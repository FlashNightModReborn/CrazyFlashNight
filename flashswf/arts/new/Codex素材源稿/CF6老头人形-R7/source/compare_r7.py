from pathlib import Path
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1]
def row(paths,label,w,h):
 b=Image.new('RGB',(w*len(paths),h),'#e4e2d8');d=ImageDraw.Draw(b);ims=[Image.open(p).convert('RGBA') for p in paths];sw,sh=ims[0].size;sc=min((w-24)/sw,(h-40)/sh)
 for i,im in enumerate(ims):
  im=im.resize((round(sw*sc),round(sh*sc)),Image.Resampling.LANCZOS);b.paste(im,(i*w+(w-im.width)//2,32+(h-40-im.height)//2),im);d.text((i*w+10,9),label+' | '+(['ORIGINAL','R6','R7'][i] if len(paths)==3 else ['ORIGINAL','R7'][i]),fill='#232820')
 return b
row([R/'reference/shapes/963.png',R/'reference/r6-review/963.png',R/'parts/963.png'],'HEAD 963',460,650).save(R/'previews/original-r6-r7-head.png')
row([R/'qa/frames/original/stand-001.png',R/'qa/frames/candidate/stand-001.png'],'STAND',550,820).save(R/'previews/original-r7-stand.png')

paths=[R/'reference/shapes/963.png',R/'reference/r6-review/963.png',R/'parts/963.png']
c=Image.new('RGB',(1140,490),'#e4e2d8');d=ImageDraw.Draw(c)
for i,p in enumerate(paths):
 im=Image.open(p).convert('RGBA').crop((145,125,204,205));im=im.resize((342,464),Image.Resampling.NEAREST if i==0 else Image.Resampling.LANCZOS);c.paste(im,(i*380+19,26),im);d.text((i*380+10,8),['ORIGINAL','R6','R7'][i]+' RIGHT ORBIT',fill='black')
c.save(R/'previews/original-r6-r7-eye.png')
