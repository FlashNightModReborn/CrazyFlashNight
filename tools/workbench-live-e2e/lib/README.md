# 双栏工作台 live E2E 共享证据原语

> **状态：FROZEN-v2 / GO（runtime-module-journal；其余准入 API v1，2026-08-04）**
> 历史审计痕迹保留：前两轮终审先后 Reopened bootstrap own `loaded` 吞写 accessor、离线 resolver 只保存 `_resolveFilename` 却受动态 `_findPath` 影响，以及 artifact `sealedAt` 未与 seal checkpoint 重复标签精确绑定的问题。第三版 v2 已补 descriptor、完整 resolver machinery、隔离 path cache 与重复时间标签合同，并经不继承旧结论的独立只读复核取得 GO。该 GO 只冻结共享准入 API；Equipment Tuning、KShop、Crafting、NPC Shop 的 opener、命令白名单、selector、三元组、token、postcondition、真实输入和业务 verdict 仍必须由各自 runner/verifier 与 live receipt 独立证明。

## 1. 冻结边界

下列模块组成冻结准入面。前五项导出 `API_VERSION === "FROZEN-v1"`；`runtime-module-journal.js` 因修正 bootstrap 的真实异步生命周期合同，导出已复核的 `API_VERSION === "FROZEN-v2"`：

- `evidence-artifact.js`：canonical JSON、SHA-256、实体文件/目录、owned capture、连续记录证据；
- `control-contract.js`：request/ack、TTL、exact control set、可信 capability 与一次性授权；
- `runtime-guard.js`：candidate-before-mutation、隔离候选 identity、CDP 端口/进程/页面绑定、重启 identity；
- `clone-save-guard.js`：`cf7_agent_*` 专用槽 JSON/SOL 全量集合、PID+process-start 独占锁、备份、写前恢复记录、硬崩溃 fail-closed、准备/释放；
- `launcher-observation.js`：认证 legacy HTTP 生命周期观察、完整日志终端边界、archive+磁盘、启动/退出残留、fresh restart；
- `runtime-module-journal.js`（`FROZEN-v2`）：显式 module/artifact manifest、bootstrap preexisting cache 与 `Module.loaded` 生命周期、CommonJS 实际加载 journal、phase seal 与 terminal reverify。

`source-fingerprint.js` 与 `source-safety-gate.js` **均不在冻结准入面内**。前者固定导出 `ADMISSION_STATUS === "DIAGNOSTIC_ONLY"`，后者只保留为旧 KShop 工件的识别标记并导出 `RETIRED_DIAGNOSTIC_ONLY`；二者产生的工件都固定 `admissionEligible:false`。历史 KShop adapter 曾把 retired gate 当作必需准入证据且没有向新 CDP API 提供独立 trusted expectations，因此当时为 `NOT_ADMITTED`；该结论与旧 `50/50` 均保留为 superseded 历史。当前 KShop canonical `bootstrap.js` 已不再加载或消费这两个诊断模块，改为显式 module journal、production/actual-loaded closure 与独立 trusted expectations，离线 `--check` 为 `ADMITTED`；runner/verifier/self-test 直达入口继续 `NOT_ADMITTED`。按 2026-08-05 本地单机比例裁决，KShop current-tree 完整 feature Gate 通过即可关闭其 A3 离线责任，不再等待 KShop live mutation；任何正则/词法命中、未命中或递归 closure 都不得单独作为 admission 证明，也不得替代实际 module journal 与领域静态审阅。

冻结含义是：A3 各领域可以依赖已获 GO 的函数名、参数职责、返回证据和 fail-closed 语义；如需不兼容修改必须升对应模块的新版本，不能在既有版本下静默放宽。journal v2 的 manifest、checkpoint 与 artifact schema 均为 v2；v1 journal 工件不得冒充 v2 准入证据。共享冻结不替代 consumer 自身的显式 manifest、离线 Gate、真实旅程与独立终审。

## 2. 强制执行顺序

每条 live 旅程必须由领域 runner 显式编排以下顺序；共享层不会替业务 runner 推断步骤：

1. 以固定 `node bootstrap.js` 形态启动单进程 CommonJS runner；bootstrap 的首个 repo require 必须是 `runtime-module-journal`，且安装时 executing `require.main` 必须仍是同一 cache-bound `Module`、`loaded === false`；先建立 explicit module/artifact manifest，再安装 journal；`--require journal main.js`、直接 main、ESM 与 worker/子 Node 均不在该准入形态内；
2. 确认没有 Launcher/Core 残留，再通过 `resolveCandidateIdentityBeforeMutation` 解析并验证 isolated candidate；只有回调收到已冻结 identity 后才允许准备克隆；
3. 对 exact `cf7_agent_*` 目标取得独占锁，稳定捕获 seed/target JSON+owned SOL 集合，再用 `prepareDedicatedClone` 备份、清 SOL、写前重验 target JSON、原子写 JSON；`prepared_pending_release` durable record 必须贯穿后续 live；
4. 启动 runner-owned candidate/CDP，取得认证 legacy HTTP session，并用实际 PID、可执行路径、start ticks、argv 证明它就是该 lifecycle；
5. 将一次完整 `/logs` 尾部固化为 terminal boundary，再执行领域 opener/preview/commit；任何遗漏、重置、尾窗缺口或多余相关记录都由领域 verifier 拒绝；
6. 用 fresh boundary 之后唯一 archive 行、调用方声明的精确保存顺序及当前磁盘 JSON 原始 SHA-256/bytes/字符数共同证明保存；
7. shutdown 后连续观测全局 Launcher/Core PID 集合严格为空，并证明当前 PID、candidate path、HTTP/socket/CDP 端口、ports rendezvous 与 credential 文件均无残留；
8. fresh restart 必须保持 candidate identity/closure 不变，同时 PID、attempt、process start、credential lifecycle 均更新；读回后再次安全退出；
9. 释放 clone 锁前重验只读 seed 全量集合、target 结束集合与备份；只有全部终验成功，`releaseDedicatedClone` 才能私有删除 exact lock（此刻 durable record 仍阻断 acquire），随后按 exact digest 删除 `prepared_pending_release` record，二者均确认 absent 后才返回 release evidence；module journal 再依次完成声明 phase checkpoint、SEALED（hook 保持且拒绝后续 load）、terminal reverify exact manifest/cache/loaded set，且每个 checkpoint/seal 都记录同一 bootstrap `Module.loaded` 的布尔状态并只允许 `false → true`；同步主模块可在 terminal restore 前保持 `false`，真实异步续程应观测为 `true`，最后才恢复原 hook 并留下 digest。

任一步失败都不得继续提交、重试业务写或悄悄重播种。若目标变更已经开始，`clone-save-guard` 始终留下 `mutation_in_progress`、`prepared_pending_release` 或 `manual_recovery_required` durable record；普通新 run 会被阻断。公共 `releaseCloneLock` 只允许释放 mutation 前且无 recovery 的普通锁，或已完成 exact manual recovery clearance 的 recovery 锁。进程硬崩溃遗留的旧锁不会被普通 acquire 或 `recoveryMode` 自动接管；`inspectCloneLock` 不创建目录，只返回 exact clone lock、recovery、owner PID/process-start 和当前 OS 观测，不授予删除权。

生产离线处置统一走固定根 CLI，并明确限定为本机单操作者、单恢复进程；同时运行多个处置 CLI 不受支持，也不是本地单机验收目标。`clearAbandonedNoRecoveryCloneLock` 只处理 recovery 已不存在、owner exact absent 的普通孤儿锁；`restoreAbandonedCloneFromRecovery` 在全部备份、APPDATA、runDir、seed 与 target 稳定复核后，原子恢复 `targetBefore` 并删除仅属于当前 dedicated slot 的多余 JSON/SOL，随后按“清 recovery → 清旧 clone lock”解阻。`prepared_pending_release` 的 lock-absent 清理失败只允许显式 `recordOnly`；其余状态必须保留并匹配旧 clone lock。每次 mutation 都要求调用方给出 exact lock/recovery digest 与 status，并在关键点证明 Launcher/Core exact zero。

## 3. 冻结 API

### `evidence-artifact.js`

- `canonicalJson(value)`、`sha256Bytes/Text/File(value)`：确定性序列化与 SHA-256；
- `assertExactDirectory(path, phase)`、`readExactRegularFile(path, options)`：拒绝缺失、非实体文件/目录和 reparse/symlink；
- `assertOwnedRunDirectory(root, runDir, ownedBaseRelative, phase)`、`ensureExactChildDirectory(...)`：`ownedBaseRelative` 必须是 root 内严格闭合、非空、无 `.`/`..`/drive/absolute 的实体目录，runDir 必须严格位于该 base 内；
- `stageOwnedCapture(options)` / `verifyOwnedCapture(options)`：只接受实体 PNG/JPEG/WebP/BMP 并在 owned run 内重算 bytes/hash；
- `canonicalRecordsDigest(records)` / `verifyCanonicalRecords(options)`：验证严格递增、边界闭合的记录切片。

### `control-contract.js`

- `validateControlRequest(request, options)` / `validateControlAck(ack, request, options)`；
- `verifyControlExchange(options)` / `assertExactControlSet(options)`：绑定 schema、requestId、step、transport、TTL、capture 与 exact request/ack 数量；
- `verifyCapabilityDecision(options)`：fallback 只能依赖调用方明确列出的可信、非 operator evidence；
- `verifyOneShotAuthorization(options)`：一份决策只允许被一个 exact request 与一个 exact ack 消费。

这些是中立 envelope；领域 runner 仍须绑定 action、browser sequence、Web callId、AS2 fid/callId、Host 日志窗口、token scope 与 postcondition。

### `runtime-guard.js`

- `resolveCandidateIdentityBeforeMutation({root,candidateRoot,assertNoRuntime,prepareClone})`：只使用 canonical `runtime-process-identity` 解析器，严格执行 no-runtime → 实体 manifest/metadata/Core bytes 校验 → clone callback；不接受 runner 注入 resolver；
- `validateCandidateIdentity(identity, candidateRoot)` / `publicCandidateIdentity(identity)`；
- `allocateLoopbackCdpPort()` / `withWebViewDebugEnvironment(port, callback)`：只为 runner 启动范围设置 exact debug port；
- `attestLoopbackCdpEndpoint(options)` / `assertRuntimeCdpBinding(binding, identity, trustedExpectations)`：绑定实际 listener、Launcher ancestry、exact port/user-data root；CDP client 固定连接 `127.0.0.1`，因此只对同端口 exact IPv4 listener 做唯一性与进程身份判定，不把另一个 WebView2 环境占用的 `::1` sibling 合并成同一 endpoint；调用方必须独立传入 trusted production URL/origin/user-data root/executable name，可选传入 exact executable path 与已知页面 content hash/bytes，API 不得从 binding 反填 expectation；
- `assertFreshRestartIdentity(options)` / `assertByteInvariant(before,end,options)`。

CDP 只承担被动观察和证据捕获。若 trusted expectations 未提供已知 content hash/bytes，共享层只证明“该受信页面 identity 下观察到一个 opaque content digest”，不证明该 digest 是 canonical 页面字节；若只提供 executable name 而未提供 exact path，也只证明 basename+Launcher ancestry，不证明 WebView 二进制身份。共享 API 不暴露页面、浏览器或输入对象，也不提供业务 opener。

### `clone-save-guard.js`

- `captureSlotArtifactSet({root,slot,appData,requireJson?})` / `captureStableSlotArtifactSet({...timing})`：把 exact APPDATA root 连同 JSON 与该 slot 所有 owned SOL 的 raw SHA-256、bytes、realpath 与集合 hash 一起绑定；APPDATA 缺失时失败，不把“无法枚举”写成空集合；
- `acquireCloneLock({root,slot,runDir,ownedBaseRelative,recoveryMode?})`、`assertCloneLockOwned(...)`、`releaseCloneLock(lock)`、`withCloneLock(options, callback)`：锁记录绑定 exact handle、owner PID/process-start；任何已有锁都会使普通与 recovery-mode acquire fail-closed；公共 release 不得删除任何已开始 mutation 或仍有 durable record 的锁；
- `inspectCloneLock({root,slot})`：真正只读且不初始化目录；返回 exact clone lock、recovery 的 present/status/digest，并附 owner identity、OS 当前 start identity 与 `owner_active/owner_absent/pid_reused`；它不是删除或并发接管 API；
- `prepareDedicatedClone({root,appData,runDir,ownedBaseRelative,seedSlot,targetSlot,lock,validateSeed?,transformJson?,transformId?,validateTarget?})`：所有业务解析/校验先于 mutation；旧 target 全量备份和 write-ahead recovery 先于 SOL 删除/JSON 替换；replace 前要求现存 JSON 仍与 `targetBefore` exact hash/bytes/path 相同，原先 absent 则仍须 absent；成功后把 record 原子转为 `prepared_pending_release` 而非清除；
- `verifyClonePreparation({preparation,appData,verifyCurrentSeed?})` / `releaseDedicatedClone({preparation,lock,appData})`；
- `clearAbandonedNoRecoveryCloneLock({root,slot,expectedLockSha256,assertNoRuntime})` / `restoreAbandonedCloneFromRecovery({root,appData,slot,expectedRecoveryStatus,expectedRecoveryRecordSha256,expectedLockSha256?,recordOnly,assertNoRuntime})`：唯一生产离线处置原语；固定路径、摘要、owner 与 no-runtime 任一不符都保留现场；
- `readCloneRecovery(root,slot,allowMissing)` / `clearCloneRecoveryAfterRestore(...)` / `clearPreparedCloneRecoveryAfterOfflineRestore(...)`：保留为已恢复状态的低层验证/兼容原语，不是生产 operator 入口，不替代上述恢复事务与 receipt；
- `verifyArtifactSet`、`verifyCurrentSlotArtifactSet`、`assertArtifactSetInvariant`、`verifyBackupManifest`；
- `assertSourceSlot` 接受合法只读 seed；`assertDedicatedSlot` 只接受 `cf7_agent_*` mutation target。

共享层只保证字节、集合、锁和恢复原语；seed/target 的业务 JSON schema 与变换语义仍由领域 adapter 提供。

### `launcher-observation.js`

- `openAuthenticatedLegacyHttpSession(options)` / `waitForAuthenticatedLegacyHttp(options)`：读取 PID-bound credential，只开放 `GET status`、`agent_control` 的 `status/start/revealOk/cancel/shutdown`、固定 `AGENT_ENTER_COMMAND`、完整日志尾和 runtime identity 验证；
- `attestAuthenticatedLauncherProcess({root,sessionEvidence,runtimeIdentity,observeProcess?})`：用实际 PID/path/start ticks/argv 证明 `--project-root` 与 `--legacy-http-automation`，并证明未走 Agent Runtime admission；
- `normalizeLogSnapshot(payload,limit,capturedAt,sessionEvidence)`、`verifyLogSnapshot`、`createTerminalLogBoundary`、`verifyTerminalLogBoundary`、`recordsAfterTerminalBoundary`：snapshot/boundary 绑定 exact authenticated session digest、lifecycle、PID/start identity；final 必须同 lifecycle，且非空 boundary 必须保留至少一条可见 overlap，全部可见交集逐 lineNumber/text exact，因 reset/catch-up 或 2000 行尾窗而无 overlap 一律失败；“最后一条相关日志”不能充当边界；
- `verifyArchiveSaveEvidence({root,slot,boundary,snapshot,requiredOrder,diskEvidence?})` / `captureDiskSaveEvidence(options)`：唯一 archive、精确保存顺序、磁盘 bytes/hash/字符数；
- `startLauncherCandidate(options)`、`waitForAgentControl(session,options)`、`waitForRuntimeReady(session,options)`；
- `queryLauncherCoreProcesses()` / `assertExclusiveLauncherProcess(processes,authenticatedPid?)`；
- `observeRuntimeResidue(options)` / `waitForCleanResidue(options)` / `assertResidueClean(evidence)`：不仅检查期望 PID/path，还要求观测到的全局 Launcher/Core PID 集合 exact zero；
- `assertFreshAuthenticatedRestart(options)`：在 candidate identity 不漂移之外，要求新 PID、attempt、start ticks、credential file hash 与 lifecycle。

### `runtime-module-journal.js`

- `buildExplicitModuleManifest({root,requiredPhases,builtins,entries})` / `verifyExplicitModuleManifest(...)`：逐文件绑定实体路径、raw hash/bytes、repo/external scope、role、loadable/preexisting；固定 preexisting 只允许 `bootstrap → journal → journal_helper(evidence-artifact)`，外部模块必须使用 `external_*` role；builtin 使用 exact allowlist，`child_process/module/vm/worker_threads` 等必须标记 `high_risk_explicit`；
- `installRuntimeModuleJournal({root,manifest})`：只接受 journal 为 bootstrap 首个 repo require 的 `node bootstrap.js` 进程；安装时 canonical clone + recursive freeze manifest，并从 journal 首次求值时的基线绑定 `Module._load/_resolveFilename/_findPath/_resolveLookupPaths/_nodeModulePaths/_pathCache/_cache/_extensions/globalPaths` 与 parent `path.dirname` 的 own data descriptor、对象/函数/handler identity、extension key set、global path 值和 path-cache null prototype/标准字符串项；同时绑定 exact preexisting cache descriptor/Module identity/parent graph。executing bootstrap 必须精确等于 `require.main`，且 `loaded` 在该同一 `Module` 上始终是 own data descriptor：有 boolean `value`、无 getter/setter，`writable/enumerable/configurable` 均为 `true`；安装初值必须为 `false`，缺失、accessor、非标准 flags、初始 `true`、identity/cache/resolver descriptor 漂移或后续 `true → false` 均 fail-closed；
- controller 只暴露 `checkpoint(phase)`、`seal(phase)`、`reverifyAndRestore()`：每次实际 load 记录 request、cache-bound parent、resolved builtin 或实体 locator、首次 miss/后续 hit、load 前后 hash/bytes；load 前后、checkpoint、seal、restore 都重验完整 resolver machinery；每个 checkpoint/seal 同时记录 resolver machinery digest，并重验 bootstrap own data descriptor、记录其 boolean `value`，在同一 `Module` identity 上只允许 `false → true`；未声明 repo/external/builtin、cache 注入/删除/换对象、非枚举/accessor/symbol cache、resolver/hook/extension 替换、失败 load 均毒化；SEALED 后任何 load 都拒绝；terminal exact coverage 通过后才恢复原 hook；
- `verifyRuntimeModuleJournal({root,manifest,artifact})`：要求 runtime hook 已恢复，重算 manifest 当前字节、artifact/checkpoint digest、resolver machinery digest、event parent/file/builtin 语义、event prefix 与 loaded/cache set、ordered exact phase 和最终 coverage；file event 以记录的 parent 实体路径重算 request→resolved 时，先拒绝 `_resolveFilename/_findPath/_resolveLookupPaths/_nodeModulePaths/_extensions/globalPaths/path.dirname` 的 descriptor/identity 漂移，再把 `_pathCache` 同步替换为私有 null-prototype 空缓存完成解析并精确恢复原 descriptor，因此原 cache 中即使存在格式合法的投毒项也不能左右结果；重封后只换 request/resolved 任一侧均拒绝。verifier 还独立验证 `bootstrapLoadedAtInstall === false`、所有 checkpoint/seal/restore 字段为布尔值且全序列不存在 `true → false`，restore 必须与 seal 精确一致。

该 journal 只证明 **cooperative、单进程、固定 bootstrap、CommonJS 生命周期内经受控 `Module._load` 及 checkpoint/seal/restore 观测点的实际结果**。resolver 基线取自 journal 作为 bootstrap 首个 repo require 被求值的时刻；因此领域 bootstrap 静态审阅仍必须排除在此之前对 Node builtin/primordial 的预污染。基线建立后，所有公开可变 CommonJS resolver helper/表的替换都会拒绝，格式合法的 `_pathCache` 内容也不会进入离线重算；Node 内部不可见 resolver closure、标准 primordial 与验证时同一文件布局/package metadata 仍属于 cooperative 平台前提，布局或 metadata 漂移会安全地 fail-closed。preexisting 只能证明安装时 cache 快照，不能伪造此前历史 request/load；两个观测点之间发生又恢复的瞬时 `loaded`/cache/hook/文件换档仍不可绝对侦测；ESM `import()`、worker isolate、子 Node、`vm/eval`、`process.dlopen` 和恶意代码/动态输入绝对不存在均不在证明范围。领域 adapter 仍须提交显式 manifest、bootstrap 静态审阅、窄 capability 与 receipt。

所有 wall-clock timestamp 只要求是可解析的诊断标签，不承担先后排序或安全证明；系统时钟回拨不应误杀有效工件。唯一重复表达同一时刻的字段必须精确等值，因此 `artifact.sealedAt === artifact.seal.capturedAt`；修改其中任一项后即使重算 artifact digest 也拒绝。journal 的权威事件顺序来自严格递增 `sequence`，checkpoint 前缀来自单调 `eventCount`，生命周期阶段顺序来自 manifest 的 exact `requiredPhases`，seal/restore 一致性来自相位记录和 digest，而不是时间戳大小。

### 非准入诊断：`source-fingerprint.js`

- `buildTransitiveSourceFingerprint({root,phase,entrypoints,externalArtifacts?})`：自动把本模块自身纳入闭包，递归跟随 repo-local literal `require`，记录每个 JS/JSON 的 SHA-256/bytes；
- `verifySourceFingerprint({root,fingerprint})`：以同一 phase/time 重算当前闭包；
- `verifySourceFingerprintPhases({root,fingerprints,requiredPhases})`：要求 exact phase set 且全部 `contentSha256` 相同；
- `scanLiteralRequires(source,filePath)`：保守词法扫描器，仅供诊断与测试。

它能诊断许多 literal require 漂移，也会拒绝若干动态 loader 形态；但诸如拼接 computed `constructor` 的代码生成可逃逸词法扫描，因此所有结果固定 `admissionEligible:false`。该工具不得扫描/批准 `runtime-module-journal`，不得被 KShop 或后续 adapter 当作 admission gate。

即使诊断 closure 在各相位一致，也**不证明真实加载集、行为安全或没有合成输入**，更不替代 runtime journal、领域 source review、窄 API 和 receipt 中的 `physicalInputAttestation:false`。

## 4. 验证与非目标

生产离线检查/处置入口（不接受 `root`、APPDATA、runDir、备份或存档路径参数）：

```powershell
node tools/workbench-live-e2e/lib/offline-clone-recovery.js inspect --slot <cf7_agent_*>
node tools/workbench-live-e2e/lib/offline-clone-recovery.js clear-no-recovery-lock --slot <cf7_agent_*> --expected-lock-sha256 <sha256> --allow-offline-recovery
node tools/workbench-live-e2e/lib/offline-clone-recovery.js restore-from-recovery --slot <cf7_agent_*> --expected-lock-sha256 <sha256> --expected-recovery-sha256 <sha256> --expected-recovery-status <status> --allow-offline-recovery
node tools/workbench-live-e2e/lib/offline-clone-recovery.js restore-record-only --slot <cf7_agent_*> --expected-recovery-sha256 <sha256> --expected-recovery-status prepared_pending_release --allow-offline-recovery
```

`inspect` 只读存档/锁状态但会写一份审计 receipt；三个 mutation mode 每次 fresh 调用 `queryLauncherCoreProcesses()` + `assertExclusiveLauncherProcess(..., null)`，stdout 恰好一个结构化 JSON，成功 receipt 固定落 `tmp/workbench-live-e2e/offline-recovery-receipts/`。未知/重复/混合参数、缺授权、外部路径、active/reused owner、错误摘要或状态均拒绝。生产操作必须一次只运行一个 CLI；并发处置明确不受支持。

离线自测：

```powershell
node tools/workbench-live-e2e/lib/self-test.js
```

当前应报告 `49/49`。除既有 FROZEN API、journal/resolver、capture/control、candidate/session/log/archive/residue/CDP 与 clone prepare/release 对抗矩阵外，还覆盖 strict CLI 参数/授权、active owner、错误摘要、no-runtime 拒绝、owner-absent 无 recovery 孤儿锁、`mutation_in_progress`/`manual_recovery_required`/`prepared_pending_release` 三状态、prepared record-only、JSON+SOL/空前态恢复、备份漂移保留现场、双 WebView2 环境分别占用 IPv4/IPv6 同端口时的 exact IPv4 endpoint 选择及 receipt bytes/hash。旧 `unlinkSync`/`copyFileSync` operator 模拟已由生产恢复 API 回归替代。测试只使用系统临时目录和模拟响应：**不启动 Launcher、不连接游戏、不修改正式或专用真实存档，也不构成 live E2E**。

共享层明确不提供：领域业务 opener/命令、通用 Bridge send、页面/浏览器控制、业务 selector、三元组/token/postcondition 判定、通用 JS sandbox/恶意代码证明、自动重试未知写、自动恢复真实存档或任何“测试通过即部署”的结论。
