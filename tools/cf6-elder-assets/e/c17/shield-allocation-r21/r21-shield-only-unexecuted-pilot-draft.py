from pathlib import Path
import datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
assert load(O / 'native-cleanup-after-r21.json')['ok']
for folder in ['elder-asset', 'audio', 'player-aim', 'elder-render']:
    result = load(O / 'native-r21-shield-allocation' / folder / 'result.json')
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
               'purpose': 'Independent shield capacity budgets after the complete R20 pilot: melee 0.5, beam 0.2, reactive 0.75 relative to R19. Keep approved 750 range, visible/collision geometry, all damage multipliers, hardness, durations and numeric HP/ATK/DEF panels unchanged.',
               'expectedRows': 12, 'levels': [30, 60, 99], 'rivals': [78, 361], 'perSideRepeat': 1,
               'fullMatrix': False, 'fullMatrixGroupMeanAndMedianNetHpLoss': [.5, .8],
               'winsAllowed': 0, 'timeoutsAllowed': 0, 'ownPhaseSpawnsPerFight': 1,
               'netHpMethod': 'Fixed full opponent chain including unspawned Beast successor; every result retained.',
               'maximumConcurrentGames': 1, 'displayLog': str(O / 'display-qualified-20261018-r7/display-state.jsonl'),
               'perShardWallLimitMs': 900000, 'perFightTimeoutFrames': 5400,
               'formalPromotion': False}, f, ensure_ascii=False, indent=2)
print(json.dumps({'experiment': cfg['experimentId'], 'rows': 12, 'acceptanceMatrix': False}))
