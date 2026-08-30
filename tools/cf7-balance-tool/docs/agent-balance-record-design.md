# 武器 `<balance>` v1 落盘、审计与展示契约

**文档角色**：武器平衡记录 schema、权威边界、profile 解析、机器门禁与玩家展示投影的 canonical doc。
**最后核对代码基线**：commit `ff5ea2e95a`；其上工作树已完成首批尚未上线的 weapon balance v1 收敛。

本文件回答“平衡结论怎样可复现地落盘、怎样按基础/进阶形态复算、怎样进入显示层”。具体业务判据与稳定条款 ID 查 [weapon-balance-rulebook.md](weapon-balance-rulebook.md)，本文件不复制条款正文。

## 0. 当前决定

- 公式、系数解释和价格规则的最高权威是 `0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx`。
- 当前权威映射：`workbookVersion=1` → SHA-256 `BAC3D341DB2B2BF966C3D473ED4793725BAF0B68BE01BA0D2804A76D6DCB840A`。
- 枪械验收目标是 **`averageDPS≈weightedDPS`**；`balanceDPS` 是中间量，不是本轮通过条件。
- 本功能尚未上线，之前的平铺结构和开发期 strict v2 草案均不是兼容对象。首次上线冻结前统一称 **weapon balance v1**；草案发生破坏性变化时直接迁移 v1，不制造虚假的 v2/v3 历史。
- 只接受 `formulaFamily=weapon + schemaVersion=1`。不存在旧结构读取、自动升级、缺 profile 回退或 `legacy` 状态。
- AS2 战斗逻辑不消费 balance。AS2 只从 compact runtime profile 生成最小玩家摘要；完整证据不进入游戏常驻物品树和 Web 消息。
- `tools/cf7-balance-tool` 是工作簿的派生实现和辅助门禁。若工具与当前工作簿冲突，以工作簿为准，并修工具，禁止反向调整判据迎合工具。

## 1. 两层记录模型

同一个审计结论分成两层，但只允许一处人工维护：

| 层 | 路径 | 角色 | 是否进入运行时 |
|---|---|---|---|
| 完整审计台账 | `tools/cf7-balance-tool/records/weapon-balance-audit.xml` | 完整 8 输入、状态、条款、证据、预算、备注和 source digest；人工复核真源 | 否 |
| compact runtime profile | 对应 `data/items/武器_*.xml` 的 item 根 `<balance>` | 8 输入、状态、显示门、input digest、审计引用 | 是，由工具从台账同步 |

工具必须复算 digest，并逐字段证明台账与 runtime profile 一致。禁止手工分别维护两份数值；`balance-sync --check` 发现差异即失败，写入由显式 `--write` 完成。

## 2. profile 身份与有效数据

### 2.1 静态形态

- 基础形态固定为 `profileKey=data`。
- 每个真实存在的 `data_2/data_3/data_4/data_ice/data_fire/...` 都是独立静态 profile。
- 有 `<balance>` 的 item 必须覆盖其全部现有静态 profile；缺任意 profile 时工具失败，AS2 隐藏摘要，绝不回退到 `data`。
- v1 不提供 `inherits`。即使某个变体看似纯视觉，也要么有独立记录，要么先由工具/人类证明并明确生成同值 profile；不能靠隐式继承绕过审计。

### 2.2 有效数据展开

工具与 AS2 必须模拟 `TierSystem`：

1. `data` 是基础数据。
2. `data_*` 的普通字段浅覆盖基础 `data`。
3. `skill/lifecycle/icon/displayname/description` 等顶层特例按现役 TierSystem 规则替换；其中 skill/lifecycle 纳入工具侧机械源摘要。
4. profile 审计发生在强化、配件、角色技能和临时状态之前。

普通强化 Lv1–Lv13 是实例级统一倍率，不产生 13 套静态 profile。未来的实例 DPS 展示应由静态 profile 与实例倍率即时派生。

## 3. compact runtime schema

`<balance>` 放在 `<item>` 根下，与 `<data>`、`<data_*>` 同级；禁止放入 `data_*`，否则会污染战斗数据域。

```xml
<balance>
  <formulaFamily>weapon</formulaFamily>
  <schemaVersion>1</schemaVersion>
  <workbookVersion>1</workbookVersion>
  <profiles>
    <data>
      <dualWield>1</dualWield>
      <pierce>1</pierce>
      <damageType>1</damageType>
      <shotgun>1</shotgun>
      <magPrice>200</magPrice>
      <weightLayers>0</weightLayers>
      <category>1</category>
      <formula>1</formula>
      <status>confirmed</status>
      <displayEligible>true</displayEligible>
      <inputDigest>fnv1a32:00000000</inputDigest>
      <auditRef>weapon:示例武器:data</auditRef>
    </data>
    <data_ice>
      <!-- 独立完整记录；不得只写与 data 的差值 -->
    </data_ice>
  </profiles>
</balance>
```

`schemaVersion` 只描述 XML 结构，`workbookVersion` 只描述公式权威版本。runtime 不重复保存 64 位 SHA；工具代码、规则表和完整审计台账共同维护精确的“版本 → SHA”映射，未知版本或映射不一致必须失败。当前尚未上线的 SHA 草案不提供兼容读取。

`profiles` 使用 profile key 作为子标签，避免重复 `<profile>` 的数组歧义，也让 AS2 可按键 O(1) 选择。每个 profile 必须完整保存八个公式输入：

| 字段 | 含义 | 主要条款域 |
|---|---|---|
| `dualWield` | 双枪/枪位系数 | `WBR-DUAL-*` |
| `pierce` | 穿刺能力系数 | `WBR-PIERCE-*` |
| `damageType` | 伤害类型系数 | `WBR-DMG-*` |
| `shotgun` | 多弹丸/多段预算值 | `WBR-SHOT-*` |
| `magPrice` | 公式使用的弹药价格 | `WBR-AMMO-*` |
| `weightLayers` | 同等级枪械额外强度预算层 | `WBR-WL-*` |
| `category` | 定价种类系数 | `WBR-CAT-*` |
| `formula` | 工作簿公式版本，当前为 1 | `WBR-AUTH-*` |

`status` 只允许 `confirmed | unresolved | invalid`。只有全部门禁通过的 `confirmed + displayEligible=true` 可投影；另外两种状态必须为 false。

## 4. 完整审计台账

```xml
<weaponBalanceAudit>
  <formulaFamily>weapon</formulaFamily>
  <schemaVersion>1</schemaVersion>
  <workbookVersion>1</workbookVersion>
  <workbookSha256>BAC3D341DB2B2BF966C3D473ED4793725BAF0B68BE01BA0D2804A76D6DCB840A</workbookSha256>
  <records>
    <record>
      <auditRef>weapon:示例武器:data</auditRef>
      <itemName>示例武器</itemName>
      <profileKey>data</profileKey>
      <dualWield>1</dualWield>
      <pierce>1</pierce>
      <damageType>1</damageType>
      <shotgun>1</shotgun>
      <magPrice>200</magPrice>
      <weightLayers>0</weightLayers>
      <category>1</category>
      <formula>1</formula>
      <status>confirmed</status>
      <displayEligible>true</displayEligible>
      <inputDigest>fnv1a32:00000000</inputDigest>
      <sourceDigest>sha256:0000000000000000000000000000000000000000000000000000000000000000</sourceDigest>
      <budgetBreakdown>
        <entry><code>acquisition.gold-standard</code><delta>0</delta><ruleRef>WBR-WL-003</ruleRef><evidenceRef>data/shops/npcs/example.json#catalog</evidenceRef></entry>
      </budgetBreakdown>
      <ruleRefs>
        <ref><id>WBR-DUAL-001</id><target>input.dualWield</target><evidenceRef>data/items/武器_示例.xml#item=示例武器/use</evidenceRef></ref>
      </ruleRefs>
      <!-- 普通 confirmed 可省略 note；黄/红必须写不可派生的短说明 -->
    </record>
  </records>
</weaponBalanceAudit>
```

### 4.1 台账闭合规则

- `auditRef` 全局唯一，并与 `itemName + profileKey` 一一对应。
- 台账与 runtime 的 8 输入、状态、显示门和 input digest 必须完全相同。
- `budgetBreakdown.entry.delta` 之和严格等于 `weightLayers`；零层也要有可复核的零贡献依据。
- `confirmed` 必须让八个 `input.*` target 都有合法条款和真实证据；获取证据还要通过现役商店/合成等专项索引。
- `unresolved/invalid` 必须 `displayEligible=false` 并提供非空 `note`；`confirmed` 的普通说明由结构化记录生成，`note` 可省。
- v1 不再存在 `rationale` 字段。DPS、残差、条款列表、SHA 和路径均可机械生成，不在每个 item 中复述。

## 5. 两种 digest

### 5.1 `inputDigest`：工具与 AS2 共验

固定字段顺序：

```text
itemName, profileKey, workbookVersion, use, bullet, clipname, split, damagetype, magictype,
singleshoot, level, power, interval, capacity, weight, impact,
dualWield, pierce, damageType, shotgun, magPrice, weightLayers, category, formula
```

规范化规则：

1. `itemName/profileKey/use/bullet/clipname/split/damagetype/magictype/singleshoot` 按字符串处理；缺失为 `""`，其他值用 `String(value)`。
2. `workbookVersion` 与后十四项必须是有限数字，用 JavaScript `String(Number(value))`。
3. 每项编码为 `key#<UTF-16 code unit 长度>=<规范值>`。
4. 完整规范串为 `weapon-v1|<项1>|...|<项24>`。
5. 对规范串按 UTF-16 code unit 执行 32 位 FNV-1a，存为 `fnv1a32:<8位小写十六进制>`。

它同时绑定物品身份、profile、工作簿版本、弹种/弹药/射击语义、六个运行数值与八个公式输入。任一项漂移，AS2 都停止投影，直到重新审计同步。

工具与 AS2 共用的当前冻结测试向量为 `fnv1a32:4bbce563`；任何一侧变更字段顺序、数值规范化或 UTF-16 处理而未同步另一侧，测试必须失败。

### 5.2 `sourceDigest`：工具侧完整机械源

工具按稳定键序列化并计算 SHA-256，至少覆盖：

- `itemName/profileKey/use`；
- 展开后的完整 effective data；
- 该 profile 生效的 skill/lifecycle。

结果存为 `sha256:<64位小写十六进制>`，只存在审计台账。它补足 AS2 固定字段摘要无法覆盖的复杂脚本/生命周期漂移；`balance-check` 必须复算一致。

两种 digest 都是防漂移门，不替代来源证据或 Git 审计。

## 6. 可复现施工流程

1. 冻结 `workbookVersion → SHA` 映射、sheet/cell 和公式版本。
2. 展开基础 data 与全部 `data_*`，检查 bullet、弹药、lifecycle、skill/subweapon 和完整玩家获取路径。
3. 先按规则表建立 `ruleRefs` 与 `budgetBreakdown`，再填 8 输入；不得为追平 DPS 反推系数。
4. 独立复算 `averageDPS`、`weightedDPS` 和带符号残差。超过 ±5% 先转 `unresolved`，不自动判红。
5. 在审计台账写完整记录；普通绿记录不写重复说明，黄/红只写不可派生的短 note。
6. 运行 `balance-sync --check` 查看差异，显式 `balance-sync --write` 生成/更新 compact runtime profile。
7. 运行 `balance-check` 反向读取所有物品，检查 profile 完整性、两种 digest、台账闭合、条款证据与公式残差。
8. 涉及 AS2/Web 时执行定向测试；没有新鲜 Flash trace 时只能报告静态/工具验证，不能声称已编译通过。

本流程不顺手修改 `power/price/interval` 等战斗值。数值整改必须是另一个有明确授权、可独立复核的任务。

## 7. 玩家显示边界

ItemDataLoader 加载后，ItemUtil 把 compact balance 提取到独立只读缓存，并从一般物品数据树删除，避免 `getItemData()` 深拷贝审计结构。库存按 `item.value.tier → EquipmentConfigManager.getTierKey()` 选择 profile；商店固定选择 `data`。

AS2 复核 v1 容器、已知工作簿版本、profile 状态、显示门、auditRef 和 input digest 后，只发送：

```js
balanceSummary = {
  state: "confirmed",
  weightLayers: 1,
  formula: 1,
  level: 30
}
```

- 多义节点、未知 tier、缺 profile、过期 digest、黄/红状态均省略整个属性。
- Web 不读取审计台账，不从 price/rarity 推断强度，也不显示 WBR ID、路径、SHA 或 note。
- 当前最高优先级是物品格 `◆层数`；Tooltip 只加简短“同级加权”。DPS 与玩家语言短标签待全量标定和信息层级冻结后再启用。
- 内部条款可以生成受控解释文案，但常态 UI 不直接展示条款编号或自由证据文本，避免信息过载。

## 8. 验证矩阵

在 `tools/cf7-balance-tool` 下运行：

```powershell
npm run typecheck
npm test
npm run roundtrip-check
npm run balance-sync -- --check
npm run balance-check
```

仓库根另运行：

```powershell
node tools/validate-doc-governance.js
git diff --check
```

| 检查 | 证明范围 |
|---|---|
| strict v1 parser | v2/平铺结构、缺字段、多义 profile 不会被兼容 |
| profile resolver | 基础 + 变体覆盖与 TierSystem 一致；缺 profile fail closed |
| digest vectors | TS 与 AS2 对同一 24 项得到相同 input digest；工具复核完整 source digest |
| `balance-sync` | runtime core 可由台账机械生成且无手工双源漂移 |
| `balance-check` | schema、profile 完整性、台账 join、SHA、digest、预算、条款证据和 DPS 绿色带 |
| AS2 定向测试 | base/tier 选择、缓存剥离、错误输入隐藏和最小消息边界 |
| Web/harness | 徽标、Tooltip、紧凑态、ARIA 与敏感审计字段隔离 |

`balance-check` 只要求已经存在 `<balance>` 的 item 覆盖自身全部 profile；不会强迫本轮范围外的所有武器立刻补记录。首次上线前仍须另行定义全量覆盖门。

## 9. 相关入口

- 业务判据：[weapon-balance-rulebook.md](weapon-balance-rulebook.md)
- 通用 XML 约束：[agentsDoc/data-schemas.md](../../../agentsDoc/data-schemas.md)
- 验证矩阵：[agentsDoc/testing-guide.md](../../../agentsDoc/testing-guide.md)
- AS2 → Web 护栏：[agentsDoc/as2-web-panel-migration.md](../../../agentsDoc/as2-web-panel-migration.md)
- 公式实现：`packages/core/src/formulas/weapons.ts`

## 10. 药剂公式族的并行投影

药剂/食品不复用 weapon v1 profile，也不进入武器 `balanceSummary`。其人工方案、机械审计与 item 根旁路同样遵循“只维护一个人工源、其余机械生成”的原则，但使用独立入口：

| 层 | 药剂入口 |
|---|---|
| 业务规则 | `docs/potion-balance-rulebook.md` |
| 人工方案 | `records/potion-balance-plan.xml` |
| 机械审计 | `records/potion-balance-audit.xml` |
| 公式 | `packages/core/src/formulas/potions.ts::computePotionV2Row()` |
| 同步 / 反查 | `npm run potion-balance-sync` / `npm run potion-balance-check` |

同步器必须从实际物品 `<effects>` 派生即时恢复、缓释恢复、Buff、净化和专用韧性输入；不得在计划表再抄一套战斗数值。item 根 `<balance>` 只保存来源等级、域、状态、价格/配额结果、digest 与审计引用，加载后仍由 `ItemUtil` 从一般物品树剥离。

药剂 v2 尚未登记进公式权威工作簿，因此当前全链统一标记 `authorityStatus=workbook-registration-pending`。同步和静态检查通过只证明三份投影一致，不能代替工作簿登记或 Flash 实机验收；`runtime-test-pending` 也不能由公式门自动提升。
