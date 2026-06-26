# CF7:ME Guardian Launcher

C# WinForms 守护进程，承担游戏启动全链：正常模式先做 WebView2 预检，再尽早构造 `GuardianForm`，随后完成 Steam 校验、Flash trust 租约、音频与总线初始化，最后由 BootstrapPanel 的 `list → ready → prewarm → reveal` 链路切入 Flash Player SA 运行态；同时承载 V8 脚本总线、HTTP / XMLSocket 通信和启动前存档决议（Protocol 2）。

> **文档角色**：Guardian Launcher 子系统的 canonical deep doc。项目总览见 [../README.md](../README.md)，顶层任务路由见 [../AGENTS.md](../AGENTS.md)。高变动章节按各自 commit 基线维护。
> **最后核对代码基线**：commit `07a0a09d9f`（2026-06-25）。
> **新接手阅读顺序**：本节 → [架构概览](#架构概览)（启动时序 + 运行态面板栈）→ [Bootstrap 前端与协议](#bootstrap-前端与协议)（cmd 表 + reveal gate + config_set）→ [存档权威迁移 (Protocol 2)](#存档权威迁移-protocol-2)。其余章节继续展开音频 / 性能调度 / GPU / UI 迁移 / 面板系统等运行时细节。
> **路径约定**：正文与代码块中以裸 `tools/` 开头的脚本路径，除 `launcher/tools/` 下三个小游戏工具（`lockbox-bake.js` / `run-minigame-qa.js` / `validate-minigame-final-state.js`）外，**默认相对仓库根**（`launcher/` 的上一级，从仓库根执行）；跨出 launcher 的 markdown 链接统一用 `../`。

## 技术栈

| 项目 | 版本/说明 |
|------|-----------|
| 运行时 | **.NET 10 (`net10.0-windows`)**, x64, **FDD (framework-dependent)** + 用户面 native C++ bootstrap |
| 语言 | C# (`LangVersion=latest`，对齐 .NET 10) for Core；C++ (Win32-only，no STL) for bootstrap |
| SDK pin | [`global.json`](../global.json) at repo root, `version: 10.0.300` + `rollForward: latestPatch` |
| UI | WinForms (`UseWindowsForms=true`, WinExe) 单窗体（GuardianForm）+ WebView2（BootstrapPanel 引导页 + WebOverlayForm 运行态 overlay） |
| 构建 | **`dotnet publish --self-contained false`**（FDD，~37MB / ~21 文件入 git）+ MSVC `cl.exe`（miniaudio + bootstrap）+ Rust/Cargo (sol_parser cdylib) + Node.js/npm (TypeScript 编译 V8 脚本) |
| 包管理 | **PackageReference + [`Directory.Packages.props`](Directory.Packages.props)** 中心化版本锁定（`ManagePackageVersionsCentrally=true`） |
| GPU 检测 | **`Vortice.DXGI` 3.6.2**（SharpDX 团队接力的社区项目，1:1 替代 SharpDX.DXGI） |
| 音频 | miniaudio (Unlicense, 单头文件 C 库 → native DLL, WASAPI) |
| 存档解析 | Rust `sol_parser.dll`（flash-lso git pin `4b049ff3`），AMF0 → JSON |
| JS 引擎 | ClearScript 7.4.5 (Chromium V8, 替代 Node.js vm2) |
| Web 覆盖层 | WebView2 1.0.3856.49 (Evergreen Runtime, 幽灵输入解耦架构) |
| JSON | Newtonsoft.Json 13.0.3 |
| 测试框架 | **xUnit 2.9.2** + Microsoft.NET.Test.Sdk 17.12.0 + xunit.runner.visualstudio 2.8.2，TFM 同主项目 `net10.0-windows`，入口 `dotnet test`（见 [tests/](#测试基建)） |

### 入口模型（Bootstrap + Core 双 exe，Core 在 runtime/ 子目录隐藏）

```
projectRoot/
├── CRAZYFLASHER7MercenaryEmpire.exe   ← 用户双击点（native C++ bootstrap，~259KB，零 .NET 依赖）
├── runtime/                            ← FDD 子目录，用户不需要进
│   ├── CRAZYFLASHER7MercenaryEmpire.Core.exe   FDD apphost
│   ├── CRAZYFLASHER7MercenaryEmpire.Core.dll   main managed assembly
│   ├── *.dll (14个 transitive deps)
│   ├── miniaudio.dll                            P/Invoke side-car
│   └── sol_parser.dll                           P/Invoke side-car
├── tools/dotnet-runtime/
│   └── windowsdesktop-runtime-10.0.8-win-x64.exe   58MB MS 官方 installer，bootstrap 用
├── hotkey_guard.exe / Adobe Flash Player 20.exe / CRAZYFLASHER7MercenaryEmpire.swf / ...
└── logs/
    ├── bootstrap.log    ← bootstrap 每次启动 append（即便 runtime 缺失也有 trace）
    └── launcher.log     ← Core 启动后写入
```

```
用户双击 CRAZYFLASHER7MercenaryEmpire.exe  (~259KB, native C++ bootstrap, 零 .NET 依赖)
       ↓
  开 logs/bootstrap.log (append)
       ↓
  检测 %ProgramFiles%\dotnet\shared\Microsoft.WindowsDesktop.App\10.* 是否在场
       ↓ 在场                                      ↓ 缺失
ShellExecute runtime\Core.exe         MessageBox 确认 → ShellExecute "runas"
  --project-root "<projectRoot>"        tools\dotnet-runtime\windowsdesktop-runtime-10.0.8-win-x64.exe
                                        /install /passive /norestart  (UAC 一次)
                                                  ↓ 安装完成 + 二次确认
                                              ShellExecute runtime\Core.exe --project-root "<>"
       ↓
runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe  (255KB FDD apphost) + 17 DLLs (~37MB)
       ↓
Guardian Launcher 主逻辑 (WinForms / V8 / WebView2 / Vortice / ...)
```

**为什么 Core 在 `runtime/` 子目录而不是根**：用户在 projectRoot 浏览看不到 Core.exe，无从误点击触发 .NET apphost 的英文"You must install .NET to run this application"默认对话框。bootstrap 用 Chinese MessageBox + 自动 install installer 提供更友好的 UX。

**Bootstrap 设计原则**：纯 Win32 + CRT（静态链接 `/MT`），零 STL，输出 ~259KB；UTF-8 源码 (`/source-charset:utf-8 /execution-charset:utf-8`) 让中文 MessageBox 文本正确编码；**职责**：runtime 检测 + 触发 installer + 显式传 `--project-root <abs>` + 转发命令行参数到 Core + 写 `logs/bootstrap.log`。

**为什么不用 self-contained single-file**：实测 146MB single-file blob 太大不利 git；改 FDD 分散到 ~21 文件 ~37MB，配合 bootstrap + bundled installer 处理 runtime 缺失场景。详见 [`docs/launcher-net10-migration-status.md`](../docs/launcher-net10-migration-status.md) "post-migration 二次审阅" 段。

### 关键路径与 hardcoded 名

- 用户面 entry：`CRAZYFLASHER7MercenaryEmpire.exe`（bootstrap，在 projectRoot 根）— **不要重命名**（19+ 处脚本 / 文档 / 自动化引用此名）
- FDD apphost：`runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`（csproj `<AssemblyName>` 控制名，build.ps1 Step 6 部署到 runtime/ 子目录）
- Core projectRoot 解析：优先 `--project-root <abs>` CLI arg（bootstrap 注入）；次选 walk-up 哨兵文件 `crossdomain.xml`（覆盖 dev 直跑场景）；fallback `Environment.ProcessPath` 父目录
- 长跑进程：Core.exe（bootstrap 启动 Core 后立即退出）— `cfn-cli.sh` / `taskkill` / GPU pref 都针对 `runtime\Core.exe`
- Bundled runtime installer：`tools/dotnet-runtime/windowsdesktop-runtime-10.0.8-win-x64.exe`（~58MB，季度更新一次）
- Bootstrap 自有日志：`logs/bootstrap.log`（追踪 runtime 检测 / installer 调用 / Core 启动）；即便 runtime 缺失场景，bootstrap 跑完仍留 trace，**不再「未配环境无 log」**

> **2026-05-28 net10.0-windows 迁移记**：从 .NET Framework 4.6.2 / MSBuild / packages.config / SharpDX 切到当前栈，5 atomic commit + 2 轮后续 hardening。决策、phase 序列、人力验收待办见 [`docs/launcher-net10-migration-status.md`](../docs/launcher-net10-migration-status.md) + [`docs/launcher-net10-migration-test-matrix.md`](../docs/launcher-net10-migration-test-matrix.md)。

## 高 DPI 与多显示器支持

Launcher 现在显式声明并初始化 **PerMonitorV2 / PerMonitor DPI-aware**。运行态 WebView2 overlay 的物理视觉尺寸仍跟随 Flash 视口高度，但写入 `WebView2.ZoomFactor` 前会按当前 monitor DPI 归一化，避免 125% / 150% 系统缩放把右侧 HUD 与顶部资源条二次放大；输入命中则由 Web 端 `viewportMetrics`（CSS viewport / DPR / visualViewport）和 C# `OverlayCoordinateContext` 共同换算，不再把 `WebView2.ZoomFactor` 直接当作鼠标坐标比例。

运行态鼠标手型视觉默认由 C# `DesktopCursorOverlay`（desktop 顶层 ULW，`useDesktopCursorOverlay=true`，2026-05 起 default-on）原生 layered window 接管，避免 WebView2 特效或 JS 队列影响 cursor 延迟；旧 `CursorOverlayForm`（OverlayBase 子类，anchor-bound）仅作 `CF7_DESKTOP_CURSOR=0` 回滚兜底。AS2 侧保留 `_root.鼠标` 纯脚本兼容代理，只承载 `gotoAndStop` / `gotoAndPlay` 状态接口与 `物品图标容器` 拖拽图标容器；几何命中统一走 AS2 `_root._xmouse/_ymouse` 点命中和 `interactionMouseDown` / `interactionMouseUp` 事件，不再让 `_root.鼠标` 作为 `hitTest` 目标。`cursor_control` task 只低频推送状态到 Launcher；`WebOverlayForm` 负责状态调度、低级鼠标 hook 与坐标泵。Web DOM 交互通过 `cursorFeedback` 只回传 hover/press 状态变化，不回传坐标，也不再提供 Web 视觉 fallback；native cursor 不可用时恢复系统鼠标并写入诊断日志。native cursor 贴图采用 `64x64` 源画布、固定热点 `(16,16)` 的资源契约，运行时只按当前 monitor DPI 整体缩放画布与热点，不再为单张贴图维护偏移。物品拖拽图标第一阶段仍留在 AS2 空容器内，仅拖拽期间同步位置，不进入 Flash 每帧 UI 状态管线。

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
                ① `_readyWiring()`（toast/web/inputShield/notch.SetReady + `form.ShowTrayIcon()`）
                ② `BootstrapPanel.SetPanelVisible(false)`
                ③ `FlashHostPanel.Visible = true`
                ④ `form.Activate()` → ReleaseBootstrapBgmGate → hotkeyGuardSpawn
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
│  │ _flashPanel (Panel, Dock=Fill)                  │      │
│  │   reveal 时 Visible=true                        │      │
│  │   └─ Flash Player SA (Win32 SetParent 嵌入)     │      │
│  ├────────────────────────────────────────────────┤      │
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
│      bench_sync(*) / bench_push(*)│
│  Async: gomoku_eval / data_query  │
│         shop_response / archive   │
│         map_response /            │
│         stage_select_response /   │
│         arena_response /          │
│         pet_response /            │
│         merc_response /           │
│         task_response /           │
│         intelligence_response /   │
│         font_pack                 │
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
│  │  SFX: preload + 30ms dedup  │  │
│  └─────────────────────────────┘  │
│  sol_parser.dll (Rust cdylib)     │
│  AMF0 → JSON, 1-based refs        │
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

按 commit `07a0a09d9f`（2026-06-25）时的源码树复核。只列追踪目录；`bin/` / `packages/` / `target/` / `node_modules/` / `obj/` 等构建产物和缓存均由 .gitignore 管理。后续若需复核本节，优先看 `git diff 07a0a09d9f..HEAD -- launcher/`。C# 文件级权威以 [CRAZYFLASHER7MercenaryEmpire.csproj](CRAZYFLASHER7MercenaryEmpire.csproj) / [tests/Launcher.Tests.csproj](tests/Launcher.Tests.csproj) 的 `Compile Include` 为准，README 仅保留职责树。

```
launcher/
├── CRAZYFLASHER7MercenaryEmpire.csproj   C# 项目文件（SDK-style, net10.0-windows, AssemblyName=...Core）
├── Directory.Packages.props               中心化 PackageVersion 锁定（ClearScript / WebView2 / Vortice.DXGI / Newtonsoft / xunit / Test.Sdk）
├── build.ps1                              总构建脚本（TS/native miniaudio/Rust sol_parser/native bootstrap/FDD publish/资产 gate，见下文）
├── setup-check.ps1                        构建/运行前依赖自检（.NET 10 SDK + WebView2 + VC + Rust + Node）
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
│   │   ├── CursorOverlayForm.cs           原生 cursor 视觉层（OverlayBase 子类，anchor-bound；回滚兜底）
│   │   ├── DesktopCursorOverlay.cs        桌面顶层 ULW cursor（默认；scale 跟 GuardianForm.ClientSize，跨 anchor 自由）
│   │   ├── WebOverlayForm.cs              WebView2 视觉层（WS_EX_TRANSPARENT）
│   │   ├── InputShieldForm.cs             幽灵输入层（GDI+ α 命中 + CDP 注入）
│   │   ├── NativeHudOverlay.cs            C# Native HUD 容器（按 widget union 动态 bounds）
│   │   ├── FlashSnapshot.cs               panel 打开前抓 Flash 画面快照（backdrop 源）
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
│   │       ├── UiCommandHandler.cs         logs / open_saves_dir / diagnostic / audio_preview
│   │       ├── ConfigCommandHandler.cs     config_set（Plan A+：currentValue 权威下发 + requestId 相关 id）
│   │       ├── FontPackCommandHandler.cs   fontpack_status / fontpack_install / fontpack_cancel（透传 FontPackTask + fontpack_progress 推送）
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
│   ├── Diagnostic/                        【诊断设施】
│   │   ├── DiagnosticPackager.cs          bootstrap/HTTP 诊断包导出（save+sol+log+config+meta → zip）
│   │   ├── DiagnosticsBootstrap.cs        渲染合成层诊断总开关（按 config diag* 启停下列四件，默认全 OFF；零开销则零日志）
│   │   ├── LayerAuditDump.cs              顶层 HWND / WS_EX_* 结构快照（startup / post-ready / shutdown 各 dump 一次，无需管理员）
│   │   ├── UlwCommitMonitor.cs            ULW（UpdateLayeredWindow）commit 频率 + p50/p95/p99/max 延迟计量
│   │   ├── DwmEtwMonitor.cs               DWM-Core ETW 实时事件计数（需管理员；非提权降级 warn + skip）
│   │   └── UiFreezeProbe.cs               后台线程看门狗：观测 UI 线程 timer 卡顿 / 前台真空 / IsHungAppWindow（仅观测不改焦点；默认 ON，env CF7_DIAG_FOCUS_PROBE=0 关）
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
│   │   ├── DataQueryTask.cs               NPC 对话 / 佣兵 spawn bundle / 敌人对话 / 任务 NPC 注册表查询（Data/ 支撑）
│   │   ├── ToastTask.cs                   UI toast 通知（fire-and-forget）
│   │   ├── ShopTask.cs                    K 点商城双层 callId 桥接（10s 超时）
│   │   ├── MapTask.cs                     Web 地图 panel snapshot / refresh / navigate
│   │   ├── StageSelectTask.cs             Web 选关 panel snapshot / enter / jump_frame / return_frame
│   │   ├── IntelligenceTask.cs            情报详情 state / snapshot(itemName) / tooltip（按需读白名单 H5 正文）
│   │   ├── ArenaTask.cs                   竞技场（DEATH MATCH 角斗场）面板双层 callId 桥接（arena_response）
│   │   ├── PetTask.cs                     战宠面板双层 callId 桥接（pet_response；snapshot/adopt/deploy/advance/level_up/restore_stamina/delete/…）
│   │   ├── MercTask.cs                    佣兵面板双层 callId 桥接（merc_response；snapshot/hire_list/hire/deploy/dismiss/equip_tooltip）
│   │   ├── FontPackTask.cs                字体包按需下载（manifest + SHA256 校验 + 镜像 url，落 %LOCALAPPDATA%/CF7FlashNight/fonts，notch/toast 进度）
│   │   ├── ArchiveTask.cs                 存档 shadow 读写 + editor/import + 启动期候选快照
│   │   ├── IconBakeTask.cs                真机图标批量烘焙（AS2 BitmapData → begin/chunk/end 协议）
│   │   └── BenchTask.cs                   性能基准 task（条件编译）
│   │
│   └── V8/
│       └── V8Runtime.cs                   ClearScript V8 运行时（伤害数字 + 搓招 DFA）
│
├── native/
│   ├── miniaudio.h                        miniaudio 单头文件库（Unlicense）
│   ├── miniaudio_bridge.c                 C 导出层（BGM crossfade/seek/pause/looping, SFX preload, peak）
│   ├── build.bat                          MSVC vcvars64 探测 + cl.exe 编译 → miniaudio.dll
│   ├── bootstrap/                         【native C++ bootstrap：用户面入口 wrapper】
│   │   ├── bootstrap.cpp                  Win32-only, 零 STL；runtime 检测 + installer 调用 + ShellExecute Core.exe
│   │   └── build.bat                      复用 vcvars64 → bin/Release/bootstrap.exe（~259KB，静态链接 CRT）
│   └── sol_parser/                        【Rust cdylib：AMF0 → JSON】
│       ├── Cargo.toml                     flash-lso git pin 4b049ff3 + serde_json
│       ├── Cargo.lock                     ✅ 已入库：锁定依赖版本集，消除浮动解析
│       ├── build.bat                      cargo build --release + 落盘到 bin/Release
│       ├── src/lib.rs                     FFI (sol_parse_file / sol_free) + Ctx DFS 索引 + Flash SOL Reference raw-1 解析
│       ├── tests/reference_semantics.rs   AMF0 Reference 真实 Flash fixture 回归测试
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
│   │   ├── panels.css                     面板系统样式（Cyberpunk 2077 风格）
│   │   ├── merc_panel.css                 佣兵面板专用样式
│   │   ├── pet_panel.css                  战宠面板专用样式
│   │   ├── task_panel.css                 任务 / 成就面板专用样式
│   │   └── team_panel.css                 战队面板专用样式
│   ├── assets/                            引导页 / cursor / map / stage-select / pets / 头像 / 字体 / dressup / dialogue 媒体
│   │   ├── bg/                            背景图层资源
│   │   ├── cursor/native/                 C# CursorOverlayForm / DesktopCursorOverlay 贴图契约（64x64, hotspot 16,16）
│   │   ├── dressup/                       对话框/战斗纸娃娃 manifest/report（tools/bake-dressup-offline.py 生成）
│   │   ├── dialogue-portraits/            事件日志 Web 对话立绘 manifest/report + PNG（tools/bake-dialogue-portraits.py 生成）
│   │   ├── map/                           地图 panel/HUD 页面图
│   │   ├── stage-select/                  选关背景与 hover 预览
│   │   ├── pets/                          战宠头像（pet_<id>.png ×83 + pet_locked.png 兜底，共 84 张）
│   │   ├── fonts/                         字体包 shipped 兜底 + manifest 来源（FontPackTask）
│   │   ├── logos/                         标题 / Steam 等品牌图标
│   │   │                                   （佣兵 / NPC 头像在 map/avatars/；地图 / 选关图标在 map/ 与 stage-select/ 内，assets/ 根下无 avatars/ 与 icons/）
│   │   └── intro.mp4                      片头视频（deferReveal 路径播放期）
│   ├── lib/
│   │   └── marked.min.js                  Markdown→HTML 渲染器（MIT）
│   ├── icons/                             物品图标资源（manifest.json + *.webp + 少量遗留 *.png；真机 / FFDec 离线烘焙共用目标）
│   ├── help/                              游戏帮助 Markdown（controls/worldview/easter-eggs.md）
│   ├── data/
│   │   └── lockbox-variants.json          开锁小游戏数据
│   └── modules/
│       ├── audio.js                       Web Audio 合成的 UI 音效（BootstrapAudio：hover/click/confirm/error + ambient hum）
│       ├── asset-timeline.js              烘焙素材共享时间线选择器（timelineFrames / durationFrames / nested layer 独立周期）
│       ├── overlay-audio-bindings.js      运行态 overlay 交互音效绑定（panel/notch 等接到 BootstrapAudio）
│       ├── perf-frame-limiter.js          overlay rAF 限帧器（webOverlayFrameRateLimit 落地点）
│       ├── about.js                       "其他" 弹窗 + AUDIO 复选框（走 config_set 协议）
│       ├── display.js                     DISPLAY 字号预设模态（顶栏入口；config_set 持久化 uiFontScale）
│       ├── dressup-doll-renderer.js       Canvas 2D 对话框/战斗纸娃娃渲染器（消费 assets/dressup/manifest.json）
│       ├── dialogue/                      可复用 Web 对话回放组件（NPC PNG 立绘 + 主角纸娃娃 Canvas）
│       ├── factions.js                    welcome 页阵营列表渲染
│       ├── archive-schema.js              存档 schema 描述/校验
│       ├── archive-editor.js              存档编辑器（welcome/slots 视图的模态）
│       ├── repair-card.js                 存档修复卡片（C2-β 检测 / 应用 / 强制继续）
│       ├── diagnostic-log.js              BootstrapPanel 日志查看器
│       ├── bridge.js                      C# ↔ JS 消息桥（overlay 侧；task/taskResult + viewportMetrics + gpuInfo 探针 + 字体预载）
│       ├── lazy-loader.js                 按需注入 <script>（URL 去重；面板懒加载依赖加载器）
│       ├── uidata.js                      帧同步 UI 状态分发（KV 格式）
│       ├── toast.js                       Toast 消息（Flash HTML 白名单）
│       ├── sparkline.js                   FPS 折线图（DPR 感知）
│       ├── notch.js                       Notch UI（FPS/clock/工具条/通知）
│       ├── currency.js                    经济面板动画
│       ├── combo.js                       搓招连击飞出动效
│       ├── cursor-feedback.js             Web DOM hover/press 状态回传（只回状态不回坐标）
│       ├── cutscene-test.js               Ruffle 过场动画测试 panel（懒加载 flashswf/_ruffle 运行时）
│       ├── jukebox.js                     旧 BGM 点歌器入口（脚本入口已注释；展开 UI 已迁 jukebox/jukebox-panel.js）
│       ├── dressup/
│       │   ├── dressup-panel.js           对话框/战斗纸娃娃生产 Panel（消费 dressup-doll-renderer + 离线 manifest）
│       │   └── dev/                       dressup renderer / panel harness
│       ├── panels.js                      通用面板生命周期（register/registerLazy/open/close/ESC）
│       ├── panels-lazy-registry.js        多个面板的懒注册表（id → deps[]；首次 open 时按需加载对应模块）
│       ├── panel-scale.js                 全屏 panel 固定画布等比缩放助手（.panel-scale-shell）
│       ├── jukebox/
│       │   └── jukebox-panel.js           BGM 点歌器（Panels.register('jukebox')；展开后内容由此承载）
│       ├── tooltip.js                     Tooltip（hover/anchored）
│       ├── icons.js                       图标 manifest 加载与解析（播放时间线消费 asset-timeline.js）
│       ├── kshop.js                       K 点商城面板（ShopTask 双层 callId）
│       ├── team/team-panel.js             战队唯一生产 Panel（薄协调器：无独立顶栏，唯一 tab 条迁移注入子面板 header 槽位）
│       ├── team/dev/harness.html           战队 browser harness（四标签 / 分类 / 佣兵卡片 / 详情栏 / 会话记忆）
│       ├── pet-panel.js                   可嵌入宠物子控制器（管理/领养/进阶；伙伴/战宠/机械按 rosterType 过滤；列表页 header 含 .team-tabs-slot）
│       ├── pets/dev/harness.html          宠物子控制器 browser harness
│       ├── merc-panel.js / merc-data.js   可嵌入佣兵子控制器（管理/雇佣/培养三页 + 2 列横版卡 + 底部详情栏技能流）+ 槽位常量
│       ├── arena-panel.js / arena-factions.js / arena-meta-rosters.js 竞技场面板（Panels.register('arena')：8 张角斗场卡 + 详情/进场；ArenaTask 双层 callId）
│       ├── arena/dev/                     竞技场 browser harness + in-page QA
│       ├── help.js / help-panel.js        帮助系统（顶层入口 + 面板骨架）
│       ├── map-avatar-source-data.js      地图 NPC 头像源数据表（symbol → assetUrl + hotspot 相对坐标 + crop）
│       ├── map-panel.js / map-canvas-stage-renderer.js / map-panel-data.js / map-fit-presets.js / map-hud.js 地图系统（正式 map panel + Canvas 底图 renderer + 静态页面/热点数据 + filter fit preset 表 + 右上角常驻 HUD；DOM+Canvas 混合分层见 map/ 子目录 + 侧栏红点系统 + 场景 LRU）
│       ├── stage-select-data.js / stage-select-panel.js 选关界面 Stage 2 runtime panel（Panels.register('stage-select')）
│       ├── intelligence-components.js     情报 H5 JSON 组件树白名单渲染器（无内容侧脚本）
│       ├── intelligence-panel.js          情报详情 Web 面板（Panels.register('intelligence')；runtime 状态由 AS2 提供，正文由 C# IntelligenceTask 按需读取）
│       ├── font-pack-banner.js            情报面板首访字体包安装条幅（FontPackTask status / download_group）
│       ├── map/                           【地图 DOM+Canvas 混合分层（2026-05 重构）】
│       │   ├── map-scene-visual-layer.js  场景视觉 DOM 层（focus/current 场景走 GPU 合成抬升，canvas 只画底图）
│       │   ├── map-avatar-layer.js        NPC 头像 DOM 层（静态+动态槽位，指纹缓存避免重建闪烁）
│       │   ├── map-hittest-engine.js      像素级 color-picking 命中引擎（每页离屏 hitmap + LRU MAX_PAGES=2）
│       │   ├── map-hotspot-hitcapture.js  单一指针事件代理（rAF 节流 pointermove + down→up→click 命中复查）
│       │   └── dev/
│       │       ├── harness.html / .css     地图 panel browser harness（?qa=1 / ?case=）
│       │       ├── qa-suite.js             in-page QA 套件（map-ui1~map-ui32c，含红点/分层用例）
│       │       ├── run-qa.js               headless Playwright runner（node …/map/dev/run-qa.js）
│       │       ├── screenshot.js           红点/选关视觉回归截图（写 tmp/map-red-dot-shots/）
│       │       ├── builder.html            地图可视化构建器入口（跳转到 builder 模式 preview）
│       │       └── preview.html / .css / .js   地图 manifest 预览 / 校准页
│       ├── tasks/                          【任务界面 Web 迁移 · 协议接入（2026-05-30）：生产模块 + C# Task + AS2 service 已接入；仍需 Flash fresh trace / 游戏内端到端复核后才能标记生产可用】
│       │   ├── task-panel.js               任务界面生产 panel（我的任务/事件日志/成就 + 副本任务 tab）
│       │   ├── task-catalog.json           任务 Web 面板分类 / 展示目录（v2：chain="委托" 挂 dungeon{} 供副本 tab）
│       │   ├── ../../assets/dungeon-posters/ 副本 WANTED 海报 PNG（ffdec 烘焙 flashswf/images/<n>.swf）+ manifest.json
│       │   ├── achievement-catalog.json    成就 Web 面板目录
│       │   ├── achievement-tab.js          任务面板内成就 tab 渲染器
│       │   ├── assets/                     迁移自 Flash 的任务界面生产美术（task_main_bg / task_icon_bg / task_scroll / requirement_* / finish_npc）
│       │   └── dev/
│       │       └── harness.html            任务界面布局原型（顶部切页 + 左任务列表 + 右任务详情，静态 mock）
│       ├── stage-select/
│       │   └── dev/
│       │       ├── harness.html           选关界面 browser harness
│       │       └── qa-suite.js            选关界面 in-page QA 套件
│       ├── intelligence/
│       │   └── dev/
│       │       ├── harness.html           情报详情 panel browser harness
│       │       └── qa-suite.js            情报详情 in-page QA 套件
│       ├── workers/
│       │   └── sharpen-worker.js          头像 / 立绘等图像锐化 Web Worker
│       └── minigames/
│           ├── shared/                    小游戏共享层（host-bridge + minigame-shell + shared/dev QA 基础层）
│           ├── lockbox/                   开锁小游戏（core + dev QA + lockbox-panel/lockbox-audio/lockbox.css + README）
│           ├── pinalign/                  定位小游戏（core + adapter/app + dev QA/sim/replay + reference + pinalign-panel/audio/css + README）
│           └── gobang/                    五子棋小游戏（core + dev QA + gobang-panel/audio/css + README，AI 走 GomokuTask/Rapfi）
│
├── tests/                                 【xUnit 2.9.2 C# 单测，见测试基建节】
│   ├── Launcher.Tests.csproj              SDK-style csproj（net10.0-windows 对齐主工程；53 个测试源码入口）
│   ├── run_tests.ps1                      `dotnet test`（Microsoft.NET.Test.Sdk + xunit.runner.visualstudio 自动 discover）
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
    └── validate-minigame-final-state.js   小游戏最终态静态校验（旧路径 / 旧协议 / 旧共享类名）
```

> 老的 `launcher/packages/` 是 .NET Framework 4.6.2 时代 packages.config 工作流的残留（同期的 `launcher/tools/nuget.exe` 已移除）；
> 已被 SDK-style PackageReference + `dotnet restore` 取代。可手动 `Remove-Item -Recurse launcher/packages` 回收磁盘（未被 git 跟踪的 restore 产物，实测约 ~130MB）。

## 在 VS Code 中构建

### 前置条件

- **Windows 10 22H2+ / Windows 11，x64**
- **.NET 10 SDK**（10.0.300 patch band，对齐 `global.json` 的 `version: 10.0.300` + `rollForward: latestPatch`）
  - user-scope 装法（无需 admin）：
    ```powershell
    iwr https://dot.net/v1/dotnet-install.ps1 -OutFile $env:TEMP\dotnet-install.ps1
    & $env:TEMP\dotnet-install.ps1 -Channel 10.0 -InstallDir $env:LOCALAPPDATA\Microsoft\dotnet
    ```
    安装后 `%LOCALAPPDATA%\Microsoft\dotnet\dotnet.exe` 即可用。`build.ps1` / `run_tests.ps1` 优先探测此路径，找不到再 fallback 到 PATH 的 `dotnet`
  - 系统级（需 admin）：`winget install Microsoft.DotNet.SDK.10`
  - SDK 装好自带 WindowsDesktop runtime 10.x（`UseWindowsForms=true` 硬依赖）
- **MSVC C 编译器**（cl.exe，用于编 miniaudio.dll）：VS 2022 Build Tools 或任意 VS 版本
  - 安装：`winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"`
  - native/build.bat 自动探测 vcvars64.bat
- **Rust 工具链**（用于编 sol_parser.dll）：`rustup-init.exe` → stable-x86_64-pc-windows-msvc
  - 安装：https://rustup.rs/
  - native/sol_parser/build.bat 要求 `cargo` 在 PATH 里
  - 首次构建 cargo 需联网拉 flash-lso（git pin）及其传递依赖。Cargo.lock 只锁版本集，**不等价于离线可复现**——能否在新机器离线构建取决于本机 `~/.cargo/registry/cache` 和 `~/.cargo/git/checkouts/` 是否已有对应依赖（或是否做过 `cargo vendor`）
- **Node.js + npm**（用于编 V8 的 TypeScript 脚本 + cf7-packer + cf7-save-repair-dict-build）：Node 18+（LTS 均可）
  - 安装：`winget install OpenJS.NodeJS.LTS`
  - build.ps1 会在 `launcher/scripts/` 下跑 `npm install` + `npx tsc`
- **WebView2 Runtime** Evergreen Bootstrapper（运行期硬依赖）
  - 检测：`setup-check.ps1` 读注册表 `HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`
- **终端**：PowerShell 或 Git Bash 都行
- **推荐先跑环境自检**：`powershell -File setup-check.ps1`
  - 当前脚本检查 5 项：`.NET 10 SDK + WindowsDesktop runtime`、`WebView2 Runtime`、`MSVC Build Tools`、`Rust cargo`、`Node + npm`

### 一键构建

```powershell
cd launcher
powershell -File setup-check.ps1
powershell -File build.ps1
```

### build.ps1 实际执行链

脚本头部先 echo `dotnet --version` + `global.json file:` 路径作为构建日志证据（CI 复现 / SDK 版本飘移诊断用）。Step 5 `dotnet publish` 调用前 `Push-Location $projectRoot` 切到 repo root，保证 dotnet host 沿 CWD 向上找到 `global.json`（不管脚本从哪个目录被调用）。**实际执行动作**：

| 阶段 | 动作 |
|------|------|
| 1a   | 战宠 roster 分类审计 — `powershell tools/audit-pet-roster-types.ps1`（以 `data/merc/pets.xml` 的 RosterType 为权威核对分类差异；**实际在 Step 1 之前最先执行**，缺脚本或审计失败 exit 1） |
| 1    | TypeScript 编译 — `cd scripts`，若 `node_modules/` 缺失则 `npm install --ignore-scripts`，再 `npx tsc --project tsconfig.json` → `scripts/dist/*.js` 供 V8Runtime 加载 |
| 1b   | 生成 `data/map/task_npc_registry.json` — `node tools/derive-task-npc-registry.js`（任务 NPC 注册表派生；生成失败 exit 1） |
| 1c   | 生成 `data/map/map_catalog.json` — `node tools/derive-map-catalog.js`（地图 hotspot 拓扑 groups/hotspots，导航权威；派生失败 exit 1） |
| 1d   | 生成 `launcher/data/map_hud_data.json` — `node tools/export-maphud-data.js`（NativeHud 小地图 context outline+meta，与 1b/1c 同源每次重生成；派生失败 exit 1） |
| 1e   | 生成 `web/modules/tasks/task-catalog.json` 后运行 `node tools/test-derive-task-conditions.js`（23 个合成夹具覆盖 conditions 单调 AND-OR 不动点；失败 exit 1） |
| 1f   | 生成 `web/modules/tasks/achievement-catalog.json` — `node tools/derive-achievement-catalog.js`（成就 tab web 直读目录，含 objective 枚举 / 跨域闭包 / 脱敏校验；派生失败 exit 1） |
| 2    | `native/build.bat` — 编 `miniaudio_bridge.c` → `bin/Release/miniaudio.dll`（自动 vcvars64） |
| 3    | `native/sol_parser/build.bat` — `cargo build --release` → `bin/Release/sol_parser.dll`（硬依赖，缺失直接 exit 1） |
| 4    | `native/bootstrap/build.bat` — 编 `bootstrap.cpp` (Win32-only C++) → `bin/Release/bootstrap.exe`（~259KB，零 .NET 依赖，复用 vcvars64） |
| 5    | `dotnet publish ... -c Release -r win-x64 --self-contained false -p:DebugType=embedded -o $publishDir` — 出 FDD apphost (`CRAZYFLASHER7MercenaryEmpire.Core.exe`) + 17 个 DLL + `CRAZYFLASHER7MercenaryEmpire.Core.deps.json` + `CRAZYFLASHER7MercenaryEmpire.Core.runtimeconfig.json`，~37MB 散落形态 |
| 6    | 拷贝产物到 `projectRoot\runtime\`：(a) `publishDir/*` 除 `*.xml`（含 `CRAZYFLASHER7MercenaryEmpire.Core.*` 全套） (b) `bootstrap.exe` → projectRoot 改名 `CRAZYFLASHER7MercenaryEmpire.exe`（用户面入口） (c) `sol_parser.dll` + `miniaudio.dll` from `bin/Release`；拷贝走 `Copy-IfDifferent`（SHA256 比对，相同跳过 → 可复现构建、不污染 git）+ 定向清理过期产物；**硬断言根目录 `CRAZYFLASHER7MercenaryEmpire.exe`，以及 `runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe` + `runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll` + `runtime\sol_parser.dll` + `runtime\miniaudio.dll` 全部落盘**（任一缺失 exit 1）；bundled runtime installer（`tools/dotnet-runtime/windowsdesktop-runtime-10.*-win-x64.exe` glob）缺失现为 **fail-fast exit 1**（旧版只 WARN） |
| 6f   | 编译产物优化护栏 — `dotnet run tools/assert-optimized.cs -- runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll` 用 PEReader 读 `DebuggableAttribute`，断言发布的 managed assembly 是 optimized（非 Debug）build；Debug DLL 漏进 `runtime\` 是历史性能回归根因，命中即 exit 1 |
| 7    | fail-fast 校验 `launcher/web` 运行时必需集：`bootstrap.html` / `bootstrap-main.js` / `overlay.html` / `config/version.js` / `assets/bg/manifest.json` / `assets/cursor/native/*` / `assets/intro.mp4` / `assets/map/*` / `assets/stage-select/*` / `help/*.md` / `icons/manifest.json` / `data/lockbox-variants.json` / 关键 `modules/*`（含 `map-canvas-stage-renderer.js` / `intelligence-components.js` / `intelligence-panel.js`）与 minigame 入口文件 |
| 7a   | 运行 `node tools/audit-native-cursor-assets.js` 校验各 cursor PNG 尺寸与 manifest 声明的 canvas 一致、且 manifest 指定的 hotspot 像素具备 alpha（当前 manifest 数据值为 `64x64` / `(16,16)`，非工具硬编码契约），缺失或不合规直接 exit 1 |
| 7b   | fail-fast 校验 `launcher/data/map_hud_data.json` + `save_repair_dict.json` + `save_schema.json` 三件运行时数据；缺失时分别提示对应生成命令 |
| 7c   | `npm --prefix tools/cf7-save-repair-dict-build run verify` — 校验 `save_repair_dict.json` 与源头 `data/**/*.xml` + `SaveManager.as` 一致，不一致 exit 1 |

> build.ps1 **不跑** `launcher/tests/`；测试走独立 `launcher/tests/run_tests.ps1`，见[测试基建](#测试基建)节。

### 产物（部署到项目根目录）

net10 FDD 模式 + bootstrap + runtime/ 子目录隐藏：

**projectRoot 根（用户能看到的层）**：
| 文件 | 大小 | 说明 |
|------|------|------|
| **`CRAZYFLASHER7MercenaryEmpire.exe`** | ~259KB | **用户面入口**：native C++ bootstrap，检测 .NET 10 桌面运行时 + 缺失自动调起 installer + 启动 Core |
| `hotkey_guard.exe` | ~7KB | 快捷键拦截辅助进程；独立 `csc` 编译（不走主 csproj，build.ps1 不自动构建），需手动编一次（见下文） |
| `Adobe Flash Player 20.exe` | 16MB | Flash Player SA（vendor binary） |
| `CRAZYFLASHER7MercenaryEmpire.swf` | 530KB | 游戏主 SWF |
| `CRAZYFLASHER7MercenaryEmpire.bat` | 2KB | 裸 Flash 模式启动脚本（不走 Guardian launcher） |
| `config.xml` / `config.toml` / `crossdomain.xml` | <5KB | 配置 |

**projectRoot/runtime/ 子目录（hidden from user, FDD 主体）**：
| 文件 | 大小 | 说明 |
|------|------|------|
| `CRAZYFLASHER7MercenaryEmpire.Core.exe` | 255KB | FDD apphost（bootstrap 启动它） |
| `CRAZYFLASHER7MercenaryEmpire.Core.dll` | 920KB | 主程序 managed assembly |
| `CRAZYFLASHER7MercenaryEmpire.Core.deps.json` / `.runtimeconfig.json` | <10KB | .NET host 元数据 |
| `ClearScript.Core.dll` / `.V8.dll` / `.V8.ICUData.dll` | ~11MB | V8 JS 引擎 managed |
| `ClearScriptV8.win-x64.dll` | 22MB | V8 native（最大头） |
| `Newtonsoft.Json.dll` | 696KB | JSON 序列化 |
| `Microsoft.Web.WebView2.{Core,WinForms,Wpf}.dll` | ~750KB | WebView2 managed |
| `WebView2Loader.dll` | 158KB | WebView2 native loader |
| `Vortice.DXGI.dll` + `Vortice.DirectX.dll` + `Vortice.Mathematics.dll` + `SharpGen.Runtime.{,COM}.dll` | ~720KB | DXGI 适配器枚举（GPU pref 检测） |
| `miniaudio.dll` | 778KB | 原生音频引擎（WASAPI）；独立 `cl.exe` 编译；与 Core.exe 同目录让 P/Invoke 命中 |
| `sol_parser.dll` | 225KB | Rust AMF0 → JSON 解析器（Protocol 2 存档决议） |

**projectRoot/tools/dotnet-runtime/**：
| 文件 | 大小 | 说明 |
|------|------|------|
| `windowsdesktop-runtime-10.0.8-win-x64.exe` | 58MB | **Bundled .NET 10 桌面运行时 installer**；bootstrap 在 runtime 缺失时 `ShellExecute "runas" /install /passive /norestart`。MS 官方包，季度更新一次 |

> **入口分工**：用户**只**双击 `CRAZYFLASHER7MercenaryEmpire.exe`（bootstrap）。Bootstrap 启动 Core 后立即退出，长跑进程是 `runtime\Core.exe`。所有 launcher 运行期行为 — V8 / WebView2 / Flash 嵌入 / 焦点诊断 / 存档决议 — 都在 Core 进程里。`cfn-cli.sh` / `taskkill` / GPU pref 都针对 `runtime\Core.exe`，不针对 bootstrap。

> **诊断 trace**：runtime 缺失场景仍写 `logs/bootstrap.log`（bootstrap 启动时 append），不再「没装环境就没 log」。Core 起来之后另写 `logs/launcher.log`（既有诊断设施）。

### 单独编译 HotkeyGuard

HotkeyGuard 是独立 WinExe（不走主 csproj）：

```powershell
cd launcher/src/Guardian
csc /target:winexe /out:../../../hotkey_guard.exe HotkeyGuard.cs
```

Launcher 启动时 `Program.cs` 尝试 `Process.Start("hotkey_guard.exe")`；若文件不存在，日志打印 `[Guardian] hotkey_guard.exe not found, shortcuts not blocked` 并继续运行（该层防御降级，仍有 SetMenu/KeyboardHook 两层兜底）。

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

`launcher/tests/` 是独立 xUnit 2.9.2 测试工程（SDK-style csproj, net10.0-windows，对齐主工程），与 build.ps1 解耦。

### 跑测试

```powershell
powershell -File launcher/tests/run_tests.ps1
```

脚本做法：
1. 探测 user-scope dotnet (`%LOCALAPPDATA%\Microsoft\dotnet\dotnet.exe`)，找不到 fallback PATH `dotnet`
2. echo `dotnet --version` 作为日志证据
3. `Push-Location $projectRoot` 保证 dotnet host 找到 repo root 的 `global.json`（SDK pin 10.0.300 + latestPatch）
4. `dotnet test Launcher.Tests.csproj -c Release` —— Microsoft.NET.Test.Sdk + xunit.runner.visualstudio 自动 discover + run，连带编译主工程的 `ProjectReference`

### 测试覆盖

当前 `Launcher.Tests.csproj` 直接编译 53 个测试源码文件（`<root>` 1 / `Bus` 4 / `Tasks` 10 / `Save` 8 / `Guardian` 30），可静态检出 530 个 `[Fact]` / `[Theory]` 标记。`SaveMigratorTests` 继续使用代码内 helper 数据；外部 fixture 目前主要集中在 `Fixtures/MapHud/`。

| 分组 | 覆盖面 |
|------|--------|
| `Bus/` | MessageRouter 当前观察行为、XMLSocket read loop 边界 |
| `Tasks/` | StageSelectTask、IconBakeTask、ArchiveTask list/filter 行为 |
| `Save/` | Protocol 2 决议、SOL 定位、legacy 首导入、版本 gate、repair policy / backup / auto-repair |
| `Guardian/` | overlay 坐标、DPI、FlashSnapshot、PanelHost/Router、InputShield telemetry、Native HUD bounds、UiData parsing、RightContext/MapHud/SafeExit/Combo/Toast/Notch/widget scaling |
| `<root>` | 基建冒烟 |

### Web QA 与开发 harness

本节最后核对代码基线：commit `07a0a09d9f`。

小游戏测试不走 `launcher/tests/`，地图 panel 的 DOM / 布局 / 交互回归也不走 C# 单测；统一按各模块自带的 QA 入口执行：

- **Node QA**：`node tools/run-minigame-qa.js --game lockbox|pinalign|gobang|all`
  - 实际入口文件：`tools/run-minigame-qa.js`
  - 共享 runner：`web/modules/minigames/shared/dev/node-qa-runner.js`
  - 适用场景：纯逻辑、确定性、导出结构、回归脚本
- **Browser harness**：直接打开各自 `dev/harness.html`
  - `web/modules/minigames/lockbox/dev/harness.html`
  - `web/modules/minigames/pinalign/dev/harness.html`
  - `web/modules/minigames/gobang/dev/harness.html`
  - `web/modules/map/dev/harness.html`（也可用 `node web/modules/map/dev/run-qa.js` headless 跑 `map-ui1`~`map-ui32c`，或 `node web/modules/map/dev/screenshot.js` 出红点 / 选关视觉回归截图到 `tmp/map-red-dot-shots/`）
  - `web/modules/stage-select/dev/harness.html`
  - `web/modules/arena/dev/harness.html`
  - `web/modules/intelligence/dev/harness.html`
  - `web/modules/team/dev/harness.html`（也可用 `node tools/run-team-harness.js` 跑 headless QA）
  - 共享 QA 基础层：`web/modules/minigames/shared/dev/harness-base.js` + `harness-base.css`
  - 支持 query 驱动的 `?qa=1` / `?case=` / `?scenario=` / `?dump=1`
  - `map` harness 额外覆盖 Canvas renderer debug state / 非空像素、页签 hit-test、右侧层级按钮遮挡、学校室友动态图、`1366x768` 紧凑视口可达性、locked group 锁定提示与锁定原因可达性
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
- **Stage Select manifest / audit / harness**：`node tools/export-stage-select-manifest.js --summary`、`node tools/audit-stage-select-layout.js --json`、`node tools/audit-diplomacy-stage-select-links.js --json`、browser harness `web/modules/stage-select/dev/harness.html?qa=1`（in-page `dev/qa-suite.js`，约 33 用例），也可用 `node tools/run-stage-select-harness.js --browser edge` 跑 headless QA
  - 从 `flashswf/UI/选关界面/LIBRARY/选关界面UI/选关界面 1024&#042576.xml` 导出 `StageSelectData` 所用 manifest；Stage 2 通过 `StageSelectTask` / `StageSelectPanelService` 接入真实解锁 snapshot、`StageInfoDict` 关卡简介/限制词条/任务提示数据、普通难度进关、外交地图直达、委托任务详情打开、runtime 页内 frame 同步与关闭语义。关卡预览按原版链路导入：外部 PNG → `Symbol 3274` 内部命名帧 → 默认预览帧，layout audit 要求 `previewMissing=0`
  - Stage 2 正式入口替换记录见 `docs/选关界面-AS2入口替换交接.md`：AS2 `openWebStageSelect` 通过 `panel_request stage-select` 传入 `source/frameLabel/returnFrameLabel`，C# 固化 runtime 初始化，`jump_frame` 只同步 Web 当前选关页，不覆盖 AS2 `_root.关卡地图帧值`；原版 return nav 通过独立 `returnFrameLabel` + `return_frame` / `stageSelectReturnFrame` 先淡出回对应基地帧再关闭 Web panel，若返回目标已经等于 `MapHotspotResolver` 从真实场景源解析出的当前热点则跳过重复淡出，close 回调 `stageSelectPanelClose`；runtime 布局隐藏测试标题/fixture/dev 控件，16 个 frame tab 收进可展开区域菜单，场景门替换覆盖基地门口、车库、地下 2 层、停机坪、联合大学左右出口；外交地图绿色点与文字从每个外交符号内部 `shape/外交地图点` / `DOMDynamicText` 矩阵导出，避免把第一防线防区按通用外交点偏移；只带 SWF、没有 XFL 的外交地图如果仍调用旧 `切换场景("", "关卡地图", ...)`，会被 AS2 公共门函数转入 Web 选关并保留 Flash fallback；地图 panel 也可通过二级 `open_stage_select` 动作复用 `RootFadeTransitionFrame` 直接打开对应选关页签，主热点点击仍只负责 `navigate`
  - `audit-diplomacy-stage-select-links` 同时报告 `stageInfoOnlyMaps`；当前 `外交-黑铁阁` 属于 `StageInfo` 与地图 SWF 存在、但原选关 XFL 没有按钮的 data-only 外交地图，不自动作为 Web 选关漏配处理。
- **Intelligence panel harness**：`node tools/run-intelligence-harness.js --browser edge`
  - 打开 `web/modules/intelligence/dev/harness.html`，同时 mock 正式 runtime 的 `state → snapshot(itemName)` 按需正文链路与 dev `bundle` 全量包兼容路径；覆盖运行态无 `bundle` 请求、右侧可折叠情报目录、AS2 tooltip 富文本刷新、物品 XML `iconName` 图标解析、H5 组件渲染、legacy 标签兼容、加密切换、缺图占位、长文本滚动与 1024×576 / 1366×768 / 1600×900 / 1920×1080 视口 hit-test
- **Icon bake offline（FFDec）**：`python tools/bake-icons-offline.py --scope all --dry-run --report tmp/icon-bake-offline-dry-run-report.json`
  - 开发期快速重烘焙入口，直接从 `data/items/asset_source_map.xml` 定位 `图标-*` linkage 所在 SWF，再用 `tools/ffdec/ffdec-cli.exe` 的 `symbolClass` / `sprite:png` 导出并写入 `launcher/web/icons/manifest.json + *.webp`（保留少量遗留 PNG），绕过 AS2 `BitmapData.draw` 与 XMLSocket chunk 传输。
  - 默认目标目录为 `launcher/web/icons`；默认开启既有图标布局保护：已有图标文件出现非微小差异时记录 `layoutProtected` 并保留旧文件，离线烘焙主要用于补缺。默认 `--image-format webp`；PNG 仅用于 FFDec 中间帧、`--image-format png` legacy 路径或少量 layered/nested 兼容产物。只审 XML/source map 覆盖率时可用 `--resolve-only`，它不启动 FFDec，只刷新 `unresolvedSummary` 与冲突候选 `conflictSources`。报告必须关注 `unresolved`（含 `reason=conflict|missing_asset`）、`export_errors`、`missing_frame`、`layoutProtected`、`f1Profile`。FFDec 导出后还会扫描 symbol 实际 PNG 帧并写 `animationAudit`：`sourceFrameCount/uniqueFrameImages/duplicateFrameRefs/timelineFrameEntries/timelineCompressedFrameRefs/longestHoldFrames/animatedCandidate`，用于区分真动态图标、多帧静态 hold 和后续可写 `timelineFrames` 的空间收益；同轮还用 `swf2xml` + `script:as` 建 sprite 图谱，补充 `nestedAnimatedDescendantCount/maxNestedDescendantFrameCount/sampleNestedDescendants` 与 `nestedStoppedDescendantCount`，用于发现父级单帧但内部子 MovieClip 自播放的图标。全量清理只允许 `--scope all` 且无 `--limit/--name` 时加 `--purge`。
  - 结构摸底优先跑 `python tools/bake-icons-offline.py --scope all --animation-structure-audit-only --ffdec-timeout-seconds 120 --report tmp/icon-animation-structure-audit.json`：该模式只导出 `symbolClass` / `script:as` / `swf2xml`，不导出 PNG、不写 manifest；报告会按 `animationStructureCandidates`、`animationStructureParentStopNested`、`animationStructurePlainStop`、`animationStructureParentTimeline`、`animationStructureUnsupported` 拆分，便于先确认哪些素材是“父级首帧冻结 + 局部子 MovieClip 播放”、哪些还需要人工校准。`--ffdec-timeout-seconds` 作用于每个 FFDec 子进程；个别大 SWF 的 `swf2xml` 超时会记录为 `spriteGraphErrors[].error=swf_xml_timeout`，PNG/SVG/XML2SWF 导出超时会以 `exitCode=124` 进入对应 export error，全量摸底和动图写入都可按 `--name` 分批复核。
  - 离线渲染使用 FFDec renderer，不保证与 Flash Player / `IconBakeTask` 既有图标像素级一致；若要接受 FFDec 产物替换既有图标，必须先跑 `python tools/audit-icon-layout-regressions.py --report tmp/icon-layout-regressions-before-restore.json` 审查 alpha 包围盒 / 质心偏移，再显式加 `--force-overwrite-existing`。若 legacy PNG 批量覆盖后出现偏移回归，可用同一审计工具加 `--restore` 从 Git 基线恢复 tracked PNG；若必须保持 Flash Player 字节基线，继续使用运行态按钮 `BAKE` / `BAKE10` / `BAKE_SKILL` 走真机协议。
  - 主线化目标不是给每个图标维护外置 offset，而是用真机 PNG 作 oracle，反推一套通用导出语义：固定 256×256 画布、按 Flash 注册点 / SVG matrix 还原 attachMovie 原点、按 AS2 真机帧选择保留 `f1/f2`。在该校准通过前，`--force-overwrite-existing` 不作为常规入口。
  - `--export-animated-frames` 是动图产物写入入口：当父 symbol 自身导出的 PNG 帧存在多张唯一画面且父级第 1 帧不是纯 `stop();` 时，默认 WebP 模式优先写单张 animated WebP + 静态首帧 fallback；legacy `--image-format png` 才写 `frames[]` / 可选 `timelineFrames[]` / `playback=loop` / `animated=true` / `fps`，并只保存唯一 PNG 帧；若父级第 1 帧是纯 `stop();`，父 timeline 一律冻结为 `playback=static-first-frame`，不会把后续变形帧写成循环动画，也会从 manifest 移除 `f2` 引用。生产推广先复用结构审计结果，例如 `--animation-candidates-only --animation-candidate-report tmp/icon-animation-structure-audit.json --animated-candidate-max-source-frames 32`，只处理 `animationStructureCandidates` 中可表示的候选，并在 PNG 导出前跳过超长周期；单个候选用 `--name` 分批确认首帧 oracle 和体积，批量节奏用 `python tools/promote-icon-animation-candidates.py --candidate-report tmp/icon-animation-structure-audit.json --max-source-frames 32 --max-animated-icon-bytes 1500000 --output-dir launcher/web/icons`，它会为每个候选生成独立 report 并汇总 `animated|visual-static|budget-static|unsupported-static|timeout`。父级首帧内只有一个自播放子 MovieClip、且 `xml2swf` 剥离后 stripped base 在首帧全透明时，工具会把子层按父级 matrix 投影到父 raw bbox，写为 `playback=nested-animation` 的全画布 `frames[]/timelineFrames[]`，第 1 帧直接复用原父级首帧以避免现有图标偏移回归。若父第 1 帧直接挂载一个或多个动效子 MovieClip，且所有动效层都在静态 base 之上、matrix 为 scale/translate，工具会写 `nestedAnimation.strategy=direct-layered-icon-canvas`：manifest 保存 `base` 与各 `layers[*].frames[]/timelineFrames[]`，Web 侧按层独立推进，避免 5 帧与 7 帧子层膨胀成 35 张组合图；单层 120 帧这类素材也走同一 wrapper，不要求至少两层。layer frame 会按透明包围盒裁剪并写 `cropX/cropY/cropWidth/cropHeight/canvasWidth/canvasHeight`，Web 运行时按 256 画布比例放回原位；静态 WebP 写入使用 lossless，legacy PNG 写入使用 `optimize=True`。可用 `--max-animated-icon-bytes` 设置单个动态图标预算，超过时报告 `animatedIconBudgetSkipped`，manifest 回退为静态首帧并清理不再引用的动图文件；若多帧候选视觉上只有同一 `uri + crop`，报告 `animatedVisualStaticDowngraded` 并同样回退静态首帧，避免无意义 runtime tick。导出器会烘焙 PlaceObject 上可支持的 `GlowFilter` / `ColorMatrixFilter` / `CXFORMWITHALPHA`，并用父首帧 oracle 做小范围自动 `offset` 校准，相关 `filters` / `offset` 只作为导出审计元数据，Web 运行时不重新实现 Flash 滤镜。复杂嵌套、非空 base 位移无法校准、旋转/斜切 matrix、层深度交错或不支持滤镜会记录 `nestedIconCanvasUnsupported` / `nestedIconLayeredUnsupported`，不做周期最小公倍数预合成。Web 侧图标入口统一走 `web/modules/icons.js`：`Icons.resolve(name)` 继续只返回 manifest 第一帧，保证旧 tooltip / 只读 URL 调用不被动播放；列表和格子里的生产图标应使用 `Icons.html(name, className)`，它会对 layered manifest 返回 base+layers wrapper 并自动播放；`Icons.applyIconToImage(img, name)` 对普通 PNG 序列动图会增强为自动播放，对 layered entry 只显示静态 fallback，避免替换既有 DOM 引用。manifest 显式 `animated=true` 或 `playback=loop|animated|nested-animation` 且存在多张唯一帧时，模块按 `timelineFrames[]|frames[] + durationFrames` 切换 `src`；legacy `f1/f2` 只作为可访问帧，不自动播放。
  - 图标与纸娃娃共享运行时时间线解释器：`web/modules/asset-timeline.js` 统一处理 `timelineFrames[]` 优先级、`durationFrames/holdFrames`、重复帧是否构成动效、按 fps 取当前帧，以及 nested layer 各自独立周期。`icons.js` 只负责 manifest URL/DOM wrapper，`dressup-doll-renderer.js` 只负责 matrix/origin/Canvas 绘制；两者不能再各自实现一套播放时间线规则。
  - 图标与纸娃娃共享导出端时间线工具：`tools/asset_timeline_export.py` 统一处理 digest 去重、`duplicateOfFrame` 与连续 hold 压缩。图标压缩默认按 `uri` 判断连续显示一致；纸娃娃调用时必须把 `uri/width/height/originX/originY` 作为 identity key，避免同图不同注册点被错误合并。基础回归：`python tools/test-asset-timeline-export.py`；父级首帧 `stop();` 但第一帧内子 MovieClip 仍自播放的语义回归：`python tools/test-nested-animation-stop-semantics.py`。
  - 图标分层运行时验证：`node tools/test-icons-layered-periods.js` 用合成 5 帧 / 7 帧子层覆盖 `Icons.html()` + `Icons.enhance()`，确认 wrapper/layers 结构正确、静态图标不误分层、子层按各自周期独立选帧，同一 URI 但 crop 位置变化也会继续播放，frame budget 是 12 而不是 35；`python tools/test-icon-animation-candidate-filter.py` 验证候选 report 预过滤、策略过滤和源帧数预算；`python tools/test-icon-animated-budget.py` 验证 animated entry 递归文件统计、超预算静态回退、视觉静态降级与不再引用文件清理。
  - 2026-06-18 动图候选基线：`tmp/icon-animation-candidates-status-all.json` 覆盖 `animationStructureCandidates` 14 个候选；在 `--max-animated-icon-bytes 1500000` 下，`金钱` / `K点` 已进入生产 manifest（32 逻辑帧分别压缩为 5 / 12 张 PNG，合计约 524KB），`强化石` / `冰魄矿石` / `月之碎片` 可导出但单图标约 8.0~8.8MB，按预算降级静态，`战术耳机加遮阳帽` 为视觉静态降级，其余 8 个因 stripped base 非空或首帧 diff 过大保守静态。
  - 2026-06-18 覆盖率基线：派生目标 1611，`--resolve-only` 可解析 1512、unresolved 99（88 个 `missing_asset`、11 个 `conflict`）；旧版完整 FFDec 写入曾改写 2354 个 tracked PNG 并造成布局回归，已改为默认保护既有布局。
- **Dressup paper-doll offline（data + XFL rig）**：`python tools/bake-dressup-offline.py --export-assets`
  - 从 `data/items/*.xml` 按 `DressupInitializer.updateDressupKeys` 的性别前缀 / 肢体后缀 / 武器字段规则展开装扮 key，并用 `data/items/asset_source_map.xml` 标注每个 skin key 的 SWF / symbol 来源，输出 `launcher/web/assets/dressup/manifest.json` 与缺口报告 `report.json`。
  - 同时解析 `flashswf/UI/对话框界面/LIBRARY/对话框肖像.xml`、`对话框UI/对话-主角模板.xml` 与 `sprite/主角/*`，抽取男/女 `man` pose、holder `attachMovie(_parent._parent._parent.<字段>, "装扮", ...)`、矩阵、fallback 基本款行为，供 `web/modules/dressup-doll-renderer.js` 在 Web 端 Canvas 复刻对话框主角纸娃娃；dialogue holder 按 XFL `DOMLayer` bottom-to-top 输出以匹配 Flash 视觉栈，身体 holder 的 attach 失败会回到 XFL `基本款`，武器 holder 无装扮时保持隐藏。manifest 还写入 `appearance.faceById/hairById`，用于 Web 端把原始脸型/发型编号归一化为 skinKey。2026-06-18 起 manifest 还写入 `rigs.battle`：解析 `flashswf/arts/things0/LIBRARY/主角-男.xml` 的 `空手站立`、`长枪站立`、`手枪站立`、`手枪2站立`、`双枪站立`、`兵器站立`，按每个 `DOMLayer` 的 active keyframe 合成战斗 holder，并识别 `_root.装备引用配置.配置装扮(...)` 的字段/引用名；`dressup-doll-renderer` 可通过 `initData.rig="battle"` + `initData.stateLabel` 切到战斗姿态。`test-dressup-manifest-integrity.py` 会检查 battle rig 状态、矩阵和必需 holder 字段闭包。
  - `--export-assets` 用 FFDec `symbolClass` / `sprite:png` 导出真实 dressup PNG 帧到 `launcher/web/assets/dressup/skins/`，并用同批 `sprite:svg` 读取每帧相对 Flash 注册点的 `originX/originY`，写回 `skinKeys[*].export + frames[]`；同轮还从对话框 SWF 导出 22 个男女基础身体件并写入 `rig.genders[*].holders[*].basic`。默认 `--zoom 2 --fps 24`，前端按 metadata 缩回 Flash 坐标、按 `originX/originY` 负偏移绘制并播放 PNG frame sequence，避免 zoom 10 造成过大资源。导出阶段还会用 FFDec `script:as` 读取父 sprite 时间轴脚本，并用 `swf2xml` 建 sprite 子图；多帧素材若 `frame_1/DoAction.as` 是纯 `stop();` 且没有自播放后代，按 Flash 首帧停止行为折叠为 `playback=static-first-frame` 的单帧 PNG，避免变形动画在 Web 纸娃娃里无脚本循环播放。若父级停在第一帧但第一帧内存在自播放子 MovieClip，则写为 `playback=nested-animation` 或 `playback=static-parent-nested-animation`；可静态定位的 child 场景会经 `xml2swf` 临时生成 stripped base，把子层从父级/父层对应显示列表移除，再在递归 `nestedAnimation.layers[]` 写入子 sprite 帧序列、Flash 矩阵和 `drawOrder`，由 Web renderer 独立推进子层，避免按周期最小公倍数全量合成；父动画后续帧才挂出的子 MovieClip 若会随父循环重建，则保留在父层帧序列里并计入 `compositedDescendantCount`。带 `onClipEvent(load)` 的条件显示层若脚本语义为 `攻击模式` 命中时 `_visible=1`、否则 `_visible=0`，导出器会用 `xml2swf` 生成 `runtimeVariants.neutral`，并在 `conditionalVisibility` 记录可见攻击模式，renderer 在非手枪/双枪攻击态使用 neutral 变体，避免中立纸娃娃把攻击光束烘进静态 PNG。重复像素帧不再复制 PNG，`frames[]` 保留完整逻辑播放帧并用相同 `uri` + `duplicateOfFrame` 复用文件；连续重复显示帧另写 `timelineFrames[]` + `durationFrames` 压缩运行时时间线，renderer 通过 `AssetTimeline` 优先按该时间线播放，避免类似 80 帧素材后段 50 帧静态 hold 造成 manifest 与运行时遍历浪费；增量导出可用重复 `--name` 或 `--limit`，工具会保留既有未选中 skin key 的 `export/frames/timelineFrames/runtimeVariants/conditionalVisibility`，`report.assetExport.exportedSkinKeys` 只表示本次写入数量，`preservedSkinKeyExports` 表示保留的旧导出条目；若只需规范化既有 PNG/manifest 而不重跑 FFDec，可用 `python tools/normalize-dressup-timelines.py` 补齐同一套 `timelineFrames[] + durationFrames`。`python tools/test-nested-animation-stop-semantics.py` 固定验证父级首帧 `stop();` 只冻结父时间线，第一帧内未停止的多帧子 MovieClip 仍保留为 nested animation；`node tools/test-dressup-renderer-periods.js` 用合成 5 帧/7 帧子层确认 renderer 按层独立选帧且消耗压缩时间轴，frame budget 是 12 而不是 35；`python tools/test-dressup-manifest-integrity.py` 检查真实 manifest 资源闭包、origin/matrix、压缩时间轴、`攻击模式` runtime variant 和 A 兵团背心“父级 1 帧 + 子层动效”样本；`python tools/test-merc-dressup-coverage.py` 检查全量佣兵装备、脸型、发型到 manifest 的运行时闭包，当前兼容别名策略下不允许回退 holder `基本款`。2026-06-19 当前 manifest 基线：覆盖 2840/2840 个 skin key，其中 2820 个 skin key 已带 export；150 个 skin key 通过 compat alias 覆盖（manual=15、auto_opposite_gender=135）；父级逻辑帧 2935、nested layer 逻辑帧 700、基础身体件 22 帧、唯一 PNG 引用 3271、重复帧引用 387、timeline 压缩帧引用 350；真实父时间线循环 16、首帧 stop 折叠 20、nested animation 24，其中 27 个 layer 已可运行时播放、6 个 descendant 由父层帧序列覆盖，`nestedLayerUnsupportedDescendants=0`；`枪-手枪-极品UZI战术版` 已有 1 个 `runtimeVariants.neutral`，由 `conditionalVariantRemovedPlaceObjects=1` 生成；全量 204 名佣兵的 1499 件可渲染装备闭包通过，3265 个部件命中 export，0 个部件回退 holder 基本款；A 兵团精致战术背心身体的父层固定为 1 帧，飘带子层 18 个逻辑帧压缩为 6 个 `durationFrames=3` 的播放段。renderer harness：`web/modules/dressup/dev/harness.html`；生产 Panel harness：`web/modules/dressup/dev/panel-harness.html`；无头验证：`node tools/test-asset-timeline.js`、`python tools/test-asset-timeline-export.py`、`python tools/test-nested-animation-stop-semantics.py`、`python tools/test-dressup-manifest-integrity.py`、`python tools/test-merc-dressup-coverage.py`、`node tools/test-dressup-renderer-periods.js`、`node tools/run-dressup-harness.js --browser edge --sample animated`、`--sample nested`、`--sample nested-a`，以及精确 skinKey 回归 `node tools/run-dressup-harness.js --browser edge --skin-key "男变装-A兵团精致战术背心身体" --gender 男 --field 身体`。
  - `report.missingSourceAudit` 是剩余缺口的来源审计：按当前 `asset_source_map.xml` 与同名 XFL/XML 扫描分类缺失 skin key，并在 `entries[*].references` 反查产生该 key 的 item、性别字段、数据文件、佣兵装备引用数量和样本；当前缺口为 0。`report.compatAliasAudit` 记录不严格等同 Flash attach 行为的兼容别名：2026-06-19 当前 150 个 alias 中，`auto_opposite_gender=135`、`manual=15`，每项都保留 sourceKey、reason、真实 SWF/symbol 和装备引用样本，便于后续回收为真实 linkage。
- **Dialogue portrait offline（SWF/XFL → PNG）**：`python tools/bake-dialogue-portraits.py`
  - 读取 `flashswf/portraits/list.xml` 与同目录 NPC portrait SWF，并读取 `flashswf/UI/对话框界面.swf` 的内部 `DefineSprite 969` + XFL `LIBRARY/对话框肖像.xml` 标签，导出透明 PNG 到 `launcher/web/assets/dialogue-portraits/external|internal/`，同时生成 `manifest.json` 与 `report.json`。manifest v2 按 `charBase`/`expression` 建索引，并为 PNG 写入 alpha `bounds` 供 Web 固定视窗裁切；Web 端通过 `web/modules/dialogue/dialogue-view.js` 消费。`report.missingFrames` 记录 FFDec 无法在对应 label 帧导出 PNG 的表情，运行时会按精确表情 → `普通` → 默认表情 → 第一张图回退，避免空白立绘。2026-06-20 生产基线：90 个角色条目、136 个表达式资产、142 张 PNG、约 15MB；13 个 label 帧暂缺导出图，详见 `report.json`。
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

# Web 资源热重载（默认 OFF）。仅开发期手动开：监听 launcher/web 改动 → 自动 reload 运行态 WebView2。
# 2026-05-28 测试员黑屏复现：watcher 偶发触发 reload 让运行态 web 闪黑，故默认关闭；env CF7_WEB_HOTRELOAD=1 覆盖。
# 注：watcher 排除 launcher/web/icons/ 子树，避免 IconBakeTask 自触发。
webOverlayHotReload = false

# 开关 Native HUD + PanelHostController 装配（Panel-Only 架构）。shipped config.toml 现默认 true；代码 fallback 默认 false（缺 key 时）。
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
useNativeHud = true

# Desktop 顶层 ULW cursor（默认 ON，2026-05 推 default-on 后保留为回滚开关）。
# ON（默认）= DesktopCursorOverlay：desktop 顶层 ULW，跨 anchor 自由 + 单一 visibility 状态机
#   + scale 跟 GuardianForm.ClientSize（窗口级；panel 打开/关闭不再缩 cursor，全屏切换不抖动）
# OFF = 旧 CursorOverlayForm：OverlayBase 子类 + anchor-bound + scale 跟 FlashHostPanel-based
#   viewport（letterbox 黑边不计入；保留作为回滚兜底，无新功能）
# 见 plans/cursor-overlay-decoupling.md。环境变量 CF7_DESKTOP_CURSOR=0 一键回滚旧路径。
useDesktopCursorOverlay = true

# Panel 态是否显式接管前台 + WebView 持焦点（默认 true）。
# true：ResumeForPanel 剥 WS_EX_NOACTIVATE + SetForegroundWindow(this) + controller.MoveFocus(Programmatic)；
#       DoFullIdleSuspend/DoSoftIdleRestore 关闭时 SetForegroundWindow(Flash) 把前台推回。
# false：完全等价旧行为 —— 不剥 NOACTIVATE、不调 SetForegroundWindow/MoveFocus；首次点击仍只切焦点。
# 修首次点击失效"卡手"问题；env CF7_PANEL_TAKE_FG=0 一键回滚。
webOverlayPanelTakeForeground = true

# 渲染合成层诊断（全部默认 OFF；排查 iGPU/DWM 时单独开，env CF7_DIAG_* 覆盖）。
# diagLayerAudit: 顶层 HWND / WS_EX_* 结构快照    diagUlwMonitor: ULW commit 频率 + p50/p95/p99 延迟
# diagEtwDwm: DWM-Core ETW 实时计数（需管理员）    diagReportIntervalSec: 上两者报告周期，clamp [1,60]
# （另有纯 env 开关 CF7_DIAG_FOCUS_PROBE=0 关闭默认 ON 的 UiFreezeProbe 看门狗，无 toml key）
diagLayerAudit = false
diagUlwMonitor = false
diagEtwDwm = false
diagReportIntervalSec = 5
```

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
- WebOverlay 注入 CSS 隐藏 web 端 `#notch` / `#toast-container` / `#top-right-tools` / `#safe-exit-panel` / `#quest-notice-bar` / `#combo-status` / `#jukebox-panel` / `#map-hud` / **`#context-panel`**（整个容器，含 `#quest-row > #map-hud-toggle / EQUIP_UI / TASK_UI` 按钮）避免与 C# 渲染重叠；notch/toast 消息（AddNotice/SetStatusItem/AddMessage）始终走 fallback (NativeHud→NotchWidget / NativeHud→ToastWidget) 而不是 web ExecScript。装备入口由 [RightContextWidget](src/Guardian/Hud/RightContextWidget.cs) 的右侧 `装备` 键接管，通过 [LauncherCommandRouter.cs](src/Guardian/LauncherCommandRouter.cs) 直接 `SendGameCommand("openEquipUI")`，与原 web 路径等价；`任务` 键（与 notice-bar 回退）派发 `TASK_UI`，现已与旧 web notch `NEW_TASK_UI` 合并，统一打开 web 端 `tasks` 面板（`taskPanelOpen` + `OpenPanel("tasks")`），不再走 AS2 `openTaskUI` 唤起
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
- 焦点不变量（`webOverlayPanelTakeForeground=true`，2026-05 起默认）：idle 三件套 `LAYERED | TRANSPARENT | NOACTIVATE` 同时在 → Flash 保前台、click-through；panel 三件套同时**不在** → WebOverlay 真前台 + WebView 持键盘焦点。`ResumeForPanel` 末尾 `BeginInvoke` 排队 `SetForegroundWindow(this) + controller.MoveFocus(Programmatic)`，等当前消息泵循环走完（FlushUiDataBuffer / SetWindowPos 都已落定）下个泵循环再激活，避开同帧前台锁定。`DoFullIdleSuspend` / `DoSoftIdleRestore` 收尾 `SetForegroundWindow(Flash)` 把前台推回。env `CF7_PANEL_TAKE_FG=0` 一键回滚到 NOACTIVATE 永挂的旧行为（首次点击仅切焦点），不需 revert commit。日志关键字：`[Panel] EX_STYLE panel-on / idle-full / idle-soft`、`[Panel] take-foreground fg=... ctrl=...`、`[Panel] restore-flash-foreground fg=...`
- 性能收益：panel 打开期 α blend 成本下降（panel 矩形小 + opaque）；idle 期 `DoFullIdleSuspend` 整个 SW_HIDE WebView2 + TrySuspendAsync → 拿回 ~15pp DWM α 地板（所有常驻 HUD 已迁到 C# widget，玩家在 panel 关闭期间仍能看到 notch / toast / 货币 / combo / RightContext 右侧 cluster）
- panel 态跟随：PanelHost.DoOpen 订阅 `ownerForm.LocationChanged`（拖窗）+ `FlashHostPanel.SizeChanged`（全屏/最大化/还原 → ResizeFlashToPanel 完成后才触发，比 owner SizeChanged 时序晚但读到的 viewport 正确）。BeginInvoke 节流合并多次事件 → 调 `WebOverlayForm.GetCurrentAnchorScreenRect`（与 SyncPosition 同算法）→ `PanelLayoutCatalog.GetRect` 重算 panelRect → `NativePanelBackdrop.RepositionTo` + `WebOverlayForm.RepositionForPanel`（两者均 `SWP_NOZORDER` 不重排避免拖动闪烁，不 `SWP_FRAMECHANGED` 跳过 NCPAINT）+ `InputShield.EnterTelemetryMode` 重设。**不**主动 ReTop HitNumber/Cursor——SWP_NOZORDER 已保证 z-order 不变。DoClose / ResetToClosedState 反订阅

#### Native HUD parity gate

`useNativeHud=true` 扩散或改默认前，必须先过刘海栏 + 右侧 HUD 视觉/功能等价 gate：刘海栏由 [NotchOverlay](src/Guardian/NotchOverlay.cs) 复刻 web `#notch` 居中 pill、`28px` row1、hover 展开 toolbar、未 game-ready 仅显示 row1-right；combo 由 [ComboWidget](src/Guardian/Hud/ComboWidget.cs) 复刻 web `#combo-status` 输入提示、DFA/Sync 命中扫光、字符收束与收起；toast 和 `game` notice 也必须保持 Web 队列/去重/生命周期语义。右侧 cluster 由 [RightHudLayout](src/Guardian/Hud/RightHudLayout.cs) 固定复刻旧 Web 常量（`right:80px`、`width:170px`、5×`34px` 顶部工具、地图 `86px`、任务行/通知行 `32px`、jukebox `24px`），小地图需显示与 web `map-hud-svg-silhouette` 等价的 PNG alpha 剪影 + current/beacon。人工截图对比旧 Web 与 native：基地场景、任务完成可交付、小地图展开/折叠、未播放/播放中 jukebox、combo 输入/命中、toast/notice 堆叠、暂停态、安全退出弹出、各 panel 开关后 idle；通过标准是位置、宽度、纵向顺序、点击区域、文案和主要颜色层级等价，允许 GDI+/CSS 字体抗锯齿差异。性能回归仍要确认 idle WebView2 `SW_HIDE`，Ctrl+G / Task Manager 采样不比当前 native HUD 基线明显退化。

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

#### 渲染合成层诊断（`diag*` + UiFreezeProbe）

排查 iGPU / DWM / ULW 合成成本的一组只读探针，集中在 [`src/Diagnostic/`](src/Diagnostic/)，由 [DiagnosticsBootstrap.cs](src/Diagnostic/DiagnosticsBootstrap.cs) 按 config 启停（全部默认 OFF，关闭时零日志）：

| 开关 | env | 行为 |
|------|-----|------|
| `diagLayerAudit` | `CF7_DIAG_LAYER_AUDIT` | 顶层 HWND + `WS_EX_*` 结构快照，startup / post-ready / shutdown 各 dump 一次（无需管理员） |
| `diagUlwMonitor` | `CF7_DIAG_ULW_MONITOR` | `OverlayBase` ULW（UpdateLayeredWindow）commit 频率 + p50/p95/p99/max 延迟，按 `diagReportIntervalSec` 报告 |
| `diagEtwDwm` | `CF7_DIAG_ETW_DWM` | 订阅 `Microsoft-Windows-Dwm-Core` ETW provider 计数事件/秒；**需管理员**，非提权 warn + skip |
| `diagReportIntervalSec` | `CF7_DIAG_INTERVAL_SEC` | 上两者报告周期，clamp `[1,60]`，默认 5 |

[UiFreezeProbe.cs](src/Diagnostic/UiFreezeProbe.cs) 是独立后台线程看门狗，**默认 ON**（env `CF7_DIAG_FOCUS_PROBE=0/false/off/no` 关），每 1000ms 观测 UI 线程 Forms.Timer 卡顿、前台 `GetForegroundWindow()==NULL` 真空、guardian/flash 的 `IsHungAppWindow`，只记日志不改焦点（与「前台 / 激活状态管理」节的前台看门狗互补）。由 [GuardianForm.cs](src/Guardian/GuardianForm.cs) 构造/拆除，不进 Program.cs 装配链。

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
| `--project-root <abs>` | bootstrap 注入的项目根绝对路径（FDD 产物 `AppContext.BaseDirectory ≠ projectRoot`，必须显式传）；`Program.cs` 在其余 flag 检测前从 args 剥离，次选 walk-up 哨兵 `crossdomain.xml`、fallback `Environment.ProcessPath` 父目录 |
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

WebView2 通过 `chrome.webview.postMessage({cmd, ...})` 发消息。所有 27 个 cmd：

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
| Font pack | `fontpack_status` | 拉字体包 manifest 安装状态 → `fontpack_status_resp`（转发 FontPackTask op=status） | 任意 |
| Font pack | `fontpack_install` | 下载指定 `group` → `fontpack_install_resp` + `fontpack_progress` 推送（FontPackTask op=download_group） | 任意 |
| Font pack | `fontpack_cancel` | 取消进行中的字体包下载 → `fontpack_cancel_resp` | 任意 |
| Repair | `repair_detect` | C2-β 存档修复：检测扫描（RepairCommandHandler） | 任意 |
| Repair | `repair_apply_manual` | C2-β 存档修复：手动应用选中修复 | 任意 |
| Repair | `repair_force_continue` | C2-β 存档修复：跳过修复强制继续 | 任意 |

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

测试员反馈"听不到音效"。日志比对：每次启动 Flash 拉档后立即推 `master_vol=0` + `bgm_vol=0.01`，存档里 `others.设置.setGlobalVolume:0` 是源头。Flash 的"设置 UI"已被移植到启动器的迁移计划里，但移植期 UI 缺位，玩家踩进 0 音量后没有可见的恢复入口（参考 [SaveManager.as:1823-1868](../scripts/类定义/org/flashNight/neur/Server/SaveManager.as) 的 packSettings/applySettings 协议）。

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

[AudioTask.cs](src/Tasks/AudioTask.cs) `HandleMasterVol` / `HandleBgmVol` 在收到 Flash 推送的可疑值时，调用注入的 `IToastSink` 弹一次 toast，提示"音频设置 UI 迁移中，可在存档编辑→简易模式→系统调整"。每次 launcher 启动只触发一次（`_volumeWarningEmitted volatile bool`），重启 launcher 才会再次提示，避免反复打扰。Sink 注入点：[Program.cs:735](src/Program.cs)（`AudioTask.SetToastSink(toastSink)`）。

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

[build.ps1](build.ps1) 的 `Step 7b` 会校验 `save_schema.json` 存在；缺失时报错并提示运行 `node tools/extract-save-schema.js`。当前 diff 视图主要靠 schema 里 inline 的 `default`，`save_schema.json` 是为后续 diff 范围扩展（不在 schema 白名单内的任意字段）准备的基线。

### 迁移完成后的清理路径

> 当 Flash 设置 UI 迁移到启动器内（脱离档存盘）之后，本节相关代码可分级退役：
>
> - **必删**：[archive-schema.js](web/modules/archive-schema.js) 中 `system` category 的两条音量字段、[archive-editor.js](web/modules/archive-editor.js) 中 `card-temporary-hint` 文案、`audio.master/bgm/sfx` 预览分支。
> - **降级**：`AudioTask` 兜底 toast 可降为低优先级 log（迁移完成后玩家有正常 UI 路径恢复）。
> - **保留**：诊断包导出、Ctrl+F、diff 视图、危险字段解锁机制 —— 这些是通用能力，不绑迁移期。

## 关键设计决策

### Flash 嵌入（SetParent）
Guardian 通过 Win32 `SetParent` 将 Flash Player SA 窗口嵌入 `_flashPanel`（WinForms Panel），移除标题栏/边框/菜单栏。500ms 看门狗定时器检测全屏等操作导致的脱离并自动重新嵌入。

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

### 前台 / 激活状态管理（AppActivationState + 前台看门狗）

**`AppActivationState`**：应用激活状态的权威源，取代散落在 `KeyboardHook` / `PerfDecisionEngine` 里的 `GetForegroundWindow()` 现场轮询。

- **激活信号**来自 `WM_ACTIVATEAPP`（进程级——同进程窗口间切换不触发），**最小化信号**来自 `WM_SIZE`/`SIZE_MINIMIZED`，均由 `GuardianForm.WndProc` 在 UI 线程喂入；字段 `volatile` + 单调 `TickCount`，无锁。
- **去抖**：后台程序（QQ/Telegram 通知）瞬间抢焦再归还会产生 `WM_ACTIVATEAPP(false)→(true)` 抖动；失活留一个 200ms 宽限窗，窗内重新激活视作从未失活。
- 消费方：`KeyboardHook.ShouldInterceptForOurApp`（判按键是否归本应用拦截）+ `PerfDecisionEngine`（失活 / 最小化时停决策，避免后台降帧污染 tier）。
- **strict 例外**：破坏性键 Ctrl+Q（`ForceExit` 杀进程）不吃去抖宽限——`KeyboardHook` 对它走 strict 路径，要求实时前台归属本应用，避免用户切走后宽限窗内误把启动器干掉。

**前台看门狗**（`GuardianForm` 400ms 定时器）：兜底层。后台程序抢焦后未归还前台会留下"焦点真空"（`GetForegroundWindow()==NULL`），导致快捷键失灵 + Flash 降帧。看门狗检测到**持续**真空（连续 ≥2 tick 确认，规避前台交接瞬态误判）后，调 `WindowManager.RestoreFlashInputFocus` 把前台回收给 Flash。锁屏 / 安全桌面期间（`SystemEvents.SessionSwitch`）停转，避免空刷日志。

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

**BGM 可视化 + 点歌器**：`PeakDetector` 自定义节点（`ma_node_vtable` passthrough）插入 bgmGroup → engine endpoint 之间，实时采样 L/R peak。C# 60ms 轮询 `ma_bridge_bgm_get_peak/cursor/length/is_playing` → WebView2 `PostWebMessageAsJson` 推 `audio` 消息。折叠态由 C# `RightContextWidget` 的 jukebox titlebar 接管（mini wave + 标题 + pause/expand）；展开 UI 是正式 panel：[jukebox/jukebox-panel.js](web/modules/jukebox/jukebox-panel.js) 注册 `Panels.register('jukebox')`，由 `JUKEBOX_EXPAND` → `LauncherCommandRouter.OpenPanel("jukebox")` → `PanelHostController` 走完整 backdrop / EX_STYLE / HUD-suspend 序列后渲染大波形 + 进度条 + 专辑浏览 + 选曲 + 设置（音量 / 覆盖关卡BGM / 真随机 / 播放模式）+ 帮助 markdown。曲目标题由 AS2 `pushUiState("bgm:title")` 经 UiData 推送（jukebox-panel.js onOpen 通过 `UiData.get('bgm')` seed 当前值，避免 panel 晚于启动期打开错过历史推送），设置状态由 `jbo:/jbr:/jbm:/vg:/vb:` 通道同步。catalog 由 `MusicCatalog` 在启动期 + 文件变更时增量推 `catalog`/`catalogUpdate`；后开 panel 缺失时主动 `cmd:'requestCatalog'` 拉全量。Web 旧 [modules/jukebox.js](web/modules/jukebox.js) 已注释脚本入口（DOM 暂留 Phase 7 删除），不再参与运行时音频/UiData 订阅。

**SFX**：启动时扫描 `sounds/export/{武器,特效,人物}/` 目录，文件名即 linkageId，覆盖顺序武器→特效→人物（后覆盖前）。Flash 侧帧内累积，帧末由 FrameBroadcaster 合批发送 `S{id1}|{id2}|{id3}` 快车道消息。native 层 30ms 去重（`miniaudio_bridge.c` `DEFAULT_THROTTLE_MS=30`）。

**路径编码**：所有字符串参数使用 `wchar_t*` (UTF-16)，文件操作用 `ma_sound_init_from_file_w()`，支持中文路径。

**音效资产**：由 `tools/export_sfx.py` 调用 FFDec CLI 从 SWF 批量导出并重命名为 linkageId，运行时无需 manifest 文件。

### 性能调度迁移（PerfDecisionEngine）
原 AS2 端的完整反馈控制回路（Kalman 滤波→PID→迟滞量化→执行器，~1400 行）已迁移到 C# launcher 端。

**迁移依据**：PID 被数学证明退化为阈值生成器（Proposition 1, 97.4% 积分饱和率），迟滞量化器是实际控制权威。

**架构**：
- **C# PerfDecisionEngine** (~250 行): 滑动窗口统计(mean5/trend10) + 直接阈值 + 2/3 非对称迟滞确认 + 方差自适应
- **AS2 PerformanceScheduler** (~250 行，薄壳): 采样 + FPS 广播 + 接收 P 指令执行 + 本地后备
- **P 前缀快车道** (C#→AS2): `P{tier}|{softU_x100}\0`，零 JSON 解析
- **失活抑制**: `AppActivationState`（WM_ACTIVATEAPP 驱动、去抖）的 `IsAppActive`/`IsMinimized` 门控，先于 panic 判定；toast 瞬时抢焦不算失活，panic 兜底不被掐断（详见下文「前台 / 激活状态管理」）
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
   │       AMF0 → JObject，Flash SOL Reference raw-1 解析（真实 Flash fixture 回归验证）
   │
   └─ [5] 版本分流：
         ├─ SOL 缺失 + shadow 有效     → Snapshot(json_shadow)
         ├─ SOL 缺失 + shadow 无效     → Empty
         ├─ soData._deleted == true    → Deleted
         ├─ mydata.version == "3.0"
         │    └─ ValidateDualWriteConsistency（dual-write tripwire；不一致则不信任 SOL）
         │        → MergeTopLevelKeys + ValidateResolvedSnapshot
         │        ├─ pass + shadow 新鲜（lastSaved >=）→ Snapshot(json_shadow)
         │        ├─ pass + shadow 更旧 / 无效         → Snapshot(sol)
         │        └─ fail → shadow 新鲜（lastSaved >=）则 Snapshot(json_shadow)
         │                   否则 Corrupt(dual-write 一致 → v3.0_structure_invalid，否则 → v3.0_dual_write_mismatch)
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
  "saveDecision": "snapshot" | "empty" | "deleted" | "needs_migration" | "corrupt" | "repairable",
  "snapshot":       /* 当 decision == snapshot：已验证的 mydata JObject */,
  "snapshotSource": "sol" | "json_shadow",
  "corruptDetail":  "v3.0_structure_invalid" | "v3.0_dual_write_mismatch" | "sol_no_test_field" | ...
}
```

> `saveDecision: "repairable"`（C2-β 存档修复路径）不像其余决议直接透传给 Flash，而是由 Launcher 侧 `RepairCommandHandler` / 存档修复卡片在 handshake 前处理（见 cmd 分发表 `repair_detect` / `repair_apply_manual` / `repair_force_continue` 与 [repair-card.js](web/modules/repair-card.js)）。

Flash 侧 `通信_fs_bootstrap.as` 把这些字段透传到 `_root._launcher*`，`SaveManager.preload()` 一次性消费（`_protocol2Consumed` 幂等锁覆盖 asLoader frame 4 + 主 FLA frame 63 双调用），然后：

- **snapshot**：`_root.mydata = snap` → `loadAll` 里直接走 `loadFromMydata` 快路径
- **deleted**：`so.clear(); so.data._deleted = true`，`_root.mydata = undefined`
- **empty**：`_root.mydata = undefined`（新游戏）
- **needs_migration / corrupt**：`_deferredResolutionAttempted = true` + `_skipPrefetch`，穿透到 AS2 同步 SOL 读取；若 SOL 也空则升格为 `_root._saveRestoreError = true` 走"存档损坏" UI

关键性能收益：原来 `loadAll` 内等待 launcher JSON prefetch 的自旋消失，实测 `preload → ready` 零等待。

**Launcher 侧复用的数据源**（`launcher/src/Save/` 中决议主路径相关的 6 个核心文件；该目录另含修复子系统 / 版本 gate / 接口等，共 19 个 .cs）：

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
- **Application.ThreadException**：接管 WinForms 默认错误对话框；退出期异常只写日志并压掉弹窗，运行期 UI 线程异常按 fatal 记录后触发 `ForceExit`
- **AppDomain.UnhandledException**：非 UI 线程未处理异常写日志

### Flash UI → Web 迁移

以下 Flash 主文件实例已迁移到 Launcher WebView2 overlay，释放 Flash 内存并提高 GC 效率：

AS2 UI → Web Panel 迁移的操作护栏统一见 [../agentsDoc/as2-web-panel-migration.md](../agentsDoc/as2-web-panel-migration.md)。迁移任务必须按该文档维护 Web cmd → C# Task → AS2 handler → response task → panel_resp → JS handler 闭环表，并明确 dev harness / 生产 panel / Flash smoke / 游戏内手测边界。

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
| 战队界面 | Panel 系统 `team/team-panel.js`（佣兵 / 伙伴 / 战宠 / 机械；宠物管理/领养/进阶 + 佣兵管理/雇佣/培养） | `TEAM` → `mercPanelOpen` + `team`；子控制器继续使用 `pets` / `mercs` Task 协议 |
| 竞技场 (DEATH MATCH) | Panel 系统 `arena-panel.js` (8 张角斗场卡) | `arena`，ArenaTask 双层 callId |
| 情报界面 | Panel 系统 `intelligence-panel.js` (H5 富文本) | `情报`/`INTELLIGENCE`，IntelligenceTask 按需正文 |
| 任务界面 | Panel 系统 `tasks/task-panel.js` (当前任务列表/详情) | 刘海屏 `任务` 键 `TASK_UI`（含 `NEW_TASK_UI` 合并）→ `taskPanelOpen` + `tasks`，TaskTask 双层 callId |
| 副本任务（委托任务，旧 FLA Symbol 1873） | tasks 面板第 4 tab `副本任务`（左难度档 + 右详情/委托对话，复用 DialogueView） | NPC「获得任务」→ AS2 `openWebDungeon`(panel_request initData{view,taskId})；cmd `dungeonDetail`/`dungeonBriefing`/`dungeonEnter` 复用 TaskTask + `task_response`；进图写门控在 AS2（金钱/等级/K点）。详见 docs/副本任务-Web面板迁移-架构设计-2026-06-26.md |

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

本节最后核对代码基线：commit `07a0a09d9f`。

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
- **map**（地图面板）: `web/modules/map-panel.js` + `web/modules/map-canvas-stage-renderer.js` + `web/modules/map-panel-data.js` + `web/modules/map-fit-presets.js`；纯 Web panel，走 `panel/panel_resp` 的 `snapshot` / `refresh` / `navigate` / `open_stage_select` / `close` 协议；当前 `snapshot` 额外承载 `unlocks / hotspotStates / currentHotspotId / markers / tips`，四个正式页面的舞台视觉由 Canvas 2D renderer 绘制（DOM 仅保留透明热点、hover 标签、右侧 rail 与操作按钮），右侧层级按钮缺少原始素材时允许直接使用 Web/CSS 复刻旧视觉语言；`map-panel.js` 会懒加载 `stage-select-data.js`，用 `RootFadeTransitionFrame` 为已解锁且有选关页签的热点提供二级“选关”动作，成功后交给 PanelHost 关闭 map 并打开 `stage-select`，主热点点击仍发送 `navigate`；同时支持 browser harness `web/modules/map/dev/harness.html`、preview `web/modules/map/dev/preview.html`、builder `web/modules/map/dev/builder.html`、CLI 导出 `tools/export-map-manifest.js`、fallback 复核 `tools/audit-map-layout.js`、filter-fit 离线调优 `tools/tune-map-filter-fit.js`、审计图导出 `tools/render-map-audit-sheet.py` 与可选的 Kimi 视觉复核 `tools/kimi-map-review.ps1`，并在紧凑视口下自动缩放舞台、按 page/filter preset 做二次 content-fit；右上角常驻 HUD 由 `web/modules/map-hud.js` 消费同一份 `MapPanelData` + UiData `mm/mh`，只显示当前区块高亮与固定 beacon，点击后打开 map panel
- **stage-select**（选关界面 Stage 2 runtime）: `web/modules/stage-select-panel.js` + generated `web/modules/stage-select-data.js`；可通过 Native HUD “其他 → 选关测试” 的 `STAGE_SELECT_TEST` 打开，也可由 AS2 场景门 `openWebStageSelect` → `panel_request stage-select` 正式打开。支持 16 个 frame label、182 个源 XML 入口实例、164 个 Web 运行时渲染实例（含 13 个 `entryKind=map/task` 直达入口）、fixture 锁定/任务/挑战模式、按外部 PNG / 内部命名帧 / 默认帧回退的 hover 预览、browser harness 和 FFDec/Web 视觉对照审计；runtime 下使用 `stageSelectSnapshot` 读取真实解锁/挑战状态，普通难度按钮通过 `stageSelectEnter entryKind=difficulty` 进入已解锁关卡，外交地图按原版绿色点直达、从源符号内部 `shape/外交地图点` / `DOMDynamicText` 矩阵复原点和文字位置、通过 `entryKind=map` 走 AS2 淡出跳转且不显示二次选择，旧外交地图 SWF 内仍指向 Flash `关卡地图` 的门由公共 `切换场景` 捕获后打开 Web 选关，`地图-*` frameLabel 会按 `StageInfoDict.RootFadeTransitionFrame` 反查回选关页签，魔神/副本任务区域把 `Symbol 3325 -> Symbol 3323 -> bitmap3321` 导出的法阵底图放在装饰层，文字按钮仍按 XFL 源矢量 CSS 复刻，通过 `entryKind=task` 直接打开原 Flash `委托任务界面`，`localFrame` 通过 `jump_frame` / `stageSelectJumpFrame` 同步 Web 当前选关页但不改 `_root.关卡地图帧值`，return 类 nav 通过独立 `returnFrameLabel` + `return_frame` / `stageSelectReturnFrame` 复刻原版 `_root.淡出动画.淡出跳转帧(_root.关卡地图帧值)`，同场景返回会直接关闭 Web panel、跨场景返回仍淡出跳转，避免旧外交地图底层场景泄露。runtime 布局隐藏测试标题、fixture/dev 控件与右侧空栏，frame tab 默认收纳到可展开区域菜单，旧 Flash `关卡地图` 保留为 fallback
- **intelligence**（情报详情面板）: `web/modules/intelligence-panel.js` + `web/modules/intelligence-components.js`；正式入口为 Native HUD / 旧 Web notch 主工具栏的 `情报` / `INTELLIGENCE`，开发入口 `其他 → 情报测试` / `INTELLIGENCE_TEST` 保留。正式 runtime 走 `state` → `snapshot(itemName)` → `tooltip(itemName)`：AS2 只返回每条情报收集值、解密等级、玩家名和 TooltipComposer 富文本，C# `IntelligenceTask` 从字典、物品 XML 与 `data/intelligence_h5/<itemName>.json` 读取白名单 H5 正文，Web 不直接 fetch 项目根或 `data/`。H5 正文由 `IntelligenceComponentRenderer` 以 DOM API 渲染，锁定页不下发 blocks，关闭时不通知 Flash。协议、组件语义、手工创作流程和验证门禁见 [情报 H5 组件创作交接](../docs/情报H5组件创作交接.md)
- **tasks**（任务界面）: `web/modules/tasks/task-panel.js` + `css/task_panel.css`；入口为刘海屏 Native HUD 右侧 `任务` 键（`TASK_UI`，含 notice-bar 回退）以及旧 Web notch “新任务界面” `NEW_TASK_UI` —— 两者已在 `LauncherCommandRouter` 合并，先发 `taskPanelOpen` 再打开 `tasks` panel，不再走 AS2 `openTaskUI` 唤起。运行态协议为 `snapshot` / `detail` / `tooltip` / `finishTask` / `deleteTask` / `navigateFinish` / `treeState` / `replayDialogue`，`TaskTask` 桥接到 AS2 `TaskPanelService` 的 `taskSnapshot` / `taskDetail` / `tasksTooltip` / `taskFinish` / `taskDelete` / `taskNavigateFinish` / `taskTreeState` / `taskReplayDialogue`，response task 为 `task_response`。snapshot 的 `satisfied` 字段复用游戏内交付权威判定 `_root.taskCompleteCheck(index)`，同时覆盖关卡、提交/持有物品与特殊需求，禁止仅用 `requirements.stages.length` 推断完成状态。**共享判定条件（`conditions`，2026-06-11 判定层共享）**：任务数据可选字段 `conditions:[{type,params,target,label,sinceAccept?}]`——与成就共享 `ObjectiveEvaluator.rawOf` 的 9 类指标（枚举单源 `tools/lib/objective-types.js`），任务由此获得「击杀 N 敌人/花费 N 金币」等成就级表达力；`sinceAccept` 窗口语义由 AddTask 拍基线进 `requirements.condBase`；`taskCompleteCheck` 与老字段合取；`detail` 回 `conditions:[{label,cur,target}]` 进度行（web 渲染 cur/target+进度条）；含 conditions 的任务借成就 `scanTick` 10s 心跳刷新红点（无事件指标如击杀数才能翻转达成态）。生命周期/奖励链不共享，详见 [docs/任务成就-判定层共享-设计-2026-06-11.md](../docs/任务成就-判定层共享-设计-2026-06-11.md)（§8 为 V8 判定下沉草案，未开工）。物品 `tooltip` 为 name-keyed，AS2 调 `_root.Web物品注释HTML` 返回 `introHTML/descHTML/itemType`——物品类型字段必须叫 `itemType`，**不可用 `type`**（会覆盖 `panel_resp` 信封的 `type`，Bridge 按 `data.type` 路由会整条丢包）。**写操作（交付/删除，2026-06-08 WS5）**：前端一律传 `taskId`（稳定主键）**不传 index**——AS2 `FinishTask/DeleteTask` 会 `splice(tasks_to_do)` 致 index 偏移，AS2 端按 `taskId` 解析当前 index；交付走 `_root.taskCompleteCheck` 服务端硬门控（`FinishTask` 自身不校验完成度，原版门控在 NPCTaskCheck），背包装不下回 `inventory_full`；删除拒绝主线（`cannot_delete_main`）；两类回包都附带刷新后的 `tasks` 概要（与 snapshot 同形状），前端 `applyWriteSnapshot` 按 `taskId` 原子重渲并尽量保留选中；删除请求在途时弹窗取消/遮罩被 `_busy` 锁屏蔽（防"以为取消却被删"）。**远程交付门控（可选玩法增强 `finish_remote`）**：任务数据新增布尔字段 `finish_remote`（`data/task/*.json`，缺省 false），仅标记为 true 的任务允许面板「交付任务」直接远程交付；其余任务保持原版玩法——必须前往 `finish_npc` 处由 NPCTaskCheck→FinishTask 交付，面板按钮显示「前往「NPC」交付」禁用态，AS2 对非远程任务回 `requires_npc`（服务端硬门控，NPC 交付路径不经 handleFinish 故不受影响）；`detail` 回包附 `finishRemote` 供面板决定按钮态。**前往交付（便利增强 `navigateFinish`，2026-06-09）**：非远程任务的主操作按钮变为「前往交付」——复用地图 `MapTaskNpcRegistry`（finish_npc→hotspot）+ `MapPanelService.canNavigateToHotspot/navigateToHotspot` 把玩家一键送到交付 NPC 的地图位置（只负责前往，到达后仍由玩家点 NPC 正常交付）；可达性 = 非战斗地图 + 热点已登记 + 所在组解锁，`detail` 回 `finishNavigable` 决定按钮可点态（可前往=「前往交付」可点，不可前往=「前往「NPC」交付」禁用），成功回 `closePanel:true`（前端关面板让场景淡出跳转），不可达回 `not_navigable`。前端（2026-06-08 UI/UX 升级）含：五类筛选 chips（主线/支线/副本/情报/其他，由 `chain[0]` 链名在前端 `CATEGORY_MAP` 归并）、卡片/列表双视图、排序、计数概览、detail 缓存、骨架屏、富物品 tooltip（复用 `PanelTooltip`，缓存+失败退避）、转圈→勾选可交付徽章、常驻扫光等入场动效与 `prefers-reduced-motion` 降级、详情底部交付/放弃操作区 + 放弃确认弹窗 + 操作锁；**功能层配色统一黑白灰，焦点橙只留给提交NPC卡，难度色为原版语义真值**。**事件日志 / 任务树 Tab（WS6，2026-06-09）**：「事件日志」tab 渲染链式任务树 + 剧情对话回放。数据按可变性切分单一权威：**静态目录**（树拓扑 + title + description + 明细字段）由 **build Step 1e** 经 `tools/derive-task-catalog.js` 从 `data/task/*.json`（游戏权威源）派生为 `web/modules/tasks/task-catalog.json`，web **直读零 AS2 传输**（派生器含闭包校验器：title/description/get_conversation/finish_conversation 的 `$KEY` 必须存在于合并 `task_texts`，否则 build exit 1）；**动态进度**经只读命令 `treeState`→AS2 `taskTreeState` 回 `chainsProgress`+已完成 id 集 `finished`+进行中 id 集 `active`（载荷极小，非全表）；**剧情对话回放（Web 立绘组件）**经 `replayDialogue {taskId,which}`→AS2 `taskReplayDialogue` 按需回传【单条任务】的对话文本行 `lines:[{speaker,sub,text,char,charBase,expression,portraitType,target?,imageurl?}]` + `heroPortrait`（name/title 经 `getDialogueSpecialString` 解析 `$PC` 等特殊串），web 在详情区内联展开对话、**不关面板（体验连续）**。`speaker/sub/text` 经共享 `PanelTooltip.convertAS2Html` 渲染 **AS2 htmlText 子集**（`<FONT COLOR/SIZE/FACE>`→span style、`<B>/<I>/<U>`、`<BR>`、`<P ALIGN>`，含颜色/字号/face 白名单校验，安全）——例：`$PC_TITLE`→`HeroUtil.getHeroTitle()` 回的 `<FONT COLOR='#FFCC00'>动态称号</FONT>` 正确着色。对话文本仍单权威留 AS2（catalog 只含 `hasGetConv/hasFinishConv` 布尔，点击才按需回传一条任务的对话，载荷小、懒加载）。**刻意不支持**（留待对话框整体迁 web 的富文本阶段，避免现在引入复杂度/风险）：`<A HREF>`（asfunction 无法 web 执行+安全）、AS2 htmlText 内联 `<IMG>`（立绘改走结构化字段 + `dialogue-portraits` manifest）、`<TEXTFORMAT>`、`<LI>`。树节点状态=已完成/进行中（由进度叠加判定）；明细复用 mine 详情结构（read-only，无交付/放弃）。**图表视图（BALDR SKY 风，2026-06-09）**：事件日志内「列表/图表」切换，图表以六边形节点（CSS clip-path）+ SVG 前置连线空间化呈现任务链的**前置依赖关系**（弥补列表线性、看不出任务线前置顺序的短板）。布局=「拓扑深度分行 + 按链分列 + 前置连线」（数据实证为主干+分支结构，237/238 单前置、跨链边多为主线里程碑→侧链入口，故无需重型 DAG 算法；委托等无序号链不入图）；状态色黑白灰真值（已完成银/进行中白发光/未解锁暗），选中=白环放大（不动焦点橙）；**任务线配色**经三杠杆区分——外环色 `--hex-rim`（链身份主区分）+ 数字色 `--hex-num` + 可选面色 `--hex-face`（阵营链黑底白字），由 `CHART_CHAIN_STYLE` 配置下发（**写手可改**，状态与链色正交：状态只驱动面色+辉光，链色走环/数字不抢读）；**对话回放按进度门控**（接取对话仅已接取显示、完成对话仅已完成显示，不剧透未到达剧情）；含 100/50/25% 缩放（CSS zoom）与详细/章节双粒度（章节折叠线性段、仅留链头尾+分支/合并点+进行中）；**左键拖拽平移取代滚动条**（隐藏滚动条、grab/grabbing 光标，保留滚轮；「点击 vs 拖拽」按 4px 阈值判定，拖拽末尾 click 被抑制不误选节点）；点节点复用同一明细+内联对话。catalog 为此加回 `req`（前置 id，画边+算深度，约 +3KB）。详见 [docs/web-task-panel-WS6-事件日志任务树-设计-2026-06-09.md](../docs/web-task-panel-WS6-事件日志任务树-设计-2026-06-09.md)。验证：dev harness `web/modules/tasks/dev/harness.html`（`?qa=1` 跑 task-ui1~41 + ach-ui1~13，含写操作门控/交付移除/放弃确认/背包满/ESC modal栈/远程交付门控+绕过按钮服务端门控/删除在途锁/前往交付/finishNavigable 不缓存固化/**事件日志树渲染+对话按钮可见性+回放内联文本（不关面板，远程交付成功才关面板露原版奖励/对话）+tab往返+图表视图+XSS清洗+图表防剧透+服务端对话门控**）+ `node tools/run-tasks-harness.js --qa|--shot=...&--query="tab=log|tab=ach"`（Edge headless）+ `TaskTaskTests.cs`（xUnit 26 facts，含「Web 夹带 action/task 不可覆盖可信 action」安全反向用例及成就桥 7 用例）。`finishNavigable` 为 AS2 动态计算，前端缓存静态详情但对其做有界后台复查（仅"满足+非远程+当前不可前往"时重选复查），不被缓存永久固化。close 会发 `taskPanelClose`（当前 AS2 no-op），不写存档。**成就 Tab（A 轮 2026-06-10）**：tasks 面板第三 tab「成就」，实现于独立文件 `web/modules/tasks/achievement-tab.js`（panels-lazy-registry deps 先于 task-panel.js 加载；task-panel 经 `TaskAchievementTab.install/reset/enter` 装配，claim 在途复用 `_busy` 锁拦切tab/关面板/二次点击；样式追加进 `css/task_panel.css` 不新建 css）。**静态目录** = build **Step 1f** 经 `tools/derive-achievement-catalog.js` 从 `data/achievement/*.json`（成就权威源，manifest `data/achievement/list.xml`，AS2 `AchievementDataLoader` 读同一源）派生 `web/modules/tasks/achievement-catalog.json` web 直读；派生器校验（失败 build exit 1）：objective 枚举白名单（infraLevel/infraBuiltCount/killTotal/taskFinished/chainProgress/skillLevel/itemOwned/economyCount）、跨域闭包（taskFinished.taskId ∈ 任务集；chainProgress 链存在且 target ≤ 链最大 seq）、economyCount counter 白名单=**正则解析 `AchievementMetrics.as` buildValid 函数体单源**（AS2 类编译器不接受对象字面量字符串键，故 .as 用 `v["键"]=true;` 赋值式——解析与之配套，格式勿改）、claim.mode 仅 remote 且条目含 `finish_remote` 字段即 fail、rewards 黑名单{经验值}+单条禁同名重复、title/description 禁 `$` 前缀；**hidden 条目脱敏输出**（title/description="???"、rewards=[]、objective 剔 params——明文含奖励仅经 AS2 `hiddenReveals` 对已解锁条目按需回传，防剧透双层）。**动态状态**走 `achievementState`（只读叠加 unlocked/claimed/progress/hiddenReveals/dataReady；hidden 未解锁条目不回 progress 防可探测）；**领取**走 `achievementClaim {achievementId}`（稳定主键非 index；**全称命名**——裸名 `claim` 会被 WebOverlayForm 在 panel 判别前无条件路由 ShopTask）。AS2 `AchievementService` 门控链：not_ready / achievement_not_found / not_unlocked（unl 锁存位图‖现算，服务端权威不信 web）/ already_claimed（幂等位图）/ inventory_full（acquire 全有或全无失败时**不置 claimed 保持可重试**），成功置位严格在 acquire true 之后，每分支回包并入完整状态叠加供 web 原子重渲；**奖励 toast 在 web 面板内渲染**（不走 AS2 任务奖励提示界面——overlay 遮挡 Flash 弹窗）。四态徽章 locked/inProgress/unlocked(领取钮+红点)/claimed(灰勾)+进度条（双端封顶 cur≤target，绝不出 NaN）。设计与施工记录：[docs/成就系统-A轮-设计-2026-06-10.md](../docs/成就系统-A轮-设计-2026-06-10.md)、[docs/成就系统-A轮-施工-2026-06-10.md](../docs/成就系统-A轮-施工-2026-06-10.md)。
  - 事件日志对话立绘（2026-06-20）已从“轻量内联文本”升级为可复用 Web 对话组件：AS2 `taskReplayDialogue` 继续回 `speaker/sub/text` 兼容字段，同时新增 `char/charBase/expression/portraitType/target?/imageurl?` 与 `heroPortrait`；Web 端由 `web/modules/dialogue/dialogue-view.js` 渲染，NPC 立绘走 `assets/dialogue-portraits/manifest.json` 的 PNG，主角走 `DressupDollRenderer` + 当前装备/脸型/发型快照。`speaker/sub/text` 仍经 `PanelTooltip.convertAS2Html` 清洗渲染；AS2 htmlText 内联 `<IMG>` 仍不开放，立绘只走结构化字段与离线 manifest。
- **dressup**（对话框主角/战斗纸娃娃预览）: `web/modules/dressup/dressup-panel.js` + `web/modules/dressup-doll-renderer.js`；开发入口为旧 Web notch “其他 → 纸娃娃测试” / `DRESSUP_TEST`。运行态可通过 `initData.gender/equipment/keyMap/appearance` 直接喂给 Canvas 2D renderer，素材来自 `assets/dressup/manifest.json` 的 PNG frame sequence + origin/matrix 元数据，不再依赖 AS2 端 `BitmapData.draw`、XMLSocket 传输或 Flash 位图采样。默认消费对话框 rig；需要战斗模板时传 `initData.rig="battle"` 与 `initData.stateLabel`（例如 `空手站立`）。renderer 会由 `stateLabel` 推断 `攻击模式`（`手枪站立` / `手枪2站立` / `双枪站立`），也可用 `initData.attackMode` 显式覆盖；manifest 中带 `conditionalVisibility.property="攻击模式"` 的素材会在非命中状态使用 `runtimeVariants.neutral`。事件日志对话回放已通过 `heroPortrait` snapshot 复用该 renderer；完整主对话框迁移时继续把主角装备快照映射到同一 initData。
- **lockbox**（开锁小游戏）: `web/modules/minigames/lockbox/` 下的正式小游戏模块；支持运行时参数、browser harness、Node QA
- **pinalign**（定位小游戏）: `web/modules/minigames/pinalign/` 下的正式小游戏模块；和 Lockbox 共用小游戏壳层与 QA 平台
- **gobang**（五子棋小游戏）: `web/modules/minigames/gobang/` 下的正式小游戏模块；Web core 负责规则裁判，AI 经 Web→C# `gomoku_eval` 调用 `GomokuTask` / Rapfi
- **team**（战队）: `web/modules/team/team-panel.js` 是唯一生产 Panel，固定标签顺序为佣兵 / 伙伴 / 战宠 / 机械；首次进入伙伴，同一 WebView 会话记忆末次标签，顶层切换会把目标子视图复位到管理列表，写操作 busy 时禁止切换和关闭。`pet-panel.js` 与 `merc-panel.js` 是可嵌入子控制器，不再独立注册 Panel；它们继续发送 `panel:"pets"` / `panel:"mercs"`，复用现有 `PetTask` / `MercTask` 与 AS2 写操作。统一 close 为纯 Web no-op，不调用有旧 Flash UI 重排副作用的 `petPanelClose`。旧命令 `PETS` / `MERCS` 仅作为隐藏兼容入口打开 `team` 的伙伴 / 佣兵标签。**壳层形态**：team-panel 是薄协调器，不渲染独立顶栏/画布（外套顶栏会把子面板压进 1024×518 触发二次缩放与黑边）——唯一一条 tab 条（`.team-tabs`）在切换时整体迁移注入激活子视图列表页 header 的 `.team-tabs-slot`（替换「战宠管理/佣兵管理」标题位；A 兵团徽标、资源条、关闭钮由子面板自有 header 承载，关闭路径经 `TeamPanelHost.requestClose` 收口）。
- 宠物域的伙伴 / 战宠 / 机械共享同一宠物池、容量与出战配额，分类权威来自 `data/merc/pets.xml` 的 `RosterType`；`pet_lib` / `adopt_list` 下发 `rosterType`，类型化 `adopt_list` 只返回非空原始分类索引。
- 佣兵子视图视觉对齐战宠战术风：独立样式 `web/css/merc_panel.css`（背景垫图 `assets/bg/official-bpk.jpg`，固定 1024×576 画布 + `--merc-scale` 整体缩放与战宠一致；panels.css 旧佣兵块已删）。卡片 2 列横版：与战宠卡同高（150px）、双倍宽度（488px），装备 11 槽收进一行；**技能不上卡**（数量不可控）——选中卡片后由底部详情栏（对齐战宠 selbar）展示技能图标流（32px 占位规格同装备，素材未采集前以技能类型首字占位）+「培养」入口；「培养」页对标战宠进阶页：性格六维条（主导维度标记）+ 技能全量列表 + 装备调配 11 槽（「更换」按钮禁用占位，为后续装备更换功能预留空间）；雇佣页同样走选中→详情栏看技能；解雇走面板内确认弹窗。**雇佣页为无缝下滑**：滚动触底自动拉下一页追加（`hire_list` 分页协议不变），底部哨兵行显示 加载中/下滑加载更多/已全部加载，并带「首屏未撑满自动续载」守卫；雇佣成功后因 AS2 池 splice 导致 poolIndex 位移，必须回第一页重拉。**等级快速定位**：可雇佣兵池在 `MercLibrary.loadFromList` 本就按等级升序（`InsertionSort.sortOn` 列 0），雇佣页顶部 chip（全部/Lv.20+/40+/60+/80+）触发 `hire_list` 带 `minLevel` → AS2 定位首个达标项所在页并覆盖页码（仅 reset 请求携带，翻页顺延不带）；页内精确定位由 Web 端锚定滚动完成；回包新增 `maxLevel`（可见池最高等级）用于禁用超出范围的 chip。佣兵摘要 `gender` 判定按字符串「男/女」（源 `mercenaries.json` 的 gender 字段；旧实现按 1/"1" 判男导致全员显示女，已修）。**禁用按钮语言**：暗色凹陷 + 虚线框（与「浅石牌=可点」彻底区分），雇佣钮禁用时文字直写原因（佣兵已满/金币不足/K点不足）。`mercSnapshot` / `mercHireList` 佣兵摘要新增 `skills`（name/level/type/trait/cooldown/cost/unlock）与 `personality`（勇气/技术/经验/反应/智力/谋略六维有序数组）——由 `MercPanelService` 按 `单位函数_fs_aka_玩家模板迁移.as` 的确定性算法（`初始化可用技能` LCG / `生成随机人格` aiSeed）重算：命中 `_root.技能缓存` 时直接采用游戏内结果，未命中时本地重算且**不回写缓存**（仅展示，不构成战斗权威）；旧 asLoader.swf 下两字段缺失，Web 端兜底显示「技能/性格情报暂不可用」。
- **佣兵纸娃娃预览（2026-06-18）**：`mercSnapshot` / `mercHireList` 佣兵摘要下发 `face` / `hair`（`MercLibrary` 已解析 skinKey），Web 端用 `face/hair + equips + assets/dressup/manifest.json` 重建卡片快照和培养页造型预览；若旧链路或开发夹具下发原始编号，面板会先用 manifest 的 `appearance.faceById/hairById` 归一化。卡片/底栏使用一次性 data URL 缓存，且只绘制 `脸型/发型/面具` 头像 holder；培养页只保留一个 live canvas，造型预览只绘制身体外观相关 holder 并与性格特质左右分栏，避免武器范围裁坏头像或压缩全身预览；manifest item 的 `helmet` 控制头盔压发。旧 `asLoader.swf` 缺 `face/hair` 时降级为性别默认脸型与空发型。
- **佣兵阵亡 / 复活币**：佣兵与战宠机制不同——不耗体力，但战斗阵亡后 `佣兵是否出战信息[i] = -1`（死亡检测写入），必须消耗 1 枚「复活币」（`data/items/收集品_材料.xml` 材料）才能再出战。snapshot 佣兵摘要带 `dead`，快照级带 `reviveCoins`（`ItemUtil.getTotal`）；新增 Web cmd `revive` → C# `MercTask` → AS2 `mercRevive`（校验 -1 态 → `ItemUtil.singleSubmit("复活币",1)` → 置 0=休息位，标脏），`deploy` 对 -1 态回 `merc_dead` 硬拒。Web 端：阵亡卡红框/去彩/「阵亡」徽章，出战位变「复活」（复活币不足禁用），工具栏带复活币计数；培养页 header 同步三态（出战/休息/复活）。
- **战宠战斗属性成长**：`petSnapshot` 每宠新增 `combat`（hp/attack/defense/speed 各为 `{start,cur,max}` 三点采样 + startLevel/maxLevel/difficulty）——`PetPanelService` 与出战实体初始化管线同构：基线按 `_root.敌人属性表[兵种]`（源 `data/enemy_properties` XML）线性插值（生命/攻击 × 当前 `难度等级`），再与 `敌人函数.宠物属性初始化` 同构地在**纯对象 sim** 上重放已达成进阶方案的 `单位进阶执行`（这些函数只读 `this.宠物属性`、只写 this 数值字段，无 MC 依赖；写入只落 sim，不回写真实宠物属性）。战宠培养页「战斗属性」区块渲染成长条：起点 Lv.1 → 当前（填充进度）→ 满级（`_root.等级限制`），已计入进阶加成；兵种缺属性表或旧 SWF 时整块隐藏。
- **arena**（竞技场 DEATH MATCH）: `web/modules/arena-panel.js`；`Panels.register('arena')`，8 张角斗场卡 + 详情/掷骰/进场，`ArenaTask` 双层 callId；可经地图/选关二级动作以 `returnToPanel` 重定向进入，close 不通知 AS2
- **jukebox**（BGM 点歌台）: `web/modules/jukebox/jukebox-panel.js` 注册 `Panels.register('jukebox')`，由 `RightContextWidget` 的 jukebox titlebar 展开按钮 → `JUKEBOX_EXPAND` → `LauncherCommandRouter.OpenPanel("jukebox")` 触发；与 kshop/help 等通用 panel 同走完整 backdrop / EX_STYLE / HUD-suspend 序列。沉浸全屏化（2026-06-12）后 PanelLayoutCatalog 对 jukebox 返回全 anchor（不再走 Centered 880×620 子矩形）；`jukebox-panel.js` 改固定 1024×576(16:9) 画布外套共享 `.panel-scale-shell` + `PanelScale.attach` 整体等比缩放铺满全 anchor（双栏控制台：左 Now-Playing 波形/进度/设置，右 曲库 专辑/曲目）。`#panel-content` inset:0、backdrop 兜底深底色（panel 铺满后不可见）。曲库 / UiData 状态在 onOpen 时通过 `cmd:'requestCatalog'` + `UiData.get` seed 当前值，避免晚注册错过历史推送。close 路径收敛：× 按钮 / ESC / backdrop click 三入口共用 `closeLocally`（先 `Panels.close()` 让 `_active` 复位再 `Bridge.send panel close`）——避免 ESC/backdrop 单独走 onRequestClose 时 `_active` 滞留导致下次 open 早 return

#### Jukebox panel harness

浏览器 harness：`launcher/web/modules/jukebox/dev/harness.html`（手动调 viewport / 单 case）。
无头运行：`node tools/run-jukebox-harness.js --browser edge [--viewport 1366x768] [--case <id>] [--headed]`。

覆盖项：面板开闭生命周期、seed 状态渲染、曲库/专辑下拉渲染、当前曲目高亮、点击曲目切歌、暂停/继续/停止、音量滑条、覆盖关卡BGM / 真随机 / 播放模式切换、帮助弹窗、设置区无滚动条、专辑下拉滚动条风格统一。

#### Jukebox panel 手测

`useNativeHud=true` 启动游戏，进到游戏就绪后逐项验证：

1. **Titlebar 入口**：`RightContextWidget` 右侧 jukebox titlebar 可见、mini wave 流动、当前曲名显示；点 expand → panel 出现
2. **panel 全屏铺满**：panel 铺满全 anchor 16:9（固定 1024×576 画布由 `.panel-scale-shell` 整体等比缩放，窄窗口同比缩小不重排）——1024×576 anchor 下 1:1、1920×1080 anchor 下整体约 1.875×；panel 覆盖全幅无可见 backdrop dim；Spy++ 验证 WebOverlay hwnd bounds **就是全 anchor**、EX_STYLE 既无 `WS_EX_LAYERED` 也无 `WS_EX_TRANSPARENT`
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
- `panels.js`: 面板注册/生命周期管理 (register/registerLazy/open/close/force_close)
- `panels-lazy-registry.js` + `lazy-loader.js`: 面板懒注册表（id → deps[]）+ 按需 `<script>` 注入，首次 `Panels.open(id)` 才加载对应模块（kshop/help/jukebox/dressup/map/stage-select/intelligence/arena/team/lockbox/pinalign/gobang/tasks/cutscene-test）
- `tooltip.js`: hover 跟随 + anchored 锚定两种模式，AS2 HTML 转换；商城和情报 runtime tooltip 共用
- `asset-timeline.js`: 图标与纸娃娃共享的烘焙时间线选择器，统一解释 `timelineFrames[]` / `durationFrames` / nested layer 独立周期
- `icons.js`: 物品图标 manifest 加载 + 名称→URL / frame list 解析，情报详情面板也复用该入口
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

**状态机**：`useNativeHud=true` 时 panel 打开状态以 `PanelHostController.ActivePanelName` 为主；`useNativeHud=false` 仍保留 WebOverlayForm `_activePanel` fallback（`null` → `"kshop" / "help" / "dressup" / "map" / "stage-select" / "intelligence" / "arena" / "team" / "lockbox" / "pinalign" / "gobang" / ...` → `null`）。当前只有 `kshop` 会在断连或强制关闭路径里设置 `_pauseNeedsRestore`；其余纯 Web / dev panel 只做面板生命周期管理，不触发 Flash 暂停恢复。

**热重载恢复**：`_uiDataSnapshot` 按 KV key 维护最新值快照，WebView2 热重载后 `FlushUiDataBuffer` 先回放完整快照，确保 game-ready 等关键状态不丢失。

**维护约束**：凡是小游戏、地图 panel、stage-select panel、intelligence panel、dressup panel、arena / team panel、Native HUD/PanelHost 的目录迁移、宿主协议变更、QA 入口变化，必须同步更新本 README 的目录树、测试入口和本节协议说明；AS2 UI → Web Panel 迁移细则同步维护 [../agentsDoc/as2-web-panel-migration.md](../agentsDoc/as2-web-panel-migration.md)，模块内细节留在各自模块 README / 设计文档。
