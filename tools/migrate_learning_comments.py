#!/usr/bin/env python3
"""Conservatively transfer learning comments between recovered GDScript trees.

Usage::

    python3 tools/migrate_learning_comments.py --old-root OLD/scripts \
        --new-root NEW/scripts --dry-run --report migration.json
    python3 tools/migrate_learning_comments.py --old-root OLD/scripts \
        --new-root NEW/scripts --report migration.json

Matching ignores comments, layout and blank lines, but preserves tokens, string
contents and logical-statement indentation. Multiline lambda statements also keep
their physical code-line layout: indentation inside a call can change the lambda's
control flow. Nested declarations must retain every enclosing class's base.
A function must match in its entirety
before *any* of its comments can move. Changed functions, ambiguous declarations,
unsafe continuation comments and missing documentation are reported for review.
The script does not infer semantic equivalence (including inferred versus explicit
types). It only inserts comments: existing code, comments, blank lines, line endings
and the final-newline state remain intact. Existing target comments take precedence.
No files are read or written at import time. Only Python's standard library is used.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
import re
import sys


WORD = re.compile(r"\w+", re.UNICODE)
DECLARATION = re.compile(
    r"^(?:(?:static|abstract)\s+)?"
    r"(?P<kind>func|class|var|const|signal|enum)\b\s*(?P<name>\w*)"
)
CLASS_NAME = re.compile(r"^class_name\s+(\w+)\b")


@dataclass
class Line:
    raw: str
    body: str
    eol: str
    code: str
    comment: str | None
    safe_before: bool
    complete: bool

    @property
    def indent(self) -> str:
        return self.body[: len(self.body) - len(self.body.lstrip(" \t"))]


@dataclass
class Statement:
    start: int
    end: int
    indent: int
    tokens: tuple[str, ...]
    text: str
    lambda_layout: tuple = ()

    @property
    def fingerprint(self) -> tuple:
        return self.indent, self.tokens, self.lambda_layout


@dataclass
class Unit:
    key: tuple[str, ...]
    kind: str
    name: str
    start: int
    end: int
    declaration: int
    fingerprint: tuple
    context: tuple = ()


@dataclass
class Source:
    text: str
    lines: list[Line]
    statements: list[Statement]
    units: list[Unit]
    class_name: str | None

    @property
    def fingerprint(self) -> tuple:
        return tuple(s.fingerprint for s in self.statements)


@dataclass
class Comment:
    start: int
    end: int
    anchor: int | None
    texts: list[str]
    inline: bool = False
    header: bool = False


@dataclass
class Edits:
    before: dict[int, list[str]] = field(default_factory=dict)
    inline: dict[int, str] = field(default_factory=dict)


def split_line(raw: str) -> tuple[str, str]:
    if raw.endswith("\r\n"):
        return raw[:-2], "\r\n"
    if raw.endswith(("\n", "\r")):
        return raw[:-1], raw[-1:]
    return raw, ""


def scan_lines(text: str) -> list[Line]:
    """Locate real comments and complete statement boundaries, including strings."""
    result: list[Line] = []
    quote: str | None = None
    brackets: list[str] = []
    continued = False
    # str.splitlines also splits U+2028 and control characters inside literals.
    # Only physical source line endings delimit GDScript lines here.
    physical_lines = re.findall(r"[^\r\n]*(?:\r\n|\r|\n|$)", text)
    for raw in physical_lines:
        if not raw:
            continue
        body, eol = split_line(raw)
        safe_before = quote is None and not brackets and not continued
        index = 0
        comment_at = None
        while index < len(body):
            char = body[index]
            if quote is not None:
                if char == "\\":
                    index += 2
                elif body.startswith(quote, index):
                    index += len(quote)
                    quote = None
                else:
                    index += 1
                continue
            if char == "#":
                comment_at = index
                break
            if char in "\"'":
                quote = char * 3 if body.startswith(char * 3, index) else char
                index += len(quote)
                continue
            if char in "([{":
                brackets.append(char)
            elif char in ")]}":
                if brackets and brackets[-1] == {")": "(", "]": "[", "}": "{"}[char]:
                    brackets.pop()
                else:
                    raise ValueError("unbalanced bracket at line %d" % (len(result) + 1))
            index += 1
        code = body if comment_at is None else body[:comment_at]
        continued = quote is None and code.rstrip().endswith("\\")
        if quote is not None and len(quote) == 1:
            # Do not silently match malformed or unsupported strings.
            raise ValueError("unterminated single-line string at line %d" % (len(result) + 1))
        result.append(Line(raw, body, eol, code,
                           None if comment_at is None else body[comment_at:],
                           safe_before, quote is None and not brackets and not continued))
    if quote is not None or brackets or continued:
        raise ValueError("unterminated string, bracket or continuation at end of file")
    return result


def tokens(code: str) -> tuple[str, ...]:
    """Tokenize without erasing spaces or newlines *inside* string literals."""
    result: list[str] = []
    index = 0
    while index < len(code):
        char = code[index]
        if char.isspace():
            index += 1
            continue
        if char == "\\" and code[index + 1:index + 2] in ("\n", "\r"):
            index += 1
            continue
        if char in "\"'":
            quote = char * 3 if code.startswith(char * 3, index) else char
            start = index
            index += len(quote)
            while index < len(code):
                if code[index] == "\\":
                    index += 2
                elif code.startswith(quote, index):
                    index += len(quote)
                    break
                else:
                    index += 1
            result.append(code[start:index])
            continue
        word = WORD.match(code, index)
        if word:
            result.append(word.group())
            index = word.end()
        else:
            # Punctuation remains individual tokens, so formatting cannot merge
            # identifiers or alter literals. Valid GDScript is a prerequisite.
            result.append(char)
            index += 1
    return tuple(result)


def parse_source(text: str) -> Source:
    lines = scan_lines(text)
    statements: list[Statement] = []
    start: int | None = None
    for index, line in enumerate(lines):
        if start is None and line.code.strip():
            if not line.safe_before:
                raise ValueError("no complete statement boundary at line %d" % (index + 1))
            start = index
        if start is not None and line.complete:
            code = "".join(item.code + item.eol for item in lines[start:index + 1])
            code_tokens = tokens(code)
            indent = len(lines[start].indent.expandtabs(4))
            lambda_layout = ()
            if index > start and any(
                pair == ("func", "(") for pair in zip(code_tokens, code_tokens[1:])
            ):
                # Parentheses suppress ordinary logical-statement boundaries,
                # but they do not erase lambda suite indentation. Be stricter
                # than token equivalence here, even for harmless line wrapping.
                lambda_layout = tuple(
                    (len(item.indent.expandtabs(4)) - indent, item.code.strip(" \t"))
                    for item in lines[start:index + 1] if item.code.strip()
                )
            statements.append(Statement(start, index, indent, code_tokens,
                                        code.strip(), lambda_layout))
            start = None

    units: list[Unit] = []
    class_name = None
    for index, statement in enumerate(statements):
        named = CLASS_NAME.match(statement.text)
        if named and statement.indent == 0:
            class_name = named.group(1)
        match = DECLARATION.match(statement.text)
        if not match:
            # An annotation may precede a member declaration on the same line.
            member = re.search(r"\b(var|const)\s+(\w+)\b", statement.text)
            if not statement.text.startswith("@") or member is None:
                continue
            kind, name = member.groups()
        else:
            kind, name = match.group("kind", "name")
        # Ignore local declarations: only class ancestry can own a declaration.
        enclosing = [unit for unit in units if unit.declaration < index < unit.end]
        if any(unit.kind != "class" for unit in enclosing):
            continue
        if statement.indent and not enclosing:
            continue
        ancestors = [unit for unit in enclosing if unit.kind == "class"]
        context = tuple(unit.name for unit in ancestors)
        ancestor_identities = []
        for ancestor in ancestors:
            body = statements[ancestor.declaration + 1:ancestor.end]
            body_indent = min((s.indent for s in body), default=-1)
            # Support both `class Inner extends Node:` and a class-body
            # `extends Node` statement, including all enclosing class levels.
            ancestor_identities.append((
                statements[ancestor.declaration].tokens,
                tuple(s.tokens for s in body
                      if s.indent == body_indent and s.tokens[:1] == ("extends",)),
            ))
        end = index + 1
        while end < len(statements) and statements[end].indent > statement.indent:
            end += 1
        unit_start = index
        while unit_start > 0:
            previous = statements[unit_start - 1]
            if previous.indent != statement.indent or not previous.text.startswith("@"):
                break
            if DECLARATION.search(previous.text) or re.search(r"\b(var|const)\s", previous.text):
                break
            unit_start -= 1
        key = (*context, kind, name or "<anonymous>")
        fingerprint = tuple((s.indent - statement.indent, s.tokens, s.lambda_layout)
                            for s in statements[unit_start:end])
        units.append(Unit(key, kind, name, unit_start, end, index, fingerprint,
                          tuple(ancestor_identities)))
    return Source(text, lines, statements, units, class_name)


def comments(source: Source) -> list[Comment]:
    starts = {statement.start: index for index, statement in enumerate(source.statements)}
    line_to_statement = {
        line: index for index, statement in enumerate(source.statements)
        for line in range(statement.start, statement.end + 1)
    }
    result: list[Comment] = []
    index = 0
    while index < len(source.lines):
        line = source.lines[index]
        if line.comment is None:
            index += 1
            continue
        if line.code.strip():
            result.append(Comment(index, index, line_to_statement.get(index),
                                  [line.comment], inline=True))
            index += 1
            continue
        start = index
        texts = []
        while index < len(source.lines):
            line = source.lines[index]
            if line.comment is None or line.code.strip():
                break
            texts.append(line.comment)
            index += 1
        following = index
        while following < len(source.lines) and not source.lines[following].body.strip():
            following += 1
        anchor = starts.get(following)
        is_header = anchor == 0 and all(not item.code.strip() for item in source.lines[:start])
        result.append(Comment(start, index - 1, anchor, texts, header=is_header))
    return result


def unit_for(source: Source, anchor: int) -> Unit | None:
    candidates = [unit for unit in source.units if unit.start <= anchor < unit.end]
    return min(candidates, key=lambda unit: unit.end - unit.start) if candidates else None


def preceding_comments(source: Source, line_index: int) -> list[str]:
    found: list[str] = []
    index = line_index - 1
    while index >= 0:
        line = source.lines[index]
        if not line.body.strip():
            index -= 1
            continue
        if line.comment is None or line.code.strip():
            break
        found.append(line.comment.rstrip())
        index -= 1
    return list(reversed(found))


def apply_edits(source: Source, edits: Edits) -> str:
    """Reconstruct with insertion provenance; assert all original bytes survive."""
    chunks: list[str] = []
    recovered: list[str] = []
    default_eol = next((line.eol for line in source.lines if line.eol), "\n")
    for index, line in enumerate(source.lines):
        if index in edits.before:
            if not line.safe_before:
                raise AssertionError("comment insertion inside a continued statement")
            chunks.extend(line.indent + comment + (line.eol or default_eol)
                          for comment in edits.before[index])
        if index in edits.inline:
            if not line.safe_before or not line.complete or line.comment is not None:
                raise AssertionError("inline insertion outside a complete single line")
            suffix = " " + edits.inline[index]
            changed = line.body + suffix + line.eol
            chunks.append(changed)
            recovered.append(changed[:len(line.body)] + line.eol)
        else:
            chunks.append(line.raw)
            recovered.append(line.raw)
    if "".join(recovered) != source.text:
        raise AssertionError("original code, whitespace or comments were altered")
    result = "".join(chunks)
    if parse_source(result).fingerprint != source.fingerprint:
        raise AssertionError("migration changed code tokens or indentation")
    return result


def migrate_text(old_text: str, new_text: str) -> tuple[str, dict]:
    """Pure in-memory migration API, also used by the command-line interface."""
    old, new = parse_source(old_text), parse_source(new_text)
    same_file = old.fingerprint == new.fingerprint
    identity = lambda source: tuple(
        statement.tokens for statement in source.statements
        if statement.indent == 0 and statement.tokens[:1] in (("class_name",), ("extends",))
    )
    same_identity = identity(old) == identity(new)
    old_counts = Counter(unit.key for unit in old.units)
    new_by_key: dict[tuple, list[Unit]] = defaultdict(list)
    for unit in new.units:
        new_by_key[unit.key].append(unit)
    mapped: dict[int, int] = {}
    reasons: dict[int, str] = {}
    if same_file:
        mapped = dict(enumerate(range(len(new.statements))))
    else:
        for unit in old.units:
            matches = new_by_key.get(unit.key, [])
            if not same_identity:
                reason = "changed_class_identity_or_base"
            elif old_counts[unit.key] > 1 or len(matches) > 1:
                reason = "ambiguous_declaration"
            elif not matches:
                reason = "declaration_removed_or_renamed"
            elif unit.context != matches[0].context:
                reason = "changed_enclosing_class"
            elif unit.fingerprint != matches[0].fingerprint:
                reason = "changed_function" if unit.kind == "func" else "changed_declaration"
            else:
                target = matches[0]
                for offset in range(unit.end - unit.start):
                    mapped[unit.start + offset] = target.start + offset
                continue
            for statement in range(unit.start, unit.end):
                reasons[statement] = reason

    edits = Edits()
    counts: Counter = Counter()
    review: list[dict] = []
    for comment in comments(old):
        anchor = comment.anchor
        reason = None
        if anchor is None:
            reason = "no_complete_following_statement"
        elif comment.header and not same_file:
            reason = "changed_file_header"
        elif anchor not in mapped:
            reason = reasons.get(anchor, "unmatched_context")
        elif not old.lines[comment.start].safe_before:
            reason = "comment_inside_continuation"
        elif comment.inline and not (old.lines[comment.start].complete and
                                    old.statements[anchor].start == old.statements[anchor].end):
            reason = "inline_comment_on_multiline_statement"
        if reason:
            counts[reason] += len(comment.texts)
            review.append({"old_line": comment.start + 1, "reason": reason,
                           "declaration": list(unit_for(old, anchor).key)
                           if anchor is not None and unit_for(old, anchor) else None,
                           "comments": comment.texts})
            continue
        target_statement = new.statements[mapped[anchor]]
        target_index = target_statement.start
        target_line = new.lines[target_index]
        existing = [] if comment.inline else preceding_comments(new, target_index)
        if not comment.inline:
            existing.extend(edits.before.get(target_index, []))
        if target_line.comment:
            existing.append(target_line.comment.rstrip())
        if target_index in edits.inline:
            existing.append(edits.inline[target_index].rstrip())
        if all(text.rstrip() in existing for text in comment.texts):
            counts["already_present"] += len(comment.texts)
            continue
        if existing:
            counts["target_has_comments"] += len(comment.texts)
            review.append({"old_line": comment.start + 1, "new_line": target_index + 1,
                           "reason": "target_has_comments", "comments": comment.texts})
            continue
        if not target_line.safe_before or " " in target_line.indent:
            reason = "unsafe_target_boundary_or_indent"
        elif comment.inline and target_statement.start != target_statement.end:
            # Do not relocate an inline explanation to one part of a reflowed
            # statement. Human review can decide whether a leading comment fits.
            reason = "inline_target_is_multiline"
        else:
            reason = None
        if reason:
            counts[reason] += len(comment.texts)
            review.append({"old_line": comment.start + 1, "new_line": target_index + 1,
                           "reason": reason, "comments": comment.texts})
            continue
        if comment.inline:
            edits.inline[target_index] = comment.texts[0]
            counts["migrated_inline"] += 1
        else:
            edits.before[target_index] = comment.texts
            counts["migrated_leading"] += len(comment.texts)

    result = apply_edits(new, edits)
    result_source = parse_source(result)
    undocumented = []
    for unit in result_source.units:
        statement = result_source.statements[unit.start]
        declaration_line = result_source.lines[statement.start]
        prefix = preceding_comments(result_source, statement.start)
        if not prefix and declaration_line.comment is None:
            undocumented.append({"line": statement.start + 1,
                                 "declaration": list(unit.key)})
    return result, {"code_equivalent": same_file, "counts": dict(counts),
                    "review": review, "undocumented_declarations": undocumented}


def read_text(path: Path) -> str:
    # Path.read_text() normalizes CRLF; these bytes are intentionally preserved.
    return path.read_bytes().decode("utf-8")


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old-root", type=Path, required=True)
    parser.add_argument("--new-root", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="preview without changing .gd files")
    mode.add_argument("--check", action="store_true", help="preview; exit 1 if migration is pending")
    parser.add_argument("--report", type=Path, help="write review and coverage details as JSON")
    args = parser.parse_args(argv)
    old_root, new_root = args.old_root.resolve(), args.new_root.resolve()
    if not old_root.is_dir() or not new_root.is_dir():
        parser.error("both roots must be existing directories")
    if old_root == new_root or old_root in new_root.parents or new_root in old_root.parents:
        parser.error("source and target trees must be separate and must not contain one another")

    old_paths = sorted(old_root.rglob("*.gd"))
    old_sources: dict[Path, tuple[str, Source]] = {}
    old_classes: dict[str, list[Path]] = defaultdict(list)
    errors: list[dict] = []
    for path in old_paths:
        try:
            text = read_text(path)
            source = parse_source(text)
            old_sources[path.relative_to(old_root)] = (text, source)
            if source.class_name:
                old_classes[source.class_name].append(path.relative_to(old_root))
        except (OSError, UnicodeError, ValueError) as exc:
            errors.append({"tree": "old", "path": str(path.relative_to(old_root)), "error": str(exc)})

    new_sources: dict[Path, tuple[str, Source]] = {}
    new_classes: Counter = Counter()
    for path in sorted(new_root.rglob("*.gd")):
        try:
            text = read_text(path)
            source = parse_source(text)
            new_sources[path.relative_to(new_root)] = (text, source)
            if source.class_name:
                new_classes[source.class_name] += 1
        except (OSError, UnicodeError, ValueError) as exc:
            errors.append({"tree": "new", "path": str(path.relative_to(new_root)), "error": str(exc)})

    files: list[dict] = []
    pending: list[tuple[Path, str]] = []
    used_old: set[Path] = set()
    totals: Counter = Counter()
    for relative, (new_text, new_source) in new_sources.items():
        old_relative = relative if relative in old_sources else None
        method = "relative_path"
        if old_relative is None and new_source.class_name:
            candidates = old_classes.get(new_source.class_name, [])
            if len(candidates) == 1 and new_classes[new_source.class_name] == 1:
                candidate = candidates[0]
                # A source that still has a same-path successor is not a rename.
                if candidate not in new_sources:
                    old_relative = candidate
                    method = "unique_class_name"
        if old_relative is None:
            new_result, detail = migrate_text("", new_text)
            detail["status"] = "no_old_source"
            totals["new_files_without_old_source"] += 1
        else:
            old_text, _ = old_sources[old_relative]
            try:
                new_result, detail = migrate_text(old_text, new_text)
            except (ValueError, AssertionError) as exc:
                errors.append({"tree": "migration", "path": str(relative), "error": str(exc)})
                continue
            used_old.add(old_relative)
            detail.update(old_path=str(old_relative), match_method=method)
        detail.update(path=str(relative), source_sha256=digest(new_text),
                      result_sha256=digest(new_result), changed=new_result != new_text)
        files.append(detail)
        totals.update(detail["counts"])
        totals["undocumented_declarations"] += len(detail["undocumented_declarations"])
        if new_result != new_text:
            pending.append((new_root / relative, new_result))

    report = {"format_version": 1, "old_root": str(old_root), "new_root": str(new_root),
              "mode": "check" if args.check else "dry_run" if args.dry_run else "write",
              "old_files": len(old_paths), "new_files": len(new_sources),
              "changed_files": len(pending), "totals": dict(totals), "errors": errors,
              "unmatched_old_files": sorted(str(path) for path in old_sources if path not in used_old),
              "files": files}
    # Validate every file before the first write; do not partially apply a plan
    # when a lexical error or invariant failure needs manual investigation.
    if not errors and not (args.check or args.dry_run):
        for path, updated in pending:
            path.write_bytes(updated.encode("utf-8"))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    action = "would update" if args.check or args.dry_run else "updated" if not errors else "blocked"
    print(f"{action}: {len(pending)} files; leading comments: {totals['migrated_leading']}; "
          f"inline comments: {totals['migrated_inline']}; review comments: "
          f"{sum(len(item['comments']) for file in files for item in file['review'])}; "
          f"undocumented declarations: {totals['undocumented_declarations']}; errors: {len(errors)}")
    for error in errors:
        print(f"ERROR {error['tree']}/{error['path']}: {error['error']}", file=sys.stderr)
    return 2 if errors else 1 if args.check and pending else 0


if __name__ == "__main__":
    raise SystemExit(main())
