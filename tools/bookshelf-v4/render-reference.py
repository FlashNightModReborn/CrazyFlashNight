"""OFFLINE v4 visual references; never a browser/game capture.

Input: immutable v3 Blender assets + JSON snapshots from actual layoutFor().
Output: references/ only. Does not save or modify the source .blend or web files.

Usage:
  python3 render-reference.py --snapshot
  blender -b model-source/bookshelf-v3.blend -t 8 --python render-reference.py
  python3 render-reference.py --compose

The panel compositor is a documented Pillow approximation. Blender studio
lighting, orthographic framing, and selected-object presentation are offline.
"""
from pathlib import Path
import sys, json, math, subprocess, hashlib
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'references'; OUT.mkdir(exist_ok=True)
SOURCE=ROOT/'model-source/bookshelf-v3.blend'
BANNER='离线效果参考 · 非浏览器截图'
VIEWS=[
 {'key':'01-wide-overview','title':'宽屏陈列','panel':[1024,576],'canvas':[802,481],'canvasOrigin':[221,59],'layout':'wide','state':'overview'},
 {'key':'02-narrow-overview','title':'窄屏重排','panel':[640,760],'canvas':[418,665],'canvasOrigin':[221,59],'layout':'narrow','state':'overview'},
 {'key':'05-collapsed-compact','title':'收起目录后回总览 · 中档三层','panel':[640,760],'canvas':[638,665],'canvasOrigin':[1,59],'layout':'medium','state':'overview','sidebarCollapsed':True},
 {'key':'03-book-inspection','title':'书本抽出后旋转','panel':[1024,576],'canvas':[802,481],'canvasOrigin':[221,59],'layout':'wide','state':'inspect'},
 {'key':'04-archive-drawer','title':'全部档案 · 抽屉展开','panel':[1024,576],'canvas':[802,481],'canvasOrigin':[221,59],'layout':'wide','state':'drawer'},
]

def compose():
 from PIL import Image,ImageDraw,ImageFont
 S=2; C={'surface':'#101923','raised':'#1a2732','line':'#354655','muted':'#91a3b2','text':'#e0e7ed','accent':'#c8c6ab','blue':'#8dc9ed'}
 regular='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';bold='/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
 def font(n,b=False):return ImageFont.truetype(bold if b else regular,round(n*S))
 for v in VIEWS:
  W,H=v['panel'];cw,ch=v['canvas'];ox,oy=v['canvasOrigin'];im=Image.new('RGB',(W*S,H*S),C['surface']);d=ImageDraw.Draw(im)
  def rect(box,fill=None,outline=None,width=1,radius=0):
   box=tuple(round(a*S) for a in box)
   if radius:d.rounded_rectangle(box,radius=radius*S,fill=C.get(fill,fill),outline=C.get(outline,outline),width=width*S)
   else:d.rectangle(box,fill=C.get(fill,fill),outline=C.get(outline,outline),width=width*S)
  def text(x,y,t,n=12,c='text',b=False):d.text((round(x*S),round(y*S)),t,font=font(n,b),fill=C.get(c,c),anchor='lt')
  raw=Image.open(OUT/(v['key']+'-canvas.png')).convert('RGB').resize((cw*S,ch*S),Image.Resampling.LANCZOS);im.paste(raw,(ox*S,oy*S))
  rect((0,0,W-1,H-1),outline='line');rect((1,58,W-2,58),'line');rect((1,H-36,W-2,H-36),'line')
  collapsed=v.get('sidebarCollapsed',False);tx=62 if collapsed else 21
  text(tx,9,'CF7  /  基地收藏室',10,'accent');text(tx,25,'基地收藏室',20,'text',True)
  if collapsed:rect((12,18,52,45),'raised','line',radius=3);text(18,24,'目录',12,'accent')
  bx=582 if W>700 else 224
  rect((bx,14,W-59,44),'#392f20','#8f7850',radius=3);text(bx+12,21,BANNER,16 if W>700 else 13,'#f2d8a1',True);text(W-37,15,'×',25,'muted')
  if not collapsed:
   rect((220,59,220,H-37),'line')
   def entry(y,title,sub,active=False):
    rect((14,y,206,y+58),'raised',radius=3);rect((14,y,16,y+58),'accent' if active else 'line');text(27,y+9,title,16,'text',active);text(27,y+35,sub,11,'muted')
   entry(76,'置物架总览','冷灰钢架 · 模块化陈列',v['state']=='overview')
   text(20,153,'藏书',11,'muted')
   entries=[('尘都诡谈','原有实体书'),('光明巴比伦','原有实体书'),('守护之力','原有实体书'),('风帆双子','原有实体书'),('闪客快打','CF1–6 合集')]
   for i,(title,sub) in enumerate(entries):entry(175+i*66,title,sub,v['state']=='inspect' and i==0)
   rect((212,72,216,524),'raised',radius=2);rect((213,74,215,418),'#5e7485',radius=1)
  # Canvas annotations are visual reference captions, not DOM controls or evidence of interaction.
  text(ox+18,oy+17,v['title'],14,'text',True)
  if collapsed:rect((W-102,oy+12,W-16,oy+45),'raised','line',radius=3);text(W-89,oy+21,'回总览',12,'accent')
  note={'overview':['四本作品 · 一套合集','角色档案为通用演示数据'],'inspect':['《尘都诡谈》柜外检视','静帧：抽出后旋转姿态'],'drawer':['目录抽屉打开','通用演示档案 · 无真实存档']}[v['state']]
  if not collapsed:text(20,508,note[0],10,'muted');text(20,524,note[1],10,'muted')
  else:text(ox+18,oy+ch-24,'三层作品区 · 四本作品 / 一套合集 · 实体书不缩放',11,'muted')
  text(18,H-25,'离线 Blender 几何渲染 + 排版合成',11,'muted')
  if W>700:text(702,H-25,'仅视觉参考 · 实際浏览器表现待核验'.replace('実際','实际'),11,'accent')
  else:text(379,H-25,'收目录后回总览 · 非实机' if collapsed else '窄屏重排 · 非实机',11,'accent')
  im.save(OUT/(v['key']+'-2x.png'));im.resize((W,H),Image.Resampling.LANCZOS).save(OUT/(v['key']+'.png'))
 print('Composed '+str(len(VIEWS))+' OFFLINE reference panels.')

if '--compose' in sys.argv:
 compose();sys.exit(0)

if '--snapshot' in sys.argv:
 # Snapshot pure layout data from the exact web candidate module, not a reimplementation.
 module=ROOT.parents[1]/'launcher/web/modules/bookshelf/shelf/layout-core.mjs'
 js="import {layoutFor} from '"+module.as_uri()+"'; console.log(JSON.stringify({wide:layoutFor('wide'),medium:layoutFor('medium'),narrow:layoutFor('narrow')},null,2));"
 result=subprocess.run(['node','--input-type=module','-e',js],check=True,text=True,capture_output=True)
 layouts=json.loads(result.stdout);(OUT/'actual-layouts.json').write_text(json.dumps(layouts,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
 (OUT/'layout-source.sha256').write_text(hashlib.sha256(module.read_bytes()).hexdigest()+'  launcher/web/modules/bookshelf/shelf/layout-core.mjs\n',encoding='utf-8',newline='\n')
 print('Captured layoutFor() outputs from',module);sys.exit(0)

import bpy
from mathutils import Vector, Euler, Matrix
from bpy_extras.object_utils import world_to_camera_view
sc=bpy.context.scene
root=bpy.data.objects['CF7_BOOKSHELF_ROOT']
layouts=json.loads((OUT/'actual-layouts.json').read_text())

def to_blender(p):return Vector((p[0],-p[2],p[1]))
def remove_tree(o):
 for c in list(o.children):remove_tree(c)
 bpy.data.objects.remove(o,do_unlink=True)
# Remove only the source fixed structure and bookends. Physical content stays unchanged.
for o in list(root.children):
 if o.type=='MESH' or o.name.startswith('BOOKEND'):remove_tree(o)
for o in list(bpy.data.objects):
 if o.name.startswith('Fixed drawer runner'):remove_tree(o)
for o in root.children_recursive:
 if 'restLocation' in o:o.location=o['restLocation']
root.location=(0,0,0)
root.rotation_euler=(0,0,0)
root.scale=(1,1,1)
source_transforms={o.name:(o.location.copy(),o.rotation_euler.copy(),o.scale.copy()) for o in root.children_recursive}
steel=bpy.data.materials['Cold grey | powder coated steel'];edge=bpy.data.materials['Machined rim'];back=bpy.data.materials['Recess charcoal']
boards=[]
floor=bpy.data.objects.get('Studio floor')
if floor:floor.dimensions=(2000,2000,.2)

def setup_layout(layout):
 global boards
 H=layout['height'];lighting_scale=max(1,H/17)
 light_specs=[('Key softbox',(-12,-17,H+9),3300,13,(0,0,H*.55)),('Front fill',(10,-16,H*.65),2100,12,(0,0,H*.40)),('Top edge',(4,4,H+9),3100,10,(0,0,H*.65))]
 for name,loc,power,size,target in light_specs:
  lamp=bpy.data.objects.get(name)
  if lamp:
   lamp.location=loc;lamp.data.energy=power*lighting_scale;lamp.data.size=size*lighting_scale**.6;lamp.rotation_euler=(Vector(target)-lamp.location).to_track_quat('-Z','Y').to_euler()
 for o in boards:
  if o.name in bpy.data.objects:bpy.data.objects.remove(o,do_unlink=True)
 boards=[]
 for name,(loc,rot,scale) in source_transforms.items():
  o=bpy.data.objects.get(name)
  if o:o.location=loc;o.rotation_euler=rot;o.scale=scale
 for name,p in layout['placements'].items():
  o=bpy.data.objects.get(name)
  if not o:raise ValueError('Layout semantic node is missing from source: '+name)
  o.location=to_blender(p)
 for b in layout['boards']:
  bpy.ops.mesh.primitive_cube_add(size=1);o=bpy.context.object;o.name='V4_'+b['name'];o.parent=root
  o.location=to_blender(b['position']);w,h,d=b['size'];o.dimensions=(w,d,h);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
  kind=b.get('kind','steel').lower();m=back if any(k in kind for k in ['back','recess']) else edge if any(k in kind for k in ['lip','rim','rail','edge','runner']) else bpy.data.materials['Collection charcoal cloth'] if kind=='foot' else steel
  o.data.materials.append(m);be=o.modifiers.new('Offline micro edge','BEVEL');be.width=.025;be.segments=2;o.modifiers.new('Offline weighted normals','WEIGHTED_NORMAL');boards.append(o)
 bpy.context.view_layer.update()

def mesh_points(objects):
 return [o.matrix_world@Vector(c) for o in objects if o.type=='MESH' and not o.hide_render for c in o.bound_box]

def fit_camera(objects,cw,ch,pitch=.23,yaw=0,padding=1.17,zoom=1):
 cam=sc.camera
 points=mesh_points(objects);lo=Vector(tuple(min(p[i] for p in points) for i in range(3)));hi=Vector(tuple(max(p[i] for p in points) for i in range(3)));center=(lo+hi)/2
 direction=Vector((math.sin(yaw)*math.cos(pitch),-math.cos(yaw)*math.cos(pitch),math.sin(pitch)))
 cam.location=center+direction*80;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=50
 bpy.context.view_layer.update()
 matrix=cam.matrix_world.inverted();ps=[matrix@p for p in points];x0=min(p.x for p in ps);x1=max(p.x for p in ps);y0=min(p.y for p in ps);y1=max(p.y for p in ps)
 right=cam.rotation_euler.to_matrix()@Vector((1,0,0));up=cam.rotation_euler.to_matrix()@Vector((0,1,0));cam.location+=right*((x0+x1)/2)+up*((y0+y1)/2)
 # Blender ortho_scale is horizontal for landscape and vertical for portrait.
 aspect=cw/ch;vertical=max(y1-y0,(x1-x0)/aspect)*padding/zoom;cam.data.ortho_scale=vertical*max(1,aspect)
 bpy.context.view_layer.update();return points

def render_view(v):
 layout=layouts[v['layout']];setup_layout(layout);state=v['state'];transforms={}
 if state=='drawer':
  drawer=bpy.data.objects['ARCHIVE_ALL_DRAWER'];drawer.location.y-=3.15
  transforms['drawer']={'name':drawer.name,'pullWeb':[0,0,3.15],'translationBlender':list(drawer.location),'scope':'Source drawer children move as one physical assembly; fixed rails do not follow.'}
 elif state=='inspect':
  book=bpy.data.objects['BOOK_dust'];rest=book.location.copy()
  source_points=mesh_points(book.children_recursive)
  source_center=Vector(tuple((min(p[i] for p in source_points)+max(p[i] for p in source_points))/2 for i in range(3)))
  cabinet_points=mesh_points(root.children_recursive)
  cabinet_center=Vector(tuple((min(p[i] for p in cabinet_points)+max(p[i] for p in cabinet_points))/2 for i in range(3)))
  cabinet_front=max(-p.y for p in cabinet_points)
  front=max(cabinet_front+8,-source_center.y+8)
  pivot=bpy.data.objects.new('OFFLINE_INSPECTION_PIVOT',None);sc.collection.objects.link(pivot);pivot.parent=root
  pivot.location=(cabinet_center.x,-(front+3),cabinet_center.z)
  book.parent=pivot;book.location=rest-source_center
  conversion=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
  pivot.rotation_euler=(conversion @ (Matrix.Rotation(.12,3,'X') @ Matrix.Rotation(.75,3,'Y')) @ conversion.transposed()).to_euler('XYZ')
  transforms['selected']={'name':book.name,'restTranslationBlender':list(rest),'originalBboxCenterBlender':list(source_center),'cabinetCenterBlender':list(cabinet_center),'extractionIntermediateBlender':[source_center.x,-front,source_center.z],'pivotBlender':list(pivot.location),'pivotEulerRadiansBlender':list(pivot.rotation_euler),'inspectionEulerRadiansWeb':[.12,.75,0],'sourceScale':1,'cameraPadding':1.65,'sequence':'Matches scene animateExtract() terminal translation; only after extraction is pivot rotation applied. Static terminal pose only.'}
 bpy.context.view_layer.update();cw,ch=v['canvas'];sc.render.resolution_x=cw*2;sc.render.resolution_y=ch*2
 if state=='inspect':
  cam=sc.camera;target=pivot.location.copy();cam.location=target+Vector((0,-math.cos(.23),math.sin(.23)))*160;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO'
  points=mesh_points(pivot.children_recursive);lo=Vector(tuple(min(p[i] for p in points) for i in range(3)));hi=Vector(tuple(max(p[i] for p in points) for i in range(3)));corners=[Vector((x,y,z)) for x in [lo.x,hi.x] for y in [lo.y,hi.y] for z in [lo.z,hi.z]]
  bpy.context.view_layer.update();ps=[cam.matrix_world.inverted()@p for p in corners];aspect=cw/ch;span=max(max(p.y for p in ps)-min(p.y for p in ps),(max(p.x for p in ps)-min(p.x for p in ps))/aspect)*1.65;cam.data.ortho_scale=span*max(1,aspect)
 else:points=fit_camera(root.children_recursive,cw,ch,pitch=.42 if state=='drawer' else .23,yaw=.28 if state=='drawer' else 0,padding=1.15)
 sc.render.resolution_percentage=100;sc.render.engine='CYCLES';sc.cycles.samples=128;sc.cycles.use_denoising=False
 if '--quick' in sys.argv:sc.cycles.samples=16
 sc.render.image_settings.file_format='PNG';sc.render.filepath=str(OUT/(v['key']+'-canvas.png'))
 sc.view_settings.view_transform='AgX';sc.view_settings.look='AgX - Medium High Contrast';sc.view_settings.exposure=.35
 # Offline studio setup is intentionally independent of the WebGL renderer.
 sc.world.color=(.16,.20,.27)
 ps=[world_to_camera_view(sc,sc.camera,p) for p in points]
 meta={**v,'isBrowserScreenshot':False,'isGameCapture':False,'geometrySource':'model-source/bookshelf-v3.blend','layoutSource':'launcher/web/modules/bookshelf/shelf/layout-core.mjs: layoutFor('+v['layout']+')','layoutSnapshot':'actual-layouts.json','boards':len(layout['boards']),'offlineBoardMicroBevel':.025,'studioLighting':'Three offline area lights repositioned by cabinet height; no WebGL parity claim','cameraBlender':list(sc.camera.location),'cameraRotationRadians':list(sc.camera.rotation_euler),'orthoScale':sc.camera.data.ortho_scale,'renderPixels':[cw*2,ch*2],'samples':sc.cycles.samples,'meshBoundsNativePixels':[min(p.x for p in ps)*cw,(1-max(p.y for p in ps))*ch,max(p.x for p in ps)*cw,(1-min(p.y for p in ps))*ch],'transforms':transforms,'limitations':['Offline Blender Cycles PBR render and Pillow panel composition, not browser or game capture.','Layout geometry comes from actual layoutFor() snapshots. Browser DOM, interaction timing, render performance, font shaping, and WebGL lighting parity are not verified by these images.','Inspection view shows one static terminal pose; it does not prove extraction/rotation animation or pointer handling.','Panel labels are offline explanatory captions. Original physical book/collection/folder textures are preserved; no additional decorative books or titles.']}
 if v.get('sidebarCollapsed'):
  meta['triggerSequence']=['收起目录','回总览'];meta['layoutTiming']='Explicit Home after sidebar collapse reselects layout for 638/665 canvas aspect; sidebar collapse alone is not claimed to immediately reflow.'
 (OUT/(v['key']+'-metadata.json')).write_text(json.dumps(meta,ensure_ascii=False,indent=2));bpy.ops.render.render(write_still=True)
 if state=='inspect':
  book.parent=root;book.location=rest;bpy.data.objects.remove(pivot,do_unlink=True)

selected=sys.argv[sys.argv.index('--view')+1] if '--view' in sys.argv else None
for view in VIEWS:
 if selected is None or view['key'] in selected.split(','):render_view(view)
print('OFFLINE_REFERENCE_RENDER_COMPLETE')
