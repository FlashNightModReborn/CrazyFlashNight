from pathlib import Path
import datetime, importlib.util, json

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
result = u.js(P / 'history/head-c4-integration-awake/strength-summary.json')
assert not result['fullMatrix'] and result['strengthPassed'] and result['wins'] == 6 and result['timeouts'] == 0
prior = u.js(P / 'history/head-current-awake/strength-summary.json')
assert prior['fullMatrix'] and prior['wins'] == 18 and prior['strengthPassed']
old = {r['path']: r['sha256'] for r in prior['sourceBindings']}
new = {r['path']: r['sha256'] for r in result['sourceBindings']}
assert set(old) == set(new) and [n for n in old if old[n] != new[n]] == ['scripts/asLoader.swf']
proof = u.js(P / 'upstream-melee-integration/melee-loader-class-equivalence.json')
assert proof['beforeSha256'] == old['scripts/asLoader.swf'] and proof['afterSha256'] == new['scripts/asLoader.swf']
assert proof['allClassActionsByteIdentical'] and proof['existingRootSourceUnchanged']
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
for name in ['head-c4-bindings-during-r18-preparation.json', 'prepare-head-c4-integration.py',
             'run-head-c4-integration.ps1', 'head-c4-progress.py', 'analyze-head-c4-integration.py',
             'collect-head-c4-complete.py', 'collect-head-c4.log']:
    package.copy(O / name, 'history/head-c4-integration-awake/support/' + name)
readme = R / 'tools/cf6-headbot-assets/README.md'
package.copy(readme, 'history/head-c4-integration-awake/support/README-before-C4-integration.md')
text = readme.read_text('utf8')
line = next(line for line in text.splitlines() if line.startswith('当前隔离候选已完成 30／60／99'))
new_line = '30／60／99 级、双方换位各三次的完整十八场在 C3 公共加载器与 R4 隔离 Host 候选上执行，全部自然获胜、无超时；下表对应这十八场的实际身份。合并上游冷兵器输入帮助函数后，C4 加载器另做三档等级双方各一次的六场集成复验，同样全部自然获胜、无超时。两轮候选身份、资源一致性、存档保护、退出与全程显示观察均通过，逐场见[完整十八场](../cf6-elder-assets/evidence/20261017-calibration/history/head-current-awake/strength-summary.json)与[C4 六场集成复验](../cf6-elder-assets/evidence/20261017-calibration/history/head-c4-integration-awake/strength-summary.json)。全部历史与失败样本见[校准汇总](../cf6-elder-assets/evidence/20261017-calibration/summary.json)，长老校准与提交仍在继续。'
text = text.replace(line, new_line)
line = next(line for line in text.splitlines() if line.startswith('有限的十八场验证不保证'))
new_line = '两轮对战分别保留各自身份，有限样本不保证所有随机局面必胜。十三项大头绑定输入中只有公共加载器发生变化；C3→C4 的 726 个已编译类动作逐字相同，既有共享根脚本在去掉新增帮助函数后也相同。老头 R18 准备期间，这十三项大头输入均保持不变。七个蓄光画面由此前原生捕获及图形等价证明支持，本轮未重新截图。标准入口、低配机器和玩家手感仍待分别验收。'
text = text.replace(line, new_line)
readme.write_text(text, 'utf8')
package.copy(P / 'summary.json', 'progress-snapshots/20261018-before-head-c4-complete.json')
summary = u.js(P / 'summary.json')
summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(), sealed=False, allGoalsMet=False)
summary['headbot'].update(currentExperiment=result['experiment'], currentExperimentState='completed; six-fight C4 integration passed',
                          currentCandidateMatrixRows=6, currentCandidateFullMatrix=False,
                          retainedFullMatrixRows=18, goalMet=True, subsequentMergedLoaderIntegrationPending=False,
                          mergedLoaderIntegration={'report': 'history/head-c4-integration-awake/strength-summary.json',
                                                   'rows': 6, 'wins': 6, 'timeouts': 0, 'fullMatrix': False,
                                                   'classEquivalence': 'upstream-melee-integration/melee-loader-class-equivalence.json',
                                                   'onlyChangedBoundInput': 'scripts/asLoader.swf'},
                          boundary='Retain the actual C3 eighteen-fight full matrix plus the separate C4 six-fight integration and exact shared-class/source impact proof. Do not relabel the eighteen fights as C4 executions.')
summary['nextStep'].update(headCurrentMatrixState='C3 full eighteen wins retained; C4 separate six wins and class/source impact proof complete')
summary['history'] = [{k: v for k, v in run.items() if k in ['label', 'experiment', 'rows', 'qualified', 'strengthAccepted', 'displayQualified', 'selectedForHeadbot', 'selectedForCurrentHeadbot', 'selectedForHeadbotIntegration', 'boundary']} for run in state['runs']]
summary['historyRows'] = sum(run['rows'] for run in state['runs'])
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'headFullMatrixRetained': 18, 'separateCurrentLoaderIntegrationWins': 6,
                  'historyRows': summary['historyRows'], 'allGoalsMet': False}))
