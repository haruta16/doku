#!/usr/bin/env python3
"""Build a real signed Spine release and load it with the production content runtime."""
from __future__ import annotations
import argparse
import os
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from run_tests import prepare_fixture_guard, run_step


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="content-spine-test-") as temporary:
        work = Path(temporary).resolve()
        source = work / "data-source"
        source.mkdir()
        (source / "levels.json").write_text('{"level":1}', encoding="utf-8")
        subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(work / "private.pem")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["openssl", "pkey", "-in", str(work / "private.pem"), "-pubout", "-out", str(work / "public.pem")], check=True)
        common = [sys.executable, str(repo / "tools/content/build_release.py"), "--source", str(source), "--product", "test", "--runtime", "runtime-v1", "--key", str(work / "private.pem")]
        subprocess.run([*common, "--output", str(work / "spine"), "--release", "spine", "--spine-assets", str(repo / "products/meowdoku/assets/effect/spine/ui_cat_icon"), "--godot", args.godot], check=True)
        subprocess.run([*common, "--output", str(work / "data-next"), "--release", "data-next"], check=True)
        project = work / "project"
        (project / "scripts/framework").mkdir(parents=True)
        shutil.copytree(repo / "scripts/framework/content", project / "scripts/framework/content")
        prepare_fixture_guard(repo, work, project)
        shutil.copyfile(repo / "tools/validation/test_content_spine.gd", project / "test.gd")
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="ContentContractTests"\n', encoding="utf-8")
        steps = [run_step([args.godot, "--headless", "--log-file", str(work / "test.engine.log"), "--path", str(project), "--script", "res://test.gd", "--", str(work)], work / "test.log")]
        if steps[-1]["ok"]:
            steps.append(run_step([args.godot, "--headless", "--log-file", str(work / "resume.engine.log"), "--path", str(project), "--script", "res://test.gd", "--", str(work), "resume"], work / "resume.log"))
        report = {"ok": len(steps) == 2 and all(step["ok"] for step in steps), "steps": steps,
                  "scope": "Isolated signed Spine publication and two-process cold-start validation; no production game or mobile runtime."}
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("SPINE_SUITE", json.dumps({"ok": report["ok"], "steps": len(steps)}), flush=True)
        raise SystemExit(0 if report["ok"] else 1)


if __name__ == "__main__":
    main()
