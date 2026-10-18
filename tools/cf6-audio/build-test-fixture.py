"""Bind each SFX probe to an actual exported actor and its native body placement."""
from pathlib import Path
import argparse,hashlib,json,shutil
from lxml import etree as E
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
NS={'x':'http://ns.adobe.com/xfl/2008/'}


def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def sfx(row,cid):
    if row.get('envelope'):
        key=hashlib.sha256(json.dumps(row['envelope'],sort_keys=True,separators=(',',':')).encode()).hexdigest()[:10]
        return f'CF6_{cid:04d}_{key}.wav'
    return f'CF6_{cid:04d}.mp3'
def literal(value):
    if isinstance(value,str):return json.dumps(value,ensure_ascii=False)
    if isinstance(value,bool):return 'true' if value else 'false'
    if isinstance(value,list):return '['+','.join(literal(x) for x in value)+']'
    if isinstance(value,dict):return '{'+','.join(k+':'+literal(v) for k,v in value.items())+'}'
    return str(value)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    config=json.loads((HERE/'cues.json').read_text('utf8'));batches=[];inputs=[]
    for owner,group in config['owners'].items():
        folder=ROOT/'flashswf/arts/new'/owner
        roots=[]
        for p in (folder/'LIBRARY').rglob('*.xml'):
            tree=E.parse(str(p))
            link=tree.getroot().get('linkageIdentifier','')
            if link.startswith('敌人-') and tree.getroot().get('linkageExportForAS')=='true':roots.append((link,p,tree))
        records=[]
        for row in group['cues']:
            options=[]
            for link,p,tree in roots:
                labels={int(f.get('index')):f.get('name') for f in tree.findall('.//x:DOMFrame[@labelType="name"]',NS)}
                for inst in tree.findall('.//x:DOMSymbolInstance[@name="man"]',NS):
                    if inst.get('libraryItemName')!=row['symbol']:continue
                    frame=int(inst.getparent().getparent().get('index'))
                    state=labels[max((k for k in labels if k<=frame),default=min(labels))]
                    preferred=('持盾' in link)==('持盾' in row['symbol'] or row['symbol'].endswith('/破盾'))
                    options.append((not preferred,frame,link,state,p))
            if not options:raise ValueError('No actual root/body placement for '+row['symbol'])
            _,frame,link,state,p=sorted(options)[0];inputs.append(p)
            body=E.parse(str(folder/'LIBRARY'/(row['symbol']+'.xml')))
            body_frames=body.findall('.//x:DOMFrame',NS)
            count=max(int(f.get('index','0'))+int(f.get('duration','1')) for f in body_frames)
            busy={int(f.get('index'))+1 for f in body_frames if f.findall('.//x:Actionscript',NS)}
            quiet=next(f for f in range(2,count+1) if f not in busy and f!=row['frame'])
            records.append({'linkage':link,'rootFrame':frame+1,'state':state,'frame':row['frame'],
                'sounds':[sfx(row,cid) for cid in row['soundIds']],'onLoad':False,'pause':True,'quiet':quiet,
                'once':row.get('once',False),'branches':[c['frame'] for c in group['cues'] if c['symbol']==row['symbol']] if row.get('once') else []})
        # Both old female voice routes are exercised separately from newly added cue guards.
        if owner=='Antigravity专用素材':
            link,p,tree=next(r for r in roots if r[0]=='敌人-CF6女僵尸')
            for body,frame,onload in [('Antigravity/CF6女僵尸/动作/击倒',6,False),('Antigravity/CF6女僵尸/动作/血腥死',1,True)]:
                inst=next(i for i in tree.findall('.//x:DOMSymbolInstance[@name="man"]',NS) if i.get('libraryItemName')==body)
                records.append({'linkage':link,'rootFrame':int(inst.getparent().getparent().get('index'))+1,
                    'state':'血腥死' if onload else '击倒','frame':frame,'sounds':['CF6_1143.mp3','CF6_1150.mp3'],
                    'onLoad':onload,'pause':False,'quiet':3,'once':False,'branches':[]})
        if owner in ('Codex特种兵素材','Codex光头保安素材','CodexWings素材'):
            death=next(r for r in records if r['state']=='血腥死')
            for _ in range(3):records.append({**death,'frame':1,'onLoad':True,'pause':False})
        batches.append({'swf':'../flashswf/arts/new/'+owner+'.swf','owner':owner,'cases':records})
        inputs.extend([folder.with_suffix('.swf'),HERE/'cues.json'])
    text='_root.cf6AudioBatches='+literal(batches)+';\n'
    destination=ROOT/'scripts/test-runners/cf6-audio/AudioFixture.as'
    expected=b'\xef\xbb\xbf'+text.encode('utf8')
    report={'schema':'cf6.audio-test-fixture.v1','cases':sum(len(b['cases']) for b in batches),
        'batches':batches,'fixtureSha256':hashlib.sha256(expected).hexdigest(),
        'inputs':[{'path':p.relative_to(ROOT).as_posix(),'sha256':digest(p)} for p in sorted(set(inputs))]}
    manifest=HERE/'test-fixture-manifest.json'
    if args.check:
        assert destination.read_bytes()==expected and json.loads(manifest.read_text('utf8'))==report,'Regenerate audio probe bindings'
    else:
        destination.parent.mkdir(parents=True,exist_ok=True)
        if not destination.exists():shutil.copyfile(ROOT/'scripts/test-runners/cf6-playtest/PlaytestFixture.as',destination)
        assert destination.read_bytes()[:3]==expected[:3]
        destination.write_bytes(expected);manifest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf8')
    print(json.dumps({'ok':True,'cases':report['cases'],'libraries':len(batches)}))


if __name__=='__main__':main()
