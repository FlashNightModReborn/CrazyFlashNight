"""R7 siege-only rooftop and gate damage. Native art remains editable in XFL.

Run from tools/base-siege-assets with --root pointing at the resources tree.
The two views share M2 damage variants and casualty artwork, not world positions.
"""
from pathlib import Path
from lxml import etree as E
import argparse, copy, json, math, random
from svg_native import NS, tag, sub, inst, layer, symbol, matrix, transform, mul, Converter

SVG = 'http://www.w3.org/2000/svg'
P = 'BaseSiege/R7/'
wash_serial=0

def se(parent, kind, **attrs):
    return E.SubElement(parent, '{'+SVG+'}'+kind,
                        {k.replace('_','-'):str(v) for k,v in attrs.items()})

def art():
    return E.Element('{'+SVG+'}svg', nsmap={None:SVG}, viewBox='0 0 1635 640')

def group(parent, name, tr=None):
    e=se(parent,'g',id=name)
    if tr:e.set('transform',tr)
    return e

def path(parent, d, fill='none', stroke='#30332f', sw=.65, **attrs):
    return se(parent,'path',d=d,fill=fill,stroke=stroke,stroke_width=sw,
              stroke_linecap='round',stroke_linejoin='round',**attrs)

def ellipse(parent,x,y,rx,ry,fill,opacity=1):
    return se(parent,'ellipse',cx=x,cy=y,rx=rx,ry=ry,fill=fill,opacity=opacity)

def wash(parent,x,y,rx,ry,seed,opacity=.20):
    """Local soot with a soft falloff, retaining the original concrete texture."""
    global wash_serial
    wash_serial+=1;gid=f'soot-{seed}-{wash_serial}'
    defs=se(parent,'defs')
    grad=se(defs,'radialGradient',id=gid,gradientUnits='userSpaceOnUse',cx=0,cy=0,r=1,
            gradientTransform=f'translate({x},{y}) scale({rx},{ry})')
    for offset,alpha in [(0,.85),(.28,.65),(.64,.25),(1,0)]:
        se(grad,'stop',offset=offset,stop_color='#202322',stop_opacity=alpha*opacity)
    ellipse(parent,x,y,rx,ry,f'url(#{gid})')

def hit(parent,x,y,size,seed,wall=False):
    r=random.Random(seed)
    g=group(parent,f'hit-{seed}',f'translate({x},{y}) rotate({r.uniform(-18,18):.2f})')
    sx=size*.7;sy=size*(.69 if wall else .32)
    wash(g,0,0,sx*2.1,sy*2.5,seed,.27)
    # An inset hole, shaded at the upper lip. The light lower crescent describes
    # missing concrete instead of outlining a protruding star-shaped rock.
    path(g,f'M{-sx:.2f} 0Q{-sx*.8:.2f} {-sy:.2f} {-sx*.1:.2f} {-sy*.8:.2f}L{sx*.2:.2f} {-sy*1.1:.2f}Q{sx*1.3:.2f} {-sy*.4:.2f} {sx*.9:.2f} {sy*.3:.2f}L{sx*.4:.2f} {sy*.5:.2f}Q{-sx*.2:.2f} {sy*1.2:.2f} {-sx:.2f} 0Z','#555958','none',0)
    ellipse(g,-sx*.1,-sy*.13,sx*.6,sy*.62,'#222626')
    path(g,f'M{-sx*.62:.2f} {sy*.48:.2f}q{sx*.6:.2f} {sy*.5:.2f} {sx*1.13:.2f} {-sy*.23:.2f}',stroke='#a4a8a2',sw=.56,opacity=.8)
    if size>4.1:
        path(g,f'M{-sx*.8:.2f} 0l{-sx*.7:.2f} {-sy*.7:.2f} {-sx*.63:.2f} {sy*.3:.2f}',stroke='#424746',sw=.5,opacity=.75)
    if seed%3==0:
        path(g,f'M{sx*1.4:.2f} {sy*1.8:.2f}l1.2 -.6 .8 .9 -1.4 .2Z','#92938e','#646862',.35)

def burst(parent,name,points,seed,wall=False):
    g=group(parent,name)
    for n,(x,y,size) in enumerate(points):hit(g,x,y,size,seed+n,wall)

def brass(parent,name,x,y,seed,count=12):
    r=random.Random(seed);g=group(parent,name)
    for _ in range(count):
        cx=x+r.uniform(-20,21);cy=y+r.uniform(-6,9)
        q=se(g,'g',transform=f'translate({cx:.2f},{cy:.2f}) rotate({r.uniform(-75,75):.2f})')
        path(q,'M0 0h3.7v1.25H0Z','#92805a','#49483a',.5)
        path(q,'M.6 .3h2.5',stroke='#b3a47b',sw=.42)

def tear(parent,name,x,y,angle=0,scale=1):
    """A small opened seam with fabric flaps and sand resting on the cover."""
    g=group(parent,name,f'translate({x},{y}) rotate({angle}) scale({scale})')
    path(g,'M-12 -1q5 -3 10 -2l3 1 4 -1 6 1q-3 5 -8 5l-5 -1q-6 1 -10 -3Z','#343835','#292e29',.7)
    path(g,'M-12 -1q4 -1 7 0l4 2 -4 1q-5 -1 -7 -3Z','#a4a8a0','#595d57',.6)
    path(g,'M4 -2l1 4q5 0 8 -3l-5 1Z','#b2b6ae','#595d57',.6)
    path(g,'M-3 3q4 -2 7 1l4 4q6 1 7 4q-9 4 -21 0q-5 -1 -2 -3l4 -2Z','#8c8979','#66695e',.5)
    path(g,'M-4 10q4 -5 7 -3l7 4q-8 1 -14 -1Z','#a7a18d','none',0)
    for a,b in [(-8,13),(1,11),(8,13),(16,13),(-5,15),(4,15)]:
        ellipse(g,a,b,.7,.38,'#777967')

def blood(parent,name,x,y,rx,ry):
    g=group(parent,name)
    path(g,f'M{x-rx} {y}q{rx*.3} {-ry*1.2} {rx*.65} {-ry*.7}q{rx*.8} {-ry*.7} {rx*1.25} {ry*.8}l{-rx*.35} {ry*.6} {-rx*.6} {ry*.1} {-rx*.22} {-ry*.3} {-rx*.55} {ry*.1}Z','#4c302c','none',0,opacity=.72)
    ellipse(g,x+rx*.9,y+ry*.7,1.4,.6,'#51342e',.6)

def write_xml(path_, tree):
    path_.parent.mkdir(parents=True,exist_ok=True)
    path_.write_bytes(E.tostring(tree,encoding='utf-8',xml_declaration=True,pretty_print=True))

def color(e,factor):
    sub(sub(e,'color'),'Color',redMultiplier=factor,greenMultiplier=factor,blueMultiplier=factor)
    return e

def masked(name,source,x0,y0,x1,y1):
    svg=art();se(svg,'rect',x=x0,y=y0,width=x1-x0,height=y1-y0,fill='#ffffff')
    shapes=Converter(svg,P+'mask').draw(svg)
    return symbol(name,[layer('cut-outline',shapes,layerType='mask',locked='true'),
                        layer('native-drawing',[inst(source)],parentLayerIndex='0',locked='true')])

def corpse_matrix(kind,x,y,scale,angle,mirror=False):
    # Both original poses use page-space coordinates. Place by visible centre.
    centre={'A':(430,519),'B':(1020,529)}[kind]
    return transform(f'translate({x},{y}) rotate({angle}) scale({-scale if mirror else scale},{scale}) translate({-centre[0]},{-centre[1]})')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);args=parser.parse_args();root=args.root
    roof=root/'flashswf/backgrounds/gk20_5_BG_围攻';gate=root/'flashswf/backgrounds/gk20_1_BG_围攻'
    sources=root/'tools/base-siege-assets/source';sources.mkdir(parents=True,exist_ok=True)
    manifest={'revision':'R7','assets':{},'story':'Two M2 positions suppressed from the air; gunners die beside cover, two assistants are caught withdrawing toward the roof access. The ammunition detonation is local to the original stores.'}
    for folder,view in [(roof,'roof'),(gate,'gate')]:
        symbols={}
        # Same shared gun drawing in both original backgrounds. Keep original source
        # symbols; the R7 copy has its own bounded namespace and no AS linkage.
        gun=E.parse(str(roof/'LIBRARY/Symbol 37.xml')).getroot()
        gun.set('name',P+'m2-native');gun.attrib.pop('itemID',None)
        gun.find('x:timeline/x:DOMTimeline',NS).set('name','m2-native')
        for el in gun.findall('.//x:DOMSymbolInstance',NS):
            # The sole nested instance is the old invisible muzzle/socket marker.
            el.getparent().remove(el)
        symbols[P+'m2-native']=gun
        symbols[P+'m2-receiver']=masked(P+'m2-receiver',P+'m2-native',-90,-100,169,35)
        symbols[P+'m2-barrel']=masked(P+'m2-barrel',P+'m2-native',172,-100,340,35)
        split=art()
        path(split,'M165 -51l8 2 -5 4 4 4 -8 2Z','#61685f','#272c28',1)
        path(split,'M165 -49l4 3 -3 3',stroke='#a4aaa0',sw=1)
        cv=Converter(split,P+'gun-break');splitels=cv.draw(split);symbols.update(cv.symbols)
        # One snapped barrel; one sagged gun with a broken trunnion. Components
        # follow the original manual M2 drawing; there are no invented power cables.
        symbols[P+'m2-post-upper']=symbol(P+'m2-post-upper',[
            layer('exposed-fracture',splitels),
            layer('receiver', [color(inst(P+'m2-receiver'),.83)]),
            layer('detached-barrel',[color(inst(P+'m2-barrel',transform('translate(-5,55) rotate(157) translate(-172,43)')),.79)])])
        symbols[P+'m2-post-lower']=symbol(P+'m2-post-lower',[
            layer('barrel-fracture',copy.deepcopy(splitels)),
            layer('sagged-barrel',[color(inst(P+'m2-barrel',transform('translate(169,-42) rotate(33) translate(-172,42)')),.81)]),
            layer('receiver',[color(inst(P+'m2-receiver'),.86)])])
        for k,num in [('A',17),('B',18)]:
            b=E.parse(str(roof/f'LIBRARY/BaseSiege/casualties/part{num}.xml')).getroot()
            b.set('name',P+'casualty-'+k);b.attrib.pop('itemID',None)
            b.find('x:timeline/x:DOMTimeline',NS).set('name','casualty-'+k)
            symbols[P+'casualty-'+k]=b

        surface=art();cover=art();stains=art()
        if view=='roof':
            # Impacts stop at obstacles and resume in bursts in the open retreat lane.
            burst(surface,'upper-post-sweep',[(1564,247,5.4),(1546,256,4.3),(1526,261,3.5),(1505,270,4.8)],101)
            burst(surface,'lower-post-sweep',[(1607,324,5.3),(1585,332,4.4),(1568,342,4),(1547,346,4.5)],111)
            burst(surface,'withdrawal-near-cover',[(1477,371,4.5),(1454,376,3.7),(1436,380,4.9),(1418,384,3.2)],121)
            burst(surface,'withdrawal-past-equipment-room',[(1266,392,3.9),(1243,399,4.8),(1222,401,3.2),(1203,406,4.1)],131)
            burst(surface,'withdrawal-first-casualty',[(1111,422,4.9),(1087,429,3.6),(1064,432,5.2),(1043,437,3.4)],141)
            burst(surface,'withdrawal-last-casualty',[(803,462,4.2),(782,469,3.7),(756,473,5.0),(734,480,3.7),(710,487,4.1)],151)
            # Fire catches stored ammunition beside the roof access. The concrete is
            # scarred locally; no flat polygon rockets, full-height crate stripes or
            # unexplained hole in the load-bearing roof.
            blast=group(surface,'ammunition-local-detonation')
            wash(blast,367,483,116,35,42,.55);wash(blast,348,483,61,18,44,.52)
            path(blast,'M324 481q8 -5 16 -3l7 -3q12 -2 19 3l10 -1q8 1 10 6l-8 4q-9 4 -18 0l-9 2 -9 -4q-12 1 -18 -4Z','#4e5350','#444a46',.6,opacity=.75)
            path(blast,'M332 482q12 -4 18 -2l12 -1 13 4 -12 2 -18 -1Z','#343a36','none',0,opacity=.7)
            path(blast,'M326 484l11 2 10 3 12 -2 10 2 8 -2',stroke='#94978c',sw=.8,opacity=.55)
            for d in ['M319 482l-14 -5 -9 2 -14 -3','M342 490l-4 7 -15 3 -7 6','M374 478l17 -5 11 2 13 -4','M382 489l14 6 16 -1 9 5']:
                path(blast,d,stroke='#444940',sw=.75,opacity=.7)
            r=random.Random(55)
            for i in range(24):
                a=r.uniform(0,math.tau);rad=r.uniform(28,116);x=356+math.cos(a)*rad;y=484+math.sin(a)*rad*.32
                q=se(blast,'g',transform=f'translate({x:.2f},{y:.2f}) rotate({r.uniform(-40,40):.2f})')
                path(q,'M-2 0l3 -1.4 2 .6 .8 1.2 -3 1.2Z',r.choice(['#7c8072','#555c51','#999c8e']),'#42483e',.55)
            burst(surface,'ammunition-strike',[(482,459,4.5),(459,466,3.8),(437,471,4.2)],161)
            brass(surface,'upper-post-expended-cases',1522,278,222,14)
            brass(surface,'lower-post-expended-cases',1570,363,223,11)
            tear(cover,'upper-post-torn-sandbag',1604,225,37,.85)
            tear(cover,'lower-post-torn-sandbag',1632,303,38,.9)
            burst(cover,'equipment-room-side-spalls',[(1382,300,3.1),(1371,310,4.2),(1361,321,3.4)],171,True)
            burst(cover,'post-edge-chips',[(1595,218,3.9),(1610,240,4.8),(1625,261,3.5),(1633,297,5.1)],181,True)
            bodies=[('A',1472,262,.84,-5,False,'upper-gunner'),('B',1532,341,.86,7,True,'lower-gunner'),
                    ('B',1094,418,.88,-9,False,'retreat-near-room'),('A',714,470,.88,-7,True,'retreat-near-access')]
            for name,x,y,rx,ry in [('upper-gunner',1524,272,12,3.6),('lower-gunner',1581,351,13,4),('retreat-near-room',1057,435,10,3.2),('retreat-near-access',675,485,11,3.8)]:blood(stains,name,x,y,rx,ry)
            guns=[('m2-post-upper',(1571.9,247.5),3),('m2-post-lower',(1607.9,315.5),12)]
            # Stored rocket fragments reuse the original casing, paint and fins.
            for k,b in [('rocket-front',(82,-2,173,29)),('rocket-rear',(-2,-2,71,29))]:
                piece=masked(P+k,'Symbol 27',*b)
                cut=art()
                edge=("M82 7l3 2 -3 3 2 3 -3 3 2 2" if k=='rocket-front' else "M70 7l-3 2 3 3 -2 3 3 3 -2 2")
                path(cut,edge,stroke='#303732',sw=2)
                path(cut,edge,stroke='#7d8279',sw=.65)
                cv=Converter(cut,P+'rocket-cut');shapes=cv.draw(cut)
                piece.find('x:timeline/x:DOMTimeline/x:layers',NS).append(layer('charred-fracture',shapes))
                # Place the fracture above the masked art while keeping mask indexes.
                ls=piece.find('x:timeline/x:DOMTimeline/x:layers',NS)
                fracture=ls[-1];ls.remove(fracture);ls.insert(0,fracture);ls[2].set('parentLayerIndex','1')
                symbols[P+k]=piece
            rockets=[]
            for kind,x,y,s,a,flip in [('rocket-front',404,488,.58,-9,1),('rocket-rear',307,472,.65,14,1),('rocket-front',354,508,.46,164,1),('rocket-rear',441,496,.43,-17,1),('rocket-rear',285,498,.34,-27,1)]:
                origin=82 if kind=='rocket-front' else 0
                m=transform(f'translate({x},{y}) rotate({a}) scale({s},{s}) translate({-origin},-13)')
                rockets.append(color(inst(P+kind,m),.49))
        else:
            burst(surface,'upper-position-roof-strike',[(131,124,4.6),(115,130,3.5),(94,140,4.4),(73,148,3.4)],201)
            burst(surface,'lower-position-roof-strike',[(54,206,4.7),(37,212,3.7),(17,221,4.2),(0,227,3.6)],211)
            brass(surface,'upper-post-expended-cases',86,151,222,14)
            brass(surface,'lower-post-expended-cases',7,235,223,11)
            # The visible diagonal is the parapet/wall edge. Surface holes are not
            # pasted into the vertical garage door; the wall has its own projection.
            tear(cover,'upper-post-torn-sandbag',200,128,-39,.85)
            tear(cover,'lower-post-torn-sandbag',116,211,-39,.9)
            burst(cover,'upper-parapet-spalls',[(244,145,4.7),(232,158,4.1),(219,172,5.1),(209,185,3.3)],221,True)
            burst(cover,'lower-parapet-spalls',[(160,228,4.4),(148,242,5.0),(135,256,3.8),(123,269,4.3)],231,True)
            path(cover,'M232 151l-4 -6 2 -6 -3 -5',stroke='#464b45',sw=.75)
            path(cover,'M149 236l-6 -3 -1 -9 -4 -5',stroke='#464b45',sw=.75)
            bodies=[('A',32,112,.76,-12,False,'upper-gunner'),('B',58,222,.70,-7,False,'lower-gunner')]
            blood(stains,'upper-gunner',77,117,10,3.2)
            blood(stains,'lower-gunner',14,238,10,3.2)
            guns=[('m2-post-upper',(110,155.9),3),('m2-post-lower',(19,235.85),12)]
            rockets=[]

        for name,svg in [('surface',surface),('cover',cover),('stains',stains)]:
            cv=Converter(svg,P+view+'-'+name);cv.convert(svg,P+view+'-'+name);symbols.update(cv.symbols)
            write_xml(sources/f'r7-{view}-{name}.svg',svg)
        doc=E.parse(str(folder/'DOMDocument.xml'));layers=doc.find('x:timelines/x:DOMTimeline/x:layers',NS)
        for la in list(layers):
            if la.get('name','').startswith(('R6-','R7-')):layers.remove(la)
        if view=='gate':
            bgpath=folder/'LIBRARY/BaseSiege/gate-without-helicopter.xml';bg=E.parse(str(bgpath))
            for el in bg.findall('.//x:DOMSymbolInstance',NS):
                if el.get('libraryItemName')=='Symbol 32':el.getparent().remove(el)
            write_xml(bgpath,bg)
        weapon_els=[]
        base=(.324432373046875,-.0677490234375,.0677490234375,.324432373046875,0,0)
        for variant,(x,y),angle in guns:
            m=mul(transform(f'translate({x},{y})'),mul(base,transform(f'rotate({angle})')))
            weapon_els.append(inst(P+variant,m))
        bodyels=[]
        for kind,x,y,s,a,mir,label in bodies:
            body=inst(P+'casualty-'+kind,corpse_matrix(kind,x,y,s,a,mir))
            body.set('name',label.replace('-','_'));bodyels.append(body)
        additions=[layer('R7-destroyed-M2-posts',weapon_els),layer('R7-cover-and-wall-strikes',[inst(P+view+'-cover')]),
                   layer('R7-fallen-defenders',bodyels),
                   layer('R7-ammunition-fragments',rockets),layer('R7-ground-evidence',[inst(P+view+'-surface'),inst(P+view+'-stains')])]
        for i,la in enumerate(additions,1):layers.insert(i,la)
        includes=doc.find('x:symbols',NS)
        for el in list(includes):
            if el.get('href','').startswith(P):includes.remove(el)
        for name,xml in sorted(symbols.items()):
            write_xml(folder/'LIBRARY'/(name+'.xml'),xml)
            sub(includes,'Include',href=name+'.xml')
        write_xml(folder/'DOMDocument.xml',doc)
        manifest['assets'][folder.name]={'defenders':[{'id':label,'pose':kind,'centre':[x,y],'scale':s,'rotation':a,'mirror':mir} for kind,x,y,s,a,mir,label in bodies],
              'M2':[{'variant':name,'origin':xy,'additionalRotation':a} for name,xy,a in guns],
              'symbols':len(symbols),'sourceSvgs':[f'r7-{view}-{k}.svg' for k in ['surface','cover','stains']]}
    (sources/'revision-r7-detail.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'ok':True,'revision':'R7','roofDefenders':4,'gateDefenders':2,'targets':list(manifest['assets'])},ensure_ascii=False))

if __name__=='__main__':main()
