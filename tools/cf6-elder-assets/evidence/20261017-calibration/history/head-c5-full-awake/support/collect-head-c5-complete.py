"""Select the new full C5 matrix, preserving every earlier result unchanged."""
from pathlib import Path
import datetime, importlib.util, json

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
label = 'head-c5-full-awake'
result = u.js(P / 'history' / label / 'strength-summary.json')
assert result['fullMatrix'] and result['strengthPassed'] and result['wins'] == 18 and not result['timeouts']
for binding in result['sourceBindings']:
    assert u.sha(R / binding['path']) == binding['sha256'], binding['path']
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
for name in ['prepare-head-c5-full.py', 'run-head-c5-full.ps1', 'head-c5-progress.py',
             'analyze-head-c5-full.py', 'collect-head-c5-complete.py', 'collect-head-c5.log']:
    package.copy(O / name, 'history/' + label + '/support/' + name)
readme = R / 'tools/cf6-headbot-assets/README.md'
package.copy(readme, 'history/' + label + '/support/README-before-C5-full-matrix.md.txt')
text = readme.read_text('utf8')
old = next(line for line in text.splitlines() if line.startswith('30／60／99 级、双方换位各三次的完整十八场'))
new = '当前 472 号大头机器人已在整合主线场景的 C5 公共加载器与 R4 隔离 Host 候选上完成 30／60／99 级、双方换位各三次的完整十八场，全部自然获胜、无超时。候选身份、资源一致性、存档保护、退出与全程显示观察均通过，下表对应本次实际结果，逐场见[当前 C5 完整矩阵](../cf6-elder-assets/evidence/20261017-calibration/history/head-c5-full-awake/strength-summary.json)。此前 C3 十八场、C4 六场与所有失败记录保留各自编号和执行身份，见[校准汇总](../cf6-elder-assets/evidence/20261017-calibration/summary.json)。'
assert text.count(old) == 1
text = text.replace(old, new)
start = text.index('| 等级 | 胜场／场次 | 最低剩余生命 | 战斗帧数 |')
end = text.index('\n\n', start)
table = ['| 等级 | 胜场／场次 | 最低剩余生命 | 战斗帧数 |', '|---|---:|---:|---:|']
for group in result['groups']:
    low, high = group['frameRange']
    table.append(f"| {group['level']} | {group['wins']}／6 | {group['minimumRemainingHpRatio'] * 100:.2f}% | {int(low)}–{int(high)} |")
text = text[:start] + '\n'.join(table) + text[end:]
old = next(line for line in text.splitlines() if line.startswith('两轮对战分别保留各自身份'))
new = '有限的十八场结果不保证所有随机局面必胜。当前十三项绑定输入均与本轮原始回执一致；主线已发布的 470／471 为同伴，大头、老头人形、老头机器人使用 472／473／474，旧编号没有运行时别名。C4→C5 的 724 个既有编译类动作逐字相同，两个场景类有变化并新增两个据点类；本轮重新执行完整矩阵。七个蓄光画面仍由此前原生捕获及图形等价证明支持，本轮未重新截图。标准入口、低配机器和玩家手感仍待分别验收。'
text = text.replace(old, new)
readme.write_text(text, 'utf8', newline='\n')
package.copy(P / 'summary.json', 'progress-snapshots/20261018-before-head-c5-complete.json')
summary = u.js(P / 'summary.json')
summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(), sealed=False, allGoalsMet=False)
summary['headbot']['retainedC4Integration'] = summary['headbot'].get('mergedLoaderIntegration')
summary['headbot']['mergedLoaderIntegration'] = {
    'report': 'history/' + label + '/strength-summary.json', 'rows': 18, 'wins': 18,
    'timeouts': 0, 'fullMatrix': True,
    'classScope': 'upstream-base-siege-integration/base-siege-loader-class-scope.json',
    'boundary': 'The separate C3 and C4 executions retain their original identities; this is the current C5 full matrix.'}
summary['headbot'].update(selectedExperiment=result['experiment'], selectedRows=18, selectedWins=18, selectedTimeouts=0,
                          groups=result['groups'], currentExperiment=result['experiment'],
                          currentExperimentState='completed; current unit 472 and C5 full matrix strength_passed',
                          currentCandidateMatrixRows=18, currentCandidateFullMatrix=True,
                          goalMet=True, currentC5FullMatrixPending=False,
                          subsequentMergedLoaderIntegrationPending=False,
                          selectedReport='history/' + label + '/strength-summary.json',
                          boundary=result['boundary'])
summary['nextStep'].update(headCurrentMatrixRows=18, headCurrentMatrixState='C5 full eighteen wins; current unit 472 and final shared data',
                          elderNextIteration='Final evidence, documentation and scoped commit/push checks remain.')
summary['history'] = [{k: v for k, v in run.items() if k in ['label', 'experiment', 'rows', 'qualified', 'strengthAccepted', 'displayQualified', 'selectedForHeadbot', 'selectedForCurrentHeadbot', 'selectedForHeadbotIntegration', 'selectedForC5Headbot', 'selectedForCurrentElder', 'acceptanceProfile', 'historicalNetHpStrengthAccepted', 'priorZeroWinStrengthAccepted', 'boundary']} for run in state['runs']]
summary['historyRows'] = sum(run['rows'] for run in state['runs'])
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'currentHeadGoalMet': True, 'wins': 18, 'historyRows': summary['historyRows'], 'allGoalsMet': False}))
