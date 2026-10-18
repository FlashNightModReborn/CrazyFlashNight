"""Bind restored native SFX to three clones and the old female agent."""
from pathlib import Path
import argparse,hashlib,json,shutil
from lxml import etree as E
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
NS={'x':'http://ns.adobe.com/xfl/2008/'}
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
assets={a.get('id'):a for a in E.parse(str(ROOT/'data/items/asset_source_map.xml')).getroot().iter('asset')}
def literal(x):
    if isinstance(x,str):return json.dumps(x,ensure_ascii=False)
    if isinstance(x,bool):return 'true' if x else 'false'
    if isinstance(x,list):return '['+','.join(literal(v) for v in x)+']'
    if isinstance(x,dict):return '{'+','.join(k+':'+literal(v) for k,v in x.items())+'}'
    return str(x)
batches=[];inputs=set()
config=json.loads((HERE/'legacy-assets.json').read_text('utf8'))
for link in config['files'][0]['affectedLinkages']:
    asset=assets[link];swf=ROOT/asset.get('swf');folder=swf.with_suffix('')/'LIBRARY'
    root_path=folder/(asset.get('symbolName')+'.xml');root=E.parse(str(root_path));records=[]
    labels={int(f.get('index')):f.get('name') for f in root.findall('.//x:DOMFrame[@labelType="name"]',NS)}
    for inst in root.findall('.//x:DOMSymbolInstance[@name="man"]',NS):
        p=folder/(inst.get('libraryItemName')+'.xml');body=E.parse(str(p))
        cues=[int(f.get('index'))+1 for f in body.findall('.//x:DOMFrame',NS)
            if any('播放音效("soundheadexplode.wav")' in (s.text or '') for s in f.findall('x:Actionscript/x:script',NS))]
        if not cues:continue
        root_frame=int(inst.getparent().getparent().get('index'))
        state=labels[max(k for k in labels if k<=root_frame)]
        busy={int(f.get('index'))+1 for f in body.findall('.//x:DOMFrame',NS) if f.findall('.//x:Actionscript',NS)}
        quiet=next(f for f in range(2,30) if f not in busy)
        for frame in cues:records.append({'linkage':link,'rootFrame':root_frame+1,'state':state,'frame':frame,
            'sounds':['soundheadexplode.wav'],'onLoad':False,'pause':False,'quiet':quiet,'once':False,'branches':[]})
        inputs.add(p)
    if len(records)!=2:raise ValueError('Unexpected legacy death consumers '+link+': '+str(records))
    batches.append({'owner':link,'swf':'../'+asset.get('swf'),'cases':records});inputs.update([swf,root_path])
legacy_cues=json.loads((HERE/'legacy-cues.json').read_text('utf8'))
link=legacy_cues['linkage'];asset=assets[link];swf=ROOT/asset.get('swf');folder=swf.with_suffix('')/'LIBRARY'
root_path=folder/(asset.get('symbolName')+'.xml');root=E.parse(str(root_path));records=[]
labels={int(f.get('index')):f.get('name') for f in root.findall('.//x:DOMFrame[@labelType="name"]',NS)}
for cue in legacy_cues['cues']:
    insts=root.findall('.//x:DOMSymbolInstance[@libraryItemName="'+cue['symbol']+'"]',NS)
    assert len(insts)==1
    root_frame=int(insts[0].getparent().getparent().get('index'))
    assert root_frame+1==cue['rootFrame']
    state=labels[max(k for k in labels if k<=root_frame)]
    records.append({'linkage':link,'rootFrame':root_frame+1,'state':state,'frame':cue['frame'],
        'sounds':[cue['sound']],'onLoad':False,'pause':True,'quiet':2,'once':False,'branches':[],'bodyMarker':'cf6LegacyAudioBody'})
    inputs.update([ROOT/cue['path'],ROOT/'sounds/export/人物'/cue['sound']])
batches.append({'owner':link,'swf':'../'+asset.get('swf'),'cases':records})
inputs.update([swf,root_path,HERE/'legacy-cues.json',HERE/'restore-legacy-cues.py'])
inputs.update([ROOT/config['files'][0]['target'],ROOT/config['files'][0]['source'],HERE/'legacy-assets.json'])
folder=ROOT/'scripts/test-runners/cf6-audio'
content='_root.cf6AudioBatches='+literal(batches)+';\n'
dest=folder/'LegacyAudioFixture.as';expected=b'\xef\xbb\xbf'+content.encode('utf8')
manifest={'cases':sum(len(b['cases']) for b in batches),'batches':batches,'fixtureSha256':hashlib.sha256(expected).hexdigest(),
    'inputs':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(inputs)]}
ledger=HERE/'legacy-test-fixture-manifest.json'
if args.check:assert dest.read_bytes()==expected and json.loads(ledger.read_text('utf8'))==manifest
else:
    if not dest.exists():shutil.copyfile(folder/'AudioFixture.as',dest)
    assert dest.read_bytes()[:3]==expected[:3];dest.write_bytes(expected)
    ledger.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'ok':True,'actualConsumers':len(batches),'cases':manifest['cases']}))
