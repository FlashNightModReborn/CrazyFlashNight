"""Consume already-delivered independent A01-A05 art without editing K3 source files.

Door animation and interactive props are explicit pending items, never flattened
from a panorama. This batch prepares compilable geometry/background targets.
"""
from pathlib import Path
import argparse
import json
import hashlib

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
ARCHIVE=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'
PACKAGES={'A02':('R3','cf6-stage2-redraw-r3'),'A03':('R1','cf6-stage3-redraw-r1'),
          'A04':('R1','cf6-stage4-redraw-r1'),'A05':('R3','cf6-stage5-redraw-r3')}


def layer(key,path,vb,role='background',position=(0,0),depth=0):
    assert path.is_file(),str(path)
    return {'id':key,'role':role,'sourceKind':'background' if role=='background' else 'isolated-part',
        'png':path.relative_to(ROOT).as_posix(),'x':vb[0]+position[0],'y':vb[1]+position[1],
        'width':vb[2],'height':vb[3],'depth':depth}


def build():
    input_path=ROOT/'tools/cf6-map-source/generated/map-input.json'
    source=json.loads(input_path.read_text(encoding='utf-8'))
    source_maps=source['maps']
    a01=dict(source_maps['A01']) if isinstance(source_maps,dict) else next(dict(m) for m in source_maps if m.get('id')=='A01')
    a01['id']='A01';a01['layers'][0]['sourceKind']='background'
    result={'schema':'cf6-map-input.v1','maps':[a01]}
    report={'schema':'cf6-map-batch-readiness.v1','maps':[{'id':'A01','backgroundPrepared':True,
        'pending':['independent yellow lamp','interactive turret and crate consumers']} ]}
    for key,(rev,name) in PACKAGES.items():
        root=ARCHIVE/(key+'-'+rev)/name
        registration=root/'baked/registration.json'
        config=json.loads(registration.read_text(encoding='utf-8'))
        base=config['optionalFlattenedBackground'] if key=='A02' else config['background']
        vb=base.get('nativeViewBox',base.get('viewBox'));pos=base['worldPlacement']
        bg=layer('background',root/'baked'/base['png'],vb,position=pos,depth=10)
        native=[bg['x'],bg['y'],bg['width'],bg['height']]
        layers=[];pending=[]
        if key=='A02':
            # Preserve the independent sky and city images; prototype uses fixed world
            # placement and repeats the native sky without stretching its texture.
            native=[min(0,bg['x']),0,bg['width'],max(bg['y']+bg['height'],500)]
            sky=root/'baked/bitmap-1595.png'
            for i in range(3):layers.append(layer('sky-'+str(i),sky,[0,0,600,187],position=(600*i,0),depth=i))
            city=config['optionalCityLayer']
            layers.append(layer('city',root/'baked'/city['png'],city['nativeViewBox'],depth=5))
            pending.extend(['source camera parallax currently fixed in prototype','interactive crate consumer'])
        layers.append(bg)
        if 'foreground' in config:
            fg=config['foreground'];front=layer('foreground',root/'baked'/fg['png'],fg['viewBox'],role='foreground',depth=20)
            front['parallax']=fg['cameraParallax'];layers.append(front)
            pending.extend(['source door animation and matching exit position','foreground parallax awaits controller support'])
        result['maps'].append({'id':key,'nativeBounds':native,'worldScale':1,'walkBounds':None,'spawn':None,'exit':None,
            'collisions':[],'layers':layers,
            'artProvenance':{'registration':registration.relative_to(ROOT).as_posix(),
                'sha256':hashlib.sha256(registration.read_bytes()).hexdigest(),
                'independentBackground':base['png'],'notScenePreview':True}})
        report['maps'].append({'id':key,'backgroundPrepared':True,'pending':pending})
    return result,report


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    data,report=build()
    for name,value in [('first-batch-input.json',data),('first-batch-readiness.json',report)]:
        path=HERE/'generated'/name;content=(json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
        if args.check:assert path.read_bytes()==content,'stale '+name
        else:path.write_bytes(content)
    print('A01-A05 independent background batch prepared; readiness manifest retains unfinished doors/props/parallax')
