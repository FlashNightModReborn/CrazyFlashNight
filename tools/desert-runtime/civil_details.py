"""Local, editable camp/depot detail derived from current gk17/gk18 art.

This is a deterministic presentation patch, not a new canonical settlement map.
Original detailed tents, vehicles and containers stay intact. Copies retain their
source material/UV layers; new props use silhouettes visible in the source SWFs.
"""
import math
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

VERSION = 'civil-detail-v1'
TERRAIN_NAMES = ('REGIONAL_TERRAIN_BASE_REGISTERED', 'REGIONAL_BASE_TERRAIN_COLLAR',
                 'R28_fallen_broad_relief', 'R28_waste_broad_relief')


def apply_civil_details(scene, context=None):
    context = context or {}
    if any(bpy.data.collections.get('LOCAL_DETAIL_' + p) for p in ('refugees', 'depot')):
        raise RuntimeError('civil_details must be applied once to a fresh source scene')
    graph = bpy.context.evaluated_depsgraph_get()
    original = list(scene.objects)
    vertices, faces = [], []
    for obj in original:
        if obj.name not in TERRAIN_NAMES or obj.hide_render:
            continue
        e = obj.evaluated_get(graph); m = e.to_mesh(); m.calc_loop_triangles()
        offset = len(vertices)
        vertices.extend(tuple(e.matrix_world @ v.co) for v in m.vertices)
        faces.extend(tuple(offset + i for i in t.vertices) for t in m.loop_triangles)
        e.to_mesh_clear()
    if not faces:
        raise RuntimeError('Registered terrain is required for civil details')
    bvh = BVHTree.FromPolygons(vertices, faces, all_triangles=True)

    def ground(x, y):
        p, _, _, _ = bvh.ray_cast(Vector((x, y, 20000)), Vector((0, 0, -1)), 40000)
        if p is None:
            raise RuntimeError('Civil detail escaped registered terrain')
        return p.z

    collections = {}
    objects = {p: [] for p in ('refugees', 'depot')}
    copies = {p: [] for p in objects}
    hidden = {p: [] for p in objects}
    for p in objects:
        col = bpy.data.collections.new('LOCAL_DETAIL_' + p)
        scene.collection.children.link(col); collections[p] = col
        col['presentationOnly'] = True; col['derivationVersion'] = VERSION

    def register(obj, p, feature):
        collections[p].objects.link(obj)
        obj['placeId'] = p; obj['derivationVersion'] = VERSION
        obj['sourceFeature'] = feature
        obj['runtimeForceDirectionalLight'] = True
        obj.hide_render = False
        objects[p].append(obj)
        return obj

    def material(name, rgb):
        name = 'LOCAL_CIVIL_' + name
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True; m.diffuse_color = (*rgb, 1)
        shader = m.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = (*rgb, 1)
        shader.inputs['Roughness'].default_value = .88
        return m

    wood = material('weathered_wood', (.20, .17, .105))
    edge = material('crate_slats', (.29, .25, .16))
    metal = material('dark_drum', (.07, .077, .071))
    rim = material('worn_drum_bands', (.13, .14, .12))
    rope = material('tent_guys', (.18, .16, .115))
    can = material('red_brown_carry_can', (.24, .105, .078))
    bedding = material('used_bedding', (.22, .165, .075))

    def mesh_obj(p, name, v, f, mat, feature):
        m = bpy.data.meshes.new(name); m.from_pydata(v, [], f); m.update()
        m.materials.append(mat)
        return register(bpy.data.objects.new(name, m), p, feature)

    def box(p, name, center, dimensions, mat, yaw=0, feature='source-visible storage box'):
        x, y, z = center; dx, dy, dz = (v/2 for v in dimensions)
        c, s = math.cos(yaw), math.sin(yaw)
        v = [(x+a*c-b*s, y+a*s+b*c, z+d) for a,b,d in
             [(-dx,-dy,-dz),(dx,-dy,-dz),(dx,dy,-dz),(-dx,dy,-dz),
              (-dx,-dy,dz),(dx,-dy,dz),(dx,dy,dz),(-dx,dy,dz)]]
        return mesh_obj(p,name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,feature)

    def tube(p, name, a, b, radius, mat, sides=8, feature='source-visible tent guy rope'):
        a, b = Vector(a), Vector(b); axis = (b-a).normalized()
        u = axis.cross(Vector((0,0,1)))
        if u.length < .01: u = axis.cross(Vector((0,1,0)))
        u.normalize(); w = axis.cross(u).normalized()
        v = [tuple(q+(u*math.cos(i*math.tau/sides)+w*math.sin(i*math.tau/sides))*radius)
             for q in (a,b) for i in range(sides)]
        f = [tuple(reversed(range(sides))), tuple(range(sides, sides*2))]
        f.extend((i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides))
        return mesh_obj(p,name,v,f,mat,feature)

    def clone_group(p, label, source_objects, x, y, rotation=0, scale=1):
        if not source_objects:
            raise RuntimeError('Missing current source feature: ' + label)
        bounds = [o.matrix_world @ Vector(v) for o in source_objects for v in o.bound_box]
        cx=(min(v.x for v in bounds)+max(v.x for v in bounds))/2
        cy=(min(v.y for v in bounds)+max(v.y for v in bounds))/2
        c,s=math.cos(rotation),math.sin(rotation)
        for index, src in enumerate(source_objects):
            e = src.evaluated_get(graph)
            m = bpy.data.meshes.new_from_object(e, preserve_all_data_layers=True, depsgraph=graph)
            m.name = 'LOCAL_' + label + '_' + str(index)
            for vertex in m.vertices:
                old=e.matrix_world @ vertex.co
                dx,dy=(old.x-cx)*scale,(old.y-cy)*scale
                nx,ny=x+dx*c-dy*s,y+dx*s+dy*c
                clearance=max(.65,old.z-ground(old.x,old.y))*scale
                vertex.co=(nx,ny,ground(nx,ny)+clearance)
            m.update()
            obj=register(bpy.data.objects.new(m.name,m),p,'copied current source geometry and material')
            obj['sourceObjectName']=src.name
        copies[p].append({'label':label,'sourceObjectCount':len(source_objects),'center':[x,y],
                          'scale':scale,'rotationRadians':rotation,'sourceNames':[o.name for o in source_objects]})

    def drum(p, name, x, y, radius=14, height=35):
        z=ground(x,y)+1
        tube(p,name+'_body',(x,y,z),(x,y,z+height),radius,metal,12,'black drum visible in gk17_3')
        for h in (2,height*.34,height*.73,height-1):
            tube(p,name+'_band_'+str(h),(x,y,z+h),(x,y,z+h+1.4),radius+1,rim,12,'rolled drum band')

    def crate(p, name, x, y, size=35, yaw=0):
        z=ground(x,y)+1
        box(p,name,(x,y,z+size*.40),(size,size*.75,size*.80),wood,yaw)
        for i in (-1,1):
            # Slatted lid and two narrow uprights give a readable box without a uniform field of cubes.
            box(p,name+'_lid_'+str(i),(x+i*size*.25*math.cos(yaw),y+i*size*.25*math.sin(yaw),z+size*.81),
                (size*.10,size*.80,2.4),edge,yaw)
        for h in (.13,.67):
            box(p,name+'_band_'+str(h),(x,y,z+size*h),(size*1.015,size*.77,2.2),edge,yaw)

    def carry_can(p, name, x, y, size=25, yaw=0):
        z=ground(x,y)+1
        box(p,name,(x,y,z+size*.52),(size*.74,size*.34,size),can,yaw,'red-brown carry can visible in gk17/gk18')
        for side in (-1,1):
            px=x+side*size*.21*math.cos(yaw);py=y+side*size*.21*math.sin(yaw)
            tube(p,name+'_handle_'+str(side),(px,py,z+size),(px,py,z+size*1.22),1.5,metal,6,'open carry-can handle')
        tube(p,name+'_handle_top',(x-size*.21*math.cos(yaw),y-size*.21*math.sin(yaw),z+size*1.22),
             (x+size*.21*math.cos(yaw),y+size*.21*math.sin(yaw),z+size*1.22),1.5,metal,6,'open carry-can handle')
        tube(p,name+'_cap',(x+size*.20,y+size*.06,z+size*.97),(x+size*.27,y+size*.06,z+size*1.12),3.2,metal,8,'short carry-can cap')

    def guy(p,name,x,y,dx,dy,height=60):
        tube(p,name,(x,y,ground(x,y)+height),(x+dx,y+dy,ground(x+dx,y+dy)+1),1.0,rope,6)
        tube(p,name+'_peg',(x+dx,y+dy,ground(x+dx,y+dy)),(x+dx-2,y+dy,ground(x+dx,y+dy)+9),1.4,wood,6)

    # Refugee daily settlement: irregular households, no defended army grid or abundant stockpile.
    aframe=[o for o in original if 'SARF04 A-frame A /' in o.name and o.type=='MESH' and not o.hide_render]
    folded=[o for o in original if 'SARF04 Folded B /' in o.name and o.type=='MESH' and not o.hide_render]
    for label,group,x,y,rot,scale in [
        ('RF_household_08',aframe,27300,11600,.28,1.12),
        ('RF_household_09',folded,27680,11680,-.65,1.06),
        ('RF_household_10',aframe,28380,12400,math.pi+.2,1.15),
        ('RF_household_11',folded,28460,12800,1.25,1.10),
        ('RF_household_12',folded,28680,11900,-.3,.95)]:
        clone_group('refugees',label,group,x,y,rot,scale)
    for i,(x,y) in enumerate([(27605,12270),(27270,12370),(27900,12530),(27980,11500),(28520,11370),(28845,12490),(28305,12650)]):
        crate('refugees','RF_household_box_'+str(i),x,y,34+(i%3)*4,.13*i)
        if i in (0,2,4,6):carry_can('refugees','RF_carry_can_'+str(i),x+48,y-11,24,.2*i)
    for i,(x,y) in enumerate([(27530,12530),(27980,12480),(28510,11520)]):
        drum('refugees','RF_reused_drum_'+str(i),x,y,13,34)
    vessel=[o for o in original if 'SARF04 Single pale storage vessel' in o.name and o.type=='MESH' and not o.hide_render]
    clone_group('refugees','RF_shared_vessel',vessel,27950,12080,0,1.12)
    # Finite visible ropes are tied to occupied tent corners, not a decorative fence.
    for i,(x,y,dx,dy,h) in enumerate([(27650,12470,-50,45,55),(27840,12470,45,50,55),
         (28105,11370,-50,40,52),(27300,12285,-50,38,50),(27435,12285,45,42,50),
         (27790,12910,-50,32,55),(27960,12910,45,32,55),(28885,12400,-45,35,40)]):
        guy('refugees','RF_visible_tent_guy_'+str(i),x,y,dx,dy,h)
    for i,(x,y,yaw) in enumerate([(27655,12410,0),(27472,12235,0),(28150,11213,math.pi/2),
                                  (27783,12860,0),(27522,12690,0)]):
        z=ground(x,y)+2
        box('refugees','RF_used_sleeping_mat_'+str(i),(x,y,z+2.4),(46,29,4.8),bedding,yaw,
            'ochre bedding visible inside gk17 tent openings')
        tube('refugees','RF_rolled_bedding_'+str(i),(x-14,y-10,z+7),(x-14,y+10,z+7),5,bedding,8,
             'ochre bedding visible inside gk17 tent openings')

    # Supply point: reuse the source pale canvas family, with a clear vehicle/loading lane.
    # Root confirmed these old box walls were unaccepted placeholders; all three
    # current gk18 backgrounds depict an open camp. Preserve editable originals.
    for obj in original:
        if obj.name.startswith(('DP / Enclosure ', 'DP / Gate post ')) and not obj.hide_render:
            obj.hide_render = True
            hidden['depot'].append(obj.name)
    tent=[o for o in original if o.name.startswith('SOURCE_ALIGNED_DEPOT_R04_TENT /') and o.type=='MESH' and not o.hide_render]
    dome=[o for o in original if o.name.startswith('SOURCE_ALIGNED_DEPOT_R04_DOME /') and o.type=='MESH' and not o.hide_render]
    rv=[o for o in original if o.name.startswith('SOURCE_DEPOT_R04_RV /') and o.type=='MESH' and not o.hide_render]
    clone_group('depot','DP_second_pale_tent',tent,25700,12350,.18,.69)
    clone_group('depot','DP_small_pale_tent',tent,24280,12140,math.pi/2,.50)
    # Locations checked against actual regional road triangles with 25-unit
    # footprint clearance and 22-unit separation from occupied source geometry.
    clone_group('depot','DP_second_dome',dome,25495,12890,-.32,1.02)
    clone_group('depot','DP_third_dome',dome,24315,12460,.55,.86)
    clone_group('depot','DP_second_motorhome',rv,24130,13900,1.25,.70)
    # A handful of cargo groups consolidates the supply function without filling the central lane.
    for i,(x,y,size) in enumerate([(25820,13700,70),(25910,13630,60),(25870,13560,54),
                                 (23980,13000,65),(24060,13040,58),(23990,13100,48)]):
        crate('depot','DP_delivery_crate_'+str(i),x,y,size,.09*i)
    for i,(x,y) in enumerate([(25880,12810),(25935,12780),(24890,13705),(23950,12720)]):
        carry_can('depot','DP_additional_carry_can_'+str(i),x,y,42,.17*i)
    for i,(x,y) in enumerate([(25590,13680),(25660,13670),(24030,12660)]):
        drum('depot','DP_service_drum_'+str(i),x,y,27,66)

    bpy.context.view_layer.update()
    places = {}
    for p, added in objects.items():
        allv=[obj.matrix_world @ Vector(v) for obj in added for v in obj.bound_box]
        places[p]={'addedObjects':len(added),'addedObjectNames':[o.name for o in added],
                   'hiddenOriginals':hidden[p], 'copiedFeatures':copies[p],
                   'addedBounds':[[min(v[i] for v in allv) for i in range(3)],
                                  [max(v[i] for v in allv) for i in range(3)]]}
    return {'version':VERSION,'sourceSHA256':context.get('source_sha256'),'places':places,'addedObjects':sum(len(v) for v in objects.values()),
            'hiddenOriginals':[name for names in hidden.values() for name in names],
            'sourceFeatures':{'refugees':['gk17_1_BG.swf','gk17_2_BG.swf','gk17_3_BG.swf',
                                        'dark used canvas, guy ropes, pale vessel, red-brown carry cans, wood box, black drum'],
                              'depot':['gk18_1_BG.swf','gk18_2_BG.swf','gk18_3_BG.swf',
                                       'pale canvas tents, low dome shelters, motorhome, carry cans and pale vessels']},
            'proposedDetails':['household and delivery group placement is a presentation layout, not canonical map geometry',
                               'five extra refugee shelters, four extra depot shelters and a second motorhome reuse existing source geometry',
                               'original earth traces remain; no new road, well, wall, unit or permanent lore claim']}
