from pathlib import Path
import datetime, importlib.util, json, re, zipfile

R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py')
u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
assert not (P/'integrity.json').exists()
assert (R/'tmp/arena-worker-experiments/cf6-cal-r19-pilot-20261018/execution-started.json').is_file()
expected={'elder-asset':[('Cf6ElderAssetTest',906),('Cf6ElderCombatEffectsTest',124),('Cf6RobotCombatTest elder',45)],
          'audio':[('Cf6AudioTest',340)],'player-aim':[('Cf6PlayerAimTest',1023)]}
for name,cases in expected.items():
    result=u.js(O/'native-r19-c5-integration'/name/'result.json')
    assert result['exitCode']==0 and result['bindingsUnchanged']
    trace=u.read(O/'native-r19-c5-integration'/name/'flashlog.txt').decode('utf-8-sig')
    for label,count in cases:assert re.search(re.escape(label)+r': '+str(count)+r' passed, 0 failed',trace),(name,label)
assert u.js(O/'native-cleanup-after-r19-c5.json')['ok']
assert u.js(O/'r19-scoped-data-impact.json')['qualified']
state=u.js(O/'evidence-history-assembly.json');package=u.Package(P);package.mapping=state['mapping']
base='output-distribution-r19/'
readme=R/'tools/cf6-elder-assets/README.md';package.copy(readme,base+'README-before-native-complete.md.txt')
text=readme.read_text('utf8')
old='R19 尚待新鲜编译、原生回归与独立对战，不能把 R18 的 2,436 项检查视为本轮通过。'
new='R19 已通过真实 CS6 编译及 2,438 项行为检查，包含盾强折算和三十帧真实补盾总量断言；十二场独立试跑正在进行，仍须通过三十六场完整验证。'
assert text.count(old)==1;readme.write_text(text.replace(old,new),'utf8')
paths=['tools/cf6-elder-assets/'+name for name in ['ElderAI.as','build.py','balance.py','balance-inputs.json','native-manifest.json','arena-plan.js','build-playtest-fixture.py','playtest-fixture-manifest.json','README.md']]
paths+=['scripts/类定义/org/flashNight/arki/unit/Action/Melee/'+name for name in ['Cf6ElderCombatEffectsTest.as','Cf6ElderAssetTest.as','Cf6PlayerAimTest.as']]
paths+=['scripts/test-runners/cf6-playtest/PlaytestFixture.as','scripts/run-cf6-elder-asset-tests.ps1',
        'scripts/类定义/org/flashNight/arki/component/Shield/AdaptiveShield.as','data/enemy_properties/CF6重制敌人.xml',
        'agentsDoc/testing-details.md','tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts',
        'tools/cf6-headbot-assets/balance.py','tools/cf6-headbot-assets/balance-inputs.json','tools/cf6-headbot-assets/arena-plan.js','tools/cf6-elder-assets/analyze-arena.py','data/units/units.json','launcher/web/modules/arena-unit-catalog.js']
package.freeze(paths,base+'source.zip')
for source,target in [('build-r19-elder','publish'),('native-r19-c5-integration','native-tests'),('native-cleanup-after-r19-c5-receipts','native-cleanup'),('native-r19-output-distribution','native-before-upstream'),('native-cleanup-after-r19-receipts','native-cleanup-before-upstream')]:package.tree(O/source,base+target)
for name in ['before-r19-output-distribution.zip','before-r19-output-distribution-index.json',
             'native-cleanup-after-r19.json','native-cleanup-after-r19-c5.json','elder-r19-image-equivalence.json','verify-elder-r19.log',
             'balance-r19-elder-write.log','balance-r19-elder-write-captured.log','balance-r19-elder-check.log',
             'regeneration-r19-elder.log','regeneration-r19-check.log','r19-build-native-wrapper.log',
             'r19-generation-recovery.json','r19-balance-failure-diagnostic.log','r19-resumed-native-wrapper.log',
             'worker-sync-r21.json','native-r19-c5-integration-plan.json','c5-build-native-wrapper.log','prepare-r19-output-distribution.py','build-and-test-r19.ps1','resume-r19-native.ps1',
             'prepare-r19-pilot.py','run-r19-pilot.ps1','collect-r19-mechanism.py','r19-scoped-data-impact.json','check-r19-scoped-data-impact.py',
             'r18-slam-formula-sensitivity-unexecuted.json','r18-slam-formula-sensitivity.py']:
    package.copy(O/name,base+name)
shared='data/enemy_properties/CF6重制敌人.xml'
with zipfile.ZipFile(O/'before-r19-output-distribution.zip') as z:original=z.read(shared)
original_path=O/'before-r19-shared-enemies.xml'
with original_path.open('xb') as f:f.write(original)
package.copy(original_path,base+'before-r19-shared-enemies.xml')
impact=u.js(O/'r19-scoped-data-impact.json');impact['baselineXmlPath']=base+'before-r19-shared-enemies.xml'
u.jput(P/base/'prior-C4-head-data-impact.json',impact)
u.jput(P/base/'summary.json',{
    'status':'native_verified; exploratory_pilot_running','slamMultiplier':8,'oldSlamMultiplier':12,
    'canonicalFormulaRegenerated':True,'baseAttackPanel':[692,1820],'shieldAttackScale':35/43,
    'kicksCapacityRatio':.1,'kicksReferenceStrengthLevelEndpoints':[.30,.12],'kicksLifetimeLevelEndpoints':[120,60],
    'slamCapacityRatio':.015,'slamReferenceStrengthRatio':10,'slamLifetimeFrames':120,
    'lossStepOfInitialMaximumHp':.05,'forcedConversion':.4,'capacityLimitOfInitialMaximumHp':.1,
    'pulseFrames':1,'pulseMissingHpRatio':.003125/3,'pulseCapacityLimitOfInitialMaximumHp':.000625/3,
    'pulseCeilingPer30ActiveFramesRatio':.00625,'decayFrames':36,'referenceStrengthRatio':10,
    'sameReactiveSupplementCeilingAsR18':True,'heavyBeamPowers':[.5,1,1.5,2],
    'robotOnly':True,'oneOwnedReactiveLayer':True,'noOpponentSpecificShieldDecision':True,
    'beamCapacityAccountingQualified':True,'meleeLayerAbsorptionAccountingQualified':True,
    'native':{'assetPassed':906,'effectsPassed':124,'robotPassed':45,'totalPassed':1075,
              'timelineCases':46,'phaseCases':13,'audioPassed':340,'audioRoutes':81,
              'playerAimPassed':1023,'playerAimCases':74,'totalSelectedChecks':2438},
    'candidateSwfSha256':u.sha(R/'flashswf/arts/new/Codex老头素材.swf'),'loaderSha256':u.sha(R/'scripts/asLoader.swf'),
    'preIntegrationHeadDataImpact':'prior-C4-head-data-impact.json','currentRegistrationIds':[472,473,474],'loaderGeneration':'C5','exploratoryPilot':'cf6-cal-r19-pilot-20261018','exploratoryPilotRows':12,
    'boundary':'Native checks and scoped data equivalence do not establish final strength, zero first-phase rage healing, new Head execution, formal promotion or player acceptance.'})
package.copy(P/'summary.json','progress-snapshots/20261018-before-r19-pilot.json')
summary=u.js(P/'summary.json');summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sealed=False,allGoalsMet=False)
summary['elder'].update(currentRound='R19',currentExperiment='cf6-cal-r19-pilot-20261018',currentExperimentState='exploratory pilot running',nativeChecksPassed=2438,r19Mechanism=base+'summary.json')
summary['headbot'].update(goalMet=False,currentRegisteredUnitId=472,currentCandidateMatrixRows=0,currentCandidateFullMatrix=False,subsequentMergedLoaderIntegrationPending=True,currentC5FullMatrixPending=True,currentExperimentState='new registration and C5 full eighteen-row matrix pending')
for row in summary['currentBindings']:row.update(bytes=(R/row['path']).stat().st_size,sha256=u.sha(R/row['path']))
(P/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
state['mapping']=package.mapping;(O/'evidence-history-assembly.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'nativeSelectedChecks':2438,'sharedEnemyDataImpactQualified':True,'pilotRows':12,'sealed':False}))
