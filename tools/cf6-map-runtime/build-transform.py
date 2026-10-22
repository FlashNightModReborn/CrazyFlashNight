"""A21 display-only 93-frame actor closure; strips every inherited action/linkage.

The original elder library remains the editable art authority. This target is a
deterministic presentation derivative, not another unit or a boss-spawn owner.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from lxml import etree as E

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'flashswf/arts/new/Codex老头素材'
TARGET=ROOT/'flashswf/backgrounds/cf6/CF6_A21_Transform'
N={'x':'http://ns.adobe.com/xfl/2008/'}
Q='{'+N['x']+'}'
ANCHOR='Codex/老头/变身/角色演出'
PREFIX='CF6A21/'


def elem(tag, **attrs): return E.Element(Q+tag, {k:str(v) for k,v in attrs.items()})


def build():
    output={};symbols={};source_rows=[]
    def visit(name):
        if name in symbols: return PREFIX+name
        path=SOURCE/'LIBRARY'/(name+'.xml')
        data=path.read_bytes();tree=E.fromstring(data)
        source_rows.append({'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(data).hexdigest()})
        symbols[name]=tree
        tree.set('name',PREFIX+name)
        tree.set('itemID','6af60000-'+hashlib.sha256(name.encode()).hexdigest()[:8])
        for attr in list(tree.attrib):
            if attr.startswith('linkage'):del tree.attrib[attr]
        for action in tree.findall('.//x:Actionscript',N):action.getparent().remove(action)
        for node in tree.iter():
            for attr in list(node.attrib):
                if attr.startswith('sound'):del node.attrib[attr]
        for instance in tree.findall('.//x:DOMSymbolInstance',N):
            instance.set('libraryItemName',visit(instance.get('libraryItemName')))
        # Parent owns the timeline frame cursor. No inherited onClipEvent or self-advancement.
        return PREFIX+name
    visit(ANCHOR)
    doc=elem('DOMDocument',frameRate=30,width=1280,height=720,xflVersion='2.2',
        creatorInfo='Adobe Flash Professional CS6',platform='Windows',majorVersion=12,buildNumber=481)
    doc=E.Element(Q+'DOMDocument',dict(doc.attrib),nsmap={None:N['x']})
    includes=elem('symbols');doc.append(includes)
    for name,tree in sorted(symbols.items()):
        href=PREFIX+name+'.xml'
        includes.append(elem('Include',href=href,itemID=tree.get('itemID')))
        output[TARGET/'LIBRARY'/href]=E.tostring(tree,encoding='utf-8',pretty_print=True)
    timelines=elem('timelines');doc.append(timelines)
    timeline=elem('DOMTimeline',name='A21 display only');timelines.append(timeline)
    layers=elem('layers');timeline.append(layers)
    layer=elem('DOMLayer',name='actor');layers.append(layer)
    frames=elem('frames');layer.append(frames)
    frame=elem('DOMFrame',index=0,keyMode=9728);frames.append(frame)
    action=elem('Actionscript');script=elem('script');script.text=E.CDATA('stop();actor.stop();');action.append(script);frame.append(action)
    elements=elem('elements');frame.append(elements)
    instance=elem('DOMSymbolInstance',libraryItemName=PREFIX+ANCHOR,name='actor');elements.append(instance)
    matrix=elem('matrix');matrix.append(elem('Matrix',a=2/3,d=2/3,tx=0,ty=-133.325*2/3));instance.append(matrix)
    output[TARGET/'DOMDocument.xml']=E.tostring(doc,encoding='utf-8',pretty_print=True)
    output[TARGET/'CF6_A21_Transform.xfl']=b'PROXY-CS5'
    publish=E.parse(str(SOURCE/'PublishSettings.xml'))
    for node in publish.getroot().iter():
        if node.tag=='flashFileName':node.text='CF6_A21_Transform.swf'
        elif node.tag=='html':node.text='0'
    output[TARGET/'PublishSettings.xml']=E.tostring(publish,encoding='utf-8',pretty_print=True)
    manifest={'schema':'cf6-a21-display.v1','sourceRoot':SOURCE.relative_to(ROOT).as_posix(),
        'sourceAnchor':ANCHOR,'sourceFrames':93,'animationOwner':'Cf6MapMechanism',
        'bossSpawnOwner':'A22 standard Wave only','inheritedActions':0,'exportedLinkage':0,
        'sources':source_rows,'outputs':[{ 'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)} for p,b in sorted(output.items())]}
    output[Path(__file__).parent/'generated/a21-transform.manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    return output


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    outputs=build()
    for p,b in outputs.items():
        if args.check:assert p.is_file() and p.read_bytes()==b, f'stale: {p}'
        else:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
    print(f'{len(outputs)} A21 display artifacts; requires actual CS6 publish and visual verification')
