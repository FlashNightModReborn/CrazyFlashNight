"""Read-only source inspection; emits JSON into the runtime-candidate workspace."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import sys
import time

import bpy
from mathutils import Vector


def render_collections(layer, blocked=False):
    blocked = blocked or layer.exclude or layer.collection.hide_render
    found = set() if blocked else {layer.collection.as_pointer()}
    for child in layer.children:
        found.update(render_collections(child, blocked))
    return found


def owner(obj):
    if obj.name.startswith('WASTE_R24_'):
        return 'waste'
    if obj.name.startswith('FALLEN_R24_'):
        return 'fallen'
    while obj:
        if obj.name == 'REGISTRATION_R9_BASE':
            return 'base'
        if obj.get('placeId'):
            return str(obj['placeId'])
        if obj.name.startswith('PLACE_'):
            return obj.name[6:]
        obj = obj.parent
    return 'environment'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    started = time.perf_counter()
    scene = bpy.context.scene
    allowed = render_collections(bpy.context.view_layer.layer_collection)
    visible = [obj for obj in scene.objects if obj.type == 'MESH' and not obj.hide_render
               and any(col.as_pointer() in allowed for col in obj.users_collection)]
    materials = collections.Counter()
    attributes = collections.Counter()
    groups = collections.defaultdict(list)
    for obj in visible:
        groups[owner(obj)].append(obj)
        for material in obj.data.materials:
            if material:
                materials[material.name] += 1
        for attribute in obj.data.color_attributes:
            attributes[f'{attribute.name}|{attribute.domain}|{attribute.data_type}'] += 1
    records = []
    for name, count in materials.most_common():
        material = bpy.data.materials[name]
        nodes = []
        if material.use_nodes:
            for node in material.node_tree.nodes:
                record = {'type': node.bl_idname, 'name': node.name}
                if node.type == 'TEX_IMAGE':
                    record.update(image=node.image.name if node.image else None,
                                  size=list(node.image.size) if node.image else None)
                if node.type in ['VERTEX_COLOR', 'ATTRIBUTE']:
                    record.update(attribute=getattr(node, 'layer_name', getattr(node, 'attribute_name', None)))
                if node.type == 'BSDF_PRINCIPLED':
                    record['inputs'] = {key: {'linked': node.inputs[key].is_linked,
                                             'value': list(node.inputs[key].default_value) if hasattr(node.inputs[key].default_value, '__len__') else node.inputs[key].default_value}
                                        for key in ['Base Color', 'Metallic', 'Roughness', 'Alpha', 'Emission Color', 'Emission Strength'] if key in node.inputs}
                nodes.append(record)
        records.append({'name': name, 'objects': count, 'diffuse': list(material.diffuse_color),
                        'nodes': nodes, 'links': [(link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name)
                                                 for link in material.node_tree.links] if material.use_nodes else []})
    group_info = {}
    for name, objects in groups.items():
        coords = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
        group_info[name] = {'objects': len(objects), 'bounds': [[min(p[i] for p in coords) for i in range(3)], [max(p[i] for p in coords) for i in range(3)]],
                            'sampleNames': [obj.name for obj in objects[:15]],
                            'belowGroundObjects': sum(max((obj.matrix_world @ Vector(c))[2] for c in obj.bound_box) < 0 for obj in objects)}
    graph = bpy.context.evaluated_depsgraph_get()
    instance_count = 0
    instance_samples = []
    for instance in graph.object_instances:
        if not instance.is_instance:
            continue
        instance_count += 1
        if len(instance_samples) < 12:
            instance_samples.append({'name': instance.object.name, 'show_self': getattr(instance, 'show_self', None),
                                     'parent': instance.parent.name if instance.parent else None,
                                     'objectHidden': instance.object.original.hide_render,
                                     'parentHidden': instance.parent.original.hide_render if instance.parent else None,
                                     'owner': owner(instance.parent.original) if instance.parent else owner(instance.object.original),
                                     'collections': [col.name for col in instance.object.original.users_collection]})
    anchors = [{'name': obj.name, 'placeId': obj.get('placeId'), 'world': list(obj.matrix_world.translation),
                'type': obj.type} for obj in scene.objects if obj.name.startswith('PLACE_') or obj.get('placeId')]
    road_objects = [{'name': obj.name, 'owner': owner(obj), 'bounds': [list(obj.matrix_world @ Vector(c)) for c in obj.bound_box]}
                    for obj in visible if any(key in obj.name for key in ['REGIONAL_ROADS', 'DERIVED_APPROACH', 'R28_', 'TERMINAL', 'ROUTE'])]
    output = {'source': bpy.data.filepath, 'sourceSHA256': hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
              'directVisibleObjects': len(visible), 'evaluatedInstances': instance_count, 'instanceSamples': instance_samples,
              'colorAttributes': dict(attributes), 'materials': records, 'groups': group_info, 'anchors': anchors,
              'roadsAndTerrain': road_objects, 'sceneCamera': {'name': scene.camera.name, 'matrix_world': [list(row) for row in scene.camera.matrix_world],
                                                             'ortho_scale': scene.camera.data.ortho_scale, 'type': scene.camera.data.type} if scene.camera else None,
              'seconds': time.perf_counter() - started}
    path = Path(args.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('DESERT_INSPECTION_DONE', json.dumps({'path': str(path), 'direct': len(visible), 'instances': instance_count,
                                             'materials': len(materials), 'seconds': output['seconds']}), flush=True)


if __name__ == '__main__':
    main()
