"""Godot 返回 0 也可能报告引擎错误，验收不能仅依赖退出码或断言摘要。"""
from pathlib import Path
import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_validation import classify_engine_errors, completion_contract, has_reported_failures, import_project, main, prepare, run, suite_scripts

KNOWN_ENGINE_BANNER = "Godot Engine v4.6.1.stable.custom_build.14d19694e (2026-02-16 15:13:51 UTC) - https://godotengine.org\n"


class ValidationRunnerTests(unittest.TestCase):
    def classify_with_environment(self, output, args, *, system="Darwin", machine="arm64", banner=KNOWN_ENGINE_BANNER):
        with patch("run_validation.platform.system", return_value=system), patch("run_validation.platform.machine", return_value=machine):
            return classify_engine_errors(banner + output, args)

    def test_custom_font_import_restores_full_configuration_before_second_pass(self):
        original = 'config_version=5\n[gui]\ntheme/custom_font="uid://sample"\nother=true\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            config = project / "project.godot"
            config.write_text(original)
            observed = []
            def imported(*args):
                observed.append(config.read_text())
                return {"ok": True}
            with patch("run_validation.run", side_effect=imported):
                results = import_project("godot", project, project / "import.log", 1)
            self.assertEqual(len(results), 2)
            self.assertNotIn("theme/custom_font", observed[0])
            self.assertIn("other=true", observed[0])
            self.assertEqual(observed[1], original)
            self.assertEqual(config.read_text(), original)

    def test_failed_or_interrupted_font_bootstrap_restores_configuration(self):
        original = 'config_version=5\n[gui]\ntheme/custom_font="res://font.ttf"\n'
        for failure in ({"ok": False, "error": "timeout"}, RuntimeError("engine unavailable")):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                project = Path(directory)
                config = project / "project.godot"
                config.write_text(original)
                with patch("run_validation.run", side_effect=[failure]) as mocked:
                    if isinstance(failure, Exception):
                        with self.assertRaises(RuntimeError):
                            import_project("godot", project, project / "import.log", 1)
                    else:
                        results = import_project("godot", project, project / "import.log", 1)
                        self.assertEqual(len(results), 1)
                        self.assertFalse(results[0]["ok"])
                self.assertEqual(mocked.call_count, 1)
                self.assertEqual(config.read_text(), original)

    def test_no_custom_font_uses_one_unmodified_import(self):
        for original in ('config_version=5\n', 'config_version=5\n[gui]\ntheme/custom_font=""\n'):
            with self.subTest(config=original), tempfile.TemporaryDirectory() as directory:
                project = Path(directory)
                config = project / "project.godot"
                config.write_text(original)
                with patch("run_validation.run", return_value={"ok": True}) as mocked:
                    self.assertEqual(len(import_project("godot", project, project / "import.log", 1)), 1)
                self.assertEqual(mocked.call_count, 1)
                self.assertEqual(config.read_text(), original)

    def test_product_tree_is_copied_and_all_product_save_paths_are_isolated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / "source", root / "target"
            product = source / "products/meowdoku/app/state.gd"
            product.parent.mkdir(parents=True)
            original = 'extends Node\nconst SAVE = "user://save.cfg"\nfunc data_dir(): return OS.get_user_data_dir()\n'
            product.write_text(original)
            scene = source / "products/meowdoku/launcher.tscn"
            scene.write_text('[gd_scene format=3]\n[node name="Main" type="Node"]\n')
            (source / "project.godot").write_text('config_version=5\n[application]\nrun/main_scene="res://products/meowdoku/launcher.tscn"\n')
            project = prepare(source, target)
            copied = (project / product.relative_to(source)).read_text()
            self.assertNotIn("user://", copied)
            self.assertNotIn("OS.get_user_data_dir()", copied)
            self.assertIn((target / "userdata").as_posix(), copied)
            self.assertEqual(product.read_text(), original)
            self.assertEqual((project / scene.relative_to(source)).read_text(), scene.read_text())

    def test_gameplay_suite_includes_daily_lifecycle(self):
        root = Path(__file__).resolve().parents[2]
        daily = "res://tools/validation/test_daily_win_lifecycle.gd"
        self.assertIn(daily, suite_scripts(root, "gameplay"))
        self.assertIn(daily, suite_scripts(root, "framework"))
        self.assertNotIn(daily, suite_scripts(root, "storage"))
        self.assertNotIn(daily, suite_scripts(root, "content"))

    def test_serious_engine_error_rejects_zero_exit_code(self):
        output = "FIXTURE TESTS: 1 assertions, 0 failures\nERROR: Stack underflow! (Engine Bug)\n"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with patch("run_validation.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                result = run("godot", path, path / "run.log", ["--script", "res://tools/validation/test_fixture.gd"], 1)
        self.assertFalse(result["ok"])
        self.assertIn("Stack underflow!", result["unexpected_errors"][0])

    def test_missing_resource_and_autoload_are_failures(self):
        messages = "ERROR: Failed loading resource: res://missing.gd.\nERROR: Failed to create an autoload, can't load from UID or path: res://missing.gd.\n"
        self.assertEqual(len(classify_engine_errors(messages, ["--editor", "--import"])["unexpected_errors"]), 2)

    def test_storage_injection_is_narrow_and_test_only(self):
        args = ["--script", "res://tools/validation/test_storage.gd"]
        for module in ("GameState", "AwardManager", "UniKitManager"):
            with self.subTest(module=module):
                message = f'ERROR: [{module}] 保存未完成: {{ "error": "write_failed", "detail": "注入替换前中断" }}'
                self.assertIn("expected_test_errors", classify_engine_errors(message, args))
                self.assertIn("unexpected_errors", classify_engine_errors(message, []))
                self.assertIn("unexpected_errors", classify_engine_errors(message.replace("注入替换前中断", "磁盘不可写"), args))
                self.assertIn("unexpected_errors", classify_engine_errors(message.replace("write_failed", "invalid_state"), args))

    def test_tutorial_failure_is_scoped_to_its_negative_test(self):
        message = "ERROR: TutorialPage: 教学棋盘未能完整创建"
        self.assertIn("expected_test_errors", classify_engine_errors(message, ["--script", "res://tools/validation/test_content_tutorial_boot_failure.gd"]))
        self.assertIn("unexpected_errors", classify_engine_errors(message, ["--script", "res://tools/validation/test_content_tutorial.gd"]))

    def test_environment_requires_the_known_call_site(self):
        message = '\x1b[31mERROR: Condition "ret != noErr" is true. Returning: ""\x1b[0m\n   at: get_system_ca_certificates (platform/macos/os_macos.mm:1014)'
        self.assertIn("environment_errors", classify_engine_errors(message, []))
        self.assertIn("unexpected_errors", classify_engine_errors(message.replace("get_system_ca_certificates", "another_function"), []))

    def test_shutdown_diagnostics_are_retained_separately(self):
        message = "ERROR: 2 resources still in use at exit (run with --verbose for details)."
        result = classify_engine_errors(message, ["--quit-after", "600"])
        self.assertEqual(result["shutdown_errors"], [message])
        self.assertEqual(result["unexpected_errors"], [message])

    def test_lifecycle_shutdown_contract_rejects_resource_and_instance_leaks(self):
        args = ["--script", "res://tools/validation/test_game_operation_lifecycle.gd"]
        for message in (
            "ERROR: 4 resources still in use at exit (run with --verbose for details).",
            "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).",
        ):
            result = classify_engine_errors(message, args)
            self.assertEqual(result["shutdown_errors"], [message])
            self.assertEqual(result["unexpected_errors"], [message])
            self.assertIn("unexpected_errors", classify_engine_errors(message, ["--quit-after", "600"]))
        self.assertFalse(classify_engine_errors("GAME OPERATION LIFECYCLE TESTS: 99 assertions, 0 failures", args))

    def test_isolated_ui_directory_error_does_not_allow_product_save_errors(self):
        message = "ERROR: Could not create directory: '/Users/test/Library/Application Support/Godot/app_userdata/UI Framework Tests'.\n   at: make_dir_recursive (core/io/dir_access.cpp:178)"
        self.assertIn("environment_errors", classify_engine_errors(message, ["--editor", "--import"]))
        self.assertIn("environment_errors", classify_engine_errors(message, ["--script", "res://tools/validation/test_ui_framework.gd"]))
        self.assertIn("unexpected_errors", classify_engine_errors(message, ["--script", "res://tools/validation/test_storage.gd"]))
        self.assertIn("unexpected_errors", classify_engine_errors(message.replace("UI Framework Tests", "Meowdoku"), ["--editor", "--import"]))

    def test_publisher_environment_exception_is_scoped_to_known_script(self):
        message = "ERROR: Error attempting to create data dir: /Users/test/Library/Application Support/Godot/app_userdata/DokuContentValidation.\n   at: ensure_user_data_dir (core/os/os.cpp:437)"
        self.assertIn("environment_errors", classify_engine_errors(message, ["--script", "res://tools/content/validate_product.gd"]))
        self.assertIn("unexpected_errors", classify_engine_errors(message, ["--script", "res://production.gd"]))
        self.assertIn("unexpected_errors", classify_engine_errors(message.replace("ensure_user_data_dir", "save_game"), ["--script", "res://tools/content/validate_product.gd"]))

    def test_framework_consumer_environment_exception_does_not_hide_product_errors(self):
        args = ["--script", "res://tools/validation/fixtures/framework_consumer.gd"]
        message = "ERROR: Error attempting to create data dir: /Users/test/Library/Application Support/Godot/app_userdata/Framework Boundary Tests.\n   at: ensure_user_data_dir (core/os/os.cpp:437)"
        self.assertIn("environment_errors", classify_engine_errors(message, args))
        self.assertIn("unexpected_errors", classify_engine_errors(message.replace("Framework Boundary Tests", "Meowdoku"), args))
        self.assertIn("unexpected_errors", classify_engine_errors(message, ["--script", "res://tools/validation/test_storage.gd"]))
        self.assertIn("unexpected_errors", classify_engine_errors(message.replace("ensure_user_data_dir", "save_game"), args))
        for leaked in ("ERROR: 2 resources still in use at exit (run with --verbose for details).", "WARNING: ObjectDB instances leaked at exit (run with --verbose for details)."):
            self.assertIn("unexpected_errors", classify_engine_errors(leaked, args))

    def test_failure_summary_counts_only_failure_fields(self):
        for message in ("checks=18 failures=0", "15 assertions, 0 failures", "2700 baseline size decisions"):
            self.assertFalse(has_reported_failures(message), message)
        for message in ("checks=18 failures=1", "15 assertions, 2 failures", "failures = 3"):
            self.assertTrue(has_reported_failures(message), message)

    def test_test_completion_requires_finished_nonempty_checks(self):
        args = ["--script", "res://tools/validation/test_fixture.gd"]
        cases = [
            ("", False), ("PASS: fixture completed", False),
            ("TESTS: 0 assertions, 0 failures", False), ("checks=0 failures=0", False),
            ("TESTS: 7 assertions", False), ("TESTS: 7 assertions\n0 failures", False),
            ("TESTS: 7 assertions, 1 failures", False),
            ("TESTS: 7 assertions, 0 failures", True),
            ("CONTENT_URL_TEST checks=14 failures=0", True),
            ("PASS: legacy test checks=15 failures=0", True),
            ("TESTS: 7 assertions, 0 failures\nTESTS: 8 assertions, 0 failures", False),
        ]
        for output, expected in cases:
            with self.subTest(output=output):
                self.assertEqual(completion_contract(output, args)["ok"], expected)
                with tempfile.TemporaryDirectory() as directory:
                    path = Path(directory)
                    with patch("run_validation.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                        self.assertEqual(run("godot", path, path / "run.log", args, 1)["ok"], expected)

    def test_script_aliases_and_framework_fixture_require_completion(self):
        for script in ("res://test.gd", "res://boot-failure.gd", "res://tools/validation/fixtures/framework_consumer.gd"):
            args = ["--script", script]
            self.assertFalse(completion_contract("", args)["ok"])
            self.assertFalse(completion_contract("", args, "smoke")["ok"])
            self.assertTrue(completion_contract("TESTS: 1 assertions, 0 failures", args, "test")["ok"])

    def test_import_smoke_recovery_and_tool_contracts_are_distinct(self):
        self.assertTrue(completion_contract("", ["--editor", "--import"])["ok"])
        self.assertTrue(completion_contract("", ["--quit-after", "600"])["ok"])
        self.assertFalse(completion_contract("", ["--quit-after", "0"])["ok"])
        recovery = ["--script", "res://tools/validate_recovery.gd"]
        self.assertFalse(completion_contract("TESTS: 1 assertions, 0 failures", recovery)["ok"])
        self.assertTrue(completion_contract("VALIDATION_OK: 257 recovered scripts, 74 scenes, 75 translations, 26 level banks, 20,746 records, and 20,710 solution entries", recovery)["ok"])
        pack = ["--script", "res://pack.gd"]
        self.assertFalse(completion_contract("PACK_VALIDATED one", pack)["ok"])
        self.assertTrue(completion_contract("PACK_VALIDATED one", pack, "tool:PACK_VALIDATED")["ok"])
        self.assertFalse(completion_contract("PACK_VALIDATED", pack, "tool:PACK_VALIDATED")["ok"])
        self.assertFalse(completion_contract("PACK_VALIDATED\nunrelated log", pack, "tool:PACK_VALIDATED")["ok"])
        self.assertFalse(completion_contract("PACK_VALIDATED one", pack, "tool:PRODUCT_VALIDATED")["ok"])
        self.assertTrue(completion_contract("PRODUCT_VALIDATED: release-one", ["--script", "res://tools/content/validate_product.gd"])["ok"])
        self.assertFalse(completion_contract("anything", pack, "unrecognized")["ok"])

    def test_nonzero_process_exit_cannot_be_overridden_by_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with patch("run_validation.subprocess.run", return_value=subprocess.CompletedProcess([], 2, "TESTS: 5 assertions, 0 failures", "")):
                result = run("godot", path, path / "run.log", ["--script", "res://test.gd"], 1)
        self.assertTrue(result["completion"]["ok"])
        self.assertFalse(result["ok"])

    def test_timeout_rejects_even_complete_partial_output_and_retains_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            error = subprocess.TimeoutExpired("godot", 1, output=b"TESTS: 2 assertions, 0 failures\n", stderr="still running\n")
            with patch("run_validation.subprocess.run", side_effect=error):
                result = run("godot", path, path / "run.log", ["--script", "res://test.gd"], 1)
            self.assertFalse(result["ok"])
            self.assertEqual(result["error"], "timeout")
            self.assertEqual((path / "run.log").read_text(), "TESTS: 2 assertions, 0 failures\nstill running\n")

    def test_known_shutdown_baseline_is_script_message_and_count_specific(self):
        resource = "ERROR: 2 resources still in use at exit (run with --verbose for details)."
        objects = "WARNING: ObjectDB instances leaked at exit (run with --verbose for details)."
        args = ["--script", "res://tools/validation/test_game_page_lifecycle.gd"]
        known = self.classify_with_environment(objects + "\n" + resource, args)
        self.assertEqual(known["known_shutdown_errors"], [objects, resource])
        self.assertNotIn("unexpected_errors", known)
        self.assertTrue(any(item.startswith("log_sha256=") for item in known["shutdown_evidence"]))
        for message, command in (
            (resource.replace("2 resources", "3 resources"), args),
            (objects + "\n" + objects, args),
            (objects, ["--script", "res://tools/validation/test_new.gd"]),
            (resource, ["--editor", "--import", *args]),
        ):
            with self.subTest(message=message, command=command):
                self.assertIn("unexpected_errors", self.classify_with_environment(message, command))

    def test_shutdown_exceptions_reference_archived_log_fingerprints(self):
        root = Path(__file__).resolve().parents[2]
        ledger = json.loads((root / "tools/validation/fixtures/shutdown_diagnostics.json").read_text())
        self.assertEqual(ledger["schema"], 2)
        self.assertEqual(ledger["environment"], {"system": "Darwin", "machine": "arm64", "godot_version": "4.6.1.stable.custom_build.14d19694e"})
        for scope, baseline in ledger["baselines"].items():
            with self.subTest(scope=scope):
                self.assertTrue(baseline["diagnostics"])
                self.assertRegex(baseline["log_sha256"], r"^[0-9a-f]{64}$")
                report = (root / baseline["report"]).read_text()
                self.assertIn(baseline["log_sha256"], report)
                if scope != "product-smoke-600":
                    self.assertIn(scope, report)

    def test_smoke_baseline_does_not_allow_unrelated_projects_or_frame_counts(self):
        message = "WARNING: ObjectDB instances leaked at exit (run with --verbose for details)."
        command = ["--path", "/tmp/doku-validation-fixture/project", "--quit-after", "600"]
        self.assertNotIn("unexpected_errors", self.classify_with_environment(message, command))
        for args in (["--path", "/tmp/other/project", "--quit-after", "600"],
                     ["--path", "/tmp/doku-validation-fixture/project", "--quit-after", "60"],
                     ["--quit-after", "600"]):
            self.assertIn("unexpected_errors", self.classify_with_environment(message, args))

    def test_shutdown_exception_requires_the_actual_platform_architecture_and_engine(self):
        message = "ERROR: 2 resources still in use at exit (run with --verbose for details)."
        args = ["--script", "res://tools/validation/test_game_page_lifecycle.gd"]
        cases = [
            ("Darwin", "arm64", KNOWN_ENGINE_BANNER, "matched"),
            ("Linux", "arm64", KNOWN_ENGINE_BANNER, "environment_mismatch"),
            ("Darwin", "x86_64", KNOWN_ENGINE_BANNER, "environment_mismatch"),
            ("Darwin", "arm64", KNOWN_ENGINE_BANNER.replace("14d19694e", "otherbuild"), "environment_mismatch"),
            ("Darwin", "arm64", "", "missing_engine_version"),
            ("Darwin", "arm64", KNOWN_ENGINE_BANNER * 2, "ambiguous_engine_version"),
        ]
        for system, machine, banner, reason in cases:
            with self.subTest(system=system, machine=machine, banner=banner):
                result = self.classify_with_environment(message, args, system=system, machine=machine, banner=banner)
                environment = result["shutdown_baseline_environment"]
                self.assertEqual(environment["reason"], reason)
                self.assertEqual(environment["applicable"], reason == "matched")
                self.assertEqual(environment["observed"]["system"], system)
                self.assertEqual(environment["observed"]["machine"], machine)
                self.assertEqual(result["shutdown_errors"], [message])
                if reason == "matched":
                    self.assertEqual(result["known_shutdown_errors"], [message])
                    self.assertNotIn("unexpected_errors", result)
                else:
                    self.assertEqual(result["unexpected_errors"], [message])
                    self.assertNotIn("known_shutdown_errors", result)
                    self.assertNotIn("shutdown_evidence", result)

    def test_new_environment_without_shutdown_diagnostics_can_pass(self):
        output = "TESTS: 1 assertions, 0 failures"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with patch("run_validation.platform.system", return_value="Linux"), \
                 patch("run_validation.platform.machine", return_value="x86_64"), \
                 patch("run_validation.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                result = run("different-godot", path, path / "run.log", ["--script", "res://tools/validation/test_game_page_lifecycle.gd"], 1)
        self.assertTrue(result["ok"])
        self.assertNotIn("shutdown_baseline_environment", result)

    def test_environment_mismatch_fails_run_and_retains_rejection_details(self):
        output = (KNOWN_ENGINE_BANNER.replace("14d19694e", "otherbuild") + "TESTS: 1 assertions, 0 failures\n"
                  "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with patch("run_validation.platform.system", return_value="Darwin"), \
                 patch("run_validation.platform.machine", return_value="arm64"), \
                 patch("run_validation.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                result = run("godot", path, path / "run.log", ["--script", "res://tools/validation/test_game_page_lifecycle.gd"], 1)
        self.assertTrue(result["completion"]["ok"])
        self.assertFalse(result["ok"])
        self.assertEqual(result["shutdown_baseline_environment"]["mismatched_fields"], ["godot_version"])
        self.assertEqual(result["shutdown_baseline_environment"]["observed"]["godot_version"], "4.6.1.stable.custom_build.otherbuild")

    def test_unknown_object_leak_fails_run_even_after_successful_checks(self):
        output = "TESTS: 1 assertions, 0 failures\nWARNING: ObjectDB instances leaked at exit (run with --verbose for details)."
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with patch("run_validation.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                result = run("godot", path, path / "run.log", ["--script", "res://test.gd"], 1)
        self.assertFalse(result["ok"])
        self.assertEqual(result["unexpected_errors"], result["shutdown_errors"])

    def test_corrupt_storage_header_exception_requires_known_test_and_call_site(self):
        message = 'ERROR: Condition "magic != 0x43454447" is true. Returning: ERR_FILE_UNRECOGNIZED\n   at: open_and_parse (core/io/file_access_encrypted.cpp:99)'
        for script in ("test_storage.gd", "test_storage_initialization.gd"):
            args = ["--script", "res://tools/validation/" + script]
            self.assertIn("expected_test_errors", classify_engine_errors(message, args))
            self.assertIn("unexpected_errors", classify_engine_errors(message.replace("open_and_parse", "unrelated"), args))
        self.assertIn("unexpected_errors", classify_engine_errors(message, ["--script", "res://production.gd"]))

    def test_main_aggregates_script_import_and_smoke_results(self):
        cases = [
            (True, [True, True], True, 0, 2, 2, 0),
            (True, [True, False], True, 1, 2, 1, 0),
            (True, [True, True], False, 1, 2, 2, 0),
            (False, [], None, 1, 0, 0, 2),
        ]
        for imported, tests, smoke, expected_exit, executed, passed, skipped in cases:
            with self.subTest(imported=imported, tests=tests, smoke=smoke), tempfile.TemporaryDirectory() as directory:
                target = Path(directory)
                source = target / "source"
                source.mkdir()
                for name in ("one.gd", "two.gd"):
                    (source / name).write_text("extends SceneTree\n")
                output = io.StringIO()
                runs = [{"ok": value} for value in tests] + ([{"ok": smoke}] if smoke is not None else [])
                with patch("run_validation.tempfile.mkdtemp", return_value=str(target)), \
                     patch("run_validation.prepare", return_value=target / "project"), \
                     patch("run_validation.import_project", return_value=[{"ok": imported}]), \
                     patch("run_validation.fresh_userdata"), \
                     patch("run_validation.run", side_effect=runs) as mocked, contextlib.redirect_stdout(output):
                    result = main(["--source", str(source), "--script", "res://one.gd", "--script", "res://two.gd", "--smoke"])
                summary = json.loads(next(line.removeprefix("VALIDATION_SUMMARY=") for line in output.getvalue().splitlines() if line.startswith("VALIDATION_SUMMARY=")))
                self.assertEqual(result, expected_exit)
                self.assertEqual(summary["scope"], "custom")
                self.assertEqual(summary["planned_scripts"], 2)
                self.assertEqual(summary["executed_scripts"], executed)
                self.assertEqual(summary["passed_scripts"], passed)
                self.assertEqual(summary["skipped_scripts"], skipped)
                self.assertEqual(summary["smoke_executed"], imported)
                self.assertEqual(mocked.call_count, len(runs))
                self.assertEqual(summary, json.loads((target / "summary.json").read_text()))
                self.assertEqual(len(json.loads((target / "report.json").read_text())), 1 + len(runs))

    def test_architecture_failure_reports_all_planned_scripts_as_skipped(self):
        output = io.StringIO()
        with patch("run_validation.check_architecture", return_value=["fixture violation"]), \
             patch("run_validation.prepare") as prepared, contextlib.redirect_stdout(output):
            self.assertEqual(main(["--suite", "framework"]), 1)
        summary = json.loads(next(line.removeprefix("VALIDATION_SUMMARY=") for line in output.getvalue().splitlines() if line.startswith("VALIDATION_SUMMARY=")))
        self.assertFalse(summary["ok"])
        self.assertEqual(summary["planned_scripts"], summary["skipped_scripts"])
        self.assertEqual(summary["executed_scripts"], 0)
        prepared.assert_not_called()

    def test_empty_requested_suite_does_not_fall_back_to_recovery(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                main(["--source", directory, "--suite", "content", "--list"])
        self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
