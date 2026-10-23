"""Full new-drawn transport1868 native vectors with the original 29-frame timeline.
No inherited gameplay scripts, no PNG stand-ins, no SWF writing or Flash control.
"""
from pathlib import Path
import argparse,base64,copy,hashlib,importlib.util,io,json,sys,xml.etree.ElementTree as ET
from PIL import Image
from pod_scale import calibrate_frames
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
DEST=ROOT/'flashswf/backgrounds/cf6/preparation'
SOURCE=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'
PROFILES={1868:('CF6_Transport1868','transport',29,'A09-R2/cf6-stage9-redraw-r2','environment-original-nodes.json')}
EXCLUDED={277,1433}


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
              template/'DOMDocument.xml',template/'PublishSettings.xml',template/'CF6_A01_BG.xfl']:
        remember(p)
    packages={}; node_sets={}; shape_trees={}; textures={};texture_rows=[]
    for sprite,(_,_,_,package,reference) in PROFILES.items():
        package=SOURCE/package;packages[sprite]=package
        source=package/'reference'/reference;remember(source)
        data=json.loads(source.read_text(encoding='utf-8'));node_sets[sprite]=data.get('nodes',data)
    def leaves(nodes,cid):
        if cid in EXCLUDED:return set()
        node=nodes[str(cid)]
        if 'frames' not in node:return {cid}
        return set().union(*(leaves(nodes,row['id']) for frame in node['frames'] for row in frame.values()))
    for sprite in PROFILES:
      for cid in sorted(leaves(node_sets[sprite],sprite)):
        path=packages[sprite]/'parts'/('shape-'+str(cid)+'.svg')
        assert path.is_file(),'new-drawn source required: '+str(path)
        remember(path);tree=ET.parse(path).getroot();shape_trees[(sprite,cid)]=tree
        for image in tree.iter():
            if api.tag(image)!='image':continue
            href=image.get('href') or image.get('{http://www.w3.org/1999/xlink}href')
            assert href.startswith(('data:image/png;base64,','data:image/jpeg;base64,'))
            raw=base64.b64decode(href.split(',',1)[1]);key=sha(raw)
            if key in textures:continue
            with Image.open(io.BytesIO(raw)) as picture:pixels=list(picture.size)
            assert key=='bd390a38e397a6693d65a0327552bc4e6692ed305bc6d612ac8c6856dcf20342' and pixels==[1113,708] and [float(image.get('width')),float(image.get('height'))]==[371,236],'only the audited original fine-grain texture is allowed; no whole-frame substitute'
            filename='intrinsic-'+key[:24]+('.jpg' if href.startswith('data:image/jpeg') else '.png')
            target=HERE/'transport-art/textures'/filename;outputs[target]=raw
            textures[key]={'name':filename,'pixels':pixels}
            texture_rows.append({'path':target.relative_to(ROOT).as_posix(),'sha256':key,'bytes':len(raw),'pixels':pixels})
    seed=DEST/'CF6_TransportTextureSeed'
    builder_path=ROOT/'tools/cf6-map-runtime/build.py';remember(builder_path)
    bs=importlib.util.spec_from_file_location('cf6_aux_import',builder_path);builder=importlib.util.module_from_spec(bs);bs.loader.exec_module(builder)
    recipe_layers=[{'id':'texture-'+str(i),'png':r['path'],'x':0,'y':0,'width':r['pixels'][0],'height':r['pixels'][1],'depth':i} for i,r in enumerate(texture_rows)]
    outputs[HERE/'transport-art/import-textures.jsfl']=builder.jsfl({'id':'transport-seed','nativeBounds':[0,0,600,500],'worldScale':1},recipe_layers,'CF6_TransportTextureSeed',seed/'CF6_TransportTextureSeed.xfl').encode('utf-8')
    seed_media=None
    if assemble:
        sys.path.insert(0,str(ROOT/'tools/cf6-map-runtime'));from native_xfl import audit
        audit(seed/'CF6_TransportTextureSeed.xfl',texture_rows)
        seed_media=ET.parse(seed/'DOMDocument.xml').getroot().find(N+'media')
        assert seed_media is not None,'real CS6 seed has no imported media'
        remember(seed/'DOMDocument.xml')
    scale_policy_path=ROOT/'tools/cf6-prop-layout/scale-policy.json'
    remember(scale_policy_path);remember(HERE/'pod_scale.py')
    scale_policy=json.loads(scale_policy_path.read_text(encoding='utf8'))
    if scale_policy['schema']!='cf6-local-scale-policy.v1':raise ValueError('unexpected scale policy')
    for sprite,(name,behavior,count,_,_) in PROFILES.items():
        nodes=node_sets[sprite];source=nodes[str(sprite)]['frames'];assert len(source)==count
        scale_audit=None
        if sprite==1939:source,scale_audit=calibrate_frames(nodes,scale_policy['pod'])
        ids=sorted(leaves(nodes,sprite))
        converter=api.Candidate(packages[sprite]/'parts'/('shape-'+str(ids[0])+'.svg'),textures=textures,allow_filters=True)
        parts={}
        for cid in ids:
            tree=shape_trees[(sprite,cid)]
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
        # Nested 1906 is the original one-frame clone decoration, fully new drawn.
        # No original actions, attachMovie, gameplay controllers or hidden hit markers survive.
        nested=sorted({r['id'] for f in source for r in f.values()}-EXCLUDED-set(parts))
        for cid in nested:
            nested_frames=nodes[str(cid)]['frames'];assert len(nested_frames)==1
            symbol='CF6InteractiveNested/'+str(cid)
            root=E('DOMSymbolItem',{'name':symbol,'symbolType':'graphic'})
            nested_tl=E('DOMTimeline',{'name':str(cid)},E('timeline',parent=root))
            frame=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':'New-drawn source parts'},E('layers',parent=nested_tl))))
            elements=E('elements',parent=frame)
            for depth,row in sorted(nested_frames[0].items(),key=lambda item:int(item[0])):
                assert 'clipDepth' not in row
                if row['id'] not in EXCLUDED:elements.append(placed(row))
            converter.symbols[symbol]=root
            node=E('DOMSymbolInstance',{'libraryItemName':symbol,'symbolType':'graphic','loop':'single frame','firstFrame':'0'});api.matrix(node,[1,0,0,1,0,0]);parts[cid]=node
        timeline=E('DOMTimeline',{'name':name});frames=E('frames',parent=E('DOMLayer',{'name':'Original source depths'},E('layers',parent=timeline)))
        masked=0
        for index,source_frame in enumerate(source):
            f=E('DOMFrame',{'index':str(index),'duration':'1','keyMode':'9728'},frames)
            E('script',parent=E('Actionscript',parent=f)).text='stop();'
            elements=E('elements',parent=f);masks=[(int(d),r) for d,r in source_frame.items() if 'clipDepth' in r]
            for depth,row in sorted(source_frame.items(),key=lambda item:int(item[0])):
                assert not masks,'unreviewed source clip mask'
                if row['id'] in EXCLUDED:continue
                instance=placed(row)
                elements.append(instance)
        target=HERE/'transport-art'/name;doc=ET.parse(template/'DOMDocument.xml').getroot();doc.set('width','600');doc.set('height','500');doc.set('frameRate','30')
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
        def compose(outer,inner):
            a,b,c,d,x,y=outer;e,f,g,h,u,v=inner
            return [a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y]
        def visual_points(cid,matrix):
            if cid in EXCLUDED:return []
            node=nodes[str(cid)]
            if 'frames' in node:
                return [point for row in (source[0] if cid==sprite else node['frames'][0]).values() for point in visual_points(row['id'],compose(matrix,row['matrix']))]
            # SVG viewBox is a conservative source geometry rectangle, not an opaque-pixel claim.
            box=list(map(float,shape_trees[(sprite,cid)].get('viewBox').replace(',',' ').split()))
            a,b,c,d,tx,ty=matrix
            return [(a*x+c*y+tx,b*x+d*y+ty) for x in (box[0],box[0]+box[2]) for y in (box[1],box[1]+box[3])]
        points=visual_points(sprite,[1,0,0,1,0,0])
        visual_bounds=[min(x for x,y in points),min(y for x,y in points),max(x for x,y in points),max(y for x,y in points)]
        assets.append({'name':name,'sourceSprite':sprite,'frames':count,'behavior':behavior,'xfl':(DEST/name/(name+'.xfl')).relative_to(ROOT).as_posix(),
            'swf':(DEST/(name+'.swf')).relative_to(ROOT).as_posix(),'frame1VisualBounds':visual_bounds,'frame1VisualBoundsBasis':'conservative union of new SVG viewBox rectangles through complete original frame-1 local matrices, excluding logic markers; not rendered opaque pixels','excludedLogicSprites':sorted(EXCLUDED),'allFramesNonEmpty':all(any(r['id'] not in EXCLUDED for r in f.values()) for f in source),'dispatchFrame':29,'filterConversions':converter.filter_reports,
            'sourceActionExcluded':'all legacy transitions, kills, saves and controls; only generated stop/native shape filters remain',
            'registration':'original symbol origin (0,0); no normalization or viewport scale; frame29 assigns the generator this._x/this._y, with current free-foot spawn adjustment recorded separately', 'localOrigin':[0,0], 'localCompensation':[0,0], 'visualScale':1})
        if scale_audit is not None:assets[-1]['scaleCalibration']={'schema':'cf6-pod-shape-scale.v1','policy':scale_policy['pod'],'frames':scale_audit,'externalRegistrationUnchanged':True,'scope':'body growth normalization and separate container/debris matrices; no gameplay or timeline changes'}
    geom_path=ROOT/'tools/cf6-map-runtime/extract-geometry.py';remember(geom_path)
    gs=importlib.util.spec_from_file_location('cf6_interactive_geometry',geom_path);geom=importlib.util.module_from_spec(gs);gs.loader.exec_module(geom)
    original=SOURCE/'原作参考/crazyflasher6-cn.swf';remember(original)
    original_sha,main_frames,sprites,shapes=geom.parse(original)
    placements=[]
    for map_id,frame_number in geom.FRAMES.items():
      for world in main_frames[frame_number-1]:
       for row in sprites.get(world['id'],[[]])[0]:
        if row['id'] in PROFILES:
         placements.append({'mapId':map_id,'mainFrame':frame_number,'worldSprite':world['id'],'worldDepth':world['depth'],'sourceSprite':row['id'],'sourceDepth':row['depth'],'nativeMatrix':row['matrix'],'coordinateSpace':'original gameworld; transform once in scene assembly'})
    assert len(placements)==3 and {p['mapId'] for p in placements}=={'A09','A14','A18'}
    def trigger(sprite,marker):
        parent=next(r for r in sprites[sprite][0] if r['id']==marker)
        leaf=next(r for r in sprites[marker][0] if r['id']==277)
        box=shapes[277]['bounds'];combined=geom.compose(parent['matrix'],leaf['matrix'])
        a,b,c,d,tx,ty=combined
        points=[(a*x+c*y+tx,b*x+d*y+ty) for x in (box[0],box[2]) for y in (box[1],box[3])]
        return {'markerSprite':marker,'sourceDepth':parent['depth'],'markerMatrix':parent['matrix'],'leafShape':277,'leafBounds':box,'leafMatrix':leaf['matrix'],'localAabb':[min(x for x,y in points),min(y for x,y in points),max(x for x,y in points),max(y for x,y in points)],'basis':'original nested marker shape bounds transformed into asset local space; original uses bounding-box hitTest, not shapeFlag'}
    triggers={str(sprite):trigger(sprite,1433) for sprite in PROFILES}
    manifest={'schema':'cf6-transport-native-source.v1','state':'native-source-assembled; CS6 compile pending' if assemble else 'native-fragments-prepared; CS6 texture import required','textureSeed':(seed/'CF6_TransportTextureSeed.xfl').relative_to(ROOT).as_posix(),'textures':texture_rows,
        'inputs':inputs,'originalSha256':original_sha,'assets':assets,'placements':placements,'triggers':triggers,
        'authority':'Art only. Proximity starts the native 29-frame performance; frame29 queues one event for the existing declared SubWave budget after its subscription is ready. No original spawn actions or new enemy quantities.',
        'outputs':{p.relative_to(ROOT).as_posix():{'sha256':sha(data),'bytes':len(data)} for p,data in outputs.items()}}
    return outputs,manifest
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');ap.add_argument('--assemble',action='store_true');args=ap.parse_args();outputs,manifest=build(args.assemble);mp=HERE/'transport-art-manifest.json'
    if not args.check:
        (DEST/'CF6_TransportTextureSeed').mkdir(parents=True,exist_ok=True)
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
