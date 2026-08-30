# Automation 自动化脚本使用指南

**文档角色**：启动与运行自动化入口。  
**当前正式列车（2026-08-28，斗兽星期级全量标定 Gate F）**：release source `c64a5440e5506a3f1567143711f984d063e56505`、tag `runtime-build-v2/20260828-arena-calibration-gate-f-v3`、release tree `abe5cd0ef38fff3e596b4bfe4c84ea3c30e5ead8` 与 request `62E4E1537771F0638DB9204A950DD19598962F7E8BBE7D73E2916FAB519982FE` 已由本地 X509 `builder-local-b` / `physical-host-b` 与 GitHub OIDC/Sigstore `github-hosted-windows`（cloud run `33130111918`）对 identity `48E2ACEA81194C0D6C3A89226DEC2748192612B5514D3F3ADB8444FA4AF6C528`、closure `DA7E5BD135FF2407ED7CE459F521BEA95C9CB6F5CC63AA5291ABAC795DAF59F1` 达成双 signer / 双 faultDomain 共识。39/39 final receipt SHA-256 为 `AC2FE8CA89D3A88C70C383E4C3DF84639DDFA956761793A16D66780634D95738`；deployment commit `693baf7051d9e67be8930b309dc14eea65c0eab6` 与 post-promotion audit run `33130680653` 均已推送/通过，审计明确输出 `state=promoted`、`deploymentChanged=true`。
正式根 bootstrap `--verify-only`、33-file bundle 与 signed consensus 已通过。历史 `gate-f-week-full-v2` 首轮 formal soak 保留 30 行候选 timeout 事实，v3 的 30/30 fresh soak 与 115 条全量事实因旧进程自抢占暂停；进程树和不可变 admission snapshot 修复后的 `gate-f-week-full-v4` 已取得 30/30 fresh soak，并在全量累计 16 个 completed shard + 1 个 F2 timeout-anomaly shard、280 条 durable row、0 duplicate。F2 p2 原向 10/10 finished、换边 5 finished + 5 timeout，0 error，exact runtime、存档与 shutdown 正常；旧 driver 将纯候选 timeout-rate 误作基础设施失败而暂停。tracked plan 继续保持 58 个 scheduled candidate + `B12` quarantine、198 个 shard / 3,255 个 run，执行 campaign 提升为 `gate-f-week-full-v5`；v5 将纯 timeout-rate 写入 `candidate_timeout_anomaly / keep_provisional` 后继续，error/runtime/save/disk/时长漂移仍 fail closed。v4 事实原样保留但不跨 plan hash 混计，v5 重新 freeze/arm/fresh soak 前不称 Gate F 通过、斗兽业务 `standard_entry_verified` 或新真人 PVE 证据。

**上一正式列车（2026-08-28，双药剂组与八槽共享冷却；历史）**：release source `b2bc05775c621616fe64be55354aebe21c63a2af`、tag `runtime-build-v2/20260827-dual-drug-banks-v1`、release tree `826f37292cb591782e3d3cc41145b9158a426032` 与 request `9FE68E5BEB945B969A2D4CDAA1D20B2D2838A4208DB8773EF7344918B0383658` 已由本地 X509 `builder-local-a` / `physical-host-a` 与 GitHub OIDC/Sigstore `github-hosted-windows`（cloud run `33090620311`）对 identity `6C9CF4699C217CC65083038D3AA69B0D6640C4E8DF5A50D367D0628E366D379D`、closure `1D0C3A1272CD084ECC9532B0565E017E07A233C1511B4372C091FF081701252F` 达成双 signer / 双 faultDomain 共识。39/39 final receipt SHA-256 为 `361CAAEDD6322796631112882DB069C5B1C2F6599AF20685F9A20BB719BD6677`；deployment commit `6902b2b6ed067c4882e9a67267d055ce0db90b34` 与 post-promotion audit run `33092179946` 均已推送/通过，审计明确输出 `state=promoted`、`deploymentChanged=true`。
无 candidate selector 的正式入口 run `2478a9f25873043318f2402f80105b52` 确认 `formal_runtime`、正式 Core DLL `D793647E666423EB73FE78F8E272CDF9A2E5792B9D694259639A6B35DD1624D0`、精确 identity/closure、同一 lifecycle 的两次 verified status、fresh handoff/reveal、可信 shutdown receipt、Guardian/Flash code 0、专用存档哈希不变且未触发强制清理；报告 SHA-256 为 `0F3349124141B5570B9FD51061AD736A71999CF1824DBF76B6AEBF50AFE41BF9`。前两次运行时 Default input desktop 持续 `GetForegroundWindow()==0`，按 30 秒门返回 `trusted_runner_credential_timeout`，均保留且不计成功；第三次只在 Default input desktop 上确认 `GetForegroundWindow()!=0` 后复用同一 runner/harness 配置。正式 identity/lifecycle 窄纵切达到 `standard_entry_verified`，但 `businessJourneyExecuted=false`，没有重跑八槽、切换、旧档迁移或重启读回；功能状态仍准确写作 `HUMAN_ACCEPTANCE_PASSED / promoted`，不称业务 `standard_entry_verified`。

**更早正式列车（历史）**：source commit `f01f4b121a4ceebd7dae051f14bb511c5ae3f1cb`（tag `runtime-build-v2/20260730-workbench-no-as2-fallback-v1`、request `3BEBE136773D2C09022F01E5B3C176A788FE3D84E453F6500C6C560F03184C7B`）曾完成双故障域 promotion 与 Equipment Tuning 窄纵切 `standard_entry_verified`；其精确证据继续保留在 [no-AS2-fallback runtime 发布记录](../docs/evidence/workbench-no-as2-fallback-runtime-release-2026-07-30.md)，但不再代表当前正式 runtime。PlayerInfo F2/r2 自身仍是历史 non-deployment train；B0 仍为 `b0_accepted`、oracle 仍为 `oracle_frozen_for_b0`。

**面板回包/最小构建门历史 release（2026-08-15）**：source `704d836f42b70f788db8b5b2151c8ab3dcf77792` / tree `c4581f1ed445840ce6d648a842c65b113509c20c` 已由 tag `runtime-build-v2/20260815-panel-wire-minimal-gate-v1`、request `CC8C3E614F3B38CA75F2868BE6DDE6A49891EFA8E9EED7E8B23E291DBBA62306`、本地 X509 `builder-local-a` / `physical-host-a` 与 GitHub OIDC/Sigstore `github-hosted-windows`（cloud run `31886952236`）完成双 signer / 双 faultDomain、production policy、strict v2 verifier 与原子 promotion/rollback；正式 identity 为 `BB77F46E18C253AD66AF9DA6E89E9E254D7798FC7FAFEC2D520A8E7D3D72595E`，closure 为 `25DD44F37E3936D11D5A281200F72FE68A1833A288B678A0520F64A4CBC49660`，deployment commit 为 `019cf8d0d253adc23578f8d2ad0042067866dec2`，post-promotion audit run `31888427406` 已通过。通用 promotion 不再读取 Audio H2 或 emergency bypass；Audio H2 保持专项 `pending`。本轮跳过重复的 promotion `-VerifyOnly` 预演，正式根入口 `--verify-only` 为 `exit 0`；业务专项正式旅程未执行，因此只称 `PROMOTED`。

**Agent Runtime F7 C1 历史冻结（2026-07-31）**：最终 C1 source commit `dd84230a1d262c6478591cae2d11051b7a8aa7b1` 只冻结源码；一期 ADR 文件名保留首次冻结日 `2026-07-30`，避免 canonical 路径与链接漂移。其 documentation-only D1 只引用父 C1。exact C1 tree 已通过 production policy **26/26**，达到 `candidate_built / NOT_DEPLOYED`（identity `F67F1054E7DD19600138C3196D0798CFA487701CB7143C4DDFD2DC426D26E372` / closure `3C2CA3E6E935BF23A061228ED3D9BDA3823E81186057E8C86118FAD5C7CEBF0D`）；当时严格入口在无前台会话按固定凭据门失败关闭，未达到 `candidate_executed`、`e2e_verified` 或 `promoted`。这是保留的历史负向证据，不再代表 F8 current 能力边界。

**Agent Runtime F8 historical release（2026-07-31）**：implementation source `53caabc90941826ddacf626f536b0f473adbf049` / tree `5ac63ec05fbbc9b89aa14f7f0b5ab25698f9742d` 的 exact isolated candidate 先以纯 Agent Runtime MCP 达到 `e2e_verified / NOT_DEPLOYED`。随后 release source `6f3d50a52413c747b05b74be88d6ee46650f4597` / tree `253e57f6d20a90fef6addfa744d0487d88f00dfb` 由 immutable tag `runtime-build-v2/20260731-agent-runtime-wings-f8-v1`、request `A9B33601805709DBB5EAE6DAF312C2B7B0B502096FDD3BDCEA9CBE26D8B1299C`、本地 X509 与 GitHub OIDC/Sigstore 双故障域共识完成 v2 promotion；正式 runtime 绑定 identity `0F4C92F237ABD7785C957F3CD135ABF2EFB1EB5D9AB5671B869F39D00970675C`、closure `54FBCCBA7C90ACF407B09E38FFB874C13DE3CDFB80CF62D0F8D4E239A42962F0`、Core EXE SHA-256 `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD` 与 Core DLL SHA-256 `0CEA0C64C037090ADAB4E9C38294075E58F1D298615DD447677D0D6725A9271E`。无 candidate id 的 `automation/start.ps1` 正式入口 pure-MCP run `20260731T040942Z` 达到窄范围 `standard_entry_verified`：覆盖单显示器 Launcher、NativeHud、授权 Help WebOverlay、Flash metadata-only fail-closed 与 trusted shutdown；没有使用 Codex Computer Use、browser/Chrome、privileged legacy HTTP 或任何 `input.*`，没有持久化像素或 PNG。该结论不外推为物理双屏、Flash pixels/native input、“13/13”、Hair/Wings 完整产品、业务写或维护者人工目视签收。

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
# 长路径隔离 Worktree 的受控 BuildOnly 叶节点（只能与上述两个开关同时使用）
.\automation\dev.ps1 -ForceBuild -BuildOnly -CandidateLeaf a5
```

`-Status` 只读报告当前身份、精确匹配和同身份闭包分叉；`-ReuseOnly` 禁止缓存未命中时构建；`-ForceBuild` 强制新建 candidate，但新旧同身份闭包不一致仍 fail-closed；`-BuildOnly` 只选择/构建并验证 candidate，不启动进程。`-CandidateLeaf` 只允许与 exact `-ForceBuild -BuildOnly` 组合使用，值必须是 1–32 个小写 ASCII 字母、数字或连字符组成的单一路径段；入口在 `tmp/runtime-candidates/v2` 下构造 direct child、复用既有 canonical/reparse 护栏并预检 bootstrap `<260` 路径预算，再把绝对 `CandidateRoot` 交给 producer。已存在的叶节点一律按 immutable candidate 拒绝，绝不启用 `ForceReplace`。该参数用于长路径隔离 Worktree，不改变 build identity、payload closure 或正式发布协议。忽略路径 `tmp/runtime-dev/active.v1.json` 只是便于精确复用的索引，每次执行前都会重算 Worktree 身份并重验 candidate，不是信任或部署证据。

完整游戏 E2E 还受 Flash 既有资源定位约束：当前项目根的 canonical 路径必须保留 `...\resources` 这一层级语义。任意名的普通 Worktree 即使能生成并启动 candidate，也可能因 `PathManager` 无法建立资源基址而停在任务数据加载。需要隔离实机验证时，应把独立 Worktree 建成 `<隔离目录>\resources`，再从该根运行 `automation/dev.ps1`；不要为满足路径约束覆盖、复制或清理正在使用的 Steam `resources` 工作区。仅构建、静态门和 Host/Web 单测不需要这一完整游戏路径形态。

断网可以完成已有 candidate 的精确复用；若需重建，本机必须已安装并通过锁定的 .NET / MSVC / Windows SDK / Rust 工具链，且 NuGet / Cargo 依赖已在本地缓存。首次开发机供给仍可能需要联网，这与正式云端双生产者验证是两个独立问题。

正式已部署入口与低层诊断入口则明确区分：

```powershell
# 无 CandidateRoot：只启动项目根已 promotion 的正式 runtime
.\automation\start.ps1
# 低层诊断兼容入口：只接受已知的绝对 candidateRoot
.\automation\start.ps1 -CandidateRoot "<absolute candidateRoot>"

# Audio v2 A6 qualification-only：观察并经生产 AS2 链施加 strict stimulus
.\automation\start.ps1 -CandidateRoot "<absolute candidateRoot>" `
  -AudioV2QualificationRunId "<32-lowercase-hex>"

# trusted Core unattended：formal runtime
node tools/cf7-agent/unattended.js --adapter jsonl --slot cf7_agent_equipment_tuning

# trusted Core unattended：显式 candidate ID
node tools/cf7-agent/unattended.js --adapter mcp --slot cf7_agent_character_build --candidate-id "<candidateId>"

# A5 隔离候选专用：物化 resources 根 + 此 slot + 此短叶
node tools/cf7-agent/unattended.js --adapter mcp --slot cf7_agent_a5_material_shop_run --candidate-id a5

# 仅供尚未迁移的旧 HTTP runner；该进程不创建 Agent Runtime/Wings
.\automation\start.ps1 -EnableLegacyHttpAutomation
```

`automation/start.ps1` 无参数时不会扫描或猜选 `launcher/bin`、`tmp/runtime-candidates/` 中的开发输出。源码领先于正式二进制时，它仍运行上一次已 promotion 的身份。日常开发不再要求人工复制 candidateRoot；`start.ps1 -CandidateRoot` 仅保留给调试指定产物等低层场景。

`-AudioV2QualificationRunId` 是 A6 exact-candidate 的 qualification-only 开关，只接受 32 位 lowercase hex，并且必须同时显式提供 `-CandidateRoot`。它不能与 formal runtime、`-UnattendedAdapter/-UnattendedSlot`、`-EnableLegacyHttpAutomation` 等入口混用；不传该参数时不创建 qualification surface。开启后 Core 分别创建只读 observer pipe 与 strict stimulus pipe：observer 只允许 `begin_case/end_case` marker、`snapshot/journal`，stimulus 只向 Flash 投递冻结命令；实际 BGM/SFX 仍必须经过生产 `AS2 → XMLSocket → AudioTask → AudioCoordinator/native`，pipe 返回 `sent=true` 仅证明 socket delivery。operator 只能自动跑前 10 case，后 4 个默认设备/物理路由/睡眠恢复/stale-SFX case 及 10 项听感必须由人类完成；此入口永远不授权 promotion。

Audio Platform v2 R4 不改变 start/operator 命令面。`sleep_resume` 收尾需在末 closing `Ready` 后取得两份显式 snapshot，由 observer 在同一 final generation/physical tuple 的同一路 bus 上证明 frame 前进与非静音。E2/H2 与 evidence-only E3 `h2-request-link.json` 只用于 Audio 专项验收及其 `e2e_verified` / `standard_entry_verified` 声明；通用 source tag/request、正式 builders 与 promotion 不消费这些产品体验证据，也不再需要 owner-emergency 参数。部署仍完整保留 immutable request、双 signer / 双 faultDomain、production policy、strict verifier、原子替换与 rollback；H2 未完成时诚实标记 Audio 验收 `pending`，不得由部署事实反向补签。

`-UnattendedSlot` 与 `-UnattendedAdapter jsonl|mcp` 选择 trusted Core runner；固定 allow-list 为 `cf7_agent_equipment_tuning`、`cf7_agent_arena_calibration`、`cf7_agent_character_build`、`cf7_agent_loot_target_full_v1`、`cf7_agent_a5_material_shop_run`，不能由 caller 提交 principal、capability、路径或 legacy flag。A5 专用槽只接受两种 exact runtime binding：物化 `resources` 根必须携 `--candidate-id a5` 并解析到 `resources/tmp/runtime-candidates/v2/a5`；canonical 根必须不携 `CandidateRoot` / candidate selector 并进入 `formal_runtime`。普通 `c-*`、其他短叶与 unqualified runtime 一律拒绝，旧槽仍只接受 formal 或原有 immutable `c-*` candidate。formal/candidate 均先校验完整 v2 manifest inventory、Core row/hash/size、build identity、payload closure 与无 reparse 的固定目录；随后执行所选 payload 自身的 `Core.exe --agent-unattended-runner`。这里的 formal 形状只是底层资格门；A5 仍没有可执行的 formal admission/runner，禁止绕过材料适用性、一次性授权与同旅程证据链直接调用它。

启动链负责：

- 启动 Guardian Launcher
- 走当前默认运行链路
- 使用内嵌总线与现有宿主架构
- `automation/start.ps1`、`scripts/gobang_trainer_cycle.ps1` 与 `tools/cfn-cli.sh` 的默认入口都绑定正式根部署；直启正式 Core 前调用根 bootstrap `--verify-only`，manifest 闭包不完整、含额外文件或二进制混搭时 fail-fast
- `dev.ps1` 把选中的精确 candidate 交给 `start.ps1 -CandidateRoot`；后者只接受本仓 v2 candidate 的绝对 canonical 路径，使用候选自身 bootstrap `--verify-runtime-only`，拒绝 reparse / metadata / manifest / Core 字节身份漂移
- 清理已失效的 `launcher_ports.json`，并等待新的端口文件写入后再返回；若 Core 进程提前退出或 30 秒内未写端口，脚本返回失败

普通 formal/candidate 启动模式会打印并硬核验 `runtimeMode`（`formal_runtime|isolated_candidate`）、`processPath`、`coreSha256`、`buildIdentity`、`payloadClosure`；详见 [`launcher/README.md`](../launcher/README.md#离线开发入口与身份绑定候选)。trusted unattended 模式的 stdout 必须保持 JSONL/MCP protocol-only，身份不靠 stdout 自报，而由启动前 verifier、Core 最早分支自校验与 Host 的 exact peer/nonce/build/closure 绑定共同证明。统一状态为 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`；只有 promotion 后再由无参数标准入口验证同一身份，才可称“已部署 / 正式验收”。

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

### Trusted Core Agent 无人值守平面

该平面的安全身份是选定 runtime payload 内的 C# Core，不是 `tools/cf7-agent/unattended.js`、`automation/start.ps1`、父进程命令行或可修改的 Node/PowerShell 依赖。标准 `start.ps1` 在首次执行所选 Core 前先以仓库 verifier + 所选 native bootstrap 校验完整 inventory/native payload；Core 启动后的最早 `Main` 分支再对 selected on-disk process path/hash/size 与 manifest/payload closure 做纵深复验，它不是“二进制执行前自证”。随后 Core 生成 runner nonce/challenge、固定 client identity 和受限 bootstrap evidence；Host 只接受同一已验证 runner PID/start/path、nonce、slot、build identity 与 closure。JSONL/MCP 仅转换 stdio，不扩 capability。

runner 创建并拥有一个新的 standard-normal Guardian，会话不与现有 Launcher 复用；五个固定专用槽以外全部拒绝，legacy HTTP 与 trusted Agent unattended 不能同时启用。正常 stdin 结束后 runner 必须请求 `allowValidatedFlashKeyframeFallback=false`、exact scope 中恰含当前一个 `RuntimeOwned` Launcher target 的 observation；该 cardinality 只约束本次 scope，不表示整个 session 全局只有一个 Launcher surface。只接受 exact target 的 `SourceLayer.Launcher` frame；Flash source 或 fallback frame 都不是退出 authority。shutdown lease 必须逐字段严格匹配 active `UnattendedTest`、purpose `Shutdown`、省略 `renewAfter`、exact owner/principal/session/attempt/target、singleton capability/operation、one action 与 issuer receipt。runner 发送 supported `session.shutdown` 后，terminal receipt 必须绑定同 action/target/before observation，并精确为 `terminal=true`、`outcome=input_dispatched`、`evidenceKind=broker_dispatch`、`reasonCode=shutdown_requested`、`reconcileKind=none`、`retryable=false`、`focusVerified=false`、`leaseState=consumed`；完整严格 receipt 后还必须观察同一 exact owned child 以 exit code 0 正常退出。

Host 侧 `LeaseDescriptor.purpose` 必填、`renewAfter` 可选，shutdown descriptor 必须省略 `renewAfter`；shutdown 只允许 `DeveloperInteractive` / `UnattendedTest`，且请求的 exact scope 恰含当前一个 `RuntimeOwned` Launcher target，唯一 operation 为 `session.shutdown`、TTL≤30 秒、one action、no renew。只有语法有效、已认证、完全授权且到达 issuance policy 的 PlayerAssist acquire 返回 `consent_required`；畸形、越权或直接 action 可更早失败。lease live table 只保留 active 或仍在执行/交付的记录；terminal tombstone 是 FIFO 256，committed-shutdown session latch 是 64，后者溢出即全局 fail-closed，eviction 永不重新开放写入。renew/release 失败后的 cleanup 只属于 exact active owner，attacker、consumed 或 pending lease 不能借此释放资源。

F8 production surface contract 将嵌入式 Flash 固定为 metadata-only：descriptor 的 `observationModes=[]`、`inputModes=[]` 必须同时为空，对它申请 pixel capture 精确返回 `unsupported_for_surface`。production session 不发布 `window.activate`，activator map 为空；WGC 只适用于 Launcher、WebOverlay、NativeHud 三类 surface。类型级 capability 不能替代实际授权，调用还必须同时满足 session grant 与 surface mode。`panel.open` 只面向 production allow-list `help|map|tasks|team|jukebox|materials`，其 scope 精确包含当前一个 `RuntimeOwned` Launcher target，并使用 one-shot lease；`materials` 复用 `nativehud_materials` 的 Host→AS2 `openMaterialUI` exact nonce/tuple 路由，不直开 Web panel。成功 receipt 只证明命令交付或同步 exact admission，可见性仍必须 fresh WebOverlay WGC 独立验证。所有 production panel producer 的 instance ID 均来自至少 144-bit CSPRNG，prefix 只作诊断、没有安全语义。

每个 action 的唯一绝对 deadline 从完整 request frame 收到时开始，覆盖 parse、admission、scheduler、performer、response writer lock 与全部 frame `WriteAsync`，不得分阶段重置。成功 consume 的 owner 独占 session execution reservation 到全部 response frames 完成或显式 abort；失败 consume 从未拥有 reservation。abort callback 返回 false 或抛异常时 reservation 保持并标记 continuity lost；完整 frames 已写出后 commit callback 返回 false 或抛异常时字节不可回滚，只能标记 continuity lost，且 SafeExit continue 不再有保证。

SafeExit 只先 arm；首个成功字节前先 claim audit response identity，再 claim shutdown lease write ownership 与 human-input sequence fence。在写所有权建立前，external input 会撤销全部 active / execution-pending / delivery-pending / queued 且尚未 delivery-write-owned 的工作；第二道 claim 失败保持零成功字节并同步 abort。一旦写所有权成功 claim，随后 human override 不得回滚，terminal 收束只归 response-completion state machine。全部 required frames 的 `WriteAsync` 完成只表示 server-side delivery disposition，不是 peer acknowledgement；后置 Flush、post-write audit append 或 commit callback 失败均不回滚已写字节。

`action_response_written` 与 `action_response_unknown` 是 reserved audit facts，generic append 必须拒绝，只有 exact pending terminal identity 的专用 claim/complete 路径可追加。DeliveryUnknown 一律使用 `EvidenceKind.ReconciliationRequired`。Action ledger replay 必须原样返回 retained `ContractReceipt`（包括 Unknown），不得再次 dispatch 或二次合成。post-write audit append 失败只标记 continuity lost、移除 pending 并以 `truncated` segment 收束，后续 dispose 不得再合成 Unknown。

Host 在每次完整 surface refresh（含周期 refresh）重试 unattended credential publication；publication 以 single-flight 锁串行，teardown 先停止 admission/周期 refresh，再越过 in-flight publication barrier 后才 dispose bootstrap/authenticator。credential acquisition 使用受信 Core 内部固定的单调 30 秒上限，caller 没有覆盖参数；它独立于最长 10 分钟的 bootstrap request/session lifetime。

F8 trusted shutdown 只对两种结构化、可证明无副作用的 canonical transient 做有限重试：shutdown 前观察仅在 `capture_unavailable`、`retryable=true`、`reconcileKind=none` 时重试；shutdown lease acquire 仅在 `input_not_quiescent`、`retryable=true`、`reconcileKind=none` 时重试。两者都最多四次、复用原 grant/session/target/scope 参数且不 regrant，只更换 RPC request ID；任何字段不匹配立即失败。`session.shutdown` action 保持 zero-retry，绝不因 receipt 丢失或超时二次 dispatch。

每个已转发的 JSONL call 都有 30 秒 wall-clock 硬截止；每个 MCP `tools/call` 使用从 handler 启动贯穿 buffered response copy/flush 的同一绝对 30 秒预算，active-loop 的并发错误/控制输出复用剩余预算，initialize/tools-list/protocol-error 等 idle 输出则各有独立 30 秒 output budget。完整 shutdown transcript 另有 30 秒截止；截止时取消调用、异步关闭认证 pipe 且不伪造成功/错误 response，再进入 bounded exact-owned-child recovery，Kill 后 5 秒仍无法观察 exact child 退出必须显式失败。Node wrapper 仅把 `adapter/slot/candidateId` 映射到固定系统 PowerShell 与 `start.ps1` 参数数组，不能成为 provenance 或授权证据。

trusted runner 的 stdout 始终只承载 JSONL/MCP protocol，不输出 credential、secret 或完成证据。只有 adapter exit code 0、strict shutdown receipt、同一 exact owned child exit code 0 且没有 forced recovery 时，才在 stderr 输出单行、不超过 16 KiB 的非秘密 completion evidence；字段限于 schema、runtime mode、process path、Core SHA-256、build identity、payload closure、guardian PID 与 terminal receipt。credential timeout、任一非零退出、receipt 不匹配或 forced recovery 都失败，不得记作 E2E 成功。

source-level 测试必须覆盖 formal/candidate 固定路径、完整 manifest inventory、Core identity、nonce replay/tamper、slot allow-list、JSONL/MCP lifecycle/framing、正常 protocol shutdown、同步返回 Task 前阻塞、active response/concurrent error/idle lifecycle stdout 背压、无响应 JSONL call、无响应 MCP call/EOF、无响应 shutdown transcript、认证 pipe 的 bounded abort 和异常 exact-child cleanup。F7 C1 历史证据为 Launcher 全树 **2678 passed + 3 explicit opt-in skipped / 2681 total，0 fail**、仓库 SDK resolver **7/7** 并精确解析 `.NET SDK 10.0.300`、Node client **37/37**、TrustedRunner 过滤 **48/48**。exact C1 candidate 的 production policy receipt 为 **26/26**（receipt SHA-256 `CC7ED850D18D2C72947DA69E74C28E529A6DC988CA37AAE4D486C43954FAB79B`），Core EXE SHA-256 为 `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD`，因此只达到 `candidate_built / NOT_DEPLOYED`。当时执行会话 `GetForegroundWindow()==0`；用该 exact candidate 走 `start.ps1 -CandidateRoot ... -UnattendedAdapter jsonl` 得到 `trusted_runner_credential_timeout`，未生成 completion evidence，post-check 无候选/Flash/热键进程、`launcher_ports.json`、live bootstrap request、credential 或 rendezvous 残留。这是保留的 fail-closed 负向证据，不是 current F8 结论。

F8 evidence 分为两个不可混写的阶段。implementation source `53caabc90941826ddacf626f536b0f473adbf049` 的 isolated candidate `c-0f4c92f237ab-98ebd18146-20260731t022411220z-20da007a` 先以同一 identity / closure 达到 `e2e_verified / NOT_DEPLOYED`；其 report、transcript 与 residue comparison 继续作为候选历史证据。release source `6f3d50a52413c747b05b74be88d6ee46650f4597` 随后取得 request `A9B33601805709DBB5EAE6DAF312C2B7B0B502096FDD3BDCEA9CBE26D8B1299C` 的双故障域共识并 promotion；无 candidate id 的正式入口 pure-MCP report `tmp/manual-agent-acceptance/formal-f8/agent-runtime-help-20260731T040942Z.json`、同目录 transcript/completion 与 `formal-residue-comparison.json` 证明 `runtimeMode=formal_runtime`、57 次 MCP call、Help panel 结构化 dispatch、可信退出、存档不变以及无新增残留差量。两阶段都未使用 Computer Use、browser/Chrome、privileged legacy HTTP；没有调用 `input.*`，Flash 双空 mode 与 pixel `unsupported_for_surface` 被实测，WGC 帧只在内存中散列后清零。正式阶段只把该单屏纵切推进为 `standard_entry_verified`，不等于 Flash 像素/原生输入、物理双屏、完整 Hair/Wings 产品或维护者人工目视签收。

### Legacy HTTP 无人值守运行态控制面

`agent_control` 是显式 `-EnableLegacyHttpAutomation` 进程中的 localhost HTTP `/task` 窄化兼容面，不是 Agent Runtime，也不是任意 GUI/DOM 遥控器。该模式签发进程生命周期 credential，并且不创建 Agent Runtime/rendezvous/Wings；Node/PowerShell runner 名称、slot 文本或 parent command line 都不能把它升级成 unattended principal。通用 `readyForRuntimeAutomation` 只在 Launcher Ready、socket、安全 snapshot 决议、AS2 对同一 `attemptId/savePath` 的 `SaveManager.loadAll()` ack，以及 Host 从**非 legacy 的同一个 UiData 包**实收 `s:1|ga:<当前 save attemptId>` 后成立；`status.gameEnteredObserved/gameEnteredAttemptId` 显式暴露最后一项，裸 `s:1`、缺 `ga`、stale `ga` 或 legacy 包均不能解锁，缺失时 blocker 为 `game_enter_not_observed`。每次 `start` 都无条件清除旧 `gameEnteredObserved/gameEnteredAttemptId` 并重新上锁；实收 `s:0` 只作防御性清锁，目前没有现役正常退出调用它的证据。arena 在此基础上另加 arena status，继续使用 `readyForArenaCalibration`。

面板迁移可增加领域专用动作，例如装备调制的 `openEquipmentTuning`。该动作只接受与当前状态一致的 `expectedSlot/expectedAttemptId`，slot 必须为 `cf7_agent_*`，并固定发送正式 AS2 opener；客户端不能传任意 panel/initData。返回 `panel_open_requested` 只表示命令已发送，runner 还要等待 Host active panel instance 和该实例首个领域 snapshot。禁止直接调用 `PanelHost.OpenPanel`、Web `Panels.open`，也禁止通过 `/console` 调业务 preview/commit。

所有专用 runner 的因果顺序固定为：在调用 `agent_control start` **之前**记录 `/logs` 水位 → 调用 `start` 并取得 expected slot / `attemptId` → 只接受该水位之后本轮新鲜 `[BootstrapAS] event=handoff` 与真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared` → 确认 watchdog 未触发后只调用一次 `_root.agentEnterResolvedSave()` → helper 先执行 `_root.notifyGameEntered()`，使同一 UiData 包携带 `s:1|ga:<_bootstrapAttemptId>`，再按 `SaveManager.loaded` 决定直接返回或 `gotoAndStop("读盘")` → Host 必须观察到 `gameEnteredAttemptId==expectedAttemptId`，并在同 attempt runtime ack 等其余门满足后才允许 runtime ready。reveal watchdog 不算标题帧回执，缺失统一失败为 `title_frame_not_observed`；notifier 尚未注入时必须 fail-closed。专用克隆槽负责隔离写入；真实 `crazyflasher7_saves*` 槽默认永不用于无人值守写测试。

Launcher 的 Flash reveal watchdog 生产默认 deadline 现为从 Ready 起算的有界 **45,000ms**。原 20,000ms 已覆盖此前约 15.68s 的样本，但 A1 冷启动实测在同一精确候选上直到约 30.85s 才收到真实 title receipt，并被 20s watchdog 正确拒绝；45s 为该实测保留有界余量。测试可以在 `GameLaunchFlow` internal 构造注入更短值。这个调整只减少 deadline 竞争，不改变上述证据合同：watchdog 日志永不计为成功，watchdog 先到的 attempt 立即丢弃，迟到 title 不得解锁 `agentEnterResolvedSave()`，runner 也不得靠延长自身 ready timeout 续用旧 attempt。

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

斗兽标定工具有独立、锁版本的 Node 依赖；首次使用或 `package-lock.json` 变化后先在仓库根目录运行：

```powershell
chcp.com 65001 | Out-Null
npm --prefix tools/arena-calibration ci --ignore-scripts --no-audit --no-fund
```

测试群工作簿直接由 intake adapter 摄取，不要求人工改填内部 `caseId`、hash、repeat、timeout、阵型或 side-swap 字段。摄取来源固定绑定 `workbookSha256 + sheetName + cell + cellValueHash`；修正/隔离规则还必须同时匹配 `tools/arena-calibration/workbook-overrides.json` 中冻结的工作簿 hash 和 sheet，且只改派生 artifact，不写回原 `.xlsx`：

```powershell
node tools/arena-calibration/intake-workbook.js `
  --workbook "<测试群工作簿.xlsx>" `
  --sheet "斗兽标定组合" `
  --overrides tools/arena-calibration/workbook-overrides.json `
  --output-dir tmp/arena-calibration/batches/<batchId> `
  --phase exploration `
  --directions "B2:both,G2:both,F5:both,C7:both,C12:both" `
  --repeat 3 `
  --batch-id <batchId> `
  --build-commit <commit>
```

`--phase` 的系统默认分别为 smoke `3600`、exploration `1800`、confirmatory `1800` frames；单元格已有显式 timeout 时原值优先并进入来源/风险记录。`timeoutFrames` 只定义 Flash 战斗的逻辑帧预算；Host 传输安全截止独立使用“按 30 FPS 折算的语义预算 ×2 + 30 秒”，并封顶 10 分钟，以覆盖舞台切换、低帧率、清理与 socket 回包，不得把 Host 合成 timeout 混作战斗 timeout。timeout 仍是战斗语义和稳定性信号，批后不得自动延长并把原 timeout 覆盖成完成样本。生成 manifest 前会对 raw submission、normalized candidate、exception、intake receipt 和 manifest 做真实 JSON Schema 实例校验。

斗兽标定的无人值守外层入口在仓库根目录运行：

```powershell
chcp.com 65001 | Out-Null
node tools/arena-calibration/run-unattended.js `
  --slot cf7_agent_arena_calibration `
  --seed-slot crazyflasher7_saves2 `
  --manifest tmp/arena-calibration/batches/<batchId>/case_manifest.json
```

`--slot` 缺省为 `cf7_agent_arena_calibration`，也可以显式传入；runner 会在启动前把该专用槽位从 `--seed-slot` 或最新有效 shadow 存档播种，并备份/移除目标槽位残留 SOL，避免复用运行中的旧 SOL。默认拒绝 `crazyflasher7_saves*` 正式槽位与 `--fresh`，除非显式传 `--allow-live-slot` / `--allow-fresh`，这两个开关只用于人工取证，不用于无人值守批跑。

该脚本会在需要时显式调用 `automation/start.ps1 -EnableLegacyHttpAutomation` 启动 Launcher，通过 HTTP `/task` 的 `agent_control` 选择专用存档；它必须在调用 `agent_control start` 前记录 `/logs` 水位，再观察到 start 后本轮新鲜 handoff 与水位后的真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`，watchdog 不计入，缺失时报 `title_frame_not_observed`。随后才校验 exact slot / attempt 并只调用一次 agent enter。helper 先发正常入口同款 `notifyGameEntered()`，让同一 UiData 包携带 `s:1|ga:<attemptId>`，再 `gotoAndStop("读盘")`（已 loaded 时直接返回）。`readyForArenaCalibration` 必须同时满足安全 snapshot、同 attempt 的 `agent_runtime_status`、Host 的 `gameEnteredObserved=true` 且 `gameEnteredAttemptId` 精确匹配、socket 与 arena status，再调用 `arena_calibration startBatch/status` 跑批次并生成 summary / run-report。遇到游戏崩溃、socket/HTTP 断开、batch timeout、缺行或异常行时，会生成 rerun manifest，并按 `--max-recovery-attempts`（默认 1）自动关闭 Launcher、重启进档、补跑剩余 case；每轮 attempt、最终失败清单和建议都会写入 `run-report.*`。rerun 必须原样保留 roster `parameters/sourceId/hpPermille`、阵型、间距和 timeout，避免重跑改变 `caseHash` 或战斗语义。它不会自动修改战斗代码；如要生成最小 pilot，可显式加 `--generate-pilot --batch-id <id>`。

runner 在启动前和全部收尾后都会对专用目标槽以外的 `crazyflasher7_saves*.json` 与对应 Flash SOL 做受保护指纹快照；任一文件新增、删除或字节 hash 改变都会让报告失败。`--shutdown` 绑定本轮 expected PID；收到成功 shutdown 后该进程已经消失属于正常终态，不能再用已过期 credential 轮询并制造 teardown 假失败。JSONL **原始行**（不是先经 normalization 丢字段后的投影）须通过 `result.schema.json` 实例校验并精确匹配 manifest/case hash；生产字段 `authorityContext`、`blueUnitResults/redUnitResults`、阶段派生单位 `from/name/auxiliary` 均在闭合 schema 内。

Gate B 之后用 `campaignctl.js` 管理跨进程状态。先由外部只读观测器生成 producer observations，再签发短期 grant；工具不会自行关闭或接管一个 active/unknown producer。每次 `init/schedule/import` 都必须提供仍有效、与 registry hash 绑定且覆盖 `launcher/flash/arena_runner` 的 idle grant；`pause` 会 durable 记录、关闭 segment 并释放 writer，`status` 只从 journal 重放，不信任 `checkpoint.json`：

```powershell
node tools/arena-calibration/campaignctl.js issue-grant `
  --observations tmp/arena-calibration/campaigns/<campaignId>/producer-observations.json `
  --output-dir tmp/arena-calibration/campaigns/<campaignId>/grant

node tools/arena-calibration/campaignctl.js init `
  --campaign-id <campaignId> --config <campaign-config.json> `
  --registry <producer-registry.json> --grant <idle-grant.json>

node tools/arena-calibration/campaignctl.js schedule `
  --campaign-id <campaignId> --registry <producer-registry.json> --grant <idle-grant.json> `
  --shard-id <shardId> --manifest <case_manifest.json>

node tools/arena-calibration/campaignctl.js import `
  --campaign-id <campaignId> --registry <producer-registry.json> --grant <idle-grant.json> `
  --shard-id <shardId> --manifest <case_manifest.json> --result <results.jsonl> `
  --run-report <run-report.json> --attention <attention-measurement.json> `
  --battle-semantics-cohort <cohortId> [--allow-partial] [--complete]

node tools/arena-calibration/campaignctl.js pause --campaign-id <campaignId> --reason <reason>
node tools/arena-calibration/campaignctl.js status --campaign-id <campaignId>
```

星期级全量标定由 `build-gate-f-week-plan.js` 与 `gate-fctl.js` 接管。前者只消费已绑定工作簿 hash/单元格的 normalized intake、exception、显式 timeout 证据与必需的 `arena-calibration.soak-admission.v1`，不重新读取或改写 `.xlsx`；当前冻结前草案位于 `tools/arena-calibration/plans/gate-f-week-full-v2/`，执行 campaign 为 `gate-f-week-full-v5`，包含 58 个待跑候选、1 个隔离 scope、198 个 10–25 run 短 shard 和 3255 个计划 run。部署列车改变了 Arena stage admission，旧 runtime 上已完成 PVE 的 G2 只保留 `1 × Lv10` 外部标签，不跨 cohort 代签新机器样本。B9 的原始工作簿/normalized timeout 仍为 1800 帧；`gate-f-week-full-v2-empirical-timeout-overrides.json` 以 workbook hash + sheet/cell/cell-value hash、candidate hash、原/换边 1800 帧 timeout、原/换边 5400 帧 finished、candidate runtime identity/closure 与不变存档快照为闭包，只在计划层把 B9 转入 `6 × 10` 长 timeout 分层，且明确要求 formal runtime 复跑。每个 shard 都有独立、hash-bound 的 `schedule_shard/auto_execute` 决策证据并同时计划 original/side-swap。

`--soak-admission tools/arena-calibration/evidence/gate-f-week-full-v2-soak-admission.json` 是生成星期计划的硬参数。生成器会逐文件复验其中的 manifest/result/report SHA-256、真实 JSON Schema 实例、exact candidate timeout、original/side-swap 自然结束、formal runtime identity、零 error/timeout/recovery、正常关闭与受保护存档不变；freeze 再把 admission path/hash 与当时 formal runtime 一起写入 plan。`resultPath` 继续逐字绑定原报告声明，`resultSnapshotPath` 则指向当次唯一 run 目录中的同字节不可变 JSONL，避免后续同 batchId 重跑覆盖准入证据；manifest 同样引用当次运行冻结的唯一 snapshot，不得循环引用会被 admission hash 重算的当前计划 manifest。首轮正式 campaign 的前两份 soak 为 20/20 finished，第三份因 B11/C12 原向真实 timeout 形成 8 finished + 2 timeout 而暂停；旧 30 行继续作为不可改写事实。修正后的三份 10-run soak 均使用 `B2/C7/G2/F3/E10`，每份都覆盖普通参数、单位 payload、阵型、长 timeout、高等级与 side-swap；v3 已取得 30/30 clean receipt。B11/C12、C9 和 B9 的既有 timeout 事实及全量普通/长 timeout 分片全部保留，退出基础设施 soak 不代表删候选或认定平衡。

```powershell
node tools/arena-calibration/build-gate-f-week-plan.js `
  --candidates tmp/arena-calibration/intake/gate-a-workbook-audit/normalized-candidates.json `
  --exceptions tmp/arena-calibration/intake/gate-a-workbook-audit/exceptions.json `
  --empirical-timeout-overrides tools/arena-calibration/evidence/gate-f-week-full-v2-empirical-timeout-overrides.json `
  --soak-admission tools/arena-calibration/evidence/gate-f-week-full-v2-summon-lineage-v3-soak-admission.json `
  --output-dir tools/arena-calibration/plans/gate-f-week-full-v2 `
  --plan-id gate-f-week-full-v2 --campaign-id gate-f-week-full-v6 `
  --battle-semantics-cohort arena-cohort-20260830-summon-lineage-v3 `
  --battle-build-commit bcfa01935d2f91a29a8a537c328c9190827c4be3
```

部署稳定并取得最终提交后，必须在 clean Git worktree 上重新绑定 exact source commit/tree/worktree hash 与当时 formal runtime；不得把冻结前草案中的任何旧 runtime 值当成正式身份：

```powershell
node tools/arena-calibration/gate-fctl.js freeze `
  --draft tools/arena-calibration/plans/gate-f-week-full-v2/plan-draft.json `
  --output-dir tmp/arena-calibration/gate-f/gate-f-week-full-v6/frozen

node tools/arena-calibration/gate-fctl.js arm `
  --plan tmp/arena-calibration/gate-f/gate-f-week-full-v6/frozen/gate-f-plan.json `
  --output-dir tmp/arena-calibration/gate-f/gate-f-week-full-v6/window-<timestamp> `
  --hours 8

node tools/arena-calibration/gate-fctl.js run `
  --plan tmp/arena-calibration/gate-f/gate-f-week-full-v6/frozen/gate-f-plan.json `
  --window tmp/arena-calibration/gate-f/gate-f-week-full-v6/window-<timestamp>/idle-window.json `
  --max-shards 3 `
  --codex-exe <可选；未给出时自动发现 Codex CLI> `
  --maximum-exception-reviews 1

node tools/arena-calibration/gate-fctl.js status `
  --plan tmp/arena-calibration/gate-f/gate-f-week-full-v6/frozen/gate-f-plan.json `
  --output tmp/arena-calibration/gate-f/gate-f-week-full-v6/status.json
```

当前 `gate-f-week-full-v6` 切换到 `arena-cohort-20260830-summon-lineage-v3`，战斗语义提交为 `bcfa01935d2f91a29a8a537c328c9190827c4be3`。D10 新鲜诊断为 10/10 完整、0 contamination/error、3 个真实 1800 帧 timeout，正式 runtime 与受保护存档均闭合；随后 `B2/C7/G2/F3/E10` 新 cohort admission probe 为 10/10 finished、0 timeout/error/recovery、正常 shutdown 与存档不变，raw admission hash 为 `sha256:a1b445c93b432e719f09472a1e2cea8633c29ddb607e6301207216b3936b37eb`。tracked v2 计划仍是 58 个 scheduled candidate + `B12` quarantine、198 shard / 3,255 run；尚未 freeze/arm，三份正式 fresh soak 尚未执行，旧 v5 的 159 completed shard/2,810 行只保留为历史，不跨 cohort 混计。

只有三份 fresh soak receipt 都为 `completed`，且 exact runtime、原始 JSONL Schema/manifest 绑定、受保护存档集合、磁盘、timeout/error、时长漂移和 0 人工动作测量全部通过，才可在新的有界 window 中去掉 `--max-shards 3` 继续剩余短 shard。`arm` 会拒绝活跃 Launcher/Flash/arena runner、低磁盘和 source/runtime 漂移；显式星期级授权 window 最长 168 小时且可随时用 `gate-fctl.js revoke` 撤销，过期后只允许提交已经产生的 durable facts，不再领取新 shard。全量阶段的纯 `timeout_rate` 超阈值属于候选质量 anomaly：原始行照常 durable 提交，写 `candidate_timeout_anomaly / keep_provisional` deferred item并继续；timeout 仍从强度拟合排除并参与最终候选低-timeout 门。标准/长分片在 exact runtime、存档、磁盘、墙钟和完整 cardinality 全部闭合后，若恢复耗尽且失败行只属于 `contamination/error/invalid_case/spawn_failed`，则 receipt 为 `quarantined`：只隔离由 `caseId` 确定的候选、跳过该候选后续 shard，其他候选继续；这些原始行绝不进入强度拟合。基础设施 soak、`stage_failed/bridge_lost`、duration drift、runtime/save/disk、runner/report/cardinality 异常仍失败。每个控制器最多异步启动一个 `run-exception-review.js`，模型只能在 hash-bound packet 上返回 `confirm_quarantine/likely_legitimate_spawn/request_method_change/abstain` 建议，不能接受样本、恢复候选或阻塞主批；CLI 缺失、超时、失败或非法输出都保持确定性 quarantine。运行监控把 controller、runner、它们的祖先和全部后代视为同一受控进程树；因此内部 `run-checks.js` 启动的 `gate-fctl.js --check` 不构成竞争者，而树外的真实第二 runner 或独立 `Flash.exe` 仍会触发让位。运行中如内容开发启动 Flash、出现 revoke/身份/磁盘异常，driver 会通过本轮 owned `.signal` 请求 abort，并在 300 秒硬上限内让位。已产生的 partial JSONL 逐行以 `manifestHash + runId` durable 提交，重复 attempt 只计一次；失败或恢复耗尽写去重 exception inbox，不要求测试群现场整理或逐批确认。Gate F low-touch 只有在真实最近 20 个 eligible epoch 与全 campaign 两个窗口都满足 attention 门后才成立，fixture 的 20 个 epoch 不能代替实跑。

Gate C–E 的机器侧入口是 `evaluationctl.js freeze-shadow|score-shadow|paired-strength|prepare-pve|validate-pve`。`freeze-shadow` 只生成三 profile 的同源请求；`score-shadow` 要求三份真实 proposal/receipt 全部过硬门，才会输出盲化 packet；`prepare-pve` 要求 exact build profile、2–4 encounter 和 holdout。PVE 的标定目标固定为“怪物组合等效于多少名、多少级人形佣兵”，玩家 build 只是冻结的测量载体。工具永远不生成模型返回、盲评或真人标签；timeout/error 只进 anomaly，不得被强度模型或无证据的 blanket timeout 延长掩盖。计划层 timeout 提升必须保留原 timeout 事实，以两侧长窗自然结束、exact runtime 和存档不变证据显式绑定，并在 formal runtime 重跑。

真人 PVE 用 `run-human-pve-session.js` 绑定 packet、私密 runtime plan、exact formal/candidate runtime 和专用克隆槽；runner 只允许固定 UI 选择动作，绝不替人点击“开始挑战”。运行中的 `next/finish/abort` 必须通过本轮 run-dir 内 owned-file signal 发送，不能依赖 PTY stdin/EOF。战斗后用 `finalize-human-pve.js` 摄取两份原始 report、截图、维护者原话与等效数量/等级，并复核源存档、非目标存档集合、active 专用槽、进程、锁、恢复记录和隔离克隆 hash；随后仍须用 `evaluationctl.js validate-pve` 对 exact packet 验证。未采集的胜负、残血、承伤、输出或异常只能标 `telemetryCompleteness=equivalence_only`，不得事后猜测。

地图箱既有冻结证据分为自动门、精确隔离 candidate E2E 与正式标准入口三层。`node tools/test-agent-entry-contract.js` 静态锁定 notifier guard、`s:1|ga:<attemptId>` 同包与 `gotoAndStop("读盘")` 顺序；装备与斗兽 runner 的 `--check` 覆盖 post-watermark 真实 title-frame marker、watchdog 拒绝、`title_frame_not_observed`、fresh handoff、exact slot/attempt、single enter 和 attempt-bound `gameEnteredObserved`。地图箱隔离 candidate 以 build identity `7C72B92B0C1CF57EB9BC0D3C1024D31657EE52E6B13D7BBF9FDB94FD5A6186DB`、payload closure `7E5EDCD4FEA80E1269C0B8BCC325D1FE0994EE8C7321F0F71CB9AF4B369C4A44`、Core SHA-256 `3EB1D3910B764F0B7F9ACA1FA989A4D8732F75479E64325223F270502256A5DF` 在 attempt `82b9e602526c4e93a02d26aac0a44f20` 完成真人领取、满背包/整理背包、部分领取、情报上限、明确放弃、终态关闭、回到游戏与存盘，达到 `e2e_verified / NOT_DEPLOYED`；native bundle 不内嵌外部 `launcher/web`，Web 字节继续由 [地图箱实施与验收基线](../docs/地图资源箱-Web战利品工作台与开锁流程-前期调研-2026-07-17.md) 的源码哈希与 WebView2 实机日志绑定。随后同一 identity / closure 经 immutable request、production receipt、`builder-local-b` + GitHub OIDC quorum、strict verifier 与 promotion，正式无参入口 attempt `9e88d51425a54b8b84dff0aa21702eac` 完成真实地图箱领取、terminal close/unpause 与存盘，达到 `standard_entry_verified`；该次冷启动虽先出现 prewarm reveal watchdog，但真实 Flash `handoff` 与 `bootstrap_reveal_ready` 均在 runtime load 和真人业务操作前到达，因此成功结论不以 watchdog 为证据。

默认启动前会先跑轻量门禁 `--build-gate arena-tools`（即 `node tools/arena-calibration/run-checks.js`）。该门会以 Ajv 2020 编译全部 schema，并同时证明合法实例通过、非法实例被拒绝；只读取 JSON schema 文件或手写字段检查不算通过。验证新 Host candidate 时必须先独立构建，再把脚本返回的精确路径交给 runner；可在 runner 内追加不产二进制的 `launcher-tests`：

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

正式 v2 consensus 当前绑定 tag `runtime-build-v2/20260825-stage-time-pools-v3`、request `ADDBA21EF66AA9429D00D349E0ACD33F27BE55641CB3B9F541ACB6BEAC47D043`、source commit `a4a85dbdcb266f66677eef28875e0862892e48ad`、release tree `0b4778aa346a6acce276052debf79a93af7a39a1`。
build identity 为 `50ED16457B8C82787A495F957259A9544AD96C819E8D1EF11087D5AF06E0BFB0`，payload closure 为 `60981913A1D18682C06B6ABF2CC6DB7EC0F57345BAF8B1D372E67D7EC3ADE5EB`。local signer 位于 `physical-host-a`，不可导出 keyId 为 `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`；GitHub Actions run `32837546069` 的 OIDC identity `B4A625D76B6E132856557C169BA3C9FA63C2B3147ABCF8AB0B905FF354C8DF40` 提供 `github-hosted-windows` 第二票。
production policy `F30603FF717C9C4B4426161451C119DCC3A0982DBF7C1A270DDEED26F371C7C8` 的 39/39 final receipt SHA-256 为 `F69E8A0569838920B86A42F3B704EABFEEF5AE4E6193A6389FB97055DDDAD9B4`；deployment commit `9f68a3ee5fbd6db9447118da12fa0fa0a00d1829` 已由首次 post-promotion audit run `32838658629` 确认为 `state=promoted`、`deploymentChanged=true`，严格 manifest/consensus 为 33 files、2 signers、2 faultDomains。
无 candidate selector 的正式入口取得 fresh reveal、前后两次 `session.status=verified`、同 lifecycle、strict shutdown receipt、Flash/Guardian exit 0、玩家调制档哈希不变与零残留。该 smoke 只证明正式身份和生命周期，不代签 JK、核电站、断壁残垣或其他业务专项 `standard_entry_verified`。cloud workflow 仍只允许 `Crazyfs` / `Flash-Night` 的固定 actor ID 首次 dispatch。

PlayerInfo B0 的 historical v1 与 F2/r2 source freeze/tag/request、双 builder、policy 和 `-VerifyOnly` 报告继续按各自历史作用域审计；F2/r2 列车自身没有 promotion。其实现字节随后被当前 `6f3d50a52413…` release 包含并进入 formal runtime，但本轮标准入口只跑 Agent Runtime 的 Launcher/NativeHud/Help WebOverlay 只读观察、结构化 opener 与 trusted shutdown，没有启用 PlayerInfo fixture 或观察真实 `pi_*`，不能把总体 runtime 发布状态写成 PlayerInfo-specific E2E。精确 source/request/identity/receipt/quorum 与启动证据以 [runtime v2 深层文档](../docs/runtime-build-reproducibility.md) 为准。

本列车还暴露过两类 portability/tooling debt。其一，历史隐藏 PowerShell worker 未显式初始化 UTF-8，中文 bundle path 被错误代码页解码并对同一 request fail-closed；显式 UTF-8 wrapper 才成功，不能据此宣称所有未来 worker 已天然跨代码页可移植。其二，四个生成物曾只有 `text=auto`，在 `core.autocrlf=true` 的 clean clone 中可物化 CRLF 并让 raw-byte `--check` 误报 stale。
2026-08-23 修复已为四文件声明 `text eol=lf`，并把真实 CRLF、Git-clean、batch/single/index OID 等价性纳入 `tools/test-runtime-build-v2.ps1`；fresh checkout 为 LF、raw/index/batch OID 相同，156 项 runtime-build 回归通过。该字节已进入本次 immutable request 与双构建/promotion，不再是 source-ahead；UTF-8 worker portability 仍是独立债务。
2026-08-25 限时关卡 v1 preflight 又暴露材料与 ShopPortraits sidecar 的两个 raw-byte 输入仍是 `text=auto`；该 v1 在 37/39 policy 后停止且未触发云构建或 promotion。v2 修复 EOL 后本地 39/39，但冻结文档仍误报 v1 的门计数，因此也未 dispatch 云构建或 promotion；v3 校正历史事实并以全新 immutable tag/request 完成上述共识与部署。三个 tag 均保持不可变。

Arena meta-team 传递派生问题同样只属于 historical PlayerInfo v1 F 当时的邻接债务：该冻结点的 `tools/derive-arena-meta-teams.js --check` 尚未比较 tracked 字节，也未进入 release prepare，因此旧 F 的双 builder/`-VerifyOnly` 从未代证该 Web 链新鲜。后续 P5 实现 commit `970a85dfdba` 已让 `--check` 精确比较 `meta_teams.json` 与 `arena-meta-rosters.js`、把 meta-team/faction generator 纳入 prepare，并将相关真源、脚本与输出纳入 runtime policy；当前 `derive-arena-meta-teams.js --check`、`derive-arena-factions.js --check` 与 `derive-arena-custom-presets.js --check` 均通过。旧约 5.8 MiB 漂移仍是 v1 F 的历史审计输入，不是当前未修复状态，也不覆盖其后 P4/P5 列车各自的 release/E2E 边界。

```powershell
$queueRoot = 'C:\qf8' # 示例专用短根；每个 release train 必须使用独立、ACL 收紧的队列，不能与旧 request 混跑
$request = ..\tools\new-runtime-build-request.ps1 `
  -QueueRoot $queueRoot -SourceKind Treeish -Treeish <full-commit>
..\tools\invoke-runtime-build-worker.ps1 `
  -QueueRoot $queueRoot -WorkerId <id> -CertificateThumbprint <thumbprint> -Once
..\tools\get-runtime-build-request-status.ps1 `
  -QueueRoot $queueRoot -RequestId $request.requestId
$cloud = ..\tools\invoke-runtime-github-build.ps1 -SourceCommitOid <full-commit>
```

最后一条命令会从受保护的单路径段 `runtime-build-v2/<release-id>` source tag 触发固定 cloud workflow，并验证 API-resolved tag、`GITHUB_REF/GITHUB_SHA` 与 run `headSha` 都精确绑定请求的 full commit；随后等待精确 run、安全解包并产出 `$cloud.proofPath`（默认只下载 attestation 小包；需把云端 candidate 字节取回本地时加 `-IncludeCandidateArchive`，才会产出 `$cloud.candidateRoot`）。unsigned job 交接 artifact 保留 1 天，失败诊断、signed 大包与 attestation 小包保留 7 天；超期未 promotion 就重新 dispatch，不把 Actions artifact 当长期档案。request、队列/CAS、双故障域 quorum、receipt 与 `promote-runtime-bundle.ps1` 的完整步骤以 [runtime v2 发布列车](../docs/runtime-build-reproducibility.md) 为准。本轮 F8 在 release source `6f3d50a52413c747b05b74be88d6ee46650f4597` 上 fresh 跑通 Runtime Lane C 11/11、scalar 572，随后完成 tag/request、本地 X509 + GitHub OIDC 双 builder、两侧同一 33-file payload、26/26 cloud-bound final policy、不可复用 `-VerifyOnly` preflight、正式 promotion 与同身份无 candidate id 的 pure-MCP Help-panel 标准入口 smoke，严格状态为 `standard_entry_verified`。该 smoke 只覆盖单屏 Launcher/NativeHud/Help WebOverlay、Flash metadata fail-closed 和 trusted shutdown；功能回归证据统一维护在 [测试指南](../agentsDoc/testing-guide.md)，本轮边界见 [F8 人工验收与正式发布记录](../docs/evidence/cf7-agent-runtime-f8-manual-acceptance-2026-07-31.md)。任何时候都禁止手工换 manifest、伪造证明，或把单机 candidate 复制进根 runtime。

### 改 Flash / AS2

不要把本目录当成编译 smoke 入口；改用：

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File ..\scripts\compile_test.ps1
```

asLoader 发布用 `powershell -ExecutionPolicy Bypass -File ..\scripts\compile_test.ps1 -Target publish -TimeoutSeconds 300`；`publish|asloader` 别名现已隐式选择 `doc.publish()` 并自动启用 `-VerifySwf scripts/asLoader.swf`，因此可省略 `-PublishOnly`。任意显式 FLA/XFL 路径只有在需要禁止 testMovie 时才额外传 `-PublishOnly`。本轮生产 AS2 已修改并发布：`scripts/asLoader.swf` 为 **1,030,706 bytes**，SHA-256 `297959B4313541022FB25853C7181B08A09D1438B81E6BE49463AD482747A518`，Git blob `52bb6a1e6b1cd3249e2c3ec4f32388a2c53d6ebc`，CS6 Compiler Errors/Warnings **0/0**。publish-only 不生成行为 trace，行为证据来自独立 fresh map-loot TestLoader runId `a7647504b7ea4aa7ae10c4feb535079d`：Arbiter **13/13**（**53 assertions**）、Service **142**、Planner **9**，Service + Planner 合计 **151**；AS2 BOM 门通过。

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
