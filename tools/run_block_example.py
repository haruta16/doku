#!/usr/bin/env python3
"""在无产品 Autoload 的临时工程运行 Block 示例，默认独立保存到系统临时目录。"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_validation import classify_engine_errors, has_reported_failures, run

ROOT = Path(__file__).resolve().parents[1]
DEPENDENCIES = (
    "scripts/framework/operation_result.gd",
    "scripts/framework/storage/save_store.gd",
    "scripts/framework/storage/local_core_store.gd",
    "scripts/framework/application/round_service.gd",
)


def prepare(target: Path, data: Path) -> Path:
    project = target / "project"
    project.mkdir()
    for relative in DEPENDENCIES:
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, destination)
    shutil.copytree(ROOT / "scripts/examples/block", project / "scripts/examples/block")
    test = project / "tools/validation/test_block_example.gd"
    test.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "tools/validation/test_block_example.gd", test)
    (project / "project.godot").write_text(
        'config_version=5\n'
        '[application]\nconfig/name="Block Framework Example"\n'
        'run/main_scene="res://scripts/examples/block/block_example.tscn"\n'
        '[display]\nwindow/size/viewport_width=620\nwindow/size/viewport_height=860\n'
        'window/stretch/mode="canvas_items"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        '[input_devices]\npointing/emulate_mouse_from_touch=true\n'
        '[example]\nstorage_directory=' + json.dumps(data.as_posix()) + '\n',
        encoding="utf-8",
    )
    return project


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--data-dir", type=Path, default=Path(tempfile.gettempdir()) / "meowdoku-block-example-data")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--frames", type=int, default=0, help="指定后在该帧数退出，用于启动检查")
    parser.add_argument("--test", action="store_true", help="跑真实页面测试；使用临时夹具，不读取示例存档")
    parser.add_argument("--screenshot", type=Path, help="配合 --test 保存截图，需可用图形环境")
    options = parser.parse_args()
    if options.frames < 0:
        parser.error("--frames must not be negative")
    if options.screenshot and (options.headless or not options.test):
        parser.error("--screenshot requires --test and a graphical display")
    target = Path(tempfile.mkdtemp(prefix="doku-block-example-"))
    project = prepare(target, options.data_dir.expanduser().resolve())
    print(f"BLOCK_EXAMPLE_PROJECT={project}", flush=True)
    print(f"BLOCK_EXAMPLE_DATA={options.data_dir.expanduser().resolve()}", flush=True)
    imported = run(options.godot, project, target / "import.log", ["--editor", "--import"], 90)
    print(json.dumps(imported, ensure_ascii=False), flush=True)
    if not imported["ok"]:
        return 1
    if options.test or options.frames:
        args = ["--quit-after", str(options.frames)] if options.frames else []
        if options.test:
            args.extend(["--script", "res://tools/validation/test_block_example.gd"])
        if options.screenshot:
            options.screenshot.parent.mkdir(parents=True, exist_ok=True)
            args.extend(["--", "--screenshot=" + str(options.screenshot.resolve())])
        tested = run(options.godot, project, target / "example.log", args, 120, rendered=not options.headless)
        print(json.dumps(tested, ensure_ascii=False), flush=True)
        (target / "report.json").write_text(json.dumps([imported, tested], ensure_ascii=False, indent=2))
        return 0 if tested["ok"] else 1
    command = [options.godot, "--path", str(project), "--log-file", str(target / "example.log")]
    if options.headless:
        command.append("--headless")
    result = subprocess.run(command)
    log = (target / "example.log").read_text() if (target / "example.log").exists() else ""
    diagnostics = classify_engine_errors(log, [])
    bad = any(marker in log for marker in ("SCRIPT ERROR:", "Parse Error:", "TEST_FAILED:"))
    bad = bad or has_reported_failures(log) or bool(diagnostics.get("unexpected_errors"))
    return result.returncode or (1 if bad else 0)


if __name__ == "__main__":
    raise SystemExit(main())
