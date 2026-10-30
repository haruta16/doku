"""公共区域不能悄悄依赖产品资源；动态和全局依赖仍交给独立 Godot 工程。"""
from pathlib import Path, PurePosixPath
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_architecture import check, resource_dependencies, violation


class ArchitectureBoundaryTests(unittest.TestCase):
    def test_framework_rejects_product_scripts_assets_and_plugins(self):
        source = PurePosixPath("scripts/framework/ui/sample.gd")
        for path in ("products/meowdoku/app/state/game_state.gd", "products/meowdoku/gameplay/domain/core.gd",
                     "products/meowdoku/assets/prefab/popup.tscn", "addons/product_sdk/plugin.gd"):
            with self.subTest(path=path):
                self.assertTrue(violation(source, PurePosixPath(path)))
        self.assertFalse(violation(source, PurePosixPath("scripts/framework/ui/base/ui_frame_window.gd")))

    def test_path_normalization_cannot_escape_framework(self):
        for uri in ("res://scripts/framework/../app/state.gd", "res://content/../products/meowdoku/assets/icon.png"):
            _, dependency = next(resource_dependencies('const P = "' + uri + '"'))
            self.assertTrue(violation(PurePosixPath("scripts/framework/content/sample.gd"), dependency))

    def test_content_runtime_namespaces_are_local_to_content(self):
        for path in ("content/%s/%s/%s", "content/%s/%s", ".godot/imported"):
            self.assertFalse(violation(PurePosixPath("scripts/framework/content/catalog.gd"), PurePosixPath(path)))
            self.assertTrue(violation(PurePosixPath("scripts/framework/ui/sample.gd"), PurePosixPath(path)))
        self.assertFalse(violation(PurePosixPath("scripts/framework/presentation/bindings.gd"), PurePosixPath(".")))

    def test_fixed_product_pack_and_imported_assets_are_not_protocol_templates(self):
        for path in ("content/meowdoku/release/logo.png", ".godot/imported/product.hash.ctex"):
            self.assertTrue(violation(PurePosixPath("scripts/framework/content/catalog.gd"), PurePosixPath(path)))

    def test_comments_are_ignored_and_resource_strings_keep_hashes(self):
        source = '# preload("res://products/meowdoku/assets/ignored.png")\nconst P = "res://products/meowdoku/assets/icon#2.png"\nvar prefix = "res://"'
        refs = list(resource_dependencies(source))
        self.assertEqual(refs, [(2, PurePosixPath("products/meowdoku/assets/icon#2.png")), (3, PurePosixPath("."))])

    def test_product_and_example_pure_domains_remain_independent(self):
        source = PurePosixPath("products/meowdoku/gameplay/domain/core.gd")
        self.assertTrue(violation(source, PurePosixPath("products/meowdoku/assets/puzzle.json")))
        self.assertFalse(violation(source, PurePosixPath("scripts/framework/operation_result.gd")))
        self.assertFalse(violation(source, PurePosixPath("products/meowdoku/gameplay/domain/cell.gd")))
        example = PurePosixPath("scripts/examples/block/domain/core.gd")
        self.assertTrue(violation(example, source))
        self.assertTrue(violation(example, PurePosixPath("scripts/examples/block/page.gd")))
        self.assertFalse(violation(example, PurePosixPath("scripts/examples/block/domain/cell.gd")))
        self.assertFalse(violation(example, PurePosixPath("scripts/framework/operation_result.gd")))

    def test_products_and_examples_do_not_rely_on_each_other(self):
        product = PurePosixPath("products/meowdoku/app/main.gd")
        example = PurePosixPath("scripts/examples/block/page.gd")
        self.assertTrue(violation(product, PurePosixPath("products/other/app/main.gd")))
        self.assertTrue(violation(product, example))
        self.assertTrue(violation(example, product))
        self.assertTrue(violation(example, PurePosixPath("scripts/examples/other/page.gd")))
        self.assertFalse(violation(product, PurePosixPath("products/meowdoku/assets/icon.png")))
        self.assertFalse(violation(product, PurePosixPath("addons/product_sdk/plugin.gd")))
        self.assertFalse(violation(example, PurePosixPath("scripts/framework/ui/ui_window_manager.gd")))

    def test_scene_resource_reference_is_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts/framework").mkdir(parents=True)
            (root / "products").mkdir(parents=True)
            (root / "scripts/examples").mkdir(parents=True)
            (root / "scripts/framework/panel.tscn").write_text('[ext_resource type="Texture2D" path="res://products/meowdoku/assets/logo.png" id="1"]')
            failures = check(root)
            self.assertEqual(len(failures), 1)
            self.assertIn("panel.tscn:1", failures[0])
            self.assertIn("products/meowdoku/assets/logo.png", failures[0])

    def test_product_and_example_files_are_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts/framework").mkdir(parents=True)
            product = root / "products/meowdoku/app/main.gd"
            example = root / "scripts/examples/block/page.gd"
            for path in (product, example):
                path.parent.mkdir(parents=True)
            product.write_text('extends Node\nconst Other = preload("res://products/other/app/main.gd")\n')
            example.write_text('extends Node\nconst Product = preload("res://products/meowdoku/app/main.gd")\n')
            failures = check(root)
            self.assertEqual(len(failures), 2)
            self.assertTrue(any("products/meowdoku/app/main.gd:2" in item for item in failures))
            self.assertTrue(any("scripts/examples/block/page.gd:2" in item for item in failures))


if __name__ == "__main__":
    unittest.main()
