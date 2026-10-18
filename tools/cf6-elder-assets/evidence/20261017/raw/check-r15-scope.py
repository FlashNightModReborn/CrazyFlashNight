from evidence_utils import *
import xml.etree.ElementTree as ET

bindings=js(TMP/'matrix-r14/input-identity.json')['sourceBindings']
changed=[r['path'] for r in bindings if sha(ROOT/r['path'])!=r['sha256']]
assert set(changed)=={'flashswf/arts/new/Codex老头素材.swf','tools/cf6-elder-assets/ElderAI.as','tools/cf6-elder-assets/native-manifest.json'}
old=read(TMP/'r14-before-ai/tools/cf6-elder-assets/ElderAI.as')
new=read(ROOT/'tools/cf6-elder-assets/ElderAI.as')
assert new==old.replace(b'if(owner.ownsRigid && frame>owner.spec.hits[owner.spec.hits.length-1])',
    b'if(owner.ownsRigid && owner.action!="beam" && frame>owner.spec.hits[owner.spec.hits.length-1])')
archive=TMP/'r14-frozen-inputs/frozen-inputs.zip'
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
jput(TMP/'r15-art-equivalence.json',{'scope':'R12/R14 versus R15 XML after removing ActionScript; all artwork and authored animation unchanged. R6 images retain their original provenance.',
    'baselineArchiveSha256':sha(archive),'currentSwfSha256':sha(ROOT/'flashswf/arts/new/Codex老头素材.swf'),'files':rows})
jput(TMP/'r15-integration-scope.json',{'changedBoundInputs':changed,'unchangedBoundInputs':len(bindings)-len(changed),
    'onlyProductionBehaviorChange':'Beam rigidity through complete authored animation; knockback brace still ends after contact frame 29. All damage and balance inputs unchanged.',
    'graphicsXmlFilesEqual':len(rows),'headAndBladeSwfsUnchanged':True})
print(json.dumps({'changedBoundInputs':changed,'equalGraphics':len(rows)},ensure_ascii=False))
