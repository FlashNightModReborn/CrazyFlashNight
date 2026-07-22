# AS2 UI 到 Web Panel 迁移护栏

**文档角色**：AS2 UI 迁移到 Launcher Web Panel 的专题 canonical doc。
**最后核对代码基线**：正式 promotion commit `6218f8b1d82efc57b77131616667fe45f3033297`（release tree `e1e6e059f148a640b3e37cbf1d912f297156d956`，2026-07-22 换机标准入口复核）；主线仍允许 native 源码 fast-forward 直推并由事后 Audit 报告 `source-ahead`，但只有本文记录的 immutable request、v2 consensus、promotion 与同身份标准入口证据才构成正式部署证据。Skill、合成、双栏工作台与 runtime v2 的细分门以对应专题 canonical doc 为准。

本文用于所有“旧 Flash / AS2 UI 迁移到 Launcher WebView2 panel”的任务。它不是普通前端开发指南，而是跨 AS2、C# 总线、Web panel、Flash CS6 编译链的稳定性护栏。凡迁移旧 UI、替换运行态入口、扩展 panel 协议、把 dev harness 推向生产，都必须先读本文。

专题规划与施工记录：[技能系统-Web面板独立迁移-工程落地规划-2026-07-15.md](../docs/技能系统-Web面板独立迁移-工程落地规划-2026-07-15.md) 已落地 `panel/domain=skills`、管理/教师双模式、学习 token 原子提交和快捷栏模型抽离；我的技能主入口归 NativeHud / fallback Notch 的独立 `SKILLS`，NPC 教师保留情境入口，旧物品栏技能页不迁成 Web 转发器。Skill 使用 same-panel rebind + 顶层 `panelInstanceId`、`reconcileId/reconcileAfterCallId` 显式未知写对账、active/candidate/return trainer capability 撤销、正确 escaping JSON encoder，以及观察期旧 UI writer 领域 bridge；这些差异不得照抄 Crafting 的普通 snapshot/generation 恢复。教师页提供 Host 盖章的 `switch_manage`；只有该路径派生的 manage 实例得到 `canReturnTrainer=true` 并可发 `switch_trainer`，trainer session 始终留在 Host、learnToken 不跨 view。Web 展示层复用 `GridDensityController`、`FilterNavigator` 的按钮/计数/键盘 primitive、`PointerDragController/InteractionBroker` 与 `PanelTooltip.convertAS2Html`，manage 采用全宽技能库 + 1—12 单排技能带；紧凑态与物品 owned grid 共用 `48px` 格、`40px` 图标和 `4px` 间距，完整卡共用 `68px` 高度节奏，但不复用物品 taxonomy/facets/lease。技能→快捷槽保持 equip 确认，快捷槽→快捷槽以单条 `moveSlot` 在空槽间移动或对占用槽交换，技能→技能格直接调用既有 reorder 交换；常驻上移/下移退役，快捷槽 `Alt+←/→` 与技能格 `Alt+↑/↓` 保留非指针兜底。已装备目标、普通模式已装备源及异常行在排序落点阶段拒绝；EasyMode 只放宽已装备源。Skill 不再照搬物品目录树：形态、配置/学习、流派三组直接 facet 始终同时可见，首击即生效、跨组可组合并支持一键清除；武术、科技等流派按真实 `Type` 投影。名称搜索默认收起；manage 不显示 metric，trainer 只保留等级/技能点，稳定同步/刷新/协议术语退出常态视觉层。异常态才显示玩家语言的重试/确认结果与诊断复制，复制内容保留实例/revision/callId/reconcile 但禁止输出 trainer session/learnToken。S0–S5 代码与自动门、四个实际 Flash 目标发布及 FFDec 静态证据已接入；NativeHud `SKILLS` 的真实 Win32 manage 点击已覆盖常规、生产最小、4:3 与 1920×1080 几何，真实 `The Girl → 学习技能` 已打开 `技能研习` 并渲染 `兴奋剂 / 能量盾`，此前 trainer→manage same-panel rebind 也已通过；新布局/往返尚只有自动几何证据。旧技能页的两个 live 图标实例以互斥 child-depth 指纹确认实际命中 main `DefineSprite 53`，不是 things id2706；S4C 现只缺 legacy fallback 事务等价/重启回读，S5 现只缺 legacy Notch/fallback、pending-write/断线真机 Gate，S6 观察/旧 UI 删除仍按专题规划保持未完成。

Skill 最新展示收口又视觉隐藏通用 L/R slot marker，但不删除 slot/ARIA/焦点语义；顶栏 `?` 以同一 Web 模态按 manage/trainer 投影不同操作说明，帮助开闭不触发 AS2/Host 消息也不清理筛选或选择。三组 direct facet 与真实流派映射加入后，manage 以两行承载三组筛选；物品/技能共享尺寸 token、技能格交换拖拽、排序拒绝落点和 `Alt+↑/↓` 均已接入。完整/紧凑现在明确只控制技能库，Hotbar 固定为居中的 `12×64px` 方槽、`48px` 图标与 `3px` 间距，使用连续底板；选中态保留等级，卸载 `×` 仅在悬停/聚焦时与等级切换。管理态顶栏在“技能库 完整/紧凑”旁以等宽、中性外框的“快捷栏 安全/快速”独立分组常显本机确认偏好，完整“快捷栏操作确认”语义保留在 aria-label，帮助模态只解释规则而不再承载设置入口：安全模式空槽直装而替换/卸载确认，快速模式三者直写，但两种模式都不能绕过技能学习确认；偏好不进入存档或 wire。物品格视觉矩阵仍为 `10/10`。内置交互浏览器仍无实例，故该变化只有自动 DOM/几何证据。

Skill 页切换把 `Bridge.send` 严格定义为本地 transport 投递结果：只有显式 `false` 才显示连接失败，`true` 不冒充 Host 业务受理；等待新实例 rebind 期间按钮锁定，超时恢复原 NPC 页重试，教师能力仍由 Host/AS2 裁决。

2026-07-16 教师能力过期语义从“创建后固定 120 秒”收敛为“连续 120 秒无成功教师域请求”：每次通过 NPC/场景/目录签名复验的 snapshot、preview 或 commit 都刷新 `lastTouchedAt`，但只有明确 NPC 教师入口可以签发能力，close/rebind/断线仍立即撤销，NPC、场景或目录变化仍立即失效。Web 选技能、调目标等级后以 debounce + latest-wins 自动预览，常态“计算消耗”按钮退役；右侧决策栏常驻技能说明、目标等级、权威消耗、研习后余额和门槛原因，主动作固定为“研习至 Lv.X · N 点”。30 秒 learnToken 在进入确认前按 25 秒前端新鲜度门静默重取，最终学习确认不取消。`trainer_session_expired` 不再自动关闭面板，而保留目录与最后快照并显示“返回游戏重新对话”的终态说明，避免视觉上等同闪退。目标等级现使用整数吸附的离散横向 range：可直接点中间刻度、拖动或输入精确等级，原生方向键/Home/End 语义保留，`− / +` 只做微调，冗余“升 1 级”退役而“升至满级”保留。拖动/输入阶段只更新本地目标并保留上一份权威消耗，松开或确认后立即请求最终等级；等待态明确标注旧结果，CTA 在新预览匹配前保持禁用。对应 Edge 三视口门为 `126/126`，fresh Flash Output Panel 为 `SkillPanelServiceTest 45/45`。

2026-07-16 快捷槽互拖的首次真机失败表明 Host 运行时产物也是协议闭环的一部分：日志若停在 Web `moveSlot` 已路由、但没有 `skillMoveSlot` Flash dispatch/response，应先核对游戏实际加载的 `runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll`，不能仅凭源码和 xUnit 判断协议已部署。凡修改 C# 命令白名单或映射，`launcher/build.ps1` 只会生成隔离 candidate；开发联调必须启动当前 tree、由脚本返回的精确 Core，并记录实际进程路径、build identity 与 payload closure，不得复用合并前 candidate 或把单个 Core 覆盖到正式目录。若要声明正式部署，还必须冻结 immutable Git-tree request，由不同 signer 与真实不同 `faultDomain` 形成 quorum，取得 production policy receipt、通过 v2 strict verifier 后再 promotion 原子写入完整闭包，并从 `automation/start.ps1` / 根 bootstrap 标准入口验证同一身份；不得手工复制或单独恢复任一二进制。

同日又收口了观察期原生 AS2 HUD 的图标投影：领域写成功后不再只更新旧槽位的 `已装备名/数量/CD/MP`，而是由 `SkillLoadoutService.projectQuickSlotRenderer` 在替换时强制走“空 → 默认图标”帧以重建 attachMovie 图标壳，卸载时清空全部显示字段并停在空帧。该 renderer 不反写 root 槽位/技能行，也不重置 `ManualCooldownService`；新鲜 Flash trace 为 `SkillLoadoutServiceTest 50/50`，`asLoader.swf` 已刷新为 990,467 bytes，FFDec 定点证据已确认 root bridge、`skillMoveSlot` 与 class `moveSlot` 方法进入产物。

快捷槽互拖必须使用独立原子命令 `moveSlot {sourceSlot,targetSlot,expectedRevision}`，不能在 Web 或 Host 侧拼接 equip/unequip。源槽为空返回 `slot_empty`；目标为空则移动，目标占用则交换；同物理槽与 EasyMode 同技能双槽为无副作用 no-op。源/目标中的非空技能都必须通过 learned、metadata、equippable、非纯被动与 `stateHealth=ok` 检查；成功只增长一次 revision、只 dirty 一次并返回一份完整 snapshot。指针拖动无需确认，拖出槽带取消；键盘以 `Alt+←/→` 移动并让焦点跟随被移动技能，便于连续调整。

## 1. 迁移分级

| 分级 | 判断标准 | 不允许声称 |
|------|----------|------------|
| 静态原型 | 只有 `launcher/web/modules/*/dev/` harness、mock 数据、美术资源 | 不得说“已接入运行态” |
| Web panel 原型 | 有正式 JS module 与 `Panels.register`，但未接 AS2 / C# 写操作 | 不得说“功能完成” |
| 协议接入 | Web cmd、C# Task、AS2 handler、response task 全链存在 | 不得跳过验证直接合并 |
| 生产可用 | 完成构建、xUnit / harness、Flash fresh trace 或人工复核、游戏内端到端手测 | 才能说“迁移完成” |

`modules/*/dev` 默认只是原型。进入生产前必须有正式模块、panel 注册、协议接入、验证入口和文档同步。

## 2. 迁移闭环表

每个功能命令必须维护一张闭环表。没有闭环表，不允许说协议完成。

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `xxxSnapshot` | `handleSnapshot` | `xxx_response` | `panel_resp panel=xxx cmd=snapshot` | `Bridge.on('panel_resp')` | 读 |
| `save` | `xxxSave` | `handleSave` | `xxx_response` | `panel_resp panel=xxx cmd=save` | 对应 callback | 写 |

当前 `tasks` panel 的第一防线调度板闭环如下；它是 `tasks` 的聚合视图，不新增 panel ID：

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `dispatchBoardSnapshot` | `dispatchBoardSnapshot` | `handleDispatchBoardSnapshot` | `task_response` | `panel_resp panel=tasks cmd=dispatchBoardSnapshot` | `DispatchBoardView` callback | 读 |
| `dispatchBoardDetail` | `dispatchBoardDetail` | `handleDispatchBoardDetail` | `task_response` | `panel_resp panel=tasks cmd=dispatchBoardDetail` | `DispatchBoardView` callback | 读 |
| `dispatchBoardBriefing` | `dispatchBoardBriefing` | `handleDispatchBoardBriefing` | `task_response` | `panel_resp panel=tasks cmd=dispatchBoardBriefing` | `DialogueView` / `DispatchBoardView` | 读 |
| `dispatchBoardEnter` | `dispatchBoardEnter` | `handleDispatchBoardEnter` | `task_response` | `panel_resp panel=tasks cmd=dispatchBoardEnter` | `DispatchBoardView` callback | 进入关卡（不直接改存档） |

共享 inventory domain 同时服务 `kshop` 库存态与独立 `workbench`；商城库存态固定为背包—战备箱，`workbench` 只接受严格枚举 profile：`battlebox`（背包—战备箱，Native HUD 默认）或 `warehouse`（背包—真实仓库，仅宿舍场景入口）。三条入口不得复制权威逻辑：

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `inventorySnapshot` | `InventoryPanelService.executeSnapshot` | `inventory_response` | `panel_resp domain=inventory cmd=snapshot` | `InventoryCoordinator` | 读 |
| `tooltip` | `inventoryTooltip` | `executeTooltip` | `inventory_response` | `panel_resp domain=inventory cmd=tooltip` | 面板 tooltip callback | 读 |
| `discard` | `inventoryDiscard` | `executeDiscard` | `inventory_response` | `panel_resp domain=inventory cmd=discard` | `InventoryCoordinator` | 背包写 |
| `move/merge/swap` | `inventoryMove/Merge/Swap` | `executeTransfer` | `inventory_response` | `panel_resp domain=inventory cmd=同名` | `InventoryCoordinator` | 双容器写 |
| `autoTransfer` | `inventoryAutoTransfer` | `executeAutoTransfer` | `inventory_response` | `panel_resp domain=inventory cmd=autoTransfer` | `InventoryCoordinator` | 来源 lease + 目标容器权威自动落位 |
| `sortAndMerge` | `inventorySortContainer` | `executeSortContainer` | `inventory_response` | `panel_resp domain=inventory cmd=sortAndMerge` | `InventoryCoordinator` | 容器写 |

K 点商城保留独立 `ShopTask` 和既有无 `domain` 的 `shop_response` 形状，但新结算已收敛到与 NPC 商店同构的“权威预览 → opaque token → 原子提交”上位模型。购物车仍以 `saveCart` 保存恢复影子；新购买不再写入历史待领取队列：

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `bulkQuery` | `shopBulkQuery` | `shopBulkQuery` | `shop_response` | `panel_resp callId` | `KShopRequestMux` callback | 读；目录（含策划专柜 `type` 与物品 `majorType/use/actionType/weaponType`）/cart/历史待领取/K 点快照 |
| `saveCart` | `shopSaveCart` | `shopSaveCart` | `shop_response` | 同上 | `KShopWriteCoordinator` | 写；购物车恢复影子 |
| `checkoutPreview` | `shopCheckoutPreview` | `buildCheckoutPreview` | `shop_response` | 同上 | 二级结算页 callback | 读；重算等级/价格/余额/容量并铸 `checkoutToken` |
| `checkoutCommit` | `shopCheckoutCommit` | token 单次消费 + 复核 + `ItemUtil.acquire` | `shop_response` | 同上 | `KShopWriteCoordinator` + `InventoryCoordinator` 刷新 | 实际物品容器 + K 点 + cart 原子写 |
| `claim`（兼容） | `shopClaim` | `shopClaim` | `shop_response` | 同上 | 历史待领取 callback | 写；旧 `商城已购买物品` → 背包 |

`checkoutPreview` 只接受 `{v:1,cart:[{idx,qty}]}`；AS2 按当前 `_root.kshop_list` 重解 item/价格/等级。目录逐行下发权威 `maxQuantity`：装备为 1，普通堆叠物品只受 `999999` 技术护栏，情报再与 `ItemUtil.getInformationRemaining` 的实时剩余容量取最小值；旧 Host 未下发该字段时 Web 才兼容回退 999。`purchaseLimit`/`maxQuantity` 是显式设计配额或动态容量，不得再用统一 100/999 常量冒充策划规则。购物车恢复与 `saveCart` 同样按权威上限清理。整单由 `ItemUtil.require` 做无副作用容量预检，情报重复项先聚合且超过剩余量必须整体拒绝，不能依赖 `InformationCollection` 的末端 clamp。预览逐行返回 `maxAffordable/maxByCapacity/maxPurchasable`，整单返回余额、总价、预计余额、`canCommit/blockingError` 与单次 token；情报容量不足使用 `destination_full`。`checkoutCommit` 不再信任 Web cart，只消费缓存 plan 并重新解析当前目录、余额与容量；复核成功后先由 `ItemUtil.acquire` 全量计划并交付，再扣 K 点、清空恢复影子并强制存盘。余额或容量不足零写，`balance == total` 合法。未知/畸形/超时 commit 仍进入 `needs_reconcile`，只允许 `bulkQuery + inventory snapshot` 对账，绝不重放 token。`_root.商城已购买物品` 只保留既有存档的 `shopClaim` 兼容；legacy `shopCheckout` 也复用同一 `finalizeCheckout` 直接交付，不再产生新的待领取债务。新 Web 只展示并领取既有历史记录。 本轮 fresh CS6 定向 trace 为 `KShopCheckoutServiceTest 17/17`、`NpcShopPanelServiceTest 43/43`，随后 publish-only `scripts/asLoader.swf` 刷新为 **1,042,507 bytes** / SHA-256 `BDF39A00273DDD1DB84630FD8FAC4C81FE8BCB88C5109D52DECCB9E82BA2433E` / mtime **2026-07-22 09:17:56 +08**，Compiler Errors **0/0**；publish 本身不替代上述行为 trace。

NPC 金币商店使用独立 `npcshop` domain 与 `NpcShopTask`，不复用 K 点商城 `ShopTask`，也不把买卖硬塞进通用 `InventoryTask`。左栏固定 NPC 目录；右栏在 Web 组合层仍呈现背包与收集品两个并列 owned View，收集品内部再切材料/情报，其中情报只读。权威 wire 按数据所有权拆分：背包只来自 `domain=inventory` 的 `InventoryCoordinator`，`npcshop` snapshot 只返回 `views.material/intelligence`；Host 的 NPC 成功回包校验不得再要求或合成 `views.bag`。

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `npcShopSnapshot` | `NPC商店WebView.executeSnapshot` | `npcshop_response` | `panel_resp domain=npcshop cmd=snapshot` | `NpcShopRequestMux` callback | 读 |
| `tooltip` | `npcShopTooltip` | `executeTooltip` | `npcshop_response` | `panel_resp domain=npcshop cmd=tooltip` | tooltip callback | 读 |
| `tradePreview` | `npcShopTradePreview` | `executeTradePreview` | `npcshop_response` | `panel_resp domain=npcshop cmd=tradePreview` | 二级结算页 callback | 读；铸造单次 trade token |
| `tradeCommit` | `npcShopTradeCommit` | `executeTradeCommit` | `npcshop_response` | `panel_resp domain=npcshop cmd=tradeCommit` | 二级结算页 callback | 背包/材料 + 实际买入容器 + 金钱原子写 |

NPC 目录对象的 `purchaseLimit` 仅在策划显式配置时生效，合法域为 `1..999999`；未配置的装备以当前背包技术容量为上限，普通堆叠物品使用 `999999` 技术护栏，情报再取实时剩余容量。snapshot、trade preview、commit 与 legacy buy 必须复用同一上限解析；Web 对 `maxQuantity=0` 必须呈现“已达持有上限”并禁止创建购买意图。金额、收集栏容量任一不足均须在写前失败，禁止先扣全额再让 collection clamp 丢弃超额部分。

合成工作台使用独立 `crafting` domain 与 `CraftingTask`，不复用 inventory/NPC/KShop 的写协议。旧 `_root.改装系统.加载改装清单(分类)` 先尝试发送 `panel_request panel=crafting initData.category`，Launcher 或 socket 不可用时才回退 `物品改装界面` SWF。Host 与 AS2 对分类均固定白名单：`铁枪会/属性武器/烹饪/化学生产/武器合成/饰品合成/进阶防具/基础防具/公社防具/黑白契约/插件合成/大学装备`；Web 不能提交任意配方对象、物品名、材料数、价格、技能折扣或强化继承结果。snapshot 顶层 `gender:"男"|"女"` 是装备检视分支的权威值：AS2 从 `_root.性别` 规范化，Host 对缺失或非法值 fail-closed，Web 不从名称或素材反猜性别。

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `craftingSnapshot` | `CraftingPanelService.executeSnapshot` | `crafting_response` | `panel_resp domain=crafting cmd=snapshot` | `CraftingRuntime.RequestMux` callback | 读；配方目录 + 权威 gender + 当前余额/技能 + 单份可合成状态 |
| `preview` | `craftingPreview` | `executePreview` | `crafting_response` | `panel_resp domain=crafting cmd=preview` | 详情栏 callback | 读；接收 `craftCount=1..99`，重算总材料/余额/容量并铸 `craftToken` |
| `tooltip` | `craftingTooltip` | `executeTooltip` | `crafting_response` | `panel_resp domain=crafting cmd=tooltip` | tooltip callback | 读 |
| `commit` | `craftingCommit` | `executeCommit` | `crafting_response` | `panel_resp domain=crafting cmd=commit` | 提交 callback | 材料/背包/金币/K 点原子写 |

Skill 使用独立 `skills` domain；每个业务 envelope 顶层严格为 `{type,panel,domain,cmd,callId,panelInstanceId,payload}`，业务字段只进 `payload`。Host 同时维护写水位与 trainer active/candidate 清理 backlog，不同未发送 scoped cleanup 必须收敛 global cleanup：

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `skillSnapshot` | `SkillPanelService.handle("snapshot")` | `skill_response` | `panel_resp domain=skills cmd=snapshot` | `SkillCoordinator` callback | 读 / 显式 reconcile probe |
| `learnPreview` | `skillLearnPreview` | `handle("learnPreview")` | `skill_response` | `panel_resp domain=skills cmd=learnPreview` | preview callback | 读；签发单次 learn token |
| `learnCommit` | `skillLearnCommit` | `handle("learnCommit")` | `skill_response` | `panel_resp domain=skills cmd=learnCommit` | `SkillCoordinator` | 技能行 + SP 原子写 |
| `equip` | `skillEquip` | `handle("equip")` | `skill_response` | `panel_resp domain=skills cmd=equip` | `SkillCoordinator` | 12 槽写 |
| `unequip` | `skillUnequip` | `handle("unequip")` | `skill_response` | `panel_resp domain=skills cmd=unequip` | `SkillCoordinator` | 12 槽写 |
| `moveSlot` | `skillMoveSlot` | `handle("moveSlot")` | `skill_response` | `panel_resp domain=skills cmd=moveSlot` | `SkillCoordinator` | 12 槽原子移动 / 交换 |
| `setPassive` | `skillSetPassive` | `handle("setPassive")` | `skill_response` | `panel_resp domain=skills cmd=setPassive` | `SkillCoordinator` | 被动启停写 |
| `reorder` | `skillReorder` | `handle("reorder")` | `skill_response` | `panel_resp domain=skills cmd=reorder` | `SkillCoordinator` | 80 行顺序写 |

`switch_manage/switch_trainer` 是 panel-control，不进入上表的 AS2 业务闭环：固定 envelope 均为 `{type:"panel",panel:"skills",cmd,panelInstanceId,payload:{v:1,focusSkillKey}}`。Host 必须验证 exact top-level/payload 键集、当前 active skills 实例和 `SkillTask` 当前 view。trainer→manage 时 learnToken 失效，session 只暂存 Host，manage initData 仅投影 `canReturnTrainer=true`；manage→trainer 只允许这个派生实例，并从 Host 恢复 session，Web 不得上传 session。关闭/断线清理暂存能力，NativeHud manage 仍须通过真实 NPC `panel_request` 才能进入 trainer。展示复用保持窄边界：Skill 可用共享密度、`FilterNavigator` 按钮/计数/键盘、pointer drag 和 AS2 HTML 白名单注释 primitive；Skill 自建三组 direct facet，不使用物品 `branchTree`/面包屑，分类器、状态与 DOM class 均归 Skill，自始至终不得引入 inventory domain、AS2 facets 或 slot lease。

`snapshot` 下发配方索引、标题、产物展示投影、基础货币消耗、材料条数、`batchEligible`，并为每条配方增加 `canCraftOne + availability`；仍不把当前材料拥有量批量复制进最多 90 项的目录。Flash 对每条配方只构造一次 `craftCount=1` 的只读计划，复用与 preview 相同的等级、材料、货币与保守容量语义，但不做 `maxCraftCount` 二分探测；因此 snapshot 工作量被约束为“一条配方一次单份计划、零最大份数探测”。产物投影包含 `name/displayName/icon + majorType/use/actionType/weaponType`：`name` 只作物品/dressup manifest 身份键，`displayName` 只作玩家文案，`icon` 只作 Icons 资产键；三者不得互相替代，XML 源字段仅在数据解析层称 `displayname`。Web 复用共享 `ItemFilter` 在完整 snapshot 上做纯展示树筛选，筛选不改变稳定 `recipeIndex`；目录可显示状态标记、可合成计数和本地“只看可合成”，这些均为最近一次 snapshot 的引导信息，提交权威仍只来自随后 preview/token。选择单项后由 `preview` 解析 `#`（装备强化门槛 / 普通物品数量）、`##`（装备数量）和可选阶数，情报/图纸只门控不消耗。Flash 同时重算角色等级 + 逆向等级、铁匠 `max(0,1-level×0.05)` 双货币倍率、装备素材最高强化继承、余额和容量，返回逐材料 `owned/required/enough/consumed`、产物、调整后价格、阻塞原因与 `canCommit`。容量保持旧系统的保守语义：在扣素材前调用 `ItemUtil.require`，不依赖“同笔消耗腾格”；这可能拒绝一个理论上可由消耗腾格完成的合成，但不会产生部分写。

批量只对“堆叠产物且没有任何装备素材”的配方开放，装备产物、单 `#` 强化素材与 `##` 装备数量素材首轮都固定 1 份。`craftCount` 必须是 `1..99` 整数；消耗材料与金币/K 点按份数放大，其中双货币严格保持旧 Flash 语义，先对每份执行 `Math.floor(basePrice × 铁匠倍率)`，再乘 `craftCount`，禁止把小数余额写入存档或改成总价末尾取整。情报/图纸等不消耗凭证只检查原需求一次，产出总量为 `recipe.value × craftCount`。Flash 用不超过 7 次二分权威探测计算当前 `maxCraftCount`，预览返回总数并把份数写入状态签名/token；Web 只呈现 `− / 数量 / + / 最大`，不使用浏览器原生 number spinner。`data/crafting/化学生产.json` 原先 7 条手工“批量 ×10”重复配方已收敛为单条基础配方，由统一份数协议替代。

材料不足时 Web 可先用一次 `snapshot` 撤销当前 token，再在同一 Overlay 内切到既有 `workbench profile=battlebox`；玩家只能经 `domain=inventory` 的 lease/transaction 显式把装备或普通堆叠物品移回背包，合成服务绝不直接读取或暗扣战备箱。工作台的“返回合成”只保留 category/recipeIndex/craftCount 作为 UI 意图，返回后强制重新 `snapshot + preview`；同分类的展示筛选和“只看可合成”可保留，但不得携带旧 snapshot 或 token。收集品材料本就由 `_root.收集品栏.材料` 全局计数，不经过战备箱搬运。合成必须与商城/独立工作台同走全 anchor：`#panel-content inset:0`，内部 1024×576 `PanelScale` 等比铺满；双栏采用同一宽左窄右语言（约 60:40）。KShop/NPC/合成目录的 `FilterNavigator` 统一使用 `visualStyle=catalog` 视觉契约，宿主只用 CSS 变量覆盖强调色，禁止回退浏览器默认白色按钮或复制专属按钮类。目录与详情继续使用浏览器原生滚动行为，但由 crafting CSS 统一窄轨皮肤与 `scrollbar-gutter`，不得改成 JS 假滚动条。

`equipment-inspector.js` 是 Web 内共享的只读装备检视层，`crafting-inspector.js` 只保留合成文案/兼容 API；两者不增加任何业务 cmd/action，也不进入 AS2 写路径。合成详情原图标与调制页顶部当前装备图标保留为主入口；调制交换态仅在已经选定的目标摘要卡提供独立角标入口，不给材料、进阶、配件或交换候选目录批量加按钮。普通武器绘制完整装备 skin 且不带人物；刀类复合武器只按权威 `actionType` 分流，`双刀` 必须用 battle `兵器站立` 的真实 holder 同时绘制 `刀_装扮 + 刀2_装扮`，`疾影` 必须同时绘制 `刀_装扮 + 刀3_装扮`。`刀1_装扮` 只是主刀的兼容别名，不能当副刀；即使两个 holder 指向同一 skinKey 也必须保留两个槽位，不能按素材键去重；不得因普通刀恰好存在 `刀2_装扮` 就误判为双刀。复合状态启用 strict fields，渲染闭包必须精确满足预期两个 holder，且 `missing=0 / failedImages=0`；素材缺任一部件、battle rig 漂移导致 holder 不再是 2/2、或任一图片失败，都须整组回退当前 `icon`，禁止退化成会误导玩家的单刀特写。防具只绘制当前权威 `gender` 分支的装备 fields（头部可带脸型承托，上装不补手、下装不补脚、手套不补前臂、鞋不补腿），不得借用异性分支；其他物品、dressup 缺失、当前性别分支缺失或纸娃娃图片加载失败也回退当前 `icon`，图标再缺失时显式显示缺图。首次主动打开才懒加载 dressup manifest；默认 185% 特写，支持 pointer drag、滚轮、键盘/按钮平移缩放、全貌/重置与纸娃娃动画及当前动态图标静态首帧暂停/继续；Canvas 动画按 24fps 限流，外层 PanelScale 改变后重采样 backing。替换 modal、换主装备/交换目标、切 operation、关闭 session/modal 或切 panel 必须销毁唯一 live renderer、RAF 与监听器。

调制检视的离线全量验收固定枚举 `data/items/*.xml` 的 1197 条原始武器/防具定义，禁止按 `name` 去重；稳定身份使用 `sourceFile + 同文件同名 occurrence`，原始 ordinal 只作诊断元数据。生产候选闭包为 1197 个当前图标基线 + 543 个武器商品图 + 男女各 552 个防具聚焦，共 2844 个逻辑候选；人类必须裁决 1749 个实际生产分支，其中 102 个为无性别图标回退（3 把弩 + 99 条颈部）。默认 185% 增益、9 双刀、9 疾影、男女分支、缺图与 holder 闭包先由自动门裁决；33 个真实动态分支只按 resolver 选中的装备 field/skin 递归识别嵌套时间轴，必须打开 production live renderer 后显式记录 `motionReviewed` 才能通过。决定同时绑定覆盖 XML/代码/实际素材字节的 `sourceDigest` 与覆盖候选 PNG、关键 metrics/gates/motion 证据的 `reviewDigest`；opener 还须逐字节复核 2946 个落盘引用，partial、陈旧、越界、缺失或哈希不符一律 fail-closed。该决定文件只作人工 QA 证据，不得成为运行时逐物品路由表。

只有可提交预览才签发 opaque 单次 `craftToken`。`commit` 先消费 token，再按分类 + recipeIndex 重取配方，并比较配方签名、金币/K 点、等级/技能、背包/药剂栏 `mutationRevision` 与相关材料/情报/装备拥有态；任一变化返回 `stale_state` 且零写。复核成功后先备份四个容器与余额，`ItemUtil.submit` 扣材料、`ItemUtil.singleAcquire` 交付，交付失败则恢复容器/余额/dirty 状态；成功后才扣调整后的金币/K 点并标 dirty。内部 recipe/ref/备份不得进入 wire，token 在成功、失败或再次 snapshot/preview 后均不可重放。

`CraftingTask` 与 Web 均采用 `idle/write_pending/needs_reconcile`。超时、断线、发送失败、未知结果或畸形 commit 回包后禁止自动重放；合成的对账读必须是同一 recipeIndex 的结构完整 `preview`，因为它同时覆盖材料、余额、容量和产物状态，成功 preview 才解除 Host 写门。单独 `snapshot` 不足以证明具体配方资源状态，不得解除 `needs_reconcile`。

资源 lease 与交易计划 token 必须分开治理。`slotLease` 是 inventory 资源的 OCC 版本：同一 `ArrayInventory` 实例、同一 `mutationRevision`、同一槽位引用与确认指纹上的重复 snapshot 必须返回同一 opaque lease，纯读不得调用全局 session reset 或使其他面板刚取得的 lease 失效；snapshot 同时回显 `containerVersion` 供诊断。任一真实容器写入推进 `mutationRevision`，容器替换、引用/数量/名称/强化/进阶/插件/更新时间变化也必须使旧 lease 返回 `stale_state`。NPC 材料/情报的 collection lease 同理：同商店、同 view/key/count 的重复读保持稳定，切换商店、键消失或数量变化才轮换并清理旧映射。`tradeToken` / `checkoutToken` / batch token 是一次性交易计划，显式重同步或一次提交尝试后仍须失效，不能为了“稳定 lease”改成可重放。

装备调制的 Web 组合遵守同一边界：顶层固定为“强化度 / 交换 / 进阶 / 配件”四栏，wire 为七类 operation（含 Web 组合态 `replace_mod`；旧 renderer 仍只适配原六类入口）。成功 snapshot 顶层必须携带规范化 `gender:"男"|"女"`；AS2 由 `_root.性别` 生成，Host 对缺失/非法值以及 commit 内嵌畸形 snapshot 一律 fail-closed，Web 不猜默认性别。强化度采用本地整数目标控件，停止调整后 debounce 发送最终 target，任何材料消耗只显示 AS2 preview，最终仍以单枚 token 提交；snapshot 的材料持有量按 `{itemName,count}[]` 读取，动态 `availableMaxLevel` 与永久 `hardMaxLevel=13` 必须分开，封顶态不得构造不可执行的 `+14`。强化石当前持有、preview 消耗和强化后剩余统一在顶部 DLS 核心呈现，持有数是主信息；强化 footer 只保留动态 CTA，不再重复装备 delta、材料行和核算说明。不得恢复逐级确认、二级强化切换行或常驻“核算强化”按钮。进入交换态时，左栏继续只承担主装备选择，既有 `filterKey/filterSpec`、面包屑和排序不得被改写；组合层通过 inventory coordinator 的独立只读 projection，以 source 的精确 `majorType + use` 取得带新鲜 lease 的同类装备并在右栏渲染目标候选。与 source 强化度相同的装备不进入 Web 候选目录，空态须明确说明“没有强化度不同的同类装备”；AS2 同级 no-op 校验继续保留以处理 projection 后状态变化。projection 不写回可见 `_requests/_windows`，同槽/不同 use 仍由 Web 收敛与 AS2 二次拒绝，右栏候选不能成为安全边界。候选 tooltip 必须把 AS2 `TooltipComposer` 产出的 `introHTML/descHTML/itemType/itemUse` 保持分段到共享 `PanelTooltip`，不得提前拼成单列；玩家态 workbench 禁止浏览器原生 `title` 与富注释竞争，精确信息使用可见文案、`aria-label` 或共享 tooltip。配件候选的“档级 / 用途 / 定位 / 状态”树与面包屑复用 `ItemFilter.FilterNavigator`，但由 tuning host CSS variables 与 scoped active state 呈现 DLS 晶体索引风格，不分叉共享筛选逻辑；分类只消费 `EquipmentTuningService.modCandidates[]` 的展示投影；点击已安装配件只进入替换选择，`replace_mod {candidateKey,replaceCandidateKey}` 必须由 AS2 在一次 preview/commit 中原子完成旧件及其直接依赖返还、新件扣除和最终配置写入，另保留显式单拆/全拆与每个已安装件的专用单拆按钮。顶栏提供本地持久化的“配件｜安全 / 快速”：安全模式是默认值，所有操作停在权威预览；快速模式仍先取 AS2 preview/token，只允许材料 delta 精确匹配且 `removedMods` 无连带项的单件安装、单件替换、单件卸下自动提交。任何依赖级联、额外材料返还、no-op、卸下全部以及强化/交换/进阶都必须停在预览，模式切换不得增加 wire 字段或绕过 `beginExternalWrite`。commit 的 `_busy` 与 write capability 必须覆盖同步回包后的 inventory refresh 整段；刷新 settle 前不得接受换装备或发起新 snapshot，释放后只能基于新 lease 继续。紧凑密度只作用候选目录，严格复用 owned grid 的 `48px` 格、`40px` 图标、`4px` 间距和持有数量角标，最低 1024×576 画布下 25 个候选必须无需滚屏全部可达，预览/材料/提交决策区保持固定信息量。整个工作台使用 DLS 青/深蓝/黑铁语言，插件档级、危险动作等语义色仍保持独立；强化栏目只允许一个强化石动态能量核心，紧凑和 reduced-motion 使用静态首帧；当前升阶与已安装插件使用真实物品图标，不退化为纯文字状态。`?` 位于 workbench 顶栏，与技能/商店的帮助层级一致，通过共享 modal 解释强化度、交换、进阶、配件筛选、直接替换、安全/快速边界及“选择只预览、确认后提交”，开闭不得产生业务消息。自动门至少固定 fresh `EquipmentTuningServiceTest 39/39`、`InventoryPanelServiceTest 92/92`、三视口调制 harness `68/68`、共享 KShop/工作台回归 `85/85`，以及 `asLoader.swf` 刷新与 Compiler Errors `0/0`。

workbench 的 `close` 与调制业务 envelope 使用同一实例边界：Host 必须校验严格四字段 `{type,panel,cmd,panelInstanceId}`，且请求 `panelInstanceId` 精确等于当前活动 workbench 实例后，才能撤销调制 session、发送 `webPanelUnpause` 或关闭 PanelHost。旧实例迟到的 close、缺实例和额外字段一律拒绝，禁止拿 Host 当前实例替客户端补盖章。

KShop `bulkQuery.catalog[]` 与 NPC shop `snapshot.catalog[]` 的自动分类投影固定包含 `majorType/use/actionType/weaponType`：它们分别来自物品现有 `type/use/actiontype/weapontype`，Web 只据此建立 `大类 → use → 武器子类` 的互斥浏览树，不读取 XML 文件名、不复制物品定义。KShop 另保留 JSON entry 的 `type` 作为策划专柜名；NPC 人工 `layout.sections` 作为同等的策划专柜来源。两者都以“类别 / 专柜”两个一级入口并存，专柜不得覆盖或伪装成自动物品大类。NPC 未配置 sections 时只呈现自动类别；未知自动字段只能进入“其他”，不得过滤掉商品。以上展示投影不参与价格、购买落点、可售性或提交复核。

NPC 商店主页面只维护待购/待售意图，不直接改存档；二级结算页把 `{catalogIndex,quantity}` 与 lease-bound sale source 交给 `tradePreview`。精确出售使用 `scope=slot + quantity`；同名批售只允许背包 seed lease + `scope=same_name,policy=plain_only`，物品名、匹配范围、合格实例与强化/进阶/带插件保护数量由 AS2 扫描，Web/Host 不接受客户端 itemName 或价格。AS2 必须在批售展开后再按真实 `entry.identity` 全局去重，禁止同名批售与逐格出售重复结算同一槽；多个售出装备返还的同名插件必须先聚合数量再交给 `ItemUtil.acquire`。不可堆叠装备复数采购在 AS2 计划中展开为多个 `{name,value:1}` 独立实例，禁止把数量塞进单件装备的强化值；预览逐行返回 `purchaseLimit/maxAffordable/maxByCapacity/maxPurchasable`，整单返回 `requiredSlots/availableSlots/missingSlots`。价格、口才折扣、情报门槛、可售性、买入真实落点、容量与最终金钱变化全部由 AS2 重算。预览返回 opaque `tradeToken`、权威明细、买卖总额、预计余额与阻塞原因；`tradeCommit` 在同一次事务中复核余额、商品、引用、普通装备保护条件、槽位、数量和价格，允许所选售款抵扣购买，也允许售出腾出的背包格被同笔购买使用。令牌单次消费，提交失败不得留下部分出售；内部 inventory/ref 不得进入 wire。旧 `buy/sell/batchPreview/batchSell` 只保留 Flash 兼容入口，其中 legacy `buy` 装备仍限单次 1 件；新 Web 不调用。`NpcShopTask` 与 Web 均采用 `idle/write_pending/needs_reconcile`：超时、断线、发送失败、未知结果或畸形写回包后只准新发结构完整的 snapshot 对账，绝不自动重放 `tradeCommit`。Host 将畸形回包规范化为 `error=malformed_response, requiresReconcile=true`，旧 snapshot 回包不得解除仍在途的写门。

`inventory_full` 时结算页可进入嵌入式“背包—战备箱”整理子路由，但不得给 `npcshop` 新造库存写协议：它必须复用 `domain=inventory` 的 `InventoryCoordinator`、slot lease、`autoTransfer(mergeThenEmpty)` 与战备箱剧情可访问容量。返回结算前分别刷新 NPC collection 状态与 inventory 背包窗口，再以 inventory 背包 + NPC material 组合视图按真实槽位/名称重绑仍存在的待售意图并重新 `tradePreview`；已移动且无法安全重绑的精确待售项必须移除并提示。采购意图以稳定 `catalogIndex` 保留。首轮不支持直接购买到战备箱。

`_root.UI系统` 是跨帧共享服务命名空间。任何后置 UI 初始化都必须使用 `_root.UI系统 = _root.UI系统 || {}` 或只补具体成员，禁止 `_root.UI系统 = {}` 整对象重置；否则会静默抹除早期注册的 Panel 服务，表现为 Host/Web 面板已打开但 snapshot 永不回包。迁移新增早期服务时，TestLoader 必须按实际 include/帧顺序加入“后置初始化后引用仍相同”的回归断言。

snapshot 请求的 `filterKey=all|weapon|armor|consumable|material|other` 由 C# 严格枚举后交给 AS2；带 `filterSpec` 时 Host 与 AS2 都必须校验映射一致（`collection → other`，其余 major 与 `filterKey` 同名），禁止接受“回显武器路径但实际走 all 分支”这类矛盾请求。AS2 必须扫描容器权威范围再分页，返回匹配项 `viewCapacity`、真实 `physicalSlot` 与 slot lease，禁止 Web 只筛当前页。背包、仓库和战备箱共用权威树筛选与权威整理组件；目录与背包的 Web 交互统一为行内单层 drilldown，武器不得截断 `use → actionType/weaponType` 第三级。纯 Web `displaySort` 已退役，未筛选窗口保持 `physicalSlot` 顺序，真实重排仍只经上述写闭环。`filterFacets/filterItemCount` 缓存以 `ArrayInventory` 实例引用、容器单调 `mutationRevision` 与 `accessibleCapacity` 做 O(1) 命中校验；`add/remove/addValue/setItems` 与三个 transaction 写入口成功后必须推进版本，失败写入不推进，禁止退回每次 snapshot 全前缀逐槽引用扫描。inventory-domain 仍主动删除受影响缓存，确保拾取、购买、出售与跨容器移动后不会返回陈旧分类。战备箱 snapshot 同时返回物理 `capacity=400` 与剧情权威 `accessibleCapacity=0..240`、`pageSizeHint=40`；Web 分页与筛选只允许使用可访问前缀，`sortAndMerge` 也只重写该前缀并逐槽保留 240..399 锁定区。旧 Flash `计算战备箱总页数` 调用同一 AS2 权威函数，禁止在 JS/C# 复制主线、挑战或基建解锁公式。

`autoTransfer` 不接受目标槽位：Web 只提交 lease-bound `source`、`targetContainerId`、固定策略 `mergeThenEmpty` 与用于回显/重铸 lease 的当前 `windows`。AS2 在目标完整可访问范围内先找同名数字堆叠、再找首个空槽；目标已满时保持来源与 dirty 状态不变，绝不自动交换异类物品。`windows` 不能影响实际落位，也不能把仓库强制跳到真实目标页。宿舍 `warehouse` profile 首批开放 Ctrl+单击与“快速存入/快速取出”常驻模式；Web 队列最多 24 项并严格单飞，未发送项可再次点击取消，超时、断线、stale 或不确定提交必须停队并对账，不重放未知写入。

世界内入口统一调用 AS2 `openInventoryWorkbench({profile,source})`，发送 `panel_request panel=workbench initData.profile`；C# `LauncherCommandRouter` 再做一次 `warehouse|battlebox` 白名单并重建固定 runtime initData。XFL 不得直接传 `containerId`、容量或任意 `initData`。宿舍入口在 Launcher 不可用或发送失败时才回退旧 Flash 仓库 MovieClip；真实仓库不得重新暴露给商城或通用 HUD。

检查点：

- Web `cmd` 必须进入 `WebOverlayForm.HandlePanelMessage` 的 case 列表。
- C# Task 的 action 字符串必须与 AS2 `gameCommand` 分发一致。
- AS2 `task` 回包名必须与 `TaskRegistry` 注册名一致。
- C# 回包必须恢复 Web 原始 `callId`，不能把 Flash 内部 `fid` 泄漏给 JS。
- JS callback 必须在成功、失败、关闭时清理 pending / busy 状态。

战宠与佣兵迁移暴露过两类典型断链：Web cmd 没进 `HandlePanelMessage` 导致静默丢弃；AS2 委托其他 service 后回包 task 名不匹配导致 tooltip / 写操作永远收不到响应。新增 panel 时优先防这两类问题。

### 2.1 地图资源箱 S0 分层接线检查点（2026-07-18）

[地图资源箱 S0 ADR](../docs/地图资源箱-S0无奖励编排-ADR-2026-07-17.md) 当前只批准无真实奖励的开发切片。AS2 中央箱候选裁决、`ChestSessionService`、独立 socket bridge 与生产 callback，Host `DevLockboxS0Runtime` / tracked PanelHost queue，以及 production overlay 中默认休眠的 Web bootstrap / actual-wire 均已接入源码；中央 arbiter 随 AS2 发布会对六类箱全局生效，不属于“默认断开”。S0 实验 flow 仍由两道默认关闭的开发门保护：`data/stages` 没有 exact `chestS0FixtureId + chestS0As2GateId` marker，Host 同时要求开发仓库与 `CF7_DEV_LOCKBOX_S0 === "1"`。这表示 actual-dev-wire **源码已接并随本轮正式闭包部署，但双门休眠、玩家不可达**；不能再写成“Host/Web 未接运行态”，也不能把 dormant code 反向写成 S0 actual-feature 生产闭环。

已接 wire 必须继续守住以下边界：Host 先预留并跟踪 `flowHandle/requestToken/panelInstanceId` 后才排队；begin 在同一临界区原子完成 capability consume、attempt reserve 与 active identity 发布，navigation pending 时 begin 与 execute gate 都 fail-closed；`resumeActive=true` reconnect capability 只保留既有 authority 收敛，禁止被 begin 消费。tracked S0 open 必须先成功取得真实全局 pause：WebOverlay `AssertWebPanelPause` 返回实际 bool，PanelHost `requireTrackedDelivery` 在 `CaptureBackdrop / ResumeForPanel / TryPostToWeb` 任何视觉 / Web 副作用之前 fail-closed，返回 `false` 或抛异常都不得报告 `OpenPosted`。请求还要通过受信 AS2 socket origin、精确 source `as2-chest-s0`、fixture `insurance-safe-s0-v1` 和环境门二次校验；Web document epoch 与 exact bind ack 后才承认 active；result 写未知不重发。Host 立即直发 AS2 causal query，并由 state-driven reconcile tick 在 `ReconcileRequired` 重试，不依赖 Web `result_query` 是否成功投递；`ResultApplied / KnownTerminal` 会重放缓存的 terminal authority projection，直到 Web 得到同一权威投影。每个 reconcile tick 必须登记 in-flight，并在每个副作用前复核 exact identity、reconcile generation 与非 release；`TryRelease` 遇 in-flight > 0 延后，tick `finally` 归零后再 release，旧 tick 不得跨 fresh-arm identity；timer 的 exact identity / generation 复核与 publish 也必须在同一 Runtime lock 内原子化，旧 attempt 的迟到 publish 不得覆盖 fresh identity timer。`KnownTerminal` 的 `releaseTrackedPause` callback 首次返回 `false` 或抛异常时保留 terminal flow并由定时 reconcile 重试，不得 reset 或 fresh arm；仅 callback 成功后才发送 `pause_release` 并 fresh arm。generic unpause 的状态检查与 generation-bound socket write 在同一 Runtime lock 上同 begin 线性化；发送失败保留 pending，reconnect / Web ready 必须先成功补发 unpause，随后才准 fresh-arm。PanelHost 的 tracked reservation 或 tracked lease 任一存在时，同一 queue lock 必须拒绝所有 generic open / close，异常关闭只走 exact identity。Web `close_ack` 丢失时 Host 发 exact `close_query`，native PanelHost exact-close 首次失败则由同一 reconcile tick 独立重试；Web 对已经 teardown 的同一 identity 重发关闭证明而不重开 DOM。`NavigationStarting` 先同步清除 WebOverlay readiness，再在 Runtime lock 内捕获 active；没有 active 时立即使旧 idle arm 失效。成功加载的新文档保持 not-ready 直到其真实 `ready`；失败或 same-document/no-new-content 才恢复旧 readiness 并 fresh rearm；document teardown 只有在相同非零 `NavigationId` 已观察到 `ContentLoading` 且 `NavigationCompleted` 成功时成立，错 id、失败或未加载的新文档都不是关闭证明。普通 bootstrap 的 `resumeActive=false` 负责把 begin-in-flight orphan 收敛为 known-no-write。Web DOM teardown 与 native PanelHost close 是两份独立证明，只有再加 AS2 terminal 后才能释放全局 `webpanel` pause；navigation 在 result 前撤销且零写、result 后只查询且零重放，panel-busy begin 只在 PanelHost 回到 idle 后用全新 capability 重臂。现有普通 Lockbox / `LOCKBOX_TEST` 保持不变；实验流不新增地图资源箱专用生产 AS2 `panel_request` / Host business route / task 白名单，也不复用 `minigame_session` 承载 chest 身份或结果。

S0 的补充并发门同样属于已冻结 wire：disconnect generation 进入单调 high-water，disconnect-before-Ready 或高于 live 的先行 disconnect 都永久拒绝该代迟到 Ready，并使旧 binding/retry/native panel 失效；`wire_loading` 是 LazyLoader 单 owner 的 transient rejection，旧 LOADING owner 继续完成，fresh arm 不触发第二次 load。pending generic unpause 必须在任何已有 arm binding 的早返回前补发，补发成功前 begin 的最终提交拒绝但不消费 Ready capability。bind timeout 之后迟到的原始 bind ack 不能从 `OPEN_BIND_UNKNOWN` 恢复，只有 exact bind query 可以。`OpenPosted` completion 还要复核 connection generation、document epoch、navigation 与游戏进程；失鲜时不启动普通 bind timer，改走 unknown/旧进程 `EXPIRED` recovery 与 exact native close。所有 timer 使用 exact owner/version；外部副作用在 Runtime lock 内线性化或登记 outbound action，Dispose 禁止新 outbound 并等待其他线程在途动作。pause release 必须追到 callback 中采用的更新 generation，bootstrap ack 最终提交重验 connection/process/pause-role。普通 `minigame_session` 仍无业务权限；Lockbox 信封即使迟到到 pause 释放之后也先由 sanitizer 消费，畸形信封只记固定 drop code，原始 payload 不落日志。

AS2 与 Web 的 fail-closed/隐私门继续追加：已识别箱的中央 arbiter 注册失败必须整体回滚，绝不退回逐 target legacy 全局监听（A03F）；已消费 bootstrap 在 suspend 后重观察 marker 不得 re-ack 或收束 authority，只有 fresh Host bootstrap 可恢复（S08）；ordered identity adoption 仅在 `_flow == null` 时允许，已有 flow 下同 session/epoch 但不同 `flowHandle/panelInstanceId` 的 ApplyResult/OpenFailed 必须被消费但零状态、kill、ack，原 exact identity 仍可完成（S09）；迟到 begin success 只 exact-match 已收养 flow，异 identity 丢弃、同 identity 幂等不重复 terminal，old openFrameSpy 同 target 重入新 session 后抛错不得污染新 authority（S10/A20）。production `onClose/onForceClose` cleanup 即使抛错也必须先完成 exact close/teardown proof，证据只记固定 code、不泄异常文本（AW26/AW27）；任何含 S0 identity 的 panel open 日志把整个 `initData` 替换为 `[redacted]`，包括嵌套 browser-host-shim identity（AW28/AW29）。专属 source/fixture 任一锚点或完整九字段 `OPEN_KEYS` shape 进入 reserved；普通真实 PanelHost partial 与非专属 8/9 字段碰撞在 `ARMED/IDLE` 直通，reserved 后 exact validator fail closed。非 `ARMED` 的 reserved `onOpen` 只能安排本地视觉关闭 microtask；该任务以单调 open/rebind sequence 与 element token 防陈旧，并仅在 token 最新、`!current` 且仍为同一 active Lockbox 时关闭。cleanup 抛错仍清空 active、只记固定分类，不得伪造 close/teardown proof、改变 authority 或 consume；ordinary rebind 取消旧 cleanup 并恢复 DOM，reserved rebind 不得关闭 ordinary active。rearm 先完整验证再原子替换，坏新 arm 不得破坏旧 arm（AW30/AW31）。

S0 历史检查点仍明确保留：stage audit **41/41**、真实 XML **28 declarations / 27 nodes / 26 identities**、Host Runtime + Coordinator **84/84**、目标竞态/flake **25/25**、Web adapter **20/20**、actual-wire **31/31**、跨栈 verifier **61/61**，以及 runId `b3b1544a05c5426eb6999706326fa9ff` 的 Arbiter **13/13**、service **13/13**、Socket Bridge **10/10**、P **4/4**、F **4/4**。本轮已精确移除 `摇滚公园.xml` 的 4 个 `TEMP` 验收夹具并重新取得 stage audit **41/41**；当前文件为 **27,345 bytes** / SHA-256 `C184AD15F1EAE24B31EF9BD552890F95153431C3FFEA80A0CC0760682AB990D5` / Git blob `43018f3b5886bc89b1881c7bb04801d4bd45f5fb`，审计仍为 **28 declarations / 27 nodes / 26 identities**、Rock Park **active 1 / commented 8**、rollout **1**，map wiring **243/243**。当前 source-tree 另通过 S0 static wiring **454/454**、Launcher/Host clean full **1220/1220**，AS2 BOM **227/227**。当前 publish-only `scripts/asLoader.swf` 为 **1,041,903 bytes** / SHA-256 `AD799970A8A2AFD0F9A402C704934F08985A3144FA608A7564E17BC4899C815E` / Git blob `3dd59f73f9fc71128da99c2eb03796290df1e010`，Compiler Errors **0/0**。B643/FA1 只保留为本轮 promotion 前的历史正式 runtime；FCA19/B2AF 隔离 candidate 是 organizer 落地前的历史证据。精确隔离 candidate `tmp/runtime-candidates/v2/c-2a0cddb077b7-08846e81b3-20260721t100014612z-f32a40a3` 在候选阶段达到 S1/S2 单 canary 切片的 `e2e_verified / NOT_DEPLOYED`；随后同一 `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107` / `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C` 身份已正式 promotion 并完成该 canary 的标准入口复核；Runtime Lane C **11/11 个入口 exit 0**（10 个 scalar 套件合计 **408**；guardrails 另报 `scripts=3 / unsafeCandidateCases=3`） 仍只证明守门回归，且该实机链不是 S0 actual-feature 证据。S0 exact fixture、真实 XFL 与 actual-feature cross-stack 仍缺，Browser 证据保持 `actualCrossStack:false / productionHost:false`。

停顿取得的首要因果证明在 AS2：`ChestS0SocketBridge` 必须在发送 begin 前的同一调用栈同步调用 `webPanelPause`，并验证 `_webPanelPauseLease` 已实际存在；exact begin payload 必须包含 `pauseAcquired:true`，Host 对缺失或 `false` fail-closed。Runtime 在 tracked enqueue 前的 generation-bound socket pause 写，以及 PanelHost 在 UI 执行前的幂等 `AssertWebPanelPause` 都只是冗余检查，不能替代 AS2 lease 证明；任一 Host 检查失败仍须精确取消、发送 `openFailed`，并在 native / Web 视觉副作用前终止且不得报告 `OpenPosted`。

### 2.2 地图资源箱 S1/S2 单-canary `loot` 闭环（2026-07-19；2026-07-22 正式验证更新）

项目维护者已批准 `APPROVED_S1_S2_CANARY_SOURCE_SLICE`：只允许 `夺取材料.xml | SubStage 5 | Instance 0` 的一处 `unlockPolicy=skip` rollout，S3 Lockbox、其余箱型、旧 UI 删除与发布豁免均不在范围。当前 AS2 `LootContainerService`、Host `LootPanelCoordinator/LootTask`、Web `loot-runtime/state/view/panel/organizer` 与 production lazy registry 已接源码。fresh CS6 TestLoader runId `dbcc28a3d99444c38bde38029ff4bd61` 已取得 Service **159/159** + Planner **7/7** = **166/166**、failed **0**、Compiler Errors **0/0**，AS BOM **227/227**；随后真正 publish-only 刷新的 `scripts/asLoader.swf` 为 **1,041,903 bytes** / SHA-256 `AD799970A8A2AFD0F9A402C704934F08985A3144FA608A7564E17BC4899C815E` / Git blob `3dd59f73f9fc71128da99c2eb03796290df1e010`；mtime **2026-07-21 17:12:59 +08**；17:13:03 的 `compiler_errors/compile_output` 为 **0 错误 / 0 警告**、`[compile] done`。publish 不产行为 trace，不能替代该 fresh TestLoader run。`c-fca19ba526c4-08846e81b3-20260721t060547571z-978633c6` 及其 build identity `FCA19BA526C4120B240B594FDD29786261A318F805A0ACD8001D48A842B60F24`、payload closure `B2AF3BEFCBA055FC68F3D49A9A450B6D946F20DD5A8E28FEAF0EC8B32BFAC4CD`、Core SHA `231388D757201454655E95876834155E17ED118476C0B5806A96E2A0A6492780` 是 organizer / attempt-bound agent 标题帧门落地前的历史 `candidate_executed / NOT_DEPLOYED`。随后构建的隔离 candidate `tmp/runtime-candidates/v2/c-2a0cddb077b7-08846e81b3-20260721t100014612z-f32a40a3`（native build identity `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107`、payload closure `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C`、Core SHA-256 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`）已精确启动并载入专用槽 `cf7_agent_loot_target_full_v1`。attempt `62f04fa249c44d94ba3171f619e61754` 严格取得 start 后 fresh handoff 与真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`，watchdog **0**，随后唯一一次 `_root.agentEnterResolvedSave()` 产生同包 `s:1|ga:<exact attempt>`，Host exact receipt 后 status 为 `readyForRuntimeAutomation=true`、`blockers=[]` 且 `saveRuntime` exact loaded；人类确认 NativeHud 由正常标题帧唤起、可见且指令有效。随后满背包混合箱在同一 `panelInstanceId=panel.loot.8a1227b8229f4eef99ac052395e4e12b` 完成“抗生素合并 / 黑暗吉他保留→organizer→真实确认丢弃牛肉罐头 ×16（50→49）→fresh ACTIVE 返回且零 close/rebind→领取黑暗吉他→terminal close/unpause 回游戏”。同一 candidate 又在 **18:37:08** 首开另一非空箱，**18:37:18** 单次普通 close 回包后 PanelHost 关闭（`instanceDigest=83e7e242b7fc`、`reason=suspended_already_closed`），**18:37:19** `generic_unpause=true`；**18:37:21** 同锚点重开取得 fresh snapshot，人类目视强化石 **×2 + ×3** 内容一致且未出现旧 AS2 UI；**18:37:29** 两次 claim 后一次 terminal close（`instanceDigest=6ef2f7f9fcb2`、`reason=terminal_already_closed`）并再次 `generic_unpause=true`。因此该隔离 candidate 当时使单 canary 资源箱切片达到 `e2e_verified / NOT_DEPLOYED`；候选随后优雅 shutdown，Guardian PID **14820** 与 HTTP/XMLSocket **1192/1924** 均退出，Flash CS6 PID **20444** 保留。候选退出后，immutable Git-tree request `FBA91942C57DC3E6662AB77AC88EEAE3CA2AFA3C82BF5FFEA6BC68CFD6C31AE4` 已对 release tree `e1e6e059f148a640b3e37cbf1d912f297156d956` 形成 `cf7-runtime-release-consensus.v2`；同一 build/closure 于 `2026-07-21T16:39:47.2329893Z` 完成 production promotion，promotion commit 为 `6218f8b1d82efc57b77131616667fe45f3033297`。随后在 `C:\cf7-standard-entry-20260722\resources` 由无参标准入口启动，外层与 Core 自检均为 `manifest verification OK files=23`，实际 Core SHA-256 仍为 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`。槽位 `cf7_agent_loot_standard_entry_v3`、attempt `4eae1360cedd413fa3175db6a8997158` 取得 fresh handoff、真实 title marker（watchdog **0**）、唯一 helper 与 exact-attempt receipt，状态达到 runtime ready；仅测试 direct opener 随后进入 production task **20038** 做领域 smoke（stage-select 不含该任务，正常玩家路径仍是宝石线人 NPC/通缉令），真实 loot 完成 snapshot、两次 claim、terminal close、PanelHost idle、unpause 与人工存盘。最终 `强化石=209498`、较基线净增 **35**，存档 SHA-256 `CCDF9BFDD71E03CDD205090F958C187587E5C332BDAC327BC754B0CC9AB0DA6B` 且二次复核稳定。因此**获批的单 S1/S2 canary 切片**现为 `standard_entry_verified`，可以称该范围已正式部署；完整 S1/S2 资产、S0 exact fixture/全局 arbiter 人工门仍未完成，不能称整体迁移完成或 S0 已验收。历史 attempt `b9bb7f9a800f479cba04542820fa2748` 与冷启动 `7560a368fdb64dc5b7e2d2e19377add7` 只继续作为旧交互的经济写/持久化证据。冻结细节见 [S1/S2 ADR](../docs/地图资源箱-S1S2真实战利品容器与Web双栏-ADR-2026-07-18.md)。

本轮还修复了真实输入才会暴露的共享 modal 惰性层缺陷：`SecondaryPage` 曾把共享 `.workbench-modal-layer` 一并纳入 underlay，导致确认层自身处于 `inert + aria-hidden`；旧 harness 的程序化 `.click()` 绕过 inert，形成假绿。现在 `secondaryUnderlay()` 排除 modal layer，modal `FocusScope` 只 inert shell root 的其他直接子节点；自动门更新为 loot state **46/46**、browser **62/62**、lazy **6/6**、focus integration **12/12**、Launcher full **1220/1220**。当前 candidate 的 25-file native bundle 不含 `launcher/web`，运行时从当前 `projectRoot/launcher/web` 读取外部 Web，故 native build identity / closure / Core 不能绑定这次 Web 修复。当次真人 E2E 运行副本另绑定下列换行敏感 raw-byte SHA-256；这些值只绑定 2026-07-21 实机使用的原 dirty 工作树字节，不应当作任意 checkout 的当前 raw hash：`workbench-components.js` `D3D9A5A4CCBE1303259ECD0FCEDABB5C7CE79E9562287473EC895A3FE75B65A4`、`workbench.js` `E6AB04C4EF4045C955E9009BE27F29D99679743D29A88DDDDEEBC6A1B141D7D1`、`loot-panel.js` `A1DEECD08BEE63CB5CAF6C226D2B326BE5ADE2C399F88F29AD2953D0AAD29E10`、`loot-organizer.js` `F85A43609B4C0194F6469C15510A0CD7C051CFC56ADFE0353B6D0EDB35C05905`、`loot-view.js` `B323D52DBE7C75BD5F32FEA6BF9CC420396E1C7A42CB3F5B21611E292EFA910B`、`launcher/web/modules/loot/dev/harness.html` `F6252EF9B549F08719AB0DE22FC8E3AA32F490E536C24E84E8D4FDCE5595E859`、focus integration test `6490DCAFD46A694F4C76AC10C61281CCE8162D6A6D87124CF260FBE2269A33C7`。 换行可移植性复核：七个文件均无 lone CR；逐字节执行 `CRLF→LF` 后，原真人运行工作树、当前短路径发布工作树与 HEAD Git blob 完全一致。规范化 SHA-256 / Git blob OID 分别为：`workbench-components.js` `B8FC6A1CB17C55F41DEF72F15085598C69ECC4F2A11C7058127477135DD8966E` / `dd1ad88c1b08bf06ecadf84e2d31d16ccb339ff7`；`workbench.js` `5459DDEE021674924A9A0767F1459AC20224269790AAD396C9BF8E302127EC9E` / `24eb9ea68bc40f1813503481da3c53ba6287062e`；`loot-panel.js` `59590D3B997EFB6B51A546783459658D70F042FF6FD430450E26A767DF64A10A` / `e66a7540fbfb2ace8411e4141a53ba3bf01e70eb`；`loot-organizer.js` `F85A43609B4C0194F6469C15510A0CD7C051CFC56ADFE0353B6D0EDB35C05905` / `d240c85e20f0fe78974f1f8bc04c5508841fbdf3`；`loot-view.js` `6A7A5259DC2D128283FEFF331DA93DA15A44FB939C79614052549ECD963FAC2D` / `cf317a30307d6f3ea584ce03e3df993296e367f8`；`launcher/web/modules/loot/dev/harness.html` `4ABE66096090FA1E63141ED592A4005476D26A1CC0EED5CC59BBBBCC2B7258AE` / `c7cf63f705cbe71d33748c18c847fe9c4c78c558`；`tools/test-workbench-focus-integration.js` `B8CF3CB0CC7636683197A7D3CB7201FC5FF9825C9B95BF54B2477EBE233C5B74` / `2752796df5bad9d36f099715ecabc3658c8e5f4a`。这证明历史真人 E2E 使用的源码与 HEAD 具有相同的 Git 规范化文本身份，但不证明任意新 checkout 的 raw bytes；正式 promotion 与 standard-entry 由上一段的 immutable request/consensus、实际正式 Core 路径和同身份 smoke 独立证明，不从换行规范化结果推导。

打开入口严格为 AS2 socket callback wrapper `{task:'panel_request',payload:{panel:'loot',source:'map_chest',initData},callId}`，而不是旧 fire-and-forget 的顶层 `{task,panel,source,initData}`；`TaskRegistry` 只抽取内层 payload，再由 loot coordinator 对 `{panel,source,initData}` 做 exact-shape 校验。AS2 `initData` 恰为八键 `{v,chestSessionId,lootContainerId,containerEpoch,openAttemptSeq,displayName,capacity,columns}`。Host 验证正整数 `openAttemptSeq` 并在 `OpenRequest/Binding` 保留 attempt identity；投 Web 时剥离它并加入 `panelInstanceId`，因此 Web initData 仍恰为 `{v,chestSessionId,lootContainerId,containerEpoch,displayName,capacity,columns,panelInstanceId}` 八键，Web 业务 11 键不变。物品、数量、概率、掉落规则和经济指令不得进入 open payload。

Web→Host 公共 11 键固定为 `{type,task,domain,panel,v,cmd,callId,panelInstanceId,chestSessionId,lootContainerId,containerEpoch}`，其中 `type=task`、`task=loot_request`、`domain=panel=loot`。Host 只在当前 exact binding 下接受，并按下表重建发往 AS2 的 action：

| Web cmd | AS2 action | 允许的额外键 | 写状态 |
|---|---|---|---|
| `snapshot` | `lootSnapshot` | `loot:{offset,limit}`、`backpack:{offset,limit}` | 读 |
| `tooltip` | `lootTooltip` | `expectedAuthorityRevision`、`source` | 读 |
| `claim` | `lootClaim` | `expectedAuthorityRevision`、`operationId`、`direction=loot_to_player`、`source`、`targetContainerId=背包` | 单向写 |
| `close` | `lootClose` | `expectedAuthorityRevision`、`operationId`、`closeLease`、`abandon` | 终态写 |
| `query` | `lootQuery` | 无 | 只读对账 |

普通 Web `query` 经 Host 重建后，Host→AS2 wire 必须严格为七键 `{task:'cmd',action:'lootQuery',callId,v,chestSessionId,lootContainerId,containerEpoch}`；Web 不能加入 attempt 或 proof 字段。`source` 恰为 `{containerId,slot,expectedLease,expectedContainerVersion}`，且 containerId 必须是当前 loot container；不支持背包→loot、swap、任意目标槽或 Web 自造容器。Flash `loot_response` 严格 15 键 `{task,callId,success,error,chestSessionId,lootContainerId,containerEpoch,authorityRevision,lastAppliedOperationId,state,remainingCount,closeLease,snapshots,tooltip,terminal}`；Host 校验后增加 / 重建 `{type=panel_resp,domain=loot,panel=loot,cmd,panelInstanceId}`，形成 Web 收到的严格 20 键信封，禁止额外 `v/source`。状态只允许 `LOOT_COMMIT_PENDING / LOOT_ACTIVE / LOOT_SUSPENDED / CONSUMED / ABANDONED / EXPIRED`；`LOOT_SUSPENDED` 非终态、`terminal=null`、旧 closeLease 失效，只有 same-scene exact target-anchor reopen 才重铸 same triple/inventory 的 fresh closeLease/panelInstanceId；active 的 snapshot/query/claim 成功投影必须同时含 loot 与 backpack snapshot，终态只带 tombstone、空 `snapshots` 与空 `closeLease`。

ordinary `target_full / inventory_full` 不再关闭 loot 去借道 AS2 HUD，而是在同一 tracked `loot` panel 内打开嵌入式 organizer。该子路由的 inventory 请求顶层必须恰为七键 `{type,domain,panel,cmd,callId,panelInstanceId,payload}`，固定 `type=panel`、`domain=inventory`、`panel=loot`，只允许 `snapshot/autoTransfer/discard`。payload 只允许背包与战备箱的 exact 全筛选 windows；`autoTransfer` 只能在两者之间以 `mergeThenEmpty` 转移，`discard` 只接受背包 source 并必须在 Web 二次确认后发送。Host 只在 `LootPanelCoordinator.IsBoundVisualExact(panelInstanceId)` 于同一锁内同时证明 state=`Bound`、active binding 与 PanelHost exact instance 后转给 `InventoryTask`，回包必须回显 `panel=loot` 与 exact `panelInstanceId`；缺键、多键、旧实例或 `OpenPosted` 均以 `panel_instance_expired` fail closed。

Host→AS2 的视觉恢复控制严格为扁平八键 `{task:'cmd',action:'lootPanelRecovery',chestSessionId,lootContainerId,containerEpoch,openAttemptSeq,recoveryNonce,reason}`。`recoveryNonce` 是 Host 生成并只在 Host/AS2 recovery 链内流转的 opaque 因果值；`reason` 只允许 `web_mount_failed | web_open_failed`。两者都不得进入 Web initData、Web request 或业务 response。该命令只由 Host 已接受的 visual binding 发出；AS2 在三元 identity 与当前 `openAttemptSeq` exact 命中时可先登记 nonce。若 AS2 尚未观察到 accepted callback，只返回 `recovery_pending`，不得提前推进 transport；callback 到达后才继续同一 proof。旧 attempt、零/坏 attempt、stale、terminal、畸形、未知 reason 或额外键均零副作用。reopen 发出前的 attempt-bound opening pending 不是 transport detach：pre-accept 拒绝、同步发送失败或异步打开失败撤销 pending 并恢复 `LOOT_SUSPENDED`；只有 accepted 后的 exact-attempt 故障才允许 ForceDetach。

detached reconcile 使用 Host 内部严格九键 proof query：普通七键 `lootQuery` 再加入 `{openAttemptSeq,recoveryNonce}`。该信封不由 Web 发起、结果不投回已销毁 Web，且没有扩展 AS2 15 键 response 或 Host→Web 20 键 projection。Host 只允许创建该 exact attempt/nonce 的 pending proof entry，并且只有该 entry 收到通过完整 sanitizer 的 `success=true` 权威投影后才可 settle detached flow；`success=false` 即使看似携带 terminal 也不能冒充恢复成功。opening reservation、claim `pendingCommit` 与 transport detach 仍是不可混淆的 `LOOT_COMMIT_PENDING`；普通七键 query 不能推进已登记 nonce 的 detached recovery。物化 journal 在随机前冻结规则 identity、`逆向` bonus 与 exact PRD engine，并拒绝大于 `2^31-1` 的数量跨度。只有未物化且不可恢复的 pre-commit failure，或不存在 transport flag 且可安全收束的 scene cleanup，才可进入 `EXPIRED`。

正常关闭复用 close v1。空箱优先进入 `CONSUMED`；**loot 主页**的非空 X/Esc/backdrop 发送 `abandon=false`，必须先形成 `LOOT_SUSPENDED` 再关闭 visual binding、释放 exact pause 并回游戏。只有独立“放弃剩余”及其二次确认才发送 `abandon=true` 并进入 `ABANDONED`。claim 直接成功必须精确证明 `authorityRevision +1`、`remainingCount -1`、本次 `lastAppliedOperationId` 与 requested slot empty；close 直接成功必须精确证明 revision `+1`、本次 operation，以及与 close 意图一致的 expected state / remaining。容量失败只有严格 raw failure shape、exact current binding 与完整 known prestate 同时成立，且已知 revision、remaining、lastAppliedOperationId、`closeLease`、`containerVersion`、requested slot 与 slot lease 全部不变时才是零写证明；错误名本身不是证明。AS2 raw failure 不签发 close capability，Host 只在这组 exact prestate 下保留已知 `closeLease/containerVersion`。Host/Web 各有独立 unknown-freshness watermark；只有 matching pending call/identity 的回包可用未证明的更高 revision（包括随后 sanitizer 失败的结构畸形回包）推进该 unknown operation 的水位，且不覆盖 known authority；其他 call/identity 不得抬高水位，后续 claim/close/query proof 不得回退。普通七键 query 不增加 `reconcileAfterCallId` 等 wire 字段；因果性由请求时序、exact pending identity 与独立 watermark 共同证明。unknown claim 只由精确因果 `+1/-1/operation/slot-empty` 或 exact noncausal no-write 证明；unknown close 的 ACTIVE 也只允许 exact noncausal no-write，SUSPENDED/terminal 必须满足因果前滚。ordinary item 的 `target_full / inventory_full` 只打开同实例 organizer；此时 `LOOT_ACTIVE`、Bound 与 pause 均不变，不发 `lootClose`、不切 `workbench`、不调 `WAREHOUSE`。X/Esc/backdrop 在 organizer 子页内优先返回领取主页；只有 inventory ready、无 busy、无 `refreshRequired` 后取得 fresh `ACTIVE` loot snapshot 才回主页，失败留页且不 replay 任何写。collection cap 不映射 organizer；write unknown 只 query、绝不重放 claim/close。

初次 open 与 reopen 的 transport failure 必须分流。只有初次 open 已物化同一 inventory 后的 accepted transport/mount/socket 故障，才可在 exact journal/effects、same-object renderer 与 pause-release proofs 全部完成后回 `LOOT_ACTIVE`。这个 legacy renderer 是 **claim-only recovery view**：容器标记 `__lootClaimOnly`，源/目标两侧都禁止 drag、swap、discard、玩家→loot 与特殊资产直写；每次图标点击必须调用 `LootContainerService.claimLegacyRecoverySlot`，继续复用正常 claim journal/lease/dirty/terminal 语义。renderer 未确认不得开放领取，空 recovery 的完成仍须 causal query/effect settle，不能靠旧 observer 双向同步。reopen 的 pre-accept、同步、异步或 accepted 后故障都只回 `LOOT_SUSPENDED`/terminal，**绝不显示旧 AS2 UI**；inventory 空则 `CONSUMED`，anchor 失效则 `EXPIRED`。

场景切换与 `cleanupForRestart` 使用 Boolean teardown barrier：`SceneManager.removeGameWorld/dispose/reset` 和根 `_root.清除游戏世界组件()` 必须在任何 collision/dispatcher/world/timeline 销毁前先调用 `LootContainerService.expireScene`。若仍为 commit/effect/detach pending，返回 `false`、完整保留场景并停止淡出；根层以单飞标志只排一个下一帧重试，成功后才恢复淡出和 teardown。禁止先销毁 world 再补写 `EXPIRED`。

ForceDetach 只用于 accepted visual binding 的故障路径，不发 `lootClose`、不猜终态，也不能替代 ordinary suspend。Host 先冻结 exact binding，再发严格八键 `lootPanelRecovery`，随后仅由同 generation 的严格九键 proof query 收敛；普通业务 query 与 generic unpause 都不能越过该 fence。fresh panel admission 还必须先取得 `LootTask → LootPanelCoordinator` 的 admission lease：旧 binding 处于 write-unknown、detached recovery、native close 或 pause-release 未决时，新 `panel_request` 以 `flow_busy` fail-closed，不能在检查与安装之间被 socket detach 穿插。suspend close 的 native close 或 pause release 未完成时，Coordinator 保持 exact binding 于 `PauseReleasePending`；只有该 coordinator-owned binding 可定向重试，不能发送不带 owner 的 generic unpause，也不能提前接受新 panel。

socket 生命周期按 generation 严格排序：replacement 先为新连接保留更高 generation，再发布旧 generation 的 disconnect，最后发布新 generation ready；旧 frame 必须同时命中 generation/client/stream，且每代 disconnect 至多一次。上层把 replacement disconnect 视为过渡并等待新 ready，只有同代自然 EOF/force-close 才走真实断线恢复；旧 generation 不得再 PostToWeb、释放 pause 或关闭 replacement。terminal 与 ForceDetach exact native close 遇 enqueue false、completion false/丢失均以有上限的指数退避自主重试；strict terminal 先到后 ForceDetach 保持 `TerminalCloseQueued`、不得降级或 recovery，ForceDetach 先到后 strict terminal可升级。旧 timer/completion 不得跨 fresh identity。

AS2 为已完成 attempt 保留有界 recovery proof ledger。只有已接纳的更新 attempt callback、exact recovery command 或 exact proof query 能删除严格小于该 attempt 的历史项；迟到旧 query 不得清理同代或更新 proof。容量不足且无法安全剪枝时必须以 `recovery_history_full` fail-closed，禁止盲目 LRU 后继续 open/close。pending lazy-load 取消与 mount/registry/required-assets 失败必须用 exact 五键 `{type:'panel',cmd:'close',panel:'loot',reason,panelInstanceId}` 通知 Host，不能静默清 `_pendingOpen`；初始 registry 缺失与 required-assets 后 panel 缺失都用 Host 已允许的 `mount_failed`。原始 XmlSocket 日志不得序列化 loot 身份或奖励：`loot_response` 整包脱敏；`panel_request` 必须先从真实 `payload.panel` 识别 loot，并兼容旧顶层 `panel`，随后只输出固定 `task/panel/payload=redacted/len`。普通非 loot panel、非 `panel_request` 的 loot-shaped payload 与其他 JSON 保持原诊断格式，避免扩大脱敏分类器而遮蔽无关故障；`XmlSocketLogRedactionTests` **10/10** 固定 nested/兼容 callback wrapper 的正向脱敏与非 loot 反向边界。busy 写入时 X 不能用原生 `disabled` 吞掉点击：保持实际可点，以 `aria-disabled/aria-busy` 表意，并由 requestClose 单飞门反馈且不追加第二次 close。loot 占用 PanelHost 时，Host 必须拒绝任何 `panel!=loot` 的 foreign `close`，禁止 organizer 或迟到的其他面板清理误关 loot/误放 pause。应用重激活以 `GuardianForm.WM_ACTIVATEAPP(true)` 为权威入口；initial/app-reactivated 共用 generation + single-flight + **200ms** 去抖路径，外部前台不抢焦，`MoveFocus` 前必须再次确认 exact overlay/child，且只在成功后 commit debounce。

本轮 source-tree 实测门为 map wiring **243/243**、stage audit **41/41**、S0 wiring **454/454**、Host 相关定向 **108/108**、AgentControl **29/29**、Launcher/Host clean full **1220/1220**、Host focus 定向 **9/9**、共享 focus integration **12/12**、XmlSocket loot 日志脱敏 **10/10**、Web loot **46/46 + 62/62 + 6/6**、workbench audit **0/0** / atlas **48/48** / item-grid **14/14**、存档工具 multi-instance **44/44**。新增门固定同实例 organizer、严格七键 inventory、`IsBoundVisualExact`、foreign-close 隔离、库存 settled 后 fresh ACTIVE snapshot、失败留页/零 replay、子页 X/Esc/backdrop 返回与背包 discard 二次确认，并新增“modal 不得存在 inert ancestor、modal 持有焦点、organizer underlay inert”的真实层级回归。fresh CS6 runId `dbcc28a3d99444c38bde38029ff4bd61` 为 Service **159/159** + Planner **7/7** = **166/166**、failed **0**、Compiler Errors **0/0**，AS BOM **227/227**；publish-only `asLoader.swf` 为 **1,041,903 bytes** / SHA-256 `AD799970A8A2AFD0F9A402C704934F08985A3144FA608A7564E17BC4899C815E` / Git blob `3dd59f73f9fc71128da99c2eb03796290df1e010`。Rock Park 4 个 `TEMP` 夹具已移除，当前审计为 **28/27/26**、Rock Park **active 1 / commented 8**、rollout **1**。历史 `c-fca19…978633c6` 只达到过旧闭包的 `candidate_executed / NOT_DEPLOYED`；`c-2a0cddb0…f32a40a3` 在隔离候选阶段达到单 canary 资源箱切片的 `e2e_verified / NOT_DEPLOYED`，精确验证 corrected Agent entry、NativeHud 正常入口、organizer 主链与普通主页 X→挂起→同箱内容不变重开→最终领取。其同一 build identity / payload closure 随后经 request `FBA91942…AE4` 正式 promotion，并在槽位 `cf7_agent_loot_standard_entry_v3` / attempt `4eae1360…7158` 完成同身份标准入口与真实 loot smoke，故获批单 canary 当前为 `standard_entry_verified`。

close v1、嵌入式 organizer、严格 proof 与焦点恢复已由上述自动门守住，`prepare-loot-target-full-save` 为 **44/44**。历史 attempt `b9bb7f9a800f479cba04542820fa2748` 已真人实证混合 claim-all、first-class suspend/reopen 与最终 consume。11:34:06 首次存盘 JSON/SOL SHA-256 为 `6D5A13300B95EB52500589BE8CDC15765A892E027090004C44BC97BA37203A9E` / `34787E3C9D92FCBBD88C5FD97D261BDCDF33CEB51752D57DA5A5DC2CFF02F05C`；随后冷启动 attempt `7560a368fdb64dc5b7e2d2e19377add7` 已从 SOL 读回抗生素 **361**、强化石 **209468**、黑暗吉他背包 slot **21 / level 1** 与冰魄神斩战备箱 slot **15 / level 13**。12:11:08 再存盘 JSON/SOL SHA-256 为 `CA9DEDF2999B84272E3BFAF5608382CD095F6E47AA8098B5BB6A516B95CE4BBD` / `B670DD4AEB7B42597110410FD332E00886AD278F6CAFD54774DE182F448ECFCB`，备份在 `C:\tmp\cf7-loot-restart-readback-20260721-121108`。该历史链不能外推为嵌入式 organizer 真人验收。

当前真人业务证据已覆盖 attempt `62f04…1754` 的正常 NativeHud 入口、同实例 organizer、真实一次点击 modal、discard、fresh ACTIVE 返回、继续领取与 terminal close/unpause 主链，以及普通主页单次 X→`LOOT_SUSPENDED`→同锚点内容不变重开→最终领取；历史 `b9bb…2748` 与冷启动 `7560…add7` 仍只负责旧流程经济写 / 跨进程持久化旁证。`c-2a0cddb0…f32a40a3` 的隔离候选阶段保持 **e2e_verified / NOT_DEPLOYED** 历史，候选已优雅退出且 Flash CS6 保留；同一 `2A0CD…A107` / `3B837…150C` 身份现已完成 production promotion，并从正式 `runtime/` 标准入口通过 attempt-bound 受控进档、两次真实 claim、terminal close/unpause 与稳定存盘，故获批单 canary 当前为 **standard_entry_verified / 正式部署**。地图临时夹具也已恢复并以 stage **41/41**、map **243/243** 复验；完整 S1/S2 资产与 S0 exact fixture/全局 arbiter 人工门仍独立保留，不能外推为整体迁移或 S0 actual-feature 验收。

补充冻结门：claim 的成功 operation journal 写入后，dirty 读回验证、loot lease cache 与 destination cache 失效属于分段幂等 mandatory effects。全部完成前 authority 保持 `LOOT_COMMIT_PENDING`；新 claim/close、snapshot/tooltip、panel/legacy recovery 与 scene terminal 均不得旁路，只有同 operation 或被 exact attempt/nonce 授权的 causal query 可恢复。初次 open transport detach 才按「exact journal → mandatory effects → same-object legacy renderer proof → exact pause-release proof」回 ACTIVE；reopen transport detach 复用前两项后回 SUSPENDED/terminal，禁止 renderer。Host 连接中 mount/navigation recovery 与 socket detach 共用该收敛机；内部 generation-bound 九键 proof query 必须先收束 in-flight claim，旧 generation 不得再 PostToWeb 或提前释放 pause。

## 3. C# 接入清单

新增生产 panel 的 C# 最小接入面：

- `launcher/src/Tasks/*Task.cs`：实现双层 `callId` 桥接、timeout、`ClearPending()`、`Dispose()`。
- `launcher/src/Program.cs`：创建 Task，注入 `WebOverlayForm`，传入 `TaskRegistry.RegisterAll`。
- `launcher/src/Bus/TaskRegistry.cs`：注册 AS2 response task，例如 `xxx_response`。
- `launcher/src/Guardian/WebOverlayForm.cs`：
  - Task 字段（如 `_petTask`）与 `SetXTask()` 注入方法。
  - `HandlePanelMessage` 覆盖所有 Web cmd。
  - `OnSocketDisconnected()` 里补一行 `if (_xTask != null) _xTask.ClearPending();`，与既有各 Task 的清理逐项对齐（断线时清 pending，防止旧回包错配新会话）。
  - `ResolvePanelCloseGameCommand()` 明确 close 是否通知 Flash。
- `launcher/CRAZYFLASHER7MercenaryEmpire.csproj`：当前 SDK-style 会自动包含 `.cs`，但迁移时仍要确认构建清单没有旧式残留假设。
- `launcher/tests/Tasks/*TaskTests.cs`：至少覆盖断连错误、cmd→action、Flash 回包重写、unsupported cmd。

禁止只新增 JS 和 AS2 service 而漏 C# 分发层。C# build 通过也不代表协议能到达 AS2，必须有 Task 级测试或游戏内验证。

## 4. AS2 接入清单

AS2 侧修改必须遵守：

- 新增 / 重建 `.as` 必须 UTF-8 with BOM；优先复制现有 `.as` 改名保留 BOM。
- 新增 boot 期 `.as` 入口：asLoader.xml 已塌成单帧 `#include _collapsed_frame.as`（见 [docs/asLoader-README.md](../docs/asLoader-README.md)）→ 不再直接改时间轴；同步入口加进对应 staged 帧 manifest 后 `node tools/assemble-collapsed-frame.js` regen，异步入口归 BootSequencer；被引用的 class 自动嵌入无需手动 include。
- response task 名必须唯一，并与 C# `TaskRegistry` 一致。
- 修改 AS2 后必须说明 `scripts/asLoader.swf` 是否已重编。
- 没有 fresh trace、Output Panel 副本或 IDE 复核时，不能说“Flash 编译通过”。
- 写存档、金钱、K点、背包、伙伴、宠物、任务状态后，必须对齐当前 save dirty / autosave 机制，不能只改内存对象。

AS2 smoke 的成功边界按 [testing-guide.md](testing-guide.md) 与 [FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md)。`publish_done.marker` 只能证明 JSFL 触发结束，不能单独作为成功依据。

## 5. Web Panel 接入清单

生产 Web panel 至少满足：

双栏工作台的 layout profile、密度、排版、颜色、状态、动效、命中区、焦点、生命周期、组件边界和 visual atlas 统一见 [workbench-ui-system.md](workbench-ui-system.md)。本文只保留跨 AS2 / Host 的权威与迁移闭环，不复制前端系统全文。

- 正式模块位于 `launcher/web/modules/`，不是只在 `dev/`。
- `Panels.register(id, ...)` 或懒注册表 `panels-lazy-registry.js` 已接入。
- `onOpen` 初始化 session、pending、busy、runtime snapshot。
- `onClose` 清理 pending、busy、timer、tooltip、hover、DOM 订阅。
- close 按钮、ESC、backdrop click 必须最终触发同一套本地 close 清理，再通知 C#。
- 任何 async callback 返回时要校验 session，避免旧面板回包污染新会话。
- 用户可输入文本进入 `innerHTML` 前必须 escape；优先用 `textContent`。
- 运行态 WebView2 是游戏 UI renderer，不是文档浏览器：Overlay 统一加载 `css/game-ui-behavior.css` + `modules/game-ui-behavior.js`，默认抑制文本选取、原生 `dragstart` 拖影与 `contextmenu`；真实编辑器只通过 `input/textarea/contenteditable/[data-browser-native]` 显式放行。不要在各 panel 重复绑一套互相冲突的 `selectstart` handler。
- 固定 1024×576 设计画布走 `.panel-scale-shell + PanelScale` 时，生产 CSS 必须为对应 `data-panel` 声明 `#panel-content { inset:0 }`；否则会静默继承通用 `4% 6%` 卡片内缩，在任何分辨率下都浪费一圈可用空间。dev harness 不得用全局 `#panel-content{inset:0}` 遮掉这项生产约束。
- **颜色必须走 token，禁止新增硬编码 DLS/θ-域/技能/调制色值**：canonical 色表见 `docs/dls-color-system.md`；新面板只能使用 `--dls-*`、`--theta-*`、`--wb-semantic-*` 及 skin 覆盖的 `--wb-accent-*`，不得在 `panels.css` 中再写 `#4ec9f0`/`#3dd5ff` 等一次性色值。
- runtime 文本必须考虑 1024×576、1366×768、1920×1080 视口，按钮文本不能溢出。

使用资源时，必须有 fallback：图标、头像、背景 missing 时不能让 panel 空白或 JS 抛异常。`Panels.init()` 会预热共享图标 manifest，`Panels.open()` 把该加载尝试作为所有生产 Panel 的 required-assets 门，完成前不进入 `create/onOpen`；新迁移面板不得再假设玩家先开过商城，也不应各自复制“先 `Icons.load()` 再发业务快照”的竞态代码。manifest 失败时 `Icons` 以空 map 完成并让面板走缺图 fallback，不永久锁死 Overlay。普通物品图标若只需要 URL 用 `Icons.resolve()` 首帧静态显示，列表/格子里的可动画图标用 `Icons.html()` / `applyIconToImage()` 交给共享模块播放，只有 manifest 显式声明 `playback` / `animated` 的图标才会按时间线切帧。

迁移 Flash MovieClip 素材时，manifest 不能只记录“静图 / 多帧图”二分。必须保留时间线语义：父 sprite 首帧纯 `stop();` 时父级停在第一帧；若第一帧内有自播放子 MovieClip，子层仍应独立播放，不能把整件素材误折叠为普通静图，也不能按子层周期最小公倍数预合成全量大序列。图标素材先用 `tools/bake-icons-offline.py --animation-structure-audit-only --ffdec-timeout-seconds 120` 审 `animationStructureCandidates` / `animationStructureParentStopNested` / `animationStructureUnsupported` / `spriteGraphErrors[].error=swf_xml_timeout`；`--ffdec-timeout-seconds` 作用于每个 FFDec 子进程，PNG/SVG/XML2SWF 超时按对应 export error 的 `exitCode=124` 审。生产推广用 `--animation-candidates-only --animation-candidate-report tmp/icon-animation-structure-audit.json` 复用结构审计候选，并可配 `--animated-candidate-max-source-frames` 在 PNG 导出前跳过超长周期候选；每轮仍应按 `--name` 分批审首帧 oracle 与体积，批量推进走 `tools/promote-icon-animation-candidates.py` 汇总 `animated|visual-static|budget-static|unsupported-static|timeout`。父级纯 `stop();` 的图标应写 `playback=static-first-frame` 并移除 `f2` 运行时引用，不能让 FFDec 导出的后续变形帧变成循环动画。图标素材若父首帧、stripped base 全透明且只有一个自播放子 MovieClip，可写成 `playback=nested-animation` 的全画布 `frames[]/timelineFrames[]`，第 1 帧复用原父级首帧以守住既有偏移；若父第 1 帧直接挂一个或多个可动子层且层深度不与静态 base 交错，写 `nestedAnimation.strategy=direct-layered-icon-canvas`，运行时用 `Icons.html()` 生成 base+layers wrapper 并按层独立播放。direct-layered 图标导出时应烘焙 PlaceObject 上可支持的滤镜，并用父首帧 oracle 做小范围自动 `offset` 校准；layer frame 可按透明包围盒裁剪，使用 `cropX/cropY/cropWidth/cropHeight/canvasWidth/canvasHeight` 在 Web 侧放回原 256 画布位置；`filters` / `offset` / crop 字段都是导出审计与还原元数据，不是手工 offset 表，也不要求 Web 运行时实现 Flash 滤镜。复杂嵌套只进 `nestedIconCanvasUnsupported` / `nestedIconLayeredUnsupported`。图标动图进生产目录前可用 `--max-animated-icon-bytes` 设置单图标体积门槛；超预算条目必须记录 `animatedIconBudgetSkipped` 并回退静态首帧；多帧候选若视觉上只有同一 `uri + crop`，必须记录 `animatedVisualStaticDowngraded` 并回退静态首帧，避免无意义运行时 tick。纸娃娃素材以 `nestedAnimation.autoPlayingDescendants`、`playback=static-parent-nested-animation|nested-animation`、重复帧 `duplicateOfFrame` 作为当前契约；能直接分层的 child MovieClip 进一步写 `nestedAnimation.layers[]`，包含 stripped base 之外的子层帧、矩阵与 `drawOrder`。连续重复显示帧应保留为播放时长而不是重复实体帧：`frames[]` 可作为完整逻辑帧/审计明细，运行时优先读取 `timelineFrames[]` 与 `durationFrames`。图标与纸娃娃运行时都必须通过 `web/modules/asset-timeline.js` 解释这些字段；`icons.js` / `dressup-doll-renderer.js` 只保留各自的 DOM、URL、Canvas、matrix/origin 逻辑，不能再分叉实现播放时间线。导出端的 digest 去重、`duplicateOfFrame` 与连续 hold 压缩同样必须走 `tools/asset_timeline_export.py`；图标可按 `uri` 合并，layered 图标判断是否动起来必须把 `cropX/cropY/cropWidth/cropHeight/canvasWidth/canvasHeight` 纳入 identity，纸娃娃必须把尺寸和注册点纳入 identity key。`python tools/test-nested-animation-stop-semantics.py` 是父级首帧 `stop();` 只冻结父时间线、第一帧内未停止子 MovieClip 仍播放的固定回归。

## 6. Close 与旧 Flash UI 副作用

默认规则：Web panel close 不应触发旧 Flash UI 重排。尤其不要在 close、hire success、save success 这类回调里调用旧 UI 的：

- `gotoAndStop`
- `attachMovie`
- `排列*图标`
- 大量 MovieClip rebuild
- 旧 SWF 面板 refresh 函数

这类调用可能干扰 PanelHost 的 backdrop 移除、HUD resume、InputShield 清理和焦点恢复。确实需要 Flash cleanup 时，必须写清：

- 为什么纯 Web cleanup 不够。
- 发送哪个 `*PanelClose` gameCommand。
- AS2 handler 是否 no-op 或只清理状态。
- 验证项：关闭后再次打开、鼠标可点击、键盘焦点恢复、Flash 前台恢复。

经验规则：像 `kshop` 这类会暂停 / 恢复 Flash 状态的面板可以有 open/close gameCommand；像 `arena`、`team` 这类纯 Web 展示 / 操作面板，close 默认不通知 Flash。`arena` 的定制赛 `custom_result` 结算页是例外：Flash 背后已停在竞技场战斗场景，关闭结算页必须由 Web close 携带 `returnBase:true`，Host 下发 `arenaReturnBase` 并让 AS2 调 `_root.返回基地()`，不能只隐藏 Web panel。`team` 内宠物子视图尤其不能在 close 时调用 `petPanelClose`，该旧命令会重建 Flash 战宠图标。

## 7. 数据权威与转录

禁止裸手工转录以下数据：

- 金币、K点、倍率、消耗公式。
- 存档字段路径。
- XML / AS2 表里的宠物、佣兵、任务、关卡、物品定义。
- unlock 条件、主线进度门槛、等级门槛。

如果必须迁移到 JS / JSON，必须同轮给出：

1. 源文件路径与字段名。
2. 生成脚本、审计脚本或逐项对照记录。
3. 差异处理规则：哪些是故意改写，哪些必须与源一致。
4. 运行时 fallback：源数据缺失时显示什么，是否禁用写操作。

静态 JS 数据只能作为展示缓存或分类辅助；写操作必须由 AS2 权威路径重新校验价格、权限、槽位和状态。Web 端禁用按钮只是 UX，不是安全校验。

## 8. 验证门槛

迁移任务最小验证按改动面叠加：

Launcher 状态统一为 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`。`launcher/build.ps1` 只到 `candidate_built`；候选运行与领域 E2E 必须绑定实际 Core 路径、build identity、payload closure。只有同一身份完成 promotion，并从 `automation/start.ps1` / 根 bootstrap 标准入口复核，才可称“已部署 / 正式验收”。

| 改动面 | 必跑 |
|--------|------|
| C# Task / router / PanelHost | `launcher/tests/run_tests.ps1` + `launcher/build.ps1`；随后启动返回的精确 candidate、记录身份并跑受影响领域 E2E。需要正式验收时再走 promotion + 标准入口复核 |
| Web module / CSS / harness | 对应 browser harness 或静态 QA；没有入口时先补入口 |
| AS2 service / include / gameCommand | `scripts/compile_test.ps1` fresh trace，或说明 IDE 人工复核状态 |
| 写存档 / 金钱 / K点 / 背包 / 伙伴 / 宠物 | 游戏内端到端手测 + 回读存档状态 |
| 文档入口、协议、验证入口变化 | `node tools/validate-doc-governance.js` |

地图资源箱 S0 的聚焦 xUnit、Node adapter / actual-wire、dev Browser 与 fresh TestLoader 都是分层证据：`W04N/W05N` 只作协议预检；browser-host-shim 虽可计 W04/W05，却没有真实 PanelHost、WebView2 或 Flash socket。历史 S0 runId 与旧同机 diagnostic candidate 只保留为分层/工具链证据，均不是 feature E2E。FCA19/B2AF 隔离 candidate 曾达到 `candidate_executed / NOT_DEPLOYED`，但既未启用 S0 exact fixture / 双门，也早于当前 organizer 与 attempt-bound agent 标题帧门，不能据此把 `actualCrossStack` 改为 `true`。源码可以在部署闭包不变时以 `source-ahead` 进入 main；只有从最终 immutable tree 重建候选并产生同进程 Flash socket→Host tracked PanelHost→WebView2→AS2 的 exact feature 脱敏事件证据，再由人类复核 XFL timeline / 游戏输入后，才可把 `actualCrossStack` 从 `false` 改为 `true`。正式 request、policy receipt、签名 quorum、strict release verification 与 promotion 仍是独立发布门。

无人值守入口遵循“受控直达 + 真实入口小门”双轨：

- 受控直达只可绕过旧 Flash 按钮查找；它必须从窄化 `agent_control` 动作进入正式 AS2 opener，再经 `panel_request`、Host 白名单、PanelHost 与领域 Task。不得直接开 Host/Web panel，也不得用 `/console` 调业务读写。迁移功能进入人工反馈期后，不得继续保留仅供测试环境切换的独立 feature flag/capability 分支；但旧 AS2 入口可以按正式 `source` 语义有意保持服务化原生 renderer，而 Web 反馈面仅由另一个正常工作台入口进入。该隔离不是调试开关：两条路径必须共用领域服务，Host 在未放行切流前应 fail-closed 拒绝残留 legacy redirect；人工验收门通过后再单独裁决是否把旧入口切到 Web。
- 动作必须绑定专用 `cf7_agent_*` 克隆槽、当前 attempt/save runtime ack 与本轮新鲜 handoff；live slot、旧 attempt 或未 ready 均应零发送。受控进档顺序固定为：记录本次 `start` 日志水位 → 在该水位后同时取得 fresh handoff 与真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`（watchdog 事件不计，缺失报 `title_frame_not_observed`）→ 仅调用一次 `agentEnterResolvedSave()` → helper fail-closed 调 `_root.notifyGameEntered()`，同包发送 attempt-bound `s:1|ga:<_bootstrapAttemptId>`，再以 `gotoAndStop` 进入“读盘”帧 → Host 排除 legacy 无 `ga` 包、将 receipt exact 绑定当前 attempt，且只有该 receipt 才设 `gameEnteredObserved=true` → runtime ready。每次 `start` 与后续 `s:0` 都重新加锁；裸 `s:1`、helper 已调用、watchdog 或 `revealPerformed` 均非成功证据。
- 直达 runner 可以只负责正式 opener、active instance 与首个权威 snapshot 的只读入口门；若它声明会继续执行 preview/commit/reconcile/存盘/重启回读，则必须显式列出写入 fixture、命令和回读证据，不能从 snapshot 推导业务写闭环。旧 AS2 入口、Web 正常入口和 fallback 各保留限时专项。入口搜索超过 60–90 秒或两次截图即停止并记缺陷，不让导航失败吞掉整轮验证时间。
- `agent_control` 的“已请求打开”不是业务成功；runner 至少等待 start 水位后的 fresh handoff 与真实 title-frame marker、随后单次 helper 的 exact-attempt game-enter receipt、runtime ready、Host active panel instance 及该实例首个领域 snapshot，才可继续。

结束汇报必须区分：

- 已跑 C# build。
- Launcher 当前状态、实际 Core 路径、build identity / payload closure；未到 `standard_entry_verified` 时明确写“未部署 / 未正式验收”。
- 已跑 xUnit。
- 已跑 Web harness / Node QA。
- 已拿到 Flash fresh trace。
- 已做游戏内端到端手测。
- 未验证项与风险。

不要用“跑通了”“应该没问题”替代具体证据。

## 9. 文档同步

触发以下任一变化时，同轮更新文档：

- 新 panel id、目录、入口、懒注册依赖。
- Web cmd / C# action / AS2 response task 变化。
- close 语义变化。
- dev harness 升级为生产 panel，或生产 panel 降级 / 废弃。
- 新增验证入口或改变必跑命令。
- 数据 source of truth 改变。

更新位置：

- `launcher/README.md`：目录树、Panel System 摘要、运行态边界。
- `agentsDoc/testing-guide.md`：验证矩阵入口。
- 本文：迁移规则变化。
- 具体施工记录 / 设计文档：一次性过程、取舍、踩坑复盘。

入口文档只写摘要和链接，不复制本文清单。

## 10. Agent 收尾格式

迁移任务结束时，用固定格式报告：

```text
迁移级别：静态原型 / Web panel 原型 / 协议接入 / 生产可用
协议闭环：列出已覆盖 cmd，说明 Web→C#→AS2→C#→Web 是否完整
写状态：列出会改存档/金钱/K点/背包/伙伴/宠物/任务的路径
验证：build / xUnit / harness / Flash fresh trace / 游戏内手测
Launcher 状态：compiled / candidate_built / candidate_executed / e2e_verified / promoted / standard_entry_verified；实际 Core 路径与身份
未验证：明确列出
文档：已更新的 canonical doc 与巡检结果
```

如果缺 Flash fresh trace 或游戏内手测，必须显式说“未做”，不能用 C# build 或 Web harness 替代。
