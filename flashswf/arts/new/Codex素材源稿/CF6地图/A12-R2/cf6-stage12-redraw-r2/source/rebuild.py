"""Independent offline assembly from frozen native-coordinate SVG reuse sources.
No original animation display state or original material is mutated.
"""
from pathlib import Path
import json,re,shutil,hashlib
from xml.etree import ElementTree as ET
from PIL import Image,ImageDraw,ImageFont
from svg_native import write_part,inner,render
def _cf6_font(size):
    # PATCHED(cf6-map-source): 硬编码 Linux 字体路径在 Windows 不存在；仅影响预览标注
    cands=[R/'reference/fonts'/'DejaVuSans.ttf']
    try:
        import matplotlib as _mpl, os as _os
        cands.append(Path(_os.path.join(_os.path.dirname(_mpl.__file__),'mpl-data','fonts','ttf','DejaVuSans.ttf')))
    except Exception:
        pass
    for _c in cands:
        if Path(_c).is_file():return ImageFont.truetype(str(_c),size)
    return ImageFont.load_default()
R=Path(__file__).resolve().parents[1]
NODES=json.loads((R/'reference/environment-original-nodes.json').read_text())['nodes']
DETAIL=json.loads((R/'reference/environment-shape-details.json').read_text())
LAY=json.loads((R/'reference/layout-inventory.json').read_text());LABEL=LAY['label'];STAGE=int(LABEL[1:]);W,H=LAY['worldLoad']['logicalBackgroundSize']
NEW={int(p.stem.split('-')[1]) for p in (R/'reference/reused').glob('bitmap-*.svg')};counter=0
FONT=_cf6_font(18)
def pref(s,p):
 for i in sorted(set(re.findall(r'\bid="([^"]+)"',s)),key=len,reverse=True):s=s.replace(f'id="{i}"',f'id="{p}{i}"').replace(f'url(#{i})',f'url(#{p}{i})').replace(f'href="#{i}"',f'href="#{p}{i}"')
 return s

def transformed(o,frag):
 global counter
 mult=o.get('colorMult',[256]*4);add=o.get('colorAdd',[0]*4)
 if mult[3]==0 and add[3]==0:return ''
 if mult!=[256]*4 or add!=[0]*4:
  counter+=1;fid=f'col{counter}'
  filt=f'<filter id="{fid}" color-interpolation-filters="sRGB"><feComponentTransfer>'+''.join(f'<feFunc{c} type="linear" slope="{mult[k]/256}" intercept="{add[k]/255}"/>' for k,c in enumerate('RGBA'))+'</feComponentTransfer></filter>'
  frag=f'<defs>{filt}</defs><g filter="url(#{fid})">{frag}</g>'
 return '<g transform="matrix('+' '.join(map(str,o.get('matrix',[1,0,0,1,0,0])))+')">'+frag+'</g>'

def node(cid,f=1,mode='new'):
 global counter
 counter+=1;z=counter;a=NODES[str(cid)]
 if a['code']!=39:
  p=R/f'parts/shape-{cid}.svg'
  return inner(p,f'n{z}') if mode=='new' and p.exists() else pref(a.get('svgInner',''),f'n{z}_')
 f=(f-1)%len(a['frames'])+1
 state=a['frames'][f-1];body='';masks=[]
 for depth,o in sorted(state.items(),key=lambda t:int(t[0])):
  dep=int(depth);masks=[v for v in masks if dep<=v[0]]
  if o.get('name')=='area':continue
  mult=o.get('colorMult',[256]*4);add=o.get('colorAdd',[0]*4)
  if mult[3]==0 and add[3]==0:continue
  frag=transformed(o,node(o['id'],1 if o['id']==254 else f-o['placedAt']+1,mode))
  if 'clipDepth' in o:
   counter+=1;mid=f'mask{counter}';fid=f'white{counter}'
   body+=f'<defs><filter id="{fid}"><feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 1 0"/></filter><mask id="{mid}" maskUnits="userSpaceOnUse" x="-5000" y="-5000" width="10000" height="10000"><g filter="url(#{fid})">{frag}</g></mask></defs>'
   masks.append((o['clipDepth'],mid));continue
  for _,mid in masks:frag=f'<g mask="url(#{mid})">{frag}</g>'
  body+=frag
 return body

def make_shapes():
 evidence=[]
 for p in (R/'reference/reused').glob('*.svg'):shutil.copy2(p,R/'parts'/p.name)
 for a in DETAIL:
  if str(a['id']) not in NODES or not set(a.get('bitmapDependencies',[]))&NEW:continue
  cid=a['id'];s=NODES[str(cid)]['svgInner'];fills=[f for f in a['fills'] if f['type']=='bitmap' and f['bitmapId']!=65535];images=list(re.finditer(r'<image\b[^>]+/>',s));assert len(images)==len(fills),(cid,len(images),len(fills))
  changed=[]
  for k,(m,f) in reversed(list(enumerate(zip(images,fills)))):
   bid=f['bitmapId']
   if bid not in NEW:continue
   p=R/f'parts/bitmap-{bid}.svg';assert p.exists(),p
   transform=re.search(r'transform="([^"]+)"',m.group()).group(1)
   frag=f'<g transform="{transform}">'+inner(p,f'b{cid}_{k}_')+'</g>';s=s[:m.start()]+frag+s[m.end():];changed.append({'bitmap':bid,'matrix':transform})
  write_part(R/f'parts/shape-{cid}.svg',a['viewBox'],s)
  evidence.append({'shape':cid,'viewBox':a['viewBox'],'replaced':changed,'retained_original_nonimage_markup':True,'original_bitmap_dependencies':a.get('bitmapDependencies',[])})
 return evidence

def composition(mode='new',phase=1,world_only=False):
 global counter
 counter=0
 world=''.join(transformed(o,node(o['id'],1,mode)) for o in sorted(LAY['worldFirstFrame'],key=lambda o:o['depth']) if 'environment' in o['role'])
 if world_only:return world
 env='';roots={o['depth']:o for o in LAY['rootSceneObjects'] if o['role']=='environment_root_layer'}
 rootplacements={int(k):v for k,v in LAY['rootDisplay'].items() if v.get('id')==LAY['worldCharacterId']}
 for dep,o in sorted({**roots,**rootplacements}.items()):env+=transformed(o,world if o['id']==LAY['worldCharacterId'] else node(o['id'],phase,mode))
 return env

def save(name,body,vb,width):
 p=write_part(R/f'previews/{name}.svg',vb,body);render(p,width);return p

def compare(name,vertical=False):
 ims=[Image.open(R/f'previews/{name}-{m}.png').convert('RGBA') for m in ['original','new']];w,h=ims[0].size
 out=Image.new('RGB',(w if vertical else 2*w,2*(h+35) if vertical else h+35),'#262b2d');d=ImageDraw.Draw(out)
 for j,im in enumerate(ims):
  x=0 if vertical else j*w;y=j*(h+35) if vertical else 0;out.paste(im,(x,y+35),im);title=('ORIGINAL' if j==0 else LABEL.upper()+' R2')+' / '+name
  if not name.startswith('object-'):title+=' / FIXED STATIC STUDY'
  d.text((x+9,y+7),title,fill='white',font=FONT)
 out.save(R/f'previews/{name}-original-new.png')

def object_body(cid,f,mode):
 global counter
 counter=0
 return node(cid,f,mode)

def samples():
 specs={1430:([1,15,30,59],[-155,-145,310,315]),1442:([1,3,6,11],[-205,-125,385,150]),1838:([1,2,7,10,16],[-190,-75,380,130]),1862:([1,5,9,13,18],[-65.5,-80.5,131,161]),1939:([1,2,10,18,25],[-210,-245,430,385]),1899:([1,2,4,6],[-75,-55,150,110])}
 records=[]
 for cid,(frames,vb) in specs.items():
  if str(cid) not in NODES:continue
  for f in frames:
   for mode in ['original','new']:save(f'object-{cid}-f{f:02d}-{mode}',object_body(cid,f,mode),vb,400)
   compare(f'object-{cid}-f{f:02d}')
  rows=[]
  for f in frames:
   im=Image.open(R/f'previews/object-{cid}-f{f:02d}-original-new.png');im.thumbnail((650,450));rows.append(im.copy())
  out=Image.new('RGB',(max(i.width for i in rows),sum(i.height for i in rows)),'#262b2d');y=0
  for im in rows:out.paste(im,(0,y));y+=im.height
  out.save(R/f'previews/object-{cid}-sample-sheet.png')
  records.append({'sprite':cid,'total_original_frames':len(NODES[str(cid)]['frames']),'preview_sample_frames':frames,'note':'Frozen SVG material reuse with unchanged original native vector, masks and original timeline. Not newly redrawn full animation.'})
 return records

def main():
 for directory in ['parts','previews','qa']:(R/directory).mkdir(exist_ok=True)
 ev=make_shapes();views=[('author',0,0),('middle',(W-600)/2,(H-350)/2),('right',W-600,H-350)]
 if STAGE==13:views=[('author',0,0),('middle',100,0),('right',200,0)]
 for mode in ['original','new']:
  env=composition(mode)
  for name,x,y in views:save(f'scene-{name}-{mode}',env,[x,y,600,350],1200)
  save(f'panorama-{mode}',env,[0,0,W,H],min(2400,W*2))
  if mode=='new':write_part(R/f'parts/environment-{LABEL}.svg',[0,0,W,H],env)
  if STAGE==13:
   save(f'panorama-world-only-{mode}',composition(mode,world_only=True),[0,0,W,H],1200)
   for f in [1,10,19,28,37]:save(f'author-f{f:02d}-{mode}',composition(mode,f),[0,0,600,350],1200)
   # Render the next cycle from frame 38 and compare it against frame 1.
   save(f'author-f38-cycle-{mode}',composition(mode,38),[0,0,600,350],1200)
 for name in ['scene-author','scene-middle','scene-right','panorama']:compare(name,vertical=name=='panorama')
 if STAGE==13:
  for f in [1,10,19,28,37]:compare(f'author-f{f:02d}')
  for mode in ['original','new']:
   assert Image.open(R/f'previews/author-f01-{mode}.png').tobytes()==Image.open(R/f'previews/author-f38-cycle-{mode}.png').tobytes()
  ims=[Image.open(R/f'previews/author-f{f:02d}-{mode}.png').convert('RGBA') for f in [37,1] for mode in ['original','new']]
  out=Image.new('RGB',(1200,2*385),'#262b2d');d=ImageDraw.Draw(out)
  for i,im in enumerate(ims):x=(i%2)*600;y=(i//2)*385;im.thumbnail((600,350));out.paste(im,(x,y+35),im);d.text((x+10,y+8),f'F{37 if i<2 else 1}: '+('ORIGINAL' if i%2==0 else 'A13 R1'),fill='white',font=FONT)
  out.save(R/'previews/elevator-37-to-1-original-new.png')
 state_samples=samples()
 manifest=json.loads((R/'reference/frozen-asset-manifest.json').read_text());assert all(hashlib.sha256((R/a['file']).read_bytes()).hexdigest()==a['sha256'] for a in manifest)
 audit={'stage':LABEL,'source_kind':'independent frozen SVG reuse + original native vector and embedded original excluded bitmap content','newly_redrawn_assets':[],'reused_bitmap_ids':sorted(NEW),'frozen_manifest_verified':True,'world_logical_dimensions':[W,H],'root_layers':[o for o in LAY['rootSceneObjects'] if o['role']=='environment_root_layer'],'gameworld_placement':[o for o in LAY['rootDisplay'].values() if o.get('id')==LAY['worldCharacterId']],'fixed_viewports':[{'name':n,'viewBox':[x,y,600,350]} for n,x,y in views],'shape_replacements':ev,'original_animation_frame_counts':{k:len(v['frames']) for k,v in NODES.items() if 'frames'in v},'state_samples':state_samples,'preserved_original_bitmap_ids':sorted({b for a in DETAIL for b in a.get('bitmapDependencies',[]) if b not in NEW and b not in [1409,1435,65535]}),'excluded_character_pose_roots':[o['id'] for o in LAY['worldFirstFrame'] if o['role']=='character_pose_prop'],'static_only':True,'root_layers_stretched':False,'a13_cycle_frame38_equals_frame1':STAGE==13}
 (R/'qa/assembly-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2))
 print(LABEL+' assembly and samples complete',flush=True)
if __name__=='__main__':main()
