"""CF6 map-size adaptation. This does not change the camera or actor scale."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
POLICY = HERE / 'viewport-policy.json'
LAYOUT = HERE / 'generated/original-camera-layout.json'
REFERENCES = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6地图/原作参考/source-manifest.json'
ROUTE = ['TUTORIAL'] + [f'A{i:02}' for i in range(1, 23) if i not in (7, 21)]
ORIGINAL = 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def geometry_path(map_id):
    return ROOT / ('tools/cf6-tutorial/original-tutorial-geometry.json' if map_id == 'TUTORIAL'
                   else f'tools/cf6-map-runtime/generated/{map_id}-original-geometry.json')


def camera_reference(source):
    """Keep historical geometry provenance; resolve the exact byte-preserved input."""
    manifest = read(REFERENCES)
    rows = manifest.get('files', [])
    if manifest.get('schema') != 'cf6-original-reference-map.v1' or not isinstance(rows, list):
        raise ValueError('invalid original reference mapping')
    matches = [row for row in rows if row.get('originalPath') == source['decodedLoad'].replace('\\', '/')]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous original camera mapping: ' + source['map'])
    row = matches[0]
    path = ROOT / row['path']
    if (row.get('kind') != 'cameraOnLoad' or row.get('mapId') != source['map']
            or path.parent.resolve() != REFERENCES.parent.resolve() or path.is_symlink()
            or row.get('sha256') != source['decodedLoadSha256'] or digest(path) != row['sha256']
            or path.stat().st_size != row.get('bytes')):
        raise ValueError('original camera reference identity changed: ' + source['map'])
    return path


def derive():
    rows = []
    for map_id in ROUTE:
        path = geometry_path(map_id)
        source = read(path)
        load = camera_reference(source)
        if source['originalSwfSha256'] != ORIGINAL or digest(load) != source['decodedLoadSha256']:
            raise ValueError('original camera source identity changed: ' + map_id)
        text = load.read_text(encoding='utf-8-sig')
        fields = {}
        for field in ('背景长', '背景高', '舞台长', '舞台高'):
            matches = re.findall(r'(?m)^\s*' + field + r'\s*=\s*([0-9.]+)\s*;', text)
            if len(matches) != 1:
                raise ValueError('ambiguous camera field: ' + map_id + '/' + field)
            fields[field] = float(matches[0])
        if [fields['舞台长'], fields['舞台高']] != [600, 350]:
            raise ValueError('unreviewed original viewport: ' + map_id)
        rows.append({'id': map_id, 'canvas': [fields['背景长'], fields['背景高']],
                     'sourceViewport': [600, 350],
                     'geometryPath': path.relative_to(ROOT).as_posix(), 'geometrySha256': digest(path),
                     'decodedLoad': load.relative_to(ROOT).as_posix(), 'decodedLoadSha256': digest(load)})
    return {'schema': 'cf6-original-camera-layout.v1', 'originalSwfSha256': ORIGINAL, 'maps': rows}


def load():
    policy, layout = read(POLICY), read(LAYOUT)
    if (policy['schema'] != 'cf6-viewport-policy.v1' or policy['cameraBaseScale'] != 1
            or policy['actorScale'] != 1 or policy['worldOrigin'] != [0, 0]
            or policy['sourceViewport'] != [600, 350]
            or layout['schema'] != 'cf6-original-camera-layout.v1'
            or layout['originalSwfSha256'] != ORIGINAL
            or [r['id'] for r in layout['maps']] != ROUTE):
        raise ValueError('unreviewed CF6 viewport policy')
    target = policy['targetViewport']
    if len(target) != 2 or any(type(v) not in (int, float) or not 1 <= v <= 2048 for v in target):
        raise ValueError('invalid target viewport')
    scale = max(target[0] / 600, target[1] / 350)
    if not 1 <= scale <= 3:
        raise ValueError('map asset scale outside reviewed range')
    for row in layout['maps']:
        if digest(ROOT / row['geometryPath']) != row['geometrySha256']:
            raise ValueError('camera geometry source changed: ' + row['id'])
        if digest(ROOT / row['decodedLoad']) != row['decodedLoadSha256']:
            raise ValueError('original camera script changed: ' + row['id'])
        if len(row['canvas']) != 2 or any(type(v) not in (int, float) or not 1 <= v <= 4000 for v in row['canvas']):
            raise ValueError('invalid original camera canvas')
    return scale, {r['id']: r for r in layout['maps']}, target


def point_fields(value, origin, scale, pairs=None):
    pairs = pairs or (('x', 'Xmin', 'Xmax', 'x0', 'x1'), ('y', 'Ymin', 'Ymax', 'y0', 'y1'))
    for axis, keys in enumerate(pairs):
        for key in keys:
            if key in value:
                number = value[key]
                if type(number) not in (int, float) or not math.isfinite(number):
                    raise ValueError('invalid coordinate: ' + key)
                value[key] = round((number + origin[axis]) * scale, 4)


def adapt(chapter, environment_bytes, native_maps):
    """Consume the unscaled normalized assembly exactly once, before economy placement."""
    scale, originals, target = load()
    environment = ET.fromstring(environment_bytes)
    envs = {n.findtext('BackgroundURL'): n for n in environment}
    audit = []
    for node in chapter['maps']:
        map_id = node['id']
        if 'presentation' in node:
            raise ValueError('CF6 viewport transform applied twice')
        native = native_maps.get(map_id)
        if native is not None and native['worldScale'] != 1:
            raise ValueError('native map must retain original asset scale')
        origin = native['nativeBounds'][:2] if native is not None else [0, 0]
        stage = node['stage']
        point_fields(stage['BasicInformation'], origin, scale, (('PlayerX',), ('PlayerY',)))
        for outer, inner in (('Instances', 'Instance'), ('Pickups', 'Pickup'), ('SpawnPoint', 'Point')):
            for placement in stage.get(outer, {}).get(inner, []):
                point_fields(placement, origin, scale)
        for wave in stage['Wave']['SubWave']:
            for enemy in wave['EnemyGroup']['Enemy']:
                point_fields(enemy, origin, scale)
        for group in node.get('bossEncounter', {}).get('groups', []):
            for enemy in group['enemies']:
                point_fields(enemy, origin, scale)
        mechanism = node['mechanism']
        mechanism['assetScale'] = scale
        canvas = list(originals[map_id]['canvas'])
        basis = 'original explicit camera canvas, capped at available native bottom/right artwork'
        for layer in mechanism.get('layers', []):
            if layer['role'] in ('screen-fixed', 'city-parallax', 'transformation'):
                raise ValueError('root-stage layers must be merged after world-size adaptation')
            if layer['role'] == 'elevator-scroll':
                clip = layer['clip']
                if [round(layer['x'] + origin[0] + clip[0], 4),
                        round(layer['y'] + origin[1] + clip[1], 4)] != [0, 0] or clip[2:] != [600, 350]:
                    raise ValueError('unreviewed elevator viewport')
                canvas = clip[2:]
                basis = 'existing elevator window mask at original world [0,0,600,350]; not generic 800x800 metadata'
            point_fields(layer, origin, scale, (('x', 'spawnX'), ('y', 'spawnY')))
            for field in ('width', 'height', 'loopHeight', 'spawnRadius'):
                if field in layer:
                    layer[field] = round(layer[field] * scale, 4)
            if 'clip' in layer:
                layer['clip'] = [round(v * scale, 4) for v in layer['clip']]
        if native is not None and map_id not in ('A10', 'A13'):
            canvas = [min(canvas[i], native['nativeBounds'][i] + native['nativeBounds'][i + 2]) for i in (0, 1)]
        if any(canvas[i] * scale + 0.001 < target[i] for i in (0, 1)):
            raise ValueError('map camera canvas cannot cover default viewport: ' + map_id)
        node['presentation'] = {'scale': scale, 'backgroundX': round(origin[0] * scale, 4),
                                'backgroundY': round(origin[1] * scale, 4)}
        node['sourceCoordinateSpace'] = 'native-original world origin; uniformly map-scaled once, actors and camera remain 1'
        node['geometryBasis'] = {'nativeNormalizedInput': node.get('geometryBasis'),
                                 'presentation': {'restoredOriginalOrigin': [0, 0], 'mapScale': scale,
                                                  'cameraCanvas': canvas, 'basis': basis}}
        env = envs[Path(node['background']).name]
        for axis, fields in enumerate((('Xmin', 'Xmax'), ('Ymin', 'Ymax'))):
            for field in fields:
                item = env.find(field)
                item.text = str(round((float(item.text) + origin[axis]) * scale, 4))
        for tag in ('Door', 'LeftSpawnLine', 'RightSpawnLine'):
            for group in env.findall(tag):
                for axis, keys in enumerate((('x0', 'x1'), ('y0', 'y1'))):
                    for key in keys:
                        item = group.find(key)
                        if item is not None:
                            item.text = str(round((float(item.text) + origin[axis]) * scale, 4))
        for item in env.findall('Collision/Point'):
            p = [float(v) for v in item.text.split(',')]
            item.text = ','.join(str(round((p[i] + origin[i]) * scale, 4)) for i in (0, 1))
        for i, field in enumerate(('Width', 'Height')):
            env.find(field).text = str(round(canvas[i] * scale, 4))
        audit.append({'id': map_id, 'nativeOrigin': origin, 'originalCanvas': originals[map_id]['canvas'],
                      'cameraCanvas': canvas, 'mapScale': scale, 'basis': basis})
    return ET.tostring(environment, encoding='utf-8', xml_declaration=True), audit


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = (json.dumps(derive(), ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if args.check:
        if not LAYOUT.is_file() or LAYOUT.read_bytes() != expected:
            raise SystemExit('stale original camera layout')
    else:
        LAYOUT.parent.mkdir(exist_ok=True)
        LAYOUT.write_bytes(expected)
    print('CF6 original camera layout: 21 maps verified')
