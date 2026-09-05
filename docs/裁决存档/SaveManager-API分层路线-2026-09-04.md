**文档角色**：2026-09-04 原始裁决存档，2026-09-05 从本机临时目录迁入版本化文档。下文保留当时判断与工序，不代表当前施工或发布状态。当前状态由[存盘风暴 ADR](../存盘风暴止血-Reward相邻durable-cut桥接与存盘次数回归门-ADR-2026-09-03.md)和 [R1 收尾记录](../R1存盘API迁移收尾-2026-09-05.md)维护；XFL 发布范围须按实际生产入口复核，历史 live/mainCopy 名称不能代替运行归属证据。

**来源**：`tmp/adjudication-savemanager-api-20260904/gptpro.txt`；原始文件 SHA-256 `98aea131771a9e350c7a83526b6e998aaa2ff47794d874513554ead98c112758`。代码基线为交接 commit `4ae00a176265b7d00ea38364d545d29cbe601efa` 中记录的裁决上下文；正文中的行号、计数与待办保留历史口径。原文从分隔线之后开始。

---

# SaveManager API 分层路线裁决

## 一、结论先行

本轮裁决如下：

| 路线                               | 裁决                   | 核心理由                                                                                                                                         |
| -------------------------------- | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **R1：四层 API 分层**                 | **采纳，分阶段落地**         | 现在已有物理八分桶、Reward N+1 精确门、fault-cut 与真实重启 harness，已经具备逐调用点迁移条件。但第一阶段必须是**语义分层，不是存盘行为优化**：strict fence 不合并、不 dirty 早退、不异步化。                    |
| **R2：保持三通道，只给 XFL 全面补 dirty 守卫** | **原案否决；只吸收已证明安全的子集** | 当前 dirty 覆盖不完整，且 `hasPendingChanges()` 已确认漏掉设置迁移 latch；把 12 个无条件 XFL debounce 全部改成 dirty 条件，会把显式兜底变成静默漏存。观测、现有守卫保留、已证实 mutator 的局部守卫可以并入 R1。 |
| **R3：shadow latest-wins 加固**     | **条件采纳，必须独立施工**      | 先做 R3a：所有同槽 archive 操作有序执行、墓碑检查与写入同门、普通 shadow 不得清 tombstone。再做 R3b：持久化 `incarnation + revision`。只加线程锁或只加 `_saveSeq` 都不完整。                   |
| **R4：`flushNow()` 全局 dirty 早退**  | **明确否决**             | 不仅审计覆盖不足，当前 `hasPendingChanges()` 本身就漏 `_settingsMigrationPending` 和 KeyManager migration；`_doSaveAll()` 还承担未必标脏的派生同步。现在落地会产生确定性漏存，而不是理论风险。  |

**总路线：R1 与 R3 分成两条发布列车。先完成 R1 的显式语义分层和调用点迁移；R3a 可独立提前止住乱序，R3b 再做 reader-first 的协议升级。R4 不绑定 R1，也不留“顺手实现”的口子。**

---

# 二、§6.1：F4 三条否决在 F1′ 后是否仍成立

## 2.1 三条理由逐项复审

| 原理由                                | 裁决                  | F1′/新测试基础带来的变化                                                                                       |
| ---------------------------------- | ------------------- | ---------------------------------------------------------------------------------------------------- |
| ① 真正落盘前返回 `true`，会制造虚假 durability  | **完全成立，无任何削弱**      | `true` 的唯一含义仍必须是 `SharedObject.flush() === true`。物理计数和 fault-cut 只能发现违规，不能让虚假返回变安全。                  |
| ② AVM1 UI 线程无法“阻塞到帧末并收集本帧后续调用”     | **完全成立，无任何削弱**      | F1′ 改的是业务 cut 排布，不改变 AVM1 单线程执行模型。所谓同步等待帧末的透明合并依旧是自锁悖论。                                              |
| ③ 改成异步 pending，所有 strict 调用者必须变状态机 | **逻辑完全成立；工程验证成本下降** | 现在已有 fault-cut、save-image restart、N+1 与物理分桶，调用者迁移的可验证性显著提高。但这只说明“可以显式迁移”，不说明“可以在 SaveManager 内透明替换”。 |

前次 F4 的三条否决原文位于 `04-背景文档/第一次裁决回执-gptpro.md.txt:261-288`。F1′ 反而降低了破坏 strict 语义的必要性：Reward 已经从 `2N+1` 压到接近当前崩溃恢复粒度下的 `N+1`，不再需要拿 durability 冒险换主要收益。

## 2.2 四层 API 的最终语义

### API 语义表

| API                             | 返回契约                                                     | 合并行为                                                              | `sv` 行为                                                    | dirty 行为                                                                | 合法使用场景                                          | 禁用场景                                                                |
| ------------------------------- | -------------------------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------- |
| `markDirty()`                   | `Void`                                                   | 无                                                                 | 不发送                                                        | 幂等置位 canonical dirty；迁移期同时维护 `_dirtyMark` 与 `_root.存档系统.dirtyMark` 兼容镜像 | 所有持久化状态 mutator                                 | 不得被当作“已请求存盘”或“已 durable”                                            |
| `requestSave(reason)`           | **`Void`**，刻意不返回“成功”                                     | 全局一个 **300ms trailing debounce**；所有 reason 合并进同一个 pending request | 调度时不发送；真正开始物理存盘时才走通用 `sv:1 → sv:2/3`                       | 不自动标脏；成功全量存盘才清 dirty/latch；失败保留                                         | UI 关闭、连续编辑后的最终兜底、当前 `saveAll()` 语义调用点           | Reward cut、资产事务提交点、manual save、退出/切场景 barrier、任何调用者需要立即依据结果继续状态机的地方 |
| `flushDurableNow(reason)`       | `Boolean`；仅本地 `SharedObject.flush() === true` 才返回 `true` | **不合并 strict 调用，不 debounce，不 dirty 早退**；可吸收此前 pending request     | 与当前 `flushNow()` 的可观察时序完全兼容；`sv:2` 只对应本地 SOL 成功，shadow 不代签 | 无论 clean/dirty 都全量组包；仅成功后清全部 dirty/migration latch                      | durable cut、事务提交、手动保存、奖励关窗、设置确认等                | 不得用于试图“最终会保存就行”的热 UI；不得因性能压力透明改成异步                                  |
| `flushBeforeTransition(reason)` | 同样为 `Boolean`，同样只认本地 flush true                          | 与 `flushDurableNow` 相同                                            | 与 strict fence 相同                                          | 与 strict fence 相同                                                       | **可阻止后续 transition 的 barrier**：返回基地、建角后开教程、安全退出 | SceneChanged 这种已经发生、且调用者不会因 false 撤销事件的事后 safety-net；普通持久化 cut      |

### `flushBeforeTransition` 不是另一套存储算法

V1 中它与 `flushDurableNow` 应共享同一个私有同步落盘内核，不能额外增加一次写盘，也不能引入不同的 dirty 行为。

但它不能只是毫无治理价值的公开别名。必须有以下差异：

1. 独立 API ingress 桶和固定 reason allowlist。
2. 静态门要求：除 safeExit 的 Host 外部门控特例外，调用者只能在返回 `true` 后执行 transition。
3. 独立测试证明 false、`"pending"`、throw 均不越过 transition。
4. 不允许 B1 SceneChanged 滥用这个名字，因为 B1 并不能回滚已经发生的 scene change。

### `requestSave` 的合并规则

采用现有的单一 300ms trailing 窗口，不按 reason 创建多套 timer，也不做 reason 优先级：

* reason 使用固定注册表中的低基数字符串，不接受任意动态文本。
* 同一窗口内 reason 做集合合并，仅用于诊断。
* pending request 遇到成功 strict fence，由该次全量存盘吸收，timer 取消。
* timer 触发时若发现 `_saveInFlight`，必须重新挂一个 pending request，不能像当前 `_onDebounceFire()` 一样直接丢弃。
* strict 调用若因重入根本未能开始，也不得先把原 pending token 删除。
* 异步 timer 回调发生异常时，应推 `sv:3`、记录错误、保留 dirty，但**不得把异常重新抛回 `EnhancedCooldownWheel`**。当前 `_onDebounceFire():458-464` 会 rethrow，而 wheel 明确规定 callback 不得抛异常（`EnhancedCooldownWheel.as:232-241`），这个瑕疵不能原样复制进新 API。

### `hasPendingChanges()` 必须修，但不能用于 R4

当前实现：

```text
_dirtyMark
|| _root.存档系统.dirtyMark
|| _drugLoadoutMigrationPending
|| _rewardInboxMigrationPending
```

明确漏掉：

* `_settingsMigrationPending`：它在 `applySettings()` 中置位，且只在成功全量存盘后清除；
* `KeyManager.hasPendingKeySettingsMigration()`：成功全量存盘同样会清除。

证据分别在：

* `SaveManager.as:2129-2132`
* `SaveManager.as:2599-2637`
* `SaveManager.as:561-569`

因此先补全查询是必要正确性修复，但这不构成允许全局 dirty 早退的条件。

---

# 三、§6.2：调用点最终分类与迁移顺序

## 3.1 调用点语义归属

| 调用点                                | 目标 API                                                       | 裁决                                                                                |
| ---------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| **A1 safeExit**                    | `flushBeforeTransition("safe_exit")`                         | 保持同步 durable。AS2 当前忽略 Boolean，但 Host 必须依赖本轮 `sv` 门控。                              |
| **A2 Reward `flushSave(cutName)`** | `flushDurableNow("reward." + cutName)`                       | 八个 cut 全部冻结；仍由领域 wrapper 统一调用，不允许调用点散落直调。                                         |
| **A3 PlayerAssetTransaction**      | `flushDurableNow("asset_tx.commit")`                         | 等 K 店 A① WIP 提交定型后迁移；保留 PAT wrapper 和事务延迟/显式 precommit 区分。                        |
| **A4 ItemUse**                     | `flushDurableNow("item_use.open_commit")`                    | 每包当前仍是一个 durable operation，不改恢复粒度。                                                |
| **A5 Loot 三类**                     | `flushDurableNow(...)`                                       | claimBatch 批尾、standalone 每格、settlement terminal 三种语义全部保留。                         |
| **A6 返回基地**                        | `flushBeforeTransition("stage.return_base")`                 | prepared settlement 必须先 durable，false 保留 prepared，不 reroll。                       |
| **B1 SceneChanged**                | `flushDurableNow("scene.changed_safety_net")`                | 继续无条件，且必须位于 `deactivateAll()` 前；不能改成 dirty 条件。                                    |
| **B2 建角**                          | `flushBeforeTransition("character_creation.start_tutorial")` | flush 成功后才启动教程。                                                                   |
| **B3/B4 设置 apply/save**            | `flushDurableNow("settings.apply/save")`                     | 保留 durable 后才清 migration latch 和返回 success。                                       |
| **B5 CharacterBuild finalize**     | `flushDurableNow("character_build.finalize")`                | 仍是 finalize fence；同时修正 `hasPendingChanges()` 完整性。                                 |
| **C1-C4 奖励 XFL**                   | `flushDurableNow(...)`                                       | “关窗即 durable”产品语义冻结，不得迁到 request。                                                 |
| **C5 手动存档**                        | `flushDurableNow("manual_save")`                             | 显式用户承诺，不得 debounce。                                                               |
| **C6 旧商城关闭**                       | 单独裁决                                                         | 若 dead，删除整个旧路径；若 live，先保留“购物车 partial flush + full strict flush”双行为，不在 R1 中偷删第一笔。 |
| **D1 商城面板关闭**                      | `requestSave("shop.panel_close")`                            | V1 保持无条件 request；在 shop 全 mutator 证明标脏前不加全局 guard。                                |
| **D2 购物车编辑**                       | `markDirty(); requestSave("shop.cart_edit")`                 | 第一批迁移候选，但需避开 K 店 A① 对同文件的并行 WIP。                                                  |
| **E1/E9/E10**                      | 保留现有 dirty guard 后 `requestSave`                             | 现有守卫形状冻结。                                                                         |
| **E6 整形支付**                        | canonical `markDirty()` 后 `requestSave`                      | 同一成功分支已明确标脏，可安全迁移。                                                                |
| **E2/E4/E5/E7/E8/E13**             | V1 无条件 `requestSave`                                         | 未证明 dirty 覆盖完整，不得顺手改成条件式。                                                         |
| **E3/E11/E12 legacy 嫌疑**           | 先 live probe；live 则无条件 `requestSave`，dead 才删除                | “运行没打到一次”不足以证明 dead。                                                              |

调用点原始清单位于 `callsites.md:28-95`，冻结分类位于 `callsites.md:205-223`。

## 3.2 分发布切片迁移

### Slice 0：冻结基线与机器可读调用点清单

**不改生产行为。**

建立 manifest，至少包含：

```text
callsiteId
sourcePath
line/frame
legacyApi
targetApi
reasonId
returnConsumed
duplicateGroup
liveState
expectedSwf
```

回归门：

* 当前 17 个 strict 逻辑调用点、15 个 debounce 调用点数量精确；
* XFL 10 个 strict 物理点、13 个 debounce 点精确；
* Reward N+1、八分桶、fault-cut、真实 restart 全绿；
* 保存当前发布 SWF hash 与 FFDec 帧脚本提取结果。

### Slice 1：只增加四层 API、shim 与计数，不迁调用点

修改：

* `SaveManager.as`
* `通信_lsy_原版存档系统.as`
* `SaveManagerTest.as`

旧入口继续存在：

```text
_root.强制存盘       -> legacy flushNow
_root.自动存盘       -> legacy saveAll
_root.本地存盘       -> legacy saveAll
```

新增入口建议放在 `_root.存档系统`：

```text
_root.存档系统.markDirty
_root.存档系统.requestSave
_root.存档系统.flushDurableNow
_root.存档系统.flushBeforeTransition
```

XFL 不应直接引用 `org.flashNight.*` 类，避免主 SWF 类嵌入和编译依赖。

此切片同时完成：

* `hasPendingChanges()` 补齐设置与 KeyManager migration；
* timer in-flight 不丢 request；
* scheduled callback 不再向 wheel 抛异常；
* 新旧 public API 共用私有内核，但互相**不能经 public method 级联调用**，防止 ingress 双计数。

回归门：

* 旧测试完全不变绿；
* 新 API contract tests 绿；
* `audit-as2-class-embedding --policy single-ownership` 绿；
* 所有 `.as` UTF-8 BOM 门绿。

### Slice 2：D1/D2 scripts debounce

修改 `商城系统_WebView.as`：

* D1：`saveAll` → 无条件 `requestSave("shop.panel_close")`
* D2：直接 dirty setter 收敛到 `markDirty()`，随后 `requestSave("shop.cart_edit")`

前置条件：K 店 A① WIP 已提交并重放相关测试，避免两个分支同时改 `商城系统_WebView.as`。

回归门：

* 连续 N 次购物车编辑：API ingress N，物理全量存盘恰好 1；
* checkout/claim 仍走 strict fence；
* request 后立刻 checkout：只发生 checkout 的一次全量物理存盘，pending request 被吸收；
* checkout false 后不得发布成功 receipt。

### Slice 3：低耦合 strict 调用点 B3/B4/B5

先迁设置和 CharacterBuild：

* B3/B4 → `flushDurableNow`
* B5 → `flushDurableNow`

回归门：

* settings migration false/pending/throw 不清 latch；
* success 才清 `_settingsMigrationPending` 与 KeyManager pending；
* clean state 调 strict 仍必须产生一次 `doSaveAll/pack/flushAttempt`；
* B5 finalize false 时不能发布已完成状态。

### Slice 4：transition API A1/A6/B2

* A1 safeExit
* A6 Stage return
* B2 Character creation

回归门：

* A6 false/pending/throw：不设置 `_returnRequested`，prepared manifest 不变化；
* B2 false：不启动 tutorial；
* A1：Host 未收到本轮有效成功门之前，`EXIT_CONFIRM` 必须被拒绝。

### Slice 5：A4/A5，再迁 A3

* A4 ItemUse
* A5 Loot
* A3 PAT 在 K 店 WIP 定型后迁

回归门：

* ItemUse false：exact restore + `commit_pending`；
* claimBatch 一批一次，standalone 一格一次，terminal 额外一次；
* save-image restart 恢复 tuple 与旧实现逐字一致；
* PAT 所有调用者区分“事务尾 fence”与“K 店 precommit fence”，不得又合并回一个模糊入口。

### Slice 6：最后迁 A2 Reward

Reward 是最高风险、同时测试最充分的 strict 车道，应最后迁移以验证新框架没有污染 cut 语义。

保持：

* `RewardInboxService.flushSave(cutName)` wrapper；
* 八个 cutName；
* attempt/result probes；
* false → `commit_pending`；
* N+1 精确公式。

不能因为内部不再调用 `_root.强制存盘` 就删除领域层计数。应把领域计数钉在 `flushSave(cutName)` 或新 shim test double，而不是退化成只测 SaveManager 物理桶。

回归门仍是：

```text
领域 strict 请求数 == N+1
save-image 成像数   == N+1
doSaveAll            == N+1
packGameState        == N+1
cut 序列             精确相等
```

### Slice 7：B1 SceneChanged 单独迁移

保持：

```text
flushDurableNow("scene.changed_safety_net")
在 EnhancedCooldownWheel.deactivateAll() 前
无 dirty 条件
```

它不是 transition API，因为 scene change 已发生；它是“销毁旧调度环境前最后一次全量 safety-net”。

回归门：

* trace 顺序严格为 `fence start → flush terminal → deactivateAll`；
* dirty=false 仍有一次完整物理存盘；
* pending debounce 在 `deactivateAll()` 前被 full fence 吸收，不得被销毁后静默丢失。

### Slice 8：XFL E1-E13 requestSave

处理策略：

| 分组                 | 处理                                               |
| ------------------ | ------------------------------------------------ |
| E1/E9/E10          | 原 dirty guard 原样保留，只替换调用 API                     |
| E6                 | 标脏改为 canonical `markDirty()`，随后 request          |
| E2/E4/E5/E7/E8/E13 | V1 保持无条件 request                                 |
| E3/E11/E12         | 插 reason probe，确认 live；证实 dead 才删除，否则无条件 request |

**live 状态职责：**

* Claude Code：完成静态元件引用图、loader/attachMovie 搜索、reason probe、XML 修改、发布前后调用点差异。
* Flash CS6 发布执行者/人工 QA：运行规定旅程，记录 reason trace、实际加载 SWF 与 hash。
* dead 删除必须同时满足静态不可达证据和运行覆盖证据；单纯“测试没触发”不能作为删除依据。

回归门：

1. XML CDATA 定点扫描数量精确。
2. Flash CS6 GUI 实际发布成功。
3. 最终 SWF 经 FFDec 再提取，API 与 reason 和 manifest 一致。
4. 各 UI 旅程触发预期 reason。
5. request 返回值未被读取。
6. 主 SWF 类嵌入数仍为 0。

### Slice 9：XFL C1-C5 strict

* C1/C2/C3/C5 必须同时修改主 XFL 副本与 `flashswf/UI` live 副本。
* C4 处理 live 副本。
* 保持现有“关窗时立即全量存盘”。
* 不在此切片顺便把 XFL 调用者改成复杂异步状态机。

回归门除上述 XFL 门外，还要人工执行：

* 两类任务奖励按钮；
* 单物品奖励关窗；
* 一键领取全部后关窗；
* 手动保存；
* 立即杀进程并重启读取。

### Slice 10：C6 与 legacy 收尾

C6 有两种合法结论：

1. **证实 dead**：删除旧商城实例化路径、两处 `_root.保存购物车()`、C6 strict 调用以及死委托 `saveShopPurchased`。
2. **仍 live 或证据不足**：保留现有两段式行为，另开 ADR 决定是否可把：

```text
partial cart flush
+ full durable flush
```

收敛成一次 full fence。

不能在 R1 中直接删 partial flush。虽然正常成功路径上 full snapshot 已包含购物车，但当前第一笔 partial flush 在“第一笔成功、第二笔失败”时仍改变恢复结果，删除它属于失败语义变化。

---

# 四、§6.3：shadow latest-wins 的安全条件与 R3 方案

## 4.1 当前问题不只是“线程池有时乱序”

当前链路：

1. XmlSocket 单 read loop 按发送顺序收到消息；
2. `ArchiveTask.HandleAsync()` 对每条消息独立 `ThreadPool.QueueUserWorkItem`；
3. `TryWriteShadowAtomic()` 用 `_lock` 串行实际写文件；
4. 但 lock 获取顺序不保证等于消息到达顺序；
5. 最后拿到 lock 的整份 snapshot 覆写 `<slot>.json`。

证据：`ArchiveTask.cs:257-272`、`:305-397`、`:109-152`。

此外还有两个更硬的缺口：

* 普通 shadow 当前调用 `TryWriteShadowAtomic(..., clearTombstone:true)`，能够主动删除 tombstone（`:381`、`:131-135`）。
* `userEdit` 的 tombstone 检查发生在 `_lock` 外（`:353-355`），检查后到写入前存在竞态。
* `RunConsistencyCheck()` 在物理写成功前就更新 `_prevSnapshots`（`:405-412`），失败或被拒绝的候选也会污染下一次比较基线。

## 4.2 纯 whole-file overwrite 什么时候安全

只有同时满足以下条件时安全：

1. 同一 slot 只有一个逻辑 writer。
2. slot incarnation 在整个期间不可删除、reset、重建或复用。
3. 所有 mutation、shadow、delete、seed、repair、userEdit 按同一个因果 FIFO 执行。
4. 每次写入都是完整 snapshot，不需要字段级 merge。
5. 重复消息要么内容完全相同，要么有明确幂等判定。

当前系统不满足第 2、3、5 条，因此“最后完成的写覆盖之前写”不能被称为 latest-wins；它只是 completion-order-wins。

## 4.3 三类场景的最低要求

| 场景                               | 单纯 FIFO 是否足够                | 必须增加什么                                                  |
| -------------------------------- | --------------------------- | ------------------------------------------------------- |
| 同一连接中的 S1/S2 线程池乱序               | **足够**，前提是同槽所有相关操作进入同一 FIFO | 有序 executor，不能只靠普通 lock                                 |
| delete 后迟到 shadow                | **不够**                      | tombstone 与写入同门；普通 shadow禁止清 tombstone；显式 recreate 才能换代 |
| slot 删除后以同 key 重建、reset、跨 writer | **不够**                      | 持久化 incarnation/generation + revision                   |
| userEdit/repair 与运行中 AS2 同时写     | **不够**                      | writer lease/quiescent 要求，或显式换代并强制 AS2 reload           |

## 4.4 R3a：先关闭当前竞态，不改存档 schema

R3a 建议作为独立止血提交：

1. 将 `ArchiveTask.HandleAsync` 的 archive 操作改为**单 FIFO executor**。当前 archive 吞吐远不是瓶颈，优先选择全局单消费者；以后确有需要再分片为 per-slot queue。
2. shadow、load、delete、reset、seed、userEdit、repair 等同槽操作必须经过同一顺序门。只串行 shadow 而让 delete 旁路仍不安全。
3. tombstone 检查、版本检查、写入、accepted-state 更新在同一临界区完成。
4. 普通 AS2 shadow、seed、userEdit、repair 默认都不得清 tombstone。
5. 只有显式 `recreate/new-incarnation` 操作能够撤销旧墓碑。
6. `_prevSnapshots` 只在写入成功且被接受后更新。

R3a 可消除本进程当前线程池乱序和 tombstone TOCTOU，但**不能解决 reset/recreate 后旧消息跨代复活**。

## 4.5 R3b：持久化 `incarnation + revision`

建议的数据形状：

```text
mydata.ext.saveClock = {
    schema: 1,
    incarnation: "<host-issued immutable id>",
    revision: 123,
    writer: "as2"   // 只用于诊断，不参与胜负
}
```

archive payload 外层重复携带：

```text
clock: {
    incarnation: "...",
    revision: 123
}
```

约束：

* **内层 clock 才是权威来源**，因为它随 SOL 和 shadow 持久化、可参与启动仲裁。
* 外层 clock 仅用于快速拒绝；C# 必须校验它与 `data.ext.saveClock` 一致。
* 只把 `_saveSeq` 放 payload 外层的方案否决：重启后丢失，读侧也看不见。
* 只有 revision、没有 incarnation 的方案否决：reset/recreate 后无法区分新档 revision 1 与旧档 revision 100。

### 写侧仲裁

在同一 incarnation 内：

* incoming revision `< accepted`：拒绝 stale。
* incoming revision `== accepted`：

  * normalized snapshot 内容完全相同：幂等 no-op；
  * 内容不同：`same_revision_conflict`，fail closed，不按 writer 或时间戳猜胜负。
* incoming revision `> accepted`：接受。

不同 incarnation：

* 只有 Host 元数据中当前 active incarnation 可以写。
* 旧 incarnation 一律拒绝。
* delete/tombstone 记录被删除的 incarnation。
* recreate 由 Host 生成新 incarnation，并通过显式流程激活。

因此 Host 需要保留一个很小的 slot metadata/epoch sidecar。当前 `reset` 会删除 JSON 与 tombstone 并彻底忘记 slot（`ArchiveTask.cs:710-762`）；这与“拒绝 reset 后迟到旧写”不可兼得。R3b 下 reset 必须保留 retirement/epoch 信息，哪怕用户界面上该槽位已完全消失。

### revision 发行

* AS2 每次 full save candidate 分配下一 revision。
* failed/pending attempt 允许消耗 revision 形成空洞；单调性比连续性重要。
* 只有本地 SOL flush true 后才发 shadow。
* userEdit/repair 在有序门内从当前 accepted revision 分配下一值。
* seed 不创造新业务版本：保留来源 snapshot 的 clock，只允许补齐缺失或覆盖更旧 shadow。
* userEdit/repair 若发生在游戏仍持有同 slot 的活动 writer 期间，应直接拒绝，或执行显式 epoch 切换并要求 AS2 reload；不能让两个活动 writer 竞争同一 revision 空间。

### 读侧仲裁

`lastSaved` 不删除，但降级为：

* UI 展示；
* legacy snapshot 的兼容 fallback；
* clock 缺失时的旧版迁移依据。

当 SOL 与 shadow 都有 clock 时：

1. 先验证 incarnation。
2. 同 incarnation 取较高 revision。
3. revision 相等而 normalized 内容不同，判定 fork/corrupt，不得继续用秒级 `lastSaved` 猜测。
4. 不同 incarnation 只接受 Host 当前 active incarnation。

需要同时修改：

* C# `SolResolver.Resolve`
* C# `SaveMigrator`
* AS2 `SaveManager.loadAll/preload` 的 JSON/SOL 仲裁
* `ArchiveTask.HandleShadow/TrySeedShadowSync`
* userEdit/repair 路径

## 4.6 R3b 发布顺序

必须 reader-first：

1. C#/AS2 reader 能识别 legacy + clock，尚不强制。
2. Host 建立 slot metadata/incarnation。
3. AS2 full save 开始发 clock。
4. 观测 clock 覆盖率与 conflict 指标。
5. 对已有 clock 的 slot 开启严格拒绝。
6. 最后才取消 clocked snapshot 的 `lastSaved` 主仲裁。

回滚时可以关闭 emitter/enforcement，但已经支持 clock 的 reader 不应回退，以免重新接受 stale shadow。

---

# 五、§6.4：分层后的回归门

## 5.1 现有八分桶保持兼容，不重命名

继续保留：

```text
packGameState
doSaveAll
flushAttempt
flushSuccess
flushPending
flushFalse
jsonStringify
shadowDispatch
```

这些桶已经被 Reward 两层门使用，不能为了 API 分层改变口径。

## 5.2 新增 API 语义桶

单独增加 `_saveApiStats`，不要把 API ingress 混入物理桶。

### API ingress

```text
legacySaveAll
legacyFlushNow
markDirty
requestSave
flushDurableNow
flushBeforeTransition
```

### request disposition

```text
requestScheduled
requestCoalesced
requestFired
requestAbsorbedByFence
requestRearmedInFlight
requestRejectedDisabled
```

### full-save origin

```text
fullFromLegacyDebounce
fullFromRequest
fullFromLegacyStrict
fullFromDurable
fullFromTransition
```

### strict outcome

按 durable/transition/legacy 分别统计：

```text
success
pending
false
earlyReject
throw
```

### flush lane

当前 `flushAttempt` 同时包含 full save、购物车 partial、墓碑和读档迁移。增加闭集 lane，但总桶继续累计：

```text
full
shop_partial
delete_tombstone
preload_tombstone
read_migration
```

每个 lane 至少有 attempt/success/pending/false。

### reason

* reason 必须来自固定注册表。
* 生产只维护固定桶或小型 bitset。
* 不允许任意字符串作为 map key，避免长期高基数增长。
* 测试模式可记录有界 trace：

```text
apiKind
reasonId
requestBatchId
physicalAttemptId
outcome
```

## 5.3 防语义偷换的核心断言

### 防 `flushDurableNow` 被改成 debounce

对完全 clean 的状态调用：

```text
返回前:
doSaveAll       +1
packGameState   +1
flushAttempt    +1
```

并立即读取真实 save image，杀进程重启后必须可见。

这条门同时直接禁止 R4 偷渡。

### 防 `requestSave` 被当 durable

1. 返回类型为 `Void`。
2. 调用后、timer 未触发前，所有物理桶增量均为 0。
3. 静态扫描禁止：

   * `if (requestSave(...))`
   * `x = requestSave(...)`
   * `return requestSave(...)`
4. frozen durable 文件中禁止出现 request API：

   * `RewardInboxService`
   * `ItemUseService`
   * `LootContainerService`
   * `StageRunSession`
   * `CharacterCreationService`
   * PAT strict wrapper
   * C1-C5 XFL

### 合并门

```text
N 次 requestSave，同一窗口:
requestSave ingress == N
requestScheduled    == 1
requestCoalesced    == N-1
doSaveAll           == 1
packGameState       == 1
```

多 reason 时必须保留 reason 集合，但仍只有一次物理存盘。

### request + strict 门

```text
requestSave()
flushDurableNow()

总 full save == 1
pending timer 已取消
后续推进时间轮不再额外保存
```

若 strict 根本因 reentrancy 未开始，原 request 必须仍然 pending。

### strict 失败门

false、`"pending"`、precommit throw：

* 返回 false 或保留 throw 语义；
* 不清任何 dirty/migration latch；
* 不发 shadow；
* 不产生 `sv:2`；
* transition 调用者不得继续。

### 兼容 wrapper 门

每个旧调用只能记录一次 legacy ingress 和一次物理尝试，不得因为：

```text
flushNow -> public flushDurableNow -> private core
```

而同时计入 legacy 与新 API。

正确结构应是两个 public 入口分别进入同一个 private core。

## 5.4 领域门

继续保留并扩展：

* Reward N=1/2/20/50 的 exact N+1；
* all-applied、partial capacity、all-capacity；
* 每个 cut 的 false/pending/throw；
* duplicate/ACK 不增加资产与不增加预期外存盘；
* ItemUse exact restore；
* Loot claimBatch/standalone/terminal；
* Stage prepared settlement；
* CharacterCreation tutorial gate；
* settings migration latch；
* PAT receipt finality；
* 真实 save-image restart，禁止用同进程 reset 替代。

## 5.5 XFL 没有单元测试宿主时的门

必须四层同时存在：

1. **源码 manifest**：调用点 ID、XML 路径、frame、reason、目标 API。
2. **XML exact scanner**：旧入口和新入口数量均为精确断言，不是 `<=`。
3. **发布产物检查**：Flash CS6 发布后的 SWF 用 FFDec 重新提取帧脚本。
4. **运行旅程 reason trace**：证明真正执行的是预期 physical SWF，不只是改到了同名旧副本。

C1/C2/C3/C5 增加 paired-source parity 门：主 XFL 与 `flashswf/UI` 副本必须同时是同一 API/reason。

## 5.6 SafeExit 还有一个现存门控缺口

源码注释声称必须经过“Arm 后本轮 `sv:1 → sv:2`”，但实现目前并未真正记录“Arm 后见过 sv:1”：

* `Arm()` 直接把 `_state` 设为 Saving：`SafeExitPanelWidget.cs:95-106`
* 任意后续 `sv:2` 都会把状态设为 Done：`:416-424`
* `TryAuthorizeExitConfirm()` 只检查 `_armed && Done`：`:143-150`

因此在 Host 已 Arm、但 AS2 safeExit 命令尚未开始执行的窗口，如果一个先前的通用 requestSave 恰好完成并发出 `sv:2`，理论上可以提前授权退出。

这不是 R1 新制造的 bug，但扩大 `requestSave` 使用面会增加暴露概率。R1 在迁移 XFL request 调用点前，应把门改成真正的：

```text
Arm:
    sawSv1AfterArm = false

收到 sv:1:
    sawSv1AfterArm = true

收到 sv:2:
    只有 armed && sawSv1AfterArm 才 Done
```

硬测试：

```text
Arm + sv:2                 -> 不可确认退出
Arm + sv:1 + sv:2          -> 可确认退出
Arm + 背景保存的 sv:2      -> 不可确认退出
```

这属于把现有书面契约落实为机械门，不改变产品语义。

---

# 六、§6.5：R2 与 R4 的最终取舍

## R2

原案“给 12 个无条件 XFL 自动存盘统一套 dirty guard”否决。

可以并入 R1 的只有：

* E1/E9/E10 保留现有 guard；
* E6、D2 这种同一成功路径已明确标脏的调用；
* 将三处悬空 `_root.存档系统.markDirty()` 真正接通；
* 所有 XFL reason/live 观测；
* 在 mutator provenance 审计完成后，逐点增加 guard。

不能先加 guard 的包括 D1、E2、E4、E5、E7、E8、E13，以及尚未确认 live 的 legacy 路径。

## R4

当前明确否决，理由不仅是“审计也许漏了”：

1. `hasPendingChanges()` 已知漏 `_settingsMigrationPending`。
2. 同样未包含 KeyManager migration。
3. 三个所谓 canonical `存档系统.markDirty()` 当前是悬空调用。
4. 40+ setter 只是已找到的集合，不能证明 persisted field 写入全覆盖。
5. `_doSaveAll()` 自身承担：

   * 主线进度同步；
   * 身价校正；
   * `packGameState()` 再计算身价；
     这些派生写入未必先触发 dirty（`SaveManager.as:527-535`、`:1642-1645`）。
6. SceneChanged 被明确设计为 audit 漏标的无条件安全网。
7. clean 早退还可能让 safeExit 在没有新的本地 flush 时产生“已完成”投影。

未来要做 dirty 优化，应另建 `requestSaveIfDirty()` 或 section-dirty/commit-epoch 体系，而不是改变 `flushDurableNow()` 的定义。前置条件至少包括全 persisted-state mutation coverage、迁移 latch 完整性和 committed mutation epoch；当前远未达到。

---

# 七、§6.6：过渡态、shim 与可逆发布

## 7.1 新旧 API 并存是否安全

运行语义上可以安全并存，前提是：

* 旧 `flushNow()` 与新 `flushDurableNow()` 进入同一 private strict core；
* 旧 `saveAll()` 与新 `requestSave()` 进入同一 private scheduler core；
* public 入口之间不互相调用；
* ingress 桶区分 legacy/new；
* 每个切片都有精确调用点 manifest。

真正的风险主要在测试和治理：

* 旧测试若只 monkey-patch `_root.强制存盘`，会漏掉迁到新 shim 的调用。
* 静态扫描若只搜旧函数名，会错误宣称调用点消失。
* 同一调用若 legacy wrapper 再调用 public new API，会被重复计数。
* XFL 某个旧 SWF 未重新发布时，仍可能在运行期使用 legacy 入口。

## 7.2 shim 不应一次性切断

`通信_lsy_原版存档系统.as` 应在整个迁移期保留委托，至少跨一个完整发布周期，并等待：

1. 所有 scripts 调用点迁完；
2. 所有 live XFL/SWF 完成重发布；
3. FFDec 产物扫描确认无旧调用；
4. 运行旅程确认加载的不是旧 SWF；
5. 回滚窗口关闭。

即使完成迁移，也建议先把旧入口降为 deprecated compatibility surface，而不是立即删除。它们体积很小，却能显著降低旧 SWF/遗漏副本导致的灾难性启动风险。

## 7.3 回滚原则

* R1 API 添加是 additive，回滚调用点时不需要删除新 API。
* scripts 切片按调用点回滚到旧 wrapper。
* XFL 切片必须同时回滚 XML 与对应发布 SWF，并校验 hash。
* R3a 没有 schema，单独可回滚。
* R3b reader-first：可以回滚 emitter 与 enforcement，但不回滚 reader 对 clock 的识别。
* R1 与 R3b 不得同一提交、同一发布开关，否则出现问题时无法区分是调用点语义还是版本仲裁错误。

---

# 八、明确否决项

1. 把 `_root.强制存盘` 全局透明改成 debounce。
2. strict fence 在真实 flush 前返回 `true`。
3. AVM1 同步等待“帧末合并”。
4. strict API 返回 pending，再让现有调用者假装同步成功。
5. 在 `_doSaveAll()` 或 strict API 顶部加入全局 dirty 早退。
6. 把 SceneChanged 改为 `ifDirty`。
7. 给所有 XFL debounce 无差别增加 dirty guard。
8. V1 按 reason 建多个 timer、优先级队列或不同 debounce 窗口。
9. 允许 `requestSave()` 返回 Boolean。
10. scheduled callback 向 `EnhancedCooldownWheel` 抛异常。
11. 仅靠当前 `_lock` 宣称 shadow 已按序。
12. 只加 payload 外层 `_saveSeq`。
13. 只加 revision、不加 incarnation/generation。
14. 普通 shadow、seed 或 userEdit 自动清除 tombstone。
15. equal revision 不比较内容而任意 latest-wins。
16. clocked snapshot 继续以秒级 `lastSaved` 作为主仲裁。
17. R1 与 shadow clock schema 同补丁施工。
18. 未证明 C6 dead 就删除旧商城存盘链。
19. 在 R1 中偷偷把 C6 两次写收成一次。
20. 只修改主 XFL 或只修改 `flashswf/UI` 同源副本之一。
21. 在所有实际 SWF 重发布前删除 legacy shim。
22. reason 接受无界任意字符串。

---

# 九、Claude Code 可直接施工的分步清单

| 步骤                       | 改动点                                                                                                                               | 必须保持的不变量                                               | 风险与回归测试                                                                                                         | 回滚方式                              |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| **0. 基线冻结**              | `callsites.md`；新增机器可读 manifest 与扫描脚本；复用 `xfl-callsite-extracts.md`                                                                | 不改生产代码                                                 | 精确锁定 A1-A6/B1-B5/C1-C6/D1-D2/E1-E13、XFL 副本和当前 SWF hash；全基线测试绿                                                   | 删除工具提交即可                          |
| **1. canonical dirty**   | `SaveManager.as:markDirty/hasPendingChanges`；`通信_lsy_原版存档系统.as`                                                                   | 置位不触发存盘；成功 full save 才清                                | 补 `_settingsMigrationPending`、KeyManager migration；三处悬空 `存档系统.markDirty()` 真正可调用；测试所有 latch false/pending/throw | 回滚新 shim；保留旧 dirty setter         |
| **2. 增加四层 API**          | `SaveManager.as:saveAll/_onDebounceFire/flushNow/_doSaveAll` 周边；shim 新方法                                                          | strict true 仍仅代表 SOL flush true；无 dirty 早退；无 strict 合并 | 新旧 API 分别计数；request Void；clean strict 仍一次物理存盘；legacy 与 new 不双计数                                                 | 调用点尚未迁移，可直接回滚 API 提交              |
| **3. scheduler 正确性**     | `SaveManager._onDebounceFire`、pending token 管理                                                                                    | request 不承诺 durability，但不能因 in-flight 静默消失             | timer in-flight 重挂；strict 重入不先删 pending；callback 异常不逃逸 wheel；dirty 与 sv3 保留                                     | 恢复旧 scheduler；该提交与调用点迁移分离         |
| **4. API/物理分桶**          | `SaveManager._saveApiStats`；`flushSO` 增加 lane 参数；`SaveManagerTest`                                                                | 现有八分桶名称与含义不变                                           | ingress/request disposition/full origin/strict outcome/flush lane 精确测试；reason 只接受注册 ID                          | 新桶可独立回滚，不影响存档格式                   |
| **5. SafeExit 真序列门**     | `SafeExitPanelWidget.Arm/OnUiDataChanged/TryAuthorizeExitConfirm`                                                                 | 只有本轮 safeExit 对应的 post-Arm save sequence 才能退出          | Arm+sv2 拒绝；Arm+sv1+sv2 接受；background save 不授权；原取消/重试/超时门全绿                                                      | 单独 C# 提交，可直接回滚                    |
| **6. D1/D2**             | `商城系统_WebView.as:shopPanelClose/shopSaveCart`                                                                                     | checkout/claim strict finality 不变                      | 等 A① WIP 定型；连续编辑合并为一次；request 后 strict 总物理一次；K 店 false exact restore                                            | 两个 callsite 单独回旧 `自动存盘`           |
| **7. B3/B4/B5**          | `GameSettingsPanelService.executeApply/executeSave`；`CharacterBuildService` bridge                                                | durable 后才 success/finalize                            | settings/key migration latch 门；clean strict 物理一次；B5 false 不 finalize                                            | 各文件独立回旧 `flushNow`                |
| **8. A1/A6/B2**          | `UI交互_lsy_UI管理.safeExit`；`StageRunSession.requestReturnBaseLocal`；`CharacterCreationService.flushCharacter`                       | false/pending/throw 均不越 transition                     | SafeExit Host 集成；Stage prepared manifest；建角 tutorial gate；真实重启                                                  | 每个 transition 独立回旧入口              |
| **9. A4/A5/A3**          | `ItemUseService.flushSave`；`LootContainerService.flushSaveVerified`；`PlayerAssetTransaction.performStrongSave/flushStrongSaveNow` | 领域恢复粒度和 receipt 次序不变                                   | ItemUse restore；Loot batch/standalone/terminal；PAT/K 店全矩阵；save-image restart                                    | 保留 wrapper，仅回滚 wrapper 内部目标 API   |
| **10. A2 Reward**        | `RewardInboxService.flushSave(cutName)`；测试 double/计数钩子                                                                            | 八 cut、false→pending、N+1 全冻结                            | N=1/2/20/50；两层计数；cut 精确序列；10 fault-cuts；真实重启；map-loot 648/648                                                   | wrapper 内一行回旧强存盘，probes 不动        |
| **11. B1 SceneChanged**  | `通信_fs_帧计时器.as:SceneChanged hook`                                                                                                 | 无条件；严格位于 `deactivateAll()` 前                           | dirty=false 仍完整存盘；pending request 被吸收；trace 顺序断言                                                                | 回旧 `flushNow`，位置不动                |
| **12. XFL E1-E13**       | `03-XFL帧脚本证据`列出的 XML；必要时主/live 双份                                                                                                 | 原有 guard 保留；未证实路径保持无条件 request                         | XML scanner、CS6 publish、FFDec、reason journey、SWF hash；legacy 静态+运行双证据                                           | 回滚 XML 和发布 SWF 成对进行               |
| **13. XFL C1-C5**        | 奖励/系统 UI XML，C1/C2/C3/C5 双份                                                                                                       | 关窗与手动保存仍同步 durable                                     | 五类人工旅程；即时杀进程重启；strict 物理桶；同源 parity                                                                             | XML+SWF 成对回滚                      |
| **14. C6/暗面清理**          | `商城主mc.xml`；`SaveManager.saveShopCart/saveShopPurchased`；shim dead delegates                                                      | 不改变 live 路径失败恢复语义                                      | 证实 dead 才删；若 live 保留双写并开独立 ADR；墓碑/迁移 direct flush 不纳入四层                                                         | 保留 compatibility delegate；恢复旧 SWF |
| **15. R3a 有序化**          | `ArchiveTask.HandleAsync/Process/HandleShadow/TryWriteShadowAtomic/RunConsistencyCheck`；必要时 `MessageRouter`                       | shadow 仍不代签 durability                                 | 强制 S2 先完成模拟；shadow/delete/reset/load 顺序；tombstone TOCTOU；写失败不更新 prev                                            | 无 schema，单独回滚队列提交                 |
| **16. R3b reader-first** | `SolResolver.Resolve`；`SaveMigrator`；`IArchive*`；Host slot metadata                                                               | legacy snapshot 仍可读；clocked snapshot fail closed       | revision stale/equal-idempotent/equal-conflict；generation；delete/recreate；userEdit/seed/repair；SOL/shadow fork  | 保留 reader，关闭 enforcement          |
| **17. R3b emitter**      | `SaveManager.packGameState/pushShadowWithConfirm/loadAll/preload`                                                                 | local SOL true 仍先于 shadow；失败不发 shadow                  | clock 内外一致；失败 revision 空洞；同秒多 save；重启后单调；旧 reader fallback 测试                                                   | 关闭 emitter，reader 保留              |
| **18. legacy 收尾**        | shim、静态门、测试文档                                                                                                                     | 旧发布 SWF 仍能运行                                           | 最终产物零旧调用后先 deprecated，不立即删除；至少跨一完整发布周期                                                                          | compatibility wrapper 原样保留        |

---

# 最终裁决语句

**四层 API 现在可以落地，但其首要价值是把“标脏、最终请求、同步 durable cut、transition barrier”从命名和治理上彻底分开，而不是立即减少 strict fence 的物理次数。**

性能收益第一阶段主要来自：

* request 路径的显式合并；
* 已证明安全的 dirty guard；
* 去除 dead/legacy 调用；
* 防止 pending request 与 strict fence 重复执行。

strict fence 的性能优化仍必须在业务 cut、journal 或增量序列化层解决，不能通过改变 `true=durable` 的定义、全局 dirty 早退或透明异步化获得。R3 则应作为独立一致性专项推进：**先有序化和封墓碑，再引入持久化 incarnation/revision；不接受半套 sequence 方案。**
