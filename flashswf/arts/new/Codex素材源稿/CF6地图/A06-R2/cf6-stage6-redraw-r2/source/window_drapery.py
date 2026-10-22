#!/usr/bin/env python3
"""Stage six window and drapery. Deterministic, editable native SVG artwork.
No image is embedded and no external resource is needed. Paths, gradients,
clipping, fine thread lines and floral ornaments are all vector primitives.
Run from any directory; outputs parts/bitmap-1756.svg and bitmap-1757.svg.
"""
from pathlib import Path
from math import sin,cos,pi
import random
from svg_native import write_part,render
ROOT=Path(__file__).resolve().parents[1]
random.seed(1757)

def path(d,fill='none',stroke=None,sw=None,extra=''):
    return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+(f' stroke-width="{sw}"' if sw is not None else '')+f' {extra}/>'
def rect(x,y,w,h,fill,extra=''):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" {extra}/>'
def line(x,y,X,Y,c,w=.5,extra=''):
    return f'<path d="M{x},{y} L{X},{Y}" fill="none" stroke="{c}" stroke-width="{w}" {extra}/>'
def grad(id,stops,x1='0%',y1='0%',x2='0%',y2='100%',extra=''):
    s=f'<linearGradient id="{id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" {extra}>'
    for p,c in stops:s+=f'<stop offset="{p}" stop-color="{c}"/>'
    return s+'</linearGradient>'
def ellipse(x,y,rx,ry,c,extra=''):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}" {extra}/>'

def common(prefix):
    return ''.join([
      grad(prefix+'gold',[('0%','#57340f'),('14%','#b08a30'),('29%','#e0bd62'),('43%','#84601c'),('62%','#ae842a'),('82%','#d4b14e'),('100%','#674416')]),
      grad(prefix+'cornice',[('0%','#d3af50'),('10%','#795115'),('25%','#b68c32'),('46%','#4b2a0d'),('56%','#997126'),('78%','#bc963e'),('100%','#70501c')]),
      grad(prefix+'wood',[('0%','#170d08'),('19%','#4b2612'),('37%','#744719'),('52%','#2d140b'),('68%','#5a3415'),('100%','#160b06')],x2='100%',y2='0%'),
      grad(prefix+'recess',[('0%','#3a210b'),('32%','#825719'),('72%','#a67c2d'),('100%','#4d2c0e')]),
      grad(prefix+'velvet',[('0%','#100704'),('22%','#3f1b0b'),('43%','#1e0d05'),('62%','#54280f'),('81%','#230d05'),('100%','#100604')],x2='100%',y2='0%'),
      grad(prefix+'silk',[('0%','#71582d'),('13%','#c3b08a'),('29%','#ece4c8'),('44%','#bca77b'),('62%','#f2e7c7'),('77%','#d4c295'),('100%','#837044')],x2='100%',y2='0%'),
      grad(prefix+'swag',[('0%','#c0a970'),('21%','#dfc997'),('39%','#a78c58'),('56%','#c8af78'),('72%','#8c6e3c'),('88%','#c8b38a'),('100%','#68502c')]),
      grad(prefix+'hem',[('0%','#e2cb7f'),('24%','#f1dfa1'),('45%','#b8933b'),('67%','#d7b653'),('100%','#9e7628')]),
      grad(prefix+'fringe',[('0%','#c3a24d'),('23%','#ecd278'),('63%','#aa8228'),('100%','#d7b452')]),
    ])

def rosette(x,y,r=2,col='#cfab58',opacity=1):
    o=f'<g opacity="{opacity}">'
    for a in range(0,360,60):
        o+=f'<ellipse cx="{x}" cy="{y-r*.66}" rx="{r*.32}" ry="{r*.57}" fill="{col}" transform="rotate({a} {x} {y})"/>'
    return o+ellipse(x,y,r*.27,r*.27,'#f0d88c')+'</g>'

def floral(x,y,s=1,col='#cda957',opacity=.7):
    return f'<g transform="translate({x} {y}) scale({s})" opacity="{opacity}">'+path('M0,6 C-2,3 -1,1 0,-3 C1,1 2,3 0,6 M0,1 C-4,-5 -6,-1 -2,1 C-5,0 -5,4 0,3 M0,1 C4,-5 6,-1 2,1 C5,0 5,4 0,3',col)+ellipse(0,-4,1,1.5,col)+'</g>'

# Shared pelmet profile ensures one continuous hem and empty window apertures.
WAVE_ANCHORS=[(19,44),(35,40),(62,50),(87,42),(107,51),(140,41),(153,44),(166,41),(198,51),(216,43),(236,51),(269,41),(281,44),(294,41),(327,51),(345,43),(367,51),(398,41),(413,44)]
def pelmet_wave(x):
    for (a,ya),(b,yb) in zip(WAVE_ANCHORS,WAVE_ANCHORS[1:]):
        if a<=x<=b:
            t=(x-a)/(b-a);t=t*t*(3-2*t);return ya*(1-t)+yb*t
    return WAVE_ANCHORS[0][1] if x<19 else WAVE_ANCHORS[-1][1]

def frame1756():
    a=['<title>1756 · gilded bronze pediment and two open window lights</title>', '<defs>'+common('w')+'</defs>']
    # Architectural triangular pediment; uninterrupted transparent window lights.
    a += [path('M0,50 L59.5,.6 L120,50 L113,51.5 L6,51.5 Z','#2a190b','#0e0b07',.7),
          path('M3.8,49 L59.5,3.4 L116.4,49 Z','url(#wgold)','#9e7c2c',.65),
          path('M10,47 L59.5,7 L110.2,47 Z','#3b260d','#33200b',.9),
          path('M15.4,44.2 L59.5,10.8 L104.7,44.2 Z','url(#wrecess)','#c4a34e',.8),
          path('M19,43 L59.5,13 L101,43 Z','#a37e2e','#543813',.65),
          path('M19,43 L59.5,13 L101,43','#d1aa50',None,None,extra='opacity=".11"'),
          path('M4.6,48.7 L59.5,4.5 L115,48.7','none','#e2c167',.6),
          path('M15.8,44.4 L104.5,44.4','none','#e4c970',.5)]
    # Hand-cut acanthus fan inside the tympanum.
    a += [path('M52,43 L40,34.7 L47.3,36.4 L37.6,25 L50.3,34.2 L45.8,18.9 L54.2,32.6 L55.2,16.2 L58.3,30.8 L60,13.6 L63.2,30.5 L67.1,18.1 L67,33.2 L77.4,25.6 L70,36.4 L79,34.7 L67.2,43 Z','#ceb653','#37270b',.85),
          path('M55,42 L49,36 M58,41 L55,25 M61,41 L61,20 M64,41 L66,29 M67,41 L73,36','none','#8c6d20',.65),
          path('M57.4,39.8 L58.8,21.2 M61.9,38.4 L63.7,24','none','#ead278',.48)]
    # Cornice, fluted capitals and restrained dark cast shadows.
    a += [rect(7.2,51,104.7,19.2,'#3d260d'),rect(8.2,51.7,102.5,5,'url(#wcornice)'),
          rect(7.5,56.3,104,9.8,'url(#wgold)'),rect(8,65.8,103.7,4.6,'url(#wrecess)'),
          rect(14.8,68.2,90.8,4.6,'url(#wcornice)'),rect(8,51.5,103.5,1,'#dfbc62'),
          line(9,55.7,110.5,55.7,'#2e1c09',.7),line(9,57.5,110.2,57.5,'#c6a34b',.5),
          line(15.5,65.5,105.3,65.5,'#e4be65',.7),line(15.6,67.5,105,67.5,'#37200c',.8),
          line(16.5,70.7,104.3,70.7,'#cc9f45',.65)]
    for x in [9.5,101.5]:
        for k in range(3):
            xx=x+k*2.05
            a += [path(f'M{xx},56.2 Q{xx-1.3},59.8 {xx},63.7 Q{xx+1.5},61 {xx},56.2Z','#694414','#281c09',.38),
                  path(f'M{xx+.2},57.4 Q{xx-.6},60 {xx+.15},62.5','none','#ddbc61',.52)]
    # Gold-lined jambs, precisely two clear openings.
    a += [rect(15,71,5.3,86.7,'url(#wwood)'),rect(99.4,71,6,87.4,'url(#wwood)'),
          rect(59.2,72,2.8,83.5,'url(#wwood)'),rect(19,71.7,81.3,2.1,'url(#wwood)'),
          rect(19,153.5,81.5,3.4,'url(#wwood)'),line(17,71.6,17,156.3,'#a97b29',.8),
          line(19.6,73.3,19.6,154.7,'#c49a3e',.48),line(102.7,71.3,102.7,157.1,'#b38a35',.65),
          line(99.4,73.6,99.4,154,'#9c7126',.5),line(60.1,74,60.1,153.5,'#78451c',.47),
          line(20.5,73.8,98.5,73.8,'#4d2810',.55),line(20.2,154.8,99.7,154.8,'#ab7d2c',.55),
          line(18,156.8,103.3,156.8,'#30200c',.7)]
    # Stepped base and polished, age-softened bronze sill.
    a += [path('M7.8,158.2 L15.3,158.2 L15.3,155.8 L20,155.8 L20,158.5 L99.8,158.5 L99.8,156.2 L105.4,156.2 L105.4,158.3 L111.7,158.3 L111.7,174.3 L8,174.3 Z','#3b280e','#23190a',.6),
          rect(8.2,160.2,103.2,9.6,'url(#wgold)'),rect(8.1,169,103.4,5,'url(#wcornice)'),
          line(8.7,161,111,161,'#d0ad50',.7),line(8.6,170.1,111,170.1,'#efce7a',.6),
          line(8.5,172.5,111,172.5,'#67451a',.7),rect(8.2,158.2,7.8,3.5,'#c1a04a'),
          rect(104.6,158.2,6.8,3.5,'#b7973e'),line(8,161.7,16,161.7,'#543b11',.5)]
    # Subtle handmade patina. Native vector grain, never raster noise.
    rr=random.Random(1756)
    a += ['<g opacity=".105" stroke-linecap="round">']
    for i in range(155):
        x=rr.uniform(8.5,111);y=rr.choice([rr.uniform(53,69),rr.uniform(162,173)])
        a.append(line(round(x,2),round(y,2),round(min(111,x+rr.uniform(.1,1.5)),2),round(y+rr.uniform(-.09,.09),2),rr.choice(['#f2d48c','#221709']),rr.uniform(.06,.22)))
    a+=['</g>']
    write_part(ROOT/'parts/bitmap-1756.svg',[0,0,121,175],''.join(a))


def curtain1757():
    d=['<title>1757 · six open window lights, embroidered ivory-and-gold silk and russet velvet drapery</title>']
    defs=common('c')
    # The left drape curves into a gathered knot at its bottom left.
    front='M19,48 C31,46 52,49 69,55 C62,89 45,129 17,153 C13,143 13,127 15,108 C17,88 18,67 19,48Z'
    back='M64,49 L89,54 C85,87 80,128 67,151 C61,163 48,171 37,168 C26,165 20,160 17,153 C37,132 54,95 64,49Z'
    defs+=f'<clipPath id="cfront"><path d="{front}"/></clipPath><clipPath id="cback"><path d="{back}"/></clipPath>'
    defs+=grad('csill',[('0%','#694316'),('15%','#99712a'),('54%','#a78332'),('79%','#b99a42'),('100%','#d0b55e')])
    defs+=grad('civory',[('0%','#7b6944'),('14%','#bba982'),('33%','#efe7cd'),('51%','#d0c09a'),('70%','#f7edce'),('85%','#c4b48d'),('100%','#8b7548')],x2='100%',y2='0%')
    defs+=grad('cband',[('0%','#e5cd7c'),('20%','#f5e0a3'),('52%','#c5a354'),('74%','#f0db9c'),('100%','#ae8733')])
    d.append('<defs>'+defs+'</defs>')
    # Outer frame and paired mullions. Window apertures are genuinely empty.
    d += [path('M1,10 L15,1 L416,1 L431,11 L426,13 L414,6 L18,6 L6,13Z','url(#cgold)','#2b1c0b',.8),
          rect(14,5,5.5,163.2,'url(#cwood)'),rect(412,5,5.2,164,'url(#cwood)')]
    d += [rect(146.5,43,12.5,125.8,'#3a210e'),rect(274,43,11.6,125.8,'#3a210e')]
    for x,w in [(87,4.5),(146.5,6.3),(154.5,4.5),(216.4,4.2),(274,5.5),(281.2,4.4),(340.5,4.3)]:
        d += [rect(x,43,w,125.8,'url(#cwood)'),line(x+.6,45,x+.6,166.3,'#a67a29',.55),line(x+w-.6,45,x+w-.6,166.3,'#1d0d06',.5)]
    d += [rect(17,165.2,398,6.6,'url(#cwood)'),line(20,166.6,412,166.6,'#784716',.7),
          line(20,169.2,412,169.2,'#95702b',.55),rect(16,171.4,400,25.3,'#34210c'),
          rect(18,172.5,396,4.3,'url(#ccornice)'),rect(18,177,396,13,'url(#csill)'),
          rect(17.8,189.7,396.3,6.1,'url(#ccornice)'),line(19,178,413,178,'#91691f',.8),
          line(19,189.2,413,189.2,'#b59749',.75),line(19,192.9,413,192.9,'#261908',1),
          line(20,195.7,413,195.7,'#92712b',.6)]
    # Subdued grain gives the sill a broad carved plane, not shiny sheet metal.
    rr=random.Random(313)
    for i in range(190):
        x=rr.uniform(21,411);y=rr.uniform(178.6,188)
        d.append(line(round(x,2),round(y,2),round(min(413,x+rr.uniform(.2,2.4)),2),round(y+.05,2),rr.choice(['#e9cc80','#55320e']),rr.uniform(.08,.2),'opacity=".075"'))
    # Narrow outer velvet ribbons with a winding gold cable.
    for mirror in [False,True]:
        tr='translate(432 0) scale(-1 1)' if mirror else ''
        d.append(f'<g transform="{tr}">')
        d += [path('M12,0 L19,0 C18,44 20,77 17,112 C16,145 23,181 20,206 L9,211 C13,167 9,135 12,95 C10,63 11,28 12,0Z','url(#cvelvet)','#71521c',.5)]
        for i in range(7):
            y=4+i*25.2
            d += [path(f'M15,{y} C24,{y+9} 8,{y+16} 13,{y+25}','none','#aa8131',3.4),path(f'M15,{y} C23,{y+9} 9,{y+16} 13,{y+25}','none','#e1c267',1.2)]
        d.append('</g>')
    # Back velvet and front embroidered silk are authored once and mirrored.
    for mirror in [False,True]:
        tr='translate(432 0) scale(-1 1)' if mirror else ''
        d.append(f'<g transform="{tr}">')
        d += [path(back,'url(#cvelvet)','#33200b',.8),'<g clip-path="url(#cback)">']
        # Deep, long, flowing velvet folds; endpoints join at gathered knot.
        folds=[(87,58,83,129,64,161,21,153),(81,56,79,118,61,159,23,152),(76,52,70,119,57,151,23,151),(72,50,61,116,48,148,22,152),(67,51,57,111,39,145,20,150)]
        for k,(x,y,c1x,c1y,c2x,c2y,ex,ey) in enumerate(folds):
            z=f'M{x},{y} C{c1x},{c1y} {c2x},{c2y} {ex},{ey}'
            d += [path(z,'none','#100704',4.1-k*.35),path(z,'none','#785233',2.7-k*.2,'opacity=".72"'),path(z,'none','#bba073',.33,'opacity=".57" stroke-dasharray="17 3 11 2 7 4"')]
        for i in range(28):
            t=i/27;x=65+t*23
            d.append(path(f'M{x:.2f},52 C{x-5:.2f},103 {43+t*24:.2f},{150+t*12:.2f} 20,152','none','#a88049',.12,'opacity=".11"'))
        # Brocade motifs recede into the dark underskirt.
        for y in range(61,157,13):
            for x in range(29,85,12): d.append(floral(x+(y%3),y,.55,'#bc8e40',.22))
        d += ['</g>',path('M88,55 C84,99 80,143 64,160 C49,178 29,166 18,154','none','#8e681f',3),path('M87.6,55 C83,99 79,143 63,159 C49,175 30,164 18,153','none','#d3b35d',1.2)]
        # Fringe following the arcing inner hem.
        for i in range(57):
            t=i/56;u=1-t
            # Cubic from the high inner corner to the knot.
            x=u*u*u*87+3*u*u*t*79+3*u*t*t*65+t*t*t*18
            y=u*u*u*55+3*u*u*t*147+3*u*t*t*189+t*t*t*153
            d.append(path(f'M{x:.2f},{y:.2f} q1.3,1.5 -.5,3.4','none','#c3a04c',.31))
        d += [path(front,'url(#civory)','#877244',.65),'<g clip-path="url(#cfront)">']
        # Soft fabric flutes: broad curved strips, diffuse hue steps, narrow valleys.
        strips=[(20,26,18,98,16,138,16,151),(28,36,26,102,19,138,17,151),(39,47,35,106,23,138,18,152),(50,58,43,109,27,139,18,153),(61,70,52,109,32,141,18,153)]
        for j,(x,X,cx,cy,dx,dy,ex,ey) in enumerate(strips):
            z=f'M{x},48 L{X},50 C{X-3},87 {dx+6},{dy} {ex},{ey} C{dx},{dy} {cx},{cy} {x},48Z'
            d += [path(z,'url(#csilk)'),path(f'M{x+.5},50 C{cx},{cy} {dx},{dy} {ex},{ey}','none','#786342',.9,'opacity=".42"'),path(f'M{x+2.1},51 C{cx+1.5},{cy} {dx+.8},{dy} {ex+.8},{ey}','none','#f5ecd5',.48,'opacity=".54"')]
        # Embroidered motifs warp and tighten toward the gathered knot.
        # Each motif is curved acanthus embroidery, never a flat leaf grid.
        rr=random.Random(778)
        for row,y in enumerate(range(59,150,11)):
            f=max(.08,(153-y)/96)
            for col,tx in enumerate([22,33,45,57,67]):
                xx=17+(tx-17+(row%2)*3.2)*f**.57 + rr.uniform(-.9,.9)
                sy=.6+rr.uniform(-.09,.08);sx=sy*(.48+.52*f)
                angle=-12-22*(1-f)+rr.uniform(-13,13)
                d += [f'<g transform="translate({xx:.2f} {y+rr.uniform(-1.8,1.8):.2f}) rotate({angle:.2f}) scale({sx:.3f} {sy:.3f})" opacity=".67">',
                      path('M0,-5 C-1,-4 -2,-3 -1,-1 C-4,-3 -7,-1 -5,1 C-3,3 -2,0 -3,-1 C-1,0 -1,3 -1,4 C-3,2 -5,4 -4,6 C-2,8 0,5 0,3 C0,5 2,8 4,6 C5,4 3,2 1,4 C1,2 2,0 3,-1 C2,1 5,3 6,1 C7,-2 3,-3 1,-1 C2,-3 1,-4 0,-5Z','#c7a94e'),
                      path('M-5,4 C-10,4 -9,-3 -6,-4 C-5,-5 -4,-3 -5,-3 M5,4 C9,3 9,-2 6,-4 C5,-5 4,-3 5,-3','none','#bda052',.5),
                      ellipse(0,-5.7,.65,.9,'#e1c46e'),'</g>']
        rr=random.Random(508)
        for i in range(950):
            x=rr.uniform(16,71);y=rr.uniform(49,153)
            d.append(path(f'M{x:.2f},{y:.2f} l{rr.uniform(-.22,.22):.2f},{rr.uniform(.13,.65):.2f}','none',rr.choice(['#f8efd3','#7a6845','#c5ad73']),rr.uniform(.07,.24),f'opacity="{rr.uniform(.12,.32):.2f}"'))
        # Hairline warp gently follows the gather; subdued to avoid metal ribs.
        for i in range(38):
            x=18+i*1.4
            d.append(path(f'M{x:.2f},49 C{x-3:.2f},93 {20+(x-18)*.22:.2f},136 17.5,151','none',('#fff6dc' if i%3 else '#7d6743'),.11,'opacity=".31"'))
        d += ['</g>',path('M67,54 C59,93 44,130 17,153','none','#bea04e',1.5),path('M66.4,54 C58,93 43,129 16.7,151.8','none','#e6d18a',.48)]
        # Two looped cords, braid wrapped across the gather, and shaped tassel.
        d += [path('M15.8,151 C12,141 7,131 5.2,123','none','#71551e',2),path('M15.8,151 C12,141 7,131 5.2,123','none','#e6d39b',1),
              path('M16.4,152 C19,142 24,132 30,126','none','#765a21',1.7),path('M16.4,152 C19,142 24,132 30,126','none','#dcc584',.8),
              ellipse(5.2,123,.8,1.1,'#e9dbad'),ellipse(30,126,.65,.85,'#e0c988'),
              path('M13.5,149 L20.9,154.4 L20,160 L13.1,155.3Z','url(#cband)','#846728',.5),
              path('M14.8,152.1 L19.9,155.9 M14.3,154 L19.4,157.8','none','#f0d693',.7),
              path('M16.6,157 C20,159 20.1,163 17.3,165 C14,165 13.9,159 16.6,157Z','url(#cgold)','#7c5b1d',.4),
              ellipse(17.2,164.8,3,1.2,'#e1c065'),
              path('M15.1,166 C14.7,173 12.4,178 12.8,183 Q17,187 21.7,182 C20.7,177 19.7,171 19.2,166Z','url(#cfringe)','#94722b',.45)]
        for i in range(10):
            x=14.6+i*.52
            d.append(path(f'M{x:.2f},166.2 Q{x+(i-5)*.22:.2f},176 {12.9+i*.93:.2f},182.6','none',('#f4d487' if i%2 else '#8b6822'),.23))
        # Long ribbon tails taper independently rather than becoming a rigid post.
        d += [path('M14.3,181 C11,192 10.8,200 9.6,210 L16.6,209 C18,197 17.6,191 17.7,181Z','url(#csilk)','#9b813e',.45),
              path('M18,182 C19,190 18.2,199 17.9,206 L21,204 C22,192 20.7,186 20.2,181Z','url(#cfringe)','#8b6725',.45),
              path('M13.5,187 Q12.5,199 12.3,207 M17.2,188 Q15.6,199 15.2,207','none','#dec67b',.6),
              floral(13.8,198,.55,'#a38432',.85)]
        d.append('</g>')
    # Continuous red-brown pelmet under the swags.
    lower='M14,0 L418,0 L418,48 L'+ ' L'.join(f'{x:.1f},{pelmet_wave(x)+5.5:.2f}' for x in [413-i*.5 for i in range(789)])+' L14,48Z'
    d += [path(lower,'url(#cvelvet)','#4f2a0e',.6)]
    # Top band botanical scroll embroidery, explicitly curved and irregular.
    d += [path('M16,.7 C38,3 47,1 65,1 C88,4 100,1 113,1 C129,3 140,2 151,1 C172,4 183,1 196,1 C216,3 228,2 241,1 C257,3 270,3 280,1 C303,3 313,2 326,1 C345,3 355,1 370,1 C387,3 401,2 416,1','none','#c2a153',.8)]
    for i,cx in enumerate([37,87,130,172,217,259,303,348,392]):
        s=.9+(i%3)*.04
        d += [f'<g transform="translate({cx} 7) scale({s})">',
              path('M-20,-4 C-19,2 -9,5 -5,1 C-2,-3 -8,-5 -10,-1 C-10,1 -6,2 -6,-1 M20,-4 C19,2 9,5 5,1 C2,-3 8,-5 10,-1 C10,1 6,2 6,-1 M-5,1 C-2,2 -1,3 0,6 C1,3 2,2 5,1','none','#d0ad58',.72),floral(0,0,.8,'#d6b665',.95),'</g>']
    # Nine fan swags alternate asymmetric left fall, deep V fall, and right
    # fall. The folded lower belly and pinched diagonal shoulders are essential.
    swags=[(18,65,33),(65,112,37),(112,150,32),(150,196,35),(196,241,37),(241,279,32),(279,325,35),(325,369,37),(369,414,33)]
    def sweep(L,R,D,top,kind,inset=0):
        L+=inset;R-=inset
        span=R-L;f=[.39,.5,.61][kind];m=L+span*f
        if kind==1:
            c=(L+span*.17,D*.66,m-4.4,D-.2,m,D,m+4.4,D-.2,R-span*.17,D*.66,R,top+.2)
        elif kind==0:
            c=(L+span*.06,D+.6,m-6,D+2,m,D,m+7,D-1,R-span*.18,D*.67,R,top+.2)
        else:
            c=(L+span*.18,D*.67,m-7,D-1,m,D,m+6,D+2,R-span*.06,D+.6,R,top+.2)
        return (L,top),c
    def curve(st,c):
        return f'M{st[0]:.2f},{st[1]:.2f} C{c[0]:.2f},{c[1]:.2f} {c[2]:.2f},{c[3]:.2f} {c[4]:.2f},{c[5]:.2f} C{c[6]:.2f},{c[7]:.2f} {c[8]:.2f},{c[9]:.2f} {c[10]:.2f},{c[11]:.2f}'
    def reverse_curve(st,c):
        return f'L{c[10]:.2f},{c[11]:.2f} C{c[8]:.2f},{c[9]:.2f} {c[6]:.2f},{c[7]:.2f} {c[4]:.2f},{c[5]:.2f} C{c[2]:.2f},{c[3]:.2f} {c[0]:.2f},{c[1]:.2f} {st[0]:.2f},{st[1]:.2f}'
    def point(st,c,t):
        if t<.5:
            t*=2;P=[st,(c[0],c[1]),(c[2],c[3]),(c[4],c[5])]
        else:
            t=(t-.5)*2;P=[(c[4],c[5]),(c[6],c[7]),(c[8],c[9]),(c[10],c[11])]
        u=1-t;return tuple(u**3*P[0][q]+3*u*u*t*P[1][q]+3*u*t*t*P[2][q]+t**3*P[3][q] for q in [0,1])
    for n,(L,R,H) in enumerate(swags):
        kind=n%3;top=4.2+(n%3)*.2;mid=L+(R-L)*[.39,.5,.61][kind]
        st,c=sweep(L,R,H,top,kind)
        ti,ci=sweep(L,R,12.7 if kind!=1 else 16,top,kind)
        silhouette=curve(st,c)+reverse_curve(ti,ci)+'Z'
        d += [f'<defs><clipPath id="cswag{n}"><path d="{silhouette}"/></clipPath></defs>',path(silhouette,'url(#cswag)','#6d552f',.55)]
        # The lower fold rolls over into a darker, wide belly.
        si,co=sweep(L,R,H-3.8,top+.1,kind,.4)
        d += [path(curve(st,c)+reverse_curve(si,co)+'Z','#75623d',None,None,'opacity=".63"'),path(curve(st,c),'none','#d0ba7e',.6)]
        depths=([13.5,19.2,25.1,H-4] if kind!=1 else [16.6,22.1,27,31.6,H-3])
        for j,D in enumerate(depths):
            ss,cc=sweep(L,R,D,top+j*.18,kind,.3+j*.18)
            z=curve(ss,cc)
            d += [path(z,'none','#6e5935',2.4 if j%2==0 else 1.65,'opacity=".66"'),path(z,'none',('#c2ab78' if j%2 else '#d2c099'),1.15 if j%2==0 else .8),path(z,'none','#e8d6a8',.24,'opacity=".68"')]
        # Cross-grain shoulder folds join the arcs at oblique angles.
        for side in [0,1]:
            x=L if side==0 else R;sgn=1 if side==0 else -1
            for j in range(5):
                d += [path(f'M{x+sgn*(.5+j*.55):.2f},{top+.1:.2f} C{x+sgn*(1.2+j*.8):.2f},{9+j*.6:.2f} {x+sgn*(3+j*.6):.2f},{17+j*1.9:.2f} {x+sgn*(7+j*1.1):.2f},{21+j*2:.2f}','none',('#cbb784' if j%2 else '#74613c'),.47,'opacity=".65"')]
        # Stitched gold blooms ride only the cloth, not a flat repeated grid.
        d.append(f'<g clip-path="url(#cswag{n})">')
        rr=random.Random(300+n)
        for q in range(170):
            x=rr.uniform(L,R);y=rr.uniform(7,H+2)
            d.append(path(f'M{x:.2f},{y:.2f} l{rr.uniform(.1,.6):.2f},{rr.uniform(-.2,.2):.2f}','none',rr.choice(['#f6e7be','#6c5531','#b89445']),rr.uniform(.08,.25),'opacity=".24"'))
        for q in range(4):
            x=L+7+q*(R-L-14)/3;y=H-9+1.5*sin(q*1.3)
            d.append(rosette(x,y,1.25,'#d5b25b',.73))
        d.append('</g>')
        # Dangling beads follow the curved lower edge and vary in length.
        for j in range(17):
            t=(j+.5)/17;x,y=point(st,c,t);ln=1.4+(j%3)*.5
            d += [line(round(x,2),round(y,2),round(x-.12,2),round(y+ln,2),'#a98740',.25),ellipse(round(x-.1,2),round(y+ln+.45,2),.4,.67,'#cfad58')]
        d.append(rosette(L,top-.3,1.15,'#bc9445',.9))
    # Exposed velvet below the fan row carries arabesque scrollwork.
    for k,cx in enumerate([34,86,133,171,216,260,303,346,397]):
        d += [path(f'M{cx-16},45 C{cx-10},34 {cx-5},42 {cx-8},44 C{cx-11},46 {cx-13},42 {cx-9},40 M{cx+16},45 C{cx+10},34 {cx+5},42 {cx+8},44 C{cx+11},46 {cx+13},42 {cx+9},40','none','#ac843e',.55),path(f'M{cx-12},43 C{cx-19},36 {cx-6},30 {cx-5},34 C{cx-4},38 {cx-9},37 {cx-8},34 M{cx+12},43 C{cx+19},36 {cx+6},30 {cx+5},34 C{cx+4},38 {cx+9},37 {cx+8},34','none','#bf9c52',.55),floral(cx,43,.64,'#d0aa53',.75)]
    # The welt follows a single continuous textile wave. The underside and
    # fringe inherit that curve, so no disconnected solid "leaf" shapes form.
    wave=pelmet_wave
    xs=[19+i*.5 for i in range(789)]
    upper='M'+' L'.join(f'{x:.2f},{wave(x):.2f}' for x in xs)
    lower=' L'.join(f'{x:.2f},{wave(x)+6.3:.2f}' for x in xs[::-1])
    d += [path(upper+' L'+lower+'Z','url(#cband)','#b58f3f',.32),path(upper,'none','#f1dfa7',.65)]
    for i in range(525):
        x=19+i*.75;y=wave(x)+5.8
        d += [path(f'M{x:.2f},{y:.2f} q{.2*sin(i):.2f},2.5 {-.18 if i%2 else .18},{6+(i%3)*.25:.2f}','none',('#d8b55e' if i%3 else '#a7802f'),.38),ellipse(x,y+5.8+(i%3)*.25,.2,.42,'#caa34e')]
    # Fine, closely worked diagonal gold stitches on the broad ivory welt.
    for i in range(395):
        x=19+i;y=wave(x)
        d.append(path(f'M{x:.2f},{y+.9:.2f} l.45,3.8','none',('#c4a157' if i%3 else '#f6e8bd'),.16,'opacity=".74"'))
    for cx in [25,38,52,67,82,97,112,127,141,155,169,184,199,214,229,244,259,273,287,302,317,332,347,362,377,392,407]:
        cy=wave(cx)+2.65
        d += [rosette(cx,cy,1.2,'#f4e3b4',.94),ellipse(cx,cy,.31,.4,'#b58d39')]
    # Corner gathered silk finials, which conceal the pelmet's sawn ends.
    for x in [14.4,416.9]:
        d += [path(f'M{x-2.8},0 L{x+2.4},0 L{x+2},32 Q{x},40 {x-2.5},32Z','url(#csilk)','#b29551',.35)]
        for k in range(5):d.append(path(f'M{x-1.8+k*.83},.6 Q{x-3+k*.8},17 {x-1.4+k*.65},32','none',('#ddc985' if k%2 else '#967c42'),.25))
    write_part(ROOT/'parts/bitmap-1757.svg',[0,0,432,211],''.join(d))

if __name__=='__main__':
    frame1756();curtain1757()
    for id,w in [(1756,121),(1757,432)]:
        render(ROOT/f'parts/bitmap-{id}.svg',w,ROOT/f'previews/bitmap-{id}-1x.png')
        render(ROOT/f'parts/bitmap-{id}.svg',w*4,ROOT/f'previews/bitmap-{id}-4x.png')
        print('Created',id)
