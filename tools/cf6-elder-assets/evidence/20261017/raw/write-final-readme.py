from evidence_utils import *
import re,statistics,sys

revision=sys.argv[1]
assert re.fullmatch(r'r\d+',revision)
report=js(ROOT/'tmp/arena-worker-experiments'/('elder-'+revision+'-matrix-20261017')/'experiment-report.json')
assert report['qualified'] and report['status']=='completed' and report['completedGroups']==6 and not report['errors']
rows=[]
for g in report['groups']:
    assert g['globalSaveUnchanged'] and g['seedSourcesUnchanged']
    for o in g['outcomes']:
        assert o['status']=='completed' and all(o[k] for k in ['cleanupVerified','protectedSavesVerified','runtimeResourcesVerified'])
        receipt=js(o['expectedReceiptPath'])
        assert sha(o['expectedReceiptPath'])==o['receiptSha256'].removeprefix('sha256:')
        assert receipt['runtimeUnchanged'] and receipt['resourcesUnchanged'] and not receipt['errors']
        assert sha(receipt['resultPath'])==receipt['resultSha256'].removeprefix('sha256:')
        rows.extend(json.loads(line) for line in read(receipt['resultPath']).decode('utf-8-sig').splitlines() if line)
assert len(rows)==36 and len({(r['batchId'],r['runId']) for r in rows})==36
stats=[]
for rival,name in [(78,'方舟兽王'),(361,'EXUSIAI 指挥官')]:
    for level in [30,60,99]:
        subset=[r for r in rows if r['authorityContext']['rivalUnitId']==rival and r['authorityContext']['level']==level]
        assert len(subset)==6
        for side in ['blue','red']:
            assert {r['repeatIndex'] for r in subset if r['authorityContext']['candidateSide']==side}=={1,2,3}
        values=[]
        for r in subset:
            other='red' if r['authorityContext']['candidateSide']=='blue' else 'blue'
            assert r['status']=='finished' and r['winner']==other and not r['errors'] and r['phaseSpawnCount']==1
            assert len(r['spawnedUnits'])==1 and r['spawnedUnits'][0]['unit']=='敌人-CF6老头机器人'
            values.append(100*(1-r[other]['remainHp']/r[other]['startMaxHp']))
        stats.append({'rival':rival,'name':name,'level':level,'min':min(values),'mean':statistics.mean(values),
            'median':statistics.median(values),'max':max(values),'values':values,
            'minFrames':min(r['frames'] for r in subset),'maxFrames':max(r['frames'] for r in subset)})
    
assert all(r['mean']>=25 and r['median']>=25 and r['max']<=85 for r in stats),json.dumps(stats,ensure_ascii=False)
for row in js(TMP/('matrix-'+revision)/'input-identity.json')['sourceBindings']:
    assert sha(ROOT/row['path'])==row['sha256'],'Current input drift: '+row['path']
jput(TMP/('final-field-review-'+revision+'.json'),{'revision':revision,'games':36,'wins':0,'timeouts':0,'groups':stats,
    'minimumOpponentRemainingHpPercent':min(100-r['max'] for r in stats)})

section='''## 当前对战验证

当前候选的[完整证据包](evidence/20261017/summary.json)包含 30／60／99 级、双方换位、每侧三次，共 **36 场**；老头组合 **0 胜、36 场自然落败、0 超时**，每场恰好生成一次机器人后继。各组平均与中位净生命损失均达到上述工作判据，每场对手也保留至少 15% 生命；全部逐场结果保留。

| 对手 | 等级 | 净失血最低 | 平均 | 中位数 | 最高 | 战斗帧数 |
|---|---:|---:|---:|---:|---:|---:|
'''
for r in stats:
    section+=f"| {r['name']} | {r['level']} | {r['min']:.2f}% | {r['mean']:.2f}% | {r['median']:.2f}% | {r['max']:.2f}% | {r['minFrames']}–{r['maxFrames']} |\n"
section+='''
净生命损失按对手初始满血与结算余血计算，包含兽王吸血回补，不是累计造成伤害。低输出场次仍在表内；有限重复不证明任意随机局面下必然落败或达到某个伤害值。

两套隔离环境绑定相同的候选 runtime 身份／闭包及源码、SWF、数据。全部实验退出、运行资源、只读种子、非目标存档和全局 SharedObject 检查通过。公共击退修正后的大头／大刀证据保留原包；最终集成核对确认它们的单位数据节点未变，共享 CF6 XML 的其余差异仅属于老头两种形态。没有把旧整份数据文件冒充成当前文件。

复查入口：[逐场阶段诊断](evidence/20261017/field-diagnostics.json)、[源码与输入索引](evidence/20261017/frozen-inputs.zip.index.json)、[无损映射](evidence/20261017/lossless-mapping.json)、[完整性清单](evidence/20261017/integrity.json)。历史失败、旧矩阵、原始 trace、编译报告及恢复过程一并归档。

原生图像可查看[人形待机](evidence/20261017/native/images/human-stand-1.png)、[变形第 55 帧](evidence/20261017/native/images/phase-55.png)、[机器人光束](evidence/20261017/native/images/beam-29.png)；[图像来源](evidence/20261017/native/image-provenance.json)说明 R6 捕获与后续版本的图形等价证明，未将其写成当前候选重新截图。

本轮状态为 `candidate_executed`，包含专项自动行为、原生绘制和上述有限候选对战；外观、动作衔接、打击感与标准入口仍待人类验收。工作区保留待审，未提交、未推送，也未进行正式 runtime 发布。
'''
file=ROOT/'tools/cf6-elder-assets/README.md'
old=read(file).decode('utf8')
assert old.count('## 当前对战验证\n')==1
assert '配表为 '+revision.upper() in old or '当前候选为 '+revision.upper() in old,'Update the reviewed candidate and balance explanation before finalizing the result table'
put(TMP/('readme-before-final-'+revision+'.md'),read(file))
file.write_text(old.split('## 当前对战验证\n')[0]+section,encoding='utf8',newline='\n')
print(json.dumps({'revision':revision,'groups':stats,'readmeUpdated':True},ensure_ascii=False))
