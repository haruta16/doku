#!/usr/bin/env python3
"""只复制完整公共框架，在无产品脚本、资源和 Autoload 的临时工程中验收。"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from run_validation import run


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = "tools/validation/fixtures/framework_consumer.gd"


def prepare(source: Path, target: Path) -> tuple[Path, dict[str, str]]:
    project = target / "project"
    project.mkdir()
    shutil.copytree(source / "scripts/framework", project / "scripts/framework")
    fixture = project / FIXTURE
    fixture.parent.mkdir(parents=True)
    shutil.copy2(source / FIXTURE, fixture)
    scripts = sorted("res://" + path.relative_to(project).as_posix()
                     for path in (project / "scripts/framework").rglob("*.gd"))
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Framework Boundary Tests"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        '[test]\nframework_boundary_isolated=true\nframework_scripts='
        + json.dumps(scripts) + '\n', encoding="utf-8",
    )
    fingerprints = {path.relative_to(project).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in project.rglob("*") if path.is_file()}
    return project, fingerprints


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--timeout", type=int, default=120)
    options = parser.parse_args()
    target = Path(tempfile.mkdtemp(prefix="doku-framework-boundary-"))
    project, fingerprints = prepare(ROOT, target)
    print(f"FRAMEWORK_BOUNDARY_PROJECT={project}", flush=True)
    results = [run(options.godot, project, target / "import.log", ["--editor", "--import"], options.timeout)]
    if results[-1]["ok"]:
        results.append(run(options.godot, project, target / "consumer.log", ["--script", "res://" + FIXTURE], options.timeout))
    # 这个小型独立消费者没有音频/长期任务，退出资源告警也是验收失败。
    for result in results:
        if result.get("shutdown_errors"):
            result["ok"] = False
        print(json.dumps(result, ensure_ascii=False), flush=True)
    passed = len(results) == 2 and all(result["ok"] for result in results)
    report = {"ok": passed, "scope": "entire framework without product code/resources/autoloads",
              "inputs": fingerprints, "checks": results}
    (target / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
