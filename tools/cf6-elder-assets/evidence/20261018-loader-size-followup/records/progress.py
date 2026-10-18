from pathlib import Path
import hashlib,json
R=Path.cwd()
def lp(p):
    p=str(Path(p).resolve());return Path(p if p.startswith('\\\\?\\') else '\\\\?\\'+p)
def read(p):return json.loads(lp(p).read_text('utf-8-sig'))
all_groups=[];failed=[]
for kind in ['head','elder']:
    E=R/'tmp/arena-worker-experiments'/f'cf6-loader-c6-{kind}-20261018'
    for p in E.rglob('group-report.json'):
        g=read(p);assert g['globalSaveUnchanged'] and g['seedSourcesUnchanged']
        rows=[]
        for o in g['outcomes']:
            if o['status']!='completed':
                failed.append({'kind':kind,'group':g['groupId'],'status':o['status'],'receipt':o['expectedReceiptPath']})
                continue
            assert o['cleanupVerified'] and o['protectedSavesVerified'] and o['runtimeResourcesVerified']
            receipt=read(o['expectedReceiptPath']);data=lp(receipt['resultPath']).read_bytes()
            assert hashlib.sha256(data).hexdigest()==receipt['resultSha256'].removeprefix('sha256:')
            rows += [json.loads(s) for s in data.decode('utf-8-sig').splitlines()]
        if not rows:continue
        assert all(not x['errors'] for x in rows)
        all_groups.append({'kind':kind,'level':rows[0]['authorityContext']['level'],
            'rival':rows[0]['authorityContext']['rivalUnitId'],'rows':len(rows),
            'wins':sum(x['status']=='finished' and x['winner']==x['authorityContext']['candidateSide'] for x in rows),
            'timeouts':sum(x['status']=='timeout' for x in rows),
            'ownPhaseSpawns':[len([s for s in x['spawnedUnits'] if s['side']==x['authorityContext']['candidateSide']]) for x in rows]})
print(json.dumps({'groups':all_groups,'failedGroups':failed,'rows':sum(x['rows'] for x in all_groups),
    'headFinal':(R/'tmp/arena-worker-experiments/cf6-loader-c6-head-20261018/experiment-report.json').exists(),
    'elderFinal':(R/'tmp/arena-worker-experiments/cf6-loader-c6-elder-20261018/experiment-report.json').exists()}))
