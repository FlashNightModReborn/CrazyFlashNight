"""CF6 K3 batch plan: enumerate native-vector targets, cross-check the Astra signal, write plan.json.

Writes ONLY batch/plan.json (and never touches layer dirs, assets, XFL or SWF).
--check additionally validates every hard precondition and exits non-zero on violation.
The ready contract is fail-closed: schema/status/files/jobs are validated by
ready_contract against live bytes; an unreadable or drifting signal is a problem,
never a pass.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ready_contract

HERE = Path(__file__).resolve().parent
NV = HERE.parent
RUNTIME = NV.parent
ROOT = RUNTIME.parents[1]
MAPS = ready_contract.MAPS
LAYERS = ready_contract.LAYERS
MAP_INPUT = ready_contract.MAP_INPUT
RUNTIME_INDEX = RUNTIME / 'generated/runtime-index.json'
SIGNAL = HERE / 'converter-ready.json'
PLAN = HERE / 'plan.json'
IMPORT_NATIVE = ROOT / 'tmp/cf6-roguelike-20261021/orchestration/import-native.ps1'
XLINK = '{http://www.w3.org/1999/xlink}href'
PATTERN_BUILDER = {'script': 'tools/cf6-map-runtime/native-vector/batch/build-pattern-layer.py',
                   'adapter': 'tools/cf6-map-runtime/native-vector/batch/pattern_adapter.py'}
PATTERN_MAPS = {'A18': 'background', 'A19': 'background', 'A20': 'background', 'A22': 'background'}
RUNTIME_FIELDS = ('status', 'exitCode', 'batchLog', 'gaps', 'reuseEvidence', 'reuseRejected', 'featureGap')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scan_svg(source):
    root = ET.parse(source).getroot()
    tags = {}
    textures = {}
    external = []
    vector_patterns = []
    for node in root.iter():
        tag = node.tag.split('}')[-1]
        tags[tag] = tags.get(tag, 0) + 1
        if tag == 'pattern':
            children = list(node)
            if not (len(children) == 1 and children[0].tag.split('}')[-1] == 'image'):
                vector_patterns.append(node.get('id'))
        if tag != 'image':
            continue
        href = node.get('href') or node.get(XLINK) or ''
        if href.startswith(('data:image/png;base64,', 'data:image/jpeg;base64,')):
            raw = base64.b64decode(href.split(',', 1)[1])
            key = hashlib.sha256(raw).hexdigest()
            textures[key] = {'sha256': key, 'bytes': len(raw), 'kind': 'jpeg' if href.startswith('data:image/jpeg;') else 'png'}
        else:
            external.append(href[:120])
    features = {k: tags[k] for k in ('path', 'rect', 'ellipse', 'circle', 'polygon', 'polyline', 'line', 'image', 'use',
                                     'linearGradient', 'radialGradient', 'clipPath', 'mask', 'filter', 'pattern', 'text') if tags.get(k)}
    return textures, external, features, sorted(vector_patterns)


def import_name_pattern():
    match = re.search(r"ValidatePattern\('([^']+)'\)", IMPORT_NATIVE.read_text(encoding='utf-8'))
    return match.group(1) if match else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    problems = []
    ready = pinned = jobs = None
    try:
        ready, pinned, jobs = ready_contract.load_ready()
    except ready_contract.ContractError as exc:
        problems.append('ready contract rejected: ' + str(exc))
    for path in (MAP_INPUT, RUNTIME_INDEX, IMPORT_NATIVE):
        if not path.is_file():
            problems.append('missing input file: ' + str(path.relative_to(ROOT)))
    if not MAP_INPUT.is_file() or not RUNTIME_INDEX.is_file():
        for p in problems:
            print('FAIL', p)
        sys.exit(1)
    pattern = import_name_pattern() if IMPORT_NATIVE.is_file() else None
    if pattern is None:
        problems.append('import-native.ps1 ValidatePattern unreadable; name acceptance unknown')
    map_input = json.loads(MAP_INPUT.read_text(encoding='utf-8'))['maps']
    runtime_index = json.loads(RUNTIME_INDEX.read_text(encoding='utf-8'))['maps']
    index_ids = {m['id'] for m in runtime_index}
    targets = []
    for map_id in MAPS:
        if map_id not in map_input:
            problems.append(map_id + ': absent from map-input')
            continue
        if map_id not in index_ids:
            problems.append(map_id + ': absent from runtime-index')
            continue
        for layer in map_input[map_id]['layers']:
            lid = layer['id']
            if lid not in LAYERS:
                continue
            name = ready_contract.expected_name(map_id, lid)
            source = (ROOT / layer['source']['svg']).resolve()
            gaps = []
            if not source.is_file():
                gaps.append('source SVG missing: ' + layer['source']['svg'])
            elif not source.is_relative_to(ROOT / ready_contract.ARCHIVE):
                gaps.append('source outside CF6 archive')
            if pattern is not None and not re.fullmatch(pattern, name):
                gaps.append('name rejected by import-native.ps1 ValidatePattern: ' + pattern)
            if gaps:
                targets.append({'name': name, 'map': map_id, 'layer': lid, 'status': 'blocked', 'gaps': gaps})
                continue
            textures, external, features, vector_patterns = scan_svg(source)
            if external:
                gaps.append('non-data-URI image refs rejected by build-layer: ' + json.dumps(external, ensure_ascii=False))
            builder = None
            if vector_patterns:
                if PATTERN_MAPS.get(map_id) == lid:
                    builder = dict(PATTERN_BUILDER, args=['--map', map_id], reason='vector-pattern-fill ' + ','.join(vector_patterns))
                else:
                    gaps.append('vector pattern outside the reviewed floor_lattice scope: ' + ','.join(vector_patterns))
            targets.append({
                'name': name, 'map': map_id, 'layer': lid,
                'source': source.relative_to(ROOT).as_posix(), 'sourceSha256': sha(source),
                'xfl': 'flashswf/backgrounds/cf6/' + name + '/' + name + '.xfl', 'swf': name + '.swf',
                'importRecipe': 'tools/cf6-map-runtime/native-vector/layers/' + name + '/import-textures.jsfl',
                'textureCount': len(textures), 'textures': sorted(textures.values(), key=lambda t: t['sha256']),
                'features': features,
                'assetDir': ready_contract.ASSET_DIR,
                'queue': (['import', 'assemble', 'publish'] if textures else ['assemble', 'publish']),
                'status': 'blocked' if gaps else 'planned',
                'gaps': gaps})
            if builder:
                targets[-1]['builder'] = builder
                targets[-1]['vectorPatterns'] = vector_patterns
    if jobs is not None:
        by_name = {t['name']: t for t in targets}
        job_names = {j['name'] for j in jobs}
        target_names = set(by_name)
        if job_names != target_names:
            problems.append('ready jobs differ from map-input enumeration; only-in-ready='
                            + repr(sorted(job_names - target_names)) + ' only-in-map-input=' + repr(sorted(target_names - job_names)))
        for job in jobs:
            target = by_name.get(job['name'])
            if target and (target.get('source') != job['source'] or target.get('sourceSha256') != job['sourceSha256']):
                problems.append('ready job ' + job['name'] + ' source differs from live map-input/SVG')
    signal = {'present': SIGNAL.is_file()}
    if signal['present']:
        signal['sha256'] = sha(SIGNAL)
    if ready is not None:
        signal.update({'schema': ready['schema'], 'status': ready['status'],
                       'converterBundleSha256': ready.get('converterBundleSha256'),
                       'dependencies': pinned, 'jobs': len(jobs)})
    if PLAN.is_file():
        try:
            previous = {t['name']: t for t in json.loads(PLAN.read_text(encoding='utf-8')).get('targets', [])}
        except Exception:
            previous = {}
        for target in targets:
            old = previous.get(target['name'])
            if old and old.get('source') == target['source'] and old.get('sourceSha256') == target['sourceSha256']:
                for field in RUNTIME_FIELDS:
                    if field in old and field not in ('gaps',):
                        target[field] = old[field]
                if old.get('gaps'):
                    target['gaps'] = target['gaps'] + [g for g in old['gaps'] if g not in target['gaps']]
    plan = {'schema': 'cf6-native-batch-plan.v2', 'generatedBy': 'tools/cf6-map-runtime/native-vector/batch/batch-plan.py',
            'generatedAt': __import__('datetime').datetime.now().isoformat(timespec='seconds'),
            'maps': MAPS, 'mapInput': {'path': MAP_INPUT.relative_to(ROOT).as_posix(), 'sha256': sha(MAP_INPUT)},
            'runtimeIndex': {'path': RUNTIME_INDEX.relative_to(ROOT).as_posix(), 'sha256': sha(RUNTIME_INDEX)},
            'importNamePattern': pattern,
            'signal': signal,
            'extraction': 'decode existing PNG/JPEG data URI bytes only; no scene rasterization, no per-frame PNG',
            'uniqueTextures': len({t['sha256'] for x in targets for t in x.get('textures', [])}),
            'cs6Operator': 'root only; this line never runs CS6',
            'targets': targets}
    PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    counts = {}
    for t in targets:
        counts[t['status']] = counts.get(t['status'], 0) + 1
    print(json.dumps({'plan': PLAN.relative_to(ROOT).as_posix(), 'targets': len(targets), 'status': counts,
                      'uniqueTextures': plan['uniqueTextures'], 'signal': signal['present'],
                      'signalAccepted': ready is not None, 'problems': problems}, ensure_ascii=False, indent=2))
    if args.check and problems:
        sys.exit(1)


if __name__ == '__main__':
    main()
