from pathlib import Path
import datetime, importlib.util, json, re

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
assert (R / 'tmp/arena-worker-experiments/cf6-cal-r17-pilot-20261018/execution-started.json').is_file()
expected = {'elder-asset': [('Cf6ElderAssetTest', 906), ('Cf6ElderCombatEffectsTest', 119), ('Cf6RobotCombatTest elder', 45)],
            'audio': [('Cf6AudioTest', 340)], 'player-aim': [('Cf6PlayerAimTest', 1023)]}
for name, cases in expected.items():
    result = u.js(O / 'native-r17-pulse-coverage' / name / 'result.json')
    assert result['exitCode'] == 0 and result['bindingsUnchanged']
    trace = u.read(O / 'native-r17-pulse-coverage' / name / 'flashlog.txt').decode('utf-8-sig')
    for label, count in cases:
        assert re.search(re.escape(label) + r': ' + str(count) + r' passed, 0 failed', trace), (name, label)
assert u.js(O / 'native-cleanup-after-r17.json')['ok']
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
readme = R / 'tools/cf6-elder-assets/README.md'
package.copy(readme, 'pulse-coverage-r17/README-before-native-complete.md')
text = readme.read_text('utf8')
old = 'R17 尚待新鲜编译与原生回归，再进行独立对战确认。'
new = 'R17 已通过真实 CS6 编译与 2,433 项行为检查，单盾／叠盾计量及施击实例诊断均有本轮回归；当前十二场独立试跑仍在进行，随后仍须三十六场完整验证。'
assert text.count(old) == 1
readme.write_text(text.replace(old, new), 'utf8')
paths = ['tools/cf6-elder-assets/' + name for name in ['ElderAI.as', 'build.py', 'balance.py', 'native-manifest.json', 'arena-plan.js', 'build-playtest-fixture.py', 'playtest-fixture-manifest.json', 'README.md']]
paths += ['scripts/类定义/org/flashNight/arki/unit/Action/Melee/' + name for name in ['Cf6ElderCombatEffectsTest.as', 'Cf6ElderAssetTest.as', 'Cf6PlayerAimTest.as']]
paths += ['scripts/test-runners/cf6-playtest/PlaytestFixture.as', 'scripts/run-cf6-elder-asset-tests.ps1',
          'scripts/类定义/org/flashNight/arki/component/Shield/AdaptiveShield.as', 'data/enemy_properties/CF6重制敌人.xml']
package.freeze(paths, 'pulse-coverage-r17/source.zip')
for source, target in [('build-r17-elder', 'publish'), ('native-r17-pulse-coverage', 'native-tests'), ('native-cleanup-after-r17-receipts', 'native-cleanup')]:
    package.tree(O / source, 'pulse-coverage-r17/' + target)
for name in ['before-r17-pulse-coverage.zip', 'before-r17-pulse-coverage-index.json', 'native-cleanup-after-r17.json',
             'elder-r17-image-equivalence.json', 'verify-elder-r17.log', 'balance-r17-elder-check.log', 'regeneration-r17-elder.log',
             'worker-sync-r19.json', 'prepare-r17-pulse-coverage.py', 'prepare-r17-pilot.py', 'run-r17-pilot.ps1', 'collect-r17-mechanism.py']:
    package.copy(O / name, 'pulse-coverage-r17/' + name)
u.jput(P / 'pulse-coverage-r17/summary.json', {
    'status': 'native_verified; exploratory_pilot_running', 'lossStepOfInitialMaximumHp': .05,
    'forcedConversion': .4, 'capacityLimitOfInitialMaximumHp': .1, 'pulseFrames': 6,
    'pulseMissingHpRatio': .00625, 'pulseCapacityLimitOfInitialMaximumHp': .00125,
    'pulseCeilingPer30ActiveFramesRatio': .00625, 'decayFrames': 36, 'strengthRatio': 10,
    'robotOnly': True, 'oneOwnedReactiveLayer': True, 'noOpponentSpecificShieldDecision': True,
    'beamCapacityAccountingQualified': True,
    'beamAccountingMethod': 'Production per-layer absorption callback, with once-only finalization; single-shield container and stacked-shield cases both exercised. No long-lived cached layer capacity reads.',
    'rageSourceDiagnostic': 'Actual shooter instance name, positive leech-result count, maximum raw bullet power, first and last actor clock. These fields do not affect shield grants or damage.',
    'native': {'assetPassed': 906, 'effectsPassed': 119, 'robotPassed': 45, 'totalPassed': 1070,
               'timelineCases': 46, 'phaseCases': 13, 'audioPassed': 340, 'audioRoutes': 81,
               'playerAimPassed': 1023, 'playerAimCases': 74, 'totalSelectedChecks': 2433},
    'candidateSwfSha256': u.sha(R / 'flashswf/arts/new/Codex老头素材.swf'), 'loaderSha256': u.sha(R / 'scripts/asLoader.swf'),
    'exploratoryPilot': 'cf6-cal-r17-pilot-20261018', 'exploratoryPilotRows': 12,
    'boundary': 'Native mechanism checks do not prove field rage-leech suppression or final strength. Full-matrix balance, current-entry integration and player acceptance remain separate.'})
package.copy(P / 'summary.json', 'progress-snapshots/20261018-before-r17-pilot.json')
summary = u.js(P / 'summary.json')
summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(), sealed=False, allGoalsMet=False)
summary['elder'].update(currentRound='R17', currentExperiment='cf6-cal-r17-pilot-20261018',
                        currentExperimentState='exploratory pilot running', nativeChecksPassed=2433,
                        r17Mechanism='pulse-coverage-r17/summary.json')
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'nativeSelectedChecks': 2433, 'singleShieldAccountingRepaired': True, 'pilotRows': 12, 'sealed': False}))
