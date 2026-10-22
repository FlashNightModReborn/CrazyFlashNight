"""Native editable layers, traced composition from CF6 bitmap1580. No raster embedding."""
from pathlib import Path
import random,sys,json
sys.path.insert(0,str(Path(__file__).parent));from svg_native import write_part,assemble,render
R=Path(__file__).resolve().parents[1];VB=[0,0,800,452]
def path(d,fill,stroke=None,w=1,extra=''):
 return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{w}" stroke-linejoin="round"' if stroke else '')+f' {extra}/>'
def rect(x,y,w,h,f,extra=''):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{f}" {extra}/>'
def grad(id,a,b):return f'<linearGradient id="{id}" x1="0" y1="0" x2="0.3" y2="1"><stop stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>'
def save(name,s):write_part(R/f'parts/{name}.svg',VB,s)
rng=random.Random(1580)
defs='<defs>'+grad('soil','#11110e','#3b3223')+grad('steel','#4b4c40','#2e332c')+grad('wall','#2a3730','#101c17')+grad('car','#434843','#151b19')+grad('roof','#55584f','#262e29')+grad('glass','#101b1c','#263533')+'</defs>'
s=defs+rect(0,0,800,452,'#050907')
for _ in range(125):
 x=rng.randint(292,798);y=rng.randint(3,152);r=rng.choice([.35,.45,.6,.8]);s+=f'<circle cx="{x}" cy="{y}" r="{r}" fill="{rng.choice(["#626352","#9c8863","#bbb490"])}" opacity="{rng.uniform(.3,.8):.2f}"/>'
s+=path('M0 164 Q210 150 340 170 Q485 158 590 171 L800 165 V452 H0Z','url(#soil)')
# Sparse soil flecks: broad ground remains quiet behind characters.
for _ in range(1700):
 x=rng.uniform(250,800);y=rng.uniform(170,452);c=rng.choice(['#625038','#1b1d17','#4a3e2b']);s+=path(f'M{x:.1f} {y:.1f} l{rng.uniform(1,3.5):.1f} {-rng.uniform(.1,.5):.1f}','none',c,rng.uniform(.35,.65),extra='opacity=".32"')
# Low contrast gravel flecks and compressed uneven ruts, kept behind action silhouettes.
for _ in range(380):
 x=rng.uniform(325,800);y=rng.uniform(179,451);k=(y-160)/292
 if x < 270+(y-164)*.94:continue
 w=rng.uniform(1.5,4.5)*(0.5+k);h=rng.uniform(.4,1.3)
 s+=path(f'M{x:.1f} {y:.1f} l{w*.6:.1f} {-h:.1f} l{w*.4:.1f} {h*.5:.1f} l{-w*.2:.1f} {h:.1f}Z',rng.choice(['#51452f','#1b2017','#635137']),None,extra='opacity=".35"')
for _ in range(65):
 x=rng.uniform(420,795);y=rng.uniform(220,450)
 s+=path(f'M{x:.1f} {y:.1f} q9 -3 21 -1 l-5 3 q-8 -2 -16 0Z','#1c2119',None,extra='opacity=".2"')
save('01-night-soil',s)
# Distinct crushed car bodies, windscreens, fenders and bumpers; fixed original pile footprint.
def car(x,y,w,h,rot=0,shade=1):
 # Coordinates in 120x40 form, with uneven crushed roof silhouette.
 b='<g transform="translate(%s %s) rotate(%s) scale(%s %s)" opacity="%s">'%(x,y,rot,w/120,h/40,shade)
 b+=path('M1 24 L8 18 L31 15 L43 10 L59 8 L64 11 L72 6 L84 13 L111 17 L119 24 L115 33 L5 35Z','url(#car)','#090f0d',1.5)
 b+=path('M30 16 L44 11 L58 10 L64 13 L73 8 L81 14 L58 15Z','url(#glass)','#0b1311',1)
 b+=path('M43 11 L44 14 M64 11 L67 14','none','#69726a',.7)
 b+=path('M6 23 L32 20 L55 21 L76 19 L111 21 L115 25 L78 24 L55 27 L23 25Z','#485047',None,extra='opacity=".7"')
 b+=path('M16 18 L21 26 L21 32 M57 17 L57 29 L84 29 L90 17 M59 20 H66','none','#111b16',1)
 b+=path('M5 31 L113 28 L115 32 L8 36Z','#242a26','#0c120f',1)
 b+=path('M8 31 L33 30 M46 31 L79 30 M95 29 L112 29','none','#788076',.8)
 b+=path('M9 25 L21 25 L20 28 L8 28Z M100 23 L113 23 L114 26 L101 26Z','#898d78','#202923',.7)
 for a in [29,94]:
  b+=f'<ellipse cx="{a}" cy="32" rx="9" ry="7" fill="#080d0b" stroke="#353d35" stroke-width="1.3"/><ellipse cx="{a}" cy="32" rx="4" ry="3.8" fill="#394139"/>'
 b+=path('M35 35 L38 27 L42 35 M75 15 L79 22 L73 27','none','#111a15',1)
 # crushed hood planes, torn door lip and dark exposed grille, never regular stacked intact cars
 b+=path('M26 18 L43 17 L52 20 L48 23 L56 26 L34 25 L32 22 L21 22Z','#64695a',None,extra='opacity=".45"')
 b+=path('M55 18 L65 16 L78 19 L74 24 L63 25 L60 22Z','#101913')
 b+=path('M5 28 L17 29 L24 27 L23 33 L8 34Z','#070e0a')
 b+=path('M29 20 L39 22 L35 25 M48 19 L44 23 L50 24 M80 23 L87 27 L83 31','none','#8c8e77',.65)
 b+=path('M53 28 L78 27 L81 31 L53 33Z','#111911','#414b3b',.6)
 for xx in range(56,78,3):b+=path(f'M{xx} 29 l1 2','none','#626958',.6)
 b+=path('M7 36 Q64 31 116 35 L114 39 L8 39Z','#080f0b',None,extra='opacity=".7"')
 return b+'</g>'
s=defs
# Back wreck silhouettes taper into darkness, as in original.
def wreckfront(x,y,w,h,angle,opacity):
 kind=int(x+y)%4
 q='<g transform="translate(%s %s) rotate(%s) scale(%s %s)" opacity="%s">'%(x,y,angle,w/100,h/35,opacity)
 q+=path('M1 12 L8 7 L28 8 L34 3 L59 5 L72 1 L89 8 L96 11 L100 27 L91 31 L10 34 L2 28Z','url(#car)','#080e0b',1.3)
 q+=path('M7 11 L30 10 L37 6 L58 9 L72 4 L86 10 L94 13 L84 17 L60 15 L37 19 L16 16Z','#53594c','#202a20',.7)
 q+=path('M16 11 L30 14 L36 11 M48 9 L45 14 L55 17 M73 7 L65 13 L75 15 M86 12 L81 17','none','#93917c',.65)
 q+=path('M9 19 L25 18 L27 23 L11 25Z M72 18 L91 16 L92 23 L76 24Z','#868c76','#1a241b',1)
 q+=path('M29 18 L68 17 L72 26 L27 28Z','#080f0b','#58604e',.7)
 for k in range(30,69,4):q+=path(f'M{k} 20 l1 5','none','#68735e',.65)
 q+=path('M4 28 L26 29 L47 26 L69 29 L97 25 L98 29 L70 33 L48 30 L27 33 L6 33Z','#555c4e','#101a12',1)
 q+=path('M7 34 L22 30 L27 35 M76 31 L82 35 L92 31','none','#080f0a',2)
 if kind==0:
  q+=path('M0 8 L26 4 L31 15 L22 21 L34 27 L25 34 L2 35Z','#172019','#0a110c',1)
  q+=path('M3 12 L19 9 L23 17 L14 21 L20 29 L5 31Z','#333b30')
  q+=path('M6 13 L16 16 L11 22 M16 23 L18 28','none','#59604b',.7)
 elif kind==1:
  q+=path('M58 4 L84 1 L95 8 L91 21 L100 32 L77 35 L71 26 L64 21Z','#1b241b','#0a110c',1)
  q+=path('M68 9 L82 5 L86 18 L77 26 L82 32 L71 29Z','#414735')
  q+=path('M72 12 L81 15 L75 22','none','#6c7159',.7)
 elif kind==2:
  q+=path('M11 18 L32 15 L41 19 L52 15 L76 20 L82 27 L61 25 L46 30 L20 29Z','#182219','#0b130d',1)
  q+=path('M14 20 L30 19 L37 23 L49 20 L65 22 L63 26 L45 26 L37 28Z','#4a513e')
 else:
  q+=path('M9 1 L24 5 L43 2 L55 7 L76 5 L88 15 L68 13 L54 16 L39 12 L21 15Z','#303b2c','#0a120c',1)
  q+=path('M15 5 L27 9 L42 6 L52 11 L72 9','none','#636c50',.7)
 q+=path('M43 29 L58 29 L59 32 L43 33Z','#a5a28c','#2b3328',.4)
 return q.replace('#868c76','#555e4d').replace('#53594c','#394233').replace('#93917c','#686c56').replace('#555c4e','#3b4535').replace('#a5a28c','#72735e')+'</g>'
# Compact crushed front/underbody stack. Fragments lean differently rather than complete cars.
for args in [(458,76,88,30,10,.22),(481,101,91,28,-8,.3),(512,124,80,22,7,.25)]:s+=car(*args)
for args in [(287,42,80,26,11,1),(289,64,90,31,-3,1),(291,87,102,32,7,1),(291,112,111,32,-7,1),(289,139,115,34,-3,1),(364,102,82,30,12,.75),(379,126,83,31,-5,.8),(426,124,77,27,9,.55),(454,142,78,26,-5,.4)]:s+=wreckfront(*args)
# Loose buckled sheet and detached tire reveal damage rather than pristine automobile repetitions.
s+=path('M361 85 L375 78 L390 86 L385 96 L370 101 L364 94Z','#454b3f','#111a12',1)
s+=path('M365 85 L376 88 L370 98 M379 84 L379 94','none','#777b65',.7)
s+='<g transform="translate(424 119) rotate(-22)"><ellipse rx="12" ry="8" fill="#070c09" stroke="#424c3b" stroke-width="3"/><ellipse rx="5" ry="3" fill="#414a38"/></g>'
# Foreground torn white door: original diagnostic right edge of wreck pile.
s+=path('M478 124 L489 120 L496 133 L504 135 L508 153 L477 158 L468 149 L470 138Z','#535e4b','#0c1410',1.7)
s+=path('M479 126 L488 123 L493 136 L479 136Z','#121d18','#92998a',.7)
s+=path('M477 139 L498 138 L502 149 L478 153Z','#636b59','#303a30',.7)
s+=path('M480 141 h5 M473 138 L472 151 M504 151 l7 6','none','#19221b',1.5)
# Split crushed fender forward of central pile.
s+=path('M397 147 L416 133 L439 137 L450 149 L442 166 L415 162 L409 169 L399 158Z','#3b423a','#101711',1.2)
s+=path('M406 145 L418 139 L432 143 L426 152 L414 151Z','#151f19')
s+=path('M404 157 L418 152 L437 156 M416 153 l-1 8 M433 157 l7 8','none','#6b7062',.8)
save('02-wreck-pile',s)
# Original metal floor: perspective seams and sparse alternating tread clusters.
edge='M0 164 L281 164 L311 187 L355 202 L344 227 L378 243 L389 274 L428 296 L442 321 L469 337 L468 359 L515 387 L537 410 L577 452 H0Z'
s=defs+'<defs><linearGradient id="fade" gradientUnits="userSpaceOnUse" x1="270" y1="164" x2="320" y2="117"><stop stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient><mask id="transition">'+rect(0,164,800,288,'url(#fade)')+'</mask><clipPath id="floorclip">'+rect(0,164,800,288,'white')+'</clipPath></defs><g mask="url(#transition)">'+rect(0,164,800,288,'url(#steel)')
s+='<g clip-path="url(#floorclip)">'
for y in [309]:s+=path(f'M0 {y} L800 {y+20}','none','#18201a',.6)+path(f'M0 {y+1.7} L800 {y+21.7}','none','#6b6e5d',.45,extra='opacity=".5"')
for x in [-50,180]:s+=path(f'M{x} 164 L{x+330} 452','none','#18211a',.45)
for row,y in enumerate(range(169,453,12)):
 for col,x in enumerate(range(-20,660,24)):
  xx=x+(row%2)*12;yy=y+(.025*x)
  if rng.random()<.08:continue
  for k in range(3):
   dx=(k-1)*3.6;lean=8 if (row+col)%2 else -8
   s+=path(f'M{xx+dx:.1f} {yy:.1f} l{lean} 5.5 l2.2 -.8 l{-lean} -5.5Z','#141e17')+path(f'M{xx+dx+.7:.1f} {yy-.5:.1f} l{lean} 5.5','none','#8f927a',.85,extra='opacity=".7"')
# broken sparse contact dirt along transition, not noise over the whole floor
for _ in range(110):
 y=rng.uniform(175,450);x=(y-164)*.95+290+rng.uniform(-45,12)
 s+=path(f'M{x:.1f} {y:.1f} l{rng.uniform(5,17):.1f} -1.5','none','#6b5433',rng.uniform(.7,1.6),extra='opacity=".55"')
# Quiet wide wear patches imply curved reflection without chrome bands.
for _ in range(180):
 x=rng.uniform(0,560);y=rng.uniform(170,452)
 s+=path(f'M{x:.1f} {y:.1f} l{rng.uniform(7,26):.1f} 2','none','#a1a18a',.45,extra='opacity=".18"')
s+='</g></g>'
# Irregular earth crossing the metal edge softens material transition while preserving boundary.
for _ in range(240):
 y=rng.uniform(176,452);x=(y-164)*.94+286+rng.uniform(-25,22)
 s+=f'<ellipse cx="{x:.2f}" cy="{y:.2f}" rx="{rng.uniform(2,11):.2f}" ry="{rng.uniform(.5,2):.2f}" fill="#3b3223" opacity=".32"/>'
save('03-metal-floor',s)
# Green industrial wall panels with chipped diagonal safety base.
s=defs+rect(0,0,292,165,'url(#wall)')
s+='<defs><linearGradient id="walltop" x2="0" y2="1"><stop stop-color="#050e0a" stop-opacity=".75"/><stop offset="1" stop-color="#050e0a" stop-opacity="0"/></linearGradient><radialGradient id="wallgrime"><stop stop-color="#060f0b" stop-opacity=".5"/><stop offset="1" stop-color="#060f0b" stop-opacity="0"/></radialGradient></defs>'+rect(0,0,292,55,'url(#walltop)')
for x,y,rx,ry in [(40,142,45,20),(171,121,60,35),(260,100,38,45),(88,44,50,35)]:s+=f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="url(#wallgrime)"/>'
for x in [25,91,157,224,291]:s+=path(f'M{x} 0 V151','none','#14231a',.6)+path(f'M{x+1} 0 V150','none','#506054',.3,extra='opacity=".45"')
for y in [30,98]:s+=path(f'M0 {y} H292','none','#14231a',.6)+path(f'M0 {y+1} H292','none','#697263',.45,extra='opacity=".45"')
for x in [28,94,160,227,287]:
 for y in [34,94,142]:s+=f'<circle cx="{x}" cy="{y}" r="1" fill="#080f0b"/><path d="M{x-.6} {y-.5} h1" stroke="#56634f" stroke-width=".45"/>'
s+=rect(0,148,292,17,'#111a14')
s+='<defs><clipPath id="wallbase">'+rect(0,148,292,17,'white')+'</clipPath></defs><g clip-path="url(#wallbase)">'
for x in range(-8,295,27):s+=path(f'M{x} 164 l7 -15 h14 l-7 15Z','#a69a39','#172019',.7)
s+='</g>'
s+=path('M0 164 H292','none','#697057',1)
for _ in range(85):
 x=rng.uniform(1,290);y=rng.uniform(3,146)
 s+=path(f'M{x:.1f} {y:.1f} l{rng.uniform(-.5,.5):.2f} {rng.uniform(2,10):.1f}','none','#6b7561',.45,extra='opacity=".15"')
for x in [17,84,145,213,280]:
 s+=path(f'M{x} 150 l-2 12 M{x+8} 150 l-3 4','none','#263226',1,extra='opacity=".6"')
# Danger plaque and radiation pictogram, same locations and footprint.
s+=rect(76,76,37,24,'#949b80','stroke="#111b14" stroke-width="1"')+rect(79,79,31,8,'#8a6529')
s+='<text x="94.5" y="85" text-anchor="middle" font-family="DejaVu Sans" font-weight="bold" font-size="5.8" fill="#d9b743">DANGER</text>'
s+=path('M80 91 H108 M82 94 H106 M84 97 H103','none','#344134',1)
s+=path('M140 72 L157 99 H124Z','#acaa46','#172319',1.3)
s+='<circle cx="140" cy="89" r="2.3" fill="#243120"/>'
for r in [0,120,240]:s+='<g transform="rotate(%s 140 89)">'%r+path('M137 84 L135 78 Q140 76 145 78 L143 84Z','#243120')+'</g>'
# Broken wall electronic cavity at top. Bent perimeter, exposed board and hanging wires.
s+=path('M204 0 L267 0 L273 13 L266 29 L250 35 L222 32 L211 25Z','#080f0c','#687260',1.6)
s+=path('M212 1 L264 2 L264 24 L253 30 L220 27Z','#153324','#303f30',1)
for _ in range(34):
 x=rng.uniform(215,260);y=rng.uniform(2,25);s+=path(f'M{x:.1f} {y:.1f} h{rng.uniform(2,6):.1f} v{rng.uniform(1,5):.1f}','none','#64805b',.45)
for x,y in [(217,10),(238,7),(250,17)]:s+=rect(x,y,6,5,'#111b14','stroke="#81927a" stroke-width=".5"')
s+=path('M210 3 L206 14 L215 25 L212 43 M226 29 L229 44 L226 54 M252 31 L252 47 M263 22 L273 30','none','#0a110d',2.2)
save('04-wall',s)
# Floor stencil retains the original service-lift marking footprint.
s='<g transform="translate(260 350) matrix(.75 .03 .65 .55 0 0)" fill="#b5b5a0" opacity=".64"><text x="0" y="14" font-family="DejaVu Sans" font-size="20" font-weight="bold">DECK</text><text x="22" y="57" font-family="DejaVu Sans" font-size="47" font-weight="bold">01</text><text x="9" y="77" font-family="DejaVu Sans" font-size="13" font-weight="bold">SERVICE LIFT</text>'+path('M115 8 Q131 -4 143 0 L173 9 L161 21 L137 14 L119 22 L108 17Z M124 27 L142 20 L168 27 L170 41 L146 47 L123 38Z','#b5b5a0')+'</g>'
# cyan light fixtures on three floor points, matching original baked positions
for x,y,w in [(239,168,58),(391,282,48),(593,438,44)]:
 s+=path(f'M{x-8} {y-2} h{w+5} l16 13 h{-w-5}Z','#1b2826','#5a746b',.8)
 s+=path(f'M{x} {y+1} h{w-6} l8 6 h{-w+6}Z','#153d40','#377880',.8)
 s+=path(f'M{x+4} {y+3} h{w-12} l3 2 h{-w+12}Z','#78d7d6')
save('05-markings-lights',s)
s='<defs><radialGradient id="glow"><stop stop-color="#45c9d1" stop-opacity=".2"/><stop offset="1" stop-color="#45c9d1" stop-opacity="0"/></radialGradient></defs>'
for x,y,rx in [(270,175,60),(418,288,52),(616,444,50)]:s+=f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="22" fill="url(#glow)"/>'
save('06-optional-light-glow',s)
from atmosphere_r2 import apply
apply()
from seams_r3 import apply as apply_seams
apply_seams()
from soil_integration import apply as apply_soil
apply_soil()
names=['01-night-soil','02-wreck-pile','03-metal-floor','04-wall','05-markings-lights','06-optional-light-glow']
assemble(VB,[{'path':R/f'parts/{n}.svg'} for n in names],R/'previews/background-r4.svg');render(R/'previews/background-r4.svg',1600)
# Actual replacement background1581 preserves original registration by translation.
assemble([-676.95,-212.95,800,452],[{'path':R/f'parts/{n}.svg','matrix':[1,0,0,1,-676.95,-212.95]} for n in names],R/'parts/background-1581.svg')
(R/'source/background-layers.json').write_text(json.dumps({'native_viewBox':VB,'original_shape':1581,'original_bitmap':1580,'replacement_viewBox':[-676.95,-212.95,800,452],'layers':names,'optional_glow':names[-1]},indent=2))
