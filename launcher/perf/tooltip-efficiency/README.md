# Tooltip 排版效率评估

在仓库根目录运行，使用 `launcher/perf/node_modules` 已有的 Playwright 和本机 Microsoft Edge。PowerShell 先切换 UTF-8。

```powershell
chcp.com 65001 > $null
$out = '..\..\..\outputs\efficiency-baseline-339'
node launcher/perf/tooltip-efficiency/samples.js --dump-parity "$out\showcase-samples.json"
node launcher/perf/tooltip-efficiency/sweep.js --scope showcase --preset legacy339 --out "$out\showcase"
node launcher/perf/tooltip-efficiency/sweep.js --scope full --preset legacy339 --viewports '1024x576@1,1067x600@1.5,1280x720@1.25,1920x1080@1' --out "$out\full"
node launcher/perf/tooltip-efficiency/compare-sheets.js --presets legacy339 --viewports '1067x600@1.5' --out "$out\sheets"
```

候选 Web 代码提供预设 API 后，可用下列命令生成四联图。

```powershell
node launcher/perf/tooltip-efficiency/compare-sheets.js --presets 'legacy339,tier12,tier13,tier14' --viewports '1067x600@1.5,1280x720@1.25' --out "$out\candidate-sheets"
```

- `sweep.js` 默认 `--scope showcase --preset legacy339`，视口默认另含 `1366x768@1`，共五档。`--limit N` 取成功构建样本的前 N 项。输出 `summary.json`、`raw.json`、`report.md`。省略 `--out` 时写到泳道工程外部的默认目录，按范围及预设分目录。
- `compare-sheets.js` 默认请求四档和上述两个视口。加 `--only-presets-available` 可在缺少预设 API 的 #339 上跳过不可用档位。输出各预设原始裁图、横向 PNG、画廊 `index.html` 和标注数据 `sheets.json`。裁图保留约 12 CSS px 深色边距和生产滚动条。截图使用 Edge 的减弱动效设置，停在阅读起点。
- `samples.js` 按传入的游戏仓根目录编译物品目录，以 `itemInput` 和生产 `buildProjection` 生成文档，默认使用当前检出。全量每物品一份 1 级商品态投影，注入活动普通 NPC 商店、K 点商店与产出配方的来源记录。动态存档发现与斗兽索引未纳入。展示集包含两件零来源短弹药、四种已安装插件组合和指定长样本。插件用真实目录定义与兼容槽位，`calculated` 提供目录基础属性。来源条数不足时，展示集以“排版样例”占位记录补足，对应 `obtain[].source` 为 `null`。
- 每次扫测复用一个页面，通过 Chromium 设备模拟设置 CSS 视口与 DPR，并检查浏览器实际值。夹具使用生产 CSS、文档渲染器和定位器，以视口中心为点锚。每个视口准备图标目录与字体后批量测量。截图额外等待当前样本图片解码。
- 外框与栏位尺寸以 CSS px 计。单一阅读视口以生产 `debugState()` 为准，`overflowPx = max(0, contentH - viewH)`，溢出率按正差值计，可滚标记按生产判定。视口闭合使用生产 8 CSS px 内边距及 1 px 几何容差。P50/P95 用最近秩，宽高比理想区间为 `[0.8, 1.5)`，惩罚沿用 `TooltipWidthDiagnostic.as`。最重 Top 15 依次按溢出、外框高度、惩罚降序。
