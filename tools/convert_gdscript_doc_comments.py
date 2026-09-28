#!/usr/bin/env python3
"""Promote declaration comments in GDScript files to documentation comments.

Only unindented ``#`` comment blocks associated with script-level declarations
are changed. Section dividers and comments inside function bodies remain regular
comments. The script is idempotent: existing ``##`` comments are never changed.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


DECLARATION_RE = re.compile(
    r"^(?:(?:static|abstract)\s+)?func\s+"
    r"|^signal\s+"
    r"|^(?:(?:static)\s+)?(?:const|var)\s+"
    r"|^@(?:onready|export(?:_[a-z_]+)?)(?:\([^\n]*\))?\s+var\s+"
)
ANNOTATION_RE = re.compile(r"^@[a-zA-Z_][a-zA-Z0-9_]*(?:\([^\n]*\))?\s*$")
SINGLE_HASH_COMMENT_RE = re.compile(r"^#(?!#)")
SECTION_DIVIDER_RE = re.compile(
    r"^\s*(?:={3,}|-{3,}|─{3,}|━{3,})(?:.*(?:={3,}|-{3,}|─{3,}|━{3,}))?\s*$"
)


def line_body(line: str) -> str:
    return line.rstrip("\r\n")


def is_single_hash_comment(line: str) -> bool:
    return SINGLE_HASH_COMMENT_RE.match(line_body(line)) is not None


def is_section_divider(line: str) -> bool:
    body = line_body(line)[1:].strip()
    return SECTION_DIVIDER_RE.fullmatch(body) is not None


def preceding_comment_block(lines: list[str], declaration_index: int) -> range:
    """Return the contiguous single-hash block associated with a declaration."""
    index = declaration_index - 1
    while index >= 0 and ANNOTATION_RE.fullmatch(line_body(lines[index])):
        index -= 1

    block_end = index + 1
    while index >= 0 and is_single_hash_comment(lines[index]):
        index -= 1
    return range(index + 1, block_end)


def indices_to_promote(lines: list[str]) -> set[int]:
    result: set[int] = set()

    # A leading comment block describes the script/class itself.
    index = 0
    while index < len(lines) and is_single_hash_comment(lines[index]):
        if not is_section_divider(lines[index]):
            result.add(index)
        index += 1

    # A top-level comment block immediately before a declaration documents it.
    for index, line in enumerate(lines):
        if not DECLARATION_RE.match(line_body(line)):
            continue
        block = preceding_comment_block(lines, index)
        if not block:
            continue

        # If a section heading shares the block, only the explanatory lines
        # following the final heading belong to the declaration documentation.
        start = block.start
        for comment_index in block:
            if is_section_divider(lines[comment_index]):
                start = comment_index + 1
        for comment_index in range(start, block.stop):
            result.add(comment_index)

    return result


def convert_file(path: Path, *, check: bool) -> int:
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    indices = indices_to_promote(lines)
    if not indices:
        return 0

    for index in indices:
        lines[index] = "#" + lines[index]
    converted = "".join(lines)
    if not check:
        path.write_text(converted, encoding="utf-8")
    return len(indices)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=Path("scripts"),
        help="directory containing .gd files (default: scripts)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="report what would change without writing files",
    )
    args = parser.parse_args()

    paths = sorted(args.root.rglob("*.gd"))
    changed_files = 0
    changed_lines = 0
    for path in paths:
        count = convert_file(path, check=args.check)
        if count:
            changed_files += 1
            changed_lines += count

    action = "would promote" if args.check else "promoted"
    print(f"{action} {changed_lines} comment lines in {changed_files} files")
    return 1 if args.check and changed_files else 0


if __name__ == "__main__":
    raise SystemExit(main())
