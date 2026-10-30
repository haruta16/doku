#!/usr/bin/env python3
"""在临时工程副本运行 Godot 检查；不读写日常游戏存档。"""
from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

from check_architecture import check as check_architecture


ROOT = Path(__file__).resolve().parents[1]
EXTERNAL_FIXTURE_TESTS = {
    "test_content_delivery.gd", "test_content_boot_failure.gd", "test_content_spine.gd",
    "test_content_updates.gd", "test_content_update_bootstrap.gd",
}
SUITES = ("recovery", "framework", "storage", "gameplay", "content")
RECOVERY_SCRIPTS = ["res://tools/validate_recovery.gd", "res://tools/verify_level_bank_roundtrip.gd", "res://tools/verify_board_teardown.gd"]
SHUTDOWN_LEDGER = json.loads((ROOT / "tools/validation/fixtures/shutdown_diagnostics.json").read_text())
SHUTDOWN_BASELINES = SHUTDOWN_LEDGER["baselines"]


def suite_scripts(source: Path, suite: str) -> list[str]:
    """自动纳入新的自包含回归；签名/HTTP/PCK 的外部夹具仍由专用 runner 构建。"""
    if suite == "recovery":
        return list(RECOVERY_SCRIPTS)
    paths = sorted((source / "tools/validation").glob("test_*.gd"))
    selected = []
    for path in paths:
        name = path.name
        if name in EXTERNAL_FIXTURE_TESTS:
            continue
        if suite == "storage" and not name.startswith(("test_storage", "test_framework")):
            continue
        if suite == "gameplay" and not name.startswith(("test_doku", "test_round", "test_game_", "test_daily_", "test_product", "test_block")):
            continue
        if suite == "content" and not name.startswith("test_content"):
            continue
        selected.append("res://" + path.relative_to(source).as_posix())
    return (list(RECOVERY_SCRIPTS) if suite == "framework" else []) + selected


def prepare(source: Path, target: Path) -> Path:
    project = target / "project"
    project.mkdir(parents=True)
    data = target / "userdata"
    data.mkdir()
    for name in ("scripts", "products", "addons", "tools", ".autoconverted"):
        if (source / name).exists():
            shutil.copytree(source / name, project / name,
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for name in ("project.godot", "icudt_godot.dat", "unikit_config.tres", "lxauth_android_config.tres"):
        if (source / name).exists():
            shutil.copy2(source / name, project / name)
    evidence = source / "docs/recovery/1.22.0"
    if evidence.is_dir():
        shutil.copytree(evidence, project / "docs/recovery/1.22.0")
    # 复制导入缓存而不是链接：Godot 可以重建缓存，但不能改动源工程缓存。
    cache = source / ".godot"
    if cache.exists():
        # 类名/UID 索引必须按副本的当前路径重建，不能带入目录迁移前的索引。
        for name in ("imported",):
            src = cache / name
            dst = project / ".godot" / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.is_dir():
                shutil.copytree(src, dst)
            elif src.is_file():
                shutil.copy2(src, dst)
    # Godot 的 custom_user_dir_name 只接受数据目录下的名字，不接受任意绝对路径。
    # 仅在副本重定向业务文件路径；原始源码、日常存档和系统 HOME 都不改变。
    for folder in ("scripts", "products", "addons", "tools"):
        for path in (project / folder).rglob("*.gd"):
            text = path.read_text()
            text = text.replace("user://", data.as_posix() + "/")
            text = text.replace("OS.get_user_data_dir()", json.dumps(data.as_posix()))
            path.write_text(text)
    config = (project / "project.godot").read_text()
    # Native/editor code can access Godot's own user:// independently of script rewriting.
    # macOS does not support an absolute custom user directory; keep its identity unique
    # to this fixture so an engine/plugin can never read the product's real save directory.
    if re.search(r"(?m)^config/use_custom_user_dir=true$", config):
        isolated_name = "DokuIsolatedValidation/" + target.name
        config = re.sub(r'(?m)^config/custom_user_dir_name=.*$',
                        'config/custom_user_dir_name=' + json.dumps(isolated_name), config)
    config = re.sub(r"(?ms)^\[editor_plugins\].*?(?=^\[|\Z)", "[editor_plugins]\nenabled=PackedStringArray()\n\n", config)
    # 工具自身的网络服务和编辑器遥控不属于玩法验收，避免抢占开发中的端口。
    for autoload in ("DebugApiServerManager", "ScreenshotHotkey", "MCPScreenshot", "MCPInputService", "MCPGameInspector"):
        config = re.sub(rf'(?m)^{autoload}=.*\n', '', config)
    config = re.sub(r"(?m)^validation/offline=.*\n", "", config)
    if "[doku]" in config:
        config = config.replace("[doku]", "[doku]\nvalidation/offline=true", 1)
    else:
        config += "\n[doku]\nvalidation/offline=true\n"
    isolate_product_transports(project)
    (target / ".isolated-validation").write_text("doku-isolated-validation-v2\n")
    (project / "project.godot").write_text(config)
    return project


def isolate_product_transports(project: Path) -> None:
    """Only the temporary copy gets offline failures; do not manufacture server success.

    Guard the actual request methods, including callers bypassing their public wrapper.
    Signatures are checked exactly: drift must stop preparation rather than leave a
    newly shaped production transport active. Editor plugins and MCP are disabled
    separately; intentionally local content HTTP fixtures use their own runners.
    """
    offline = 'ProjectSettings.get_setting("doku/validation/offline", false)'
    guards = {
        "products/meowdoku/app/network/http_client.gd": (
            'func _send(method: int, path: String, raw_body: String, bearer: String) -> ApiResponse:\n',
            '\tif %s:\n\t\treturn _net_fail("isolated_validation_offline")\n' % offline),
        "products/meowdoku/app/features/level_rec/net/rec_http.gd": (
            'func post(path: String, body: Dictionary) -> Dictionary:\n',
            '\tif %s:\n\t\treturn {"ok": false, "http_status": 0, "code": -1, "message": "isolated_validation_offline", "data": {}}\n' % offline),
        "products/meowdoku/app/features/data_sync/data_sync_manager.gd": (
            'func _resolve_sync_enabled() -> bool:\n',
            '\tif %s:\n\t\t_sync_enabled_source = "isolated_validation"\n\t\treturn false\n' % offline),
    }
    for relative, (signature, guard) in guards.items():
        path = project / relative
        if not path.is_file():
            continue  # Small independent framework fixtures omit product services.
        source = path.read_text()
        if source.count(signature) != 1:
            raise ValueError("Cannot safely isolate production transport: " + relative)
        path.write_text(source.replace(signature, signature + guard, 1))



def assert_isolated_product(project: Path) -> None:
    """Recheck the actual fixture before every launch, including incremental refreshes."""
    transport = project / "products/meowdoku/app/network/http_client.gd"
    if not transport.exists():
        return  # Independent framework fixtures have no product transports.
    marker = project.parent / ".isolated-validation"
    config = (project / "project.godot").read_text()
    if not marker.is_file() or marker.read_text() != "doku-isolated-validation-v2\n":
        raise ValueError("Product validation requires a prepared isolated fixture")
    if not re.search(r"(?m)^validation/offline=true$", config):
        raise ValueError("Product validation offline setting is missing")
    if re.search(r"(?m)^(DebugApiServerManager|ScreenshotHotkey|MCPScreenshot|MCPInputService|MCPGameInspector)=", config):
        raise ValueError("Product validation remote-control autoload is enabled")
    expected_name = "DokuIsolatedValidation/" + project.parent.name
    if 'config/custom_user_dir_name=' + json.dumps(expected_name) not in config:
        raise ValueError("Product validation engine data directory is not isolated")
    if not re.search(r"(?ms)^\[editor_plugins\]\s*enabled=PackedStringArray\(\)", config):
        raise ValueError("Product validation editor plugins are enabled")
    guards = {
        "products/meowdoku/app/network/http_client.gd": '\tif ProjectSettings.get_setting("doku/validation/offline", false):\n\t\treturn _net_fail("isolated_validation_offline")',
        "products/meowdoku/app/features/level_rec/net/rec_http.gd": '\tif ProjectSettings.get_setting("doku/validation/offline", false):\n\t\treturn {"ok": false, "http_status": 0, "code": -1, "message": "isolated_validation_offline", "data": {}}',
        "products/meowdoku/app/features/data_sync/data_sync_manager.gd": '\tif ProjectSettings.get_setting("doku/validation/offline", false):\n\t\t_sync_enabled_source = "isolated_validation"\n\t\treturn false',
    }
    for relative, guard in guards.items():
        path = project / relative
        if not path.is_file() or guard not in path.read_text():
            raise ValueError("Product validation transport guard is missing: " + relative)


def has_reported_failures(output: str) -> bool:
    # 两种摘要格式不能重叠：checks=18 failures=0 中的 18 属于 checks。
    counts = re.findall(r"\bfailures[ \t]*=[ \t]*(\d+)\b|\b(\d+)[ \t]+failures\b(?![ \t]*=)", output)
    return any(int(left or right) > 0 for left, right in counts)


# 这些最小工程不使用引擎默认数据目录。仅容忍已实测的沙箱建目录失败，
# 真实存档/资源错误仍失败；脚本与项目名必须同时匹配。
FIXTURE_SCRIPTS = {
    "UI Framework Tests": {"res://tools/validation/test_ui_framework.gd"},
    "Framework Boundary Tests": {"res://tools/validation/fixtures/framework_consumer.gd"},
    "Doku Business Boundary": {"res://tools/validation/test_product_session.gd", "res://tools/validation/test_product_settlement.gd"},
    "DokuContentValidation": {"res://tools/content/validate_product.gd"},
    "ContentPacker": {"res://pack.gd"},
    "Block Framework Example": {"", "res://tools/validation/test_block_example.gd"},
}


def _fixture_directory_error(line: str, context: str, output: str, script: str, editor: bool) -> bool:
    for name, scripts in FIXTURE_SCRIPTS.items():
        if not editor and script not in scripts:
            continue
        suffix = "/Godot/app_userdata/" + name
        if re.fullmatch(r"ERROR: Could not create directory: '.*" + re.escape(suffix) + r"'\.", line) and "make_dir_recursive" in context:
            return True
        if re.fullmatch(r"ERROR: Error attempting to create data dir: .*" + re.escape(suffix) + r"\.", line) and "ensure_user_data_dir" in context:
            return True
        if editor and suffix in output and line == "ERROR: Could not open 'user://' directory: 'user://'." and "objectdb_profiler" in context:
            return True
    return False


def _script_argument(args: list[str]) -> str:
    return args[args.index("--script") + 1] if "--script" in args else ""


def _shutdown_baseline(args: list[str]) -> dict:
    script = _script_argument(args)
    if "--editor" in args:
        return {}
    if script:
        return SHUTDOWN_BASELINES.get(script, {})
    # 只有本运行器的隔离产品工程、固定 600 帧 smoke 可使用既有退出证据。
    # 独立示例、其他工具和编辑器不能因没有 --script 而继承产品例外。
    if "--path" in args and "--quit-after" in args:
        project = Path(args[args.index("--path") + 1])
        frames = args[args.index("--quit-after") + 1]
        if project.name == "project" and project.parent.name.startswith("doku-validation-") and frames == "600":
            return SHUTDOWN_BASELINES.get("product-smoke-600", {})
    return {}


def _shutdown_environment(output: str, baseline: dict) -> dict:
    # 采用本次子进程实际输出的版本，不能用 --godot 路径或历史报告推断。
    # OS 系列与当前架构必须一致；不把相同文案自动扩展为其他引擎/平台的例外。
    versions = re.findall(r"^Godot Engine v([^\s]+)(?:[ \t]|$)", output, re.M)
    observed = {"system": platform.system(), "machine": platform.machine(),
                "godot_version": versions[0] if len(versions) == 1 else None}
    expected = dict(SHUTDOWN_LEDGER["environment"])
    mismatched = [key for key in expected if observed.get(key) != expected[key]]
    if not baseline:
        reason = "unregistered_scope"
    elif not versions:
        reason = "missing_engine_version"
    elif len(versions) != 1:
        reason = "ambiguous_engine_version"
    elif mismatched:
        reason = "environment_mismatch"
    else:
        reason = "matched"
    return {"applicable": reason == "matched", "reason": reason, "expected": expected,
            "observed": observed, "mismatched_fields": mismatched,
            **({"version_banners": versions} if len(versions) > 1 else {})}


def classify_engine_errors(output: str, args: list[str]) -> dict:
    """未知 ERROR 一律失败；只放过明确的环境消息和测试有意注入的故障。"""
    clean = re.sub(r"\x1b\[[0-9;]*m", "", output)
    lines = clean.splitlines()
    script = _script_argument(args)
    is_test = script.startswith("res://tools/validation/test_")
    categories = {"unexpected_errors": [], "expected_test_errors": [], "environment_errors": [],
                  "shutdown_errors": [], "known_shutdown_errors": [], "shutdown_evidence": []}
    baseline = _shutdown_baseline(args)
    environment = _shutdown_environment(clean, baseline)
    remaining = Counter(baseline.get("diagnostics", []) if environment["applicable"] else [])
    for index, line in enumerate(lines):
        if line.startswith("SCRIPT ERROR:") or (line.startswith("WARNING: AnimationMixer") and "couldn't resolve track:" in line):
            categories["unexpected_errors"].append(line)
            continue
        if (re.fullmatch(r"WARNING: ObjectDB instances leaked at exit(?: \(run with --verbose for details\))?\.", line)
                or re.fullmatch(r"ERROR: \d+ resources still in use at exit(?: \(run with --verbose for details\))?\.", line)):
            categories["shutdown_errors"].append(line)
            categories["shutdown_baseline_environment"] = environment
            if remaining[line] > 0:
                remaining[line] -= 1
                categories["known_shutdown_errors"].append(line)
                if not categories["shutdown_evidence"]:
                    categories["shutdown_evidence"] = [baseline["report"], "log_sha256=" + baseline["log_sha256"]]
            else:
                categories["unexpected_errors"].append(line)
            continue
        if not line.startswith("ERROR:"):
            continue
        context = "\n".join(lines[index + 1:index + 3])
        if line == 'ERROR: Condition "ret != noErr" is true. Returning: ""' and "get_system_ca_certificates" in context:
            category = "environment_errors"
        elif "--editor" in args and re.fullmatch(r"ERROR: (?:Cannot save file '.*editor_settings-4\.6\.tres'\.|Error saving editor settings to .*editor_settings-4\.6\.tres)", line):
            category = "environment_errors"
        elif _fixture_directory_error(line, context, clean, script, "--editor" in args):
            category = "environment_errors"
        elif is_test and re.fullmatch(r'ERROR: \[(?:GameState|AwardManager|UniKitManager)\].*"error": "write_failed".*"detail": "注入替换前中断".*', line):
            category = "expected_test_errors"
        elif script.endswith("/test_game_reward_restore_lifecycle.gd") and re.fullmatch(r'ERROR: \[AdRewardRestoredPage\].*"error": "write_failed".*"detail": "注入替换前中断".*', line):
            category = "expected_test_errors"
        elif (script in {"res://tools/validation/test_storage.gd", "res://tools/validation/test_storage_initialization.gd"}
              and line == 'ERROR: Condition "magic != 0x43454447" is true. Returning: ERR_FILE_UNRECOGNIZED'
              and "open_and_parse" in context):
            category = "expected_test_errors"
        elif (script == "res://tools/validation/test_122_business_storage.gd"
              and re.fullmatch(r"ERROR: ConfigFile parse error at .*/doku-validation-[^/]+/project/fixtures/legacy/purchase\.cfg:0: Unexpected EOF while parsing simple tag\.", line)):
            # This exact fixture is deliberately truncated to assert fail-closed migration.
            category = "expected_test_errors"
        elif script.endswith("/test_content_tutorial_boot_failure.gd") and line == "ERROR: TutorialPage: 教学棋盘未能完整创建":
            category = "expected_test_errors"
        elif script.endswith("/test_game_page_lifecycle.gd") and re.fullmatch(r"ERROR: DailyGamePage: invalid solution day_offset=\d+ virtual_idx=\d+ transform=\d+ entry_idx=0, advancing", line):
            category = "expected_test_errors"
        elif script == "res://boot-failure.gd" and "resume" not in args and (
            (line == 'ERROR: Condition "!success" is true. Returning: ERR_FILE_CORRUPT' and "png_to_image (drivers/png/png_driver_common.cpp:" in context)
            or (line == "ERROR: Error loading image: 'res://content/test/broken-image/broken.png'." and "load_image (core/io/image_loader.cpp:" in context)
        ):
            category = "expected_test_errors"
        else:
            category = "unexpected_errors"
        categories[category].append(line)
    return {key: value for key, value in categories.items() if value}


def completion_contract(output: str, args: list[str], contract: str | None = None) -> dict:
    """测试需要实际检查数与完成摘要；导入、定帧 smoke、恢复和制作工具各有自己的合同。

    专用 runner 可给复制后的脚本别名显式传 test；制作工具通过已知路径或
    tool:MARKER 指定完成标记。不会把任意 PASS 或退出 0 当成测试执行过的证据。
    """
    script = _script_argument(args)
    if contract is None:
        if "--editor" in args and "--import" in args and not script:
            contract = "import"
        elif script == "res://tools/validate_recovery.gd":
            contract = "recovery"
        elif script == "res://tools/verify_level_bank_roundtrip.gd":
            contract = "bank_roundtrip"
        elif script == "res://tools/content/validate_product.gd":
            contract = "tool:PRODUCT_VALIDATED"
        elif script == "res://tools/content/verify_pack.gd":
            contract = "tool:PACK_VALIDATED"
        elif not script and "--quit-after" in args:
            contract = "smoke"
        else:
            contract = "test"
    clean = re.sub(r"\x1b\[[0-9;]*m", "", output)
    if contract == "import":
        return {"kind": contract, "ok": "--editor" in args and "--import" in args and not script}
    if contract == "smoke":
        frames = args[args.index("--quit-after") + 1] if "--quit-after" in args else ""
        return {"kind": contract, "ok": not script and frames.isdigit() and int(frames) > 0}
    if contract == "recovery":
        marker = re.search(r"^VALIDATION_OK: [1-9][\d,]* recovered scripts, [1-9]\d* scenes, [1-9]\d* translations, "
                           r"[1-9]\d* level banks, [1-9][\d,]* records, and [1-9][\d,]* solution entries$", clean, re.M)
        return {"kind": contract, "ok": marker is not None,
                **({"summary": marker.group()} if marker else {"error": "missing_recovery_completion"})}
    if contract == "bank_roundtrip":
        marker = re.search(r"^ENCRYPTOR_ROUNDTRIP_OK: 59 files$", clean, re.M)
        return {"kind": contract, "ok": marker is not None}
    if contract.startswith("tool:"):
        marker = contract.removeprefix("tool:")
        matched = re.search(r"^" + re.escape(marker) + r"(?::|[ \t])[ \t]*\S.*$", clean, re.M) if marker else None
        return {"kind": contract, "ok": matched is not None,
                **({"summary": matched.group()} if matched else {"error": "missing_tool_completion"})}
    if contract != "test":
        return {"kind": contract, "ok": False, "error": "unknown_completion_contract"}
    summaries = []
    for line in clean.splitlines():
        checks = re.search(r"\b(?:checks|assertions)\s*=\s*(\d+)\b|\b(\d+)\s+assertions\b", line)
        failures = re.search(r"\bfailures\s*=\s*(\d+)\b|\b(\d+)\s+failures\b(?!\s*=)", line)
        if checks and failures:
            summaries.append({"checks": int(checks.group(1) or checks.group(2)),
                              "failures": int(failures.group(1) or failures.group(2)), "summary": line})
    if len(summaries) != 1:
        return {"kind": contract, "ok": False,
                "error": "missing_test_completion" if not summaries else "ambiguous_test_completion"}
    summary = summaries[0]
    passed = summary["checks"] > 0 and summary["failures"] == 0
    return {"kind": contract, "ok": passed, **summary,
            **({} if passed else {"error": "zero_checks" if summary["checks"] == 0 else "reported_failures"})}


def run(engine: str, project: Path, output: Path, args: list[str], timeout: int, rendered: bool = False,
        *, completion: str | None = None) -> dict:
    assert_isolated_product(project)
    command = [engine, *([] if rendered else ["--headless"]), "--path", str(project), "--log-file", str(output.with_suffix(".engine.log")), *args]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        combined = result.stdout + result.stderr
        output.write_text(combined)
        bad = any(marker in combined for marker in ("SCRIPT ERROR:", "Parse Error:", "VALIDATION_FAILED:", "TEST_FAILED:"))
        # 即使某个测试忘记用非零退出码，非零失败计数也不能显示为通过。
        bad = bad or has_reported_failures(combined)
        diagnostics = classify_engine_errors(combined, command)
        bad = bad or bool(diagnostics.get("unexpected_errors"))
        # Historical shutdown evidence explains an old diagnostic; it is not a
        # waiver for the migrated implementation's current acceptance run.
        bad = bad or bool(diagnostics.get("shutdown_errors"))
        completed = completion_contract(combined, args, completion)
        passed = result.returncode == 0 and not bad and completed["ok"]
        summary = "\n".join(line for line in combined.splitlines()
                            if any(marker in line for marker in ("PASS:", "TESTS:", "VALIDATION_OK:", "GAME ENTRY FLOW:", "failures=", "PERFORMANCE_RESULT=")))
        return {"command": command, "exit_code": result.returncode, "ok": passed,
                "log": str(output), "summary": summary if passed else combined[-2500:], "completion": completed,
                "diagnostics_classified": True, **diagnostics}
    except subprocess.TimeoutExpired as error:
        def decode(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
        output.write_text(decode(error.stdout) + decode(error.stderr))
        return {"command": command, "ok": False, "error": "timeout", "log": str(output)}


def import_project(engine: str, project: Path, output: Path, timeout: int) -> list[dict]:
    """隔离工程先导入字体，再按完整配置导入；两步都通过同一严格错误门禁。"""
    config_path = project / "project.godot"
    original = config_path.read_text()
    gui = re.search(r"(?ms)^\[gui\][ \t]*\n.*?(?=^\[|\Z)", original)
    font = re.search(r"(?m)^theme/custom_font[ \t]*=[ \t]*(.+)$", gui.group()) if gui else None
    if font is None or font.group(1).strip() in ('""', 'null'):
        return [run(engine, project, output, ["--editor", "--import"], timeout)]
    # Godot 在资源扫描前初始化项目主题。干净工程的 fontdata 此时尚未生成，
    # 因此只在测试副本首轮暂去掉这一设置；不能忽略 missing-resource 报错。
    section = gui.group()
    without_font = re.sub(r"(?m)^theme/custom_font[ \t]*=.*(?:\n|$)", "", section)
    bootstrap_config = original[:gui.start()] + without_font + original[gui.end():]
    try:
        config_path.write_text(bootstrap_config)
        bootstrap = run(engine, project, output.with_name(output.stem + "-bootstrap" + output.suffix), ["--editor", "--import"], timeout)
        bootstrap["phase"] = "resource_import_without_project_custom_font"
    finally:
        # 包括超时、失败或异常；后续验证不能沿用删掉字体的简化配置。
        config_path.write_text(original)
    results = [bootstrap]
    if bootstrap["ok"]:
        complete = run(engine, project, output, ["--editor", "--import"], timeout)
        complete["phase"] = "full_project_configuration_import"
        results.append(complete)
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--source", type=Path, default=ROOT)
    parser.add_argument("--script", action="append", default=[])
    parser.add_argument("--suite", choices=SUITES, help="framework 为全部自包含回归；内容HTTP/PCK夹具仍运行 tools/content/run_tests.py")
    parser.add_argument("--list", action="store_true", help="只列出所选测试，不复制或启动工程")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--rendered", action="store_true", help="测试与smoke使用图形窗口；导入仍为headless")
    parser.add_argument("--timeout", type=int, default=300)
    options = parser.parse_args(argv)
    scripts = list(dict.fromkeys((suite_scripts(options.source.resolve(), options.suite) if options.suite else []) + options.script))
    if not options.suite and not options.script:
        scripts = ["res://tools/validate_recovery.gd"]
    if not scripts:
        parser.error("所选 suite 没有验证脚本，不能以空套件宣称通过")
    missing = [script for script in scripts if not script.startswith("res://") or not (options.source / script.removeprefix("res://")).is_file()]
    if missing:
        parser.error("找不到验证脚本: " + ", ".join(missing))
    if options.list:
        print("\n".join(scripts))
        return 0
    scope = options.suite or ("custom" if options.script else "recovery")
    if options.suite and options.script:
        scope += "+custom"
    print("VALIDATION_SCOPE=" + json.dumps({"scope": scope, "planned_scripts": len(scripts),
                                           "smoke_requested": options.smoke}, ensure_ascii=False), flush=True)
    if options.suite == "framework":
        violations = check_architecture(options.source.resolve())
        for violation in violations:
            print("ARCHITECTURE_FAILED: " + violation, flush=True)
        if violations:
            print("VALIDATION_SUMMARY=" + json.dumps({
                "scope": scope, "planned_scripts": len(scripts), "executed_scripts": 0,
                "passed_scripts": 0, "failed_scripts": 0, "skipped_scripts": len(scripts),
                "import_steps": 0, "smoke_requested": options.smoke, "smoke_executed": False,
                "smoke_ok": None, "known_shutdown_diagnostics": 0, "report": None,
                "ok": False, "error": "architecture_boundary_failed"}, ensure_ascii=False), flush=True)
            return 1
        print("ARCHITECTURE_OK: explicit framework/product/example/domain resource boundaries", flush=True)
    target = Path(tempfile.mkdtemp(prefix="doku-validation-"))
    project = prepare(options.source.resolve(), target)
    print(f"VALIDATION_WORKSPACE={target}", flush=True)
    results = import_project(options.godot, project, target / "import.log", options.timeout)
    import_steps = len(results)
    script_results = []
    smoke_result = None
    for imported in results:
        print(json.dumps(imported, ensure_ascii=False), flush=True)
    if results[-1]["ok"]:
        for index, script in enumerate(scripts):
            fresh_userdata(target, f"before-test-{index}")
            tested = run(options.godot, project, target / f"test-{index}.log", ["--script", script], options.timeout, options.rendered)
            script_results.append(tested)
            results.append(tested)
            print(json.dumps(tested, ensure_ascii=False), flush=True)
        if options.smoke:
            fresh_userdata(target, "before-smoke")
            smoke_result = run(options.godot, project, target / "smoke.log", ["--quit-after", "600"], options.timeout, options.rendered)
            results.append(smoke_result)
            print(json.dumps(results[-1], ensure_ascii=False), flush=True)
    (target / "report.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    artifacts = project / "validation_artifacts"
    if artifacts.exists():
        print("VALIDATION_ARTIFACTS=" + str(artifacts), flush=True)
    passed = bool(results) and all(item["ok"] for item in results) and len(script_results) == len(scripts)
    summary = {"scope": scope, "planned_scripts": len(scripts), "executed_scripts": len(script_results),
               "passed_scripts": sum(item["ok"] for item in script_results),
               "failed_scripts": sum(not item["ok"] for item in script_results),
               "skipped_scripts": len(scripts) - len(script_results), "import_steps": import_steps,
               "smoke_requested": options.smoke, "smoke_executed": smoke_result is not None,
               "smoke_ok": smoke_result["ok"] if smoke_result is not None else None,
               "known_shutdown_diagnostics": sum(len(item.get("known_shutdown_errors", [])) for item in results),
               "report": str(target / "report.json"), "ok": passed}
    (target / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    print("VALIDATION_SUMMARY=" + json.dumps(summary, ensure_ascii=False), flush=True)
    return 0 if passed else 1


def fresh_userdata(target: Path, label: str) -> None:
    """每个测试进程独立；保留前一份临时存档供排查，不复用它影响下一测试。"""
    data = target / "userdata"
    data.rename(target / f"userdata-{label}")
    data.mkdir()


if __name__ == "__main__":
    raise SystemExit(main())
