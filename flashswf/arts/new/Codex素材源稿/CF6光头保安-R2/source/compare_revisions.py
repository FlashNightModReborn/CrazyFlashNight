from pathlib import Path
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];OLD=R/'reference/revision-r1'
A=Image.open(R/'reference/581.png').convert('RGBA');B=Image.open(OLD/'previews/atlas581.png').convert('RGBA');C=Image.open(R/'previews/atlas581.png').convert('RGBA')
for name,crop,scale in [('face',(225,0,295,86),6),('jacket',(0,8,140,251),4)]:
 w=(crop[2]-crop[0])*scale;h=(crop[3]-crop[1])*scale;out=Image.new('RGB',(w*3,h+40),'#e8e9e3');d=ImageDraw.Draw(out)
 for i,(im,s) in enumerate([(A,1),(B,3),(C,3)]):
  cell=im.crop(tuple(v*s for v in crop)).resize((w,h),Image.Resampling.LANCZOS);out.paste(cell,(i*w,40),cell);d.text((i*w+12,12),['ORIGINAL','R1','R2 REFINEMENT'][i],fill='#142023')
 out.save(R/f'previews/{name}-original-r1-r2.png')
ims=[Image.open(p).convert('RGBA') for p in [R/'previews/stand-original.png',OLD/'previews/stand-candidate.png',R/'previews/stand-candidate.png']];bbs=[im.getbbox() for im in ims];crop=(min(b[0] for b in bbs)-10,min(b[1] for b in bbs)-10,max(b[2] for b in bbs)+10,max(b[3] for b in bbs)+10);w=crop[2]-crop[0];h=crop[3]-crop[1];out=Image.new('RGB',(w*3,h+40),'#e8e9e3');d=ImageDraw.Draw(out)
for i,im in enumerate(ims):im=im.crop(crop);out.paste(im,(i*w,40),im);d.text((i*w+12,12),['ORIGINAL','R1','R2 REFINEMENT'][i],fill='#142023')
out.save(R/'previews/stand-original-r1-r2.png')
