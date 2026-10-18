from pathlib import Path
import datetime, importlib.util, json, re

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
assert (R / 'tmp/arena-worker-experiments/cf6-cal-r18-pilot-20261018/execution-started.json').is_file()
expected = {'elder-asset': [('Cf6ElderAssetTest', 906), ('Cf6ElderCombatEffectsTest', 122), ('Cf6RobotCombatTest elder', 45)],
            'audio': [('Cf6AudioTest', 340)], 'player-aim': [('Cf6PlayerAimTest', 1023)]}
for name, cases in expected.items():
    result = u.js(O / 'native-r18-near-shield-budget' / name / 'result.json')
    assert result['exitCode'] == 0 and result['bindingsUnchanged']
    trace = u.read(O / 'native-r18-near-shield-budget' / name / 'flashlog.txt').decode('utf-8-sig')
    for label, count in cases:
        assert re.search(re.escape(label) + r': ' + str(count) + r' passed, 0 failed', trace), (name, label)
assert u.js(O / 'native-cleanup-after-r18.json')['ok']
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
base = 'near-shield-budget-r18/'
readme = R / 'tools/cf6-elder-assets/README.md'
package.copy(readme, base + 'README-before-native-complete.md')
text = readme.read_text('utf8')
old = 'R18 尚待新鲜编译、原生回归与独立对战，不能把 R17 已通过的 2,433 项检查视为 R18 通过。'
new = 'R18 已通过真实 CS6 编译及 2,436 项行为检查，其中三项新增断言核对近战层实际吸收与旧层隔离；十二场独立试跑正在进行，仍须通过三十六场完整验证。'
assert text.count(old) == 1
readme.write_text(text.replace(old, new), 'utf8')
paths = ['tools/cf6-elder-assets/' + name for name in ['ElderAI.as', 'build.py', 'balance.py', 'native-manifest.json', 'arena-plan.js', 'build-playtest-fixture.py', 'playtest-fixture-manifest.json', 'README.md']]
paths += ['scripts/类定义/org/flashNight/arki/unit/Action/Melee/' + name for name in ['Cf6ElderCombatEffectsTest.as', 'Cf6ElderAssetTest.as', 'Cf6PlayerAimTest.as']]
paths += ['scripts/test-runners/cf6-playtest/PlaytestFixture.as', 'scripts/run-cf6-elder-asset-tests.ps1',
          'scripts/类定义/org/flashNight/arki/component/Shield/AdaptiveShield.as', 'data/enemy_properties/CF6重制敌人.xml',
          'agentsDoc/testing-details.md', 'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts']
package.freeze(paths, base + 'source.zip')
for source, target in [('build-r18-elder', 'publish'), ('native-r18-near-shield-budget', 'native-tests'), ('native-cleanup-after-r18-receipts', 'native-cleanup')]:
    package.tree(O / source, base + target)
for name in ['before-r18-near-shield-budget.zip', 'before-r18-near-shield-budget-index.json',
             'before-r18-testing-details.md', 'before-r18-testing-details-index.json',
             'native-cleanup-after-r18.json', 'elder-r18-image-equivalence.json', 'verify-elder-r18.log',
             'balance-r18-elder-check.log', 'regeneration-r18-elder.log', 'regeneration-r18-check.log',
             'worker-sync-r20.json', 'prepare-r18-near-shield-budget.py', 'run-r18-native.ps1',
             'prepare-r18-pilot.py', 'run-r18-pilot.ps1', 'collect-r18-mechanism.py',
             'r17-formula-sensitivity-unexecuted.json']:
    package.copy(O / name, base + name)
u.jput(P / base / 'summary.json', {
    'status': 'native_verified; exploratory_pilot_running',
    'kicksCapacityRatio': .10, 'kicksStrengthLevelEndpoints': [.30, .12], 'kicksLifetimeLevelEndpoints': [120, 60],
    'slamCapacityRatio': .015, 'slamStrengthRatio': 10, 'slamLifetimeFrames': 120,
    'lossStepOfInitialMaximumHp': .05, 'forcedConversion': .4, 'capacityLimitOfInitialMaximumHp': .1,
    'pulseFrames': 3, 'pulseMissingHpRatio': .003125, 'pulseCapacityLimitOfInitialMaximumHp': .000625,
    'pulseCeilingPer30ActiveFramesRatio': .00625, 'decayFrames': 36, 'strengthRatio': 10,
    'sameReactiveSupplementCeilingAsR17': True, 'actionPowersAndFormulaPanelUnchanged': True,
    'robotOnly': True, 'oneOwnedReactiveLayer': True, 'noOpponentSpecificShieldDecision': True,
    'beamCapacityAccountingQualified': True, 'meleeLayerAbsorptionAccountingQualified': True,
    'meleeAccountingMethod': 'Separate production per-layer absorption callbacks, gated by actor identity and current owned shield ID; actual soft/hard absorption and retired-layer rejection exercised.',
    'native': {'assetPassed': 906, 'effectsPassed': 122, 'robotPassed': 45, 'totalPassed': 1073,
               'timelineCases': 46, 'phaseCases': 13, 'audioPassed': 340, 'audioRoutes': 81,
               'playerAimPassed': 1023, 'playerAimCases': 74, 'totalSelectedChecks': 2436},
    'candidateSwfSha256': u.sha(R / 'flashswf/arts/new/Codex老头素材.swf'), 'loaderSha256': u.sha(R / 'scripts/asLoader.swf'),
    'exploratoryPilot': 'cf6-cal-r18-pilot-20261018', 'exploratoryPilotRows': 12,
    'boundary': 'Native mechanism checks do not establish final strength or zero first-phase rage healing. Candidate full-matrix balance, formal promotion and player acceptance are separate.'})
package.copy(P / 'summary.json', 'progress-snapshots/20261018-before-r18-pilot.json')
summary = u.js(P / 'summary.json')
summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(), sealed=False, allGoalsMet=False)
summary['elder'].update(currentRound='R18', currentExperiment='cf6-cal-r18-pilot-20261018',
                        currentExperimentState='exploratory pilot running', nativeChecksPassed=2436,
                        r18Mechanism=base + 'summary.json')
for row in summary['currentBindings']:
    row.update(bytes=(R / row['path']).stat().st_size, sha256=u.sha(R / row['path']))
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'nativeSelectedChecks': 2436, 'meleeLayerAbsorptionQualified': True, 'pilotRows': 12, 'sealed': False}))
