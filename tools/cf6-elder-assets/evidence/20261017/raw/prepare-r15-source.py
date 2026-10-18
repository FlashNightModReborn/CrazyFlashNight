from evidence_utils import *
import re, subprocess

raw=read(TMP/'behavior-r15-before-trace.txt').decode('utf-8-sig')
starts=re.findall(r'FocusedTestRunId cf6-elder Start: ([a-f0-9]+)',raw)
ends=re.findall(r'FocusedTestRunId cf6-elder Complete: ([a-f0-9]+)',raw)
assert len(starts)==1 and starts==ends
assert read(TMP/'behavior-r15-before-errors.txt').decode('utf-8-sig').strip()=='0 个错误, 0 个警告'
assert re.findall(r'Cf6ElderAssetTest: (\d+) passed, (\d+) failed',raw)==[('684','6')]
failures=[line for line in raw.splitlines() if '[TEST_FAIL]' in line]
assert len(failures)==6
for label in ['beam recovery retains rigidity but releases displacement brace',
    'production forced impact preserves the committed beam recovery',
    'actual production knockback moves the recovering beam actor']:
    assert sum(label in line for line in failures)==2
assert sha(ROOT/'flashswf/arts/new/Codex老头素材.swf')==sha(TMP/'r14-before-ai/flashswf/arts/new/Codex老头素材.swf')
path=ROOT/'tools/cf6-elder-assets/ElderAI.as'
original=read(TMP/'r14-before-ai/tools/cf6-elder-assets/ElderAI.as')
assert read(path)==original and original.startswith(b'\xef\xbb\xbf')
before=b'if(owner.ownsRigid && frame>owner.spec.hits[owner.spec.hits.length-1])'
after=b'if(owner.ownsRigid && owner.action!="beam" && frame>owner.spec.hits[owner.spec.hits.length-1])'
assert original.count(before)==1
lp(path).write_bytes(original.replace(before,after))
for args in [['--import-approved'],['--check']]:
    subprocess.run(['python','-X','utf8','-B','tools/cf6-elder-assets/build.py',*args],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B','tools/cf6-elder-assets/balance.py'],cwd=ROOT,check=True)
print('R15 production delta: only beam rigidity remains owned through normal animation recovery; post-shot knockback immunity still releases after frame 29.')
