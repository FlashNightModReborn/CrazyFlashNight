"""R2 structure-first environment reconstruction, in original bitmap1580 coordinates.
Original reference is sampled only to guide broad material values; output is editable SVG geometry.
"""
from pathlib import Path
from PIL import Image,ImageFilter
import random,math
from svg_native import write_part
R=Path(__file__).resolve().parents[1]; VB=[0,0,800,452]
def P(d,f,st=None,w=.6,op=1):return f'<path d="{d}" fill="{f}" opacity="{op}"'+(f' stroke="{st}" stroke-width="{w}" stroke-linejoin="round"' if st else '')+'/>'
def E(x,y,rx,ry,f,op=1):return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{f}" opacity="{op}"/>'
def G(id,stops,x1=0,y1=0,x2=0,y2=1):return f'<linearGradient id="{id}" x1="{x1*100}%" y1="{y1*100}%" x2="{x2*100}%" y2="{y2*100}%">'+''.join(f'<stop offset="{o}" stop-color="{c}"/>' for o,c in stops)+'</linearGradient>'
def save(n,s):write_part(R/f'parts/{n}.svg',VB,s)
def wreck():
 from wreck_contours import make
 save('02-wreck-pile',make())

def ground():
 im=Image.open(R/'reference/original-1580.png').convert('RGB');smooth=im.filter(ImageFilter.GaussianBlur(9));detail=im.filter(ImageFilter.GaussianBlur(2));rng=random.Random(20261580)
 def rgb(v):return '#'+''.join(f'{min(255,max(0,int(x))):02x}' for x in v)
 def sample(x,y):return smooth.getpixel((min(799,max(0,int(x))),min(451,max(0,int(y)))))
 defs='<defs>'+G('earth',[(0,'#10150e'),(.28,'#3b3222'),(1,'#504435')])+G('metal',[(0,'#353831'),(.5,'#2d322b'),(1,'#393e34')])+'</defs>'
 sky=defs+P('M0 0H800V452H0Z','#030604')
 for _ in range(130):
  x=rng.uniform(292,800);y=rng.uniform(0,150);sky+=E(round(x,2),round(y,2),rng.choice([.3,.4,.65]),rng.choice([.3,.4,.65]),rng.choice(['#74705a','#ad9d70','#4a4e3b']),rng.uniform(.25,.7))
 sky+=P('M0 162 L285 161 L360 177 L508 166 L645 160 L800 155 V452H0Z','url(#earth)')
 # Multi-scale compressed earth contours, sampled broad values but independently authored geometry.
 for _ in range(170):
  x=rng.uniform(290,800);y=rng.uniform(170,452);w=rng.uniform(6,25);h=rng.uniform(1,4);v=sample(x,y);v=[min(v[0],70)*.72,min(v[1],61)*.72,min(v[2],43)*.72]
  sky+=P(f'M{x:.1f} {y:.1f} q{w*.25:.1f} {-h:.1f} {w*.55:.1f} {-h*.3:.1f} l{w*.45:.1f} {h*.4:.1f} l{-w*.15:.1f} {h:.1f} q{-w*.5:.1f} {-h*.5:.1f} {-w*.85:.1f} {h*.2:.1f}Z',rgb(v),None,op=.1)
 # Granular soil is shaded tiny facets (light top / dark bottom), with depth-dependent scale.
 for _ in range(14000):
  y=rng.uniform(172,452);x=rng.uniform(250,800)
  boundary=292+(y-168)*.95+16*math.sin(y*.08)
  if x<boundary-45 and rng.random()>.07:continue
  k=.55+(y-172)/280*.9;w=rng.uniform(.6,2.8)*k;h=rng.uniform(.25,.9)*k;v=sample(x,y);v=[min(v[0],78),min(v[1],68),min(v[2],48)];gain=rng.uniform(.7,1.4)
  sky+=P(f'M{x:.1f} {y:.1f} l{w*.4:.1f} {-h:.1f} l{w*.6:.1f} {h*.25:.1f} l{-w*.2:.1f} {h*.8:.1f}Z',rgb([c*gain for c in v]),None,op=.65)
  if w>2:sky+=P(f'M{x:.1f} {y+.2:.1f} l{w*.8:.1f} {h*.2:.1f}','none','#12180e',.4,.65)
 save('01-night-soil',sky)
 # Metal substrate fades irregularly where islands of dirt cover it. Native fixed mask.
 s=defs+'<defs><linearGradient id="mix" gradientUnits="userSpaceOnUse" x1="255" y1="164" x2="335" y2="120"><stop stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient><mask id="groundmix"><path d="M0 164H800V452H0Z" fill="url(#mix)"/></mask><radialGradient id="wear"><stop stop-color="#a4a68a" stop-opacity=".16"/><stop offset="1" stop-color="#a4a68a" stop-opacity="0"/></radialGradient></defs><g mask="url(#groundmix)">'+P('M0 164H800V452H0Z','url(#metal)')
 for _ in range(80):
  x=rng.uniform(0,580);y=rng.uniform(166,452);s+=E(round(x,1),round(y,1),rng.uniform(10,40),rng.uniform(3,12),'url(#wear)')
 s+='<defs><radialGradient id="oil"><stop stop-color="#0b140d" stop-opacity=".2"/><stop offset="1" stop-color="#0b140d" stop-opacity="0"/></radialGradient></defs>'
 for _ in range(30):
  x=rng.uniform(0,470);y=rng.uniform(168,450);s+=E(round(x,1),round(y,1),rng.uniform(12,32),rng.uniform(4,11),'url(#oil)')
 # Each five-ridge group has extruded dark side, narrow upper face and worn crest.
 for row,y in enumerate(range(166,456,14)):
  for col,x in enumerate(range(-28,675,29)):
   x=x+(row%2)*14.5+rng.uniform(-2,2);y0=y+rng.uniform(-1.1,1.1);near=.65+(y-164)/288*.55
   v=sample(x,y); dirt=max(0,min(.8,(v[0]-v[1]-3)/20)) if x>100 else 0
   dx,dy=(29,1.7) if (row+col)%2 else (22,12)
   for k in range(5):
    xx=x+k*3.1 if dy>5 else x;yy=y0+k*2.25 if dy<5 else y0-k*1.3
    if rng.random()<.06+dirt*.45:continue
    width=.36*near;endx=xx+dx+rng.uniform(-8,4);endy=yy+dy
    dv=detail.getpixel((min(799,max(0,int(xx))),min(451,max(0,int(yy))))); lum=sum(dv)/3
    crest=rgb([min(164,lum+75),min(164,lum+75),min(157,lum+67)]);face=rgb([lum*.95,lum,lum*.86]);side=rgb([lum*.53,lum*.57,lum*.49])
    s+='<g opacity="'+str(round(1-dirt*.65,3))+'">'
    s+=P(f'M{xx:.1f} {yy:.1f} L{endx:.1f} {endy:.1f} l0 {width+.35:.1f} L{xx:.1f} {yy+width+.35:.1f}Z',side)
    s+=P(f'M{xx:.1f} {yy:.1f} L{endx:.1f} {endy:.1f} l-1.7 {width:.1f} L{xx+1:.1f} {yy+width:.1f}Z',face)
    s+=P(f'M{xx+1:.1f} {yy:.1f} L{endx-1:.1f} {endy:.1f}','none',crest,.62*near,rng.uniform(.7,.95))
    s+='</g>'
 for _ in range(95):
  x=rng.uniform(10,570);y=rng.uniform(168,450);w=rng.uniform(8,36);h=rng.uniform(1,4)
  s+=P(f'M{x:.1f} {y:.1f} q{w*.3:.1f} {-h:.1f} {w:.1f} 0 q{-w*.4:.1f} {h*.7:.1f} {-w:.1f} 0Z',rng.choice(['#111b13','#a8a88d','#6a674d']),None,op=rng.uniform(.06,.15))
 # Rust/wear scratches respect the plate direction, never a perfectly repeated print.
 for _ in range(240):
  x=rng.uniform(0,590);y=rng.uniform(166,452)
  s+=P(f'M{x:.1f} {y:.1f} l{rng.uniform(4,20):.1f} {rng.uniform(-1,2):.1f}','none',rng.choice(['#161e14','#b0ac8c','#756447']),rng.uniform(.25,.55),.35)
 s+='</g>'
 # Dirt tongues invade the steel, with distributed small grains along irregular margins.
 for _ in range(160):
  y=rng.uniform(175,452);x=265+(y-164)*.9+rng.uniform(-42,55)+12*math.sin(y*.13);w=rng.uniform(5,20);h=rng.uniform(.4,1.4)
  s+=P(f'M{x:.1f} {y:.1f} l{w*.3:.1f} {-h:.1f} l{w*.4:.1f} {h*.7:.1f} l{w*.3:.1f} {-h*.3:.1f} l-2 {h*1.4:.1f} l{-w*.8:.1f} {h*.2:.1f}Z',rng.choice(['#383321','#49402b','#594b30']),None,op=rng.uniform(.3,.65))
 for _ in range(1100):
  y=rng.uniform(175,452);x=260+(y-164)*.9+rng.uniform(-36,70)
  s+=E(round(x,1),round(y,1),rng.uniform(.3,1.5),rng.uniform(.2,.6),rng.choice(['#6b5936','#211f13','#51452d']),.65)
 save('03-metal-floor',s)

def wall():
 rng=random.Random(414);s='<defs>'+G('wall',[(0,'#111d16'),(.2,'#28352a'),(.6,'#28382a'),(1,'#16271a')])+G('rim',[(0,'#63705b'),(.5,'#233625'),(1,'#0b160e')])+'<radialGradient id="stain"><stop stop-color="#080f0a" stop-opacity=".52"/><stop offset="1" stop-color="#080f0a" stop-opacity="0"/></radialGradient></defs>'
 s+=P('M0 0H292V165H0Z','url(#wall)')
 for x,y,rx,ry in [(15,140,41,28),(119,50,70,26),(258,93,33,80),(208,142,64,24),(69,132,40,21)]:s+=E(x,y,rx,ry,'url(#stain)')
 for x in [25,91,157,224,291]:s+=P(f'M{x} 0V148','none','#0e1e12',.6,.6)+P(f'M{x+1} 0V148','none','#54604a',.35,.45)
 for y in [30,98]:s+=P(f'M0 {y}H292','none','#101f14',.65,.8)+P(f'M0 {y+.8}H292','none','#5b6950',.35,.4)
 # Large patches follow panel surfaces; scratches are secondary, not the entire aging.
 for _ in range(70):
  x=rng.uniform(0,290);y=rng.uniform(5,147);w=rng.uniform(2,16);h=rng.uniform(.7,4)
  s+=P(f'M{x:.1f} {y:.1f} q{w*.3:.1f} {-h*.3:.1f} {w*.6:.1f} {-h*.2:.1f} l{w*.4:.1f} {h*.4:.1f} q{-w*.4:.1f} {h*.7:.1f} {-w:.1f} {h*.2:.1f}Z',rng.choice(['#65705a','#0c1c10','#435239']),None,op=.13)
 for _ in range(110):
  x=rng.uniform(0,292);y=rng.uniform(0,145);s+=P(f'M{x:.1f} {y:.1f} l.2 {rng.uniform(2,9):.1f}','none','#546349',.35,.17)
 s+='<defs><clipPath id="base"><path d="M0 148H292V165H0Z"/></clipPath></defs><g clip-path="url(#base)">'+P('M0 148H292V165H0Z','#101c12')
 for x in range(-8,295,27):s+=P(f'M{x} 164 l7 -15h14l-7 15Z','#79752d','#233122',.5)
 for _ in range(80):
  x=rng.uniform(0,292);y=rng.uniform(149,164);s+=P(f'M{x:.1f} {y:.1f} l{rng.uniform(1,3):.1f} -.3 l.4 .7 l-2 .4Z','#283522',None,op=.7)
 s+='</g>'
 # Original warning locations preserved, lettering is legible but aged.
 s+=P('M76 76H113V100H76Z','#7b8567','#152416',.8)+P('M79 79H110V87H79Z','#7d5524')
 s+='<text x="94.5" y="85" text-anchor="middle" font-family="DejaVu Sans" font-weight="bold" font-size="5.8" fill="#c3a745">DANGER</text>'
 s+=P('M80 91H108 M82 94H106 M84 97H103','none','#33482f',1)
 s+=P('M140 72L157 99H124Z','#98963b','#263d22',1)+E(140,89,2.3,2.3,'#22351c')
 for a in [0,120,240]:s+=f'<g transform="rotate({a} 140 89)">'+P('M137 84L135 78Q140 76 145 78L143 84Z','#22351c')+'</g>'
 # Torn wall aperture has thickness, broken perimeter strips and recessed broken PCB, not a hanging sign.
 s+=P('M203 0 Q208 3 214 3 L220 1 Q230 4 239 1 L252 2 L267 0 Q264 7 269 13 L266 20 Q270 25 260 29 L253 33 L244 31 Q237 36 228 32 L218 32 L214 25 Q207 24 209 16 L207 10Z','url(#rim)','#09130c',1)
 s+=P('M212 1 Q220 7 230 5 L239 3 L249 5 L261 2 L261 10 Q266 15 260 22 L252 28 L242 26 Q233 32 222 27 L217 22 L214 18 L216 10Z','#030906')
 s+='<g transform="translate(240 16) scale(.82) translate(-240 -16)">'
 s+=P('M220 4 L232 7 L247 4 L259 8 L257 23 L249 27 L238 23 L227 27 L220 22Z','#183622','#455f37',.4)
 for _ in range(65):
  x=rng.uniform(222,254);y=rng.uniform(6,24);s+=P(f'M{x:.1f} {y:.1f} h{rng.uniform(1,5):.1f} v{rng.uniform(-3,3):.1f}','none','#718263',.4,.65)
 for x,y in [(224,11),(239,7),(247,18)]:s+=P(f'M{x} {y}h5v4h-5Z','#030b06','#617354',.4)
 s+='</g>'
 s+=P('M216 5 L228 7 L235 5 L248 6 L259 3 L259 7 L247 10 L235 8 L228 11 L220 8Z','#050d07')
 s+=P('M214 13 L220 18 L223 26 L219 29 L215 23Z','#0b160d')
 s+=P('M210 22 L213 34 L211 45 M221 30 L224 42 L222 58 M238 32 L239 46 L237 54 M259 28 L257 45','none','#0a140c',2.2)
 s+=P('M207 8 L211 14 L207 20 M264 10 L270 13 L267 18 M216 27 L217 36 M250 31 L254 35','none','#647458',.8)
 for x in [211,222,239,254]:s+=P(f'M{x} 30q-2 14 0 24','none','#0a180d',4,.16)
 save('04-wall',s)
def apply():wreck();ground();wall()
