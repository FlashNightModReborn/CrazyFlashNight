from evidence_utils import *
import statistics,subprocess

report=js(ROOT/'tmp/arena-worker-experiments/elder-r11-matrix-20261017/experiment-report.json')
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
        stats.append({'rival':rival,'level':level,'wins':wins,'netLoss':values,'min':min(values),
            'mean':statistics.mean(values),'median':statistics.median(values),'max':max(values)})
jput(TMP/'r11-matrix-review.json',{'games':36,'wins':sum(r['wins'] for r in stats),'groups':stats,'acceptedAsFinal':False,
    'workingCriterionMet':all(r['mean']>=25 and r['median']>=25 and r['max']<=85 and r['wins']==0 for r in stats)})
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log','launcher.log.1','bootstrap.log']:
        source=root/'logs'/log
        if source.is_file():put(TMP/('r11-matrix-final-w'+str(index)+'-'+log),read(source))
for file in TMP.glob('live-elder-audit-r*.jsonl'):
    put(TMP/('r11-matrix-final-'+file.name),read(file))
native=js(TMP/'native-r12-evidence.json')
for row in native['sourceBindings']:assert sha(ROOT/row['path'])==row['sha256']
for row in js(TMP/'matrix-r11/input-identity.json')['sourceBindings']:
    if row['path'] not in ['flashswf/arts/new/Codex老头素材.swf','tools/cf6-elder-assets/ElderAI.as','tools/cf6-elder-assets/native-manifest.json']:
        assert sha(ROOT/row['path'])==row['sha256'],'Unexpected R12 source drift: '+row['path']

readme=ROOT/'tools/cf6-elder-assets/README.md'
text=read(readme).decode('utf8')
put(TMP/'r11-before-ai/tools/cf6-elder-assets/README.md',read(readme))
replacements={
    '当前 R7 发布资源为 **356,913 字节':'当前 R12 发布资源为 **356,928 字节',
    'R7 行为测试为 **668 passed / 0 failed**':'R12 行为测试为 **680 passed / 0 failed**',
    '当前行为与发布 SWF 为 R7，配表为 R11。':'当前候选为 R12：行为与发布 SWF 为 R12，配表沿用 R11。',
    '完整原生绘制在 R6 覆盖':'R12 把机器人连踢起手距离从 150 调到 190 像素；两段推进、两次接触区域与伤害倍率未改。真实发布资源的测试验证了左右朝向从 190 像素起手后均能在原第 9／26 帧接触目标，推进不越过 90 像素停止距离。\n\n完整原生绘制在 R6 覆盖',
    '这些证据明确分层，不把旧图像写成新版本重新截图。':'R12 的 85 个 XML 再次与 R7 去除脚本后相同，并通过新一轮 6 点绘制探针（16 passed / 0 failed）。这些证据明确分层，不把旧图像写成新版本重新截图。',
    '固定比例 `BitmapData.draw` 夹具的重复绘制中位数':'R6 固定比例 `BitmapData.draw` 夹具的重复绘制中位数'
}
for old,new in replacements.items():
    assert text.count(old)==1,old
    text=text.replace(old,new)
beast99=next(r for r in stats if r['rival']==78 and r['level']==99)
wins=sum(r['wins'] for r in stats)
history=f"R11 完整 36 场为 {wins} 胜、{36-wins} 负；99 级兽王平均净生命损失 {beast99['mean']:.2f}%、中位数 {beast99['median']:.2f}%，仍未达线。R12 保留全部 R11 配表，只将连踢起手距离与已验证的推进／接触范围对齐；不按对手身份改行为，也不改对手与伤害结算。\n\n"
needle='工作判据在 R8 开跑前选定：'
assert text.count(needle)==1;text=text.replace(needle,history+needle)
readme.write_text(text,encoding='utf8',newline='\n')

paths=[r['path'] for r in js(TMP/'r11-frozen-inputs/frozen-inputs.zip.index.json')['files']]
changed=[]
for name in ['headbot-combat','headbot-combat2']:
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for relative in paths:
        destination=lp(root/relative);data=read(ROOT/relative)
        old=sha(destination) if destination.is_file() else None
        if old==digest(data):continue
        assert relative.startswith(('tools/cf6-elder-assets/','flashswf/arts/new/Codex老头素材/')) or relative in [
            'flashswf/arts/new/Codex老头素材.swf','scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as'],relative
        destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(data)
        assert sha(destination)==digest(data)
        changed.append({'root':str(root),'path':relative,'beforeSha256':old,'sha256':digest(data)})
jput(TMP/'worker-copy-r12.json',{'scope':'R12 robot kick reach only with updated tests/documentation and fresh native asset; panel and all shared game sources unchanged','files':changed})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r12-matrix-20261017',repeat=3,levels=[99,30,60],outputDirectory=str(TMP/'matrix-r12'))
jput(TMP/'matrix-r12-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r12-config.json')],cwd=ROOT,check=True)
frozen=Package(TMP/'r12-frozen-inputs');frozen.freeze(paths)
print(json.dumps({'r11Groups':stats,'r12FrozenInputs':frozen.finish()},ensure_ascii=False))
print('R12 full matrix prepared; prior matrix retained and both workers synchronized after verified exit.')
