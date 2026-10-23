"""Full native-vector 1430/1862 doors and 1832 camera, with original local timelines.
No inherited gameplay scripts, no PNG stand-ins, no SWF writing or Flash control.
"""
from pathlib import Path
import argparse,base64,copy,hashlib,importlib.util,io,json,sys,xml.etree.ElementTree as ET
from PIL import Image
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
DEST=ROOT/'flashswf/backgrounds/cf6/preparation'
PACKAGE=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/A09-R2/cf6-stage9-redraw-r2'
PROFILES={1430:('CF6_AuxDoor1430','clear-and-gate',59),1862:('CF6_AuxDoor1862','actual-unit-spawn',18),1832:('CF6_AuxCamera1832','ambient-loop',147)}
def sha(raw):return hashlib.sha256(raw).hexdigest()
def encoded(value):return (json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
def xml(node):return ET.tostring(node,encoding='utf-8',xml_declaration=True)
def build(assemble=False):
    path=ROOT/'tools/cf6-map-runtime/native-vector/build-a01.py'
    ms=importlib.util.spec_from_file_location('cf6_aux_native',path);api=importlib.util.module_from_spec(ms);ms.loader.exec_module(api)
    E,N=api.E,api.N
    template=ROOT/'flashswf/backgrounds/cf6/CF6_A01_BG'
    outputs={};inputs={};assets=[]
    def remember(p):inputs[p.relative_to(ROOT).as_posix()]=sha(p.read_bytes())
    for p in [Path(__file__),path,ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',api.FONT,
              template/'DOMDocument.xml',template/'PublishSettings.xml',template/'CF6_A01_BG.xfl',PACKAGE/'reference/environment-original-nodes.json']:
        remember(p)
    nodes=json.loads((PACKAGE/'reference/environment-original-nodes.json').read_text(encoding='utf-8'))['nodes']
    textures={};texture_rows=[];shape_trees={}
    all_ids=sorted({r['id'] for sprite in PROFILES for f in nodes[str(sprite)]['frames'] for r in f.values()}-{360,1426})
    for cid in all_ids:
        original=nodes[str(cid)];assert 'frames' not in original,'unreviewed nested timeline'
        path=PACKAGE/'parts'/('shape-'+str(cid)+'.svg')
        if path.is_file():remember(path);tree=ET.parse(path).getroot()
        else:
            assert not original['bitmapDependencies'],'unregistered original texture'
            tree=ET.fromstring('<svg xmlns="http://www.w3.org/2000/svg" viewBox="'+' '.join(map(str,original['viewBox']))+'">'+original['svgInner']+'</svg>')
        shape_trees[cid]=tree
        for image in tree.iter():
            if api.tag(image)!='image':continue
            href=image.get('href') or image.get('{http://www.w3.org/1999/xlink}href')
            assert href.startswith(('data:image/png;base64,','data:image/jpeg;base64,'))
            raw=base64.b64decode(href.split(',',1)[1]);key=sha(raw)
            if key in textures:continue
            with Image.open(io.BytesIO(raw)) as picture:pixels=list(picture.size)
            assert max(pixels)<1024 and max(float(image.get('width')),float(image.get('height')))<256,'unexpected large raster: no whole-frame substitutes'
            filename='intrinsic-'+key[:24]+('.jpg' if href.startswith('data:image/jpeg') else '.png')
            target=HERE/'auxiliary-art/textures'/filename;outputs[target]=raw
            textures[key]={'name':filename,'pixels':pixels}
            texture_rows.append({'path':target.relative_to(ROOT).as_posix(),'sha256':key,'bytes':len(raw),'pixels':pixels})
    seed=DEST/'CF6_AuxiliaryTextureSeed'
    builder_path=ROOT/'tools/cf6-map-runtime/build.py';remember(builder_path)
    bs=importlib.util.spec_from_file_location('cf6_aux_import',builder_path);builder=importlib.util.module_from_spec(bs);bs.loader.exec_module(builder)
    recipe_layers=[{'id':'texture-'+str(i),'png':r['path'],'x':0,'y':0,'width':r['pixels'][0],'height':r['pixels'][1],'depth':i} for i,r in enumerate(texture_rows)]
    outputs[HERE/'auxiliary-art/import-textures.jsfl']=builder.jsfl({'id':'auxiliary-seed','nativeBounds':[0,0,600,500],'worldScale':1},recipe_layers,'CF6_AuxiliaryTextureSeed',seed/'CF6_AuxiliaryTextureSeed.xfl').encode('utf-8')
    seed_media=None
    if assemble:
        sys.path.insert(0,str(ROOT/'tools/cf6-map-runtime'));from native_xfl import audit
        audit(seed/'CF6_AuxiliaryTextureSeed.xfl',texture_rows)
        seed_media=ET.parse(seed/'DOMDocument.xml').getroot().find(N+'media')
        assert seed_media is not None,'real CS6 seed has no imported media'
        remember(seed/'DOMDocument.xml')
    for sprite,(name,behavior,count) in PROFILES.items():
        source=nodes[str(sprite)]['frames'];assert len(source)==count
        converter=api.Candidate(PACKAGE/'parts/shape-1421.svg',textures=textures,allow_filters=True)
        ids=sorted({r['id'] for frame in source for r in frame.values()}-{360,1426})
        parts={}
        for cid in ids:
            tree=shape_trees[cid]
            converter.byid={n.get('id'):n for n in tree.iter() if n.get('id')}
            converter.grads={n.get('id'):n for n in tree.iter() if api.tag(n) in ('linearGradient','radialGradient')}
            parts[cid]=converter.instance(converter.walk_native(tree),'part-'+str(cid))
        def placed(row):
            node=copy.deepcopy(parts[row['id']]);node.remove(node.find(N+'matrix'));api.matrix(node,row['matrix'])
            mult,add=row.get('colorMult',[256]*4),row.get('colorAdd',[0]*4)
            if mult!=[256]*4 or add!=[0]*4:
                attrs={c+'Multiplier':api.base.fmt(mult[i]/256) for i,c in enumerate(('red','green','blue','alpha'))}
                attrs.update({c+'Offset':str(add[i]) for i,c in enumerate(('red','green','blue','alpha'))});E('Color',attrs,E('color',parent=node))
            return node
        def clipped(instance,mask):
            root=E('DOMSymbolItem',{'name':'pending','symbolType':'graphic'})
            layers=E('layers',parent=E('DOMTimeline',{'name':'SourceClip'},E('timeline',parent=root)))
            for attrs,element in [({'name':'Boundary','layerType':'mask','locked':'true'},placed(mask)),({'name':'Source','parentLayerIndex':'0','locked':'true'},instance)]:
                frame=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},E('frames',parent=E('DOMLayer',attrs,layers)))
                E('elements',parent=frame).append(element)
            name='CF6AuxClip/'+sha(xml(root));root.set('name',name);converter.symbols[name]=root
            instance=E('DOMSymbolInstance',{'libraryItemName':name,'symbolType':'graphic','loop':'single frame','firstFrame':'0'});api.matrix(instance,[1,0,0,1,0,0]);return instance
        timeline=E('DOMTimeline',{'name':name});frames=E('frames',parent=E('DOMLayer',{'name':'Original source depths'},E('layers',parent=timeline)))
        masked=0
        for index,source_frame in enumerate(source):
            f=E('DOMFrame',{'index':str(index),'duration':'1','keyMode':'9728'},frames)
            E('script',parent=E('Actionscript',parent=f)).text='stop();'
            elements=E('elements',parent=f);masks=[(int(d),r) for d,r in source_frame.items() if 'clipDepth' in r]
            for depth,row in sorted(source_frame.items(),key=lambda item:int(item[0])):
                if row['id'] in (360,1426) or 'clipDepth' in row:continue
                instance=placed(row)
                for md,mr in sorted([(d,r) for d,r in masks if d<int(depth)<=r['clipDepth']],reverse=True):
                    instance=clipped(instance,mr);masked+=1
                elements.append(instance)
        target=HERE/'auxiliary-art'/name;doc=ET.parse(template/'DOMDocument.xml').getroot();doc.set('width','600');doc.set('height','500');doc.set('frameRate','30')
        for child in list(doc):
            if api.tag(child) in ('media','symbols','timelines','folders'):doc.remove(child)
        if seed_media is not None:doc.append(copy.deepcopy(seed_media))
        includes=E('symbols',parent=doc)
        for symbol,tree in converter.symbols.items():
            outputs[target/'LIBRARY'/(symbol+'.xml')]=xml(tree);E('Include',{'href':symbol+'.xml','loadImmediate':'false'},includes)
        E('timelines',parent=doc).append(timeline)
        outputs[target/'DOMDocument.xml']=xml(doc);outputs[target/(name+'.xfl')]=(template/'CF6_A01_BG.xfl').read_bytes()
        profile=ET.parse(template/'PublishSettings.xml');profile.find('.//PublishFormatProperties/flashFileName').text=name+'.swf';outputs[target/'PublishSettings.xml']=xml(profile.getroot())
        if (template/'mimetype').is_file():outputs[target/'mimetype']=(template/'mimetype').read_bytes()
        # Native DOMBitmapItem href remains a source asset reference even with a valid bin cache.
        for texture in texture_rows:
            source_texture=ROOT/texture['path']
            outputs[target/'LIBRARY'/source_texture.name]=outputs[source_texture]
        if assemble:
            final=DEST/name
            for source_path,data in list(outputs.items()):
                if source_path.is_relative_to(target):outputs[final/source_path.relative_to(target)]=data
            for cache in (seed/'bin').glob('*'):
                if cache.is_file():remember(cache);outputs[final/'bin'/cache.name]=cache.read_bytes()
        assets.append({'name':name,'sourceSprite':sprite,'frames':count,'behavior':behavior,'xfl':(DEST/name/(name+'.xfl')).relative_to(ROOT).as_posix(),
            'swf':(DEST/(name+'.swf')).relative_to(ROOT).as_posix(),'nativeClippedPlacements':masked,'allFramesNonEmpty':True,'filterConversions':converter.filter_reports,
            'sourceActionExcluded':'all legacy transitions, kills, saves and controls; only generated stop/native shape filters remain',
            'registration':'original symbol origin; no viewport scale; placement belongs to scene assembler'})
    placements=[]
    source_map=ROOT/'tools/cf6-map-source/generated/map-input.json';remember(source_map)
    maps=json.loads(source_map.read_text(encoding='utf-8'))['maps']
    for mid in maps:
        geometry=ROOT/'tools/cf6-map-runtime/generated'/(mid+'-original-geometry.json')
        if not geometry.exists():continue
        remember(geometry);display=json.loads(geometry.read_text(encoding='utf-8'))['geometry']['display']
        for row in display:
            if row.get('id') in PROFILES:
                placements.append({'mapId':mid,'sourceSprite':row['id'],'sourceDepth':row['depth'],'sourceName':row.get('name'),
                    'nativeMatrix':row['matrix'],'coordinateSpace':'original gameworld; transform once in scene-assembly',
                    'gateLocal':[-12.55,98.5] if row['id']==1430 else None,
                    'gateBasis':'original1430 depth7 area registration; not a recovered actor foot trajectory' if row['id']==1430 else None})
    manifest={'schema':'cf6-auxiliary-native-source.v1','state':'native-source-assembled; CS6 compile pending' if assemble else 'native-fragments-prepared; CS6 texture import required','textureSeed':(seed/'CF6_AuxiliaryTextureSeed.xfl').relative_to(ROOT).as_posix(),'textures':texture_rows,
        'inputs':inputs,'assets':assets,'placements':placements,'clearDoor':{'sourceSprite':1430,'cutFrame':58,'fullFrames':59,'actorPolicy':'CF7 stand at gate; no original actor samples exist'},
        'outputs':{p.relative_to(ROOT).as_posix():{'sha256':sha(data),'bytes':len(data)} for p,data in outputs.items()}}
    return outputs,manifest
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');ap.add_argument('--assemble',action='store_true');args=ap.parse_args();outputs,manifest=build(args.assemble);mp=HERE/'auxiliary-art-manifest.json'
    if not args.check:
        (DEST/'CF6_AuxiliaryTextureSeed').mkdir(parents=True,exist_ok=True)
        (ROOT/'tmp/cf6-map-runtime/native-import').mkdir(parents=True,exist_ok=True)
        if mp.exists():
            previous=json.loads(mp.read_text(encoding='utf-8'))['outputs']
            for path,identity in previous.items():
                p=ROOT/path
                if not p.exists() or sha(p.read_bytes())!=identity['sha256']:raise ValueError('preserve edited owned source: '+path)
        else:
            for p in outputs:
                if p.exists():raise ValueError('unowned target exists: '+str(p))
    outputs[mp]=encoded(manifest)
    for p,raw in outputs.items():
        if args.check:
            if not p.exists() or p.read_bytes()!=raw:raise ValueError('stale output '+str(p))
        else:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
    print(json.dumps({'state':'checked' if args.check else 'prepared','assets':len(manifest['assets']),'placements':len(manifest['placements']),'files':len(outputs),'bytes':sum(map(len,outputs.values()))}))
