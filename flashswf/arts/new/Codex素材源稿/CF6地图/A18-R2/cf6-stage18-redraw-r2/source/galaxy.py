"""Seeded original-layout galaxy window texture; independent generated RGB, editable framing."""
from pathlib import Path
import numpy as np,io,base64,json
from PIL import Image,ImageDraw
from scipy.ndimage import gaussian_filter
from svg_native import write_part,render
R=Path(__file__).resolve().parents[1];rng=np.random.default_rng(1955);W,H=1200,400
Y,X=np.mgrid[:H,:W];x=X/2-337;y=Y/2-58;t=np.deg2rad(57);u=x*np.cos(t)+y*np.sin(t);v=-x*np.sin(t)+y*np.cos(t);rr=np.sqrt((u/210)**2+(v/75)**2);ang=np.arctan2(v/75,u/210)
def noise(h,w):return np.array(Image.fromarray(rng.uniform(0,255,(h,w)).astype('uint8')).resize((W,H),Image.Resampling.BICUBIC))/255-.5
fine=noise(H,W);mid=noise(100,300);large=noise(15,45)
spiral=(.5+.5*np.sin(ang*2-rr*7+large*.8))**2
arms=np.exp(-rr*1.2)*np.exp(-np.maximum(0,.18-rr)*30)*spiral*(.35+np.clip(mid+.3,0,1)*2)
arms=gaussian_filter(arms,1.6)*(0.7+np.clip(large+.5,0,1))
core=np.exp(-((u/48)**2+(v/30)**2))*68+np.exp(-rr*1.9)*29+np.exp(-((x/4.5)**2+(y/4.5)**2))*190
base=3+5*(large+.5);rgb=np.stack([base+arms*47+core*1.05,base+arms*63+core*1.05,base+arms*84+core*.75],-1)
# Tiny uneven star populations concentrated into spiral dust, with sparse field stars.
rand=rng.random((H,W));stars=rand<(0.004+arms*.075);brightness=rng.uniform(25,200,(H,W))*stars;warm=rng.random((H,W));rgb+=np.stack([brightness*(.75+.3*warm),brightness*(.85+.2*warm),brightness*(1.1-.5*warm)],-1)
rgb+=gaussian_filter(brightness,.7)[...,None]*.55;rgb+=fine[...,None]*4
im=Image.fromarray(np.uint8(np.clip(rgb,0,255)));b=io.BytesIO();im.save(b,format='PNG');data=base64.b64encode(b.getvalue()).decode()
s=f'<image width="600" height="200" href="data:image/png;base64,{data}"/><path d="M0 45L31 91L97 138L0 181Z" fill="#000"/>'
p=write_part(R/'parts/bitmap-1955.svg',[0,0,600,200],s);render(p,1200,R/'previews/galaxy-new.png');o=Image.new('RGB',(1200,840),'#242b2e');d=ImageDraw.Draw(o)
for j,im in enumerate([Image.open(R/'reference/1955.png').resize((1200,400)),Image.open(R/'previews/galaxy-new.png')]):o.paste(im,(0,j*420+20));d.text((8,j*420+3),['ORIGINAL1955','R1 / SEEDED GALAXY TEXTURE + EDITABLE FRAME'][j],fill='white')
o.save(R/'previews/galaxy-original-new.png');(R/'qa/galaxy-method.json').write_text(json.dumps({'seed':1955,'native':[600,200],'generatedPixels':[1200,400],'originalRGBReused':False,'method':'elliptical spiral density, multiscale independent cloud noise, density-weighted star populations; manually observed black frame silhouette'},indent=2))
