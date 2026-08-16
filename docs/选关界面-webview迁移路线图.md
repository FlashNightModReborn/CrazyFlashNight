# 选关界面 WebView 迁移路线图

**文档角色**：`flashswf/UI/选关界面` 到 Launcher WebView panel 的 canonical migration doc。  
**当前阶段**：Stage 2 Step 2 工程实现已落地；正式入口走 Web `stage-select`，旧 Flash `关卡地图` 保留为 fallback。Stage 3 已完成路线评估，获准进入单战区门控原型，不代表承诺 16 页全量 3D 化。

> **`.fla` 退役（2026-06）**：地图/选关界面已完全迁移至 web。`flashswf/UI/选关界面` 不再作为可再生 SOT，
> 仅保留为冻结历史参照。`launcher/web/modules/stage-select-data.js` 现为**唯一权威 SOT，允许直接手改**
> （新增外交地图据点等条目直接编辑本文件，不回写 .fla）。导出器 `--write-module` 默认拒绝覆盖手写 SOT
> （详见脚本顶部退役说明 / 第 2 节）。约束：`stageButton.id` 必须全局唯一，改后跑
> `node tools/audit-stage-select-layout.js`（已含重复 id 检测 + 渲染计数基线）。

## 1. 阶段边界

Stage 1 已完成表现层与开发闭环：

- 新增独立 panel id：`stage-select`
- 通过刘海屏“系统 → 其他 → 测试 → 选关测试”打开
- 由 XFL/XML 生成 `StageSelectManifest`
- 渲染 16 个原版 frame label、背景、选关按钮、页内导航按钮、hover 预览、难度按钮
- 使用 `allUnlocked` / `mixed` / `challenge` 三套 fixture 覆盖锁定、任务闪光、挑战模式

Stage 2 在此基础上完成 live bridge 与正式入口替换：

- Web 打开时通过 `stageSelectSnapshot` 读取真实 `isStageUnlocked` / `isChallengeMode`，并把 `StageInfoDict` 中的 `Description` / `MaterialDetail` / `Limitation`、`tasks_to_do` 任务提示与推荐难度同步到 hover 卡片
- 难度按钮通过 `stageSelectEnter` 进入已解锁关卡
- C# 使用 `StageSelectTask` 桥接 `stage_select_response`
- AS2 `openWebStageSelect` 通过 `panel_request` 请求 `panel:"stage-select"`，并携带 `source`、`frameLabel`、`returnFrameLabel`；C# 打开正式入口时固定初始化 `mode:"runtime"`
- 场景门 helper 复用旧 `切换场景` 的方向键、hitTest、15 帧节流、出生点与转场记录语义；Web 打开成功时留在原场景，失败时回落旧 Flash `关卡地图`
- Web runtime 下隐藏 fixture/dev 控件与测试标题，16 个 frame tab 收进可展开区域菜单，`localFrame` 页内跳转只同步 Web 当前选关页，不覆盖 AS2 `_root.关卡地图帧值`；`return` / `return-garage` 会先通过独立 `returnFrameLabel` + `return_frame` 回到对应基地帧再关闭 panel；若返回目标已经等于 `MapHotspotResolver` 从真实场景源解析出的当前热点，AS2 会跳过重复淡出
- Web 地图面板复用 `stage-select-data.js` 中的 `RootFadeTransitionFrame` 索引，为已解锁且有选关页签的地图热点提供二级“选关”动作；地图热点主点击仍保持直接导航。

Stage 2 明确不做：

- 不迁移委托任务界面（历史范围注记；2026-08 起副本任务入口已改为重定向 Web `tasks` 面板副本 tab，旧 Flash `委托任务界面` 已退役——现行表述见 `launcher/README.md` stage-select 节）
- 不迁移外交地图场景本体（场景本体至今未迁移；原「/ 委托任务详情界面」半句已随上条注记失效）
- 不处理战斗结束回流与角斗场返回路径
- 不手动编辑 SWF

## 2. 真相源

| 层 | 真相源 |
| --- | --- |
| 历史布局（冻结参照，已退役） | `flashswf/UI/选关界面/LIBRARY/选关界面UI/选关界面 1024&#042576.xml` |
| 按钮行为参考（冻结参照） | `flashswf/UI/选关界面/LIBRARY/选关界面UI/选关按钮.xml` |
| **权威运行时 SOT（手写）** | `launcher/web/modules/stage-select-data.js` |
| **计数基线单一真值（golden inventory）** | `launcher/web/modules/stage-select/dev/stage-select-golden.js` |
| Live bridge | `StageSelectTask` + `StageSelectPanelService` |
| Web 素材 | `launcher/web/assets/stage-select/` |
| 导出工具（冻结，默认拒绝覆盖） | `tools/export-stage-select-manifest.js` |
| 静态审计（含 dup-id 守卫） | `tools/audit-stage-select-layout.js` |
| 视觉对照 | `tools/run-stage-select-visual-audit.ps1` |

`.fla` 退役后，`XFL/XML` 仅是**冻结历史参照**（不再再生）；`launcher/web/modules/stage-select-data.js` 是**唯一权威运行时 SOT**。
日常修改（新增/移动据点、改名、调坐标）**直接手改该 manifest**，再跑 `audit-stage-select-layout.js` 守门——不再回写 .fla、不再重跑导出器全量覆盖。
`source*` 类指标（如 `sourceStageButtonInstances=182`）反映冻结 .fla，恒定不变；`rendered` 类计数 = .fla 渲染基线 + web 手写新增，随手改增长，新增条目时同步上调审计基线。

## 3. 当前资产状态

导出器已确认（冻结 .fla 源统计恒定；运行时真值以 golden 为准）：

- labels：16
- 源 XML 选关按钮实例：182
- 源 XML 选关按钮实例（冻结 .fla）：182
- Web 运行时去重渲染实例：166（.fla 基线 164 + web 手写 2：外交-隧道据点 subway、据点M）
- 直达入口实例：14（`entryKind=map` 10 + `entryKind=task` 4）
- 渲染外交地图按钮：10（含 subway）
- 唯一关卡名（冻结 assetReport）：162；`stageNames` inventory 当前 164（冻结 162 + web 手写 2）
- 页内导航按钮：28
- 背景 missing：0

> 注：subway「外交-隧道据点」是 .fla 退役后首个纯 web 手写据点（无 .fla 源），id `stage_0_15`。
> 「据点M」（id `stage_10_18`，基地车库页，UnlockCondition 75）来自 commit `9f7584b3cb` 情报支线半成品，新增时未补登 `stageNames` 与审计基线（审计红、harness 外交计数断言过期），2026-08-16 P0 已补登闭环。
> 后续新增条目同此模式：id 唯一 + 补登 `stageNames` + 更新 golden 的 `expected` / `provenance`（不再手改审计工具内的数字）。

当前有 6 个页面使用 FFDec 派生背景，因为对应背景来自 SWF 内嵌 bitmap/shape；导出器会优先使用 Adobe Animate 2024 / Flash CS6 自带 JRE 运行 `ffdec.jar`：

- 沙漠虫洞
- 雪山内部
- 雪山内部第二层
- 亡灵沙漠
- 异界战场
- 坠毁战舰

预览图只有少量原始 PNG，但原版 `选关按钮.xml` 会在外部 PNG 加载失败时跳到 `Symbol 3274` 的内部命名帧，再失败才停在默认预览帧。Stage 1 导出器按同一优先级生成 Web 资源：外部 PNG 12 张、内部命名帧、默认帧；审计中 `previewMissing` 必须为 0，`previewFallbacks` 记录内部/默认回退数量。P4-b 新增第四级派生预览：`tools/derive-stage-select-previews.js` 对仍停在默认帧的关卡按「StageInfo → 单关 XML 首个 Background SWF → FFDec frame 1 主视觉帧 → 异常图像拒收 → 细节滑窗裁缩 161×69 JPEG」产出 `previewSource=derived` 资产（当前 previewSources = external 12 / internal 76 / derived 65 / default 11 / missing 0，报告与 stage→background 索引在 `tmp/stage-select-preview-derive/`）。

## 4. 后续阶段

Stage 2 bridge 当前状态：

- Step 1：`stageSelectSnapshot` / `stageSelectEnter` 已服务刘海屏“选关测试”，按真实解锁校验后进关
- Step 2：已替换原 Flash 选关界面场景门入口，补齐打开时机、关闭回退、当前 frame label 同步；落地记录见 `docs/选关界面-AS2入口替换交接.md`
  - AS2 新增 `openWebStageSelect`，通过 `panel_request` 请求 `stage-select`
  - C# `TaskRegistry` / `LauncherCommandRouter` 支持 `panel_request stage-select` 与 `frameLabel/returnFrameLabel` 初始化，正式入口 `mode` 固化为 `runtime`，未知 panel 仍只记 unsupported
  - Web runtime 模式隐藏 fixture/dev 控件与测试标题，右侧空信息栏不占布局；16 个 frame tab 收进可展开区域菜单；`localFrame` 先切 Web 页面再发 `jump_frame`，C# 转为 AS2 `stageSelectJumpFrame`，只记录 `Web选关当前帧值`
  - `return` / `return-garage` 在 runtime 下发送 `return_frame`，C# 转为 AS2 `stageSelectReturnFrame`，使用入口保存的 `returnFrameLabel` 淡出回 `_root.关卡地图帧值` 对应基地帧；同场景返回仅关闭 Web panel，不做重复淡出；C# 关闭时通知 AS2 `stageSelectPanelClose` 清理门入口防重复打开状态
  - 外交地图入口按原版绿色点直达；副本 / 委托入口已改为 `entryKind:"task"` → `openWebDungeon` 重定向 Web `tasks` 面板副本 tab（旧 Flash 委托详情已退役，本条取代此前「继续打开旧 Flash 委托详情」表述）；Web 地图面板可通过 `open_stage_select` 二级动作直接打开对应选关页签
  - 已替换 `基地门口`、车库、地下 2 层、停机坪、联合大学左右出口
  - 保留旧 Flash `关卡地图MC` 与 `切换场景("", "关卡地图", ...)` fallback
- 后续：战斗结束回流与角斗场返回路径仍按旧 Flash 承载

Stage 3 只按战区 opt-in 做现代化改造，优先选择 1 个 hero 页面验证构成主义三维沙盘、节点式导航、SWF 派生视觉资产和 DOM 热点 UI 分层，不承诺 16 页一次性重做。技术路线、成本假设与放行门槛见第 5 节。

## 5. Stage 3 构成主义三维沙盘原型

### 5.1 决策状态

- **已批准**：投入一个单战区、可完整退出的技术 / 美术垂直切片，用真实关卡节点验证 Three.js 在 WebView2 内的体验、性能和生产成本。
- **尚未批准**：16 个战区全量重做、逐关独立精模、以 WebGL2 取代当前 2D fallback、把关卡或任务权威迁入三维 manifest。
- **默认 hero 候选**：`基地门口`。它同时覆盖基地辨识、普通关卡、任务上下文和多地标密度；正式资产施工前仍可按素材闭包与叙事代表性换成等规模页面。
- **复盘点**：hero slice 验收后再决定继续生产管线、退回 img2 / 2.5D，或只保留少量 hero 战区。不得用“Three.js 已跑起来”替代投资回报复盘。

### 5.2 目标形态

Stage 3 的推荐终态不是“把每张 SWF 背景自动转换成三维关卡”，而是混合渲染：

| 层 | 职责 |
| --- | --- |
| Three.js | 战区沙盘、共享构成主义体块、地标剪影、受限镜头、选中 / 路径空间反馈 |
| SWF 派生资产 | 关卡色板、轮廓、招牌 / 阵营贴花、背景母版、浅挤压装饰与概念参考 |
| DOM | 关卡名、锁定 / 难度 / 任务状态、剧情摘要、键盘焦点、无障碍与最终点击命中 |
| 当前 2D Stage Select | WebGL2 不可用、上下文丢失、低配策略或原型失败时的正式 fallback |

美术采用构成主义 / 沙盘售楼盘语言：正交或弱透视固定镜头，使用板、梁、塔、圆筒、管线、斜坡、废墟块等共享几何语法，通过夸张轮廓、阵营色和少量贴花区分地标。该风格用于建立稳定的生产约束，不应成为取消辨识度、比例和最终画布可读性检查的理由。

img2 继续作为互补工具，用于概念探索、背板、贴花、丝网印刷式纹理和地标变体草图；不负责最终空间结构与点击拓扑。

### 5.3 数据与权威边界

- `launcher/web/modules/stage-select-data.js` 继续是选关入口、布局和稳定 id 的唯一运行时 SOT；AS2 继续权威判定解锁、挑战模式、任务进度与实际进关。
- 三维施工时可新增纯视觉 `stage-diorama-manifest`（最终路径随原型确定），只允许用稳定 `stageButton.id` / `frameLabel` 关联节点、GLB node、相机锚点和视觉标签；不得复制出第二套关卡名、解锁条件或进入参数。
- 任务、剧情和对话只保存 `taskId` / 对话引用 / spoiler tier 等关联键，运行时按现有 snapshot 与 AS2 剧透门控读取；不得把动态状态或完整对话手抄进三维资产配置。
- 当前盘点用于估算生产规模：`data/stages` 约 212 个关卡配置、992 个子场景背景引用、354 个不同背景 SWF。关卡 XML 的主体是背景序列与战斗配置，不是建筑物级语义场景图，因此必须保留人工语义标注和美术编排步骤。

### 5.4 SWF 资产利用边界

原型允许建设离线参考包工具，输出：

- 关卡 / 子场景 contact sheet 与背景序列；
- 主色板、轮廓、层级 bounds 和可复用贴花候选；
- `stage → background sequence` 索引；
- 人工补录的地标原型标签，如 `tower`、`factory`、`tunnel`、`temple`、`wreck`。

不建设通用“SWF → 语义 3D / Mesh”转换器。SWF 可提供视觉母版、局部矢量和合成顺序，不能可靠推导建筑用途、体量和交互意义；若自动化不能显著缩短人工编排时间，应停止扩张转换工具。

### 5.5 WebView2、WebGL2 与资源分发

- 项目当前支持目标仍为 Windows 10 22H2+ / Windows 11 x64。正常更新的目标系统通常已有 Evergreen WebView2 Runtime，当前开发与原型不因此阻断。
- Three.js 作为固定版本的本地 Web 资产进入发布闭包，禁止运行时依赖 CDN；用户无需单独安装 Three.js 或“WebGL2 Runtime”。
- WebGL2 来自 WebView2/Chromium + ANGLE + GPU 驱动，不能仅凭“已安装 WebView2”视为必然可用。打开 3D 页面前必须以 `canvas.getContext("webgl2")` 做能力检测，并处理 `webglcontextlost`；失败立即使用当前 2D renderer。
- 当前发布包只携带 WebView2 managed DLL 与 `WebView2Loader.dll`，缺 Runtime 时会 fail-closed 并引导用户安装。自动部署 Evergreen Bootstrapper / Standalone Installer 是**正式上线 gate**，不是 hero 原型前置；不采用需要项目自行追更安全版本的大体积 Fixed Version 作为默认方案。
- 实现 Three.js 依赖时属于“新子栈 / 构建闭包变化”触发器：同轮同步 `launcher/README.md`、`agentsDoc/architecture.md`、`agentsDoc/testing-guide.md` 与打包清单，并运行文档治理巡检。只有写入代码和发布链时触发，不因本节路线评估提前宣称已经接入。

### 5.6 原型工程约束

- 以“一个战区一个 GLB + 全局共享积木库”为默认资产粒度，不以“每关一个完整场景”为生产单位。
- 正式 UI 使用 DOM 呈现文字与按钮；不把关卡名、长剧情文本或可访问交互做成三维文字。
- 优先无光照 / 有限材质、顶点色和烘焙 AO；默认关闭实时阴影、景深、泛光链、透明 PBR 与全屏后处理。
- 重复梁柱 / 楼板使用实例化；只懒加载当前战区。切换战区和关闭 panel 时显式释放 geometry、material、texture、render target、listener 与动画循环。
- 使用按需渲染：只在镜头 tween、hover / 选中反馈和受控环境动画期间出帧；静止态不维持无意义的高频 RAF。
- 固定 1024×576 设计画布并复核 1024×576、1366×768、1920×1080；限制相机移动范围，选关效率优先于自由观察。
- hero slice 不改 Stage Select bridge、进关协议、close 语义和旧 Flash fallback；若原型需要协议变更，必须另开设计与验证范围。

### 5.7 成本假设与放行门槛

以下仅是当前资产规模下的规划区间，不是交付承诺：

| 阶段 | 预期产物 | 估算 |
| --- | --- | --- |
| 技术探针 | 固定版本 Three.js、本地加载、单沙盘 blockout、WebGL2 回退、性能指标 | 1–2 人周 |
| hero 垂直切片 | 1 个战区、12–16 个可辨地标、真实状态 / 任务上下文、完整开关生命周期 | 累计 6–10 人周，约 4–6 日历周 |
| 生产管线 | SWF 参考包、积木库、GLB / manifest 校验、压缩与打包闭包 | hero 后追加 4–8 人周 |
| 16 战区积木化生产 | 150+ 节点，以共享语法和局部定制为前提 | 约 6–12 人月 |
| 逐关高定 | 大量独特模型、材质和动画 | 可能升至 18–30 人月以上，不作为默认路线 |

hero slice 必须同时满足以下 gate，才允许扩大生产：

- 12–16 个地标在最终 1024×576 画布上可快速区分；小规模测试的找关时间与误点率不劣于当前 2D 页面。
- 常规目标机交互目标 60 FPS，低配模式至少稳定 30 FPS；静止态近零持续渲染。
- 建议单战区冷加载不高于约 1.5 秒、GLB + 纹理约 5–10 MB、可见三角形约 15–25 万、draw call 约 100 以内。它们是原型预算线，可由真实 WebView2 基准修订，不是脱离设备的硬件事实。
- 连续打开 / 关闭 30 次后，Three renderer 统计、进程内存与 GPU 资源不持续增长；WebGL context lost 能回退或恢复。
- GPU 判据来自真实 WebView2 / iGPU，headless harness 只负责逻辑、主线程和确定性截图，不用其绝对帧率代替真机结论。
- 积木库稳定后，普通新地标的目标生产成本不超过约 0.5–1.5 个美术工作日；若仍普遍需要 3–4 天以上，暂停全量路线并比较 img2 / 2.5D 的收益。

不满足任一关键 gate 时，默认保留 Stage 2 现状，并把已产出的概念、贴花和分层资产回收给 2D / 2.5D 方案，而不是为证明前期投入继续扩张。

### 5.8 原型验证计划

实现时保留第 6 节全部 Stage 2 gate，并新增独立 hero harness，至少覆盖：

- WebGL2 可用 / 不可用、context lost、低特效和 2D fallback；
- 真实 snapshot、锁定节点、难度选择、任务提示、页内切换与 close/reopen；
- 1024×576 / 1366×768 / 1920×1080 的镜头、DOM 锚点与命中区对齐；
- 当前战区懒加载、切换释放、30 次生命周期压力与资源统计；
- 真 WebView2 五次重复取中位数的加载、交互帧时间和 GPU 采样。

在原型代码、资源路径和 harness 命令真实存在前，不提前把计划命令写进 `agentsDoc/testing-guide.md`，也不声称 Stage 3 已通过验证。

## 6. 验证入口

```powershell
node tools/export-stage-select-manifest.js --summary
node tools/audit-stage-select-layout.js --json
node tools/audit-diplomacy-stage-select-links.js --json
node tools/derive-stage-select-previews.js --report tmp/stage-select-preview-derive/report.json   # 重派生 derived 预览资产+报告；--write 才回写 manifest（改前自动备份 tmp/）
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
