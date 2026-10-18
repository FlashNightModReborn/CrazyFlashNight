from evidence_utils import *
from datetime import datetime, timedelta
import re, statistics, sys

observed={}
for file in sorted(TMP.glob('live-elder-audit-r*.jsonl')):
    for line in read(file).decode('utf8').splitlines():
        if not line:continue
        event=json.loads(line);key=(str(Path(event['source']).parents[1]),event['lineSha256'])
        if key not in observed or event['observedAt']<observed[key]['observedAt']:observed[key]=event
events=list(observed.values())
for revision in sys.argv[1:]:
    rows=[]
    for worker in ['headbot-combat','headbot-combat2']:
        root=Path('C:/Users/fs/.codex/worktrees')/worker/'CrazyFlashNight'
        for batch in (root/'tmp/arena-calibration/batches').glob('elder-'+revision+'-matrix-20261017*'):
            for file in batch.rglob('results.jsonl'):
                for line in read(file).decode('utf-8-sig').splitlines():
                    if not line:continue
                    row=json.loads(line);side=row['authorityContext']['candidateSide'];other='red' if side=='blue' else 'blue'
                    name=row[side+'SpawnPositions'][0]['name']
                    start=datetime.fromisoformat(row['startedAt'].replace('Z','+00:00'))
                    end=datetime.fromisoformat(row['completedAt'].replace('Z','+00:00'))+timedelta(seconds=3)
                    selected=[event for event in events if '\\'+worker+'\\' in event['source']
                        and start<=datetime.fromisoformat(event['observedAt'])<=end
                        and re.search(r'unit='+re.escape(name)+r'(?:__elderbot)? ',event['line'])]
                    detail={}
                    for event in selected:
                        raw=event['line'];form=re.search(r' form=(human|robot) ',raw)
                        if not form:continue
                        numbers={key:float(value) for key,value in re.findall(r'\b(clock|starts|contacts|targetHp)=(-?\d+(?:\.\d+)?)',raw)}
                        actions={key:[int(a),int(b)] for key,a,b in re.findall(r'\b(beam|kicks|slam|burst|stab)=(\d+)/(\d+)',raw)}
                        detail[form[1]]={**numbers,**actions}
                    rows.append({'rival':row['authorityContext']['rivalUnitId'],'level':row['authorityContext']['level'],
                        'side':side,'repeat':row['repeatIndex'],'win':row['winner']==side,
                        'netLoss':round(100*(1-row[other]['remainHp']/row[other]['startMaxHp']),3),
                        'opponentInitialHp':row[other]['startMaxHp'],'phases':detail})
    print(json.dumps({'revision':revision,'scope':'Issued contacts are not actual hits or damage. Human-end target HP includes any enemy healing up to that instant.','rows':rows},ensure_ascii=False))
