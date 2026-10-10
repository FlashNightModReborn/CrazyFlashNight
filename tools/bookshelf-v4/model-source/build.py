import bpy, math, json, os, sys
from mathutils import Vector
ROOT=os.path.dirname(os.path.abspath(__file__))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
PREVIEW='--preview' in args
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene
sc.render.engine='CYCLES';sc.cycles.samples=12 if PREVIEW else 160
sc.cycles.use_denoising=False
sc.render.resolution_x=1280 if PREVIEW else 1600;sc.render.resolution_y=720 if PREVIEW else 900;sc.render.resolution_percentage=100
sc.world.color=(.14,.17,.21)
sc.view_settings.view_transform='AgX'
def mat(n,c,metal=0,rough=.5):
 if n in bpy.data.materials:return bpy.data.materials[n]
 m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;return m
steel=mat('Cold grey | powder coated steel',(.17,.20,.24),.5,.37); edge=mat('Machined rim',(.35,.39,.43),.65,.28);back=mat('Recess charcoal',(.063,.075,.088),.15,.7);black=mat('Collection charcoal cloth',(.021,.024,.03),.12,.54);paper=mat('Ivory paper',(.76,.74,.67),0,.83);folder=mat('Archive slate paper',(.22,.28,.32),0,.8);label=mat('Label stock',(.66,.69,.67),0,.68)
def empty(n,loc=(0,0,0),parent=None,**props):
 o=bpy.data.objects.new(n,None);sc.collection.objects.link(o);o.location=loc;o.parent=parent
 for k,v in props.items():o[k]=v
 return o
root=empty('CF7_BOOKSHELF_ROOT',entryKey='bookshelf')
def cube(n,loc,size,m,parent=root,bevel=.025):
 bpy.ops.mesh.primitive_cube_add(size=1);o=bpy.context.object;o.name=n;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.location=loc;o.parent=parent;o.data.materials.append(m)
 if bevel:b=o.modifiers.new('Micro hard edge','BEVEL');b.width=bevel;b.segments=2;o.modifiers.new('Corner normals','WEIGHTED_NORMAL')
 return o
texm={}
def texture(n):
 if n in texm:return texm[n]
 m=mat('Texture | '+n,(1,1,1),0,.53);p=m.node_tree.nodes.get('Principled BSDF');t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(os.path.join(ROOT,'textures',n+'.png'));m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color']);texm[n]=m;return m
# face lies in XZ plane, facing front -Y

def face(n,x,y,z,w,h,m,parent):
 mesh=bpy.data.meshes.new(n);mesh.from_pydata([(-w/2,0,-h/2),(w/2,0,-h/2),(w/2,0,h/2),(-w/2,0,h/2)],[],[(0,1,2,3)]);mesh.uv_layers.new()
 for loop,uv in zip(mesh.uv_layers.active.data,[(0,0),(1,0),(1,1),(0,1)]):loop.uv=uv
 o=bpy.data.objects.new(n,mesh);sc.collection.objects.link(o);o.parent=parent;o.location=(x,y,z);o.data.materials.append(m);return o
# 23.5 wide; clear heights 6.80, maximum book/case 6.55
W=23.5;D=4.65;T=.30
for x in [-W/2,W/2]:cube('Cabinet side', (x,0,8.48),(T,D,16.96),steel)
for z in [.15,2.80,9.90,17.00]:cube('Structural shelf',(0,0,z),(W,T*0+D,T),steel)
cube('Recessed back',(0,2.22,8.55),(W,.16,16.9),back)
for z in [2.8,9.9,17.0]:cube('Shelf leading lip',(0,-2.36,z-.01),(W,.12,.30),edge)
for x in [-10.6,10.6]:cube('Cabinet foot',(x,0,-.14),(1.2,3.8,.28),black)
# Books keep stable centers and small yaw; blank covers are honest material only
books=[('dust',-8.5,10.05,1.23,6.42,3.75,10,(.13,.15,.16)),('babylon',-6.36,10.05,1.30,6.50,3.9,10,(.025,.045,.23)),('guardian',-4.17,10.05,1.38,6.55,3.80,10,(.66,.69,.70)),('sail-twins',-8.5,2.95,1.24,6.32,3.8,10,(.25,.28,.29))]
book_roots=[]
for key,x,z,w,h,d,yaw,col in books:
 br=empty('BOOK_'+key,(x,-.1,z),root,entryKey=key,kind='work',pullAxis='-Y',pullMax=2.5);br.rotation_euler.z=math.radians(yaw);book_roots.append(br)
 cover=mat(key+' cover',col,0,.66)
 cube(key+' page block',(0,.06,h/2),(w-.12,d-.18,h-.12),paper,br,.018)
 for xx in [-w/2+.035,w/2-.035]:cube(key+' hard cover',(xx,0,h/2),(.07,d,h),cover,br,.018)
 cube(key+' rounded spine',(0,-d/2+.07,h/2),(w,.14,h),cover,br,.04)
 face(key+' original spine',0,-d/2-.008,h/2,w*.98,h*.99,texture('spine-'+key),br)
 for i in range(18):cube(key+' page seam',(0,.1,.15+i*(h-.28)/18),(w-.14,d-.15,.007),mat('Paper seams',(.54,.53,.48)),br,0)
# Minimal movable bookends, visible empty space carries no fake entries
for x,z in [(-9.75,10.05),(-2.80,10.05),(-9.75,2.95),(-6.7,2.95)]:
 er=empty('BOOKEND',(x,0,z),root,kind='movableBookend');cube('Bookend base',(.24,0,.04),(.62,3.6,.08),edge,er);cube('Bookend upright',(0,.4,1.15),(.09,2.7,2.3),steel,er)
# Six slim boxes in a physical charcoal slipcase; front is original collection graphic
cr=empty('COLLECTION_CF1_6',(3.0,-.05,2.95),root,entryKey='crazy-flasher',kind='collection',pullAxis='-Y',pullMax=2.6)
cw=5.65;ch=6.55;cd=3.95
for x in [-cw/2+.10,cw/2-.10]:cube('Slipcase side',(x,0,ch/2),(.20,cd,ch),black,cr)
for z in [.10,ch-.10]:cube('Slipcase shell',(0,0,z),(cw,cd,.20),black,cr)
cube('Slipcase back',(0,cd/2-.1,ch/2),(cw,.20,ch),black,cr)
# top fascia carries original collection identity, lower opening reveals labeled box spines
cube('Collection identity fascia',(0,-cd/2-.025,5.75),(cw,.12,1.45),black,cr)
face('Original collection mark',0,-cd/2-.09,5.75,2.2,1.43,texture('box-crazy-flasher'),cr)
for i in range(6):
 r=empty('DISC_CF'+str(i+1),(-2.21+i*.88,0,.23),cr,entryKey='cf'+str(i+1),kind='disc',pullAxis='-Y',pullMax=2.3)
 cube('CF'+str(i+1)+' slim case',(0,0,2.36),(.80,3.70,4.72),black,r,.04)
 face('CF'+str(i+1)+' identified spine',0,-1.86,2.36,.70,4.46,texture('case-spine-cf'+str(i+1)),r)
 art=face('CF'+str(i+1)+' original cover',.405,0,2.36,3.15,4.46,texture('disc-cf'+str(i+1)),r);art.rotation_euler.z=math.pi/2
# Archive bank: three shortcuts + all-archives drawer. Labels generated externally as honest demo data.
archive=empty('ARCHIVE_BANK',(0,0,0),root,kind='characterArchive',demoData=True)
for i,(x,k) in enumerate([(-8.55,'current'),(-3.15,'recent02'),(2.25,'recent03')]):
 r=empty('ARCHIVE_SHORTCUT_'+k,(x,-.05,.38),archive,entryKey='archive:'+k,kind='archiveShortcut',demoData=True)
 cube('Shortcut compartment bottom',(0,0,.05),(5.05,4.1,.10),back,r)
 cube('Shortcut compartment back',(0,1.99,1.02),(5.05,.12,2.03),back,r)
 for sx in [-2.47,2.47]:cube('Shortcut compartment side',(sx,0,1.02),(.11,4.1,2.03),back,r)
 cube('Physical character folder',(0,-1.94,1.10),(4.80,.13,1.90),folder,r)
 face('Character folder label',0,-2.015,1.15,4.2,.90,texture('archive-'+k),r)
 cube('Pull tab',(0,-2.18,.40),(1.25,.34,.13),edge,r)
drawer=empty('ARCHIVE_ALL_DRAWER',(8.2,0,.39),archive,entryKey='archive:all',kind='archiveDirectory',pullAxis='-Y',pullMax=3.15,demoData=True)
cube('Drawer floor',(0,0,.07),(5.0,4.12,.14),steel,drawer)
for x in [-2.45,2.45]:cube('Drawer side',(x,0,.95),(.10,4.12,1.8),steel,drawer)
cube('Drawer back',(0,2.01,.95),(5.0,.10,1.8),steel,drawer)
cube('All archives front',(0,-2.08,1.02),(5.1,.18,2.03),steel,drawer)
face('All archives label',0,-2.18,1.3,4.6,.74,texture('archive-all'),drawer)
cube('All archives handle',(0,-2.40,.52),(1.95,.42,.17),edge,drawer)
for i in range(5):
 f=empty('DIRECTORY_FOLDER_'+str(i+1),(0,-1.4+i*.63,.15),drawer,kind='demoFolder',demoData=True)
 cube('Directory folder',(0,0,.81),(4.50,.10,1.62),folder,f)
 cube('Folder top tab',(-1.1+(i%3)*.85,0,1.71),(.75,.10,.25),label,f)
 face('Demo directory label',0,-.056,1.02,3.92,.97,texture('archive-demo'+str(i+1).zfill(2)),f)
# rails fixed to archive bank
for x in [5.55,10.85]:cube('Fixed drawer runner',(x,0,.57),(.10,4.30,.12),edge,archive)
# studio
floor=mat('Backdrop',(.035,.047,.064),0,.65);cube('Studio floor',(0,0,-.42),(200,200,.2),floor,None,0)
def area(n,loc,power,size,color,target=(0,0,8)):
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=n;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.data.color=color;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Key softbox',(-12,-17,26),3300,13,(.82,.89,1));area('Front fill',(10,-16,14),2100,12,(1,.95,.88));area('Top edge',(4,4,26),3100,10,(.61,.76,1))
bpy.ops.object.camera_add(location=(23*-0.055,-37,22.2));cam=bpy.context.object;cam.name='CAMERA_OVERVIEW';cam.rotation_euler=(Vector((0,0,8.3))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=33.4;sc.camera=cam
sc.render.image_settings.file_format='PNG';sc.render.filepath=os.path.join(ROOT,'layout-preview.png' if PREVIEW else 'overview.png')
sys.path.insert(0,ROOT)
import states
states.remember_rest()
for o in sc.objects:
 if 'pullAxis' in o:
  o['authoringCoordinateSystem']='Blender Z-up'
  o['pullDirectionGltfParent']=[0.0,0.0,1.0]
  o['restTranslationGltf']=[o.location.x,o.location.z,-o.location.y]
# Preserve external textures in package and pack blend for standalone opening.
for image in bpy.data.images:
 if image.source=='FILE':image.pack()
if not PREVIEW:
 bpy.ops.object.select_all(action='DESELECT')
 def select_tree(o):
  o.select_set(True)
  for c in o.children:select_tree(c)
 select_tree(root)
 bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,'bookshelf-v3.glb'),export_format='GLB',use_selection=True,export_extras=True,export_apply=True,export_animations=False)
 nodes=[{'name':o.name,'parent':o.parent.name if o.parent else None,'entryKey':o.get('entryKey'),'kind':o.get('kind'),'restLocation':list(o.get('restLocation',o.location)),'pullAxis':o.get('pullAxis'),'pullMax':o.get('pullMax')} for o in [root]+list(root.children_recursive) if o.type=='EMPTY']
 json.dump(nodes,open(os.path.join(ROOT,'semantic-nodes.json'),'w'),ensure_ascii=False,indent=2)
 json.dump({'blenderVersion':bpy.app.version_string,'meshObjects':sum(o.type=='MESH' for o in root.children_recursive),'verticesBeforeModifiers':sum(len(o.data.vertices) for o in root.children_recursive if o.type=='MESH'),'materials':len(bpy.data.materials),'textures':len([i for i in bpy.data.images if i.source=='FILE']),'animationClips':0,'lighting':'Offline studio lights excluded from GLB; PBR, not baked/unlit','demoData':True},open(os.path.join(ROOT,'modelstats.json'),'w'),indent=2)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'bookshelf-v3.blend'))
if '--no-render' not in args:bpy.ops.render.render(write_still=True)
if not PREVIEW and '--no-render' not in args:
 states.apply_state('archives-open')
 cam.location=(10.2,-15.5,7.6);cam.rotation_euler=(Vector((5.3,-.7,1.75))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=14.4
 sc.render.filepath=os.path.join(ROOT,'archives-open.png');bpy.ops.render.render(write_still=True)
 states.apply_state('disc-pulled')
 cam.location=(11.4,-17,12.8);cam.rotation_euler=(Vector((3,-1.0,6.1))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=13.7
 sc.render.filepath=os.path.join(ROOT,'collection-pulled.png');bpy.ops.render.render(write_still=True)
 states.reset()

