# CF7:ME Guardian Launcher

C# WinForms 守护进程，承担游戏启动全链：正常模式先做 WebView2 预检，再尽早构造 `GuardianForm`，随后完成 Steam 校验、Flash trust 租约、音频与总线初始化，最后由 BootstrapPanel 的 `list → ready → prewarm → reveal` 链路切入 Flash Player SA 运行态；同时承载 V8 脚本总线、HTTP / XMLSocket 通信和启动前存档决议（Protocol 2）。

> **文档角色**：Guardian Launcher 子系统的 canonical deep doc。项目总览见 [../README.md](../README.md)，顶层任务路由见 [../AGENTS.md](../AGENTS.md)。高变动章节按各自 commit 基线维护。
> **最后核对代码基线**：commit `cc25c357d`（2026-04-30）。
> **新接手阅读顺序**：本节 → [架构概览](#架构概览)（启动时序 + 运行态面板栈）→ [Bootstrap 前端与协议](#bootstrap-前端与协议)（cmd 表 + reveal gate + config_set）→ [存档权威迁移 (Protocol 2)](#存档权威迁移-protocol-2)。其余章节继续展开音频 / 性能调度 / GPU / UI 迁移 / 面板系统等运行时细节。

## 技术栈

| 项目 | 版本/说明 |
|------|-----------|
| 运行时 | .NET Framework 4.6.2, x64 |
| 语言 | C# 5 |
| UI | WinForms (WinExe) 单窗体（GuardianForm）+ WebView2（BootstrapPanel 引导页 + WebOverlayForm 运行态 overlay） |
| 构建 | MSBuild 4.0 + NuGet (packages.config) + MSVC (miniaudio native DLL) + Rust/Cargo (sol_parser cdylib) + Node.js/npm (TypeScript 编译 V8 脚本) |
| 音频 | miniaudio (Unlicense, 单头文件 C 库 → native DLL, WASAPI) |
| 存档解析 | Rust `sol_parser.dll`（flash-lso git pin `4b049ff3`），AMF0 → JSON |
| JS 引擎 | ClearScript 7.4.5 (Chromium V8, 替代 Node.js vm2) |
| Web 覆盖层 | WebView2 1.0.3856.49 (Evergreen Runtime, 幽灵输入解耦架构) |
| JSON | Newtonsoft.Json 13.0.3 |
| 测试框架 | xUnit 2.4.2（legacy packages.config + net462，见 [tests/](#测试基建)） |
| GPU (实验, 当前休眠) | SharpDX 4.2.0 (D3D11, 管线待完善，`gpuSharpening` 配置当前无消费者) |

## 高 DPI 与多显示器支持

Launcher 现在显式声明并初始化 **PerMonitorV2 / PerMonitor DPI-aware**。运行态 WebView2 overlay 的物理视觉尺寸仍跟随 Flash 视口高度，但写入 `WebView2.ZoomFactor` 前会按当前 monitor DPI 归一化，避免 125% / 150% 系统缩放把右侧 HUD 与顶部资源条二次放大；输入命中则由 Web 端 `viewportMetrics`（CSS viewport / DPR / visualViewport）和 C# `OverlayCoordinateContext` 共同换算，不再把 `WebView2.ZoomFactor` 直接当作鼠标坐标比例。

运行态鼠标手型视觉只由 C# `CursorOverlayForm` 原生 layered window 接管，避免 WebView2 特效或 JS 队列影响 cursor 延迟。AS2 侧保留 `_root.鼠标` 纯脚本兼容代理，只承载 `gotoAndStop` / `gotoAndPlay` 状态接口与 `物品图标容器` 拖拽图标容器；几何命中统一走 AS2 `_root._xmouse/_ymouse` 点命中和 `interactionMouseDown` / `interactionMouseUp` 事件，不再让 `_root.鼠标` 作为 `hitTest` 目标。`cursor_control` task 只低频推送状态到 Launcher；`WebOverlayForm` 负责状态调度、低级鼠标 hook 与坐标泵。Web DOM 交互通过 `cursorFeedback` 只回传 hover/press 状态变化，不回传坐标，也不再提供 Web 视觉 fallback；native cursor 不可用时恢复系统鼠标并写入诊断日志。native cursor 贴图采用 `64x64` 源画布、固定热点 `(16,16)` 的资源契约，运行时只按当前 monitor DPI 整体缩放画布与热点，不再为单张贴图维护偏移。物品拖拽图标第一阶段仍留在 AS2 空容器内，仅拖拽期间同步位置，不进入 Flash 每帧 UI 状态管线。

| Windows 兼容性设置 | 支持口径 |
|------------------|----------|
| 不勾选“替代高 DPI 缩放行为” | 正式支持 |
| 勾选后“缩放执行：应用程序” | 正式支持 |
| “系统” / “系统(增强)” | 仅检测并提示；不承诺 Web overlay 像素级交互正确 |

诊断日志以 `[DPI]` 前缀写入 Guardian 日志，包含进程 DPI 初始化结果、AppCompatFlags 原始值、窗口 / monitor DPI、overlay bounds、Web CSS viewport、输入换算比例与 hitRect 样本。若测试员反馈地图、商城、帮助或小游戏点击错位，先核对兼容性值是否为 `DPIUNAWARE` / `GDIDPISCALING`；正式建议是关闭覆盖或改为“应用程序”。

检测到“系统 / 系统(增强)”风险态时会弹出非阻塞提示；用户可勾选“不再提示当前兼容性设置”，Launcher 会把当前 AppCompatFlags raw value 记入 UserPrefs。raw value 变化后仍会再次提示。

引导器默认窗口现在按当前屏幕工作区选择 16:9 client size（目标 1600×900，过小屏幕自动收敛），欢迎页在窄宽 / 低高视口下会压缩侧栏宽度和卡片间距；极端手动缩小时改为垂直滚动兜底，避免启动说明、存档行、右侧版本 / 阵营信息被直接裁掉。字号入口独立放在顶栏“显示”按钮内，用户选择的 1.15 / 1.35 / 1.55 / 1.75 会直接作为启动器字号倍率生效并持久化，不再被小视口偷偷钳制。

## 架构概览

### 单窗体模型

**GuardianForm 是整个 launcher 生命周期的唯一 WinForms 窗体**。启动期和运行态共用同一 Form，原来的 `BootstrapForm` 已在 Phase A 重构中吸收为 `BootstrapPanel`（一个 Control，层级位于 `_flashPanel` 之上）。"启动成功"不再是 Form 切换，而是**面板可见性交换（panel swap）**。

### 启动时序（入口 → Ready → Reveal）

```
Program.Run(args)
   │
   ├─ 解析 `--bus-only` / `--force-webview-fail`，定位 projectRoot
   ├─ 正常模式入口预检 WebView2 Runtime
   │   └─ `CoreWebView2Environment.GetAvailableBrowserVersionString()`
   │   └─ 失败 → MessageBox + return 1（这里只是入口 fail-closed 预检）
   │
   ├─ `bootstrapWebDir = busOnly ? null : launcher/web`
   ├─ `new GuardianForm(bootstrapWebDir)`
   │   ├─ Form 很早就构造；正常模式下 `BootstrapPanel` 此时已挂进 `_flashPanel` 上层
   │   └─ bus-only 模式不创建 `BootstrapPanel`，`_flashPanel` 直接可见
   │
   ├─ `LogManager.InitFileLog` + `AppConfig` + `UserPrefs`
   ├─ `SteamOwnershipCheck.Check(projectRoot)`
   │   ├─ 合法 git 开发仓库 → 跳过所有权校验（fail-open for dev）
   │   └─ 发行环境失败 → MessageBox + return 1
   ├─ `FlashTrustManager.EnsureTrust(projectRoot)`
   │   ├─ 以 `cf7me.cfg` 为租约文件，尝试用户级 / SysWOW64 / System32 三处 trust 目录
   │   └─ 全部失败只记 WARNING；退出统一 `RevokeTrust()`
   ├─ 正常模式额外校验 `flashPlayerPath` / `swfPath`
   ├─ `AudioEngine.Init` + `MusicCatalog`
   ├─ `PortAllocator` → `XmlSocketServer.Start` + `HttpApiServer.Start`
   ├─ `ToastOverlay` / `NotchOverlay`（两者均仅 `useNativeHud=false`） / `V8Runtime` / `FrameTask`
   ├─ 再次获取 WebView2 Runtime 版本，构造 `WebOverlayForm` + `InputShieldForm`
   ├─ `TaskRegistry.RegisterAll(...)` + 写 `launcher_ports.json`
   │
   ├─ bus-only 分支：
   │   └─ `Application.Run(form)`，等待外部 Flash/Flash CS6 自行连总线
   │
   └─ 正常模式：
       ├─ 可选拉起 `hotkey_guard.exe`
       ├─ 构造 `WindowManager` / `ProcessManager` / `SaveResolutionContext` / `GameLaunchFlow`
       ├─ `BootstrapPanel` 在控件 `Load` 事件里异步初始化 WebView2
       ├─ `bootstrap-main.js` 初始化顺序：
       │    1. `send({cmd:'list'})`
       │    2. 双 `requestAnimationFrame`
       │    3. `send({cmd:'ready'})`
       ├─ `ready` → `LifecycleCommandHandler.HandleReady()` → `GameLaunchFlow.Prewarm()`
       │    └─ 冷启动 silent prewarm：`Idle → Spawning → WaitingConnect → WaitingHandshake`
       │       握手先到且 `_pendingSlot == null` → `PrewarmHandshakeHeld`
       │       `bootstrap_handshake` 响应被挂起，等待用户真正选槽
       ├─ `start_game` / `rebuild` 消费槽位：
       │    ├─ `PrewarmHandshakeHeld` → flush held handshake → `Embedding → WaitingGameReady → Ready`
       │    ├─ `WaitingConnect/WaitingHandshake` → 只记录 `_pendingSlot`，待握手后走快路径
       │    └─ `Idle`（未 prewarm 或已 Reset）→ 走冷启路径
       └─ `Ready` 后 reveal gate：
            ├─ `deferReveal:true` 等 JS 发 `reveal_ok`
            ├─ `requireFlashReveal:true` 等 Flash 发 `bootstrap_reveal_ready`
            │   清 `_revealWaitingFlash` 的瞬间就先推 `{cmd:'flash_ready'}`
            └─ 两个 flag 都清空 → `DoPerformReveal()`
                ① `readyWiring`（toast/web/inputShield/notch.SetReady）
                ② `BootstrapPanel.SetPanelVisible(false)`
                ③ `FlashHostPanel.Visible = true`
                ④ `form.ShowTrayIcon()`
```

**失败分支**（仍在 BootstrapPanel 可见时出错）：
- Prewarm 阶段 Flash 异常退出 / socket 断连 → `TransitionToError("flash_exited")` / 相关 reason
- 用户在 Error 态发 `retry` → 锁内快照 `_pendingSlot` → 锁外 `Reset(onIdle: StartGame(slot))`，重置到 Idle 后立即重拉（不停在 Idle 等点击）
- 用户主动 `cancel_launch`：任何非 Idle 状态 → `Reset(null, "user_cancel")` → 回 Idle；silent prewarm 被打断也走这条

**Ready 之后失败**：Flash 进程退出 / zombie 兜底 → `GuardianForm.ForceExit()` → **整个 Launcher 退出**。Ready 后想"换槽位"必须重启 launcher。

### 运行态面板栈（Ready 之后）

```
┌──────────────────────────────────────────────────────────┐
│  GuardianForm (单 WinForms 窗体, 全生命周期共用)            │
│  ┌────────────────────────────────────────────────┐      │
│  │ BootstrapPanel (WebView2, z-order 最高)         │      │
│  │   初始显示，reveal 时 SetPanelVisible(false)     │      │
│  │   承载 launcher/web/bootstrap.html              │      │
│  ├────────────────────────────────────────────────┤      │
│  │ _flashPanel (D3DPanel, Dock=Fill)              │      │
│  │   reveal 时 Visible=true                        │      │
│  │   └─ Flash Player SA (Win32 SetParent 嵌入)     │      │
│  ├────────────────────────────────────────────────┤      │
│  │ _gpuCaptureStrip (Dock=Right, 实验性 GPU 截取区) │      │
│  │ _logBar (Dock=Bottom, 折叠式日志+搜索)           │      │
│  └────────────────────────────────────────────────┘      │
│  TrayIcon (托盘图标)                                      │
└────┬─────────────────────────────────┬───────────────────┘
     │                                 │
┌────┴────┐                      ┌─────┴──────┐
│XMLSocket│                      │  HTTP API  │
│TCP :port│                      │  :port     │
│\0-delim │                      │  REST/JSON │
└────┬────┘                      └─────┬──────┘
     │                                 │
     ├─ 入站快车道 (AS2 → C#, 前缀协议) ───────────────┐
     │  'F' → FrameTask.HandleRaw(...)                 │
     │       payload: F{cam}\x01{hn}[\x02{fps}]        │
     │                [\x03{uiState}][\x04{inputPayload}] │
     │       uiState 透传 overlay/bench（含 mm/mh 地图 HUD） │
     │       inputPayload 喂 DFA                             │
     │  'R' → FrameTask.HandleReset()           │
     │  'S' → AudioTask.HandleSfxFastLane()     │
     │  'B' → Bench echo（AS2 冒烟，回 K 前缀）    │
     │  'N' → INotchSink.AddNotice(通知)        │
     │  'W' → INotchSink.SetStatusItem(波次)    │
     │  'U' → WebView2 UiData 透传              │
     │  'D' → FrameTask.LoadInputModule(DFA)    │
     │  (绕过 JSON 解析，零 GC 分配)              │
     ├─ 出站快车道 (C# → AS2) ───────────────────┤
     │  'P' → AS2 applyFromLauncher(tier,softU) │
     │  (PerfDecisionEngine 决策推送)             │
     └──────────────────────────────────────────┘
     │
┌────┴──────────────────────────────┐
│    MessageRouter (JSON 路由)      │
│  Sync: toast / audio / icon_bake  │
│        frame / hn_reset           │
│        bootstrap_ready /          │
│        bootstrap_reveal_ready     │
│        bench_sync / bench_push(*) │
│  Async: gomoku_eval / data_query  │
│         shop_response / archive   │
│         bootstrap_handshake       │
│           (prewarm held callback) │
│         bench_async(*)            │
│  (*) benchTask != null 时才注册    │
└─────────────┬─────────────────────┘
              │
┌─────────────┴─────────────────────┐
│  AudioEngine (C# P/Invoke)        │
│  ┌─────────────────────────────┐  │
│  │  miniaudio.dll (native C)   │  │
│  │  WASAPI shared mode         │  │
│  │  BGM: dual-instance xfade   │  │
│  │  SFX: preload + 90ms dedup  │  │
│  └─────────────────────────────┘  │
│  sol_parser.dll (Rust cdylib)     │
│  AMF0 → JSON, 0-based refs        │
└───────────────────────────────────┘

 热键四层防御：
 ① SetMenu(NULL)                   移除 Flash 原生菜单加速器
 ② hotkey_guard.exe                独立子进程，WH_KEYBOARD_LL，前台感知
 ③ KeyboardHook (进程内低级钩子)     ESC 路由 + Ctrl+F/Q 兜底
 ④ RegisterHotKey (fallback)       钩子安装失败时退化为系统热键

 ┌─────────────────────────────────────────┐
 │  幽灵输入解耦 (Ghost Input Decoupled)     │
 │  InputShieldForm                        │
 │  (GDI+ α=1 命中区拦截 → CDP 注入)        │
 │         ↓ CDP Input.dispatchMouseEvent  │
 │  WebOverlayForm                         │
 │  (WS_EX_TRANSPARENT, WebView2 渲染)      │
 │         ↓ 穿透                           │
 │  Flash HWND (WS_CHILD)                  │
 └─────────────────────────────────────────┘
```

## 延迟基线（2026-04）

基于 Flash CS6 `TestLoader` 与 `CRAZYFLASHER7MercenaryEmpire.exe --bus-only` 的多轮实测，当前可先把 Guardian Launcher 的延迟结论理解为"启动建连慢，稳定态传输快，长尾主要在 Flash/业务侧"。这里保留概要，完整样本、脚本和排查过程见 [`../docs/protocol-latency-baseline.md`](../docs/protocol-latency-baseline.md)。

- **启动建连**：`ServerManager` 从读取 `launcher_ports.json` 到 XMLSocket 连通，当前基线约 `2.1s - 2.4s`；主耗时在 XMLSocket 建连/策略握手，不在 HTTP 探测。
- **Launcher 自身传输**：`raw_b_k`、`frame_ui_k`、`json_sync/json_async/json_push_cmd` 的 C# 处理段实测为微秒级，说明 launcher 不是主要延迟源。
- **稳定态快车道**：`XMLSocket` fast-lane、`FrameBroadcaster.send()`、`cmd` 回推在即时打点下通常为低毫秒；之前看起来接近 `1 帧` 的结果，主要来自 Flash 侧回调时机与旧版采样方法。
- **HTTP / LoadVars**：`/testConnection`、`/getSocketPort`、`/logBatch` 在 AS2 侧仍会表现出接近帧级的回调抖动；这是 AVM1/`LoadVars` 的特点，不代表 launcher 的 HTTP 处理本身变慢。
- **业务重路径**：`archive_load`、`merc_bundle`、`npc_dialogue` 的长尾更多由数据加载、缓存填充和序列化决定，不是总线 transport 本身。

复测入口：

- [`../scripts/protocol_latency_cycle.ps1`](../scripts/protocol_latency_cycle.ps1)：单轮基线
- [`../scripts/protocol_latency_sweep.ps1`](../scripts/protocol_latency_sweep.ps1)：多轮抖动/尾延迟统计

## 目录结构

按 commit `cc25c357d`（2026-04-30）时的源码树复核。只列追踪目录；`bin/` / `packages/` / `target/` / `node_modules/` / `obj/` 等构建产物和缓存均由 .gitignore 管理。后续若需复核本节，优先看 `git diff cc25c357d..HEAD -- launcher/`。C# 文件级权威以 [CRAZYFLASHER7MercenaryEmpire.csproj](CRAZYFLASHER7MercenaryEmpire.csproj) / [tests/Launcher.Tests.csproj](tests/Launcher.Tests.csproj) 的 `Compile Include` 为准，README 仅保留职责树。

```
launcher/
├── CRAZYFLASHER7MercenaryEmpire.csproj   C# 项目文件
├── packages.config                        NuGet 包清单
├── build.ps1                              总构建脚本（NuGet/TS/native/Rust/MSBuild/资产 gate，见下文）
├── setup-check.ps1                        构建/运行前依赖自检（Targeting Pack / MSBuild / nuget / WebView2）
├── app.manifest                           DPI awareness / Windows 兼容声明
├── app.ico                                应用图标
│
├── data/
│   ├── save_schema.json                   存档编辑器 diff/默认值基线
│   ├── save_repair_dict.json              存档自动修复字典
│   └── map_hud_data.json                  Native HUD 小地图 catalog（build.ps1 会 fail-fast 校验）
│
├── src/
│   ├── Program.cs                         入口：正常模式先做 WebView2 预检，再尽早构造 GuardianForm；随后初始化 Steam/Trust/总线并接 GameLaunchFlow
│   │
│   ├── Config/
│   │   ├── AppConfig.cs                   config.toml 解析（Flash/SWF 路径、GPU/overlay/native HUD 诊断开关）
│   │   ├── GpuPreferenceManager.cs        HKCU UserGpuPreferences 写入/退出清理
│   │   ├── UserPrefs.cs                   用户级偏好持久化（优先 LocalAppData，不可用时回退项目根）
│   │   ├── SteamOwnershipCheck.cs         Steam 进程 + SteamAPI AppID 正版校验（开发仓库 fail-open，发行环境 fail-closed）
│   │   └── FlashTrustManager.cs           `cf7me.cfg` trust 租约（用户级/系统级多目录尝试，退出按租约清理）
│   │
│   ├── Guardian/
│   │   ├── GuardianForm.cs                单窗体主壳（_flashPanel + BootstrapPanel + _logBar + TrayIcon，全生命周期共用）
│   │   ├── BootstrapPanel.cs              启动引导面板（WebView2 Control，在 `Load` 里初始化并承载 bootstrap.html）
│   │   ├── BootstrapMessageHandler.cs     薄 dispatcher（~120 行 switch），按 cmd 分派到 Handlers/ 下
│   │   ├── GameLaunchFlow.cs              状态机：Idle → Prewarm/Spawning → ... → Ready → Reveal
│   │   │                                    含 Prewarm + PrewarmDeadline + RevealGate（JS/Flash 双 flag）
│   │   ├── GuardianContext.cs             ApplicationContext 外壳（MainForm=GuardianForm）
│   │   ├── FlashHtmlParser.cs             AS2 HTML 子集转纯文本/白名单结构
│   │   ├── WindowManager.cs               Win32 SetParent 嵌入 + 500ms 脱离看门狗
│   │   ├── ProcessManager.cs              Flash SA 进程生命周期 + 僵尸兜底
│   │   ├── LogManager.cs                  线程安全日志 → TextBox + 文件通道（logs/launcher.log）+ 测试 sink hook
│   │   ├── OverlayBase.cs                 GDI+ Layered Window 覆盖层基类
│   │   ├── ToastOverlay.cs                GDI+ toast 消息（独立 ULW；仅 useNativeHud=false fallback；useNativeHud=true 由 Hud/ToastWidget 在 NativeHudOverlay 内承载）
│   │   ├── NotchOverlay.cs                GDI+ 刘海栏（独立 ULW，仅 useNativeHud=false fallback；useNativeHud=true 由 Hud/NotchWidget 在 NativeHudOverlay 内承载）
│   │   ├── HitNumberOverlay.cs            GDI+ 伤害数字
│   │   ├── CursorOverlayForm.cs           原生 cursor 视觉层（Layered Window，高频低延迟）
│   │   ├── WebOverlayForm.cs              WebView2 视觉层（WS_EX_TRANSPARENT）
│   │   ├── InputShieldForm.cs             幽灵输入层（GDI+ α 命中 + CDP 注入）
│   │   ├── NativeHudOverlay.cs            C# Native HUD 容器（按 widget union 动态 bounds）
│   │   ├── NativePanelBackdrop.cs         panel 打开期 Flash snapshot 背景层
│   │   ├── PanelHostController.cs         panel 打开/关闭队列：snapshot/backdrop/EX_STYLE/HUD suspend
│   │   ├── LauncherCommandRouter.cs       按钮命令与 panel 打开的唯一中枢
│   │   ├── PanelLayoutCatalog.cs          panel 尺寸/锚点计算
│   │   ├── IToastSink.cs / INotchSink.cs  Toast / Notch 抽象接口
│   │   ├── FlashCoordinateMapper.cs       Flash 舞台坐标 ↔ 屏幕坐标
│   │   ├── FpsRingBuffer.cs               FPS 环形缓冲 + 场景重置
│   │   ├── PerfDecisionEngine.cs          性能决策（滑动窗口 + 迟滞，替代 AS2 Kalman/PID）
│   │   ├── HotkeyGuard.cs                 独立进程源码（csc 单独编译为 hotkey_guard.exe）
│   │   ├── KeyboardHook.cs                进程内 WH_KEYBOARD_LL（ESC 路由 + Ctrl+F 兜底；失败 fallback RegisterHotKey）
│   │   │
│   │   ├── Hud/                           Native HUD widget 与解析工具
│   │   │   ├── RightContextWidget.cs       右侧 5 键 + 小地图卡片 + 装备/任务行 + jukebox titlebar
│   │   │   ├── SafeExitPanelWidget.cs      安全退出二次确认
│   │   │   ├── ComboWidget.cs              搓招输入态与命中通知
│   │   │   ├── ToastWidget.cs              toast 消息（useNativeHud=true 时承载，复刻 ToastOverlay 视觉，alpha 在 segment 颜色内做）
│   │   │   ├── NotchWidget.cs              刘海栏（useNativeHud=true 时承载，FPS 药丸 + 工具栏 + 通知栈 + 展开图表 + currency/clock）
│   │   │   ├── MapHudWidget.cs             小地图 shared renderer / blocks fallback
│   │   │   └── WidgetScaler.cs / UiDataPacketParser.cs / MapHudDataCatalog.cs 等支撑类
│   │   │
│   │   └── Handlers/                      【BootstrapMessageHandler 拆分后的 cmd handler 集】
│   │       ├── BootstrapCommandHelpers.cs  共享工具：PostResp / PostError / DispatchArchive / RequireIdleOrTearDown 等
│   │       ├── LifecycleCommandHandler.cs  ready / ping / cancel_launch
│   │       ├── GameStateCommandHandler.cs  start_game / rebuild / reveal_ok / retry
│   │       ├── ArchiveCommandHandler.cs    list / delete / load / load_raw
│   │       ├── DataEditCommandHandler.cs   save / reset / export（共享 RequireIdleOrTearDown 守卫）
│   │       ├── ImportCommandHandler.cs     import_start / import_commit
│   │       ├── UiCommandHandler.cs         logs / open_saves_dir
│   │       ├── ConfigCommandHandler.cs     config_set（Plan A+：currentValue 权威下发 + requestId 相关 id）
│   │       └── RepairCommandHandler.cs     C2-β 存档修复检测 / 手动应用 / 强制继续
│   │
│   ├── Bus/
│   │   ├── XmlSocketServer.cs             TCP 服务器（8 入站前缀 + 1 出站前缀 + JSON 双通道）
│   │   ├── HttpApiServer.cs               HTTP REST（11 个 path，详见 HTTP API 节）
│   │   ├── MessageRouter.cs               JSON task 路由：RegisterSync / RegisterAsync
│   │   ├── TaskRegistry.cs                Task 注册表 — single source of truth
│   │   ├── PortAllocator.cs               种子 "1192433993" 确定性端口分配
│   │   ├── FlashPolicyHandler.cs          Flash 跨域策略（crossdomain.xml）
│   │   └── BenchTrace.cs                  性能基准追踪（条件编译）
│   │
│   ├── Save/                              【启动前存档决议链 — Protocol 2】
│   │   ├── SolResolver.cs                 决议矩阵入口：tombstone → shadow → SOL → 版本分流；`source=sol` 时同步首导入 authority
│   │   ├── SolParserNative.cs             sol_parser.dll P/Invoke 封装
│   │   ├── NativeSolParser.cs             `ISolParser` 默认实现
│   │   ├── SolFileLocator.cs              SOL 路径定位（仅当前运行根；`.swf/.exe` 双兼容 + root-scoped fallback）
│   │   ├── SaveMigrator.cs                2.7→3.0 迁移（含 legacy `mydata[3]` 缺失补 0）+ MergeTopLevelKeys + ValidateResolvedSnapshot
│   │   ├── LegacyPresetSlotSeeder.cs      标准 10 槽 authority 预热：`list/load/load_raw` 前探测 legacy SOL 并补种 shadow
│   │   ├── SaveAutoRepairService.cs       启动期 silent 自动修复高置信度存档问题
│   │   ├── RepairPolicy.cs / RepairDictionary.cs / RepairMatcher.cs / RepairBackupStore.cs
│   │   ├── SaveCorruptionScanner.cs / SaveFieldLayering.cs / LauncherVersionGate.cs
│   │   ├── ISolParser.cs / ISolFileLocator.cs / IArchiveStateProbe.cs / IArchiveShadowWriter.cs
│   │   └── SaveResolutionContext.cs       DI 聚合（resolver + archive + swfPath + legacy seeder）
│   │
│   ├── Diagnostic/
│   │   └── DiagnosticPackager.cs          bootstrap/HTTP 诊断包导出
│   │
│   ├── Audio/
│   │   ├── AudioEngine.cs                 miniaudio P/Invoke（play/stop/seek/peak）
│   │   └── MusicCatalog.cs                BGM 目录：XML 解析 + 文件系统扫描 + 热加载
│   │
│   ├── Data/                              【NPC/佣兵数据迁移，Mar 2026】
│   │   ├── DataCache.cs                   XML 数据热缓存
│   │   └── XmlDataLoader.cs               启动时异步预载，data_query task 消费
│   │
│   ├── Services/
│   │   └── DirectoryWatcherService.cs     通用文件监听（500ms 去抖 + 增量回调）
│   │
│   ├── Tasks/
│   │   ├── AudioTask.cs                   BGM JSON handler + SFX 快车道
│   │   ├── FrameTask.cs                   帧数据（F/R 快车道 + JSON 后备 + 搓招 D 前缀）
│   │   ├── GomokuTask.cs                  五子棋 AI（外部 rapfi 引擎）
│   │   ├── DataQueryTask.cs               NPC/佣兵数据查询（Data/ 支撑）
│   │   ├── ToastTask.cs                   UI toast 通知（fire-and-forget）
│   │   ├── ShopTask.cs                    K 点商城双层 callId 桥接（10s 超时）
│   │   ├── MapTask.cs                     Web 地图 panel snapshot / refresh / navigate
│   │   ├── StageSelectTask.cs             Web 选关 panel snapshot / enter
│   │   ├── ArchiveTask.cs                 存档 shadow 读写 + editor/import + 启动期候选快照
│   │   ├── IconBakeTask.cs                物品图标批量烘焙（begin/chunk/end 协议）
│   │   └── BenchTask.cs                   性能基准 task（条件编译）
│   │
│   ├── V8/
│   │   └── V8Runtime.cs                   ClearScript V8 运行时（伤害数字 + 搓招 DFA）
│   │
│   └── Render/                            GPU 锐化（实验性，当前休眠：配置字段无消费者）
│       ├── GpuRenderer.cs                 D3D11 off-screen CAS 处理
│       ├── CasShaderBytecode.cs           HLSL CAS 着色器
│       ├── D3DPanel.cs                    双缓冲显示面板
│       └── RenderNativeMethods.cs         PrintWindow/BitBlt P/Invoke
│
├── native/
│   ├── miniaudio.h                        miniaudio 单头文件库（Unlicense）
│   ├── miniaudio_bridge.c                 C 导出层（BGM crossfade/seek/pause/looping, SFX preload, peak）
│   ├── build.bat                          MSVC vcvars64 探测 + cl.exe 编译
│   └── sol_parser/                        【Rust cdylib：AMF0 → JSON】
│       ├── Cargo.toml                     flash-lso git pin 4b049ff3 + serde_json
│       ├── Cargo.lock                     ✅ 已入库：锁定依赖版本集，消除浮动解析
│       ├── build.bat                      cargo build --release + 落盘到 bin/Release
│       ├── src/lib.rs                     FFI (sol_parse_file / sol_free) + Ctx DFS 索引 + 0-based Reference 解析
│       ├── tests/reference_semantics.rs   AMF0 Reference round-trip 测试
│       └── examples/
│           ├── oracle.rs                  Layer 1 结构断言 + JSON dump
│           └── dumpidx.rs                 by_index 调试转储
│
├── scripts/                               【TypeScript 源 + dist (V8 嵌入脚本)】
│   ├── package.json / package-lock.json   npm 依赖（typescript）
│   ├── tsconfig.json
│   ├── src/                               animation.ts / camera.ts / command-dfa.ts /
│   │                                       input-{event,processor,sampler}.ts / parser.ts /
│   │                                       pool.ts / trie-dfa.ts / types.ts
│   └── dist/                              tsc 产出，V8Runtime.cs 加载
│
├── web/                                   【WebView2 前端资源】
│   ├── bootstrap.html                     启动引导 UI 入口（topbar + view-welcome + view-slots + intro overlay）
│   ├── bootstrap-main.js                  启动引导主控 IIFE（状态机前端、reveal 触发、sendConfigSet、字号/音频偏好、片头视频）
│   ├── overlay.html                       运行态 DOM（Toast/Notch/工具条/Panel/Tooltip）
│   ├── config/
│   │   └── version.js                     版本号/CHANNEL 唯一配置点（e 常数思路：2.71 → 2.718 → 2.7182 … 稳定版跳出 e）
│   ├── css/
│   │   ├── bootstrap.css                  引导页基础样式 + :root 字号/letter-spacing/几何缩放变量（--fs-scale / --ls-scale / --geom-scale）
│   │   ├── welcome.css                    欢迎页样式（Cyberpunk 卡片 + 阵营侧栏 + 字号预设按钮）
│   │   ├── overlay.css                    Notch/Toast/Jukebox 等样式 + 动效
│   │   └── panels.css                     面板系统样式（Cyberpunk 2077 风格）
│   ├── assets/                            引导页 / cursor / map / stage-select 图片与媒体
│   │   ├── bg/                            背景图层资源
│   │   ├── cursor/native/                 C# CursorOverlayForm 贴图契约（64x64, hotspot 16,16）
│   │   ├── map/                           地图 panel/HUD 页面图
│   │   ├── stage-select/                  选关背景与 hover 预览
│   │   ├── logos/                         标题 / Steam 等品牌图标
│   │   └── intro.mp4                      片头视频（deferReveal 路径播放期）
│   ├── lib/
│   │   └── marked.min.js                  Markdown→HTML 渲染器（MIT）
│   ├── icons/                             物品图标资源（manifest.json + *.png）
│   ├── help/                              游戏帮助 Markdown（controls/worldview/easter-eggs.md）
│   ├── data/
│   │   └── lockbox-variants.json          开锁小游戏数据
│   └── modules/
│       ├── audio.js                       Web Audio 合成的 UI 音效（BootstrapAudio：hover/click/confirm/error + ambient hum）
│       ├── about.js                       "其他" 弹窗 + DISPLAY 字号预设按钮 + AUDIO 复选框（走 config_set 协议）
│       ├── factions.js                    welcome 页阵营列表渲染
│       ├── archive-schema.js              存档 schema 描述/校验
│       ├── archive-editor.js              存档编辑器（welcome/slots 视图的模态）
│       ├── diagnostic-log.js              BootstrapPanel 日志查看器
│       ├── bridge.js                      C# ↔ JS 消息桥（overlay 侧）
│       ├── uidata.js                      帧同步 UI 状态分发（KV 格式）
│       ├── toast.js                       Toast 消息（Flash HTML 白名单）
│       ├── sparkline.js                   FPS 折线图（DPR 感知）
│       ├── notch.js                       Notch UI（FPS/clock/工具条/通知）
│       ├── currency.js                    经济面板动画
│       ├── combo.js                       搓招连击飞出动效
│       ├── jukebox.js                     旧 BGM 点歌器入口（脚本入口已注释；展开 UI 已迁 panels/jukebox-panel.js）
│       ├── panels.js                      通用面板生命周期（register/open/close/ESC）
│       ├── panels/
│       │   └── jukebox-panel.js           BGM 点歌器（Panels.register('jukebox')；展开后内容由此承载）
│       ├── tooltip.js                     Tooltip（hover/anchored）
│       ├── icons.js                       图标 manifest 加载与解析
│       ├── kshop.js                       K 点商城面板（ShopTask 双层 callId）
│       ├── help.js / help-panel.js        帮助系统（顶层入口 + 面板骨架）
│       ├── map-panel.js / map-panel-data.js / map-fit-presets.js / map-hud.js 地图系统（正式 map panel + 静态页面/热点数据 + filter fit preset 表 + 右上角常驻 HUD）
│       ├── stage-select-data.js / stage-select-panel.js 选关界面 Stage 2 runtime panel（Panels.register('stage-select')）
│       ├── intelligence-panel.js          情报详情 Web 面板（Panels.register('intelligence')；runtime 状态由 AS2 提供，正文由 C# IntelligenceTask 按需读取）
│       ├── map/
│       │   └── dev/
│       │       ├── harness.html           地图 panel browser harness + QA suite
│       │       ├── builder.html           地图可视化构建器入口（跳转到 builder 模式 preview）
│       │       └── preview.html           地图 manifest 预览 / 校准页
│       ├── stage-select/
│       │   └── dev/
│       │       └── harness.html           选关界面 browser harness + QA suite
│       ├── intelligence/
│       │   └── dev/
│       │       └── harness.html           情报详情 panel browser harness + QA suite
│       └── minigames/
│           ├── shared/                    小游戏共享层（host-bridge + minigame-shell + shared/dev QA 基础层）
│           ├── lockbox/                   开锁小游戏（core/dev + lockbox-audio/panel/css/README）
│           ├── pinalign/                  定位小游戏（core/adapter/app/dev/reference + audio/panel/css/README）
│           └── gobang/                    五子棋小游戏（core/dev + panel/css/README，AI 走 GomokuTask/Rapfi）
│
├── tests/                                 【xUnit 2.4.2 C# 单测，见测试基建节】
│   ├── Launcher.Tests.csproj              legacy csproj + packages.config（net462 对齐主工程；45 个测试源码入口）
│   ├── packages.config                    xunit / xunit.runner.console / xunit.runner.visualstudio
│   ├── run_tests.ps1                      双段 nuget restore + msbuild + xunit.console
│   ├── SanityTests.cs                     基建冒烟
│   ├── Bus/ / Tasks/ / Save/              总线、task、Protocol 2、修复策略与自动修复
│   ├── Guardian/                          DPI/坐标/panel/native HUD/widget 相关单测
│   └── Fixtures/MapHud/                   Native Map HUD payload fixtures
│
├── perf/                                  WebView2 overlay / panel 性能 harness、场景、ablation 与报告工具
│
├── docs/
│   └── phase1-owner-matrix.md             （Phase 1 所有权/职责矩阵归档）
│
└── tools/
    ├── lockbox-bake.js                    Lockbox 变体池离线生成工具（写入 web/data/lockbox-variants.json）
    ├── run-minigame-qa.js                 小游戏 Node QA 入口（lockbox / pinalign / gobang / all）
    ├── validate-minigame-final-state.js   小游戏最终态静态校验（旧路径 / 旧协议 / 旧共享类名）
    └── nuget.exe                          NuGet CLI
```

## 在 VS Code 中构建

### 前置条件

- **Windows 10/11，x64**
- **.NET Framework 4.6.2 目标包**（系统自带 4.6.2+ 运行时）
- **MSBuild**：`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\msbuild.exe`（系统自带）
- **MSVC C 编译器**（cl.exe，用于编 miniaudio.dll）：VS 2022 Build Tools 或任意 VS 版本
  - 安装：`winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"`
  - native/build.bat 自动探测 vcvars64.bat
- **Rust 工具链**（用于编 sol_parser.dll）：`rustup-init.exe` → stable-x86_64-pc-windows-msvc
  - 安装：https://rustup.rs/
  - native/sol_parser/build.bat 要求 `cargo` 在 PATH 里
  - 首次构建 cargo 需联网拉 flash-lso（git pin）及其传递依赖。Cargo.lock 只锁版本集，**不等价于离线可复现**——能否在新机器离线构建取决于本机 `~/.cargo/registry/cache` 和 `~/.cargo/git/checkouts/` 是否已有对应依赖（或是否做过 `cargo vendor`）
- **Node.js + npm**（用于编 V8 的 TypeScript 脚本）：Node 18+（LTS 均可）
  - 安装：`winget install OpenJS.NodeJS.LTS`
  - build.ps1 会在 `launcher/scripts/` 下跑 `npm install` + `npx tsc`
- **终端**：PowerShell 或 Git Bash 都行
- **推荐先跑环境自检**：`powershell -File setup-check.ps1`
  - 当前脚本只检查 4 项硬依赖：`.NET Framework 4.6.2 Targeting Pack`、`MSBuild`、`launcher/tools/nuget.exe`、`WebView2 Runtime`

### 一键构建

```powershell
cd launcher
powershell -File setup-check.ps1
powershell -File build.ps1
```

### build.ps1 实际执行链

脚本代码里的阶段编号是"历史叠加式"（原始 4 步之上 insert 1.5/1.8/1.9/3.5，后又扩到 6/6a/6b），文字头写的 `[Step N/4]`、`[Step N/6]` 并非分母变化，而是遗留。**实际执行动作如下**：

| 阶段 | 动作 |
|------|------|
| 1    | `nuget restore` — 恢复 NuGet 包 (ClearScript / Newtonsoft.Json / SharpDX / WebView2) |
| 1.5  | TypeScript 编译 — `cd scripts`，若 `node_modules/` 缺失则 `npm install --ignore-scripts`，再 `npx tsc --project tsconfig.json` → `scripts/dist/*.js` 供 V8Runtime 加载 |
| 1.8  | `native/build.bat` — 编 miniaudio_bridge.c → `bin/Release/miniaudio.dll`（自动 vcvars64） |
| 1.9  | `native/sol_parser/build.bat` — `cargo build --release` → `bin/Release/sol_parser.dll`（硬依赖，缺失直接 exit 1） |
| 2    | `msbuild CRAZYFLASHER7MercenaryEmpire.csproj /p:Configuration=Release` — 编 C# |
| 3    | 复制 managed 产物（exe + DLLs + miniaudio.dll + sol_parser.dll）到项目根（逐文件 Copy，找不到仅 WARN） |
| 3.5  | 硬断言 `sol_parser.dll` 已落盘到项目根（防止"编过但运行时 DllNotFoundException"） |
| 4    | 复制 V8 原生 DLL（ClearScriptV8.win-x64.dll）到项目根 |
| 5    | 复制 WebView2 原生 loader（WebView2Loader.dll）到项目根 |
| 6    | fail-fast 校验 `launcher/web` 运行时必需集：`bootstrap.html` / `bootstrap-main.js` / `overlay.html` / `config/version.js` / `assets/bg/manifest.json` / `assets/cursor/native/*` / `assets/intro.mp4` / `assets/map/*` / `assets/stage-select/*` / `help/*.md` / `icons/manifest.json` / `data/lockbox-variants.json` / 关键 `modules/*`（含 `intelligence-panel.js`）与 minigame 入口文件 |
| 6a   | 运行 `node tools/audit-native-cursor-assets.js` 校验 native cursor `64x64` 画布与 `(16,16)` 热点契约，缺失或不合规直接 exit 1 |
| 6b   | fail-fast 校验 `launcher/data/map_hud_data.json` 与 `launcher/data/save_schema.json`；缺失时分别提示 `node tools/export-maphud-data.js` / `node tools/extract-save-schema.js` |

> build.ps1 **不跑** `launcher/tests/`；测试走独立 `launcher/tests/run_tests.ps1`，见[测试基建](#测试基建)节。

### 产物（部署到项目根目录）

| 文件 | 说明 |
|------|------|
| `CRAZYFLASHER7MercenaryEmpire.exe` | Guardian 主程序 |
| `miniaudio.dll` | 原生音频引擎（WASAPI） |
| `sol_parser.dll` | Rust AMF0 → JSON 解析器（Protocol 2 存档决议用） |
| `ClearScript.Core.dll` | V8 引擎核心 |
| `ClearScript.V8.dll` | V8 managed 封装 |
| `ClearScript.V8.ICUData.dll` | V8 国际化数据（~10MB） |
| `ClearScriptV8.win-x64.dll` | V8 原生引擎（~22MB） |
| `Newtonsoft.Json.dll` | JSON 库 |
| `SharpDX.dll` / `SharpDX.DXGI.dll` / `SharpDX.Direct3D11.dll` / `SharpDX.D3DCompiler.dll` | DirectX 封装（当前 GPU 锐化休眠，保留依赖） |
| `Microsoft.Web.WebView2.Core.dll` | WebView2 托管核心 |
| `Microsoft.Web.WebView2.WinForms.dll` | WebView2 WinForms 控件 |
| `WebView2Loader.dll` | WebView2 原生加载器 |

此外项目根的 `hotkey_guard.exe` 是独立子进程（见下文），需**手动编译**——build.ps1 当前不自动构建它。

### 单独编译 HotkeyGuard

HotkeyGuard 是独立 WinExe（不走主 csproj）：

```powershell
cd launcher/src/Guardian
csc /target:winexe /out:../../../hotkey_guard.exe HotkeyGuard.cs
```

Launcher 启动时 `Program.cs` 尝试 `Process.Start("hotkey_guard.exe")`；若文件不存在，日志打印 `HotkeyGuard.exe not found, shortcuts not blocked` 并继续运行（该层防御降级，仍有 SetMenu/KeyboardHook 两层兜底）。

### VS Code 任务配置（可选）

在项目根目录创建 `.vscode/tasks.json`：

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build Guardian",
      "type": "shell",
      "command": "powershell -File launcher/build.ps1",
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": "$msCompile"
    }
  ]
}
```

配置后按 `Ctrl+Shift+B` 即可构建。

## 测试基建

`launcher/tests/` 是独立 xUnit 2.4.2 测试工程（legacy csproj + packages.config + net462），与主工程解耦。

### 跑测试

```powershell
cd launcher/tests
powershell -File run_tests.ps1
```

脚本做法：
1. `nuget restore ../packages.config -PackagesDirectory ../packages`（主工程 HintPath 依赖，ProjectReference 要求）
2. `nuget restore packages.config -PackagesDirectory ../packages`（测试包合并到同一 packages 目录）
3. `msbuild Launcher.Tests.csproj`（会连带编译主工程）
4. 探测 xunit.console.exe 实际路径（不 hardcode `tools/net462/`）
5. 调 runner 跑产出 dll

### 测试覆盖

当前 `Launcher.Tests.csproj` 直接编译 45 个测试源码文件（`<root>` 1 / `Bus` 2 / `Tasks` 4 / `Save` 8 / `Guardian` 30），可静态检出 443 个 `[Fact]` / `[Theory]` 标记。`SaveMigratorTests` 继续使用代码内 helper 数据；外部 fixture 目前主要集中在 `Fixtures/MapHud/`。

| 分组 | 覆盖面 |
|------|--------|
| `Bus/` | MessageRouter 当前观察行为、XMLSocket read loop 边界 |
| `Tasks/` | StageSelectTask、IconBakeTask、ArchiveTask list/filter 行为 |
| `Save/` | Protocol 2 决议、SOL 定位、legacy 首导入、版本 gate、repair policy / backup / auto-repair |
| `Guardian/` | overlay 坐标、DPI、FlashSnapshot、PanelHost/Router、InputShield telemetry、Native HUD bounds、UiData parsing、RightContext/MapHud/SafeExit/Combo/Toast/Notch/widget scaling |
| `<root>` | 基建冒烟 |

### Web QA 与开发 harness

本节最后核对代码基线：commit `cc25c357d`。

小游戏测试不走 `launcher/tests/`，地图 panel 的 DOM / 布局 / 交互回归也不走 C# 单测；统一按各模块自带的 QA 入口执行：

- **Node QA**：`node tools/run-minigame-qa.js --game lockbox|pinalign|gobang|all`
  - 实际入口文件：`tools/run-minigame-qa.js`
  - 共享 runner：`web/modules/minigames/shared/dev/node-qa-runner.js`
  - 适用场景：纯逻辑、确定性、导出结构、回归脚本
- **Browser harness**：直接打开各自 `dev/harness.html`
  - `web/modules/minigames/lockbox/dev/harness.html`
  - `web/modules/minigames/pinalign/dev/harness.html`
  - `web/modules/minigames/gobang/dev/harness.html`
  - `web/modules/map/dev/harness.html`
  - `web/modules/stage-select/dev/harness.html`
  - `web/modules/intelligence/dev/harness.html`
  - 共享 QA 基础层：`web/modules/minigames/shared/dev/harness-base.js` + `harness-base.css`
  - 支持 query 驱动的 `?qa=1` / `?case=` / `?scenario=` / `?dump=1`
  - `map` harness 额外覆盖页签 hit-test、右侧层级按钮遮挡、学校室友动态图、`1366x768` 紧凑视口可达性、locked group 锁定提示与锁定原因可达性
- **Map preview / calibration**：`web/modules/map/dev/preview.html`
  - 读取运行时 manifest，显示 assembled stage backdrop、`sceneVisuals` 拼接层、热点、页内按钮 `buttonRect`、动态头像槽位、XFL source rect
  - 支持 draft 校准、source 吸附、复制 selected/page override、复制当前页 JSON、复制完整 manifest、下载当前页 JSON
  - 用于视觉校准、条件模拟与默认视口收敛，可观察 locked groups / flash hint / hotspotStates，但不替代 browser harness 的交互 gate
- **Map visual builder**：`web/modules/map/dev/builder.html`（或 `preview.html?mode=builder`）
  - 在 preview 基础上开启 builder 模式，支持热点 / 过滤按钮拖拽与缩放、bundle 粘贴导入、本地草稿持久化、按页/全量清理
  - 用于日常布局施工与回写准备，不替代最终 manifest 导出或运行时联调
- **Manifest CLI 导出**：`node tools/export-map-manifest.js [--page base] [--output tmp/map-page-base.json] [--summary]`
  - 从 `web/modules/map-panel-data.js` 导出当前运行时 manifest 或单页导出
  - 用于把 preview / panel 当前数据结构交给后续 XFL / FFDec 校准链，不替代最终 authoring tool
- **Map layout fallback audit**：`node tools/audit-map-layout.js [--page school] [--json]`
- **Stage Select manifest / audit / harness**：`node tools/export-stage-select-manifest.js --summary`、`node tools/audit-stage-select-layout.js --json`、`node tools/run-stage-select-harness.js --browser edge`
  - 从 `flashswf/UI/选关界面/LIBRARY/选关界面UI/选关界面 1024&#042576.xml` 导出 `StageSelectData` 所用 manifest；Stage 2 通过 `StageSelectTask` / `StageSelectPanelService` 接入真实解锁 snapshot、`StageInfoDict` 关卡简介/限制词条/任务提示数据、真实进关、runtime 页内 frame 同步与关闭语义。关卡预览按原版链路导入：外部 PNG → `Symbol 3274` 内部命名帧 → 默认预览帧，layout audit 要求 `previewMissing=0`
  - Stage 2 正式入口替换记录见 `docs/选关界面-AS2入口替换交接.md`：AS2 `openWebStageSelect` 通过 `panel_request stage-select` 传入 `source/frameLabel`，C# 固化 runtime 初始化，`jump_frame` 同步 AS2 `_root.关卡地图帧值`，close 回调 `stageSelectPanelClose`；runtime 布局隐藏测试标题/fixture/dev 控件，16 个 frame tab 收进可展开区域菜单，场景门替换覆盖基地门口、车库、地下 2 层、停机坪、联合大学左右出口，并保留 Flash fallback
- **Intelligence panel harness**：`node tools/run-intelligence-harness.js --browser edge`
  - 打开 `web/modules/intelligence/dev/harness.html`，同时 mock 正式 runtime 的 `state → snapshot(itemName)` 按需正文链路与 dev `bundle` 全量包兼容路径；覆盖运行态无 `bundle` 请求、右侧可折叠情报目录、AS2 tooltip 富文本刷新、物品 XML `iconName` 图标解析、legacy 标签清洗、加密切换、缺图占位、长文本滚动与 1024×576 / 1366×768 / 1600×900 / 1920×1080 视口 hit-test
- **Stage Select FFDec visual audit**：`powershell -ExecutionPolicy Bypass -File tools/run-stage-select-visual-audit.ps1`
  - 通过 `tools/ffdec/ffdec.jar` 导出 `DefineSprite 330`，按 FFDec SVG 舞台原点裁成 1024×576 原帧，再用无头 Edge 抓 Web 舞台截图，输出 `tmp/stage-select-visual-audit/sheets/*-compare.png` 三联图和 `visual-audit-index.json`
  - 首次运行前先 `npm --prefix launcher/perf ci --ignore-scripts`；工具会优先使用 Adobe Animate 2024 / Flash CS6 自带 JRE，坐标参照 `ffdecFrameIndex` 字段（首帧特殊为 1，其余为 `sourceFrameIndex + 1`）
  - hover 卡片抽查可用 `node tools/capture-stage-select-web-frames.js --browser edge --fixture mixed --frame 基地门口 --hover-stage 新手练习场`
- **Map filter-fit tuner**：`node tools/tune-map-filter-fit.js --write`
  - 对照 `flashswf/UI/地图界面/LIBRARY/地图界面.xml` 中的原版实例坐标复核当前热点布局
  - 用于 fallback 期全量复核与 compact 页 XFL 对齐，不替代 browser harness 的交互 gate
- **Map audit sheets**：`python tools/render-map-audit-sheet.py --page base --page faction --page defense --page school`
  - 基于 manifest + `audit-map-layout` 输出热点/头像审计图（scene visual、hotspot rect、runtime/source/authored avatar overlay）
  - 用于全量视觉复核、Kimi/人工比对和 hand-tuned 页剩余偏差收口
- **Kimi visual review（可选）**：`powershell -ExecutionPolicy Bypass -File tools/kimi-map-review.ps1 ...`
  - 读取本地审计图与 audit JSON，让外部视觉模型辅助判断热点框/头像是否仍有肉眼可见偏差
  - 仅作视觉意见补充，不替代本地 audit / harness / 游戏内联调
- **静态收口校验**：`node tools/validate-minigame-final-state.js`
  - 用于阻止旧 `modules/lockbox-*.js`、旧版分游戏 session 命令名、旧共享结构 class 名回流

### LogManager 测试 hook

`LogManager.SetSink(Action<string>)` / `ResetSink()` 允许测试把日志重定向到 collect list；字段 `_sink` 标 `volatile`；生产路径 `_sink == null` 时走原文件+控制台通道，零 regression。

## 运行时配置与启动门槛

### 启动门槛（入口门槛 + 开发环境例外）

严格 fail-closed 的是入口 WebView2 预检和发行环境下的 Steam 校验；Flash trust 是 best-effort 租约，不属于拒启门槛。

1. **WebView2 Runtime 预检**（`--bus-only` 例外跳过）
   - 调用 `CoreWebView2Environment.GetAvailableBrowserVersionString()`
   - 失败 → MessageBox 指向 Evergreen Bootstrapper 下载页 → `return 1`
   - 命令行 `--force-webview-fail` 可强制触发本路径（测试用）

2. **Steam 正版校验** (`SteamOwnershipCheck.Check`)
   - 合法 git 开发仓库直接跳过所有权校验（支持 clone/worktree/fork/mirror）
   - 发行环境依次检查 Steam 进程、SteamAPI DLL 加载、AppID 所有权
   - `reason` 取值 `steam_not_running` / `not_owned` / `dll_missing` / `dll_load_failed` / 其他
   - 发行环境失败 → 对应文案 MessageBox → `return 1`，并**拒绝写入 Flash trust**

3. **Flash Trust 配置** (`FlashTrustManager.EnsureTrust`)
   - 租约文件固定叫 `cf7me.cfg`，优先写用户级 trust 目录，失败再尝试 `SysWOW64` / `System32`
   - `trustAcquired == false` 只打 WARNING，不拒启（降级运行，SWF 可能连不上）
   - `RevokeTrust()` 只移除本次 `EnsureTrust()` 新写入或追加的条目，不碰预存 trust 项

Steam 门槛负责正版校验，Flash trust 负责让 SWF 能联网，两者在代码里已经拆成“拒启门槛”和“可降级能力”两类。

### 两份配置源：机器级 vs 用户级

Launcher 的配置被**显式拆成两份**，避免互相污染：

#### config.toml（项目根目录，机器级，只读）

下面示例已枚举所有当前识别的 key，缺失即落代码默认：

```toml
flashPlayerPath = "Adobe Flash Player 20.exe"
swfPath = "CRAZYFLASHER7MercenaryEmpire.swf"

# GPU CAS 锐化（实验性）— 当前代码中该字段无消费者，pipeline 待完善。
# 保留为未来 feature flag；写什么都不影响当前运行行为。
gpuSharpening = false
sharpness = 0.5

# WebView2 / overlay performance diagnostics.
# Keep defaults false while investigating; toggle one at a time or use env vars.
webOverlayLowEffects = false
webOverlayDisableCssAnimations = false
webOverlayDisableVisualizers = false
webOverlayFrameRateLimit = 60
webView2DisableGpu = false
webView2AdditionalArgs = ""
nativeCursorOverlay = true

# off | auto | on — 管理 HKCU UserGpuPreferences；见下方"每应用 GPU 偏好"一节。
gpuPreference = "off"

# 开发用：Ctrl+G 触发 GPU 合成成本探针。玩家版必须 false。
devGpuProbeHotkey = false

# 开关 Native HUD + PanelHostController 装配（overlay 架构纯化迁移态；默认 false）。
# 设 true 启用 Panel-Only + 当前已注册 NativeHud widget（含 ToastWidget + NotchWidget）：
#   - useNativeHud=true 时不实例化 ToastOverlay 与 NotchOverlay；toast/notch 全部由 NativeHudOverlay 内的
#     ToastWidget + NotchWidget 承载，panel 开关随 nativeHud.Suspend/Resume，省两层独立 ULW
#     （DWM α traversal 收益叠加；常驻 ULW 5→3）
#   - panel 打开走 PanelHostController.OpenPanel：FlashSnapshot → backdrop → NativeHud（含 ToastWidget+NotchWidget）整层 Suspend
#     → WebOverlay 缩到 panel 矩形 + opaque + 去 LAYERED|TRANSPARENT
#   - panel 关闭：WebOverlay 回 anchor + 透明 + click-through；NativeHud Resume 重新评估 widget union（toast/notch 一并复显）
#   - WebOverlay SetReady 时不再 SuspendFallback——NativeHud 内 NotchWidget 一直作为常驻 HUD（含 LOG/EXIT/全屏按钮、FPS 药丸、currency、clock）；
#     toast/notch fallback 在 nativeHud 构造完毕后由 webOverlay.SetFallback(nativeHud, nativeHud) 升级，
#     IToastSink → ToastWidget，INotchSink → NotchWidget（同一 NativeHud 实例同时实现两个接口）
#   - 注入 CSS 隐藏 web 端 #notch / #toast-container / #top-right-tools / #context-panel / #safe-exit-panel /
#     #quest-notice-bar / #combo-status / #jukebox-panel / #map-hud 避免双重 UI
#   - NativeHudOverlay 当前注册 RightContextWidget / SafeExitPanelWidget / ComboWidget / ToastWidget / NotchWidget；
#     RightContextWidget 内部复用 MapHudWidget renderer，旧拆分 widget 类已移除。
#   - notch 通知路由：useNativeHud=true 时 `notchSink = nativeHud`（不走 CompositeNotchSink）。
#     NotchWidget 注册后是通用兜底 sink，所有 category 都直进 NativeHudOverlay.AddNotice → BeginInvoke。
#     INotchNoticeConsumer 精确订阅（如 ComboWidget 接 "combo"）优先于 NotchWidget 通用渲染，避免双显示。
#     ⚠ webOverlay 不再加入 sink 链——其 INotchSink 实现在 _useNativeHud=true 时仅会把调用 forward 回
#     _notchFallback (=nativeHud)，留在 sink 链里会让 SetStatusItem/ClearStatusItem 派发两次。
#     useNativeHud=false 退化路径仍是 `notchSink = webOverlay`（ExecScript / GDI+ NotchOverlay 兜底）。
# 性能收益：panel 打开期 α blend 成本下降；panel 关闭后 DoFullIdleSuspend 会 SW_HIDE + TrySuspendAsync 运行态 WebView2。
useNativeHud = false

# Desktop 顶层 ULW cursor（默认 ON，2026-05 推 default-on 后保留为回滚开关）。
# ON（默认）= DesktopCursorOverlay：desktop 顶层 ULW，跨 anchor 自由 + 单一 visibility 状态机
#   + scale 跟 GuardianForm.ClientSize（窗口级；panel 打开/关闭不再缩 cursor，全屏切换不抖动）
# OFF = 旧 CursorOverlayForm：OverlayBase 子类 + anchor-bound + scale 跟 FlashHostPanel-based
#   viewport（letterbox 黑边不计入；保留作为回滚兜底，无新功能）
# 见 plans/cursor-overlay-decoupling.md。环境变量 CF7_DESKTOP_CURSOR=0 一键回滚旧路径。
useDesktopCursorOverlay = true
```

代码默认（[AppConfig.cs](src/Config/AppConfig.cs) 构造函数）：`GpuSharpeningEnabled = true`, `Sharpness = 0.5`。示例显式写 `false` 是遵循正文「当前禁用」语义，等 pipeline 接上以后再统一默认。

`devGpuProbeHotkey=true`（或 `CF7_DEV_GPU_PROBE=1`）启用 Ctrl+G 切换 WebView2 `DefaultBackgroundColor=Black` + Flash 子窗口隐藏的 GPU 合成探针，用于实测 alpha blend 占 iGPU 的比重。日志写 `[GpuProbe] ON/OFF tick=...` 可对照任务管理器曲线。**玩家版必须保持 false**：误触会让游戏画面消失，再按一次才能恢复。

`useNativeHud=true`（或 `CF7_NATIVE_HUD=1`）开启 Panel-Only 架构 + NativeHud 接管 HUD + 当前 NativeHud widget：
- `HandleButtonClick` 与 `RequestOpenPanel` 路由到 [LauncherCommandRouter.cs](src/Guardian/LauncherCommandRouter.cs)（按钮命令唯一中枢）
- 所有 panel 打开统一进 [PanelHostController.cs](src/Guardian/PanelHostController.cs) 的 command queue：[FlashSnapshot.cs](src/Guardian/FlashSnapshot.cs).Capture → ComposeBackdrop → [NativePanelBackdrop.cs](src/Guardian/NativePanelBackdrop.cs) 显示 → [NativeHudOverlay.cs](src/Guardian/NativeHudOverlay.cs)（含 ToastWidget+NotchWidget）整层 Suspend → WebOverlayForm.ResumeForPanel（去 `WS_EX_LAYERED|WS_EX_TRANSPARENT`、`TransparencyKey=Empty`、`DefaultBackgroundColor=Black`、SetWindowPos `HWND_TOP|SWP_FRAMECHANGED` 至 [PanelLayoutCatalog.cs](src/Guardian/PanelLayoutCatalog.cs) 决定的矩形）→ PostToWeb `panel_viewport_set` → InputShield 进 telemetry → 顶置 HitNumber/Cursor → 启用 ESC
- panel 关闭（useNativeHud=true 路径）：WebOverlayForm.ForceIdleState 走 `DoFullIdleSuspend` —— `SuspendWebTimers` 停 fps/audio/position-settle/reload timer + `_frozenForIdle=true` 冻结 HandleUiData 仅缓存不 ExecScript + `ShowWindow SW_HIDE` + 恢复 `WS_EX_LAYERED|WS_EX_TRANSPARENT` + `HWND_NOTOPMOST` 防御 + `TransparencyKey/transparent BG` 复位 + `CoreWebView2.TrySuspendAsync` fire-and-forget；NativeHud Resume 重新评估 widget union（toast/notch 一并复显）。下次 `ResumeForPanel` 先调 `CoreWebView2.Resume()` 唤醒。useNativeHud=false 仍走 `DoSoftIdleRestore` 仅恢复样式拉回 anchor 矩形（保留 web HUD 显示）
- WebOverlay SetReady 时不再 SuspendFallback ([WebOverlayForm.SuspendFallback](src/Guardian/WebOverlayForm.cs))——NotchWidget/ToastWidget 在 NativeHud 内一直显示作为常驻 HUD（含 LOG/EXIT/全屏等按钮、FPS 药丸、currency、clock）；不再依赖独立 NotchOverlay/ToastOverlay ULW
- Toast / Notch 宿主迁移：useNativeHud=true 时 Program.cs 不实例化 ToastOverlay 也不实例化 NotchOverlay。nativeHud 构造完成后 `webOverlay.SetFallback(nativeHud, nativeHud)` 让同一 NativeHud 实例同时充当 IToastSink + INotchSink。
  - **Notch 通路（N/W/S 前缀，notchSink）**：`socketServer.SetNotchHandler(notchSink)`，其中 `notchSink = nativeHud`（useNativeHud=true）或 `webOverlay`（useNativeHud=false）。socket worker 直接调 `nativeHud.AddNotice / SetStatusItem / ClearStatusItem` → BeginInvoke → NotchWidget 处理；不再通过 CompositeNotchSink 复合到 webOverlay（`WebOverlayForm.AddNotice/SetStatusItem/ClearStatusItem` 在 `_useNativeHud=true` 时只会回弹 `_notchFallback=nativeHud`，留在 sink 链上会造成 SetStatusItem/ClearStatusItem 两次派发，SetReady 两次唤醒，徒增 NotchWidget upsert/repaint 压力——id 去重避免视觉双显但不省 CPU）。
  - **Toast 通路（M 前缀，toastSink）**：`toastSink = webOverlay`（不变）。socket → WebOverlayForm.AddMessage → 在 `_useNativeHud=true` 时 forward 给 `_toastFallback=nativeHud` → BeginInvoke → ToastWidget.AddMessage。这条仍走 webOverlay 是因为 toast 没有"通用 vs 类别精确"派发问题，且 webOverlay 入口在 useNativeHud=false 时还需要 ExecScript 走 web 端；保留单一入口减少 ToastTask 配置分支。
  - **AddNotice 类别派发**：NotchWidget 注册后是通用兜底 sink，`NativeHudOverlay.HasNoticeConsumerFor` 对所有 category 返回 true（注：现在该 API 只剩诊断用途，无外部 sink 链消费）；INotchNoticeConsumer 精确订阅（如 ComboWidget 接 "combo"）优先于 NotchWidget 通用渲染，避免双显示。
  - useNativeHud=false 退化路径仍是独立 ToastOverlay/NotchOverlay ULW，notchSink 退回 webOverlay。
- WebOverlay 注入 CSS 隐藏 web 端 `#notch` / `#toast-container` / `#top-right-tools` / `#safe-exit-panel` / `#quest-notice-bar` / `#combo-status` / `#jukebox-panel` / `#map-hud` / **`#context-panel`**（整个容器，含 `#quest-row > #map-hud-toggle / EQUIP_UI / TASK_UI` 按钮）避免与 C# 渲染重叠；notch/toast 消息（AddNotice/SetStatusItem/AddMessage）始终走 fallback (NativeHud→NotchWidget / NativeHud→ToastWidget) 而不是 web ExecScript。装备/任务入口由 [RightContextWidget](src/Guardian/Hud/RightContextWidget.cs) 的右侧 `装备/任务` 行接管，通过 [LauncherCommandRouter.cs](src/Guardian/LauncherCommandRouter.cs) 直接 `SendGameCommand("openEquipUI"/"openTaskUI")`，与原 web 路径等价
- **Native HUD 默认组成**：[NotchWidget](src/Guardian/Hud/NotchWidget.cs) 接管 web `#notch`（金币/KP、FPS、光照 sparkline、时钟、row1-right、hover toolbar，UiData `g/k/s/q` 直接喂入；`game` notice 复刻 Web 的队列、去重计数、3 秒退场和 4 条上限；视觉与原 [NotchOverlay](src/Guardian/NotchOverlay.cs) 严格对齐——hover state machine 通过 OnMouseEvent Enter/Leave 驱动而非 WM_MOUSELEAVE，按钮/sparkline/▼ 命中走 widget-local 坐标），[ToastWidget](src/Guardian/Hud/ToastWidget.cs) 复刻 web `#toast-container` 的 `285px` 宽度、8 秒显示 + 1.2 秒淡出、最多 8 条队列（视觉与原 [ToastOverlay](src/Guardian/ToastOverlay.cs) 严格对齐，alpha 在 segment 颜色内做以共享 NativeHud bitmap），[RightContextWidget](src/Guardian/Hud/RightContextWidget.cs) 接管右侧 5 键 + context panel + jukebox titlebar（布局统一走 [RightHudLayout](src/Guardian/Hud/RightHudLayout.cs)，小地图 card 复用 [MapHudWidget](src/Guardian/Hud/MapHudWidget.cs) shared renderer：优先按 `visuals.assetUrl` PNG alpha 绘制 web `map-hud-svg-silhouette` 等价剪影，失败才回退 blocks），[SafeExitPanelWidget](src/Guardian/Hud/SafeExitPanelWidget.cs)（**必须由 SAFEEXIT click → router → widget.Arm() 显式开启**才显示；同样走 `right:80px` 对齐规则；Arm 后 sv:1 显示「存盘中…」状态条，sv:2 切到 取消/退出 按钮），[ComboWidget](src/Guardian/Hud/ComboWidget.cs)（搓招进度 + DFA/Sync 命中扫光、字符收束、收起动画）。旧的拆分 widget 类已收敛进 `RightContextWidget` 或移除，不再在源码树中作为独立类维护
- NativeHud 鼠标 Click 合成必须 Down/Up 命中**同 widget**（[NativeHudOverlay.cs](src/Guardian/NativeHudOverlay.cs) `_leftDownWidget` 跟踪）；widget 内部如需 button-level 匹配（如 SafeExitPanel 的取消/退出），自行用 `_downIndex` 守门（见 SafeExitPanelWidget.TryFireButtonClick）
- NativeHud UiData 派发分两路：snapshot KV (`g:1234|k:5`) 走 [IUiDataConsumer](src/Guardian/Hud/INativeHudWidget.cs)；旧版 (`task|拯救公主` / `combo|波动拳|↓↘|...`) 走 [IUiDataLegacyConsumer](src/Guardian/Hud/INativeHudWidget.cs)。检测：[UiDataPacketParser.TryParseLegacy](src/Guardian/Hud/UiDataPacketParser.cs)——首段无 `:` 且总段数 ≥ 2 视为 legacy。NativeHudOverlay.HandleUiData 优先 legacy 探测，命中则一次性事件不入 snapshot；不命中再走 KV 路径。两套消费者计数 + LegacyTypes 集合 fast-path 独立守门（无消费者或 type 未订阅时整包早 return）
- N 前缀 notice 派发走 [INotchNoticeConsumer](src/Guardian/Hud/INativeHudWidget.cs)：socket "N{category}|color|text" → `notchSink.AddNotice`。**useNativeHud=true 时 notchSink 直接是 nativeHud**（不再经 [CompositeNotchSink](src/Guardian/CompositeNotchSink.cs)），webOverlay 不在 sink 链上避免 SetStatusItem/ClearStatusItem 派发两次。NativeHud 内分两路：(1) `_registeredNoticeCategories` 门控的精确订阅 widget（ComboWidget 接 "combo" → DFA/Sync 命中扫光）；(2) **NotchWidget 通用兜底 sink**——所有未被 INotchNoticeConsumer 订阅的 category 都路由到 NotchWidget 通知行。两路互斥（`AddNotice` 内 `hasCategoryConsumer` 守门），避免双显示。useNativeHud=false 时 notchSink=webOverlay，N 前缀走 ExecScript 或 webOverlay._notchFallback=NotchOverlay。CompositeNotchSink 类型仍保留（A.2 后未被使用，留待后续 phase 删除或在新 fan-out 场景复用）
- NativeHudOverlay 鼠标管线：拦 `WM_MOUSEACTIVATE` 返 `MA_NOACTIVATE` 防 Owner 被点击 deactivate；NativeHud 的 OnMouseDown/Up/Move 派发屏幕坐标到 widget，hit testing 走 `widget.TryHitTest(screenPt)`。NotchWidget 内部 hover state machine 通过 `OnMouseEvent(Enter/Leave)` 替代 WM_MOUSEMOVE/WM_MOUSELEAVE：Enter→Expanding，Leave→AutoHide 倒计时 500ms
- z-order：NativeHud 通过 `SetZOrderInsertAfter(hitNumber.Handle)` 沉到 HitNumber/Cursor 之下，widget 区域不会遮挡伤害数字与鼠标。架构链：Cursor → HitNumber → NativeHud → (Backdrop → WebOverlay) → Flash
- 缩放统一走 [WidgetScaler](src/Guardian/Hud/WidgetScaler.cs)：`scale = vpH/576`（用 letterbox-stripped viewport 高度，与 widgets 的 CalcViewport 锚点同源；不用 anchor.Height 避免 4:3 窗口下偏大错位）
- SAFEEXIT 二次确认：router 先调 `OnSafeExitArm`（→ `SafeExitPanelWidget.Arm()`，必须）再 `SendGameCommand("safeExit")` 触发存盘；C# widget 进 Saving 立即显示状态条，sv:2 后展示按钮。**Arm 是必需的**——否则 sv 这种通用存盘事件被自动存盘/商店关闭/升级路径触发时也会拉起退出确认面板
- 异常恢复：任何 step 抛异常 → `ResetToClosedState()` 强制 `ForceIdleState`，保证回到一致基线；连续 5 次失败熔断清空队列
- 关键不变量：`_panelMode==true ⇔ WebView 在 panelRect+opaque+direct-hit + NativeHud(含 NotchWidget) 隐藏`；`_panelMode==false ⇔ WebView 在 anchor+transparent+click-through + NativeHud 显示`
- 性能收益：panel 打开期 α blend 成本下降（panel 矩形小 + opaque）；idle 期 `DoFullIdleSuspend` 整个 SW_HIDE WebView2 + TrySuspendAsync → 拿回 ~15pp DWM α 地板（所有常驻 HUD 已迁到 C# widget，玩家在 panel 关闭期间仍能看到 notch / toast / 货币 / combo / RightContext 右侧 cluster）
- panel 态跟随：PanelHost.DoOpen 订阅 `ownerForm.LocationChanged`（拖窗）+ `FlashHostPanel.SizeChanged`（全屏/最大化/还原 → ResizeFlashToPanel 完成后才触发，比 owner SizeChanged 时序晚但读到的 viewport 正确）。BeginInvoke 节流合并多次事件 → 调 `WebOverlayForm.GetCurrentAnchorScreenRect`（与 SyncPosition 同算法）→ `PanelLayoutCatalog.GetRect` 重算 panelRect → `NativePanelBackdrop.RepositionTo` + `WebOverlayForm.RepositionForPanel`（两者均 `SWP_NOZORDER` 不重排避免拖动闪烁，不 `SWP_FRAMECHANGED` 跳过 NCPAINT）+ `InputShield.EnterTelemetryMode` 重设。**不**主动 ReTop HitNumber/Cursor——SWP_NOZORDER 已保证 z-order 不变。DoClose / ResetToClosedState 反订阅

#### Native HUD parity gate

`useNativeHud=true` 扩散或改默认前，必须先过刘海栏 + 右侧 HUD 视觉/功能等价 gate：刘海栏由 [NotchOverlay](src/Guardian/NotchOverlay.cs) 复刻 web `#notch` 居中 pill、`28px` row1、hover 展开 toolbar、未 game-ready 仅显示 row1-right；combo 由 [ComboWidget](src/Guardian/Hud/ComboWidget.cs) 复刻 web `#combo-status` 输入提示、DFA/Sync 命中扫光、字符收束与收起；toast 和 `game` notice 也必须保持 Web 队列/去重/生命周期语义。右侧 cluster 由 [RightHudLayout](src/Guardian/Hud/RightHudLayout.cs) 固定复刻旧 Web 常量（`right:80px`、`width:170px`、5×`34px` 顶部工具、地图 `86px`、任务行/通知行 `32px`、jukebox `24px`），小地图需显示与 web `map-hud-svg-silhouette` 等价的 PNG alpha 剪影 + current/beacon。人工截图对比旧 Web 与 native：基地场景、任务完成可交付、小地图展开/折叠、未播放/播放中 jukebox、combo 输入/命中、toast/notice 堆叠、暂停态、安全退出弹出、8 个 panel 开关后 idle；通过标准是位置、宽度、纵向顺序、点击区域、文案和主要颜色层级等价，允许 GDI+/CSS 字体抗锯齿差异。性能回归仍要确认 idle WebView2 `SW_HIDE`，Ctrl+G / Task Manager 采样不比当前 native HUD 基线明显退化。

`webOverlayLowEffects` 是运行态 overlay 聚合诊断开关，等价于同时启用 `webOverlayDisableCssAnimations` 与 `webOverlayDisableVisualizers`，并对 map panel 额外关闭全屏 scanline / radar / pulse、移除大图与场景节点的 CSS filter/drop-shadow、降低 full-surface overlay 透明覆膜成本。`webOverlayDisableCssAnimations` 只注入 `perf-no-css-animations`，关闭 CSS animation / transition；`webOverlayDisableVisualizers` 只隐藏 BGM/FPS canvas，并把 BGM 可视化推送从 60ms 降为 250ms 的 track-end 轮询。`webOverlayFrameRateLimit` 默认 `60`，通过 Web 端 requestAnimationFrame 限帧器把 overlay 的 JS/canvas 刷新链路限制到 60fps；`0`、`off` 或 `unlimited` 表示跟随当前显示器刷新率跑满。`webView2DisableGpu` 会同时给 BootstrapPanel 与运行态 WebOverlayForm 追加 `--disable-gpu --disable-gpu-rasterization --disable-accelerated-2d-canvas`，用于验证核显占满是否来自 WebView2 合成；它可能把负载转移到 CPU，不建议作为默认运行配置。`nativeCursorOverlay=false` 或环境变量 `CF7_NATIVE_CURSOR_OVERLAY=0` 会关闭 C# 原生 cursor layered window，恢复系统鼠标，用于 A/B 排除 cursor 迁移对 GPU 满载的影响。`useDesktopCursorOverlay`（默认 `true`，2026-05 推 default-on）：DesktopCursorOverlay 是 desktop 顶层 ULW，scale 跟 `GuardianForm.ClientSize`（窗口级，panel 开关/全屏切换都跟随；ctor 即 seed，外部 SetScale 推送只在 GuardianForm 还没 sample 过时作 fallback）。`useDesktopCursorOverlay=false` 或环境变量 `CF7_DESKTOP_CURSOR=0` 一键回滚到旧 CursorOverlayForm（OverlayBase 子类，anchor-bound，scale 跟 FlashHostPanel-based viewport，仅作回滚兜底）。详见 toml 示例注释。`useNativeHud=true` 或环境变量 `CF7_NATIVE_HUD=1` 启用 Panel-Only 架构 + Native HUD widget（详见上方 useNativeHud 段落与 Native HUD parity gate）。`webView2AdditionalArgs` 和环境变量 `CF7_WEBVIEW2_ARGS` 用于一次性追加 Chromium 参数；环境变量 `CF7_WEB_LOW_EFFECTS`、`CF7_WEB_DISABLE_CSS_ANIMATIONS`、`CF7_WEB_DISABLE_VISUALIZERS`、`CF7_WEB_FRAME_RATE_LIMIT`、`CF7_WEBVIEW2_DISABLE_GPU` 可覆盖对应配置。

BootstrapPanel 使用 `launcher/webview2_userdata`；运行态 WebOverlayForm 使用独立的 `launcher/webview2_overlay_userdata`。两者不能共用目录，因为 WebView2 同一个 user-data 目录下的 browser process group 要求启动参数一致，诊断参数（如禁 GPU）会导致启动阶段和运行阶段互相冲突。BootstrapPanel 在 reveal 后隐藏时会调用 WebView2 `TrySuspendAsync()`，避免启动页在游戏运行中继续参与 GPU 合成。

#### 每应用 GPU 偏好 (`gpuPreference`)

`config.toml` 的 `gpuPreference` 字段让 launcher 自己维护 `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` 下 launcher exe 与 `msedgewebview2.exe` 的条目：

| 模式 | 行为 |
|------|------|
| `off`（默认） | 启动时清理遗留条目，不写入新条目 |
| `auto` | DXGI 探测到非 Intel / 非软件适配器的独显 **且** `GetSystemPowerStatus` 回 AC Online 时才写入；否则 revert |
| `on`  | 无条件写入（副作用自担） |

退出时**始终** revert 写入的条目，保证卸载 / 升级后注册表干净。环境变量 `CF7_GPU_PREFERENCE=off|auto|on` 覆盖配置。诊断日志以 `[GpuPref]` 前缀进 `logs/launcher.log`，记录探测到的独显名 / VendorId / ACLineStatus。

**Flash Player 刻意不纳入**：Flash SA 的 Stage3D 走 DX9 老路径，在部分独显驱动组合下稳定性反而不如核显；保持跟随系统默认。

**适用性**：仅在独显直连 / MUX 直连 / 桌面机独显场景下建议开 `auto`。Optimus 混合输出 (dGPU 渲染 → iGPU 扫描输出) 的游戏本 / 笔记本**不建议开启**；实测表现为核显占用不归零（DWM + Flash 仍在核显上）、独显回传引入 1-2 帧延迟、鼠标跟手感下降，峰值 FPS 可能相近但输入延迟明显变差。判断依据是 BIOS 是否有独显直连 / MUX Switch 开关；没有则保持 `off`。

**副作用警告**（`auto` 会自动规避一部分）：
- Optimus 笔记本 dGPU 渲染 → iGPU 输出的合成结果要经 PCIe 回传，PCIe 流量反而上升；PCIe 链路本身有信号完整性问题的机器可能因此更不稳。
- dGPU 陪跑 WebView2 合成会额外抽电；电池模式续航明显下降。
- 断续的 WebView2 合成负载（hover / menu / radar pulse）让独显频繁 P-state 抖动，对"鼠标跟手感"这种延迟敏感路径反而不如核显稳态。
- Optimus 模式下桌面合成与最终扫描输出仍经核显，任务管理器里核显 3D 不会归零；务必用 `sample-launcher-gpu.ps1` A/B 验证，`phys_0` 是否真有可观的 3D 负载下降。

双显卡机器上可用 `tools/set-launcher-gpu-preference.ps1` 查看或手动写入 Windows 每应用 GPU 偏好（仅诊断用途；launcher 启动时会按 `gpuPreference` 自动覆盖本脚本的写入）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\set-launcher-gpu-preference.ps1 -List
powershell -ExecutionPolicy Bypass -File tools\set-launcher-gpu-preference.ps1 -Apply
powershell -ExecutionPolicy Bypass -File tools\set-launcher-gpu-preference.ps1 -Revert
powershell -ExecutionPolicy Bypass -File tools\sample-launcher-gpu.ps1 -DurationSeconds 6
node tools\audit-web-overlay-complexity.js
```

`-Apply` 写入当前用户注册表后必须完整关闭并重启 launcher / game。WebView2 Evergreen runtime 升级后 `msedgewebview2.exe` 路径可能变更，需要重新运行 `-Apply`。`sample-launcher-gpu.ps1` 只读采样 Windows GPU engine 计数器，并按 `launcher` / `flash` / `bootstrap` / `web_overlay` 分组输出平均与峰值，用于复核负载是否仍集中在运行态 WebOverlayForm。`audit-web-overlay-complexity.js` 不启动浏览器，只静态统计 overlay CSS / JS 中 animation、filter、drop-shadow、box-shadow、blend、clip-path、layout measurement、RAF 等高风险点，用于在机器不稳定时优先做低风险定位。在无独显直连 / MUX 的笔记本上，即使渲染进程被调度到独显，桌面合成与最终扫描输出仍可能经过核显，因此任务管理器中核显 3D 不一定归零；若重启后 WebOverlayForm 仍完全落在 `phys_0`，下一步应继续削减 map overlay 的 WebView2 渲染成本。

2026-04-25 地图界面排查记录见 [Web Overlay 性能排查记录](../docs/web-overlay-performance-audit-2026-04-25.md)。

#### launcher_user_prefs.json（用户级，频繁读写）

优先路径：`%LOCALAPPDATA%\CF7FlashNight\launcher_user_prefs.json`。
如果 `LocalApplicationData` 不可用，会直接回退到项目根 `launcher_user_prefs.json`。若 appdata 可用但只存在 legacy 文件，则首次读取后会自动做一次性迁移，之后不再写 repo 根。

| 字段 | 类型 | 默认 | 含义 |
|------|------|------|------|
| `lastPlayedSlot` | string &#124; null | null | 欢迎页默认高亮的槽位 |
| `introEnabled`   | bool   | false | 「加载片头动画」复选框 |
| `sfxEnabled`     | bool   | true  | UI 音效（hover/click/confirm/error） |
| `ambientEnabled` | bool   | false | Idle 态环境 hum（θ-FLOOD 背景低频） |
| `uiFontScale`    | number | 1.35  | 引导页 `:root --fs-scale` 倍率，clamp 到 [0.7, 1.9] |
| `suppressedHighDpiWarningRaw` | string &#124; null | null | 内部字段：用户选择不再提示的高 DPI 兼容性 raw value |

前端（[web/modules/display.js](web/modules/display.js), [web/modules/about.js](web/modules/about.js), [web/bootstrap-main.js](web/bootstrap-main.js)）通过 **`config_set` 协议**读写公开字段（见 Bootstrap 前端与协议节）。`suppressedHighDpiWarningRaw` 只由 C# 兼容性提示对话框读写，不下发给 Web。`list_resp` 每次都会附带 `introEnabled` / `sfxEnabled` / `ambientEnabled` / `uiFontScale`，而 `lastPlayedSlot` 只在非空时下发；前端缺失该字段时按 `null` 处理。

### 命令行参数

| 参数 | 作用 |
|------|------|
| `--bus-only` | 跳过入口的 WebView2 **fail-closed 预检**、Flash SA 启动、BootstrapPanel / GameLaunchFlow 路径；保留 HTTP + XMLSocket + WebOverlayForm 构造（仍会调用 `GetAvailableBrowserVersionString`，环境里无 WebView2 仍会抛）。用于让 Flash CS6 testMovie / 基准工具自行连总线 |
| `--force-webview-fail` | 强制触发 WebView2 缺失分支（冒烟测试） |

## Bootstrap 前端与协议

### 整体模型

BootstrapPanel 加载 `launcher/web/bootstrap.html`，由 `bootstrap-main.js` 主控（IIFE 模块）。页面是两栈视图：

```
bootstrap.html
├── topbar (常驻)            CF7:ME 品牌 + state-badge + [取消启动] [重试] [全屏] [日志] [其他]
├── #view-welcome            欢迎页：title-logo + slot-plate + briefing + faction 列表 + VERSION 右栏
├── #view-slots              槽位选择：toolbar + 卡片网格（CRUD）
├── #modal-host              模态容器（archive-editor / about / diagnostic-log）
├── .intro-ov + .intro-skip  片头视频层 + ESC 跳过按钮
└── 底栏                     Steam 品牌 + 频道字样
```

`BootstrapPanel` 本身不会在 `GuardianForm` 构造期同步拿到可用 WebView2；实际初始化发生在控件 `Load` 事件里，完成后才进入下面这套前端握手。

**脚本加载顺序**（bootstrap.html body 尾）：`config/version.js` → `modules/audio.js`（暴露 `window.BootstrapAudio`）→ `bootstrap-main.js` 主控 IIFE → `modules/factions.js` + 4 个模态模块。

**IIFE 初始化后的消息顺序**：
1. 先 `send({cmd:'list'})` 取槽位 + 偏好（`list_resp` 固定带回 `slots` + 4 个固定偏好字段，`lastPlayedSlot` 仅非空时附带）
2. 双 `requestAnimationFrame` 后再 `send({cmd:'ready'})` → C# 侧 `Prewarm()` silent 拉 Flash

顺序不能颠倒：list 要先铺好欢迎页存档卡片与字号/音频偏好，ready 后即便 prewarm 状态机立即跳转，也会被 `silentAtEmit` 过滤不污染 UI（两层保险）。

### 槽位选中后的启动路径

点击"确认"按钮（有片头）或卡片内快捷"启动"（无片头），`bootstrap-main.js` 发送 `start_game` / `rebuild`，按需带两个 reveal gate flag：

| flag | 语义 | 清除条件 |
|------|------|----------|
| `deferReveal:true` | 等 JS 端播完片头视频 / 用户跳过 / 无片头直通 | JS 发 `{cmd:'reveal_ok'}` |
| `requireFlashReveal:true` | 等 Flash 封面帧（帧 81）发 `bootstrap_reveal_ready` | AS2 通过 XMLSocket 发任务 |

**`flash_ready` 时机**：`bootstrap_reveal_ready` 到达清掉 `_revealWaitingFlash` 的瞬间就广播 `{cmd:'flash_ready'}`，让跳过按钮切"进入游戏"态——哪怕此时 JS 侧片头还没播完、`_revealWaitingJs` 仍 true、panel swap 尚未执行。两 flag 都清空后 `DoPerformReveal()` 才真正做 panel swap（BootstrapPanel 隐藏、FlashHostPanel 显示 + readyWiring + 托盘图标可见）。`hotkey_guard.exe` 在 `Program.Run` 初始化阶段就已 `Process.Start`，**不在 reveal 路径**（GameLaunchFlow 构造时 `hotkeyGuardSpawn` 传的是 `null`）。

### cmd 分发表（BootstrapMessageHandler → Handlers/*）

WebView2 通过 `chrome.webview.postMessage({cmd, ...})` 发消息。所有 19 个 cmd：

| 分组 | cmd | 职责 | 状态约束 |
|------|-----|------|----------|
| Lifecycle | `ready` | WebView2 就绪 → **触发 `Prewarm()` silent 拉 Flash**（冷启动关键） | 任意；session latch 防重入 |
| Lifecycle | `ping` | 连通性 echo（payload 原样回传 `pong`） | 任意 |
| Lifecycle | `cancel_launch` | 用户主动取消启动；非 Idle → `Reset(null, "user_cancel")` | 任意；Idle 下 no-op |
| GameState | `start_game` | 点击确认启动该 slot（附 `deferReveal?` / `requireFlashReveal?`），自动写 `lastPlayedSlot` | **接受 4 态**：Idle（冷启，TransitionToSpawning）/ WaitingConnect / WaitingHandshake（prewarm 握手未到，存 slot 待 handshake 快路径）/ PrewarmHandshakeHeld（flush held callback → TransitionToEmbedding）；其他启动中态直接 return 不回包 |
| GameState | `rebuild` | 同 `start_game`，UI 层语义"重建存档场景" | 同上 |
| GameState | `reveal_ok` | JS 侧 reveal 信号（片头播完/跳过/无片头直通） | 任意；非 waitingJs 状态下 log + no-op |
| GameState | `retry` | `GameLaunchFlow.Retry()`：锁内快照 `_pendingSlot` → 锁外 `Reset(onIdle: StartGame(slot))` | **仅 Error 态有效**，其他态直接 return |
| Archive query | `list` | 先对标准 10 槽做 legacy SOL 预热，再列所有槽位 → `list_resp`（`slots` + 4 个固定偏好字段；`lastPlayedSlot` 仅非空时附带） | 任意 |
| Archive query | `load` | 标准 10 槽先做 legacy SOL 预热，再读 shadow JSON → `load_resp`（遇 tombstone 报错） | 任意 |
| Archive query | `load_raw` | 标准 10 槽先做 legacy SOL 预热，再绕过 tombstone 读原始 JSON（editor 用）→ `load_raw_resp` | 任意 |
| Archive query | `delete` | 写 tombstone → `delete_resp` | 任意 |
| Data edit | `save` | 玩家侧编辑写回 shadow（`userEdit=true` 强校验 + 覆写 `lastSaved`） | **`RequireIdleOrTearDown`**（见下） |
| Data edit | `reset` | 清 launcher 副本 + tombstone（不清 SOL，下次启动可能从 SOL 回填） | 同上 |
| Data edit | `export` | 把 slot 导出到用户选择路径 → `export_resp` | 任意 |
| Import | `import_start` | 两段式导入：预览 | **`RequireIdleOrTearDown`** |
| Import | `import_commit` | 两段式导入：确认落盘 | 同上 |
| Ui/diag | `logs` | 读取 `logs/launcher.log` 最近 N 行 → `logs_resp` | 任意 |
| Ui/diag | `open_saves_dir` | 调 `explorer.exe` 打开 `saves/` 文件夹 | 任意 |
| Ui/diag | `diagnostic` | 打包当前档(`json + sol 二进制原件`) + `logs/` + `config/` + `meta.json` 到 `logs/diagnostic-{slot}-{ts}.zip` → `diagnostic_resp` | 任意 |
| Ui/diag | `audio_preview` | 直调 `AudioEngine.ma_bridge_*` 应用音量并(SFX 通道)播放硬编码常驻 SFX (Button9.wav) → `audio_preview_resp` | 任意 |
| Config | `config_set` | UserPrefs 写入 + 持久化（Plan A+ 协议，见下方） | 任意 |

未识别 cmd → `PostError(unknown_cmd, cmd)`。

### Idle 守卫：`RequireIdleOrTearDown` 语义

`save` / `reset` / `import_start` / `import_commit` 共享这个守卫，语义**不是**一律 `not_idle`：

- **Idle** → 直接执行
- **silent prewarm 中**（launchFlow.IsInSilentPrewarm）→ `Reset(onReady, "user_edit_" + cmd)` 拆掉 prewarm 回 Idle，再 flush pending 跑原 onReady；**用户编辑不被后台 prewarm 挡住**
- **其他非 Idle**（用户已点启动、Embedding / WaitingGameReady / Ready）→ 回 `{ok:false, error:"not_idle"}`

这是单窗体 + prewarm 模型的必要补丁：冷启动后 Flash 已在后台跑，但用户编辑存档的时候 launcher 得能静默 tear down 再继续。

### `config_set` 协议（Plan A+ 权威下发）

入：`{cmd:'config_set', key, value, requestId?}`（`requestId` number 可选）

```
key 白名单（[ConfigCommandHandler.cs](src/Guardian/Handlers/ConfigCommandHandler.cs)）:
  introEnabled     bool
  lastPlayedSlot   string | null
  sfxEnabled       bool
  ambientEnabled   bool
  uiFontScale      number → clamp [FontScaleMin=0.7, FontScaleMax=1.9]
```

出：`{cmd:'config_set_resp', key, requestId?, ok, error?, currentValue?}`

```
error (ok=false 时出现):
  unknown_key            key 不在白名单
  bad_value              value 类型与 key 期望不匹配
  save_failed            内存已更新但 %LOCALAPPDATA% 落盘失败（磁盘满/权限问题）
  exception              其他意外
  key_missing            请求里没 key
  userprefs_unavailable  userPrefs 不可用

currentValue (Plan A+):
  无论 ok/失败都附带 = 服务端 UserPrefs 当前真实值（已做所有 rollback）
  未知 key / userPrefs 缺失 → 省略
```

关键不变式：

1. **写入原子性**：C# 侧在 switch 前快照 `config_set` 白名单字段；`Save()` 或异常时一次性回滚，保证公开偏好"内存 == 磁盘"
2. **前端权威对齐**：`bootstrap-main.js` 收到 `config_set_resp` **无条件** `applyFn(currentValue)` 对齐 UI + BootstrapAudio + 本地状态，不再依赖 optimistic prior 快照
3. **相关 id**：`requestId` 解决连点/乱序场景下 apply 对错请求的问题；监听 map 是 `Map<requestId, applyFn>`，响应按 id 查 apply，用完即删
4. **list 回退**：仅三种异常路径才退到 `list` 刷新（applyFn throw / 没带 requestId / `!ok && currentValue` 缺失）

### C# → bootstrap 推送

`GameLaunchFlow.OnStateChanged` 的订阅方按 `silentAtEmit` 参数过滤：**silent prewarm 活跃期（`_pendingSlot == null` 的后台 teardown 窗口）直接 return，不广播给 bootstrap UI** —— 避免 archive-editor 进只读 / bootstrap.html 闪 running badge / RequireIdle 挡 save。`silentAtEmit` 在 `SetState` 锁内就地快照，不受 UI 线程 BeginInvoke 排队延迟影响。用户点 `start_game` 后 `_pendingSlot` 赋值，后续跳转才正常推：

```json
{ "type": "bootstrap", "cmd": "state", "state": "<State>", "msg": "<free-form>" }
```

其他推送：`flash_ready`（Flash 封面帧到达的瞬间；不等 JS reveal）、`config_set_resp`、各种 `*_resp`、`error`。没有 `reason` 字段，前端靠 `msg` 解析（如 `"flash_exited"` / `"handshake_timeout"`）。

### 与运行态生命周期的关系

**reveal 成功 = panel swap，不是 Form 切换**：BootstrapPanel.SetPanelVisible(false) + FlashHostPanel.Visible=true + readyWiring。BootstrapPanel 不会 Dispose，仍在同一 GuardianForm 里；隐藏后会请求 WebView2 suspend，避免启动页继续占用 GPU 合成资源。**代码库没有任何让它在 Ready 之后重新显形的路径**。

**Ready 后的退出路径**：

| 触发 | 处理 |
|------|------|
| Flash 进程正常退出 | `OnFlashExited` → `form.ForceExit()` → **整个 Launcher 一起退出** |
| socket 断连 10s + Flash 仍活 | Zombie 兜底 → `form.ForceExit()` → 同上 |

**活跃启动态（非 Ready）出错**：Flash 异常 → `TransitionToError("flash_exited")`。BootstrapPanel 还可见，玩家可在 Error 态 `retry` 回到 Idle 重试，或 `cancel_launch` 回 Idle 自己改。

玩家想"换槽位"还是要退 launcher 重启，这一点和旧模型一致；只是"显隐切换"从 Form.Show/Hide 变成了 Panel.SetPanelVisible。

## Phase 5.8：音频迁移期存档编辑器（2026-04-28）

### 起源 — 主音量为 0 静音事件

测试员反馈"听不到音效"。日志比对：每次启动 Flash 拉档后立即推 `master_vol=0` + `bgm_vol=0.01`，存档里 `others.设置.setGlobalVolume:0` 是源头。Flash 的"设置 UI"已被移植到启动器的迁移计划里，但移植期 UI 缺位，玩家踩进 0 音量后没有可见的恢复入口（参考 [SaveManager.as:1323-1348](../scripts/类定义/org/flashNight/neur/Server/SaveManager.as) 的 packSettings/applySettings 协议）。

### 临时入口：存档编辑器系统卡片

[archive-editor.js](web/modules/archive-editor.js) 简易模式按 [archive-schema.js](web/modules/archive-schema.js) 的 `category` 字段分组渲染卡片：

- `character`（角色名/性别/金钱/等级/经验/...）
- `progress`（主线进度）
- `training`（健身五维）
- `system`（**setGlobalVolume / setBGMVolume**，迁移期临时入口）
- `danger`（version 等改动后会让档无法识别的字段）

系统卡片每个字段是 **滑杆 + 数字输入框 + 三预设（静音 / 默认 / 最大）+ 试听** 的组合控件；试听走 bootstrap channel `audio_preview` 直调 `AudioEngine.ma_bridge_*`，SFX 通道还会播一个硬编码的常驻 SFX (Button9.wav) 给即时反馈。

危险字段（schema 中 `danger:true`）默认 disabled，需双击 `danger-lock` 按钮 confirm 后才解锁；解锁状态进 `_dangerUnlocked` set 内存表，unmount 即清空。

### 兜底 toast — `master_vol==0` / `bgm_vol<0.02` 进程级单次提醒

[AudioTask.cs](src/Tasks/AudioTask.cs) `HandleMasterVol` / `HandleBgmVol` 在收到 Flash 推送的可疑值时，调用注入的 `IToastSink` 弹一次 toast，提示"音频设置 UI 迁移中，可在存档编辑→简易模式→系统调整"。每次 launcher 启动只触发一次（`_volumeWarningEmitted volatile bool`），重启 launcher 才会再次提示，避免反复打扰。Sink 注入点：[Program.cs:430](src/Program.cs)（`AudioTask.SetToastSink(toastSink)`）。

### 诊断包导出（`logs/diagnostic-{slot}-{ts}.zip`）

存档编辑器顶部右侧"导出诊断包"按钮 → bootstrap channel `diagnostic` → [DiagnosticPackager.cs](src/Diagnostic/DiagnosticPackager.cs)。HTTP `/diagnostic` 是等价的外部入口。

zip 内容：

```
diagnostic-{slot}-{ts}.zip
├── save/{slot}.json           当前编辑器聚焦的 shadow JSON
├── save/{slot}.sol            通过 SolFileLocator 解析的 SOL 二进制原件（迁移期权威源对比需要）
├── logs/launcher.log          + launcher.log.1（FileShare.ReadWrite 打开，避开锁）
├── config/config.toml
├── config/launcher_user_prefs.json
├── meta.json                  OS / git HEAD（读 .git/HEAD 解析 ref） / CLR / 机器名 / 时间戳
└── README.txt                 给测试员的提示
```

slot 缺省时只打 logs + config + meta（不带档），用于"启动失败前没机会进编辑器"的场景。

### 已修改 (diff) 视图

第四个 tab，遍历 `archive-schema.fields` 中所有声明了 `default` 的字段，把当前值与 default 不同的列出来，每行带"恢复默认"按钮。遇危险字段时按钮报错让用户先回简易模式解锁。空状态文案"档与白名单字段默认值完全一致"。

### 搜索浮层

编辑器顶部右侧"搜索"按钮触发（不绑 Ctrl+F —— `KeyboardHook` / `HotkeyGuard` 把 Ctrl+F 当全屏切换拦在 web 之外，浮层收不到事件）。`advanced` / `tree` / `modified` 三个模式可用，`simple` 模式按钮 disabled（卡片化已自带分组，搜索意义低）。

浮层右上角浮层，包含搜索框 + `n / m` 计数 + 上下跳转 + 关闭。`advanced` 模式走 textarea selection range；`tree` / `modified` 模式走 DOM 节点 textContent + input value 扫描，`tree` 模式自动展开所有 `<details>` 让匹配可见。debounce 200ms。Esc 关闭浮层。

### 权威源 — `launcher/data/save_schema.json`

由 [tools/extract-save-schema.js](../tools/extract-save-schema.js) 从开发者的 `saves/crazyflasher7_saves.json` 抽取生成。流程：

1. 完整克隆档结构（保留每条游戏数据，迁移期需要原值做对比）
2. 套用 `SCHEMA_DEFAULTS` 白名单（角色等级/经验/金钱/技能点 → 0/1，音量 → 50/80），避免开发者档里的进度/等级被冒充成"出厂默认"
3. 写出到 `launcher/data/save_schema.json`，附 `__meta` 字段标记来源 + 生成时间

[build.ps1](build.ps1) 的 `Step 6b` 会校验 `save_schema.json` 存在；缺失时报错并提示运行 `node tools/extract-save-schema.js`。当前 diff 视图主要靠 schema 里 inline 的 `default`，`save_schema.json` 是为后续 diff 范围扩展（不在 schema 白名单内的任意字段）准备的基线。

### 迁移完成后的清理路径

> 当 Flash 设置 UI 迁移到启动器内（脱离档存盘）之后，本节相关代码可分级退役：
>
> - **必删**：[archive-schema.js](web/modules/archive-schema.js) 中 `system` category 的两条音量字段、[archive-editor.js](web/modules/archive-editor.js) 中 `card-temporary-hint` 文案、`audio.master/bgm/sfx` 预览分支。
> - **降级**：`AudioTask` 兜底 toast 可降为低优先级 log（迁移完成后玩家有正常 UI 路径恢复）。
> - **保留**：诊断包导出、Ctrl+F、diff 视图、危险字段解锁机制 —— 这些是通用能力，不绑迁移期。

## 关键设计决策

### Flash 嵌入（SetParent）
Guardian 通过 Win32 `SetParent` 将 Flash Player SA 窗口嵌入 `_flashPanel`（WinForms 自绘 D3DPanel），移除标题栏/边框/菜单栏。500ms 看门狗定时器检测全屏等操作导致的脱离并自动重新嵌入。

### 双通道通信

**XMLSocket**（TCP，`\0` 分隔 JSON）：Flash 原生支持，承载 IPC 主流量。除了 JSON 路由还有 8 个入站快车道前缀（见架构概览节）+ 1 个出站前缀（`P`，C#→AS2）。

**HTTP API**（REST，11 个 path）：

| 端点 | 方法 | 作用 |
|------|------|------|
| `/testConnection` | POST | 基础连通性探测 |
| `/getSocketPort` | GET | 获取 XMLSocket 监听端口（Flash 在握手前查询用） |
| `/status` | GET | 总线状态快照 `{ok, socketConnected, httpPort, socketPort, tasks[]}`；`tasks` 是 TaskRegistry 的元数据清单。**不包含**启动阶段 / attemptId / savePath，那些只在 bootstrap UI 里可见 |
| `/console` | POST | 外部 console 命令队列（5s 超时，`OnConsoleResult` 回调解析） |
| `/task` | POST | 通用 httpCallable：按 JSON 路由进 MessageRouter |
| `/logBatch` | POST | AS2 端日志批量上报（批次持久化到文件通道） |
| `/logs` | GET | Bootstrap UI / 外部读取最近若干行 `logs/launcher.log` |
| `/save-push` | POST | 从 `saves/{slot}.json` 读取并推送给 AS2（Protocol 2 之外的辅助路径） |
| `/diagnostic` | POST | 与 bootstrap channel `diagnostic` 等价的 HTTP 入口，body `{"slot":"..."}` 触发诊断 zip 打包，响应 `{ok, zipPath, zipName, zipSize, warnings[]}` |
| `/shutdown` | POST | 请求 Launcher 退出（OnKillFlash → Dispose 链） |
| `/crossdomain.xml` | GET | Flash 跨域策略 |

### 端口分配
从种子 `"1192433993"` 提取 4/5 位数子串作为候选端口，与 AS2 `ServerManager.as` 保持一致。运行时逐个测试可用性，第一个通过的作为 httpPort，第二个作为 socketPort（实测 httpPort=1192, socketPort=1924）。

### 快捷键拦截（四层防御）

| 层 | 手段 | 说明 |
|----|------|------|
| ① | `SetMenu(NULL)` | 移除 Flash 原生菜单栏，Ctrl+F/Q/W/O/P 的加速器从源头消失 |
| ② | `hotkey_guard.exe`（独立进程） | `WH_KEYBOARD_LL` 前台感知，仅 Guardian/Flash 在前台时拦截 Ctrl+F（全屏）/ Ctrl+Q（退出）；进程不在（未编译）时只打 log，降级到下一层 |
| ③ | `KeyboardHook`（进程内低级钩子） | ESC 面板路由 + Ctrl+F 兜底；安装失败（Windows 钩子配额用尽等）会打 `KeyboardHook failed, falling back to RegisterHotKey` |
| ④ | `RegisterHotKey`（fallback） | 上一层失败时退化为系统全局热键注册；功能弱化但至少能保住 Ctrl+F/Ctrl+Q |

### 原生音频引擎（miniaudio）
音频播放从 Flash Sound API 完全迁移到 C# launcher 的 native DLL，Flash 侧仅发送播放指令。

**架构**：
- `miniaudio_bridge.c` → `miniaudio.dll`: 单文件 C 库，WASAPI shared mode，支持 play/stop/seek/peak
- `AudioEngine.cs`: P/Invoke 封装 (bgm_play/stop/seek/get_peak/get_cursor/get_length/is_playing)
- `AudioTask.cs`: BGM JSON handler (bgm_play/stop/vol/seek) + SFX 快车道批量解析
- `MusicCatalog.cs`: BGM 曲库管理，合并 bgm_list.xml + 文件系统自动发现 + FileSystemWatcher 热加载
- `DirectoryWatcherService.cs`: 通用文件监听服务（500ms 去抖，可复用于 mod/皮肤等场景）

**BGM 专辑系统**：`MusicCatalog` 启动时解析 `sounds/bgm_list.xml`（手工注册曲目）并扫描 `sounds/*/` 子目录发现未注册的音频文件（MP3/WAV/OGG/FLAC），按文件夹名归类为专辑。合并后的完整目录在 Flash 业务就绪后推送（`OnClientReady` 事件），热加载增量通过 `catalogUpdate` 推送。玩家只需在 `sounds/` 下新建文件夹投放音频，游戏运行中即可识别。详细说明见 [`../sounds/README.md`](../sounds/README.md)。

**BGM 优先级**：Flash 侧 `SoundEffectManager` 实现 3 级优先级状态机（stage > jukebox > scene），支持 override 模式（jukebox > stage > scene）。被高优先级抢占的 BGM 意图记录在 `_suppressedScene/_suppressedStage` 中，恢复时精确还原（含 album 模式和 loop 语义）。

**BGM**：双 `ma_sound` 实例 ping-pong crossfade。切换时旧曲淡出与新曲淡入重叠进行，基于 `ma_engine_get_time_in_milliseconds` 全局时钟调度。`stopBGM` 使用 `ma_sound_stop_with_fade_in_milliseconds`，操作两个槽位确保无残留。注意 miniaudio 的 base volume 与 fader 是相乘关系，crossfade 路径中 `ma_sound_set_volume` 必须设为 1.0（由 fader 独立控制 0→1 淡入）。Seek 使用 `ma_sound_seek_to_second()`（基于声源自身采样率换算，不依赖 engine sample rate）。

**BGM 可视化 + 点歌器**：`PeakDetector` 自定义节点（`ma_node_vtable` passthrough）插入 bgmGroup → engine endpoint 之间，实时采样 L/R peak。C# 60ms 轮询 `ma_bridge_bgm_get_peak/cursor/length/is_playing` → WebView2 `PostWebMessageAsJson` 推 `audio` 消息。折叠态由 C# `RightContextWidget` 的 jukebox titlebar 接管（mini wave + 标题 + pause/expand）；展开 UI 是正式 panel：[panels/jukebox-panel.js](web/modules/panels/jukebox-panel.js) 注册 `Panels.register('jukebox')`，由 `JUKEBOX_EXPAND` → `LauncherCommandRouter.OpenPanel("jukebox")` → `PanelHostController` 走完整 backdrop / EX_STYLE / HUD-suspend 序列后渲染大波形 + 进度条 + 专辑浏览 + 选曲 + 设置（音量 / 覆盖关卡BGM / 真随机 / 播放模式）+ 帮助 markdown。曲目标题由 AS2 `pushUiState("bgm:title")` 经 UiData 推送（jukebox-panel.js onOpen 通过 `UiData.get('bgm')` seed 当前值，避免 panel 晚于启动期打开错过历史推送），设置状态由 `jbo:/jbr:/jbm:/vg:/vb:` 通道同步。catalog 由 `MusicCatalog` 在启动期 + 文件变更时增量推 `catalog`/`catalogUpdate`；后开 panel 缺失时主动 `cmd:'requestCatalog'` 拉全量。Web 旧 [modules/jukebox.js](web/modules/jukebox.js) 已注释脚本入口（DOM 暂留 Phase 7 删除），不再参与运行时音频/UiData 订阅。

**SFX**：启动时扫描 `sounds/export/{武器,特效,人物}/` 目录，文件名即 linkageId，覆盖顺序武器→特效→人物（后覆盖前）。Flash 侧帧内累积，帧末由 FrameBroadcaster 合批发送 `S{id1}|{id2}|{id3}` 快车道消息。native 层 90ms 去重。

**路径编码**：所有字符串参数使用 `wchar_t*` (UTF-16)，文件操作用 `ma_sound_init_from_file_w()`，支持中文路径。

**音效资产**：由 `tools/export_sfx.py` 调用 FFDec CLI 从 SWF 批量导出并重命名为 linkageId，运行时无需 manifest 文件。

### 性能调度迁移（PerfDecisionEngine）
原 AS2 端的完整反馈控制回路（Kalman 滤波→PID→迟滞量化→执行器，~1400 行）已迁移到 C# launcher 端。

**迁移依据**：PID 被数学证明退化为阈值生成器（Proposition 1, 97.4% 积分饱和率），迟滞量化器是实际控制权威。

**架构**：
- **C# PerfDecisionEngine** (~250 行): 滑动窗口统计(mean5/trend10) + 直接阈值 + 2/3 非对称迟滞确认 + 方差自适应
- **AS2 PerformanceScheduler** (~250 行，薄壳): 采样 + FPS 广播 + 接收 P 指令执行 + 本地后备
- **P 前缀快车道** (C#→AS2): `P{tier}|{softU_x100}\0`，零 JSON 解析
- **失焦抑制**: WindowManager.IsFlashForeground() 门控，先于 panic 判定
- **前馈 hold**: 关卡脚本 setPerformanceLevel() 可挂起远程模式 N 秒
- **断线后备**: AS2 极简阈值降级 (FPS<15→tier=1)；15 秒无样本自动触发 warmup

### 存档权威迁移（Protocol 2）

自 2026-04-18 起，**存档权威从 AS2 迁到 Launcher**。启动期 Launcher 预先读并决议 shadow + SOL，通过 `bootstrap_handshake` 响应把 snapshot 直接下发给 Flash，彻底消除启动期 async I/O 等待。当前 v3.0 规则下，**同秒或更新的 shadow 会覆盖 SOL**，这样 Bootstrap editor / import 写入的 JSON 会在下次启动直接生效。

自 2026-04-22 起，**valid legacy SOL 不再只是“临时给 Flash 用”**：当 Resolver 返回 `Snapshot(source=sol)` 时，会立刻通过 `ArchiveTask` 复用同一条 `.tmp -> rename` 原子写路径，把归一化后的 snapshot 首次落盘为 `saves/{slot}.json`。Bootstrap `list/load/load_raw` 还会在标准 10 槽上先做一次 legacy 预热，因此外部用户即使还没“先进游戏存一次”，只要当前运行根下存在可解析的旧 SOL，也能直接在 launcher editor / 任务系统里看到 authority。

运行根边界也在同轮收紧：`resources/` 与 `CrazyFlashNight/` 继续保持物理隔离；`SolFileLocator` 只在**当前运行根**对应的 SharedObject 子树中搜索 `.swf` / `.exe` 两类历史路径，不再做跨根 glob；`rebuild` / legacy SOL 删除也只会作用于当前运行根。

**决议主路径**（`GameLaunchFlow.StartGame(slot)` / `Prewarm()` 锁外执行）：

```
SolResolver.Resolve(slot, swfPath)
   │
   ├─ [1] ArchiveTask.IsTombstoned(slot)  → "deleted"
   │
   ├─ [2] ArchiveTask.TryLoadShadowSync   → shadow 预置（失败不阻断）
   │
   ├─ [3] SolFileLocator.FindSolFile      → 定位 SOL 文件路径
   │       遍历 %APPDATA%\...\#SharedObjects\* 多 hash 子目录
   │       仅当前运行根：`.swf` drop-drive → `.swf` keep-drive
   │                    → `.exe` drop-drive → `.exe` keep-drive
   │                    → 当前根 root-scoped fallback
   │
   ├─ [4] SolParserNative.Parse           → Rust sol_parser.dll FFI
   │       AMF0 → JObject，0-based Reference 解析（round-trip 测试验证）
   │
   └─ [5] 版本分流：
         ├─ SOL 缺失 + shadow 有效     → Snapshot(json_shadow)
         ├─ SOL 缺失 + shadow 无效     → Empty
         ├─ soData._deleted == true    → Deleted
         ├─ mydata.version == "3.0"
         │    └─ MergeTopLevelKeys + ValidateResolvedSnapshot
         │        ├─ pass + shadow 新鲜（lastSaved >=）→ Snapshot(json_shadow)
         │        ├─ pass + shadow 更旧 / 无效         → Snapshot(sol)
         │        └─ fail → shadow 新鲜（lastSaved >=）则 Snapshot(json_shadow)
         │                   否则 Corrupt(v3.0_structure_invalid)
         ├─ mydata.version == "2.7"
         │    └─ Migrate_2_7_to_3_0（`mydata[3]` 缺失/null 先补 0）→ Validate
         │        ├─ pass → Snapshot(sol)
         │        └─ fail → DeferToFlash
         └─ pre-2.7
              └─ shadow 严格更新（>）→ Snapshot(json_shadow)，否则 DeferToFlash
```

当 `Snapshot(sol)` 成立时，Resolver 还会同步执行一次 authority seed：

```
ArchiveTask.TrySeedShadowSync(slot, normalizedSnapshot)
   └─ saves/{slot}.json.tmp → rename saves/{slot}.json
```

seed 失败只记日志，不改变 `bootstrap_handshake` 的决议结果；也就是说，seed 失败时 Flash 仍会按 `snapshotSource: "sol"` 启动。

决议结果（`SolResolveResult`）随 `bootstrap_handshake` 响应下发：

```json
{
  "task": "bootstrap_handshake",
  "success": true,
  "attemptId": "...",
  "savePath": "<slot>",
  "protocol": 2,
  "saveDecision": "snapshot" | "empty" | "deleted" | "needs_migration" | "corrupt",
  "snapshot":       /* 当 decision == snapshot：已验证的 mydata JObject */,
  "snapshotSource": "sol" | "json_shadow",
  "corruptDetail":  "v3.0_structure_invalid" | "sol_no_test_field" | ...
}
```

Flash 侧 `通信_fs_bootstrap.as` 把这些字段透传到 `_root._launcher*`，`SaveManager.preload()` 一次性消费（`_protocol2Consumed` 幂等锁覆盖 asLoader frame 4 + 主 FLA frame 63 双调用），然后：

- **snapshot**：`_root.mydata = snap` → `loadAll` 里直接走 `loadFromMydata` 快路径
- **deleted**：`so.clear(); so.data._deleted = true`，`_root.mydata = undefined`
- **empty**：`_root.mydata = undefined`（新游戏）
- **needs_migration / corrupt**：`_deferredResolutionAttempted = true` + `_skipPrefetch`，穿透到 AS2 同步 SOL 读取；若 SOL 也空则升格为 `_root._saveRestoreError = true` 走"存档损坏" UI

关键性能收益：原来 `loadAll` 内等待 launcher JSON prefetch 的自旋消失，实测 `preload → ready` 零等待。

**Launcher 侧复用的数据源**（`launcher/src/Save/` 六个文件）：

| 文件 | 职责 |
|------|------|
| `SolResolver.cs` | 决议入口，上述矩阵实现；`source=sol` 时触发 authority seed |
| `SolParserNative.cs` | sol_parser.dll P/Invoke（UTF-16 路径，UTF-8 JSON 回传） |
| `SolFileLocator.cs` | 多 hash 子目录；只搜当前运行根，兼容 `.swf + .exe` 父目录，不跨根 fallback |
| `SaveMigrator.cs` | 2.7→3.0 迁移（含 legacy 主线位补 0）+ MergeTopLevelKeys + ValidateResolvedSnapshot |
| `LegacyPresetSlotSeeder.cs` | Bootstrap `list/load/load_raw` 前预热标准 10 槽，把 valid legacy SOL 提前 seed 成 authority |
| `SaveResolutionContext.cs` | DI 聚合（传给 GameLaunchFlow / Bootstrap handlers） |

### ArchiveTask shadow 辅助链

shadow 链不仅是运行中存盘的 JSON 冗余副本，也是启动期 Resolver 的候选权威源。Bootstrap UI 的存档 CRUD / import / editor 全都写这条链；下次启动时，只要 shadow `lastSaved` 同秒或更新于 SOL，就会直接作为 `json_shadow` snapshot 下发给 Flash。

现在这条链还承担 **legacy authority 首导入**：

- `SolResolver` 返回 `Snapshot(source=sol)` 时，立即把归一化后的 snapshot 原子落盘到 `saves/{slot}.json`
- `ArchiveCommandHandler` 在 `list/load/load_raw` 前对标准 10 槽执行预热；若当前 authority 缺失但当前根存在 valid legacy SOL，会先 seed shadow 再继续现有查询逻辑
- 预热只覆盖 `crazyflasher7_saves` 到 `crazyflasher7_saves9`；自定义 legacy 槽名不在自动继承范围内
- root 隔离保持不变：每个 launcher 运行根只看自己的 `saves/` 与自己的 SharedObject 子树，不会跨 `resources/` / `CrazyFlashNight/` 互相读档或删档

**JSON 协议**（XMLSocket，async）：

| op | 方向 | 动作 |
|----|------|------|
| `shadow` | Flash → C# | 游戏内存盘时推 mydata JSON，落盘为 `saves/{slot}.json`（tmp + rename 原子写），附带前后快照语义 diff 发 warnings |
| `load` | Flash → C# | 按 slot 读 shadow JSON 返回；遇 tombstone 直接报错 |
| `load_raw` | Bootstrap → C# | 绕过 tombstone 读原始 JSON（editor 用） |
| `list` | Bootstrap → C# | 枚举所有 slot（合并 .json + .tombstone），带 corrupt/inconsistent/mainProgress 元信息 |
| `delete` | Bootstrap → C# | 原子写 `.tombstone` 再删 `.json` |
| `reset` | Bootstrap → C# | 清 launcher 副本 + tombstone（不清 SOL） |

**HTTP `/save-push`**（辅助接口，非启动主路径）：从 `saves/` 读指定 slot 的 JSON，通过 XMLSocket 推给 AS2（`save_push` task），可被外部工具用于调试/恢复。启动期恢复不走这条——主路径是 Protocol 2 的 `bootstrap_handshake` snapshot 下发。

一致性校验（`RunConsistencyCheck`）：每次 `shadow` 写入前，对比上次快照检测"角色名变化 / 等级倒退 / 金钱为负 / 版本降级"等可疑变动，附到 `warnings` 字段回传 Flash，不阻断写入但留痕。

### 进程生命周期加固
- **shutdown try-catch 保护**：每个 Dispose 步骤独立 try-catch，防止单点异常跳过后续清理
- **Flash 僵尸进程检测**：Socket 断连后 10s 内进程仍未退出则 ForceExit（Flash Player 20 SA 偶发退出卡死）
- **OnKillFlash 钩子**：退出前先 DetachFlash + AudioEngine.Shutdown + KillFlash，在 ExitThread 之前执行
- **ProcessManager 线程安全**：`_flashProcess` 访问加锁，`KillFlash()` 可多次安全调用
- **AppDomain.UnhandledException**：非 UI 线程未处理异常写日志

### GPU 锐化（实验性, 当前禁用）
目标：Flash 以 LOW 画质渲染降低 CPU 负担，外部 GPU CAS 锐化补偿画质。

已验证可行：
- BitBlt 捕获 Flash 帧 (0/300 黑帧, avg 2ms, p95 4ms)
- D3D11 off-screen CAS 处理 + staging 回读

待解决：将 GPU 处理后的帧显示到用户可见的 WinForms 面板（WM_PAINT 覆盖 / airspace 问题）。

### Flash UI → Web 迁移

以下 Flash 主文件实例已迁移到 Launcher WebView2 overlay，释放 Flash 内存并提高 GC 效率：

| Flash 实例 | Web 实现 | 协议 |
|-----------|---------|------|
| 弹出公告界面 (新任务横幅) | notch.js 通知条 `#quest-notice-bar` | `Utask\|{name}` (旧格式透传) |
| 弹出公告界面 (公告) | notch.js 通知条 | `Uannounce\|{text}` (旧格式透传) |
| 任务完成提示 | notch.js 通知条完成态 (❗ 图标呼吸 + 整条可点击) | `td:0/1` + `tdh:<hotspotId>` + `tdn:0/1` (KV 帧同步) |
| 地图界面（旧右上角小地图位） | `map-hud.js` 右上角 HUD + `map-panel.js` 全屏地图面板 | `mm/mh` (KV 帧同步) + `TASK_MAP` click |
| 功能按钮界面 (装备/任务) | `#quest-row` 工具条按钮行 | `cmd` gameCommand |
| 存盘动画 | ✕ 按钮状态变化 (·· → ✓) | `sv:1/2` (KV 帧同步) |
| 安全退出界面 | `#safe-exit-panel` 面板 | `sv:1/2` + `EXIT_CONFIRM` click |
| 帮助界面 (帮助界面.swf) | Panel 系统 `help-panel.js` (Markdown tab) | Bridge → C# panel_cmd open help |
| K点商城 (旧商城界面 MC 已退役) | Panel 系统 `kshop.js` (商品/购物车/领取) | `SHOP` → `kshop`，ShopTask 双层 callId 桥接 (Web↔Flash) |

**右上角工具条布局**：
```
┌──────────────────────┬────────┐
│ ⚙  🔧  ⏸  ?  ✕      │ 基地   │
├──────────────────────┤ 线框概览│
│ ☰ 装备  │  ☰ 任务   │ 当前区块│
├──────────────────────┤        │
│ [❗] 任务已达成·交付  │        │
├──────────────────────┤        │
│ ♪ 点歌  未播放        │        │
└──────────────────────┴────────┘
```

最右侧 `80px` 窄列现在由 `map-hud.js` 占用，直接复用 `map-panel-data.js` 的热点/scene 几何；AS2 只经 UiData 推 `mm`（模式）和 `mh`（当前 hotspotId），HUD 只做当前区块高亮 + 固定 beacon 点，点击后走 `TASK_MAP` 打开全屏地图 panel。

**通知条状态机**：隐藏 → (新任务/公告到达) → 播放通知 → (队列空+td:1) → 完成态常驻 → (td:0) → 隐藏。完成态图标持续呼吸脉冲 (`icon-breathe`)。

**任务条点击分派**：完成态整条 `#quest-notice-main` 可点击。`tdh` 非空且 `tdn=1`（非战斗地图 + hotspot 在 `NAVIGATE_TARGETS` + 所在组已解锁）时，右侧 `⇨` 装饰亮起，点击发 `TASK_DELIVER` → C# 转发 `navigateToHotspot` gameCommand → AS2 `MapPanelService.navigateToHotspot` 直传到 NPC 所在地图；否则退化为 `TASK_UI` 打开任务栏。

### 面板系统（Panel System）

本节最后核对代码基线：commit `cc25c357d`。

全屏遮罩面板框架，用于承载需要独占交互的复杂 UI（商城、帮助、调试小游戏等），取代 Flash MovieClip 弹窗。

**架构**：
```
按钮点击 (SHOP/HELP/DEV PANEL)
    ↓
C# LauncherCommandRouter.Dispatch / RequestOpenPanel
    ↓
useNativeHud=true: PanelHostController.OpenPanel
    FlashSnapshot → backdrop → HUD suspend → WebOverlay panelRect opaque
useNativeHud=false: PostToWeb panel_cmd open + _activePanel fallback
    ↓
JS Panels.open(id) → 创建/显示面板 DOM → 遮罩 + ESC 支持
    ↓ (ESC)
C# KeyboardHook / PanelHost ESC source → panel close / panel_esc
    ↓ (关闭)
JS Bridge.send({cmd:'close', panel:id}) → C# HandlePanelMessage → PanelHost/WebOverlay 回 idle
```

**面板类型**：
- **kshop**（K 点商城）: 唯一支持入口为 Launcher `SHOP` → Web Panel；旧 Flash `shopMainMC` 已退役。面板需要 Flash 交互；打开/关闭会走 `shopPanelOpen/shopPanelClose`，并参与 `_pauseNeedsRestore`
- **help**（游戏帮助）: 纯 Web 侧 Markdown 帮助面板，不触发 Flash 暂停恢复
- **map**（地图面板）: `web/modules/map-panel.js` + `web/modules/map-panel-data.js` + `web/modules/map-fit-presets.js`；纯 Web panel，走 `panel/panel_resp` 的 `snapshot` / `refresh` / `navigate` / `close` 协议；当前 `snapshot` 额外承载 `unlocks / hotspotStates / currentHotspotId / markers / tips`，四个正式页面均已切到 `assembled` 场景拼接模式，右侧层级按钮缺少原始素材时允许直接使用 Web/CSS 复刻旧视觉语言；同时支持 browser harness `web/modules/map/dev/harness.html`、preview `web/modules/map/dev/preview.html`、builder `web/modules/map/dev/builder.html`、CLI 导出 `tools/export-map-manifest.js`、fallback 复核 `tools/audit-map-layout.js`、filter-fit 离线调优 `tools/tune-map-filter-fit.js`、审计图导出 `tools/render-map-audit-sheet.py` 与可选的 Kimi 视觉复核 `tools/kimi-map-review.ps1`，并在紧凑视口下自动缩放舞台、按 page/filter preset 做二次 content-fit；右上角常驻 HUD 由 `web/modules/map-hud.js` 消费同一份 `MapPanelData` + UiData `mm/mh`，只显示当前区块高亮与固定 beacon，点击后打开 map panel
- **stage-select**（选关界面 Stage 2 runtime）: `web/modules/stage-select-panel.js` + generated `web/modules/stage-select-data.js`；可通过 Native HUD “其他 → 选关测试” 的 `STAGE_SELECT_TEST` 打开，也可由 AS2 场景门 `openWebStageSelect` → `panel_request stage-select` 正式打开。支持 16 个 frame label、167 个源 XML 选关按钮实例、152 个 Web 运行时去重渲染实例、fixture 锁定/任务/挑战模式、按外部 PNG / 内部命名帧 / 默认帧回退的 hover 预览、browser harness 和 FFDec/Web 视觉对照审计；runtime 下使用 `stageSelectSnapshot` 读取真实解锁/挑战状态，难度按钮通过 `stageSelectEnter` 进入已解锁关卡，`localFrame` 通过 `jump_frame` / `stageSelectJumpFrame` 同步 AS2 frame，return 类 nav 只关闭 panel。runtime 布局隐藏测试标题、fixture/dev 控件与右侧空栏，frame tab 默认收纳到可展开区域菜单。它不迁移外交 / 委托任务界面，旧 Flash `关卡地图` 保留为 fallback
- **intelligence**（情报详情面板）: `web/modules/intelligence-panel.js`；正式入口为 Native HUD / 旧 Web notch 主工具栏的 `情报` / `INTELLIGENCE`，打开 `mode:"prod", source:"runtime"`；开发入口 `其他 → 情报测试` / `INTELLIGENCE_TEST` 保留。正式 runtime 走 `panel/panel_resp` 的 `state` / `snapshot(itemName)` / `tooltip(itemName)` / `close` 协议：C# `IntelligenceTask` 读取真实 `data/dictionaries/information_dictionary.xml`、`data/items/收集品_情报.xml` 与固定目录 `data/intelligence/<itemName>.txt`，Flash 只返回 `_root.收集品栏.情报.toObject()`、解密等级、玩家名和 TooltipComposer 富文本，Web 不直接 fetch 项目根或 `data/`。正式打开先拉 `state` 小包合并本地 catalog，右侧目录显示每条情报独立 `value/unlockedCount/pageCount/iconName`，点击目录才请求选中项 `snapshot`；锁定页正文不下发。Dev/harness 仍保留 `bundle` / `catalog` / 显式 `snapshot(value, decryptLevel, pcName)` 兼容路径，用于第一阶段全量 fixture 和视觉回归。图标使用 `icons.js` / `icons/manifest.json` 解析首帧图标，优先 `iconName`、再回退情报名；阅读器渲染 legacy txt 的分页、收集进度、解密/密文视图、`${PC_NAME}` 替换和 `b/strong/u/i/font[color]/br` 白名单标签；目录 hover 复用 `tooltip.js` 的 `PanelTooltip.showAtMouse/followMouse/hide/updateContent`，基础 tooltip 立即显示，AS2 `intelligenceTooltip` 返回后刷新富文本。关闭时不通知 Flash。视觉对齐旧 Flash 情报窗：深灰标题栏、纸张点阵阅读区、底部箭头翻页；browser harness 为 `web/modules/intelligence/dev/harness.html`
- **lockbox**（开锁小游戏）: `web/modules/minigames/lockbox/` 下的正式小游戏模块；支持运行时参数、browser harness、Node QA
- **pinalign**（定位小游戏）: `web/modules/minigames/pinalign/` 下的正式小游戏模块；和 Lockbox 共用小游戏壳层与 QA 平台
- **gobang**（五子棋小游戏）: `web/modules/minigames/gobang/` 下的正式小游戏模块；Web core 负责规则裁判，AI 经 Web→C# `gomoku_eval` 调用 `GomokuTask` / Rapfi
- **jukebox**（BGM 点歌台）: `web/modules/panels/jukebox-panel.js` 注册 `Panels.register('jukebox')`，由 `RightContextWidget` 的 jukebox titlebar 展开按钮 → `JUKEBOX_EXPAND` → `LauncherCommandRouter.OpenPanel("jukebox")` 触发；与 kshop/help 等通用 panel 同走完整 backdrop / EX_STYLE / HUD-suspend 序列。PanelLayoutCatalog 用基准 880×620 设计尺寸 + `anchor.Height / 576` 等比缩放（与 `Hud.WidgetScaler.DESIGN_HEIGHT` 同源）：1024×576 design viewport 下宽 880 / 高被 Centered clamp 到 576；1920×1080 anchor 下宽 1650（占比 86%）/ 高 clamp 到 1080。`jukebox-panel.js` 用 inset 百分比布局对 panelRect 任意尺寸鲁棒。曲库 / UiData 状态在 onOpen 时通过 `cmd:'requestCatalog'` + `UiData.get` seed 当前值，避免晚注册错过历史推送。close 路径收敛：× 按钮 / ESC / backdrop click 三入口共用 `closeLocally`（先 `Panels.close()` 让 `_active` 复位再 `Bridge.send panel close`）——避免 ESC/backdrop 单独走 onRequestClose 时 `_active` 滞留导致下次 open 早 return

#### Jukebox panel 手测

`useNativeHud=true` 启动游戏，进到游戏就绪后逐项验证：

1. **Titlebar 入口**：`RightContextWidget` 右侧 jukebox titlebar 可见、mini wave 流动、当前曲名显示；点 expand → panel 出现
2. **panel 缩放跟随**：panel 居中显示且尺寸跟 anchor 同比缩放（基准 880×620 × `anchor.Height/576`，高度通常被 Centered clamp 到 anchor.Height 全高）——1024×576 anchor 下 ~880×576、1920×1080 anchor 下 ~1650×1080；周围有 backdrop dim；Spy++ 验证 WebOverlay hwnd bounds **不是全 anchor**（宽度小于 anchor.Width）、EX_STYLE 既无 `WS_EX_LAYERED` 也无 `WS_EX_TRANSPARENT`
3. **打开 seed 状态**：当前正在播放的曲目标题立刻显示在 panel 标题区（不是 `未播放`）；音量滑条显示当前实际值；覆盖关卡BGM / 真随机 / 播放模式 选中态正确
4. **曲库列表**：专辑下拉显示所有专辑 + 计数；切换专辑过滤；当前播放曲目高亮 active
5. **选曲**：点击曲目立即切歌；标题更新；进度条归零；含特殊字符（`"` / `\` / 中英混排）的曲名正确发到 AS2（`HandleJukeboxMessage` 已用 JObject 解析）
6. **播放控制**：暂停 ↔ 继续按钮翻转；停止回到默认 BGM；进度条拖拽 seek 立即生效
7. **设置**：覆盖关卡BGM / 真随机切换；播放模式三选一切换；AS2 端通过 `setGlobalVolume`/`setBGMVolume`/`jukeboxOverride` 等收到对应命令
8. **帮助 markdown**：点 `?` 弹模态加载 `sounds/README.md` 渲染；关闭模态正常
9. **关闭面板（× / ESC / backdrop 三路径全测）**：右上 ×、ESC 键、点 panel 外侧 backdrop 三种入口都立即隐藏 panel（DOM 即刻消失）+ WebView2 SW_HIDE 回到 idle；任一入口关闭后再次打开 panel **必须 onOpen 正常触发**（不能因 panels.js `_active` 滞留早 return）——验证：关 → 立刻 expand 重开，UI 应正常 seed 当前 bgm 标题，不是空 panel
10. **重开干净**：关 panel 后再开，**不**显示上一次曲名/进度/音量瞬态（cleanup 已重置 `bgmTitle/currentDuration/progress/wave`；onOpen 重新 seed）
11. **不漏 listener**：30 次 open/close 循环后 launcher.log 无累积；`Bridge.off` 正确解绑（uidata 走 `UiData.off`）
12. **legacy 不污染**：[overlay.html](web/overlay.html) 的 `modules/jukebox.js` 脚本入口已注释；DevTools console 无 `audio` / `catalog` 双重处理日志

无法通过手测验证的回归（如 idle iGPU 下降）走 `Ctrl+G` 探针 + Task Manager GPU 标签人工对照。

**通用模块**：
- `panels.js`: 面板注册/生命周期管理 (register/open/close/force_close)
- `tooltip.js`: hover 跟随 + anchored 锚定两种模式，AS2 HTML 转换；商城和情报 runtime tooltip 共用
- `icons.js`: 物品图标 manifest 加载 + 名称→URL 解析，情报详情面板也复用该入口
- `web/modules/minigames/shared/host-bridge.js`: 小游戏 → 宿主的统一桥接
- `web/modules/minigames/shared/minigame-shell.css`: 小游戏共享结构样式

**小游戏宿主协议**：
- Lockbox / Pinalign / Gobang 统一使用共享 session envelope，不再维护分游戏 session 命令名
- 统一发 `Bridge.send({ type:'panel', cmd:'minigame_session', payload:{ game, kind, data } })`
- 生命周期约定：
  - `open`: 面板已打开，只保证 `data.requested`
  - `ready`: 状态已建立，`data.requested` / `data.resolved` / `data.metrics` 都必须存在
  - `close`: 带最后一次已知 `phase` / `metrics`
  - `turn` / `result` / `export`: 沿用各游戏语义，但都走同一 envelope
- Gobang AI 额外走 Web panel → C# `gomoku_eval`：`{ type:'panel', panel:'gobang', cmd:'gomoku_eval', callId, payload:{ moves, timeLimit, ruleset } }`；响应为同 `callId` 的 `panel_resp`，`moves` 为 `[[x,y,role],...]`，`role` 使用 `1` 黑 / `-1` 白

**状态机**：`useNativeHud=true` 时 panel 打开状态以 `PanelHostController.ActivePanelName` 为主；`useNativeHud=false` 仍保留 WebOverlayForm `_activePanel` fallback（`null` → `"kshop" / "help" / "map" / "stage-select" / "intelligence" / "lockbox" / "pinalign" / "gobang" / ...` → `null`）。当前只有 `kshop` 会在断连或强制关闭路径里设置 `_pauseNeedsRestore`；其余纯 Web / dev panel 只做面板生命周期管理，不触发 Flash 暂停恢复。

**热重载恢复**：`_uiDataSnapshot` 按 KV key 维护最新值快照，WebView2 热重载后 `FlushUiDataBuffer` 先回放完整快照，确保 game-ready 等关键状态不丢失。

**维护约束**：凡是小游戏、地图 panel、stage-select panel、intelligence panel、Native HUD/PanelHost 的目录迁移、宿主协议变更、QA 入口变化，必须同步更新本 README 的目录树、测试入口和本节协议说明；模块内细节留在各自模块 README / 设计文档。
