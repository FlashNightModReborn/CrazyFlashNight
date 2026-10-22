"""1746 grand double door: native editable vector, original 232 x 176 registration."""
from pathlib import Path
from svg_native import write_part,render
from PIL import Image,ImageDraw,ImageFont
import random,json
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
s='''<defs><linearGradient id="wood"><stop stop-color="#2d2815"/><stop offset=".28" stop-color="#514329"/><stop offset=".62" stop-color="#65532f"/><stop offset="1" stop-color="#3c321e"/></linearGradient><linearGradient id="panel" x2="0" y2="1"><stop stop-color="#352d1c"/><stop offset=".35" stop-color="#5b4928"/><stop offset="1" stop-color="#4a3c23"/></linearGradient><linearGradient id="inlay" x2=".25" y2="1"><stop stop-color="#6e6e5d"/><stop offset=".2" stop-color="#8c8b76"/><stop offset=".58" stop-color="#96937f"/><stop offset="1" stop-color="#7b7b69"/></linearGradient><linearGradient id="silver"><stop stop-color="#33382f"/><stop offset=".25" stop-color="#b2b4a3"/><stop offset=".5" stop-color="#e4dfc9"/><stop offset=".73" stop-color="#9c9f8e"/><stop offset="1" stop-color="#3c4137"/></linearGradient><linearGradient id="outer" x2="0" y2="1"><stop stop-color="#76613b"/><stop offset=".5" stop-color="#57462a"/><stop offset="1" stop-color="#302817"/></linearGradient></defs>'''
def path(d,fill,stroke=None,sw=1,op=1):return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' opacity="{op}"/>'
def rect(x,y,w,h,fill,stroke=None,sw=1):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>'
s+=rect(.7,.7,230.6,174.6,'url(#wood)','#16180e',1.4)
s+=path('M1 1H231L222 10H10Z','url(#outer)','#201c10',.9)+path('M1 1L10 10V175H1Z','#6e5936','#231f12',.8)+path('M231 1L222 10V175H231Z','#332c1b','#181b10',.8)
s+=path('M10 10H222M10 11.7H222','none','#9b8050',.6,.55)
# Side frames and the low, long upper transom. Inlays retain original grey-stone/glass appearance.
s+=rect(38,11,156,164,'url(#wood)','#17190e',1)
for x in [13.5,199.5]:
 for y,h in [(14,18),(36,32),(72,31),(107,30),(141,28)]:
  s+=rect(x,y,18.5,h,'#1b1d14','#0d130c',.8)
  s+=rect(x+1.5,y+1.7,15.5,h-3.2,'url(#inlay)')
  s+=path(f'M{x+1.8} {y+h-1.5}V{y+1.7}H{x+17}', 'none','#b0aa8d',.55,.5)
  s+=path(f'M{x+1.5} {y+h-1}H{x+18}V{y+1}', 'none','#514b31',1)
s+=rect(41.5,13.5,149.3,20,'#1b1d11','#10150d',.8)+rect(44,16,144.2,14.8,'url(#inlay)')
s+=path('M44 30.8V16H188.2','none','#bbb49a',.65,.5)
# Four recessed panels per leaf, fixed seam x116. Original doorway proportions are retained.
for row,(y,h) in enumerate([(41,25),(76,25),(111,25),(145,25)]):
 for x in [50.5,127.7]:
  s+=rect(x,y,53.8,h,'#262719','#171b10',.65)
  s+=path(f'M{x+.9} {y+.8}H{x+52.9}L{x+50.4} {y+3.1}H{x+3.3}V{y+h-2.5}L{x+.9} {y+h-.7}Z','#302918')
  s+=path(f'M{x+3.3} {y+h-2.5}H{x+50.4}V{y+3.1}L{x+52.9} {y+.8}V{y+h-.7}H{x+.9}Z','#80683b')
  s+=rect(x+4,y+3.6,45.7,h-7,'url(#panel)')
  s+=path(f'M{x+4} {y+3.6}V{y+h-3.4}H{x+49.7}','none','#b39150',.45,.44)
  grain=random.Random(1746+row*11+int(x))
  for k in range(7):
   gy=y+5.5+k*(h-11)/7;gx=x+5+grain.uniform(0,4);length=grain.uniform(24,38)
   s+=path(f'M{gx:.2f} {gy:.2f}q{length*.4:.2f} {grain.uniform(-1.1,1.1):.2f} {length:.2f} 0','none',grain.choice(['#8c7546','#252318']),grain.uniform(.25,.7),grain.uniform(.12,.22))

# Subtle short grain lines, not equal-length bright ruled lines.
rng=random.Random(1746)
for j in range(360):
 x=rng.uniform(40,193);y=rng.uniform(36,173);length=rng.uniform(.8,5)
 if 106<x<125 and 90<y<130:continue
 s+=path(f'M{x:.2f} {y:.2f}q{length/2:.2f} {-rng.uniform(.1,.5):.2f} {length:.2f} 0','none',rng.choice(['#211f13','#ab8850']),rng.uniform(.12,.32),rng.uniform(.05,.13))
for y in [70.4,105.2,140.1]:s+=path(f'M39 {y}H193','none','#241f13',1)+path(f'M39 {y+1}H193','none','#8b7142',.5,.6)
s+=path('M116 36V174','none','#15190e',1.4)+path('M117 36V174','none','#987b43',.6,.5)
# Twin vertical handle mounts. Dark backplates, pale metal grips and stepped lower pulls.
for x in [109.5,121.5]:
 s+=path(f'M{x-2.4} 95Q{x} 91.6 {x+2.5} 95L{x+2.6} 111Q{x+2.3} 113 {x+1.5} 114V123Q{x+3} 126.6 {x} 128Q{x-3} 127 {x-1.7} 123V114L{x-2.6} 112Z','#111810','#080f09',.7)
 s+=path(f'M{x-1.6} 96Q{x} 94.2 {x+1.7} 96V109.5H{x-1.6}Z','url(#silver)','#6e7564',.4)
 s+=rect(x-1.6,110,3.3,1.7,'url(#silver)')
 s+=path(f'M{x-.9} 114V122.6H{x+.9}V114Z','url(#silver)')
 for yy in [116.1,119.4,123.2]:s+=path(f'M{x-1.3} {yy}Q{x} {yy+.7} {x+1.3} {yy}','none','#969d8b',.7)
 s+=path(f'M{x-1.4} 125.5Q{x} 127 {x+1.4} 125.5','none','#949a86',.7)
s+=path('M1 175H231','none','#13170d',1.5)
p=write_part(R/'parts/bitmap-1746.svg',[0,0,232,176],s);render(p,928,R/'previews/grand-door-new-4x.png')
old=Image.open(R/'reference/bitmap-1746-original.png').convert('RGBA').resize((928,704),Image.Resampling.NEAREST);new=Image.open(R/'previews/grand-door-new-4x.png').convert('RGBA')
out=Image.new('RGB',(1856,744),'#35372f');out.paste(old,(0,40),old);out.paste(new,(928,40),new);d=ImageDraw.Draw(out);f=_cf6_font(20);d.text((12,10),'ORIGINAL 1746 / 232 x 176',font=f,fill='white');d.text((940,10),'R1 / SAME NATIVE COORDINATES',font=f,fill='white');out.save(R/'previews/grand-door-original-new.png')
print('Rebuilt 1746 grand door native vector')
