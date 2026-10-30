#!/usr/bin/env python3
"""Build a signed channel artifact that selects immutable releases for each runtime.

Deploy channel.json and channel.sig together at a stable URL. The channel revision
must increase even when deliberately rolling back to an older release. This tool
writes a new local artifact; it never uploads files or overwrites a published one.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

from build_release import MAX_FILE, MAX_RELEASE, safe_path

IDENTIFIER = re.compile(r"[a-z0-9_-]{1,80}\Z")
HOST = re.compile(r"[A-Za-z0-9.-]+\Z")
MAX_REVISION = 2**53 - 1


def allowed_url(url: str, allow_local_http: bool) -> bool:
    if not (url.startswith("https://") or (allow_local_http and url.startswith("http://"))):
        return False
    if len(url) > 2048 or any(ord(char) <= 32 or ord(char) > 126 for char in url):
        return False
    if any(char in url for char in "?#\\@"):
        return False
    try:
        parsed = urlsplit(url)
        host, port = parsed.hostname or "", parsed.port
    except ValueError:
        return False
    if not HOST.fullmatch(host) or host.startswith(".") or host.endswith(".") or ".." in host:
        return False
    if port is not None and not 1 <= port <= 65535:
        return False
    # urlsplit accepts an empty explicit port and normalizes host case. Match
    # the client: no empty port, and only literal lowercase loopback for HTTP.
    if parsed.netloc.endswith(":"):
        return False
    literal_host = parsed.netloc.split(":", 1)[0]
    return parsed.scheme == "https" or (allow_local_http and parsed.scheme == "http" and literal_host in {"localhost", "127.0.0.1"})


def build(args: argparse.Namespace) -> None:
    if not IDENTIFIER.fullmatch(args.product) or not IDENTIFIER.fullmatch(args.channel):
        raise ValueError("product/channel must be lowercase identifiers")
    if not 1 <= args.revision <= MAX_REVISION:
        raise ValueError("revision must be a positive, exactly representable JSON integer")
    if not 1 <= len(args.target) <= 64:
        raise ValueError("channel needs 1..64 runtime targets")
    output = args.output.resolve()
    if output.exists():
        raise ValueError("Output already exists; write a new artifact and deploy the pair atomically")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="channel-build-", dir=output.parent) as temporary:
        work = Path(temporary)
        public = work / "public.pem"
        subprocess.run(["openssl", "pkey", "-in", str(args.key.resolve()), "-pubout", "-out", str(public)], check=True)
        targets, runtimes = [], set()
        for directory_name, url in args.target:
            directory = Path(directory_name).resolve()
            if not 0 < (directory / "manifest.json").stat().st_size <= 1024 * 1024:
                raise ValueError("Target manifest exceeds the client size limit")
            raw = (directory / "manifest.json").read_bytes()
            manifest = json.loads(raw)
            if manifest.get("format") != 1 or manifest.get("product") != args.product:
                raise ValueError("Target manifest has an incompatible product/format")
            release, runtime = manifest.get("release"), manifest.get("runtime")
            if not isinstance(release, str) or not IDENTIFIER.fullmatch(release):
                raise ValueError("Invalid target release")
            if not isinstance(runtime, str) or not 1 <= len(runtime) <= 160 or runtime in runtimes:
                raise ValueError("Each runtime must have exactly one target")
            if not allowed_url(url, args.allow_local_http):
                raise ValueError("Target must use HTTPS without credentials/query; localhost HTTP requires the development flag")
            subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(public), "-signature", str(directory / "manifest.sig"), str(directory / "manifest.json")], check=True, stdout=subprocess.DEVNULL)
            entries = manifest.get("files")
            if not isinstance(entries, list) or not 1 <= len(entries) <= 2048:
                raise ValueError("Target has no valid file list")
            total = 0
            for entry in entries:
                relative = entry.get("path") if isinstance(entry, dict) else None
                if not isinstance(relative, str) or not safe_path(relative):
                    raise ValueError("Target contains an unsafe file path")
                payload = directory / relative
                if payload.is_symlink() or not payload.is_file() or not payload.resolve().is_relative_to(directory):
                    raise ValueError("Target payload must be a local file inside the release")
                size = payload.stat().st_size
                if not 0 < size <= MAX_FILE or size != entry.get("bytes"):
                    raise ValueError("Target payload size does not match its signed manifest")
                if hashlib.sha256(payload.read_bytes()).hexdigest() != entry.get("sha256"):
                    raise ValueError("Target payload hash does not match its signed manifest")
                total += size
            if total > MAX_RELEASE:
                raise ValueError("Target exceeds the client release size limit")
            runtimes.add(runtime)
            targets.append({"runtime": runtime, "release": release, "url": url.rstrip("/"), "manifest_sha256": hashlib.sha256(raw).hexdigest()})
        value = {"format": 1, "product": args.product, "channel": args.channel, "revision": args.revision,
                 "targets": sorted(targets, key=lambda target: target["runtime"])}
        stage = work / "artifact"
        stage.mkdir()
        metadata = stage / "channel.json"
        encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
        if len(encoded) > 64 * 1024:
            raise ValueError("Channel exceeds the 64 KiB client limit")
        metadata.write_bytes(encoded)
        subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(args.key.resolve()), "-out", str(stage / "channel.sig"), str(metadata)], check=True)
        stage.rename(output)
    print(f"Built signed channel revision {args.revision}: {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product", required=True)
    parser.add_argument("--channel", default="stable")
    parser.add_argument("--revision", type=int, required=True)
    parser.add_argument("--target", nargs=2, metavar=("RELEASE_DIRECTORY", "IMMUTABLE_URL"), action="append", required=True)
    parser.add_argument("--key", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--allow-local-http", action="store_true")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
