# CF7:ME Guardian Launcher

C# WinForms 守护进程，承担游戏启动全链：正常模式先做 WebView2 预检，再尽早构造 `GuardianForm`，随后完成 Steam 校验、Flash trust 租约、音频与总线初始化，最后由 BootstrapPanel 的 `list → ready → prewarm → reveal` 链路切入 Flash Player SA 运行态；同时承载 V8 脚本总线、HTTP / XMLSocket 通信和启动前存档决议（Protocol 2）。

> **文档角色**：Guardian Launcher 子系统的 canonical deep doc。项目总览见 [../README.md](../README.md)，顶层任务路由见 [../AGENTS.md](../AGENTS.md)。高变动章节按各自 commit 基线维护。
> **最后核对架构与工作流**：source commit `9118eb5097ab073d26a9806138f9fabf28e3ca79` 已由 immutable tag `runtime-build-v2/20260730-workbench-character-build-v1`、request `F5992FE5AFA3B74024CACEFCA1BACD311C1A3EE7C50CF3D08145A3E49BC211BC`、本地 X509 + GitHub OIDC/Sigstore 双故障域共识完成正式 promotion。exact candidate 与无参正式入口都完成 production Equipment Tuning opener → exact workbench instance → 同实例首个权威 snapshot → supported application shutdown 的只读纵切，故 Launcher 生命周期在该明确范围内为 `standard_entry_verified`；不代表角色构筑/双栏工作台完整业务、写入、普通关闭或视觉验收。本文只维护 Launcher 的稳定入口、协议与验证规则；逐次证据见 [本轮 runtime 发布与只读 snapshot 门](../docs/evidence/workbench-character-build-runtime-readonly-release-2026-07-30.md)，通用判定见 [验证矩阵](../agentsDoc/testing-guide.md)。
> **PlayerInfo 当前边界**：F2 `891d9b08dbd826d8b2624c6bdc59082b3db57ecd` / r2 自身仍是历史 non-deployment train；其实现字节被较新的 `9118eb…` release 包含并进入 formal runtime。B0 仍为 `b0_accepted`，oracle 仍为 `oracle_frozen_for_b0`；本轮 formal smoke 没有启用 PlayerInfo fixture、观察真实 `pi_*` 或完成 PlayerInfo-specific standard-entry E2E，不能从总体 runtime 的 `standard_entry_verified` 外推 PlayerInfo 专项验收。历史 identity、可见验收与边界继续见 [runtime v2 深层文档](../docs/runtime-build-reproducibility.md)、[PlayerInfo 工具证据](../tools/player-info-hud/README.md)和 [B0 专项 ADR](../docs/玩家信息界面-NativeHud-SVG真源与程序化动效-B0-ADR与分片施工计划-2026-07-28.md)。
> **冻结专项证据**：地图资源箱 Web-only source `2c87d31fecbbfb50c072ec199da0134755974402` 已由 immutable tag `runtime-build-v2/20260722-map-loot-web-only-v1`、request `F1F9493CF08DD88F26E1493FCACE306AC160866EA21440FC62698E5965A1AF04` 与 promotion commit `40119635ae5527225a425eb7f69af54f85115066` 完成正式发布；隔离 candidate attempt `82b9e602526c4e93a02d26aac0a44f20` 达到 `e2e_verified`，标准入口 attempt `9e88d51425a54b8b84dff0aa21702eac` 达到 `standard_entry_verified`。该结论只覆盖冻结的 build identity `7C72B92B0C1CF57EB9BC0D3C1024D31657EE52E6B13D7BBF9FDB94FD5A6186DB`、payload closure `7E5EDCD4FEA80E1269C0B8BCC325D1FE0994EE8C7321F0F71CB9AF4B369C4A44` 与 Core SHA-256 `3EB1D3910B764F0B7F9ACA1FA989A4D8732F75479E64325223F270502256A5DF`，不得外推到后续源码。
> **当前冻结发布证据**：source `9118eb5097ab073d26a9806138f9fabf28e3ca79` 的正式 runtime 绑定 Core SHA-256 `9DE1C5249EA5827AB8CE7C19CAE0CAE8724809BE2BC7DE4F600AD2F7AB78F336`、build identity `EB60E241929B5F88110C4EAE218DFD98569AE657F2B765179DBF644F0EEE0255` 与 payload closure `889FC7A800CFE738EAA99992CD6C5689AA65ECFEF3F406A617B3A1A344F4520B`。无参标准入口 attempt `9539e5f3f6d44b7daf487d8985465972` 取得 fresh handoff、真实 title receipt、单次 enter 与同实例首个权威调制 snapshot 后 supported shutdown；未发送 preview/commit，也未验证普通 panel close、人工视觉、存档或重启回读。
> **当前源码边界**：审阅/F0 锚点 `c96f4c3d750561022b706c72a4d53050431e627d` 之后的 A2b、A3、B1–B7、C1–C3、E、G1–G5、H1–H6、双宿主浏览器策略与 Native 右侧条件槽现已包含在 `9118eb…` 冻结 tree 与正式 runtime；自动门不等于所有功能都完成该 release identity 下的实机验收。本轮实机只覆盖上述 Equipment Tuning opener/snapshot 窄纵切，Character Build、Materials / Intelligence 返回、业务写入/reconcile、普通关闭、视觉与持久化仍不得标成已由本次 standard-entry smoke 证明。
> **新接手阅读顺序**：本节 → [架构概览](#架构概览)（启动时序 + 运行态面板栈）→ [Bootstrap 前端与协议](#bootstrap-前端与协议)（cmd 表 + reveal gate + config_set）→ [启动期存档决议 (Protocol 2)](#启动期存档决议protocol-2)。其余章节继续展开音频 / 性能调度 / GPU / UI 迁移 / 面板系统等运行时细节。
> **路径约定**：正文与代码块中以裸 `tools/` 开头的脚本路径，除 `launcher/tools/` 下三个小游戏工具（`lockbox-bake.js` / `run-minigame-qa.js` / `validate-minigame-final-state.js`）外，**默认相对仓库根**（`launcher/` 的上一级，从仓库根执行）；跨出 launcher 的 markdown 链接统一用 `../`。

## 技术栈

| 项目 | 版本/说明 |
|------|-----------|
| 运行时 | **.NET 10 (`net10.0-windows`)**, x64, **FDD (framework-dependent)** + 用户面 native C++ bootstrap |
| 语言 | C# (`LangVersion=latest`，对齐 .NET 10) for Core；C++ (Win32-only，no STL) for bootstrap |
| SDK pin | [`global.json`](../global.json) at repo root, `version: 10.0.300` + `rollForward: disable`；runtime 发布另受 toolchain lock 约束 |
| UI | WinForms (`UseWindowsForms=true`, WinExe) 单窗体（GuardianForm）+ WebView2（BootstrapPanel 引导页 + WebOverlayForm 运行态 overlay） |
| Native HUD 图像 | **SkiaSharp 3.119.4**（MIT；共享地图 WebP 按最长边 512px 解码）→ `System.Drawing.Bitmap`；PlayerInfo 的 8 个 canonical SVG 固定用 **Svg.Skia 5.1.1**，且只能经 `PlayerInfoStrictSvg` 受控 facade 解析并烘焙为原子 whole-batch：8 个 logical layer 拥有 10 个 PArgb payload；PlayerInfo active+inactive LRU 总预算 16 MiB，decoded/tinted 地图缓存分别使用 24/12 MiB |
| 构建 | 纯 producer `build-runtime-candidate.ps1`：**`dotnet publish --self-contained false`**（FDD、无 PDB）+ MSVC `cl.exe`（miniaudio + bootstrap）+ Rust/Cargo（sol_parser）；TypeScript/派生资产准备与产品审计已从 producer 分离 |
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
│   ├── *.dll (ClearScript / WebView2 / Vortice / SkiaSharp / Svg.Skia managed/native 闭包)
│   ├── THIRD-PARTY-NOTICES.txt                    第三方包与分发 notice
│   ├── miniaudio.dll                            P/Invoke side-car
│   ├── sol_parser.dll                           P/Invoke side-car
│   └── cf7-runtime-manifest.tsv                 producer 生成的 v1/v2 文件清单 + SHA256
├── tools/dotnet-runtime/
│   └── windowsdesktop-runtime-10.0.8-win-x64.exe   58MB MS 官方 installer，bootstrap 用
├── hotkey_guard.exe / Adobe Flash Player 20.exe / CRAZYFLASHER7MercenaryEmpire.swf / ...
└── logs/
    ├── bootstrap.log      ← bootstrap 每次启动 append；Core 早期阶段也续写启动诊断
    ├── startup-exit.jsonl ← 最近启动退出/失败原因码（机器可读，最多保留 20 条）
    ├── startup-failure-latest.txt ← 最近一次玩家自诊断弹窗摘要（若存在）
    ├── dumps/             ← Core native dump 与 createdump 日志（早期 hard crash 用）
    ├── perf-latest.jsonl  ← Core 启动性能时间线（若 Core 已进入托管入口）
    └── launcher.log       ← Core 进入托管入口后尽早写入（WebView2 预检前）
```

```
用户双击 CRAZYFLASHER7MercenaryEmpire.exe  (~259KB, native C++ bootstrap, 零 .NET 依赖)
       ↓
  开 logs/bootstrap.log (append)
       ↓
  检测 %ProgramFiles%\dotnet\shared\Microsoft.WindowsDesktop.App\10.* 是否在场
        ↓ 缺失                                      ↓ 在场 / 安装完成后
MessageBox 确认 → ShellExecute "runas"        校验 runtime manifest + 预置 .NET dump
tools\dotnet-runtime\windowsdesktop-runtime-10.0.8-win-x64.exe
/install /passive /norestart  (UAC 一次)
        ↓ 安装完成 + 二次确认                       ↓
        └──────────────────────────────────→ ShellExecute runtime\Core.exe
                                             --project-root "<projectRoot>"
       ↓
runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe  (255KB FDD apphost) + 19 DLLs (~49MB)
       ↓
Guardian Launcher 主逻辑 (WinForms / V8 / WebView2 / Vortice / ...)
```

**为什么 Core 在 `runtime/` 子目录而不是根**：用户在 projectRoot 浏览看不到 Core.exe，无从误点击触发 .NET apphost 的英文"You must install .NET to run this application"默认对话框。bootstrap 用 Chinese MessageBox + 自动 install installer 提供更友好的 UX。

**Bootstrap 设计原则**：纯 Win32 + CRT（静态链接 `/MT`），零 STL，输出 ~259KB；UTF-8 源码 (`/source-charset:utf-8 /execution-charset:utf-8`) 让中文 MessageBox 文本正确编码；**职责**：runtime 检测 + 触发 installer + 关键文件 preflight + runtime manifest SHA256 校验 + 预置 .NET dump 环境变量 + 显式传 `--project-root <abs>` + 转发命令行参数到 Core + 写 `logs/bootstrap.log`。Core 进入托管入口后通过 `StartupDiagnostics` 继续把早期阶段线写进同一文件，直到 `launcher.log` 通道就绪。Core 尚未起来时的 fatal 场景由 bootstrap 自诊断弹窗给出 `CF7-BOOT-*` 错误码，并允许玩家直接打开日志目录；若 Core 在 5 秒观察窗内非零/未知退出，bootstrap 会写 `startup-failure-latest.txt` / `startup-exit.jsonl`，并提示发送 `logs\dumps` 下最新 dump。

**为什么不用 self-contained single-file**：实测 146MB single-file blob 太大不利 git；改 FDD 分散到 23 个 manifest 文件、约 49MB（含 Native HUD WebP decoder），配合 bootstrap + bundled installer 处理 runtime 缺失场景。详见 [`docs/launcher-net10-migration-status.md`](../docs/launcher-net10-migration-status.md) "post-migration 二次审阅" 段。

### 关键路径与 hardcoded 名

- 用户面 entry：`CRAZYFLASHER7MercenaryEmpire.exe`（bootstrap，在 projectRoot 根）— **不要重命名**（19+ 处脚本 / 文档 / 自动化引用此名）
- FDD apphost：`runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`（csproj `<AssemblyName>` 控制名；纯 producer 先写隔离 candidate，promotion 后才进入正式 runtime）
- Runtime manifest：`runtime\cf7-runtime-manifest.tsv`（v2 记录三域构建身份、payload closure 与逐文件摘要；bootstrap preflight 校验入口 exe/runtime 字节，双故障域共识后随 promotion 原子落盘）
- Core projectRoot 解析：优先 `--project-root <abs>` CLI arg（bootstrap 注入）；次选 walk-up 哨兵文件 `crossdomain.xml`（覆盖 dev 直跑场景）；fallback `Environment.ProcessPath` 父目录
- 长跑进程：Core.exe（bootstrap 启动 Core 后立即退出）— `cfn-cli.sh` / `taskkill` / GPU pref 都针对 `runtime\Core.exe`
- Bundled runtime installer：`tools/dotnet-runtime/windowsdesktop-runtime-10.0.8-win-x64.exe`（~58MB，季度更新一次）
- Bootstrap 自有日志：`logs/bootstrap.log`（追踪 runtime 检测 / installer 调用 / runtime 目录与关键文件 preflight / manifest 校验 / dump 配置 / Core 启动后 5s 秒退观察；Core 托管入口还会续写 WebView2、config、文件探针、Steam、Flash trust、端口、任务注册、LaunchFlow 状态线）；`logs/startup-exit.jsonl` 额外保留最近 20 条退出/失败原因码，供客服脚本直接读取；`logs/startup-failure-latest.txt` 保留最近一次玩家自诊断弹窗摘要；`logs/dumps` 保留 Core hard crash dump 与 createdump 日志；即便 runtime 缺失场景，bootstrap 跑完仍留 trace，**不再「未配环境无 log」**

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

- [`../scripts/protocol_latency_cycle.ps1`](../scripts/protocol_latency_cycle.ps1)：单轮基线；只接受唯一 runId 闭环、由 AS2 队列定义派生的 exact 14 指标 schema、fresh compiler 0/0 与 retry=0，并交叉核对 raw samples 和 summary
- [`../scripts/protocol_latency_sweep.ps1`](../scripts/protocol_latency_sweep.ps1)：多轮抖动/尾延迟统计；任一 cycle 非零退出，或 JSON 缺失/null/非有限/负值/schema 不完整时整轮 fail closed，不把失败样本折成 0

## 目录结构

按 commit `3d8e5b7b68833a255c26a472e87fc93584010dd0`（2026-07-24）时的源码树复核。只列追踪目录；`bin/` / `packages/` / `target/` / `node_modules/` / `obj/` 等构建产物和缓存均由 .gitignore 管理。后续若需复核本节，优先看 `git diff 3d8e5b7b68833a255c26a472e87fc93584010dd0..HEAD -- launcher/`。C# 文件级权威以 [CRAZYFLASHER7MercenaryEmpire.csproj](CRAZYFLASHER7MercenaryEmpire.csproj) / [tests/Launcher.Tests.csproj](tests/Launcher.Tests.csproj) 的 `Compile Include` 为准，README 仅保留职责树。

```
launcher/
├── CRAZYFLASHER7MercenaryEmpire.csproj   C# 项目文件（SDK-style, net10.0-windows, AssemblyName=...Core）
├── Directory.Packages.props               中心化 PackageVersion 锁定（含 SkiaSharp 3.119.4 / Svg.Skia 5.1.1）
├── THIRD-PARTY-NOTICES.txt                PlayerInfo SVG renderer 完整依赖图与分发 notice
├── build.ps1                              兼容编排器（prepare → pure producer → policy，见下文）
├── build-runtime-candidate.ps1            纯二进制 producer（native/Rust/bootstrap/FDD publish）
├── setup-check.ps1                        构建/运行前依赖自检（.NET 10 SDK + WebView2 + VC + Rust + Node）
├── app.manifest                           DPI awareness / Windows 兼容声明
├── app.ico                                应用图标
│
├── data/
│   ├── save_schema.json                   存档编辑器 diff/默认值基线
│   ├── save_repair_dict.json              存档自动修复字典
│   └── map_hud_data.json                  Native HUD 小地图 catalog（prepare 派生、policy fail-fast 校验）
│
├── contracts/
│   └── panel-contracts.v2.json            NPC/KShop/Crafting/Hairdresser 跨层命令能力、AS2 业务裁决、数值权威、交互策略与共享边界向量登记表
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
│   │   ├── StartupDiagnostics.cs          Core 早期启动诊断 → 续写 logs/bootstrap.log（WebView2/config/文件/Steam/端口/LaunchFlow 阶段）
│   │   ├── OverlayBase.cs                 GDI+ Layered Window 覆盖层基类
│   │   ├── ToastOverlay.cs                GDI+ toast 消息（独立 ULW；仅 useNativeHud=false fallback；useNativeHud=true 由 Hud/ToastWidget 在 NativeHudOverlay 内承载）
│   │   ├── NotchOverlay.cs                GDI+ 刘海栏（独立 ULW，仅 useNativeHud=false fallback；useNativeHud=true 由 Hud/NotchWidget 在 NativeHudOverlay 内承载）
│   │   ├── HitNumberOverlay.cs            GDI+ 伤害数字
│   │   ├── CursorOverlayForm.cs           原生 cursor 视觉层（OverlayBase 子类，anchor-bound；回滚兜底）
│   │   ├── DesktopCursorOverlay.cs        桌面顶层 ULW cursor（默认；scale 跟 GuardianForm.ClientSize，跨 anchor 自由）
│   │   ├── WebOverlayForm.cs              WebView2 视觉层（WS_EX_TRANSPARENT）
│   │   ├── InputShieldForm.cs             幽灵输入层（GDI+ α 命中 + CDP 注入）
│   │   ├── NativeHudOverlay.cs            C# Native HUD 容器（Screen/Composite bounds 分离；透明保留区 click-through）
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
│   │   │   ├── NativeHudTheme.cs           Flash 槽位主题（黑底、直角发丝框、角标/压边/语义色）
│   │   │   ├── NativeHudFonts.cs           Native HUD 思源宋体私有加载 + 系统字体回退
│   │   │   ├── RightContextWidget.cs       右侧 6 入口动作行 + 条件状态槽 + compact/expanded 地图预览
│   │   │   ├── RightContextSlotOwner.cs     右侧条件槽封闭 owner（唯一优先级由 NativeHudOverlay 仲裁）
│   │   │   ├── SafeExitPanelWidget.cs      安全退出单行二次确认（仅 exact transaction owner 可绘制/命中）
│   │   │   ├── ComboWidget.cs              搓招输入态与命中通知
│   │   │   ├── ToastWidget.cs              toast 消息（useNativeHud=true 时承载，复刻 ToastOverlay 视觉，alpha 在 segment 颜色内做）
│   │   │   ├── NotchWidget.cs              刘海栏（稳定 CompositeBounds；FPS/BGM + 游戏/辅助/系统三行工具栏 + 通知/图表）
│   │   │   ├── PreparationNavigationCatalog.cs B1 frozen 六项目标、progression 投影与 Native/legacy HUD 行 fixture
│   │   │   ├── AudioHudState.cs             Native HUD 唯一 BGM 峰值历史（100ms 采样 / 250ms 播放态轮询）
│   │   │   ├── MapDisplayState.cs           runtimeMapMode / preference / effective 三层地图显示策略
│   │   │   ├── MapHudWidget.cs             小地图 shared renderer / blocks fallback
│   │   │   ├── PlayerInfo/                 HP/MP canonical SVG、typed manifest/strict facade、PArgb raster pipeline、fixture-only visual state/widget/compositor/path glyph atlas 与独立 click-through split surface（B0；无真实 UiData/`pi_*`）
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
│   │   ├── SolResolver.cs                 决议矩阵入口：tombstone → shadow → SOL → 版本分流；`source=sol` 时同步首导入 shadow
│   │   ├── SolParserNative.cs             sol_parser.dll P/Invoke 封装
│   │   ├── NativeSolParser.cs             `ISolParser` 默认实现
│   │   ├── SolFileLocator.cs              SOL 路径定位（仅当前运行根；`.swf/.exe` 双兼容 + root-scoped fallback）
│   │   ├── SaveMigrator.cs                2.7→3.0 迁移（含 legacy `mydata[3]` 缺失补 0）+ MergeTopLevelKeys + ValidateResolvedSnapshot
│   │   ├── LegacyPresetSlotSeeder.cs      标准 10 槽 shadow 预热：`list/load/load_raw` 前探测 legacy SOL 并补种 shadow
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
│   │   ├── ShopTask.cs                    K 点商城桥接 + 单写 owner / needs_reconcile / 写后 catalog 完整性 / callId 重放保护
│   │   ├── InventoryTask.cs               inventory-domain v1 白名单桥 + domain/cmd/callId 及可选 panel/instance binding 回包重写
│   │   ├── NpcShopTask.cs                 NPC 金币商店桥 + 严格 payload 白名单 / 写对账 / 防重放
│   │   ├── CraftingTask.cs                合成桥 + 分类/索引/token 白名单 / preview 对账门
│   │   ├── HairdresserTask.cs             理发店 snapshot/commit 桥 + shared pending lifecycle / fresh snapshot 对账
│   │   ├── SkillTask.cs                   skills-domain v1 严格 envelope / 实例租约 / 写对账与 cleanup 收敛
│   │   ├── EquipmentTuningTask.cs         equipment_tuning 严格 envelope / 实例租约 / write epoch 与精确对账水位
│   │   ├── MapTask.cs                     Web 地图 panel snapshot / refresh / navigate
│   │   ├── StageSelectTask.cs             Web 选关 panel snapshot / enter / jump_frame / return_frame
│   │   ├── IntelligenceTask.cs            情报详情 state / snapshot(itemName) / tooltip（按需读白名单 H5 正文）
│   │   ├── ArenaTask.cs                   竞技场（DEATH MATCH 角斗场）面板双层 callId 桥接（arena_response）
│   │   ├── ArenaCalibrationTask.cs        斗兽标定批次控制（arena_calibration / arena_calibration_response；startBatch/status/abort + JSONL writer）
│   │   ├── AgentControlTask.cs             无人值守 start/status/领域 opener + 当前 attempt 的 UiData s:1|ga ready 门
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
│   │   ├── hairdresser.css                 理发店双栏、目录、预览与故障态样式
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
│       ├── dressup-doll-renderer.js       Canvas 2D 对话框/战斗纸娃娃渲染器（纯测量 + 可选稳定 fit envelope）
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
│       ├── tooltip.js                     Tooltip（复合 hover/anchored + 长说明滚轮/键盘读取）
│       ├── icons.js                       图标 manifest 加载与解析（播放时间线消费 asset-timeline.js）
│       ├── game-ui-behavior.js            Overlay 统一禁原生选取/拖影/菜单（编辑控件显式放行）
│       ├── workbench.js                   Gate A1 primitive + Gate A2 accepted InteractionBroker
│       ├── workbench-inspection-viewport.js 共享瞬态检视相机（Canvas-only 缩放/平移/全貌复位，关闭清零）
│       ├── item-filter.js                  物品类别/套装模型 + 渐进树导航 + 标题区单行折叠面包屑（目录本地计数 / 库存权威 facets 共用）
│       ├── kshop-runtime.js               KShop request mux + save/checkoutCommit/legacy claim 写协调
│       ├── inventory-runtime.js           range/window snapshot / category|set filterSpec / owned write gate / transfer·discard·sortAndMerge Coordinator
│       ├── inventory-ui.js                页码/类别·套装树筛选/权威整理 + OwnedInventoryViewShell
│       ├── kshop-views.js                 KShop 目录/购物车/历史待领取 View + 权威二级结算页
│       ├── kshop.js                       采购、权威直接交付结算 + 背包↔战备箱组合层
│       ├── inventory-workbench.js         workbench 唯一注册、公共 header/close 与 storage/tuning/build dispatch
│       ├── inventory-storage-workbench.js storage/tuning controller（不注册 Panel）
│       ├── character-build-session.js     loadout mux、revision、写入/对账与 finalize gate
│       ├── character-build-view.js        单 Canvas 纸娃娃 home、11+4 槽、候选与顶部动作组合
│       ├── character-build.js             build controller，同实例组合 session/view/storage ports
│       ├── character-build/
│       │   ├── character-build-template.js 静态双栏壳 markup（无行为/authority）
│       │   ├── character-build-action-view.js 候选动作投影与唯一调制能力判定
│       │   ├── character-build-tuning.js  已穿戴调制 adapter 与 exact detach
│       │   ├── character-build-slot-transition.js 调制中槽位 rebind / detach 事务 leaf
│       │   ├── character-build-pose.js    选中姿态与七种 battle pose 稳定取景集合
│       │   ├── character-build-doll-preview.js exact stage/Canvas 的全 body 放大预览与共享瞬态相机编排
│       │   ├── character-build-stats-view.js  9 组 47 行属性、负重色带、抗性图标与线性/对数相对图
│       │   └── dev/                       exact stats fixture 与独立/生产路由 browser harness
│       ├── loot/
│       │   ├── loot-runtime.js            loot request mux / exact container binding
│       │   ├── loot-state.js              claim/close/query 权威状态机与 fresh snapshot 刷新
│       │   ├── loot-view.js               战利品双栏、容量阻塞 CTA 与确认模态
│       │   ├── loot-organizer.js          同一 loot panel 内嵌背包↔战备箱整理子页
│       │   └── loot-panel.js              loot 生命周期编排、整理子页往返与实例级 cleanup
│       ├── equipment-tuning-runtime.js    tuning-domain call/session mux + timeout/未知写结果对账
│       ├── equipment-tuning-view.js       七类 wire operation / 四栏组合的 snapshot→preview→token-only commit 右栏 View
│       ├── equipment-tuning/dev/harness.html  装备调制生产模块 browser harness
│       ├── crafting-runtime.js             crafting-domain session/callId mux
│       ├── crafting.js                     配方目录 + 权威详情/一次性提交双栏工作台
│       ├── crafting-materials.js           材料目录 + 怪物/关卡来源 + 合成用途只读视图
│       ├── crafting-inspector.js           合成产物三路只读检视器（武器单件/复合、性别防具、当前图标 + 缩放平移）
│       ├── hairdresser-runtime.js           hairdresser shared request mux facade / snapshot·commit 校验
│       ├── hairdresser.js                   77 行发型目录 + 本地纸娃娃预览 + unknown-write 对账
│       ├── hairdresser/dev/harness.html     理发店生产模块三视口 browser harness
│       ├── skills-runtime.js               skills-domain 实例隔离 / request mux / write-reconcile 状态机
│       ├── skills.js                       技能浏览、教师学习、快捷槽装备与被动开关面板
│       ├── skills/dev/harness.html         Skill 生产模块 browser harness
│       ├── kshop/dev/harness.html          KShop Step 0–5a / Gate A1–A3 browser + visual harness
│       ├── npcshop-runtime.js             NPC 商店独立 request mux + callId/session 隔离
│       ├── npcshop.js                     NPC 商品目录 + 待购/待售选择 + 权威原子二级结算
│       ├── npcshop/dev/harness.html        NPC 商店 browser harness
│       ├── team/team-panel.js             战队唯一生产 Panel（薄协调器：无独立顶栏，唯一 tab 条迁移注入子面板 header 槽位）
│       ├── team/dev/harness.html           战队 browser harness（四标签 / 分类 / 佣兵卡片 / 详情栏 / 会话记忆）
│       ├── pet-panel.js                   可嵌入宠物子控制器（管理/领养/进阶；伙伴/战宠/机械按 rosterType 过滤；列表页 header 含 .team-tabs-slot）
│       ├── pets/dev/harness.html          宠物子控制器 browser harness
│       ├── merc-panel.js / merc-data.js   可嵌入佣兵子控制器（管理/雇佣/培养三页 + 2 列横版卡 + 底部详情栏技能流）+ 槽位常量
│       ├── arena-panel.js / arena-custom-parameters.js / arena-custom-param-editor.js / arena-custom-undo.js / arena-custom-polling.js / arena-custom-result-view.js / arena-factions.js / arena-meta-rosters.js 竞技场面板（Panels.register('arena')：标准档位卡 + 死线警报隐藏卡 + 详情/进场；ArenaTask 双层 callId）
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
│       │       ├── qa-suite.js             in-page QA 套件（map-ui1~map-ui33，含动态缩放用例）
│       │       ├── run-qa.js               headless Playwright runner（node …/map/dev/run-qa.js）
│       │       ├── screenshot.js           红点/选关视觉回归截图（写 tmp/map-red-dot-shots/）
│       │       ├── builder.html            地图可视化构建器入口（跳转到 builder 模式 preview）
│       │       └── preview.html / .css / .js   地图 manifest 预览 / 校准页
│       ├── tasks/                          【任务界面 Web 迁移 · 协议接入（2026-05-30）：生产模块 + C# Task + AS2 service 已接入；仍需 fresh Flash 行为证据（trace 或 Output Panel 副本，明确类型）/ IDE 复核 / 游戏内端到端复核后才能标记生产可用】
│       │   ├── task-panel.js               任务界面生产 panel（我的任务/事件日志/成就 + 副本任务 tab）
│       │   ├── mission-brief-view.js        副本任务与前线调度板共用的关卡简报/限制/奖励渲染器
│       │   ├── dispatch-board-view.js       前线调度板聚合模式（板内任务列表 + 关卡简报 + 委托对白 + 进入关卡）
│       │   ├── task-catalog.json           任务 Web 面板分类 / 展示目录（v2：chain="委托" 挂 dungeon{} 供副本 tab）
│       │   ├── ../../assets/dungeon-posters/ 副本 WANTED 海报 PNG（ffdec 烘焙 flashswf/images/<n>.swf）+ manifest.json
│       │   ├── achievement-catalog.json    成就 Web 面板目录
│       │   ├── achievement-tab.js          任务面板内成就 tab 渲染器
│       │   ├── assets/                     迁移自 Flash 的任务界面生产美术（task_main_bg / task_icon_bg / task_scroll / requirement_* / finish_npc）
│       │   └── dev/
│       │       └── harness.html            任务面板 browser harness（常规任务/副本/成就/前线调度板 mock + QA）
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
│   ├── Contracts/PanelContractVectors.cs  读取同一 `panel-contracts.v2.json` 的 xUnit 边界 fixture
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
- **正式 runtime 发布工具链**：从仓库根运行 `powershell -ExecutionPolicy Bypass -File tools\bootstrap-runtime-build-env.ps1`。脚本按 [`runtime-toolchain.lock.json`](../config/build/runtime-toolchain.lock.json) 补齐 .NET `10.0.300`、Rust `1.96.0`、VS Build Tools `17.14.36` / MSVC `19.44.35228.0` 与 Windows SDK `22621`，并校验固定安装器和最终 executable 的 SHA-256；`.NET` provisioning 固定到官方 `dotnet/install-scripts` 的完整 commit URL，避免 mutable `dot.net` 重签导致云端 hash 漂移。只有 VS 阶段需要一次 UAC。已有环境用 `-VerifyOnly`，不会下载或安装。
  - .NET 与 Rust 使用 user scope，不要求改系统 PATH；VS 可以与机器已有更高版本实例并存，检测器遍历所有实例选择精确匹配字节。
  - 纯 producer 会再次运行正式门禁；bootstrap 的退出码不能代替构建验证。完整身份、队列、证明与换机规则见 [runtime v2 发布列车](../docs/runtime-build-reproducibility.md)。
  - 普通 Web / AS2 / 数据开发不要求取得 runtime 发布权，但不得用不匹配环境重建并提交二进制。
  - Rust 首次构建 cargo 需联网拉 flash-lso（git pin）及其传递依赖。Cargo.lock 只锁版本集，**不等价于离线可复现**——能否在新机器离线构建取决于本机 `~/.cargo/registry/cache` 和 `~/.cargo/git/checkouts/` 是否已有对应依赖（或是否做过 `cargo vendor`）
- **Node.js + npm**（用于编 V8 的 TypeScript 脚本 + cf7-packer + cf7-save-repair-dict-build）：Node 18+（LTS 均可）
  - 安装：`winget install OpenJS.NodeJS.LTS`
  - `prepare-launcher-release-assets.ps1` 负责 locked restore、TypeScript 编译与派生资产；producer 不调用 Node
- **WebView2 Runtime** Evergreen Bootstrapper（运行期硬依赖）
  - 检测：`setup-check.ps1` 读注册表 `HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`
- **终端**：PowerShell 或 Git Bash 都行
- **推荐先跑环境自检**：`powershell -File setup-check.ps1`
  - 当前脚本检查 5 项：`.NET 10 SDK + WindowsDesktop runtime`、`WebView2 Runtime`、`MSVC Build Tools`、`Rust cargo`、`Node + npm`

### 离线开发入口与身份绑定候选

```powershell
chcp.com 65001 | Out-Null
powershell -File launcher\setup-check.ps1
powershell -File automation\dev.ps1
# 或双击项目根：本地开发启动.cmd
```

`automation/dev.ps1` 是日常 Launcher/Host 本地验证的显式入口。它每次重算当前 Worktree build identity，仅复用 `tmp/runtime-candidates/v2/` 中身份精确相同且闭包无分叉的 candidate；未命中时调用 `build.ps1 -SkipPrepare -SkipPolicy -BuilderId local-dev` 生成隔离 candidate，然后把该精确绝对路径交给 `automation/start.ps1 -CandidateRoot`。候选自始至终为 `NOT_DEPLOYED`，不覆盖根 bootstrap 或正式 `runtime/`。

`tmp/runtime-dev/active.v1.json` 是忽略路径中的便利索引，不是信任证据；执行前仍重算身份、重验 metadata/manifest/Core 字节。可用参数为：

```powershell
.\automation\dev.ps1 -Status      # 只读报告匹配/过期/同身份闭包分叉
.\automation\dev.ps1 -ReuseOnly   # 无精确命中则失败，不构建
.\automation\dev.ps1 -ForceBuild  # 强制新建，与已有同身份闭包不一致仍拒绝激活
.\automation\dev.ps1 -BuildOnly   # 只选择/构建并验证，不启动
```

断网复用已有匹配 candidate 不需要云端；断网重建的前提是本机已安装并通过锁定的 .NET / MSVC / Windows SDK / Rust 工具链，NuGet 与 Cargo 依赖也已缓存。首次供给与云端正式发布均是独立流程，日常开发不要求联网、GitHub 证明或 promotion 权限。

`automation/start.ps1` 无 `-CandidateRoot` 始终是已 promotion 正式 runtime 的标准入口，不猜选开发输出。`automation/start.ps1 -CandidateRoot <absolute candidateRoot>` 仅是低层诊断兼容入口：它只接受本仓 `tmp/runtime-candidates/v2/` 下的绝对 canonical 路径，拒绝 reparse 别名，核对 metadata/manifest 的 schema、build identity、payload closure 与实际 Core SHA-256，再用候选自身 bootstrap `--verify-runtime-only` 启动并由 Core 反向自检。必须保存它确认的 `runtimeMode=isolated_candidate`、`processPath`、`coreSha256`、`buildIdentity`、`payloadClosure`；不要手工直启、不要从 `launcher/bin` 或旧正式 `runtime/` 代替，也不得手工复制 candidate 进正式 `runtime/`。

状态统一为 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`。`dev.ps1` 默认成功启动最多达到 `candidate_executed`，后续真实领域闭环才能达到 `e2e_verified`；正式部署仍须冻结 immutable Git tree，完成双 signer / 双 faultDomain 共识、production policy receipt 与 v2 strict verifier 后，只经 `tools/promote-runtime-bundle.ps1` 原子提升。promotion 后还必须从无参数 `automation/start.ps1` / 根 bootstrap 启动同一身份并完成 smoke，才达到 `standard_entry_verified` 并可称“已部署 / 正式验收”。逐级证据定义见 [runtime v2 发布列车](../docs/runtime-build-reproducibility.md#开发到正式验收状态机)。

### v2 职责与身份

| 层 | 入口 | 职责 |
|----|------|------|
| Prepare | `tools/prepare-launcher-release-assets.ps1` | locked restore、V8 TypeScript 与 task/map/achievement/arena/save-repair 等 tracked 派生资产；默认不重建含私有输入/时间戳的 save schema |
| Producer | `launcher/build-runtime-candidate.ps1` | 精确环境门 → deterministic miniaudio → clean/locked Rust parser → native bootstrap → 无 PDB FDD publish → immutable candidate/manifest v2 → 120 秒内同步等待 `--verify-runtime-only` 的真实 exit code；失败保留诊断，成功清除 candidate `logs/` |
| Policy | `tools/validate-launcher-release-policy.ps1` | Web/data/native cursor/优化程序集等只读产品审计；`candidate-player-info-svg-contract` 对精确 v2 candidate 执行 locked restore，并核对 9 项 embedded resource、8 个 canonical source byte、strict 最小 raster、notice、禁用依赖；runtime 根或任意后代出现 reparse/junction 会在递归枚举前被拒绝。随后实际 renderer-family DLL/native 相对路径集合须 exact=11、每项非空并记录 actual size/hash；这些字节再由 candidate payload closure/build identity 绑定。deps libraries 与唯一 renderer-bearing runtime target 也须精确相等；额外顶层 DLL、嵌套 native 文件或 deps library/runtime-target 都 fail-closed；`panel-cross-layer-contracts` 继续核对 Panel command identity、capability/access、唯一 AS2 业务裁决 owner、数值权威、NPC 双上限交互策略、exact response handler 与剥离注释后的 Host/AS2 可执行锚点；最后验证 tree 前后不变并签发绑定 tree/identity 的 production receipt |

输入由 [`runtime-inputs.v2.json`](../config/build/runtime-inputs.v2.json) 分为 `artifactSourceHash`、`producerRecipeHash`、`toolchainLockHash`、`policyHash` 四个互斥域；build identity 只含前三域。payload closure 排除 manifest，所以政策/manifest 变化不会冒充二进制漂移。candidate 位于 `tmp/runtime-candidates/v2/c-<identity-prefix>-<builder-hash>-<run-token>/`，完整身份保留在 metadata/证明；短目录与构建前后的 MAX_PATH 门兼容 native bootstrap 的 legacy 缓冲。producer 使用独立 native/Cargo/MSBuild/temp 输出，不写正式 runtime、不签名、不跑政策门。

### 正式发布列车

正式发布不以 `build.ps1` 的单机 exit 0 为准：最终 tree 先经 `new-runtime-build-request.ps1` 冻结为 Git bundle；注册本地 worker 在隔离 clone 中运行纯 producer，并用 CurrentUser 不可导出 X509 key 签名。共享 queue 必须限制为受信维护者可写，因为 bundle 内构建源码会在 builder 账户执行；worker 会清除调用者 Git index/worktree/object 上下文，失败日志在 checkout 删除前受限归档。推荐第二故障域由 `.github/workflows/runtime-cloud-builder.yml` 在明确的 `windows-2022` / VS 2022 runner family 构建相同 full commit，再用 GitHub OIDC/Sigstore keyless provenance 证明。cloud 只接受 `Crazyfs` / `Flash-Night` 固定 actor ID 的首次 `workflow_dispatch`，但不要求两人共同在线或互相审批；任一授权发布者都可组合本地票与自动云端票。promotion 至少要求两个不同 signer identity 和两个不同 `faultDomain`，且 artifact/recipe/toolchain/build identity/payload closure 全等。

当前 consensus 采用本地 X509 keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3` / `physical-host-a` 与 GitHub OIDC builder identity `AC20F09BE9C7138A9C3B5BECCC39944C434FF52C49A3EDF3268647E54599D72D` / `github-hosted-windows`（run `30511825565`）；tracked registry 仍只含公钥。正式 bootstrap/runtime/manifest/consensus 已由唯一 promotion 入口切换到 request `F5992FE5AFA3B74024CACEFCA1BACD311C1A3EE7C50CF3D08145A3E49BC211BC`、build identity `EB60E241929B5F88110C4EAE218DFD98569AE657F2B765179DBF644F0EEE0255` 与 payload closure `889FC7A800CFE738EAA99992CD6C5689AA65ECFEF3F406A617B3A1A344F4520B`；此前材料/商城/战备箱、角色构筑 ↔ Skills、地图资源箱、理发店、商店与单-canary consensus 均只保留为历史记录。一次性 migration fuse 不得复用，后续发布不得降级 v1。

```powershell
$request = .\tools\new-runtime-build-request.ps1 `
  -QueueRoot <queue-root> -SourceKind Treeish -Treeish <full-commit>
.\tools\invoke-runtime-build-worker.ps1 `
  -QueueRoot <queue-root> -WorkerId <id> -CertificateThumbprint <thumbprint> -Once
.\tools\get-runtime-build-request-status.ps1 `
  -QueueRoot <queue-root> -RequestId $request.requestId
$cloud = .\tools\invoke-runtime-github-build.ps1 -SourceCommitOid <full-commit>
```

cloud helper 会等待精确 run、安全解压并返回 `$cloud.candidateRoot` / `$cloud.proofPath`；unsigned candidate/envelope 只保留 1 天，失败 diagnostics 与 signed 结果保留 7 天，超期未 promotion 时重新 dispatch。取得 production policy receipt 和第二故障域证明后，唯一部署入口是 `tools/promote-runtime-bundle.ps1 -RequestId ... -PolicyReceiptPath ...`。它验证 request、candidate、receipt、证明和 fault domains 后事务替换 bootstrap/runtime/consensus，随后在 120 秒内同步等待 full-install `--verify-only` 的真实 exit code，失败或超时自动回滚。

只需要留存“双 builder / 双 faultDomain 对同一冻结闭包达成一致”而明确不部署时，仍调用同一脚本并追加 `-VerifyOnly -ReportPath <absolute-new-json>`。该模式完整重放 request/worktree/receipt/candidate/证明/去重/consensus 与 live deployment cleanliness；脚本声明的唯一仓内输出是在项目根内非受保护、父目录已存在且无 reparse/8.3 alias 的新路径 CreateNew 一份 `cf7-runtime-promotion-preflight.v2`。报告显式记 `reportCreated=true`、runtime/release-state/promotion/deployment 均未改变且 `reusableAsPromotionInput=false`，不对 Git/gh 的仓外实现缓存作无范围断言。写前/写后任一输入或 live deployment 漂移都会删除报告并失败。它不写 bootstrap、`runtime/**`、manifest、consensus 或 promotion transaction，也不能作为后续 promotion 的缓存输入；正式发布必须去掉两个参数重新跑全链。完整 enrollment、cloud artifact 验证、两种 promotion 调用与 CI `source-ahead` 规则见 [runtime v2 发布列车](../docs/runtime-build-reproducibility.md)。当前受控部署已是 v2；任何后续部署变更都必须带新的合法 v2 consensus，CI 永久禁止降级。

> producer / `build.ps1` **都不跑** `launcher/tests/`；测试走独立 `launcher/tests/run_tests.ps1`。不得单独恢复、复制或冲突取舍 runtime 二进制。正式根的 headless 直启 Core 必须先调用根 bootstrap `--verify-only`；符合上文身份与路径约束的隔离 candidate 则先调用自身 bootstrap `--verify-runtime-only`。两种模式下 Core 都会在最早入口按当前身份反向执行同一类自检并 fail-closed。

### promotion 后的正式产物（项目根目录）

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
| `Svg.Skia.dll` + `Svg.Animation.dll` + `Svg.Custom.dll` + `Svg.Model.dll` + `Svg.SceneGraph.dll` + `ShimSkiaSharp.dll` + `ExCSS.dll` | 生产 lock graph 精确版本 | PlayerInfo 受控静态 SVG managed renderer 闭包；不含 `Svg.Skia.JavaScript` / Jint |
| `SkiaSharp.dll` + `libSkiaSharp.dll` + `HarfBuzzSharp.dll` + `libHarfBuzzSharp.dll` | 生产 lock graph 精确版本 | Skia/HarfBuzz managed + win-x64 native 依赖；`SkiaSharp` 固定 3.119.4 |
| `THIRD-PARTY-NOTICES.txt` | ~143KB | PlayerInfo renderer 依赖 attribution、MIT/MS-PL 与 Win32 bundled notice；production contract 要求源码/candidate exact bytes |
| `miniaudio.dll` | 778KB | 原生音频引擎（WASAPI）；独立 `cl.exe` 编译；与 Core.exe 同目录让 P/Invoke 命中 |
| `sol_parser.dll` | 225KB | Rust AMF0 → JSON 解析器（Protocol 2 存档决议） |

**projectRoot/tools/dotnet-runtime/**：
| 文件 | 大小 | 说明 |
|------|------|------|
| `windowsdesktop-runtime-10.0.8-win-x64.exe` | 58MB | **Bundled .NET 10 桌面运行时 installer**；bootstrap 在 runtime 缺失时 `ShellExecute "runas" /install /passive /norestart`。MS 官方包，季度更新一次 |

> **入口分工**：用户**只**双击 `CRAZYFLASHER7MercenaryEmpire.exe`（bootstrap）。Bootstrap 发起 Core 后会观察 5 秒：若 Core 非零/未知秒退，`bootstrap.log` 记录退出码，`startup-failure-latest.txt` / `startup-exit.jsonl` 记录 native 侧失败摘要，并提示发送 `logs\dumps` 最新 dump；若仍运行，bootstrap 退出，长跑进程是 `runtime\Core.exe`。所有 launcher 运行期行为 — V8 / WebView2 / Flash 嵌入 / 焦点诊断 / 存档决议 — 都在 Core 进程里。`cfn-cli.sh` / `taskkill` / GPU pref 都针对 `runtime\Core.exe`，不针对 bootstrap。

> **诊断 trace**：runtime 缺失场景仍写 `logs/bootstrap.log`（bootstrap 启动时 append），不再「没装环境就没 log」。Core 进入托管入口后通过 `StartupDiagnostics` 续写同一文件：`core.main_enter`、`core.environment`、关键 sidecar / 游戏文件探针、WebView2 预检与 BootstrapPanel 初始化分段、Steam / Flash trust、端口、任务注册、`launch.state` 都能在 `bootstrap.log` 中看到。bootstrap 在启动 Core 前会设置 .NET dump 到 `logs\dumps\Core-%p-%t.dmp`，并校验 `runtime\cf7-runtime-manifest.tsv`；Core 未进入托管入口就秒退时，native 侧会写 `startup-exit.jsonl` 与 `startup-failure-latest.txt`。`StartupDiagnostics.Exit/Failure` 会同步写 `logs/startup-exit.jsonl`（含 `terminal` 标记）；失败路径会弹出玩家自诊断报告，写 `logs/startup-failure-latest.txt`，并自动生成 `logs/diagnostic-*.zip` 供玩家发送；`LogManager` 文件通道会在 WebView2 预检前开启并写 `logs/launcher.log`；性能时间线写 `logs/perf-latest.jsonl`。

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
      "label": "Build Guardian candidate",
      "type": "shell",
      "command": "powershell -File launcher/build.ps1 -BuilderId local-dev",
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

1. 先跑 `resolve-dotnet.tests.ps1` 的纯 selector 负例矩阵与 repo-root 集成检查；只有 10.0.301/10.0.400、缺失或未知 roll-forward 策略都必须 fail-closed
2. 通过 `resolve-dotnet.ps1` 探测用户级与系统级 host，并由 `global.json` 强制选择精确 10.0.300 SDK；即使只差一个 patch 的 10.0.301 也拒绝
3. echo `dotnet --version` 作为日志证据
4. `Push-Location $projectRoot` 保证 dotnet host 找到 repo root 的 `global.json`（SDK pin 10.0.300 + `rollForward: disable`）
5. `dotnet test Launcher.Tests.csproj -c Release` —— Microsoft.NET.Test.Sdk + xunit.runner.visualstudio 自动 discover + run，连带编译主工程的 `ProjectReference`

### 测试覆盖

PlayerInfo NativeHud 已把 `Svg.Skia 5.1.1`（`SkiaSharp 3.119.4` 保持不变）、同一份 `PlayerInfoStrictSvg` facade、8 个 SVG + runtime manifest 和 `THIRD-PARTY-NOTICES.txt` 接入生产项目；repo-only provenance/oracle evidence 不嵌入 Core。隔离 qualification 仍可按下列入口复跑 synthetic/canonical corpus：

```powershell
chcp.com 65001 | Out-Null
. .\launcher\resolve-dotnet.ps1
$dotnetHost = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path
& $dotnetHost restore tools\player-info-hud\renderer-qualification\RendererQualification.csproj --locked-mode -r win-x64
& $dotnetHost build tools\player-info-hud\renderer-qualification\RendererQualification.csproj --no-restore -c Release -r win-x64
& $dotnetHost run --project tools\player-info-hud\renderer-qualification\RendererQualification.csproj --no-build --no-restore -c Release -r win-x64 -- `
  --asset-manifest launcher\src\Guardian\Hud\PlayerInfo\Assets\player-info.manifest.json `
  --report tmp\player-info-hud-b004-validation-fresh.json
```

历史 `tools/player-info-hud/evidence/b0-02/qualification-report.json` 固定记录原始 B0-02 的 10/10 行为测试与 16 项 fail-closed，不得被当前 harness 覆盖。B0-04 提交快照保持 `isolated_qualification_passed`：12/12 行为测试、78/78 fail-closed（其中 58 项值级 grammar）与 8/8 canonical SVG，且该历史报告的 `rendererQualified=false` 不回写。B0-03b 的生产结论必须另对**真实 v2 candidate**运行：

```powershell
& .\tools\validate-player-info-svg-production-contract.ps1 `
  -ProjectRoot (Get-Location).Path `
  -CandidateRoot '<absolute-v2-candidate-root>' `
  -Report 'tmp\player-info-hud-production-contract.json'
```

只有报告同时为 `status=passed`、`mode=candidate`、`policyEligible=true`，并通过 production policy 与本片全量回归，才可按 [B0 专项 ADR](../docs/玩家信息界面-NativeHud-SVG真源与程序化动效-B0-ADR与分片施工计划-2026-07-28.md) 记为 `renderer_qualified`；直接 `--core` 仅是 `policyEligible=false` 的诊断 seam。该状态不代表视觉 parity、`PlayerInfoWidget`、真实 `pi_*`、promotion 或部署。完整 structural/Web/FFDec/Flash diagnostic 与人工接受边界见 [`tools/player-info-hud/README.md`](../tools/player-info-hud/README.md)。

B0-05 把 embedded manifest 解析为 child authoring metadata 与 main-viewport-clipped HP/MP layer contract；`1024×64@(0,512)` 不是 runtime clip。物理尺寸按 Flash content viewport `height/576` 生成（PMv2 monitor DPI 只作 telemetry，不二次乘 scale），单 worker latest-wins 管线原子发布 8 个 logical layer / 10 个 owned PArgb payload 的 `Format32bppPArgb` whole-batch；`mp.fill` 拥有 canonical + 两个 clip fragment，完整 raster key 为 8 字段并含 `sourceToBitmapIdentity`。active+inactive whole-batch LRU 合计不得超过 16 MiB。`TryUseCurrent` 只借用锁内 batch，借用回调内重入 `Request/Dispose` 会 fail-closed；`Dispose` 清空排队通知并等待外部正在执行的 observer 退出，防止借用 bitmap 或旧通知越过所有权终点。对 active raster worker，B0-05 的 `Dispose` 只发 cancel；并发 shutdown 必须继续 `await WaitForIdleAsync()` 才是资源释放终点。专用入口为 `tools/player-info-hud/run-b0-05-runtime-qualification.ps1`，其 v2 fresh-bake 合同先以同一 `Task.Run`/fresh `Bake` 路径固定执行 16 轮四 viewport round-robin excluded warmup（64 个记录样本、无自适应停），再取每 viewport 20 个 acceptance 样本，p95 门仍为 100 ms；报告必须显式保持 `measurementKind=synthetic_fixed_bounds`。B0-05 的 near-full bridge 已裁决 `split_required`：PlayerInfo fixture/未来生产 surface 不得注册进现有 `NativeHudOverlay` 的单一 union。

v2 B0-05 formal runner 共 32 Gate；在启动任何 dotnet host 前拒绝已登记的 `DOTNET_*` / `COMPlus_*` JIT/GC 覆盖，并由报告和脚本共同核验 Normal priority、继承 affinity 与 server-GC。parse/raster counter 只代表完成的 StrictSvg/Skia payload-slot operation，不代表 PArgb copy completion，也不作逐 logical-layer 归因；单独的 PArgb copy 诊断只对 8 个逻辑层各复制一个代表性 payload，`mp.fill` 两个 fragment 不在该 copy 诊断中。

B0-06 已按该裁决实现窄纵切：`PlayerInfoSplitSurface` 唯一持有并推进只接 11-case fixture 的 `PlayerInfoAnimationModel`，`PlayerInfoWidget` 只消费注入的 getter-only `IPlayerInfoVisualStateSource`，不保存 model 或写代理。compositor 使用 MP 两个 immutable PArgb fragment、HP 固定覆盖轮廓 + 旋转渐变和 source-bound Aero/LCD Std path glyph atlas；typed effect policy 精确包含两个 B0 `ImplementedActive`（`hp-mp-dynamic-text-and-glow`、`hp-horizontal-line-glow`）与唯一 `DeferredB3` 的 `hp-light-overlay`，窄 `PlayerInfoCompositionRecipe` 固定 9 个文字布局并对合同漂移 fail-closed，不引入通用效果图。MP current 为右锚 `74.55`；maximum 的 XFL authored 左锚为 `80.65`，C# path rasterizer 对 Flash standard-text coverage 应用 `+0.30` local phase correction，effective anchor 为 `80.95`，两层 `00000` 装饰底字分别与前景锚点关系锁定。direct comparator 要求四字段 unique `bestDx=0`，并按 label/maximum/percent leading edge、current trailing edge 检查 anchor-edge delta=0；cyan-weighted centroid 只诊断。三处 HP 文字使用由 XFL/compiled SWF 解析出的 source-red Glow，MP 无 Glow；HP 以 `sigma=1` 两次 source-over blur（alpha 255 + 128）近似 authored strength 1.5，再绘白色 core。横线同为 red blur + white core；只有保留 authored `overlay` 元数据的 hp light-overlay 延后到 B3，B0 不渲染它。生成 glyph source 另有 fail-closed 测试按 tracked provenance 核验路径、编码、字节数与 SHA-256。`PlayerInfoWidget.TryHitTest` 恒 false。`PlayerInfoSplitSurface` 是单独的 `OverlayBase` / `IPanelHudCompanion` layered HWND；PanelHost Resume 先保持 pending，只有有效布局且 raster request 已建立才结束恢复，否则等待后续布局重试，shutdown 显式 drain raster worker。Program 仅在 `useNativeHud=true`、非 `--bus-only` 且 `CF7_PLAYER_INFO_FIXTURE_CASE` 精确命中 allowlist 时创建它；创建失败或未设置变量都保留旧 Flash HUD，代码不发起隐藏/修改旧 HUD。它不实现 `IUiDataConsumer`、不读取 `PlayerInfoSnapshotBuilder`、不新增 `pi_*`，因此不是 production runtime integration。

PlayerInfo split surface 为当前 tight physical bounds 持有一个可复用的 top-down PArgb DIB 与 memory DC；尺寸变化时才重建，逐帧由 compositor 直接绘制该 DIB 的 non-owning `Bitmap` view，再提交 prepared DC，不发生调用方每帧 `GetHbitmap` 或额外 managed→HBITMAP 中间复制。故 B0-06 的 `LayeredWindowCommitResult` 计时口径是实际 prepared-DC `UpdateLayeredWindow` transaction，不再声称每帧包含 DIB/DC setup+cleanup；后者被摊销到 surface 生命周期，并继续由 lifecycle GDI/USER/process 零增长与趋势门约束。

B0-06 formal runner 复用 B0-05 的同一 execution-environment 合同：启动任何 `dotnet` host 前拒绝 exact 12 个已冻结 JIT/GC override 名，要求 runner priority=`Normal` 并冻结非零 affinity mask；报告与脚本再独立重建 testhost 的 JSON 布尔字段类型、override 全空、priority=`Normal`、affinity 与 runner 精确相等、server GC=false。该合同直接参与 qualification status/failures；未新增 Gate ID，总数仍为 48。现有 warmup Gate 有意从 v1 的单组收敛收紧为连续两组收敛，原 GDI/USER/process handle 零增长及趋势数值门不变。

B0-06 自动入口为 `tools/player-info-hud/run-b0-06-runtime-qualification.ps1` 和 [`tools/player-info-hud/README.md`](../tools/player-info-hud/README.md) 的 C# visual capture / headless Edge direct-edge 流程。qualification 合同固定 3000 visible visual steps、3000 idle ticks，并在同一 STA/owner 上运行最多 5 个 100-cycle excluded warmup group；只有三类 handle 的全部 checkpoint 不高于各自组起点、endpoint delta 不为正且无正向趋势时，该组才严格收敛。必须连续两组各自满足该规则，首个合格 pair 后才立即运行新的独立 100-cycle acceptance group；五组内没有合格 pair 必须以 `diagnostic_after_warmup_cap` 失败，不能放宽原门。commit `bf8dd2c…8479` 的 47/47、run `a6aadeb6…7a7b`、旧 NativeHud/split p95 与 C#/Web/comparison A/B 都是历史 v1 qualification，只证明该旧 source/binary/renderer closure，不能批准 main-space v2。最终 source merge `40853287e7ed04714d68935c0002f8ad6d8aea05` 已完成 clean B0-06 48/48（run `ed61d7275fdd4a96a73f762c5c2a4d71`）及同源 C#/Web/direct A/B 冻结；tracked `visual-evidence.v2` 对两轮分别固定 C# `36 files / 35 PNG / 1,261,624 B / DD58…661E`、Web `12 files / 11 PNG / 221,781 B / 9D21…7A7B`、direct report-excluded `66 PNG / 3,114,450 B / F05A…ABF`，四个 MP 字段均为 unique `bestDx=0` 且约定锚边 `anchorEdgeDx=0`。visual manifest 的 capture-time 字段固定为 `structural_capture_complete / fixture_only`，individual comparison 固定为 `diagnostic_awaiting_human_review` 且无接受阈值；这些冻结字段不回写。Web scope 精确为 `canonical_static_svg_layers_only`，不含 C# 程序化文字/Glow，因此 C#↔Web 指标明确包含 layer-scope difference。其后的 exact `p50` isolated-candidate 人类 receipt 已在真实游戏 composite 接受 visible DWM、z-order/occlusion、click-through、动效与审美，并以 source-bound main-RSL-equivalent capture 将 oracle 冻结为 `oracle_frozen_for_b0`，故 B0 为 `b0_accepted`；该外部接受不声称 `fixture_static_parity`、`fixture_full_parity`、额外物理显示器切换或已部署。

prepared-DIB dirty worktree 预检 run `3b6e9aa8d0574a80a1f91bce82941513` 与中间 clean F 的 B0-05 都只保留为历史诊断，已被最终 source merge `40853287e7ed04714d68935c0002f8ad6d8aea05` 的 clean B0-05 32/32（run `c42d755dfa294ea5898366c7870e6ab8`）、clean B0-06 48/48（run `ed61d7275fdd4a96a73f762c5c2a4d71`）和完整回归 **1747 通过 + 3 个 opt-in 跳过 / 1750 总计**取代；旧诊断不得继续充当 current evidence。

2026-07-17 末轮调制交互收口：强化石核心统一承载持有、preview 消耗与强化后剩余，放大持有量并将强化 footer 收敛为单一动态 CTA；交换目录只显示同 `use` 且与 source 强化度不同的装备，无候选时给出明确空态。AS2 的同强化度 no-op 校验仍保留，用于防御 projection 后的状态变化。

`Launcher.Tests.csproj` 采用 SDK glob 自动纳入测试源码；上游 `9f4669e` 的 **960/960** 与 2026-07-28 B0-05/上游合并树的 **1651 通过 + 1 opt-in 跳过 / 1652 总计**只作历史基线。clean B0-06 v1 实现基线的 focused 筛选（完整 PlayerInfo 命名空间 + `PanelHostHudCompanionTests`）为 **136 通过 + 3 个专用 opt-in 跳过 / 139 总计**，无并发负载完整 `launcher/tests/run_tests.ps1` 为 **1737 通过 + 3 个 opt-in 跳过 / 1740 总计**；两者均只证明旧 v1。最终 main-space v2 source merge `40853287e7ed04714d68935c0002f8ad6d8aea05` 的 focused（再含 union/topology）为 **180 通过 + 3 个专用 opt-in 跳过 / 183 总计**，同源 clean 完整回归为 **1747 通过 + 3 个 opt-in 跳过 / 1750 总计**。Runtime Lane C 独立为 **11/11**、exit 0、scalar assertions **566**；guardrails 另列为 `scripts=3 / unsafeCandidateCases=3`，不得混算为 577 项同质断言。dirty/并发负载态曾在 Loot、Skill、GameLaunch、CharacterBuild 等既有 wall-clock tests 暴露时序失败；其中一项 Skill 隔离 20 次为 13 pass / 7 fail。随后 clean official full 通过只证明上述 clean run，不证明这些时序敏感性已消失，也未据此修改 PlayerInfo 生产代码。`ShopTaskTests` 继续覆盖 KShop `checkoutPreview/checkoutCommit` 映射、只读预览成功载荷校验、commit 写 gate、对账与防重放，并守 legacy checkout/claim；成功 `checkoutCommit/claim` 缺少写后 `catalog` 必须进入 `reconcile_required`，不能把旧动态上限当作定局。`InventoryTaskTests` 除 lease-bound `tooltip`、三容器 source/target、结构化 `filterSpec`、`sortAndMerge` / `autoTransfer` 白名单外，新增 loot organizer 七键 envelope：只接受 `panel=loot`、exact active `panelInstanceId` 与 `snapshot/autoTransfer/discard` 三条命令；`autoTransfer` 仅允许背包↔战备箱，`discard` 仅允许背包，并断言成功、本地拒绝、timeout 与发送失败都回显原 panel/instance binding。`AgentControlTaskTests` 覆盖非 legacy 同包 `s:1|ga:<attemptId>`、裸/缺失/stale attempt 拒绝、`gameEnteredAttemptId` 投影、`start` 清锁，以及实收 `s:0` 时的防御性清锁；后者只是实现回归，不表示现役正常退出已调用该信号。`NpcShopTaskTests`、`CraftingTaskTests`、`HairdresserTaskTests`、`SkillTaskTests`、Router/WebOverlay 与 `LauncherCommandRouterTests` 继续守各自 payload、写门、实例和失败分类契约；Crafting 另覆盖 `view=materials` 路由、`materials/materialDetail` payload 与权威成功回包校验。Character Build ↔ Skills 另以 exact `openRequestId`、manage-only/no-trainer、atomic consume、late trainer cleanup、双 settled gate、bounded rollback、lifecycle latest-intent-wins 与 deferred open race 固定边界。Hairdresser 继续固定第三个共享 pending consumer、close 清理、未知 commit 后 fresh snapshot applied/not-applied 收敛及零 replay。`SaveMigratorTests` 继续使用代码内 helper 数据，外部 fixture 目前主要集中在 `Fixtures/MapHud/`。

上述 2026-07-28 历史树的 **1651 通过 + 1 opt-in 跳过 / 1652 总计** 包含双向返回、原生 workbench nonce、材料直达路由与 Host 竞态补强：reserved instance 后 init enrichment、Character/Notch/trainer 三来源能力隔离、strict `navigate_character_build`、普通 `×`/Esc/backdrop、Skill visual 与 coordinator 两门乱序恰好一次、idle close 无 callback、native workbench nonce 与迟到 A/正确 B、reload/disconnect/shutdown/competition cancellation、preflight/admission/consumed Host rejection 的一次前向 rollback 或一次 toast、旧 timeout 不越过更新 intent、反向失败不复活 Skills、open false 不记 success，以及返回后的稳定焦点 key。通用 Panel runtime 同树为 **27/27**，覆盖 initial/lazy registry、create/append/onOpen/onRebind、same-active pending replacement、lazy sync/non-thenable/rejection、cleanup 与 Bridge 异常的 exact-owner fail-close。它们仍只是源码/自动门，不等于 candidate 或部署。

上述 **1720/1720** 在既有双向返回、原生 workbench nonce、材料直达和 Host 竞态矩阵之外，还覆盖 B1 preparation frozen tuple/off-on HUD 几何与 progression reason、B2 native tuning nonce/admission、B7 Build-only strict bool 注入/省略、Skills return 与三目标 rollback 的 on/off focus、WebOverlay recovery payload 和 Program 同 gate 接线，以及单一 RightContext slot owner 的优先级、owner 切换、像素与命中排他。通用 Panel runtime 最近同树证据为 **27/27**，覆盖 initial/lazy registry、create/append/onOpen/onRebind、same-active pending replacement、lazy sync/non-thenable/rejection、cleanup 与 Bridge 异常的 exact-owner fail-close。它们仍只是源码/自动门，不等于 candidate 或部署。

冻结 source `9118eb5097ab073d26a9806138f9fabf28e3ca79` 的最终汇总覆盖并取代“当前树=1720/1729/831”的旧口径：Host H1 定向历史门为 **253/253**，Launcher 全量最终 fresh 为 **1902 pass + 3 explicit opt-in skip / 1905**、0 fail；首次全量曾暴露既有 SkillTask 20ms wall-clock flake，隔离 5 次均绿后仅把测试 timeout 调至 250ms，确定性 timeout 负例仍在。B0-05/B0-06 formal 与 B0-06 visual capture 保持 explicit opt-in skip；只完成 qualification contract `3/3`、runner parser `0 error` 与失败 envelope/affinity AST 纯内存门。F2 的 `48/48 / b0_accepted` 只属其专项 base closure；较新的右槽 workload 已进入冻结树，但不冒充 PlayerInfo formal qualification。Crafting 三视口 **119/119**、Intelligence **30/30**、Equipment Tuning 三视口各 **115/115**（model **61/61**、runtime **25/25**、confirmation **4/4**、interaction **7/7**、source-marker leaf **2/2**）、Character standalone 三视口各 **218/218**、workbench **867/867 + 12/12 + 18/18**、inventory modules **31/31**、dressup **222/222**、preparation leaf **10/10**、KShop **135/135**、item-grid matrix **20/20**、ratchet **66/66**，default/release-tree strict UI audit 均为 **0 error / 0 warning**。冻结树最终 Flash focused run 分别为 Tuning `a6f2a1abb3dd44189e9cd1ab4583490b`（**55/55 + 144/144**）、Character `a5d8512263894ded9540aedec991c643`（**539/539**）与 Item Panels `49b52f058b4046bdba5dcafffd6bb50f`（**28/28 + 46/46 + 144/144 + 36/36**）；三轮均为 fresh trace/output/errors、Compiler **0/0**、32K retry **0**。随后只对 `scripts/asLoader/asLoader.xfl` 执行 `-Target publish`，产物为 **1,065,911 bytes**、SHA-256 `BAB9E46D140739F753262264DB326039432552783E87CC184DE8C423AD084CAB`、9,723 functions、最大 46,025B；没有编 main，publish 不出 fresh trace，行为仍由上述 TestLoader 证明。上段 1720、PlayerInfo 1740 与后文各批次数字仍保留为历史/局部快照。该源码已随本轮 runtime 发布，但自动门不能外推成所有功能已在 promoted identity 下完成实机 E2E；本轮标准入口仅验证 Equipment Tuning opener 到同实例首个权威 snapshot 的只读纵切。

装备调制接入增加 `EquipmentTuningTaskTests`、AgentControl 安全门和 Router/WebOverlay 实例路由回归。它固定七键 envelope `{type,panel,domain,cmd,callId,panelInstanceId,payload}`，覆盖 snapshot/preview/commit/tooltip/detach、七类 operation 白名单、一次性 token、write epoch、发送失败/timeout/迟到、断连与切离 session 撤销、强制关闭后的 exact reconcile hint，以及 battlebox、Character Build 嵌入态、legacy redirect `migration_paused`、agent source 和 warehouse 隔离。协议没有 `tuningAvailable` feature flag；UI 固定“强化度 / 交换 / 进阶 / 配件”、永久 `+13`、按 source `majorType+use` 的只读交换候选、安全/快速边界、分段富注释和 `48/40/4px` 紧凑格。一个持久化完整/紧凑控件在 storage、构筑候选与 embedded tuning 标题间迁移；调制 compact 只作用材料、配件、转换候选等浏览型卡片，operation tabs 与主提交语义保持完整，切换零业务流量。commit 的 busy/write capability 必须覆盖 inventory refresh 整段，并等待新 lease 后才开放下一交互。当前自动命令和证据口径统一见 [验证矩阵](../agentsDoc/testing-guide.md)；本文不再复制已失效的 per-viewport case 数、Host 全量数或旧 asLoader 哈希。

本轮 A2b 已把 Tuning detail 与固定 CommitBar 分离；独立和嵌入态共享“逐次确认 / 单件快捷”，preview 重绘保持 DOM/draft/focus/scroll identity，inventory/loadout authority source 常驻可见，`readPending / busy / reconcile / detaching / retry` 对 tabs、tier、input/stepper/range/marks/cap 与 CTA 使用同一锁投影。`projectLoadout` 锁按 owner 保存并只恢复自身接管节点的 base/original `disabled` 与 `aria-disabled`，不得误解锁 drug/empty/blocked 或原生 disabled；number/range/mark/stepper/cap 发起强化 preview 时保持发起控件焦点，只有候选/交换 preview 才允许把 CommitBar 带入可见范围并迁移语义焦点。confirmation wrapper 是有名称的 `role="group"`，`aria-disabled` 只下沉真实控件族，不写到 generic section。ChoiceGroup reject/throw 回滚 pressed 状态，阻断原因不随 disabled CTA 一起淡化。这是现役 feature-local 收口，不代表 Character Build candidate tuning 的 ADR C 纵切已经完成。

冻结 source `9118eb…` 已收紧三项玩家合同：“单件快捷”只省略符合白名单的 install/replace/detach 的一次人工确认，仍完整经过 AS2 preview、opaque token、source lease、revision、写入单飞与未知结果 reconcile；batch/cascade/remove-all 进入现有 CommitBar，恰好一次显式确认，不叠第二模态。插件容量只消费当前 `snapshot.equipment.modSlotCapacity` 与同一 snapshot 的 `snapshot.equipment.mods`；物品格 presentation projection 的 `modSlots[]` 是另一字段，不得混写。capacity 仅接受 `0..64` 的有限整数且 installed≤capacity；展示安全上限只防异常快照制造无界 DOM，不是本地三槽业务规则。`0` 明示无插件槽，字段缺失不猜，负数/小数/Infinity/installed 超限/容量超限等畸形值明示容量未知。顶部是持久快捷总览，进阶、已装插件和空插件槽均可点击进入对应 tab/候选；配件页按同一 capacity 提供大尺寸替换、单拆与空槽安装入口，两处空槽点击都只导航且不提前 preview/commit。空槽序号不是可提交的物理槽号，任一空位目前都是等价安装入口，最终位置由 AS2 决定。真实剑圣腿甲按 `1 个进阶 + 3 个插件` 呈现；`1/3 + 2` 个空插件槽演示剩余容量，4+ synthetic fixture 只证明 Web 无三槽硬编码。summary / operation focus key 按 surface + 槽序号唯一化，详细槽重渲不得把焦点跳回顶部。“卸下全部”位于独立批量操作 group，不得伪装成额外插件槽。调制源改用 12×12 source-port glyph，并同时保留 `aria-current` 与“当前调制装备 / 用于交换”的完整 accessible name，不再用粗重文字贴纸占据物品格。这些字节已进入正式 runtime；本轮实机只读纵切停在首个权威 snapshot，未点击槽位或发送 preview/commit，不能把上述写入合同标成已由本轮 standard-entry smoke 运行。

B2 已接通 `EQUIPMENT_TUNING` 的 exact production contract：Router 只发 `openInventoryWorkbench` 的 `{profile:"battlebox",view:"tuning",source:"nativehud_equipment_tuning",openRequestId:<opaque tuning.open.*>}`；AS2 只回显并由 Host 只消费 exact 五个顶层键 `{task:"panel_request",panel:"workbench",source:"nativehud_equipment_tuning",initData:{profile:"battlebox",view:"tuning"},openRequestId}`，其中 `initData` 恰好两键。任何携 exact source 或 `tuning.open.*` token 的形似请求都必须先进入 tuning validator，missing/extra/wrong-layer/near-shape 不得回落 ordinary workbench open。Host 绑定 generation、baseline、admission、lifecycle 与一次消费，缺失、近似、迟到、重复、active/pending 竞争请求全部 fail closed。成功态是 standalone workbench tuning，不带 `returnTo`；与 battlebox storage 同实例本地切换，普通 Close/Esc 回游戏。legacy `legacy_equipment_tuning` 仍保留原生 renderer。B7 现只把这个既有 exact handler 投影到默认 on 的“整备”入口，没有修改 nonce、admission 或 route authorization。

B4 fixed post-close 基座当批的 fresh 自动门为：Launcher 定向 `381/381`、全量 `1681/1681`；inventory workbench modules `26/26`；Character standalone `215/215`、production workbench `768/768` 加 hidden-body `4/4`；Panel runtime `27/27`、contracts `62/62`。这组历史断言覆盖三 reason 封闭 parser/当时仅 Skills enable、exact instance、arm 与 target timer 分离、settled race、lifecycle/competition/late callback、once rollback 和 focus 双值 parser；它不替代后续 B5–B7 的当前证据。

B5 Materials exact handoff 的 fresh 自动门为：Launcher 定向 `249/249`、全量 `1707/1707`；tracked item-panel run `bec9c608004d48e0bcb18a7f1c0f5708` 为 EquipmentInventory `28/28`、NPC `46/46`、Inventory `144/144`、Crafting `36/36`，Compiler Errors/Warnings `0/0`、32K retry `0`。direct HUD 与 Character settled 都先建立独立 material wait，再发送 Host opaque `openRequestId`；只消费 AS2 顶层 exact echo 与 Host admission。missing nonce 在 armed/wait 存在时拒绝但保留 wait，nonce-bearing wrong/near-match 终止当前目标，迟到/重复零打开；Character 退场后失败至多一次 rollback。本批只刷新 TestLoader，未 publish `scripts/asLoader.swf`，也未构建 candidate 或部署。

B6 Intelligence exact handoff 已在固定三目标 switch 内启用。Character exact coordinator settled 后，Router 在同一 lifecycle fence 内销毁 arm/timer、捕获 Host exact idle admission，并只用内部构造的 `{mode:"prod",source:"runtime",debug:false}` 同步打开 `intelligence`；Web 不提供 panel/initData，该分支不发送 AS2 nonce、不建立 target timer，也不进入 Skill/Material `FixedPanelOpenWait`。admission/open false 或 exception 在退场后至多触发一次 Character rollback；rollback 也不可准入时停在游戏并提示从装备入口重试。competing intent/panel、epoch、navigation/热重载、socket/shutdown 与迟到/重复 settled 都不能重开；Host 已接受的 open 不因后续 `webPanelPause` false/throw 反转。

B6 fresh 自动门为：Launcher 定向 `257/257`、全量 `1715/1715`；inventory workbench modules `26/26`；Character standalone `215/215`、production workbench `786/786` 加 hidden-body `5/5`；Panel runtime `27/27`、contracts 4 domains / 23 commands。该批未修改 AS2/Flash，故未运行 CS6、未刷新 TestLoader、未 publish `asLoader.swf`；也未构建 candidate、执行游戏 E2E、promotion、部署或标准入口验收。

B7 已把 `PreparationNavigationV1` 的代码默认与随仓配置切为 `true`，并以同一值接线 Native/legacy HUD、Router、WebOverlay recovery 与 Build Web initData。on 时 Build exact-set 为 `preparation-menu | stats | help | close`，Skills return 与三目标 rollback 聚焦 `preparation-menu`；显式 `false`（或配置项存在但值非法）会整体恢复旧 HUD/header 与 `skills` focus。Web 只接受严格 optional bool 与固定六项映射，错误类型或 gate/focus 不配对直接拒绝，gate 不参与 route authorization。带 reason 的 Build busy header action 保持 `aria-disabled` 与真实激活解释路径，保留基线 accessible name、把生产 capture 先读取的 cue 切为 `error`，显示对应动作 reason（Close 明示完成后才能关闭工作台）后阻止原 handler并在恢复时还原；无 reason 才使用原生 `disabled`。standalone tuning 的兄弟切换统一写“战备箱与背包”，不臆造“返回收纳”历史。fresh 自动门为 preparation leaf `10/10`、inventory modules `27/27`、Character production 三视口合计 `831/831` + hidden/lifecycle `12/12` + normal/reduced 菜单矩阵 `18/18`、Tuning 三视口 `96/96`、KShop `134/134`、Launcher focused `237/237` 与全量 `1720/1720`；busy action 使用真实 Edge 内 DOM `.click()`，不冒充 trusted pointer/Enter/Space。这是 B7 当批 promotion 前的历史快照：当批未修改 `.as`/Flash/SWF，也未构建 candidate、执行游戏 E2E、promotion、部署或标准入口验收；实现字节后来随 `9118eb…` 正式部署，但本轮 formal smoke 仍未执行 B7/Character 游戏旅程或显式 off 回退。

合成工作台生产接入为独立 `crafting` domain：配方使用 `snapshot/preview/tooltip/commit`，材料目录使用只读 `materials/materialDetail`，Flash 统一回 `crafting_response`。`LauncherCommandRouter` 对配方只接受 12 个已知分类并重建 `{mode:"runtime",category,source,debug:false}`；Native HUD `MATERIALS` 只在 exact correlated admission 后重建 `{mode:"runtime",view:"materials",source:"nativehud_materials",debug:false}`，不再打开旧 material-only 页面且没有 fallback。`CraftingTask` 只接受分类、recipeIndex、严格整数 `craftCount=1..99`、itemName 或 opaque `expectedCraftToken`，不透传 Web 价格/材料/产物。snapshot 为每条配方执行一次 `craftCount=1` 权威计划，返回严格配对的 `canCraftOne/availability`，不运行 `maxCraftCount` 二分；Web 用它显示卡片状态、可合成计数和本地“只看可合成”，但提交仍只信 preview/token。Flash 只对堆叠产物且无装备素材的配方开放批量，返回 `batchEligible/maxCraftCount`，并把份数、总材料、总产出和双货币总价绑定进一次性 token；装备产物/装备素材仍固定单份。材料目录由 `crafting-materials.js` 消费 `ItemUtil.materialDict`、材料注释、`ItemObtainIndex` 与 `SynthesisIndex` 的 AS2 投影，展示持有量、怪物/关卡来源和配方/装备用途，Web 不扫描 XML 或推断掉率；视图固定为 `44:56` 真双栏档案，目录和详情独立滚动，选择按稳定材料 key 原位更新。Web 将每次成功 preview 保存为同 category/recipeIndex/craftCount 的 checkpoint；普通读 timeout/disconnected/畸形恢复 checkpoint，权威分歧刷新 snapshot。只有 AS2 明示 reconcile，或已投递 commit 的超时、断线、drop/畸形结果进入 `needs_reconcile`；同步未投递失败保持可操作，此后受门控写入返回 `reconcile_required`；只有同配方结构完整的成功 preview 能解除写门，snapshot 不能。配方入口为 `modules/crafting.js`，复用 `Workbench.DualPaneShell` 与共享 `ItemFilter catalog` 类别/套装视觉契约，生产 `#panel-content` 使用全 anchor、1024×576 scale-shell 等比铺满，内部以约 60:40 双栏和窄轨原生滚动呈现；材料不足时先 snapshot 撤销 token，再本地切入 `workbench profile=battlebox`，返回仅保留 category/recipeIndex/craftCount 及展示筛选意图并强制重新核算。无头验证入口为 `node tools/run-crafting-harness.js`，当前三视口均 119/119，并覆盖材料直达/目录/详情/来源用途、223 条 fixture 的目录可达性、重复重建、跨面板路由后 `ResizeObserver` 全量断连与检视器 RAF 生命周期、普通武器动效、双刀/疾影 strict 2/2 holder 组合、battle rig 漂移整组回退，以及纸娃娃图片加载失败图标回退，并固定证明内部模态/二级页先消费 Esc、普通 `×`/Esc/backdrop 最终只关闭 exact crafting owner。

这里的合成“整理背包”是纯 Web 子路由：Host 始终只看到并持有 exact `crafting` owner、原 `panelInstanceId` 与同一 pause lease，不得另发 `panel=workbench` open。只有显式“返回合成”恢复原合成 DOM/浏览意图；普通关闭、Host close、lazy dependency 失败或 workbench mount 失败均关闭 crafting owner，不隐式恢复。合成 token 在切入前撤销，整理所用 inventory lease 与合成写 token 不共享。独立 workbench 则必须由 Host 分配有效 `panelInstanceId`，不得借该子路由接受无实例挂载。

装备检视器的离线全量人工验收入口为 `node tools/build-equipment-inspector-review.js` → `node tools/test-equipment-inspector-review.js` → `node tools/open-equipment-inspector-review.js --check`，人类再用不带 `--check` 的 opener 开始裁决。当前批次保留 1197 条原始定义与 3 组重名，生成 2844 个逻辑候选、1749 个 required 分支；其中 543 个武器商品图、男女各 552 个防具聚焦、102 个图标回退，另固定 9 双刀、9 疾影和 33 个 production live 动效硬门。决定绑定实际素材字节的 `sourceDigest`、候选产物/构图证据的 `reviewDigest` 与 2946 个落盘文件哈希；静态首帧或仅打开 live 窗口都不能代替显式 `motionReviewed`。`tmp/equipment-inspector-review/` 与人类导出只作 QA 证据，不改变生产 resolver。

产物详情原 68px 图标继续承担快速识别，点击后由 `modules/crafting-inspector.js` 打开只读特写 modal。snapshot 顶层 `gender` 来自 `_root.性别`，AS2 只把精确“女”保留为女，其余规范为男；Host 仍严格要求 wire 只能是“男/女”。运行态同时严格区分 `name`（物品与 dressup manifest 身份键）、`displayName`（展示文案；XML 源字段为 `displayname`）和 `icon`（Icons 资产键），避免牙狼等改名物品误判。三路策略固定为：普通武器直接绘制完整装备 skin、不带人体；刀类 `actionType=双刀` 用 battle `兵器站立` 的真实矩阵同时绘制 `刀_装扮 + 刀2_装扮`，`actionType=疾影` 同时绘制 `刀_装扮 + 刀3_装扮`，两个 holder 即使共用 skinKey 也不去重，普通刀不能仅因带 `刀2_装扮` 被误判。复合状态使用 strict fields，运行时结果必须为精确 2/2 holder 且无 missing/failed image；缺任一部件或 battle rig 漂移都整组回退当前图标。防具只取当前存档性别的装备 fields 聚焦，头部可带脸型承托，上装不补手、下装不补脚、手套不补前臂、鞋不补腿；其他、dressup 缺失或当前性别分支缺失回退当前图标，绝不跨性别借分支，图标也缺时显式缺图。窗口默认 185% 特写，支持拖拽、滚轮、方向键/按钮平移、缩放键、全貌、重置特写及纸娃娃父/嵌套动画及当前动态图标静态首帧暂停继续；同一时刻只保留一个 live Canvas renderer，关闭 modal 或切 panel 必须销毁 renderer、RAF 和监听器。

| 分组 | 覆盖面 |
|------|--------|
| `Bus/` | MessageRouter 当前观察行为、XMLSocket read loop 边界 |
| `Tasks/` | StageSelectTask、IconBakeTask、ArchiveTask list/filter 行为 |
| `Save/` | Protocol 2 决议、SOL 定位、legacy 首导入、版本 gate、repair policy / backup / auto-repair |
| `Guardian/` | overlay 坐标、DPI、FlashSnapshot、PanelHost/Router、InputShield telemetry、Native HUD bounds、UiData parsing、RightContext/MapHud/SafeExit/Combo/Toast/Notch/widget scaling |
| `<root>` | 基建冒烟 |

### Web QA 与开发 harness

本节回归以 `b072f97841ccb30e167c14495241ae64d9054e22` 为 upstream base，并覆盖 source commit `c60aab2386aee4516608397373ae4c59148c5f77` 的工作台合并结果；该 source 已由 commit `6218f8b1d82efc57b77131616667fe45f3033297` 完成 runtime promotion。未重跑计数按上游基线或待复验标注。

小游戏测试不走 `launcher/tests/`，地图 panel 的 DOM / 布局 / 交互回归也不走 C# 单测；统一按各模块自带的 QA 入口执行：

- **双栏工作台治理门**：`node tools/audit-workbench-ui.js --strict-warnings` 做结构化静态审计；`node tools/run-workbench-visual-atlas.js --strict-warnings [--shot-dir=tmp/workbench-visual-atlas]` 跑 `1024×576 / 1366×768 / 1920×1080 × full/compact × focus × reduced-motion × secondary page` 的 48 场景合同。视觉与工程规则见 [workbench-ui-system.md](../agentsDoc/workbench-ui-system.md)，它不替代各 feature harness 或游戏内手测。当前基线：静态审计 `0 error / 0 warning`、atlas `48/48`、物品格矩阵 `20/20`。
- **Node QA**：`node tools/run-minigame-qa.js --game lockbox|pinalign|gobang|all`
  - 实际入口文件：`tools/run-minigame-qa.js`
  - 共享 runner：`web/modules/minigames/shared/dev/node-qa-runner.js`
  - 适用场景：纯逻辑、确定性、导出结构、回归脚本
- **Browser harness**：直接打开各自 `dev/harness.html`
  - `web/modules/minigames/lockbox/dev/harness.html`
  - `web/modules/minigames/pinalign/dev/harness.html`
  - `web/modules/minigames/gobang/dev/harness.html`
  - `web/modules/map/dev/harness.html`（也可用 `node tools/run-map-harness-headless.js --browser edge` 跑 `map-ui1`~`map-ui33`，或 `node web/modules/map/dev/screenshot.js` 出红点 / 选关视觉回归截图到 `tmp/map-red-dot-shots/`）
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
  - 运行时图标入口约束：`Icons.resolve()` 是首帧 fallback，不作为用户可见物品/装备/奖励/tooltip 的默认渲染入口；生产格子与富 tooltip 统一走 `Icons.html()` / `PanelTooltip.dynamicIconHtml()`，并由 `node tools/audit-web-icon-render-entrypoints.js` 审计防回退。
  - 图标与纸娃娃共享导出端时间线工具：`tools/asset_timeline_export.py` 统一处理 digest 去重、`duplicateOfFrame` 与连续 hold 压缩。图标压缩默认按 `uri` 判断连续显示一致；纸娃娃调用时必须把 `uri/width/height/originX/originY` 作为 identity key，避免同图不同注册点被错误合并。基础回归：`python tools/test-asset-timeline-export.py`；父级首帧 `stop();` 但第一帧内子 MovieClip 仍自播放的语义回归：`python tools/test-nested-animation-stop-semantics.py`。
  - 图标分层运行时验证：`node tools/test-icons-layered-periods.js` 用合成 5 帧 / 7 帧子层覆盖 `Icons.html()` + `Icons.enhance()`，确认 wrapper/layers 结构正确、静态图标不误分层、子层按各自周期独立选帧，同一 URI 但 crop 位置变化也会继续播放，frame budget 是 12 而不是 35；`python tools/test-icon-animation-candidate-filter.py` 验证候选 report 预过滤、策略过滤和源帧数预算；`python tools/test-icon-animated-budget.py` 验证 animated entry 递归文件统计、超预算静态回退、视觉静态降级与不再引用文件清理。
  - 2026-06-18 动图候选基线：`tmp/icon-animation-candidates-status-all.json` 覆盖 `animationStructureCandidates` 14 个候选；在 `--max-animated-icon-bytes 1500000` 下，`金钱` / `K点` 已进入生产 manifest（32 逻辑帧分别压缩为 5 / 12 张 PNG，合计约 524KB），`强化石` / `冰魄矿石` / `月之碎片` 可导出但单图标约 8.0~8.8MB，按预算降级静态，`战术耳机加遮阳帽` 为视觉静态降级，其余 8 个因 stripped base 非空或首帧 diff 过大保守静态。
  - 2026-06-18 覆盖率基线：派生目标 1611，`--resolve-only` 可解析 1512、unresolved 99（88 个 `missing_asset`、11 个 `conflict`）；旧版完整 FFDec 写入曾改写 2354 个 tracked PNG 并造成布局回归，已改为默认保护既有布局。
- **Dressup paper-doll offline（data + XFL rig）**：`python tools/bake-dressup-offline.py --export-assets`
  - 从 `data/items/*.xml` 按 `DressupInitializer.updateDressupKeys` 的性别前缀 / 肢体后缀 / 武器字段规则展开装扮 key，并用 `data/items/asset_source_map.xml` 标注每个 skin key 的 SWF / symbol 来源，输出 `launcher/web/assets/dressup/manifest.json` 与缺口报告 `report.json`。
  - 同时解析 `flashswf/UI/对话框界面/LIBRARY/对话框肖像.xml`、`对话框UI/对话-主角模板.xml` 与 `sprite/主角/*`，抽取男/女 `man` pose、holder `attachMovie(_parent._parent._parent.<字段>, "装扮", ...)`、矩阵、fallback 基本款行为，供 `web/modules/dressup-doll-renderer.js` 在 Web 端 Canvas 复刻对话框主角纸娃娃；dialogue holder 按 XFL `DOMLayer` bottom-to-top 输出以匹配 Flash 视觉栈，身体 holder 的 attach 失败会回到 XFL `基本款`，武器 holder 无装扮时保持隐藏。manifest 还写入 `appearance.faceById/hairById`，用于 Web 端把原始脸型/发型编号归一化为 skinKey。2026-06-18 起 manifest 还写入 `rigs.battle`：解析 `flashswf/arts/things0/LIBRARY/主角-男.xml` 的 `空手站立`、`长枪站立`、`手枪站立`、`手枪2站立`、`双枪站立`、`兵器站立`、`手雷站立`，按每个 `DOMLayer` 的 active keyframe 合成战斗 holder，并识别 `_root.装备引用配置.配置装扮(...)` 的字段/引用名；男女 `手雷站立` 各包含一个真实 `手雷_装扮` holder，不再借空手姿态兼容。`dressup-doll-renderer` 可通过 `initData.rig="battle"` + `initData.stateLabel` 切到战斗姿态。`test-dressup-manifest-integrity.py` 会检查 battle rig 状态、矩阵和必需 holder 字段闭包。
  - 换皮/重绘的确定性整套参考图可用 `node tools/run-dressup-harness.js --browser edge --init-file <preset.json> --canvas-shot <transparent.png>`；preset 支持 `gender/rig/stateLabel/equipment/captureTimeMs`，也可用重复 `--equip 槽位=物品名` 临时覆盖，`--freeze-ms` 固定动画采样时刻。固定时钟时 runner 会等待当前图片请求收口，并检查装备回填、`missing=0`、目标 rig/state 与非空 Canvas；`--canvas-shot` 保存原始透明 Canvas，不带 harness CSS 背景。逐件换皮审计可额外传 `--skin-override-file <json>`，将 JSON 中的 `skins/<文件名> -> 仓库内预览 PNG` 仅在 Playwright 请求层替换；runner 会报告每个 override 的命中次数并拒绝未请求的映射，不修改正式 manifest/skin。批量 retarget、六姿态捕获与 alpha 差异板统一走 `python tools/monster-reskin-pipeline/audit_dressup_reskin.py`；该独立 12-skin/15-holder 换皮门尚未扩为 Character Build 的七姿态，不得从 manifest 的新增 `手雷站立` 外推。钛合金61整套示例与“整图冻结设计、原 skin PNG 约束逐件重绘、禁止从遮挡整图机械切件”的边界见 [monster-reskin-pipeline README](../tools/monster-reskin-pipeline/README.md) 和 [titanium-61-dressup.json](../tools/monster-reskin-pipeline/examples/titanium-61-dressup.json)。
  - `--export-assets` 用 FFDec `symbolClass` / `sprite:png` 导出真实 dressup PNG 帧到 `launcher/web/assets/dressup/skins/`，并用同批 `sprite:svg` 读取每帧相对 Flash 注册点的 `originX/originY`，写回 `skinKeys[*].export + frames[]`；同轮还从对话框 SWF 导出 22 个男女基础身体件并写入 `rig.genders[*].holders[*].basic`。默认 `--zoom 2 --fps 24`，前端按 metadata 缩回 Flash 坐标、按 `originX/originY` 负偏移绘制并播放 PNG frame sequence，避免 zoom 10 造成过大资源。导出阶段还会用 FFDec `script:as` 读取父 sprite 时间轴脚本，并用 `swf2xml` 建 sprite 子图；多帧素材若 `frame_1/DoAction.as` 是纯 `stop();` 且没有自播放后代，按 Flash 首帧停止行为折叠为 `playback=static-first-frame` 的单帧 PNG，避免变形动画在 Web 纸娃娃里无脚本循环播放。若父级停在第一帧但第一帧内存在自播放子 MovieClip，则写为 `playback=nested-animation` 或 `playback=static-parent-nested-animation`；可静态定位的 child 场景会经 `xml2swf` 临时生成 stripped base，把子层从父级/父层对应显示列表移除，再在递归 `nestedAnimation.layers[]` 写入子 sprite 帧序列、Flash 矩阵和 `drawOrder`，由 Web renderer 独立推进子层，避免按周期最小公倍数全量合成；父动画后续帧才挂出的子 MovieClip 若会随父循环重建，则保留在父层帧序列里并计入 `compositedDescendantCount`。带 `onClipEvent(load)` 的条件显示层若脚本语义为 `攻击模式` 命中时 `_visible=1`、否则 `_visible=0`，导出器会用 `xml2swf` 生成 `runtimeVariants.neutral`，并在 `conditionalVisibility` 记录可见攻击模式，renderer 在非手枪/双枪攻击态使用 neutral 变体，避免中立纸娃娃把攻击光束烘进静态 PNG。重复像素帧不再复制 PNG，`frames[]` 保留完整逻辑播放帧并用相同 `uri` + `duplicateOfFrame` 复用文件；连续重复显示帧另写 `timelineFrames[]` + `durationFrames` 压缩运行时时间线，renderer 通过 `AssetTimeline` 优先按该时间线播放，避免类似 80 帧素材后段 50 帧静态 hold 造成 manifest 与运行时遍历浪费；增量导出可用重复 `--name` 或 `--limit`，工具会保留既有未选中 skin key 的 `export/frames/timelineFrames/runtimeVariants/conditionalVisibility`，`report.assetExport.exportedSkinKeys` 只表示本次写入数量，`preservedSkinKeyExports` 表示保留的旧导出条目；若只需规范化既有 PNG/manifest 而不重跑 FFDec，可用 `python tools/normalize-dressup-timelines.py` 补齐同一套 `timelineFrames[] + durationFrames`。`python tools/test-nested-animation-stop-semantics.py` 固定验证父级首帧 `stop();` 只冻结父时间线，第一帧内未停止的多帧子 MovieClip 仍保留为 nested animation；`node tools/test-dressup-renderer-periods.js` 用合成 5 帧/7 帧子层确认 renderer 按层独立选帧且消耗压缩时间轴，frame budget 是 12 而不是 35；`python tools/test-dressup-manifest-integrity.py` 检查真实 manifest 资源闭包、origin/matrix、压缩时间轴、`攻击模式` runtime variant 和 A 兵团背心“父级 1 帧 + 子层动效”样本；`python tools/test-merc-dressup-coverage.py` 检查全量佣兵装备、脸型、发型到 manifest 的运行时闭包。2026-06-19 当时的兼容策略不允许 holder `基本款` 回退；下列数字只作历史基线，不代表现役策略：覆盖 2840/2840 个 skin key，其中 2820 个 skin key 已带 export；150 个 skin key 通过 compat alias 覆盖（manual=15、auto_opposite_gender=135）；父级逻辑帧 2935、nested layer 逻辑帧 700、基础身体件 22 帧、唯一 PNG 引用 3271、重复帧引用 387、timeline 压缩帧引用 350；真实父时间线循环 16、首帧 stop 折叠 20、nested animation 24，其中 27 个 layer 已可运行时播放、6 个 descendant 由父层帧序列覆盖，`nestedLayerUnsupportedDescendants=0`；`枪-手枪-极品UZI战术版` 已有 1 个 `runtimeVariants.neutral`，由 `conditionalVariantRemovedPlaceObjects=1` 生成；全量 204 名佣兵的 1499 件可渲染装备闭包通过，3265 个部件命中 export，0 个部件回退 holder 基本款；A 兵团精致战术背心身体的父层固定为 1 帧，飘带子层 18 个逻辑帧压缩为 6 个 `durationFrames=3` 的播放段。renderer harness：`web/modules/dressup/dev/harness.html`；生产 Panel harness：`web/modules/dressup/dev/panel-harness.html`；无头验证：`node tools/test-asset-timeline.js`、`python tools/test-asset-timeline-export.py`、`python tools/test-nested-animation-stop-semantics.py`、`python tools/test-dressup-manifest-integrity.py`、`python tools/test-merc-dressup-coverage.py`、`node tools/test-dressup-renderer-periods.js`、`node tools/run-dressup-harness.js --browser edge --sample animated`、`--sample nested`、`--sample nested-a`，以及精确 skinKey 回归 `node tools/run-dressup-harness.js --browser edge --skin-key "男变装-A兵团精致战术背心身体" --gender 男 --field 身体`。
  - `report.missingSourceAudit` 是剩余缺口的来源审计：按当前 `asset_source_map.xml` 与同名 XFL/XML 扫描分类缺失 skin key，并在 `entries[*].references` 反查产生该 key 的 item、性别字段、数据文件、佣兵装备引用数量和样本。现役离线策略明确禁用 `auto_opposite_gender`：只存在异性素材的 key 保持 `covered=false`，renderer 由当前性别 holder 的 `basic` fallback 承接，不把异性身体/肢体伪装成精确覆盖；经人工确认可共用的 alias 仍可写入 `COMPAT_DRESSUP_ALIASES`，但每项必须保留显式 `reason`。上行 2026-06-19 数字只作历史快照，现役 manifest/report 基线为 items `1288`、skinKeys `2843`、covered `2702`、missing `141`、manual alias `9`、auto alias `0`、battle states `7`、battle audit error `0`；missing 分类为 `opposite_gender_only=135`、`exact_xml_without_as_linkage=3`、`no_matching_source=3`。全量佣兵闭包为 resolved parts `3253`、当前性别 holder basic fallback `12`、failures `0`。
- **合成商品图离线人工验收（生产策略回归）**：`node tools/build-crafting-product-review.js --sample` 先验证普通武器完整 skin、双刀/疾影复合武器和防具局部人台；`node tools/build-crafting-product-review.js` 再从 `data/crafting/*.json` 全量派生唯一产物，调用现有图标烘焙器生成 256px 矢量候选，并复用 `dressup-doll-renderer.js` 的 battle rig/matrix/origin 生成纸娃娃候选。解析时严格区分物品内部 `name`、玩家可见 `displayname` 与图标资产键 `icon`，图标 manifest/烘焙过滤一律用 `icon`，避免牙狼改名类物品被误报缺图。双刀候选必须以真实 `兵器站立` holder 同时画主刀/副刀，疾影必须同时画刀身/刀鞘；是否复合只看 `actionType`，不按 `dressup2` 是否存在猜测。任一必需部件缺失、加载失败或最终不是两个 holder 时 specialization contract 失败，不得把单件图交给人类误冻。防具同时给出男女“装备聚焦”和旧全人台参考：聚焦版只以装备实际 fields 定框，上装不补手、下装不补脚、手套不补前臂、鞋不补腿，只有头盔保留脸型承托；随后在 512px 离屏画布合成并单次缩到 256px。聚焦候选以 `sqrt(alphaPixels)` 作为等效线性视觉尺度，必须大于当前图标且达到 `1.08×` 才保留“优先审”；未超过原图标或增益不足者标记为 `nonqualifying`，评审页禁用其最终单选。renderer 本身可播放父时间线与 nested animation，但评审交付 PNG 仍是固定首帧；检测到动画的候选必须标记 `static-first-frame + contractPass=false`，同样不得被最终单选签收。全人台候选保留稳定 ID，避免人类旧决定静默换图。候选集以 `sourceDigest` 绑定配方、物品 XML、icon/dressup manifest、renderer、inspector、render harness 与 builder；跨 digest 只迁移“需要调构图/缺少合适素材”问题标志和备注，绝不迁移 `candidateId` 通过决定，同 digest 也只保留仍存在且可签收的候选。全部中间图、报告与 `review-data.json` 只落 `tmp/crafting-product-review/`；`node tools/open-crafting-product-review.js` 打开本地评审页，选择结果由页面导出为带同一 `sourceDigest` 的 `crafting-product-review-decisions.json`。固定无头门为 `node tools/test-crafting-product-review.js`：它会从当前源重新计算 digest，遇到 stale `review-data.json` 直接失败并要求先重建；当前全量基线为 280 个唯一产物、1371 个候选，其中 71 个武器契约含 7 个复合武器（3 双刀、4 疾影）。评审页/decision 仍只作素材与构图回归，不是运行时 manifest；生产检视器直接消费 dressup/icon manifest，并按已定三路契约 fail-safe 回退。修改路线或构图策略时，先重跑 sample/full 人工验收，再跑生产 inspector 全量门。
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
# 显式开发模式，默认 false；CF7_WEBVIEW2_DEV_MODE=1 可作单次会话覆盖。
# 只恢复未被 Host 热键合同保留的 browser accelerator、DevTools 与默认右键；用户缩放与 pinch 始终关闭。
webView2DeveloperMode = false
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

# 临时整备 IA 原子 rollout gate。B7 后代码默认/随仓配置均为 true。
# true 同步切换两套 HUD、Build menu、Host focus 与 Web fixed mapping；
# 显式 false 原子恢复旧 HUD/header/focus，配置项存在但非法也 fail-closed 为 off。
preparationNavigationV1 = true

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
- WebOverlay 注入 CSS 隐藏 web 端 `#notch` / `#toast-container` / `#top-right-tools` / `#safe-exit-panel` / `#quest-notice-bar` / `#combo-status` / `#jukebox-panel` / `#map-hud` / **`#context-panel`**，避免与 C# 渲染重叠。右侧动作行固定为 `地图 / 任务 / 装备 / 设置 / 暂停 / 退出`：前三项使用 50px 双字标签并分别派发 `TASK_MAP / TASK_UI / EQUIP_UI`，后三项恢复原有 `⚙ / Ⅱ(▶) / ×` 图标并保留 tooltip。点歌机、地图开关、修改器、帮助迁入刘海展开区“辅助”行。
- **Native HUD 视觉契约**：[NativeHudTheme.cs](src/Guardian/Hud/NativeHudTheme.cs) 是 `useNativeHud=true` 路径的统一绘图语言：高密度黑底、1 device-pixel 直角发丝外框、与外框隔开的内侧明暗压边、左上/右下技能槽式角标，金/青/红/绿仅表达货币、交互、危险和完成状态；不再以圆角/切角外壳或大圆角半透明卡片模拟毛玻璃。常见 1.0～1.875 倍 viewport scale 均保持 1px 结构线，只有超高缩放才进到 2px；结构线关闭抗锯齿以避免半像素发虚。hover/pressed 主要由底色和内部角标反馈，不把整圈外框提亮成粗线。刘海外层单独使用低权重 frame，不与右栏按钮共用强边框。刘海折叠行与右侧动作行共享 32px 设计高度，刘海展开按钮共享 24px 高度；RightContext 地图/状态、SafeExit 与 Combo 外框均复用同一主题。
- **Native HUD 字体契约**：[NativeHudFonts.cs](src/Guardian/Hud/NativeHudFonts.cs) 将思源宋体用于刘海中文、右侧双字入口/提示、SafeExit、Toast 和地图标签；数字/FPS 继续用 Consolas，系统图标继续用 Segoe UI Symbol，Combo 保持微软雅黑以维护输入字距。Native 通过 `PrivateFontCollection` 优先加载 FontPack 已下载到 `%LOCALAPPDATA%/CF7FlashNight/fonts/source-han-serif-cn-regular.otf` 的同一文件，不要求注册 Windows 字体；缺失时依次回退系统 Source Han / Noto Serif / SimSun / Microsoft YaHei。字体在本进程初始化后新下载需重启 Launcher 生效。`闪7重置版字体` 只服务 Flash CS6/FLa 缺字替换，不复制思源宋体，避免双份 11MB 文件与版本漂移。
- **Native HUD 默认组成**：[NotchWidget](src/Guardian/Hud/NotchWidget.cs) 接管 web `#notch`。B7 后 `PreparationNavigationV1=true` 是代码与随仓默认：Native 为“游戏 / 整备 / 辅助 / 系统”四行，legacy 至少为“游戏 / 整备”两行；整备 frozen tuple 固定 `装备 / 战备箱 / 装备调制 / 技能 / 材料 / 情报`，battlebox/tuning 未解锁时仍结构可见并显示统一 reason。显式 `false` 会原子恢复 Native“游戏 / 辅助 / 系统”三行与 legacy 旧单行 toolbar，不改变各目标的 Host/AS2 授权协议。[AudioHudState](src/Guardian/Hud/AudioHudState.cs) 以最高 10Hz 采样 BGM L/R peak；“系统 → 其他”使用“控制 / 测试 / 工具”分类页并随刘海收起。[ToastWidget](src/Guardian/Hud/ToastWidget.cs) 承载 toast，[RightContextWidget](src/Guardian/Hud/RightContextWidget.cs) 承载 252px 六入口行、条件槽和可选地图预览，[SafeExitPanelWidget](src/Guardian/Hud/SafeExitPanelWidget.cs) 只消费 exact transaction owner，[ComboWidget](src/Guardian/Hud/ComboWidget.cs) 承载搓招输入与命中动画。地图 shared renderer 复用 [MapHudWidget](src/Guardian/Hud/MapHudWidget.cs) 的 WebP alpha silhouette/blocks fallback，并只异步预热当前 outline 工作集。
- **右侧条件槽唯一 owner**：[NativeHudOverlay](src/Guardian/NativeHudOverlay.cs) 是 `RightContextSlotOwner` 的唯一仲裁点，严格按 `transactionDecision > actionableNotice > contextHint > hidden` 计算一次并把同一 owner 投影给 RightContext 与 SafeExit。transaction 时 RightContext 的 notice/hint 零绘制、零命中；notice 时 hint 零绘制、零命中；hint 只绘制说明、不拥有 action hitbox；hidden 或缺 owner 时条件槽视觉、ScreenBounds 与命中均为空。透明 `CompositeBounds` 只保留 hover/repaint union，必须 click-through。装备 hint 固定为“打开角色构筑；其他整备功能在刘海或装备页”；右槽不复制整备导航。旧 `_externalStatusSlotActive` 高度布尔接线已经移除。
- **地图三层状态**：[MapDisplayState.cs](src/Guardian/Hud/MapDisplayState.cs) 将 AS2 `mm=0/1/2/3` 只读解析为 `runtimeMapMode`；`mapDisplayPreference` 是 UserPrefs 的 `auto/off/compact/expanded`；`effectiveDisplayMode` 由前两者和地图/战术能力纯派生。`CanDeliver` 等玩法逻辑只能读取 runtime，显示切换不得覆盖 `mm`。交互职责已拆分：刘海“地图开关”只做 `hidden → compact` 或 `compact|expanded → off`；地图卡片右上角只做 `compact ↔ expanded`，不再关闭地图。恢复 `auto` 只走设置/偏好写入。
- NativeHud 鼠标 Click 合成必须 Down/Up 命中**同 widget**（[NativeHudOverlay.cs](src/Guardian/NativeHudOverlay.cs) `_leftDownWidget` 跟踪）；widget 内部如需 button-level 匹配（如 SafeExitPanel 的取消/退出），自行用 `_downIndex` 守门（见 SafeExitPanelWidget.TryFireButtonClick）
- NativeHud UiData 派发分两路：snapshot KV (`g:1234|k:5`) 走 [IUiDataConsumer](src/Guardian/Hud/INativeHudWidget.cs)；旧版 (`task|拯救公主` / `combo|波动拳|↓↘|...`) 走 [IUiDataLegacyConsumer](src/Guardian/Hud/INativeHudWidget.cs)。检测：[UiDataPacketParser.TryParseLegacy](src/Guardian/Hud/UiDataPacketParser.cs)——首段无 `:` 且总段数 ≥ 2 视为 legacy。NativeHudOverlay.HandleUiData 优先 legacy 探测，命中则一次性事件不入 snapshot；不命中再走 KV 路径。两套消费者计数 + LegacyTypes 集合 fast-path 独立守门（无消费者或 type 未订阅时整包早 return）
- N 前缀 notice 派发走 [INotchNoticeConsumer](src/Guardian/Hud/INativeHudWidget.cs)：socket "N{category}|color|text" → `notchSink.AddNotice`。**useNativeHud=true 时 notchSink 直接是 nativeHud**（不再经 [CompositeNotchSink](src/Guardian/CompositeNotchSink.cs)），webOverlay 不在 sink 链上避免 SetStatusItem/ClearStatusItem 派发两次。NativeHud 内分两路：(1) `_registeredNoticeCategories` 门控的精确订阅 widget（ComboWidget 接 "combo" → DFA/Sync 命中扫光）；(2) **NotchWidget 通用兜底 sink**——所有未被 INotchNoticeConsumer 订阅的 category 都路由到 NotchWidget 通知行。两路互斥（`AddNotice` 内 `hasCategoryConsumer` 守门），避免双显示。useNativeHud=false 时 notchSink=webOverlay，N 前缀走 ExecScript 或 webOverlay._notchFallback=NotchOverlay。CompositeNotchSink 类型仍保留（A.2 后未被使用，留待后续 phase 删除或在新 fan-out 场景复用）
- NativeHudOverlay 鼠标管线：拦 `WM_MOUSEACTIVATE` 返 `MA_NOACTIVATE` 防 Owner 被点击 deactivate；`INativeHudCompositeBoundsProvider.CompositeBounds` 只决定 HWND/bitmap 保留区，实际交互始终走 `widget.TryHitTest(screenPt)`，透明保留区返回 `HTTRANSPARENT`。Notch 展开开始时只发一次 bounds，动画帧仅 repaint，收起完成后再收敛一次 bounds，避免每帧 `SetWindowPos`/bitmap resize。
- 顶部几何契约固定为 `RightOffsetBase=48`、右侧 `3×50 + 3×34 = 252px`、刘海最小 gap `12px`；1024×576 下右侧左边界 724、刘海最大宽 400。刘海宽度由 `2 × (rightRowLeft - gap - viewportCenterX)` 计算并 clamp；刘海绘制还必须硬裁切到自身矩形，展开内容不得越界侵入右栏。
- z-order：NativeHud 通过 `SetZOrderInsertAfter(hitNumber.Handle)` 沉到 HitNumber/Cursor 之下，widget 区域不会遮挡伤害数字与鼠标。架构链：Cursor → HitNumber → NativeHud → (Backdrop → WebOverlay) → Flash
- 缩放统一走 [WidgetScaler](src/Guardian/Hud/WidgetScaler.cs)：`scale = vpH/576`（用 letterbox-stripped viewport 高度，与 widgets 的 CalcViewport 锚点同源；不用 anchor.Height 避免 4:3 窗口下偏大错位）
- SAFEEXIT 二次确认：router 先调 `OnSafeExitArm`（→ `SafeExitPanelWidget.Arm()`，必须），再以可观测的 `TrySendGameCommand("safeExit")` 触发存盘；send false/异常必须转入 Failed 并向 Web fallback 推 `safe_exit_failed`，不能永久停在 Saving。C# widget 在右侧第二行的同一个 252×32 状态槽内显示 `sv:1=Saving`、`sv:2=Done`、`sv:3=Failed`；Failed 只有取消/重试，重试只重发 `SAFEEXIT`。只有 Armed+Done 能由 widget 一次性消费 `EXIT_CONFIRM` capability，raw/重放/未 Arm/Saving/Failed 均被 router 拒绝；消费后才执行普通退出。Done 态无操作 5 秒后按安全取消语义自动收起，不执行退出；悬停确认按钮时暂停倒计时，移开后继续。普通自动存盘没有 Arm 不会显示；Ctrl+Q、Flash 僵尸和 fatal shutdown 等 emergency 路径独立，不冒充安全退出成功。
- Character Build shutdown persistence：受控退出在 overlay suspend、Task dispose、socket teardown 和 Flash termination 之前，先以现有 exact generation 的 `recoverDetach`/finalize persistence proof 通过 `OnShutdownFence`；3 秒内不能取得证明则取消本次普通退出、保留运行态并提示重试。只有显式 emergency 可以跳过该普通 fence，且必须向玩家明确这是放弃未保存改动的止损语义。
- 异常恢复：任何 step 抛异常 → `ResetToClosedState()` 强制 `ForceIdleState`，保证回到一致基线；连续 5 次失败熔断清空队列
- 关键不变量：`_panelMode==true ⇔ WebView 在 panelRect+opaque+direct-hit + NativeHud(含 NotchWidget) 隐藏`；`_panelMode==false ⇔ WebView 在 anchor+transparent+click-through + NativeHud 显示`
- 焦点不变量（`webOverlayPanelTakeForeground=true`，2026-05 起默认）：idle 三件套 `LAYERED | TRANSPARENT | NOACTIVATE` 同时在 → Flash 保前台、click-through；panel 三件套同时**不在** → WebOverlay 真前台 + WebView 持键盘焦点。`ResumeForPanel` 末尾 `BeginInvoke` 排队 `SetForegroundWindow(this) + controller.MoveFocus(Programmatic)`，等当前消息泵循环走完（FlushUiDataBuffer / SetWindowPos 都已落定）下个泵循环再激活，避开同帧前台锁定。`DoFullIdleSuspend` / `DoSoftIdleRestore` 收尾 `SetForegroundWindow(Flash)` 把前台推回。env `CF7_PANEL_TAKE_FG=0` 一键回滚到 NOACTIVATE 永挂的旧行为（首次点击仅切焦点），不需 revert commit。日志关键字：`[Panel] EX_STYLE panel-on / idle-full / idle-soft`、`[Panel] take-foreground fg=... ctrl=...`、`[Panel] restore-flash-foreground fg=...`
- 性能收益：panel 打开期 α blend 成本下降（panel 矩形小 + opaque）；idle 期 `DoFullIdleSuspend` 整个 SW_HIDE WebView2 + TrySuspendAsync → 拿回 ~15pp DWM α 地板（所有常驻 HUD 已迁到 C# widget，玩家在 panel 关闭期间仍能看到 notch / toast / 货币 / combo / RightContext 右侧 cluster）
- panel 态跟随：PanelHost.DoOpen 订阅 `ownerForm.LocationChanged`（拖窗）+ `FlashHostPanel.SizeChanged`（全屏/最大化/还原 → ResizeFlashToPanel 完成后才触发，比 owner SizeChanged 时序晚但读到的 viewport 正确）。BeginInvoke 节流合并多次事件 → 调 `WebOverlayForm.GetCurrentAnchorScreenRect`（与 SyncPosition 同算法）→ `PanelLayoutCatalog.GetRect` 重算 panelRect → `NativePanelBackdrop.RepositionTo` + `WebOverlayForm.RepositionForPanel`（两者均 `SWP_NOZORDER` 不重排避免拖动闪烁，不 `SWP_FRAMECHANGED` 跳过 NCPAINT）+ `InputShield.EnterTelemetryMode` 重设。**不**主动 ReTop HitNumber/Cursor——SWP_NOZORDER 已保证 z-order 不变。DoClose / ResetToClosedState 反订阅

#### Native HUD parity gate

`useNativeHud=true` 的视觉/功能 gate 以当前收敛布局为准。`PreparationNavigationV1=true` 时，刘海与右侧动作行共享居中 `32px` 顶行，展开的“游戏 / 整备 / 辅助 / 系统”四行不得超过安全宽度；`false` 回退 fixture 仍精确守住旧“游戏 / 辅助 / 系统”三行与七项游戏行。所有绘制硬裁切在刘海矩形内，“系统 → 其他”的分类页随刘海收起，不能残留独立长菜单。常驻组件使用黑底、直角发丝外框、内侧明暗压边和技能槽式角标；hover/pressed/active/danger 主要通过底色、文字和角标表达，不得回退为粗白框、圆角/切角外壳或大圆角半透明卡片。展开/收起动画的 HWND placement 与 bitmap resize 只允许端点级变化，透明 CompositeBounds 必须 click-through。

右侧动作行固定为 `right:48px / width:252px / 3×50px+3×34px`。第二行只在 exact `contextHint / actionableNotice / transactionDecision` owner 存在时占用；无 owner 时不保留空框，地图直接贴在动作行下方。SafeExit Done 态无操作 5 秒自动收起，悬停确认按钮时暂停，自动收起不得触发退出；Failed 态只允许取消/重试，raw 或重放 `EXIT_CONFIRM` 不得触发普通退出。地图 `compact=64px / expanded=112px`；卡片 `＋/－` 只切 `compact ↔ expanded`，刘海“辅助 → 地图开关”只切显示/关闭，恢复 `auto` 走设置/偏好写入。人工覆盖仍包括 1024×576、1600×900、1920×1080、4:3 letterbox 与 100%–175% DPI，以及刘海/右槽/SafeExit/map/combo/toast/panel 生命周期；阶段性自动门不能替代 B7 默认 on 与显式 off 的真实 GUI 旅程、candidate 或标准入口验收。

`webOverlayLowEffects` 是运行态 overlay 聚合诊断开关，等价于同时启用 `webOverlayDisableCssAnimations` 与 `webOverlayDisableVisualizers`，并对 map panel 额外关闭全屏 scanline / radar / pulse、移除大图与场景节点的 CSS filter/drop-shadow、降低 full-surface overlay 透明覆膜成本。`webOverlayDisableCssAnimations` 只注入 `perf-no-css-animations`，关闭 CSS animation / transition；`webOverlayDisableVisualizers` 只隐藏 BGM/FPS canvas，并把 BGM 可视化推送从 60ms 降为 250ms 的 track-end 轮询。`webOverlayFrameRateLimit` 默认 `60`，通过 Web 端 requestAnimationFrame 限帧器把 overlay 的 JS/canvas 刷新链路限制到 60fps；`0`、`off` 或 `unlimited` 表示跟随当前显示器刷新率跑满。`webView2DisableGpu` 会同时给 BootstrapPanel 与运行态 WebOverlayForm 追加 `--disable-gpu --disable-gpu-rasterization --disable-accelerated-2d-canvas`，用于验证核显占满是否来自 WebView2 合成；它可能把负载转移到 CPU，不建议作为默认运行配置。`nativeCursorOverlay=false` 或环境变量 `CF7_NATIVE_CURSOR_OVERLAY=0` 会关闭 C# 原生 cursor layered window，恢复系统鼠标，用于 A/B 排除 cursor 迁移对 GPU 满载的影响。`useDesktopCursorOverlay`（默认 `true`，2026-05 推 default-on）：DesktopCursorOverlay 是 desktop 顶层 ULW，scale 跟 `GuardianForm.ClientSize`（窗口级，panel 开关/全屏切换都跟随；ctor 即 seed，外部 SetScale 推送只在 GuardianForm 还没 sample 过时作 fallback）。`useDesktopCursorOverlay=false` 或环境变量 `CF7_DESKTOP_CURSOR=0` 一键回滚到旧 CursorOverlayForm（OverlayBase 子类，anchor-bound，scale 跟 FlashHostPanel-based viewport，仅作回滚兜底）。详见 toml 示例注释。`useNativeHud=true` 或环境变量 `CF7_NATIVE_HUD=1` 启用 Panel-Only 架构 + Native HUD widget（详见上方 useNativeHud 段落与 Native HUD parity gate）。`webView2AdditionalArgs` 和环境变量 `CF7_WEBVIEW2_ARGS` 用于一次性追加 Chromium 参数；环境变量 `CF7_WEB_LOW_EFFECTS`、`CF7_WEB_DISABLE_CSS_ANIMATIONS`、`CF7_WEB_DISABLE_VISUALIZERS`、`CF7_WEB_FRAME_RATE_LIMIT`、`CF7_WEBVIEW2_DISABLE_GPU` 可覆盖对应配置。

`WebView2BrowserPolicy` 在两个玩家可见宿主完成 `EnsureCoreWebView2Async` 后、首次 `Navigate` 前统一应用浏览器行为。默认 `webView2DeveloperMode=false`：BootstrapPanel 与 WebOverlayForm 都关闭用户 zoom、pinch、browser accelerator、DevTools、默认右键、自动填充和密码保存；Host 仍可按 DPI / PanelScale 写入自己的 `ZoomFactor`。只有显式 `webView2DeveloperMode=true` 或 `CF7_WEBVIEW2_DEV_MODE=1` 才恢复未被 Host 保留的 accelerator、DevTools 和默认右键，用户 zoom/pinch、自动填充与密码保存仍关闭。`KeyboardHook` / `HotkeyGuard` 继续保留 `Ctrl+W/R/P/O/F/Q`，所以开发态以 `F5` 作为浏览器 reload 正例，`Ctrl+R` 仍走 Host 合同。该开关与 Git worktree、`Program.SetDevMode`、热重载互不推导，避免异步初始化竞态或开发仓库自动放开玩家浏览器 chrome。当前 exact candidate 已在本机 150% DPI 下完成 Bootstrap/Overlay 的 production/development 实机 smoke；100% DPI 与真实触控/触控板 pinch 尚无物理设备证据。稳定行为与验证边界以 [工作台规范 §6](../agentsDoc/workbench-ui-system.md#6-命中区键盘与焦点) 和 [测试矩阵](../agentsDoc/testing-guide.md) 为唯一现役合同；本段只保留 Launcher 接线摘要。

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
| `mapDisplayPreference` | string | `auto` | Native HUD 地图预览偏好：`auto/off/compact/expanded`；非法值归一化为 `auto` |
| `suppressedHighDpiWarningRaw` | string &#124; null | null | 内部字段：用户选择不再提示的高 DPI 兼容性 raw value |

前端（[web/modules/display.js](web/modules/display.js), [web/modules/about.js](web/modules/about.js), [web/bootstrap-main.js](web/bootstrap-main.js)）通过 **`config_set` 协议**读写公开字段（见 Bootstrap 前端与协议节）。`mapDisplayPreference` 当前由 C# Native HUD 的刘海地图开关（显示/关闭）和地图卡片尺寸控件（compact/expanded）写入，不进入 Bootstrap `config_set` 白名单；`suppressedHighDpiWarningRaw` 只由 C# 兼容性提示对话框读写，不下发给 Web。`list_resp` 每次都会附带 `introEnabled` / `sfxEnabled` / `ambientEnabled` / `uiFontScale`，而 `lastPlayedSlot` 只在非空时下发；前端缺失该字段时按 `null` 处理。

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

`BootstrapPanel` 本身不会在 `GuardianForm` 构造期同步拿到可用 WebView2；实际初始化发生在控件 `Load` 事件里。初始化阶段会分别记录 user-data 目录可写性、`CoreWebView2Environment.CreateAsync`、`EnsureCoreWebView2Async`、`Navigate` / `NavigationCompleted`，完成后才进入下面这套前端握手。

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

### Agent control（无人值守外层控制）

`agent_control` 是 HTTP `/task` 专用的本地自动化控制面，不是 Bootstrap WebView2 `cmd`，也不是任意 GUI/DOM 遥控器。它用于无人值守任务的外层编排：查询启动状态、选择专用存档进入游戏、等待 Flash/socket/运行态存档 ack、调用领域专用的固定入口，必要时取消启动或关闭 launcher。它保持快速返回；长轮询、日志水位、恢复与报告生成放在各领域 runner 中。斗兽标定使用 `tools/arena-calibration/run-unattended.js`，装备调制入口门使用 `tools/equipment-tuning/run-unattended.js`。

控制请求示例：

```jsonl
{ "task": "agent_control", "action": "status" }
{ "task": "agent_control", "action": "start", "slot": "cf7_agent_arena_calibration", "fresh": false, "requireFlashReveal": true }
{ "task": "agent_control", "action": "revealOk" }
{ "task": "agent_control", "action": "openEquipmentTuning", "expectedSlot": "cf7_agent_equipment_tuning", "expectedAttemptId": "<status.save.attemptId>" }
{ "task": "agent_control", "action": "cancel" }
{ "task": "agent_control", "action": "shutdown" }
```

`status` 返回 `launchState`、`revealPerformed`、`socketConnected`、`gameEnteredObserved`、`gameEnteredAttemptId`、`readyForRuntimeAutomation`、`runtimeReadyBlockedBy`、`readyForArenaCalibration`、`readyBlockedBy`、`save`、`saveRuntime`、只读 `activePanel` 和内嵌 `arenaCalibration`。通用 ready 要求 `launchState=Ready`、socket、安全 snapshot 决议、AS2 `agent_runtime_status` 对同一 `attemptId/savePath` 的 loaded ack，以及 Host 从**非 legacy 的同一个 UiData 包**观察到 `s:1|ga:<当前 save attemptId>`；裸 `s:1`、缺失/空 `ga`、stale `ga` 与 legacy 包都不能解锁，未满足时 blocker 为 `game_enter_not_observed`。每次 `start` 都无条件清除旧 `gameEnteredObserved/gameEnteredAttemptId` 并重新上锁；实收 `s:0` 只作防御性清锁，目前没有现役正常退出调用它的证据。arena ready 在此基础上再要求 arena status 可读。坏档停在 `save_decision_unsafe` / `runtime_save_not_loaded`，不得进入任何领域动作。`start` 默认 `requireFlashReveal:true`、`deferReveal:false`；slot 拒绝路径分隔符和保留字符，且默认不写 `lastPlayedSlot`。

`openEquipmentTuning` 只在 `readyForRuntimeAutomation=true`、`expectedSlot/expectedAttemptId` 与当前状态完全一致且 slot 匹配 `cf7_agent_*` 时接受。客户端不能指定 panel、profile、view 或 initData；Host 固定发送 AS2 `openInventoryWorkbench(profile=battlebox,view=tuning,source=agent_control)`，随后仍走 `panel_request → LauncherCommandRouter → PanelHost → equipment_tuning snapshot`。返回 `equipment_tuning_panel_open_requested` 只表示 opener 已发出，runner 必须再等待同一 active workbench instance 的 `equipment_tuning_snapshot_confirmed`。禁止直接调用 `PanelHost.OpenPanel`、Web `Panels.open`，也禁止借 `/console` 发送 preview/commit。

装备调制只读直达门从仓库根执行：

```powershell
node tools/equipment-tuning/run-unattended.js --seed-slot crazyflasher7_saves2 --shutdown
```

目标固定默认为 `cf7_agent_equipment_tuning`；runner 永久拒绝 live target 和 `--fresh`，先备份/重建专用目标槽，再严格按“调用 `agent_control start` 前记录 `/logs` 水位 → `start` → fresh handoff + 水位后的真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`（watchdog 拒绝）→ exact slot/attempt → single enter → 同包 attempt receipt → 同 attempt runtime ack”的顺序，等待 `gameEnteredObserved=true`、`gameEnteredAttemptId==expectedAttemptId`、active panel 与首个 snapshot 联合成立。reveal watchdog 不算 title-frame receipt，缺失时报 `title_frame_not_observed`。它在 snapshot 后停止，`uiBusinessClicks=false`、`businessWritesAttempted=false`，因此证明正式入口和读链，不替代业务写入/重启回读专项。

AS2 在 `SaveManager.loadAll()` 成功后通过内部 JSON task `agent_runtime_status` 上报 `{loaded, savePath, attemptId, source, role, level}`；该 task 仅 AS2→C#，不对 HTTP 暴露。无人值守 runner 的入口因果链固定为：调用 `agent_control start` 前记录 `/logs` 水位 → `start` 产生 expected slot/attempt 并清除旧观察 → 接受该水位后的 fresh handoff 与真实 title-frame receipt（watchdog 不算）→ 只通过 `/console` 调用一次 `_root.agentEnterResolvedSave()`。helper 与正常存档入口保持同序：先要求 `_root.notifyGameEntered` 已注入并调用它，使 FrameBroadcaster 在**同一 UiData 包**发出 `s:1|ga:<_bootstrapAttemptId>`，再按 `SaveManager.loaded` 直接返回或执行 `gotoAndStop("读盘")`；notifier 不可用时 fail-closed，且不得提前自行消费 launcher snapshot。Program 将真实 UiData 包交给 `AgentControlTask`，后者忽略 legacy 包并要求 `gameEnteredAttemptId==expectedAttemptId`；只有再取得同 attempt runtime ack 等全部条件才进入 runtime ready，所以脚本输出、调用成功或 runtime load ack 都不能单独伪造 `gameEnteredObserved/gameEnteredAttemptId`。这一步不放在 `agent_control` 里长等，`agent_control` 只提供生命周期和状态安全门。

**历史单-canary证据（不代表当前全正整数网格 Web-only 源码）**：`node tools/test-agent-entry-contract.js` 曾锁定 helper 与正常入口的同包 `s:1|ga:<attemptId>`、notifier fail-closed 和 `gotoAndStop("读盘")`；装备和斗兽 runner 的 `--check` 曾覆盖 post-watermark 真实 title-frame marker、watchdog 拒绝、`title_frame_not_observed`、fresh handoff、exact slot/attempt、single enter 与 attempt-bound `gameEnteredObserved`。当时 Launcher source-tree 全量为 **1220/1220**，AgentControl 定向为 **29/29**，装备 runner `--check` 为 **34 checks**。

**历史证据（不得外推）**：旧 `c-2a0cddb077b7-...` candidate、request `FBA91942C57DC3E6662AB77AC88EEAE3CA2AFA3C82BF5FFEA6BC68CFD6C31AE4` 与 formal attempt `4eae1360cedd413fa3175db6a8997158` 只证明当时单-canary 闭包；其 `e2e_verified` / `standard_entry_verified` 状态不再代表当前地图箱实现。

**地图箱冻结发布证据（历史）**：source `2c87d31fecbbfb50c072ec199da0134755974402` 的隔离 candidate（build identity `7C72B92B0C1CF57EB9BC0D3C1024D31657EE52E6B13D7BBF9FDB94FD5A6186DB`、payload closure `7E5EDCD4FEA80E1269C0B8BCC325D1FE0994EE8C7321F0F71CB9AF4B369C4A44`、Core SHA-256 `3EB1D3910B764F0B7F9ACA1FA989A4D8732F75479E64325223F270502256A5DF`）已由 attempt `82b9e602526c4e93a02d26aac0a44f20` 完成真实地图箱、同实例 organizer、部分领取、容量/情报上限拒绝、放弃、终态关闭与存盘，达到 `e2e_verified / NOT_DEPLOYED`。同一身份经 tag `runtime-build-v2/20260722-map-loot-web-only-v1`、request `F1F9493CF08DD88F26E1493FCACE306AC160866EA21440FC62698E5965A1AF04` 和 promotion commit `40119635ae5527225a425eb7f69af54f85115066` 完成双故障域正式发布；无参数标准入口 attempt `9e88d51425a54b8b84dff0aa21702eac` 随后完成真实 Web loot claim、terminal close/unpause 与存盘，达到 `standard_entry_verified`。native bundle 不含 `launcher/web`，外部 Web 字节仍由实施基线所列源码哈希与实机日志独立绑定。

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
├── save/{slot}.sol            通过 SolFileLocator 解析的 SOL 二进制原件（启动决议源对比需要）
├── logs/launcher.log          + launcher.log.1（FileShare.ReadWrite 打开，避开锁）
├── logs/bootstrap.log         + bootstrap.log.old（native 引导器 + Core 早期启动诊断）
├── logs/perf-latest.jsonl     Core 启动性能时间线（若存在）
├── logs/startup-exit.jsonl    最近启动退出/失败原因码（若存在）
├── logs/startup-failure-latest.txt 最近一次玩家自诊断弹窗摘要（若存在）
├── logs/dumps/*.log           .NET createdump 诊断日志（若存在；.dmp 本体按需单独发送）
├── config/config.toml
├── config/launcher_user_prefs.json
├── runtime/cf7-runtime-manifest.tsv 构建文件清单与 SHA256（若存在）
├── meta.json                  OS / git HEAD（读 .git/HEAD 解析 ref） / CLR / 机器名 / 时间戳
└── README.txt                 给测试员的提示
```

slot 缺省时只打 logs + config + meta（不带档），用于"启动失败前没机会进编辑器"的场景。

启动失败自诊断弹窗复用同一个打包器：Core 已进入托管入口后的 WebView2、Steam、文件缺失、端口失败、Flash 启动/握手/嵌入失败会显示 `CF7-LAUNCH-*` 错误码、建议动作、复制摘要与打开报告位置按钮。Core 尚未起来的 runtime / preflight / Core launch 失败由 native bootstrap 显示 `CF7-BOOT-*` 错误码，并提供打开 `logs/` 的入口。成功启动路径不弹窗。

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

`/task` 中的 `arena_calibration` 是批次控制面：`startBatch` 只启动后台批次并快速返回，`status` 查询进度，`abort` 会下发 AS2 `arenaCalibrationAbort` 清理当前标定单位和 clock，并在 C# 侧把当前等待中的 run 记为 `aborted`。结果写入 `logs/arena-calibration/<batchId>-results.jsonl`；manifest 必须位于 `tmp/arena-calibration/`，`batchId` 只允许 `[A-Za-z0-9._-]` 的短标识。数值验收必须在专用竞技场标定地图中进行，不刷主角/同伴；普通 `gameworld` smoke 只证明通信和写文件链路可用。AS2 runner 若尚未处于 `_arenaCalibrationStage`，会先通过 `ArenaController.prepareArenaStage(0, 0, "", onLoaded, onLoadError)` 预载 `DEATH MATCH角斗场`，再走 `淡出跳转帧("wuxianguotu_1")` 进入 StageManager 的 calibration no-player 分支；StageInfo/跳转入口不可用时返回 `stage_failed`。禁止从玩家宿舍/基地等普通场景直接替换 `gameworld`。

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

**BGM 可视化 + 点歌器**：`PeakDetector` 自定义节点（`ma_node_vtable` passthrough）插入 bgmGroup → engine endpoint 之间，实时采样 L/R peak。Native HUD 由 [AudioHudState](src/Guardian/Hud/AudioHudState.cs) 统一维护曲名、visualizer 偏好、播放态和 64 点峰值历史：peak 最快 100ms、播放态 250ms，Notch 把它作为 FPS sparkline 的低透明度背景包络，暂停时冻结并降透明度；右侧不再常驻 jukebox titlebar 或独立轮询。点歌机入口位于刘海展开区“辅助”行；正式展开 UI 仍由 [jukebox/jukebox-panel.js](web/modules/jukebox/jukebox-panel.js) 注册 `Panels.register('jukebox')`，经 `JUKEBOX_EXPAND` → `LauncherCommandRouter.OpenPanel("jukebox")` → `PanelHostController` 打开，继续承载大波形、进度、专辑、设置与 BGM 暂停/恢复。曲目标题由 AS2 `pushUiState("bgm:title")` 经 UiData 推送，catalog 仍由 `MusicCatalog` 启动期与热加载增量维护。

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

### 启动期存档决议（Protocol 2）

自 2026-04-18 起，Launcher 拥有**启动期快照选择权和文件保管能力**：它预先读取并决议 shadow + SOL，通过 `bootstrap_handshake` 把 snapshot 直接下发给 Flash，消除启动期 async I/O 等待。运行期玩家状态的业务/语义权威仍在 AS2：AS2 从 `_root.*` 组装并写入 SOL，再把整份 shadow 推送给 Launcher；`ArchiveTask` 还不是领域事务、revision/CAS 或幂等命令核心。当前 v3.0 规则下，**同秒或更新的 shadow 会覆盖 SOL**，这样 Bootstrap editor / import 写入的 JSON 会在下次启动直接生效。

自 2026-04-22 起，**valid legacy SOL 不再只是“临时给 Flash 用”**：当 Resolver 返回 `Snapshot(source=sol)` 时，会立刻通过 `ArchiveTask` 复用同一条 `.tmp` 写完后删除旧目标、再移动到目标的替换路径，把归一化后的 snapshot 首次落盘为 `saves/{slot}.json`。Bootstrap `list/load/load_raw` 还会在标准 10 槽上先做一次 legacy 预热，因此外部用户即使还没“先进游戏存一次”，只要当前运行根下存在可解析的旧 SOL，也能直接在 launcher editor / 任务系统里看到已决议快照。当前实现不提供 crash-atomic replacement 或多文件事务保证。

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

当 `Snapshot(sol)` 成立时，Resolver 还会同步执行一次 shadow seed：

```
ArchiveTask.TrySeedShadowSync(slot, normalizedSnapshot)
   └─ 写 saves/{slot}.json.tmp → 删除旧目标（若有）→ Move 到 saves/{slot}.json
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
| `SolResolver.cs` | 决议入口，上述矩阵实现；`source=sol` 时触发 shadow seed |
| `SolParserNative.cs` | sol_parser.dll P/Invoke（UTF-16 路径，UTF-8 JSON 回传） |
| `SolFileLocator.cs` | 多 hash 子目录；只搜当前运行根，兼容 `.swf + .exe` 父目录，不跨根 fallback |
| `SaveMigrator.cs` | 2.7→3.0 迁移（含 legacy 主线位补 0）+ MergeTopLevelKeys + ValidateResolvedSnapshot |
| `LegacyPresetSlotSeeder.cs` | Bootstrap `list/load/load_raw` 前预热标准 10 槽，把 valid legacy SOL 提前 seed 为 shadow 文件 |
| `SaveResolutionContext.cs` | DI 聚合（传给 GameLaunchFlow / Bootstrap handlers） |

### ArchiveTask shadow 辅助链

shadow 链不仅是运行中存盘的 JSON 冗余副本，也是启动期 Resolver 的 snapshot 候选。Bootstrap UI 的存档 CRUD / import / editor 全都写这条链；下次启动时，只要 shadow `lastSaved` 同秒或更新于 SOL，就会直接作为 `json_shadow` snapshot 下发给 Flash。

现在这条链还承担 **legacy shadow 首导入**：

- `SolResolver` 返回 `Snapshot(source=sol)` 时，立即把归一化后的 snapshot 经现役 delete-and-move 替换路径落盘到 `saves/{slot}.json`；这不是 crash-atomic replacement 证明
- `ArchiveCommandHandler` 在 `list/load/load_raw` 前对标准 10 槽执行预热；若当前 shadow 缺失但当前根存在 valid legacy SOL，会先 seed shadow 再继续现有查询逻辑
- 预热只覆盖 `crazyflasher7_saves` 到 `crazyflasher7_saves9`；自定义 legacy 槽名不在自动继承范围内
- root 隔离保持不变：每个 launcher 运行根只看自己的 `saves/` 与自己的 SharedObject 子树，不会跨 `resources/` / `CrazyFlashNight/` 互相读档或删档

**JSON 协议**（XMLSocket，async）：

| op | 方向 | 动作 |
|----|------|------|
| `shadow` | Flash → C# | 游戏内存盘时推 mydata JSON，写 tmp 后以 delete-and-move 替换 `saves/{slot}.json`（当前无 crash-atomic replacement 保证），附带前后快照语义 diff 发 warnings |
| `load` | Flash → C# | 按 slot 读 shadow JSON 返回；遇 tombstone 直接报错 |
| `load_raw` | Bootstrap → C# | 绕过 tombstone 读原始 JSON（editor 用） |
| `list` | Bootstrap → C# | 枚举所有 slot（合并 .json + .tombstone），带 corrupt/inconsistent/mainProgress 元信息 |
| `delete` | Bootstrap → C# | 写 tmp 后以 delete-and-move 替换 `.tombstone`，再删 `.json`；当前不是跨两文件事务 |
| `reset` | Bootstrap → C# | 清 launcher 副本 + tombstone（不清 SOL） |

**HTTP `/save-push`**（辅助接口，非启动主路径）：从 `saves/` 读指定 slot 的 JSON，通过 XMLSocket 推给 AS2（`save_push` task），可被外部工具用于调试/恢复。启动期恢复不走这条——主路径是 Protocol 2 的 `bootstrap_handshake` snapshot 下发。

一致性校验（`RunConsistencyCheck`）：每次 `shadow` 写入前，对比上次快照检测"角色名变化 / 等级倒退 / 金钱为负 / 版本降级"等可疑变动，附到 `warnings` 字段回传 Flash，不阻断写入但留痕。

### 进程生命周期加固
- **shutdown try-catch 保护**：每个 Dispose 步骤独立 try-catch，防止单点异常跳过后续清理
- **Panel pending 清理**：NpcShop/Crafting/Hairdresser 共用 `PanelPendingCallTracker<TContext>`，只收敛机械 correlation、Timer、去重与单终态；业务 write/reconcile 仍由各 Task 裁决，early / bus-only / normal 三条退出路径均显式 `Dispose()` 三个 Task。Hairdresser 的生产 close observer 还会 `ClearPending()`；若关闭时已有 commit，领域 `needs_reconcile` 与期望发型保留，重开只以 fresh snapshot 收敛，迟到 commit 不复活
- **Flash 僵尸进程检测**：Socket 断连后 10s 内进程仍未退出则 ForceExit（Flash Player 20 SA 偶发退出卡死）
- **OnKillFlash 钩子**：退出前先 DetachFlash + AudioEngine.Shutdown + KillFlash，在 ExitThread 之前执行
- **ProcessManager 线程安全**：`_flashProcess` 访问加锁，`KillFlash()` 可多次安全调用
- **Application.ThreadException**：接管 WinForms 默认错误对话框；退出期异常只写日志并压掉弹窗，运行期 UI 线程异常按 fatal 记录后触发 `ForceExit`
- **AppDomain.UnhandledException**：非 UI 线程未处理异常写日志

### Flash UI → Web 迁移

以下条目已接入或正处于 Launcher WebView2 overlay 迁移期；旧 Flash renderer 是否已删除、是否实际释放对应内存，必须以各条目自己的 fallback、E2E 与退役状态为准：

AS2 UI → Web Panel 迁移的操作护栏统一见 [../agentsDoc/as2-web-panel-migration.md](../agentsDoc/as2-web-panel-migration.md)，本轮数值权威、preview/commit 失败分类与共享 Tooltip 生命周期的专项决策见 [Web Panel 跨层契约与交互可靠性专项治理](../docs/Web-Panel跨层契约与交互可靠性专项治理-2026-07-22.md)。迁移任务必须按该文档维护 Web cmd → C# Task → AS2 handler → response task → panel_resp → JS handler 闭环表；NPC/KShop/Crafting/Hairdresser 还必须同步 `contracts/panel-contracts.v2.json` 中的 `(wireDomain, cmd)` 身份、cmd→action、`query|transaction` capability、read/write access、唯一 AS2 业务裁决 owner、nullable `flashCommandHandler` 精确 wrapper receiver/inline 事实、`flashResponseTask → hostResponseHandler` 精确绑定、边界权威与适用的 interaction policy，并运行 `node tools/validate-panel-contracts.js` 与 `node tools/test-panel-contracts.js`。dev harness / 生产 panel / Flash smoke / 游戏内手测边界仍须分层报告。双栏工作台的 layout/density/type/color/state/motion/focus/lifecycle/cascade 与组件边界只以 [workbench-ui-system.md](../agentsDoc/workbench-ui-system.md) 为准；本节只登记运行态入口和领域差异。

| Flash 实例 | Web 实现 | 协议 |
|-----------|---------|------|
| 基地理发店（Web-only，旧 renderer/fallback 已退役） | `hairdresser-runtime.js` + `hairdresser.js` + `hairdresser.css` + 共享 `panel-runtime.js` / `dressup-doll-renderer.js` | 理发师 NPC 只发精确 `panel_request panel=hairdresser source=world_hairdresser`；命令缺失或发送失败均 fail-closed，不回退旧 UI；独立 `hairdresser` domain 只允许 snapshot/commit，Web 本地预览，AS2 权威写发型并标 dirty，未知写只以 fresh snapshot 对账且零重放 |
| 弹出公告界面 (新任务横幅) | notch.js 通知条 `#quest-notice-bar` | `Utask\|{name}` (旧格式透传) |
| 弹出公告界面 (公告) | notch.js 通知条 | `Uannounce\|{text}` (旧格式透传) |
| 任务完成提示 | notch.js 通知条完成态 (❗ 图标呼吸 + 整条可点击) | `td:0/1` + `tdh:<hotspotId>` + `tdn:0/1` (KV 帧同步) |
| 地图界面（旧右上角小地图位） | `map-hud.js` 右上角 HUD + `map-panel.js` 全屏地图面板 | `mm/mh` (KV 帧同步) + `TASK_MAP` click |
| Native HUD 功能入口 | 右侧六路动作 + 默认“游戏 / 整备 / 辅助 / 系统”四行；整备为 frozen 六项目标 | `PreparationNavigationV1=true` 默认原子接通两套 HUD、Build menu 与 Host focus；`EQUIP_UI` 打开 Character Build，`MATERIALS` 走 Host-owned nonce + AS2 exact echo，`EQUIPMENT_TUNING` 走独立 exact nonce opener，Intelligence 走 Host 固定同步 admission。显式 off 整体恢复旧七项游戏行/header/focus，不放宽任一路由 |
| 存盘动画 | ✕ 按钮状态变化 (·· → ✓ / 失败) | `sv:1/2/3`（开始 / 成功 / 失败，KV 帧同步） |
| 安全退出界面 | Native `SafeExitPanelWidget`；`useNativeHud=false` 时 `#safe-exit-panel` fallback | `sv:1/2/3` + Armed/Done one-shot `EXIT_CONFIRM` capability；Failed 只取消/重试 |
| 帮助界面 (帮助界面.swf) | Panel 系统 `help-panel.js` (Markdown tab) | Bridge → C# panel_cmd open help |
| K点商城 / 库存管理 (旧商城界面 MC 已退役) | `game-ui-behavior.*` + `workbench.js` + `kshop-runtime.js` + `kshop-views.js` + `inventory-runtime.js` + `inventory-ui.js` + `kshop.js` | `SHOP` → `kshop`；权威二级结算直接交付实际物品容器 + 历史待领取兼容 + 背包—战备箱库存态，40 槽/页、剧情权威 0..6 页、权威树筛选、权威 sortAndMerge、discard |
| 独立物品工作台 / 角色构筑 | `inventory-workbench.js` + `inventory-storage-workbench.js` + `character-build-*.js` + `workbench-inspection-viewport.js` + 上述共享 inventory/workbench 组件 | 严格 `profile=battlebox|warehouse`；`view=storage|tuning|build` 由唯一 facade 在同一 PanelHost instance 内分发。刘海 `WAREHOUSE` 默认背包—战备箱；宿舍 XFL 打开背包—真实仓库；`EQUIP_UI` 默认以 `profile=battlebox,view=build` 打开 Character Build，只有 `CF7_WEB_INVENTORY_WORKBENCH=0` 回退完整旧 Hub。原生 build opener、Skills 返回与前向失败回滚都由 Host 签发一次性 `openRequestId`，且只准入 exact `workbench/nativehud_equipment/battlebox/build`；baseline 同时冻结 active panel/instance、queued command、reserved owner/instance 与 idle/processing fence。新 Host 配旧 `asLoader.swf` 时缺 nonce 必然 fail-closed，Host/SWF 必须以同一 immutable candidate 配对验证。角色构筑采用主角 DLS 混合皮肤与 `55:45` 双栏（右栏最小 `360px`）；左内层以弹性纸娃娃 + 内容宽槽区组织，槽区收缩贴右、四药剂同排，1024 下 Canvas 至少 `300px`；占用的固定 11+4 槽使用真实图标、状态角标与完整 ARIA，颈部/缺图显式 fallback；左 PaneChrome 把浏览摘要放在“当前构筑”右侧、放大入口放在最右，不再重复总槽位与分组计数；未选候选时预览 overlay 隐藏，routine 底部提示折叠；右 PaneChrome 最多三项候选动作且无通用详情/pin。一个持久化 full/compact 控件在 storage、构筑候选与 embedded tuning 标题间迁移；`空手/长枪/手枪/手枪2/双枪/兵器/手雷` 七种 battle pose 每次从当前权威合成状态重测结构骨架 fit envelope，`手雷站立` 使用真实 `手雷_装扮` holder，身体核心字段参与取景，手臂、手与武器只绘制、不参与缩小人物，禁止按 `panelInstanceId + gender` 跨状态复用旧缓存；放大页复用 exact Canvas/renderer identity，并提供共享瞬态缩放/平移/全貌复位，关闭清零、嵌入态不吞输入；普通物品筛选仍保持 inventory 中性 |
| 材料目录 | `crafting-materials.js`，复用 crafting 壳、材料字典、获取索引与合成索引 | Native HUD/Character settled 都先建立 material wait，再走 `openMaterialUI({openRequestId}) → exact panel=crafting/source=nativehud_materials/initData.view=materials`；Host 固定 runtime initData。只读呈现持有量、怪物/关卡来源和配方/装备用途；独立完整/紧凑偏好默认紧凑 7 列、完整 2 列并同步键盘网格；顶栏共享帮助解释筛选、来源/用途与键盘操作；旧 material-only flag/页面已退役，发送、admission 或挂载失败均 fail-closed，不保留 Flash fallback |
| 装备调制切片 | `equipment-tuning-runtime.js` + `equipment-tuning-view.js` + `equipment-inspector.js` + `workbench-inspection-viewport.js`，嵌入 `workbench view=tuning` | 独立 `domain=equipment_tuning`；顶层为“强化度 / 交换 / 进阶 / 配件”，强化自动核算最终目标且以动态/永久上限分离避免 `+14` 幻象，交换通过 coordinator 只读 projection 在右栏展示同 use 权威候选且不改左栏筛选/面包屑；snapshot 额外提供 Host 强校验的权威男女分支，顶部当前装备图标与已选交换目标可打开共享 185% 交互检视，材料/进阶/配件/候选目录不扩容；候选富注释保持 AS2 intro/desc 分段，workbench 禁止原生 `title` 竞争；“调制说明”无 pin/pressed/persisted subject，打开时随 operation 与当前 focus 更新，Esc 只收起说明并恢复入口，下一次才退出 tuning；配件按插件定义投影的档级/目录用途/定位建立共享树与面包屑并由 tuning host 呈现 DLS 晶体索引风格，顶部持久快捷总览与配件页详细操作区都按权威 capacity 全量投影槽位，顶部进阶/已装/空槽均可一步进入对应操作，详细区保留替换、单拆与空槽安装，批量卸下独立于 slot group；顶栏安全/快速偏好仅本地持久化，快速仍经 AS2 preview/token 且只对无连带单件操作自动提交。完整/紧凑复用 workbench 唯一 density 控件与偏好：紧凑候选对齐 owned grid 的 `48/40/4px`，只收紧材料/配件/转换等浏览卡片，不压缩 tabs/主提交语义；全工作台使用 DLS 基调，强化石核心按密度与 reduced-motion 动静降级；顶栏 `?` 复用 workbench modal 且零业务消息。七类 wire 写全部由 AS2 snapshot/preview/opaque token commit 裁决；Host 维护实例租约、write epoch 与未知写结果精确对账，库存刷新完成前禁止并发转移/整理/关闭 |
| NPC 物品商店 | `npcshop-runtime.js` + `npcshop.js` + 共享 `workbench.js`/图标/tooltip | 场景 NPC 对话与平板联系人 `openNpcShop` → `npcshop`；主页面选择待购/待售，右栏顶层切背包/收集品，二级结算页调整数量并以 AS2 opaque token 原子提交整单 |
| 合成工作台 | `crafting-runtime.js` + `crafting.js` + `crafting-inspector.js` 薄适配 + 共享 `equipment-inspector.js`/`dressup-doll-renderer.js`/`item-filter.js`/工作台壳 | 12 类旧合成入口 → `crafting`；Flash 权威 preview/一次性 commit，并以权威 `actionType`/`gender` 驱动普通武器完整 skin、双刀/疾影双 holder、防具性别聚焦或其他当前图标的只读特写 modal；支持批量份数上限与共享树筛选。“整理背包”只是 exact crafting instance 内的纯 Web 子路由，Host owner/instance/pause 不变；仅显式返回恢复合成，普通关闭或子路由加载/挂载失败都关闭 crafting |
| 技能管理 | `skills-runtime.js` + `skills.js` + 独立 `skills` domain | 刘海屏与 Character Build 的「技能」入口都以 `nativehud/manage` 打开自身技能管理，不含教师 session/返回研习能力；只有 Character 来源的 exact manage instance 获得展示位 `canReturnCharacterBuild` 与显式“← 返回构筑”，真正一次性能力仍只在 Host。刘海直开、`×`、Esc、native backdrop 都普通关闭，不走返回。世界教师独立以 `world_skill_trainer/trainer` 打开，同一 active Skills 内才可通过 exact rebind 暂时切到管理页并返回教师。浏览、初学、升级、12 槽装备/卸下/排序和纯被动启用均由 AS2 权威服务裁决，展示复用完整/紧凑、三组首击生效且可组合的 Skill facet 和共享 pointer drag，但不进入 inventory/equipment domain |
| 战队界面 | Panel 系统 `team/team-panel.js`（佣兵 / 伙伴 / 战宠 / 机械；宠物管理/领养/进阶 + 佣兵管理/雇佣/培养） | `TEAM` → `mercPanelOpen` + `team`；子控制器继续使用 `pets` / `mercs` Task 协议 |
| 竞技场 (DEATH MATCH) | Panel 系统 `arena-panel.js` (标准档位卡 + 死线警报隐藏卡) | `arena`，ArenaTask 双层 callId |
| 情报界面 | Panel 系统 `intelligence-panel.js` (H5 富文本) | `情报`/`INTELLIGENCE`，IntelligenceTask 按需正文 |
| 任务界面 | Panel 系统 `tasks/task-panel.js` (当前任务列表/详情) | 刘海屏 `任务` 键 `TASK_UI`（含 `NEW_TASK_UI` 合并）→ `taskPanelOpen` + `tasks`，TaskTask 双层 callId |
| 副本任务（委托任务，旧 FLA Symbol 1873） | tasks 面板第 4 tab `副本任务`（左难度档 + 右详情/委托对话，复用 DialogueView） | NPC「获得任务」→ AS2 `openWebDungeon`(panel_request initData{view,taskId})；cmd `dungeonDetail`/`dungeonBriefing`/`dungeonEnter` 复用 TaskTask + `task_response`；进图写门控在 AS2（金钱/等级/K点）。详见 docs/副本任务-Web面板迁移-架构设计-2026-06-26.md |
| 第一防线调度板 | tasks 面板的 `dispatch-board` 聚合模式（不显示常规任务 tab；左侧板内任务，右侧复用关卡简报与 DialogueView） | 基建交互 → AS2 `openWebDispatchBoard`(panel_request initData{view,boardId,skin})；cmd `dispatchBoardSnapshot`/`dispatchBoardDetail`/`dispatchBoardBriefing`/`dispatchBoardEnter` 复用 TaskTask + `task_response`；任务归属与进图资格由 AS2 按 `dispatch_board` 和进行中任务状态权威校验 |

装备调制不设独立玩家放量开关，也不下发可制造调试/游玩差异的 `tuningAvailable` capability。Character Build 可从已穿戴装备或候选进入嵌入式调制，并在同一 Character session 内以 external-write/reconcile 门收束；`profile=battlebox view=storage` 仍提供工作台调制入口，宿舍 `profile=warehouse` 不提供。AS2 旧调制子入口固定留在已服务化 renderer，不发送 Web redirect，且仍调用同一 `EquipmentTuningService`；TaskRegistry 与 Router 对残留 `source=legacy_equipment_tuning` 请求 fail-closed 返回 `migration_paused`。`EQUIP_UI` 默认打开 Character Build，环境变量 `CF7_WEB_INVENTORY_WORKBENCH=0` 只用于完整旧 Hub 的显式 legacy fallback。agent source 走同一正式 workbench/profile 语义，但另受专用槽、attempt、runtime-ready 与正式 opener 约束。

插件分类元数据的单源位于 `data/items/equipment_mods`：每个子文件根层显式声明 `modGrade/catalogScope`，每个 mod 的精确 `use/weapontype` 与 `tag→uiRole` 继续决定规则/定位；`ui_presentation.xml` 只把受控 ID 映射为标签、色号和符号。材料物品 XML 不复制这些字段。`EquipmentTuningService` 向右栏候选投影 grade/scope/role，`InventoryPanelService` 对松散插件材料附加 `modMeta`；安装可用性只认 AS2 返回的 `availabilityCode`。构建门 `node tools/validate-equipment-mod-ui.js` 同时校验 104 个 mod、四档、六种 scope、100 个插件材料与四个特殊材料的一对一物品映射。

当前 Tuning 交换 target 必须重建 exact `{sourceKind:"inventory",containerId:"背包",slot,expectedLease}` 四键；旧三键 shape 会在进入 Flash 前以 `invalid_payload` 拒绝。单件插件点击立即在原候选和对应槽上投影 `aria-busy`/阶段文案，但这只是 presentation intent，不会乐观改写库存、槽内容、数量、lease 或 revision，也不排队重放。成功 commit 先展示 Host 已校验的写后 tuning snapshot，同时继续持有同一个 inventory external-write capability 直到 fresh 背包刷新完成；刷新 source ref 与写后 snapshot 匹配时直接采用并省去重复 tuning snapshot，漂移、畸形或刷新失败仍走 fresh read / retry / reconcile。`equipment-tuning-write-lifecycle.js` 只承载这段即时意图、write、refresh/retry 和 quick-commit 时序；`inventory-storage-workbench.js` 对 owner-only 状态变化仍刷新 controls/marker/pager，但不重绘引用未变化的 inventory pane。配件页“卸下全部”是槽 rail 最右侧、与槽卡等高的方形按钮，仍位于具名 slot group 外的独立批量动作组。

独立 Workbench 本地导航以 transaction generation + `destroyed` fence 保护 `build ↔ storage/tuning`：destroy 会先使 pending 失效并撤销端口，迟到的双向 prepare callback 不得再激活 Build、挂载 Storage、提交 history 或恢复旧焦点。pending 期间若 controller 上报另一个合法 view，该权威实际状态会先 supersede 旧事务、清 timeout、推进 generation，并在旧目标为 Build 时 suspend，再沿封闭三视图 plan/commit/reset 收敛；不会提交新 view 却遗留旧 pending。若所有既有领域 timeout 之后事务仍未终结，30 秒 watchdog 才 discard/abort 并恢复可操作态，迟到 callback 继续被 generation 拒绝。fresh 叶门为 inventory modules **31/31**，生产三视口为 **867/867**，另有 hidden/lifecycle **12/12** 与 preparation **18/18**。这关闭了可证的 teardown、分叉上报与 orphan navigation 竞态/活锁路径，但重启后恢复本身不是内存泄漏或 WebView renderer crash 的证据；tooltip/透明遮挡仍只是待现场 hit-test 的候选，未取得 ProcessFailed、heap、console/命中证据前不得写成根因。

**旧 Web HUD 右上角工具条布局（仅 `useNativeHud=false` fallback）**：
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

该 fallback 的最右侧 `80px` 窄列由 `map-hud.js` 占用，直接复用 `map-panel-data.js` 的热点/scene 几何；AS2 只经 UiData 推 `mm`（模式）和 `mh`（当前 hotspotId），HUD 只做当前区块高亮 + 固定 beacon 点，点击后走 `TASK_MAP` 打开全屏地图 panel。默认 `useNativeHud=true` 不使用这套几何；当前 252px 六入口、条件状态槽和 `compact/expanded` 地图契约见上文 Native HUD 段落。

**通知条状态机**：隐藏 → (新任务/公告到达) → 播放通知 → (队列空+td:1) → 完成态常驻 → (td:0) → 隐藏。完成态图标持续呼吸脉冲 (`icon-breathe`)。

**任务条点击分派**：完成态整条 `#quest-notice-main` 可点击。`tdh` 非空且 `tdn=1`（非战斗地图 + hotspot 在 `NAVIGATE_TARGETS` + 所在组已解锁）时，右侧 `⇨` 装饰亮起，点击发 `TASK_DELIVER` → C# 转发 `navigateToHotspot` gameCommand → AS2 `MapPanelService.navigateToHotspot` 直传到 NPC 所在地图；否则退化为 `TASK_UI` 打开任务栏。

### 面板系统（Panel System）

本节只描述 Panel lifecycle、focus、tooltip 与业务面板的当前架构；动态测试计数、候选身份和 promotion 状态统一以 [验证矩阵](../agentsDoc/testing-guide.md) 及对应专题 ADR 为准，历史提交不得外推为当前树证据。

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

> **地图资源箱现状覆盖说明**：旧单-canary promotion、candidate、CS6 与实机计数仅作历史。当前真实 loot wire、Coordinator 与 Web 模块协议不变，S0 平行 Host/Web/AS2 接线已物理删除；六类资源箱 preset 完成箱体领域准入后，所有正整数 `row/col` 都是 Web intent，支持 `1×1`、`col<=8`、`capacity<=64`。超界或畸形尺寸 fail-closed；只有精确 `0×0` direct 与无 reservation 的 break 地面掉落，负数/单边零/混合尺寸不得降级；生产 XML/runtime marker 和 Flash recovery renderer 均不再是当前路径。

- **loot**（地图网格箱 S1/S2，当前 Web-only source）：`web/modules/loot/loot-runtime.js`、`loot-state.js`、`loot-view.js`、`loot-organizer.js`、`loot-panel.js` 复用 `transfer-pair` 与 owned inventory primitive；AS2 是奖励、容器与状态唯一权威，Host 只负责 strict shape / exact binding / 串行 / panel 生命周期，Web 只发意图。AS2 先以六类资源箱 preset 做箱体领域准入，防止投影召唤器等非箱正网格被劫持；准入后选择器把所有正整数 `row/col` 视为 Web intent：`1×1` 有效，`col<=8 && row*col<=64`。超界或畸形尺寸 fail-closed；只有精确 `0×0` direct 与无 reservation 的 break 保持地面掉落，负数/单边零/混合/缺字段全部拒绝；箱型名及当前 2×4 / 4×4 / 4×8 不构成准入后的 rollout/shape 白名单，生产 XML/runtime marker=0。掉落数量仅在 min/max 同时缺省时默认 `1/1`，单边缺省或显式坏值 fail-closed。claim/close 继续要求 exact revision/remaining/operation/slot/lease 证明；unknown 只 query、不 replay，Host/Web 各维护独立 freshness watermark。ordinary `target_full / inventory_full` 在同一 tracked `loot`、同一 `panelInstanceId` 内打开背包—战备箱 organizer，只允许 strict `snapshot/autoTransfer/discard`；全程保持 Coordinator `Bound`、pause 与 `LOOT_ACTIVE`，返回前必须取得 fresh ACTIVE snapshot。主页非空 X/Esc/backdrop 进入 `LOOT_SUSPENDED`，明确放弃才 `ABANDONED`。初次、reopen、mount、navigation 与 socket failure 都保留同一 inventory/anchor并收束为 `LOOT_SUSPENDED`（空→`CONSUMED`，anchor 失效→`EXPIRED`）；journal/effects/proof 未完成时保持 `LOOT_COMMIT_PENDING`。Flash 网格 renderer、claim-only adapter 与 observer recovery 不再是产品路径。场景切换/restart 必须先通过 `expireScene` teardown barrier；pending 时完整保留 world。静态门全量审计真实声明、item catalog、缺省/坏值数量、能力边界、direct/break 负向路径与 marker=0，准确计数以最新脚本输出为准；人工采用集中代表场，不造 9 站。旧单-canary candidate/promotion/standard-entry 仅是历史证据，详见 [S1/S2 ADR](../docs/地图资源箱-S1S2真实战利品容器与Web双栏-ADR-2026-07-18.md) 与 [验证矩阵](../agentsDoc/testing-guide.md)。

> **loot open ACK 与 break 精确边界**：上述“无 reservation 的 break”只指正在破碎的 exact target 没有 reservation/authority；另一箱存在 Web authority 不得全局阻断本箱 direct drop，同 target authority 仍必须拦重复奖励，unsupported shape 始终 fail-closed。`LootPanelCoordinator` raw ACK 只允许 queued 四键或 rejection 五键，`MessageRouter` 再注入原 `callId`；`accepted=true` 只表示已入队，不表示 bound/mount。AS2 对 timeout、send exception、socket closed、畸形或未知 ACK 不作 rejection 推断，而是退役当前 XMLSocket source并复用 exact-attempt socket-detach proof；旧 source 的迟到事件按对象身份隔离。完整枚举以 [S1/S2 ADR §5](../docs/地图资源箱-S1S2真实战利品容器与Web双栏-ADR-2026-07-18.md#5-冻结-wire-v1) 为准。
- **lockbox**（开锁小游戏）：`web/modules/minigames/lockbox/` 下的独立正式小游戏模块，保留 core/solver/generator、panel、audio、CSS、普通 browser harness 与 Node QA。地图资源箱 S0 bootstrap/adapter/actual-wire 及 Host/AS2 接线已退役，不再存在 dormant gate 或当前地图箱业务分流；未来开锁奖励需另立协议与 ADR。普通 `minigame_session` 继续固定脱敏。

> **Web transport 返回值边界**：`Bridge.send(message)` 在 WebView2 `postMessage` 可同步调用时返回 `true`，transport 缺失或调用抛错时返回 `false`；这个布尔值只描述本地投递，不是 Host 业务受理回执。需要业务定局的面板必须继续等待自身 response/rebind。Skill 的 trainer↔manage 控制在成功投递后进入等待态，新 `panelInstanceId` rebind 才算切换完成；3 秒无 rebind 会恢复原页面按钮，教师 capability 的有效性仍由 Host/AS2 校验。

> **武器平衡摘要边界**：KShop catalog、NPC catalog 与 inventory item projection 可选携带 AS2 生成的 `{state:"confirmed",weightLayers,formula,level}`。只有严格 weapon balance v1 的精确 profile、绿色显示声明、当前已知 `workbookVersion` 和绑定身份/profile/机械语义/工作簿版本/14 项业务数字的 input digest 同时通过才下发；库存按实例 tier 选 profile，商店选 `data`，未知 tier 或缺 profile 禁止回退。ItemUtil 在加载期把 compact balance 提取到独立缓存，普通物品克隆不携带它。共享 `ItemCard` 只用最小摘要渲染 `LvN ◆±N` / `◆±N` 与一行“同级加权”，不得接收或展示 WBR、工作簿版本、digest、evidence、auditRef 或 note，也不得按价格或稀有度自行推断。字段缺失是正常 fail-closed，不改变既有 envelope、写能力或目录可用性。完整契约见 `tools/cf7-balance-tool/docs/agent-balance-record-design.md`。

- **kshop**（K 点商城 + 战备箱库存态）: 唯一支持入口为 Launcher `SHOP` → Web Panel；旧 Flash `shopMainMC` 已退役。采购态继续使用 catalog/cart 恢复影子与可靠写 gate；`kshop-views.js` 承载视图 DOM；`kshop-cart-controller.js` 与 catalog/owned/tooltip presenter 把本地意图、投影和注释从 facade 拆开，`kshop.js` 只保留领域编排。新结算先发只读 `checkoutPreview`，由 AS2 重算目录、等级、K 点与 `ItemUtil.require` 容量并铸造单次 `checkoutToken`；`checkoutCommit` 复核后以 `ItemUtil.acquire` 整单直接交付到背包/材料/情报/药剂栏等实际落点，再扣 K 点、清空购物车并强制存盘。余额或容量不足整单不扣款，恰好等额允许购买。新购买不再进入 `_root.商城已购买物品`；旧存档队列继续以 purchased token + claim 单飞自然清空。成功 checkout/claim 回包必须携写后 `catalog`，Web 立即采用动态 `maxQuantity` 并再次清理购物车；首次 bulkQuery 清理出的失效/超限购物车也会经 saveCart 写回恢复影子。commit 未知结果只做 `bulkQuery + inventory snapshot` 对账。套装数据以 `data/items/item_sets.xml` 的 `id/name/order` 为元数据单一权威，物品 XML 只声明 `setId`；`ItemUtil` 在启动加载期补齐既有 `setName/setOrder` 投影，故 AS2 → Host → Web 协议不变。`item-filter.js` 为 KShop/NPC/库存共用分类模型：商品目录显示“类别 / 套装 / 专柜”三个一级入口；类别沿 `majorType → use → actionType/weaponType` 下钻，套装沿注入后的 `setId/setName/setOrder` 聚合并按中心 `order` 排序，专柜沿 KShop JSON `type` 展示 13 个策划来源分组，三条维度互不覆盖。背包使用 AS2 权威 `setFacets` 显示“类别 / 套装”，其中 `{branch:"set",setId}` 始终扫描完整容器而非当前物理页；native select 仅作旧 AS2 无 facets 时的兼容回退。分类轨道固定占位并取消按钮过渡动画，切层不再推动下方物品格。owned 库存的纯 Web 展示排序已退役，只保留会明确修改存档的权威整理。共享 GridRenderer 按稳定 key 复用引用未变化的节点；同一窗口的选择、数量与权威刷新保留滚动及实体/子控件焦点，分类/分页/重开显式归顶。共享 `PanelTooltip` 的复合 hover 在 grace 到期时用真实命中状态作终局判定；KShop harness 同时以 pointer 与 pen 真实事件覆盖“触发物→浮层”过桥、快速划入空白隐藏，并为 legacy `showAtMouse/hideHover` 消费者保留物理鼠标探针。公共视觉门固定 **8 个正交样本 / 20 项 conformance**。自动门：Edge harness **135/135**（1024×576、1366×768、1920×1080）、NPC harness **106/106**、item-filter model 22/22、视觉矩阵 20/20；Launcher xUnit **1902 pass + 3 explicit opt-in skip / 1905**；fresh Output Panel 为 `InventoryPanelServiceTest` 144/144、`NpcShopPanelServiceTest` 46/46、`CraftingPanelServiceTest` 36/36；真机门见验证矩阵。
  KShop 商品普通单击或 `+` 每次加购 1 件，拖拽加购只作为可选精细路径保留；购物车主页面只显示 `×N`、小计和整行移除，不再提供数量弹层或 `− / +`。唯一精确数量入口是“核对并结账”的真实 `SecondaryPage`，它与 NPC 结算共用 `QuantityControl`。合法上限 `A` 供严格整数输入、完整 range、`− / + / +5` 与真实数量键盘步进使用；当前可直接提交上限 `E` 只显示为“可用”预设与轨道标记，`A>200` 改用对数位置映射。无效草稿零 preview，第一次 Esc 只撤销草稿；权威重算按商品/行 key 复用节点并恢复焦点与滚动。控件只管理本地数量意图与生命周期，下一次 AS2 preview 仍裁决价格、容量和可提交性。NPC 的 `A=purchaseLimit`、`E=maxPurchasable`，不得合并两种权威上限。KShop 顶栏通过共享 `HelpAction` 解释加购/结算/交付分工，开闭零业务消息。
  共享层级筛选把路径放在 PaneChrome 标题区同一行：宽布局显示完整路径且祖先 crumb 可返回；只有真实窄态才折叠中段省略号，并始终保留 root、current leaf 与完整 accessible path。root/current/ancestor 的 `aria-label` 与可见语义一致；省略号本身 `aria-hidden`，但其 `title` 必须列出被折叠的中段完整路径，未发生折叠时不得遗留该 title。不得再加第二行、横向滚动，或在 facets 已存在时恢复 native select。
- **workbench**（独立物品工作台与角色构筑）: `web/modules/inventory-workbench.js` 是唯一 `Panels.register("workbench")` facade，只拥有公共 shell/header/close 与 `storage/tuning/build` dispatch；storage/tuning 业务已迁入 `inventory-storage-workbench.js`，角色构筑由 session/view/controller 加 mutation/action-view/tuning/pose 模块组合，controller 均不得反向注册 Panel。Host 固化严格 profile：`battlebox`=背包 50 + 战备箱 40（Native HUD `WAREHOUSE` 默认），`warehouse`=背包 50 + 真实仓库 50（宿舍 `openInventoryWorkbench` → `panel_request` 专用，24 页）；`build ↔ storage` 只在同一个 `panelInstanceId`/pause lease 内切换。两种 storage profile 均不请求商城目录、不触发 `shopPanelOpen/Close`；图标 required-assets 门、全屏 anchor、tooltip、类别/套装权威筛选、权威整理、lease 与事务实现完全共享。两种 profile 都提供“批量存入/批量取出”：入口、模式、计数、退出与唯一提交位于双栏下方的正文命令栏，不进入全局顶栏或覆盖格子；普通点击暂存多选、重复点击取消，显式“执行转移”后按序严格单飞调用既有 `inventoryAutoTransfer`；`Ctrl+单击` 保持单件立即转移，任一 stale/timeout/未知写停止余项并对账。最低画布固定验证 `0/1/5/50` 件零溢出/零重叠；独立战备箱紧凑态使用 `6×7` 容纳 40 槽并保持 48px 卡高。AS2 落位仍只执行 merge-first→首空位。顶栏只有一个共享 `HelpAction`，按 storage/tuning/build 动态解释当前视图；战备箱帮助必须明确精确放置、拖拽、`Ctrl+单击` 与批量暂存/取消/执行。所有提供完整/紧凑切换的生产界面首次进入默认紧凑，已有显式本地 `full|compact` 偏好优先；storage/build/tuning 共用 `cf7.itemgrid.mode.workbench`。模块行数 ratchet 由 `tools/audit-workbench-ui.js` 单源维护，文档不冻结易漂移的当前计数；不得提高阈值或压行换余量。自动门不能替代宿舍、现役英雄和真实存档回读。
  standalone `workbench` 只能在 Host 已分配有效 `panelInstanceId` 后挂载；实例缺失必须拒绝，不能借 crafting 的 Web 子路由走无实例兼容。
- **character build**（角色构筑，当前工作树）: `EQUIP_UI` 默认经 AS2 opener preflight 打开 `panel=workbench, profile=battlebox, view=build`；`CF7_WEB_INVENTORY_WORKBENCH=0` 仅作完整旧装备 Hub fallback。独立 `domain=loadout` 提供 `snapshot/candidates/flushLive/statsSnapshot/finalize` 与 `equipEquipment/unequipEquipment/equipDrug/unequipDrug`；snapshot 固定投影 11 个装备槽、4 个药剂槽、三条 revision/dirty、权威性别/portrait 与结构化 stats，candidate 资格由 AS2 catalog authority 决定，Web 不解析物品规则。

  C1 在 loadout projection 上增加可选 `candidateFacets:{scope:"all",filterFacets,filterItemCount}`。旧 AS2 省略该字段仍可读取并显示 unknown；字段一旦出现，`CharacterBuildProtocol` 必须验证 exact shape、递归 facet/count 一致性、唯一 id、文本与 `0..50` 边界，任一畸形拒绝整份响应。AS2 从同一次完整背包 snapshot 投影，复用候选结构资格检查并在复扫前后以 `containerVersion` 围住 revision；相关 `use` 与候选资格不一致时省略整组字段，不伪造零。Web 的 `character-build-projection.js` 只把该引用带入 ViewModel，`character-build-facet-counts.js` 只做固定槽映射、`0`/`—`、ARIA 与既有 slot leaf decoration：`手枪2` 合并 `手枪2 + 手枪`，药剂读取 `药剂` leaf；不按名称猜 taxonomy、不新增业务请求、不接管 View 的稳定 key/focus/scroll 生命周期。`filterItemCount` 表示完整 `scope=all` 背包 facet 总数，不得显示成构筑候选总数；选槽后的 `candidates` 与所有写前复核仍是最终权威。

  C2 候选 rich tooltip 复用现役 `InventoryPanelService.inventoryTooltip` 与共享 `PanelTooltip`，没有新增 AS2 endpoint。Web 的 `character-build-candidate-tooltip.js` 只发送 exact active workbench instance 上的 `inventory/tooltip`，payload 为 `{v,source,context:{kind:"character_build_candidate",sessionGeneration}}`；Host 只接受最近一次已验证 candidates 回包中的 exact 背包 source，包括可说明但不可提交的 blocked 行。任何 `payload.context` 属性都进入严格 Character 分流，`null`、primitive、近似 kind、多余字段、跨实例/旧 session 或伪造 lease 不得回落到 ordinary InventoryTask。snapshot、新 candidates、任一写、rebind 与 close 都推进 completion fence；Character 路径只接受并重建 exact rich response，迟到回包不得复活。没有 context 的 storage tooltip 保持原 generic lease-only 合同。Web scope/cache identity 绑定 candidate identity、session generation、slot 与 lease；pointer 与键盘 focus 共用 basic→rich 内容，失效/超时不自动重放或重试。tooltip 没有选择、装备或调制 authority。

  编辑态采用主角档案白 + DLS 诊断青混合皮肤，普通物品筛选仍保持 inventory 中性。双栏固定 `55:45`，右栏不得窄于 `360px`；这是 1024 逻辑宽度下仍能维持三列完整候选和八列紧凑图标的左倾上限，不继续压到 `56:44`。左内层使用 `minmax(0,1fr) max-content`：纸娃娃弹性吸收余量，11+4 槽区按约 `204px` 内容宽收缩并贴右，三组末格与 pane 右缘对齐，1024 下 Canvas 至少 `300px` 且四药剂同排；不得为了表面右对齐保留无效固定列宽。已占用的固定槽以 `Icons.html()` 的真实动态图标/分层图为主，保留槽名、数量/强化/升阶/插件角标与完整 ARIA；颈部零 projection 使用静态物品图标，缺图显式 fallback，不能回退为纯文字砖。左侧“外观与配置 / 当前构筑”PaneChrome 把浏览摘要内联在“当前构筑”右侧、放大入口放在最右，不显示 `15 / 15` 或“护具/武装/药剂”的重复分组计数；未选候选时 overlay 整层隐藏，选中后只显示“预览 · 名称”。routine 浏览/读取/恢复提示折叠且不占 pane 底部空间，blocked/write/reconcile/error 仍就地显示。右栏候选动作直接并入“背包候选 / 候选对比”同一标题行；通用“详情”和 pin 已删除，装备上下文最多三项“装备 / 调制 / 卸下”，药剂提交显示“装入”，`aria-label` 保留完整动作语义；可调制的已装备武防显示“调制”，不适用时显示禁用“不可调制”与原因，药剂不显示该动作。1024×576 下动作组保持单行、不换行、不溢出；独立动作行已删除，候选底部也不复制 action rail。同一个持久化 density toggle DOM、同一个 `GridDensityController` 与同一个 `cf7.itemgrid.mode.workbench` 在 storage、构筑候选和 embedded tuning 标题间迁移；构筑态改变候选网格，调制态改变材料/配件/转换候选等浏览型卡片，左侧纸娃娃与 11+4 槽、operation tabs 和主提交语义不压缩，切换零业务流量并保持选择、焦点和预览。纸娃娃始终使用单 Canvas，候选只改变覆盖层合成输入；`dressup-doll-renderer.js` 的纯测量 API 每次从当前权威 snapshot（有候选时为覆盖后的当前合成 state）构造空手/长枪/手枪/手枪2/双枪/兵器/手雷七种 pose，并合并带留白的结构骨架 fit envelope；`手雷站立` 使用 battle rig 的真实 `手雷_装扮` holder，不回退为空手兼容。`身体/脸型/发型/面具/屁股/左大腿/右大腿/小腿/脚` 参与取景，手臂、手与武器只绘制、不参与 scale；装备或外观状态变化必须重新测量，禁止按 `panelInstanceId + gender` 跨状态缓存。未传 envelope 的其他消费者仍按当前内容自适应。`character-build-doll-preview.js` 只把 exact stage/Canvas 迁入全 body SecondaryPage，底层 inert、Esc 后归位并恢复 opener，不创建第二 renderer/current-preview state。放大态通过共享 `workbench-inspection-viewport.js` 提供 wheel/`+/-`、主键拖拽、方向键与“全貌”复位；transform 只落 exact Canvas，关闭清零，嵌入态不截获相关输入。

  候选第一次单击、Enter 或 Space 只固定本地预览；再次单击同一候选或在同一候选上按 Space 清除选择/预览，零业务写入。只有同一已选候选上的明确、非 auto-repeat Enter 才等价触发唯一主 CTA，并继续受 disabled、pending、lease、revision 与写门约束。

  个人信息 exact shape 是 9 组 47 行：首屏只把 AS2 已投影的 `weightRatio`、三段阈值和 `movementSpeed` 组成旧 PlayerInfo 负重色带，并显示摘要 KPI；完整明细为 3×3 分组，抗性摘要 4×2、明细 2×4，八个 `currentColor` SVG 只作装饰且保留字段文字/原始值。武器威力使用明确标注的 `log10(value+1)` 对数相对量级，抗性保持线性组内相对量级；两者都只在整组有限非负且不全零时出现，不复制速度/战斗公式、不预测候选、不把防御字段当可加和，也不把抗性硬定为 0–100。stats SecondaryPage 在 1024×576 打开时直接聚焦唯一滚动区，支持键盘/滚轮，正文至少 11px；缺比例、畸形阈值、缺值/负值/全零只撤误导性图形，原始 47 行仍保留。

  已穿戴装备和候选都可进入嵌入式调制，调制写通过 Character external-write/reconcile 门收束后才返回；入口直写“调制说明”，不提供 pin、`aria-pressed` 或持久化主题，打开后随强化/进阶/配件/转换 operation 与当前 focus 更新。Esc 按“检视 modal → 调制说明 → 返回候选”逐层消费，关闭说明时恢复说明入口且不退出 tuning。Character Build 的“技能”入口现走 Host-owned exact retire → Skills 窄事务：Web 只在本地 finalize 完成后发送当前 instance 的严格 workbench close `reason:"navigate_skills"`，不直接打开 Skills、不模拟 Native HUD，也不串接双领域 session；Native HUD/Notch `SKILLS` 与教师入口继续走各自现役 preflight。

  B4 将这条 post-close 事务收敛为固定 `Skills | Materials | Intelligence` 目标 enum 和小型 Host intent；intent 只持有目标、exact Build instance、`armed | rollback_after_settle` phase、generation、lifecycle epoch 与阶段 timer，不提供 registry、DSL 或任意 destination。strict close parser 只接受 `navigate_skills | navigate_materials | navigate_intelligence`；B4 当批只启用 Skills，Materials/Intelligence 在任何 normal close、binding 消费或目标 open 前明确拒绝。arm→coordinator-settled timeout 与 settled→Skills 的既有 `SkillOpenTimeoutMs` 严格分离：settled transition 在同一 lifecycle 锁内销毁前一 timer 并进入后一 wait。pre-destructive 失败恢复同一 exact Build DOM，退场后失败至多一次 native Character rollback；competition、stale、navigation/热重载、socket、shutdown 和 epoch 变化均单次取消，迟到 callback 不得重开或重复回滚。Web 的 `returnFocusAction` 仅解析 `skills | preparation-menu`；B4–B6 当批 Host 仍只发送 `skills`，该历史阶段已由 B7 默认 on 投影取代。

  B5 已在该固定 enum 内启用 Materials：Native HUD direct 与 Character settled 各自建立独立 material wait，Host 生成 `material.open.*` opaque requestId，再发送 `openMaterialUI({openRequestId})`；AS2 只对合法字符串原样回显，Host 只消费 exact `{task:"panel_request",panel:"crafting",source:"nativehud_materials",initData:{view:"materials"},openRequestId}` 与对应 baseline/admission。省略 nonce 的 legacy envelope 只在无 armed intent/wait 时 ordinary-open；pending 时 missing nonce 拒绝但不替换 wait，携带 nonce 的 wrong/near-match 则结束当前目标。send-false/throw、`MaterialPanelOpenTimeoutMs`、competition、navigation/热重载、socket、shutdown、admission、迟到/重复都零旁路；Character 已退场时失败至多一次复用原生 Build rollback。该路径不创建 registry、bus 或通用返回栈。

  B6 已在同一固定 enum 内启用 Intelligence：exact coordinator settled 后只在同一 lifecycle fence 内销毁 arm/timer、捕获 Host exact idle admission，并用 Host 内建封闭 `{mode:"prod",source:"runtime",debug:false}` 同步打开 `intelligence`。该分支不发 AS2 nonce、不安装 target timer、不复用 Skill/Material wait 或 `FixedPanelOpenWait`；Web 也不能传任意 panel/initData。Host admission/open false 或异常在退场后至多启动一次原生 Build rollback，rollback 失败则保持游戏态并提示从装备入口重试；competing intent/panel、epoch、navigation/热重载、socket/shutdown、迟到/重复 settled 均零重开。Host open 一旦原子接受，后续 pause socket false/throw 不得反转为 rollback 或第二次 open。

  B7 只在 presentation 层把上述六个既有固定目标原子切到默认 on：Build `initData` 增严格 `preparationNavigationV1:true`，header exact-set 为 `preparation-menu | stats | help | close`，Skills return 和三目标 rollback 聚焦 `preparation-menu`；off 时字段省略并恢复旧 `storage | stats | skills | help | close` / `skills` focus。Web 菜单固定六项，equipment 为可聚焦 current/disabled 零业务项，battlebox/tuning 在 `questProgress <= 13` 保持可见禁用与统一 reason；触发器 click/Enter/Space 都执行 toggle，ArrowDown 总是打开并进入 roving menu，Tab/Shift+Tab 只关闭菜单且不得 `preventDefault` 或人工移动焦点。busy、Stats、modal、SecondaryPage、rebind、deactivate、destroy 均由稳定 controller 管理焦点和 listener。该 gate 不参与 B2–B6 的 route authorization。

  H1 为 Character-origin Materials / Intelligence 接通 exact“← 返回装备”：只有 forward handoff 后由 Host 绑定到 exact `panelName + panelInstanceId + lifecycle` 的子实例得到 `navigationOrigin:"character_build"` 与 `canReturnCharacterBuild:true` 展示位；真正 one-shot 只在 Host。尚处 `PendingInstanceBind` 时没有授权任何同名实例，ordinary crafting/intelligence same-name open 必须在 admission/initData enrichment 前原子撤销 pending bind；forward echo 丢失、取消或迟到都不能授权后来普通实例。Crafting/Intelligence Web 只发 exact 五键 `navigate_character_build` close；Native HUD 直开、普通 `×`/Esc/backdrop、stale/rebound/foreign instance 都回游戏。Intelligence 只在 authoritative `state / bundle / snapshot / glossary_snapshot` 请求在途时阻断返回；tooltip 与后台 glossary catalog 不阻断，settle 后恢复。Host 先 exact retire 子 visual/owner，再复用 Native equipment typed preflight 取得 fresh workbench nonce，建立新 Character session/snapshot；competition、navigation/热重载、socket、shutdown 与 lifecycle epoch 前进撤销能力。没有新增 `returnTo`、通用 panel stack 或 destination registry；这些实现字节已包含在 `9118eb…` 正式 runtime，但本轮标准入口只读 smoke 没有运行 Materials / Intelligence 往返，因此不能把自动门外推为该旅程的本身份实机验收。

  Host `CharacterBuildTask` exact 绑定 panel instance、session generation、transport generation 与 write/reconcile watermarks；普通 close 在视觉关闭和 pause release 前取得 AS2 terminal proof，navigation/socket detach 只允许同 ready generation 一次自动恢复，第二次失败进入可见 `fatal_blocked`。PanelHost visual-retire 以 Host-owned exact barrier 关闭匹配 lease/visual，替换实例不可误关，callback 只在 visual 真正 idle 后完成一次；不能用 `PanelClosed` 或 generic unpause 代替。`navigate_skills` 只对白名单 strict close envelope 开放：Router 在 normal close barrier 前验证并武装 exact active/bound/finalized instance，之后仍走 visual-retire、`characterBuildRecoverDetach`、持久化证明与 pause release；只有 `SetCoordinatorSettled` 确认 Character binding/recovery 和 Host visual 均已清理，才原子消费 one-shot。消费时先 `DiscardDeferredBarrierOpen()`，再建立只期待 `nativehud/manage` 的短期 Skill open capability，并把 Host 生成的 opaque `openRequestId` 随 `skillPanelOpen` 发给 AS2；AS2 校验后仅在对应 manage `panel_request` 顶层原样回显。实际 Skills 只有在 nonce、source、view 与 Host baseline 全部匹配时才经 `RequestOpenPanel/OpenSkillsPanel` 打开；send-false、timeout、Web navigation、socket disconnect 或 competing panel 会撤销 capability，任何迟到回包均拒绝。若 one-shot 在最终锁内消费前已被取消或替换，callback 返回未消费，不得丢弃 recovery 窗口内的 deferred open。教师请求不能消费/取消 Character 或 Notch 的 manage wait，只允许在无该 wait且 Skills 尚未 active 时以 `source=world_skill_trainer,view=trainer` 独立进入；manage 已打开后迟到的教师请求必须拒绝并 cleanup session，active Skills 的 trainer↔manage 只走 exact-instance panel-control rebind；`nativehud+trainer` 与 `world_skill_trainer+manage` 均 fail-closed。Host 不直接 `OpenPanel("skills")`。Character one-shot 在消费/取消后归零，不持久化到 Skills 生命周期，也不携带 Character session/revision/watermark；后续 Skill capability 只保存短期 presentation correlation。通用 Web task bridge采用正 allowlist；Character recovery 时 loot admission 在入队、lease 和 UI 执行三处 fail-closed。Guardian 崩溃后遗留的旧 AS2/Flash 进程不支持接管，需重启游戏，不增加跳过 generation 的恢复后门。较早 B4 隔离候选已完成真实装备/药剂/调制写、finalize、安全退出和同候选重启读回，只作为历史 `e2e_verified / NOT_DEPLOYED` 证据；本轮 exact source `c4faf14460` 的双向导航已进一步完成双故障域 promotion 与无参正式入口，严格状态为 `standard_entry_verified`。协议与自动门见[角色构筑专题 §9](../docs/角色构筑-Web双栏工作台-工程落地规划-2026-07-26.md#9-验证矩阵与当前证据)，最终身份、GUI 和日志见[正式关闭证据](../docs/evidence/character-build-skills-bidirectional-navigation-closure-2026-07-28.md)。

  Character 来源的 Skills manage 只额外得到 `canReturnCharacterBuild:true` 展示位；`PanelHostController` 必须在预留新 `panelInstanceId` 后再调用 `SkillTask.EnrichPanelInitData(..., panelInstanceId)`，随后由 `BindPanelInstance` 把 Host-only 能力绑定到该 exact instance。Notch 直开、trainer、trainer 派生 manage、rebind/stale/foreign instance 都没有这项能力，`canReturnTrainer` 与 `canReturnCharacterBuild` 互斥。玩家只有点击显式“← 返回构筑”才发送 strict `reason:"navigate_character_build"`；`×`、物理 Esc 与 native backdrop 都是普通 Skills close。Host 现役把 Esc/backdrop 同折叠为 `panel_esc`，因此不得在 Web 假造不同返回语义；帮助/确认模态与展开搜索仍先消费 Esc。

  反向导航在 arm 时原子消费 exact Host capability，并要求 manage、write idle、零 pending/queued reconcile/cleanup、无教师 return session。随后仍执行普通 `skillPanelClose` 与后台 cleanup/reconcile；只有 tracked Skills visual 真正 idle 且 `SkillTask.IsClosedAndSettled` 同时成立，才允许调用原生 Character Build opener。visual close 与 coordinator settled 两条回调都可尝试完成，但共享同一个 one-shot，乱序也只能打开一次；idle manage close 即使没有新的 coordinator callback，也必须由 visual close 路径完成。等待超时、active/foreign visual、竞争 panel、Web navigation/热重载、socket disconnect 或 shutdown 都撤销能力。

  `EQUIP_UI`、Skills 返回与前向失败回滚共用 native workbench typed preflight：Host 生成一次性 `openRequestId`，它只授权 exact `{panel:"workbench",source:"nativehud_equipment",profile:"battlebox",view:"build"}`。AS2 `InventoryPanelService` 只校验并在该 tuple 的顶层 `panel_request` 原样回显；Router baseline 同时冻结 active panel/instance、PanelHost queued command、reserved owner/instance 与 idle/processing fence，nonce、tuple 或任一水位不匹配都 fail-closed，迟到 A 不能消费 B。navigation/reload、socket disconnect 与 shutdown 是先推进 cancellation generation/epoch 的 lifecycle barrier，barrier 前 callback 不得在之后创建 wait、重新排队或打开，连续导航只允许 latest intent 胜出；send-false、timeout 与 competition 也撤销当前 wait。workbench 没有滚动兼容：新 Host + 旧 `asLoader.swf` 的无 nonce 回包必然拒绝，两侧必须进入同一 immutable candidate，绑定同一 build identity / payload closure 实际执行并完成 E2E。

  前向 Character 已退场后，如果 Skill preflight send-false/timeout、请求被拒或 `OpenPanel("skills")` 返回 false，Router 只允许一次 `origin=skill_open_rollback` 的 Character Build preflight；成功后用 fresh session 重建，失败则停止、不循环并 toast 引导从“装备”重开。反向 Skills 已退场后若 Character preflight 失败，不自动复活 Skills，只提示重试。所有 open/rebind false 都记 failed/rejected，不能继续记录 opened。跨 panel 不保存旧 DOM opener；B7 默认 on 时，`skills_return` 与 `skill_open_rollback` 只给新 workbench 下发无权限的 `navigationOrigin/returnFocusAction:"preparation-menu"`，首屏稳定后聚焦“整备”；显式 off/非法配置回退才使用 `returnFocusAction:"skills"` 聚焦旧“技能配置”动作。
> **情报奖励溢出边界**：每个情报物品使用自身 XML `maxvalue`，不存在统一“四个”上限。敌人掉落、拾取、任务、成就和脚本奖励都经 `ItemUtil.planRewardAcquire/acquireReward` 复核；可接受部分入账，超出部分按物品 `price` 精确折算金币，零价情报只截断。同批重复情报共享剩余容量，折算金币不再被掉落随机/等级倍率二次修改。商城与合成继续严格拒绝超容量交易，不能借溢出折算套利。

- **npcshop**（NPC 金币物品商店）: `web/modules/npcshop-runtime.js` + `web/modules/npcshop-secondary-pages.js` + `web/modules/npcshop.js`；入口与交易权威边界保持不变。三视图只在 Web 组合：背包唯一来自 `domain=inventory` 的 `InventoryCoordinator`，NPC snapshot 只拥有材料/情报，Host 不再要求重复 `views.bag`。Host 对购买数量只执行 `1..999999` 传输技术护栏；`purchaseLimit/maxPurchasable` 等有效上限由 AS2 按价格、容量与策划配置动态裁决，Host 不再复制固定 100 业务上限。`purchaseLimit` 是合法 preview 输入硬上限，`maxPurchasable` 则是当前可直接提交上限和“可用”按钮/轨道标记目标；`+ / +5` 可以构造暂时超出余额或容量的计划以追加待售项或进入整理空间，但权威 preview 必须同步阻塞原因、禁用提交并保持加减/返回/可用恢复可操作。re-preview 在途时数量行会与 handler gate 同步可见锁定，权威回包后再重开，避免按钮看似可点却静默吞操作。`tradePreview` 成功回包在进入 Web 前还要严格校验 token、总额、余额/容量/commit-state 自洽、slot/same_name 计数、行 schema，以及买入/卖出行与归一化请求的物品身份、数量和 scope 一致性。inventory slot lease 与 collection lease 在资源未变化时跨纯读稳定，容器写版本/集合数量变化后才返回 `stale_state`；一次性 `tradeToken` 仍在提交尝试后消费。Web 以 preview epoch 屏蔽关闭/重开前的迟到回包，并把每次成功 preview 的精确请求与 settlement 固化为 checkpoint：一般只读 timeout、断线或畸形回包恢复最近成功 checkpoint 并重新开放加减/返回；`stale_state/shop_not_found/item_not_found/locked/invalid_price/invalid_quantity/insufficient_quantity/nothing_to_sell/sell_forbidden` 改取 fresh authority snapshot；只有已投递写入的 timeout/send failure、`reconcile_required` 或畸形 commit 才进入 reconcile，且绝不重放 token；commit 在途同时锁住返回、数量调整、批售、移除与重复提交。公共 `ItemFilter` 从 `majorType/use/actionType/weaponType` 建立类别树，并从运行时补齐的 `setId/setName/setOrder` 建立并列套装树；配置了人工 sections 时再保留“专柜”入口。目录与背包统一为行内单层 drilldown，材料/情报保持 NPC 商店领域投影。目录/背包选择按稳定 key 原位更新，结算数量重算保留滚动，筛选换窗归顶；整理空间返回结算前另取一次不改变当前筛选 UI 的完整 `filterKey=all` 背包快照，用于重绑跨筛选累计的待售项。容量分析即使收到重复情报行也会先按名称聚合，超出收集栏剩余量稳定归类 `destination_full`。数值 fixture、NPC 双上限 `interactionPolicy` 与 C# 定向测试共享 `contracts/panel-contracts.v2.json`；契约变异门当前 **62/62**，另覆盖 capability/owner、nullable Flash handler binding、全局 action/response-handler 唯一、HandleWebRequest 内实际 resolver 与 fail-closed domain guard、Host case 覆写/歧义 return、未登记 Host command、AS2 action→cmd/receiver/source 精确绑定、静态 action/response-task assignment、handler alias 及字符串伪证据。领域冻结时自动门：套装数据 66 套/327 件、NPC 数据 35 NPC/834 商品、browser harness **86/86**、视觉矩阵 17/17；Launcher xUnit **1257/1257**；Flash `NpcShopPanelServiceTest` 46/46 与 `InventoryPanelServiceTest` 131/131 fresh Output Panel。
  当前整合树的现役 browser 基线为 **106/106**；其中严格整数输入、线性/对数 range、真实数量键盘步进、`A=purchaseLimit` / `E=maxPurchasable`、“可用”标记、首个 Esc 撤销草稿及 preview 后稳定行/焦点/滚动均在真实重绘生命周期中覆盖。上一段 **86/86** 仅保留为增量前记录。
- **crafting**（合成工作台）: `web/modules/crafting-runtime.js` + `web/modules/crafting.js` + `web/modules/crafting-inspector.js` + `web/modules/dressup-doll-renderer.js`；12 个旧分类入口由 Host 严格重建 category 后进入独立 domain。snapshot 目录投影带权威 `gender`、`batchEligible`、`canCraftOne/availability`、互不混用的 `name/displayName/icon`、`majorType/use/actionType/weaponType` 与 `setId/setName/setOrder`；Flash 每配方只做一次单份计划且不探测最大份数，Web 复用公共 `ItemFilter catalog` 视觉契约做本地类别/套装树筛选、“只看可合成”、卡片状态和计数，但保留稳定 recipeIndex 且不把目录提示当提交权威。详情原图标点击打开只读检视器：普通武器绘制完整装备 skin，不带人物；双刀/疾影按权威 `actionType` 使用 battle `兵器站立` 的两个真实 holder，分别绘制主刀+副刀或刀身+刀鞘；复合渲染必须 strict 2/2 且无 missing/failed image，任一必需部件缺失或 rig 漂移即整组回退图标；防具按当前权威 gender 仅绘制装备聚焦 fields，且不借异性分支；其他、缺失素材或纸娃娃图片加载失败也回退当前图标，图标再缺失时显式缺图。窗口默认 185%，支持拖拽/滚轮/键盘/按钮、全貌/重置与纸娃娃/图标动效暂停继续，24fps 重绘，窗口缩放后重采样 backing，关闭时销毁唯一 live Canvas/RAF/监听器。生产挂载与商城/工作台一致使用全 anchor + 1024×576 scale-shell，内部双栏为同向约 60:40；preview 的 `craftCount=1..99` 只对堆叠产物且无装备素材的配方生效，Flash 返回 `maxCraftCount`、总材料/产物/双货币价格并把份数绑定一次性 token，双货币先按每份 `Math.floor(basePrice × 铁匠倍率)` 再乘份数，commit 原子复核。Web 保存同 category/recipeIndex/craftCount 的成功 preview checkpoint；普通读 timeout/disconnected/畸形回包恢复并继续可操作，权威分歧才刷新 snapshot，只有明示 reconcile 或已投递 commit 的未知结果进入写对账。材料不足时“背包 / 战备箱”先 snapshot 撤销当前 token，再在同一 Overlay 本地打开 `workbench profile=battlebox`；“返回合成”只恢复 category/recipeIndex/craftCount 与展示筛选意图并强制重新 snapshot/preview，不共享 lease 或写 token。目录/详情保留浏览器原生滚动语义，提交后同配方 snapshot 重绘保留当前目录位置，自动回退其他配方时目录/详情归顶，数量预览跨占位重绘保留详情位置，以 CSS 窄轨统一外观；数量控件使用自绘按钮而非原生 number spinner。自动门：`test-crafting-inspector.js` 男女全量 560/560（每性别 71 武器、153 防具、56 图标；另固定全 XML 9 双刀+9 疾影、合成子集 3+4、同 skin 双槽、缺件/rig 漂移回退与非双刀例外）、browser harness 三视口均 76/76、Launcher xUnit 1257/1257（该领域冻结时历史树）；Flash 必须取得 `CraftingPanelServiceTest` 27/27 fresh Output Panel 后才能称 TestLoader 通过。
  Native HUD 材料直达现已进入同一 domain 的 `materials/materialDetail` 两个只读命令，由 `crafting-materials.js` 以 `44:56` 双栏显示持有量、怪物/关卡来源和配方/装备用途且不保留旧页 fallback。现役 browser 基线为三视口各 **119/119**；tracked TestLoader 契约已扩为 `CraftingPanelServiceTest 36/36`，新增 omitted token legacy envelope、合法 token exact echo 与显式畸形 token 零发送，必须取得本轮 fresh Output Panel/trace 后才能声称 Flash 套件通过。上一段 **76/76、27/27** 是材料增量前记录。
  上述“本地打开 workbench”仅指在 exact crafting instance 内挂载整理子路由，不调用 Host `Panels.open("workbench")`、不改变 owner/instance/pause；只有显式“返回合成”恢复。普通关闭、Host close、lazy dependency 或 mount 失败都关闭 crafting owner。这里“不共享 lease”只指 inventory authority lease 不与合成写 token 共用，不是另建 Host pause lease。
- **skills**（独立技能管理）: `web/modules/skills-runtime.js` + `web/modules/skills.js`；刘海屏与教师入口都进入同一独立 domain，Web 业务命令只允许 `snapshot/learnPreview/learnCommit/equip/unequip/moveSlot/setPassive/reorder`。Host 严格接受七键顶层 envelope `{type,panel,domain,cmd,callId,panelInstanceId,payload}`，业务字段只允许放在 `payload`，并以 active/candidate/return 实例租约阻止迟到旧面板写入。`switch_manage/switch_trainer` 是独立 panel-control：只接受当前相应 view 实例与 exact `{v:1,focusSkillKey}` 嵌套 payload；trainer session 在往返期间只存 Host，教师来源 manage 仅获 `canReturnTrainer` 投影，learnToken 不跨 view，关闭/断线清理暂存能力。NativeHud manage 不获得返回教师入口。AS2 `SkillPanelService` 重建完整 TrainerEntry、检查重复物理技能行并 fail-closed、按 expectedRevision 裁决写入；教师能力只由 NPC 入口签发并继续强绑定 NPC/场景/目录签名，寿命语义为连续 120 秒无成功教师域请求，合法 snapshot/preview/commit 刷新 `lastTouchedAt`，close/rebind/断线仍立即撤销；未学技能仅允许学到 1 级，纯被动不进入快捷槽。展示层复用 `GridDensityController` 的完整/紧凑偏好、`FilterNavigator` 的按钮/计数/键盘 primitive、`PointerDragController + InteractionBroker` 的 ghost/有效或拒绝落点，以及 `PanelTooltip.convertAS2Html` 的安全注释链；manage 不再常驻详情栏，改为全宽技能库 + 1—12 连续单排技能带。完整/紧凑明确只作用于技能库：紧凑技能格与 owned item grid 共用 `48px` 格、`40px` 图标和 `4px` 间距，完整卡共用 `68px` 高度节奏；Hotbar 固定为居中的 `12×64px` 方槽、`48px` 图标和 `3px` 间距，使用连续低对比底板，键位/槽号/等级分层，正常态始终显示等级，卸载控件仅在悬停/聚焦时替代等级角标；技能仍保留青色状态语义。拖到快捷槽与点击装备共用本机安全/快速策略：安全模式空槽直装、替换需确认，快速模式直装/直换；卸载同样由该偏好裁决，技能点学习确认始终保留。快捷槽互拖走单条 `moveSlot(sourceSlot,targetSlot,expectedRevision)`：空目标移动、占用目标交换，不拼接 equip/unequip，也不弹确认；拖到另一个技能格走既有 reorder 交换；已装备目标、普通模式已装备源和异常行排序落点拒绝，EasyMode 只放宽已装备源。常驻上移/下移退役，`Alt+↑/↓` 保留键盘兜底。Skill 不使用物品目录 branchTree：形态、manage 配置或 trainer 学习、流派三组 direct facet 永久并列，任一选项首击即筛选，跨组可组合并可一键清除；武术、剑术、枪术、内功、神功、科技、超能力、投技、龙吼按真实 `Type` 存在性显示，无流派条目留在“不限”。名称搜索默认收起并支持 `/` 展开、Esc 清除；manage 不显示 metric，trainer 只保留等级/技能点，稳定同步、revision、常驻刷新和协议术语退出常态玩家界面。异常时才显示重试/确认结果与诊断复制，复制记录保留实例/revision/callId/reconcile 且排除 trainer session/learnToken。通用 L/R slot marker 在 Skill 中只做视觉隐藏，slot/ARIA/焦点语义继续存在；manage 顶栏在“技能库 完整/紧凑”旁以独立二选一分组常显只存于 `localStorage` 的“快捷栏｜安全/快速”，切换零业务传输并以 toast 明示后果；trainer 不显示该快捷栏专属控件。顶栏 `?` 纯按 manage/trainer 说明点击、三类拖拽、快捷槽 `Alt+←/→`、技能格 `Alt+↑/↓`、卸载、被动、筛选/搜索、两种确认规则、初学等级、自动消耗预览和页面切换，不再承载设置入口，开闭零传输并恢复入口焦点。技能选择按稳定节点原位更新并保留列表滚动与实体焦点，键盘重排后焦点实体保持可见；trainer 选技能或调目标等级即以 debounce + latest-wins 自动预览，常态“计算消耗”按钮退役。已学技能目标改用 step=1 的离散横向 range，可直接点中间刻度、拖动、精确输入或用方向键/Home/End；`− / +` 仅微调，“升 1 级”退役，“升至满级”保留。拖动/输入期间只本地更新目标，保留并灰显上一份权威消耗，松开或确认后只请求最终等级；右侧决策栏常驻技能说明、目标等级、权威消耗、研习后余额与门槛原因，主动作固定显示目标与点数。30 秒 learnToken 在确认前按 25 秒新鲜度门静默重取，学习确认仍不可绕过；`trainer_session_expired` 保留当前目录和最后快照，显示重新对话的可解释终态，不自动关闭面板。物品 taxonomy、AS2 facets、lease 或 authority 仍不复用。未知写结果进入 `needs_reconcile`，只有进入该状态后新发起且越过 watermark 的完整 snapshot 才能解除；关闭时由 Host 经 `skillPanelClose` 下发 cleanup，不属于 Web 业务 cmd，不同实例/作用域的 cleanup 会收敛成 global cleanup，视觉关闭后仍在后台重试对账。自动门：browser harness 132/132（1024×576、1366×768、1920×1080）、ItemFilter 22/22、物品格视觉 17/17、KShop 91/91、Launcher xUnit 1257/1257（该领域冻结时历史树）、tracked runner contract `SkillLoadoutServiceTest` 50/50 + `SkillPanelServiceTest` 48/48；main、物品技能 UI、玩家信息 UI、things 均已独立发布且 FFDec bridge 标志齐全。NativeHud `SKILLS` 已由真实 Win32 中心点击在常规、生产最小、4:3 letterbox 与 1920×1080 物理面板重复打开旧版 manage，权威 snapshot/ESC cleanup 成功且稳定态专用存档哈希不变。正式地下室场景中，人类真实点击 `The Girl → 学习技能` 打开旧版 `技能研习`，目视目录为 `兴奋剂 / 能量盾`；此前 trainer→manage same-panel rebind 也已完成。新布局与 manage→trainer 返回目前只有自动 DOM/几何证据，尚未新增真机目视结论。旧技能页 slot0/slot1 的 live 互斥 depth 指纹又确认实际命中 main `DefineSprite 53`，不是 things id2706。生产 Gate 现仍缺 legacy fallback 事务等价/重启回读、legacy Notch/fallback、pending-write/断线真机记录；闭合后才开始 S6 的 7 天、100 次管理入口与 30 次教师入口观察样本。
  技能库与其他带 density 控件的生产视图一致：无已保存偏好时首次默认紧凑，玩家明确保存的 `full|compact` 仍优先；当前三视口 browser 基线为 **150/150**。
  Character-return 与 trainer-return 是互斥来源能力：前者只属于 Character→Skills 交接生成的 exact manage instance，Web 只见 `canReturnCharacterBuild` 展示位并通过显式 close reason 请求；后者只属于 trainer→manage rebind，Web 只见 `canReturnTrainer`。Notch 直开的 manage 两者都没有。任一 close/rebind/navigation/reload/disconnect 都清理未绑定/已绑定 capability；Web 夹带布尔值、stale instance 或普通 Esc/backdrop 不能取得返回权。

  - 2026-07-28 该日施工树自动门为 KShop `111/111`、NPC Shop `89/89`、Launcher xUnit `1651 通过 + 1 opt-in 跳过 / 1652 总计`、Panel runtime `27/27`、Panel contracts `62/62`（4 domains / 23 commands）、共享 components `12/12`、inventory modules `15/15`、Skill policy `65/65`、Skill browser 三视口各 `148/148`、Crafting 三视口各 `99/99`、Character Build production `642/642 + 4/4 hidden-body`、standalone `195/195`、dressup `211/211`、tuning 三视口各 `83/83`；strict UI audit 为 `0 error / 0 warning`，CSS bundle 为 18 imports / 17,795 lines / 667,554 bytes / SHA-256 `3edf4d9adf25da206aa991336d3a58f4abb51fecd9c08e82e8ab9cd0d371161e`。上一段的 KShop `91/91`、Launcher `1257/1257` 以及 2026-07-29 B0 冻结的 `1737 + 3 / 1740` 都只是领域/日期历史树；当前 Launcher 全量统一看本节第 885 行的 `1902 pass + 3 explicit opt-in skip / 1905` 口径。Character/Notch manage opener 的 Skill AS2 为 fresh `50/50 + 48/48`，角色构筑六套为 fresh `533/533`，compiler 均 `0/0`；本轮材料/情报 focused TestLoader 已取得 EquipmentInventory `28/28`、NPC `46/46`、Inventory `142/142`、Crafting `34/34`、compiler `0/0`、32K retry `0` 的 fresh trace。最终业务 initData 固定无 `trainerSession/canReturnTrainer`，只管理自身技能，Character 来源可另有无权限的 `canReturnCharacterBuild` 展示位。AS2 只对旧 Host 缺 token 的 `nativehud/manage` Skill opener 保留临时单向兼容；workbench 与材料路由无兼容，Host/SWF 必须配对部署。本轮 publish-only `scripts/asLoader.swf` 已刷新为 1,064,450 bytes / SHA-256 `7ABDAE15848FF516A622142D75A630FA6A8783AA541C1B4DFBB6BC7B81451BD8` / 9,719 functions / 最大 46,025B，Compiler Errors/Warnings `0/0`；独立 `物品与技能相关界面.swf` 已刷新为 65,521 bytes / SHA-256 `C92BEAF595A751171C13D6F8EC75C7F4A4A38E1698AB7A517581DEF69CF5403C`，并以 FFDec 确认退役材料 flag/提示串不存在且直接导航仍在。既有 K3 最高 thinking session `bc2345d4-42eb-47aa-9b03-5ea627bd5e3c` 只审查此前冻结的双向导航树，不覆盖本段新增 UI 施工；这些自动门也不等于 candidate、E2E、promotion 或标准入口验证。证据见 [双向导航关闭索引](../docs/evidence/character-build-skills-bidirectional-navigation-closure-2026-07-28.md)。
  - 2026-07-26 教师目标等级的 Web 本地上限改为 `min(MaxLevel, currentLevel + floor(skillPoints / UpgradeSP))`。range、数值框、刻度、微调与快捷目标共用该上限；SP 不足一级时显示不可升级且不发 preview，零费升级仍可到元数据上限，未学技能仍固定 Lv.1。切到不可升级技能会取消上一技能尚未触发的 preview debounce 并隔离迟到回包，避免旧技能沿用新目标等级。快捷目标按实际结果显示“升至满级”或“升至可负担最高级”；AS2 preview/commit 继续权威重算费用并防御状态漂移。纯策略回归 `47/47`，三视口 browser harness `132/132`。
  - 2026-07-16 观察期原生快捷技能 HUD 同步修复：`SkillLoadoutService.projectQuickSlotRenderer` 在替换时强制“空 → 默认图标”重建 attachMovie 图标壳，卸载时清空名称/数量/行号/CD/MP/图标并停在空帧，解决“等级归零但旧图标残留”。该 renderer 只是可选显示投影，不反写 root 槽位/技能行，不重置手动冷却；本轮只需重发 `scripts/asLoader.swf`，未修改玩家信息 XFL。
- **help**（游戏帮助）: 纯 Web 侧 Markdown 帮助面板，无面板专属 AS2 清理命令；仍走统一 Web Panel 生命周期，打开时发 `webPanelPause`、关闭时发 `webPanelUnpause`
- **map**（地图面板）: `web/modules/map-panel.js` + `web/modules/map-scale-policy.js` + `web/modules/map-canvas-stage-renderer.js` + `web/modules/map-panel-data.js` + `web/modules/map-fit-presets.js`；纯 Web panel，走 `panel/panel_resp` 的 `snapshot` / `refresh` / `navigate` / `open_stage_select` / `close` 协议；当前 `snapshot` 额外承载 `unlocks / hotspotStates / currentHotspotId / markers / tips`，四个正式页面的舞台视觉由 Canvas 2D renderer 绘制（DOM 仅保留透明热点、hover 标签、右侧 rail 与操作按钮），右侧层级按钮缺少原始素材时允许直接使用 Web/CSS 复刻旧视觉语言；`map-panel.js` 会懒加载 `stage-select-data.js`，用 `RootFadeTransitionFrame` 为已解锁且有选关页签的热点提供二级“选关”动作，成功后交给 PanelHost 关闭 map 并打开 `stage-select`，主热点点击仍发送 `navigate`；舞台保持 1031×608 逻辑坐标，但不再固定卡在 1.3，而由 `MapScalePolicy` 联合 viewport、生成态 source-ratio capability、DPR 与两个全 DPR 静态 backing store（可见背景 + backdrop cache）的总像素预算动态收敛（产品异常上限 1.75）；位图清晰度按 `stageScale × contentFitScale × DPR / sourceRatio` 的物理像素倍率裁切，再按 page/filter preset 做二次 content-fit；地图 page/composite/avatar/roommate 运行时资产统一为经 RIFF chunk 解析确认 `VP8L` 的无损 WebP，WebView2 直接消费。Native HUD 由 `MapHudImageDecoder` 通过 SkiaSharp 把当前 hotspot 工作集直接按最长边 512px 解码进 premultiplied BGRA `System.Drawing.Bitmap`，不依赖系统可选 WebP codec，也不创建中间全尺寸 `SKBitmap` / `byte[]`；decoded/tinted 缓存分别使用 24/12 MiB 的按像素字节 LRU，淘汰时释放 GDI 对象。FFDec composite 重导仍以 PNG 为中间帧并由 `tools/convert-map-assets-webp.py` 自动转换；真源 composite 可用 `tools/export-map-composite-assets.ps1 -Page <page|all> -Zoom <1..8> -Asset <name,...>` 选择性重导，随后必须 `node tools/tune-map-filter-fit.js --write` 更新 capability。2026-07-16 已按审计将 7 张瓶颈图重导为 4×、`union-university` 重导为 5.5×；不对缺冻结真源的 `fallen-entrance` / `subway` 插值。开发链同时支持 browser harness `web/modules/map/dev/harness.html`、preview `web/modules/map/dev/preview.html`、builder `web/modules/map/dev/builder.html`、CLI 导出 `tools/export-map-manifest.js`、fallback 复核 `tools/audit-map-layout.js`、审计图导出 `tools/render-map-audit-sheet.py` 与可选的 Kimi 视觉复核 `tools/kimi-map-review.ps1`；右上角常驻 HUD 由 `web/modules/map-hud.js` 消费同一份 `MapPanelData` + UiData `mm/mh`，只显示当前区块高亮与固定 beacon，点击后打开 map panel
  - 缩放体验由 `focus / horizontal / vertical / overview / dense` 五类 profile 驱动，内部 content-fit 异常护栏最高 4.5，但外层 stage 与物理清晰度上限仍为 1.75；两个静态 backing store 共用常规 10M / 低资源 6M 像素总预算；`tools/audit-map-scale-experience.js` 固定检查全部 18 filter 的 324 组 viewport/DPR/effects 矩阵。当前 capability debt 白名单仅为 `defense:all`、`defense:first_line`、`faction:fallen`，对应缺真源的 `subway` / `fallen-entrance`，出现其他债务会失败。瞬态任务环、marker、tip 不进入 camera bounds，避免状态刷新跳镜；可选视觉复核脚本默认调用 Kimi Code 高速模型。
- **stage-select**（选关界面 Stage 2 runtime）: `web/modules/stage-select-panel.js` + generated `web/modules/stage-select-data.js`；可通过 Native HUD “系统 → 其他 → 测试 → 选关测试” 的 `STAGE_SELECT_TEST` 打开，也可由 AS2 场景门 `openWebStageSelect` → `panel_request stage-select` 正式打开。支持 16 个 frame label、182 个源 XML 入口实例、164 个 Web 运行时渲染实例（含 13 个 `entryKind=map/task` 直达入口）、fixture 锁定/任务/挑战模式、按外部 PNG / 内部命名帧 / 默认帧回退的 hover 预览、browser harness 和 FFDec/Web 视觉对照审计；runtime 下使用 `stageSelectSnapshot` 读取真实解锁/挑战状态，普通难度按钮通过 `stageSelectEnter entryKind=difficulty` 进入已解锁关卡，外交地图按原版绿色点直达、从源符号内部 `shape/外交地图点` / `DOMDynamicText` 矩阵复原点和文字位置、通过 `entryKind=map` 走 AS2 淡出跳转且不显示二次选择，旧外交地图 SWF 内仍指向 Flash `关卡地图` 的门由公共 `切换场景` 捕获后打开 Web 选关，`地图-*` frameLabel 会按 `StageInfoDict.RootFadeTransitionFrame` 反查回选关页签，魔神/副本任务区域把 `Symbol 3325 -> Symbol 3323 -> bitmap3321` 导出的法阵底图放在装饰层，文字按钮仍按 XFL 源矢量 CSS 复刻，`entryKind=task` 改发 `openWebDungeon` 跳转 Web `tasks` 面板副本 tab（旧 Flash `委托任务界面` 已退役删除；`StageSelectPanelService.handleEnter` 走 closePanel:false 重定向），`localFrame` 通过 `jump_frame` / `stageSelectJumpFrame` 同步 Web 当前选关页但不改 `_root.关卡地图帧值`，return 类 nav 通过独立 `returnFrameLabel` + `return_frame` / `stageSelectReturnFrame` 复刻原版 `_root.淡出动画.淡出跳转帧(_root.关卡地图帧值)`，同场景返回会直接关闭 Web panel、跨场景返回仍淡出跳转，避免旧外交地图底层场景泄露。runtime 布局隐藏测试标题、fixture/dev 控件与右侧空栏，frame tab 默认收纳到可展开区域菜单，旧 Flash `关卡地图` 保留为 fallback
- **intelligence**（情报详情面板）: `web/modules/intelligence-panel.js` + `web/modules/intelligence-components.js`；正式入口为 Native HUD / 旧 Web notch 主工具栏的 `情报` / `INTELLIGENCE`，Native HUD 开发入口 `系统 → 其他 → 测试 → 情报测试` / `INTELLIGENCE_TEST` 保留。正式 runtime 走 `state` → `snapshot(itemName)` → `tooltip(itemName)`：AS2 只返回每条情报收集值、解密等级、玩家名和 TooltipComposer 富文本，C# `IntelligenceTask` 从字典、物品 XML 与 `data/intelligence_h5/<itemName>.json` 读取白名单 H5 正文，Web 不直接 fetch 项目根或 `data/`。H5 正文由 `IntelligenceComponentRenderer` 以 DOM API 渲染，锁定页不下发 blocks，关闭时不通知 Flash。协议、组件语义、手工创作流程和验证门禁见 [情报 H5 组件创作交接](../docs/情报H5组件创作交接.md)
- **tasks**（任务界面）: `web/modules/tasks/task-panel.js` + `css/task_panel.css`；入口为刘海屏 Native HUD 右侧 `任务` 键（`TASK_UI`，含 notice-bar 回退）以及旧 Web notch “新任务界面” `NEW_TASK_UI` —— 两者已在 `LauncherCommandRouter` 合并，先发 `taskPanelOpen` 再打开 `tasks` panel，不再走 AS2 `openTaskUI` 唤起。运行态协议为 `snapshot` / `detail` / `tooltip` / `finishTask` / `deleteTask` / `navigateFinish` / `treeState` / `replayDialogue`，`TaskTask` 桥接到 AS2 `TaskPanelService` 的 `taskSnapshot` / `taskDetail` / `tasksTooltip` / `taskFinish` / `taskDelete` / `taskNavigateFinish` / `taskTreeState` / `taskReplayDialogue`，response task 为 `task_response`。snapshot 的 `satisfied` 字段复用游戏内交付权威判定 `_root.taskCompleteCheck(index)`，同时覆盖关卡、提交/持有物品与特殊需求，禁止仅用 `requirements.stages.length` 推断完成状态。**共享判定条件（`conditions`，2026-06-11 判定层共享）**：任务数据可选字段 `conditions:[{type,params,target,label,sinceAccept?}]`——与成就共享 `ObjectiveEvaluator.rawOf` 的 9 类指标（枚举单源 `tools/lib/objective-types.js`），任务由此获得「击杀 N 敌人/花费 N 金币」等成就级表达力；`sinceAccept` 窗口语义由 AddTask 拍基线进 `requirements.condBase`；`taskCompleteCheck` 与老字段合取；`detail` 回 `conditions:[{label,cur,target}]` 进度行（web 渲染 cur/target+进度条）；含 conditions 的任务借成就 `scanTick` 10s 心跳刷新红点（无事件指标如击杀数才能翻转达成态）。生命周期/奖励链不共享，详见 [docs/任务成就-判定层共享-设计-2026-06-11.md](../docs/任务成就-判定层共享-设计-2026-06-11.md)（§8 为 V8 判定下沉草案，未开工）。物品 `tooltip` 为 name-keyed，AS2 调 `_root.Web物品注释HTML` 返回 `introHTML/descHTML/itemType`——物品类型字段必须叫 `itemType`，**不可用 `type`**（会覆盖 `panel_resp` 信封的 `type`，Bridge 按 `data.type` 路由会整条丢包）。**写操作（交付/删除，2026-06-08 WS5）**：前端一律传 `taskId`（稳定主键）**不传 index**——AS2 `FinishTask/DeleteTask` 会 `splice(tasks_to_do)` 致 index 偏移，AS2 端按 `taskId` 解析当前 index；交付走 `_root.taskCompleteCheck` 服务端硬门控（`FinishTask` 自身不校验完成度，原版门控在 NPCTaskCheck），背包装不下回 `inventory_full`；删除拒绝主线（`cannot_delete_main`）；两类回包都附带刷新后的 `tasks` 概要（与 snapshot 同形状），前端 `applyWriteSnapshot` 按 `taskId` 原子重渲并尽量保留选中；删除请求在途时弹窗取消/遮罩被 `_busy` 锁屏蔽（防"以为取消却被删"）。**远程交付门控（可选玩法增强 `finish_remote`）**：任务数据新增布尔字段 `finish_remote`（`data/task/*.json`，缺省 false），仅标记为 true 的任务允许面板「交付任务」直接远程交付；其余任务保持原版玩法——必须前往 `finish_npc` 处由 NPCTaskCheck→FinishTask 交付，面板按钮显示「前往「NPC」交付」禁用态，AS2 对非远程任务回 `requires_npc`（服务端硬门控，NPC 交付路径不经 handleFinish 故不受影响）；`detail` 回包附 `finishRemote` 供面板决定按钮态。**前往交付（便利增强 `navigateFinish`，2026-06-09）**：非远程任务的主操作按钮变为「前往交付」——复用地图 `MapTaskNpcRegistry`（finish_npc→hotspot）+ `MapPanelService.canNavigateToHotspot/navigateToHotspot` 把玩家一键送到交付 NPC 的地图位置（只负责前往，到达后仍由玩家点 NPC 正常交付）；可达性 = 非战斗地图 + 热点已登记 + 所在组解锁，`detail` 回 `finishNavigable` 决定按钮可点态（可前往=「前往交付」可点，不可前往=「前往「NPC」交付」禁用），成功回 `closePanel:true`（前端关面板让场景淡出跳转），不可达回 `not_navigable`。前端（2026-06-08 UI/UX 升级）含：五类筛选 chips（主线/支线/副本/情报/其他，由 `chain[0]` 链名在前端 `CATEGORY_MAP` 归并）、卡片/列表双视图、排序、计数概览、detail 缓存、骨架屏、富物品 tooltip（复用 `PanelTooltip`，缓存+失败退避）、转圈→勾选可交付徽章、常驻扫光等入场动效与 `prefers-reduced-motion` 降级、详情底部交付/放弃操作区 + 放弃确认弹窗 + 操作锁；**功能层配色统一黑白灰，焦点橙只留给提交NPC卡，难度色为原版语义真值**。**事件日志 / 任务树 Tab（WS6，2026-06-09）**：「事件日志」tab 渲染链式任务树 + 剧情对话回放。数据按可变性切分单一权威：**静态目录**（树拓扑 + title + description + 明细字段）由 **build Step 1e** 经 `tools/derive-task-catalog.js` 从 `data/task/*.json`（游戏权威源）派生为 `web/modules/tasks/task-catalog.json`，web **直读零 AS2 传输**（派生器含闭包校验器：title/description/get_conversation/finish_conversation 的 `$KEY` 必须存在于合并 `task_texts`，否则 build exit 1）；**动态进度**经只读命令 `treeState`→AS2 `taskTreeState` 回 `chainsProgress`+已完成 id 集 `finished`+进行中 id 集 `active`（载荷极小，非全表）；**剧情对话回放（Web 立绘组件）**经 `replayDialogue {taskId,which}`→AS2 `taskReplayDialogue` 按需回传【单条任务】的对话文本行 `lines:[{speaker,sub,text,char,charBase,expression,portraitType,target?,imageurl?}]` + `heroPortrait`（name/title 经 `getDialogueSpecialString` 解析 `$PC` 等特殊串），web 在详情区内联展开对话、**不关面板（体验连续）**。`speaker/sub/text` 经共享 `PanelTooltip.convertAS2Html` 渲染 **AS2 htmlText 子集**（`<FONT COLOR/SIZE/FACE>`→span style、`<B>/<I>/<U>`、`<BR>`、`<P ALIGN>`，含颜色/字号/face 白名单校验，安全）——例：`$PC_TITLE`→`HeroUtil.getHeroTitle()` 回的 `<FONT COLOR='#FFCC00'>动态称号</FONT>` 正确着色。对话文本仍单权威留 AS2（catalog 只含 `hasGetConv/hasFinishConv` 布尔，点击才按需回传一条任务的对话，载荷小、懒加载）。**刻意不支持**（留待对话框整体迁 web 的富文本阶段，避免现在引入复杂度/风险）：`<A HREF>`（asfunction 无法 web 执行+安全）、AS2 htmlText 内联 `<IMG>`（立绘改走结构化字段 + `dialogue-portraits` manifest）、`<TEXTFORMAT>`、`<LI>`。树节点状态=已完成/进行中（由进度叠加判定）；明细复用 mine 详情结构（read-only，无交付/放弃）。**图表视图（BALDR SKY 风，2026-06-09）**：事件日志内「列表/图表」切换，图表以六边形节点（CSS clip-path）+ SVG 前置连线空间化呈现任务链的**前置依赖关系**（弥补列表线性、看不出任务线前置顺序的短板）。布局=「拓扑深度分行 + 按链分列 + 前置连线」（数据实证为主干+分支结构，237/238 单前置、跨链边多为主线里程碑→侧链入口，故无需重型 DAG 算法；委托等无序号链不入图）；状态色黑白灰真值（已完成银/进行中白发光/未解锁暗），选中=白环放大（不动焦点橙）；**任务线配色**经三杠杆区分——外环色 `--hex-rim`（链身份主区分）+ 数字色 `--hex-num` + 可选面色 `--hex-face`（阵营链黑底白字），由 `CHART_CHAIN_STYLE` 配置下发（**写手可改**，状态与链色正交：状态只驱动面色+辉光，链色走环/数字不抢读）；**对话回放按进度门控**（接取对话仅已接取显示、完成对话仅已完成显示，不剧透未到达剧情）；含 100/50/25% 缩放（CSS zoom）与详细/章节双粒度（章节折叠线性段、仅留链头尾+分支/合并点+进行中）；**左键拖拽平移取代滚动条**（隐藏滚动条、grab/grabbing 光标，保留滚轮；「点击 vs 拖拽」按 4px 阈值判定，拖拽末尾 click 被抑制不误选节点）；点节点复用同一明细+内联对话。catalog 为此加回 `req`（前置 id，画边+算深度，约 +3KB）。详见 [docs/web-task-panel-WS6-事件日志任务树-设计-2026-06-09.md](../docs/web-task-panel-WS6-事件日志任务树-设计-2026-06-09.md)。验证：dev harness `web/modules/tasks/dev/harness.html`（`?qa=1` 跑 task-ui1~45 + ach-ui1~13，含写操作门控/交付移除/放弃确认/背包满/ESC modal栈/远程交付门控+绕过按钮服务端门控/删除在途锁/前往交付/finishNavigable 不缓存固化/**事件日志树渲染+对话按钮可见性+回放内联文本（不关面板，远程交付成功才关面板露原版奖励/对话）+tab往返+图表视图+XSS清洗+图表防剧透+服务端对话门控+副本委托对话完整立绘/缩略模式切换+按行顺序渲染**）+ `node tools/run-tasks-harness.js --qa|--shot=...&--query="tab=log|tab=ach"`（Edge headless）+ `TaskTaskTests.cs`（xUnit 26 facts，含「Web 夹带 action/task 不可覆盖可信 action」安全反向用例及成就桥 7 用例）。`finishNavigable` 为 AS2 动态计算，前端缓存静态详情但对其做有界后台复查（仅"满足+非远程+当前不可前往"时重选复查），不被缓存永久固化。close 会发 `taskPanelClose`（当前 AS2 no-op），不写存档。**成就 Tab（A 轮 2026-06-10）**：tasks 面板第三 tab「成就」，实现于独立文件 `web/modules/tasks/achievement-tab.js`（panels-lazy-registry deps 先于 task-panel.js 加载；task-panel 经 `TaskAchievementTab.install/reset/enter` 装配，claim 在途复用 `_busy` 锁拦切tab/关面板/二次点击；样式追加进 `css/task_panel.css` 不新建 css）。**静态目录** = build **Step 1f** 经 `tools/derive-achievement-catalog.js` 从 `data/achievement/*.json`（成就权威源，manifest `data/achievement/list.xml`，AS2 `AchievementDataLoader` 读同一源）派生 `web/modules/tasks/achievement-catalog.json` web 直读；派生器校验（失败 build exit 1）：objective 枚举白名单（infraLevel/infraBuiltCount/killTotal/taskFinished/chainProgress/skillLevel/itemOwned/economyCount）、跨域闭包（taskFinished.taskId ∈ 任务集；chainProgress 链存在且 target ≤ 链最大 seq）、economyCount counter 白名单=**正则解析 `AchievementMetrics.as` buildValid 函数体单源**（AS2 类编译器不接受对象字面量字符串键，故 .as 用 `v["键"]=true;` 赋值式——解析与之配套，格式勿改）、claim.mode 仅 remote 且条目含 `finish_remote` 字段即 fail、rewards 黑名单{经验值}+单条禁同名重复、title/description 禁 `$` 前缀；**hidden 条目脱敏输出**（title/description="???"、rewards=[]、objective 剔 params——明文含奖励仅经 AS2 `hiddenReveals` 对已解锁条目按需回传，防剧透双层）。**动态状态**走 `achievementState`（只读叠加 unlocked/claimed/progress/hiddenReveals/dataReady；hidden 未解锁条目不回 progress 防可探测）；**领取**走 `achievementClaim {achievementId}`（稳定主键非 index；**全称命名**——裸名 `claim` 会被 WebOverlayForm 在 panel 判别前无条件路由 ShopTask）。AS2 `AchievementService` 门控链：not_ready / achievement_not_found / not_unlocked（unl 锁存位图‖现算，服务端权威不信 web）/ already_claimed（幂等位图）/ inventory_full（acquire 全有或全无失败时**不置 claimed 保持可重试**），成功置位严格在 acquire true 之后，每分支回包并入完整状态叠加供 web 原子重渲；**奖励 toast 在 web 面板内渲染**（不走 AS2 任务奖励提示界面——overlay 遮挡 Flash 弹窗）。四态徽章 locked/inProgress/unlocked(领取钮+红点)/claimed(灰勾)+进度条（双端封顶 cur≤target，绝不出 NaN）。设计与施工记录：[docs/成就系统-A轮-设计-2026-06-10.md](../docs/成就系统-A轮-设计-2026-06-10.md)、[docs/成就系统-A轮-施工-2026-06-10.md](../docs/成就系统-A轮-施工-2026-06-10.md)。
  - 事件日志对话立绘（2026-06-20）已从“轻量内联文本”升级为可复用 Web 对话组件：AS2 `taskReplayDialogue` 继续回 `speaker/sub/text` 兼容字段，同时新增 `char/charBase/expression/portraitType/target?/imageurl?` 与 `heroPortrait`；Web 端由 `web/modules/dialogue/dialogue-view.js` 渲染，NPC 立绘走 `assets/dialogue-portraits/manifest.json` 的 PNG，主角走 `DressupDollRenderer` + 当前装备/脸型/发型快照。`speaker/sub/text` 仍经 `PanelTooltip.convertAS2Html` 清洗渲染；AS2 htmlText 内联 `<IMG>` 仍不开放，立绘只走结构化字段与离线 manifest。
  - 任务 NPC placement 扩展（2026-07-02）：`data/map/task_npc_registry.json` 允许同名 NPC 多 hotspot placement；任务数据可用 `get_npc_hotspot` / `finish_npc_hotspot` 显式指定接取/提交地点，`derive-task-catalog` 会在同名 NPC 多 placement 时硬门控该字段。AS2 `NPCTaskCheck`、地图任务红点、HUD 交付与任务面板 `finishNavigable/navigateFinish` 均按 `NPC 名 + hotspot` 解析；未写 hotspot 的旧任务保持 name-only 兼容。
  - 前线调度板聚合模式（2026-07-10）：仍使用 `tasks` panel，通过 `initData.view="dispatch-board"`、`boardId`、`skin` 切换为场景化界面，不另造第二套选关 panel。`dispatch-board-view.js` 请求 `dispatchBoardSnapshot/detail/briefing/enter`，`mission-brief-view.js` 与副本 tab 共用关卡信息渲染；Web 只负责选择与表现，AS2 每次重查 `dispatch_board` 归属、任务状态和目标关卡后才允许进入。任务入口对白使用独立 `mission_briefing`：调度板禁止回退到一次性 `get_conversation`，旧委托副本暂时保留兼容回退。`dispatch_replayable:true` 的已完成任务继续显示为“复盘案例”，可重进关卡但不重新接取任务、不重复发任务奖励。第一防线 skin 使用 `tasks/assets/dispatch_board_first_defense.png` 作为板级稳定垫图。
- **dressup**（对话框主角/战斗纸娃娃预览）: `web/modules/dressup/dressup-panel.js` + `web/modules/dressup-doll-renderer.js`；开发入口为旧 Web notch “其他 → 纸娃娃测试” / `DRESSUP_TEST`。运行态可通过 `initData.gender/equipment/keyMap/appearance` 直接喂给 Canvas 2D renderer，素材来自 `assets/dressup/manifest.json` 的 PNG frame sequence + origin/matrix 元数据，不再依赖 AS2 端 `BitmapData.draw`、XMLSocket 传输或 Flash 位图采样。默认消费对话框 rig；需要战斗模板时传 `initData.rig="battle"` 与 `initData.stateLabel`（例如 `空手站立`）。renderer 会由 `stateLabel` 推断 `攻击模式`（`手枪站立` / `手枪2站立` / `双枪站立`），也可用 `initData.attackMode` 显式覆盖；manifest 中带 `conditionalVisibility.property="攻击模式"` 的素材会在非命中状态使用 `runtimeVariants.neutral`。`measureState/measureEnvelope` 不创建 Canvas、不加载图片也不推进动画，可供消费者预先合并多个状态的纯几何边界；将结果作为可选 `fitEnvelope` 回传后，render 使用同一 scale/offset，未传时保持原逐内容 fit。精确回归入口为 `node tools/test-dressup-stable-fit.js`，通用动效/默认路径继续由 `node tools/run-dressup-harness.js` 与 `node tools/test-dressup-renderer-periods.js` 覆盖。事件日志对话回放已通过 `heroPortrait` snapshot 复用该 renderer；完整主对话框迁移时继续把主角装备快照映射到同一 initData。
- **lockbox**（开锁小游戏）: `web/modules/minigames/lockbox/` 下的正式小游戏模块；支持运行时参数、browser harness、Node QA
- **pinalign**（定位小游戏）: `web/modules/minigames/pinalign/` 下的正式小游戏模块；和 Lockbox 共用小游戏壳层与 QA 平台
- **gobang**（五子棋小游戏）: `web/modules/minigames/gobang/` 下的正式小游戏模块；Web core 负责规则裁判，AI 经 Web→C# `gomoku_eval` 调用 `GomokuTask` / Rapfi
- **team**（战队）: `web/modules/team/team-panel.js` 是唯一生产 Panel，固定标签顺序为佣兵 / 伙伴 / 战宠 / 机械；首次进入伙伴，同一 WebView 会话记忆末次标签，顶层切换会把目标子视图复位到管理列表，写操作 busy 时禁止切换和关闭。`pet-panel.js` 与 `merc-panel.js` 是可嵌入子控制器，不再独立注册 Panel；它们继续发送 `panel:"pets"` / `panel:"mercs"`，复用现有 `PetTask` / `MercTask` 与 AS2 写操作。统一 close 为纯 Web no-op，不调用有旧 Flash UI 重排副作用的 `petPanelClose`。旧命令 `PETS` / `MERCS` 仅作为隐藏兼容入口打开 `team` 的伙伴 / 佣兵标签。**壳层形态**：team-panel 是薄协调器，不渲染独立顶栏/画布（外套顶栏会把子面板压进 1024×518 触发二次缩放与黑边）——唯一一条 tab 条（`.team-tabs`）在切换时整体迁移注入激活子视图列表页 header 的 `.team-tabs-slot`（替换「战宠管理/佣兵管理」标题位；A 兵团徽标、资源条、关闭钮由子面板自有 header 承载，关闭路径经 `TeamPanelHost.requestClose` 收口）。
- 宠物域的伙伴 / 战宠 / 机械共享同一宠物池、容量与出战配额，分类权威来自 `data/merc/pets.xml` 的 `RosterType`；`pet_lib` / `adopt_list` 下发 `rosterType`，类型化 `adopt_list` 只返回非空原始分类索引。
- 佣兵子视图视觉对齐战宠战术风：独立样式 `web/css/merc_panel.css`（背景垫图 `assets/bg/official-bpk.jpg`，固定 1024×576 画布 + `--merc-scale` 整体缩放与战宠一致；panels.css 旧佣兵块已删）。卡片 2 列横版：与战宠卡同高（150px）、双倍宽度（488px），装备 11 槽收进一行；**技能不上卡**（数量不可控）——选中卡片后由底部详情栏（对齐战宠 selbar）展示技能图标流（32px 占位规格同装备，素材未采集前以技能类型首字占位）+「培养」入口；「培养」页对标战宠进阶页：性格六维条（主导维度标记）+ 技能全量列表 + 装备调配 11 槽（「更换」按钮禁用占位，为后续装备更换功能预留空间）；雇佣页同样走选中→详情栏看技能；解雇走面板内确认弹窗。**雇佣页为无缝下滑**：滚动触底自动拉下一页追加（`hire_list` 分页协议不变），底部哨兵行显示 加载中/下滑加载更多/已全部加载，并带「首屏未撑满自动续载」守卫；雇佣成功后因 AS2 池 splice 导致 poolIndex 位移，必须回第一页重拉。**等级快速定位**：可雇佣兵池在 `MercLibrary.loadFromList` 本就按等级升序（`InsertionSort.sortOn` 列 0），雇佣页顶部 chip（全部/Lv.20+/40+/60+/80+）触发 `hire_list` 带 `minLevel` → AS2 定位首个达标项所在页并覆盖页码（仅 reset 请求携带，翻页顺延不带）；页内精确定位由 Web 端锚定滚动完成；回包新增 `maxLevel`（可见池最高等级）用于禁用超出范围的 chip。佣兵摘要 `gender` 判定按字符串「男/女」（源 `mercenaries.json` 的 gender 字段；旧实现按 1/"1" 判男导致全员显示女，已修）。**禁用按钮语言**：暗色凹陷 + 虚线框（与「浅石牌=可点」彻底区分），雇佣钮禁用时文字直写原因（佣兵已满/金币不足/K点不足）。`mercSnapshot` / `mercHireList` 佣兵摘要新增 `skills`（name/level/type/trait/cooldown/cost/unlock）与 `personality`（勇气/技术/经验/反应/智力/谋略六维有序数组）——由 `MercPanelService` 按 `单位函数_fs_aka_玩家模板迁移.as` 的确定性算法（`初始化可用技能` LCG / `生成随机人格` aiSeed）重算：命中 `_root.技能缓存` 时直接采用游戏内结果，未命中时本地重算且**不回写缓存**（仅展示，不构成战斗权威）；旧 asLoader.swf 下两字段缺失，Web 端兜底显示「技能/性格情报暂不可用」。
- **佣兵纸娃娃预览（2026-06-18）**：`mercSnapshot` / `mercHireList` 佣兵摘要下发 `face` / `hair`（`MercLibrary` 已解析 skinKey），Web 端用 `face/hair + equips + assets/dressup/manifest.json` 重建卡片快照和培养页造型预览；若旧链路或开发夹具下发原始编号，面板会先用 manifest 的 `appearance.faceById/hairById` 归一化。卡片/底栏使用一次性 data URL 缓存，且只绘制 `脸型/发型/面具` 头像 holder；培养页只保留一个 live canvas，造型预览只绘制身体外观相关 holder 并与性格特质左右分栏，避免武器范围裁坏头像或压缩全身预览；manifest item 的 `helmet` 控制头盔压发。旧 `asLoader.swf` 缺 `face/hair` 时降级为性别默认脸型与空发型。
- **佣兵阵亡 / 复活币**：佣兵与战宠机制不同——不耗体力，但战斗阵亡后 `佣兵是否出战信息[i] = -1`（死亡检测写入），必须消耗 1 枚「复活币」（`data/items/收集品_材料.xml` 材料）才能再出战。snapshot 佣兵摘要带 `dead`，快照级带 `reviveCoins`（`ItemUtil.getTotal`）；新增 Web cmd `revive` → C# `MercTask` → AS2 `mercRevive`（校验 -1 态 → `ItemUtil.singleSubmit("复活币",1)` → 置 0=休息位，标脏），`deploy` 对 -1 态回 `merc_dead` 硬拒。Web 端：阵亡卡红框/去彩/「阵亡」徽章，出战位变「复活」（复活币不足禁用），工具栏带复活币计数；培养页 header 同步三态（出战/休息/复活）。
- **战宠战斗属性成长**：`petSnapshot` 每宠新增 `combat`（hp/attack/defense/speed 各为 `{start,cur,max}` 三点采样 + startLevel/maxLevel/difficulty）——`PetPanelService` 与出战实体初始化管线同构：基线按 `_root.敌人属性表[兵种]`（源 `data/enemy_properties` XML）线性插值（生命/攻击 × 当前 `难度等级`），再与 `敌人函数.宠物属性初始化` 同构地在**纯对象 sim** 上重放已达成进阶方案的 `单位进阶执行`（这些函数只读 `this.宠物属性`、只写 this 数值字段，无 MC 依赖；写入只落 sim，不回写真实宠物属性）。战宠培养页「战斗属性」区块渲染成长条：起点 Lv.1 → 当前（填充进度）→ 满级（`_root.等级限制`），已计入进阶加成；兵种缺属性表或旧 SWF 时整块隐藏。
- **arena**（竞技场 DEATH MATCH）: `web/modules/arena-panel.js` + `web/modules/arena-custom-parameters.js` + `web/modules/arena-custom-param-editor.js` + `web/modules/arena-custom-undo.js` + `web/modules/arena-custom-polling.js` + `web/modules/arena-custom-result-view.js`；`Panels.register('arena')`，标准模式按社群档位生成 10 张公开卡（1-5、5-10、10-15、15-20、20-30、30-35、35-40、40-50、50-60、60-100），每次打开 panel 或点「全部重抽」时按档位 `countMin/countMax` 确定本 session 人数、经济与 `expr`，所有标准 / 死线警报隐藏卡的佣兵等效人数最终封顶 4；公开卡按会话固定配比随机落位：7 张佣兵卡、2 张怪物组卡、1 张 mixed 卡，mixed 优先使用真实 meta-team，数据不足时兜底为佣兵模板 + 已知怪物组；公开卡难度代号使用竞技场专属称号风格映射（不直接读取 `data/hero/hero_titles.xml`，避免玩家履历称号与挑战风险耦合）。
  基于 `arenaSnapshot.playerLevel` 额外生成高 1/2 档的 2 张死线警报隐藏卡（超出最高档时封顶到 60-100），死线警报 I 配置范围 1-3 人但混编实际至少 2 人，死线警报 II 固定 4 人，即使同档也用人数区分压力；隐藏混编按等效人数均衡配比：2 人 = 1 佣兵 + 1 怪物，3 人 = 2 佣兵 + 1 怪物，4 人 = 2 佣兵 + 2 怪物；隐藏卡只显示经济与倍率，不显示等级 / 人数 / 对手配置。
  标准 mixed / 死线警报混编的人形侧优先从 `data/merc/mercenaries.json` 派生的普通佣兵池抽取（排除 `hidden:true`），避免剧情 NPC / 彩蛋兵种模板进入常规经济刷取；Web roster 下发 `{kind:"merc", mercId}`，AS2 入场端按本地 `mercs_list` 重建佣兵 tuple。怪物侧优先从 `ArenaMetaRosters.teams` 的关卡拆解真实小队抽取并按 `members[].count` 展开，纯怪物卡同样优先走非人形真实小队；仅当当前等级带没有“玩家已击杀过全部 spritename”的可用小队时，才退回 `factions` 聚合兵种池单体抽样。仅当当前等级带没有可用普通佣兵时，才回退到 `ArenaMetaRosters.teams` 中 `humanoid=true` / `spritename` 含 `主角` 的关卡人形模板；派生数据会保留人形模板的 `data.gender` 作为展示字段，避免把 `主角-男` 这类内部模板名误显示成角色性别。真实刷怪数可高于卡面佣兵等效人数，Web 端单个怪物组展开上限为 12 体，AS2 入场后按 12 活体上限分批补刷更大 roster；UI 对 roster 卡显式区分“等效”“实体”“怪物组”，详情行用 `怪物组 i/n` 标注组内成员，避免把等效人数误读成实际刷怪体数；公开 mixed 至少 1 个佣兵模板 + 1 个怪物组单位，死线警报则按前述均衡比例让佣兵承担主力、怪物提供混沌度；普通佣兵池和 meta-team 都不足时才走旧的人形模板 + 已知怪物组临时混编，仍不足则显示失败态且不降级成纯 merc。
  `ArenaTask` 双层 callId；`arenaSnapshot` 透传 AS2 `_root.等级` 为 `snapshot.playerLevel`，并透传 `_root.killStats.byType` 的已击杀 `spritename` 列表为 `snapshot.knownEnemies`，Web 本地 roster 采样、堕落模式出卡与爬升模式 `pool` 均只使用已击杀过的 `spritename`，AS2 `arenaEnter` 侧再按 `兵种库[type].兵种名` 做同样校验，避免未见敌人提前出现在竞技场；`定制赛` tab 走 `custom_start/status/abort`，赛程代码仍是配置真源但控件已迁入三层编辑页，入口卡只显示当前对阵、费用、状态和确认入口，配置总览负责整局预设、赛程代码、红蓝交换和双方配置卡，单方阵容页负责全量单位目录、关卡参数预设与 roster 编辑；`arena-unit-catalog.js`（`tools/derive-arena-unit-catalog.js` 由 `data/units/units.json` 全量派生，`is_hostile` 只作 UI 标签，`faction` 只作浏览器分组）可手动添加蓝/红 roster，`arena-unit-param-presets.js`（`tools/derive-arena-unit-param-presets.js` 从 `data/stages/**` 的 `Enemy.Parameters` 派生）提供如 P90 跳蚤、M79 铁拳这类关卡参数预设，roster 行内只显示参数摘要与编辑入口，深层参数页支持 JSON 与 `<Parameters>...</Parameters>` XML 片段互转编辑，参数 JSON/XML codec 由 `arena-custom-parameters.js` 承载，参数编辑页 state/render 由 `arena-custom-param-editor.js` 承载，撤销快照由 `arena-custom-undo.js` 承载，后台状态轮询由 `arena-custom-polling.js` 承载，单位浏览器默认按势力折叠分组，搜索实时过滤并自动展开匹配组，滚动到底继续追加渲染；`arena-custom-presets.js` 提供测试群预设并支持整局/单侧随机，单侧配置可保存到 localStorage 后读取到任意一方，怪物图标暂用 `u<ID>` 占位，点击主按钮先显示确认区再委托；inline single-case 委托给 `ArenaCalibrationTask.startSingle`，定制赛结果写 `logs/arena-custom/`，批量标定仍写 `logs/arena-calibration/`；`custom_start` 成功后回 `closePanel:true` 并退出 Web panel，AS2 no-player 标定场由动态交战热点驱动 `斗兽标定镜头` 观战，后台终态由 `ArenaTask` 过滤自有 batchId 后通过 `RequestOpenPanel("arena", initData.mode="custom_result")` 回开独立结算页；结算页 DOM 由 `arena-custom-result-view.js` 纯渲染，确认按钮、全局 `×`、ESC / backdrop 关闭入口都发送 `returnBase:true`，Host 下发 `arenaReturnBase` 让 AS2 返回基地，`custom_status` 仅作调试/兜底查询；可经地图/选关二级动作以 `returnToPanel` 重定向进入，普通 close 不通知 AS2；browser harness 为 `web/modules/arena/dev/harness.html`，无头入口为 `node tools/run-arena-harness.js --browser edge [--case <id>]`
  - `arena-custom-presets.js` 是 `tools/derive-arena-custom-presets.js` 从 `data/arena/meta_teams.json` 派生的待标定组合池：蓝方固定为 `thief-lv30x4` 对照阵容，红方为关卡拆解元战队；`tools/derive-arena-meta-teams.js` 对关卡 Enemy 中出现的兵种全量保留，`is_hostile` 只作为标签，不再过滤 `teams[]` / 定制预设，人形模板仅从自动势力采样池剔除；`Enemy.Parameters` 会进入 `meta_teams.json`、`arena-meta-rosters.js`、定制赛程码、C# 标定命令与 AS2 刷怪 init，但 AS2 最后覆盖 `是否为敌人`、`产生源`、`掉落物=[]`、`不掉钱` 和 `计算经验值`。当前 `launcher/build.ps1` 经 release prepare 会重派生 `arena-custom-presets.js`、`arena-unit-catalog.js` 与 `arena-unit-param-presets.js`，但尚不会先重派生 `meta_teams.json` / `arena-meta-rosters.js`；`derive-arena-meta-teams.js --check` 也只作解析诊断，不证明 tracked 字节同步。触及 `data/stages/**` 时若要闭合 meta-team 链，必须在独立 clean worktree 无 `--check` 运行 meta generator，再运行 custom-presets generator，审核并一并提交三份输出；在该门改成 fail-closed 并纳入 prepare 前，禁止声称 build 已自动闭合全部 Arena 派生物，也禁止手工维护生成物。PlayerInfo 最终 K1 已接受它为不阻断 B0 的既存治理债务，但并未修复这条 Arena 链。
  - 定制赛战场参数进入赛程码与后台标定同一契约：`spawnDistance` 缺省 `650`，`timeoutFrames` 缺省沿用定制赛默认，`blueFormation` / `redFormation` 支持 `line`、`column`、`wedge`、`shield`、`grid`，`formationSpacing` 缺省 `54`。`line` / `column` 使用玩家屏幕语义：横列沿 X 横向拉开，纵队沿 Y 纵向拉开；楔形、前盾后排、网格分别提供三角纵深、前墙 + 后排、X/Y 散点网格。配置总览页只显示战场摘要，战场参数子页用预设 + 安全滑条/按钮写入这些字段，确认页、custom_result、JSONL 结果必须保持一致；阵型验收看 JSONL 的 `blueSpawnPositions` / `redSpawnPositions` 与 `formationAudit`，不靠战斗结束截图判断。`tools/derive-arena-unit-catalog.js` 还会静态扫描 `flashswf/arts/**/LIBRARY/*.xml` 中死亡后 `_root.加载游戏世界人物` + `死亡检测({noCount:true})` 的 Symbol，给单位目录标记 `multiPhase` / `phaseSpawns`；AS2 `ArenaCalibrationService` 在本轮 runner scope 内接管死亡派生单位、登记同 side、禁掉落/经验，并对开局残留或运行中未知战斗单位返回 `contamination`，避免把污染场误记为有效样本。
- **jukebox**（BGM 点歌台）: `web/modules/jukebox/jukebox-panel.js` 注册 `Panels.register('jukebox')`，由 `NotchWidget` 展开区“辅助”行「点歌机」→ `JUKEBOX_EXPAND` → `LauncherCommandRouter.OpenPanel("jukebox")` 触发；右侧不再保留 titlebar。与 kshop/help 等通用 panel 同走完整 backdrop / EX_STYLE / HUD-suspend 序列。沉浸全屏化（2026-06-12）后 PanelLayoutCatalog 对 jukebox 返回全 anchor（不再走 Centered 880×620 子矩形）；`jukebox-panel.js` 改固定 1024×576(16:9) 画布外套共享 `.panel-scale-shell` + `PanelScale.attach` 整体等比缩放铺满全 anchor（双栏控制台：左 Now-Playing 波形/进度/设置，右 曲库 专辑/曲目）。`#panel-content` inset:0、backdrop 兜底深底色（panel 铺满后不可见）。曲库 / UiData 状态在 onOpen 时通过 `cmd:'requestCatalog'` + `UiData.get` seed 当前值，避免晚注册错过历史推送。close 路径收敛：× 按钮 / ESC / backdrop click 三入口共用 `closeLocally`（先 `Panels.close()` 让 `_active` 复位再 `Bridge.send panel close`）——避免 ESC/backdrop 单独走 onRequestClose 时 `_active` 滞留导致下次 open 早 return

#### Jukebox panel harness

浏览器 harness：`launcher/web/modules/jukebox/dev/harness.html`（手动调 viewport / 单 case）。
无头运行：`node tools/run-jukebox-harness.js --browser edge [--viewport 1366x768] [--case <id>] [--headed]`。

覆盖项：面板开闭生命周期、seed 状态渲染、首次 catalog 到达后专辑 chip 对账、曲库/专辑下拉渲染、当前曲目高亮、点击曲目 pending→active、暂停/继续、停止后 STANDBY 待机屏、音量滑条、覆盖关卡BGM / 真随机 / 播放模式切换、磷光主题持久化、LED 状态、帮助弹窗、设置区无滚动条、专辑下拉滚动条风格统一。

#### Jukebox panel 手测

`useNativeHud=true` 启动游戏，进到游戏就绪后逐项验证：

1. **刘海入口与背景包络**：hover 展开 Notch，“辅助”行出现「点歌机 / 地图开关 / 修改器 / 帮助」；FPS 折线背景在 BGM 播放时有低透明度 L/R 包络，暂停后冻结并降透明度；点「点歌机」→ panel 出现；点「地图开关」→ 小地图显示/关闭并以中文 toast 回显；“系统 → 其他”按“控制 / 测试 / 工具”切页，离开并收起刘海后子页不得残留
2. **panel 全屏铺满**：panel 铺满全 anchor 16:9（固定 1024×576 画布由 `.panel-scale-shell` 整体等比缩放，窄窗口同比缩小不重排）——1024×576 anchor 下 1:1、1920×1080 anchor 下整体约 1.875×；panel 覆盖全幅无可见 backdrop dim；Spy++ 验证 WebOverlay hwnd bounds **就是全 anchor**、EX_STYLE 既无 `WS_EX_LAYERED` 也无 `WS_EX_TRANSPARENT`
3. **打开 seed 状态**：当前正在播放的曲目标题立刻显示在 panel 标题区（不是 `未播放`）；catalog 到达后标题旁显示当前曲目所属专辑 chip；音量滑条显示当前实际值；覆盖关卡BGM / 真随机 / 播放模式 选中态正确
4. **曲库列表**：专辑下拉显示所有专辑 + 计数；切换专辑过滤；当前播放曲目高亮 active
5. **选曲**：点击曲目立即切歌；标题更新；进度条归零；含特殊字符（`"` / `\` / 中英混排）的曲名正确发到 AS2（`HandleJukeboxMessage` 已用 JObject 解析）
6. **播放控制**：暂停 ↔ 继续按钮翻转；停止回到默认 BGM，波形区进入带 `STANDBY` 字样的待机屏；进度条拖拽 seek 立即生效
7. **设置**：覆盖关卡BGM / 真随机切换；播放模式三选一切换；AS2 端通过 `setGlobalVolume`/`setBGMVolume`/`jukeboxOverride` 等收到对应命令
8. **帮助 markdown**：点 `?` 弹模态加载 `sounds/README.md` 渲染；关闭模态正常
9. **关闭面板（× / ESC / backdrop 三路径全测）**：右上 ×、ESC 键、点 panel 外侧 backdrop 三种入口都立即隐藏 panel（DOM 即刻消失）+ WebView2 SW_HIDE 回到 idle；任一入口关闭后再次打开 panel **必须 onOpen 正常触发**（不能因 panels.js `_active` 滞留早 return）——验证：关 → 再次展开刘海点「点歌机」重开，UI 应正常 seed 当前 bgm 标题，不是空 panel
10. **重开干净**：关 panel 后再开，**不**显示上一次曲名/进度/音量瞬态（cleanup 已重置 `bgmTitle/currentDuration/progress/wave`；onOpen 重新 seed）
11. **不漏 listener**：30 次 open/close 循环后 launcher.log 无累积；`Bridge.off` 正确解绑（uidata 走 `UiData.off`）
12. **legacy 不污染**：旧 `web/modules/jukebox.js` 已删除，生产懒加载、发布资产门禁与 Web overlay 复杂度审计只引用 `web/modules/jukebox/jukebox-panel.js`；DevTools console 无 `audio` / `catalog` 双重处理日志

无法通过手测验证的回归（如 idle iGPU 下降）走 `Ctrl+G` 探针 + Task Manager GPU 标签人工对照。

- **hairdresser**（基地理发店，Web-only）: `web/modules/hairdresser-runtime.js` + `web/modules/hairdresser.js` + `web/css/hairdresser.css`；lazy 依赖固定为 `panel-runtime → asset-timeline → dressup-doll-renderer → hairdresser-runtime → hairdresser`，`panel-scale.js` 已由 overlay boot 加载，禁止在 lazy deps 中重复执行。基地理发师 NPC 只调用 `_root.gameCommands["openHairdresser"]()` 并发送精确 `panel_request {panel:"hairdresser",source:"world_hairdresser"}`；命令缺失或发送失败均 fail-closed，不回退旧 UI。独立 domain 只有 snapshot/commit：AS2 从现役三数组保持 77 行原序与重复项，任一非零/非法价格整体拒绝；snapshot 下发权威 `gender/face/currentHair/catalog`。Web 选择只用共享 `DressupDollRenderer` 做 strict 脸型/发型、本地、非动画预览，光头只绘脸型；未知性别或缺素材只给可读降级，不猜性别，也不禁目录或 commit。commit 只传 hairIdentifier，无价格、货币、backend preview、token 或自动存盘；AS2 先重查免费目录和全部依赖，再依次写 root 发型、live actor、刷新装扮及 dirty mark。字段完整且 `currentHair` 精确匹配本次选择的成功回包立即复用正常 `requestClose()`，只产生一次 close；确定失败和未知写对账保持面板可操作，不加延时器或第二套完成状态。Host `HairdresserTask` 是 `PanelPendingCallTracker<TContext>` 的第三个真实消费者，不自建 pending/Timer/callId mux；Web 继续组合既有 `PanelRuntime.PanelRequestMux`，未知写只以 fresh snapshot 判定 applied/not-applied，绝不重放。生产 close 清 transport pending；若有在途写则保留 `needs_reconcile` 到重开对账，迟到 commit 不复活。release policy 把 CSS/runtime/panel 设为必需路径，packer 仍由既有 `css/**`、`modules/**` 规则纳入。旧 Flash renderer、fallback 与主 XFL 三个全局发型函数已退役；角色创建默认发型 writer 和 `界面-发型选择` 控件不属于该迁移边界，继续保留。P0-F F3 关闭时的真实 NPC、socket/WebView2、权威写入、成功自动关闭、完整重启回读和维护者验收严格达到 `e2e_verified / NOT_DEPLOYED`，历史证据见 [P0-F §10.6](../docs/P0-跨层迁移基座与架构收敛专项-2026-07-23.md#106-f3-理发店纵切关闭记录)；其后 2026-07-24 冻结发布记录已将同一正式身份推进到 `standard_entry_verified`。稳定验证入口见 [验证矩阵](../agentsDoc/testing-guide.md)。

**通用模块**：
- `panels.js`: 面板注册/生命周期管理 (register/registerLazy/open/close/force_close)
- `panels-lazy-registry.js` + `lazy-loader.js`: 面板懒注册表（id → deps[]）+ 按需 `<script>` 注入，首次 `Panels.open(id)` 才加载对应模块（kshop/workbench/npcshop/crafting/hairdresser/skills/help/jukebox/dressup/map/stage-select/intelligence/arena/team/lockbox/pinalign/gobang/tasks/cutscene-test）
- `tooltip.js`: 复合 hover + anchored 两种模式，AS2 HTML 转换；触发物到浮层保留短过桥时间，grace 到期以真实 pointer/pen 命中状态作最终判定，两者均未命中时必须关闭；长说明支持浮层滚轮、触发物 `PageUp/PageDown` 与 `Esc`，确定性生命周期立即关闭。KShop browser harness 用真实 `PointerEvent`（pointer + pen）保护复合过桥与空白终态，并用物理鼠标覆盖 legacy `showAtMouse/hideHover`；商城、情报、任务、佣兵、竞技场 runtime tooltip 共用，图标通过 `PanelTooltip.dynamicIconHtml` 接入动态图/分层图播放链
- `workbench.js` + `item-filter.js`: 共享工作台标题提供筛选路径挂载点；目录、背包、仓库与战备箱的树筛选在标题同一行渲染可点击祖先路径，宽度不足时隐藏中段并保留根级和最近两级
- `workbench-components.js`: 共享 `SecondaryPage`、`QuantityControl` 与 `HelpAction`；非平凡双栏工作台复用唯一 `?` 入口和 shell modal，不在领域内复制 help button/focus/inert 生命周期
- `asset-timeline.js`: 图标与纸娃娃共享的烘焙时间线选择器，统一解释 `timelineFrames[]` / `durationFrames` / nested layer 独立周期
- `icons.js`: 物品图标 manifest 加载 + 上游 `icon` 名→URL / frame list 解析；任务/成就奖励由 AS2 或 build catalog 提交真实 `icon` 字段，情报详情面板也复用该入口；生产格子/tooltip 默认走 `Icons.html`/`PanelTooltip.dynamicIconHtml`，`Icons.resolve` 仅作首帧 fallback
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

**状态机**：`useNativeHud=true` 时 panel 打开状态以 `PanelHostController.ActivePanelName` 为主；`useNativeHud=false` 仍保留 WebOverlayForm `_activePanel` fallback（`null` → `"kshop" / "skills" / "help" / "dressup" / "map" / "stage-select" / "intelligence" / "arena" / "team" / "lockbox" / "pinalign" / "gobang" / ...` → `null`）。所有 Web Panel 打开都会通过 `webPanelPause` 持有统一 `"webpanel"` pause lease，关闭走 `webPanelUnpause` 释放；`kshop` 额外还有 `shopPanelOpen/shopPanelClose` 与 `_pauseNeedsRestore` 断线恢复语义；`skills` 使用实例绑定的 `skillPanelOpen/skillPanelClose`，关闭后的 cleanup/reconcile 可在视觉面板退场后继续；crafting 内的整理背包不属于新 panel open，Host active owner/instance/pause 始终仍是 crafting。其余纯 Web / dev panel 不发面板专属 AS2 open/close 命令，只参与统一 pause lease 和 PanelHost 生命周期。

**热重载恢复**：`_uiDataSnapshot` 按 KV key 维护最新值快照，WebView2 热重载后 `FlushUiDataBuffer` 先回放完整快照，确保 game-ready 等关键状态不丢失。reload/navigation 会销毁承载全部 panel visual 的浏览器文档，因此开始 reload 前必须按 exact instance authoritative-close 当前 Skills，并先推进 lifecycle cancellation generation/epoch，再撤销 Character↔Skills 两向 navigation one-shot、Skill/workbench 两类 opener wait、PanelHost queued/reserved admission 与未绑定 init context，让 `SkillTask` 进入既有 cleanup/reconcile；不能只刷新 DOM 后沿用旧 Host capability。socket disconnect 与 shutdown 使用同一 cancellation barrier，所有迟到 callback 在创建 wait、重新排队或 open 前都必须复验 epoch；相邻 intent 只允许 latest 胜出。competing panel 也撤销当前能力，迟到旧 `panel_request` 或旧 close callback 不得在新文档/新连接上重新开面板。Character authority 仍按自己的 detach recovery barrier 收束，不由这条 Skills 清理规则替代。

**维护约束**：凡是小游戏、地图 panel、stage-select panel、intelligence panel、dressup panel、arena / team panel、Native HUD/PanelHost 的目录迁移、宿主协议变更、QA 入口变化，必须同步更新本 README 的目录树、测试入口和本节协议说明；AS2 UI → Web Panel 迁移细则同步维护 [../agentsDoc/as2-web-panel-migration.md](../agentsDoc/as2-web-panel-migration.md)，模块内细节留在各自模块 README / 设计文档。
