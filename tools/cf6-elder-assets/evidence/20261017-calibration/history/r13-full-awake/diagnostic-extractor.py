"""Copy only diagnostics belonging to completed groups of an explicitly named run."""
from pathlib import Path
import datetime,hashlib,json,re,sys,zipfile
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';experiment=sys.argv[1]
E=R/'tmp/arena-worker-experiments'/experiment;out=O/(experiment+'-private-diagnostics')
out.mkdir(exist_ok=True)
def lp(p):
    value=str(Path(p).resolve());return Path(value if value.startswith('\\\\?\\') else '\\\\?\\'+value)
def read(p):return lp(p).read_bytes()
def sha(data):return hashlib.sha256(data).hexdigest()
def put(p,data):
    if p.exists():assert read(p)==data,str(p)
    else:lp(p).write_bytes(data)
records=[];events=[]
for path in sorted(E.rglob('group-report.json')):
    group=json.loads(read(path).decode('utf-8-sig'))
    for outcome in group['outcomes']:
        if outcome['status']!='completed':continue
        receipt=Path(outcome['expectedReceiptPath'])
        receipt_data=json.loads(read(receipt).decode('utf-8-sig'))
        local_zone=datetime.timezone(datetime.timedelta(hours=8))
        start=datetime.datetime.fromisoformat(receipt_data['hostStartedAt'].replace('Z','+00:00')).astimezone(local_zone)
        finish=datetime.datetime.fromisoformat(receipt_data['lifecycleCompletedAt'].replace('Z','+00:00')).astimezone(local_zone)
        assert datetime.timedelta(0)<finish-start<datetime.timedelta(days=1)
        session=next(part.removeprefix('session-') for part in receipt.parts if part.startswith('session-'))
        worker=Path(*receipt.parts[:receipt.parts.index('tmp')]);logs=worker/'logs'
        archives=list(logs.glob('diagnostic-cf7_agent_aw_'+session+'-*.zip'))
        assert len(archives)==1,(group['groupId'],archives)
        archive=archives[0];data=read(archive);put(out/archive.name,data)
        with zipfile.ZipFile(lp(archive)) as z:
            original=z.read('logs/launcher.log')
        name=group['groupId']+'-'+session+'-launcher.log';put(out/name,original)
        found=[]
        for number,line in enumerate(original.decode('utf-8-sig').splitlines(),1):
            stamp=re.match(r'^(\d{2}:\d{2}:\d{2}\.\d{3})\s',line)
            if not stamp:continue
            tod=datetime.time.fromisoformat(stamp.group(1))
            candidates=[datetime.datetime.combine(d,tod,local_zone) for d in {start.date(),finish.date()}]
            in_interval=[d for d in candidates if start<=d<=finish]
            if not in_interval:continue
            assert len(in_interval)==1
            for match in re.finditer(r'\[CF6_ELDER_(?:COMBAT_END|PHASE_READY)\][^\r\n]*?(?=&frame=|$)',line):
                event={'group':group['groupId'],'session':session,'sourceArchiveSha256':sha(data),'sourceEntry':'logs/launcher.log','sourceEntrySha256':sha(original),'lineNumber':number,'localTime':in_interval[0].isoformat(),'message':match.group(0)}
                found.append(event);events.append(event)
        records.append({'group':group['groupId'],'session':session,'archive':archive.name,'archiveSha256':sha(data),'entrySha256':sha(original),'hostStartedAt':receipt_data['hostStartedAt'],'lifecycleCompletedAt':receipt_data['lifecycleCompletedAt'],'eventCount':len(found)})
index={'experiment':experiment,'wholeExperimentFinal':(E/'experiment-report.json').exists(),'privateArchives':records,'events':events,'boundary':'Original diagnostic archives include isolated save/configuration data and remain private. This derived list contains only literal CF6 combat/phase messages, with source archive and entry hashes plus line numbers.'}
index['filter']='Only timestamped lines within this exact receipt hostStartedAt..lifecycleCompletedAt (local UTC+08:00); prior sessions in the rolling log are excluded. Diagnostic exporter text is preserved literally, including any pre-existing replacement characters; authoritative identity still comes from original arena rows.'
target=out/('index-'+str(len(records))+'-groups-time-bound.json');put(target,(json.dumps(index,ensure_ascii=False,indent=2)+'\n').encode('utf8'))
print(json.dumps({'experiment':experiment,'groups':len(records),'events':len(events),'index':str(target)},ensure_ascii=False))
