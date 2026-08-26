# 单位数据镜像、CSharp 原生绘制与碰撞判定 · 长期迁移路线 ADR（2026-08-09）

**文档角色**：跨 AS2 / Guardian Launcher Host 的长期迁移路线与 ADR。本文只冻结目标量纲、AVM1 优先原则、权威边界、固定跨帧语义、阶段门、停止线与待验证项。现役拓扑、现役协议字段和现役测试入口仍由对应 canonical docs 维护；具体施工另起 `*-施工-*.md`。

**状态**：`PROPOSED / ROUTE_FROZEN / NOT_IMPLEMENTED / P0_EVIDENCE_PENDING`。

`ROUTE_FROZEN` 只表示本提案的目标、边界、已冻结输入与未决项已经固定供评审；后续变化必须进入决策日志。它不等于 `ROUTE_ACCEPTED`，也不授权 P0 施工或任何 gameplay authority 切换。

**最后核对代码基线**：commit `fff104b0f29d7c5def80f2ba0b5cc2682124f500`（2026-08-09）。

**证据口径**：

- `[产品输入已冻结]`：用户在当前规划讨论中已经明确的产品/架构输入，作为本提案的冻结前提；不代表 ADR 已正式接受或代码已经实现。
- `[提案内冻结]`：为使路线可施工而在本文中固定的技术选择；只有进入 `ROUTE_ACCEPTED / P0_AUTHORIZED` 后才生效。
- `[源码事实]`：在上述代码基线完成只读追踪的现状。
- `[待量测]`：方向成立，但量纲或收益必须由 P0 运行时数据裁决。
- `[建议门]`：本 ADR 给出的初始验收门；P0 可以用证据收紧或替换，但必须留下决策记录。

---

## 0. 一页结论

### 0.1 冻结的路线提案

当前路线提案冻结为：

```text
最小单位/子弹世界帧
    → CSharp World Overlay 垂直切除 Flash 头顶显示税
    → CSharp 异步 SenseFrame / BulletThreat
    → 普通 AABB 弹短期影子比对
    → 固定 n→n+1 的 CSharp AABB 命中权威
    → 雷达 / 边界异常保护
    → 射线与地图几何按 profile 另案
```

这不是“把 AS2 数据结构翻译成 CSharp”，而是以统一世界帧为跨栈数据面，**尽快删除 AVM1 中昂贵的显示树、排序、缓存重建、候选扫描和重复查询**。CSharp 在目标量纲下优先采用简单、可验证的暴力遍历。

### 0.2 目标量纲

| 项目 | 当前体验边界（产品输入，尚非 profiler 基线） | 目标场景（产品输入） |
|---|---:|---:|
| 同屏单位 | 约 10–20 | 30–50 |
| 活跃子弹 | 约 30–50 | 50–100 |
| 主要弹种 | 绝大部分 AABB | 绝大部分 AABB |
| 稀有复杂弹 | 多边形、射线占比低 | 先保留 AS2，按尖峰 profile 决定 |
| 游戏节奏 | 30 fps | 固定一帧约 33.3 ms |

50 单位 × 100 子弹只有 5,000 个粗配对/帧。该量纲对 CSharp 是低负载，对 AVM1 却足以迫使现役代码采用扫描线、近有序排序、属性缓存、循环展开、静态上下文与零临时分配。CSharp 首版因此不复刻这些结构。

### 0.3 成功判据

迁移成功不以“CSharp 已收到相同数据”或“CSharp 计算很快”为准，而以以下净收益为准：

```text
净收益
= 被删除的 AS2 显示/更新/排序/碰撞/查询成本
- WorldFrame 构建与编码
- AS2 回包解析与提交
- 仍保留的 shadow / fallback 成本
```

被迁域的 AS2 热函数、显示对象或缓存消费者没有真正停止，便不能宣称该阶段取得性能收益。

---

## 1. 与既有文档的关系

### 1.1 继承而不复制的现役不变量

[子弹命中-伤害双管线拆分 · 架构设计（2026-06-22）](子弹命中-伤害双管线拆分-架构设计-2026-06-22.md) 是阶段 4 的前置 ADR，也是以下已验证不变量的来源；当前实现事实仍以源码与 canonical docs 为准：

- 命中判定与伤害结算的 clean / dirty 边界；
- AABB 命中倍率恒为 `1`、polygon 使用真实 overlapRatio、ray 使用衰减的三态差异；
- 同一子弹的命中顺序、霰弹值影子窗口与 `additionalEffectDamage` 累积约束；
- 消弹 token、暂停、穿透、销毁优先级和同步 `settleHit` 语义；
- 复杂射线、多边形与现役 AS2 结算管线的行为红线。

本文不重复定义这些规则，也不因 CSharp 计算更“精确”而静默改变旧产品语义。

### 1.2 对既有“阶段 4”的提案内新增边界

本文对旧 ADR 中尚未闭合的 CSharp 碰撞阶段提出并在本提案内冻结：

1. `[产品输入已冻结]` 固定 `n` 帧几何检测、`n+1` 帧 AS2 提交可以成为新战斗时序契约。
2. `[产品输入已冻结]` 允许弹体在视觉上过冲一帧；命中特效使用冻结的 `n` 帧命中点。
3. `[产品输入已冻结]` Guardian Launcher / CSharp 是强制运行时，不支持脱离 Launcher 的独立 Flash 产品形态。
4. `[提案内冻结]` CSharp 只产出几何事实或候选；伤害、闪避、护盾、RNG、死亡和事件仍由 AS2 提交。
5. `[产品输入已冻结]` CSharp 在目标量纲下优先暴力计算；禁止为了复刻 AS2 优化结构而增加 AVM1 整理税。
6. `[提案内冻结]` Shadow 只是限时验证工具，不能成为正式环境的常驻双算。
7. `[提案内冻结]` late / duplicate / cross-epoch / wrong-generation 结果绝不补应用。

进入 `ROUTE_ACCEPTED / P0_AUTHORIZED` 后，CSharp 阶段 4 的跨进程路线以本文为该提案的唯一 source of truth；旧 ADR 只保留伤害/顺序不变量和本提案摘要。在接受之前，本文不覆盖现役实现或旧 ADR，只冻结评审对象。

### 1.3 与 UI 迁移文档的边界

本文规划的是跟随 Flash 世界坐标的 **CSharp native world overlay**，不是 Web Panel request/commit 生命周期。它可以复用 Launcher 的坐标映射、layered window 和 prepared DIB 模式，但不沿用 [AS2 UI → Web Panel 迁移护栏](../agentsDoc/as2-web-panel-migration.md) 的领域事务模板。

---

## 2. 已核对的现状地基

### 2.1 AVM1 是首要成本域

`agentsDoc/as2-performance.md` 的基准将局部算术置于低成本带，而成员访问、函数/方法调用、`new`、闭包、`arguments`、字符串方法和 `split` 依次落入中税至极重成本带（[成本阶梯](../agentsDoc/as2-performance.md#1-avm1-成本阶梯速查)）。现役 BQP 也明确以双指针、零临时分配、内联、变量提升、属性缓存和循环展开换取性能（[BulletQueueProcessor.as:L8-L22](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L8)；[L2561-L2572](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L2561)）。

因此，本路线的优化顺序必须是：

1. 先删除 AVM1 热工作；
2. 再减少跨层字段；
3. 最后才优化 CSharp 算法。

### 2.2 TargetCache 不是可直接搬走的权威单位池

`TargetCacheUpdater` 是按阵营维护的单位索引镜像；单位仍以 MovieClip 和业务对象图为权威。Updater 复用并交换数组、重建 `nameIndex`（[TargetCacheUpdater.as:L20-L40](../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Targetcache/TargetCacheUpdater.as#L20)；[L270-L388](../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Targetcache/TargetCacheUpdater.as#L270)），`SortedUnitCache` 再维护排序键与前缀最大值（[SortedUnitCache.as:L1233-L1278](../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Targetcache/SortedUnitCache.as#L1233)；引用不能跨帧持有）。

`updateFromUnitArea()` 并非稳态每次缓存读取都调用：只有 `tempVersion < currentVersion` 时才重新收集并用 `getRect` 建立边界；日常移动主要由 `Mover` 同步 collider，缓存更新再读取现成边界并重排（[TargetCacheUpdater.as:L249-L268](../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Targetcache/TargetCacheUpdater.as#L249)；[Mover.as:L134-L154](../scripts/类定义/org/flashNight/arki/spatial/move/Mover.as#L134)）。

由此得到两条约束：

- 不得为了导出 WorldFrame 调用 `acquireEnemyCache/acquireAllCache(..., 1)`，否则会继续支付排序、索引和缓存维护税。
- CSharp 镜像首期来自独立、扁平、生命周期维护的 roster；TargetCache 为尚未迁移的 AS2 同步消费者保留，按消费者减少后再裁决退役范围。

### 2.3 现有 F 快车道不能直接扩成计算数据面

现役 `FrameBroadcaster` 在帧末合并 camera / hit-number / fps / UI / input 段（[FrameBroadcaster.as:L88-L135](../scripts/类定义/org/flashNight/arki/render/FrameBroadcaster.as#L88)）。CSharp 端 `XmlSocketServer` 使用单 ReadLoop 同步分派，且现有处理路径与 connection transition 锁、C# hit reducer/overlay、V8 GameInput 等工作耦合（[XmlSocketServer.cs:L343-L400](../launcher/src/Bus/XmlSocketServer.cs#L343)；[L442-L550](../launcher/src/Bus/XmlSocketServer.cs#L442)）。

因此：

- P0-COMMON 必须设计独立、版本化的 `\0` 分隔 UTF-8 扁平文本 world 快车道；P0-COLLISION 在同一 envelope 上补齐 collision request/result 合同（下文统称 raw lane；不是二进制流）；具体 prefix 尚未冻结。
- ingress 在锁内只允许校验小头部并投递有界 mailbox，解析与计算移出读循环。
- overlay、AI 和 collision 可以共享一份不可变 WorldFrame，但不能共享一种 deadline/丢帧策略。
- 当前 ReadLoop 会在遇到 `\0` 前持续扩展 `MemoryStream`（[XmlSocketServer.cs:L343-L400](../launcher/src/Bus/XmlSocketServer.cs#L343)）；新 lane 在进入解析与 mailbox 前必须有字节级硬上限，不能把“本地连接”当作无界分配许可。

### 2.4 HitNumber 是纵切原型，不是可复制的常驻实体模板

截至 2026-08-25，伤害数字已完成独立迁移：`FrameTask → HitNumberRuntime → HitNumberOverlay` 全部为 C#，V8 `HitNumber` namespace 与 Flash MovieClip fallback 已删除。世界层只保留短自然寿命，有限世界上限按 Burst 原子选择；balanced/total/classic/detail 四种表现共用同一 reducer，精确历史另进固定 32,768 段环形账本并只在暂停态 Web 设置按需分页物化。UI 侧使用 generation 栅栏、latest-wins 单槽 mailbox、紧边界和持久 top-down PArgb DIB / memory DC，常态不再逐帧创建整视口 Bitmap、HBITMAP 或 DC。具体生产与验收合同见 [Launcher README](../launcher/README.md#打击伤害数字生产路径)和[专项 harness](../tools/hit-number-visual-harness/README.md)。

它仍只是瞬态事件纵切，不是人物文字的可复制模板。人物文字是持久实体状态，仍必须新增身份、spawn/despawn、full resync、迟到帧丢弃和实体级 latest-wins；不能把伤害段的 1.08 秒窗口、Burst 身份或允许丢旧视觉帧直接套到 roster。

World Overlay 首版继续复用 `PlayerInfoLayeredDibSurface` 的持久 surface 模式。伤害数字保持独立 reducer 和独立 surface；P1 不得重新引入 V8 状态机或第二套 damage-number reducer。是否把两个已单一权威的最终绘制面物理合层，仍由 P1 的 paint/ULW profile 单独裁决。

---

## 3. 架构原则

### 原则 1 · AVM1 税最小化

每增加一个帧级字段、dirty 检查、容器、排序或第二次遍历，都必须能指向一个将被删除的 AS2 热循环或显示成本。只因“CSharp 顺手可用”而扩充 WorldFrame，不构成收益理由。

### 原则 2 · CSharp 可以笨，但边界必须确定

首版允许 `O(B×N)` AABB 和 `O(A×N)` AI 摘要。CSharp 的简单实现必须保持固定迭代顺序、稳定 tie-break、版本化数值语义和有界内存；“暴力”不等于无序或无界。

### 原则 3 · 一份世界事实，多种消费时效

- collision：exact `frameSeq`，固定 `n+1` deadline，不允许 latest-wins。
- bullet threat：随 collision frame 产出，结果年龄上限为 1 帧，不进入四帧 AI advisory 节拍。
- AI：四帧节拍的 advisory `SenseFrame`，允许受控陈旧，不允许晚到覆盖玩家命令。
- overlay：latest-wins，可丢旧视觉帧，不影响游戏逻辑。
- telemetry/debug：可采样、可降级、不得反压 collision。

### 原则 4 · AS2 仍是业务提交权威

CSharp 返回 `HitIntent`、`SenseFrame` 或 `BoundsCorrectionIntent`；AS2 在显式 phase 中复核代际和业务状态后提交。CSharp 不直接写 HP、护盾、库存、掉落、仇恨、死亡或事件总线。

### 原则 5 · 正式态只保留一个计算权威

Shadow 可以短期开启；正式 steady-state 中，同一弹体/查询域不得同时由 AS2 和 CSharp 全量计算。fallback 是 deadline miss 时的冷路径或场景边界切换，不是每帧热备。

### 原则 6 · 本地共进程不等于无需时序身份

Launcher 是强制运行时，因此不需要按不可信公网服务器设计认证、分布式共识或持久重试；但 socket、线程、暂停、重连、换图和对象池复用仍会产生 stale result。batch key `{streamEpoch, sceneEpoch, frameSeq}` 与 entity key `{handle, generation}` 仍是硬约束。

---

## 4. 目标边界与非目标

### 4.1 本路线目标

- 同一份单位/子弹动态帧同时服务 world overlay、普通 AABB 碰撞、AI 粗查询、bullet threat、雷达与调试。
- 将人物姓名、称号及可选血条/盾条/韧性表现从 Flash 显示树垂直切到 CSharp。
- 将普通 AABB 弹的候选枚举和几何命中移到 CSharp，AS2 保留结算。
- 保持 AI 调用点同步，改为读取已完成的四帧 `SenseFrame`。
- 建立可量测、可熔断、可按弹种/消费者切换的分期入口。

### 4.2 明确非目标

- 不迁完整伤害、Buff、RNG、死亡、掉落与事件状态机。
- 不在首期迁完整 AI 行为树、寻路、LOS 或玩家命令。
- 不在首期迁 Flash `collisionLayer.hitTest`、区域 hitTest、拾取/交互事务。
- 不要求人物文字与 Flash 设备字体、GlowFilter、hardlight/screen 做像素等价。
- 不以独立 Flash 运行、物理双屏或混合 DPI 作为首期发布门；必须保留未来扩展空间。
- 不因少量射线/多边形尖峰污染普通 AABB v1 协议。

---

## 5. 权威矩阵

| 领域 | 现役/切换前权威 | 目标态权威 | CSharp 输出 | AS2 提交责任 |
|---|---|---|---|---|
| 实体出生/死亡/阵营/代际 | AS2 | AS2 | 镜像状态 | 分配 handle/generation、换图清空 |
| 单位/子弹动态事实 | AS2 | AS2 producer | WorldFrame 镜像 | 产生一次扁平帧 |
| 人物文字/头顶条绘制 | Flash | CSharp | native world overlay | 只发语义状态与锚点；停旧显示树 |
| 普通 AABB 几何命中 | AS2 | CSharp（白名单） | ordered HitIntent | `n+1` 复核并结算 |
| 动态消弹/反弹前置裁决 | AS2 BQP stage 1 | AS2（v1） | 无 | WorldFrame freeze 前处理；VANISH/REMOVE 不导出，BOUNCE 按现役语义跳过当帧单位碰撞 |
| 射线/多边形/特殊弹 | AS2 | AS2，按 profile 再议 | 可选 shadow | 保持旧顺序与特效 |
| 闪避/伤害/护盾/RNG | AS2 | AS2 | 无 | 完整业务权威 |
| hit/kill/death 等事件 | AS2 | AS2 | 无 | 保持事件顺序与副作用 |
| AI nearest/range/count | AS2 TargetCache | CSharp advisory | SenseFrame shortlist/摘要 | live 复核、评分、选靶、玩家命令优先 |
| bulletThreat | AS2 扫描尾部 | CSharp（remote-primary）+ AS2（legacy） | 每碰撞帧 ThreatFrame：count/minETA/direction | 下一帧合并/写入 AI 可读快照，最大年龄 1 帧；legacy 未迁前保留本地贡献 |
| 相机实际 transform | AS2 | AS2 | 可选统计建议 | snap/切镜/缩放仍由 AS2 |
| 雷达/屏外指示 | 无或局部 | CSharp | 视觉投影 | 不产生玩法副作用 |
| xmin/xmax/ymin/ymax 越界 | AS2/缺口 | CSharp 建议 + AS2 提交 | BoundsCorrectionIntent | 复核移动 revision/传送并走 Mover |
| 地图像素碰撞/导航 | AS2 | AS2，后续独立 ADR | 无 | 继续使用现役地图语义 |
| 治疗/拾取/库存事务 | AS2 | AS2 | 最多候选建议 | 即时重验并原子提交 |

---

## 6. 固定一帧碰撞时序

### 6.1 目标 phase

```text
frame n pre-simulation
    drain exact result(n-1) 或执行同一 frozen snapshot 的 fallback
    标记 n-1 committed

frame n simulation
    unit/task update
    bullet preCheck / AABB update / external-simple queue enqueue

frame n collision-submit
    执行动态消弹/反弹 prepass
    BOUNCE/VANISH/REMOVE 在 AS2 各自完成一次 movement/收尾
    只保留 NONE 子弹进入 WorldFrame
    单次扫描 unit roster + external-simple bullet queue
    构建 immutable WorldFrame(n)
    投递 CSharp collision worker
    migrated bullet 执行既有 movement / 非碰撞生命周期

CSharp worker
    解析 WorldFrame(n)
    暴力 AABB / 固定排序
    返回 HitIntentBatch(n, applyAt=n+1)

frame n+1 pre-simulation
    只消费 exact n，随后才允许单位 AI 与 bullet preCheck
```

`pre-simulation commit` 必须是显式 phase，不依赖 EventBus 当前倒序订阅的偶然顺序。

### 6.2 已冻结的跨帧语义

- `n` 帧几何为命中事实；`n+1` 使用 AS2 当时活状态进行伤害、护盾、闪避和事件结算。
- `n+1` 必须重验 scene/handle/generation、alive/HP、`防止无限飞`、自碰撞和 batch disposition；不因目标在 `n` 后正常移动而推翻已经成立的几何命中。
- 允许弹体多飞一帧；命中特效使用 `n` 帧冻结命中点。
- 伤害数字跟随命中点还是 `n+1` 目标位置，由表现阶段单独冻结；不得影响命中权威。
- 结果晚于 `n+1 pre-simulation` 不得补伤害。
- 一个完整 batch key `{streamEpoch, sceneEpoch, frameSeq}` 只能由 remote 或 fallback 之一提交；v1 不允许按子弹或 contact 混合两种来源。

### 6.3 生命周期裁决

1. `streamEpoch` 或 `sceneEpoch` 不符：整批丢弃，不进入 disposition ledger。
2. batch 不完整、metadata/profile revision 不符、输入计数/`inputIntegrityToken` 不符或出现未知 handle/profile：整批判无效，对同一 frozen snapshot 走 fallback；禁止猜默认 profile 或部分采用。
3. target generation 不符：对应候选丢弃，绝不重定向到复用 handle 的新实体；bullet 必须命中本 batch 的 detached pending settlement record，记录缺失视为 batch fault。
4. 同 generation 但目标在 `n+1` 已死亡：跳过该候选，继续该子弹的后续有序候选。
5. 子弹生成后射手死亡：子弹仍有效，使用当前 `settlementRevision` 对应的 context。初始 context 在生成期冻结；若子弹随后发生合法 BOUNCE，必须在旧 pending batch 已 disposition 后，原子替换 owner handle/generation、shooter reference、阵营与其他归属字段，并推进 `settlementRevision`，下一次 WorldFrame/`inputIntegrityToken` 使用新 revision。
6. **每一个进入 remote-primary WorldFrame 的 bullet** 都必须在 AS2 建立 detached pending settlement record，直到整个 batch 已作出 remote/fallback disposition；不能等 CSharp 报告命中后才补建。该记录持有 bullet/owner generation、结算上下文与生命周期意图，未释放前对应 handle/generation 不得复用。
7. bullet MovieClip 在 `n` 后因地图/范围/表现销毁，不会取消其 pending record；若 remote/fallback 在该 frozen snapshot 得出命中，仍在 `n+1` 依记录结算。
8. AS2 已 fallback：之后到达的同 batch key CSharp 结果无条件丢弃。

第 6 条的粒度固定为：每个 bullet generation 一份 settlement context，每个 pending batch ledger 只引用它。batch disposition 后释放该 batch 引用；只有 bullet 已进入本地终止态且 pending 引用归零，才释放 context 并允许复用 handle/generation。在“`n+1` 先提交、再运行本帧 bullet preCheck/导出”的时序下，同一 bullet 正常最多只有一个未决 batch；不得据此实现无界 seq-range 或长期累计 30 份 batch record。

### 6.4 batch 完整性与单一 disposition

每个输入 batch 至少携带：

```text
batch key = streamEpoch + sceneEpoch + frameSeq
batchId（与 batch key 一一对应的 opaque correlation id）
expectedUnitCount / expectedBulletCount
inputIntegrityToken（inputHash 或 manifestHash）
metaRevision / fullSyncRevision
collisionComparatorRevision
collisionNumericRevision
batchComplete
```

CSharp 结果必须回显 batch key、`batchId`、`inputIntegrityToken`、metadata/full-sync revision、comparator/numeric revision、处理计数与 `status=complete`。`inputIntegrityToken` 至少覆盖有序 unit/bullet roster、每个记录的 kind/handle/generation、bullet settlement revision、counts、cancel disposition 与相关 revision。`batchId` 不能替代三元 batch key 授权提交；两者映射冲突、scene 内 `frameSeq` 回退/重复/静默 wrap，或 `applyAtFrameSeq != frameSeq + 1` 都是整批 fault。v1 只接受**完整批次 remote commit**：partial、truncated、overloaded、fault、revision mismatch、count/token mismatch 都使整批 fallback；不做 per-bullet remote/local 混合，也不在部分 contact 已提交后重试整批。零命中结果只有在完整性字段证明所有 expected bullets 已处理时才是合法空结果。

### 6.5 结果顺序

结果粒度固定为“子弹 × 有序候选列表”，禁止按目标聚合。P0-COLLISION 必须从现役 BQP/SortedUnitCache 的真实选中顺序冻结 `collisionComparatorRevision`，包括边界相等、同 left 值、同进入时间和稳定 tie-break；**不得把 CSharp roster 遍历顺序当作碰撞语义**。结果至少绑定：

```text
queue/source ordinal
    → bullet ordinal
    → frozen legacy comparator
    → candidate/contact ordinal
```

第一批只迁不穿透的普通弹，仍必须返回有序候选而不是仅返回首个目标：`n+1` 提交时前一候选可能已经死亡或失效，AS2 需要继续扫描后续候选。

### 6.6 数值等价合同

v1 使用独立 `collisionNumericRevision`，并将它与 `collisionComparatorRevision` 一起写入输入和结果。数值等价以现役 BQP 普通 AABB 热路径为 oracle，不以抽象几何库或“CSharp 更精确”为 oracle：

- AABB/Z 分离必须逐比较复刻现役 `<`、`<=`、`>=` 组合，不引入 epsilon、`float` 降精度或隐式量化。普通 BQP 热路径在左右边缘相等时存在方向性：`unitRight == bulletLeft` 被内联 `bulletLeft >= unitRight` 排除；`unitLeft == bulletRight` 仍进入候选窗口，且不会再被 X 条件排除，Y/Z 合法时可命中。该不对称是 v1 parity 合同，不能笼统改写成“所有边缘接触均不命中”；是否修正另立 gameplay/balance 裁决（[BulletQueueProcessor.as:L2992-L3008](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L2992)；[L3062-L3108](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L3062)）。
- AABB `dmgMult` 恒为 `1`。
- AABB 命中点必须复刻 AVM1 位运算：先以 `Number` 求两侧重叠边界之和，再按 ECMAScript `ToInt32` 语义转换该和，最后执行有符号算术 `>> 1`；不得用 CSharp `double / 2` 代替（[BulletQueueProcessor.as:L3154-L3159](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L3154)）。
- 输入使用 AS2 `Number` / CSharp `double` 可往返的有限值；`NaN`、`±Infinity`、缺失值、超长/不可解析 token 或 codec 声明范围外的值使整批无效，禁止默认为零。`-0` 在线路上规范化为 `0`。
- P0-COLLISION golden 至少覆盖小数与负坐标、奇偶和、四向边界相等、Z 临界值、`ToInt32` wrap 边界，以及 contact point 的逐值 parity。

---

## 7. 数据面概念合同

> 本节冻结职责与最小语义，不冻结 wire prefix、分隔符、具体类型宽度或类名。对应 P0-COMMON / P0-COLLISION readiness 量测后另立协议施工文档。

### 7.1 身份头

所有计算帧和结果至少携带：

```text
protocolVersion
streamEpoch
sceneEpoch
frameSeq
sourceFrameSeq / applyAtFrameSeq
metaRevision / fullSyncRevision
```

collision input/result 还必须携带 `collisionComparatorRevision / collisionNumericRevision`；Sense/Threat/overlay 只携其消费者实际需要的 plan/presentation revision，不为统一头部强塞碰撞字段。

实体键使用 `{handle, generation}`；若单位与子弹最终采用分池编号，则 wire key 必须提升为 `{kind, handle, generation}`，不能依赖记录上下文猜 kind。`_name` 只可作诊断字段。`DepthManager.entityID` 会回收，不能单独承担跨帧身份。handle 只在 spawn 分配，generation 在每次池复用或新逻辑生命期推进；同一 stream 内不得静默 wrap。spawn metadata 必须早于实体首次进入 WorldFrame，释放与复用还必须满足 §6.3 的 pending record barrier。

### 7.2 EntityMetaDelta

自然生命周期事件，只在 spawn/change/despawn 发生：

- handle / generation / kind / faction / capability flags；
- name / title / level / style token；
- head-anchor profile：局部锚点、方向抵消规则与基础显示缩放；其 revision 独立于 collider；
- collider profile / local bounds / geometry revision；
- simple bullet 的静态形状和允许的运动类别。

每次变化推进单调 `metaRevision`；场景启动与重连发送带 `fullSyncRevision` 的完整 catalog。CSharp 必须先顺序应用到 WorldFrame 声明的 revision，再返回 `laneReady(protocolVersion, streamEpoch, sceneEpoch, fullSyncRevision, metaRevision, capabilities)`。未知 handle/profile、缺失 revision 或 WorldFrame 超前于 metadata 都使该 batch 无效并触发 fallback，不能猜默认值。

同一连接内检测到 revision gap、未知 profile/handle、worker state 丢失或冲突重复 delta 时，不能永久停在 fallback 等待下一次重连。CSharp 必须返回 `metaResyncRequired(streamEpoch, sceneEpoch, appliedMetaRevision, observedMetaRevision, reason)` 并立即撤销 `laneReady`；AS2 对当前 pending batch 使用同一 frozen snapshot fallback，停止新的 remote commit，推进 `fullSyncRevision` 并发送带 expected meta count、`catalogIntegrityToken` 与 `catalogSnapshotMetaRevision` watermark 的完整 catalog。full catalog 构建期间产生的新 delta 进入有界队列，在 catalog 原子替换后从 watermark+1 连续应用；队列溢出或再次出现 gap 就重启 full sync。CSharp 只有在完整 catalog 原子替换且追平声明的 ready revision 后，才可返回精确匹配的 `laneReady`。恢复前所有 gameplay result 都拒绝；完全相同的旧 revision 可幂等丢弃，同 revision 内容冲突、跳号或 partial full sync 一律 fault。

正常流中 CSharp 以 `metaAckRevision` 回报已原子应用的 watermark；AS2 只需在有界窗口内保留未确认 delta，并始终保有重新生成完整 catalog 的能力。ACK 停滞或 delta window 溢出时不得无界留存或猜测丢包，直接撤销 readiness 并合并为一次 full resync。

`catalogIntegrityToken` 属于 P0-COMMON，只覆盖 catalog/fullSync revision、expected meta count、有序记录内容与完整结束标记；§6.4 的 `inputIntegrityToken` 属于 P0-COLLISION，覆盖 collision batch、bullet settlement/cancel/comparator/numeric 等动态输入。二者不能共用含糊的 `integrityToken` 名称，也不能让 catalog 恢复等待碰撞 token 算法冻结。

`head-anchor profile revision` 与 `collider geometry revision` 不得共用；动态层也必须拆开 live visual transform 与 cached AABB/collision-transform revision。前者服务显示，跟随单位当前视觉位置、朝向与缩放；后者服务 gameplay parity，表示现役 `aabbCollider` 最近一次实际刷新后的冻结几何。静止单位只推进动画、但未触发现役碰撞盒刷新时，head anchor 可以继续随视觉状态更新，cached AABB/collision-transform revision 不得因此推进。高频 collision-transform 属于 WorldFrame，不推进低频 `metaRevision`。

这不是通用逐字段 dirty engine；只使用现有生命周期或明确 setter 能自然给出的变化。

### 7.3 WorldFrame

v1 优先采用每帧自包含的全量动态数值帧：

- camera transform 与 viewport revision；
- unit handle/gen、`displayX=_x`、`displayY=_y`、`groundY=Z轴坐标`、朝向/显示缩放、head-anchor profile/visual-transform revision、gameplay eligibility flags、faction/capability revision，以及 cached dynamic AABB 或 collider profile + collision-transform revision；
- bullet handle/gen、owner handle/gen、`settlementRevision`、`displayX=_x`、`displayY=_y`、`groundY=Z轴坐标`、zRange、gameplay flags、source ordinal；
- 仅 collision/AI/overlay 至少一个消费者需要的动态字段。

上述字段名是语义名，wire grammar 仍由对应 readiness 冻结。三分量不能折叠：`displayX/displayY` 服务单位本体与头顶锚点投影，`groundY` 服务地面平面、纵深、AI 与 Z 粗判；浮空高度由 `groundY - displayY` 派生（[玩家模板迁移.as:L833-L848](../scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as#L833)）。只发送 `_x/_y` 会丢失碰撞 Z，只发送 `_x/Z轴坐标` 会使浮空单位的头顶锚点钉在地面。P0-COMMON 必须冻结“直接发送当帧 world-space head anchor”或“profile + 完整 live visual transform”之一；只有 root position 与 profile、却缺方向/缩放/旋转语义，不构成完整 anchor 合同。

位置、碰撞、相机，以及 `alive/collidable/faction/generation/capability` 等 gameplay eligibility 必须每帧或以同帧可见 revision 更新；collision/AI 不得从四帧表现槽读取资格。HP ratio、盾/韧性等纯表现状态可按四帧节拍；姓名/称号只走 MetaDelta。需要当前 HP 的 AI predicate 由 AS2 live 复核，不能把表现采样当权威。

### 7.4 HitIntentBatch

CSharp 返回几何事实，不返回最终伤害：

- source/apply frame；
- batchId、status、expected/processed counts、inputIntegrityToken；
- meta/fullSync/comparator/numeric revision；
- bullet/target handle + generation，以及 bullet `settlementRevision`；
- source/contact ordinal；
- contact point；
- AABB `dmgMult=1` 或明确 geometry kind；
- 可选 TOI/法线只在有已冻结消费者时加入。

### 7.5 SenseFrame

按四帧节拍返回固定词汇表：

- nearest hostile/ally shortlist；
- bounded range count / left-right density；
- camera/radar 可复用的只读统计。

每个 query result 还必须声明 `complete`、`provenTopK` 或 `advisoryOnly`。只有完整有序集，或能证明省略项不可能超过第 K 名的 `provenTopK`，才允许替代 legacy query；否则 AS2 保留本地查询或 fallback。

不支持 AS2 任意 `Function predicate` 跨进程执行；这类 query 长期留 AS2。计划在 spawn/行为参数变化时用稳定 `planId/revision` 更新，不能每次查询建立 RPC 对象。

### 7.6 ThreatFrame

随每个 collision WorldFrame 计算并在下一帧提交，按单位返回 `count/minETA/direction`。它与四帧 `SenseFrame` 分 lane/节拍，采用结果的年龄不得超过 1 帧；结果缺失时保留现役本地值或走该 collision batch 的 fallback，不用更老的 advisory 覆盖。

### 7.7 BoundsCorrectionIntent

只用于安全保护：

- sceneEpoch、entity handle/gen；
- observed frame / movement revision；
- 违反的 xmin/xmax/ymin/ymax；
- 建议恢复位置或 last-known-legal token。

AS2 必须复核实体代际、传送/击飞状态和 movement revision，并通过统一 Mover/位置 setter 应用，禁止 CSharp 直接写 `_x/_y`。

### 7.8 Raw lane envelope 与硬上限

raw lane 是 `\0` 分隔 UTF-8 扁平文本，不是无限长二进制流。每个 `protocolVersion` 必须冻结 `maxMessageBytes`、`maxAssemblyAge`、`maxReadIdle`、`maxUnits`、`maxBullets`、`maxContactsPerBullet`、`maxTotalContacts`、`maxMetaEntries`、`maxFieldCount` 与单字段/数字 token 最大长度；full catalog 可以使用独立但仍有限的 cap。

上限必须在四处执行：AS2 producer 发送前、CSharp 遇到 NUL 前的字节累积阶段、parser 写复用数组前、AS2 result parser 提交前。expected counts 超 cap 本身就是非法 header。未达到 byte cap 但迟迟没有 NUL 的半包，也必须在 `maxAssemblyAge` 或 `maxReadIdle` 到期后清空累积、关闭当前 connection generation 并撤销 readiness；pending collision 仍只在其 `n+1` deadline 走一次 frozen fallback。任何 oversize、assembly timeout、truncated、字段数不符或 contact explosion 只允许关闭当前 connection generation/整批 fault、fallback 并计入 circuit breaker；禁止截断、partial commit、无界扩容或对 gameplay latest-wins。P0-COMMON 冻结全局 byte/assembly/field envelope 与 unit/meta/catalog caps；P0-COLLISION 冻结 bullet request、result/contact caps。

---

## 8. AVM1 友好的 producer 设计

### 8.1 单次扫描

remote-primary 稳态结构目标：

```text
一次 unit roster 线性扫描
+ 一次 external-simple bullet queue 线性扫描
+ 一次 raw frame 编码/发送
+ n+1 一次结果游标解析/提交
```

overlay、AI、collision 不得分别触发第二次 gameworld/TargetCache/BulletQueue 扫描。

### 8.2 禁止项

- 不为导出调用 `TargetCacheManager.acquire*Cache(..., 1)`。
- 不为 CSharp 调用 `sortByLeftBoundary()`。
- 不在热路径 `for-in gameworld`、visitor callback、JSON stringify 或 `LiteJSON`。
- 不逐实体 `new Object/new Array`，不物化 rich DTO。
- 不在 AS2 计算 CSharp 可暴力完成的阵营候选、距离、排序、空间格或 per-entity/加密 hash。只允许两个按域冻结的完整性例外：P0-COMMON 的 `catalogIntegrityToken` 在 catalog 编码中顺带产生；P0-COLLISION 的 `inputIntegrityToken` 在 WorldFrame/collision batch 编码中顺带产生。二者都不得为 token 二次遍历或引入加密热税。
- 不把 full snapshot 先写一份 SoA，再二次遍历序列化，除非 P0-COMMON 证明其净收益。
- 不复制 HitNumber 的 viewport 剔除；同一 WorldFrame 由 CSharp 完成 overlay 投影与裁剪。

### 8.3 roster 与 external-simple queue

- unit roster 由 spawn/death/faction change 生命周期维护，热帧只读复用引用与缓存数值身份。
- bullet capability 冻结三种互斥运行模式：
  - `legacy-only`：只进入 legacy BQP，不进入外部玩法权威；
  - `shadow`：仍由 legacy BQP 唯一结算，只额外导出只读 frozen input/result trace 做比较，不建立 external gameplay authority；
  - `remote-primary`：生成/分类时只进入 external-simple queue，不进入 legacy BQP active queue。
- P0-COLLISION 只验证分类与碰撞扩展，不改变现役入队；P3 使用 `shadow`；只有 P4 gate 通过后才把白名单弹切为 `remote-primary`。
- legacy BQP 继续处理 ray/polygon/cancel/UnitBullet 等例外，保持其现有预取键、排序、扫描和清理优化不受破坏。
- `remote-primary` 只移出“子弹 × 单位”几何检测，不得绕过场上动态出现的全局消弹区。v1 从 BQP 抽取或复用一段共享 AS2 cancel prepass，在 WorldFrame freeze 前处理 external-simple queue（现役前置顺序见 [BulletQueueProcessor.as:L2643-L2672](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L2643)；[L2867-L2984](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L2867)）：
  - `VANISH/REMOVE`：保留现役 `霰弹值=1`、`STATE_HIT_MAP`、killFlags、恰好一次 movement、地图命中 FX/`击中时触发函数` 与 REMOVE/VANISH 统一终止优先级，不进入本帧 collision batch（[BulletQueueProcessor.as:L2976-L2984](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L2976)；[L3329-L3370](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as#L3329)）；
  - `BOUNCE`：执行现役 `handleBounce`，在旧 pending batch 已 disposition 后原子刷新 owner/faction/shooter settlement context 与 `settlementRevision`，再执行恰好一次 movement，并按现役 `continue` 语义跳过当帧单位碰撞（[BulletCancelQueueProcessor.as:L405-L432](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletCancelQueueProcessor.as#L405)）；
  - `NONE`：才允许冻结并导出。
- cancel disposition 必须进入 frozen input/`inputIntegrityToken` 和 shadow golden；不能在 `n+1` live world 补判。只有 profile 证明该条件 prepass 本身成为瓶颈，才把 cancel-zone geometry 纳入 P6。
- cancel-zone catalog/SoA 每帧只允许 prepare 一次并同时服务 external 与 legacy 队列。该 prepass 在 `hasCZ=false` 时必须保持 O(1) 快退；有区域时可直接对目标量纲采用条件式 `O(B×C)` 暴力遍历，不能为了复用现役双扫描线而让 external queue 常态排序。区域优先级、重叠区 first-writer/token 语义仍须复刻现役。
- `shadow` 弹仍由现役 BQP stage 1 唯一产生 cancel/bounce 副作用；影子链只读取其 token/disposition 作为 oracle，禁止第二次调用 `handleBounce` 或重复写终止意图。独立 external cancel prepass 只在 remote-primary 切流时成为权威。
- 只有 `NONE` 的 remote-primary bullet 在导出后执行既有一次 movement 和非碰撞 shouldDestroy；BOUNCE/VANISH/REMOVE 已在 prepass 分支各执行一次，禁止漏执行或双执行。每个导出 bullet 的命中结算使用 §6.3 的 detached pending record。

### 8.4 编码策略待量测

AS2 微基准表明裸字符串 `+` 可能比 `Array.join()` 便宜，但完整 WorldFrame 还涉及数字转字符串、数组写入、字符串扩容和 GC。P0-COMMON 必须在真实 50/100 载荷上比较：

1. 分段直接拼接；
2. 复用 flat parts 数组 + 单次 join；
3. 字段裁剪与自然 MetaDelta 后的 full dynamic frame。

未取得真实 build/encode/send p95/p99 前，不冻结二进制、压缩、量化、base64 或通用 delta。

### 8.5 collider profile 机会

普通 bullet 已采用“首次缓存 local bounds，之后按位置偏移”的路径，透明弹为固定 25×25（[AABBCollider.as:L281-L343](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/AABBCollider.as#L281)）。单位 `updateFromUnitArea()` 会调用 `unit.area.getRect(_root.gameworld)`（[AABBCollider.as:L433-L446](../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/AABBCollider.as#L433)），但现役 TargetCache 并非稳态每帧重算该 `getRect`。

现役单位 AABB 是一次 `unit.area.getRect(_root.gameworld)` 的缓存快照，不是当前动画帧几何的持续函数。Mover 的多个实际移动路径会刷新碰撞盒（[Mover.as:L134-L154](../scripts/类定义/org/flashNight/arki/spatial/move/Mover.as#L134)；[L177-L204](../scripts/类定义/org/flashNight/arki/spatial/move/Mover.as#L177)），状态/tick 路径与 TargetCache 重新收集也存在显式刷新；但“静止且只播放动画”不保证刷新。

因此 P0-COLLISION/P3 的 parity 真源必须是当帧已经缓存的 `aabbCollider.left/right/top/bottom`，读取时不得再次调用 `getRect()`。静止动画、静止转向或姿态细节变化若没有触发现役 `updateFromUnitArea()`，CSharp 也必须继续使用旧碰撞盒；不得依据 live visual transform 主动提高精度。

`collider profile + collision-transform snapshot` 只是减少四边传输的候选优化：

- P0-COLLISION baseline：逐帧导出 cached AABB 四边，先证明 collision parity；
- profile 模式：只有在不增加 AS2 `getRect`、姿态判断或第二次扫描的前提下，证明能重建同一 cached AABB，才可进入 remote-primary；
- profile/revision 只在现役碰撞盒刷新点推进，不按动画播放帧加密；
- 真正修复“静止动画使用陈旧 AABB”属于独立 gameplay/balance 裁决，不得夹带进本迁移。

不能为了少数动态碰撞器污染全部单位/子弹记录，也不能为了省四个数值字段改变现役碰撞语义。

---

## 9. CSharp 计算与调度设计

### 9.1 v1 简单实现

- raw ingress 先在字节层执行 prefix/消息长度硬限，再解码小 header；只有 counts/caps 合法才进入 bounded mailbox，完整解析仍在 worker。
- worker 先应用并确认 metadata/fullSync revision，未 `laneReady` 或 revision 不闭合时拒绝 gameplay batch。
- parser 写入双缓冲或复用的 struct arrays。
- 普通 AABB 直接 `B×N`，按 faction/flags 过滤。
- AI 摘要按 `A×N` 暴力扫描，先复刻旧 metric/tie，再单独评估行为升级。
- handle→index 表、结果数组和 overlay surface 必须有界复用。

### 9.2 首期禁止提前引入

- spatial hash / BVH / quadtree / sweep-line；
- SIMD / unsafe / 多 worker job system；
- 通用 ECS、predicate DSL、query planner；
- delta/bitpack/varint/compression；
- shared memory、第二 socket 或 native C++ 依赖。

只有 `parse + O(B×N + A×N)` 在目标负载下成为 deadline 主因，才先优化 parser/复用；仍不满足，再评估最简单的 uniform grid。

### 9.3 mailbox 与优先级

| lane | mailbox/顺序 | 过载策略 |
|---|---|---|
| metadata/fullSync control | 单调 revision；一个 retained full catalog + 有界 delta/ACK watermark | gap/worker reset 立即撤销 laneReady 并请求 full resync；禁止静默丢 delta |
| collision input | 单 worker，最多 active + pending | 拒绝并报告 miss；禁止覆盖 expected seq |
| collision result | exact epoch/seq，小型 expected/future 槽 | 旧、重复、late 立即丢弃 |
| ThreatFrame | 与 collision result 同 batch/seq，最大年龄 1 | 缺失时不得沿用更老 threat advisory |
| AI SenseFrame | latest completed，带 age/plan revision | 可覆盖旧 advisory；不得拖慢 collision |
| overlay | 单 pending UI post，latest-wins | 丢旧视觉帧，保留最新 full state |
| telemetry/debug | 有界采样 | 首先降级或关闭 |

### 9.4 World Overlay

逻辑绘制面分 nameplate、bar、damage-number、debug/radar 图层。damage-number 已由独立 C# `HitNumberRuntime` 单一持有段寿命、Burst 聚合/裁剪、balanced/total/classic/detail 投影与 reset generation；AS2 只在 `H1` 时发送结算后段事件，V8 只保留 GameInput。固定容量精确账本同属该 runtime，但不参与世界 paint。WorldFrame 不接管或复制这份状态，“damage-number 图层”仍只表示未来可能复用同一最终合成面。

物理上 World Overlay 优先使用固定 viewport surface、持久 DIB/DC 和每帧最多一次 layered-window commit。现役 HitNumber 已采用紧边界持久 DIB/DC，但与 World Overlay 保持独立 surface；是否物理合层由 P1 GDI+/ULW profile 决定。任何合层只能组合最终 paint，不得产生第二套 damage-number reducer、把设置面板的 Host-local 分页账本带回战斗 overlay，或把 WorldFrame 变成伤害历史 authority。

#### 9.4.1 Bar presentation reducer

P1 cutover 后，CSharp 是 residual HP、渐隐、受击显现、轻微抖动与颜色表现的唯一 reducer；AS2 只提供四帧语义快照和带 frame/epoch 的表现事件，不继续计算或传输最终 `_width/_alpha/timeline frame`。现役语义基线包括 HP 变化时重置 actual/residual 起点、残余血条二次缓出、长时间无变化后的渐隐，以及受击时重新显现/播放、颜色反馈和位置抖动（[InformationComponentUpdater.as:L19-L35](../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Updater/InformationComponentUpdater.as#L19)；[L60-L129](../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Updater/InformationComponentUpdater.as#L60)；[BloodBarEffectHandler.as:L27-L55](../scripts/类定义/org/flashNight/arki/component/Effect/BloodBarEffectHandler.as#L27)）。

P1 shadow 可同时计算用于限时对账，但只能有一个可见 authority；切流后必须停止 Flash updater/时间线，且禁止从隐藏 MovieClip 反读 width/alpha。若完整复刻成本不成立，只能通过产品裁决降低表现合同，不能永久保留 AS2 width/alpha 状态机。

Bar reducer 只按已接受的 game/presentation frame 推进，不使用独立 wall-clock timer；Flash pause 不得让 residual/fade 私自前进。逻辑年龄由单调 source/presentation `frameSeq` 或显式四帧采样序号计算，不按 UI paint/post 次数 `+1`。latest-wins 合并视觉帧时，reducer 必须按 seq delta 确定性追进，或由最新 full presentation snapshot 直接重建；gap 超过冻结上限时 resync/snap，禁止逐个补播无界历史事件。`sceneEpoch` 或 `streamEpoch` 变化立即废弃旧 reducer 状态与旧事件；恢复后的第一份完整 presentation snapshot 按 P1 冻结的初始化策略建立 actual/residual/fade 状态，旧 epoch 事件一律丢弃。重连后选择“完整恢复残血/渐隐状态”或“无动画 snap 到当前玩法事实”由 P1 cutover 前裁决，但不得猜测或沿用旧 stream 状态。

首期产品边界：

- 语义/可读性等价，不要求 Flash 字体与 blend mode 像素等价；
- 普通单位允许绘制在 Flash 世界之上；特殊遮挡/特殊血条单位走 allowlist；
- 单屏为正式首期范围，保留 PMv2/混合 DPI 升级接口；
- 位置每帧，表现状态四帧，文本事件化；
- 切流后必须停止实例化或运行对应 Flash TextField、GlowFilter、时间线/updater，不能只隐藏。

---

## 10. 弹种能力分层

### 10.1 首批 authority allowlist

首批只允许同时满足以下条件的普通弹：

- axis-aligned AABB；
- 普通直线或已证明的简单确定性运动；
- 非 ray、非 polygon chain、非 UnitBullet；
- 非 pierce / multi-hit；
- 无弹体自定义 cancel/bounce/反射 callback；场上动态消弹区仍服从 §8.3 的 AS2 前置权威；
- 无特殊 hitBehavior、同步 callback、处决或强状态 on-hit；
- 地图 pixel hitTest 不决定同一帧命中优先级，或已具备 detached settlement 裁决。

第一批建议从 AI→AI 普通单目标弹开始，再扩伙伴→敌、玩家→敌；敌→玩家另做公平性感知验收。

### 10.2 暂缓而非永久禁止

- 透明近战：产品已接受一帧延迟，但其现役“一帧检测即销毁”需要 detached record 后再迁。
- 穿透：需要整段 ordered batch、hitCount 和霰弹值窗口。
- polygon chain：需要顶点/transform 合同和 overlapRatio 等价。
- ray：瞬时/持久/chain/fork 模式复杂，先记录 p95/p99/max 尖峰。
- cancel/bounce：与碰撞前置否决、运动和销毁优先级强耦合。
- UnitBullet：同时具有单位/子弹双重身份及额外 Z 语义。

### 10.3 不允许的“顺手修正”

- AABB 不得因为 CSharp 能算真实 overlapRatio 就改变 `dmgMult=1`。
- AI 最近目标不得在迁移等价阶段从 legacy X/left-edge 语义静默改成中心点 2D 最近。
- CSharp `double`/排序更稳定不构成改变 AS2 命中顺序的授权。

---

## 11. AI、TargetCache 与同步 facade

### 11.1 数据可旧，不代表调用点异步

现有 AI 调用在同一 AS2 调用栈中立即使用查询结果。迁移后保留同步 facade：每个四帧 AI tick 只读取已经完成的 `SenseFrame`，不在调用点发 RPC 或等待结果。

### 11.2 v1 语义

- CSharp 返回候选/计数/摘要，不直接写最终 target 或 aggro。
- AS2 使用当前 hp、阵营、代际、距离、玩家命令和强制仇恨做 live 复核。
- 玩家点名、受击仇恨和手动命令永远高于晚到 SenseFrame。
- v1 复刻 legacy distance/tie 语义；fresh 2D 行为作为后续独立平衡升级。
- 结果错过当前四帧 action slot 时不得异步等待；按 age cap 使用 last-valid 或保守 no-op。
- 若要删除某个 legacy query，CSharp 结果必须提供该 query 的完整有序候选，或带可验证上界的 `provenTopK`；普通 advisory shortlist 经 AS2 live 过滤后可能候选耗尽，不能据此宣称 legacy-equivalent，必须保留本地 fallback。
- 读取任意 AS2 `Function predicate`、技能瞬时范围或业务对象状态的查询不进入 v1 词汇表，继续本地同步执行。

### 11.3 TargetCache 退役顺序

1. 先建立按 request type / faction / callsite 的剩余消费者清单与 profiler 基线。
2. P4 后 remote-primary queue 不再发起 TargetCache 查询；但只要同阵营 legacy ray/polygon/UnitBullet/特殊队列非空，其 interval=1 消费仍保留，不能按阶段名整段删除。
3. bulletThreat 先只对 remote-primary 弹迁入 `ThreatFrame`；legacy 弹继续使用 AS2 威胁扫描，除非另有经过等价验证的合流设计。
4. nearest/range/count 按 query gate 逐步切 SenseFrame；任意 predicate 和未证明 complete/provenTopK 的调用继续本地。
5. 相机统计、治疗候选等低频消费者按收益决定；治疗提交仍在 AS2。
6. 只有代表负载下实际的 cache refresh/sort cadence 随消费者减少而下降，才登记局部收益；不得从“普通弹已切权威”推导 BQP interval=1 已消失。
7. 仅当所有同步消费者清单为空且 profile 证明成立，才拆出轻量 UnitRegistry 并退役 SortedUnitCache 热维护。

“迁了一个 AI 查询”不等于 TargetCache 已可删除；“TargetCache 尚未全删”也不否定先移除每帧碰撞消费者的局部收益。

---

## 12. 雷达、边界保护与未来地图几何

### 12.1 雷达/调试是低风险消费者

外部 AABB debug overlay 是 P0-COMMON/P1 的首个验证面，可直接暴露坐标、ID、generation、frame age 和 collider profile 错位。雷达、屏外箭头在 WorldFrame 稳定后加入，不得反向要求 AS2 生成专用第二份实体列表。

### 12.2 边界异常保护

WorldFrame 已含位置时，CSharp 检测 xmin/xmax/ymin/ymax 越界的边际成本接近零，可以返回 `BoundsCorrectionIntent`。但四次数值比较本身在 AS2 很便宜，不能把它包装成跨进程迁移的主要性能收益。

目标是修复少量单位穿出地图边缘后的安全恢复：

- CSharp 可维护 last-known-legal 建议；
- AS2 复核 scene/generation/movement revision/传送状态；
- 应用走 Mover 或统一位置 setter；
- intent 可重复到达但提交必须幂等；
- 任何迟到修正不得把已合法移动的新实体拉回旧位置。

### 12.3 地图碰撞另立 ADR

完整 `collisionLayer.hitTest`、导航与静态地图几何不属于单位 AABB 迁移的自然延伸。路线冻结为：

```text
Scene bounds v1
    → radar/static contour v2
    → profile 证明收益后，再立 map collision/navigation ADR
```

---

## 13. Shadow、fallback、暂停与重连

### 13.1 Shadow 只能限时

- 碰撞按稳定 bullet handle 抽取完整生命周期，避免只抽离散帧破坏轨迹对比。
- AI 按 query/plan 抽样。
- overlay 用固定关卡截图/语义 oracle；不在正式态保留隐藏 Flash renderer。
- 常态记录 count/hash/first-diff；出现 mismatch 后才开启短窗口详细 pair/contact trace。
- 权威切换后 production 默认关闭 AS2 全量 shadow。

### 13.2 deadline fallback

`n+1 pre-simulation` 是唯一 deadline，AS2 不等待、不晚应用。默认路线是：

1. 保留 `WorldFrame(n)` 的 frozen payload/等价扁平数据一帧；
2. exact、完整且 revision/integrity 闭合的 CSharp result 按时到达则整批 remote commit；
3. 缺失或无效时，只对该 frozen snapshot 执行一次 AS2 fallback kernel；
4. late remote result 丢弃；
5. 连续 miss/parse fault/queue fault 触发 circuit breaker，在安全 phase 暂停并解析唯一 pending batch，随后进入 `remote-suspended`：停止新的 remote-primary gameplay batch、继续拒绝 late result，也不把存活 external queue 热转进 BQP。

fallback kernel 必须使用与 remote 相同的 frozen input、`collisionComparatorRevision + collisionNumericRevision`、方向性边界、`ToInt32 >> 1` contact-point 算法、资格字段、候选合法性规则和 detached settlement ledger；禁止在 `n+1` live world 上重新检测。碰撞就绪门/P3 必须以 golden 校验候选集合、首命中/顺序/命中点、死亡跳过与副作用输入，并量测 50/100 最坏 AS2 fallback 尖峰。

“从 payload 再解析并暴力 fallback”与“同时保留预分配数值帧”的 AVM1 成本由 P0-COLLISION 裁决；禁止为了 fallback 每帧预先跑 legacy BQP。v1 也禁止把当前场景仍存活的 external-simple bullets 热转移进 BQP；如未来需要无重载原地接管，必须另立带 queue/ledger handoff 的协议与验收。

`remote-suspended` 之后的玩家可见恢复方式尚未冻结，候选包括“暂停并提示重试/退出”“受控使用 fallback kernel 维持到场景边界”“回 checkpoint/重载场景”。自动重载可能损失当前进度，不得在施工中擅自选用；P4 前必须取得产品裁决并为所选旅程建立真机验收。

### 13.3 暂停、换图与重连

- pause barrier 进入前必须先处理唯一 pending batch：按时完整 remote result 则提交，否则用同一 frozen snapshot fallback；已发生的几何命中不得因暂停静默消失。只有明确的 scene epoch reset 才能取消整个旧 epoch，恢复后禁止补旧伤害。
- scene reset 先推进 `sceneEpoch`，清 input/result/ledger/overlay，再允许新场景 spawn。
- socket reconnect 推进 `streamEpoch`；CSharp 清 worker/cache，AS2 完成 metadata full resync 并收到匹配 revision 的 `laneReady` 后才恢复 remote-primary。
- 同一 socket generation 内的 metadata gap/worker reset 不等待重连：立即撤销 `laneReady`，按 §7.2 走 `metaResyncRequired → full catalog → matching laneReady`；恢复前所有 gameplay batch 只可 fallback/local-only。
- Launcher 整体崩溃无需支持孤儿 Flash 继续战斗；CSharp 子 worker 故障仍必须 fail-closed，不得污染当前 AS2 状态。

---

## 14. 分阶段路线与 Gate

### P0 · 公共数据面与分域就绪

`ROUTE_ACCEPTED / P0_AUTHORIZED` 后，P0 分为两个可独立验收的 readiness profile。P1/P2 只依赖 `P0-COMMON`；碰撞 comparator、cancel、settlement 与 fallback 证据不得阻塞最高 ROI 的 overlay。`P0-COLLISION` 可以与 P1/P2 并行或稍后完成，但必须在 P3 开始前通过。

#### P0-COMMON · WorldFrame / Overlay / Sense 公共地基

**施工范围**：

- 原型化 entity namespace 与 unit handle/generation 生命周期，不改变现役 gameplay authority；
- 建立最小 unit roster、metadata ACK/fullSync/resync/laneReady 与有界 raw lane；
- 比较 unit-first WorldFrame 编码策略，冻结 `_x/_y/Z轴坐标`、head anchor/live visual transform 与 cached AABB debug baseline；
- CSharp 只解析、计数和画 debug AABB，不切任何 gameplay authority；
- 记录 entity count、payload、AS2 build/encode/send、CSharp queue/parse、overlay paint 与 frame age。

**`P0_COMMON_MEASURED` 退出门**：

- 公共字段每项都有消费者/删除收益；unit count、payload bytes 与分项 p50/p95/p99/max 可测；
- 跨场景/错代际/重复帧、重连旧 stream 全部拒绝；revision gap 能在同一连接完成 `laneNotReady → full resync → matching laneReady`；
- oversize、assembly age/read idle 超时、缺 NUL、超长 token 与伪造 counts 在分配/提交前 fail-closed；
- WorldFrame 构建没有调用 TargetCache 排序或为 CSharp 物化每实体 DTO；
- 公共数据面 p95/p99 未侵蚀计划删除的 overlay/query 热路径收益；否则裁字段或停止扩张。

#### P0-COLLISION · P3 前的碰撞就绪扩展

**施工范围**：

- 原型化 bullet 生成期 finalization、capability/三模式分类、settlement record/revision 与复用屏障；
- 明确 `n` 帧 cancel/precheck 后 export 与 `n+1` 帧 AI/bullet preCheck 前 commit 两个显式 phase；
- 建立 AS2 cancel prepass 原型，但不改变现役入队/结算权威；
- 冻结 collision batch completeness、comparator/numeric revision、result caps、ordered candidate 与逐碰撞帧 ThreatFrame 合同；
- 以 cached AABB 四边建立 collision parity baseline，原型化同 frozen snapshot 的 fallback kernel 并记录最坏尖峰。

**`P0_COLLISION_READY` 退出门**：

- incomplete batch、unknown profile/settlement revision、空结果伪完整、partial result/contact explosion 均整批拒绝；
- comparator/numeric golden 覆盖方向性相等边界、负数/小数、Z 临界、`ToInt32 >> 1` 与 contact point parity；
- cached AABB 与静止动画/静止转向的陈旧性 golden 保持现役；
- 动态消弹区出现/消失、VANISH/REMOVE/BOUNCE、反弹归属 revision、一次 movement 与统一收尾有小型 fixture/golden oracle corpus；P0-COLLISION 不启用代表关卡的正式运行时 shadow；
- fallback 与 remote 使用同一 frozen input/comparator/numeric/ledger，50/100 最坏 AVM1 尖峰已量测；
- 按时 remote、deadline fallback、重复/迟到 remote 与临界并发到达的组合，只允许 ledger 从 `PENDING` 原子进入一个终态；remote+fallback 双提交、重复结算与 late apply 均为 0；
- collision request/result slack 可测；证据不成立时不进入 P3/P4，但不回滚已通过的 P1/P2。

### P1 · World Overlay 垂直切除

**施工范围**：姓名、称号、基础血/盾/韧性条；位置每帧、表现事实四帧、文本/受击事件化；CSharp 单独推进 bar presentation reducer；保留特殊单位 allowlist。现役 C# damage-number reducer 保持独立且不改语义，物理 surface 是否合并只做消融。

**开工前引用闭包门**：必须基于冻结 commit 生成 AS2 + XFL 的完整 touchpoint inventory，至少覆盖 attach/unload 与兼容别名、`variableName` 文本写点、`InformationComponentUpdater` / `BloodBarEffectHandler`、方向/缩放与锚点、天气透明度、登场/死亡/注销、特殊 bitmap capture，以及非显示系统对信息 MovieClip 存在性的假设（例如 [CharacterBuildService.as:L2828-L2849](../scripts/类定义/org/flashNight/arki/item/CharacterBuildService.as#L2828)）。inventory 必须区分活跃语义、可删除死引用和特殊 allowlist；具体文件清单下沉 P1 施工文档，AS2 编译不报错不能证明动态 MovieClip 引用已经闭合。

**退出门**：

- Flash 对应 TextField/filter/updater 调用确实归零或仅剩明确例外；
- residual/fade/受击显现/颜色/抖动语义通过冻结 corpus；cutover 后 AS2 不再推进或发送最终 width/alpha/timeline frame；
- 30–50 单位下 paint+commit、GDI/USER handles、UI mailbox 有界；
- 单屏、缩放、方向、天气、登场、死亡与场景重置无残影；
- C# HitNumber 的 reducer 权威没有出现第二份；独立/合并 surface 的结论有 paint/ULW profile 支撑；
- touchpoint inventory 每项均有改写、删除或 allowlist disposition；除冻结例外外，不再存在对退役信息 MovieClip 的活跃运行期依赖；
- mailbox 合帧/连续丢视觉帧、长 pause 后恢复、reconnect/scene reset/旧 epoch 受击事件 golden 通过，bar reducer 不按 paint 次数或 wall clock 漂移；
- 失败可以关闭 native renderer，但不得留下双状态机常驻。

### P2 · SenseFrame 只读查询

**施工范围**：四帧 AI 候选/count、ThreatAssessor 粗统计与相机只读统计；AS2 保留最终决策。逐碰撞帧 bulletThreat 不属于本阶段依赖：其 `ThreatFrame` 合同在 P0-COLLISION 冻结、P3 随碰撞影子对账、P4 才随 remote-primary 普通弹切流。

**退出门**：

- 同冻结帧 legacy metric 的候选集合/顺序在白名单 query 上无差异；
- 替代 legacy query 的结果具备 complete/provenTopK 证明；advisory-only 或任意 predicate 继续本地；
- SenseFrame 采用年龄不越过四帧 action 合同；
- 迟到结果覆盖玩家命令、错代际目标、跨场景目标均为 0；
- AS2 被替换 query 的调用次数/耗时在 profiler 中真实下降；TargetCache cadence 只记录观察值，不作为 P2 强制退出门。

### P3 · 普通 AABB 碰撞影子

**施工范围**：白名单弹种保持 `shadow` 模式与 legacy BQP 唯一结算；按完整生命周期抽样，CSharp 返回 ordered candidates 与只读 ThreatFrame 供比较，不进入 external gameplay authority。

**退出门**：

- 在冻结的代表关卡语料、弹种 allowlist、30–50/50–100 负载矩阵和规定持续时间内，FP/FN/重复/首命中或顺序错/跨 epoch 全部为 0；
- AABB multiplier 保持 1，contact point 与 `collisionNumericRevision` parity 为 0 差异；
- ThreatFrame 的 count/minETA/direction 与现役 white-list bulletThreat oracle 等价，采用年龄不超过 1 帧；
- 高速过冲、双弹同目标、单弹双目标、方向性相等边界/tie、目标死亡/复活、动态消弹区出现/消失、暂停/换图、结果缺失/重复、fallback 最坏尖峰均有 golden；
- shadow 关闭后 WorldFrame 的净成本仍满足收益门。

### P4 · 普通 AABB remote-primary

**施工范围**：只对白名单弹种切 CSharp 几何权威；AS2 `n+1` 结算。

**退出门**：

- 每个 accepted frame 恰由 remote/fallback 之一提交；late apply/duplicate/cross-generation 为 0；
- 每个 remote result 都通过 batch completeness、`inputIntegrityToken`、meta/fullSync/comparator/numeric revision 闭合；partial commit 为 0；
- migrated bullet 不再进入 legacy sort/cache/collision 热路；
- 动态消弹/反弹 prepass 没有被 remote-primary 绕过；revision gap/worker reset 恢复前 remote commit 为 0；
- remote-primary 与 legacy bulletThreat 贡献按 §11.3 分流且无漏记/双记；
- 目标 30–50 单位、50–100 子弹下 AS2 frame p95/p99 净改善；
- fallback/熔断注入不造成双伤、漏序或旧场景写入；熔断后不发生 external queue → BQP 的场景内热转移；
- 产品批准的 `remote-suspended` 玩家可见恢复旅程完成真机验收，不以“下一场景再正常”代替当前故障场景闭环；
- 玩家/敌人方向分别完成打击感与公平性验收。

### P5 · 雷达、边界保护与 TargetCache 收敛

**施工范围**：雷达/屏外指示、BoundsCorrectionIntent、剩余高频 query 迁移；按消费者清单评估 UnitRegistry/SortedUnitCache 收敛。

**退出门**：

- bounds correction 不覆盖传送或更新后的合法位置；
- 雷达不新增 AS2 第二次实体扫描；
- TargetCache 是否退役由剩余消费者和 profile 证明，不按路线愿景强删。

### P6 · 稀有复杂域（条件阶段）

只有 ray/polygon/map 的 p95/p99/max 或维护成本成为明确瓶颈，才分别立项：

- ray math / persistent state；
- polygon vertex/transform contract；
- cancel/bounce/pierce ordered windows；
- static scene geometry / map collision / navigation。

这些不是 P4 上线的尾项，不得阻塞普通 AABB 收益落地。

---

## 15. 量测矩阵与停止线

### 15.1 负载矩阵

至少覆盖：

| 场景 | 单位 | 子弹 | 用途 |
|---|---:|---:|---|
| 当前低负载 | 10 | 30 | 回归基线 |
| 当前高负载 | 20 | 50 | 现状边界 |
| 目标常态 | 30 | 50 | 首个产品门 |
| 目标大场面 | 50 | 100 | 核心路线门 |
| 诊断压力 | 80+ | 200+ | 只定位曲线，不作为产品承诺 |

复杂 ray/polygon 场景单列，禁止用低占比平均数掩盖尖峰。

### 15.2 必测指标

**AS2**：

- frame total p50/p95/p99/max；
- unit/bullet scan、WorldFrame build/encode/send；
- BQP sort/cache/scan/narrow/settle；
- TargetCache refresh/sort/nameIndex；
- InformationComponentUpdater/display/filter A/B；
- result parse/commit/fallback；
- 临时分配与可见 GC 尖峰。

**CSharp**：

- ingress queue age/depth/overwrite/reject；
- parse、AABB、AI、overlay paint、ULW commit；
- result send 与距 `n+1` commit 的 slack；
- GDI/USER handles、managed allocations/GC；
- deadline miss、circuit breaker、metadata gap/full-resync/laneReady 恢复次数；

**Wire**：

- entity/bullet count、bytes/frame；
- full/meta/presentation 各段占比；
- oversize/count/token/contact-cap 拒绝计数；
- 现有输入、SFX、UI/control 消息 p95/p99 是否回退。

### 15.3 零容忍正确性门

- cross-scene apply = 0；
- wrong-generation apply = 0；
- duplicate settlement = 0；
- late apply = 0；
- fallback + remote 双提交 = 0；
- 玩家命令被迟到 AI 覆盖 = 0；
- AABB damage multiplier 漂移 = 0；
- comparator/numeric revision 不符却被采用 = 0；
- 动态消弹/反弹前置裁决被绕过 = 0。

### 15.4 性能停止线

- WorldFrame 构建/编码 p95 抵消被删除 AS2 热路径：保留 overlay/debug 收益，停止 gameplay authority 扩张。
- CSharp 结果无法稳定在 `n+1` deadline 前到达：停止扩张 collision authority；已切 remote-primary 的当前场景只能走获批的 circuit recovery，不能暗示无成本热切 BQP。AI/overlay 可继续使用镜像。
- World Overlay 需要常驻 Flash 状态机才能保持语义：缩小迁移范围或重做 presentation reducer，不接受永久呈现双状态源。该停止线不禁止碰撞 fallback kernel 作为有界冷路径。
- 为少数特殊弹增加的字段/分支显著污染普通帧：特殊弹留 legacy lane。
- TargetCache 仍有高频本地消费者：不强行退役，只删除已迁消费者。

---

## 16. 跨阶段未决项登记

| 项目 | 当前状态 | 最晚裁决阶段 | 所需证据/裁决 |
|---|---|---|---|
| entity namespace/generation/reuse barrier | 语义冻结，未实现 | P0-COMMON（unit）/P0-COLLISION（bullet） | spawn/despawn/复活/换图/池复用、pending record 引用归零 golden |
| batch triple/batchId/disposition ledger | 语义冻结，字段编码未定 | P0-COLLISION 退出 | stream+scene+frame 单调性、batchId 一一映射、counts/integrity、完整空结果、单一 disposition 注入 |
| metadata ACK/fullSync/resync/laneReady | 恢复语义冻结，未实现 | P0-COMMON 退出 | `catalogIntegrityToken`、gap/worker reset、unknown profile、同连接 full resync、重连与恢复前零 remote commit |
| raw lane grammar 与硬上限 | 扁平 UTF-8/NUL 语义冻结，prefix/数值未定 | P0-COMMON；bullet/result/contact cap 到 P0-COLLISION | 与 F/K/JSON 无歧义；bytes/assembly age/read idle/count/token/contact explosion 分配前拒绝；解析成本 |
| WorldFrame 编码与动态字段 | 三分量/资格/cached AABB 语义冻结，具体 shape 未定 | unit 到 P0-COMMON；bullet 到 P0-COLLISION | 每字段消费者与删除收益；50/100 build/GC/payload p95/p99 |
| head anchor/live visual transform | 必须与 collider revision 分离 | P0-COMMON 退出 | direct world anchor vs profile+完整 transform、浮空/方向/缩放/天气 corpus |
| collider parity/profile 覆盖率 | cached AABB 为 parity baseline；profile 优化未证明 | P0-COLLISION 退出 | 移动/状态/重收集刷新、静止动画/转向陈旧性、四边直传 vs profile 税与 payload |
| dynamic cancel prepass | v1 AS2 前置权威冻结，尚未抽取 | P0-COLLISION 退出 | 区域动态出现/消失、VANISH/REMOVE/BOUNCE、归属 revision、一次 movement/收尾、pause/export 与 integrity golden |
| bullet finalization/settlement record 挂接 | 语义冻结，具体函数未定 | P0-COLLISION 退出 | 生成期 capability/handle/owner context、bounce revision、终止后 pending record、复用屏障 |
| pre-simulation/export phase 载体 | 时序冻结，具体接点未定 | P0-COLLISION 退出 | `n` cancel/precheck 后 export；`n+1` AI/bullet preCheck 前 commit；不依赖 EventBus 偶然顺序 |
| collision comparator/numeric revision | 现役 BQP 为 oracle，revision/codec 未定 | P0-COLLISION 退出 | 方向性相等边界、tie、finite double round-trip、ToInt32/shift/contact point corpus |
| fallback kernel/载体 | 未冻结 | P0-COLLISION 退出 | frozen snapshot、comparator+numeric、ledger 与 50/100 最坏 AVM1 尖峰；payload reparse vs 预分配数值帧 |
| circuit-break threshold | 未冻结 | P4 前 | queue age/deadline miss/[1389ms 未归因离群](protocol-latency-baseline.md#L111)的风险注入；阈值不能由 tiny echo 外推 |
| bar presentation reducer | CSharp 单一权威方向冻结；精确容差/重连初始化未定 | P1 cutover 前 | residual/fade/hit/color/shake、game frame 时钟、pause/reconnect/reset/旧 epoch；必要时产品降级合同 |
| damage-number physical composition | C# reducer 与独立持久 surface 已现役；是否与 World Overlay 合层未冻结 | P1 退出 | production paint/ULW profile；独立与合并 surface 消融；Host-local 分页账本与单一 reducer 不变 |
| P1 touchpoint inventory completeness | 已知类别已登记，未穷举 | P1 开工前 | 直接属性、variableName、attach/unload、方向、天气、命中、死亡、bitmap capture 全量清单 |
| P1 touchpoint disposition closure | 未施工 | P1 退出 | 每项标记改写/删除/allowlist；运行期直接引用与 Flash smoke 闭合 |
| World Overlay renderer | 持久 DIB/有界 post 方向已选，细节未定 | P1 pilot 内、P1 退出前 | 字体、paint/ULW、单屏/DPI、handle 稳定性 |
| AI legacy metric/completeness | 需要逐调用点冻结 | P2 前 | left-edge/X/tie、complete/provenTopK、filter、age cap corpus |
| circuit-break 玩家可见恢复 | `PRODUCT_DECISION_PENDING` | P4 前 | 暂停提示/持续 fallback/checkpoint 重载等方案的进度、提示、失败与真机验收 |
| damage number 锚点 | 未冻结 | P4 前 | frozen contact point 与 commit-time target position 产品验收 |

任何未决项都不得通过“代码里先选一个”绕过 ADR 记录。

---

## 17. 文档与施工触发器

本文建立路线，不建立现役协议。首次 P0-COMMON 或 P0-COLLISION 代码切片若发生以下任一变化，必须同轮同步 canonical docs：

- 新增 raw prefix / schema / Task / worker：更新 `agentsDoc/architecture.md` 与 `launcher/README.md`。
- 新增测试入口、golden、延迟注入或性能门：更新 `agentsDoc/testing-guide.md`。
- World Overlay 从规划变为现役：在架构文档登记 native world overlay，不把它写成 Web Panel。
- AS2 producer/phase 入口变化：更新相关 AS2 架构说明；实际编译仍遵守 Flash CS6 fresh trace/Output Panel 证据边界。
- TargetCache/BQP 消费者或 authority 变化：同步本文阶段状态与既有子弹 ADR 的关联说明。
- 地图静态几何或导航进入范围：另立 ADR，不在本文静默扩张。

路线状态按 readiness 依赖推进，而不是强制串行阻塞：

```text
PROPOSED / ROUTE_FROZEN / NOT_IMPLEMENTED / P0_EVIDENCE_PENDING
    → ROUTE_ACCEPTED / P0_AUTHORIZED
        → P0_COMMON_MEASURED
            → P1_OVERLAY_PILOT
            → P2_SENSE_PILOT
        → P0_COLLISION_READY（同时依赖 P0_COMMON_MEASURED）
            → P3_COLLISION_SHADOW
                → P4_AABB_REMOTE_PRIMARY
```

P0-COLLISION 可以与 P1/P2 并行取证，也可以在其后启动；它不能阻塞已满足 P0-COMMON 的视觉/只读查询收益，但 P3/P4 不得绕过 P0-COLLISION。P1 与 P2 之间也不互相构成发布前置，分别按各自 gate 推进。

任何阶段的绿色 unit/harness 只证明对应范围；不得从 shadow parity 推导 gameplay authority，也不得从 candidate build 推导部署或产品验收。

---

## 18. 决策日志

| 日期 | 决策 | 状态 |
|---|---|---|
| 2026-08-09 | 目标为 30–50 单位、50–100 子弹的大混战 | 产品输入已冻结，量纲待 profiler 基线 |
| 2026-08-09 | Launcher/CSharp 是强制运行时，不保留独立 Flash 产品形态 | 产品输入已冻结 |
| 2026-08-09 | AVM1 税最小化高于 CSharp 算法复杂度优化 | 产品/架构输入已冻结 |
| 2026-08-09 | 普通 AABB 碰撞允许固定一帧延迟和视觉过冲；采用结果的 exact deadline 为 `n+1 pre-simulation` | 产品输入已冻结 |
| 2026-08-09 | 最吃判定精度的近战子弹也可接受固定一帧延迟与视觉过冲；透明近战迁移资格仍由 detached record/碰撞就绪/P3 证据决定 | 产品延迟语义已冻结；迁移资格待证据 |
| 2026-08-09 | 不要求旧 RNG/逐帧 replay 完全一致 | 产品输入已冻结 |
| 2026-08-09 | 伤害/闪避/护盾/RNG/死亡与事件仍由 AS2 结算 | 提案内冻结，待路线接受生效 |
| 2026-08-09 | AI 保持同步 facade，四帧读取异步 SenseFrame | 产品输入已冻结 |
| 2026-08-09 | remote-primary bulletThreat 独立按碰撞帧产出 ThreatFrame、最大年龄 1 帧；legacy 贡献在迁移前留 AS2 | 提案内冻结，待路线接受生效 |
| 2026-08-09 | AI v1 保持旧行为，2D/fresh 行为升级另案 | 产品输入已冻结 |
| 2026-08-09 | 人物文字以语义/可读性等价为首期目标 | 产品输入已冻结 |
| 2026-08-09 | P1 头顶条切流后由 CSharp presentation reducer 单独持有；不永久保留 AS2 width/alpha 状态机 | 提案内冻结，待路线接受生效 |
| 2026-08-09 | P1 保留当时现役 V8 damage-number reducer；是否合并物理 surface 由 profile 决定 | 历史决策；reducer 部分已被 2026-08-25 独立迁移取代 |
| 2026-08-25 | damage-number 已迁为 C# 单一 reducer + 独立持久紧边界 surface；V8/Flash fallback 退役，P1 只保留物理合层消融权 | 当前现役；合层仍待 P1 量测 |
| 2026-08-09 | 射线/多边形稀有弹先留 AS2，按尖峰 profile 再迁 | 产品范围输入已冻结 |
| 2026-08-09 | remote-primary 普通弹仍先经过 AS2 动态消弹/反弹 prepass | 提案内冻结（v1），待路线接受生效 |
| 2026-08-09 | collider parity 首先直传现役 cached AABB；profile 不得按动画帧提高精度 | 提案内冻结（v1 baseline），待路线接受生效 |
| 2026-08-09 | 地图碰撞延后到雷达之后；先做 scene bounds 安全保护 | 产品范围输入已冻结 |
| 2026-08-09 | 首期正式范围按单屏设计，保留混合 DPI 升级接口 | 产品输入已冻结 |
| 2026-08-09 | codec、stable handle 编码与首批弹种名单由证据阶段裁决 | 路线接受后待量测 |
| 2026-08-09 | circuit trip threshold | P4 前由真实 payload/slack/fault 注入裁决；不是 `n+1` gameplay deadline |
| 2026-08-09 | circuit breaker 后的玩家可见恢复方式 | 待产品裁决；不得默认自动重载 |

---

## 19. 关联文档

- [项目技术架构总览](../agentsDoc/architecture.md)
- [AS2 性能特性与优化指引](../agentsDoc/as2-performance.md)
- [AS2 反幻觉约束](../agentsDoc/as2-anti-hallucination.md)
- [Launcher source of truth](../launcher/README.md)
- [验证矩阵](../agentsDoc/testing-guide.md)
- [文档治理规则](../agentsDoc/documentation-governance.md)
- [AS2 UI → Web Panel 迁移护栏](../agentsDoc/as2-web-panel-migration.md)
- [子弹命中-伤害双管线拆分 · 架构设计（2026-06-22）](子弹命中-伤害双管线拆分-架构设计-2026-06-22.md)
- [子弹命中-伤害双管线拆分 · 施工（2026-06-23）](子弹命中-伤害双管线拆分-施工-2026-06-23.md)
