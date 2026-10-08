"""Bounded, in-memory repair of the inherited Waste-city approach for export.

Source Blend files are never saved here. A repair is published into the current
scene only after source endpoint, city-corridor and ground checks pass. Fallen's
inherited approach is deliberately left for a separate design decision.
"""
import collections
import json
import math
import time

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

NAME = 'RUNTIME_WASTE_APPROACH_REPAIR'
START = Vector((8500.0, -4750.0, 38.498046875))
END = Vector((12136.0, -8992.0, 127.99807739257812))
START_DIRECTION = Vector((0.6507914066314697, -0.7592566013336182))
ALLOWED_GROUND = {'WASTE_R24_City_Ground', 'WASTE_R24_City_Continuation_Ground',
                  'WASTE_R24_Connected_Street_Courts', 'WASTE_R24_City_Streets'}
STEP = 40.0
MAX_GRADE = 0.12  # Display-geometry constraint, not a vehicle/engineering certification.


def _visible(obj):
    return obj.type == 'MESH' and not obj.hide_render and any(not c.hide_render for c in obj.users_collection)


def _bvh(objects):
    vertices, faces = [], []
    for obj in objects:
        obj.data.calc_loop_triangles()
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
        faces.extend(tuple(offset + i for i in triangle.vertices) for triangle in obj.data.loop_triangles)
    return BVHTree.FromPolygons(vertices, faces, all_triangles=True) if faces else None


def _cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _area(points):
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:] + points[:1]))) * .5 if len(points) > 2 else 0


def _clip(subject, clip):
    orientation = 1 if _cross(clip[0], clip[1], clip[2]) >= 0 else -1
    output = list(subject)
    for a, b in zip(clip, clip[1:] + clip[:1]):
        source, output = output, []
        if not source:
            break
        previous = source[-1]
        dp = orientation * _cross(a, b, previous)
        for current in source:
            dc = orientation * _cross(a, b, current)
            if (dc >= -1e-7) != (dp >= -1e-7):
                t = dp / (dp - dc)
                output.append((previous[0] + (current[0] - previous[0]) * t,
                               previous[1] + (current[1] - previous[1]) * t))
            if dc >= -1e-7:
                output.append(current)
            previous, dp = current, dc
    return output


def _line_hits_triangle(a, b, triangle):
    orientation = 1 if _cross(*triangle) >= 0 else -1
    lo, hi = 0.0, 1.0
    for x, y in zip(triangle, triangle[1:] + triangle[:1]):
        da, db = orientation * _cross(x, y, a), orientation * _cross(x, y, b)
        if da < 0 and db < 0:
            return False
        if da < 0 or db < 0:
            t = da / (da - db)
            if da < 0:
                lo = max(lo, t)
            else:
                hi = min(hi, t)
    return hi - lo > 1e-7


def _rounded_path(controls):
    points = [Vector(controls[0])]
    for i in range(1, len(controls) - 1):
        a, b, c = Vector(controls[i - 1]), Vector(controls[i]), Vector(controls[i + 1])
        # The regional mouth is 420 display units wide. A 72-unit trim at the
        # first bend folds its inner offset; leave a deliberately larger turn.
        radius = min(260, (b - a).length * .4, (c - b).length * .4)
        entry = b + (a - b).normalized() * radius
        exit_point = b + (c - b).normalized() * radius
        points.append(entry)
        for j in range(1, 9):
            t = j / 8
            points.append(entry * (1 - t) ** 2 + b * (2 * t * (1 - t)) + exit_point * t ** 2)
    points.append(Vector(controls[-1]))
    sampled = [points[0]]
    for a, b in zip(points, points[1:]):
        count = max(1, math.ceil((b - a).length / STEP))
        for j in range(1, count + 1):
            p = a.lerp(b, j / count)
            if (p - sampled[-1]).length > 1e-5:
                sampled.append(p)
    return sampled


def _obstacles(objects):
    triangles, grid = [], collections.defaultdict(set)
    cell_size = 256.0
    for obj in objects:
        obj.data.calc_loop_triangles()
        points = [obj.matrix_world @ v.co for v in obj.data.vertices]
        for triangle in obj.data.loop_triangles:
            xyz = [points[i] for i in triangle.vertices]
            xy = [(p.x, p.y) for p in xyz]
            if max(p[0] for p in xy) < 8250 or min(p[0] for p in xy) > 12250 or max(p[1] for p in xy) < -9300 or min(p[1] for p in xy) > -4500:
                continue
            index = len(triangles)
            triangles.append({'xy': xy, 'object': obj.name, 'z': [min(p.z for p in xyz), max(p.z for p in xyz)], 'area': _area(xy)})
            for x in range(math.floor(min(p[0] for p in xy) / cell_size), math.floor(max(p[0] for p in xy) / cell_size) + 1):
                for y in range(math.floor(min(p[1] for p in xy) / cell_size), math.floor(max(p[1] for p in xy) / cell_size) + 1):
                    grid[x, y].add(index)
    return triangles, grid, cell_size


def _corridor_hits(sections, obstacle_data):
    triangles, grid, cell_size = obstacle_data
    hits = []
    for i in range(len(sections) - 1):
        left, right = sections[i]['baseXY']
        next_left, next_right = sections[i + 1]['baseXY']
        for strip in ([left, right, next_right], [left, next_right, next_left]):
            candidates = set()
            for x in range(math.floor(min(p[0] for p in strip) / cell_size), math.floor(max(p[0] for p in strip) / cell_size) + 1):
                for y in range(math.floor(min(p[1] for p in strip) / cell_size), math.floor(max(p[1] for p in strip) / cell_size) + 1):
                    candidates.update(grid.get((x, y), ()))
            for index in candidates:
                triangle = triangles[index]
                if triangle['area'] > 1e-5:
                    area = _area(_clip(triangle['xy'], strip))
                    collision = area > .01
                else:
                    a, b = max(((a, b) for a in triangle['xy'] for b in triangle['xy']), key=lambda p: math.dist(*p))
                    collision, area = math.dist(a, b) > .1 and _line_hits_triangle(a, b, strip), 0
                if collision:
                    hits.append({'section': i, 'object': triangle['object'], 'projectedOverlapArea': area, 'obstacleZ': triangle['z']})
                    if len(hits) >= 12:
                        return hits
    return hits


def _strip_samples(a, b, key, steps=4):
    # Same explicit diagonal as the exported triangles, not a bilinear patch.
    left, right = a[key]
    next_left, next_right = b[key]
    for x, y, z in ((left, right, next_right), (left, next_right, next_left)):
        for i in range(steps + 1):
            for j in range(steps + 1 - i):
                yield x * (i / steps) + y * (j / steps) + z * (1 - (i + j) / steps)


def apply_road_repairs(scene):
    begin = time.perf_counter()
    report = {'schema': 'cf7-runtime-derived-road-repair/1', 'status': 'deferred',
              'created_objects': [], 'excluded_original_objects': [], 'checks': {}, 'attempts': [],
              'units': 'Blender display-scene XYZ, Z up; not physical metres',
              'source_saved': False, 'notes': ['Fallen approach retained unchanged; a direct strip through the enlarged city is not an accepted repair.',
                                              'This repairs a visual candidate connection only, not gameplay navigation or vehicle clearance.']}
    if bpy.data.objects.get(NAME):
        report.update(status='already_present', created_objects=[NAME])
        return report
    old = scene.objects.get('R24_WASTE_DERIVED_APPROACH')
    roads = scene.objects.get('R24_RENDERED_REGIONAL_ROADS')
    streets = scene.objects.get('WASTE_R24_City_Streets')
    base = scene.objects.get('REGIONAL_TERRAIN_BASE_REGISTERED')
    if scene.get('R25_option') != 'B' or not all((old, roads, streets, base)):
        report['notes'].append('Required B-scene geometry is missing; no source objects hidden.')
        return report
    bpy.context.view_layer.update()
    street_tree, road_tree = _bvh([streets]), _bvh([roads])
    terrain_objects = [base] + [o for o in scene.objects if o.name in {'R28_fallen_broad_relief', 'R28_waste_broad_relief'} and _visible(o)]
    terrain_trees = [_bvh([o]) for o in terrain_objects]
    ground_cache = {}
    def ground(xy):
        key = (round(float(xy[0]), 5), round(float(xy[1]), 5))
        if key not in ground_cache:
            heights = []
            for bvh in terrain_trees:
                hit = bvh.ray_cast(Vector((xy[0], xy[1], 100000)), Vector((0, 0, -1)), 200000)[0]
                if hit is not None:
                    heights.append(hit.z)
            if not heights:
                raise RuntimeError('No source ground under candidate corridor')
            ground_cache[key] = max(heights)
        return ground_cache[key]
    source_start = road_tree.find_nearest(START)
    source_end = street_tree.find_nearest(END)
    report['checks']['regional_start_reference_error'] = source_start[3]
    report['checks']['city_street_reference_error'] = source_end[3]
    if source_start[3] > 1 or source_end[3] > 1 or source_end[1].z < .95:
        report['notes'].append('Reference endpoint is no longer on the expected current surface.')
        return report
    start, end = source_start[0], source_end[0]
    city_obstacles = [o for o in scene.objects if o.name.startswith('WASTE_R24_') and _visible(o) and o.name not in ALLOWED_GROUND]
    obstacle_data = _obstacles(city_obstacles)
    report['checks']['city_obstacle_meshes'] = [o.name for o in city_obstacles]
    report['checks']['allowed_existing_ground_meshes'] = sorted(ALLOWED_GROUND)
    p1 = Vector((start.x, start.y)) + START_DIRECTION * 360
    variants = [
        ('west_entry_gentle_bend', [(start.x, start.y), tuple(p1), (8660, -6920), (10900, -8580), (11680, -8992), (end.x, end.y)]),
        ('retained_middle_then_west_entry', [(start.x, start.y), tuple(p1), (8660, -6920), (10500, -7480), (11050, -8992), (end.x, end.y)]),
        ('southern_west_entry', [(start.x, start.y), tuple(p1), (8660, -6920), (10000, -8640), (11250, -8992), (end.x, end.y)]),
    ]
    accepted = None
    try:
        for variant, controls in variants:
            path = _rounded_path(controls)
            distances = [0.0]
            for a, b in zip(path, path[1:]):
                distances.append(distances[-1] + (b - a).length)
            total = distances[-1]
            heights, sections = [], []
            for i, p in enumerate(path):
                fraction = distances[i] / total
                tangent = START_DIRECTION.copy() if i == 0 else Vector((1, 0)) if i == len(path) - 1 else (path[i + 1] - path[i - 1]).normalized()
                side = Vector((-tangent.y, tangent.x))
                width = 420 + (120 - 420) * min(1, fraction / .45) if fraction <= .45 else 120 + (48 - 120) * (fraction - .45) / .55
                sample_heights = [ground(p + side * width / 2 * q) for q in (-1, -.5, 0, .5, 1)]
                heights.append(max(start.z + (end.z - start.z) * fraction, max(sample_heights) + 4))
                sections.append({'center': p, 'side': side, 'width': width, 'groundMax': max(sample_heights)})
            heights[0], heights[-1] = start.z, end.z
            for i in range(1, len(heights)):
                heights[i] = max(heights[i], heights[i - 1] - MAX_GRADE * (distances[i] - distances[i - 1]))
            for i in range(len(heights) - 2, -1, -1):
                heights[i] = max(heights[i], heights[i + 1] - MAX_GRADE * (distances[i + 1] - distances[i]))
            attempt = {'variant': variant, 'controlsXY': [list(p) for p in controls], 'length': total, 'sections': len(sections)}
            report['attempts'].append(attempt)
            if heights[0] - start.z > .2 or heights[-1] - end.z > .2:
                attempt.update(status='rejected', reason='ground_profile_cannot_meet_fixed_endpoints_without_excess_grade')
                continue
            endpoint_errors = []
            for i, section in enumerate(sections):
                p, side, width = section['center'], section['side'], section['width']
                top_xy = [p + side * width / 2, p - side * width / 2]
                section['top'] = [Vector((xy.x, xy.y, heights[i])) for xy in top_xy]
                if i in (0, len(sections) - 1):
                    bvh = road_tree if i == 0 else street_tree
                    for j, vertex in enumerate(section['top']):
                        hit, normal, _, error = bvh.find_nearest(vertex)
                        endpoint_errors.append(error)
                        section['top'][j] = hit
                        top_xy[j] = Vector((hit.x, hit.y))
                end_fade = min(1, distances[i] / 260, (total - distances[i]) / 260)
                shoulder = min(65, max(0, heights[i] - section['groundMax']) * .5) * max(0, end_fade)
                base_xy = [top_xy[0] + side * shoulder, top_xy[1] - side * shoulder]
                section['baseXY'] = [tuple(xy) for xy in base_xy]
                section['bottom'] = [Vector((xy.x, xy.y, ground(xy) - .25)) for xy in base_xy]
            if max(endpoint_errors) > 1.5:
                attempt.update(status='rejected', reason='cross_section_does_not_match_source_road_or_street', errors=endpoint_errors)
                continue
            folds = []
            for i in range(len(sections) - 1):
                for key in ('top', 'bottom'):
                    left, right = sections[i][key]
                    next_left, next_right = sections[i + 1][key]
                    area_a, area_b = _cross(left, right, next_right), _cross(left, next_right, next_left)
                    if min(area_a, area_b) <= 1e-5:
                        folds.append({'section': i, 'surface': key, 'twiceAreas': [area_a, area_b],
                                      'center': list(sections[i]['center']), 'width': sections[i]['width']})
            if folds:
                attempt.update(status='rejected', reason='candidate_cross_sections_fold_in_plan', foldSamples=folds[:8])
                continue
            collisions = _corridor_hits(sections, obstacle_data)
            if collisions:
                attempt.update(status='rejected', reason='would_cover_existing_city_structure', collisions=collisions)
                continue
            minimum_clearance = float('inf')
            for i in range(len(sections) - 1):
                for p in _strip_samples(sections[i], sections[i + 1], 'top'):
                    minimum_clearance = min(minimum_clearance, p.z - ground(p))
            if minimum_clearance < -.15:
                attempt.update(status='rejected', reason='road_surface_intersects_source_terrain', minimum_clearance=minimum_clearance)
                continue
            # A flat underside can bridge a small terrain hollow even if its four
            # corners touch ground. Sink only the derived footing sufficiently to
            # keep the sampled entire underside buried; never move source ground.
            for i in range(len(sections) - 1):
                needed = 0.0
                for p in _strip_samples(sections[i], sections[i + 1], 'bottom'):
                    needed = max(needed, p.z - ground(p) + .25)
                if needed > 0:
                    for section in sections[i:i + 2]:
                        for vertex in section['bottom']:
                            vertex.z -= needed + .01
            maximum_bottom_gap = -float('inf')
            for i in range(len(sections) - 1):
                for p in _strip_samples(sections[i], sections[i + 1], 'bottom'):
                    maximum_bottom_gap = max(maximum_bottom_gap, p.z - ground(p))
            attempt.update(status='accepted', minimum_ground_clearance=minimum_clearance,
                           maximum_sampled_bottom_gap=maximum_bottom_gap, endpoint_errors=endpoint_errors)
            accepted = (variant, sections, distances, minimum_clearance, endpoint_errors, maximum_bottom_gap)
            break
    except Exception as error:
        report['notes'].append('Geometry inspection failed safely: ' + str(error))
        report['elapsed_seconds'] = time.perf_counter() - begin
        return report
    if accepted is None:
        report['notes'].append('No bounded corridor passed; original approach remains visible and unchanged.')
        report['elapsed_seconds'] = time.perf_counter() - begin
        return report
    variant, sections, distances, minimum_clearance, endpoint_errors, maximum_bottom_gap = accepted
    vertices = [tuple(v) for section in sections for v in section['top'] + section['bottom']]
    faces, slots = [], []
    def quad(indices, material_slot):
        a, b, c, d = indices
        faces.extend([(a, b, c), (a, c, d)])
        slots.extend([material_slot, material_slot])
    for i in range(len(sections) - 1):
        a, b = i * 4, (i + 1) * 4
        quad((a, a + 1, b + 1, b), 0)
        quad((a + 2, a + 3, b + 3, b + 2), 1)
        # Reverse bottom winding while retaining the checked diagonal.
        faces[-2] = tuple(reversed(faces[-2])); faces[-1] = tuple(reversed(faces[-1]))
        quad((a, b, b + 2, a + 2), 1)
        quad((a + 1, a + 3, b + 3, b + 1), 1)
    last = (len(sections) - 1) * 4
    quad((0, 2, 3, 1), 1); quad((last, last + 1, last + 3, last + 2), 1)
    if not all(math.isfinite(v) for vertex in vertices for v in vertex):
        report['notes'].append('Non-finite derived geometry refused.')
        return report
    mesh = bpy.data.meshes.new(NAME + '_MESH')
    mesh.from_pydata(vertices, [], faces); mesh.update(); mesh.calc_loop_triangles()
    if any(triangle.area <= 1e-8 for triangle in mesh.loop_triangles):
        bpy.data.meshes.remove(mesh)
        report['notes'].append('Degenerate derived solid refused; original approach retained.')
        return report
    edge_counts = collections.Counter(tuple(sorted(pair)) for face in faces for pair in zip(face, face[1:] + face[:1]))
    if any(count != 2 for count in edge_counts.values()):
        bpy.data.meshes.remove(mesh)
        report['notes'].append('Derived solid is not edge-closed; original approach retained.')
        return report
    for material in old.data.materials[:2]:
        mesh.materials.append(material)
    if len(mesh.materials) < 2:
        bpy.data.meshes.remove(mesh)
        report['notes'].append('Original road and earth materials unavailable.')
        return report
    for polygon, slot in zip(mesh.polygons, slots):
        polygon.material_index = slot
    collection = bpy.data.collections.new('RUNTIME_DERIVED_ROAD_REPAIRS')
    scene.collection.children.link(collection)
    obj = bpy.data.objects.new(NAME, mesh); collection.objects.link(obj)
    obj.hide_render = False
    obj['placeId'] = 'waste'
    obj['runtimeForceDirectionalLight'] = True
    obj['sourceObjectsJson'] = json.dumps([old.name, roads.name, streets.name, *[o.name for o in terrain_objects]])
    obj['repairScope'] = 'Derived display approach solid; source Blend and city meshes unchanged; no gameplay qualification'
    excluded = [old]
    banks = scene.objects.get('R24_WASTE_LOCAL_CUT_BANKS')
    if banks:
        excluded.append(banks)
    previous_visibility = {o.name: o.hide_render for o in excluded}
    for original in excluded:
        original.hide_render = True
    report.update(status='applied', created_objects=[obj.name], excluded_original_objects=[o.name for o in excluded],
                  prior_hide_render=previous_visibility, chosen_variant=variant,
                  source_mapping={obj.name: [old.name, roads.name, streets.name]},
                  materials=[m.name for m in mesh.materials], vertices=len(vertices), triangles=len(mesh.loop_triangles),
                  centerline_length=distances[-1], width_start=420, width_end=48,
                  elapsed_seconds=time.perf_counter() - begin)
    report['checks'].update(endpoint_cross_section_max_error=max(endpoint_errors),
                            actual_start_center=list((sections[0]['top'][0] + sections[0]['top'][1]) * .5),
                            actual_end_center=list((sections[-1]['top'][0] + sections[-1]['top'][1]) * .5),
                            minimum_sampled_top_clearance=minimum_clearance,
                            bottom_projected_and_buried=True, maximum_sampled_bottom_above_ground=maximum_bottom_gap,
                            solid_edge_closed=True,
                            projected_city_obstacle_intersections=0, finite_vertices=True,
                            source_city_meshes_changed=False, source_regional_road_changed=False,
                            nominal_grade_limit=MAX_GRADE)
    return report
