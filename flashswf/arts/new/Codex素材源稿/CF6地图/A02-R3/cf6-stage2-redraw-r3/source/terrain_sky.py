from pathlib import Path
from PIL import Image,ImageDraw
import random,math
from svg_native import write_part,render
R=Path(__file__).resolve().parents[1]
def P(d,f,s=None,w=.5,op=1):return f'<path d="{d}" fill="{f}" opacity="{op}"'+(f' stroke="{s}" stroke-width="{w}"' if s else '')+'/>'
# Ground: editable light model/filter, not tens of thousands of tiny polygon noise facets.
s='''<defs><linearGradient id="soil" x2="0" y2="1"><stop stop-color="#15140e"/><stop offset=".3" stop-color="#3c3524"/><stop offset=".65" stop-color="#514730"/><stop offset="1" stop-color="#655438"/></linearGradient><filter id="gravel" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB"><feTurbulence type="fractalNoise" baseFrequency=".62 .71" numOctaves="3" seed="1611" stitchTiles="stitch" result="grain"/><feColorMatrix in="grain" type="matrix" values=".55 .55 .55 0 .04 .55 .55 .55 0 .04 .55 .55 .55 0 .04 0 0 0 0 1" result="grit"/><feComposite in="grit" in2="SourceGraphic" operator="arithmetic" k1="1.12" k2="0" k3=".05" k4="0" result="sand"/><feDiffuseLighting in="grain" surfaceScale=".48" diffuseConstant="1" lighting-color="#fff8df" result="relief"><feDistantLight azimuth="230" elevation="55"/></feDiffuseLighting><feComposite in="relief" in2="sand" operator="arithmetic" k1=".55" k2="0" k3=".52" k4="0"/></filter><radialGradient id="rut"><stop stop-color="#181b12" stop-opacity=".38"/><stop offset="1" stop-color="#181b12" stop-opacity="0"/></radialGradient><filter id="soft"><feGaussianBlur stdDeviation="3"/></filter></defs>'''
s+='<g filter="url(#gravel)">'+P('M0 0H324V300H0Z','url(#soil)')+'</g>'
for x,y,rx,ry in [(29,75,95,15),(196,151,110,20),(287,216,75,23),(58,265,120,18),(177,27,140,30)]:
 for shift in [-324,0,324]:s+=f'<ellipse cx="{x+shift}" cy="{y}" rx="{rx}" ry="{ry}" fill="url(#rut)"/>'
rng=random.Random(1611)
for _ in range(65):
 x=rng.uniform(0,324);y=rng.uniform(0,300);w=rng.uniform(4,17)
 s+=P(f'M{x:.1f} {y:.1f}q{w*.4:.1f} -1 {w:.1f} .4','none',rng.choice(['#827052','#252619','#655439']),rng.uniform(.3,.8),.18)
for _ in range(310):
 x=rng.uniform(0,324);y=rng.uniform(5,300);w=rng.uniform(.4,2.1);h=rng.uniform(.3,1.1)
 s+=P(f'M{x:.2f} {y:.2f}l{w*.4:.2f} {-h:.2f}l{w*.6:.2f} {h*.4:.2f}l{-w*.2:.2f} {h:.2f}Z',rng.choice(['#a18a60','#756445','#25271c','#48442f']),None,op=.3)
p=write_part(R/'parts/bitmap-1611.svg',[0,0,324,300],s);render(p,972,R/'previews/terrain-new.png')
# Five isolated metal fragments retain their original tiny footprint and perspective; never replace with generic round gravel.
im=Image.open(R/'reference/background/1610.png').convert('RGBA');alpha=im.getchannel('A');s=''
for d in ['M0 40L5 39L10 35L11 39L8 40L11 42L7 41L5 43L0 42Z','M103 0L109 2L108 4L105 3Z','M37 24L40 24L42 26L41 28L39 27Z','M69 52L73 53L77 55L73 55L72 57L69 56Z','M156 49L160 49L161 50L163 49L163 52L160 52L158 51L156 53Z']:
 s+=P(d,'#3f4742','#101815',.45)
s+=P('M0 41L5 41L10 37 M105 1L108 2 M38 25L40 26 M70 53L73 54 M157 50L160 50','none','#89918a',.4)
p=write_part(R/'parts/bitmap-1610.svg',[0,0,164,57],s);render(p,820,R/'previews/fragments-new.png')
# Distant skyline matches original per-column alpha contour, with independently editable building faces.
im=Image.open(R/'reference/background/1597.png').convert('RGBA');a=im.getchannel('A');tops=[]
for x in range(176):
 ys=[y for y in range(75) if a.getpixel((x,y))>120];tops.append(min(ys) if ys else 75)
d='M0 75L0 '+str(tops[0]);prev=tops[0]
for x,y in enumerate(tops[1:],1):
 if y!=prev:d+=f'H{x}V{y}';prev=y
d+='H176V75Z'
s='<defs><linearGradient id="city" x2="0" y2="1"><stop stop-color="#302619"/><stop offset=".45" stop-color="#443822"/><stop offset="1" stop-color="#171e19"/></linearGradient><clipPath id="buildings">'+P(d,'white')+'</clipPath></defs>'+P(d,'url(#city)')
s+='<g clip-path="url(#buildings)">'
for x,w in [(0,13),(19,12),(33,8),(51,6),(60,7),(72,8),(86,12),(101,10),(120,9),(136,8),(146,11),(164,11)]:
 y=min(tops[x:x+w]);s+=P(f'M{x} {y}h{w}V75h{-w}Z',rng.choice(['#3a2f20','#332d21','#403621','#25281e']),None,op=.65);s+=P(f'M{x+.4} {y+1}V74','none','#746143',.45,.35)
s+='</g>';p=write_part(R/'parts/bitmap-1597.svg',[0,0,176,75],s);render(p,880,R/'previews/city-new.png')
# Clouded gold-grey sky: large cloud bodies and rim light, no hard cell/noise tessellation.
s='''<defs><linearGradient id="sky" x2="0" y2="1"><stop stop-color="#6b6d69"/><stop offset=".38" stop-color="#a7a68d"/><stop offset=".72" stop-color="#e0d5a1"/><stop offset="1" stop-color="#eadba1"/></linearGradient><linearGradient id="cloud" x2="0" y2="1"><stop stop-color="#92937b"/><stop offset="1" stop-color="#696f61"/></linearGradient><filter id="cloudsoft" x="-.08" y="-.15" width="1.16" height="1.3"><feTurbulence baseFrequency=".035 .06" numOctaves="3" seed="18" result="noise"/><feDisplacementMap in="SourceGraphic" in2="noise" scale="10" xChannelSelector="R" yChannelSelector="G"/><feGaussianBlur stdDeviation="1.7"/></filter><radialGradient id="billow" cx=".32" cy=".2" r=".8"><stop stop-color="#d8d5b5"/><stop offset=".35" stop-color="#acb09a"/><stop offset=".7" stop-color="#959e8b"/><stop offset="1" stop-color="#7e8b79"/></radialGradient><filter id="haze" x="0" y="0" width="1" height="1"><feTurbulence baseFrequency=".012 .045" numOctaves="3" seed="1595"/><feColorMatrix type="matrix" values="0 0 0 0 .88 0 0 0 0 .87 0 0 0 0 .73  .2 0 0 0 0"/></filter></defs>'''
s+=P('M0 0H600V187H0Z','url(#sky)')+P('M0 0H600V187H0Z','#acac92') if False else P('M0 0H600V187H0Z','url(#sky)')
s+='<rect width="600" height="187" filter="url(#haze)" opacity=".45"/>'
s+='<g filter="url(#cloudsoft)">'
clouds=['M0 179Q5 168 13 171Q18 159 28 164Q32 151 43 157Q52 145 65 151Q73 138 84 147Q90 136 100 142Q112 129 125 143Q135 136 143 148Q151 143 161 156Q174 152 182 166L190 187H0Z','M429 187Q440 172 449 174Q451 158 465 162Q469 147 482 151Q479 137 489 131Q492 116 507 120Q513 109 525 120Q541 117 546 133Q558 133 560 149Q574 144 580 157Q591 151 600 164V187Z','M213 187Q217 176 227 180Q234 165 244 171Q255 158 267 171Q279 165 284 179Q296 173 305 187Z','M327 187Q332 175 344 176Q351 161 364 169Q375 167 384 183L390 187Z']
for j,d in enumerate(clouds):
 s+='<defs><clipPath id="cloudbody'+str(j)+'">'+P(d,'white')+'</clipPath></defs>'
 s+=P(d,'url(#cloud)','#ece0ad',1.3,.9)
 s+='<g clip-path="url(#cloudbody'+str(j)+')">'
 boxes=[(0,130,185,187),(430,114,600,187),(213,160,305,187),(327,163,390,187)]
 x0,y0,x1,y1=boxes[j]
 for _ in range(45 if j<2 else 14):
  x=rng.uniform(x0,x1);y=rng.uniform(y0,y1);rx=rng.uniform(5,16);ry=rx*rng.uniform(.6,1.1)
  s+=f'<ellipse cx="{x:.2f}" cy="{y:.2f}" rx="{rx:.2f}" ry="{ry:.2f}" fill="url(#billow)" opacity=".27"/>'
 s+='</g>' 
s+=P('M24 137Q19 124 26 116Q22 102 35 102Q47 102 50 111Q41 106 35 113Q31 125 37 133Z','#eee3b2',None,op=.65)
s+='</g>'
p=write_part(R/'parts/bitmap-1595.svg',[0,0,600,187],s);render(p,1200,R/'previews/sky-new.png')
# paired proof at shared dimensions
for cid,name in [(1611,'terrain'),(1597,'city'),(1595,'sky')]:
 old=Image.open(R/f'reference/background/{cid}.png').convert('RGBA');new=Image.open(R/f'previews/{name}-new.png').convert('RGBA');w=old.width*2;h=old.height*2;out=Image.new('RGB',(w*2,h+28),'#283029');dr=ImageDraw.Draw(out)
 for j,im in enumerate([old,new]):im=im.resize((w,h));out.paste(im,(w*j,28),im);dr.text((j*w+6,7),['Original','R1 layered vector/filter'][j],fill='white')
 out.save(R/f'previews/{name}-original-new.png')
