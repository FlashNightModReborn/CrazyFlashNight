from evidence_utils import *
import statistics, subprocess
from datetime import datetime, timezone

workers = [Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight' for name in ['headbot-combat', 'headbot-combat2']]
assert not (ROOT/'tmp/arena-worker-experiments/elder-r16-matrix-20261017').exists()
assert not (TMP/'matrix-r16-run.log').exists()
assert all(not list((root/'tmp/arena-calibration/batches').glob('elder-r16*')) for root in workers)
report = js(ROOT/'tmp/arena-worker-experiments/elder-r15-matrix-20261017/experiment-report.json')
assert report['qualified'] and report['status'] == 'completed' and report['completedGroups'] == 6 and not report['errors']
rows = []
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:
        assert outcome['status'] == 'completed' and all(outcome[key] for key in ['cleanupVerified', 'protectedSavesVerified', 'runtimeResourcesVerified'])
        receipt = js(outcome['expectedReceiptPath'])
        assert sha(outcome['expectedReceiptPath']) == outcome['receiptSha256'].removeprefix('sha256:')
        assert receipt['runtimeUnchanged'] and receipt['resourcesUnchanged'] and not receipt['errors']
        assert sha(receipt['resultPath']) == receipt['resultSha256'].removeprefix('sha256:')
        rows.extend(json.loads(line) for line in read(receipt['resultPath']).decode('utf-8-sig').splitlines() if line)
assert len(rows) == 36 and len({(row['batchId'], row['runId']) for row in rows}) == 36
stats = []
for rival, name in [(78, '方舟兽王'), (361, 'EXUSIAI 指挥官')]:
    for level in [30, 60, 99]:
        subset = [row for row in rows if row['authorityContext']['rivalUnitId'] == rival and row['authorityContext']['level'] == level]
        assert len(subset) == 6
        for side in ['blue', 'red']:
            assert {row['repeatIndex'] for row in subset if row['authorityContext']['candidateSide'] == side} == {1, 2, 3}
        values = []
        for row in subset:
            side = row['authorityContext']['candidateSide']; other = 'red' if side == 'blue' else 'blue'
            assert row['status'] == 'finished' and row['winner'] == other and not row['errors'] and row['phaseSpawnCount'] == 1
            assert len(row['spawnedUnits']) == 1 and row['spawnedUnits'][0]['unit'] == '敌人-CF6老头机器人'
            values.append(100*(1-row[other]['remainHp']/row[other]['startMaxHp']))
        stats.append({'rival':rival, 'name':name, 'level':level, 'values':values, 'min':min(values),
                      'mean':statistics.mean(values), 'median':statistics.median(values), 'max':max(values),
                      'withinTargetBand':sum(50 <= value <= 80 for value in values),
                      'minFrames':min(row['frames'] for row in subset), 'maxFrames':max(row['frames'] for row in subset)})

for row in js(TMP/'matrix-r16/input-identity.json')['sourceBindings']:
    assert sha(ROOT/row['path']) == row['sha256'], 'Unexpected prepared R16 input drift: '+row['path']
for row in js(TMP/'native-r15-evidence.json')['sourceBindings']:
    assert sha(ROOT/row['path']) == row['sha256'], 'Native input drift: '+row['path']
owned = ['tools/cf6-elder-assets/balance.py', 'tools/cf6-elder-assets/balance-inputs.json',
         'data/enemy_properties/CF6重制敌人.xml', 'tools/cf6-elder-assets/README.md']
for relative in owned: put(TMP/'r16-pre-review'/relative, read(ROOT/relative))
file = ROOT/'tools/cf6-elder-assets/balance.py'; before = read(file)
needle = b"'growth':0.9,'attackBias':2,'defenseBias':34}"
assert before.count(needle) == 1
lp(file).write_bytes(before.replace(needle, b"'growth':1,'attackBias':2,'defenseBias':34}"))
subprocess.run(['python', '-X', 'utf8', '-B', str(file), '--write'], cwd=ROOT, check=True)
subprocess.run(['python', '-X', 'utf8', '-B', str(file)], cwd=ROOT, check=True)
for relative in owned[:3]:
    assert sha(ROOT/relative) == sha(TMP/'r15-before-balance'/relative), 'Review candidate differs from executed R15: '+relative
for row in js(TMP/'matrix-r15/input-identity.json')['sourceBindings']:
    assert sha(ROOT/row['path']) == row['sha256'], 'Executed R15 binding not restored: '+row['path']
copied = []
for root in workers:
    for relative in owned[:3]:
        target = root/relative; old_hash = sha(target)
        assert old_hash == sha(TMP/'r16-pre-review'/relative), 'Unexpected owned Worker drift: '+relative
        lp(target).write_bytes(read(ROOT/relative))
        assert sha(target) == sha(ROOT/relative)
        copied.append({'root':str(root), 'path':relative, 'beforeSha256':old_hash, 'sha256':sha(target)})
    for row in js(TMP/'matrix-r15/input-identity.json')['sourceBindings']:
        assert sha(root/row['path']) == row['sha256'], 'Worker R15 binding not restored: '+row['path']
jput(TMP/'worker-copy-review-r15.json', {'scope':'User requested human review before further tuning. Restore only three prepared R16 data/generator files per Worker to executed R15; all 17 declared bindings verified. Preserve all R16 preparation evidence.', 'files':copied})
jput(TMP/'r16-prepared-not-executed.json', {'revision':'r16', 'dataPreparedAndStaticallyVerified':True,
    'candidateCombatExecuted':False, 'experimentDirectoryAbsent':True, 'workerBatchesAbsent':True,
    'retainedInputs':'r16-frozen-inputs/frozen-inputs.zip.index.json', 'restoredForReview':'r15',
    'reason':'User selected human move/gameplay review first, then strength tuning toward 50-80 percent HP exchange.'})

readme = ROOT/'tools/cf6-elder-assets/README.md'; text = read(readme).decode('utf8')
before_text = '当前候选为 R16：行为与发布 SWF 沿用 R15，配表为 R16。'
assert text.count(before_text) == 1
text = text.replace(before_text, '当前待人工验收版本为 R15：行为、发布 SWF 与配表全部恢复到已完成 36 场候选对战的 R15 身份。')
before_text = '机器人成长 0.9、高攻低血防 2、高防低血 34。机器人成长 0.9 用于收回 R15 高等级对局过近的取胜边界，30 级面板几乎不变；'
assert text.count(before_text) == 1
text = text.replace(before_text, '机器人成长 1.0、高攻低血防 2、高防低血 34。此配置现用于招式验收，强度待用户体验后按 50%–80% 交换目标继续校准；')
before_text = 'R16 仅将机器人成长从 1.0 收至 0.9，保留高防低血 34、R15 光束收招、全部伤害倍率与用户指定阶段／档次。按同一公式，30 级面板几乎不变，99 级 HP／攻击／防御从 27549／7231／7224 收至 26545／6874／6580；这只是公式预估，完整两对手、三等级矩阵仍须重跑，不用预估替代战斗证据。'
assert text.count(before_text) == 1
text = text.replace(before_text, '随后准备过成长 0.9 的 R16 配表，并完成静态验证；尚未启动任何 R16 候选对战。用户明确选择“先交付验收版，体验后再调强度”，因此恢复已实测的 R15 配置。R16 的源码、冻结输入、校验结果和恢复记录全部保留，不计作实战结果。')
text = text.replace('工作判据在 R8 开跑前选定：', '历史工作判据在 R8 开跑前选定：', 1)
text = text.replace('该阈值是本轮将“明显威胁”落到可检查数据的设计口径，不是用户指定数值，也不是任意随机对局的胜率保证；',
                    '该阈值是此前 agent 自定的工作口径，现已由用户的 50%–80% 期望取代，不能用于判定当前强度达标；', 1)
assert text.count('## 当前对战验证\n') == 1
section = '''## 当前验收目标与对战结果

用户在 2026-10-17 明确：老头＋机器人应达到约 **50%–80% 血量交换能力**，并选择**先交付招式验收版，体验后再调强度**。本次按完整两阶段对同级方舟兽王／EXUSIAI 指挥官的最终净生命损失记录该目标；每场低值、高值及分布均保留，不把平均值达标当作每场都达标。

当前 R15 **尚未完成强度校准**。六组平均净失血为 32.57%–56.14%；99 级指挥官另有一场净失血 95.89%，只剩 4.11% 生命。现阶段交付用于体验招式衔接与打击感，后续同时处理低输出和险胜边界。

[完整证据包](evidence/20261017/summary.json)包含 30／60／99 级、双方换位、每侧三次，共 **36 场**；老头组合 **0 胜、36 场自然落败、0 超时**，每场恰好生成一次机器人后继。

| 对手 | 等级 | 净失血最低 | 平均 | 中位数 | 最高 | 落在 50%–80% 的场次 |
|---|---:|---:|---:|---:|---:|---:|
'''
for row in stats:
    section += f"| {row['name']} | {row['level']} | {row['min']:.2f}% | {row['mean']:.2f}% | {row['median']:.2f}% | {row['max']:.2f}% | {row['withinTargetBand']}/6 |\n"
section += '''
净生命损失包含兽王吸血回补，不是累计造成伤害。有限重复不证明任意随机局面下必然落败，或每场都落在目标区间。

两套隔离环境绑定相同候选 runtime 身份／闭包及对应源码、SWF、数据。全部实验退出、运行资源、只读种子、非目标存档和全局 SharedObject 检查通过。公共击退修正后的大头／大刀证据保留原包；集成核对确认它们的单位数据节点未变，共享 CF6 XML 的其余差异仅属于老头两种形态。

复查入口：[逐场阶段诊断](evidence/20261017/field-diagnostics.json)、[源码与输入索引](evidence/20261017/frozen-inputs.zip.index.json)、[无损映射](evidence/20261017/lossless-mapping.json)、[完整性清单](evidence/20261017/integrity.json)。历史失败、旧矩阵、原始 trace、编译报告、R16 未执行准备及恢复过程一并归档。

原生图像：[人形待机](evidence/20261017/native/images/human-stand-1.png)、[变形第 55 帧](evidence/20261017/native/images/phase-55.png)、[机器人光束](evidence/20261017/native/images/beam-29.png)。[图像来源](evidence/20261017/native/image-provenance.json)说明 R6 捕获与后续版本图形等价证明，未将旧图写成 R15 重新截图。

本轮状态为 `candidate_executed / 待人工招式验收 / 强度校准未完成`。外观、动作衔接、打击感与标准入口待用户验收。工作区保留待审，未提交、未推送，也未进行正式 runtime 发布。
'''
readme.write_text(text.split('## 当前对战验证\n')[0]+section, encoding='utf8', newline='\n')
jput(TMP/'review-candidate-r15.json', {'revision':'r15', 'preparedAt':datetime.now(timezone.utc).isoformat(),
    'userDecision':'先交付验收版，体验后再调强度', 'targetNetHpExchangePercent':[50, 80],
    'balanceCalibrationComplete':False, 'humanAcceptance':False, 'games':36, 'wins':0, 'timeouts':0,
    'groups':stats, 'executedR15BindingsRestored':True, 'r16NotExecuted':True})
print(json.dumps({'reviewCandidate':'r15', 'restoredWorkerFiles':len(copied), 'games':36,
                  'targetNetHpExchangePercent':[50, 80], 'balanceCalibrationComplete':False, 'groups':stats}, ensure_ascii=False))
