from pathlib import Path
import datetime,importlib.util,json
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py');u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
assert not(P/'integrity.json').exists()
label='r22-full-awake';base='history/'+label+'/'
analysis=u.js(P/base/'acceptance-summary.json');net=u.js(P/base/'phase-aware-summary.json')
prior_zero_win=u.js(P/base/'prior-zero-win-acceptance-summary.json')
assert prior_zero_win['profile']=='high-level-beast-near-death-exusiai-net-hp-v1' and prior_zero_win['fullMatrix']
assert analysis['fullMatrix']and len(analysis['rows'])==36 and analysis['expectedLevels']==[60,80,100]
assert analysis['profile']=='high-level-beast-near-death-exusiai-net-hp-minority-wins-v2'
assert u.js(P/base/'display-assessment.json')['qualified']
diagnostics=u.js(O/'r22-complete-reactive-analysis.json')
assert diagnostics['wholeExperimentFinal']and len(diagnostics['rows'])==36
assert all(row['observedStartRange']==750 and row['observedShieldCapacityScale']==.5 and row['observedBeamShieldCapacityScale']==.2 and row['observedReactiveShieldCapacityScale']==.75 and row['observedPulseMissingHpRatio']==1/6400 for row in diagnostics['rows'])
counts={'wins':sum(r['status']=='finished'and r['won']for r in analysis['rows']),
        'losses':sum(r['status']=='finished'and r['lost']for r in analysis['rows']),
        'draws':sum(r['status']=='finished'and not r['won']and not r['lost']for r in analysis['rows']),
        'timeouts':sum(r['status']=='timeout'for r in analysis['rows'])}
assert sum(counts.values())==36
state=u.js(O/'evidence-history-assembly.json');package=u.Package(P);package.mapping=state['mapping']
files=[('cf6-cal-r22-full-20261018-private-diagnostics/index-18-groups-18-shards-time-bound.json','diagnostic-events.json'),
       ('r22-complete-reactive-analysis.json','reactive-diagnostics-analysis.json'),
       ('r22-complete-near-death-observations.json','beast-near-death-observations.json'),
       ('r22-beast-acceptance-addendum.json','beast-acceptance-addendum.json'),
       ('r22-exusiai-acceptance-addendum.json','acceptance-addendum.json')]
for source,target in files:package.copy(O/source,base+target)
for name in ['preserve-arena-group-diagnostics.py','analyze-reactive-pilot.py','extract-beast-near-death.py',
             'collect-r22-complete.py','collect-r22-full.log','check-r22-beast-acceptance.py',
             'r22-beast-acceptance-check-v2.json','r22-beast-acceptance-check-v3.json']:
    package.copy(O/name,base+'support/'+name)
for name in ['check-r22-exusiai-acceptance.py','r22-exusiai-acceptance-check.json','record-r22-exusiai-acceptance.py']:
    package.copy(O/name,base+'support/'+name)
package.copy(R/'tools/cf6-elder-assets/assess-arena-targets.py',base+'support/assess-arena-targets.py')
package.copy(R/'tools/cf6-elder-assets/analyze-arena.py',base+'support/analyze-arena.py')
for row in u.js(P/base/'plan/input-identity.json')['sourceBindings']:assert u.sha(R/row['path'])==row['sha256'],row['path']
for run in state['runs']:
    if run['label']==label:run.update(strengthAccepted=analysis['strengthPassed'],historicalNetHpStrengthAccepted=net['strengthPassed'],priorZeroWinStrengthAccepted=prior_zero_win['strengthPassed'],selectedForCurrentElder=analysis['strengthPassed'],acceptanceProfile=analysis['profile'])
mechanism_path=P/'high-level-r22/summary.json';package.copy(mechanism_path,'progress-snapshots/r22-before-full-completion.json')
mechanism=u.js(mechanism_path);mechanism.update(status='candidate_executed; full_matrix_complete',fullMatrixAccepted=analysis['strengthPassed'],
    completedRows=36,outcomes=counts,acceptanceSummary='../history/'+label+'/acceptance-summary.json',
    historicalNetHpSummary='../history/'+label+'/phase-aware-summary.json',observedRageRows=sum(r['observedInitialFormRage']for r in analysis['rows']))
mechanism_path.write_text(json.dumps(mechanism,ensure_ascii=False,indent=2),'utf8')
package.copy(P/'summary.json','progress-snapshots/20261018-before-r22-full-complete.json')
summary=u.js(P/'summary.json');summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sealed=False,allGoalsMet=False)
summary['elder'].update(currentExperimentState='full matrix complete; accepted'if analysis['strengthPassed']else'full matrix complete; target not met',
    goalMet=analysis['strengthPassed'],latestCompletedBatch=base+'acceptance-summary.json',latestCompletedBatchExecutionQualified=True,
    latestCompletedBatchStrengthPassed=analysis['strengthPassed'],latestGroups=analysis['groups'],selectedReport=base+'acceptance-summary.json',
    selectedRows=36,selectedExperiment='cf6-cal-r22-full-20261018',latestWins=counts['wins'],latestLosses=counts['losses'],latestDraws=counts['draws'],latestTimeouts=counts['timeouts'])
summary['nextStep']['elderNextIteration']='Fresh four-suite native regression, current Host source tests and Head C5 full matrix remain.'if analysis['strengthPassed']else'Assess the complete preserved matrix before any new bounded tuning.'
summary['history']=[{k:v for k,v in run.items()if k in ['label','experiment','rows','qualified','strengthAccepted','displayQualified','selectedForHeadbot','selectedForCurrentHeadbot','selectedForHeadbotIntegration','selectedForCurrentElder','acceptanceProfile','historicalNetHpStrengthAccepted','priorZeroWinStrengthAccepted','boundary']}for run in state['runs']]
summary['historyRows']=sum(run['rows']for run in state['runs'])
(P/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
state['mapping']=package.mapping;(O/'evidence-history-assembly.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'strengthPassed':analysis['strengthPassed'],'outcomes':counts,'historyRows':summary['historyRows'],'sealed':False}))
