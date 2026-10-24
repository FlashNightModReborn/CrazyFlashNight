"""Original nested vehicle timelines, with native redraws and no inherited actions.

prepare creates a texture import recipe; assemble requires the real CS6 seed.
This tool never creates SWF or fabricates Flash bitmap records.
"""
from pathlib import Path
import argparse
import base64
import copy
import hashlib
import importlib.util
import io
import json
import re
import sys
import xml.etree.ElementTree as ET
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = HERE/'source'
DEST = ROOT/'flashswf/arts/new/CF6Vehicle'
SEED = HERE/'texture-seed'
SVG = '{http://www.w3.org/2000/svg}'
XLINK = '{http://www.w3.org/1999/xlink}href'
NS = {'x':'http://ns.adobe.com/xfl/2008/'}
EXPORTS = {1803:'Player',1813:'ArmoredBoss',1791:'Road',612:'Raider',629:'Shield',627:'Roadblock',361:'Grenade',
           356:'Bullet',115:'Spark',391:'Explosion'}
EXCLUDE = {277,281,359,360,501,1433,1434,1497,1498,1585,1793,1795,1804,1805,1816}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2)+'\n').encode('utf-8')


def xml(node):
    if node.tag.endswith('DOMDocument'):
        # CS6 consumes library media before resolving symbol dependencies.
        # Printer/publish history must remain after the document content.
        rank={'folders':0,'media':1,'symbols':2,'timelines':3,'PrinterSettings':4,'publishHistory':5}
        children=list(node)
        for child in children:node.remove(child)
        for child in sorted(children,key=lambda item:rank.get(item.tag.split('}')[-1],6)):node.append(child)
    return ET.tostring(node, encoding='utf-8', xml_declaration=True)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec);spec.loader.exec_module(result)
    return result


def prepare():
    inputs = {}
    def read(path):
        raw = path.read_bytes();inputs[path.relative_to(ROOT).as_posix()] = sha(raw);return raw
    nodes = json.loads(read(SOURCE/'original-nodes.json'))['nodes']
    trees = {}
    replacements = {1754:'sky.svg',1785:'parts/bitmap-1784.svg',1787:'asphalt.svg',
                    1788:'asphalt.svg',1790:'parts/bitmap-1789.svg',1807:'armored-body.svg',1809:'armored-wheel.svg'}
    for key, node in nodes.items():
        cid = int(key)
        if node['code'] not in (2,22,32,83) or cid in EXCLUDE:
            continue
        tree = ET.fromstring(read(SOURCE/'ffdec'/f'{cid}.svg'))
        # FFDec exports positive viewport coordinates; the source instances expect
        # the original registration. Remove only the exporter root translation.
        children = [n for n in tree if n.tag == SVG+'g']
        if len(children) != 1:
            raise ValueError('unexpected FFDec shape wrapper '+key)
        children[0].attrib.pop('transform', None)
        if cid in (1797,1799):
            name = 'player-body.svg' if cid == 1797 else 'player-wheel-0.svg'
            tree = ET.fromstring(read(SOURCE/'redraw'/name))
            if cid == 1797:
                group = ET.Element(SVG+'g', {'transform':'translate(-205.5,-72)'})
                for child in list(tree):
                    if child.tag != SVG+'defs':tree.remove(child);group.append(child)
                tree.append(group)
        elif cid in replacements:
            redraw = ET.fromstring(read(SOURCE/'redraw'/replacements[cid]))
            patterns = {n.get('id'):n for n in tree.iter() if n.tag == SVG+'pattern'}
            replaced = 0
            for parent in list(tree.iter()):
                for child in list(parent):
                    styles = dict(part.split(':',1) for part in child.get('style','').split(';') if ':' in part)
                    match = re.fullmatch(r'url\(#([^)]*)\)', child.get('fill',styles.get('fill','')))
                    if not match or match.group(1) not in patterns:continue
                    pattern = patterns[match.group(1)]
                    clip_id = 'vehicle_crop_'+key+'_'+str(replaced)
                    definitions = ET.SubElement(tree,SVG+'defs')
                    clip = ET.SubElement(definitions,SVG+'clipPath', {'id':clip_id,'clipPathUnits':'userSpaceOnUse'})
                    boundary = copy.deepcopy(child);boundary.attrib.pop('style',None);boundary.attrib.pop('fill',None);boundary.set('fill','#fff');clip.append(boundary)
                    holder = ET.Element(SVG+'g',{'clip-path':'url(#'+clip_id+')'})
                    content = ET.SubElement(holder,SVG+'g',{'transform':pattern.get('patternTransform','matrix(1 0 0 1 0 0)')})
                    for piece in redraw:content.append(copy.deepcopy(piece))
                    index = list(parent).index(child);parent.remove(child);parent.insert(index,holder);replaced += 1
            if not replaced:raise ValueError('redraw did not replace source bitmap '+key)
            for parent in list(tree.iter()):
                for child in list(parent):
                    if child.tag == SVG+'pattern' and child.get('id') in patterns:parent.remove(child)
        # Identity FFDec pattern viewboxes are redundant and unsupported by the
        # strict converter; nonidentity cases are deliberately rejected.
        definitions = ET.SubElement(tree,SVG+'defs')
        for parent in list(tree.iter()):
            for child in list(parent):
                if child.tag != SVG+'pattern':continue
                box = child.get('viewBox')
                if box:
                    actual = list(map(float,box.split()))
                    if actual != [0,0,float(child.get('width')),float(child.get('height'))]:raise ValueError('nonidentity bitmap viewport')
                    child.attrib.pop('viewBox')
                if parent is not definitions:parent.remove(child);definitions.append(child)
        trees[cid] = tree
    trees[91799] = ET.fromstring(read(SOURCE/'redraw/player-wheel-1.svg'))
    trees[91754] = ET.fromstring(read(SOURCE/'redraw/sky-extension.svg'))
    textures, outputs = {}, {}
    for tree in trees.values():
        for element in tree.iter(SVG+'image'):
            href = element.get('href') or element.get(XLINK) or ''
            if not href.lower().startswith(('data:image/png;base64,','data:image/jpeg;base64,')):raise ValueError('external image')
            raw = base64.b64decode(href.split(',',1)[1]);identity = sha(raw)
            with Image.open(io.BytesIO(raw)) as im:
                size = list(im.size);suffix = '.jpg' if im.format == 'JPEG' else '.png'
            name = 'CF6VehicleTexture_'+identity[:20]+suffix
            record = {'name':name,'pixels':size,'sha256':identity,'path':str(SOURCE/'textures'/name)}
            if identity in textures and textures[identity] != record:raise ValueError('texture identity conflict')
            textures[identity] = record;outputs[SOURCE/'textures'/name] = raw
            element.set('href','data:image/'+('jpeg' if suffix == '.jpg' else 'png')+';base64,'+href.split(',',1)[1]);element.attrib.pop(XLINK,None)
    manifest = {'schema':'cf6-vehicle-texture.v1','inputs':inputs,'textures':textures}
    outputs[HERE/'texture-manifest.json'] = encoded(manifest)
    assets = [{'path':r['path'],'name':r['name']} for r in textures.values()]
    recipe = '''// Root-owned CS6 only. Creates one new seed; never replaces an existing document.
(function(){
var target=FLfile.platformPathToURI(%s), assets=%s, doc=null;
function uri(path){return encodeURI(decodeURI(FLfile.platformPathToURI(path)));}
if(FLfile.exists(target))throw new Error("Vehicle texture seed already exists");
try{doc=fl.createDocument();if(!doc)throw new Error("No seed document");
doc.asVersion=2;doc.frameRate=30;doc.width=600;doc.height=350;
for(var i=0;i<assets.length;i++){
 var a=assets[i];doc.importFile(uri(a.path),false);
 if(doc.selection.length!=1)throw new Error("Texture import selection "+a.name);
 var item=doc.selection[0].libraryItem;
 if(item.name!=a.name)throw new Error("Texture library name "+item.name);
 item.compressionType="lossless";item.useImportedJPEGData=false;item.allowSmoothing=true;
 doc.deleteSelection();
}
doc.getTimeline().layers[0].frames[0].actionScript="stop();";
if(!fl.saveDocument(doc,encodeURI(decodeURI(target))))throw new Error("Seed save failed");
fl.trace("CF6_VEHICLE_TEXTURE_SEED_SAVED "+target);
}finally{if(doc)fl.closeDocument(doc,false);}
})();
''' % (json.dumps(str(SEED/'CF6VehicleTextureSeed.xfl')),json.dumps(assets))
    outputs[HERE/'import-textures.jsfl'] = recipe.encode('utf-8')
    return nodes, trees, textures, outputs, inputs


def assemble(nodes, trees, textures, outputs, inputs):
    native = ROOT/'tools/cf6-map-runtime/native-vector'
    sys.path.insert(0,str(native))
    adapter = module('vehicle_native_adapter',native/'build-a08.py')
    api = adapter.generic.api;E,N = api.E,api.N
    converter = adapter.A08Candidate(SOURCE/'redraw/player-body.svg',textures=textures,allow_filters=True)
    dependencies = [Path(__file__),HERE/'extract_source.py',HERE/'prepare_redraw.py',HERE/'redraw-manifest.json',
        native/'build-a01.py',native/'build-a08.py',native/'build-layer.py',native/'procedural_filter.py',
        ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',api.FONT,
        ROOT/'tools/cf6-map-runtime/build.py',ROOT/'tools/cf6-map-runtime/extract-geometry.py',ROOT/'tools/swf-audit/swfscan.py',
        ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/原作参考/crazyflasher6-cn.swf',
        SEED/'DOMDocument.xml',SEED/'texture-seed.xfl',SOURCE/'actions.json']
    for path in dependencies:
        inputs[path.relative_to(ROOT).as_posix()] = sha(path.read_bytes())
    controls = {}
    for action in json.loads((SOURCE/'actions.json').read_text(encoding='utf-8')):
        match = re.fullmatch(r'scripts/DefineSprite_(\d+)(?:_[^/]+)?/frame_(\d+)/DoAction.as',action['originalPath'])
        if not match:continue
        path = HERE/action['capture'];raw = path.read_bytes()
        if sha(raw) != action['sha256']:raise ValueError('source action capture changed')
        inputs[path.relative_to(ROOT).as_posix()] = sha(raw)
        controls[(int(match[1]),int(match[2]))] = raw.decode('utf-8-sig')
    parts = {}
    for cid,tree in trees.items():
        converter.byid = {n.get('id'):n for n in tree.iter() if n.get('id')}
        converter.grads = {n.get('id'):n for n in tree.iter() if api.tag(n) in ('linearGradient','radialGradient')}
        parts[cid] = converter.instance(converter.walk_native(tree),'vehicle-shape-'+str(cid))
    # Give the front R5 wheel its own source symbol; the original has two copies
    # of one bitmap, while the reviewed redraw contains distinct front/rear art.
    nodes = copy.deepcopy(nodes);nodes['91800'] = copy.deepcopy(nodes['1800'])
    for frame in nodes['91800']['frames']:
        for row in frame.values():
            if row['id'] == 1799:row['id'] = 91799
    for frame in nodes['1801']['frames']:
        frame['4']['id'] = 91800
    retained = set()
    def retain(cid):
        if cid in retained or cid in EXCLUDE:return
        node = nodes.get(str(cid))
        if node is None:
            if cid in parts:retained.add(cid);return
            raise ValueError('missing art node '+str(cid))
        if node['code'] in (11,33,37):return
        retained.add(cid)
        for frame in node.get('frames',[]):
            for row in frame.values():retain(row['id'])
    for cid in EXPORTS:retain(cid)
    def placed(row, depth):
        cid = row['id']
        if cid in parts:result = copy.deepcopy(parts[cid])
        else:
            result = E('DOMSymbolInstance',{'libraryItemName':'CF6VehicleSource/'+str(cid),'name':'p'+str(depth)})
        old = result.find(N+'matrix')
        if old is not None:result.remove(old)
        api.matrix(result,row['matrix'])
        mult,add = row.get('colorMult',[256]*4),row.get('colorAdd',[0]*4)
        if mult != [256]*4 or add != [0]*4:
            attrs = {c+'Multiplier':api.base.fmt(mult[i]/256) for i,c in enumerate(('red','green','blue','alpha'))}
            attrs.update({c+'Offset':str(add[i]) for i,c in enumerate(('red','green','blue','alpha'))})
            E('Color',attrs,E('color',parent=result))
        return result
    for cid in sorted(retained):
        node = nodes.get(str(cid),{})
        if 'frames' not in node:continue
        frames = node['frames'];name = 'CF6VehicleSource/'+str(cid)
        symbol = E('DOMSymbolItem',{'name':name,'symbolType':'movie clip'})
        if cid in EXPORTS:symbol.attrib.update(linkageExportForAS='true',linkageExportInFirstFrame='true',linkageIdentifier='CF6Vehicle'+EXPORTS[cid])
        layers = E('layers',parent=E('DOMTimeline',{'name':name},E('timeline',parent=symbol)))
        all_depths = sorted({int(d) for f in frames for d,r in f.items() if r['id'] in retained},reverse=True)
        masks = {}
        for f in frames:
            for d,r in f.items():
                if 'clipDepth' in r:
                    if int(d) in masks and masks[int(d)] != r['clipDepth']:raise ValueError('changing mask span')
                    masks[int(d)] = r['clipDepth']
        order = []
        for depth in all_depths:
            covering = [m for m,end in masks.items() if m<depth<=end]
            if len(covering)>1:raise ValueError('nested source timeline masks need explicit assembly')
            if covering and covering[0] not in order:order.append(covering[0])
            if depth not in order:order.append(depth)
        for depth in order:
            attrs = {'name':'source_depth_'+str(depth)}
            if depth in masks:attrs.update(layerType='mask',locked='true')
            else:
                covering = [m for m,end in masks.items() if m<depth<=end]
                if covering:attrs.update(parentLayerIndex=str(order.index(covering[0])),locked='true')
            target_frames = E('frames',parent=E('DOMLayer',attrs,layers))
            for index,frame in enumerate(frames):
                output = E('DOMFrame',{'index':str(index),'duration':'1','keyMode':'9728'},target_frames)
                elements = E('elements',parent=output);row = frame.get(str(depth))
                if row and row['id'] in retained:elements.append(placed(row,depth))
        commands = E('frames',parent=E('DOMLayer',{'name':'controlled_timeline'},layers))
        for index in range(len(frames)):
            frame = E('DOMFrame',{'index':str(index),'duration':'1','keyMode':'9728'},commands)
            for label,number in node.get('labels',{}).items():
                if number == index+1:frame.set('name',label);frame.set('labelType','name')
            source = controls.get((1800 if cid==91800 else cid,index+1),'')
            next_frame = (index+1)%len(frames)+1
            if re.search(r'(?<![.\w])stop\(\)',source):next_frame=index+1
            jump = re.search(r'(?<![.\w])gotoAnd(?:Play|Stop)\((\d+)\)',source)
            if jump:next_frame=int(jump[1])
            parent_pose = re.search(r'_parent.gotoAndStop\("([^"\n]+)"\)',source)
            pose = json.dumps(parent_pose[1],ensure_ascii=False) if parent_pose else 'undefined'
            # Only newly generated scalar metadata is executable. Source actions
            # are read as data and never copied, evaluated or invoked.
            script = 'stop();__cf6SourceId='+str(cid)+';__cf6Next='+str(next_frame)+';__cf6ParentPose='+pose+';'
            script += '__cf6RemoveParent='+('true' if '_parent.removeMovieClip()' in source else 'false')+';'
            script += '__cf6RemoveSelf='+('true' if re.search(r'^this\.removeMovieClip\(\);$',source,re.M) else 'false')+';'
            E('script',parent=E('Actionscript',parent=frame)).text = script
            E('elements',parent=frame)
        converter.symbols[name] = symbol
    template = ROOT/'flashswf/backgrounds/cf6/CF6_A01_BG'
    for path in [template/'DOMDocument.xml',template/'PublishSettings.xml',template/'CF6_A01_BG.xfl']:
        inputs[path.relative_to(ROOT).as_posix()] = sha(path.read_bytes())
    root = ET.parse(template/'DOMDocument.xml').getroot()
    for child in list(root):
        if api.tag(child) in ('media','symbols','timelines','folders'):root.remove(child)
    root.set('width','600');root.set('height','350');root.set('frameRate','30')
    seed = ET.parse(SEED/'DOMDocument.xml').getroot()
    media = seed.find(N+'media')
    if media is None:raise ValueError('real CS6 texture seed required')
    byname = {r.get('name'):r for r in media}
    if set(byname) != {r['name'] for r in textures.values()}:raise ValueError('seed texture inventory mismatch')
    root.append(copy.deepcopy(media))
    for row in media:
        for prefix,key in [('LIBRARY','href'),('bin','bitmapDataHRef')]:
            path = SEED/prefix/row.get(key);raw = path.read_bytes()
            inputs[path.relative_to(ROOT).as_posix()] = sha(raw);outputs[DEST/prefix/row.get(key)] = raw
    symbols = E('symbols',parent=root)
    # The RSL mount exports an empty anchor and every public vehicle symbol.
    anchor = E('DOMSymbolItem',{'name':'CF6Vehicle','symbolType':'movie clip','linkageExportForAS':'true',
        'linkageExportInFirstFrame':'true','linkageIdentifier':'CF6Vehicle'})
    afr = E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':'anchor'},E('layers',parent=E('DOMTimeline',{'name':'CF6Vehicle'},E('timeline',parent=anchor))))))
    E('elements',parent=afr);E('script',parent=E('Actionscript',parent=afr)).text='stop();'
    converter.symbols['CF6Vehicle']=anchor
    for name,tree in converter.symbols.items():
        outputs[DEST/'LIBRARY'/(name+'.xml')]=xml(tree);E('Include',{'href':name+'.xml','loadImmediate':'false'},symbols)
    timeline=E('DOMTimeline',{'name':'CF6Vehicle'},E('timelines',parent=root))
    frame=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':'stop'},E('layers',parent=timeline))))
    elements=E('elements',parent=frame)
    # CS6 export-only roots can compile unresolved child placeholders. Actual
    # invisible instances force the native dependency graph into this library.
    for index,cid in enumerate(EXPORTS):
        instance=E('DOMSymbolInstance',{'libraryItemName':'CF6VehicleSource/'+str(cid),
            'name':'nativeProbe'+str(cid),'symbolType':'movie clip'},elements)
        E('Matrix',{'tx':str(30+index*20),'ty':'100'},E('matrix',parent=instance))
        E('Color',{'alphaMultiplier':'0'},E('color',parent=instance))
    E('script',parent=E('Actionscript',parent=frame)).text='stop();'
    outputs[DEST/'DOMDocument.xml']=xml(root)
    outputs[DEST/'CF6Vehicle.xfl']=(template/'CF6_A01_BG.xfl').read_bytes()
    profile=ET.parse(template/'PublishSettings.xml')
    profile.find('.//PublishFormatProperties/flashFileName').text='CF6Vehicle.swf'
    outputs[DEST/'PublishSettings.xml']=xml(profile.getroot())
    # Fixed sky is a separate root-stage layer. The empty world background is
    # intentional: all moving roadway is the service-owned original 1791 clip.
    for name,size,sky in [('CF6_A07_BG',[1150,450],False),('CF6_A07_sky',[800,253],True)]:
        target=ROOT/'flashswf/backgrounds/cf6'/name
        doc=copy.deepcopy(root);doc.set('width',str(size[0]));doc.set('height',str(size[1]))
        existing=doc.find(N+'timelines');doc.remove(existing)
        t=E('DOMTimeline',{'name':name},E('timelines',parent=doc))
        f=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':'sky' if sky else 'world_placeholder'},E('layers',parent=t))))
        elements=E('elements',parent=f)
        if sky:
            elements.append(placed({'id':91754,'matrix':[1,0,0,1,0,186.5]},0))
            elements.append(placed({'id':1754,'matrix':[1,0,0,1,400,93.5]},1))
        E('script',parent=E('Actionscript',parent=f)).text='stop();'
        used_symbols,used_images=set(),set()
        def dependencies_of(tree):
            for item in tree.iter():
                if api.tag(item)=='DOMSymbolInstance':
                    item_name=item.get('libraryItemName')
                    if item_name not in used_symbols:
                        used_symbols.add(item_name);dependencies_of(converter.symbols[item_name])
                elif api.tag(item)=='DOMBitmapInstance':used_images.add(item.get('libraryItemName'))
                elif api.tag(item)=='BitmapFill':used_images.add(item.get('bitmapPath'))
        dependencies_of(elements)
        old=doc.find(N+'symbols');doc.remove(old);incl=E('symbols',parent=doc)
        for item_name in sorted(used_symbols):
            E('Include',{'href':item_name+'.xml','loadImmediate':'false'},incl)
            outputs[target/'LIBRARY'/(item_name+'.xml')]=outputs[DEST/'LIBRARY'/(item_name+'.xml')]
        old=doc.find(N+'media');doc.remove(old);asset_media=E('media',parent=doc)
        for item_name in sorted(used_images):
            item=byname[item_name];asset_media.append(copy.deepcopy(item))
            for prefix,key in [('LIBRARY','href'),('bin','bitmapDataHRef')]:
                outputs[target/prefix/item.get(key)]=outputs[DEST/prefix/item.get(key)]
        outputs[target/'DOMDocument.xml']=xml(doc)
        outputs[target/(name+'.xfl')]=outputs[DEST/'CF6Vehicle.xfl']
        settings=copy.deepcopy(profile.getroot());settings.find('.//PublishFormatProperties/flashFileName').text=name+'.swf'
        outputs[target/'PublishSettings.xml']=xml(settings)
    outputs[HERE/'source/art-timelines.json']=encoded({str(cid):nodes[str(cid)] for cid in sorted(retained) if str(cid) in nodes and 'frames' in nodes[str(cid)]})
    return {'schema':'cf6-vehicle-art.v1','state':'source_assembled; requires fresh CS6 compilation',
        'inputs':inputs,'exports':{str(cid):'CF6Vehicle'+name for cid,name in EXPORTS.items()},
        'nativeSymbols':len(converter.symbols),'sourceNodes':len(retained),'textures':len(textures),
        'outputs':{p.relative_to(ROOT).as_posix():{'sha256':sha(raw),'bytes':len(raw)} for p,raw in outputs.items()}}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--assemble',action='store_true');parser.add_argument('--check',action='store_true');args=parser.parse_args()
    nodes,trees,textures,outputs,inputs=prepare()
    if args.assemble:
        manifest=assemble(nodes,trees,textures,outputs,inputs)
        projects=[DEST,ROOT/'flashswf/backgrounds/cf6/CF6_A07_BG',ROOT/'flashswf/backgrounds/cf6/CF6_A07_sky']
        expected={p for p in outputs if any(p.is_relative_to(project) for project in projects)}
        actual={p for project in projects if project.exists() for p in project.rglob('*') if p.is_file()}
        extra=actual-expected
        if extra:raise ValueError('unreferenced native files require identity-verified retirement: '+str(sorted(extra)[0]))
        previous_path=HERE/'art-manifest.json'
        if not args.check and previous_path.exists():
            previous=json.loads(previous_path.read_text(encoding='utf-8'))['outputs']
            for path in actual:
                old=previous.get(path.relative_to(ROOT).as_posix())
                if old is None or sha(path.read_bytes())!=old['sha256']:
                    raise ValueError('preserve independently edited or unowned native file: '+str(path))
        outputs[HERE/'art-manifest.json']=encoded(manifest)
    for path,raw in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes()!=raw:raise ValueError('stale vehicle art source '+str(path))
        elif not path.is_file() or path.read_bytes()!=raw:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
    print(json.dumps({'state':'checked' if args.check else 'prepared','textures':len(textures),'files':len(outputs)}))


if __name__=='__main__':main()
