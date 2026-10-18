from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib,sys
TMP=Path(__file__).resolve().parent
base=TMP/sys.argv[1]
dest=TMP/sys.argv[2]
assert not dest.exists(),'Preserve existing preview'
dest.mkdir()
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
records=[]
for actor in ['headbot','elder','bladebot']:
    folder=base/actor/'images'
    if not folder.exists():continue
    files=sorted(folder.glob('*.png'))
    for page in range((len(files)+5)//6):
        selected=files[page*6:page*6+6]
        sheet=Image.new('RGB',(1120,850),(232,230,226));draw=ImageDraw.Draw(sheet)
        for i,p in enumerate(selected):
            native=Image.open(p).convert('RGBA')
            bg=Image.new('RGBA',native.size,(232,230,226,255));bg.alpha_composite(native)
            preview=bg.convert('RGB');preview.thumbnail((550,250),Image.Resampling.LANCZOS)
            x=10+(i%2)*560;y=12+(i//2)*280
            draw.text((x,y),actor+' / '+p.stem,font=font,fill=(25,25,25))
            sheet.paste(preview,(x,y+25))
        out=dest/(actor+f'-{page+1}.png');sheet.save(out)
        records.append({'preview':out.name,'sources':[{'path':str(p.relative_to(TMP)).replace('\\','/'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in selected]})
(dest/'provenance.json').write_text(json.dumps({'purpose':'Review-only contact sheets; original native PNGs are unmodified','transform':'Native RGBA composed on RGB(232,230,226), reduced to fit 550x250, filename labels outside each image','sheets':records},ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'directory':str(dest),'sheets':[r['preview'] for r in records]},ensure_ascii=False))
