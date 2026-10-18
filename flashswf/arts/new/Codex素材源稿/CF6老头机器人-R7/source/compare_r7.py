from pathlib import Path
from PIL import Image,ImageDraw,ImageChops
import json,hashlib
R=Path(__file__).resolve().parents[1];OLD=R/'reference/frozen-r6'
def board(ids,name,w=650,h=700):
 out=Image.new('RGB',(w*3,h*len(ids)),'#dedbd3');d=ImageDraw.Draw(out)
 for row,sid in enumerate(ids):
  for col,path in enumerate([R/f'reference/shapes/{sid}.png',OLD/f'parts/{sid}.png',R/f'parts/{sid}.png']):
   im=Image.open(path).convert('RGBA');sc=min((w-30)/im.width,(h-65)/im.height);im=im.resize((round(im.width*sc),round(im.height*sc)),Image.Resampling.LANCZOS);out.paste(im,(col*w+(w-im.width)//2,row*h+50),im);d.text((col*w+15,row*h+18),f'{sid} | '+['ORIGINAL','R6 FROZEN','R7 TORN LEG ONLY'][col],fill='black')
 out.save(R/f'previews/{name}.png')


board([981],'leg-original-r6-r7',600,790)

out=Image.new('RGB',(2100,1050),'#dedbd3');d=ImageDraw.Draw(out)
for i,path in enumerate([R/'qa/frames/original/stand-001.png',OLD/'qa/frames/candidate/stand-001.png',R/'qa/frames/candidate/stand-001.png']):
 im=Image.open(path).convert('RGBA');sc=min(680/im.width,980/im.height);im=im.resize((round(im.width*sc),round(im.height*sc)),Image.Resampling.LANCZOS);out.paste(im,(i*700+(700-im.width)//2,55),im);d.text((i*700+20,20),['ORIGINAL','R6 FROZEN','R7 TORN LEG ONLY'][i],fill='black')
out.save(R/'previews/stand-original-r6-r7.png')
checks=[]
for n in range(977,990):
 a=Image.open(OLD/f'parts/{n}.png').convert('RGBA');b=Image.open(R/f'parts/{n}.png').convert('RGBA');ext=ImageChops.difference(a,b).getextrema();checks.append({'id':n,'RGBChanged':any(v[1]>0 for v in ext[:3]),'alphaUnchanged':ext[3]==(0,0),'SVGsha256':hashlib.sha256((R/f'parts/{n}.svg').read_bytes()).hexdigest()})
(R/'qa/r7-local-validation.json').write_text(json.dumps({'parts':checks,'standingFramesRendered':1,'batch377':False,'batch283':False,'ASExecuted':False},indent=2))
# User-requested original / R6 standing pair.
out=Image.new('RGB',(1400,1050),'#dedbd3');d=ImageDraw.Draw(out)
for i,path in enumerate([R/'qa/frames/original/stand-001.png',R/'qa/frames/candidate/stand-001.png']):
 im=Image.open(path).convert('RGBA');sc=min(680/im.width,980/im.height);im=im.resize((round(im.width*sc),round(im.height*sc)),Image.Resampling.LANCZOS);out.paste(im,(i*700+(700-im.width)//2,55),im);d.text((i*700+20,20),['ORIGINAL','R7 TORN LEG ONLY'][i],fill='black')
out.save(R/'previews/stand-original-r7.png')
