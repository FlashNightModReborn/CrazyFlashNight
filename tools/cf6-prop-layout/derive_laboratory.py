"""Derive paired pod/vehicle instance recipes from pinned original placement records."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET
import calibrate as c

MAPS={'A11':1907,'A14':1924,'A15':1930,'A16':1945,'A17':1951}

def inverse_point(m,p):
    a,b,d,e,x,y=m;det=a*e-b*d
    if abs(det)<1e-9:raise ValueError('singular original matrix')
    u,v=p[0]-x,p[1]-y
    return [(e*u-d*v)/det,(-b*u+a*v)/det]

def derive():
    recipe=c.read(c.HERE/'recipe.json')
    pod_scale=c.read(c.HERE/'scale-policy.json')['pod']['initialScale']
    recipe['instances']=[i for i in recipe['instances'] if i.get('derivation')!='laboratory-source-pairs.v1']
    for mid,source_sprite in MAPS.items():
        package=next((c.ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图').glob(mid+'-*'))
        source=next(package.glob('*/reference/environment-original-nodes.json'))
        nodes=c.read(source)['nodes']
        placements=[(int(k),v) for k,v in sorted(nodes[str(source_sprite)]['frames'][0].items(),key=lambda kv:int(kv[0])) if v.get('name')!='area' and v.get('colorMult',[256]*4)[3]!=0]
        base=c.ROOT/'flashswf/backgrounds/cf6'/('CF6_'+mid+'_BG');relative='DOMDocument.xml'
        while True:
            nodes_xml=ET.parse(base/relative).getroot().findall('.//x:DOMSymbolInstance',c.NS)
            if len(nodes_xml)!=1:break
            relative='LIBRARY/'+nodes_xml[0].get('libraryItemName')+'.xml'
        baseline=c.HERE/'baselines'/(mid+'-'+Path(relative).name)
        if not baseline.exists():baseline.write_bytes((base/relative).read_bytes())
        original=baseline.read_bytes();instances=c.roots(original)
        if len(placements)!=len(instances):raise ValueError('original/native root occurrence count differs')
        matrices=[c.matrix(i.find('./x:matrix/x:Matrix',c.NS).attrib) for i in instances]
        for (_,p),m in zip(placements,matrices):
            if not c.near(m,p['matrix']):raise ValueError('original/native placement matrix differs')
        g=c.PropGeometry(base/'LIBRARY')
        def add(index,pivot_parent,assembly,category,reason):
            depth,source_item=placements[index];inst=instances[index]
            row={'id':mid+'-source-depth-'+str(depth),'mapId':mid,'category':category,
                 'xflDirectory':base.relative_to(c.ROOT).as_posix(),'parentFile':relative,
                 'instanceIndex':index,'symbol':inst.get('libraryItemName'),
                 'baseline':baseline.relative_to(c.HERE).as_posix(),'baselineSha256':c.sha(original),
                 'pivotNative':inverse_point(matrices[index],pivot_parent),'localVisualScale':75/128*(pod_scale if category=='cultivation-pod' else 1),
                 'assemblyId':assembly,'assemblyPivotParent':pivot_parent,
                 'sourceSprite':source_item['id'],'sourceDepth':depth,'sourceOriginalMatrix':source_item['matrix'],
                 'derivation':'laboratory-source-pairs.v1','sourceArt':source.relative_to(c.ROOT).as_posix(),
                 'sourceArtSha256':c.sha(source.read_bytes()),'justification':reason,
                 'collisionPolicy':'只缩整套物件视觉，原作地面几何不变；底图烘焙保留既有遮挡边界，真实人物绕行/交错另需消费者验收。'}
            recipe['instances'].append(row)
        shells=[i for i,(_,p) in enumerate(placements) if p['id']==1901]
        actors=[i for i,(_,p) in enumerate(placements) if p['id']==1906]
        paired=[]
        for shell in shells:
            origin=placements[shell][1]['matrix'][4:]
            matches=[i for i in actors if c.near(placements[i][1]['matrix'][4:],[origin[0]+36.4,origin[1]+19.1])]
            if len(matches)!=1:raise ValueError('missing/ambiguous authored pod occupant pair')
            actor=matches[0];paired.append(actor)
            shell_bounds=c.bounds(list(g.symbol(instances[shell].get('libraryItemName'))))
            pivot=c.point(matrices[shell],[(shell_bounds[0]+shell_bounds[2])/2,shell_bounds[3]])
            assembly=mid+'-pod-'+str(placements[shell][0])
            for i in [shell,actor]:add(i,list(pivot),assembly,'cultivation-pod','培养舱1901和内部人像1906按原作offset[36.4,19.1]成对，壳和内部同骨架按现役230cm克隆兽尺度统一放大；共同脚点不变，人像/玻璃/遮罩保持同变换。')
        if sorted(paired)!=sorted(actors):raise ValueError('unpaired pod occupant')
        if mid=='A15':
            vehicle=[i for i,(_,p) in enumerate(placements) if p['id'] in (1929,1809,1867)]
            if [placements[i][1]['id'] for i in vehicle]!=[1929,1809,1809,1809,1867]:raise ValueError('vehicle body/wheel/front assembly changed')
            boxes=[c.bounds(list(g.symbol(instances[i].get('libraryItemName'),transform=matrices[i]))) for i in vehicle]
            union=[min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes)]
            pivot=[(union[0]+union[2])/2,union[3]]
            for i in vehicle:add(i,pivot,'A15-armored-van','vehicle-assembly','装甲车1929车身+1809三轮+1867车头围绕同一接地点整体恢复原作比例；轮轴、车头、轮胎不独立缩放。')
    return recipe

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    recipe=derive()
    target=c.HERE/'recipe.json';data=(json.dumps(recipe,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if target.read_bytes()!=data:raise SystemExit('stale laboratory furniture recipe')
    else:target.write_bytes(data)
    print('calibration recipe instances:',len(recipe['instances']))
