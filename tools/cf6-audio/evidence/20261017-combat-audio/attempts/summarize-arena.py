from pathlib import Path
import hashlib,json,statistics
ROOT=Path.cwd();TMP=ROOT/'tmp/cf6-combat-audio-20261017'
def lp(p):
    s=str(Path(p).resolve());return Path(s if s.startswith('\\\\?\\') else '\\\\?\\'+s)
def load(p):return json.loads(lp(p).read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(lp(p).read_bytes()).hexdigest()
families=[]
for family,count in [('headbot',18),('bladebot',24),('elder',36),('headbot-final',6)]:
    folder=ROOT/'tmp/arena-worker-experiments'/('cf6-'+family+'-combat-audio-20261017');report=load(folder/'experiment-report.json')
    assert report['status']=='completed' and not report['errors'];rows=[]
    for item in load(folder/'expected-receipts.json')['receipts']:
        receipt=load(item['receiptPath']);assert receipt['status']=='completed' and not receipt['errors']
        p=lp(receipt['resultPath']);assert sha(p)==receipt['resultSha256'].removeprefix('sha256:')
        rows.extend(json.loads(line) for line in p.read_text('utf-8-sig').splitlines())
    assert len(rows)==count;groups={}
    detailed=[]
    for row in rows:
        assert not row['errors'];ctx=row['authorityContext'];side=ctx['candidateSide'];other='red' if side=='blue' else 'blue'
        remaining=row[side]['remainHp']/row[side]['startMaxHp'];rivalLoss=1-row[other]['remainHp']/row[other]['startMaxHp']
        entry={'runId':row['runId'],'caseId':row['caseId'],'candidateSide':side,'level':ctx['level'],'rivalUnitId':ctx['rivalUnitId'],
            'status':row['status'],'candidateWon':row['winner']==side,'candidateLost':row['winner']==other,'draw':row['winner']=='draw','winner':row['winner'],'frames':row['frames'],
            'candidateRemainingFraction':remaining,'rivalNetHpLossFraction':rivalLoss,'phaseSpawnCount':row.get('phaseSpawnCount',0)}
        detailed.append(entry);groups.setdefault((ctx['rivalUnitId'],ctx['level']),[]).append(entry)
    summaries=[]
    for (rival,level),group in groups.items():
        loss=[r['rivalNetHpLossFraction'] for r in group];hp=[r['candidateRemainingFraction'] for r in group];frames=[r['frames'] for r in group]
        summaries.append({'rivalUnitId':rival,'level':level,'rows':len(group),'wins':sum(r['candidateWon'] for r in group),
            'losses':sum(r['candidateLost'] for r in group),'draws':sum(r['draw'] for r in group),
            'timeouts':sum(r['status']=='timeout' for r in group),'rivalNetHpLoss':{'min':min(loss),'mean':statistics.mean(loss),'median':statistics.median(loss),'max':max(loss)},
            'candidateRemainingHp':{'min':min(hp),'max':max(hp)},'frames':{'min':min(frames),'max':max(frames)},
            'within50to80NetLoss':sum(.5<=v<=.8 for v in loss)})
    families.append({'family':family,'experimentReportSha256':sha(folder/'experiment-report.json'),'experimentQualified':report['qualified'],
        'totalRows':len(rows),'groups':summaries,'runs':detailed,'phaseSpawnCountExactlyOnce':all(r['phaseSpawnCount']==1 for r in detailed) if family=='elder' else None,
        'scope':'Initial Head fragment version; frame/AI DoAction bodies match final and final version has a separate six-row run' if family=='headbot' else 'Final published resources'})
output={'schema':'cf6.combat-audio.arena-summary.v1','families':families,'totalRows':sum(x['totalRows'] for x in families),
    'automaticBalanceRetuning':False,'netLossDefinition':'Final net remaining HP includes rival healing; it is not accumulated dealt damage.',
    'qualification':'Qualified experiment means runtime identity, protection and execution evidence passed; losses and timeouts remain negative strength results.'}
with (TMP/'arena-summary.json').open('x',encoding='utf8') as f:json.dump(output,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps({r['family']:{'rows':r['totalRows'],'wins':sum(g['wins'] for g in r['groups']),'losses':sum(g['losses'] for g in r['groups']),'draws':sum(g['draws'] for g in r['groups']),'timeouts':sum(g['timeouts'] for g in r['groups'])} for r in families},ensure_ascii=False))
