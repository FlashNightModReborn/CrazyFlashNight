"""Native vector layer candidates with pinned, unchanged intrinsic textures only."""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import io
import json
import sys
import xml.etree.ElementTree as ET
from PIL import Image

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
api=load_module('cf6_native_vector',HERE/'build-a01.py')
builder=load_module('cf6_map_builder',HERE.parent/'build.py')
E=api.E;N=api.N


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--map',required=True);parser.add_argument('--layer',default='background')
    parser.add_argument('--assemble',action='store_true');args=parser.parse_args()
    inputs=ROOT/'tools/cf6-map-source/generated/map-input.json'
    source_map=json.loads(inputs.read_text(encoding='utf-8'))['maps'][args.map]
    matches=[x for x in source_map['layers'] if x['id']==args.layer]
    if len(matches)!=1:raise ValueError('one explicit source layer required')
    layer=matches[0];source=(ROOT/layer['source']['svg']).resolve()
    if not source.is_relative_to(ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'):raise ValueError('source outside CF6 archive')
    name='CF6_'+args.map+'_'+('BG' if args.layer=='background' else args.layer)+'_VectorCandidate01'
    target=ROOT/'flashswf/backgrounds/cf6'/name;out=HERE/'layers'/name;out.mkdir(parents=True,exist_ok=True)
    root_svg=ET.parse(source).getroot();textures={};png_inputs=[]
    for image in root_svg.iter():
        if api.tag(image)!='image':continue
        href=image.get('href') or image.get('{http://www.w3.org/1999/xlink}href') or ''
        if not href.startswith(('data:image/png;base64,','data:image/jpeg;base64,')):raise ValueError('non-PNG/JPEG or nonlocal image requires explicit support')
        raw=base64.b64decode(href.split(',',1)[1]);key=hashlib.sha256(raw).hexdigest()
        if key in textures:continue
        filename='intrinsic-'+key[:24]+('.jpg' if href.startswith('data:image/jpeg;') else '.png');path=HERE/'assets'/filename
        if path.exists() and path.read_bytes()!=raw:raise ValueError('intrinsic texture hash collision')
        if not path.exists():path.write_bytes(raw)
        with Image.open(io.BytesIO(raw)) as picture:
            if picture.format not in ('PNG','JPEG'):raise ValueError('invalid raster data URI')
            pixels=list(picture.size)
        textures[key]={'name':filename,'pixels':pixels}
        png_inputs.append({'path':path.relative_to(ROOT).as_posix(),'sha256':key,'bytes':len(raw),'pixels':pixels})
    manifest={'schema':'cf6-native-layer-input.v1','map':args.map,'layer':args.layer,'name':name,
              'source':source.relative_to(ROOT).as_posix(),'sourceSha256':hashlib.sha256(source.read_bytes()).hexdigest(),
              'inputIndex':inputs.relative_to(ROOT).as_posix(),'inputIndexSha256':hashlib.sha256(inputs.read_bytes()).hexdigest(),
              'extraction':'decode existing PNG/JPEG data URI bytes only; no image rasterization or modification',
              'inputs':png_inputs,'textures':textures,'xfl':(target/(name+'.xfl')).relative_to(ROOT).as_posix(),'swf':name+'.swf'}
    (out/'texture-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if args.layer=='background':width,height=source_map['nativeBounds'][2:];origin=source_map['nativeBounds'][:2];x=layer['x']-origin[0];y=layer['y']-origin[1]
    else:width,height=layer['width'],layer['height'];x=y=0
    if png_inputs:
        recipe_layers=[{'id':'texture-'+str(i),'png':p['path'],'x':0,'y':0,'width':p['pixels'][0],'height':p['pixels'][1],'depth':i} for i,p in enumerate(png_inputs)]
        recipe=builder.jsfl({'id':'native-'+name,'nativeBounds':[0,0,width,height],'worldScale':1},recipe_layers,name,target/(name+'.xfl'))
        (out/'import-textures.jsfl').write_text(recipe,encoding='utf-8')
        target.mkdir(exist_ok=True)
    converter=api.Candidate(source,textures=textures,allow_filters=True)
    elements=converter.walk_native(root_svg);view=api.base.nums(root_svg.get('viewBox'))
    sx=layer['width']/view[2];sy=layer['height']/view[3]
    placed=converter.instance(elements,'registered-native-layer',(sx,0,0,sy,x-view[0]*sx,y-view[1]*sy))
    timeline=E('DOMTimeline',{'name':name});layers=E('layers',parent=timeline)
    actions=E('frames',parent=E('DOMLayer',{'name':'initialize-then-bake' if args.layer=='background' else 'stop'},layers))
    fr=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},actions);E('elements',parent=fr)
    if args.layer=='background':
        fr=E('DOMFrame',{'index':'1','duration':'1','keyMode':'9728'},actions);E('elements',parent=fr)
        script=api.background_script()
    else:script='stop();'
    E('script',parent=E('Actionscript',parent=fr)).text=script
    fr=E('DOMFrame',{'index':'0','duration':'2' if args.layer=='background' else '1','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':args.layer},layers)))
    E('elements',parent=fr).append(placed)
    names=[]
    for symbol,tree in converter.symbols.items():
        path=out/'LIBRARY'/(symbol+'.xml');path.parent.mkdir(parents=True,exist_ok=True);ET.ElementTree(tree).write(path,encoding='utf-8',xml_declaration=True);names.append(symbol)
    ET.ElementTree(timeline).write(out/'timeline.xml',encoding='utf-8',xml_declaration=True)
    report={'schema':'cf6-native-layer-candidate.v1','name':name,'source':manifest['source'],'sourceSha256':manifest['sourceSha256'],
            'nativeShapes':sum(1 for tree in converter.symbols.values() for node in tree.iter() if node.tag==N+'DOMShape'),
            'nativeSymbols':len(names),'intrinsicTextures':len(textures),'masks':converter.masks,'filters':converter.filter_reports,'patterns':converter.pattern_reports,'gradientFallbacks':converter.gradient_fallbacks,
            'sourceViewport':view,'registrationMatrix':[sx,0,0,sy,x-view[0]*sx,y-view[1]*sy],
            'state':'source generated; intrinsic native import/assembly and actual Flash rendering still required',
            'limits':['SVG filter-region clipping is reported per filter and not yet reproduced.','Native Gaussian blur is a three-pass approximation.','Root SVG viewport crop must be compared at the original edge.']}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (out/'converter.source.py').write_bytes((HERE/'build-a01.py').read_bytes());(out/'builder.source.py').write_bytes(Path(__file__).read_bytes())
    if args.assemble:
        sys.path.insert(0,str(HERE.parent));from native_xfl import finalize,audit
        target.mkdir(exist_ok=True);xfl=target/(name+'.xfl')
        if png_inputs:
            audit(xfl,png_inputs);doc=ET.parse(target/'DOMDocument.xml')
        else:
            template=ROOT/'flashswf/backgrounds/cf6/CF6_A01_VectorCandidate01'
            doc=ET.parse(template/'DOMDocument.xml');media=doc.getroot().find(N+'media')
            if media is not None:doc.getroot().remove(media)
            xfl.write_bytes((template/'CF6_A01_VectorCandidate01.xfl').read_bytes())
            (target/'PublishSettings.xml').write_bytes((template/'PublishSettings.xml').read_bytes())
        root=doc.getroot();root.set('width',str(round(width)));root.set('height',str(round(height)))
        for node in list(root):
            if api.tag(node) in ('symbols','timelines','folders'):root.remove(node)
        includes=E('symbols',parent=root)
        for symbol in names:
            path=target/'LIBRARY'/(symbol+'.xml');path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes((out/'LIBRARY'/(symbol+'.xml')).read_bytes())
            E('Include',{'href':symbol+'.xml','loadImmediate':'false'},includes)
        E('timelines',parent=root).append(timeline)
        doc.write(target/'DOMDocument.xml',encoding='utf-8',xml_declaration=True);finalize(xfl,name+'.swf',png_inputs)
        report['state']='native XFL assembled; actual CS6 compile and rendering still pending'
        (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('name','nativeShapes','nativeSymbols','intrinsicTextures','state')},ensure_ascii=False))


if __name__=='__main__':main()
