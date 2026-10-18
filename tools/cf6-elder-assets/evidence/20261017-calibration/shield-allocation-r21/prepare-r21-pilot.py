from pathlib import Path
import datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
assert load(O / 'native-cleanup-after-r21.json')['ok']
assert load(O / 'r21-unaffected-native-suites.json')['qualified']
for folder in ['native-r21-fixture-repair/elder-asset', 'native-r21-shield-allocation/audio', 'native-r21-shield-allocation/player-aim', 'native-r21-shield-allocation/elder-render']:
    result = load(O / folder / 'result.json')
    assert result['exitCode'] == 0 and result['bindingsUnchanged']
render = load(O / 'r21-native-render-verification.json')
assert render['ok'] and render['images'] == 12
assert render['currentElderSwfSha256'] == hashlib.sha256((R / 'flashswf/arts/new/Codex老头素材.swf').read_bytes()).hexdigest()
cfg = load(O / 'arena-r20-pilot-config.json')
cfg.update(experimentId='cf6-cal-r21-pilot-20261018', outputDirectory=str(O / 'arena-r21-pilot'), repeat=1)
with (O / 'arena-r21-pilot-config.json').open('x', encoding='utf8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
subprocess.run(['node', 'tools/cf6-elder-assets/arena-plan.js', str(O / 'arena-r21-pilot-config.json')], check=True)
plan = load(O / 'arena-r21-pilot/experiment-plan.json')
assert len(plan['groups']) == 6 and len(plan['workers']) == 1
assert all(g['mode'] == 'serial' and len(g['jobs']) == 1 and g['jobs'][0]['batchTimeoutMs'] == 900000 for g in plan['groups'])
with (O / 'arena-r21-pilot/preregistered-purpose.json').open('x', encoding='utf8') as f:
    json.dump({'registeredAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'purpose': 'Redistribute output through the unchanged canonical formula: slam multiplier 8 to 18, attack multiplier flag 6.875, actual level 30/60/99 attack 813/1184/1666. Normal/heavy written powers remain unchanged, so actual wave output falls about 36 percent while slam rises about 45 percent. Independent capacity budgets: melee 0.5, beam 0.2, reactive 0.75 relative to R19; shield attack normalization 55/43 keeps hardness within 1.4 percent of R20. Keep approved 750 range, visible/collision geometry, durations, HP/DEF, human form and other units unchanged.',
               'expectedRows': 12, 'levels': [30, 60, 99], 'rivals': [78, 361], 'perSideRepeat': 1,
               'fullMatrix': False, 'fullMatrixGroupMeanAndMedianNetHpLoss': [.5, .8],
               'winsAllowed': 0, 'timeoutsAllowed': 0, 'ownPhaseSpawnsPerFight': 1,
               'netHpMethod': 'Fixed full opponent chain including unspawned Beast successor; every result retained.',
               'maximumConcurrentGames': 1, 'displayLog': str(O / 'display-qualified-20261018-r7/display-state.jsonl'),
               'perShardWallLimitMs': 900000, 'perFightTimeoutFrames': 5400,
               'formalPromotion': False}, f, ensure_ascii=False, indent=2)
print(json.dumps({'experiment': cfg['experimentId'], 'rows': 12, 'acceptanceMatrix': False}))
