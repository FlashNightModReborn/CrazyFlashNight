"""R7 editable SVG -> native XFL. Raster inputs retain their original embedded bytes.

The existing tutorial assembly command selects this module through layout.artRevision.
Native texture caches are produced by CS6; this module never writes SWF bytes.
"""
from pathlib import Path
import argparse,base64,copy,hashlib,importlib.util,io,json,sys,math
import xml.etree.ElementTree as ET
from PIL import Image

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
ART=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/教程-R7'
SOURCE=ART/'教程房-R7-bold-全图.svg'
WORK=HERE/'r7'
TARGET=ROOT/'flashswf/backgrounds/cf6/CF6_Tutorial_BG'
IMPORT_NAME='CF6_A01_TutorialR7Textures01'
IMPORT_TARGET=ROOT/'flashswf/backgrounds/cf6'/IMPORT_NAME
N='{http://ns.adobe.com/xfl/2008/}'
NS={'x':N[1:-1]}

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def digest(b):return hashlib.sha256(b).hexdigest()
def encoded(value):return (json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode('utf-8')

def expand_cropped_patterns(root,api):
    """Keep source pixels and exact SVG tile clipping; never stretch/crop the image bytes."""
    svg='{http://www.w3.org/2000/svg}'
    defs=ET.SubElement(root,svg+'defs');report=[]
    byid={n.get('id'):n for n in root.iter() if n.get('id')}
    for parent in list(root.iter()):
        for index,node in enumerate(list(parent)):
            fill=node.get('fill','')
            if not fill.startswith('url(#r4-original-'):continue
            name=fill[5:-1];pattern=byid[name]
            assert pattern.get('patternUnits')=='userSpaceOnUse' and len(pattern)==1
            img=pattern[0];assert api.tag(img)=='image'
            assert not (set(node.attrib)-{'d','fill','opacity'}) and api.tag(node)=='path'
            assert not img.get('transform') and not img.get('x') and not img.get('y') and not pattern.get('viewBox')
            w,h=float(pattern.get('width')),float(pattern.get('height'))
            assert float(img.get('width'))>=w and float(img.get('height'))==h
            transform=api.base.transform(pattern.get('patternTransform'))
            a,b,c,d,x,y=transform;det=a*d-b*c;assert abs(det)>1e-6
            inverse=lambda px,py:((d*(px-x)-c*(py-y))/det,(-b*(px-x)+a*(py-y))/det)
            corners=[inverse(px,py) for px,py in [(0,0),(1020,0),(0,450),(1020,450)]]
            xs=[p[0] for p in corners];ys=[p[1] for p in corners]
            tile_id=name+'-native-tile';clip_id=tile_id+'-clip';shape_id=name+'-native-shape'
            clip=ET.SubElement(defs,svg+'clipPath',{'id':clip_id})
            ET.SubElement(clip,svg+'rect',{'x':'0','y':'0','width':str(w),'height':str(h)})
            tile=ET.SubElement(defs,svg+'g',{'id':tile_id,'clip-path':'url(#'+clip_id+')'})
            tile.append(copy.deepcopy(img))
            clip=ET.SubElement(defs,svg+'clipPath',{'id':shape_id})
            ET.SubElement(clip,svg+'path',{'d':node.get('d'),'fill':'white'})
            group=ET.Element(svg+'g',{'clip-path':'url(#'+shape_id+')','opacity':node.get('opacity','1')})
            tiled=ET.SubElement(group,svg+'g',{'transform':pattern.get('patternTransform','')})
            count=0
            for col in range(math.floor(min(xs)/w)-1,math.ceil(max(xs)/w)+1):
                for row in range(math.floor(min(ys)/h)-1,math.ceil(max(ys)/h)+1):
                    ET.SubElement(tiled,svg+'use',{'href':'#'+tile_id,'x':str(col*w),'y':str(row*h)})
                    count+=1
            parent.remove(node);parent.insert(index,group)
            report.append({'id':name,'sourceTile':[w,h],'imageExtent':[float(img.get('width')),float(img.get('height'))],
                'nativeTiles':count,'policy':'native image instances with original per-tile and shape masks; embedded bytes unchanged'})
    assert len(report)==3
    clip=ET.SubElement(defs,svg+'clipPath',{'id':'r7-root-viewport'})
    ET.SubElement(clip,svg+'rect',{'x':'0','y':'0','width':'1000','height':'450'})
    group=ET.Element(svg+'g',{'clip-path':'url(#r7-root-viewport)'})
    for child in list(root):
        if api.tag(child) not in api.SKIP:root.remove(child);group.append(child)
    root.append(group)
    return report

def convert():
    api=load('cf6_tutorial_r7_vector',ROOT/'tools/cf6-map-runtime/native-vector/build-a01.py')
    builder=load('cf6_tutorial_r7_import',ROOT/'tools/cf6-map-runtime/build.py')
    original=SOURCE.read_bytes();source=ET.fromstring(original)
    assert source.get('viewBox')=='0 0 1000 450','R7 map coordinate system changed'
    inputs=[];textures={};files={}
    for node in source.iter():
        if api.tag(node)!='image':continue
        href=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href') or ''
        if not href.startswith(('data:image/png;base64,','data:image/jpeg;base64,')):
            raise ValueError('R7 accepts only the supplied embedded PNG/JPEG bytes')
        b=base64.b64decode(href.split(',',1)[1],validate=True);sha=digest(b)
        if sha in textures:continue
        name='intrinsic-'+sha[:24]+('.png' if href.startswith('data:image/png;') else '.jpg')
        with Image.open(io.BytesIO(b)) as image:pixels=list(image.size)
        p=WORK/'textures'/name;files[p]=b
        textures[sha]={'name':name,'pixels':pixels}
        inputs.append({'path':p.relative_to(ROOT).as_posix(),'sha256':sha,'bytes':len(b),'pixels':pixels})
    pattern_expansions=expand_cropped_patterns(source,api)
    converter=api.Candidate(SOURCE,textures=textures,allow_filters=True)
    converter.root=source;converter.byid={n.get('id'):n for n in source.iter() if n.get('id')}
    elements=converter.walk_native(source)
    assert converter.used_textures==set(textures),'unconsumed R7 texture'
    placed=converter.instance(elements,'tutorial-r7-native',(1,0,0,1,0,0))
    timeline=api.E('DOMTimeline',{'name':'CF6_Tutorial_BG'})
    layers=api.E('layers',parent=timeline)
    frames=api.E('frames',parent=api.E('DOMLayer',{'name':'initialize-then-bake'},layers))
    frame=api.E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},frames);api.E('elements',parent=frame)
    frame=api.E('DOMFrame',{'index':'1','duration':'1','keyMode':'9728'},frames);api.E('elements',parent=frame)
    guard=api.background_script().replace('_root._saveExt.bookRun.routeId=="historical"',
        '(_root._saveExt.bookRun.routeId=="historical" || _root._saveExt.bookRun.routeId=="type61")')
    api.E('script',parent=api.E('Actionscript',parent=frame)).text=guard
    frames=api.E('frames',parent=api.E('DOMLayer',{'name':'R7 较重边线'},layers))
    frame=api.E('DOMFrame',{'index':'0','duration':'2','keyMode':'9728'},frames)
    api.E('elements',parent=frame).append(placed)
    for name,tree in converter.symbols.items():files[WORK/'LIBRARY'/(name+'.xml')]=ET.tostring(tree,encoding='utf-8',xml_declaration=True)
    files[WORK/'timeline.xml']=ET.tostring(timeline,encoding='utf-8',xml_declaration=True)
    import_layers=[{'id':'texture-'+str(i),'png':row['path'],'x':0,'y':0,'width':row['pixels'][0],'height':row['pixels'][1],'depth':i} for i,row in enumerate(inputs)]
    recipe=builder.jsfl({'id':'tutorial-r7-textures','nativeBounds':[0,0,1000,450],'worldScale':1},import_layers,IMPORT_NAME,IMPORT_TARGET/(IMPORT_NAME+'.xfl'))
    # Existing controlled import runner requires its owned recipe directory.
    recipe_path=ROOT/'tools/cf6-map-runtime/native-vector/layers'/IMPORT_NAME/'import-textures.jsfl'
    files[recipe_path]=recipe.encode('utf-8')
    manifest={'schema':'cf6-tutorial-r7-native.v1','source':SOURCE.relative_to(ROOT).as_posix(),
        'sourceSha256':digest(original),'sourceBytes':len(original),'selectedOutline':'bold',
        'inputs':inputs,'textures':textures,'symbols':list(converter.symbols),
        'nativeShapes':converter.shape_count,'nativeSymbols':len(converter.symbols),
        'gradientUses':converter.generated_gradients,'masks':converter.masks,
        'patterns':converter.pattern_reports,'croppedPatternTiles':pattern_expansions,'filters':converter.filter_reports,
        'gradientFallbacks':converter.gradient_fallbacks,'imagePlacements':converter.image_reports,
        'sourceViewport':[0,0,1000,450],'runtimeScaleOwner':'Cf6MapPresentation; no extra source scale',
        'sourceLimitations':['Original package includes three bitmap textures; map and furniture geometry remain editable vectors.','Native rendering requires actual CS6 and game verification.'],
        'generatorInputs':[{'path':p.relative_to(ROOT).as_posix(),'sha256':digest(p.read_bytes())} for p in [Path(__file__),ROOT/'tools/cf6-map-runtime/native-vector/build-a01.py',ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',ROOT/'tools/cf6-map-runtime/build.py']]}
    files[WORK/'conversion.json']=encoded(manifest)
    return files,manifest

def write_or_check(files,check):
    for p,b in files.items():
        if check:
            if not p.is_file() or p.read_bytes()!=b:raise ValueError('Stale R7 generated file: '+str(p.relative_to(ROOT)))
        else:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)

def capture_media():
    native=load('cf6_tutorial_r7_native_xfl',ROOT/'tools/cf6-map-runtime/native_xfl.py')
    manifest=json.loads((WORK/'conversion.json').read_text(encoding='utf-8'))
    native.audit(IMPORT_TARGET/(IMPORT_NAME+'.xfl'),manifest['inputs'])
    doc=ET.parse(IMPORT_TARGET/'DOMDocument.xml').getroot()
    files={}
    for item in doc.findall('./x:media/x:DOMBitmapItem',NS):
        for folder,field in [('LIBRARY','href'),('bin','bitmapDataHRef')]:
            relative=Path(folder)/item.get(field)
            source=IMPORT_TARGET/relative
            assert source.resolve().is_relative_to(IMPORT_TARGET.resolve()) and source.is_file()
            files[WORK/'native-media'/relative]=source.read_bytes()
    for child in list(doc):
        if child.tag!=N+'media':doc.remove(child)
    files[WORK/'native-media/DOMDocument.xml']=ET.tostring(doc,encoding='utf-8',xml_declaration=True)
    files[WORK/'native-media/closure.json']=encoded({'schema':'cf6-tutorial-r7-native-media.v1',
        'sourceImport':IMPORT_TARGET.relative_to(ROOT).as_posix(),
        'files':[{'path':p.relative_to(WORK/'native-media').as_posix(),'sha256':digest(b),'bytes':len(b)} for p,b in files.items()]})
    for p,b in files.items():
        if p.exists() and p.read_bytes()!=b:raise ValueError('Refusing to replace an existing native media snapshot')
    write_or_check(files,False)

def geometry_from_art(layout,legacy):
    from collections import deque
    spec=layout['r7Geometry'];wb=layout['world']['walkBounds'];paths=spec['blockedPolygons']
    geo={'spawn':layout['spawn'],'spawnAdjusted':False,'blockedPaths':paths,
        'collisions':legacy.geometry.filled_trapezoids(paths,wb),
        'exit':{'direction':'右','rect':spec['exitRect'],'basis':'R7 door approach; native coordinates before viewport transform'},
        'leftSpawnLine':[59,255,61,440],'rightSpawnLine':[979,440,981,444]}
    def free(p):
        return wb[0]<p[0]<wb[2] and wb[1]<p[1]<wb[3] and sum(legacy.geometry.point_inside(p,q) for q in paths)%2==0
    def clearance(p):
        if not free(p):return False
        for polygon in paths:
            for i,a in enumerate(polygon):
                b=polygon[(i+1)%len(polygon)];dx=b[0]-a[0];dy=b[1]-a[1]
                t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy)))
                if math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)<8:return False
        return True
    assert clearance(geo['spawn'])
    er=spec['exitRect'];center=[(er[0]+er[2])/2,(er[1]+er[3])/2]
    assert clearance(center),'R7 door approach lacks clearance'
    for pickup in layout['pickups']:assert free([pickup['x'],pickup['y']])
    point=lambda c:[wb[0]+2.5+c[0]*5,wb[1]+2.5+c[1]*5]
    cells={(x,y) for x in range(int((wb[2]-wb[0])/5)) for y in range(int((wb[3]-wb[1])/5)) if clearance(point((x,y)))}
    start=min(cells,key=lambda c:math.dist(point(c),geo['spawn']))
    targets={c for c in cells if er[0]<point(c)[0]<er[2] and er[1]<point(c)[1]<er[3]}
    visited={start};queue=deque([start])
    while queue:
        x,y=queue.popleft()
        for adjacent in [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]:
            if adjacent in cells and adjacent not in visited:visited.add(adjacent);queue.append(adjacent)
    assert targets & visited,'R7 door approach unreachable'
    db=spec['doorArtBounds'];assert db[0]<er[2] and db[2]>er[0] and db[1]<er[3] and db[3]>er[1]
    import random
    random_source=random.Random('R7-TUTORIAL')
    for i in range(1000):
        p=[random_source.uniform(wb[0],wb[2]),random_source.uniform(wb[1],wb[3])]
        assert sum(legacy.geometry.point_inside(p,q) for q in paths)%2==sum(legacy.geometry.point_inside(p,q) for q in geo['collisions'])%2
    return geo,{'freeGridCells':len(cells),'reachableCells':len(visited),'clearanceNative':8,'exit':geo['exit'],
        'scope':'native source geometry and 8px center clearance; actual avatar collision and traversal require game verification'}

def assemble(legacy,check=False):
    files,manifest=convert()
    native=load('cf6_tutorial_r7_native_xfl',ROOT/'tools/cf6-map-runtime/native_xfl.py')
    cache=WORK/'native-media';closure=json.loads((cache/'closure.json').read_text(encoding='utf-8'))
    for row in closure['files']:
        p=cache/row['path'];b=p.read_bytes()
        assert p.resolve().is_relative_to(cache.resolve()) and digest(b)==row['sha256'] and len(b)==row['bytes']
    native.audit(cache/'DOMDocument.xml',manifest['inputs'])
    doc=ET.parse(cache/'DOMDocument.xml').getroot()
    doc.set('width','1000');doc.set('height','450');doc.set('frameRate','30')
    for item in doc.findall('./x:media/x:DOMBitmapItem',NS):
        item.attrib.pop('sourceExternalFilepath',None)
        for folder,field in [('LIBRARY','href'),('bin','bitmapDataHRef')]:
            relative=Path(folder)/item.get(field);files[TARGET/relative]=(cache/relative).read_bytes()
    symbols=ET.SubElement(doc,N+'symbols')
    for name in manifest['symbols']:
        ET.SubElement(symbols,N+'Include',{'href':name+'.xml','loadImmediate':'false'})
        files[TARGET/'LIBRARY'/(name+'.xml')]=files[WORK/'LIBRARY'/(name+'.xml')]
    ET.SubElement(doc,N+'timelines').append(ET.fromstring(files[WORK/'timeline.xml']))
    files[TARGET/'DOMDocument.xml']=ET.tostring(doc,encoding='utf-8',xml_declaration=True)
    files[TARGET/'PublishSettings.xml']=legacy.build_publish_settings().encode('utf-8')
    files[TARGET/'CF6_Tutorial_BG.xfl']=b'PROXY-CS5'
    layout=json.loads((HERE/'layout.json').read_text(encoding='utf-8'))
    geo,geometry_report=geometry_from_art(layout,legacy)
    files[HERE/'environment.fragment.xml']=legacy.build_environment(layout,geo).encode('utf-8')
    files[HERE/'tutorial-map.fragment.json']=encoded(legacy.build_map_fragment(layout,geo))
    input_paths=[SOURCE,ART/'CF6-教程摆件-R7-Flash边线对照与源包.zip',HERE/'layout.json',HERE/'assemble.py',cache/'closure.json']
    provenance={'schema':'cf6-tutorial-assembly.v3','artRevision':'r7-bold','mapId':'TUTORIAL',
        'sourceArchiveSha256':digest(input_paths[1].read_bytes()),'selectedSource':manifest['source'],
        'nativeShapes':manifest['nativeShapes'],'nativeSymbols':manifest['nativeSymbols'],'intrinsicBitmaps':len(manifest['inputs']),
        'sourceInputs':[{'path':p.relative_to(ROOT).as_posix(),'sha256':digest(p.read_bytes())} for p in input_paths],
        'geometry':geometry_report,'conversion':(WORK/'conversion.json').relative_to(ROOT).as_posix(),
        'outputs':[{'path':p.relative_to(ROOT).as_posix(),'bytes':len(b),'sha256':digest(b)} for p,b in sorted(files.items())],
        'acceptanceBoundary':'deterministic native source assembly; CS6 and actual game evidence recorded separately'}
    files[HERE/'provenance.json']=encoded(provenance)
    write_or_check(files,check)
    result=native.finalize(TARGET/'CF6_Tutorial_BG.xfl','CF6_Tutorial_BG.swf',manifest['inputs'],check=True)
    print(json.dumps({'check':'ok' if check else 'assembled','symbols':result['symbolItems'],
        'textures':result['bitmapItems'],'geometry':geometry_report,'generatedBytes':sum(len(b) for b in files.values())},ensure_ascii=False))

def main():
    parser=argparse.ArgumentParser(__doc__);parser.add_argument('--check',action='store_true')
    parser.add_argument('--capture-native-media',action='store_true')
    args=parser.parse_args()
    if args.capture_native_media:capture_media();print('Captured exact CS6 native media closure.');return
    files,manifest=convert();write_or_check(files,args.check)
    print(json.dumps({k:manifest[k] for k in ('nativeShapes','nativeSymbols','gradientUses','selectedOutline')},ensure_ascii=False))

if __name__=='__main__':main()
