"""Materialize the adopted base-gate C asset from its handoff ZIP; no Blender needed."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'launcher/web/assets/stage-diorama/base-gate'
DATA = ROOT / 'launcher/web/modules/stage-select/stage-select-diorama-data.js'
PACKAGE_HASH = '70b96dded85d09a4b992fd2906c5f85e04a4395ec55386d657df9d8878cdb44c'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def generate(archive):
    if digest(archive.read_bytes()) != PACKAGE_HASH:
        raise ValueError('Unexpected handoff ZIP; explicitly review a new source before importing')
    prefix = 'stage-select-C-handoff-20260909/C方案工程/'
    with zipfile.ZipFile(archive) as archive_zip:
        read = lambda name: archive_zip.read(prefix + name)
        mapping = json.loads(read('visual-mapping.json'))
        study = json.loads(read('study.json'))
        camera = mapping['cameras']['hero']
        environment = next(p['presentation'] for p in study['profiles'] if p['id'] == 'print')
        slots = {s['labelAnchor']: s for s in mapping['slots']}
        sub = lambda a, b: [x-y for x, y in zip(a, b)]
        dot = lambda a, b: sum(x*y for x, y in zip(a, b))
        norm = lambda v: [x / math.sqrt(dot(v, v)) for x in v]
        cross = lambda a, b: [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
        backward = norm(sub(camera['gltfPosition'], camera['gltfTarget']))
        right = norm(cross([0, 1, 0], backward))
        up = cross(backward, right)
        pins = {}
        for node in mapping['nodes']:
            sid = node['stageButtonId']
            x, y, z = slots[node['labelAnchor']]['labelWorldBlender']
            delta = sub([x, z, -y], camera['gltfTarget'])
            px = 512 + dot(delta, right) * 1024 / camera['horizontalSpan']
            py = 288 - dot(delta, up) * 1024 / camera['horizontalSpan']
            index = int(sid.rsplit('_', 1)[1])
            # 固定主镜头的名称排布：密集地铁组交错，训练场名称向下。
            dx = 20 if index == 14 else 38 if index == 15 else 0
            dy = 44 if index in (0, 10, 11, 12, 14, 15) else -44
            pins[sid] = dict(x=round(px, 3), y=round(py, 3), labelX=dx, labelY=dy,
                             labelAnchor=node['labelAnchor'], focusAnchor=node['focusAnchor'],
                             building=node['glbNode'])
        config = dict(frameLabel=mapping['frameLabel'], camera=camera, environment=environment,
                      gridYawRadians=mapping['gridYawRadians'], pins=pins)
        outputs = {
            DEST / '.gitattributes': b'* -text\n',
            DATA.parent / '.gitattributes': b'stage-select-diorama-data.js text eol=lf\nstage-select-intel-data.js text eol=lf\n',
            DEST / 'city.glb': read('stage-select-v10.glb'),
            DATA: ('// 由 tools/import-stage-select-diorama.py 从采用包生成；只含视觉身份与坐标。\n'
                   'var StageSelectDioramaData = ' + json.dumps(config, ensure_ascii=False, indent=2) + ';\n').encode('utf-8'),
        }
        sources = {
            'three.core.js': 'build/three.core.js',
            'three.module.js': 'build/three.module.js',
            'GLTFLoader.js': 'examples/jsm/loaders/GLTFLoader.js',
            'BufferGeometryUtils.js': 'examples/jsm/utils/BufferGeometryUtils.js',
            'OrbitControls.js': 'examples/jsm/controls/OrbitControls.js',
            'LICENSE': 'LICENSE',
        }
        for name, source in sources.items():
            raw = read('review/vendor/three/' + source)
            if name in ('GLTFLoader.js', 'BufferGeometryUtils.js', 'OrbitControls.js'):
                raw = raw.decode().replace("from 'three'", "from './three.module.js'").replace(
                    "from '../utils/BufferGeometryUtils.js'", "from './BufferGeometryUtils.js'").encode()
            outputs[DEST / 'vendor' / name] = raw
        manifest = dict(schema=1, sourceZipSha256=PACKAGE_HASH, threeRevision='180',
                        transforms='Only loader relative import paths and fixed camera projection; GLB unchanged.',
                        files=[dict(path=p.relative_to(ROOT).as_posix(), bytes=len(b), sha256=digest(b))
                               for p, b in outputs.items()])
        outputs[DEST / 'manifest.json'] = (json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode()
        return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', nargs='?', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((DEST / 'manifest.json').read_text(encoding='utf-8'))
        total = 0
        for row in manifest['files']:
            data = (ROOT / row['path']).read_bytes()
            assert len(data) == row['bytes'] and digest(data) == row['sha256'], row['path']
            total += len(data)
        assert total < 12_000_000, 'Single-scene runtime asset budget exceeded'
        print(json.dumps(dict(ok=True, files=len(manifest['files']), bytes=total)))
        return
    if not args.archive:
        parser.error('archive is required unless --check is used')
    outputs = generate(args.archive)
    for path, data in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(json.dumps(dict(ok=True, files=len(outputs), bytes=sum(map(len, outputs.values())))))


if __name__ == '__main__':
    main()
