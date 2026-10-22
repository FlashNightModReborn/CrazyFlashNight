"""CF6 a18-a22 shared industrial wall, floor, and decals.

All structural RGB artwork is manually authored SVG in original native coordinates.
The original alpha channel is retained as a coverage/registration contract only.
Original RGB is never sampled, vectorized, embedded, recolored or upscaled into art.
Surface grain is independently synthesized from deterministic multiscale noise.
Original references are project-local and used for alpha/QA, not RGB reconstruction.
Run: python source/industrial_materials.py [--no-render]
"""
from pathlib import Path
import argparse,base64,hashlib,io,json,math
import numpy as np
from PIL import Image,ImageDraw
from svg_native import write_part,render,inner
ROOT=Path(__file__).resolve().parents[1]
IDS=[1231,1957,1958,1962,1964,1965,1966]

def f(v):return ('%.4f'%v).rstrip('0').rstrip('.')
def rect(x,y,w,h,c,op=1,extra=''):
 return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" fill="{c}" opacity="{f(op)}" {extra}/>'
def path(d,c='none',stroke=None,sw=.6,op=1,extra=''):
 return f'<path d="{d}" fill="{c}" opacity="{f(op)}"'+(f' stroke="{stroke}" stroke-width="{f(sw)}" stroke-linejoin="round"' if stroke else '')+f' {extra}/>'
def line(x,y,xx,yy,c,sw=.5,op=1):return path(f'M{f(x)} {f(y)}L{f(xx)} {f(yy)}','none',c,sw,op)
def poly(p,c,stroke=None,sw=.6,op=1):return path('M'+'L'.join(f'{f(x)} {f(y)}' for x,y in p)+'Z',c,stroke,sw,op)
def ellipse(x,y,rx,ry,c,op=1,extra=''):
 return f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rx)}" ry="{f(ry)}" fill="{c}" opacity="{f(op)}" {extra}/>'
def grad(id,cols,x1=0,y1=0,x2=0,y2=1):
 return f'<linearGradient id="{id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'+''.join(f'<stop offset="{off}" stop-color="{col}"/>' for off,col in cols)+'</linearGradient>'
def rgb(v):return '#'+''.join('%02x'%max(0,min(255,round(x))) for x in v)
def alpha(n):
 a=np.array(Image.open(ROOT/f'reference/{n}.png').getchannel('A'));h,w=a.shape;d={}
 if np.all(a==255):return f'<mask id="coverage" maskUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{h}">'+rect(0,0,w,h,'#fff')+'</mask>'
 for y,row in enumerate(a):
  edges=np.r_[0,np.flatnonzero(row[1:]!=row[:-1])+1,w]
  for l,r in zip(edges[:-1],edges[1:]):
   v=int(row[l])
   if v:d.setdefault(v,[]).append(f'M{l} {y}h{r-l}v1h{l-r}Z')
 return f'<mask id="coverage" maskUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{h}" style="mask-type:alpha">'+''.join('<path d="'+''.join(p)+f'" fill="#fff" opacity="{(v-.5 if v==254 else v)/255:.9f}"/>' for v,p in sorted(d.items()))+'</mask>'
def noise(w,h,seed,scale=4):
 rng=np.random.default_rng(seed);W,H=w*scale,h*scale
 def nn(nx,ny):
  return np.array(Image.fromarray(rng.normal(0,1,(max(2,ny),max(2,nx))).astype('float32'),'F').resize((W,H),Image.Resampling.BICUBIC))
 a=.42*nn(w//24,h//24)+.25*nn(w//8,h//8)+.13*nn(w//3,h//3)+.07*nn(w,h)+.035*rng.normal(0,1,(H,W))
 return np.clip(a,-1.7,1.7)
def image_data(a):
 b=io.BytesIO();Image.fromarray(a.astype('uint8'),'RGBA').save(b,format='PNG',optimize=True);return base64.b64encode(b.getvalue()).decode()
def grain(id,w,h,seed,strength=.5):
 a=noise(w,h,seed);rgb0=np.where((a>0)[...,None],[204,205,195],[9,10,8]);rgba=np.dstack([rgb0,np.minimum(abs(a)*55*strength,65)])
 return f'<pattern id="{id}" patternUnits="userSpaceOnUse" width="{w}" height="{h}"><image width="{w}" height="{h}" href="data:image/png;base64,{image_data(rgba)}"/></pattern>'
def start(n,defs=''):
 w,h=Image.open(ROOT/f'reference/{n}.png').size
 return '<defs>'+alpha(n)+defs+f'<clipPath id="nativeBounds">{rect(0,0,w,h,"#fff")}</clipPath></defs><g id="new-native-art" mask="url(#coverage)" clip-path="url(#nativeBounds)">'
def finish(n,s,do_render=True):
 w,h=Image.open(ROOT/f'reference/{n}.png').size
 p=write_part(ROOT/f'parts/bitmap-{n}.svg',[0,0,w,h],s+'</g>')
 if do_render:
  render(p,w*4,ROOT/f'previews/industrial-{n}-4x.png');render(p,w,ROOT/f'previews/industrial-{n}-native.png')
 return p

def wall(do_render):
 n=1231;w,h=482,166
 defs=grad('wall',[(0,'#6c6663'),(.35,'#5d5754'),(1,'#3d3b35')])
 defs+=grad('rib',[(0,'#3a3c3c'),(.08,'#747572'),(.19,'#babbb1'),(.32,'#96978e'),(.45,'#666a62'),(.56,'#60655c'),(.68,'#c0c0b8'),(.82,'#9c9d94'),(.95,'#5b5d59'),(1,'#3d4140')],x2=1,y2=0)
 defs+=grad('ribTop',[(0,'#a2a5a0'),(.35,'#a7aaa5'),(.7,'#6a6e67'),(1,'#3c423b')],x2=.8,y2=1)
 defs+=grad('cavity',[(0,'#343a30'),(.35,'#4c5145'),(.7,'#454d3e'),(1,'#343d2d')],x2=1,y2=0)
 defs+='<radialGradient id="hole" cx=".52" cy=".88" r=".95"><stop stop-color="#a4a5a4"/><stop offset=".38" stop-color="#777a80"/><stop offset=".76" stop-color="#3f424b"/><stop offset="1" stop-color="#22282b"/></radialGradient>'
 defs+=grain('grain',w,h,n,.49)+grain('ribgrain',64,166,n+4,1.10)+grain('cavitygrain',24,121,n+8,2.3)
 rib='M214.2 166L214.2 67C214.1 43 220.2 24.4 232.9 18.3C238.4 15.7 244.4 16.2 249.4 17.3C263.2 20.1 267.7 40.7 268.1 62.4L268.3 166Z'
 defs+='<clipPath id="ribClip">'+path(rib,'#fff')+'</clipPath>'
 s=start(n,defs)+rect(0,0,w,h,'url(#wall)')
 # Narrow, irregularly subdivided wall sheets: exact arrangement, thin recessed seams.
 plates=[(0,33.5,0,166,2),(33.5,99.5,0,166,-1),(99.5,134.4,0,44.6,1),(99.5,134.4,44.6,142.4,0),(134.4,199.5,0,69.6,1),(134.4,199.5,69.6,166,-2),(199.5,241.5,0,166,2),(241.5,285.3,0,137.5,0),(285.3,365.6,0,33.5,1),(285.3,365.6,33.5,166,0),(365.6,467.5,0,78.5,1),(365.6,467.5,78.5,166,-2),(467.5,482,0,166,2)]
 for x0,x1,y0,y1,v in plates:
  s+=rect(x0,y0,x1-x0,y1-y0,'#d2cdc3' if v>0 else '#101611',abs(v)*.017)
 s+=rect(0,0,w,h,'url(#grain)',.65)
 seams=[(33.5,0,33.5,166),(99.5,0,99.5,166),(134.4,0,134.4,166),(199.5,0,199.5,166),(241.5,0,241.5,166),(285.3,0,285.3,166),(365.6,0,365.6,166),(467.5,0,467.5,166),(99.5,44.6,134.4,44.6),(134.4,69.6,199.5,69.6),(99.5,142.4,134.4,142.4),(99.5,165.1,134.4,142.4),(267.5,137.5,285.3,137.5),(285.3,33.5,365.6,33.5),(285.3,65.8,365.6,124.4),(329.9,98.3,329.9,166),(329.9,125.7,365.6,125.7),(365.6,78.5,467.5,78.5)]
 for a,b,c,d in seams:
  s+=line(a+.55,b+.45,c+.55,d+.45,'#a5a197',.6,.24)+line(a,b,c,d,'#171b15',.78,.97)
 # Recess behind the perforated raised reinforcement.
 s+=path(rib,'#151d17',None,op=.45,extra='transform="translate(1.2 .4)"')+path(rib,'url(#rib)','#3d4140',.65)
 s+=path('M215.5 60C218 33 224 19 237 17.3C250 14.5 257 24 260 32L254 36L248 46L239 48L230 60Z','url(#ribTop)',None,op=.85)
 inner='M232.2 166L231.9 72C231.5 63.5 234.1 56.9 235.8 52.3L238 48.3Q239.9 45.5 242.5 48L244.3 53.3L245.2 58.6L249.7 64.9L250.1 166Z'
 s+=path(inner,'url(#cavity)','#1c241c',.75)
 s+='<defs><clipPath id="cavityClip">'+path(inner,'#fff')+'</clipPath></defs><g clip-path="url(#cavityClip)">'+rect(230,45,24,121,'url(#cavitygrain)',.9)+'</g>'
 # A shallow U-channel has transverse stamped seams and two slightly bent wires.
 for yy in [64.6,93.3,107.5,117.3,132.6]:
  s+=line(232,yy,249.8,yy+(.8 if yy==117.3 else 0),'#1f281d',.9)+line(232.5,yy+.9,249.7,yy+1.1,'#858a77',.48,.36)
 s+=path('M238.4 49L240.8 49.5L242.9 54.6L242.5 58.8L236.3 59.4L235.1 56.8Z','#6f7b69','#2b3828',.65)
 s+=path('M240.2 110Q242.3 118.9 240.4 124.8L238.7 130.6L239.8 145L238.1 166','none','#293a2a',1.2,.95)
 s+=path('M245.7 111L244.6 129L246 145L245.2 166','none','#747b65',.6,.65)
 s+=path('M251 20.8Q257.7 23.7 253.5 29.7L243.7 43.5','none','#3f4840',.8,.78)+path('M252.3 20.9Q258.8 24.1 254.6 30.8L245.1 43.4','none','#b4b9ab',.5,.58)
 s+=path('M216 166L216 68C216 39 224 21 235 18','none','#c0c3b8',.7,.4)
 s+=path('M266.2 166L266 62Q266 34 256 23','none','#262f2c',1,.6)
 # Recessed elliptical holes. Their asymmetric lips and base reflection give depth.
 holes=[(229.6,26.5,4.4,4.7),(244.7,25.5,4.3,4.8),(227.5,44,4.6,5.1),(254.5,43.9,4.4,5.1),(223.6,62,4.4,5.5),(259,62,4.2,5.5)]
 for yy in [84.4,104.1,123,142.3,162]:holes.extend([(223.1,yy,4.05,5.9),(258.7,yy,4.05,5.9)])
 for x,y,rx,ry in holes:
  s+=ellipse(x,y,rx+1.05,ry+1.0,'#585d5b',.9)+ellipse(x-.1,y+.35,rx+.55,ry+.5,'#c1c2b9',.55)+ellipse(x,y-.25,rx,ry,'url(#hole)')
  s+=path(f'M{f(x-rx*.65)} {f(y+ry*.72)}Q{f(x)} {f(y+ry*1.12)} {f(x+rx*.65)} {f(y+ry*.72)}','none','#c8c9c1',.46,.58)
 s+='<g clip-path="url(#ribClip)">'+rect(210,0,64,166,'url(#ribgrain)',.7)
 rng=np.random.default_rng(n)
 for j in range(110):
  x=rng.uniform(216,266);y=rng.uniform(19,166)
  s+=line(x,y,x+rng.uniform(.15,1.5),y+rng.uniform(.1,.8),'#d6d6c9' if j%3 else '#262c29',.17,rng.uniform(.08,.24))
 s+='</g>'
 return finish(n,s,do_render)

def floor(do_render):
 """1957 is a periodic structural surface, including wrapped diagonal beams.

 The 207x128 canvas and opaque coverage are unchanged. Its lattice vectors are
 (207, 0) and (-28, 128), matching the original staggered floor rows. Assembly
 seam correction is isolated in floor_seams.py because original 1959 fills use
 inconsistent 203.05/203.95/207px horizontal starts and a stray 1px vertical jog.
 """
 n=1957;w,h=207,128;slope=179/128;pitch=207/13
 # Color is uniform along x. The same structural value therefore reaches both
 # edges; there is no unmotivated vertical cap, dark seam, or beam end face.
 defs=grad('deep',[(0,'#191917'),(.38,'#252522'),(1,'#47453f')])
 defs+=grad('rail',[(0,'#a2a6a2'),(.3,'#a8aca7'),(.62,'#9fa69f'),(1,'#969e96')])
 defs+=grad('beam',[(0,'#8d8a7f'),(.12,'#959187'),(.5,'#898579'),(.88,'#817e71'),(1,'#77776b')],x2=1,y2=0)
 # Independent low-contrast periodic grain. No reference RGB is sampled.
 # u shifts by one full horizontal period between staggered row boundaries.
 scale=4;yy,xx=np.mgrid[0:h*scale,0:w*scale]/scale
 u=(xx-slope*yy)/w;v=yy/h;rng=np.random.default_rng(n)
 field=np.zeros_like(u)
 for count,lo,hi,amplitude in [(10,1,4,.48),(15,4,12,.24),(20,12,40,.12),(24,40,110,.05)]:
  layer=np.zeros_like(u)
  for _ in range(count):
   ku=int(rng.integers(lo,hi));kv=int(rng.integers(-hi,hi+1));phase=rng.uniform(0,2*math.pi)
   layer+=np.sin(2*math.pi*(ku*u+kv*v)+phase)
  field+=layer*amplitude/math.sqrt(count)
 tone=np.where((field>0)[...,None],[211,212,197],[18,19,15])
 rgba=np.dstack([tone,np.minimum(np.abs(field)*26,27)])
 defs+=f'<pattern id="floorgrain" patternUnits="userSpaceOnUse" width="{w}" height="{h}"><image width="{w}" height="{h}" href="data:image/png;base64,{image_data(rgba)}"/></pattern>'
 s='<defs>'+defs+'</defs><g id="new-native-art">'+rect(-w,0,w*3,h,'url(#deep)')
 # Raised mesh belongs to the same oblique lattice as the broad load beams.
 # Exact 13-cell x period avoids the 207 / 16.05 mismatch of the prior draft.
 for j in range(16):
  y=3.4+j*8
  s+=line(-w,y+1.0,w*2,y+1.0,'#131a14',1.15,.9)
  s+=line(-w,y,w*2,y,'#7d7a70',1.3)
  s+=line(-w,y-.35,w*2,y-.35,'#aaa89a',.34,.7)
 for j in range(-14,16):
  x=j*pitch
  s+=line(x+.85,-2,x+.85+slope*132,130,'#111711',1.35,.9)
  s+=line(x,-2,x+slope*132,130,'#817f72',1.45)
  s+=line(x-.35,-2,x-.35+slope*132,130,'#b0ac9c',.34,.67)
 # Straight cross-rails, with the old lower-left step deliberately removed.
 # Both edges reach every horizontal tile boundary at precisely the same y.
 s+=rect(-w,0,w*3,10.8,'#a2a79d')
 s+=line(-w,10.35,w*2,10.35,'#c3c8bc',.65,.8)
 s+=line(-w,11.35,w*2,11.35,'#303b30',.7,.75)
 s+=rect(-w,116.1,w*3,11.9,'#a2a79d')
 s+=line(-w,116.3,w*2,116.3,'#c3c9ba',.7,.75)
 s+=line(-w,127.55,w*2,127.55,'#687667',.65,.45)
 # Wrap every load beam, bevel, and shadow across both x boundaries. The
 # right-hand continuation reappears on the left instead of becoming a cap.
 for k in [-1,0,1]:
  s+=f'<g transform="matrix(1 0 {slope} 1 {k*w} 0)">'
  s+=rect(-1,0,50.7,h,'#273028',.42)
  s+=rect(0,0,48.8,h,'url(#beam)')
  s+=rect(0,0,2.4,h,'#67675b',.42)
  s+=rect(47.2,0,1.6,h,'#bec2b3',.61)
  s+=line(2.1,0,2.1,h,'#b3b9a6',.55,.38)+'</g>'
 s+=rect(-w,0,w*3,h,'url(#floorgrain)',.76)
 return finish(n,s,do_render)

def dark_wall(do_render):
 n=1958;w,h=135,169
 # Structureless dark blue mottling is regenerated from independent noise; the
 # original variable alpha is preserved so the layer blends exactly as before.
 a=noise(w,h,n,4);b=noise(w,h,n+1,4);tone=np.clip(a*.62+b*.38,-1.5,1.5)*1.83
 cols=np.stack([53+tone*13,56+tone*14,71+tone*16,np.full_like(tone,255)],axis=2)
 defs=grad('base',[(0,'#303744'),(.4,'#384052'),(1,'#333b4a')])
 s=start(n,defs)+rect(0,0,w,h,'url(#base)')
 s+=f'<image id="independent-cloud-microtexture" width="{w}" height="{h}" href="data:image/png;base64,{image_data(np.clip(cols,0,255))}"/>'
 return finish(n,s,do_render)

# Outline-font strokes are authored here, independent of platform fonts.
GLYPHS={'D':'M0 0V6H2.2Q4 6 4 3Q4 0 2.2 0Z','A':'M0 6L2 0L4 6M.7 4H3.3','N':'M0 6V0L4 6V0','G':'M4 .6Q0 -1 0 3Q0 7 4 5.5V3H2.5','E':'M4 0H0V6H4M0 3H3.2','R':'M0 6V0H2.5Q4 0 4 1.5Q4 3 2.5 3H0M2.2 3L4.2 6'}
def danger(x,y,w,h,color):
 return f'<g transform="translate({x} {y}) scale({w/29} {h/6})" fill="none" stroke="{color}" stroke-width=".65" stroke-linejoin="round">'+''.join(f'<path d="{GLYPHS[c]}" transform="translate({i*5})"/>' for i,c in enumerate('DANGER'))+'</g>'

def arrow(do_render):
 n=1962;defs=grain('grain',48,30,n,2.0)+grad('paint',[(0,'#686866'),(.5,'#696966'),(1,'#585954')])
 s=start(n,defs)+rect(0,0,48,30,'#60615c')
 # Continuous opaque substrate inside the original alpha mask retains every worn
 # edge. Main RGB facets are newly drawn, not traced from bitmap color blocks.
 for dx in [0,21.5]:
  s+=path(f'M{dx} 0H{dx+10.2}L{dx+26.5} 14.8L{dx+10.5} 29.8H{dx}L{dx+15.5} 14.8Z','url(#paint)')
 s+=rect(0,0,48,30,'url(#grain)',.6)
 rng=np.random.default_rng(n)
 for j in range(75):
  x=rng.uniform(0,48);y=rng.uniform(0,30);rr=rng.uniform(.15,.85)
  s+=path(f'M{f(x)} {f(y)}l{f(rr)} {f(rr*.3)}l{f(rr*.3)} {f(rr*.8)}l{f(-rr)} {f(rr*.3)}Z','#323930' if j%3 else '#9da096',None,op=rng.uniform(.2,.5))
 for j in range(22):
  x=rng.uniform(1,47);y=rng.uniform(1,29);r=rng.uniform(.7,2.2)
  s+=path(f'M{f(x-r)} {f(y)}l{f(r*.7)} {f(-r*.5)}l{f(r*.3)} {f(r*.3)}l{f(r*.7)} {f(-r*.2)}l{f(r*.7)} {f(r*.8)}l{f(-r*.4)} {f(r)}l{f(-r)} {f(-r*.3)}Z','#21231e',None,op=rng.uniform(.45,.8))
 return finish(n,s,do_render)

def radiation(do_render):
 n=1964;defs=grain('grain',38,32,n,.5)+grad('yellow',[(0,'#e5d717'),(.4,'#ebdf19'),(1,'#dfd10b')])
 s=start(n,defs)+rect(0,0,38,32,'#11180f')
 s+=path('M17.1 1.8Q19 -.3 21 1.8L36.2 27.1Q38.3 30.6 34.3 31H3.7Q-.4 30.7 1.7 27.1Z','url(#yellow)','#27301b',1.6)
 s+=path('M18.3 3.3L3.5 28.6H34.5L19.7 3.3Q19 2.4 18.3 3.3Z','none','#eee13a',.45,.65)
 cx,cy=19,18.7
 # Three blades and central dot, standard trefoil; all are separately editable.
 for a0,a1 in [(-180,-120),(-60,0),(60,120)]:
  def pt(r,a):return(cx+r*math.cos(math.radians(a)),cy+r*math.sin(math.radians(a)))
  p0,p1,p2,p3=pt(3.6,a0),pt(10.5,a0),pt(10.5,a1),pt(3.6,a1)
  d=f'M{f(p0[0])} {f(p0[1])}L{f(p1[0])} {f(p1[1])}A10.5 10.5 0 0 1 {f(p2[0])} {f(p2[1])}L{f(p3[0])} {f(p3[1])}A3.6 3.6 0 0 0 {f(p0[0])} {f(p0[1])}Z'
  s+=path(d,'#10160c')
 # The original has two upper sectors and one downward-facing sector.
 # The alpha is independent of symbol geometry and is unchanged.
 s+=ellipse(cx,cy,2.35,2.35,'#10160c')+rect(0,0,38,32,'url(#grain)',.5)
 return finish(n,s,do_render)

def danger_sign(do_render):
 n=1965;defs=grain('grain',41,26,n,.45)+grad('paper',[(0,'#292a26'),(1,'#282b29')])
 s=start(n,defs)+rect(0,0,41,26,'#0c100b')
 s+=rect(.7,.7,39.6,24.5,'url(#paper)')+rect(1.2,1.1,38.5,9.3,'#302a14')+rect(1.8,1.6,37.3,8.2,'#34270e',.5)
 s+=danger(3,2.2,34.5,6.2,'#1e1508')+line(1,11.1,40,11.1,'#080f0a',.8)+line(1.8,12,39.1,12,'#595b52',.45,.75)
 # Original subtext is below legibility. Preserve its grouped ink rhythm without
 # inventing a readable safety instruction absent from the supplied original.
 rows=[(14.2,[(2.2,5.1),(6.2,10.5),(11.6,17),(18,22.1),(23.1,28),(29.2,34),(35.1,38.8)]),(17.2,[(2.4,7),(8,14),(15.1,20.4),(21.4,27.9),(29,32.4),(33.5,38.7)]),(20.2,[(2.6,7.2),(8.1,12.1),(13.1,20),(21.3,26.5),(27.4,33),(34.1,38.4)]),(23.1,[(7.4,12.1),(13.1,20.1),(21.1,27),(28.1,33.7)])]
 for y,parts in rows:
  for x0,x1 in parts:
   s+=line(x0,y,x1,y,'#0b110e',.95,.94)+line(x0+.2,y+.8,x1-.3,y+.8,'#151d18',.48,.75)
 s+=rect(0,0,41,26,'url(#grain)',.16)
 return finish(n,s,do_render)

def triangle(do_render):
 n=1966;defs=grain('grain',31,27,n,.7)
 s=start(n,defs)+rect(0,0,31,27,'#12170f')
 s+=path('M15.3 1.5L1.8 21H29.2Z','#30372a','#22291c',.55)
 s+=path('M15.3 2.3L7.6 13.7H23.2Z','#aaa9a2')
 # Faded red block glyphs preserve the original stencil's visual occupancy.
 for dx in [10.2,19.8]:
  s+=path(f'M{dx} 8.2h2.5v.8h-1.7v1h1.4v.8h-1.4v1.1h1.7v.8h-2.5Z','#8e6f65',None,op=.85)
 s+=path('M14 10H17.7V12H14Z','#93776e',None,op=.72)
 s+=poly([(5.8,15.5),(25,15.5),(28.7,21),(2.1,21)],'#11170d')
 for pts in [[(5.9,16.5),(8.6,16.5),(11.4,20.5),(8,20.5)],[(14.9,16.5),(18.5,16.5),(21.3,20.5),(17.6,20.5)],[(2.6,19.7),(4.5,18),(6.3,20.5),(2.2,20.5)]]:
  s+=poly(pts,'#8c8127')
 # Two original small pale footer groups; no invented legible wording.
 s+=path('M4 23H9V27H4ZM6 24V25H7V24ZM10 23H12V25H14V23H16V27H10Z','#a5a6a1',extra='fill-rule="evenodd"')
 s+=path('M19 23H23V27H19ZM20 24V25H21V24ZM24 23H28V24H26V25H28V27H24Z','#979b93',extra='fill-rule="evenodd"')
 s+=rect(0,0,31,27,'url(#grain)',.45)
 return finish(n,s,do_render)

def checker(im,background=(57,64,67)):
 im=im.convert('RGBA');out=Image.new('RGBA',im.size,background+(255,));out.alpha_composite(im);return out.convert('RGB')
def review(round_name):
 outdir=ROOT/'previews'/round_name;outdir.mkdir(parents=True,exist_ok=True);rows=[]
 for n in IDS:
  old=Image.open(ROOT/f'reference/{n}.png').convert('RGBA');new=Image.open(ROOT/f'previews/industrial-{n}-native.png').convert('RGBA');w,h=old.size;sc=3 if n in [1231,1957,1958] else 10
  out=Image.new('RGB',(w*sc*2,h*sc+34),'#273135');d=ImageDraw.Draw(out)
  out.paste(checker(old).resize((w*sc,h*sc),Image.Resampling.NEAREST),(0,34));out.paste(checker(new).resize((w*sc,h*sc),Image.Resampling.LANCZOS),(w*sc,34));d.text((8,9),f'ORIGINAL {n}',fill='white');d.text((w*sc+8,9),'NEW / native SVG + independent micrograin',fill='white');out.save(outdir/f'compare-{n}.png')
  a=np.array(old.getchannel('A'));b=np.array(new.getchannel('A'))
  rows.append({'bitmapId':n,'nativeSize':[w,h],'alphaExact':bool(np.array_equal(a,b)),'alphaMaxError':int(np.max(abs(a.astype(int)-b.astype(int)))),'alphaBoundsOriginal':list(old.getbbox()),'alphaBoundsNew':list(new.getbbox()),'rgbMeanOccupiedOriginal':np.array(old)[:,:,:3][a>0].mean(0).round(3).tolist(),'rgbMeanOccupiedNew':np.array(new)[:,:,:3][b>0].mean(0).round(3).tolist()})
 (ROOT/f'qa/industrial-{round_name}-contracts.json').write_text(json.dumps(rows,indent=2))
 # Original/new material contact sheet is self-contained and never used as art.
 out=Image.new('RGB',(1500,890),'#273135');d=ImageDraw.Draw(out)
 for r,n in enumerate(IDS):
  y=35+r*120;old=Image.open(ROOT/f'reference/{n}.png').convert('RGBA');new=Image.open(ROOT/f'previews/industrial-{n}-native.png').convert('RGBA');sc=min(2,105/old.height);size=(round(old.width*sc),round(old.height*sc));d.text((10,y),str(n),fill='white');out.paste(checker(old).resize(size,Image.Resampling.NEAREST),(75,y));out.paste(checker(new).resize(size,Image.Resampling.LANCZOS),(805,y))
 d.text((75,10),'ORIGINAL',fill='white');d.text((805,10),'NEW',fill='white');out.save(outdir/'industrial-contact.png')
 return rows

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--no-render',action='store_true');ap.add_argument('--review-name',default='round2');args=ap.parse_args()
 for sub in ['parts','previews','qa']: (ROOT/sub).mkdir(exist_ok=True)
 for fn in [wall,floor,dark_wall,arrow,radiation,danger_sign,triangle]:fn(not args.no_render)
 if not args.no_render:print(json.dumps(review(args.review_name),indent=2))
 manifest={'bitmapIds':IDS,'method':'Hand-authored native SVG structure, deterministic independently synthesized grain, original alpha-only contract','productionModified':False,'externalRuntimeAssets':False,'parts':{str(n):hashlib.sha256((ROOT/f'parts/bitmap-{n}.svg').read_bytes()).hexdigest() for n in IDS}}
 (ROOT/'qa/industrial-build-manifest.json').write_text(json.dumps(manifest,indent=2))
if __name__=='__main__':main()
