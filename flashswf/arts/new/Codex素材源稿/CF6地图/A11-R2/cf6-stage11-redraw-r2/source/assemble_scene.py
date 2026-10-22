from pathlib import Path
import json,re
from svg_native import write_part,inner,render
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1]
NODES=json.loads((R/'reference/environment-original-nodes.json').read_text())['nodes']
DETAIL=json.loads((R/'reference/environment-shape-details.json').read_text())
NEW={1404,1405,1414,1415,1817,1820,1821,1828,1833,1842,1844,1412,1877,1882,1588,1895,1897,1902};counter=0
# Replace only actual bitmap images, preserving original clip, solid and gradient fills.
for a in DETAIL:
 if str(a['id']) not in NODES or not set(a.get('bitmapDependencies',[]))&NEW:continue
 cid=a['id'];s=NODES[str(cid)]['svgInner'];fills=[f for f in a['fills'] if f['type']=='bitmap' and f['bitmapId']!=65535];images=list(re.finditer(r'<image\b[^>]+/>',s));assert len(images)==len(fills),(cid,len(images),len(fills))
 for k,(m,f) in reversed(list(enumerate(zip(images,fills)))):
  bid=f['bitmapId']
  if bid not in NEW:continue
  p=R/f'parts/bitmap-{bid}.svg';assert p.exists(),p
  transform=re.search(r'transform="([^"]+)"',m.group()).group(1)
  frag=f'<g transform="{transform}">'+inner(p,f'b{cid}_{k}_')+'</g>'
  s=s[:m.start()]+frag+s[m.end():]
 write_part(R/f'parts/shape-{cid}.svg',a['viewBox'],s)
from tyrant_culture import build as build_tyrant
build_tyrant(R,R/'reference/tyrant-native/LIBRARY')
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
  return pref(a.get('svgInner',''),f'n{z}_')
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
def placed(o,frame,mode):
 global counter
 frag=node(o['id'],frame,mode);mult=o.get('colorMult',[256]*4);add=o.get('colorAdd',[0]*4)
 if mult!=[256]*4 or add!=[0]*4:
  counter+=1;fid=f'placecol{counter}';frag='<defs><filter id="'+fid+'" color-interpolation-filters="sRGB"><feComponentTransfer>'+''.join(f'<feFunc{c} type="linear" slope="{mult[k]/256}" intercept="{add[k]/255}"/>' for k,c in enumerate('RGBA'))+'</feComponentTransfer></filter></defs><g filter="url(#'+fid+')">'+frag+'</g>'
 return '<g transform="matrix('+' '.join(map(str,o['matrix']))+')">'+frag+'</g>'

font=ImageFont.truetype(str(R/'reference/fonts/DejaVuSans.ttf'),20)
LAY=json.loads((R/'reference/layout-inventory.json').read_text())
ROOT_WORLD_MATRIX=next(o['matrix'] for o in LAY['rootDisplay'].values() if o.get('name')=='gameworld')
for mode in ['original','new']:
 counter=0;env=''
 for o in LAY['worldFirstFrame']:
  if 'environment' not in o['role']:continue
  env+=placed(o,1,mode)
 # Apply the source root transform once to the assembled world, never to native bitmap/shape parts.
 env='<g transform="matrix('+' '.join(map(str,ROOT_WORLD_MATRIX))+')">'+env+'</g>'
 if mode=='new':write_part(R/'parts/environment-a11.svg',[0,0,990,450],env)
 for name,x,y in [('author',0,0),('middle',-195,-50),('right',-390,-100)]:save(f'scene-{name}-{mode}',f'<g transform="translate({x} {y})">{env}</g>',[0,0,600,350],1200)
 save(f'panorama-{mode}',env,[0,0,990,450],1980)
for name in ['scene-author','scene-middle','scene-right','panorama']:
 ims=[Image.open(R/f'previews/{name}-{m}.png').convert('RGBA') for m in ['original','new']];w,h=ims[0].size;o=Image.new('RGB',(w,h*2+82),'#222721');d=ImageDraw.Draw(o)
 for j,im in enumerate(ims):o.paste(im,(0,41+j*(h+41)),im);d.text((12,9+j*(h+41)),('ORIGINAL CF6' if j==0 else 'A11 R2')+' | '+name+' | FIXED STATIC ENVIRONMENT, NOT GAME SCREENSHOT',font=font,fill='white')
 o.save(R/f'previews/{name}-original-new.png')
im=Image.open(R/'previews/panorama-new.png').convert('RGBA');o=Image.new('RGB',(im.width,im.height+45),'#222721');o.paste(im,(0,45),im);d=ImageDraw.Draw(o);d.text((15,10),'A11 / 990 x 450 WORLD / FIXED STATIC ENVIRONMENT, NOT GAME SCREENSHOT',font=font,fill='white');o.save(R/'previews/panorama-new-labelled.png')


# Static-only refresh preserves previously rendered independent object-state comparisons.
if '--static-only' in __import__('sys').argv:raise SystemExit(0)

for cid,frames,vb in [(1899,[1,2,3,4,5,6],[-25,-22,50,44]),(1906,[1],[-105,-120,210,245])]:
 for frame in frames:
  ims=[]
  for mode in ['original','new']:
   p=save(f'object-{cid}-f{frame}-{mode}',node(cid,frame,mode),vb,600);ims.append(Image.open(p.with_suffix('.png')).convert('RGBA'))
  w,h=ims[0].size;o=Image.new('RGB',(w*2,h+42),'#41474a');d=ImageDraw.Draw(o)
  for j,im in enumerate(ims):o.paste(im,(w*j,42),im);d.text((w*j+8,8),('ORIGINAL' if j==0 else 'A11 R2')+f' / {cid} FRAME {frame}',font=font,fill='white')
  o.save(R/f'previews/object-{cid}-f{frame}-original-new.png')
