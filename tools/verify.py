#!/usr/bin/env python3
"""编排已有隔离验证，保存范围、子报告和输入指纹；不操作 Git 或日常玩家存档。"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

from validation_report import build_summary, capture_environment, write_summary


ROOT = Path(__file__).resolve().parents[1]
SUITES = ("quick", "framework", "all")
INPUT_DIRECTORIES = ("scripts", "products", "tools", "addons", ".autoconverted")
LIMITS = [
    "No APK/native SDK/mobile-device or production CDN/TLS acceptance.",
    "Development release checks simulate the build predicate; they do not export a release binary.",
    "PCK proof checks content/UID behavior, not a production mobile package.",
    "Recorded shutdown exceptions remain visible; passing does not mean leak-free.",
]


def steps_for(suite: str, engine: str, output: Path) -> list[dict]:
    python = [sys.executable, "-B", "-u"]
    steps = [
        {"name": "architecture", "command": [*python, "tools/check_architecture.py"], "completion": "architecture"},
        {"name": "python", "command": [*python, "-m", "unittest", "discover", "-s", "tools/validation", "-p", "test_*.py"], "completion": "python", "allow_skips": suite == "quick"},
    ]
    if suite == "quick":
        return steps
    from run_validation import suite_scripts

    scopes = {
        "framework": {"expected_scripts": suite_scripts(ROOT, "framework"), "require_import": True, "smoke": True},
        "framework_boundary": {"report_field": "checks", "expected_scripts": ["res://tools/validation/fixtures/framework_consumer.gd"], "require_import": True},
        "ui_boundary": {"expected_scripts": ["res://tools/validation/test_ui_framework.gd"], "require_import": True},
        "business_boundary": {"expected_scripts": ["res://tools/validation/test_product_session.gd", "res://tools/validation/test_product_settlement.gd"], "require_import": True},
        "block": {"expected_scripts": ["res://tools/validation/test_block_example.gd"], "require_import": True},
        "development": {"branches": ["debug", "simulated_release"], "expected_scripts": ["res://tools/validation/test_development_boundaries.gd"], "require_import": True},
    }
    for name, script, args, pointer in [
        ("framework", "run_validation.py", ["--suite", "framework", "--smoke"], "VALIDATION_WORKSPACE"),
        ("framework_boundary", "run_framework_boundary_tests.py", [], "FRAMEWORK_BOUNDARY_PROJECT"),
        ("ui_boundary", "run_ui_framework_tests.py", [], "UI_FRAMEWORK_WORKSPACE"),
        ("business_boundary", "run_business_boundary_tests.py", [], "BUSINESS_BOUNDARY_PROJECT"),
        ("block", "run_block_example.py", ["--headless", "--test"], "BLOCK_EXAMPLE_PROJECT"),
        ("development", "run_development_boundary_tests.py", [], "DEVELOPMENT_BOUNDARY_WORKSPACE"),
    ]:
        steps.append({"name": name, "command": [*python, "tools/" + script, "--godot", engine, *args], "pointer": pointer, **scopes[name]})
    if suite == "all":
        scopes.update({
            "content": {"report_field": "steps", "expected_scripts": ["res://test.gd", "res://updates.gd", "res://boot-failure.gd", "res://boot-failure.gd", "res://bootstrap-test.gd", "res://bootstrap-test.gd"], "require_import": True, "expected_rejections": 1},
            "spine": {"report_field": "steps", "expected_scripts": ["res://test.gd", "res://test.gd"]},
            "publication": {"report_field": "product_publication_checks", "expected_cases": [
                "catalog", "unknown-inherited-media", "raw-correct", "per-level-home-slot", "gc-correct", "gc-wrong-shape",
                "main-first-rank-missing", "main-combined-source", "main-late-policy-missing", "main-ab-size-missing",
                "daily-missing-rank", "daily-missing-tier", "lk-invalid-date", "lk-invalid-label", "shortened-special-bank", "special-bank-without-guide",
                "special-valid-prefill", "special-malformed-prefill", "special-wrong-prefill-answer", "raw-wrong-size",
                "spine-correct", "spine-wrong-contract",
            ]},
        })
        for name, script in [("content", "run_tests.py"), ("publication", "run_product_tests.py"), ("spine", "run_spine_test.py")]:
            report = output / (name + "-report.json")
            steps.append({"name": name, "command": [*python, "tools/content/" + script, "--godot", engine, "--report", str(report)], "report": str(report), **scopes[name]})
        steps.append({"name": "pck", "command": [*python, "tools/content/verify_exported_resources.py", "--godot", engine], "completion": "pck"})
    return steps


def fingerprints() -> dict[str, str]:
    paths = [ROOT / "project.godot", ROOT / "export_presets.cfg", ROOT / "icudt_godot.dat",
             ROOT / "docs/validation/review-followup-content-report.json"]
    for directory in INPUT_DIRECTORIES:
        paths.extend(path for path in (ROOT / directory).rglob("*")
                     if path.is_file() and "__pycache__" not in path.parts
                     and path.suffix not in (".pyc", ".log"))
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths) if path.is_file()}


def _records_passed(records, step: dict) -> bool:
    if not isinstance(records, list) or not records or not all(isinstance(item, dict) and item.get("ok") is True for item in records):
        return False
    if "expected_cases" in step:
        return (all(isinstance(item.get("case"), str) for item in records)
                and Counter(item["case"] for item in records) == Counter(step["expected_cases"])
                and all(type(item.get("exit_code")) is int
                        and ((item["exit_code"] != 0 and item.get("artifact_exists") is False)
                             if item.get("expected_rejection") else (item["exit_code"] == 0 and item.get("artifact_exists") is True))
                        for item in records))
    scripts = []
    imports = smoke = rejections = 0
    for item in records:
        command = item.get("command")
        if not isinstance(command, list) or not command or not all(isinstance(arg, str) for arg in command):
            return False
        if item.get("expected_rejection") is True:
            if type(item.get("exit_code")) is not int or item["exit_code"] == 0:
                return False
            rejections += 1
            continue
        if type(item.get("exit_code")) is not int or item["exit_code"] != 0 or not isinstance(item.get("completion"), dict) or item["completion"].get("ok") is not True:
            return False
        if "--script" in command:
            index = command.index("--script") + 1
            if index >= len(command):
                return False
            scripts.append(command[index])
        elif "--editor" in command and "--import" in command:
            imports += 1
        elif "--quit-after" in command:
            smoke += 1
        else:
            return False
    return (bool(step.get("expected_scripts")) and Counter(scripts) == Counter(step["expected_scripts"])
            and (imports > 0 if step.get("require_import") else imports == 0)
            and smoke == int(step.get("smoke", False)) and rejections == step.get("expected_rejections", 0))


def report_passed(value, step: dict) -> bool:
    if "branches" in step:
        if not isinstance(value, dict) or value.get("ok") is not True:
            return False
        branches = value.get("branches")
        return (isinstance(branches, list) and len(branches) == len(step["branches"])
                and all(isinstance(branch, dict) and branch.get("ok") is True and isinstance(branch.get("mode"), str) for branch in branches)
                and Counter(branch.get("mode") for branch in branches) == Counter(step["branches"])
                and all(_records_passed(branch.get("steps"), step) for branch in branches))
    if "report_field" in step:
        return (isinstance(value, dict) and value.get("ok") is True
                and _records_passed(value.get(step["report_field"]), step))
    return _records_passed(value, step)


def collect_completion(step: dict, text: str, output: Path) -> dict:
    contract = step.get("completion")
    if contract == "architecture":
        return {"ok": any(line.startswith("ARCHITECTURE_OK:") for line in text.splitlines())}
    if contract == "python":
        count = re.search(r"(?m)^Ran (\d+) tests? in ", text)
        terminal = re.search(r"(?m)^OK(?: \(skipped=(\d+)\))?[ \t]*$", text)
        tests = int(count[1]) if count else 0
        skipped = int(terminal[1]) if terminal and terminal[1] else 0
        executed = tests - skipped
        return {"ok": bool(count and terminal and executed > 0 and (skipped == 0 or step.get("allow_skips", False))),
                "tests": tests, "executed": executed, "skipped": skipped}
    if contract == "pck":
        return {"ok": bool(re.search(r"(?m)^PCK_PROOF_OK cases=2\s*$", text))}
    path = Path(step["report"]) if "report" in step else None
    if "pointer" in step:
        match = re.search(r"(?m)^" + re.escape(step["pointer"]) + r"=(.+)$", text)
        if match:
            directory = Path(match[1].strip())
            if step["pointer"].endswith("_PROJECT"):
                directory = directory.parent
            path = directory / "report.json"
    if path is None or not path.is_file():
        return {"ok": False, "error": "missing_child_report"}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return {"ok": False, "error": "invalid_child_report", "detail": str(error)}
    retained = output / (step["name"] + "-report.json")
    if path.resolve() != retained.resolve():
        shutil.copy2(path, retained)
    passed = report_passed(value, step)
    return {"ok": passed, "report": str(retained),
            "sha256": hashlib.sha256(retained.read_bytes()).hexdigest(),
            **({} if passed else {"error": "child_report_failed_or_incomplete"})}


def stop_process(process: subprocess.Popen) -> list[str]:
    # 子运行器会启动 Godot；超时或中断必须结束这一组，不能留下孤立验证进程。
    errors = []
    try:
        if os.name == "nt":
            killed = subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, timeout=15, check=False)
            if killed.returncode != 0:
                errors.append("taskkill_failed:" + str(killed.returncode))
        else:
            os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except (OSError, subprocess.TimeoutExpired) as exception:
        errors.append("process_tree_cleanup_failed:" + str(exception))
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            process.kill()
            process.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired) as exception:
            errors.append("process_cleanup_failed:" + str(exception))
    except OSError as exception:
        errors.append("process_wait_failed:" + str(exception))
    return errors


def run_step(step: dict, output: Path, timeout: int, engine: str) -> dict:
    log = output / (step["name"] + ".log")
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", DOKU_GODOT=engine)
    started = time.monotonic()
    error = ""
    exit_code = None
    process = None
    cleanup_errors = []
    try:
        with log.open("w", encoding="utf-8") as stream:
            # Popen 的 context manager 会无限 wait；失败清理必须保留自己的时间上限。
            process = subprocess.Popen(step["command"], cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=os.name != "nt")
            try:
                exit_code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                error = "timeout"
                cleanup_errors = stop_process(process)
                exit_code = process.poll()
    except KeyboardInterrupt:
        error = "interrupted"
        if process is not None:
            cleanup_errors = stop_process(process)
            exit_code = process.poll()
    except OSError as exception:
        error = str(exception)
    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    completion = collect_completion(step, text, output)
    return {"name": step["name"], "command": step["command"], "ok": exit_code == 0 and not error and completion["ok"],
            "exit_code": exit_code, "error": error, "elapsed_seconds": round(time.monotonic() - started, 3),
            "log": str(log), "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest() if log.exists() else "",
            "completion": completion, **({"cleanup_errors": cleanup_errors} if cleanup_errors else {})}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUITES, default="all", help="quick=Python/架构；framework=再加完整自包含与独立验证；all=再加内容/发布/Spine/PCK专项")
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--output", type=Path, help="不存在或为空且位于输入目录之外的证据目录；默认系统临时目录")
    parser.add_argument("--step-timeout", type=int, default=1800, help="每个子套件的最大秒数；子套件还有自己的逐进程超时")
    parser.add_argument("--list", action="store_true", help="只列出明确范围，不启动验证")
    options = parser.parse_args()
    if options.step_timeout <= 0:
        parser.error("--step-timeout 必须大于零")
    if options.list:
        for step in steps_for(options.suite, options.godot, Path("<evidence>")):
            print(json.dumps(step, ensure_ascii=False))
        return 0
    engine = shutil.which(options.godot) or options.godot
    if options.suite != "quick" and not Path(engine).is_file():
        parser.error("找不到 Godot；用 --godot 或 DOKU_GODOT 指定匹配 Spine 的引擎")
    if Path(engine).is_file():
        engine = str(Path(engine).resolve())
    if options.output and options.output.exists() and (not options.output.is_dir() or any(options.output.iterdir())):
        parser.error("--output 必须不存在或为空，避免覆盖已有证据")
    output = options.output.resolve() if options.output else Path(tempfile.mkdtemp(prefix="doku-verify-"))
    if any(output.is_relative_to((ROOT / directory).resolve()) for directory in INPUT_DIRECTORIES):
        parser.error("--output 不能位于 scripts/products/tools/addons/.autoconverted 输入目录内")
    output.mkdir(parents=True, exist_ok=True)
    environment = capture_environment(engine, output)
    before = fingerprints()
    (output / "inputs.json").write_text(json.dumps(before, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    plan = steps_for(options.suite, engine, output)
    excluded = [step["name"] for step in steps_for("all", engine, output) if step["name"] not in {item["name"] for item in plan}]
    print(f"VERIFY_WORKSPACE={output}", flush=True)
    print(f"VERIFY_SCOPE={options.suite} planned={len(plan)} excluded={','.join(excluded) or 'none'}", flush=True)
    results = []
    interrupted = False
    active_step = None
    try:
        for step in plan:
            active_step = step
            print("VERIFY_START=" + step["name"], flush=True)
            result = run_step(step, output, options.step_timeout, engine)
            results.append(result)
            active_step = None
            print(f"VERIFY_RESULT={step['name']} {'passed' if result['ok'] else 'FAILED'} log={result['log']}", flush=True)
            if result.get("error") == "interrupted":
                interrupted = True
                break
    except KeyboardInterrupt:
        interrupted = True
        if active_step is not None and (not results or results[-1]["name"] != active_step["name"]):
            # 包括子进程尚未创建、或读取完成证据时的中断；已开始的步骤不能标成未执行。
            log = output / (active_step["name"] + ".log")
            results.append({"name": active_step["name"], "command": active_step["command"], "ok": False,
                            "exit_code": None, "error": "interrupted", "log": str(log),
                            "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest() if log.exists() else "",
                            "completion": {"ok": False, "error": "interrupted"}})
    after = fingerprints()
    changed = sorted(name for name in before.keys() | after.keys() if before.get(name) != after.get(name))
    passed = sum(item["ok"] for item in results)
    ok = not interrupted and not changed and len(results) == len(plan) and passed == len(plan)
    report = {"ok": ok, "suite": options.suite, "planned": len(plan), "executed": len(results), "passed": passed,
              "excluded": excluded, "not_executed": [step["name"] for step in plan[len(results):]], "interrupted": interrupted,
              "changed_inputs": changed, "inputs": "inputs.json", "limits": LIMITS, "steps": results,
              "environment": environment, "archive_summary": "summary.json",
              "inputs_sha256": hashlib.sha256((output / "inputs.json").read_bytes()).hexdigest()}
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    archive = build_summary(output / "report.json")
    if ok and not archive["ok"]:
        ok = False
        report["ok"] = False
        report["archive_validation"] = {"ok": False, "error": "summary_validation_failed",
                                        "evidence_issues": archive.get("evidence_issues", []),
                                        "observed_unknown_count": archive.get("diagnostics", {}).get("observed_unknown_count")}
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("VERIFY_ARCHIVE_SUMMARY=" + str(write_summary(output / "report.json")), flush=True)
    print("VERIFY_SUMMARY=" + json.dumps({key: report[key] for key in ("ok", "suite", "planned", "executed", "passed", "excluded", "not_executed", "changed_inputs")}, ensure_ascii=False), flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
