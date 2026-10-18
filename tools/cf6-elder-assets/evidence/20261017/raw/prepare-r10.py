from evidence_utils import *
import statistics, subprocess

experiment='elder-r9-matrix-20261017'
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
assert len(rows)==36
stats=[]
for rival in [78,361]:
    for level in [30,60,99]:
        subset=[r for r in rows if r['authorityContext']['rivalUnitId']==rival and r['authorityContext']['level']==level]
        assert len(subset)==6
        values=[]
        for r in subset:
            other='red' if r['authorityContext']['candidateSide']=='blue' else 'blue'
            assert r['status']=='finished' and r['winner']==other and not r['errors'] and r['phaseSpawnCount']==1
            values.append(100*(1-r[other]['remainHp']/r[other]['startMaxHp']))
        stats.append({'rival':rival,'level':level,'netLoss':values,'mean':statistics.mean(values),'median':statistics.median(values)})
jput(TMP/'r9-matrix-review.json',{'games':36,'wins':0,'groups':stats,'targetMet':all(r['mean']>=25 and r['median']>=25 for r in stats),
    'scope':'Six samples per same-level group; R9 misses the preselected group mean criterion at Beast King 99. All attempts retained.'})
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log','launcher.log.1','bootstrap.log']:
        source=root/'logs'/log
        if source.is_file():put(TMP/('r9-matrix-final-w'+str(index)+'-'+log),read(source))
put(TMP/'r9-matrix-diagnostics.jsonl',read(TMP/'live-elder-audit-r7.jsonl'))
for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
    put(TMP/'r9-before-balance'/relative,read(ROOT/relative))
file=ROOT/'tools/cf6-elder-assets/balance.py'
old=read(file).decode('utf8')
before="'growth':0.9,'attackBias':2,'defenseBias':40}"
after="'growth':1.1,'attackBias':2,'defenseBias':40}"
assert old.count(before)==1
file.write_text(old.replace(before,after),encoding='utf8',newline='\n')
subprocess.run(['python','-X','utf8','-B',str(file),'--write'],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B',str(file)],cwd=ROOT,check=True)
readme=ROOT/'tools/cf6-elder-assets/README.md'
old_readme=read(readme).decode('utf8')
put(TMP/'r9-before-balance/tools/cf6-elder-assets/README.md',read(readme))
assert old_readme.count('配表为 R9')==1 and old_readme.count('机器人成长 0.9')==1
updated_readme=old_readme.replace('配表为 R9','配表为 R10').replace('机器人成长 0.9','机器人成长 1.1')
before='机器人较低成长控制后段攻击增长，高防低血分配用于'
after='机器人成长 1.1 用于补足高等级压力，30 级面板几乎不变；高防低血分配用于'
assert updated_readme.count(before)==1
updated_readme=updated_readme.replace(before,after)
before='R9 只把机器人高防低血从 28 调为 40，其他输入、行为脚本和 SWF 不变。'
assert updated_readme.count(before)==1
beast99=next(r for r in stats if r['rival']==78 and r['level']==99)
ex99=next(r for r in stats if r['rival']==361 and r['level']==99)
after=before+f"\n\nR9 完整 36 场全部自然落败，但 99 级兽王平均净生命损失 {beast99['mean']:.2f}%、中位数 {beast99['median']:.2f}%，平均值仍未达线；同版 99 级指挥官的最大净损失为 {max(ex99['netLoss']):.2f}%。R10 仅将机器人成长从 0.9 调为 1.1，阶段、档次、攻防分配、动作和 SWF 均不变，重新执行完整矩阵。"
readme.write_text(updated_readme.replace(before,after),encoding='utf8',newline='\n')
changed=[]
for name in ['headbot-combat','headbot-combat2']:
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
        destination=lp(root/relative);before_hash=sha(destination);data=read(ROOT/relative);destination.write_bytes(data)
        assert sha(destination)==digest(data)
        changed.append({'root':str(root),'path':relative,'beforeSha256':before_hash,'sha256':digest(data)})
jput(TMP/'worker-copy-r10.json',{'scope':'Robot growth 0.9 to 1.1 only; fixed stage/tier, attack/defense allocation, measured actions, R7 AI and all SWFs unchanged','files':changed})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r10-matrix-20261017',repeat=3,levels=[99,30,60],outputDirectory=str(TMP/'matrix-r10'))
jput(TMP/'matrix-r10-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r10-config.json')],cwd=ROOT,check=True)
frozen=Package(TMP/'r10-frozen-inputs')
frozen.freeze(r['path'] for r in js(TMP/'r9-frozen-inputs/frozen-inputs.zip.index.json')['files'])
print(json.dumps({'r10FrozenInputs':frozen.finish()},ensure_ascii=False))
print('R10 repeated matrix ready; no outcomes asserted.')
