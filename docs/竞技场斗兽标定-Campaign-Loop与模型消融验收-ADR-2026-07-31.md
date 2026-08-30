# 竞技场斗兽标定 Campaign Loop、模型消融与人类 PVE 验收 ADR

**文档角色**：斗兽标定 Campaign Loop、模型职责、最小消融、人类 PVE 验收与长时运行恢复的 canonical ADR。真实战斗采样协议、AS2 / C# / Node L0 平台仍以 [竞技场斗兽标定平台 — 架构设计与施工计划](竞技场斗兽标定平台-架构设计-2026-06-29.md) 为准；逐批事实进入 campaign journal，里程碑、临时模型选择与人工结论摘要写入 [竞技场斗兽标定：实验计划与运行日志](竞技场斗兽标定-实验计划与运行日志-2026-07-02.md)。

**状态**：`GATE_E_EQUIVALENCE_LABELS_COMPLETE / OBJECTIVE_PVE_TELEMETRY_UNREPORTED / NOT_FORMALLY_APPLIED`（2026-08-27）。Gate B 的 durable Campaign Supervisor 已验收；Gate C 已取得 A/B/C 三份真实模型输出和一次与模型身份、先验及历史结论隔离的模型盲评；Gate D 又执行 34-run 主动探索与 21-run 确证 shard，使 `candidate-dd65977b16a48a35` 达到 original 15 + swapped 15、0 timeout、0 error、side-swap 已复核。Gate E 的两场正式运行时 PVE 均由维护者标为“1 名 10 级佣兵等效战力”，数值等效标签已进入独立证据链。两场没有补录胜负、残血、承伤、输出等客观遥测，第一场的控制进程还在战斗结束后因 PTY EOF 走了清理性 abort，因此只称 `equivalence_only`，不称完整 PVE telemetry、正式标定落盘、发布或标准入口业务验收。

**最后核对代码基线**：HEAD commit `286e531f214264304e490b122f533e13163b5b83`（2026-08-27）；本节所述 Gate A 增量和证据位于该 HEAD 上的当前工作树，尚未由本文冒称已提交或发布。正式运行身份仍由 runtime manifest 与实际 Core 进程独立核验。

---

## 0. 决策摘要

1. 标定工程采用三层 loop：
   - **L0 固定执行内核**：Campaign 状态、预算、租约、身份、校验、运行、落盘、恢复和失败收束。
   - **L1 标定 loop**：Luna Max 或同级低配额模型执行批次级计划、初判、剪枝提案与异常分流。
   - **L2 优化 loop 的 loop**：Sol 与人类修改方法、验收标准、模型路由和施工优先级。
2. 采用**确定性 Campaign Supervisor + 单一模型经理 + 有界 worker / critic**，不采用多个对等模型共同持有主控权。
3. Campaign Supervisor 是唯一状态权威；所有模型输出都是提案。模型不能直接提交结果、改正式配置、扩权限或把未知结果改写为成功。
4. 首个 provisional profile 为 `Sol manager + Luna executor/preliminary judge`，但模型绑定必须配置化。ADR 决定比较方法，不永久冻结模型赢家。
5. 严格 seed 复现不是前置条件。AS2 内建随机源仍未统一时，seed 只作观测元数据，不作“相同 seed 必然复现”的身份或验收依据。
6. 梯队由连续潜在强度、置信区间和对局图关系派生；不把玩家提交的弱先验强绑到固定区间。Elo 可作实时展示，不作唯一统计真值。
7. 最小消融能力属于生产标定的证据基础；完整通用消融平台不属于首期。首期验收必须完成一次冻结快照的 shadow 比较，但不要求统计上证明永久模型优劣。
8. 人类 PVE 是“怪物组合等效于多少名、多少级人形佣兵”的最终外部验收源之一；冻结的玩家构筑只是有余量的测量载体，玩家等级、能否取胜或怪物原始等级都不能直接代替等效标签。
9. 一星期指**累计 campaign 时间**，不是单进程连续运行。每个 shard 必须短、可中断、可重入，游戏、Launcher 或电脑异常后从已提交事实继续。
10. 当前斗兽无人值守链仍是显式 legacy HTTP automation；不能把 F8 标准 Agent Runtime 的发布状态误写成斗兽业务控制已迁移。未来迁移需要独立的结构化 arena capability 决策，禁止把 `/console` 或任意 AS2 执行口扩入 Agent Runtime。
11. “节约人类时间”是 hard acceptance，不是愿景描述：正常 shard 人工操作必须为 0，日常异常进入异步 exception inbox，只有权限、方法论、正式配置落地或全局事实连续性问题可以进入人工批准路径。
12. 内容开发、Flash 编译和人工游戏会话永远高于 campaign；后台标定只能使用空闲窗口，并须在有界时间内让出 Launcher / Flash / 机器资源。

---

## 1. 背景、问题与目标

### 1.1 当前事实

现役平台已经能：

- 在专用 no-player 竞技场中运行蓝 / 红双方真实 Flash 战斗。
- 由 C# 后台串行执行 manifest 并 append JSONL。
- 由 Node 工具生成 summary、规则 next batch、durable Campaign journal、模型评估/PVE 证据和无人值守报告。
- 使用专用存档、exact 运行身份、有限自动重启、rerun manifest 和逐行 exactly-once commit 处理崩溃与 partial attempt。
- 记录阵型、出生位置、多阶段刷怪和污染状态。
- 以冻结 source/runtime/manifest/decision plan、有界可撤销 idle window、真实 producer/磁盘门和去重 exception inbox 编排 Gate F 短 shard。

本 ADR 发起时的平台仍主要是“单批次执行器 + 规则摘要器”；Gate B–E 已在 2026-08-27 形成真实证据，Gate F0 工程控制面也已实现。2026-08-28 的 v4 campaign 已完成三份 fresh 10-run soak，并在全量保存 16 个 completed shard、1 个 F2 timeout-anomaly shard 和 280 条 durable row；F2 的原向 10/10 finished、换边 5 finished + 5 timeout，runtime/save/shutdown 与 error 门均正常。旧 driver 把纯候选 timeout-rate 当成基础设施失败而暂停；当前边界是以 v5 拆分 execution health 与 candidate quality，保留 timeout anomaly 后无人值守继续，再累计真实 20+ eligible epoch 和全量星期级结果。以下历史缺口已转化为现役契约：

- 候选、批次、attempt、模型决定、PVE 与 Gate F shard 共享 hash-bound campaign/provenance 身份。
- paired strength、bridge、side-swap、timeout/error anomaly 与盲化模型裁决已有独立 artifact；不再把单 case 胜率直接当最终档位。
- journal 的双 flush、segment hash chain、单 writer、partial row durable commit 与 duplicate exclusion 已由 fixture/既有真实 shard分别覆盖。
- 两场真人 PVE 的 `1 × Lv10` 等效标签已有结构化证据；未自动记录的客观 telemetry 保持未报告，不事后补猜。
- 星期级稳定性、低注意力和完整候选终态仍须由新鲜 Gate F 实跑建立，F0 fixture 和调度草案不能代签。

### 1.2 目标

- 让候选从低质量玩家样本进入后，能够被归一化、聚合、桥接和逐步划分档位。
- 让 Luna 执行高频低成本 loop，让 Sol 与人类只处理高价值决策和方法论变化。
- 把人类提供原始组合的时间与系统运维、PVE 主观评价时间分开计量，并把降低运维人时、人工动作和主动打断设为 Gate F 硬门。
- 让每次模型选择、剪枝和人工验收都可追溯、可重放、可盲评。
- 让 campaign 随时暂停、崩溃后恢复，并避免重复计数或跨版本拼接。
- 在真实标定作业中顺带形成足够的消融证据，而不是先建设一个脱离业务的通用 Agent 实验平台。

### 1.3 非目标

- 不要求首期统一 AS2 全部随机数发生器。
- 不要求首期建立通用多供应商 Agent graph 或模型锦标赛平台。
- 不让多个 Agent 并行控制同一个 Flash 会话。
- 不允许未经人类批准自动写 `arena-factions.js`、`arena_config.xml` 或正式奖励配置；允许对人类已批准的 **exact recommendation bundle** 做确定性 base-hash CAS apply。
- 不把人形怪 vs 待标定怪的直接对战当作最终体验真值。
- 不以一次小样本消融宣称某模型永久更优。
- 不把 Agents SDK、Codex subagent 或任一外部框架的 trace 当作 campaign 事实账本。

### 1.4 Human-attention contract

人类注意力是受预算约束的稀缺资源。Campaign 不得通过“可以人工处理”掩盖自动化缺口。人类时间至少分成提交、PVE、运维主动操作和被迫留守等待四类，分别统计；不能把标定数据生产或必要 PVE 时间记成运维失败，也不能把运维 / 留守时间藏进“数据整理”或“等待”：

| 指标域 | 说明 | Gate F 首轮阈值 |
|---|---|---|
| `submissionActiveMinutes` | 人类提供原始组合、来源和可选主观档位的时间 | 单独报告，不计入运维预算 |
| `pveActiveMinutes` | 人类实际 PVE 与少量主观标签时间 | 单独报告；每 packet 目标 5–10 分钟、硬上限 15 分钟 |
| `opsActiveMinutes` | campaign 启动、恢复、异常处理和收尾的主动操作时间 | 优化目标为 `0`；每 24 小时硬上限 `<= 10` 分钟；单次启动 `<= 5` 分钟；正常收尾 `<= 10` 分钟 |
| `humanBlockedMinutes` | 人类虽未点击，但必须留在机器旁等待下一次确认、监看或解锁的时间 | `unattended` shard 与正常 / 可延期异常必须为 `0` |
| `shardHumanActionCount` | shard 开始至提交 / 暂停的人工点击、命令或确认 | 每个 `shardKind=unattended` 的 shard 必须为 `0` |
| `proactiveInterruptCount` | 系统即时打断内容开发者的次数 | 正常、可延期异常必须为 `0`；只允许数据完整性 / 权限 / 安全 P0 |
| `proposalHumanTouchRate` | 人工 approve、reject 或 edit proposal 的 eligible epoch 比例 | gold suite 建立后 `<= 10%`；分母至少 20 个 epoch |
| `proposalManualEditRate` | 人工实际改写 proposal 的 eligible epoch 比例，是 human touch 的子集 | 同窗口单独报告，不得代替 `proposalHumanTouchRate` |
| `exceptionInboxOpenCount` | 去重后的未闭合 inbox item 数 | Gate F 收尾 urgent / overdue 为 `0`，普通 deferred `<= 5` |
| `exceptionOccurrenceCount / exceptionAffectedScopeCount` | 去重前发生次数，以及受影响 candidate / work item 去重数与最大 fan-out | 必须报告；不能用一个 dedupe item 隐藏大面积失败 |

补充规则：

- 只有人类可以离开且系统不会等待其下一次确认的异步游戏 / 模型 / 脚本等待，才不计 `opsActiveMinutes`；需要人类留守的等待全部计入 `humanBlockedMinutes`，不能以“没有点击”排除。
- `opsActiveMinutes` 必须按 `startup | recovery | exception | closeout` 分桶；正常自动恢复的 `recoveryOpsActiveMinutes` 必须为 `0`，恢复耗尽后进入 inbox 也不即时要求操作。
- `shardKind` 必须在执行前冻结到 shard manifest，首版闭合为 `unattended | pve_packet | fault_injection | maintenance`；执行后不得把高人工 shard 重标成异常或非正常 shard 来规避门槛。
- eligible epoch 是 gold suite 建立后产生 `auto_execute` 或 `defer_and_continue` proposal 的 epoch；按设计必须人工批准的 rubric / 权限 / gold / 正式 apply 变更和 PVE 标签 packet 不进入分母，但排除数量与原因必须报告，不能事后重分类。
- `proposalHumanTouchRate` 和 `proposalManualEditRate` 同时按“滚动最近 20 个 eligible epoch”和“本次 Gate F 全 campaign”报告；approve、reject、edit 都进入前者分子，只有 edit 进入后者分子。分母不足 20 或为 0 时记作 `insufficient_data`，不得按 0% 通过 Gate F。
- exception inbox 必须同时保存每个 `dedupeKey` 的 `occurrenceCount`、受影响 candidate / work item 去重数和 `maxAffectedScopeCount`；item 数只是告警噪声指标，不是影响面指标。
- 每次人工动作必须有 `attentionEvent`，记录原因、耗时、是否可避免和触发源；不能靠会话文字事后估算。
- 首轮阈值冻结在 experiment manifest 中。若要调整，必须在下一次 Gate F 尝试前经 L2 变更并说明原因，不能看到结果后移动门槛。
- 未达到阈值时可以完成数值实验，但不得宣称 low-touch campaign 已验收。

---

## 2. 文档与系统边界

| 事实 | Canonical 位置 |
|---|---|
| AS2 双边战斗、C# Task、JSONL、Node v1 契约 | [斗兽标定平台架构](竞技场斗兽标定平台-架构设计-2026-06-29.md) |
| Campaign 状态、模型权威、消融、人类 PVE、长时恢复 | **本文** |
| 每批路径、样本结果、临时模型 profile、人工决定 | [实验计划与运行日志](竞技场斗兽标定-实验计划与运行日志-2026-07-02.md) |
| 当前运行和验证命令 | [testing-guide.md](../agentsDoc/testing-guide.md)、[automation/README.md](../automation/README.md) |
| Agent Runtime 权限与 standard / legacy 互斥 | [CF7 Agent Runtime / Wings 一期 ADR](CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md) |

本文只引用 L0 字段和入口，不复制完整 wire shape 或命令。L0 协议变化先更新平台架构与验证矩阵；Campaign 决策变化先更新本文。

---

## 3. Loop 分层、Actor 与权威

### 3.1 三层 loop

```text
L2  Human + Sol
    优化目标、验收标准、提示模板、模型路由、统计方法与失败策略
                           │
                           ▼
L1  Luna / bounded agents
    读取冻结快照，提出下一批、初筛、剪枝、桥接与升级人工建议
                           │
                           ▼
L0  Campaign Supervisor + arena runner
    校验、排队、租约、运行、提交、恢复、审计、预算和停止
```

L2 不逐局遥控 L0；L1 不拥有提交权；L0 不擅自修改业务目标。

### 3.2 权威表

| Actor | 可以 | 不可以 |
|---|---|---|
| Campaign Supervisor | 冻结输入、分配 shard、校验提案、按风险级别自动执行、提交事件、去重、恢复、执行预算和失败策略 | 发明业务档位、覆盖人工验收、把未知结果当成功 |
| Sol manager | 汇总证据、选择下一批、批准剪枝、处理冲突、提出 loop 改进 | 直接调用 Flash、直接改正式配置、改写原始 JSONL |
| Luna executor / preliminary judge | 执行有界 planning task、初判、日志归纳、生成结构化提案、声明 abstain | 绕过 schema、扩张工具权限、替 Supervisor 提交 |
| specialist / critic | 对冻结快照做统计、异常、成本或安全审阅 | 与 manager 争夺最终控制权 |
| 人类 | 冻结目标与验收区间、盲评 PVE、批准方法论和正式建议 | 手工改原始结果来“修正”模型 |
| arena runner | 执行已校验 manifest、输出 L0 事实、有限恢复 | 自行决定档位、模型选择或正式配置写回 |

### 3.3 主控拓扑决策

首期采用 manager-style：

```text
Campaign Supervisor
  -> Sol manager
       -> Luna planner/executor
       -> statistics critic
       -> failure critic
  -> Supervisor validates and commits
```

多个 worker 可以并行读取不同快照、日志或候选子图，但同一 campaign epoch 只有一个 manager proposal 被提交，同一 Flash 会话只有一个 active run。不得用多数投票替代证据裁决；模型意见冲突时由 Sol 解释差异，无法解释时输出 `abstain`。Supervisor 随后优先执行冻结的 rule fallback；没有合法 fallback 时隔离 affected scope 并继续其余工作。只有解决冲突必须修改 rubric、统计方法或 gold suite 时，才升级人类。

### 3.4 风险分级与人工批准边界

模型提案经过 schema、身份、cohort、预算、动作白名单和停止条件校验后，按以下三级处理：

| 等级 | 语义 | 典型动作 |
|---|---|---|
| `auto_execute` | 白名单动作且所有硬门通过，由 Supervisor 自动执行，不逐批询问人类 | 预算内追加样本、side swap、bridge、短 shard、规则内剪枝、生成 PVE packet、正常暂停 / 恢复 |
| `defer_and_continue` | 隔离局部异常，把问题写入 exception inbox，其余不受影响工作继续 | contamination、单候选异常、模型分歧、恢复耗尽、局部图断连、PVE 分歧 |
| `human_approval_required` | 只有扩大权限、改变方法论或写入正式内容等不可逆 / 高影响动作 | 改验收阈值、改统计方法、扩工具权限、改 gold suite、正式配置 apply、跨 cohort 强制合并 |

`human_approval_required` 不是普通失败的默认兜底，且提案失败与可信执行 manifest 失败必须分开：

- **模型 proposal 非法**：schema、未知 action、预算或前置约束任一失败，都只拒绝该 proposal，按 `dedupeKey` 记录异常，再执行冻结 rule fallback；没有合法 fallback 时收束为 `abstain` / 隔离 affected scope。Campaign 继续，非法 proposal 不得进入 L0。
- **Supervisor 生成的可信 L0 manifest 非法**：proposal 已通过但确定性 adapter 产出的 manifest 仍不能通过 L0 schema / identity / cohort 验证，表示内部不变量或 adapter 已失效，整个 campaign 才进入 `FAILED_CLOSED`。
- **未知 action**：必须在 proposal schema 层 reject；不存在“无法分类后仍继续执行该 action”的路径。任何未分类动作都不得下发。
- **执行异常的模型兜底**：标准/长 shard 的候选级异常先由确定性规则写 `quarantined` receipt 并 `defer_and_continue`；后台模型只读取 hash-bound request，最多返回 `confirm_quarantine | likely_legitimate_spawn | request_method_change | abstain`。模型不得接受污染样本、恢复候选、改 receipt 或阻塞下一 shard；CLI 缺失、超时、非法输出或模型失败都保持默认隔离。

只有事实账本不连续、可信 L0 manifest 非法、身份 / 权限异常或全局资源安全问题才 `FAILED_CLOSED` 停止整个 campaign。

### 3.5 Exception inbox

每个 `requiresHuman` / exception item 至少包含：

```text
exceptionId
urgency: immediate | daily_digest | before_close
defaultAction
continueUnaffectedWork
reviewDeadline
dedupeKey
affectedScope
occurrenceCount
affectedCandidateIds
affectedWorkItemIds
maxAffectedScopeCount
evidenceRefs
createdAt
```

- `dedupeKey` 相同的重复异常聚合计数，不重复打断。
- 每次聚合都递增 `occurrenceCount`，并更新 `affectedCandidateIds / affectedWorkItemIds / maxAffectedScopeCount`；摘要必须同时显示 inbox item、occurrence 和 affected-scope 三类数量。
- `continueUnaffectedWork=true` 时，Supervisor 必须隔离 affected scope 后继续。
- `daily_digest` 每天最多形成一次摘要，不主动弹出即时确认。
- 到 `reviewDeadline` 未处理时执行 `defaultAction`；默认动作必须是 pause affected scope、quarantine 或保持 provisional，不能默认扩大执行。
- 只有 `urgency=immediate` 且属于数据完整性、权限或机器安全时允许即时打断，并计入 `proactiveInterruptCount`。

---

## 4. Campaign 工作流

### 4.1 主流程

```text
候选登记
→ 规范化与稳定 identity
→ 先验、约束和未知项标注
→ 冻结 decision snapshot
→ planner 选择对局 / side swap / bridge / shard
→ Supervisor 校验预算和安全门
→ arena runner 执行短 shard
→ append-only 提交原始结果
→ 统计拟合、异常和图连通分析
→ Luna 初判 / Sol 裁决
→ 人类盲化 PVE 验收
→ 档位建议、置信状态与 holdout
```

### 4.2 候选登记

输入必须拆成两层，禁止把系统派生工作转嫁给数据提供者。

`raw_submission` 是人类接口。人类只需提供：

- 组合本体；允许表格行、名单、JSON 或可定位的源记录。
- 来源或提供者代号。
- 可选主观档位、预期和自由备注。

人类默认**不需要**提供 `caseId`、hash、蓝红配对、repeat、timeout、sideSwap、阵型、采样预算或风险标签。

`normalized_candidate` 由系统生成，至少记录：

- 独立于单个 batch 的稳定 `candidateId`。
- 规范化 roster 与完整参数。
- `candidateHash`、`rawSubmissionHash` 和源记录引用。
- 默认值、风险标签、数据质量与补全 receipt。
- side swap / anchor / bridge 候选和初始采样预算。
- 人工主观 tier 形成的弱先验；它不能锁定最终区间。

数据质量为 `complete | partial | ambiguous | invalid`。系统能从数据源、默认规则或现有单位目录确定的字段必须自动补全；只有会改变组合语义的真歧义才进入 exception inbox，并按 `dedupeKey` 批量询问。低质量样本不得静默丢弃，也不得要求人类逐条整理成内部 manifest。

### 4.3 决策 epoch

每次 planning 都以不可变 `decisionSnapshotId` 为输入。snapshot 至少包含：

- campaign / epoch / runtime cohort。
- 候选、对局图、已提交结果和排除结果。
- 当前后验、置信区间、side bias 与异常摘要。
- 剩余实机、时间、配额和人工预算。
- 可用动作白名单与停止条件。
- 生成 snapshot 的代码、schema、统计器与策略版本。

模型不能通过读取“最新目录”自行决定输入；Supervisor 必须把 exact snapshot 交给模型。

### 4.4 短 shard

一星期 campaign 必须拆成短 shard。首期默认目标为 **10–25 run 或约 20–40 分钟，以先到者为准**，具体值由组合耗时和机器状态配置，不写死在业务协议。

每个 shard：

- 启动前验证存档、runtime identity、manifest、预算和磁盘空间。
- 一次只租约给一个 runner。
- 每个完成 §5.3 durable commit 的 run 立即成为可恢复事实；仅写入 L0 文件但尚未形成 matching commit record 时不得称已提交。
- shard 结束后生成 checkpoint；模型只在 shard / epoch 边界介入。
- 用户暂停、游戏崩溃、Launcher 失联或机器健康门失败时停止领取新 work item。

机器健康只能使用真实可观测信号；没有温度传感器数据时不得猜测温度。最低门包括进程响应、磁盘空间、错误频率、单局耗时漂移和人工 pause。

### 4.5 开发活动优先级与资源让位

日常内容开发、Flash CS6 编译、人工启动游戏和维护者交互会话永远高于后台标定。Campaign 的自动启动 / 恢复采用 fail-closed 空闲证明，**“没有观察到 development lease”不等于空闲**。

最低调度合同：

- Campaign 只有在收到可信 arbiter 签发且未过期、scope 覆盖 Launcher / Flash / arena runner 的显式 `idleGrant` 后，才可自动启动 / 恢复；替代路径仅限 arbiter 能证明所有已登记 producer 均在线、租约状态新鲜且当前无活动，并为该判断生成等价 grant receipt。
- `idleGrant` 至少绑定 `grantId / issuer / scope / issuedAt / expiresAt / producerSetHash / revokeSignal`。任一 producer 未接线、离线、TTL 过期、时钟 / 状态未知或 arbiter 无法证明覆盖完整时，默认保持 `PAUSED`，不得领取 work item。
- 开发脚本、Flash 编译入口和人工 Launcher 启动必须登记为 producer 并建立 / 刷新 `developmentLease`；存在有效 lease 或 revoke signal 时 campaign 不得自动启动或恢复。
- 观察到开发抢占后立即进入 `PAUSING`，不领取下一局；当前局在安全单局边界提交或 abort 后让位。
- 首轮 `targetYieldLatency` 冻结为 `<=60` 秒，`maxYieldLatency` 硬上限为 `<=5` 分钟。不能在目标内到达安全边界时立即启动受控 abort / retryable；任何情况下都不得越过硬上限继续占用资源。
- 让位完成包括释放 arena runner、legacy automation Launcher、Flash 占用和 campaign work lease；仅把状态写成 paused 不算释放资源。
- 内容开发结束后只在新的 idle window 自动恢复；不得因检测到仓库短暂无写入就猜测人类已经离开。
- 所有抢占与恢复计入调度遥测，但正常自动让位不计人工动作。

---

## 5. 可中断状态与 exactly-once 计数

### 5.1 Campaign 状态

```text
DRAFT
  -> READY
  -> RUNNING
  -> PAUSING
  -> PAUSED
  -> RUNNING
  -> COMPLETED

局部异常:
  RUNNING -> EXCEPTIONS_PENDING -> RUNNING
  （受影响 scope defer，其余继续）

需要方法论 / 权限决定:
  RUNNING -> REVIEW_REQUIRED -> RUNNING | ABORTED

任意非终态:
  -> ABORTED
  -> FAILED_CLOSED
```

`RUNNING -> COMPLETED` 是正常自动完成路径，不能把人类 review 放在所有 campaign 的关键路径上。`PAUSED` 和 `EXCEPTIONS_PENDING` 都是正常可恢复状态，不是失败；后者允许 exception inbox 非空但未超阈值时继续不受影响工作。进程退出、电脑重启或游戏崩溃后，只要账本连续且租约可收束，campaign 仍可从 `PAUSED` 恢复。

### 5.2 Work item 状态

```text
PENDING
→ LEASED
→ RUNNING
→ COMMITTED

异常分支:
→ RETRYABLE
→ QUARANTINED
→ CANCELLED
```

执行语义为 **at-least-once execution + exactly-once counting**：

- `runKey` 必须稳定绑定 `campaignId + candidate/case hash + side assignment + sample ordinal + battleSemanticsCohortId`。
- 多次 attempt 可以指向同一 `runKey`。
- 统计器只消费一个 canonical committed result；**账本中首个 schema 有效、hash 有效且 durable commit 完成的事件胜出**。
- 后续 attempt 即使也产生有效结果，只能标记为 duplicate / excluded evidence，不能用“最新结果”、多数票或模型选择覆盖首个 durable commit。
- 已落盘 result、响应丢失时不得盲目重复计数；重复 attempt 必须按上述确定性规则 reconcile。
- 无法判断副作用或结果是否提交时进入 `QUARANTINED`，不能自动伪造成缺失样本。

### 5.3 持久化

在现有 batch v1 文件之上增加以下耐久 campaign store；`tmp/arena-calibration/**` 只允许保存可重建的 manifest、模型草稿和缓存，不得承载 canonical journal：

```text
logs/arena-calibration/campaigns/<campaignId>/
  campaign_manifest.json
  checkpoint.json
  candidates.json
  events/<segmentId>.jsonl
  epochs/<epochId>/
    decision_snapshot.json
    proposals/<proposalId>.json
    decision_receipt.json
    adjudication.json
  shards/<shardId>/
    shard_manifest.json
    run_report.json
```

- `events/*.jsonl` 共同组成 append-only 决策账本。目录至少保留到 campaign 收尾后 90 天；只要 recommendation / apply / rollback / 异议仍引用它就不得清理。清理必须由独立保留策略生成 deletion receipt，不能由正常 runner 顺手删除。
- 每个 campaign 同时只有一个 journal writer。writer 必须持有绑定 `campaignId + writerProcessIdentity + writerEpoch + expiresAt` 的独占 OS lock / lease；旧进程 incarnation 未确认死亡、lease 未收束或 writer 状态未知时，新 writer 不得 append。
- 事件至少携带单调 sequence、previous hash 和 event hash。每次 commit 采用二阶段耐久记录：先 append 完整 event 并 flush 语言运行时缓冲与 Windows `FlushFileBuffers`（或平台等价物），再 append 引用 `sequence + eventHash + segmentOffset` 的 `durable_commit` record 并再次 flush。只有 event 与匹配的、已完成第二次 flush 的 commit record 同时存在，才算 §5.2 的 durable commit；Supervisor 才能返回 `durableCommitReceipt`。
- segment 关闭时 append `segment_close`（含末 sequence / hash）、完成同样的 durable flush，再以 atomic replace 更新 segment index 和派生 checkpoint。已关闭 segment 永不重开；进程异常留下的不完整尾行或没有匹配 commit record 的 event 均不算事实，只能在新 segment 中记录为 `truncated_tail` / excluded evidence。
- 崩溃恢复顺序冻结为：取得新 writer lease → 验证全部 closed segment 与 hash chain → 扫描唯一 open segment → 只接受带匹配 durable commit 的完整 event → 在新 segment 记录断尾 → 从 journal 重建 checkpoint → reconcile `runKey` 后恢复领取。不得先信 checkpoint，也不得在旧尾部补写。
- `checkpoint.json` 是原子替换的派生快照，不是事实真源。
- 现有 batch `result.jsonl` 保持 L0 原始事实；Campaign 只引用其 hash 和 canonical row。
- 临时模型对话、自然语言草稿和 SDK trace 不是恢复必需输入。

---

## 6. 运行 cohort、随机性与统计方法

### 6.1 Artifact identity 与 battle semantics cohort

必须分离“精确执行身份”和“可否统计合并”：

- `executionArtifactIdentity` 精确记录每次执行的 AS2 / SWF、Launcher、runner、配置、manifest 和其他二进制 / 数据身份；任何字节变化都产生新 identity。
- `battleSemanticsCohortId` 只绑定可能改变战斗结果分布的闭包，用于决定统计池是否可以合并。
- `decisionPolicyId` 绑定 prompt、模型、planner、rubric 与主控拓扑，用于区分决策来源；它通常不切分既有战斗样本。

必然切换 battle semantics cohort 的变化包括：

- 战斗 AS2、ArenaCalibrationService、单位 / 技能 / AI / stage 数据或 SWF 战斗资产变化。
- roster 参数归一化、阵型、出生距离、timeout 结果语义和污染判定变化。
- manifest / result 中影响战斗输入或胜负解释的协议变化。

文档、纯 UI、非 arena Launcher 面板或已证明不进入战斗闭包的改动仍更新 `executionArtifactIdentity`，但可以保留 `battleSemanticsCohortId`。保留必须产生 `cohortCompatibilityReceipt`，列出 changed paths、闭包分类器版本、负向测试和理由；未知、无法分类或测试不足时 fail closed 创建新 battle cohort。不得因为根 commit 改变就自动丢弃全部历史样本，也不得因为文件名看似无关就跳过证明。

### 6.2 Seed 语义

- 记录可获得的 seed、启动时间、attempt 和运行身份。
- `seed` 不参与“结果必然相同”的验收承诺。
- 不能只控制项目 LCG 就声称控制了 AS2 `random()`、`Math.random()` 和所有内部随机源。
- 通过重复样本、side swap、批次分块和置信区间吸收随机噪音。
- 若未来统一随机源，应另立可复现性 ADR，并用覆盖清单证明随机源闭包。

### 6.3 强度与梯队

首期统计 v2 应满足以下性质，不强绑单一实现库：

- 以成对比较概率模型估计连续潜在强度和不确定度。
- 能显式处理平局；Bradley–Terry / Davidson 家族可作为首选基线。
- 单独估计或诊断 side bias、批次 / cohort effect。
- 检查候选图连通性；孤岛必须通过 bridge case 连接，不能独立硬排。
- 对明显非传递关系保留局部 matchup 标签，不强迫单轴解释全部构筑。
- 档位由后验区间和人工体验锚点派生，允许 `boundary`、`provisional` 和 `context_dependent`。
- Elo 只作便宜的在线排序或展示，不作最终可信源。

---

## 7. 模型输入、输出与消融

### 7.1 最小证据契约

首期至少需要四类结构化产物：

1. `decision_snapshot`：模型看到的不可变输入。
2. `controller_proposal`：下一批、剪枝、桥接、升级人工、停止或 abstain。
3. `decision_receipt`：模型 / role / prompt 与策略版本、耗时、配额、校验和最终采纳结果。
4. `adjudication`：机械评分、盲化人工评分、异议和最终理由。

proposal 必须声明：

- `proposalId / decisionSnapshotId / modelProfile / role`。
- 动作及 exact candidate / case hash。
- 预算和预期信息收益。
- 证据引用。
- 风险、反例和置信度。
- `abstain` 或 `requiresHuman`。

自然语言理由可以保留，但不能替代结构化动作。

Gate A 冻结 `controller_proposal.actions[*].action` 的首版闭合枚举：

| action | 默认风险级别 |
|---|---|
| `schedule_shard` | `auto_execute` |
| `append_samples` | `auto_execute` |
| `create_side_swap` | `auto_execute` |
| `create_bridge` | `auto_execute` |
| `prune_sampling` | `auto_execute`，只停止追加，不删除事实 |
| `quarantine_candidate` | `defer_and_continue` |
| `enqueue_pve_packet` | `auto_execute`，只入人类待办，不即时打断 |
| `complete_candidate` | `auto_execute`，必须满足冻结完成门 |
| `pause_campaign` | `auto_execute` |
| `abstain` | `defer_and_continue` |
| `request_method_change` | `human_approval_required` |
| `propose_recommendation_bundle` | `auto_execute`，只生成 dry-run bundle |
| `request_formal_apply` | `human_approval_required` |

未知 action 必须 schema 失败；不得用自由文本 action 或通用 tool call 绕过枚举。各 action 的 exact required / optional 字段、预算上限和前置状态属于 Gate A schema 的必交付，不再列为非阻塞开放项。

### 7.2 三类比较

| 比较 | 回答的问题 |
|---|---|
| Sol vs Luna 读取同一 snapshot | 模型能力 / 成本比较 |
| Sol 独立 vs Luna 提案后 Sol 裁决 | 工作流拓扑消融 |
| 固定 rule planner vs LLM planner | 引入智能推理是否产生增益 |

三类结果必须分别报告，不能合成“某模型总体胜率”。

### 7.3 首轮 shadow profiles

- `A_sol_manager_only`
- `B_luna_manager_only`
- `C_luna_propose_sol_adjudicate`

三个 profile 读取同一冻结 snapshot、相同动作白名单和预算，输出相同 schema。首轮 shadow 不直接执行三套实机计划；只执行 Supervisor 最终采纳的一份，其余作为反事实提案保留。

shadow 先比较：

- schema / 安全门通过率。
- 计划可执行性和约束违反。
- 候选图连接、side swap 与边界覆盖。
- 预期不确定度下降。
- 人类盲评和修改次数。
- 配额、延迟和上下文体量。

只有 shadow 显示有物质差异，才进入按匹配候选池或分块 epoch 的在线交错实验。不得为了消融无条件把实机战斗量放大三倍。

### 7.4 模型选择规则

- 所有 hard safety gate 必须通过；质量分不能抵销硬失败。
- 选择阈值在揭盲前写入 experiment manifest。
- 更复杂 profile 只有在质量增益覆盖配额、延迟和协调成本时才晋级。
- 结果不足时保留 provisional profile，不强行宣布赢家。
- 模型升级、prompt 大改或职责变化后重新跑冻结 snapshot suite。

---

## 8. 人类 PVE 验收

### 8.1 定位

机器斗兽结果负责相对强度和稳定性；人类 PVE 负责把冻结怪物组合外部拟合为“等效 N 名、L 级人形佣兵”。两类证据分别保存，不能把 PVE 标签覆盖到原始 battle result。

人形佣兵是本标定任务的语义标尺。批准的玩家存档只负责提供一致且有足够余量的测量条件；例如 32 级玩家通常能击败 4 名 40 级佣兵，并不意味着每个被其击败的组合都应标成 32 级，也不允许把玩家胜负直接换算成档位。

### 8.2 协议

- PVE 交付单位是可暂停的 `calibrationPacket`，默认包含 2–4 个 encounter，目标人类 active time 为 5–10 分钟，硬上限 15 分钟。
- packet 自动选择批准的玩家 build profile、准备 encounter、进入 PVE、记录客观遥测并在 encounter 边界 checkpoint；不同 build family 分开记录。
- 客观遥测至少包括战斗时长、玩家死亡 / 失败、承伤、输出、剩余生命和可获得的异常事件；能自动采集的字段不得要求人类手填。
- 人类默认只提交 `equivalentHumanoidCount + equivalentHumanoidLevel`、原话、最多两个压力标签和可选置信度；胜负、残血、承伤、输出等能自动采集的字段不得要求人类事后回忆或由工具虚构。
- 主控模型提供若干成对候选及推荐观察点，但显示层隐藏 controller / model identity、候选先验档位、来源、历史机器结论和推荐结论，并随机化 A/B 顺序。
- packet 可以随时暂停；恢复后从未完成 encounter 继续，已提交标签不重复询问。
- 保留 holdout 候选，避免所有样本都参与方法调整。

### 8.3 Gold suite 与低接触消融

- pilot 阶段由人类对冻结 snapshot / proposal 和少量 PVE packet 建立版本化 gold suite。
- gold suite 建立后，每次模型 / prompt / workflow 变化先跑全量机械回归；人工只复核新增任务类型、rubric 变化、重大 profile 分歧和固定比例随机审计。
- 普通无分歧回归不得重复要求人类盲裁。
- gold suite 变更属于 `human_approval_required`，必须新版本，不能就地改标签使当前模型通过。

### 8.4 结论状态

候选最终状态至少允许：

- `accepted`
- `boundary`
- `provisional`
- `context_dependent`
- `abnormal`
- `rejected`
- `quarantined`

`provisional` 和 `quarantined` 都是**当前 campaign revision 的合法终态**：前者表示证据不足但结果可交付，后者表示数据 / 运行异常阻止数值结论；未来新 campaign 可以显式 reopen。它们不是跨版本永久结论。“已跑完全部候选”不等于“全部 accepted”。无法稳定量化的候选应进入边界、上下文相关或隔离状态，并留下下一步证据需求。

### 8.5 Recommendation bundle 与一次批准落地

标定结果进入正式内容前必须生成可验证的 `recommendationBundle`，禁止要求人类手工抄录 `benchLevel` 或在 Web JS / XML 间翻译。Bundle 至少包含：

- recommendation / candidate / campaign / cohort identity。
- 建议值、置信状态、证据与 PVE 引用。
- 当前运行时 SOT 的 exact target path / symbol、base hash 和 source revision。
- dry-run diff 与机器可读 patch。
- 受影响验证命令、预期输出和回滚 patch / 原值。
- 配置 SOT 未闭合、base hash 漂移或目标歧义时的 fail-closed reason。

生成 bundle 属于 `auto_execute`，不会改正式内容。`request_formal_apply` 属于 `human_approval_required`：人类只批准一次 exact bundle；随后确定性 apply 工具用 base-hash CAS 应用 exact patch、运行验证并生成 apply receipt / rollback bundle。模型不得在批准后自由改写 patch，验证失败则自动回滚或保持未应用状态并进入 exception inbox。

---

## 9. 当前能力缺口与功能增强

| 优先级 | 能力 | 当前事实 | 需要增强 |
|---|---|---|---|
| P0 | 契约闭合 | Gate A 已闭合，Gate B execution artifact 继续绑定 `parameters/sourceId/hpPermille`、原始结果和 manifest hash | 无开放缺口；后续变更按 cohort compatibility 重新判定 |
| P0 | 结果枚举 | core、schema、fixture 和生产实例 validator 均接受 `contamination`，异常不进入强度样本 | 接入真实异常时继续写 durable disposition |
| P0 | 候选 registry | stable source/candidate 身份已进入 intake；Gate B 账本及 Gate F partial import 以 `manifestHash + runId` 首次 durable commit 去重 | 用星期级真实 shard 验证全部候选终态 |
| P0 | 决策证据 | 13-action proposal / receipt / adjudication、确定性 L0 adapter、三 profile 真实输出、盲评回执及 198 份 Gate F shard decision evidence 已冻结 | 正式 freeze 时绑定最终 source/runtime identity |
| P0 | 人类注意力 | 两个既有真实 `unattended` shard 均记录 0 action / 0 blocked / 0 interrupt；Gate F0 fixture 证明不足 20 epoch fail、20 epoch 与 3/20 touch 阈值 | 用 Gate F 真实最近 20 epoch 和全 campaign 两窗口验收；fixture 不代签 |
| P1 | Campaign Supervisor | Node owner 已实现 journal、checkpoint、writer lease、pause/resume、partial row exactly-once、失败 receipt 和真实两 shard campaign | 真实断电和星期级漂移留 Gate F 实跑 |
| P1 | Provenance | 两个 execution artifact 均闭合 runKey、formal runtime、cohort、compatibility receipt、raw JSONL 与 save guard | 后续 shard 继续复用同一强门 |
| P1 | 资源调度 | exact producer registry、短 grant、最长 24 小时 revocable window、真实 Windows process/disk gate 与 owned cancel signal；缺失/active/unknown/stale/expired/revoked 均 fail closed | 真实长时抢占延迟留 Gate F 汇总 |
| P2 | 分析 v2 | regularized Bradley–Terry（draw half）已输出区间、side bias、图分量与异常排除 | 样本仍少且图断连，不能用于最终分档 |
| P2 | planner v2 | 已生成 bridge、side-swap audit 与 timeout/error anomaly disposition | 跑真实桥接 shard 后复算 |
| P3 | 模型 adapter | A/B/C 三 profile 已对同一 snapshot 完成真实调用；机械 scorecard 与盲化模型复核均有 receipt，盲评顺序为 C > A > B | 本次只建立一次可重放证据，不外推为永久模型排名 |
| P3 | 人类 PVE | exact formal runtime、冻结 Lv32 玩家 build、2 场受控 encounter、两份截图/报告和两条 `1 × Lv10` 等效标签已闭合 | 客观战斗 telemetry 未报告，当前只到 `equivalence_only`；以后 packet 直接采数值等效合同 |
| P3 | 正式建议落地 | 结果到 Web JS / XML 之间需人工翻译 | recommendation bundle、dry-run diff、一次批准 apply 和 rollback receipt |
| P4 | 故障演练 | 已有 crash/timeout/rerun 实机证据；fixture 覆盖 checkpoint 撕裂、重复 attempt、ack 丢失、磁盘不足、window expiry/revoke、active producer 和 manifest/decision 篡改 | 真实断电、长时漂移和运行中内容开发抢占留 Gate F 实跑 |

P0 契约漂移已于 2026-08-27 闭合。当前统一门用 Ajv 2020 编译 46 个顶层/嵌入 schema，并完成 73 项检查，合法实例通过、对应非法形状拒绝；覆盖 manifest、result、summary、next batch、工作簿 intake、Campaign runtime、shadow / paired / PVE artifacts、数值人形佣兵等效响应、Gate F plan/window/decision/attention/shard receipt/status，以及候选 quarantine、异常模型 request/result/receipt/dispatch。测试群工作簿以 SHA-256 `840B30AF82CA686E954DC4A6378A5C2B297506070E034ED79EA91DA9E0B3B793`、sheet `斗兽标定组合` 和单元格定位摄取：59 个 populated cells 形成 59 个 raw submissions、58 个 normalized candidates，`C9` 和 `B9` 产生 hash-bound 派生修正，`B12` 保留原文并隔离，原工作簿未改写。

fresh 运行前置门也已闭合：10-run `gate-a-pilot-20260827-a` 覆盖普通、单位 payload、阵型、显式长 timeout 与高等级案例，10/10 finished、0 timeout/error/contamination；随后 30-run `gate-a-exploration-20260827-a` 为 27 finished、3 timeout、0 error/contamination。两批均绑定同一 verified formal runtime identity / payload closure，且专用目标槽以外 20 份 live shadow JSON / SOL 的跑前跑后集合 hash 完全一致。探索批 10% timeout 必须保留为调查信号；每个方向只有 3 个样本，不足最终候选门。独立 1-run `gate-a-shutdown-regression-20260827-a` 证明 expected PID 消失可作为正常 shutdown 终态；随后 `gate-a-schema-regression-20260827-a` 以 1/1 finished、原始 JSONL direct-schema-valid、exact manifest/case binding、`error=null` 和相同 save hash 证明生产字段闭包真正进入现役 runner。

---

## 10. Agent Runtime 与当前 runner 的边界

F8 冻结了两种互斥控制面：

- **standard normal**：启用 CF7 Agent Runtime / Wings，privileged legacy HTTP `DenyAll`。
- **explicit legacy HTTP automation**：签发进程生命周期 credential，不创建 Agent Runtime / Wings。

当前 `tools/arena-calibration/run-unattended.js` 属于第二种。它通过 `LegacyHttpClient` 读取 exact launcher ports 和授权信息，并显式启动 legacy automation，以使用 arena `/task` 和窄化 agent entry 路径。

因此：

- Campaign Supervisor 当前只能把 arena runner 当作受约束 L0 adapter。
- 不得声称斗兽已使用 F8 Agent Runtime 的标准 MCP 业务能力。
- 不得让 Wings 或标准 Agent Runtime 调用 `/console`。
- 不得为了统一外观把 legacy token、slot 文本或 parent command line 当成 Agent Runtime principal。
- 若未来迁移，必须定义 bounded `arena.inspect / propose / run / status / abort / reconcile` 或等价结构化能力、租约、reason code 和审计合同，并另起协议 ADR。

F8 的 lease、audit 与 trusted runner 设计可作安全参考，官方 manager-style 编排可作模型拓扑参考；两者都不能跳过现有 arena 业务 owner。

---

## 11. 失败路线

| 失败 | 状态 / 路线 | 是否自动重试 |
|---|---|---|
| 模型 proposal schema / action / 预算 / 前置约束非法 | 只 reject proposal，写去重 exception；冻结 rule fallback，否则 `abstain` / quarantine affected scope，campaign 继续 | 可有界重试模型；不启动游戏 |
| Supervisor 确定性 adapter 生成的可信 L0 manifest 非法 | 内部不变量失败，`FAILED_CLOSED` | 否；修 adapter / 契约 |
| 人类 raw submission 缺失或有歧义 | 隔离该 submission / candidate，批量进入 inbox，其余继续 | 补齐后可重新 normalize |
| 正式槽、坏档或 runtime identity 不符 | `FAILED_CLOSED`，写安全 exception | 否 |
| socket / Launcher 在结果提交前断开 | work item `RETRYABLE` | 有界；新 attempt |
| result 已提交但 ack 丢失 | reconcile `runKey`，首个有效 durable commit 胜出 | 不盲重计 |
| 标准/长 shard 的 `contamination/error/invalid_case/spawn_failed`，且 runtime/save/disk/墙钟/cardinality 均闭合 | affected candidate `QUARANTINED`，写 inbox，跳过其后续 shard，其余继续；可异步唤醒无接受权的模型诊断 | 默认否，修复后 fresh rerun |
| 基础设施 soak、`stage_failed/bridge_lost`、duration drift、runtime/save/disk、runner/report/cardinality 异常 | shard 失败；全局身份/存档/磁盘问题可 `FAILED_CLOSED` | 按现有有界恢复与安全门 |
| timeout / 僵持 | 独立异常样本 | 按策略追加或隔离 |
| 图断连 / 区间过宽 | planner 生成 bridge / boundary 样本 | 是，受预算约束 |
| 模型 profile 冲突或 Sol 无法解释 | Sol `abstain`；Supervisor 执行冻结 rule fallback，否则 `defer_and_continue` 并隔离 affected scope | 否；仅需改 rubric / 统计方法 / gold suite 时进入 L2 |
| 自动恢复次数耗尽 | 受影响 work item / candidate quarantine，其余继续 | 否；不即时打断 |
| 模型与 gold / 人类长期冲突 | `context_dependent`，只在方法论变更时进入 L2 review | 否 |
| 人工 pause、机器异常或磁盘不足 | `PAUSING -> PAUSED` | 恢复门通过后 |
| audit / journal 不连续 | `FAILED_CLOSED` | 不跨缺口续写成功事实 |

任何自动恢复都必须有上限。达到上限后保留 checkpoint、失败证据和默认隔离动作，不无限重启轻薄设备；人工恢复建议进入 exception inbox，而不是立即中断内容开发。

---

## 12. 分期施工与验收

### Gate A：ADR 与最小契约（`COMPLETE`，2026-08-27）

- 本文评审通过。
- 定义 raw submission、normalized candidate、campaign、snapshot、proposal、receipt、adjudication、attention event 和 exception inbox schema。
- `controller_proposal` 使用本文 §7.1 的闭合 action 枚举，并为每个 action 冻结 exact required / optional 字段、预算和前置状态。
- 冻结 proposal action 到现役 `next_batch.json` / `case_manifest.json` 的确定性 adapter；无法无损映射的 action 必须拒绝，不能让模型直接构造 L0 控制请求。
- 冻结 §5.3 的 journal 根路径、至少 90 天 / 引用存续期保留规则、单 writer lease、双 flush durable commit、segment close 和断尾恢复顺序；实现 owner 可以后定，但不得改写 durable 判据。
- attention schema 冻结 `shardKind` 的执行前声明、`humanBlockedMinutes`、proposal rate 的统计窗口 / 最小分母 / zero-epoch 语义，以及 exception item / occurrence / affected-scope 三套计数。
- 修复 `parameters` 闭包与 `contamination` 枚举漂移。
- Node fake fixtures 分别证明：未知 / 非法模型 action 被 reject 且 campaign 继续；可信 L0 manifest 非法使 campaign `FAILED_CLOSED`；两者不能共用模糊的“schema 非法”期望。

完成回执：闭合 action 共 13 项；schema registry、合法/非法实例、参数/authority hash、生产原始 JSONL、污染结果、最终候选硬门和确定性 adapter fixture 全部通过。10-run fresh pilot 通过后才进入 30-run exploration；原始 JSONL 和历史 teardown 错误均未被改写。Gate A 的完成只代表 Gate B 可开工，不代表 journal durability、模型消融、最终候选或正式配置回写已完成。

### Gate B：可恢复最小 Campaign（`COMPLETE`，2026-08-27）

- 以 provisional profile 完成一个小型真实 campaign。
- 至少包含两个 shard 和一次人为 pause / 进程中断。
- 注入 writer contention、第一次 / 第二次 flush 前后崩溃、未关闭 segment、断尾和 ack 丢失；恢复只能采纳带匹配 `durable_commit` 的首个有效 result，不丢失、不重复计数，也不把未提交 event 补写成事实。
- `auto_execute / defer_and_continue / human_approval_required` 三条路径均有 fixture；普通 batch 不要求人工确认。
- attention event、execution artifact、battle semantics cohort、compatibility receipt 与 decision policy 可追溯。
- 无 grant、过期 grant、缺失 / 离线 producer、未知 lease 状态均阻止启动；有效 `idleGrant` 才允许恢复。开发抢占目标在 60 秒内让位，5 分钟硬上限内必须释放 Launcher、Flash 和 work lease。

完成回执：`gate-b-campaign-20260827-a` 以 `provisional_gate_b_v1 / rule-provisional-gate-b-v1` 运行 B2、G2 两个真实 shard，中间显式 `campaign_paused + segment_close` 后由新进程、新 producer snapshot 和新 idle grant 恢复；最终 journal 重放为 `PAUSED`、26 个 committed event、2 个唯一 runKey、3 个 closed segment、0 个 open segment。两局均 1/1 finished、0 timeout/error，绑定 formal Core SHA-256 `69372E65CAB80D81A9448A41AA2167E8A7E707FB949CF57710BADC25118B16E2`、build identity `E746A365F2715556A3298C4CBF1E926F039BC147625D4612F850768C9A52ADA3`、payload closure `8175440099ECF58708CD35F81F9C4A0B81390EC64EF2896D96EB885779A20475`；20 份受保护 live JSON/SOL 的前后 snapshot 都是 `sha256:fcfaa53f9000a5b7e75205bb3549aa2c8b5798df3fe5d4843725222ffbede73b`。fixture 另覆盖 writer contention、四个双 flush crash 点、ack 丢失 exactly-once、未提交断尾排除、closed segment 篡改拒绝和显式 pause/resume。该完成只证明 Campaign 控制面与已覆盖运行路径，不证明候选数值稳定或 Gate C。

### Gate C：最小消融验收（`COMPLETE`，2026-08-27）

- 从 Gate B 冻结若干真实 decision snapshot。
- A / B / C 三个 shadow profile 输出同一 proposal schema。
- 完成机械评分和至少一次同时隐藏模型、先验档位、来源及历史结论的人类裁决，形成 versioned gold suite。
- 输出 initial profile 选择或“证据不足”，不要求永久模型排名。

冻结 snapshot `sha256:643992178e0de1d8cd9f6ad7eb731cd6bceb417a4987da748af9c8d8cb2d867f` 已由 A=`gpt-5.6-sol`、B=`gpt-5.6-luna`、C=`Luna draft + gpt-5.6-sol adjudication` 三个真实 profile 产生 proposal / receipt；随后 `gpt-5.6-sol` high 对盲化 packet 独立复核，给出 C > A > B、confidence 0.96，review hash `sha256:1ac12776aebcd38af04c73692a575625f2e43eff7b1f85d0afc0c33a32636b55`。这完成本轮冻结快照的模型盲评要求，但只是一次方法选择证据，不建立永久模型排名，也不冒充真人 PVE。

### Gate D：统计与主动采样（`SELECTED_CANDIDATE_MACHINE_COMPLETE`）

- paired model 输出潜在强度区间。
- planner 能发现断连子图并生成 bridge。
- side swap、平局、异常和非传递候选不会被强塞普通档。

初始 42 行只形成断连预分析。随后按主动计划执行 34 个 fresh run，并对单一候选执行 21 个 confirmatory run；最终配对报告共有 91 个 eligible、6 个异常排除、1 个连通分量、0 bridge 待办，report hash `sha256:882618beb7772abbd848c70bb4b7c48902750f4b7aeb599558329c65652d5aa3`。最终 snapshot `sha256:54264666fb09b946b4206a1b9ec50c4cdefd2b2dc0771a70280b51bb37a6b5e3` 中，工作簿 G2 的 `candidate-dd65977b16a48a35` 达到 original 15 + swapped 15、两向 0 timeout / 0 error、`sideSwapReviewed=true`，`complete_candidate` receipt 已 accepted。其余候选仍保持 provisional，不随单候选一起晋级。

### Gate E：人类 PVE 外部验收（`EQUIVALENCE_LABELS_COMPLETE / OBJECTIVE_TELEMETRY_UNREPORTED`）

- 主控生成成对 PVE 候选。
- 以可暂停 calibration packet 自动选择 build、进场和采集客观遥测；人类只提交等效人形佣兵数量、等级及少量可选标签。
- 每 packet 2–4 encounter、目标 5–10 分钟、硬上限 15 分钟；超过即验收失败或拆包。
- 至少一个 holdout 不参与前期调参。
- 输出 accepted / boundary / provisional 等状态和证据引用。

本轮 packet `sha256:f66096025432d7f3707adde7b8eb514dd4d10f0ee5e3be9e123331048ee73449` 绑定获批 Lv32 玩家 build 与 exact formal runtime。两场受控 encounter 的 match hash 分别为 `sha256:dddd9868fe3dd1a8c96d5abd7c7109e287fe1f17ac7dd302e9674f18bfeed538`、`sha256:5489bae928a643aa37a0e26513e15284d48b0346d85c657d0d901e285e3f1e88`，维护者分别给出“体感应该是10级人形怪级的等效战力”和“1名10级佣兵等效战力”，均规范化为 `1 × Lv10`。数值响应 hash 为 `sha256:76ab8e72f4edfcfdbebd7c38b7235a273d0205b4fc9248f3987a4609cec18f18`，通过 exact packet validator；源存档 hash 未变、非目标存档集合未变，active 专用槽 / runtime process / lock / recovery record 均为 0。

该 packet 在口径修正前生成，原 `subjectiveLabelContract` 仍是泛化体验档；已执行 encounter 的 packet hash 不回写。数值等效响应以新 schema 作为 hash-bound 补充证据，后续 packet builder 直接输出 `monster_group_to_humanoid_mercenary_equivalence`。由于本轮没有自动落下 duration、胜负、承伤、输出、残血和异常 telemetry，也不让维护者事后补猜，Gate E 当前只完成等效标签子门；未生成 recommendation bundle，未修改 `arena_factions.json`，未 formal apply。

### Gate F：星期级累计 campaign（`F0_ENGINEERING_READY / FORMAL_SOAK_PAUSED / ROUTING_FIX_READY`）

- 多次正常暂停、游戏崩溃或电脑重启后可恢复。
- 没有无限重启、跨 cohort 拼接或重复计数。
- 每个候选完成标定，或有明确的 provisional / quarantined / rejected 终态。
- 人类可以从摘要回溯 exact 原始结果、模型决定和 PVE 评分。
- 每个执行前声明为 `shardKind=unattended` 的 shard `shardHumanActionCount=0`；`opsActiveMinutes` 优化目标为 0、每 24 小时硬上限 `<=10` 分钟，单次启动 `<=5` 分钟，正常收尾 `<=10` 分钟；不得事后重标 shardKind。
- `unattended` shard 与正常 / 可延期异常的 `humanBlockedMinutes=0`；只有维护者可以离开的异步等待才可排除。
- 正常自动恢复 `recoveryOpsActiveMinutes=0`；恢复耗尽只写 exception inbox，不即时要求维护者介入。
- 正常 / 可延期异常 `proactiveInterruptCount=0`；urgent / overdue inbox 为 0，普通 deferred item backlog `<=5`。同时报告 occurrence、受影响 candidate / work item 和最大 fan-out；deferred 的 affected-candidate 与 affected-work-item 比例均须 `<=10%`，分母为本 campaign 已登记 candidate / 已调度 work item；任一分母为 0 时记作 `insufficient_data`，不得借此按 0% 通过 Gate F。
- gold suite 建立后，在滚动最近 20 个 eligible epoch 与 Gate F 全 campaign 两个窗口内，`proposalHumanTouchRate<=10%`；approve / reject / edit 均计 touch，edit 另报 `proposalManualEditRate`。任一窗口分母不足 20 或为 0 时不得称 low-touch 已验收。
- 内容开发 / Flash 编译抢占以 `targetYieldLatency<=60` 秒为目标，并在 `maxYieldLatency<=5` 分钟硬上限内释放 Launcher、Flash 和 work lease。
- 对进入正式建议阶段的候选生成 recommendation bundle；人类不需要手工抄录配置。

Gate F0 首轮以 `gate-f-week-full-v1` 计划族、`gate-f-week-full-v2` 执行 campaign 冻结 58 个 normalized candidate，`B12` 保持 quarantine；共 198 个短 shard、3255 个计划 run、198 份 hash-bound `schedule_shard/auto_execute` 决策证据。新部署在 `ArenaController.prepareArenaStage()` 增加 `StageRunSession.canStartStage()` admission，因此 G2 `candidate-dd65977b16a48a35` 的两场 `1 × Lv10` PVE 标签继续保留，但旧 runtime 的机器完成证据不跨 cohort 代签，G2 也重新执行 55 run。普通候选为 `10 + 20 + 25 = 55` run，显式长 timeout 候选为 `6 × 10 = 60` run，全部包含 original/side-swap。B9 的 1800 帧双向 timeout 与 5400 帧 2776/3494 finished 已作为 schema-valid、hash/cell/candidate/runtime/save-bound 的计划层 override 固化；normalized intake 和旧超时不改写，candidate 证据不能代签 formal replay。合并候选的首份 10-run 诊断为 9 finished + C9 换边 1 timeout；随后 C9 的 5400 帧双向探针均在 1800 帧前 finished，故没有形成 timeout override。

首轮三份 formal soak 已真实执行：`f-soak-01/02` 合计 20/20 finished，`f-soak-03` 为 8 finished + B11/C12 原向 2 timeout。三份均绑定 formal identity `48E2ACEA81194C0D6C3A89226DEC2748192612B5514D3F3ADB8444FA4AF6C528`、closure `DA7E5BD135FF2407ED7CE459F521BEA95C9CB6F5CC63AA5291ABAC795DAF59F1` 与不变存档 snapshot `sha256:fcfaa53f9000a5b7e75205bb3549aa2c8b5798df3fe5d4843725222ffbede73b`；30 行均 Schema/manifest-bound、零 error/recovery、正常关闭且无玩家/存档污染。失败只来自第三份把候选自身长战随机性混入基础设施门：B11 原向跑满 9000 帧、C12 原向跑满 5400 帧，而各自 side-swap 自然结束。该批正确暂停且旧行原样保留，不能通过重试或调大 timeout 改写成平台稳定。

修正后的 `gate-f-week-full-v2` plan / `gate-f-week-full-v3` campaign 新增必需的 `arena-calibration.soak-admission.v1`：生成器逐文件复验原始 manifest/result/report SHA-256、真正 Schema 实例、exact candidate timeout、original/side-swap 自然结束、formal runtime identity、零 error/timeout/recovery、正常关闭与受保护存档不变；freeze 继续绑定 admission path/hash 和 exact runtime。三份 10-run fresh soak 都使用 `B2/C7/G2/F3/E10`，每份同时覆盖普通参数、单位 payload、阵型、长 timeout、高等级与 side-swap，并已取得 30/30 finished、0 timeout/error/recovery、exact formal runtime、正常关闭和受保护存档不变。B11/C12、C9、B9 及其他候选仍完整保留全量普通/长 timeout 分片和既有 timeout 事实，退出基础设施 soak 不删除候选、不构成平衡结论。

v3 全量随后完成 8/198 shard、提交 115 条 durable row、排除 10 条重复且 0 failed。第一次让位来自诊断命令行自身含 producer 关键字，第二次则在 `f-c2-p3` 构建门开始约 7 秒后、0 战斗行时由内部 `arena-tools → run-checks.js → gate-fctl.js --check` 后代进程触发；两次均是 fail-closed 的 `producer_preempted`，不是窗口到期、战斗失败或存档/runtime 污染。v3 事实原样保留，不跨 plan hash 混计到新 campaign。

`gate-f-week-full-v4` 草案把 controller/runner 的祖先和全部后代归入同一受控进程树，树外独立 runner/Flash 仍保持抢占；soak admission 另以唯一 run 目录中的 `resultSnapshotPath` 和 manifest snapshot 锁住实际字节，同时保留报告内原 `resultPath` 的逐字验证，避免固定 batch 输出被覆盖及 admission hash 循环引用。工程门继续覆盖 plan/manifest/decision/admission 篡改、经验 timeout override 真正 Schema 实例与双向语义闭包、低磁盘、active producer、window 到期/撤销、过期 grant 后既有事实提交、partial row exactly-once、重复排除、20-epoch attention 和 exception inbox 去重。v4 尚未 freeze/arm 或实跑；重新三份 fresh soak、真实 20-epoch low-touch、星期级恢复/抢占和 3255-run 候选终态出现前，不得写成 Gate F 通过或全量标定完成。

v4 随后完成 30/30 fresh soak；全量在 16 个 completed shard + 1 个 F2 anomaly shard 后暂停，累计 280 条 durable row、0 duplicate。F2 p2 的 20 行全部 Schema/manifest-bound：原向 10/10 finished，换边 5 finished + 5 个 1800 帧 timeout，0 error，exact runtime、存档不变、正常 shutdown。该事实不能通过重试洗掉，也不能称为平台失败；它已经满足 side-swap 暴露与至少 30 个累计样本中的异常证据，应进入候选低 timeout 筛选和后续 stability investigation。

`gate-f-week-full-v5` 草案把 execution health 与 candidate quality 显式分离：只有纯 `timeout_rate` 超阈值时，shard 仍以完整执行事实提交并生成 `candidate_timeout_anomaly / keep_provisional` deferred item，然后继续下一个 shard；timeout 行继续排除于强度拟合并参与最终候选门。任何 error/污染、duration drift、runtime/save/disk、runner/report/cardinality 异常仍写 failed receipt 并暂停或 fail closed。v4 的 280 行保留但不跨 plan hash 混计；v5 尚未 freeze/arm 或实跑，仍须三份 fresh soak 后才开放全量。

---

## 13. ADR 验收边界

本文的实现验收是：

1. 实际标定闭环可运行、可中断、可恢复。
2. 模型输入输出和采纳过程可冻结重放。
3. 至少完成一次低成本 shadow 消融。
4. 首个模型 profile 有预先定义的证据，而不是凭模型名决定。
5. 人类 PVE 结果进入独立证据链。
6. 安全、身份、可信 L0 manifest、journal continuity 和 exactly-once 计数失败会 fail closed；非法模型 proposal 只被拒绝并回退，不能扩大成 campaign 停机，也不能下发执行。
7. 人类 active / blocked time、主动打断、proposal touch / edit rate 和 exception item / occurrence / affected-scope 满足冻结阈值。
8. 日常内容开发能有界抢占并释放标定资源。
9. 正式建议以 dry-run / apply / rollback bundle 交付，不要求手工翻译。

本文的实现验收**不是**：

- 完成全部怪物的最终平衡。
- 用一次小样本证明 Sol 或 Luna 永久更优。
- 交付通用 Agent orchestration 产品。
- 把一星期累计 campaign 变成一星期不停机单进程。

---

## 14. 开放项

- Sol / Luna 的实际调用面：Codex 原生 subagent、自建 adapter、MCP 或 Agents SDK。
- paired model 的先验、正则强度与区间校准；首版实现已落地但尚未由桥接大样本验证。
- 首批 exact 玩家 build profile、自动进场/目标遥测、体验量表与 holdout 比例。
- shadow 进入在线交错实验的物质增益阈值。
- Campaign 事件账本已由 Node owner 实现；未来迁移 owner 不得改变 §5.3 的 canonical 路径、保留、单 writer、flush、commit 与恢复语义。
- producer registry exact scope、TTL 与当前已打开且响应的 TestLoader observation 已闭合；未来新增 producer 必须先扩 schema/registry 与 fail-closed fixture。
- recommendation apply 工具在现有 Web JS SOT 与未来配置 SOT 迁移间的适配层。

这些开放项不得削弱 §5.3 durable journal、§7.1 action 枚举、Human-attention contract 或 Gate A 的客观闭合；在对应实现 Gate 前必须闭合。

---

## 15. 参考

### 仓库内

- [竞技场斗兽标定平台 — 架构设计与施工计划](竞技场斗兽标定平台-架构设计-2026-06-29.md)
- [竞技场斗兽标定：实验计划与运行日志](竞技场斗兽标定-实验计划与运行日志-2026-07-02.md)
- [CF7 Agent Runtime 与 Wings Network 一期 ADR](CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md)
- [Automation README](../automation/README.md)
- [验证矩阵](../agentsDoc/testing-guide.md)
- [Agent 协作与 harness 实践](../agentsDoc/agent-harness.md)

### OpenAI 官方实践参考

- [Codex Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Agents SDK：manager-style workflows](https://developers.openai.com/api/docs/guides/agents/orchestration#use-agents-as-tools-for-manager-style-workflows)
- [Agents SDK 与 Responses API 对比](https://developers.openai.com/api/docs/guides/agents#compare-the-responses-api-and-agents-sdk)
- [Building Consistent Workflows with Codex CLI & Agents SDK](https://developers.openai.com/cookbook/examples/codex/codex_mcp_agents_sdk/building_consistent_workflows_codex_cli_agents_sdk)

这些外部资料只作为编排模式参考；本文没有引入新的运行时依赖。
