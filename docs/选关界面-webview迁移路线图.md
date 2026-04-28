# 选关界面 WebView 迁移路线图

**文档角色**：`flashswf/UI/选关界面` 到 Launcher WebView panel 的 canonical migration doc。  
**当前阶段**：Stage 1 静态高保真复刻。

## 1. 阶段边界

Stage 1 只迁移表现层与开发闭环：

- 新增独立 panel id：`stage-select`
- 通过刘海屏“其他 → 选关测试”打开
- 由 XFL/XML 生成 `StageSelectManifest`
- 渲染 16 个原版 frame label、背景、选关按钮、页内导航按钮、hover 预览、难度按钮
- 使用 `allUnlocked` / `mixed` / `challenge` 三套 fixture 覆盖锁定、任务闪光、挑战模式

Stage 1 明确不做：

- 不接 AS2 snapshot
- 不触发真实 `_root.选关界面进入关卡`
- 不迁移委托任务界面
- 不修改 `.as` 或 SWF

## 2. 真相源

| 层 | 真相源 |
| --- | --- |
| 历史布局 | `flashswf/UI/选关界面/LIBRARY/选关界面UI/选关界面 1024&#042576.xml` |
| 按钮行为参考 | `flashswf/UI/选关界面/LIBRARY/选关界面UI/选关按钮.xml` |
| Web 运行时 | `launcher/web/modules/stage-select-data.js` 中的 generated manifest |
| Web 素材 | `launcher/web/assets/stage-select/` |
| 导出工具 | `tools/export-stage-select-manifest.js` |
| 静态审计 | `tools/audit-stage-select-layout.js` |
| 视觉对照 | `tools/run-stage-select-visual-audit.ps1` |

XFL/XML 是历史布局真相源；Web manifest 是迁移后的运行时真相源。任何手动校准都必须回写 manifest 或导出器，不能长期停留在 DOM/CSS 临时覆盖。

## 3. 当前资产状态

导出器已确认：

- labels：16
- 源 XML 选关按钮实例：167
- Web 运行时去重渲染实例：152
- 唯一关卡名：149
- 页内导航按钮：31
- 背景 missing：0

当前有 6 个页面使用 FFDec 派生背景，因为对应背景来自 SWF 内嵌 bitmap/shape；导出器会优先使用 Adobe Animate 2024 / Flash CS6 自带 JRE 运行 `ffdec.jar`：

- 沙漠虫洞
- 雪山内部
- 雪山内部第二层
- 亡灵沙漠
- 异界战场
- 坠毁战舰

预览图只有少量原始 PNG，但原版 `选关按钮.xml` 会在外部 PNG 加载失败时跳到 `Symbol 3274` 的内部命名帧，再失败才停在默认预览帧。Stage 1 导出器按同一优先级生成 Web 资源：外部 PNG 12 张、内部命名帧、默认帧；审计中 `previewMissing` 必须为 0，`previewFallbacks` 记录内部/默认回退数量。

## 4. 后续阶段

Stage 2 再设计 AS2 bridge：

- `stage_snapshot`：只读推送解锁、任务、挑战模式、翻译后的展示状态
- `stage_enter`：Web 发送 `{stageName, difficulty}`，AS2 校验后调用原 `_root.选关界面进入关卡`
- `stage_jump_frame`：跳转 frame label，AS2 侧维护 `_root.关卡地图帧值`
- `stage_open_diplomacy`：外交地图按钮只触发原 Flash 委托任务界面

Stage 3 只按关卡 opt-in 做现代化改造，优先选择 1 个 hero 页面验证节点式导航、2.5D 分层、远景天幕和热点 UI 分层，不承诺 16 页一次性重做。

## 5. 验证入口

```powershell
node tools/export-stage-select-manifest.js --summary
node tools/audit-stage-select-layout.js --json
node tools/run-stage-select-harness.js --browser edge
npm --prefix launcher/perf ci --ignore-scripts
node tools/capture-stage-select-web-frames.js --browser edge --fixture mixed --frame 基地门口 --hover-stage 新手练习场
powershell -ExecutionPolicy Bypass -File tools/run-stage-select-visual-audit.ps1
powershell -ExecutionPolicy Bypass -File launcher/build.ps1
powershell -ExecutionPolicy Bypass -File launcher/tests/run_tests.ps1
```

Browser harness：

```text
launcher/web/modules/stage-select/dev/harness.html?qa=1
```

视觉对照：

```text
tmp/stage-select-visual-audit/sheets/*-compare.png
tmp/stage-select-visual-audit/visual-audit-index.json
```

`run-stage-select-visual-audit.ps1` 借鉴地图 panel 的 audit sheet 思路，但参照物改为 FFDec 导出的 `DefineSprite 330`。FFDec sprite PNG 是 1689×928 的扩展 bounds，审计工具按 SVG 舞台原点 `translate(526.6, 206.95)` 裁出 1024×576，再与无头 Edge 捕获的 Web 舞台逐帧并排和 diff。首帧使用 `ffdecFrameIndex=1`，其余 label 使用 `sourceFrameIndex + 1`。
