"""Self-contained same-scale original / frozen R2 / R3 dozer-blade review.

No reference image pixels are used in the SVG artwork. This script only assembles
inspection boards, using retained inputs inside this deliverable.
"""
from pathlib import Path
from tempfile import TemporaryDirectory
from PIL import Image, ImageDraw, ImageFont
from svg_native import render
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
ROOT = Path(__file__).resolve().parents[1]
W,H=118,88
BG=(30,35,32,255)

def font(size):
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',size)

def board(images, crop, scale, output, subtitle):
    x0,y0,x1,y1=crop; w=(x1-x0)*scale;h=(y1-y0)*scale
    margin=18;gap=24;header=60
    out=Image.new('RGBA',(margin*2+w*3+gap*2,header+h+margin),BG)
    draw=ImageDraw.Draw(out)
    labels=['ORIGINAL','R2 / FROZEN','R3 / BLADE REVISION']
    for n,(im,label) in enumerate(zip(images,labels)):
        # All images arrive at 12x native dimensions. SVGs are independently
        # rendered at that scale, and original pixels use nearest-neighbour.
        region=im.crop(tuple(v*12 for v in crop))
        if scale!=12:region=region.resize((w,h),Image.Resampling.LANCZOS)
        xx=margin+n*(w+gap)
        out.alpha_composite(region,(xx,header))
        draw.text((xx,12),label,font=font(18),fill='#d2d7ca')
        draw.text((xx,36),subtitle,font=font(11),fill='#909a8b')
    out.convert('RGB').save(ROOT/'previews'/output)

def main():
    (ROOT/'previews').mkdir(exist_ok=True)
    original=Image.open(ROOT/'reference/wreck-props/1609.png').convert('RGBA')
    assert original.size==(W,H)
    original=original.resize((W*12,H*12),Image.Resampling.NEAREST)
    with TemporaryDirectory(prefix='cf6-blade-review-') as tmp:
        r2=Path(tmp)/'r2.png';r3=Path(tmp)/'r3.png'
        render(ROOT/'reference/frozen-previous/bitmap-1609-r2.svg',W*12,r2)
        render(ROOT/'parts/bitmap-1609.svg',W*12,r3)
        images=[original,Image.open(r2).convert('RGBA'),Image.open(r3).convert('RGBA')]
        assert all(im.size==(W*12,H*12) for im in images)
        board(images,(0,0,W,H),6,'blade-full-original-r2-r3.png',
              'Same 118 x 88 native frame / displayed at 6x')
        board(images,(49,67,90,88),12,'blade-detail-original-r2-r3.png',
              'Same crop x49-90, y67-88 / displayed at 12x')
        board(images,(49,65,W,H),9,'blade-chassis-original-r2-r3.png',
              'Same crop x49-118, y65-88 / displayed at 9x')
    print('Rebuilt self-contained original / R2 / R3 dozer-blade review boards.')

if __name__=='__main__':main()
