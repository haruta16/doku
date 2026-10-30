#!/usr/bin/env python3
"""从保留的 verify 报告与日志生成归档摘要；不重跑验证、不调整诊断基线。"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys


DIAGNOSTIC_KEYS = ("unexpected_errors", "expected_test_errors", "environment_errors",
                   "shutdown_errors", "known_shutdown_errors", "unclassified_errors")
GROUP_FIELDS = ("steps", "checks", "branches", "product_publication_checks")
BANNER = re.compile(r"Godot Engine v([^\s]+)")
PROOF = re.compile(r"^EXPORTED_CONTENT_PROOF checks=(\d+) failures=(\d+)$")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def capture_environment(engine: str, output: Path) -> dict:
    """版本探针只在证据目录执行 --version，不打开原工程或编辑器。"""
    command = [engine, "--version"]
    text, error, exit_code = "", "", None
    try:
        result = subprocess.run(command, cwd=output, capture_output=True, text=True, timeout=10)
        text, exit_code = result.stdout + result.stderr, result.returncode
    except (OSError, subprocess.TimeoutExpired) as exception:
        error = str(exception)
    log = output / "engine-version.log"
    log.write_text(text + ("\n" + error if error else ""), encoding="utf-8")
    versions = BANNER.findall(text)
    versions += re.findall(r"(?m)^(\d+\.\d+(?:\.[^\s]+)?)\s*$", text)
    versions = sorted(set(versions))
    return {"observed_at": _now(), "system": platform.system(), "machine": platform.machine(),
            "platform": platform.platform(), "python_version": platform.python_version(), "python_executable": sys.executable,
            "engine": {"command": command, "path": engine, "version": versions[0] if len(versions) == 1 else None,
                       "versions": versions, "exit_code": exit_code, "error": error,
                       "log": log.name, "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}}


def _artifact(root: Path, name: str) -> Path:
    # verify 的顶层产物均在同一目录；归档搬家后不依赖原临时目录仍然存在。
    # 同时识别其他系统写入的路径分隔符，允许在另一平台读取保留的证据。
    return root / name.replace("\\", "/").rsplit("/", 1)[-1]


def _read(path: Path, issues: list, label: str, *, json_data: bool = False):
    try:
        text = path.read_text(encoding="utf-8")
        return json.loads(text) if json_data else text
    except (OSError, ValueError) as exception:
        issues.append({"source": label, "error": "missing_or_invalid_artifact", "detail": str(exception)})
        return None


def _records(value, pointer: str = ""):
    if isinstance(value, list):
        for index, item in enumerate(value):
            yield from _records(item, pointer + "/" + str(index))
    elif isinstance(value, dict):
        if isinstance(value.get("command"), list) and ("ok" in value or "exit_code" in value):
            yield pointer or "/", value
        else:
            for key in GROUP_FIELDS:
                if isinstance(value.get(key), list):
                    yield from _records(value[key], pointer + "/" + key)


def _engine_record(record: dict) -> bool:
    command = record.get("command", [])
    return any(flag in command for flag in ("--godot", "--headless", "--editor", "--main-pack", "--script"))


def _nonnegative(value) -> bool:
    return type(value) is int and value >= 0


def build_summary(report_path: Path) -> dict:
    root = report_path.resolve().parent
    issues, sources, uncovered, known_warnings = [], [], [], []
    report = _read(report_path, issues, report_path.name, json_data=True)
    if not isinstance(report, dict):
        return {"schema_version": 1, "generated_at": _now(), "ok": False, "source_report": report_path.name,
                "evidence_issues": issues or [{"source": report_path.name, "error": "invalid_verify_report"}]}
    diagnostics = Counter({key: 0 for key in DIAGNOSTIC_KEYS})
    versions, groups = set(), []
    if not isinstance(report.get("steps"), list) or not report.get("steps"):
        issues.append({"source": report_path.name, "error": "empty_or_invalid_group_records"})
    steps = report.get("steps", []) if isinstance(report.get("steps"), list) else []
    actual_passed = sum(isinstance(step, dict) and step.get("ok") is True for step in steps)
    planned, executed, passed = (report.get(key) for key in ("planned", "executed", "passed"))
    pending = report.get("not_executed")
    if (not all(_nonnegative(value) for value in (planned, executed, passed))
            or executed != len(steps) or passed != actual_passed
            or not isinstance(pending, list) or planned != len(steps) + len(pending)
            or (report.get("ok") is True and (planned != passed or report.get("interrupted") or report.get("changed_inputs")))):
        issues.append({"source": report_path.name, "error": "inconsistent_group_counts_or_status"})

    def record_diagnostics(value: dict, source: dict, *, required: bool) -> None:
        categories = {key: value[key] for key in DIAGNOSTIC_KEYS if isinstance(value.get(key), list)}
        classified = value.get("diagnostics_classified") is True or "unexpected_errors" in categories
        if required and not classified:
            uncovered.append({**source, "reason": "classification_not_provided"})
        if not categories and not classified and "shutdown_baseline_environment" not in value:
            return
        entry = {**source, "categories": categories, "diagnostics_classified": classified}
        for key in ("shutdown_evidence", "shutdown_baseline_environment"):
            if key in value:
                entry[key] = value[key]
        sources.append(entry)
        for category, messages in categories.items():
            diagnostics[category] += len(messages)
            if category in ("known_shutdown_errors", "environment_errors", "expected_test_errors"):
                for message, count in Counter(message for message in messages if isinstance(message, str)).items():
                    known_warnings.append({"source": source, "category": category, "message": message, "count": count})

    for step in report.get("steps", []) if isinstance(report.get("steps"), list) else []:
        if not isinstance(step, dict):
            issues.append({"source": report_path.name, "error": "invalid_group_record"})
            continue
        name = step.get("name", "unknown")
        previous_diagnostics = diagnostics.copy()
        completion = step.get("completion", {})
        completion = completion if isinstance(completion, dict) else {}
        group = {key: step[key] for key in ("name", "ok", "exit_code", "error", "elapsed_seconds", "cleanup_errors") if key in step}
        group["reported_ok"] = step.get("ok")
        counts = {key: 0 for key in ("reported_processes", "script_processes", "imports", "smokes", "cases", "counted_checks", "check_failures", "uncounted_script_processes")}
        group["counts"] = counts
        log_name = str(step.get("log", name + ".log"))
        log_path = _artifact(root, log_name)
        log = _read(log_path, issues, log_path.name)
        log = log or ""
        versions.update(BANNER.findall(log))
        group["log"] = log_path.name
        if log_path.is_file():
            digest = hashlib.sha256(log_path.read_bytes()).hexdigest()
            group["log_sha256"] = digest
            if step.get("log_sha256") and step["log_sha256"] != digest:
                issues.append({"source": log_path.name, "error": "hash_mismatch"})
        records = []
        if completion.get("report"):
            path = _artifact(root, str(completion["report"]))
            value = _read(path, issues, path.name, json_data=True)
            group["report"] = path.name
            if path.is_file():
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                group["report_sha256"] = digest
                if completion.get("sha256") and completion["sha256"] != digest:
                    issues.append({"source": path.name, "error": "hash_mismatch"})
            records = list(_records(value))
            if not records:
                issues.append({"source": path.name, "error": "no_process_records"})
            for pointer, record in records:
                command = record.get("command", [])
                counts["reported_processes"] += 1
                counts["script_processes"] += int("--script" in command)
                counts["imports"] += int("--editor" in command and "--import" in command)
                counts["smokes"] += int("--quit-after" in command and "--script" not in command)
                counts["cases"] += int("case" in record)
                measured = record.get("completion", {})
                measured = measured if isinstance(measured, dict) else {}
                if _nonnegative(measured.get("checks")):
                    counts["counted_checks"] += measured["checks"]
                elif "--script" in command:
                    counts["uncounted_script_processes"] += 1
                if _nonnegative(measured.get("failures")):
                    counts["check_failures"] += measured["failures"]
                if record.get("ok") is not True:
                    group["ok"] = False
                text = record.get("log", "")
                if isinstance(text, str) and "\n" in text:
                    versions.update(BANNER.findall(text))
                source = {"group": name, "artifact": path.name, "pointer": pointer, "command": command}
                record_diagnostics(record, source, required=_engine_record(record))
        elif name == "python":
            counts["reported_processes"] = 1
            # 失败的 unittest 摘要也保留 skips/failures/errors，不能只解析最后的 OK。
            found = re.search(r"(?m)^Ran (\d+) tests? in ", log)
            terminal = re.search(r"(?m)^(?:OK|FAILED)(?: \(([^\n]+)\))?[ \t]*$", log)
            details = dict(re.findall(r"(skipped|failures|errors)=(\d+)", terminal[1] or "")) if terminal else {}
            total = int(found[1]) if found else completion.get("tests")
            skipped = int(details.get("skipped", completion.get("skipped", 0)))
            group["python"] = {"tests": total, "executed": max(0, total - skipped) if _nonnegative(total) else None,
                               "skipped": skipped, "failures": int(details.get("failures", 0)), "errors": int(details.get("errors", 0))}
            if not found and not _nonnegative(total):
                issues.append({"source": log_path.name, "error": "missing_python_counts"})
            if group["python"]["failures"] or group["python"]["errors"]:
                group["ok"] = False
        elif name == "pck":
            counts["reported_processes"] = None  # 过滤后的日志没有每次引擎调用的命令。
            uncovered.append({"group": name, "artifact": log_path.name, "reason": "filtered_log_does_not_enumerate_engine_processes"})
            classified = Counter()
            raw = []
            for line_number, line in enumerate(log.splitlines(), 1):
                if line.startswith("Traceback (most recent call last):"):
                    break  # 异常文本可能重印 stdout，不能将同一次 proof 再计一次。
                source = {"group": name, "artifact": log_path.name, "line": line_number}
                if line.startswith("PCK_ENGINE_DIAGNOSTICS="):
                    try:
                        value = json.loads(line.split("=", 1)[1])
                        if not isinstance(value, dict):
                            raise ValueError("diagnostics must be an object")
                        record_diagnostics(value, source, required=False)
                        # shutdown 与 unexpected/known 会有同一条，原始输出只抵扣一次。
                        for message in {message for key in DIAGNOSTIC_KEYS for message in value.get(key, []) if isinstance(message, str)}:
                            classified[message] += max(value.get(key, []).count(message) for key in DIAGNOSTIC_KEYS)
                    except (ValueError, TypeError) as exception:
                        issues.append({**source, "error": "invalid_pck_diagnostics", "detail": str(exception)})
                elif match := PROOF.fullmatch(line):
                    counts["cases"] += 1
                    counts["counted_checks"] += int(match[1])
                    counts["check_failures"] += int(match[2])
                elif re.match(r"^(?:ERROR:|SCRIPT ERROR:|Parse Error:|TEST_FAILED:|PACK_VALIDATION_FAILED:|WARNING: ObjectDB instances leaked)", line):
                    raw.append((source, line))
            for source, message in raw:
                if classified[message]:
                    classified[message] -= 1
                else:
                    record_diagnostics({"unclassified_errors": [message]}, source, required=False)
            if counts["cases"] == 0:
                issues.append({"source": log_path.name, "error": "missing_pck_proof_counts"})
        else:
            counts["reported_processes"] = 1
            if name != "architecture":
                issues.append({"source": log_path.name, "error": "missing_group_report"})
        if counts["check_failures"]:
            group["ok"] = False
        group["diagnostic_counts"] = {key: diagnostics[key] - previous_diagnostics[key] for key in DIAGNOSTIC_KEYS}
        if group["diagnostic_counts"]["unexpected_errors"] or group["diagnostic_counts"]["unclassified_errors"]:
            group["ok"] = False
        group["classification_complete"] = not any(source["group"] == name for source in uncovered)
        groups.append(group)

    inputs_name = str(report.get("inputs", "inputs.json"))
    inputs_path = _artifact(root, inputs_name)
    inputs = _read(inputs_path, issues, inputs_path.name, json_data=True)
    if not isinstance(inputs, dict):
        inputs = None
    inputs_hash = hashlib.sha256(inputs_path.read_bytes()).hexdigest() if inputs_path.is_file() else None
    binding = "not_recorded"
    if "inputs_sha256" in report:
        binding = "matched" if inputs_hash is not None and report["inputs_sha256"] == inputs_hash else "mismatch"
        if binding != "matched":
            issues.append({"source": inputs_path.name, "error": "inputs_hash_mismatch"})
    environment = report.get("environment", {"source": "not_recorded", "engine": {"version": None}})
    environment = dict(environment) if isinstance(environment, dict) else {"source": "invalid_environment_record"}
    environment["observed_log_versions"] = sorted(versions)
    if environment.get("source") == "not_recorded" and len(versions) == 1:
        environment["engine"] = {"version": next(iter(versions)), "source": "retained_log_banner"}
    unknown = diagnostics["unexpected_errors"] + diagnostics["unclassified_errors"]
    return {"schema_version": 1, "generated_at": _now(), "source_report": report_path.name, "evidence_directory": str(root),
            "source_report_sha256": hashlib.sha256(report_path.read_bytes()).hexdigest(),
            "ok": report.get("ok") is True and not issues and unknown == 0 and all(group.get("ok") is True for group in groups),
            "reported_ok": report.get("ok"), "environment": environment,
            "scope": {key: report.get(key) for key in ("suite", "planned", "executed", "passed", "excluded", "not_executed", "interrupted", "changed_inputs")},
            "inputs": {"artifact": inputs_path.name, "count": len(inputs) if inputs is not None else None,
                       "sha256": inputs_hash, "hash_binding": binding, "expected_sha256": report.get("inputs_sha256")},
            "groups": groups, "diagnostics": {"counts": dict(diagnostics), "observed_unknown_count": unknown,
                "unknown_count": unknown if not uncovered else None, "classification_complete": not uncovered,
                "unclassified_sources": uncovered, "sources": sources,
                "note": "Categories may overlap (shutdown is also known or unexpected); counts cover retained evidence, not unreported nested processes."},
            "known_warnings": known_warnings, "evidence_issues": issues, "limits": report.get("limits", [])}


def write_summary(report_path: Path) -> Path:
    destination = report_path.parent / "summary.json"
    destination.write_text(json.dumps(build_summary(report_path), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="保留的 verify report.json")
    args = parser.parse_args()
    print(write_summary(args.report.resolve()))
