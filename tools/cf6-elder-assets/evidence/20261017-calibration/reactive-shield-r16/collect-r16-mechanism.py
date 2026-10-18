from pathlib import Path
import datetime, importlib.util, json, re

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
assert (R / 'tmp/arena-worker-experiments/cf6-cal-r16-pilot-20261018/execution-started.json').is_file()
selected = {'elder-asset': 'native-r16-decay-adapter-repair', 'player-aim': 'native-r16-decay-adapter-repair', 'audio': 'native-r16-reactive-shield'}
expected = {'elder-asset': [('Cf6ElderAssetTest', 906), ('Cf6ElderCombatEffectsTest', 116), ('Cf6RobotCombatTest elder', 45)],
            'audio': [('Cf6AudioTest', 340)], 'player-aim': [('Cf6PlayerAimTest', 1023)]}
for name, folder in selected.items():
    result = u.js(O / folder / name / 'result.json')
    assert result['exitCode'] == 0 and result['bindingsUnchanged']
    trace = u.read(O / folder / name / 'flashlog.txt').decode('utf-8-sig')
    for label, count in expected[name]:
        assert re.search(re.escape(label) + r': ' + str(count) + r' passed, 0 failed', trace), (name, label)
assert u.js(O / 'native-r16-reactive-shield/elder-asset/result.json')['exitCode'] == 1
assert u.js(O / 'native-cleanup-after-r16.json')['ok']
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
readme = R / 'tools/cf6-elder-assets/README.md'
package.copy(readme, 'reactive-shield-r16/README-before-native-complete.md')
text = readme.read_text('utf8')
old = next(line for line in text.splitlines() if line.startswith('当前强度校准尚未完成。'))
new = '当前强度校准尚未完成。R15 十二场诊断已全部自然落败、无超时，但仍有分组低于目标；原始结果已完整保留。R16 按用户追加的“每损失 5% 生命强制生成、再周期补充”加入机器人应激盾：以本形态初始满血值固定损血门槛，每跨一档转换该档损失，保留不足一档的余量；两种来源共用一层最高 10% 初始满血容量的硬盾，强度为空手攻击力的 10 倍。每 24 个有效帧按当前缺失生命的 5% 补充，单次不超过初始满血的 1%；没有新补充时，容量在 36 帧内线性衰减至零。暂停不推进，死亡或离开形态只清理自身层与订阅。\n\n该机制不治疗实际 HP，也不修改全局吸血顺序：触发补盾的那一击已经完成吸血，后续命中才受新盾保护。动作、倍率、已有砸地／连打盾与光束盾保持 R15。当前候选已编译并通过选定的 2,430 项行为检查；首次夹具遗漏衰减盾适配器导致的真实失败另行保留，修复只补入生产接口原文，没有降低断言。十二场新试跑正在使用合并冷兵器更新后的加载程序运行，尚不能宣布完整强度目标或狂暴期零吸血成立。全部旧轮次和实际运行身份见[校准汇总](evidence/20261017-calibration/summary.json)，尚未提交推送或正式发布 runtime。'
readme.write_text(text.replace(old, new), 'utf8')
paths = ['tools/cf6-elder-assets/' + name for name in ['ElderAI.as', 'build.py', 'balance.py', 'native-manifest.json', 'arena-plan.js', 'build-playtest-fixture.py', 'playtest-fixture-manifest.json', 'README.md']]
paths += ['scripts/类定义/org/flashNight/arki/unit/Action/Melee/' + name for name in ['Cf6ElderCombatEffectsTest.as', 'Cf6ElderAssetTest.as', 'Cf6PlayerAimTest.as']]
paths += ['scripts/test-runners/cf6-playtest/PlaytestFixture.as', 'scripts/run-cf6-elder-asset-tests.ps1', 'data/enemy_properties/CF6重制敌人.xml']
package.freeze(paths, 'reactive-shield-r16/source.zip')
for source, target in [('build-r16-elder', 'publish'), ('native-r16-reactive-shield', 'native-first-attempt'),
                       ('native-r16-decay-adapter-repair', 'native-repaired-adapter'), ('native-cleanup-after-r16-receipts', 'native-cleanup')]:
    package.tree(O / source, 'reactive-shield-r16/' + target)
for name in ['before-r16-reactive-shield.zip', 'before-r16-reactive-shield-index.json',
             'before-r16-decay-adapter-repair.zip', 'before-r16-decay-adapter-repair-index.json',
             'native-cleanup-after-r16.json', 'elder-r16-image-equivalence.json', 'verify-elder-r16.log',
             'balance-r16-elder-check.log', 'regeneration-r16-elder.log', 'worker-sync-r18.json',
             'prepare-r16-reactive-shield.py', 'repair-r16-decay-adapter.py', 'prepare-r16-pilot.py', 'run-r16-pilot.ps1',
             'playtest-fixture-r16-repair-generation.log', 'playtest-fixture-r16-repair-check.log', 'collect-r16-mechanism.py']:
    package.copy(O / name, 'reactive-shield-r16/' + name)
u.jput(P / 'reactive-shield-r16/summary.json', {
    'status': 'native_verified; exploratory_pilot_running',
    'lossBasis': 'Observed positive HP changes per form, accumulated exactly once; healing rebases the observation without adding credit. Lethal damage cannot grant a shield.',
    'lossStepOfInitialMaximumHp': .05, 'forcedConversion': 1, 'capacityLimitOfInitialMaximumHp': .1,
    'pulseFrames': 24, 'pulseMissingHpRatio': .05, 'pulseCapacityLimitOfInitialMaximumHp': .01,
    'decayFrames': 36, 'strengthRatio': 10, 'robotOnly': True, 'oneOwnedLayer': True,
    'incomingLeechDiagnostic': 'Counts the production damage-result leech flag, with a separate count for a shooter whose rage flag is active. This is not a pre-hit HP probe or a blanket zero-healing proof.',
    'native': {'assetPassed': 906, 'effectsPassed': 116, 'robotPassed': 45, 'totalPassed': 1067,
               'timelineCases': 46, 'phaseCases': 13, 'audioPassed': 340, 'audioRoutes': 81, 'playerAimPassed': 1023, 'playerAimCases': 74,
               'selectedFolders': selected, 'totalSelectedChecks': 2430},
    'firstAttempt': {'overallPassed': False, 'effectsPassed': 105, 'effectsFailed': 10, 'assetPassed': 905, 'assetFailed': 1,
                     'diagnosedCause': 'The generated fixture omitted the existing production decay-shield adapter. The candidate SWF and production behavior were unchanged by the fixture repair.'},
    'candidateSwfSha256': u.sha(R / 'flashswf/arts/new/Codex老头素材.swf'), 'loaderSha256': u.sha(R / 'scripts/asLoader.swf'),
    'exploratoryPilot': 'cf6-cal-r16-pilot-20261018', 'exploratoryPilotRows': 12,
    'boundary': 'Native tests distinguish the trigger hit, whose leech has already settled, from later shielded hits. Full-matrix balance, field rage-heal gaps, player experience and formal runtime promotion remain separate.'})
package.copy(P / 'summary.json', 'progress-snapshots/20261018-before-r16-pilot.json')
summary = u.js(P / 'summary.json')
summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(), sealed=False, allGoalsMet=False)
summary['elder'].update(currentRound='R16', currentExperiment='cf6-cal-r16-pilot-20261018',
                        currentExperimentState='exploratory pilot running', nativeChecksPassed=2430,
                        r16Mechanism='reactive-shield-r16/summary.json')
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'nativeSelectedChecks': 2430, 'originalFailurePreserved': True, 'pilotRows': 12, 'sealed': False}))
