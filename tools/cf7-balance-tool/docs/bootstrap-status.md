# Bootstrap Status

> 本文记录工具可运行状态和历史回归基线；`baseline-extracted.json` 不是武器公式权威。当前武器标定权威边界与已知 CLI 限制见 [`agent-balance-record-design.md`](agent-balance-record-design.md)。

## 当前状态

- `tools/cf7-balance-tool` 已完成 workspace 初始化、字段扫描、XML round-trip、批量 preview / batch-set 和 Electron 中文审阅台
- 已接通导出 payload、刷新 preview、输出镜像 XML、导入外部 preview / payload、输出路径配置、产物历史
- 当前原始 `data/` 不会被 renderer 直接改写，实际写出仍走 CLI 链路
- 首批武器审计已收敛为尚未上线的严格 balance v1：工具侧完整台账为决策真源，item XML 只保留数字 `workbookVersion` 和按 `data/data_*` 分开的 compact runtime profile；完整 SHA 由版本注册表与台账保存一次，旧平铺/v2/runtime SHA 草案硬失败且缺 profile 禁止回退
- `balance-sync` 复算 input/source digest 并对账台账与 runtime core；`balance-check` 继续校验 SHA、预算、规则 target、DPS 残差和已支持的精确获取证据
- 玩家投影只从完整通过的 confirmed profile 派生，不下发 note、WBR ID、工作簿 SHA、auditRef 或 evidence

## 本轮增量验证（2026-07-23，工作树）

- 首批长枪/手枪已同步 **37/37 profile、8/8 XML**：`confirmed=26`、`unresolved=11`、`invalid=0`，可显示 26，`balance-check` 为 0 failures / 22 warnings；warnings 均对应仍需人类解释的黄项
- 8 个 XML 的非 `<balance>` 内容迁移前后 SHA-256 全部一致；runtime balance 块由 **153,671 bytes** 降至 **26,203 bytes**，减少 **82.95%**；把重复 SHA 换成版本映射又比中间草案减少 **2,257 bytes / 7.93%**
- `npm run typecheck` 通过；`npm test` 为 **23 文件 / 708 用例**；round-trip **97/97**；`balance-sync --check` 为 **37/37、零差异**；`balance-check` 为 **37/37、ok=true**
- fresh TestLoader：`InventoryPanelServiceTest 131/131`、`KShopCheckoutServiceTest 20/20`、`NpcShopPanelServiceTest 46/46`，各自 Compiler Errors **0/0**；AS2 BOM gate **220/220**
- publish-only `scripts/asLoader.swf` 为 **1,033,191 bytes** / SHA-256 `A5AEF4B61B45FCB5AA7AAD293FA6AE364060117EAA28CAFE8A815FA78B95B409`，Compiler Errors **0/0**；行为结论以此前述 fresh TestLoader 为准
- Web 最小四字段投影回归：workbench primitives **9/9**、KShop presenters **19/19**、KShop harness **91/91**、NPC harness **86/86**、物品格视觉矩阵 **17/17**

## 已验证（2026-03-06 工具里程碑 v2；不是 weapon balance schema）

- `npm install`
- `npm run typecheck`
- `npm test` — 16 文件，666 用例全部通过
- `npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json`
- `npm run roundtrip-check -- --project ./project.json --output ./reports/roundtrip-report.json`
- `npm run batch-preview -- --project ./project.json --input ./reports/batch-updates.sample.json --output ./reports/batch-preview-report.json --output-dir ./reports/batch-output`
- `npm run batch-set -- --project ./project.json --input ./reports/batch-updates.sample.json --output ./reports/batch-set-report.json --output-dir ./reports/batch-output`
- `npm run calibrate -- --input ./baseline/baseline-extracted.json` — 462 项全部通过
- `npm run calc -- weapons --input /tmp/test-weapon.json`
- `npm run query -- weapons --input ./baseline/baseline-extracted.json --sort -averageDPS --limit 5`
- `npm run diff -- weapons --input ./baseline/baseline-extracted.json --input2 ./baseline/baseline-extracted.json`
- `npm run validate -- --input ./baseline/baseline-extracted.json`
- `npm run build --workspace @cf7-balance-tool/web`

## 当前能力

- `packages/core`：字段分类、共享类型、报告辅助逻辑、8 大公式引擎，以及严格 weapon balance v1 profile/台账/digest/规则目录/审计与玩家派生投影
- `packages/xml-io`：XML 扫描、文档对象、round-trip、batch preview / batch-set，以及武器 v1 profile/ledger/evidence 解析、有效数据展开与精确获取索引
- `packages/cli`：`project scan` / `project fields` / `project roundtrip-check` / `project batch-preview` / `project batch-set` / `xml get` / `xml set` / `calibrate` / `calc` / `query` / `diff` / `validate` / `balance-sync` / `balance-check`
- `packages/web`：Electron + React 中文默认界面，已有可审阅 diff 、可编辑暂存值、产物状态、历史报告、侧边栏文件导航、表格/卡片双视图、列排序、撤销/重做(Ctrl+Z/Y)

## 公式引擎

| 模块 | 校准测试 | 覆盖列 |
|------|----------|--------|
| 枪械 (weapons) | 288 项 | 25 列（DPS/周期伤害/加权等） |
| 防具 (armor) | 55 项 | 5 列（总分/法抗上限），含手套/项链变体 |
| 近战 (melee) | 2 项 | 1 列（推荐锋利度） |
| 爆炸 (explosives) | 1 项 | 1 列（推荐单发威力） |
| 伤害 (damage) | 156 项 | 物理6列 + 魔法2列 |
| 经济 (economy) | 12 项 | 装备定价/合成/副本收益 |
| 药剂 (potions) | 56 项 | 8 列（强度/数值/价格） |
| 怪物 (monsters) | 60 项 | 10 列（攻/防/HP/经验/金币） |

## 字段基线

- 扫描 XML：89
- 字段名：528
- 字段出现次数：36854
- 未分类字段：394
- round-trip 校验：89 / 89 通过

## 常用命令

```bash
npm install
npm run typecheck
npm test

# XML 操作
npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json
npm run roundtrip-check -- --project ./project.json --output ./reports/roundtrip-report.json
npm run batch-preview -- --project ./project.json --input ./reports/manual-updates.generated.json --output ./reports/batch-preview-report.json --output-dir ./reports/batch-output
npm run batch-set -- --project ./project.json --input ./reports/manual-updates.generated.json --output ./reports/batch-set-report.json --output-dir ./reports/batch-output

# 公式引擎
npm run calibrate -- --input ./baseline/baseline-extracted.json
npm run calc -- weapons --input /tmp/weapon-input.json
npm run query -- weapons --input ./baseline/baseline-extracted.json --sort -averageDPS --limit 10
npm run diff -- weapons --input ./baseline/baseline-extracted.json --input2 ./baseline/modified.json
npm run validate -- --input ./baseline/baseline-extracted.json

# v1 台账/runtime 对账与严格审计
npm run balance-sync -- --check
npm run balance-check

# GUI
npm run dev:web
npm run dev:electron
```

## 规则提醒

- `xmlPath` 重复节点索引是 0-based，例如 `root.item[0]`、`root.item[1]`
- 相对 `filePath` 先按输入 JSON 所在目录解析，找不到再回退到 `project.json` 所在目录
- `project batch-set --output-dir` 写出的是镜像目录树，不会覆盖原始 XML

## 主要报告

- `reports/field-usage-report.json`
- `reports/roundtrip-report.json`
- `reports/manual-updates.generated.json`
- `reports/batch-preview-report.json`
- `reports/batch-set-report.json`
- `reports/batch-output`
