"""Native editable stage 11 culture-chamber housing and biohazard drum.
The transparent chamber opening is intentional; shape 1901 owns its original
40%-alpha cyan glass. Enemy atlas 261 and all monster placements stay untouched.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
import json, math, re, random
from PIL import Image, ImageDraw
from svg_native import write_part, render
R=Path(__file__).resolve().parents[1]
A=R/'reference'

def path(d, fill='none', stroke='#080c10', sw=.65, op=1, extra=''):
 return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{op}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'
def ellipse(cx,cy,rx,ry,fill,stroke='none',sw=.5,op=1):
 return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{op}"/>'
def rect(x,y,w,h,fill,stroke='none',sw=.5,rx=0):
 return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'
def screw(x,y,r=.5):
 return ellipse(x,y,r,r,'#172027','#080c11',.18)+path(f'M{x-r*.45} {y-r*.3}l{r*.9} {r*.6}',stroke='#91a0aa',sw=.17)

def build_shell():
 s='''<title>Culture chamber shell with separate side control unit</title>
 <desc>Native paths, gradients and editable details. Transparent center is preserved for original shape 1901 glass and unchanged enemy sprite.</desc><defs>
 <linearGradient id="body" x1="0" x2="1"><stop stop-color="#272c32"/><stop offset=".14" stop-color="#61676f"/><stop offset=".31" stop-color="#777e85"/><stop offset=".57" stop-color="#484f57"/><stop offset=".78" stop-color="#555b65"/><stop offset=".94" stop-color="#383f48"/><stop offset="1" stop-color="#222930"/></linearGradient>
 <linearGradient id="upperbody" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#343c45"/><stop offset=".12" stop-color="#65707b"/><stop offset=".3" stop-color="#858e97"/><stop offset=".56" stop-color="#68747f"/><stop offset=".77" stop-color="#727c87"/><stop offset=".94" stop-color="#58636e"/><stop offset="1" stop-color="#303943"/></linearGradient>
 <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#8b949c"/><stop offset=".3" stop-color="#525b64"/><stop offset=".66" stop-color="#292f37"/><stop offset="1" stop-color="#626b73"/></linearGradient>
 <linearGradient id="dark" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#353e49"/><stop offset=".44" stop-color="#242b35"/><stop offset="1" stop-color="#11171d"/></linearGradient>
 <radialGradient id="cap" cx=".4" cy=".2" r=".85"><stop stop-color="#505966"/><stop offset=".56" stop-color="#383f4a"/><stop offset="1" stop-color="#232b35"/></radialGradient>
 <radialGradient id="lens" cx=".36" cy=".25" r=".8"><stop stop-color="#3a839b"/><stop offset=".45" stop-color="#21687e"/><stop offset=".83" stop-color="#164459"/><stop offset="1" stop-color="#0a2432"/></radialGradient>
 <linearGradient id="floor" x1="0" y1="0" x2="1" y2=".3"><stop stop-color="#777f84"/><stop offset=".23" stop-color="#b1b7b9"/><stop offset=".45" stop-color="#d8dbd9"/><stop offset=".63" stop-color="#949b9e"/><stop offset=".86" stop-color="#c0c5c4"/><stop offset="1" stop-color="#818a90"/></linearGradient>
 <linearGradient id="box" x1="0" x2="1"><stop stop-color="#42494f"/><stop offset=".25" stop-color="#62696e"/><stop offset=".7" stop-color="#4d555c"/><stop offset="1" stop-color="#303943"/></linearGradient>
 <linearGradient id="red" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#da3c46"/><stop offset=".4" stop-color="#9d1527"/><stop offset="1" stop-color="#4a0b16"/></linearGradient>
 <clipPath id="upperface"><path d="M70.1 38Q110 60 149.4 38V51Q149.2 62.5 109.6 62.5Q70 62.5 70.1 51Z"/></clipPath>
 <clipPath id="lowerface"><path d="M71.7 162Q109.5 181.2 149.1 163V179Q148 192.5 109 192.5Q71.8 192 71.7 179Z"/></clipPath>
 </defs>'''
 # Top housing: a deep metal drum and raised dome, not a turret.
 s+='<g id="upper-housing">'
 s+=path('M70.1 32.7Q110 12.3 149.4 32.7V51Q149.3 62.6 109.7 62.6Q70 62.5 70.1 51Z','url(#upperbody)',sw=1.1)
 s+=path('M71.5 48.7V51Q73.2 60 110 60.8Q146 60.8 148.1 51V48.7',stroke='#adb4bb',sw=.34,op=.4)
 s+=path('M73.4 54.7Q109.8 68.1 146 54.6',stroke='#141b22',sw=.7)
 s+=path('M70.8 42Q110 62.4 148.6 42',stroke='#272e37',sw=.65)
 s+=ellipse(109.8,32,39.7,14.8,'url(#edge)','#090e14',.9)
 s+=ellipse(109.8,30.4,36.7,12.2,'url(#cap)','#11171e',.65)
 # Dome segmented plates and concentric machined joins.
 s+=path('M91.9 20.1Q89.4 25.8 90.2 29.2L95.5 32.5L91 42.2',stroke='#131a23',sw=.7)
 s+=path('M125.8 20Q128.1 26 127.5 29.4L121.7 32.5L127.4 42.3',stroke='#101720',sw=.7)
 s+=path('M74.8 27.5Q75.4 35.1 91.3 39.5M128.7 39Q142.6 35.8 145 28.1',stroke='#68737e',sw=.32,op=.65)
 s+=path('M94.8 32.3Q109.7 35.5 122.3 32.3',stroke='#77818c',sw=.3,op=.4)
 # Ribbed retaining ring follows the elliptical projected arc.
 s+=path('M70.1 33.8Q109.7 56.6 149.4 33.8L149.4 40Q110 61.9 70.1 40Z','#141c25',sw=.5)
 for i in range(43):
  t=math.pi-i*math.pi/42
  x=109.75+39.2*math.cos(t);y=33.9+11.2*math.sin(t)
  w=.7+(.24*math.sin(t))
  s+=path(f'M{x:.3f} {y:.3f}v4.7',stroke='#848f98',sw=w)
  s+=path(f'M{x+.7:.3f} {y+.5:.3f}v4.1',stroke='#343e48',sw=.32)
 s+=path('M70.2 33.8Q109.7 56.5 149.3 33.8',stroke='#8f99a1',sw=.45)
 s+=path('M70.2 40Q110 62.4 149.4 40',stroke='#121921',sw=.65)
 # Recessed unlit front port; preserve original black aperture.
 s+=path('M97 46.6L124 46.5V58.7H97Z','#767e86',sw=.7)
 s+=path('M98.4 47.5H122.7V57.6H98.4Z','#141b20',sw=.5)
 s+=rect(99.5,48.7,22.1,7.7,'#030609','#060b0f',.4)
 s+=path('M98.4 57.7H123M123.1 47.5V57.7',stroke='#a1a7ab',sw=.35,op=.6)
 s+=path('M100 49.1H121.1',stroke='#2b3640',sw=.35)
 for x,y in [(96,47.2),(125.2,47.2),(96,58.1),(125.2,58.1)]:s+=screw(x,y,.42)
 # Minute wear stays inside the manufactured metal skin.
 s+='<g clip-path="url(#upperface)" opacity=".14">'
 for x,y,w in [(76,46,3),(81,54,2),(85,46,4),(132,52,5),(141,48,2),(129,57,3),(90,57,2)]:s+=path(f'M{x} {y}l{w} -.3',stroke='#b9c0c2',sw=.19)
 rng=random.Random(1588)
 for j in range(210):
  x=rng.uniform(71,149);y=rng.uniform(42,63);w=rng.uniform(.15,1.4)
  s+=path(f'M{x:.3f} {y:.3f}l{w:.3f} {rng.uniform(-.15,.15):.3f}',stroke=rng.choice(['#c9d0d2','#171e26']),sw=rng.uniform(.08,.16),op=rng.uniform(.22,.48))
 s+='</g>'
 # Top instrument pedestal with two round blue gauges.
 s+=path('M92.1 8.2L94.3 .6H123.8L126.1 8.2Z','url(#dark)',sw=.9)
 s+=path('M94.8 1.6H123.4M93.3 6.7H125',stroke='#67727d',sw=.4,op=.5)
 s+=path('M92 8.3H126.4L126.5 26.6H113.4L112.7 25H106.6L106.1 26.6H91.9Z','url(#box)',sw=.85)
 s+=path('M92.8 9.1H125.5M93 9.4V25.5',stroke='#9aa5ac',sw=.35,op=.55)
 for x in [101.4,116.3]:
  s+=ellipse(x,17.5,5.3,5.8,'#222b34','#0a1118',.6)
  s+=ellipse(x,17.6,4.35,4.7,'url(#lens)','#7b929f',.4)
  s+=path(f'M{x-2.6} 15.4Q{x-1.3} 13.6 {x+.7} 13.8',stroke='#78b6c5',sw=.5,op=.6)
  s+=path(f'M{x-2.9} 19.7Q{x} 22.2 {x+3} 19.7',stroke='#0b3045',sw=.5)
  s+=path(f'M{x} 14v1M{x} 20.7v.7M{x-3.3} 17.6h.8M{x+2.5} 17.6h.7',stroke='#72a1b0',sw=.2,op=.65)
 for x,y in [(94.1,10.5),(124.1,10.5),(94.1,24.5),(124.1,24.5)]:s+=screw(x,y,.32)
 s+='</g>'
 # Base ring and floor. Glass supplied by shape 1901 remains a separate overlay.
 s+='<g id="lower-platform">'
 s+=path('M71.6 161.2Q108.8 143 149.1 160.8V178.7Q147.9 192.3 109.1 192.3Q71.6 191.9 71.6 178.7Z','url(#body)',sw=1.1)
 s+=ellipse(110.2,161.2,37.9,11.8,'#141c23','#0a1016',.7)
 s+=ellipse(110.3,161.5,34.4,9.65,'url(#floor)','#7b858c',.55)
 s+=path('M76.2 161.3H144.6M110.3 151.9V171',stroke='#333d43',sw=.65)
 s+=path('M77 160.5H109.3M111.1 160.5H143.5M109.6 152.3V160.5M109.6 162.3V170.2',stroke='#edf2ef',sw=.27,op=.7)
 s+=path('M73.3 162Q109.5 184.1 148.3 162',stroke='#929ba1',sw=.65)
 s+=path('M73 165.7Q109.4 185.3 148.6 165.2',stroke='#242c33',sw=.55)
 s+=path('M72.9 178Q73.4 189.7 109.5 190.5Q145.8 190.5 147.9 178.6',stroke='#a5adb2',sw=.35,op=.55)
 # Narrow right-side metal panels make cylinder volume clear.
 s+=path('M135.3 169.4V188.6M142.6 166.8V185.7',stroke='#172129',sw=.85)
 s+=path('M136.2 169.8V187.9M143.3 167.4V184.9',stroke='#97a2a9',sw=.3,op=.6)
 # Three broad horizontal louvres preserve the original front vent.
 s+=rect(92.9,175.3,34.2,13.2,'#1a232b','#070d12',.8)
 s+=path('M93.5 175.8H126.6M93.5 175.8V187.7',stroke='#a2abb2',sw=.35,op=.65)
 for j in range(3):
  y=176.7+j*3.45
  s+=rect(94.5,y,30.9,2.2,'url(#edge)')
  s+=path(f'M94.6 {y+.25}H125.2',stroke='#87929a',sw=.28)
  s+=path(f'M94.6 {y+2.5}H125.2',stroke='#03080d',sw=.48)
 for x in [91.3,128.6]:
  for y in [176.2,187.1]:s+=screw(x,y,.4)
 s+='<g clip-path="url(#lowerface)" opacity=".24">'
 for x,y,w in [(80,177,4),(79,182,2),(84,186,4),(131,181,2),(146,173,2),(101,190,4)]:s+=path(f'M{x} {y}l{w} -.35',stroke='#b9c4ca',sw=.17)
 for j in range(180):
  x=rng.uniform(72,149);y=rng.uniform(165,193);w=rng.uniform(.15,1.35)
  s+=path(f'M{x:.3f} {y:.3f}l{w:.3f} {rng.uniform(-.15,.15):.3f}',stroke=rng.choice(['#c9d0d2','#111b24']),sw=rng.uniform(.08,.16),op=rng.uniform(.22,.5))
 s+='</g>'
 # Side clamps: sloped electronic brackets with inset dark faces.
 s+='<g id="left-glass-clamp">'
 s+=path('M62 145.5L68.2 143.6L72.4 154.8L74.9 166.6L70.6 166.1L61.1 162.4L60.2 147Z','url(#edge)',sw=.8)
 s+=path('M62.1 147.5L67.1 146.2L70.4 161.1L63.1 159.9Z','#101922','#84929c',.5)
 s+=path('M63.6 149L66.1 148.4L68.4 158.8L65.1 158.2Z','url(#dark)','#263b49',.35)
 s+=path('M61.8 146.7L62.9 161.6L70.8 164.1',stroke='#a3acb4',sw=.35,op=.65)
 s+=path('M70.5 161.5L74.5 168.7',stroke='#0b141e',sw=1.5)
 s+='</g><g id="right-glass-clamp">'
 s+=path('M150.2 143.6L157.9 145.7L156.5 162.6L148.2 166.4L145.8 165.1L147.5 153.4Z','url(#edge)',sw=.85)
 s+=path('M151.1 146.2L156 147.5L154.7 159.8L149 161.3Z','#0c1720','#8b9aa4',.5)
 s+=path('M151.9 148.3L154.6 149L153.7 158.1L150.4 159Z','url(#dark)','#2a3e4a',.35)
 s+=path('M150.4 145.4L148 163.4L155.8 160.8',stroke='#a2acb5',sw=.34,op=.6)
 s+=path('M148 162L145.7 167.8',stroke='#0b141c',sw=1.4)
 s+='</g></g>'
 # Hose connection behind the independent control box.
 s+='<g id="control-hose">'
 s+=path('M43.8 167.9L56.6 170L70.4 170.5Q76.8 171.9 76.5 179.1Q76.7 183 72.7 183.9L57.2 182.9L43.8 181.4Z','url(#dark)',sw=1.05)
 s+=path('M45.8 169.5L56.5 171.5L70.4 171.9Q74.2 173.2 74.9 176',stroke='#5b6672',sw=.45,op=.65)
 s+=path('M58.1 170.6V182.7M70.6 171.2V183.7',stroke='#080f17',sw=.75)
 s+=path('M58.8 171.1V182M71.3 172.1V183',stroke='#5a626c',sw=.28,op=.55)
 s+='</g>'
 # Separate console preserves the original open flip-up screen and red switch.
 s+='<g id="side-control-box">'
 s+=path('M.7 166.5L15 156.6L47.1 156.8L47.1 185.6L33 195H.7Z','url(#box)',sw=1.1)
 s+=path('M33 166.8L47.1 156.8V185.5L33 194.9Z','url(#dark)',sw=.8)
 s+=path('M.9 166.6L15 157H46.2L32.8 166.6Z','#4c5760',sw=.65)
 s+=path('M2 166H32.5L44.2 158',stroke='#909ba3',sw=.35,op=.7)
 s+=path('M1.4 167.8H31.8V193.8H1.4Z','url(#box)',sw=.45)
 s+=path('M2.2 169.4H10.3V176.3H2.2Z','#101b22','#89949b',.5)
 s+=rect(4,170.8,3.8,3.8,'#626c72','#080f15',.55)
 s+=rect(5,171.4,1.3,1.7,'#151e25')
 s+=path('M2.3 180.8H17.4V170.8H25.6V180.8H29.8V190.8H2.3Z','#19242b','#a3adb0',.65)
 s+=path('M3.8 182.2H19V172.3H23.9V182.2H28.5V189.4H3.8Z','#0a131b',sw=.45)
 s+=path('M5 183H16.4M5 187.6H16.3',stroke='#32454d',sw=.3,op=.7)
 s+=rect(20.2,174,2.7,7.6,'#323d43','#080d14',.4)
 s+=path('M20.1 181.1Q22 180.2 23.5 181.4L24.2 187Q22 190 19.6 187.5Z','url(#red)','#390d17',.45)
 s+=ellipse(21.8,183.1,1.55,1.7,'#c9263a','#731326',.3)
 s+=path('M21.3 181.9L21.2 184.1',stroke='#ed6971',sw=.4,op=.65)
 for x,y in [(2.2,168.2),(30.8,168.2),(2.2,192.3),(30.8,192.3)]:s+=screw(x,y,.4)
 s+=path('M34.6 168.3L45.5 161V184.6L34.6 191.7',stroke='#5e6b75',sw=.4,op=.6)
 # Accordion-style coupling is drawn on the console side in front of the hose.
 s+=ellipse(43.1,174.5,7.6,6.8,'#111b23','#050d14',.65)
 for j in range(7):
  x=37.7+j*1.35
  s+=path(f'M{x+1.4:.2f} 168.5Q{x-2.5:.2f} 173.6 {x+1.6:.2f} 180.5',stroke='#54626d',sw=.55)
  s+=path(f'M{x+2:.2f} 168.5Q{x-1.9:.2f} 173.6 {x+2.2:.2f} 180.5',stroke='#0a111a',sw=.55)
 # Tilted black screen retains visible hinge feet, bright bevel and empty display.
 s+=path('M14.7 147.6L40.3 147.4L37.9 159.9H12.9Z','#0b131b',sw=.85)
 s+=path('M15.9 148.9H38.7L36.9 158.5H14.5Z','#03090d','#525d66',.5)
 s+=path('M16.4 149.5L14.9 157.9M38 149.5L36.5 157.8',stroke='#8b969e',sw=.45,op=.65)
 s+=path('M18 150.1H36.5',stroke='#18212b',sw=.35)
 s+=path('M20.9 159.3H29.3V161.7H20.4Z','#7e8a92','#111b23',.45)
 s+=path('M21.4 160H28.8',stroke='#b2bdc2',sw=.25,op=.7)
 s+='</g>'
 return write_part(R/'parts/bitmap-1588.svg',[0,0,160,196],s)

def comparisons(ids):
 for i in ids:
  scale=5 if i==1588 else 9
  new=render(R/f'parts/bitmap-{i}.svg',160*scale if i==1588 else 52*scale,R/f'previews/culture-{i}-new.png')
  orig=Image.open(R/f'reference/{i}.png').convert('RGBA');b=Image.open(new).convert('RGBA');orig=orig.resize(b.size,Image.Resampling.NEAREST)
  out=Image.new('RGB',(b.width*2,b.height+34),'#566067');d=ImageDraw.Draw(out)
  for j,img in enumerate([orig,b]):
   # Checkerboard makes intentional transparency obvious.
   for x in range(0,b.width,24):
    for y in range(34,b.height+34,24):
     d.rectangle((j*b.width+x,y,j*b.width+x+23,y+23),fill='#c7cece' if (x//24+y//24)%2 else '#aab5b8')
   out.paste(img,(j*b.width,34),img);d.text((j*b.width+10,10),f'{i}: '+['ORIGINAL','NATIVE EDITABLE R1'][j],fill='white')
  out.save(R/f'previews/culture-{i}-original-new.png')

def glass_preview():
 node=json.load(open(A/'environment-original-nodes.json'))['nodes']['1901']
 native=re.sub(r'<clipPath.*?</g>','',node['svgInner'],count=1)
 root=ET.parse(R/'parts/bitmap-1588.svg').getroot();s=''.join(ET.tostring(e,encoding='unicode') for e in root)
 s+='<g id="unchanged-native-shape-1901-glass" transform="translate(80 98)">'+native+'</g>'
 p=write_part(R/'previews/culture-1901-glass-preview.svg',[0,0,160,196],s)
 render(p,800,R/'previews/culture-1901-glass-preview.png')


# Frozen native drum geometry from stage8 revision r6, now independently authored
# here. Original atlas 1902 and 1833 are byte-for-byte RGBA identical (verified).
# Only original ALPHA is read by the mask; no original RGB texture is retained.
import base64, io
import numpy as np
REF=R/'reference'
WH={1902:(52,89)}
def drum_path(d,fill,stroke=None,width=.5,extra=''):
 return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{width}"' if stroke else '')+f' {extra}/>'

def drum_line(d,c='#99a0a6',w=.4,o=1):
 return drum_path(d,'none',c,w,f'opacity="{o}" stroke-linecap="round" stroke-linejoin="round"')

def drum_rect(x,y,w,h,c,stroke=None,sw=.5,rx=0,extra=''):
 return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'

def drum_ell(x,y,rx,ry,c,stroke=None,sw=.5,extra=''):
 return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'

def drum_circle(x,y,r,c,stroke=None,sw=.5,extra=''):return drum_ell(x,y,r,r,c,stroke,sw,extra)

def drum_lg(id,stops,x2='0',y2='1',x1='0',y1='0'):
 return f'<linearGradient id="{id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</linearGradient>'

def drum_rg(id,stops,cx='.36',cy='.28',r='.74'):
 return f'<radialGradient id="{id}" cx="{cx}" cy="{cy}" r="{r}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</radialGradient>'

def drum_png_data(im):
 b=io.BytesIO();im.save(b,format='PNG');return base64.b64encode(b.getvalue()).decode()

def drum_original_mask(i):
 im=Image.open(REF/f'{i}.png').convert('RGBA');a=im.getchannel('A');white=Image.new('RGBA',im.size,'white');white.putalpha(a);w,h=im.size
 return f'<mask id="source-alpha-{i}" maskUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{h}" style="mask-type:alpha"><image x="0" y="0" width="{w}" height="{h}" href="data:image/png;base64,{drum_png_data(white)}"/></mask>'

def drum_grain(w,h,seed,strength=14):
 rng=np.random.default_rng(seed);ww,hh=w*3,h*3
 a=rng.normal(0,1,(hh,ww));b=np.array(Image.fromarray(rng.integers(0,255,(max(2,h//4),max(2,w//4)),dtype=np.uint8)).resize((ww,hh),Image.Resampling.BICUBIC))/255-.5
 rgb=np.where((a+b)[...,None]>0,np.array([192,202,208]),np.array([3,5,8]));alpha=np.minimum(np.abs(a)*strength+np.abs(b)*strength,35).astype('uint8');im=Image.fromarray(np.dstack((np.broadcast_to(rgb,(hh,ww,3)),alpha)).astype('uint8'))
 return f'<image width="{w}" height="{h}" href="data:image/png;base64,{drum_png_data(im)}"/>'

def drum_coated(i,body,base='#101317'):
 w,h=WH[i];return '<defs>'+drum_original_mask(i)+'</defs>'+f'<g mask="url(#source-alpha-{i})">'+drum_rect(0,0,w,h,base)+body+'</g>'

def drum_drum():
 s='<defs>'+drum_lg('barrel',[(0,'#3d3010'),(.07,'#80601c'),(.21,'#a8822c'),(.48,'#927023'),(.76,'#7d5b17'),(.94,'#59400f'),(1,'#34260b')],'1','0')+drum_lg('rib',[(0,'#b69745'),(.25,'#8d6c22'),(.48,'#49370e'),(.7,'#76591b'),(1,'#b79b50')])+drum_rg('lid',[(0,'#c2a15a'),(.6,'#ae8b42'),(1,'#624912')],'.34','.25','.83')+drum_lg('rim',[(0,'#d0b36c'),(.27,'#a28034'),(.56,'#4f3b10'),(.8,'#786025'),(1,'#bd9f52')],'1','.7')+'</defs>'
 # Original cylinder is almost front-on: keep its shallow ellipse, round rim,
 # two raised bands and four narrow end ribs instead of a generic drum icon.
 s+=drum_path('M1 7.6Q2 1 26 0Q49 1 51 7.6L50.6 81.9Q49.6 88.2 26 88.8Q2.8 88.1 .8 82Z','url(#barrel)','#2c250d',.6)
 s+=drum_ell(26,82.4,25.1,6.2,'url(#rim)','#443711',.6)+drum_ell(26,80.8,24.9,5.6,'url(#barrel)','#4a3910',.45)
 s+=drum_path('M2 10Q25 15 49.6 9V80.6Q25.6 87.6 1.7 80.8Z','url(#barrel)')
 s+=drum_ell(26,6.6,25.1,5.3,'url(#rim)','#42320d',.6)+drum_ell(26,5.4,23.8,3.9,'url(#lid)','#594318',.55)
 s+=drum_line('M5.3 4.9Q24.3 -.6 45.2 4.6','#ddc48c',.6,.76)+drum_line('M5 7.1Q25 12.9 46.9 7.5','#6e531c',.55,.84)
 # Repeating formed steel ribs curve around the cylindrical shell.
 for y in [12.3,16.6,20.5,24.3,68.2,72.5,76.6,80.3]:
  s+=drum_path(f'M1.7 {y}Q25.5 {y+3.5} 50.1 {y-0.2}L50.1 {y+1.6}Q25.5 {y+5.0} 1.7 {y+1.8}Z','url(#rib)','#4a390f',.35)
  s+=drum_line(f'M2.6 {y+.3}Q25.6 {y+3.3} 49.3 {y+.1}','#b99b50',.45,.6)
 # Broad rolled hoops at original atlas y=30 and 62.
 for y in [29.2,61.9]:
  s+=drum_path(f'M.9 {y}Q25.5 {y+4.7} 50.8 {y-.2}L50.8 {y+2.6}Q25.5 {y+7.3} 1 {y+2.7}Z','url(#rim)','#47360e',.45)
  s+=drum_line(f'M1.6 {y+.15}Q25.5 {y+4.4} 50.1 {y-.05}','#d4b76f',.58,.75)
  s+=drum_line(f'M2 {y+2.75}Q26 {y+7} 50 {y+2.4}','#34270d',.6,.9)
 # Original two bung closures on top; ellipse perspective, no invented fittings.
 s+=drum_ell(34,3.2,5.3,1.9,'#3c3218','#8a763e',.4)+drum_path('M29.2 2.2H38.7V4.8Q34 7.1 29.2 4.8Z','url(#rib)','#3d3216',.45)+drum_ell(34,2.3,4.7,1.45,'#b29b64','#5c4d2b',.45)+drum_line('M31 2.1H36.7','#d7c394',.35,.7)
 s+=drum_ell(11.2,8.8,3.1,1.5,'#382d12','#8f773a',.45)+drum_path('M8.9 8L13.6 8L14.1 10.5H8.5Z','url(#rim)','#4b3c19',.4)+drum_ell(11.2,7.9,2.4,1.05,'#b09a60','#574421',.4)
 # Pale triangle follows the original front-face registration and worn ink.
 s+=drum_path('M26 29.1L44 58.8L7.1 58.8Z','none','#c5b783',1.3,extra='stroke-linejoin="round" opacity=".79"')
 s+=drum_path('M26 32.9L40.9 57.2H10.3Z','none','#b7a571',.45,extra='opacity=".5"')
 # Biohazard trefoil: restrained, three open crescents around a small ring.
 s+='<g transform="translate(26 46.8) scale(.88) translate(-26 -46.8)" opacity=".76">'
 s+=drum_circle(26,46.8,4.0,'none','#c4b88e',.8)
 for a in [0,120,240]:
  s+=f'<g transform="rotate({a} 26 46.8)">'
  s+=drum_path('M23.0 35.2C17.7 37.0 18.7 44.1 23.8 45.8L25.0 43.2C20.9 42.8 20.2 38.3 23.0 35.2Z','#c5b88a')
  s+=drum_path('M29.0 35.2C34.3 37.0 33.3 44.1 28.2 45.8L27.0 43.2C31.1 42.8 31.8 38.3 29.0 35.2Z','#c5b88a')
  s+='</g>'
 s+=drum_circle(26,46.8,1.4,'#bfb68f')+'</g>'
 rng=np.random.default_rng(1833)
 for i in range(90):
  x=float(rng.uniform(4,49));y=float(rng.uniform(12,83));leng=float(rng.uniform(.2,2.2))
  s+=drum_line(f'M{x:.2f} {y:.2f}l{leng:.2f} {rng.uniform(-.2,.2):.2f}',rng.choice(['#e1c77d','#3f330f','#6c5317']),float(rng.uniform(.13,.32)),float(rng.uniform(.12,.34)))
 s+=f'<g opacity=".42">{drum_grain(52,89,1833,9)}</g>'
 s+=drum_line('M3.2 35V58M4.4 37V48','#c2a255',.35,.4)+drum_line('M48.6 36V59','#34290c',.6,.55)
 return drum_coated(1902,s,'#614a15')

def build_drum():
 return write_part(R/"parts/bitmap-1902.svg",[0,0,52,89],drum_drum())

if __name__=='__main__':
 build_shell();build_drum();comparisons([1588,1902]);glass_preview()
