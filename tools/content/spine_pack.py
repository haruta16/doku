"""Restricted Spine publication: clean import, export, strip global metadata, validate.

Only PNG + matching .atlas/.skel pairs are authored inputs. Existing .import and
.tres files are never copied: each generation receives newly imported resource
UIDs and generated, script-free SpineSkeletonDataResource wrappers.
"""
from __future__ import annotations
from pathlib import Path
import json
import os
import shutil
import struct
import subprocess

PROJECT = '''config_version=5
[application]
config/name="ContentExportProof"
[rendering]
renderer/rendering_method="gl_compatibility"
[editor]
export/convert_text_resources_to_binary=false
'''
PRESET = '''[preset.0]
name="Content"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
'''


def isolated_engine(original: str, root: Path) -> str:
    source = shutil.which(original)
    if source is None:
        raise ValueError("Godot executable not found; set --godot or DOKU_GODOT")
    target = root / "engine" / ("Godot.exe" if os.name == "nt" else "Godot")
    target.parent.mkdir()
    shutil.copy2(Path(source).resolve(), target)
    (target.parent / "_sc_").touch()
    return str(target)


def run_engine(engine: str, arguments: list[str]) -> str:
    result = subprocess.run([engine, "--headless", "--log-file", str(Path(engine).parent / "content.log"), *arguments], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
    user_directory = Path.home() / "Library/Application Support/Godot/app_userdata/ContentExportProof"
    infrastructure = {f"ERROR: Could not create directory: '{user_directory}'.",
                      f"ERROR: Error attempting to create data dir: {user_directory}.",
                      "ERROR: Could not open 'user://' directory: 'user://'.",
                      'ERROR: Condition "ret != noErr" is true. Returning: ""'}
    errors = [line for line in result.stdout.splitlines() if ("ERROR:" in line or "PACK_VALIDATION_FAILED" in line) and line not in infrastructure]
    if result.returncode or errors:
        raise RuntimeError(result.stdout)
    return result.stdout


def read_pack(path: Path):
    data = path.read_bytes()
    if len(data) < 108:
        raise ValueError("Truncated export pack")
    magic, version, *_ = struct.unpack_from("<5I", data)
    if magic != 0x43504447 or version != 3:
        raise ValueError("This publisher requires Godot 4.6 PCK v3")
    base, directory = struct.unpack_from("<2Q", data, 24)
    count, = struct.unpack_from("<I", data, directory)
    cursor = directory + 4
    for _ in range(count):
        length, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        name = data[cursor:cursor + length].rstrip(b"\0").decode("utf-8")
        cursor += length
        offset, size = struct.unpack_from("<2Q", data, cursor)
        flags, = struct.unpack_from("<I", data, cursor + 32)
        cursor += 36
        if flags or base + offset + size > directory:
            raise ValueError("Unsupported exported PCK entry")
        yield name, data[base + offset:base + offset + size]


def project_at(path: Path) -> None:
    path.mkdir()
    (path / "project.godot").write_text(PROJECT, encoding="utf-8")


def build_spine_pack(godot: str, source: Path, destination: Path, work: Path, product: str, release: str, repo: Path, raw_assets: Path | None = None) -> None:
    from build_release import files_under, RAW
    engine = isolated_engine(godot, work)
    project = work / "spine-project"
    project_at(project)
    (project / "export_presets.cfg").write_text(PRESET, encoding="utf-8")
    namespace = f"content/{product}/{release}"
    authored = []
    for original, relative in files_under(source):
        if original.suffix.lower() not in {".png", ".atlas", ".skel"}:
            continue
        if original.relative_to(source).as_posix() != relative:
            raise ValueError("Spine publication filenames must already be lowercase; atlas references are case sensitive")
        target = project / namespace / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if original.suffix == ".png":
            shutil.copyfile(original, target)
        else:
            authored.append((original, target))
    run_engine(engine, ["--editor", "--path", str(project), "--import"])
    wrappers = 0
    for original, target in authored:
        shutil.copyfile(original, target)
        if target.suffix != ".atlas":
            continue
        matching = original.with_suffix(".skel")
        if not matching.is_file():
            raise ValueError(f"Atlas needs a same-named .skel file: {original}")
        relative = target.relative_to(project).as_posix()
        wrapper = f'''[gd_resource type="SpineSkeletonDataResource" format=3]
[ext_resource type="SpineAtlasResource" path="res://{relative}" id="1"]
[ext_resource type="SpineSkeletonFileResource" path="res://{relative.removesuffix('.atlas')}.skel" id="2"]
[resource]
atlas_res = ExtResource("1")
skeleton_file_res = ExtResource("2")
'''
        target.with_suffix(".tres").write_text(wrapper, encoding="utf-8")
        wrappers += 1
    if not wrappers:
        raise ValueError("No .atlas/.skel pair found")
    run_engine(engine, ["--editor", "--path", str(project), "--import"])
    exported = work / "exported.pck"
    run_engine(engine, ["--path", str(project), "--export-pack", "Content", str(exported)])
    extracted = work / "filtered"
    extracted.mkdir()
    pack_files = []
    for name, data in read_pack(exported):
        if not (name.startswith(namespace + "/") or name.startswith(".godot/imported/")):
            continue
        target = extracted / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        pack_files.append({"source": str(target), "path": name})
    if raw_assets:
        occupied = {entry["path"] for entry in pack_files}
        for original, relative in files_under(raw_assets):
            name = namespace + "/" + relative
            if original.suffix.lower() not in RAW or name in occupied or name + ".import" in occupied:
                raise ValueError(f"Raw asset conflicts with the imported resource closure: {relative}")
            pack_files.append({"source": str(original), "path": name})
    packer = work / "packer"
    project_at(packer)
    shutil.copyfile(repo / "tools/content/pack_raw.gd", packer / "pack.gd")
    spec = packer / "pack.json"
    spec.write_text(json.dumps({"output": str(destination), "files": pack_files}), encoding="utf-8")
    run_engine(engine, ["--path", str(packer), "--script", "res://pack.gd", "--", str(spec)])
    verifier = work / "verifier"
    project_at(verifier)
    (verifier / "scripts/framework/content").mkdir(parents=True)
    for name in ["content_manifest.gd", "content_raw_pack.gd"]:
        shutil.copyfile(repo / "scripts/framework/content" / name, verifier / "scripts/framework/content" / name)
    shutil.copyfile(repo / "tools/content/verify_pack.gd", verifier / "verify.gd")
    result = run_engine(engine, ["--path", str(verifier), "--script", "res://verify.gd", "--", str(destination), product, release, "spine_pck"])
    if "PACK_VALIDATED spine_pck" not in result:
        raise RuntimeError(result)
