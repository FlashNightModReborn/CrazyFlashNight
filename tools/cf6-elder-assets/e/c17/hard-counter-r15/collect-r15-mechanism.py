from pathlib import Path
import importlib.util, json, re

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
assert not (P / 'integrity.json').exists()
for name in ['elder-asset', 'audio', 'player-aim']:
    result = u.js(O / 'native-r15-hard-counter' / name / 'result.json')
    assert result['exitCode'] == 0 and result['bindingsUnchanged']
expected = {'elder-asset': [('Cf6ElderAssetTest', 906), ('Cf6ElderCombatEffectsTest', 92), ('Cf6RobotCombatTest elder', 45)],
            'audio': [('Cf6AudioTest', 340)], 'player-aim': [('Cf6PlayerAimTest', 1023)]}
for name, cases in expected.items():
    trace = u.read(O / 'native-r15-hard-counter' / name / 'flashlog.txt').decode('utf-8-sig')
    for label, count in cases:
        assert re.search(re.escape(label) + r': ' + str(count) + r' passed, 0 failed', trace), (name, label)
assert u.js(O / 'native-cleanup-after-r15.json')['ok']
paths = ['tools/cf6-elder-assets/' + name for name in ['ElderAI.as', 'build.py', 'balance.py', 'native-manifest.json', 'arena-plan.js', 'README.md']]
paths += ['scripts/类定义/org/flashNight/arki/unit/Action/Melee/' + name for name in ['Cf6ElderCombatEffectsTest.as', 'Cf6ElderAssetTest.as', 'Cf6PlayerAimTest.as']]
paths += ['scripts/run-cf6-elder-asset-tests.ps1', 'data/enemy_properties/CF6重制敌人.xml']
package.freeze(paths, 'hard-counter-r15/source.zip')
for source, target in [('build-r15-elder', 'publish'), ('native-r15-hard-counter', 'native-tests'), ('native-cleanup-after-r15-receipts', 'native-cleanup')]:
    package.tree(O / source, 'hard-counter-r15/' + target)
for name in ['before-r15-hard-counter.zip', 'before-r15-hard-counter-index.json', 'before-r15-testing-details.md', 'before-r15-testing-details-index.json',
             'native-cleanup-after-r15.json', 'elder-r15-image-equivalence.json', 'verify-elder-r15.log', 'balance-r15-elder-check.log',
             'regeneration-r15-elder.log', 'worker-sync-r17.json', 'prepare-r15-hard-counter.py', 'prepare-r15-pilot.py', 'run-r15-pilot.ps1', 'collect-r15-mechanism.py']:
    package.copy(O / name, 'hard-counter-r15/' + name)
u.jput(P / 'hard-counter-r15/summary.json', {
    'status': 'native_verified; exploratory_pilot_pending',
    'slamShield': {'capacityRatio': .03, 'strengthRatio': 10, 'frames': 120},
    'observedLevel30Fixture': {'attack': 1033, 'maximumHp': 15318, 'shieldStrength': 10330, 'shieldCapacity': 459.54, 'rageHeavyRawPower': 8925},
    'beamShieldAccounting': 'Read actual capacity once at replacement, cancellation or form end; expiry retains remaining capacity. No shield or damage writes.',
    'kickShieldUnchanged': True, 'beamShieldLifecycleUnchanged': True, 'actionPowersAndFormulaPanelUnchanged': True,
    'native': {'assetPassed': 906, 'effectsPassed': 92, 'robotPassed': 45, 'totalPassed': 1043,
               'timelineCases': 46, 'phaseCases': 13, 'audioPassed': 340, 'audioRoutes': 81, 'playerAimPassed': 1023, 'playerAimCases': 74},
    'candidateSwfSha256': u.sha(R / 'flashswf/arts/new/Codex老头素材.swf'),
    'exploratoryPilot': 'cf6-cal-r15-pilot-20261018', 'exploratoryPilotRows': 12,
    'boundary': 'Native fixtures verify mechanisms and specific trajectories. The twelve-fight pilot is diagnostic and does not replace full-matrix balance acceptance; player experience and formal runtime promotion remain separate.'})
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'nativeChecks': 2406, 'pilotExpectedRows': 12, 'sealed': False}))
