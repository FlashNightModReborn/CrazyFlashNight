from pathlib import Path
import argparse,datetime,hashlib,json,re,subprocess
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
parser=argparse.ArgumentParser();parser.add_argument('--display-log',type=Path,required=True);a=parser.parse_args()
load=lambda p:json.loads(p.read_text('utf-8-sig'));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name in ['native-cleanup-after-r22.json','r22-source-scope-check.json','r22-acceptance-profile-check.json']:assert load(O/name)['ok']
native=O/'native-r22-periodic-budget/elder-asset';result=load(native/'result.json');assert result['exitCode']==0 and result['bindingsUnchanged']
trace=(native/'flashlog.txt').read_text('utf-8-sig')
for name,count in [('Cf6ElderAssetTest',908),('Cf6ElderCombatEffectsTest',127),('Cf6RobotCombatTest elder',45)]:
    assert re.search(re.escape(name)+r': '+str(count)+r' passed, 0 failed',trace)
assert a.display_log.is_file()
cfg=load(O/'arena-r21-pilot-config.json');cfg.update(experimentId='cf6-cal-r22-full-20261018',outputDirectory=str(O/'arena-r22-full-base'),levels=[60,80,100],repeat=3)
with(O/'arena-r22-full-config.json').open('x',encoding='utf8')as f:json.dump(cfg,f,ensure_ascii=False,indent=2)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(O/'arena-r22-full-config.json')],check=True)
subprocess.run(['node',str(O/'split-full-repeat-plan-v2.js'),str(O/'arena-r22-full-base'),str(O/'arena-r22-full')],check=True)
with(O/'arena-r22-full/preregistered-purpose.json').open('x',encoding='utf8')as f:
    json.dump({'registeredAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'userScope':'重点保60-100这个范围，低等级不考虑',
               'purpose':'First R22 arena execution is the full thirty-six-row matrix under the newly authorized high-level profile. R21 exploratory observations remain historical.',
               'firstArenaExecutionOfVariant':True,'precedingPilotExperiment':'cf6-cal-r21-pilot-20261018',
               'expectedRows':36,'expectedLevels':[60,80,100],'levels':[60,80,100],'rivals':[78,361],'perSideRepeat':3,
               'requiredNaturalLosses':36,'winsAllowed':0,'drawsAllowed':0,'timeoutsAllowed':0,
               'fullMatrixGroupMeanAndMedianNetHpLoss':[.5,.8],'ownPhaseSpawnsPerFight':1,
               'netHpMethod':'Fixed full opponent chain including unspawned Beast successor; every outcome retained.',
               'maximumConcurrentGames':1,'groups':18,'rowsPerGroup':2,'perFightTimeoutFrames':5400,'perShardWallLimitMs':900000,
               'displayLog':str(a.display_log.resolve()),'nativeCandidate':'cf6-transition-paint-r4',
               'focusedNativePassed':1080,'audioPlayerAimAndRenderCurrentVariantPending':True,
               'priorExploratorySummarySha256':sha(P/'history/r21-pilot-awake/phase-aware-summary.json'),
               'formalPromotion':False},f,ensure_ascii=False,indent=2)
print(json.dumps({'experiment':cfg['experimentId'],'rows':36,'levels':[60,80,100],'firstArenaExecutionOfVariant':True}))
