#!/usr/bin/env python3
"""Rebuild bitmap 1600 as editable, native SVG stone architecture.

Every surface below is authored vector geometry. No raster embedding, tracing,
noise filters or opaque backdrop. The separate drums, flutes, broken caps,
architrave and receding step courses remain editable in the emitted SVG.
Run: python source/ruins.py
"""
from pathlib import Path
import math, sys, random
sys.path.insert(0,str(Path(__file__).parent))
from svg_native import write_part, render
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=[]
def path(d,fill,stroke=None,sw=.35,opacity=1,extra=''):
    OUT.append(f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round"' if stroke else '')+(f' opacity="{opacity}"' if opacity!=1 else '')+f' {extra}/>')
def poly(points,fill,stroke=None,sw=.35,opacity=1):
    path('M'+' L'.join(f'{x:.2f},{y:.2f}' for x,y in points)+' Z',fill,stroke,sw,opacity)
def line(points,color,sw=.35,opacity=1):
    path('M'+' L'.join(f'{x:.2f},{y:.2f}' for x,y in points),'none',color,sw,opacity)
def g(name,extra=''): OUT.append(f'<g id="{name}" {extra}>')
def end(): OUT.append('</g>')

def defs():
    OUT.append('''<defs>
<linearGradient id="stone" x1="0" x2="1" y1=".12" y2=".18" objectBoundingBox="true"><stop stop-color="#413121"/><stop offset=".18" stop-color="#776044"/><stop offset=".4" stop-color="#625039"/><stop offset=".71" stop-color="#453325"/><stop offset="1" stop-color="#21170f"/></linearGradient>
<linearGradient id="frontStone" x1="0" x2="1" y1=".12" y2=".18"><stop stop-color="#56442e"/><stop offset=".2" stop-color="#806a4e"/><stop offset=".41" stop-color="#6d5940"/><stop offset=".64" stop-color="#51402d"/><stop offset=".84" stop-color="#39281c"/><stop offset="1" stop-color="#281b13"/></linearGradient>
<linearGradient id="flute" x1="0" x2="1"><stop stop-color="#23190f" stop-opacity=".88"/><stop offset=".4" stop-color="#3e2e1d" stop-opacity=".4"/><stop offset=".86" stop-color="#9b8869" stop-opacity=".4"/><stop offset="1" stop-color="#9c8967" stop-opacity=".65"/></linearGradient>
<linearGradient id="stoneTop" x1="0" y1="0" x2=".15" y2="1"><stop stop-color="#948160"/><stop offset=".5" stop-color="#7a684b"/><stop offset="1" stop-color="#473724"/></linearGradient>
<linearGradient id="stoneFace" x1="0" y1="0" x2=".15" y2="1"><stop stop-color="#796348"/><stop offset=".32" stop-color="#58442e"/><stop offset="1" stop-color="#2b2217"/></linearGradient>
<linearGradient id="stepTop" x1=".2" y1="0" x2=".75" y2="1"><stop stop-color="#685c3d"/><stop offset=".38" stop-color="#96815a"/><stop offset=".7" stop-color="#6f5c40"/><stop offset="1" stop-color="#4a412e"/></linearGradient>
<linearGradient id="stepFace" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#806746"/><stop offset=".22" stop-color="#5d482f"/><stop offset="1" stop-color="#241e15"/></linearGradient>
<linearGradient id="highArch" x1=".1" y1="0" x2=".8" y2="1"><stop stop-color="#39291d"/><stop offset=".22" stop-color="#271b15"/><stop offset=".6" stop-color="#211812"/><stop offset="1" stop-color="#120e0b"/></linearGradient>
<linearGradient id="heightShade" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="126"><stop stop-color="#090301" stop-opacity=".8"/><stop offset=".29" stop-color="#090301" stop-opacity=".7"/><stop offset=".46" stop-color="#0d0501" stop-opacity=".55"/><stop offset=".68" stop-color="#100702" stop-opacity=".27"/><stop offset=".88" stop-color="#180b02" stop-opacity=".03"/><stop offset="1" stop-color="#100801" stop-opacity="0"/></linearGradient>
</defs>''')

def foundations():
    g('perspective-foundations')
    # Small broken ground fragments, all inside the original clipped silhouette.
    poly([(0,152),(6,146),(16,143),(20,140),(29,139),(35,133),(44,130),(71,129),(117,136),(175,146),(261,143),(298,133),(308,134),(315,139),(323,140),(332,145),(343,145),(350,151),(349,152)],'#29271a')
    for pts,c in [([(6,149),(10,146),(16,147),(14,151)],'#4c4830'), ([(16,145),(21,143),(25,146),(22,149)],'#5e5437'), ([(26,140),(33,137),(38,140),(34,143)],'#52462f'), ([(30,149),(34,143),(42,144),(44,152)],'#191910'), ([(300,135),(306,134),(310,136),(307,138)],'#898364'), ([(327,145),(334,144),(339,146),(337,149)],'#5c5439'), ([(342,149),(347,149),(348,152),(342,152)],'#695e40')]: poly(pts,c)
    # Lowest, clipped broad terrace, including its chipped outer right corner.
    path('M22 143 L36 137 Q91 137 145 149 Q203 158 269 147 L311 138 L321 140 L324 143 L332 146 L329 149 L319 152 L72 152 L50 149 L37 148 L31 146 Z','url(#stepFace)')
    path('M26 142 L38 136 Q91 137 145 147 Q205 157 267 145 L308 136 L317 138 L321 140 Q272 158 223 160 L128 155 L77 149 L46 145 Z','url(#stepTop)')
    line([(39,138),(76,144),(117,150),(151,155)],'#b0a16a',.55,.6)
    path('M300 142 L313 139 L318 141 L314 144 L308 146 L304 151 L295 152 L300 148 Z','#342c1e')
    path('M34 137 Q81 137 129 146 Q197 161 276 143 L307 134 L312 136 L310 139 Q242 162 167 155 Q110 147 65 142 L40 139 Z','#3b3321')
    # Second step; joints run into the perspective rather than flat stripes.
    path('M33 136 L43 131 Q91 132 143 142 Q209 151 282 136 L297 132 L304 134 L302 138 Q232 158 165 150 Q102 141 58 139 L34 140 Z','url(#stepFace)')
    path('M37 134 L47 128 Q91 130 144 139 Q212 149 280 134 L294 130 L300 133 Q228 153 166 147 Q106 138 61 137 L37 137 Z','url(#stepTop)')
    line([(45,133),(75,136),(105,140),(146,147),(187,149),(226,146),(260,140),(289,134)],'#a29466',.6,.64)
    # Main front stylobate has large weathered courses and substantial depth.
    path('M43 128 L51 123 L122 123 L181 125 L224 130 L280 127 L288 129 L292 133 Q247 143 199 145 Q167 148 130 138 L76 133 L46 132 Z','url(#stepFace)')
    path('M48 124 L62 120 L119 120 L165 120 L199 124 L247 126 L278 125 L285 127 L288 129 Q249 138 202 139 Q168 143 133 134 L87 130 L48 128 Z','url(#stepTop)')
    line([(49,127),(80,130),(110,133),(132,137),(165,142),(195,143),(228,140),(256,135),(285,130)],'#a5976a',.7,.5)
    # Individually placed broken masonry joints and inset fissures.
    for p in [ [(58,126),(57,131),(54,132)],[(70,128),(69,132),(71,135)],[(85,130),(83,135),(82,138)],[(102,132),(100,138),(99,143)],[(120,134),(118,140),(119,146)],[(140,138),(139,143),(137,148)],[(159,141),(159,148),(158,152)],[(176,141),(179,146),(179,151)],[(204,140),(204,145),(207,151)],[(231,137),(234,142),(239,147)],[(257,132),(261,137),(267,142)],[(278,129),(282,132),(289,137)]]:
        line(p,'#2b2419',.7,.85)
        line([(x+.8,y-.4) for x,y in p],'#b2a078',.35,.4)
    for pts,c in [ ([(48,128),(57,127),(57,131),(52,132),(48,131)],'#58452e'), ([(65,129),(73,131),(75,134),(68,133)],'#aa9764'), ([(77,131),(81,131),(80,135),(76,135)],'#beb077'), ([(88,133),(96,134),(95,137),(87,136)],'#8f8053'), ([(107,136),(117,138),(116,141),(109,139)],'#a99864'), ([(125,139),(137,142),(137,146),(130,145)],'#71603b'), ([(142,143),(155,145),(155,150),(144,149)],'#a99967'), ([(163,145),(174,144),(176,150),(164,149)],'#746544'), ([(212,142),(226,140),(229,143),(215,146)],'#4f452d'), ([(249,137),(255,135),(258,137),(251,140)],'#b3a171')]: poly(pts,c,opacity=.75)
    # Erosion scars belong to selected blocks, not a tiled surface texture.
    for p in [[(43,135),(47,135),(48,138),(44,137)],[(60,137),(66,139),(68,144),(64,143)],[(92,142),(97,143),(96,146),(92,146)],[(123,147),(128,148),(128,151),(123,150)],[(183,148),(191,149),(190,151),(182,151)],[(239,145),(247,143),(250,144),(244,147)],[(285,141),(291,140),(294,141),(288,143)]]: poly(p,'#29271a',opacity=.8)
    end()


def terrace_wear():
    g('individual-weathered-terrace-blocks')
    rng=random.Random(12699)
    # Top paving recedes around the front shafts; wide stones are seen obliquely.
    for x0,y0,x1,y1 in [(49,124,61,125),(63,125,75,126),(78,126,88,127),(91,127,104,128),(106,128,117,130),(119,129,132,132),(134,131,146,133),(149,132,160,134),(184,133,196,133),(198,133,210,133),(213,132,224,131),(228,130,239,129),(243,129,253,128),(257,128,268,127),(270,127,280,126)]:
        dx=x1-x0
        poly([(x0,y0),(x1-1,y1-.4),(x1,y1+1),(x1-.8,y1+2),(x0+dx*.6,y0+2.3),(x0+.5,y0+1.8)],rng.choice(['#786244','#aa9162','#4d432c','#877a51','#b29a6a']),opacity=.7)
        line([(x0,y0+.4),(x0+.5,y0+1.8),(x0+dx*.6,y0+2.3)],'#c8b280',.35,.45)
        line([(x1-1,y1+.2),(x1-.8,y1+2)],'#30271a',.45,.6)
    # Face stones follow the curved perspective edge, with uneven weathered lips.
    xs=[46,54,65,76,88,100,112,125,139,152,166,180,194,210,225,241,257,273,286]
    def yy(x): return 127+14*math.sin(math.pi*(x-46)/240)
    for k,(a,b) in enumerate(zip(xs[:-1],xs[1:])):
        y0,y1=yy(a),yy(b)
        shade=['#806a47','#5e4c32','#96805a','#675235','#a38d60','#79623e'][k%6]
        poly([(a+.7,y0+.3),(b-1,y1+.3),(b-.9,y1+3),(b-2,y1+3.5),(a+2,y0+3.7),(a+.5,y0+2.9)],shade,opacity=.4)
        line([(a+.8,y0+.6),(a+2,y0+.1),(b-2,y1+.2)],'#c0ac78',.38,.42)
        if k%3==1:
            poly([(a+2,y0+1),(a+4,y0+1.2),(a+4.5,y0+2.5),(a+3.4,y0+3.3),(a+1.5,y0+2.4)],'#312b1b',opacity=.7)
        if k%3==2:
            line([(a+4,y0+1),(a+6,y0+.4),(a+7,y0+2.3),(a+5.5,y0+3)],'#d0b882',.32,.5)
    # Broken left edge exposes a darker, fragmented substructure.
    for pts,col in [ ([(36,137),(40,131),(45,130),(43,134),(47,137),(43,141),(39,140)],'#514630'), ([(44,136),(49,135),(50,139),(47,141),(45,140)],'#282318'), ([(51,136),(57,137),(56,140),(54,142),(51,141)],'#2a2217'), ([(58,138),(61,138),(63,140),(62,143),(58,142)],'#72603e'), ([(65,138),(70,139),(69,142),(65,145)],'#292319'), ([(73,140),(77,141),(78,144),(75,146),(73,144)],'#34291c'), ([(80,141),(84,141),(87,144),(85,146),(81,145)],'#a28d5a')]:poly(pts,col)
    end()


def column(name,x,top,w,bottom,broken=False,front=False,flutes=6,lean=0,phase=0,cap=False):
    """A curved shaft built as fluted stone drums, with irregular edges."""
    g(name)
    h=bottom-top; cx=x+w/2
    rng=random.Random(sum(ord(c) for c in name)*71)
    # Irregular base slab, elliptical torus and turned shoulder.
    bw=w*1.3
    poly([(cx-bw/2-1,bottom-1.5),(cx-bw/2+1,bottom-3.2),(cx+bw/2-1,bottom-3.1),(cx+bw/2+1,bottom-.7),(cx+bw/2+.6,bottom+1.5),(cx-bw/2-1,bottom+1.1)],'url(#stoneFace)')
    path(f'M{cx-bw/2} {bottom-2.4} Q{cx} {bottom-5} {cx+bw/2} {bottom-2.2} L{cx+bw/2-.6} {bottom-.6} Q{cx} {bottom+1} {cx-bw/2} {bottom-1} Z','url(#stoneTop)')
    path(f'M{x-1} {bottom-4} Q{cx} {bottom-5.8} {x+w+1} {bottom-3.5} L{x+w+1} {bottom-1.6} Q{cx} {bottom-.4} {x-1} {bottom-2.2} Z','url(#stone)')
    xl=x+.75+lean; xr=x+w-.7+lean
    if broken:
        topPts=[(xl,top+2),(xl+w*.12,top+.5),(xl+w*.32,top),(xl+w*.48,top+.45),(xl+w*.68,top+1.6),(xr,top+3.4)]
    else: topPts=[(xl,top+.6),(xl+w*.26,top),(xr-w*.2,top+.2),(xr,top+1)]
    # Distinct observed break profiles keep the surviving column heights unique.
    profiles={
        'left-01-shard':[(59.2,99.1),(60.5,96),(62.5,97.1),(63.3,99.4),(62.8,101)],
        'left-02-broken':[(72.9,88.1),(73.7,86.1),(76.5,85.5),(78,86.1),(78.7,90)],
        'left-04-high':[(92,74.4),(93.1,71.6),(96.8,72),(98.7,72.5),(101,76)],
        'left-06-high':[(115.2,59),(116.1,56.3),(118.4,55.3),(120.2,54.9),(123.1,56.2),(125.8,58.4)],
        'left-07-broad-break':[(131.1,83),(131.7,80.3),(135.6,79.8),(139.7,80.2),(142.5,81.6),(145.8,85.1),(147,88.7)],
        'main-03-broken':[(220.7,56),(222.5,54.4),(224.3,52),(227,51.6),(229.8,52.7),(232,55.4),(234.5,58.2)]
    }
    if name in profiles: topPts=profiles[name]
    right_nodes=[];left_nodes=[]
    for frac in sorted(rng.uniform(.06,.95) for _ in range(max(5,int(h/7)))):
        bulge=math.sin(frac*math.pi)*.4
        xx=x+w-.7+lean*(1-frac)+bulge
        yy=top+h*frac
        if name=='left-07-broad-break' and yy<89: yy=89+frac
        right_nodes += [(xx+rng.uniform(-.35,.45),yy),(xx-rng.uniform(.05,.38),yy+rng.uniform(.3,.9))]
        xx=x+.75+lean*(1-frac)-bulge
        left_nodes += [(xx-rng.uniform(.1,.4),yy),(xx+rng.uniform(.05,.35),yy+rng.uniform(.2,.8))]
    contour='M'+' L'.join(f'{a:.2f},{b:.2f}' for a,b in topPts+right_nodes)+f' L{x+w},{bottom-3} Q{cx},{bottom-1.5} {x},{bottom-3.6} L'+' L'.join(f'{a:.2f},{b:.2f}' for a,b in reversed(left_nodes))+' Z'
    path(contour,'url(#frontStone)' if front else 'url(#stone)')
    OUT.append(f'<clipPath id="clip-{name}"><path d="{contour}"/></clipPath>')
    g(name+'-shaft',f'clip-path="url(#clip-{name})"')
    # Round groove edges narrow at the sides. Intentional undulation matches wear.
    for j in range(flutes):
        a=(j+.5)/flutes
        fx=x+w*(.05+.9*a); fw=w/flutes*.58
        topx=fx+lean+(cx-fx)*.07
        path(f'M{topx:.2f} {top+.9:.2f} C{topx-.45:.2f} {top+h*.32:.2f} {fx-.35:.2f} {top+h*.62:.2f} {fx:.2f} {bottom-4:.2f} Q{fx+fw*.45:.2f} {bottom-2.8:.2f} {fx+fw:.2f} {bottom-4:.2f} C{fx+fw-.2:.2f} {top+h*.63:.2f} {topx+fw:.2f} {top+h*.29:.2f} {topx+fw*.85:.2f} {top+1:.2f} Z','url(#flute)',opacity=.57 if front else .47)
        if j<flutes-1:
            line([(topx+fw+.15,top+3),(fx+fw+.25,top+h*.42),(fx+fw-.1,bottom-6)],'#a18a61',.26,.22)
    # Broad quiet facets and vertical worn channels, deliberately asymmetric.
    path(f'M{x+w*.12} {top+h*.13} L{x+w*.29} {top+h*.09} L{x+w*.26} {top+h*.4} L{x+w*.13} {top+h*.48} Z','#bea078',opacity=.13)
    path(f'M{x+w*.61} {top+h*.06} L{x+w*.79} {top+h*.08} L{x+w*.85} {top+h*.78} L{x+w*.68} {top+h*.86} Z','#180f09',opacity=.2)
    # Stone drums have uneven course heights, shallow joints and local spalls.
    y=top+(9 if h>35 else 6)+(phase%3)
    k=0
    while y < bottom-6:
        k+=1
        bend=rng.uniform(.2,1.4)
        path(f'M{x-.5} {y} Q{cx} {y+bend} {x+w+.5} {y-.2}','none','#21170e',.30,.43)
        path(f'M{x+.4} {y+.85} Q{cx} {y+bend+1} {x+w-.3} {y+.5}','none','#b6a079',.24,.15)
        # A worn rim loses stone on one side, with a lighter exposed lower lip.
        side=.15 if k%3 else .68
        xx=x+w*side
        chip=[(xx,y-.7),(xx+w*.17,y-.1),(xx+w*.2,y+.9),(xx+w*.14,y+2),(xx+.25,y+1.6),(xx-.35,y+.4)]
        poly(chip,'#3c2c1e',opacity=.39)
        line([(xx+.2,y+1.6),(xx+w*.13,y+2),(xx+w*.19,y+.9)],'#b49b70',.32,.38)
        if k%2:
            line([(x+w*.72,y),(x+w*.64,y+2),(x+w*.7,y+3.7)],'#1c150e',.35,.55)
        y+=rng.choice([10.5,13,15.5,18,22])
    for frac,side,ww,hh in [(.18,.16,.26,.09),(.39,.06,.33,.13),(.63,.43,.29,.1),(.81,.17,.34,.07)]:
        xx=x+w*side; yy=top+h*frac
        poly([(xx,yy),(xx+w*ww*.6,yy-1),(xx+w*ww,yy+.7),(xx+w*ww*.8,yy+h*hh*.5),(xx+w*ww,yy+h*hh),(xx+w*ww*.4,yy+h*hh*.9),(xx,yy+h*hh*.65)],'#ad9470',opacity=.12)
    # Broad granular loss follows individual flutes and loaded stone edges.
    # These are local erosion patches, not an all-over noise or image texture.
    for q in range(max(4,int(h/5))):
        yy=top+3+rng.random()*(h-10)
        xx=x+w*rng.choice([.08,.18,.35,.49,.69,.83])
        ww=rng.uniform(.55,1.6);hh=rng.uniform(1.3,4.8)
        poly([(xx,yy),(xx+ww*.7,yy-.5),(xx+ww,yy+.5),(xx+ww*.85,yy+hh*.4),(xx+ww*1.1,yy+hh*.7),(xx+ww*.5,yy+hh),(xx-.2,yy+hh*.75),(xx+.15,yy+hh*.4)],rng.choice(['#baa17a','#241b12','#997f58','#443322']),opacity=rng.uniform(.13,.28))
        if q%4==0:
            line([(xx,yy),(xx+ww*.7,yy-.5),(xx+ww,yy+.5)],'#b09a74',.22,.23)
    for q in range(max(3,int(h/9))):
        xx=x+w*rng.uniform(.12,.55); yy=top+rng.uniform(.12,.93)*h
        line([(xx,yy),(xx-.3,yy+1.2),(xx+.1,yy+2.1),(xx-.2,yy+3.5)],'#b7a178',.25,.25)
        line([(xx+.55,yy+.5),(xx+.35,yy+1.4),(xx+.8,yy+2.4)],'#2b1e13',.22,.28)
    # One weathered continuous limestone scar on the light-facing quarter.
    poly([(x+w*.13,top+h*.58),(x+w*.25,top+h*.56),(x+w*.3,top+h*.6),(x+w*.23,top+h*.64),(x+w*.26,top+h*.67),(x+w*.12,top+h*.69),(x+w*.09,top+h*.65)],'#a68e62',opacity=.2)
    # Selected chips and worn patches in the flutes, structurally located.
    for frac,side in [(.22,.2),(.47,.66),(.73,.35),(.87,.8)]:
        yy=top+h*frac; xx=x+w*side
        poly([(xx,yy),(xx+w*.13,yy-1),(xx+w*.18,yy+.3),(xx+w*.1,yy+2),(xx-.3,yy+1)],'#877050',opacity=.32)
        line([(xx,yy),(xx+w*.12,yy-.8),(xx+w*.18,yy+.2)],'#c0a477',.24,.24)
    path(contour,'url(#heightShade)')
    end()
    if broken:
        poly(topPts+[(xr-1,top+4.4),(xl+w*.55,top+3.1),(xl+w*.28,top+2.3)],'#514030' if front else '#4d3e2b')
        line(topPts[:-1],'#8a7657',.45,.55)
        line([(xl+w*.29,top+1),(xl+w*.34,top+3),(xl+w*.21,top+5.8)],'#241a11',.5,.8)
        poly([(xr-2,top+2),(xr,top+3.5),(xr-.7,top+6),(xr-2.9,top+4.7)],'#21170f')
    if cap:
        path(f'M{x-1.2} {top+2.4} L{x-1.7} {top-.6} L{x+w+1.1} {top-1.1} L{x+w+1.5} {top+1.1} Q{cx} {top+3.6} {x-1.2} {top+2.4} Z','url(#stoneFace)')
    end()


def architrave():
    g('receding-low-architrave')
    # The low diagonal lintel lies behind the three taller foreground uprights.
    poly([(143,90),(151,87.3),(153,88),(165,83.3),(167,84),(173,82),(181,80.7),(183,81.2),(194,78),(205,75),(207,73.9),(218,71),(229,68.2),(231,68.7),(244,64),(258,60.6),(259,61.2),(274,57.8),(275.7,61.5),(277.5,65.9),(273.9,69.7),(263,71.8),(251,75.1),(245.9,76.7),(243.2,74.9),(219.8,81.5),(207,85.8),(183,91),(159,98),(145.3,97.9)],'url(#stoneFace)')
    poly([(143,90),(174,81),(194,77.2),(219,70.4),(245,63.3),(273.9,57.5),(274.8,60.2),(244.9,67.7),(219.1,74.7),(193.4,81.9),(172.4,86.2),(144.8,93.5)],'url(#stoneTop)')
    path('M145 94 L174 86.7 L195 82.1 L220 75.7 L245 68.5 L275 61.4 L276 64 L246 71.2 L219 78.5 L194 85.2 L174 89.4 L145.5 97 Z','#7c6647',opacity=.65)
    line([(145,94.4),(171.5,87.5),(194,82.6),(220,75.8),(244,69),(274.7,61.9)],'#b09b74',.45,.63)
    for x,y in [(152,87.8),(164,84.4),(177,81.2),(190,78.7),(204,75.3),(218,71.2),(233,67.1),(248,63.2),(260,60.7),(271,58.3)]:
        line([(x,y),(x+.3,y+3.5),(x+1,y+7.3)],'#34271b',.65,.8)
        line([(x+1,y+.4),(x+1.2,y+3.4)],'#c1a779',.4,.45)
    for x,y,w in [(148,91,7),(160,87.8,8),(175,84.8,8),(187,81.8,7),(201,78.3,9),(216,74.4,9),(232,70.4,8),(247,66.5,8),(261,63.1,8)]:
        poly([(x,y),(x+w*.45,y-1.5),(x+w,y-1.9),(x+w-.8,y),(x+w*.5,y+1.1),(x+.6,y+1.4)],'#b09972',opacity=.22)
        line([(x+.6,y+2),(x+2,y+1.8),(x+3,y+2.2),(x+4.7,y+1.4),(x+6,y+1.2)],'#231b12',.32,.45)
    # Missing soffit chips and fractured lintel ends.
    for p in [[(145,96),(149,94.6),(151,96.4),(148,98.6)],[(181,89.3),(185,88.6),(184,91.3),(181,91.7)],[(235,77.2),(239,75.9),(241,76.5),(239,78.4)],[(272,67.7),(275,66.8),(276,68),(274,69.4)]]:poly(p,'#241b12')
    end()


def high_arch():
    g('shattered-high-lintel')
    # Massive broken central portal, a short irregular span, not a new temple.
    silhouette=[(150.3,20.2),(152.1,18.3),(153.2,17.5),(153.9,14.8),(156.2,13.6),(158.6,8.4),(159.1,5.4),(161.9,4.2),(163.1,1.4),(166.8,0),(169.9,1.1),(171.8,1.1),(176.8,4.1),(181.3,5.8),(185.4,9.3),(190.8,11.7),(195.8,15.5),(198.9,18.2),(201.4,22.2),(202.8,26.4),(207.3,29.6),(209.5,31.3),(209.5,37.5),(206.5,39.8),(198.9,39.8),(192.6,37.3),(190.6,34.6),(190.6,31.5),(188.2,29.8),(187.3,26.2),(183.2,22.8),(179.3,21.1),(176.4,23.7),(172.5,27.1),(167,30.3),(161.6,29.1),(157,28.3),(153.2,25.2)]
    poly(silhouette,'url(#highArch)')
    # Broad top stone faces and underside are separately editable.
    poly([(151,20.2),(156.1,15.7),(160.4,8.2),(164.7,4.9),(168.4,3.2),(176.9,7.1),(186.8,11.7),(196.4,17.5),(200.4,22.2),(199.7,24),(191,20.6),(180.3,13.9),(170.3,9.9),(166.7,10.8),(162.2,17),(158.5,20.2),(155.4,24.6)],'#3c2c20')
    poly([(163.4,2.3),(166.9,.8),(171.6,2.2),(179.8,6.5),(187.7,10.1),(195.8,16.1),(198.2,19.3),(189.9,15.1),(180.1,10.2),(171.1,5.6),(168.1,5.4),(165.6,8.5),(161.2,9)],'#463124',opacity=.7)
    poly([(156.9,18.7),(162.9,14.6),(166.3,10.4),(170.4,10),(177.1,13),(183,17.4),(188.6,20.9),(193.6,23.4),(197.9,25.2),(200.5,28.2),(196.3,28.9),(190.5,25.7),(185.5,21.6),(180.2,20.4),(175.8,22.6),(171.9,26.5),(168.1,26.9),(161.4,25.1),(157,25.4)],'#18120e')
    # Chipped capitals under the span.
    path('M153.7 23.7 L159.4 24.4 L167.9 27.7 L176.7 24 L177.5 27.3 L173.8 30.9 L168.4 32.4 L158.1 29.7 Z','url(#stoneFace)')
    path('M156.8 27.4 L164.8 29.2 L174 29.1 L173.8 32.2 Q166.1 34.2 158.8 31.1 Z','#352619')
    path('M188.1 29 L193.1 30.1 L198.7 31.7 L208.7 31.9 L209.1 36.1 L205.4 39.1 L195.2 38 L192.3 35.9 L190.3 32.8 Z','url(#stoneFace)')
    path('M192.5 36.7 L199.1 38.3 L207.6 37.3 L207.7 40.6 L202.4 42.3 L194.6 40.4 Z','#3c2c20')
    # Major cracks, split stones and edge losses, not decorative speckling.
    for p in [[(168,2),(167.2,6),(169,9.7)],[(178,5),(177.5,8.6),(178.6,13.9)],[(188.1,10.5),(187.6,13.4),(189.7,19.5)],[(196.2,17.2),(194.7,19.8),(197,25.5)],[(158.5,13.8),(160.5,15),(161,18.8)],[(201.6,26.4),(199.4,29),(201,32.1)]]: line(p,'#120d09',.45,.65)
    for p in [[(159,7.8),(162.1,7),(161.2,10.7),(158.2,13.5)],[(153.1,19.1),(156.3,17.8),(155.3,20),(152.2,21.8)],[(171.7,4.5),(175.4,6.1),(174.9,7.1),(171.1,5.6)],[(184.4,12.8),(187.1,14.3),(186.4,15.2),(183,13.9)],[(195.4,21.4),(198.3,23.6),(197.3,24.1),(194.8,22.9)]]:poly(p,'#7d6242',opacity=.35)
    poly(silhouette,'#080402',opacity=.38)
    end()

def rubble():
    g('foreground-footings-and-chips')
    # Layered right stylobate occupies the narrow ledge under the tall colonnade.
    path('M178 123.7 Q226 130.8 280 126.4 L285 128.7 L284.2 131 Q232 138 180 130.5 L176 128.3 Z','url(#stoneFace)')
    path('M178.3 123.5 Q226.5 129.4 279.6 126.2 L283.8 128 Q231.8 133.8 179.4 127.2 Z','url(#stoneTop)')
    path('M181 129.3 Q232 134.6 285 129.3 L289 131.2 L288 133 Q236 141.4 181 132.8 Z','url(#stoneFace)')
    line([(181,129.8),(207,132.1),(237,132.7),(265,131.3),(285,129.8)],'#b19b6b',.5,.4)
    for x,y in [(185,125.2),(197,126.3),(210,127.5),(225,128.3),(241,128.2),(255,128.1),(270,127.5)]:
        line([(x,y),(x+.8,y+2),(x-.1,y+3.5)],'#2b2218',.55,.75)
        line([(x+1,y+.3),(x+1.6,y+1.8)],'#a28b60',.35,.45)
    # Raised fractured rail under the receding left-hand column line.
    for x,y,w in [(52,123.3,11),(63,123.5,13),(77,123.1,13),(91,122.9,14),(107,123.2,14),(122,122.6,14),(138,122,14)]:
        path(f'M{x} {y} L{x+w-2} {y-.7} L{x+w} {y+.5} L{x+w-.6} {y+2.8} L{x+1.5} {y+3.7} L{x-.7} {y+2.1} Z','url(#stoneFace)')
        line([(x+.2,y+.3),(x+w-2,y-.2),(x+w-.5,y+.7)],'#b09a6b',.5,.5)
        line([(x+w*.55,y+.3),(x+w*.51,y+1.4),(x+w*.65,y+3)],'#302316',.45,.6)
    # Broken lower drum of the foreground giant: broad curved, crumbled stone.
    path('M155.7 108.8 Q165 111.3 175.5 108.5 L175.4 111.7 L177.5 114.5 L176.9 118.3 L174.6 121 L167.8 122.4 L161 121.8 L155.2 120.5 L153.4 117.5 L154.8 114.2 L153.9 112.2 Z','url(#frontStone)')
    path('M155 111.2 Q164.3 114 175.9 111.2 L176.5 113.8 Q166.2 117.1 154.5 113.7 Z','url(#stoneTop)')
    path('M155.1 115.2 Q162 117.6 174.7 115.6 L176.1 117.8 L174.5 120.3 Q165.9 122.6 157 119.5 L154.6 118.4 Z','url(#stone)')
    for p in [[(159,112.5),(160,114.2),(158.7,116.8),(160.2,119.8)],[(168.2,113.4),(167.4,116),(168,118.1),(167.8,121)],[(173.3,112.6),(172.7,114.8),(174.1,116.4),(172.7,119.9)]]:line(p,'#2c2115',.6,.65)
    for pts in [[(155,112),(157,112.5),(158.1,114),(157,116),(154.5,115)],[(160,116),(162.8,115.6),(163.2,118.3),(161.1,120),(159.8,118.8)],[(169.2,118.4),(171.5,117),(174.1,117.2),(173,120.1),(169.1,120.4)]]:poly(pts,'#ad9368',opacity=.32)
    # Fractured plinth of the foremost column, obscuring receding steps.
    poly([(153.4,120.3),(159.8,118.6),(166.3,120.1),(174.8,120),(178,122.6),(176.8,126.1),(167.5,127.8),(158.5,126.6),(153,126)],'#211c13')
    poly([(155.4,119.9),(161.4,118.9),(168,120.7),(173.9,120.3),(176.7,122.1),(170.4,123.4),(164.1,122),(157,123.1),(153.8,122)],'#826c46')
    poly([(160.1,123),(166.3,124.1),(174.5,123.5),(175.2,126.1),(165.3,127.4),(160.2,126.5)],'#352b1c')
    path('M160 128.6 L165.8 126.6 L173.1 127.1 L178.5 126.4 L182.1 129.7 L180.4 132.5 L170.1 134.4 L160.6 132.6 Z','url(#stoneFace)')
    poly([(159.7,127.3),(165.9,125.7),(173.6,126),(179.6,125.9),(181.9,128.5),(173.6,130.1),(164.1,129.3),(159.9,130)],'url(#stoneTop)')
    line([(173.4,127.2),(173.8,130.1),(174,133.4)],'#211a10',.75)
    poly([(132,128.4),(137.3,126.3),(142.1,127.3),(144.5,130.8),(139.3,133.8),(133,132.7)],'#51402a')
    poly([(132.5,127.8),(137.6,125.8),(141.3,126.9),(142.5,129.1),(137.5,130),(133.1,129.4)],'#8a7048')
    for p,c in [ ([(56,123),(59,121),(64,122),(63,124)],'#9c855c'), ([(76,124),(81,122),(84,123),(82,125)],'#4b3a25'), ([(103,124),(109,123),(110,125),(106,126)],'#a48c5b'), ([(146,123),(150,121),(153,123),(150,125)],'#3a2c1c'), ([(183,125),(187,122.6),(191,123),(194,125),(191,128)],'#665135'), ([(211,128),(216,126),(219,128),(216,130)],'#92764f'), ([(239,125),(241,121),(245,123),(247,127)],'#504732'), ([(243,123),(245,119),(246.5,121),(246,125)],'#93815a'), ([(279,128),(282,124),(284,127),(284,130)],'#655b3e')]: poly(p,c)
    # Small basal splits, subdued moss mineral seams on horizontal faces only.
    for p in [[(54,126),(57,125.7),(59,126.4)],[(71,128),(76,128.6),(79,128.8)],[(113,130),(118,130.5),(121,131)],[(191,134),(197,133.7),(201,133.9)],[(223,135),(231,133.4),(235,133.1)],[(271,130),(275,129.2),(279,129.4)]]:line(p,'#aba36c',.7,.5)
    end()

def build():
    defs(); foundations(); terrace_wear()
    g('distant-left-columns')
    column('left-01-shard',54.7,96,7.7,123.1,True,False,4,lean=4,phase=1)
    column('left-02-broken',68.1,85.5,9.8,123.4,True,False,4,lean=4,phase=2)
    column('left-03-short',81,99.7,10.4,123.2,True,False,4,lean=1,phase=1)
    column('left-04-high',88.6,71.6,11.6,123.3,True,False,5,lean=2.8,phase=3)
    column('left-05-stump',98.8,107,10.3,123.1,True,False,4,phase=1)
    column('left-06-high',111.2,54.9,15,122.6,True,False,6,lean=3.7,phase=2)
    column('left-07-broad-break',128.8,79.8,18.6,121.7,True,True,6,lean=1.8,phase=1)
    end()
    g('rear-colonnade')
    column('rear-01',148.7,94.5,8.2,120.1,False,False,3,phase=2,cap=True)
    column('rear-02-stump',180.7,91.5,10.6,120.7,True,False,4,phase=3)
    column('rear-03',211,80.3,8.4,121.8,False,False,3,phase=0,cap=True)
    column('rear-04-right',246,73.7,10.3,127.5,False,True,4,phase=1,cap=True)
    column('rear-05-right',257,70.2,11.7,127.7,False,True,4,phase=2,cap=True)
    column('rear-06-right',270.1,68,9.3,128.2,False,False,4,phase=3,cap=True)
    architrave(); end()
    g('foreground-tall-columns')
    column('main-01-tall',155.5,25.8,20.8,121,False,True,7,lean=.8,phase=1)
    column('main-02-tall',192.3,38.7,18,122.1,False,False,6,lean=0,phase=2)
    column('main-03-broken',220.3,51.6,16.1,126.8,True,True,5,lean=-.4,phase=3)
    high_arch(); end(); rubble()
    return write_part(ROOT/'parts/bitmap-1600.svg',(0,0,350,152),''.join(OUT))

def preview(svg):
    tmp=ROOT/'previews/ruins-new.png'; render(svg,1400,tmp)
    original=Image.open(ROOT/'reference/ruins/1600.png').convert('RGBA').resize((1400,608),Image.Resampling.NEAREST)
    new=Image.open(tmp).convert('RGBA')
    # Dark surroundings preserve the asset's intended game-scene lighting.
    board=Image.new('RGB',(1440,1320),(30,31,30)); d=ImageDraw.Draw(board)
    d.text((20,10),'ORIGINAL  |  bitmap 1600  |  350 x 152',fill=(208,204,183))
    board.paste(original,(20,40),original)
    d.text((20,666),'NATIVE VECTOR REDRAW  |  editable stone surfaces',fill=(208,204,183))
    board.paste(new,(20,696),new)
    board.save(ROOT/'previews/ruins-original-new.png')
    # Native-sized pair is useful for checking readability at actual game size.
    small=Image.new('RGB',(720,184),(30,31,30));d=ImageDraw.Draw(small)
    d.text((10,4),'ORIGINAL',fill=(208,204,183));d.text((370,4),'REDRAW',fill=(208,204,183))
    o=Image.open(ROOT/'reference/ruins/1600.png').convert('RGBA');n=new.resize((350,152),Image.Resampling.LANCZOS)
    small.paste(o,(10,25),o);small.paste(n,(370,25),n);small.save(ROOT/'previews/ruins-native-check.png')
if __name__=='__main__':
    svg=build();preview(svg);print(svg)
