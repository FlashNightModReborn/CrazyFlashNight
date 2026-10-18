from evidence_utils import *
import statistics, subprocess

report=js(ROOT/'tmp/arena-worker-experiments/elder-r14-matrix-20261017/experiment-report.json')
assert report['qualified'] and report['status']=='completed' and report['completedGroups']==6 and not report['errors']
rows=[]
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:
        assert outcome['status']=='completed' and all(outcome[k] for k in ['cleanupVerified','protectedSavesVerified','runtimeResourcesVerified'])
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
        stats.append({'rival':rival,'level':level,'wins':wins,'values':values,'min':min(values),
            'mean':statistics.mean(values),'median':statistics.median(values),'max':max(values)})
assert next(r for r in stats if r['rival']==361 and r['level']==30)['median']<25
jput(TMP/'r14-matrix-review.json',{'games':36,'wins':sum(r['wins'] for r in stats),'groups':stats,'acceptedAsFinal':False,
    'originalWorkingCriterionMet':all(r['mean']>=25 and r['median']>=25 and r['wins']==0 for r in stats),
    'fifteenPercentWinnerMarginMet':all(r['max']<=85 for r in stats)})
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log','launcher.log.1','bootstrap.log']:
        p=root/'logs'/log
        if p.is_file():put(TMP/('r14-matrix-final-w'+str(index)+'-'+log),read(p))
for file in TMP.glob('live-elder-audit-r*.jsonl'):put(TMP/('r14-matrix-final-'+file.name),read(file))
native=js(TMP/'native-r15-evidence.json')
for row in native['sourceBindings']:assert sha(ROOT/row['path'])==row['sha256']
old_bindings=js(TMP/'matrix-r14/input-identity.json')['sourceBindings']
changed=[r['path'] for r in old_bindings if sha(ROOT/r['path'])!=r['sha256']]
assert set(changed)=={'flashswf/arts/new/Codex老头素材.swf','tools/cf6-elder-assets/ElderAI.as','tools/cf6-elder-assets/native-manifest.json'}
assert js(TMP/'r15-integration-scope.json')['graphicsXmlFilesEqual']==85

readme=ROOT/'tools/cf6-elder-assets/README.md';text=read(readme).decode('utf8')
put(TMP/'readme-before-r15-field.md',read(readme))
before='当前候选为 R14：行为与发布 SWF 沿用 R12，配表为 R14。'
assert text.count(before)==1
text=text.replace(before,'当前候选为 R15：行为与发布 SWF 为 R15，配表沿用 R14。')
before='机器人在各招式接触前暂时持有刚体，光束另在蓄能到第 29 帧持有抗击退；两项分别保存和恢复原值，不减少伤害。'
assert text.count(before)==1
text=text.replace(before,'机器人近战在各招式接触前暂时持有刚体；光束在完整 64 帧动作中持有刚体，蓄能至第 29 帧另持有抗击退。两项分别保存和恢复原值，不减少伤害。')
before='光束第 30 帧释放这两项状态；各招式收招、中断或死亡也会释放仍持有的状态。'
assert text.count(before)==1
text=text.replace(before,'光束第 30 帧恢复原抗击退状态，因此收招期间仍可被水平推动；正常收招、中断或死亡恢复仍持有的刚体与抗击退状态。')
before='当前 R12 发布资源为 **356,928 字节、53 个 Shape、28 个 Sprite、0 位图**，XFL 共 82 个元件。真实 CS6 发布和专项测试都要求当轮 Compiler 0/0。R12 行为测试为 **680 passed / 0 failed**，包含 34 组实际时间轴动作、13 组阶段场景，以及共用被击移动、变形接地、追踪与状态恢复。'
assert text.count(before)==1
text=text.replace(before,f"当前 R15 发布资源为 **{native['swfBytes']:,} 字节、53 个 Shape、28 个 Sprite、0 位图**，XFL 共 82 个元件。真实 CS6 发布和专项测试都要求当轮 Compiler 0/0。R15 行为测试为 **690 passed / 0 failed**，包含 34 组实际时间轴动作、13 组阶段场景，以及共用被击移动、变形接地、追踪与状态恢复。")
needle='完整原生绘制在 R6 覆盖'
assert text.count(needle)==1
text=text.replace(needle,'R15 只让光束刚体保持到完整收招，其他招式、伤害倍率、时序与配表不变。新增左右两侧的收招夹具使用真实伤害与冲击函数：承伤计算不减免、强制冲击不打断已承诺的收招、发射后仍允许真实水平击退，结束后状态恢复。此设计在旧 R12 资源的对照中为 684 passed / 6 failed，新资源为 690 passed / 0 failed；不将夹具改善写成尚未取得的实战收益。\n\n'+needle)
needle='这些证据明确分层，不把旧图像写成新版本重新截图。'
assert text.count(needle)==1
text=text.replace(needle,'R15 的 85 个 XML 去除脚本后仍与 R12 相同，并通过本轮 6 点绘制探针（16 passed / 0 failed）。'+needle)
failures=[]
for r in stats:
    name='兽王' if r['rival']==78 else '指挥官'
    if r['mean']<25 or r['median']<25:failures.append(f"{r['level']} 级{name}均值／中位数 {r['mean']:.2f}%／{r['median']:.2f}% 未同时达线")
    if r['wins'] or r['max']>85:failures.append(f"{r['level']} 级{name}出现 {r['wins']} 胜、最大净失血 {r['max']:.2f}%")
wins=sum(r['wins'] for r in stats)
history=f"R14 完整 36 场为 {wins} 胜、{36-wins} 负；"+'；'.join(failures)+'。R15 保留全部 R14 配表，只调整上述光束收招刚体，重新检查两个对手和全部等级；旧数据与低输出场次全部保留。\n\n'
needle='工作判据在 R8 开跑前选定：';assert text.count(needle)==1
text=text.replace(needle,history+needle)
readme.write_text(text,encoding='utf8',newline='\n')

index=js(TMP/'r14-frozen-inputs/frozen-inputs.zip.index.json')['files']
own=lambda p:p.startswith(('tools/cf6-elder-assets/','flashswf/arts/new/Codex老头素材/')) or p in [
    'flashswf/arts/new/Codex老头素材.swf','scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as']
sync=[]
for name in ['headbot-combat','headbot-combat2']:
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for row in index:
        relative=row['path']
        if not own(relative):continue
        current=sha(ROOT/relative)
        if current==row['sha256']:continue
        target=lp(root/relative);before=sha(target)
        assert relative=='tools/cf6-elder-assets/README.md' or before==row['sha256'],'Unexpected owned Worker drift: '+relative
        target.write_bytes(read(ROOT/relative));assert sha(target)==current
        sync.append({'root':str(root),'path':relative,'beforeSha256':before,'sha256':current})
    for row in old_bindings:assert sha(root/row['path'])==sha(ROOT/row['path']),'Declared Worker input drift: '+row['path']
jput(TMP/'worker-copy-r15.json',{'scope':'R15 Elder native behavior, matching root XML, test and current README only; all 17 declared inputs match. Offline helper exclusions remain as recorded in worker-copy-r12.json; no whole-worktree equality claim.','files':sync})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r15-matrix-20261017',repeat=3,levels=[30,60,99],rivals=['exusiai','beastking'],outputDirectory=str(TMP/'matrix-r15'))
jput(TMP/'matrix-r15-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r15-config.json')],cwd=ROOT,check=True)
frozen=Package(TMP/'r15-frozen-inputs');frozen.freeze(r['path'] for r in index)
print(json.dumps({'priorGroups':stats,'workerFilesCopied':len(sync),'r15FrozenInputs':frozen.finish()},ensure_ascii=False))
