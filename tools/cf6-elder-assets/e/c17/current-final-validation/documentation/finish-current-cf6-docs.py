"""Make the README current after acceptance, retaining its entire prior revision."""
from pathlib import Path
import importlib.util, json

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
elder = u.js(P / 'history/r22-full-awake/acceptance-summary.json')
head = u.js(P / 'history/head-c5-full-awake/strength-summary.json')
native = u.js(O / 'r22-final-native-assessment.json')
host = u.js(O / 'host-r22-final/assessment.json')
assert elder['strengthPassed'] and head['strengthPassed'] and head['wins'] == 18
assert native['ok'] and host['ok'] and not u.js(O / 'test-round-display-cleanup.json')['displayHoldActive']
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
readme = R / 'tools/cf6-elder-assets/README.md'
prior = readme.read_text('utf8')
package.copy(readme, 'current-final-validation/documentation/elder-README-before-closeout.md.txt')

def section(start, end):
    return prior[prior.index(start):prior.index(end)].strip()

beast = [g for g in elder['groups'] if g['rival'] == 78]
exusiai = [g for g in elder['groups'] if g['rival'] == 361]
assert len(beast) == len(exusiai) == 3
beast_rows = '\n'.join(f"| {g['level']} | {g['observedInitialFormRage']}／6 | {g['initialFormDefeated']}／6 | {g['losses']}／6 |" for g in beast)
exu_rows = '\n'.join(f"| {g['level']} | {g['netLoss']['mean']*100:.2f}% | {g['netLoss']['median']*100:.2f}% | {g['netLoss']['min']*100:.2f}%–{g['netLoss']['max']*100:.2f}% | {g['wins']}／{g['losses']} |" for g in exusiai)
win_count = sum(r['status'] == 'finished' and r['won'] for r in elder['rows'])
loss_count = sum(r['status'] == 'finished' and r['lost'] for r in elder['rows'])
assert win_count + loss_count == 36
intro = f'''# CF6 老头与老头机器人装配

本目录维护人形 R7、机器人 R7 和角色局部变形的确定性 XFL 装配。人形为阶段 8／档次系数 9，机器人为阶段 8／档次系数 20，默认先人形、再生成机器人。当前 R22 已完成维护者指定的 60–100 级强度矩阵；低等级不作为本轮通过条件。机器验证、玩家体验和正式 runtime 发布分别记录。

## 当前校准结果

60／80／100 级、两个对手、双方各三次共三十六场，实际 {win_count} 胜、{loss_count} 负，无平局或超时，且每场恰好完成一次老头人形到机器人的交接。兽王按维护者追加口径逐场确认一形态濒死狂暴或已打穿一形态，并最终自然落败；不再以兽王终场净削血作为通过门槛。EXUSIAI 每组六场的平均与中位全链净削血均须在 50%–80%；维护者已明确允许少量胜局，各组仍须以落败为主。原始零胜局计划、口径变更及原口径失败判定都保留。

| 兽王等级 | 实际观察到濒死狂暴 | 一形态被击败 | 老头自然落败 |
|---|---:|---:|---:|
{beast_rows}

| EXUSIAI 等级 | 平均净削血 | 中位净削血 | 逐场范围 | 老头胜／负 |
|---|---:|---:|---:|---:|
{exu_rows}

逐场结果及判定见[当前三十六场](evidence/20261017-calibration/history/r22-full-awake/acceptance-summary.json)。组内均值不代表每场都在区间内，有限重复也不保证所有随机局面。兽王自身濒死扣血与吸血会改变终场 HP，不能把其全部净削血归因于老头输出。

最终主线源码下重新完成四组真实 CS6 回归，共 {native['passed']:,} 项通过、零失败：老头行为及护盾、音频、玩家瞄准、十二个原生绘制点。十二张当前图像与 R21 对应图像逐像素相同；这次没有重新执行 805 点完整扫描。另有当前 C5 公共加载器下的大头完整十八场全胜，以及当前合并源码的九组 Host 定向测试 {host['passed']} 项通过。Host 早先全量测试的 120 项资源窗口前置失败仍保留，不用定向通过替代全量通过。

汇总入口：[本轮证据](evidence/20261017-calibration/summary.json)。实际对战使用冻结 C5 加载器与 R4 隔离 Host 候选；后来合入的 AI 终端源码只做源码回归，未借此发布新终端功能。测试期间临时保持唤醒已结束，真实存档、原始失败和编译记录均保留。本包在提交前封存，实际 commit／push 以 Git 历史为准；未进行正式 runtime 发布。玩家手感、物理音频、弱机性能和标准入口体验仍分别待验收。

## 当前护盾与射击规则

机器人起手射程为 750，人形为 500。普通束与重束沿既有枪口和光束轴延长到局部 600 像素，画面与真实碰撞同源。普通红束第 29 帧发射、完整动作 44 帧，起手间隔 80 帧；重束第 35／47／59／71 帧依次发出 ×0.5／×1／×1.5／×2 波伤害，完整动作 106 帧、冷却 600 帧。第 11 帧起锁定方向与纵深，后续段不追踪，走出射线后可避开剩余段。

重束由有效红束易伤，或本人真实砸地命中后的 180 个有效帧窗口授权。砸地窗口绑定同一目标实例，不施加易伤；MISS、换目标、同名换代、目标死亡、本人死亡或到期都会失去资格。起手时至少一条资格须剩余 72 帧；持续阶段两条资格都失效或动作取消便停止剩余段。砸地倍率为 ×18，普通束为 ×3；面板由同一工作簿公式重算，不直接叠加旧面板。

连打真实命中盾容量为当前满血 5%；强度率从 1 级的 30% 平滑到 99 级的 12%，时限从 120 帧到 60 帧，超界取端点。砸地真实命中硬盾容量为当前满血 0.75%、强度率 10 倍、时限 120 帧。光束起手盾容量为当前满血的 `0.2 × min(0.6, 1 / (1 + (等级 / 20)^2))`，公式内等级限制在 1–99；覆盖普通束／重束完整 44／106 帧动作，中断撤回。各层先将实际攻击力乘 `55/43` 再应用各自强度率；光束强度率为 75%，最高 800。各层只管理自己的身份，不删除其他来源护盾。

机械应激盾按累计损失初始满血的每 5% 强制补充，实际转换 30% 所失生命，本层容量上限为初始满血的 7.5%。每个有效帧另补当前缺失生命的 1/6400，上限为初始满血的 1/6400；三十帧最大预算为初始满血的 0.46875%，仅损血 20% 时为 0.09375%。新补充合并本层剩余容量后重设线性衰减，不重复缩放旧容量；没有继续补充时 36 帧耗尽，持续刷新时不保证第 36 帧消失。它不治疗实际 HP，也不撤销触发击已经结算的吸血。所有单位使用相同伤害管线，没有对手名称、兵种或玩家身份分支，也没有按目标设置伤害上限。
'''
core = section('## 真源与入口', '## R15 及更早的验证记录')
core = core.replace('尚未提交的三角色注册统一迁到', '原预留的三角色注册统一迁到')
diagnostics = section('每个形态结束时的 `CF6_ELDER_COMBAT_END`', '## 数值校准口径')
calibration = section('## 数值校准口径', '旧 R7 的完整 36 场与 R8 的 12 场小样均保留。')
calibration = calibration.replace('此前交付的 R15 已完成 36 场候选对战；本轮加入蓄力与条件重束后，动作观测和公式输入已重新生成，不能沿用其胜负统计。', '历史版本的对战仅证明其自身执行身份；当前结论由上述 R22 完整矩阵支持。')
history = '''## 历史证据

R1–R22 的候选试验、失败、平局、超时、未执行草案、恢复和历次口径变更集中保存在[校准汇总](evidence/20261017-calibration/summary.json)及其历史条目中；旧净削血分析保持原口径，当前兽王判定另存授权补充。详细施工前正文保存在[原文快照](evidence/20261017-calibration/current-final-validation/documentation/elder-README-before-closeout.md.txt)，不作为现役参数说明。

更早记录分别见 [R15 交付](evidence/20261017/summary.json)、[试玩反馈](evidence/20261017-playtest/summary.json)及[音效与机器人对战](../cf6-audio/evidence/20261017-combat-audio/summary.json)。旧图像、行为通过与候选对战各自绑定原始源码和资源身份，不冒充当前版本重新执行。此前封存的完整性清单逐项复核保留。
'''
readme.write_text(intro.strip() + '\n\n' + core + '\n\n' + diagnostics + '\n\n' + calibration + '\n\n' + history, 'utf8', newline='\n')
audio = R / 'tools/cf6-audio/README.md'
package.copy(audio, 'current-final-validation/documentation/audio-README-before-closeout.md.txt')
text = audio.read_text('utf8')
assert '由尚未提交的 470–472 迁至' in text
audio.write_text(text.replace('由尚未提交的 470–472 迁至', '由原预留的 470–472 迁至'), 'utf8', newline='\n')
package.copy(O / 'finish-current-cf6-docs.py', 'current-final-validation/documentation/finish-current-cf6-docs.py')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'ok': True, 'elderReadmeLines': len(readme.read_text('utf8').splitlines()), 'historyPreserved': True, 'sealed': False}))
