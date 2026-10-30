"""Retain a successful all-suite report and its referenced isolated process logs."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import tempfile
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('target', type=Path)
args = parser.parse_args()
source, target = args.source.resolve(), args.target.resolve()
report = json.loads((source / 'report.json').read_text())
assert report['ok'] and report['suite'] == 'all' and not report['changed_inputs']
assert report['passed'] == report['planned'] == report['executed'] and not report['excluded']
assert json.loads((source / 'summary.json').read_text())['ok']
assert not target.exists(), 'Archive target must be new'
shutil.copytree(source, target)
paths = set()
inline_logs = []
recorded_log_hashes = {}
direct_log_paths = set()
command_log_references = {}
inline_engine_candidates = {}
verified_child_documents = {}

def check_hash(raw, expected, label):
    assert isinstance(expected, str) and len(expected) == 64, ('Invalid recorded SHA-256', label)
    actual = hashlib.sha256(raw).hexdigest()
    assert actual == expected, ('Recorded evidence hash mismatch', label, expected, actual)

def retained_artifact(name):
    path = Path(name)
    # verify retains top-level reports by basename, even when their original
    # absolute location is recorded in the parent completion object.
    relative = Path(path.name) if path.is_absolute() else path
    result = (target / relative).resolve()
    assert result.is_relative_to(target), ('Evidence path escapes archive', name)
    assert result.is_file(), ('Referenced evidence is absent from archive', name)
    return result

def normalized_log_path(name):
    path = Path(name)
    return str(path.resolve() if path.is_absolute() else (source / path).resolve())

def command_log(command):
    if not isinstance(command, list) or '--log-file' not in command:
        return None, None
    index = command.index('--log-file') + 1
    assert index < len(command) and isinstance(command[index], str), ('Malformed log command', command)
    path = normalized_log_path(command[index])
    normalized = list(command)
    normalized[index] = path
    return path, normalized

def visit(value, document, pointer='$'):
    if isinstance(value, list):
        for index, item in enumerate(value):
            visit(item, document, pointer + '/' + str(index))
    elif isinstance(value, dict):
        log = value.get('log')
        embedded_log = isinstance(log, str) and ('\n' in log or log.startswith('Godot Engine'))
        engine_path, normalized_command = command_log(value.get('command', []))
        if engine_path is not None:
            paths.add(engine_path)
            command_log_references.setdefault(engine_path, []).append(
                {'document': document, 'pointer': pointer, 'command': normalized_command})
        if isinstance(log, str):
            if embedded_log:
                expected = value.get('log_sha256')
                if expected:
                    check_hash(log.encode(), expected, document + ':inline-log:' + pointer)
                record = {'document': document, 'pointer': pointer + '/log',
                          'sha256': hashlib.sha256(log.encode()).hexdigest()}
                inline_logs.append(record)
                # Only a SHA-verified child report can later authorize substitution.
                # Merely finding a summary string or matching path is insufficient.
                if engine_path is not None and expected:
                    inline_engine_candidates.setdefault(engine_path, []).append(
                        {**record, 'recorded_inline_sha256': expected,
                         'command': normalized_command})
            elif log and Path(log).suffix == '.log':
                original = normalized_log_path(log)
                paths.add(original)
                direct_log_paths.add(original)
                expected = value.get('log_sha256')
                if expected:
                    assert original not in recorded_log_hashes or recorded_log_hashes[original] == expected, ('Conflicting recorded log hashes', original)
                    recorded_log_hashes[original] = expected
        if isinstance(value.get('report'), str) and value.get('sha256'):
            child = retained_artifact(value['report'])
            check_hash(child.read_bytes(), value['sha256'], document + ':child-report:' + value['report'])
            child_name = child.relative_to(target).as_posix()
            assert child_name not in verified_child_documents or verified_child_documents[child_name] == value['sha256'], ('Conflicting child report hashes', child_name)
            verified_child_documents[child_name] = value['sha256']
        if isinstance(value.get('inputs'), str) and value.get('inputs_sha256'):
            child = retained_artifact(value['inputs'])
            check_hash(child.read_bytes(), value['inputs_sha256'], document + ':inputs')
        for key, item in value.items():
            if isinstance(item, (dict, list)):
                visit(item, document, pointer + '/' + str(key))

def inline_substitute(original):
    # A raw logfile field is a separate retention promise, not an engine-path
    # duplicate from summary.sources. Never replace that promise with inline text.
    if original in direct_log_paths:
        return None
    references = command_log_references.get(original, [])
    candidates = [item for item in inline_engine_candidates.get(original, [])
                  if item['document'] in verified_child_documents]
    if not references or not candidates:
        return None
    matches = []
    for reference in references:
        exact = [item for item in candidates if item['command'] == reference['command']]
        if not exact:
            return None
        assert len({item['sha256'] for item in exact}) == 1, ('Conflicting inline engine logs', original, reference['command'])
        item = exact[0]
        if item not in matches:
            matches.append(item)
    return {'original_engine_log_path': original,
            'retention': 'inline_stdout_stderr_substitute',
            'engine_log_file_retained': False,
            'original_engine_log_missing': True,
            'reason': 'Disposable engine file is absent; the exact command has complete captured stdout/stderr in a retained SHA-verified child report. This is not a byte-for-byte copy of the engine --log-file output.',
            'inline_sources': [{**item,
                                'source_document_sha256': verified_child_documents[item['document']],
                                'original_inline_hash_verified': True} for item in matches],
            'matched_reference_count': len(references)}

for document in target.glob('*.json'):
    if document.name == 'inputs.json':
        continue
    visit(json.loads(document.read_text()), document.name)

allowed = (Path('/private/tmp'), Path(tempfile.gettempdir()).resolve())
records, missing, written, substitutions = [], [], set(), []
with zipfile.ZipFile(target / 'process-logs.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for original in sorted(paths):
        path = Path(original).resolve()
        assert any(path.is_relative_to(root) for root in allowed), ('Unexpected non-temporary log', original)
        # Publication case logs are already copied with the report directory.
        # Validate those retained bytes, not a possibly changed original later.
        retained = target / path.relative_to(source) if path.is_relative_to(source) else path
        if not retained.is_file():
            substitute = inline_substitute(str(path))
            if substitute is not None:
                substitutions.append(substitute)
            else:
                missing.append(original)
            continue
        raw = retained.read_bytes()
        expected = recorded_log_hashes.get(str(path))
        if expected:
            check_hash(raw, expected, original)
        sha = hashlib.sha256(raw).hexdigest()
        name = sha + '/' + path.name
        if name not in written:
            archive.writestr(name, raw)
            written.add(name)
        records.append({'original_path': original, 'archive_entry': name, 'sha256': sha, 'bytes': len(raw),
                        'recorded_sha256': expected, 'recorded_hash_verified': expected is not None})
assert not missing, ('Referenced process logs were not retained', missing)
index = {'schema': 2, 'scope': 'Successful frozen all-suite reports, source fingerprints, raw case logs, and referenced process logs; no player data, engine binary, private signing key, or disposable test project is included.',
         'process_logs': records, 'inline_logs_in_reports': inline_logs, 'inline_engine_log_substitutions': substitutions, 'missing_referenced_logs': missing,
         'process_archive': 'process-logs.zip', 'process_archive_sha256': hashlib.sha256((target / 'process-logs.zip').read_bytes()).hexdigest(),
         'artifact_sha256': {path.relative_to(target).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in sorted(target.rglob('*')) if path.is_file()}}
(target / 'archive-index.json').write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'archive': str(target), 'process_logs': len(records), 'inline_logs': len(inline_logs), 'inline_engine_substitutions': len(substitutions), 'artifacts': len(index['artifact_sha256']), 'missing': missing}))
