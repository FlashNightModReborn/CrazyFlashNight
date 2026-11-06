"""Deterministically assemble approved Tonghe SVG geometry into the existing icon.

Only the existing money wrapper and its unexported 32-frame child are replaced.
The SVG silhouette clip becomes a native Flash mask. Native coordinates are
8x, paired with an exact 0.125 wrapper transform, to retain sub-twip detail
without making the nested icon baker render 5K intermediate frames.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from coin_svg import Coin

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'flashswf/arts/new/Codex素材源稿/统合金币R4'
LIBRARY=ROOT/'flashswf/arts/素材库-物品技能图标'
CHILD=LIBRARY/'LIBRARY/消耗道具相关/Symbol 4297.xml'
WRAPPER=LIBRARY/'LIBRARY/消耗道具相关/图标-金钱.xml'
NATIVE_SCALE=8
NS='http://ns.adobe.com/xfl/2008/'
ET.register_namespace('',NS)
ET.register_namespace('xsi','http://www.w3.org/2001/XMLSchema-instance')

def module(path):
    spec=importlib.util.spec_from_file_location('tonghe_native_writer',path)
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod

def xml_bytes(root):
    ET.indent(root,space='  ')
    return (ET.tostring(root,encoding='unicode')+'\n').encode('utf-8')

def produce():
    native=module(ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py')
    E=native.E
    asset=Coin(SOURCE/'model.json',SOURCE/'original_node.svg',SOURCE/'style.json')
    child=E('DOMSymbolItem',{'name':'消耗道具相关/Symbol 4297','itemID':'668e7c1e-0000108a'})
    layers=E('layers',parent=E('DOMTimeline',{'name':'Symbol 4297'},E('timeline',parent=child)))
    mask=E('DOMLayer',{'name':'统合金币-轮廓遮罩','layerType':'mask','locked':'true','color':'#999999'},layers)
    art=E('DOMLayer',{'name':'统合金币-R4矢量','parentLayerIndex':'0','locked':'true','color':'#D7BB40'},layers)
    mask_frames=E('frames',parent=mask);art_frames=E('frames',parent=art)
    result={};frames=[]
    matrix=(NATIVE_SCALE,0,0,NATIVE_SCALE,-14*NATIVE_SCALE,-14*NATIVE_SCALE)
    for frame in range(32):
        svg,info=asset.svg(frame*11.25)
        svg_path=SOURCE/'svg'/f'frame_{frame:02d}.svg'
        result[svg_path]=svg.encode('utf-8')
        writer=native.Writer.__new__(native.Writer)
        writer.root=ET.fromstring(svg)
        writer.grads={e.get('id'):e for e in writer.root.iter() if native.tag(e) in ('linearGradient','radialGradient')}
        writer.shape_count=writer.segment_count=0
        bodies=[e for e in writer.root if native.tag(e)=='g']
        if len(bodies)!=1:raise ValueError('Expected one isolated SVG body')
        body=copy.deepcopy(bodies[0])
        if body.attrib.pop('clip-path',None)!='url(#coin-silhouette)':raise ValueError('Unexpected SVG clip')
        # This is the SVG rasterizer isolation workaround, not a design fade.
        # Preserve it once on the native outer instance rather than per shape.
        if body.attrib.pop('opacity',None)!='.9999':raise ValueError('Unexpected group opacity')
        clip=next(e for e in writer.root.iter() if e.get('id')=='coin-silhouette')
        if len(clip)!=1:raise ValueError('Expected one silhouette path')
        mask_element=writer.shape(clip[0],{'fill':'#FFFFFF','stroke':'none'},matrix)
        mf=E('DOMFrame',{'index':frame,'duration':'1','keyMode':'9728'},mask_frames)
        E('elements',parent=mf).append(mask_element)
        af=E('DOMFrame',{'index':frame,'duration':'1','keyMode':'9728'},art_frames)
        elements=E('elements',parent=af)
        for shape in writer.walk(body,{},matrix):elements.append(shape)
        info.update({'native_shapes':writer.shape_count,'native_segments':writer.segment_count,
                     'svg_sha256':hashlib.sha256(svg.encode()).hexdigest()})
        frames.append(info)
    wrapper=E('DOMSymbolItem',{'name':'消耗道具相关/图标-金钱','itemID':'66a5ea66-000017d6',
                              'linkageExportForAS':'true','linkageIdentifier':'图标-金钱'})
    ls=E('layers',parent=E('DOMTimeline',{'name':'图标-金钱'},E('timeline',parent=wrapper)))
    f=E('DOMFrame',{'index':'0','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':'统合金币-共享动画','color':'#D7BB40'},ls)))
    instance=E('DOMSymbolInstance',{'libraryItemName':'消耗道具相关/Symbol 4297'},E('elements',parent=f))
    E('Matrix',{'a':'0.125','d':'0.125'},E('matrix',parent=instance))
    E('Point',parent=E('transformationPoint',parent=instance))
    E('Color',{'alphaMultiplier':'0.9999'},E('color',parent=instance))
    result[CHILD]=xml_bytes(child);result[WRAPPER]=xml_bytes(wrapper)
    inputs=[SOURCE/n for n in ['model.json','style.json','original_node.svg','R3_B_original_unchanged.blend']]
    inputs += [Path(__file__),Path(__file__).with_name('coin_svg.py'),ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py']
    publication_inputs=[Path(__file__).with_name(n) for n in ['publish.py','repair_font_metrics.py','verify_swf.py']]+sorted(Path(__file__).with_name('compile-fonts').glob('*'))
    manifest={'schema':'tonghe-gold-native/v1','revision':'side-reeds-restored-v2','fps':30,'frames':32,
              'native_scale':NATIVE_SCALE,'wrapper_scale':.125,'canvas':[28,28],'pivot':[14,14],
              'native_origin':[0,0],'linkage':'图标-金钱','native_mask':True,'bitmaps':False,
              'inputs':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in inputs],
              'publication_inputs':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in publication_inputs if p.is_file()],
              'outputs':[{'path':p.relative_to(ROOT).as_posix(),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()} for p,b in result.items()],
              'frame_audit':frames}
    result[SOURCE/'native-manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    return result,manifest

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');args=ap.parse_args()
    files,manifest=produce();bad=[]
    for path,data in files.items():
        if args.check:
            if not path.is_file() or path.read_bytes()!=data:bad.append(path.relative_to(ROOT).as_posix())
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    if bad:raise SystemExit('Stale generated outputs: '+', '.join(bad))
    print(json.dumps({'checked':args.check,'frames':32,'generated_files':len(files),'native_shapes':sum(f['native_shapes'] for f in manifest['frame_audit']),
                      'native_xfl_bytes':sum(len(files[p]) for p in [CHILD,WRAPPER])},ensure_ascii=False))

if __name__=='__main__':main()
