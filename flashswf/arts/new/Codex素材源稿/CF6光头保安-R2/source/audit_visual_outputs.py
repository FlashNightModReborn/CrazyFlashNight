"""Decode every review animation, verify frame counts, and make visual sample sheets.
This verifies exported review media only; it never executes game/Flash code.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import json,hashlib
R=Path(__file__).resolve().parents[1];out=[]
expected={'death-a0':31,'death-a1':46,'death-a2':35,'transform-887':75,'live-actions':197,'knockdown-variants':232}
for name,count in expected.items():
 p=R/f'previews/{name}.gif';im=Image.open(p);assert im.n_frames==count,(name,im.n_frames,count)
 samples=sorted(set([0,count//5,2*count//5,3*count//5,4*count//5,count-1]));sheet=Image.new('RGB',(930,550),'#e8e9e3');d=ImageDraw.Draw(sheet);total=0;frames=[]
 for i in range(count):
  im.seek(i);im.load();dur=im.info.get('duration',0);assert dur>0;(w,h)=im.size;assert(w,h)==(620,500);total+=dur
  if i in samples:
   n=samples.index(i);pic=im.convert('RGB');pic.thumbnail((310,250));x=(n%3)*310;y=(n//3)*275;sheet.paste(pic,(x,y+22));d.text((x+8,y+5),f'{name}: exported frame {i+1}/{count}',fill='#172126')
 sheet.save(R/f'qa/gif-{name}-samples.png',optimize=True)
 out.append({'file':str(p.relative_to(R)),'framesDecoded':count,'size':[w,h],'totalDurationMs':total,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'allFramesDecoded':True})
coverage=json.loads((R/'qa/frame-coverage.json').read_text());records=coverage['records'];assert len(records)==616
(R/'qa/gif-checks.json').write_text(json.dumps({'reviewMediaOnly':True,'runtimeVerified':False,'gifCount':len(out),'totalFramesDecoded':sum(v['framesDecoded'] for v in out),'records':out},indent=2))
print('PASS: decoded all',sum(v['framesDecoded'] for v in out),'frames in 6 review GIFs.')
