# 测试约定与验证矩阵
**文档角色**：验证矩阵 canonical doc。  
**最后核对代码基线**：commit `d063d53c2`（2026-05-30）。

按子栈选验证；不要用「编译一下」「跑一下 build」笼统覆盖跨栈任务。

## 0. 通用前缀

PowerShell 命令前先跑（避免 GBK 乱码）：

```powershell
chcp.com 65001 | Out-Null
```
下方所有 PowerShell 命令默认已执行该前缀,不再每条重复。
## 1. 任务 → 验证入口矩阵

| 任务类型 | 必跑 | 视改动追加 |
|----------|------|------------|
| AS2 class / 帧脚本 / Flash 资源联动 | `scripts/compile_test.ps1` 或 `bash scripts/compile_test.sh` | Flash IDE 复核、截图、专项 TestLoader 套件、`tools/swf-audit/`（SWF 静态审计：背景实例覆盖度 / 尺寸 / 标签直方图，见该目录 README） |
| AS2 UI → Web Panel 迁移 | 按 [as2-web-panel-migration.md](as2-web-panel-migration.md) 补闭环表 + `launcher/build.ps1` + `launcher/tests/run_tests.ps1` | AS2 fresh trace / Web harness / 游戏内端到端手测按改动面追加 |
| XML / 数据 / 游戏数值 | 受影响路径运行时 smoke | `compile_test`、游戏内人工验证 |
| 导弹运动 / 追踪参数离线调优 | `python tools/missile-tuning-sim/run_sim.py compare --configs ...` | `scan --objective loiter|pressure|hit` / `audit`、`compile_test`、游戏内人工验证 |
| Launcher C# / Host / Bus | `launcher/build.ps1` | `launcher/tests/run_tests.ps1`、`tools/cfn-cli`、`--bus-only` |
| Launcher WebView2 / GPU 诊断 | `powershell -ExecutionPolicy Bypass -File tools/set-launcher-gpu-preference.ps1 -List` + `powershell -ExecutionPolicy Bypass -File tools/sample-launcher-gpu.ps1 -DurationSeconds 6` + `node tools/audit-web-overlay-complexity.js` | `-Apply` / `-Revert` 后完整重启 launcher / game，再复核 WebView2 GPU engine；机器不稳定时优先用静态复杂度审计 |
| Launcher Web / Minigame | `node launcher/tools/run-minigame-qa.js --game lockbox\|pinalign\|gobang\|all` | browser harness、`node launcher/tools/validate-minigame-final-state.js` |
| Launcher Web / Map Panel | `powershell -ExecutionPolicy Bypass -File launcher/build.ps1` + `node tools/audit-map-taskmarkers.js`（契约守门，必须 0 error / 0 warn） | browser harness `map-ui1`~`map-ui32` 全绿（`launcher/web/modules/map/dev/harness.html` → 面板"Run suite"，或 `node tools/run-map-harness-headless.js --browser edge`）、`node tools/audit-map-layout.js`；重算 filter-fit preset 时跑 `node tools/tune-map-filter-fit.js --write` |
| Launcher Web / Stage Select Panel | `powershell -ExecutionPolicy Bypass -File launcher/build.ps1` + `node tools/export-stage-select-manifest.js --summary` + `node tools/audit-stage-select-layout.js --json` + `node tools/audit-diplomacy-stage-select-links.js --json` + `node tools/run-stage-select-harness.js --browser edge` | 接 AS2 snapshot / enter 时追加 `launcher/tests/run_tests.ps1` 与 `scripts/compile_test.ps1`；坐标/视觉偏移时追加 `powershell -ExecutionPolicy Bypass -File tools/run-stage-select-visual-audit.ps1` 生成 FFDec/Web 对照图 |
| Launcher Web / Intelligence Panel | `powershell -ExecutionPolicy Bypass -File launcher/build.ps1` + `powershell -ExecutionPolicy Bypass -File launcher/tests/run_tests.ps1` + `node tools/validate-intelligence-h5.js --strict` + `node tools/run-intelligence-harness.js --browser edge` | 改 AS2 `intelligenceState/intelligenceTooltip` 或正式入口运行态联动时追加 Flash compile smoke；手测 Native HUD 与旧 Web notch 的主工具栏“情报”和“其他 → 情报测试” |
| Launcher Web / Task Panel | `node tools/run-tasks-harness.js --qa`（task-ui1~43 + ach-ui1~13，Edge headless：筛选/列表/排序/详情缓存/富物品 tooltip/空态 + 写操作交付·放弃·确认弹窗·背包满·ESC modal栈·远程交付门控(含绕过按钮直发 finishTask→requires_npc 服务端门控自断言)·删除在途锁·前往交付·finishNavigable 不缓存固化(注册表迟到→重选复查) + **事件日志(WS6)：任务树渲染·对话按钮可见性·回放内联文本(不关面板)·对话 AS2 htmlText(FONT/B)经 convertAS2Html 渲染·tab往返·图表视图(BALDR SKY风:六边形+前置连线渲染/点节点选中+明细/25%缩放/章节折叠/左键拖拽平移+点击拖拽判定/任务线配色按链区分/对话回放进度门控/重开重置工具栏)·对话回放真白名单清洗恶意标签(XSS,ui38)·图表防剧透(未接取节点不进图+详情遮罩,ui39)·服务端对话门控(绕过直发 finish→locked,ui40)·共享判定条件进度行渲染(conditions {label,cur,target}+done态,ui41)·条件进度不缓存固化(运行态字段重选后台复查→进度行就地刷新,ui42)·satisfied 权威纠偏(条件达成翻转完成态→徽章/交付按钮/列表角标同步,ui43)·纯缓存契约仅限无 conditions/无导航复查任务(ui11)** 自断言） | 改 AS2 `taskSnapshot/taskDetail/tasksTooltip/taskFinish/taskDelete/taskNavigateFinish/taskTreeState/taskReplayDialogue/achievementState/achievementClaim` 或 C# `TaskTask`/`WebOverlayForm` 路由时追加 `launcher/tests/run_tests.ps1`（xUnit `TaskTaskTests` 26 + `PanelBridgeTests` 3；Web→Flash 透传信封收口到共用 `PanelBridge.BuildFlashCommand`，含 `action`/`task` 保留键守卫——全 8 桥共用、保留键集单一处，新桥调它即继承，杜绝逐桥漏抄）+ `scripts/compile_test.ps1`；**改任务数据展示字段(title/description/chain) 须重跑 `node tools/derive-task-catalog.js`（build Step 1e；含闭包校验器，缺 `$KEY` exit 1）刷新 `task-catalog.json`**；**任务 `conditions` 字段同走 Step 1e 校验（类型枚举/label 必填/sinceAccept 单调限定/economyCount 白名单单源/布尔型 taskFinished·itemOwned 的 target 必须=1/itemOwned count≥1/chainProgress 有序号链存在+target≤链最大 seq/条件死锁=单调 AND-OR 不动点（对齐运行时语义：taskAvailable 只查 get_requirements、链序号不约束完成顺序；chainProgress 按「任一 seq≥target 候选可完成」析取处理，基线可完成集 vs 带条件集之差=条件死锁，统一覆盖自链·seq 缺口·跨链/taskFinished 互锁·get_req 介导环·级联，且不误报同链独立乱序任务)）；**build Step 1e 固定运行 `node tools/test-derive-task-conditions.js`（23 用例正反矩阵，合成夹具走 `--task-dir` 不碰真实数据；正式数据 conditions=0 时常规派生不执行这些分支，矩阵负责持续守门）**；新增 objective 类型三处联动：`ObjectiveEvaluator.as` 分发 + `tools/lib/objective-types.js` 枚举 +（成就启用时）achievement derive params case**；**改成就数据(`data/achievement/*.json`)或 `AchievementMetrics.as` 白名单须重跑 `node tools/derive-achievement-catalog.js --check` + 真跑（build Step 1f；含 objective 枚举/跨域闭包/economyCount 白名单单源/hidden 脱敏校验）刷新 `achievement-catalog.json`**；成就 tab=tasks 面板第三 tab（`achievement-tab.js`，claim 走 `achievementClaim` 全称命令防 ShopTask 截胡，背包满回 `inventory_full` 保持可重试）；写操作传 taskId（非 index，splice 后偏移）、交付走服务端 `taskCompleteCheck` 硬门控、远程交付仅 `finish_remote` 任务开放（否则回 `requires_npc`）、前往交付复用地图 `MapPanelService.navigateToHotspot`（不可达回 `not_navigable`）、事件日志静态目录走 build 派生 web 直读·进度叠加走 `treeState`·对话回放 `replayDialogue` 按需回传单任务对话文本行 web 内联渲染(不关面板)；视觉/动效复核 `node tools/run-tasks-harness.js --shot=<png> --query="view=list&filter=副本&detail=6"`（日志 tab 用 `--query="tab=log"`）；正式 runtime 富 tooltip/筛选/动效/交付发奖扣物/放弃移除/前往跳转/事件日志树·对话回放需游戏内端到端手测；**远程交付（`finish_remote`）成功后面板必须关闭**——AS2 `FinishTask` 会 `SetDialogue` 完成对话+弹奖励提示界面+可能自动接取下一任务再弹接取对话，这些原版 UI 在游戏层、被独占 web 覆盖层挡住，故成功路径关面板露出（手测确认奖励/对话可见且无残留） |
| Launcher Web / Team Panel | `powershell -ExecutionPolicy Bypass -File tools/audit-pet-roster-types.ps1` + `node tools/run-team-harness.js` + `launcher/build.ps1` + `launcher/tests/run_tests.ps1` | 游戏内手测 Native/Web fallback 的唯一战队入口、四标签、领养/雇佣/出战/关闭重开；未改 AS2 时无需 Flash smoke |
| 文档与治理 | `node tools/validate-doc-governance.js` | 交叉 grep / 链接检查 / 基线复核 |

## 2. AS2 / Flash 验证

**入口**：`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1` 或 `bash scripts/compile_test.sh`

**两种构建目标，成功判据不同**（取决于 Flash CS6 当前打开的是哪个 loader；脚本据 `publish_done.marker` + `compiler_errors.txt` 决定 exit 0/1）：

- **TestLoader（测试构建，带 trace）**：成功 = `[OK] 编译完成` + 本次运行**新鲜生成**的 `scripts/flashlog.txt` + trace 无 `[TEST_FAIL]` 哨兵 + `compiler_errors.txt` `0 个错误`。
- **asLoader / publish 模式（发布二进制，剔 trace 等功能以免性能损耗）**：**本就不出 trace**——脚本会打 `[INFO] 无 trace 输出 (publish 模式不执行 trace)`，`flashlog.txt` 不刷新属正常，**不要据此判失败**。成功 = `[OK] 编译完成` + `scripts/compiler_errors.txt` 显示 `0 个错误` + `scripts/asLoader.swf` 已刷新（mtime/size 变化）。
  - **把「SWF 已刷新」变成机器门**：跑 publish 时传 `-VerifySwf scripts/asLoader.swf`（如 `powershell -File scripts/compile_test.ps1 -TimeoutSeconds 150 -VerifySwf scripts/asLoader.swf`）。脚本触发前记录 SWF 的 mtime/size 基线，成功路径校验其确被重写：未变 / 不存在 → `[ERROR] 目标 SWF 未刷新` + `exit 1`（fail-closed）。**不传该参数时脚本只看 `0 个错误`，「SWF 已刷新」需人工核对**——以前文档写了这条判据但脚本不强制，marker 产出而 SWF 未重写会假成功，故 asLoader publish 一律带 `-VerifySwf`。

公共项：`publish_done.marker` **仅说明 JSFL 触发结束**，不能单独视为成功；必要时核对 `scripts/compile_output.txt`。慢机编译易超过默认窗口（实测 asLoader publish ~77s），`[TIMEOUT]` 后先核对 marker / SWF / `compiler_errors.txt` 是否其实已在超时后产出，再用 `-TimeoutSeconds` 调大重试。**新建 .as 类被引用时必须显式 import——含同包引用（2026-06-13 实测）**：CS6 常驻会话的同包隐式解析用陈旧包索引，会话期间新建的类不写 import 会报 `无法加载类或接口'X'` 且无语法错误细节（帧脚本与跨包显式 import 均正常）；修复 = 引用方加显式 import；删 ASO 缓存、重复编译、`fl.quit()` 均无效，BOM 正常 + 帧脚本能加载即可排除内容/编码方向。

**对外表述边界**：

- 可以说：`已完成 Flash CS6 自动化 smoke 验证` / `已触发编译并拿到新鲜 trace`（TestLoader）/ `asLoader 发布编译 0 错误、SWF 已重生成`（publish 模式）
- **不要**在缺少新鲜 trace、编译器错误面板或 IDE 复核时说「已编译通过」；但 **asLoader publish 无 trace 属正常设计**，以 `0 个错误` + SWF 刷新为准，别因缺 trace 误判失败

**主 SWF / asLoader class 边界审计**：改 `scripts/类定义/org/flashNight/neur/Server/*` 或部署前追加 `node tools/audit-as2-class-embedding.js --policy child-only`；临时双 SWF 重打兜底用 `--policy dual-build --marker _repairPending --marker applyRepairResolved`。若主 SWF 仍嵌入 `__Packages.org.flashNight.neur.Server.SaveManager` / `ServerManager`，asLoader 新 class 不会覆盖。**全局单一归属门（asLoader 重构 P1）**：`--policy single-ownership` 断言「主 SWF 嵌入 `org.flashNight.*` 类 = 0 且无 class 同时嵌入两 SWF」——比 child-only 更强，守「主时间轴误直引用游戏 class 致其嵌进主 SWF → 首注册胜出 shadow 掉 asLoader 重编版本」。改主 FLA 帧脚本 / 新增主时间轴 class 引用、或部署前跑（当前基线 main=0 / loader=570 / intersection=0）。
详见 [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md)。
## 3. Launcher Host 验证
| 用途 | 命令 |
|------|------|
| 构建 | `powershell -File launcher/build.ps1` |
| xUnit | `powershell -File launcher/tests/run_tests.ps1` |
| 总线健康 | `bash tools/cfn-cli.sh status` |
| AS2 回环 | `bash tools/cfn-cli.sh console "help"` |
| 集成 (testMovie) | `bash tools/cfn-cli.sh start-bus`（headless：直跑 `runtime/Core.exe`，绕 bootstrap 的 MessageBox） |

`--bus-only` 适用：Flash CS6 testMovie ↔ Launcher 通信链验证;AI / 模拟实验需外部 Flash 自连总线;排查启动链路 vs 总线本身。根目录 `.exe` 是 net10 native bootstrap（runtime 缺失会弹框阻塞自动化），headless 调用方（`cfn-cli.sh` / `automation/start.ps1` / `scripts/gobang_trainer_cycle.ps1`）都已切到 `runtime/Core.exe` + 复刻 bootstrap 的 `DOTNET_ROOT` 探测。验 **Flash↔launcher 建连 / XMLSocket / FlashPlayerTrust** 类问题**只用真 launcher**，别用 `compile_test`/`testMovie` 或裸 socket 桩：testMovie 作者环境 socket 沙箱与独立播放器不同（自动信任 + 默认探 843 master policy），裸桩常假阳性（`connect()=true` 但服务端零连接、`onConnect` 不回）；定病因优先读真机 `logs/launcher.log` 是否出现 `WaitingConnect -> WaitingHandshake`(=socket 已连上)。复盘见 [优化随笔/Flash本地SWF信任与Launcher建连](../scripts/优化随笔/Flash本地SWF信任与Launcher建连——trust编码与IPv6loopback踩坑.md)。

当前 `launcher/build.ps1` 除编译外还会 fail-fast 校验 `launcher/web` 必需资源（bootstrap/overlay/config/assets/help/icons/data/cursor/map/stage-select 与关键 modules / intelligence panel + H5 component renderer / minigame 入口）、运行 `node tools/audit-native-cursor-assets.js` 校验 native cursor `64x64` 画布与 `(16,16)` 热点契约，并校验 `launcher/data/map_hud_data.json` / `save_schema.json` 存在。

DPI 相关 smoke：改 DPI manifest / overlay 坐标 / Web viewport metrics 时，除 build + xUnit 外人工覆盖单屏 100/125/150/175%、Windows 未勾选与“应用程序”覆盖、双屏混合 DPI 启动/跨屏/全屏切换；“系统/系统(增强)”只要求 `[DPI]` 日志和提示，不把点击正确性列为通过标准。
Native HUD parity gate：改 [NotchOverlay](../launcher/src/Guardian/NotchOverlay.cs)、[RightContextWidget](../launcher/src/Guardian/Hud/RightContextWidget.cs)、[RightHudLayout](../launcher/src/Guardian/Hud/RightHudLayout.cs)、[MapHudWidget](../launcher/src/Guardian/Hud/MapHudWidget.cs)、[SafeExitPanelWidget](../launcher/src/Guardian/Hud/SafeExitPanelWidget.cs)、[ComboWidget](../launcher/src/Guardian/Hud/ComboWidget.cs)、`Program.cs` native widget 注册顺序时，必跑 `launcher/build.ps1` + `launcher/tests/run_tests.ps1`。人工截图对比旧 Web 与 native：刘海栏居中 pill/hover toolbar/未 ready 行为、combo 输入提示 + DFA/Sync 命中扫光/收起、toast 最多 8 条队列、`game` notice 去重计数/3 秒退场、基地场景、任务完成可交付、小地图 PNG 剪影/current/beacon + 展开/折叠、未播放/播放中 jukebox、暂停态、安全退出弹出、8 个 panel 开关后 idle。通过标准：刘海栏与右侧 cluster 的位置、宽度、纵向顺序、点击区域、文案和主要颜色层级等价；允许字体抗锯齿差异。性能回归需确认 idle WebView2 仍 `SW_HIDE`，Ctrl+G / Task Manager 采样不比当前 native HUD 基线明显退化。
## 4. Launcher Web 验证（Minigame / Map / Jukebox）
| 用途 | 命令 |
|------|------|
| Node QA(单局) | `node launcher/tools/run-minigame-qa.js --game lockbox\|pinalign\|gobang` |
| Node QA(全套) | `node launcher/tools/run-minigame-qa.js --game all` |
| Jukebox Panel harness | `node tools/run-jukebox-harness.js --browser edge` |
| 静态校验 | `node launcher/tools/validate-minigame-final-state.js` |

**Browser harness**(直接打开)：`launcher/web/modules/minigames/{lockbox,pinalign,gobang}/dev/harness.html` / `launcher/web/modules/map/dev/harness.html` / `launcher/web/modules/stage-select/dev/harness.html` / `launcher/web/modules/intelligence/dev/harness.html` / `launcher/web/modules/jukebox/dev/harness.html`。

**默认顺序**：纯逻辑 / 确定性问题先跑 Node QA；协议 / DOM / 布局 / 交互问题进 browser harness；目录 / 协议 / 旧入口回流问题再补静态校验。
`map` harness 固定覆盖：Canvas renderer debug state 与非空像素、顶部分页与关闭按钮的 hit-test 可达性、右侧层级按钮遮挡、学校页 `室友头像` 动态切换、`1366x768` 紧凑视口滚动可达性、locked group 的锁定提示与锁定原因可达性、`base` assembled 热点框与 Canvas scene visual 联合包围框对齐（`map-ui11`）、静态头像运行时 rect 与 source metadata 对齐（`map-ui10`）、taskNpc 环锚点跟随并套住动态头像、任务环层低于 hotspot 标签层（`map-ui12`）、连点热点去重 + busy 物理 disabled（`map-ui13`）、hotspot / 分页 / filter / close 的 `data-audio-cue` 语义路由 **且单次触发**（`map-ui14`，依赖 overlay 载入 `modules/audio.js` + `modules/overlay-audio-bindings.js`；harness 用 `BootstrapAudio` 计数器存根替身）、右侧 rail 脱离 stage frame + body 不溢出（`map-ui15`）、locked filter 点击不切状态且弹锁定原因 toast（`map-ui16`）、faction filter 切换驱动 `data-active-filter` 属性与 canvas filter summary（`map-ui17`）、defense restricted filter 触发 canvas anomaly state（`map-ui18`）、rail 手风琴仅展开 active 非 meta filter 子场景列表 + 点子项复用 `requestNavigate`（`map-ui19` / `map-ui20`）、filter-fit preset 按 page/filter preset 命中并维持 coverage floor（`map-ui21`）、学校页静态头像与场景归属保持一致并输出 review 候选（`map-ui22`）、热点左下角标签通过 content-fit 内独立标签层保持高于透明命中层并贴合热点（`map-ui23`）、地图热点二级“选关”动作打开匹配 stage-select frame 且不替代主 `navigate`（`map-ui24`）、host 驱动关闭后 canvas RAF 循环停止不泄漏（`map-ui25`）、任务红点 hotspot/filter/page 三级聚合 + 同 hotspot 多 NPC 折叠为 1（`map-ui26`）、locked group 剧透防护下任务红点不点亮（`map-ui27`）、task hotspot stage-select 副动作快捷入口（`map-ui28`）、同一 hotspot 多 NPC 仅计 1 + 跨 filter 折叠（`map-ui29`）、page tab badge 计数 >= 10 时夹到 "9+"（`map-ui30`）、pixel-level hittest 引擎 alpha 边缘 / 重叠覆盖（z 顺序后画覆盖前画）/ filter 过滤 / 浮点/NaN 坐标边界（`map-ui31a`~`map-ui31d`）、sceneVisual DOM 层非 hierarchy 模式 canvas drawScenes 短路（`map-ui32a`）/ hierarchy 模式 canvas 画非 focus muted + DOM 显 focus 无双绘（`map-ui32b`）/ current+hover 不同位 DOM 两张同显 + dimmer 压暗（`map-ui32c`）。

改 `map-panel.js` / `map-canvas-stage-renderer.js` / `map-panel-data.js` / `panels.js` / `地图系统_WebView.as` 的 PR **必须**在合并前跑通以下 gate（缺一不得合并）：
1. `node tools/audit-map-taskmarkers.js` 输出 `0 warn, 0 error`
2. 在 `launcher/web/modules/map/dev/harness.html` 面板点 "Run suite" 全绿（`map-ui1`~`map-ui32`），或跑 `node tools/run-map-harness-headless.js --browser edge`
3. `node tools/audit-map-layout.js` 无几何漂移

地图 manifest 校准入口：`launcher/web/modules/map/dev/preview.html`；可视化构建入口：`launcher/web/modules/map/dev/builder.html`；fallback 期全量复核入口：`node tools/audit-map-layout.js [--page school] [--json]`；filter-fit preset 离线重算入口：`node tools/tune-map-filter-fit.js --write`。`preview` 负责看运行时同构的 Canvas assembled stage（`sceneVisuals` + backdrop/theme + filter/anomaly overlay）、布局、过滤、`buttonRect`、动态头像槽位、locked groups 条件、flash hint、XFL source rect、draft 校准与 override 导出；`builder` 在此基础上开启热点 / 过滤按钮拖拽缩放、bundle 粘贴导入和草稿持久化；两者都不替代 browser harness 的交互 gate。需要给人眼或外部视觉模型看图时，用 `python tools/render-map-audit-sheet.py --page base --page faction --page defense --page school` 生成热点/头像审计图，再按需调用 `powershell -ExecutionPolicy Bypass -File tools/kimi-map-review.ps1 ...` 做视觉复核。
选关界面 Stage Select：`node tools/export-stage-select-manifest.js --summary` 复核 XFL/XML → manifest 数量，`node tools/audit-stage-select-layout.js --json` 复核 16 labels / 182 source entry instances / 164 rendered entry instances / 13 direct `entryKind=map/task` instances / 2 decoration instances / 28 nav buttons / 背景与装饰资源存在 / `previewMissing=0` / `mapDirectLayoutMissing=[]` / `unmappedStageLikeInstances=[]`，`node tools/audit-diplomacy-stage-select-links.js --json` 用 FFDec 全量扫描 `Type=外交地图` 的 `RootFadeTransitionFrame` SWF，并显式列出 StageInfo-only 外交地图（当前 `外交-黑铁阁`，源选关 XFL 无按钮、不按 Web 缺漏处理），确认旧 `关卡地图` 门被 AS2 公共 Web 选关陷阱覆盖、`地图-*` frameLabel 会反查回选关页签，且 return-frame bridge / return-frame isolation / 同场景 return filter 仍存在，`node tools/run-stage-select-harness.js --browser edge` 覆盖 open/close、16 页切换、fixture、runtime 隐藏测试标题/fixture/dev 控件、runtime 地图空间占比、runtime frame menu 展开跳转同步、runtime `localFrame` 单次 `jump_frame` 同步、runtime return nav 使用入口 `returnFrameLabel` 发送 `return_frame` 并关闭、hover preview、真实 snapshot mock、live 关卡简介渲染、Flash HTML 标签清洗、锁定关卡不发 enter、已解锁关卡 enter 成功关闭、外交地图绿色直达/委托任务直达入口 `entryKind` 且无二次难度按钮、9 个外交地图入口的 `shape/外交地图点` 与文字内部矩阵运行时坐标、魔神法阵底图装饰层、challenge 只发地狱、背景矩阵、普通难度按钮锚点与 1024×576 / 1366×768 / 1920×1080 视口。坐标或视觉回归时，先跑 `npm --prefix launcher/perf ci --ignore-scripts`，再跑 `powershell -ExecutionPolicy Bypass -File tools/run-stage-select-visual-audit.ps1`；该工具会用 FFDec 导出 `DefineSprite 330`，裁出 1024×576 原帧，并和无头 Edge 截到的 Web 舞台生成 `tmp/stage-select-visual-audit/sheets/*-compare.png` 与 `visual-audit-index.json`。需要抽查 hover 卡片时可用 `node tools/capture-stage-select-web-frames.js --browser edge --fixture mixed --frame 基地门口 --hover-stage 新手练习场` 生成无头 Edge 单帧截图。接入 `StageSelectTask` / `StageSelectPanelService` 后属于 Web + Launcher Host + AS2 双栈验证，必须补 `launcher/tests/run_tests.ps1` 与 Flash smoke；涉及 `panel_request stage-select`、`source/frameLabel/returnFrameLabel`、`stageSelectJumpFrame`、`stageSelectReturnFrame` 或 `stageSelectPanelClose` 时，launcher xUnit 也必须覆盖协议转换与 close 回调。

URL 参数:`?qa=1` 自动断言 / `?case=` 单条 / `?scenario=` 脚本场景 / `?dump=1` 结构化输出。

若改动后的行为无法被现有 harness 或 QA 覆盖，同轮补测试入口，不把“靠人工记得点开”当作默认收尾。

静态校验拦截:旧平铺 Lockbox 入口、旧版分游戏 session 命令名、旧共享结构 class 名。Jukebox Panel 自动 harness：`launcher/web/modules/jukebox/dev/harness.html`（手动）或 `node tools/run-jukebox-harness.js --browser edge`（无头）。改 `web/modules/jukebox/jukebox-panel.js` / `WebOverlayForm.HandleJukeboxMessage` / `MusicCatalog` / `RightContextWidget` jukebox titlebar 时仍须补跑 [launcher/README.md](../launcher/README.md) "Jukebox panel 手测" 12 步中未被 harness 覆盖的端到端项。
## 5. 自动化与文档治理

| 用途 | 入口 |
|------|------|
| 启动 / 运行链 | [automation/README.md](../automation/README.md) |
| Flash 编译 smoke 细节 | [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md) |
| 离线导弹调优 | `python tools/missile-tuning-sim/run_sim.py compare --configs ...` / `python tools/missile-tuning-sim/run_sim.py scan --objective loiter ...` |
| 文档治理巡检 | `node tools/validate-doc-governance.js` |

巡检脚本检查:必读文件存在、AGENTS.md 关键链接存在、回流模式未重新进入入口、关键文档基线标记存在、关键版本未回退。脚本是巡检器,不是 source of truth。

## 6. 收尾话术参考

- 文档改动:`已更新文档并运行文档治理巡检`
- Minigame:`已跑 Node QA / 静态校验;browser harness 未人工点开`
- Map Panel:`已跑 launcher/build.ps1 / browser harness;未做完整游戏内联调`
- Stage Select Panel:`已跑 manifest 导出 / layout audit / Edge harness / Launcher tests;如触碰 AS2 需说明 Flash smoke 新鲜 trace 状态`
- Launcher:`已跑 build / xUnit;未做完整运行态手点`
- Flash:`已完成 Flash smoke;未在缺少新鲜 trace 或 IDE 复核时声称编译通过`

完整失败模式与重入约束看 [agent-harness.md](agent-harness.md)。
