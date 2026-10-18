from evidence_utils import *
from xml.etree import ElementTree as E

def canonical(element):
    return E.canonicalize(E.tostring(element,encoding='unicode'),strip_text=True)

old={r['path']:r['sha256'] for r in js(TMP/'pilot-r8/input-identity.json')['sourceBindings']}
new={r['path']:r['sha256'] for r in js(TMP/'matrix-r9/input-identity.json')['sourceBindings']}
changed=[p for p in old if old[p]!=new[p]]
assert set(changed)=={'data/enemy_properties/CF6重制敌人.xml','tools/cf6-elder-assets/balance-inputs.json'}
a=E.fromstring(read(TMP/'r8-before-balance/data/enemy_properties/CF6重制敌人.xml'))
b=E.fromstring(read(ROOT/'data/enemy_properties/CF6重制敌人.xml'))
assert [c.tag for c in a]==[c.tag for c in b]
tags=[c.tag for c in a if canonical(c)!=canonical(b.find(c.tag))]
assert tags==['敌人-CF6老头机器人']
previous=js(TMP/'r8-before-balance/tools/cf6-elder-assets/balance-inputs.json')
current=js(ROOT/'tools/cf6-elder-assets/balance-inputs.json')
assert previous['human']==current['human']
flag_changes=[k for k in previous['robot']['flags'] if previous['robot']['flags'][k]!=current['robot']['flags'][k]]
assert flag_changes==['高防低血系数']
r={'changedBoundInputs':changed,'changedEnemySubtrees':tags,'changedFormulaFlags':flag_changes,
   'unchangedBoundInputs':len(old)-len(changed),'swfChanged':False}
jput(TMP/'r9-integration-scope.json',r)
print(json.dumps(r,ensure_ascii=False))
