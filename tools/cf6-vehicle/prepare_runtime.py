"""Vehicle-only AS2 sources and source-derived collision/spawn constants."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
DEST=ROOT/'scripts/类定义/org/flashNight/arki/scene'


def literal(value):
    if isinstance(value,dict):
        if any(not re.fullmatch(r'[^\W\d]\w*',key,re.UNICODE) for key in value):raise ValueError('non-identifier AS2 field')
        return '{'+','.join(key+':'+literal(item) for key,item in value.items())+'}'
    if isinstance(value,list):return '['+','.join(map(literal,value))+']'
    return json.dumps(value,ensure_ascii=False,separators=(',',':'))


def mul(a,b):
    return [a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5]]


def data():
    nodes=json.loads((HERE/'source/original-nodes.json').read_text(encoding='utf-8'))['nodes']
    def bounds(cid,m=(1,0,0,1,0,0)):
        node=nodes[str(cid)]
        if 'bounds' in node:
            left,top,right,bottom=node['bounds']
            points=[(m[0]*x+m[2]*y+m[4],m[1]*x+m[3]*y+m[5]) for x,y in [(left,top),(right,top),(right,bottom),(left,bottom)]]
            return [min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)]
        children=[bounds(row['id'],mul(m,row['matrix'])) for row in node['frames'][0].values()]
        return [min(r[0] for r in children),min(r[1] for r in children),max(r[2] for r in children),max(r[3] for r in children)]
    def marker(cid,depth,frame=1):
        row=nodes[str(cid)]['frames'][frame-1][str(depth)]
        return bounds(row['id'],row['matrix'])
    world=nodes['1816']['frames']
    result={'player':marker(1803,12),'boss':marker(1813,25),'raider':marker(612,22),
        'shield':marker(629,34),'obstacle':marker(627,2),'grenade':marker(361,4,31),'bullet':marker(356,1),
        'walls':[marker(1816,d) for d in [30,32,34,36]],
        'bossWalls':[marker(1813,d) for d in [29,31,33,35]],
        'escape':marker(1816,38),'tail':[], 'initial':[],
        'generators':[{'kind':'raider','x':1255,'budget':200,'hp':10},
                      {'kind':'obstacle','x':1253,'budget':15,'hp':200},
                      {'kind':'raider','x':1256,'budget':200,'hp':10}],
        'muzzles':[nodes['1803']['frames'][7][str(d)]['matrix'][4:] for d in [18,20]],
        'audio':json.loads((HERE/'audio-manifest.json').read_text(encoding='utf-8'))['cues']}
    kinds={612:'raider',627:'obstacle',629:'shield'}
    for target,frame in [('initial',world[0]),('tail',world[2])]:
        for row in frame.values():
            if row['id'] in kinds:
                result[target].append({'kind':kinds[row['id']],'x':row['matrix'][4],'y':row['matrix'][5],
                    'hp':300 if row['id']==629 else (100 if row['id']==612 else 200),'matrix':row['matrix'][:4]})
            if target=='tail' and row['id']==1795:
                result['endpoint']={'x':row['matrix'][4],'y':row['matrix'][5],'rect':bounds(1795,mul([1,0,0,1,-row['matrix'][4],-row['matrix'][5]],row['matrix']))}
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    outputs={}
    for path in HERE.glob('Cf6Vehicle*.as.txt'):
        outputs[DEST/path.name[:-4]]=path.read_text(encoding='utf-8-sig')
    rules_source=ROOT/'tools/cf6-scene-completion/Cf6VehicleRules.as.txt'
    outputs[DEST/'Cf6VehicleRules.as']=rules_source.read_text(encoding='utf-8-sig')
    outputs[DEST/'Cf6VehicleData.as']='/** Generated from pinned original nodes; do not hand-edit. */\nclass org.flashNight.arki.scene.Cf6VehicleData {\n    public static function create():Object {return '+literal(data())+';}\n}\n'
    generated={}
    for path,text in outputs.items():
        raw=text.replace('\r\n','\n').encode('utf-8-sig')
        if path.name!='Cf6VehicleTest.as':generated[path.relative_to(ROOT).as_posix()]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
        if args.check:
            if not path.is_file() or path.read_bytes()!=raw:raise ValueError('stale '+str(path))
        elif not path.is_file() or path.read_bytes()!=raw:path.write_bytes(raw)
    rules_output=DEST/'Cf6VehicleRules.as'
    expected=rules_source.read_text(encoding='utf-8-sig').replace('\r\n','\n').encode('utf-8-sig')
    if rules_output.read_bytes()!=expected:raise ValueError('canonical vehicle rules consumer is stale')
    generated[rules_output.relative_to(ROOT).as_posix()]={'sha256':hashlib.sha256(expected).hexdigest(),'bytes':len(expected)}
    inputs=[Path(__file__),HERE/'source/original-nodes.json',HERE/'audio-manifest.json',rules_source]+[p for p in HERE.glob('Cf6Vehicle*.as.txt') if p.name!='Cf6VehicleTest.as.txt']
    manifest={'schema':'cf6-vehicle-runtime.v1','inputs':{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},'outputs':generated}
    raw=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8');path=HERE/'runtime-manifest.json'
    if args.check:
        if not path.is_file() or path.read_bytes()!=raw:raise ValueError('stale vehicle runtime manifest')
    elif not path.is_file() or path.read_bytes()!=raw:path.write_bytes(raw)
    print(json.dumps({'state':'checked' if args.check else 'prepared','classes':len(outputs)}))


if __name__=='__main__':main()
