from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path.cwd();BASE=ROOT/'tmp/cf6-combat-audio-20261017';OUT=BASE/'image-review2'
OUT.mkdir(exist_ok=False)
plan=json.loads((ROOT/'tools/cf6-headbot-assets/death-render-plan.json').read_text('utf8'))
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',20)
rows=[]
for family,row in plan.items():
    keys=['death-'+str(f) for f in row['frames']]+['death-left-'+str(row['mirrorFrame'])]
    page=Image.new('RGB',(1240,1720),(232,230,226));draw=ImageDraw.Draw(page)
    for i,key in enumerate(keys):
        p=BASE/'final-images'/family/(key+'.png');im=Image.open(p);bbox=im.getbbox()
        crop=im.crop((max(0,bbox[0]-15),max(0,bbox[1]-15),min(im.width,bbox[2]+15),min(im.height,bbox[3]+15)))
        assert crop.width<=620 and crop.height<=395
        x=(i%2)*620+(620-crop.width)//2;y=(i//2)*430+35
        page.paste(crop,(x,y),crop);draw.text(((i%2)*620+18,(i//2)*430+8),family+' '+key,fill='#222222',font=font)
        rows.append({'family':family,'key':key,'source':p.relative_to(BASE).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
            'reviewTransformation':'alpha composited onto neutral background; transparent margins cropped; native pixel scale retained'})
    page.save(OUT/(family+'.png'))
(OUT/'provenance.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'images':len(rows),'pages':3,'pixelScale':1}))
