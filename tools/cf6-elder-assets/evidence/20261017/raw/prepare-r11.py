from evidence_utils import *
import statistics,subprocess

experiment='elder-r10-matrix-20261017'
report=js(ROOT/'tmp/arena-worker-experiments'/experiment/'experiment-report.json')
assert report['qualified'] and report['status']=='completed' and report['completedGroups']==6 and not report['errors']
rows=[]
for g in report['groups']:
    assert g['globalSaveUnchanged'] and g['seedSourcesUnchanged']
    for o in g['outcomes']:
        assert o['status']=='completed' and all(o[k] for k in ['cleanupVerified','runtimeResourcesVerified','protectedSavesVerified'])
        receipt=js(o['expectedReceiptPath'])
        assert sha(o['expectedReceiptPath'])==o['receiptSha256'].removeprefix('sha256:')
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
        for r in subset:
            side=r['authorityContext']['candidateSide'];other='red' if side=='blue' else 'blue'
            assert r['status']=='finished' and r['winner'] in ['blue','red'] and not r['errors'] and r['phaseSpawnCount']==1
            wins+=int(r['winner']==side)
            values.append(100*(1-r[other]['remainHp']/r[other]['startMaxHp']))
        stats.append({'rival':rival,'level':level,'wins':wins,'netLoss':values,'min':min(values),
            'mean':statistics.mean(values),'median':statistics.median(values),'max':max(values)})
old_criterion=all(r['mean']>=25 and r['median']>=25 and r['wins']==0 for r in stats)
margin_met=all(r['max']<=85 for r in stats)
total_wins=sum(r['wins'] for r in stats)
jput(TMP/'r10-matrix-review.json',{'games':36,'wins':total_wins,'groups':stats,
    'originalWorkingCriterionMet':old_criterion,'fifteenPercentWinnerMarginMet':margin_met,'acceptedAsFinal':False,
    'scope':'All R10 results retained. The original 25-percent mean/median and zero-win rule is reported separately. Before R11 execution a further conservative criterion requires every opponent to retain at least 15 percent HP; R10 is not relabeled as failing the original rule solely because of a narrow winning margin.'})
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log','launcher.log.1','bootstrap.log']:
        source=root/'logs'/log
        if source.is_file():put(TMP/('r10-matrix-final-w'+str(index)+'-'+log),read(source))
put(TMP/'r10-matrix-diagnostics.jsonl',read(TMP/'live-elder-audit-r7.jsonl'))
for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json',
    'data/enemy_properties/CF6重制敌人.xml','tools/cf6-elder-assets/README.md']:
    put(TMP/'r10-before-balance'/relative,read(ROOT/relative))
file=ROOT/'tools/cf6-elder-assets/balance.py'
old=read(file).decode('utf8')
before="'growth':1.1,'attackBias':2,'defenseBias':40}"
after="'growth':1,'attackBias':2,'defenseBias':40}"
assert old.count(before)==1
file.write_text(old.replace(before,after),encoding='utf8',newline='\n')
subprocess.run(['python','-X','utf8','-B',str(file),'--write'],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B',str(file)],cwd=ROOT,check=True)
readme=ROOT/'tools/cf6-elder-assets/README.md'
old_readme=read(readme).decode('utf8')
assert old_readme.count('配表为 R10')==1
updated=old_readme.replace('配表为 R10','配表为 R11').replace('机器人成长 1.1','机器人成长 1.0')
ex99=next(r for r in stats if r['rival']==361 and r['level']==99)
prefix=f"R10 完整 36 场为 {total_wins} 胜、{36-total_wins} 负；原均值／中位数与零胜局工作判据{'通过' if old_criterion else '未通过'}。99 级指挥官最接近的一场仅剩 {100-ex99['max']:.2f}% 生命。为给不能击败对手的定位增加余量，R11 只将机器人成长从 1.1 收至 1.0，并在开跑前补充每场胜方至少保留 15% 生命的保守选版检查。此值仅用于本轮候选，不是任意随机局面的胜率保证。\n\n"
assert updated.count('工作判据在 R8 开跑前选定：')==1
updated=updated.replace('工作判据在 R8 开跑前选定：',prefix+'工作判据在 R8 开跑前选定：')
readme.write_text(updated,encoding='utf8',newline='\n')
changed=[]
for name in ['headbot-combat','headbot-combat2']:
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
        destination=lp(root/relative);before_hash=sha(destination);data=read(ROOT/relative);destination.write_bytes(data)
        assert sha(destination)==digest(data)
        changed.append({'root':str(root),'path':relative,'beforeSha256':before_hash,'sha256':digest(data)})
jput(TMP/'worker-copy-r11.json',{'scope':'Robot growth 1.1 to 1.0 only; all fixed/observed flags, allocation, R7 AI and SWFs unchanged','files':changed})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r11-matrix-20261017',repeat=3,levels=[99,30,60],outputDirectory=str(TMP/'matrix-r11'))
jput(TMP/'matrix-r11-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r11-config.json')],cwd=ROOT,check=True)
frozen=Package(TMP/'r11-frozen-inputs')
frozen.freeze(r['path'] for r in js(TMP/'r10-frozen-inputs/frozen-inputs.zip.index.json')['files'])
print(json.dumps({'r11FrozenInputs':frozen.finish()},ensure_ascii=False))
print('R11 repeated matrix ready; every opponent must retain at least 15 percent HP in addition to the existing criterion.')
