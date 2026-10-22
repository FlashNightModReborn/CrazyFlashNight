"""CF6 a10/a13 elevator: hand-authored editable, native-coordinate reconstruction.

Four bitmap replacements. Original image alpha is used only for coverage and
registration; no original RGB pixels are sampled, traced, embedded or upscaled.
All mechanical planes, perspective lattice, plates, fittings and lights are new
SVG geometry. Optional micro-grain is deterministic independently synthesized
material, not a picture of the object. Source rebuilds everything locally.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np, io, base64, json, hashlib, math
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from svg_native import write_part,render,inner
R=Path(__file__).resolve().parents[1]
IDS=[1412,1873,1877,1882]
def f(x):return ('%.4f'%x).rstrip('0').rstrip('.')
def path(d,c='none',stroke=None,w=.6,op=1,extra=''):
 return f'<path d="{d}" fill="{c}" opacity="{f(op)}"'+(f' stroke="{stroke}" stroke-width="{f(w)}" stroke-linejoin="round"' if stroke else '')+f' {extra}/>'
def rect(x,y,w,h,c,op=1,extra=''):return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" fill="{c}" opacity="{f(op)}" {extra}/>'
def line(x,y,xx,yy,c,w=.5,op=1):return path(f'M{f(x)} {f(y)}L{f(xx)} {f(yy)}','none',c,w,op)
def poly(pts,c,stroke=None,w=.6,op=1):return path('M'+'L'.join(f'{f(x)} {f(y)}' for x,y in pts)+'Z',c,stroke,w,op)
def circle(x,y,r,c,op=1):return f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{c}" opacity="{f(op)}"/>'
def bolt(x,y,r=1.1):
 return circle(x+.15,y+.3,r+.3,'#0e1214')+circle(x,y,r,'#5c6262')+circle(x-.13,y-.2,r*.72,'#929796',.65)+line(x-r*.45,y+.15,x+r*.45,y-.2,'#171d20',.34)
def label(text,x,y,w,h,c):
 font=TTFont(str(R/'reference/fonts/DejaVuSans-Bold.ttf'));gs=font.getGlyphSet();cm=font.getBestCmap();cur=0;s=[]
 for c0 in text:
  g=gs[cm[ord(c0)]];p=SVGPathPen(gs);g.draw(p);s.append(f'<path transform="translate({cur})" d="{p.getCommands()}"/>');cur+=g.width
 return f'<g fill="{c}" transform="translate({x} {y+h}) scale({w/cur} {-h/1493})">'+''.join(s)+'</g>'
def alpha(n):
 a=np.array(Image.open(R/f'reference/{n}.png').getchannel('A'));H,W=a.shape;d={}
 for y,row in enumerate(a):
  edges=np.r_[0,np.flatnonzero(row[1:]!=row[:-1])+1,W]
  for l,r in zip(edges[:-1],edges[1:]):
   v=int(row[l])
   if v:d.setdefault(v,[]).append(f'M{l} {y}h{r-l}v1h{l-r}Z')
 return f'<mask id="coverage" maskUnits="userSpaceOnUse" x="0" y="0" width="{W}" height="{H}" style="mask-type:alpha">'+''.join('<path d="'+''.join(p)+f'" fill="#fff" opacity="{(v-.5 if v==254 else v)/255:.9f}"/>' for v,p in sorted(d.items()))+'</mask>'
def grain(name,w,h,seed,strength=.5):
 rng=np.random.default_rng(seed);W,H=w*3,h*3
 def n(x,y):return np.array(Image.fromarray(rng.uniform(-1,1,(y,x)).astype('float32'),'F').resize((W,H),Image.Resampling.BICUBIC))
 a=.38*n(max(2,w//38),max(2,h//35))+.3*n(max(2,w//7),max(2,h//7))+.14*n(max(2,w//2),max(2,h//2))+.10*rng.normal(0,1,(H,W))
 rgb=np.where((a>0)[...,None],[190,199,201],[1,5,7]);rgba=np.dstack([rgb,np.minimum(abs(a)*115*strength,65)]).astype('uint8')
 buf=io.BytesIO();Image.fromarray(rgba).save(buf,format='PNG',optimize=True)
 return f'<pattern id="{name}" patternUnits="userSpaceOnUse" width="{w}" height="{h}"><image width="{w}" height="{h}" href="data:image/png;base64,{base64.b64encode(buf.getvalue()).decode()}"/></pattern>'
def metaldefs(w,h,seed):
 return '''<linearGradient id="face" x2=".8" y2=".25"><stop stop-color="#555b5b"/><stop offset=".26" stop-color="#646a69"/><stop offset=".72" stop-color="#4a5050"/><stop offset="1" stop-color="#353c3d"/></linearGradient>
 <linearGradient id="frontbeam" x2="0" y2="1"><stop stop-color="#6c7170"/><stop offset=".15" stop-color="#5c6261"/><stop offset=".8" stop-color="#4e5554"/><stop offset="1" stop-color="#737975"/></linearGradient>
 <linearGradient id="top" x2="0" y2="1"><stop stop-color="#8b918e"/><stop offset=".32" stop-color="#747a78"/><stop offset="1" stop-color="#515957"/></linearGradient>
 <linearGradient id="side" x2="1" y2="0"><stop stop-color="#21292b"/><stop offset=".5" stop-color="#343c3d"/><stop offset="1" stop-color="#434b4a"/></linearGradient>
 <linearGradient id="post" x2="1" y2="0"><stop stop-color="#2d3435"/><stop offset=".2" stop-color="#606764"/><stop offset=".44" stop-color="#717773"/><stop offset=".75" stop-color="#535b58"/><stop offset="1" stop-color="#282f30"/></linearGradient>
 <linearGradient id="tube" x2="0" y2="1"><stop stop-color="#a2a6a0"/><stop offset=".17" stop-color="#aeb2ab"/><stop offset=".32" stop-color="#848b83"/><stop offset=".7" stop-color="#424a48"/><stop offset="1" stop-color="#232d2c"/></linearGradient>
 <linearGradient id="deck" x2="0" y2="1"><stop stop-color="#383f3f"/><stop offset="1" stop-color="#5f6764"/></linearGradient>
 <linearGradient id="rail" x2="1" y2="0"><stop stop-color="#161d1e"/><stop offset=".35" stop-color="#606964"/><stop offset=".6" stop-color="#747c75"/><stop offset="1" stop-color="#293230"/></linearGradient>
 <linearGradient id="panel" x2=".7" y2="1"><stop stop-color="#777d77"/><stop offset=".5" stop-color="#646d65"/><stop offset="1" stop-color="#414c45"/></linearGradient>'''+grain('grain',w,h,seed,.6)
def start(n,defs=''):return '<defs>'+alpha(n)+defs+'</defs><g id="new-native-art" mask="url(#coverage)">'
def finish(n,s):
 w,h=Image.open(R/f'reference/{n}.png').size
 p=write_part(R/f'parts/bitmap-{n}.svg',[0,0,w,h],s+'</g>');render(p,w*4,R/f'previews/elevator-{n}-4x.png');render(p,w,R/f'previews/elevator-{n}-native.png');return p

def lamp():
 n=1412;s=start(n,metaldefs(63,27,n)+'''<linearGradient id="glazing" x2="0" y2="1"><stop stop-color="#143c39"/><stop offset=".3" stop-color="#3c9285"/><stop offset=".48" stop-color="#93d1b8"/><stop offset=".55" stop-color="#2d8478"/><stop offset="1" stop-color="#1e5851"/></linearGradient>''')
 s+=rect(0,0,63,27,'#101819')+poly([(0,0),(63,0),(58,5),(5,5)],'url(#top)')+poly([(0,27),(63,27),(58,22),(5,22)],'url(#side)')
 s+=poly([(0,0),(5,5),(5,22),(0,27)],'#444f4f')+poly([(63,0),(58,5),(58,22),(63,27)],'#252f30')
 s+=rect(5,5,53,17,'#121c1c')+rect(7,6.5,49,14,'#82938a')+rect(8.2,7.5,46.5,12,'#0e2927')+rect(10,9,43,9,'url(#glazing)')
 for y in [9.8,16.4]:s+=line(10,y,53,y,'#5fcbb7',1.8,.95)+line(10,y-.4,53,y-.4,'#a1ddc5',.42,.65)
 s+=rect(9.8,12,43.5,2.8,'#102a29')
 for x in np.arange(10.5,53,1.85):s+=line(x,12.1,x,14.8,'#47716b',.38,.75)
 s+=line(9.8,12,53.3,12,'#60998c',.35,.5)+line(9.8,15.2,53.3,15.2,'#0e2423',.5,.9)
 s+=line(7,6.6,56,6.6,'#c0c8b9',.55,.8)+line(7,20.5,56,20.5,'#5a6c61',.6,.8)
 for x,y in [(3,4),(60,4),(3,23),(60,23)]:s+=bolt(x,y,.65)
 s+=rect(0,0,63,27,'url(#grain)',.5);return finish(n,s)

def wall():
 n=1873;w,h=700,182
 defs='''<linearGradient id="wall" x2="0" y2="1"><stop stop-color="#111a1d"/><stop offset=".5" stop-color="#1b272b"/><stop offset="1" stop-color="#101a1e"/></linearGradient><linearGradient id="curve" x2="1" y2="0"><stop stop-color="#000609" stop-opacity=".44"/><stop offset=".2" stop-color="#01090d" stop-opacity=".08"/><stop offset=".5" stop-color="#3a4446" stop-opacity="0"/><stop offset=".8" stop-color="#01090d" stop-opacity=".08"/><stop offset="1" stop-color="#000609" stop-opacity=".44"/></linearGradient>'''+grain('wallgrain',w,h,n,.10)
 # Curved rows follow the original cylinder cross-section. The boundaries flatten at centre and steepen at both edges.
 def yy(x,b):return b+165*(1-math.sqrt(max(0,1-((x-350)/360)**2)))
 def curve(b,reverse=False):
  xs=list(range(0,701,25));xs=xs[::-1] if reverse else xs
  return 'L'.join(f'{x} {f(yy(x,b))}' for x in xs)
 s=start(n,defs)+rect(0,0,w,h,'url(#wall)')
 rng=np.random.default_rng(n)
 for r,b in enumerate([-175,-111,-47,17,81,145]):
  xs=[0,36,105,223,345,465,588,661,700]
  for j,(x0,x1) in enumerate(zip(xs[:-1],xs[1:])):
   a=[(x,yy(x,b)) for x in range(x0,x1,10)]+[(x1,yy(x1,b))]
   c=[(x,yy(x,b+64)) for x in range(x1,x0,-10)]+[(x0,yy(x0,b+64))]
   val=int(rng.integers(21,24));col=f'#{val:02x}{val+6:02x}{val+8:02x}'
   gid=f'plate{r}_{j}';off=yy((x0+x1)/2,b);top=val+13;bot=val-5
   s+=f'<defs><linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="0" x2="0" y1="{off}" y2="{off+64}"><stop stop-color="#{top:02x}{top+5:02x}{top+7:02x}"/><stop offset="1" stop-color="#{bot:02x}{bot+6:02x}{bot+8:02x}"/></linearGradient></defs>'
   s+=poly(a+c,f'url(#{gid})')
   s+=path('M'+'L'.join(f'{f(x)} {f(y)}' for x,y in a),'none','#536063',.55,.13)
   s+=line(x1,yy(x1,b)+.4,x1,yy(x1,b+64)-.2,'#080f13',.55,.33)+line(x1+.7,yy(x1,b)+.4,x1+.7,yy(x1,b+64)-.2,'#5b696a',.35,.10)
   # Broad burnished steel streak, carefully subordinate to cylinder shading.
   for k in range(3):
    xx=rng.uniform(x0+1,x1-1);y0=yy(xx,b)+rng.uniform(4,23)
    s+=line(xx,y0,xx+rng.uniform(-2,2),y0+rng.uniform(15,31),'#77827f',rng.uniform(.15,.6),rng.uniform(.025,.055))
 s+=rect(0,0,w,h,'url(#wallgrain)',.65)+rect(0,0,w,h,'url(#curve)')
 return finish(n,s)

def worn_strokes(x,y,w,h,seed,count=30,vertical=False):
 rng=np.random.default_rng(seed);s=''
 for i in range(count):
  xx=rng.uniform(x,x+w);yy=rng.uniform(y,y+h);ln=rng.uniform(.7,5);col=rng.choice(['#b3b5aa','#252e2f','#787f78'])
  if vertical:s+=line(xx,yy,min(x+w,xx+rng.uniform(-.2,.2)),min(y+h,yy+ln),col,.22,rng.uniform(.06,.2))
  else:s+=line(xx,yy,min(x+w,xx+ln),yy+rng.uniform(-.18,.18),col,.22,rng.uniform(.06,.2))
 return s

def warning(x,y,w=9,h=13):
 # Paper wraps around the upright edge, with proportional red/ochre header and separate fine ink.
 face=w*.8;sk=min(4,w*.13);hh=h*.32
 s=poly([(x,y+1),(x+face,y+1),(x+w,y-sk),(x+w,y+h-sk),(x+face,y+h+1),(x,y+h+1)],'#979d91','#3e4842',.3)
 s+=poly([(x+.6,y+1.6),(x+face,y+1.6),(x+w-.5,y-sk+.7),(x+w-.5,y+hh-sk),(x+face,y+hh+1),(x+.6,y+hh+1)],'#8c7134')
 s+=label('DANGER',x+1,y+2,face-2,hh-1,'#9d422b')
 s+=poly([(x+face,y+hh+1),(x+w,y+hh-sk),(x+w,y+h-sk),(x+face,y+h+1)],'#727b6f')
 for v in [.51,.65,.8]:s+=line(x+1,y+h*v,x+face-1,y+h*v,'#424d43',max(.28,h*.027),.75)
 s+=line(x+face,y+2,x+face,y+h,'#4c574b',.3,.55)
 return s

def folded_triangle(seam,y,left,right,height,tag,slope,front='#8c884d',side='#545a34',small_label=False):
 # A surface decal, split exactly at the upright's physical front/side edge.
 # The side copy shears with the column (12:10 front post; 11:9 rear post).
 tri=[(left,y+height),(seam,y),(right,y+height)]
 def ink(fill,edge,boltfill,label_fill):
  z=poly(tri,fill,edge,.42)
  span=right-left
  pts=[(seam-.04*span,y+.20*height),(seam-.25*span,y+.61*height),(seam-.04*span,y+.61*height),(seam-.22*span,y+.94*height),(seam+.19*span,y+.44*height),(seam+.01*span,y+.44*height)]
  z+=poly(pts,boltfill)
  if small_label:
   z+=rect(left+1,y+height+.8,span-3,3.8,label_fill,.9)
   z+=line(left+2,y+height+2,right-3,y+height+2,boltfill,.35,.65)+line(left+2.5,y+height+3.4,right-3.5,y+height+3.4,boltfill,.28,.6)
  return z
 d=f'<defs><clipPath id="{tag}-front">'+rect(left-2,y-2,seam-left+2,height+10,'white')+f'</clipPath><clipPath id="{tag}-side">'+rect(seam,y-2,right-seam+2,height+10,'white')+'</clipPath></defs>'
 d+=f'<g id="{tag}-front-decal" clip-path="url(#{tag}-front)">'+ink(front,'#414d3b','#35432f','#92998a')+'</g>'
 d+=f'<g id="{tag}-side-decal" transform="matrix(1 {-slope} 0 1 0 {slope*seam})" clip-path="url(#{tag}-side)">'+ink(side,'#2c3c2c','#1e301f','#53664c')+'</g>'
 return d

def platform():
 n=1877;w,h=480,453;s=start(n,metaldefs(w,h,n))+rect(0,0,w,h,'#242b2b')
 # Guide rails extend above/below the car and stay behind all structural members.
 for x in [155,304]:
  s+=rect(x,0,11,453,'url(#rail)')+line(x+.8,0,x+.8,453,'#090f10',.8)+line(x+3,0,x+3,453,'#889085',.5,.45)+line(x+9.5,0,x+9.5,453,'#101719',.7)
  s+=worn_strokes(x+2,2,7,449,n+x,85,True)
 # Rear uprights: front and inside faces retain original perspective and width.
 s+=poly([(60,35),(74,35),(74,307),(60,307)],'url(#post)','#171e1f',.8)
 s+=poly([(74,35),(85,26),(85,307),(74,307)],'url(#side)','#11181a',.8)
 s+=poly([(394,26),(406,35),(406,307),(394,307)],'url(#side)','#11181a',.8)
 s+=poly([(406,35),(420,35),(420,307),(406,307)],'url(#post)','#171e1f',.8)
 # Upper crosshead and rear-facing corner caps.
 s+=poly([(74,52),(406,52),(417,61),(63,61)],'url(#top)','#202828',.7)
 s+=rect(74,61,332,11,'url(#frontbeam)')+line(75,61.7,405,61.7,'#a0a69c',.55,.7)+line(75,71.6,405,71.6,'#111b1c',.85)
 s+=poly([(0,97),(60,53),(74,62),(31,97)],'url(#top)','#161e20',.75)
 s+=poly([(31,97),(74,62),(74,73),(31,117)],'url(#side)','#141b1d',.8)
 s+=rect(0,97,31,20,'url(#face)')+line(.8,97.6,30,97.6,'#939b91',.6,.65)
 s+=poly([(406,62),(420,53),(480,97),(449,97)],'url(#top)','#161e20',.75)
 s+=poly([(406,62),(449,97),(449,117),(406,73)],'url(#side)','#141b1d',.8)
 s+=rect(449,97,31,20,'url(#face)')+line(450,97.6,479,97.6,'#939b91',.6,.65)
 for pts in [[(60,35),(72,25),(85,25),(74,35)],[(394,25),(407,25),(420,35),(406,35)]]:s+=poly(pts,'url(#top)','#1d2526',.7)
 for x in [60,406]:s+=rect(x,35,14,27,'url(#face)')+line(x+.7,35.5,x+13.3,35.5,'#a1a69b',.55,.65)
 # Small fasteners and narrow weld seams, kept inside the old material footprint.
 for x in [63,82,398,417]:
  for y in [69,301]:s+=bolt(x,y,.8)
 for x in [68,412]:s+=worn_strokes(x-6,75,12,228,n+x,95,True)
 s+=folded_triangle(74,199.5,63.5,80,12.5,'rear-left-voltage',9/11,'#858b79','#4c5b48',True)
 s+=warning(406,219,10,13)
 # Rear guardrail, solid cylindrical handrail and six thin balusters.
 for x in [76,99,149,198,273,323,373,398]:
  s+=rect(x,255,7.6,52,'url(#rail)')+line(x+.9,256,x+.9,306,'#9aa195',.45,.6)
 s+=path('M75 248H405Q408 253 405 258H75Q72 253 75 248Z','url(#tube)','#1d2829',.55)
 s+=line(76,249.6,404,249.6,'#b4b8ac',.6,.65)
 # Floor deck plane (all holes are dark recesses, not transparent cutouts).
 deck=[(60,306),(420,306),(480,367),(0,367)]
 s+=poly(deck,'url(#deck)','#1b2325',.85)
 # Bilinear projection of five inset grating panels; spacing expands towards camera.
 def proj(u,v):
  q=v*.78+v*v*.22;return (60-60*q+(360+120*q)*u,306+61*q)
 for i in range(5):
  u0=(i+.13)/5;u1=(i+.87)/5;v0=.065;v1=.87
  verts=[proj(u0,v0),proj(u1,v0),proj(u1,v1),proj(u0,v1)]
  s+=poly(verts,'#111b1c','#252e2c',.55)
  # Each steel cell has a dark web, highlight lip, and depth side rather than a texture stamp.
  for row in range(18):
   v=v0+(v1-v0)*row/18;x0,y0=proj(u0,v);x1,y1=proj(u1,v)
   s+=line(x0,y0,x1,y1,'#637066',.67,.85)+line(x0,y0+.65,x1,y1+.65,'#0a1315',.6,.8)
  for k in range(16):
   u=u0+(u1-u0)*k/15;x0,y0=proj(u,v0);x1,y1=proj(u,v1)
   s+=line(x0,y0,x1,y1,'#778176',.62,.85)+line(x0+.6,y0,x1+.6,y1,'#202c28',.4,.9)
  s+=poly(verts,'none','#889186',.5,.65)
 # Perspective beams between grating fields, scraped front nosing, inset bolt rows.
 for u in [0,.2,.4,.6,.8,1]:
  pts=[proj(max(0,u-.011),0),proj(min(1,u+.011),0),proj(min(1,u+.020),1),proj(max(0,u-.020),1)]
  s+=poly(pts,'url(#face)')
  x0,y0=proj(u,0);x1,y1=proj(u,1);s+=line(x0,y0,x1,y1,'#9ba293',.45,.38)
  for v in [.04,.94]:x,y=proj(u,v);s+=bolt(x,y,.72)
 s+=poly([proj(0,.885),proj(1,.885),proj(1,1),proj(0,1)],'url(#top)')
 s+=rect(0,367,480,20,'url(#frontbeam)')+line(1,367.7,479,367.7,'#b0b6aa',.8,.7)+line(1,386.3,479,386.3,'#192325',.8)
 s+=worn_strokes(2,368,476,17,n,180)
 # Central six-slot lift control housing. Bottom slot is the original green indicator.
 s+=poly([(220,254),(224,241),(255,241),(260,254)],'#a0a69c','#182122',.75)
 s+=poly([(220,254),(227,254),(227,311),(220,311)],'url(#side)','#172122',.7)
 s+=rect(227,254,33,57,'url(#panel)')+line(227.8,255,259,255,'#8d9789',.65,.7)+line(259.4,254,259.4,310,'#172421',.8)
 for i in range(6):
  y=258+i*7.5;s+=rect(238,y,18,4.7,'#101915')+line(238,y,256,y,'#29382c',.6)+line(238.5,y+4.7,256,y+4.7,'#84917e',.4,.55)
  if i==5:s+=rect(239.2,y+1,15.6,2.6,'#2b851e')+line(240,y+1.5,254,y+1.5,'#69b449',.5,.8)
  else:s+=rect(239.4,y+1.2,15,2.1,'#26332a')
 for x,y in [(229,256.5),(258,307.5),(222.5,257),(222.5,307)]:s+=bolt(x,y,.55)
 s+=rect(0,0,w,h,'url(#grain)',.65)
 return finish(n,s)

def front():
 n=1882;w,h=480,388;s=start(n,metaldefs(w,h,n))+rect(0,0,w,h,'#303737')
 # Front-frame plane and bevels; no fill is added across the transparent central opening.
 for x in [0,450]:
  s+=rect(x,10,30,378,'url(#post)')+line(x+.8,10,x+.8,387,'#a0a598',.5,.6)+line(x+29.3,10,x+29.3,387,'#111c1d',.8)
  s+=worn_strokes(x+2,13,26,370,n+x,190,True)
 s+=poly([(0,10),(12,0),(42,0),(30,10)],'url(#top)','#141f20',.6)
 s+=poly([(30,10),(42,0),(42,376),(30,388)],'url(#side)','#162022',.65)
 s+=poly([(438,0),(467,0),(480,10),(450,10)],'url(#top)','#141f20',.6)
 s+=poly([(438,0),(450,10),(450,388),(438,376)],'url(#side)','#162022',.65)
 s+=poly([(30,61),(42,51),(438,51),(450,61)],'url(#top)','#1c2727',.65)+rect(30,61,420,19,'url(#frontbeam)')
 s+=line(31,61.7,449,61.7,'#a2aa9c',.65,.7)+line(31,79.4,449,79.4,'#1d2728',.65)
 for x in [0,450]:
  for y in [60,80,330,351]:s+=line(x,y,x+30,y,'#1c2828',.75)+line(x,y+1,x+30,y+1,'#7d887b',.4,.4)
 for x in [4,26,454,476]:
  for y in [64,76,335,347]:s+=bolt(x,y,.65)
 # The two handrail spans deliberately stop before the central entrance gap.
 for a,b in [(40,203),(274,439)]:
  for x in ([40,70,130,190] if a==40 else [280,340,400,431]):
   s+=rect(x,270,8.8,61,'url(#rail)')+line(x+1.2,271,x+1.2,330,'#a1a994',.5,.55)
  s+=path(f'M{a+1} 262H{b-1}Q{b+1} 264 {b} 273H{a}Q{a-1} 267 {a+1} 262Z','url(#tube)','#182625',.55)
  s+=line(a+2,263.5,b-2,263.5,'#b7c0ad',.6,.65)
  for x in [a+3,b-3]:s+=line(x,264,x,272,'#34453b',.45,.7)
 # The two original paper warning plates and small triangular high-voltage marks.
 s+=warning(3.6,153,33,27)+warning(3.6,227,33,27)
 s+=folded_triangle(30,201,19,36,19,'front-left-voltage',10/12)
 s+=poly([(455,240),(465,220),(474,240)],'#92904e','#49523e',.55)
 s+=path('M465 223L461 231H465L462 237L469 228H465Z','#37432f')
 # Existing stencil occupancy retained by the original alpha contract, freshly painted neutral ink.
 s+=rect(374,332,32,19,'#293431')
 s+=label('EXIT',375,334,24,5,'#899589')+label('EXIT',375,341,25,6,'#afb6a7')
 s+=line(375,349,404,349,'#7b8679',.5,.7)+worn_strokes(375,334,25,13,n+99,16)
 s+=rect(0,0,w,h,'url(#grain)',.7)
 return finish(n,s)

def checker(im):
 im=im.convert('RGBA');w,h=im.size;a=np.indices((h,w)).sum(axis=0)*0
 yy,xx=np.indices((h,w));v=np.where(((xx//16+yy//16)%2)[...,None],65,77);rgb=np.repeat(v,3,axis=2).astype('uint8');bg=Image.fromarray(rgb,'RGB').convert('RGBA');bg.alpha_composite(im);return bg.convert('RGB')
def reviews():
 pages=[]
 for n in IDS:
  old=Image.open(R/f'reference/{n}.png').convert('RGBA');new=Image.open(R/f'previews/elevator-{n}-native.png').convert('RGBA');scale=2 if n!=1412 else 8
  w,h=old.size;out=Image.new('RGB',(w*scale*2,h*scale+34),'#252d32');d=ImageDraw.Draw(out)
  out.paste(checker(old).resize((w*scale,h*scale),Image.Resampling.NEAREST),(0,34));out.paste(checker(new).resize((w*scale,h*scale),Image.Resampling.LANCZOS),(w*scale,34));d.text((8,9),f'ORIGINAL {n} / native alpha',fill='white');d.text((w*scale+8,9),'NEW / editable mechanical geometry',fill='white');out.save(R/f'previews/compare-{n}.png')
  a=np.array(old.getchannel('A'));b=np.array(new.getchannel('A'));pages.append({'bitmapId':n,'dimensions':[w,h],'alphaExact':bool(np.array_equal(a,b)),'alphaMaxError':int(abs(a.astype(int)-b.astype(int)).max()),'newOccupiedPixels':int((b>0).sum()),'oldOccupiedPixels':int((a>0).sum())})
 (R/'qa/alpha-contracts.json').write_text(json.dumps(pages,indent=2))
def run():
 for x in ['parts','previews','qa']:R.joinpath(x).mkdir(exist_ok=True)
 out=[]
 for fn in [lamp,wall,platform,front]:
  p=fn();n=int(p.stem.split('-')[1]);w,h=Image.open(R/f'reference/{n}.png').size
  out.append({'bitmapId':n,'nativeSize':[w,h],'svg':str(p.relative_to(R)),'preview4x':f'previews/elevator-{n}-4x.png','source':'source/elevator_materials.py','method':'Hand-authored mechanical vector geometry; original alpha-only coverage; independently synthesized material grain; no original RGB used','sha256':hashlib.sha256(p.read_bytes()).hexdigest()});print('WROTE',p,flush=True)
 (R/'qa/elevator-materials-manifest.json').write_text(json.dumps(out,ensure_ascii=False,indent=2));reviews()
if __name__=='__main__':run()
