"""PCK proof diagnostics must survive its log filter and reject incomplete runs."""
import contextlib
import io
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/content"))
import verify_exported_resources as proof


class ExportProofTests(unittest.TestCase):
    def run_output(self, output, args=None):
        captured = io.StringIO()
        with patch.object(proof.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, output)), contextlib.redirect_stdout(captured):
            proof.run("godot", args or ["--main-pack", "proof.pck"])
        return captured.getvalue()

    def test_shutdown_leaks_fail_after_success_and_remain_visible(self):
        for message in ("WARNING: ObjectDB instances leaked at exit (run with --verbose for details).",
                        "ERROR: 2 resources still in use at exit (run with --verbose for details)."):
            with self.subTest(message=message):
                captured = io.StringIO()
                output = "EXPORTED_CONTENT_PROOF checks=7 failures=0\n" + message
                with patch.object(proof.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, output)), contextlib.redirect_stdout(captured):
                    with self.assertRaisesRegex(RuntimeError, "errors during the export proof"):
                        proof.run("godot", ["--main-pack", "proof.pck"])
                self.assertIn(message, captured.getvalue())
                self.assertIn('"shutdown_errors"', captured.getvalue())
                self.assertIn('"unexpected_errors"', captured.getvalue())

    def test_successful_probe_requires_completed_nonempty_checks(self):
        self.assertIn("checks=7", self.run_output("EXPORTED_CONTENT_PROOF checks=7 failures=0"))
        for output in ("", "EXPORTED_CONTENT_PROOF checks=0 failures=0", "EXPORTED_CONTENT_PROOF checks=7 failures=1"):
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                self.run_output(output)

    def test_known_environment_errors_are_retained_with_call_site(self):
        user_directory = Path.home() / "Library/Application Support/Godot/app_userdata/ContentExportProof"
        directory_error = f"ERROR: Could not create directory: '{user_directory}'."
        messages = (directory_error + "\n   at: make_dir_recursive (core/io/dir_access.cpp:178)\n"
                    'ERROR: Condition "ret != noErr" is true. Returning: ""\n'
                    "   at: get_system_ca_certificates (platform/macos/os_macos.mm:1014)\n")
        captured = self.run_output(messages, ["--editor", "--import"])
        self.assertIn("PCK_ENGINE_DIAGNOSTICS=", captured)
        self.assertIn('"environment_errors"', captured)
        self.assertIn(directory_error, captured)
        for invalid in (messages.replace("ContentExportProof", "Meowdoku"),
                        messages.replace("make_dir_recursive", "save_game"),
                        messages.replace("get_system_ca_certificates", "unrelated")):
            with self.subTest(output=invalid), self.assertRaises(RuntimeError):
                self.run_output(invalid, ["--editor", "--import"])

    def test_profiler_directory_exception_is_editor_and_proof_only(self):
        user_directory = Path.home() / "Library/Application Support/Godot/app_userdata/ContentExportProof"
        message = (f"ERROR: Error attempting to create data dir: {user_directory}.\n"
                   "   at: ensure_user_data_dir (core/os/os.cpp:437)\n"
                   "ERROR: Could not open 'user://' directory: 'user://'.\n"
                   "   at: objectdb_profiler (core/object/object.cpp:100)\n")
        self.assertNotIn("unexpected_errors", proof.proof_diagnostics(message, ["--editor", "--import"]))
        self.assertNotIn("unexpected_errors", proof.proof_diagnostics(message, ["--export-pack", "Proof", "proof.pck"]))
        self.assertIn("unexpected_errors", proof.proof_diagnostics(message, ["--main-pack", "proof.pck"]))
        self.assertIn("unexpected_errors", proof.proof_diagnostics(message.replace("ContentExportProof", "Meowdoku"), ["--editor", "--import"]))


if __name__ == "__main__":
    unittest.main()
