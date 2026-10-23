#!/usr/bin/env python3
"""从原始 XAPK 建立独立清单，并校验恢复工程的发布内容覆盖率。"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
from zipfile import ZipFile


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def inventory(package: Path, output: Path) -> dict:
    result: dict = {
        "schema": 1,
        "package_file": package.name,
        "package_sha256": digest(package.read_bytes()),
        "splits": [],
        "scripts": [],
        "scenes": [],
        "translations": [],
        "level_banks": [],
    }
    with ZipFile(package) as outer:
        result["xapk_manifest"] = json.loads(outer.read("manifest.json"))
        for split in sorted(n for n in outer.namelist() if n.endswith(".apk")):
            data = outer.read(split)
            with ZipFile(io.BytesIO(data)) as apk:
                names = apk.namelist()
                result["splits"].append({"path": split, "sha256": digest(data), "entries": len(names)})
                for name in sorted(names):
                    if not name.startswith("assets/") or name.endswith("/"):
                        continue
                    path = name.removeprefix("assets/")
                    if path.endswith(".gdc"):
                        result["scripts"].append({
                            "path": path.removesuffix(".gdc") + ".gd",
                            "bytecode_path": ".autoconverted/" + path,
                            "sha256": digest(apk.read(name)),
                        })
                    elif path.endswith(".tscn.remap"):
                        result["scenes"].append(path.removesuffix(".remap"))
                    elif path.endswith(".translation"):
                        result["translations"].append({"path": path, "sha256": digest(apk.read(name))})
                    elif path.startswith("assets/resources/levels/") and path.endswith((".json", ".bin")):
                        result["level_banks"].append({"path": path, "sha256": digest(apk.read(name))})
    for key in ("scripts", "scenes", "translations", "level_banks"):
        paths = [item if isinstance(item, str) else item["path"] for item in result[key]]
        if len(paths) != len(set(paths)):
            raise ValueError("Split packages contain ambiguous duplicate paths: " + key)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": str(output), **{key: len(result[key]) for key in ("scripts", "scenes", "translations", "level_banks")}}, ensure_ascii=False))
    return result


def verify(root: Path, manifest: Path) -> int:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    failures: list[str] = []
    expected_scripts = set()
    for item in data["scripts"]:
        expected_scripts.add(item["path"])
        if not (root / item["path"]).is_file():
            failures.append("Missing recovered source: " + item["path"])
        bytecode = root / item["bytecode_path"]
        if not bytecode.is_file() or digest(bytecode.read_bytes()) != item["sha256"]:
            failures.append("Original bytecode missing/changed: " + item["bytecode_path"])
    for path in data["scenes"]:
        if not (root / path).is_file():
            failures.append("Missing recovered scene: " + path)
    for key in ("translations", "level_banks"):
        for item in data[key]:
            path = root / item["path"]
            if not path.is_file() or digest(path.read_bytes()) != item["sha256"]:
                failures.append("Original runtime data missing/changed: " + item["path"])
    actual_bytecode = {p.relative_to(root / ".autoconverted").as_posix().removesuffix(".gdc") + ".gd" for p in (root / ".autoconverted").rglob("*.gdc")}
    for stale in sorted(actual_bytecode - expected_scripts):
        failures.append("Stale bytecode outside new package: " + stale)
    print(json.dumps({"status": "failed" if failures else "passed", "version": data["xapk_manifest"]["version_name"], "scripts": len(data["scripts"]), "scenes": len(data["scenes"]), "translations": len(data["translations"]), "level_banks": len(data["level_banks"]), "failures": failures}, ensure_ascii=False, indent=2))
    return bool(failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    collect = commands.add_parser("inventory", help="Read the original XAPK; never infer expectations from recovered files")
    collect.add_argument("package", type=Path)
    collect.add_argument("output", type=Path)
    check = commands.add_parser("verify", help="Check source coverage and hashes of unmodified bytecode/runtime data")
    check.add_argument("root", type=Path)
    check.add_argument("manifest", type=Path)
    args = parser.parse_args()
    if args.command == "inventory":
        inventory(args.package, args.output)
        return 0
    return verify(args.root, args.manifest)


if __name__ == "__main__":
    raise SystemExit(main())
