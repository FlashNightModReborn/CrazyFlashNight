# Launcher runtime v2 可复现构建与发布列车

**文档角色**：Launcher Windows runtime 的身份、构建、证明、排队、promotion 与 CI 策略 canonical deep doc。
**最后核对代码基线**：角色构筑 ↔ 玩家自身技能双向导航正式发布冻结 source commit `c4faf14460238c7ea3e85983f31dee8be1b79afa`（tag `runtime-build-v2/20260728-character-build-skills-bidirectional-v1`）、release tree `88e9e76fbb0534c69f363a36ab838e6ecfa2d958` 与 request `BBCC17C7E46AC852BA0F1D12AA9434188C7775BEA8F593C13B13710783183548`，并由 promotion commit `45b9748baa68786a52557239d5bd7c52869970f7` 记录正式部署闭包。exact isolated candidate 已完成原生装备 → Character Build → Skills manage → 返回构筑、装备不变及 Esc/`×` 普通关闭负链；其后无参 `automation/start.ps1` 以同一正式 identity 再次完成双向 GUI 与回游戏 smoke，故当前严格状态为 `standard_entry_verified`。完整证据见 [双向导航正式关闭记录](evidence/character-build-skills-bidirectional-navigation-closure-2026-07-28.md)。

## 当前迁移状态

runtime v2 的工具、schema、队列、本地 X509 证明、GitHub OIDC/Sigstore 证明、promotion 与 CI 状态机已经完成正式闭环；**仓库当前受控部署已是 manifest/consensus v2**。当前 consensus 的 artifact source `FA66E96F314BB2E829967A716F83C019EEE62A76A5E47C8F580EE36800A23A6F`、producer recipe `DE5E1C0263A803CC416598BFDB074C20E5D22C594DF601EC231BC702793BFE7D` 与 toolchain lock `7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD` 形成 build identity `4E5EEE4AB5BE0CC8D084254C54F23AC4D6269C11CFED987409EA6BBE171CE191`；payload closure 为 `7460D8D4FC4416EDBDDFE7577403CBA7233ECC347BDF2D605BC5D2252AF39507`，manifest SHA-256 为 `72932CB04FFF5239B2862A291D85C672F55497CC629DB30B05C79B82FC32E33F`。production policy `89F35ED0F8618346614642B0D913443041345433CDDA3536046F8F1E5C6F36BE` 的 22/22 receipt SHA-256 为 `C5E683CDD3958B9CF7503DBD08C309CC6EA6E6EFF92F3203B78682AF9C1BE9C3`；`builder-local-a` / `physical-host-a`（keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`）与 GitHub OIDC builder `3B32F64D834C2A9961A7C4EA57AD998E0A463360F703904601C1A33823F675BC` / `github-hosted-windows`（run `30333045634`）的双 signer、双 faultDomain、production receipt 与 v2 strict/full-install verifier 全部满足后，于 `2026-07-28T07:32:13.5124981Z` 完成 promotion。

v1 与一次性 `migration-bootstrap` 现在只保留为历史迁移审计输入。该 marker 曾精确绑定 base `711c469036ad6b1226833faf255499abb1ebf2ed`、旧 artifact closure 与目标 builder registry 字节哈希，并在 legacy deployment 零变化时解决“cloud workflow 必须先进入 default branch”的 bootstrap 悖论；marker 后的首个部署提交已经完成完整 v2 promotion。CI 从此只接受 v2 strict 状态，并永久拒绝 v2 → v1 降级。

当前正式部署对应 source commit `c4faf14460238c7ea3e85983f31dee8be1b79afa`、build identity `4E5EEE4AB5BE0CC8D084254C54F23AC4D6269C11CFED987409EA6BBE171CE191`、payload closure `7460D8D4FC4416EDBDDFE7577403CBA7233ECC347BDF2D605BC5D2252AF39507` 与 Core SHA-256 `16DF387268E8052A0B66B2F49DD8645DB38C37EB23430D4AC0CB46527A3B9BA0`，包含角色构筑 ↔ Skills exact 双向导航、原生 workbench nonce、失败回滚及此前正式能力。无参正式根入口以 `formal_runtime` 启动并绑定上述身份，runtime attempt `d508d2dac3964c6fa92ba98675bfdc15` 完成原生装备 → Character Build → Skills manage → 返回构筑 → Esc 回游戏；实际 GUI、fresh Host/AS2 marker 与进程退出共同闭环。native identity / closure 只覆盖正式 runtime 文件闭包；Web/Flash 字节及业务闭环另由冻结 source/release tree、production policy 与实机证据绑定。因此 `standard_entry_verified` 是机器证据与实际视觉验收的组合结论，不由 consensus 单独推出。source-only、隔离 candidate 与已 promotion 的正式 Core 仍是三件不同的事；root EXE、`runtime/**`、manifest、builder registry 或 consensus 若变化，Audit 必须转入 strict 并在无匹配 promotion 时失败。

历史 `chest-s0-a8a-local-r3/r4` 是 2026-07-18 基于 `a8a760a3cc` 的同机未注册诊断；S0 已从当前源码与 required-assets policy 退役，这些旧 artifactSource/buildIdentity/payloadClosure 只留在 Git 历史和旧 ADR 中，不代表当前工作树、release evidence 或待恢复的发布输入。

2026-07-19 本机构建阻塞已经解除：锁定 bootstrapper FileVersion `17.14.37502.11` 已把 side-by-side Build Tools 安装到 `C:\Program Files (x86)\CF7VS\BT1736`，cl `19.44.35228.0`、link `14.44.35228.0` 与 Windows SDK `rc` 均通过 lock 中的精确版本和 SHA-256 门；`bootstrap-runtime-build-env.ps1 -VerifyOnly` 与 `check-runtime-build-env.ps1` 均 exit `0`。安装后还修复了 Windows PowerShell 5.1 对 `vswhere` 顶层 JSON 数组的函数返回包装：现在逐实例输出，旧 VS 与 BT1736 不会被拼成一个虚假 `installationPath`，同一进程即可重新发现 side-by-side 实例。

2026-07-19 的 `AE1FC1EF… / 172A85C6…` 23-file diagnostic candidate 曾在临时开发目录完成基础启动、map/tasks/NPC 与早期 loot claim/close/unpause/存盘诊断，并暴露 `TransparencyKey` 点击穿透、claim-all 收束与 terminal late-ack 问题；它不含后续修复，也不代表以 `b072f97841ccb30e167c14495241ae64d9054e22` 为 upstream base 的本轮发布。该 candidate 及其后的 FCA19/B2AF/231388 等合并前 loot diagnostic candidate 均已退役。本轮人类 E2E 最初使用的隔离 candidate 位于 `tmp/runtime-candidates/v2/c-2a0cddb077b7-08846e81b3-20260721t100014612z-f32a40a3`，绑定 build identity `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107`、payload closure `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C` 与 Core SHA-256 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`；corrected Agent entry、正常 NativeHud、同实例 organizer、普通 suspend/same-anchor 内容不变 reopen/final claim 已在该候选完成，因此它在当时达到 `e2e_verified / NOT_DEPLOYED`。随后同一 build identity / payload closure 经 source commit `c60aab2386aee4516608397373ae4c59148c5f77` 的 immutable request、production receipt、`builder-local-b` + GitHub OIDC quorum 与 strict verifier 完成 promotion；prewarm-held 正式入口 attempt `4eae1360cedd413fa3175db6a8997158` 又取得 fresh title marker、exact attempt receipt，完成真实 loot 两次 claim、terminal close/unpause 与存盘，故唯一 canary 达到 `standard_entry_verified`。此前一次正式入口 attempt 因 reveal watchdog 先于真实 title receipt 而以 `title_frame_not_observed` 失败，保留为换机/冷启动 portability 历史观察，不覆盖后续成功结论。隔离 candidate 的 25-file native payload 不含 `launcher/web`，外部 Web 字节仍由源码哈希与 WebView2 实机日志独立绑定，不能由 native identity/closure 代证。

## 不变量

- 单个进程、机器名或自由填写的 `BuilderId` 都不构成独立 builder；正式 quorum 至少需要两个不同签名身份和两个不同 `faultDomain`。
- producer 只生产二进制 payload，不运行生成器或产品政策审计；政策变化不能污染 payload 身份。
- request JSON 没有自由命令字段，只冻结 Git tree 与政策身份；但 Git bundle 本身含 producer/MSBuild/Cargo 源码，worker 会在 builder 账户下执行该冻结 commit 的构建代码。因此共享 queue 是受控写入信任边界，必须限制写权限；四域复算与 promotion 能阻止错误产物晋级，不能判断源码业务意图，也不能把恶意 queue writer 沙箱成无 RCE 能力。
- candidate、CAS 与 attestation 都不能直接覆盖正式部署；只有 promotion 能事务写入根 bootstrap、`runtime/`、manifest 与 release consensus。
- strict/promotion 状态逐文件验证字节闭包；日常 native 源码可以处于 `source-ahead` 而不立刻 promotion。事后 Audit 在部署字节未变时不读取 payload blob，也不声称验证源码内容语义；只有正式部署闭包变化才必须携带完整新共识。
- 工具链不匹配、证明不足、相同故障域、分叉 payload、脏部署或无效政策 receipt 都 fail-closed；禁止伪造第二 builder、手改 hash/receipt/attestation 或复制单机 candidate 到正式 runtime。

## 开发到正式验收状态机

| 状态 | 最小证据 | 明确不代表 |
|------|----------|------------|
| `compiled` | 编译命令成功，输出仍可位于 `bin/obj` 或其他临时目录 | candidate 已生成、运行时已加载新字节 |
| `candidate_built` | producer 返回唯一 immutable `candidateRoot`，metadata/manifest 的 build identity 与 payload closure 自洽 | 已执行、已部署 |
| `candidate_executed` | 推荐由 `automation/dev.ps1` 按当前 Worktree build identity 精确选择后启动；低层诊断也可用 `automation/start.ps1 -CandidateRoot <absolute candidateRoot>`。两者都须确认 `runtimeMode=isolated_candidate`，且实际 process path、Core SHA-256、build identity、payload closure 全部匹配 | 领域 E2E 已通过、正式入口已更新 |
| `e2e_verified` | 在上述已绑定 candidate 进程中完成受影响领域的真实 Web→Host→AS2→回包 / 写后回读门 | promotion 或正式验收 |
| `promoted` | 唯一 promotion 入口完成事务替换、v2 consensus 与 full-install `--verify-only` | 标准玩家入口已实际加载该身份 |
| `standard_entry_verified` | promotion 后无参数运行 `automation/start.ps1` / 根 bootstrap，确认 `runtimeMode=formal_runtime`、正式 Core 路径/SHA-256/build identity/payload closure 与被提升身份一致，并完成受影响领域 smoke | — |

状态只能按 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified` 报告；允许因任务范围停在中间，但不得跨级命名。只有同一身份已达到 `promoted` 且随后达到 `standard_entry_verified`，才可称“已部署 / 正式验收”。日常开发显式走 `automation/dev.ps1`：它按当前 Worktree 身份精确复用/生成隔离 candidate，但始终为 `NOT_DEPLOYED`。`automation/start.ps1` 无参数只消费正式根部署，不得猜测或自动选择 `launcher/bin`、`tmp/runtime-candidates/` 中的“最新”输出；`start.ps1 -CandidateRoot` 仅保留为指定精确候选的低层诊断兼容入口，不再推荐手工直启 Core。

## v2 四域身份

`config/build/runtime-inputs.v2.json` 是输入域清单。四域互斥，发现同一路径同时属于两个域会失败。

| 身份 | 内容 | 变化后的动作 |
|------|------|--------------|
| `artifactSourceHash` | C#、C/C++、Rust 与项目/包输入等真正影响 payload 的源码 | 必须重新构建 |
| `producerRecipeHash` | 纯 producer、native build、环境门与确定性参数（含 `sol_parser/.cargo/config.toml` 的 `/Brepro` 链接参数） | 必须重新构建 |
| `toolchainLockHash` | runtime toolchain lock、`global.json`、Rust toolchain | 必须重新构建并重新取得环境资格 |
| `policyHash` | 生成器、审计器、队列/证明/promotion/CI 规则及已派生发布资产 | 新 request + 新政策 receipt；前三域未变时可复用同一 build identity/CAS payload |

`buildIdentityHash = SHA256(artifactSourceHash + producerRecipeHash + toolchainLockHash)`，故意不含 `policyHash`。`releaseTreeOid` 冻结完整 Git tree，`requestId = SHA256(releaseTreeOid + policyHash)`；两者分别回答“发布哪棵树”和“用哪套政策批准”。

`policyHash` 与日常审计触发集合不是同一个集合。`config/build/native-change-gate.v1.json` 联合前三域、payload、全局 native 扩展/入口名和 release 信任链路径，回答“这次 push/PR 是否值得启动 native/runtime 事后审计”；广义内容 policy 不因此变成 native。命中源码边界但未改部署字节时，Audit 成功报告 `source-ahead`，不要求即时 promotion。生成器、审计器和派生发布资产仍留在 `policyHash`，下一次正式 release 再用当时完整 release tree 建 request 与 receipt。

`payloadClosureHash` 对根 `CRAZYFLASHER7MercenaryEmpire.exe` 与 `runtime/**` 的实际 payload 文件有序计算，明确排除 `runtime/cf7-runtime-manifest.tsv`、证明与 release record。这样 manifest/policy 元数据变化不会被误判成二进制失衡；manifest v2 再记录四个构建字段中的前三个、`buildIdentityHash`、`payloadClosureHash`、工具链可读名和逐文件大小/SHA-256。

## producer 与政策闸门

发布链分成三个职责，不能重新合并：

1. `tools/prepare-launcher-release-assets.ps1` 只恢复锁定的 TypeScript/字典依赖并派生受跟踪发布资产。`save_schema.json` 默认保留；只有显式 `-SaveSchemaSource` 才从指定 canonical save 重建，避免私有存档和时间戳偷偷进入发布。
2. `launcher/build-runtime-candidate.ps1` 是纯 payload producer：先执行精确环境门，再在 job 独占的 native/Cargo/MSBuild/temp 目录构建 miniaudio、Rust parser、bootstrap 与 FDD Core，生成不可覆盖的 v2 candidate。candidate 尚无正式 consensus，因此这里只同步、有界等待 bootstrap `--verify-runtime-only` 并检查真实 exit code；失败会保留/输出受限日志，成功必须删除 `logs/`。它不跑 Web/数据产品审计，也不签名。
3. `tools/validate-launcher-release-policy.ps1` 是只读政策门：绑定 `releaseTreeOid` 与四域身份，验证 tracked tree 在审计前后未变化，按需严格验证 candidate，并把每项结果写成 `cf7-runtime-policy-validation.v2` production receipt。它既支持 clean commit 的 `Worktree` 身份，也支持工作树逐字节 materialize 同一 staged tree 的 `Index` 身份；candidate 始终按磁盘 payload 复核。候选优化检查会丢弃调用者注入的 `CF7_DOTNET_EXE`，重新运行锁定工具链门禁并只接受其选出的 host；门禁不产出精确 host 就禁止签发。`required-web-runtime-assets` 必须覆盖生产懒加载闭包；地图资源箱必须逐项包含 `modules/loot/loot-runtime.js`、`loot-state.js`、`loot-view.js`、`loot-organizer.js` 与 `loot-panel.js`，任一缺失都 fail-closed 并在 receipt 点名。`panel-cross-layer-contracts` 使用的契约 JSON、validator 与变异测试脚本全部进入 `policyHash`，同时由 native change gate 和 GitHub workflow paths 触发事后审计，避免 sparse materialize 缺少门禁输入或未来只改契约却漏审。子审计 stdout/stderr 只进入人类/CI 日志，不能混入结构化 `checks[]`。receipt 只能写未跟踪路径。

`launcher/build.ps1` 只是人工兼容编排器：prepare → pure producer → policy。它只写隔离 candidate，最多把状态推进到 `candidate_built`，不写根 bootstrap 或正式 `runtime/`；它适合已准备好的本地 tree 做完整候选检查，但不是多机发布协议，也不会替代签名 worker、immutable request 或 quorum。

未提交工作树的可见功能检查统一走 `automation/dev.ps1`（或根 `本地开发启动.cmd`）。它重算当前 Worktree build identity，只复用同身份且闭包唯一的 candidate；无命中时以 `-SkipPrepare -SkipPolicy -BuilderId local-dev` 新建隔离 candidate。`-Status` 只读报告匹配/过期/同身份闭包分叉，`-ReuseOnly` 禁止构建，`-ForceBuild` 强制新建但仍拒绝分叉闭包，`-BuildOnly` 只选择/构建并验证而不启动。忽略的 `tmp/runtime-dev/active.v1.json` 只是 repository-relative 选择索引，不授予信任，每次执行前仍重验字节身份。

`dev.ps1` 最终把精确 candidate 交给 `automation/start.ps1 -CandidateRoot`。该低层入口只接受当前仓库 `tmp/runtime-candidates/v2/` 下的 canonical 非 reparse producer 输出，严格核对完整安装哨兵、candidate metadata、runtime manifest、`buildIdentityHash`、`payloadClosureHash` 与 Core SHA-256，再调用 candidate 自身 bootstrap `--verify-runtime-only`；Core 启动后仍按同一身份反向自检，并显式使用当前完整安装根加载工作树 Web。只有报告/日志中的 `runtimeMode=isolated_candidate`、`processPath`、`coreSha256`、`buildIdentity`、`payloadClosure` 全部与预选 candidate 一致，才能报告 `candidate_executed`。目录 walk-up、候选树外搬运、reparse 别名或 marker/身份漂移一律 fail-closed；该模式始终 `NOT_DEPLOYED`，不产生签名、receipt 或 promotion 权限，也不得把 candidate 手工复制进正式 `runtime/`。

prepare 中的派生器必须字节幂等；例如 save-repair dictionary 仅在结构内容变化时刷新 `generated.at`。重复 prepare 因时间戳制造 diff 属于构建门故障，不能要求维护者提交无语义的时间漂移。

## 精确环境与隔离输出

- 新机器先运行 `tools/bootstrap-runtime-build-env.ps1`；已有环境用 `-VerifyOnly`。若已有实例的精确 MSVC 字节不匹配，bootstrap 不会用旧实例的同名 component ID 冒充锁定 payload，而会走锁定 bootstrapper 的专用 side-by-side 目录；只有工具字节已匹配、仅缺 SDK 时才对该实例执行 `modify`。Windows PowerShell 5.1 下必须逐个输出 `vswhere` 解析到的实例，禁止把顶层 JSON 数组作为单个 `Object[]` 返回后拼接安装路径。正式 producer 每次仍会重跑 `tools/check-runtime-build-env.ps1`。断网复用已有精确匹配 candidate 不需要云端；断网重建则必须预先安装通过锁定门的工具链，并已缓存 NuGet/Cargo 依赖。
- `config/build/runtime-toolchain.lock.json` 锁定 .NET SDK/host、Roslyn/MSBuild、MSVC `cl/link`、Windows SDK `rc`、Rust `rustc/cargo` 及 bootstrapper 入口字节；NuGet 图由 `launcher/packages.lock.json` 固定。Visual Studio 安装器只是尽力补齐组件，不能把会移动的在线 channel 伪装成已固定 payload；最终资格始终以 `cl/link/rc` 的版本与 SHA-256 精确门为准。`.NET` provisioning 脚本也必须使用 `dotnet/install-scripts` 官方仓库的完整 commit URL 并固定 SHA-256，禁止重新使用会因 Authenticode 重签而变字节的 `https://dot.net/v1/dotnet-install.ps1`。
- 当前基线 `cf7-win-x64-2026-07-22` 为 .NET SDK `10.0.300`、Visual Studio Build Tools `17.14.36` / installer `17.14.37502.11` / MSVC toolset `14.44.35207`（cl `19.44.35228.0`、link `14.44.35228.0`）、Windows SDK `10.0.22621.0`、Rust `1.96.0`；精确 SHA 只以 lock JSON 为准。2026-07-22 已核验 `dot.net` 当前脚本的 Microsoft Authenticode 签名有效，去除签名块后与官方 `dotnet/install-scripts@4a37a9f9d1a061fc389d6515100336db4e51710e` 源码逐行相同，因此 provisioning 改用该不可变源码字节。2026-07-19 本机 BT1736 的 bootstrap `-VerifyOnly` 与独立环境门均为 exit `0`。
- producer 清除外部编译/链接/Rust 注入变量；miniaudio 源先规范化为 LF，再用固定 `/pathmap`、`/experimental:deterministic`、`/Brepro`；Rust 每次 clean + locked；managed publish 不带 PDB/SourceLink。
- candidate 默认位于 `tmp/runtime-candidates/v2/c-<identity-prefix>-<builder-hash>-<run-token>/`，完整 build identity / builder label 只存 metadata 与证明，避免目录名把 legacy `MAX_PATH` 撑爆；producer 在编译前后都做 259 字符预算门，已存在目录不覆盖。native / Cargo / MSBuild / `TMP` / `TEMP` 的 job 工作根默认位于环境门规范化后的 machine-local `[IO.Path]::GetTempPath()/cf7-runtime-build-work/job-<token>/`，避免仓库位于 `Program Files (x86)` 等含括号路径时把 CMD 元字符传给 VsDevCmd；`CF7_RUNTIME_WORK_ROOT` 只能覆盖为短的本机绝对目录，卷根、UNC/映射网络盘、reparse point、仓库内/祖先、CMD 元字符或 projected MAX_PATH 超限均 fail-closed。队列 worker 从 request Git bundle 创建隔离 clone；输出按 job 分离，不再共享 `launcher/bin/Release`、Cargo target、MSBuild obj/bin 或临时目录。

## 本地 builder enrollment 与证明

每台本地发布机一次性执行：

```powershell
chcp.com 65001 | Out-Null
$entry = .\tools\register-runtime-builder.ps1 `
  -BuilderId <builder-id> -FaultDomain <physical-fault-domain>
```

脚本在 `Cert:\CurrentUser\My` 创建 3072-bit、不可导出的 RSA 私钥，只把 public certificate/`keyId`/epoch/faultDomain 写到 `tmp/runtime-builder-enrollment/`，**不会自动改 registry**。维护者核对机器与故障域后，才把 entry 合入 `config/build/runtime-builders.v2.json`。私钥不得导出或跨机复制；轮换/撤销通过新 epoch/key 或 `enabled=false` 完成。两台 VM 若共享同一宿主、磁盘或管理员边界，不得宣称两个 faultDomain。

tracked registry 继续保留 `builder-local-a` / `physical-host-a` 与 `builder-local-b` / `physical-host-b` 两张公钥；本次 consensus 实际采用 `builder-local-a` 的 keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3` / `physical-host-a` 和 GitHub Actions run `30333045634` 的 OIDC builder identity `3B32F64D834C2A9961A7C4EA57AD998E0A463360F703904601C1A33823F675BC` / `github-hosted-windows`。任一单独本地票都仍不构成 quorum，也不授权单机 promotion。

本次 local proof 使用已注册的 `builder-local-a` 3072-bit CurrentUser 不可导出 RSA key：keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`、thumbprint `647AFE92BD801518AF25F2A2EE1845E6847C2118`、epoch `1`；未复制或导出私钥。不同故障域的第二票由 GitHub hosted OIDC/Sigstore 提供，双 faultDomain quorum 已满足；dirty staged/unstaged/untracked 工作树仍不能冒充 source commit。

worker 使用该 CurrentUser certificate 对 canonical payload inventory 做 RS256 签名。验证端只信 tracked registry 中启用且 epoch/faultDomain/certificate 全匹配的 key；旧式自由文本 builder ID 不再计入 v2 quorum。

## immutable request、队列与 CAS

需要跨机器时，所有 worker 指向同一具备原子目录 rename 语义且仅受信维护者可写的 `-QueueRoot`（例如 ACL 收紧且共享名前缀足够短的 SMB 共享）；默认 `tmp/runtime-build-queue` 只适合路径预算允许的单仓本地演练。目录包含 `requests/`、`leases/`、`results/` 与 `cas/candidates/`，不进 Git。QueueRoot 本身也受传统文件 259 字符、目录 247 字符预算约束，因为 CAS final path 保留完整 build identity 与 payload closure，失败记录还允许 128 字符 diagnostic 文件名；request 与 worker（包括 DryRun）都必须在建目录、取证书或编译前 fail-fast，复制时再按实际 payload 路径复核。Windows 本机正式队列应给每趟列车分配经预算检查的专用短根（例如本列车使用 `C:\cf7q`），不要在 `%LOCALAPPDATA%` 后继续拼 release-id 深目录；worker 没有 RequestId 过滤，含未 `ready` / `superseded` request 的根不得直接混跑下一列车。队列可以共享，但 worker 的隔离 checkout 默认放在本机短路径 `%LOCALAPPDATA%\CF7\runtime-build-checkouts`；worker 会清除外部 `GIT_INDEX_FILE/GIT_DIR/GIT_WORK_TREE/object/config-count` 上下文，并在 materialize 前固定 local Git `core.autocrlf=false`、`core.longpaths=true`，避免 worker 账户的全局换行策略改变 Worktree identity。checkout/candidate 目录只使用 request、worker 的短哈希并预检 MAX_PATH；包含 legacy 深路径的本机 checkout 通过扩展路径形式安全清理。只用 `-CheckoutRoot` 或 `CF7_RUNTIME_CHECKOUT_ROOT` 覆盖，不要把 checkout 放进共享队列、网络盘或层级很深的项目目录。

最终 tree 已提交时使用 `Treeish`；只有纯本地双 builder 才可用 `Index` snapshot。需要 GitHub cloud builder 时必须先提交，并让 request 与 cloud workflow 使用同一 full commit：

```powershell
$request = .\tools\new-runtime-build-request.ps1 `
  -QueueRoot <queue-root> -SourceKind Treeish -Treeish <full-commit>
$requestId = $request.requestId
```

request 内含完整 frozen `releaseTreeOid`、四域 hash、build identity、source/request commit，以及只覆盖四个 v2 identity domain 精确 Git blob 子树的 `source.bundle`、`bundleTreeOid` 与 bundle SHA；大型无关 tracked asset 仍由 `releaseTreeOid` 绑定，但不会塞进 worker bundle。冻结 stage-0 条目时固定 `core.quotepath=false`，路径字段必须按仓库中的 UTF-8 字面值比对，不能让机器级 Git 配置把中文路径转成 C 风格转义文本。worker clone 后复核 `bundleTreeOid`，相同 tree+policy 幂等复用；tree 已过时就创建新 request 并用 `-SupersedeRequestId <old-id>` 标记旧列车，不删除历史。

每台已 enrollment 的本地机器运行：

```powershell
.\tools\invoke-runtime-build-worker.ps1 `
  -QueueRoot <queue-root> -WorkerId <builder-id> `
  -CertificateThumbprint <thumbprint> -Once
# 常驻机器可改用 -Watch；状态查询：
.\tools\get-runtime-build-request-status.ps1 `
  -QueueRoot <queue-root> -RequestId $requestId
```

worker 具有单机 mutex、request lease、heartbeat/TTL 与失败记录；抢到 lease 后从 Git bundle 隔离 clone、复核 frozen tree/identity、调用纯 producer、签名并发布结果。失败时会在删除短 checkout 前把非 reparse、单文件 ≤1 MiB、总计 ≤2 MiB 的 bootstrap diagnostics 写到该 request 的 `_failures` 记录；若 queue I/O 已不可用、失败记录本身无法落盘，worker 只追加固定告警并保留原始构建错误，不能让二次诊断写失败覆盖首因或转成成功。CAS 地址是 `buildIdentityHash/payloadClosureHash`；发布前后都严格复核 candidate，key 对同一 build identity 出现分叉 closure 会作为 equivocation 拒绝。状态退出码固定为 `0=active 全 ready`、`10=pending/empty`、`20=failed/invalid`、`30=只有 superseded`。status 只统计 queue 内本地 X509 result；采用 local + GitHub 时显示 `1/2` 是正常的，最终 combined quorum 由 promotion 把该本地 proof 与外部 verified GitHub proof 一起计算。

推荐把便宜、可离线完成的失败门前移：先取得本地 X509 candidate/proof，再对**该本地 candidate** 跑一次 production policy preflight；这份 preflight receipt 只用于提前暴露 source、CSS、inventory 等政策问题，因为 receipt 绑定具体 `candidateRoot`，不能拿去批准稍后选中的 cloud candidate。preflight 通过后再消耗 GitHub hosted build；cloud proof 到手并选定最终 cloud candidate 后，仍须针对该 cloud candidate 重新签正式 production policy receipt，promotion 只接受后者。这样不削弱双故障域和最终 receipt 约束，同时避免本地即可发现的政策失败拖到云构建之后。

## GitHub hosted 独立故障域

`.github/workflows/runtime-cloud-builder.yml` 提供第二种 producer：只接受人工 `workflow_dispatch`，并在分配 hosted runner 前要求 `github.run_attempt == 1`，且 `github.actor_id` 必须是 `Crazyfs` 的 `91271520` 或 `Flash-Night` 的 `138298913`；失败后重新 dispatch，不能用 rerun 按钮绕过首次运行约束。授权只限制正式发布能力和 Actions 消耗，不构成第二人审批：两名授权发布者中的任一人都可以独立触发。从一次性 source tag dispatch full source commit 后，workflow 在明确的 `windows-2022` / VS 2022 runner family 精确 checkout、配置锁定工具链、运行纯 producer 并验证 v2 candidate；运行时还复核 `RUNNER_ENVIRONMENT`、`RUNNER_OS` 与 `ImageOS=win22`。`windows-2025` 自 2026-06 起已被 GitHub 迁到 VS 2026，不能再承载当前 17.14/v143 锁。checkout 先只取 config/materializer seed，再由 `runtime-inputs.v2.json` 展开四域精确文件集合；禁止为约 9 MiB 的 producer 输入铺开约 4.5 GiB 工作树并挤占 hosted runner 的安装/构建空间。Index 固定文件的存在性必须用 Git object 查询，不能比较受 `core.quotepath` 影响的展示文本；sparse-checkout 的标准输入固定为 UTF-8，因此根目录中文入口在无用户级 Git/终端配置的干净 hosted runner 上也必须可复现 materialize。producer 失败时上传独立 bootstrap/Visual Studio setup diagnostics。独立 `attest` job 仅对 deterministic envelope 调用 `actions/attest`；权限限定为 `id-token: write` / `attestations: write`，使用 GitHub OIDC + Sigstore/SLSA keyless provenance，不保存长期私钥。

`config/build/runtime-github-builder.v2.json` 固定 repository、signer workflow、release source ref、`github-hosted-windows-2022` runner class 与 `github-hosted-windows` faultDomain。日常 release train 使用一次性、单路径段的 `refs/tags/runtime-build-v2/<release-id>`：cloud config、dispatch helper、envelope/attestation verifier 与 admission audit 都拒绝其他命名空间及嵌套 tag，保证 `sourceRef` 必定受 creation + immutability ruleset 保护。tag 必须精确指向 source commit，helper 在 dispatch 前经 GitHub API 解析并 peel annotated tag、拒绝目标不等；workflow 再断言 `GITHUB_REF` 与 `GITHUB_SHA` 分别等于该 tag 和 requested full commit，helper 定位/等待 run 时也要求 `headSha` 相等。由此 GitHub 实际执行的 workflow 字节与被四域政策 hash 绑定的 workflow 字节来自同一 commit，证明同时绑定 tag、full commit 与 tree。远端 creation ruleset 只允许两个授权发布账号创建新 tag，再由无 bypass 的 update/deletion ruleset 冻结已创建 tag；不要删除或移动已经出具证明的 tag。runner 镜像的小版本仍由 GitHub 滚动维护；任何工具字节变化都会被 toolchain lock fail-closed，必须显式轮换基线，不能自动放宽。最短触发、等待、取回与验真命令是：

```powershell
$cloud = .\tools\invoke-runtime-github-build.ps1 -SourceCommitOid <full-commit>
# promotion 使用：-CandidateRoot $cloud.candidateRoot -ExternalAttestationPath $cloud.proofPath

# 进程或网络中断后，复用同一已完成 run；helper 会重验 run / artifact metadata 后续传 .partial：
$cloud = .\tools\invoke-runtime-github-build.ps1 `
  -SourceCommitOid <full-commit> -ResumeRunId <run-id>

# 只用于受控恢复/离线 transport fixture；不会绕过 metadata、双层解压或 Sigstore 验真：
$cloud = .\tools\invoke-runtime-github-build.ps1 `
  -SourceCommitOid <full-commit> -ResumeRunId <run-id> `
  -PreDownloadedArtifactArchive <outer-artifact.zip>
```

helper 只触发固定 workflow，用精确 `run-name`、`headSha` 与 dispatch 前 run ID 集定位本次同 commit run；`-ResumeRunId` 不重新 dispatch，但仍以同一套 identity 门重验指定 run。run 成功后，helper 查询该 run 的官方 Actions artifact metadata，要求唯一精确名称、artifact/run ID、`workflow_run.head_sha`、大小、未过期状态与 `sha256:<64hex>` digest 全部成立；随后用 GitHub CLI token 只向官方 API 换取短期 HTTPS redirect，不记录 token 或 signed URL。外层 ZIP 默认经 HTTPS 流式传输，奇数次直连、偶数次系统代理，失败只保留 `artifact-download/artifact-<id>.zip.partial`；重试发送 `Range`，严格要求 `206`、起止字节、总长和 `Content-Length` 与 metadata 一致，每约 5 MiB 只报告 received/expected 字节数。完整大小和 SHA-256 都通过后才把 partial 改名。

外层 Actions ZIP 必须恰好包含根目录三文件 `runtime-candidate.v2.zip`、`runtime-build-envelope.v2.json`、`runtime-build-envelope.v2.sigstore.json`，并通过 entry count、路径、大小、link/reparse 与 case-collision 门；之后内层 candidate 再走原有 safe extractor，最后调用 `verify-runtime-github-attestation.ps1`。`-PreDownloadedArtifactArchive` 只是 transport 测试/恢复 seam：仍查询所选 run 的 exact metadata、校验外层大小/digest，并走相同的外层/内层解压和 Sigstore verifier，不能成为离线信任旁路。验证器通过 `gh attestation verify` 同时钉住 repository、workflow、source-ref、commit/tree、envelope/candidate inventory 与全部身份字段，并输出可直接交给 promotion 的 normalized proof。下载 artifact 本身不可信；只有该验证通过后才算 GitHub producer。推荐 quorum 是“一个注册本地 X509 builder + GitHub OIDC builder”；两个注册本地 builder 也可，但必须拥有不同 key 和真实不同 faultDomain。

`test-invoke-runtime-github-build.ps1` 的确定性默认套件通过预下载 seam 覆盖 exact metadata、outer/inner 恶意 ZIP、digest/run/head 负例、恢复选 run 与最终 verifier，并静态钉住 Range/长度/文件模式/进度契约；它不伪造 TLS 或把本地 HTTP 冒充 GitHub/Azure 网络行为。修改下载器后，除离线套件外还要用一个未过期的真实 Actions artifact 执行默认 helper，或受控构造 partial 后跑真实 HTTPS `206` 续传，确认最终 outer SHA-256 与 GitHub metadata 相等。

Actions artifact 只是短期交接介质：unsigned candidate/envelope 保留 1 天；失败 bootstrap diagnostics 保留 7 天；signed candidate/envelope/Sigstore bundle 保留 7 天。超过 signed 窗口仍未 promotion 时重新 dispatch，不能把 artifact retention 当长期证据仓。promotion 后 tracked v2 consensus 内嵌的验证材料才是仓库审计记录。

## 政策 receipt 与 promotion

在与 request tree 完全一致、tracked 内容干净的工作树中运行：

```powershell
.\tools\prepare-launcher-release-assets.ps1 -ReleaseTreeOid <full-commit>
# 若生成物变化：审阅、提交，再用新 commit 建 request；不得对旧 request 继续发布。
.\tools\validate-launcher-release-policy.ps1 `
  -ReleaseTreeOid $request.releaseTreeOid `
  -CandidateRoot <verified-candidate> `
  -ReceiptPath tmp\runtime-policy-receipts\release.v2.json
```

promotion 自动读取 queue 中匹配 build identity 的本地签名结果，并可追加已 normalized 的 GitHub proof：

```powershell
.\tools\promote-runtime-bundle.ps1 `
  -QueueRoot <queue-root> -RequestId $requestId `
  -CandidateRoot <verified-candidate> `
  -PolicyReceiptPath tmp\runtime-policy-receipts\release.v2.json `
  -ExternalAttestationPath tmp\runtime-cloud-result\verified-github-proof.v2.json
```

promotion 重新验证 request/worktree/receipt/candidate/所有证明，要求至少两个不同 signer identity + faultDomain 且五项共同产物字段（前三域、build identity、payload closure）全等；随后在 `tmp/runtime-promotions/` 组装 next/previous，事务替换正式 runtime、bootstrap 与 `config/build/runtime-release-consensus.json`。v2 consensus 内嵌 policy receipt 与全部签名/Provenance proof；正式安装完成后同步、有界等待 full-install bootstrap `--verify-only` 并检查真实 exit code，两个 verify 模式同时出现会按 CLI 误用拒绝。任何失败或 120 秒超时都进入自动回滚，previous 保留供人工恢复。

## CI 事后 Audit 状态机

`.github/workflows/runtime-bundle-integrity.yml` 是事后审计器，不是 required status context。它监听 `main` push、目标为 `main` 的可选 PR，以及获授权发布者的 `workflow_dispatch`；不再监听 `merge_group`，也不申请 Actions/Checks API 权限。静态 `paths` 只覆盖 native gate 的扩展名、基名、固定路径和前缀，再联合 artifact source、producer recipe、toolchain lock 与 payload roots/trees。纯 docs/data/Flash/XFL/Web-only 变化不启动 Windows runner。修改 native gate 或 runtime input descriptor 时必须同步 workflow paths 与回归，避免“配置认为需要审计、GitHub 却未触发”的裂缝。

该 `paths` 过滤只用于常规成本控制。GitHub.com 对 path filter 的生成 diff 只检查前 3,000 个文件；匹配文件落在窗口之外时 workflow 可能不启动，而超过 1,000 个 commit 或 diff 生成超时会让 workflow 总是启动。故超大提交下既可能漏审，也可能让纯内容提交占用 runner；这不会改变正式 release 的 immutable tag / quorum / receipt / promotion 安全边界。官方行为见 [Git diff comparisons](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#git-diff-comparisons)。

job 名为 `audit-native-runtime`。所有事件都以 job-level `github.run_attempt == 1` 在 runner 分配前拒绝 rerun；`workflow_dispatch` 再限制为 `Crazyfs` / `Flash-Night` 的固定 actor ID，并传入 `-ForceDeploymentVerification`，强制当前 HEAD 走 integrity、source identity 与 strict consensus 全链，作为明确的 release-readiness 检查。push/PR 则用于对真实 diff 做低成本被动审计。它不解析外部成功绿灯锚，也不把某次 Actions success 变成服务端准入权。

`tools/classify-runtime-release-state.ps1 -Mode Audit` 先完成 Git path safety 与 native binding 检查，再计算 `deploymentChanged`：

| 状态 | 条件 | 行为 |
|------|------|------|
| `source-ahead` | native/release 输入发生变化，但根 EXE、`runtime/**`、runtime release consensus 与 builder registry 等部署闭包未变 | exit 0；输出 `state=source-ahead mode=Audit deploymentChanged=false`；不运行 verifier，不下载或重哈希 payload。这是正常开发态，不要求即时 promotion |
| deployment unchanged 但路径/绑定非法 | 危险 Git path、symlink/gitlink/mode/case collision，或新增/修改 native 对象未被 descriptor/payload/canonical release control 绑定 | 失败报警；修复边界，不用 descriptor 漏列绕过审计 |
| deployment changed | 根 bootstrap、`runtime/**`、manifest/consensus、builder registry 等正式部署闭包变化 | 运行逐文件 v2 integrity + strict signed consensus；缺少匹配 promotion、证明不足、闭包分叉或 v2 → v1 时失败 |

push 红灯发生时提交已经进入 `main`；workflow 只能报警，不能回滚。PR 事件可以提供提前反馈，但仓库不要求 PR，也不会把该检查设为 merge gate。正式 release 的可靠边界仍是 immutable source tag、local X509 + GitHub OIDC 双生产者、production receipt 与 promotion，而不是一次普通 CI success。

`config/build/main-branch-admission.v2.json` 描述远端仅有的三条不依赖 Actions 的 ruleset：`main-global-ref-integrity-v1` 无 bypass 地禁止删除与 non-fast-forward；`runtime-source-tag-creation-v1` 只允许两个授权发布账号创建 `runtime-build-v2/*`；`runtime-source-tag-immutability-v1` 无 bypass 地禁止已有 source tag update/deletion。没有身份 gate、Require PR、CODEOWNER 或 required status check。所有 write collaborator 都能 fast-forward 直推，包括 native 路径；GitHub Free 公开仓库没有本方案可用的服务端 path push restriction，完整残余风险见 [contribution-workflow.md](contribution-workflow.md)。

## 验证矩阵与诊断

```powershell
.\tools\test-runtime-dev-entry.ps1
.\tools\test-runtime-entry-guardrails.ps1
.\tools\test-runtime-build-v2.ps1
.\tools\test-runtime-release-policy.ps1
.\tools\test-runtime-build-queue.ps1
.\tools\test-runtime-github-attestation.ps1
.\tools\test-invoke-runtime-github-build.ps1
.\tools\test-main-branch-admission.ps1
.\tools\test-runtime-release-state.ps1
.\tools\test-runtime-build-consensus.ps1   # v1 migration guard
.\tools\test-runtime-release-consensus-v2.ps1

# Supplemental；不计入下述 Runtime Lane C 11/11 与 scalar 400
.\tools\test-resolve-runtime-trusted-base.ps1
.\tools\test-submit-contribution.ps1
.\launcher\tests\run_tests.ps1
```

最近一次完整 Runtime Lane C 复跑为 **11/11 个入口 exit 0**：其中十个会输出 scalar 计数的套件合计 **400** 项，`test-runtime-entry-guardrails.ps1` 另报告 `scripts=3 / unsafeCandidateCases=3`，不把异构摘要强行折算成单一 `x/x` 断言数。`test-resolve-runtime-trusted-base.ps1` 是单列 supplemental，当前 **9/9**，不计入 11 个入口或 400。bootstrap `-VerifyOnly` 与 build environment `RuntimePublish` 均 exit **0**。这些只证明 runtime/admission 守门回归，本身不产生 candidate identity、runtime proof 或 promotion；功能与端到端回归证据统一维护在 [测试指南](../agentsDoc/testing-guide.md)，不在本文复制。

- candidate：`tools/verify-runtime-bundle-v2.ps1 -DeploymentRoot <candidate>`；只审字节闭包才加 `-IntegrityOnly`。
- 提交态由 classifier 按 manifest header 分流；手工 v2 复核用 `tools/verify-runtime-bundle-v2.ps1 -Staged` + `tools/verify-runtime-consensus.ps1 -Staged`。
- `artifactSourceHash` / `producerRecipeHash` / `toolchainLockHash` 不等：构建身份不同，不比较闭包。
- build identity 相同而 `payloadClosureHash` 不同：真实可复现性失败或 signer equivocation，停止 promotion 并逐文件定位，不任选其一。
- `policyHash` 不同但 build identity/closure 相同：建立新 request、重新跑政策 receipt；允许复用已验证 CAS，不重编 payload。
- native 源码变化且部署闭包未变：Audit 应以 `source-ahead` 成功；不要为了“追平源码”在每次 push 后抢构建锁、改 manifest 或立即 promotion。
- 部署闭包变化但无匹配 v2 consensus：事后 Audit 必须失败；不要靠重跑 Actions、手改 hash 或补文档把红灯洗绿。

升级 SDK/编译器是显式维护事件：人工核对官方来源，更新 lock 与 bootstrapper hash，在不同故障域重建并取得新 quorum，同轮更新本文与 Launcher 文档。不得关闭 hash 校验来迁就某台机器的自动 servicing。
