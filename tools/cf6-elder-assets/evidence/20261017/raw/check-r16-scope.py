from evidence_utils import *
from xml.etree import ElementTree as E
import re

old = {row['path']:row['sha256'] for row in js(TMP/'matrix-r15/input-identity.json')['sourceBindings']}
new = {row['path']:row['sha256'] for row in js(TMP/'matrix-r16/input-identity.json')['sourceBindings']}
changed = [path for path in old if old[path] != new[path]]
assert set(changed) == {'data/enemy_properties/CF6重制敌人.xml', 'tools/cf6-elder-assets/balance-inputs.json'}
before = read(TMP/'r15-before-balance/data/enemy_properties/CF6重制敌人.xml')
after = read(ROOT/'data/enemy_properties/CF6重制敌人.xml')
pattern = r'<敌人-CF6老头机器人>.*?</敌人-CF6老头机器人>'
outside_before, count_before = re.subn(pattern, '<OWN_ROBOT/>', before.decode('utf8'), flags=re.S)
outside_after, count_after = re.subn(pattern, '<OWN_ROBOT/>', after.decode('utf8'), flags=re.S)
assert count_before == count_after == 1 and outside_before == outside_after, 'Unowned XML bytes changed'
a = E.fromstring(before); b = E.fromstring(after)
canonical = lambda element: E.canonicalize(E.tostring(element, encoding='unicode'), strip_text=True)
assert [c.tag for c in a] == [c.tag for c in b]
tags = [c.tag for c in a if canonical(c) != canonical(b.find(c.tag))]
assert tags == ['敌人-CF6老头机器人']
previous = js(TMP/'r15-before-balance/tools/cf6-elder-assets/balance-inputs.json')
current = js(ROOT/'tools/cf6-elder-assets/balance-inputs.json')
assert previous['human'] == current['human']
flag_changes = [key for key in previous['robot']['flags'] if previous['robot']['flags'][key] != current['robot']['flags'][key]]
assert flag_changes == ['成长系数']
assert previous['robot']['flags']['成长系数'] == 1 and current['robot']['flags']['成长系数'] == .9
old_generator = read(TMP/'r15-before-balance/tools/cf6-elder-assets/balance.py')
new_generator = read(ROOT/'tools/cf6-elder-assets/balance.py')
assert old_generator.replace(b"'growth':1,'attackBias':2,'defenseBias':34}", b"'growth':0.9,'attackBias':2,'defenseBias':34}") == new_generator
result = {'changedBoundInputs':changed, 'changedEnemySubtrees':tags, 'changedFormulaFlags':flag_changes,
          'allUnownedXmlBytesUnchanged':True, 'unchangedBoundInputs':len(old)-len(changed), 'swfChanged':False}
jput(TMP/'r16-integration-scope.json', result)
print(json.dumps(result, ensure_ascii=False))
