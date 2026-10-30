#!/usr/bin/env python3
"""Validate a candidate Meowdoku release before publication, without game autoloads or player data."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_validation import classify_engine_errors, has_reported_failures

ROOT = Path(__file__).resolve().parents[1]
PURE_FILES = (
    "scripts/framework/presentation/content_scene_bindings.gd",
    "products/meowdoku/gameplay/content/doku_content_validator.gd",
    "products/meowdoku/gameplay/content/doku_level_catalog.gd",
    "products/meowdoku/gameplay/content/doku_policy.gd",
    "products/meowdoku/gameplay/content/level_bank_io.gd",
    "products/meowdoku/gameplay/domain/doku_level_definition.gd",
    "products/meowdoku/gameplay/domain/doku_main_selection_rules.gd",
    "products/meowdoku/gameplay/domain/queendoku_core.gd",
    "products/meowdoku/gameplay/domain/cell_state.gd",
    "tools/content/validate_product.gd",
)


def validate(release: Path, engine: str) -> None:
    with tempfile.TemporaryDirectory(prefix="doku-product-check-") as directory:
        project = Path(directory)
        for relative in PURE_FILES:
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        shutil.copytree(ROOT / "scripts/framework/content", project / "scripts/framework/content")
        for relative in ("products/meowdoku/assets/config", "products/meowdoku/assets/resources/levels", "products/meowdoku/assets/editor/levels"):
            shutil.copytree(ROOT / relative, project / relative)
        registry = json.loads((ROOT / "products/meowdoku/assets/config/scene_bindings.json").read_text())["resources"]
        for source, binding in registry.items():
            if binding["kind"] != "spine":
                relative = Path(source.removeprefix("res://"))
                (project / relative).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, project / relative)
                continue
            relative = Path(source.removeprefix("res://")).parent
            if not (project / relative).exists():
                shutil.copytree(ROOT / relative, project / relative)
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="DokuContentValidation"\n'
            '[content]\nscene_bindings_path="res://products/meowdoku/assets/config/scene_bindings.json"\n', encoding="utf-8")
        for arguments in (["--editor", "--import"], ["--script", "res://tools/content/validate_product.gd", "--", str(release.resolve())]):
            command = [engine, "--headless", "--path", str(project), "--log-file", str(project / "engine.log"), *arguments]
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            output = result.stdout + result.stderr
            diagnostics = classify_engine_errors(output, arguments)
            if (result.returncode or has_reported_failures(output) or diagnostics.get("unexpected_errors")
                    or any(marker in output for marker in ("SCRIPT ERROR:", "Parse Error:", "PRODUCT_VALIDATION_FAILED:"))):
                raise RuntimeError(output[-8000:])
            if "--script" in arguments:
                if "PRODUCT_VALIDATED:" not in output:
                    raise RuntimeError("Product validator did not report completion")
                print(next(line for line in output.splitlines() if "PRODUCT_VALIDATED:" in line))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    args = parser.parse_args()
    validate(args.release, args.godot)


if __name__ == "__main__":
    main()
