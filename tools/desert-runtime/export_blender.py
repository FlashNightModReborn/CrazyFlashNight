"""Export the frozen R24/R25-B/R28 display source without saving/modifying it.

Run with the repository's already available portable Blender, --disable-autoexec.
Material/instance evaluation uses Blender; compact material batches are written as
standard GLB and then read back with Blender's built-in glTF importer.
"""
import argparse
import collections
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
import numpy as np
from mathutils import Vector
from glb_writer import GLBWriter
from material_eval import MaterialPlan
from forest_lod import crown_lod

EXPECTED_SOURCE = 'a6242048e490c11d5e5c81edd6800fb6f231e2d71967c976d5f83016103da524'
FORMAL = ['refugees', 'depot', 'ruins', 'base', 'fort', 'frontbase', 'secret', 'ambush', 'diplomacy']
SCALE = 0.001
SUN = np.asarray([-0.48, -0.67, 0.57], dtype=np.float32)
SUN /= np.linalg.norm(SUN)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    temporary = Path(path).with_suffix('.partial.json')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


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
    if obj.name.startswith('R25_FOREST_TREE_'):
        return 'forest'
    while obj:
        if obj.name == 'REGISTRATION_R9_BASE':
            return 'base'
        if obj.get('placeId') and obj.get('placeId') != '__landmarks__':
            return str(obj['placeId'])
        if obj.name.startswith('PLACE_'):
            return obj.name[6:]
        obj = obj.parent
    return 'environment'


def to_gltf(values):
    array = np.asarray(values, dtype=np.float32)
    result = array[..., [0, 2, 1]].copy() * SCALE
    result[..., 2] *= -1
    return result


def expand_bounds(target, key, position):
    if not len(position):
        return
    lo, hi = position.min(axis=0), position.max(axis=0)
    if key not in target:
        target[key] = [lo.copy(), hi.copy()]
    else:
        target[key][0] = np.minimum(target[key][0], lo)
        target[key][1] = np.maximum(target[key][1], hi)


def clip_above_zero(position, color, uv):
    """Exact triangle-plane clipping for the commune's first-screen surface shell."""
    triangles = position.reshape(-1, 3, 3)
    above = triangles[:, :, 2] >= 0
    keep = above.all(axis=1)
    mixed = above.any(axis=1) & ~keep
    output_p = [triangles[keep].reshape(-1, 3)]
    output_c = [color.reshape(-1, 3, 4)[keep].reshape(-1, 4)]
    output_u = [uv.reshape(-1, 3, 2)[keep].reshape(-1, 2)] if uv is not None else None
    for index in np.flatnonzero(mixed):
        items = [(triangles[index, i], color[index * 3 + i], uv[index * 3 + i] if uv is not None else None) for i in range(3)]
        clipped = []
        for i, current in enumerate(items):
            previous = items[i - 1]
            current_in, previous_in = current[0][2] >= 0, previous[0][2] >= 0
            if current_in != previous_in:
                t = -previous[0][2] / (current[0][2] - previous[0][2])
                clipped.append(tuple(a + (b - a) * t if a is not None else None for a, b in zip(previous, current)))
            if current_in:
                clipped.append(current)
        for i in range(1, len(clipped) - 1):
            tri = [clipped[0], clipped[i], clipped[i + 1]]
            output_p.append(np.asarray([item[0] for item in tri]))
            output_c.append(np.asarray([item[1] for item in tri]))
            if output_u is not None:
                output_u.append(np.asarray([item[2] for item in tri]))
    return np.concatenate(output_p), np.concatenate(output_c), np.concatenate(output_u) if output_u is not None else None, int((~above.any(axis=1)).sum()), int(mixed.sum())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True)
    parser.add_argument('--design', required=True)
    parser.add_argument('--skip-roundtrip', action='store_true')
    parser.add_argument('--road-repairs', action='store_true')
    parser.add_argument('--source-sha256', default=EXPECTED_SOURCE,
                        help='Exact frozen editable source hash; use the detail build report for a derived source')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    started = time.perf_counter()
    source = Path(bpy.data.filepath).resolve()
    source_hash = digest(source)
    if source_hash != args.source_sha256 or bpy.context.scene.get('R25_option') != 'B':
        raise RuntimeError('Expected the exact locally verified R24 + R25-B + R28 source')
    if source_hash != EXPECTED_SOURCE and bpy.context.scene.get('localDetailBaseSHA256') != EXPECTED_SOURCE:
        raise RuntimeError('Derived editable source is not linked to the preserved base')
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    design_path = Path(args.design).resolve()
    design = json.loads(design_path.read_text(encoding='utf-8-sig'))
    design_hash = digest(design_path)
    generator_names = ['export_blender.py', 'material_eval.py', 'glb_writer.py', 'forest_lod.py']
    if args.road_repairs:
        generator_names.append('road_repairs.py')
    generator = [{'path': f'tools/desert-runtime/{name}', 'sha256': digest(Path(__file__).parent / name)}
                 for name in generator_names]
    scene = bpy.context.scene
    multistage_areas = json.loads(scene.get('localMultistageAreas', '[]'))
    road_report = {'status': 'not_requested', 'source_saved': False}
    if args.road_repairs:
        from road_repairs import apply_road_repairs
        road_report = apply_road_repairs(scene)
        bpy.context.view_layer.update()
    write_json(out / 'derivation-preflight.json', {'sourceBlendSha256': source_hash, 'generatorInputs': generator,
                                                 'designSha256': design_hash, 'roadRepairs': road_report})
    allowed = render_collections(bpy.context.view_layer.layer_collection)
    direct = {obj.as_pointer() for obj in scene.objects if not obj.hide_render
              and any(col.as_pointer() in allowed for col in obj.users_collection)}
    graph = bpy.context.evaluated_depsgraph_get()
    writer = GLBWriter()
    plans = {}
    material_metrics = {}
    batches = collections.defaultdict(lambda: [[], [], [], 0])
    batch_serial = collections.Counter()
    group_bounds = {}
    source_rows = []
    pruning = collections.Counter()
    counts = collections.Counter()
    sample_owners = collections.Counter()
    cache = {}
    anchors = {obj.name[6:]: list(obj.matrix_world.translation) for obj in scene.objects if obj.name.startswith('PLACE_') and obj.type == 'EMPTY'}
    camera = scene.camera
    camera_hint = None
    if camera:
        cam_position = camera.matrix_world.translation
        cam_forward = camera.matrix_world.to_quaternion() @ Vector((0, 0, -1))
        reference = cam_position + cam_forward * (camera.data.ortho_scale * 1.5)
        camera_hint = {'name': camera.name, 'type': camera.data.type,
                       'gltfPosition': to_gltf(cam_position).tolist(), 'gltfTargetReference': to_gltf(reference).tolist(),
                       'horizontalSpanReference': float(camera.data.ortho_scale * SCALE),
                       'note': 'Inherited source review camera; production framing uses the landmark bounds.'}

    def flush(key):
        parts = batches[key]
        if not parts[3]:
            return
        group_id, material_id, protected, submap_index = key
        positions = np.concatenate(parts[0])
        colors = np.concatenate(parts[1])
        uvs = np.concatenate(parts[2]) if parts[2] else None
        for first in range(0, len(positions), 60000):
            end = min(first + 60000, len(positions))
            writer.batch(group_id, material_id, positions[first:end], colors[first:end], uvs[first:end] if uvs is not None else None,
                         protected, batch_serial[group_id], submap_index)
            batch_serial[group_id] += 1
        batches[key] = [[], [], [], 0]

    for instance in graph.object_instances:
        obj = instance.object.original
        if instance.object.type != 'MESH':
            continue
        counts['evaluatedMeshOccurrences'] += 1
        parent = instance.parent.original if instance.parent else None
        if instance.is_instance:
            if parent is None or parent.as_pointer() not in direct or obj.hide_render or not getattr(instance, 'show_self', True):
                pruning['hidden_or_unrendered_instance'] += 1
                continue
            group_id = owner(parent)
            counts['visibleInstanceOccurrencesBeforePruning'] += 1
        else:
            if obj.as_pointer() not in direct or not getattr(instance, 'show_self', True):
                pruning['hidden_or_excluded_source_object'] += 1
                continue
            group_id = owner(obj)
            counts['visibleDirectOccurrencesBeforePruning'] += 1
        submap_index = obj.get('submapIndex')
        if instance.is_instance and parent is not None and parent.get('submapIndex') is not None:
            submap_index = parent.get('submapIndex')
        if submap_index is not None and (isinstance(submap_index, bool) or not isinstance(submap_index, int) or not 0 <= submap_index <= 3):
            raise RuntimeError('Invalid observation submap index: ' + obj.name)
        if any('ARCHIVE' in col.name.upper() for col in obj.users_collection):
            pruning['explicit_archive_collection'] += 1
            continue
        if obj.name == 'solid-bottom':
            pruning['invisible_display_solid_bottom'] += 1
            continue
        if group_id == 'forest' and ('_branch_' in obj.name or '_buttress_' in obj.name):
            pruning['forest_secondary_branches_and_buttresses'] += 1
            continue
        world_matrix = np.asarray(instance.matrix_world, dtype=np.float32)
        bbox = np.asarray([instance.matrix_world @ Vector(corner) for corner in instance.object.bound_box], dtype=np.float32)
        if group_id == 'commune' and bbox[:, 2].max() < 0:
            pruning['commune_entirely_underground_object'] += 1
            continue
        key = obj.as_pointer()
        if key not in cache:
            evaluated = instance.object
            mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=graph)
            mesh.calc_loop_triangles()
            if not len(mesh.loop_triangles):
                evaluated.to_mesh_clear()
                pruning['empty_mesh'] += 1
                continue
            lod_mesh = None
            if group_id == 'forest' and 'overlapping_leaf_clusters' in obj.name:
                original_canopy_triangles = len(mesh.loop_triangles)
                lod_mesh = crown_lod(mesh)
                mesh = lod_mesh
                mesh.calc_loop_triangles()
                counts['uniqueCanopyTemplatesSimplified'] += 1
                counts['templateCanopyTrianglesBefore'] += original_canopy_triangles
                counts['templateCanopyTrianglesAfter'] += len(mesh.loop_triangles)
            vertex = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
            mesh.vertices.foreach_get('co', vertex)
            loop_vertex = np.empty(len(mesh.loops), dtype=np.int32)
            mesh.loops.foreach_get('vertex_index', loop_vertex)
            triangle_loops = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int32)
            mesh.loop_triangles.foreach_get('loops', triangle_loops)
            material_index = np.empty(len(mesh.loop_triangles), dtype=np.int32)
            mesh.loop_triangles.foreach_get('material_index', material_index)
            normals = np.empty(len(mesh.corner_normals) * 3, dtype=np.float32)
            mesh.corner_normals.foreach_get('vector', normals)
            attr_cache = {}

            def attributes(name):
                attribute = mesh.color_attributes.get(name) if name else mesh.color_attributes.active_color
                if attribute is None and len(mesh.color_attributes):
                    attribute = mesh.color_attributes[mesh.color_attributes.render_color_index]
                if attribute is None:
                    return np.ones((len(mesh.loops), 4), dtype=np.float32)
                if attribute.name not in attr_cache:
                    values = np.empty(len(attribute.data) * 4, dtype=np.float32)
                    attribute.data.foreach_get('color', values)
                    values = values.reshape(-1, 4)
                    attr_cache[attribute.name] = values[loop_vertex] if attribute.domain == 'POINT' else values
                return attr_cache[attribute.name]

            payloads = []
            for mat_index in np.unique(material_index):
                material = mesh.materials[int(mat_index)] if int(mat_index) < len(mesh.materials) else None
                mat_key = material.as_pointer() if material else 0
                if mat_key not in plans:
                    plans[mat_key] = MaterialPlan(material)
                plan = plans[mat_key]
                loops = triangle_loops.reshape(-1, 3)[material_index == mat_index].reshape(-1)
                loop_colors = plan.evaluate(plan.color, len(mesh.loops), attributes)
                loop_alpha = plan.evaluate(plan.alpha, len(mesh.loops), attributes)[:, 0]
                loop_colors[:, 3] = loop_alpha
                colors = loop_colors[loops].copy()
                uv = plan.uv(mesh, loops)
                image_node = plan.image_node
                texture_id = writer.texture(image_node.image, image_node.interpolation, image_node.extension) if image_node else None
                alpha = plan.alpha_linked or bool((colors[:, 3] < 0.999).any())
                runtime_material = writer.material(texture_id, alpha, plan.double_sided)
                payloads.append((vertex.reshape(-1, 3)[loop_vertex[loops]].copy(), normals.reshape(-1, 3)[loops].copy(),
                                 colors, uv, runtime_material, plan.baked, plan.name))
                material_metrics[plan.name] = {'originalMaterial': plan.name, 'runtimeMaterial': runtime_material,
                                               'baseTexture': image_node.image.name if image_node else None,
                                               'bakedSource': plan.baked, 'hasNormalMapInSource': plan.has_normal_map,
                                               'emissionFoldedToUnlitBase': plan.emission_folded,
                                               'sourceEmissionStrength': plan.source_emission_strength,
                                               'alphaImageEquivalence': plan.alpha_image_equivalence,
                                               'warnings': list(set(plan.warnings))}
            cache[key] = payloads
            evaluated.to_mesh_clear()
            if lod_mesh is not None:
                bpy.data.meshes.remove(lod_mesh)
        determinant = np.linalg.det(world_matrix[:3, :3])
        if determinant < 0:
            counts['negativeDeterminantOccurrencesRewound'] += 1
        normal_matrix = np.linalg.inv(world_matrix[:3, :3]).T
        object_triangles = 0
        for local_position, local_normal, color, uv, material_id, baked, material_name in cache[key]:
            local_tri = local_position.astype(np.float64).reshape(-1, 3, 3)
            local_cross = np.cross(local_tri[:, 1] - local_tri[:, 0], local_tri[:, 2] - local_tri[:, 0])
            counts['sourceZeroAreaTrianglesAcrossKeptOccurrences'] += int((np.einsum('ij,ij->i', local_cross, local_cross) == 0).sum())
            position = local_position @ world_matrix[:3, :3].T + world_matrix[:3, 3]
            normals = local_normal @ normal_matrix.T
            normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
            colors = color.copy()
            protected = (group_id in ['waste', 'fallen'] or baked) and not obj.get('runtimeForceDirectionalLight', False)
            if not protected:
                # Low-cost orientation lighting only, not a claimed physical AO bake.
                illumination = 0.53 + 0.38 * np.maximum(normals @ SUN, 0) + 0.09 * np.maximum(normals[:, 2], 0)
                colors[:, :3] *= illumination[:, None]
            colors = np.clip(colors, 0, 1)
            current_uv = uv.copy() if uv is not None else None
            if determinant < 0:
                order = np.arange(len(position)).reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
                position, colors = position[order], colors[order]
                current_uv = current_uv[order] if current_uv is not None else None
            if group_id == 'commune' and (position[:, 2] < 0).any():
                position, colors, current_uv, removed, clipped = clip_above_zero(position, colors, current_uv)
                pruning['commune_underground_triangles'] += removed
                pruning['commune_ground_crossing_triangles_clipped'] += clipped
            if not len(position):
                continue
            position = to_gltf(position)
            # Eliminate geometric zero-area/duplicate-point faces explicitly at the
            # actual exported Float32 precision, not by loosening the readback gate.
            export_tri = position.astype(np.float64).reshape(-1, 3, 3)
            cross = np.cross(export_tri[:, 1] - export_tri[:, 0], export_tri[:, 2] - export_tri[:, 0])
            valid = np.einsum('ij,ij->i', cross, cross) > 0
            pruning['zero_area_at_export_float32'] += int((~valid).sum())
            if not valid.all():
                position = position.reshape(-1, 3, 3)[valid].reshape(-1, 3)
                colors = colors.reshape(-1, 3, 4)[valid].reshape(-1, 4)
                current_uv = current_uv.reshape(-1, 3, 2)[valid].reshape(-1, 2) if current_uv is not None else None
            if not len(position):
                continue
            expand_bounds(group_bounds, group_id, position)
            batch_key = (group_id, material_id, protected, submap_index)
            batches[batch_key][0].append(position)
            batches[batch_key][1].append(colors)
            if current_uv is not None:
                batches[batch_key][2].append(current_uv)
            batches[batch_key][3] += len(position)
            object_triangles += len(position) // 3
            if batches[batch_key][3] >= 60000:
                flush(batch_key)
        if object_triangles:
            counts['keptInstanceOccurrences' if instance.is_instance else 'keptDirectOccurrences'] += 1
            sample_owners[group_id] += 1
            source_rows.append({'name': obj.name, 'placeId': group_id, 'submapIndex': submap_index,
                                'instanceParent': parent.name if instance.is_instance else None,
                                'triangles': object_triangles})
        if counts['evaluatedMeshOccurrences'] % 1500 == 0:
            print('DESERT_EXPORT_PROGRESS', counts['evaluatedMeshOccurrences'], round(time.perf_counter() - started, 1), flush=True)
    for key in list(batches):
        flush(key)
    pruning['same_attribute_opaque_duplicate_triangles'] = writer.duplicate_triangles_removed

    stage_ids = {entry['place']: entry['id'] for entry in design['stageMapping'] if entry.get('place')}
    design_names = {place['id']: place['name'] for place in design['places']}
    places = []
    for group_id, (lo, hi) in sorted(group_bounds.items()):
        if group_id == 'environment':
            continue
        center = (lo + hi) / 2
        anchor = to_gltf(anchors[group_id]).tolist() if group_id in anchors else center.tolist()
        subareas = []
        for area in multistage_areas:
            if area['placeId'] != group_id:
                continue
            box = to_gltf([area['worldBounds']['min'], area['worldBounds']['max']])
            subareas.append({key: area[key] for key in ['id', 'label', 'subStageIndex', 'sourceBackground']})
            subareas[-1].update(worldBounds={'min': box.min(axis=0).tolist(), 'max': box.max(axis=0).tolist()},
                                worldCenter=to_gltf(area['worldCenter']).tolist(),
                                sourceObjectCount=len(area.get('objects', [])))
        places.append({'id': group_id, 'placeId': group_id, 'name': design_names.get(group_id, group_id),
                       'stageId': stage_ids.get(group_id), 'formalEntry': group_id in FORMAL,
                       'worldAnchor': anchor, 'center': center.tolist(), 'bounds': {'min': lo.tolist(), 'max': hi.tolist()},
                       'sourceOwner': 'evaluated source ancestry/prefix with preserved world transforms',
                       'visibleOccurrences': sample_owners[group_id],
                       **({'subareas': sorted(subareas, key=lambda a: a['subStageIndex'])} if subareas else {})})
    if not all(any(place['id'] == item for place in places) for item in FORMAL):
        raise RuntimeError('Missing formal place bounds')
    all_lo = np.min([bounds[0] for bounds in group_bounds.values()], axis=0)
    all_hi = np.max([bounds[1] for bounds in group_bounds.values()], axis=0)
    framed = [p for p in places if p['id'] in FORMAL + ['waste', 'fallen', 'commune', 'forest']]
    overview = {'min': np.min([p['bounds']['min'] for p in framed], axis=0).tolist(),
                'max': np.max([p['bounds']['max'] for p in framed], axis=0).tolist()}
    places_doc = {'schema': 1, 'coordinateSystem': 'gltf-y-up-display/1000',
                  'coordinateTransform': '[source X, source Z, -source Y] * 0.001',
                  'sourceBlendSha256': source_hash, 'places': places, 'bounds': {'min': all_lo.tolist(), 'max': all_hi.tolist()},
                  'overviewBounds': overview, 'sourceCamera': camera_hint,
                  'scope': 'Existing formal stage identities only; display scale is not globally calibrated physical scale.'}
    for place in places:
        writer.anchor(place)
    write_json(out / 'places.json', places_doc)
    statistics = writer.save(out / 'scene.glb')
    print('DESERT_GLB_WRITTEN', json.dumps(statistics), flush=True)
    readback = {'performed': False}
    if not args.skip_roundtrip:
        cache.clear()
        bpy.ops.wm.read_factory_settings(use_empty=True)
        import_started = time.perf_counter()
        bpy.ops.import_scene.gltf(filepath=str(out / 'scene.glb'))
        meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
        triangles = 0
        for obj in meshes:
            obj.data.calc_loop_triangles()
            triangles += len(obj.data.loop_triangles)
        points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
        actual_bounds = to_gltf(np.asarray(points, dtype=np.float32) / SCALE)
        # Importer returns Z-up: mapping /SCALE above converts back to the exported GLTF coordinates.
        actual_min, actual_max = actual_bounds.min(axis=0), actual_bounds.max(axis=0)
        error = float(max(np.max(np.abs(actual_min - all_lo)), np.max(np.abs(actual_max - all_hi))))
        readback = {'performed': True, 'meshObjects': len(meshes), 'triangles': triangles,
                    'images': len(bpy.data.images), 'boundsErrorDisplayUnits': error,
                    'seconds': time.perf_counter() - import_started,
                    'pass': len(meshes) == statistics['meshes'] and triangles == statistics['triangles'] and error < 0.002}
        if not readback['pass']:
            write_json(out / 'readback-failure.json', readback)
            raise RuntimeError('Runtime GLB roundtrip mismatch')
    if digest(source) != source_hash:
        raise RuntimeError('Source identity changed during export')
    for item in generator:
        if digest(Path(__file__).parent / Path(item['path']).name) != item['sha256']:
            raise RuntimeError('Generator changed while export was in flight: ' + item['path'])
    if digest(design_path) != design_hash:
        raise RuntimeError('Design input changed while export was in flight')
    report = {'schema': 1, 'status': 'runtime_candidate_exported_not_live_verified',
              'createdUtc': datetime.now(timezone.utc).isoformat(), 'sourceBlend': str(source), 'sourceBlendSha256': source_hash,
              'generatorInputs': generator, 'designInput': {'path': str(design_path), 'sha256': design_hash},
              'blenderVersion': bpy.app.version_string, 'statistics': statistics, 'readback': readback,
              'pruning': dict(pruning), 'roadRepairs': road_report, 'sourceOccurrences': dict(counts), 'placeOccurrences': dict(sample_owners),
              'sourceUnchanged': True, 'coordinateSystem': 'gltf-y-up-display/1000',
              'bakedCityColorTreatment': 'Existing city vertex colours and embedded base textures retained; no extra orientation lighting applied to them.',
              'newLightingTreatment': 'Ordinary materials converted to unlit vertex orientation lighting; not a ray-traced AO bake.',
              'materials': list(material_metrics.values()), 'images': writer.image_audit,
              'meshes': writer.mesh_audit, 'elapsedSeconds': time.perf_counter() - started,
              'limitations': ['No physical collision or walking world is supplied.',
                             'Normal/roughness microdetail is not evaluated by this unlit first-pass display exporter.',
                             'Emission-only windows/signs are folded into bounded unlit colour; HDR bloom/exposure equivalence is not claimed.',
                             'Runtime CPU/GPU performance and visual equivalence still require the actual WebView2 entry.']}
    write_json(out / 'source-object-map.json', source_rows)
    write_json(out / 'export-report.json', report)
    print('DESERT_RUNTIME_EXPORT_COMPLETE', json.dumps({'out': str(out), 'seconds': report['elapsedSeconds'], 'statistics': statistics}), flush=True)


if __name__ == '__main__':
    main()
