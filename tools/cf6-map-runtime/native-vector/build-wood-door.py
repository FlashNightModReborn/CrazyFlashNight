"""Native vector door parts and original placement matrices (wood/exit/grand)."""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('cf6_vector_candidate',HERE/'build-a01.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
E=api.E;N=api.N
PROFILES={
    'wood1714':{'package':'A03-R1/cf6-stage3-redraw-r1','name':'CF6_DoorWood1714_VectorCandidate01','sprite':1714,'frames':9,'parts':[1707,1709,1710,1711,1712],'offset':[85,100],'size':[170,240],'entry':'shape-1709.svg'},
    'exit1720':{'package':'A03-R1/cf6-stage3-redraw-r1','name':'CF6_DoorExit1720_VectorCandidate01','sprite':1720,'frames':50,'parts':[1715,1716,1718],'offset':[85,100],'size':[170,240],'entry':'shape-1718.svg'},
    'grand1750':{'package':'A05-R3/cf6-stage5-redraw-r3','name':'CF6_DoorGrand1750_VectorCandidate01','sprite':1750,'frames':40,'parts':[86,1747,1748,1749],'offset':[200,110],'size':[400,280],'entry':'shape-1747.svg'}}


def build(kind):
    config=PROFILES[kind]
    PACKAGE=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'/config['package']
    NAME=config['name'];TARGET=ROOT/'flashswf/backgrounds/cf6'/NAME
    nodes_path=PACKAGE/'reference/environment-original-nodes.json'
    nodes=json.loads(nodes_path.read_text(encoding='utf-8'))['nodes']
    converter=api.Candidate(PACKAGE/'parts'/config['entry'])
    parts={};inputs=[nodes_path]
    for cid in config['parts']:
        path=PACKAGE/'parts'/('shape-'+str(cid)+'.svg')
        if path.is_file():
            tree=ET.parse(path).getroot();inputs.append(path)
        else:
            tree=ET.fromstring('<svg xmlns="http://www.w3.org/2000/svg" viewBox="'+' '.join(map(str,nodes[str(cid)]['viewBox']))+'">'+nodes[str(cid)]['svgInner']+'</svg>')
        converter.byid={n.get('id'):n for n in tree.iter() if n.get('id')}
        converter.grads={n.get('id'):n for n in tree.iter() if api.tag(n) in ('linearGradient','radialGradient')}
        elements=converter.walk_native(tree)
        parts[cid]=converter.instance(elements,'original-shape-'+str(cid))
    timeline=E('DOMTimeline',{'name':'Original '+str(config['sprite'])+' isolated environment frames'})
    layers=E('layers',parent=timeline);layer=E('DOMLayer',{'name':'original placements and clipping'},layers);frames=E('frames',parent=layer)
    masks=[]
    def instance(placement):
        node=copy.deepcopy(parts[placement['id']]);old=node.find(N+'matrix');node.remove(old)
        api.matrix(node,placement['matrix'])
        mult=placement.get('colorMult',[256]*4);add=placement.get('colorAdd',[0]*4)
        if mult!=[256]*4 or add!=[0]*4:
            attrs={channel+'Multiplier':api.base.fmt(mult[i]/256) for i,channel in enumerate(('red','green','blue','alpha'))}
            attrs.update({channel+'Offset':str(add[i]) for i,channel in enumerate(('red','green','blue','alpha'))})
            E('Color',attrs,E('color',parent=node))
        return node
    for index,frame in enumerate(nodes[str(config['sprite'])]['frames'][:config['frames']]):
        output=[];rows=sorted((int(depth),place) for depth,place in frame.items() if place['id'] in config['parts']);i=0
        while i<len(rows):
            depth,place=rows[i];i+=1
            if 'clipDepth' not in place:output.append(instance(place));continue
            children=[]
            while i<len(rows) and rows[i][0]<=place['clipDepth']:
                if 'clipDepth' in rows[i][1]:raise ValueError('nested original clip needs explicit extension')
                children.append(instance(rows[i][1]));i+=1
            content=converter.instance(children,'door-content',name='content')
            mask=converter.instance([instance(place)],'door-clip',name='maskShape')
            output.append(converter.instance([content,mask],'original-depth-'+str(depth),script='stop();content.setMask(maskShape);'))
            masks.append({'sourceFrame':index+1,'depth':depth,'clipDepth':place['clipDepth']})
        fr=E('DOMFrame',{'index':str(index),'duration':'1','keyMode':'9728'},frames)
        E('script',parent=E('Actionscript',parent=fr)).text='stop();'
        els=E('elements',parent=fr)
        # Match the same [-85,-100,170,240] registration as the prior frame PNG
        # sequence. Runtime placement can switch resources without moving the door.
        els.append(converter.instance(output,'door-frame-'+str(index+1),(1,0,0,1,*config['offset'])))
    TARGET.mkdir(exist_ok=True)
    template=ROOT/'flashswf/backgrounds/cf6/CF6_A01_VectorCandidate01'
    doc=ET.parse(template/'DOMDocument.xml');root=doc.getroot();root.set('width',str(config['size'][0]));root.set('height',str(config['size'][1]))
    for child in list(root):
        if api.tag(child) in ('media','symbols','timelines','folders'):root.remove(child)
    includes=E('symbols',parent=root)
    for name,tree in converter.symbols.items():
        path=TARGET/'LIBRARY'/(name+'.xml');path.parent.mkdir(parents=True,exist_ok=True)
        ET.ElementTree(tree).write(path,encoding='utf-8',xml_declaration=True)
        E('Include',{'href':name+'.xml','loadImmediate':'false'},includes)
    E('timelines',parent=root).append(timeline)
    doc.write(TARGET/'DOMDocument.xml',encoding='utf-8',xml_declaration=True)
    (TARGET/(NAME+'.xfl')).write_bytes((template/'CF6_A01_VectorCandidate01.xfl').read_bytes())
    if (template/'mimetype').is_file():(TARGET/'mimetype').write_bytes((template/'mimetype').read_bytes())
    profile=ET.parse(template/'PublishSettings.xml')
    profile.find('.//PublishFormatProperties/flashFileName').text=NAME+'.swf'
    profile.write(TARGET/'PublishSettings.xml',encoding='utf-8',xml_declaration=True)
    report={'schema':'cf6-native-door-candidate.v1','name':NAME,'frames':config['frames'],'sourceSprite':config['sprite'],
            'nativeShapesProcessed':converter.shape_count,'nativeSymbols':len(converter.symbols),'originalClipDepths':masks,
            'originalRootWhitelist':config['parts'],'excluded':'all actor/weapon/transition root nodes and inherited ActionScript',
            'sourceInputs':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in inputs],
            'textureCount':0,'nativeRootScripts':'stop only; mask wrappers initialize native setMask; no inherited game actions',
            'state':'native XFL source only; CS6 compile and actual playback of every source frame required'}
    (HERE/(kind+'-door-report.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--kind',choices=list(PROFILES),default='wood1714');args=parser.parse_args();build(args.kind)
