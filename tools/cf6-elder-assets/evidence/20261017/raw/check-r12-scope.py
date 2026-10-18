from evidence_utils import *
import xml.etree.ElementTree as ET

changed=[]
for row in js(TMP/'matrix-r11/input-identity.json')['sourceBindings']:
    if sha(ROOT/row['path'])!=row['sha256']:changed.append(row['path'])
assert set(changed)=={'flashswf/arts/new/Codex老头素材.swf','tools/cf6-elder-assets/ElderAI.as','tools/cf6-elder-assets/native-manifest.json'}
old=read(TMP/'r11-before-ai/tools/cf6-elder-assets/ElderAI.as')
new=read(ROOT/'tools/cf6-elder-assets/ElderAI.as')
assert new==old.replace(b'closeRange:elderForm=="human"?175:150',b'closeRange:elderForm=="human"?175:190')
archive=TMP/'r11-frozen-inputs/frozen-inputs.zip'
def graphics(data):
    if not data.strip():return data
    root=ET.fromstring(data)
    for parent in root.iter():
        for child in list(parent):
            if child.tag.endswith('}Actionscript'):parent.remove(child)
    return ET.canonicalize(ET.tostring(root,encoding='unicode'),strip_text=True).encode('utf8')
rows=[]
with zipfile.ZipFile(lp(archive)) as zipped:
    paths=[p for p in zipped.namelist() if p.startswith('flashswf/arts/new/Codex老头素材/') and p.endswith('.xml')]
    for path in paths:
        before=graphics(zipped.read(path));after=graphics(read(ROOT/path))
        assert before==after,'Graphic source drift: '+path
        rows.append({'path':path,'sha256WithoutActionscript':digest(after)})
assert len(rows)==85
jput(TMP/'r12-art-equivalence.json',{'scope':'R7/R11 versus R12 canonical XFL XML after removing ActionScript; no artwork or animation changes. R6 images retain their original provenance.',
    'baselineArchiveSha256':sha(archive),'currentSwfSha256':sha(ROOT/'flashswf/arts/new/Codex老头素材.swf'),'files':rows})
jput(TMP/'r12-integration-scope.json',{'changedBoundInputs':changed,'unchangedBoundInputs':len(js(TMP/'matrix-r11/input-identity.json')['sourceBindings'])-len(changed),
    'onlyProductionBehaviorChange':'Robot kick approach reach 150 to 190; all damage and balance inputs unchanged',
    'graphicsXmlFilesEqual':len(rows),'headAndBladeSwfsUnchanged':True})
print(json.dumps({'changedBoundInputs':changed,'equalGraphics':len(rows)},ensure_ascii=False))
