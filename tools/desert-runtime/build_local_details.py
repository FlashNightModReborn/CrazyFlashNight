"""Build a new editable six-place detail candidate from the preserved base Blend.

Run with Blender --disable-autoexec. The base is never overwritten. The new Blend
is a full editable snapshot; the JSON report pins the original and all recipes.
"""
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
from civil_details import apply_civil_details
from military_details import apply_military_details
from ambush_details import apply_ambush_details

BASE_SHA = 'a6242048e490c11d5e5c81edd6800fb6f231e2d71967c976d5f83016103da524'
PLACES = {'refugees', 'depot', 'fort', 'frontbase', 'ambush', 'diplomacy'}
RECIPE_NAMES = ['build_local_details.py', 'civil_details.py', 'military_details.py', 'ambush_details.py']


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf8')


def matrix(obj):
    return [float(v) for row in obj.matrix_world for v in row]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--audit', required=True, type=Path)
    parser.add_argument('--design', default=str(ROOT/'docs/design-data/desert-spatial-draft.json'), type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    source = Path(bpy.data.filepath).resolve()
    if digest(source) != BASE_SHA:
        raise RuntimeError('Expected the preserved, independently restored base Blend')
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    model_dir = output/'model'; model_dir.mkdir(exist_ok=True)
    model = model_dir/'desert-six-place-detail-v1.blend'
    if model.exists():
        raise RuntimeError('Refusing to overwrite an existing editable candidate')
    recipes = [{'path': 'tools/desert-runtime/'+name, 'sha256': digest(HERE/name)} for name in RECIPE_NAMES]
    design = json.loads(args.design.read_text('utf-8-sig'))
    audit = json.loads(args.audit.read_text('utf8'))
    if audit['sourceSHA256'] != BASE_SHA:
        raise RuntimeError('Source audit belongs to another Blend')
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    originals = {o.name: {'matrix': matrix(o), 'hidden': o.hide_render} for o in scene.objects}
    anchors = {o.name: matrix(o) for o in scene.objects if o.name.startswith('PLACE_')}
    context = {'layout_data': design, 'source_sha256': BASE_SHA, 'audit': audit}
    reports = {'civil': apply_civil_details(scene, context),
               'military': apply_military_details(scene, context),
               'ambush': apply_ambush_details(scene, context)}
    bpy.context.view_layer.update()
    assert all(scene.objects.get(name) is not None for name in originals), 'Original object deleted'
    assert all(matrix(scene.objects[name]) == row['matrix'] for name, row in originals.items()), 'Original transform changed'
    assert all(matrix(scene.objects[name]) == value for name, value in anchors.items()), 'Geographic anchor changed'
    changed_visibility = [name for name, row in originals.items() if scene.objects[name].hide_render != row['hidden']]
    added = [o for o in scene.objects if o.name not in originals]
    by_place = {place: [] for place in sorted(PLACES)}
    for obj in added:
        place = obj.get('placeId')
        if place not in PLACES:
            raise RuntimeError('Unowned new detail object: ' + obj.name)
        by_place[place].append(obj.name)
    if any(not rows for rows in by_place.values()):
        raise RuntimeError('A requested place received no new detail')
    scene['localDetailVersion'] = 'six-place-detail-v1'
    scene['localDetailBaseSHA256'] = BASE_SHA
    scene['localDetailScope'] = 'Source-informed presentation reconstruction; original objects and geographic anchors preserved'
    # This new file contains the full scene and packed images; save-copy leaves the base untouched.
    bpy.ops.wm.save_as_mainfile(filepath=str(model), copy=True, check_existing=False)
    assert digest(source) == BASE_SHA, 'Original Blend changed'
    for row in recipes:
        assert digest(ROOT/row['path']) == row['sha256'], 'A recipe changed while building'
    report = {'schema': 1, 'createdUtc': datetime.now(timezone.utc).isoformat(),
              'version': 'six-place-detail-v1', 'baseSourceBlendSha256': BASE_SHA,
              'sourceBlend': str(model), 'sourceBlendSha256': digest(model), 'bytes': model.stat().st_size,
              'generatorInputs': recipes, 'designInput': {'path': str(args.design), 'sha256': digest(args.design)},
              'auditInput': {'path': str(args.audit), 'sha256': digest(args.audit)},
              'originalTransformsAndAnchorsUnchanged': True, 'originalSourceUnchanged': True,
              'originalObjectsDeleted': 0, 'changedOriginalVisibility': changed_visibility,
              'addedObjectsByPlace': by_place, 'details': reports,
              'limits': ['The compact 3D layouts are presentation reconstructions, not surveyed geography.',
                         'Source features were checked against current complete backgrounds; game logic and IDs are unchanged.',
                         'New model still requires exported Web-view inspection; saving a Blend is not visual acceptance.']}
    write_json(output/'detail-build-report.json', report)
    print(json.dumps({'sourceBlend': str(model), 'sha256': report['sourceBlendSha256'],
                      'added': {k: len(v) for k, v in by_place.items()}, 'hiddenOriginals': len(changed_visibility)}), flush=True)


if __name__ == '__main__':
    main()
