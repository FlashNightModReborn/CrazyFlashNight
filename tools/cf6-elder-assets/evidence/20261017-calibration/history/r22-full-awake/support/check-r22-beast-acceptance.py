from pathlib import Path
import copy,importlib.util,json
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
spec=importlib.util.spec_from_file_location('acceptance',R/'tools/cf6-elder-assets/assess-arena-targets.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
analysis={'expectedLevels':[60,80,100],'fullMatrix':True,'strengthPassed':False,'rows':[],'groups':[]}
diagnostics={'rows':[]}
for rival in [78,361]:
    for level in [60,80,100]:
        for side in ['blue','red']:
            for repeat in range(3):
                identity={'runId':f'synthetic-{rival}-{level}-{side}-{repeat}','rival':rival,'level':level,'side':side,'status':'finished','frames':100}
                analysis['rows'].append({**identity,'opponentPhaseSpawns':0,'lost':True,'won':False,'ownPhaseValid':True,'errors':[]})
                diagnostics['rows'].append({**identity,'initialPhaseRageLeech':1 if rival==78 else 0,'unknownPhaseRageLeech':0,
                    'sourceArchiveSha256':'fixture','sourceEntrySha256':'fixture','lineNumber':1,'resultSha256':'fixture'})
        value=.4 if rival==78 else .65
        analysis['groups'].append({'rival':rival,'level':level,'netLoss':{'mean':value,'median':value},'meetsGroupTarget':rival==361})
checks=[]
def verify(name,ok):
    assert ok,name
    checks.append(name)
verify('Complete synthetic matrix accepts Beast observed rage even when net HP is below the previous interval',m.assess(analysis,diagnostics)['strengthPassed'])
a=copy.deepcopy(analysis);d=copy.deepcopy(diagnostics)
for row in a['rows']+d['rows']:row['runId']=row['runId'].replace(str(row['rival'])+'-','')
verify('Run IDs may repeat across rivals and are joined with full fight identity',m.assess(a,d)['strengthPassed'])
for field,value,name in [('initialPhaseRageLeech',0,'No observed rage and no successor fails'),('unknownPhaseRageLeech',1,'Unknown identity is rejected')]:
    d=copy.deepcopy(diagnostics);d['rows'][0][field]=value
    if field=='unknownPhaseRageLeech':
        try:m.assess(analysis,d)
        except ValueError:checks.append(name)
        else:raise AssertionError(name)
    else:verify(name,not m.assess(analysis,d)['strengthPassed'])
a=copy.deepcopy(analysis);d=copy.deepcopy(diagnostics);a['rows'][0]['opponentPhaseSpawns']=1;d['rows'][0]['initialPhaseRageLeech']=0
r=m.assess(a,d);verify('Successor proves first-form defeat without falsely claiming observed rage',r['strengthPassed'] and not r['rows'][0]['observedInitialFormRage'] and r['rows'][0]['beastProgressEvidence']=='successor_spawned')
for status,lost,won,label in [('finished',False,True,'win'),('finished',False,False,'draw'),('timeout',False,False,'timeout')]:
    a=copy.deepcopy(analysis);d=copy.deepcopy(diagnostics)
    a['rows'][0].update(status=status,lost=lost,won=won);d['rows'][0]['status']=status
    verify('Beast '+label+' fails',not m.assess(a,d)['strengthPassed'])
for key,value in [('mean',.49),('median',.81)]:
    a=copy.deepcopy(analysis);a['groups'][3]['netLoss'][key]=value
    verify('EXUSIAI '+key+' outside interval fails',not m.assess(a,diagnostics)['strengthPassed'])
for action,label in [('missing','Missing diagnostic rejected'),('duplicate','Duplicate diagnostic rejected'),('extra','Extra diagnostic rejected'),('side','Mismatched side rejected')]:
    d=copy.deepcopy(diagnostics)
    if action=='missing':d['rows'].pop()
    elif action=='duplicate':d['rows'].append(copy.deepcopy(d['rows'][0]))
    elif action=='extra':d['rows'].append({**d['rows'][0],'runId':'synthetic-extra'})
    else:d['rows'][0]['side']='red'
    try:m.assess(analysis,d)
    except ValueError:checks.append(label)
    else:raise AssertionError(label)
a=copy.deepcopy(analysis);a['fullMatrix']=False
verify('Partial matrix cannot pass',not m.assess(a,diagnostics)['strengthPassed'])
a=copy.deepcopy(analysis);a['expectedLevels']=[30,60,99]
try:m.assess(a,diagnostics)
except ValueError:checks.append('Historical level profile cannot silently become current acceptance')
else:raise AssertionError('Wrong levels accepted')
notices={'rows':[{**{k:r[k]for k in ('runId','rival','level','side','status','frames','resultSha256')},
                 'notifications':[{'syntheticFixture':True}]if r['rival']==78 else []}for r in diagnostics['rows']]}
d=copy.deepcopy(diagnostics)
for row in d['rows']:row['initialPhaseRageLeech']=0
result=m.assess(analysis,d,notices)
verify('Observed unique notifications qualify rage without any later rage hit',result['strengthPassed'] and result['rows'][0]['observedInitialFormRageByNotification'] and not result['rows'][0]['observedInitialFormRageByHit'])
for action in ['missing','hash','duplicate']:
    n=copy.deepcopy(notices)
    if action=='missing':n['rows'].pop()
    elif action=='hash':n['rows'][0]['resultSha256']='different'
    else:n['rows'].append(copy.deepcopy(n['rows'][0]))
    try:m.assess(analysis,d,n)
    except ValueError:checks.append('Notification '+action+' identity rejected')
    else:raise AssertionError(action+' notification accepted')
report={'ok':True,'checks':checks,'count':len(checks),'fixtureKind':'Explicitly synthetic in-memory assessment cases; no historical battle rows relabeled or changed.'}
with(O/'r22-beast-acceptance-check-v3.json').open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps(report))
