from evidence_utils import *
from datetime import datetime,timedelta
import re,statistics,subprocess,sys

assert len(sys.argv)==2,'Specify the executed human-review candidate explicitly'
revision=sys.argv[1]
assert revision=='r15'
review=js(TMP/'review-candidate-r15.json')
assert review['executedR15BindingsRestored'] and review['r16NotExecuted'] and not review['balanceCalibrationComplete']
assert review['targetNetHpExchangePercent']==[50,80] and not review['humanAcceptance']
out=ROOT/'tools/cf6-elder-assets/evidence/20261017'
package=Package(out)
def snapshot_copy(source,relative):
 # Historical Markdown retains its original bytes and source path in the lossless
 # mapping. Its relative links belong to the old checkout, not this archive tree.
 if Path(relative).suffix.lower()=='.md':relative+='.snapshot.txt'
 package.copy(source,relative)
def snapshot_tree(source,relative):
 base=lp(source)
 for file in base.rglob('*'):
  if file.is_file():snapshot_copy(file,(Path(relative)/file.relative_to(base)).as_posix())
report,rows,identities=package.collect('matrix','elder-'+revision+'-matrix-20261017',TMP/('matrix-'+revision),True)
assert len(rows)==36 and len({(r['batchId'],r['runId']) for r in rows})==36
attempts=[]
for label,experiment,folder in [
 ('r2-pilot','elder-r2-pilot-20261016','pilot-r2'),
 ('r3-pilot','elder-r3-pilot-20261017','pilot-r3'),
 ('r3-beast-pilot','elder-r3-beast-pilot-20261017','pilot-r3-beast'),
 ('r4-pilot','elder-r4-pilot-20261017','pilot-r4'),
 ('r6-pilot','elder-r6-pilot-20261017','pilot-r6'),
 ('r7-pilot','elder-r7-pilot-20261017','pilot-r7'),
 ('r7-matrix','elder-r7-matrix-20261017','matrix-r7'),
 ('r8-pilot','elder-r8-pilot-20261017','pilot-r8'),
 ('r9-matrix','elder-r9-matrix-20261017','matrix-r9'),
 ('r10-matrix','elder-r10-matrix-20261017','matrix-r10'),
 ('r11-matrix','elder-r11-matrix-20261017','matrix-r11'),
 ('r12-matrix','elder-r12-matrix-20261017','matrix-r12'),
 ('r13-matrix','elder-r13-matrix-20261017','matrix-r13'),
 ('r14-matrix','elder-r14-matrix-20261017','matrix-r14'),
 ('r15-matrix','elder-r15-matrix-20261017','matrix-r15')]:
 if experiment=='elder-'+revision+'-matrix-20261017':continue
 r,old_rows,_=package.collect('history/'+label,experiment,TMP/folder,False)
 attempts.append({'label':label,'experiment':experiment,'qualified':r['qualified'],'status':r['status'],'rows':len(old_rows),'acceptedAsFinalPositioning':False})
levels=[]
for rival in [78,361]:
 for level in [30,60,99]:
  subset=[r for r in rows if r['authorityContext']['rivalUnitId']==rival and r['authorityContext']['level']==level]
  assert len(subset)==6
  for side in ['blue','red']:assert {r['repeatIndex'] for r in subset if r['authorityContext']['candidateSide']==side}=={1,2,3}
  values=[]
  for r in subset:
   side=r['authorityContext']['candidateSide'];other='red' if side=='blue' else 'blue'
   assert r['status']=='finished' and r['winner']==other and not r['errors'] and r['phaseSpawnCount']==1
   assert len(r['spawnedUnits'])==1 and r['spawnedUnits'][0]['unit']=='敌人-CF6老头机器人'
   values.append(100*(1-r[other]['remainHp']/r[other]['startMaxHp']))
  levels.append({'rivalUnitId':rival,'level':level,'games':6,'wins':0,'measure':'opponent_net_hp_loss_percent',
   'minPercent':min(values),'meanPercent':sum(values)/len(values),'medianPercent':statistics.median(values),'maxPercent':max(values),
   'withinTargetBand':sum(50<=value<=80 for value in values),
   'minFrames':min(r['frames'] for r in subset),'maxFrames':max(r['frames'] for r in subset)})

assert any(r['meanPercent']<50 for r in levels) and any(r['maxPercent']>80 for r in levels)
assert not js(TMP/'r16-prepared-not-executed.json')['candidateCombatExecuted']

inputs=js(TMP/('matrix-'+revision)/'input-identity.json')
for row in inputs['sourceBindings']:assert sha(ROOT/row['path'])==row['sha256'],'Source drift: '+row['path']
native_evidence=js(TMP/'native-r15-evidence.json')
for row in native_evidence['sourceBindings']:assert sha(ROOT/row['path'])==row['sha256'],'Native evidence drift: '+row['path']
paths={r['path'] for r in inputs['sourceBindings']}
paths.update(r['path'] for r in js(ROOT/'tools/cf6-elder-assets/native-manifest.json')['buildInputs'])
for base in ['tools/cf6-elder-assets','flashswf/arts/new/Codex老头素材',
 'flashswf/arts/new/Codex素材源稿/CF6老头人形-R7','flashswf/arts/new/Codex素材源稿/CF6老头机器人-R7',
 'flashswf/arts/new/Codex素材源稿/CF6老头变形-R2','scripts/test-runners/cf6-elder','scripts/test-runners/cf6-elder-render']:
 for p in lp(ROOT/base).rglob('*'):
  if p.is_file() and 'evidence' not in p.parts and '__pycache__' not in p.parts:paths.add(p.relative_to(lp(ROOT)).as_posix())
paths.update(['scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as',
 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderRenderTest.as',
 'scripts/run-cf6-elder-asset-tests.ps1','scripts/run-cf6-elder-render-tests.ps1',
 'tools/cf7-balance-tool/data/monster-flag-ledger.json','agentsDoc/testing-details.md','agentsDoc/game-design.md'])
paths.update(['tools/cf6-bladebot-assets/balance.py','data/enemy_properties/诺亚新敌人.xml',
 'tools/cf7-balance-tool/data/monster-census.json','tools/cf7-balance-tool/docs/monster-flag-rulebook.md',
 'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts','tools/cf7-balance-tool/packages/core/package.json',
 'tools/cf7-balance-tool/package.json','tools/cf7-balance-tool/package-lock.json'])
paths.update(['scripts/类定义/org/flashNight/arki/unit/UnitComponent/Status/ImpactStateHandler.as',
 'scripts/类定义/org/flashNight/arki/component/Damage/UniversalDamageHandle.as',
 'scripts/类定义/org/flashNight/arki/component/Damage/DamageResult.as',
 'scripts/类定义/org/flashNight/arki/component/StatHandler/ImpactHandler.as',
 'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'])
package.freeze(paths)
for p in TMP.iterdir():
 if p.is_file() and not p.name.startswith(('blade-','headbot-')):
  snapshot_copy(p,'raw/'+p.name)
for name in ['r6-frozen-inputs','r7-frozen-inputs','r8-frozen-inputs','r9-frozen-inputs','r10-frozen-inputs','r11-frozen-inputs','r12-frozen-inputs','r13-frozen-inputs','r14-frozen-inputs','r15-frozen-inputs','r16-frozen-inputs',
 'r7-before-balance','r8-before-balance','r9-before-balance','r10-before-balance','r11-before-ai','r12-before-balance','r13-before-balance','r14-before-ai','r15-before-balance','r16-pre-review','native-images-r3',
 'render-r1-recovery','wings-post-knockback-timeout','preview-first']:
 if (TMP/name).is_dir():snapshot_tree(TMP/name,'raw/'+name)
native_review=js(TMP/'native-review-r6.json')
for row in native_review['reviewed']:
 source=TMP/'render-capture-r6-images'/row['file'];assert sha(source)==row['sha256']
 package.copy(source,'native/images/'+row['file'])
jput(out/'native/image-provenance.json',{'scope':'19 individually reviewed R6 native Flash images; R7, R12 and R15 each have equal graphics XML and their own fresh six-point render probe',
 'captureRunId':'3ba51affbe834d5b9d48a7b034adc3c9','captureSwfSha256':native_review['swfSha256'],
 'currentSwfSha256':sha(ROOT/'flashswf/arts/new/Codex老头素材.swf'),'reviewed':native_review['reviewed'],
 'graphicsEquivalence':['../raw/r7-art-equivalence.json','../raw/r12-art-equivalence.json','../raw/r15-art-equivalence.json'],'humanAcceptance':False})

observed={}
for file in sorted(TMP.glob('live-elder-audit-r*.jsonl')):
 for line in read(file).decode('utf8').splitlines():
  if not line:continue
  event=json.loads(line);key=(str(Path(event['source']).parents[1]),event['lineSha256'])
  if key not in observed or event['observedAt']<observed[key]['observedAt']:observed[key]=event
events=list(observed.values())
diagnostics=[]
for r in rows:
 side=r['authorityContext']['candidateSide'];name=r[side+'SpawnPositions'][0]['name']
 start=datetime.fromisoformat(r['startedAt'].replace('Z','+00:00'));end=datetime.fromisoformat(r['completedAt'].replace('Z','+00:00'))+timedelta(seconds=3)
 worker='headbot-combat2' if r['workerId']=='elder-w2' else 'headbot-combat'
 selected=[]
 for event in events:
  if ('\\'+worker+'\\') not in event['source']:continue
  time=datetime.fromisoformat(event['observedAt'])
  if not start<=time<=end:continue
  if re.search(r'(?:parent|unit)='+re.escape(name)+r'(?:__elderbot)? ',event['line']):selected.append(event)
 phases=[e for e in selected if '[CF6_ELDER_PHASE_READY]' in e['line']]
 diagnostics.append({'batchId':r['batchId'],'runId':r['runId'],'parentName':name,'level':r['authorityContext']['level'],
   'rivalUnitId':r['authorityContext']['rivalUnitId'],'phaseEventsObserved':len(phases),'events':selected})
jput(out/'field-diagnostics.json',{'scope':'Exact Worker, run time interval and parent-instance name; contact counters are issued contacts, not damage or actual hits',
 'rows':diagnostics,'allPhaseDiagnosticsObserved':all(r['phaseEventsObserved']==1 for r in diagnostics)})
jput(out/'summary.json',{'schema':'cf6-elder.two-phase.v1','completedAt':report['completedAt'],'revision':revision,
 'repositoryHeadAtArchive':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
 'evidenceState':'candidate_executed','positioningMatrixVerified':False,'balanceCalibrationComplete':False,
 'humanReviewRequested':True,'handoffPurpose':'User selected move/gameplay review first, then strength tuning.',
 'userTargetNetHpExchangePercent':[50,80],'targetBandMatches':sum(r['withinTargetBand'] for r in levels),
 'targetScope':'Complete human then robot versus same-level Ark Beast King or EXUSIAI commander; record final net HP loss, including opponent healing. Current candidate is not declared balanced.',
 'historicalWorkingThreatCriterion':'Before R8, agent chose mean and median net HP loss at least 25 percent per six-match group with no wins or timeouts. Superseded by the user 50-80 percent expectation; retained only to explain earlier revisions.',
 'historicalWorkingSurvivalMargin':'Before R11, agent added a 15 percent opponent remaining-HP check. R15 fails this old check in one EXUSIAI 99 match; retained as history, not waived or labelled passed.',
 'minimumOpponentRemainingHpPercent':min(100-r['maxPercent'] for r in levels),
 'formalRuntimePromoted':False,'standardEntryVerified':False,'humanAcceptance':False,
 'fixed':{'human':{'stage':8,'tier':9,'unitId':471},'robot':{'stage':8,'tier':20,'unitId':472}},
 'games':36,'wins':0,'timeouts':0,'singleSuccessorPerMatch':True,'levels':levels,'priorAttempts':attempts,
 'preparedButNotExecuted':[{'revision':'r16','growth':0.9,'staticChecksPassed':True,'combatExecuted':False,'restoredForReview':'r15','record':'raw/r16-prepared-not-executed.json'}],
 'priorQualificationScope':'Historical coordinator qualified flags establish execution and protection checks only; none of the prior attempts is accepted as the final positioning matrix.',
 'sourceBindings':inputs['sourceBindings'],'runtimeIdentities':identities,
 'native':{'revision':native_evidence['revision'],'bytes':native_evidence['swfBytes'],'sha256':sha(ROOT/'flashswf/arts/new/Codex老头素材.swf'),'shapes':53,'sprites':28,'bitmaps':0,'symbols':82},
 'behavior':{**native_evidence['proof']['behavior'],'timelineCases':34,'phaseCases':13},
 'render':{'fullR6RunId':'002525ae1e7a4c818082329aecfa041c','fullR6Passed':1439,'drawPoints':718,'images':19,
 'r7ProbeRunId':'ab9ca9340e47403e97bf0d38daef7d83','r7ProbePassed':16,'r7ProbePoints':6,'equivalentGraphicsXmlFiles':85,
 'currentProbe':{**native_evidence['proof']['render-probe'],'drawPoints':native_evidence['drawPoints'],'revision':native_evidence['revision']}},
 'limits':'Human move review handoff only; strength calibration toward 50-80 percent remains incomplete. Finite repeated isolated candidate combat; no cumulative damage claim; fixture render timing is not game performance. Physical appearance, motion, gameplay and standard entry acceptance remain open.'})
finished=package.finish()
checks=[]
for command,name in [(['node','tools/validate-doc-governance.js'],'review-doc-governance-final.log'),(['git','diff','--check'],'review-diff-check-final.log')]:
 check=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 put(TMP/name,check.stdout)
 checks.append({'log':name,'exitCode':check.returncode,'sha256':sha(TMP/name)})
 assert check.returncode==0,'Post-seal check failed; preserve the sealed package and this external check log: '+name
jput(TMP/'review-post-seal-checks.json',{'checks':checks,'sealedPackageUnmodified':True})
print(json.dumps({'levels':levels,**finished,'postSealChecks':checks},ensure_ascii=False))
