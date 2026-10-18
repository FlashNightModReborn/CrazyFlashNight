from pathlib import Path
import datetime, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
assert load(O / 'native-cleanup-after-r16.json')['ok']
for name in ['elder-asset', 'player-aim']:
    result = load(O / 'native-r16-decay-adapter-repair' / name / 'result.json')
    assert result['exitCode'] == 0 and result['bindingsUnchanged']
assert load(O / 'native-r16-reactive-shield/audio/result.json')['exitCode'] == 0
cfg = load(O / 'arena-r14-full-config.json')
cfg.update(experimentId='cf6-cal-r16-pilot-20261018', outputDirectory=str(O / 'arena-r16-pilot'), repeat=1)
with (O / 'arena-r16-pilot-config.json').open('x', encoding='utf8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
subprocess.run(['node', 'tools/cf6-elder-assets/arena-plan.js', str(O / 'arena-r16-pilot-config.json')], check=True)
plan = load(O / 'arena-r16-pilot/experiment-plan.json')
assert len(plan['groups']) == 6 and len(plan['workers']) == 1
for group in plan['groups']:
    assert group['mode'] == 'serial' and len(group['jobs']) == 1
    assert group['jobs'][0]['batchTimeoutMs'] == 900000
with (O / 'arena-r16-pilot/preregistered-purpose.json').open('x', encoding='utf8') as f:
    json.dump({'registeredAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'purpose': 'Exploratory five-percent HP-loss trigger and periodic decaying-shield pilot on the merged melee-input loader; does not replace the full thirty-six-fight acceptance matrix.',
               'expectedRows': 12, 'levels': [30, 60, 99], 'rivals': [78, 361], 'perSideRepeat': 1,
               'fullMatrixGroupMeanAndMedianNetHpLoss': [.5, .8], 'winsAllowed': 0, 'timeoutsAllowed': 0,
               'ownPhaseSpawnsPerFight': 1, 'netHpMethod': 'Fixed full chain including unspawned beast successor; all rows retained.',
               'executionQualificationRequired': True, 'continuousObservedDisplayRequired': True,
               'displayLog': str(O / 'display-qualified-20261018-r4/display-state.jsonl'),
               'nativeCandidate': 'cf6-transition-paint-r4', 'maximumConcurrentGames': 1,
               'perShardWallLimitMs': 900000, 'perFightTimeoutFrames': 5400, 'formalPromotion': False},
              f, ensure_ascii=False, indent=2)
print(json.dumps({'experiment': cfg['experimentId'], 'rows': 12, 'singleWorker': True, 'acceptanceMatrix': False}))
