#!/usr/bin/env python3
"""仅复制通用 UI 脚本，在没有产品 Autoload、资源、存档的临时工程验收。"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

from run_validation import run

ROOT = Path(__file__).resolve().parents[1]
DEPENDENCIES = (
    "scripts/framework/ui/ui_window_manager.gd",
    "scripts/framework/ui/base/ui_base_window.gd",
    "scripts/framework/ui/base/ui_frame_window.gd",
    "scripts/framework/ui/base/ui_child_window.gd",
    "scripts/framework/ui/ui_events.gd",
    "scripts/framework/ui/ui_modal_mask.gd",
    "scripts/framework/ui/ui_layer_config.gd",
    "scripts/framework/ui/ui_helper.gd",
    "tools/validation/test_ui_framework.gd",
    "tools/validation/fixtures/ui_creating_child.gd",
    "tools/validation/fixtures/ui_creating_frame.gd",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    options = parser.parse_args()
    target = Path(tempfile.mkdtemp(prefix="doku-ui-framework-"))
    project = target / "project"
    project.mkdir()
    for relative in DEPENDENCIES:
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, destination)
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="UI Framework Tests"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        '[test]\nui_framework_isolated=true\n', encoding="utf-8",
    )
    print(f"UI_FRAMEWORK_WORKSPACE={target}", flush=True)
    results = [run(options.godot, project, target / "import.log", ["--editor", "--import"], 90)]
    if results[-1]["ok"]:
        results.append(run(options.godot, project, target / "test.log",
                           ["--script", "res://tools/validation/test_ui_framework.gd"], 90))
    print(json.dumps(results, ensure_ascii=False, indent=2))
    (target / "report.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    return 0 if all(result["ok"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
