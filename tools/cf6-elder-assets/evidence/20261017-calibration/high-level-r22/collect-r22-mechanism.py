from pathlib import Path
import datetime,importlib.util,json,re
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py');u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
assert not(P/'integrity.json').exists()
assert(R/'tmp/arena-worker-experiments/cf6-cal-r22-full-20261018/execution-started.json').is_file()
native=O/'native-r22-periodic-budget/elder-asset';result=u.js(native/'result.json')
assert result['exitCode']==0 and result['bindingsUnchanged']
trace=u.read(native/'flashlog.txt').decode('utf-8-sig')
selected=[('Cf6ElderAssetTest',908),('Cf6ElderCombatEffectsTest',127),('Cf6RobotCombatTest elder',45)]
for label,count in selected:assert re.search(re.escape(label)+r': '+str(count)+r' passed, 0 failed',trace)
for name in ['native-cleanup-after-r22.json','r22-source-scope-check.json','r22-acceptance-profile-check.json','r22-beast-acceptance-check.json']:assert u.js(O/name)['ok']
state=u.js(O/'evidence-history-assembly.json');package=u.Package(P);package.mapping=state['mapping'];base='high-level-r22/'
paths={r['path']for r in u.js(O/'before-r22-high-level-budget-index.json')}
paths.update(b['path']for b in u.js(O/'arena-r22-full/input-identity.json')['sourceBindings'])
paths.update(['tools/cf6-elder-assets/assess-arena-targets.py','tools/cf6-elder-assets/analyze-arena.py'])
package.freeze(paths,base+'source-at-full-run.zip')
for source,target in [('build-r22-elder','publish'),('native-r22-periodic-budget','native-focused'),
                      ('native-cleanup-after-r22-receipts','native-cleanup'),('arena-r22-full-base','canonical-plan-before-sharding')]:
    package.tree(O/source,base+target)
names=['before-r22-high-level-budget.zip','before-r22-high-level-budget-index.json','before-r22-beast-acceptance.zip',
       'r22-authorized-changes.json','r22-source-scope-check.json','r22-acceptance-profile-check.json',
       'r22-beast-acceptance-addendum.json','r22-beast-acceptance-check.json','class-closure-r22.json',
       'native-cleanup-after-r22.json','elder-r22-generate.log','elder-r22-generator-check.log',
       'elder-r22-balance-check.log','elder-r22-resource-verification.log','audio-fixture-r22-generation.log',
       'r22-build-focused-wrapper.log','prepare-r22-high-level-scope.py','prepare-r22-beast-acceptance.py',
       'check-r22-beast-acceptance.py','build-and-test-r22-focused.ps1','check-r22-source-scope.py',
       'check-r22-acceptance-profile.py','native-r22-focused-plan.json','worker-sync-r24.json',
       'prepare-r22-full.py','run-r22-full.ps1','split-full-repeat-plan-v2.js','collect-r22-mechanism.py']
for name in names:package.copy(O/name,base+name)
identity=u.js(O/'arena-r22-full/input-identity.json')
for row in identity['sourceBindings']:assert u.sha(R/row['path'])==row['sha256'],row['path']
u.jput(P/base/'summary.json',{'status':'focused_native_verified; full_matrix_running',
    'acceptanceProfile':'high-level-beast-near-death-exusiai-net-hp-v1','levels':[60,80,100],
    'fullMatrixExperiment':'cf6-cal-r22-full-20261018','fullMatrixRows':36,'fullMatrixAccepted':False,
    'beastCriterion':'Observed initial-form rage or actual successor spawn beyond that threshold; natural loss in every row.',
    'exusiaiCriterion':'Mean and median net HP loss 50-80 percent in each six-row group; natural loss in every row.',
    'humanInstructionChangedCriterionAfterStart':True,'frozenBattleConditionsUnchanged':True,
    'actualPeriodicMissingHpRatio':1/6400,'periodicInitialHpCapacityCeiling':1/6400,
    'maximumBudgetPer30ActiveFrames':.0046875,'budgetPer30ActiveFramesAtTwentyPercentMissingHp':.0009375,
    'forcedLossStep':.05,'forcedConversion':.3,'reactiveLayerCapacityLimit':.075,'decayFramesWithoutRefresh':36,
    'robotStartRange':750,'humanStartRange':500,'slamPower':18,'normalBeamPower':3,'heavyBeamPowers':[.5,1,1.5,2],
    'meleeShieldCapacityScale':.5,'beamShieldCapacityScale':.2,'reactiveShieldCapacityScale':.75,
    'damagePanelAndGraphicsUnchangedFromR21':True,'focusedNativeChecksPassed':1080,
    'nativeAudioPlayerAimAndRenderPending':True,'currentElderSwfSha256':u.sha(R/'flashswf/arts/new/Codex老头素材.swf'),
    'loaderSha256':u.sha(R/'scripts/asLoader.swf'),'boundary':'The recorded criterion addendum supersedes only Beast net HP acceptance. All original plans and historical results remain intact. Full strength, current Head matrix, human acceptance and formal promotion are not established by this preparation package.'})
package.copy(P/'summary.json','progress-snapshots/20261018-before-r22-full-current.json')
summary=u.js(P/'summary.json');summary.update(updatedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sealed=False,allGoalsMet=False)
summary['elder'].update(target='36 rows at 60/80/100: Beast reaches observed initial-form rage or first-form defeat; EXUSIAI six-row mean and median net HP loss 50-80 percent. Every row naturally loses; no wins, draws or timeouts.',
    currentRound='R22',currentExperiment='cf6-cal-r22-full-20261018',currentExperimentState='full thirty-six-row matrix running',
    nativeChecksPassed=1080,nativeCheckBoundary='Current focused Elder suite only; audio, player aim and render pending.',
    currentMechanism=base+'summary.json',acceptanceAddendum=base+'r22-beast-acceptance-addendum.json',acceptanceLevels=[60,80,100])
summary['nextStep']['elderNextIteration']='Complete the frozen thirty-six-row matrix and evaluate it under the explicit human-requested Beast criterion addendum. Preserve legacy net HP metrics separately.'
for row in summary['currentBindings']:row.update(bytes=(R/row['path']).stat().st_size,sha256=u.sha(R/row['path']))
(P/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
state['mapping']=package.mapping;(O/'evidence-history-assembly.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'focusedNativeChecksPassed':1080,'fullMatrixRunning':True,'sealed':False,'levels':[60,80,100]}))
