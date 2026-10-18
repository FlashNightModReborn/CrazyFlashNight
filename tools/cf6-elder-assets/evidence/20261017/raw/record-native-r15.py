from evidence_utils import *
import re

assert sha(ROOT/'flashswf/arts/new/Codex老头素材.swf')==sha(TMP/'publish-r15.swf')
assert read(TMP/'publish-r15-errors.txt').decode('utf-8-sig').strip()=='0 个错误, 0 个警告'
proof={}
for label,domain,suite,expected in [('behavior','cf6-elder','Cf6ElderAssetTest',690),('render-probe','cf6-elder-render','Cf6ElderRenderTest',16)]:
    raw=read(TMP/(label+'-r15-trace.txt')).decode('utf-8-sig')
    starts=re.findall(r'FocusedTestRunId '+domain+r' Start: ([a-f0-9]+)',raw)
    ends=re.findall(r'FocusedTestRunId '+domain+r' Complete: ([a-f0-9]+)',raw)
    assert len(starts)==1 and starts==ends and '[TEST_FAIL]' not in raw
    assert re.findall(suite+r': (\d+) passed, (\d+) failed',raw)==[(str(expected),'0')]
    assert read(TMP/(label+'-r15-errors.txt')).decode('utf-8-sig').strip()=='0 个错误, 0 个警告'
    proof[label]={'runId':starts[0],'passed':expected,'failed':0,'traceSha256':sha(TMP/(label+'-r15-trace.txt'))}
assert len(js(TMP/'r15-art-equivalence.json')['files'])==85
bindings=[]
for path in ['flashswf/arts/new/Codex老头素材.swf','tools/cf6-elder-assets/ElderAI.as',
    'tools/cf6-elder-assets/ElderTransform.as','tools/cf6-elder-assets/native-manifest.json',
    'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as']:
    bindings.append({'path':path,'sha256':sha(ROOT/path)})
jput(TMP/'native-r15-evidence.json',{'revision':'r15','proof':proof,'sourceBindings':bindings,
    'swfBytes':len(read(TMP/'publish-r15.swf')),'timelineCases':34,'phaseCases':13,'drawPoints':6,'equivalentGraphicsXmlFiles':85,
    'graphicsProof':'r15-art-equivalence.json','imagesRemainR6':True,
    'beforeChange':{'runId':'cdf3712b8cbf4474b74e01fffb35916b','passed':684,'failed':6,'scope':'Added beam-recovery behavior intentionally fails in old R12 SWF; old suite checks and damage calculation remain passing'}})
print(json.dumps(proof,ensure_ascii=False))
