"""Import the reviewed Blender export as a bounded stage-select presentation.

Source Blend remains in the recoverable archive. This importer owns generated
config and manifest; gameplay identities remain in stage-select-data.js.
"""
import argparse
import gzip
import hashlib
import io
import itertools
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'launcher/web/assets/stage-diorama/desert-region'
SETTINGS = ROOT / 'config/stage-select-desert.json'
DESIGN = ROOT / 'docs/design-data/desert-spatial-draft.json'
EXPECTED = {f'stage_34_{i}' for i in [0, 1, 2, 3, 4, 5, 6, 7, 10]}
SCENE_TRANSPORT_PATH = 'scene.glb.gz'
GIT_BLOB_LIMIT = 100 * 1024 * 1024
OUTPUT_NAMES = {SCENE_TRANSPORT_PATH, 'places.json', 'export-report.json',
                'config.json', 'source-object-map.json', 'manifest.json'}
GZIP_HEADER = bytes.fromhex('1f8b08000000000002ff')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf8')


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def compress_scene(scene):
    # GzipFile emits OS=255 independently of the host. gzip.compress(mtime=0)
    # delegated its header to zlib on some Python versions (OS byte differed).
    stream = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', fileobj=stream, compresslevel=9, mtime=0) as writer:
        writer.write(scene)
    packed = stream.getvalue()
    assert packed[:10] == GZIP_HEADER, 'Unexpected gzip timestamp, filename, level or platform header'
    assert gzip.decompress(packed) == scene, 'Lossless scene compression failed'
    assert len(packed) <= GIT_BLOB_LIMIT, 'Compressed scene exceeds the 100 MiB Git blob limit'
    transport = {'path': SCENE_TRANSPORT_PATH, 'encoding': 'gzip', 'sha256': sha(packed),
                 'bytes': len(packed), 'decodedBytes': len(scene)}
    return packed, transport


def transport_audit(scene_hash):
    return {'decodedSHA256': scene_hash, 'roundtripByteEqual': True,
            'gzipLevel': 9, 'gzipMtime': 0, 'gzipFilename': '', 'gzipOSByte': 255,
            'scope': 'Lossless repository transport; original GLB/export report identity is unchanged'}


def destination_files():
    return {p.relative_to(DEST).as_posix() for p in DEST.rglob('*') if p.is_file()} if DEST.exists() else set()


def assert_destination_inventory(allow_legacy=False):
    expected = OUTPUT_NAMES | ({'scene.glb'} if allow_legacy else set())
    actual = destination_files()
    assert actual <= expected if allow_legacy else actual == expected, {
        'unexpected': sorted(actual-expected), 'missing': sorted(OUTPUT_NAMES-actual)}


def decode_stored_scene(manifest):
    transport = manifest['sceneTransport']
    assert set(transport) == {'path', 'encoding', 'sha256', 'bytes', 'decodedBytes'}, 'Invalid scene transport fields'
    assert transport['path'] == SCENE_TRANSPORT_PATH and transport['encoding'] == 'gzip'
    packed = (DEST/SCENE_TRANSPORT_PATH).read_bytes()
    assert 0 < len(packed) == transport['bytes'] <= GIT_BLOB_LIMIT
    assert sha(packed) == transport['sha256'] and packed[:10] == GZIP_HEADER, 'Stored gzip identity/header mismatch'
    scene = gzip.decompress(packed)
    assert len(scene) == transport['decodedBytes'], 'Decoded GLB byte count mismatch'
    report = read(DEST/'export-report.json')
    assert len(scene) == report['statistics']['bytes'] and sha(scene) == report['statistics']['sha256'], 'Decoded bytes differ from the reviewed GLB identity'
    return scene, packed, transport


def vec(value):
    assert isinstance(value, list) and len(value) == 3
    assert all(isinstance(n, (int, float)) and math.isfinite(n) for n in value)
    return value


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def glb_audit(data):
    magic, version, length = struct.unpack_from('<III', data)
    assert (magic, version, length) == (0x46546C67, 2, len(data)), 'Invalid GLB'
    n, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20+n])
    assert all('uri' not in r for r in doc.get('buffers', [])), 'External buffer'
    assert all('uri' not in r for r in doc.get('images', [])), 'External image'
    primitives = [p for m in doc.get('meshes', []) for p in m['primitives']]
    triangles = sum(doc['accessors'][p['indices']]['count']//3 for p in primitives if p.get('mode', 4) == 4)
    return {'bytes': len(data), 'meshes': len(doc.get('meshes', [])),
            'primitives': len(primitives), 'triangles': triangles,
            'materials': len(doc.get('materials', [])), 'images': len(doc.get('images', []))}


def derive(places, settings, scene_hash, scene_transport):
    rows = places['places']
    if isinstance(rows, dict):
        rows = [dict(value, placeId=key) for key, value in rows.items()]
    pins = {}
    points = []
    for row in rows:
        sid = row.get('stageId') or row.get('id')
        anchor = vec(row.get('worldAnchor') or row.get('anchor'))
        bounds = row.get('bounds') or row.get('focusBounds')
        low, high = vec(bounds['min']), vec(bounds['max'])
        assert all(a <= b for a, b in zip(low, high)), 'Invalid bounds'
        if sid in EXPECTED:
            pins[sid] = {'worldAnchor': anchor, 'placeId': row.get('placeId', row.get('id')),
                         'focusBounds': {'min': low, 'max': high},
                         'labelX': 0, 'labelY': 35, 'labelHeight': 30,
                         **settings['pins'][sid]}
            pins[sid]['labelWidth'] = max(90, len(pins[sid]['shortLabel'])*14 + 20)
            if row.get('subareas'):
                pins[sid]['subareas'] = row['subareas']
            points.extend(itertools.product(*zip(low, high)))
        elif row.get('placeId', row.get('id')) in settings['contextPlaces']:
            radius = settings['contextRadius']
            points.extend(itertools.product(*[(max(lo, a-radius), min(hi, a+radius)) for lo, hi, a in zip(low, high, anchor)]))
    assert set(pins) == EXPECTED, 'Missing/extra stage anchors'
    yaw = math.radians(settings['camera']['yawDegrees'])
    pitch = math.radians(settings['camera']['pitchDegrees'])
    direction = [math.sin(yaw)*math.cos(pitch), math.sin(pitch), math.cos(yaw)*math.cos(pitch)]
    right = [math.cos(yaw), 0, -math.sin(yaw)]
    up = [-math.sin(yaw)*math.sin(pitch), math.cos(pitch), -math.cos(yaw)*math.sin(pitch)]
    xvalues, yvalues = [[dot(p, axis) for p in points] for axis in [right, up]]
    middle = [(min(values)+max(values))/2 for values in [xvalues, yvalues]]
    left, top, right_edge, bottom = settings['camera']['viewport']
    span = max((max(xvalues)-min(xvalues))*1024/(right_edge-left),
               (max(yvalues)-min(yvalues))*1024/(bottom-top))
    middle[0] -= ((left+right_edge)/2-512)*span/1024
    middle[1] += ((top+bottom)/2-288)*span/1024
    target = [right[i]*middle[0] + up[i]*middle[1] for i in range(3)]
    camera = {'gltfPosition': [target[i]+direction[i]*max(200, span*2) for i in range(3)],
              'gltfTarget': target, 'horizontalSpan': span, 'maxSpan': max(600, span*3),
              'minSpan': settings['camera']['minSpan']}
    # Stable labels are presentation-only. World anchors and gameplay IDs stay fixed.
    occupied = [(12, 500, 160, 574), (620, 460, 1024, 574), (900, 66, 1024, 150), (0, 0, 1024, 66)]
    markers = []
    for sid, pin in sorted(pins.items()):
        relative = [a-b for a, b in zip(pin['worldAnchor'], target)]
        x, y = 512+dot(relative, right)*1024/span, 288-dot(relative, up)*1024/span
        offsets = [(dx*dx+dy*dy, dx, dy) for dx in range(-60, 61, 4) for dy in range(-60, 61, 4)
                   if 40 < x+dx < 975 and 78 < y+dy < 454
                   and all(abs(x+dx-a) >= 44 or abs(y+dy-b) >= 44 for _, a, b in markers)]
        assert offsets, f'No distinct marker room for {sid}'
        _, dx, dy = min(offsets)
        pin['screenOffset'] = [dx, dy]
        x, y = x+dx, y+dy
        pin.update(x=x, y=y)
        markers.append((sid, x, y))
    for sid, pin in sorted(pins.items(), key=lambda pair: pair[1]['y']):
        x, y = pin['x'], pin['y']
        w = pin['labelWidth']/2
        candidates = []
        for dx in [0, -60, 60, -110, 110, -150, 150]:
            for dy in [35, -35, 62, -62, 88, -88]:
                box = (x+dx-w, y+dy-15, x+dx+w, y+dy+15)
                if box[0] < 8 or box[2] > 1016 or box[1] < 66 or box[3] > 554:
                    continue
                obstacles = occupied + [(a-20, b-20, a+20, b+20) for other, a, b in markers if other != sid]
                collisions = sum(box[0] < b[2]+5 and box[2] > b[0]-5 and box[1] < b[3]+5 and box[3] > b[1]-5 for b in obstacles)
                candidates.append((collisions*100000+dx*dx+dy*dy, dx, dy, box))
        assert candidates, f'No room for {sid}'
        _, pin['labelX'], pin['labelY'], box = min(candidates)
        occupied.append(box)
    return {'schema': 1, 'revision': settings['revision'], 'coordinateSystem': 'glTF X-east Y-up Z-south; source display units / 1000',
            'camera': camera, 'pins': pins, 'assetHashes': {'scene.glb': scene_hash}, 'sceneTransport': scene_transport}


def generator_inputs():
    paths = [SETTINGS, DESIGN, ROOT/'docs/design-data/desert-multistage-expansion.json', Path(__file__),
             *sorted(p for p in (ROOT/'tools/desert-runtime').glob('*.py') if not p.name.startswith('inspect_'))]
    return [{'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p.read_bytes())} for p in paths]


def check_export_inputs(report):
    assert report['readback']['pass'] is True, 'Blender GLB roundtrip has not passed'
    assert report['sourceUnchanged'] is True
    assert report['designInput']['sha256'] == sha(DESIGN.read_bytes()), 'Design mapping changed after export'
    for item in report['generatorInputs']:
        path = (ROOT/item['path']).resolve()
        assert path.is_relative_to(ROOT/'tools/desert-runtime'), 'Unexpected export generator path'
        assert sha(path.read_bytes()) == item['sha256'], 'Exporter changed after export: ' + item['path']


def import_export(source):
    source = source.resolve()
    assert not source.is_relative_to(DEST.resolve()), 'Keep the original export outside the managed destination'
    assert_destination_inventory(allow_legacy=True)
    scene = (source/'scene.glb').read_bytes()
    scene_hash = sha(scene)
    places = read(source/'places.json')
    report = read(source/'export-report.json')
    check_export_inputs(report)
    assert report['sourceBlendSha256'] == read(SETTINGS)['sourceBlendSha256'], 'Unexpected source Blend identity'
    assert report['statistics']['sha256'] == scene_hash and report['statistics']['bytes'] == len(scene), 'Export report belongs to another GLB'
    assert places['sourceBlendSha256'] == report['sourceBlendSha256'], 'Place metadata belongs to another source'
    packed, transport = compress_scene(scene)
    config = derive(places, read(SETTINGS), scene_hash, transport)
    # Only the former importer-owned raw output may be removed. Verify its old
    # manifest identity (or exact equality to this preserved export) first.
    legacy = DEST/'scene.glb'
    legacy_sha = None
    if legacy.exists():
        assert legacy.is_file() and not legacy.is_symlink(), 'Unexpected legacy scene path'
        legacy_bytes = legacy.read_bytes(); legacy_sha = sha(legacy_bytes)
        prior = read(DEST/'manifest.json') if (DEST/'manifest.json').exists() else {}
        prior_row = next((row for row in prior.get('files', []) if row.get('path') == 'scene.glb'), None)
        assert legacy_sha == scene_hash or (prior_row and prior_row['sha256'] == legacy_sha
               and prior_row['bytes'] == len(legacy_bytes)), 'Legacy raw scene is not a verified importer output'
        del legacy_bytes
    output = {SCENE_TRANSPORT_PATH: packed, 'places.json': encoded(places),
              'export-report.json': encoded(report), 'config.json': encoded(config),
              'source-object-map.json': encoded(read(source/'source-object-map.json'))}
    manifest = {'schema': 1, 'revision': config['revision'], 'scope': 'Local stage-select candidate; no runtime promotion or Host E2E proof',
                'generatorInputs': generator_inputs(), 'sourceBlendSha256': report['sourceBlendSha256'],
                'sourceArchive': read(SETTINGS)['sourceArchive'],
                'sceneTransport': transport, 'transportAudit': transport_audit(scene_hash),
                'audit': glb_audit(scene), 'files': [{'path': name, 'bytes': len(data), 'sha256': sha(data)} for name, data in output.items()]}
    output['manifest.json'] = encoded(manifest)
    assert set(output) == OUTPUT_NAMES
    assert all(len(data) <= GIT_BLOB_LIMIT for data in output.values()), 'A generated file exceeds the 100 MiB Git blob limit'
    DEST.mkdir(parents=True, exist_ok=True)
    for name, data in output.items():
        (DEST/name).write_bytes(data)
    decoded, _, stored = decode_stored_scene(manifest)
    assert decoded == scene and stored == transport, 'Stored transport failed exact GLB roundtrip'
    if legacy_sha is not None:
        assert legacy.resolve().parent == DEST.resolve() and sha(legacy.read_bytes()) == legacy_sha
        assert sha((source/'scene.glb').read_bytes()) == scene_hash, 'Original export changed before removing its derived copy'
        legacy.unlink()
    assert_destination_inventory()


def check():
    assert_destination_inventory()
    manifest = read(DEST/'manifest.json')
    check_export_inputs(read(DEST/'export-report.json'))
    assert manifest['generatorInputs'] == generator_inputs(), 'Generator/settings changed; regenerate'
    names = [entry['path'] for entry in manifest['files']]
    assert len(names) == len(set(names)) and set(names) == OUTPUT_NAMES-{'manifest.json'}, 'Manifest file inventory mismatch'
    assert all((DEST/name).stat().st_size <= GIT_BLOB_LIMIT for name in OUTPUT_NAMES), 'Generated Git blob limit exceeded'
    for entry in manifest['files']:
        data = (DEST/entry['path']).read_bytes()
        assert len(data) == entry['bytes'] and sha(data) == entry['sha256'], entry['path']
    scene, packed, transport = decode_stored_scene(manifest)
    regenerated, expected_transport = compress_scene(scene)
    assert packed == regenerated and transport == expected_transport, 'Gzip is not the deterministic producer output'
    config = derive(read(DEST/'places.json'), read(SETTINGS), sha(scene), transport)
    assert encoded(config) == (DEST/'config.json').read_bytes(), 'Config stale'
    assert glb_audit(scene) == manifest['audit']
    assert manifest['transportAudit'] == transport_audit(sha(scene)), 'Transport audit stale'
    print(json.dumps({'ok': True, **manifest['audit'], 'sceneTransport': transport,
                      'decodedSHA256': sha(scene), 'exactOutputInventory': sorted(OUTPUT_NAMES)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', nargs='?', type=Path, help='Directory containing the reviewed Blender export')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.source:
        import_export(args.source)
    if args.check:
        check()
    if not args.source and not args.check:
        parser.error('source or --check required')
