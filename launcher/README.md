# CF7:ME Guardian Launcher

C# WinForms 守护进程，承担游戏启动全链：WebView2 / Steam / Flash trust 三道启动门槛 → Bootstrap UI 槽位管理 → GameLaunchFlow 状态机 → Flash Player SA 嵌入 + V8 脚本总线 + HTTP / XMLSocket 通信 + 启动前存档决议下发。

> **新接手请先读**：[启动时序图](#架构概览) → [Bootstrap UI 与槽位管理](#bootstrap-ui-与槽位管理) → [存档权威迁移 (Protocol 2)](#存档权威迁移-protocol-2)。后半段（音频 / 性能调度 / UI 迁移 / 面板系统）大致仍能按原样阅读。

## 技术栈

| 项目 | 版本/说明 |
|------|-----------|
| 运行时 | .NET Framework 4.6.2, x64 |
| 语言 | C# 5 |
| UI | WinForms (WinExe) + WebView2（Bootstrap 引导窗 + 游戏内 overlay） |
| 构建 | MSBuild 4.0 + NuGet (packages.config) + MSVC (miniaudio native DLL) + Rust/Cargo (sol_parser cdylib) + Node.js/npm (TypeScript 编译 V8 脚本) |
| 音频 | miniaudio (Unlicense, 单头文件 C 库 → native DLL, WASAPI) |
| 存档解析 | Rust `sol_parser.dll`（flash-lso git pin `4b049ff3`），AMF0 → JSON |
| JS 引擎 | ClearScript 7.4.5 (Chromium V8, 替代 Node.js vm2) |
| Web 覆盖层 | WebView2 1.0.3856.49 (Evergreen Runtime, 幽灵输入解耦架构) |
| JSON | Newtonsoft.Json 13.0.3 |
| GPU (实验, 当前休眠) | SharpDX 4.2.0 (D3D11, 管线待完善，`gpuSharpening` 配置当前无消费者) |

## 架构概览

### 启动时序（入口 → Ready）

```
Program.Run(args)
   │
   ├─ [门槛 1] WebView2 Runtime 预检
   │   └─ CoreWebView2Environment.GetAvailableBrowserVersionString()
   │   └─ 失败 → MessageBox + return 1   (fail-closed)
   │
   ├─ [门槛 2] SteamOwnershipCheck.Check(projectRoot)
   │   └─ Steam 进程 + SteamAPI AppID → 未正版则拒启 (reason: steam_not_running / not_owned / dll_missing / ...)
   │
   ├─ [门槛 3] FlashTrustManager.EnsureTrust(projectRoot)
   │   └─ 写 #Security/FlashPlayerTrust/<swfName>.cfg (退出前 RevokeTrust)
   │
   ├─ AudioEngine.Init + MusicCatalog 扫描
   ├─ PortAllocator → XmlSocketServer.Start + HttpApiServer.Start
   ├─ TaskRegistry.RegisterAll(router, ...)   ← 注册所有 JSON task handler
   ├─ hotkey_guard.exe 子进程拉起 (可选, 不存在则跳过)
   │
   ├─ WindowManager + ProcessManager 构建 (不启动 Flash)
   │
   ├─ BootstrapForm (WebView2) 显示：launcher/web/bootstrap.html
   │   └─ 槽位列表 UI 从这里发消息：list / start_game / retry / load / save / ...
   │
   ├─ GameLaunchFlow 状态机接管后续：
   │       Idle
   │        │  ← BootstrapMessageHandler 收到 start_game(slot)
   │        ▼
   │   [锁外] SolResolver.Resolve(slot, swfPath)
   │        │     Rust sol_parser.dll → JObject
   │        │     ├─ Snapshot  → soData[test] 合法 v3.0 / v2.7 迁成 3.0
   │        │     ├─ Empty     → SOL 缺失且 shadow 无
   │        │     ├─ Deleted   → tombstone 短路
   │        │     ├─ NeedsMigration / DeferToFlash → Rust 决议失败转 AS2 处理
   │        │     └─ Corrupt   → 结构异常
   │        ▼
   │   Spawning → WaitingConnect → WaitingHandshake
   │        │                           │
   │        │                           └─ bootstrap_handshake 响应附带
   │        │                              protocol=2 + saveDecision + snapshot
   │        │                              + snapshotSource + corruptDetail
   │        ▼
   │   Embedding (Win32 SetParent Flash → _flashPanel)
   │        │
   │        ▼
   │   WaitingGameReady → bootstrap_ready 到达
   │        │
   │        ▼
   │   Ready → readyWiring (toast/web/inputShield/hnOverlay.SetReady, 托盘可见)
   │           BootstrapForm.Hide (不 Close)
   │           GuardianForm.Show
   │
   └─ 失败分支：活跃启动态出错 → Error；BootstrapForm 仍显（未 Hide），
                  唯一能回 Idle 的 cmd 是 retry（reset/start_game/rebuild 在非 Idle 态会被拒）
                  Ready 之后失败不走这支 —— 详见 "Bootstrap UI → 与运行态的关系"
```

### 运行态窗口栈（Ready 之后）

```
┌─────────────────────────────────────────────────┐
│  GuardianForm (WinForms, 运行态主壳)             │
│  ┌──────────────────────────────────────┐       │
│  │ _flashPanel  (Panel, Dock=Fill)      │       │
│  │   └─ Flash Player SA (SetParent 嵌入) │       │
│  ├──────────────────────────────────────┤       │
│  │ Toolbar (Dock=Top)  │ LogBar (Dock=Bot)│     │
│  └──────────────────────────────────────┘       │
│  TrayIcon                                       │
└───────┬──────────────────────────┬──────────────┘
        │                          │
   ┌────┴────┐               ┌─────┴──────┐
   │XMLSocket│               │  HTTP API  │
   │TCP :port│               │  :port     │
   │\0-delim │               │  REST/JSON │
   └────┬────┘               └─────┬──────┘
        │                          │
        ├─ 入站快车道 (AS2 → C#, 前缀协议) ────────┐
        │  'F' → FrameTask.HandleRaw(cam,hn,fps)   │
        │  'R' → FrameTask.HandleReset()           │
        │  'S' → AudioTask.HandleSfxFastLane()     │
        │  'B' → Bench echo（AS2 冒烟测试，回 K 前缀）│
        │  'N' → INotchSink.AddNotice(通知)        │
        │  'W' → INotchSink.SetStatusItem(波次)    │
        │  'U' → WebView2 UiData 透传              │
        │  'D' → FrameTask.LoadInputModule(DFA)    │
        │  (绕过 JSON 解析，零 GC 分配)             │
        ├──────────────────────────────────────────┤
        ├─ 出站快车道 (C# → AS2) ──────────────────┤
        │  'P' → AS2 applyFromLauncher(tier,softU) │
        │  (PerfDecisionEngine 决策推送)            │
        ├──────────────────────────────────────────┘
        │
   ┌────┴──────────────────────────┴──┐
   │    MessageRouter (JSON 路由)     │
   │  Sync:                           │
   │   toast / audio / icon_bake      │
   │   frame / hn_reset (JSON 后备)   │
   │   bootstrap_handshake / _ready   │
   │   bench_sync / bench_push (*)    │
   │  Async:                          │
   │   gomoku_eval / data_query       │
   │   shop_response / archive        │
   │   bench_async (*)                │
   │  (*) benchTask != null 时才注册   │
   └───────────────┬──────────────────┘
                   │
   ┌───────────────┴──────────────────┐
   │  AudioEngine (C# P/Invoke)       │
   │  ┌────────────────────────────┐  │
   │  │  miniaudio.dll (native C)  │  │
   │  │  WASAPI shared mode        │  │
   │  │  BGM: dual-instance xfade  │  │
   │  │  SFX: preload + 90ms dedup │  │
   │  └────────────────────────────┘  │
   │  sol_parser.dll (Rust cdylib)    │
   │  AMF0 → JSON, 0-based refs       │
   └──────────────────────────────────┘

   热键四层防御：
   ① SetMenu(NULL)                   移除 Flash 原生菜单加速器
   ② hotkey_guard.exe                独立子进程，WH_KEYBOARD_LL，前台感知
   ③ KeyboardHook (进程内低级钩子)    ESC 路由 + Ctrl+F/Q 兜底
   ④ RegisterHotKey (fallback)       上一步安装失败时退化为系统热键

   ┌─────────────────────────────────────────┐
   │  幽灵输入解耦 (Ghost Input Decoupled)    │
   │                                         │
   │  InputShieldForm                        │
   │  (GDI+ α=1 命中区拦截 → CDP 注入)       │
   │         ↓ CDP Input.dispatchMouseEvent  │
   │  WebOverlayForm                         │
   │  (WS_EX_TRANSPARENT, WebView2 渲染)     │
   │         ↓ 穿透                          │
   │  Flash HWND (WS_CHILD)                  │
   └─────────────────────────────────────────┘
```

## 延迟基线（2026-04）

基于 Flash CS6 `TestLoader` 与 `CRAZYFLASHER7MercenaryEmpire.exe --bus-only` 的多轮实测，当前可先把 Guardian Launcher 的延迟结论理解为“启动建连慢，稳定态传输快，长尾主要在 Flash/业务侧”。这里保留概要，完整样本、脚本和排查过程见 [`../docs/protocol-latency-baseline.md`](../docs/protocol-latency-baseline.md)。

- **启动建连**：`ServerManager` 从读取 `launcher_ports.json` 到 XMLSocket 连通，当前基线约 `2.1s - 2.4s`；主耗时在 XMLSocket 建连/策略握手，不在 HTTP 探测。
- **Launcher 自身传输**：`raw_b_k`、`frame_ui_k`、`json_sync/json_async/json_push_cmd` 的 C# 处理段实测为微秒级，说明 launcher 不是主要延迟源。
- **稳定态快车道**：`XMLSocket` fast-lane、`FrameBroadcaster.send()`、`cmd` 回推在即时打点下通常为低毫秒；之前看起来接近 `1 帧` 的结果，主要来自 Flash 侧回调时机与旧版采样方法。
- **HTTP / LoadVars**：`/testConnection`、`/getSocketPort`、`/logBatch` 在 AS2 侧仍会表现出接近帧级的回调抖动；这是 AVM1/`LoadVars` 的特点，不代表 launcher 的 HTTP 处理本身变慢。
- **业务重路径**：`archive_load`、`merc_bundle`、`npc_dialogue` 的长尾更多由数据加载、缓存填充和序列化决定，不是总线 transport 本身。

复测入口：

- [`../scripts/protocol_latency_cycle.ps1`](../scripts/protocol_latency_cycle.ps1)：单轮基线
- [`../scripts/protocol_latency_sweep.ps1`](../scripts/protocol_latency_sweep.ps1)：多轮抖动/尾延迟统计

## 目录结构

按实际 `ls` 重生成（2026-04-18）。只列追踪目录；`bin/` / `packages/` / `target/` / `node_modules/` 等构建产物和缓存均由 .gitignore 管理。

```
launcher/
├── CRAZYFLASHER7MercenaryEmpire.csproj   C# 项目文件
├── packages.config                        NuGet 包清单
├── build.ps1                              总构建脚本 (10 步, 见下文)
├── app.ico                                应用图标
│
├── src/
│   ├── Program.cs                         入口：WebView2/Steam/Trust 三道门槛 → 总线 → BootstrapForm → GameLaunchFlow
│   │
│   ├── Config/
│   │   ├── AppConfig.cs                   config.toml 解析 (4 key: flashPlayerPath/swfPath/gpuSharpening/sharpness)
│   │   ├── SteamOwnershipCheck.cs         Steam 进程 + SteamAPI AppID 正版校验 (fail-closed)
│   │   └── FlashTrustManager.cs           写入/撤销 FlashPlayerTrust .cfg，让 SWF 可联网
│   │
│   ├── Guardian/
│   │   ├── GuardianForm.cs                运行态主壳（Toolbar/Log/Tray，Ready 后显形）
│   │   ├── BootstrapForm.cs               启动引导窗（WebView2，承载 bootstrap.html 槽位 UI）
│   │   ├── BootstrapMessageHandler.cs     Bootstrap UI 消息分发（详见 "Bootstrap UI 与槽位管理" 的 cmd 表）
│   │   ├── GameLaunchFlow.cs              启动状态机：Idle→Spawning→…→Ready/Error/Resetting，存档决议入口
│   │   ├── GuardianContext.cs             ApplicationContext 外壳：MainForm=BootstrapForm，BootstrapForm 关闭时路由到 GuardianForm.ForceExit
│   │   ├── FlashHtmlParser.cs             AS2 HTML 子集转纯文本/白名单结构
│   │   ├── WindowManager.cs               Win32 SetParent 嵌入 + 500ms 脱离看门狗
│   │   ├── ProcessManager.cs              Flash SA 进程生命周期 + 僵尸兜底
│   │   ├── LogManager.cs                  线程安全日志 → TextBox + 文件通道 (logs/launcher.log)
│   │   ├── OverlayBase.cs                 GDI+ Layered Window 覆盖层基类
│   │   ├── ToastOverlay.cs                GDI+ toast 消息 (WS_EX_TRANSPARENT)
│   │   ├── NotchOverlay.cs                GDI+ 刘海栏 (选择性穿透, 状态机)
│   │   ├── HitNumberOverlay.cs            GDI+ 伤害数字
│   │   ├── WebOverlayForm.cs              WebView2 视觉层 (WS_EX_TRANSPARENT)
│   │   ├── InputShieldForm.cs             幽灵输入层 (GDI+ α 命中 + CDP 注入)
│   │   ├── IToastSink.cs / INotchSink.cs  Toast / Notch 抽象接口
│   │   ├── FlashCoordinateMapper.cs       Flash 舞台坐标 ↔ 屏幕坐标
│   │   ├── FpsRingBuffer.cs               FPS 环形缓冲 + 场景重置
│   │   ├── PerfDecisionEngine.cs          性能决策引擎 (滑动窗口 + 迟滞，替代 AS2 Kalman/PID)
│   │   ├── HotkeyGuard.cs                 独立进程源码 (csc 单独编译为 hotkey_guard.exe)
│   │   └── KeyboardHook.cs                进程内 WH_KEYBOARD_LL (ESC 路由 + Ctrl+F 兜底；失败 fallback RegisterHotKey)
│   │
│   ├── Bus/
│   │   ├── XmlSocketServer.cs             TCP 服务器（8 入站前缀 + 1 出站前缀 + JSON 双通道）
│   │   ├── HttpApiServer.cs               HTTP REST (10 端点, 详见 HTTP API 节)
│   │   ├── MessageRouter.cs               JSON task 路由：RegisterSync / RegisterAsync
│   │   ├── TaskRegistry.cs                Task 注册表 — single source of truth
│   │   ├── PortAllocator.cs               种子 "1192433993" 确定性端口分配
│   │   ├── FlashPolicyHandler.cs          Flash 跨域策略 (crossdomain.xml)
│   │   └── BenchTrace.cs                  性能基准追踪 (条件编译)
│   │
│   ├── Save/                              【启动前存档决议链 — Protocol 2】
│   │   ├── SolResolver.cs                 决议矩阵入口：tombstone → shadow → SOL → 版本分流
│   │   ├── SolParserNative.cs             sol_parser.dll P/Invoke 封装
│   │   ├── SolFileLocator.cs              SOL 路径定位（多 hash 子目录 + 3 档 variant fallback）
│   │   ├── SaveMigrator.cs                2.7→3.0 迁移 + MergeTopLevelKeys + ValidateResolvedSnapshot
│   │   └── SaveResolutionContext.cs       DI 聚合 (resolver + archive + swfPath)
│   │
│   ├── Audio/
│   │   ├── AudioEngine.cs                 miniaudio P/Invoke (play/stop/seek/peak)
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
│   │   ├── GomokuTask.cs                  五子棋 AI (外部 rapfi 引擎)
│   │   ├── DataQueryTask.cs               NPC/佣兵数据查询 (Data/ 支撑)
│   │   ├── ToastTask.cs                   UI toast 通知 (fire-and-forget)
│   │   ├── ShopTask.cs                    K 点商城双层 callId 桥接 (10s 超时)
│   │   ├── ArchiveTask.cs                 存档 shadow 备份 + list/delete/reset/load_raw（辅助链）
│   │   ├── IconBakeTask.cs                物品图标批量烘焙（begin/chunk/end 协议）
│   │   └── BenchTask.cs                   性能基准 task (条件编译)
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
│   ├── miniaudio.h                        miniaudio 单头文件库 (Unlicense)
│   ├── miniaudio_bridge.c                 C 导出层 (BGM crossfade/seek/pause/looping, SFX preload, peak)
│   ├── build.bat                          MSVC vcvars64 探测 + cl.exe 编译
│   └── sol_parser/                        【Rust cdylib：AMF0 → JSON】
│       ├── Cargo.toml                     flash-lso git pin 4b049ff3 + serde_json
│       ├── Cargo.lock                     ✅ 已入库（2026-04-18 起）：锁定依赖版本集，消除浮动解析
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
├── web/                                   【WebView2 前端资源（Bootstrap UI + Overlay UI）】
│   ├── bootstrap.html                     启动引导 UI（槽位 CRUD + 启动按钮）
│   ├── overlay.html                       运行态 DOM (Toast/Notch/工具条/Panel/Tooltip)
│   ├── css/
│   │   ├── bootstrap.css                  Bootstrap UI 样式
│   │   ├── overlay.css                    Notch/Toast/Jukebox 等样式 + 动效
│   │   └── panels.css                     面板系统样式 (Cyberpunk 2077 风格)
│   ├── lib/
│   │   └── marked.min.js                  Markdown→HTML 渲染器 (MIT)
│   ├── icons/                             物品图标资源
│   │   ├── manifest.json
│   │   └── *.png
│   ├── help/                              游戏帮助 Markdown
│   │   ├── controls.md / worldview.md / easter-eggs.md
│   ├── data/
│   │   └── lockbox-variants.json          开锁小游戏数据
│   └── modules/
│       ├── bridge.js                      C# ↔ JS 消息桥
│       ├── uidata.js                      帧同步 UI 状态分发 (KV 格式)
│       ├── toast.js                       Toast 消息 (Flash HTML 白名单)
│       ├── sparkline.js                   FPS 折线图 (DPR 感知)
│       ├── notch.js                       Notch UI (FPS/clock/工具条/通知)
│       ├── currency.js                    经济面板动画
│       ├── combo.js                       搓招连击飞出动效
│       ├── jukebox.js                     BGM 点歌器 (波形/seek/专辑)
│       ├── panels.js                      通用面板生命周期 (register/open/close/ESC)
│       ├── tooltip.js                     Tooltip (hover/anchored)
│       ├── icons.js                       图标 manifest 加载与解析
│       ├── kshop.js                       K 点商城面板 (ShopTask 双层 callId)
│       ├── help.js / help-panel.js        帮助系统（顶层入口 + 面板骨架）
│       ├── archive-editor.js              存档编辑器（Bootstrap UI 内联）
│       ├── archive-schema.js              存档 schema 描述/校验
│       ├── diagnostic-log.js              Bootstrap UI 日志查看器
│       ├── lockbox-core.js / lockbox-panel.js / lockbox-generator.js /
│       │   lockbox-solver.js / lockbox-audio.js
│       └── minigames/
│           └── pinalign/                  定位小游戏（core/adapter/app/dev/reference + audio/panel/css）
│
└── tools/
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

### 一键构建

```powershell
cd launcher
powershell -File build.ps1
```

### build.ps1 实际 10 步流程

| 步骤 | 动作 |
|------|------|
| 1    | `nuget restore` — 恢复 NuGet 包 (ClearScript / Newtonsoft.Json / SharpDX / WebView2) |
| 1.5  | TypeScript 编译 — `cd scripts`，若 `node_modules/` 缺失则跑 `npm install --ignore-scripts`，再 `npx tsc --project tsconfig.json` → `scripts/dist/*.js` 供 V8Runtime 加载 |
| 1.8  | `native/build.bat` — 编 miniaudio_bridge.c → `bin/Release/miniaudio.dll`（自动 vcvars64） |
| 1.9  | `native/sol_parser/build.bat` — `cargo build --release` → `bin/Release/sol_parser.dll`（硬依赖，缺失直接 exit 1） |
| 2    | `msbuild CRAZYFLASHER7MercenaryEmpire.csproj /p:Configuration=Release` — 编 C# |
| 3    | 复制 managed 产物（exe + DLLs + miniaudio.dll + sol_parser.dll）到项目根 |
| 3.5  | 硬断言 `sol_parser.dll` 已落盘到项目根（防止"编过但运行时 DllNotFoundException"） |
| 4    | 复制 V8 原生 DLL（ClearScriptV8.win-x64.dll）到项目根 |
| 5    | 复制 WebView2 原生 loader（WebView2Loader.dll）到项目根 |
| 6    | 校验 web 资源目录（overlay.html / bootstrap.html / modules / icons）完整 |

### 产物（部署到项目根目录）

| 文件 | 说明 |
|------|------|
| `CRAZYFLASHER7MercenaryEmpire.exe` | Guardian 主程序 |
| `miniaudio.dll` | 原生音频引擎 (WASAPI) |
| `sol_parser.dll` | Rust AMF0 → JSON 解析器（Protocol 2 存档决议用） |
| `ClearScript.Core.dll` | V8 引擎核心 |
| `ClearScript.V8.dll` | V8 managed 封装 |
| `ClearScript.V8.ICUData.dll` | V8 国际化数据 (~10MB) |
| `ClearScriptV8.win-x64.dll` | V8 原生引擎 (~22MB) |
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

### VS Code 任务配置 (可选)

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

## 运行时配置与启动门槛

### 启动门槛（`Program.Run` 入口三道 fail-closed 检查）

1. **WebView2 Runtime 预检**（`--bus-only` 例外跳过）
   - 调用 `CoreWebView2Environment.GetAvailableBrowserVersionString()`
   - 失败 → MessageBox 指向 Evergreen Bootstrapper 下载页 → `return 1`
   - 命令行 `--force-webview-fail` 可强制触发本路径（测试用）

2. **Steam 正版校验** (`SteamOwnershipCheck.Check`)
   - 依次检查 Steam 进程、SteamAPI DLL 加载、AppID 所有权
   - `reason` 取值 `steam_not_running` / `not_owned` / `dll_missing` / `dll_load_failed` / 其他
   - 失败 → 对应文案 MessageBox → `return 1`，并**拒绝写入 FlashPlayerTrust**

3. **Flash Trust 配置** (`FlashTrustManager.EnsureTrust`)
   - 在 `%APPDATA%\Macromedia\Flash Player\#Security\FlashPlayerTrust\` 写入 `.cfg` 让 SWF 可联网
   - `trustAcquired == false` 只打 WARNING，不拒启（降级运行，SWF 可能连不上）
   - 进程退出前 try/finally 里调 `RevokeTrust` 清理

Steam + Trust 两步组成反盗版链的 launcher 侧兜底，详见 `memory/anti-piracy-strategy.md`（项目知识库）。

### config.toml（项目根目录）

只有 4 个 key 会被识别，缺失即落代码默认：

```toml
flashPlayerPath = "Adobe Flash Player 20.exe"
swfPath = "CRAZYFLASHER7MercenaryEmpire.swf"

# GPU CAS 锐化（实验性）— 当前代码中该字段无消费者，pipeline 待完善。
# 保留为未来 feature flag；写什么都不影响当前运行行为。
gpuSharpening = false
sharpness = 0.5
```

代码默认（[AppConfig.cs:23-26](src/Config/AppConfig.cs#L23)）：`GpuSharpeningEnabled = true`, `Sharpness = 0.5`。示例显式写 `false` 是遵循正文「当前禁用」语义，等 pipeline 接上以后再统一默认。

### 命令行参数

| 参数 | 作用 |
|------|------|
| `--bus-only` | 只跳过入口的 WebView2 **fail-closed 预检**、Flash SA 启动、BootstrapForm / GameLaunchFlow 路径；保留 HTTP + XMLSocket + WebOverlayForm 构造（仍会调用 `GetAvailableBrowserVersionString`，环境里无 WebView2 仍会抛）。用于让 Flash CS6 testMovie / 基准工具自行连总线 |
| `--force-webview-fail` | 强制触发 WebView2 缺失分支（冒烟测试） |

## Bootstrap UI 与槽位管理

启动完成所有门槛后，Launcher **先**弹 `BootstrapForm` —— 一个承载 `launcher/web/bootstrap.html` 的 WebView2 窗口，里面跑 `archive-editor.js` / `archive-schema.js` / `diagnostic-log.js` 等模块，给玩家管理所有存档槽位。只有玩家在 Bootstrap UI 点了某个槽位的"开始游戏"，`GameLaunchFlow.StartGame(slot)` 才会拉起 Flash。

### bootstrap → C# 消息分发（`BootstrapMessageHandler.Handle`）

WebView2 通过 `chrome.webview.postMessage({ cmd, ... })` 发消息到 C#。所有 cmd（状态约束列反映代码真实语义）：

| cmd | 职责 | 状态约束 |
|-----|------|----------|
| `ready` | WebView2 就绪信号 | 任意 |
| `ping` | 连通性 echo（payload 原样回传） | 任意 |
| `list` | 列出所有槽位 → `list_resp`（含 slots 数组） | 任意 |
| `load` | 读取 slot 的 shadow JSON → `load_resp` | 任意 |
| `load_raw` | 绕过 tombstone 检查读原始 JSON（editor 用）→ `load_raw_resp` | 任意 |
| `save` | 玩家侧编辑后写回 shadow（注入 userEdit=true，强制 schema 校验 + 覆写 lastSaved） | **Idle**（`RequireIdle`） |
| `delete` | 写 tombstone → `delete_resp` | 任意 |
| `reset` | 清 launcher 副本 + tombstone（不清 SOL，下次启动可能从 SOL 回填） | **Idle**（`RequireIdle`） |
| `export` | 把 slot 导出到用户选择路径 | 任意 |
| `import_start` / `import_commit` | 两段式导入（预览 + 确认） | **Idle**（`RequireIdle`） |
| `start_game` | 拉起 Flash 进入该 slot（`GameLaunchFlow.StartGame`） | **Idle**（非 Idle 被 StartGame 静默忽略，不回错误包） |
| `rebuild` | 同 `start_game`，UI 侧语义上标记"重建存档场景" | **Idle**（同上） |
| `retry` | `GameLaunchFlow.Retry()` = 锁内快照 `_pendingSlot` → 锁外 `Reset(onIdle: StartGame(slot))`：**重置到 Idle 后立刻重拉同一 slot**，不会停在 Idle 等玩家二次点击 | **仅 Error 态有效**（其他态直接 `return`，不副作用） |
| `logs` | 读取 `logs/launcher.log` 的最近 N 行 → `logs_resp` | 任意 |
| `open_saves_dir` | 打开 `saves/` 文件夹（Explorer） | 任意 |

未识别的 cmd → `PostError(unknown_cmd)`。所有响应统一由 `PostResp` 产生 `{type:"bootstrap", cmd, ok, slot?, error?}`（注意是 `ok` 而非 `success`）。触发 `RequireIdle` 守卫的 4 个 cmd（save/reset/import_start/import_commit）在非 Idle 态返回 `{ok:false, error:"not_idle"}`。`start_game`/`rebuild` 的守卫在 `GameLaunchFlow.StartGame` 内部，发现非 Idle 直接 `return` 不回复，前端只能靠 `OnStateChanged` 推送观察到状态没前进。

### C# → bootstrap 推送

`GameLaunchFlow.OnStateChanged` 每次状态跳转都会往 BootstrapForm 推单一消息：

```json
{ "type": "bootstrap", "cmd": "state", "state": "<State>", "msg": "<free-form>" }
```

只有 `state` + `msg`，没有 `reason` 字段。前端从 `msg` 里解析（例如 `"flash_exited"`、`"game_ready_timeout"`、`"handshake_timeout"`）来决定 UI 表现。

### 与运行态的关系

**启动成功路径**：`Ready` 达到后 `_bootForm.HideForReady()`（仅 Hide，不 Close），`GuardianForm.Show()` 接管显示。整条代码库**没有**任何让 BootstrapForm 在 Ready 之后重新显形的路径。

**Ready 后退出路径**：

| 触发 | 处理 |
|------|------|
| Flash 进程正常退出 | `OnFlashExited` → `form.ForceExit()` → **整个 Launcher 一起退出** |
| socket 断连 10s + Flash 仍活 | Zombie 兜底 → `form.ForceExit()` → 同上 |

**活跃启动态（非 Ready）出错路径**：`Spawning / WaitingConnect / WaitingHandshake / Embedding / WaitingGameReady` 下 Flash 异常退出 → `TransitionToError("flash_exited")`。这种情况下 BootstrapForm 根本还没 Hide，它一直显示着，玩家可在 Error 态发 `retry` 回到 Idle 重试。

所以 **BootstrapForm 在 Ready 之后就不再参与生命周期**；玩家想"换槽位"必须退出 Launcher 重启。

## 关键设计决策

### Flash 嵌入 (SetParent)
Guardian 通过 Win32 `SetParent` 将 Flash Player SA 窗口嵌入 WinForms Panel，移除标题栏/边框/菜单栏。500ms 看门狗定时器检测全屏等操作导致的脱离并自动重新嵌入。

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
| ② | `hotkey_guard.exe`（独立进程） | `WH_KEYBOARD_LL` 前台感知，仅 Guardian/Flash 在前台时拦截 Ctrl+F(全屏) / Ctrl+Q(退出)；进程不在（未编译）时只打 log，降级到下一层 |
| ③ | `KeyboardHook`（进程内低级钩子） | ESC 面板路由 + Ctrl+F 兜底；安装失败（Windows 钩子配额用尽等）会打 `KeyboardHook failed, falling back to RegisterHotKey` |
| ④ | `RegisterHotKey`（fallback） | 上一层失败时退化为系统全局热键注册；功能弱化但至少能保住 Ctrl+F/Ctrl+Q |

### 原生音频引擎 (miniaudio)
音频播放从 Flash Sound API 完全迁移到 C# launcher 的 native DLL，Flash 侧仅发送播放指令。

**架构**：
- `miniaudio_bridge.c` → `miniaudio.dll`: 单文件 C 库，WASAPI shared mode，支持 play/stop/seek/peak
- `AudioEngine.cs`: P/Invoke 封装 (bgm_play/stop/seek/get_peak/get_cursor/get_length/is_playing)
- `AudioTask.cs`: BGM JSON handler (bgm_play/stop/vol/seek) + SFX 快车道批量解析
- `MusicCatalog.cs`: BGM 曲库管理，合并 bgm_list.xml + 文件系统自动发现 + FileSystemWatcher 热加载
- `DirectoryWatcherService.cs`: 通用文件监听服务（500ms 去抖，可复用于 mod/皮肤等场景）

**BGM 专辑系统**：`MusicCatalog` 启动时解析 `sounds/bgm_list.xml`（手工注册曲目）并扫描 `sounds/*/` 子目录发现未注册的音频文件（MP3/WAV/OGG/FLAC），按文件夹名归类为专辑。合并后的完整目录在 Flash 业务就绪后推送（`OnClientReady` 事件），热加载增量通过 `catalogUpdate` 推送。玩家只需在 `sounds/` 下新建文件夹投放音频，游戏运行中即可识别。详细说明见 `sounds/README.md`。

**BGM 优先级**：Flash 侧 `SoundEffectManager` 实现 3 级优先级状态机（stage > jukebox > scene），支持 override 模式（jukebox > stage > scene）。被高优先级抢占的 BGM 意图记录在 `_suppressedScene/_suppressedStage` 中，恢复时精确还原（含 album 模式和 loop 语义）。

**BGM**：双 `ma_sound` 实例 ping-pong crossfade。切换时旧曲淡出与新曲淡入重叠进行，基于 `ma_engine_get_time_in_milliseconds` 全局时钟调度。`stopBGM` 使用 `ma_sound_stop_with_fade_in_milliseconds`，操作两个槽位确保无残留。注意 miniaudio 的 base volume 与 fader 是相乘关系，crossfade 路径中 `ma_sound_set_volume` 必须设为 1.0（由 fader 独立控制 0→1 淡入）。Seek 使用 `ma_sound_seek_to_second()`（基于声源自身采样率换算，不依赖 engine sample rate）。

**BGM 可视化 + 点歌器**：`PeakDetector` 自定义节点（`ma_node_vtable` passthrough）插入 bgmGroup → engine endpoint 之间，实时采样 L/R peak。C# 60ms 轮询 `ma_bridge_bgm_get_peak/cursor/length/is_playing` → WebView2 `PostWebMessageAsJson` → `jukebox.js` 渲染滚动波形 + 进度条（可拖拽 seek）。点歌器面板含专辑浏览、选曲播放、设置菜单（覆盖关卡BGM / 真随机）和帮助按钮。曲目标题由 AS2 `pushUiState("bgm:title")` 经 UiData 通道推送，设置状态由 `jbo:/jbr:` 通道同步。

**SFX**：启动时扫描 `sounds/export/{武器,特效,人物}/` 目录，文件名即 linkageId，覆盖顺序武器→特效→人物（后覆盖前）。Flash 侧帧内累积，帧末由 FrameBroadcaster 合批发送 `S{id1}|{id2}|{id3}` 快车道消息。native 层 90ms 去重。

**路径编码**：所有字符串参数使用 `wchar_t*` (UTF-16)，文件操作用 `ma_sound_init_from_file_w()`，支持中文路径。

**音效资产**：由 `tools/export_sfx.py` 调用 FFDec CLI 从 SWF 批量导出并重命名为 linkageId，运行时无需 manifest 文件。

### 性能调度迁移 (PerfDecisionEngine)
原 AS2 端的完整反馈控制回路（Kalman 滤波→PID→迟滞量化→执行器，~1400 行）已迁移到 C# launcher 端。

**迁移依据**：PID 被数学证明退化为阈值生成器（Proposition 1, 97.4% 积分饱和率），迟滞量化器是实际控制权威。

**架构**：
- **C# PerfDecisionEngine** (~250 行): 滑动窗口统计(mean5/trend10) + 直接阈值 + 2/3 非对称迟滞确认 + 方差自适应
- **AS2 PerformanceScheduler** (~250 行，薄壳): 采样 + FPS 广播 + 接收 P 指令执行 + 本地后备
- **P 前缀快车道** (C#→AS2): `P{tier}|{softU_x100}\0`，零 JSON 解析
- **失焦抑制**: WindowManager.IsFlashForeground() 门控，先于 panic 判定
- **前馈 hold**: 关卡脚本 setPerformanceLevel() 可挂起远程模式 N 秒
- **断线后备**: AS2 极简阈值降级 (FPS<15→tier=1)；15 秒无样本自动触发 warmup

### 存档权威迁移 (Protocol 2)

自 2026-04-18 起，**存档权威从 AS2 迁到 Launcher**。启动期 Launcher 预先读并决议 SOL，通过 `bootstrap_handshake` 响应把 snapshot 直接下发给 Flash，彻底消除启动期 async I/O 等待。

**决议主路径**（`GameLaunchFlow.StartGame(slot)` 锁外执行）：

```
SolResolver.Resolve(slot, swfPath)
   │
   ├─ [1] ArchiveTask.IsTombstoned(slot)  → "deleted"
   │
   ├─ [2] ArchiveTask.TryLoadShadowSync   → shadow 预置（失败不阻断）
   │
   ├─ [3] SolFileLocator.FindSolFile      → 定位 SOL 文件路径
   │       遍历 %APPDATA%\...\#SharedObjects\* 多 hash 子目录
   │       三档 variant fallback：drop-drive / keep-drive / glob
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
         │        ├─ pass → Snapshot(sol)
         │        └─ fail → shadow 新鲜（lastSaved >=）则 Snapshot(json_shadow)
         │                   否则 Corrupt(v3.0_structure_invalid)
         ├─ mydata.version == "2.7"
         │    └─ Migrate_2_7_to_3_0 → Validate
         │        ├─ pass → Snapshot(sol)
         │        └─ fail → DeferToFlash
         └─ pre-2.7
              └─ shadow 严格更新（>）→ Snapshot(json_shadow)，否则 DeferToFlash
```

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

**Launcher 侧复用的数据源**（`launcher/src/Save/` 五个文件）：

| 文件 | 职责 |
|------|------|
| `SolResolver.cs` | 决议入口，上述矩阵实现 |
| `SolParserNative.cs` | sol_parser.dll P/Invoke（UTF-16 路径，UTF-8 JSON 回传） |
| `SolFileLocator.cs` | 多 hash 子目录 + 三档 variant fallback |
| `SaveMigrator.cs` | 2.7→3.0 迁移 + MergeTopLevelKeys + ValidateResolvedSnapshot |
| `SaveResolutionContext.cs` | DI 聚合（传给 GameLaunchFlow） |

### ArchiveTask shadow 辅助链

**Protocol 2 之外仍存在**的 shadow 备份链，主要用途：游戏运行中存盘的 JSON 冗余副本、Bootstrap UI 的存档 CRUD 支撑、以及 corrupt/DeferToFlash 场景的兜底参考。

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

### GPU 锐化 (实验性, 当前禁用)
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
| 任务完成提示 | notch.js 通知条完成态 (❗ 图标呼吸 + 可点击) | `td:0/1` (KV 帧同步) |
| 功能按钮界面 (装备/任务) | `#quest-row` 工具条按钮行 | `cmd` gameCommand |
| 存盘动画 | ✕ 按钮状态变化 (·· → ✓) | `sv:1/2` (KV 帧同步) |
| 安全退出界面 | `#safe-exit-panel` 面板 | `sv:1/2` + `EXIT_CONFIRM` click |
| 帮助界面 (帮助界面.swf) | Panel 系统 `help-panel.js` (Markdown tab) | Bridge → C# panel_cmd open help |
| K点商城 (商城界面 MC) | Panel 系统 `kshop.js` (商品/购物车/领取) | ShopTask 双层 callId 桥接 (Web↔Flash) |

**右上角工具条布局**：
```
┌──────────────────────┐
│ ⚙  🔧  ⏸  ?  ✕      │  ← #top-right-tools
├──────────────────────┤
│ ☰ 装备  │  ☰ 任务   │  ← #quest-row (游戏中常驻)
├──────────────────────┤
│ [❗] 任务已达成·交付  │  ← #quest-notice-bar (动态)
├──────────────────────┤
│ ♪ 点歌  未播放        │  ← #jukebox-panel
└──────────────────────┘
```

**通知条状态机**：隐藏 → (新任务/公告到达) → 播放通知 → (队列空+td:1) → 完成态常驻 → (td:0) → 隐藏。完成态图标持续呼吸脉冲 (`icon-breathe`)，可点击跳转地图交付。

### 面板系统 (Panel System)

全屏遮罩面板框架，用于承载需要独占交互的复杂 UI（商城、帮助等），取代 Flash MovieClip 弹窗。

**架构**：
```
按钮点击 (SHOP/HELP)
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
- **kshop** (K点商城): 需要 Flash 交互 (shopPanelOpen/Close 暂停控制, ShopTask 异步桥接)
- **help** (游戏帮助): 纯 Web 侧，无 Flash 交互，不暂停游戏

**通用模块**：
- `panels.js`: 面板注册/生命周期管理 (register/open/close/force_close)
- `tooltip.js`: hover 跟随 + anchored 锚定两种模式，AS2 HTML 转换
- `icons.js`: 物品图标 manifest 加载 + 名称→URL 解析

**状态机 (_activePanel)**：`null` → `"kshop"/"help"` → `null`。断连时仅对 `kshop` 设 `_pauseNeedsRestore`，help 面板不触发 Flash 暂停恢复。

**热重载恢复**：`_uiDataSnapshot` 按 KV key 维护最新值快照，WebView2 热重载后 `FlushUiDataBuffer` 先回放完整快照，确保 game-ready 等关键状态不丢失。
