from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import hashlib,json
TMP=Path(__file__).resolve().parent
out=TMP/'handoff-preview'
assert not out.exists(),'Preserve previous preview'
out.mkdir()
base=TMP/'final-images/elder/images'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24)
items=[('beam-29','普通红束：命中施加易伤'),('heavy-beam-52','蓄能重束：蓄力光提示'),('heavy-beam-53','蓄能重束：粗度 ×3，伤害 ×3')]
sheet=Image.new('RGB',(1100,900),(232,230,226));draw=ImageDraw.Draw(sheet)
sources=[]
for i,(name,label) in enumerate(items):
    path=base/(name+'.png');native=Image.open(path).convert('RGBA')
    bg=Image.new('RGBA',native.size,(232,230,226,255));bg.alpha_composite(native)
    # Same fixed native scale and camera on every row; only blank margins are cropped.
    crop=bg.convert('RGB').crop((0,70,1100,350))
    sheet.paste(crop,(0,300*i+20));draw.text((24,300*i+5),label,font=font,fill=(30,30,30))
    sources.append({'path':str(path.relative_to(TMP)).replace('\\','/'),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
sheet.save(out/'two-beams.png')
(out/'provenance.json').write_text(json.dumps({'source':'Actual Flash native captures; no generated or redrawn graphics','transform':'Alpha-composite on RGB(232,230,226), same 1100x280 crop from y=70..350 on each 1100x500 source; no rescaling','sources':sources},ensure_ascii=False,indent=2)+'\n','utf8')
print(str(out/'two-beams.png'))
