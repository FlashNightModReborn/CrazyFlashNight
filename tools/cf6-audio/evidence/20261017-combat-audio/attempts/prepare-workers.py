from pathlib import Path
import hashlib,json,re,shutil,subprocess,zipfile
ROOT=Path.cwd();OUT=ROOT/'tmp/cf6-combat-audio-20261017'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
load=lambda p:json.loads(p.read_text('utf-8-sig'))
def write(p,v):
    with p.open('x',encoding='utf8') as f:json.dump(v,f,ensure_ascii=False,indent=2);f.write('\n')
workers=load(OUT/'worker-preflight.json')['workers']
registry=subprocess.check_output(['git','worktree','list','--porcelain'],text=True,encoding='utf8')
active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name='Core.exe' OR Name='FlashPlayer.exe'\" | Select-Object ExecutablePath,CommandLine | ConvertTo-Json"],text=True,encoding='utf8')
assert not active.strip(),'Unexpected active game process; stop before resource synchronization'
paths=set()
for family in ['headbot','elder','bladebot','manman','wings','soldier','guard','zombie']:
    folder=ROOT/('tools/cf6-'+family+'-assets')
    for p in folder.rglob('*'):
        if p.is_file() and 'evidence' not in p.parts and '__pycache__' not in p.parts:paths.add(p.relative_to(ROOT).as_posix())
    manifest=load(folder/'native-manifest.json');owner=ROOT/manifest['owner']
    for p in owner.rglob('*'):
        if p.is_file():paths.add(p.relative_to(ROOT).as_posix())
    paths.add(owner.relative_to(ROOT).as_posix()+'.swf')
for p in (ROOT/'tools/cf6-audio').glob('*'):
    if p.is_file():paths.add(p.relative_to(ROOT).as_posix())
for p in (ROOT/'sounds/export/人物').glob('CF6_*'):paths.add(p.relative_to(ROOT).as_posix())
paths.add('sounds/export/人物/soundheadexplode.wav')
paths.update(r['path'] for r in load(ROOT/'tmp/cf6-elder-20261016/matrix-r15/input-identity.json')['sourceBindings'])
for family,file in [('headbot','arena-plan.js'),('bladebot','arena-wave-plan.js')]:
    text=(ROOT/('tools/cf6-'+family+'-assets')/file).read_text('utf8')
    start=text.index('const boundPaths=');end=text.index('const sourceBindings=',start)
    paths.update(re.findall(r'"((?:flashswf|scripts|data|launcher|tools)/[^"\n]+)"',text[start:end]))
paths.update(p for p in load(OUT/'native-plan2.json')['bindings'] if p.startswith('scripts/逻辑/') or p.startswith('scripts/类定义/') and 'Test.as' not in p)
rows=[]
for index,w in enumerate(workers,1):
    root=Path(w['root']);assert root.as_posix() in registry
    assert subprocess.check_output(['git','rev-parse','--show-toplevel'],cwd=root,text=True).strip()==root.as_posix()
    for old in load(ROOT/'tmp/cf6-elder-20261016/matrix-r15/input-identity.json')['sourceBindings']:
        assert sha(root/old['path'])==old['sha256'],'Owned Worker baseline changed: '+old['path']
    entries=[]
    with zipfile.ZipFile(OUT/('worker-'+str(index)+'-before.zip'),'x',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for rel in sorted(paths):
            source=ROOT/rel;dest=root/rel;assert source.is_file(),rel
            if dest.exists():z.write(dest,rel)
            entries.append({'path':rel,'beforeSha256':sha(dest) if dest.exists() else None,'sha256':sha(source)})
    for row in entries:
        dest=root/row['path'];assert dest.resolve().is_relative_to(root.resolve())
        if row['beforeSha256']==row['sha256']:continue
        dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/row['path'],dest)
        assert sha(dest)==row['sha256']
    rows.append({'root':str(root),'files':entries,'preservedArchive':'worker-'+str(index)+'-before.zip'})
write(OUT/'worker-sync.json',{'scope':'Exact current CF6 consumer resources and source bindings; private candidate unchanged; no saves copied','workers':rows})
seed=load(OUT/'worker-preflight.json')['seed']
for family,variant,repeat in [('headbot','wave',3),('bladebot','wave-combo',2),('elder','two-phase',3)]:
    conf={'experimentId':'cf6-'+family+'-combat-audio-20261017','outputDirectory':str(OUT/('arena-'+family)),'variant':variant,'levels':[30,60,99],'repeat':repeat,
        'workers':[{'projectRoot':w['root'],'candidateRoot':w['candidateRoot'],'seedPath':seed} for w in workers]}
    write(OUT/('arena-'+family+'-config.json'),conf)
print(json.dumps({'workers':len(rows),'copiedOrCheckedPerWorker':len(paths),'plannedRows':78}))
