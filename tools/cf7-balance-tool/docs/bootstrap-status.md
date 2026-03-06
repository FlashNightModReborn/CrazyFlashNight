# Bootstrap Status

## 当前状态

- `tools/cf7-balance-tool` 已完成 workspace 初始化、字段扫描、XML round-trip、批量 preview / batch-set 和 Electron 中文审阅台
- 已接通导出 payload、刷新 preview、输出镜像 XML、导入外部 preview / payload、输出路径配置、产物历史
- 当前原始 `data/` 不会被 renderer 直接改写，实际写出仍走 CLI 链路

## 已验证（2026-03-06）

- `npm install`
- `npm run typecheck`
- `npm test`
- `npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json`
- `npm run roundtrip-check -- --project ./project.json --output ./reports/roundtrip-report.json`
- `npm run batch-preview -- --project ./project.json --input ./reports/batch-updates.sample.json --output ./reports/batch-preview-report.json --output-dir ./reports/batch-output`
- `npm run batch-set -- --project ./project.json --input ./reports/batch-updates.sample.json --output ./reports/batch-set-report.json --output-dir ./reports/batch-output`
- `npm run build --workspace @cf7-balance-tool/web`
- 测试：7 个文件，29 个用例全部通过

## 当前能力

- `packages/core`：字段分类、共享类型、报告辅助逻辑
- `packages/xml-io`：XML 扫描、文档对象、round-trip 校验、batch preview / batch-set
- `packages/cli`：`project scan` / `project fields` / `project roundtrip-check` / `project batch-preview` / `project batch-set` / `xml get` / `xml set`
- `packages/web`：Electron + React 中文默认界面，已有可审阅 diff 、可编辑暂存值、产物状态、历史报告

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
npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json
npm run roundtrip-check -- --project ./project.json --output ./reports/roundtrip-report.json
npm run batch-preview -- --project ./project.json --input ./reports/manual-updates.generated.json --output ./reports/batch-preview-report.json --output-dir ./reports/batch-output
npm run batch-set -- --project ./project.json --input ./reports/manual-updates.generated.json --output ./reports/batch-set-report.json --output-dir ./reports/batch-output
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
