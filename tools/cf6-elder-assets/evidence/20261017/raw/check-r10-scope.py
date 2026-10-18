from evidence_utils import *
from xml.etree import ElementTree as E
import re

def canonical(element):
    return E.canonicalize(E.tostring(element,encoding='unicode'),strip_text=True)

old={r['path']:r['sha256'] for r in js(TMP/'matrix-r9/input-identity.json')['sourceBindings']}
new={r['path']:r['sha256'] for r in js(TMP/'matrix-r10/input-identity.json')['sourceBindings']}
changed=[p for p in old if old[p]!=new[p]]
assert set(changed)=={'data/enemy_properties/CF6重制敌人.xml','tools/cf6-elder-assets/balance-inputs.json'}
before_bytes=read(TMP/'r9-before-balance/data/enemy_properties/CF6重制敌人.xml')
after_bytes=read(ROOT/'data/enemy_properties/CF6重制敌人.xml')
pattern=r'<敌人-CF6老头机器人>.*?</敌人-CF6老头机器人>'
outside_before,count_before=re.subn(pattern,'<OWN_ROBOT/>',before_bytes.decode('utf8'),flags=re.S)
outside_after,count_after=re.subn(pattern,'<OWN_ROBOT/>',after_bytes.decode('utf8'),flags=re.S)
assert count_before==count_after==1 and outside_before==outside_after,'Unowned XML bytes changed'
a=E.fromstring(before_bytes)
b=E.fromstring(after_bytes)
assert [c.tag for c in a]==[c.tag for c in b]
tags=[c.tag for c in a if canonical(c)!=canonical(b.find(c.tag))]
assert tags==['敌人-CF6老头机器人']
previous=js(TMP/'r9-before-balance/tools/cf6-elder-assets/balance-inputs.json')
current=js(ROOT/'tools/cf6-elder-assets/balance-inputs.json')
assert previous['human']==current['human']
flag_changes=[k for k in previous['robot']['flags'] if previous['robot']['flags'][k]!=current['robot']['flags'][k]]
assert flag_changes==['成长系数']
r={'changedBoundInputs':changed,'changedEnemySubtrees':tags,'changedFormulaFlags':flag_changes,'allUnownedXmlBytesUnchanged':True,
   'unchangedBoundInputs':len(old)-len(changed),'swfChanged':False}
jput(TMP/'r10-integration-scope.json',r)
print(json.dumps(r,ensure_ascii=False))
