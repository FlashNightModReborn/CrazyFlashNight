from evidence_utils import *
import re

assert sha(ROOT/'flashswf/arts/new/Codex老头素材.swf')==sha(TMP/'publish-r12.swf')
assert read(TMP/'publish-r12-errors.txt').decode('utf-8-sig').strip()=='0 个错误, 0 个警告'
proof={}
for label,domain,suite,expected in [('behavior','cf6-elder','Cf6ElderAssetTest',680),('render-probe','cf6-elder-render','Cf6ElderRenderTest',16)]:
    raw=read(TMP/(label+'-r12-trace.txt')).decode('utf-8-sig')
    starts=re.findall(r'FocusedTestRunId '+domain+r' Start: ([a-f0-9]+)',raw)
    ends=re.findall(r'FocusedTestRunId '+domain+r' Complete: ([a-f0-9]+)',raw)
    assert len(starts)==1 and starts==ends and '[TEST_FAIL]' not in raw
    results=re.findall(suite+r': (\d+) passed, (\d+) failed',raw)
    assert results==[(str(expected),'0')]
    assert read(TMP/(label+'-r12-errors.txt')).decode('utf-8-sig').strip()=='0 个错误, 0 个警告'
    proof[label]={'runId':starts[0],'passed':expected,'failed':0,'traceSha256':sha(TMP/(label+'-r12-trace.txt'))}
assert len(js(TMP/'r12-art-equivalence.json')['files'])==85
bindings=[]
for path in ['flashswf/arts/new/Codex老头素材.swf','tools/cf6-elder-assets/ElderAI.as',
    'tools/cf6-elder-assets/ElderTransform.as','tools/cf6-elder-assets/native-manifest.json',
    'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as']:
    bindings.append({'path':path,'sha256':sha(ROOT/path)})
jput(TMP/'native-r12-evidence.json',{'revision':'r12','proof':proof,'sourceBindings':bindings,
    'swfBytes':len(read(TMP/'publish-r12.swf')),'timelineCases':34,'phaseCases':13,'drawPoints':6,'equivalentGraphicsXmlFiles':85,
    'graphicsProof':'r12-art-equivalence.json','imagesRemainR6':True})
print(json.dumps(proof,ensure_ascii=False))
