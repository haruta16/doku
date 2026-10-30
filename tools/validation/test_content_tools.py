"""Publication and content test gates must reject unusable output even at exit code zero."""
from pathlib import Path
import argparse
import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/content"))
import build_channel
import build_release
import run_tests
import run_product_tests
import validate_content_product
from run_validation import classify_engine_errors


class ContentToolTests(unittest.TestCase):
    def test_content_suite_requires_all_steps(self):
        self.assertFalse(run_tests.content_report([])["ok"])
        self.assertFalse(run_tests.content_report([{"ok": True}] * 5)["ok"])
        steps = [{"ok": True} for _ in range(run_tests.CONTENT_STEP_COUNT)]
        self.assertTrue(run_tests.content_report(steps)["ok"])
        steps[-1]["ok"] = False
        self.assertFalse(run_tests.content_report(steps)["ok"])

    def test_missing_bootstrap_fixture_is_not_a_silent_skip(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative in run_tests.REQUIRED_CONTENT_INPUTS:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            run_tests.require_fixtures(root)
            (root / "tools/validation/test_content_update_bootstrap.gd").unlink()
            with self.assertRaisesRegex(FileNotFoundError, "test_content_update_bootstrap"):
                run_tests.require_fixtures(root)

    def test_replacing_failed_publication_recomputes_report_success(self):
        previous = {"ok": False, "steps": [{"ok": True}], "product_publication_checks": [{"case": "old", "ok": False}]}
        current = [{"case": "new", "ok": True}]
        report = run_product_tests.merge_publication_checks(previous, current)
        self.assertTrue(report["ok"])
        self.assertEqual(report["product_publication_checks"], current)

    def test_publication_success_preserves_failed_delivery_step(self):
        previous = {"ok": False, "steps": [{"ok": False}], "product_publication_checks": [{"ok": False}]}
        report = run_product_tests.merge_publication_checks(previous, [{"ok": True}])
        self.assertFalse(report["ok"])
        self.assertEqual(report["steps"], previous["steps"])

    def test_publisher_url_contract_uses_client_fixtures(self):
        cases = json.loads((ROOT / "tools/validation/fixtures/content_channel_urls.json").read_text())
        self.assertIsInstance(cases, list)
        self.assertTrue(cases, "URL contract must not pass without any cases")
        for entry in cases:
            with self.subTest(url=entry["url"]):
                self.assertIsInstance(entry["url"], str)
                self.assertIs(type(entry["local"]), bool)
                self.assertIs(type(entry["allowed"]), bool)
                self.assertEqual(build_channel.allowed_url(entry["url"], entry["local"]), entry["allowed"])

    def test_channel_builder_rejects_invalid_url_without_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / "source"
            source.mkdir()
            (source / "settings.json").write_text('{"enabled":true}')
            key = work / "private.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(key)], check=True, capture_output=True)
            release = work / "release"
            with contextlib.redirect_stdout(io.StringIO()):
                build_release.build(argparse.Namespace(source=source, output=release, product="test", release="one", runtime="runtime-v1", key=key, godot=None, raw_assets=None, spine_assets=None))
            for index, url in enumerate(["https://example.com:/one", "http://LOCALHOST:8080/one"]):
                output = work / f"channel-{index}"
                with self.subTest(url=url), self.assertRaisesRegex(ValueError, "Target must use HTTPS"):
                    build_channel.build(argparse.Namespace(product="test", channel="stable", revision=1, target=[(str(release), url)], key=key, output=output, allow_local_http=True))
                self.assertFalse(output.exists())

    def test_content_runner_rejects_engine_error_even_with_success_summary(self):
        output = "CONTENT_TESTS checks=51 failures=0\nERROR: Stack underflow! (Engine Bug)\n"
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            with patch("run_tests.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                result = run_tests.run_step(["godot", "--script", "res://test.gd"], Path(directory) / "run.log")
        self.assertFalse(result["ok"])
        self.assertIn("Stack underflow", result["unexpected_errors"][0])

    def test_content_runner_rejects_nonzero_failures_at_zero_exit(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            with patch("run_tests.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "CONTENT_TESTS checks=51 failures=1\n", "")):
                result = run_tests.run_step(["godot", "--script", "res://test.gd"], Path(directory) / "run.log")
        self.assertFalse(result["ok"])

    def test_corrupt_png_exception_is_only_for_the_fault_process(self):
        message = 'ERROR: Condition "!success" is true. Returning: ERR_FILE_CORRUPT\n   at: png_to_image (drivers/png/png_driver_common.cpp:68)'
        self.assertIn("expected_test_errors", classify_engine_errors(message, ["--script", "res://boot-failure.gd"]))
        self.assertIn("unexpected_errors", classify_engine_errors(message, ["--script", "res://boot-failure.gd", "--", "resume"]))
        self.assertIn("unexpected_errors", classify_engine_errors(message, ["--script", "res://test.gd"]))

    def test_signing_validator_rejects_generic_engine_error(self):
        # A successful marker cannot hide a native resource-loading error before signing.
        output = "PRODUCT_VALIDATED: candidate\nERROR: Failed loading resource: res://broken.tres.\n"
        with patch("validate_content_product.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
            with self.assertRaisesRegex(RuntimeError, "Failed loading resource"):
                validate_content_product.validate(ROOT, "godot")

    def test_release_cannot_be_signed_after_zero_exit_engine_error(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / "source/doku"
            source.mkdir(parents=True)
            (source / "policy.json").write_text('{"schema":1,"draft_unlock_level":21}')
            engine = work / "godot"
            engine.write_text('#!/bin/sh\nprintf "PRODUCT_VALIDATED: candidate\\nERROR: Failed loading resource: res://broken.tres.\\n"\nexit 0\n')
            engine.chmod(0o755)
            key = work / "private.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(key)], check=True, capture_output=True)
            output = work / "release"
            result = subprocess.run([sys.executable, str(ROOT / "tools/content/build_release.py"),
                "--source", str(source.parent), "--output", str(output), "--product", "meowdoku",
                "--release", "fault", "--runtime", "runtime-v1", "--key", str(key),
                "--godot", str(engine)], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Failed loading resource", result.stderr)
            self.assertFalse(output.exists())

    def test_raw_packer_rejects_native_error_before_signing(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source, raw = work / "source", work / "raw"
            source.mkdir()
            raw.mkdir()
            (source / "settings.json").write_text('{"enabled":true}')
            (raw / "image.png").write_bytes(b"fixture")
            output = work / "release"
            args = argparse.Namespace(source=source, output=output, product="test", release="one", runtime="runtime-v1", key=work / "unused.pem", godot="godot", raw_assets=raw, spine_assets=None)
            with patch("build_release.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "ERROR: Pack failed internally.\n", "")):
                with self.assertRaisesRegex(RuntimeError, "Pack failed internally"):
                    build_release.build(args)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
