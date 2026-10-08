"""Expand the supply point into the three currently registered gk18 submaps.

The existing camp becomes the first observation segment. Additional pale tent
groups occupy western/southwestern and northwestern clearings, preserving the
real regional road surface and the nearby refugee settlement. This is a compact
presentation reconstruction, not new gameplay routing or surveyed geography.
"""
import collections
import math
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from road_repairs import _clip, _area

SOURCE_SHA = '15e2253ba1636b680e58f90062f5c8fb4a1469fe9d3580a0c93520a874c6ecf4'
TERRAIN = {'REGIONAL_TERRAIN_BASE_REGISTERED', 'REGIONAL_BASE_TERRAIN_COLLAR',
           'R28_fallen_broad_relief', 'R28_waste_broad_relief'}


def owns(obj, place):
    while obj:
        if obj.get('placeId') == place or obj.name == 'PLACE_' + place:
            return True
        obj = obj.parent
    return False


def bounds(objects):
    points = [o.matrix_world @ Vector(v) for o in objects for v in o.bound_box]
    return [[min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]]


def apply_depot_multistage(scene, context):
    assert context['source_sha256'] == SOURCE_SHA
    assert not bpy.data.collections.get('MULTISTAGE_depot')
    original = [o for o in scene.objects if o.type == 'MESH' and not o.hide_render]
    existing = [o for o in original if owns(o, 'depot')]
    graph = bpy.context.evaluated_depsgraph_get()
    terrain_vertices, terrain_faces = [], []
    for o in original:
        if o.name not in TERRAIN:
            continue
        o.data.calc_loop_triangles(); start = len(terrain_vertices)
        terrain_vertices.extend(tuple(o.matrix_world @ v.co) for v in o.data.vertices)
        terrain_faces.extend(tuple(start+i for i in t.vertices) for t in o.data.loop_triangles)
    ground_bvh = BVHTree.FromPolygons(terrain_vertices, terrain_faces, all_triangles=True)

    def ground(x, y):
        p = ground_bvh.ray_cast(Vector((x, y, 20000)), Vector((0, 0, -1)), 40000)[0]
        if p is None: raise RuntimeError('Expanded depot escaped registered terrain')
        return p.z

    roads, road_grid = [], collections.defaultdict(set)
    road = bpy.data.objects['R24_RENDERED_REGIONAL_ROADS']; road.data.calc_loop_triangles()
    rv = [road.matrix_world @ v.co for v in road.data.vertices]
    cell = 300
    for tri in road.data.loop_triangles:
        xy = [(rv[i].x, rv[i].y) for i in tri.vertices]
        if max(p[0] for p in xy) < 19900 or min(p[0] for p in xy) > 26800 or max(p[1] for p in xy) < 10400 or min(p[1] for p in xy) > 17600:
            continue
        i = len(roads); roads.append(xy)
        for gx in range(math.floor(min(p[0] for p in xy)/cell), math.floor(max(p[0] for p in xy)/cell)+1):
            for gy in range(math.floor(min(p[1] for p in xy)/cell), math.floor(max(p[1] for p in xy)/cell)+1): road_grid[gx,gy].add(i)

    def road_overlap(rect, margin=55):
        x0,y0,x1,y1=rect; x0-=margin;y0-=margin;x1+=margin;y1+=margin
        polygon=[(x0,y0),(x1,y0),(x1,y1),(x0,y1)]; candidates=set()
        for gx in range(math.floor(x0/cell),math.floor(x1/cell)+1):
            for gy in range(math.floor(y0/cell),math.floor(y1/cell)+1): candidates.update(road_grid.get((gx,gy),()))
        return any(_area(_clip(polygon,roads[i]))>.1 for i in candidates)

    def overlap(a,b,margin=55):
        return a[0] < b[2]+margin and a[2] > b[0]-margin and a[1] < b[3]+margin and a[3] > b[1]-margin

    col=bpy.data.collections.new('MULTISTAGE_depot');scene.collection.children.link(col)
    col['sourceSHA256']=SOURCE_SHA;col['presentationOnly']=True
    rows={0:list(existing),1:[],2:[]};new=[];placements=[]
    for o in existing: o['submapIndex']=0;o['submapPlace']='depot'

    # Existing props are preserved. Flat ground/markings do not block expansion props.
    occupied=[]
    for o in existing:
        low,high=bounds([o])
        if high[2]-low[2] < 7: continue
        occupied.append([low[0],low[1],high[0],high[1]])

    source_groups={
        'tent':[o for o in original if o.name.startswith('SOURCE_ALIGNED_DEPOT_R04_TENT /')],
        'dome':[o for o in original if o.name.startswith('SOURCE_ALIGNED_DEPOT_R04_DOME /')],
        'rv':[o for o in original if o.name.startswith('SOURCE_DEPOT_R04_RV /')],
        'pale_vessels':[o for o in original if o.name.startswith('SOURCE_ALIGNED_DEPOT_R04_CONTAINERS_1 /')],
        'dark_drums':[o for o in original if o.name.startswith('SOURCE_ALIGNED_DEPOT_R04_CONTAINERS_2 /')],
        'carry_cans':[o for o in original if o.name.startswith('SOURCE_ALIGNED_DEPOT_R04_CONTAINERS_4 /')]
    }
    assert all(source_groups.values()), 'Missing a source depot feature'
    templates={}
    for kind,objects in source_groups.items():
        lo,hi=bounds(objects);cx=(lo[0]+hi[0])/2;cy=(lo[1]+hi[1])/2
        templates[kind]={'objects':objects,'center':(cx,cy),'offsets':[(x-cx,y-cy) for x in (lo[0],hi[0]) for y in (lo[1],hi[1])]}

    zones={0:[23100,10950,26350,14350],1:[20500,11000,23350,13000],2:[20500,14100,23450,17000]}

    def place(kind, segment, preferred, scale=1, rotation=0):
        template=templates[kind];c,s=math.cos(rotation),math.sin(rotation)
        offsets=[((x*c-y*s)*scale,(x*s+y*c)*scale) for x,y in template['offsets']]
        low=[min(p[i] for p in offsets) for i in range(2)];high=[max(p[i] for p in offsets) for i in range(2)]
        zone=zones[segment]
        candidates=[]
        # Search the entire authorized zone; a preferred point near an edge must
        # not accidentally exclude clear ground at the opposite side.
        xr=range(math.ceil((zone[0]+25-low[0]-preferred[0])/70),math.floor((zone[2]-25-high[0]-preferred[0])/70)+1)
        yr=range(math.ceil((zone[1]+25-low[1]-preferred[1])/70),math.floor((zone[3]-25-high[1]-preferred[1])/70)+1)
        for ix in xr:
            for iy in yr:
                x,y=preferred[0]+ix*70,preferred[1]+iy*70
                rect=[x+low[0],y+low[1],x+high[0],y+high[1]]
                if rect[0]<zone[0]+25 or rect[1]<zone[1]+25 or rect[2]>zone[2]-25 or rect[3]>zone[3]-25:continue
                if road_overlap(rect) or any(overlap(rect,b) for b in occupied):continue
                candidates.append((ix*ix+iy*iy,x,y,rect))
        if not candidates:
            raise RuntimeError(f'No road-clear footprint for depot segment {segment+1} {kind} at {preferred}')
        _,x,y,rect=min(candidates);occupied.append(rect)
        cx,cy=template['center'];label=f'MS_DP_{segment+1}_{kind}_{len(placements):02d}'
        made=[]
        for index,source in enumerate(template['objects']):
            e=source.evaluated_get(graph)
            mesh=bpy.data.meshes.new_from_object(e,preserve_all_data_layers=True,depsgraph=graph)
            for v in mesh.vertices:
                old=e.matrix_world@v.co;dx,dy=(old.x-cx)*scale,(old.y-cy)*scale
                nx,ny=x+dx*c-dy*s,y+dx*s+dy*c
                v.co=(nx,ny,ground(nx,ny)+max(.7,old.z-ground(old.x,old.y))*scale)
            mesh.update();obj=bpy.data.objects.new(label+'_'+str(index),mesh);col.objects.link(obj)
            obj['placeId']='depot';obj['submapIndex']=segment;obj['submapPlace']='depot'
            obj['sourceFeatureObject']=source.name;obj['runtimeForceDirectionalLight']=True
            rows[segment].append(obj);new.append(obj);made.append(obj.name)
        placements.append({'kind':kind,'subStageIndex':segment,'center':[x,y], 'scale':scale,'rotation':rotation,
                           'footprint':rect,'sourceObjects':[o.name for o in template['objects']],'objects':made,
                           'roadClearanceMargin':55,'proposal':'Source-derived asset grouping within a reconstructed submap region'})

    # First map retains the two existing RVs and its pale camp; a rear tent restores
    # the multi-group reading of gk18_1 without changing any old object transform.
    place('tent',0,(23450,11840),.53,.1)
    # Map 2: densely layered pale tents and domes, plus one RV, as in gk18_2.
    for x,y,scale,rotation in [(20980,11430,.57,.12),(21700,11450,.65,-.1),(22450,11450,.54,.05),
                               (23010,11600,.51,-.18),(20880,12300,.52,.15),(21600,12400,.59,0),
                               (22310,12410,.57,.12),(22940,12410,.49,-.1)]:
        place('tent',1,(x,y),scale,rotation)
    place('rv',1,(21200,11960),.68,math.pi/2+.12)
    for p,s in [((22000,11940),.72),((22700,12000),.67),((20690,12000),.66)]:place('dome',1,p,s,.15)
    # Map 3: a separate rear camp, with groups on available clear ground around
    # the existing diagonal road rather than a solid new enclosure across it.
    for x,y,scale,rotation in [(20900,16460,.59,.07),(21650,16500,.68,-.12),(22480,16500,.55,.10),
                               (20970,15540,.52,-.15),(22470,14610,.58,.05),(23000,15120,.60,-.1),
                               (21970,15000,.50,.12)]:
        place('tent',2,(x,y),scale,rotation)
    place('rv',2,(21180,15950),.70,math.pi/2+.05)
    place('dome',2,(21750,16000),.78,.2)
    place('dome',2,(23150,14600),.73,-.12)
    for segment,positions in [(1,[(21100,11200),(23100,12800)]),(2,[(20820,16800),(23100,14300)])]:
        for index,p in enumerate(positions):
            place('pale_vessels' if index==0 else 'dark_drums',segment,p,.75,0)
            place('carry_cans',segment,(p[0]+150,p[1]+60),.70,.2)

    bpy.context.view_layer.update()
    all_bounds=bounds(existing+new)
    subareas=[]
    labels=['第1段 · 转运前场','第2段 · 营帐纵深','第3段 · 后续驻营区']
    for segment,objects in rows.items():
        lo,hi=bounds(objects)
        subareas.append({'id':f'depot-{segment+1:02d}','placeId':'depot','subStageIndex':segment,
                         'sourceBackground':f'flashswf/backgrounds/gk18_{segment+1}_BG.swf','label':labels[segment],
                         'worldBounds':{'min':lo,'max':hi},'worldCenter':[(lo[i]+hi[i])/2 for i in range(3)],
                         'objects':[o.name for o in objects],
                         'layoutEvidence':'Current XML sequence and full background silhouettes; geographic arrangement is a reconstruction'})
    return {'sourceSHA256':SOURCE_SHA,'placeId':'depot','newObjects':[o.name for o in new],
            'retainedFirstSegmentObjects':[o.name for o in existing], 'hiddenOriginals':[],
            'subareas':subareas,'placements':placements,'expandedBounds':all_bounds,
            'expandedAllowedXY':[20500,11000,26350,17000], 'eastNeighborSeparation':'No new feature extends east of the existing depot envelope toward refugees',
            'roadObject':road.name,'boundedRoadTriangles':len(roads),
            'limits':['Three source submaps represented as distinct connected clearings, not new gameplay entrances.',
                      'Functional zone labels and the western/northwestern arrangement are display proposals.']}
