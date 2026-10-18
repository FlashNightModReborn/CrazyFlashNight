"""Read-only final generated-input/resource checks, separate from live acceptance."""
from pathlib import Path
import datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
out = O / 'final-static-gates'
out.mkdir(exist_ok=False)
load = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
identity = load(O / 'arena-r22-full/input-identity.json')
paths = sorted({r['path'] for r in load(O / 'before-r22-high-level-budget-index.json')} |
               {r['path'] for r in identity['sourceBindings']})
before = [{'path': p, 'sha256': sha(R / p)} for p in paths]
checks = []
for family in ['elder', 'headbot', 'bladebot']:
    for script, args in [('build.py', ['--check']), ('balance.py', []), ('verify.py', [])]:
        checks.append((family + '-' + script.removesuffix('.py'),
                       ['python', '-X', 'utf8', '-B', 'tools/cf6-' + family + '-assets/' + script] + args))
checks += [('arena-catalog', ['node', 'tools/derive-arena-unit-catalog.js', '--check']),
           ('bom', ['node', 'tools/check-bom.js', '--file', 'tools/cf6-elder-assets/ElderAI.as',
                    '--file', 'tools/cf6-elder-assets/ElderTransform.as',
                    '--file', 'tools/cf6-headbot-assets/HeadbotAI.as']),
           ('agent-entry', ['node', 'tools/test-agent-entry-contract.js'])]
records = []
for name, command in checks:
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (out / (name + '.log')).open('xb') as f:
        result = subprocess.run(command, stdout=f, stderr=subprocess.STDOUT)
    records.append({'name': name, 'command': command, 'exitCode': result.returncode,
                    'startedAtUtc': started, 'completedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    'logSha256': sha(out / (name + '.log'))})
    print(json.dumps({'gate': name, 'exitCode': result.returncode}), flush=True)
after = [{'path': p, 'sha256': sha(R / p)} for p in paths]
report = {'ok': all(r['exitCode'] == 0 for r in records) and before == after,
          'checks': records, 'sourceUnchanged': before == after, 'sourceBindings': before,
          'boundary': 'Generated inputs, canonical formulas, source BOM and resource identity only. Live candidate fights, native execution, human experience and formal runtime deployment remain separate.'}
with (out / 'summary.json').open('x', encoding='utf8') as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
assert report['ok'], 'Preserve every failed gate and inspect it before any repair'
