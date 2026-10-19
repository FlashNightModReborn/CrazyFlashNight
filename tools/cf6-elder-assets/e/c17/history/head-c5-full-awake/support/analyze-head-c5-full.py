"""Assess every row of the separately collected current Headbot matrix."""
from pathlib import Path
import hashlib, json

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
label = 'head-c5-full-awake'
base = P / 'history' / label
read = lambda p: json.loads(p.read_text('utf-8-sig'))
rows = read(base / 'all-results.json')
display = read(base / 'display-assessment.json')
identity = read(base / 'plan/input-identity.json')
assert len(rows) == 18 and display['qualified']
for binding in identity['sourceBindings']:
    assert hashlib.sha256((R / binding['path']).read_bytes()).hexdigest() == binding['sha256'], binding['path']
groups = {}
seen = set()
detail = []
for row in rows:
    context = row['authorityContext']
    assert context['candidateUnitId'] == 472 and context['rivalUnitId'] == 286
    assert context['stage'] == 7 and context['tier'] == 16 and context['variant'] == 'wave'
    assert context['sourceBindings'] == identity['sourceBindings']
    level, side = context['level'], context['candidateSide']
    assert level in (30, 60, 99) and side in ('blue', 'red')
    assert row['runId'] not in seen and not row['errors']
    seen.add(row['runId'])
    other = 'red' if side == 'blue' else 'blue'
    assert not row['spawnedUnits'] and row['phaseSpawnCount'] == 0
    natural_win = (row['status'] == 'finished' and row['winner'] == side
                   and row[other]['aliveCount'] == 0 and row[side]['aliveCount'] == 1
                   and row[side]['remainHp'] > 0)
    entry = {'runId': row['runId'], 'level': level, 'side': side, 'status': row['status'],
             'naturalWin': natural_win, 'frames': row['frames'],
             'remainingHpRatio': row[side]['remainHp'] / row[side]['startMaxHp']}
    detail.append(entry)
    groups.setdefault(level, []).append(entry)
assert set(groups) == {30, 60, 99}
out = []
for level, members in sorted(groups.items()):
    assert len(members) == 6 and {s: sum(r['side'] == s for r in members) for s in ('blue', 'red')} == {'blue': 3, 'red': 3}
    out.append({'level': level, 'n': 6, 'wins': sum(r['naturalWin'] for r in members),
                'timeouts': sum(r['status'] == 'timeout' for r in members),
                'minimumRemainingHpRatio': min(r['remainingHpRatio'] for r in members),
                'frameRange': [min(r['frames'] for r in members), max(r['frames'] for r in members)]})
result = {'experiment': 'cf6-cal-head-c5-20261018', 'fullMatrix': True,
          'strengthPassed': all(r['naturalWin'] for r in detail),
          'wins': sum(r['naturalWin'] for r in detail),
          'timeouts': sum(r['status'] == 'timeout' for r in detail),
          'groups': out, 'rows': detail, 'sourceBindings': identity['sourceBindings'],
          'runtimeIdentities': display['runtimeIdentities'],
          'rawResultsSha256': hashlib.sha256((base / 'all-results.json').read_bytes()).hexdigest(),
          'boundary': 'These eighteen current-candidate fights verify this matrix only; finite random outcomes do not guarantee every future matchup. Formal promotion and player acceptance are separate.'}
data = (json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode('utf8')
with (base / 'strength-summary.json').open('xb') as f: f.write(data)
with (O / 'head-c5-full-strength-summary.json').open('xb') as f: f.write(data)
state = read(O / 'evidence-history-assembly.json')
run = [run for run in state['runs'] if run['label'] == label]
assert len(run) == 1
run[0]['strengthAccepted'] = result['strengthPassed']
run[0]['selectedForC5Headbot'] = result['strengthPassed']
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({key: result[key] for key in ('experiment', 'fullMatrix', 'strengthPassed', 'wins', 'timeouts', 'groups')}, ensure_ascii=False))
