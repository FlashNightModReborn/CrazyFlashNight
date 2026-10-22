#!/usr/bin/env python3
"""CF6 1742 R3: dense, shaded woven floral carpet.

Rebuild: python source/carpet_r3.py
Only writes carpet1742 and carpet-r3 named previews/QA. It never calls decor.py.
Reference: The Met, French Aubusson Carpet, 1814–30, accession 10.152.14,
https://www.metmuseum.org/art/collection/search/218949 (Public Domain).
The supplied reference photograph informs broad lobed foliage, petal value
steps, and subtle wool weave. Selected individual woven flower heads are manually cropped and recolored. It is
NOT the game's original rug or a claimed recovered historical design.
Ornament is editable SVG; named flower heads are tiny documented photo crops,
with deterministic material overprint across the entire rug.
Original bitmap contributes alpha/registration only, never visible RGB.
A 660x250 pattern is mapped ONCE into the original 901x145 asset footprint.
The game's existing .375396728515625 instance scale must remain unchanged.
"""
from pathlib import Path
from math import sin, cos, pi
import io, base64, random, json, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from scipy.ndimage import gaussian_filter
from svg_native import write_part, render

ROOT=Path(__file__).resolve().parent.parent
PRE=ROOT/'previews'; QA=ROOT/'qa'
for p in (PRE,QA): p.mkdir(exist_ok=True)

def path(d, fill='none', stroke=None, sw=None, other=''):
    a=f'<path d="{d}" fill="{fill}"'
    if stroke:a+=f' stroke="{stroke}"'
    if sw:a+=f' stroke-width="{sw}"'
    return a+' '+other+'/>'
def use(n,x=0,y=0,s=1,r=0,sx=None,sy=None,opacity=None):
    if sx is None:sx=s
    if sy is None:sy=s
    o='' if opacity is None else f' opacity="{opacity}"'
    return f'<use href="#{n}" transform="translate({x:.3f} {y:.3f}) rotate({r:.3f}) scale({sx:.3f} {sy:.3f})"{o}/>'
def ellipse(x,y,rx,ry,f,st=None,sw=.5,other=''):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{f}"'+(f' stroke="{st}" stroke-width="{sw}"' if st else '')+f' {other}/>'
def b64(im):
    f=io.BytesIO();im.save(f,format='PNG',optimize=True)
    return base64.b64encode(f.getvalue()).decode()
def gradient(n,colors,rad=False):
    tag='radialGradient' if rad else 'linearGradient'
    geom=' cx=".42" cy=".36" r=".72"' if rad else ' x1="0" y1="0" x2=".8" y2="1"'
    return f'<{tag} id="{n}"{geom}>'+''.join(f'<stop offset="{i/(len(colors)-1):.3f}" stop-color="{c}"/>' for i,c in enumerate(colors))+f'</{tag}>'

def leaf(n,cols):
    s=f'<g id="{n}">'
    # A curving serrated leaf body, with broad folded faces instead of line fill.
    d='M0 0 C-4-2-9-4-10-8 L-8.1-8.5 Q-13-11-11.4-15 L-9.6-14.6 Q-12-19-8-23 Q-7-19-4.8-17.9 Q-5.9-23-1.1-28 Q-1.5-22 1.4-20.2 Q3-24 7-25 Q4.5-20.9 6.2-18.6 Q11-19 12-15 Q8-16 6.3-13.6 Q10.5-12.9 10-9.3 Q6.3-10.4 4.5-7.5 Q6.5-5.3 4-2.2 Q2-3.3 0 0Z'
    s+=path(d,f'url(#{n}Fill)')
    s+=path('M0 0 C-2-5-3-12-1.1-28 C-4.6-20-5.1-13-3-8 C-8-10-9-12-11.4-15 C-8-8-3-6 0 0Z',cols[2],other='opacity=".85"')
    s+=path('M-.2-1 C-1.5-7-1.6-15-1.1-24 Q1-19 1.6-16 Q4-17 6.2-18.6 Q3.6-13.2.4-12 Q2.7-10 4.5-7.5 Q1.4-8-.2-1Z',cols[0],other='opacity=".75"')
    s+=path('M-1.5-4Q-4-8-8.1-8.5 M-2.4-10Q-5-14-9.6-14.6 M-.9-8Q2-10 6.5-11 M-.5-15Q2.2-19 6.3-21','none',cols[1],.55,other='opacity=".65"')
    return s+'</g>'

def make_rose(name,colors,seed):
    rng=random.Random(seed);s=f'<g id="{name}">'
    s+=ellipse(0,0,9,7.9,colors[-1])
    # Irregular overlapping cupped petals. Every ring has differently sized
    # lobes and a muted shadow beneath its rolled edge, not a flat icon outline.
    for ring,(count,r,sc) in enumerate([(8,4.9,1),(7,3.1,.78),(5,1.4,.53),(3,.55,.30)]):
        for i in range(count):
            a=i*360/count+rng.uniform(-12,12)+ring*31
            x=r*cos(a*pi/180);y=r*sin(a*pi/180)
            stretch=rng.uniform(.83,1.18)
            s+=f'<g transform="translate({x:.2f} {y:.2f}) rotate({a+90:.2f}) scale({sc*stretch:.3f} {sc:.3f})">'
            d='M-4.5 2 C-6.7-.4-6.9-3.7-3.8-5.2 C-2.1-7 1.8-5.7 4.1-4.8 C6.3-3.3 5.6-.5 3 1.7 C.8 3.5-1.6 2.5-4.5 2Z'
            s+=path(d,f'url(#{name}Petal)')
            s+=path('M-4.5 2 C-1.2.4 1.6.6 3 1.7 C.8 3.5-1.6 2.5-4.5 2Z',colors[-1],other='opacity=".65"')
            s+=path('M-5-3.1 Q-4.4-5.7-2.1-5.6 Q.8-5.2 3.8-4.6 L3.2-3.9 Q-.4-4.9-2.3-4.8 Q-4.3-4.9-5-3.1Z',colors[0],other='opacity=".88"')
            s+=path('M-3.6-3.9 Q-3.1-1.1-1 1 M1-4.6Q2.3-2.4 1.6-.3','none',colors[1],.35,other='opacity=".5"')
            s+='</g>'
    s+=path('M-1.4.7 Q-2.7-1.2-.3-1.9 Q2.2-1.2.8.3 Q-.5 1.1-.5-.3','none',colors[-1],.9)
    return s+'</g>'


# Crop centers/radii in the unmodified 956x1200 Met source. Only individual
# flower heads, not its green field or complete floral ring, enter the artwork.
PD_FLOWERS=[
 ('metCream',336,505,27,25),('metRose',389,479,25,24),
 ('metPink',570,483,24,26),('metWhite',624,558,26,23),
 ('metRed',578,709,27,26),('metBlush',366,711,26,24),
 ('metIvory',291,627,23,22),('metPeach',310,651,23,23),
 ('metBud',300,543,20,22),('metYellow',664,447,21,22),
]

def textile_flowers():
    src=Image.open(ROOT/'reference/open-art/met-aubusson-218949-PD.jpg').convert('RGB')
    out=''
    for j,(n,cx,cy,rx,ry) in enumerate(PD_FLOWERS):
        tile=src.crop((cx-rx,cy-ry,cx+rx,cy+ry))
        arr=np.array(tile).astype(float)
        # Restore the photograph's dark exposure without changing the weave.
        arr=np.clip((arr-55)*1.34+77,0,255)
        arr[:,:,2]=np.clip(arr[:,:,2]*1.04,0,255)
        red=np.maximum(arr[:,:,0]-arr[:,:,1]-8,0)
        arr[:,:,0]=np.clip(arr[:,:,0]+red*.32,0,255)
        arr[:,:,1]=np.clip(arr[:,:,1]-red*.10,0,255)
        if n in ('metCream','metWhite','metIvory'):
            arr=np.clip(arr+np.array([14,16,21]),0,255)
        if n=='metRed':
            core=np.maximum(arr[:,:,0]-arr[:,:,1]-20,0)
            arr=np.clip(arr-core[:,:,None]*np.array([.10,.38,.31]),0,255)
        rgba=Image.fromarray(arr.astype(np.uint8),'RGB').convert('RGBA')
        h,w=arr.shape[:2]; y,x=np.mgrid[:h,:w]
        theta=np.arctan2((y-ry)/ry,(x-rx)/rx)
        rad=np.sqrt(((x-rx)/rx)**2+((y-ry)/ry)**2)
        # Hand-selected petal extent with gentle lobed edge; an inner alpha
        # core preserves every dark petal fold, rather than keying shadows out.
        edge=.88+.035*np.sin(theta*7+j)+.025*np.cos(theta*11-j)
        mask=np.clip((edge-rad)*18,0,1)
        rgba.putalpha(Image.fromarray((mask*255).astype(np.uint8)))
        out+=f'<g id="{n}"><image x="-11" y="-11" width="22" height="22" preserveAspectRatio="none" href="data:image/png;base64,{b64(rgba)}"/></g>'
    return out

def motifs():
    s=textile_flowers()
    palettes={'goldLeaf':['#c9bd93','#a5986e','#726647'], 'sageLeaf':['#b8b28e','#81805d','#4d5038'], 'darkLeaf':['#959578','#646448','#3c412e']}
    for n,c in palettes.items():s+=gradient(n+'Fill',c)+leaf(n,c)
    flowers={'rose':['#d6ac8a','#b68160','#8d4f39','#513c29'],'cream':['#e6dcb6','#c4ba8c','#a09564','#625c3e'],'pink':['#dbb39b','#bd8e76','#90624c','#60432e'],'russet':['#c9a276','#ac7654','#81503c','#533b2c']}
    for i,(n,c) in enumerate(flowers.items()):s+=gradient(n+'Petal',c[:3])+make_rose(n,c,220+i)
    # Five fleshy bell petals for tiny secondary flowers.
    s+='<g id="smallFloret">'
    for j in range(5):
        s+=f'<g transform="rotate({j*72})">'+path('M0 0 C-3.2-1.3-3.7-4.2-1.1-5.4 C1.4-5.8 3-3.1 1.4-1Z','url(#creamPetal)')+'</g>'
    s+=ellipse(0,0,1.1,.9,'#8e653c')+ellipse(-.3,-.3,.4,.3,'#d9b979')+'</g>'
    # Solid, folded fan over a broad stem; repeated at variable scales.
    s+='<g id="goldSpray">'
    s+=path('M0 0 C11-3 18-12 30-10 C38-9 41-3 38 2 C35 8 29 6 31 2 C32-.6 35 .6 35 2','none','#76643f',3.3)
    s+=path('M0-.5 C11-3.5 18-12.5 30-10.5 C38-9.5 41-3.5 38 1.5 C35 7 29 5 31 1.5','none','#c7b47f',2.1)
    for x,y,sc,a in [(5,-2,.64,-65),(13,-7,.80,-45),(22,-10,.62,-10),(30,-9,.49,25),(9,-4,.55,115),(18,-9,.59,140),(27,-9,.42,175)]:s+=use('goldLeaf',x,y,sc,a)
    s+=path('M0-1 C12-5 17-12 27-11','none','#e1cea0',.65)
    s+='</g>'
    # An interlocking solid acanthus C-scroll, with open red pockets retained.
    s+='<g id="acanthusScroll">'
    s+=path('M0 0 C15-18 37-19 48-6 C57 6 48 22 35 20 C24 18 23 6 29 3 C37-2 44 7 38 11 C34 14 31 10 33 8','none','#665737',3.5)
    s+=path('M0-.3 C15-18.3 37-19.3 48-6.3 C57 5.7 48 21.7 35 19.7 C24 17.7 23 5.7 29 2.7 C37-2.3 44 6.7 38 10.7 C34 13.7 31 9.7 33 7.7','none','#ab996c',2.4)
    for x,y,sc,a in [(5,-6,.7,-70),(17,-14,.88,-46),(31,-16,.72,0),(44,-10,.63,50),(49,1,.51,85),(43,16,.6,140),(31,18,.5,210),(16,-12,.53,140),(29,-15,.46,175)]:s+=use('goldLeaf',x,y,sc,a)
    s+=use('goldLeaf',36,16,.51,-35)+use('goldLeaf',29,18,.44,-120)+use('smallFloret',36,7,.65,0)
    s+='</g>'
    # Low-contrast fine botanical web below the larger floral masses.
    s+='<g id="underVine">'+path('M-2 0 C3-5 8-5 12-1 S20 5 24-2 C28-9 34-5 36-1','none','#b59b6c',.48)
    for x,y,sc,a in [(2,-2,.24,-45),(9,-3,.25,50),(14,1,.21,135),(21,1,.26,40),(29,-5,.23,-15),(34,-3,.22,80)]:s+=use('goldLeaf',x,y,sc,a)
    s+='</g>'
    s+='<g id="bloomCluster">' 
    # Stem-linked dark leaves form a single asymmetrical flower group.
    for x,y,sc,a in [(-15,8,.76,-60),(-8,7,.8,-30),(2,10,.92,20),(13,6,.8,65),(22,5,.56,77),(-24,3,.58,-80),(-6,14,.7,150),(12,13,.7,135)]:s+=use('darkLeaf',x,y,sc,a)
    for n,x,y,sc,a in [('metCream',-13,-2,.64,-20),('metRose',1,-6,.80,15),('metWhite',15,1,.57,55),('metPeach',-1,9,.48,-30),('metBud',-22,5,.42,19),('smallFloret',26,7,.59,0),('smallFloret',-10,14,.57,15)]:s+=use(n,x,y,sc,a)
    s+='</g>'
    return s

def woven_surface():
    # Low amplitude wool shading: no coarse stains or photographic camouflage.
    rng=np.random.default_rng(174203)
    h,w=750,1980
    noise=rng.normal(0,1,(h,w)).astype(np.float32)
    row=gaussian_filter(rng.normal(0,1,(h,1)),sigma=(.45,0))*1.4
    col=gaussian_filter(rng.normal(0,1,(1,w)),sigma=(0,.5))*.65
    coarse=gaussian_filter(noise,6);coarse/=max(coarse.std(),.001)
    y,x=np.mgrid[:h,:w]
    weave=np.sin(y*pi)*.0 + np.cos(y*pi/3.6)*1.1 + np.cos(x*pi/1.4)*.35
    v=noise*.7+row+col+coarse*.30+weave
    alpha=np.minimum(32,np.abs(v)*4.2+1).astype(np.uint8)
    rgba=np.empty((h,w,4),np.uint8); pos=v>0
    for i,c in enumerate((232,218,182)):rgba[:,:,i]=np.where(pos,c,(39,30,24)[i])
    rgba[:,:,3]=alpha
    return Image.fromarray(rgba,'RGBA').quantize(colors=64,method=Image.Quantize.FASTOCTREE,dither=Image.Dither.NONE)

def carpet():
    original=Image.open(ROOT/'reference/bitmap-1742-original.png').convert('RGBA')
    a=Image.new('RGBA',original.size,(255,255,255,255));a.putalpha(original.getchannel('A'))
    defs=motifs()+gradient('woolRed',['#7b152a','#7f162a','#701126','#75132a'])+gradient('ivoryField',['#c4c29e','#d2c8a0','#b8b38d'])
    defs+=f'<mask id="nativeOriginalAlpha" maskUnits="userSpaceOnUse" x="0" y="0" width="901" height="145"><image width="901" height="145" href="data:image/png;base64,{b64(a)}"/></mask>'
    defs+='<clipPath id="flat"><path d="M0 0H660V250H0Z"/></clipPath>'
    outer='M101 43 C96 54 87 54 83 62 C80 67 84 72 75 77 C58 88 57 108 66 121 C59 134 60 151 76 161 C84 167 80 173 87 181 C91 188 100 187 104 197 C152 198 212 197 280 198 C302 198 313 210 332 207 C352 209 363 198 383 198 C447 197 505 199 555 197 C560 187 569 187 574 180 C579 174 576 167 584 161 C600 150 602 135 594 122 C601 109 599 92 585 80 C576 73 580 67 573 60 C567 54 560 54 555 43 C498 41 438 43 380 42 C359 43 350 32 331 34 C310 31 301 43 279 42 C217 42 158 42 101 43Z'
    defs+='<clipPath id="reserve">'+path(outer)+'</clipPath><clipPath id="ovalCenter"><ellipse cx="336" cy="124" rx="139" ry="43.4"/></clipPath>'
    s='<title>1742 R3 woven floral carpet</title><desc>Authored shaded floral vector ornament, documented individual woven flower-head crops from the Public Domain Met Aubusson reference, and subtle wool overprint. This is not an identification or recovery of the original pattern. Original transparency and native perspective registration are preserved.</desc><defs>'+defs+'</defs>'
    s+='<g id="original-alpha-registration" mask="url(#nativeOriginalAlpha)">'+path('M0 0H901V145H0Z','#76152a')+'<g id="single-native-projection" transform="matrix(1 0 .964 .58 0 0)" clip-path="url(#flat)">'
    s+='<g id="wool-ground">'+path('M0 0H660V250H0Z','url(#woolRed)')+'</g>'
    # Continuous gold binding and broad botanical edge braid.
    s+='<g id="gold-binding-and-solid-leaf-band">'
    for x,y,w,h,c,sw in [(15,7,630,235,'#5e4d32',3),(17,9,626,231,'#c9ba88',3.7),(20,11.8,620,225.4,'#8f7a50',2.5),(24,14,612,221,'#d0c393',2.9),(29,17.5,602,214,'#7c6b43',2),(31,19.5,598,210,'#bca976',.85)]:s+=path(f'M{x} {y}H{x+w}V{y+h}H{x}Z','none',c,sw)
    for side in (0,1):
        for i,x in enumerate(range(63,602,38)):
            y=25 if side==0 else 225
            s+=use('goldSpray',x if side==0 else 660-x,y,.54,0 if side==0 else 180,sy=.47 if side==0 else .47)
            if i%3==1:s+=use('goldSpray',x+13 if side==0 else 647-x,y-4 if side==0 else y+4,.42,180 if side==0 else 0,sy=.29,opacity=.7)
            if i%3==1:s+=use('smallFloret',x+5 if side==0 else 655-x,y+1.7 if side==0 else y-1.7,.55)
    for side in (0,1):
        for y in range(48,212,32):s+=use('goldSpray',24 if side==0 else 636,y,.55,90 if side==0 else -90,sy=.43)
    s+='</g>'
    s+='<g id="lobed-red-reserve">'+path(outer,'#79172a','#b5a373',4.1)+path(outer,'none','#d4c497',1.05)
    # Arrange flowing, connected masses along each half; no ring of tiny loops.
    s+='<g id="broad-acanthus-botanical-network" clip-path="url(#reserve)">'
    s+='<g id="low-contrast-leafy-undernetwork" opacity=".31">'
    rr=random.Random(7102)
    for row,y in enumerate(range(48,209,13)):
        for col,x in enumerate(range(67,598,29)):
            s+=use('underVine',x+(row%2)*13+rr.uniform(-3,3),y+rr.uniform(-2,2),rr.uniform(.70,.96),rr.uniform(-24,24)+(180 if row%2 else 0),sy=rr.uniform(.56,.78))
    s+='</g>' 
    for side in (0,1):
        tr='' if side==0 else ' transform="translate(660 250) rotate(180)"'
        s+=f'<g{tr}>'
        s+=path('M92 86 C117 52 162 60 194 65 C239 74 280 42 329 48 C374 46 425 73 467 65 C506 59 552 55 568 88','none','#a18e5c',2.1)
        for x,y,sc,rr in [(104,79,.83,-21),(164,67,.80,-5),(220,62,.74,-9),(276,53,.71,-2),(338,52,.74,4),(400,62,.76,7),(460,66,.82,8),(516,73,.83,28)]:
            s+=use('acanthusScroll',x,y,sc,rr,sy=sc*.77,opacity=.81)
            s+=use('goldSpray',x+17,y+4,.65,155+rr,sy=.58,opacity=.82)
        for x,y,sc,rr in [(112,94,.64,-42),(183,60,.5,-8),(261,56,.51,0),(404,56,.5,6),(477,62,.52,12),(551,93,.64,43)]:s+=use('bloomCluster',x,y,sc,rr)
        s+='</g>'
    # Layered folded leaves knit the side chambers into the fine ground.
    for x,y,sc,r in [(145,96,.82,30),(133,144,.84,-25),(176,80,.55,15),(174,170,.56,-16),(519,94,.81,145),(527,151,.82,199),(486,79,.56,168),(488,173,.56,198)]:
        s+=use('goldSpray',x,y,sc,r,sy=sc*.78)
        s+=use('metCream' if x%2 else 'metRose',x+5,y,.48,r)
    # End lobes curve around rather than cross the central oval.
    for x,y,sx,rr in [(99,127,.90,-55),(562,124,-.9,55)]:
        s+=use('acanthusScroll',x,y,1,rr,sx=sx,sy=.72)+use('bloomCluster',x+(-2 if x<300 else 2),y+.5,.67,10 if x<300 else -10)
    s+='</g></g>'
    # Ivory oval: original bounds and compressed native position retained.
    s+='<g id="ivory-central-oval">'
    for rx,ry,fill,st,sw in [(167,59.6,'#9b8758','#dbcd9d',1.6),(162,56.7,'#761c2c','#806d45',.9),(154,51.9,'#bba775','#d4c497',1.1),(147,47.6,'#cfc29a','#746742',1.1),(139,43.4,'url(#ivoryField)','#595b3f',1.15)]:s+=ellipse(336,124,rx,ry,fill,st,sw)
    # Alternating broad leaves/ribbon folds make the ornamental annulus legible.
    for i in range(58):
        t=2*pi*i/58; x=336+157.8*cos(t); y=124+54.2*sin(t)
        a=180*t/pi+90
        s+=use('goldLeaf',x,y,.35,a,sy=.25)+use('smallFloret',336+146*cos(t),124+47.7*sin(t),.15,a,opacity=.67)
    s+='<g id="dense-irregular-central-bouquet" clip-path="url(#ovalCenter)">'
    # A tapered, stem-connected silhouette with natural red/cream focal flowers.
    for d in ['M229 125 C264 117 298 118 336 131 C376 136 408 131 443 124','M258 126 Q283 97 313 104 Q338 111 365 94','M315 135 Q354 156 397 137','M302 125 Q330 97 350 109 Q381 114 405 101']:
        s+=path(d,'none','#68704b',1.1)
    rng=random.Random(9184)
    for i in range(57):
        x=rng.uniform(232,441); y=125+sin((x-231)/210*pi)*rng.uniform(-23,24)
        sc=rng.uniform(.29,.62);a=rng.uniform(-100,100)+(180 if i%4==0 else 0)
        s+=use('darkLeaf' if i%3 else 'sageLeaf',x,y,sc,a)
    # Varied scale, tilt, and half-open profile heads. Sparse branch tips
    # flank a warmer red nucleus; heads are not arranged as a rose grid.
    heads=[
      ('metIvory',242,124,.42,-45,.62),('metBud',253,114,.42,-25,.73),
      ('metCream',268,119,.75,20,.78),('metPeach',276,135,.48,-15,.63),
      ('metBlush',288,109,.63,60,.80),('metWhite',298,123,.94,-26,.75),
      ('metRose',315,108,.86,11,.82),('metRed',325,131,1.22,28,.88),
      ('metCream',339,116,.79,-22,.70),('metBud',343,140,.59,52,.58),
      ('metPink',351,101,.49,-8,.66),('metWhite',362,126,.91,7,.80),
      ('metRed',374,111,.78,36,.70),('metCream',385,137,.64,-30,.72),
      ('metRose',399,122,.66,12,.69),('metBlush',412,133,.43,-50,.55),
      ('metIvory',420,116,.44,52,.61),('metCream',437,125,.34,-8,.52),
      ('metBud',307,142,.43,32,.60),('metWhite',358,145,.43,60,.58),
      ('metPeach',283,122,.43,-50,.65),('metCream',328,99,.36,25,.58),
    ]
    for n,x,y,sc,a,flat in heads:s+=use(n,x,y,sc*1.29,a,sy=sc*flat*1.48)
    # Side-facing pale petals and small flowerlets articulate the silhouettes.
    for x,y,sc,a in [(233,121,.38,-32),(258,134,.4,10),(283,99,.36,-30),(299,101,.40,16),(349,92,.32,45),(390,107,.38,70),(405,110,.36,-20),(432,131,.3,20),(373,147,.35,0)]:s+=use('smallFloret',x,y,sc,a)
    s+='</g></g>'
    # Four corner plaques: circular flowers, surrounding folded acanthus leaves.
    s+='<g id="four-corner-flower-plaques">'
    for x,y,r in [(53,30,0),(607,30,90),(607,220,180),(53,220,270)]:
        s+=f'<g transform="translate({x} {y}) rotate({r})">'
        for xx,yy,sc,a in [(-17,-2,.82,-66),(-7,-4,.82,-28),(7,-3,.83,27),(19,1,.80,67),(-18,9,.72,-113),(17,12,.73,111),(-7,18,.63,169)]:s+=use('goldLeaf',xx,yy,sc,a)
        s+=use('goldSpray',19,13,.72,15)+use('goldSpray',-18,3,.70,170)
        s+=ellipse(0,6,23.3,18.4,'#9a8d65','#dfcea0',2.3)+ellipse(0,6,20.7,15.6,'#d3c69c','#695f40',1.0)+ellipse(0,6,17.9,12.5,'#b2a879','#dfd2a7',1.1)
        for xx,yy,sc,a in [(-7,8,.45,-70),(10,10,.49,60),(3,12,.42,160)]:s+=use('darkLeaf',xx,yy,sc,a)
        for j in range(12):
            a=j*pi/6;s+=use('goldLeaf',14*cos(a),6+10.5*sin(a),.36,j*30+80,sy=.26)
        s+=use('metRose',0,6,.82,-17,sy=.65)+use('metCream',-10,8,.39,25)+use('metWhite',10,7,.36,13)
        s+='</g>'
    s+='</g>'
    # Wool is overprinted across all colors, unifying flowers with the ground.
    s+='<g id="subtle-wool-fibres-and-wear"><image x="0" y="0" width="660" height="250" preserveAspectRatio="none" href="data:image/png;base64,'+b64(woven_surface())+'"/>'
    rng=random.Random(10342)
    for i in range(1300):
        x=rng.uniform(2,658);y=rng.uniform(2,248);length=rng.uniform(.25,1.9)
        s+=path(f'M{x:.2f} {y:.2f}l{length:.2f} 0','none','#e8d9ac' if i%3 else '#34281e',rng.uniform(.07,.16),other='opacity=".15"')
    s+='</g></g></g>'
    return write_part(ROOT/'parts/bitmap-1742.svg',[0,0,901,145],s)

def board(rows,path,width=1802):
    height=145*width//901
    out=Image.new('RGB',(width,height*len(rows)+30*len(rows)),'#252521');d=ImageDraw.Draw(out)
    for i,(name,im) in enumerate(rows):
        y=i*(height+30);d.text((10,y+8),name,fill='#ede5d5')
        im=im.convert('RGBA').resize((width,height),Image.Resampling.LANCZOS)
        out.paste(im,(0,y+30),im)
    out.save(path)

def preview(p):
    for scale in (1,3,4):render(p,901*scale,PRE/f'carpet-r3-{scale}x.png')
    old=ROOT/'reference/r2-1742.svg'
    for scale in (1,3):render(old,901*scale,PRE/f'carpet-r2-{scale}x.png')
    orig=Image.open(ROOT/'reference/bitmap-1742-original.png').convert('RGBA')
    r2=Image.open(PRE/'carpet-r2-1x.png').convert('RGBA');r3=Image.open(PRE/'carpet-r3-1x.png').convert('RGBA')
    board([('ORIGINAL | native 901 x 145',orig),('FROZEN R2 | native 901 x 145',r2),('R3 | native 901 x 145',r3)],PRE/'carpet-r3-native-original-r2-r3.png',901)
    board([('ORIGINAL | source enlarged',orig),('FROZEN R2 | vector rendered at 3x',Image.open(PRE/'carpet-r2-3x.png')),('R3 | vector rendered at 3x',Image.open(PRE/'carpet-r3-3x.png'))],PRE/'carpet-r3-original-r2-r3-3x.png',2703)
    # Same registered region and same enlargement in every column.
    boxes=[('CENTER',(270,32,630,113)),('LEFT CORNER / LEAF BAND',(20,0,310,143)),('RIGHT RED RESERVE',(540,35,760,121))]
    crops=Image.new('RGB',(1800,1100),'#252521');draw=ImageDraw.Draw(crops)
    ims=[orig.resize((2703,435),Image.Resampling.NEAREST),Image.open(PRE/'carpet-r2-3x.png').convert('RGBA'),Image.open(PRE/'carpet-r3-3x.png').convert('RGBA')]
    for ri,(label,box) in enumerate(boxes):
        for ci,im in enumerate(ims):
            crop=im.crop(tuple(v*3 for v in box))
            crop.thumbnail((580,310),Image.Resampling.LANCZOS)
            x=ci*600+10;y=ri*365+35
            draw.text((x,ri*365+12),['ORIGINAL','R2','R3'][ci]+' / '+label,fill='white')
            crops.paste(crop,(x,y),crop)
    crops.save(PRE/'carpet-r3-same-scale-details.png')
    a=np.array(orig.getchannel('A')).astype(int);b=np.array(r3.getchannel('A')).astype(int)
    qa={'asset':1742,'revision':'R3','native_size':[901,145],'projection':'single authored-flat-to-native matrix(1 0 .964 .58 0 0); game instance remains scale .375396728515625','original_rgb_used':False,'reference':'The Met, French Aubusson Carpet 1814–30, 10.152.14, Public Domain. Selected individual floral heads cropped and recolored; no green field or complete flower ring copied; not the game original.','reference_url':'https://www.metmuseum.org/art/collection/search/218949','pd_flower_crops':PD_FLOWERS,'method':'Documented individual Met woven flower crops mixed with individually shaded irregular petal rings, connected broad acanthus, dense asymmetrical center clusters and dark leaf pockets, deterministic low-contrast woven overprint. Editable SVG geometry plus generated RGBA material overprint.','alpha_max_absolute_error':int(np.max(abs(a-b))),'original_alpha_pixels':int(np.count_nonzero(a)),'new_alpha_pixels':int(np.count_nonzero(b)),'original_reference_sha256':hashlib.sha256((ROOT/'reference/bitmap-1742-original.png').read_bytes()).hexdigest(),'pd_reference_sha256':hashlib.sha256((ROOT/'reference/open-art/met-aubusson-218949-PD.jpg').read_bytes()).hexdigest(),'scope':'Only carpet 1742. Painting 1743 and statue files untouched by this generator.'}
    (QA/'carpet-r3-construction.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2))
    print(json.dumps(qa,ensure_ascii=False,indent=2))

if __name__=='__main__':preview(carpet())
