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

```powershell
cd "<项目根目录>\\automation"
.\start.ps1
```

脚本负责：

- 启动 Guardian Launcher
- 走当前默认运行链路
- 使用内嵌总线与现有宿主架构
- `automation/start.ps1`、`scripts/gobang_trainer_cycle.ps1` 与 `tools/cfn-cli.sh` 直启 Core 前调用根 bootstrap `--verify-only`，manifest 闭包不完整、含额外文件或二进制混搭时 fail-fast
- 清理已失效的 `launcher_ports.json`，并等待新的端口文件写入后再返回；若 Core 进程提前退出或 30 秒内未写端口，脚本返回失败

### 普通合作者一键提交到主线

在 Git 客户端完成本地 commit 后，双击仓库根目录的 `一键提交到主线.cmd`。它会把本地 `main` 上尚未发布的 commit 安全转成 `contrib/*` 分支、ready PR 和允许时的 auto-merge；文档/内容车道会保持窗口显示检查进度，合并后 `--ff-only` 清理并回到 `main`，软件车道则显示待审 PR 后返回。不要求使用者手工建立分支或理解 PR。若远端已经前进、工作树未提交或 Git 正处于 merge/rebase/cherry-pick 等操作中间态，工具会停下而不自动 rebase/reset；Git 可从 PATH、Git for Windows 或 GitHub Desktop 自带版本解析。

命令行入口与离线回归：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\tools\submit-contribution.ps1 -Wait
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\tools\test-submit-contribution.ps1
```

普通内容是否自动合并、哪些路径才触发 runtime 双故障域 promotion，统一看 [普通合作者一键贡献与路径分域](../docs/contribution-workflow.md)。

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
```

目标槽固定默认为 `cf7_agent_equipment_tuning`，必须与显式 seed 不同。runner 永久拒绝 live target 和 `--fresh`；若已有 Launcher，则在改写任何 shadow/SOL 前读取 `agent_control`，只要 Launcher 或 Flash 当前指向目标 agent 槽就 fail-fast。SOL 只按“SharedObject 随机根之后的 `localhost/<完整本地游戏路径>/CRAZYFLASHER7MercenaryEmpire.swf/<slot>.sol`”精确归属，不得用 `resources` basename 或 SWF 名模糊扫描其他安装。通过安全门后才备份目标 shadow/SOL 并重建专用克隆槽；随后等待 fresh handoff、同 attempt runtime load ack，调用固定 `openEquipmentTuning`，并以同一 `panelInstanceId` 的 `equipment_tuning_panel_bound` + `equipment_tuning_snapshot_confirmed` 为通过门。它在首个权威 snapshot 后停止，不点击业务控件、不发送 preview/commit。离线安全与契约回归入口为 `node tools/equipment-tuning/run-checks.js`。

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

默认启动前会先跑轻量门禁 `--build-gate arena-tools`（即 `node tools/arena-calibration/run-checks.js`）。如本轮确实需要重编译或验证指定栈，可显式传：

```powershell
node tools/arena-calibration/run-unattended.js `
  --slot cf7_agent_arena_calibration `
  --seed-slot crazyflasher7_saves2 `
  --manifest tmp/arena-calibration/batches/<batchId>/case_manifest.json `
  --build-gate launcher
```

可选 gate：`none`、`arena-tools`、`launcher-build`、`launcher-tests`、`launcher`、`as2-publish`、`as2-test`。除 `arena-tools` 外，runner 会先尝试关闭已有 Launcher，再执行 gate；失败会写入 run-report 并停止，不继续进游戏。自动恢复只消费 runner 自己生成的 rerun manifest，不会在失败后自行修改业务代码或反复编译。

### 兼容旧入口

- `start_game.ps1`：兼容旧入口，当前等价于 `start.ps1`
- `start_server.ps1`：已废弃，不再代表当前架构

## 4. 改代码后的常用动作

### 改 Launcher

```powershell
chcp.com 65001 | Out-Null
powershell -File ..\launcher\tests\run_tests.ps1
# 需要本地完整 candidate 时：
powershell -File ..\launcher\build.ps1 -BuilderId local-dev
```

`launcher/build.ps1` 现在只是 prepare → pure producer → read-only policy 的兼容编排器；它生成隔离 candidate，但不构成本地签名或正式发布。新机器先运行 `powershell -ExecutionPolicy Bypass -File ..\tools\bootstrap-runtime-build-env.ps1`，已有环境加 `-VerifyOnly`；普通 Web/AS2/数据改动不要求取得 runtime 发布权，也不要为消除 `source-ahead` 自动重建二进制。

正式发布必须把最终提交冻结成 immutable request，由已 enrollment 的本地 worker 和另一个真实故障域（推荐 GitHub hosted Windows + OIDC/Sigstore）分别生产相同 payload，再凭 production policy receipt 进入 promotion：

当前 `builder-local-a` / `physical-host-a` 的非导出 CurrentUser 私钥已实签验证，registry 仅含其公钥；仍缺 cloud 第二票与正式 v2 promotion。一次性 migration marker 只负责让固定 workflow 先进入 default branch，不能发布二进制；marker 合入后下一提交必须完成 v2 promotion。

```powershell
$request = ..\tools\new-runtime-build-request.ps1 `
  -QueueRoot <queue-root> -SourceKind Treeish -Treeish <full-commit>
..\tools\invoke-runtime-build-worker.ps1 `
  -QueueRoot <queue-root> -WorkerId <id> -CertificateThumbprint <thumbprint> -Once
..\tools\get-runtime-build-request-status.ps1 `
  -QueueRoot <queue-root> -RequestId $request.requestId
$cloud = ..\tools\invoke-runtime-github-build.ps1 -SourceCommitOid <full-commit>
```

最后一条命令会触发固定 cloud workflow、等待精确 run、安全解压并产出 `$cloud.candidateRoot` / `$cloud.proofPath`。request、队列/CAS、双故障域 quorum、receipt 与 `promote-runtime-bundle.ps1` 的完整步骤以 [runtime v2 发布列车](../docs/runtime-build-reproducibility.md) 为准。当前正式部署仍是 v1；首次 v2 promotion 前禁止手工换 manifest，任何时候都禁止把单机 candidate 复制进根 runtime。

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
| `start.ps1` | 当前总入口 |
| `start_game.ps1` | 兼容旧入口 |
| `start_server.ps1` | 已废弃的旧入口 |
| `publish.ps1` | 开发态批量发布辅助脚本 |
| `../一键提交到主线.cmd` | 普通合作者双击提交入口 |

## 7. 相关文档

- 启动 / 运行与子系统细节：[`launcher/README.md`](../launcher/README.md)
- 测试矩阵：[`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- Flash 编译 smoke：[`scripts/FlashCS6自动化编译.md`](../scripts/FlashCS6自动化编译.md)
- 离线导弹调优：[`tools/missile-tuning-sim/README.md`](../tools/missile-tuning-sim/README.md)
- 普通合作者一键贡献：[`docs/contribution-workflow.md`](../docs/contribution-workflow.md)
