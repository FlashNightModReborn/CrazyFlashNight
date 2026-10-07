"""Create a fresh editable three-place, eleven-submap display candidate."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import bpy
from depot_multistage import apply_depot_multistage
from military_multistage import apply_military_multistage

SOURCE_SHA = '15e2253ba1636b680e58f90062f5c8fb4a1469fe9d3580a0c93520a874c6ecf4'
COUNTS = {'depot': 3, 'fort': 4, 'frontbase': 4}
RECIPES = ['build_multistage.py', 'depot_multistage.py', 'military_multistage.py', 'road_repairs.py']


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def matrix(obj):
    return [float(value) for row in obj.matrix_world for value in row]


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--plan', type=Path, default=ROOT/'docs/design-data/desert-multistage-expansion.json')
    parser.add_argument('--layout', type=Path, default=ROOT/'docs/design-data/desert-spatial-draft.json')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    source = Path(bpy.data.filepath).resolve()
    if digest(source) != SOURCE_SHA:
        raise RuntimeError('Expected the verified six-place detail source')
    output = args.out.resolve(); (output/'model').mkdir(parents=True, exist_ok=True)
    target = output/'model/desert-three-multistage-v1.blend'
    if target.exists(): raise RuntimeError('Refusing to overwrite an earlier editable candidate')
    inputs = [{'path': str(HERE/name), 'sha256': digest(HERE/name)} for name in RECIPES]
    inputs += [{'path': str(p.resolve()), 'sha256': digest(p)} for p in [args.plan, args.layout]]
    scene = bpy.context.scene; bpy.context.view_layer.update()
    original = {o.name: {'matrix': matrix(o), 'hidden': o.hide_render} for o in scene.objects}
    anchors = {o.name: matrix(o) for o in scene.objects if o.name.startswith('PLACE_')}
    context = {'source_sha256': SOURCE_SHA, 'layout_data': json.loads(args.layout.read_text('utf-8-sig')),
               'multistage_data': json.loads(args.plan.read_text('utf-8-sig'))}
    print('MULTISTAGE_BUILD_BEGIN', flush=True)
    depot = apply_depot_multistage(scene, context)
    print('MULTISTAGE_DEPOT_COMPLETE', len(depot['newObjects']), flush=True)
    military = apply_military_multistage(scene, context)
    print('MULTISTAGE_MILITARY_COMPLETE', military['addedObjects'], flush=True)
    bpy.context.view_layer.update()
    assert all(scene.objects.get(name) for name in original), 'Original object deleted'
    assert all(matrix(scene.objects[name]) == row['matrix'] for name, row in original.items()), 'Original transform changed'
    assert all(matrix(scene.objects[name]) == value for name, value in anchors.items()), 'Anchor changed'
    changed_visibility = [name for name, row in original.items() if scene.objects[name].hide_render != row['hidden']]
    assert not changed_visibility, 'This expansion must preserve the previous visible scene'
    areas = depot['subareas'] + military['subareas']
    for place, count in COUNTS.items():
        rows = [a for a in areas if a['placeId'] == place]
        assert sorted(a['subStageIndex'] for a in rows) == list(range(count)), 'Missing submap observation area'
        for area in rows:
            assert area.get('objects'), 'Observation area has no actual objects'
            assert all(scene.objects[name].get('submapIndex') == area['subStageIndex'] for name in area['objects']), 'Submap tag mismatch'
    scene['localMultistageAreas'] = json.dumps(areas, ensure_ascii=False)
    scene['localMultistageVersion'] = 'three-place-eleven-submap-v1'
    scene['localMultistageSourceSHA256'] = SOURCE_SHA
    scene['localMultistageScope'] = 'Reconstructed display districts following existing 3/4/4 submap order; no new game entries'
    for row in inputs: assert digest(row['path']) == row['sha256'], 'Input changed during construction'
    bpy.ops.wm.save_as_mainfile(filepath=str(target), copy=True, check_existing=False)
    assert digest(source) == SOURCE_SHA
    added = [o.name for o in scene.objects if o.name not in original]
    report = {'schema': 1, 'createdUtc': datetime.now(timezone.utc).isoformat(),
              'sourceBlend': str(target), 'sourceBlendSha256': digest(target), 'bytes': target.stat().st_size,
              'baseEditableSource': str(source), 'baseEditableSourceSha256': SOURCE_SHA,
              'generatorInputs': inputs, 'subareas': areas, 'addedObjects': added,
              'originalTransformsAndAnchorsUnchanged': True, 'originalVisibilityUnchanged': True,
              'originalSourceUnchanged': True, 'details': {'depot': depot, 'military': military},
              'limits': ['District orientation, functional names, connecting ground and display sizes are reconstruction proposals.',
                         'The original eleven submaps and three game entry IDs remain authoritative.',
                         'A saved native model does not prove final Web visual or real Host/game acceptance.']}
    write_json(output/'multistage-build-report.json', report)
    print(json.dumps({'file':str(target),'sha256':report['sourceBlendSha256'],'bytes':report['bytes'],
                      'newObjects':len(added),'subareas':len(areas)}), flush=True)


if __name__ == '__main__':
    main()
