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
R=Path(__file__).resolve().parents[1];font=_cf6_font(18)
for name,files in [('cars',['car-1602-original-new.png','car-1603-original-new.png','car-1604-original-new.png']),('wrecks',[f'wreck-{n}-comparison.png' for n in [1606,1607,1608,1609]])]:
 ims=[]
 for f in files:
  im=Image.open(R/'previews'/f).convert('RGB');im.resize((1200,round(im.height*1200/im.width)));ims.append(im.resize((1200,round(im.height*1200/im.width))))
 out=Image.new('RGB',(1200,sum(im.height+26 for im in ims)),'#202822');d=ImageDraw.Draw(out);y=0
 for f,im in zip(files,ims):d.text((8,y+3),f.split('-')[1],font=font,fill='white');out.paste(im,(0,y+26));y+=im.height+26
 out.save(R/f'previews/{name}-original-new-board.png')
