from pathlib import Path
import hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
paths = ['launcher/src/Guardian/WorldCompositor/WorldCompositorController.cs',
         'launcher/contracts/ragchat.v1.json', 'scripts/通信/通信_aka_Agent联动.as']
items = []
for path in paths:
    oid = subprocess.check_output(['git', 'rev-parse', ':' + path]).decode().strip()
    ordinary = subprocess.check_output(['git', 'cat-file', '--filters', ':' + path])
    items.append((path, oid, ordinary))
data = subprocess.check_output(['git', 'cat-file', '--batch', '--filters', '-Z'],
                               input=('\0'.join(oid + ' ' + path for path, oid, _ in items) + '\0').encode('utf8'))
position = 0
rows = []
for path, oid, ordinary in items:
    end = data.index(b'\0', position)
    header = data[position:end].decode().split()
    assert header[:2] == [oid, 'blob'], header
    original_size = int(header[2])
    start = end + 1
    assert b'\0' not in ordinary
    finish = data.index(b'\0', start)
    actual = data[start:finish]
    assert actual == ordinary, path
    rows.append({'path': path, 'originalHeaderBytes': original_size, 'filteredBytes': len(actual), 'sha256': hashlib.sha256(actual).hexdigest(),
                 'matchesIndividualFilters': True})
    position = finish + 1
assert position == len(data)
report = {'ok': True, 'files': rows,
          'boundary': 'The installed Git filtered batch interface is compared byte-for-byte with individual git cat-file --filters calls, including Unicode paths. Both invoke real Git checkout filters; no manual line-ending conversion is substituted.'}
with (O / 'git-batch-filter-equivalence.json').open('x', encoding='utf8') as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print(json.dumps({'ok': True, 'matchedIndividualCalls': len(rows)}))
