from pathlib import Path
from PIL import Image,ImageDraw
import json,subprocess,sys
R=Path(__file__).resolve().parents[1]
C=json.loads((R/'qa/frame-coverage.json').read_text());records={(r['sequence'],r['frame']):r for r in C['records']};names={595:'stand',596:'walk',597:'hit',598:'grabbed',599:'612-knockdown',611:'death',874:'888-attack',875:'888-knockdown',887:'transform'}
(R/'previews').mkdir(exist_ok=True)
subprocess.run(['inkscape',str(R/'parts/atlas581.svg'),'--export-filename='+str(R/'previews/atlas581.png')],check=True,capture_output=True)
subprocess.run([sys.executable,str(R/'source/preview_stand.py')],check=True)
def png(sid,frame,v='candidate'):return R/f'qa/frames/{v}/{sid}-{frame:03d}.png'
def board(keys,name,cols=4):
 cw,ch=380,320;out=Image.new('RGB',(cw*cols,ch*((len(keys)+cols-1)//cols)),'#e8e9e3');d=ImageDraw.Draw(out)
 for n,(sid,f) in enumerate(keys):
  x=n%cols*cw;y=n//cols*ch;d.text((x+8,y+7),f'{names[sid]} {f:03d} | original / R2',fill='#172126')
  ims=[Image.open(png(sid,f,v)).convert('RGBA') for v in ['original','candidate']];bb=[im.getbbox() for im in ims];bb=[b for b in bb if b]
  if not bb:d.text((x+15,y+90),'SOURCE DISPLAY LIST EMPTY',fill='#4c575b');continue
  crop=(max(0,min(b[0] for b in bb)-6),max(0,min(b[1] for b in bb)-6),min(ims[0].width,max(b[2] for b in bb)+6),min(ims[0].height,max(b[3] for b in bb)+6))
  for k,im in enumerate(ims):
   im=im.crop(crop);im.thumbnail((cw//2-8,ch-33),Image.Resampling.LANCZOS);out.paste(im,(x+k*cw//2+(cw//2-im.width)//2,y+28+(ch-31-im.height)//2),im)
 out.save(R/f'previews/{name}.png',optimize=True)
for sid in names:
 kk=sorted(k for k,r in records.items() if k[0]==sid and 'original' in r['files'])
 board(kk,f'{sid}-{names[sid]}-comparison',3 if sid in [611,887] else 4)
branches=[('a0',1,31),('a1',32,77),('a2',78,112)]
for label,start,end in branches:board(sorted(k for k,r in records.items() if k[0]==611 and start<=k[1]<=end and 'original' in r['files']),f'death-{label}-comparison',3)
# A compact joint-focused contact retains equal source/candidate scaling per pair.
kk=[]
for sid,f in [(596,8),(596,16),(874,21),(874,43),(599,29),(611,40),(611,50),(887,40)]:
 if (sid,f) in records and 'original' in records[(sid,f)]['files']:kk.append((sid,f))
board(kk,'joint-action-comparison',3)
def makegif(seqs,name):
 ims=[];dur=[]
 for sid,start,end,label in seqs:
  # Union cropping is fixed for each whole sequence/branch, never per frame.
  raw=[Image.open(png(sid,f)).convert('RGBA') for f in range(start,end+1)];bb=[im.getbbox() for im in raw if im.getbbox()]
  crop=(max(0,min(b[0] for b in bb)-10),max(0,min(b[1] for b in bb)-10),min(raw[0].width,max(b[2] for b in bb)+10),min(raw[0].height,max(b[3] for b in bb)+10))
  for f,im in zip(range(start,end+1),raw):
   canvas=Image.new('RGB',(620,500),'#e8e9e3');d=ImageDraw.Draw(canvas);d.text((12,9),f'CF6 bald guard R2 | {label} | {f:03d}',fill='#172126');d.text((12,27),'Original placement matrices; static reconstruction, not gameplay.',fill='#536066');im=im.crop(crop);im.thumbnail((600,445),Image.Resampling.LANCZOS);canvas.paste(im,((620-im.width)//2,48+(445-im.height)//2),im);ims.append(canvas.convert('P',palette=Image.Palette.ADAPTIVE,colors=128));dur.append([30,30,40][(f-1)%3])
  dur[-1]=650
 out=R/f'previews/{name}.gif';ims[0].save(out,save_all=True,append_images=ims[1:],duration=dur,loop=0,disposal=2,optimize=True);print(out.name,out.stat().st_size,flush=True)
for label,a,b in branches:makegif([(611,a,b,'death '+label)],'death-'+label)
makegif([(887,1,75,'transformation 887 (includes five original blank frames)')],'transform-887')
# Separate independent files keep everyday attachment sizes below 15 MB.
makegif([(sid,1,len([k for k in records if k[0]==sid]),names[sid]) for sid in [595,596,597,598,874]],'live-actions')
makegif([(sid,1,len([k for k in records if k[0]==sid]),names[sid]) for sid in [599,875]],'knockdown-variants')
(R/'qa/preview-build.json').write_text(json.dumps({'gifFpsApproximation':'30/30/40 ms cadence at source 30 fps, 650 ms branch-end review pause','constantCropWithinSequence':True,'sourceBlankTailRetained':True,'files':[{'file':str(p.relative_to(R)),'bytes':p.stat().st_size} for p in sorted((R/'previews').glob('*')) if p.suffix in ['.png','.gif']]},indent=2))
