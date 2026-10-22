"""Editable native-size redraws of CF6 river bridge 1784 and arcade 1789.
Reference assistance: landmarks and silhouette are inspected from supplied artwork.
Only source alpha is read into an editable vector clip; no source RGB is sampled,
resized, painted over, filtered, or embedded. Texture PNGs are independently
synthesized minerals / water, while architectural shapes remain editable SVG.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np, io, base64, json, hashlib
from scipy.ndimage import gaussian_filter
from svg_native import write_part, render
R=Path(__file__).resolve().parents[1]
rng=np.random.default_rng(17841789)

def f(x):return f'{x:.3f}'.rstrip('0').rstrip('.')
def rect(x,y,w,h,c,op=1,extra=''):
 return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" fill="{c}" opacity="{op}" {extra}/>'
def path(d,c,op=1,extra=''):
 return f'<path d="{d}" fill="{c}" opacity="{op}" {extra}/>'
def line(x1,y1,x2,y2,c,w=.5,op=1):
 return f'<path d="M{f(x1)} {f(y1)}L{f(x2)} {f(y2)}" fill="none" stroke="{c}" stroke-width="{w}" opacity="{op}"/>'
def poly(pts,c,op=1):return '<polygon points="'+' '.join(f'{f(x)},{f(y)}' for x,y in pts)+f'" fill="{c}" opacity="{op}"/>'
def pngdata(a):
 b=io.BytesIO();Image.fromarray(np.uint8(np.clip(a,0,255))).save(b,format='PNG',optimize=True);return base64.b64encode(b.getvalue()).decode()
def material(name,w,h,seed,scale=3,strength=1):
 rr=np.random.default_rng(seed);W,H=int(w*scale),int(h*scale)
 def n(sx,sy):
  a=rr.uniform(-1,1,(sy,sx)).astype('float32');return np.array(Image.fromarray(a,'F').resize((W,H),Image.Resampling.BICUBIC))
 coarse=n(max(3,int(w/20)),max(3,int(h/20)));mid=n(int(w/2.7),int(h/2.7));fine=n(int(w*1.1),int(h*1.1));dust=rr.normal(0,.15,(H,W))
 field=coarse*.35+mid*.34+fine*.29+dust*.2
 dy,dx=np.gradient(gaussian_filter(field,.45));relief=field+(.7*dx-1.0*dy)
 a=np.zeros((H,W,4));light=relief>0;a[:,:,:3]=np.where(light[:,:,None],np.array([255,233,175]),np.array([37,26,11]));a[:,:,3]=np.clip(abs(relief)*84*strength,0,155)
 # Tiny recesses and crystalline chips, irregular and sparse rather than uniform speckle.
 hit=rr.random((H,W));a[hit>.997]=[245,224,178,45];a[hit<.003]=[25,17,6,55]
 return f'<pattern id="{name}" patternUnits="userSpaceOnUse" width="{w}" height="{h}"><image width="{w}" height="{h}" href="data:image/png;base64,{pngdata(a)}"/></pattern>'
def alphaclip(n):
 a=np.array(Image.open(R/f'reference/{n}.png').getchannel('A'))>127;seg=[]
 # Alpha-only tracing, exact pixel coverage, never inspecting RGB channels.
 for y,row in enumerate(a):
  z=np.flatnonzero(np.diff(np.r_[0,row,0].astype('int8')));seg += [f'M{l} {y}h{r-l}v1h{l-r}Z' for l,r in zip(z[::2],z[1::2])]
 return '<clipPath id="originalAlpha"><path d="'+''.join(seg)+'"/></clipPath>'
def plaster(d,c,texture='plasterNoise'):
 return path(d,c)+path(d,f'url(#{texture})',.7)
def wall(x,y,w,h,c):return plaster(f'M{f(x)} {f(y)}h{f(w)}v{f(h)}h-{f(w)}Z',c)
def window(x,y,w,h,kind='dark',shutters=False):
 # Local deterministic irregularity: crooked jambs, broken lintels, partial shutters.
 rr=np.random.default_rng(int(x*177+y*632+w*719+h*31)%2**32)
 x+=rr.uniform(-.15,.15);y+=rr.uniform(-.22,.22);w+=rr.uniform(-.12,.12)
 dark=rr.choice(['#273127','#303427','#3c3e2c','#28362b','#42452f'])
 s=rect(x-.18,y-.25,w+.36,h+.5,'#e2b877',rr.uniform(.18,.42))
 s+=poly([(x,y),(x+w,y+rr.uniform(-.14,.14)),(x+w-.04,y+h),(x+rr.uniform(-.1,.1),y+h)],'#74542f')
 s+=rect(x+.3,y+.4,max(.1,w-.55),max(.1,h-.65),dark)
 s+=line(x,y,x+w,y,'#7c572e',.45)+line(x,y,x,y+h,'#745330',.4)
 if rr.random()<.7:s+=line(x-.2,y+h+.2,x+w+rr.uniform(.1,.7),y+h+.2,'#efc680',.4,rr.uniform(.4,.8))
 if kind=='glass' and rr.random()<.7:
  s+=poly([(x+.5,y+.6),(x+w-.5,y+.7),(x+w-.5,y+h*.45),(x+.6,y+h*.7)],'#aaa780',rr.uniform(.07,.21))
 if w>4 and rr.random()<.85:s+=line(x+w*rr.uniform(.42,.58),y+.15,x+w*.5,y+h,'#a88f60',rr.uniform(.25,.45))
 if h>7 and rr.random()<.5:s+=line(x+.2,y+h*.52,x+w-.2,y+h*.52,'#9e8b5b',.25)
 if shutters:
  for side in [-1,1]:
   xx=x-1.4 if side==-1 else x+w+.2;ww=rr.uniform(.75,1.2)
   s+=rect(xx,y+rr.uniform(-.15,.15),ww,h,rr.choice(['#5c6744','#5b5f39','#4f5b3d']))
   if rr.random()<.4:s+=line(xx+.4,y+.2,xx+.4,y+h-.2,'#c4a36b',.25,.55)
   for yy in np.arange(y+1,y+h,rr.uniform(.9,1.4)):s+=line(xx,yy,xx+ww,yy,'#323c2a',.2,.5)
 if rr.random()<.28:
  s+=rect(x+.25,y+.3,w*.35,h-.6,'#777b50',.6)
 # Water run-off and peeling plaster beneath a subset of recesses.
 if rr.random()<.4:
  s+=path(f'M{f(x+w*.2)} {f(y+h+.4)}l.2 1.8l.6 -.2l-.3 -1.7Z','#8c713c',.23)
 return s

def roof(x,y,w,h,seed=1):
 rr=np.random.default_rng(seed);d=f'M{f(x-1)} {f(y+h)}L{f(x+2)} {f(y)}H{f(x+w-3)}L{f(x+w+1)} {f(y+h)}Z'
 s=path(d,'#726039')+path(d,'url(#roofNoise)',.95)
 # Uneven narrow baked clay tiles on broken rows.
 for yy in np.arange(y+.7,y+h,.95):
  for xx in np.arange(x+(int(yy)%2)*.8,x+w,1.7):
   s+=line(xx,yy,xx+.8,yy+.5,rr.choice(['#ac8546','#a27f47','#4c4c31','#d7a863']),.45,rr.uniform(.35,.8))
 s+=line(x-1,y+h+.2,x+w+1,y+h+.2,'#352e1c',.7)+line(x,y+h+.7,x+w,y+h+.7,'#e6bf79',.45)
 return s

def river_surface():
 rr=np.random.default_rng(1784007);S=3;W,H=345*S,120*S
 yy,xx=np.mgrid[0:H,0:W].astype(float);y=yy/S+67;x=xx/S
 def n(nx,ny):
  z=rr.uniform(-1,1,(ny,nx)).astype('float32');return np.array(Image.fromarray(z,'F').resize((W,H),Image.Resampling.BICUBIC))
 z=n(23,31);b=n(10,17);micro=n(155,210)
 keys=[67,82,108,121,143,187]
 colors=np.array([[39,53,43],[42,77,84],[72,132,152],[111,175,182],[116,192,205],[124,203,217]])
 rgb=np.stack([np.interp(y,keys,colors[:,c]) for c in range(3)],axis=2)
 depth=np.clip((y-106)/60,0,1)
 wave=np.sin(y*.71+np.sin(x*.029+y*.045)*2.0+z*.8)
 bright=np.maximum(0,wave-.33)**2
 shade=np.minimum(0,wave+.35)
 variation=(z*7+b*4+bright*26+shade*9)*(.35+.65*depth)+micro*1.3
 rgb+=variation[:,:,None]*np.array([.9,1,1.05])[None,None,:]
 # Near-bank reflections break into fine bronze/cyan horizontal stipple.
 rf=n(121,174);gold=np.maximum(0,rf-.15)*np.exp(-((y-118)/10)**2)*35
 rgb+=gold[:,:,None]*np.array([1.0,.55,-.25])[None,None,:]
 return f'<image id="generated-river-surface" x="0" y="67" width="345" height="120" href="data:image/png;base64,{pngdata(rgb)}"/>'

def bridge():
 W,H=345,187
 defs=alphaclip(1784)+material('plasterNoise',345,187,1784,3,1)+material('roofNoise',345,187,1787,3,1.4)+material('masonryNoise',345,187,1785,3,1.15)
 defs+='''<linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#30433d"/><stop offset=".24" stop-color="#487e90"/><stop offset=".48" stop-color="#75b7bd"/><stop offset="1" stop-color="#82cdd8"/></linearGradient><linearGradient id="bridgeStone" x1="0" y1="0" x2="1" y2=".6"><stop stop-color="#9e743d"/><stop offset=".48" stop-color="#c69b56"/><stop offset="1" stop-color="#a68147"/></linearGradient><linearGradient id="wallWarm" x2=".8" y2="1"><stop stop-color="#edc27e"/><stop offset=".55" stop-color="#ddb072"/><stop offset="1" stop-color="#b88a4b"/></linearGradient>'''
 s='<defs>'+defs+'</defs><g id="river-city" clip-path="url(#originalAlpha)">'
 s+=rect(0,0,W,H,'#685b37')
 # River back plane and compressed, broken reflected bands.
 s+=river_surface()
 rr=np.random.default_rng(17484)
 for i in range(460):
  y=rr.uniform(73,187);depth=(y-73)/114;x=rr.uniform(-30,345);ln=rr.uniform(2,18)*(1+depth*2.7);th=rr.uniform(.12,.7)*(1+depth*.65)
  c=rr.choice(['#b2e9e9','#a5d9d8','#618e97','#3c6570','#96cbd0','#c1dede'])
  s+=path(f'M{f(x)} {f(y)}q{f(ln*.3)} {f(-th*.8)} {f(ln*.5)} 0t{f(ln*.5)} 0l{f(-ln*.12)} {f(th)}q{f(-ln*.38)} {f(th*.6)} {f(-ln*.88)} 0Z',c,rr.uniform(.08,.25)*(1.1-depth*.2))
 # Recessed water reflects the light sky in broken, long horizontal ribbons.
 for i in range(210):
  y=rr.uniform(77,112);x=rr.uniform(-20,345);ln=rr.uniform(4,34)
  c=rr.choice(['#739a9b','#598d9e','#85b2bc','#a9b6a2','#977d4b'])
  s+=path(f'M{f(x)} {f(y)}l{f(ln)} -.2l{f(-ln*.1)} .6l{f(-ln*.8)} .15Z',c,rr.uniform(.15,.45))
 # Bronze reflections are vertically clustered, horizontally broken.
 for i in range(900):
  y=rr.uniform(109,143);x=rr.uniform(0,345);fade=(143-y)/34
  if rr.random()<.64:
   s+=rect(x,y,rr.uniform(.35,6),rr.uniform(.2,.65),rr.choice(['#b4b58c','#c4ba8a','#689797','#bfd2bb']),rr.uniform(.16,.65)*fade)
 # Broad pale caustic eddies in front, with fragments rather than line grids.
 for j in range(64):
  y=rr.uniform(145,185);x=rr.uniform(-15,345);ln=rr.uniform(12,49)
  s+=path(f'M{f(x)} {f(y)}q{f(ln*.38)} -1.7 {f(ln)} -1.2q{f(-ln*.2)} 1.4 {f(-ln*.45)} 1.5q{f(-ln*.35)} .2 {f(-ln*.55)} -.3Z','#c1f0ed',rr.uniform(.12,.3))
 # Rear corridor plaster and its three shadowed arch passages.
 s+=wall(0,6,345,57,'#d9ac69')+rect(0,9,345,2,'#b5904e',.5)
 for d in ['M40 61V48C40 26 63 26 63 48V61Z','M65 61V47C65 26 96 26 96 47V61Z','M99 61V47C99 25 130 25 130 47V61Z']:
  s+=path(d,'#242b22')
 # Distant architecture visible in left arcade, and recess walls.
 s+=wall(42,40,9,19,'#8d8860')+wall(47,35,10,22,'#787e65')+wall(68,40,12,17,'#999b76')+wall(78,35,8,24,'#c4bc83')
 for x,y,w,h in [(43,42,2,5),(47,39,2,5),(51,36,2,5),(52,45,2,6),(69,43,3,6),(74,40,3,5),(79,39,2,4),(83,44,2,7),(79,50,3,5)]:s+=window(x,y,w,h)
 for x in np.arange(42,60,2.4):s+=line(x,39,x,58,'#b8a36b',.35,.5)
 # Rear upper long window galleries: irregular grouped mullioned glass, not a uniform grid.
 for x,y,w in [(34,12,28),(67,11,28),(100,11,28)]:
  s+=rect(x-1,y-1,w+2,15,'#f1ca87')+rect(x,y,w,13,'#756b43')
  for k,(dx,ww,dy) in enumerate([(1.3,4.1,.3),(7.3,5.1,.6),(14.6,4.7,0),(21.3,4.6,.5)]):
   s+=window(x+dx,y+dy,ww,11.7-dy,'glass')
  s+=line(x-1,y+13.9,x+w+1,y+13.9,'#876339',.75)
 s+=line(29,9,29,30,'#846039',.7)+line(132,9,132,29,'#ae7e43',.7)
 # Long low tiled corridor roof, tiny chips and slightly uneven upper edge.
 s+=roof(0,1,345,7,17841)
 # Background center tower and roof silhouette.
 s+=wall(157,4,37,28,'#cf9f5e')+wall(165,9,19,29,'#e5b675')
 for x in [158,165,174,183]:s+=wall(x,0,2,10,'#9e8c56')
 s+=roof(158,6,36,5,17842)+rect(160,12,33,1,'#846e40')
 for x in [159,170,181,189]:s+=window(x,14,2.7,6,'glass')
 s+=wall(144,16,2,7,'#957643')+wall(150,17,2,6,'#bda06b')
 # Left building edge and warm river houses.
 s+=wall(-4,18,14,47,'#d29b40')
 for y in [22,35,49,60]:s+=rect(0,y,10,1.1,'#f0bb60')
 for x,y,w,h in [(1,26,3,5),(5,27,3,4),(0,41,3,5),(1,54,3,6)]:s+=window(x,y,w,h,shutters=True)
 s+=wall(10,27,31,39,'url(#wallWarm)')+roof(10,21,31,6,17843)
 for x,y,w,h in [(13,29,3.2,5),(18,29,3.3,5),(24,29,3.6,5),(30,29,3.4,5),(36,29,2.5,5),(13,41,3.1,6),(19,41,4,6),(27,41,3.2,6),(34,40,3.8,6),(13,55,3.3,6),(20,55,3.7,6),(28,55,3.2,5.5),(35,55,3.3,5.4)]:s+=window(x,y,w,h,'glass',shutters=y>35)
 for y in [36,50,64]:s+=rect(10,y,32,.8,'#eec783')
 s+=line(41,28,41,65,'#664f30',1.2)+line(10,28,10,65,'#96703d',.6)
 # Bridge front, continuous masonry with accurately unequal spans and piers.
 bridge_d='M0 64L43 63L78 59L136 64L172 68L220 66L274 68L321 66L345 67V112H326V96C297 73 244 62 196 94V112H166V97C122 67 69 59 13 96V112H0Z'
 s+='<defs><clipPath id="bridgeFace">'+path(bridge_d,'white')+'</clipPath></defs>'
 s+=path(bridge_d,'url(#bridgeStone)')+path(bridge_d,'url(#masonryNoise)',.95)
 s+=path('M148 91L166 97V112L148 108Z','#342d20')+path('M325 96L330 95V112H325Z','#332c1d')
 s+=path('M148 91L166 97V112L148 108Z','url(#masonryNoise)',.4)+line(149,93,149,106,'#5d5035',.6,.5)
 # Masonry arch wedge traces, only a few darker stones and radial joints.
 for center,rx,ry,a0,a1 in [(82,74,27,201,340),(262,68,24,204,338)]:
  for t in np.arange(a0,a1,7.5):
   ang=np.deg2rad(t);x=center+rx*np.cos(ang);y=98+ry*np.sin(ang)
   s+=line(x,y,x+3*np.cos(ang),y+3.8*np.sin(ang),'#786342',.45,.55)
   s+=line(x+.5,y,x+2.5*np.cos(ang)+.5,y+3.8*np.sin(ang),'#e4b96f',.35,.55)
 # Broken ashlar seams; pier vertical courses, ragged water stains.
 for x0,x1,y0,y1 in [(0,13,67,111),(166,196,69,112),(330,345,68,112)]:
  for yy in np.arange(y0+3,y1,4.1):
   s+=line(x0,yy,x1,yy+rr.uniform(-.7,.7),'#765b35',.32,.22)
   xx=rr.uniform(x0+2,x1-1);s+=line(xx,yy,xx+.2,yy+4,'#735d38',.35,.3)
  for k in range(22):
   x=rr.uniform(x0,x1);y=rr.uniform(y0,y1);s+=rect(x,y,rr.uniform(.3,1.8),min(rr.uniform(2,10),y1-y),'#544f33',rr.uniform(.1,.3))
 s+=path('M166 74L173 72V110L166 112Z','#ad864b',.75)+line(173,74,174,110,'#d8af6b',.6,.8)
 # Upper stones, dirt, moss and a broken parapet over the left span.
 s+=path('M40 60Q77 57 137 61L139 67Q90 59 41 66Z','#857747')
 s+='<g clip-path="url(#bridgeFace)">'
 for i in range(300):
  x=rr.uniform(1,345);y=rr.uniform(61,76)
  if x<137 or x>195:
   s+=poly([(x,y),(x+rr.uniform(.5,2),y-.4),(x+rr.uniform(.8,3),y+.4),(x,y+rr.uniform(.3,1.2))],rr.choice(['#d9ad62','#7b7845','#b89450','#e2bc77','#506044']),rr.uniform(.3,.7))
 s+='</g>'
 for x in np.arange(43,132,2.7):
  if rr.random()<.65:s+=line(x,60,x+rr.uniform(-.8,.8),rr.uniform(55,59),'#afa471',.65,.8)
 # Projecting house structures in foreground, carefully varied heights and widths.
 s+=wall(139,28,33,39,'#dfb77b')+roof(138,22,35,5,17844)
 s+=wall(136,31,3,35,'#686047')
 for x,y,w,h in [(142,30,4.4,5.5),(149,30,5,5.5),(158,30,4.4,5.5),(165,30,4.5,5.5),(142,42,4.5,6),(150,42,4.8,6),(158,42,4.4,6),(165,42,4.4,6),(142,55,4.6,7),(150,55,4.6,7),(158,55,4.4,7),(165,55,4.4,7)]:s+=window(x,y,w,h,'glass',x<155 and y>35)
 for y in [38,51,65]:s+=rect(139,y,33,.75,'#f0d192')
 s+=line(139,28,139,67,'#634d2c',1.1)+line(171,28,171,68,'#b18b4f',.8)
 # Central irregular older gabled group: one projecting bay, shutters, low annexes.
 s+=wall(172,34,21,32,'#c49652')+path('M177 24L187 18L197 24V38H177Z','#b89458')+roof(176,19,22,6,17845)
 s+=rect(183,24,9,8,'#e4c992')
 for xx in [184,186.5,189]:s+=window(xx,24.6,1.5,5.5,'glass')
 s+=roof(173,34,22,4,17846)
 for x,y,w,h in [(177,40,3,5),(187,40,2.5,5),(176,54,3.1,6),(184,54,3.2,6),(190,53,2.3,6)]:s+=window(x,y,w,h,'glass')
 s+=wall(194,38,17,28,'#d3a765')+rect(197,40,10,6,'#a37e47')+rect(196,49,13,1.2,'#e5bc7b')+window(198,53,7.5,7)
 s+=wall(211,39,20,27,'#deb677')+roof(210,25,22,3,17847)
 s+=wall(211,28,12,11,'#c79c60')+window(216,30,3,6)+wall(222,28,3,11,'#ac874e')
 s+=path('M225 28L227 24H230V39H225Z','#c5aa75')+rect(225,24,6,1,'#7b6a42')
 for x,y,w,h in [(213,41,4.8,4.5),(220,41,4.6,4.5),(214,55,6,6),(224,55,4.4,6)]:s+=window(x,y,w,h,'glass')
 s+=wall(231,39,24,27,'#d4ab68')+roof(230,36,26,3,17848)
 for x,y,w,h in [(236,41,6,5),(244,41,5,5),(233,55,5,6),(240,55,6.6,6),(250,55,3,6)]:s+=window(x,y,w,h,'glass',y<50)
 s+=rect(232,50,23,1,'#f0cb88')+rect(232,52,23,.7,'#a5783c')
 # Chimney/corner projections behind the next high facade.
 s+=wall(244,23,2,15,'#8e8059')+rect(243,22,4,1.6,'#655d3c')+wall(250,27,6,11,'#c29f67')
 s+=wall(256,26,22,42,'#dfb57a')+roof(254,20,25,5,17849)
 s+=rect(255,37,25,2.6,'#7a7046')+line(255,39.5,280,39.5,'#edcc8b',.7)
 for x,y,w,h in [(259,28,3.6,7),(266,28,3.6,7),(272,29,3.8,6),(258,42,4.5,6),(265,42,4.7,6),(273,42,3.5,6),(257,55,4.7,7),(266,55,4.7,7),(273,55,3.6,7)]:s+=window(x,y,w,h,'glass',y>38)
 s+=wall(278,23,16,43,'#d7a765')+roof(277,18,18,5,17850)+window(282,28,7,6,'glass')
 for x,y,w,h in [(280,42,5.3,5),(287,42,5.6,5),(281,55,4.9,6.7),(288,55,4.6,6.7)]:s+=window(x,y,w,h,'glass',y>50)
 s+=rect(279,37,15,.8,'#eec887')+rect(278,50,16,.8,'#efc788')
 s+=wall(295,38,15,29,'#ecc68b')+roof(295,36,16,2,17851)+wall(300,24,5,12,'#969068')
 for x,y,w,h in [(297,41,4.3,5),(304,41,4.2,5),(299,55,6.8,7)]:s+=window(x,y,w,h,'glass')
 s+=wall(311,37,21,30,'#e8bf7d')+roof(310,34,22,3,17852)
 for x,y,w,h in [(314,41,4.1,5),(320,41,4.5,5),(326,41,3.5,5),(317,55,7.5,7)]:s+=window(x,y,w,h,'glass',True)
 s+=rect(311,49,21,1,'#efcf93')+wall(332,18,13,49,'#d99c40')+rect(334,23,11,1,'#f2bd6c')
 for x,y,w,h in [(336,28,6,5),(336,41,6,6),(337,55,4.5,6.5)]:s+=window(x,y,w,h,'glass')
 # Less regular patches, detached plaster, sill drips, masonry peeking through.
 for x0,x1,y0,y1 in [(10,40,29,65),(140,171,28,67),(174,193,39,66),(195,254,39,65),(256,330,40,65)]:
  for k in range(int((x1-x0)*1.4)):
   x=rr.uniform(x0,x1);y=rr.uniform(y0,y1)
   if k%4==0:s+=path(f'M{f(x)} {f(y)}l1 -.2l.8 .4l-.3 .8h-1.3Z',rr.choice(['#9a793f','#f1cb87','#b89558']),rr.uniform(.1,.27))
 # Facade edge wear and small irregular patches interrupt perfectly planar rows.
 for x,y0,y1 in [(10,28,64),(41,28,65),(139,28,66),(171,29,66),(194,39,65),(211,39,65),(230,39,65),(255,26,66),(278,24,66),(294,39,66),(310,38,66),(332,20,66)]:
  s+=line(x,y0,x+.15,y1,'#695333',.55,.65)
  for k in range(8):
   yy=rr.uniform(y0,y1);s+=rect(x+.3,yy,rr.uniform(.25,.8),rr.uniform(.8,2.5),'#f0c78b',rr.uniform(.25,.6))
 for x,y in [(23,38),(36,51),(146,38),(161,51),(182,47),(198,48),(219,50),(238,48),(249,50),(268,51),(288,38),(319,51)]:
  s+=path(f'M{x} {y}l3 -.2l1 .4l-.2 .6l-2 .4l-2 -.3Z','#efca8a',.68)
 # House foundations cantilever beyond stone bridge; timber braces and stone corbels.
 s+=path('M138 66L172 67L171 70L140 69Z','#6c623f')+path('M172 66H333V69L196 70Z','#9b7c46')
 for x,y in [(142,69),(149,69),(159,69),(181,68),(197,68),(202,68),(209,68),(217,69),(225,69),(233,69),(249,69),(258,69),(265,69),(279,69),(292,69),(305,69),(318,69),(336,69)]:
  s+=poly([(x,y),(x+1.8,y),(x+1.3,y+rr.uniform(4,8)),(x,y+rr.uniform(4,8))],'#645735',.8)
 s+=line(194,82,202,69,'#ddd1a0',1.4)+line(195,83,204,70,'#4e5435',.7)+line(203,78,210,69,'#c2b384',1.1)+line(4,81,11,68,'#5d5635',1.1)
 s+='</g>'
 p=write_part(R/'parts/bitmap-1784.svg',[0,0,W,H],s);return p

def arcade():
 W,H=238,219
 defs=alphaclip(1789)+'''<linearGradient id="columnLeft" x2="1" y2="0"><stop stop-color="#312013"/><stop offset=".12" stop-color="#79522f"/><stop offset=".34" stop-color="#c49a60"/><stop offset=".55" stop-color="#b88c50"/><stop offset=".72" stop-color="#76502e"/><stop offset=".81" stop-color="#492d19"/><stop offset=".88" stop-color="#ad804b"/><stop offset="1" stop-color="#b49059"/></linearGradient><linearGradient id="columnRight" x2="1" y2="0"><stop stop-color="#342214"/><stop offset=".13" stop-color="#694025"/><stop offset=".32" stop-color="#ac7b45"/><stop offset=".55" stop-color="#c5a16a"/><stop offset=".72" stop-color="#b69158"/><stop offset=".89" stop-color="#9b713f"/><stop offset="1" stop-color="#6a472b"/></linearGradient>'''+material('arcadeNoise',W,H,1789,3,1.25)
 defs+='''<linearGradient id="limestone" x1="0" y1="0" x2="1" y2=".7"><stop stop-color="#c39c66"/><stop offset=".25" stop-color="#b88a52"/><stop offset=".6" stop-color="#a67a46"/><stop offset="1" stop-color="#bb8e56"/></linearGradient><linearGradient id="column" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#2c2417"/><stop offset=".13" stop-color="#927046"/><stop offset=".36" stop-color="#c29a62"/><stop offset=".61" stop-color="#ad7d46"/><stop offset=".91" stop-color="#6e3d22"/><stop offset="1" stop-color="#30291c"/></linearGradient><linearGradient id="beam" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#c9ae7e"/><stop offset=".35" stop-color="#ba935d"/><stop offset=".72" stop-color="#b18952"/><stop offset="1" stop-color="#5a3d25"/></linearGradient><linearGradient id="base" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#d2b480"/><stop offset=".35" stop-color="#9f7648"/><stop offset=".7" stop-color="#b08b55"/><stop offset="1" stop-color="#433724"/></linearGradient><linearGradient id="keystone" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#d0ac76"/><stop offset=".6" stop-color="#b58d57"/><stop offset="1" stop-color="#70512e"/></linearGradient>'''
 s='<defs>'+defs+'</defs><g id="stone-arcade" clip-path="url(#originalAlpha)">'
 s+=rect(0,0,238,219,'url(#limestone)')
 # Wide spandrels remain structural slabs. Dark upper crevice reads as depth.
 s+=rect(0,21,238,4,'#392416',.85)+rect(3,25,232,2,'#84532e',.45)
 s+=path('M14 26V91H18C28 52 55 25 96 24Z','#aa7945')+path('M127 24C165 28 195 52 207 92H223V25Z','#b3824a')
 s+='<defs><linearGradient id="under-beam" x2="0" y2="1"><stop stop-color="#31160b" stop-opacity=".85"/><stop offset="1" stop-color="#7b4522" stop-opacity="0"/></linearGradient><linearGradient id="sideShadow" x2="1" y2="0"><stop stop-color="#3c2113" stop-opacity=".85"/><stop offset="1" stop-color="#6d3d1f" stop-opacity="0"/></linearGradient></defs>'
 s+=rect(13,24,210,8,'url(#under-beam)')+rect(16,26,6,65,'url(#sideShadow)')+rect(225,26,6,65,'url(#sideShadow)')
 # Inset architectural pilaster channels and warm recessed side wall.
 s+=rect(1,23,13,71,'url(#columnLeft)')+rect(14,24,2,69,'#37281a')+rect(16,25,1.1,66,'#d1a16b',.9)
 s+=rect(222,23,16,72,'url(#columnRight)')+rect(220.7,25,1.4,68,'#654326')+rect(223,25,.6,68,'#deb783',.8)
 s+=path('M16 94C31 44 59 23 99 23H126C168 25 196 51 209 94H201C187 54 160 31 125 30H100C65 30 36 51 24 94Z','#70502d')
 # Full arch courses. Inner layers extend to transparent boundary for visible thickness.
 curves=[('M17 94C31 45 59 24 99 24L126 24C167 26 195 51 208 94','#594026',4.2),('M17 93C31 45 60 24 99 24L126 24C167 26 194 51 208 93','#c19a61',.85),('M20 94C33 47 62 26 100 26L126 26C164 28 192 53 205 94','#67462a',1.1),('M21.5 94C35 49 63 28 100 28L126 28C164 29 190 54 203.5 94','#9d7142',.8),('M24 94C36 51 65 30 100 30L125 30C160 31 187 55 201 94','#302014',4.1)]
 for d,c,w in curves:s+=path(d,'none',1,f'stroke="{c}" stroke-width="{w}"')
 # Arch voussoir seams are shallow irregular cuts, not exaggerated wedge sectors.
 for x1,y1,x2,y2 in [(20,79,27,81),(28,61,34,65),(40,45,45,50),(57,32,61,38),(77,25,79,31),(145,28,143,33),(166,37,162,42),(184,53,179,57),(197,73,191,76)]:
  s+=line(x1,y1,x2,y2,'#654529',.45,.72)+line(x1+.6,y1,x2+.6,y2,'#b8945d',.3,.35)
 s+=path('M19 93C33 46 62 25 99 25L126 25C166 27 194 52 206 93','none',.4,'stroke="#4c2e18" stroke-width="1.25"')
 # Vertical columns: long slightly asymmetrical stone shafts and recessed inner edges.
 s+=rect(0,99,24,91,'url(#columnLeft)')+rect(199,99,39,91,'url(#columnRight)')
 s+=rect(17,101,6.8,87,'#ba8c53',.08)+line(16,101,16,187,'#5e4226',.55)+line(18,102,18,186,'#c09b63',.45)+line(23.5,101,23.5,190,'#5d4529',.8)
 s+=rect(203,101,19,87,'#bb8750',.04)+line(201,101,201,187,'#302318',.8)+line(203,102,203,187,'#d1aa76',.6)+line(222,101,222,187,'#644326',.55)+line(223.2,101,223.2,188,'#c8a16b',.4)
 # Thin accumulated soot tucked beneath capital and at the shaft sides.
 s+=rect(1,100,23,3,'#48301c',.6)+rect(199,100,39,3,'#4e321c',.6)
 # Bottom column bases. Multiple moulding steps have brighter shoulders and dark undersides.
 for x,w in [(0,24),(199,39)]:
  s+=rect(x,187,w,2,'#594126')+rect(x,188,w,2,'#c6a273')+rect(x,190,w,2,'#715230')+rect(x,192,w,2,'#b4905b')
 s+=path('M0 194H24L31 201V219H0Z','url(#base)')+path('M199 194H238V219H192V201Z','url(#base)')
 s+=path('M0 193H24L29 198H0Z','#cfaa72')+line(0,199,30,199,'#4d3721',.9)+line(192,199,238,199,'#4d3721',.9)+path('M199 193H238V198H194Z','#c5a16c')
 # Low sill stepping stones retain source gaps and bevels.
 for i,(x,w) in enumerate([(32,24),(59,24),(86,25),(112,25),(140,24),(167,25)]):
  s+=rect(x,202,w,12,'#57442c')
  s+=path(f'M{x+2} 202.4H{x+w-3}Q{x+w-1} 202.4 {x+w-.6} 205V211.5Q{x+w-1} 213 {x+w-3} 213H{x+2}Q{x+.3} 212.4 {x+.4} 210.7V204.7Q{x+.6} 203 {x+2} 202.4Z','url(#base)')
  s+=path(f'M{x+2} 202.7H{x+w-3}Q{x+w-1.5} 203 {x+w-1} 204.5L{x+1} 204.7Q{x+.9} 203.5 {x+2} 202.7Z','#c8ad7c')
  s+=line(x+2,205.1,x+w-2,205,'#8a633b',.4,.65)+line(x+w-.8,206,x+w-.8,211,'#bb9c6c',.5,.6)
  s+=path(f'M{x+.6} 210.8Q{x+w*.4} 211.9 {x+w-1} 210.7V213.4H{x+.6}Z','#4b3924',.36)
 # Upper entablature beams, mortared slab joints and irregular edge chips.
 s+=rect(0,0,238,17,'url(#beam)')+rect(0,16.3,238,1.4,'#352719')+rect(0,17.8,238,4.6,'url(#beam)')+rect(0,22.1,238,1,'#241b13')
 for x in [32,98,125,190]:
  s+=line(x,1,x,22.3,'#4a3521',.75)+line(x+1,1,x+1,21.7,'#dfbf89',.65)
 s+=line(1,.8,238,.8,'#ead1a0',.85,.9)+line(1,16,238,16,'#dbc294',.7,.9)+line(1,21.3,238,21.3,'#b99460',.65)
 s+=rect(91,2,8,21,'url(#sideShadow)',.85)+path('M93 3L98 2V25H89L92 18Z','#332113',.25)+rect(0,1,6,15,'url(#sideShadow)',.75)
 # Center keystone projects beyond the flat beam and over the arch crown.
 s+=path('M97 0H125V30L121 34H99L97 29Z','#38271b',.72)
 s+=path('M99 0H124V28L121 31H99Z','url(#keystone)')+line(99.4,1,99.4,28,'#c7a574',.8)+line(123.6,1,123.6,28,'#80603d',.8)+path('M99 28L121 28V31H99Z','#5d4025',.5)
 # Stone capitals at spring line: asymmetric crop is faithful to the source.
 for x,w in [(0,28),(195,43)]:
  s+=rect(x,93,w,2,'#c0a071')+rect(x,95,w,2,'#705031')+rect(x,97,w,3,'url(#base)')+rect(x,100,w,1,'#392719')+line(x,93.4,x+w,93.4,'#e0be83',.65)+line(x,98,x+w,98,'#cba870',.55)
 # Independent multiscale mineral overlay. Original RGB never enters this map.
 s+=rect(0,0,238,219,'url(#arcadeNoise)',.7)
 # Low contrast worn fractures and chips concentrated on corners, not random scratches.
 rr=np.random.default_rng(7891789)
 for x0,x1,y0,y1 in [(1,23,102,185),(201,236,102,185),(0,237,2,15),(2,94,25,34),(129,235,25,35),(2,28,202,216),(195,236,202,216)]:
  for k in range(30):
   x=rr.uniform(x0,x1);y=rr.uniform(y0,y1);dx=rr.uniform(.4,2.3);dy=rr.uniform(.2,1.7)
   s+=poly([(x,y),(x+dx,y+.2),(x+dx*.7,y+dy),(x-.2,y+dy*.7)],rr.choice(['#ead1a3','#684a2d','#9b713e']),rr.uniform(.13,.28))
 for x,y in [(4,112),(10,168),(210,136),(230,161),(61,7),(174,11),(4,46),(229,55)]:
  s+=path(f'M{x} {y}l1.2 1.3l-.6 2.1l1.4 1.8l-.7 1.5','none',.4,'stroke="#6c4c2e" stroke-width=".38"')
 s+='</g>'
 return write_part(R/'parts/bitmap-1789.svg',[0,0,W,H],s)

def previews(n,p):
 im=Image.open(R/f'reference/{n}.png');w,h=im.size
 render(p,w,R/f'previews/river-{n}-1x.png');render(p,w*4,R/f'previews/river-{n}-new.png')
 for scale in [1,4]:
  a=Image.new('RGB',(w*scale*2+12,h*scale+26),'#303539');d=ImageDraw.Draw(a)
  o=im.resize((w*scale,h*scale),Image.Resampling.NEAREST);new=Image.open(R/(f'previews/river-{n}-'+('1x.png' if scale==1 else 'new.png')))
  for j,pic in enumerate([o,new]):
   a.paste(pic,(j*(w*scale+12),26),pic);d.text((j*(w*scale+12)+5,6),['ORIGINAL','EDITABLE REDRAW'][j],fill='white')
  a.save(R/f'previews/river-{n}-compare-{scale}x.png')

def main():
 for n,p in [(1784,bridge()),(1789,arcade())]:previews(n,p)
 records={str(n):{'native':Image.open(R/f'reference/{n}.png').size,'svg_sha256':hashlib.sha256((R/f'parts/bitmap-{n}.svg').read_bytes()).hexdigest()} for n in [1784,1789]}
 (R/'qa/river-arcade-method.json').write_text(json.dumps({'method':'Manually authored editable SVG architecture, independently synthesized multiscale mineral PNG surface patterns, editable river waves. Source alpha only traced into vector clip to retain exact original footprint. No original RGB sampled, filtered or embedded.','reference_assistance':'Original images inspected for silhouette, landmark proportions, warm palette, arch thickness and building arrangement. Exact source alpha trace is disclosed.','passes':['Pass 0: first image inspected at native and 4x; coarse texture, regular windows and flat river found.','Pass 1: reduced stone noise, restored form shadows, irregularized gallery windows, rebuilt directional water reflection.','Pass 2: inspected native and 4x side by side; softened brick joints, individually varied window recesses/shutters, added facade wear and broken brighter water ribbons. Independent review requested round column volume, unequal arch bevel lighting, blunt sill stones, brown pier depth and crisper ripples. All addressed; independent final visual review accepted as a composite candidate with no new silhouette/connectivity defect.'], 'assets':records},indent=2))
if __name__=='__main__':main()
