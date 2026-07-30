# 技术栈保留 / 收敛评估

**文档角色**：技术栈决策 canonical doc。  
**最后核对代码基线**（全局技术栈评估的历史锚点）：commit `9f8f0c225`（2026-04-20）；它不是下文 §3 的 F7 source baseline。

## 1. 总结结论

当前不建议发起“代码层全栈重写”。  
建议发起的是：**文档与治理全量翻新 + 技术栈收敛路线图**。

原因不是“现有技术栈很优雅”，而是：

- AS2 / Flash CS6 仍是物理约束，不能假装不存在
- C# Guardian + WebView2 已经成为运行时中枢，重写代价高、回归面大
- TypeScript / Rust / PowerShell 目前更多是受控边界件，不是失控主栈
- 当前最大问题是 **认知失真和治理缺位**，而不是“语言数量本身”

## 2. 三段式矩阵

### Hard Keep

| 栈 / 组件 | 当前角色 | 保留理由 |
|----------|----------|----------|
| AS2 / Flash CS6 | 核心游戏逻辑、资产编译 | 无现实替代链路，且游戏主体绑定该运行时 |
| C# Guardian Launcher | 宿主、启动链、总线、音频、存档决议 | 已是运行时中枢，不再是可随意替换的外设 |
| WebView2 overlay / Panel 系统 | 启动引导、运行态 UI、小游戏 | 已承载 UI 迁移成果，回退成本高 |
| 本地通信总线（XMLSocket / HTTP / TaskRegistry） | Flash ↔ Host 的既有契约 | 现有运行时集成依赖明确，替换风险高 |

### Contain

| 栈 / 组件 | 当前角色 | 收敛原则 |
|----------|----------|----------|
| TypeScript / ClearScript V8 | Launcher 内嵌脚本与构建工具链 | 只服务于 `launcher/`，不扩展成新的独立应用层 |
| Rust `sol_parser` | 单一 native 解析边界件 | 保持单一职责，不把 Rust 扩成新的业务主栈 |
| PowerShell 自动化 | Windows 启动、Flash smoke、诊断 | 保留，但避免把核心业务逻辑沉到脚本层 |
| Node 运行时 | TypeScript 构建、QA、developer JSONL/MCP 客户端与便利包装 | 只作为工具/适配运行时；无人值守安全身份、session truth、策略与执行器均在受验证的 C# Core/Host，不把 Node 或 PowerShell 叙述为生产 authority |

### Retire / Stop Expanding

| 旧概念 / 旧叙述 | 当前处理 |
|----------------|----------|
| “项目就是单纯的 AS2 + Flash CS6 技术栈” | 停止作为顶层项目概述使用 |
| “当前运行态依赖 Node.js 本地服务器” | 停止扩散，仅保留历史语境说明 |
| 与当前架构不符的旧版本 / 旧路径 / 旧测试说明 | 逐步清理并交给治理巡检拦截 |
| 在入口文档重复复制子系统深文档 | 停止扩张，改为链接 canonical doc |

## 3. CF7 Agent Runtime / Wings 一期边界

| 边界 | F7 source truth | 收敛原则与外部缺口 |
|------|-----------------|--------------------|
| CF7 Agent Runtime / Wings Network 一期 | §3 的 F7 source baseline 是最终 C1 `dd84230a1d262c6478591cae2d11051b7a8aa7b1`（2026-07-31），包含 CF7A v1 当前用户命名管道、受 ACL 保护的 rendezvous、精确进程/HWND/session registry、观察 grant、独占 write lease、WGC/guarded input、结构化 action/receipt/reconcile、purpose-scoped audit，以及使用共同 owner pending marker 与同目录 atomic move 的 8 MiB Runtime-owned JSONL trace export；Wings Shell/Persona/offline backend、`window.activate`、Hair transaction 与 F7 shutdown/runner 单终态闭包均已接入同一 Host pipeline | 技术底座继续留在现役 C# Launcher；`CurrentUserOnly` 只保证当前用户，Host 仍独立验证 peer token、Windows session 与 elevation。standard normal 与 privileged legacy HTTP 互斥；无人值守安全入口是选中并验证的 Core 二进制 `--agent-unattended-runner`，Node/PowerShell 只作便利包装。协议 `1.0` 仍是 pre-release，wire-breaking 必须原子升级 server/schema/clients。单文件 atomic move 不构成 filesystem/audit 跨资源事务。source frozen 不等于 candidate 执行、实机 E2E、v2 promotion 或标准入口验收；物理双屏矩阵和正式发布仍是外部门，范围见 [F7 一期范围冻结 ADR](CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md) |

一期 ADR 文件名保留首次冻结日 `2026-07-30`，避免 canonical 路径与链接漂移。当前 documentation-only D1 只引用父 C1 `dd84230a1d262c6478591cae2d11051b7a8aa7b1`；D1 不能在自身内容中记录尚未知的自身 commit hash。

F7 的 shutdown 边界不可下沉到脚本层：`LeaseDescriptor.purpose` 必填、`renewAfter` 可选且 shutdown 必须省略；只允许 `DeveloperInteractive` / `UnattendedTest`，请求的 exact scope 恰含当前一个 `RuntimeOwned` Launcher target（不推导 session 全局 singleton），并固定 `session.shutdown`、TTL≤30 秒、one action、no renew。lease 只将 active/执行中/待交付记录保持 live；terminal tombstone FIFO 256、committed-session latch 64，后者溢出即全局 fail-closed，eviction 不得重开写。renew/release cleanup 只属于 exact active owner。成功 consume 的 owner 持有 reservation 到全部 frames 完成或显式 abort；abort false 保留 reservation 并丢失 continuity，完整写后 commit false 不回滚字节并丢失 continuity。单一 action deadline 从完整 request frame 收到时开始，覆盖 parse/admission/scheduler/performer/writer lock/全部 frame `WriteAsync`。

SafeExit 只先 arm；首字节前先 claim reserved audit identity，再 claim lease delivery ownership 与 human-input sequence fence。external input 撤销尚未 write-owned 的 active / execution-pending / delivery-pending / queued 工作；ownership 成功后 human override 不得回滚，terminal 只由 completion state machine 收束。`action_response_written/unknown` 禁止 generic append，DeliveryUnknown 固定 `ReconciliationRequired`；ledger replay 原样返回 retained `ContractReceipt`（含 Unknown）。全部 frame 的 `WriteAsync` 只表示 server disposition，不是 peer ack；Flush、post-write audit 或 commit failure（包括 callback 返回 false 或抛异常）均不回滚字节。

受信 runner 在每次完整/周期 surface refresh 重试 credential publication，以 single-flight 和 teardown barrier 隔离 dispose；Core 内部使用 caller 不可调的单调 30 秒 credential-acquisition 上限，独立于最长 10 分钟 bootstrap request/session。stdout 只承载 JSONL/MCP protocol 且无秘密；只有 adapter=0、strict receipt、exact child exit 0 且无 forced recovery 时，stderr 才输出一行 ≤16 KiB、只含 schema/runtime/process/Core hash/build identity/payload closure/PID/terminal receipt 的非秘密证据。

F7 fresh source evidence 为 Launcher 全树 **2678 passed + 3 explicit opt-in skipped / 2681 total，0 fail**、SDK resolver **7/7**（精确 `.NET SDK 10.0.300`）、Node client **37/37**、TrustedRunner 过滤 **48/48**。exact C1 tree 的 production policy **26/26** 已达到 `candidate_built / NOT_DEPLOYED`（identity `F67F1054E7DD19600138C3196D0798CFA487701CB7143C4DDFD2DC426D26E372` / closure `3C2CA3E6E935BF23A061228ED3D9BDA3823E81186057E8C86118FAD5C7CEBF0D`）；严格入口在当前无前台会话按凭据门失败关闭且无 completion evidence，故未达到 `candidate_executed`、`e2e_verified` 或 `promoted`，正式 runtime 保持不变。

## 4. 为什么不是现在重写

### 不划算

- 需要跨越 Flash 资产、AS2 逻辑、启动链、总线、UI、存档决议等多个边界
- 回归面覆盖游戏行为、启动行为、工具链、数据兼容性与验证基建
- 在没有先收敛文档与边界的前提下，重写只会把认知混乱转移到新栈

### 当前真正该做的

- 先把多栈现实文档化
- 先把 canonical doc 和验证矩阵固定下来
- 先停止旧叙述继续污染入口文档
- 先让“哪一层负责什么”变得可执行

## 5. 默认路线图

### Phase 1：文档 truth restoration

- 重写顶层入口与深文档
- 明确 canonical doc 与职责边界
- 引入文档基线与巡检脚本

### Phase 2：边界收敛

- 停止旧入口、旧叙述、旧协议继续扩散
- 把子系统细节压回自己的 source of truth
- 让验证入口与任务子栈对齐

### Phase 3：受控演进

- 只在收益明确时做 containment 级收敛
- 默认优先“小边界替换”而不是“全栈替换”
- 任何新的技术栈引入都必须先说明：它服务哪个既有边界，如何验证，如何被文档接纳

## 6. 决策默认值

- 默认保留现有核心多栈架构
- 默认优先治理认知复杂度，而不是减少语言数量本身
- 默认把 Node / Rust / PowerShell 视为受控边界件
- 默认不把“代码层全栈重写”作为后续工程的前提条件
