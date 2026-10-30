#!/usr/bin/env python3
"""在隔离工程检查产品 debug 与模拟 release 谓词；不替代实际 release 包验收。"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile

from run_validation import import_project, prepare, run


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "res://tools/validation/test_development_boundaries.gd"
# 仅替换产品装配代码中的构建谓词；断言脚本保持原样，期望值由用户参数传入。
BUILD_PREDICATE_FILES = (
    "products/meowdoku/app/bootstrap/launcher.gd",
    "products/meowdoku/app/ui/ui_registry.gd",
    "products/meowdoku/app/state/game_state.gd",
    "products/meowdoku/gameplay/presentation/main/view/game_page.gd",
    "products/meowdoku/gameplay/presentation/daily/view/daily_game_page.gd",
    "products/meowdoku/gameplay/presentation/board/board_view.gd",
    "addons/cheat_manager/cheat_bus.gd",
)


def prepare_branch(source: Path, target: Path, mode: str) -> Path:
    project = prepare(source, target)
    if mode == "simulated_release":
        for name in BUILD_PREDICATE_FILES:
            path = project / name
            path.write_text(path.read_text().replace("OS.is_debug_build()", "false"))
    return project


def run_branch(engine: str, project: Path, target: Path, mode: str, timeout: int) -> dict:
    steps = import_project(engine, project, target / "import.log", timeout)
    for imported in steps:
        print(json.dumps(imported, ensure_ascii=False), flush=True)
    if steps[-1]["ok"]:
        steps.append(run(engine, project, target / "test.log", ["--script", SCRIPT, "--", mode], timeout))
        print(json.dumps(steps[-1], ensure_ascii=False), flush=True)
    return {"mode": mode, "ok": all(step["ok"] for step in steps), "steps": steps}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    target = Path(tempfile.mkdtemp(prefix="doku-validation-development-"))
    print(f"DEVELOPMENT_BOUNDARY_WORKSPACE={target}", flush=True)
    branches = []
    for mode in ("debug", "simulated_release"):
        branch = target / mode
        project = prepare_branch(ROOT, branch, mode)
        branches.append(run_branch(args.godot, project, branch, mode, args.timeout))
    report = {
        "scope": "Isolated userdata in each branch. The release branch replaces OS.is_debug_build() only in the seven listed product files; no exported release binary or mobile SDK is validated.",
        "predicate_files": list(BUILD_PREDICATE_FILES),
        "ok": all(branch["ok"] for branch in branches),
        "branches": branches,
    }
    (target / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
