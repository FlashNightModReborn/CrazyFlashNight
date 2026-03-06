# Bootstrap Status

## 当前状态

- `tools/cf7-balance-tool` 已完成 workspace 初始化、字段扫描、XML round-trip、批量 preview / batch-set 和 Electron 中文审阅台
- 已接通导出 payload、刷新 preview、输出镜像 XML、导入外部 preview / payload、输出路径配置、产物历史
- 当前原始 `data/` 不会被 renderer 直接改写，实际写出仍走 CLI 链路

## 已验证（2026-03-06 v2）

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

- `packages/core`：字段分类、共享类型、报告辅助逻辑、8 大公式引擎（枪械/防具/近战/爆炸/伤害/经济/药剂/怪物）
- `packages/xml-io`：XML 扫描、文档对象、round-trip 校验、batch preview / batch-set
- `packages/cli`：`project scan` / `project fields` / `project roundtrip-check` / `project batch-preview` / `project batch-set` / `xml get` / `xml set` / `calibrate` / `calc` / `query` / `diff` / `validate`
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
