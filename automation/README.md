# Automation 自动化脚本使用指南

**文档角色**：启动与运行自动化入口。  
**最后核对代码基线**：commit `e9aaf0a7a6`（2026-07-16）+ 当前装备调制无人值守入口与 runtime v2 发布列车工作树。

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

`agent_control` 是 localhost HTTP `/task` 的窄化控制面，不是任意 GUI/DOM 遥控器。通用 `readyForRuntimeAutomation` 只在 Launcher Ready、Flash reveal、socket、安全 snapshot 决议，以及 AS2 对同一 `attemptId/savePath` 的 `SaveManager.loadAll()` ack 全部满足时成立；arena 在此基础上另加 arena status，继续使用 `readyForArenaCalibration`。

面板迁移可增加领域专用动作，例如装备调制的 `openEquipmentTuning`。该动作只接受与当前状态一致的 `expectedSlot/expectedAttemptId`，slot 必须为 `cf7_agent_*`，并固定发送正式 AS2 opener；客户端不能传任意 panel/initData。返回 `panel_open_requested` 只表示命令已发送，runner 还要等待 Host active panel instance 和该实例首个领域 snapshot。禁止直接调用 `PanelHost.OpenPanel`、Web `Panels.open`，也禁止通过 `/console` 调业务 preview/commit。

所有专用 runner 都应在启动前记录 `/logs` 水位，等待水位之后本轮新鲜 `[BootstrapAS] event=handoff`，再单次调用 `_root.agentEnterResolvedSave()` 复用主时间轴 `读盘` 帧。专用克隆槽负责隔离写入；真实 `crazyflasher7_saves*` 槽默认永不用于无人值守写测试。

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

目标槽固定默认为 `cf7_agent_equipment_tuning`，必须与显式 seed 不同。runner 永久拒绝 live target 和 `--fresh`；不传 `--candidate-root` 时绑定 `formal_runtime`，传入时绑定唯一 `isolated_candidate`，并在报告中硬核验 `runtimeMode/processPath/coreSha256/buildIdentity/payloadClosure` 与启动前期望完全一致。若已有 Launcher，则在改写任何 shadow/SOL 前读取 `agent_control`，只要 Launcher / Flash 当前指向目标 agent 槽或现有进程身份不能满足本轮选择就 fail-fast。SOL 只按“SharedObject 随机根之后的 `localhost/<完整本地游戏路径>/CRAZYFLASHER7MercenaryEmpire.swf/<slot>.sol`”精确归属，不得用 `resources` basename 或 SWF 名模糊扫描其他安装。通过安全门后才备份目标 shadow/SOL 并重建专用克隆槽；随后等待 fresh handoff、同 attempt runtime load ack，调用固定 `openEquipmentTuning`，并以同一 `panelInstanceId` 的 `equipment_tuning_panel_bound` + `equipment_tuning_snapshot_confirmed` 为通过门。它在首个权威 snapshot 后停止，不点击业务控件、不发送 preview/commit。离线安全与契约回归入口为 `node tools/equipment-tuning/run-checks.js`。

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

该脚本会在需要时调用 `automation/start.ps1` 启动 Launcher，通过 HTTP `/task` 的 `agent_control` 选择专用存档；必须等 `bootstrap_reveal_ready` 已完成并观察到本轮新鲜 handoff 后，才通过 AS2 agent 入口复用主时间轴 `读盘` 帧的原“进入游戏”流程，避免在 asLoader 临时 `_root` 上提前消费 snapshot、交接后卡在主菜单。随后等待 `readyForArenaCalibration`；该 ready 必须同时满足 Launcher 存档决议为安全 snapshot、AS2 已完成 `SaveManager.loadAll()` 并回报 `agent_runtime_status`、socket/reveal/arena status 均就绪，再调用 `arena_calibration startBatch/status` 跑批次并生成 summary / run-report。遇到游戏崩溃、socket/HTTP 断开、batch timeout、缺行或异常行时，会生成 rerun manifest，并按 `--max-recovery-attempts`（默认 1）自动关闭 Launcher、重启进档、补跑剩余 case；每轮 attempt、最终失败清单和建议都会写入 `run-report.*`。它不会自动修改战斗代码；如要生成最小 pilot，可显式加 `--generate-pilot --batch-id <id>`。

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

`launcher/build.ps1` 现在只是 prepare → pure producer → read-only policy 的 candidate-only 兼容编排器；它生成隔离 candidate，不覆盖根 bootstrap / 正式 `runtime/`，也不构成本地签名或正式发布。只有在脚本返回的精确 candidate 上继续执行并保留身份证据，状态才会从 `candidate_built` 前进到 `candidate_executed` / `e2e_verified`。新机器先运行 `powershell -ExecutionPolicy Bypass -File ..\tools\bootstrap-runtime-build-env.ps1`，已有环境加 `-VerifyOnly`；普通 Web/AS2/数据改动不要求取得 runtime 发布权，也不要为消除 `source-ahead` 自动重建二进制。

正式发布必须把最终提交冻结成 immutable request，由已 enrollment 的本地 worker 和另一个真实故障域（推荐 GitHub hosted Windows + OIDC/Sigstore）分别生产相同 payload，再凭 production policy receipt 进入 promotion：

当前 `builder-local-a` / `physical-host-a` 的非导出 CurrentUser 私钥与 GitHub hosted OIDC/Sigstore 第二故障域已完成正式 v2 promotion；registry 仍只含本地 builder 公钥，GitHub 证明通过 keyless provenance 验真。cloud workflow 只允许 `Crazyfs` / `Flash-Night` 的固定 actor ID 手工首次 dispatch，但不要求两人共同在线或互相审批；任一获授权发布者都可以把本地票与云端自动票组合成 quorum。一次性 migration marker 仅保留为历史审计输入，后续 v2 部署变化必须完整重走发布列车。

```powershell
$request = ..\tools\new-runtime-build-request.ps1 `
  -QueueRoot <queue-root> -SourceKind Treeish -Treeish <full-commit>
..\tools\invoke-runtime-build-worker.ps1 `
  -QueueRoot <queue-root> -WorkerId <id> -CertificateThumbprint <thumbprint> -Once
..\tools\get-runtime-build-request-status.ps1 `
  -QueueRoot <queue-root> -RequestId $request.requestId
$cloud = ..\tools\invoke-runtime-github-build.ps1 -SourceCommitOid <full-commit>
```

最后一条命令会触发固定 cloud workflow、等待精确 run、安全解压并产出 `$cloud.candidateRoot` / `$cloud.proofPath`。unsigned job 交接 artifact 保留 1 天，失败诊断与 signed 结果保留 7 天；超期未 promotion 就重新 dispatch，不把 Actions artifact 当长期档案。request、队列/CAS、双故障域 quorum、receipt 与 `promote-runtime-bundle.ps1` 的完整步骤以 [runtime v2 发布列车](../docs/runtime-build-reproducibility.md) 为准。当前正式部署已是 v2；任何时候都禁止手工换 manifest、伪造证明，或把单机 candidate 复制进根 runtime。

### 改 Flash / AS2

不要把本目录当成编译 smoke 入口；改用：

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File ..\scripts\compile_test.ps1
```

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
