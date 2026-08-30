# CF7:ME Guardian Launcher

**文档角色**：Guardian Launcher 子系统 source of truth。这里维护稳定架构、运行边界、入口、配置、协议注册表和验证路由；项目总览见 [README](../README.md)，任务路由见 [AGENTS](../AGENTS.md)。<br>
**最后核对代码基线**：release source commit `95019c7e63492d9cb88c010d1ee06376281c590b`（2026-08-29，启动前门、角色创建、作者/版本 Markdown 与版本记录迁移收尾；deployment `fdb4fe30aa911bbac91d60d7c349c217fa71a78c`）。动态 identity/closure、发布审计与当前 release state 只读下列 manifest、consensus 与 runtime 文档。
维护者已确认最终隔离候选实际使用无问题，因此该专项为 `HUMAN_ACCEPTANCE_PASSED / promoted`。部署后只执行正式根 bootstrap `--verify-only`，没有从无 candidate 的正式入口重跑普通读档、新建 durable 后重启读回、重建备份或旧 SOL 保护旅程，不称本功能业务 `standard_entry_verified`。
## 当前真值与阅读顺序

正式 runtime 的可变身份、文件闭包和 promotion 时间只以以下机器或发布真源为准，本 README 不复制发布收据：

- [runtime release consensus](../config/build/runtime-release-consensus.json)：request、release tree、build identity、payload closure、签名共识与 promotion 时间。
- [runtime manifest](../runtime/cf7-runtime-manifest.tsv)：正式入口与 `runtime/` 的逐文件大小、SHA-256 和构建身份。
- [runtime build reproducibility](../docs/runtime-build-reproducibility.md)：当前发布列车、状态边界、双 signer/双 faultDomain 流程和历史列车。
- [testing guide](../agentsDoc/testing-guide.md)：当前验证矩阵及专项 E2E 边界；C#/Web 字体改动另读 [字体 Gate E ADR](../docs/字体资产目录与语义角色解析-ADR-2026-08-20.md)、[字体目录](../fonts/README.md) 与 [fontctl](../tools/fontctl/README.md)。Web/Native 消费者、打包层和生产闭包已切换，维护者人工观感已接受；正式部署状态仍只读 runtime consensus 与标准入口证据。

新接手建议依次阅读：本文的“系统边界” → “运行架构” → “源码职责地图” → “构建、候选与发布” → “测试入口与证据边界”。改 AS2/Web Panel 再读 [AS2 → Web Panel 迁移护栏](../agentsDoc/as2-web-panel-migration.md)；改双栏工作台交互或样式再读 [Workbench UI System](../agentsDoc/workbench-ui-system.md)。

## 系统边界

Guardian Launcher 是 C# WinForms 长跑宿主，负责：

- 从 native bootstrap 进入受校验的 .NET Core 进程；
- WebView2 预检、Bootstrap UI、Flash Player SA 嵌入和前台/焦点管理；
- HTTP、XMLSocket、V8、Host ↔ Web 与 Host ↔ AS2 通信；
- Native HUD、Web Overlay、Panel 生命周期和输入屏障；
- 启动期存档决议、诊断、原生音频和 Agent Runtime 的受信宿主边界。

它不负责：

- 替代 AS2 业务裁决；Web 只能展示 Host/AS2 授权的数据和意图；
- 用浏览器 harness 代签真实 WebView2 → Flash、物理输入或游戏内 E2E；
- 通过 `launcher/build.ps1` 直接部署正式 runtime；
- 把 Audio H2、截图或听感证据塞进通用 runtime promotion 门。

Launcher 验收状态固定为：

```text
compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified
```

每一级只陈述已取得的证据，不从静态检查、mock browser、candidate 或通用 smoke 外推更高状态。

## 技术栈与版本真源

| 层 | 当前技术 | 版本或文件权威 |
|---|---|---|
| Host | C#、WinForms、`net10.0-windows`、x64 | [主 csproj](CRAZYFLASHER7MercenaryEmpire.csproj) |
| SDK | exact .NET SDK，禁止 feature-band 漂移 | [global.json](../global.json) |
| NuGet | WebView2、ClearScript、Vortice、SkiaSharp、Svg.Skia、Newtonsoft.Json | [Directory.Packages.props](Directory.Packages.props) |
| Web | HTML/CSS/JavaScript、WebView2、V8 模块 | [web](web/) |
| Native | C++ bootstrap、HotkeyGuard、miniaudio side-car | [native](native/) |
| Tests | xUnit、Node browser/harness、专项 PowerShell/Python gate | [tests](tests/) 与 [testing guide](../agentsDoc/testing-guide.md) |

不要在本文件手写 NuGet 版本、runtime 文件数或产物大小；这些值分别从版本真源和 manifest 读取。

## 运行架构

### 入口与进程

```text
CRAZYFLASHER7MercenaryEmpire.exe        native bootstrap，用户唯一正式入口
└─ runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe
   └─ GuardianForm + Flash SA + WebView2/V8 + Native HUD/Panel + Bus
```

Bootstrap 使用纯 Win32/CRT，在启动 Core 前验证正式 runtime manifest、必要文件和 .NET Desktop Runtime。它把绝对项目根以 `--project-root` 传给 Core，并把剩余参数继续转发。启动 Core 后保留 5 秒早退观察窗：Core 非零或未知退出时写启动失败摘要；Core 仍在运行时 bootstrap 才退出。长跑进程始终是 `runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe`。

关键日志：

| 路径 | 用途 |
|---|---|
| `logs/bootstrap.log` | native preflight、manifest、runtime 检测和 Core 早期阶段 |
| `logs/startup-exit.jsonl` | 最近启动退出/失败原因码 |
| `logs/startup-failure-latest.txt` | 最近一次玩家可读失败摘要 |
| `logs/dumps/` | Core native dump 与 createdump 日志 |
| `logs/perf-latest.jsonl` | 托管入口后的启动性能时间线 |
| `logs/launcher.log` | Host、Bus、Flash、Panel、Audio 与运行期诊断 |
### 启动时序

```text
bootstrap preflight
  → Core runtime 自校验、字体 catalog / XML-hash projection 校验与 face-major 的 custom/cache/permanent 来源解析
  → WebView2 fail-closed 预检 → GuardianForm / BootstrapPanel
  → Steam、Flash trust、Audio、Bus、Task registry
  → save list / ready / prewarm
  → Flash title receipt → Bootstrap Web 启动前门 → bootstrap_reveal_ready 资源栅栏 → 当前 attempt 的 s:1|ga:<attemptId> 场景回执
  → reveal → runtime panels and HUD
```

`publish_done.marker`、进程存在或页面加载完成都不能单独代表成功。真实启动结论必须绑定新鲜日志、实际进程路径和对应 runtime identity。
### 窗口与输入所有权

`GuardianForm` 是主窗口与 Flash 容器。运行态 UI 由 Native HUD、Web Overlay、Panel backdrop/input shield 和原生 cursor 按状态组合；Panel 打开时由 `PanelHostController` 统一协调 snapshot、焦点、输入屏障、Native HUD suspend/resume 和 WebView2 几何。

正式 Panel 路由由 `LauncherCommandRouter` 与领域 handler 授权。Web 不得凭本地 DOM 状态制造业务能力；AS2 仍是需要游戏状态或存档写入的最终裁决方。跨层请求必须遵守 exact envelope、instance/session、generation、nonce/token、revision 和迟到回包 fence，具体以 [迁移护栏](../agentsDoc/as2-web-panel-migration.md)为准。
### 通信面

| 通道 | 用途 | 约束 |
|---|---|---|
| WebView2 message | Bootstrap、Overlay、Panel 控制与展示 | Host 校验命令和 payload；Web 不拥有业务写权限 |
| XMLSocket | Flash ↔ Host 任务消息 | 连接、握手和业务回包分别判定，裸 socket 不能代签 Flash 建连；GameStage `T+|id|seconds|label` / `T-|id` / `T!` 仅投影 keyed 计时 HUD，AS2 独占倒计时和失败裁决，断连清理 |
| HTTP | 兼容查询、资源与受限控制面 | legacy automation 不是 Agent Runtime 的信任边界 |
| V8 | 搓招 `GameInput` DFA | 单 engine/单锁，模块源与加载闭包必须可复验；不再持有伤害数字状态或渲染描述符 |
| named pipe / MCP | CF7 Agent Runtime | 观察 grant 与 write lease 分离，绑定 peer/session/frame/generation |

### Loot feed 与纸娃娃烘焙协议

- AS2 所有权变化由 `PlayerAssetTransaction` 在领域最外层提交后生成 detached receipt，再经 XMLSocket fire-and-forget `loot` v1 发送 `{v,direction,kind,itemKey,name,count,source,operationId,icon?,tier?,mergeScope?,reason?}`。完全缺 `v` 的旧格式只为现役 kill/gain 兼容；v1 错型、缺必填、未知 source 或非 safe 正整数均 fail-closed。
- `LootFeedTask` 只把已提交事实投影到 NativeHud `LootFeedWidget`；资产写入/回滚仍由 AS2 领域权威负责，消费者失败不能反向破坏资产。地图 `loot_response` 是另一业务域，常驻 feed 无 Web fallback。范围、source 表、所有权排除项与存档终点见[玩家物资事务与双向播报 ADR](../docs/玩家物资事务与双向播报-ADR-2026-08-22.md)。
- `LootFeedModel` 统一五槽池与可恢复队列；视觉键为 `direction/kind/itemKey/tier/派生调度策略/eliteLevel`，且展示名/图标须一致。`operationId/reason/mergeScope/raw source` 只留在 Host 幂等与审计层；跨 raw source 仅在策略完全相同且都非 `unknown` 时合并。`reload` 为 immediate exact-aggregate；Host 按 operation/effect 去重并拒绝冲突重放。
- 绘制采用 5 个 26px 直角卡、20px 图标与 12px 名称，宽度在 96–220px 内按 8px 微量化。gain 沿用 `×N` 且一件省略数量；loss 使用珊瑚红 `−N`，一件也明确显示 `−1`。精英使用琥珀分段轨，Boss 使用金色双轨；任务、开箱与普通物资不借用 Boss 视觉。
  入场只做 4px/180ms SmoothStep 垂直归位；计数按 125ms 提交，用 180ms/1–2px SmoothStep 交叉淡化并仅在数字区增加有界色洗/底沿，击杀按本批增量增强但不缩放整卡、不发粒子；退场 280ms，动画图标最多运行 450ms 后冻结。静态持有不申请重绘，视觉签名 32ms 采样且仍受 NativeHud 33ms 合成硬上限约束；socket burst 维持单 UI drain / 单批决策，bounds 只随卡片/等待行或方向感知的计数位数桶变化（gain `1→2`、loss `9→10` 才跨桶）。
- `LootIconCatalog` 从 `launcher/web/icons/manifest.json`、敌人头像 manifest 与 `launcher/data/doll-portraits` 解析图标。64px `Bitmap` 只由有界 LRU 持有，图标帧集不得跨 LRU 淘汰保存位图引用；动画整组超过预算时降级静态首帧。
- 主角/佣兵击杀缺少预烘焙头像时，Host 发 WebView2 message `{type:"dollBake",key,requestId,tuple}`。Web 只负责渲染，并经 allowlisted task `doll_bake_result` 回传 `{key,requestId,pngBase64|error}`；`requestId` 必须与当前 key 的唯一在飞项 exact 匹配。缺失、foreign、duplicate、timeout 后迟到或无在飞项的回包一律拒绝，且不得清除更新请求。
- `DollBakeTask` 只接受可完整解码的 exact 256×256 PNG。Web 离屏渲染显式固定 `pixelRatio:1` 并关闭一次性快照的动画循环，使传输尺寸不受宿主 125%、150%、175% DPI 放大。校验通过后才原子写入 `launcher/data/doll-portraits/<hex>.png`；拒绝尺寸/内容时记录 key、requestId 与原因。
  调度器首次复用历史缓存时执行同一完整校验，旧尺寸或损坏文件不再短路请求而会触发重烘焙；目录读取端也拒绝非 256×256 文件。匹配请求的失败终态只释放该请求以允许重试；成功终态再触发 `PortraitReady`，让仍存活的占位卡重探图标。Web 不拥有任意文件名、缓存路径或跨 key 写权限。
### 原生音频平台 v2

原生音频 bridge、格式能力和可观测性以 [Audio Platform v2 ADR](../docs/原生音频平台-v2-格式能力桥接契约与可观测性-ADR-2026-08-09.md)为准。通用 runtime promotion 只证明供应链与部署完整性；Audio H2 仍是独立产品验收，不从通用 promotion 或其他 Panel smoke 外推。
前门 BGM 仅走 Native Audio v2，固定循环 `sounds/PTXOA馆长/主菜单.mp3`、gain `0.4`，不读槽位音量偏好。lease 只在 `Ready` 且 source 为空时获取，不重播自身也不抢异源。无 OP 的读档/建角/提交后加载保持到 actual reveal；OP 与 legacy 在 admission 让出。`SceneReady` 不交接音频，reveal 前 reset/error 可恢复；actual reveal 以 requestId-CAS 让出并由 AS2 接权，已 supersede 时不 stop，recovery 不复活已 revoke intent。
### Agent Runtime

Agent Runtime 的 wire、受信 runner、credential bootstrap、30 秒预算和 structured-first/visual-fallback 边界见 [Contracts README](src/AgentRuntime/Contracts/README.md)与[一期范围冻结 ADR](../docs/CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md)。历史 F7/F8 发布证据留在 ADR 和 `docs/evidence/`，不回流到本文件。

## 源码职责地图

**最后核对代码基线**：commit `04718fa57afb64836e95893f0c4ff821d25ca043`（2026-08-16）。

本节是职责地图，不是手写文件 inventory。C# 主项目采用 SDK 默认递归 `**/*.cs`，实际排除项以 [主 csproj 的 `DefaultItemExcludes`](CRAZYFLASHER7MercenaryEmpire.csproj)为准；测试项目同样使用 SDK 隐式项。

<!-- launcher-source-map:start -->
| 路径 | 职责 |
|---|---|
| [CRAZYFLASHER7MercenaryEmpire.csproj](CRAZYFLASHER7MercenaryEmpire.csproj) | Host 编译边界、依赖、嵌入资源和确定性构建设置 |
| [src/Program.cs](src/Program.cs) | Core 入口、运行模式、依赖装配和启动顺序 |
| [src/Guardian](src/Guardian/) | 窗口、启动 UI、WebView2、Native HUD、Panel、焦点和命令路由 |
| [src/Fonts](src/Fonts/) | XML-hash runtime 投影、face-major 来源解析、已验证字节快照缓存、Native role 创建与 WebView2 exact-set/ETag 资源处理 |
| [src/Tasks](src/Tasks/) | Flash/Host 任务实现与领域消息处理 |
| [src/Bus](src/Bus/) | HTTP、XMLSocket、V8 和消息总线 |
| [src/Save](src/Save/) | 启动期存档决议、备份、repair 与用户存档操作 |
| [src/Audio](src/Audio/) | Audio Platform v2 managed bridge、协调与专项诊断 |
| [src/AgentRuntime](src/AgentRuntime/) | named pipe、MCP/JSON adapters、观察与写 lease |
| [src/Config](src/Config/) | `config.toml` 与用户偏好解析 |
| [web](web/) | Bootstrap、Overlay、Panel、minigame、样式和静态资源 |
| [native](native/) | bootstrap、HotkeyGuard 和原生 side-car 源码 |
| [tests](tests/) | Launcher xUnit 工程、fixtures 和 exact-SDK runner |
| [perf](perf/) | Web Overlay 性能 harness 与审计说明 |
| [data](data/) | Launcher 运行时 schema、字体与数据资源 |
| [docs](docs/) | Launcher 内部 owner/生命周期专题文档 |
<!-- launcher-source-map:end -->

新增一级职责目录、移动入口或改变 SDK include/exclude 规则时，必须同步本节和文档治理检查。

## 构建、候选与发布

**最后核对代码基线**：commit `04718fa57afb64836e95893f0c4ff821d25ca043`（2026-08-16）。

### 日常开发

推荐使用仓库级开发入口：

```powershell
chcp.com 65001 | Out-Null
powershell -File automation/dev.ps1
```

也可运行根目录 `本地开发启动.cmd`。这些入口选择或生成隔离 candidate，不修改正式 `runtime/`。

直接调用兼容编排器：

```powershell
chcp.com 65001 | Out-Null
powershell -File launcher/build.ps1 -BuilderId local-dev
```

`launcher/build.ps1` 只执行 prepare → pure producer → policy，最高到 `candidate_built`。它不具备 promotion 权限，也不能把 candidate 复制到正式 runtime。

### 离线开发入口与身份绑定候选

`automation/dev.ps1` 把 exact candidate 交给 `automation/start.ps1 -CandidateRoot <absolute-path>`。候选入口必须位于本仓受控 candidate 根、不是 reparse point，并由候选自身 bootstrap 使用 `--verify-runtime-only` 验证 manifest、Core、build identity 和 payload closure。

正式入口使用根 bootstrap 的 `--verify-only` 验证已部署闭包。普通运行日志可以报告 `formal_runtime` 或 `isolated_candidate`，但 trusted unattended stdout 只承载协议；其身份由 verifier、exact process path、peer credential 和 Host 绑定共同证明。

### 正式发布

正式发布必须遵守 [runtime build reproducibility](../docs/runtime-build-reproducibility.md)：冻结 immutable request，由注册本地 X509 worker 与另一真实 faultDomain 对同一 identity/closure 生成证明，经 production policy 与 strict v2 verifier 后，才允许 `tools/promote-runtime-bundle.ps1` 原子写入正式闭包。

正式产物的文件数、大小与 SHA-256 只读 [runtime manifest](../runtime/cf7-runtime-manifest.tsv)；当前共识只读 [runtime release consensus](../config/build/runtime-release-consensus.json)。普通 docs/Web/AS2 修改不因此自动触发 runtime promotion。

## 测试入口与证据边界

**最后核对代码基线**：commit `04718fa57afb64836e95893f0c4ff821d25ca043`（2026-08-16）。

### Launcher xUnit

```powershell
chcp.com 65001 | Out-Null
powershell -File launcher/tests/run_tests.ps1
```

Runner 先验证 exact SDK resolver 与 `xunit.runner.json`，再从仓库根执行 Release `dotnet test`。SDK 由 [global.json](../global.json)精确锁定；测试集合串行策略由 [xunit.runner.json](tests/xunit.runner.json)与对应测试共同约束。

### 测试覆盖

以下只描述静态测试分区，不保存会随代码增长而失效的 passed/total 数字。

<!-- launcher-test-taxonomy:start -->
| 分区 | 主要范围 |
|---|---|
| `<root>` | 基础设施与跨域冒烟 |
| `AgentRuntime/` | pipe、adapter、credential、lease、runner 与生命周期 |
| `Audio/` | managed bridge、qualification 合同与恢复语义 |
| `Bus/` | Router、HTTP、XMLSocket 与消息边界 |
| `Config/` | 配置解析、默认值、环境覆盖和用户偏好 |
| `Contracts/` | 跨层 schema 与固定 envelope |
| `Diagnostic/` | runtime verifier、诊断与报告合同 |
| `Fixtures/` | 测试数据与共享 fixture |
| `Fonts/` | 字体投影、来源优先级、完整性、fallback 与重启边界 |
| `Guardian/` | 窗口、HUD、Panel、焦点、DPI、地图和输入 |
| `Infrastructure/` | 进程、文件、时间和平台设施 |
| `Save/` | Protocol 2、SOL 定位、备份与 repair |
| `Tasks/` | Flash/Host 领域任务及解析边界 |
<!-- launcher-test-taxonomy:end -->

### Web、Panel 与专项验证

Web/Node、真实 Edge harness、AS2 runner、Flash CS6 publish-only smoke、candidate 和正式入口旅程必须按 [testing guide](../agentsDoc/testing-guide.md)选择。模块 README 可以给出本领域命令，但不能把 mock/browser harness 写成真实游戏 E2E。

最小证据分层：

| 证据 | 能证明 | 不能代替 |
|---|---|---|
| 静态检查、Node/xUnit | 源码合同和回归 | WebView2 → Flash、物理输入、视觉验收 |
| browser harness | 真实浏览器 DOM/交互 | Launcher Host、Flash、正式 runtime |
| candidate build/run | 隔离闭包可构建/执行 | promotion、标准入口 |
| feature E2E | 对应冻结身份的业务旅程 | 未执行的其他领域 |
| standard entry | 正式部署入口下的明确旅程 | 全产品或跨设备泛化 |

测试结果若需长期保存，应进入专题 ADR/`docs/evidence/`，并绑定 source、process path、identity、closure 和未覆盖边界；不要回填本节的动态计数。

## 运行时配置

`config.toml` 是机器级、随仓、启动时只读配置；`launcher_user_prefs.json` 是用户级偏好。配置解析权威为 [AppConfig.cs](src/Config/AppConfig.cs)，注释和 shipped value 权威为 [config.toml](../config.toml)。

下表完整登记 `AppConfig` 当前识别的 key。`代码默认 / shipped` 不一致时必须同时写清，避免把缺 key 行为误当随仓配置。

<!-- launcher-config-registry:start -->
| key | 代码默认 / shipped | 环境覆盖 | 角色 |
|---|---|---|---|
| `flashPlayerPath` | `Adobe Flash Player 20.exe` / 同 | — | Flash SA 路径 |
| `swfPath` | `CRAZYFLASHER7MercenaryEmpire.swf` / 同 | — | 主 SWF 路径 |
| `webOverlayLowEffects` | `false` / `false` | `CF7_WEB_LOW_EFFECTS` | 聚合低特效诊断 |
| `webOverlayDisableCssAnimations` | `false` / `false` | `CF7_WEB_DISABLE_CSS_ANIMATIONS` | 关闭 CSS 动画 |
| `webOverlayDisableVisualizers` | `false` / `false` | `CF7_WEB_DISABLE_VISUALIZERS` | 关闭可视化器 |
| `webOverlayFrameRateLimit` | `60` / `60` | `CF7_WEB_FRAME_RATE_LIMIT` | Web 刷新率上限，`0` 为不限 |
| `webView2DisableGpu` | `false` / `false` | `CF7_WEBVIEW2_DISABLE_GPU` | GPU A/B 诊断 |
| `webView2AdditionalArgs` | 空 / 空 | `CF7_WEBVIEW2_ARGS` | 附加 Chromium 参数 |
| `webView2DeveloperMode` | `false` / `false` | `CF7_WEBVIEW2_DEV_MODE` | DevTools、accelerator 与右键开发模式 |
| `nativeCursorOverlay` | `true` / `true` | `CF7_NATIVE_CURSOR_OVERLAY` | 原生 cursor 总 gate |
| `gpuPreference` | `off` / `off` | `CF7_GPU_PREFERENCE` | `off/auto/on` 每应用 GPU 偏好 |
| `devGpuProbeHotkey` | `false` / `false` | `CF7_DEV_GPU_PROBE` | Ctrl+G 合成诊断，玩家版保持关闭 |
| `preparationNavigationV1` | `true` / `true` | — | 整备导航 presentation；显式 false 或非法值回退旧 presentation |
| `useDesktopCursorOverlay` | `true` / 缺省 | `CF7_DESKTOP_CURSOR` | desktop ULW cursor；false 使用旧 anchor-bound 路径 |
| `webOverlayPanelTakeForeground` | `true` / 缺省 | `CF7_PANEL_TAKE_FG` | Panel 前台与 WebView 焦点接管 |
| `diagLayerAudit` | `false` / `false` | `CF7_DIAG_LAYER_AUDIT` | 顶层 HWND 结构快照 |
| `diagUlwMonitor` | `false` / `false` | `CF7_DIAG_ULW_MONITOR` | ULW commit 频率与延迟 |
| `diagEtwDwm` | `false` / `false` | `CF7_DIAG_ETW_DWM` | DWM ETW 计数，需要管理员 |
| `diagReportIntervalSec` | `5` / `5` | `CF7_DIAG_INTERVAL_SEC` | 诊断报告周期，clamp 1–60 秒 |
| `webOverlayHotReload` | `false` / `false` | `CF7_WEB_HOTRELOAD` | 开发热重载，玩家版保持关闭 |
<!-- launcher-config-registry:end -->
`CF7_DIAG_FOCUS_PROBE` 是 `UiFreezeProbe` 的独立环境急停，不属于 `AppConfig` key。生产默认值、诊断建议和硬件边界以 `config.toml` 注释为准，README 不复制长注释。用户偏好落在 `%LOCALAPPDATA%/CF7FlashNight/launcher_user_prefs.json`；项目根同名文件只作一次性 legacy 导入。
<!-- launcher-user-prefs-registry:start -->
当前字段为 `lastPlayedSlot`、`introEnabled`、`sfxEnabled`、`ambientEnabled`、`uiFontScale`、`suppressedHighDpiWarningRaw`、`mapDisplayPreference`、`hitNumberMode` 和 `hitNumberWorldRowLimit`。
<!-- launcher-user-prefs-registry:end -->
公开 Web 写入必须经过 `config_set` 白名单；Host-only 字段不得因前端同名而获得写权限。<a id="打击伤害数字生产路径"></a> **打击伤害数字生产路径**：AS2 仍负责伤害结算，`HitNumberBatchProcessor` 仅发送结算后的逐段事实；C# `HitNumberRuntime` 是唯一表现状态机，负责短寿命状态、模式投影和世界行裁剪，`HitNumberOverlay` 消费 latest-wins frame 并以紧边界持久 DIB 绘制。V8 只保留 `GameInput`，Flash renderer 不再作为 fallback。
机器全局偏好提供 `off/balanced/total/classic/detail` 五状态。默认 `balanced` 只保留同目标最近三次 Burst，并把总伤的“最新段来源色闪现→该次攻击贡献主体色”、属性来源色、固定效果色、emoji、贡献强度及吸血/护盾精确值投影到攻击摘要；`classic` 复刻旧 Flash 散射/14 帧动效，`detail` 按 Burst 原子展示逐段并按实际数字/属性标签边界扩格、缩列。四模式共用同一 11 色语义表，逐段项永远使用自身来源色；属性贡献可见度与模式标签密度为正交尺度，因此平衡/逐发可保持紧凑而不伪造低贡献。
`total` 保留旧总伤表达：当前段颜色闪现后回落到贡献主体色，状态按伤害贡献衰减，吸血/护盾保留精确累计值，总伤与 hit 渐进追赶；伤害类型与粉碎使用独立文字槽，非 MISS 零伤保持来源色，MISS 不累计，淡出续击恢复同一条目，最新目标最后绘制，冲击脉冲受平衡字号上限约束。balanced/detail 同样把最新受击目标最后绘制。
非零 `hitNumberWorldRowLimit` 是全局攻击行上限，有限 `detail` 另对每目标只保留最新六行；`0` 明确解除两层产品上限并保持真正无限制。四种显示模式仍保留屏外剔除和自然寿命，有限上限不拆攻击，切换立即建立新 generation 并重排。
精确对账不占战斗键：暂停态设置通过 Host-local `hit_number_ledger` 分页读取固定 32,768 段环形账本，按目标/Burst 保留逐段事实并显式报告溢出；`off` 后停止接收新段，既有记录保留至 reset 或覆盖。验证入口见[专项视觉/性能 harness](../tools/hit-number-visual-harness/README.md)和[测试矩阵](../agentsDoc/testing-guide.md)；合成门不代签真实战斗的目标归属、打击感或高 hit 人类验收。

## 命令行参数

表内区分开发入口、bootstrap verifier 和受信内部模式。内部 flag 不构成面向玩家的兼容承诺，调用方应使用对应 automation/Agent Runtime wrapper。

<!-- launcher-cli-registry:start -->
| 参数 | 类别 | 作用 |
|---|---|---|
| `--project-root <abs>` | bootstrap → Core | 注入项目根；Core 消费后从其余参数剥离 |
| `--bus-only` | 开发 | 跳过正式 Flash 启动链，保留 Bus/Overlay 供 CS6 testMovie 或工具连接 |
| `--force-webview-fail` | 测试 | 强制 WebView2 预检失败分支 |
| `--verify-only` | bootstrap verifier | 校验正式根部署后退出 |
| `--verify-runtime-only` | candidate verifier | 校验 isolated candidate 后退出 |
| `--agent-unattended-runner` | 受信内部 | 进入 exact credential/peer 绑定的 Agent Runtime runner |
| `--unattended-bootstrap-request` | 受信内部 | 绑定无人值守 bootstrap request 文档 |
| `--audio-v2-qualification-run-id` | 专项内部 | 绑定 Audio v2 qualification run |
| `--legacy-http-automation` | 兼容内部 | 显式启用 legacy HTTP automation 外层，不提升信任等级 |
<!-- launcher-cli-registry:end -->

Agent Runtime adapter 自身的 `--adapter`、`--slot` 等 wrapper 参数见 [Contracts README](src/AgentRuntime/Contracts/README.md)，不属于 Core/Bootstrap 公共 CLI。

## Bootstrap Web 协议

Bootstrap Web 发出的命令必须由 `BootstrapMessageHandler` exact dispatch；未知命令、错误 payload 或越权状态应 fail-closed。下表是当前 command registry，处理细节以 [BootstrapMessageHandler.cs](src/Guardian/BootstrapMessageHandler.cs)和 `src/Guardian/Handlers/` 为准。

<!-- launcher-bootstrap-command-registry:start -->
| cmd | 领域 |
|---|---|
| `ready` | Web ready |
| `ping` | 健康检查 |
| `cancel_launch` | 启动生命周期 |
| `start_game` | 启动生命周期 |
| `character_create_open` | 用当前 Web `openRequestId` 打开新建 / 重建角色草稿 |
| `character_create_submit` | 提交当前 open/attempt 的角色草稿与显式 `displayNameCustomized` |
| `reveal_ok` | reveal receipt |
| `retry` | 启动错误恢复 |
| `list` | 存档列表 |
| `delete` | 写 tombstone 并保留 catalog 身份供辨认/重建 |
| `rename_slot` | 修改 Host 权威槽位显示名；允许重名，空串恢复跟随角色名，不修改物理 `slotKey` |
| `load` | 存档操作 |
| `load_raw` | 存档原始读取 |
| `save` | 存档操作 |
| `reset` | 彻底清 shadow、tombstone 与 catalog 身份 |
| `export` | 存档导出 |
| `import_start` | 导入预检 |
| `import_commit` | 导入提交 |
| `logs` | 打开日志 |
| `open_saves_dir` | 打开存档目录 |
| `diagnostic` | 导出诊断包 |
| `audio_preview` | 音频预览 |
| `config_set` | 用户偏好写入 |
| `fontpack_status` | 字体包状态；逐文件返回 `verificationState` |
| `fontpack_install` | 字体包安装；成功项返回同字节验证状态 |
| `fontpack_cancel` | 字体包取消 |
| `repair_detect` | repair 检测 |
| `repair_apply_manual` | repair 人工应用 |
| `repair_force_continue` | repair 明示继续 |
<!-- launcher-bootstrap-command-registry:end -->
`config_set` 只写白名单。启动前门的 attempt/slot/displayName/backup/reveal、durable/SceneReady、catalog 与 exact retry 边界见 [AS2 → Web 迁移护栏](../agentsDoc/as2-web-panel-migration.md)；`bootstrap_reveal_ready` 不代签 `s:1|ga:<attemptId>`，重建不预删 SOL。FontPack 的真实探针、exact HTTPS allow-list 与字节/ETag/WOFF2 边界见[字体目录](../fonts/README.md)。
Bootstrap 建角在准备期由 `openRequestId` 关联完整遮罩：live snapshot 与纸娃娃有效首帧汇合，且 canvas 至少有 501 个非透明像素，再经过双 `requestAnimationFrame` 才移除 `inert`。准备遮罩不叠加专用幻方；既有 PM19 幻方在建角全过程保持 ambient，退出后再与 Ready 同步，动效从不参与 ready 判定。显式资源失败或 12 秒期限只降级展示。title/snapshot/scene deadline 继续分相，编辑期无 watchdog；迟到回调不得揭开新页，durable 后故障不得重放创建。
角色名为主，存档显示名在高级选项中默认跟随；确认页仅在自定义名不同时另列。建角固定 `1024×576` + `PanelScale`，窗口/全屏只等比缩放。外观保留三装备槽、单发型槽和左侧唯一身高；紧凑/完整均挂载 77 项，完整卡片使用可辨识短名与候选池内部滚动，三步零页面滚屏；脸型只走 exact wire，注释统一用 `PanelTooltip`。作者/版本正文来自 `web/content/*.md`；版本记录为近全屏单节点浏览器，运行版本只读 `web/config/version.js`，历史证据与视频提纲按[版本考古规范](../docs/version-archaeology/README.md)收口。
## Panel 与 minigame 注册表

**最后核对代码基线**：commit `630d7def1e78e48021334b67d32486c61ad4c051`（2026-08-17）。`Panels.open(id)` 首次命中 lazy entry 时，`lazy-loader.js` 按声明顺序加载依赖；成功 URL 按 promise 去重，失败 URL 驱逐缓存并允许重试。精确依赖顺序和注册集合以 [panels-lazy-registry.js](web/modules/panels-lazy-registry.js)为代码权威。

<!-- launcher-panel-registry:start -->
| id | 类别 | 最终注册模块 |
|---|---|---|
| `kshop` | 工作台 | `modules/kshop.js` |
| `workbench` | 工作台 | `modules/inventory-workbench.js` |
| `loot` | 工作台 | `modules/loot/loot-panel.js` |
| `npcshop` | 工作台 | `modules/npcshop.js` |
| `crafting` | 工作台 | `modules/crafting.js` |
| `hairdresser` | 业务 Panel | `modules/hairdresser.js` |
| `settings` | 全屏工具 / Launcher bootstrap shell | `modules/settings-panel.js` |
| `skills` | 工作台 | `modules/skills.js` |
| `help` | 工具 Panel | `modules/help-panel.js` |
| `jukebox` | 工具 Panel | `modules/jukebox/jukebox-panel.js` |
| `cutscene-test` | 开发 Panel | `modules/cutscene-test.js` |
| `dressup` | 工具 Panel | `modules/dressup/dressup-panel.js` |
| `map` | 业务 Panel | `modules/map-panel.js` |
| `stage-select` | 业务 Panel | `modules/stage-select-panel.js` |
| `lockbox` | minigame | `modules/minigames/lockbox/lockbox-panel.js` |
| `pinalign` | minigame | `modules/minigames/pinalign/pinalign-panel.js` |
| `gobang` | minigame | `modules/minigames/gobang/gobang-panel.js` |
| `blackmarket` | minigame | `modules/minigames/blackmarket/blackmarket-panel.js` |
| `warlord` | minigame | `modules/minigames/warlord/warlord-panel.js` |
| `intelligence` | 业务 Panel | `modules/intelligence-panel.js` |
| `arena` | 工作台 | `modules/arena-panel.js` |
| `team` | 工作台 | `modules/team/team-panel.js` |
| `tasks` | 业务 Panel | `modules/tasks/task-panel.js` |
<!-- launcher-panel-registry:end -->
Panel 的共同边界：
- Host 拥有 open/admission、实例和跨 Panel 导航；Web 只消费授权 initData/snapshot。
- NPC 商店价格 wire 使用整数 `buyRatePermille` 与 safe-integer 金额；AS2/Host 按 `floor((basePrice × quantity) × rate / 1000)` 的同一顺序复验，Web 不重算价格。旧浮点 `buyMultiplier` 不兼容，Host、asLoader、Web 与 harness 必须进入同一 immutable candidate 原子交付；完整字段与 blocked-preview 边界见 [AS2 UI → Web Panel 迁移护栏](../agentsDoc/as2-web-panel-migration.md)。
- Team 内嵌 `pets` / `mercs` 的全部请求（含 T800 武器命令与佣兵装备 tooltip）携 active `panelInstanceId`；Web 回包精确匹配 instance/callId/cmd，Host 拒绝 inactive/foreign/stale owner，replacement 清退旧 pending，迟到响应不可跨实例采用。业务写仍由白名单、revision/lease/token 与 AS2/Host 裁决，未知结果进入对账；T800 详见[施工记录](../docs/终结者T800-托管长枪与射击核心-施工-2026-08-22.md)。
- LoadoutPicker 候选只接受装备槽、药剂槽或无 selector 背包总览三种 target。Character `equipmentEligibility` 在两种 scope 由 Host 复验；Merc `eligibleSlots` 由 AS2 两种 scope 签发。scope 只筛候选，白名单裁决 drop target，写后保留原 scope/anchor；Merc 按新 revision 恰好刷新一次 authority。详见[迁移护栏](../agentsDoc/as2-web-panel-migration.md)。
- `equipment_tuning` 的 loadout `convert` 只接受 exact 背包 inventory target。已改变的成功 commit 必须包含一份完整背包 snapshot，其他 loadout 写与 convert no-op 必须包含零份；Host 依 operation/no-op 严格校验后，Web 才可在同一写锁下收敛 loadout/背包 authority。配件候选 snapshot 可携完整兼容目录，但 Web fresh open 默认只显示“已拥有”；全目录只能由玩家显式切换。
- `equipment_tuning` 的已穿戴调制按 after effective data 复核玩家等级；`level_locked` 是 Host 可确定收束的业务拒绝，Web 显示“调制后的装备需要更高角色等级”。背包装备不受该玩家等级门限制。`replace_mod` 的候选可用性和 after `modSlotCapacity` 都来自拆件后的 probe；存档加载不做迁移、卸装或清洗。进阶页仅显示 `available=true` 并在 Web 空态解释缺料/顺序；四入口同排。候选错误留在 Web，flush/finalize 先取消旁路读，保存失败仍阻断。
- 合法配件变换可使 before/after effective `modSlotCapacity` 不同；Host 仍复核 `0..64` 整数、installed≤capacity、操作差分及 preview/commit/fresh snapshot 深绑定。空背包未建 Flash authority 时，仅 exact panel 在 idle 且无 pending/detaching/write 可本地 no-op detach；其余仍严格走 Flash，断线不可绕过。
- close、Esc、backdrop、导航和 recovery 经过同一 lifecycle fence。Team/blackmarket/warlord close 携当前实例并等待 Host exact `panel_cmd close`；Bridge 投递成功不等于接受，确认丢失 3 秒后只恢复同实例重试权，不本地关闭；迟到 A 不得关闭 replacement B，旧 `panel:"pets"|"mercs"` child close 一律拒绝。
- Workbench 的布局和交互以 [Workbench UI System](../agentsDoc/workbench-ui-system.md)为准。关卡内 `StageOutcomeTask` 把复活/胜负决策投影进 `RightContextWidget` 既有 32px 条件槽，不创建浮窗、不暂停 Flash。胜负条常驻，忽略即继续探索；无可交付任务只显示“回基地”，AS2 `tdr` 证明返回后可路由时追加“前往交付”，并在奖励终态和 Web exact close 后导航。
  respawn 恢复 HP/MP/可见性后清 `倒地/_killed`、死亡 latch 并 reset WatchDog，重开同一 MovieClip 技能门。Web 左栏同滚屏合并击杀与物资 gain/loss，右栏切换待领/材料，一个密度控制器同步三者；整理页保留 KShop 同源灰黑 inventory skin。奖励每批最多 50 项，`claimBatch` 进入 AS2 顺序 authority journal 并以 exact query 对账。2026-08-30 起 Loot v2 固定 `targetContainerId:"自动"`与 loot/背包/药剂栏三快照，Host/Web 不选药剂槽。
  关卡奖励退场前写 `_saveExt.stageSettlement.v=1` 并 strict flush；单领、批领和终态依 durable remaining/receipt journal 对账。SaveManager 读档重建 pending，Loot 恢复已落盘 operation/revision。flush 未确认时保持 `LOOT_COMMIT_PENDING`，不得回成功或释放场景；详见[关卡结果与基地结算 ADR](../docs/关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md)。
  地图在战斗/结算中只读，导航按 AS2 lifecycle lock 零发送；loader staging 在首次 gameplay init 按 drop→reward 提交。跨淡出回包保持正整数 `callId`；Stage Select 关闭须先投递，transport false/throw 时保留面板与重试权。NativeHud down 绑定 exact action/revision，suspend/hide/capture loss/外放均取消。
  有效 `stage_settlement` 报告可在 `remaining=0` 时 suspend/reopen，`map_chest` 不继承。Panel close 仅在 close 起点与恢复前两次 live foreground 都属于 CF7 时恢复 Flash，切到 QQ/浏览器后不得抢焦。完整权威与生命周期详见[关卡结果与基地结算 ADR](../docs/关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md)。
- `settings` 在 `1024×576` anchor 内全屏复用 Launcher bootstrap Web 壳的品牌铭牌、终端状态、DLS 青/锈红/骨白令牌与切角，不挂 `workbench-shell`。两页手工复刻的铭牌/kicker/分隔线/状态点/角标/扫描线/按钮/终端卡片已收敛为共享 [terminal.css](web/css/terminal.css)，bootstrap.html 与 overlay.html 均直接 link。
  新表面层级/灰阶只取 [tokens.css](web/css/workbench/tokens.css) 的 `--term-*` 派生 token；顶栏直接承载“游戏 / 键位 / 本机与 Web”三页，不保留重复“作弊码”页，玩家解释统一走共享 `PanelTooltip` `simple-tooltip`，不使用原生 `title`。
  默认游戏页把单击“尝试复活/立即返回基地”、声音、画面/性能和紧凑作弊码输入聚合在首屏；完整作弊指令由 [cheat-codes.md](web/help/cheat-codes.md)维护，并通过只复制、不自动执行的模态帮助展示，一键命令包装仍留给修改器迁移。高级表达式与 raw 命令一律按 save 处理；AS2 调用前置脏，部分写后异常返回 `command_ambiguous + requiresReconcile`。音量 preview 在首个 setter 前挂恢复租约，半应用或半恢复保留首次基线并允许重试。
  非 preview 写的 timeout、`DeliveryUnknown` 或 malformed success 均建立 reconcile latch；它跨 owner close、同名 rebind 与 pending cleanup 保留，只由锁存后发出、格式有效且成功的 Flash snapshot 清除，早期迟到 snapshot 不得解锁。
  latch 存在时后续写 fail-closed；Web 不显示“确定未执行”也不自动重放。cancel 半恢复保持面板与首次基线，先以权威 snapshot 对账再允许继续写。<br>36 键双列同屏，标签紧邻控件，键名/键值至少 12px。新“药剂组切换键”默认为 `6`；携键表的 snapshot/apply 精确使用 `keySchemaVersion:2`，旧 `6` 自定义绑定保留并为新动作确定分配空闲键。
  药剂存档 feature 现为 `drugLoadout.version=3`：精确 8 槽 affinity 记录同名药剂最近耗尽位置。任务/商店/拾取、Character Build、DrugIcon 与 Loot v2 共享“最近耗尽原槽→现有同名最低槽→背包同名→背包空槽”规划；从未绑定的新药剂仍进背包。v2 读档迁移到 v3，future v4 原样保留并 fail closed，详见[双药剂组 ADR](../docs/双药剂组-八槽共享冷却-ADR-2026-08-27.md)。
  Host 打开设置时将已有 16:9 Flash 进入帧按原裁切像素、JPEG 90 编成实例内静态图；上限 `4096×2304 / 8 MiB`，拒绝均匀近黑，不降采样至 `512×288`。Flash SA 为 DPI Unaware 且显示器 DPI 更高时，输出保持 `GetClientRect` 物理尺寸，GDI 源按 `windowDpi/monitorDpi` 换算并 `StretchBlt`；其他 awareness 1:1。日志同时记录 source/output，`BitBlt/StretchBlt` false 必须显式失败。
  镜头倍率使用全屏二级模拟器，入口基线按 16:9 填满舞台并保留自然像素；动态镜头关闭时仍按基础倍率预览。点歌器规则与 Web 主题集中在“本机与 Web”。Agent Runtime 仅允许 exact `settings` 与 `settings_camera_preview`；后者固定映射到 `settings + initialView:"camera_preview"`。闭环先用 Flash metadata-only grant + `window.list` 等待 surface 稳定，再用 fresh WebOverlay WGC 验证；它不授予 Flash pixels/input，也不应用或保存设置。
  打击伤害数字属于 Host `UserPrefs`，不再进入 AS2 的游戏设置 snapshot/save；五状态模式、世界行上限和暂停态 Web 对账日志统一以[生产路径](#打击伤害数字生产路径)为准。偏好逐项即时保存，失败恢复控件和内存权威值；旧 `_root.是否打击数字特效`、`_root.同屏打击数字特效上限` 与 Flash MovieClip renderer 均不再是运行时 fallback。
- AS2/Host/Web 三层迁移、数据权威与旧 Flash UI 退役边界以 [迁移护栏](../agentsDoc/as2-web-panel-migration.md)为准。
- 合成配方的默认完整密度、10 列紧凑网格、跨容器持有量、0–99 件存档标记、任务物资高亮、等高材料卡与 exact NPC 头像/摩托车或越野车商店路由以 [P1–P4 ADR](../docs/合成工作台-持有量标记采购联动-P1-P4-ADR-2026-08-17.md)为准。采购 demand 由 AS2 分别投影装备栏/战备箱计数及来源强化上限，材料行以“合成前需要从战备箱取出”或“合成前需要卸下装备”明确表达前置条件，项目浮层说明不会自动移动装备，Web 不猜位置也不把指引伪装成执行按钮。配方直达消费最新权威 preview 并由 Host/AS2 复证，不依赖材料档案 session；装备前置物同样合法。
- 嵌套合成来源使用 28px 扳手方块：同分类在当前 snapshot 原地精确定位；跨分类复用只读 snapshot，并校验 exact producer tuple 后在同一 panel instance 内切换。多来源不得静默选首项。
Minigame 专项说明分别位于 [lockbox](web/modules/minigames/lockbox/README.md)、[pinalign](web/modules/minigames/pinalign/README.md)、[gobang](web/modules/minigames/gobang/README.md)、[黑市全目录影子版](web/modules/minigames/blackmarket/README.md)和[军阀战术演习](web/modules/minigames/warlord/README.md)。
`blackmarket` 仅允许 `dev + shadowOnly`；产品不接调用方 seed，只生成不命中真实目录的匿名货物与 `data:` 表面。lazy closure 不含 exact oracle、dressup/preview 或 debug API，close 绑定 exact 实例；Web 根外夹具仅供 Node QA。面板固定 `1024×576`/`PanelScale`，K 账本按 `deltaV=deltaTp+50×deltaK` 复核；测试见 [testing guide](../agentsDoc/testing-guide.md)。
`warlord` 为 `1024×576` 全锚、`productionWrites=false / battleAuthority=as2`；卡牌隔离战宠，JS resolver 仅供 fixture，恢复只走 Host 内部专用路由。维护者已确认 c4 战后返回；正式列车已 promotion/audit/identity smoke，状态为 `HUMAN_ACCEPTANCE_PASSED / promoted`，未重跑部署后军阀业务。详见[军阀演习 ADR](../docs/军阀战术演习-3D沙盘UI-ADR-2026-08-24.md)。
## 存档编辑与诊断

Bootstrap 存档编辑器当前提供 schema 驱动的简易系统设置、原始编辑、diff、搜索和诊断包导出。字段权威是 [save_schema.json](data/save_schema.json)，业务读写仍经过 Host handler 和存档安全策略。
简易模式的系统卡片仍是迁移期可发现性补偿，不代表 Audio 平台验收。旧 `AudioTask.SetToastSink` 当前只是兼容 no-op，不能声称会弹出音量提示。事件起因、现役边界和退出条件见 [音频迁移期存档编辑器事件记录](../docs/launcher-save-editor-audio-migration-incident-2026-04-28.md)；高频 README 不保存事故时间线。
## 故障定位

| 现象 | 首查 |
|---|---|
| 根入口无响应或秒退 | `logs/bootstrap.log`、`startup-failure-latest.txt`、runtime manifest |
| Core 已起但未 reveal | `logs/launcher.log` 的 WebView2、Flash title receipt、LaunchFlow 状态 |
| Flash 未连总线 | `WaitingConnect → WaitingHandshake`、FlashPlayerTrust 和真实 Launcher 进程 |
| Panel 打不开或立即关闭 | open/admission、instance/generation、focus/lifecycle 和 Web console |
| Web 画面黑屏 | hot reload、WebView2 process failure、overlay suspend/resume；不要先把 watcher 打开 |
| Audio 无声 | Host audio 状态、存档音量、endpoint generation；H2 按专项流程处理 |
| candidate/正式身份不符 | verifier 输出、process path、manifest、identity、closure 和 consensus |

Flash/AS2 变更的编译与 smoke 必须遵守 [Flash CS6 自动化说明](../scripts/FlashCS6自动化编译.md)；没有新鲜 trace、Output Panel 或 IDE 复核时，不声称“已编译通过”。

## 维护规则

以下变化必须在同轮更新本 README 对应 registry/地图，并运行文档治理：

- Core/Bootstrap 入口、参数或启动阶段变化；`AppConfig` key、环境覆盖或用户偏好写入边界变化；
- Bootstrap `cmd`、Panel id、lazy 最终模块或 minigame 入口变化；
- 测试分区、runner、SDK/包版本真源或验证入口变化；
- Host/Web/AS2 协议、权威、生命周期或旧 UI 退役边界变化；
- runtime 构建、候选、promotion 或正式入口术语变化；发布收据、动态测试计数、一次性 runId、截图和事故时间线进入 canonical ADR/`docs/evidence/` 或 Git 历史，不回填高频 README。

```powershell
chcp.com 65001 | Out-Null; node tools/validate-doc-governance.js; git diff --check
```
