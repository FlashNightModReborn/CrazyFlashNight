"""Editable ruin ensemble derived from all three current gk19 backgrounds.

Broken door frames, jagged wall shells, rubble, faded tents and a motorhome are
source features. Their compact 3D arrangement is a presentation reconstruction;
it neither invents another stage nor changes the existing geographic anchor.
"""
import math
import random
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

VERSION = 'ambush-detail-v1'


def apply_ambush_details(scene, context=None):
    name = 'LOCAL_DETAIL_ambush'
    if bpy.data.collections.get(name):
        raise RuntimeError('Apply ambush detail only once to the frozen base')
    original = list(scene.objects)
    graph = bpy.context.evaluated_depsgraph_get()
    vertices, faces = [], []
    terrain_names = {'REGIONAL_TERRAIN_BASE_REGISTERED', 'REGIONAL_BASE_TERRAIN_COLLAR',
                     'R28_fallen_broad_relief', 'R28_waste_broad_relief'}
    for obj in original:
        if obj.name not in terrain_names or obj.hide_render:
            continue
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh(); mesh.calc_loop_triangles()
        offset = len(vertices)
        vertices.extend(tuple(evaluated.matrix_world @ v.co) for v in mesh.vertices)
        faces.extend(tuple(offset + i for i in tri.vertices) for tri in mesh.loop_triangles)
        evaluated.to_mesh_clear()
    bvh = BVHTree.FromPolygons(vertices, faces, all_triangles=True)

    def ground(x, y):
        point, _, _, _ = bvh.ray_cast(Vector((x, y, 20000)), Vector((0, 0, -1)), 40000)
        if point is None:
            raise RuntimeError('Ruin feature escaped registered terrain')
        return point.z

    collection = bpy.data.collections.new(name)
    scene.collection.children.link(collection)
    collection['presentationOnly'] = True
    collection['derivationVersion'] = VERSION
    added, hidden, copied = [], [], []

    def material(label, color):
        m = bpy.data.materials.new('LOCAL_AMBUSH_' + label)
        m.use_nodes = True; m.diffuse_color = (*color, 1)
        shader = m.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = (*color, 1)
        shader.inputs['Roughness'].default_value = .95
        return m

    concrete = material('weathered_wall', (.31, .30, .265))
    broken = material('pale_fracture', (.43, .42, .37))
    shaded = material('inner_plaster', (.235, .235, .21))
    footing = material('weathered_foundations', (.25, .25, .215))
    earth = material('compacted_ruin_dust', (.27, .265, .22))
    bone = material('old_bone', (.51, .48, .36))
    iron = material('exposed_rusted_rod', (.12, .11, .085))
    rng = random.Random(19072026)

    def register(obj, feature):
        collection.objects.link(obj)
        obj['placeId'] = 'ambush'; obj['derivationVersion'] = VERSION
        obj['sourceFeature'] = feature; obj['runtimeForceDirectionalLight'] = True
        obj.hide_render = False; added.append(obj.name)
        return obj

    def mesh_obj(label, points, polygons, materials, indices=None, feature='gk19 broken concrete shell'):
        mesh = bpy.data.meshes.new(label)
        mesh.from_pydata(points, [], polygons); mesh.update()
        for m in materials: mesh.materials.append(m)
        if indices:
            for poly, index in zip(mesh.polygons, indices): poly.material_index = index
        return register(bpy.data.objects.new(label, mesh), feature)

    def prism(label, polygon, x, y, yaw, thickness, base, mats=None):
        # Polygon is authored in the local horizontal/vertical plane, then extruded.
        c, s = math.cos(yaw), math.sin(yaw)
        count = len(polygon)
        points = [(x+u*c-v*s, y+u*s+v*c, base+h) for v in (-thickness/2, thickness/2) for u, h in polygon]
        sides = [(i, (i+1)%count, (i+1)%count+count, i+count) for i in range(count)]
        polygons = [tuple(reversed(range(count))), tuple(range(count, count*2)), *sides]
        polygons = [tuple(reversed(face)) for face in polygons]
        return mesh_obj(label, points, polygons,
                        mats or [concrete, shaded, broken], [0, 1] + [2]*count)

    def box(label, x, y, z, width, depth, height, mat, yaw=0):
        return prism(label, [(-width/2, 0), (width/2, 0), (width/2, height), (-width/2, height)],
                     x, y, yaw, depth, z, [mat, mat, mat])

    def tube(label, a, b, radius, mat, sides=6):
        a, b = Vector(a), Vector(b)
        axis = (b-a).normalized(); u = axis.cross(Vector((0, 0, 1)))
        if u.length < .01: u = axis.cross(Vector((0, 1, 0)))
        u.normalize(); v = axis.cross(u).normalized()
        points = [tuple(p + radius*(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides)))
                  for p in (a, b) for i in range(sides)]
        polygons = [tuple(reversed(range(sides))), tuple(range(sides, sides*2))]
        polygons += [(i, (i+1)%sides, (i+1)%sides+sides, i+sides) for i in range(sides)]
        return mesh_obj(label, points, polygons, [mat], feature='small source-like debris')

    def wall(label, x, y, length, height, angle, base=None):
        # Broad uneven breaks follow the source silhouettes; avoid a repeated sawtooth fence.
        profiles = [((0,.88),(.08,1),(.19,.94),(.29,.61),(.54,.57),(.60,.27),(.89,.24),(1,.14)),
                    ((0,.18),(.28,.20),(.34,.34),(.42,.32),(.70,.58),(.82,.96),(.94,1),(1,.87)),
                    ((0,.63),(.11,.60),(.20,.43),(.37,.20),(.69,.19),(.81,.27),(.93,.23),(1,.09))]
        profile = rng.choice(profiles)
        top = [(-length/2+u*length, height*h) for u,h in profile]
        base = ground(x, y)-2 if base is None else base
        return prism(label, [(-length/2, 0), (length/2, 0), *reversed(top)], x, y, angle, 28, base)

    def door(label, x, y, angle, width, height, base):
        # A real open arch outline, not a black rectangle pasted onto a solid box.
        outer = [(-width*.5, 0), (-width*.5, height*.55), (-width*.27, height),
                 (width*.27, height*.95), (width*.5, height*.53), (width*.5, 0)]
        inner = [(-width*.31, 0), (-width*.31, height*.40), (-width*.31, height*.73),
                 (width*.31, height*.73), (width*.31, height*.38), (width*.31, 0)]
        c, s = math.cos(angle), math.sin(angle)
        points = [(x+u*c-v*s, y+u*s+v*c, base+h) for v in (-16, 16) for edge in (outer, inner) for u, h in edge]
        polygons, indices = [], []
        for i in range(5):
            polygons += [(i, i+1, i+7, i+6), (i+12, i+18, i+19, i+13),
                         (i, i+12, i+13, i+1), (i+6, i+7, i+19, i+18)]
            indices += [0, 1, 2, 2]
        polygons += [(0, 6, 18, 12), (5, 17, 23, 11)]; indices += [2, 2]
        return mesh_obj(label, points, [tuple(reversed(face)) for face in polygons], [concrete, shaded, broken], indices)

    def rubble(label, x, y, radius, count):
        for i in range(count):
            angle = rng.random()*math.tau; distance = radius*math.sqrt(rng.random())
            px, py = x+math.cos(angle)*distance, y+math.sin(angle)*distance
            w, d, h = rng.uniform(15, 42), rng.uniform(12, 34), rng.uniform(8, 25)
            z = ground(px, py)-1
            points = [(px-w,py-d,z), (px+w,py-d*.7,z), (px+w*.7,py+d,z), (px-w*.8,py+d*.7,z),
                      (px-w*.45,py-d*.4,z+h), (px+w*.5,py-d*.35,z+h*.6),
                      (px+w*.25,py+d*.5,z+h*.8), (px-w*.4,py+d*.2,z+h*.5)]
            mesh_obj(label+'_'+str(i), points, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],
                     [concrete, broken], [0,1,0,1,0,0], 'gk19 scattered wall fragments')

    # Preserve the geographic place and hide only its four documented primitive placeholders.
    for obj in original:
        if obj.type == 'MESH' and obj.name in {'ambush_dry_1','ambush_dry_2','ambush_roof_3','ambush_concrete_4'}:
            obj.hide_render = True; hidden.append(obj.name)
    if len(hidden) != 4:
        raise RuntimeError('Ambush placeholder identity drift')

    shells = [(-7840,14640,390,270,245,-.10), (-7790,15320,410,310,300,.07),
              (-7060,15430,330,240,230,-.13), (-6410,15300,370,300,285,.12),
              (-6250,14655,345,265,225,-.07)]
    for i,(x,y,w,d,h,angle) in enumerate(shells):
        c,s=math.cos(angle),math.sin(angle)
        def pt(a,b): return x+a*c-b*s, y+a*s+b*c
        z=max(ground(*pt(a,b)) for a in (-w/2,w/2) for b in (-d/2,d/2))-2
        # The source is scattered wall remains, not five complete fenced courtyards.
        bx,by=pt(-w*.35,d*.28)
        box('AMB_foundation_fragment_'+str(i),bx,by,z-4,w*.23,d*.57,8,footing,angle)
        fx,fy=pt(0,-d/2);door('AMB_open_broken_door_'+str(i),fx,fy,angle,w*.58,h,z)
        for side in (-1,1):
            if (i,side) in {(0,1),(2,-1),(3,1)}:
                continue
            fraction = .62 if i in (2,4) else 1
            sx,sy=pt(side*w/2,-d*(1-fraction)/2)
            wall(f'AMB_return_wall_{i}_{side}',sx,sy,d*fraction,h*(.80 if side==1 else .68),angle+math.pi/2,z)
        if i != 4:
            bx,by=pt(w*.12,d/2)
            wall('AMB_partial_rear_'+str(i),bx,by,w*(.35 if i==1 else .70),h*(.35 if i==2 else .65),angle,z)
        # Broken lintel/slab rests on rubble instead of sealing the entire shell with a roof.
        sx,sy=pt(w*.2,d*.2)
        slab=box('AMB_fallen_slab_'+str(i),sx,sy,z+12,w*.38,d*.48,22,broken,angle+.35)
        if i in (0,3):
            # A fallen side section tilts into the debris; it is not a new intact roof.
            for v in slab.data.vertices:
                lift = max(0, (v.co.x-(sx-w*.19))*.34)
                v.co.z += lift
            slab.data.update()
        if i%2 == 0:
            rubble('AMB_collapse_'+str(i),*pt(w*.37,-d*.3),75,7)
        for rod in range(2):
            sx,sy=pt(-w*.48, d*.18+rod*10)
            tube(f'AMB_exposed_rod_{i}_{rod}',(sx,sy,z+h*.38),(sx+5,sy-7,z+h*.56),2.0,iron)
    wall('AMB_free_standing_partition',-7135,14575,300,180,.10)
    rubble('AMB_displaced_lintel',-6760,15200,95,10)
    rubble('AMB_west_fall',-8130,15095,80,7)

    def clone_feature(prefix, label, x, y, scale, rotation):
        rows=[o for o in original if o.type=='MESH' and not o.hide_render and o.name.startswith(prefix)]
        if not rows: raise RuntimeError('Missing source feature '+prefix)
        points=[o.matrix_world@Vector(v) for o in rows for v in o.bound_box]
        cx=(min(v.x for v in points)+max(v.x for v in points))/2
        cy=(min(v.y for v in points)+max(v.y for v in points))/2
        c,s=math.cos(rotation),math.sin(rotation)
        for i,src in enumerate(rows):
            e=src.evaluated_get(graph);m=bpy.data.meshes.new_from_object(e,preserve_all_data_layers=True,depsgraph=graph)
            for v in m.vertices:
                p=e.matrix_world@v.co;dx,dy=(p.x-cx)*scale,(p.y-cy)*scale
                nx,ny=x+dx*c-dy*s,y+dx*s+dy*c
                v.co=(nx,ny,ground(nx,ny)+max(1,p.z-ground(p.x,p.y))*scale)
            m.update();obj=register(bpy.data.objects.new(label+'_'+str(i),m),'gk19 source-like reused tent/motorhome')
            obj['copiedSourceObject']=src.name;copied.append({'source':src.name,'copy':obj.name})
    clone_feature('SOURCE_DEPOT_R04_RV /','AMB_abandoned_motorhome',-7430,14955,.62,math.pi/2+.08)
    clone_feature('SOURCE_ALIGNED_DEPOT_R04_DOME /','AMB_small_faded_tent',-8135,15480,.60,-.3)
    # Two subtle old animal-remain clusters are visible in the gk19 reference; no gore or live actors.
    for n,(x,y) in enumerate([(-7500,14505),(-6620,14790)]):
        z=ground(x,y)+5
        tube('AMB_old_spine_'+str(n),(x-26,y,z),(x+26,y,z),3,bone)
        for k in range(5):
            a=x-18+k*8
            tube(f'AMB_old_rib_{n}_{k}',(a,y-13,z),(a+3,y+13,z+4),2,bone)
    bpy.context.view_layer.update()
    return {'version':VERSION,'places':{'ambush':{'addedObjects':len(added),'hiddenOriginals':hidden,
              'sourceFeatures':['five broken door/wall groups','partial shell returns and collapsed lintels',
                                'faded tent and motorhome','scattered fragments and old bones'],
              'proposedDetails':['compact five-shell 3D arrangement','small exposed rebar and foundations'],
              'sourceBackgrounds':['gk19_1_BG.swf','gk19_2_BG.swf','gk19_3_BG.swf']}},
            'addedObjects':added,'hiddenOriginals':hidden,'copiedSourceObjects':copied,
            'sourceFeatures':'See current full gk19 frame evidence; layout is a presentation reconstruction',
            'proposedDetails':'Local 3D composition only; geographic PLACE_ambush and gameplay identity unchanged'}
