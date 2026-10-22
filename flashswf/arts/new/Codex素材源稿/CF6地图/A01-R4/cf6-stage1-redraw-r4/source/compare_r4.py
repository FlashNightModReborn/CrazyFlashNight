from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
def _cf6_font(size):
    # PATCHED(cf6-map-source): 硬编码 Linux 字体路径在 Windows 不存在；仅影响预览标注
    cands=[R/'reference/fonts'/'DejaVuSans.ttf']
    try:
        import matplotlib as _mpl, os as _os
        cands.append(Path(_os.path.join(_os.path.dirname(_mpl.__file__),'mpl-data','fonts','ttf','DejaVuSans.ttf')))
    except Exception:
        pass
    for _c in cands:
        if Path(_c).is_file():return ImageFont.truetype(str(_c),size)
    return ImageFont.load_default()
R=Path(__file__).resolve().parents[1];font=_cf6_font(20)
paths=[R/'reference/original-1580.png',R/'reference/frozen-previous/background-r3.png',R/'previews/background-r4.png']
ims=[Image.open(p).convert('RGB').resize((800,452),Image.Resampling.LANCZOS) for p in paths]
for name,b,scale in [('soil',(450,175,800,452),2),('transition',(180,190,650,452),1.5),('background',(0,0,800,452),1)]:
 w,h=int((b[2]-b[0])*scale),int((b[3]-b[1])*scale);out=Image.new('RGB',(w*3,h+36),'#202822');d=ImageDraw.Draw(out)
 for i,im in enumerate(ims):out.paste(im.crop(b).resize((w,h),Image.Resampling.LANCZOS),(w*i,36));d.text((w*i+8,7),['Original CF6','Frozen R3','R4 shared soil'][i],font=font,fill='white')
 out.save(R/f'previews/{name}-original-r3-r4.png')
paths=[R/'previews/scene-original.png',R/'reference/frozen-previous/scene-r3.png',R/'previews/scene-r4.png'];out=Image.new('RGB',(2400,488),'#202822');d=ImageDraw.Draw(out)
for i,p in enumerate(paths):out.paste(Image.open(p).convert('RGB').resize((800,452),Image.Resampling.LANCZOS),(i*800,36));d.text((i*800+8,7),['Original CF6','Frozen R3','R4 shared soil'][i],font=font,fill='white')
out.save(R/'previews/scene-original-r3-r4.png')
