from PIL import Image,ImageDraw
from pathlib import Path
R=Path(__file__).resolve().parents[1]
a=Image.open(R/'reference/original-1580.png').convert('RGB').resize((1200,678));b=Image.open(R/'previews/background-r4.png').convert('RGB').resize((1200,678));out=Image.new('RGB',(2400,718),'#dddddd');out.paste(a,(0,40));out.paste(b,(1200,40));d=ImageDraw.Draw(out);d.text((15,15),'CF6 ORIGINAL 1580 / 800 x 452',fill='black');d.text((1215,15),'R4 HYBRID CANDIDATE / SAME CAMERA',fill='black');out.save(R/'previews/background-original-r4.png')
