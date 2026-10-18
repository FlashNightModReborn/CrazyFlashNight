from pathlib import Path
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];BG='#e6e4db';LABELS=['ORIGINAL','R2 FROZEN','R3 CROWN + INTAKES']
def panel(images,name,size):
 out=Image.new('RGB',(size[0]*3,size[1]),BG);d=ImageDraw.Draw(out)
 for j,im in enumerate(images):
  d.text((j*size[0]+12,10),LABELS[j],fill='#222a21');im=im.copy();im.thumbnail((size[0]-24,size[1]-40));out.paste(im,(j*size[0]+(size[0]-im.width)//2,32+(size[1]-40-im.height)//2),im)
 out.save(R/'previews'/name)
def load(p):return Image.open(R/p).convert('RGBA')
body=[load('reference/shapes/929.png'),load('reference/r2-review/929.png'),load('parts/929.png')]
panel(body,'body-original-r2-r3.png',(550,890))
panel([im.crop((25,0,467,180)) for im in body],'crown-original-r2-r3.png',(500,260))
panel([im.crop((108,345,534,501)) for im in body],'intakes-original-r2-r3.png',(600,300))
panel([im.crop((108,345,270,501)).resize((486,468)) for im in body],'intake-left-original-r2-r3.png',(510,510))
panel([im.crop((411,348,534,483)).resize((369,405)) for im in body],'intake-right-original-r2-r3.png',(390,450))
panel([load('qa/frames/original/stand-walk-001.png'),load('reference/r2-review/stand.png'),load('qa/frames/candidate/stand-walk-001.png')],'stand-original-r2-r3.png',(540,720))
