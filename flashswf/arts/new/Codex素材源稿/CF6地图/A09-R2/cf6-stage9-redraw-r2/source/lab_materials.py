"""a9 laboratory materials: hand-authored native SVG in original bitmap space.

Reconstructs 1446 fan grille, 1842 concrete floor, 1844 caution barrier and
1848 three-way security door. Geometry, seams and labels are authored here;
optional PNGs are newly generated deterministic grain, never sampled source RGB.
Original audit geometry is used only for registration, clipping and state QA.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
import math, json, re, io, base64, hashlib, sys
import numpy as np
from PIL import Image, ImageDraw
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from svg_native import write_part, render, inner
R=Path(__file__).resolve().parents[1]
AUDIT=R/'reference'
REV=sys.argv[1] if len(sys.argv)>1 else 'r2'
SIZES={1446:(57,57),1842:(231,70),1844:(87,114),1848:(131,161)}

def p(d,fill,stroke=None,sw=.5,extra=''):
 return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'
def ln(d,c='#969ca4',w=.4,o=1):return p(d,'none',c,w,f'opacity="{o}" stroke-linecap="round" stroke-linejoin="round"')
def rect(x,y,w,h,c,stroke=None,sw=.5,extra=''):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'
def circ(x,y,r,c,stroke=None,sw=.5,extra=''):return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'
def bolt(x,y,r=.45):return circ(x+.12,y+.14,r+.15,'#15181c')+circ(x,y,r,'#62676d')+ln(f'M{x-r*.5} {y-r*.3}l{r} .1','#b4b8bd',.16,.65)
def grad(id,stops,x2=0,y2=1):return f'<linearGradient id="{id}" x2="{x2}" y2="{y2}">'+''.join(f'<stop offset="{i}" stop-color="{c}"/>' for i,c in stops)+'</linearGradient>'
def texture(w,h,seed,base=(100,103,110),amp=6,scale=3):
 """New multiscale mineral/paint noise. No source file is read here."""
 rng=np.random.default_rng(seed);W,H=int(w*scale),int(h*scale)
 noise=np.zeros((H,W))
 for pitch,weight in ([(2,.65),(5,.60),(12,.32),(30,.15)] if seed==1842 else [(2,.35),(5,.48),(14,.50),(33,.42),(80,.25)]):
  a=rng.integers(0,256,(max(2,H//pitch),max(2,W//pitch)),dtype=np.uint8)
  q=np.asarray(Image.fromarray(a).resize((W,H),Image.Resampling.BICUBIC)).astype(float)
  noise+=(q-127.5)/45*weight
 noise+=rng.normal(0,.40,(H,W))
 a=np.clip(np.array(base)[None,None,:]+noise[:,:,None]*amp,0,255).astype('uint8')
 b=io.BytesIO();Image.fromarray(a).save(b,format='PNG')
 return f'<image width="{w}" height="{h}" href="data:image/png;base64,{base64.b64encode(b.getvalue()).decode()}"/>'
def grain(w,h,seed,opacity=.25):return f'<g opacity="{opacity}">'+texture(w,h,seed,(110,113,119),10)+'</g>'
def outlined_text(text,x,y,w,h):
 font=TTFont(str(R/'reference/fonts/DejaVuSans-BoldOblique.ttf'));gs=font.getGlyphSet();cm=font.getBestCmap();cur=0;v=[]
 for c in text:
  gl=gs[cm[ord(c)]];pen=SVGPathPen(gs);gl.draw(pen);v.append(f'<path transform="translate({cur} 0)" d="{pen.getCommands()}"/>');cur+=gl.width
 return f'<g transform="translate({x} {y+h}) scale({w/cur} {-h/1493})" fill="#181a1c" stroke="#b7babd" stroke-width="225" paint-order="stroke fill" stroke-linejoin="round">'+''.join(v)+'</g>'

def fan():
 # Central opening and mesh remain translucent so original rotating blades show.
 ring='M0 0H57V57H0Z M28.3 8.2A20.15 20.15 0 1 0 28.3 48.5A20.15 20.15 0 1 0 28.3 8.2Z'
 s='<defs>'+grad('panel',[(0,'#2b3236'),(.14,'#12191c'),(.6,'#1c2225'),(1,'#11171a')])+grad('rim',[(0,'#080c0e'),(.54,'#30383c'),(1,'#596065')])+f'<clipPath id="panelClip">{p(ring,"white",extra="fill-rule=\"evenodd\"")}</clipPath><clipPath id="meshClip">'+p('M28.3 9.5A18.85 18.85 0 1 0 28.3 47.2A18.85 18.85 0 1 0 28.3 9.5Z M28.3 24.45A3.9 3.9 0 1 1 28.3 32.25A3.9 3.9 0 1 1 28.3 24.45Z','white',extra='clip-rule="evenodd"')+'</clipPath></defs>'
 s+=p(ring,'url(#panel)',extra='fill-rule="evenodd"')+'<g clip-path="url(#panelClip)">'+grain(57,57,1446,.13)+'</g>'
 s+=ln('M.6 .8H56.1V55.5','#8e9699',.6,.52)+ln('M.4 56.4H56.6V.5','#070b0e',1.2,1)+ln('M1.1 1.8V54.5','#4b5459',.65,.5)
 s+=circ(28.3,28.35,21.6,'none','#0a0d10',1.1)+circ(28.3,28.35,20.5,'none','url(#rim)',1.4)+circ(28.3,28.35,19.25,'none','#0a0f12',.85)
 s+='<g clip-path="url(#meshClip)" opacity=".70"><g transform="rotate(10 28.3 28.35)">'
 for q in np.arange(-5,65,1.95):
  s+=ln(f'M{q:.3f} -8V65','#060d11',.78,.9)+ln(f'M{q+.26:.3f} -8V65','#687177',.20,.58)
  s+=ln(f'M-8 {q:.3f}H65','#0b1216',.71,.86)+ln(f'M-8 {q+.24:.3f}H65','#6c7478',.21,.49)
 s+='</g></g>'+circ(28.3,28.35,4.0,'none','#0a0e12',.75)+circ(28.3,28.35,4.45,'none','#434b50',.28)
 # restrained edge wear, no invented screw heads on this simple stamped panel
 for d in ['M4 1h8','M46 1h7','M1 40v8','M42 56h7','M42.8 13.2l1.6 1.8','M15 43l2 1.3']:
  s+=ln(d,'#798185',.22,.28)
 return s

def floor():
 poly='M0 .2L161.55 .2L230.9 69.9L69.8 69.9Z'
 s='<defs><clipPath id="tileClip">'+p(poly,'white')+'</clipPath></defs>'
 s+='<g clip-path="url(#tileClip)">'+texture(231,70,1842,(117,121,133),5.4)+'</g>'
 s+=ln('M.7 .65L161.15 .65L230.0 69.2','#afb2b9',.55,.66)+ln('M.6 .85L70.1 69.5L230.6 69.5','#565c68',.55,.7)
 # Tiny wear and screw pits sit at the same four corner regions.
 for x,y in [(2.2,1.4),(160.7,1.4),(70.2,68.4),(228.7,68.4)]:
  s+=circ(x,y,.42,'#3f4651')+ln(f'M{x-.35} {y-.35}l.6 .05','#c0c2c7',.22,.82)
 rng=np.random.default_rng(18421)
 for _ in range(180):
  y=float(rng.uniform(2,68));x=float(rng.uniform(y+2,y+158))
  s+=ln(f'M{x:.2f} {y:.2f}l{rng.uniform(.25,2):.2f} {rng.uniform(-.3,.3):.2f}',['#c2c4ca','#545c67'][int(rng.integers(2))],float(rng.uniform(.10,.22)),float(rng.uniform(.10,.24)))
 return s

def barrier():
 # R2: both trestles are identical A frames in one perspective, with a single
 # rail seated through their crowns. Visual geometry only; registration is fixed.
 face='M11.9 3.5H23.8L34.2 50.6H26.1L18.3 18.4L8.8 50.6H.8Z'
 s='<defs>'+grad('iron',[(0,'#626568'),(.18,'#51565a'),(.55,'#42494c'),(1,'#343b3e')],1,.18)+grad('side',[(0,'#2e383d'),(.5,'#202b31'),(1,'#162127')],1,0)+grad('top',[(0,'#939b9e'),(.36,'#6b777c'),(1,'#435058')],.2,1)+grad('warning',[(0,'#d5c344'),(.3,'#c7b838'),(.75,'#b3a52c'),(1,'#cfbd39')],.4,1)+grad('railMetal',[(0,'#858d89'),(.25,'#59635e'),(.7,'#313d38'),(1,'#1c2926')],.4,1)+'</defs>'
 def stand(dx,dy,tag):
  # Far faces retreat along the rail's own 48.5:62 depth axis. This avoids
  # the incompatible side-face perspective present in both source and R1.
  q=f'<g id="{tag}" transform="translate({dx+3.2} {dy+.8})">'
  verts=[(11.9,3.5),(23.8,3.5),(34.2,50.6),(26.1,50.6),(18.3,18.4),(8.8,50.6),(.8,50.6)]
  back=lambda x,y:(x-3.05,y-3.9)
  q+='<g transform="translate(-3.05 -3.9)">'+p(face,'url(#side)','#17242a',.5)+'</g>'
  for i,(x,y) in enumerate(verts):
   xx,yy=verts[(i+1)%len(verts)];bx,by=back(x,y);bxx,byy=back(xx,yy)
   dd=f'M{x} {y}L{xx} {yy}L{bxx} {byy}L{bx} {by}Z'
   q+=p(dd,'url(#top)' if i in [0] else 'url(#side)','#1e2c2c',.35)
  q+=p(face,'url(#iron)','#252e32',.55)
  q+=f'<defs><clipPath id="{tag}-face-grain">'+p(face,'white')+'</clipPath></defs>'+f'<g clip-path="url(#{tag}-face-grain)">'+grain(38,52,1844,.16)+'</g>'
  # True cross-tie: front, top and end planes use that same depth vector.
  q+=p('M5.7 40.5L2.65 36.6H25.05L28.1 40.5Z','url(#top)','#303936',.38)
  q+=p('M5.7 40.5L2.65 36.6L1.55 40.3L4.6 44.2Z','url(#side)','#24322e',.35)
  q+=p('M5.7 40.5H28.1L29.1 44.2H4.6Z','url(#iron)','#28332e',.5)
  q+=ln('M12.5 4.1H23.2M12.5 4.1L1.7 49.8M6.2 41.1H27.5','#949da1',.36,.52)
  q+=ln('M24.2 5L34 49.9M27.1 49.8H33.4M1.8 50H8.1','#141f1e',.42,.65)
  # The crown carries a flush sleeve; the rail seats into its rear side.
  q+=p('M15.2 9.3H21.2L23 17.3H13.4Z','#242e2c','#151f20',.45)
  q+=p('M16 10H20.5L21.5 15.7H14.6Z','#757e82','#939b9e',.28)
  q+=ln('M15.1 16.3H21.5','#111b1c',.55,.9)+ln('M16.2 11.7H20.5M15.7 13.7H20.8','#b1babd',.25,.4)
  for x,y in [(14.1,6.3),(22,6.3),(7,42.5),(26.4,42.5),(4.1,48.3),(30,48.3)]:q+=bolt(x,y,.32)
  for d in ['M12.4 12l-.6 2.4','M10.2 23l-.5 1.9','M25.1 25l.6 2.3','M30.4 45l.5 1.5','M14.7 4.5h3.2','M7.8 41.6h2.7']:
   q+=ln(d,'#a0a6a9',.19,.37)
  q+='</g>'
  return q
 s+=stand(0,0,'far-A-frame')
 # One rectangular rail prism; endpoints share the two crown fixing centers.
 s+=p('M23.5 12.7L25.8 11.3L74.3 73.3L72 74.7Z','url(#railMetal)','#182523',.55)
 s+=p('M23.5 12.7L72 74.7L69 78.5L20.5 16.5Z','#0f1915','#101d18',.55)
 # Parametric stripes follow this rail face, rather than unrelated diagonals.
 def rp(u,v):return (23.5+48.5*u-3*v,12.7+62*u+3.8*v)
 for lo,hi in [(.02,.20),(.34,.51),(.65,.83)]:
  pts=[rp(lo,0),rp(hi,0),rp(hi-.055,1),rp(max(0,lo-.055),1)]
  s+=p('M'+'L'.join(f'{x:.3f} {y:.3f}' for x,y in pts)+'Z','url(#warning)')
 s+=ln('M23.9 12.8L72.2 74.5','#b3b9a6',.4,.6)+ln('M20.7 16.8L68.5 77.9','#070f0e',.55,.9)
 s+=stand(48.5,62,'near-A-frame')
 return s

def door():
 frame='M.3 26.2H116.9V160.7H.3Z M6.1 33.4V154.0H110.9V33.4Z'
 s='<defs>'+grad('door',[(0,'#707279'),(.12,'#777980'),(.43,'#85868b'),(.72,'#797b82'),(1,'#656a73')],1,.15)+grad('edge',[(0,'#2b2f37'),(.18,'#9398a1'),(.36,'#6d717a'),(.62,'#343841'),(1,'#1a1e25')],.15,1)+grad('sign',[(0,'#13161d'),(.63,'#151921'),(1,'#20232d')],.1,1)+f'<clipPath id="doorClip">{rect(6,33.3,105,120.7,"white")}</clipPath></defs>'
 # Top status screen and detachable side reader keep the original silhouette.
 s+=rect(19.3,.5,74.2,23.5,'#15191f','#080c12',.7)+rect(20.7,1.5,71.4,21.0,'#6a7079','#393e46',.45)+rect(22.0,2.7,68.7,18.6,'url(#sign)','#090c12',.7)+ln('M22.7 3.4H90.0','#5b626e',.3,.35)
 s+=rect(.2,26.1,116.7,134.8,'#242932','#151a21',.4)+p(frame,'url(#edge)',extra='fill-rule="evenodd"')
 s+=rect(5.2,32.4,106.9,122.8,'#20242d','#12171e',.7)
 s+=rect(6.1,33.4,104.8,120.6,'url(#door)','#3d424b',.5)
 s+='<g clip-path="url(#doorClip)">'+grain(131,161,1848,.16)
 # Broad soft brush variation and accumulated drip stains, not traced pixels.
 s+='<defs><filter id="dripBlur"><feGaussianBlur stdDeviation=".48"/></filter><linearGradient id="dripWash" x2="0" y2="1"><stop stop-color="#242a33" stop-opacity=".25"/><stop offset="1" stop-color="#30353e" stop-opacity="0"/></linearGradient></defs>'
 rng=np.random.default_rng(18480)
 s+='<g filter="url(#dripBlur)">'
 for y0,x0,x1 in [(34,7,110),(62,39,73),(111,39,73)]:
  for _ in range(60):
   x=float(rng.uniform(x0,x1));w=float(rng.uniform(.35,1.6));h=float(rng.uniform(3,24))
   s+=p(f'M{x:.2f} {y0}h{w:.2f}q.7 {h*.4:.2f} -.3 {h:.2f}l-.6 -1Z','url(#dripWash)')
 s+='</g>'
 s+='<defs><radialGradient id="doorWear" cx=".54" cy=".48" r=".7"><stop offset=".2" stop-color="#171e29" stop-opacity="0"/><stop offset=".72" stop-color="#171e29" stop-opacity=".02"/><stop offset="1" stop-color="#171e29" stop-opacity=".27"/></radialGradient></defs>'+rect(6.1,33.4,104.8,120.6,'url(#doorWear)')
 s+='</g>'
 # These plate seams align to the exact three-way animation split coordinates.
 seams=['M38.5 33.3V154','M74.1 33.3V154','M38.5 61.5H74.1','M6.3 67.5H22.6V73.6H38.5','M38.5 109.9H74.1','M38.5 113H74.1','M6.3 128.7H38.5','M74.1 132.0H110.7','M38.5 140.3H74.1']
 for d in seams:s+=ln(d,'#30353d',.72,.93)
 for d in ['M39.2 34V153','M74.8 34V153','M39 62.3H73.5','M7 68.3H21.8V74.4H37.9','M39 114H73.5','M7 129.5H38','M75 132.8H110','M39 141.1H73.5']:
  s+=ln(d,'#b0b3b9',.30,.55)
 # Small original plate latch immediately under the upper central seam.
 s+=rect(40.5,63.2,11.0,3.0,'#353c47','#454c55',.35)
 for x,w in [(41.1,1.7),(43.5,2.0),(46.3,3.7)]:s+=rect(x,63.8,w,1.9,'#9a9fa8','#2c3540',.35)
 # Bold slanted C.T is rebuilt from editable outlines, keeping original typography layout.
 ct='M48.0 82.4H29.5Q26.0 82.4 24.1 85.6L20.9 91.2L20.5 105.0H41.8L43.0 102.2H28.6V93.5L31.2 87.1H47.0Q49.6 87.1 49.7 85Q49.9 83.3 48.0 82.4Z M56.0 97.7H61.8L60.4 103.8H54.3Z M75.3 82.5H98.1Q100 82.5 99.4 84.9L98.6 87.0H88.5L81.2 105.0H73.6L80.2 87.0H72.6Z'
 s+=p(ct,'#171a1e','#b7bac0',2.1,'paint-order="stroke fill" stroke-linejoin="round"')
 # KEEP OUT is outlined, so it needs no external font at delivery time.
 s+=outlined_text('KEEP OUT',18.9,115.4,76.5,8.6)
 # Hairline abrasion catches light on the rubbed steel surface.
 for d in ['M8.2 42v8','M8 90v13','M11 149h10','M35.8 37v4','M40.8 66v7','M70.3 68v11','M77 37v7','M108 112v11','M101 151h6','M42 143h4','M64 136l2 -.4','M16 76l3 .4','M89 125l2 -.2']:
  s+=ln(d,'#c1c3c5',.21,.23)
 # Ink wear is authored as restrained short marks confined to known letter interiors.
 for d in ['M24 97.5l.5 -2','M29 84.7h2','M37 103h2','M81 97l.5 -1.4','M87 84.5h4','M57 99h1.1']:
  s+=ln(d,'#626871',.26,.5)
 s+=ln('M1.4 27.1H115.5V159.4H1.4Z','#a6acb6',.5,.57)+ln('M3.7 30.5H113.8V157.7H3.7Z','#1c222c',.8,.9)+ln('M6.4 153.4H110.3V34.3','#c1c3c6',.4,.3)
 s+=rect(120.4,81.6,10.0,15.8,'#12171e','#0b0f15',.6)+rect(121.6,82.6,7.7,13.5,'#5b626d','#2c333c',.5)+rect(122.6,83.7,5.6,1.6,'#11171d')
 s+=ln('M122.4 86.8H128.3M122.4 88.3H128.3M122.4 89.8H128.3','#90959e',.3,.42)+rect(123,91.0,4.6,3.9,'#696f77','#414954',.3)+ln('M121.7 96.2H129','#a3a7ac',.3,.55)
 return s

def comparison(cid,rev):
 orig=Image.open(AUDIT/f'bitmaps/{cid}.png').convert('RGBA');w,h=orig.size
 for scale in [1,4]:
  new=Image.open(R/f'review/bitmap-{cid}-{rev}-{scale}x.png').convert('RGBA')
  # Matching display scale on each side. New native 4x is not enlarged from 1x.
  origS=orig.resize((w*scale,h*scale),Image.Resampling.NEAREST)
  col=max(w,112);out=Image.new('RGBA',((col*2+36)*scale,(h+36)*scale),'#c9cdd1');d=ImageDraw.Draw(out)
  for j,im in enumerate([origS,new]):out.alpha_composite(im,((12+j*(col+12)+(col-w)//2)*scale,26*scale));d.text(((12+j*(col+12))*scale,6*scale),['ORIGINAL '+str(cid),rev.upper()+' NATIVE SVG'][j],fill='#222a33')
  out.convert('RGB').save(R/f'review/bitmap-{cid}-original-{rev}-{scale}x.png')

def main():
 for directory in ['parts','review','qa']: (R/directory).mkdir(exist_ok=True)
 for cid,fn in [(1446,fan),(1842,floor),(1844,barrier),(1848,door)]:
  wh=SIZES[cid];s=fn();f=write_part(R/f'parts/bitmap-{cid}.svg',[0,0,*wh],s)
  for scale in [1,4]:render(f,wh[0]*scale,R/f'review/bitmap-{cid}-{REV}-{scale}x.png')
  comparison(cid,REV)
  print('generated',cid,flush=True)
 evidence={'revision':REV,'method':'Hand-authored native SVG geometry and lettering; new deterministic multiscale grain only. Original RGB never enters art generation.','bitmap_sizes':SIZES,'fonts':'DejaVu Sans Bold Oblique outlines for KEEP OUT; C.T is custom editable path.','registration':'Top-left bitmap coordinates; original fill matrices and clip paths retained by assembler.','shape_ids':[1447,1843,1845,1849,1852,1853,1854,1855,1857,1858,1859,1860,1861],'door':{'sprite':1862,'frames':18,'distinct_display_states':13,'mask_shape':86,'mask_depth':2,'clip_depth':6},'outputs':{i:hashlib.sha256((R/f'parts/bitmap-{i}.svg').read_bytes()).hexdigest() for i in SIZES}}
 (R/f'qa/lab-materials-{REV}.json').write_text(json.dumps(evidence,indent=2,ensure_ascii=False))
if __name__=='__main__':main()
