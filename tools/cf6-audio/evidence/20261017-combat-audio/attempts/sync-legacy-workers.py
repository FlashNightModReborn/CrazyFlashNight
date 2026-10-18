from pathlib import Path
import hashlib,json,shutil,subprocess,zipfile
ROOT=Path.cwd();OUT=ROOT/'tmp/cf6-combat-audio-20261017'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
load=lambda p:json.loads(p.read_text('utf-8-sig'))
initial=load(OUT/'worker-sync.json');prior=load(OUT/'worker-final-sync.json');roots=[Path(w['root']) for w in initial['workers']]
report=load(ROOT/'tmp/arena-worker-experiments/cf6-elder-combat-audio-20261017/experiment-report.json')
assert report['status']=='completed' and report['qualified'] and not report['errors']
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:assert all(outcome[k] for k in ['cleanupVerified','protectedSavesVerified','runtimeResourcesVerified'])
active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'CRAZYFLASHER7MercenaryEmpire.Core.exe' -or $_.Name -eq 'Adobe Flash Player 20.exe' -or $_.Name -eq 'FlashInputBroker.exe' } | Select-Object ExecutablePath,ProcessId | ConvertTo-Json"],text=True,encoding='utf8')
processes=json.loads(active) if active.strip() else []
if isinstance(processes,dict):processes=[processes]
for proc in processes:
    path=proc.get('ExecutablePath');assert path is not None,'Unobservable game process'
    assert not any(Path(path).is_relative_to(root) for root in roots),'Owned game is still active'
cue_config=load(ROOT/'tools/cf6-audio/legacy-cues.json');rows=[]
for index,(base,last) in enumerate(zip(initial['workers'],prior['workers']),1):
    root=Path(base['root']);expected={r['path']:r['sha256'] for r in base['files']};expected.update({r['path']:r['sha256'] for r in last['changes']})
    expected.update({r['path']:r['beforeSha256'] for r in cue_config['cues']})
    expected.update({'tools/cf6-audio/legacy-cues.json':None,'tools/cf6-audio/restore-legacy-cues.py':None})
    changes=[]
    for rel,digest in expected.items():
        target=root/rel
        assert (not target.exists()) if digest is None else sha(target)==digest,'Independent Worker edit: '+rel
        current=sha(ROOT/rel)
        if current!=digest:changes.append({'path':rel,'beforeSha256':digest,'sha256':current})
    with zipfile.ZipFile(OUT/('worker-'+str(index)+'-before-legacy.zip'),'x',zipfile.ZIP_DEFLATED) as z:
        for row in changes:
            if row['beforeSha256'] is not None:z.write(root/row['path'],row['path'])
    for row in changes:
        target=root/row['path'];assert target.resolve().is_relative_to(root.resolve());target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/row['path'],target);assert sha(target)==row['sha256']
    rows.append({'root':str(root),'changes':changes})
with (OUT/'worker-legacy-sync.json').open('x',encoding='utf8') as f:json.dump({'scope':'After Elder cleanup, restore the two old-agent cues before final Head matchups. Prior robot behavior remains unchanged.','workers':rows},f,ensure_ascii=False,indent=2)
print(json.dumps({'workers':len(rows),'changedPaths':[len(w['changes']) for w in rows]}))
