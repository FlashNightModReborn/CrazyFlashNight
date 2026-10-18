from evidence_utils import *
import statistics, subprocess

experiment='elder-r8-pilot-20261017'
report=js(ROOT/'tmp/arena-worker-experiments'/experiment/'experiment-report.json')
assert report['qualified'] and report['status']=='completed' and report['completedGroups']==6 and not report['errors']
assert all(g['globalSaveUnchanged'] and g['seedSourcesUnchanged'] and all(o['cleanupVerified'] and o['runtimeResourcesVerified'] and o['protectedSavesVerified'] for o in g['outcomes']) for g in report['groups'])
rows=[]
for group in report['groups']:
    for outcome in group['outcomes']:
        receipt=js(outcome['expectedReceiptPath'])
        assert sha(outcome['expectedReceiptPath'])==outcome['receiptSha256'].removeprefix('sha256:')
        assert sha(receipt['resultPath'])==receipt['resultSha256'].removeprefix('sha256:')
        rows.extend(json.loads(line) for line in read(receipt['resultPath']).decode('utf-8-sig').splitlines() if line)
assert len(rows)==12
stats=[]
for rival in [78,361]:
    for level in [30,60,99]:
        subset=[r for r in rows if r['authorityContext']['rivalUnitId']==rival and r['authorityContext']['level']==level]
        assert len(subset)==2
        values=[]
        for r in subset:
            other='red' if r['authorityContext']['candidateSide']=='blue' else 'blue'
            assert r['status']=='finished' and r['winner']==other and not r['errors'] and r['phaseSpawnCount']==1
            values.append(100*(1-r[other]['remainHp']/r[other]['startMaxHp']))
        stats.append({'rival':rival,'level':level,'netLoss':values,'mean':statistics.mean(values),'median':statistics.median(values)})
jput(TMP/'r8-pilot-review.json',{'games':12,'wins':0,'groups':stats,'targetMet':all(r['mean']>=25 and r['median']>=25 for r in stats),
    'scope':'Two samples per same-level group; R8 misses the preselected 25-percent group mean and median criterion at Beast King 99. All attempts retained.'})
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log','launcher.log.1','bootstrap.log']:
        source=root/'logs'/log
        if source.is_file():put(TMP/('r8-pilot-final-w'+str(index)+'-'+log),read(source))
put(TMP/'r8-pilot-diagnostics.jsonl',read(TMP/'live-elder-audit-r7.jsonl'))
for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
    put(TMP/'r8-before-balance'/relative,read(ROOT/relative))
file=ROOT/'tools/cf6-elder-assets/balance.py'
old=read(file).decode('utf8')
before="'growth':0.9,'attackBias':2,'defenseBias':28}"
after="'growth':0.9,'attackBias':2,'defenseBias':40}"
assert old.count(before)==1
file.write_text(old.replace(before,after),encoding='utf8',newline='\n')
subprocess.run(['python','-X','utf8','-B',str(file),'--write'],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B',str(file)],cwd=ROOT,check=True)
changed=[]
for name in ['headbot-combat','headbot-combat2']:
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
        destination=lp(root/relative);before_hash=sha(destination);data=read(ROOT/relative);destination.write_bytes(data)
        assert sha(destination)==digest(data)
        changed.append({'root':str(root),'path':relative,'beforeSha256':before_hash,'sha256':digest(data)})
jput(TMP/'worker-copy-r9.json',{'scope':'Robot defense allocation 28 to 40 only; fixed stage/tier, growth, attack, measured actions, R7 AI and all SWFs unchanged','files':changed})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r9-matrix-20261017',repeat=3,levels=[99,30,60],outputDirectory=str(TMP/'matrix-r9'))
jput(TMP/'matrix-r9-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r9-config.json')],cwd=ROOT,check=True)
frozen=Package(TMP/'r9-frozen-inputs')
frozen.freeze(r['path'] for r in js(TMP/'r8-frozen-inputs/frozen-inputs.zip.index.json')['files'])
print(json.dumps({'r9FrozenInputs':frozen.finish()},ensure_ascii=False))
print('R9 repeated matrix ready; no outcomes asserted.')
