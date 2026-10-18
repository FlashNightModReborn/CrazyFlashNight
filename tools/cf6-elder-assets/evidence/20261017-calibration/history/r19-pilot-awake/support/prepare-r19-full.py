from pathlib import Path
import argparse, datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
args = argparse.ArgumentParser()
args.add_argument('--display-log', type=Path, required=True)
a = args.parse_args()
load = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
pilot = P / 'history/r19-pilot-awake'
analysis = load(pilot / 'phase-aware-summary.json')
assert len(analysis['rows']) == 12 and len(analysis['groups']) == 6
assert all(g['n'] == 2 and g['meetsGroupTarget'] and not g['wins'] and not g['timeouts'] for g in analysis['groups'])
assert load(pilot / 'display-assessment.json')['qualified']
for row in load(pilot / 'plan/input-identity.json')['sourceBindings']:
    assert sha(R / row['path']) == row['sha256'], row['path']
cfg = load(O / 'arena-r19-pilot-config.json')
cfg.update(experimentId='cf6-cal-r19-full-20261018', outputDirectory=str(O / 'arena-r19-full-base'), repeat=3)
with (O / 'arena-r19-full-config.json').open('x', encoding='utf8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
subprocess.run(['node', 'tools/cf6-elder-assets/arena-plan.js', str(O / 'arena-r19-full-config.json')], check=True)
subprocess.run(['node', str(O / 'split-full-repeat-plan.js'), str(O / 'arena-r19-full-base'), str(O / 'arena-r19-full')], check=True)
with (O / 'arena-r19-full/preregistered-purpose.json').open('x', encoding='utf8') as f:
    json.dump({'registeredAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'purpose': 'Fresh complete thirty-six-fight acceptance matrix for R19 under merged C5 loader and current registrations; keep the twelve exploratory observations separate.',
               'expectedRows': 36, 'levels': [30, 60, 99], 'rivals': [78, 361], 'perSideRepeat': 3,
               'fullMatrixGroupMeanAndMedianNetHpLoss': [.5, .8], 'winsAllowed': 0, 'timeoutsAllowed': 0,
               'ownPhaseSpawnsPerFight': 1, 'netHpMethod': 'Fixed full chain including unspawned beast successor; all rows retained.',
               'exploratorySummarySha256': sha(pilot / 'phase-aware-summary.json'),
               'displayLog': str(a.display_log.resolve()), 'nativeCandidate': 'cf6-transition-paint-r4',
               'maximumConcurrentGames': 1, 'groups': 18, 'rowsPerGroup': 2,
               'perShardWallLimitMs': 900000, 'perFightTimeoutFrames': 5400, 'formalPromotion': False},
              f, ensure_ascii=False, indent=2)
print(json.dumps({'experiment': cfg['experimentId'], 'rows': 36, 'singleWorker': True, 'acceptanceMatrix': True}))
