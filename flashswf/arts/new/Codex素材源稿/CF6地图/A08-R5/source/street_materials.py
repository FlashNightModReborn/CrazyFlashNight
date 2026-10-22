"""CF6 a8: native-coordinate static street materials, seven hand-authored SVG redraws.
No original RGB is traced, resized, recolored, or embedded. Original alpha is the
only original image channel used, encoded as editable vector mask spans. Small
independently synthesized plaster/metal grain is included in SVG patterns.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np, json, io, base64, hashlib
from scipy.ndimage import gaussian_filter
from svg_native import write_part, render
R=Path(__file__).resolve().parents[1]
IDS=[1404,1405,1414,1415,1817,1820,1821]
def f(x):return ('%.3f'%x).rstrip('0').rstrip('.')
def rect(x,y,w,h,c,op=1,extra=''):return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" fill="{c}" opacity="{f(op)}" {extra}/>'
def path(d,c='none',op=1,extra=''):return f'<path d="{d}" fill="{c}" opacity="{f(op)}" {extra}/>'
def line(x,y,xx,yy,c,w=.5,op=1):return path(f'M{f(x)} {f(y)}L{f(xx)} {f(yy)}','none',op,f'stroke="{c}" stroke-width="{f(w)}" stroke-linecap="round"')
def poly(a,c,op=1):return '<polygon points="'+' '.join(f'{f(x)},{f(y)}' for x,y in a)+f'" fill="{c}" opacity="{f(op)}"/>'
def ellipse(x,y,rx,ry,c,op=1):return f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rx)}" ry="{f(ry)}" fill="{c}" opacity="{f(op)}"/>'
def pngdata(a):
 b=io.BytesIO();Image.fromarray(np.uint8(np.clip(a,0,255))).save(b,format='PNG',optimize=True);return base64.b64encode(b.getvalue()).decode()
def alphamask(n):
 # Alpha coverage only. Batching identical-alpha spans remains fully editable.
 a=np.array(Image.open(R/f'reference/{n}.png').getchannel('A'));H,W=a.shape;by={}
 for y,row in enumerate(a):
  edges=np.r_[0,np.flatnonzero(row[1:]!=row[:-1])+1,W]
  for left,right in zip(edges[:-1],edges[1:]):
   val=int(row[left])
   if val:by.setdefault(val,[]).append(f'M{left} {y}h{right-left}v1h{left-right}Z')
 return f'<mask id="alpha" maskUnits="userSpaceOnUse" x="0" y="0" width="{W}" height="{H}" style="mask-type:alpha">'+''.join('<path d="'+''.join(p)+'" fill="#fff" opacity="'+format(v/255,'.9f')+'"/>' for v,p in sorted(by.items()))+'</mask>'
def grain(name,w,h,seed,strength=1,scale=4):
 rr=np.random.default_rng(seed);W,H=round(w*scale),round(h*scale)
 def noise(sx,sy):
  a=rr.uniform(-1,1,(max(2,round(sy)),max(2,round(sx)))).astype('float32');return np.array(Image.fromarray(a,'F').resize((W,H),Image.Resampling.BICUBIC))
 a=(noise(w/39,h/33)*.055+noise(w/7,h/6)*.12+noise(w/1.2,h/1.2)*.5+rr.normal(0,.14,(H,W))) if name=='plaster' else (noise(w/39,h/33)*.36+noise(w/7,h/6)*.29+noise(w/1.2,h/1.2)*.23+rr.normal(0,.08,(H,W)))
 gy,gx=np.gradient(gaussian_filter(a,.4));a+=gx*.8-gy*.65
 rgba=np.zeros((H,W,4));rgba[:,:,:3]=np.where((a>0)[:,:,None],[181,188,202],[4,7,11]);rgba[:,:,3]=np.minimum(abs(a)*130*strength,125)
 return f'<pattern id="{name}" patternUnits="userSpaceOnUse" width="{w}" height="{h}"><image width="{w}" height="{h}" href="data:image/png;base64,{pngdata(rgba)}"/></pattern>'
def start(n,defs=''):
 return '<defs>'+alphamask(n)+defs+'</defs><g id="native-redraw" mask="url(#alpha)">'
def finish(n,w,h,s):
 s+='</g>';p=write_part(R/f'parts/bitmap-{n}.svg',[0,0,w,h],s);render(p,w*4,R/f'previews/street-{n}-4x.png');render(p,w,R/f'previews/street-{n}-native.png');return p

def vent():
 n=1404;w,h=85,50
 defs='''<linearGradient id="frame" x2=".8" y2="1"><stop stop-color="#637077"/><stop offset=".34" stop-color="#353e43"/><stop offset=".8" stop-color="#20292e"/><stop offset="1" stop-color="#626b6f"/></linearGradient><linearGradient id="louver" x2="0" y2="1"><stop stop-color="#677279"/><stop offset=".12" stop-color="#47535a"/><stop offset=".8" stop-color="#404a51"/><stop offset=".88" stop-color="#242e35"/><stop offset="1" stop-color="#1c262b"/></linearGradient>'''+grain('metalgrain',85,50,n,.45)
 s=start(n,defs)+rect(0,0,w,h,'#0b1013')+rect(1,1,83,48,'url(#frame)')+rect(2.1,2.1,80.8,45.8,'#151e23')
 s+=line(1,1,83,1,'#889297',.6,.8)+line(1,1,1,48,'#677278',.65,.7)+line(83,1,83,48,'#78848a',.65,.65)+line(1,48,83,48,'#727d81',.65,.65)
 s+=rect(3.8,3.5,77.4,43,'#0b1216')
 # Eight bent folded-steel blades, retaining the original compressed perspective.
 for i in range(8):
  y=4.2+i*5.18
  s+=poly([(4.1,y),(80.8,y),(78.6,y+3.75),(6.3,y+3.75)],'url(#louver)')
  s+=line(5.1,y+.55,79.9,y+.55,'#788388',.5,.74)+line(6.7,y+3.7,78.3,y+3.7,'#060b0e',.82)
  s+=line(4.4,y+.4,6.2,y+3.6,'#919596',.55,.45)+line(80.2,y+.3,78.7,y+3.6,'#131b20',.65,.9)
  s+=line(10.2+i*.9,y+1.65,46+i*2.8,y+1.65,'#7a858b',.17,.2)
 s+=rect(0,0,w,h,'url(#metalgrain)',.8)
 for x,y in [(2.6,2.5),(82.1,2.5),(2.6,47.1),(82.1,47.1)]:
  s+=ellipse(x,y,.8,.8,'#111a1f')+ellipse(x-.1,y-.15,.49,.49,'#727e81')+line(x-.35,y+.2,x+.3,y-.2,'#1c2328',.25)
 return finish(n,w,h,s)

def stain():
 n=1405;w,h=57,74;s=start(n)+rect(0,0,w,h,'#11161b')
 # Soft existing transparency is retained; new color work gives cool soot and iron seepage.
 s+=path('M2 0C12 5 16 2 27 6S43 6 57 13V24C37 16 23 18 6 12Z','#26313b',.5)
 for x,y,ww,l,c in [(9,7,4,62,'#080f16'),(15,6,3,41,'#151d26'),(27,13,3,39,'#0a1017'),(39,12,4,47,'#0e151a'),(47,16,2,22,'#252b31')]:
  s+=path(f'M{x} {y}q{ww} -1 {ww} 2l{-ww*.4} {l}q-1 5 -1 -1Z',c,.55)
 return finish(n,w,h,s)

def plaster_wall():
 n=1817;w,h=600,225
 defs='''<linearGradient id="wallshade" x2="0" y2="1"><stop stop-color="#41434e"/><stop offset=".38" stop-color="#393d46"/><stop offset=".65" stop-color="#2d3037"/><stop offset=".84" stop-color="#25272d"/><stop offset="1" stop-color="#202226"/></linearGradient><linearGradient id="wallgrainfade" x2="0" y2="1"><stop stop-color="white"/><stop offset=".55" stop-color="white" stop-opacity=".85"/><stop offset="1" stop-color="white" stop-opacity=".32"/></linearGradient><mask id="wallgrainmask" x="0" y="0" width="600" height="225" maskUnits="userSpaceOnUse"><rect width="600" height="225" fill="url(#wallgrainfade)"/></mask>'''+grain('plaster',600,225,n,.38,4)
 s=start(n,defs)+rect(0,0,w,h,'url(#wallshade)')+rect(0,0,w,h,'url(#plaster)',.68,'mask="url(#wallgrainmask)"')
 rr=np.random.default_rng(n)
 # Extremely subtle streaks, fine pores and worn plaster. No invented block joints.
 for i in range(175):
  x=rr.uniform(0,w);y=rr.uniform(0,h);ww=rr.uniform(.2,1.3);hh=rr.uniform(2,24)
  s+=path(f'M{f(x)} {f(y)}q{f(ww)} -2 {f(ww)} 1l{f(-ww*.35)} {f(hh)}Z',rr.choice(['#181c24','#7b7d86','#4f505a']),rr.uniform(.015,.045))
 for i in range(1800):
  x=rr.uniform(0,w);y=rr.uniform(0,h);rx=rr.uniform(.06,.25);ry=rr.uniform(.05,.18)
  s+=ellipse(x,y,rx,ry,rr.choice(['#969ba6','#101722']),rr.uniform(.02,.09))
 return finish(n,w,h,s)

def ladder():
 n=1820;w,h=57,171
 defs='''<linearGradient id="rail" x2="1" y2="0"><stop stop-color="#12171d"/><stop offset=".27" stop-color="#464b53"/><stop offset=".53" stop-color="#6a7076"/><stop offset=".72" stop-color="#3a4149"/><stop offset="1" stop-color="#181f25"/></linearGradient><linearGradient id="rung" x2="0" y2="1"><stop stop-color="#788086"/><stop offset=".18" stop-color="#5e636b"/><stop offset=".55" stop-color="#3d434b"/><stop offset="1" stop-color="#11171e"/></linearGradient>'''+grain('iron',57,171,n,.6)
 s=start(n,defs)+rect(0,0,w,h,'#1a2026')
 # Alpha mask opens all gaps; only metallic bar regions survive.
 for x in [3,48]:
  s+=rect(x,1,6,169,'url(#rail)')+line(x+1.3,2,x+1.3,169,'#929397',.38,.35)+line(x+5.5,2,x+5.5,169,'#10171c',.65)
  for y in [4,57,113,166]:s+=ellipse(x+3,y,1.2,.9,'#181f24')+ellipse(x+2.8,y-.2,.62,.5,'#8b8d90',.6)
 for i in range(9):
  y=4+i*19.6
  s+=rect(7,y,44,6,'url(#rung)')+line(9,y+.45,48,y+.45,'#7f8489',.5,.7)+line(8,y+5.9,50,y+5.9,'#0b1219',.65)
  s+=rect(7,y+.5,2.1,5,'#333a42',.8)+rect(48.5,y+.5,2,5,'#303840',.8)
  for x in [13+i%3,31+(i%2)*5]:s+=path(f'M{x} {f(y+.65)}l2.7 .12l-.8 .45l-1.7 -.1Z','#9b9690',.32)
 s+=rect(0,0,w,h,'url(#iron)',.7)
 rr=np.random.default_rng(n)
 for i in range(90):
  x=rr.choice([rr.uniform(4.5,7.5),rr.uniform(49.2,51.5)]);y=rr.uniform(4,167)
  s+=line(x,y,x+rr.uniform(-.4,.5),y+rr.uniform(.5,2.3),'#9d8b78',.16,.22)
 return finish(n,w,h,s)

def circuit_hole(n):
 large=n==1414;w,h=(118,134) if large else (74,91)
 # Polygon landmarks explicitly authored from the supplied silhouette, not RGB tracing.
 pts=[(22,73),(15,65),(13,51),(24,43),(27,29),(36,25),(39,20),(51,21),(61,25),(72,19),(82,25),(88,28),(90,42),(91,56),(87,68),(76,76),(63,80),(49,76),(37,78)] if large else [(18,55),(16,48),(17,36),(20,29),(29,25),(31,17),(42,16),(48,19),(54,17),(59,26),(60,42),(57,50),(45,58),(33,59)]
 d='M'+'L'.join(f'{x} {y}' for x,y in pts)+'Z'
 defs=grain('grime',w,h,n,.55)+f'<clipPath id="circuit-interior">{path(d,"#fff")}</clipPath>'
 s=start(n,defs)+rect(0,0,w,h,'#161c1d')
 # The old broken-plaster outline and drips retain alpha; concrete lips remain irregular.
 s+=path(d,'#0a1111')+path(d,'none',1,'stroke="#030707" stroke-width="2.3" stroke-linejoin="round"')
 for j,(x,y) in enumerate(pts):
  xx,yy=pts[(j+1)%len(pts)]
  if yy>y or j%3==1:s+=line(x+.5,y+.5,xx+.5,yy+.5,'#6f7167',.55,.45)
 s+='<g id="exposed-circuit-board" clip-path="url(#circuit-interior)">'+rect(0,0,w,h,'#030b08')
 # Multiple pcb islands, component housings, etched copper tracks, solder points.
 rr=np.random.default_rng(n);xmin,xmax=(20,88) if large else (18,59);ymin,ymax=(24,76) if large else (19,56)
 for i in range(35 if large else 21):
  x=rr.uniform(xmin,xmax-5);y=rr.uniform(ymin,ymax-5);cw=rr.uniform(2,7);ch=rr.uniform(2,6)
  s+=rect(x,y,cw,ch,rr.choice(['#07120c','#0b1a10','#102117','#060e0a']))
  if i%3==0:
   s+=rect(x+.7,y+.7,cw-1.1,ch-1.1,'#030b08')
   for xx in np.arange(x+.8,x+cw,.9):s+=line(xx,y-.45,xx,y+.3,'#69806c',.26,.8)+line(xx,y+ch-.15,xx,y+ch+.7,'#5e7965',.26,.7)
 for i in range(200 if large else 120):
  x=rr.uniform(xmin,xmax);y=rr.uniform(ymin,ymax);ln=rr.uniform(1,11);step=rr.uniform(1,5);direc=rr.choice([-1,1])
  dd=f'M{f(x)} {f(y)}h{f(ln*direc)}v{f(step*rr.choice([-1,1]))}h{f(rr.uniform(1,5)*direc)}'
  s+=path(dd,'none',rr.uniform(.45,.92),f'stroke="{rr.choice(["#355c40","#497957","#254b34","#78927a"])}" stroke-width="{f(rr.uniform(.2,.43))}"')
  if i%3==0:s+=ellipse(x,y,.52,.5,'#a7b5a0',.55)+ellipse(x,y,.19,.19,'#0a1b10')
 for i in range(115 if large else 75):
  x=rr.uniform(xmin,xmax);y=rr.uniform(ymin,ymax)
  s+=rect(x,y,rr.uniform(.4,1.4),.36,'#adbaab',rr.uniform(.22,.66))
 # Ragged dark cavity and projecting concrete thickness hide the board perimeter.
 # The hole must read as a recess with circuitry glimpsed behind it, never a green decal.
 if large:
  shadow_shapes=[
   'M13 50L25 42L29 30L39 22L45 27L37 35L35 49L28 55L30 65L23 73L16 65Z',
   'M39 22L51 22L60 26L71 20L82 25L88 30L82 35L74 31L66 35L59 31L50 34L44 30Z',
   'M84 33L91 41L91 58L87 68L81 71L83 61L79 56L84 50L81 44Z',
   'M27 70L38 72L44 69L52 75L63 77L75 72L85 64L87 71L75 78L63 81L49 77L37 79L23 74Z',
   'M44 41L51 40L52 45L49 50L43 48Z',
   'M65 54L74 52L77 57L73 62L66 61Z']
 else:
  shadow_shapes=[
   'M17 37L20 29L29 25L31 17L39 16L42 21L35 24L34 31L28 32L25 41L21 45L23 52L18 55Z',
   'M41 17L48 19L54 17L59 26L59 33L54 29L50 25L45 28L41 24Z',
   'M57 33L61 41L57 51L45 59L33 60L20 56L25 51L32 55L38 53L43 55L50 49L55 46Z',
   'M36 37L42 35L46 38L44 42L38 42Z']
 for sd in shadow_shapes:s+=path(sd,'#020706',.94)
 s+=path(d,'none',1,'stroke="#020605" stroke-width="3.2" stroke-linejoin="round"')
 s+='</g>'+path(d,'none',1,'stroke="#080c0b" stroke-width="1.2" stroke-linejoin="round"')
 # Scraped pale bottom rim and broken dark cement tongues.
 if large:
  s+=path('M22 73L37 78L49 76L63 80L76 76L87 68','none',1,'stroke="#101715" stroke-width="2.2" stroke-linejoin="round"')
  s+=path('M77 74.5L80 72.6M82 71.6L85 68.8','none',.38,'stroke="#8c8a7c" stroke-width=".48"')
  cracks=['M14 52L6 48L0 49','M25 42L20 33L16 31','M40 23L48 11L50 5','M87 29L102 21L111 17','M89 64L98 66L105 75','M28 77L16 91L9 99','M74 78L76 91L74 113','M42 79L43 96L40 115']
 else:
  s+=path('M18 55L33 59L45 58L57 50','none',1,'stroke="#101715" stroke-width="2.1" stroke-linejoin="round"')
  s+=path('M49 55L51.5 53.4M53.5 52.1L55.2 50.8','none',.35,'stroke="#8c8a7c" stroke-width=".46"')
  cracks=['M20 29L10 21L8 15','M31 18L34 7L34 0','M53 20L66 10','M17 43L8 47L0 49','M57 47L65 56L68 67','M33 59L34 72L33 85']
 for c in cracks:s+=path(c,'none',.82,'stroke="#080e12" stroke-width=".75"')
 s+=rect(0,0,w,h,'url(#grime)',.8)
 return finish(n,w,h,s)

def graffiti():
 n=1821;w,h=133,162
 defs=grain('paintgrain',w,h,n,.65)+'''<linearGradient id="silver" x2="1" y2=".4"><stop stop-color="#828681"/><stop offset=".2" stop-color="#b5b5aa"/><stop offset=".52" stop-color="#4a5152"/><stop offset=".78" stop-color="#90918a"/><stop offset="1" stop-color="#464e50"/></linearGradient><linearGradient id="flame" x2="0" y2="1"><stop stop-color="#4d4b2d"/><stop offset=".55" stop-color="#7b6e28"/><stop offset="1" stop-color="#947d31"/></linearGradient><clipPath id="shieldpaint"><path d="M29 59Q31 54 40 55L103 55L104 89L93 140L43 141L30 101Z"/></clipPath>'''
 s=start(n,defs)+rect(0,0,w,h,'#252c2c')
 # Ragged flame crown, deep outline, faded ochre highlights.
 crown='M5 44L20 48L25 42Q16 28 24 17Q29 8 24 1Q33 13 29 22Q27 33 39 37Q35 25 36 19Q40 31 49 34L56 28Q48 16 53 11L57 5Q53 17 64 25Q68 30 64 39L73 37Q82 24 79 15Q88 25 82 34L79 40L89 43Q103 37 104 27Q107 19 116 13Q107 24 106 32Q104 41 106 46L118 42L126 37Q118 52 107 56L97 52L72 54L46 53L27 56L18 54Z'
 s+=path(crown,'url(#flame)',1,'stroke="#242b2a" stroke-width="1.7" stroke-linejoin="round"')
 for dd in ['M21 47Q32 48 36 42Q26 39 26 28','M38 48Q54 42 56 34','M52 49L66 36','M63 49L73 39','M78 49Q91 48 97 41','M93 50L101 44']:
  s+=path(dd,'none',.45,'stroke="#b09b43" stroke-width="2"')
 # Side rakes and lower splinters retain the old asymmetrical silhouette.
 for dd in ['M33 90L19 99L0 121L23 111L8 128L29 120L18 139L44 127Z','M97 94L114 104L133 122L111 116L128 130L104 120L114 139L92 127Z','M42 137L37 146L46 144L49 157L58 162L51 149L59 141Z','M64 139L75 151L79 162L88 144L92 149L98 140Z']:
  s+=path(dd,'#3a4141',1,'stroke="#252c2b" stroke-width="1.2"')
 for dd in ['M7 119L28 104','M15 125L31 116','M24 134L38 122','M104 105L124 120','M102 116L117 128','M47 144L52 153','M76 143L80 153']:
  s+=path(dd,'none',.5,'stroke="#82837b" stroke-width="1.6"')
 shield='M29 59Q31 54 40 55L103 55L104 89L93 140L43 141L30 101Z'
 s+=path(shield,'url(#silver)',1,'stroke="#232c2d" stroke-width="2.1" stroke-linejoin="round"')
 s+=path('M42 60L94 59L94 94L83 136L50 136L39 101Z','#292f30')
 # Original emblem is a red slash-mark / letter-like shard inside a saw-toothed silver shield.
 s+=poly([(44,60),(50,60),(46,72)],'#94968f')+poly([(54,60),(60,60),(56,72)],'#a4a499')+poly([(66,60),(72,60),(68,72)],'#a4a499')+poly([(78,60),(84,60),(81,73)],'#95998f')
 s+=poly([(51,127),(56,136),(60,127),(64,136),(69,126),(73,136),(79,127),(83,137)],'#9c9f94')
 s+=path('M60 67L82 64L68 88L81 84L54 126L59 104L47 110L68 79L54 85Z','#552b29',.82)
 s+=path('M73 73L60 92L72 88L57 116','none',.55,'stroke="#84332c" stroke-width="2.1"')
 # Silver horizontal crossbar, intentionally uneven spray-painted not a UI glyph.
 s+=path('M34 85L62 85L60 90L37 90L31 96L31 108L51 108L51 113L28 113L24 109L24 96Z','url(#silver)',1,'stroke="#252e30" stroke-width="1.35" stroke-linejoin="round"')
 s+=path('M83 85L112 85Q121 84 120 88Q119 92 112 92L97 92L91 111L84 108L91 90L81 90Z','url(#silver)',1,'stroke="#252e30" stroke-width="1.2"')
 # Paint abrasions and angled chalk hatching remain inside the shield, with no baked original RGB.
 s+='<g clip-path="url(#shieldpaint)">';rr=np.random.default_rng(n)
 for i in range(100):
  x=rr.uniform(26,105);y=rr.uniform(55,141);ln=rr.uniform(2,13)
  s+=line(x,y,x-ln*.55,y+ln,rr.choice(['#afb0a4','#1c272b','#5e6766','#b3b3aa']),rr.uniform(.2,.65),rr.uniform(.08,.32))
 s+='</g>'+rect(0,0,w,h,'url(#paintgrain)',.9)
 return finish(n,w,h,s)

def run():
 R.joinpath('parts').mkdir(exist_ok=True);R.joinpath('previews').mkdir(exist_ok=True)
 funcs=[vent,stain,lambda:circuit_hole(1414),lambda:circuit_hole(1415),plaster_wall,ladder,graffiti]
 out=[]
 for fn in funcs:
  p=fn();n=int(p.stem.split('-')[1]);im=Image.open(R/f'reference/{n}.png')
  out.append({'bitmapId':n,'originalSize':list(im.size),'svg':str(p.relative_to(R)),'preview4x':f'previews/street-{n}-4x.png','originalAlpha':'exact alpha-only editable vector mask; no original RGB reused','source':'source/street_materials.py','sha256':hashlib.sha256(p.read_bytes()).hexdigest()});print('WROTE',p,flush=True)
 R.joinpath('qa/street-materials-manifest.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
if __name__=='__main__':run()
