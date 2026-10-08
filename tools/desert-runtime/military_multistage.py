"""Four connected source-informed districts for fort and frontbase.

Input is the preserved six-place detail-v2 scene. The old courtyards and all
original objects stay in place; new districts extend the display footprint.
Subareas are observation metadata, never additional game entry IDs.
"""
import collections
import hashlib
import math
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

SOURCE_SHA = '15e2253ba1636b680e58f90062f5c8fb4a1469fe9d3580a0c93520a874c6ecf4'
TERRAIN = {'REGIONAL_TERRAIN_BASE_REGISTERED', 'REGIONAL_BASE_TERRAIN_COLLAR',
           'R28_fallen_broad_relief', 'R28_waste_broad_relief'}
GROUND = {'fort': 'court / open manoeuvre area',
          'frontbase': 'FB / ground / compacted open compound'}
HALF_SIZE = {'fort': (5080., 3900.), 'frontbase': (3910., 3215.4)}
LABELS = {'fort': ['第1段 · 入营空场', '第2段 · 军需仓配', '第3段 · 通信营区', '第4段 · 指挥集结'],
          'frontbase': ['第1段 · 撤收后勤', '第2段 · 防空驻车', '第3段 · 装甲驻车', '第4段 · 指挥核心']}
ZONE_BOXES = {
    'fort': [[(-4800,-3780,4800,-2010)], [(-4900,-1890,-2560,3690)],
             [(-2540,-1950,2540,1950),(2600,-1810,3550,1480)],
             [(-2450,2010,4890,3780),(3670,-1890,4890,2010)]],
    'frontbase': [[(-3680,1500,3680,3070)], [(-3780,-1410,-1890,1460)],
                  [(-3670,-3070,3670,-1520)],
                  [(-1700,-1398,1700,1398),(1870,-1420,3770,1420)]]}
# A shared service margin belongs visually to the motor pool; its ground is
# already supplied by the adjacent arrival apron, so no coincident floor is made.
PLACEMENT_EXTRA = {('frontbase',1): [(-2660,1510,-2020,2170)]}
CONNECTORS = {
    'fort': [[(0,-2490),(-2410,-2490),(-3650,-1740),(-3650,250)],
             [(-3650,250),(-2420,150)],
             [(-450,2020),(1450,2240),(3340,2240),(3570,1500),(3570,-1480)]],
    'frontbase': [[(1200,1870),(-1000,1840),(-1850,1590),(-1810,1000)],
                  [(-1810,1000),(-1810,-1450),(-1900,-1820),(0,-1820)],
                  [(0,-1820),(0,-1400)],
                  [(460,1400),(1780,1470),(2790,1370),(2820,-1090)]]}


def _cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def _area(p):return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(p,p[1:]+p[:1])))*.5 if len(p)>2 else 0.


def _clip(subject, clip):
    sign=1 if _cross(*clip[:3])>=0 else -1
    result=list(subject)
    for a,b in zip(clip,clip[1:]+clip[:1]):
        previous=result;result=[]
        if not previous:break
        q=previous[-1];dq=sign*_cross(a,b,q)
        for r in previous:
            dr=sign*_cross(a,b,r)
            if (dq>=-1e-7)!=(dr>=-1e-7):
                t=dq/(dq-dr);result.append((q[0]+t*(r[0]-q[0]),q[1]+t*(r[1]-q[1])))
            if dr>=-1e-7:result.append(r)
            q,dq=r,dr
    return result


def _hull(points):
    points=sorted(set(points));lo=[];hi=[]
    for p in points:
        while len(lo)>1 and _cross(lo[-2],lo[-1],p)<=0:lo.pop()
        lo.append(p)
    for p in reversed(points):
        while len(hi)>1 and _cross(hi[-2],hi[-1],p)<=0:hi.pop()
        hi.append(p)
    return lo[:-1]+hi[:-1]


def _bbox(points):return [min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)]
def _rect(box,pad=0):return [(box[0]-pad,box[1]-pad),(box[2]+pad,box[1]-pad),(box[2]+pad,box[3]+pad),(box[0]-pad,box[3]+pad)]
def _overlap(a,b,pad=0):return min(a[2],b[2])-max(a[0],b[0])>-pad and min(a[3],b[3])-max(a[1],b[1])>-pad
_BUFFER_DIRECTIONS=tuple((math.cos(i*math.tau/16),math.sin(i*math.tau/16)) for i in range(16))


def _expand(poly,pad):
    # Convex rounded buffer in the footprint's actual orientation. World-axis
    # AABBs overstate diagonal tents and falsely eliminate otherwise open lanes.
    return _hull([(x+pad*u,y+pad*v) for x,y in poly for u,v in _BUFFER_DIRECTIONS])


def _visible_collections(layer, blocked=False):
    blocked=blocked or layer.exclude or layer.collection.hide_render
    found=set() if blocked else {layer.collection.as_pointer()}
    for c in layer.children:found.update(_visible_collections(c,blocked))
    return found


def _owner(obj):
    while obj:
        if obj.get('placeId'):return str(obj['placeId'])
        if obj.name.startswith('PLACE_'):return obj.name[6:]
        obj=obj.parent
    return None


def _bounds(objects):
    points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    return [[min(p[a] for p in points) for a in range(3)], [max(p[a] for p in points) for a in range(3)]]


def _material(name,color):
    m=bpy.data.materials.new('MS '+name);m.diffuse_color=(*color,1);m.use_nodes=True
    bsdf=m.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(*color,1)
    bsdf.inputs['Roughness'].default_value=.95
    return m


class _RoadIndex:
    def __init__(self, triangles):
        self.triangles=triangles;self.grid=collections.defaultdict(set);self.cell=240.
        for i,t in enumerate(triangles):
            for k in self.keys(_bbox(t)):self.grid[k].add(i)

    def keys(self,b):
        for x in range(math.floor(b[0]/self.cell),math.floor(b[2]/self.cell)+1):
            for y in range(math.floor(b[1]/self.cell),math.floor(b[3]/self.cell)+1):yield x,y

    def intersects(self, polygon, pad=0):
        if pad:polygon=_expand(polygon,pad)
        candidates=set()
        for k in self.keys(_bbox(polygon)):candidates.update(self.grid.get(k,()))
        return any(_area(_clip(polygon,self.triangles[i]))>1 for i in candidates)


class MilitaryExpansion:
    def __init__(self,scene):
        self.scene=scene;self.new={'fort':[],'frontbase':[]};self.original={};self.frames={};self.collections={}
        self.zone_objects={p:[[] for _ in range(4)] for p in self.new}
        self.assets={};self.clusters=[];self.moved=[];self.road_skips=collections.Counter();self.ground_triangles=collections.Counter()
        allowed=_visible_collections(bpy.context.view_layer.layer_collection)
        self.visible=[o for o in scene.objects if o.type=='MESH' and not o.hide_render and any(c.as_pointer() in allowed for c in o.users_collection)]
        for p in self.new:
            self.original[p]=[o for o in self.visible if _owner(o)==p]
            for obj in self.original[p]:obj['submapIndex']=2 if p=='fort' else 3
            m=bpy.data.objects[GROUND[p]].matrix_world
            self.frames[p]=(m.translation.x,m.translation.y,math.atan2(m[1][0],m[0][0]))
            name='MILITARY_MULTISTAGE_'+p
            assert bpy.data.collections.get(name) is None, 'Multistage expansion already applied'
            collection=bpy.data.collections.new(name);scene.collection.children.link(collection)
            collection['sourceSHA256']=SOURCE_SHA;collection['scope']='four-substage display reconstruction'
            self.collections[p]=collection
        graph=bpy.context.evaluated_depsgraph_get();vertices=[];faces=[]
        for original in self.visible:
            if original.name not in TERRAIN and original.name not in GROUND.values():continue
            o=original.evaluated_get(graph);mesh=o.to_mesh();mesh.calc_loop_triangles();offset=len(vertices)
            vertices.extend(o.matrix_world@v.co for v in mesh.vertices)
            faces.extend(tuple(offset+i for i in t.vertices) for t in mesh.loop_triangles);o.to_mesh_clear()
        self.terrain=BVHTree.FromPolygons(vertices,faces,all_triangles=True);self.height_cache={}
        road=bpy.data.objects['R24_RENDERED_REGIONAL_ROADS'];road.data.calc_loop_triangles()
        points=[road.matrix_world@v.co for v in road.data.vertices]
        triangles=[]
        for tri in road.data.loop_triangles:
            xy=[(points[i].x,points[i].y) for i in tri.vertices];b=_bbox(xy)
            if _overlap(b,[17500,17000,43000,49500]):triangles.append(xy)
        self.road=_RoadIndex(triangles)
        self.road_signature=hashlib.sha256(repr([tuple(v) for v in points]).encode()).hexdigest()
        connector_triangles=[]
        for p,paths in CONNECTORS.items():
            for path in paths:
                strip=self._strip(p,path,220.)
                for i in range(0,len(strip)-2,2):
                    connector_triangles.extend([[strip[i],strip[i+1],strip[i+3]],[strip[i],strip[i+3],strip[i+2]]])
        self.connections=_RoadIndex(connector_triangles)
        self.obstacles=[]
        groups=collections.defaultdict(list)
        for p,objects in self.original.items():
            for obj in objects:
                n=obj.name
                if n.startswith(('court','FB /','fort_light')):continue
                if n.startswith(('SA_FORT_TENT','SA_FRONTBASE_TENT','SOURCE_ALIGNED_FORT','Menghu_G05_R07','RHINO_R09','FRONTBASE RV')):
                    key=n.split(' /')[0]
                elif n.startswith('MD ') and ' / ' in n and len(n.split(' / '))>2:key=' / '.join(n.split(' / ')[:2])
                else:key=n
                groups[p,key].append(obj)
        for (p,name),objects in groups.items():
            pts=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
            if max(v.z for v in pts)-min(v.z for v in pts)<65:continue
            poly=_hull([(v.x,v.y) for v in pts])
            self.obstacles.append((p,_bbox(poly),poly,name))
        self.materials={'ground':_material('compacted camp soil',(.29,.275,.225)),
                        'road':_material('local service track',(.24,.225,.185)),
                        'sandbag':_material('low earth-filled cover',(.20,.145,.09))}

    def xy(self,p,x,y):
        ox,oy,a=self.frames[p];return (ox+math.cos(a)*x-math.sin(a)*y,oy+math.sin(a)*x+math.cos(a)*y)

    def local(self,p,x,y):
        ox,oy,a=self.frames[p];return (math.cos(a)*(x-ox)+math.sin(a)*(y-oy),-math.sin(a)*(x-ox)+math.cos(a)*(y-oy))

    def height(self,x,y):
        key=(round(x,3),round(y,3))
        if key not in self.height_cache:
            q=self.terrain.ray_cast(Vector((x,y,20000)),Vector((0,0,-1)),40000)[0]
            assert q is not None, 'Expanded military ground falls outside terrain'
            self.height_cache[key]=q.z
        return self.height_cache[key]

    def register(self,p,zone,obj,role):
        obj['placeId']=p;obj['runtimeForceDirectionalLight']=True;obj['multistageRole']=role
        obj['multistageSourceSHA256']=SOURCE_SHA
        if zone is not None:
            obj['subareaId']=f'{p}-{zone+1:02d}';obj['subStageIndex']=zone;obj['submapIndex']=zone
            self.zone_objects[p][zone].append(obj)
        self.collections[p].objects.link(obj);self.new[p].append(obj)
        return obj

    def mesh(self,p,zone,name,verts,faces,material,role):
        data=bpy.data.meshes.new('MS '+name);data.from_pydata(verts,[],faces);data.materials.append(self.materials[material]);data.update()
        obj=bpy.data.objects.new('MS '+p+' / '+name,data)
        return self.register(p,zone,obj,role)

    def _strip(self,p,path,width):
        centers=[]
        for a,b in zip(path,path[1:]):
            n=max(1,math.ceil(math.dist(a,b)/150))
            centers.extend([(a[0]+(b[0]-a[0])*i/n,a[1]+(b[1]-a[1])*i/n) for i in range(n)])
        centers.append(path[-1]);result=[]
        for i,c in enumerate(centers):
            before=Vector(c)-Vector(centers[max(0,i-1)]);after=Vector(centers[min(len(centers)-1,i+1)])-Vector(c)
            if before.length<.01:before=after.copy()
            if after.length<.01:after=before.copy()
            before.normalize();after.normalize();n=Vector((-before.y-after.y,before.x+after.x)).normalized()
            scale=(width/2)/max(.55,n.dot(Vector((-after.y,after.x))))
            for side in (-1,1):result.append(self.xy(p,c[0]+n.x*scale*side,c[1]+n.y*scale*side))
        return result

    def grounds(self,p):
        old_zone=2 if p=='fort' else 3
        for zone,boxes in enumerate(ZONE_BOXES[p]):
            for index,(xmin,ymin,xmax,ymax) in enumerate(boxes):
                if zone==old_zone and index==0:continue
                nx=math.ceil((xmax-xmin)/150);ny=math.ceil((ymax-ymin)/150)
                vertices=[]
                for j in range(ny+1):
                    for i in range(nx+1):
                        x,y=self.xy(p,xmin+(xmax-xmin)*i/nx,ymin+(ymax-ymin)*j/ny)
                        vertices.append((x,y,self.height(x,y)+.7))
                faces=[]
                for j in range(ny):
                    for i in range(nx):
                        a=j*(nx+1)+i;b=a+1;c=b+nx+1;d=a+nx+1
                        for tri in [(a,b,c),(a,c,d)]:
                            if self.road.intersects([(vertices[q][0],vertices[q][1]) for q in tri]):
                                self.road_skips[p]+=1;continue
                            faces.append(tri)
                self.ground_triangles[p]+=len(faces)
                used=sorted({i for face in faces for i in face});mapping={old:new for new,old in enumerate(used)}
                self.mesh(p,zone,f'zone {zone+1} terrain apron {index}',[vertices[i] for i in used],
                          [tuple(mapping[i] for i in face) for face in faces],'ground','terrain_apron')
        for index,path in enumerate(CONNECTORS[p]):
            pairs=self._strip(p,path,190.);verts=[(x,y,self.height(x,y)+8) for x,y in pairs];faces=[]
            for i in range(0,len(verts)-2,2):faces.extend([(i,i+3,i+1),(i,i+2,i+3)])
            self.mesh(p,None,f'linked service route {index}',verts,faces,'road','connector')

    def source_asset(self,prefix,source_place):
        key=(prefix,source_place)
        if key not in self.assets:
            objects=[o for o in self.visible if _owner(o)==source_place and (o.name==prefix or o.name.startswith(prefix+' /'))]
            assert objects, 'Missing native source asset: '+prefix
            pts=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
            lo=[min(v[a] for v in pts) for a in range(3)];hi=[max(v[a] for v in pts) for a in range(3)]
            center=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
            poly=_hull([(v.x-center.x,v.y-center.y) for v in pts])
            self.assets[key]=(objects,center,poly)
        return self.assets[key]

    def asset(self,p,zone,name,prefix,source_place,x,y,scale=1.,yaw=0,search=640):
        source,origin,poly=self.source_asset(prefix,source_place)
        scales=(scale,scale,scale) if isinstance(scale,(int,float)) else scale
        target_angle=self.frames[p][2]+yaw;source_angle=self.frames[source_place][2]
        linear=Matrix.Rotation(target_angle,4,'Z')@Matrix.Diagonal((*scales,1))@Matrix.Rotation(-source_angle,4,'Z')
        shape=[linear@Vector((u,v,0)) for u,v in poly]
        deltas=[(i,j) for i in range(-search,search+1,80) for j in range(-search,search+1,80)]
        if (0,0) not in deltas:deltas.append((0,0))
        deltas.sort(key=lambda q:(q[0]*q[0]+q[1]*q[1],abs(q[0])+abs(q[1]),q))
        picked=None
        for dx,dy in deltas:
            cx,cy=self.xy(p,x+dx,y+dy);foot=[(cx+v.x,cy+v.y) for v in shape]
            local=[self.local(p,*q) for q in foot];hx,hy=HALF_SIZE[p]
            if any(abs(u)>hx-55 or abs(v)>hy-55 for u,v in local):continue
            zone_boxes=ZONE_BOXES[p][zone]+PLACEMENT_EXTRA.get((p,zone),[])
            if any(not any(a-15<=u<=c+15 and b-15<=v<=d+15 for a,b,c,d in zone_boxes) for u,v in local):continue
            if self.road.intersects(foot,150) or self.connections.intersects(foot,70):continue
            bbox=_bbox(foot);padded=_expand(foot,55)
            if any(q==p and _overlap(bbox,b,55) and _area(_clip(padded,hull))>1 for q,b,hull,_ in self.obstacles):continue
            samples=foot+[(cx,cy)]+[((a[0]+b[0])/2,(a[1]+b[1])/2) for a,b in zip(foot,foot[1:]+foot[:1])]
            heights=[self.height(*q) for q in samples]
            if max(heights)-min(heights)>55:continue
            picked=(dx,dy,cx,cy,foot,max(heights)+5,max(heights)-min(heights));break
        if picked is None:raise RuntimeError(f'No bounded road-clear placement: {p}/{name} near {x},{y}')
        dx,dy,cx,cy,foot,z,gap=picked
        delta=Matrix.Translation((cx,cy,z))@linear@Matrix.Translation(-origin)
        added=[]
        for original in source:
            obj=bpy.data.objects.new(f'MS {p}-{zone+1:02d} / {name} / '+original.name.split(' / ',1)[-1],original.data.copy())
            obj.matrix_world=delta@original.matrix_world;obj['sourceObjectName']=original.name
            obj['multistageCluster']=name;obj['supportHeightRange']=gap
            self.register(p,zone,obj,'structure');added.append(obj.name)
        self.obstacles.append((p,_bbox(foot),foot,name))
        self.clusters.append({'placeId':p,'subareaId':f'{p}-{zone+1:02d}','name':name,'sourceTemplate':prefix,
                              'objects':added,'footprintXY':[list(q) for q in foot],'localCenter':[x+dx,y+dy],
                              'supportHeightRange':gap,'regionalRoadOverlap':False})
        if dx or dy:self.moved.append({'placeId':p,'name':name,'nominalLocal':[x,y],'placedLocal':[x+dx,y+dy]})

    def tent(self,p,z,name,x,y,scale=1.,yaw=0):
        self.asset(p,z,name,'SA_FORT_TENT_18','fort',x,y,scale,yaw)

    def supply(self,p,z,name,x,y,scale=1):
        self.asset(p,z,name,'SA_FORT_HAZARD_STACK_32','fort',x,y,scale,search=400)

    def frame(self,p,z,name,x,y,scale=1.5):
        self.asset(p,z,name,'SA_FORT_ARCHED_FRAME_26','fort',x,y,scale,search=800)

    def mast(self,p,z,name,x,y,scale=.55):
        # The inherited main tower stays the dominant one. Additional source
        # masts are smaller field relays, never new geographic anchors.
        self.asset(p,z,name,'SA_FORT_LATTICE_TOWER','fort',x,y,scale,search=400)

    def perimeter(self,p):
        hx,hy=HALF_SIZE[p];hx-=110;hy-=110;c=300
        ring=[(-hx+c,-hy),(hx-c,-hy),(hx,-hy+c),(hx,hy-c),(hx-c,hy),(-hx+c,hy),(-hx,hy-c),(-hx,-hy+c)]
        for edge,(a,b) in enumerate(zip(ring,ring[1:]+ring[:1])):
            n=max(1,round(math.dist(a,b)/285));angle=math.atan2(b[1]-a[1],b[0]-a[0])+self.frames[p][2]
            for i in range(n):
                x=a[0]+(b[0]-a[0])*(i+.5)/n;y=a[1]+(b[1]-a[1])*(i+.5)/n;wx,wy=self.xy(p,x,y)
                shape=[(wx+u*math.cos(angle)-v*math.sin(angle),wy+u*math.sin(angle)+v*math.cos(angle)) for u,v in [(-116,-57),(116,-57),(116,57),(-116,57)]]
                if self.road.intersects(shape,210) or self.connections.intersects(shape,90):continue
                vertices=[];faces=[]
                for layer in range(2):
                    for bag in range(2):
                        u=(bag-.5)*116+(12 if layer else -12);cx=wx+u*math.cos(angle);cy=wy+u*math.sin(angle)
                        z=self.height(cx,cy)+layer*39+3;offset=len(vertices)
                        corners=[(-47,-49),(47,-49),(57,-36),(57,36),(47,49),(-47,49),(-57,36),(-57,-36)]
                        for dz in (0,43):
                            vertices.extend((cx+a*math.cos(angle)-b*math.sin(angle),cy+a*math.sin(angle)+b*math.cos(angle),z+dz) for a,b in corners)
                        faces.extend([tuple(offset+j for j in reversed(range(8))),tuple(offset+8+j for j in range(8))])
                        faces.extend((offset+j,offset+(j+1)%8,offset+(j+1)%8+8,offset+j+8) for j in range(8))
                self.mesh(p,None,f'outer low cover {edge}-{i}',vertices,faces,'sandbag','perimeter')


def _fort(k):
    p='fort';k.grounds(p)
    for i,(x,y,s) in enumerate([(-3560,-3120,1.05),(-2080,-3190,.96),(1900,-3180,1.08)]):k.tent(p,0,f'arrival tent {i}',x,y,s)
    k.mast(p,0,'arrival bare frame mast',-2850,-3270,.45)
    for i,(x,y) in enumerate([(-2740,-3110),(-1400,-3360),(2580,-3180)]):k.supply(p,0,f'arrival cases {i}',x,y,1.15)
    for i,(x,y) in enumerate([(x,y) for y in (-1480,1390,2800) for x in (-4380,-3080)]):k.tent(p,1,f'quartermaster tent {i}',x,y,.92,math.pi/2 if x<-3600 else -math.pi/2)
    k.mast(p,1,'warehouse relay mast',-4710,3250,.62)
    for i,(x,y) in enumerate([(-4050,-700),(-4150,2150),(-2900,3420)]):k.supply(p,1,f'warehouse pallets {i}',x,y,1.5)
    for i,(x,y) in enumerate([(3020,-1030),(3040,380)]):k.tent(p,2,f'communications annex tent {i}',x,y,.84,-math.pi/2)
    k.frame(p,2,'communications open service frame',3020,-300,(1.1,1.1,1.65))
    for i,(x,y) in enumerate([(-1970,3000),(80,3010),(1190,3010),(2290,3010),(3410,3010),(4420,3010), (4320,-1170),(4320,180),(4320,1500)]):
        k.tent(p,3,f'command compound tent {i}',x,y,.91 if x>4000 else .96,-math.pi/2 if y<2000 else 0)
    k.frame(p,3,'command flank open frame',4140,2300,1.35)
    for i,(x,y) in enumerate([(3350,3560),(4420,3520),(4720,-550)]):k.supply(p,3,f'command supplies {i}',x,y,1.3)
    k.perimeter(p)


def _frontbase(k):
    p='frontbase';k.grounds(p)
    for i,(x,y) in enumerate([(-2840,2490),(-1740,2460),(-640,2500),(2450,2480)]):k.tent(p,0,f'arrival support tent {i}',x,y,.9)
    k.asset(p,0,'arrival support motorhome','FRONTBASE RV','frontbase',3180,1720,1.)
    k.frame(p,0,'arrival open frame',3350,2350,1.0);k.mast(p,0,'arrival relay mast',-3410,2820,.5)
    for i,(x,y) in enumerate([(-1180,2920),(3300,2920)]):k.supply(p,0,f'arrival stores {i}',x,y,1.2)
    for i,(x,y) in enumerate([(-3520,-1100),(-2130,-990),(-3520,-500),(-2130,-130),(-3520,100),(-3520,700)]):
        k.tent(p,1,f'air defense tent {i}',x,y,.8,math.pi/2 if x<-2800 else -math.pi/2)
    for i,(x,y) in enumerate([(-2840,-1100),(-2840,-330),(-2840,480)]):k.asset(p,1,f'air defense Tigr {i}','Menghu_G05_R07','frontbase',x,y,1.,math.pi/2,search=900)
    k.frame(p,1,'air defense service frame',-2330,1810,.95)
    for i,(x,y) in enumerate([(-3100,-2580),(-2150,-2580),(-1200,-2580),(1100,-2580),(2180,-2580),(3200,-2580),(-2800,-1810),(2620,-1810)]):
        k.tent(p,2,f'armor district tent {i}',x,y,.79,math.pi if y<-2200 else 0)
    for i,(x,y) in enumerate([(-3120,-1990),(-1530,-1920),(3260,-1970)]):k.asset(p,2,f'armor park Rhino {i}','RHINO_R09','frontbase',x,y,.95,math.pi/2,search=900)
    k.frame(p,2,'armor frame left',-1100,-3030,1.08);k.frame(p,2,'armor frame right',1470,-3020,1.08)
    for i,(x,y) in enumerate([(2240,-1040),(3240,-1030),(2340,50),(3290,130),(3360,1010)]):
        k.tent(p,3,f'command extension tent {i}',x,y,.83,-math.pi/2)
    k.frame(p,3,'command supplies open frame',2050,850,1.1)
    for i,(x,y) in enumerate([(2020,-570),(3490,640),(1430,-870)]):k.supply(p,3,f'command stores {i}',x,y,1.15)
    k.perimeter(p)


def apply_military_multistage(scene,context):
    assert context['source_sha256']==SOURCE_SHA, 'Expected the preserved detail-v2 source'
    before={o.name:tuple(v for row in o.matrix_world for v in row) for o in scene.objects}
    k=MilitaryExpansion(scene)
    print('MILITARY_MULTISTAGE_PHASE fort',flush=True);_fort(k)
    print('MILITARY_MULTISTAGE_PHASE frontbase',flush=True);_frontbase(k)
    assert all(scene.objects.get(name) is not None and tuple(v for row in scene.objects[name].matrix_world for v in row)==matrix for name,matrix in before.items())
    subareas=[];places={}
    for p in k.new:
        existing_zone=2 if p=='fort' else 3
        for z in range(4):
            originals=k.original[p] if z==existing_zone else []
            objects=originals+k.zone_objects[p][z];bounds=_bounds(objects)
            subareas.append({'id':f'{p}-{z+1:02d}','placeId':p,'subStageIndex':z,'sourceBackground':f'flashswf/backgrounds/gk{21 if p=="fort" else 22}_{z+1}_BG.swf',
                             'label':LABELS[p][z],'worldBounds':{'min':bounds[0],'max':bounds[1]},
                             'worldCenter':[(a+b)/2 for a,b in zip(*bounds)],'coordinateSystem':'sourceXYZ',
                             'objects':[o.name for o in objects],'originalObjects':[o.name for o in originals],
                             'newObjects':[o.name for o in k.zone_objects[p][z]],
                             'status':'source-informed subarea observation; not a new game entry'})
        counts=collections.Counter();triangles=0
        for obj in k.new[p]:obj.data.calc_loop_triangles();triangles+=len(obj.data.loop_triangles);counts[obj['multistageRole']]+=1
        places[p]={'newObjects':len(k.new[p]),'newTriangles':triangles,'roles':dict(counts),
                   'worldBounds':_bounds(k.original[p]+k.new[p]),'allowedLocalHalfSize':list(HALF_SIZE[p]),
                   'terrainTriangles':k.ground_triangles[p],'terrainTrianglesOmittedForMainRoad':k.road_skips[p],
                   'originalObjectsPreserved':len(k.original[p]),'sharedObjects':[o.name for o in k.new[p] if not o.get('subareaId')]}
    return {'sourceSHA256':SOURCE_SHA,'places':places,'subareas':subareas,'addedObjects':sum(len(v) for v in k.new.values()),
            'hiddenOriginals':[],'originalTransformsUnchanged':True,'regionalRoadVertexSignature':k.road_signature,
            'structureClusters':k.clusters,'clearanceRelocations':k.moved,
            'scope':'Four display districts per existing place; source sequence retained; orientation/functions/connectors are proposed reconstruction; no new stage entry or permanent battle aftermath.'}
