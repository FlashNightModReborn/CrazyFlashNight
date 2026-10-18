from pathlib import Path
import datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
names = ['tools/cf6-elder-assets/README.md', 'tools/cf6-headbot-assets/README.md',
         'tools/cf6-audio/README.md', 'agentsDoc/testing-details.md', 'launcher/README.md']
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
before = [{'path': name, 'sha256': sha(R / name)} for name in names]
with (O / 'final-documentation-check.log').open('xb') as f:
    result = subprocess.run(['node', 'tools/validate-doc-governance.js'], stdout=f, stderr=subprocess.STDOUT)
after = [{'path': name, 'sha256': sha(R / name)} for name in names]
report = {'ok': result.returncode == 0 and before == after, 'exitCode': result.returncode,
          'sourceUnchanged': before == after, 'documents': before,
          'logSha256': sha(O / 'final-documentation-check.log'),
          'completedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'boundary': 'The canonical documentation governance check is preserved with all warnings. Success does not imply that historical repository link debt is zero.'}
with (O / 'final-documentation-check.json').open('x', encoding='utf8') as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print(json.dumps({'ok': report['ok'], 'exitCode': result.returncode}))
assert report['ok']
