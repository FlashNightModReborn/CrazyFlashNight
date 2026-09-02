# AS2 / WebPanel 止血治理：窗口生命周期、Reward 根事务与软锁归因 ADR

- **文档角色**：跨 AS2 / C# Guardian / WebView2 / Web 的正式止血治理架构决策记录；冻结问题边界、最小架构差量、施工顺序、验证与回滚，并记录 W 的当前施工检查点。本文中的状态摘要不替代 exact candidate、测试输出或 runtime 共识收据。
- **状态**：`W_HUMAN_ACCEPTANCE_PASSED / PROMOTED / FORMAL_BUSINESS_REVALIDATION_PENDING；A/S_SECOND_TRAIN_AUTHORIZED`
- **决策日期**：2026-09-01
- **最后核对代码基线**：W release source `b2a70248eb6fae5dda843d2a7f7156a18b03ef7e`，tree `c35b896578a4b5f7b8751081a600ef374781b589`，deployment `a3b0b5f77027be295cf574c6751310f634067812`。W 开工 Checkpoint-0 `11376feb76116334c68c2cc8632f52650b194abe` / tree `bfbe61dce0ad42de77b5972af00a7893ed08b066` 与原始撰写基线 `dff0c4390b5788151f75954cde397d54fba54257` 只保留为设计考古。
- **调度约束**：维护者已于 2026-09-02 在 exact candidate 上通过 H-W，W 的 immutable request、双故障域共识、promotion、部署与推送均已完成。现继续施工 A/A1 与 S/O1 到第二次真人验收点；第二列车只有在人类通过 H-A/H-S 后才允许提交与部署。
- **当前实现状态**：W/B0 代码、focused/full Launcher 自动门、隔离候选执行、H-W、40/40 production policy、双 signer / 双 faultDomain 共识、严格 preflight、原子 promotion、worktree/index 正式根复验与 bootstrap `--verify-only` 均已完成；deployment 已推送，首次 post-promotion Audit run `33645182028` 通过并精确输出 `state=promoted`、`deploymentChanged=true`。部署后没有重跑正式入口 W 业务旅程，因此只称 `HUMAN_ACCEPTANCE_PASSED / promoted`，不称 W 专项 `standard_entry_verified`。

> 自包含声明：本文不依赖任何 Chat 对话、分享链接、下载文件、模型原始回执或仓库外日志才能理解和执行。现场事实摘要、源码反证、决策、否决项、硬门与施工边界均写在本文中；进一步核查只需本文链接的仓库内源码和 canonical 文档。

---

## 0. 决策摘要

本轮不把反复出现的同步校验、焦点和窗口修补继续当作互不相关的局部 bug。它们共同暴露出两个缺失的发布边界：

1. **窗口几何缺少“验证后才发布”的边界**。瞬态无效几何能够被钳成 `1×1` 或被 fallback 重新包装成合法矩形，并在暂停、窗口组、WebView2 controller、CSS viewport 和修复缓存之间扩散。
2. **Reward Inbox 多 child 领取缺少“副作用前持久化”的根事务边界**。现役 child coordinator 在同一调用中准备并立即写 destination/source；根 operation 只存在于瞬态 authority，重启后 Host/Web 只能根据 projection 猜未知写结果。

因此冻结三条相互解耦的轨道：

| 轨道 | 决策 | 目标 | 发布关系 |
|---|---|---|---|
| **W / B0 Window** | `SELECTED_WITH_REQUIRED_G0` | 在 publication boundary 拒绝无效几何；保存代际绑定的 committed snapshot；同尺寸恢复执行无焦点 presentation replay | 可独立提交、候选、验收和回滚；先就绪则先止血 |
| **A / A1 Authority** | `SELECTED_WITH_REQUIRED_G0` | 为 `reward_inbox` 的单领与批领建立一个 v1 兼容的 durable active root、单 terminal tombstone 与 exact partial result；在首个副作用前形成 `prepare → persist → apply/reconcile` 切口 | AS2 producer 与 C#/Web exact consumer 是同一完成单元，但不与 W 绑定 |
| **S / O1 Observation** | `SELECTED_WITH_REQUIRED_G0` | 用临时、低频、只读探针定位 Web、Host、socket 或 AS2 中最早停止推进的 owner | 可随 W/A 候选携带；不得演变为 watchdog 或自动修复平台 |

同时作出四项否决：

- **否决**仅把四个 dirty 文件覆盖到冻结 HEAD 上作为当前态验证基线；它不是依赖闭包。
- **否决**把 B0 扩张成全局 geometry state core、epoch/revision/latest-wins 调度器或通用 repair framework。
- **否决**把 A1 扩张成全仓 durable workflow、event sourcing、C# Reward 权威迁移或新的 StateCore。
- **否决**把 W 与 A 合并成不可分发布列车；一次人工窗口可以共用，但两条证据必须分别裁决。

本 ADR 是**止血设计**，不是对 AS2/C#/Web 全栈迁移架构的最终重写。若窄边界落地后仍持续产生同类事故，再以新证据另立长期收敛 ADR；本轮不预建未来框架。

---

## 1. 背景、现场输入与证据等级

### 1.1 已知现场输入

以下内容是本 ADR 接受的现场事故摘要。它们用于确定风险与复现旅程，不冒充机器证明：

- 自“关卡结果与基地结算”迁入 C#/Web 分层后，测试员持续遇到焦点恢复、窗口组装和卡顿问题，并发生过多轮针对焦点的局部修复。
- 至少一次窗口生命周期事故中，瞬态窗口尺寸被当成 `1×1` 发布，随后 backdrop、Web overlay、controller、CSS viewport 或输入层使用了被污染的几何，窗口组装散架。
- 最小化、任务栏恢复、QQ/浏览器等外部窗口抢前台，是高频触发环境；修复必须保持“外部窗口在前台时不抢回焦点”的既有 fail-closed 合同。
- 一次软锁现场中，约七分钟没有 blackmarket 交互消息，但 `[Frame:UI]` 仍继续推进。现有证据无法区分“Web 事件循环停止”和“用户没有触发事件”。
- 从结算迁移开始出现的“近乎无法游玩”的卡顿报告是真实的体验风险，但现有计数只能证明某些 layout/focus 路径被频繁调用，尚不能证明 stale callback、WebView2 同步调用或特定窗口 API 是唯一根因。

### 1.2 本文如何使用证据

| 等级 | 含义 | 本轮用途 |
|---|---|---|
| **C：源码确认** | 当前 commit/工作树可直接定位的控制流、状态或 exact key 集 | 可以冻结架构不变量和 focused test |
| **F：现场报告** | 测试员或维护者观察到的行为，缺少完整机器因果链 | 可以定义真人复现旅程，不能单独指定根因 |
| **H：待验证假说** | 对卡顿、陈旧回调或软锁 owner 的解释 | 只能驱动只读探针，不能直接解锁结构扩张 |

本文所有“现役实现如何工作”的陈述均来自 C 级源码复核；F/H 级内容会明确标注。没有把旧测试数字、历史候选或 runtime promotion 当作本轮新实现证据。

### 1.3 与既有决策的关系

本文补充但不推翻以下仓库内决策：

- [关卡结果与基地结算 C# / Web 分层 ADR](../docs/关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md)：AS2 继续拥有关卡与 Loot/Reward 业务权威；C#/Web 负责严格桥接和展示。
- [地图资源箱 S1/S2 ADR](../docs/地图资源箱-S1S2真实战利品容器与Web双栏-ADR-2026-07-18.md)：Loot 的 revision、lease、suspend、close 与一次性语义继续有效。
- [玩家物资事务与双向播报 ADR](../docs/玩家物资事务与双向播报-ADR-2026-08-22.md)：资产写入以权威事务和持久化终点为准，播报不是资产真源。
- [焦点管理长期备忘](../docs/焦点管理-诊断与卡顿排查-2026-05-24.md)：关闭时的前台所有权复核、外部/null fail-closed 不得回退。
- [P0-F 跨层迁移基座与架构收敛专项](../docs/P0-跨层迁移基座与架构收敛专项-2026-07-23.md)：Loot 是业务反例而不是公共基座母版；共享 transport helper 不拥有领域 reconcile 政策。

---

## 2. W 开工前实现的源码反证

本节冻结的是 W 设计与 Checkpoint-0 的反例，不再描述本文件顶部所列 W 工作树。W 当前实现已按 §4 和 §8.1 关闭这些反例；A/S 各节仍是未施工现状。

### 2.1 Window：无效几何能越过 publication boundary

| 位置 | 当前行为 | 风险 |
|---|---|---|
| [`WebOverlayForm.GetCurrentAnchorScreenRect`](../launcher/src/Guardian/WebOverlayForm.cs) | mapper 结果在构造矩形时使用 `Math.Max(1, ...)` | 原始非正尺寸失去 invalid 身份，变成可发布的 `1×1` |
| [`PanelHostController.ComputeAnchorScreenRect`](../launcher/src/Guardian/PanelHostController.cs) | mapper 不可用后依次 fallback 到 Flash panel、owner client，异常时返回 `1024×576` | explicit-invalid 与 unavailable 未区分；错误数据可能被另一来源“合法化” |
| `PanelHostController` tracked open | `AssertWebPanelPause()` 在 `ComputeAnchorScreenRect()` 之前执行 | 若在几何计算之后才拒绝，会留下“游戏已 pause、Panel 未显示”的新软锁 |
| `PanelHostController.ApplyOwnerLayoutChange` | 新旧 anchor/panel rect 完全相等时立即 return | 最小化后恢复到原尺寸，即使 owned overlay 没有被 OS/合成器恢复，也不会重放 presentation |
| `WebOverlayForm.SyncPosition` | panel mode 下立即 return | 普通位置同步无法补上同尺寸 restore |
| `WebOverlayForm.ResumeForPanel` | 调用 `BeginPanel()` 建立新 focus generation，末尾调用 `QueuePanelFocusRestore("panel_resume")` | 完整 resume 不能被直接复用为 restore replay，否则会制造新的抢焦路径 |
| `WebOverlayForm.SchedulePanelViewportRepair` | repair 使用当前 `this.ClientSize` | 如果 ClientSize 已被污染，repair 会把污染状态再次当作真源 |

这些事实共同证明：删除一个 `Math.Max` 不足以止血。修复必须同时覆盖输入分类、side-effect admission、committed snapshot 与同尺寸 restore replay。

### 2.2 Reward：现役 child commit 没有 durable pre-effect cut

| 位置 | 当前行为 | 风险 |
|---|---|---|
| [`RewardInboxService`](../scripts/类定义/org/flashNight/arki/item/RewardInboxService.as) | 顶层 `VERSION=1`；共用 receipt 最多 128 条；`_authority.operations/pendingCommit/pendingPersist` 是进程内对象 | 非终态根领取不能依赖瞬态 authority，也不能塞进会淘汰的共用 receipt 队列 |
| `RewardInboxService.executeLoot` | `claimBatch` 逐 child 调用 coordinator；root operation/terminal 只记录在当前 authority | kill/restart 后无法从持久数据确认整个 batch 到了哪个 child |
| `RewardInboxService.executeClaimBatch` | capacity error 会跳过该 child 并继续；只要 `applied > 0` 就记录本次 operation 成功，剩余 entry 留在 ledger | `committed` 不能被定义成“全部 child 都已领取”；必须另有 exact partial result |
| [`LootClaimCommitCoordinator.beginOrdinary/beginSpecial`](../scripts/类定义/org/flashNight/arki/item/LootClaimCommitCoordinator.as) | 构造 descriptor 并设置 `PREPARED` 后，在同一次调用中立即修改 destination、affinity 和 source | 外层无法在首个资产副作用前强制落盘 prepared descriptor |
| coordinator pending | 保存 `sourceInventory/sourceItem/collection` 等活对象引用 | 重启后不能靠这些引用重绑定或裁决已发生副作用 |
| Reward fingerprint | 使用临时 container、physical slot、lease、container version 等会话状态 | 不适合作为跨文档/进程重启的 root request fingerprint |

现役 Loot/Stage Settlement 已经有 per-operation receipt、strict flush 和 causal recovery；本文并不否认这些能力。缺口专属于 **Reward Inbox 多 child 根操作**：child 级现役机制不能自动推出一个跨重启、可 exact query 的 root terminal。

### 2.3 存档闭包已经存在，但当前未承载 active root

以下源码确认 A1 不需要另建数据库或 C# 存档后端：

- [`通信_lsy_原版存档系统.as`](../scripts/通信/通信_lsy_原版存档系统.as) 将 `_root.强制存盘()` 绑定到 `SaveManager.flushNow()`。
- [`SaveManager.flushNow/packGameState`](../scripts/类定义/org/flashNight/neur/Server/SaveManager.as) 组装玩家状态并写入 SharedObject；`_root._saveExt` 进入 `mydata.ext`。
- `SaveManager.loadFromMydata/unpackGameState` 在背包、药剂栏、collection 等资产恢复后还原 `_root._saveExt`，并调用 Reward Inbox 的归一化/会话重置入口。
- `SaveManager.flushSO` 只有 `SharedObject.flush() === true` 才返回成功；`"pending"`、`false` 与异常均不是 durable success。

因此 A1 的最小落点是现有 Reward Inbox v1 持久 feature 下的可选子结构；仍必须通过真实 save image 的 kill/restart 验证，不能只靠静态路径声称持久化已正确。现役 `SaveManager._applyCore` 会在 Reward normalizer 返回失败时拒绝整份角色存档，因此嵌套 root schema 的隔离策略必须在本文明确，不能把“fail closed”留成两种实现。

### 2.4 Reward exact query 尚不存在

| 层 | 当前事实 |
|---|---|
| AS2 | [`LootContainerValidation`](../scripts/类定义/org/flashNight/arki/item/LootContainerValidation.as) 的 `lootQuery` request exact key 只允许 envelope、现有 identity（含 `containerEpoch/sourceKind`）与 `openAttemptSeq/recoveryNonce` proof，没有 authority revision 或 `rootOperationId` |
| C# | [`LootTask`](../launcher/src/Tasks/LootTask.cs) 的 request/response whitelist 和 sanitizer 没有 root ID、root status 或 root result |
| Web runtime | [`loot-runtime.js`](../launcher/web/modules/loot/loot-runtime.js) 的 exact key 集没有 root 字段 |
| Web state/panel | [`loot-state.js`](../launcher/web/modules/loot/loot-state.js) 与 [`loot-panel.js`](../launcher/web/modules/loot/loot-panel.js) 使用 `authorityRevision / remainingCount / lastAppliedOperationId / slot projection / freshness` 判定未知 write 与 batch 是否推进 |
| Restart discovery | `inboxSummary` 与 `rewardAuthority` 分别由 `ItemUseTask`、`LootPanelCoordinator` exact 校验，当前都没有 recoverable root 字段；`rewardReady` 只由 `remainingCount > 0` 推出 |

这些 projection guard 对普通 Loot 仍有价值；本轮只删除 `sourceKind=reward_inbox` 写结果的猜测式因果裁决。响应丢失后，Reward 不得 retry write 或从 grid delta 猜成功，只能 exact query(root)。

现役 `claim/claimBatch` 已经严格要求 `operationId`；A1 将该字段直接定义为 Reward durable `rootOperationId` 的 wire 表示，不再给写请求增加平行 ID。新增 root ID 只出现在原本缺失它的 query/discovery/response shape。

现役 C# 把 `query` 标为 `IsWrite=false`，但 AS2 在按 command 分派前会续跑当前瞬态 `pendingCommit/pendingPersist`。这说明“transport read”与“完成先前写入”在现行链路中本就并存；A1 必须把边界收紧为**不接纳新意图、只幂等 forward-complete 已 durable root**，而不是把 query 含糊写成纯函数或新增一次未知写。

### 2.5 Softlock：当前 telemetry 无法区分 idle 与 Web loop stop

- [`blackmarket-panel.js`](../launcher/web/modules/minigames/blackmarket/blackmarket-panel.js) 在 open、ready、FX 和用户操作时发送 `minigame_session`，当前没有存活 heartbeat。
- [`WebOverlayForm`](../launcher/src/Guardian/WebOverlayForm.cs) 对 blackmarket `minigame_session` 只记录脱敏事件，没有把 document/socket/Host outstanding/AS2 wait owner 关联成可比较的只读 tuple。
- 因此长时间没有事件只说明“没有事件到达 Host”，不能区分用户 idle、JS event loop stop、Web document/socket 断裂、Host pending 停滞或 AS2 business/pause/scene owner 未推进。

O1 只能增加归因观测；在确定 first stalled owner 之前，不允许添加 timeout、retry、close 或 repair 行为。

### 2.6 原始工作树不能直接作为四文件 overlay 基线

在本文撰写前的只读预检中：

- `HEAD == origin/main == dff0c4390b5788151f75954cde397d54fba54257`，暂存区为空。
- `git diff --name-only` 有 132 个真实 tracked 内容变更；另有百余个且仍随军阀施工变化的 untracked 文件。精确 untracked 数不写成稳定事实，由 Checkpoint-0 的机器 inventory 冻结；`git status` 的 tracked 数更高，其中四项只有状态/行尾差异而没有内容 diff。
- `PanelHostController.cs`、`WebOverlayForm.cs` 与两个现役 focused test 已有在途修改。
- dirty `WebOverlayForm.cs` 引用了当时仍为 untracked 的 `WarlordStageTask.cs`，说明仅复制四个目标文件不能形成可编译依赖闭包。
- `scripts/asLoader.swf` 是当前 dirty 二进制之一；任何完整 checkpoint 都必须按二进制内容保存并记录 hash，不能只保存文本 patch。

结论：partial patch 只能充当冲突地图，不能充当编译、测试或集成证据。该历史风险已由 2026-09-02 的 clean `11376feb...` Checkpoint-0 取代；W 没有覆盖或复用旧 dirty overlay。

---

## 3. 决策驱动与不可破坏不变量

### 3.1 业务与层级权威

1. AS2 继续拥有 Reward ledger、玩家资产、存档和 claim 业务终态。
2. C# Host 只做严格 wire 校验、correlation、路由和保守失败；不得根据 Web projection 创造业务终态。
3. Web 只发送意图、展示 exact result 和管理本地交互；不得重放未知写来“试试看”。
4. Window 由 Guardian/PanelHost 拥有；Web CSS 或 AS2 不裁决 HWND、foreground、owner generation 和 committed screen geometry。

### 3.2 正确性不变量

- **无效几何零副作用**：不得 pause、隐藏 HUD、显示 backdrop、改变 overlay/controller/CSS/shield、创建 focus generation 或抢前台。
- **恢复不等于重新打开**：同一 panel generation 的 presentation revalidation 可以重显，但不能开启新 session/focus generation。
- **副作用前持久化**：Reward child 的 destination/source effect 发生前，root intent 与可重绑定 descriptor 必须 durable。
- **exact-once 不靠推断**：response 丢失后 query；在当前 root 的合法查询窗口内，同 root duplicate 返回既有状态，不同 fingerprint 零 mutation 冲突；后继 root 已确认 supersession 后，旧 root 只返回 `operation_expired`。
- **partial 也是 exact terminal**：批领允许容量受限的部分成功，但必须返回稳定 applied/blocked/remaining 结果；不得把部分成功写成“全部 child 完成”。
- **nonterminal 不淘汰**：active root 不受共用 receipt 容量淘汰；单 terminal tombstone 在后继 root 明确确认前持续可发现，合法 query 不得从 terminal 回退成 `not_started`。
- **嵌套损坏只隔离 Reward lane**：顶层 Reward 未来版本继续按现役规则拒绝整档；v1 内 future/malformed root 保留原数据并 quarantine Reward 写入，不阻止其他角色状态装载。
- **观测无控制权**：heartbeat/probe 不改变业务、暂停、scene、socket、焦点或窗口状态。

### 3.3 工程与发布不变量

- W 开工前必须确认军阀在途施工已不再与 `WebOverlayForm.cs` 等目标文件形成重叠 dirty 闭包；本轮已由 clean Checkpoint-0 满足。
- 每个 production file 在同一施工波次只有一个 owner；跨 owner 只通过已冻结 fixture/join point 对接。
- W 与 A 始终保留独立 commit、candidate、证据和 rollback。
- runtime v2 供应链证据只证明 C#/Web 字节的生产与部署，不能代签 AS2 journal、存档或业务 journey。
- fresh AS2 trace/Compiler/Output/SWF identity 不能代签 C# runtime identity/closure，反之亦然。

---

## 4. W / B0：Window invalid-publication containment

### 4.1 G0-W 必须先冻结的语义

实现命名可以调整，但以下语义是规范性的：

#### 输入分类

anchor 计算结果必须分成三类：

| 分类 | 定义 | 允许行为 |
|---|---|---|
| `valid` | 来源可用，矩形有限、正尺寸，且不是已知 minimized/transient sentinel | 可以生成 panel rect 并提交 snapshot |
| `explicit-invalid` | 来源明确返回非有限、非正、minimized/sentinel `1×1` 或与当前 owner/generation 不相容的矩形 | 立即 fail closed；禁止 fallback 和全部 presentation side effect |
| `unavailable` | 来源确实无法提供读数，而不是提供了错误读数 | 可以尝试下一个独立可验证来源；所有来源 unavailable 时 fail closed |

不得用 `Math.Max(1)`、默认 `1024×576` 或另一来源 fallback 抹去 explicit-invalid 的因果身份。下游在已经证明 valid 的前提下可以保留防御 clamp；本轮不机械删除所有 `Math.Max`。

#### provisional measurement → committed snapshot

打开路径必须区分“已验证的候选测量”和“已经随成功 presentation 发布的 committed snapshot”。仅仅算出 valid rect 不能提前把它冒充为活动窗口事实。

在读取 geometry 前先预留一个**本地 open identity**，但不得调用 `BeginPanel()` 或创建 focus generation：

- tracked open 复用调用方已经预留的 `panelInstanceId`；
- ordinary open 由 `PanelHostController` 在 geometry 前分配只供本次打开尝试使用的 identity；
- identity 预留不 pause、不显示窗口、不修改 controller/CSS/shield，也不赋予焦点资格。

valid measurement 先形成 provisional snapshot，至少绑定 owner HWND/handle generation、local open identity、anchor/panel rect、source/provenance、monitor/DPI identity。它只用于本次 admission，不得被 repair、restore 或其他 callback 当作活动 snapshot 读取。

只有 pause/suspend 交付成功、`ResumeForPanel` 建立活动 panel/focus generation，且 overlay/controller presentation 被接受后，才能把 provisional snapshot 提升为 committed snapshot。committed snapshot 至少绑定：

- owner HWND 与 handle generation；
- 活动 panel instance 与 focus generation；
- anchor screen rect 与 panel screen rect；
- source/provenance 与最近一次 valid 原因；
- 足以判断 monitor/DPI identity 是否仍属于同一代的信息。

同一代 transient invalid 不覆盖或清空旧 committed snapshot，也不得把旧 snapshot 当作一份“新测量”再次提交。新 panel、owner handle 重建、monitor/DPI identity 改变且本代没有 valid snapshot 时 fail closed；旧代 snapshot 不得跨代复用。

#### admission 顺序

tracked 与 ordinary open 都遵守同一顺序：

```text
预留 local open identity（不创建 focus generation）
  → 读取并分类 geometry
      ├─ explicit-invalid / exhausted-unavailable
      │    → 丢弃本次 identity/provisional，返回失败，零 presentation mutation
      └─ valid → 形成 provisional snapshot
                   → AssertWebPanelPause + companion/HUD suspend
                   → backdrop capture/show
                   → ResumeForPanel 建立活动 panel/focus generation
                   → overlay/controller/CSS/shield presentation accepted
                   → provisional 提升为 committed snapshot
```

几何 admission 必须早于 `AssertWebPanelPause()`、HUD/companion suspend、backdrop capture/show 和 focus generation。pause、open 或 presentation delivery 任一步失败，都必须走现役 pre-open cleanup、丢弃 provisional，且不得留下可供 restore/repair 使用的新 committed snapshot 或半个窗口组。

### 4.2 同尺寸 restore 的无焦点 presentation replay

当 owner 从 minimize/hidden 恢复、当前测量重新 valid，但 anchor/panel rect 与 committed snapshot 完全相同时，`geometryChanged == false` 不能直接结束整个流程。必须执行一次幂等 revalidation replay：

- 恢复/确认 backdrop 与 Web overlay visibility；
- 用 committed panel rect 重放 Form 与 WebView2 child/controller bounds；
- 必要时执行现役 compositor kick；
- 重发同一尺寸的 CSS viewport/resize 通知；
- 重新确认 shield telemetry rect 与窗口组 z-order；
- 更新本代“已完成 restore replay”原因/bit，抑制同一恢复事件的重复重放。

该 replay 明确禁止：

- 调用 `BeginPanel()` 或增加 panel/focus generation；
- 调用 `QueuePanelFocusRestore`、`SetForegroundWindow`、controller focus 或任何抢前台路径；
- 重新发送业务 open、重新建立 Loot authority 或改变 close eligibility；
- 用当前可能被污染的 `ClientSize` 替代 committed rect。

允许引入一个**本地、代际绑定的 restore-revalidation reason/bit**；它不是全局 geometry epoch 或 publication scheduler。该 bit 的状态机固定如下：

- 只在同一活动 generation 已有 committed snapshot，且观察到 minimize/hidden、layout-time explicit-invalid，或明确表示 presentation 被 OS/owner 撤回的 restore signal 时置位；初次打开的 invalid 不得置位；
- 普通 layout callback 即使 rect 与 committed rect 相同，也不能自行置位；没有 bit 的 same-rect callback 继续 no-op；
- 下一次同 generation valid layout 恰好消费一次：same rect 执行一次 replay 后清除，rect 改变则走正常 geometry update 并清除；
- panel close、open/presentation failure、owner handle/panel/focus generation 改变、monitor/DPI identity 改变时清除；旧代 bit 不得迁移。

置位只记录“本代 presentation 需要复核”，不修改窗口、焦点或业务状态，因此不构成 invalid geometry 的 presentation side effect。

### 4.3 repair 真源

`panel_viewport_repair` 必须显式接收或读取本代 committed geometry。若没有本代 snapshot，repair fail closed；不得以 `this.ClientSize` 自我证明当前尺寸正确。

### 4.4 B1 延期

本轮不建设 stale-callback arbitration。调用次数或 burst 数量只证明调用发生，不能证明旧 callback 覆盖了新矩形，也不能证明它是卡顿主因。

只有观测到以下完整反例，才允许另开 B1：

1. 较旧 callback 在时间上晚到；
2. 它覆盖了较新的、已验证的 full rect；
3. 现役 owner/panel/focus generation 无法拒绝；
4. 覆盖造成可见错误或可测成本。

即使解锁，B1 也只做最小局部 arbitration，不自动授权全局 revision/latest-wins。

---

## 5. A / A1：Reward Inbox durable root journal

### 5.1 结构边界与存档兼容矩阵

在现有 Reward Inbox 顶层 `v=1` 持久 feature 中只增加两个可选子结构：至多一个 `activeClaimRoot`，以及至多一个紧凑的 `claimRootTerminal` tombstone。`claim` 视为只有一个 child 的 root，`claimBatch` 使用同一协议；不得做不兼容的顶层 `VERSION` 升级，不得创建多领域 operation registry。

normalizer 的行为固定如下，避免“fail closed”被实现成两种互斥含义：

| 输入 | 归一化结果 | 其他角色状态 |
|---|---|---|
| Reward feature 缺失，或 `v=1` 且缺少两个新字段 | 补为空结构，正常继续 | 正常装载 |
| 顶层 Reward `v != 1` | 保持现役 `future_reward_inbox` 规则，拒绝整份 save | 不装载 |
| `v=1` 且 nested root/tombstone schema 已知并合法 | 精确归一化 | 正常装载 |
| `v=1` 且 nested `claimRootSchemaVersion` future/malformed | 原样保留 opaque nested payload 与诊断，Reward lane 标记 `quarantined`，禁止 Reward 写入和自动续跑 | normalizer 整体返回可装载，其他角色状态继续装载 |

任何 nested 异常都不得静默丢字段、回落为空 root 或把未知版本当作 `not_started`。G0-A 必须冻结 opaque 保存/再写回方式和诊断字段，focused test 必须证明 Reward lane quarantine 不升级成整档拒绝。

### 5.2 最小持久字段

`activeClaimRoot` 至少包含：

- `claimRootSchemaVersion`、`rootOperationId`（来自现役 write `operationId`）、`commandKind=claim|claimBatch`；
- 稳定 request fingerprint 与被确认的 `previousTerminalRootOperationId`；
- 有序 Reward `entryId` 列表、`cursor`、`appliedCount`、`rootStatus`；
- 当前 child ordinal；
- 当前 child 的逻辑 reconcile descriptor：
  - Reward `entryId`；
  - item name、quantity 与不可变签名；
  - destination domain 与稳定 locator；
  - destination exact before/after；
  - source ledger exact before/after；
  - 涉及药剂栏时的 affinity before/after；
  - child phase；
- 当前 exact result 累积：`appliedEntryIds`、逐 entry 的 `blocked/error`、`remainingEntryIds`、`appliedCount` 与 `stopReason`。

`claimRootTerminal` 至少保留 schema/version、root ID、command/fingerprint、`rootStatus`、`resultKind`、`discoveryAcknowledged`，以及同一份 exact result。它不再保留进程对象或已经不需要 reconcile 的重型 child descriptor。

不得持久化 `ArrayInventory`、item、collection 等进程活对象引用。reload 必须根据稳定 locator/entryId 重新绑定并核对 before/after；无法唯一重绑定或发现状态不变量冲突时，active root 进入 `quarantined`，禁止猜测或自动继续。

### 5.3 root identity、状态与 partial result

fingerprint 只基于跨重启稳定的事实：有序 `entryId`、命令语义、数量/不可变签名和目标 domain。不得纳入 physical slot、slot lease、临时 container id/version 或 Web document identity。

最小状态集固定为：

```text
not_started | pending | committed | terminal_failure | quarantined
```

- `not_started` 只用于查询一个从未成功 admission 的 root；它不是持久 active 状态。
- `pending` 表示 intent 已 durable，apply/reconcile 尚未形成 durable terminal。
- `committed` 表示命令形成了 durable 成功终态；它可以是全部领取，也可以是现役语义允许的“仅容量阻塞”部分领取，绝不等价于“全部 child 完成”。
- `terminal_failure` 表示权威已经作出可重复查询的最终失败；它可以携带失败前已经 durable 的 exact partial effects。
- `quarantined` 表示 active journal 的重绑定或不变量不足以安全继续；它保持可发现、可查询，禁止自动 mutation，也不压缩成普通 terminal tombstone。

exact response 的 `resultKind` 与状态对应关系固定为：

| `resultKind` | 条件 | `rootStatus` | exact 结果要求 |
|---|---|---|---|
| `none` | root 从未成功 admission | `not_started` | 空 result，`appliedCount=0` |
| `in_progress` | root 已 durable、尚未收束 | `pending` | 返回当前 durable applied/blocked/remaining，不推断未落盘 effect |
| `all_applied` | 所有请求 child 已应用 | `committed` | 全量 `appliedEntryIds`，remaining 为空 |
| `partial_applied` | `appliedCount > 0`，未应用项全部只因容量受限 | `committed` | applied、capacity-blocked 与 remaining 精确分列 |
| `no_effect_capacity` | `appliedCount == 0`，全部/首个可执行项因容量被拒 | `terminal_failure` | 零 applied，保留 capacity error 与 remaining |
| `partial_failed` | 已有 durable applied，随后出现非容量错误而停止 | `terminal_failure` | applied 与失败点/未处理 remaining 精确分列 |
| `failed` | 尚无 applied 即遇到确定性的非容量业务错误 | `terminal_failure` | 零 applied，保留 exact error/stop reason |
| `quarantined` | rebind/invariant 不足以安全续跑 | `quarantined` | 返回已知 durable partial、opaque/error 诊断与 remaining，零自动 mutation |

`quarantined` 保持 active journal，不压缩成 terminal tombstone。remaining entry 只能在前一 tombstone 被后继 root 明确确认后，以新的有序 source list 和 fingerprint 进入新 root。

同 `rootOperationId + fingerprint` 的 duplicate 返回或继续既有 operation；同 root 不同 fingerprint 返回 `operation_conflict` 且零 mutation。已有 `pending/quarantined` active root 时拒绝新 root，并通过 discovery carrier 暴露当前 root。

malformed payload、foreign identity、stale authority 或 root/fingerprint conflict 属于 **protocol admission rejection**：不建立新 root，也不产生业务 mutation。

identity、root ID/fingerprint 与有序 entry 已通过 admission 后，capacity、row materialization 和 destination planner 才属于该 root 的**业务结果**；即使零资产效果，也必须先 durable 再返回 `no_effect_capacity/failed/quarantined`，从而允许 duplicate exact query。

### 5.4 prepare → persist → apply/reconcile

必须在现有 `LootClaimCommitCoordinator` 内增加窄切口，避免在 `RewardInboxService` 复制一套 destination/source planner：

```text
1. validate + freeze ordered source entries、现役 operationId/root fingerprint 与 predecessor acknowledgement
2. coordinator.prepare(child) → 纯逻辑 descriptor 或确定性 capacity/business decision，零资产副作用
3. 原子持久化 active root + prepared child/business decision，并在适用时 supersede 已确认 tombstone；强 flush 必须 === true
4. coordinator.applyOrReconcile(descriptor)
5. source + destination + affinity 精确收敛
6. 持久化 child completion、exact partial result、cursor/appliedCount；强 flush 必须 === true
7. 按矩阵继续下一 child、跳过 capacity-blocked child，或收束 non-capacity failure
8. 将 committed/terminal_failure 从 active 原子转成单个 claimRootTerminal；强 flush 必须 === true
9. 才向 Host/Web 返回 terminal；quarantined 保持 active 并返回 exact blocked 状态
```

flush `false`、`"pending"`、throw 或进程终止都不得当成 durable success。response 丢失后不重放 write，只执行 exact query(root)。query 若幂等推进既有 durable descriptor，也必须逐 cut 遵守同一 flush 与 exact-result 规则。

### 5.5 restart discovery、root admission 与 Reward-only exact query

只给 query 增加 root ID 不足以恢复，因为 Web document 重建后可能已丢失原 ID。三类现役 carrier 的责任固定为：

| Carrier | 责任与新增语义 |
|---|---|
| `inboxSummary` | **首要 restart discovery carrier**；新增 `recoverableRootOperationId`、粗粒度 `recoverableRootStatus`、`recoveryRequired` |
| `rewardAuthority` | 与当前 Loot identity 精确绑定的恢复 carrier；镜像上述 root identity/status，并在没有 remaining row 但仍需恢复时允许 `recoveryOnly=true` |
| `lootQuery` response | 返回指定 root 的详细 `rootStatus/resultKind/result/appliedCount/error/stopReason`；不得用 summary/projection 代替 |

`recoveryRequired` 在 active root 为 pending/quarantined，或 terminal tombstone 尚未完成 discovery acknowledgement 时为 true。`rewardReady` 固定为 `remainingCount > 0 || recoveryRequired`。

因此即使 `remainingCount == 0`，系统仍能建立 recovery-only Reward authority 并 exact query。已 acknowledgement 的 terminal tombstone 仍在 summary 暴露 root ID/status，但不再制造永久的“待领取”假阳性。

`ItemUseTask`、`LootPanelCoordinator` 与 `LootTask` 的 exact validators 必须共同接受同一受限 shape，不能由某一层静默剥掉 discovery 字段。

现有 action 继续复用，不新增平行 action。G0-A 一次冻结以下 allowed-key/type fixture：

| 方向 | 必需新增语义 |
|---|---|
| Web/Host → AS2 `claim/claimBatch` | 现役 `operationId` 直接充当 root ID；新增 `previousTerminalRootOperationId`（当前没有 tombstone 时为空），并继续携带现役 identity/revision；二者参与严格 admission |
| Web/Host → AS2 `lootQuery` | `rootOperationId`，可选 `acknowledgeTerminalRootOperationId`；继续携带现役 panel/container/recovery identity；foreign/malformed root fail closed |
| AS2 → Host/Web Reward response | `rootOperationId`、`rootStatus`、`resultKind`、exact `result`、`appliedCount`；失败/阻断时带受限 `error/stopReason` |
| Reward `inboxSummary/rewardAuthority` | 上表定义的 discovery 与 recovery-only 字段 |

AS2、C# 和 Web 必须生产/消费同一 fixture。不得先让 producer/consumer 各自猜 shape，再靠兼容分支收敛。

`lootQuery` 的因果合同固定为：

- C# transport 分类继续是 `IsWrite=false`；query request 本身不得创建 root、child、fingerprint 或任何新业务意图；
- AS2 只允许依据**已经 durable 的 active root/descriptor**幂等 forward-complete，不能根据 Web projection、freshness 或客户端 payload 创建/裁决资产事实；
- Host/Web 在拿到 exact terminal 前保持 `recovery_required`，不得把 query timeout 当作 write unknown、不得 replay 原 claim，也不得以 projection delta 推断成功；
- query response 再次丢失时，active root 或未 acknowledgement 的 terminal tombstone 仍会要求 discovery；重复 query 收敛到同一 exact 状态；
- `acknowledgeTerminalRootOperationId` 只有在客户端已成功消费同 root 的 exact terminal 后才能发送，只改变 tombstone 的 discovery bit，不删除 exact result、不授权新 root，也不产生资产副作用。

### 5.6 单 tombstone 的 discovery acknowledgement 与 supersession

active nonterminal 永不受现有 `MAX_RECEIPTS` 淘汰。`committed/terminal_failure` 落盘时由 active root 转成唯一的 `claimRootTerminal`，初始 `discoveryAcknowledged=false`；query、panel close、document teardown 和普通 snapshot 均不得清除它。

客户端成功消费 exact terminal 后，可以用同一 `lootQuery` 发送 `acknowledgeTerminalRootOperationId`。AS2 只在它精确匹配当前 terminal 时幂等持久化 `discoveryAcknowledged=true`；不匹配时零 mutation 失败。ack response 丢失是安全的：客户端在发送前已经取得 exact terminal，而 tombstone 仍保留并继续回答 duplicate；差异只在下次是否需要主动恢复展示。

下一 root 的 admission 是唯一 supersession 机制：

1. 没有 tombstone 时，新 request 必须携带空 `previousTerminalRootOperationId`；
2. 有 tombstone 时，新 request 必须携带与其完全相同的 `previousTerminalRootOperationId`；缺失或不匹配返回 conflict，零 mutation；
3. coordinator 已 prepare 且零资产副作用后，在同一次 durable write 中移除被确认 tombstone、建立新 active root；flush 未返回 `true` 时旧 tombstone 仍是权威，新 root 未 admission；
4. admission response 丢失时，客户端已知自己以现役 `operationId` 提交的新 root ID，restart discovery 也会暴露它；不得重建旧 root；
5. successor admission 后查询旧 root 返回受限 `operation_expired`，不得回退成 `not_started`。若永远没有 successor，单个紧凑 tombstone 持续保留。

这一规则用“至多一个 active root + 至多一个 terminal tombstone”换取可机械证明的 discovery acknowledgement 与 supersession，不引入 tombstone 队列、TTL 或后台清理器。

### 5.7 无效 Reward row

当前存在“remaining 统计包含某 row，但 materialize 静默跳过”的双域风险时，不得继续依赖 UI projection。protocol identity/root admission 成功后、首个 child effect 前，必须二选一并 durable：

- 将 root 收束为 `terminal_failure` 并返回 exact invalid-row result；或
- 把 root/child 标记为可查询 `quarantined`，零后续 mutation。

不得静默跳过后继续报告整个 batch committed。

本轮不扩展 Reward 类型能力。现役分类仍只覆盖 `material / information / ordinary`；money、K 点、经验、技能点等 standard Loot scalar 不进入 A1，也不增加对应 post-commit 行为或测试门。

---

## 6. S / O1：软锁最小归因观测

### 6.1 目标

一次主动复现的目标是指出**最早停止推进的 owner**；证据链至少覆盖以下可区分层级：

```text
Web event loop / document
→ MinigameHostBridge / socket
→ Host route / outstanding request
→ AS2 business operation / pause owner / scene owner
```

O1 不修复软锁，只缩小下一次修复的故障域。

一次采集的合法结论不强迫命中某个故障 owner，固定允许：

- `first_stalled_owner=<named layer>`：只有存在具名 outstanding operation，且跨层 identity/sequence 能证明最早停止点时成立；
- `no_outstanding_operation`：采集窗口内没有待完成业务，不能制造“卡住”结论；
- `user_idle`：有足够输入/交互证据证明只是没有用户动作；
- `inconclusive`：证据不足或身份链断裂，保留缺口并停止归因。

heartbeat 存活只证明相应 Web document 的定时回调曾推进；它不能单独证明 socket、Host route 或 AS2 owner 正常。heartbeat 静默也不能单独证明 Web event loop 是 first stalled owner。

### 6.2 允许的最小变化

1. blackmarket 增加低频、feature-gated、生命周期有界的 heartbeat；随 panel close/rebind/document teardown 清理。
2. heartbeat 只携带现有 identity 和只读状态，例如 panel/document generation、单调 sequence、snapshot revision、pending bit；不得携带玩家敏感数据或全量 payload。
3. Host 在 `WebOverlayForm.cs` 的现役 `minigame_session` 路由内记录一个极窄关联 hook，把 heartbeat 与现有 ready/socket generation、route/outstanding 状态关联。
4. AS2 只在 G0-S 明确列名的 wait-owner 位置增加只读 tuple；不横扫全仓日志。
5. 日志有界、脱敏、可删除。第一个 owner 被确认后删除 heartbeat 或默认关闭并降到手动诊断入口。

### 6.3 明确禁止

- heartbeat timeout 自动 close/reload/retry/repair；
- 通用 watchdog 或健康平台；
- 改写 await、pause、scene、socket 或窗口行为；
- 因 heartbeat 静默直接判定 Web 卡死；
- 在一次清晰归因后继续无限增加探针。

只有第一次主动复现仍无法区分 owner 时，才允许针对同一假说做第二次采集。

---

## 7. 施工调度、所有权与 join points

### 7.1 W 独立开工裁决

2026-09-02 复核确认军阀重叠源码与依赖闭包已经收束：`HEAD == origin/main == 11376feb76116334c68c2cc8632f52650b194abe`、工作树干净、仅一个 worktree。维护者随后明确授权 W 先行施工到 H-W，而不等待军阀持续数天的产品验收。该裁决只解锁 W/B0，不解锁 A/A1、S/O1，也不允许在 H-W 之前提交或启动正式发布。

W 没有沿用原始四文件 overlay。开工前的全量 Launcher 基线为 SDK resolver **7/7**、Launcher **4509 passed + 3 explicit opt-in skipped / 4512 total**；由此把后续失败归因边界固定在 clean Checkpoint-0。

### 7.2 Checkpoint-0

若未来再次从 dirty 工作树开工，Root 仍必须创建完整可恢复 checkpoint，覆盖：

- 所有 tracked 内容差异；
- 所有相关 untracked 文件；
- 二进制 `scripts/asLoader.swf` 及其他运行时资产；
- 文件 inventory、逐文件 hash 与恢复说明；
- `PanelHostController/WebOverlayForm` 的完整编译依赖闭包；
- 零止血 patch 状态下的 baseline build/focused test 结果。

本轮军阀施工已经提交且工作树干净，因此冻结上述 commit/tree 加零残余状态清单即构成 Checkpoint-0；没有为了形式制造另一份大型副本或 worktree。

### 7.3 修正后的并发 DAG

```text
ADR 已确认并以 docs-only 提交冻结
                 │
          wait for Warlord closure
                 │
                 Checkpoint-0 + rebase audit
                         │
Wave 0（只读，可并行）
 ├─ Root：完整依赖闭包 / build / release gate inventory
 ├─ W：geometry 输入、mutation、restore 反例与 focused test
 ├─ A：descriptor、save boundary、fault cut 与 reload rebind
 └─ S：Reward inference exact-set、softlock wait-owner inventory
          │
          ├─ G0-W：geometry admission / restore replay
          ├─ G0-A：root journal / exact query / restart discovery
          └─ G0-S：heartbeat / outstanding / AS2 wait tuple
          │
Wave 1
 ├─ W：B0 + Window tests + WebOverlay 内 Host observation hook
 ├─ A：AS2 durable producer + coordinator prepare/apply seam + AS2 tests
 └─ S1：blackmarket heartbeat + 非 Window wait-owner probes
          │
          ├─ J-W：W clean evidence → current integration base
          └─ J-A-contract：AS2 exact fixture/status/restart 语义冻结
                                      │
Wave 2                              S2
                           Host/Web exact query consumer
                           + Reward inference deletion
                                      │
                                  J-A
                                      │
                         C-W 与 C-A 独立 candidate
                                      │
                     可共用一次 H，分别裁决 H-W/H-A/H-S
```

### 7.4 文件所有权

| Owner | 独占 production files | 责任 | 禁止 |
|---|---|---|---|
| **Root** | integration base、G0 fixtures、最终 canonical docs/release records | Checkpoint-0、冻结 G0、单点合并、J-W/J-A、候选与回滚清单 | 不代替 feature owner 写实现；不把 partial overlay 当基线 |
| **W** | `PanelHostController.cs`、`WebOverlayForm.cs`、优先新增的 Window focused tests | B0 与 `WebOverlayForm` 内 O1 Host hook | 不改 Loot/AS2；不改 focus eligibility；不加通用 timer/geometry framework |
| **A** | `RewardInboxService.as`、`LootClaimCommitCoordinator.as`、`LootContainerValidation.as`、`LootContainerService.as` 中 Reward routing、AS2 focused tests/fixture | durable producer、prepare-before-effect、reload rebind/quarantine、exact query producer | 不写 Host/Web；不建共享 durable runtime；不持久化活对象 |
| **S / A consumer** | `LootTask.cs`、`ItemUseTask.cs`、`LootPanelCoordinator.cs`、Loot Web 三文件及 focused tests | J-A-contract 后实现 discovery/exact validators、S2 exact consumer 和 Reward inference deletion | 不写 AS2/Window；不定义 business terminal；不加 retry |
| **S / O1** | `blackmarket-panel.js`、G0-S 后明确列名的非 Window wait-owner 文件 | S1 观测与 bounded correlation | 不写 Window files；不加 retry/watchdog/control behavior |

原始撰写时 Window focused test 曾经 dirty，但该状态已由 clean Checkpoint-0 取代。W 新增 `PanelGeometryLifecycleTests.cs`，并只为新合同调整三个既有 source-contract test 与 Router 预暂停断言；未覆盖在途版本，也未修改 AS2/Loot/Reward 文件。

### 7.5 唯一 join points

1. **Checkpoint-0**：证明止血前真实基线可恢复、可编译；失败先归因基线，不能让 W/A patch 替罪。
2. **G0-W**：冻结 valid/explicit-invalid/unavailable、pre-pause admission、snapshot identity、same-rect replay。
3. **G0-A**：Root+A+S 共同冻结持久字段、wire fixture、restart discovery 和 fault semantics。
4. **G0-S**：Root+W+S 冻结观测 tuple 与 `WebOverlayForm` 单 owner hook。
5. **J-W**：W 在隔离基线上通过 focused 证据；Root 合入当前 integration base 后再编译/定向回归。
6. **J-A-contract**：AS2 exact fixture 和 persisted result shape 通过后才解锁 S2。
7. **J-A**：producer + consumer、fault cuts 与 Reward zero-inference 共同通过。
8. **C-W/C-A**：两个独立 candidate；不以 mega-candidate 作为唯一证据。

---

## 8. 验证合同

### 8.1 W / B0 patch 合并前硬门

- mapper explicit-invalid 不进入 fallback。
- invalid open 对 bounds、controller、CSS、shield、visibility、focus 和业务 pause 均为零 mutation。
- 首次打开/新 generation 无 valid snapshot 时 fail closed，不留下 orphan pause。
- 同代 transient invalid 保留旧 committed snapshot，但不跨 owner handle/panel generation 复用。
- minimize → same-rect restore 触发一次且仅一次 focus-free presentation replay。
- replay 不调用 `QueuePanelFocusRestore`、`SetForegroundWindow`、controller focus 或业务 open。
- repair 只读 committed geometry；以当前 `ClientSize` 为真源的路径不可达或删除。
- 既有 close eligibility、关闭前/恢复前 live foreground recheck、external/null fail-closed tests 全绿。

### 8.2 A / A1 patch 合并前硬门

- v1 旧存档缺失新字段时可规范化；顶层未来 Reward 版本继续拒绝整档；v1 nested future/malformed root 原样保留并只 quarantine Reward lane，其他角色状态可读回。
- active nonterminal 不受 `MAX_RECEIPTS` 淘汰。
- stable entry list、fingerprint 和 reload rebind 可机械验证。
- prepared descriptor 强 flush 成功前 destination/source mutation 计数为零。
- 代表性 fault cuts：
  1. root intent flush 前；
  2. intent 已落盘、destination effect 前；
  3. destination after、source before；
  4. source after、child completion flush 前；
  5. middle child completion 后、next child 前；
  6. last child effect 后、root terminal flush 前；
  7. terminal 已落盘、response 前。
- flush false/`pending` 与 throw 均覆盖。
- 使用真实 persisted save image kill/restart，而不只是在同进程调用 test reset。
- same fingerprint duplicate 恰好一次；conflicting fingerprint 为零 mutation。
- `claim` 单 child 与 `claimBatch` 多 child 均经过同一 root 协议；§5.3 全部 `resultKind` 逐项验证 exact result、状态约束与 duplicate。
- ordinary empty、ordinary merge、material、information，以及实际可达时的 drug/affinity 各有代表样本；明确不新增 Reward scalar 能力。
- invalid row 在 admission failure 或 quarantine 中形成 exact 结果。
- terminal tombstone 不被 query/close/restart 清除；discovery acknowledgement 只改变 bit，ack response loss 不影响 exact duplicate。
- 后继 admission 的 predecessor ack、原子 supersession、response loss 与旧 root `operation_expired` 均有测试。
- `remainingCount == 0` 且 recovery 未 acknowledgement 时，仍可通过 `inboxSummary → recovery-only rewardAuthority → lootQuery` 找回 exact 状态；ack 后 `rewardReady` 可回落但 tombstone 仍可 query。
- `rootOperationId/rootStatus/resultKind/result/appliedCount` 的 AS2↔C#↔Web fixture exact 一致，`ItemUseTask/LootPanelCoordinator/LootTask` exact validators 不剥离字段。
- query 不创建新 intent；只 forward-complete 已 durable descriptor。query response 丢失后重复 discovery/query 返回同一 exact 状态，Host/Web 始终不重放 claim 或使用 projection 推断。
- stale、foreign、malformed root response fail closed。
- 机械 exact-set 证明 `reward_inbox` write 结果不再由 projection delta、freshness、write retry 或 detached state 推断。
- 标准 Loot/Stage Settlement 行为不因 Reward 特例退化。

### 8.3 S / O1 硬门

- probe 只读取现有状态，不改变 await、pause、scene、socket、Web 或 Window 行为。
- 每条记录带现有 panel/document/socket/business identity，有界且脱敏。
- heartbeat 随 close/rebind/teardown 清理；没有 timeout、retry、repair 或自动 close。
- 每次主动复现只输出 `first_stalled_owner / no_outstanding_operation / user_idle / inconclusive` 之一；后两者和 inconclusive 都是合法结果，不为通过测试而虚构根因。
- heartbeat 单独存活或静默都不能推断下游 owner 状态。

### 8.4 Candidate 门

#### C-W

- Guardian focused tests。
- 在**完整当前依赖闭包**上运行一次 B 相关 Launcher suite；不要求每个 owner 重跑 full suite。
- 真实 Windows candidate 绑定实际 EXE/Core/payload closure。
- candidate-executed 的 HWND、taskbar、foreground、WebView2 实证。

2026-09-02 机器检查点：新增 W 生命周期合同与受影响 Router/Host tests **266/266**；随后 canonical `launcher/tests/run_tests.ps1` 取得 SDK resolver **7/7**、Launcher **4516 passed + 3 explicit opt-in skipped / 4519 total**。隔离候选 `c-7bd7cb663ffe-08846e81b3-20260902t120840656z-8f558f09` 已由 `automation/start.ps1 -CandidateRoot` 通过 33-file integrity、manifest/metadata、实际 Core 进程路径与 bus-ready 核验，达到 `candidate_executed / NOT_DEPLOYED`：

- build identity `7BD7CB663FFE7F338BBAA5566CD738B22A106A0835D272A7498D43C2EBE7972D`；
- payload closure `F59DB97F0F6302FDF5F2F9934FEA07394FA8B135E7F5B6E0B690A60C9078D331`；
- Core DLL SHA-256 `82C94E7B35C3311F4DCC62FE0FBF2E0835C3838DC4D111CFE23778583E1F2BAB`；
- 正式 Core 仍为 `A5F84FDA978839869FD5B47170D652E40DDB534357E483AA71D2C0CE3D58E476`，formal closure 未改写。

上述机器结果本身不代签 taskbar、foreground 与肉眼 WebView2 presentation；该门随后由下方 H-W 关闭。该隔离候选不是正式发布证明，也没有被手工复制进正式 runtime。

#### W 正式发布检查点

W 实现与 H-W 先由 commit `28edc13560` 落盘；新机构建环境随后注册不可导出本地 X509 `builder-local-c` / `physical-host-c`。首个 immutable tag `runtime-build-v2/20260902-window-lifecycle-w1` / request `AE7B4246693EAF19B66D1F92D82A6A4EE51A653D22B514B52E0B238B57CBECD9` 在本地 production policy 暴露材料字典 raw-byte sidecar 过期后停止，未 dispatch 云构建、未 promotion；tag 保持不可变，由 W2 全新 request supersede。

最终 release source `b2a70248eb6fae5dda843d2a7f7156a18b03ef7e`（tag `runtime-build-v2/20260902-window-lifecycle-w2`）、release tree `c35b896578a4b5f7b8751081a600ef374781b589`、request commit `d90c901f863406d4fd4f8cf50d1167a9d579b9a5` 与 request `981A0D150FFDCDB1B2B430E44DE6B9D2FBE76726B8EAA515711950325A731096` 形成 build identity `7BD7CB663FFE7F338BBAA5566CD738B22A106A0835D272A7498D43C2EBE7972D`。本地 X509 keyId `CFB70E2D339ACB25E9B6C2873DF4F1AEEBA8EA75AD23B825724B27FCA70C0B86` / `physical-host-c` 与 GitHub OIDC/Sigstore builder `8B958CC4E6C87DC7D9406842EA1AC0CEBAF8D4FFFE93332BC4AD421D893CFD8D` / `github-hosted-windows`（cloud run `33641807449`）对 33-file payload closure `DBAD534395A8383DFD29DF0321BFEE39AC30040763A957E8260013E6D480F18A` 达成双 signer、双 faultDomain 共识。

40/40 production receipt SHA-256 为 `869F8855B37274D3FD88F47877E040C4A27628E81D590357891107EFE58BD2E7`；正式 Core DLL / manifest / consensus SHA-256 分别为 `3B346B9818FFACC536B250BC2CB41D9FD67FE19B8D74CD82DF2527430226A361`、`9D888B3BE393BDAB4CF10C74ECF912E6F2744867A15707B4819A7B42DC7E1E01`、`8DCD3B45730ED595F2A558A1C6539E39D2F06A9202F12E401669DC6F33AD6220`。严格 `VerifyOnly` preflight 明确零 runtime/release-state mutation，随后原子 promotion、worktree/index bundle、signed consensus、GitHub proof replay 与正式根 bootstrap `--verify-only` 均通过；deployment commit `a3b0b5f77027be295cf574c6751310f634067812` 已推送，post-promotion Audit run `33645182028` 通过并精确输出 `state=promoted`、`deploymentChanged=true`。这些发布证据不反向把早期 H-W 候选冒充成正式 runtime 业务复验；W 专项 `standard_entry_verified` 仍待部署后旅程。

#### C-A

- fresh TestLoader trace 与 Compiler/Output 无错误。
- 实际目标 SWF/asLoader 的字节、hash、装载位置与运行入口证据。
- Host/Web focused contract tests 和 A 相关组合 suite。
- exact candidate 上按 §8.2 fault cuts 执行 persisted readback、kill/restart、duplicate exact query、ledger 与 `appliedCount` 机械核对。
- 预先构建并验证 `A-compat-disabled` 回滚候选：拒绝新 root admission，但保留 v1 nested normalizer、opaque/quarantine、discovery、tombstone 和 exact query consumer。
- rollback 前 active-root drain/quarantine 通过。

若 C# runtime 字节进入正式 runtime，继续遵守 [runtime build reproducibility](../docs/runtime-build-reproducibility.md) 的 immutable request、双 signer、双 faultDomain、相同 identity/closure、production policy、原子 promotion 与 post-promotion audit。该链不代签 A 的 AS2 业务正确性。

### 8.5 一次物理 Windows/Flash 人类窗口，三项分别裁决

**H-W**：

- 活动 Panel 最小化并从任务栏恢复，window rect 与最小化前完全相同；
- QQ/浏览器抢前台后返回；
- 无永久空白、窗口组逃逸、错误 hide/show 或抢焦；关闭路径继续 external/null fail closed。

2026-09-02，维护者在上述 exact candidate 完成同尺寸任务栏恢复、外部 QQ/浏览器前台与关闭路径复核后明确回复“有效”。H-W 因而裁决为 `HUMAN_ACCEPTANCE_PASSED`，解锁 W 的正式发布列车；该结论不代签尚未运行的 post-promotion 标准入口。

**H-A**：

- 选取玩家可辨认的多项 Reward，观察全部领取或容量受限部分领取的中文结果是否与实际物品一致；
- 正常关闭/重启并重开领取界面，已领取项不重复、未领取项不丢失，剩余数量与可见列表一致；
- 腾出空间后能够继续领取 remaining entry，流程没有永久 loading、错误禁用或必须理解内部 root ID 才能恢复的交互。

fault cut、exact query、ledger 和 `appliedCount` 对账属于 C-A 自动化门，不要求真人逐字核验内部协议状态。

**H-S**：

- 候选携带 O1 时主动复现一次 blackmarket 卡住；
- 按 §6.1 输出四种合法结论之一，并让日志能够解释该结论；`inconclusive` 不冒充归因通过，只按 §6.3 保留一次定向补采资格。

三项可同场执行，但结果不得合并成一个 pass。A 失败不能抹掉已经通过的 W，W 失败也不能推翻 A 的持久化证据。

### 8.6 不接受的替代证据

- Node/headless 不代签 HWND、DWM、taskbar、foreground、InputShield 或物理 WebView2。
- 旧 SWF、marker 或 PowerShell exit 0 不代签 fresh Flash 行为。
- runtime promotion 不代签 Reward exact-once。
- AS2 trace 不代签 C# signer/faultDomain/identity/closure。
- 调用次数、无基线 soak、p95/p99 不自动证明 stale overwrite 或卡顿根因。
- 同一 grep/静态字段由多个 owner 重复运行，不计为多份独立证据。

具体命令与发布状态术语以 [testing-guide](../agentsDoc/testing-guide.md)、[launcher README](../launcher/README.md) 和 [AS2/Web Panel migration](../agentsDoc/as2-web-panel-migration.md) 为仓库内 canonical 入口。

---

## 9. 发布切片与回滚

### 9.1 发布策略

| 方案 | 适用条件 | 回滚 | 裁决 |
|---|---|---|---|
| **R1：W 先发，A 后发** | W 明显先达到 candidate + H-W | W 独立 revert；A 失败不影响 W | W 先绿时立即采用，不等待 A |
| **R2：同一维护窗口的两个独立提交** | W/A readiness 接近 | 首次 A1 admission 前可回 W-only；之后只回 `W + A-compat-disabled` | 结构上的默认方案 |
| **R3：不可分 mega-train** | 当前没有真实源码依赖支持 | 任一失败迫使两轨一起回退 | `VETO` |

一次维护窗口不等于一次发布单元。即使采用 R2，W/A 仍有独立 commit、candidate、evidence、rollback 和人类裁决。

### 9.2 W 回滚

- 只撤销 geometry admission、committed snapshot 与 restore replay。
- 不回退已经验证的 focus close eligibility、live foreground recheck、external/null fail-closed。
- B1 不在本轮，不存在 epoch/revision 状态迁移。

### 9.3 A 回滚

A 的字节回滚边界以“是否已有 A1 root durable admission”为准：

- **首次 admission 前**：存档中尚无 A1 active/tombstone/opaque root，可回到 W-only candidate 与上一份已验证 AS2 产物。
- **首次 admission 后**：不得回到不认识 A1 字段的旧 AS2 normalizer 或旧 Host/Web exact sanitizer。回滚必须进入预先验证的 `A-compat-disabled` 模式。

`A-compat-disabled` 的顺序固定为：

1. AS2 与 Host/Web 同时关闭新 Reward root admission，旧客户端缺少 predecessor acknowledgement 的 claim 也 fail closed。
2. 对所有 pending active root exact query/reconcile，收敛到 `committed / terminal_failure / quarantined`；quarantined 保持可发现且禁止 mutation。
3. 保留 v1 nested normalizer、opaque 数据再写回、terminal tombstone、discovery acknowledgement、exact query producer/consumer 与 strict validators。
4. 不得重新打开 projection inference、legacy write retry 或 detached reconcile 处理既存 durable root。
5. 只有另一个 ADR/迁移工具能够证明目标 save cohort 已无 active/tombstone/opaque A1 数据时，才允许撤掉 compatibility floor；本轮不预建该迁移。

因此 A1 一旦写入存档，安全回滚是“禁新写、保留读与恢复”，不是 byte-for-byte 回到旧协议。这个兼容 floor 不构成 W/A 绑定：W 仍可独立保留、撤销和发布，只是 A 自身不能丢掉已经持久化的解释能力。

O1 可在 first stalled owner 确认后单独删除或默认关闭，不影响 W/A 的业务状态。

---

## 10. 反过度设计硬门

### 10.1 本轮明确不建设

- `GeometryStateCore`、全局 desired/actual geometry registry；
- `WindowGroupDefinition`、`FocusReturnPolicy` 自动代码化；
- 全局 owner epoch、geometry revision、latest-wins publication scheduler；
- 通用 repair timer、compositor repair framework、magic delay 表；
- `OperationProfile` registry、durable workflow BaseTask、通用 event sourcing；
- JoinPolicy、proof bus、全局 await registry；
- C# StateCore 或 Reward/存档业务权威迁移；
- 新 detached reconcile/retry 抽象；
- 通用 heartbeat/watchdog/自动恢复平台；
- W+A 统一事务或 release coordinator；
- 手工逐 revision approval、复制 hash 的 receipt 流程；
- 无基线 soak、p95/p99 或固定次数 SLA。

### 10.2 仅允许的五个窄例外

1. Reward `activeClaimRoot`、terminal tombstone 与同域 `A-compat-disabled` admission gate。
2. 现有 `claim/claimBatch` 的 predecessor acknowledgement，以及 `lootQuery`、Reward `inboxSummary/rewardAuthority` 与 Reward response 的 root coordination 字段。
3. 现有 coordinator 内的 prepare/apply seam。
4. Window 本地、代际绑定的 restore-revalidation reason/bit。
5. 临时、低频、有界、feature-gated 的 blackmarket heartbeat。

任一实现若需要第六个架构例外，先暂停对应最小 hunk并修订 ADR；不得以“顺手整理”扩张。

---

## 11. 结果、代价与后续判断

### 11.1 预期收益

- 无效几何在发布边界被阻断，不再污染多个窗口消费者。
- 同尺寸恢复不依赖尺寸变化碰巧触发，同时不重新打开抢焦路径。
- Reward batch 在 kill/restart 和 response loss 下有单一、可查询的根事实。
- Host/Web 不再为 Reward 未知写维护多套 projection 因果猜测。
- 下一次软锁复现先定位 owner，再决定是否修 Web、transport、Host 或 AS2。
- W 与 A 可独立止血，避免一个慢轨阻塞另一个已闭合风险。

### 11.2 接受的代价

- Reward v1 feature 增加一个专用 durable lane 和兼容 normalizer。
- 现有 Reward claim/query/summary/authority/response 出现一组明确受限的 root coordination shape 扩展，需要跨 AS2/C#/Web fixture。
- 首次 A1 root durable admission 后，回滚必须长期保留 `A-compat-disabled` 解释能力，除非未来有独立、可证明的数据迁移。
- Window 需要保存小型 committed snapshot 并区分 restore replay 与 full resume。
- 第一次软锁诊断候选会携带临时观测代码。

这些代价都局限在现有调用链，没有新增进程、数据库、IPC hop 或业务权威。

### 11.3 何时说明止血仍不够

出现以下任一新证据时，另立长期架构治理 ADR，而不是继续向本文塞入框架：

- 两个以上独立 Panel 仍需要复制同一种已证明的 geometry publication state machine；
- 完成 A1 后仍有第二个业务域需要同构 durable root，且共享部分不含领域 payload/reconcile 政策；
- 捕获到跨 owner/panel generation 的 stale overwrite，局部 generation guard 无法拒绝；
- O1 证明软锁来自共享 transport/runtime，而非单一 minigame/AS2 owner；
- 止血落地后同类事故仍持续，且反例能够指向同一缺失抽象。

在这些证据出现前，“框架更完整”不是成功指标。

---

## 12. 当前状态与冻结流程

| 项目 | 当前状态（2026-09-02） | 下一自然动作 |
|---|---|---|
| ADR 内容 | W 设计保持 `APPROVED / DESIGN_FROZEN`；本轮未扩张为 B1 framework | H-W 反馈若要求范围变化，先修订 ADR |
| Checkpoint-0 | clean commit `11376feb...` / tree `bfbe61dc...`，baseline Launcher **4509+3/4512** | 已关闭 |
| G0-W | valid / explicit-invalid / unavailable、pre-pause admission、committed snapshot、same-rect replay 已冻结并实现 | 只允许 H-W 发现的窄修正 |
| G0-A/G0-S | 未启动；A/S production files 零修改；W 发布后第二列车已获授权 | W promotion/push 后继续施工到 H-A/H-S |
| W 实现 | `PanelHostController`、`WebOverlayForm`、Router pause owner 与 tests 已完成；无 AS2/SWF 变更 | 等待 H-W |
| 自动测试 | focused **266/266**；full SDK resolver **7/7**、Launcher **4516+3/4519** | H-W 若触发代码迭代则重跑 affected + full |
| 隔离候选 | `candidate_executed / NOT_DEPLOYED`；identity `7BD7...972D`、closure `F59D...D331`、Core `82C9...2BAB` | 已完成 W 候选职责 |
| 人类验收 | H-W 已由维护者回复“有效”，状态 `HUMAN_ACCEPTANCE_PASSED`；H-A/H-S 留给第二列车 | W 发布后实施 A/S，再等待第二次人类裁决 |
| runtime 发布 | W release 正在配置本地 builder/GitHub 环境；尚未提交、建 request、取得共识或 promotion；正式 Core 未变 | 完整执行 v2 source/tag/request/local+cloud/policy/promotion/push/audit |
| asLoader | W 不涉及，未编译、未改写、未发布 | 无动作 |

本次冻结使用的全中文提交标题：

```text
docs: 冻结窗口生命周期与奖励根事务止血架构
```

该历史提交只冻结 ADR。当前 W 工作树和候选仍未形成 release source commit；本节新增的机器检查点不暗示 H-W、云端共识、promotion、部署或正式入口已经完成。

---

## 13. 仓库内参考入口

- [系统拓扑 canonical doc](../agentsDoc/architecture.md)
- [AS2 UI → Web Panel 迁移护栏](../agentsDoc/as2-web-panel-migration.md)
- [Launcher 子系统 source of truth](../launcher/README.md)
- [验证矩阵](../agentsDoc/testing-guide.md)
- [文档治理规则](../agentsDoc/documentation-governance.md)
- [runtime v2 可复现发布](../docs/runtime-build-reproducibility.md)
- [关卡结果与基地结算 ADR](../docs/关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md)
- [焦点管理长期备忘](../docs/焦点管理-诊断与卡顿排查-2026-05-24.md)
- [地图资源箱 S1/S2 ADR](../docs/地图资源箱-S1S2真实战利品容器与Web双栏-ADR-2026-07-18.md)
- [玩家物资事务与双向播报 ADR](../docs/玩家物资事务与双向播报-ADR-2026-08-22.md)
- [P0-F 跨层迁移基座与架构收敛专项](../docs/P0-跨层迁移基座与架构收敛专项-2026-07-23.md)
