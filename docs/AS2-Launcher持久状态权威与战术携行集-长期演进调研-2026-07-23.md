# AS2 → Launcher 持久状态权威与战术携行集：长期演进调研

**文档角色**：长期架构调研储备 / 候选路线图；不是已批准 ADR，不是当前协议 source of truth。

**最后核对代码基线**：commit `466b899b515078169f342f7e0541be04e0f6e81d`（2026-07-23）。

**讨论输入**：物资箱三层权威施工经验、当前存档/背包/装备/弹药实现、肉鸽热切换目标，以及经代码复核后内化的异构审阅结论。

**启用条件**：任何实施必须先把对应阶段收敛成正式 ADR，并同步更新 `agentsDoc/architecture.md`、`agentsDoc/as2-web-panel-migration.md`、`launcher/README.md`、`agentsDoc/testing-guide.md` 等实际 canonical doc；本文不能单独授权协议或存档 schema 变化。

---

## 0. 执行摘要

本轮调研形成的候选长期方向是：

> 在 Launcher 中建立统一的持久玩家状态核心；AS2 保留实时游戏模拟和明确租约内的活体执行权威；Web 只提交命令并消费投影。

关键修正是不能把“权威迁到 Launcher”理解为“每次射击、换弹或装备对象字段变化都跨进程提交”。当前主角 MovieClip 直接持有装备栏中的同一个 `BaseItem`，帧逻辑会原地修改 `shot`、`reloadCount` 等字段。因此长期模型必须同时区分：

- **持久权威**：角色档案、钱包、物品归属、库存、Run、交易结果与结算；候选归 Launcher。
- **活体执行权威**：演员、战斗、当前弹匣、动作、技能帧逻辑及明确租约内的活动装备；保留 AS2。
- **投影**：AS2/Web 为兼容或展示持有的 revisioned snapshot；投影不是可写真相。
- **执行租约**：Launcher 把一个很小的战斗工作集排他交给 AS2，场景检查点或退出时收回。

由此得到的优先切口不是把整个 50 格背包交给 AS2，而是新增受限的 **CombatLoadout / 战术携行集**：活动装备、武器运行态、8～12 类战斗补给、快捷物品和战斗技能。完整背包、仓库、战备箱原则上不进入 AS2。

当前推荐的推进顺序是：先收口写入口与角色清单，再用绿色肉鸽 Run 验证 Launcher 持久态 + AS2 执行租约，最后迁移主线所有权聚合；不要在当前物资箱之后继续复制“AS2 经济权威 + Host 转发恢复 + Web 对账”的特性专用分布式事务。

---

## 1. 问题与触发信号

### 1.1 物资箱不是普通 UI 迁移

当前地图物资箱同时跨越：

- AS2 奖励物化、`ArrayInventory`、journal、revision、slot lease 与终态；
- C# panel binding、open/close/pause、socket generation、超时与故障恢复；
- Web freshness、unknown-write reconcile、projection proof、页面重载与交互生命周期；
- XMLSocket 断线、WebView 文档销毁、场景 teardown 和持久存档。

在已勘察的功能切片中，物资箱相关改动约 1.98 万行，生产实现与测试/harness 大致各占一半。用户侧开发体验是高强度模型运行超过四天仍不断发现新竞态和边界缺陷；该信号应解释为架构成本，而不是单次实现失误。

问题的本质是：经济真相、面板生命周期和持久化分别处于三个可独立失败的环境，功能代码被迫重建一套特性专用的分布式事务与恢复协议。

### 1.2 肉鸽目标需要真正的角色上下文

计划中的肉鸽玩法要求：

- 不退出 Launcher；
- 不关闭或重新启动 Flash；
- 从主线角色进入一个指定等级、指定装备、背包/仓库为空的新角色；
- Run 期间主线资产不被污染；
- Run 可拥有独立进度、掉落和结算；
- 退出后恢复原主线角色；
- 将来更换主角玩法技术时不必重新绑定主线存档实现。

仅切换 `savePath`、复制存档槽或设置“本会话禁存档”无法完整满足这些要求。它们可以做技术探针，但没有解决活动 Run 持久化、崩溃恢复、幂等结算和 `_root.*` 缓存重建。

---

## 2. 已验证的当前事实

### 2.1 Launcher 目前只是启动时快照裁决者

Protocol 2 已让 Launcher 负责启动时 SOL / shadow JSON 的选择、修复、备份和外部编辑。但是运行期仍由 AS2：

- 从 `_root.*` 组装 `mydata`；
- 写入 SOL；
- 再把 shadow 推送给 Launcher；
- 在读取时把角色、金钱、技能、背包、装备、仓库、战备箱等重新写回 `_root`。

因此当前准确表述是：

> Launcher 已有启动快照选择权和文件保管能力，但还没有运行期玩家状态的业务/语义权威。

C# `ArchiveTask` 当前主要提供整份 JSON 替换和一致性检查，没有领域 revision、CAS、幂等命令账本或多聚合事务核心；现役实现的“删旧文件 → 移动 `.tmp`”也不能直接充当未来 StateCore 的事务原子性证明。

### 2.2 背包、仓库和经济仍由 AS2 运行态对象掌管

`InventoryPanelService`、`ArrayInventory` 与 `ItemUtil` 共同承担：

- 容器 snapshot、tooltip、移动、合并、交换、整理、丢弃；
- revision、容器 epoch、slot lease 与事务写入口；
- 金钱、K 点、材料、情报、药剂、背包物品的获得和提交；
- `dirtyMark` 与生命周期事件。

源码中仍有大量 `_root.物品栏`、`_root.金钱`、`ItemUtil.acquire/submit/require` 等直接读写。动态别名和时间轴脚本还会放大实际写入面。因此迁移不能依赖一次性搜索替换，也不能让 AS2 和 Launcher 在同一领域长期双写。

### 2.3 主角和装备栏共享同一个活体实例

`DressupInitializer.loadHeroEquipment()` 直接返回 `_root.物品栏.装备栏.getItem(equipKey)`，随后把该 `BaseItem` 赋给主角 MovieClip。战斗代码对 `自机.长枪.value.shot` 等字段的写入，就是对装备栏/存档实例的原地写入。

这构成真实硬约束：

- 不能把每帧或每发子弹的字段写入改成同步 Host RPC；
- 不能在没有租约/运行态拆分的情况下声称 Launcher 始终独占活动装备；
- 未来若要彻底解除耦合，应把 `shot` 等战斗临时字段逐步从持久 `BaseItem.value` 拆入 `ActorRuntimeState`，但该重构不应成为第一阶段前置。

### 2.4 当前弹药是普通背包消耗品

武器 XML 用 `clipname` 指向“手枪通用弹药”“突击步枪通用弹药”“能量电池”“火箭弹弹药”等普通可堆叠物品。换弹路径通过：

1. `ItemUtil.singleContain(name, 1)` 检查；
2. 在换弹提交点通过 `ItemUtil.singleSubmit(name, 1)` 扣除；
3. `ItemUtil.getTotal(name)` 刷新剩余弹匣数。

`ItemUtil.contain()` 会先按物品身份把材料、情报路由到对应收集品栏，普通物品才搜索背包和药剂栏；`getTotal()` 又只对材料/情报走收集品栏，普通物品只累计背包。因此这些门面并非同一个统一容器查询。生产代码中约有 48 处 `singleContain/singleSubmit/getTotal` 调用，大多数集中于 `ReloadManager`、`LongGunSubWeaponCore`、`WeaponStateManager` 和少量战斗技能；另有佣兵、成就等非战斗调用，不能把整个 `ItemUtil` 直接重定向到战术包。

### 2.5 “50 格全传输”不是主要性能瓶颈

当前 `ArrayInventory` 查找通过已占用索引遍历，不总是扫描 50 个物理格；Web inventory snapshot 也支持 offset/limit 窗口。不过普通背包页面的 page size 为 50，`buildSnapshot()` 会为可见槽位（包括空槽）生成投影和 lease。

所以缩小工作集确实减少传输与 lease 数量，但更重要的收益是：

- 普通背包从 AS2 可写对象图中消失；
- Web 修改普通背包不再使战斗侧引用失效；
- 活动场景只需同步一个小型、明确语义的工作集；
- 未来技术替换只消费 `CombatLoadout`，不消费完整存档。

---

## 3. 路线争议与综合判断

### 3.1 路线 A：全部继续由 AS2 权威

候选做法是把物资箱沉淀出的 snapshot/revision/slot lease/reconcile 分别抽成 AS2、C#、Web 三层通用基板，再增加 Launcher CQRS 读副本。

可取部分：

- 提取通用命令 envelope、超时分类、revision gap、完整快照恢复；
- Launcher 维护只读投影，消除 tooltip、筛选、分页等读流量的 AS2 往返；
- 在 AS2 内先收口经济写入口。

不可作为长期终点的原因：

- 真实写仍跨 Web → Host → AS2；
- unknown commit、socket detach 和场景 teardown 仍可能威胁经济提交；
- 如果把物资箱专用 proof/watermark/recovery 状态机抽成通用基类，会把当前高成本模式制度化；
- 无法自然提供独立、可恢复的 `RogueRun` 持久状态。

结论：CQRS 读副本可作为过渡降本手段，通用传输原语值得抽取；不能把当前整套三层事务固化为以后所有面板的模板。

### 3.2 路线 B：Launcher 始终独占所有游戏状态

该路线会要求射击、弹匣、装备生命周期和演员状态持续跨进程同步，或者在 AS2 保留另一份可写镜像。

结论：不采用。它会把低频 UI 同步问题搬到高频战斗边界，形成事实双权威或不可接受的帧级 IPC。

### 3.3 路线 C：持久权威 + 排他执行租约（推荐）

Launcher 拥有持久档案和经济事务；AS2 只在明确阶段获得一个排他、有限、可结算的运行工作集。任一对象在同一时刻只有一个可写 owner。

该路线吸收了外部审阅中最重要的硬约束，同时不接受“装备活体引用存在，因此所有持久经济权威必须永久留在 AS2”的过度推论。

---

## 4. 目标权威原则

1. **不是尽可能外迁，而是按状态性质划界**：持久、跨 UI、跨玩法上下文的状态进 Launcher；帧关键模拟留 AS2。
2. **Web 永不成为业务权威**：Web 只提交命令、维护界面临时状态、消费投影。
3. **同一领域同一时刻只有一个可写 owner**：shadow compare 只能只读，不能以“双写同步”作为迁移方案。
4. **聚合作为单位迁移**：钱包、背包、仓库、装备归属、材料、收藏应视为 Ownership Aggregate；只迁金钱会继续制造跨权威交易。
5. **活动工作集可以租出，但必须排他**：Host 租出时锁定相应对象，Web 不得同时出售、移动或调制。
6. **不做帧级 IPC**：射击、AI、物理、技能帧、当前 HP/MP 和弹匣内部状态必须本地执行。
7. **持久化后确认**：Host 领域命令先校验、持久化，再向调用者确认。
8. **失败后不猜测**：未知结果按 `commandId` 查询或重取投影，不盲目重放非幂等写。
9. **存储引擎不是架构边界**：先建立 repository/transaction 接口；是否使用 SQLite 延后到真实需求出现。
10. **兼容镜像不是权威**：迁移后保留的 `_root.*` 只能通过投影适配器更新，并由 divergence detector 监测越权写。

---

## 5. 候选权威矩阵

| 领域 | 长期持久权威 | 活体执行权威 | Web 权限 |
|---|---|---|---|
| 存档槽、版本迁移、备份、导入导出 | Launcher | 无 | 受控管理 |
| 主线角色档案、RogueRun | Launcher | AS2 消费活动上下文投影 | 展示/发命令 |
| 钱包、背包、仓库、战备箱、材料、收藏 | Launcher | 默认无；只租出战术携行子集 | 直接对 Host 发命令 |
| 活动装备归属 | Launcher | AS2 在 execution lease 内修改活体字段 | 租约期只读或安全点操作 |
| 当前弹匣、`shot/reloadCount`、武器临时状态 | 检查点持久化或不持久化 | AS2 | 只读投影 |
| 战术包/快捷消耗品 | Launcher at rest | AS2 在场景租约内 | at rest 可写；active 只读 |
| 商店、制作、调制、掉落领取、Run 结算 | Launcher | AS2 仅产生世界意图或消费结果投影 | 直接对 Host 发命令 |
| 地图、场景、AI、物理、输入、演员、战斗 | 不属于持久聚合 | AS2 | 无权威 |
| 世界物件触发/敌人死亡/箱体破坏 | AS2 现场裁决 | AS2 | 无权威 |
| 面板动画、选择、排序显示、焦点 | 无 | 无 | Web 临时状态 |

---

## 6. Launcher StateCore 候选模型

### 6.1 上下文分层

建议至少区分：

- `AccountState`：设置、账号级解锁；
- `CampaignProfile`：主线角色及主线资产；
- `RogueRun`：`runId`、种子、临时角色、等级、装备、背包、钱包、进度；
- `RuntimeProjection`：当前发给 AS2 的活动角色投影；
- `UiSession`：面板实例、焦点和短期 capability，不进入角色存档。

### 6.2 命令 envelope

候选统一字段：

```text
contextId
commandId
expectedRevision
kind
payload
```

Host 按 `contextId` 串行执行命令，保存近期 `commandId` 结果以支持幂等重试，返回：

```text
success / error
contextId
commandId
newRevision
projection or patch
```

AS2/Web 只应用单调递增投影；发现 revision 空洞、上下文变化或未知 patch 时请求完整 snapshot。

### 6.3 初期持久化策略

当前存档体量很小。试点阶段可以使用：

- versioned envelope；
- 整聚合临时文件 + 原子 rename；
- 与聚合新状态、命令结果处于同一耐久提交的有界幂等命令账本；
- 备份与显式迁移；
- JSON 导入导出和诊断投影。

账本若与聚合分文件，必须由正式 ADR 给出可恢复的原子提交协议；不得先写聚合、后写账本再声称 exactly-once。账本淘汰也必须绑定客户端最大重试窗口、持久 tombstone 或等价防重规则，不能让旧 `commandId` 在失忆后重新生效。

只有当多聚合事务、历史查询、长 Run 日志或审计量证明需要时，再评估 SQLite。不要让数据库选择阻塞 ownership 边界验证，也不要引入自制通用 event store。

---

## 7. 排他执行租约

### 7.1 生命周期

```text
AtRest（Launcher 可写）
  → LeasePreparing（冻结相关 Host 写）
  → ActiveInAS2（AS2 排他执行）
  → Settling（拒绝新命令，提交最终 delta/snapshot）
  → AtRest（Host 持久化并收回所有权）
```

租约至少绑定：

```text
leaseId
contextId
baseRevision
runtimeGeneration
worksetDigest
eventSeq / checkpointSeq
```

### 7.2 规则

- 租约签发前 Host 必须持久化“对象已租出”的状态，避免 Web 同时使用同一物品。
- AS2 只能修改租约工作集，不能扫描或写入完整 Host 背包。
- Host 在租约期拒绝冲突写；安全补给点必须先 checkpoint/settle，再重签租约。
- 普通高频帧状态不跨 IPC；弹夹、稀有消耗品等低频经济变化可按事件或检查点异步提交。
- 场景退出前需要一次通用 settle barrier，但它只结算一个小型工作集，不再为每个面板/槽位建立专用 proof 状态机。
- socket 断开或进程崩溃的恢复策略必须显式裁决，不能默认“AS2 本地即最终真相”。

---

## 8. CombatLoadout / 战术携行集

### 8.1 目标

CombatLoadout 是 Launcher 持久资产与 AS2 活体战斗之间的窄桥：

```text
CombatLoadout
├─ ActiveEquipment
├─ WeaponRuntimeState
├─ TacticalPack
├─ QuickItems
└─ CombatSkills
```

完整 50 格背包、1200 格仓库和 400 格战备箱默认不进入 AS2。

### 8.2 战术包不是第六个通用 ArrayInventory

建议初期只支持 8～12 个“补给种类槽”，允许：

- `use=弹夹` 的弹药；
- 能量电池；
- 燃料罐；
- 明确标记的手雷/战斗消耗品；
- 肉鸽规则允许的临时道具。

默认禁止：

- 武器、防具和配件；
- 任务物品；
- 材料、情报、收藏品；
- 制作/商店专用资源；
- 任意未登记物品类型。

authoritative representation 可采用稳定 `supplyId/itemId + count`，UI 槽位只是布局；不要为每个槽位复制 inventory domain 的独立 lease。整个 TacticalPack 使用一个 execution lease。

### 8.3 AS2 访问接口

不再让换弹逻辑调用通用 `ItemUtil`：

```text
CombatSupplyService.has(name, count)
CombatSupplyService.consume(name, count)
CombatSupplyService.getCount(name)
```

加载时建立 `reserveCountsByName`，战斗查找为 O(1)。

非战斗经济使用另一入口：

```text
EconomyFacade.credit/debit
EconomyFacade.acquireItem/consumeItem
EconomyFacade.transferItem
```

迁移期 facade 可先调用旧 AS2 backend，后续切到 Host backend。这样收口代码不会成为一次性废弃层。

### 8.4 传输与结算

场景进入时只传：

```text
contextId
leaseId
loadoutRevision
equippedItems
tacticalSupplies
quickItems
```

备用弹夹通常只在换弹时扣除，不需要逐发同步。可在换弹提交后异步发送：

```text
leaseId
eventSeq
supplyId
delta=-1
reason=reload
```

Host 幂等记录；场景切换再做完整 checkpoint。`shot` 等弹匣内部状态只需在检查点同步，或明确为不保证崩溃精确恢复的运行态。

### 8.5 拾取策略

推荐默认规则：

- 普通战利品进入 Host `LootPouch/待结算物资`；
- 不把捡到的普通装备或材料推入 AS2 背包；
- 只有显式标记为“即时战斗补给”的物品可通过幂等 `grantSupply` 进入当前 TacticalPack；
- 是否允许超容量、自动合并或立即使用必须由 CombatLoadout 规则裁决，不回退到完整背包扫描。

### 8.6 兼容旧主线体验

战术包会改变“背包里有弹药即可使用”的现有体验。主线可默认提供自动补给策略：

- 根据已装备武器推导所需 `clipname`；
- 玩家配置目标携带量；
- 进入关卡前由 Launcher 从背包自动装入；
- 离开关卡后剩余补给回到持久携行集；
- 肉鸽模式可采用严格有限容量。

---

## 9. 地图物资箱在目标边界下的形态

候选流程：

1. AS2 判定箱体被打开/破坏，生成稳定 `worldEventId`；
2. Host 幂等物化并持久化战利品容器；
3. Web 只与 Host 查询、领取、整理；
4. Host 在同一进程内原子修改战利品容器和 Ownership Aggregate；
5. AS2 只接收箱体已消费/剩余/视觉关闭投影。

第一阶段允许 AS2 继续计算掉落结果，但必须把结果连同 `worldEventId` 交给 Host 幂等持久化；以后再把掉落规则生成迁到经过校验的 item/rule manifest。

预期可删除或显著收缩：

- 领取写结果跨 XMLSocket 的精确 proof；
- Host/Web 双 freshness watermark；
- panel close 对经济事务终态的参与；
- 为保护临时 AS2 容器而建立的场景 teardown 特性屏障；
- 大量特性专用 7/8/9-key recovery wire。

当前在途物资箱不建议立即推倒重写。应冻结扩张、收束最小可用切片，把它保留为新边界的回归样本；StateCore 试点通过后再替换其经济权威链。

---

## 10. 肉鸽热切换

### 10.1 现有可复用原语

- 场景创建主角时会重新读取 `_root` 角色字段；
- `packGameState()/loadFromMydata()` 提供初步对称装载能力；
- `newCharacter()`、删档和斗兽标定枚举了部分清理/禁存需求；
- 斗兽标定已有 `_root.斗兽标定禁存档`，可用于无持久化技术探针。

这些是施工素材，不是完整热切换保证。`loadFromMydata()` 不会自动证明所有 manager、timer、event listener、被动效果和缓存已经按角色上下文重建。

### 10.2 Character Manifest

必须先建立显式、机器可验证的角色字段清单：

- 角色身份、等级、经验、属性；
- 装备、技能、快捷栏、宠物/佣兵关系；
- 背包/钱包/收藏等持久领域；
- HP/MP、弹匣、临时 buff 等运行领域；
- 设置、键位、音频等账号/设备领域；
- 切换后必须重建/销毁的 manager、缓存与订阅。

该 manifest 应同时约束 Host 投影和 AS2 adapter，不能只维护为某个 `newCharacter()` 函数内的隐式清单。

### 10.3 安全切换流程

```text
1. 仅在基地/安全边界申请 context switch gate
2. 阻止新经济命令，等待在途命令完成
3. 关闭/静止 panel、输入、活动 CombatLoadout lease
4. teardown 当前世界、演员、manager、timer、listener、被动与缓存
5. Host 原子激活目标 contextId
6. Host 下发完整 revisioned RuntimeProjection + CombatLoadout
7. AS2 写入兼容镜像并重建装备/技能/HUD/输入
8. AS2 回报 projection/workset ack 后进入新场景
```

Run 结束时由 Host 通过 `runId + settlementId` 幂等结算到 CampaignProfile。

### 10.4 技术探针与正式玩法分开

第一轮可复用斗兽标定模式做“主线内存快照 → 禁存 → 注入临时角色 → 场景重生 → 恢复主线”的廉价探针，只验证 Character Manifest 和 AS2 生命周期清理。

正式肉鸽不能只依赖禁存：活动 Run 应是 Launcher 中独立、可恢复的 `RogueRun`，支持崩溃恢复、跨场景继续和幂等结算。`mydata.ext.roguelike` 可保留局外 meta，但不应成为活动 Run 全部状态的唯一容器。

---

## 11. 分阶段路线

### P0：稳定性止损 + 迁移基座收敛

P0 拆成两个可并行但治理独立的工作包；P0-F 的完整范围和退出门见 [P0-F 跨层迁移基座与架构收敛专项](P0-跨层迁移基座与架构收敛专项-2026-07-23.md)：

- **P0-S 稳定性止损**：冻结当前物资箱继续泛化；完成 `force_flush`/安全退出握手等已知存档窗口加固；明确“shadow 主路径”与 SOL legacy/回退的长期关系，但不把文件保管误称为业务权威迁移。
- **P0-F 迁移基座收敛**：新增 durable-domain Web panel 前先冻结命令业务裁决层、现役 identity 和失败语义；复用现有 Panel/Task/inventory/事务/测试基建，只收口 transport lifecycle 机械重复，不在 P0-F 预做聚合权威迁移或通用 context 框架。

本文本身不修改生产协议；P0-S 的具体修复，以及 P0-F 中真正触发 wire/schema 变化的工作，仍分别通过窄 ADR 或现役契约变更落地。P0-S 不属于 P0-F 的 F0–F4，不得随其顺带施工。P0-F 的当前状态、workstreamId、owner、暂停范围与 terminal 只以专项章程头部为准，本文不复制动态状态；该门不按机器位置套用，也不改变其他协作者的贡献方式或主线准入。Execution lease 另立玩法/上下文 ADR，只复用 P0-F 已证明的机械原语，不由 P0-F 预建。

### P1：收口与清单

- 建立 `EconomyFacade` 与 `CombatSupplyService` 门面；
- 对约 48 处 `singleContain/singleSubmit/getTotal` 生产调用做战斗/非战斗分类；
- 建立 Character Manifest；
- 从 XML 生成带 digest 的 item catalog / combat-supply manifest；
- 盘点所有 `_root` 直接写入，建立迁移期 divergence detector。

### P2：只读 StateCore

- 定义 versioned state envelope 和 repository；
- 导入现有 v3 存档，导出 AS2 兼容投影；
- 用真实/构造存档进行 shadow compare；
- 建立统一命令 envelope、revision 和幂等账本，但不接管生产写；
- 严禁 AS2/Host 双写同一领域。

### P3：肉鸽绿色试点

- 新建 Launcher-authoritative `RogueRun`；
- Run 使用独立钱包、背包、装备和 CombatLoadout；
- AS2 只接收活动角色投影和 execution lease；
- Web 面板直接对 Host 发命令；
- 先完成基地 → Run → 基地同进程切换和崩溃恢复，再扩展玩法。

### P4：主线 CombatLoadout

- 主线新增战术携行配置和自动补给兼容模式；
- 换弹、子武器和战斗消耗从 `ItemUtil` 切到 `CombatSupplyService`；
- 完成 execution lease、低频消费事件和场景 checkpoint；
- 完整背包不再进入 AS2 战斗扫描。

### P5：迁移主线 Ownership Aggregate

以一个切换门迁移：

- 钱包；
- 背包、仓库、战备箱、药剂；
- 装备归属与实例；
- 材料、情报、收藏品。

迁移后旧 AS2 writer 必须 fail closed；AS2 只保留投影和活动租约工作集。

### P6：迁移依赖经济事务

- 地图掉落/物资箱；
- NPC/KShop；
- 制作、调制、分解；
- 任务奖励；
- 宠物/佣兵购买；
- Run 结算。

技能配置、名册、成就和长期进度按收益继续迁移；战斗、AI、物理和地图运行没有必要为了架构纯度搬出 AS2。

---

## 12. 验收门

### 存档与 StateCore

- 至少几十份真实/构造存档无损导入、导出、再导入；
- Ownership Aggregate digest 与旧 AS2 shadow 在只读阶段一致；
- migration 失败不覆盖原档，备份和回退路径可验证；
- “持久化完成、响应未返回”之间强杀后，命令重试仍恰好执行一次。

### 投影与越权

- AS2/Web 对乱序、重复、revision gap、断线和 full snapshot 有确定行为；
- 已迁移领域的 `_root` 越权写可以被检测并 fail closed；
- Web 在 Flash socket 不可用时仍可独立验证 Host 领域读写，但真实游戏写在必要前置缺失时 fail closed。

### CombatLoadout

- 租约期 Host 拒绝出售/移动同一物品；
- 换弹、双枪、tube、战术换弹、子武器 onFire/onReload 消耗与旧语义等价；
- 断线/崩溃时备用弹药的恢复策略有明确、自动化证据；
- 连续多场景进入/退出不重复或丢失物品；
- 普通背包操作不再使活动装备/补给引用失效。

### 肉鸽热切换

- 同一 Flash 进程完成 Campaign → RogueRun → Campaign；
- 主线档案 digest 不变，Run 状态独立保存；
- 没有残留 manager、timer、listener、被动效果、输入或旧演员引用；
- Run 崩溃恢复和 `settlementId` 重试不重复发奖；
- 多轮切换后的内存、帧率和事件计数稳定。

### 真实 E2E

遵守 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified` 术语。自动测试、旧 trace、单个 marker 或本地 candidate 不能被表述为正式部署。

---

## 13. 主要风险与防线

| 风险 | 防线 |
|---|---|
| AS2 直接写入面大、动态别名漏检 | facade strangler + 静态审计 + runtime divergence detector |
| 活动装备同一对象身份 | 排他 execution lease；逐步拆分 ActorRuntimeState |
| Host/AS2 长期双写 | 每领域 `authorityMode`；任一时刻只允许一个 writer |
| 过早抽象物资箱协议 | 只抽 envelope/idempotency/revision/full snapshot，不抽专用 proof 机器 |
| 战术包改变主线体验 | 自动补给兼容模式；肉鸽先采用严格容量 |
| 弹药崩溃恢复产生复制/丢失 | 低频幂等消费事件 + 场景 checkpoint + 显式异常策略 |
| 地面拾取又把完整背包拉回 AS2 | Host LootPouch；仅登记即时补给进入 TacticalPack |
| context switch 只换数据不清运行态 | Character Manifest + teardown/rebind registry + 多轮泄漏测试 |
| SQLite/新依赖扩大 runtime 发布闭包 | 先 repository abstraction 和原子 JSON；需求证明后再选引擎 |
| 旧 MOD 依赖 `_root` 直写 | 明确兼容等级；提供 facade；越权写记录和迁移窗口 |

---

## 14. 决策登记

### 已形成稳定推荐

- Launcher 长期应成为持久玩家状态与经济事务核心。
- AS2 继续拥有实时游戏模拟和租约内活体执行权威。
- Web 不成为权威，迁移领域优先直接与 Host StateCore 协调。
- 使用排他 execution lease，避免帧级同步和事实双权威。
- 引入 Character Manifest、EconomyFacade、CombatSupplyService。
- 以新肉鸽 Run 作为绿色试点，避免先冒险迁移全部主线旧档。
- 完整背包不进入 AS2；战斗只接收 CombatLoadout/TacticalPack。
- CQRS 读副本是可选过渡优化，不是最终写边界。

### 明确不采用

- Launcher 同步裁决每发子弹/每帧演员状态；
- 继续让所有持久经济领域永久留在 AS2，只把现有三层恢复状态机通用化；
- 在同一领域运行 AS2/Host 双 writer 再靠对账合并；
- 把纯内存禁存模式当作正式肉鸽持久化；
- 直接新增一个功能完整、继续复制 slot lease 的“第六背包”；
- 在权威边界未验证前先引入通用数据库/event store。

### 尚待 ADR 裁决

- TacticalPack 最终是 8、10、12 格，还是按种类/重量容量；
- 哪些 XML 类型可标记为 `combatSupply`；
- 主线自动补给的默认数量与旧档兼容策略；
- 活动租约崩溃时未确认弹药消耗采用保守扣除、最近 checkpoint 还是其他策略；
- 战斗中拾取即时补给的 exact grant 语义；
- `shot/reloadCount` 哪些字段需要检查点持久化；
- StateCore 初期文件 envelope 和幂等账本的精确格式；
- 主线 Ownership Aggregate 的切换窗口和回退政策。

---

## 15. 后续会话重入规则

后续 Agent 讨论相同主题时应先读取本文，再按任务补读 canonical doc。除非代码基线或目标发生实质变化，不要重复从头回答“是否迁移权威”。优先从下列开放项继续：

1. Character Manifest 字段审计；
2. 48 处战斗/非战斗物品消费调用分类；
3. CombatLoadout/TacticalPack 正式 ADR；
4. StateCore versioned envelope 与 command ledger 设计；
5. 肉鸽无持久化热切换探针；
6. 绿色 RogueRun 持久试点；
7. P0-F 现有机器契约演进、Host pending-call helper 与首个 Transaction 试点 ADR。

开始实施前必须重新核对当前 commit、工作树、最新物资箱状态与 canonical docs；本文中的行数、调用点数量和实现状态是 `466b899...` 基线上的调研快照，不得当作永久不变量。

---

## 16. 关联文档与代码锚点

- [AS2 UI 到 Web Panel 迁移护栏](../agentsDoc/as2-web-panel-migration.md)
- [系统架构](../agentsDoc/architecture.md)
- [Launcher source of truth](../launcher/README.md)
- [验证矩阵](../agentsDoc/testing-guide.md)
- [技术栈保留 / 收敛评估](tech-stack-rationalization.md)
- [地图资源箱 S1/S2 ADR](地图资源箱-S1S2真实战利品容器与Web双栏-ADR-2026-07-18.md)
- [跨层契约与交互可靠性专项治理](Web-Panel跨层契约与交互可靠性专项治理-2026-07-22.md)
- [P0-F 跨层迁移基座与架构收敛专项](P0-跨层迁移基座与架构收敛专项-2026-07-23.md)
- [`SaveManager.as`](../scripts/类定义/org/flashNight/neur/Server/SaveManager.as)
- [`InventoryPanelService.as`](../scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as)
- [`ArrayInventory.as`](../scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as)
- [`ItemUtil.as`](../scripts/类定义/org/flashNight/arki/item/ItemUtil.as)
- [`DressupInitializer.as`](../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as)
- [`ReloadManager.as`](../scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ReloadManager.as)
- [`SkillReloadCore.as`](../scripts/类定义/org/flashNight/arki/unit/Action/Skill/SkillReloadCore.as)
