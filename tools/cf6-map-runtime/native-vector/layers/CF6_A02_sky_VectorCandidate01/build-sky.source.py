"""Prepare only A02/A06 independent native skies without changing frozen batch inputs."""
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
from sky_filter import sky_effect

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('sky_generic',HERE/'build-layer.py');generic=importlib.util.module_from_spec(spec);spec.loader.exec_module(generic)
api=generic.api;E=api.E;N=api.N
SOURCES={'A02':'A02-R3/cf6-stage2-redraw-r3/parts/bitmap-1595.svg','A06':'A06-R2/cf6-stage6-redraw-r2/parts/bitmap-1753.svg'}


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


class SkyCandidate(api.Candidate):
    def __init__(self,*a,**kw):super().__init__(*a,**kw);self.sky_effects=[]
    def walk_native(self,node,inherited=None,mask_mode=False):
        match=re.fullmatch(r'url\(#([^)]*)\)',node.get('filter',''))
        if match and match.group(1) in ('cloudsoft','haze'):
            if mask_mode:raise ValueError('sky procedural filters cannot act as luminance masks')
            script,report=sky_effect(self.byid[match.group(1)])
            clone=copy.deepcopy(node);clone.attrib.pop('filter')
            content=self.instance(super().walk_native(clone,inherited,False),'sky-filter-content',name='content')
            self.sky_effects.append(report)
            return [self.instance([content],'native-sky-'+match.group(1),script=script)]
        return super().walk_native(node,inherited,mask_mode)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--map',choices=list(SOURCES),required=True);parser.add_argument('--assemble',action='store_true');args=parser.parse_args()
    ready=json.loads((HERE/'batch/converter-ready.json').read_text(encoding='utf-8'))
    for row in ready['files']:
        if sha(ROOT/row['path'])!=row['sha256']:raise ValueError('frozen input changed: '+row['path'])
    source=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'/SOURCES[args.map]
    name='CF6_'+args.map+'_sky_VectorCandidate01';target=ROOT/'flashswf/backgrounds/cf6'/name;out=HERE/'layers'/name
    target.mkdir(exist_ok=True);out.mkdir(parents=True,exist_ok=True);assets=HERE/'assets';assets.mkdir(exist_ok=True)
    root_svg=ET.parse(source).getroot();width=600 if args.map=='A02' else 800;height=187
    if api.base.nums(root_svg.get('viewBox'))!=[0,0,width,height]:raise ValueError('sky viewport changed')
    textures={};inputs=[]
    for node in root_svg.iter():
        if api.tag(node)!='image':continue
        href=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href') or ''
        if not href.startswith('data:image/png;base64,'):raise ValueError('sky only accepts original embedded PNG')
        raw=base64.b64decode(href.split(',',1)[1]);key=hashlib.sha256(raw).hexdigest()
        if key in textures:continue
        filename='intrinsic-'+key[:24]+'.png';path=assets/filename
        if path.exists() and path.read_bytes()!=raw:raise ValueError('intrinsic byte mismatch')
        if not path.exists():path.write_bytes(raw)
        with Image.open(io.BytesIO(raw)) as im:pixels=list(im.size)
        textures[key]={'name':filename,'pixels':pixels};inputs.append({'path':path.relative_to(ROOT).as_posix(),'sha256':key,'bytes':len(raw),'pixels':pixels})
    c=SkyCandidate(source,textures=textures,allow_filters=True);content=c.instance(c.walk_native(root_svg),'sky-viewport-content',name='content')
    mask=c.instance(c.primitive(ET.Element('{http://www.w3.org/2000/svg}rect',{'width':str(width),'height':str(height)}),{'fill':'#FFFFFF'}),'sky-viewport-mask',name='maskShape')
    placed=c.instance([content,mask],'sky-viewport',script='stop();content.setMask(maskShape);')
    manifest={'schema':'cf6-native-sky-input.v1','map':args.map,'layer':'sky','name':name,'source':source.relative_to(ROOT).as_posix(),'sourceSha256':sha(source),
        'extraction':'original embedded PNG bytes only; no rasterization','inputs':inputs,'textures':textures,'xfl':(target/(name+'.xfl')).relative_to(ROOT).as_posix(),'swf':name+'.swf','size':[width,height]}
    (out/'texture-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if inputs:
        layers=[{'id':'texture-'+str(i),'png':p['path'],'x':0,'y':0,'width':p['pixels'][0],'height':p['pixels'][1],'depth':i} for i,p in enumerate(inputs)]
        (out/'import-textures.jsfl').write_text(generic.builder.jsfl({'id':'native-'+name,'nativeBounds':[0,0,width,height],'worldScale':1},layers,name,target/(name+'.xfl')),encoding='utf-8')
    timeline=E('DOMTimeline',{'name':name});frame=E('DOMFrame',{'index':'0','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':'fixed-sky-art'},E('layers',parent=timeline))))
    E('elements',parent=frame).append(placed);E('script',parent=E('Actionscript',parent=frame)).text='stop();'
    for symbol,tree in c.symbols.items():
        p=out/'LIBRARY'/(symbol+'.xml');p.parent.mkdir(parents=True,exist_ok=True);ET.ElementTree(tree).write(p,encoding='utf-8',xml_declaration=True)
    ET.ElementTree(timeline).write(out/'timeline.xml',encoding='utf-8',xml_declaration=True)
    report={'schema':'cf6-native-sky-candidate.v1','name':name,'source':manifest['source'],'sourceSha256':manifest['sourceSha256'],'nativeShapes':sum(1 for tree in c.symbols.values() for node in tree.iter() if node.tag==N+'DOMShape'),
        'nativeSymbols':len(c.symbols),'intrinsicTextures':len(textures),'size':[width,height],'proceduralEffects':c.sky_effects,'frozenCoreBundleSha256':ready['converterBundleSha256'],
        'specializedInputs':[{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in [Path(__file__),HERE/'sky_filter.py']],
        'state':'native source prepared; source import/assembly, real CS6 compile and consumer verification remain separate'}
    if args.assemble:
        sys.path.insert(0,str(HERE.parent));from native_xfl import audit,finalize
        xfl=target/(name+'.xfl')
        if inputs:audit(xfl,inputs);doc=ET.parse(target/'DOMDocument.xml')
        else:
            template=ROOT/'flashswf/backgrounds/cf6/CF6_A01_VectorCandidate01';doc=ET.parse(template/'DOMDocument.xml');media=doc.getroot().find(N+'media')
            if media is not None:doc.getroot().remove(media)
            xfl.write_bytes((template/(template.name+'.xfl')).read_bytes());(target/'PublishSettings.xml').write_bytes((template/'PublishSettings.xml').read_bytes())
        root=doc.getroot();root.set('width',str(width));root.set('height',str(height))
        for n in list(root):
            if api.tag(n) in ('symbols','timelines','folders'):root.remove(n)
        includes=E('symbols',parent=root)
        for symbol in c.symbols:
            p=target/'LIBRARY'/(symbol+'.xml');p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((out/'LIBRARY'/(symbol+'.xml')).read_bytes());E('Include',{'href':symbol+'.xml','loadImmediate':'false'},includes)
        E('timelines',parent=root).append(timeline);doc.write(target/'DOMDocument.xml',encoding='utf-8',xml_declaration=True);finalize(xfl,name+'.swf',inputs)
        report['state']='native XFL assembled; real CS6 compile and consumer verification still pending'
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for p in [Path(__file__),HERE/'sky_filter.py',HERE/'build-a01.py']:(out/(p.stem+'.source.py')).write_bytes(p.read_bytes())
    print(json.dumps({k:report[k] for k in ('name','nativeShapes','nativeSymbols','intrinsicTextures','state')},ensure_ascii=False))


if __name__=='__main__':main()
