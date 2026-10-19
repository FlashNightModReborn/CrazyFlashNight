"""Release the authorized temporary display hold before post-test documentation work."""
from pathlib import Path
import argparse,datetime,importlib.util,json,time
parser=argparse.ArgumentParser();parser.add_argument('--scope',required=True);parser.add_argument('--last-experiment',required=True);a=parser.parse_args()
assert all('/'not in v and '\\'not in v and v not in ['.','..']for v in [a.scope,a.last_experiment])
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration';S=O/a.scope
load=lambda p:json.loads(p.read_text('utf-8-sig'))
report=load(R/'tmp/arena-worker-experiments'/a.last_experiment/'experiment-report.json')
assert report['status']=='completed'and report['qualified']
assert load(S/'authorization.json')['authorized']
requested=datetime.datetime.now(datetime.timezone.utc).isoformat()
with(S/'stop').open('x',encoding='utf8')as f:f.write('Last authorized live test completed; release the temporary hold before documentation and Git closeout.\n')
for attempt in range(20):
    events=[json.loads(line)for line in(S/'display-state.jsonl').read_text('utf8').splitlines()]
    if any(e['event']=='subscription_ended'for e in events):break
    time.sleep(.5)
else:raise RuntimeError('Display release has not been observed; preserve this request and inspect the helper')
released=[e for e in events if e['event']=='display_request_released'];ended=[e for e in events if e['event']=='subscription_ended']
assert len(released)==len(ended)==1 and released[0]['result']!=0 and ended[0]['result']==0
assert not any(e['event']=='scope_failed'for e in events)
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py');u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
assert not(P/'integrity.json').exists();state=u.js(O/'evidence-history-assembly.json');package=u.Package(P);package.mapping=state['mapping']
package.tree(S,'display-scopes/final-completed')
closure={'ok':True,'lastExperiment':a.last_experiment,'lastExperimentCompletedAt':report['completedAt'],
    'releaseRequestedAtUtc':requested,'release':released[0],'subscriptionEnd':ended[0],
    'displayHoldActive':False,'persistentPowerPlanChanged':False,
    'boundary':'The temporary display hold was released after the final live test and before documentation, evidence sealing or Git closeout.'}
u.jput(P/'display-scopes/final-completed/closure.json',closure);u.jput(O/'test-round-display-cleanup.json',closure)
package.copy(P/'summary.json','progress-snapshots/before-final-display-release.json')
summary=u.js(P/'summary.json');summary['nextStep']['displayObservationActive']=False;summary['testDisplayCleanup']='display-scopes/final-completed/closure.json'
(P/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
state['mapping']=package.mapping;(O/'evidence-history-assembly.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'ok':True,'displayHoldActive':False,'lastExperiment':a.last_experiment}))
