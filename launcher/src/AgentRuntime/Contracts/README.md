# AgentRuntime Contracts（C# 映射）

本目录是 CF7 Agent Runtime `1.0` 预发布 wire contract 的 C# 解析、规范化与验证实现。F7 于 2026-07-31 source freeze 为 C1 `dd84230a1d262c6478591cae2d11051b7a8aa7b1`；一期 ADR 文件名保留首次冻结日 `2026-07-30`，避免 canonical 路径与链接漂移。本 documentation-only D1 只记录其 immutable parent C1；D1 自身 hash 要到提交后才产生，不能自引用。JSON Schema、method/reason registry 与 vectors 的唯一 wire 真源仍在 [`launcher/contracts/agent-runtime/v1/`](../../../contracts/agent-runtime/v1/README.md)，本目录不得另造兼容字段或第二套协议。

协议仍未有 promoted v1 consumer。截至本 D1，C1 尚未取得 `candidate_executed`、`e2e_verified` 或 `promoted`，正式 runtime 未改变。任何 wire-breaking 变更必须把 schema、registry、生成物、这些 C# models/validator、CLI/MCP client、fixture、harness 与 canonical docs 在同一提交原子升级；不得以 nullable/default/忽略未知字段维持宽旧行为。

## F7 固定不变量

- 认证上下文只来自受保护 rendezvous、credential proof 与 pipe peer。`PipeOptions.CurrentUserOnly` 只证明当前用户；Gateway 仍要验证独立 OS peer token 的 Windows session、elevation/integrity 与 exact client process incarnation。
- session/surface identity 同时绑定可执行路径、PID、进程启动时间、HWND/owner 关系、lifecycle/attempt/surface/document/panel generation。`activePanel` 精确为 `{name,instanceId,targetId}`；Web 导航开始立即推进 document generation。
- `window.state` 是只读查询；`window.activate` 是独立 action，production performer 在 dispatch 前后都复核 session/lifecycle、attempt、target、HWND/owner、surface/coordinate/focus/modal binding。
- `business_modal` 保留 wire enum 位，但 production selector 必须得到空 scope。内部 `BusinessModal` 是 human-only security surface，不进入 discover/capture/input。
- `trace.export` 只允许显式 enrolled developer 的 `DeveloperInteractive` 会话，同时满足 `trace.export + observation.export`、精确 `consentPurpose`、同 principal/session grant 的 `data.export + allowExport` 与 consent receipt。Runtime-owned exporter 最多写 8 MiB JSONL，以 owner staging → 共同 process-incarnation pending marker 取得所有权并在同目录原子改名；可控失败只清理 owned files，删除受阻时保留 marker 供 definitely-dead-owner/same-process-inactive janitor 重试。marker 删除是发布线性化点，不能把单文件 move 表述为 audit/filesystem 跨资源“任一失败零残留”，也不能把 marker 删除前写入的单条 `trace_export_completed` 当作发布证明；后续同 artifact 的 failed fact 是补偿记录。wire 只返回 artifact ID/文件名，不返回路径。
- Hair 六方法绑定唯一 DomainTransaction WebOverlay target。`expectedCurrentHair` CAS、focused runner、零 replay 与 close/reopen 隔离不可放宽。unknown receipt 不带 token；token 只在同一 `HairAppearanceModifierTransaction` 实例的 lifecycle-local escrow 中，由 exact connection/principal/session/lifecycle/target 的权威 reconcile 按 transaction/previewHash/expiry 单次消费。不同连接、新 transaction 或 Core restart 永不交付。
- Launcher-owned consent prompt 必须绑定 exact Launcher HWND/owner incarnation 与 prompt instance；foreign input、第二 security surface 或 binding 漂移均 fail closed。
- `LeaseDescriptor.purpose` 必填，`renewAfter` 可选；shutdown descriptor 必须省略 `renewAfter`。`session.shutdown` 只允许 `DeveloperInteractive` / `UnattendedTest`，其 exact scope 只解析一个当前 `RuntimeOwned` Launcher target；这是 scope cardinality，不是宣称 session 全局只有一个 Launcher target。专用 lease 的唯一 capability/operation 为 `session.shutdown`、TTL≤30 秒、one action、no renew。`PlayerAssist` 只有语法有效、已认证、通过全部先行授权门并到达 issuance policy 的 acquire 才返回 `consent_required`；畸形、越权或直接 action 可更早失败。
- renew/release 只解析 exact active lease 与 exact client/principal owner；terminal tombstone、owner mismatch 或其他 lease 不能清理当前 owner。live table 只保留 active / reservation-draining lease，terminal tombstone 为 256 项 FIFO。committed-shutdown session latch 独立保留最多 64 个 exact session ID 且不驱逐；再出现不同 session 时升级为 global fail-closed。tombstone eviction 永不重新开放写入。
- 相同 action/idempotency identity 与 canonical payload 必须 replay exact retained `ContractReceipt`，包括 `DeliveryUnknown` terminal `Unknown`，不得 redispatch、追加第二组通用 action audit 或二次合成 receipt；canonical payload 或双索引 identity 冲突继续 fail closed。
- 同 session execution reservation 只归成功 consume 的 action owner，并跨 consume 保持到 JSON 与可选 binary 等全部 response frames 完成 `WriteAsync` commit 或显式 abort；失败 consume 从未拥有 reservation，不能释放、abort 或覆盖其他 owner。SafeExit 只先 arm；首个成功字节前必须先 claim exact terminal-audit identity，再 claim lease write ownership 与 human-input sequence fence。第二道失败时保持零成功字节，把 audit pending 补偿为 `action_response_unknown`、收束 unknown/manual 并同步确认 SafeExit abort。
- 全部 required frames 完成 `WriteAsync` 后才是 server-side delivery commit，不代表 peer acknowledgment：正常追加唯一 `action_response_written` 并 continue，后置 Flush 失败不回滚。post-write audit append 失败同样不回滚；它只能标记 continuity lost、移除 pending 并以 `truncated` segment 收束，后续 dispose 不得合成 Unknown。delivery-unknown receipt 的 `EvidenceKind` 固定为 `ReconciliationRequired`。generic audit append 必须拒绝 reserved `action_response_written` / `action_response_unknown`，只能由 response-delivery state machine claim/append。完整写前失败才收束 unknown/manual。
- external/human input 抢占所有尚未取得 delivery-write ownership 的 active / execution-pending / delivery-pending / queued action。一旦 shutdown 在 byte 1 前取得该 ownership，普通 revoke/human override 不得回滚，terminal outcome 只归 response completion state machine。依赖 host 的 abort callback 返回 false 或抛异常时保留 session reservation 并标记 continuity lost；post-write commit callback 返回 false 或抛异常时不回滚已完成 delivery、标记 continuity lost，且 SafeExit continuation 不再有保证。
- 每个 action 的唯一绝对 deadline 从完整 CF7A request frame 收到时开始，覆盖 UTF-8/JSON/参数解析、capability/admission、scheduler、performer、response writer lock 与 JSON/可选 binary 的全部 `WriteAsync`；任何阶段不得重置。

受信无人值守 runner 不接受 client 自报身份：只有 strict verifier 验证过完整 manifest inventory、selected payload、build identity 与 payload closure 后启动的 exact `Core.exe --agent-unattended-runner` 才是安全边界。Node/PowerShell 只是调用包装。credential acquisition 使用内部固定 30 秒 monotonic deadline，与 bootstrap/session document 的 10 分钟 maximum lifetime 独立，caller 无调参入口。Host 每次 periodic full surface refresh（默认 250 ms）都重试完整 observe/publish/enforce；`_unattendedBindingSync` 保证 single-flight，stopping fence 与 teardown barrier 禁止排队 refresh 穿过已释放依赖。退出 observation 固定 `allowValidatedFlashKeyframeFallback=false` 且只接受 exact target 的 `SourceLayer.Launcher` frame；shutdown lease 与 terminal receipt 必须逐字段严格匹配。完整严格 receipt 后还必须在 10 秒内观察同一 exact owned child 以 exit code 0 正常退出；timeout、非零退出或 forced kill 均失败，不得报告 E2E success。只有 adapter exit 0、已观察严格 shutdown receipt、exact owned Guardian clean exit 且无 forced recovery 时才在 stderr 写一条前缀精确为 `cf7-trusted-runner-evidence: ` 的成功证据；UTF-8 总长≤16 KiB，字段只含 `cf7.agent_runtime.trusted_unattended_completion.v1` schema、`runtimeMode`、`processPath`、`coreSha256`、`buildIdentity`、`payloadClosure`、`guardianProcessId` 与 strict `terminalReceipt`，不得含 credential/ticket/nonce secret，stdout 只承载协议。MCP active call 的同一绝对 30 秒预算覆盖 handler 到 response copy/flush，idle protocol output 另有逐次 30 秒预算；timeout 关闭 authenticated pipe、零伪 response 并进入 bounded exact-child recovery，不能保留该 lifecycle 重连。

## 主要文件

- `AgentProtocolV1.cs` / `AgentJsonRpcV1.cs`：CF7A frame 与严格 JSON-RPC profile。
- `AgentContractModels.cs` / `AgentMethodParametersV1.cs`：wire DTO 与逐 method 参数闭集。
- `AgentContractRegistries.cs`：method、capability 与 reason registry 的加载/对照。
- `AgentContractValidator.cs`：身份、字段、operation 与条件必填校验。
- `CanonicalJsonV1.cs`：idempotency、intent 与 receipt 使用的稳定 canonical JSON。

## 验证与证据边界

从仓库根运行：

```powershell
chcp.com 65001 | Out-Null
launcher/tests/run_tests.ps1
node --test tools/cf7-agent/tests
node tools/validate-doc-governance.js
git diff --check
```

F7 fresh source evidence 为 Launcher 全树 **2678 passed + 3 explicit opt-in skipped / 2681 total，0 fail**、仓库 SDK resolver **7/7** 并精确解析 `.NET SDK 10.0.300`、Node client **37/37**、TrustedRunner 过滤 **48/48**。这些门只证明 C1 `dd84230a1d262c6478591cae2d11051b7a8aa7b1` 的 source implementation；C1 尚未达到 `candidate_executed`、`e2e_verified` 或 `promoted`。对应 candidate execution、真实跨进程/窗口 E2E、物理双屏、v2 promotion 与标准入口复核必须按 [`agentsDoc/testing-guide.md`](../../../../agentsDoc/testing-guide.md) 分层取证；正式 runtime 未改变，也不得继承另一 source identity 的状态。
