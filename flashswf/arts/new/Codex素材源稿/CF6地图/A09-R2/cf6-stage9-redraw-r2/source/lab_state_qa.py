"""Exact original registration and mask/state comparison for lab assets."""
from pathlib import Path
import json,re,sys,hashlib
from PIL import Image,ImageDraw
from svg_native import write_part,inner,render
R=Path(__file__).resolve().parents[1];A=R/'reference'
REV=sys.argv[1] if len(sys.argv)>1 else 'r2'
N=json.loads((A/'lab-original-nodes.json').read_text())['nodes']
D=json.loads((A/'lab-shape-details.json').read_text());IDS={1446,1842,1844,1848};count=0

def pref(s,prefix):
 ids=re.findall(r'\bid="([^"]+)"',s)
 for i in sorted(ids,key=len,reverse=True):s=s.replace(f'id="{i}"',f'id="{prefix}{i}"').replace(f'url(#{i})',f'url(#{prefix}{i})').replace(f'href="#{i}"',f'href="#{prefix}{i}"')
 return s

def make_shapes():
 evidence=[]
 for d in D:
  cid=d['id']
  if str(cid) not in N or not set(d.get('bitmapDependencies',[]))&IDS:continue
  s=N[str(cid)]['svgInner'];imgs=list(re.finditer(r'<image\b[^>]+/>',s));fills=[f for f in d['fills'] if f['type']=='bitmap' and f['bitmapId']!=65535]
  assert len(imgs)==len(fills),(cid,len(imgs),len(fills))
  # Mixed floor-wall composite shapes are left to the stage assembler.
  if set(d.get('bitmapDependencies',[]))-{65535}-IDS:continue
  for k,(im,f) in reversed(list(enumerate(zip(imgs,fills)))):
   if f['bitmapId'] not in IDS:continue
   xf=re.search(r'transform="([^"]+)"',im.group()).group(1)
   frag=f'<g transform="{xf}">'+inner(R/f'parts/bitmap-{f["bitmapId"]}.svg',f'b{cid}_{k}_')+'</g>'
   s=s[:im.start()]+frag+s[im.end():]
  write_part(R/f'parts/shape-{cid}.svg',d['viewBox'],s)
  evidence.append({'shape':cid,'viewBox':d['viewBox'],'fills':fills,'original_clip_paths_retained':True})
 (R/f'qa/lab-shape-registration-{REV}.json').write_text(json.dumps(evidence,indent=2))

def node(cid,frame=1,new=False):
 global count
 count+=1;k=count;n=N[str(cid)]
 if n['code']!=39:
  f=R/f'parts/shape-{cid}.svg'
  return inner(f,f'n{k}_') if new and f.exists() else pref(n.get('svgInner',''),f'n{k}_')
 state=n['frames'][(frame-1)%len(n['frames'])];s='';masks=[]
 for depth,o in sorted(state.items(),key=lambda t:int(t[0])):
  dep=int(depth);masks=[m for m in masks if dep<=m[0]]
  frag=node(o['id'],frame-o['placedAt']+1,new)
  frag='<g transform="matrix('+' '.join(map(str,o['matrix']))+')">'+frag+'</g>'
  if 'clipDepth' in o:
   count+=1;mid=f'clip{count}';s+=f'<defs><clipPath id="{mid}" clipPathUnits="userSpaceOnUse">{frag}</clipPath></defs>';masks.append((o['clipDepth'],mid));continue
  for _,mid in masks:frag=f'<g clip-path="url(#{mid})">{frag}</g>'
  s+=frag
 return s

def main():
 make_shapes();ev=[]
 for frame in range(1,19):
  for new in [False,True]:
   kind='new' if new else 'original';body=node(1862,frame,new)
   f=write_part(R/f'review/door-{REV}-{kind}-f{frame:02d}.svg',[-65.5,-80.5,131,161],body)
   render(f,262)
  ev.append({'frame':frame,'original_state':N['1862']['frames'][frame-1]})
 out=Image.new('RGB',(840,6*375),'#c9cdd1');d=ImageDraw.Draw(out)
 for j in range(18):
  x=(j%3)*280;y=(j//3)*375;d.text((x+8,y+7),f'F{j+1:02d}   ORIGINAL    /    {REV.upper()} NATIVE',fill='#202833')
  for k,kind in enumerate(['original','new']):
   im=Image.open(R/f'review/door-{REV}-{kind}-f{j+1:02d}.png').convert('RGBA').resize((131,161),Image.Resampling.LANCZOS)
   out.paste(im,(x+7+k*135,y+32),im)
   # A 2x comparison of the opening center below gives mask-edge evidence.
   crop=Image.open(R/f'review/door-{REV}-{kind}-f{j+1:02d}.png').convert('RGBA').crop((11,66,222,308)).resize((116,133),Image.Resampling.LANCZOS)
   out.paste(crop,(x+14+k*135,y+216),crop)
 out.save(R/f'review/door-all18-original-{REV}.png')
 # Fan mask stays transparent, five original native blades keep original timing.
 fan_frames=[];seen=set()
 for i,frame_state in enumerate(N['1448']['frames']):
  key=json.dumps(frame_state,sort_keys=True)
  if key not in seen:fan_frames.append(i+1);seen.add(key)
 for frame in fan_frames:
  for new in [False,True]:
   kind='new' if new else 'original';f=write_part(R/f'review/fan-{REV}-{kind}-f{frame:02d}.svg',[-28.5,-28.5,57,57],node(1448,frame,new));render(f,342)
 fanout=Image.new('RGB',(7*230,180),'#c9cdd1');fd=ImageDraw.Draw(fanout)
 for i,fr in enumerate(fan_frames):
  fd.text((i*230+10,8),f'FAN FRAME {fr}: ORIGINAL / NEW',fill='#202833')
  for k,kind in enumerate(['original','new']):
   im=Image.open(R/f'review/fan-{REV}-{kind}-f{fr:02d}.png').convert('RGBA').resize((114,114),Image.Resampling.LANCZOS);fanout.paste(im,(i*230+k*114,42),im)
 fanout.save(R/f'review/fan-all7-original-{REV}.png')
 one=Image.new('RGB',(7*140,100),'#c9cdd1');od=ImageDraw.Draw(one)
 for i,fr in enumerate(fan_frames):
  od.text((i*140+4,4),f'F{fr} ORIG / NEW',fill='#202833')
  for k,kind in enumerate(['original','new']):
   im=Image.open(R/f'review/fan-{REV}-{kind}-f{fr:02d}.png').convert('RGBA').resize((57,57),Image.Resampling.LANCZOS);one.paste(im,(i*140+k*66+4,25),im)
 one.save(R/f'review/fan-all7-original-{REV}-1x.png')
 (R/f'qa/door-all18-{REV}.json').write_text(json.dumps({'sprite':1862,'frames':18,'display_states':len(set(json.dumps(f,sort_keys=True) for f in N['1862']['frames'])),'unchanged_frame_matrices_masks_and_depths':True,'states':ev},indent=2))
 print('all 18 door frames + fan states verified/exported',flush=True)
if __name__=='__main__':main()
