from pathlib import Path
import json,re,xml.etree.ElementTree as E,subprocess
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];NS='http://www.w3.org/2000/svg'
T=json.loads((R/'reference/timelines.json').read_text());state={}
def mm(a,b):
 A,B,C,D,X,Y=a;e,f,g,h,x,y=b;return [A*e+C*f,B*e+D*f,A*g+C*h,B*g+D*h,A*x+C*y+X,B*x+D*y+Y]
def rec(cid,m):
 if str(cid) in T:
  for dep,o in sorted(T[str(cid)][0].items(),key=lambda x:int(x[0])):rec(o['id'],mm(m,o['matrix']))
 else:state[str(len(state)+1)]={'id':cid,'matrix':m}
rec(595,[1,0,0,1,0,0])
V=[-40,-95,95,165]
for variant in ['original','candidate']:
 b=[]
 for dep,o in sorted(state.items(),key=lambda x:int(x[0])):
  cid=o['id']; f=R/('reference' if variant=='original' else 'parts')/f'{cid}.svg'
  if not f.exists():continue
  root=E.parse(f).getroot();body=''.join(E.tostring(c,encoding='unicode') for c in root)
  ids=re.findall(r'id="([^"]+)"',body)
  for i in sorted(ids,key=len,reverse=True):body=body.replace(f'id="{i}"',f'id="p{dep}_{i}"').replace(f'#{i}"',f'#p{dep}_{i}"').replace(f'#{i})',f'#p{dep}_{i})')
  b.append('<g transform="matrix('+','.join(map(str,o['matrix']))+')">'+body+'</g>')
 f=R/f'previews/stand-{variant}.svg';f.write_text(f'<svg xmlns="{NS}" viewBox="'+ ' '.join(map(str,V))+'" width="570" height="990">'+''.join(b)+'</svg>')
 subprocess.run(['inkscape',str(f),'--export-filename='+str(f.with_suffix('.png'))],check=True,capture_output=True)
ims=[Image.open(R/f'previews/stand-{v}.png').convert('RGBA') for v in ['original','candidate']]
bb=[im.getbbox() for im in ims];box=(min(b[0] for b in bb)-12,min(b[1] for b in bb)-12,max(b[2] for b in bb)+12,max(b[3] for b in bb)+12)
board=Image.new('RGB',((box[2]-box[0])*2,box[3]-box[1]+40),'#e7e8e2');d=ImageDraw.Draw(board)
for i,im in enumerate(ims):
 im=im.crop(box);board.paste(im,(i*im.width,35),im);d.text((i*im.width+15,10),['ORIGINAL','R2 REFINED VECTOR'][i],fill='#1b2429')
board.save(R/'previews/stand-comparison.png')
# Enlarged isolated head and coat, identical source pixel crops.
atlas=Image.open(R/'reference/581.png').convert('RGBA');new=Image.open(R/'previews/atlas581.png').convert('RGBA')
for name,crop in [('face',(225,0,295,86)),('jacket',(0,8,140,251))]:
 sc=5 if name=='face' else 3;w=(crop[2]-crop[0])*sc;h=(crop[3]-crop[1])*sc;bo=Image.new('RGB',(w*2,h+35),'#e7e8e2');dr=ImageDraw.Draw(bo)
 for i,im in enumerate([atlas.crop(crop).resize((w,h)),new.crop(tuple(c*3 for c in crop)).resize((w,h))]):bo.paste(im,(i*w,35),im);dr.text((i*w+12,10),['ORIGINAL','R2 VECTOR'][i],fill='#1b2429')
 bo.save(R/f'previews/{name}-comparison.png')
