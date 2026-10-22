"""Bind display-only door sequences to original placements and generator locations."""
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SCRIPTS = ROOT / 'tmp/cf6-soldier-20261016/knife-audit/deobfuscated-export/scripts'
# generator depth is read from the actual original display list; target door is
# independently checked against that instance's decoded load action.
BINDINGS = {'A03': [('wood1714', 21, 182), ('exit1720', 28, None)],
            'A04': [('wood1714', 21, 251), ('wood1714', 89, 255)],
            'A05': [('grand1750', 88, None)]}


def build():
    native_path = HERE / 'generated/door-runtime-index.json'
    native = {row['id']: row for row in json.loads(native_path.read_text(encoding='utf-8'))['sets']}
    result = {'schema': 'cf6-map-mechanism-overrides.v1', 'coordinateSpace': 'native world; convert exactly once',
              'sourceManifest': native_path.relative_to(ROOT).as_posix(),
              'sourceManifestSha256': hashlib.sha256(native_path.read_bytes()).hexdigest(), 'maps': {}}
    for map_id, bindings in BINDINGS.items():
        geometry_path = HERE / 'generated' / (map_id + '-original-geometry.json')
        geometry = json.loads(geometry_path.read_text(encoding='utf-8'))['geometry']
        display = {row['depth']: row for row in geometry['display']}
        rows = []
        for name, depth, generator_depth in bindings:
            source = native[name]
            place = display[depth]
            assert place['matrix'][:4] == [1, 0, 0, 1], 'non-translation door needs an explicit transform'
            box = source['viewBox']
            row = {'id': name + '-' + str(depth), 'role': 'door-spawn-sequence' if generator_depth else 'door-exit-sequence',
                   'url': source['swf'], 'xfl': source['xfl'], 'frames': source['frames'],
                   'x': place['matrix'][4] + box[0], 'y': place['matrix'][5] + box[1],
                   'width': box[2], 'height': box[3], 'depth': depth,
                   'basis': {'geometry': geometry_path.relative_to(ROOT).as_posix(),
                             'geometrySha256': hashlib.sha256(geometry_path.read_bytes()).hexdigest(),
                             'originalDepth': depth, 'originalSprite': place['id'], 'viewBox': box,
                             'scope': 'isolated display only; no original actor, spawn, transition or save actions'}}
            if generator_depth:
                generator = display[generator_depth]
                load_path = SCRIPTS / ('DefineSprite_' + str(geometry['worldSprite'])) / 'frame_1' / ('PlaceObject2_1434_' + str(generator_depth)) / 'CLIPACTIONRECORD onClipEvent(load).as'
                assert '目标门 = "' + place['name'] + '"' in load_path.read_text(encoding='utf-8-sig')
                row.update(spawnX=generator['matrix'][4], spawnY=generator['matrix'][5], spawnRadius=100)
                row['basis'].update(generatorDepth=generator_depth, targetDoor=place['name'],
                                    generatorLoad=load_path.relative_to(ROOT).as_posix(),
                                    generatorLoadSha256=hashlib.sha256(load_path.read_bytes()).hexdigest(),
                                    radiusPolicy='prototype association radius 100px; nearest actual enemy event, no enemy creation')
            rows.append(row)
        result['maps'][map_id] = {'layers': rows, 'kind': 'door' if any(r['role']=='door-exit-sequence' for r in rows) else 'exit'}
    return result


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    path=HERE/'generated/door-mechanism-overrides.json'
    content=(json.dumps(build(),ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check: assert path.read_bytes()==content, 'stale door mechanism config'
    else: path.write_bytes(content)
    print('checked door placements and original generator-to-door bindings; actual playback remains required')
