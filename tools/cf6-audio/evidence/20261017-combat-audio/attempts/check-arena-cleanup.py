"""Confirm owned battle processes are gone and retain their final logs without touching saves."""
from pathlib import Path
import datetime,hashlib,json,shutil,subprocess
R=Path.cwd();T=R/'tmp/cf6-combat-audio-20261017'
load=lambda p:json.loads(p.read_text('utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
preflight=load(T/'worker-preflight.json');initial=load(T/'worker-sync.json');last=load(T/'worker-final-sync.json');legacy=load(T/'worker-legacy-sync.json')
roots=[Path(r['root']) for r in initial['workers']]
assert not (T/'arena-final-cleanup.json').exists()
reports=[]
for family in ['headbot','bladebot','elder','headbot-final']:
    path=R/'tmp/arena-worker-experiments'/('cf6-'+family+'-combat-audio-20261017')/'experiment-report.json'
    report=load(path);assert report['qualified'] and report['status']=='completed' and not report['errors']
    for group in report['groups']:
        assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
        for outcome in group['outcomes']:assert outcome['status']=='completed' and all(outcome[k] for k in ['cleanupVerified','protectedSavesVerified','runtimeResourcesVerified'])
    reports.append({'family':family,'reportSha256':sha(path),'saveProtectionAndCleanupVerified':True})
output=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'CRAZYFLASHER7MercenaryEmpire.Core.exe' -or $_.Name -eq 'Adobe Flash Player 20.exe' -or $_.Name -eq 'FlashInputBroker.exe' } | Select-Object ExecutablePath,ProcessId | ConvertTo-Json"],text=True,encoding='utf8')
processes=json.loads(output) if output.strip() else []
if isinstance(processes,dict):processes=[processes]
for proc in processes:
    path=proc.get('ExecutablePath');assert path is not None,'Unobservable process identity'
    assert not any(Path(path).is_relative_to(root) for root in roots),'Owned battle process remains'
assert sha(Path(preflight['seed']))==preflight['seedSha256']
worker_checks=[];builds=load(T/'delivery-inputs.json')['builds']
for index,(base,update,repair) in enumerate(zip(initial['workers'],last['workers'],legacy['workers']),1):
    root=Path(base['root']);expected={r['path']:r['sha256'] for r in base['files']}
    expected.update({r['path']:r['sha256'] for r in update['changes']});expected.update({r['path']:r['sha256'] for r in repair['changes']})
    for rel,digest in expected.items():assert sha(root/rel)==digest,'Frozen worker file changed: '+rel
    for build in builds:assert sha(root/build['consumer'])==sha(R/build['consumer'])
    logs=T/('worker-'+str(index)+'-final-logs');logs.mkdir(exist_ok=False);kept=[]
    for file in (root/'logs').glob('*.log*'):
        if file.is_file():
            dest=logs/file.name;shutil.copyfile(file,dest);assert sha(file)==sha(dest);kept.append({'file':file.name,'sha256':sha(dest),'bytes':dest.stat().st_size})
    worker_checks.append({'root':str(root),'frozenFilesVerified':len(expected),'currentPublishedSwfsVerified':len(builds),'logs':kept})
result={'ok':True,'timeUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'ownedGameProcessesAbsent':True,
 'seedUnchanged':True,'seedSha256':preflight['seedSha256'],'reports':reports,'workers':worker_checks,
 'otherProcessesWereNotChanged':True,'noSaveRestorePerformed':True}
(T/'arena-final-cleanup.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'ok':True,'ownedGameProcessesAbsent':True,'seedUnchanged':True,'workers':len(worker_checks)}))
