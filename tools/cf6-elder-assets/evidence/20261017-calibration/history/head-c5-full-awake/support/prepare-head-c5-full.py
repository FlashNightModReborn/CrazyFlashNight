"""Freeze the current eighteen-fight matrix only after Elder tuning is accepted."""
from pathlib import Path
import argparse, datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
args = argparse.ArgumentParser()
args.add_argument('--elder-label', required=True)
args.add_argument('--display-log', type=Path, required=True)
a = args.parse_args()
load = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert '/' not in a.elder_label and '\\' not in a.elder_label
elder_base = P / 'history' / a.elder_label
elder = load(elder_base / 'acceptance-summary.json')
assert elder['profile'] == 'high-level-beast-near-death-exusiai-net-hp-minority-wins-v2'
assert elder['fullMatrix'] and elder['strengthPassed'] and len(elder['rows']) == 36
assert elder['expectedLevels'] == [60, 80, 100]
assert all(row['candidateUnitId'] == 473 and row['successorUnitId'] == 474 for row in elder['rows'])
assert load(elder_base / 'display-assessment.json')['qualified']
for row in load(elder_base / 'plan/input-identity.json')['sourceBindings']:
    assert sha(R / row['path']) == row['sha256'], row['path']
proof = load(P / 'upstream-base-siege-integration/base-siege-loader-class-scope.json')
assert proof['qualified'] and not proof['removedClasses']
assert sha(R / 'scripts/asLoader.swf') == proof['afterSha256']
for row in proof['sourceBindings']:
    assert sha(R / row['path']) == row['sha256'], row['path']
cfg = load(O / 'arena-head-current-config.json')
cfg.update(experimentId='cf6-cal-head-c5-20261018', outputDirectory=str(O / 'arena-head-c5'), repeat=3)
assert len(cfg['workers']) == 1
with (O / 'arena-head-c5-config.json').open('x', encoding='utf8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
subprocess.run(['node', 'tools/cf6-headbot-assets/arena-plan.js', str(O / 'arena-head-c5-config.json')], check=True)
plan = load(O / 'arena-head-c5/experiment-plan.json')
assert len(plan['groups']) == 3
for group in plan['groups']:
    assert group['mode'] == 'serial' and len(group['jobs']) == 1
    assert group['jobs'][0]['batchTimeoutMs'] == 900000
with (O / 'arena-head-c5/preregistered-purpose.json').open('x', encoding='utf8') as f:
    json.dump({'registeredAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'purpose': 'New complete Headbot matrix under current unit 472 and merged C5 loader, after the final Elder data are accepted. Earlier C3 and C4 fights retain their original identities.',
               'expectedRows': 18, 'levels': [30, 60, 99], 'perSideRepeat': 3,
               'requiredNaturalWins': 18, 'timeoutsAllowed': 0, 'fullMatrix': True,
               'candidateUnitId': 472, 'rivalUnitId': 286,
               'acceptedElderHistory': a.elder_label,
               'acceptedElderSummarySha256': sha(elder_base / 'acceptance-summary.json'),
               'displayLog': str(a.display_log.resolve()),
               'maximumConcurrentGames': 1, 'formalPromotion': False}, f, ensure_ascii=False, indent=2)
print(json.dumps({'experiment': cfg['experimentId'], 'rows': 18, 'candidateUnitId': 472}))
