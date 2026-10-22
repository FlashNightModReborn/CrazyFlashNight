"""Offline CF6 industrial map assembly; frozen native-coordinate assets, exact source frames.
Run python source/rebuild.py. Only local references and standard Python/Inkscape are used.
"""
from pathlib import Path
import argparse,json,re,shutil,hashlib
from PIL import Image,ImageDraw,ImageFont
from svg_native import write_part,inner,render
from floor_seams import correct_floor_seams
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
NEW={int(p.stem.split('-')[1]) for p in (R/'reference/reused').glob('bitmap-*.svg')}
FROZEN_SHAPES={int(p.stem.split('-')[1]) for p in (R/'reference/reused').glob('shape-*.svg')}
FONT=_cf6_font(17)
counter=0;leaf_defs={}
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
 global counter,leaf_defs
 a=NODES[str(cid)]
 if a['code']!=39:
  sid=f'leaf_{cid}_{mode}'
  if sid not in leaf_defs:
   p=R/f'parts/shape-{cid}.svg';frag=inner(p,sid) if mode=='new' and p.exists() else pref(a.get('svgInner',''),sid+'_')
   leaf_defs[sid]=f'<g id="{sid}">{frag}</g>'
  return f'<use href="#{sid}"/>'
 f=(f-1)%len(a['frames'])+1;state=a['frames'][f-1];body='';masks=[]
 for depth,o in sorted(state.items(),key=lambda t:int(t[0])):
  dep=int(depth);masks=[v for v in masks if dep<=v[0]]
  if o.get('name')=='area':continue
  if o.get('colorMult',[256]*4)[3]==0 and o.get('colorAdd',[0]*4)[3]==0:continue
  frag=transformed(o,node(o['id'],1 if o['id']==254 else f-o['placedAt']+1,mode))
  if 'clipDepth' in o:
   counter+=1;mid=f'mask{counter}';fid=f'white{counter}'
   body+=f'<defs><filter id="{fid}"><feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 1 0"/></filter><mask id="{mid}" maskUnits="userSpaceOnUse" x="-5000" y="-5000" width="10000" height="10000"><g filter="url(#{fid})">{frag}</g></mask></defs>'
   masks.append((o['clipDepth'],mid));continue
  for _,mid in masks:frag=f'<g mask="url(#{mid})">{frag}</g>'
  body+=frag
 return body

def reset():
 global counter,leaf_defs
 counter=0;leaf_defs={}
def complete(body):return '<defs>'+''.join(leaf_defs.values())+'</defs>'+body

def make_shapes():
 evidence=[]
 for p in (R/'reference/reused').glob('*.svg'):shutil.copy2(p,R/'parts'/p.name)
 for a in DETAIL:
  cid=a['id']
  if str(cid) not in NODES or cid in FROZEN_SHAPES or not set(a.get('bitmapDependencies',[]))&NEW:continue
  s=NODES[str(cid)]['svgInner'];fills=[f for f in a.get('fills',[]) if f['type']=='bitmap' and f['bitmapId']!=65535];images=list(re.finditer(r'<image\b[^>]+/>',s));assert len(images)==len(fills),(cid,len(images),len(fills))
  changed=[];defs={}
  for k,(m,f) in reversed(list(enumerate(zip(images,fills)))):
   bid=f['bitmapId']
   if bid not in NEW:continue
   p=R/f'parts/bitmap-{bid}.svg';assert p.exists(),p
   transform=re.search(r'transform="([^"]+)"',m.group()).group(1)
   sid=f'material_{cid}_{bid}'
   if sid not in defs:defs[sid]=f'<g id="{sid}">'+inner(p,sid)+'</g>'
   frag=f'<use transform="{transform}" href="#{sid}"/>';s=s[:m.start()]+frag+s[m.end():];changed.append({'bitmap':bid,'matrix':transform})
  s, floor_audit = correct_floor_seams(a, s)
  write_part(R/f'parts/shape-{cid}.svg',a['viewBox'],'<defs>'+''.join(defs.values())+'</defs>'+s)
  evidence.append({'shape':cid,'viewBox':a['viewBox'],'replaced':changed,'retained_original_nonimage_markup':floor_audit is None,'floor_seam_repair':floor_audit,'original_bitmap_dependencies':a.get('bitmapDependencies',[])})
 return evidence

def composition(mode='new',camera=(0,0),world_only=False):
 reset()
 world=''.join(transformed(o,node(o['id'],1,mode)) for o in sorted(LAY['worldFirstFrame'],key=lambda o:o['depth']) if 'environment' in o['role'])
 if world_only:return complete(world)
 roots={o['depth']:o for o in LAY['rootSceneObjects'] if o['role']=='environment_root_layer'}
 rootplacements={int(k):v for k,v in LAY['rootDisplay'].items() if v.get('id')==LAY['worldCharacterId']}
 body=''
 for dep,o in sorted({**roots,**rootplacements}.items()):
  if o['id']==LAY['worldCharacterId']:
   # Camera movement applies only to gameworld. Root 1956 stays fixed at its source matrix.
   worldplaced=transformed(o,world);body+=f'<g transform="translate({-camera[0]} {-camera[1]})">{worldplaced}</g>'
  else:body+=transformed(o,node(o['id'],1,mode))
 return complete(body)

def save(name,body,vb,width):
 p=write_part(R/f'previews/{name}.svg',vb,body);render(p,width);p.unlink();return p.with_suffix('.png')
def compare(name,vertical=False):
 ims=[Image.open(R/f'previews/{name}-{m}.png').convert('RGBA') for m in ['original','new']];w,h=ims[0].size
 out=Image.new('RGB',(w if vertical else 2*w,2*(h+30) if vertical else h+30),'#202528');d=ImageDraw.Draw(out)
 for j,im in enumerate(ims):
  x=0 if vertical else j*w;y=j*(h+30) if vertical else 0;out.paste(im,(x,y+30),im)
  title=('ORIGINAL' if j==0 else LABEL.upper()+' R2')+' / '+name+' / STATIC SOURCE STUDY'
  if name.startswith('object-'):
   _,cid,frame=name.split('-');title=('ORIG' if j==0 else LABEL.upper()+' R2')+' / '+cid+' '+frame
  d.text((x+9,y+6),title,fill='white',font=FONT)
 out.save(R/f'previews/{name}-original-new.png',optimize=True)

def object_body(cid,f,mode):
 reset();return complete(node(cid,f,mode))
def samples():
 specs={1442:([1,3,6,11],[-205,-125,385,150]),1862:([1,2,5,9,13,18],[-100,-90,200,200]),1982:([1,2,8,16,24,32],[-110,-100,220,220]),1976:([1,3,6,8,9,10,12,15,16],[-200,-90,400,180]),1868:([1,10,20,29],[-320,-140,640,200]),481:([1,6,11],[-50,-60,100,100])}
 records=[]
 for cid,(frames,vb) in specs.items():
  if str(cid) not in NODES:continue
  rows=[]
  for f in frames:
   for mode in ['original','new']:save(f'object-{cid}-f{f:02d}-{mode}',object_body(cid,f,mode),vb,400)
   compare(f'object-{cid}-f{f:02d}')
   im=Image.open(R/f'previews/object-{cid}-f{f:02d}-original-new.png');im.thumbnail((800,450));rows.append(im.copy())
  out=Image.new('RGB',(max(i.width for i in rows),sum(i.height for i in rows)),'#202528');y=0
  for im in rows:out.paste(im,(0,y));y+=im.height
  out.save(R/f'previews/object-{cid}-sample-sheet.png',optimize=True)
  records.append({'sprite':cid,'total_original_frames':len(NODES[str(cid)]['frames']),'preview_sample_frames':frames,'original_timeline_and_native_masks_unchanged':True})
 return records

def refresh_labels():
 for p in (R/'previews').glob('*-original.png'):
  name=p.stem[:-9]
  if (R/f'previews/{name}-new.png').exists():compare(name,vertical=name.startswith('panorama'))
 for sheet in (R/'previews').glob('object-*-sample-sheet.png'):
  cid=sheet.name.split('-')[1];rows=[]
  for p in sorted((R/'previews').glob(f'object-{cid}-f*-original-new.png')):
   im=Image.open(p);im.thumbnail((800,450));rows.append(im.copy())
  out=Image.new('RGB',(max(i.width for i in rows),sum(i.height for i in rows)),'#202528');y=0
  for im in rows:out.paste(im,(0,y));y+=im.height
  out.save(sheet,optimize=True)
 print(LABEL+' compact labels refreshed',flush=True)

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--scenes-only',action='store_true');parser.add_argument('--samples-only',action='store_true');parser.add_argument('--labels-only',action='store_true');args=parser.parse_args()
 if args.labels_only:refresh_labels();return
 for directory in ['parts','previews','qa']:(R/directory).mkdir(exist_ok=True)
 ev=make_shapes()
 if args.samples_only:
  state_samples=samples();p=R/'qa/assembly-audit.json';a=json.loads(p.read_text());a['state_samples']=state_samples;p.write_text(json.dumps(a,ensure_ascii=False,indent=2));print(LABEL+' state samples complete',flush=True);return
 views=[('author',0,0),('middle',(W-600)/2,(H-350)/2),('right',W-600,H-350)]
 for mode in ['original','new']:
  for name,x,y in views:save(f'scene-{name}-{mode}',composition(mode,(x,y)),[0,0,600,350],600)
  save(f'panorama-{mode}',composition(mode),[0,0,W,H],W)
  save(f'panorama-world-only-{mode}',composition(mode,world_only=True),[0,0,W,H],W)
  if mode=='new':
   write_part(R/f'parts/environment-{LABEL}.svg',[0,0,W,H],composition(mode))
   write_part(R/f'parts/environment-world-only-{LABEL}.svg',[0,0,W,H],composition(mode,world_only=True))
 for name in ['scene-author','scene-middle','scene-right','panorama','panorama-world-only']:compare(name,vertical=name.startswith('panorama'))
 state_samples=[] if args.scenes_only else samples()
 manifest=json.loads((R/'reference/frozen-asset-manifest.json').read_text());assert all(hashlib.sha256((R/a['file']).read_bytes()).hexdigest()==a['sha256'] for a in manifest)
 audit={'stage':LABEL,'source_kind':'independent frozen native-coordinate SVG reuse and preserved original vectors/excluded bitmap content','newly_redrawn_bitmap_ids':[i for i in sorted(NEW) if i in [1231,1955,1957,1958,1962,1964,1965,1966,1971]],'reused_bitmap_ids':[i for i in sorted(NEW) if i not in [1231,1955,1957,1958,1962,1964,1965,1966,1971]],'frozen_shape_ids':sorted(FROZEN_SHAPES),'frozen_manifest_verified':True,'world_logical_dimensions':[W,H],'root_layers':[o for o in LAY['rootSceneObjects'] if o['role']=='environment_root_layer'],'gameworld_placement':[o for o in LAY['rootDisplay'].values() if o.get('id')==LAY['worldCharacterId']],'fixed_viewports':[{'name':n,'viewBox':[0,0,600,350],'camera_world_translation':[-x,-y],'root_camera_translation':[0,0]} for n,x,y in views],'shape_replacements':ev,'original_animation_frame_counts':{k:len(v['frames']) for k,v in NODES.items() if 'frames'in v},'state_samples':state_samples,'preserved_original_bitmap_ids':sorted({b for a in DETAIL for b in a.get('bitmapDependencies',[]) if b not in NEW and b not in [1409,1435,65535]}),'original_font_outline_shapes':[a['id'] for a in DETAIL if a.get('fontOutlineExact')],'static_only':True,'runtime_simulation':False,'root_layers_stretched':False,'panorama_note':'fixed root-author phase overview; fixed root 1956 covers only source 600x200 and is never repeated or stretched','full_frame_matrices_colors_clipDepth_retained':True}
 (R/'qa/assembly-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2))
 print(LABEL+' assembly and samples complete',flush=True)
if __name__=='__main__':main()
