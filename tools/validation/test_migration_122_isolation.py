"""The 1.22 recovery runner cannot silently use production network or source data."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from run_validation import assert_isolated_product, classify_engine_errors, completion_contract, isolate_product_transports, prepare


class Migration122IsolationTests(unittest.TestCase):
    def test_copy_preserves_evidence_and_source_while_isolating_new_services(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            source = base / "source"
            source.mkdir()
            config = ('config_version=5\n[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="ProductionSave"\n[autoload]\nMCPGameInspector="*res://mcp.gd"\n'
                      '[editor_plugins]\nenabled=PackedStringArray("res://plugin.cfg")\n')
            (source / "project.godot").write_text(config)
            for name in ["unikit_config.tres", "lxauth_android_config.tres"]:
                (source / name).write_text("SDK fixture configuration\n")
            evidence = source / "docs/recovery/1.22.0/package_manifest.json"
            evidence.parent.mkdir(parents=True)
            evidence.write_bytes(b'{"immutable_original_identity": true}\n')
            paths = ["products/meowdoku/app/network/http_client.gd",
                     "products/meowdoku/app/features/level_rec/net/rec_http.gd",
                     "products/meowdoku/app/features/data_sync/data_sync_manager.gd"]
            originals = {}
            for relative in paths:
                path = source / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                originals[relative] = (ROOT / relative).read_bytes()
                path.write_bytes(originals[relative])
            project = prepare(source, base / "fixture")
            self.assertEqual((source / "project.godot").read_text(), config)
            for name in ["unikit_config.tres", "lxauth_android_config.tres"]:
                self.assertEqual((project / name).read_bytes(), (source / name).read_bytes())
            self.assertEqual((project / evidence.relative_to(source)).read_bytes(), evidence.read_bytes())
            prepared_config = (project / "project.godot").read_text()
            self.assertNotIn('MCPGameInspector=', prepared_config)
            self.assertIn('enabled=PackedStringArray()', prepared_config)
            self.assertIn('validation/offline=true', prepared_config)
            self.assertNotIn('ProductionSave', prepared_config)
            self.assertIn('DokuIsolatedValidation/fixture', prepared_config)
            for relative in paths:
                self.assertEqual((source / relative).read_bytes(), originals[relative])
                copied = (project / relative).read_text()
                self.assertIn('doku/validation/offline', copied)
                self.assertNotIn('user://', copied)
            self.assertTrue((base / 'fixture/.isolated-validation').is_file())
            assert_isolated_product(project)
            (project / paths[0]).write_bytes(originals[paths[0]])
            with self.assertRaisesRegex(ValueError, 'transport guard is missing'):
                assert_isolated_product(project)
            isolate_product_transports(project)
            (project / 'project.godot').write_text(prepared_config.replace('validation/offline=true', 'validation/offline=false'))
            with self.assertRaisesRegex(ValueError, 'offline setting is missing'):
                assert_isolated_product(project)

    def test_changed_transport_contract_stops_preparation(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            transport = project / 'products/meowdoku/app/network/http_client.gd'
            transport.parent.mkdir(parents=True)
            transport.write_text('extends Node\nfunc new_transport():\n\treturn HTTPRequest.new()\n')
            with self.assertRaisesRegex(ValueError, 'Cannot safely isolate production transport'):
                isolate_product_transports(project)

    def test_only_the_named_truncated_purchase_fixture_is_expected(self):
        line = "ERROR: ConfigFile parse error at /tmp/doku-validation-fixture/project/fixtures/legacy/purchase.cfg:0: Unexpected EOF while parsing simple tag."
        args = ["--script", "res://tools/validation/test_122_business_storage.gd"]
        self.assertEqual(classify_engine_errors(line, args)["expected_test_errors"], [line])
        self.assertTrue(classify_engine_errors(line.replace("purchase.cfg", "profile.cfg"), args)["unexpected_errors"])
        self.assertTrue(classify_engine_errors(line.replace("/tmp/doku-validation-fixture", "/real-product"), args)["unexpected_errors"])
        self.assertTrue(classify_engine_errors(line, ["--script", "res://tools/validation/test_storage.gd"])["unexpected_errors"])

    def test_roundtrip_contract_cannot_pass_with_old_bank_count(self):
        command = ['--script', 'res://tools/verify_level_bank_roundtrip.gd']
        for text in ['', 'ENCRYPTOR_ROUNDTRIP_OK: 26 files', 'VALIDATION_OK: 59 files']:
            self.assertFalse(completion_contract(text, command)['ok'])
        self.assertTrue(completion_contract('ENCRYPTOR_ROUNDTRIP_OK: 59 files', command)['ok'])


if __name__ == '__main__':
    unittest.main()
