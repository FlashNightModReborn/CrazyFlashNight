from pathlib import Path
import json,sys
exp=sys.argv[1]
roots=[Path('C:/Users/fs/.codex/worktrees')/w/'CrazyFlashNight' for w in ['headbot-combat','headbot-combat2']]
rows=[]
for root in roots:
 for batch in (root/'tmp/arena-calibration/batches').glob(exp+'*'):
  for p in batch.rglob('results.jsonl'):
   for s in p.read_text(encoding='utf-8-sig').splitlines():
    d=json.loads(s); c=d.get('authorityContext') or {}; side=c.get('candidateSide'); other='red' if side=='blue' else 'blue'
    if not side: rows.append({'case':d.get('caseId'),'status':d.get('status'),'errors':d.get('errors')});continue
    me=d.get(side,{}) or {}; rival=d.get(other,{}) or {}
    rows.append({'rival':c.get('rivalUnitId'),'level':c.get('level'),'side':side,'repeat':d.get('repeatIndex'),'status':d.get('status'),'win':d.get('winner')==side,'frames':d.get('frames'),'phase':d.get('phaseSpawnCount'),'ownHp':me.get('remainHp'),'ownStart':me.get('startMaxHp'),'enemyHp':rival.get('remainHp'),'enemyStart':rival.get('startMaxHp'),'ownPercent':round(100*me.get('remainHp',0)/me['startMaxHp'],3) if me.get('startMaxHp') else None,'enemyNetLossPercent':round(100*(1-rival.get('remainHp',0)/rival['startMaxHp']),3) if rival.get('startMaxHp') else None,'errors':d.get('errors')})
print(json.dumps({'experiment':exp,'rows':rows},ensure_ascii=False,indent=2))
