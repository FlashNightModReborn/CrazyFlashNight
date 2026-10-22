"""Strict fail-closed contract for the Astra-owned converter-ready.json signal.

The signal is read-only for this line. Any missing field, unknown file field,
duplicate path, path escape, byte/sha mismatch, unexpected schema/status, or a
job inconsistent with the live map-input rejects the whole batch; presence of
a JSON file alone never authorizes a build. Raising ContractError is the only
failure mode; callers decide whether to aggregate or abort.
"""
from pathlib import Path, PurePosixPath
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
NV = HERE.parent
RUNTIME = NV.parent
ROOT = RUNTIME.parents[1]
SIGNAL = HERE / 'converter-ready.json'
MAP_INPUT = ROOT / 'tools/cf6-map-source/generated/map-input.json'
ARCHIVE = 'flashswf/arts/new/Codex素材源稿/CF6地图'
ASSET_DIR = 'tools/cf6-map-runtime/native-vector/batch/assets'
REQUIRED_SCHEMA = 'cf6-native-converter-ready.v1'
REQUIRED_STATUS = 'ready_for_K3_source_preparation'
ENTRY = 'tools/cf6-map-runtime/native-vector/build-layer.py'
SHA_RE = re.compile(r'[0-9a-f]{64}\Z')
# Actual import closure of build-layer.py read from source: build-a01.py and
# build.py via load_module, native_xfl.py on --assemble, svg_to_xfl_legacy.py
# and the DejaVuSans-Bold.ttf text metric font via build-a01.py constants.
EXPECTED_DEPS = {
    'tools/cf6-map-runtime/native-vector/build-layer.py',
    'tools/cf6-map-runtime/native-vector/build-a01.py',
    'tools/cf6-map-runtime/build.py',
    'tools/cf6-map-runtime/native_xfl.py',
    'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
    'flashswf/arts/new/Codex素材源稿/CF6地图/A08-R5/reference/vehicles-props-DejaVuSans-Bold.ttf',
}
JOB_FIELDS = {'map', 'layer', 'name', 'source', 'sourceSha256',
              'ownedLayersDirectory', 'ownedCandidateDirectory', 'prepareArguments'}
MAPS = ['A09', 'A10', 'A11', 'A12', 'A13', 'A14', 'A15', 'A16', 'A17', 'A18', 'A19', 'A20', 'A22']
LAYERS = ('background', 'foreground', 'elevator-scroll')


class ContractError(Exception):
    pass


def sha_bytes(raw):
    return hashlib.sha256(raw).hexdigest()


def sha_file(path):
    return sha_bytes(path.read_bytes())


def _require(condition, message):
    if not condition:
        raise ContractError(message)


def _rel_path(value, field):
    _require(isinstance(value, str) and value, field + ' must be a non-empty string')
    pure = PurePosixPath(value)
    _require(not value.startswith('/') and ':' not in value and '\\' not in value,
             field + ' must be a repo-relative posix path: ' + repr(value))
    _require('..' not in pure.parts, field + ' escapes the repo: ' + repr(value))
    return value


def expected_name(map_id, layer):
    return 'CF6_' + map_id + '_' + ('BG' if layer == 'background' else layer) + '_VectorCandidate01'


def dependency_identity():
    """Live sha256/bytes of the pinned dependency files, keyed by repo-relative path."""
    identity = {}
    for rel in sorted(EXPECTED_DEPS):
        path = ROOT / rel
        raw = path.read_bytes()
        identity[rel] = {'sha256': sha_bytes(raw), 'bytes': len(raw)}
    return identity


def load_ready(signal=SIGNAL):
    """Validate the signal and every on-disk byte it pins. Returns (body, files, jobs)."""
    _require(signal.is_file(), 'converter-ready.json absent; Astra-owned stability signal is required')
    try:
        body = json.loads(signal.read_text(encoding='utf-8'))
    except Exception as exc:
        raise ContractError('converter-ready.json unreadable: ' + str(exc))
    _require(isinstance(body, dict), 'signal top level must be a JSON object')
    _require(body.get('schema') == REQUIRED_SCHEMA,
             'schema must be ' + REQUIRED_SCHEMA + ', got ' + repr(body.get('schema')))
    _require(body.get('status') == REQUIRED_STATUS,
             'status must be ' + REQUIRED_STATUS + ', got ' + repr(body.get('status')))
    files = body.get('files')
    _require(isinstance(files, list) and files, 'files must be a non-empty array')
    pinned = {}
    for index, entry in enumerate(files):
        where = 'files[' + str(index) + ']'
        _require(isinstance(entry, dict), where + ' must be an object')
        _require(set(entry) == {'path', 'sha256', 'bytes'},
                 where + ' fields must be exactly path/sha256/bytes, got ' + repr(sorted(entry)))
        rel = _rel_path(entry['path'], where + '.path')
        _require(SHA_RE.fullmatch(entry['sha256'] or '') is not None if isinstance(entry['sha256'], str) else False,
                 where + '.sha256 must be 64 lowercase hex chars')
        _require(isinstance(entry['bytes'], int) and entry['bytes'] > 0, where + '.bytes must be a positive integer')
        _require(rel not in pinned, 'duplicate dependency path: ' + rel)
        path = ROOT / rel
        _require(path.is_file(), 'declared dependency missing on disk: ' + rel)
        raw = path.read_bytes()
        _require(len(raw) == entry['bytes'], 'bytes mismatch for ' + rel)
        _require(sha_bytes(raw) == entry['sha256'], 'sha256 mismatch for ' + rel)
        pinned[rel] = {'sha256': entry['sha256'], 'bytes': entry['bytes']}
    _require(set(pinned) == EXPECTED_DEPS,
             'dependency set differs from the actual build-layer.py import closure; missing='
             + repr(sorted(EXPECTED_DEPS - set(pinned))) + ' unexpected=' + repr(sorted(set(pinned) - EXPECTED_DEPS)))
    _require(body.get('entry') == ENTRY, 'entry must be ' + ENTRY)
    index_rel = _rel_path(body.get('inputIndex'), 'inputIndex')
    _require(index_rel == MAP_INPUT.relative_to(ROOT).as_posix(), 'inputIndex must be the live map-input.json')
    _require(isinstance(body.get('inputIndexSha256'), str) and SHA_RE.fullmatch(body['inputIndexSha256']),
             'inputIndexSha256 must be 64 lowercase hex chars')
    _require(MAP_INPUT.is_file(), 'map-input.json missing on disk')
    _require(sha_file(MAP_INPUT) == body['inputIndexSha256'], 'map-input.json differs from the pinned inputIndexSha256')
    jobs = body.get('jobs')
    _require(isinstance(jobs, list) and jobs, 'jobs must be a non-empty array')
    seen_names = set()
    seen_pairs = set()
    checked = []
    for index, job in enumerate(jobs):
        where = 'jobs[' + str(index) + ']'
        _require(isinstance(job, dict), where + ' must be an object')
        _require(set(job) == JOB_FIELDS, where + ' fields must be exactly ' + repr(sorted(JOB_FIELDS)))
        _require(job['map'] in MAPS, where + '.map outside the authorized 13 maps: ' + repr(job['map']))
        _require(job['layer'] in LAYERS, where + '.layer invalid: ' + repr(job['layer']))
        name = expected_name(job['map'], job['layer'])
        _require(job['name'] == name, where + '.name must be ' + name)
        _require((job['map'], job['layer']) not in seen_pairs, 'duplicate job for ' + name)
        _require(name not in seen_names, 'duplicate job name ' + name)
        seen_pairs.add((job['map'], job['layer']))
        seen_names.add(name)
        source = _rel_path(job['source'], where + '.source')
        _require(source.startswith(ARCHIVE + '/'), where + '.source outside the CF6 archive: ' + source)
        _require(isinstance(job['sourceSha256'], str) and SHA_RE.fullmatch(job['sourceSha256']),
                 where + '.sourceSha256 must be 64 lowercase hex chars')
        source_path = ROOT / source
        _require(source_path.is_file(), where + '.source missing on disk: ' + source)
        _require(sha_file(source_path) == job['sourceSha256'], where + ' source sha256 mismatch: ' + source)
        _require(job['ownedLayersDirectory'] == 'tools/cf6-map-runtime/native-vector/layers/' + name,
                 where + '.ownedLayersDirectory must be the owned layer dir of ' + name)
        _require(job['ownedCandidateDirectory'] == 'flashswf/backgrounds/cf6/' + name,
                 where + '.ownedCandidateDirectory must be the owned candidate dir of ' + name)
        _require(job['prepareArguments'] == ['--map', job['map'], '--layer', job['layer'], '--asset-dir', ASSET_DIR],
                 where + '.prepareArguments must pin map/layer and the batch asset dir')
        checked.append(job)
    return body, pinned, checked


def verify_unchanged(pinned, signal_sha, consumed=()):
    """Re-hash pinned dependencies, the signal itself and consumed inputs; raise on drift."""
    problems = []
    for rel, expect in pinned.items():
        path = ROOT / rel
        if not path.is_file():
            problems.append('dependency vanished: ' + rel)
            continue
        raw = path.read_bytes()
        if len(raw) != expect['bytes'] or sha_bytes(raw) != expect['sha256']:
            problems.append('dependency mutated: ' + rel)
    if not SIGNAL.is_file() or sha_file(SIGNAL) != signal_sha:
        problems.append('converter-ready.json changed during the batch')
    for rel, expect_sha in consumed:
        path = ROOT / rel
        if not path.is_file() or sha_file(path) != expect_sha:
            problems.append('consumed input changed: ' + rel)
    if problems:
        raise ContractError('; '.join(problems))
