# 数值平衡覆盖契约

**文档角色**：全装备与药剂 balance 标定覆盖的常驻契约——目标态、新增物品 Definition of Done、存量迁移与覆盖门演进的唯一真源。
**建立**：2026-09-19，维护者批示「期望所有的装备药剂都需要完成平衡标定」。跟踪卡：issue #102（Epic #23 常驻）。
**上位权威**：公式与系数解释仍以 `0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx` 为最高权威；各家族记录模型见 [agent-balance-record-design.md](agent-balance-record-design.md)，业务判据见各 rulebook。

## 1. 目标态

所有装备（枪械、近战、爆炸类、防具含颈部）与药剂/食品物品：

- 携带本人族 item 根 `<balance>` 标签，字段、digest 与审计引用满足该家族 schema；
- 人工唯一真源在各家族 plan/台账，标签与 audit 由 sync 机械派生，禁止手工双源维护；
- `status=confirmed` 且满足该家族展示门才可视为完成；`unresolved/invalid` 必须带不可派生的短 note，且不投影；
- 各家族 `*-balance-check` 常绿，数值、价格、获取证据或公式输入任一漂移即红，提示重新审计。

标签与 digest 是自说明与防漂移门，不替代来源证据、Git 审计或实战验收；运行时不消费的家族标签（当前 armor/potion）不因此降低标定要求。

## 2. 新增物品 Definition of Done

新增或实改数值的装备/药剂物品，同批必须完成：

1. 在对应家族 plan/台账登记人工记录（层数分解、价格确认、证据引用）；
2. sync 落盘标签与 audit，对应家族 check 转绿；
3. 规则书无法解释的取舍记 `unresolved` + note 并落卡，不得调系数伪造 confirmed。

不允许先上数值后补标定；不允许为绕开覆盖门删除物品或排除文件。

## 3. 家族现状与覆盖门演进（2026-09-19 基线）

| 家族 | 人工源 | 门 | 覆盖现状 | 覆盖门状态 |
|---|---|---|---|---|
| weapon v1 | `records/weapon-balance-audit.xml` | `balance-check` | 40 条记录 | 仅校验已有记录；**全量覆盖门待开启**（本契约收口 design §8 的 deferred 项） |
| armor v1 | `records/armor-balance-plan.xml` | `armor-balance-check` | 钛合金61式五件 confirmed | 按 plan 登记项校验，不强制整文件 |
| potion v2 | `records/potion-balance-plan.xml` | `potion-balance-check` | 三文件 77 项；缺口 issue #101 | 已有整文件 coverage 门（家族先例） |
| melee / explosives | — | — | 公式引擎在（`formulas/melee.ts`、`explosives.ts`），家族未注册 | 先注册家族再谈覆盖 |

覆盖门演进顺序（每步落卡、机器门验收）：

1. potion 缺口清零（#101），确认既有 coverage 门常绿；
2. melee、explosives 家族注册（仿 armor 的 potion 式轻量路径）；
3. armor 按部件/等级带分批补录，随后开启整文件 coverage 门；
4. weapon 定义并开启全量覆盖门（design §8 预留），存量分批迁移；
5. 全部家族覆盖门常绿后，本契约进入维持态：check 红即腐败，按治理流程处理。

## 4. 批次跟踪

覆盖批次以 issue #102 checklist 为准，仓内文档状态更新是每批完工动作的一部分。卡片字段：Domain=数值标定，验收方式=机器门；含真人实战标定的批次单独落需人类验收的卡，不与机器门覆盖混签。
