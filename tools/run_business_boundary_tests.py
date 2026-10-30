#!/usr/bin/env python3
"""在没有 Autoload、页面、内容解析器和题库的最小工程中验证 Doku 业务边界。"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

from run_validation import run


ROOT = Path(__file__).resolve().parents[1]
# 明确的发布子集是一道可执行边界：新增隐式全局/资源依赖会使此工程导入或测试失败。
# 不把整个 application 目录复制进来，以免把产品的 AB/选题装配误称为纯业务。
FILES = (
    "scripts/framework/operation_result.gd",
    "scripts/framework/content/content_manifest.gd",
    "scripts/framework/storage/save_store.gd",
    "scripts/framework/storage/local_core_store.gd",
    "scripts/framework/application/economy_service.gd",
    "scripts/framework/application/round_service.gd",
    "products/meowdoku/gameplay/application/meowdoku_round_session.gd",
    "products/meowdoku/gameplay/application/meowdoku_round_settlement.gd",
    "products/meowdoku/gameplay/application/meowdoku_settlement_rules.gd",
    "products/meowdoku/app/state/meowdoku_store.gd",
    "products/meowdoku/app/state/meowdoku_state_fields.gd",
    "products/meowdoku/app/state/meowdoku_award_policy.gd",
    "products/meowdoku/app/features/profile/model/profile_catalog.gd",
    "products/meowdoku/gameplay/application/meowdoku_action_facts.gd",
    "products/meowdoku/gameplay/application/models/level_kind.gd",
)
TESTS = ("test_product_session.gd", "test_product_settlement.gd")


def prepare(target: Path) -> Path:
    project = target / "project"
    project.mkdir()
    sources = [ROOT / path for path in FILES]
    sources.extend((ROOT / "products/meowdoku/gameplay/domain").glob("*.gd"))
    sources.extend(ROOT / "tools/validation" / name for name in TESTS)
    for source in sources:
        destination = project / source.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Doku Business Boundary"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n',
        encoding="utf-8",
    )
    return project


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--timeout", type=int, default=90)
    options = parser.parse_args()
    target = Path(tempfile.mkdtemp(prefix="doku-validation-business-"))
    project = prepare(target)
    print(f"BUSINESS_BOUNDARY_PROJECT={project}", flush=True)
    results = [run(options.godot, project, target / "import.log", ["--editor", "--import"], options.timeout)]
    print(json.dumps(results[-1], ensure_ascii=False), flush=True)
    if results[-1]["ok"]:
        for name in TESTS:
            results.append(run(options.godot, project, target / (name + ".log"),
                               ["--script", "res://tools/validation/" + name], options.timeout))
            print(json.dumps(results[-1], ensure_ascii=False), flush=True)
    (target / "report.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    return 0 if all(result["ok"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
