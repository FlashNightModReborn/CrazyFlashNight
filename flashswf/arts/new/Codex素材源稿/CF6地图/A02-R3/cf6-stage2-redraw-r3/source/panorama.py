"""Art overview: fixed root parallax phase, world geometry unscaled.
Sky-only horizontal extension is a preview convention, not a runtime camera.
"""
from pathlib import Path
from svg_native import assemble,render
from PIL import Image,ImageDraw,ImageFont
import json
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
R=Path(__file__).resolve().parents[1]
VB=[0,0,1250,450]; sx=1.000030517578125
for mode in ['original','new']:
 sky=R/'parts/shape-1596.svg' if mode=='new' else R/'reference/original-shapes/1596.svg'
 city=R/'parts/shape-1598.svg' if mode=='new' else R/'reference/original-shapes/1598.svg'
 crate=R/'reference/stage1-crate/prop-1442.svg' if mode=='new' else R/'reference/original-shapes/prop-1442.svg'
 layers=[{'path':sky,'matrix':[VB[2]/600,0,0,1,VB[0],0]}, {'path':city,'matrix':[1,0,0,1,-.75,-1]}, {'path':R/f'previews/background-{mode}.svg','matrix':[sx,0,0,1,673.5*sx,207.1]}, {'path':crate,'matrix':[sx,0,0,1,488.55*sx,274.4]}]
 p=assemble(VB,layers,R/f'previews/panorama-{mode}.svg');render(p,2500)
font=_cf6_font(21)
for mode in ['original','new']:
 im=Image.open(R/f'previews/panorama-{mode}.png').convert('RGB');out=Image.new('RGB',(im.width,im.height+74),'#202822');out.paste(im,(0,74));d=ImageDraw.Draw(out);d.text((18,9),('ORIGINAL CF6' if mode=='original' else 'R3 / SECOND PLAYABLE STAGE A2')+' | COMPLETE WORLD OVERVIEW',font=font,fill='white');d.text((18,40),'Fixed initial city phase; sky extended horizontally for overview only. Not a game screenshot.',font=font,fill='#c3c8c0');out.save(R/f'previews/panorama-{mode}-labelled.png')
a=Image.open(R/'previews/panorama-original-labelled.png');b=Image.open(R/'previews/panorama-new-labelled.png');out=Image.new('RGB',(a.width,a.height*2));out.paste(a,(0,0));out.paste(b,(0,a.height));out.save(R/'previews/panorama-original-r3.png')
(R/'qa/panorama-registration.json').write_text(json.dumps({'viewBox':VB,'worldScaleX':sx,'worldTranslation':[673.5*sx,207.1],'cityPhase':[-.75,-1],'skyPreviewOnlyHorizontalScale':VB[2]/600,'logicalWorld':[1250,450],'runtimeScreenshot':False,'foregroundRescaledOrRearranged':False},indent=2))
