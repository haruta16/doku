#!/usr/bin/env python3
"""Run content contracts in isolated projects with a loopback-only HTTP fixture.

Use --report PATH to retain structured evidence after temporary keys and fixtures
are removed. No production host or original game user directory is accessed.
"""
from __future__ import annotations
import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_validation import classify_engine_errors, completion_contract, has_reported_failures

REQUIRED_CONTENT_INPUTS = (
    "tools/validation/test_content_delivery.gd",
    "tools/validation/test_content_updates.gd",
    "tools/validation/test_content_boot_failure.gd",
    "tools/validation/test_content_update_bootstrap.gd",
    "tools/validation/fixtures/content_fixture_guard.gd",
    "products/meowdoku/app/bootstrap/content_bootstrap.gd",
)
CONTENT_STEP_COUNT = 8  # publisher rejection, four contracts, bootstrap import and two processes


def require_fixtures(repo: Path) -> None:
    missing = [relative for relative in REQUIRED_CONTENT_INPUTS if not (repo / relative).is_file()]
    if missing:
        raise FileNotFoundError("Required content fixtures are missing: " + ", ".join(missing))


def content_report(results: list[dict]) -> dict:
    complete = len(results) == CONTENT_STEP_COUNT
    return {"ok": complete and all(item.get("ok") is True for item in results), "steps": results,
            "expected_steps": CONTENT_STEP_COUNT, "executed_steps": len(results),
            **({} if complete else {"error": "incomplete_content_suite"}),
            "scope": "Isolated projects; ephemeral keys; local HTTP faults and real Godot runtime; no mobile or production TLS validation."}


def prepare_fixture_guard(repo: Path, work: Path, project: Path) -> None:
    (work / ".content-test-fixture").write_text("doku-isolated-content-v1\n", encoding="utf-8")
    guard = Path("tools/validation/fixtures/content_fixture_guard.gd")
    (project / guard).parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(repo / guard, project / guard)


class FixtureHandler(http.server.SimpleHTTPRequestHandler):
    lock = threading.Lock()
    counts: dict[str, int] = {}

    def log_message(self, *_args):
        pass

    def do_GET(self):
        original = self.path
        with self.lock:
            self.counts[original] = self.counts.get(original, 0) + 1
            count = self.counts[original]
            with (Path(self.directory) / "http-requests.log").open("a") as stream:
                stream.write(original + "\n")
        if original.startswith("/unavailable"):
            self.send_error(503)
            return
        if original.startswith("/flaky/"):
            if original.endswith("/data/levels.json") and count < 3:
                self.send_error(503)
                return
            self.path = original.removeprefix("/flaky")
        if original.startswith("/slow/"):
            self.path = original.removeprefix("/slow")
            if original.endswith("/data/levels.json"):
                time.sleep(0.2)
        try:
            super().do_GET()
        except (BrokenPipeError, ConnectionResetError):
            pass  # cancellation deliberately closes a request in flight


def run_step(command: list[str], log: Path, timeout: int = 90) -> dict:
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    output = result.stdout + result.stderr
    log.write_text(output)
    print(output, end="", flush=True)
    diagnostics = classify_engine_errors(output, command)
    completed = completion_contract(output, command)
    passed = (result.returncode == 0 and not has_reported_failures(output)
              and completed["ok"]
              and not diagnostics.get("unexpected_errors")
              and not any(token in output for token in ("SCRIPT ERROR:", "Parse Error:", "TEST_FAILED:", "PACK_VALIDATION_FAILED:")))
    summary = [line for line in output.splitlines() if re.search(r"CONTENT_.*(checks=|passed:)|PACK_VALIDATED", line)]
    return {"command": command, "exit_code": result.returncode, "ok": passed,
            "completion": completed, "summary": summary, "log": output, "diagnostics_classified": True,
            "log_sha256": hashlib.sha256(output.encode()).hexdigest(), **diagnostics}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    require_fixtures(repo)
    results = []
    with tempfile.TemporaryDirectory(prefix="content-tests-") as temporary:
        work = Path(temporary).resolve()
        project = work / "project"
        (project / "scripts/framework").mkdir(parents=True)
        shutil.copytree(repo / "scripts/framework/content", project / "scripts/framework/content")
        prepare_fixture_guard(repo, work, project)
        for source, target in [("test_content_delivery.gd", "test.gd"), ("test_content_updates.gd", "updates.gd"), ("test_content_boot_failure.gd", "boot-failure.gd")]:
            shutil.copyfile(repo / "tools/validation" / source, project / target)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="ContentContractTests"\n', encoding="utf-8")
        source = work / "source"
        source.mkdir()
        (source / "levels.json").write_text(json.dumps({"level": 8}), encoding="utf-8")
        subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(work / "private.pem")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["openssl", "pkey", "-in", str(work / "private.pem"), "-pubout", "-out", str(work / "http-public.pem")], check=True)
        subprocess.run([sys.executable, str(repo / "tools/content/build_release.py"), "--source", str(source), "--output", str(work / "http"), "--product", "test", "--release", "http", "--runtime", "runtime-v1", "--key", str(work / "private.pem")], check=True)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(FixtureHandler, directory=str(work)))
        url = f"http://127.0.0.1:{server.server_address[1]}"
        subprocess.run([sys.executable, str(repo / "tools/content/build_channel.py"), "--product", "test", "--channel", "stable", "--revision", "2", "--target", str(work / "http"), url + "/http", "--key", str(work / "private.pem"), "--output", str(work / "channel"), "--allow-local-http"], check=True)
        tampered = work / "tampered-release"
        shutil.copytree(work / "http", tampered)
        (tampered / "data/levels.json").write_text('{"level":9}')
        bad_command = [sys.executable, str(repo / "tools/content/build_channel.py"), "--product", "test", "--revision", "3", "--target", str(tampered), url + "/http", "--key", str(work / "private.pem"), "--output", str(work / "bad-channel-artifact"), "--allow-local-http"]
        rejected = subprocess.run(bad_command, capture_output=True, text=True, timeout=20)
        builder_ok = rejected.returncode != 0 and not (work / "bad-channel-artifact").exists()
        results.append({"command": bad_command, "exit_code": rejected.returncode, "ok": builder_ok, "expected_rejection": True, "summary": ["Channel publisher rejects modified payload before producing an artifact"]})
        if not builder_ok:
            raise RuntimeError("Channel builder accepted a modified release")
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            steps = [("test.gd", [str(work), url + "/http"]), ("updates.gd", [str(work), url]), ("boot-failure.gd", [str(work)]), ("boot-failure.gd", [str(work), "resume"])]
            for index, (script, extra) in enumerate(steps):
                command = [args.godot, "--headless", "--log-file", str(work / f"step-{index}.engine.log"), "--path", str(project), "--script", "res://" + script, "--", *extra]
                results.append(run_step(command, work / f"step-{index}.log"))
                if not results[-1]["ok"]:
                    break
            if all(item["ok"] for item in results):
                results.extend(run_bootstrap(repo, work, args.godot, url))
        finally:
            server.shutdown()
            server.server_close()
        report = content_report(results)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print("CONTENT_SUITE", json.dumps({"ok": report["ok"], "steps": len(results)}), flush=True)
        return 0 if report["ok"] else 1


def run_bootstrap(repo: Path, work: Path, engine: str, url: str) -> list[dict]:
    project = work / "bootstrap-project"
    shutil.copytree(work / "project/scripts", project / "scripts")
    prepare_fixture_guard(repo, work, project)
    bootstrap = Path("products/meowdoku/app/bootstrap/content_bootstrap.gd")
    (project / bootstrap).parent.mkdir(parents=True, exist_ok=True)
    (project / bootstrap).write_text(
        (repo / bootstrap).read_text().replace("user://content", (work / "bootstrap-cache").as_posix()))
    shutil.copyfile(repo / "tools/validation/test_content_update_bootstrap.gd", project / "bootstrap-test.gd")
    shutil.copyfile(work / "http-public.pem", project / "public.pem")
    config = '\n'.join(['config_version=5', '[application]', 'config/name="ContentBootstrapTests"',
        '[autoload]', 'ContentRuntime="*res://products/meowdoku/app/bootstrap/content_bootstrap.gd"', '[content]',
        'product="test"', 'runtime_id="runtime-v1"', 'public_key_path="res://public.pem"',
        'channel="stable"', f'channel_url="{url}/channel"', 'allow_local_http=true', ''])
    (project / "project.godot").write_text(config)
    results = [run_step([engine, "--headless", "--log-file", str(work / "bootstrap-import.engine.log"), "--path", str(project), "--editor", "--import"], work / "bootstrap-import.log")]
    if not results[-1]["ok"]:
        return results
    for mode in ([], ["resume"]):
        suffix = "resume" if mode else "first"
        command = [engine, "--headless", "--log-file", str(work / f"bootstrap-{suffix}.engine.log"), "--path", str(project), "--script", "res://bootstrap-test.gd", "--", str(work), url, *mode]
        results.append(run_step(command, work / f"bootstrap-{suffix}.log"))
        if not results[-1]["ok"]:
            break
        # 第二进程刻意不联网，只验证活动版本与频道水位的独立恢复。
        (project / "project.godot").write_text(config.replace(f'channel_url="{url}/channel"', 'channel_url=""'))
    return results


if __name__ == "__main__":
    raise SystemExit(main())
