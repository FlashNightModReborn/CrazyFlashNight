from pathlib import Path
import datetime, importlib.util, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
analysis = u.js(P / 'history/r20-pilot-awake/phase-aware-summary.json')
assert len(analysis['rows']) == 12 and not analysis['fullMatrix']
wins = sum(row['won'] for row in analysis['rows'])
timeouts = sum(row['status'] == 'timeout' for row in analysis['rows'])
losses = sum(row['lost'] for row in analysis['rows'])
diag = O / 'cf6-cal-r20-pilot-20261018-private-diagnostics/index-6-groups-6-shards-time-bound.json'
assert len(u.js(diag)['events']) == 36
derived = O / 'r20-complete-reactive-analysis.json'
with (O / 'r20-complete-reactive-analysis.log').open('x', encoding='utf8') as log:
    subprocess.run(['python', '-X', 'utf8', '-B', str(O / 'analyze-reactive-pilot.py'),
                    'cf6-cal-r20-pilot-20261018', '--diagnostics', str(diag), '--output', str(derived)],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
diagnostics = u.js(derived)
assert diagnostics['wholeExperimentFinal'] and len(diagnostics['rows']) == 12
assert all(row['observedStartRange'] == 750 and row['observedShieldCapacityScale'] == .5
           and len(row['selectorCallsAndOutOfRange']) == 2 for row in diagnostics['rows'])
for source, name in [(diag, 'diagnostic-events.json'), (derived, 'reactive-diagnostics-analysis.json'),
                     (O / 'preserve-arena-group-diagnostics.py', 'diagnostic-extractor.py'),
                     (O / 'analyze-reactive-pilot.py', 'diagnostic-analyzer.py'),
                     (O / 'collect-r20-pilot.log', 'collection.log'),
                     (O / 'collect-r20-complete.py', 'pilot-completion-collector.py')]:
    package.copy(source, 'history/r20-pilot-awake/' + name)
path = P / 'range-support-r20/summary.json'
package.copy(path, 'progress-snapshots/r20-native-before-pilot-complete.json')
mechanism = u.js(path)
mechanism.update(status='candidate_executed; exploratory_pilot_complete', exploratoryPilotCompleted=True,
                 pilotWins=wins, pilotTimeouts=timeouts, pilotLosses=losses,
                 exploratoryPilotAnalysis='../history/r20-pilot-awake/phase-aware-summary.json',
                 reactiveDiagnosticsAnalysis='../history/r20-pilot-awake/reactive-diagnostics-analysis.json',
                 fullMatrixAccepted=False, displayQualified=True, beamCapacityAccountingQualified=True)
path.write_text(json.dumps(mechanism, ensure_ascii=False, indent=2), 'utf8')
readme = R / 'tools/cf6-elder-assets/README.md'
package.copy(readme, 'progress-snapshots/README-before-r20-complete.md.txt')
readme_text = readme.read_text('utf-8-sig')
prior = '十二场独立试跑正在进行，仍须通过完整三十六场强度矩阵；'
assert readme_text.count(prior) == 1
readme_text = readme_text.replace(prior, f'十二场独立试跑已完成，为 {losses} 负、{wins} 胜、{timeouts} 超时；所有结果均保留，仍须通过完整三十六场强度矩阵；')
readme.write_text(readme_text, 'utf8', newline='\n')
package.copy(P / 'summary.json', 'progress-snapshots/20261018-before-r20-complete.json')
summary = u.js(P / 'summary.json')
summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(), sealed=False, allGoalsMet=False)
summary['elder'].update(currentRound='R20', currentExperiment='cf6-cal-r20-pilot-20261018',
                        currentExperimentState='exploratory pilot complete; no full acceptance matrix',
                        latestCompletedBatch='history/r20-pilot-awake/phase-aware-summary.json',
                        latestCompletedBatchExecutionQualified=True, latestCompletedBatchStrengthPassed=False,
                        latestGroups=analysis['groups'], nativeChecksPassed=2669)
summary['nextStep'].update(elderNextIteration='Use all twelve exploratory observations and literal selector/absorption diagnostics to decide whether to run a fresh thirty-six-row matrix or perform another bounded tuning step.')
for row in summary['currentBindings']:
    row.update(bytes=(R / row['path']).stat().st_size, sha256=u.sha(R / row['path']))
summary['history'] = [{k: v for k, v in run.items() if k in ['label', 'experiment', 'rows', 'qualified', 'strengthAccepted', 'displayQualified', 'selectedForHeadbot', 'selectedForCurrentHeadbot', 'selectedForHeadbotIntegration', 'boundary']} for run in state['runs']]
summary['historyRows'] = sum(run['rows'] for run in state['runs'])
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'pilotWins': wins, 'pilotLosses': losses, 'pilotTimeouts': timeouts, 'historyRows': summary['historyRows'], 'sealed': False}))
