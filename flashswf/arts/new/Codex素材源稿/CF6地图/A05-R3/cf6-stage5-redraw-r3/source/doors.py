"""Editable native-vector redraw of CF6 stage 3 door bitmaps 1708 and 1717.

All coordinates use the original bitmap pixels. No linked/embedded raster artwork.
The PNGs in ../reference are the independently rebuildable source references.
The grille's openings are genuine transparent canvas, never a black rectangle.
"""
from pathlib import Path
import argparse, random, shutil, sys
from xml.etree import ElementTree as ET
from PIL import Image, ImageDraw
from svg_native import write_part, render

ROOT = Path(__file__).resolve().parents[1]
PARTS, PREV, REF = (ROOT/p for p in ('parts', 'previews', 'reference'))
for p in (PARTS,PREV,REF): p.mkdir(exist_ok=True)
WOOD_PANELS = [(19.5,19.7,21.4,27.8), (63.0,19.7,24.5,27.8), (97.3,19.7,24.6,27.8),
               (19.5,59.4,21.4,45.8), (63.0,59.4,24.5,45.8), (97.3,59.4,24.6,45.8),
               (19.5,116.7,21.4,46.7), (63.0,116.7,24.5,46.7), (97.3,116.7,24.6,46.7)]
# Slight original down-right tilt is retained; x is the centre at top and foot.
BARS = [(4.7,4.9),(15.8,15.8),(27.5,26.6),(39.0,38.2),(50.7,49.6),
        (62.4,61.3),(74.2,73.0),(85.8,85.0),(97.3,97.1)]


def rect(x,y,w,h,fill,extra=''):
    return f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" fill="{fill}" {extra}/>'
def path(d,fill='none',extra=''):
    return f'<path d="{d}" fill="{fill}" {extra}/>'
def poly(points,fill,extra=''):
    return '<polygon points="'+' '.join(f'{x:g},{y:g}' for x,y in points)+'" fill="'+fill+'" '+extra+'/>'
def group(id_,body,extra=''):
    return f'<g id="{id_}" {extra}>'+body+'</g>'
def line(x1,y1,x2,y2,color,width=1,extra=''):
    return path(f'M{x1:g} {y1:g}L{x2:g} {y2:g}',extra=f'stroke="{color}" stroke-width="{width:g}" {extra}')
def circle(x,y,r,fill,extra=''):
    return f'<circle cx="{x:g}" cy="{y:g}" r="{r:g}" fill="{fill}" {extra}/>'


def wood_shape():
    s=rect(.55,.55,141.7,177.8,'#25180f')
    s+=rect(1.55,1.25,5.7,175.6,'#795630')+rect(135.15,1.25,5.8,175.6,'#795630')
    s+=rect(7.5,1.25,127.2,9.7,'#795630')+rect(7.5,174.3,127.2,2.7,'#795630')
    s+=rect(9.5,11.75,124.0,161.9,'#78542c')
    s+=line(54.5,11.75,54.5,173.65,'#27180e',.9)
    for i,(x,y,w,h) in enumerate(WOOD_PANELS):
        s+=group(f'panel-{i+1}',rect(x,y,w,h,'#25180f')+rect(x+2.6,y+2.6,w-5.2,h-5.2,'#624526'))
    for x in (7.5,129.4):
        for y in (26.5,141.4):s+=rect(x,y,3.8,15.1,'#111515')+rect(x+1,y+1,1.8,13.1,'#8e9692')
    for x in (47.0,61.5):s+=circle(x,93.5,4.8,'#151818')+circle(x,93.5,3.3,'#444c47')
    s+=rect(32.7,91.9,14.3,3.3,'#2f3733')+rect(61.5,91.9,14.1,3.3,'#2f3733')
    s+=circle(61.5,111.5,4.8,'#141717')
    return s

def bar_x(index,y):
    top,bottom=BARS[index];return top+(bottom-top)*((y-8)/166)

def grille_shape():
    s=path('M.7 .65H100.2V178.2H.7ZM5.5 8.1V174H96.5V8.1Z','#bfc1bc',extra='fill-rule="evenodd"')
    for i in range(1,8):
        x1,x2=BARS[i];s+=line(x1,8.1,x2,174,'#a0a6a1',1.6)
    # The first and third motifs have their high tips on even bars; the middle
    # motif reverses them. This original phase difference is intentional.
    for row,(cy,half,phase) in enumerate(((37.5,11.6,0),(89.0,10.9,1),(142.3,11.3,0))):
        for sign in (-1,1):
            pts=[]
            for i in range(9):
                y=cy+sign*(half if (i+phase)%2==0 else 0)
                pts.append((bar_x(i,y),y))
            d='M'+'L'.join(f'{x:.3f} {y:.3f}' for x,y in pts)
            s+=path(d,extra='stroke="#aeb4ae" stroke-width="1.25" stroke-linejoin="round"')
    return s

def checker(size,cell=12):
    im=Image.new('RGBA',size,'#888b88');d=ImageDraw.Draw(im)
    for y in range(0,size[1],cell):
        for x in range(0,size[0],cell):
            if (x//cell+y//cell)%2:d.rectangle((x,y,x+cell-1,y+cell-1),fill='#b8bbb8')
    return im

def comparisons(stage):
    for n,w in ((1708,143),(1717,101)):
        orig=Image.open(REF/f'bitmap-{n}-original.png').convert('RGBA')
        new=Image.open(PREV/f'bitmap-{n}-{stage}.png').convert('RGBA')
        h=179;scale=4;W=w*scale;H=h*scale
        out=Image.new('RGB',(W*2+40,H+50),'#f4f2eb');d=ImageDraw.Draw(out)
        d.text((10,10),f'Original {n} | 4x original scale',fill='#262722')
        d.text((W+30,10),f'{stage} native SVG | same 4x scale',fill='#262722')
        for x,img in ((10,orig),(W+30,new)):
            img=img.resize((W,H),Image.Resampling.LANCZOS)
            bg=checker((W,H),16);bg.alpha_composite(img);out.paste(bg.convert('RGB'),(x,35))
        out.save(PREV/f'doors-{n}-{stage}-comparison.png')


def gradient(id_,stops,x1='0',y1='0',x2='0',y2='1',units='objectBoundingBox'):
    return f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" gradientUnits="{units}">'+''.join(f'<stop offset="{o}" stop-color="{c}"/>' for o,c in stops)+'</linearGradient>'


def wood_grain(x,y,w,h,seed, count=35, opacity=.27):
    """Long bent grain strokes and pore marks. All marks remain editable paths."""
    rng=random.Random(seed);out=[]
    for j in range(max(3,int(w/4))):
        xx=x+rng.uniform(.8,max(.9,w-.8));yy=y+rng.uniform(.5,max(.6,h*.18));end=y+h-.4
        bend=min(w*.10,rng.uniform(.5,1.6));sw=rng.uniform(.4,1.15)
        d=f'M{xx:.3f} {yy:.3f}C{xx+bend:.3f} {yy+(end-yy)*.3:.3f} {xx-bend:.3f} {yy+(end-yy)*.63:.3f} {xx+bend*.2:.3f} {end:.3f}'
        out.append(path(d,extra=f'stroke="#291709" stroke-width="{sw:.3f}" opacity="{opacity*.18:.3f}"'))
    for j in range(count):
        xx=x+rng.uniform(.4,w-.4);yy=y+rng.uniform(0,h*.35);length=rng.uniform(h*.2,h*.85)
        end=min(y+h-.4,yy+length);bend=rng.uniform(-.65,.65)
        d=f'M{xx:.3f} {yy:.3f}C{xx+bend:.3f} {yy+(end-yy)*.30:.3f} {xx-bend:.3f} {yy+(end-yy)*.67:.3f} {xx+bend*.35:.3f} {end:.3f}'
        color='#271708' if j%3 else '#c39b61'
        out.append(path(d,extra=f'stroke="{color}" stroke-width="{rng.uniform(.08,.27):.3f}" opacity="{opacity*rng.uniform(.4,1):.3f}"'))
    for j in range(max(8,int(w*h/45))):
        xx=x+rng.uniform(.2,w-.2);yy=y+rng.uniform(.3,h-.3)
        out.append(line(xx,yy,xx+rng.uniform(-.12,.12),min(y+h-.15,yy+rng.uniform(.15,.85)),'#20150c',rng.uniform(.06,.16),f'opacity="{opacity*.7:.3f}"'))
    # Sparse irregular grain loops make the boards read as wood rather than stripes.
    for j in range(max(1,int(w*h/850))):
        xx=x+rng.uniform(w*.25,w*.75);yy=y+rng.uniform(h*.15,h*.78);kw=min(w*.1,rng.uniform(.45,1.15));kh=min(rng.uniform(3,8.5),h*.21)
        out.append(path(f'M{xx:.3f} {yy-kh:.3f}C{xx+kw:.3f} {yy-kh*.4:.3f} {xx+kw:.3f} {yy+kh*.4:.3f} {xx:.3f} {yy+kh:.3f}C{xx-kw*.8:.3f} {yy+kh*.3:.3f} {xx-kw*.9:.3f} {yy-kh*.5:.3f} {xx:.3f} {yy-kh:.3f}',extra=f'stroke="#2a180a" stroke-width=".16" opacity="{opacity*.8:.3f}"'))
    return ''.join(out)


def original_wood_alpha():
    """Native edge-only mask preserves source alpha: wood has NO transparent hole.

    Only the 640 perimeter samples are needed; the 141x177 interior is opaque.
    Consecutive identical samples are emitted as editable SVG rectangles.
    """
    im=Image.open(REF/'bitmap-1708-original.png').convert('RGBA');a=im.getchannel('A')
    s=rect(1,1,141,177,'white')
    def runs(values,x,y,horizontal):
        out='';start=0
        while start<len(values):
            end=start+1
            while end<len(values) and values[end]==values[start]:end+=1
            out+=rect(x+start if horizontal else x,y if horizontal else y+start,end-start if horizontal else 1,1 if horizontal else end-start,'white',f'fill-opacity="{values[start]/255:.7f}"')
            start=end
        return out
    s+=runs([a.getpixel((x,0)) for x in range(143)],0,0,True)
    s+=runs([a.getpixel((x,178)) for x in range(143)],0,178,True)
    s+=runs([a.getpixel((0,y)) for y in range(1,178)],0,1,False)
    s+=runs([a.getpixel((142,y)) for y in range(1,178)],142,1,False)
    return '<mask id="original-wood-alpha" maskUnits="userSpaceOnUse" x="0" y="0" width="143" height="179" style="mask-type:alpha" shape-rendering="crispEdges">'+s+'</mask>'


def wood_panel(i,x,y,w,h):
    # Original proportions retained. Nested shapes are true wood moulding facets.
    s=rect(x-.35,y-.25,w+.7,h+.55,'#27180e')
    s+=rect(x,y,w,h,'url(#moulding-wood)')
    s+=poly([(x,y),(x+w,y),(x+w-1.1,y+1.1),(x+1.1,y+1.1)],'#412515')
    s+=poly([(x,y),(x+1.1,y+1.1),(x+1.1,y+h-1.1),(x,y+h)],'#422712')
    s+=poly([(x,y+h),(x+w,y+h),(x+w-1.1,y+h-1.1),(x+1.1,y+h-1.1)],'#967141')
    s+=poly([(x+w,y),(x+w,y+h),(x+w-1.1,y+h-1.1),(x+w-1.1,y+1.1)],'#7f5a32')
    s+=rect(x+1.2,y+1.2,w-2.4,h-2.4,'#24150b')
    s+=poly([(x+1.5,y+1.5),(x+w-1.5,y+1.5),(x+w-3.1,y+3.5),(x+3.1,y+3.5)],'#27180d')
    s+=poly([(x+1.5,y+1.5),(x+3.1,y+3.5),(x+3.1,y+h-3.1),(x+1.5,y+h-1.5)],'#301c0e')
    s+=poly([(x+1.5,y+h-1.5),(x+w-1.5,y+h-1.5),(x+w-3.1,y+h-3.1),(x+3.1,y+h-3.1)],'#6e4d29')
    s+=poly([(x+w-1.5,y+1.5),(x+w-1.5,y+h-1.5),(x+w-3.1,y+h-3.1),(x+w-3.1,y+3.5)],'#694822')
    s+=rect(x+3.1,y+3.5,w-6.2,h-6.6,'url(#panel-recess)')
    s+=wood_grain(x+3.3,y+3.8,w-6.6,h-7.1,3200+i,18,.28)
    s+=line(x+3.1,y+3.5,x+w-3.1,y+3.5,'#1d120a',.6,'opacity=".55"')
    s+=line(x+3.1,y+3.5,x+3.1,y+h-3.1,'#201208',.5,'opacity=".6"')
    s+=line(x+3.1,y+h-3.1,x+w-3.1,y+h-3.1,'#ac7d43',.22,'opacity=".58"')
    s+=line(x+1.05,y+h-1.05,x+w-1.05,y+h-1.05,'#b18a50',.18,'opacity=".5"')
    # Small chipped high spots on the thick frame, avoiding a uniform gold outline.
    for t in (.17,.68):
        s+=line(x+1.15,y+h*t,x+1.15,y+h*t+min(2.0,h*.09),'#bd9256',.18,'opacity=".38"')
    return group(f'wood-panel-{i+1}',s)


def hinge(i,x,y):
    s=rect(x-.25,y-.25,4.15,15.6,'#171811')
    s+=rect(x+.18,y+.3,3.2,14.6,'#353a32')
    s+=rect(x+.65,y+.7,2.35,13.8,'url(#iron-cross)')
    s+=line(x+.9,y+1.05,x+.9,y+13.9,'#c1c4af',.32,'opacity=".76"')
    s+=line(x+3.05,y+.7,x+3.05,y+14.5,'#131a17',.5)
    for yy in (y+1.3,y+13.8):
        s+=line(x+.6,yy,x+3.0,yy,'#222920',.3)
    return group(f'iron-hinge-{i}',s)


def handle(i,cx,cy,direction):
    s=circle(cx+.15,cy+.35,4.9,'#191a12')+circle(cx,cy,4.35,'url(#iron-ring)')
    s+=circle(cx,cy,3.25,'#20261f')+circle(cx-.1,cy-.12,2.65,'url(#iron-ring)')
    s+=circle(cx,cy,1.8,'#29322a')
    s+=path(f'M{cx-3.5:g} {cy+.9:g}A3.6 3.6 0 0 1 {cx+1.3:g} {cy-3.35:g}',extra='stroke="#a7ad98" stroke-width=".25" opacity=".8"')
    x=cx-14.25 if direction<0 else cx-.4;w=14.5
    s+=rect(x-.3,cy-1.9,w+.6,4.05,'#141a16',extra='rx=".5"')
    s+=rect(x,cy-1.65,w,3.25,'url(#handle-face)',extra='rx=".42"')
    s+=line(x+.6,cy-1.15,x+w-.7,cy-1.15,'#a1a78f',.25,'opacity=".75"')
    s+=line(x+.6,cy+1.3,x+w-.5,cy+1.3,'#111811',.5)
    s+=rect(cx-.6,cy-2.1,1.25,4.1,'url(#iron-cross)',extra='rx=".25"')
    for a in (-1,1):s+=circle(cx+a*2.75,cy+a*1.35,.25,'#111a13')
    return group(f'iron-handle-{i}',s)


def wood_art():
    defs=gradient('face-wood',[('0','#7d5b31'),('.45','#71502a'),('1','#614222')])
    defs+=gradient('frame-wood',[('0','#9b7643'),('.17','#7e592e'),('.63','#684820'),('1','#49301a')],x2='1',y2='0')
    defs+=gradient('top-wood',[('0','#9b7848'),('.3','#805b32'),('.68','#62411f'),('1','#302014')])
    defs+=gradient('moulding-wood',[('0','#81582f'),('.1','#594020'),('.8','#644523'),('1','#9a7342')])
    defs+=gradient('panel-recess',[('0','#4b321b'),('.12','#604225'),('.55','#6e4d29'),('1','#5c3d20')])
    defs+=gradient('iron-cross',[('0','#272e29'),('.16','#727b6c'),('.35','#b6baa4'),('.53','#7d8677'),('.80','#454f45'),('1','#1e2821')],x2='1',y2='0')
    defs+=gradient('iron-ring',[('0','#8f9582'),('.22','#4e594a'),('.58','#29352b'),('1','#141c16')])
    defs+=gradient('handle-face',[('0','#7e8773'),('.25','#606c5a'),('.55','#485643'),('1','#263427')])
    defs+=original_wood_alpha()
    s=rect(0,0,143,179,'#100c08')
    # Outer upright casings retain their independent board grain and original width.
    for i,(x,w) in enumerate(((1.2,6.2),(135.0,6.5))):
        s+=group(f'outer-upright-{i+1}',rect(x,.8,w,176.8,'url(#frame-wood)')+wood_grain(x+.3,1.1,w-.6,176.1,100+i,22,.25))
        s+=line(x+.45,1.3,x+.45,176.9,'#c49b62',.3,'opacity=".5"')
        s+=line(x+w-.25,1,x+w-.25,177.6,'#21160d',.5)
    s+=group('top-transom-board',rect(7.5,1.1,127.3,5.8,'url(#top-wood)')+line(8.0,1.8,134.3,1.8,'#bc965f',.4,'opacity=".45"')+line(8,5.9,134.6,5.9,'#352313',.55))
    for yy in (3.2,4.6):s+=path(f'M9 {yy}Q48 {yy-.25} 72 {yy+.1}T133 {yy}',extra='stroke="#372213" stroke-width=".15" opacity=".45"')
    s+=rect(7.5,7.0,127.3,4.25,'#322010')
    s+=rect(8.1,8.0,126.0,2.55,'url(#top-wood)')
    s+=line(8.1,8.05,134.1,8.05,'#9b7946',.35)
    s+=rect(8,11.1,127.1,163.4,'#25180d')
    s+=rect(9.7,11.65,124,162.2,'url(#face-wood)')
    s+=group('left-leaf-board-grain',wood_grain(10.0,12,43.8,161.5,1708,95,.24))
    s+=group('right-leaf-board-grain',wood_grain(55.2,12,78.0,161.5,1808,155,.24))
    s+=line(9.95,12.3,9.95,173.3,'#ab8046',.35,'opacity=".5"')
    s+=line(133.15,11.8,133.15,173.5,'#33210f',.65)
    s+=line(54.4,11.65,54.4,173.9,'#2a1b0e',1.05)
    s+=line(55.0,12,55.0,173.5,'#a57742',.30,'opacity=".7"')
    for i,p in enumerate(WOOD_PANELS):s+=wood_panel(i,*p)
    s+=rect(7.5,174.1,127.3,3.1,'url(#top-wood)')
    s+=line(8,174.65,134.3,174.65,'#ac8550',.3,'opacity=".6"')
    s+=line(7.5,177.3,135.1,177.3,'#160f0a',.8)
    for i,(x,y) in enumerate(((7.5,26.5),(7.5,141.4),(129.4,26.5),(129.4,141.4))):s+=hinge(i+1,x,y)
    s+=handle(1,47.0,93.5,-1)+handle(2,61.5,93.5,1)
    lock=circle(61.65,111.8,4.95,'#221d12')+circle(61.5,111.5,4.3,'url(#iron-ring)')+circle(61.5,111.5,3.15,'#181f18')+circle(61.5,111.5,2.3,'#323c2e')
    lock+=circle(61.35,110.8,.7,'#0a100c')+path('M60.95 111.1H61.75L62.0 113.4H60.65Z','#0a100c')
    lock+=path('M57.85 112.1A3.8 3.8 0 0 1 62.7 107.9',extra='stroke="#8e947e" stroke-width=".26" opacity=".65"')
    s+=group('keyhole-escutcheon',lock)
    return '<defs>'+defs+'</defs>'+group('bitmap-1708-wood-door',s,'mask="url(#original-wood-alpha)"')


def grille_art():
    defs=gradient('steel-height',[('0','#c8c8c8'),('.2','#a7a7a7'),('.48','#818181'),('.74','#a0a0a0'),('1','#656565')],x1='0',y1='0',x2='0',y2='179',units='userSpaceOnUse')
    defs+=gradient('steel-frame-top',[('0','#e1e1e1'),('.2','#bfbfbf'),('.55','#ababab'),('.8','#898989'),('1','#5a5a5a')])
    defs+=gradient('steel-side',[('0','#4a4a4a'),('.2','#9f9f9f'),('.4','#c9c9c9'),('.65','#8a8a8a'),('1','#474747')],x2='1',y2='0')
    defs+=gradient('steel-bottom',[('0','#a4a4a4'),('.3','#7a7a7a'),('1','#4b4b4b')])
    defs+=gradient('joint-metal',[('0','#d8d8d8'),('.35','#a4a4a4'),('1','#616161')])
    s=''
    # Original 0.7..100.2 outer footprint; the inner rectangle stays transparent.
    frame=path('M.7 .65H100.2V178.2H.7ZM5.5 8.1V174H96.5V8.1Z','#3d3d3d','fill-rule="evenodd"')
    frame+=rect(1.25,1.0,98.0,7.3,'url(#steel-frame-top)')
    frame+=rect(1.25,8.1,4.4,166.2,'url(#steel-side)')
    frame+=rect(96.0,8.1,3.25,166.2,'url(#steel-side)')
    frame+=rect(1.3,174.0,97.95,3.25,'url(#steel-bottom)')
    frame+=line(1.7,1.6,98.9,1.6,'#e9e9e9',.45,'opacity=".85"')
    frame+=line(2.0,3.3,98.5,3.3,'#e0e0e0',.24,'opacity=".4"')
    frame+=line(5.5,7.95,96.5,7.95,'#e3e3e3',.36,'opacity=".85"')
    frame+=line(5.3,8.4,5.3,173.8,'#5a5a5a',.5)
    frame+=line(1.9,8.5,1.9,173.6,'#d0d0d0',.4,'opacity=".62"')
    frame+=line(96.4,8.4,96.4,173.7,'#d7d7d7',.32,'opacity=".76"')
    frame+=line(99.15,1.3,99.15,177.2,'#333333',.45)
    frame+=line(5.4,174.4,96.6,174.4,'#c0c0c0',.35,'opacity=".75"')
    # Subtle small abrasion strokes are in the metal only, never the aperture.
    rng=random.Random(1717)
    for j in range(80):
        yy=rng.uniform(9,173);xx=rng.choice([rng.uniform(2.0,4.8),rng.uniform(96.8,98.6)])
        frame+=line(xx,yy,xx+rng.uniform(-.1,.1),min(173.8,yy+rng.uniform(.3,2.2)),rng.choice(['#dcdcdc','#3f3f3f']),rng.uniform(.10,.22),'opacity=".3"')
    s+=group('metal-outer-frame',frame)
    # Original uprights gently spread/bend at short forged joints. Their narrow
    # specular ridges STOP before the joints rather than passing through them.
    for i in range(1,8):
        x1,x2=BARS[i];width=2.55
        nodes=[]
        for row,(cy,half,phase) in enumerate(((37.5,11.6,0),(89.0,10.9,1),(142.3,12.0,0))):
            nodes.extend([cy] if (i+phase)%2 else [cy-half,cy+half])
        nodes.sort();ys=[8.1,174.0]
        for yy in nodes:ys.extend([yy-3.0,yy-1.1,yy,yy+1.0,yy+3.0])
        ys=sorted(ys)
        left=[];right=[];face_right=[]
        for yy in ys:
            dist=min(abs(yy-n) for n in nodes);spread=max(0,1-dist/3.0)
            bend=(.16 if i%2 else -.16)*spread
            xx=bar_x(i,yy)+bend;ww=width+.35*spread
            left.append((xx-ww/2,yy));right.append((xx+ww/2,yy));face_right.append((xx+.38+.10*spread,yy))
        bar=poly(left+right[::-1],'#4c4c4c')
        bar+=poly(left+face_right[::-1],'url(#steel-height)')
        start=8.35
        for end in nodes+[176.1]:
            stop=min(173.8,end-2.3)
            if stop>start:
                bar+=line(bar_x(i,start)-.72,start,bar_x(i,stop)-.72,stop,'#dcdcdc',.24,'opacity=".78"')
                bar+=line(bar_x(i,start)+.66,start,bar_x(i,stop)+.66,stop,'#3c3c3c',.29,'opacity=".68"')
            start=end+2.3
        for j,(a,b) in enumerate(((10.4,25),(51,73.5),(103,124.2),(156,172.3))):
            bar+=line(bar_x(i,a)-.7,a,bar_x(i,b)-.7,b,'#e6e6e6',.15,f'opacity="{.35+.12*(i%3):g}"')
        rng=random.Random(400+i)
        for j in range(13):
            yy=rng.uniform(10,171);xx=bar_x(i,yy)
            bar+=line(xx-.65,yy,xx+.15,yy+rng.uniform(-.12,.12),'#3f3f3f',.16,'opacity=".35"')
        s+=group(f'metal-upright-{i}',bar)
    # Three original diamond courses; middle course deliberately changes phase.
    for row,(cy,half,phase) in enumerate(((37.5,11.6,0),(89.0,10.9,1),(142.3,12.0,0))):
        body=''
        for sign in (-1,1):
            pts=[]
            for i in range(9):
                y=cy+sign*(half if (i+phase)%2==0 else 0)
                pts.append((bar_x(i,y),y))
            # The slant thins between short flared joints, with a small curve
            # into the upright instead of a separate rigid rhombus laid over it.
            d=f'M{pts[0][0]:.3f} {pts[0][1]:.3f}'
            for i in range(1,len(pts)):
                ax,ay=pts[i-1];bx,by=pts[i];dx=bx-ax;dy=by-ay
                if abs(ay-cy)>.1:
                    c1x=ax+dx*.12;c1y=ay+dy*.24;c2x=bx-dx*.23;c2y=by-dy*.14
                else:
                    c1x=ax+dx*.23;c1y=ay+dy*.14;c2x=bx-dx*.12;c2y=by-dy*.24
                d+=f'C{c1x:.3f} {c1y:.3f} {c2x:.3f} {c2y:.3f} {bx:.3f} {by:.3f}'
            body+=path(d,extra='stroke="#4c4c4c" stroke-width="1.38" stroke-linejoin="round"')
            body+=path(d,extra='stroke="url(#steel-height)" stroke-width=".86" stroke-linejoin="round"')
            body+=path(d,extra=f'stroke="#e0e0e0" stroke-width=".16" stroke-linejoin="round" transform="translate(-.13 -.18)" opacity="{.70-.08*row:.2f}"')
        # Only the original intersection positions receive a small forged weld.
        for i in range(1,8):
            nodes=[cy] if (i+phase)%2 else [cy-half,cy+half]
            for yy in nodes:
                xx=bar_x(i,yy)
                # A compact, variable forged shoulder ties diagonal and upright
                # together. Short curves catch light only on selected joints.
                body+=path(f'M{xx-.78:.3f} {yy-1.7:.3f}Q{xx-.74:.3f} {yy-.5:.3f} {xx-2.0:.3f} {yy+.85:.3f}Q{xx-.55:.3f} {yy+.38:.3f} {xx-.50:.3f} {yy+1.4:.3f}L{xx+.68:.3f} {yy+1.5:.3f}Q{xx+.65:.3f} {yy+.42:.3f} {xx+2.10:.3f} {yy+.85:.3f}Q{xx+.65:.3f} {yy-.65:.3f} {xx+.69:.3f} {yy-1.7:.3f}Z','url(#joint-metal)')
                tone=['#6a6a6a','#949494','#b7b7b7'][(i+row)%3]
                body+=path(f'M{xx-.68:.3f} {yy-1.55:.3f}Q{xx-.68:.3f} {yy-.20:.3f} {xx-1.60:.3f} {yy+.52:.3f}',extra=f'stroke="{tone}" stroke-width=".32" opacity=".88"')
                if (i+row)%3==0:
                    body+=line(xx-.35,yy+.45,xx+.70,yy+.62,'#3a3a3a',.23,'opacity=".58"')
        s+=group(f'forged-diamond-course-{row+1}',body)
    # Mount intersections retain independent editable polygons.
    for i in range(1,8):
        xx=BARS[i][1]
        s+=poly([(xx-.9,172.8),(xx+.8,172.8),(xx+1.8,174.8),(xx-1.8,174.8)],'url(#steel-height)')
    return '<defs>'+defs+'</defs>'+group('bitmap-1717-open-metal-grille',s)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--shape-only',action='store_true');args=ap.parse_args()
    stage='shape' if args.shape_only else 'redraw'
    drawings=((1708,143,wood_shape() if args.shape_only else wood_art()),(1717,101,grille_shape() if args.shape_only else grille_art()))
    for n,w,body in drawings:
        dest=PREV/f'bitmap-{n}-shape.svg' if args.shape_only else PARTS/f'bitmap-{n}.svg'
        write_part(dest,(0,0,w,179),body)
        render(dest,w*4,PREV/f'bitmap-{n}-{stage}.png')
        if not args.shape_only: render(dest,w,PREV/f'bitmap-{n}-native.png')
    comparisons(stage)
if __name__=='__main__':main()
