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
R=Path(__file__).resolve().parents[1];font=_cf6_font(16)
for cid,frames in [(1714,[1,4,9]),(1720,[1,25,90,150,174]),(1729,[1,25,50,90,130,150,174]),(1736,[1,7,10,13,16])]:
 w,h=(380,200) if cid==1736 else (340,520) if cid==1729 else (340,480);out=Image.new('RGB',(w*len(frames),(h+32)*2),'#343a35');d=ImageDraw.Draw(out)
 for row,mode in enumerate(['original','new']):
  for j,f in enumerate(frames):
   im=Image.open(R/f'previews/state-{cid}-f{f}-{mode}.png').convert('RGBA').resize((w,h));out.paste(im,(j*w,row*(h+32)+32),im);d.text((j*w+8,row*(h+32)+8),f'{mode.upper()} / {cid} FRAME {f}',font=font,fill='white')
 out.save(R/f'previews/states-{cid}-original-new.png')
