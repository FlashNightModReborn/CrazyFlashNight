# 游戏系统索引

**文档角色**：游戏系统 canonical 索引。**最后核对系统边界**：2026-07-22。本文只维护稳定设计与入口索引；变动中的 candidate、promotion、测试计数和真人结论归对应实施基线或冻结发布记录，历史证据不能代表当前 tree。

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
- **跨图限时**：`StageManager` 持有单次 `GameStage` 会话的 `StageTimePoolController`；`SubStage/TimePoolRef` 可表达连续、A-B-A 续算和 A+B 重叠池。`WaveSpawner.tick()` 后才推进有效帧，保证同帧通关优先；暂停、对话、转场与未引用子图不扣时，结束/失败/退出/重开清空且不持久化。
- **展示边界**：AS2 独占剩余帧和 `FailStage` 裁决；Launcher XMLSocket `T+|id|seconds|label` / `T-|id` / `T!` 仅向 keyed NativeHud 状态行投影，不能复用按波次重置的 `WaveInformation.Duration`、Buff `TimeLimitComponent` 或 `W/wave_timer`。
- **碰撞层权威与重绘**：`SceneCollisionManager` 持有边界之外的 polygon 追加快照与 MC 矩形；`ObstacleRenderer` 在普通障碍初绘成功后把同一 MC / 矩形直接登记进该权威集合（AVM1 不保证 `for..in gameworld` 枚举时间轴子实例），`redraw()` 在 `clearAll()` 后只回放全部追加来源与存活登记 MC，不得因任一 MC 卸载丢失普通障碍。`SceneManager.removeGameWorld()` 必须先通过 loot authority barrier；成功后才停帧更新，再在 dispatcher/gameworld 存活时 `dispose()` 精确旧层和 MC/矩形强引用，最后才销毁 dispatcher 与 gameworld；本轮静态门 **35/35**，2026-07-25 最终 helper/marker 代码冻结后的 fresh CS6 回归为 **21/21、4/4 cases、0 failed、Compiler Errors 0/0、32K retry=0**；专项门见 [testing-guide.md](testing-guide.md) §2。
- **关卡事件音效**：`StageEvent` 消费 XML 解析后已归一化的 `Sound[]`，只逐项播放有效非空音效名；不得再保留永远不可达的字符串分支。本轮静态回归 **11/11**。

## 13. 装备生命周期系统
- **帧脚本**：`scripts/逻辑/装备函数/`（每个 `.as` 注册 `_root.装备生命周期函数.XXX初始化/周期`，物品 XML `<lifecycle>` 节点按装备绑定，战斗中驱动动画/特效/子弹/buff）
- **用途索引 + API 快查 + 新增 7 步流程**：`scripts/逻辑/装备函数/README.md`（就近 hub）
- **编译真源**：`scripts/asLoaderManifest/frame37.as`（f37_N chunk，**非**旧 `装备函数列表.as`，后者已退役删除）；三方一致性门 `tools/validate-equip-fn-coverage.js`
- **装载/销毁边界**：`attr_N` 的 init/cycle 可独立存在；init-only 不创建帧任务。主动整只重建/移除装备单位时先 `DressupInitializer.teardownLifeCycles(unit)`，再 `removeMovieClip()`，不能只依赖迟到的周期自清理
- **canonical / runtime 投影边界**：`DressupInitializer` 在 11 槽装载后由 `RuntimeEquipmentProjection` 冻结 exact refs 与 `level/tier/mods` 语义签名，全部 lifecycle 完成后提交 applied stamp，teardown 统一回收 alias。吉他喷火、死者之手这类复合武器只能用 owner/version 绑定的 `reserveEmptySlotAlias → commitSlotAlias` 借用 canonical 空槽；CharacterBuild 以 manager 规范化后的 canonical 状态判定 dirty，HP/MP、Buff 内容、姿态、弹药、战技和形态都不参与 dirty
- **视觉引用换分支**：单位整体替换 `man` 时，当前活动 `unit.man` 下的新 holder 应接管同基础引用/实例的规范注册；旧 `man` 即使仍有 parent 也不得继续占用可见武器的生命周期引用。同一活动 `man` 内真实并存 holder 仍使用 `#N` 隔离
- **非人形换装桥**：调用 `DressupInitializer` 的普通敌人模板若没有人形模板的 `装载主动战技/装载副武器控制槽/装载生命周期函数/完成生命周期函数装载`，会在基础装备与射击初始化之后提前中断，使白板枪能开火但 lifecycle 动画、特效与变速全不运行。应在明确采用换装核心的单位服务边界按缺失项挂接成熟函数，不要扩大修改全局敌人模板，也不要覆盖素材已有实现
- ⚠ 与 `org.flashNight.arki.item.equipment`（class 化装备**数值计算**系统）是两套平行系统，勿混

## 14. 套装效果系统（一期实现与实机复核中）
- **设计与验收真源**：[套装系统设计与剑圣一期验收](../docs/套装系统-设计与剑圣一期验收-2026-07-14.md)
- **运行边界**：每单位一个逻辑 `SetEffectController`；一期保留子装备自治 tick 和成员 `<lifecycle>` 完整配置，用 `setGate/effectId/componentId` 在通用 loader 解析前门控。中心 routine 保存必需组件 manifest、共享 context 和 placement 通道；placement 在引用重建后即时校正，预计算任务每帧各采样一次有效肢体的 target-local 基向量，胸甲/腿甲共享 `身体_引用`，手甲消费 `左下臂_引用`，组件 tick 逐帧消费缓存而不重复执行肢体坐标换算。五个 ref 由既有 loader 创建后登记到 effect record，preflight/commit/rollback 保证任一组件失败时整套不提交。头甲的低光夜视与常驻扫描/锁定相互独立。原体抗性表项是开启对应定向破击的负向暴露，不是普通 Buff；一期按 `baseIfMissing=10 + value=75` 聚合为 85，写入层不钳制
- **接线点**：`updateLifeCycles()` 清理后先 `prepare`，再装载单件生命周期，最后由 `_root.主角函数.完成生命周期函数装载()` 执行 `finalize`；一期以仅在五件齐全时激活的剑圣装甲重构作为纵向验收

## 15. 地图资源箱中央裁决与 Web-only 瞬态战利品容器

- **唯一产品路径**：六类地图箱由 `BoxInteractionArbiter` 做领域准入；所有合法正整数 `row/col` 只进入 `LootContainerService` 与 Web loot panel。生产 XML/runtime 不使用 rollout marker，Flash renderer、claim-only adapter、observer recovery 与 S0 平行编排均不属于当前路径。
- **中央裁决**：每个 world 只有一个箱体互动监听，一次输入按 `(dx²+dz², registrationOrder)` 选择至多一个箱。六 preset 白名单只防止投影召唤器等非箱元件被 `row/col` 劫持，不是地图或尺寸白名单；已识别箱注册失败必须整体 initialize 回滚，不能降级到逐 target legacy listener。
- **网格选择**：`LootContainerService.classifyMapChestShape()` 接受 `1×1`，并以 `col<=8 && row*col<=64` 作为 Web 能力上限。畸形或超界正网格 fail-closed：不 kill、不滚奖、不显示 Flash UI。只有精确 `0×0` 的 direct 箱继续地面掉落；负数、单边为零、混合或缺字段全部 fail-closed。攻击破碎保持地面掉落语义，不打开 Web。
- **破碎时间轴**：六类 canonical linkage 都必须有统一开启回调；所有可攻击且有“破碎”标签的箱必须在该标签帧调用统一破碎脚本。已存在 reservation/active/suspended authority 时，break guard 阻止重复发奖；没有 authority 的破碎与精确 `0×0` 直投也必须先通过 Web 物化器共用的完整掉落规则校验，坏配置只 trace 并停止。
- **AS2 权威**：`LOOT_COMMIT_PENDING` 先完整预检并一次物化到真实 `ArrayInventory`，再提交 own-kill/opening frame；`chestSessionId ↔ lootContainerId ↔ inventory` 一对一。只允许 loot→玩家，特殊资产先完整预检再事务提交。
- **幂等与未知结果**：claim/close 使用 operation id、authority revision、slot/close lease 与 exact binding。未知写不得重放，只能 query；成功和容量零写都需精确状态证明，错误名本身不是证明。
- **状态收束**：空箱为 `CONSUMED`；非空 X/Esc/backdrop 为 `LOOT_SUSPENDED`；只有二次确认的“放弃剩余”进入 `ABANDONED`；anchor/场景失效进入 `EXPIRED`。同场景同 anchor 可重开同一 inventory，v1 不跨游戏进程持久化瞬态 loot。
- **运输恢复**：Host 只管理 tracked panel、pause、bind/close 和重连；Web 只展示并发意图。初次、reopen、mount、navigation 或 socket 故障都必须保留同一 AS2 authority，不创建替代 renderer 或第二份奖励。scene teardown 在 authority 收束前 fail-closed。
- **同页整理**：普通满包可在同一 `loot` panel 内切换背包—战备箱 organizer，保持同一 `panelInstanceId`、binding 与 pause；返回前必须取得 fresh `LOOT_ACTIVE` snapshot。collection cap 不映射 organizer。
- **旧资产边界**：地图箱完成标准是旧 renderer/API 的地图生产引用不可达；仓库已迁到 Web-only，主 XFL 的 Include、递归放置及发布 SWF 的 ImportAssets/linkage/PlaceObject 闭包都不得再到达 `资源箱界面`。standalone legacy XFL 可作为封存资产暂留磁盘，物理删除不是本轮准入条件，但不得恢复 main 可达性。
- **S0 决策**：`ChestSessionService / ChestS0SocketBridge / DevLockboxS0` 及 Web bootstrap/adapter/wire 已退役。普通 Lockbox 小游戏可独立保留，但未来地图开锁必须另立协议和 ADR，不得恢复 dormant gate 或插入 loot 前置分流。
- **验证口径**：静态门全量扫描 stage、掉落规则和 XFL callback；AS2/Host/Web 自动门覆盖网格边界、arbiter、journal、stale/duplicate/unknown、disconnect、organizer 与 teardown。真人只做正常标题帧/NativeHud、代表性装备箱领空、生存箱满包整理、保险箱单击 suspend/reopen，以及装备/生存破碎；direct 有现成夹具时顺带目视，数值、存盘与重启回读尽量自动化并合并标准入口验证。
- **证据分层**：严格使用 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`。旧单-canary 的 candidate、promotion 和标准入口只作历史证据，不能覆盖当前全正网格 tree。
