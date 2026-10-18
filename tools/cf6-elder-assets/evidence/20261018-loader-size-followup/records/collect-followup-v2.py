"""Collect only the completed C6 follow-up; never mutate the sealed C5 package."""
from pathlib import Path
import datetime, hashlib, importlib.util, json, re, subprocess

R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';D=O/'loader-size-followup'
P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
Q=R/'tools/cf6-elder-assets/evidence/20261018-loader-size-followup'
S=O/'display-qualified-20261018-r10'
load=lambda p:json.loads(p.read_text('utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
stamp=lambda s:datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py')
u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
assert not Q.exists(),'Preserve existing follow-up evidence'
assert load(D/'native/completion.json')['ok'] and load(D/'inputs-after.json')['unchanged']
assert load(D/'change-analysis.json')['qualified']
assert load(D/'split-control-flow.json')['qualified']
assert load(D/'boot-proof/summary.json')['qualified'] and load(D/'boot-proof/summary.json')['boots']==9
near_death=load(D/'beast-near-death.json')
assert near_death['wholeExperimentFinal'] and len(near_death['rows'])==12
near_rows={(x['rival'],x['level'],x['side'],x['runId']):x for x in near_death['rows']}
assert sha(R/'scripts/asLoader.swf')==load(D/'change-analysis.json')['c6LoaderSha256']
events=[json.loads(s) for s in (S/'display-state.jsonl').read_text('utf8').splitlines()]
released=[e for e in events if e['event']=='display_request_released']
ended=[e for e in events if e['event']=='subscription_ended']
assert len(released)==len(ended)==1 and released[0]['result']!=0 and ended[0]['result']==0
assert not any(e['event']=='scope_failed' for e in events)
native=(D/'native/flashlog.txt').read_text('utf-8-sig')
starts=re.findall(r'^FocusedTestRunId boot-sequencer Start: (.+)$',native,re.M)
completes=re.findall(r'^FocusedTestRunId boot-sequencer Complete: (.+)$',native,re.M)
assert len(starts)==len(completes)==1 and starts[0].strip()==completes[0].strip()
assert native.count('=== BootSequencerTest: 91 passed, 0 failed ===')==1
assert native.count('========== BootstrapHandshakeTest END: 12/12 passed, 0 failed ==========')==1
runner_bytes=(D/'boot-sequencer-runner.log').read_bytes()
runner_text=runner_bytes.decode('utf16' if runner_bytes.startswith(b'\xff\xfe') else 'utf-8-sig')
assert '32K retry=0, compiler 0/0' in runner_text
prior_index=load(P/'integrity.json')
assert sha(P/'integrity.json')=='9bf2da89fbbaa07b62bbdd2d7b0f8a66ea49376b62a7283a042e9ba578857d5c'
for row in prior_index['files']:
    assert u.sha(P/row['path'])==row['sha256'],row['path']
prior={'qualified':True,'commit':'dabd11a89570125b6fe2125aa45b5ccaf2d60cd2','integritySha256':sha(P/'integrity.json'),
       'filesVerified':len(prior_index['files']),'totalBytes':prior_index['totalBytes'],
       'boundary':'Every frozen C5 file remains unchanged. C5 live-root validation is historical after replacing the current loader with C6.'}
u.jput(D/'prior-c5-retention.json',prior)
Q.mkdir(parents=True)
pkg=u.Package(Q)
reports={};raw_parts={};copied_scopes=set()
assert load(D/'failed100-assessment.json')['qualifiedForFreshIsolatedRetry']
for part,kind,expected,exp,plan_name,scope_name in [
    ('head','head',6,'cf6-loader-c6-head-20261018','arena-head','display-qualified-20261018-r10'),
    ('elder-primary','elder',10,'cf6-loader-c6-elder-20261018','arena-elder','display-qualified-20261018-r10'),
    ('elder-retry','elder',2,'cf6-loader-c6-b100-retry1-20261018','arena-elder-retry','display-qualified-20261018-r11')]:
    S=O/scope_name
    events=[json.loads(x) for x in (S/'display-state.jsonl').read_text('utf8').splitlines()]
    released=[e for e in events if e['event']=='display_request_released']
    ended=[e for e in events if e['event']=='subscription_ended']
    assert len(released)==len(ended)==1 and released[0]['result']!=0 and ended[0]['result']==0
    assert not any(e['event']=='scope_failed' for e in events)
    report,rows,identities=pkg.collect(part,exp,D/plan_name,require_qualified=part!='elder-primary')
    if part=='elder-primary':
        assert report['status']=='unqualified' and not report['qualified'] and not report['errors']
        failures=[]
        for g in report['groups']:
            assert g['globalSaveUnchanged'] and g['seedSourcesUnchanged']
            for o in g['outcomes']:
                assert o['cleanupVerified'] and o['protectedSavesVerified'] and o['runtimeResourcesVerified']
                receipt=u.js(o['expectedReceiptPath'])
                assert receipt['runtimeUnchanged'] and receipt['resourcesUnchanged']
                if o['status']!='completed':
                    failures.append(g['groupId'])
                    assert receipt['resultPath'] is None and receipt['rows']==0
                    assert len(receipt['errors'])==2 and all(x['message']=='Worker endpoint ownership probe unavailable; no credential was sent' for x in receipt['errors'])
                else:assert not receipt['errors']
        assert failures==['beastking-level100']
    raw_parts[part]=rows
    assert len(rows)==expected
    begin=stamp(load(R/'tmp/arena-worker-experiments'/exp/'execution-started.json')['startedAt'])
    end=stamp(report['completedAt'])
    observed=[e for e in events if e['event']=='state_observed']
    assert [e for e in observed if stamp(e['utc'])<=begin][-1]['state']==1
    assert all(e['state']==1 for e in observed if begin<=stamp(e['utc'])<=end)
    assert stamp(released[0]['utc'])>=end
    coverage=[e for e in events if stamp(e['utc'])<=begin][-1:]+[e for e in events if begin<stamp(e['utc'])<end]+[e for e in events if stamp(e['utc'])>=end][:1]
    gaps=[(stamp(b['utc'])-stamp(a['utc'])).total_seconds() for a,b in zip(coverage,coverage[1:])]
    assert gaps and all(0<=x<=30 for x in gaps)
    identity=load(D/plan_name/'input-identity.json')
    for b in identity['sourceBindings']:
        assert sha(R/b['path'])==b['sha256'],b['path']
    seen=set();detail=[]
    for row in rows:
        c=row['authorityContext']; side=c['candidateSide'];other='red' if side=='blue' else 'blue'
        key=(c['rivalUnitId'],c['level'],side,row['runId']);assert key not in seen;seen.add(key)
        assert c['sourceBindings']==identity['sourceBindings']
        assert row['status']=='finished' and row['winner'] in [side,other] and not row['errors']
        winning=row[row['winner']]; losing=row[other if row['winner']==side else side]
        assert winning['aliveCount']>0 and winning['remainHp']>0 and losing['aliveCount']==0
        own=[x for x in row['spawnedUnits'] if x['side']==side]
        if kind=='head':
            assert c['candidateUnitId']==472 and c['rivalUnitId']==286
            assert row['winner']==side and not row['spawnedUnits'] and row['phaseSpawnCount']==0
        else:
            assert c['candidateUnitId']==473 and c['successorUnitId']==474
            assert len(own)==1 and own[0]['from']=='兵种473' and own[0]['unit']=='敌人-CF6老头机器人'
            if c['rivalUnitId']==78:
                evidence=near_rows[key]
                opponent_spawns=[x for x in row['spawnedUnits'] if x['side']==other]
                assert row['winner']==other
                assert len(evidence['notifications'])==1 or len(opponent_spawns)>0
        detail.append({'level':c['level'],'side':side,'rivalUnitId':c['rivalUnitId'],'runId':row['runId'],
            'won':row['winner']==side,'lost':row['winner']==other,'status':row['status'],'frames':row['frames'],'ownPhaseSpawns':len(own)})
    wanted={(r,l,s) for r in ([286] if kind=='head' else [78,361])
            for l in ([30,60,99] if kind=='head' else [60,80,100]) for s in ['blue','red']}
    if kind=='head':assert {(r['rivalUnitId'],r['level'],r['side']) for r in detail}==wanted
    result={'qualified':part!='elder-primary','completedRowsVerified':True,'originalExecutionReportQualified':report['qualified'],'integrationOnly':True,'fullStrengthMatrix':False,'experiment':exp,'rows':len(rows),
            'wins':sum(x['won'] for x in detail),'losses':sum(x['lost'] for x in detail),'timeouts':0,
            'maximumObserverGapSeconds':max(gaps),'startUtc':begin.isoformat(),'endUtc':end.isoformat(),
            'runtimeIdentities':identities,'sourceBindings':identity['sourceBindings'],'details':detail,
            'boundary':'Current-loader boot/combat integration and protected-save/cleanup checks. Complete calibration remains the separately frozen C5 18+36 matrix.'}
    u.jput(Q/part/'all-results.json',rows);u.jput(Q/part/'integration-summary.json',result)
    reports[part]=result
    if scope_name not in copied_scopes:
        pkg.tree(S,'display-scopes/'+scope_name);copied_scopes.add(scope_name)
combined=reports['elder-primary']['details']+reports['elder-retry']['details']
wanted={(r,l,s) for r in [78,361] for l in [60,80,100] for s in ['blue','red']}
assert len(combined)==12 and {(r['rivalUnitId'],r['level'],r['side']) for r in combined}==wanted
assert reports['elder-primary']['sourceBindings']==reports['elder-retry']['sourceBindings']
reports['elder']={**reports['elder-primary'],'qualified':True,'combinedIntegration':True,
    'experiments':['cf6-loader-c6-elder-20261018','cf6-loader-c6-b100-retry1-20261018'],
    'rows':12,'wins':sum(x['won'] for x in combined),'losses':sum(x['lost'] for x in combined),
    'details':combined,'endUtc':reports['elder-retry']['endUtc'],
    'maximumObserverGapSeconds':max(reports['elder-primary']['maximumObserverGapSeconds'],reports['elder-retry']['maximumObserverGapSeconds']),
    'runtimeIdentities':reports['elder-primary']['runtimeIdentities']+reports['elder-retry']['runtimeIdentities'],
    'failedAttemptRetained':True,'sourceReports':['../elder-primary/integration-summary.json','../elder-retry/integration-summary.json'],
    'boundary':'Twelve valid integration rows from the original ten completed cases plus a fresh isolated pair. The original primary experiment remains unqualified due to a pre-transport ownership probe failure and is preserved. No full strength matrix or blind same-session replay is claimed.'}
u.jput(Q/'elder/all-results.json',raw_parts['elder-primary']+raw_parts['elder-retry'])
u.jput(Q/'elder/integration-summary.json',reports['elder'])
closure={'qualified':True,'displayHoldActive':False,'persistentPowerPlanChanged':False,
         'released':released[0],'subscriptionEnded':ended[0],'lastLiveCompletedAt':reports['elder']['endUtc']}
u.jput(D/'display-cleanup.json',closure)
assert S.name=='display-qualified-20261018-r11'
pkg.tree(D,'records')
pkg.copy(O/'prepare-loader-size-followup.py','tools/prepare-loader-size-followup.py')
pkg.copy(O/'split-loader-communication.py','tools/split-loader-communication.py')
for name in ['scripts/asLoaderManifest/frame3.as','scripts/asLoaderManifest/_collapsed_frame.as']:
    pkg.copy(R/name,'current-source/'+name)
summary={'schema':'cf6-loader-size-followup.v1','qualified':True,
    'recordedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'baseCommit':prior['commit'],
    'reason':'Repair the existing AS2 artifact ownership function-size CI gate without changing combat tuning.',
    'loaderC6':load(D/'publish/identity.json'),'functionSize':{'priorF3':60668,'f3_1':45559,'f3_2':15472,'largestCurrent':53041,'maximumAllowedExclusive':60000},
    'compiledClasses':{'unchanged':727,'changed':['org.flashNight.neur.Server.ServerManager'],'added':0,'removed':0},
    'nativeBoot':{'passed':103,'failed':0,'runId':starts[0].strip(),'compilerErrors':0,'compilerWarnings':0,'retry32k':0},
    'actualCandidateBoots':{'countWithValidatedFightResults':9,'totalHostAttempts':10,'eventOrderEquivalentToGolden':True,'proof':'records/boot-proof/summary.json'},
    'currentBeastObservation':{'rows':6,'naturalLosses':6,'observedRageNotifications':near_death['observedBeastRageNotifications'],'proof':'records/beast-near-death.json'},
    'headIntegration':{k:reports['head'][k] for k in ['rows','wins','losses','timeouts','fullStrengthMatrix']},
    'elderIntegration':{k:reports['elder'][k] for k in ['rows','wins','losses','timeouts','fullStrengthMatrix']},
    'priorC5Calibration':{'path':'../20261017-calibration','headRows':18,'headWins':18,'elderRows':36,'elderWins':2,'elderLosses':34,'filesUnchanged':prior},
    'displayCleanup':closure,'formalRuntimePromoted':False,'retainedFailedAttempts':1,'failedAttemptAssessment':'records/failed100-assessment.json','displayScopes':['display-scopes/display-qualified-20261018-r10','display-scopes/display-qualified-20261018-r11'],
    'boundary':'C6 is an actual executed isolated-candidate loader. No new complete strength matrix, formal Host runtime promotion, standard-entry acceptance, physical input/audio or low-end performance claim.'}
u.jput(Q/'summary.json',summary)
u.jput(D/'package-state.json',{'mapping':pkg.mapping})
print(json.dumps({'qualified':True,'head':summary['headIntegration'],'elder':summary['elderIntegration'],'priorFilesUnchanged':prior['filesVerified']}))
