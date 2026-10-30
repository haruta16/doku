#!/usr/bin/env python3
"""Export isolated real PCKs with this project's Spine assets and reproduce UID aliasing.

This is a toolchain proof, not the production raw-PCK publisher. Exported engine
packs contain global import/UID metadata and are intentionally NOT accepted by the
raw_pck runtime profile. No source project import files or player data are modified.
"""
from __future__ import annotations
import argparse
import os
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

from spine_pack import isolated_engine
from run_tests import classify_engine_errors, completion_contract, has_reported_failures

PRESET = '''[preset.0]
name="Proof"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
'''
PROJECT = '''config_version=5
[application]
config/name="ContentExportProof"
run/main_scene="res://main.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
[editor]
export/convert_text_resources_to_binary=false
'''
PROBE = '''extends Node
var failures := 0
var checks := 0
func _ready() -> void:
    var args := OS.get_cmdline_user_args()
    var filtered := args.size() > 2 and args[2] == "filtered"
    var uid := ResourceUID.text_to_id("uid://b7eqvkjrlbffh")
    var builtin_path := ResourceUID.get_id_path(uid)
    checks += 1
    if builtin_path != "res://builtin_gradient.tres":
        failures += 1
    for index in 2:
        var release := "r%d" % (index + 1)
        checks += 1
        if not ProjectSettings.load_resource_pack(args[index], true):
            push_error("exported PCK did not mount")
            failures += 1
            continue
        var spine = load("res://content/proof/" + release + "/spine/ui_cat_icon.tres")
        var valid: bool = spine != null and spine.get_class() == "SpineSkeletonDataResource" and spine.get("atlas_res") != null and spine.get("skeleton_file_res") != null
        if valid:
            var sprite = ClassDB.instantiate("SpineSprite")
            sprite.set("skeleton_data_res", spine)
            add_child(sprite)
            valid = sprite.get("skeleton_data_res") == spine
            sprite.queue_free()
        if not valid:
            failures += 1
        checks += 1
        print("SPINE_EXPORTED_LOAD ", release, " ", valid)
        if filtered:
            checks += 1
            var unchanged := ResourceUID.get_id_path(uid) == builtin_path
            print("FILTERED_UID_BASE_UNCHANGED ", unchanged)
            if not unchanged:
                failures += 1
        else:
            print("UID_MAPPING ", release, " ", ResourceUID.get_id_path(uid))
        if index == 0:
            checks += 1
            var builtin_container = ResourceLoader.load("res://builtin_container.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
            var actual: String = builtin_container.gradient.resource_name if builtin_container != null else "missing"
            print("UID_BASE_DEPENDENCY_RESOLVED_TO=", actual)
            if actual != ("builtin" if filtered else "r1"):
                failures += 1
    if not filtered:
        checks += 1
        var old_container = ResourceLoader.load("res://content/proof/r1/container.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
        var actual: String = old_container.gradient.resource_name if old_container != null else "missing"
        print("UID_COLLISION_REPRO old_r1_dependency_resolved_to=", actual)
        if actual != "r2":
            failures += 1
    print("EXPORTED_CONTENT_PROOF checks=%d failures=%d" % [checks, failures])
    get_tree().quit(0 if failures == 0 else 1)
'''


def proof_diagnostics(output: str, args: list[str]) -> dict:
    diagnostics = classify_engine_errors(output, args)
    # This proof has its own minimal project name. Preserve its existing sandbox
    # directory diagnostics, scoped to the exact path and engine call site. Shared
    # classification handles certificate errors and rejects every shutdown leak.
    user_directory = Path.home() / "Library/Application Support/Godot/app_userdata/ContentExportProof"
    sites = {f"ERROR: Could not create directory: '{user_directory}'.": "make_dir_recursive",
             f"ERROR: Error attempting to create data dir: {user_directory}.": "ensure_user_data_dir"}
    # --export-pack also initializes the editor's ObjectDB profiler.
    if ("--editor" in args or "--export-pack" in args) and str(user_directory) in output:
        sites["ERROR: Could not open 'user://' directory: 'user://'."] = "objectdb_profiler"
    lines = re.sub(r"\x1b\[[0-9;]*m", "", output).splitlines()
    for index, line in enumerate(lines):
        if line in sites and sites[line] in "\n".join(lines[index + 1:index + 3]):
            if line in diagnostics.get("unexpected_errors", []):
                diagnostics["unexpected_errors"].remove(line)
                diagnostics.setdefault("environment_errors", []).append(line)
    return {key: value for key, value in diagnostics.items() if value}


def run(godot: str, args: list[str]) -> None:
    command = [godot, "--log-file", str(Path(godot).parent / "proof.log"), *args]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    diagnostics = proof_diagnostics(result.stdout, command)
    if diagnostics:
        print("PCK_ENGINE_DIAGNOSTICS=" + json.dumps(diagnostics, ensure_ascii=False), flush=True)
    for line in result.stdout.splitlines():
        if any(marker in line for marker in ["SPINE_EXPORTED", "UID_", "EXPORTED_CONTENT", "ERROR:", "ObjectDB instances leaked"]):
            print(line)
    if result.returncode:
        raise RuntimeError(result.stdout)
    if diagnostics.get("unexpected_errors") or has_reported_failures(result.stdout) or any(
            marker in result.stdout for marker in ("SCRIPT ERROR:", "Parse Error:", "TEST_FAILED:", "PACK_VALIDATION_FAILED:")):
        raise RuntimeError("Godot reported errors during the export proof:\n" + result.stdout)
    if "--main-pack" in args and not completion_contract(result.stdout, args, "test")["ok"]:
        raise RuntimeError("Export proof did not complete its checks:\n" + result.stdout)


def pack_entries(path: Path):
    data = path.read_bytes()
    magic, version, *_ = struct.unpack_from("<5I", data)
    assert magic == 0x43504447 and version == 3
    base, directory = struct.unpack_from("<2Q", data, 24)
    count, = struct.unpack_from("<I", data, directory)
    cursor = directory + 4
    for _ in range(count):
        size, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        name = data[cursor:cursor + size].rstrip(b"\0").decode("utf-8")
        cursor += size
        offset, length = struct.unpack_from("<2Q", data, cursor)
        cursor += 36
        yield name, data[base + offset:base + offset + length]


def create_project(path: Path):
    path.mkdir()
    (path / "project.godot").write_text(PROJECT, encoding="utf-8")
    (path / "export_presets.cfg").write_text(PRESET, encoding="utf-8")
    (path / "main.tscn").write_text('[gd_scene format=3]\n[node name="Main" type="Node"]\n', encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("DOKU_GODOT") or "godot")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    source = repo / "products/meowdoku/assets/effect/spine/ui_cat_icon"
    with tempfile.TemporaryDirectory(prefix="content-export-proof-") as temporary:
        root = Path(temporary).resolve()
        # A copied executable + self-contained editor mode keeps editor settings in tmp.
        # Do not modify HOME or the user's installed editor's _sc_ marker.
        args.godot = isolated_engine(args.godot, root)
        for release in ["r1", "r2"]:
            project = root / release
            create_project(project)
            content = project / "content/proof" / release
            spine = content / "spine"
            spine.mkdir(parents=True)
            # Import textures first: this Spine importer resolves atlas textures during import.
            for extension in ["png"]:
                shutil.copyfile(source / ("maomi_fuor." + extension), spine / ("maomi_fuor." + extension))
            run(args.godot, ["--headless", "--editor", "--path", str(project), "--import"])
            for extension in ["atlas", "skel"]:
                shutil.copyfile(source / ("maomi_fuor." + extension), spine / ("maomi_fuor." + extension))
            (spine / "ui_cat_icon.tres").write_text('''[gd_resource type="SpineSkeletonDataResource" format=3]
[ext_resource type="SpineAtlasResource" path="res://content/proof/RELEASE/spine/maomi_fuor.atlas" id="1"]
[ext_resource type="SpineSkeletonFileResource" path="res://content/proof/RELEASE/spine/maomi_fuor.skel" id="2"]
[resource]
atlas_res = ExtResource("1")
skeleton_file_res = ExtResource("2")
'''.replace("RELEASE", release), encoding="utf-8")
            (content / "gradient.tres").write_text('[gd_resource type="Gradient" format=3 uid="uid://b7eqvkjrlbffh"]\n[resource]\nresource_name="' + release + '"\n', encoding="utf-8")
            (content / "container.tres").write_text('''[gd_resource type="GradientTexture2D" format=3]
[ext_resource type="Gradient" uid="uid://b7eqvkjrlbffh" path="res://content/proof/RELEASE/gradient.tres" id="1"]
[resource]
gradient = ExtResource("1")
'''.replace("RELEASE", release), encoding="utf-8")
            run(args.godot, ["--headless", "--editor", "--path", str(project), "--import"])
            run(args.godot, ["--headless", "--path", str(project), "--export-pack", "Proof", str(root / (release + ".pck"))])
            filtered_files = []
            filtered_dir = root / (release + "-filtered")
            filtered_dir.mkdir()
            for name, content_bytes in pack_entries(root / (release + ".pck")):
                if name.startswith("content/proof/" + release + "/spine/") or name.startswith(".godot/imported/"):
                    target = filtered_dir / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(content_bytes)
                    filtered_files.append({"source": str(target), "path": name})
            packer = root / (release + "-packer")
            create_project(packer)
            shutil.copyfile(repo / "tools/content/pack_raw.gd", packer / "pack.gd")
            (packer / "pack.json").write_text(json.dumps({"output": str(root / (release + "-filtered.pck")), "files": filtered_files}), encoding="utf-8")
            run(args.godot, ["--headless", "--path", str(packer), "--script", "res://pack.gd", "--", str(packer / "pack.json")])
        base = root / "base"
        create_project(base)
        (base / "probe.gd").write_text(PROBE, encoding="utf-8")
        (base / "builtin_gradient.tres").write_text('[gd_resource type="Gradient" format=3 uid="uid://b7eqvkjrlbffh"]\n[resource]\nresource_name="builtin"\n', encoding="utf-8")
        (base / "builtin_container.tres").write_text('[gd_resource type="GradientTexture2D" format=3]\n[ext_resource type="Gradient" uid="uid://b7eqvkjrlbffh" path="res://builtin_gradient.tres" id="1"]\n[resource]\ngradient=ExtResource("1")\n', encoding="utf-8")
        (base / "main.tscn").write_text('[gd_scene format=3]\n[ext_resource type="Script" path="res://probe.gd" id="1"]\n[node name="Main" type="Node"]\nscript=ExtResource("1")\n', encoding="utf-8")
        run(args.godot, ["--headless", "--editor", "--path", str(base), "--import"])
        run(args.godot, ["--headless", "--path", str(base), "--export-pack", "Proof", str(root / "base.pck")])
        run(args.godot, ["--headless", "--path", str(root), "--main-pack", str(root / "base.pck"), "--", str(root / "r1.pck"), str(root / "r2.pck")])
        run(args.godot, ["--headless", "--path", str(root), "--main-pack", str(root / "base.pck"), "--", str(root / "r1-filtered.pck"), str(root / "r2-filtered.pck"), "filtered"])
        print("PCK_PROOF_OK cases=2", flush=True)


if __name__ == "__main__":
    main()
