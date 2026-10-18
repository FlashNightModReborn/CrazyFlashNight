from pathlib import Path
import hashlib, json, re, zipfile
import xml.etree.ElementTree as E

R = Path.cwd();O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
shared = 'data/enemy_properties/CF6重制敌人.xml'
sha = lambda data: hashlib.sha256(data).hexdigest()
with zipfile.ZipFile(O / 'before-r19-output-distribution.zip') as z: before = z.read(shared)
after = (R / shared).read_bytes()
allowed = {'敌人-CF6老头人形', '敌人-CF6老头机器人'}
old = E.fromstring(before);new = E.fromstring(after)
assert [node.tag for node in old] == [node.tag for node in new]
changed = [a.tag for a, b in zip(old, new) if E.tostring(a) != E.tostring(b)]
assert set(changed) == {'敌人-CF6老头机器人'}
def unrelated(data):
    text = data.decode('utf-8-sig').replace('\r\n', '\n')
    for tag in sorted(allowed):
        text, count = re.subn(r'<' + re.escape(tag) + r'>.*?</' + re.escape(tag) + r'>', '', text, flags=re.S)
        assert count == 1
    return text.encode('utf8')
assert unrelated(before) == unrelated(after)
head = json.loads((P / 'history/head-c4-integration-awake/strength-summary.json').read_text('utf8'))
bindings = head['sourceBindings']
for row in bindings:
    assert sha(before if row['path'] == shared else (R / row['path']).read_bytes()) == row['sha256']
result = {'qualified': True, 'beforeSha256': sha(before), 'afterSha256': sha(after), 'path': shared,
          'onlyChangedEnemyNodes': changed, 'unchangedNonElderNormalizedSha256': sha(unrelated(after)),
          'normalization': 'UTF-8 BOM removal and CRLF to LF; remove only the two named Elder element blocks, then require exact remaining text equality.',
          'headIntegration': 'history/head-c4-integration-awake', 'headBindings': len(bindings),
          'otherHeadBindingsUnchanged': True, 'headNodeAndAllOtherEnemyNodesUnchanged': True,
          'originalArchive': 'before-r19-output-distribution.zip',
          'boundary': 'Source impact proof for an Elder-only shared XML edit; no new Head battle execution is claimed.'}
with (O / 'r19-scoped-data-impact.json').open('x', encoding='utf8') as f: json.dump(result, f, ensure_ascii=False, indent=2)
print(json.dumps(result, ensure_ascii=False))
