from pathlib import Path
import datetime,importlib.util,json,re
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py');u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
assert not (P/'integrity.json').exists()
assert (R/'tmp/arena-worker-experiments/cf6-cal-r20-pilot-20261018/execution-started.json').is_file()
selected={
 'native-r20-fixture-repair/elder-asset':[('Cf6ElderAssetTest',908),('Cf6ElderCombatEffectsTest',125),('Cf6RobotCombatTest elder',45)],
 'native-r20-range-support/audio':[('Cf6AudioTest',340)],
 'native-r20-range-support/player-aim':[('Cf6PlayerAimTest',1211)],
 'native-r20-range-support/elder-render':[('Cf6ElderRenderTest',40)]}
total=0
for folder,labels in selected.items():
 result=u.js(O/folder/'result.json');assert result['exitCode']==0 and result['bindingsUnchanged']
 trace=u.read(O/folder/'flashlog.txt').decode('utf-8-sig')
 for label,count in labels:
  assert re.search(re.escape(label)+r': '+str(count)+r' passed, 0 failed',trace),(folder,label)
  total+=count
assert total==2669 and u.js(O/'native-cleanup-after-r20.json')['ok']
assert u.js(O/'r20-unaffected-native-suites.json')['qualified']
assert u.js(O/'r20-native-render-verification.json')['ok']
state=u.js(O/'evidence-history-assembly.json');package=u.Package(P);package.mapping=state['mapping'];base='range-support-r20/'
readme=R/'tools/cf6-elder-assets/README.md';package.copy(readme,base+'README-before-native-complete.md.txt')
text=readme.read_text('utf8');old='R20 尚待新鲜编译、原生回归、当前图像和独立斗兽；R19 十二场十负二胜、零超时全部保留，不能作为本版通过记录。'
new='R20 已完成真实 CS6 发布、2,669 项选定原生检查和十二张当前原生画面。首次回归保留两处旧测试布置失败，修正后仅重跑长老套件；其他套件的实际测试 SWF 不包含这两项测试类，且其余 144 项绑定输入均与当前一致。十二场独立试跑正在进行，仍须通过完整三十六场强度矩阵；R19 十二场十负二胜、零超时继续保留其实际身份。'
assert text.count(old)==1;readme.write_text(text.replace(old,new),'utf8',newline='\n')
paths={r['path']for r in u.js(O/'before-r20-range-support-index.json')}
paths.update(b['path']for b in u.js(O/'arena-r20-pilot/input-identity.json')['sourceBindings'])
paths.update(['scripts/test-runners/cf6-elder-render/TestLoader-charge.as.template','scripts/类定义/org/flashNight/arki/unit/UnitUtil.as','tools/cf6-elder-assets/decode-native-capture.py','tools/cf6-elder-assets/analyze-arena.py'])
package.freeze(paths,base+'source.zip')
for source,target in [('build-r20-elder','publish'),('native-r20-range-support','native-first-cohort'),('native-r20-fixture-repair','native-fixture-repair'),('native-cleanup-after-r20-receipts','native-cleanup'),('native-r20-captures','native-images')]:
 package.tree(O/source,base+target)
for name in ['before-r20-range-support.zip','before-r20-range-support-index.json','r20-authorized-changes.json',
 'before-r20-native-fixture-repair.zip','r20-native-fixture-repair.json','r20-unaffected-native-suites.json',
 'r20-native-render-verification.json','r20-source-scope-check-v2.json','class-closure-r20.json','native-cleanup-after-r20.json',
 'elder-r20-generate.log','elder-r20-generator-check.log','elder-r20-balance-check.log','elder-r20-resource-verification.log',
 'audio-fixture-r20-generation.log','r20-build-native-wrapper.log','r20-native-fixture-repair-wrapper.log',
 'prepare-r20-range-support.py','build-and-test-r20.ps1','repair-r20-native-fixtures.py','check-r20-unaffected-native-suites.js',
 'native-r20-range-support-plan.json','native-r20-fixture-repair-plan.json','worker-sync-r22.json','prepare-r20-pilot.py','run-r20-pilot.ps1','collect-r20-mechanism.py']:
 package.copy(O/name,base+name)
u.jput(P/base/'preparation-attempts.json',{'productionMutationBeforeFirstGuardFailure':False,'firstPreparationGuard':'The first in-memory mutator stopped because the beam capacity expression was not the guessed capacityRate expression. No production files or backup archive were written at that point. The guarded source match was corrected to the actual formula before the successful preparation.','sourceScopeGuard':'The first source-scope check found units.json absent from the pre-change archive index and stopped without writing a report. The v2 report uses the immutable R19 plan for registration identity.','nativeFailure':'Native first-cohort elder suite reported movement-target and shield-transition fixture failures. Original logs, test SWF and exact two source files are retained; repair changes neither production script nor published resource.'})
u.jput(P/base/'summary.json',{'status':'native_verified; exploratory_pilot_running','authorization':'User approved trial 750 robot range and reduced shield sustain after visible/collision extension was explained.','robotStartRange':750,'humanStartRange':500,'localBeamLength':600,'oldLocalBeamLength':461.05,'shieldCapacityScale':.5,'shieldStrengthAndDurationsChanged':False,'damageMultipliersAndNumericPanelsChanged':False,'actualKicksCapacityRatio':.05,'actualSlamCapacityRatio':.0075,'lossStepOfInitialMaximumHp':.05,'actualForcedConversion':.2,'actualReactiveCapacityLimit':.05,'pulseFrames':1,'actualPulseMissingHpRatio':1/1920,'actualPulseCapacityLimit':1/9600,'actualPulseCeilingPer30ActiveFrames':.003125,'decayFramesWithoutRefresh':36,'heavyBeamPowers':[.5,1,1.5,2],'nativeSelectedChecks':2669,'selectedNativeCohorts':selected,'nativeImages':12,'playerSourceCases':96,'fixtureRepairScope':'r20-unaffected-native-suites.json','currentElderSwfSha256':u.sha(R/'flashswf/arts/new/Codex老头素材.swf'),'loaderSha256':u.sha(R/'scripts/asLoader.swf'),'currentRegistrationIds':[472,473,474],'exploratoryPilot':'cf6-cal-r20-pilot-20261018','exploratoryPilotRows':12,'fullMatrixAccepted':False,'boundary':'Selected native evidence and source scope do not establish final strength, zero Beast healing, current Head full matrix, formal promotion or human acceptance. Diagnostic range counts are selector calls, not all runtime frames.'})
package.copy(P/'summary.json','progress-snapshots/20261018-before-r20-pilot.json')
summary=u.js(P/'summary.json');summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sealed=False,allGoalsMet=False)
summary['elder'].update(currentRound='R20',currentExperiment='cf6-cal-r20-pilot-20261018',currentExperimentState='exploratory pilot running',nativeChecksPassed=2669,r20Mechanism=base+'summary.json')
summary['nextStep']['elderNextIteration']='Assess every R20 row and the selector range diagnostics before a fresh thirty-six-fight matrix.'
for row in summary['currentBindings']:row.update(bytes=(R/row['path']).stat().st_size,sha256=u.sha(R/row['path']))
(P/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
state['mapping']=package.mapping;(O/'evidence-history-assembly.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'nativeSelectedChecks':total,'nativeImages':12,'pilotRunning':True,'sealed':False}))
