#!/usr/bin/env python3
"""Inventory the three immutable Meowdoku migration baselines without changing them.

Only --output is written. An optional relocation map uses the existing
{schema: 1, paths: {"res://source": "res://destination"}} format. The raw
three-tree inventory is exhaustive even while the destination map is incomplete.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess


BASELINES = {
    "original_181": "7af200ca1b582a86c92ab3d498c6af43a20d201a",
    "framework_181": "d89f94d1dd03d1b3369054351ee95ccc93d9cb93",
    "recovery_122": "2af1f49bdde26131f85a453a821fce7351cf4885",
}
OLD_MAP = "tools/validation/fixtures/recovered_relocations.json"
EVIDENCE = "docs/recovery/1.22.0/"


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(repo), *args])


def tree(repo: Path, revision: str) -> dict:
    entries = {}
    for record in git(repo, "ls-tree", "-r", "-z", "-l", revision).split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        mode, kind, oid, size = metadata.decode("ascii").split()
        entries[raw_path.decode("utf-8")] = {
            "oid": oid, "mode": mode, "kind": kind,
            "bytes": int(size) if size != "-" else None,
        }
    return entries


class Blobs:
    """Read only requested objects; do not materialize a working tree."""

    def __init__(self, repo: Path):
        self.process = subprocess.Popen(
            ["git", "-C", str(repo), "cat-file", "--batch"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        )

    def read(self, oid: str) -> bytes:
        self.process.stdin.write((oid + "\n").encode("ascii"))
        self.process.stdin.flush()
        header = self.process.stdout.readline().decode("ascii").split()
        if len(header) != 3 or header[1] != "blob":
            raise ValueError("Expected a Git blob: " + repr(header))
        size = int(header[2])
        result = self.process.stdout.read(size)
        if len(result) != size or self.process.stdout.read(1) != b"\n":
            raise ValueError("Truncated Git object stream")
        return result

    def close(self) -> None:
        self.process.stdin.close()
        self.process.stdout.close()
        if self.process.wait() != 0:
            raise ValueError("git cat-file failed")


def same(left, right) -> bool:
    return left == right


def change(before, after) -> str:
    if before is None:
        return "added" if after is not None else "absent"
    if after is None:
        return "deleted"
    return "unchanged" if same(before, after) else "modified"


def action(base, current, incoming) -> str:
    if incoming is None:
        return "review_upstream_retirement" if current is not None else "absent"
    if same(current, incoming):
        return "already_identical"
    if base is None:
        return "add_incoming" if current is None else "reconcile_both_added"
    if same(base, incoming):
        return "preserve_framework" if current is not None else "review_framework_removal"
    if same(base, current):
        return "take_incoming"
    return "review_framework_removal" if current is None else "reconcile_both_modified"


def scope(path: str) -> str:
    if path.startswith(".autoconverted/"):
        return "original_bytecode_evidence"
    if path.startswith("docs/recovery/"):
        return "recovery_evidence"
    if path.startswith("docs/"):
        return "documentation"
    if path.startswith("tools/"):
        return "tooling"
    if path.startswith(("addons/", "android/")):
        return "platform_or_development_plugin"
    if path.startswith("assets/resources/levels/"):
        return "original_runtime_bank"
    if path.startswith("assets/editor/levels/"):
        return "editable_bank"
    if path.startswith("assets/"):
        return "product_asset"
    if path.startswith("scripts/") or path.endswith(".tscn"):
        return "product_source_or_scene"
    return "project_configuration_or_other"


def clean_resource_path(value: str) -> str:
    if not isinstance(value, str) or not value.startswith("res://"):
        raise ValueError("Relocation paths must start with res://: " + repr(value))
    raw = value.removeprefix("res://")
    if not raw or "\\" in raw or raw.startswith("/") or ".." in PurePosixPath(raw).parts:
        raise ValueError("Unsafe relocation path: " + repr(value))
    if PurePosixPath(raw).as_posix() != raw:
        raise ValueError("Relocation path must be normalized: " + repr(value))
    return raw


def read_mapping(document: dict) -> dict:
    if document.get("schema") != 1 or not isinstance(document.get("paths"), dict):
        raise ValueError("Expected a schema=1 relocation map with paths")
    return {clean_resource_path(k): clean_resource_path(v) for k, v in document["paths"].items()}


def destination(path: str, mapping: dict) -> tuple[str, str]:
    if path in mapping:
        return mapping[path], "explicit"
    if path.endswith((".uid", ".import")):
        suffix = ".uid" if path.endswith(".uid") else ".import"
        if path[:-len(suffix)] in mapping:
            return mapping[path[:-len(suffix)]] + suffix, "sidecar"
    # Existing product asset ownership is unambiguous; script placement is not.
    if path.startswith("assets/"):
        return "products/meowdoku/" + path, "existing_asset_convention"
    return path, "identity"


def verify_evidence(blobs: Blobs, incoming: dict) -> dict:
    def document(path):
        return json.loads(blobs.read(incoming[EVIDENCE + path]["oid"]))

    package = document("package_manifest.json")
    integrity = document("final_source_integrity.json")
    runtime = document("runtime_manifest.json")
    atlas = document("atlas_recovery_report.json")
    checks = {
        "original_bytecode": [(x["bytecode_path"], x["sha256"]) for x in package["scripts"]],
        "original_runtime_banks": [(x["path"], x["sha256"]) for x in package["level_banks"]],
        "original_translations": [(x["path"], x["sha256"]) for x in package["translations"]],
        "final_recovered_sources": [(x["path"], x["sha256"]) for x in integrity["items"]],
        "editable_banks": [(x["editor_path"], x["editor_sha256"]) for x in runtime["banks"]],
        "restored_atlas_pngs": [(x["source_file"].removeprefix("res://"), x["png_sha256"]) for x in atlas["items"]],
    }
    result = {"package_sha256": package["package_sha256"], "groups": {}}
    result["manifest_package_identity_matches"] = package["package_sha256"] == runtime["package_sha256"]
    for name, expected in checks.items():
        failed = []
        for path, digest in expected:
            entry = incoming.get(path)
            actual = hashlib.sha256(blobs.read(entry["oid"])).hexdigest() if entry else None
            if actual != digest:
                failed.append({"path": path, "expected_sha256": digest, "actual_sha256": actual})
        result["groups"][name] = {"expected": len(expected), "passed": len(expected) - len(failed), "failures": failed,
                                  "duplicate_paths": len(expected) != len({p for p, _ in expected})}
    sets = {
        "original_bytecode": {p for p in incoming if p.startswith(".autoconverted/") and p.endswith(".gdc")},
        "original_runtime_banks": {p for p in incoming if p.startswith("assets/resources/levels/") and p.endswith((".json", ".bin"))},
        "original_translations": {p for p in incoming if p.startswith("assets/localization/") and p.endswith(".translation")},
        "editable_banks": {p for p in incoming if p.startswith("assets/editor/levels/") and p.endswith(".json")},
    }
    for name, actual_paths in sets.items():
        expected_paths = {p for p, _ in checks[name]}
        result["groups"][name]["unexpected_files"] = sorted(actual_paths - expected_paths)
    result["scene_paths"] = {"expected": len(package["scenes"]), "missing": [p for p in package["scenes"] if p not in incoming]}
    result["scope"] = "Git objects at the fixed 1.22 revision; not a new bytecode recompilation, pixel comparison, engine run, or migrated-tree proof"
    result["ok"] = (result["manifest_package_identity_matches"]
                    and not result["scene_paths"]["missing"]
                    and all(not group["failures"] and not group["duplicate_paths"]
                            and not group.get("unexpected_files", []) for group in result["groups"].values()))
    return result


def inventory(repo: Path, mapping_file: Path | None) -> dict:
    trees = {name: tree(repo, revision) for name, revision in BASELINES.items()}
    base, current, incoming = [trees[name] for name in BASELINES]
    blobs = Blobs(repo)
    try:
        mapping = read_mapping(json.loads(blobs.read(current[OLD_MAP]["oid"])))
        if mapping_file:
            mapping.update(read_mapping(json.loads(mapping_file.read_text(encoding="utf-8"))))
        raw = []
        for path in sorted(set().union(*trees.values())):
            raw.append({"path": path, "scope": scope(path),
                        "versions": {name: entries[path] for name, entries in trees.items() if path in entries},
                        "upstream_change": change(base.get(path), incoming.get(path)),
                        "framework_change_at_original_path": change(base.get(path), current.get(path))})
        logical, owners, referenced_current = [], defaultdict(list), set()
        for path in sorted(base.keys() | incoming.keys()):
            target, rule = destination(path, mapping)
            b, c, i = base.get(path), current.get(target), incoming.get(path)
            if c is not None:
                referenced_current.add(target)
            if i is not None:
                owners[target].append(path)
            logical.append({"original_path": path, "destination": target, "mapping_rule": rule,
                            "scope": scope(path), "base": b, "framework": c, "incoming": i,
                            "upstream_change": change(b, i), "framework_change": change(b, c),
                            "suggested_action": action(b, c, i),
                            "shared_framework_destination": target.startswith("scripts/framework/")})
        unbound = [{"path": path, **current[path]} for path in sorted(current.keys() - referenced_current)]
        collisions = {p: sources for p, sources in owners.items() if len(sources) > 1}
        package = json.loads(blobs.read(incoming[EVIDENCE + "package_manifest.json"]["oid"]))
        identities = {x["path"] for x in package["scripts"]} | set(package["scenes"])
        unmapped = sorted(p for p in identities if p.startswith("scripts/") and destination(p, mapping)[1] == "identity")
        binary_resources = []
        for path, entry in incoming.items():
            if Path(path).suffix not in {".res", ".scn", ".tres", ".material", ".mesh", ".anim"}:
                continue
            payload = blobs.read(entry["oid"])
            if payload[:4] in (b"RSRC", b"RSCC"):
                binary_resources.append({"path": path, "destination": destination(path, mapping)[0],
                                         "magic": payload[:4].decode("ascii"), "oid": entry["oid"],
                                         "requires_dependency_aware_relocation": True})
        coverage = {name: {"tree_files": len(entries),
                           "inventoried": sum(name in item["versions"] for item in raw)}
                    for name, entries in trees.items()}
        if any(v["tree_files"] != v["inventoried"] for v in coverage.values()):
            raise AssertionError("Incomplete raw tree coverage")
        return {"schema": 1, "baselines": BASELINES, "coverage": coverage,
                "mapping": {"baseline_path": OLD_MAP, "overlay_sha256": hashlib.sha256(mapping_file.read_bytes()).hexdigest() if mapping_file else None,
                            "effective_count": len(mapping), "unmapped_recovered_code_or_scenes": unmapped,
                            "destination_collisions": collisions},
                "action_counts": dict(sorted(Counter(x["suggested_action"] for x in logical).items())),
                "original_evidence": verify_evidence(blobs, incoming),
                "binary_resources": binary_resources,
                "raw_files": raw, "logical_files": logical, "framework_unbound_files": unbound,
                "limitations": ["Suggestions require review; no automatic resolution or file mutation is performed.",
                                "Original evidence documents are immutable inputs; subsequent migration edits need a separate ledger.",
                                "Binary resource dependencies require an isolated engine-aware rewrite, not string replacement.",
                                "No runtime, SDK, network, Android device, or exact migrated-tree validation is claimed."]}
    finally:
        blobs.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--mapping", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = args.output.resolve()
    # Do not overwrite a tracked source or evidence file even if requested by mistake.
    try:
        relative_output = output.relative_to(repo).as_posix()
    except ValueError:
        relative_output = None
    if relative_output is not None and subprocess.run(
        ["git", "-C", str(repo), "ls-files", "--error-unmatch", "--", relative_output],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0:
        parser.error("--output must not overwrite a tracked file")
    if args.mapping and output == args.mapping.resolve():
        parser.error("--output must not overwrite --mapping")
    result = inventory(repo, args.mapping)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "coverage": result["coverage"],
                      "action_counts": result["action_counts"], "evidence_ok": result["original_evidence"]["ok"],
                      "unmapped_recovered": len(result["mapping"]["unmapped_recovered_code_or_scenes"]),
                      "collisions": len(result["mapping"]["destination_collisions"]),
                      "binary_resources": len(result["binary_resources"])}, ensure_ascii=False))
    return 0 if result["original_evidence"]["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
