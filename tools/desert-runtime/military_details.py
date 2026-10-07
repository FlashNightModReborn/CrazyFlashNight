"""Editable, source-informed candidate details for three existing military places.

The frozen source stays intact. Existing tent meshes/materials are copied into
explicit detail collections; only the diplomacy's named block placeholders are
hidden. Functional zoning and perimeter layout are proposed display composition,
not newly established geography or a literal inventory of a regiment.
"""
import math
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

SOURCE = 'a6242048e490c11d5e5c81edd6800fb6f231e2d71967c976d5f83016103da524'
TERRAIN = {'REGIONAL_TERRAIN_BASE_REGISTERED', 'REGIONAL_BASE_TERRAIN_COLLAR',
           'R28_fallen_broad_relief', 'R28_waste_broad_relief'}
GROUND = {'fort': 'court / open manoeuvre area',
          'frontbase': 'FB / ground / compacted open compound'}
SOURCE_FEATURES = {
    'fort': ['gk21_1..4: olive camouflage tents with open dark doors',
             'gray cases, black drums, hazard-edged stacks, open arched frames',
             'source Blend already contains four detailed tents and a lattice mast'],
    'frontbase': ['gk22_1..4: olive tents, communication masts, open frames and cases',
                  'gk22_1..2: white RV; gk22_2: Tigr; gk22_3: Rhino',
                  'battle-specific blood and casualties are not permanent geography'],
    'diplomacy': ['current map SWF exported linkage 123: three rows of olive tents',
                  'open tent doors, sandbags, gray cases and drums',
                  'Rhino, Tigr and Tesla stand behind tents in the 2D source'],
}


def _bounds(objects):
    points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    return [[min(p[a] for p in points) for a in range(3)],
            [max(p[a] for p in points) for a in range(3)]]


def _material(name, rgb):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    node = m.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (*rgb, 1)
    node.inputs['Roughness'].default_value = .9
    return m


class DetailKit:
    def __init__(self, scene, context):
        self.scene = scene
        self.audit = context['audit']
        self.layout = context['layout_data']
        self.new = {p: [] for p in SOURCE_FEATURES}
        self.hidden = []
        self.collections = {}
        self.frames = {}
        self.gates = {p: [] for p in SOURCE_FEATURES}
        self.assets = [o for o in scene.objects if o.type == 'MESH' and not o.hide_render]
        for p in self.new:
            name = 'LOCAL_DETAIL_' + p
            assert not bpy.data.collections.get(name), 'Detail collection already exists: ' + name
            c = bpy.data.collections.new(name)
            c['sourceSHA256'] = SOURCE
            c['evidenceStatus'] = 'source_informed_display_candidate'
            scene.collection.children.link(c)
            self.collections[p] = c
            if p in GROUND:
                m = bpy.data.objects[GROUND[p]].matrix_world
                self.frames[p] = (m.translation.x, m.translation.y, math.atan2(m[1][0], m[0][0]))
            else:
                self.frames[p] = (43000., 35000., math.atan2(1, 2))
        vertices, faces = [], []
        for o in self.assets:
            if o.name not in TERRAIN and o.name not in GROUND.values():
                continue
            o.data.calc_loop_triangles()
            n = len(vertices)
            vertices.extend(o.matrix_world @ v.co for v in o.data.vertices)
            faces.extend(tuple(n + a for a in t.vertices) for t in o.data.loop_triangles)
        self.bvh = BVHTree.FromPolygons(vertices, faces, all_triangles=True)
        self.mats = {
            'canvas': _material('MD olive canvas', (.18, .24, .075)),
            'canvas_light': _material('MD sunlit olive canvas', (.26, .31, .11)),
            'metal': _material('MD weathered gray metal', (.30, .33, .31)),
            'dark': _material('MD dark framing and drums', (.085, .095, .083)),
            'sandbag': _material('MD muted earth sandbags', (.20, .145, .09)),
            'case': _material('MD pale gray supply cases', (.47, .49, .45)),
            'stripe': _material('MD faded hazard ochre', (.58, .46, .12)),
        }

    def xy(self, p, x, y):
        ox, oy, a = self.frames[p]
        return ox + math.cos(a)*x - math.sin(a)*y, oy + math.sin(a)*x + math.cos(a)*y

    def height(self, x, y):
        q = self.bvh.ray_cast(Vector((x, y, 20000)), Vector((0, 0, -1)), 40000)[0]
        assert q is not None, f'No terrain under military detail at {x}, {y}'
        return q.z

    def point(self, p, x, y, z=0):
        x, y = self.xy(p, x, y)
        return (x, y, self.height(x, y) + z)

    def register(self, p, o, source=None):
        o['placeId'] = p
        o['runtimeForceDirectionalLight'] = True
        o['sourceSHA256'] = SOURCE
        o['detailEvidence'] = 'source_informed_display_candidate'
        if source:
            o['detailSourceObject'] = source
        self.collections[p].objects.link(o)
        self.new[p].append(o)
        return o

    def mesh(self, p, name, vertices, faces, mat):
        data = bpy.data.meshes.new('MD ' + name)
        data.from_pydata(vertices, [], faces)
        data.update()
        data.materials.append(self.mats[mat])
        o = bpy.data.objects.new('MD ' + p + ' / ' + name, data)
        return self.register(p, o)

    def box(self, p, name, x, y, w, d, h, mat, z=0, yaw=0):
        a = self.frames[p][2] + yaw
        cx, cy = self.xy(p, x, y)
        footprint = [(cx + math.cos(a)*u - math.sin(a)*v,
                      cy + math.sin(a)*u + math.cos(a)*v)
                     for u, v in [(-w/2, -d/2), (w/2, -d/2), (w/2, d/2), (-w/2, d/2)]]
        bottom = min(self.height(*q) for q in footprint) + z
        verts = [(u, v, bottom+k) for k in (0, h) for u, v in footprint]
        return self.mesh(p, name, verts, [(0,3,2,1),(4,5,6,7),(0,1,5,4),
                         (1,2,6,5),(2,3,7,6),(3,0,4,7)], mat)

    def beam(self, p, name, a, b, width, mat):
        a, b = Vector(a), Vector(b)
        axis = (b-a).normalized()
        cross = axis.cross(Vector((0, 0, 1)))
        if cross.length < .01:
            cross = axis.cross(Vector((0, 1, 0)))
        u = cross.normalized()*width/2
        v = axis.cross(u).normalized()*width/2
        vertices = [tuple(q+s*u+t*v) for q in (a,b) for s,t in [(-1,-1),(1,-1),(1,1),(-1,1)]]
        return self.mesh(p, name, vertices, [(0,3,2,1),(4,5,6,7),(0,1,5,4),
                         (1,2,6,5),(2,3,7,6),(3,0,4,7)], mat)

    def clone_tent(self, p, name, x, y, scale=1, yaw=0):
        prefix = 'SA_FORT_TENT_18'
        src = [o for o in self.assets if o.name.startswith(prefix + ' /')]
        assert len(src) == 50, 'Expected complete, detailed source tent components'
        lo, hi = _bounds(src)
        center = Vector(((lo[0]+hi[0])/2, (lo[1]+hi[1])/2, lo[2]))
        target = Vector(self.point(p, x, y, 8))
        angle = self.frames[p][2] - self.frames['fort'][2] + yaw
        delta = Matrix.Translation(target) @ Matrix.Rotation(angle, 4, 'Z') @ Matrix.Scale(scale, 4) @ Matrix.Translation(-center)
        for original in src:
            o = bpy.data.objects.new('MD ' + p + ' / ' + name + ' / ' + original.name.split(' / ',1)[-1], original.data.copy())
            o.matrix_world = delta @ original.matrix_world
            self.register(p, o, original.name)

    def canopy(self, p, name, x, y, w, d, height):
        # Open sides, a segmented pitched cloth roof and exposed cross frames.
        for side in (-1, 1):
            for i in range(3):
                u = x + (i/2-.5)*w
                self.beam(p, name+' post', self.point(p,u,y+side*d/2),
                          self.point(p,u,y+side*d/2,height), 18, 'metal')
        for i in range(5):
            u = x + (i/4-.5)*w
            a, b, c = self.point(p,u,y-d/2,height), self.point(p,u,y,height+95), self.point(p,u,y+d/2,height)
            self.beam(p,name+' roof rib',a,b,13,'metal')
            self.beam(p,name+' roof rib',b,c,13,'metal')
        for side in (-1,1):
            v = [self.point(p,u,y+t,height+(95 if t==0 else 0)+8)
                 for u,t in [(x-w/2,0),(x+w/2,0),(x+w/2,side*d/2),(x-w/2,side*d/2)]]
            # One upward face avoids coincident front/back triangles acquiring
            # different baked directional colors in the runtime exporter.
            self.mesh(p,name+' canvas slope',v,[(3,2,1,0)] if side<0 else [(0,1,2,3)],
                      'canvas_light' if side<0 else 'canvas')
        self.box(p,name+' work bench',x-w*.28,y,w*.25,95,95,'metal')
        self.box(p,name+' stacked cases',x+w*.25,y+40,w*.2,145,135,'case')

    def cases(self,p,name,x,y,scale=1):
        for i in range(3):
            self.box(p,name+' lower case',x+(i-1)*100*scale,y,94*scale,145*scale,58*scale,'case')
            self.box(p,name+' lid',x+(i-1)*100*scale,y,99*scale,150*scale,10*scale,'metal',z=58*scale)
        self.box(p,name+' upper crate',x,y+12,170*scale,125*scale,75*scale,'metal',z=68*scale)
        for k in (-1,1):
            self.box(p,name+' hazard band',x+k*56*scale,y-54*scale,24*scale,9*scale,38*scale,'stripe',z=84*scale)

    def sandbags(self, p, name, a, b, layers=2, width=83):
        length=math.dist(a,b);count=max(1,round(length/125));dx=(b[0]-a[0])/count;dy=(b[1]-a[1])/count
        yaw=math.atan2(dy,dx)
        for level in range(layers):
            for i in range(count):
                # Each bag has a chamfered footprint, deliberately broad enough
                # to read as earth-filled cover at overview zoom.
                stagger=.16 if level%2 else -.16
                x=a[0]+(i+.5+stagger)*dx; y=a[1]+(i+.5+stagger)*dy
                w=length/count-5;d=width;h=35
                corners=[(-w/2+12,-d/2),(w/2-12,-d/2),(w/2,-d/2+13),(w/2,d/2-13),
                         (w/2-12,d/2),(-w/2+12,d/2),(-w/2,d/2-13),(-w/2,-d/2+13)]
                verts=[]
                wx,wy=self.xy(p,x,y);angle=self.frames[p][2]+yaw
                z=self.height(wx,wy)+level*32+5
                for dz in (0,h):
                    for u,v in corners:verts.append((wx+u*math.cos(angle)-v*math.sin(angle),wy+u*math.sin(angle)+v*math.cos(angle),z+dz))
                faces=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
                self.mesh(p,name+f' bag {level}-{i}',verts,faces,'sandbag')

    def perimeter(self,p,hx,hy,layer=2):
        # Keep current regional approach centerlines open at the inherited edge.
        directions=[]
        lookup={a['id']:a['xy'] for a in self.layout['places']}
        origin=lookup[p]
        for route in self.layout['routes']:
            points=route['points']
            for index in [0,len(points)-1]:
                if points[index]!=p:continue
                neighbor=points[1 if index==0 else -2]
                xy=lookup[neighbor] if isinstance(neighbor,str) else neighbor
                dx=(xy[0]-origin[0])*1000;dy=(xy[1]-origin[1])*1000;a=self.frames[p][2]
                u=math.cos(a)*dx+math.sin(a)*dy;v=-math.sin(a)*dx+math.cos(a)*dy
                t=min(hx/abs(u) if u else 1e9,hy/abs(v) if v else 1e9)
                directions.append((u*t,v*t,route['id']))
        if not directions:directions=[(0,-hy,'existing local access')]
        self.gates[p]=[{'localXY':[round(x,3),round(y,3)],'route':name,'clearWidth':600 if p!='diplomacy' else 400} for x,y,name in directions]
        corners=[(-hx,-hy),(hx,-hy),(hx,hy),(-hx,hy)]
        for a,b in zip(corners,corners[1:]+corners[:1]):
            length=math.dist(a,b);steps=max(1,round(length/250))
            for i in range(steps):
                u=(i+.5)/steps;x=a[0]+u*(b[0]-a[0]);y=a[1]+u*(b[1]-a[1])
                clearance=450 if p!='diplomacy' else 280
                if any(math.hypot(x-gx,y-gy)<clearance for gx,gy,_ in directions):continue
                # Many bags share one short segment semantically, still editable.
                d=.42/steps
                self.sandbags(p,'perimeter cover', (a[0]+(u-d)*(b[0]-a[0]),a[1]+(u-d)*(b[1]-a[1])),
                              (a[0]+(u+d)*(b[0]-a[0]),a[1]+(u+d)*(b[1]-a[1])),layer,72)

    def hide(self,names):
        for name in names:
            o=bpy.data.objects.get(name)
            assert o is not None, 'Missing explicit diplomacy placeholder: '+name
            o.hide_render=True
            o['detailReplacementReason']='Replaced primitive diplomacy block with source-informed tent camp'
            self.hidden.append(name)


def apply_military_details(scene, context):
    assert context['source_sha256']==SOURCE
    assert context['audit']['sourceSHA256']==SOURCE
    kit=DetailKit(scene,context)
    kit.clone_tent('fort','inner barracks A',712.559,452.493,.88)
    kit.clone_tent('fort','north barracks B',660,1290,.94)
    kit.clone_tent('fort','southern barracks',900,-1200,.92,math.pi)
    kit.canopy('fort','open maintenance shelter',-1680,-550,930,460,260)
    kit.cases('fort','supply group',-1050,-1000,1.25)
    kit.perimeter('fort',2360,1770,3)
    kit.sandbags('fort','command cover',(1160,720),(1470,720),2)

    kit.canopy('frontbase','mobile repair shelter',-820,1080,830,350,230)
    kit.cases('frontbase','temporary logistics',-366.177,685.699,.84)
    kit.perimeter('frontbase',1580,1180,2)
    kit.sandbags('frontbase','tower equipment cover',(1180,750),(1440,750),2)

    kit.hide(['diplomacy_light_8','diplomacy_roof_9','diplomacy_concrete_10','diplomacy_roof_11'])
    for x,label in [(-550,'liaison tent'),(0,'reception tent'),(550,'officer tent')]:
        kit.clone_tent('diplomacy',label,x,350,.57)
    for x,label in [(-585,'guard shelter'),(575,'stores shelter')]:
        kit.clone_tent('diplomacy',label,x,-210,.43,math.pi/2 if x<0 else -math.pi/2)
    kit.cases('diplomacy','camp supply cases',-280,290,.7)
    kit.cases('diplomacy','reception supply cases',285,300,.7)
    kit.sandbags('diplomacy','entrance left',(-528.885,-561.459),(-308.885,-561.459),2,62)
    kit.sandbags('diplomacy','entrance right',(308.885,-572.639),(528.885,-572.639),2,62)

    report={'places':{},'addedObjects':sum(len(v) for v in kit.new.values()),
            'hiddenOriginals':kit.hidden,'sourceFeatures':SOURCE_FEATURES,
            'proposedDetails':{'fort':['additional barracks','open maintenance and supply zone','low perimeter with route gates'],
                               'frontbase':['mobile repair shelter','temporary logistics beside the command court','low protective perimeter'],
                               'diplomacy':['small olive tent camp replacing four primitive blocks','reception court','sandbag entrance']}}
    for p,objects in kit.new.items():
        lo,hi=_bounds(objects);oldlo,oldhi=context['audit']['groups'][p]['sourceBounds']
        assert all(lo[a]>=oldlo[a]-.01 and hi[a]<=oldhi[a]+.01 for a in (0,1)), f'Detail extends inherited horizontal range: {p}, {lo}, {hi}'
        tris=0
        for o in objects:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
        report['places'][p]={'addedObjects':len(objects),'addedTriangles':tris,'addedBounds':[lo,hi],
                             'horizontalRangePreserved':True,'routeGates':kit.gates[p],
                             'sourceFeatures':SOURCE_FEATURES[p],
                             'proposedDetails':report['proposedDetails'][p]}
    return report
