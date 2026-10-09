# 近战（刀类）平衡规则表

> **权威工作簿**：`0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx`（「刀」页）
>
> **文档角色**：近战 `<balance>` 标定的业务判据入口；数值模型与条款沿用防具/武器同口径，本表只记近战特定判据。

## 1. 权威与落盘

| 层 | 近战入口 |
|---|---|
| 人工方案（唯一人工真源） | `records/melee-balance-plan.xml` |
| 机械审计（派生） | `records/melee-balance-audit.xml` |
| 运行时旁路摘要（派生） | 各近战 item 根下的 `<balance>` |
| 公式实现 | `packages/core/src/formulas/melee.ts::computeMeleeRow()` |
| 同步 / 反查 | `npm run melee-balance-sync` / `npm run melee-balance-check` |

`melee-balance-sync` 从 plan 与物品 XML 实读数值重算审计账本和内联 `<balance>`；`melee-balance-check` 校验工作簿快照、锋利度拟合带、价格带、digest 与投影一致性。

家族按文件名分治，只允许登记 `data/items/武器_刀_*.xml`。覆盖门按文件逐开：`coverageFiles` 内列出的文件要求全量登记，未覆盖文件不拦截。

## 2. 记录字段与公式映射

- `data.level` → `level`（限制等级）、`data.weight` → `weight`（重量）、`data.power` → 锋利度实测值。
- 记录侧：`weightLayers`（M 层加权）、`damageTypeFactor`（伤害类型系数）、`categoryFactor`（种类系数）、`adoptedGoldPrice`（确认金币价，缺省取市场价）、`expectedKPointPrice`/`kpointEvidenceRef`（成对出现）。

## 3. 判据（MBR 前缀）

| 条款 ID | 判据 | 口径来源 |
|---|---|---|
| `MBR-SHARP-001` | 锋利度拟合带 `\|power/recommendedSharpness − 1\| ≤ 0.05` 为硬门 | 对应 ABR-SCORE-001 的分数拟合带 |
| `MBR-PRICE-001` | `adoptedGoldPrice/recommendedGoldPrice ∈ [0.8, 1.25]`；确认价偏离须在 note 记录取整基准 | ABR-PRICE-004 同口径 |
| `MBR-KP-001` | K 点实售对公式值偏差 ≤ 5%，且必须有商店 JSON 证据 | ABR-PRICE-004 同口径 |
| `MBR-LAYER-001` | `weightLayers` 为加权层数：金币购买 0、K 点购买 +1、高价 +1、合成 +1、Boss/高难掉落 +1~2、40 级以上浮动 +1、免费赠送可为负；层数须有获取渠道证据，公式反推层数只能落 `unresolved` | ABR-LAYER-001~006 同口径 |
| `MBR-TRIAGE-001` | `confirmed` 要求每层有可复查证据且全部硬门通过；`unresolved` 允许公式反推层数但 note 必须写明缺口；`invalid` 不落盘 | ABR-TRIAGE-001~003 同口径 |
| `MBR-SCOPE-001` | 不可获取/NPC 专用/彩蛋错位物品按 `balanceMode="exception"` 登记并给 `exceptionCode` | potion `exceptionCode` 同口径 |

## 4. 现状

- 存量 231 件（16 个文件）经机械扫描大面积偏离 v1 公式基线（锋利度与价格双带同时满足的仅 1 件），分批迁移须逐件取得获取渠道证据后由 `unresolved` 推进。
- 首批登记：`巨尸长斧`（`武器_刀_狂野.xml`，机械拟合通过，层数为公式反推，待裁定）。
