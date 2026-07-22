# 游戏系统索引

**文档角色**：游戏系统 canonical 索引。**最后核对代码基线**：工作树基于 commit `6ae2323aec90a5475470b235a1303df76e18098c`（2026-07-22）；地图箱全正网格 Web-only 变更尚未提交、编译或部署，旧 promotion 只作单-canary 历史证据。

---

## 0. 核心代码库速查（org.flashNight 七大包）

| 包 | 职责 |
|----|------|
| **arki** | 游戏引擎核心（战斗/渲染/场景/物品/单位） |
| **aven** | 协调与测试（EventCoordinator、Proxy、测试框架） |
| **gesh** | 通用工具库（array/string/number/object/pratt/path/xml 等） |
| **hana** | 小游戏资源（库符号注入主文件运行时） |
| **naki** | 数据结构与数学（排序、随机数、缓存、插值） |
| **neur** | 事件/控制/计时/状态机（EventBus、计时器三级体系、Tween、导航） |
| **sara** | 物理引擎（粒子、约束、碰撞、复合体） |

核心类库路径：`scripts/类定义/org/flashNight/`

---

## 1. 子弹系统
- **位置**：`scripts/类定义/org/flashNight/arki/bullet/`
- **核心**：BulletFactory（工厂模式创建和管理子弹实例）

## 2. Buff/属性系统
- **位置**：`scripts/类定义/org/flashNight/arki/component/`
- **核心**：BuffCalculator 等组件
- **审查文档**：`tools/BuffSystem_Review_Prompt_CN.md`、`tools/BuffSystem_NestedProperty_Review_Prompt_CN.md`（v2）

## 3. 事件系统
- **位置**：`scripts/类定义/org/flashNight/neur/`
- **核心**：自定义事件总线、EventDispatcher 模式
- **审查文档**：`tools/EventSystem_Review_Prompt_CN.md`

### 场景事件阶段
- `SceneChanged`：场景切换的根事件，用于清理旧场景状态、刷新坐标/表现/UI 快照等直接响应。
- `SceneRuntimeReset`：由 `scripts/通信/通信_fs_帧计时器.as` 在 `EnhancedCooldownWheel.I().deactivateAll()` 和运行时保护状态重置后发布。只用于需要在全局计时任务清理后重建循环、对象池或运行时句柄的子系统，不是 `SceneChanged` 的通用替代。
- 当前明确订阅者：弹壳系统在该阶段重建弹壳池与全局更新循环，避免 `EnhancedCooldownWheel` 全局清理后出现外部 running flag 假活。

## 4. 计时器系统

分层架构：

| 层级 | 组件 | 位置 | 说明 |
|------|------|------|------|
| 帧驱动 | `"frameUpdate"` 事件总线 | `ServerManager.as` 每帧 publish | 全局帧心跳源 |
| 轻量层 | `EnhancedCooldownWheel` | `neur/ScheduleTimer/` | 128 槽位时间轮，最大延迟 **127 帧（~4.2s@30FPS）** |
| 重型层 | `TaskManager` + `CerberusScheduler` | `neur/ScheduleTimer/` | 三级时间轮 + 最小堆，最大延迟 60 分钟，支持重入/暂停/生命周期清理 |
| 通信层 | `_root.帧计时器` | `scripts/通信/通信_fs_帧计时器.as` | TaskManager 全局 API 封装 + PerformanceScheduler |

- **禁用原生 `setTimeout`/`setInterval`**：游戏逻辑与帧动画深度耦合，必须使用帧驱动计时器
- **零间隔持久任务顺序契约**：同一 `TaskManager` 按任务本次进入 `zeroFrameTasks` 的顺序执行；持续留表的 `0→0` 更新不换位，分发外 `0→正→0` 按重新入队排尾。ID 快照在时间轮和 pending reschedule 之后的零间隔分发阶段入口收集：时间轮回调新建零任务本次 `updateFrame()` 执行，零任务回调新建 ID 下次执行。快照时已有 ID 在分发中重入不提供延后保证；生产者必须先于消费者入表
- **审查文档**：`tools/TimerSystem_Review_Prompt_CN.md`

### 选用决策

**默认选 EnhancedCooldownWheel**（轻量、GC 友好）。升级到 TaskManager 的场景：
- 延迟超过 127 帧（CooldownWheel 位运算会回环）
- 需要生命周期自动清理（`addLifecycleTask` + `EventCoordinator.addUnloadCallback`）
- 回调中需要修改其他任务（v1.8 重入契约）
- 需要暂停/恢复/动态延迟调整（`delayTask`）

## 5. 摄像机系统
- **位置**：`scripts/类定义/org/flashNight/arki/camera/`

## 6. 音频系统
- **位置**：`scripts/类定义/org/flashNight/arki/audio/`
- **核心**：LightweightSoundEngine（实现 IMusicEngine 接口）
- 音频资源目录：`music/`、`sounds/`

## 7. 物理引擎
- **位置**：`scripts/类定义/org/flashNight/sara/`
- **功能**：粒子系统、物理约束、表面碰撞检测

## 8. 深度管理（已投入使用）
- **位置**：`scripts/类定义/org/flashNight/gesh/depth/`
- **核心**：DepthManager.as — Twip Trick 模运算 Y 排序，swapDepths 劫持透明接入
- **测试**：DepthManagerTest.as（30 功能 + 性能基准）

## 9. 数据结构与算法
- **位置**：`scripts/类定义/org/flashNight/naki/`
- **内容**：DataStructures（AVL/红黑树/BVH/图/堆/并查集/LRU/BigInt 等）、RandomNumberEngine（LCG/MT/PCG）、Cache、Interpolation、DP、Sort

### 排序子系统（`naki/Sort/`）

**主力排序：TimSort.as**（v3.3，稳定）— `sort()` + `sortIndirect()` 两入口。文件头"AS2/AVM1 平台决策记录"是项目中最详尽的 AVM1 字节码实测总结。其他实现：PDQSort、PowerSort、NaturalMergeSort、InsertionSort、QuickSort。

| 场景 | 推荐 | 原因 |
|------|------|------|
| 极小数据（≤10-20） | 手动插入排序 | 避免 C++ 桥接固定开销 |
| 有序/近似有序、需稳定排序 | TimSort | O(n) 最优，极限优化 |
| 原生 `Array.sort()` | **谨慎** | 朴素快排，有序数据退化 O(n²) |

## 10. 通用工具（gesh，21 个子模块）
- **位置**：`scripts/类定义/org/flashNight/gesh/`

### 高频子模块

| 子目录 | 核心类 | 用途 |
|--------|--------|------|
| `array/` | `ArrayUtil`、`ArrayPool` | ES6 风格数组方法（**仅限测试**）；数组对象池 |
| `number/` | `NumberUtil` | `clamp`/`normalize`/`remap`/`defaultIfNaN`/`toFixed`、角度转换 |
| `object/` | `ObjectUtil` | 深拷贝（循环检测）、`deepEquals`、多格式序列化 |
| `pratt/` | `PrattEvaluator` | 表达式求值引擎，`createForBuff()` 供 Buff 动态公式 |
| `string/` | `StringUtils`、`KMPMatcher` | HTML 编解码、压缩（LZW/Huffman）、KMP 匹配 |
| `path/` | `PathManager` | 资源路径管理与环境检测 |
| `xml/` | — | XML 解析工具（详见 [data-schemas.md](data-schemas.md)） |

> 其余 14 个子模块（func/property/iterator/json/symbol/arguments/depth/text/tooltip/toml/fntl/regexp/paint/init）按需查阅源码目录。

## 11. 小游戏系统（未投入使用）
- **位置**：`scripts/类定义/org/flashNight/hana/`
- 作为资源文件存在，库符号注入主文件运行时（详见 architecture.md「子 SWF 加载与通信」）

## 12. 关卡系统
- **帧脚本**：`scripts/逻辑/关卡系统/`
- **数据**：`data/stages/`
- **碰撞层权威与重绘**：`SceneCollisionManager` 持有边界之外的 polygon 追加快照与 MC 矩形；`ObstacleRenderer` 在普通障碍初绘成功后把同一 MC / 矩形直接登记进该权威集合（AVM1 不保证 `for..in gameworld` 枚举时间轴子实例），`redraw()` 在 `clearAll()` 后只回放全部追加来源与存活登记 MC，不得因任一 MC 卸载丢失普通障碍。`SceneManager.removeGameWorld()` 必须先通过 loot authority barrier；成功后才停帧更新，再在 dispatcher/gameworld 存活时 `dispose()` 精确旧层和 MC/矩形强引用，最后才销毁 dispatcher 与 gameworld；本轮静态门 **35/35**，fresh CS6 runId `a5bbc5c450704bceba88cd92bc387b70` 为 **21/21、4/4 cases、0 failed、Compiler Errors 0/0**；专项门见 [testing-guide.md](testing-guide.md) §2。
- **关卡事件音效**：`StageEvent` 消费 XML 解析后已归一化的 `Sound[]`，只逐项播放有效非空音效名；不得再保留永远不可达的字符串分支。本轮静态回归 **11/11**。

## 13. 装备生命周期系统
- **帧脚本**：`scripts/逻辑/装备函数/`（每个 `.as` 注册 `_root.装备生命周期函数.XXX初始化/周期`，物品 XML `<lifecycle>` 节点按装备绑定，战斗中驱动动画/特效/子弹/buff）
- **用途索引 + API 快查 + 新增 7 步流程**：`scripts/逻辑/装备函数/README.md`（就近 hub）
- **编译真源**：`scripts/asLoaderManifest/frame37.as`（f37_N chunk，**非**旧 `装备函数列表.as`，后者已退役删除）；三方一致性门 `tools/validate-equip-fn-coverage.js`
- ⚠ 与 `org.flashNight.arki.item.equipment`（class 化装备**数值计算**系统）是两套平行系统，勿混

## 14. 套装效果系统（一期实现与实机复核中）
- **设计与验收真源**：[套装系统设计与剑圣一期验收](../docs/套装系统-设计与剑圣一期验收-2026-07-14.md)
- **运行边界**：每单位一个逻辑 `SetEffectController`；一期保留子装备自治 tick 和成员 `<lifecycle>` 完整配置，用 `setGate/effectId/componentId` 在通用 loader 解析前门控。中心 routine 保存必需组件 manifest、共享 context 和 placement 通道；placement 在引用重建后即时校正，预计算任务每帧各采样一次有效肢体的 target-local 基向量，胸甲/腿甲共享 `身体_引用`，手甲消费 `左下臂_引用`，组件 tick 逐帧消费缓存而不重复执行肢体坐标换算。五个 ref 由既有 loader 创建后登记到 effect record，preflight/commit/rollback 保证任一组件失败时整套不提交。头甲的低光夜视与常驻扫描/锁定相互独立。原体抗性表项是开启对应定向破击的负向暴露，不是普通 Buff；一期按 `baseIfMissing=10 + value=75` 聚合为 85，写入层不钳制
- **接线点**：`updateLifeCycles()` 清理后先 `prepare`，再装载单件生命周期，最后由 `_root.主角函数.完成生命周期函数装载()` 执行 `finalize`；一期以仅在五件齐全时激活的剑圣装甲重构作为纵向验收

## 15. 地图资源箱中央裁决、S0 编排与 S1/S2 瞬态战利品容器

- **S0 pause 因果门**：`ChestS0SocketBridge` 在发送 begin 前的同一 AS2 调用栈同步调用 `webPanelPause` 并验证 `_webPanelPauseLease` 已存在；exact begin payload 必须为 `pauseAcquired:true`，Host 拒绝缺失 / `false`。Runtime enqueue 前的 generation-bound pause 写与 PanelHost UI 执行前确认仅作冗余，不能替代 AS2 lease 证明；任一失败仍须精确取消、`openFailed`、零视觉 / Web 副作用且不得 `OpenPosted`。
- **中央裁决**：`BoxInteractionArbiter` 的六个资源箱 preset 白名单只定义**箱体领域准入**，用于防止投影召唤器等带有 `row/col` 的非箱地图元件被劫持；它不是 Web rollout 或网格尺寸白名单，也不得为扩大迁移面而放宽。每个 world 只有一个全局互动监听，一次输入按 `(dx²+dz², registrationOrder)` 选择至多一个箱。`SceneInteractionManager.currentMC` 对箱候选独占，非箱 `InteractionHandler` 与地面拾取仍保留既有共消费。对已识别箱，arbiter 注册失败必须使整个 initialize 回滚，绝不降级为逐 target legacy `subscribeGlobal`；A03F 固定证明零 per-target listener / pickup / 初始化 marker / 残留 record。`unregister` 仅停用、重注册复用稳定顺序；目标 unload 用 `forget` 删除已知记录，world 销毁再整体 cleanup。
- **旧行为保留**：`row <= 0 || col <= 0` 的直投箱仍走原爆落处理；中央裁决只解决多箱 fan-out，不把所有箱强制改成 Lockbox，也不改变投影召唤器 / 地面拾取语义。
- **S1/S2 生产选择器**：进入上述箱体领域后，`LootContainerService.beginFixture` 再以统一 shape classifier 裁决：所有正整数 `row/col` 都是 Web intent；`1×1` 有效，`col<=8 && row*col<=64` 进入 Web，超界或畸形正网格 fail-closed，不 kill、不滚奖、不显示 Flash UI。只有 `row/col` 任一非正的 direct 箱继续地面掉落，保险柜破碎也不走 Web。“所有正整数”不把任意带尺寸的地图元件提升为箱子；六 preset 只负责前一层准入，而箱型名称和当前恰有的 2×4 / 4×4 / 4×8 不参与准入后的 Web 选择。生产 XML 与运行时均不再使用 rollout marker。掉落规则缺省 `最小数量/最大数量` 由 planner 私有归一为 `1/1`，不批改生产 XML。
- **瞬态 loot authority 与精确证明**：`LootContainerService` 在 `LOOT_COMMIT_PENDING` 中先完整预检并一次物化到真实 `ArrayInventory`，再提交 own-kill / opening frame；`chestSessionId ↔ lootContainerId ↔ inventory` 一对一。只允许 loot→玩家权威域；普通物品保留 `BaseItem` 引用，特殊资产经完整预检后事务式目标增加 + source 删除。claim 成功必须同时证明 `authorityRevision` 精确 `+1`、`remainingCount` 精确 `-1`、`lastAppliedOperationId` 为本次 operation 且 exact requested slot 已空；close 成功必须同时证明 revision 精确 `+1`、本次 operation，以及与该 close 意图一致的 expected state / remaining。容量失败只有严格 raw failure shape 与 exact current binding / 完整 known prestate 同时成立，且已知 revision、remaining、lastAppliedOperationId、`closeLease`、`containerVersion`、requested slot 与 slot lease 全部保持不变时，才是可继续队列的零写证明；错误名本身不是证明。AS2 raw failure 不签发 close capability，Host 只在上述 exact prestate 下保留已知 `closeLease/containerVersion`，不能因 `target_full` 丢掉当前 Bound organizer 或随后普通 suspend 所需能力。材料等 collection 域按自身容量裁决，不能用背包空格推断 `target_full`。
- **未知结果水位**：Host 与 Web 各维护独立 unknown-freshness watermark；只有命中 exact pending call / identity 的回包，才可用其中未证明的更高 authority revision（包括随后完整 sanitizer 失败的 success/error response）推进该 unknown operation 的水位；它不覆盖 last-known authority，其他 call/identity 也不得抬高水位。后续 claim/close/query 证明不得回退到该水位以下。unknown claim 只可由精确 `+1/-1/operation/requested-slot-empty` 证明已应用，或由同 revision/count/lastApplied/closeLease/containerVersion/source-slot-lease 的非因果投影证明零写；unknown close 的 ACTIVE 结论也只接受这种精确非因果零写，SUSPENDED/terminal 必须满足因果前滚规则。普通七键 query 不新增 `reconcileAfterCallId` 等 wire 字段；因果性由请求时序、exact pending identity 与独立 watermark 共同证明。
- **终态、挂起与恢复**：`close v1` 不增加业务 wire：空箱优先归一为 `CONSUMED`；非空 X/Esc/backdrop 都以 `abandon=false` 先形成 `LOOT_SUSPENDED`，再关闭 visual binding、释放 exact pause 并回游戏；只有“放弃剩余”二次确认发送 `abandon=true` 并进入 `ABANDONED`。同场景同 anchor 可重开同一 triple/inventory，并重铸 fresh `closeLease/panelInstanceId/openAttemptSeq`；不同 anchor 仍 busy，跨场景或重启不持久化。初次、reopen、mount、navigation 与 socket failure 都保留同一 inventory/anchor 并收束为 `LOOT_SUSPENDED`，空→`CONSUMED`，anchor 失效→`EXPIRED`；未完成 exact journal/effects/proof 时保持 `LOOT_COMMIT_PENDING`。Flash renderer、claim-only adapter 与 observer recovery 不再是产品路径，禁止用回退掩盖缺陷。
- **旧资产边界**：地图箱迁移完成的判据是旧 renderer/API/生产调用不可达，而不是删除所有名为 `资源箱界面` 的库 symbol。`flashswf/UI/物品与技能相关界面/DOMDocument.xml` 仍把该 symbol 作为 `仓库界面` 实例使用；仓库拆分或迁移前不得物理删除共享 symbol，后续清理只可删除地图箱专属且已证明不可达的脚本/符号。
- **场景销毁屏障**：场景切换与 `cleanupForRestart` 必须在任何 world/dispatcher/collision/timeline 销毁前调用 `LootContainerService.expireScene`。`SceneManager.removeGameWorld/dispose/reset` 与根清理入口返回 Boolean；若 authority 仍 pending，返回 `false` 并完整保留场景，根时间轴停止并只排一个下一帧重试，成功后才恢复淡出并执行 teardown，禁止“先拆世界、后补 loot terminal”。
- **普通 loot query wire**：Web `lootQuery` 经 Host 重建后的 Host→AS2 wire 严格七键 `{task,action,callId,v,chestSessionId,lootContainerId,containerEpoch}`，不能携带 attempt 或 proof identity。
- **loot recovery wire 与并发门**：Host→AS2 `lootPanelRecovery` 严格八键，在 identity/attempt/reason 之外加入 Host-only opaque `recoveryNonce`，reason 只允许 `web_mount_failed|web_open_failed`；detached reconcile 只发严格九键 query，在普通业务 shape 上增加 `openAttemptSeq/recoveryNonce`。proof 字段不投 Web，AS2 15 键 response→Host 20 键 projection 不变；普通业务 query 不得推进已登记 nonce 的 detach fence。Host 只以 exact pending proof entry 收到的 validated `success=true` 投影 settle，失败 tombstone 不能冒充。`LootTask→Coordinator` fresh admission lease 封锁 write-unknown/detached/native-close/pause-release 未决 flow；`PauseReleasePending` 只允许 exact coordinator-owned retry，禁止 generic unpause 和提前新开。socket replacement 先保留新 generation，再发布旧 disconnect，最后发布新 ready；frame 同时命中 generation/client/stream，每代 disconnect 至多一次，旧代不得 PostToWeb、释放 pause 或关闭 replacement。AS2 completed proof ledger 只由更新 accepted callback / exact recovery / exact proof query 剪除严格更旧项；容量无法安全腾出时以 `recovery_history_full` fail-closed，不做盲目 LRU。
- **领取与嵌入式整理**：Web claim-all 冻结启动时的有界 `physicalSlot` 队列并严格串行；capacity exact no-write 才跳过，unknown/no-progress 熔断并保持 binding，`target_full` 不关闭。只有 ordinary `target_full / inventory_full` 把主动作切为同一 tracked `loot` panel 内的背包—战备箱 organizer；全程保持同一 `panelInstanceId`、Coordinator `Bound`、原 pause lease 和 AS2 `LOOT_ACTIVE`，零 `lootClose`、零 panel rebind/跨 panel。organizer 只允许背包↔战备箱自动转移，以及经二次确认的背包整格 discard；collection cap 不映射 organizer。子页中的 X/Esc/backdrop 优先请求返回 loot，必须等 inventory 无 busy、无 `refreshRequired` 且 ready，再取得 fresh `ACTIVE` loot snapshot 才可回主页；任一同步失败都留在子页且不 replay claim/close。只有 loot 主页的普通 X/Esc/backdrop 继续按 non-abandon close 进入 `LOOT_SUSPENDED`。busy X 保持可点但复用单飞门。应用重激活焦点经 generation/single-flight/200ms/前台复核恢复，外部前台不得被抢焦；v1 不从 Web cache 或新 Flash 进程复活。
- **organizer Host 边界**：只接受严格七键 `{type,domain,panel,cmd,callId,panelInstanceId,payload}`，固定 `type=panel/domain=inventory/panel=loot`，且仅允许 `snapshot/autoTransfer/discard` 的严格 payload。Host 必须在 `LootPanelCoordinator` 同一锁内用 `IsBoundVisualExact` 原子证明 state=`Bound`、active binding、PanelHost 名称与 exact `panelInstanceId` 全部一致，再路由到 `InventoryTask`；回包继续回显 `panel=loot` 与 exact instance。loot 占用 PanelHost 时，任何其他 panel 的 `close` 都作 foreign close 隔离，不得释放 loot pause 或关闭其 binding。
- **受控 agent 标题帧门**：受控进档顺序固定为：记录本次 `start` 日志水位 → 在该水位后同时取得 fresh handoff 与真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`（watchdog 事件不计，缺失报 `title_frame_not_observed`）→ 仅调用一次 `agentEnterResolvedSave()` → helper fail-closed 调 `_root.notifyGameEntered()`，同包发送 attempt-bound `s:1|ga:<_bootstrapAttemptId>`，再以 `gotoAndStop` 进入“读盘”帧 → Host 排除 legacy 无 `ga` 包、将 receipt exact 绑定当前 attempt，且只有该 receipt 才设 `gameEnteredObserved=true` → runtime ready。每次 `start` 与后续 `s:0` 都重新加锁；裸 `s:1`、helper 已调用、watchdog 或 `revealPerformed` 均非成功证据。
- **S0 会话**：`ChestSessionService` 只认 source `as2-chest-s0` 与 fixture `insurance-safe-s0-v1`。成功结果必须由本服务发起的同步唯一 kill 触发开盖 callback；根 `资源箱开启脚本/资源箱破碎脚本` 仅对该 active fixture 短路到无奖励 spy，其他箱继续旧奖励路径。begin 的 capability consume、attempt reserve 与 active identity 发布原子化；navigation pending 时 begin / execute fail-closed，`resumeActive=true` reconnect capability 禁止消费但继续持有 authority 收敛。已消费 bootstrap 在 suspend 后重观察 marker 不得再次 ack 或收束 authority，只有 fresh Host bootstrap 可恢复 orphan（S08）。ordered identity adoption 只允许 `_flow == null`；已有 flow 时，同 session/epoch 但不同 `flowHandle/panelInstanceId` 的 ApplyResult/OpenFailed 必须被消费但保持零状态、kill、ack，原 exact identity 仍可成功（S09）。迟到 begin success 只有 exact-match 已收养 flow 才可幂等接受；异 identity 丢弃，同 identity 不重复 terminal。old openFrameSpy 同 target 重入新 session 后再抛异常时，旧回调不得污染新 authority（S10/A20）。tracked open 必须先成功取得真实全局 pause；`AssertWebPanelPause` 返回实际 bool，`requireTrackedDelivery` 在 backdrop / Web 视觉副作用之前 fail-closed，返回 `false` 或抛异常不得报告 `OpenPosted`。result ack 未知时不重放写：Host 立即直发 AS2 causal query，并由 state-driven reconcile tick 按 coordinator state 重试，不依赖 Web `result_query` 投递；terminal authority projection 会缓存并重放。reconcile tick 登记 in-flight，并在每个副作用前复核 exact identity、generation 与非 release；`TryRelease` 遇 in-flight > 0 延后，tick `finally` 归零后再 release，旧 tick 不得跨 fresh-arm identity；timer 的 exact identity / generation 复核与 publish 同锁原子化，旧 attempt 不得覆盖 fresh identity timer。`KnownTerminal` 下 `releaseTrackedPause` callback 首次返回 `false` 或抛异常须保留 terminal flow 并定时重试，期间不得 reset / fresh arm；仅成功后才发送 `pause_release` 并 fresh arm。generic unpause 的状态检查与 generation-bound write 同 begin 线性化；失败保留 pending，reconnect / Web ready 未成功补发前禁止 fresh-arm。tracked reservation / lease 任一存在时，PanelHost queue 同锁拒绝 generic open / close，只接受 exact identity close。普通 `resumeActive=false` bootstrap 把 begin-in-flight orphan 收敛为 known-no-write。Web `close_ack` 丢失走 Host `close_query`，native exact-close 失败独立重试，不重开已 teardown DOM；release 必须同时具备 AS2 terminal、Web DOM close 与 native PanelHost close。`NavigationStarting` 先清 WebOverlay readiness，再锁内捕获 active，无 active 立即使旧 idle arm 失效；成功新文档等真实 ready，失败 / same-document 恢复旧 readiness 后 fresh rearm，但 document teardown 仍只认 matching `NavigationId + ContentLoading + success`。随后 result 前撤销、result 后查询且均不重放写；panel-busy 只在 Host idle 后以新 capability 重臂。
- **S0 并发与隐私加固**：disconnect generation 使用单调 high-water，disconnect-before-Ready 与更高 generation 的先行 disconnect 都会封死迟到 Ready、作废旧 binding/retry 并精确关旧 native panel；`wire_loading` 只代表既有 LazyLoader owner 尚未 settle，不抢 owner、不二次 load，Host 以 fresh capability 重臂。pending generic unpause 在任何 arm 早返回前补发，未成功前 begin 最终提交 fail-closed。bind timeout 后的迟到原始 bind ack 不再恢复 `OPEN_BIND_UNKNOWN`，只有 exact bind query 可以恢复。`OpenPosted` completion 复核 generation/document/navigation/process，失鲜时不启普通 bind timer并重试 exact close；旧游戏进程被替换时旧 flow 终结为 `EXPIRED`。bind/authority/binding/retry/reconcile timer 都按 exact owner/version 管理；外部副作用登记 outbound action，Dispose 后不启动新动作。pause release 必须追随 callback 中采用的新 generation，bootstrap ack 最终提交重验 connection/process/pause-role。Web `onClose/onForceClose` cleanup 抛错不得阻断 exact close/teardown proof，只记固定 code、不记异常文本（AW26/AW27）；任一含 S0 身份的 panel open 日志把整个 `initData`（含嵌套 harness identity）替换为 `[redacted]`（AW28/AW29）。专属 source/fixture 任一锚点或完整九字段 `OPEN_KEYS` shape 进入 reserved；普通真实 PanelHost partial 与非专属 8/9 字段碰撞在 `ARMED/IDLE` 直通，reserved 后 exact validator fail closed。非 `ARMED` reserved `onOpen` 只安排本地视觉关闭 microtask，以单调 open/rebind sequence 和 element token 防陈旧，仅在 token 最新、`!current` 且仍为同一 active Lockbox 时关闭；cleanup 抛错仍令 `active=null` 并只记固定分类，不伪造 proof、不改变 authority/consume。ordinary rebind 取消旧 cleanup 并恢复 DOM，reserved rebind 不关闭 ordinary active。rearm 必须 validate-before-atomic-replace，坏新 arm 不得破坏旧 arm（AW30/AW31）。Lockbox `minigame_session` 即使在 pause 释放后到达也先去敏；畸形信封只记固定 drop code，原始 secret 不落日志。
- **源码层**：S0 AS2 bridge / production callback、Host `DevLockboxS0Runtime` / tracked queue、production overlay 的默认休眠 bootstrap / actual-wire 保持已接；两道 S0 门仍默认关闭。S1/S2 已接 AS2 `LootContainerService` 与地图 / 回调 / strict 7/8/9-key query/recovery proof，Host `LootPanelCoordinator/LootTask`（含 admission fence、bind/close/pause retry、exact proof settlement 与 socket generation ordering）、Web `loot` 四模块 / lazy registry / CSS。当前工作树把全正网格能力选择器与 Web-only failure 收束接入同一 authority；生产 XML/runtime marker 和 Flash recovery renderer 不再属于当前路径。该范围尚未通过本轮 fresh CS6 / publish / E2E，不能与旧单-canary正式树混同。
- **自动层**：S0 历史门保持可追溯。当前全正网格静态门必须覆盖全部真实网格声明、item catalog、缺省数量 1/1、`1×1..64` / `col<=8`、超界 fail-closed、direct 与 break 负向边界、生产 marker=0；准确计数以最新脚本输出为准。Host/Web 协议与既有定向测试未改；本轮尚未产生 fresh CS6 TestLoader trace、`asLoader.swf` publish 证据或当前 source 真机 E2E，故只能称 source-static 通过，不能称 compiled / promoted / deployed。
- **候选层**：`c-fca19ba526c4-08846e81b3-20260721t060547571z-978633c6` 只是嵌入式 organizer 与 attempt-bound agent 标题帧门之前的历史 candidate；其 build identity `FCA19BA526C4120B240B594FDD29786261A318F805A0ACD8001D48A842B60F24`、payload closure `B2AF3BEFCBA055FC68F3D49A9A450B6D946F20DD5A8E28FEAF0EC8B32BFAC4CD`、Core SHA `231388D757201454655E95876834155E17ED118476C0B5806A96E2A0A6492780` 曾达到 `candidate_executed / NOT_DEPLOYED`，但不能代表当前 source tree。随后构建的精确隔离 candidate `tmp/runtime-candidates/v2/c-2a0cddb077b7-08846e81b3-20260721t100014612z-f32a40a3` 的 native build identity 为 `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107`、payload closure 为 `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C`、Core SHA-256 为 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`；它在隔离运行阶段已精确启动并完成单 canary 资源箱领域闭环，当时状态为 `e2e_verified / NOT_DEPLOYED`。该结论只描述 promotion 前的候选历史；同一 build identity / payload closure 随后已按下述发布层完成正式 promotion 与标准入口复核。该 candidate 的 25-file native bundle 不含 `launcher/web`，运行时从当前 `projectRoot/launcher/web` 读取外部 Web，因此相同 native identity 不绑定本轮 Web 修复；Web 证据须另以源码 SHA-256 与当前 WebView2 实机链绑定。候选随后优雅 shutdown，Guardian PID **14820** 与 HTTP/XMLSocket **1192/1924** 均退出，Flash CS6 PID **20444** 保留。
- **实机宿主层**：新 candidate 已载入专用槽 `cf7_agent_loot_target_full_v1`；attempt `62f04fa249c44d94ba3171f619e61754` 严格按 start 后日志水位→fresh handoff→真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`（watchdog **0**）→唯一一次 `_root.agentEnterResolvedSave()`→同包 `s:1|ga:<exact attempt>`→Host exact receipt 执行，最终 `readyForRuntimeAutomation=true`、`blockers=[]` 且 `saveRuntime` exact loaded；人类同时确认正常标题帧唤起的 NativeHud 可见且指令有效。满背包混合箱随后在同一 `panelInstanceId=panel.loot.8a1227b8229f4eef99ac052395e4e12b` 完成：抗生素并入已有堆叠、黑暗吉他因满背包保留→同面板 organizer→真实二次确认丢弃整格牛肉罐头 **×16**（背包 50→49）→fresh `ACTIVE` snapshot 返回战利品且无 close/rebind→领取黑暗吉他→terminal close/unpause 自动回游戏。普通关闭回归又在 **18:37:08** 首开非空箱，**18:37:18** 单次 close 后 PanelHost 以 `instanceDigest=83e7e242b7fc / reason=suspended_already_closed` 关闭，**18:37:19** unpause；**18:37:21** 同锚点 fresh reopen，人类目视强化石 **×2 + ×3** 内容一致且无旧 AS2 UI；**18:37:29** 两次 claim 与一次 terminal close 以 `instanceDigest=6ef2f7f9fcb2 / reason=terminal_already_closed` 收束并 unpause。由此该隔离 candidate 当时已完成单 canary 的 organizer、普通 suspend/reopen 与一次点击 modal 实机闭环，可写为 `e2e_verified / NOT_DEPLOYED`；同一身份后续的正式结论见发布层与部署层。历史 attempt `b9bb7f9a800f479cba04542820fa2748` 与冷启动 `7560a368fdb64dc5b7e2d2e19377add7` 只继续作为旧交互的经济写/持久化证据。
- **发布层**：immutable Git-tree request `FBA91942C57DC3E6662AB77AC88EEAE3CA2AFA3C82BF5FFEA6BC68CFD6C31AE4` 已对 release tree `e1e6e059f148a640b3e37cbf1d912f297156d956` 形成 `cf7-runtime-release-consensus.v2`，并于 `2026-07-21T16:39:47.2329893Z` 完成正式 promotion。生产身份为 build `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107` / payload closure `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C` / artifact source `FCAF63616D73EE54912CC71332B38E318E9F087B18DC8BA19C923A065820F92A` / recipe `75723146B70547AD1B87F54A19A806A356501290D1507CBD43952ECB9C5906EE` / toolchain `CA5BCE58D3BBE7C77D37454B89651F4FB3F7D3F678007299BB641D5E8CE2A17F`；Core SHA-256 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`，promotion commit 为 `6218f8b1d82efc57b77131616667fe45f3033297`。这使同一身份从历史 candidate 的 `e2e_verified / NOT_DEPLOYED` 前进到 `promoted`，但不改写其候选阶段事实。
- **历史部署层**：旧单-canary tree 曾在 `C:\cf7-standard-entry-20260722\resources` 通过 request / promotion / standard-entry，attempt `4eae1360…7158` 完成 claim、terminal close、unpause 与存盘，故**仅该历史树**曾达到 `standard_entry_verified`。它不能覆盖当前全正网格 Web-only source、S0 actual-feature 或完整迁移。冻结边界见 [S0 ADR](../docs/地图资源箱-S0无奖励编排-ADR-2026-07-17.md)、[S1/S2 ADR](../docs/地图资源箱-S1S2真实战利品容器与Web双栏-ADR-2026-07-18.md) 与 [专题治理文档](../docs/地图资源箱-Web战利品工作台与开锁流程-前期调研-2026-07-17.md)。

