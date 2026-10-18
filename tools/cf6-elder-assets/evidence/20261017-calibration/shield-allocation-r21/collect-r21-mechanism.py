from pathlib import Path
import datetime,importlib.util,json,re
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py');u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
assert not(P/'integrity.json').exists()
assert(R/'tmp/arena-worker-experiments/cf6-cal-r21-pilot-20261018/execution-started.json').is_file()
selected={'native-r21-fixture-repair/elder-asset':[('Cf6ElderAssetTest',908),('Cf6ElderCombatEffectsTest',125),('Cf6RobotCombatTest elder',45)],
          'native-r21-shield-allocation/audio':[('Cf6AudioTest',340)],
          'native-r21-shield-allocation/player-aim':[('Cf6PlayerAimTest',1211)],
          'native-r21-shield-allocation/elder-render':[('Cf6ElderRenderTest',40)]}
total=0
for folder,labels in selected.items():
    result=u.js(O/folder/'result.json');assert result['exitCode']==0 and result['bindingsUnchanged']
    trace=u.read(O/folder/'flashlog.txt').decode('utf-8-sig')
    for label,count in labels:
        assert re.search(re.escape(label)+r': '+str(count)+r' passed, 0 failed',trace),(folder,label)
        total+=count
assert total==2669
for name,key in [('native-cleanup-after-r21.json','ok'),('r21-unaffected-native-suites.json','qualified'),
                 ('r21-native-render-verification.json','ok'),('r21-source-scope-check.json','ok'),('r21-scoped-data-impact.json','qualified')]:
    assert u.js(O/name)[key]
trace=u.read(O/'native-r21-fixture-repair/elder-asset/flashlog.txt').decode('utf-8-sig')
deltas=re.findall(r'^\[CF6_SHIELD_REFERENCE\] attackDelta=([^ ]+) hardDelta=([^ ]+) beamDelta=([^ ]+) softDelta=([^\r\n]+)',trace,re.M)
assert len(deltas)==1
values=[float(v) for v in deltas[0]];assert all(abs(v)<1e-10 for v in values) and any(v!=0 for v in values)
state=u.js(O/'evidence-history-assembly.json');package=u.Package(P);package.mapping=state['mapping'];base='shield-allocation-r21/'
readme=R/'tools/cf6-elder-assets/README.md';package.copy(readme,base+'README-before-native-complete.md.txt')
text=readme.read_text('utf8');old='本轮尚待新鲜原生回归与独立斗兽验证，不能沿用 R20 的执行结果宣称通过。'
new='R21 已完成真实 CS6 发布、2,669 项选定原生检查和十二张当前原生画面。首次长老套件的九项失败保留在原始记录中；五处浮点精确比较改用既有误差比较后重跑通过，实际原生算术残差约为 10⁻¹³。生产逻辑与资源未因夹具修复改变，其他三套件的实际测试 SWF 均不包含该测试类，其余绑定与当前一致。十二场独立试跑正在进行，仍须通过完整三十六场强度矩阵。'
assert text.count(old)==1;readme.write_text(text.replace(old,new),'utf8',newline='\n')
paths={r['path'] for r in u.js(O/'before-r21-shield-allocation-index.json')}
paths.update(b['path']for b in u.js(O/'arena-r21-pilot/input-identity.json')['sourceBindings'])
paths.update(['scripts/test-runners/cf6-elder-render/TestLoader-charge.as.template','scripts/类定义/org/flashNight/arki/unit/UnitUtil.as','tools/cf6-elder-assets/decode-native-capture.py','tools/cf6-elder-assets/analyze-arena.py'])
package.freeze(paths,base+'source.zip')
for source,target in [('build-r21-elder','publish'),('native-r21-shield-allocation','native-first-cohort'),('native-r21-fixture-repair','native-fixture-repair'),('native-cleanup-after-r21-receipts','native-cleanup'),('native-r21-captures','native-images')]:
    package.tree(O/source,base+target)
for name in ['before-r21-shield-allocation.zip','before-r21-shield-allocation-index.json','r21-authorized-changes.json',
             'before-r21-native-fixture-repair.zip','r21-native-fixture-repair.json','r21-unaffected-native-suites.json',
             'r21-native-render-verification.json','r21-image-equivalence-to-r20.json','r21-source-scope-check.json','r21-scoped-data-impact.json',
             'class-closure-r21.json','native-cleanup-after-r21.json','elder-r21-generate.log','elder-r21-generator-check.log',
             'elder-r21-balance-write.log','elder-r21-balance-check.log','arena-catalog-r21-generation.log','arena-catalog-r21-check.log',
             'elder-r21-resource-verification.log','audio-fixture-r21-generation.log','r21-build-native-wrapper.log',
             'r21-native-fixture-repair-wrapper.log','prepare-r21-shield-allocation.py','build-and-test-r21.ps1',
             'repair-r21-native-fixtures.py','check-r21-unaffected-native-suites.js','check-r21-scoped-data-impact.py',
             'check-r21-source-scope.py','verify-r21-native-images.py','native-r21-shield-allocation-plan.json',
             'native-r21-fixture-repair-plan.json','worker-sync-r23.json','prepare-r21-pilot.py','run-r21-pilot.ps1',
             'r21-shield-only-unexecuted-draft.py','r21-shield-only-unexecuted-pilot-draft.py','r20-slam-formula-sensitivity.json',
             'collect-r21-mechanism.py']:
    package.copy(O/name,base+name)
u.jput(P/base/'native-floating-point-deltas.json',{'observedNativeDeltas':dict(zip(['normalizedAttack','hardStrength','beamStrength','softStrength'],values)),
        'testAbsoluteTolerance':.00001,'changedFixtureFiles':1,'productionAndPublishedResourceUnchangedDuringRepair':True,
        'scope':'Five equality expressions account for nine failures because the beam-level expression is exercised five times. The real leech/crumble boundary and depletion assertions remain in the passing suite.'})
u.jput(P/base/'preparation-notes.json',{'shieldOnlyDraftExecuted':False,'decisionChangedBeforeProductionMutation':'Complete R20 data showed high-level EXUSIAI wins with only about 2.2-2.4k beam absorption. Add authorized action redistribution through the unchanged formula, with the shield-only draft preserved.',
        'preflightGuard':'A read-only guard found the historical source index lacked units.json and the claim ledger. No preparation or production mutation had run. The final pre-change archive explicitly includes both.',
        'originalR20ResultsUnchanged':True})
u.jput(P/base/'summary.json',{'status':'native_verified; exploratory_pilot_running','robotStartRange':750,'humanStartRange':500,
        'localBeamLength':600,'slamPower':18,'normalBeamPower':3,'heavyBeamPowers':[.5,1,1.5,2],
        'attackMultiplierFlag':6.875,'robotBaseAttackPanel':[442,1172],'actualAttackLevels30_60_99':[813,1184,1666],
        'shieldAttackScale':55/43,'hardnessDeltaRatioBound':.014,
        'meleeShieldCapacityScale':.5,'beamShieldCapacityScale':.2,'reactiveShieldCapacityScale':.75,
        'actualForcedConversion':.3,'actualReactiveCapacityLimit':.075,'pulseFrames':1,
        'actualPulseMissingHpRatio':1/1280,'actualPulseCapacityLimit':1/6400,'actualPulseCeilingPer30ActiveFrames':.0046875,
        'decayFramesWithoutRefresh':36,'humanHpDefenseOtherUnitsAndGeometryUnchanged':True,
        'nativeSelectedChecks':total,'selectedNativeCohorts':selected,'nativeImages':12,'playerSourceCases':96,
        'currentElderSwfSha256':u.sha(R/'flashswf/arts/new/Codex老头素材.swf'),'loaderSha256':u.sha(R/'scripts/asLoader.swf'),
        'currentRegistrationIds':[472,473,474],'exploratoryPilot':'cf6-cal-r21-pilot-20261018','exploratoryPilotRows':12,
        'fullMatrixAccepted':False,'boundary':'Native checks and preserved current images do not establish final strength, current Head full matrix, zero total Beast healing, formal promotion or human acceptance.'})
package.copy(P/'summary.json','progress-snapshots/20261018-before-r21-pilot.json')
summary=u.js(P/'summary.json');summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sealed=False,allGoalsMet=False)
summary['elder'].update(currentRound='R21',currentExperiment='cf6-cal-r21-pilot-20261018',currentExperimentState='exploratory pilot running',nativeChecksPassed=total,r21Mechanism=base+'summary.json')
summary['nextStep']['elderNextIteration']='Assess all R21 rows with explicit win/loss/draw/timeout counts before a fresh thirty-six-fight matrix.'
for row in summary['currentBindings']:row.update(bytes=(R/row['path']).stat().st_size,sha256=u.sha(R/row['path']))
(P/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
state['mapping']=package.mapping;(O/'evidence-history-assembly.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'nativeSelectedChecks':total,'nativeImages':12,'pilotRunning':True,'sealed':False}))
