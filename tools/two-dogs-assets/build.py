"""Import approved V6 dogs into the owned CS6 library; never publish SWF here.

Native XFL becomes the editing source after --import-approved. Reimport refuses
to overwrite native edits. Ordinary invocation only checks the current source.
"""
from pathlib import Path
import argparse, copy, hashlib, importlib.util, json, re, sys
import xml.etree.ElementTree as SE
from lxml import etree as E

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ARCHIVE = ROOT/'flashswf/arts/new/Codex素材源稿/两犬-V6'
OWNER = ROOT/'flashswf/arts/new/Codex专用素材'
SOURCE = ROOT/'flashswf/arts/things1/LIBRARY'
PREFIX = 'Codex/两犬/'
X = 'http://ns.adobe.com/xfl/2008/'
N = '{'+X+'}'
NS = {'x': X}
PARSER = E.XMLParser(remove_blank_text=True, strip_cdata=False)
VARIANTS = [('01-military','制式军警犬','敌人-制式军警犬',475),
            ('02-raider','盗贼撕咬犬','敌人-盗贼撕咬犬',476)]
DEATH = {747:1351,748:1352,750:1354,752:1356,754:1358,756:1360,
         758:1362,759:1363,761:1365,763:1367,765:1369,767:1371}
ACTIONS = {739:'idle-dodge',741:'walk-run',743:'attack',744:'hit',
           745:'knockdown',746:'down-thrown',772:'death'}
NORMAL = {726+i:1331+i for i in range(13)}

spec=importlib.util.spec_from_file_location('dog_native_svg',ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py')
svg=importlib.util.module_from_spec(spec);spec.loader.exec_module(svg)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def uid(name): return '6cd10000-'+hashlib.sha256(name.encode('utf-8')).hexdigest()[:8]
def node(tag,attrs=None,parent=None):
    out=E.Element(N+tag,{k:str(v) for k,v in (attrs or {}).items()})
    if parent is not None:parent.append(out)
    return out
def frame(index,duration,elements=()):
    f=node('DOMFrame',{'index':index,'duration':duration,'keyMode':9728})
    holder=node('elements',parent=f)
    for e in elements:holder.append(e)
    return f
def symbol(name,shapes):
    out=E.Element(N+'DOMSymbolItem',{'name':name,'itemID':uid(name),'symbolType':'graphic'},nsmap={None:X})
    layers=node('layers',parent=node('DOMTimeline',{'name':name.rsplit('/',1)[-1]},node('timeline',parent=out)))
    frames=node('frames',parent=node('DOMLayer',{'name':'V6 原生矢量','color':'#648D91'},layers))
    frames.append(frame(0,1,shapes))
    return out
def xml_bytes(tree):
    for script in tree.findall('.//x:script',NS):
        src=script.text or ''
        script.text=E.CDATA('\n'.join(line.expandtabs(4).rstrip(' \t') for line in src.splitlines())+ ('\n' if src.endswith('\n') else ''))
    return E.tostring(tree,encoding='utf-8',xml_declaration=True,pretty_print=True)
def native(path):
    writer=svg.Writer(path)
    shapes=[]
    for shape in writer.walk(writer.root):
        shape=E.fromstring(SE.tostring(shape))
        shape.attrib.pop('isFloating',None);shape.set('isDrawingObject','true')
        shapes.append(shape)
    return shapes,{'shapes':len(shapes),'segments':writer.segment_count}
def tail():
    # A continuous, weighted shepherd tail. Root (0,0) and all rig matrices stay.
    paths=[
        ('M -7 -5 C 22 -6 55 9 72 36 C 86 61 84 89 101 115 Q 116 137 132 143 Q 132 153 119 153 C 99 144 80 131 67 111 C 51 92 34 72 17 46 Q 6 29 -6 13 Q -12 0 -7 -5 Z','#292d32','#11151a',2),
        ('M -4 5 Q 18 15 32 36 C 51 68 63 92 79 113 Q 96 137 120 147 Q 108 147 97 139 L 91 140 Q 79 134 72 124 L 66 123 Q 55 109 48 97 L 43 95 Q 30 74 17 49 Q 8 29 -4 18 Z','#b58a50','none',0),
        ('M 12 25 Q 29 46 42 71 Q 54 96 74 121 Q 82 132 95 140 L 91 140 Q 79 134 72 124 L 66 123 Q 53 108 43 95 Q 30 74 17 49 Z','#775638','none',0),
        ('M 1 -1 Q 34 0 54 22 Q 67 36 72 56 Q 62 36 50 27 Q 31 9 1 7 Z','#373c42','none',0)]
    body=''.join(f'<path d="{d}" fill="{f}" stroke="{s}" stroke-width="{w}" stroke-linejoin="round"/>' for d,f,s,w in paths)
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-15 -12 158 174" data-coordinate-system="flash-local-px" data-origin-x="0" data-origin-y="0"><g>'+body+'</g></svg>'
def matrix(inst):
    m=inst.find('x:matrix/x:Matrix',NS)
    return tuple(float(m.get(k,'1' if k in ('a','d') else '0')) for k in ('a','b','c','d','tx','ty')) if m is not None else (1,0,0,1,0,0)
def point(p,m): return (p[0]*m[0]+p[1]*m[2]+m[4],p[0]*m[1]+p[1]*m[3]+m[5])
def bezier(ps,t):
    while len(ps)>1: ps=[tuple(a*(1-t)+b*t for a,b in zip(p,q)) for p,q in zip(ps,ps[1:])]
    return ps[0]
def polygon(ps):return 'M '+' L '.join(' '.join(f'{v:.7f}' for v in p) for p in ps)+' Z'
def mouth_paths(head,jaw):
    # Lip roots are unchanged. Rear cheek, palate and tongue have separate
    # silhouettes; the anterior gape stays open in this near-lateral view.
    def upper(t):return point(bezier([(0,46),(-13,71),(-20,105),(-27,134)],t),head)
    def lower(t):return point(bezier([(-15,10),(0,14),(14,44),(11,92)],t),jaw)
    def p(t,w):return tuple(a*w+b*(1-w) for a,b in zip(upper(t),lower(t)))
    def xy(v):return ' '.join(f'{x:.7f}' for x in v)
    def curve(start,*commands):
        return 'M '+xy(start)+' '+ ' '.join(op+' '+' '.join(xy(v) for v in ps) for op,ps in commands)+' Z'
    def strip(start,end,lo,hi):
        ts=[start+(end-start)*i/16 for i in range(17)]
        return polygon([p(t,hi) for t in ts]+[p(t,lo) for t in reversed(ts)])
    # The mobile far cheek ends in a curved commissure, behind the front teeth.
    cheek=curve(upper(0),('Q',[upper(.30),upper(.61)]),
        ('C',[p(.46,.78),p(.32,.53),p(.39,.32)]),
        ('Q',[p(.45,.15),lower(.49)]),('Q',[lower(.20),lower(0)]))
    throat=curve(p(.01,.16),('Q',[p(.08,.47),p(.02,.91)]),
        ('Q',[p(.22,.84),p(.31,.65)]),('Q',[p(.25,.38),p(.34,.18)]))
    palate=strip(.02,.98,.88,1)
    floor=strip(.02,.95,0,.11)
    # Retracted tongue: broad root, rounded tip, no long panting projection.
    tongue=curve(p(.02,.07),('Q',[p(.09,.28),p(.25,.32)]),
        ('C',[p(.43,.35),p(.65,.23),p(.75,.17)]),
        ('Q',[p(.83,.10),p(.72,.07)]),('Q',[p(.41,.10),p(.02,.07)]))
    light=curve(p(.18,.27),('Q',[p(.43,.34),p(.69,.18)]),
        ('Q',[p(.51,.23),p(.30,.24)]),('Q',[p(.22,.22),p(.18,.27)]))
    groove=curve(p(.18,.17),('Q',[p(.41,.23),p(.65,.14)]),
        ('Q',[p(.41,.20),p(.18,.15)]))
    paths=[(cheek,'#39232b'),(throat,'#1c1419'),(palate,'#58373f'),
        (floor,'#633e47'),(tongue,'#995d66'),(light,'#bb8386'),(groove,'#75434e')]
    # Subtle palate folds remain attached to the roof, not to the lower jaw.
    for t in (.22,.38,.54):
        paths.append((polygon([p(t,.90),p(t+.018,.90),p(t+.015,.98),p(t-.004,.98)]),'#76505a'))
    return paths
def mouth_shapes(paths):
    out=[]
    for d,color in paths:
        el=SE.Element('path',{'d':d,'fill':color})
        # Use the common native path writer; this helper has no SVG resources.
        writer=object.__new__(svg.Writer);writer.grads={};writer.shape_count=writer.segment_count=0
        shape=E.fromstring(SE.tostring(writer.shape(el,{'fill':color},(1,0,0,1,0,0))))
        shape.attrib.pop('isFloating',None);shape.set('isDrawingObject','true');out.append(shape)
    return out
def active(layer,index):
    for f in layer.findall('x:frames/x:DOMFrame',NS):
        start=int(f.get('index'));duration=int(f.get('duration','1'))
        if start<=index<start+duration:return f
    return None
def add_mouth(tree):
    layers=tree.find('x:timeline/x:DOMTimeline/x:layers',NS)
    total=max(int(f.get('index'))+int(f.get('duration','1')) for f in layers.findall('x:DOMLayer/x:frames/x:DOMFrame',NS))
    positions=[]
    for i,l in enumerate(layers):
        if any(e.get('libraryItemName') in ('Symbol 735','Symbol 737') for e in l.findall('.//x:DOMSymbolInstance',NS)):positions.append(i)
    if not positions:return {'frames':0,'keyframes':0}
    insert=max(positions)+1
    mouth=node('DOMLayer',{'name':'口腔内壁（随双颌姿势）','color':'#7B3C4D'})
    frames=node('frames',parent=mouth)
    samples=[]
    for i in range(total):
        found={}
        for l in layers:
            f=active(l,i)
            if f is None:continue
            for e in f.findall('x:elements/x:DOMSymbolInstance',NS):
                if e.get('libraryItemName') in ('Symbol 735','Symbol 737'):found[e.get('libraryItemName')]=matrix(e)
        sig=(found.get('Symbol 737'),found.get('Symbol 735'))
        if len(found)!=2:sig=(None,None)
        samples.append(sig)
    index=0;count=0
    while index<total:
        end=index+1
        while end<total and samples[end]==samples[index]:end+=1
        head,jaw=samples[index]
        shapes=mouth_shapes(mouth_paths(head,jaw)) if head is not None else []
        frames.append(frame(index,end-index,shapes));count+=bool(shapes);index=end
    for layer in layers:
        parent=layer.get('parentLayerIndex')
        if parent is not None and int(parent)>=insert:layer.set('parentLayerIndex',str(int(parent)+1))
    layers.insert(insert,mouth)
    return {'frames':total,'keyframes':count}
def verify_input():
    manifest=json.loads((ARCHIVE/'approved-input.json').read_text(encoding='utf-8'))
    for rel,want in manifest['artwork'].items():
        if sha(ARCHIVE/rel)!=want:raise ValueError('Approved source drift: '+rel)
def generate_variant(folder,label,linkage,unitid):
    prefix=PREFIX+label+'/'
    generated={};mapping={};reports=[];sources={};mouths={}
    for old,cid in {**NORMAL,**DEATH}.items():
        group='normal' if cid<1351 else 'death'
        path=next((ARCHIVE/'artwork'/folder/group).glob(f'{cid}_*.svg'))
        if folder=='01-military' and cid==1343:
            path=HERE/'refinements/military-tail.svg'
        name=prefix+'分件/'+str(cid)+'-'+path.stem.split('_',1)[-1]
        mapping[f'Symbol {old}']=name
        shapes,report=native(path);generated[name]=symbol(name,shapes)
        reports.append({'historicalSlot':cid,'sourceNative':f'Symbol {old}','name':name,**report})
    def clone(name):
        if name in mapping:return mapping[name]
        mapped=prefix+('敌人-'+label if name=='敌人-僵尸1-狗' else '原生/'+name)
        mapping[name]=mapped
        p=SOURCE/(name+'.xml');sources[str(p.relative_to(ROOT)).replace('\\','/')]=sha(p)
        tree=E.parse(str(p),PARSER).getroot()
        if name.startswith('Symbol ') and int(name.split()[1]) in ACTIONS:
            mouths[name]=add_mouth(tree)
        tree.set('name',mapped);tree.set('itemID',uid(mapped))
        for k in list(tree.attrib):
            if k.startswith('linkage') or k in ('lastModified','lastUniqueIdentifier'):del tree.attrib[k]
        tree.find('x:timeline/x:DOMTimeline',NS).set('name',mapped.rsplit('/',1)[-1])
        if name=='敌人-僵尸1-狗':tree.attrib.update({'linkageExportForAS':'true','linkageExportInFirstFrame':'true','linkageIdentifier':linkage})
        generated[mapped]=tree
        for e in tree.iter():
            ref=e.get('libraryItemName')
            if ref:e.set('libraryItemName',clone(ref))
        return mapped
    root=clone('敌人-僵尸1-狗')
    # Record ALL native source files, including artwork that was replaced.
    for name in mapping:
        p=SOURCE/(name+'.xml');sources[str(p.relative_to(ROOT)).replace('\\','/')]=sha(p)
    return generated,{'folder':folder,'displayName':label,'linkage':linkage,'unitId':unitid,'root':root,'mapping':mapping,'parts':reports,'mouths':mouths},sources
def register():
    # Copy the current zombie-dog numeric and flag data without balance edits.
    prop=ROOT/'data/enemy_properties/原版敌人 2011-2012.xml'
    text=prop.read_text(encoding='utf-8-sig')
    original=re.search(r'    <敌人-僵尸1-狗>.*?    </敌人-僵尸1-狗>',text,re.S).group()
    blocks=[]
    for _,label,linkage,_ in VARIANTS:
        block=original.replace('敌人-僵尸1-狗',linkage).replace('<displayname>野狗</displayname>',f'<displayname>{label}</displayname>')
        blocks.append('\n'.join(line.rstrip() for line in block.splitlines()))
    (ROOT/'data/enemy_properties/两犬.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<root>\n    <!-- 两犬属性逐项照搬原僵尸犬；仅显示名和链接不同。 -->\n'+'\n'.join(blocks)+'\n</root>\n',encoding='utf-8')
    p=ROOT/'data/enemy_properties/list.xml';s=p.read_text(encoding='utf-8')
    if '<items>两犬.xml</items>' not in s:p.write_text(s.replace('</root>','  <items>两犬.xml</items>\n</root>'),encoding='utf-8')
    p=ROOT/'data/units/units.json';raw=p.read_text(encoding='utf-8-sig');units=json.loads(raw)
    base=next(u for u in units if u['id']==13)
    additions=[]
    for _,label,linkage,unitid in VARIANTS:
        match=[u for u in units if u['id']==unitid or u['spritename']==linkage]
        expect=copy.deepcopy(base);expect.update(id=unitid,spritename=linkage,name=label)
        if match and 'key' in match[0]:expect['key']=match[0]['key']
        elif 'key' in expect:del expect['key']
        if match and match!=[expect]:raise ValueError('Unit registration collision: '+str(unitid))
        if not match:additions.append(expect)
    if additions:
        text=',\n'.join('\n'.join('  '+line for line in json.dumps(u,ensure_ascii=False,indent=2).splitlines()) for u in additions)
        p.write_text(raw.rstrip()[:-1].rstrip()+',\n'+text+'\n]\n',encoding='utf-8',newline='\n')
def import_approved():
    verify_input()
    (HERE/'refinements').mkdir(exist_ok=True)
    tailpath=HERE/'refinements/military-tail.svg'
    if tailpath.exists() and tailpath.read_text(encoding='utf-8')!=tail()+'\n':raise ValueError('Tail refinement differs from import')
    tailpath.write_text(tail()+'\n',encoding='utf-8',newline='\n')
    trees={};variants=[];sources={}
    for args in VARIANTS:
        generated,report,source=generate_variant(*args);trees.update(generated);variants.append(report);sources.update(source)
    mp=HERE/'native-manifest.json';prior=json.loads(mp.read_text(encoding='utf-8')) if mp.exists() else {'outputs':[]}
    hashes={r['path']:r['sha256'] for r in prior['outputs']}
    rows=[]
    for name,tree in trees.items():
        p=OWNER/'LIBRARY'/(name+'.xml');rel=str(p.relative_to(OWNER)).replace('\\','/')
        data=xml_bytes(tree)
        if p.exists() and p.read_bytes()!=data and sha(p)!=hashes.get(rel):raise ValueError('Native edits would be overwritten: '+rel)
        rows.append({'path':rel,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)})
    for name,tree in trees.items():
        p=OWNER/'LIBRARY'/(name+'.xml');p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(xml_bytes(tree))
    p=OWNER/'DOMDocument.xml';text=p.read_text(encoding='utf-8-sig');doc=E.fromstring(text.encode('utf-8'),PARSER)
    present={e.get('href') for e in doc.findall('x:symbols/x:Include',NS)}
    additions=['    <Include href="'+name+'.xml" itemID="'+uid(name)+'" loadImmediate="false"/>' for name in sorted(trees) if name+'.xml' not in present]
    if additions:text=text.replace('</symbols>','\n'.join(additions)+'\n  </symbols>')
    # Add actual author folders so the editable source opens cleanly in CS6.
    existing={e.get('name') for e in doc.findall('x:folders/x:DOMFolderItem',NS)}
    folders=sorted({'/'.join(name.split('/')[:i]) for name in trees for i in range(1,len(name.split('/'))) }-existing)
    folderxml='\n'.join('    <DOMFolderItem name="'+name+'" isExpanded="false"/>' for name in folders)
    if folders:
        if '</folders>' in text:text=text.replace('</folders>',folderxml+'\n  </folders>')
        else:text=text.replace('<symbols>','<folders>\n'+folderxml+'\n  </folders>\n  <symbols>',1)
    p.write_text(text,encoding='utf-8')
    register()
    manifest={'schema':'two-dogs.native-import.v1','owner':str(OWNER.relative_to(ROOT)).replace('\\','/'),'approvedInput':str(ARCHIVE.relative_to(ROOT)).replace('\\','/'),'behaviorSource':'敌人-僵尸1-狗','variants':variants,'outputs':rows,'sources':sources,'nativeSymbolCount':len(trees),'refinementSourceSha256':sha(tailpath),'notes':['98 unique native symbols; 50 replaced identity-bearing body/death pieces; original pure blood retained.','Mouth geometry follows native head and jaw per key pose; military tail retains root and rig.','All inherited AS2 scripts and unit numeric values are unchanged. Original zombie dog is untouched.']}
    mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'imported':len(trees),'variants':2,'identityPieces':50},ensure_ascii=False))
def check():
    manifest=json.loads((HERE/'native-manifest.json').read_text(encoding='utf-8'))
    for rel,want in manifest['sources'].items():
        if sha(ROOT/rel)!=want:raise ValueError('Behavior source drift: '+rel)
    for row in manifest['outputs']:
        root=E.parse(str(OWNER/row['path']),PARSER).getroot()
        if root.findall('.//x:DOMBitmapInstance',NS) or root.findall('.//x:BitmapFill',NS):raise ValueError('Unexpected bitmap')
        for el in root.iter():
            ref=el.get('libraryItemName')
            if ref and not (OWNER/'LIBRARY'/(ref+'.xml')).exists():raise ValueError('Missing native reference: '+ref)
    print(json.dumps({'nativeSymbolsChecked':len(manifest['outputs']),'missingReferences':0,'bitmapInstances':0},ensure_ascii=False))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--import-approved',action='store_true');args=parser.parse_args()
    if args.import_approved:import_approved()
    check()
