from pathlib import Path
import hashlib,json,shutil,subprocess,zipfile
ROOT=Path.cwd();OUT=ROOT/'tmp/cf6-combat-audio-20261017'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
load=lambda p:json.loads(p.read_text('utf-8-sig'))
old=load(OUT/'worker-sync.json');roots=[Path(w['root']) for w in old['workers']]
report=load(ROOT/'tmp/arena-worker-experiments/cf6-headbot-combat-audio-20261017/experiment-report.json')
assert report['status']=='completed' and not report['errors']
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:
        assert all(outcome[k] for k in ['cleanupVerified','protectedSavesVerified','runtimeResourcesVerified'])
active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'CRAZYFLASHER7MercenaryEmpire.Core.exe' -or $_.Name -eq 'Adobe Flash Player 20.exe' -or $_.Name -eq 'FlashInputBroker.exe' } | Select-Object ExecutablePath,ProcessId | ConvertTo-Json"],text=True,encoding='utf8')
processes=json.loads(active) if active.strip() else []
if isinstance(processes,dict):processes=[processes]
for proc in processes:
    p=proc.get('ExecutablePath')
    assert p is not None,'Unobservable game process; preserve resources'
    assert not any(Path(p).is_relative_to(r) for r in roots),'Owned game still active'
rows=[]
for index,worker in enumerate(old['workers'],1):
    root=Path(worker['root']);changes=[]
    for row in worker['files']:
        assert sha(root/row['path'])==row['sha256'],'Worker changed independently: '+row['path']
        if sha(ROOT/row['path'])!=row['sha256']:changes.append({'path':row['path'],'beforeSha256':row['sha256'],'sha256':sha(ROOT/row['path'])})
    with zipfile.ZipFile(OUT/('worker-'+str(index)+'-before-final.zip'),'x',zipfile.ZIP_DEFLATED) as z:
        for row in changes:z.write(root/row['path'],row['path'])
    for row in changes:
        target=root/row['path'];assert target.resolve().is_relative_to(root.resolve())
        shutil.copyfile(ROOT/row['path'],target);assert sha(target)==row['sha256']
    rows.append({'root':str(root),'changes':changes})
with (OUT/'worker-final-sync.json').open('x',encoding='utf8') as f:json.dump({'scope':'Final fragment identity correction and Blade explosion timing; preserve all prior Worker bytes','workers':rows},f,ensure_ascii=False,indent=2)
config=load(OUT/'arena-headbot-config.json');config['experimentId']='cf6-headbot-final-combat-audio-20261017';config['outputDirectory']=str(OUT/'arena-headbot-final');config['repeat']=1
with (OUT/'arena-headbot-final-config.json').open('x',encoding='utf8') as f:json.dump(config,f,ensure_ascii=False,indent=2)
print(json.dumps({'workers':len(rows),'changedPaths':[len(w['changes']) for w in rows],'headFinalSmokeRows':6}))
