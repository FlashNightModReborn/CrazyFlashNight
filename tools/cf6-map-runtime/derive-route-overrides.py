"""Adapt all original map geometry without mutating archived art/source metadata."""
from pathlib import Path
import argparse
import json
import hashlib
import geometry

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
ROUTE=[f'A{i:02}' for i in range(1,23) if i not in (7,21)]


def build():
    result={'schema':'cf6-map-runtime-overrides.v1','maps':{}}
    for key in ROUTE:
        source=HERE/'generated'/(key+'-original-geometry.json')
        evidence=json.loads(source.read_text(encoding='utf-8'));raw=evidence['geometry']
        paths,approximations=geometry.collision_paths(evidence)
        blocked=geometry.filled_trapezoids(paths,raw['walkBounds'])
        spawn_source=raw['spawn'];arrival_proof=None
        arrival=next((item for item in raw['display'] if item.get('id')==1729),None)
        if arrival is not None:
            script=ROOT/'tmp/cf6-soldier-20261016/knife-audit/deobfuscated-export/scripts/DefineSprite_1729/frame_1/DoAction.as'
            text=script.read_text(encoding='utf-8-sig')
            assert '_root.gameworld.man1._x = this._x;' in text and '_root.gameworld.man1._y = this._y;' in text
            spawn_source=arrival['matrix'][4:]
            arrival_proof={'sprite':1729,'worldPlacement':spawn_source,
                'script':script.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(script.read_bytes()).hexdigest(),
                'meaning':'explicit original arrival script assigns hero to this direct-world instance position'}
        spawn,changed=geometry.safe_spawn(spawn_source,raw['walkBounds'],paths)
        exit_spec=geometry.manual_exit(raw['walkBounds'],paths)
        result['maps'][key]={'worldScale':1,'walkBounds':raw['walkBounds'],'spawn':spawn,
            'exit':exit_spec,'collisions':blocked,
            'leftSpawnLine':geometry.spawn_line(raw['walkBounds'],paths,'left'),
            'rightSpawnLine':geometry.spawn_line(raw['walkBounds'],paths,'right'),
            'geometryStatus':'originalStaticFillWithPrototypeDerivedEntryExit',
            'geometryBasis':{'originalSwfSha256':evidence['originalSwfSha256'],
                'evidence':'tools/cf6-map-runtime/generated/'+source.name,
                'walkBounds':'decoded original root world load',
                'originalAuthoredSpawn':raw['spawn'],'spawnAdjusted':changed,
                'explicitOriginalArrival':arrival_proof,
                'spawnAdjustment':'nearest 10px grid position with 20px X edge margin when authored point is outside walkable region' if changed else None,
                'collision':'original named 地图 shape fill transformed to world; even-odd contour holes decomposed into nonoverlapping convex trapezoids',
                'approximations':approximations,
                'exit':'prototypeDerived CF7 manual exit in a free rightmost reachable corridor; not original automatic transition or visible door',
                'spawnLines':'prototypeDerived generic left/right WaveSpawner safe intervals; original named spawn instances retain content-line authority',
                'scale':'1; original and CF7 body size comparable; camera/character-scale consumer validation pending'}}
    result['maps']['A01']['layerSourceKinds']={'background':'background'}
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    target=HERE/'route-geometry-overrides.json'
    data=build();content=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode()
    if args.check:assert target.read_bytes()==content,'stale route geometry overrides'
    else:target.write_bytes(content)
    print(json.dumps({key:{'polygons':len(row['collisions']),'spawnAdjusted':row['geometryBasis']['spawnAdjusted'],
        'approximations':row['geometryBasis']['approximations'],'exit':row['exit']['rect']} for key,row in data['maps'].items()},ensure_ascii=False))
