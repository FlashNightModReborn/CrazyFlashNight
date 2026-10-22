from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,numpy as np,hashlib
from xml.etree import ElementTree as ET
R=Path(__file__).resolve().parents[1];ids=[1404,1405,1414,1415,1817,1820,1821]
font=ImageFont.truetype(str(R/'reference/fonts/DejaVuSans.ttf'),15)
board=Image.new('RGB',(1280,1220),'#42454e');d=ImageDraw.Draw(board);y=18;stats=[]
for n in ids:
 a=Image.open(R/f'reference/{n}.png').convert('RGBA');b=Image.open(R/f'previews/street-{n}-native.png').convert('RGBA');delta=np.abs(np.array(a.getchannel('A')).astype(int)-np.array(b.getchannel('A')).astype(int))
 d.text((16,y),f'{n} original, native {a.width} x {a.height}',font=font,fill='white');d.text((656,y),f'{n} redraw, native {b.width} x {b.height}',font=font,fill='white');y+=24;board.paste(a,(16,y),a);board.paste(b,(656,y),b);y+=a.height+20
 svg=R/f'parts/bitmap-{n}.svg';rt=ET.parse(svg).getroot()
 stats.append({'bitmapId':n,'originalSize':list(a.size),'redrawNativeSize':list(b.size),'svgViewBox':rt.get('viewBox'),'alphaMaximumAbsoluteError':int(delta.max()),'alphaMeanAbsoluteError':float(delta.mean()),'alphaNonzeroMaskIdentical':bool(np.array_equal(np.array(a.getchannel('A'))>0,np.array(b.getchannel('A'))>0)),'sha256':hashlib.sha256(svg.read_bytes()).hexdigest()})
 # Detail is the same native canvas shown at 4x on each side.
 old=a.resize((a.width*4,a.height*4),Image.Resampling.BICUBIC);new=Image.open(R/f'previews/street-{n}-4x.png').convert('RGBA')
 if n!=1817:
  bb=Image.new('RGB',(old.width*2+60,old.height+76),'#42454e');dd=ImageDraw.Draw(bb);dd.text((20,12),f'{n} original 4x',font=font,fill='white');dd.text((old.width+40,12),f'{n} redraw 4x',font=font,fill='white');bb.paste(old,(20,46),old);bb.paste(new,(old.width+40,46),new);bb.save(R/f'qa/street-{n}-same-scale-detail.png')
board.crop((0,0,1280,y)).save(R/'qa/street-second-native-comparison.png')
R.joinpath('qa/street-alpha-dimension-check.json').write_text(json.dumps(stats,indent=2))
print(json.dumps(stats,indent=2))
