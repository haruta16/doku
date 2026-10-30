#!/usr/bin/env python3
"""Build an auditable three-way staging tree; never mutate the checkout or select conflict winners."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

TEXT_EXTENSIONS = {'.gd', '.gdshader', '.tscn', '.tres', '.import', '.godot', '.cfg', '.py', '.json', '.txt', '.atlas', '.md', '.po', '.uid'}


def sha(data: bytes | None) -> str | None:
    return hashlib.sha256(data).hexdigest() if data is not None else None


def destination(path: str, exact: dict[str, str]) -> str:
    if path in exact:
        return exact[path]
    if path.endswith(('.uid', '.import')):
        suffix = '.uid' if path.endswith('.uid') else '.import'
        return destination(path[:-len(suffix)], exact) + suffix
    if path.startswith('assets/'):
        return 'products/meowdoku/' + path
    if path in ('icon.png', 'launcher.tscn'):
        return {'icon.png': 'products/meowdoku/assets/icons/project_icon.png', 'launcher.tscn': 'products/meowdoku/launcher.tscn'}[path]
    if path.startswith('scripts/editor/'):
        return path.replace('scripts/editor/', 'products/meowdoku/editor/', 1)
    for prefix, target in [('scripts/common/', 'products/meowdoku/app/platform/'), ('scripts/core/net/', 'products/meowdoku/app/network/'), ('scripts/core/log/', 'products/meowdoku/app/diagnostics/'), ('scripts/core/', 'products/meowdoku/app/state/')]:
        if path.startswith(prefix):
            return target + path[len(prefix):]
    if not path.startswith('scripts/module/'):
        return path
    module, rest = path[len('scripts/module/'):].split('/', 1)
    filename = Path(rest).name
    base = 'products/meowdoku/'
    if module == 'game_state':
        return base + 'app/state/' + rest
    if module == 'bank':
        return base + ('gameplay/content/' + rest[6:] if rest.startswith('model/') else 'gameplay/presentation/bank/' + rest)
    if module == 'gameplay':
        if rest.startswith('selector/'):
            return base + 'gameplay/application/selection/' + rest[len('selector/'):]
        if rest.startswith('core/'):
            return base + 'gameplay/domain/' + filename
        if rest.startswith('model/'):
            return base + 'gameplay/application/models/' + filename
        return base + 'gameplay/presentation/board/' + rest.removeprefix('view/')
    if module == 'game':
        if rest.startswith('input/'):
            return base + 'gameplay/presentation/' + rest
        if rest.startswith('core/'):
            return base + 'gameplay/domain/' + filename
        return base + 'gameplay/presentation/main/' + rest
    if module in ('golden_fish', 'color_challenge'):
        return base + 'gameplay/application/' + module + '/' + rest
    if module in ('daily', 'tutorial', 'result', 'how_to_play'):
        return base + 'gameplay/presentation/' + module + '/' + rest
    if module == 'ui':
        if rest == 'panel/launcher.gd':
            return base + 'app/bootstrap/launcher.gd'
        if rest.startswith(('base/', 'extensions/', 'widget/virtual_list')):
            return 'scripts/framework/ui/' + rest
        return base + 'app/ui/' + rest
    if module == 'common':
        return base + 'app/platform/' + rest
    if module in ('sound', 'session', 'tracker'):
        return base + 'app/services/' + rest
    if module == 'event_bus':
        return base + 'app/services/' + rest
    if module == 'debug':
        return base + 'app/diagnostics/' + rest
    if module == 'cheat':
        if rest == 'cheat_commands.gd':
            return base + 'app/diagnostics/cheat_commands.gd'
        return base + 'app/diagnostics/cheat/' + rest
    return base + 'app/features/' + module + '/' + rest


def tree(root: Path) -> dict[str, Path]:
    return {p.relative_to(root).as_posix(): p for p in root.rglob('*') if p.is_file() and not any(v in p.parts for v in ('.git', '.godot', '__pycache__'))}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', type=Path, default=Path('/tmp/doku-122-migration-session.json'))
    parser.add_argument('--apply', action='store_true')
    options = parser.parse_args()
    session = json.loads(options.session.read_text())
    current, original, upstream, stage = (Path(session[k]) for k in ('preport', 'original', 'upstream', 'stage'))
    original_files, new_files = tree(original), tree(upstream)
    exact = {a.removeprefix('res://'): b.removeprefix('res://') for a, b in json.loads((current / 'tools/validation/fixtures/recovered_relocations.json').read_text())['paths'].items()}
    # Source files moved upstream still retain their script UID; use that identity before directory defaults.
    current_uids = {p.read_text().strip(): p.relative_to(current).as_posix()[:-4] for p in current.rglob('*.gd.uid')}
    for path, source in new_files.items():
        if path.endswith('.gd.uid'):
            target = current_uids.get(source.read_text().strip())
            if target:
                exact[path[:-4]] = target
    mapping = {p: destination(p, exact) for p in sorted(original_files.keys() | new_files.keys())}
    reverse: dict[str, list[str]] = {}
    for source in new_files:
        reverse.setdefault(mapping[source], []).append(source)
    collisions = {p: sources for p, sources in reverse.items() if len(sources) > 1}
    if collisions:
        raise RuntimeError('Target collisions: ' + json.dumps(collisions))
    map_path = Path('/tmp/doku-122-full-map.json')
    map_path.write_text(json.dumps({'schema': 1, 'paths': {'res://' + a: 'res://' + b for a, b in mapping.items() if a != b}}, ensure_ascii=False, indent=2) + '\n')
    # Rewrite only active res:// identities, with directory-prefix support for constructed resource paths.
    prefixes = {'assets/': 'products/meowdoku/assets/', 'scripts/editor/': 'products/meowdoku/editor/'}
    for p in mapping:
        if not p.startswith('scripts/'):
            continue
        parent = str(Path(p).parent) + '/'
        children = [q for q in mapping if q.startswith(parent) and str(Path(q).parent) + '/' == parent]
        destinations = {str(Path(mapping[q]).parent) + '/' for q in children}
        if len(destinations) == 1:
            prefixes[parent] = next(iter(destinations))
    replacements = sorted({**prefixes, **mapping}.items(), key=lambda item: -len(item[0]))
    pattern = re.compile('|'.join(re.escape('res://' + a) for a, b in replacements if a != b))
    replace_map = {'res://' + a: 'res://' + b for a, b in replacements if a != b}

    def mapped_bytes(path: str, data: bytes) -> bytes:
        if path.startswith(('.autoconverted/', 'docs/')) or Path(path).suffix not in TEXT_EXTENSIONS:
            return data
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            return data
        return pattern.sub(lambda match: replace_map[match[0]], text).encode()

    incoming = stage.parent / (stage.name + '-incoming')
    bases = stage.parent / (stage.name + '-ancestor')
    conflicts = stage.parent / (stage.name + '-conflicts')
    rows = []
    for path in sorted(original_files.keys() | new_files.keys()):
        target = mapping[path]
        old = mapped_bytes(path, original_files[path].read_bytes()) if path in original_files else None
        new = mapped_bytes(path, new_files[path].read_bytes()) if path in new_files else None
        ours_path = current / target
        ours = ours_path.read_bytes() if ours_path.is_file() else None
        row = {'source': path, 'target': target, 'ancestor_sha256': sha(old), 'framework_sha256': sha(ours), 'incoming_sha256': sha(new)}
        result = ours
        if new == old:
            row['action'] = 'preserve_framework'
        elif new is None:
            if target in reverse:
                row['action'] = 'upstream_relocated'
            elif ours == old:
                row['action'], result = 'delete_upstream_removed', None
            else:
                row['action'] = 'review_delete'
        elif ours is None or ours == old:
            row['action'], result = 'import_upstream', new
        elif ours == new:
            row['action'] = 'already_equivalent'
        elif old is None:
            row['action'] = 'review_add_collision'
        else:
            if Path(path).suffix in TEXT_EXTENSIONS and b'\x00' not in old + ours + new:
                with tempfile.TemporaryDirectory(prefix='doku122-merge-') as temp:
                    inputs = []
                    for name, content in [('ours', ours), ('base', old), ('theirs', new)]:
                        p = Path(temp) / name
                        p.write_bytes(content)
                        inputs.append(str(p))
                    merged = subprocess.run(['git', 'merge-file', '-p', *inputs], capture_output=True)
                if merged.returncode == 0:
                    row['action'], result = 'merge_clean_review_required', merged.stdout
                else:
                    row['action'] = 'review_content_conflict'
                    if options.apply:
                        p = conflicts / target
                        p.parent.mkdir(parents=True, exist_ok=True)
                        p.write_bytes(merged.stdout)
            else:
                row['action'] = 'review_binary_conflict'
        if options.apply:
            for directory, content in [(incoming, new), (bases, old)]:
                if content is not None:
                    p = directory / target
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_bytes(content)
            p = stage / target
            live = p.read_bytes() if p.is_file() else None
            if result != ours and live != ours:
                row['action'] = 'review_parallel_change'
            elif result != ours:
                if result is None:
                    p.unlink(missing_ok=True)
                else:
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_bytes(result)
        rows.append(row)
    report = {'schema': 1, 'stage': str(stage), 'incoming': str(incoming), 'ancestor': str(bases), 'conflicts': str(conflicts), 'mapping': str(map_path), 'applied': options.apply, 'files': rows}
    report_path = Path('/tmp/doku-122-stage-report.json')
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    from collections import Counter
    print(json.dumps({'report': str(report_path), 'mapping': str(map_path), 'actions': dict(Counter(row['action'] for row in rows)), 'stage': str(stage)}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
