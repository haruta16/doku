#!/usr/bin/env python3
"""Exercise real Meowdoku publication contracts in disposable projects and releases."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from run_validation import classify_engine_errors, has_reported_failures


def evaluate_publication_result(exit_code: int, log: str, *, rejection: str,
                                artifact_exists: bool, signature_exists: bool) -> dict:
    """An expected business rejection never excuses an engine failure alongside it."""
    # A nested validator may forward the first engine line as RuntimeError's
    # message. Preserve the raw log but classify that line as engine output too.
    diagnostic_log = re.sub(r"(?m)^(?:RuntimeError|ValueError): (?=(?:ERROR|SCRIPT ERROR|WARNING):)", "", log)
    diagnostics = classify_engine_errors(diagnostic_log, [])
    engine_failed = (bool(diagnostics.get("unexpected_errors"))
                     or bool(diagnostics.get("shutdown_errors"))
                     or has_reported_failures(log)
                     or any(marker in log for marker in ("SCRIPT ERROR:", "Parse Error:")))
    completed = (exit_code != 0 and rejection in log and not artifact_exists) if rejection else (
        exit_code == 0 and "PRODUCT_VALIDATED:" in log and signature_exists)
    return {"ok": bool(completed and not engine_failed),
            "diagnostics_classified": True, **diagnostics}


def persist_case_log(directory: Path, name: str, log: str, report: Path | None = None) -> dict:
    """Keep raw case output outside the publisher's disposable project directory."""
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / (name + ".log")
    path.write_text(log, encoding="utf-8")
    record = {"log": str(path), "log_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    if report is not None:
        record["log_relative"] = os.path.relpath(path, report.resolve().parent)
    return record


def merge_publication_checks(report: dict, checks: list[dict]) -> dict:
    report = dict(report)
    report["product_publication_checks"] = checks
    # These checks replace the previous publication run. Recompute the summary
    # from retained delivery steps and current cases, not the old summary bit.
    report["ok"] = all(step.get("ok", False) for step in report.get("steps", [])) and all(check.get("ok", False) for check in checks)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--report", type=Path, help="Append product_publication_checks to a JSON report")
    args = parser.parse_args()
    checks = []
    case_logs = (args.report.resolve().with_name(args.report.stem + "-case-logs")
                 if args.report else Path(tempfile.mkdtemp(prefix="doku-product-publication-case-logs-")))
    case_logs.mkdir(parents=True, exist_ok=True)
    print("PRODUCT_PUBLICATION_LOGS=" + str(case_logs), flush=True)
    with tempfile.TemporaryDirectory(prefix="doku-product-publication-") as directory:
        work = Path(directory).resolve()
        key = work / "private.pem"
        subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(key)], check=True, capture_output=True)
        raw = work / "raw"
        raw.mkdir()
        shutil.copyfile(ROOT / "products/meowdoku/assets/sprites/game/icon_mark_white_2.png", raw / "mark.png")
        catalog = {"schema": 1, "levels": {"21": {
            "puzzle": {"bank": "doku/levels/bankdata4x4", "rank": 1, "index": 1},
            "prefill": [[0, 2]],
            "rules": {"initial_lives": 3, "draft_unlock_level": 21},
            "reward": {"hint": 1},
        }}}

        def publish(name: str, files: dict, *, raw_assets: Path | None = None,
                    spine_assets: Path | None = None, rejection: str = "", description: str) -> None:
            source, output = work / name / "source", work / "releases" / name
            for relative, value in files.items():
                target = source / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(json.dumps(value), encoding="utf-8")
            command = [sys.executable, str(ROOT / "tools/content/build_release.py"),
                       "--source", str(source), "--output", str(output),
                       "--product", "meowdoku", "--release", name,
                       "--runtime", "godot-4.6.1-spine-4.2-data-v2", "--key", str(key),
                       "--godot", args.godot]
            if raw_assets is not None:
                command += ["--raw-assets", str(raw_assets)]
            if spine_assets is not None:
                command += ["--spine-assets", str(spine_assets)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=240)
            log = result.stdout + result.stderr
            verdict = evaluate_publication_result(result.returncode, log, rejection=rejection,
                                                 artifact_exists=output.exists(),
                                                 signature_exists=(output / "manifest.sig").is_file())
            valid = verdict["ok"]
            checks.append({"case": name, "command": command, "exit_code": result.returncode,
                           **verdict, "expected_rejection": rejection or None,
                           "artifact_exists": output.exists(), "summary": description,
                           **persist_case_log(case_logs, name, log, args.report)})
            print(f"PRODUCT_PUBLICATION {name}: {'passed' if valid else 'FAILED'} — {description}", flush=True)
            if not valid:
                print(log[-12000:], file=sys.stderr)

        policy = {"doku/policy.json": {"schema": 1, "draft_unlock_level": 21}}
        publish("catalog", {**policy, "doku/level_catalog.json": catalog},
                description="Fixed level resolves built-in puzzle, prefill, rules and reward before signing")
        catalog["levels"]["21"]["media"] = {"game/mark": "theme/tutorial/mark"}
        publish("unknown-inherited-media", {**policy, "doku/level_catalog.json": catalog},
                rejection="level_media_missing:theme/tutorial/mark",
                description="JSON-only cannot assume that an earlier media release provides a new alias")
        raw_files = {**policy, "doku/level_catalog.json": catalog,
                     "media.json": {"textures": {"game/mark": "mark.png", "theme/tutorial/mark": "mark.png"}}}
        publish("raw-correct", raw_files, raw_assets=raw,
                description="Original 32×168 game/mark texture and a per-level alias pass the fixed binding contract")
        wrong_scope = json.loads(json.dumps(catalog))
        wrong_scope["levels"]["21"]["media"] = {"ui/home/logo": "theme/tutorial/mark"}
        publish("per-level-home-slot", {**raw_files, "doku/level_catalog.json": wrong_scope}, raw_assets=raw,
                rejection="content_schema:doku/level_catalog",
                description="Global home slot cannot pass publication as a per-level alias without a consumer")
        gc_source = json.loads((ROOT / "products/meowdoku/assets/editor/levels/bankDataGC6x6.json").read_text())["levels"][0]
        publish("gc-correct", {"doku/levels/bankdatagc6x6.json": {"levels": [gc_source]}},
                description="GC publication uses the same levels wrapper and per-entry rank as the actual consumer")
        publish("gc-wrong-shape", {"doku/levels/bankdatagc6x6.json": {"1": [gc_source]}},
                rejection="content_schema:doku/levels/bankdatagc6x6",
                description="Rank-keyed GC data is rejected instead of silently producing an empty runtime bank")
        small = json.loads((ROOT / "products/meowdoku/assets/editor/levels/bankData4x4.json").read_text())
        publish("main-first-rank-missing", {"doku/levels/bankdata4x4.json": {"2": [small["2"][0]]}},
                rejection="main_pool_missing",
                description="Valid rank 2 puzzles cannot remove the first main level's rank 1 pool")
        publish("main-combined-source", {"doku/levels/bankdata4x4.json": {"2": [small["2"][0]]},
                                          "doku/levels/bankdatalkstyle4x4.json": {"1": [small["1"][0]]}},
                description="Main availability uses the union of eligible bank sources")
        publish("main-late-policy-missing", {"doku/levels/bankdata4x4.json": {"1": [small["1"][0]]},
                "doku/policy.json": {"schema": 1, "size_cycles": {"base": [
                    {"from": 1, "sizes": [7]}, {"from": 1000001, "sizes": [4]}]}}},
                rejection="main_pool_missing",
                description="An unreachable difficulty in a far-future size segment is rejected before signing")
        publish("main-ab-size-missing", {"doku/levels/bankdata4x4.json": {"1": [small["1"][0]]},
                "doku/policy.json": {"schema": 1, "size_cycles": {"8": [
                    {"from": 1, "sizes": [7]}, {"from": 1000001, "sizes": [4]}]}}},
                rejection="main_pool_missing",
                description="GamePage's size AB overrides share the publication availability contract")
        daily_regular = json.loads((ROOT / "products/meowdoku/assets/editor/levels/bankData10x10.json").read_text())
        publish("daily-missing-rank", {"doku/levels/bankdata10x10.json": {"1": [daily_regular["1"][0]]}},
                rejection="daily_pool_missing",
                description="Valid individual puzzles cannot remove a required daily difficulty pool")
        daily_style = json.loads((ROOT / "products/meowdoku/assets/editor/levels/bankDataLKStyle12x12.json").read_text())
        daily_style["4"] = [entry for entry in daily_style["4"] if entry.get("tier") != "N"]
        publish("daily-missing-tier", {"doku/levels/bankdatalkstyle12x12.json": daily_style},
                rejection="daily_pool_missing",
                description="A legal H tier does not satisfy the daily consumer's required N tier")
        linked_in = json.loads((ROOT / "products/meowdoku/assets/editor/levels/bankDataLK.json").read_text())
        for field, invalid in (("date", {"bad": 1}), ("label", ["bad"])):
            malformed = json.loads(json.dumps(linked_in))
            malformed[0][field] = invalid
            publish("lk-invalid-" + field, {"doku/levels/bankdatalk.json": malformed},
                    rejection="$[0]." + field,
                    description="Consumed LK display metadata rejects wrong types with the exact field path")
        publish("shortened-special-bank", {"doku/levels/bankdatasp.json": {"levels": [gc_source]}},
                rejection="special_level_10:level_reference_missing",
                description="A bank-only release must preserve references inherited from the builtin policy")
        special_levels = json.loads((ROOT / "products/meowdoku/assets/editor/levels/bankDataSP.json").read_text())["levels"]
        for entry in special_levels:
            entry["pattern"] = "ordinary"
        publish("special-bank-without-guide", {"doku/levels/bankdatasp.json": {"levels": special_levels}},
                description="Ordinary SP replacement preserves level references without coupling to the client-owned tutorial")
        special_prefill = json.loads(json.dumps(special_levels))
        first_special = special_prefill[0]
        first_special["prefill_positions"] = [[0, first_special["solution"][0]]]
        publish("special-valid-prefill", {"doku/levels/bankdatasp.json": {"levels": special_prefill}},
                description="SP prefill with an in-bounds answer coordinate passes the actual publication path")
        first_special["prefill_positions"] = "bad"
        publish("special-malformed-prefill", {"doku/levels/bankdatasp.json": {"levels": special_prefill}},
                rejection="content_schema:doku/levels/bankdatasp",
                description="String prefill cannot be signed and delivered to a typed Array consumer")
        first_special["prefill_positions"] = [[0, (first_special["solution"][0] + 1) % len(first_special["regionMap"])]]
        publish("special-wrong-prefill-answer", {"doku/levels/bankdatasp.json": {"levels": special_prefill}},
                rejection="content_schema:doku/levels/bankdatasp",
                description="A well-shaped SP coordinate that contradicts the answer is rejected before signing")
        shutil.copyfile(ROOT / "products/meowdoku/assets/icons/project_icon.png", raw / "mark.png")
        publish("raw-wrong-size", raw_files, raw_assets=raw,
                rejection="texture_binding_dimensions:game/mark",
                description="432×432 replacement for fixed 32×168 game/mark is rejected without final output")
        publish("spine-correct", {**policy, "media.json": {"spine": {"game/cat": "maomi_fuor.tres"}}},
                spine_assets=ROOT / "products/meowdoku/assets/effect/spine/ui_cat_icon",
                description="Original ui_cat_icon (maomi_fuor) exported to game/cat preserves required animations and skins")
        publish("spine-wrong-contract", {**policy, "media.json": {"spine": {"game/cat": "logo.tres"}}},
                spine_assets=ROOT / "products/meowdoku/assets/effect/spine/ui_logo", rejection="spine_binding_contract:game/cat",
                description="Valid exported ui_logo Spine cannot satisfy game/cat's animation/skin contract; no final output")
    ok = all(check["ok"] for check in checks)
    if args.report:
        report = json.loads(args.report.read_text()) if args.report.exists() else {"ok": True}
        report = merge_publication_checks(report, checks)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PRODUCT_PUBLICATION_TESTS checks={len(checks)} failures={sum(not check['ok'] for check in checks)}")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
