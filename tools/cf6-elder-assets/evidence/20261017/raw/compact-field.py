from pathlib import Path
import collections,json,statistics,sys
groups=collections.defaultdict(list)
for root in [Path('C:/Users/fs/.codex/worktrees')/w/'CrazyFlashNight' for w in ['headbot-combat','headbot-combat2']]:
 for batch in (root/'tmp/arena-calibration/batches').glob(sys.argv[1]+'*'):
  for p in batch.rglob('results.jsonl'):
   for s in p.read_text(encoding='utf-8-sig').splitlines():
    d=json.loads(s);c=d.get('authorityContext') or {};groups[(c.get('rivalUnitId'),c.get('level'))].append(d)
result=[]
for (rival,level),rows in sorted(groups.items()):
 values=[]
 for r in rows:
  side=r['authorityContext']['candidateSide'];foe=r['red' if side=='blue' else 'blue'];values.append(100*(1-foe['remainHp']/foe['startMaxHp']))
 result.append({'rival':rival,'level':level,'rows':len(rows),'wins':sum(r['winner']==r['authorityContext']['candidateSide'] for r in rows),'statuses':dict(collections.Counter(r['status'] for r in rows)),'phaseCounts':dict(collections.Counter(r['phaseSpawnCount'] for r in rows)),'netLoss':[round(x,3) for x in values],'min':round(min(values),3),'mean':round(sum(values)/len(values),3),'median':round(statistics.median(values),3),'max':round(max(values),3)})
for row in result:print(json.dumps(row,ensure_ascii=False))
