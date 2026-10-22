"""Original-coordinate asphalt1786: deterministic multi-scale mineral aggregate and editable worn lane paint."""
from pathlib import Path
import numpy as np,io,base64,json,hashlib
from PIL import Image,ImageDraw
from scipy.ndimage import gaussian_filter
from svg_native import write_part,render
R=Path(__file__).resolve().parents[1];rng=np.random.default_rng(1786);W,H=652,432
def noise(size):return np.array(Image.fromarray(rng.uniform(0,255,size).astype('uint8')).resize((W,H),Image.Resampling.BICUBIC),dtype=float)/255-.5
fine=noise((432,652));mid=noise((96,141));broad=noise((7,11));aggregate=noise((300,220));height=.18*mid+.12*fine+.7*aggregate;dy,dx=np.gradient(height)
y=np.linspace(0,1,H)[:,None];base=48+65*y +8*broad+10*mid+12*fine+30*aggregate +95*(-dy)
# paired mineral ridges and dark micro-pits, irregular rather than lined brush grain.
pit=rng.random((H,W));base+=np.where(pit>.986,15,np.where(pit<.015,-14,0));base+=noise((42,58))*4
rgb=np.stack([base*1.08,base*1.035,base],axis=-1);im=Image.fromarray(np.uint8(np.clip(rgb,0,255)));b=io.BytesIO();im.save(b,format='PNG');data=base64.b64encode(b.getvalue()).decode()
s='<defs><linearGradient id="paint" x2="0" y2="1"><stop stop-color="#b8b6ac"/><stop offset="1" stop-color="#a09f97"/></linearGradient><filter id="wear" color-interpolation-filters="sRGB"><feTurbulence baseFrequency=".8" numOctaves="2" seed="786" result="grain"/><feColorMatrix in="grain" type="matrix" values="0 0 0 0 .2 0 0 0 0 .2 0 0 0 0 .18 .9 0 0 0 -.32"/><feComposite in2="SourceGraphic" operator="in"/></filter></defs>'
s+=f'<image width="326" height="216" href="data:image/png;base64,{data}"/>'
for d in ['M9 103H135L146 117H20Z','M174 103H303L313 117H184Z']:
 s+=f'<path d="{d}" fill="url(#paint)" opacity=".88"/><path d="{d}" fill="#9f9e93" filter="url(#wear)" opacity=".25"/>'
p=write_part(R/'parts/bitmap-1786.svg',[0,0,326,216],s);render(p,978,R/'previews/asphalt-new.png')
o=Image.new('RGB',(978*2,648+30),'#252825');d=ImageDraw.Draw(o)
for j,a in enumerate([Image.open(R/'reference/1786.png').resize((978,648)),Image.open(R/'previews/asphalt-new.png')]):o.paste(a,(j*978,30));d.text((j*978+8,8),['ORIGINAL1786','R1 / MULTISCALE ASPHALT'][j],fill='white')
o.save(R/'previews/asphalt-original-new.png')
(R/'qa/asphalt-method.json').write_text(json.dumps({'seed':1786,'native':[326,216],'generatedTexture':[652,432],'method':'Deterministic mineral relief, paired bright grains and dark pits; SVG lane markings in original coordinates; no original RGB sampling','sha256':hashlib.sha256(p.read_bytes()).hexdigest()},indent=2))
