"""CF6 stage 2: editable mechanical props, with R3 dozer-blade-only revision.

The reference PNGs are inspection-only; no image element, pixel trace, noise texture,
external file, or audit-directory dependency is used in the SVG artwork.
Run from any working directory: python source/wreck_props.py [1606 1607 1608 1609]
Each intact part is described as a continuous volume. Damage is limited to the
missing rotor / glazing and collapsed supports that are visible in the references.
"""
from pathlib import Path
import sys, math, json
from PIL import Image, ImageDraw, ImageFont
from svg_native import write_part, render
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'reference/wreck-props'
SIZES={1606:(170,75),1607:(204,99),1608:(185,104),1609:(118,88)}

def path(d,fill='none',stroke='#090b0b',sw=.6,extra=''):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'
def line(d,c='#555a58',w=.5,extra=''):return path(d,'none',c,w,extra)
def ellipse(x,y,rx,ry,fill,stroke='#090b0b',sw=.5,extra=''):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'
def circle(x,y,r,fill='#595d59',stroke='#0a0c0b',sw=.35):return ellipse(x,y,r,r,fill,stroke,sw)
def group(name,s,extra=''):return f'<g id="{name}" {extra}>{s}</g>'
def linear(name,stops,x1=0,y1=0,x2=0,y2=1):
    return f'<linearGradient id="{name}" x1="{x1*100}%" y1="{y1*100}%" x2="{x2*100}%" y2="{y2*100}%">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</linearGradient>'
def radial(name,stops,cx='.3',cy='.25',r='.8'):
    return f'<radialGradient id="{name}" cx="{cx}" cy="{cy}" r="{r}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</radialGradient>'
def defs():
    return '<defs>'+''.join([
        linear('metal',[(0,'#575c5a'),(.24,'#3d4241'),(.63,'#272c2c'),(1,'#111516')]),
        linear('dark',[(0,'#2b302f'),(.35,'#1c2121'),(1,'#070b0b')]),
        linear('shell',[(0,'#303636'),(.2,'#202727'),(.55,'#101717'),(1,'#080c0d')]),
        linear('silver',[(0,'#b1b6b1'),(.2,'#858c87'),(.56,'#515a55'),(1,'#282e2c')]),
        linear('cylinder',[(0,'#2a2f2b'),(.22,'#969d8e'),(.42,'#c7cabb'),(.6,'#686f61'),(1,'#20261f')],0,0,1,0),
        linear('rubber',[(0,'#2d3230'),(.2,'#1c211f'),(.64,'#111512'),(1,'#060907')]),
        radial('wheel',[(0,'#9ca39d'),(.48,'#7f8781'),(.8,'#4a534e'),(1,'#252e27')]),
        radial('podShell',[(0,'#424847'),(.28,'#252c2b'),(.58,'#111716'),(.83,'#080d0c'),(1,'#040706')],'.23','.22','.84'),
        radial('podSocket',[(0,'#3d4440'),(.43,'#252e29'),(.8,'#111a14'),(1,'#080e0a')],'.29','.22','.86'),
        linear('gold',[(0,'#b59b43'),(.19,'#aa8530'),(.45,'#947124'),(.75,'#6c5019'),(1,'#382b12')],0,0,.75,1),
        linear('goldRound',[(0,'#5c4118'),(.17,'#b68b32'),(.4,'#c5a34e'),(.65,'#98732a'),(1,'#4c3311')],0,0,1,0),
        linear('track',[(0,'#6a7252'),(.22,'#535d3c'),(.5,'#3d482d'),(1,'#222c1b')]),
        linear('bucket',[(0,'#5b6630'),(.28,'#424f20'),(.65,'#273513'),(1,'#0d1609')],0,0,1,1),
    ])+'</defs>'
def bolt(x,y,r=.55):return circle(x,y,r,'#59615a',sw=.25)+line(f'M{x-r*.48} {y}h{r*.96}','#151b16',.18)
def pin(x,y,r=1.25,gold=False):
    return circle(x,y,r,'#8c7338' if gold else '#747d74',sw=.38)+circle(x,y,r*.52,'#353b2c' if gold else '#252e29',sw=.25)+line(f'M{x-r*.52} {y-r*.52}q{r*.4} {-r*.26} {r*.78} 0','#c0b477' if gold else '#b1b7ad',.22)
def tube(x1,y1,x2,y2,w=1.5,col='#777f77'):
    return line(f'M{x1} {y1}L{x2} {y2}','#080d09',w+.7)+line(f'M{x1} {y1}L{x2} {y2}',col,w)+line(f'M{x1-.18} {y1-.16}L{x2-.18} {y2-.16}','#b0b7ab',max(.22,w*.2))
def hydraulic(x1,y1,x2,y2,split=.55,w=2.2):
    xm=x1+(x2-x1)*split;ym=y1+(y2-y1)*split
    a=tube(x1,y1,x2,y2,.8,'#999e82')
    a+=line(f'M{x1} {y1}L{xm} {ym}','#322c14',w+.65)+line(f'M{x1-.18} {y1-.15}L{xm-.18} {ym-.15}','#9d8238',w)
    a+=line(f'M{x1-.4} {y1-.23}L{xm-.4} {ym-.23}','#d3b961',.45)
    a+=pin(x1,y1,.6,True)+pin(x2,y2,.6,True)
    return a

def excavator():
    s=defs()
    # The low front attachment is a thin dozer blade, not a crawler or solid
    # wedge. Its almost upright face has a narrow rolled top and short end face.
    # The few source-visible rear connections stay low contrast and partly
    # concealed; the low-resolution reference does not establish cylinder count.
    a=path('M57.2 74.7 Q60.5 72.2 67.5 71.1 L79.6 68.9 82.4 69.8 70.5 72.8 60.6 76.3 57 76.2Z','url(#dark)',sw=.45)
    a+=path('M59.1 74.4 L64.2 72.6 70.2 71.5 69.3 72.2 62 74.8Z','#303830',stroke='none',sw=0)
    a+=line('M59.7 73.9 L64 72.5 68.2 71.7','#495045',.32)
    a+=path('M64.1 77 L77.6 71.3 81.7 71.5 79.9 73.6 68 79.1Z','#20291b',sw=.45)
    a+=path('M65.1 77.1 L78.8 71.5 79.9 72 67.2 77.9Z','#5d6749',stroke='none',sw=0)
    a+=line('M66.1 77.2 L77.8 72.2','#798162',.27)
    a+=path('M71.5 78.4 L80.9 74.5 84.3 75.1 79.2 80.7 74.5 81.3Z','#0b110c',sw=.45)
    # A thin folded lip and short right end reveal plate thickness; neither is
    # extended back to the turntable as a filled triangular ramp.
    a+=path('M51.9 77 Q62.4 77.9 74.1 79.8 L74.6 86.3 Q62.1 85 51.8 81.7 L52.4 79.5Z','url(#dark)',sw=.5)
    a+=path('M52.1 76.7 Q63.4 77.7 74.3 79.3 L76.3 80.1 74.1 80 Q62.2 78.4 51.9 77.4Z','#353d32',sw=.25)
    a+=line('M52.6 77.1 Q62.9 78.1 74 79.6','#61695b',.35)
    a+=path('M74.2 79.7 L76.3 80.1 76.8 86.1 74.6 86.5Z','#111811',sw=.38)
    a+=line('M74.4 80.3 L74.8 85.7','#3b4436',.42)
    a+=path('M51.9 81.1 Q62.1 84.2 74.5 85.8 L74.6 86.4 Q62.1 85 51.8 81.7Z','#172016',sw=.25)
    a+=line('M52.8 81.9 Q61.8 84.6 73.7 86','#333d2c',.25)
    a=group('thin_inclined_dozer_blade_and_shadowed_mount',a)
    # The unchanged near crawler keeps its thin top run, rounded end wheels
    # and shadowed roller bed; the rotating chassis remains above it.
    a+=path('M77 78 Q78 74 84 73 L108 72 Q115 72 117 77 Q119 83 112 86 L83 87 Q77 87 76 83Z','url(#dark)',sw=.7)
    a+=path('M81 77 Q83 75 88 75 L108 74.5 Q113 74.5 114 78 Q116 82 111 83.5 L84 85 Q79 85 79 81Z','url(#track)',sw=.5)
    a+=path('M83 78 Q86 76 90 76 L108 75.8 Q112 76 112 79.5 Q112 82 109 82.3 L85 83.7 Q81 84 81 81Z','#111b0e',sw=.35)
    a+=ellipse(109.5,79.3,2.7,3.2,'url(#track)',sw=.45)+ellipse(109.5,79.3,1.15,1.8,'#182212',sw=.3)
    a+=ellipse(84.4,80.4,2.6,2.8,'#3d492d',sw=.4)+ellipse(84.4,80.4,1.15,1.45,'#1b2615',sw=.3)
    # Low-contrast partial wheel arcs suggest the obscured roller bed; their
    # count is not asserted as a newly invented detailed mechanism.
    a+=line('M89 80.1 Q91 82.8 93 80.7 M95.2 80 Q97.3 82.4 99.4 80 M101 79.7 Q103.3 81.8 105 79.7','#293722',.4)
    a+=path('M80.5 76.8 Q85 74.4 90 74.4 L109 73.9','none','#81886a',.55)
    a+=path('M81 83.4 L86 84 110 82.8','none','#505f3b',.8)
    for x in [82,85.6,89.2,92.8,96.4,100,103.6,107.2,110.8]:
        yy=75.2-(x-82)*.038
        a+=line(f'M{x} {yy}l.45 1.65','#29331f',.5)
        a+=line(f'M{x+.2} {84.8-(x-82)*.045}l-.1 -1.5','#1f2b18',.5)
    a+=line('M114 76l-1.2 1 M116 79l-1.5 .2 M114.6 82l-1.3-.6','#252f1d',.65)
    a+=path('M75 75 L80 70 97 67 103 71 92 75 82 77Z','url(#dark)',sw=.55)
    a+=path('M79 68 L80 64 91 63 100 65 100 69 Q91 73 80 70Z','url(#dark)',sw=.5)
    a+=line('M81 68 Q90 71 98 67','#596344',.5)
    s+=group('continuous_crawlers_and_connected_turntable',a)
    # Genuine window apertures: no extra opaque pane over a source void.
    a=path('M63 43 Q64 36 69 33 L86 33 89 35 91 62 86 66 63 66 62 61Z M65 43 Q66 38 70 35 L81 35 83 47 65 48Z M85 35.8 L88 36.2 89 47 85.7 47Z','url(#dark)',sw=.6,extra='fill-rule="evenodd"')
    a+=path('M64 50 L72 49 75 60 65 62Z','#0a1010',sw=.4)
    a+=path('M66.7 52 L70 52 69.7 56.6 66.7 57Z','url(#silver)',sw=.3)
    a+=line('M68.2 52.7v3.3','#d0d6ce',.45)
    a+=line('M64.3 48.6 L72.2 48.1 M64.6 61.8L72.9 61.2 M65 64.6h7.2','#515a4b',.45)
    a+=path('M69 33 L86.5 33 89 35 69 35Z','url(#metal)',sw=.45)
    a+=line('M64 43 Q64 38 67.4 35.5 M84 36l1 10','#60694f',.35)
    s+=group('cab_frame_and_open_glazing',a)
    # A rounded counterweight with a continuous top and pressed cover.
    a=path('M81 49 Q85 48 88 51 L93 52 Q103 51.5 112 53 Q115 53 115.1 57 L115.6 62 Q115 65 111 65.6 L92 67.1 81 64.3Z','url(#gold)',sw=.65)
    a+=path('M88 53.1 Q101 52.6 111.2 54 Q112 56.3 111.2 60.8 L90 62Z','url(#goldRound)',sw=.35)
    a+=path('M111.3 53.2 Q114.5 53.1 115 55 L115.7 61.5 113.6 64 111.4 63Z','url(#dark)',sw=.4)
    a+=path('M82 63 L93 64.8 114 63 114 66 93 68 82 66Z','url(#dark)',sw=.45)
    a+=line('M90 53.6 Q101 53.4 110 54.5','#dcc277',.45)
    a+=line('M91 62L110 61.2','#c4a24e',.35)
    for x in [96,98.1,100.2,102.3,104.4]:a+=line(f'M{x} 56.6v3','#4d3b18',.42)
    a+=path('M87 51 Q89 50.5 90 52 L91 59 89.5 61 87 60Z','#977437',sw=.25)
    a+=ellipse(89.2,53.3,1.5,2,'#322d1a',sw=.35)+line('M88.6 52.1l.3 1.3','#dbbd70',.35)
    for x,y in [(92,55),(108,55.2),(110,60.5)]:a+=bolt(x,y,.35)
    s+=group('rounded_counterweight_and_engine_cover',a)
    # One continuous main boom, with no fictional hinge at its curved shoulder.
    a=path('M80 61 Q80.8 64 77.8 64 L74.3 61.4 Q73 54 72.4 46 C71.9 38.1 69.9 32 64.5 27.2 L54.6 18.5 Q49.8 15 46.4 10.8 L48.8 8.9 Q54.5 13.8 61.4 18.6 C70.1 24.3 75.5 29.3 78 36 Q81 45.5 80 61Z','url(#gold)',sw=.65)
    a+=path('M48.5 10.5 C54.5 16 63 20.8 68.7 26.5 Q74.5 31.3 76.2 38.7 Q79 49 78.5 61.4 L76.5 61 Q75.5 51 74.4 43 C73.8 34.6 70.6 29.3 64 24.3 L53.7 16.4Z','url(#goldRound)',sw=.25)
    a+=line('M49.7 11.6 Q56.8 18 64.2 22.5 Q71.7 28.2 74.5 34.9','#d4b768',.55)
    a+=line('M76.4 40.2 Q78.2 49 77.9 57.5','#c4a35b',.45)
    a+=path('M74.3 44 Q75.5 54 76.2 60.4 L75 61 73.8 54.3Z','#6e461c',stroke='none',sw=0)
    # Lift ram: base eye is on the rotating chassis, rod eye on a boom lug.
    a+=path('M73 57.4 L77 58 78.5 62.2 75.5 63.4Z','url(#gold)',sw=.4)
    a+=path('M68.5 31.4 L71.4 32.6 72.2 35.1 69.4 35.8Z','url(#gold)',sw=.35)
    a+=hydraulic(75.7,60.7,70.3,33.7,.59,1.8)
    a+=pin(77.9,61.3,1.45,True)
    # Stick cylinder follows the upper boom; both endpoints have brackets.
    a+=path('M57 11.6 L59.2 12.8 59.7 15.8 57.4 15Z','url(#gold)',sw=.3)
    a+=path('M68.5 22 L71.7 24 70.8 26.4 68 24.7Z','url(#gold)',sw=.3)
    a+=hydraulic(70.1,24.4,57.7,12.8,.6,2.1)
    a+=line('M70 31 Q68 34 69.8 40 Q72 46 72.6 52','#1c2613',.7)
    a+=line('M70.7 31.7 Q69.5 36 71.3 42.6','#77794a',.32)
    s+=group('single_continuous_boom_and_anchored_rams',a)
    # Dipper and bucket keep separate pins and a small connected linkage.
    a=path('M49 1.2 L50 2 47.4 8.6 Q46.6 11 42.8 13.6 L32.2 23 22 31 18 30.5 17.2 28 L26.3 20.7 39.8 8.4 45.1 4.6Z','url(#gold)',sw=.6)
    a+=path('M47.5 3.8 L45.3 8.3 37.8 14.7 29.8 22.3 21.2 28.5 20.1 27.8 30 18.8 41.1 9Z','url(#goldRound)',sw=.25)
    a+=line('M43.8 8.9 L34.6 17 23.1 26.7','#d2b05a',.45)
    a+=pin(47.1,9.1,1.65,True)
    a+=path('M34.1 10.3 L37.8 8.5 39.3 10.1 36.7 13Z','url(#gold)',sw=.3)
    a+=hydraulic(36.7,10.4,23.6,22,.46,1.15)
    a+=path('M23.5 21.4 L24.7 23.6 21.8 27.7 19.2 27.4Z','url(#gold)',sw=.35)
    a+=pin(20.3,28.2,1.1,True)
    a+=path('M17.3 28.8 Q13.6 26 8.6 28.5 L2 32 Q.2 35 2 42 L4.6 50.2 7.5 50.8 9.2 44.8 Q13.6 40.6 17.6 34 L19.1 30Z','url(#bucket)',sw=.65)
    a+=path('M3 32.7 Q8.5 29 13.6 29.5 L17.2 31 Q13.4 37.8 9.6 40.7 L6.7 46 Q4.5 40.1 3 32.7Z','url(#bucket)',sw=.35)
    a+=path('M2 34.8 Q3.3 42.5 4.8 49.7 L7 50.5 6.8 46.3 5 38Z','#0a1308',sw=.4)
    a+=line('M4.2 32 Q9 29.5 13.8 29.8 M11 39l3.9-4.6','#697341',.45)
    a+=path('M8.1 46 L9.7 43.5 10.1 45.5 8.2 48Z','#6e7454',sw=.3)
    s+=group('dipper_bucket_pivots_and_linkage',a)
    return s

def pod():
    s=defs()
    # The left foot and compressed underframe remain low, with small round joints.
    a=path('M1.7 88 Q5 83 15 81 L27 77 31 73 35 73 40 77 43 84 Q39 88 31 90 L22 94 10 100 Q4 101 1 96Z','url(#dark)',sw=.65)
    a+=path('M3 88 Q10 84 18 84 L30 80 34 80 31 84 19 89 11 96 4 97Z','url(#metal)',sw=.35)
    a+=line('M3.8 92.2 Q8 93 12 91 M9 97 L16.5 88 26.8 83.3','#747d73',.5)
    for x,y in [(3.2,89),(5.4,86.7),(8.3,85.3),(11.5,83.9)]:a+=line(f'M{x} {y}l1.2 4.8','#090e0b',.8)
    a+=path('M31 69 L34 70 39 75 37.4 79 31 80 29 76Z','url(#metal)',sw=.5)
    a+=pin(33.6,75.5,1.6)
    a+=path('M41 84 Q55 81 65 87 L77 89 87 91 99 92 104 98 100 101 83 100 72 97 61 98 49 94Z','url(#dark)',sw=.55)
    a+=line('M50 88 Q60 87 66 92 L77 95 94 96','#4a544b',.65)
    s+=group('low_foot_and_compressed_underframe',a)
    # A single deep round shell. Shoulder, opening and front skirt belong to it.
    a=path('M42 68 Q43.6 55.4 50 44 C51 29 62.6 14.3 78.5 6 Q92-.3 107 1.6 C124 2.7 138.3 18.7 145 36.7 Q150.1 51.6 148.5 65 L145.8 75 Q145.5 83.4 138.6 88.7 L129 94 Q119.3 99.3 112 96.3 Q106.6 92.7 103.4 84 C100.7 78.2 92 75.4 84.2 75.8 Q72.2 78.1 61 77 L51.3 74Z','url(#podShell)',sw=.8)
    # Broad shoulder modelling has no outlined polygon seams or added cracks.
    a+=path('M50.7 43.7 C52.8 29 62.2 17.6 77.6 9.1 Q82.6 7.2 85.6 7.1 C77.3 13 74.5 21.5 74.1 29.5 Q72.8 34.4 66.1 36.4 Q56.8 37.8 50.7 43.7Z','url(#metal)',stroke='none',sw=0)
    a+=path('M80 10.7 Q82.3 15.1 87.6 20.1 Q93.9 25.1 96 29.6 C91.8 31.2 87.9 32 82.3 33.9 Q76 36 73.9 31.3 Q74.3 20 80 10.7Z','url(#silver)',stroke='none',sw=0)
    a+=line('M79 10.2 C75 17.4 73 25.4 73.7 31.4 Q74.5 34.7 78.2 35.1','#080d0b',.85)
    a+=path('M87 3.9 Q96.8 1.1 107.2 3.3 C114 6 119 12 121 17.5 Q113.3 13.1 108.1 15.6 C101.9 11 95.5 6.3 87 3.9Z','url(#dark)',stroke='none',sw=0)
    a+=line('M54.2 32.7 Q62.8 17.6 75.3 10.8 M85.6 5.1 Q94 2.9 102 4','#59625b',.4)
    a+=path('M140 29 Q147 43 146.5 57.7 Q146.6 65 143.5 70.2 L141.7 68.8 Q145 55 142.9 44.6Z','url(#metal)',stroke='none',sw=0)
    a+=line('M145.8 46.4 Q149 59 143.3 69.2','#747d70',.45)
    a+=path('M134.1 64.6 Q139 66 139.3 72 Q138.2 79.8 128.6 85.6 L118.5 91.4 Q120.5 85.6 126 82.6 C132.5 78.9 132.8 72.9 134.1 64.6Z','url(#dark)',stroke='none',sw=0)
    a+=path('M133.7 76.5 Q130.4 81.9 121.1 86.8 L120.5 83.7 Q129.9 79.3 134.3 73.6Z','url(#silver)',stroke='none',sw=0)
    a+=path('M108.2 69.5 Q113 66.2 115.4 71.2 L115 82.4 118.1 87.4 115.3 94.1 Q109.4 89.6 108.2 80.6Z','#080d0b',stroke='none',sw=0)
    s+=group('continuous_dome_shoulder_and_front_skirt',a)
    # The oval socket is a machined collar set into the same curved left face.
    a=path('M54 31.5 Q62 26.7 72.7 31.1 C81.2 35 82 44.1 76.3 52.2 Q70 61.4 62 60 C54.4 59.1 49.6 51.1 50.8 41.3 Q51 35 54 31.5Z','url(#dark)',sw=.6)
    a+=path('M55.2 34 Q61.9 29.2 70.1 33.4 C77.7 37.8 77.7 44.9 71.5 51.9 Q65.4 58.2 60.8 55 C54.7 52.4 52.2 42 55.2 34Z','url(#metal)',sw=.45)
    a+=path('M57 35.9 Q62.3 32.1 67.7 35.2 C73 38.1 71.6 44.8 66.2 50.9 Q61.9 54.6 58.7 50.6 C55.3 47 54.7 40.5 57 35.9Z','url(#podSocket)',sw=.45)
    a+=line('M53.7 38 Q52.6 46.1 57.9 53.4 M57 33 Q63.9 30.5 70.1 34.2','#6e786f',.48)
    a+=line('M62.2 58.7 Q71.3 59.4 77.2 47.2','#202923',1)
    s+=group('integrated_oval_sensor_collar',a)
    # Narrow exposed face: cast perforated neck, with rounded pockets rather
    # than a shield outline. Three collar ribs wrap round its right edge.
    a=path('M83.1 35.8 Q88.2 33 94.3 35.1 Q99.4 36.3 99.8 41.2 L97.5 46.4 Q98.2 50.4 95.2 53.6 L94.7 59.4 91 64.1 Q88 64.5 85.8 61.1 L84 55.8 84.7 50.8 Q80.7 47 80.9 42.4Z','url(#silver)',sw=.45)
    a+=path('M84.1 37.8 Q89.1 35.7 94.7 37.4 L94.9 40.1 90.6 39.6 85.5 41.2 83.7 40Z','#6c756c',stroke='none',sw=0)
    a+=ellipse(92,43,2.2,1.65,'#111711',sw=.35,extra='transform="rotate(-24 92 43)"')
    a+=ellipse(89.4,50.7,2.1,1.6,'#111711',sw=.35,extra='transform="rotate(-24 89.4 50.7)"')
    a+=line('M90.4 41.9 Q92.5 40.6 94 42 M87.9 49.8 Q89.7 48.3 91 49.8','#b7bfb2',.35)
    a+=path('M87.5 57.7 Q90 55.9 93.2 56.7 L92 60.9 90.3 62.2Z','#596358',stroke='none',sw=0)
    a+=path('M98.9 42.1 Q105.1 43.8 110.8 49.7 Q113.5 55.6 108 61.6 L100.3 64.3 95.5 60.7 98.4 54.6Z','url(#dark)',sw=.35)
    for d in [
        'M99.4 42.8 L102.4 44.3 Q105.3 49.4 98.4 57.1 L95.4 58.7 96.7 55.1 Q102.1 48.4 99.4 44.5Z',
        'M103 44.4 L106.2 46.7 Q109 51.1 102 60.3 L98 62.5 98.9 59.6 Q105.7 52.3 103 46.1Z',
        'M107 47.5 L110.1 49.8 Q113.8 54.5 106.8 62.1 L101.8 64 100.5 62.8 Q110 56.7 107 49.1Z']:
        a+=path(d,'url(#silver)',sw=.38)
    a+=line('M100.8 44.3 Q104 49.5 97.5 56.9 M104.9 46.8 Q107.6 51.6 101.1 59.8 M108.9 49.7 Q112 54.6 105.2 61.6','#9ca48e',.4)
    a+=path('M80.7 58.7 Q85.2 62.3 88.1 65.5 Q91.8 67.7 96.4 66.8 L98.2 69.3 Q94.8 73.7 89.8 74.4 Q82.9 72.7 78.7 67Z','url(#metal)',sw=.4)
    a+=line('M81 62.9 Q86.4 68.9 94.5 69.4','#88927f',.6)
    s+=group('cast_neck_plate_and_wrapped_collars',a)
    # Three-lobed inspection hubs remain whole, seated in complete round rims.
    for name,cx,cy,rx,ry,rot in [('upper',126.8,17.3,5.9,9.3,-39),('lower',125.8,49.1,7.4,9.4,-20)]:
        a=ellipse(0,0,rx+.5,ry+.5,'#080d0a',sw=.45)
        a+=ellipse(0,0,rx,ry,'url(#metal)',sw=.4)
        a+=ellipse(-.15,.1,rx-.85,ry-.9,'#111a12',sw=.3)
        segments=''
        segments+=path('M-.7 .5 Q-4.8 -1 -5.2 -5.2 Q-3 -8.9 1.4 -8 L.6 -2.1Z','url(#silver)',sw=.35)
        segments+=path('M.5 -1.2 L2.5 -7.7 Q6.5 -5.9 6.8 -1.9 L4 2.3 1.5 1.5Z','url(#metal)',sw=.35)
        segments+=path('M-.4 1.5 L2.2 2.1 4.1 4.1 Q1.6 7.8 -2.8 7.8 L-5.4 5.3 -3.7 2.7Z','url(#silver)' if name=='upper' else 'url(#metal)',sw=.35)
        a+=f'<g transform="scale({(rx-.9)/7.2} {(ry-.9)/9})">{segments}</g>'
        a+=ellipse(-.45,.6,.9,1.15,'#535f4d',sw=.3)
        a+=line(f'M{-rx*.7} {-ry*.45} Q{-rx*.3} {-ry*.92} {rx*.25} {-ry*.82}','#aeb7a4',.42)
        # A thin shadow folds the lower cap into the shell instead of a thick bright ring.
        if name=='lower':a+=path(f'M{rx*.65} {-ry*.4} Q{rx+.8} {ry*.2} {rx*.55} {ry*.75} L{rx*.15} {ry*.89} Q{rx*.55} {ry*.1} {rx*.65} {-ry*.4}Z','#101810',stroke='none',sw=0)
        s+=group(f'{name}_oblique_radially_divided_inspection_cap',a,f'transform="translate({cx} {cy}) rotate({rot})"')
    # Slim flanking members; supported spans stay genuinely transparent.
    a=path('M48.8 47.7 Q52.5 46.8 52.4 49.9 L47.2 59.9 43.3 70.1 43.9 73.3 41.7 74.9 40.6 69.9 Q42.8 58 48.8 47.7Z','url(#metal)',sw=.5)
    a+=line('M49.4 49.4 Q45 57 42.4 68.1','#a3ad9a',.65)
    a+=path('M49.3 58.6 L54 57.9 56 60.7 52.8 64.4 47.2 65 46.7 63Z','url(#metal)',sw=.4)
    a+=line('M49.7 59.7l3.2-.3 M48.4 63.5l3.4-1.2','#9ca692',.4)
    s+=group('slender_flank_linkage',a)
    # Collapsed lower supports are open triangular linkages, with cylinders and
    # small feet. Distinct tube paths preserve the reference negative spaces.
    a=''
    # left near support, leaning right from the shoulder
    a+=tube(55,73.7,46.7,83.1,1.6)+tube(55,73.7,60.8,84.6,1.6)+tube(48.2,83.5,60.8,84.6,1.2)
    a+=tube(55.5,75.6,55.9,82.4,1.2)+pin(55.2,74.3,1.1)+pin(59.7,84.5,1.15)
    a+=tube(51.9,84.8,47.1,92.7,1.6)+tube(59.1,85.1,56.4,96.5,1.5)
    a+=path('M46.4 91.1 L49.4 91.9 48 95.2 44.4 97.3 43.4 96.2Z','url(#metal)',sw=.4)
    a+=path('M55.3 94.9 L58.4 95.5 56.8 99.3 53 99.5 52.9 97.3Z','url(#dark)',sw=.4)
    # middle A-frame, two tubular edges around an open center
    a+=tube(76.4,69.8,87.4,86.1,1.85)+tube(76.4,69.8,74.7,85.2,1.75)+tube(74.7,85.2,87.4,86.1,1.15)
    a+=tube(78.7,74,85.3,83.6,.9)+pin(76.6,70.7,1.1)+pin(75,85.5,1.15)+pin(87,86.5,1.1)
    a+=tube(75,86.5,67.1,94.1,1.5)+tube(86.4,87.5,85.9,94.7,1.65)+tube(85.9,94.7,88.5,101.1,1.65)
    a+=path('M65.8 92.8 L69 94.1 67.8 96 63.8 96 63.2 94.7Z','url(#metal)',sw=.4)
    a+=path('M85.6 99.8 L89.1 100.1 89.2 103 85.9 102.5 83.6 100.6Z','url(#dark)',sw=.4)
    # right-side support: narrow twin rails from shell mount to the knee.
    a+=tube(148.9,63.7,159.7,78.7,1.9)+tube(146.7,67,150.5,78.5,1.7)+tube(150.5,78.5,159.7,78.7,1.15)
    a+=tube(151.3,66.8,160.9,77,.8)+pin(149.1,64.6,1.15)+pin(151.4,79.1,1.2)+pin(160.3,79.1,1.2)
    a+=tube(159.3,81.2,158.4,87.4,1.7)+tube(158.4,87.4,161.8,93.5,1.55)
    a+=tube(149.8,79.2,144.2,85.9,1.45)
    a+=path('M162.3 79.3 Q168.3 78.6 174.8 82.2 L182.9 88.2 182 91.8 173 91.1 165 87.6Z','url(#dark)',sw=.55)
    a+=path('M166.8 82 L173.3 83.5 180.3 89 174 87.8 169.9 86Z','url(#metal)',sw=.3)
    a+=path('M159.9 91.9 L163 92.2 162.7 95.5 160.1 95.9 157.7 92.8Z','url(#metal)',sw=.4)
    a+=line('M69.5 91.4 Q72.5 88.5 73.8 91.3 M79.7 89.5 Q83 86.8 83.8 90.5 M152.8 83.4 Q148.7 83.3 146.2 88','#59644e',.55)
    a+=line('M55.7 78.8L55.9 81.7','#4e5b49',2.5)+line('M55.5 78.7L55.7 81.6','#a7b29c',.55)
    a+=line('M78.3 76L82 81.4','#53604a',2.4)+line('M78 75.9L81.7 81.3','#aeb8a2',.5)
    a+=line('M152.3 70L156.1 75.3','#526047',2.4)+line('M152 69.9L155.8 75.2','#b3bca6',.5)
    a+=path('M53.7 82.2 L57.6 82.1 59 84.2 57.5 86 54 85.3Z','url(#metal)',sw=.35)
    a+=path('M73.4 84.2 L77.2 84.7 78.4 87 75.4 88.1 73.1 86.9Z','url(#metal)',sw=.35)
    a+=path('M157.9 77.8 L161.7 78.1 163 80.9 160.8 82.4 158 81.3Z','url(#metal)',sw=.35)
    s+=group('open_triangular_supports_and_small_jointed_feet',a)
    return s

def wheel(name,cx,cy,rx,ry,rot,depth=2):
    """Concentric ellipses in one local plane keep rim, hub and holes coaxial."""
    a=ellipse(-depth,0,rx,ry,'url(#rubber)',sw=.7)
    a+=ellipse(0,0,rx,ry,'url(#rubber)',sw=.65)
    a+=ellipse(0,0,rx-2.8,ry-3.1,'url(#silver)',sw=.45)
    a+=ellipse(.05,.1,rx-4.3,ry-4.7,'url(#wheel)',sw=.45)
    # A narrow recessed ring separates the actual disk from its outer rim.
    a+=ellipse(.05,.1,rx-4.7,ry-5.1,'none','#29312c',.45)
    disk=''
    for ang in [0,120,240]:
        disk+=path('M-5.7 -11.3 Q-.6 -15.3 5.2 -12.5 L5 -9.4 Q-.4 -11.1 -4.7 -8.2Z','#131b15',sw=.45,extra=f'transform="rotate({ang})"')
        disk+=line('M-5 -11.6 Q-.4 -14.2 4.2 -12.6','#b2b9ad',.35,extra=f'transform="rotate({ang})"')
    a+=f'<g transform="scale({(rx-4.7)/18} {(ry-5.1)/18})">{disk}</g>'
    a+=ellipse(0,0,(rx-4.7)*.27,(ry-5.1)*.27,'url(#metal)',sw=.45)
    a+=ellipse(0,0,(rx-4.7)*.18,(ry-5.1)*.18,'url(#silver)',sw=.4)
    a+=ellipse(0,0,(rx-4.7)*.07,(ry-5.1)*.07,'#202820',sw=.3)
    for deg in [17,64,111,158,205,252,299,346]:
        t=math.radians(deg);x=(rx-5.7)*math.cos(t);y=(ry-6)*math.sin(t)
        a+=ellipse(x,y,.52,.67,'#202820',sw=.16)
    a+=path(f'M{-rx+1.5} -2 C{-rx+1.3} {-ry*.68} {-rx*.4} {-ry+1} 0 {-ry+1}','none','#5b655c',.5)
    a+=path(f'M{-rx+3.6} -3 C{-rx+3.6} {-ry*.67} {-rx*.35} {-ry+4.2} 0 {-ry+4.1}','none','#b0b8aa',.5)
    for deg in range(0,360,22):
        t=math.radians(deg);x=rx*math.cos(t);y=ry*math.sin(t)
        xx=(rx-2.1)*math.cos(t+.035);yy=(ry-2.1)*math.sin(t+.035)
        a+=line(f'M{x:.2f} {y:.2f}L{xx:.2f} {yy:.2f}','#080d09',.65)
    return group(name,a,f'transform="translate({cx} {cy}) rotate({rot})"')

def motorcycle():
    s=defs()
    s+=wheel('partly_occluded_far_wheel',21,56.9,18,15,-19,1.2)
    # The torn seat is one shallow padded form with a thin support stem.
    a=path('M30.2 1.1 Q40.5 3.5 49.3 9 Q53.4 11.1 54.5 15.3 L51.4 17.1 Q43.4 14.4 33 13.4 L29.2 11.7Z','url(#dark)',sw=.65)
    a+=path('M31.4 3.1 Q41.5 5.9 48 10 L50.2 12.9 Q41 10.9 31 10.1Z','url(#metal)',stroke='none',sw=0)
    a+=line('M31 5 L38 7.1 M32 8l10 3','#424b42',.4)
    a+=path('M41.2 14.6 L44.6 15.2 48 21.1 45.5 22.6 42.6 18.4Z','url(#silver)',sw=.4)
    a+=tube(38.4,18.3,48.8,21.8,1.65)+tube(48.8,21.8,64.7,17.1,1.8)
    a+=path('M64.7 15.9 Q72 15 78 17.8 L81.2 23.4 78.4 27.6 74.6 25.2 73.1 21.5 66 20.5Z','url(#dark)',sw=.5)
    a+=tube(28,28,34.2,30.1,1.3)+tube(34.2,30.1,43.4,26.3,1.3)
    a+=line('M29 27.5l-1.7-1.4','#b9c0b2',.8)
    s+=group('seat_stem_handlebar_and_rear_attachment',a)
    # The engine is a coherent crankcase below an open frame triangle.
    a=path('M64 45 Q70 43.6 77 45 L86 46 97 43.8 109 41.8 120.8 40 Q126.8 42 129 46.1 L129.2 57.6 Q128 64 121 66 L108 67 94 65.4 Q86 68.3 77 67.4 L69 64.8 65.4 58.5Z','url(#dark)',sw=.65)
    a+=path('M69.6 48 Q75 44.3 80.8 48.2 L83 56.8 Q79 62.1 72.9 58.5 Q68.7 54.8 69.6 48Z','url(#metal)',sw=.5)
    a+=ellipse(76.9,52.9,4.7,5.8,'url(#metal)',sw=.45)+ellipse(76.8,52.9,2.5,3.2,'#151e18',sw=.4)
    a+=path('M85.3 48.6 Q92.8 44.3 98.6 48.1 L102 51.3 101 59 Q95.7 63.7 87 61.2 Q82.9 58 83.6 52Z','url(#metal)',sw=.5)
    a+=ellipse(92,54,5.6,6.1,'url(#dark)',sw=.4)+ellipse(92,54,3.6,4.1,'url(#metal)',sw=.35)
    a+=line('M86 60.5 Q93 63.1 99 59.8','#777f70',.45)
    a+=path('M70 61 Q75 63.9 84.5 63.2 L95.1 64.6 101.6 64.4 101.8 67 87 67 76 66.5Z','url(#dark)',sw=.35)
    a+=path('M100.9 46 L110.7 42.1 120.7 43.3 124.4 47.2 121 63.8 114.4 66 101.1 64.7Z','url(#metal)',sw=.5)
    # Cooling fins are closely spaced and share a cast cylinder behind them.
    for k in range(6):
        y=47.9+k*2.65
        a+=path(f'M101.5 {y} Q109 {y+1.2} 120.4 {y-.9} L120.1 {y+.6} Q109 {y+2.5} 101.2 {y+1.35}Z','url(#silver)',sw=.3)
    a+=path('M104.6 44.8 L110.4 43.7 115.1 46 112.8 48 106.6 47.2Z','url(#metal)',sw=.4)
    a+=line('M101.2 49 L100.6 61.7 M120.3 48.6 L118.2 62.5','#939d8b',.4)
    a+=path('M117.8 39.9 Q124.8 39.1 129 44 L130.6 48.6 125.4 50 120.7 45.8Z','url(#dark)',sw=.45)
    for x,y in [(86.5,50),(97.2,51),(94,59),(74,61),(111,45.6),(124,46.3)]:a+=bolt(x,y,.48)
    s+=group('connected_crankcase_sump_and_finned_cylinder',a)
    # Tubes connect seat tube, steering head, engine mounts and swingarm pivot.
    # Interior triangle stays transparent; there is no large invented panel.
    a=path('M65 16.5 Q74.6 15.6 85.8 18.2 L98.9 20.4 Q107.6 24 113.5 30.8 L123 39.8 121 43.3 112.2 35.1 Q104.5 27.6 97.4 24.1 L84.2 21.5 73.8 20.5 67.4 21.3Z','url(#metal)',sw=.6)
    a+=line('M68 17.4 Q81 16.8 98 21.4 Q109 25.7 120 39.9','#aab2a4',.5)
    a+=path('M73 22.2 L76.6 23.4 79 34.5 78.8 42.1 84.1 46.1 81.8 48.4 75.1 43.3 74.4 33.7Z','url(#metal)',sw=.45)
    a+=tube(82.5,44.9,99.1,42.5,1.65)+tube(99.1,42.5,113.1,41,1.55)
    a+=path('M117.5 32.1 Q125 27.1 135.9 29.4 L138.4 32.9 Q127.7 31.8 121.7 36.2Z','url(#metal)',sw=.4)
    a+=line('M123 30.4 Q130 28.6 135.9 30','#8a9482',.45)
    a+=path('M125.2 35.8 Q131.8 33.8 136 36.8 L138 40.6 133 42 128 40.6Z','url(#dark)',sw=.4)
    a+=line('M56.4 25.1 Q66.8 21.8 78.1 25.2 Q88.4 29.1 95.1 37.6','#202c21',.65)
    a+=line('M91.5 45 Q92.5 40.7 96.9 41.3 M115.2 42 Q119.1 39.5 121.8 40.4','#535e4c',.45)
    s+=group('continuous_open_frame_and_engine_mounts',a)
    # Right wheel has one stable oblique plane with a complete plate and hub.
    s+=wheel('right_concentric_elliptical_disk_wheel',145.1,53.7,15.4,23.2,-42,1.7)
    a=path('M162.2 61.3 L166.3 60.4 168.9 61.8 166.3 66 161.8 68.2 160.5 66.4Z','url(#metal)',sw=.45)
    a+=line('M163.1 61.7L168 61.5','#9aa68f',.5)
    s+=group('source_visible_right_rim_lip',a)
    # The dominant near disk occludes the lower frame, preserving source depth.
    s+=wheel('dominant_front_concentric_disk_wheel',47,47.7,20.8,28.1,36,2.7)
    # A short fork/axle yoke in front of the disk ties the hub back to the frame.
    a=path('M66.5 20.5 Q69.5 21.2 68.3 24.9 L61 37.4 48.8 49.3 44.9 49.0 45.8 46.0 57.5 34.9 63.6 23.2Z','url(#metal)',sw=.45)
    a+=line('M65.4 23.5L59 35.8 47.8 46.8','#969f91',.6)
    a+=pin(47,47.7,2.05)
    a+=path('M28.5 63.4 L31.5 62.4 35.1 65.7 34.1 70.9 31.5 72.1 28.1 68.9Z','url(#silver)',sw=.45)
    a+=line('M29.3 64.6 Q32 65.5 32 69.8','#c1c7b9',.45)
    s+=group('fork_axle_yoke_and_source_lower_rim_fold',a)
    return s

def helicopter():
    s=defs()
    # Minimal opaque backing for the original solid seam under the engine bay.
    s+=group('underbody_seam_backing',path('M118 60 L131 60 131 65.2 118 65.2Z','#192020',stroke='none',sw=0))
    s+=group('continuous_underbody_connection',path('M77 50 Q87 52 99 58 L123 63 141 69 137 80 112 94 91 95 79 92 68 87 69 75Z','url(#shell)',sw=.55)+path('M132 37 L138 33 140.5 41 Q141.4 50 148 59 L158 67.7 144 69.7 128 63.9Z','url(#dark)',sw=.4))
    # Tall fin and tail remain a single tapered airframe volume; small seams
    # follow the underlying curve rather than splitting it into armour plates.
    a=path('M2 1.3 L6.4 4.4 22 40.8 19 45.5 13.3 35.7 10 22.4Z','url(#dark)',sw=.65)
    a+=path('M4.2 4.8 L8 12.1 17.8 37.4 18.6 40.1 15.6 35.3 10.8 22.4Z','url(#metal)',stroke='none',sw=0)
    a+=path('M3 32.1 L7.8 33.4 23 43.3 20.8 46.1 12.8 41.7 6.1 39Z','url(#dark)',sw=.55)
    a+=path('M14.1 41.8 Q22 42.3 31.6 45.6 L48.1 51.1 Q57.6 54.7 64.3 51.9 L80.8 43.5 84.3 57.8 Q77.3 65.6 68.2 69.9 L51.2 70.9 Q37.4 66 27.6 59.5 L16.2 54Z','url(#shell)',sw=.65)
    a+=path('M17 44.5 Q29.3 46.4 42 51.4 Q56.5 57.1 65.7 54 L77.2 49.1 77 56.5 Q68.5 63 57.8 61.1 L38.1 55.9 20.2 52.5Z','url(#metal)',stroke='none',sw=0)
    a+=line('M19 45.5 Q35 49.5 47 53.1 M48.6 54.1 Q56 56.4 62 54.8','#6e7770',.45)
    a+=path('M27.5 55.6 Q33.5 53.3 38.9 57.6 L56.8 64.1 Q68.6 67 80.6 61.9 L88 64.5 87.8 76.7 Q80 84.6 70.2 87.4 L64.7 89.1 Q57.6 84.3 52 80.2 L34.1 67.7 28.8 64.5Z','url(#metal)',sw=.6)
    a+=path('M31.3 57.8 Q34 56.5 38.3 59.5 Q47.2 64.9 57 67.7 Q64 69.7 67.3 69.2 L66.7 81.8 Q62.9 82 57.5 78.6 C47.6 72.4 41.7 67.6 32.5 63.1Z','url(#shell)',stroke='none',sw=0)
    a+=line('M32.4 57.9 Q42.6 63.7 55.9 67.2 Q61.7 69 66.2 68.9','#616c64',.45)
    a+=line('M67.8 68.9 L68.2 81.2 65.7 85.8 M72.1 67.7 Q79 67.7 84.6 64.9 M70.3 83.6 Q78 80.6 84.4 75.5','#0a100d',.6)
    a+=line('M69.2 69.1L69.3 80.9 M70.7 84.8 Q78.3 82.1 84.4 77.4','#525e53',.45)
    a+=path('M20 49.9 Q25 49.1 29 53.6 L25.6 56.5 20.2 54.3Z','#121a15',sw=.35)
    # A small bent open seam is visible at the tail root in the source.
    a+=line('M44.2 53.2 Q48.7 53 51.2 50.3 L55.5 49.9','#858e80',.65)
    s+=group('continuous_tapered_fin_tailbeam_and_lower_shell',a)
    # Rotor blades are absent in the source; retain the existing compact hub.
    a=path('M118.8 25 L120 18.8 117 17.4 119.7 14.5 119.8 9.3 122.2 8.5 123.6 11.1 123.5 14.4 127.5 16.1 125.5 18.8 126.7 24.4Z','url(#dark)',sw=.5)
    a+=path('M113.4 12.5 Q119 10.7 124.5 12 L130.1 13.5 135.8 13.3 134.7 15.4 128.2 15.8 122.3 17 117 15.7 112.5 15.4Z','url(#metal)',sw=.45)
    a+=line('M118.4 12.2 Q121 11.7 124.5 12.6','#9aa095',.4)
    a+=path('M105.4 27 Q113.7 22.4 126.8 23.7 L135.5 26.5 136.5 30.3 105 30.4Z','url(#dark)',sw=.5)
    s+=group('compact_rotor_hub_and_gearbox',a)
    # Engine fairing is a complete enclosure, with shallow recessed service door.
    a=path('M82 28.2 L91.5 27.5 Q109 27.3 122.7 26.7 L135.3 26.7 Q138.9 27.3 139 31.7 L136.3 49.7 Q134 57.5 129 61 L111.1 62.8 94.1 58.6 82 59Z','url(#shell)',sw=.65)
    a+=path('M92.5 30.7 Q105.6 28.7 120.6 29.6 Q123.9 30.2 124 33.4 L122 44.7 Q121.4 48.8 117.4 49.1 L96 48.6 Q92.8 48.4 92.6 45.3Z','url(#metal)',sw=.5)
    a+=path('M96 32.7 Q106 31.2 118.6 32.4 L119.2 35.4 117.4 44.9 96.2 44.2Z','url(#dark)',sw=.35)
    a+=line('M94 31.1 L94.1 45.3 Q94.3 47.3 96.5 47.4 L117.8 47.9','#647063',.5)
    a+=path('M126.3 30.8 L134.2 30.6 135 35.3 131.2 39.1 127 41.3 125.3 48.9 121.9 48.1Z','url(#dark)',sw=.4)
    a+=line('M128 33.3l5.1-1.2 M128.3 36.1l4.2-1.1','#646f60',.5)
    a+=path('M83.4 30.4L89.3 30.2 89.2 54.8 83.4 54Z','url(#dark)',sw=.35)
    for x in [84.8,87.2,89.5]:a+=line(f'M{x} 31.4v20.7','#4c584d',.5)
    for y in [51.5,54.4,57.2]:a+=line(f'M92.6 {y}Q106 {y+1.1} 118.4 {y-.1}','#0a100d',.8)
    for x,y in [(96,34),(118.2,33.4),(96.5,45.4),(119,45.8),(85.1,31.5),(85.1,52.2)]:a+=bolt(x,y,.42)
    s+=group('continuous_engine_fairing_and_service_recesses',a)
    # Curved cockpit perimeter with missing glazing. Only source frame remains.
    a=path('M142 28.5 L148.3 28.5 Q154.6 30.5 159.2 35.9 L171.9 45.8 Q178.6 51.4 180.4 58.7 L180.9 67.6 177.1 72 171.1 69.2 172.2 59 Q168.4 50.4 161.8 44 L154.6 36.6 Q149.8 32.1 142.3 32.2Z','url(#dark)',sw=.6)
    a+=path('M141.5 29.9 L140.2 41.9 Q140.8 49 147.1 58.1 L151.4 60.7 150.4 63.5 145.4 61.8 Q136.8 51 137.5 39.1 L138.1 30.5Z','url(#metal)',sw=.5)
    a+=line('M145.5 30.5 Q151.3 31.3 157.2 36.9 L170.2 47.2','#76816f',.45)
    a+=path('M158.4 36.8 L160.5 39.1 159.9 48.8 160.5 57.2 158.8 58.5 157.3 49.4Z','url(#dark)',sw=.45)
    a+=path('M167.3 52.3 L169.5 56.8 176.7 54.5 178.1 61.8 175.7 68.6 172.7 67 171 60.1Z','#080e0a',sw=.4)
    a+=path('M147.7 60.8 Q157 62.2 167.9 68.2 L176.3 70.2 177.2 73.1 Q166.2 71.8 158.4 68.2 L150.3 66.5Z','url(#silver)',sw=.5)
    a+=line('M149.1 61.7 Q157.6 63.7 166 68.9','#b2b9a8',.65)
    s+=group('curved_cockpit_frame_with_open_glazing',a)
    # Continuous crushed belly and nose. The side intake is shallowly inset in
    # that same body; no separate torus or external cylindrical armour capsule.
    a=path('M82.6 87.6 Q83.2 78.7 92.4 72.5 Q101.2 67 113.5 66.4 L123.7 64.5 Q136.8 63.9 146.2 67.7 L160.9 69.1 Q171.8 69.4 181.8 74.4 C189 75 197.3 78 201 82.4 Q205 87.9 200 92.5 Q193.4 96 181 95.6 L166.4 95 Q154 97.7 140.8 97 L130.4 95.7 117.1 96.6 104.9 94.9 95.9 95.7 84 94.1Z','url(#shell)',sw=.75)
    # Long upper flank remains attached from intake shoulder through nose.
    a+=path('M91.1 76.8 Q98.3 70.3 111.6 69 L124.3 66.5 Q135.4 66 145.2 70.2 L160.2 72.1 Q176.1 72 187.7 78 L193.4 82.5 Q183.5 79.8 174.5 79.4 L150.5 77.8 Q137.4 76.1 126.4 77.7 L108.3 83.2 95.5 84.6Z','url(#metal)',stroke='none',sw=0)
    a+=path('M101 75.4 Q112.8 70.4 123.8 70.4 Q131.1 70.3 135.1 72.1 L131.5 74.9 Q119.8 74.5 108.8 78.7 L103.5 80.6 Q99.2 79.5 101 75.4Z','#080e0b',sw=.45)
    a+=line('M102.1 74.7 Q113.8 70 125.4 71.2','#737f6e',.55)
    a+=line('M103.2 79.8 Q109.7 82.5 121.2 77.6','#1c281c',.65)
    a+=path('M94.4 83.1 Q104.6 85.7 117.1 82.4 L132.4 78.5 Q139.7 77.5 145.8 78.7 L171.7 81.4 Q180.5 82.4 187.4 83.3 L192.6 87.8 Q181.6 93.4 165.3 92.9 L144.4 94.3 Q132.4 92.8 122.7 93.1 L106.6 92.5 98.1 89.7Z','url(#dark)',stroke='none',sw=0)
    a+=path('M137.1 80.1 Q145.8 78.1 157.7 81 L174.5 82.6 176.2 89.5 Q165.1 92.4 151.2 92 L138.5 92.2Z','url(#metal)',sw=.45)
    a+=line('M140.1 80.4 Q152.1 80.6 161.2 82.2 L171.7 83.1','#6e7a69',.45)
    a+=line('M139.3 90.6 Q150.7 92.3 173.8 89.3','#59674e',.45)
    for x,y in [(143,83.4),(150.6,84.5),(155.2,84.8)]:a+=bolt(x,y,.5)
    for x in [159.5,163,166.5,170]:a+=path(f'M{x} 85.3q1-.2 1 .7l-.3 3.2-1.1 .1Z','#080f09',sw=.25)
    a+=path('M176.7 76.1 Q180.3 77.4 184.4 82.1 Q187.3 87.9 182.8 92.6 L176.1 93.5 Q180.4 87.7 176.7 81.4Z','url(#metal)',stroke='none',sw=0)
    a+=line('M178.3 77.7 Q185.7 84.5 182.2 90.1','#7a8672',.55)
    a+=path('M187.9 77.7 Q197.7 79 201.3 84 Q203.1 89.3 199.2 91.8 L190.9 94 Q195.4 88.4 191.8 83Z','url(#dark)',stroke='none',sw=0)
    a+=line('M200.6 84.8 Q202 89 197.8 91.1','#687661',.45)
    a+=path('M99.7 91.6 L113.9 92.2 121.9 95.3 131.4 94.3 132 97.1 119.5 97.3 109.4 95.3 101 95.9Z','url(#dark)',sw=.4)
    a+=path('M133.4 89.4 L136.3 89.6 137.3 95.8 136 97.1 132.7 96.9Z','url(#metal)',sw=.35)
    a+=path('M84.4 85.4 Q87.2 82.7 90.8 82.4 L92.1 86.3 87 92.2 84.5 91.3 86.5 87.6Z','url(#metal)',sw=.4)
    a+=line('M96.4 85.9 L97.4 91.1 M99.4 88.3 Q107.2 90.9 114.1 88.4','#63725a',.5)
    # A few shallow compressed seams where the original actually folds.
    a+=line('M146 85.8 Q149.6 84 152.1 86.2 Q156.3 87 158.3 86 M117.2 92.6 Q121 91.3 126.4 93 M171.9 79.5 L174.5 80.4','#152014',.5)
    s+=group('single_compressed_belly_with_integrated_intake_and_nose',a)
    a=line('M130.4 41.2 Q129 47 123.1 48.2 L121.6 55.1 Q120.5 59.8 116.4 63.4','#77846d',1.2)
    a+=line('M129.4 41.7 Q128 46.4 122.4 47.7 L120.7 55.6','#182713',.45)
    a+=line('M88.1 74.5 L86.7 80 87 84.2 M178.6 73 L183.4 72.7 187.3 75','#42533a',.45)
    s+=group('source_exposed_hose_and_small_seams',a)
    return s

BUILDERS={1606:motorcycle,1607:helicopter,1608:pod,1609:excavator}
def finalize_palette(s,i):
    if i==1609:return s
    import re
    def neutral(m):
        h=m.group(0)[1:];r,g,b=[int(h[k:k+2],16) for k in (0,2,4)];y=round(.2126*r+.7152*g+.0722*b)
        # Reference 1606/1608 are neutral metal; no unintended green cast.
        return '#'+('%02x'%y)*3
    return re.sub(r'#[0-9a-fA-F]{6}',neutral,s)

def make_preview(i):
    w,h=SIZES[i]
    render(ROOT/f'parts/bitmap-{i}.svg',w*6,ROOT/f'previews/wreck-{i}-new.png')
    render(ROOT/f'parts/bitmap-{i}.svg',w,ROOT/f'previews/wreck-{i}-native.png')
    orig=Image.open(REF/f'{i}.png').convert('RGBA').resize((w*6,h*6),Image.Resampling.LANCZOS)
    new=Image.open(ROOT/f'previews/wreck-{i}-new.png').convert('RGBA')
    comp=Image.new('RGBA',(w*12+30,h*6+50),(30,35,32,255));d=ImageDraw.Draw(comp)
    comp.alpha_composite(orig,(10,35));comp.alpha_composite(new,(w*6+20,35))
    label='R3 / BLADE REVISION' if i==1609 else 'R2 / CONTINUOUS MECHANICAL VOLUMES'
    d.text((10,10),'ORIGINAL',fill='#c5c9bd');d.text((w*6+20,10),label,fill='#c5c9bd')
    comp.save(ROOT/f'previews/wreck-{i}-comparison.png')

def main(ids):
    (ROOT/'previews').mkdir(parents=True,exist_ok=True)
    for i in ids:
        if not (REF/f'{i}.png').is_file():raise FileNotFoundError(f'Missing retained reference: {i}.png')
        write_part(ROOT/f'parts/bitmap-{i}.svg',(0,0,*SIZES[i]),finalize_palette(BUILDERS[i](),i))
        make_preview(i)
    print('Rebuilt native SVG props:',', '.join(map(str,ids)))
if __name__=='__main__':main(list(map(int,sys.argv[1:])) or list(BUILDERS))
