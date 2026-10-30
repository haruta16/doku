"""验证编排必须保留失败、范围和缺失证据，不能把未执行误记成通过。"""
from pathlib import Path
import contextlib
import io
import json
import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import verify


class VerifyTests(unittest.TestCase):
    def test_fingerprints_include_native_root_configs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            names = ["unikit_config.tres", "lxauth_android_config.tres"]
            for name in names:
                (root / name).write_text("[resource]\nvalue = 1\n")
            with patch.object(verify, "ROOT", root):
                before = verify.fingerprints()
                self.assertEqual(set(names), set(before))
                for name in names:
                    (root / name).write_text("[resource]\nvalue = 2\n")
                after = verify.fingerprints()
            self.assertEqual(set(names), {name for name in before if before[name] != after[name]})

    def _step(self, name):
        return next(step for step in verify.steps_for("all", "engine", Path("evidence")) if step["name"] == name)

    def _records(self, step):
        commands = [["engine", "--script", script] for script in step.get("expected_scripts", [])]
        if step.get("require_import"):
            commands.insert(0, ["engine", "--editor", "--import"])
        if step.get("smoke"):
            commands.append(["engine", "--quit-after", "600"])
        records = [{"command": command, "ok": True, "exit_code": 0, "completion": {"ok": True}} for command in commands]
        for _ in range(step.get("expected_rejections", 0)):
            records.append({"command": ["publisher"], "ok": True, "exit_code": 1, "expected_rejection": True})
        return records

    def test_all_includes_external_suites_and_quick_is_explicit_subset(self):
        all_steps = verify.steps_for("all", "engine with spaces", Path("evidence"))
        names = [step["name"] for step in all_steps]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual({"content", "publication", "spine", "pck"}, set(names) - {step["name"] for step in verify.steps_for("framework", "engine", Path("evidence"))})
        self.assertEqual([step["name"] for step in verify.steps_for("quick", "engine", Path("evidence"))], ["architecture", "python"])
        for step in all_steps[2:]:
            self.assertIn("engine with spaces", step["command"])
        self.assertIn("--test", next(step["command"] for step in all_steps if step["name"] == "block"))

    def test_no_report_or_empty_report_never_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            step = {"name": "framework", "pointer": "VALIDATION_WORKSPACE"}
            self.assertFalse(verify.collect_completion(step, "", output)["ok"])
            (output / "report.json").write_text("[]")
            self.assertFalse(verify.collect_completion(step, f"VALIDATION_WORKSPACE={output}\n", output)["ok"])
        self.assertFalse(verify.report_passed([{"ok": True}, {"ok": False}], self._step("block")))
        self.assertFalse(verify.report_passed({"ok": "true"}, self._step("content")))

    def test_project_pointer_retains_actual_child_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "evidence"
            output.mkdir()
            step = self._step("block")
            (Path(temporary) / "report.json").write_text(json.dumps(self._records(step)))
            result = verify.collect_completion(step,
                                               f"BLOCK_EXAMPLE_PROJECT={temporary}/project\n", output)
            self.assertTrue(result["ok"])
            self.assertEqual(len(result["sha256"]), 64)
            self.assertTrue((output / "block-report.json").is_file())

    def test_completion_rejects_empty_python_and_incomplete_pck(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            for text in ["", "Ran 0 tests in 0.01s\nOK\n", "Ran 2 tests in 0.01s\nFAILED\n"]:
                self.assertFalse(verify.collect_completion({"completion": "python"}, text, output)["ok"])
            self.assertTrue(verify.collect_completion({"completion": "python"}, "Ran 2 tests in 0.01s\n\nOK\n", output)["ok"])
            self.assertFalse(verify.collect_completion({"completion": "pck"}, "EXPORTED_CONTENT_PROOF failures=0\n", output)["ok"])
            self.assertTrue(verify.collect_completion({"completion": "pck"}, "PCK_PROOF_OK cases=2\n", output)["ok"])

    def test_nonzero_exit_cannot_be_hidden_by_success_marker(self):
        with tempfile.TemporaryDirectory() as temporary:
            step = {"name": "probe", "completion": "architecture", "command": [sys.executable, "-c", "print('ARCHITECTURE_OK: probe'); raise SystemExit(3)"]}
            result = verify.run_step(step, Path(temporary), 10, "unused")
            self.assertFalse(result["ok"])
            self.assertEqual(result["exit_code"], 3)

    def test_timeout_is_failure_and_stops_child_process(self):
        with tempfile.TemporaryDirectory() as temporary:
            step = {"name": "probe", "completion": "architecture", "command": [sys.executable, "-c", "import time; time.sleep(30)"]}
            result = verify.run_step(step, Path(temporary), 0.1, "unused")
            self.assertFalse(result["ok"])
            self.assertEqual(result["error"], "timeout")

    def test_report_scope_requires_every_framework_script_and_smoke(self):
        step = self._step("framework")
        from run_validation import suite_scripts
        self.assertEqual(step["expected_scripts"], suite_scripts(verify.ROOT, "framework"))
        records = self._records(step)
        self.assertTrue(verify.report_passed(records, step))
        self.assertFalse(verify.report_passed(records[:-1], step))  # missing smoke
        self.assertFalse(verify.report_passed(records[:1] + records[2:], step))  # missing test
        self.assertFalse(verify.report_passed(records + [records[1]], step))  # duplicate cannot replace a test
        records[1]["completion"] = {"ok": False}
        self.assertFalse(verify.report_passed(records, step))

    def test_external_reports_cannot_pass_with_empty_or_partial_groups(self):
        for name in ("content", "spine", "framework_boundary"):
            step = self._step(name)
            records = self._records(step)
            field = step["report_field"]
            self.assertTrue(verify.report_passed({"ok": True, field: records}, step))
            for incomplete in ({"ok": True}, {"ok": True, field: []}, {"ok": True, field: records[:-1]}):
                self.assertFalse(verify.report_passed(incomplete, step), name)
        step = self._step("content")
        no_bootstrap = [record for record in self._records(step) if "res://bootstrap-test.gd" not in record["command"]]
        self.assertFalse(verify.report_passed({"ok": True, "steps": no_bootstrap}, step))

    def test_development_requires_both_nonempty_branches(self):
        step = self._step("development")
        branches = [{"mode": mode, "ok": True, "steps": self._records(step)} for mode in step["branches"]]
        self.assertTrue(verify.report_passed({"ok": True, "branches": branches}, step))
        self.assertFalse(verify.report_passed({"ok": True, "branches": branches[:1]}, step))
        branches[1]["steps"] = []
        self.assertFalse(verify.report_passed({"ok": True, "branches": branches}, step))
        branches[1]["mode"] = []
        self.assertFalse(verify.report_passed({"ok": True, "branches": branches}, step))

    def test_publication_requires_each_case_and_real_success_or_rejection(self):
        step = self._step("publication")
        records = [{"case": name, "ok": True, "exit_code": 0, "artifact_exists": True} for name in step["expected_cases"]]
        self.assertTrue(verify.report_passed({"ok": True, step["report_field"]: records}, step))
        self.assertFalse(verify.report_passed({"ok": True, step["report_field"]: records[:-1]}, step))
        records[0]["expected_rejection"] = "expected reason"
        self.assertFalse(verify.report_passed({"ok": True, step["report_field"]: records}, step))
        records[0].update(exit_code=1, artifact_exists=False)
        self.assertTrue(verify.report_passed({"ok": True, step["report_field"]: records}, step))
        records[0]["case"] = []
        self.assertFalse(verify.report_passed({"ok": True, step["report_field"]: records}, step))

    def test_publication_accepts_all_22_actual_runner_cases_and_rejects_missing_lk_cases(self):
        # 旧验收报告独立记录了完整的 22 个病例；为它们构造现行 runner 的证据字段。
        # 不能从 verify 自己的清单生成全部病例，否则清单漏项时正例也会一起漏项。
        report = json.loads((ROOT / "docs/validation/review-followup-content-report.json").read_text(encoding="utf-8"))
        cases = [record["case"] for record in report["product_publication_checks"]]
        self.assertEqual(len(cases), 22)
        self.assertEqual(len(set(cases)), 22)
        step = self._step("publication")
        records = [{"case": case, "ok": True, "exit_code": 0, "artifact_exists": True} for case in cases]
        self.assertTrue(verify.report_passed({"ok": True, step["report_field"]: records}, step))
        for missing in ("lk-invalid-date", "lk-invalid-label"):
            self.assertIn(missing, cases)
            partial = [record for record in records if record["case"] != missing]
            self.assertFalse(verify.report_passed({"ok": True, step["report_field"]: partial}, step))

    def test_quick_python_reports_skips_and_requires_some_execution(self):
        step = next(step for step in verify.steps_for("quick", "unused", Path("evidence")) if step["name"] == "python")
        with tempfile.TemporaryDirectory() as temporary:
            completed = verify.collect_completion(step, "Ran 12 tests in 0.1s\n\nOK (skipped=2)\n", Path(temporary))
            self.assertTrue(completed["ok"])
            self.assertEqual((completed["tests"], completed["executed"], completed["skipped"]), (12, 10, 2))
            for text in ("Ran 2 tests in 0.1s\nOK (skipped=2)\n", "Ran 0 tests in 0.1s\nOK\n",
                         "Ran 2 tests in 0.1s\nOK (skipped=3)\n", "Ran 12 tests in 0.1s\nFAILED (skipped=2)\n"):
                self.assertFalse(verify.collect_completion(step, text, Path(temporary))["ok"])

    def test_framework_and_all_python_reject_any_skipped_test(self):
        with tempfile.TemporaryDirectory() as temporary:
            for suite in ("framework", "all"):
                step = next(step for step in verify.steps_for(suite, "unused", Path("evidence")) if step["name"] == "python")
                completed = verify.collect_completion(step, "Ran 12 tests in 0.1s\nOK (skipped=2)\n", Path(temporary))
                self.assertFalse(completed["ok"])
                self.assertEqual(completed["skipped"], 2)
                self.assertTrue(verify.collect_completion(step, "Ran 12 tests in 0.1s\nOK\n", Path(temporary))["ok"])

    def test_windows_cleanup_failure_or_timeout_has_bounded_fallback(self):
        for result in (subprocess.CompletedProcess([], 1), subprocess.TimeoutExpired("taskkill", 15)):
            process = Mock(pid=123)
            process.wait.side_effect = [subprocess.TimeoutExpired("child", 5), 0]
            with patch.object(verify.os, "name", "nt"), patch.object(verify.subprocess, "run") as taskkill:
                if isinstance(result, Exception):
                    taskkill.side_effect = result
                else:
                    taskkill.return_value = result
                errors = verify.stop_process(process)
            self.assertTrue(errors)
            process.kill.assert_called_once_with()
            self.assertTrue(all(call.kwargs.get("timeout") == 5 for call in process.wait.call_args_list))
            self.assertEqual(taskkill.call_args.kwargs["timeout"], 15)

    def test_cleanup_reports_unreaped_process_without_infinite_wait(self):
        process = Mock(pid=123)
        process.wait.side_effect = subprocess.TimeoutExpired("child", 5)
        with patch.object(verify.os, "name", "nt"), patch.object(verify.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
            errors = verify.stop_process(process)
        self.assertEqual(process.wait.call_count, 2)
        self.assertTrue(any(error.startswith("process_cleanup_failed:") for error in errors))

    def test_run_step_interrupt_retains_failed_step_log_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            step = {"name": "probe", "completion": "architecture", "command": ["unused"]}
            process = Mock()
            process.wait.side_effect = KeyboardInterrupt()
            process.poll.return_value = -9
            with patch.object(verify.subprocess, "Popen", return_value=process), patch.object(verify, "stop_process", return_value=[]) as stop:
                result = verify.run_step(step, Path(temporary), 10, "unused")
            self.assertFalse(result["ok"])
            self.assertEqual(result["error"], "interrupted")
            self.assertTrue(Path(result["log"]).is_file())
            self.assertEqual(len(result["log_sha256"]), 64)
            stop.assert_called_once_with(process)

    def test_output_inside_input_tree_is_rejected_before_writing(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            for directory in verify.INPUT_DIRECTORIES:
                output = source / directory / "evidence"
                with patch.object(verify, "ROOT", source), \
                     patch.object(sys, "argv", ["verify", "--suite", "quick", "--output", str(output)]), \
                     patch.object(verify, "run_step") as run, contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as error:
                        verify.main()
                self.assertEqual(error.exception.code, 2)
                self.assertFalse(output.exists())
                run.assert_not_called()

    def test_fingerprints_include_actual_root_data_and_the_fixed_report_fixture(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            fixture = source / "docs/validation/review-followup-content-report.json"
            fixture.parent.mkdir(parents=True)
            fixture.write_text("fixture")
            (fixture.parent / "unrelated-history.json").write_text("not an input")
            (source / "icudt_godot.dat").write_bytes(b"data")
            with patch.object(verify, "ROOT", source):
                captured = verify.fingerprints()
            self.assertEqual(set(captured), {"icudt_godot.dat", "docs/validation/review-followup-content-report.json"})

    def test_quick_resolves_existing_relative_engine_before_version_probe(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine = root / "version-engine"
            engine.write_text("#!" + sys.executable + "\nprint('4.6.1.stable.fixture')\n")
            engine.chmod(0o700)
            output = root / "out"
            relative = os.path.relpath(engine, Path.cwd())
            with patch.object(sys, "argv", ["verify", "--suite", "quick", "--godot", relative, "--output", str(output)]), \
                 patch.object(verify, "fingerprints", side_effect=[{}, {}]), \
                 patch.object(verify, "run_step", side_effect=[
                     {"name": "architecture", "ok": False, "log": "a.log"},
                     {"name": "python", "ok": False, "log": "b.log"}]), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(verify.main(), 1)
            captured = json.loads((output / "report.json").read_text())["environment"]["engine"]
            self.assertEqual(captured["path"], str(engine.resolve()))
            self.assertEqual(captured["version"], "4.6.1.stable.fixture")
            self.assertEqual(captured["exit_code"], 0)
            self.assertEqual(captured["error"], "")

    def _main_report(self, output, steps, fingerprints=None):
        with patch.object(sys, "argv", ["verify", "--suite", "quick", "--output", str(output)]), \
             patch.object(verify, "fingerprints", side_effect=fingerprints or [{}, {}]), \
             patch.object(verify, "run_step", side_effect=steps), contextlib.redirect_stdout(io.StringIO()):
            code = verify.main()
        return code, json.loads((output / "report.json").read_text())

    def test_aggregate_preserves_failure_and_excluded_scopes(self):
        with tempfile.TemporaryDirectory() as temporary:
            code, report = self._main_report(Path(temporary) / "out", [
                {"name": "architecture", "ok": False, "log": "a.log"}, {"name": "python", "ok": True, "log": "b.log"}])
            self.assertEqual(code, 1)
            self.assertEqual((report["planned"], report["executed"], report["passed"]), (2, 2, 1))
            self.assertIn("content", report["excluded"])

    def test_input_changes_invalidate_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            code, report = self._main_report(Path(temporary) / "out", [
                {"name": "architecture", "ok": True, "log": "a.log"}, {"name": "python", "ok": True, "log": "b.log"}],
                [{"source.gd": "old"}, {"source.gd": "new"}])
            self.assertEqual(code, 1)
            self.assertEqual(report["changed_inputs"], ["source.gd"])

    def test_archive_evidence_failure_downgrades_verdict_and_exit_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "out"
            code, report = self._main_report(output, [
                {"name": "architecture", "ok": True, "log": "missing-a.log"},
                {"name": "python", "ok": True, "log": "missing-b.log"}])
            self.assertEqual(code, 1)
            self.assertFalse(report["ok"])
            self.assertEqual(report["archive_validation"]["error"], "summary_validation_failed")
            summary = json.loads((output / "summary.json").read_text())
            self.assertFalse(summary["ok"])
            self.assertFalse(summary["reported_ok"])
            self.assertEqual(summary["source_report_sha256"], hashlib.sha256((output / "report.json").read_bytes()).hexdigest())
            self.assertEqual(summary["inputs"]["hash_binding"], "matched")

    def test_interrupt_reports_not_executed(self):
        with tempfile.TemporaryDirectory() as temporary:
            code, report = self._main_report(Path(temporary) / "out", [KeyboardInterrupt()])
            self.assertEqual(code, 1)
            self.assertTrue(report["interrupted"])
            self.assertEqual(report["executed"], 1)
            self.assertEqual(report["steps"][0]["error"], "interrupted")
            self.assertEqual(report["steps"][0]["log"], str((Path(temporary) / "out" / "architecture.log").resolve()))
            self.assertEqual(report["not_executed"], ["python"])
            summary = json.loads((Path(temporary) / "out" / "summary.json").read_text())
            self.assertFalse(summary["ok"])
            self.assertTrue(summary["scope"]["interrupted"])
            self.assertEqual(summary["scope"]["not_executed"], ["python"])

    def test_returned_interrupt_stops_remaining_steps(self):
        with tempfile.TemporaryDirectory() as temporary:
            code, report = self._main_report(Path(temporary) / "out", [
                {"name": "architecture", "ok": False, "error": "interrupted", "log": "a.log"}])
            self.assertEqual(code, 1)
            self.assertTrue(report["interrupted"])
            self.assertEqual((report["executed"], report["passed"], report["not_executed"]), (1, 0, ["python"]))


if __name__ == "__main__":
    unittest.main()
