#!/usr/bin/env python3
"""Build immutable signed JSON + optional raw-asset PCK releases, without opening the game.

Private keys are provided by path and never copied to the output. manifest.sig is
RSA PKCS#1 v1.5 / SHA-256 over the exact manifest.json bytes (OpenSSL/Godot compatible).
The output is a local publication artifact, not an automatic upload or CDN deployment.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_validation import classify_engine_errors, has_reported_failures

IDENTIFIER = re.compile(r"[a-z0-9_-]{1,80}\Z")
SEGMENT = re.compile(r"[a-z0-9_-][a-z0-9_.-]*\Z")
RAW = {".json", ".png", ".jpg", ".jpeg", ".webp", ".ogg", ".wav", ".mp3"}
MAX_FILE = 128 * 1024 * 1024
MAX_RELEASE = 256 * 1024 * 1024


def safe_path(value: str) -> bool:
    return len(value) <= 240 and all(SEGMENT.fullmatch(part) for part in value.split("/"))


def files_under(root: Path):
    if not root.is_dir() or root.is_symlink():
        raise ValueError(f"Not a real source directory: {root}")
    for source in sorted(root.rglob("*")):
        if source.is_symlink():
            raise ValueError(f"Symlink is not a publication input: {source}")
        if source.is_file():
            relative = source.relative_to(root).as_posix().lower()
            if not safe_path(relative):
                raise ValueError(f"Unsupported resource name: {relative}")
            if not 0 < source.stat().st_size <= MAX_FILE:
                raise ValueError(f"Unsupported resource size: {source}")
            yield source, relative


def record(path: Path, relative: str, logical_id: str, kind: str) -> dict:
    return {"id": logical_id, "path": relative, "kind": kind,
            "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def build(args: argparse.Namespace) -> None:
    if not IDENTIFIER.fullmatch(args.product) or not IDENTIFIER.fullmatch(args.release):
        raise ValueError("product/release must be lowercase identifiers")
    if not args.runtime:
        raise ValueError("runtime compatibility ID must not be empty")
    args.godot = args.godot or os.environ.get("DOKU_GODOT") or "godot"
    output = args.output.resolve()
    if output.exists():
        raise ValueError("Release output already exists; release IDs are immutable")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="content-build-", dir=output.parent) as temporary:
        stage = Path(temporary) / "release"
        stage.mkdir()
        entries, seen = [], set()
        for source, relative in files_under(args.source.resolve()):
            if source.suffix.lower() != ".json":
                raise ValueError("The data source may contain JSON files only")
            value = json.loads(source.read_text(encoding="utf-8"))
            if not isinstance(value, (dict, list)):
                raise ValueError(f"JSON content must be object/array: {source}")
            destination = "data/" + relative
            logical_id = relative.removesuffix(".json")
            if logical_id in seen:
                raise ValueError(f"Duplicate normalized logical ID: {logical_id}")
            seen.add(logical_id)
            target = stage / destination
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            entries.append(record(target, destination, logical_id, "json"))
        if "media" in seen and not (args.raw_assets or args.spine_assets):
            raise ValueError("media mapping must be published with a resource pack")
        if args.raw_assets or args.spine_assets:
            if "raw-assets" in seen:
                raise ValueError("raw-assets is reserved for the optional media pack")
        if args.spine_assets:
            from spine_pack import build_spine_pack
            build_spine_pack(args.godot, args.spine_assets.resolve(), stage / "assets.pck", Path(temporary), args.product, args.release, Path(__file__).resolve().parents[2], args.raw_assets.resolve() if args.raw_assets else None)
            entries.append(record(stage / "assets.pck", "assets.pck", "raw-assets", "spine_pck"))
        if args.raw_assets and not args.spine_assets:
            pack_files, paths = [], set()
            for source, relative in files_under(args.raw_assets.resolve()):
                if source.suffix.lower() not in RAW:
                    raise ValueError(f"Unsupported raw resource: {source}")
                internal = f"content/{args.product}/{args.release}/{relative}"
                if not safe_path(internal) or internal in paths:
                    raise ValueError(f"Duplicate or invalid pack path: {internal}")
                paths.add(internal)
                pack_files.append({"source": str(source), "path": internal})
            if not pack_files:
                raise ValueError("Raw asset directory is empty")
            isolated = Path(temporary) / "packer"
            isolated.mkdir()
            (isolated / "project.godot").write_text('config_version=5\n[application]\nconfig/name="ContentPacker"\n', encoding="utf-8")
            shutil.copyfile(Path(__file__).with_name("pack_raw.gd"), isolated / "pack.gd")
            spec = isolated / "pack.json"
            spec.write_text(json.dumps({"output": str(stage / "assets.pck"), "files": pack_files}), encoding="utf-8")
            command = [args.godot, "--headless", "--log-file", str(isolated / "engine.log"), "--path", str(isolated), "--script", "res://pack.gd", "--", str(spec)]
            packed = subprocess.run(command, capture_output=True, text=True, timeout=120)
            diagnostics = classify_engine_errors(packed.stdout + packed.stderr, command)
            if (packed.returncode or diagnostics.get("unexpected_errors") or has_reported_failures(packed.stdout + packed.stderr)
                    or any(marker in packed.stdout + packed.stderr for marker in ("SCRIPT ERROR:", "Parse Error:"))):
                raise RuntimeError(packed.stdout + packed.stderr)
            print(packed.stdout + packed.stderr, end="")
            entries.append(record(stage / "assets.pck", "assets.pck", "raw-assets", "raw_pck"))
        if not entries or len(entries) > 2048 or sum(e["bytes"] for e in entries) > MAX_RELEASE:
            raise ValueError("Release exceeds content profile limits or is empty")
        if any(e["bytes"] > MAX_FILE for e in entries):
            raise ValueError("Pack exceeds the per-file limit")
        manifest = {"format": 1, "product": args.product, "release": args.release,
                    "runtime": args.runtime, "files": entries}
        manifest_path = stage / "manifest.json"
        manifest_path.write_bytes(json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8"))
        # 产品语义与跨资源依赖在签名前验证；检查失败不留下可被发布的最终目录。
        if args.product == "meowdoku":
            engine = args.godot
            if not engine or shutil.which(engine) is None:
                raise ValueError("Meowdoku publication requires the matching Godot/Spine engine; set --godot, DOKU_GODOT or provide godot on PATH")
            validation = Path(__file__).resolve().parents[1] / "validate_content_product.py"
            subprocess.run([sys.executable, str(validation), "--release", str(stage), "--godot", engine], check=True)
        subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(args.key.resolve()), "-out", str(stage / "manifest.sig"), str(manifest_path)], check=True)
        stage.rename(output)
    print(f"Built immutable release: {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--product", required=True)
    parser.add_argument("--release", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--key", required=True, type=Path)
    parser.add_argument("--raw-assets", type=Path)
    parser.add_argument("--spine-assets", type=Path)
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
