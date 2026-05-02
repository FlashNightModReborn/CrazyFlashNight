# 选关界面 XFL 说明

本目录是选关界面 WebView 迁移的历史真相源。

## 真相源边界

- `选关界面.xfl` / `DOMDocument.xml`：Flash CS6 工程入口。
- `LIBRARY/选关界面UI/选关界面 1024&#042576.xml`：Stage Select manifest 的布局真相源，包含 16 个 frame label、背景层、按钮实例和页内导航脚本。
- `LIBRARY/选关界面UI/选关按钮.xml`：共享选关按钮行为参考，包含锁定、任务提示、挑战模式、预览图加载、四难度按钮等 AS2 逻辑。
- `flashswf/images/关卡预览图/`：外部关卡预览图来源。原版加载失败后会回落到 `LIBRARY/选关界面UI/Symbol 3274.xml` 的内部命名帧，再失败才停在默认预览帧；Web Stage Select 按同一顺序导入。

## Web 迁移产物

- `launcher/web/modules/stage-select-data.js`：由工具生成的 Web runtime manifest。
- `launcher/web/modules/stage-select-panel.js`：Stage 2 Step 1 测试入口 live-enter panel。
- `launcher/web/assets/stage-select/`：Web 运行时背景与预览图派生资产。
- `tools/export-stage-select-manifest.js`：XFL/XML 到 manifest / assets / data module 的导出工具。
- `tools/audit-stage-select-layout.js`：Stage Select 静态布局审计工具。
- `tools/audit-diplomacy-stage-select-links.js`：外交地图 SWF 旧 `关卡地图` 返回门与 Web 选关回流审计工具。
- `tools/run-stage-select-visual-audit.ps1`：FFDec 原帧与 Web 舞台截图的视觉对照工具，输出 `tmp/stage-select-visual-audit/sheets/*-compare.png`。

## 注意事项

- 不要手动编辑 SWF。
- Stage 2 runtime 的 AS2 bridge 服务 Web 选关真实交互：普通 `选关按钮` 走难度进关，`配置关卡属性("外交-*")` / `Type=外交地图` 入口按 `shape/外交地图点.xml` 的 `#009900` 绿色点直达原 Flash 淡出跳转，旧外交地图 SWF 内返回 `关卡地图` 的门由公共 AS2 门函数转入 Web 选关，`地图-*` frameLabel 会反查回选关页签，页内跳转只记录 Web 当前选关页；原版 return nav 通过独立 `returnFrameLabel` + `stageSelectReturnFrame` 淡出回 `_root.关卡地图帧值` 对应基地帧，同场景返回只关闭 Web panel，`NPC任务_任务_关卡路径` 魔神入口按 `选关界面UI/Symbol 3325` 放置 `Symbol 3323` 的 `image/bitmap3321.png` 法阵底图，文字按钮按 `选关界面UI/魔神选关.xml` 的 90.6×21px 红色渐变矢量复刻并打开原 `委托任务界面`；不手动编辑 SWF。
- 外交地图直达入口不能使用统一偏移：导出器会读取每个 `配置关卡属性("外交-*")` 符号内部的 `shape/外交地图点` 与 `DOMDynamicText` 矩阵生成 `directLayout`。`外交地图-第一防线防区.xml` 的点和文字相对坐标不同于通用外交点，必须以源符号 XML 为准。
- 0 帧内容归入第一个 label `基地门口`；这是原 XFL 中 label 从 1 帧开始但内容从 0 帧开始导致的兼容规则。
- 部分背景来自 SWF 内嵌 bitmap/shape。导出器优先使用 Adobe Animate 2024 / Flash CS6 自带 JRE 运行 `tools/ffdec/ffdec.jar`，并将派生图写入 `launcher/web/assets/stage-select/backgrounds/`。
- 关卡 hover 预览分三类：外部 PNG、`Symbol 3274` 内部命名帧、默认预览帧。大部分内部预览可直接从 XFL `bin/M *.dat` 复制 JPEG；少量 lossless 图由导出器用 FFDec 补出。审计口径中 `previewMissing` 应为 0，`previewFallbacks` 表示内部/默认回退数量。
- FFDec CLI 的 `frame` 只能导出 SWF 主时间轴首帧；选关界面 143 个页面帧位于 `DefineSprite 330`。视觉审计使用 FFDec 导出的 sprite PNG，再按 SVG 中的舞台原点 `translate(526.6, 206.95)` 裁切 1024×576。除首帧外，审计用 `ffdecFrameIndex = sourceFrameIndex + 1` 和 Web manifest 对齐。
