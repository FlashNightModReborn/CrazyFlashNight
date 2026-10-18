from evidence_utils import *

out=ROOT/'tools/cf6-headbot-assets/evidence/20261017-knockback'
package=Package(out)
report,rows,identities=package.collect('matrix','headbot-post-knockback-20261017',TMP/'headbot-post-knockback',True)
assert len(rows)==18
levels=[]
for level in [30,60,99]:
    subset=[r for r in rows if r['authorityContext']['level']==level]
    assert len(subset)==6
    for side in ['blue','red']:
        assert {r['repeatIndex'] for r in subset if r['authorityContext']['candidateSide']==side}=={1,2,3}
    assert all(r['status']=='finished' and r['winner']==r['authorityContext']['candidateSide'] for r in subset)
    percentages=[100*r[r['authorityContext']['candidateSide']]['remainHp']/r[r['authorityContext']['candidateSide']]['startMaxHp'] for r in subset]
    levels.append({'level':level,'games':6,'wins':6,'minRemainingHpPercent':min(percentages),
        'maxRemainingHpPercent':max(percentages),'minFrames':min(r['frames'] for r in subset),'maxFrames':max(r['frames'] for r in subset)})
inputs=js(TMP/'headbot-post-knockback/input-identity.json')
for row in inputs['sourceBindings']: assert sha(ROOT/row['path'])==row['sha256']

readme=ROOT/'tools/cf6-headbot-assets/README.md'
text=read(readme).decode('utf-8')
title='## 公共击退修正后的复验（2026-10-17）'
assert title not in text
text+='\n'+title+'\n\n'
text+='大刀联动检查发现公共被击移动回调使用了未限定归属的减速度，真实执行会令速度成为 NaN。修正为单位自身减速度后重新发布 asLoader，并用本单位相同的波属性素材完成三档等级、双阵营、每侧三次的 18 场复验。大头本身的 AI、矢量和面板未改。\n\n'
text+='| 等级 | 胜场 / 场数 | 机器人结算余血 |\n|---|---:|---:|\n'
for row in levels: text+='| %d | 6 / 6 | %.1f%%–%.1f%% |\n'%(row['level'],row['minRemainingHpPercent'],row['maxRemainingHpPercent'])
text+='\n全部自然结束，存档、只读种子、资源和进程清理检查通过；[新回执](evidence/20261017-knockback/summary.json)绑定修正后的 asLoader、实际候选身份及完整数据文件。此前 20261016-wave 的 18 场仍是旧 asLoader 下的历史结果，原包保留。本次未重新生成角色图形，也未进行正式 runtime 发布；有限斗兽结果不代替人类外观与操作验收。\n'
readme.write_text(text,encoding='utf-8',newline='\n')

with zipfile.ZipFile(lp(ROOT/'tools/cf6-headbot-assets/evidence/20261016-wave/frozen-inputs.zip')) as old:
    paths=set(old.namelist())
paths.update(r['path'] for r in inputs['sourceBindings'])
paths.update(['scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as','tools/cf6-bladebot-assets/build-knockback-fixture.py',
    'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6KnockbackScopeTest.as',
    'scripts/test-runners/cf6-knockback-scope/EnemyKnockbackFixture.as','scripts/test-runners/cf6-knockback-scope/TestLoader.as.template',
    'scripts/run-cf6-knockback-scope-tests.ps1'])
package.freeze(paths)
for pattern in ['headbot-post-w*','knockback-scope-fixed*','asLoader-knockback-publish*','enemy-knockback-change.json','production-class-audit-r6.json']:
    for p in TMP.glob(pattern):
        if p.is_file():package.copy(p,'raw/'+p.name)
jput(out/'summary.json',{'schema':'cf6-headbot.post-knockback.v1','completedAt':report['completedAt'],
    'evidenceState':'candidate_executed','positioningMatrixVerified':True,'formalRuntimePromoted':False,'standardEntryVerified':False,
    'sourceBindings':inputs['sourceBindings'],'sharedSourceSha256':sha(ROOT/'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as'),
    'scope':'Same headbot source and panel; revalidated after shared knockback deceleration scope repair.',
    'games':18,'wins':18,'timeouts':0,'levels':levels,'runtimeIdentities':identities,
    'priorEvidence':'../20261016-wave/summary.json','limits':'Finite 1v1 repeats; no human visual, player operation, performance, or formal runtime acceptance.'})
print(json.dumps({'levels':levels,**package.finish()},ensure_ascii=False))
