from evidence_utils import *
import statistics, subprocess, sys

assert len(sys.argv)==2 and int(sys.argv[1])==34, 'R14 selects allocation 34 after both EX30 and EX60 failed in R13; it remains between R13=28 and R12=40'
defense=int(sys.argv[1])
report=js(ROOT/'tmp/arena-worker-experiments/elder-r13-matrix-20261017/experiment-report.json')
assert report['qualified'] and report['status']=='completed' and report['completedGroups']==6 and not report['errors']
rows=[]
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:
        assert outcome['status']=='completed' and all(outcome[k] for k in ['cleanupVerified','runtimeResourcesVerified','protectedSavesVerified'])
        receipt=js(outcome['expectedReceiptPath'])
        assert sha(outcome['expectedReceiptPath'])==outcome['receiptSha256'].removeprefix('sha256:')
        assert receipt['runtimeUnchanged'] and receipt['resourcesUnchanged'] and not receipt['errors']
        assert sha(receipt['resultPath'])==receipt['resultSha256'].removeprefix('sha256:')
        rows.extend(json.loads(line) for line in read(receipt['resultPath']).decode('utf-8-sig').splitlines() if line)
assert len(rows)==36 and len({(r['batchId'],r['runId']) for r in rows})==36
stats=[]
for rival in [78,361]:
    for level in [30,60,99]:
        subset=[r for r in rows if r['authorityContext']['rivalUnitId']==rival and r['authorityContext']['level']==level]
        assert len(subset)==6
        for side in ['blue','red']:
            assert {r['repeatIndex'] for r in subset if r['authorityContext']['candidateSide']==side}=={1,2,3}
        values=[];wins=0
        for row in subset:
            side=row['authorityContext']['candidateSide'];other='red' if side=='blue' else 'blue'
            assert row['status']=='finished' and row['winner'] in ['blue','red'] and not row['errors'] and row['phaseSpawnCount']==1
            wins+=int(row['winner']==side)
            values.append(100*(1-row[other]['remainHp']/row[other]['startMaxHp']))
        stats.append({'rival':rival,'level':level,'wins':wins,'netLoss':values,'min':min(values),'mean':statistics.mean(values),
            'median':statistics.median(values),'max':max(values)})
original_met=all(r['mean']>=25 and r['median']>=25 and r['wins']==0 for r in stats)
margin_met=all(r['max']<=85 for r in stats)
assert next(r for r in stats if r['rival']==361 and r['level']==30)['median']<25
jput(TMP/'r13-matrix-review.json',{'games':36,'wins':sum(r['wins'] for r in stats),'groups':stats,'acceptedAsFinal':False,
    'originalWorkingCriterionMet':original_met,'fifteenPercentWinnerMarginMet':margin_met})
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log','launcher.log.1','bootstrap.log']:
        p=root/'logs'/log
        if p.is_file():put(TMP/('r13-matrix-final-w'+str(index)+'-'+log),read(p))
for file in TMP.glob('live-elder-audit-r*.jsonl'):put(TMP/('r13-matrix-final-'+file.name),read(file))
for row in js(TMP/'matrix-r13/input-identity.json')['sourceBindings']:
    assert sha(ROOT/row['path'])==row['sha256'],'Unexpected R13 source drift: '+row['path']
for row in js(TMP/'native-r12-evidence.json')['sourceBindings']:
    assert sha(ROOT/row['path'])==row['sha256'],'Unexpected native source drift: '+row['path']
for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json',
    'data/enemy_properties/CF6重制敌人.xml','tools/cf6-elder-assets/README.md']:
    put(TMP/'r13-before-balance'/relative,read(ROOT/relative))
file=ROOT/'tools/cf6-elder-assets/balance.py';old=read(file).decode('utf8')
needle="'growth':1,'attackBias':2,'defenseBias':28}"
assert old.count(needle)==1
file.write_text(old.replace(needle,"'growth':1,'attackBias':2,'defenseBias':34}"),encoding='utf8',newline='\n')
subprocess.run(['python','-X','utf8','-B',str(file),'--write'],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B',str(file)],cwd=ROOT,check=True)
readme=ROOT/'tools/cf6-elder-assets/README.md';text=read(readme).decode('utf8')
before='当前候选为 R13：行为与发布 SWF 沿用 R12，配表为 R13。'
assert text.count(before)==1
text=text.replace(before,'当前候选为 R14：行为与发布 SWF 沿用 R12，配表为 R14。')
text=text.replace('高防低血 28','高防低血 34')
failures=[]
for r in stats:
    name='兽王' if r['rival']==78 else '指挥官'
    if r['mean']<25 or r['median']<25:
        failures.append(f"{r['level']} 级{name}均值／中位数 {r['mean']:.2f}%／{r['median']:.2f}% 未同时达线")
    if r['wins'] or r['max']>85:
        failures.append(f"{r['level']} 级{name}出现 {r['wins']} 胜、最大净失血 {r['max']:.2f}%")
wins=sum(r['wins'] for r in stats)
history=f"R13 完整 36 场为 {wins} 胜、{36-wins} 负；"+'；'.join(failures)+'。完整结果确认两个指挥官组均偏弱后，R14 将机器人高防低血分配从 28 调为 34，取 R13 与 R12 之间的分配，其他系数、原生资源与行为均不变；同样重跑全部六组，不删除低输出场次或降低既定阈值。此前预估的 32 未执行，不计为对战证据。\n\n'
needle='工作判据在 R8 开跑前选定：';assert text.count(needle)==1
text=text.replace(needle,history+needle);readme.write_text(text,encoding='utf8',newline='\n')
changed=[]
for name in ['headbot-combat','headbot-combat2']:
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
        destination=lp(root/relative);old_hash=sha(destination);data=read(ROOT/relative)
        destination.write_bytes(data);assert sha(destination)==digest(data)
        changed.append({'root':str(root),'path':relative,'beforeSha256':old_hash,'sha256':digest(data)})
jput(TMP/'worker-copy-r14.json',{'scope':'Robot high-defense allocation 28 to 34 only; all native assets, measured flags and user-fixed C/D unchanged','files':changed})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r14-matrix-20261017',repeat=3,levels=[30,60,99],rivals=['exusiai','beastking'],outputDirectory=str(TMP/'matrix-r14'))
jput(TMP/'matrix-r14-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r14-config.json')],cwd=ROOT,check=True)
frozen=Package(TMP/'r14-frozen-inputs')
frozen_paths={r['path'] for r in js(TMP/'r13-frozen-inputs/frozen-inputs.zip.index.json')['files']}
frozen_paths.update(['tools/cf6-bladebot-assets/balance.py','data/enemy_properties/诺亚新敌人.xml',
    'tools/cf7-balance-tool/data/monster-census.json','tools/cf7-balance-tool/docs/monster-flag-rulebook.md',
    'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts','tools/cf7-balance-tool/packages/core/package.json',
    'tools/cf7-balance-tool/package.json','tools/cf7-balance-tool/package-lock.json'])
frozen.freeze(frozen_paths)
print(json.dumps({'priorGroups':stats,'defenseAllocation':defense,'r14FrozenInputs':frozen.finish()},ensure_ascii=False))
