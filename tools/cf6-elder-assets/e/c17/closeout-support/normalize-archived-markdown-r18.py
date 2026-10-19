"""Keep historical Markdown source verbatim as inert text, with lossless mapping."""
from pathlib import Path
import argparse, datetime, hashlib, importlib.util, json, re

args = argparse.ArgumentParser()
args.add_argument('--label', required=True)
a = args.parse_args()
assert re.fullmatch(r'[a-z0-9-]+', a.label)
R = Path.cwd().resolve()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = (R / 'tools/cf6-elder-assets/evidence/20261017-calibration').resolve()
assert not (P / 'integrity.json').exists()
state_path = O / 'evidence-history-assembly.json'
raw_state = state_path.read_bytes()
state = json.loads(raw_state)
backup = O / ('before-archived-markdown-format-' + a.label + '.json')
receipt_path = P / 'closeout-support' / ('archived-markdown-format-' + a.label + '.json')
assert not backup.exists() and not receipt_path.exists()
sha = lambda data: hashlib.sha256(data).hexdigest()
changes = []
for row in state['mapping']:
    for part in row['parts']:
        if not part['path'].endswith('.md'): continue
        source = (P / part['path']).resolve()
        assert source.is_relative_to(P)
        assert re.fullmatch(r'(?:README-before-[^/]+|before-r\d+-testing-details)\.md', source.name), source
        assert row['encoding'] == 'identity' and len(row['parts']) == 1
        data = source.read_bytes()
        assert len(data) == part['bytes'] == row['originalBytes']
        assert sha(data) == part['sha256'] == row['originalSha256']
        target = source.with_name(source.name + '.txt').resolve()
        assert target.is_relative_to(P) and not target.exists()
        changes.append({'source': source, 'target': target, 'part': part,
                        'oldPath': part['path'], 'newPath': target.relative_to(P).as_posix(),
                        'bytes': len(data), 'sha256': sha(data)})
assert changes
with backup.open('xb') as f: f.write(raw_state)
for change in changes:
    change['source'].rename(change['target'])
    assert sha(change['target'].read_bytes()) == change['sha256']
    change['part']['path'] = change['newPath']
receipt = {'timeUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
           'files': [{k: c[k] for k in ['oldPath', 'newPath', 'bytes', 'sha256']} for c in changes],
           'previousAssemblyStateSha256': sha(raw_state), 'originalFileBytesChanged': False,
           'boundary': 'These are verbatim historical source snapshots, not current navigation documents. Their original relative links retain their original context in the source archive. Only the public copy filename and its lossless mapping changed; canonical documentation and original source bytes are untouched.'}
receipt_path.parent.mkdir(parents=True, exist_ok=True)
with receipt_path.open('x', encoding='utf8') as f:
    json.dump(receipt, f, ensure_ascii=False, indent=2)
    f.write('\n')
spec = importlib.util.spec_from_file_location('evidence', O.parent / 'cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
package = u.Package(P)
package.mapping = state['mapping']
package.copy(Path(__file__), 'closeout-support/normalize-archived-markdown-' + a.label + '.py')
state['mapping'] = package.mapping
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'renamedCopies': len(changes), 'originalBytesUnchanged': True,
                  'receipt': receipt_path.relative_to(R).as_posix()}))
