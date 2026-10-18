"""Bind each actual C6 boot to its private original archive and compare public excerpts."""
from pathlib import Path
import datetime,hashlib,json,re,shutil,subprocess,sys,zipfile
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';D=O/'loader-size-followup';B=D/'boot-proof'
B.mkdir(exist_ok=True)
def lp(p):
    p=str(Path(p).resolve());return Path(p if p.startswith('\\\\?\\') else '\\\\?\\'+p)
def data(p):return lp(p).read_bytes()
def sha(b):return hashlib.sha256(b).hexdigest()
zone=datetime.timezone(datetime.timedelta(hours=8))
for name,source in [('trace-diff.js',R/'tools/trace-diff.js'),('boot-golden.log',R/'tools/baselines/boot-golden.log')]:
    if (B/name).exists():assert data(B/name)==data(source)
    else:shutil.copy2(source,B/name)
kinds=sys.argv[1:] or ['head','elder']
assert kinds and len(set(kinds))==len(kinds) and set(kinds)<={'head','elder','elder-retry'}
for kind in kinds:
    groups={'head':3,'elder':5,'elder-retry':1}[kind]
    assert not (B/(kind+'-summary.json')).exists(),'Preserve completed boot proof'
    records=[]
    exp='cf6-loader-c6-b100-retry1-20261018' if kind=='elder-retry' else f'cf6-loader-c6-{kind}-20261018'
    subprocess.run(['python','-X','utf8','-B',str(O/'preserve-arena-group-diagnostics.py'),exp],check=True)
    archive_dir=O/(exp+'-private-diagnostics')
    index=json.loads(data(archive_dir/f'index-{groups}-groups-{groups}-shards-time-bound.json').decode('utf8'))
    assert index['wholeExperimentFinal'] and index['completedShards']==groups
    for entry in index['privateArchives']:
        raw=data(archive_dir/entry['archive']);assert sha(raw)==entry['archiveSha256']
        with zipfile.ZipFile(lp(archive_dir/entry['archive'])) as z:source=z.read('logs/launcher.log')
        assert sha(source)==entry['entrySha256']
        start=datetime.datetime.fromisoformat(entry['hostStartedAt'].replace('Z','+00:00')).astimezone(zone)
        end=datetime.datetime.fromisoformat(entry['lifecycleCompletedAt'].replace('Z','+00:00')).astimezone(zone)
        found=[]
        for number,line in enumerate(source.decode('utf-8-sig').splitlines(),1):
            tm=re.match(r'^(\d{2}:\d{2}:\d{2}\.\d{3})\s',line)
            if not tm:continue
            times=[datetime.datetime.combine(day,datetime.time.fromisoformat(tm.group(1)),zone) for day in {start.date(),end.date()}]
            if not any(start<=t<=end for t in times):continue
            for m in re.finditer(r'\[BootstrapAS\][^|\r\n]*?(?=\||&frame=|$)',line):
                found.append({'sourceLine':number,'localTime':tm.group(1),'message':m.group()})
            if '[XmlSocket:JSON] ' in line and any(message in line for message in ['任务数据加载完毕','任务文本加载完毕']):
                wire=line.split('[XmlSocket:JSON] ',1)[1]
                payload=json.loads(wire)
                if payload.get('task')=='toast' and payload.get('payload') in ['任务数据加载完毕','任务文本加载完毕']:
                    found.append({'sourceLine':number,'localTime':tm.group(1),'message':'[XmlSocket:JSON] '+wire})
        assert found
        assert sum(bool(re.search(r'event=s2_enter\b|handshake stage entered|frame4 entered',x['message'])) for x in found)==1
        assert sum('event=handoff' in x['message'] for x in found)==1
        name=kind+'-'+entry['group']+'-complete-wire'
        excerpt=B/(name+'.log')
        excerpt.write_text('\n'.join(x['localTime']+' '+x['message'] for x in found)+'\n','utf8')
        with (B/(name+'-trace-diff.log')).open('xb') as f:
            run=subprocess.run(['node','tools/trace-diff.js','diff','tools/baselines/boot-golden.log',str(excerpt)],stdout=f,stderr=subprocess.STDOUT)
        record={'kind':kind,'group':entry['group'],'session':entry['session'],'sourceArchive':entry['archive'],
                'sourceArchiveSha256':entry['archiveSha256'],'sourceEntry':'logs/launcher.log','sourceEntrySha256':entry['entrySha256'],
                'hostStartedAt':entry['hostStartedAt'],'lifecycleCompletedAt':entry['lifecycleCompletedAt'],
                'excerpt':excerpt.name,'excerptSha256':sha(excerpt.read_bytes()),'events':found,
                'traceDiffExitCode':run.returncode,'comparisonLog':name+'-trace-diff.log'}
        records.append(record)
        assert run.returncode==0,record
    (B/(kind+'-summary.json')).write_text(json.dumps({'qualified':len(records)==groups,'records':records},ensure_ascii=False,indent=2)+'\n','utf8')
if not all((B/(kind+'-summary.json')).exists() for kind in ['head','elder','elder-retry']):
    print(json.dumps({'completedBootProofKinds':kinds,'partial':True,'boots':len(records)}));sys.exit(0)
records=[r for kind in ['head','elder','elder-retry'] for r in json.loads(data(B/(kind+'-summary.json')).decode('utf8'))['records']]
summary={'qualified':len(records)==9,'boots':len(records),'traceToolSha256':sha(data(R/'tools/trace-diff.js')),
         'goldenSha256':sha(data(R/'tools/baselines/boot-golden.log')),'records':records,
         'boundary':'Each excerpt contains literal BootstrapAS messages plus the exact task-data/task-text completion toast wire from this receipt host interval, with archive/entry hashes and source lines. Private archives retain isolated save/configuration data locally. Event-order equality supports the happy path only, not every boundary or player acceptance.'}
(B/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'qualified':summary['qualified'],'actualCandidateBoots':len(records)}))
