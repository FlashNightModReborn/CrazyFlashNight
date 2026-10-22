"""Native PNG import recipes for isolated door frame sets; no Flash process control."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
spec=importlib.util.spec_from_file_location('cf6_map_build',HERE/'build.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
NAMES={'wood1714':'CF6_DoorWood1714','exit1720':'CF6_DoorExit1720','grand1750':'CF6_DoorGrand1750'}


def build():
    source=HERE/'generated/door-art.manifest.json'
    art=json.loads(source.read_text(encoding='utf-8'))
    index={'schema':'cf6-door-native.v1','sourceManifestSha256':hashlib.sha256(source.read_bytes()).hexdigest(),
           'timelineOwner':'Cf6MapMechanism; imported XFL must be finalized before publishing','sets':[]}
    outputs={}
    for row in art['sets']:
        name=NAMES[row['id']];xfl=ROOT/'flashswf/backgrounds/cf6'/name/(name+'.xfl')
        box=row['viewBox'];layers=[];inputs=[]
        for i,frame in enumerate(row['frames']):
            png=ROOT/frame['png'];digest=hashlib.sha256(png.read_bytes()).hexdigest()
            if digest!=frame['pngSha256']:raise ValueError('Door frame differs from manifest: '+str(png))
            layers.append({'id':'frame'+str(frame['sourceFrame']),'png':frame['png'],
                'x':0,'y':0,'width':box[2],'height':box[3],'depth':i})
            inputs.append({'path':frame['png'],'sha256':digest,'bytes':png.stat().st_size,'sourceFrame':frame['sourceFrame']})
        m={'id':row['id'],'nativeBounds':[0,0,box[2],box[3]],'worldScale':1}
        outputs[HERE/'generated/native-sequences'/(name+'.jsfl')]=builder.jsfl(m,layers,name,xfl).encode('utf-8')
        index['sets'].append({'id':row['id'],'name':name,'xfl':xfl.relative_to(ROOT).as_posix(),
            'swf':'flashswf/backgrounds/cf6/'+name+'.swf','frames':len(inputs),'viewBox':box,'inputs':inputs,
            'behavior':'entry open-close pulse' if row['id']=='wood1714' else 'clear-only opening; terminal open frame',
            'excluded':'all inherited actions, actors, weapons, collision markers and transitions'})
    outputs[HERE/'generated/door-runtime-index.json']=(json.dumps(index,ensure_ascii=False,indent=2)+'\n').encode()
    return outputs,index


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    outputs,index=build()
    for path,content in outputs.items():
        if args.check:assert path.read_bytes()==content,'stale '+str(path)
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
    if not args.check:
        (ROOT/'tmp/cf6-map-runtime/native-import').mkdir(parents=True,exist_ok=True)
        for row in index['sets']:(ROOT/row['xfl']).parent.mkdir(parents=True,exist_ok=True)
    print('prepared native door recipes; native import, finalize-door-native and precise CS6 publish remain required')
