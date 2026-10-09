# 爆炸类（手雷/投掷爆炸物）平衡规则表

> **权威工作簿**：`0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx`（「爆炸类」页）
>
> **文档角色**：爆炸类 `<balance>` 标定的业务判据入口；与近战同构的轻量路径，本表只记爆炸特定判据。

## 1. 权威与落盘

| 层 | 爆炸类入口 |
|---|---|
| 人工方案（唯一人工真源） | `records/explosives-balance-plan.xml` |
| 机械审计（派生） | `records/explosives-balance-audit.xml` |
| 运行时旁路摘要（派生） | 各爆炸物 item 根下的 `<balance>` |
| 公式实现 | `packages/core/src/formulas/explosives.ts::computeExplosivesRow()` |
| 同步 / 反查 | `npm run explosives-balance-sync` / `npm run explosives-balance-check` |

## 2. 记录字段与公式映射

- `data.level` → `level`、`item.price` → `magPrice`（投掷消耗品单件即"弹夹"）、`data.capacity` → `magSize`、`data.power` → 威力实测值。
- 记录侧：`weightLayers`（加权层级）、`balanceMode`（`formula`/`exception`）、`adoptedGoldPrice`（声明后才启用价格带）、`expectedKPointPrice`/`kpointEvidenceRef`（成对出现）。

## 3. 判据（EBR 前缀）

| 条款 ID | 判据 | 口径来源 |
|---|---|---|
| `EBR-POWER-001` | 威力拟合带 `\|power/recommendedPower − 1\| ≤ 0.05` 为硬门 | ABR-SCORE-001 同口径 |
| `EBR-PRICE-001` | 价格带 `[0.8, 1.25]` 只对声明 `adoptedGoldPrice` 的记录启用——投掷消耗品按一次性成本定价，不套用武器价格公式；武器型爆炸物登记时应声明 | ABR-PRICE-004 放宽版 |
| `EBR-CLASS-001` | `消耗品_手雷.xml` 中 bullet 产生实体投影的物品按 `exceptionCode="summon-projection"` 分流；不走爆炸公式 | 物品 bullet 字段 |
| `EBR-CLASS-002` | 玩笑投掷物 `novelty-throwable`、非爆炸投掷体 `non-explosive-projectile`、空袭信标 `airstrike-beacon` 同样按 exception 分流 | 物品 bullet/impact 字段 |
| `EBR-TRIAGE-001` | 存量偏离公式的真实爆炸物挂 `exceptionCode="legacy-off-formula"` + `unresolved`，保留公式输出作诊断，待人工裁定改数值还是改层数口径 | ABR-TRIAGE-002 同口径 |

## 4. 覆盖现状

- `消耗品_手雷.xml`（39 项）已开启整文件覆盖门：formula 1 项（BBPLAYER手雷）、exception 38 项分流如上。
- `武器_长枪_发射器.xml` 等武器型爆炸物尚未登记，后续按武器通道评估是否并入本家族。
