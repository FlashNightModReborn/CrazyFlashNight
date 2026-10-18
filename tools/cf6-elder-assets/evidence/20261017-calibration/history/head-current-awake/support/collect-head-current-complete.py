from pathlib import Path
import datetime, importlib.util, json

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
result = u.js(P / 'history/head-current-awake/strength-summary.json')
assert result['fullMatrix'] and result['strengthPassed'] and result['wins'] == 18 and not result['timeouts']
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
for name in ['head-bindings-during-r15-preparation.json', 'analyze-current-head-matrix.py', 'head-progress.py', 'collect-head-current-complete.py']:
    package.copy(O / name, 'history/head-current-awake/support/' + name)
readme = R / 'tools/cf6-headbot-assets/README.md'
package.copy(readme, 'history/head-current-awake/support/README-before-current-matrix.md')
text = readme.read_text('utf8')
old = next(line for line in text.splitlines() if line.startswith('已完成的选定十八场同级方舟爪豪'))
new = '当前隔离候选已完成 30／60／99 级、双方换位各三次的十八场同级方舟爪豪复验，全部自然获胜、无超时。候选身份、资源一致性、存档保护、退出及全程显示观察检查均通过；逐场结果见[当前完整矩阵](../cf6-elder-assets/evidence/20261017-calibration/history/head-current-awake/strength-summary.json)。此前十八场结果及调参失败仍保留在[校准汇总](../cf6-elder-assets/evidence/20261017-calibration/summary.json)，本轮汇总尚未封存，长老强度校准与提交工作仍在继续。'
assert text.count(old) == 1
text = text.replace(old, new)
start = text.index('| 等级 | 胜场／场次 | 最低剩余生命 | 战斗帧数 |')
end = text.index('\n\n', start)
table = ['| 等级 | 胜场／场次 | 最低剩余生命 | 战斗帧数 |', '|---|---:|---:|---:|']
for group in result['groups']:
    low, high = group['frameRange']
    table.append(f"| {group['level']} | {group['wins']}／6 | {group['minimumRemainingHpRatio'] * 100:.2f}% | {int(low)}–{int(high)} |")
text = text[:start] + '\n'.join(table) + text[end:]
old = next(line for line in text.splitlines() if line.startswith('30 级仍出现险胜，有限的十八场'))
new = '有限的十八场验证不保证所有随机局面必胜。本轮沿用当前大头发布 SWF，并绑定实际 loader 与隔离 Host 候选；测试期间准备长老下一版源文件，没有改变大头计划绑定的十三项输入。七个蓄光画面仍由此前原生捕获及图形等价证明支持，未将它们写成这轮重新截图。标准入口、低配机器和玩家手感仍待分别验收。'
text = text.replace(old, new)
readme.write_text(text, 'utf8')
u.put(P / 'progress-snapshots/20261018-before-head-current-complete.json', u.read(P / 'summary.json'))
summary = u.js(P / 'summary.json')
summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(), sealed=False, allGoalsMet=False)
summary['headbot'].update(selectedExperiment=result['experiment'], selectedRows=18, selectedWins=18, selectedTimeouts=0,
                          groups=result['groups'], currentExperiment=result['experiment'], currentExperimentState='completed; strength_passed',
                          currentCandidateMatrixRows=18, goalMet=True, selectedReport='history/head-current-awake/strength-summary.json',
                          boundary=result['boundary'])
summary['nextStep'].update(headCurrentMatrixState='completed; strength_passed', elderNextIteration='R15 hard shield and read-only beam consumption pilot')
summary['history'] = [{k: v for k, v in run.items() if k in ['label', 'experiment', 'rows', 'qualified', 'strengthAccepted', 'displayQualified', 'selectedForHeadbot', 'selectedForCurrentHeadbot', 'boundary']} for run in state['runs']]
summary['historyRows'] = sum(run['rows'] for run in state['runs'])
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'currentHeadGoalMet': True, 'wins': 18, 'historyRows': summary['historyRows'], 'allGoalsMet': False}))
