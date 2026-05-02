# 选关界面 WebView 迁移路线图

**文档角色**：`flashswf/UI/选关界面` 到 Launcher WebView panel 的 canonical migration doc。  
**当前阶段**：Stage 2 Step 2 工程实现已落地；正式入口走 Web `stage-select`，旧 Flash `关卡地图` 保留为 fallback。

## 1. 阶段边界

Stage 1 已完成表现层与开发闭环：

- 新增独立 panel id：`stage-select`
- 通过刘海屏“其他 → 选关测试”打开
- 由 XFL/XML 生成 `StageSelectManifest`
- 渲染 16 个原版 frame label、背景、选关按钮、页内导航按钮、hover 预览、难度按钮
- 使用 `allUnlocked` / `mixed` / `challenge` 三套 fixture 覆盖锁定、任务闪光、挑战模式

Stage 2 在此基础上完成 live bridge 与正式入口替换：

- Web 打开时通过 `stageSelectSnapshot` 读取真实 `isStageUnlocked` / `isChallengeMode`，并把 `StageInfoDict` 中的 `Description` / `MaterialDetail` / `Limitation`、`tasks_to_do` 任务提示与推荐难度同步到 hover 卡片
- 难度按钮通过 `stageSelectEnter` 进入已解锁关卡
- C# 使用 `StageSelectTask` 桥接 `stage_select_response`
- AS2 `openWebStageSelect` 通过 `panel_request` 请求 `panel:"stage-select"`，并携带 `source`、`frameLabel`、`returnFrameLabel`；C# 打开正式入口时固定初始化 `mode:"runtime"`
- 场景门 helper 复用旧 `切换场景` 的方向键、hitTest、15 帧节流、出生点与转场记录语义；Web 打开成功时留在原场景，失败时回落旧 Flash `关卡地图`
- Web runtime 下隐藏 fixture/dev 控件与测试标题，16 个 frame tab 收进可展开区域菜单，`localFrame` 页内跳转只同步 Web 当前选关页，不覆盖 AS2 `_root.关卡地图帧值`；`return` / `return-garage` 会先通过独立 `returnFrameLabel` + `return_frame` 回到对应基地帧再关闭 panel；若返回目标已经是当前 `_root.关卡标志`，AS2 会跳过重复淡出

Stage 2 明确不做：

- 不迁移委托任务界面
- 不迁移外交 / 委托类按钮承载 UI
- 不处理战斗结束回流与角斗场返回路径
- 不手动编辑 SWF

## 2. 真相源

| 层 | 真相源 |
| --- | --- |
| 历史布局 | `flashswf/UI/选关界面/LIBRARY/选关界面UI/选关界面 1024&#042576.xml` |
| 按钮行为参考 | `flashswf/UI/选关界面/LIBRARY/选关界面UI/选关按钮.xml` |
| Web 运行时 | `launcher/web/modules/stage-select-data.js` 中的 generated manifest |
| Live bridge | `StageSelectTask` + `StageSelectPanelService` |
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
- 页内导航按钮：28
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

Stage 2 bridge 当前状态：

- Step 1：`stageSelectSnapshot` / `stageSelectEnter` 已服务刘海屏“选关测试”，按真实解锁校验后进关
- Step 2：已替换原 Flash 选关界面场景门入口，补齐打开时机、关闭回退、当前 frame label 同步；落地记录见 `docs/选关界面-AS2入口替换交接.md`
  - AS2 新增 `openWebStageSelect`，通过 `panel_request` 请求 `stage-select`
  - C# `TaskRegistry` / `LauncherCommandRouter` 支持 `panel_request stage-select` 与 `frameLabel/returnFrameLabel` 初始化，正式入口 `mode` 固化为 `runtime`，未知 panel 仍只记 unsupported
  - Web runtime 模式隐藏 fixture/dev 控件与测试标题，右侧空信息栏不占布局；16 个 frame tab 收进可展开区域菜单；`localFrame` 先切 Web 页面再发 `jump_frame`，C# 转为 AS2 `stageSelectJumpFrame`，只记录 `Web选关当前帧值`
  - `return` / `return-garage` 在 runtime 下发送 `return_frame`，C# 转为 AS2 `stageSelectReturnFrame`，使用入口保存的 `returnFrameLabel` 淡出回 `_root.关卡地图帧值` 对应基地帧；同场景返回仅关闭 Web panel，不做重复淡出；C# 关闭时通知 AS2 `stageSelectPanelClose` 清理门入口防重复打开状态
  - 已替换 `基地门口`、车库、地下 2 层、停机坪、联合大学左右出口
  - 保留旧 Flash `关卡地图MC` 与 `切换场景("", "关卡地图", ...)` fallback
- 后续：外交地图按钮继续触发原 Flash 委托任务界面；战斗结束回流与角斗场返回路径仍按旧 Flash 承载

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
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1
node tools/validate-doc-governance.js
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
