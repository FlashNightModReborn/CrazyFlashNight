# CF7:ME Guardian Launcher

C# WinForms 守护进程，承担游戏启动全链：正常模式先做 WebView2 预检，再尽早构造 `GuardianForm`，随后完成 Steam 校验、Flash trust 租约、音频与总线初始化，最后由 BootstrapPanel 的 `list → ready → prewarm → reveal` 链路切入 Flash Player SA 运行态；同时承载 V8 脚本总线、HTTP / XMLSocket 通信和启动前存档决议（Protocol 2）。

> **文档角色**：Guardian Launcher 子系统的 canonical deep doc。项目总览见 [../README.md](../README.md)，顶层任务路由见 [../AGENTS.md](../AGENTS.md)。高变动章节按各自 commit 基线维护。
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
   ├─ `ToastOverlay` / `V8Runtime` / `FrameTask` / `NotchOverlay`
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

按 commit `9f8f0c225`（2026-04-20）时的源码树整理。只列追踪目录；`bin/` / `packages/` / `target/` / `node_modules/` / `obj/` 等构建产物和缓存均由 .gitignore 管理。后续若需复核本节，优先看 `git diff 9f8f0c225..HEAD -- launcher/`。

```
launcher/
├── CRAZYFLASHER7MercenaryEmpire.csproj   C# 项目文件
├── packages.config                        NuGet 包清单
├── build.ps1                              总构建脚本（10 阶段，见下文）
├── setup-check.ps1                        构建/运行前依赖自检（Targeting Pack / MSBuild / nuget / WebView2）
├── app.ico                                应用图标
│
├── src/
│   ├── Program.cs                         入口：正常模式先做 WebView2 预检，再尽早构造 GuardianForm；随后初始化 Steam/Trust/总线并接 GameLaunchFlow
│   │
│   ├── Config/
│   │   ├── AppConfig.cs                   config.toml 解析（flashPlayerPath/swfPath/gpuSharpening/sharpness）
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
│   │   ├── ToastOverlay.cs                GDI+ toast 消息（WS_EX_TRANSPARENT）
│   │   ├── NotchOverlay.cs                GDI+ 刘海栏（选择性穿透, 状态机）
│   │   ├── HitNumberOverlay.cs            GDI+ 伤害数字
│   │   ├── WebOverlayForm.cs              WebView2 视觉层（WS_EX_TRANSPARENT）
│   │   ├── InputShieldForm.cs             幽灵输入层（GDI+ α 命中 + CDP 注入）
│   │   ├── IToastSink.cs / INotchSink.cs  Toast / Notch 抽象接口
│   │   ├── FlashCoordinateMapper.cs       Flash 舞台坐标 ↔ 屏幕坐标
│   │   ├── FpsRingBuffer.cs               FPS 环形缓冲 + 场景重置
│   │   ├── PerfDecisionEngine.cs          性能决策（滑动窗口 + 迟滞，替代 AS2 Kalman/PID）
│   │   ├── HotkeyGuard.cs                 独立进程源码（csc 单独编译为 hotkey_guard.exe）
│   │   ├── KeyboardHook.cs                进程内 WH_KEYBOARD_LL（ESC 路由 + Ctrl+F 兜底；失败 fallback RegisterHotKey）
│   │   │
│   │   └── Handlers/                      【BootstrapMessageHandler 拆分后的 cmd handler 集】
│   │       ├── BootstrapCommandHelpers.cs  共享工具：PostResp / PostError / DispatchArchive / RequireIdleOrTearDown 等
│   │       ├── LifecycleCommandHandler.cs  ready / ping / cancel_launch
│   │       ├── GameStateCommandHandler.cs  start_game / rebuild / reveal_ok / retry
│   │       ├── ArchiveCommandHandler.cs    list / delete / load / load_raw
│   │       ├── DataEditCommandHandler.cs   save / reset / export（共享 RequireIdleOrTearDown 守卫）
│   │       ├── ImportCommandHandler.cs     import_start / import_commit
│   │       ├── UiCommandHandler.cs         logs / open_saves_dir
│   │       └── ConfigCommandHandler.cs     config_set（Plan A+：currentValue 权威下发 + requestId 相关 id）
│   │
│   ├── Bus/
│   │   ├── XmlSocketServer.cs             TCP 服务器（8 入站前缀 + 1 出站前缀 + JSON 双通道）
│   │   ├── HttpApiServer.cs               HTTP REST（10 端点，详见 HTTP API 节）
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
│   │   ├── ISolParser.cs / ISolFileLocator.cs / IArchiveStateProbe.cs / IArchiveShadowWriter.cs
│   │   └── SaveResolutionContext.cs       DI 聚合（resolver + archive + swfPath + legacy seeder）
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
│   ├── assets/                            引导页图片与媒体
│   │   ├── bg/                            背景图层资源
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
│       ├── jukebox.js                     BGM 点歌器（波形/seek/专辑）
│       ├── panels.js                      通用面板生命周期（register/open/close/ESC）
│       ├── tooltip.js                     Tooltip（hover/anchored）
│       ├── icons.js                       图标 manifest 加载与解析
│       ├── kshop.js                       K 点商城面板（ShopTask 双层 callId）
│       ├── help.js / help-panel.js        帮助系统（顶层入口 + 面板骨架）
│       ├── map-panel.js / map-panel-data.js / map-fit-presets.js / map-hud.js 地图系统（正式 map panel + 静态页面/热点数据 + filter fit preset 表 + 右上角常驻 HUD）
│       ├── map/
│       │   └── dev/
│       │       ├── harness.html           地图 panel browser harness + QA suite
│       │       ├── builder.html           地图可视化构建器入口（跳转到 builder 模式 preview）
│       │       └── preview.html           地图 manifest 预览 / 校准页
│       └── minigames/
│           ├── shared/                    小游戏共享层（host-bridge + minigame-shell + shared/dev QA 基础层）
│           ├── lockbox/                   开锁小游戏（core/dev + lockbox-audio/panel/css/README）
│           └── pinalign/                  定位小游戏（core/adapter/app/dev/reference + audio/panel/css/README）
│
├── tests/                                 【xUnit 2.4.2 C# 单测，见测试基建节】
│   ├── Launcher.Tests.csproj              legacy csproj + packages.config（net462 对齐主工程）
│   ├── packages.config                    xunit / xunit.runner.console / xunit.runner.visualstudio
│   ├── run_tests.ps1                      双段 nuget restore + msbuild + xunit.console
│   ├── SanityTests.cs                     基建冒烟
│   ├── Save/                              SaveMigratorTests.cs / SolResolverTests.cs
│   └── Bus/                               MessageRouterTests.cs（锁定当前观察行为）
│
├── docs/
│   └── phase1-owner-matrix.md             （Phase 1 所有权/职责矩阵归档）
│
└── tools/
    ├── lockbox-bake.js                    Lockbox 变体池离线生成工具（写入 web/data/lockbox-variants.json）
    ├── run-minigame-qa.js                 小游戏 Node QA 入口（lockbox / pinalign / all）
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

### build.ps1 实际 10 阶段流程

脚本代码里的阶段编号是"历史叠加式"（原始 4 步之上 insert 1.5/1.8/1.9/3.5，后又扩到 6），文字头写的 `[Step N/4]` 与 `[Step N/6]` 并非分母变化、而是遗留。**实际执行阶段如下**：

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
| 6    | fail-fast 校验 `launcher/web` 运行时必需集：`bootstrap.html` / `bootstrap-main.js` / `overlay.html` / `config/version.js` / `assets/bg/manifest.json` / `assets/intro.mp4` / `help/*.md` / `icons/manifest.json` / `data/lockbox-variants.json` / 关键 `modules/*` 与 minigame 入口文件；缺失直接 exit 1 |

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

当前 `Launcher.Tests.csproj` 直接编译 6 个测试源码文件；`SaveMigratorTests` 继续使用代码内 helper 数据，没有额外的 `Fixtures/SaveMigrator/` 外部 fixture 目录。

| 文件 | 覆盖面 | `[Fact]` 数量 |
|------|--------|---------------|
| `Save/SaveMigratorTests.cs` | undefined→2.6→2.7→3.0 迁移链 + MergeTopLevelKeys + ValidateResolvedSnapshot 结构校验 | 29 |
| `Save/SolResolverTests.cs` | tombstone / shadow / v3.0 / v2.7 / pre-2.7 / parse 失败等决议矩阵，外加首导入 authority / seed 失败边界 | 21 |
| `Save/SolFileLocatorTests.cs` | 当前运行根 `.swf/.exe` 解析顺序、root-scoped fallback、跨根隔离、删除范围 | 4 |
| `Save/LegacyPresetSlotSeederTests.cs` | 标准 10 槽预热、已有 authority 跳过、批量预热只探测缺失槽 | 3 |
| `Bus/MessageRouterTests.cs` | 协议分发 + callId wrap + error 构造，**锁定当前观察行为**（异常冒泡 / respond 无去重） | 15 |
| `SanityTests.cs` | 基建冒烟 | 2 |

### Web QA 与开发 harness

本节最后核对代码基线：commit `9f8f0c225`。

小游戏测试不走 `launcher/tests/`，地图 panel 的 DOM / 布局 / 交互回归也不走 C# 单测；统一按各模块自带的 QA 入口执行：

- **Node QA**：`node tools/run-minigame-qa.js --game lockbox|pinalign|all`
  - 实际入口文件：`tools/run-minigame-qa.js`
  - 共享 runner：`web/modules/minigames/shared/dev/node-qa-runner.js`
  - 适用场景：纯逻辑、确定性、导出结构、回归脚本
- **Browser harness**：直接打开各自 `dev/harness.html`
  - `web/modules/minigames/lockbox/dev/harness.html`
  - `web/modules/minigames/pinalign/dev/harness.html`
  - `web/modules/map/dev/harness.html`
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
  - 用于阻止旧 `modules/lockbox-*.js`、旧 `lockbox_session/pinalign_session`、旧共享结构 class 名回流

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

只 4 个 key 会被识别，缺失即落代码默认：

```toml
flashPlayerPath = "Adobe Flash Player 20.exe"
swfPath = "CRAZYFLASHER7MercenaryEmpire.swf"

# GPU CAS 锐化（实验性）— 当前代码中该字段无消费者，pipeline 待完善。
# 保留为未来 feature flag；写什么都不影响当前运行行为。
gpuSharpening = false
sharpness = 0.5
```

代码默认（[AppConfig.cs:23-26](src/Config/AppConfig.cs#L23)）：`GpuSharpeningEnabled = true`, `Sharpness = 0.5`。示例显式写 `false` 是遵循正文「当前禁用」语义，等 pipeline 接上以后再统一默认。

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

**reveal 成功 = panel swap，不是 Form 切换**：BootstrapPanel.SetPanelVisible(false) + FlashHostPanel.Visible=true + readyWiring。BootstrapPanel 不会 Dispose，仍在同一 GuardianForm 里，只是不可见。**代码库没有任何让它在 Ready 之后重新显形的路径**。

**Ready 后的退出路径**：

| 触发 | 处理 |
|------|------|
| Flash 进程正常退出 | `OnFlashExited` → `form.ForceExit()` → **整个 Launcher 一起退出** |
| socket 断连 10s + Flash 仍活 | Zombie 兜底 → `form.ForceExit()` → 同上 |

**活跃启动态（非 Ready）出错**：Flash 异常 → `TransitionToError("flash_exited")`。BootstrapPanel 还可见，玩家可在 Error 态 `retry` 回到 Idle 重试，或 `cancel_launch` 回 Idle 自己改。

玩家想"换槽位"还是要退 launcher 重启，这一点和旧模型一致；只是"显隐切换"从 Form.Show/Hide 变成了 Panel.SetPanelVisible。

## 关键设计决策

### Flash 嵌入（SetParent）
Guardian 通过 Win32 `SetParent` 将 Flash Player SA 窗口嵌入 `_flashPanel`（WinForms 自绘 D3DPanel），移除标题栏/边框/菜单栏。500ms 看门狗定时器检测全屏等操作导致的脱离并自动重新嵌入。

### 双通道通信

**XMLSocket**（TCP，`\0` 分隔 JSON）：Flash 原生支持，承载 IPC 主流量。除了 JSON 路由还有 8 个入站快车道前缀（见架构概览节）+ 1 个出站前缀（`P`，C#→AS2）。

**HTTP API**（REST，10 个端点）：

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

**BGM 可视化 + 点歌器**：`PeakDetector` 自定义节点（`ma_node_vtable` passthrough）插入 bgmGroup → engine endpoint 之间，实时采样 L/R peak。C# 60ms 轮询 `ma_bridge_bgm_get_peak/cursor/length/is_playing` → WebView2 `PostWebMessageAsJson` → `jukebox.js` 渲染滚动波形 + 进度条（可拖拽 seek）。点歌器面板含专辑浏览、选曲播放、设置菜单（覆盖关卡BGM / 真随机）和帮助按钮。曲目标题由 AS2 `pushUiState("bgm:title")` 经 UiData 通道推送，设置状态由 `jbo:/jbr:` 通道同步。

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
| K点商城 (商城界面 MC) | Panel 系统 `kshop.js` (商品/购物车/领取) | ShopTask 双层 callId 桥接 (Web↔Flash) |

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

本节最后核对代码基线：commit `9f8f0c225`。

全屏遮罩面板框架，用于承载需要独占交互的复杂 UI（商城、帮助、调试小游戏等），取代 Flash MovieClip 弹窗。

**架构**：
```
按钮点击 (SHOP/HELP/DEV PANEL)
    ↓
C# HandleButtonClick → 设置 _activePanel → PostToWeb panel_cmd open
    ↓
JS Panels.open(id) → 创建/显示面板 DOM → 遮罩 + ESC 支持
    ↓ (ESC)
C# KeyboardHook._panelEscEnabled → PostToWeb panel_esc → Panels.triggerRequestClose
    ↓ (关闭)
JS Bridge.send({cmd:'close', panel:id}) → C# HandlePanelMessage → 按面板 ID 路由
```

**面板类型**：
- **kshop**（K 点商城）: 需要 Flash 交互；打开/关闭会走 `shopPanelOpen/shopPanelClose`，并参与 `_pauseNeedsRestore`
- **help**（游戏帮助）: 纯 Web 侧 Markdown 帮助面板，不触发 Flash 暂停恢复
- **map**（地图面板）: `web/modules/map-panel.js` + `web/modules/map-panel-data.js` + `web/modules/map-fit-presets.js`；纯 Web panel，走 `panel/panel_resp` 的 `snapshot` / `refresh` / `navigate` / `close` 协议；当前 `snapshot` 额外承载 `unlocks / hotspotStates / currentHotspotId / markers / tips`，四个正式页面均已切到 `assembled` 场景拼接模式，右侧层级按钮缺少原始素材时允许直接使用 Web/CSS 复刻旧视觉语言；同时支持 browser harness `web/modules/map/dev/harness.html`、preview `web/modules/map/dev/preview.html`、builder `web/modules/map/dev/builder.html`、CLI 导出 `tools/export-map-manifest.js`、fallback 复核 `tools/audit-map-layout.js`、filter-fit 离线调优 `tools/tune-map-filter-fit.js`、审计图导出 `tools/render-map-audit-sheet.py` 与可选的 Kimi 视觉复核 `tools/kimi-map-review.ps1`，并在紧凑视口下自动缩放舞台、按 page/filter preset 做二次 content-fit；右上角常驻 HUD 由 `web/modules/map-hud.js` 消费同一份 `MapPanelData` + UiData `mm/mh`，只显示当前区块高亮与固定 beacon，点击后打开 map panel
- **lockbox**（开锁小游戏）: `web/modules/minigames/lockbox/` 下的正式小游戏模块；支持运行时参数、browser harness、Node QA
- **pinalign**（定位小游戏）: `web/modules/minigames/pinalign/` 下的正式小游戏模块；和 Lockbox 共用小游戏壳层与 QA 平台

**通用模块**：
- `panels.js`: 面板注册/生命周期管理 (register/open/close/force_close)
- `tooltip.js`: hover 跟随 + anchored 锚定两种模式，AS2 HTML 转换
- `icons.js`: 物品图标 manifest 加载 + 名称→URL 解析
- `web/modules/minigames/shared/host-bridge.js`: 小游戏 → 宿主的统一桥接
- `web/modules/minigames/shared/minigame-shell.css`: 小游戏共享结构样式

**小游戏宿主协议**：
- Lockbox / Pinalign 不再各自发 `lockbox_session` / `pinalign_session`
- 统一发 `Bridge.send({ type:'panel', cmd:'minigame_session', payload:{ game, kind, data } })`
- 生命周期约定：
  - `open`: 面板已打开，只保证 `data.requested`
  - `ready`: 状态已建立，`data.requested` / `data.resolved` / `data.metrics` 都必须存在
  - `close`: 带最后一次已知 `phase` / `metrics`
  - `turn` / `result` / `export`: 沿用各游戏语义，但都走同一 envelope

**状态机 (_activePanel)**：`null` → `"kshop" / "help" / "lockbox" / "pinalign" / ...` → `null`。当前只有 `kshop` 会在断连或强制关闭路径里设置 `_pauseNeedsRestore`；其余纯 Web / dev panel 只做面板生命周期管理，不触发 Flash 暂停恢复。

**热重载恢复**：`_uiDataSnapshot` 按 KV key 维护最新值快照，WebView2 热重载后 `FlushUiDataBuffer` 先回放完整快照，确保 game-ready 等关键状态不丢失。

**维护约束**：凡是小游戏或地图 panel 的目录迁移、宿主协议变更、QA 入口变化，必须同步更新本 README 的目录树、测试入口和本节协议说明；模块内细节留在各自模块 README / 设计文档。
