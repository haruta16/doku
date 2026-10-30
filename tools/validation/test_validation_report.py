"""归档摘要只汇总实际证据；失败、未收集诊断和缺失文件不能变成零错误。"""
from pathlib import Path
import json
import hashlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import validation_report as archive


class ValidationReportTests(unittest.TestCase):
    def _report(self, root, steps, **overrides):
        (root / "inputs.json").write_text(json.dumps({"scripts/example.gd": "abc"}))
        value = {"ok": True, "suite": "all", "planned": len(steps), "executed": len(steps), "passed": len(steps),
                 "steps": steps, "inputs": "inputs.json", "excluded": [], "not_executed": [], "interrupted": False,
                 "changed_inputs": [], **overrides}
        path = root / "report.json"
        path.write_text(json.dumps(value))
        return path

    def _group(self, root, name, records, *, text="", ok=True):
        (root / (name + ".log")).write_text(text)
        (root / (name + "-report.json")).write_text(json.dumps(records))
        # 故意使用旧临时绝对路径，验证搬移证据目录后仍使用同目录保留文件。
        return {"name": name, "ok": ok, "exit_code": 0 if ok else 1, "log": "/old/" + name + ".log",
                "completion": {"ok": ok, "report": "/old/" + name + "-report.json"}}

    def _record(self, script="res://test.gd", checks=4, failures=0, **fields):
        return {"command": ["godot", "--headless", "--script", script], "ok": failures == 0, "exit_code": int(failures > 0),
                "completion": {"ok": failures == 0, "checks": checks, "failures": failures},
                "unexpected_errors": [], "environment_errors": [], "expected_test_errors": [],
                "shutdown_errors": [], "known_shutdown_errors": [], **fields}

    def test_windows_artifact_paths_resolve_inside_relocated_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            step = self._group(root, "framework", [self._record()])
            step["log"] = r"C:\old\evidence\framework.log"
            step["completion"]["report"] = r"C:\old\evidence\framework-report.json"
            summary = archive.build_summary(self._report(root, [step], inputs=r"C:\old\evidence\inputs.json"))
            self.assertTrue(summary["ok"], summary["evidence_issues"])
            self.assertEqual(summary["inputs"]["artifact"], "inputs.json")
            self.assertEqual(summary["groups"][0]["counts"]["counted_checks"], 4)

    def test_counts_diagnostics_and_baseline_sources_are_preserved_without_double_counting(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            warning = "WARNING: ObjectDB instances leaked at exit."
            record = self._record(checks=7, shutdown_errors=[warning], known_shutdown_errors=[warning],
                                  environment_errors=["ERROR: known environment"], shutdown_evidence=["baseline.json", "log_sha256=123"],
                                  shutdown_baseline_environment={"applicable": True, "reason": "matched"})
            records = {"ok": True, "branches": [{"mode": "debug", "ok": True, "steps": [record]},
                                                  {"mode": "simulated_release", "ok": True, "steps": [self._record(checks=9)]}]}
            step = self._group(root, "development", records, text="Godot Engine v4.6.1.stable.custom_build.123 - https://godotengine.org\n")
            summary = archive.build_summary(self._report(root, [step]))
            self.assertTrue(summary["ok"])
            self.assertEqual(summary["groups"][0]["counts"]["counted_checks"], 16)
            self.assertEqual(summary["groups"][0]["counts"]["script_processes"], 2)
            self.assertEqual(summary["diagnostics"]["unknown_count"], 0)
            self.assertEqual(summary["diagnostics"]["counts"]["shutdown_errors"], 1)
            self.assertEqual(summary["diagnostics"]["counts"]["known_shutdown_errors"], 1)
            source = summary["diagnostics"]["sources"][0]
            self.assertEqual(source["pointer"], "/branches/0/steps/0")
            self.assertEqual(source["shutdown_evidence"], record["shutdown_evidence"])
            self.assertTrue(source["shutdown_baseline_environment"]["applicable"])
            self.assertEqual(len(summary["known_warnings"]), 2)
            self.assertEqual(summary["environment"]["engine"]["version"], "4.6.1.stable.custom_build.123")

    def test_absent_publication_diagnostics_are_unknown_not_zero(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = {"command": ["python", "build_release.py", "--godot", "godot"], "ok": True, "exit_code": 0, "case": "catalog"}
            step = self._group(root, "publication", {"ok": True, "product_publication_checks": [record]})
            summary = archive.build_summary(self._report(root, [step]))
            self.assertTrue(summary["ok"])
            self.assertEqual(summary["groups"][0]["counts"]["cases"], 1)
            self.assertIsNone(summary["diagnostics"]["unknown_count"])
            self.assertEqual(summary["diagnostics"]["observed_unknown_count"], 0)
            self.assertEqual(summary["diagnostics"]["unclassified_sources"][0]["pointer"], "/product_publication_checks/0")

    def test_explicit_classification_marker_proves_zero_without_empty_category_arrays(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = {"command": ["godot", "--script", "res://test.gd"], "ok": True, "exit_code": 0,
                      "completion": {"checks": 3, "failures": 0}, "diagnostics_classified": True}
            step = self._group(root, "framework", [record])
            summary = archive.build_summary(self._report(root, [step]))
            self.assertTrue(summary["diagnostics"]["classification_complete"])
            self.assertEqual(summary["diagnostics"]["unknown_count"], 0)
            self.assertTrue(summary["diagnostics"]["sources"][0]["diagnostics_classified"])

    def test_pck_failure_and_diagnostics_survive_filtering_and_traceback_reprint(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            message = "ERROR: unexpected proof error"
            log = ('PCK_ENGINE_DIAGNOSTICS=' + json.dumps({"unexpected_errors": [message]}) + '\n' + message + '\n'
                   'EXPORTED_CONTENT_PROOF checks=7 failures=1\nTraceback (most recent call last):\n'
                   'EXPORTED_CONTENT_PROOF checks=7 failures=1\n')
            (root / "pck.log").write_text(log)
            step = {"name": "pck", "ok": True, "log": "pck.log", "completion": {"ok": True}}
            summary = archive.build_summary(self._report(root, [step]))
            self.assertFalse(summary["ok"])
            self.assertEqual(summary["groups"][0]["counts"]["counted_checks"], 7)
            self.assertEqual(summary["groups"][0]["counts"]["cases"], 1)
            self.assertEqual(summary["groups"][0]["counts"]["check_failures"], 1)
            self.assertEqual(summary["diagnostics"]["observed_unknown_count"], 1)
            self.assertEqual(summary["diagnostics"]["counts"]["unclassified_errors"], 0)

    def test_unclassified_pck_script_error_cannot_disappear(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "pck.log").write_text("SCRIPT ERROR: stopped before completion\n")
            step = {"name": "pck", "ok": False, "log": "pck.log", "completion": {"ok": False}}
            summary = archive.build_summary(self._report(root, [step], ok=False))
            self.assertFalse(summary["ok"])
            self.assertEqual(summary["diagnostics"]["observed_unknown_count"], 1)
            self.assertEqual(summary["diagnostics"]["sources"][0]["line"], 1)
            self.assertIn("missing_pck_proof_counts", [item["error"] for item in summary["evidence_issues"]])

    def test_interruption_python_failures_and_skip_scope_remain_visible(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "python.log").write_text("Ran 5 tests in 0.1s\nFAILED (failures=1, errors=1, skipped=2)\n")
            step = {"name": "python", "ok": False, "error": "interrupted", "log": "python.log"}
            summary = archive.build_summary(self._report(root, [step], ok=False, interrupted=True, planned=3,
                                                        not_executed=["framework", "content"], excluded=["pck"], changed_inputs=["source.gd"]))
            self.assertFalse(summary["ok"])
            self.assertEqual(summary["groups"][0]["python"], {"tests": 5, "executed": 3, "skipped": 2, "failures": 1, "errors": 1})
            self.assertEqual(summary["scope"]["not_executed"], ["framework", "content"])
            self.assertEqual(summary["scope"]["changed_inputs"], ["source.gd"])

    def test_missing_empty_and_changed_artifacts_never_become_complete_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            summary = archive.build_summary(self._report(root, []))
            self.assertFalse(summary["ok"])
            step = {"name": "framework", "ok": True, "log": "missing.log", "completion": {"report": "missing.json"}}
            self.assertFalse(archive.build_summary(self._report(root, [step]))["ok"])
            step = self._group(root, "framework", [self._record()])
            step["completion"]["sha256"] = "wrong"
            summary = archive.build_summary(self._report(root, [step]))
            self.assertFalse(summary["ok"])
            self.assertIn("hash_mismatch", [item["error"] for item in summary["evidence_issues"]])

    def test_declared_group_counts_cannot_hide_missing_or_failed_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "architecture.log").write_text("ARCHITECTURE_OK: fixture\n")
            step = {"name": "architecture", "ok": True, "log": "architecture.log"}
            for inconsistent in ({"planned": 2}, {"executed": 2}, {"passed": 0}, {"passed": True}, {"interrupted": True}):
                summary = archive.build_summary(self._report(root, [step], **inconsistent))
                self.assertFalse(summary["ok"], inconsistent)
                self.assertIn("inconsistent_group_counts_or_status", [item["error"] for item in summary["evidence_issues"]])

    def test_inputs_are_bound_when_hash_is_recorded_and_legacy_absence_is_explicit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "architecture.log").write_text("ARCHITECTURE_OK: fixture\n")
            step = {"name": "architecture", "ok": True, "log": "architecture.log"}
            path = self._report(root, [step])
            self.assertEqual(archive.build_summary(path)["inputs"]["hash_binding"], "not_recorded")
            value = json.loads(path.read_text())
            value["inputs_sha256"] = hashlib.sha256((root / "inputs.json").read_bytes()).hexdigest()
            path.write_text(json.dumps(value))
            self.assertEqual(archive.build_summary(path)["inputs"]["hash_binding"], "matched")
            (root / "inputs.json").write_text('{"different": "input"}')
            summary = archive.build_summary(path)
            self.assertFalse(summary["ok"])
            self.assertEqual(summary["inputs"]["hash_binding"], "mismatch")

    def test_environment_probe_records_actual_output_and_unavailable_engine(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = subprocess.CompletedProcess([], 0, "4.6.1.stable.custom_build.real\n", "")
            with patch.object(archive.subprocess, "run", return_value=result) as run, patch.object(archive.platform, "platform", return_value="fixture-platform"):
                captured = archive.capture_environment("/isolated/godot", root)
            self.assertEqual(captured["engine"]["version"], "4.6.1.stable.custom_build.real")
            self.assertEqual(run.call_args.args[0], ["/isolated/godot", "--version"])
            self.assertEqual(run.call_args.kwargs["cwd"], root)
            with patch.object(archive.subprocess, "run", side_effect=FileNotFoundError("missing engine")), patch.object(archive.platform, "platform", return_value="fixture-platform"):
                missing = archive.capture_environment("/missing/godot", root)
            self.assertIsNone(missing["engine"]["version"])
            self.assertIn("missing engine", missing["engine"]["error"])

    def test_real_retained_report_counts_can_be_rebuilt_without_running_engine(self):
        # 用独立历史报告的真实记录验证嵌套汇总，不把手写的旧摘要当新输入。
        fixture = json.loads((ROOT / "docs/validation/review-followup-content-report.json").read_text())
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            records = fixture["steps"]
            self.assertTrue(records)
            step = self._group(root, "content", {"ok": fixture["ok"], "steps": records})
            summary = archive.build_summary(self._report(root, [step]))
            actual = list(archive._records({"steps": records}))
            self.assertEqual(summary["groups"][0]["counts"]["reported_processes"], len(actual))
            self.assertEqual(summary["groups"][0]["counts"]["script_processes"], sum("--script" in value["command"] for _, value in actual))
            self.assertIsNone(summary["diagnostics"]["unknown_count"])
            destination = archive.write_summary(root / "report.json")
            self.assertEqual(destination.name, "summary.json")
            self.assertEqual(json.loads(destination.read_text())["inputs"]["count"], 1)


if __name__ == "__main__":
    unittest.main()
