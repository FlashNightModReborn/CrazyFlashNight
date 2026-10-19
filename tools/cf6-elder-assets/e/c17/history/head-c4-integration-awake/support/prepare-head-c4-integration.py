from pathlib import Path
import datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
proof = load(R / 'tools/cf6-elder-assets/evidence/20261017-calibration/upstream-melee-integration/melee-loader-class-equivalence.json')
assert proof['allClassActionsByteIdentical'] and proof['existingRootSourceUnchanged']
assert hashlib.sha256((R / 'scripts/asLoader.swf').read_bytes()).hexdigest() == proof['afterSha256']
old = load(O / 'arena-head-current/input-identity.json')
differences = [b['path'] for b in old['sourceBindings']
               if hashlib.sha256((R / b['path']).read_bytes()).hexdigest() != b['sha256']]
assert differences == ['scripts/asLoader.swf'], differences
cfg = load(O / 'arena-head-current-config.json')
cfg.update(experimentId='cf6-cal-head-c4-20261018', outputDirectory=str(O / 'arena-head-c4'), repeat=1)
with (O / 'arena-head-c4-config.json').open('x', encoding='utf8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
subprocess.run(['node', 'tools/cf6-headbot-assets/arena-plan.js', str(O / 'arena-head-c4-config.json')], check=True)
with (O / 'arena-head-c4/preregistered-purpose.json').open('x', encoding='utf8') as f:
    json.dump({'registeredAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'purpose': 'Six bounded integration fights after merging the new cold-weapon input helper. Preserve the earlier eighteen-fight C3 matrix under its actual identity; these are separate C4 observations.',
               'expectedRows': 6, 'levels': [30, 60, 99], 'perSideRepeat': 1,
               'requiredNaturalWins': 6, 'timeoutsAllowed': 0, 'fullMatrix': False,
               'onlyChangedHeadBoundInputSinceFullMatrix': differences,
               'compiledClassEquivalence': '726 class actions byte-identical; existing shared root source unchanged except the newly added helper',
               'displayLog': str(O / 'display-qualified-20261018-r5/display-state.jsonl'),
               'maximumConcurrentGames': 1, 'formalPromotion': False}, f, ensure_ascii=False, indent=2)
print(json.dumps({'experiment': cfg['experimentId'], 'rows': 6, 'onlyChangedBoundInput': differences}))
