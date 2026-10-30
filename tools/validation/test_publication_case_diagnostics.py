"""Publication rejection must not hide an unrelated engine error or shutdown leak."""
from pathlib import Path
import hashlib
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/content"))
import run_product_tests as publication


class PublicationCaseDiagnosticsTests(unittest.TestCase):
    rejection = "content_schema:doku/levels/bankdatagc6x6"

    def reject(self, extra="", *, artifact=False, exit_code=1):
        return publication.evaluate_publication_result(
            exit_code, "PRODUCT_VALIDATION_FAILED: " + self.rejection + "\n" + extra,
            rejection=self.rejection, artifact_exists=artifact, signature_exists=False)

    def test_expected_business_rejection_remains_valid(self):
        result = self.reject()
        self.assertTrue(result["ok"])
        self.assertTrue(result["diagnostics_classified"])

    def test_expected_rejection_with_script_error_is_not_valid(self):
        for error in ["SCRIPT ERROR: Invalid access to property 'state' on null instance.\n",
                      "Parse Error: Identifier not found.\n"]:
            with self.subTest(error=error):
                self.assertFalse(self.reject(error)["ok"])

    def test_expected_rejection_with_shutdown_leak_is_not_valid(self):
        for error in ["WARNING: ObjectDB instances leaked at exit (run with --verbose for details).\n",
                      "ERROR: 1 resources still in use at exit (run with --verbose for details).\n"]:
            with self.subTest(error=error):
                result = self.reject(error)
                self.assertFalse(result["ok"])
                self.assertTrue(result["shutdown_errors"])

    def test_expected_rejection_with_unexpected_engine_error_is_not_valid(self):
        result = self.reject("ERROR: Could not load a required resource.\n")
        self.assertFalse(result["ok"])
        self.assertTrue(result["unexpected_errors"])

    def test_nested_validator_exception_prefix_does_not_hide_engine_diagnostics(self):
        for error in ["RuntimeError: ERROR: 1 resources still in use at exit.\n",
                      "RuntimeError: ERROR: Could not load a required resource.\n"]:
            with self.subTest(error=error):
                self.assertFalse(self.reject(error)["ok"])

    def test_rejection_still_requires_nonzero_exit_reason_and_no_artifact(self):
        self.assertFalse(self.reject(artifact=True)["ok"])
        self.assertFalse(self.reject(exit_code=0)["ok"])
        self.assertFalse(publication.evaluate_publication_result(
            1, "Unrelated publisher failure", rejection=self.rejection,
            artifact_exists=False, signature_exists=False)["ok"])

    def test_success_requires_signature_and_rejects_engine_errors_too(self):
        valid = {"rejection": "", "artifact_exists": True, "signature_exists": True}
        self.assertTrue(publication.evaluate_publication_result(0, "PRODUCT_VALIDATED: valid\n", **valid)["ok"])
        for error in ["SCRIPT ERROR: invalid call\n", "ERROR: unexpected failure\n",
                      "WARNING: ObjectDB instances leaked at exit.\n",
                      "ERROR: 2 resources still in use at exit.\n"]:
            with self.subTest(error=error):
                self.assertFalse(publication.evaluate_publication_result(
                    0, "PRODUCT_VALIDATED: valid\n" + error, **valid)["ok"])
        self.assertFalse(publication.evaluate_publication_result(
            0, "PRODUCT_VALIDATED: valid\n", rejection="", artifact_exists=True, signature_exists=False)["ok"])

    def test_case_log_survives_disposable_project_and_has_verifiable_paths_and_hash(self):
        with tempfile.TemporaryDirectory() as archive:
            report = Path(archive) / "publication-report.json"
            logs = Path(archive) / "publication-report-case-logs"
            text = "PRODUCT_VALIDATION_FAILED: 拒绝原因\nWARNING: ObjectDB instances leaked at exit.\n"
            with tempfile.TemporaryDirectory() as work:
                self.assertTrue(Path(work).is_dir())
                record = publication.persist_case_log(logs, "negative-case", text, report)
            absolute = Path(record["log"])
            self.assertTrue(absolute.is_absolute())
            self.assertEqual(absolute, (report.parent / record["log_relative"]).resolve())
            self.assertEqual(absolute.read_text(), text)
            self.assertEqual(hashlib.sha256(absolute.read_bytes()).hexdigest(), record["log_sha256"])


if __name__ == "__main__":
    unittest.main()
