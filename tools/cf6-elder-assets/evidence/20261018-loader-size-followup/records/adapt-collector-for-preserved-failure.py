from pathlib import Path
import ast
D=Path.cwd()/'tmp/cf6-combat-calibration-20261017/loader-size-followup'
s=(D/'collect-followup.py').read_text('utf8')
def change(a,b):
    global s
    assert s.count(a)==1,a
    s=s.replace(a,b)
change('reports={}\nfor kind,expected in [(\'head\',6),(\'elder\',12)]:\n    exp=f\'cf6-loader-c6-{kind}-20261018\'\n    report,rows,identities=pkg.collect(kind,exp,D/f\'arena-{kind}\',require_qualified=True)', '''reports={};raw_parts={}
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
        assert report['status']=='completed' and not report['qualified']
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
    raw_parts[part]=rows''')
change("identity=load(D/f'arena-{kind}/input-identity.json')", "identity=load(D/plan_name/'input-identity.json')")
change("    assert {(r['rivalUnitId'],r['level'],r['side']) for r in detail}==wanted", "    if kind=='head':assert {(r['rivalUnitId'],r['level'],r['side']) for r in detail}==wanted")
change("result={'qualified':True,'integrationOnly':True", "result={'qualified':part!='elder-primary','completedRowsVerified':True,'originalExecutionReportQualified':report['qualified'],'integrationOnly':True")
change("    u.jput(Q/kind/'all-results.json',rows);u.jput(Q/kind/'integration-summary.json',result)\n    reports[kind]=result", '''    u.jput(Q/part/'all-results.json',rows);u.jput(Q/part/'integration-summary.json',result)
    reports[part]=result
    pkg.tree(S,'display-scopes/'+scope_name)
combined=reports['elder-primary']['details']+reports['elder-retry']['details']
wanted={(r,l,s) for r in [78,361] for l in [60,80,100] for s in ['blue','red']}
assert len(combined)==12 and {(r['rivalUnitId'],r['level'],r['side']) for r in combined}==wanted
assert reports['elder-primary']['sourceBindings']==reports['elder-retry']['sourceBindings']
reports['elder']={**reports['elder-primary'],'qualified':True,'combinedIntegration':True,
    'experiments':['cf6-loader-c6-elder-20261018','cf6-loader-c6-b100-retry1-20261018'],
    'rows':12,'wins':sum(x['won'] for x in combined),'losses':sum(x['lost'] for x in combined),
    'details':combined,'endUtc':reports['elder-retry']['endUtc'],
    'runtimeIdentities':reports['elder-primary']['runtimeIdentities']+reports['elder-retry']['runtimeIdentities'],
    'failedAttemptRetained':True,'sourceReports':['../elder-primary/integration-summary.json','../elder-retry/integration-summary.json'],
    'boundary':'Twelve valid integration rows from the original ten completed cases plus a fresh isolated pair. The original primary experiment remains unqualified due to a pre-transport ownership probe failure and is preserved. No full strength matrix or blind same-session replay is claimed.'}
u.jput(Q/'elder/all-results.json',raw_parts['elder-primary']+raw_parts['elder-retry'])
u.jput(Q/'elder/integration-summary.json',reports['elder'])''')
change("pkg.tree(S,'display-scope')", "assert S.name=='display-qualified-20261018-r11'")
change("    'displayCleanup':closure,'formalRuntimePromoted':False,", "    'displayCleanup':closure,'formalRuntimePromoted':False,'retainedFailedAttempts':1,'failedAttemptAssessment':'records/failed100-assessment.json','displayScopes':['display-scopes/display-qualified-20261018-r10','display-scopes/display-qualified-20261018-r11'],")
ast.parse(s)
with (D/'collect-followup-v2.py').open('x',encoding='utf8') as f:f.write(s)
print('Collector prepared: primary failed run remains unqualified; ten valid rows plus fresh isolated pair cover twelve cases.')
