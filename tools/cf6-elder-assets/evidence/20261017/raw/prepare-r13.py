from evidence_utils import *
import statistics,subprocess,sys

assert len(sys.argv)==2 and int(sys.argv[1]) in [28,30,32],'Choose a reviewed allocation estimate explicitly'
defense=int(sys.argv[1])
report=js(ROOT/'tmp/arena-worker-experiments/elder-r12-matrix-20261017/experiment-report.json')
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
        values=[];wins=0
        for row in subset:
            side=row['authorityContext']['candidateSide'];other='red' if side=='blue' else 'blue'
            assert row['status']=='finished' and row['winner'] in ['blue','red'] and not row['errors'] and row['phaseSpawnCount']==1
            wins+=int(row['winner']==side)
            values.append(100*(1-row[other]['remainHp']/row[other]['startMaxHp']))
        stats.append({'rival':rival,'level':level,'wins':wins,'netLoss':values,'min':min(values),'mean':statistics.mean(values),
            'median':statistics.median(values),'max':max(values)})
old_criterion=all(r['mean']>=25 and r['median']>=25 and r['wins']==0 for r in stats)
margin_met=all(r['max']<=85 for r in stats)
jput(TMP/'r12-matrix-review.json',{'games':36,'wins':sum(r['wins'] for r in stats),'groups':stats,'acceptedAsFinal':False,
    'originalWorkingCriterionMet':old_criterion,'fifteenPercentWinnerMarginMet':margin_met})
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log','launcher.log.1','bootstrap.log']:
        p=root/'logs'/log
        if p.is_file():put(TMP/('r12-matrix-final-w'+str(index)+'-'+log),read(p))
for file in TMP.glob('live-elder-audit-r*.jsonl'):put(TMP/('r12-matrix-final-'+file.name),read(file))
for row in js(TMP/'matrix-r12/input-identity.json')['sourceBindings']:
    assert sha(ROOT/row['path'])==row['sha256'],'Unexpected R12 source drift: '+row['path']
for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json',
    'data/enemy_properties/CF6重制敌人.xml','tools/cf6-elder-assets/README.md']:
    put(TMP/'r12-before-balance'/relative,read(ROOT/relative))
file=ROOT/'tools/cf6-elder-assets/balance.py';old=read(file).decode('utf8')
needle="'growth':1,'attackBias':2,'defenseBias':40}"
assert old.count(needle)==1
file.write_text(old.replace(needle,"'growth':1,'attackBias':2,'defenseBias':"+str(defense)+'}'),encoding='utf8',newline='\n')
subprocess.run(['python','-X','utf8','-B',str(file),'--write'],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B',str(file)],cwd=ROOT,check=True)
readme=ROOT/'tools/cf6-elder-assets/README.md';text=read(readme).decode('utf8')
before='当前候选为 R12：行为与发布 SWF 为 R12，配表沿用 R11。'
assert text.count(before)==1
text=text.replace(before,'当前候选为 R13：行为与发布 SWF 沿用 R12，配表为 R13。')
text=text.replace('高防低血 40','高防低血 '+str(defense))
beast30=next(r for r in stats if r['rival']==78 and r['level']==30)
wins=sum(r['wins'] for r in stats)
history=f"R12 完整 36 场为 {wins} 胜、{36-wins} 负；原均值／中位数与零胜局判据{'通过' if old_criterion else '未通过'}，但 30 级兽王最接近的一场仅剩 {100-beast30['max']:.2f}% 生命，未通过开跑前已采用的 15% 余量检查。R13 仅将机器人高防低血分配从 40 调至 {defense}，保留 R12 连踢范围、全部伤害倍率与成长 1；阶段／档次不变。该分配会降低物理有效耐久并提高名义生命值，不能仅凭公式推断混合伤害与吸血对局的结果，须重新完成全部矩阵。\n\n"
needle='工作判据在 R8 开跑前选定：';assert text.count(needle)==1
text=text.replace(needle,history+needle);readme.write_text(text,encoding='utf8',newline='\n')
changed=[]
for name in ['headbot-combat','headbot-combat2']:
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
        destination=lp(root/relative);old_hash=sha(destination);data=read(ROOT/relative)
        destination.write_bytes(data);assert sha(destination)==digest(data)
        changed.append({'root':str(root),'path':relative,'beforeSha256':old_hash,'sha256':digest(data)})
jput(TMP/'worker-copy-r13.json',{'scope':'Robot high-defense allocation 40 to '+str(defense)+' only; all native assets, observed flags and user-fixed C/D unchanged','files':changed})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r13-matrix-20261017',repeat=3,levels=[30,99,60],outputDirectory=str(TMP/'matrix-r13'))
jput(TMP/'matrix-r13-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r13-config.json')],cwd=ROOT,check=True)
frozen=Package(TMP/'r13-frozen-inputs')
frozen.freeze(r['path'] for r in js(TMP/'r12-frozen-inputs/frozen-inputs.zip.index.json')['files'])
print(json.dumps({'priorGroups':stats,'defenseAllocation':defense,'r13FrozenInputs':frozen.finish()},ensure_ascii=False))
