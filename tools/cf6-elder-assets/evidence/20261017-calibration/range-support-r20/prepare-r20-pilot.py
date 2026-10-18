from pathlib import Path
import datetime,hashlib,json,subprocess
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';load=lambda p:json.loads(p.read_text('utf-8-sig'))
assert load(O/'native-cleanup-after-r20.json')['ok']
assert load(O/'r20-unaffected-native-suites.json')['qualified']
for folder in ['native-r20-fixture-repair/elder-asset','native-r20-range-support/audio','native-r20-range-support/player-aim','native-r20-range-support/elder-render']:
 result=load(O/folder/'result.json');assert result['exitCode']==0 and result['bindingsUnchanged']
cfg=load(O/'arena-r19-pilot-config.json');cfg.update(experimentId='cf6-cal-r20-pilot-20261018',outputDirectory=str(O/'arena-r20-pilot'),repeat=1)
with(O/'arena-r20-pilot-config.json').open('x',encoding='utf8')as f:json.dump(cfg,f,ensure_ascii=False,indent=2)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(O/'arena-r20-pilot-config.json')],check=True)
plan=load(O/'arena-r20-pilot/experiment-plan.json');assert len(plan['groups'])==6 and len(plan['workers'])==1
assert all(g['mode']=='serial' and len(g['jobs'])==1 and g['jobs'][0]['batchTimeoutMs']==900000 for g in plan['groups'])
with(O/'arena-r20-pilot/preregistered-purpose.json').open('x',encoding='utf8')as f:
 json.dump({'registeredAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'purpose':'Authorized 750 robot start range with matching 600-local-pixel visible/collision beam and halved shield capacity. All action timing, damage multipliers, initial HP/ATK/DEF panels and human range stay at R19.','expectedRows':12,'levels':[30,60,99],'rivals':[78,361],'perSideRepeat':1,'fullMatrix':False,'fullMatrixGroupMeanAndMedianNetHpLoss':[.5,.8],'winsAllowed':0,'timeoutsAllowed':0,'ownPhaseSpawnsPerFight':1,'netHpMethod':'Fixed full opponent chain including unspawned beast successor; every result retained.','maximumConcurrentGames':1,'displayLog':str(O/'display-qualified-20261018-r7/display-state.jsonl'),'perShardWallLimitMs':900000,'perFightTimeoutFrames':5400,'formalPromotion':False},f,ensure_ascii=False,indent=2)
print(json.dumps({'experiment':cfg['experimentId'],'rows':12,'acceptanceMatrix':False}))
