from pathlib import Path
import hashlib,json,zipfile,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2];TMP=Path(__file__).resolve().parent
def normalized(data):
    if not data.strip():return data
    root=ET.fromstring(data)
    for parent in root.iter():
        for child in list(parent):
            if child.tag.rsplit('}',1)[-1]=='Actionscript':parent.remove(child)
    return ET.tostring(root,encoding='utf-8')
rows=[]
with zipfile.ZipFile(TMP/'baseline-source.zip') as before:
    old=set(before.namelist())
    for owner in ['Codex大头机器人素材','Codex老头素材','Codex大刀机器人素材']:
        prefix='flashswf/arts/new/'+owner+'/'
        unchanged=[];changed=[];added=[];removed=[]
        current={p.relative_to(ROOT).as_posix():p for p in (ROOT/prefix).rglob('*.xml')}
        for name,p in current.items():
            if name not in old:added.append(name);continue
            prior=normalized(before.read(name));now=normalized(p.read_bytes())
            if prior==now:unchanged.append({'path':name,'geometrySha256':hashlib.sha256(now).hexdigest()})
            else:changed.append({'path':name,'beforeGeometrySha256':hashlib.sha256(prior).hexdigest(),'afterGeometrySha256':hashlib.sha256(now).hexdigest()})
        for name in old:
            if name.startswith(prefix) and name.endswith('.xml') and name not in current:removed.append(name)
        rows.append({'owner':owner,'unchangedXml':unchanged,'changedXml':changed,'addedXml':added,'removedXml':removed})
result={'method':'Compare parsed native XFL XML after removing Actionscript nodes only; does not infer runtime performance or human visual acceptance.','owners':rows}
(TMP/'native-graphics-delta.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps([{k:v for k,v in r.items() if k not in ['unchangedXml']}|{'unchangedXmlCount':len(r['unchangedXml'])} for r in rows],ensure_ascii=False))
