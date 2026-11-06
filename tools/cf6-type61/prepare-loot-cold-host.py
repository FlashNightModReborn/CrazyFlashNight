"""Dedicated network-mode loopback probe; no global Flash trust changes."""
from pathlib import Path
import hashlib
import json

ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'scripts/TestLoader'
target=ROOT/'scripts/tmp-cf6-loot-cold-host'
outputs={target/p.relative_to(source):p.read_bytes() for p in (source/'LIBRARY').rglob('*') if p.is_file()}
outputs[target/'DOMDocument.xml']=(source/'DOMDocument.xml').read_bytes()
outputs[target/'Cf6SoldierLootColdProbe.xfl']=(source/'TestLoader.xfl').read_bytes()
settings=(source/'PublishSettings.xml').read_text('utf8')
for before,after in (
    ('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>'),
    ('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>'),
    ('<flashFileName>TestLoader.swf</flashFileName>','<flashFileName>../Cf6SoldierLootColdProbe.swf</flashFileName>'),
    ('<UseNetwork>0</UseNetwork>','<UseNetwork>1</UseNetwork>')):
    if settings.count(before)!=1:raise ValueError('Cold probe host template drift: '+before)
    settings=settings.replace(before,after)
outputs[target/'PublishSettings.xml']=settings.encode('utf8')
for path,raw in outputs.items():
    path.parent.mkdir(parents=True,exist_ok=True)
    if not path.is_file() or path.read_bytes()!=raw:path.write_bytes(raw)
manifest={'schema':'cf6-loot-cold-host.v1','scope':'Disposable loopback test host; SharedObject only, no local file reads or global trust edits',
    'files':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()} for p,b in outputs.items()]}
out=ROOT/'tmp/cf6-soldier-enhancement/loot-cold-host.json';out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(manifest,indent=2),encoding='utf8')
print(json.dumps({'host':str(target.relative_to(ROOT)),'files':len(outputs),'useNetwork':True}))
