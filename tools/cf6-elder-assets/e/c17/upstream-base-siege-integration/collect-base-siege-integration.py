from pathlib import Path
import datetime, hashlib, importlib.util, json

R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';F=O/'upstream-base-siege-integration';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py');u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
assert not (P/'integrity.json').exists()
assert u.js(O/'native-cleanup-after-r19-c5.json')['ok']
assert u.js(O/'base-siege-loader-class-scope.json')['qualified']
assert u.js(F/'registration-verification.json')['ok']
for name in ['elder-asset','audio','player-aim']:
    result=u.js(O/'native-r19-c5-integration'/name/'result.json');assert result['exitCode']==0 and result['bindingsUnchanged']
state=u.js(O/'evidence-history-assembly.json');package=u.Package(P);package.mapping=state['mapping'];base='upstream-base-siege-integration/'
package.tree(O/'build-integrated-base-siege-loader',base+'publish')
for kind in ['base','working','index','upstream']:
    package.tree(F/kind,base+'preserved-'+kind)
for name in ['preservation.json','integration.json','before-registration.zip','before-registration-index.json','registration-source-changes.json','registration-verification.json',
             'head-balance-write.log','head-balance-check.log','elder-balance-write.log','elder-balance-check.log','catalog-generate.log','catalog-check.log','head-resource-check.log','head-resource-verify.log']:
    package.copy(F/name,base+name)
package.copy(F/'lock-recovery/receipt.json',base+'git-lock-recovery.json')
for name in ['base-siege-loader-class-scope.json','class-closure-r19-c5.json','compare-base-siege-loader-classes.js','integrate-upstream-base-siege.py','relocate-cf6-registration.py','collect-base-siege-integration.py']:
    package.copy(O/name,base+name)
source_paths=['scripts/类定义/org/flashNight/arki/scene/'+name for name in ['BaseSiegeController.as','BaseSiegeRules.as','StageManager.as','WaveSpawner.as']]
source_paths+=['scripts/逻辑/关卡系统/关卡系统_lsy_关卡回调函数.as','scripts/逻辑/关卡系统/关卡系统_lsy_无限过图.as',
              'tools/cf6-headbot-assets/balance.py','tools/cf6-headbot-assets/arena-plan.js','tools/cf6-headbot-assets/README.md',
              'tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/arena-plan.js','tools/cf6-elder-assets/analyze-arena.py','tools/cf6-elder-assets/README.md',
              'tools/cf6-audio/README.md','data/units/units.json','launcher/web/modules/arena-unit-catalog.js']
package.freeze(source_paths,base+'integrated-source.zip')
private=[]
for name in ['working.patch','index.patch','status-before.txt','index-before.bin','lock-recovery/index-before.bin','lock-recovery/original-index.lock']:
    path=F/name;h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(8*1024*1024),b''):h.update(chunk)
    private.append({'file':name,'bytes':path.stat().st_size,'sha256':h.hexdigest()})
u.jput(P/base/'private-preservation.json',{'files':private,'boundary':'Full Git index and broad staged/working patches remain private local recovery material; scoped original files and relevant source history are preserved separately in this package.'})
u.jput(P/base/'summary.json',{'head':'937e1815465a5c1c01376b1a947787c0e1b9de8f','fastForwardCompleted':True,'nativeC5Passed':True,
    'upstreamUnitRecordsPreserved':True,'publishedCompanionIds':[470,471],'currentCf6Ids':[472,473,474],
    'priorCf6Ids':[470,471,472],'historicalRowsRewritten':False,'currentLoaderSha256':u.sha(R/'scripts/asLoader.swf'),
    'pendingHeadCurrentMatrixRows':18,'pendingElderCurrentMatrixRows':36,
    'boundary':'Scene startup changed and registrations were relocated to avoid published companions. Historical C3/C4 rows retain their original identities; final qualification requires fresh complete matrices on current IDs.'})
package.copy(P/'summary.json','progress-snapshots/20261018-before-base-siege-integration.json')
summary=u.js(P/'summary.json');summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sealed=False,allGoalsMet=False)
summary['headbot'].update(goalMet=False,currentRegisteredUnitId=472,currentCandidateMatrixRows=0,currentCandidateFullMatrix=False,
    currentExperimentState='current C5 and relocated registration require full eighteen-row matrix',subsequentMergedLoaderIntegrationPending=True,currentC5FullMatrixPending=True)
summary['elder'].update(currentRegisteredUnitId=473,currentSuccessorUnitId=474)
summary['upstreamBaseSiegeIntegration']=base+'summary.json'
for row in summary['currentBindings']:row.update(bytes=(R/row['path']).stat().st_size,sha256=u.sha(R/row['path']))
(P/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
state['mapping']=package.mapping;(O/'evidence-history-assembly.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'integrationCollected':True,'currentCf6Ids':[472,473,474],'head18AndElder36StillPending':True,'sealed':False}))
