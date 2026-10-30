"""Apply the reviewed stage only after final verify and workspace drift checks."""
from pathlib import Path
import argparse
import hashlib
import json
import runpy
import shutil
import subprocess
import sys

p = argparse.ArgumentParser()
p.add_argument('--verification', type=Path, required=True)
p.add_argument('--apply', action='store_true')
args = p.parse_args()
session = json.loads(Path('/tmp/doku-122-migration-session.json').read_text())
created_inputs_path = Path('/tmp/doku122-created-file-inputs.json')
created_inputs = json.loads(created_inputs_path.read_text())['files']
workspace, stage = (Path(session[key]).resolve() for key in ('workspace', 'stage'))
assert workspace == Path('/Users/haruta/workspace/doku')
report = json.loads((args.verification / 'report.json').read_text())
assert report['ok'] and report['suite'] == 'all'
assert not report['changed_inputs'] and not report['excluded'] and not report['not_executed']
assert report['executed'] == report['passed'] == report['planned']
summary = json.loads((args.verification / 'summary.json').read_text())
assert summary['ok']
expected_inputs = json.loads((args.verification / 'inputs.json').read_text())

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None

def safe_name(name):
    q = Path(name)
    assert not q.is_absolute() and '..' not in q.parts and '.git' not in q.parts
    return q

def validate_stage_inputs(stage, expected_inputs):
    verifier = stage / 'tools/verify.py'
    expected_verifier = expected_inputs.get('tools/verify.py')
    assert expected_verifier and digest(verifier) == expected_verifier, 'Validated verify.py identity is required before loading its fingerprint function'
    changed = [name for name, sha in expected_inputs.items() if digest(stage / safe_name(name)) != sha]
    assert not changed, ('validated inputs changed', changed)
    old_path, old_bytecode = list(sys.path), sys.dont_write_bytecode
    try:
        sys.path.insert(0, str(stage / 'tools'))
        sys.dont_write_bytecode = True
        namespace = runpy.run_path(str(verifier), run_name='__migration_verify_fingerprints__')
        current_inputs = namespace['fingerprints']()
    finally:
        sys.path[:] = old_path
        sys.dont_write_bytecode = old_bytecode
    assert isinstance(current_inputs, dict), 'Verifier did not return an input fingerprint map'
    changed = sorted(name for name in expected_inputs.keys() | current_inputs.keys()
                     if expected_inputs.get(name) != current_inputs.get(name))
    assert not changed, ('validated input set or bytes changed', changed)
    return current_inputs

def validate_workspace_inputs(workspace, initial, created):
    allowed = {'docs/migration-1.22-plan.md', 'tools/migration_122_inventory.py', 'tools/migration_122_stage.py'}
    assert isinstance(created, dict) and set(created) == allowed, 'Only the three separately recorded migration-created files may extend workspace protection'
    assert not initial.keys() & created.keys(), 'Created-file records must not replace original workspace evidence'
    initial_drift = [name for name, sha in initial.items() if digest(workspace / safe_name(name)) != sha]
    created_drift = [name for name, sha in created.items() if digest(workspace / safe_name(name)) != sha]
    assert not initial_drift, ('original workspace changed', initial_drift)
    assert not created_drift, ('migration-created workspace files changed', created_drift)
    return {**initial, **created}

validate_stage_inputs(stage, expected_inputs)
protected_inputs = validate_workspace_inputs(workspace, session['fingerprints'], created_inputs)
branch = subprocess.check_output(['git', '-C', str(workspace), 'branch', '--show-current'], text=True).strip()
assert branch == 'migration/meowdoku-1.22-framework', branch
head = subprocess.check_output(['git', '-C', str(workspace), 'rev-parse', 'HEAD'], text=True).strip()
assert head == 'd89f94d1dd03d1b3369054351ee95ccc93d9cb93', head

def included(q):
    evidence_log = q.parts[:2] == ('docs', 'validation')
    return not set(q.parts) & {'.git', '.godot', '__pycache__', '.DS_Store'} and q.suffix != '.pyc' and (q.suffix != '.log' or evidence_log)

desired = {}
for path in stage.rglob('*'):
    rel = path.relative_to(stage)
    if included(rel):
        assert not path.is_symlink(), ('stage symlink', str(rel))
        if path.is_file():
            desired[rel.as_posix()] = digest(path)
added = sorted(name for name in desired if not (workspace / name).exists())
changed = sorted(name for name, sha in desired.items() if (workspace / name).exists() and digest(workspace / name) != sha)
deleted = sorted(name for name in session['fingerprints'] if name not in desired and included(safe_name(name)))
collisions = [name for name in changed if name not in protected_inputs]
assert not collisions, ('new user files collide with stage', collisions)
assert all(name in desired for name in created_inputs), 'Separately recorded migration-created files must retain reviewed stage updates'
for name in added + changed + deleted:
    target = workspace / safe_name(name)
    assert target.resolve().is_relative_to(workspace), ('external symlink target', name)
manifest = {'schema': 1, 'branch': branch, 'previous_head': head, 'validated_report': str(args.verification / 'report.json'),
            'source_files': desired, 'added': added, 'changed': changed, 'deleted': deleted,
            'applied': args.apply, 'initial_workspace_drift': [], 'validated_input_drift': [],
            'workspace_protection': {
                'initial_snapshot_fingerprints': session['fingerprints'],
                'migration_created_fingerprints': created_inputs,
                'migration_created_record': str(created_inputs_path),
                'migration_created_record_sha256': digest(created_inputs_path),
                'migration_created_drift': []}}
Path('/tmp/doku122-application-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'mode': 'apply' if args.apply else 'preview', 'added': len(added), 'changed': len(changed), 'deleted': len(deleted), 'files': len(desired)}))
if args.apply:
    for name in added + changed:
        target = workspace / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(stage / name, target)
    for name in deleted:
        (workspace / name).unlink()
    mismatch = [name for name, sha in desired.items() if digest(workspace / name) != sha]
    assert not mismatch, ('post-apply mismatch', mismatch)
    assert not any((workspace / name).exists() for name in deleted)
    print('APPLICATION_OK: all staged files match and reviewed deletions are absent')
