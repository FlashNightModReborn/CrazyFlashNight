"""Join the literal Beast rage notification to exact host and fight time intervals."""
from pathlib import Path
import argparse,datetime,hashlib,json,re
parser=argparse.ArgumentParser();parser.add_argument('experiment');parser.add_argument('--diagnostics',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);a=parser.parse_args()
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';E=R/'tmp/arena-worker-experiments'/a.experiment
def lp(p):
    value=str(Path(p).resolve());return Path(value if value.startswith('\\\\?\\')else'\\\\?\\'+value)
read=lambda p:lp(p).read_bytes();load=lambda p:json.loads(read(p).decode('utf-8-sig'));sha=lambda b:hashlib.sha256(b).hexdigest()
time=lambda text:datetime.datetime.fromisoformat(text.replace('Z','+00:00'))
zone=datetime.timezone(datetime.timedelta(hours=8))
index=load(a.diagnostics);assert index['experiment']==a.experiment
record_index={(r['group'],r['session']):r for r in index['privateArchives']}
source='flashswf/arts/things5/LIBRARY/敌人-方舟兽王.xml';source_bytes=read(R/source);source_text=source_bytes.decode('utf-8-sig')
assert source_text.count('_root.发布消息("封印崩解……");')==3
assert len(re.findall(r'if\(_parent\.狂暴模式 == 0 and _parent\.hp <= _parent\.hp满血值 \* 0\.2\)\s*\{\s*_parent\.狂暴模式 = 1;[^}]*?_root\.发布消息\("封印崩解……"\);',source_text))==3
rows=[];unattributed=[]
for path in sorted(E.rglob('group-report.json')):
    group=load(path)
    for outcome in group['outcomes']:
        if outcome['status']!='completed':continue
        assert outcome['cleanupVerified']and outcome['protectedSavesVerified']and outcome['runtimeResourcesVerified']
        receipt_path=Path(outcome['expectedReceiptPath']);receipt=load(receipt_path)
        raw_data=read(receipt['resultPath']);assert sha(raw_data)==receipt['resultSha256'].removeprefix('sha256:')
        raw=[json.loads(line)for line in raw_data.decode('utf-8-sig').splitlines()]
        session=next(p.removeprefix('session-')for p in receipt_path.parts if p.startswith('session-'))
        record=record_index[(group['groupId'],session)]
        log=read(a.diagnostics.parent/(group['groupId']+'-'+session+'-launcher.log'))
        assert sha(log)==record['entrySha256']
        archive=read(a.diagnostics.parent/record['archive']);assert sha(archive)==record['archiveSha256']
        start=time(receipt['hostStartedAt']).astimezone(zone);end=time(receipt['lifecycleCompletedAt']).astimezone(zone)
        notifications=[]
        for number,line in enumerate(log.decode('utf-8-sig').splitlines(),1):
            match=re.match(r'^(\d{2}:\d{2}:\d{2}\.\d{3}) \[XmlSocket:JSON\] (\{.*\})$',line)
            if not match:continue
            payload=json.loads(match.group(2))
            if payload.get('task')!='toast'or payload.get('payload')!='封印崩解……':continue
            timestamps=[datetime.datetime.combine(day,datetime.time.fromisoformat(match.group(1)),zone)for day in {start.date(),end.date()}]
            timestamps=[stamp for stamp in timestamps if start<=stamp<=end]
            if not timestamps:continue
            assert len(timestamps)==1
            stamp=timestamps[0]
            matches=[row for row in raw if time(row['startedAt'])<=stamp<=time(row['completedAt'])]
            event={'localTime':stamp.isoformat(),'lineNumber':number,'literalMessage':match.group(2),
                'sourceArchiveSha256':record['archiveSha256'],'sourceEntrySha256':record['entrySha256']}
            if not matches:unattributed.append({**event,'group':group['groupId'],'session':session});continue
            assert len(matches)==1,'Overlapping battle intervals'
            row=matches[0];ctx=row['authorityContext'];assert ctx['rivalUnitId']==78,'Beast notification in another rival fight'
            event['runId']=row['runId'];notifications.append(event)
        for row in raw:
            ctx=row['authorityContext'];other='red'if ctx['candidateSide']=='blue'else'blue'
            initial=[s for s in row[other+'SpawnPositions']if s['index']is not None]
            assert len(initial)==1 and len(row[other+'UnitResults'])==1
            matched=[event for event in notifications if event['runId']==row['runId']]
            rows.append({'group':group['groupId'],'runId':row['runId'],'rival':ctx['rivalUnitId'],'level':ctx['level'],
                'side':ctx['candidateSide'],'status':row['status'],'frames':row['frames'],'startedAt':row['startedAt'],
                'completedAt':row['completedAt'],'initialOpponentName':initial[0]['name'],
                'notifications':matched,'resultSha256':sha(raw_data)})
report={'experiment':a.experiment,'wholeExperimentFinal':(E/'experiment-report.json').exists(),
    'rows':rows,'observedBeastRageNotifications':sum(len(r['notifications'])for r in rows),
    'unattributedNotifications':unattributed,'sourceContract':{'path':source,'sha256':sha(source_bytes),'thresholdRatio':.2,'branchCount':3},
    'diagnosticIndexSha256':sha(read(a.diagnostics)),
    'boundary':'Literal XmlSocket toast notifications only, matched first to the exact receipt host interval and then to a unique raw battle startedAt..completedAt interval. Each accepted fight has exactly one initial opponent. Beast source sets its rage flag before this unique notification; no HP-only or damage-only inference is used. Zero notifications do not establish that rage never occurred. Unattributed notifications are excluded.'}
with lp(a.output).open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'rows':len(rows),'observedBeastRageNotifications':report['observedBeastRageNotifications'],'unattributed':len(unattributed)}))
