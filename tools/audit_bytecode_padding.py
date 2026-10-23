"""Audit Godot 4 token buffers; requires Python 3.14 compression.zstd.

String and NodePath alignment follows Godot 4.6.1 core/io/marshalls.cpp.
Only format padding is normalized. Identifier, constant, and token bytes stay
untouched; unrecognized Variant types fail rather than being guessed.
"""
import argparse
from compression import zstd
from pathlib import Path
import json
import struct


def u32(data, pos):
    return struct.unpack_from("<I", data, pos)[0]


def payload(path):
    data = path.read_bytes()
    assert data[:4] == b"GDSC"
    decoded = zstd.decompress(data[12:]) if u32(data, 8) else data[12:]
    assert not u32(data, 8) or len(decoded) == u32(data, 8)
    return decoded


def string_end(data, pos, padding):
    size = u32(data, pos)
    end = pos + 4 + size
    aligned = end + (-size % 4)
    padding.update(range(end, aligned))
    return aligned


def normalize(data):
    identifiers, constants = struct.unpack_from("<II", data)
    pos = 16
    for _ in range(identifiers):
        pos += 4 + u32(data, pos) * 4
    padding = set()
    for _ in range(constants):
        header = u32(data, pos)
        kind = header & 0xFF
        pos += 4
        if kind == 0:
            pass
        elif kind == 1:
            pos += 4
        elif kind in (2, 3):
            pos += 8 if header & (1 << 16) else 4
        elif kind in (4, 21):
            pos = string_end(data, pos, padding)
        elif kind == 22:
            names, subnames, flags = struct.unpack_from("<III", data, pos)
            assert names & 0x80000000
            count = (names & 0x7FFFFFFF) + subnames + bool(flags & 2)
            pos += 12
            for _ in range(count):
                pos = string_end(data, pos, padding)
        else:
            raise ValueError(f"Unsupported Variant type {kind} at {pos - 4}")
    normalized = bytearray(data)
    for offset in padding:
        normalized[offset] = 0
    return bytes(normalized), padding


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True, help="包含 roundtrip_results.json 和原始恢复产物的目录")
    parser.add_argument("--report", type=Path, help="报告输出路径，默认写入工作目录")
    args = parser.parse_args()
    base = args.work_dir.resolve()
    manifest = json.loads((base / "roundtrip_results.json").read_text())
    fixes = json.loads((base / "float_precision_fixes.json").read_text())
    fixed = {str(Path(x["path"]).with_suffix(".gdc")) for x in fixes}
    audited = []
    for item in manifest["entries"]:
        if item["status"] == "identical":
            continue
        original = base / "asset_pack/assets" / item["path"]
        if item["path"] in fixed:
            compiled = base / "precision_fixed_compiled" / Path(item["path"]).name
            assert original.read_bytes() == compiled.read_bytes()
            audited.append({"path": item["path"], "status": "identical_after_float_precision_fix"})
            continue
        compiled = base / "roundtrip_compiled" / (item["roundtrip_stem"] + ".gdc")
        a, b = payload(original), payload(compiled)
        normalized_a, padding_a = normalize(a)
        normalized_b, padding_b = normalize(b)
        assert normalized_a == normalized_b
        diffs = [i for i in range(len(a)) if a[i] != b[i]]
        assert set(diffs).issubset(padding_a & padding_b)
        audited.append({"path": item["path"], "status": "only_variant_string_alignment_padding", "changed_padding_bytes": len(diffs), "decompressed_offsets": diffs})
    raw_identical = manifest["counts"].get("identical", 0)
    precision_fixed = sum(x["status"] == "identical_after_float_precision_fix" for x in audited)
    padding_only = sum(x["status"] == "only_variant_string_alignment_padding" for x in audited)
    summary = {"raw_identical": raw_identical, "identical_after_precision_fixes": raw_identical + precision_fixed, "padding_only": padding_only, "accounted_for": raw_identical + len(audited), "differences": audited}
    report = args.report or (base / "bytecode_fidelity_report.json")
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
