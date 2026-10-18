"""Native R8 siege casualty and emplacement revision.

Original bloody-death rig poses, A-company clothes and four original hairstyles.
The two map views share each gunner's body, hair and weapon condition.
No live units, death scripts, global exports or runtime gameplay are introduced.
"""
from pathlib import Path
from lxml import etree as E
import argparse, copy, json, sys, math, hashlib, re

P = 'BaseSiege/R8/'
S = 'http://www.w3.org/2000/svg'
IDS = ('upper-gunner', 'lower-gunner', 'retreat-near-room', 'retreat-near-access')
HAIRS = ('黑中分头', '黑朋克头', '精武短发', '黑马尾头')
POSES = (60, 174, 290, 414)  # Zero-based frames in original bloody-death Symbol 825.


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument('--donors', type=Path)
    args = ap.parse_args()
    root = args.root
    donors = args.donors or root
    sys.path.insert(0, str(donors/'tools/base-siege-assets'))
    sys.path.insert(0, str(donors/'tools/asset-metrology'))
    from svg_native import NS, tag, sub, inst, layer, symbol, matrix, transform, mul, Converter
    from xfl_geometry import Geometry, bounds
    from refine_roof_r7 import art, path, group, ellipse, wash, write_xml, color
    sources = root/'tools/base-siege-assets/source'
    sources.mkdir(parents=True, exist_ok=True)
    roof = root/'flashswf/backgrounds/gk20_5_BG_围攻'
    gate = root/'flashswf/backgrounds/gk20_1_BG_围攻'
    lib = roof/'LIBRARY'
    symbols = {}

    def mat(el):
        m = el.find('x:matrix/x:Matrix', NS)
        return tuple(float(m.get(k, 1 if k in ('a','d') else 0)) for k in ('a','b','c','d','tx','ty')) if m is not None else (1,0,0,1,0,0)

    def at(doc, fr):
        for la in reversed(doc.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)):
            for f in la.findall('./x:frames/x:DOMFrame', NS):
                if int(f.get('index')) <= fr < int(f.get('index'))+int(f.get('duration',1)):
                    yield from f.findall('./x:elements/x:DOMSymbolInstance', NS)

    def put(name, xml):
        symbols[name] = xml
        # Geometry below reads the staged library, not the production files.
        write_xml(lib/(name+'.xml'), xml)
        return name

    def vector(svg, name):
        cv = Converter(svg, name)
        cv.convert(svg, name)
        for k,v in cv.symbols.items(): put(k,v)
        return name

    def bbox(name):
        return bounds(Geometry(lib).symbol(name))

    def mapped_point(m, x, y):
        return (m[0]*x+m[2]*y+m[4], m[1]*x+m[3]*y+m[5])

    def cloned(name, source_lib, dest_prefix, visited=None):
        visited = visited if visited is not None else {}
        if name in visited: return visited[name]
        new = dest_prefix+name
        visited[name] = new
        node = E.parse(str(source_lib/(name+'.xml'))).getroot()
        node.set('name',new)
        for k in list(node.attrib):
            if k.startswith('linkage') or k in ('itemID','lastModified'): node.attrib.pop(k)
        node.set('symbolType','graphic')
        node.find('x:timeline/x:DOMTimeline',NS).set('name',new.rsplit('/',1)[-1])
        for script in node.findall('.//x:Actionscript',NS): script.getparent().remove(script)
        for e in node.findall('.//x:DOMSymbolInstance',NS):
            e.set('libraryItemName',cloned(e.get('libraryItemName'),source_lib,dest_prefix,visited))
            e.set('symbolType','graphic');e.set('loop','single frame');e.set('firstFrame','0')
        put(new,node)
        return new

    # Rebind original A-company equipment to the original death rig, part for part.
    skin_file = donors/'tools/base-siege-assets/source/casualty-A-short-crop.svg'
    donor = E.parse(str(skin_file)).xpath('//*[@id="character"]')[0]
    action_file = donors/'flashswf/arts/things0/LIBRARY/sprite/Symbol 825.xml'
    action = E.parse(str(action_file))
    skins = {}
    for part in donor:
        m = transform(part.get('transform'))
        matches = [e for e in at(action,60) if max(abs(a-b) for a,b in zip(mat(e),m)) < .001]
        assert len(matches)==1
        skins[matches[0].get('libraryItemName')] = copy.deepcopy(part)
    fields = {}
    head_field = next(k for k in skins if k.rsplit('/',1)[-1]=='头')
    torso_field = next(k for k in skins if k.rsplit('/',1)[-1]=='身体')
    for i,(field,g) in enumerate(skins.items()):
        g.attrib.pop('transform',None)
        if field==head_field: continue
        fields[field] = vector(g,P+f'body-parts/part-{i:02}')
    head = skins[head_field]
    face = vector(head[0],P+'body-parts/face')
    mask = vector(head[2],P+'body-parts/mask')
    hair_matrix = transform(head[1].get('transform'))

    # Two unaltered native environmental blood drawings; opaque native red.
    pools = []
    for n in (23,87):
        p = sources/f'r8-native-blood-{n}.svg'
        if not p.exists():
            p.write_bytes((donors/'tools/base-siege-assets/source'/p.name).read_bytes())
        pool_svg=E.parse(str(p)).getroot()
        if n==87:
            # This source also contains distant curled spray. Keep its settled
            # central contact patch and nearby drops, not detached airborne arcs.
            from fontTools.pens.boundsPen import BoundsPen
            from fontTools.svgLib.path import parse_path
            for el in pool_svg.findall('.//{'+S+'}path'):
                kept=[]
                for d in re.findall(r'M[^M]+',el.get('d')):
                    pen=BoundsPen(None);parse_path(d,pen)
                    if pen.bounds and pen.bounds[2]<55:kept.append(d)
                el.set('d',''.join(kept))
        pools.append(vector(pool_svg,P+f'blood/native-{n}'))

    body_meta = {}
    for i,(ident,hair,fr) in enumerate(zip(IDS,HAIRS,POSES)):
        native_hair = cloned('发型/发型-男式-'+hair,
                             donors/'flashswf/arts/things切割/LIBRARY',P+'hair/')
        hn = P+'heads/'+ident
        put(hn,symbol(hn,[layer('mask',[inst(mask)]),
                         layer('native-hair',[inst(native_hair,hair_matrix)]),
                         layer('face',[inst(face)])]))
        elems=[];head_m=None;torso_m=None
        for e in at(action,fr):
            field=e.get('libraryItemName')
            if field==head_field:
                elems.append(inst(hn,mat(e)));head_m=mat(e)
            elif field in fields:
                elems.append(inst(fields[field],mat(e)))
                if field==torso_field:torso_m=mat(e)
        assert len(elems)==15 and head_m and torso_m
        # A compact cloth wound follows the torso transform; no detached spray.
        bx,by,bw,bh=bbox(fields[torso_field])
        wound=art();g=group(wound,'cloth-impact',f'translate({bx+(bw-bx)*(.52 if i%2 else .68)},{by+(bh-by)*.38})')
        path(g,'M-10 -5l7 -3 4 3 6 -2 -1 5 6 3 -8 2 -1 9 -5 -5 -5 1 2 -5 -7 -2Z','#660000','none',0)
        path(g,'M-3 -2l5 -1 2 4 -4 3 -4 -2Z','#250e10','#17191a',.9)
        path(g,'M-4 7q-2 10 1 21l3 6 2 -4 -2 -9 2 -7 -2 -8Z','#660000','none',0)
        wound_name=vector(wound,P+'wounds/'+ident)
        raw=P+'poses/'+ident
        put(raw,symbol(raw,[layer('settled-contact-wound',[inst(wound_name,torso_m)]),layer('native-death-pose',elems)]))
        b=bbox(raw);cx=(b[0]+b[2])/2;bottom=b[3]
        norm=transform(f'scale(.277084350585938,.276901245117188) translate({-cx},{-bottom})')
        hb=bbox(hn);hx,hy=mapped_point(mul(norm,head_m),(hb[0]+hb[2])/2,(hb[1]+hb[3])/2)
        tb=bbox(fields[torso_field]);tx,ty=mapped_point(mul(norm,torso_m),(tb[0]+tb[2])/2,(tb[1]+tb[3])/2)
        pool=pools[i%2];pb=bbox(pool)
        pw=(72,63,77,59)[i];ph=(17,16,18,17)[i]
        px=hx*.58+tx*.42;py=max(hy,ty)+13
        pm=transform(f'translate({px-pw/2},{py-ph/2}) scale({pw/(pb[2]-pb[0])},{ph/(pb[3]-pb[1])}) translate({-pb[0]},{-pb[1]})')
        body=P+'defenders/'+ident
        put(body,symbol(body,[layer('body',[inst(raw,norm)]),layer('native-contact-blood',[inst(pool,pm)])]))
        body_meta[ident]={'hair':hair,'poseFrame0':fr,'nativeAction':'血腥死 / sprite/Symbol 825','bounds':bbox(body),'headCentre':[hx,hy],'poolCentre':[px,py]}

    # Whole native machine gun: receiver, feed box, barrel and stock stay connected.
    gun = E.parse(str(roof/'LIBRARY/Symbol 37.xml')).getroot()
    gun.set('name',P+'m2-native');gun.attrib.pop('itemID',None)
    gun.find('x:timeline/x:DOMTimeline',NS).set('name','m2-native')
    for el in gun.findall('.//x:DOMSymbolInstance',NS):el.getparent().remove(el)
    put(P+'m2-native',gun)
    impact=art()
    # One clear pierced receiver plate, with metal on its lower edge. Smaller
    # impacts continue into the feed box; the barrel is not arbitrarily severed.
    path(impact,'M36 -34l8 -7 10 3 5 10 -7 8 -13 -4 2 -5Z','#101213','#454a49',1.4)
    path(impact,'M39 -24l9 3 6 -4',stroke='#888c87',sw=1.5)
    for x,y in [(78,-29),(112,7)]:
        g=group(impact,f'receiver-hit-{x}',f'translate({x},{y})')
        path(g,'M-6 -1l3 -4 5 1 3 4 -5 4 -5 -1Z','#16191a','#0b0d0e',1.1)
        path(g,'M-5 1l3 3 4 -1',stroke='#80847f',sw=1.2)
    # Dark soot stays within the receiver; the yellow feed belt remains recognizable.
    wash(impact,92,-26,48,18,804,.38)
    path(impact,'M107 -9l9 -3 7 2 4 -2',stroke='#777c77',sw=1.3)
    vector(impact,P+'m2-receiver-damage')
    for variant in ('upper','lower'):
        put(P+'m2-post-'+variant,symbol(P+'m2-post-'+variant,[
            layer('localized-receiver-impacts',[inst(P+'m2-receiver-damage')]),
            layer('complete-native-gun',[color(inst(P+'m2-native'),.89 if variant=='upper' else .94)])]))
    # The lower tripod is toppled as a complete rigid stand, without orphan legs.
    stand=E.parse(str(gate/'LIBRARY/Symbol 28.xml')).getroot()
    stand.set('name',P+'tripod-native');stand.attrib.pop('itemID',None)
    stand.find('x:timeline/x:DOMTimeline',NS).set('name','tripod-native')
    put(P+'tripod-native',stand)
    # Original lower stand's top pin is (-844.1,-39.6), in its native drawing.
    # It meets the original gun at world (93.6,205.5). Preserve that exact joint.
    pin=(-844.1,-39.6)
    base=(.324432373046875,-.0677490234375,.0677490234375,.324432373046875,0,0)
    det=base[0]*base[3]-base[1]*base[2]
    delta=(93.6-26,205.5-232.85)
    gun_pin=((base[3]*delta[0]-base[2]*delta[1])/det,(-base[1]*delta[0]+base[0]*delta[1])/det)
    put(P+'tripod-grounded',symbol(P+'tripod-grounded',[layer('native-tripod',[
        inst(P+'tripod-native',transform(f'scale(1,.65) rotate(-76) translate({-pin[0]},{-pin[1]})'))])]))

    manifest={'revision':'R8','defenders':body_meta,
              'reservedTigrHair':['mercenary-short-dark-crop','发型-男式-平头'],
              'sourceHashes':{'deathRig':hashlib.sha256(action_file.read_bytes()).hexdigest(),'equipmentSkin':hashlib.sha256(skin_file.read_bytes()).hexdigest()},
              'unchangedTigrBodies':{str(n):hashlib.sha256((donors/f'flashswf/backgrounds/gk1_2_BG_围攻/LIBRARY/BaseSiege/casualties/part{n}.xml').read_bytes()).hexdigest() for n in [17,18]},
              'views':{},'weaponStory':{'upper':'receiver struck; complete gun stays seated on its original tripod','lower':'whole gun and tripod knocked down onto the inside of the parapet'}}
    for folder,view in [(roof,'roof'),(gate,'gate')]:
        # Retain valid R7 strafing and wall damage, remove the oversized cloth flaps.
        surface=E.parse(str(donors/f'tools/base-siege-assets/source/r7-{view}-cover.svg')).getroot()
        for e in list(surface):
            if 'torn-sandbag' in e.get('id',''):surface.remove(e)
        seam=group(surface,'small-punctures-in-native-bags')
        points=[(1634,233,30),(1660,307,33)] if view=='roof' else [(197,127,-38),(112,218,-38)]
        for i,(x,y,ang) in enumerate(points):
            g=group(seam,f'bag-{i}',f'translate({x},{y}) rotate({ang})')
            path(g,'M-5 0l4 -1 3 1 3 -1',stroke='#3b3d38',sw=1.05)
            path(g,'M-3 2l4 1 3 -1',stroke='#babbb2',sw=.55)
            # Sand settles immediately below the opened seam, on the bag beneath it.
            path(g,'M-3 5q4 -2 7 0l5 1q-5 2 -12 0Z','#99947f','none',0)
            for dx,dy in [(-2,7),(4,7),(8,6),(1,9)]:ellipse(g,dx,dy,.45,.3,'#7b7868')
        cover_name=vector(surface,P+view+'-cover')
        write_xml(sources/f'r8-{view}-cover.svg',surface)
        bg_name='BaseSiege/original-background' if view=='roof' else 'BaseSiege/gate-without-helicopter'
        bgpath=folder/'LIBRARY'/(bg_name+'.xml');bg=E.parse(str(bgpath))
        lower_stand='Symbol 33' if view=='roof' else 'Symbol 28'
        bag='Symbol 31' if view=='roof' else 'Symbol 27'
        # Values target only the two original top bags. Re-running is idempotent.
        bag_edits={(-18.15,703.3):(.78,-14.0),(56.8,730.3):(.79,60.7)} if view=='roof' else {(-127.75,-733.6):(.78,-123.6),(-33.8,-818.55):(.79,-29.9)}
        for el in bg.findall('.//x:DOMSymbolInstance',NS):
            if el.get('libraryItemName')==lower_stand:el.getparent().remove(el)
            elif el.get('libraryItemName')==bag:
                m=el.find('x:matrix/x:Matrix',NS)
                key=(round(float(m.get('ty','0')),2),round(float(m.get('tx','0')),2))
                if key in bag_edits:
                    d,y=bag_edits[key];m.set('d',str(d));m.set('ty',str(y))
        write_xml(bgpath,bg)
        if view=='roof':
            bodies=[('upper-gunner',1473,275,.86,-5,False),('lower-gunner',1508,349,.84,6,False),
                    ('retreat-near-room',1090,440,.9,-8,True),('retreat-near-access',714,491,.9,4,True)]
            guns=[('upper',1571.9,241.55,0),('lower',1526,378,12)]
            tripod_angle=140
        else:
            bodies=[('upper-gunner',20,146,.76,-10,False),('lower-gunner',0,214,.73,-6,False)]
            guns=[('upper',110,149.9,0),('lower',-2,313,-16)]
            tripod_angle=145
        gunels=[inst(P+'m2-post-'+v,mul(transform(f'translate({x},{y})'),mul(base,transform(f'rotate({a})')))) for v,x,y,a in guns]
        tx,ty=mapped_point(mat(gunels[1]),*gun_pin)
        tripod=(tx,ty,tripod_angle)
        tx,ty,ta=tripod
        gunels.insert(0,inst(P+'tripod-grounded',transform(f'translate({tx},{ty}) rotate({ta})')))
        bodyels=[]
        for ident,x,y,s,a,flip in bodies:
            b=inst(P+'defenders/'+ident,transform(f'translate({x},{y}) rotate({a}) scale({-s if flip else s},{s})'))
            b.set('name',ident.replace('-','_'));bodyels.append(b)
        doc=E.parse(str(folder/'DOMDocument.xml'));ls=doc.find('x:timelines/x:DOMTimeline/x:layers',NS)
        for la in list(ls):
            if la.get('name','').startswith('R8-') or la.get('name') in ('R7-destroyed-M2-posts','R7-cover-and-wall-strikes','R7-fallen-defenders'):ls.remove(la)
            if la.get('name')=='R7-ground-evidence':
                for el in la.findall('.//x:DOMSymbolInstance',NS):
                    if el.get('libraryItemName','').endswith('-stains'):el.getparent().remove(el)
        additions=[layer('R8-grounded-M2-posts',gunels),layer('R8-cover-and-wall-strikes',[inst(cover_name)]),layer('R8-fallen-defenders',bodyels)]
        for i,la in enumerate(additions,1):ls.insert(i,la)
        includes=doc.find('x:symbols',NS)
        for el in list(includes):
            if el.get('href','').startswith(P):includes.remove(el)
        # Both backgrounds receive identical shared identities, including all four
        # bodies, so a future placement cannot accidentally substitute a hairstyle.
        for name,xml in sorted(symbols.items()):
            write_xml(folder/'LIBRARY'/(name+'.xml'),xml)
            sub(includes,'Include',href=name+'.xml')
        write_xml(folder/'DOMDocument.xml',doc)
        manifest['views'][view]={'defenders':[{'id':i,'position':[x,y],'scale':s,'rotation':a,'mirror':f} for i,x,y,s,a,f in bodies],
                                'guns':[{'condition':v,'origin':[x,y],'additionalRotation':a} for v,x,y,a in guns],'fallenTripod':tripod}
    # The gate cover is generated second; keep the shared library closure equal.
    doc=E.parse(str(roof/'DOMDocument.xml'));includes=doc.find('x:symbols',NS)
    known={e.get('href') for e in includes}
    for name,xml in sorted(symbols.items()):
        write_xml(roof/'LIBRARY'/(name+'.xml'),xml)
        if name+'.xml' not in known:sub(includes,'Include',href=name+'.xml')
    write_xml(roof/'DOMDocument.xml',doc)
    (sources/'revision-r8-detail.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'ok':True,'revision':'R8','defenders':body_meta,'nativeSymbols':len(symbols)},ensure_ascii=False))


if __name__=='__main__':main()
