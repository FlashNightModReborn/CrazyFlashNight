# Automation 自动化脚本使用指南

**文档角色**：启动与运行自动化入口。  
**最后核对代码基线**：上游 `origin/main` `b072f97841ccb30e167c14495241ae64d9054e22`（2026-07-21 发布前复核）+ 当前 `release/map-loot-20260721-final` 未 promotion 发布候选树；source-tree、candidate 与 runtime 门按下文分层记录。

本目录只负责 **运行与启动自动化**。  
Flash CS6 编译 smoke、JSFL、trace、截图与计划任务细节，统一放在 [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md)。

## 1. 这个目录负责什么

- 首次环境准备（Flash 信任目录等）
- 一键启动游戏 / Launcher
- 兼容旧入口脚本的过渡封装
- 运行期常见问题的快速排查

## 2. 首次配置

### PowerShell 执行策略

Windows 默认可能禁止本地脚本执行。常用做法：

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

如果只想对当前窗口生效：

```powershell
Set-ExecutionPolicy Bypass -Scope Process
```

### 首次运行 `configure_server.ps1`

```powershell
cd "<项目根目录>\\automation"
.\configure_server.ps1
```

用途：

- 配置 Flash trust
- 校正启动所需的本地环境前置项

## 3. 日常启动

本地日常开发推荐显式走 `dev.ps1`，或双击项目根的 `本地开发启动.cmd`。该入口计算当前 Worktree build identity，只精确复用同身份 candidate；无命中时在本机生成隔离 candidate，但始终报告 `NOT_DEPLOYED`，不会写根 bootstrap 或正式 `runtime/`。

```powershell
cd "<项目根目录>"
.\automation\dev.ps1
# 等价的双击入口：.\本地开发启动.cmd

# 开发 candidate 状态 / 只复用 / 强制重建 / 只构建不启动
.\automation\dev.ps1 -Status
.\automation\dev.ps1 -ReuseOnly
.\automation\dev.ps1 -ForceBuild
.\automation\dev.ps1 -BuildOnly
```

`-Status` 只读报告当前身份、精确匹配和同身份闭包分叉；`-ReuseOnly` 禁止缓存未命中时构建；`-ForceBuild` 强制新建 candidate，但新旧同身份闭包不一致仍 fail-closed；`-BuildOnly` 只选择/构建并验证 candidate，不启动进程。忽略路径 `tmp/runtime-dev/active.v1.json` 只是便于精确复用的索引，每次执行前都会重算 Worktree 身份并重验 candidate，不是信任或部署证据。

断网可以完成已有 candidate 的精确复用；若需重建，本机必须已安装并通过锁定的 .NET / MSVC / Windows SDK / Rust 工具链，且 NuGet / Cargo 依赖已在本地缓存。首次开发机供给仍可能需要联网，这与正式云端双生产者验证是两个独立问题。

正式已部署入口与低层诊断入口则明确区分：

```powershell
# 无 CandidateRoot：只启动项目根已 promotion 的正式 runtime
.\automation\start.ps1
# 低层诊断兼容入口：只接受已知的绝对 candidateRoot
.\automation\start.ps1 -CandidateRoot "<absolute candidateRoot>"
```

`automation/start.ps1` 无参数时不会扫描或猜选 `launcher/bin`、`tmp/runtime-candidates/` 中的开发输出。源码领先于正式二进制时，它仍运行上一次已 promotion 的身份。日常开发不再要求人工复制 candidateRoot；`start.ps1 -CandidateRoot` 仅保留给调试指定产物等低层场景。

启动链负责：

- 启动 Guardian Launcher
- 走当前默认运行链路
- 使用内嵌总线与现有宿主架构
- `automation/start.ps1`、`scripts/gobang_trainer_cycle.ps1` 与 `tools/cfn-cli.sh` 的默认入口都绑定正式根部署；直启正式 Core 前调用根 bootstrap `--verify-only`，manifest 闭包不完整、含额外文件或二进制混搭时 fail-fast
- `dev.ps1` 把选中的精确 candidate 交给 `start.ps1 -CandidateRoot`；后者只接受本仓 v2 candidate 的绝对 canonical 路径，使用候选自身 bootstrap `--verify-runtime-only`，拒绝 reparse / metadata / manifest / Core 字节身份漂移
- 清理已失效的 `launcher_ports.json`，并等待新的端口文件写入后再返回；若 Core 进程提前退出或 30 秒内未写端口，脚本返回失败

两种运行模式启动前后都打印并硬核验 `runtimeMode`（`formal_runtime|isolated_candidate`）、`processPath`、`coreSha256`、`buildIdentity`、`payloadClosure`；详见 [`launcher/README.md`](../launcher/README.md#离线开发入口与身份绑定候选)。统一状态为 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`；只有 promotion 后再由无参数标准入口验证同一身份，才可称“已部署 / 正式验收”。

### 全员直推与 native 事后审计

所有 write collaborator，包括 `Crazyfs`、`Flash-Night`，都继续在现有 Git 客户端中 `Pull → Commit → Push main`；没有身份 PR 门、CODEOWNER 前置审批或 required Actions check。PR 与根目录 `一键提交到主线.cmd` 只作为自愿讨论辅助，不是准入入口。

普通 docs/data/Flash/XFL/Web-only 提交不触发 runtime workflow。native 源码 push 后 `audit-native-runtime` 可以成功报告 `source-ahead`，表示源码领先于正式部署，不要求每次立即 promotion；只有根 EXE、`runtime/**`、manifest/consensus 等部署闭包变化而缺少完整 v2 promotion 时才失败报警。报警发生在 push 之后，不能撤销已进入 `main` 的提交。

离线回归与远端规则复核：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\tools\test-submit-contribution.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\tools\test-main-branch-admission.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\tools\audit-main-branch-admission.ps1 -ExpectedState ConfigOnly
```

native 审计边界、正式 release 双生产者共识、三条零 Actions ruleset 与 GitHub Free 无服务端 path restriction 的残余风险，统一看 [协作者直推与 native/runtime 发布边界](../docs/contribution-workflow.md)。远端规则漂移只读复核：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\tools\audit-main-branch-admission.ps1`。

### 无人值守运行态控制面

`agent_control` 是 localhost HTTP `/task` 的窄化控制面，不是任意 GUI/DOM 遥控器。通用 `readyForRuntimeAutomation` 只在 Launcher Ready、socket、安全 snapshot 决议、AS2 对同一 `attemptId/savePath` 的 `SaveManager.loadAll()` ack，以及 Host 从**非 legacy 的同一个 UiData 包**实收 `s:1|ga:<当前 save attemptId>` 后成立；`status.gameEnteredObserved/gameEnteredAttemptId` 显式暴露最后一项，裸 `s:1`、缺 `ga`、stale `ga` 或 legacy 包均不能解锁，缺失时 blocker 为 `game_enter_not_observed`。每次 `start` 都无条件清除旧 `gameEnteredObserved/gameEnteredAttemptId` 并重新上锁；实收 `s:0` 只作防御性清锁，目前没有现役正常退出调用它的证据。arena 在此基础上另加 arena status，继续使用 `readyForArenaCalibration`。

面板迁移可增加领域专用动作，例如装备调制的 `openEquipmentTuning`。该动作只接受与当前状态一致的 `expectedSlot/expectedAttemptId`，slot 必须为 `cf7_agent_*`，并固定发送正式 AS2 opener；客户端不能传任意 panel/initData。返回 `panel_open_requested` 只表示命令已发送，runner 还要等待 Host active panel instance 和该实例首个领域 snapshot。禁止直接调用 `PanelHost.OpenPanel`、Web `Panels.open`，也禁止通过 `/console` 调业务 preview/commit。

所有专用 runner 的因果顺序固定为：在调用 `agent_control start` **之前**记录 `/logs` 水位 → 调用 `start` 并取得 expected slot / `attemptId` → 只接受该水位之后本轮新鲜 `[BootstrapAS] event=handoff` 与真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared` → 确认 watchdog 未触发后只调用一次 `_root.agentEnterResolvedSave()` → helper 先执行 `_root.notifyGameEntered()`，使同一 UiData 包携带 `s:1|ga:<_bootstrapAttemptId>`，再按 `SaveManager.loaded` 决定直接返回或 `gotoAndStop("读盘")` → Host 必须观察到 `gameEnteredAttemptId==expectedAttemptId`，并在同 attempt runtime ack 等其余门满足后才允许 runtime ready。reveal watchdog 不算标题帧回执，缺失统一失败为 `title_frame_not_observed`；notifier 尚未注入时必须 fail-closed。专用克隆槽负责隔离写入；真实 `crazyflasher7_saves*` 槽默认永不用于无人值守写测试。

### 装备调制只读直达门

从仓库根运行：

```powershell
chcp.com 65001 | Out-Null
node tools/equipment-tuning/run-unattended.js `
  --seed-slot crazyflasher7_saves2 `
  --shutdown

# 验证新 Host candidate 时：
node tools/equipment-tuning/run-unattended.js `
  --seed-slot crazyflasher7_saves2 `
  --candidate-root "<absolute candidateRoot>" `
  --shutdown
```

目标槽固定默认为 `cf7_agent_equipment_tuning`，必须与显式 seed 不同。runner 永久拒绝 live target 和 `--fresh`；不传 `--candidate-root` 时绑定 `formal_runtime`，传入时绑定唯一 `isolated_candidate`，并在报告中硬核验 `runtimeMode/processPath/coreSha256/buildIdentity/payloadClosure` 与启动前期望完全一致。若已有 Launcher，则在改写任何 shadow/SOL 前读取 `agent_control`，只要 Launcher / Flash 当前指向目标 agent 槽或现有进程身份不能满足本轮选择就 fail-fast。SOL 只按“SharedObject 随机根之后的 `localhost/<完整本地游戏路径>/CRAZYFLASHER7MercenaryEmpire.swf/<slot>.sol`”精确归属，不得用 `resources` basename 或 SWF 名模糊扫描其他安装。通过安全门后才备份目标 shadow/SOL 并重建专用克隆槽；随后必须在调用 `start` 前记录 `/logs` 水位，再按 start→fresh handoff + 水位后真实 title-frame marker（watchdog 拒绝）→exact slot/attempt→single enter→同包 attempt receipt→同 attempt runtime load ack 的顺序，等待 `gameEnteredObserved=true` 且 `gameEnteredAttemptId==expectedAttemptId`，再调用固定 `openEquipmentTuning`，并以同一 `panelInstanceId` 的 `equipment_tuning_panel_bound` + `equipment_tuning_snapshot_confirmed` 为通过门。它在首个权威 snapshot 后停止，不点击业务控件、不发送 preview/commit。离线安全与契约回归入口为 `node tools/equipment-tuning/run-checks.js`。

### 无人值守斗兽标定

斗兽标定的无人值守外层入口在仓库根目录运行：

```powershell
chcp.com 65001 | Out-Null
node tools/arena-calibration/run-unattended.js `
  --slot cf7_agent_arena_calibration `
  --seed-slot crazyflasher7_saves2 `
  --manifest tmp/arena-calibration/batches/<batchId>/case_manifest.json
```

`--slot` 缺省为 `cf7_agent_arena_calibration`，也可以显式传入；runner 会在启动前把该专用槽位从 `--seed-slot` 或最新有效 shadow 存档播种，并备份/移除目标槽位残留 SOL，避免复用运行中的旧 SOL。默认拒绝 `crazyflasher7_saves*` 正式槽位与 `--fresh`，除非显式传 `--allow-live-slot` / `--allow-fresh`，这两个开关只用于人工取证，不用于无人值守批跑。

该脚本会在需要时调用 `automation/start.ps1` 启动 Launcher，通过 HTTP `/task` 的 `agent_control` 选择专用存档；它必须在调用 `agent_control start` 前记录 `/logs` 水位，再观察到 start 后本轮新鲜 handoff 与水位后的真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`，watchdog 不计入，缺失时报 `title_frame_not_observed`。随后才校验 exact slot / attempt 并只调用一次 agent enter。helper 先发正常入口同款 `notifyGameEntered()`，让同一 UiData 包携带 `s:1|ga:<attemptId>`，再 `gotoAndStop("读盘")`（已 loaded 时直接返回）。`readyForArenaCalibration` 必须同时满足安全 snapshot、同 attempt 的 `agent_runtime_status`、Host 的 `gameEnteredObserved=true` 且 `gameEnteredAttemptId` 精确匹配、socket 与 arena status，再调用 `arena_calibration startBatch/status` 跑批次并生成 summary / run-report。遇到游戏崩溃、socket/HTTP 断开、batch timeout、缺行或异常行时，会生成 rerun manifest，并按 `--max-recovery-attempts`（默认 1）自动关闭 Launcher、重启进档、补跑剩余 case；每轮 attempt、最终失败清单和建议都会写入 `run-report.*`。它不会自动修改战斗代码；如要生成最小 pilot，可显式加 `--generate-pilot --batch-id <id>`。

当前证据已分为自动门与精确候选实机两层。`node tools/test-agent-entry-contract.js` 静态锁定 notifier guard、`s:1|ga:<attemptId>` 同包与 `gotoAndStop("读盘")` 顺序；装备与斗兽 runner 的 `--check` 覆盖 post-watermark 真实 title-frame marker、watchdog 拒绝、`title_frame_not_observed`、fresh handoff、exact slot/attempt、single enter 和 attempt-bound `gameEnteredObserved`。Launcher source-tree 全量 **1220/1220**，其中 AgentControl 定向 **29/29**；装备 runner `--check` 为 **34 checks**。此外，隔离 candidate `tmp/runtime-candidates/v2/c-2a0cddb077b7-08846e81b3-20260721t100014612z-f32a40a3`（build identity `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107`、payload closure `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C`、Core SHA-256 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`）已精确启动并载入专用槽 `cf7_agent_loot_target_full_v1`。attempt `62f04fa249c44d94ba3171f619e61754` 严格按“调用 `start` 前记录 `/logs` 水位 → `start` → fresh handoff + 真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`（watchdog **0**）→ 唯一一次 `_root.agentEnterResolvedSave()` → 同包 `s:1|ga:<exact attempt>` → Host `gameEnteredAttemptId==expectedAttemptId` → `readyForRuntimeAutomation=true`、`blockers=[]`、`saveRuntime` exact loaded”执行；人类同时确认 NativeHud 可见且其指令有效，Host `activePanel=stage-select`。随后同一 candidate 已真人完成正常 NativeHud 入口、满背包混合箱→同实例 organizer→真实二次确认丢弃牛肉罐头 ×16→fresh ACTIVE 返回且无 close/rebind→领取黑暗吉他→terminal close/unpause 回游戏的主链；普通主页又在单次 close 后进入 suspended，同锚点重开时强化石 **×2 + ×3** 内容一致且无旧 AS2 UI，最终两次 claim 与一次 terminal close 收束。因此本轮单 canary 资源箱切片达到 `e2e_verified / NOT_DEPLOYED`。其 25-file native bundle 不含 `launcher/web`，外部 Web 修复必须另用 [测试指南](../agentsDoc/testing-guide.md) 所列 SHA-256 与实机日志绑定，不能由 native identity/closure 代证。候选随后优雅 shutdown，Guardian PID **14820**、HTTP/XMLSocket **1192/1924** 均退出，Flash CS6 PID **20444** 保留；没有 promotion、standard-entry 或部署结论。

默认启动前会先跑轻量门禁 `--build-gate arena-tools`（即 `node tools/arena-calibration/run-checks.js`）。验证新 Host candidate 时必须先独立构建，再把脚本返回的精确路径交给 runner；可在 runner 内追加不产二进制的 `launcher-tests`：

```powershell
$repo = (Resolve-Path .).Path
$candidate = .\launcher\build.ps1 -ProjectRoot $repo -BuilderId local-dev -SkipPolicy | Select-Object -Last 1
node tools/arena-calibration/run-unattended.js `
  --slot cf7_agent_arena_calibration `
  --seed-slot crazyflasher7_saves2 `
  --manifest tmp/arena-calibration/batches/<batchId>/case_manifest.json `
  --candidate-root $candidate.candidateRoot `
  --build-gate launcher-tests
```

可执行 gate：`none`、`arena-tools`、`launcher-tests`、`as2-publish`、`as2-test`。`launcher-build` 及会展开到它的 `launcher` 仅保留参数识别并立即 fail-fast，因为嵌入构建只能产生一个未选择的 candidate；必须按上例先构建再传 `--candidate-root`。runner 在启动 / 重启 / 恢复各阶段都要求实际 `runtimeMode/processPath/coreSha256/buildIdentity/payloadClosure` 与预选身份一致，字段写入 `run-report.*`；门禁失败或身份漂移会停止，不继续进游戏。自动恢复只消费 runner 自己生成的 rerun manifest，不会在失败后自行修改业务代码或反复编译。

### 兼容旧入口

- `start_game.ps1`：兼容旧入口，当前等价于 `start.ps1`
- `start_server.ps1`：已废弃，不再代表当前架构

## 4. 改代码后的常用动作

### 改 Launcher

```powershell
chcp.com 65001 | Out-Null
powershell -File ..\launcher\tests\run_tests.ps1
# 需要隔离的本地完整 candidate 时（不会部署正式 runtime）：
powershell -File ..\launcher\build.ps1 -BuilderId local-dev
```

`launcher/build.ps1` 现在只是 prepare → pure producer → read-only policy 的 candidate-only 兼容编排器；它生成隔离 candidate，不覆盖根 bootstrap / 正式 `runtime/`，也不构成本地签名或正式发布。只有在脚本返回的精确 candidate 上继续执行并保留身份证据，状态才会从 `candidate_built` 前进到 `candidate_executed` / `e2e_verified`。新机器先运行 `powershell -ExecutionPolicy Bypass -File ..\tools\bootstrap-runtime-build-env.ps1`，已有环境加 `-VerifyOnly`；若已有实例的精确 MSVC 字节不匹配，bootstrap 必须使用锁定 bootstrapper 的专用 side-by-side 目录，只有工具字节已匹配而仅缺 SDK 时才允许 `modify`，Windows PowerShell 5.1 下 `vswhere` 顶层数组必须逐实例输出。普通 Web/AS2/数据改动不要求取得 runtime 发布权，也不要为消除 `source-ahead` 自动重建二进制。

正式发布必须把最终提交冻结成 immutable request，由已 enrollment 的本地 worker 和另一个真实故障域（推荐 GitHub hosted Windows + OIDC/Sigstore）分别生产相同 payload，再凭 production policy receipt 进入 promotion：

正式 v2 consensus 当前绑定 request `184428C21AF75D0BE8C24D33237AB265B20C0240ECC80AC32850CF17829E4420`、source commit `9f4669e03e59016f820df2424cc5b4851a1c566a`、build identity `B643463C39ACA1F9ED2BC5CA4F36F4C4A4E3A8F9D020A04CB379F9F83B2F6CB1` 与 payload closure `FA1EC72FEA78623653EA3D4E4794334A215E535FECE0597B003FA5BED09BD000`；当前上游基线 `origin/main` 为 `b072f97841ccb30e167c14495241ae64d9054e22`，发布候选树位于其上，因此正式部署与当前源码仍须分层陈述。registry 只保存本地 builder 公钥，GitHub 证明通过 keyless provenance 验真。换机账户没有复制 `builder-local-a` 的历史私钥；维护者确认这是新的真实物理机后，已 enrollment `builder-local-b` / `physical-host-b`，CurrentUser 不可导出 key 的 keyId 为 `EB5D32E04B6EE8697850314E19698DE1A3FACFFCCC6418A12CF7FEDE6033CDA5`、thumbprint 为 `141A0B12F18A1C25C2BF4A32B3C279F81C44D007`，其公钥 entry 已加入待发布 registry。只有该 registry 与完整 source/policy 一起进入 immutable commit 后，本机才能签正式 local proof；cloud workflow 仍只允许 `Crazyfs` / `Flash-Night` 的固定 actor ID 首次 dispatch，并以 GitHub hosted OIDC/Sigstore 提供不同故障域的第二票。

```powershell
$queueRoot = 'C:\cf7q' # 本列车专用短根；不得与未 ready/superseded 的旧 request 混跑
$request = ..\tools\new-runtime-build-request.ps1 `
  -QueueRoot $queueRoot -SourceKind Treeish -Treeish <full-commit>
..\tools\invoke-runtime-build-worker.ps1 `
  -QueueRoot $queueRoot -WorkerId <id> -CertificateThumbprint <thumbprint> -Once
..\tools\get-runtime-build-request-status.ps1 `
  -QueueRoot $queueRoot -RequestId $request.requestId
$cloud = ..\tools\invoke-runtime-github-build.ps1 -SourceCommitOid <full-commit>
```

最后一条命令会从受保护的单路径段 `runtime-build-v2/<release-id>` source tag 触发固定 cloud workflow，并验证 API-resolved tag、`GITHUB_REF/GITHUB_SHA` 与 run `headSha` 都精确绑定请求的 full commit；随后等待精确 run、安全解压并产出 `$cloud.candidateRoot` / `$cloud.proofPath`。unsigned job 交接 artifact 保留 1 天，失败诊断与 signed 结果保留 7 天；超期未 promotion 就重新 dispatch，不把 Actions artifact 当长期档案。request、队列/CAS、双故障域 quorum、receipt 与 `promote-runtime-bundle.ps1` 的完整步骤以 [runtime v2 发布列车](../docs/runtime-build-reproducibility.md) 为准。最近一次完整 Runtime Lane C 复跑为 **11/11 个入口 exit 0**；十个 scalar 套件合计 **408**，guardrails 另报告 `scripts=3 / unsafeCandidateCases=3`。bootstrap / build environment 均 exit **0**；这些只证明 runtime/admission 守门回归，不产生 candidate identity、runtime proof 或 promotion。FCA19/B2AF/231388 candidate 仅保留为 organizer 与 corrected Agent entry 之前的历史。当前精确开发 candidate 位于 `tmp/runtime-candidates/v2/c-2a0cddb077b7-08846e81b3-20260721t100014612z-f32a40a3`，build identity 为 `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107`，payload closure 为 `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C`，Core SHA-256 为 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`；它已完成 corrected Agent entry、正常 NativeHud、organizer 主链与普通主页 suspend→same-anchor 内容不变 reopen→最终领取，单 canary 资源箱切片状态为 `e2e_verified / NOT_DEPLOYED`。该目录的 native bundle 不含 `launcher/web`，其 identity/closure 不能绑定外部 Web 字节。候选已优雅退出，且从未产生 request、receipt、签名 quorum、promotion 或 standard-entry 证据；不得表述为已部署或正式验收。功能回归证据统一维护在 [测试指南](../agentsDoc/testing-guide.md)，不在 runtime 发布段重复复制。任何时候都禁止手工换 manifest、伪造证明，或把单机 candidate 复制进根 runtime。

### 改 Flash / AS2

不要把本目录当成编译 smoke 入口；改用：

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File ..\scripts\compile_test.ps1
```

asLoader 发布用 `powershell -ExecutionPolicy Bypass -File ..\scripts\compile_test.ps1 -Target publish -TimeoutSeconds 300`；`publish|asloader` 别名现已隐式选择 `doc.publish()` 并自动启用 `-VerifySwf scripts/asLoader.swf`，因此可省略 `-PublishOnly`。任意显式 FLA/XFL 路径只有在需要禁止 testMovie 时才额外传 `-PublishOnly`。本轮生产 AS2 已修改并发布：`scripts/asLoader.swf` 为 **1,041,903 bytes**（mtime **2026-07-21 17:12:59**），SHA-256 `AD799970A8A2AFD0F9A402C704934F08985A3144FA608A7564E17BC4899C815E`，Git blob `3dd59f73f9fc71128da99c2eb03796290df1e010`，Compiler Errors **0/0**。publish-only 不生成行为 trace，行为证据来自独立 fresh map-loot TestLoader runId `dbcc28a3d99444c38bde38029ff4bd61`：Service **159/159** + Planner **7/7**，合计 **166/166**；AS2 BOM 门为 **227/227**。

### 调导弹 / 追踪参数

离线调优 `MissileMovement.as` / `missileConfigs.xml` 时，优先用专用模拟器先筛参数：

```powershell
chcp.com 65001 | Out-Null
python ..\tools\missile-tuning-sim\run_sim.py audit --verbose
python ..\tools\missile-tuning-sim\run_sim.py compare --configs interceptor cruise pressureSlow --velocity 20 --use-prelaunch
python ..\tools\missile-tuning-sim\run_sim.py scan --base-config cruise --objective loiter --use-prelaunch --grid initialSpeedRatio=0.25,0.3 rotationSpeed=1.1,1.2 preLaunchFrames.min=18,20
```

适用边界：

- 用于离线比较预设、轨迹与“持续施压”指标
- `loiter` 目标适合慢巡航 / 滞空型导弹，`--grid` / `--set` 支持 `preLaunchFrames.min=18` 这类嵌套字段
- 默认按“已指定攻击目标”路径模拟，不替代游戏内最终手感复核

## 5. 常见问题

### 启动脚本无法执行

- 先检查 PowerShell 执行策略
- 再确认脚本路径是否位于当前项目根

### 启动后无法正常连总线

- 优先用 `tools/cfn-cli.sh status` 或 `tools/cfn-cli.ps1 status` 看当前总线状态
- 必要时看 `launcher/README.md` 的运行与诊断章节

### 机器路径与默认路径不同

- 不要手改文档里的旧绝对路径示例去推断工程结构
- 以当前项目根目录为基准运行脚本

## 6. 文件说明

| 文件 | 用途 |
|------|------|
| `config.toml` | 运行时配置 |
| `configure_server.ps1` | 首次环境准备 |
| `dev.ps1` | 推荐的显式本地开发入口；精确复用/生成 Worktree candidate，始终 `NOT_DEPLOYED` |
| `start.ps1` | 正式根部署的当前标准入口；不自动选择 candidate |
| `../本地开发启动.cmd` | `dev.ps1` 的根目录双击封装；失败默认暂停便于阅读错误 |
| `start_game.ps1` | 兼容旧入口 |
| `start_server.ps1` | 已废弃的旧入口 |
| `publish.ps1` | 开发态批量发布辅助脚本 |
| `../一键提交到主线.cmd` | 自愿走 PR 讨论时的辅助入口；不参与主线准入 |

## 7. 相关文档

- 启动 / 运行与子系统细节：[`launcher/README.md`](../launcher/README.md)
- 测试矩阵：[`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- Flash 编译 smoke：[`scripts/FlashCS6自动化编译.md`](../scripts/FlashCS6自动化编译.md)
- 离线导弹调优：[`tools/missile-tuning-sim/README.md`](../tools/missile-tuning-sim/README.md)
- 协作者直推与 native/runtime 发布边界：[`docs/contribution-workflow.md`](../docs/contribution-workflow.md)
