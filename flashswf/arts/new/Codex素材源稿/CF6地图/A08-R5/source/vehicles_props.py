"""Stage 8 car, access door, trigger pedestals, and biohazard drum.

New native SVG drawing based on observed original 1823/1420/1828/1833 artwork.
R3 car surfaces are newly authored paths with native project M134 barrel paths.
Car outline is now smooth editable SVG rather than the low-resolution alpha.
Other prop sources retain original alpha for registration and cut-up boundaries.
Generated deterministic micrograin is independent of the original RGB image.
The build reads no network and does not touch production files. SVGs are complete.
"""
from pathlib import Path
import base64, io, json, hashlib, math
import numpy as np
from PIL import Image, ImageDraw
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from svg_native import write_part, render, inner
R=Path(__file__).resolve().parents[1]
REF=R/'reference'
IDS=(1823,1420,1828,1833)
WH={1823:(411,144),1420:(144,176),1828:(55,44),1833:(52,89)}
SEED=1823142018281833

def path(d,fill,stroke=None,width=.5,extra=''):
 return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{width}"' if stroke else '')+f' {extra}/>'
def line(d,c='#99a0a6',w=.4,o=1):
 return path(d,'none',c,w,f'opacity="{o}" stroke-linecap="round" stroke-linejoin="round"')
def rect(x,y,w,h,c,stroke=None,sw=.5,rx=0,extra=''):
 return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'
def ell(x,y,rx,ry,c,stroke=None,sw=.5,extra=''):
 return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'
def circle(x,y,r,c,stroke=None,sw=.5,extra=''):return ell(x,y,r,r,c,stroke,sw,extra)
def bolt(x,y,r=.55):
 return circle(x+.15,y+.2,r+.17,'#0b1013')+circle(x,y,r,'#60696f')+line(f'M{x-r*.4:.2f} {y-r*.35:.2f}l{r*.7:.2f} -.1','#b4b9ba',.2,.7)
def lg(id,stops,x2='0',y2='1',x1='0',y1='0'):
 return f'<linearGradient id="{id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</linearGradient>'
def rg(id,stops,cx='.36',cy='.28',r='.74'):
 return f'<radialGradient id="{id}" cx="{cx}" cy="{cy}" r="{r}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</radialGradient>'
def label(text,x,y,w,h,c='#d4d7d6',font='DejaVuSans-Bold.ttf'):
 f=TTFont(REF/('vehicles-props-'+font));gs=f.getGlyphSet();cm=f.getBestCmap();n=0;els=[]
 for ch in text:
  g=gs[cm[ord(ch)]];pen=SVGPathPen(gs);g.draw(pen);els.append(f'<path transform="translate({n} 0)" d="{pen.getCommands()}"/>');n+=g.width
 return f'<g fill="{c}" transform="translate({x} {y+h}) scale({w/n} {-h/1493})">'+''.join(els)+'</g>'
def png_data(im):
 b=io.BytesIO();im.save(b,format='PNG');return base64.b64encode(b.getvalue()).decode()
def original_mask(i):
 im=Image.open(REF/f'{i}.png').convert('RGBA');a=im.getchannel('A');white=Image.new('RGBA',im.size,'white');white.putalpha(a);w,h=im.size
 return f'<mask id="source-alpha-{i}" maskUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{h}" style="mask-type:alpha"><image x="0" y="0" width="{w}" height="{h}" href="data:image/png;base64,{png_data(white)}"/></mask>'
def grain(w,h,seed,strength=14):
 rng=np.random.default_rng(seed);ww,hh=w*3,h*3
 a=rng.normal(0,1,(hh,ww));b=np.array(Image.fromarray(rng.integers(0,255,(max(2,h//4),max(2,w//4)),dtype=np.uint8)).resize((ww,hh),Image.Resampling.BICUBIC))/255-.5
 rgb=np.where((a+b)[...,None]>0,np.array([192,202,208]),np.array([3,5,8]));alpha=np.minimum(np.abs(a)*strength+np.abs(b)*strength,35).astype('uint8');im=Image.fromarray(np.dstack((np.broadcast_to(rgb,(hh,ww,3)),alpha)).astype('uint8'))
 return f'<image width="{w}" height="{h}" href="data:image/png;base64,{png_data(im)}"/>'
def coated(i,body,base='#101317'):
 w,h=WH[i];return '<defs>'+original_mask(i)+'</defs>'+f'<g mask="url(#source-alpha-{i})">'+rect(0,0,w,h,base)+body+'</g>'

def wheel(cx,cy,rx=29.6,ry=29.8):
 s=f'<g transform="translate({cx} {cy}) scale({rx/30} {ry/30})">'
 s+=circle(0,0,30,'#0a0c0f','#06090b',.6)+circle(0,0,29,'url(#tire)','#2f3336',.5)+circle(0,0,26.2,'#090e13','#7c858c',.55)+circle(0,0,24.6,'#111923','#151b20',1.15)
 for k in range(44):
  a=k*360/44;s+=f'<g transform="rotate({a})">'+line('M-1.1 -29.1l1.8 .3l.6 1.5','#62666a',.32,.4)+line('M-.7 -27.8l1.2 .2','#060a0e',.4,.8)+'</g>'
 # Cast multi-spoke alloys, with black spoke apertures and subtle rim bolts.
 s+=circle(0,0,23.3,'url(#rim)','#899299',.35)+circle(0,0,21.9,'#0b1219','#05090d',.65)
 # Deep inset trapezoid windows preserve the original chunky ten-sector rim.
 # The webs stay dark; they are not a fan of bright turbine blades.
 s+=circle(0,0,21.8,'#34434e','#17212b',.5)
 for k in range(10):
  a=k*36;s+=f'<g transform="rotate({a})">'
  s+=path('M-3.0 -7.1L-8.0 -17.8L-7.4 -20.9L2.5 -22.2L3.6 -19.7L1.5 -9.0Z','#02070c','#0a1118',.8)
  s+=path('M-5.8 -17.5L-3.5 -11.2L.1 -10.2L1.1 -19.6L-4.7 -19.0Z','#253540','#3e4b56',.4)
  if k in [0,1,6,8]:
   s+=path('M-5.1 -17.2L-3.9 -14.0L-.0 -13.5L.7 -17.5L-1.3 -18.5Z','#647681',extra='opacity=".45"')
  s+=line('M-8.3 -19.4L-3.5 -8.1M3.2 -20.2L1.6 -9.3','#8a969f',.35,.40)
  s+=line('M-6.6 -22L2.0 -23.1','#a0a9af',.4,.5)
  if k in [2,7]:
   s+=path('M-4.7 -18.1h1.1v5.2h-1.1Z','#a3adb3')+rect(-.9,-18.4,.7,5,'#738591')
  s+=circle(0,-24,.35,'#75838d')+'</g>'
 s+=circle(0,0,7.2,'#080c10','#79838a',.45)+circle(0,0,5.2,'#111b24','#101821',.6)+circle(0,0,3.0,'#18232d','#3c4a56',.4)+circle(-.6,-.8,1.2,'#52606c')
 for k in range(5):
  a=k*math.tau/5;s+=bolt(math.sin(a)*4.9,math.cos(a)*4.9,.55)
 s+=line('M-23.3 7.4Q-18 23 0 24.4Q18 23 23.6 5.7','#777f84',.35,.65)+'</g>'
 return s

def rear_aero_r3():
 """Rear twin-channel spoiler: load-bearing blades, webs and inset throats.

 Planes follow the original 1823 quarter-panel perspective. These are solid
 painted surfaces; the narrow black paths are only the recessed air channels.
 """
 s='<g id="rear-aero-r3">'
 # Dark side window stays behind the independent aero assembly.
 s+=path('M41 20L67 18L64 39L67 51L48 52L35 49Z','url(#glass)','#060c12',.65)
 s+=path('M42 24L62 21L59 36Q50 34 39 38Z','#8b9da9',extra='opacity=".10"')
 # Upper tunnel under the roof shoulder: broad recess, solid far end-wall.
 s+=path('M71 20L101 15L140 14L156 23L149 25L94 24L84 27L82 34L74 35L72 28Z','#03080c','#131b22',.55)
 s+=path('M101 15L140 14L156 23L149 24L138 18L102 18L75 22L71 21Z','url(#aeroUpper)','#19232b',.35)
 s+=line('M73 20L101 16L140 15L153 23','#adb7be',.55,.48)
 # Thick rear vertical web, with a real side wall instead of a loose triangle.
 s+=path('M72 22L78 22L76 35L72 38L69 34Z','url(#aeroWeb)','#10171d',.55)
 s+=path('M78 22L85 24L83 35L76 35Z','#121a21','#090f15',.45)
 s+=line('M73 23L71 34','#83919b',.65,.5)
 # Upper solid blade: the small lower lip exposes its thickness over the slot.
 s+=path('M85 23L106 24L151 25L155 27L96 30L92 34L84 35Z','url(#aeroUpper)','#1c272f',.55)
 s+=path('M96 30L154 27L149 29L97 32L92 35L84 36L84 34L92 33Z','#202a32','#0d151c',.35)
 s+=line('M86 24L108 25L149 26','#a6b1b9',.65,.54)
 s+=line('M96 30L151 27.5','#9ca7ae',.4,.39)
 # The slit sits beneath the top blade, not inside a hollow decorative triangle.
 s+=path('M97 32L149 29L140 32L96 35L92 35Z','#03090e')
 # Broad lower airfoil surface, visibly filled and anchored into the rear body.
 s+=path('M69 34L88 36L96 35L150 30L115 54L72 53L67 47L66 41Z','url(#aeroLower)','#17212a',.55)
 s+=path('M69 36L89 38L134 34L113 50L75 50L70 46Z','#7d8b95',extra='opacity=".10" filter="url(#softReflect)"')
 s+=line('M70 35L89 36.5L147 31','#a7b1b7',.55,.41)
 # Foil edge and dark inner channel converge toward the car's forward shoulder.
 s+=path('M115 54L150 30L156 28L143 42L125 53L120 55L72 55L72 53Z','#080f16','#080e14',.45)
 s+=path('M121 52L143 35L151 31L140 43L127 52Z','#202c35')
 s+=path('M148 32L158 28L152 35L143 42L138 43Z','url(#aeroWeb)','#18232c',.4)
 s+=line('M72 53L115 54L150 30','#a9b2b8',.7,.69)
 s+=line('M120 55L137 47','#52626d',.5,.48)
 s+='</g>'
 return s

def windshield_rib_r3(far=False):
 """Solid cast stiffener curving down the glazed/body shoulder, not a ring."""
 if far:
  # Foreshortened far-side edge. The flange attaches to the far weapon cradle.
  return '<g id="windscreen-rib-far-r3">'+path('M313.8 .6Q317 -.4 318.2 3.4Q319.8 9.4 318.5 18.2L314.8 18.5Q315.6 12.1 314.8 7.0Q314.1 3.2 313.8 .6Z','url(#ribMetal)','#071019',.55)+path('M314.4 1.5Q316.5 5.9 316 15.4L315.2 17.6L314 15.3Q315 7.8 313.5 3.0Z','#586875',extra='opacity=".6"')+line('M315.2 1.5Q317.8 7.4 316.7 16.6','#a3b0b8',.6,.63)+path('M296 16.6L315.6 10.1L317 16.8L316.2 20.8L297.5 19.2Z','#111c25','#071019',.55)+line('M297 17L315.3 11.4','#778792',.55,.59)+'</g>'
 s='<g id="windscreen-rib-near-r3">'
 # One continuous solid leaf with a narrow recessed face and a raised front edge.
 s+=path('M312.2 30.6Q315.3 28.8 317.7 33.3Q321 40.2 319.3 48.6L317.6 57.7L313.1 58.3Q314.3 49.1 313.9 42.8Q313.5 36.1 310.5 33.1Z','url(#ribMetal)','#08131d',.65)
 s+=path('M313.2 32.9Q316.1 34.5 317.1 40.8Q318.2 48.7 315.8 55.8L314.4 55.5Q315.6 46.4 314.7 40.0Z','#253a49')
 s+=line('M313.1 31.5Q316.7 31.4 318.6 40.9Q319.4 47.8 316.9 56.4','#aab7c0',.8,.71)
 s+=line('M311.6 33.1Q314.4 39.7 313.8 47.1','#0c1b26',.7,.9)
 # Broad saddle/gusset connects the rib foot to the near cradle, below glass.
 s+=path('M289.3 53L312.9 45.6L315.7 54.5L313.9 59.3L290.8 57.6L284.5 55.8Z','#17242e','#07111a',.6)
 s+=path('M289.6 53.2L312.5 46.8L312.8 49.5L293.2 55.3Z','#607380')
 s+=path('M297.6 54.2L312.7 50.5L313.5 55.9L302.1 55.8Z','#09131c')
 s+=line('M289.6 53.2L312.2 47','#abb8c0',.55,.61)
 s+=bolt(312.1,54.9,.55)
 return s+'</g>'

def project_m134_r3(far=False):
 """Project M134 core, adapted to a vehicle mount in two perspective poses.

 Native six-barrel artwork is a local XFL-derived editable SVG. Receiver and
 drive motor are newly drawn closed surfaces from that same project model;
 hand grip/carry frame are omitted because the car has its own saddle/brace.
 The two instances use distinct flattening/shear, mount and occlusion geometry.
 """
 pfx='m134far' if far else 'm134near'
 mat='.19 .003 -.013 .17 312 7.1' if far else '.25 .004 -.018 .22 297 47.8'
 # Separate cast cradle grounds each weapon in the vehicle shoulder.
 if far:
  s=path('M304 21.2L333.8 20.7L337 24.6L330 27L305 25.2Z','#09131b','#02070b',.5)
  s+=line('M305.3 22.2L333 22','#6a7c89',.6,.67)
 else:
  s=path('M278.5 62.9L321.6 63L328.5 68.5L321.4 74.4L282 71.4L274.5 66.6Z','#09121b','#02070a',.7)
  s+=path('M278.7 63.2L321.5 63.2L324.8 66.3L281 67.0Z','#3b4c5a','#11212d',.55)
  s+=line('M280 63.8L320.3 64','#aab6be',.6,.68)
  for x,y in [(282,66),(320,67),(285,70)]:s+=bolt(x,y,.55)
 s+=f'<g id="{pfx}-project-core" transform="matrix({mat})">'
 # Low-mounted drive motor and its rear clamp, source M134's distinctive belly.
 s+=path('M-70 72L35 71Q51 73 53 87Q52 102 39 105L-69 103Q-81 99 -81 88Q-81 76 -70 72Z','url(#gun)','#03090d',2.1)
 s+=ell(-69,87.5,9,15.4,'#111b23','#060c11',1.6)+ell(40,87.5,10.8,17,'url(#m134Face)','#061019',1.8)
 s+=path('M-49 71Q-55 88 -48 103L-39 105Q-46 88 -39 72Z','#070e14','#15212a',1.5)
 s+=line('M-66 76H26M-67 95H26','#a1adb5',1.1,.58)
 s+=path('M-29 99L-26 109L-18 109L-16 101Z','#0c151d')
 # Solid cylindrical receiver, explicit front/rear end caps and curved feed cover.
 s+=path('M-45 23Q-58 26 -59 47Q-58 69 -45 72L80 75Q98 73 101 49Q99 26 86 22Z','url(#gun)','#03090e',2.1)
 s+=ell(-45,47.5,9,24.1,'url(#m134Face)','#060b10',1.7)
 s+=path('M-38 24L40 23L29 30L-40 31Z','#677580',extra='opacity=".72"')
 s+=line('M-33 27H30M-36 65L24 67','#bcc4c9',1.2,.61)
 s+=path('M1 24L33 24Q14 42 -12 67L-26 70L-35 59Q-13 37 1 24Z','url(#m134Feed)','#071018',2)
 s+=path('M10 28L24 28Q8 42 -15 64L-24 64Q-4 40 10 28Z','#8e9da7',extra='opacity=".45"')
 s+=line('M4 28Q-10 41 -29 60','#c2c9cd',1.2,.65)
 s+=path('M49 22L59 21Q50 49 60 75L48 75Q38 49 49 22Z','#0a131b','#192832',1.5)
 # Compact top housing; original portable carry frame is not transplanted.
 s+=path('M-37 14H38L53 19L49 26L-41 26Z','url(#gun)','#050d13',2)
 s+=rect(-30,15.5,58,4.3,'#76848d',extra='opacity=".66"')
 s+=rect(8,31,20,7,'url(#m134Face)','#050c12',1.6,2)
 s+=ell(79,48.5,15,27,'url(#m134Face)','#040b11',2)
 s+=ell(82,48.5,10.5,22.3,'#0a151f','#687a87',1.2)
 # Editable project barrel cluster. Native translate matches the parent XFL.
 s+='<g transform="translate(98.7 25.7)">'+inner(REF/'m134-native/render/m134-native-barrel-only-phase3.svg',pfx)+'</g>'
 # Retaining plate overlaps the rear barrel roots to make a physical joint.
 s+=path('M81 22Q92 24 98 28L98 76Q90 81 81 77Q90 64 91 48Q91 33 81 22Z','url(#m134Face)','#030c14',1.4)
 s+=line('M91 30Q97 49 91 71','#b0bdc6',1.1,.7)
 for x,y in [(-35,34),(-35,61),(35,35),(35,65),(77,30),(77,68),(43,87)]:s+=bolt(x,y,1.55)
 s+='</g>'
 if far:
  # The far shoulder covers the underside of the cradle, unlike the near mount.
  s+=path('M303.5 24.9L316.8 25.4L324.2 27L315.2 26.6Z','#1a2b38')
 return s

def coated_car_r3(body,hardware):
 """Smooth native vector vehicle outline; independent M134 hardware alpha.

 R3 edge-cleanup removes the low-resolution source alpha from bitmap1823.
 Registration/canvas are unchanged, but the body and tires now have continuous
 editable curves. The original body has no transparent interior holes: its
 only enclosed alpha holes were in the discarded far-weapon triangular brace.
 """
 hull='M11.6 70.5Q12.6 56.5 16.6 43L32.5 21Q38.5 14 49 12Q98 5.6 162 6L173 2.3Q191 .2 214 .4L240 1.2Q260 3.5 285 11.1Q301 17 315 23Q349 30 377 45Q393.5 55.5 398 67.2Q405 85 399 100Q397 110.5 386 115L340 120L113 120L49 111L27 100Q11.8 90 11.6 70.5Z'
 outline=path(hull,'white')+ell(80.3,102.1,29.75,30.45,'white')+ell(313.7,102.1,29.65,30.35,'white')
 return '<g id="far-gun-behind-body-r5" transform="translate(0 4)">'+gun_cradle_brace_r5(True)+project_m134_r3(True)+'</g><defs><clipPath id="car-body-envelope-r3">'+outline+'</clipPath></defs><g clip-path="url(#car-body-envelope-r3)">'+rect(0,0,411,144,'#080d12')+body+'</g>'+hardware

def cockpit_r5():
 """Opaque interior plus separately editable translucent glass; no background leak."""
 front='M252 8Q287 16 322 30Q327 34 325 40L319 60Q284 47 251 32Q256 21 252 8Z'
 side='M191 14Q216 18 245 17Q242 29 233 33L192 35Z'
 shapes=path(front,'white')+path(side,'white')
 out='<defs><clipPath id="cockpit-apertures-r5">'+shapes+'</clipPath></defs>'
 out+='<g id="cockpit-interior-r5" clip-path="url(#cockpit-apertures-r5)">'
 out+=rect(184,4,145,60,'#101b22')
 # Far door and rear cockpit wall establish enclosed cabin depth.
 out+=path('M191 15L244 16L277 19L303 31L297 34L243 26L192 28Z','#24323b')
 out+=line('M245 11L245 28L292 36','#4b5c67',.5,.38)
 # Both seat backs have curved upholstery, shoulder wings and a recessed headrest.
 out+=path('M257 19Q253 9 259 8L267 10Q272 12 272 20L276 28L271 33L256 28Z','#091016','#465761',.65)
 out+=path('M259 12Q263 10 267 14L269 21L260 19Z','#455963')
 out+=path('M260 21L269 23L272 30L262 28Z','#283b46')
 out+=path('M201 20Q202 12 210 13L219 15Q223 17 223 23L228 31L226 39L201 38L198 29Z','#0b141b','#3a4b56',.5)
 out+=path('M205 16Q211 15 217 18L218 23L204 22Z','#53636c')
 out+=path('M204 25L218 26L223 34L202 34Z','#344752')
 out+=line('M205 26L205 32M217 27L220 33','#829099',.35,.65)
 # Dashboard follows windshield's lower curved edge; steering wheel is behind glass.
 out+=path('M252 30Q284 39 316 49L325 55L319 63L248 35Z','#0a151d','#435965',.7)
 out+=path('M256 32Q285 41 315 51L319 55L287 45L255 35Z','#4a606b')
 out+=ell(284,39,7,3.2,'none','#090f15',1.7,extra='transform="rotate(24 284 39)"')
 out+=line('M284 39L288 45M279 38L287 40','#75838a',.65,.7)
 out+=path('M300 45L307 48L309 50L301 47Z','#253c49')
 out+=line('M302 46L306 48','#70adab',.45,.8)
 out+='</g>'
 # Independent tinted glass. The opaque cabin remains underneath the transparency.
 out+='<g id="cockpit-glass-r5" clip-path="url(#cockpit-apertures-r5)">'
 out+=path(front,'#81a5b6',extra='fill-opacity=".22"')+path(side,'#709aa9',extra='fill-opacity=".17"')
 out+=path('M251 9Q283 17 322 31L325 38Q285 27 252 20Z','#d8e5e8',extra='fill-opacity=".22"')
 out+=path('M192 15Q213 18 242 18L238 22Q216 21 193 21Z','#d3e1e6',extra='fill-opacity=".16"')
 out+=line('M254 10Q286 19 322 32','#e3edf0',.65,.58)
 out+='</g>'
 # Rubber seal / narrow body flange is outside glass, not across its center.
 out+='<g id="cockpit-frame-r5">'+path(front,'none','#14232d',1.2)+path(side,'none','#101d26',1.1)
 out+=line('M250 7Q256 19 249 32M190 14L191 35','#96a6ae',1,.7)
 out+=line('M251 33Q286 49 319 61','#a4b2bb',.7,.7)
 return out+'</g>'

def gun_cradle_brace_r5(far=False):
 """Matching triangular recoil supports; far version projects above the body edge."""
 t='translate(76 -33) scale(.76 .82)' if far else ''
 out=f'<g id="gun-cradle-brace-{str(far).lower()}-r5" transform="{t}">'
 out+=path('M288 56L315 40L319 39L323 62L318 64L315 45L296 57Z','#52636f','#07131c',.8)
 out+=path('M292 56L314 44L315 47L299 57Z','#91a1aa',extra='opacity=".55"')
 out+=path('M315 40L319 39L323 62L318 64Z','url(#ribMetal)','#0b1821',.55)
 out+=path('M286 57L320 61L323 65L288 61Z','#263b49','#08131b',.65)
 out+=line('M289 58L320 62','#a7b6bf',.6,.65)
 out+=bolt(317,43,.6)+bolt(320,62,.65)+bolt(289,59,.55)
 return out+'</g>'

def car():
 defs=lg('shoulder',[(0,'#515c65'),(.13,'#6b7780'),(.36,'#89969f'),(.49,'#a1acb3'),(.66,'#8a969e'),(.84,'#67747e'),(.96,'#919fa9'),(1,'#b8c3cb')],'.14','1')+lg('side',[(0,'#777e83'),(.13,'#b5b9bb'),(.25,'#9ba1a5'),(.48,'#49535a'),(.72,'#151d24'),(1,'#050a0f')])+lg('roof',[(0,'#56616a'),(.10,'#7c878e'),(.22,'#9aa3a8'),(.32,'#8c979e'),(.51,'#687680'),(.75,'#7d8b95'),(.89,'#8797a2'),(.96,'#495c6a'),(1,'#263c4c')],'224','60','200','-4')+lg('rear',[(0,'#a3adb4'),(.12,'#4d5962'),(.38,'#242d34'),(.65,'#343e46'),(.86,'#141c23'),(1,'#070c11')],'.28','1')+lg('glass',[(0,'#071019'),(.15,'#0c1720'),(.23,'#3b4a56'),(.28,'#1b2a36'),(.49,'#101b24'),(.75,'#02070c'),(1,'#010408')],'.70','1')+lg('bonnet',[(0,'#7b858d'),(.1,'#a0a9af'),(.21,'#4c5964'),(.40,'#1a2631'),(.65,'#0a141d'),(.82,'#34434e'),(.90,'#8a99a3'),(1,'#101b24')],'.56','1')+lg('gun',[(0,'#151b20'),(.12,'#69737b'),(.23,'#b1b9bd'),(.31,'#57646c'),(.48,'#1c2831'),(.79,'#050b10'),(.93,'#36444d'),(1,'#121b22')])+lg('spoke',[(0,'#929ba1'),(.2,'#343e47'),(.42,'#68747e'),(.57,'#141d26'),(1,'#081018')],'1','1')+rg('tire',[(0,'#1d242b'),(.5,'#11171d'),(.79,'#05090e'),(.85,'#31383f'),(.92,'#151c22'),(1,'#070b10')])+rg('rim',[(0,'#8a989f'),(.35,'#263440'),(.73,'#101922'),(.86,'#657581'),(.94,'#a4afb6'),(1,'#27343e')])+rg('headlamp',[(0,'#ffffff'),(.48,'#f8feff'),(.8,'#c9d9e2'),(1,'#687d8b')])
 defs+='<linearGradient id="bodyblack" gradientUnits="userSpaceOnUse" x1="0" y1="57" x2="9" y2="123"><stop stop-color="#5c6871"/><stop offset=".13" stop-color="#1d2932"/><stop offset=".34" stop-color="#03080d"/><stop offset=".65" stop-color="#050a0e"/><stop offset=".85" stop-color="#182129"/><stop offset=".94" stop-color="#333e48"/><stop offset="1" stop-color="#070d13"/></linearGradient>'
 defs+='<linearGradient id="hoodReflection" x1="0" y1="0" x2=".2" y2="1"><stop stop-color="#18232c"/><stop offset=".18" stop-color="#6c7a85"/><stop offset=".35" stop-color="#c8d0d4"/><stop offset=".45" stop-color="#89969f"/><stop offset=".66" stop-color="#495a67"/><stop offset=".85" stop-color="#1e303e"/><stop offset="1" stop-color="#0a1722"/></linearGradient><filter id="softReflect" x="-.1" y="-.3" width="1.2" height="1.6"><feGaussianBlur stdDeviation="1.05"/></filter><filter id="broadReflect" x="-.2" y="-.3" width="1.4" height="1.6"><feGaussianBlur stdDeviation="2.0"/></filter>'
 defs+=lg('aeroUpper',[(0,'#68737c'),(.18,'#4a565f'),(.48,'#333e47'),(1,'#19242c')],'.2','1')+lg('aeroLower',[(0,'#4d5963'),(.22,'#3b4752'),(.58,'#2c3843'),(.88,'#24303a'),(1,'#141f28')],'.28','1')+lg('aeroWeb',[(0,'#7b8892'),(.22,'#45525c'),(.65,'#17242e'),(1,'#0e1720')],'1','.2')+lg('ribMetal',[(0,'#8a99a3'),(.15,'#495d6c'),(.45,'#2e4556'),(.75,'#213748'),(1,'#101f2c')],'1','.2')
 defs+=lg('m134Face',[(0,'#617581'),(.2,'#344958'),(.48,'#132430'),(.7,'#060e16'),(1,'#2e424f')],'1','.3')+lg('m134Feed',[(0,'#18232c'),(.27,'#5b6b77'),(.42,'#7d8d97'),(.62,'#2d404e'),(1,'#121e29')],'1','1')
 defs=defs.replace('<linearGradient id="roof"','<linearGradient gradientUnits="userSpaceOnUse" id="roof"')
 s='<defs>'+defs+'</defs>'
 # One continuous sports-car shell. The source footprint includes roof hardware.
 s+=path('M12 71Q14 59 17 42L33 20Q39 14 49 12L110 7L162 6L173 2L189 1L206 0L245 1L262 4L285 11L315 23Q349 30 377 45Q394 55 398 67Q405 85 399 100Q397 111 386 115L340 120L113 120L49 111L27 100Q12 90 12 71Z','url(#bodyblack)','#060b10',.7)
 # Rear quarter and roof shoulders: long edges remain smooth and unbroken.
 s+=path('M17 43L35 21Q40 16 49 14L109 9L158 8L173 17L171 25L153 27L126 50L109 59L67 57L62 43L66 20L40 22L34 51L28 65L16 63Z','url(#rear)','#0e151c',.65)
 s+=line('M37 19Q78 10 123 10Q145 10 158 11','#c7ced2',1.2,.43)
 s+=path('M40 16L110 9L158 8L169 19L163 23L147 22L137 14L100 14L68 18Z','#39434b','#0d141a',.55)
 s+=path('M35 25Q44 19 67 18L63 38Q51 37 36 43Z','#6e7d88',extra='opacity=".22" filter="url(#softReflect)"')
 s+=rear_aero_r3()
 s+=path('M164 7L175 4L184 6L190 34L187 58L171 58L171 25L176 24Z','url(#roof)','#111920',.55)
 # Roof and windscreen are separate curved surfaces, as in original.
 s+=path('M188 3L214 2L239 3Q250 6 252 17Q250 29 239 35L192 36Z','url(#roof)','#202a32',.6)
 s+=cockpit_r5()
 # Broad silver door shoulder returns light from the curved cabin shell.
 s+=path('M171 37Q179 36 188 35Q220 39 247 33Q282 48 319 62L319 65Q294 64 275 64Q237 62 189 59L172 56Z','url(#shoulder)')
 s+=path('M177 40Q213 45 246 39Q271 51 296 58Q276 57 260 54Q221 47 177 47Z','#dce2e5',extra='opacity=".14" filter="url(#softReflect)"')
 s+=path('M178 50Q219 50 254 54Q278 60 306 62L275 63Q230 62 178 57Z','#182c3b',extra='opacity=".24" filter="url(#softReflect)"')
 s+=line('M176 56Q221 61 273 61','#c9d4dc',.8,.46)
 s+=line('M197 38Q220 41 244 36','#a7b2ba',.4,.27)
 s+=line('M189 40L190 57','#151f28',.45,.37)
 # Bonnet tapers around the front guns into the bright teardrop lamp.
 s+=path('M326 31Q354 36 377 49Q391 56 396 68L397 80Q382 78 366 71L334 65L319 62L325 41Z','url(#bonnet)','#060c12',.75)
 s+=path('M329 35Q354 41 378 55Q387 61 390 68L386 71Q374 56 353 49Q339 44 327 43Z','#b5c2ca',extra='opacity=".25" filter="url(#softReflect)"')
 s+=path('M328 43Q346 48 367 58Q374 61 376 65L360 62L329 56L324 56Z','#030c14',extra='opacity=".60" filter="url(#broadReflect)"')
 s+=line('M326 31Q362 40 384 54Q395 63 396 73','#737f89',.55,.47)
 s+=path('M340 68Q361 67 388 73L394 77L391 82Q374 78 362 74L347 73Z','url(#headlamp)','#536775',.55)
 s+=path('M352 69Q372 69 388 74L389 77Q370 72 357 73Z','#f3fbff',extra='opacity=".76"')
 s+=path('M347 82Q369 87 394 83Q396 91 391 99Q374 105 350 107L351 104Q375 101 385 96Q371 90 347 88Z','#7e909f',extra='opacity=".15" filter="url(#broadReflect)"')
 # Door belt, lower sill and wheel arch lip.
 s+=path('M33 56L107 60L179 59Q232 60 269 63L273 68L190 69L105 67L54 65L29 64Z','url(#side)','#141e27',.45)
 s+=path('M35 57Q72 59 107 61Q146 60 178 60Q221 61 262 64L267 66Q222 65 177 63Q142 63 107 64Q68 63 34 60Z','#ced7dd',extra='opacity=".24" filter="url(#softReflect)"')
 s+=line('M37 56L110 60L179 59L262 63','#b4bdc4',.55,.57)+line('M178 60L178 72M176 73L175 110L270 111L274 75','#02070c',.6,1)
 s+=path('M107 111L280 116L299 121L111 121Z','#151e27','#050b11',.65)+line('M112 116L288 119','#5b6974',.65,.55)
 s+=path('M344 111L389 107L397 100Q395 111 384 113L340 119Z','#0b121a','#05090e',.5)+line('M351 111L387 108','#64727e',.55,.58)
 s+=line('M45 100Q46 72 79 72Q109 72 112 100M284 99Q287 74 313 73Q338 72 344 101','#4e606e',1.4,.82)
 s+=line('M44 100Q46 69 79 70Q111 70 114 102M282 99Q287 70 312 71Q340 70 346 100','#111c26',.9,.9)
 # Original bright arrow livery: substantial high-contrast shapes with clean edges.
 arrows=[
 'M54 49L63 55L59 55Q61 61 78 68Q59 64 51 57L48 60Z',
 'M73 36L91 45L85 45Q88 52 91 66L96 76L86 71L79 53L78 46L71 49Z',
 'M99 54L110 62L106 62Q109 74 115 88L122 93Q111 89 108 79L102 65L99 65Z',
 'M37 70L43 74L41 79L51 76L31 96L28 88L31 88L33 77L30 78Z',
 'M31 89L36 94L56 71L45 94L39 99L35 97Z',
 'M111 93L124 97L141 92L136 99L129 101L143 101L159 89L155 89L163 79L166 93L162 92L145 105L126 111L124 115L120 106Z',
 'M132 108L166 107L176 110L194 104L210 98L198 111L177 116L165 113L140 112L127 113Z',
 'M155 96L174 101L193 88L190 87L207 79L202 94L200 90L177 106L169 105Z',
 'M185 113L197 116L218 95L229 85L222 85L238 79L240 90L236 89L217 108L199 119Z',
 'M216 100L245 101L254 102L256 99L267 112L246 114L247 110L225 107L212 108Z',
 'M154 98L158 99L154 103L149 104L150 101Z']
 for p in arrows:s+=path(p,'#c8cfd2',extra='opacity=".94"')
 s+=line('M78 41L86 67L91 72M100 59L110 84M36 91L45 81M130 109L144 108M165 102L174 104L195 91','#f4f7f7',.45,.62)
 # Round '83' race badge in its source location, including its dark base bands.
 s+=circle(136.3,75.0,16.2,'#9ea9b0','#141e27',.75)+circle(136.3,75.0,14.9,'#d8dcdd','#586771',.55)
 s+=path('M122 78H151L147 87L136 90L127 87Z','#111a22')+line('M123 78H150M124 81H149','#b7c1c6',.55,.86)
 s+=label('83',125.0,64.0,23.1,13.2,'#0a1117')+label('SHOW',127.2,83.4,18.1,3.0,'#ccd4d7')
 for j,(x,w) in enumerate([(125.5,6),(132.2,7),(140.2,7)]):s+=rect(x,79,w,.65,'#c8d0d3')
 # Small white horned emblem; faithful ornament rather than damage.
 s+=path('M168 91L167 85L170 81L174 82L175 79L173 77L176 74L179 78L177 81L180 83L177 84L176 88L173 89L173 96L171 94L171 88Z','#bcc7cd')
 s+=path('M168 82L165 79L166 84L170 87L174 88L179 86L181 83L181 88L176 92L170 90L167 87Z','#c7d0d4')
 s+=line('M168 85L177 88M174 80L173 84M168 87L167 93','#101922',.8,.9)
 # Rear tail light and small metallic corner fastenings.
 s+=path('M24 46L29 52L28 62L23 66L19 62L19 53Z','#8b1018','#220a10',.8)
 s+=path('M24 48L27 53L26 60L23 63L21 59L21 53Z','#df2630')+line('M23 50L22 58','#ff6b68',.5,.7)
 # Independent, very subtle painted-metal microtexture; preserves RGB artwork.
 s+=f'<g opacity=".18">{grain(411,144,1823,7)}</g>'
 s+=wheel(80.3,102.1,29.4,30.1)+wheel(313.7,102.1,29.3,30.0)
 # Fore and rear miniguns keep original two distinct perspective placements.
 hardware=gun_cradle_brace_r5(False)+project_m134_r3(False)
 # Small roof fittings; source has these, without invented armor damage.
 # R3 cleanup: obsolete small upper-outline block at x258 is omitted.
 s+=path('M182 1L185 1L189 4L188 5L183 4Z','#353f47')
 for x,y in [(174,11),(180,50),(245,7),(252,32),(266,58),(346,41),(373,58),(160,11),(37,27),(61,53)]:s+=bolt(x,y,.45)
 for d in ['M48 14L68 12','M117 8L143 7','M173 29v5','M192 38l8 5','M244 44l2 1','M256 16l5 1','M361 52l4 2','M178 51l1 4']:
  s+=line(d,'#aeb8be',.42,.43)
 return coated_car_r3(s,hardware)

def door():
 s='<defs>'+lg('frame',[(0,'#a2aaad'),(.12,'#606b70'),(.32,'#899397'),(.66,'#555f66'),(1,'#272f36')],'1','.2')+lg('door',[(0,'#9ca6ab'),(.18,'#889398'),(.55,'#7b888e'),(.78,'#99a4a9'),(1,'#76828a')],'.8','1')+lg('bevel',[(0,'#b5bec0'),(.18,'#7e8b91'),(.48,'#3d4a52'),(.75,'#18232b'),(1,'#63717a')],'1','1')+lg('black',[(0,'#242c32'),(.3,'#141d24'),(1,'#38464f')])+rg('lock',[(0,'#c2cdd1'),(.36,'#a0afb7'),(.72,'#7a8d98'),(1,'#405664')],'.31','.24','.91')+lg('rim',[(0,'#ccd4d7'),(.22,'#8a9ba5'),(.48,'#394d5b'),(.70,'#132630'),(1,'#aebec6')],'1','1')+lg('yellow',[(0,'#d3c24d'),(.35,'#a49633'),(1,'#6c672c')],'1','1')+lg('ringShade',[(0,'#d3dce0'),(.22,'#97a7b1'),(.5,'#677c89'),(.7,'#334b59'),(1,'#738893')],'1','1')+'</defs>'
 # Header separate from the two sliding door halves and jambs.
 s+=rect(0,0,118,24,'url(#frame)','#17212a',.7)+rect(12,1.5,94,19.1,'#14202a','#050b10',.7)
 s+=rect(15,3.4,87.5,15.2,'url(#black)','#59676f',.55)+line('M17 5H101M104 3v16','#93a1a8',.55,.5)+line('M14 19H103','#070d12',.8,.8)
 s+=rect(.7,23,117.7,152,'#19242c','#0a1118',.7)
 s+=rect(6,27,107,143,'url(#frame)','#2e3c45',.8)
 # Hazard tape is inside the same source jamb strips and lower threshold.
 s+=rect(.6,24.3,5.1,149.2,'#202a31')+rect(112.2,24.2,5.4,149.5,'#1b252e')+rect(5.4,23.6,106.3,3.1,'#1b252e')+rect(6,169.6,107,4.7,'#19232b')
 for y in range(25,170,25):
  s+=path(f'M.6 {y}L5.7 {y+3}V{y+14}L.6 {y+11}Z','url(#yellow)')
  s+=path(f'M112.2 {y+11}L117.7 {y+14}V{y+25}L112.2 {y+22}Z','url(#yellow)')
 for x in range(15,109,25):
  s+=path(f'M{x} 23.6h11l2.5 3.1h-11Z','url(#yellow)')
 for x in range(8,108,25):
  s+=path(f'M{x} 169.6h12l3.8 4.7h-12Z','url(#yellow)')
 s+=rect(7.4,29.2,103.4,138.2,'url(#door)','#263741',.8)
 # Recesses stay exactly on their original sides of y=98.4/99.9 split.
 s+=rect(15.7,34,85,58,'#3d4d58','#182933',.9)+rect(17.4,35.7,81.6,54.4,'url(#door)','#a7b4ba',.55)
 s+=rect(15.7,105.5,85,57.5,'#42535e','#182933',.9)+rect(17.5,107.3,81.4,53.7,'url(#door)','#a6b6be',.5)
 s+=rect(65.1,39.3,28.4,8.1,'#273a47','#0d1e2a',.65)+rect(66.5,40.6,25.6,5.4,'#cad1d1','#8b999e',.4)+line('M67.6 41.4H90.8','#f0f1e8',.4,.6)
 # Broad cam-lock disk, with machined concentric bevels. The horizontal seam
 # deliberately crosses the disk so original split animation has no mismatch.
 s+=circle(59.3,97.3,31.0,'#1a2a35','#14232c',1.0)+circle(59.0,96.2,29.7,'url(#rim)','#c0ccd1',.55)
 s+=circle(59,96.1,26.8,'#2d414e','#3a505e',.8)+circle(59,96.2,24.5,'url(#ringShade)','#182b38',.6)
 s+=circle(59,96.2,21.2,'#223744','#9faeb7',.65)+circle(59,96.2,19.7,'url(#lock)','#3b505e',.65)
 s+=line('M38.6 91.3Q42.1 75.3 59 75.0Q71 76 76.5 84.5','#e1e7e9',.85,.65)+line('M33 96.8Q32.8 72.6 53.5 67.5','#dce4e7',.6,.75)
 s+=line('M38.9 104.2Q44.4 118.9 59 118.3Q70 118.8 78 107.6','#101f2c',.75,.8)
 # Controlled vertical wear stains with no added cracks or changed mechanics.
 rng=np.random.default_rng(1420)
 for i in range(42):
  x=float(rng.uniform(20,97));y=float(rng.choice([rng.uniform(38,60),rng.uniform(127,145)]));length=float(rng.uniform(4,18))
  s+=line(f'M{x:.2f} {y:.2f}q-1 {length/2:.2f} -.3 {length:.2f}','#243c4b',float(rng.uniform(.25,.7)),float(rng.uniform(.04,.13)))
 s+=f'<g opacity=".6">{grain(144,176,1420,9)}</g>'
 s+=rect(6.5,98.1,105.1,1.15,'#172934')+line('M7 99.8H111','#b2c1c8',.35,.55)
 s+=line('M8.2 30V97M8.2 101V167M10 168H109','#c2ced1',.6,.58)+line('M110 31V166','#263e4d',.8,.82)
 # Remote pushbutton/handle patch at x=119.5..143, y=31.4..77.4.
 s+=path('M124 34.2H139.8L142.3 37.0V70.4L139.8 73.3H123.4L121.2 70.4V37.4Z','url(#frame)','#0a1a26',.7)
 s+=path('M124 36H139L140 38H123Z','#c7d1d4')+rect(123.7,38.8,15.3,30.1,'#465965','#1b303e',.65)
 s+=rect(126.4,42.4,10.3,18.1,'#1a2b37','#0b1b28',.75)+rect(127.2,43.1,8.8,16.6,'url(#black)')+line('M125 40V67.8H138','#b7c6ce',.5,.7)
 # Lever patch is outside the animated handle crop; preserve original atlas slot.
 s+=rect(120.4,83.3,22,12.7,'url(#frame)','#152b3b',.7)+rect(123,85.9,14.8,4.6,'#0b1e2b','#9caeb9',.5)
 s+=rect(124.8,86.8,11.8,2.5,'#72848e')+rect(122.2,84.7,3.4,6.9,'#d1d8d9','#122936',.8)
 return coated(1420,s,'#697980')

def pedestal():
 s='<defs>'+lg('pedestal',[(0,'#a0adb5'),(.2,'#697d8b'),(.6,'#334a5b'),(1,'#172b3b')],'1','.8')+lg('rod',[(0,'#1b2d3b'),(.35,'#8ca1ae'),(.6,'#d0d9dd'),(.82,'#405a6b'),(1,'#172c3b')],'1','0')+lg('cap',[(0,'#a0adb3'),(.22,'#6f818c'),(.3,'#2d414f'),(.9,'#162a38'),(1,'#71828c')])+lg('face',[(0,'#506776'),(.55,'#2f495b'),(1,'#1b3447')],'1','1')+'</defs>'
 # Left three-quarter view. Preserve the oblique plinth and cap registration.
 s+=path('M.8 31.1L9.5 25.4L20.3 24.7L21.6 35.2L13.1 41.9L1.1 42.6Z','#182e3e','#0a1c2b',.6)
 s+=path('M1.2 31.4L10.1 26.4L20 25.6L12.2 31.5Z','url(#pedestal)','#2b4353',.45)
 s+=path('M12.6 31.5L20 26.3L20.9 35L13 41.3Z','#243d4e','#142a3c',.6)
 s+=path('M2 32.8L11.7 32.1L12 40.5L2 41.2Z','url(#face)','#91a2ad',.5)
 s+=path('M5.1 34.2L8.4 34L8.7 39L5.3 39.4Z','#182c3b','#5e7788',.45)+ell(6.6,36.9,.85,1.2,'#9aadb6','#2e4758',.3)
 s+=path('M10.6 23.1L12.2 20.7L18.3 20.6L19.3 23.4L18.8 26.9L11.1 27.9Z','url(#pedestal)','#1b3345',.45)
 s+=rect(13.2,7.8,3.2,13.9,'url(#rod)','#213c4f',.4)+rect(11.8,20.6,6.4,2.5,'url(#cap)','#193244',.4)
 s+=path('M7.5 1.4L25.7 1.1L25.6 6.7L16.5 8.6L7.6 7.7Z','url(#cap)','#132d40',.5)
 s+=path('M7.8 1.7L24.9 1.4L23.3 3.3L10.2 3.7L7.7 3Z','#a4b1b8')+line('M9.6 5.5L23.8 5.2','#3e586a',.5,.8)
 s+=line('M13.8 9V20M11 23L17.7 22.6M2.5 32.6L11.4 32.1M13.7 33L19.4 28.8','#c7d2d7',.35,.6)
 # Right front view. Atlas seam at x=31.5; no marks spill across the cut.
 s+=path('M39.0 28.2L41.6 25.2H50.1L52 28.5V42.2H39Z','#142b3c','#091e2d',.55)
 s+=rect(39.6,31.5,11.8,10.8,'url(#face)','#9aaeb9',.5)+rect(41.6,33.6,7.9,7.1,'#233d50','#122e42',.6)
 s+=ell(45.5,37.2,1.1,1.5,'#8da5b4','#324f62',.4)+circle(45.2,36.8,.35,'#d7e0e4')
 s+=path('M40.8 23.3L42 20.9H49L50.2 23.3V27.2H40.8Z','url(#pedestal)','#102b3e',.45)+rect(42,20.6,6.9,2.8,'url(#cap)','#244153',.4)
 s+=rect(43.7,7.5,3.6,13.5,'url(#rod)','#1b3548',.4)
 s+=path('M35.8 1H54.7V7.1L45.2 8.7L35.8 7.4Z','url(#cap)','#173248',.5)+path('M36.2 1.4H54.2L52.7 3H38Z','#a3b3bd')
 s+=line('M40.2 29.5H50.9M41.7 24H49.2M44.4 9V19.5M36.8 5H53.5','#c1d0d7',.4,.6)
 for x,y in [(2.8,33.6),(10.4,39.6),(40.9,33.1),(50.2,40.8)]:s+=bolt(x,y,.35)
 s+=f'<g opacity=".46">{grain(55,44,1828,7)}</g>'
 return coated(1828,s,'#203747')

def drum():
 s='<defs>'+lg('barrel',[(0,'#3d3010'),(.07,'#80601c'),(.21,'#a8822c'),(.48,'#927023'),(.76,'#7d5b17'),(.94,'#59400f'),(1,'#34260b')],'1','0')+lg('rib',[(0,'#b69745'),(.25,'#8d6c22'),(.48,'#49370e'),(.7,'#76591b'),(1,'#b79b50')])+rg('lid',[(0,'#c2a15a'),(.6,'#ae8b42'),(1,'#624912')],'.34','.25','.83')+lg('rim',[(0,'#d0b36c'),(.27,'#a28034'),(.56,'#4f3b10'),(.8,'#786025'),(1,'#bd9f52')],'1','.7')+'</defs>'
 # Original cylinder is almost front-on: keep its shallow ellipse, round rim,
 # two raised bands and four narrow end ribs instead of a generic drum icon.
 s+=path('M1 7.6Q2 1 26 0Q49 1 51 7.6L50.6 81.9Q49.6 88.2 26 88.8Q2.8 88.1 .8 82Z','url(#barrel)','#2c250d',.6)
 s+=ell(26,82.4,25.1,6.2,'url(#rim)','#443711',.6)+ell(26,80.8,24.9,5.6,'url(#barrel)','#4a3910',.45)
 s+=path('M2 10Q25 15 49.6 9V80.6Q25.6 87.6 1.7 80.8Z','url(#barrel)')
 s+=ell(26,6.6,25.1,5.3,'url(#rim)','#42320d',.6)+ell(26,5.4,23.8,3.9,'url(#lid)','#594318',.55)
 s+=line('M5.3 4.9Q24.3 -.6 45.2 4.6','#ddc48c',.6,.76)+line('M5 7.1Q25 12.9 46.9 7.5','#6e531c',.55,.84)
 # Repeating formed steel ribs curve around the cylindrical shell.
 for y in [12.3,16.6,20.5,24.3,68.2,72.5,76.6,80.3]:
  s+=path(f'M1.7 {y}Q25.5 {y+3.5} 50.1 {y-0.2}L50.1 {y+1.6}Q25.5 {y+5.0} 1.7 {y+1.8}Z','url(#rib)','#4a390f',.35)
  s+=line(f'M2.6 {y+.3}Q25.6 {y+3.3} 49.3 {y+.1}','#b99b50',.45,.6)
 # Broad rolled hoops at original atlas y=30 and 62.
 for y in [29.2,61.9]:
  s+=path(f'M.9 {y}Q25.5 {y+4.7} 50.8 {y-.2}L50.8 {y+2.6}Q25.5 {y+7.3} 1 {y+2.7}Z','url(#rim)','#47360e',.45)
  s+=line(f'M1.6 {y+.15}Q25.5 {y+4.4} 50.1 {y-.05}','#d4b76f',.58,.75)
  s+=line(f'M2 {y+2.75}Q26 {y+7} 50 {y+2.4}','#34270d',.6,.9)
 # Original two bung closures on top; ellipse perspective, no invented fittings.
 s+=ell(34,3.2,5.3,1.9,'#3c3218','#8a763e',.4)+path('M29.2 2.2H38.7V4.8Q34 7.1 29.2 4.8Z','url(#rib)','#3d3216',.45)+ell(34,2.3,4.7,1.45,'#b29b64','#5c4d2b',.45)+line('M31 2.1H36.7','#d7c394',.35,.7)
 s+=ell(11.2,8.8,3.1,1.5,'#382d12','#8f773a',.45)+path('M8.9 8L13.6 8L14.1 10.5H8.5Z','url(#rim)','#4b3c19',.4)+ell(11.2,7.9,2.4,1.05,'#b09a60','#574421',.4)
 # Pale triangle follows the original front-face registration and worn ink.
 s+=path('M26 29.1L44 58.8L7.1 58.8Z','none','#c5b783',1.3,extra='stroke-linejoin="round" opacity=".79"')
 s+=path('M26 32.9L40.9 57.2H10.3Z','none','#b7a571',.45,extra='opacity=".5"')
 # Biohazard trefoil: restrained, three open crescents around a small ring.
 s+='<g transform="translate(26 46.8) scale(.88) translate(-26 -46.8)" opacity=".76">'
 s+=circle(26,46.8,4.0,'none','#c4b88e',.8)
 for a in [0,120,240]:
  s+=f'<g transform="rotate({a} 26 46.8)">'
  s+=path('M23.0 35.2C17.7 37.0 18.7 44.1 23.8 45.8L25.0 43.2C20.9 42.8 20.2 38.3 23.0 35.2Z','#c5b88a')
  s+=path('M29.0 35.2C34.3 37.0 33.3 44.1 28.2 45.8L27.0 43.2C31.1 42.8 31.8 38.3 29.0 35.2Z','#c5b88a')
  s+='</g>'
 s+=circle(26,46.8,1.4,'#bfb68f')+'</g>'
 rng=np.random.default_rng(1833)
 for i in range(90):
  x=float(rng.uniform(4,49));y=float(rng.uniform(12,83));leng=float(rng.uniform(.2,2.2))
  s+=line(f'M{x:.2f} {y:.2f}l{leng:.2f} {rng.uniform(-.2,.2):.2f}',rng.choice(['#e1c77d','#3f330f','#6c5317']),float(rng.uniform(.13,.32)),float(rng.uniform(.12,.34)))
 s+=f'<g opacity=".42">{grain(52,89,1833,9)}</g>'
 s+=line('M3.2 35V58M4.4 37V48','#c2a255',.35,.4)+line('M48.6 36V59','#34290c',.6,.55)
 return coated(1833,s,'#614a15')

def compare(i,rev='r1'):
 original=Image.open(REF/f'{i}.png').convert('RGBA');new=Image.open(R/f'previews/vehicles-props-{i}-{rev}-1x.png').convert('RGBA');w,h=original.size
 for scale in [1,4]:
  pad=12;labelh=22;out=Image.new('RGB',((w*2+pad*3)*scale,(h+labelh+pad*2)*scale),'#c9cdd0');d=ImageDraw.Draw(out)
  for j,im in enumerate([original,new]):
   bg=Image.new('RGBA',(w,h),'#c9cdd0');bg.alpha_composite(im);out.paste(bg.convert('RGB').resize((w*scale,h*scale),Image.Resampling.NEAREST if scale==1 else Image.Resampling.LANCZOS),((pad+j*(w+pad))*scale,(labelh+pad)*scale));d.text(((pad+j*(w+pad))*scale,8*scale),['ORIGINAL '+str(i),rev.upper()+' SVG '+str(i)][j],fill='#1b2630')
  out.save(R/f'previews/vehicles-props-{i}-original-{rev}-{scale}x.png')

def main(rev='r6'):
 for i,fn in [(1823,car),(1420,door),(1828,pedestal),(1833,drum)]:
  p=write_part(R/f'parts/bitmap-{i}.svg',[0,0,*WH[i]],fn());render(p,WH[i][0],R/f'previews/vehicles-props-{i}-{rev}-1x.png');render(p,WH[i][0]*4,R/f'previews/vehicles-props-{i}-{rev}-4x.png');compare(i,rev)
 e={'source':'R5 car: layered cockpit and corrected gun occlusion; new editable body/receiver SVG plus native project M134 barrel paths; smooth vector car/tires alpha and independent hardware alpha. Other props: upstream R2 artwork unchanged, original alpha retained. Deterministic generated micrograin and outlined typography.','seed':SEED,'dimensions':WH,'shared_shape_map':{'1823':[1824],'1420':[1421,1422,1423,1424],'1828':[1829,1830,1831],'1833':[1834,1835,1836,1837]},'unchanged':'All SWF fill matrices, original clipping polygons, atlas dimensions, animation display states and scene placement are retained by assembly. Bitmap1823 body outline is smoothed and new M134 alpha differs deliberately.','files':{str(i):{'sha256':hashlib.sha256((R/f'parts/bitmap-{i}.svg').read_bytes()).hexdigest()} for i in IDS}}
 e['files']['1823'].update({'source':'source/vehicles_props.py: car/cockpit_r5/gun_cradle_brace_r5/rear_aero_r3/project_m134_r3/coated_car_r3','native_barrel':'reference/m134-native/render/m134-native-barrel-only-phase3.svg','alpha':'Smooth editable vehicle/tire outline, independent M134 hardware alpha; intentionally not old alpha','receiver':'Same-source referenced redrawing, not an untouched native whole gun','canvas':[411,144]})
 (R/'qa/vehicles-props-method.json').write_text(json.dumps(e,ensure_ascii=False,indent=2))

def audit_and_clips(rev='r6'):
 details=json.loads((REF/'vehicles-props-shape-details.json').read_text());nodes=json.loads((REF/'vehicles-props-original-nodes.json').read_text())
 rows=[]
 for sh in details:
  sid=sh['id'];vb=sh['viewBox'];old=write_part(R/f'previews/vehicles-props-shape-{sid}-original.svg',vb,nodes[str(sid)]['svgInner']);chunks=[]
  for j,f in enumerate(sh['fills']):
   if f['type']=='solid':chunks.append(path(f['path'],f['color'],extra=f'fill-opacity="{f.get("alpha",1)}"'));continue
   if f['type']!='bitmap' or f['bitmapId']==65535:continue
   i=f['bitmapId'];cid=f'c{sid}_{j}';mat=' '.join(map(str,f['matrix']))
   chunks.append(f'<clipPath id="{cid}">{path(f["path"],"white")}</clipPath><g clip-path="url(#{cid})"><g transform="matrix({mat})">'+inner(R/f'parts/bitmap-{i}.svg',f'p{sid}_{j}')+'</g></g>')
  new=write_part(R/f'previews/vehicles-props-shape-{sid}-new.svg',vb,''.join(chunks))
  for p in [old,new]:render(p,max(1,round(vb[2]*4)),p.with_suffix('.png'))
  rows.append({'id':sid,'viewBox':vb,'fills':[{k:f[k] for k in ['type','bitmapId','matrix','path'] if k in f} for f in sh['fills']]})
 for group,ids in [('door',[1421,1422,1423,1424]),('pedestal',[1829,1830,1831]),('drum',[1834,1835,1836,1837])]:
  ims=[];scale=2
  for sid in ids:
   vb=nodes[str(sid)]['viewBox'];wh=(round(vb[2]*scale),round(vb[3]*scale));pair=[]
   for role in ['original','new']:
    im=Image.open(R/f'previews/vehicles-props-shape-{sid}-{role}.png').convert('RGBA').resize(wh,Image.Resampling.LANCZOS);pair.append(im)
   ims.append((sid,wh,pair))
  maxw=max(x[1][0] for x in ims);cw=maxw+24;height=sum(x[1][1]+42 for x in ims)+12;out=Image.new('RGB',(cw*2+12,height),'#c8ced2');d=ImageDraw.Draw(out);y=8
  for sid,wh,pair in ims:
   for j,im in enumerate(pair):
    x=12+j*cw;d.text((x,y),str(sid)+' '+['ORIGINAL','NEW SVG'][j],fill='#152838');bg=Image.new('RGBA',wh,'#c8ced2');bg.alpha_composite(im);out.paste(bg.convert('RGB'),(x,y+22))
   y+=wh[1]+42
  out.save(R/f'previews/vehicles-props-{group}-clips-review.png')
 alpha={}
 for i in IDS:
  a=np.array(Image.open(REF/f'{i}.png').convert('RGBA'));b=np.array(Image.open(R/f'previews/vehicles-props-{i}-{rev}-1x.png').convert('RGBA'))
  alpha[str(i)]={'original_size':list(a.shape[1::-1]),'new_size':list(b.shape[1::-1]),'alpha_mismatch_pixels':int(np.count_nonzero(a[:,:,3]!=b[:,:,3])),'max_alpha_difference':int(np.abs(a[:,:,3].astype(int)-b[:,:,3].astype(int)).max()),'visible_rgb_changed_pixels':int(np.count_nonzero((a[:,:,:3]!=b[:,:,:3]).any(2)&(a[:,:,3]>0))),'visible_pixels':int(np.count_nonzero(a[:,:,3]))}
 state=[]
 for root,inc in [(1430,[1421,1422,1423,1424]),(1832,[1829,1830,1831]),(1838,[1834,1835,1836,1837])]:
  bs=[];frs=nodes[str(root)]['frames'];unique={json.dumps(fr,sort_keys=True) for fr in frs}
  for fr in frs:
   for z in fr.values():
    if z.get('id') not in inc:continue
    x,y,w,h=nodes[str(z['id'])]['viewBox'];a,b,c,d,tx,ty=z.get('matrix',[1,0,0,1,0,0]);ps=[(a*xx+c*yy+tx,b*xx+d*yy+ty)for xx in [x,x+w]for yy in [y,y+h]];bs+=ps
  u=[min(p[0]for p in bs),min(p[1]for p in bs),max(p[0]for p in bs),max(p[1]for p in bs)]
  state.append({'sprite':root,'frames':len(frs),'raw_distinct_display_states':len(unique),'unclipped_visible_leaf_union_ltrb':u,'matrix_clipDepth_colorMult_colorAdd':'unchanged in original reference, passed to main scene assembly'})
 evidence={'alpha':alpha,'shape_clip_audit':rows,'animated_roots':state,'review_iteration':rev,'external_review_applied':['Chunky dark windowed wheel hubs replace dense silver radial spokes','Upper car shell has continuous curved reflection instead of hard triangular armor face','R3 uses native project M134 barrels plus same-source reconstructed receiver/motor, vehicle mounts, and solid curved braces','Drum formed ribs flattened and narrower bright lip; cylindrical dark side retained','Door center lighting restored upper-left convex gradient'],'art_source':'R3 car: native project M134 barrel SVG plus newly authored car/receiver paths and grain. Body outline uses smooth SVG; other props preserve upstream alpha.'}
 (R/'qa/vehicles-props-geometry-alpha.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2))
 return evidence

if __name__=='__main__':
 import sys
 rev=sys.argv[1] if len(sys.argv)>1 else 'r6'
 if rev=='--audit':audit_and_clips(sys.argv[2] if len(sys.argv)>2 else 'r6')
 else:main(rev)
