"""QA-only floor comparison. Uses exact source hierarchies and frozen R1 art.
R2 differs from R1 ONLY in the floor1957 and bounded static seam correction.
No part of this file is used to generate production artwork.
"""
from pathlib import Path
import copy,importlib.util,json,re,sys,argparse
from PIL import Image,ImageDraw,ImageFont
from svg_native import inner,write_part,render
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
BASE=R.parents[1]
FONT=_cf6_font(17)

def build_variant(a,original,r1dir,variant):
 if variant=='original':return original,None
 s=original;fills=[f for f in a.get('fills',[]) if f['type']=='bitmap' and f['bitmapId']!=65535]
 images=list(re.finditer(r'<image\b[^>]+/>',s));assert len(images)==len(fills),(a['id'],len(images),len(fills))
 defs={}
 for m,f in reversed(list(zip(images,fills))):
  bid=f['bitmapId'];p=r1dir/f'bitmap-{bid}.svg'
  if variant=='r2' and bid==1957:p=R/'parts/bitmap-1957.svg'
  if not p.exists():continue
  transform=re.search(r'transform="([^"]+)"',m.group()).group(1);sid=f'material_{a["id"]}_{bid}'
  if sid not in defs:defs[sid]=f'<g id="{sid}">'+inner(p,sid)+'</g>'
  frag=f'<use transform="{transform}" href="#{sid}"/>';s=s[:m.start()]+frag+s[m.end():]
 audit=None
 if variant=='r2':s,audit=correct_floor_seams(a,s)
 return '<defs>'+''.join(defs.values())+'</defs>'+s,audit

def stack(files,out,title):
 ims=[Image.open(p).convert('RGBA') for p in files];w=max(i.width for i in ims);h=sum(i.height+30 for i in ims)
 canvas=Image.new('RGB',(w,h),'#252c2d');d=ImageDraw.Draw(canvas);y=0
 for label,im in zip(['ORIGINAL','R1 / frozen','R2 / repaired floor only'],ims):
  d.text((8,y+5),f'{label} / {title}',font=FONT,fill='white');canvas.paste(im,(0,y+30),im);y+=im.height+30
 canvas.save(out)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--round',default='round1');ap.add_argument('--stages',nargs='+',type=int,default=[18,19,20,22]);args=ap.parse_args();reports=[]
 out=R/'previews/floor-seam-r2'/args.round;out.mkdir(parents=True,exist_ok=True)
 for stage in args.stages:
  sr=BASE/'working'/f'cf6-stage{stage}-redraw-r2';fr=BASE/'frozen'/f'cf6-stage{stage}-redraw-r1';spec=importlib.util.spec_from_file_location(f'rebuild_{stage}',sr/'source/rebuild.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
  nodes=copy.deepcopy(mod.NODES);details=mod.DETAIL;shape=next(a for a in details if 1957 in a.get('bitmapDependencies',[]));cid=shape['id'];vb=shape['viewBox'];files={'local':[],'scene':[],'world':[]}
  for variant in ['original','r1','r2']:
   mod.NODES=copy.deepcopy(nodes)
   for a in details:
    if str(a['id']) not in mod.NODES or mod.NODES[str(a['id'])]['code']==39:continue
    if not a.get('bitmapDependencies'):continue
    src=nodes[str(a['id'])].get('svgInner','')
    if '<image' not in src:continue
    art,audit=build_variant(a,src,fr/'reference/reused',variant);mod.NODES[str(a['id'])]['svgInner']=art
    if audit:reports.append({'stage':stage,**audit})
   mod.reset();body=mod.complete(mod.node(cid,1,'original'))
   localvb=([-350,-80,760,291] if stage in [18,19] else [-380,-79,760,413])
   for typ,b,v,width in [('local',body,localvb,1140),('scene',mod.composition('original'),[0,0,600,350],900),('world',mod.composition('original',world_only=True),[0,0,mod.W,mod.H],mod.W)]:
    p=write_part(out/f'a{stage}-{typ}-{variant}.svg',v,b);render(p,width);files[typ].append(p.with_suffix('.png'));p.unlink()
   print(stage,variant,flush=True)
  for typ,paths in files.items():stack(paths,out/f'a{stage}-{typ}-original-r1-r2.png',f'a{stage} {typ}; exact original hierarchy')
 (R/'qa/floor-seam-repair-audit.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2))
 print(out,flush=True)
if __name__=='__main__':main()
