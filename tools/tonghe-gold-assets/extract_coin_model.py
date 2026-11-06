import bpy
import hashlib
import json
import sys
from pathlib import Path

from mathutils import Vector

out = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
out.parent.mkdir(parents=True, exist_ok=True)
tail=sys.argv[sys.argv.index('--')+1:]
logo_path=Path(tail[1]).resolve() if len(tail)>1 else out.parent/'original_node.svg'
if not logo_path.is_file():
    raise FileNotFoundError('Pass the original_node.svg path after the output JSON path')
scene = bpy.context.scene
scene.frame_set(1)
bpy.context.view_layer.update()
body = bpy.data.objects['R3_B_ContinuousCoinBlank']
cam = scene.camera
data = {
    'schema': 'tonghe-coin-projection/v1',
    'source_blend_sha256': hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
    'source_blend_name': Path(bpy.data.filepath).name,
    'blender_version': bpy.app.version_string,
    'parameters': json.loads(scene['params']),
    'original_mark_contract': {
        'svg_sha256': hashlib.sha256(logo_path.read_bytes()).hexdigest(),
        'path_bounds': [0,0,132.75,227.85],
        'bounds_basis': 'Original node filled-path extent; corresponds to measured model mark bounds',
    },
    'camera': {'type': cam.data.type, 'ortho_scale': cam.data.ortho_scale,
               'world_matrix': [list(r) for r in cam.matrix_world],
               'inverse_world_matrix': [list(r) for r in cam.matrix_world.inverted()]},
    'spin': {'axis': [0,0,1], 'center': [0,0,0], 'frames': 32, 'fps': 30},
    'body': {
        'name': body.name,
        'vertices': [list(body.matrix_world @ v.co) for v in body.data.vertices],
        'local_vertices': [list(v.co) for v in body.data.vertices],
        'faces': [{'vertices': list(p.vertices), 'material': p.material_index,
                   'normal': list(body.matrix_world.to_3x3() @ p.normal)} for p in body.data.polygons],
        'materials': [m.name for m in body.data.materials],
    },
    'marks': [],
    'animation_samples': [],
}
for name in ['Front_Logo_node', 'Back_Logo_node']:
    ob = bpy.data.objects[name]
    points = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    data['marks'].append({'name':name,'min_world':lo,'max_world':hi,
                          'world_matrix':[list(r) for r in ob.matrix_world]})
for frame in range(1,34):
    scene.frame_set(frame)
    data['animation_samples'].append({'frame':frame-1,'rotation_z':bpy.data.objects['CoinSpin_Z'].rotation_euler.z})
out.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
print(json.dumps({'vertices':len(data['body']['vertices']), 'faces':len(data['body']['faces']),
                  'camera':data['camera'], 'marks':data['marks']},ensure_ascii=False,indent=2))
