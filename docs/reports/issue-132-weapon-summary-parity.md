# #132 武器摘要对照与获取校验

## 2026-11-21 结案验收

获取校验已修复。QJZ171 对应 Pig 商店第 53 号货位。提示目录只供展示，任务、成就和存档任务的奖励按游戏语法复核，金币商店、K 点商城与合成按加载清单核对。金币证据还须与货位上的物品名一致。

同一批 59 份物品 XML、612 个配置（含 44 个变体）中，严格校验放行数从 34 回到 35。真实 Flash 读取现役模块后，全部配置的可见性及四字段均与修复后的工具一致。Edge 中的库存、NPC 商店和 K 点商城卡片各显示 35 个摘要，另外 577 个均隐藏。新增 11 个回归用例，工具全套 939/939 通过。全库 `balance-check` 仍报告 8 个原已隐藏配置的 16 条数据错误。[逐项验收与现役模块指纹](../evidence/issue-132-weapon-summary-acceptance.json)

本卡以获取校验修复和现役摘要验收结案，原议题的生产瘦身按“不再计划”归档。游戏继续从作者 XML 生成摘要。武器精简 XML、小摘要的同代绑定、消费端迁移和旧索引释放均留待另行立项。

## 对照方法与复跑

离线探针起点为 `23ec828cd04c783c86abb016c1f080eb814d41ba`。

`weapon-summary-as2-model.ts` 按现役 `InventoryPanelService.buildBalanceSummary` 及其私有 helper 建立独立 TS 模型，FNV 使用 AS2 的移位加法；工具侧直接调用现役 parser、`validateWeaponBalanceRecord`、`derivePlayerWeaponBalanceProjection`。
另外输出 `balanceCheck` 列，保留现役 `balance-check` 的 evidence 和 use/dualWield 附加门，不用其更强规则替换 AS2 可见性。

模型对 AS2 的 workbook/字段白名单常量和完整摘要 helper 区段做规范换行 SHA-256 检查：
`2344e6ccba4014187045ce29a0a513d2b5b53129e3d002b7e335168b84fabf39`。
锚点缺失或区段改变即报错，必须重新审阅模型，不能静默沿用。
离线探针使用 JS 的数字和字符串转换、XMLParser 及对象枚举。上方结案验收另外使用了真实 AVM1。

在 `tools/cf7-balance-tool` 执行（Windows PowerShell 先 `chcp.com 65001`）：

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm exec -- tsc -b packages/core packages/xml-io packages/cli --force --pretty false
npm exec -- vitest run packages/xml-io/tests/weapon-summary-parity.test.ts
npm run weapon-summary-parity -- --repo ../.. --output ../../tmp/issue-132/weapon-summary-parity.json
npm run weapon-summary-parity -- --repo ../.. --output ../../tmp/issue-132/weapon-summary-parity.json --check
```

报告仅输出到 `tmp` 或仓外，包含每个输入的实际字节 SHA-256、HEAD、源文件/list ordinal/item ordinal/同文件同名 occurrence/profile key 和两层四字段结果。输入包含物品清单、台账、相关实现，以及 evidence 扫描的 `data/config/scripts` 文本边界与显式证据文件。`--check` 逐字节重算，HEAD 或输入改变后需重生成。大报告不进入 Git。

## 获取校验修复前的数据结果

Linux 源码候选的生成与 `--check` 均退出 0，仅证明报告可复现。没有 parser 错误，台账 orphan/重复 runtime join 均为 0；这不证明数据链通过。报告另外保留每条 validation 的 severity/code/path/message，防止“两个结果都为空”掩盖数据错误。完整逐 profile 明细见上述生成物。

| 范围 | 本轮数量 |
|---|---:|
| `list.xml` 的物品文件 | 59 |
| `type=武器` 源记录（不按名称去重） | 568 |
| 全部 `data/data_*` 行 | 612 |
| weapon 家族 profile | 373（35 confirmed、338 unresolved） |
| melee 家族 / 无 balance 的合法无武器摘要行 | 238 / 1 |
| 全部 `data_*` | 44（weapon 37、melee 7） |
| AS2 模型 / 工具投影可见 | 35 / 35 |
| 可见性或四字段差异 | 0 / 612 |
| 完整 evidence 附加门可见 / 残差 | 34 / 1 |
| 工具 validation 错误 profile / 错误条数 | 8 / 16 |

44 个变体逐个枚举：`data_fire` 19、`data_ice` 19，`data_2`、`data_3`、`data_4`、`data_fire_gold_stolen`、`data_ice_gold_stolen`、`data_pilebunker_m7` 各 1。未找到的 profile 不回退 `data`。源记录顺序和重名均保留；本探针不宣称复现 `ItemUtil` 的反序枚举、自动 ID、默认 modslot 或同名覆盖结果。

修复前的唯一残差来自 `data/items/武器_长枪_机枪.xml` 中的 `QJZ171/data`。AS2 模型与工具投影均为 `{state:"confirmed",weightLayers:1,formula:1,level:37}`。严格校验返回 `high_price_unreviewed_acquisition`，命中的唯一文件为展示用的 `data/tooltip/tooltip-catalog.json`。

原工具门仍为红灯：`balance-sync -- --check` 在 `AMML3/data: ledger record missing; base fallback is forbidden` 停止；`balance-check` 检查 373 个 weapon profile，返回 `ok=false`、17 条 failure（16 条 validation 加上上述 QJZ171 证据项）。这 16 条为：

| 当前数据问题 | profile / 条数 |
|---|---|
| `source_digest_mismatch` | 钛合金P90、061ABSR、HSR10S、NA45、AK47火麒麟，各 `data`，5 条 |
| `input_digest_mismatch` + `ledger_input_digest_mismatch` | 061ABSR、HSR10S，各 `data`，4 条 |
| `inline_ledger_field_mismatch` | HSR10S/data，4 个字段 |
| `audit_record_missing` | AMML3、HSR10、HSR10tac，各 `data`，3 条 |

这些 8 个 profile 都是 unresolved，AS2 当前先按状态隐藏，因此输出等价仍成立。缺 ledger 的 3 条本身已有 compact balance；与“1 条无 balance 的合法无摘要”`武器_刀_双刀.xml / 双匕首/data` 无关。orphan=0 只说明台账到运行副本方向没有孤儿；不能推导运行副本都能回接台账。本轮不生成缺失审计、不同步作者 XML 来消除基线红灯。

## 规则差异与反例

合成夹具覆盖确认/草案/合法无摘要、所有变体选择、重复容器/profile/台账、损坏结构、未知版本、digest 和同代错配、14 项数字输入及身份/机械输入变化。规则差异与上面的现役数据差异分别保留。

| 规则边界 | AS2 模型 | 现役工具 |
|---|---|---|
| 缺/未知 profile、未知 schema/workbook、重复 profile、过期 inputDigest | 省略 | 拒绝/省略 |
| balance 的单元素数组 | 可解包 | strict parser 拒绝数组 |
| workbookVersion 为 `"1"`、displayEligible 为 `1` | 省略 | parser 可归一化后显示 |
| profile 数字为十六进制字符串 | Number 可接受 | strict 十进制 parser 拒绝 |
| 容器额外 `#text` | 白名单拒绝 | parser 忽略 |
| 无台账、台账身份/字段/SHA 错配 | inputDigest 仍匹配时可显示 | 拒绝 |
| skill/lifecycle 等完整 source 变化，24 项 input 不变 | 仍可显示 | sourceDigest 拒绝 |
| 两个 digest 已更新但 DPS 不在确认带 | 可显示 | `dps_residual_out_of_band` 拒绝 |

反例不意味着当前作者 XML 存在这些结构，也不证明完整接受语言等价。新 TS 模型不会替代当前 AS2 或放宽工具验证。

## 生产接入和删除条件

当前最后读者仍是 Inventory、NPC 与 KShop 摘要出口；它们从 `ItemUtil` 独立 balance 索引读原容器。`ItemUtil.loadItemData` 虽已从常规物品对象删除 balance，仍保留 `balanceDataDict`，`getRawBalanceData` 仍供摘要出口使用。本阶段不删除任何树、字典、缓存或原始机制字段。

若重启武器瘦身，需确定新产物的可见性规则，并在真实 AS2 中验证全 profile、同代绑定和运行输入变化。全部摘要出口切换到同代小摘要、`getRawBalanceData` 可达读者归零并通过实际加载验证后，才具备评估释放旧索引的条件。武器有效 data/skill/lifecycle 的业务读者仍须逐项核对。[#131 非 weapon 家族候选验收](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/131)
