#!/usr/bin/env python3
"""CF6 stage 5: editable botanical carpet and oil-flower picture reconstruction.

Artwork is regenerated from authored vector geometry, named layers, gradients,
and deterministic hairline material marks. Original files supply ONLY the rug's binary alpha silhouette. No original RGB
bitmap, quantized color-region tracing, or upscaled RGB fragment is embedded in
visible artwork. Floral placements and carving are reference-informed,
not an assertion that the historical pattern has been recovered stitch by stitch.

The carpet design is authored on a 660 x 250 design plane and projected ONCE to
its already established 901 x 145 native asset footprint. The original bitmap is
never transformed. Consumers should position this native SVG without a further
perspective operation.

Run: python source/decor.py
Writes ONLY parts/bitmap-1742.svg, parts/bitmap-1743.svg, previews/decor-*, qa/decor-*.
"""
from pathlib import Path
from math import sin, cos, pi
import base64, io, random, json, subprocess
from PIL import Image, ImageDraw
import numpy as np
from svg_native import write_part, render

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'parts'; PRE=ROOT/'previews'; QA=ROOT/'qa'
for d in [OUT,PRE,QA]: d.mkdir(exist_ok=True,parents=True)

def use(name,x=0,y=0,s=1,r=0,sx=None,sy=None,opacity=None):
    op='' if opacity is None else f' opacity="{opacity}"'
    if sx is None: sx=s
    if sy is None: sy=s
    return f'<use href="#{name}" transform="translate({x:.4f} {y:.4f}) rotate({r:.4f}) scale({sx:.4f} {sy:.4f})"{op}/>'

def path(d,fill='none',stroke=None,sw=None,other=''):
    a=f'<path d="{d}" fill="{fill}"'
    if stroke: a+=f' stroke="{stroke}"'
    if sw: a+=f' stroke-width="{sw}"'
    return a+' '+other+'/>'

def circ(x,y,r,fill,other=''):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" {other}/>'

def ellipse(x,y,rx,ry,fill,stroke=None,sw=None,other=''):
    a=f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}"'
    if stroke: a+=f' stroke="{stroke}"'
    if sw: a+=f' stroke-width="{sw}"'
    return a+' '+other+'/>'

def botanicals(p):
    # Each named flower has a designed silhouette and petal fold system.
    defs='''<linearGradient id="leafLight" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#92946d"/><stop offset=".45" stop-color="#656c4a"/><stop offset="1" stop-color="#343e31"/></linearGradient>
    <linearGradient id="ivoryLeafPaint" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#e2d9ad"/><stop offset=".42" stop-color="#bdb783"/><stop offset="1" stop-color="#7e8256"/></linearGradient>
    <radialGradient id="roseRed"><stop stop-color="#692a24"/><stop offset=".5" stop-color="#b45c46"/><stop offset=".78" stop-color="#aa6b51"/><stop offset="1" stop-color="#7d3d2d"/></radialGradient>
    <linearGradient id="rosePetal" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#c88971"/><stop offset=".45" stop-color="#ae5f4b"/><stop offset="1" stop-color="#74362f"/></linearGradient>
    <radialGradient id="creamRose"><stop stop-color="#b59b61"/><stop offset=".65" stop-color="#e1d5a1"/><stop offset="1" stop-color="#9a996b"/></radialGradient>
    <g id="greenLeaf">'''
    leaf='M0 0 C-2.7-2.4-4.3-6.2-3.8-10.1 C-1.2-9.9 2.8-8.6 3.2-5.4 C3.6-3 1.5-.8 0 0Z'
    defs+=path(leaf,'url(#leafLight)')+path('M0-.2 C-.4-2.9-1.4-6.2-3.8-10.1','none','#b2b28a',.32)
    for yy in [-2.2,-4.2,-6.1]:
        defs+=path(f'M{-0.12+yy*.20:.2f} {yy} q-1.4-.8-2.1-2 M{-0.12+yy*.20:.2f} {yy} q1.8-1 2.3-2','none','#303e33',.20)
    defs+='</g><g id="ivoryLeaf">'+path(leaf,'url(#ivoryLeafPaint)','#72764d',.24)+path('M0 0 C-.4-2.9-1.4-6.2-3.8-10.1','none','#eee2ad',.40)+'</g>'
    # Directed elongated acanthus lobe, for woven ornament and carved frames.
    ac='M0 0 C-4.3-2-9.7-5.6-11.2-10.9 C-11.8-13.3-10.6-16.5-8.6-18.8 C-9.3-15.7-8.2-14.1-6.5-12.6 C-7.1-16.2-5.5-19.7-2.3-22.1 C-3.6-18.6-2.8-15.8-.7-13.7 C-.6-17.1 1.4-19.1 4.3-20.1 C2.7-17.5 3.1-15.2 5.6-13.5 C8.2-11.9 9.8-9.9 9.8-7.5 C6.9-9.8 5.8-10.5 3.8-9.5 C6.2-7.6 6.7-5.4 6.1-3.5 C4.1-5 2.2-5.4.6-4.6 C1.2-3.3 1-1.4 0 0Z'
    defs+='<g id="acanthus">'+path(ac,'#b7b17d','#6e704a',.50)+path('M0 0 C-1-5-3-10-2.4-19 M-2-8 Q-7-8-9.5-13 M-1-5 Q3-7 6.1-6.5 M-3-12 Q1-14 4-15','none','#e0d6a0',.65)+path('M-2-8 Q-5-10-5-14 M-1-5 Q2-7 3-11','none','#85865a',.42)+'</g>'
    defs+='<g id="rose">'
    # Uneven overlapping petals establish a botanical, not circular-badge, center.
    for j in range(9):
        angle=j*40+8
        pet='M-1.6-1.2 C-6.2-2.5-8-5.5-5.8-7.8 C-3.2-10.3 1.7-8.5 4.6-6.7 C5.9-4.5 3.7-1.5 1.2-.2Z'
        defs+=f'<g transform="rotate({angle})">'+path(pet,'url(#rosePetal)','#8c5a41',.14)+path('M-5.8-7.6 Q-1.7-9.4 3.6-6.8','none','#d8aa7a',.42)+'</g>'
    for j in range(6):
        defs+=f'<g transform="rotate({j*60+14}) scale(.63)">'+path('M-1 0 C-5-1-6.5-3.5-4.7-6 C-2.5-7.4 1.5-6.6 3.3-4.7 C3.4-2.2 1.8-.8-1 0Z','#b77853','#996747',.22)+path('M-4.6-5.9 Q-1-7 2.8-4.9','none','#d9a97a',.55)+'</g>'
    for angle in [11,53,94,137,181,224,268,312]:
        defs+=f'<g transform="rotate({angle})">'+path('M-3.7-6.8 Q-2.1-5.6-.6-4.8 M-2.4-7.7Q-1.1-6.5.4-5.6 M.1-7.1Q1-6.1 1.4-5.2','none','#e2b68a',.17,other='opacity=".7"')+path('M-4.3-6.7Q-3-5.4-2.9-4.7','none','#754b3a',.18,other='opacity=".6"')+'</g>'
    defs+=path('M-2.6-1.2 Q-3.4-4.3-.3-4.1 Q3.1-3.4 2-1 Q.8.6-1.3-.3 Q-2.1-1.1-.4-2.1','none','#63382c',.85)+path('M-2.5-2.9 Q-.4-4.6 1.8-2.4','none','#e2b17a',.52)+'</g>'
    defs+='<g id="whiteRose">'
    for j in range(10):
        defs+=f'<g transform="rotate({j*36+9})">'+path('M-1 0 C-4.5-1.7-5.8-4.5-4.1-6.8 C-1.9-8.9 1.4-7.5 3.8-5.7 C4.5-3.2 2.1-1.3-1 0Z','url(#creamRose)','#9da17a',.14)+path('M-4-6.7 Q-.6-8.5 3.3-5.7','none','#ebe2bb',.4)+'</g>'
    defs+=path('M-2-2 Q-.4-4 1.3-2 Q2.3 0-.3.4 Q-2.3 0-1-1.6','none','#8c7548',.8)+circ(.1,-1,.6,'#c9b77e')+'</g>'
    defs+='<g id="blueFlower">'
    for j in range(5):
        defs+=f'<g transform="rotate({j*72})">'+path('M0 0 C-4-2-4.1-5.1-1.2-6.4 C1.2-7 3.4-4.7 2.5-2.6Z','#8d9b9a','#3c5352',.24)+path('M.2-1 L-.3-5.1','none','#c1c9b6',.4)+'</g>'
    defs+=circ(0,0,1.2,'#b29c5f')+circ(-.35,-.3,.4,'#e5d6a3')+'</g>'
    defs+='<g id="smallFlower">'
    for j in range(5):
        defs+=f'<g transform="rotate({j*72})">'+path('M0 0 C-2.6-1.5-3-3.7-.8-4.3 C1-4.4 2.4-2.9 1.7-1.5Z','#dfd5a5','#8b8557',.24)+'</g>'
    defs+=circ(0,0,.8,'#ad7443')+'</g>'
    # Botanical branch used in coherent arranged bouquets.
    defs+='<g id="sprig">'+path('M0 0 Q-1-13 5-28','none','#737649',.75)
    for x,y,r,s in [(-.4,-3,-60,.9),(0,-6,65,.8),(1,-10,-43,.8),(1.7,-15,62,.65),(3.2,-20,-30,.6)]: defs+=use('greenLeaf',x,y,s,r)
    defs+=use('smallFlower',5,-27,.65)+use('smallFlower',-.8,-19,.45)+use('smallFlower',6.3,-16,.5)+'</g>'
    # A fully drawn S-scroll with leaves along its changing direction.
    defs+='<g id="scrollSpray">'+path('M0 0 C11-2 22-4 24-12 C26-20 14-23 13-16 C12-10 22-10 27-16 C32-23 39-21 42-16','none','#8d8b57',1.2)+path('M0-.7 C11-3 21-5 23-12 C25-18 16-21 14-16','none','#dbd1a0',.65)
    for x,y,s,r in [(7,-2,.7,-70),(12,-4,.65,45),(22,-12,.55,35),(29,-18,.6,-28),(37,-20,.45,65)]: defs+=use('ivoryLeaf',x,y,s,r)
    defs+=use('acanthus',3,0,.45,-70)+use('smallFlower',42,-16,.55)+'</g>'
    # Continuous botanical lace tile: entwined stems, curled terminal, paired
    # leaflets, and curved offshoots. It is a woven vine, not a dotted fill.
    defs+='<g id="laceVine">'
    defs+=path('M-2 0 C5-1 5-7 12-7 C20-7 19 4 27 3 C34 2 33-8 41-8 C48-8 49 0 57 0 C62 0 63-5 67-6','none','#9e986b',.7)
    defs+=path('M6-4 C2-8 4-14 9-13 C13-13 14-9 11-8 C9-7 7-9 9-10 M22 1 C19 6 22 12 27 11 C31 11 32 7 29 6 C27 5 25 7 27 8 M38-7 C35-13 40-17 44-14 C47-12 44-9 42-11','none','#b5ab76',.50)
    defs+=path('M0-.6 C6-2 6-7.8 12-7.8 M30 1 C34-2 34-7 40-8.7 M45-6 C49-3 50 1 57 1','none','#d3c494',.27)
    for x,y,r,sc in [(1,-1,-48,.60),(6,-5,54,.58),(13,-7,-35,.65),(17,-4,85,.60),(23,2,-72,.70),(28,2,70,.63),(34,-2,-56,.61),(40,-8,40,.59),(47,-5,-33,.62),(53,-.5,55,.65),(60,-2,-38,.58)]:defs+=use('ivoryLeaf',x,y,sc,r)
    defs+=use('acanthus',17,-3,.38,92)+use('acanthus',49,-3,.36,86)+use('ivoryLeaf',25,4,.70,160)+use('ivoryLeaf',45,-5,.67,-130)
    defs+='</g>'
    # Bouquet structure: all flowers belong to painted stems and leaves.
    defs+='<g id="rugBouquet">'
    for x,y,r,s in [(-52,8,-55,1.1),(-32,17,-15,1.3),(-9,18,23,1.5),(25,15,51,1.2),(48,9,70,1.0),(-64,7,-78,.8),(63,8,72,.8)]: defs+=use('sprig',x,y,s,r)
    for x,y,r,s in [(-43,3,62,1),(-31,-7,-40,.9),(-16,4,30,1.1),(4,-7,-30,1.4),(20,2,24,1.1),(43,4,-48,1.0),(-4,14,92,1.1),(28,13,72,.8)]: defs+=use('greenLeaf',x,y,s,r)
    for x,y,s,r,n in [(-46,-5,.72,20,'whiteRose'),(-28,-3,.85,-20,'rose'),(-8,-15,1.1,23,'rose'),(13,-5,.8,12,'whiteRose'),(29,-12,.7,45,'rose'),(48,-2,.7,-10,'whiteRose'),(-11,8,.63,0,'blueFlower'),(7,11,.72,-22,'rose'),(29,7,.5,17,'blueFlower'),(-35,11,.5,15,'smallFlower'),(61,4,.6,21,'smallFlower'),(-64,0,.55,33,'smallFlower')]: defs+=use(n,x,y,s,r)
    defs+='</g>'
    return defs

def original_alpha():
    im=Image.open(ROOT/'reference/bitmap-1742-original.png').convert('RGBA')
    a=im.getchannel('A'); m=Image.new('RGBA',im.size,(255,255,255,255)); m.putalpha(a)
    f=io.BytesIO();m.save(f,format='PNG')
    return base64.b64encode(f.getvalue()).decode()

def carpet():
    defs=botanicals('rug')+'''
    <linearGradient id="woolRed" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#630b20"/><stop offset=".33" stop-color="#741025"/><stop offset=".66" stop-color="#6b0c23"/><stop offset="1" stop-color="#640b21"/></linearGradient>
    <linearGradient id="ivoryField" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#bfbfa0"/><stop offset=".46" stop-color="#cecbaa"/><stop offset="1" stop-color="#b5b693"/></linearGradient>
    <linearGradient id="goldBand" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#b7a16b"/><stop offset=".4" stop-color="#d3c28e"/><stop offset=".62" stop-color="#aa935d"/><stop offset="1" stop-color="#d2c18b"/></linearGradient>
    <clipPath id="rugFlatClip"><path d="M0 0H660V250H0Z"/></clipPath>
    '''
    defs+=f'<mask id="nativeOriginalAlpha" maskUnits="userSpaceOnUse" x="0" y="0" width="901" height="145"><image x="0" y="0" width="901" height="145" href="data:image/png;base64,{original_alpha()}"/></mask>'
    s='<title>CF6 1742 red floral carpet, native perspective</title><desc>Editable reference-informed botanical reconstruction; original alpha only is retained as a silhouette mask. Visible detail is authored botanical vector art.</desc><defs>'+defs+'</defs>'
    s+='<g id="carpet-native-extent" mask="url(#nativeOriginalAlpha)"><path d="M0 0H901V145H0Z" fill="#680d23"/><g id="single-native-projection" transform="matrix(1 0 .964 .58 0 0)" clip-path="url(#rugFlatClip)">'
    s+='<g id="wool-ground">'+path('M-2-2H663V253H-2Z','url(#woolRed)')+'</g>'
    s+='<g id="woven-outer-borders">'
    s+=path('M21 13H639V237H21Z','none','#a39363',8.5)
    s+=path('M21 13H639V237H21Z','none','#c3b684',5.7)
    s+=path('M21 13H639V237H21Z','none','#a99b6c',3.4)

    for x,y,w,h,c,sw in [(14,7,631,235,'#a59a65',2.8),(18,10,623,229,'#d2c28a',1.3),(23,14,613,221,'#6b613e',1.3),(26,16,607,217,'#b3a374',2.1),(30,18,599,213,'#d0c394',.65)]:
        s+=path(f'M{x} {y}H{x+w}V{y+h}H{x}Z','none',c,sw)
    # Cream rolled vines along each border, attached by one continuous tendril.
    for side in [0,1]:
        y=22 if side==0 else 228
        s+=path(f'M40 {y} C160 {y-2} 230 {y+2} 330 {y} S510 {y-2} 620 {y}','none','#d0c69a',.55)
        for x in [75,105,135,165,195,225,255,285,345,375,405,435,465,495,525,555,585]:
            s+=use('scrollSpray',x,y, .74, 0 if side==0 else 180)
    for side in [0,1]:
        x=21 if side==0 else 639
        for y in [48,72,96,120,144,168,192,216]: s+=use('scrollSpray',x,y,.63,90 if side==0 else -90)
    s+='<g id="continuous-border-leaf-lace">'
    for x in range(38,624,22):
        s+=use('laceVine',x,21,.54,0)+use('laceVine',660-x,230,.54,180)
        s+=use('acanthus',x+7,21,.46,-50)+use('acanthus',653-x,230,.46,130)
    for y in range(30,227,19):
        s+=use('laceVine',22,y,.49,90)+use('laceVine',638,250-y,.49,-90)
        s+=use('acanthus',25,y+7,.43,35)+use('acanthus',635,243-y,.43,215)
    s+='</g></g>'
    # Lobed central red reserve is faithful to the long quatrefoil outline.
    outer='M101 43 C96 54 87 54 83 62 C80 67 84 72 75 77 C58 88 57 108 66 121 C59 134 60 151 76 161 C84 167 80 173 87 181 C91 188 100 187 104 197 C152 198 212 197 280 198 C302 198 313 210 332 207 C352 209 363 198 383 198 C447 197 505 199 555 197 C560 187 569 187 574 180 C579 174 576 167 584 161 C600 150 602 135 594 122 C601 109 599 92 585 80 C576 73 580 67 573 60 C567 54 560 54 555 43 C498 41 438 43 380 42 C359 43 350 32 331 34 C310 31 301 43 279 42 C217 42 158 42 101 43Z'
    s+='<defs><clipPath id="lobed-vine-field">'+path(outer)+'</clipPath></defs>'
    s+='<g id="lobed-medallion">'+path(outer,'#711225','#c4b985',4)+path(outer,'none','#827c4e',.85)
    s+='<g id="dense-interlaced-botanical-field" clip-path="url(#lobed-vine-field)" opacity=".63">'
    for row,y in enumerate(range(48,207,16)):
        for col,x in enumerate(range(55,600,36)):
            xx=x+(18 if row%2 else 0)
            s+=use('laceVine',xx,y,.71,0 if row%2==0 else 180)
    s+='</g><g opacity=".64">'
    # Repeating leaf flourishes in the red reserve, not anonymous dots.
    for i in range(34):
        t=i*2*pi/34
        x=330+224*cos(t);y=121+66*sin(t)
        s+=use('scrollSpray',x,y,1.06,180*t/pi+90)
    s+='</g><g id="continuous-scroll-vine-network" clip-path="url(#lobed-vine-field)" opacity=".65">'
    for rx,ry,phase in [(218,70,0),(226,77,.18),(239,65,.1)]:
        points=[]
        for j in range(241):
            t=j*2*pi/240
            rr=rx+5*sin(t*16+phase);hh=ry+3*cos(t*16+phase)
            points.append((330+rr*cos(t),121+hh*sin(t)))
        d='M'+' L'.join(f'{x:.2f} {y:.2f}' for x,y in points)+'Z'
        s+=path(d,'none','#a59d6f',.63)
        for j in range(36):
            t=j*2*pi/36+phase;x=330+rx*cos(t);y=121+ry*sin(t)
            s+=use('ivoryLeaf',x,y,.57,180*t/pi+60)+use('ivoryLeaf',x,y,.45,180*t/pi-75)
    s+='</g>'
    # Small purposeful bouquets at compass positions around the reserve.
    for x,y,sc,rr in [(144,79,.38,-25),(118,122,.38,10),(156,168,.39,20),(243,183,.32,0),(410,183,.34,20),(503,171,.40,-20),(546,122,.37,0),(506,77,.39,12),(411,56,.32,0),(250,56,.32,0)]:
        s+=use('rugBouquet',x,y,sc,rr)
    s+='</g>'
    s+='<g id="oval-medallion-rings" transform="translate(6 24.78) scale(1 .82)">'
    for rx,ry,fill,stroke,sw in [(166,72,'#b5a570','#e1d5a0',2.2),(161,68,'#751b29','#8a8055',1.1),(152,61,'#c5b583','#e1d4a6',1),(145,56,'#d6cd9e','#877f53',1.5),(140,52,'url(#ivoryField)','#4f5941',1.3)]: s+=ellipse(330,121,rx,ry,fill,stroke,sw)
    # Fine gold scrolling chain in the annulus, with outward leaf tips.
    for i in range(42):
        t=2*pi*i/42; x=330+157*cos(t);y=121+64.5*sin(t)
        ang=180*t/pi+90
        s+=use('ivoryLeaf',x,y,.48,ang)+path(f'M{x:.2f} {y:.2f} q2.0-1.6 3.8 0','none','#d5c999',.5)
    s+=use('rugBouquet',331,124,1.50,0)
    for x,y,sc,r in [(272,117,.47,-18),(302,100,.44,11),(345,98,.43,18),(366,110,.42,-17),(396,122,.38,18),(307,143,.42,33),(349,142,.4,18),(377,135,.36,-15)]:
        s+=use('sprig',x,y,.60,r)+use('whiteRose' if x%2 else 'rose',x,y,sc,r)

    # Woven secondary stems soften negative space in central ivory field.
    for x,y,ss,rr in [(229,124,.65,-65),(430,123,.62,73),(282,148,.48,110),(375,147,.45,72),(291,91,.43,-25),(375,94,.46,24)]:s+=use('sprig',x,y,ss,rr)
    s+='</g>'
    # Large leaf-and-flower corner plaques matched to four original clusters.
    s+='<g id="corner-botanical-plaques">'
    for x,y,r in [(51,27,0),(611,27,90),(611,219,180),(51,219,270)]:
        s+=f'<g transform="translate({x} {y}) rotate({r})">'
        s+=path('M-27-12 C-10-17 8-13 16-7 C33-1 35 10 26 17 C33 24 25 31 14 27 C7 37-7 34-13 23 C-26 25-34 15-28 8 C-41 1-37-10-27-12Z','#c6c393','#737c51',.7)
        for xx,yy,sc,rr in [(-20,-5,.65,-65),(-15,17,.82,-130),(12,20,.75,100),(23,4,.72,45),(5,-6,.8,-10)]:s+=use('acanthus',xx,yy,sc,rr)
        s+=ellipse(-1,8,17,14,'#a4a16c','#e6dbab',1.2)+ellipse(-1,8,14,11,'#c9c397','#6c704c',.6)
        s+=use('rose',-1,8,.88,-15)+use('greenLeaf',9,12,.9,60)+use('greenLeaf',-12,11,.8,-60)
        s+=use('scrollSpray',23,20,.84,15)+use('scrollSpray',-21,0,.78,175)
        for xx,yy,sc,rr in [(28,13,.48,63),(36,18,.37,85),(-25,8,.48,-65),(-32,-1,.37,-76),(-9,-9,.46,-22),(12,-9,.39,20),(1,24,.47,159),(20,24,.44,114)]:s+=use('acanthus',xx,yy,sc,rr)

        s+='</g>'
    s+='</g>'
    s+='<g id="woven-thread-material" fill="none" stroke-linecap="round">'
    # Hairline strands are vector material, never upscaled original pixel noise.
    random.seed(1742)
    for j in range(900):
        x=random.uniform(2,657);y=random.uniform(1,249);length=random.uniform(.8,3.6)
        c='#eddaad' if j%3 else '#2c2620'
        s+=path(f'M{x:.2f} {y:.2f}l{length:.2f} .12','none',c,.13,other='opacity=".13"')
    for y in range(2,250,2): s+=path(f'M0 {y}H660','none','#d3bc94',.09,other='opacity=".08"')
    s+='</g></g></g>'
    return write_part(OUT/'bitmap-1742.svg',[0,0,901,145],s)

def painting():
    defs=botanicals('paint')+'''
    <linearGradient id="frameMetal" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#b89b61"/><stop offset=".13" stop-color="#453321"/><stop offset=".32" stop-color="#8b7049"/><stop offset=".63" stop-color="#31261d"/><stop offset=".82" stop-color="#96784c"/><stop offset="1" stop-color="#423221"/></linearGradient>
    <linearGradient id="goldCarve" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#dec58b"/><stop offset=".22" stop-color="#ae8850"/><stop offset=".48" stop-color="#806039"/><stop offset=".68" stop-color="#c9aa6b"/><stop offset="1" stop-color="#4b3924"/></linearGradient>
    <linearGradient id="ovalGold" x1="0" y1="0" x2="1" y2=".6"><stop stop-color="#4d3b24"/><stop offset=".18" stop-color="#a98644"/><stop offset=".32" stop-color="#d2ae67"/><stop offset=".52" stop-color="#91703c"/><stop offset=".77" stop-color="#e1c17a"/><stop offset="1" stop-color="#624723"/></linearGradient>
    <radialGradient id="oilBackground" cx=".43" cy=".34" r=".76"><stop stop-color="#82733d"/><stop offset=".35" stop-color="#4e4c30"/><stop offset=".7" stop-color="#292d22"/><stop offset="1" stop-color="#201d18"/></radialGradient>
    <linearGradient id="vaseBlue" x1="0" y1="0" x2="1" y2=".2"><stop stop-color="#302c35"/><stop offset=".26" stop-color="#6f7487"/><stop offset=".51" stop-color="#777d8d"/><stop offset=".74" stop-color="#454659"/><stop offset="1" stop-color="#242932"/></linearGradient>
    <linearGradient id="tableGold" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#97804c"/><stop offset=".3" stop-color="#776640"/><stop offset="1" stop-color="#423422"/></linearGradient>
    <clipPath id="pictureOval"><ellipse cx="36" cy="45.2" rx="20.2" ry="28.3"/></clipPath>
    <g id="frameLeaf">'''
    d='M0 0 C-1.4-1.4-3.6-1.7-3.8-4.5 C-2.5-3.8-2.1-4.7-2.5-6.4 C-1.6-6.1-.8-4.9-.4-3.8 C.3-6 1.6-7.1 3.1-7.5 C2.1-5.8 2.3-5.1 3.4-4.7 C2.8-3 1.8-2.2.5-1.9 C1-1.3.6-.5 0 0Z'
    defs+=path(d,'url(#goldCarve)','#261e15',.24)+path('M0-.2Q-.3-3 2.5-6.6 M-.2-1.8Q-2-2.2-2.8-3.8','none','#c9b17b',.27)+'</g>'
    defs+='<g id="frameScroll">'+path('M0 0 C-3.3-2.2-6.3-3.5-5.1-6.6 C-3.8-9.8 1.4-9.3 1.2-6.5 C1.2-4.1-2.8-3.9-2.5-6.2','none','#231c14',1.3)+path('M0-.2 C-3-2.5-5.9-3.5-4.9-6.4 C-4-9.3.8-9 .7-6.6 C.7-4.6-2.3-4.5-2.4-6','none','url(#goldCarve)',.9)+path('M-.4-.5 C-2.6-2.4-5.6-3.6-4.8-6.1','none','#d3be8c',.22)+use('frameLeaf',-.2,-.3,.67,48)+'</g>'
    s='<title>CF6 1743 carved antique flower painting</title><desc>Editable floral still life with modeled gold-and-bronze relief frame. Reference-informed new vector brush shapes, carved relief paths, and procedural hairline canvas; no original color bitmap.</desc><defs>'+defs+'</defs>'
    s+='<g id="outer-carved-frame">'
    s+=path('M0 0H72V89H0Z','#30261d')
    s+=path('M.5.7 L70.8.4 L71.4 88.1 L.4 88.5Z','url(#frameMetal)','#a18c65',.45)
    s+=path('M1.9 2.2H69.7V86.9H2Z','none','#22190f',1.4)
    s+=path('M2.3 2.6H69V86H2.7Z','none','#bba474',.45)
    s+=path('M4.1 4.2 C15 4.7 23 3.7 36 4.2 S57 3.9 67.8 4.4 L67.2 84.4 C55 83.8 45 84.7 36 84.3 S15 85 4.7 84.3Z','none','#211910',1.6)
    s+=path('M4.4 4.8 C15 5.3 24 4.4 36 4.9 S57 4.5 67.1 5 L66.7 83.8 C54 83.2 46 84.1 36 83.7 S14 84.3 5.2 83.6Z','none','#ad9160',.5)
    # Deep recessed scalloped border makes the relief read as thick carved metal.
    s+=path('M7 9 C12 9 14 6 20 7 C25 7 25 9 31 8 C37 9 42 7 49 8 C56 7 59 10 64 9 L64 80 C56 79 53 82 47 81 C40 80 35 83 29 81 C22 80 18 82 13 80 L8 79Z','#413125','#1e1811',.8)
    # Horizontal and vertical mitred leaf chains are paired, never random beads.
    s+='<g id="recessed-dark-bronze-leaf-chain" opacity=".64">'
    for x in [10,19,28,37,46,55,64]:
        s+=use('frameScroll',x,8.1,.68,90)+use('frameScroll',72-x,81,.68,-90)
    for y in [17,29,41,53,65,77]:
        s+=use('frameScroll',7.8,y,.82,0)+use('frameScroll',64.4,y,.82,180)
    s+='</g>'
    for x,y,r in [(8,11,-15),(62,11,105),(63,79,165),(9,79,255)]:
        s+=f'<g transform="translate({x} {y}) rotate({r})">'+use('frameLeaf',0,0,1.2,0)+use('frameLeaf',1,1,.92,76)+use('frameLeaf',-1,0,.95,-55)+use('frameScroll',0,0,.84,40)+'</g>'
    # Rococo spandrels retain their dark negative spaces and knotted scrollwork.
    for x,y,r in [(16,17,-35),(56,17,35),(16,70,-145),(56,70,145)]:
        s+=use('frameScroll',x,y,1.28,r)+use('frameLeaf',x+(-1 if x<36 else 1),y,1.02,r+30)
    s+=path('M8.9 23 C10 35 8 52 10 64 M63.2 23 C61.8 36 63.2 51 61.8 65','none','#b39662',.6)
    s+=path('M11.2 24 C12.4 39 10.7 52 11.5 63 M60.8 25 C59.5 38 61.1 52 59.7 64','none','#221b13',1.1)
    s+='</g>'
    s+='<g id="oval-raised-gold-surround">'
    s+=ellipse(36,45,25.9,33.6,'#33261a','#bc9e60',.4)
    s+=ellipse(36,45,25,32.9,'url(#ovalGold)','#302217',.7)
    s+=ellipse(36,45,22.9,30.8,'none','#dbbd77',.65)
    s+=ellipse(36,45.2,21.8,29.8,'#413120','#5c452b',.65)
    # Carved overlapping leaf chain, individually editable and coherently tangent.
    for i in range(52):
        t=2*pi*i/52;xx=36+23.9*cos(t);yy=45+31.6*sin(t)
        # Tangent angle of elliptical contour.
        import math
        ang=math.degrees(math.atan2(31.6*cos(t),-23.9*sin(t)))+90
        s+=use('frameLeaf',xx,yy,.42,ang)
    s+=ellipse(36,45.2,20.9,29,'none','#d0b479',.55)
    s+=ellipse(36,45.2,20.35,28.5,'#28281c','#1e2118',.7)
    s+='</g>'
    s+='<g id="flower-oil-painting" clip-path="url(#pictureOval)">'
    s+=ellipse(36,45.2,20.5,28.7,'url(#oilBackground)')
    s+=path('M15 61 C27 59 43 60 58 60 L58 76H14Z','url(#tableGold)')
    s+=path('M16 61.3 Q34 59.2 57 60.7','none','#b29a5d',.7)
    # Glazed dark vase with distinctive foot, lip, and reflected vertical light.
    s+=ellipse(36,60.4,9.2,1.7,'#2c291e',other='opacity=".72"')
    s+=path('M28.7 50.3 Q36 49.2 43 50.3 C42.5 53.4 42.3 58.5 38.7 60 L33.1 60 C29.5 58.4 29.1 53.2 28.7 50.3Z','url(#vaseBlue)','#292b2c',.4)
    s+=ellipse(35.9,50.6,7.2,1.7,'#252a2b','#7e7e84',.25)
    s+=path('M31 52 C31 54.6 31.8 57.4 33.2 58.3 M33.2 52.4L34 56.5','none','#acaaa7',.42,other='opacity=".55"')
    s+=path('M32.8 59.5H39L40 60.7H31.9Z','#777578','#28252a',.3)
    # Stems fan from the vase opening toward the individually painted flower heads.
    for d in ['M35 51Q29 41 28 30','M36 51Q34 34 32 24','M36 52Q41 39 43 27','M36 51Q48 42 49 36','M35 51Q23 43 21 38','M36 52Q39 43 41 41','M35 52Q29 44 28 45']:
        s+=path(d,'none','#78815a',.55)
    for x,y,sc,r in [(29,43,.61,-62),(37,49,.67,66),(24,42,.63,-58),(43,42,.64,51),(39,33,.67,35),(30,31,.55,-19),(46,38,.61,69),(26,50,.63,-85),(43,50,.58,105),(34,35,.55,12)]:s+=use('greenLeaf',x,y,sc,r)
    # Tall flowers and pale foliage describe the recognizable upward bouquet.
    for d,c in [('M29 33 Q25 28 27 23 Q29 26 30 30Z','#b4b8a2'),('M33 31 Q31 24 32 20 Q34 24 34 30Z','#d0cdb2'),('M40 32 Q42 25 44 23 Q45 28 42 33Z','#9daaaa'),('M25 38 Q21 32 22 29 Q26 33 27 37Z','#8a9d89'),('M43 36 Q48 29 50 31 Q48 35 45 37Z','#738f86')]:s+=path(d,c)
    # Scumbled white and blue-gray petals merge into an irregular upper light group.
    for d,c in [('M25 33 C24 30 28 29 29 31 C30 28 33 29 32 32 C35 31 36 34 33 35 C30 37 26 36 25 33Z','#aeb9a8'),('M33 32 C33 29 35 28 37 30 C38 28 41 29 41 31 C44 31 43 34 40 35 C39 37 36 36 35 35Z','#a2b4b1'),('M24 37 C22 35 23 32 25 33 C28 31 30 34 28 36 C28 39 25 39 24 37Z','#c9cbb0')]:s+=path(d,c)
    for x,y,sc,r in [(27,32,.35,13),(32,32,.33,41),(35,30,.29,-12),(39,34,.30,20)]:s+=use('whiteRose',x,y,sc,r)
    # Flower heads follow the reference composition: red right, white left/front.
    for n,x,y,sc,r in [('rose',32,25,.32,-17),('blueFlower',38,32,.64,12),('whiteRose',29,35,.50,18),('smallFlower',24,33,.54,-10),('rose',26,39,.43,17),('rose',42,40,.69,10),('whiteRose',32.5,46.5,.70,6),('rose',47,48,.51,20),('rose',24,47,.38,-19),('blueFlower',27,52,.40,24),('smallFlower',37,36,.44,33),('smallFlower',46,34,.36,5),('smallFlower',21,41,.32,55)]:
        s+=use(n,x,y,sc,r)
    # Warm oil glazes and brush dashes create paint, not scaled pixel noise.
    s+='<g id="oil-brush-impasto" stroke-linecap="round">'
    brushes=[(30.2,43.4,1.2,-.5,'#e0d8b4'),(34.1,45.3,.9,.5,'#e8dfbd'),(31.7,48.1,1.0,.25,'#b7b58a'),(40.1,37.6,1.3,-.35,'#d49a7b'),(43.4,40.1,.4,1.1,'#a94c3f'),(42.1,42.5,1.0,-.3,'#6e302d'),(26.1,37.6,.8,.4,'#dbad6d'),(37.8,30.1,1.1,.4,'#b5c8c1'),(25,47,1,.2,'#ce8656'),(47.1,46.9,.7,.4,'#b85542'),(33,24.4,.7,.2,'#be9350')]
    for x,y,dx,dy,c in brushes:s+=path(f'M{x} {y}l{dx} {dy}','none',c,.45)
    random.seed(1743)
    for i in range(125):
        x=random.uniform(16,56);y=random.uniform(17,73)
        s+=path(f'M{x:.2f} {y:.2f}l{random.uniform(.15,.6):.2f} {random.uniform(-.2,.2):.2f}','none','#d9ca98' if i%3 else '#181e16',.07,other='opacity=".19"')
    s+='</g></g>'
    # Selected chased ridges; no uniform bright outline around the whole frame.
    s+='<g id="chased-edge-highlights" fill="none" stroke-linecap="round">'
    for d in ['M2 1.4H23 M40 1.3H65','M1.2 7V28 M1.4 65V84','M70.4 12V39 M70 58V82','M8 87.6H28 M41 87.5H64','M16 12Q21 9 28 11','M43 11Q51 10 56 15','M17 76Q22 80 30 79','M43 80Q52 80 58 75']:
        s+=path(d,'none','#d6c39a',.22,other='opacity=".65"')
    s+='</g>'
    return write_part(OUT/'bitmap-1743.svg',[0,0,72,89],s)

def preview(paths):
    for p,w,h in [(paths[0],901,145),(paths[1],72,89)]:
        ident=p.stem.split('-')[-1]
        for scale in [1,4,8] if ident=='1743' else [1,3]:
            render(p,w*scale,PRE/f'decor-{ident}-{scale}x.png')
        orig=Image.open(ROOT/f'reference/bitmap-{ident}-original.png').convert('RGBA')
        new=Image.open(PRE/f'decor-{ident}-1x.png').convert('RGBA')
        factor=4 if ident=='1742' else 8
        board=Image.new('RGB',(w*factor,max(h*factor,100)*2+48),'#252522')
        d=ImageDraw.Draw(board);d.text((8,5),'ORIGINAL - same native extent',fill='white');d.text((8,h*factor+28),'VECTOR REDRAW - same native extent',fill='white')
        # Native-scale comparison enlarged only for inspection, plus real vector render.
        board.paste(orig.resize((w*factor,h*factor),Image.Resampling.NEAREST),(0,22),orig.resize((w*factor,h*factor),Image.Resampling.NEAREST))
        svgpath=PRE/f'decor-{ident}-qa-large.png';render(p,w*factor,svgpath)
        high=Image.open(svgpath).convert('RGBA');board.paste(high,(0,h*factor+46),high)
        board.save(PRE/f'decor-{ident}-comparison.png')
        board.save(PRE/('decor-carpet-original-new.png' if ident=='1742' else 'decor-painting-original-new.png'))
        info={'asset':ident,'native_size':[w,h],'viewBox':[0,0,w,h],'original_alpha_pixels':int(np.count_nonzero(np.array(orig)[:,:,3])),'new_alpha_pixels':int(np.count_nonzero(np.array(new)[:,:,3])),'alpha_max_absolute_error':int(np.abs(np.array(orig)[:,:,3].astype(int)-np.array(new)[:,:,3].astype(int)).max()),'visible_artwork':'Authored editable vector geometry and deterministic vector material marks. Original alpha mask for rug only; no original RGB image or quantized color-region tracing embedded.','construction':'Reference-informed redraw with one native footprint projection for 1742, no external additional perspective.'}
        (QA/f'decor-{ident}-construction.json').write_text(json.dumps(info,ensure_ascii=False,indent=2))

if __name__=='__main__':
    paths=[carpet(),painting()];preview(paths)
    print('\n'.join(str(p) for p in paths))
