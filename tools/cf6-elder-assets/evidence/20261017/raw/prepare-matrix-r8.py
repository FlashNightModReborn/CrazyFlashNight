from evidence_utils import *
import statistics, subprocess

experiment='elder-r8-pilot-20261017'
report=js(ROOT/'tmp/arena-worker-experiments'/experiment/'experiment-report.json')
assert report['qualified'] and report['status']=='completed' and report['completedGroups']==6 and not report['errors']
rows=[]
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:
        assert outcome['status']=='completed' and all(outcome[k] for k in ['cleanupVerified','runtimeResourcesVerified','protectedSavesVerified'])
        receipt=js(outcome['expectedReceiptPath'])
        assert receipt['runtimeUnchanged'] and receipt['resourcesUnchanged'] and not receipt['errors']
        assert sha(outcome['expectedReceiptPath'])==outcome['receiptSha256'].removeprefix('sha256:')
        assert sha(receipt['resultPath'])==receipt['resultSha256'].removeprefix('sha256:')
        rows.extend(json.loads(line) for line in read(receipt['resultPath']).decode('utf-8-sig').splitlines() if line)
assert len(rows)==12
groups=[]
for rival in [78,361]:
    for level in [30,60,99]:
        selected=[r for r in rows if r['authorityContext']['rivalUnitId']==rival and r['authorityContext']['level']==level]
        assert len(selected)==2 and {r['authorityContext']['candidateSide'] for r in selected}=={'blue','red'}
        values=[]
        for r in selected:
            other='red' if r['authorityContext']['candidateSide']=='blue' else 'blue'
            assert r['status']=='finished' and r['winner']==other and not r['errors'] and r['phaseSpawnCount']==1
            values.append(100*(1-r[other]['remainHp']/r[other]['startMaxHp']))
        assert statistics.mean(values)>=25 and statistics.median(values)>=25,(rival,level,values)
        groups.append({'rival':rival,'level':level,'netLoss':values,'mean':statistics.mean(values)})
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log','launcher.log.1','bootstrap.log']:
        source=root/'logs'/log
        if source.is_file():put(TMP/('r8-pilot-final-w'+str(index)+'-'+log),read(source))
put(TMP/'r8-pilot-diagnostics.jsonl',read(TMP/'live-elder-audit-r7.jsonl'))
jput(TMP/'r8-pilot-review.json',{'games':12,'wins':0,'groups':groups,'scope':'Small pilot permits a separately retained repeated matrix; not final positioning acceptance.'})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r8-matrix-20261017',repeat=3,levels=[30,60,99],outputDirectory=str(TMP/'matrix-r8'))
jput(TMP/'matrix-r8-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r8-config.json')],cwd=ROOT,check=True)
print(json.dumps({'pilotGroups':groups,'next':'Fresh R8 repeated matrix is ready'},ensure_ascii=False))
