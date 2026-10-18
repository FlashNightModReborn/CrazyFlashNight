from pathlib import Path
import json,statistics
ROOT=Path.cwd();BASE=ROOT/'tmp/arena-worker-experiments'
def lp(p):return Path('\\\\?\\'+str(Path(p).resolve()))
for family in ['headbot','bladebot','elder','headbot-final']:
    p=BASE/('cf6-'+family+'-combat-audio-20261017')
    if not (p/'expected-receipts.json').exists():continue
    rows=[];receipts=[]
    for item in json.loads((p/'expected-receipts.json').read_text('utf8'))['receipts']:
        f=Path(item['receiptPath']);d=f.parent;manifest=d/'manifest.json'
        if f.exists():
            r=json.loads(f.read_text('utf8'));receipts.append({'job':item['jobId'],'status':r['status'],'errors':r.get('errors',[])})
            result=Path(r['resultPath']) if r.get('resultPath') else None
        elif manifest.exists():
            m=json.loads(manifest.read_text('utf8'));launch=json.loads((d/'launch.json').read_text('utf8'))
            result=Path(launch['outputRoot'])/'batches'/m['batchId']/'attempts'/item['attemptId']/'results.jsonl'
        else:result=None
        if result:result=lp(result)
        if result and result.exists():
            for line in result.read_text('utf8').splitlines():
                try:rows.append(json.loads(line))
                except json.JSONDecodeError:pass
    summary={'family':family,'rows':len(rows),'finished':sum(r['status']=='finished' for r in rows),
        'timeouts':sum(r['status']=='timeout' for r in rows),'wins':sum(r.get('winner')==r['authorityContext']['candidateSide'] for r in rows),
        'losses':sum(r.get('winner')==('red' if r['authorityContext']['candidateSide']=='blue' else 'blue') for r in rows),'draws':sum(r.get('winner')=='draw' for r in rows),
        'settledJobs':len(receipts),'jobErrors':[r for r in receipts if r['errors']]}
    if (p/'experiment-report.json').exists():
        r=json.loads((p/'experiment-report.json').read_text('utf8'));summary.update(qualified=r['qualified'],status=r['status'],errors=r['errors'])
    print(json.dumps(summary,ensure_ascii=False))
