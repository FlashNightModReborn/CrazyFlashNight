from pathlib import Path
import json,re
from svg_native import write_part,inner,render
from PIL import Image,ImageDraw,ImageFont
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
R=Path(__file__).resolve().parents[1];NODES=json.loads((R/'reference/environment-original-nodes.json').read_text())['nodes'];DETAIL=json.loads((R/'reference/environment-shape-details.json').read_text());NEW={1701,1702,1704,1708,1717,1724};counter=0
for a in DETAIL:
 if not set(a.get('bitmapDependencies',[]))&NEW:continue
 cid=a['id'];s='<defs>'
 for bid in sorted(set(a['bitmapDependencies'])&NEW):s+=f'<g id="bitmap{bid}">'+inner(R/f'parts/bitmap-{bid}.svg',f'b{bid}')+'</g>'
 s+='</defs>'
 for k,f in enumerate(a['fills']):
  if f['type']=='bitmap' and f['bitmapId'] in NEW:
   s+=f'<clipPath id="fill{k}"><path d="{f["path"]}"/></clipPath><g clip-path="url(#fill{k})"><use href="#bitmap{f["bitmapId"]}" transform="matrix('+ ' '.join(map(str,f['matrix']))+')"/></g>'
 write_part(R/f'parts/shape-{cid}.svg',a['viewBox'],s)
def pref(s,p):
 ids=re.findall(r'\bid="([^"]+)"',s)
 for i in sorted(ids,key=len,reverse=True):s=s.replace(f'id="{i}"',f'id="{p}{i}"').replace(f'url(#{i})',f'url(#{p}{i})').replace(f'href="#{i}"',f'href="#{p}{i}"')
 return s

def node(cid,f=1,mode='new'):
 global counter
 counter+=1;z=counter;a=NODES[str(cid)]
 if a['code']!=39:
  p=R/f'parts/shape-{cid}.svg';q=R/f'reference/reused-crate/shape-{cid}.svg'
  if mode=='new' and p.exists():return inner(p,f'n{z}')
  if mode=='new' and q.exists():return inner(q,f'n{z}')
  return pref(a['svgInner'],f'n{z}_')
 state=a['frames'][(f-1)%len(a['frames'])];body='';masks=[]
 for depth,o in sorted(state.items(),key=lambda t:int(t[0])):
  dep=int(depth);masks=[v for v in masks if dep<=v[0]]
  if o.get('name')=='area':continue
  mult=o.get('colorMult',[256]*4);add=o.get('colorAdd',[0]*4)
  if mult[3]==0 and add[3]==0:continue
  frag=node(o['id'],1 if o['id']==254 else f-o['placedAt']+1,mode)
  if mult!=[256]*4 or add!=[0]*4:
   counter+=1;fid=f'col{counter}';filt=f'<filter id="{fid}" color-interpolation-filters="sRGB"><feComponentTransfer>'+''.join(f'<feFunc{c} type="linear" slope="{mult[k]/256}" intercept="{add[k]/255}"/>' for k,c in enumerate('RGBA'))+'</feComponentTransfer></filter>';frag=f'<defs>{filt}</defs><g filter="url(#{fid})">{frag}</g>'
  frag='<g transform="matrix('+' '.join(map(str,o['matrix']))+')">'+frag+'</g>'
  if 'clipDepth' in o:
   counter+=1;mid=f'mask{counter}';fid=f'white{counter}';body+=f'<defs><filter id="{fid}"><feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 1 0"/></filter><mask id="{mid}" maskUnits="userSpaceOnUse" x="-5000" y="-5000" width="10000" height="10000"><g filter="url(#{fid})">{frag}</g></mask></defs>';masks.append((o['clipDepth'],mid));continue
  for _,mid in masks:frag=f'<g mask="url(#{mid})">{frag}</g>'
  body+=frag
 return body

def save(name,body,vb,width,folder='previews'):
 p=write_part(R/f'{folder}/{name}.svg',vb,body);render(p,width);return p
font=_cf6_font(20)
for mode in ['original','new']:
 counter=0
 bg=node(1706,mode=mode);env=f'<g transform="translate(673.5 207.1)">{bg}</g>'
 for cid,x,y in [(1714,536.45,114.95),(1720,1198.4,112.4),(1442,378.1,444),(255,1043.85,216.55)]:env+=f'<g transform="translate({x} {y})">'+node(cid,mode=mode)+'</g>'
 root=node(1727,mode=mode)
 if mode=='new':
  write_part(R/'parts/background-1706.svg',[-676.95,-240.75,1508.95,483.55],bg)
  write_part(R/'parts/foreground-1727.svg',[111,.55,1211.95,178.75],root)
 for name,x,y in [('load-derived',0,-77.2),('middle',-350,-50),('right',-700,-100)]:
  body=f'<g transform="translate({x} {y})">{env}</g><g transform="translate({x*1.2} {y*1.2})">{root}</g>'
  save(f'scene-{name}-{mode}',body,[0,0,600,350],1200)
 save(f'panorama-{mode}',env+root,[0,0,1300,450],2600)
 for cid,frames in [(1714,[1,4,9]),(1720,[1,25,90,150,174])]:
  for f in frames:save(f'state-{cid}-f{f}-{mode}',node(cid,f,mode),[-85,-100,170,240],510)
for name in ['load-derived','middle','right','panorama']:
 ims=[Image.open(R/f'previews/{"" if name=="panorama" else "scene-"}{name}-{m}.png').convert('RGBA') for m in ['original','new']];w,h=ims[0].size
 out=Image.new('RGB',(w,h*2+82),'#202822');d=ImageDraw.Draw(out)
 for j,im in enumerate(ims):out.paste(im,(0,41+j*(h+41)),im);d.text((12,9+j*(h+41)),('ORIGINAL CF6' if j==0 else 'R1 / INTERIOR REDRAW')+' | '+name+' | STATIC LAYERS, NOT GAME SCREENSHOT',font=font,fill='white')
 out.save(R/f'previews/{name}-original-new.png')
# Full panorama includes foreground lamps at fixed author phase, without stretching any layer.
im=Image.open(R/'previews/panorama-new.png').convert('RGBA');out=Image.new('RGB',(im.width,im.height+72),'#202822');out.paste(im,(0,72),im);d=ImageDraw.Draw(out);d.text((15,10),'THIRD PLAYABLE STAGE A3 / COMPLETE 1300 x 450 WORLD',font=font,fill='white');d.text((15,40),'Foreground lamps at fixed author phase. Static artwork overview, not a game screenshot.',font=font,fill='#c3c7ba');out.save(R/'previews/panorama-new-labelled.png')
print('Rebuilt original/new interior, original matrices, depth masks and static state samples')
