# 存盘风暴止血：Reward 相邻 durable-cut 桥接与存盘次数回归门 — ADR（2026-09-03）

> 本文是跨多次会话工作的**压缩锚点**：记录从 loot 面板死锁到存盘风暴的完整事故链、已落地修复、GPT Pro 裁决全文要点与施工单。后续施工以此为唯一基线，不重新推导。

## 0. 当前状态快照（施工起点）

**已落地并验证（未提交 git，全部在工作树）**:

| 批 | 内容 | 验证 |
|---|---|---|
| loot 租约+情报修复 | `LootContainerService` 槽位稳定租约（解绑容器 mutationRevision + 单槽失效）;`LootMaterializationPlanner`/`StageRunSession.materializeRewards` 情报上限过滤（planInformationAcquire，满仓零价情报不生成） | map-loot 链全绿；用户现场复验通过（装备箱不再出情报、部分领取不再死锁） |
| loot 契约登记 | `panel-contracts.v2.json` 第 6 域 loot(7 命令）；校验器新增 `normalized-exact-identity` 模式锚点；变异测试 70/70 | `validate/test-panel-contracts` 全绿 |
| ItemUse 回滚 | `ItemUseService.executeConsume` 收据失败时对称快照恢复（restoreConsumeState + 对冲播报） | 含在 217/217 |
| rewardInbox 形状修复 | `normalizeClaimRootResultShapes`：终态/活动根 `result` 三 id 列表空对象→[]（治"材料盒子 reward_inbox_full"根因：AMF0 空数组磨形 → 车道 quarantine) | 含在 217/217 |
| 空数组二期 | `StageRunSession.normalizeSaveData`（结算五字段）+ `SaveManager.normalizeTaskAndPetShapes`(pets 内层槽/tasks_to_do),migrate()/_applyCore 双渠道接入 | 405/405 |
| K 店枚举 | `kshop-runtime.js` definitive 失败集并入 `destination_full` | presenters 33/33 |
| Web 用例 | `test-loot-state.js` 租约轮换/稳定双向用例 | 71/71 |

**测试基线**:map-loot 链 634/634(217+12+405) 起步；Commit 0-5 施工后见 §4 状态表——当前 **648/648(231+12+405)**,Compiler 0/0,32K retry=0;asLoader.swf 2026-09-03 23:42 已重发（1,234,121 bytes,SHA-256 `3446AF0BD17E5873E1BC88B629CD5D27060A82CFAA5AC2FF51D99812E28EB7AF`，最大函数 31,997B);Reward claimBatch 探针 2N+1 → **N+1**(N=2/10/20 实测 3/11/21);testing-guide.md 门槛已同步 648;`validate-doc-governance.js` 通过。

**验证命令**:`powershell -NoProfile -ExecutionPolicy Bypass -Command "chcp.com 65001 | Out-Null; & 'scripts/run-map-loot-tests.ps1' -TimeoutSeconds 500"`;Web:`node launcher/web/modules/loot/dev/test-loot-state.js`、`node tools/test-panel-contracts.js`、`node tools/validate-panel-contracts.js`。**AS2 改动后必须**:`scripts/compile_test.ps1 -Target publish -TimeoutSeconds 900 -VerifySwf scripts/asLoader.swf` + `node tools/swf-function-sizes.js scripts/asLoader.swf --max 60000 --top 15`。

**编码铁律（本会话三次血泪）**:`.as` 必须 UTF-8 BOM + 保持既有行尾；**禁止用内置 Edit/Write 改 .as**（会剥 BOM/转 CRLF)，一律 Bash python `newline=''` 读写并写后校验；ps1 为 LF+BOM。

## 1. 事故与发现链（已完成部分）

1. **loot 面板"需要核对"死锁**（用户 15:26 现场）：批量领取部分成功（3 装备成功 + 满仓情报 `cap_reached` 跳过）时，AS2 侧兄弟格租约被容器级 mutationRevision 轮换，Web `_claimBatchProjection` 要求幸存格租约字面值不变 → 证明永不可通过 → `reconcile_required` 死锁且面板无法关闭。定性：2026-07-22 跨层契约治理的漏网之鱼（loot 域当时被"已有更强门"放行但未登记）。修复见 §0 第一行；同族普查（agent 报告 `logs/dumps/` 无，裁决包 `tmp/adjudication-save-storm-20260903/02-审计报告/审计1` 有全文）确认无扩散，loot 域补登记进机器契约。
2. **材料盒子无法打开**（用户 18:35 现场，`reward_inbox_full`)：终态 claim root 的空 `blockedEntries/remainingEntryIds` 经 AMF0/JSON 往返磨为空对象 `{}`,`validRootResult` 拒认 → `inspectRootLane` 判 `malformed_claim_root_terminal` → 奖励车道 quarantine（所有礼包拒开）。探针逐字段复刻现场存档实锤。修复见 §0"rewardInbox 形状修复"；空数组审计（裁决包审计2）又发现 `stageSettlement` 五字段同型软锁（每次结算首次落盘 `receipts` 恒空）、pets 内层槽、tasks_to_do——已由空数组二期修复，C# `SaveMigrator` 对应字段集 launcher 渠道本已覆盖，AS2 裸 SOL 路径是缺口。
3. **两次 Flash hang→段错误**(19:18:57、19:48:39，均 0xC0000005/unknown 模块）：收件箱高速连领 + 每秒 2-3 次全量存盘 → `UIFreezeProbe hung_window flash=True` 静默 3-4 秒 → 段错误。证据封档 `logs/dumps/crash-20260903-191857/` 与 `crash-20260903-194839/`;WER full-dump 已前置（HKCU LocalDumps → `logs\dumps\wer`,**收尾时须清理该注册表键**)。TestLoader 300/300 压力循环阴性（AS2 逻辑层无死循环）。
4. **"领取较多物品慢得出奇"** → 存盘风暴专项（本 ADR 主题）。

## 2. 存盘风暴量化证据

- **基准病理（探针实测）**：奖励 claim root 车道 `claimBatch` 全量存盘次数 = **2N+1**(N=2/10/20 → 5/21/41)。机制：`RewardInboxService.advanceActiveRoot` 每条目两处 `persistRootProgress`(prepare :674、applied :730 → :789-798 各一次 `flushSave`)+ admission(A+P0)1 次 + finalize/terminal 1 次。**注意**:`LootClaimCommitCoordinator` 自身无 flush(GPT Pro 纠正）。
- **附加 O(N²)**:`collectRootRemaining`(:981-989）每条目 N×全账簿扫描；每条目 `ObjectUtil.clone(root)`(:667/:680/:716)。
- **同型循环放大源共 4 处**（审计3 全文）：奖励 root 车道（2N+1)、**标准 loot 逐格 claim**(`LootContainerService.as:2115-2121` 每格 `flushSaveVerified`,N 格 N 次）、K 店逐项 claim（一项一命令，N 次）、连开礼包(`ItemUseService.as:143`,N 包 N 次）。
- **SaveManager 三结构结论**:①`强制存盘`=flushNow 立即全量、全游戏无合并（`SaveManager.as:447-478`);②~~带 300ms debounce 的 saveAll 仅 2 个生产调用点~~ **勘误（2026-09-04，裁决包复核）**:`scripts/` 层仅 2 处（商城关闭/购物车），但 XFL 帧脚本层另有 13 处生产调用点（3 处 dirtyMark 守卫：淡出 frame16、新版物品栏/仓库关闭；10 处无条件），合计 15 处，详见 `tmp/adjudication-savemanager-api-20260904/callsites.md`;③dirtyMark 从不触发存盘，用药/拾取/合成/成就/战宠/佣兵/任务/Inventory 写全部 0 次/动作（战斗中捡钱不是风暴源）。
- **物理放大**：一次逻辑存盘 ≈ AMF0+JSON 两次全量序列化 + ≥2 份磁盘产物（SOL+shadow)。
- **崩溃归因（保留）**：存盘风暴是确定性性能缺陷与高可信崩溃放大器，但证据不足以宣称它是两次 0xC0000005 的唯一根因（300/300 只排除压力脚本下确定性死循环）。

## 3. GPT Pro 裁决（2026-09-03，回执 `tmp/adjudication-save-storm-20260903/gptpro.md.txt` 777 行）

**总决：立即施工 `F1′ + 存盘次数回归门`;F5 随后独立提交；F2/F3原案/F4 否决。**

### 3.1 F1′（P0，唯一立即落地的主修复）

不是删两类落盘，而是利用 **`post(child i) == pre(child i+1)`**，把相邻 durable cut 桥接进同一次全量存盘：

```
现状: [A+P0]→[C0]→[P1]→[C1]→…→[C(N-1)]→[T]      = 2N+1
F1′: [A+P0]→[C0+P1]→[C1+P2]→…→[C(N-1)+T]          = N+1（每 child durable prefix 前缀下的理论下界）
```

**实现约束（全部强制）**:①admission `A+P0` 不动，首项 effect 不提前；②child i `applyOrReconcile` 成功后在内存同时完成资产收敛+ledger+result/cursor 更新+下一 child 纯 prepare(`childDescriptor=P(i+1)`)，然后只 flush 一次；③**bridge flush 返回 true 前严禁执行下一 child**（否则实质退化为 F2);④末 child 直接构造 terminal 并与完成态一次落盘，不先存 `cursor=N` 再存 terminal;⑤`publishCommitted/publishAfterDurable` 仍在 durable save 之后（现 :730-732 的次序保持）;⑥capacity decision 同样桥接（capacity child 的 cursor 前进 + 下一 child prepared 同一 save);⑦quarantine 不纳入优化（异常路径保持独立强存盘）。

**隐藏阻断项（Commit 2，发布阻断而非后续清理）**:persistRootProgress 失败时，`exactRootResponse`(:1008-1032/:1403-1417）经 `withSnapshots(record)` 返回"旧 durable root result + 未 durable 当前资产快照"的**跨 cut 混合投影**,Web `_consumeRewardRoot` 先 `_apply(projection)` 再进恢复（loot-state.js:455-470)。必须封死，二选一并三层（AS2/C#/Web sanitizer）同步：a) commit_pending 返回上一 durable projection;b) Reward pending response 不携带可应用资产 projection,Web 保留旧 projection 仅走 exact-query recovery。**不建议回滚资产 effect**（回滚自身可失败且破坏 forward-only reconcile 模型）。

### 3.2 否决项与条件采纳

- **F2(markDirty+K 条/批尾 flush）否决**：恢复粒度降为 K 边界，丢失每 child committed prefix。mini-WAL 变体属新持久化架构，非本轮。
- **F3 原案（帧末/关面板统一存盘）否决**：制造"UI 已确认、资产未 durable"窗口，已返回成功的逐格 claim 崩溃后丢失。
- **F3′ 条件采纳**：只改**命令边界**不改存盘语义——标准 loot 多选/一键领取直接复用现有 `claimBatch`；连续点击可在 Web 发请求前微批聚合（聚合期不确认单格成功；已发出的 standalone claim 保持独立 durable)。
- **F4(flushNow 全局合并）本轮否决**：同步 durable fence 无法透明改异步（true=已 durable 的契约、AVM1 单线程无法推进帧末收集、改 pending 需全部调用方改状态机）。SaveManager API 分层（markDirty/requestSave/flushDurableNow/flushBeforeTransition）留待二次裁决（见 §6)。
- **F5 采纳但 P1 后置独立提交**:advance 入口建一次性 `entryId→ledger entry` 索引；remainingEntryIds 增量维护（成功删、capacity/failed 保留）;quarantine 才重扫真账簿；窄 staged-root 拷贝（orderedEntries 冻结、result 三数组 slice、scalar 显式复制）替代热路径通用深拷贝。**不得**引入新 schema/链表；不得伪称全量 O(N)；保持持久化空数组仍是 `[]`。

### 3.3 存盘次数回归门（必须，精确结构断言）

| 场景 | 强存盘次数 |
|---|---|
| Reward root N 项全 applied(terminal ACK 前） | **恰好 N+1** |
| Reward root N 项全/部分 capacity(ACK 前） | **恰好 N+1** |
| Reward claim N=1(ACK 前） | **恰好 2** |
| 首次 terminal ACK | 额外 +1 |
| 重复 query / 重复 ACK / duplicate write / invalid/stale 拒绝 | 0 |
| 标准 loot standalone claim | 1 |
| 标准 loot claimBatch(N) | 1 |
| settlement terminal close | 额外 1 |

两层计数（防 wrapper 假通过）:①领域层 `_root.强制存盘` 调用数（公式断言）;②SaveManager 物理量（packGameState/_doSaveAll/flushSO attempt+success/JSON stringify/shadow dispatch)。规模 N=1,2,20,50 × all-applied/partial capacity/all-capacity/中间 child failure/terminal save failure/false/pending/throw/restart exact tuple/duplicate 不增资产不增存盘/pending 响应无跨 cut 投影。耗时/P95/字节量只做软观测，不设跨机器毫秒硬门。

### 3.4 临时降压（F1 落地前可选，非必须）

按钮节流对单次 claimBatch 同步风暴无效。推荐 **bounded advance + exact-query 续跑**:`advanceActiveRoot` 每次最多推进 4-5 child 返回 `rootStatus=pending`,Web 让一帧后以同 rootOperationId 发 query 续跑。**必须成对施工**(AS2 降 budget + Web 自动续跑 + 单飞 + 让帧 + backoff)，否则把性能事故改造成用户可见停滞（现 `_consumeRewardRoot` 收到 pending 只进 reconcile_required,loot-state.js:455-470)。fallback:feature flag 每 root 最多 4-5 项（更差，仅极短期熔断）。**禁止**：每格一个独立 root(2N+1→~3N)、强制存盘临时指向 saveAll、先成功关面板再存、凭 dirtyMark 当后台存盘、关闭 commit_pending/quarantine、shadow 合并与 F1 同补丁。

### 3.5 fault-cut 测试语义化（Commit 3 依据）

现 `testRewardClaimRootFaultCutsAndRestartRecovery` 用物理 `failAt=1/2/3` 序号，F1′ 后序号改变会偶然耦合。改为**语义故障点注入**:`before_root_admission_flush / after_destination_before_source / after_effect_before_bridge_flush / after_bridge_flush_before_next_apply / after_last_effect_before_terminal_flush / after_terminal_flush_before_response / pending_projection_response`。测试必须用真实 save-image restart harness(`LootContainerServiceTest.as:4104-4192`)，不得退化为同进程 reset。语义参照基准测试保持：`testClaimBatchCommitsOnceAndIsIdempotent`(:932-961,N 项 batch 只存 1 次）与 `persistedSettlementBatchCommitsAtTail`(:964-1002)。

## 4. 施工单（Commit 序，验收即发布门）

**施工状态（2026-09-03 当天完成 Commit 0-5，全部未提交 git）**:

| Commit | 状态 | 证据 |
|---|---|---|
| 0 观测钩子+两层计数+旧基线 | ✅ | `setDurableCutProbe` + SaveManager `_savePhysicalStats` 八分桶；旧基线 2N+1 固化；map-loot 643/643、character-build 全绿（含 `migrate_3_0_noop` 既有红灯 fixture 对齐修复） |
| 1 F1′ 桥接（2N+1→N+1) | ✅ | `advanceActiveRoot` 重写 + `prepareChildDescriptor` 纯 prepare;gate 翻转 N+1；探针实测 N=2/10/20 → 3/11/21（旧 5/21/41);643/643。既有物理序号 cut 6 按语义修正为 failAt=2(Commit 3 前过渡） |
| 2 mixed-cut pending 投影封死 | ✅ | 冻结 §3.1 选项 b:AS2 `exactRootResponse` 对 pending/commit_pending 响应强制 `snapshots=[]` + `closeLease=""`;C# `LootTask` 边界 fail-closed 拒收带投影 pending;Web `_consumeRewardRoot` 永不应用 pendingCut 投影。645/645 + C# 4553 pass + Web 72/72 + contracts 70/70 |
| 3 语义 fault-cut 重写 | ✅ | `setDurableCutAttemptProbe` 预通知 + 真实存盘边界语义注入（false/pending/throw 保真）;10 切面矩阵（ADR 12 类中 quarantine/ACK/successor 由既有真实重启测试承载），全部 save-image 真实重启 + cut 序列精确断言；648/648 |
| 4 F5 性能清理 | ✅ | `buildLedgerIndex` 索引 + `remainingEntryIds` 增量维护（仅 quarantine 重扫真账簿）+ `shallowRootCutSnapshot` 窄拷贝替代热路径 `ObjectUtil.clone(root)`；存盘次数零漂移（同一道门复验）;648/648 |
| 5 标准 loot F3′ | ✅ 零代码改动 | 勘察确认生产已满足命令边界：`drainClaimAll` 以 ≤50/批 走 `_model.claimBatch`(loot-panel.js:455-550),standalone claim 保持一项一 save;Edge harness **102/102** 含 "claim-all uses one authority batch" 钉死，lazy-cancel 6/6；四项存盘不变量已由 gate 锁定 |

**回归门基线变更**:map-loot 链 634 → **648**(service 217→231、planner 12、stage 405),`run-map-loot-tests.ps1` 与 testing-guide.md 已同步；SaveManagerTest 为自校验计数（fixture 对齐后 239/239)。

- **专项 A(K 店，独立立项）**:batch 前先裁决修正 ①`PlayerAssetTransaction.commit` strong-save false 时命令 finality（现只记 `strongSaveFlushed=false` 仍发 receipt、shopClaim 仍 `claimSucceeded=true`,PlayerAssetTransaction.as:223-236)②purchased row 稳定 identity vs 可变 purchasedIdx ③batch operationId/冻结列表/exact result 证明 ④unknown response reconcile ⑤batch partial failure 政策。未完成前只允许 UI 单飞/cooldown。
- **专项 B（礼包 openMany，独立立项）**：先裁决产品语义——多包一个原子 command（则批尾一次 full save）还是保留每包 durable prefix（则需 root journal/mini-WAL)。不得靠 debounce。
- **发布门**:648/648 基线全绿 ✅ + save-count 门全绿 ✅ + semantic fault-cut 全绿 ✅ + pending 无 mixed-cut 投影 ✅ + Reward happy path N+1 ✅ + 无 bridge true 前执行下一 child ✅(fault 切面 4/5 实证）+ root save/terminal ACK/shadow 分桶监控 ✅(Commit 0 两层计数）+ 弱机实测连续阻塞明显下降（**待测试员现场复验**,asLoader 已重发）。

## 5. 工程与收尾清单（勿忘）

- 未提交改动（约 24 文件）：三轮修复、loot 契约（json+两个 tools)、K 店枚举、rewardInbox 形状、空数组二期、测试 harness(stress/probe)、文档。提交切分待用户定；提交标题全中文并写清测试员回归点。
- 测试文件里的 `stressMaterialBoxOpenClaimLoop`（压力 harness）与探针保留；`testRewardInboxTerminalEmptyArrayShapeRepair` 是空数组参照实例。
- **WER HKCU LocalDumps 键在收尾时清理**（配置见 §1.3);HKLM 写需管理员（当时被拒，故用 HKCU)。
- 崩溃证据包:`logs/dumps/crash-20260903-191857/`(+README)、`crash-20260903-194839/`；若再崩溃,full dump 落 `logs\dumps\wer`。
- GPT Pro 裁决包（含提示词模板）:`tmp/adjudication-save-storm-20260903/`（zip 同目录）。

## 6. 后续路线（2026-09-04 第二次 GPT Pro 裁决已落地）

裁决回执：`tmp/adjudication-savemanager-api-20260904/gptpro.txt`(877 行，唯一权威；本节只是路由摘要）。

**总决：R1 与 R3 分两条发布列车。R1 四层 API 分层采纳、19 步分片施工；R3 shadow 拆 R3a（无 schema 有序化止血）+ R3b(reader-first 持久化 incarnation+revision);R2 原案否决只吸收安全子集；R4 全局 dirty 早退明确否决。**

- **R1 四层 API**:`markDirty()`(Void，置位不是存盘请求）/`requestSave(reason)`(Void,300ms trailing 单 timer,reason 注册表）/`flushDurableNow(reason)`(Boolean,strict 不合并不早退，true 仍只代表 SOL flush true)/`flushBeforeTransition(reason)`(Boolean，可阻止 transition 的 barrier，与 durable 同核不同 ingress/allowlist/测试）。新旧 public 入口各自进同一私有内核、**不得 public 级联**(ingress 双计数）；旧 shim 至少跨一个完整发布周期。
- **19 步施工清单**（回执 §九为唯一工序表）:0 基线 manifest → 1 canonical dirty(`hasPendingChanges()` 补 `_settingsMigrationPending`+KeyManager，接通 3 处悬空 `存档系统.markDirty()`)→ 2 四层 API → 3 scheduler 正确性（in-flight 重挂、strict 重入不删 pending、callback 异常不逃逸 wheel)→ 4 `_saveApiStats` 语义桶（八分桶不动）→ **5 SafeExit 真序列门（现存缺口：Arm 后未记 sv:1，任意 sv:2 可提前授权退出，独立 C# 修复）** → 6 D1/D2（等 K店 A① WIP 定型）→ 7 B3/B4/B5 → 8 A1/A6/B2 → 9 A4/A5/A3(A3 后迁）→ 10 A2 Reward 最后迁（八 cut/N+1/两层计数全冻结）→ 11 B1 SceneChanged 单独迁（无条件、deactivateAll 前）→ 12 XFL E1-E13 → 13 XFL C1-C5（主/live 双份 parity)→ 14 C6（未证 dead 不删、不偷并双写）→ 15 R3a → 16/17 R3b reader-first → 18 legacy 收尾。
- **R3a（可独立提前止血）**:archive 同槽操作单 FIFO executor;tombstone 检查/版本检查/写入/accepted-state 同一临界区；普通 shadow/seed/userEdit 不得清 tombstone，只有显式 recreate 换代；`_prevSnapshots` 只在写入成功且接受后更新。
- **R3b(reader-first)**:mydata.ext.saveClock{schema,incarnation,revision,writer}，内层权威外层速拒；equal revision 内容不同 → fail closed;revision 允许空洞；reset 必须保留 retirement/epoch;reader 先识别 legacy+clock 再开 emitter 再开 enforcement,`lastSaved` 降级为展示/legacy fallback。
- **R4 否决的硬理由**:`hasPendingChanges()` 本身漏 `_settingsMigrationPending` 与 KeyManager;40+ setter 不能证明覆盖；`_doSaveAll()` 承担未必标脏的派生同步；SceneChanged 是刻意无条件安全网。未来只许另建 `requestSaveIfDirty()`/section-dirty 体系，不得改 `flushDurableNow` 定义。
- **回归门要点**：八分桶保持兼容；新增 `_saveApiStats`(ingress/disposition/origin/strict outcome/flush lane/reason 注册表）；防语义偷换三门（clean strict 必 +1 物理、request 返回 Void 静态禁读值、frozen durable 文件禁现 request API);XFL 四层门（manifest/XML exact scanner/CS6 发布/FFDec+旅程 reason trace)。
- **22 项明确否决**见回执 §八；R1 与 R3b 不得同补丁同开关；K店 batch 语义（专项 A③④⑤ 与礼包 openMany）作为下一轮裁决输入，已备 `tmp/kshop-batch-adjudication-input-20260904.md`。
