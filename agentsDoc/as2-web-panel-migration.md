# AS2 UI 到 Web Panel 迁移护栏

**文档角色**：AS2 UI 迁移到 Launcher Web Panel 的专题 canonical doc。
**最后核对代码基线**：commit `c4faf14460238c7ea3e85983f31dee8be1b79afa`（2026-07-28）的角色构筑 ↔ Skills 双向导航、原生 workbench nonce 与失败回滚已由 immutable tag `runtime-build-v2/20260728-character-build-skills-bidirectional-v1`、request `BBCC17C7E46AC852BA0F1D12AA9434188C7775BEA8F593C13B13710783183548` 和 promotion commit `45b9748baa68786a52557239d5bd7c52869970f7` 完成双 signer / 双 faultDomain v2 发布；无参正式入口绑定 build identity `4E5EEE4AB5BE0CC8D084254C54F23AC4D6269C11CFED987409EA6BBE171CE191`、payload closure `7460D8D4FC4416EDBDDFE7577403CBA7233ECC347BDF2D605BC5D2252AF39507` 与 Core SHA-256 `16DF387268E8052A0B66B2F49DD8645DB38C37EB23430D4AC0CB46527A3B9BA0`，并完成双向 GUI 与普通关闭负链，严格状态为 `standard_entry_verified`。Skill、合成、双栏工作台与 runtime v2 的细分门以对应专题 canonical doc 为准。

本文用于所有“旧 Flash / AS2 UI 迁移到 Launcher WebView2 panel”的任务。它不是普通前端开发指南，而是跨 AS2、C# 总线、Web panel、Flash CS6 编译链的稳定性护栏。凡迁移旧 UI、替换运行态入口、扩展 panel 协议、把 dev harness 推向生产，都必须先读本文。

涉及“UI 全迁后是否把存档/背包/经济持久权威转入 Launcher”、肉鸽同进程角色热切换或战术携行集时，先读 [AS2 → Launcher 持久状态权威与战术携行集长期演进调研](../docs/AS2-Launcher持久状态权威与战术携行集-长期演进调研-2026-07-23.md)。[P0-F 跨层迁移基座与架构收敛专项](../docs/P0-跨层迁移基座与架构收敛专项-2026-07-23.md)只作为本轮 `panel-contracts.v2`、窄 `PanelPendingCallTracker` 与 Hairdresser 第三个真实消费者的具名决策与冻结证据，不再承担当前暂停或执行路由。长期路线仍是候选储备，不得据此绕过现有 AS2 权威与验证门；未来持久状态/经济写 Panel 必须按真实领域逐项登记、裁决和验证，不授权批量迁移、持久权威转移或自动重启 P0-F。

专题规划与施工记录：[技能系统-Web面板独立迁移-工程落地规划-2026-07-15.md](../docs/技能系统-Web面板独立迁移-工程落地规划-2026-07-15.md) 已落地 `panel/domain=skills`、管理/教师双模式、学习 token 原子提交和快捷栏模型抽离；我的技能主入口归 NativeHud / fallback Notch 的独立 `SKILLS`，NPC 教师保留情境入口，旧物品栏技能页不迁成 Web 转发器。Skill 使用 same-panel rebind + 顶层 `panelInstanceId`、`reconcileId/reconcileAfterCallId` 显式未知写对账、active/candidate/return trainer capability 撤销、正确 escaping JSON encoder，以及观察期旧 UI writer 领域 bridge；这些差异不得照抄 Crafting 的普通 snapshot/generation 恢复。教师页提供 Host 盖章的 `switch_manage`；只有该路径派生的 manage 实例得到 `canReturnTrainer=true` 并可发 `switch_trainer`，trainer session 始终留在 Host、learnToken 不跨 view。Web 展示层复用 `GridDensityController`、`FilterNavigator` 的按钮/计数/键盘 primitive、`PointerDragController/InteractionBroker` 与 `PanelTooltip.convertAS2Html`，manage 采用全宽技能库 + 1—12 单排技能带；紧凑态与物品 owned grid 共用 `48px` 格、`40px` 图标和 `4px` 间距，完整卡共用 `68px` 高度节奏，但不复用物品 taxonomy/facets/lease。技能→快捷槽保持 equip 确认，快捷槽→快捷槽以单条 `moveSlot` 在空槽间移动或对占用槽交换，技能→技能格直接调用既有 reorder 交换；常驻上移/下移退役，快捷槽 `Alt+←/→` 与技能格 `Alt+↑/↓` 保留非指针兜底。已装备目标、普通模式已装备源及异常行在排序落点阶段拒绝；EasyMode 只放宽已装备源。Skill 不再照搬物品目录树：形态、配置/学习、流派三组直接 facet 始终同时可见，首击即生效、跨组可组合并支持一键清除；武术、科技等流派按真实 `Type` 投影。名称搜索默认收起；manage 不显示 metric，trainer 只保留等级/技能点，稳定同步/刷新/协议术语退出常态视觉层。异常态才显示玩家语言的重试/确认结果与诊断复制，复制内容保留实例/revision/callId/reconcile 但禁止输出 trainer session/learnToken。S0–S5 代码与自动门、四个实际 Flash 目标发布及 FFDec 静态证据已接入；NativeHud `SKILLS` 的真实 Win32 manage 点击已覆盖常规、生产最小、4:3 与 1920×1080 几何，真实 `The Girl → 学习技能` 已打开 `技能研习` 并渲染 `兴奋剂 / 能量盾`，此前 trainer→manage same-panel rebind 也已通过；新布局/往返尚只有自动几何证据。旧技能页的两个 live 图标实例以互斥 child-depth 指纹确认实际命中 main `DefineSprite 53`，不是 things id2706；S4C 现只缺 legacy fallback 事务等价/重启回读，S5 现只缺 legacy Notch/fallback、pending-write/断线真机 Gate，S6 观察/旧 UI 删除仍按专题规划保持未完成。

Skill 最新展示收口又视觉隐藏通用 L/R slot marker，但不删除 slot/ARIA/焦点语义；顶栏 `?` 以同一 Web 模态按 manage/trainer 投影不同操作说明，帮助开闭不触发 AS2/Host 消息也不清理筛选或选择。三组 direct facet 与真实流派映射加入后，manage 以两行承载三组筛选；物品/技能共享尺寸 token、技能格交换拖拽、排序拒绝落点和 `Alt+↑/↓` 均已接入。完整/紧凑现在明确只控制技能库，Hotbar 固定为居中的 `12×64px` 方槽、`48px` 图标与 `3px` 间距，使用连续底板；选中态保留等级，卸载 `×` 仅在悬停/聚焦时与等级切换。管理态顶栏在“技能库 完整/紧凑”旁以等宽、中性外框的“快捷栏 安全/快速”独立分组常显本机确认偏好，完整“快捷栏操作确认”语义保留在 aria-label，帮助模态只解释规则而不再承载设置入口：安全模式空槽直装而替换/卸载确认，快速模式三者直写，但两种模式都不能绕过技能学习确认；偏好不进入存档或 wire。物品格视觉矩阵仍为 `10/10`。内置交互浏览器仍无实例，故该变化只有自动 DOM/几何证据。

Skill 页切换把 `Bridge.send` 严格定义为本地 transport 投递结果：只有显式 `false` 才显示连接失败，`true` 不冒充 Host 业务受理；等待新实例 rebind 期间按钮锁定，超时恢复原 NPC 页重试，教师能力仍由 Host/AS2 裁决。

2026-07-16 教师能力过期语义从“创建后固定 120 秒”收敛为“连续 120 秒无成功教师域请求”：每次通过 NPC/场景/目录签名复验的 snapshot、preview 或 commit 都刷新 `lastTouchedAt`，但只有明确 NPC 教师入口可以签发能力，close/rebind/断线仍立即撤销，NPC、场景或目录变化仍立即失效。Web 选技能、调目标等级后以 debounce + latest-wins 自动预览，常态“计算消耗”按钮退役；右侧决策栏常驻技能说明、目标等级、权威消耗、研习后余额和门槛原因，主动作固定为“研习至 Lv.X · N 点”。30 秒 learnToken 在进入确认前按 25 秒前端新鲜度门静默重取，最终学习确认不取消。`trainer_session_expired` 不再自动关闭面板，而保留目录与最后快照并显示“返回游戏重新对话”的终态说明，避免视觉上等同闪退。目标等级现使用整数吸附的离散横向 range：可直接点中间刻度、拖动或输入精确等级，原生方向键/Home/End 语义保留，`− / +` 只做微调，冗余“升 1 级”退役而“升至满级”保留。拖动/输入阶段只更新本地目标并保留上一份权威消耗，松开或确认后立即请求最终等级；等待态明确标注旧结果，CTA 在新预览匹配前保持禁用。对应 Edge 三视口门为 `126/126`，fresh Flash Output Panel 为 `SkillPanelServiceTest 45/45`。

2026-07-26 教师页把已学技能的本地可选上限收敛为 `min(MaxLevel, currentLevel + floor(skillPoints / UpgradeSP))`；例如 Lv.1、每级 30 SP、持有 160 SP 时只允许选到 Lv.6。滑条、数字框、刻度、`+` 与快捷目标共用这一上限；未达元数据满级但 SP 不足一级时显示明确的不可升级状态且不发送注定失败的 preview，`UpgradeSP=0` 仍允许到元数据上限，未学技能继续固定只预览 Lv.1。切换到不可升级技能会同步取消上一技能尚未触发的 debounce 并使其迟到回包失效，避免跨技能复用目标等级。AS2 preview/commit 的费用重算与 `insufficient_sp` 权威校验保持不变。快捷按钮仅在确实可到元数据上限时显示“升至满级”，否则显示“升至可负担最高级”。对应纯策略门为 `Skills UI modules 47/47`，Edge 三视口门为 `132/132`。

2026-07-16 快捷槽互拖的首次真机失败表明 Host 运行时产物也是协议闭环的一部分：日志若停在 Web `moveSlot` 已路由、但没有 `skillMoveSlot` Flash dispatch/response，应先核对游戏实际加载的 `runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll`，不能仅凭源码和 xUnit 判断协议已部署。凡修改 C# 命令白名单或映射，`launcher/build.ps1` 只会生成隔离 candidate；开发联调必须启动当前 tree、由脚本返回的精确 Core，并记录实际进程路径、build identity 与 payload closure，不得复用合并前 candidate 或把单个 Core 覆盖到正式目录。若要声明正式部署，还必须冻结 immutable Git-tree request，由不同 signer 与真实不同 `faultDomain` 形成 quorum，取得 production policy receipt、通过 v2 strict verifier 后再 promotion 原子写入完整闭包，并从 `automation/start.ps1` / 根 bootstrap 标准入口验证同一身份；不得手工复制或单独恢复任一二进制。

同日又收口了观察期原生 AS2 HUD 的图标投影：领域写成功后不再只更新旧槽位的 `已装备名/数量/CD/MP`，而是由 `SkillLoadoutService.projectQuickSlotRenderer` 在替换时强制走“空 → 默认图标”帧以重建 attachMovie 图标壳，卸载时清空全部显示字段并停在空帧。该 renderer 不反写 root 槽位/技能行，也不重置 `ManualCooldownService`；新鲜 Flash trace 为 `SkillLoadoutServiceTest 50/50`，`asLoader.swf` 已刷新为 990,467 bytes，FFDec 定点证据已确认 root bridge、`skillMoveSlot` 与 class `moveSlot` 方法进入产物。

快捷槽互拖必须使用独立原子命令 `moveSlot {sourceSlot,targetSlot,expectedRevision}`，不能在 Web 或 Host 侧拼接 equip/unequip。源槽为空返回 `slot_empty`；目标为空则移动，目标占用则交换；同物理槽与 EasyMode 同技能双槽为无副作用 no-op。源/目标中的非空技能都必须通过 learned、metadata、equippable、非纯被动与 `stateHealth=ok` 检查；成功只增长一次 revision、只 dirty 一次并返回一份完整 snapshot。指针拖动无需确认，拖出槽带取消；键盘以 `Alt+←/→` 移动并让焦点跟随被移动技能，便于连续调整。

## 1. 迁移分级

| 分级 | 判断标准 | 不允许声称 |
|------|----------|------------|
| 静态原型 | 只有 `launcher/web/modules/*/dev/` harness、mock 数据、美术资源 | 不得说“已接入运行态” |
| Web panel 原型 | 有正式 JS module 与 `Panels.register`，但未接 AS2 / C# 写操作 | 不得说“功能完成” |
| 协议接入 | Web cmd、C# Task、AS2 handler、response task 全链存在 | 不得跳过验证直接合并 |
| 生产可用 | 完成构建、xUnit / harness、Flash fresh trace / fresh Output Panel 副本 / IDE 复核（明确证据类型）、游戏内端到端手测 | 才能说“迁移完成” |

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

### 武器平衡展示摘要（只读附加字段）

库存行、K 点商城目录行和 NPC 商店目录行可带可选 `balanceSummary`：`{state:"confirmed",weightLayers:Number,formula:1,level:Number}`。该字段由 AS2 从 ItemUtil 独立 balance 缓存和原始武器数据生成；必须同时命中严格 weapon balance v1、当前 profile 的 `status=confirmed`、`displayEligible=true`、当前已知 `workbookVersion`，并让绑定身份、profile、弹药/射击语义、工作簿版本及 14 项业务数字的 FNV-1a/UTF-16 digest 一致。库存按实例 tier 精确选择 `data_*`，商店固定 `data`；未知 tier、缺 profile、旧草案、黄/红、版本/digest 过期、多节点歧义或任一非有限输入一律**省略整个字段**，不发送 `null` 占位，也不回退基础 profile。

这只是现有 snapshot/catalog 的只读附加投影，不新增命令、revision 或写能力。Web 只允许使用 `state/weightLayers/formula/level`；不得接收或显示 `auditRef/note/inputDigest/workbookVersion/ruleRefs/evidenceRef`，也不得按 price/rarity 自行补造。字段缺失是正常 fail-closed 状态，不能让目录或库存 envelope 因此判畸形。当前常态视觉为图标左下 `LvN ◆±N`（紧凑/owned 为 `◆±N`）与 Tooltip 的一行“同级加权”；`◆0` 表示已确认零层。WBR 条款号和内部审计状态不进入玩家界面，DPS/受控短标签只保留为后续显式协议扩展。

2026-07-23 本轮 strict v1 fresh 证据：`InventoryPanelServiceTest 131/131`、`KShopCheckoutServiceTest 20/20`、`NpcShopPanelServiceTest 46/46`，各自 Compiler Errors `0/0`；publish-only `scripts/asLoader.swf` 为 1,033,191 bytes / SHA-256 `A5AEF4B61B45FCB5AA7AAD293FA6AE364060117EAA28CAFE8A815FA78B95B409`。Web 回归为 workbench primitives 9/9、KShop presenters 19/19、KShop harness 91/91、NPC harness 86/86、物品格视觉矩阵 17/17。

K 点商城保留独立 `ShopTask` 和既有无 `domain` 的 `shop_response` 形状，但新结算已收敛到与 NPC 商店同构的“权威预览 → opaque token → 原子提交”上位模型。购物车仍以 `saveCart` 保存恢复影子；新购买不再写入历史待领取队列：

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `bulkQuery` | `shopBulkQuery` | `shopBulkQuery` | `shop_response` | `panel_resp callId` | `KShopRequestMux` callback | 读；目录（含策划专柜 `type` 与物品 `majorType/use/actionType/weaponType`）/cart/历史待领取/K 点快照 |
| `saveCart` | `shopSaveCart` | `shopSaveCart` | `shop_response` | 同上 | `KShopWriteCoordinator` | 写；购物车恢复影子 |
| `checkoutPreview` | `shopCheckoutPreview` | `buildCheckoutPreview` | `shop_response` | 同上 | 二级结算页 callback | 读；重算等级/价格/余额/容量并铸 `checkoutToken` |
| `checkoutCommit` | `shopCheckoutCommit` | token 单次消费 + 复核 + `ItemUtil.acquire` | `shop_response` | 同上 | `KShopWriteCoordinator` + `InventoryCoordinator` 刷新 | 实际物品容器 + K 点 + cart 原子写；成功回包含写后 `catalog` |
| `claim`（兼容） | `shopClaim` | `shopClaim` | `shop_response` | 同上 | 历史待领取 callback | 写；旧 `商城已购买物品` → 实际目标容器；成功回包含写后 `catalog` |

`checkoutPreview` 只接受 `{v:1,cart:[{idx,qty}]}`；AS2 按当前 `_root.kshop_list` 重解 item/价格/等级。目录逐行下发权威 `maxQuantity`：装备为 1，普通堆叠物品只受 `999999` 技术护栏，情报再与 `ItemUtil.getInformationRemaining` 的实时剩余容量取最小值；旧 Host 未下发该字段时 Web 才兼容回退 999。`purchaseLimit`/`maxQuantity` 是显式设计配额或动态容量，不得再用统一 100/999 常量冒充策划规则。购物车恢复与 `saveCart` 同样按权威上限清理；首次 `bulkQuery` 清理出的变化必须继续写回恢复影子，不能只停留在本次 Web 内存。整单由 `ItemUtil.require` 做无副作用容量预检，情报重复项先聚合且超过剩余量必须整体拒绝，不能依赖 `InformationCollection` 的末端 clamp。预览逐行返回 `maxAffordable/maxByCapacity/maxPurchasable`，整单返回余额、总价、预计余额、`canCommit/blockingError` 与单次 token；情报容量不足使用 `destination_full`。`checkoutCommit` 不再信任 Web cart，只消费缓存 plan 并重新解析当前目录、余额与容量；复核成功后先由 `ItemUtil.acquire` 全量计划并交付，再扣 K 点、清空恢复影子并强制存盘。余额或容量不足零写，`balance == total` 合法。成功 `checkoutCommit/claim` 必须携写后 `catalog`，Host/Web 缺字段即按畸形成功进入对账；Web 采用新目录并再次清理当前购物车，动态上限为 0 时呈现 `sold_out/已达持有上限`。未知/畸形/超时 commit 仍进入 `needs_reconcile`，只允许 `bulkQuery + inventory snapshot` 对账，绝不重放 token。`_root.商城已购买物品` 只保留既有存档的 `shopClaim` 兼容；legacy `shopCheckout` 也复用同一 `finalizeCheckout` 直接交付、不再产生新的待领取债务，并和新入口一样允许精确余额结账。新 Web 只展示并领取既有历史记录。 2026-07-22 历史 fresh CS6 定向 trace 为 `KShopCheckoutServiceTest 18/18`、`NpcShopPanelServiceTest 44/44`，随后 publish-only `scripts/asLoader.swf` 刷新为 **1,042,562 bytes** / SHA-256 `ACE5DFC7FC5D9DA615ECB0CCC945545E825530AE5E15F8032DB45C2BED613143` / Git blob `ccae1fcfac19199c213941e78da573fac3ee4027` / mtime **2026-07-22 10:13:40 +08**，Compiler Errors **0/0**；publish 本身不替代上述行为 trace。

KShop 目录的普通单击或 `+` 直接把商品加购 1 件；拖到“拖拽加购”区域仍作为可选的精细交互保留，不能再把拖拽作为唯一主路径。购物车主页面只显示 `×N`、小计和整行移除，不提供 `− / +`；旧目录数量弹层与购物车数量编辑均已退役。唯一精确数量入口是“核对并结账”的二级页，它必须使用共享 `SecondaryPage` 的 dialog/inert/focus/Esc/opener 闭环，并与 NPC 商店复用 `workbench-components.js` 的 `QuantityControl`。数量控件以目录/preview 的合法上限 `A` 提供数字输入、完整 range 和真实数量键盘步进，以 `maxPurchasable=E` 提供“可用”预设与轨道标记；`A>200` 只改变为对数位置映射，不改变真实数量或 ARIA 上限。空值、小数、负数和越界草稿本地报错且零 preview，第一次 Esc 只撤销草稿。preview 重算必须按商品 key 复用行/控件并恢复滚动与字段焦点；关闭和销毁再统一释放 listener。控件只产生本地数量意图，权威价格、容量、动态上限和可提交性仍由下一次 preview 裁决。商城顶栏统一使用共享 `HelpAction`，说明上述单击/拖拽/结算分工，开闭帮助不得产生业务消息。

NPC 金币商店使用独立 `npcshop` domain 与 `NpcShopTask`，不复用 K 点商城 `ShopTask`，也不把买卖硬塞进通用 `InventoryTask`。左栏固定 NPC 目录；右栏在 Web 组合层仍呈现背包与收集品两个并列 owned View，收集品内部再切材料/情报，其中情报只读。权威 wire 按数据所有权拆分：背包只来自 `domain=inventory` 的 `InventoryCoordinator`，`npcshop` snapshot 只返回 `views.material/intelligence`；Host 的 NPC 成功回包校验不得再要求或合成 `views.bag`。

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `npcShopSnapshot` | `NPC商店WebView.executeSnapshot` | `npcshop_response` | `panel_resp domain=npcshop cmd=snapshot` | `NpcShopRequestMux` callback | 读 |
| `tooltip` | `npcShopTooltip` | `executeTooltip` | `npcshop_response` | `panel_resp domain=npcshop cmd=tooltip` | tooltip callback | 读 |
| `tradePreview` | `npcShopTradePreview` | `executeTradePreview` | `npcshop_response` | `panel_resp domain=npcshop cmd=tradePreview` | 二级结算页 callback | 读；铸造单次 trade token |
| `tradeCommit` | `npcShopTradeCommit` | `executeTradeCommit` | `npcshop_response` | `panel_resp domain=npcshop cmd=tradeCommit` | 二级结算页 callback | 背包/材料 + 实际买入容器 + 金钱原子写 |

NPC 目录对象的 `purchaseLimit` 仅在策划显式配置时生效，合法域为 `1..999999`；未配置的装备以当前背包技术容量为上限，普通堆叠物品使用 `999999` 技术护栏，情报再取实时剩余容量。snapshot、trade preview、commit 与 legacy buy 必须复用同一上限解析；Web 对 `maxQuantity=0` 必须呈现“已达持有上限”并禁止创建购买意图。金额、收集栏容量任一不足均须在写前失败，禁止先扣全额再让 collection clamp 丢弃超额部分。

Host 的 `1..999999` 只是 NPC 购买数量的 transport 护栏，不是业务配额；AS2 返回的 `purchaseLimit/maxAffordable/maxByCapacity/maxPurchasable` 才是动态有效上限。其中 `purchaseLimit` 是合法 preview 输入的硬上限，`maxPurchasable` 是当前余额、容量与整单条件下可直接提交的快捷上限：`+ / +5` 可以在 `purchaseLimit` 内构造暂时不可提交的计划，以便追加待售项或进入“整理空间”，但 preview 必须返回 `canCommit=false + blockingError` 并保持加减、返回和“可用”可操作；“可用”以 `reason=maximum` 精确回到当前 `maxPurchasable`，不能把越界 preview 错当写成功或界面冻结。re-preview 在途时数量行必须与 handler gate 一致地可见禁用，回包后再重绘开放；禁止保留看似可点、实际被 `_previewBusy` 静默吞掉的按钮。Host 不得复制固定 100/999 上限，但必须对成功 `tradePreview` 严格校验 token、总额、容量、`projectedBalance/missingSlots/canCommit/blockingError` 自洽、slot/same_name 计数、行类型/小计，以及买入/卖出行与归一化请求的物品身份、数量、scope 一致性；畸形读回包不得污染写门。Web 用 preview epoch 屏蔽关闭/重开前的迟到回包，每次成功 preview 把精确请求与 settlement 绑成 checkpoint：普通读 timeout、断线或畸形回包恢复最近 checkpoint 并保持加减/返回可操作；`stale_state/shop_not_found/item_not_found/locked/invalid_price/invalid_quantity/insufficient_quantity/nothing_to_sell/sell_forbidden` 必须获取 fresh authority snapshot；只有 Host 明示 `requiresReconcile` 的写 timeout/send failure、`reconcile_required` 或畸形 commit 才进对账，绝不自动重放 token；`tradeCommit` 在途必须同时锁住返回、加减、可用、批售、移除与重复提交。

NPC 购买/出售结算同样使用共享 `QuantityControl`。购买的合法上限 `A=purchaseLimit` 供普通数字输入、range、`+ / +5` 和键盘使用；当前可直接提交上限 `E=maxPurchasable` 只供“可用”预设与轨道标记，`reason=maximum` 必须精确使用 `E`，两类上限不能在 UI 组件里合并。出售的 `A/E` 都来自权威 `maxQuantity`。数字草稿在 change/Enter 前允许保留；空值、小数、负数和越界值显示错误且不发 preview，第一次 Esc 恢复已提交值，不能在玩家按退格时立即跳回最小值或把 Esc 冒泡成关闭结算。

情报奖励按每个情报物品自身配置的 `maxvalue` 结算，不存在全局“四个”上限。`ItemUtil.planRewardAcquire/acquireReward` 在同一奖励批次内为重复情报共享剩余容量：可接受部分正常入账，超出部分按该物品非负整数 `price` 精确折算进金币；`price=0` 的剧情情报只截断并明确提示，不制造无价值拾取物。敌人掉落在生成时先分流一次，实际拾取时再复核并发占用；折算金币标记为 exact currency，不再经过随机转 K 点、等级或模式倍率。任务、成就与 `GrantItemEffect` 都必须走奖励入口。商城与合成仍使用严格容量预检，超上限交易/配方整体拒绝，禁止通过购买情报套利成金币。

合成工作台使用独立 `crafting` domain 与 `CraftingTask`，不复用 inventory/NPC/KShop 的写协议。旧 `_root.改装系统.加载改装清单(分类)` 先尝试发送 `panel_request panel=crafting initData.category`，Launcher 或 socket 不可用时才回退 `物品改装界面` SWF。Host 与 AS2 对分类均固定白名单：`铁枪会/属性武器/烹饪/化学生产/武器合成/饰品合成/进阶防具/基础防具/公社防具/黑白契约/插件合成/大学装备`；Web 不能提交任意配方对象、物品名、材料数、价格、技能折扣或强化继承结果。snapshot 顶层 `gender:"男"|"女"` 是装备检视分支的权威值：AS2 从 `_root.性别` 规范化，Host 对缺失或非法值 fail-closed，Web 不从名称或素材反猜性别。

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `craftingSnapshot` | `CraftingPanelService.executeSnapshot` | `crafting_response` | `panel_resp domain=crafting cmd=snapshot` | `CraftingRuntime.RequestMux` callback | 读；配方目录 + 权威 gender + 当前余额/技能 + 单份可合成状态 |
| `materials` | `craftingMaterials` | `executeMaterials` | `crafting_response` | `panel_resp domain=crafting cmd=materials` | `CraftingMaterials` catalog callback | 读；材料字典目录 + 持有量 + 来源/用途计数 |
| `materialDetail` | `craftingMaterialDetail` | `executeMaterialDetail` | `crafting_response` | `panel_resp domain=crafting cmd=materialDetail` | `CraftingMaterials` detail callback | 读；材料说明、怪物/关卡来源与合成产物用途 |
| `preview` | `craftingPreview` | `executePreview` | `crafting_response` | `panel_resp domain=crafting cmd=preview` | 详情栏 callback | 读；接收 `craftCount=1..99`，重算总材料/余额/容量并铸 `craftToken` |
| `tooltip` | `craftingTooltip` | `executeTooltip` | `crafting_response` | `panel_resp domain=crafting cmd=tooltip` | tooltip callback | 读 |
| `commit` | `craftingCommit` | `executeCommit` | `crafting_response` | `panel_resp domain=crafting cmd=commit` | 提交 callback | 材料/背包/金币/K 点原子写 |

Native HUD `MATERIALS → openMaterialUI → CraftingPanelService.openMaterialsPanel` 直接发送 `panel_request panel=crafting initData.view=materials`；Host 只重建固定 runtime initData，Web 进入 `crafting-materials.js` 的只读材料视图。该入口不再设置旧 material-only flag、不打开旧 `物品与技能相关界面`，发送或挂载失败时只明确报错，禁止保留 Flash fallback。目录复用 `ItemUtil.materialDict` 与现有材料注释，详情复用 `ItemObtainIndex`、`SynthesisIndex` 和敌人名称投影，分别呈现哪些怪物/关卡可获得以及材料会用于哪些配方/装备；Web 不扫描 XML、不推断掉率，也不新增平板电脑或巴别塔文档迁移范围。材料视图独立持久化 `cf7.itemgrid.mode.crafting-materials`，无偏好时默认紧凑 7 列图标格，完整模式恢复 2 列可读文本；切换须同步键盘列数并保持选择/焦点。顶栏共享帮助说明筛选、密度、来源/用途和方向键，不另造材料专用模态系统。

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

上述切换只是在 exact `crafting` instance 内挂载纯 Web 整理子路由：Host active owner、原 `panelInstanceId` 与 pause lease 始终仍属 `crafting`，不发送新的 `panel=workbench` open。只有显式“返回合成”才恢复合成 DOM；普通关闭、Host close、lazy dependency 失败或 workbench mount 失败均关闭 exact crafting owner，不隐式返回或复活。独立 workbench 必须由 Host 分配有效 `panelInstanceId` 后才能挂载，缺实例 fail-closed；整理使用的 inventory lease 与已撤销的合成 token 不共享，但这不表示存在第二条 Host pause lease。

`equipment-inspector.js` 是 Web 内共享的只读装备检视层，`crafting-inspector.js` 只保留合成文案/兼容 API；两者不增加任何业务 cmd/action，也不进入 AS2 写路径。合成详情原图标与调制页顶部当前装备图标保留为主入口；调制交换态仅在已经选定的目标摘要卡提供独立角标入口，不给材料、进阶、配件或交换候选目录批量加按钮。普通武器绘制完整装备 skin 且不带人物；刀类复合武器只按权威 `actionType` 分流，`双刀` 必须用 battle `兵器站立` 的真实 holder 同时绘制 `刀_装扮 + 刀2_装扮`，`疾影` 必须同时绘制 `刀_装扮 + 刀3_装扮`。`刀1_装扮` 只是主刀的兼容别名，不能当副刀；即使两个 holder 指向同一 skinKey 也必须保留两个槽位，不能按素材键去重；不得因普通刀恰好存在 `刀2_装扮` 就误判为双刀。复合状态启用 strict fields，渲染闭包必须精确满足预期两个 holder，且 `missing=0 / failedImages=0`；素材缺任一部件、battle rig 漂移导致 holder 不再是 2/2、或任一图片失败，都须整组回退当前 `icon`，禁止退化成会误导玩家的单刀特写。防具只绘制当前权威 `gender` 分支的装备 fields（头部可带脸型承托，上装不补手、下装不补脚、手套不补前臂、鞋不补腿），不得借用异性分支；其他物品、dressup 缺失、当前性别分支缺失或纸娃娃图片加载失败也回退当前 `icon`，图标再缺失时显式显示缺图。首次主动打开才懒加载 dressup manifest；默认 185% 特写，支持 pointer drag、滚轮、键盘/按钮平移缩放、全貌/重置与纸娃娃动画及当前动态图标静态首帧暂停/继续；Canvas 动画按 24fps 限流，外层 PanelScale 改变后重采样 backing。替换 modal、换主装备/交换目标、切 operation、关闭 session/modal 或切 panel 必须销毁唯一 live renderer、RAF 与监听器。

调制检视的离线全量验收固定枚举 `data/items/*.xml` 的 1197 条原始武器/防具定义，禁止按 `name` 去重；稳定身份使用 `sourceFile + 同文件同名 occurrence`，原始 ordinal 只作诊断元数据。生产候选闭包为 1197 个当前图标基线 + 543 个武器商品图 + 男女各 552 个防具聚焦，共 2844 个逻辑候选；人类必须裁决 1749 个实际生产分支，其中 102 个为无性别图标回退（3 把弩 + 99 条颈部）。默认 185% 增益、9 双刀、9 疾影、男女分支、缺图与 holder 闭包先由自动门裁决；33 个真实动态分支只按 resolver 选中的装备 field/skin 递归识别嵌套时间轴，必须打开 production live renderer 后显式记录 `motionReviewed` 才能通过。决定同时绑定覆盖 XML/代码/实际素材字节的 `sourceDigest` 与覆盖候选 PNG、关键 metrics/gates/motion 证据的 `reviewDigest`；opener 还须逐字节复核 2946 个落盘引用，partial、陈旧、越界、缺失或哈希不符一律 fail-closed。该决定文件只作人工 QA 证据，不得成为运行时逐物品路由表。

只有可提交预览才签发 opaque 单次 `craftToken`。`commit` 先消费 token，再按分类 + recipeIndex 重取配方，并比较配方签名、金币/K 点、等级/技能、背包/药剂栏 `mutationRevision` 与相关材料/情报/装备拥有态；任一变化返回 `stale_state` 且零写。复核成功后先备份四个容器与余额，`ItemUtil.submit` 扣材料、`ItemUtil.singleAcquire` 交付，交付失败则恢复容器/余额/dirty 状态；成功后才扣调整后的金币/K 点并标 dirty。内部 recipe/ref/备份不得进入 wire，token 在成功、失败或再次 snapshot/preview 后均不可重放。

`CraftingTask` 与 Web 均采用 `idle/write_pending/needs_reconcile`。Web 把每次成功 preview 保存为同 `category/recipeIndex/craftCount` 的 checkpoint：普通 preview timeout/client_timeout/disconnected/畸形或未知非权威读错恢复 checkpoint 并继续可操作；stale/category/recipe/item/material/money/kpoint/inventory/level/batch 分歧先刷新 snapshot。只有回包明示 `requiresReconcile/reconcile_required`，或已投递 commit 的 timeout/drop/disconnected/畸形结果才进入写对账；同步未投递的 commit 失败保持可操作，任何失败都禁止自动重放；合成的对账读必须是同一 recipeIndex 的结构完整 `preview`，因为它同时覆盖材料、余额、容量和产物状态，成功 preview 才解除 Host 写门。单独 `snapshot` 不足以证明具体配方资源状态，不得解除 `needs_reconcile`。

基地理发店使用独立 `hairdresser` domain，入口固定为 `基地场景合集` 中理发师 NPC → `_root.gameCommands["openHairdresser"]()` → 精确 `panel_request {panel:"hairdresser",source:"world_hairdresser"}`。该入口已冻结为 Web-only：命令缺失或 socket 发送失败均 fail-closed，不再加载旧 UI。旧 `理发店界面 / 发型TAB` renderer、实例、linkage 与主 XFL 的 `改变发型 / 预览发型 / 恢复发型` 已退役；新建角色流程中的男女默认发型 writer、8 个 `界面-发型选择[1-4]` 控件及 2 个 `控制值="发型"` 绑定不属于理发店 renderer，继续保留。P0-F F3 关闭当时的冻结候选证据严格为 `e2e_verified / NOT_DEPLOYED`，不得改写为当时已经部署；其后独立完成的 v2 promotion 与标准入口复读已将 2026-07-24 冻结正式身份推进到 `standard_entry_verified`。

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `hairdresserSnapshot` | `HairdresserPanelService.handle("snapshot")` → `executeSnapshot` | `hairdresser_response` | `panel_resp domain=hairdresser cmd=snapshot` | `HairdresserRuntime.RequestMux` callback | 读；`gender/face/currentHair` + 77 行权威目录 |
| `commit` | `hairdresserCommit` | `HairdresserPanelService.handle("commit")` → `executeCommit` | `hairdresser_response` | `panel_resp domain=hairdresser cmd=commit` | 提交 / 对账 callback | 写；发型 root + live actor 刷新 + dirty mark |

AS2 从现役 `_root.发型库 / 发型名称库 / 发型价格` 三数组逐行投影 `{identifier,name}`，必须保持 77 行源顺序和重复项，不按 identifier/name 去重；长度不一致、空标识、非数值价格或任一非零价格均整体 fail-closed。snapshot 的 `gender/face/currentHair` 是权威文本；Web 不反猜二值性别，renderer 无法识别时只显示可读降级，目录和提交仍可用。发型选择只在 Web 内以既有 `DressupDollRenderer` 预览脸型/发型，使用 strict fields、非动画且光头项只渲染脸型；预览、取消、X、ESC、backdrop 和 close 都不写业务状态。

commit 只接受 `{v:1,hairIdentifier}`，不接受价格、货币、backend preview、execution token 或任意 catalog 行对象。AS2 每次重新解析当前免费目录，并在写前一次性确认目标存在、root actor、live actor、存档对象与装扮刷新方法可用；全部前置条件通过后，顺序固定为 `_root.发型` → live actor `发型` → `gotoAndPlay("刷新装扮")` → `_root.存档系统.dirtyMark=true`。它保持现役免费语义，不扣 K 点/金币，也不新增自动存盘命令。Web 收到字段完整且 `currentHair` 精确等于本次选择的权威成功回包后，必须立即复用正常 `requestClose()`：当前 Web session 只关闭一次，Host 继续独占 pending 清理和游戏焦点恢复。确定失败保持面板可操作；未知结果仍在当前面板读取 fresh snapshot 并显示 applied/not-applied，不用延时器猜成功，也不因普通重开 snapshot 自动关闭。

`HairdresserTask` 直接组合同一 `PanelPendingCallTracker<TContext>`，只在领域内维护 `idle/write_pending/needs_reconcile` 和期望发型。确定成功或确定失败恢复 idle；已投递 commit 的 timeout、send-false、断线、畸形或未知回包进入 `needs_reconcile`。随后只准发新鲜、结构完整且越过在途写的 snapshot；若 `currentHair` 等于期望值则记为 applied，否则记为 not-applied，两种都可解除写门，任何路径都禁止自动重放 commit。Web 仍用共享 `PanelRequestMux` 做 generation/session 隔离；生产 PanelHost close observer 同时显式调用 `HairdresserTask.ClearPending()`。若关闭时已有 commit，clear 只终结 transport pending 并保留领域 `needs_reconcile` 与期望发型；重开再以 post-unknown fresh snapshot 收敛，旧 commit 回包不得复活，也不得跨会话保留选择或重放写。

资源 lease 与交易计划 token 必须分开治理。`slotLease` 是 inventory 资源的 OCC 版本：同一 `ArrayInventory` 实例、同一 `mutationRevision`、同一槽位引用与确认指纹上的重复 snapshot 必须返回同一 opaque lease，纯读不得调用全局 session reset 或使其他面板刚取得的 lease 失效；snapshot 同时回显 `containerVersion` 供诊断。任一真实容器写入推进 `mutationRevision`，容器替换、引用/数量/名称/强化/进阶/插件/更新时间变化也必须使旧 lease 返回 `stale_state`。NPC 材料/情报的 collection lease 同理：同商店、同 view/key/count 的重复读保持稳定，切换商店、键消失或数量变化才轮换并清理旧映射。`tradeToken` / `checkoutToken` / batch token 是一次性交易计划，显式重同步或一次提交尝试后仍须失效，不能为了“稳定 lease”改成可重放。

装备调制的 Web 组合遵守同一边界：顶层固定为“强化度 / 交换 / 进阶 / 配件”四栏，wire 为七类 operation（含 Web 组合态 `replace_mod`；旧 renderer 仍只适配原六类入口）。成功 snapshot 顶层必须携带规范化 `gender:"男"|"女"`；AS2 由 `_root.性别` 生成，Host 对缺失/非法值以及 commit 内嵌畸形 snapshot 一律 fail-closed，Web 不猜默认性别。强化度只把本地最终目标交给 AS2 preview/token，动态上限与永久 `hardMaxLevel=13` 分开，封顶态不得构造 `+14`；交换候选由 inventory coordinator 按 source 精确 `majorType+use` 做独立只读 projection，不改写左栏窗口/筛选/面包屑，AS2 继续保留 no-op 与 lease 二次防线。候选 tooltip 保持 `introHTML/descHTML/itemType/itemUse` 分段，不与浏览器原生 `title` 竞争。配件目录复用“档级 / 用途 / 定位 / 状态”树；`replace_mod` 在一次 preview/commit 中原子返还旧件、扣新件并写最终配置，安全/快速偏好只能影响是否在严格无连带单件操作后自动提交，不能增加 wire 或绕过 `beginExternalWrite`。commit 的 busy/write capability 必须覆盖 inventory refresh 整段；刷新 settle 前不得换装备或发新 snapshot。紧凑候选保持 `48px` 格、`40px` 图标、`4px` 间距，1024×576 下 25 项无需滚屏；决策区信息量固定，reduced-motion 使用静态首帧。当前 Character Build 还能从已穿戴或候选装备进入同一 tuning writer，并由 loadout external-write/reconcile 门收束。自动门以 [testing-guide.md](testing-guide.md) 的当前 runner 为准，不在本文冻结早期 per-viewport case 数。

workbench 的 `close` 与调制业务 envelope 使用同一实例边界：Host 必须校验严格四字段 `{type,panel,cmd,panelInstanceId}`，且请求 `panelInstanceId` 精确等于当前活动 workbench 实例后，才能撤销调制 session、发送 `webPanelUnpause` 或关闭 PanelHost。旧实例迟到的 close、缺实例和额外字段一律拒绝，禁止拿 Host 当前实例替客户端补盖章。

KShop `bulkQuery.catalog[]` 与 NPC shop `snapshot.catalog[]` 的自动分类投影固定包含 `majorType/use/actionType/weaponType`：它们分别来自物品现有 `type/use/actiontype/weapontype`，Web 只据此建立 `大类 → use → 武器子类` 的互斥浏览树，不读取 XML 文件名、不复制物品定义。KShop 另保留 JSON entry 的 `type` 作为策划专柜名；NPC 人工 `layout.sections` 作为同等的策划专柜来源。两者都以“类别 / 专柜”两个一级入口并存，专柜不得覆盖或伪装成自动物品大类。NPC 未配置 sections 时只呈现自动类别；未知自动字段只能进入“其他”，不得过滤掉商品。以上展示投影不参与价格、购买落点、可售性或提交复核。

NPC 商店主页面只维护待购/待售意图，不直接改存档；二级结算页把 `{catalogIndex,quantity}` 与 lease-bound sale source 交给 `tradePreview`。精确出售使用 `scope=slot + quantity`；同名批售只允许背包 seed lease + `scope=same_name,policy=plain_only`，物品名、匹配范围、合格实例与强化/进阶/带插件保护数量由 AS2 扫描，Web/Host 不接受客户端 itemName 或价格。AS2 必须在批售展开后再按真实 `entry.identity` 全局去重，禁止同名批售与逐格出售重复结算同一槽；多个售出装备返还的同名插件必须先聚合数量再交给 `ItemUtil.acquire`。不可堆叠装备复数采购在 AS2 计划中展开为多个 `{name,value:1}` 独立实例，禁止把数量塞进单件装备的强化值；预览逐行返回 `purchaseLimit/maxAffordable/maxByCapacity/maxPurchasable`，整单返回 `requiredSlots/availableSlots/missingSlots`。价格、口才折扣、情报门槛、可售性、买入真实落点、容量与最终金钱变化全部由 AS2 重算。预览返回 opaque `tradeToken`、权威明细、买卖总额、预计余额与阻塞原因；`tradeCommit` 在同一次事务中复核余额、商品、引用、普通装备保护条件、槽位、数量和价格，允许所选售款抵扣购买，也允许售出腾出的背包格被同笔购买使用。令牌单次消费，提交失败不得留下部分出售；内部 inventory/ref 不得进入 wire。旧 `buy/sell/batchPreview/batchSell` 只保留 Flash 兼容入口，其中 legacy `buy` 装备仍限单次 1 件；新 Web 不调用。`NpcShopTask` 与 Web 均采用 `idle/write_pending/needs_reconcile`：超时、断线、发送失败、未知结果或畸形写回包后只准新发结构完整的 snapshot 对账，绝不自动重放 `tradeCommit`。Host 将畸形回包规范化为 `error=malformed_response, requiresReconcile=true`，旧 snapshot 回包不得解除仍在途的写门。

`inventory_full` 时结算页可进入嵌入式“背包—战备箱”整理子路由，但不得给 `npcshop` 新造库存写协议：它必须复用 `domain=inventory` 的 `InventoryCoordinator`、slot lease、`autoTransfer(mergeThenEmpty)` 与战备箱剧情可访问容量。返回结算前分别刷新 NPC collection 状态与 inventory 背包窗口，再以 inventory 背包 + NPC material 组合视图按真实槽位/名称重绑仍存在的待售意图并重新 `tradePreview`；已移动且无法安全重绑的精确待售项必须移除并提示。采购意图以稳定 `catalogIndex` 保留。首轮不支持直接购买到战备箱。

`_root.UI系统` 是跨帧共享服务命名空间。任何后置 UI 初始化都必须使用 `_root.UI系统 = _root.UI系统 || {}` 或只补具体成员，禁止 `_root.UI系统 = {}` 整对象重置；否则会静默抹除早期注册的 Panel 服务，表现为 Host/Web 面板已打开但 snapshot 永不回包。迁移新增早期服务时，TestLoader 必须按实际 include/帧顺序加入“后置初始化后引用仍相同”的回归断言。

snapshot 请求的 `filterKey=all|weapon|armor|consumable|material|other` 由 C# 严格枚举后交给 AS2；带 `filterSpec` 时 Host 与 AS2 都必须校验映射一致（`collection → other`，其余 major 与 `filterKey` 同名），禁止接受“回显武器路径但实际走 all 分支”这类矛盾请求。AS2 必须扫描容器权威范围再分页，返回匹配项 `viewCapacity`、真实 `physicalSlot` 与 slot lease，禁止 Web 只筛当前页。背包、仓库和战备箱共用权威树筛选与权威整理组件；目录与背包的 Web 交互统一为行内单层 drilldown，武器不得截断 `use → actionType/weaponType` 第三级。纯 Web `displaySort` 已退役，未筛选窗口保持 `physicalSlot` 顺序，真实重排仍只经上述写闭环。`filterFacets/filterItemCount` 缓存以 `ArrayInventory` 实例引用、容器单调 `mutationRevision` 与 `accessibleCapacity` 做 O(1) 命中校验；`add/remove/addValue/setItems` 与三个 transaction 写入口成功后必须推进版本，失败写入不推进，禁止退回每次 snapshot 全前缀逐槽引用扫描。inventory-domain 仍主动删除受影响缓存，确保拾取、购买、出售与跨容器移动后不会返回陈旧分类。战备箱 snapshot 同时返回物理 `capacity=400` 与剧情权威 `accessibleCapacity=0..240`、`pageSizeHint=40`；Web 分页与筛选只允许使用可访问前缀，`sortAndMerge` 也只重写该前缀并逐槽保留 240..399 锁定区。旧 Flash `计算战备箱总页数` 调用同一 AS2 权威函数，禁止在 JS/C# 复制主线、挑战或基建解锁公式。

`autoTransfer` 不接受目标槽位：Web 只提交 lease-bound `source`、`targetContainerId`、固定策略 `mergeThenEmpty` 与用于回显/重铸 lease 的当前 `windows`。AS2 在目标完整可访问范围内先找同名数字堆叠、再找首个空槽；目标已满时保持来源与 dirty 状态不变，绝不自动交换异类物品。`windows` 不能影响实际落位，也不能把仓库强制跳到真实目标页。`warehouse` 与 `battlebox` profile 都提供“批量存入/批量取出”：开启后普通点击只暂存最多 50 个格，重复点击取消，显式“执行转移”后再依次调用既有 `autoTransfer` 并严格单飞；`Ctrl+单击` 保留为单件立即转移。任一超时、断线、stale 或不确定提交必须停止余项并对账，不重放未知写入。storage/tuning/build 共用同一个标准 `HelpAction`，按当前 view 动态解释精确放置、拖拽、Ctrl 快移、批量暂存/执行或调制/构筑规则；不得重新在子标题中并列第二个帮助按钮。

世界内入口统一调用 AS2 `openInventoryWorkbench({profile,source})`，发送 `panel_request panel=workbench initData.profile`；C# `LauncherCommandRouter` 再做一次 `warehouse|battlebox` 白名单并重建固定 runtime initData。XFL 不得直接传 `containerId`、容量或任意 `initData`。宿舍入口在 Launcher 不可用或发送失败时才回退旧 Flash 仓库 MovieClip；真实仓库不得重新暴露给商城或通用 HUD。

检查点：

- Web `cmd` 必须进入 `WebOverlayForm.HandlePanelMessage` 的 case 列表。
- C# Task 的 action 字符串必须与 AS2 `gameCommand` 分发一致。
- AS2 `task` 回包名必须与 `TaskRegistry` 注册名一致。
- C# 回包必须恢复 Web 原始 `callId`，不能把 Flash 内部 `fid` 泄漏给 JS。
- JS callback 必须在成功、失败、关闭时清理 pending / busy 状态。

战宠与佣兵迁移暴露过两类典型断链：Web cmd 没进 `HandlePanelMessage` 导致静默丢弃；AS2 委托其他 service 后回包 task 名不匹配导致 tooltip / 写操作永远收不到响应。新增 panel 时优先防这两类问题。

### 2.1 历史试验边界

地图资源箱 S0 无奖励试验、双 marker/dev gate、专用 AS2 socket bridge、Host coordinator 与 Web bootstrap/adapter/wire 已从源码、专项测试和发布资产要求中物理删除。普通 Lockbox 小游戏保持独立；未来开锁玩法必须另立协议与 ADR，不得恢复 dormant S0 或插在真实 loot authority 前面。退役原因与不可恢复边界见 [S0 墓碑 ADR](../docs/地图资源箱-S0无奖励编排-ADR-2026-07-17.md)，实现细节只从 Git 历史追溯。

2026-07-21 的单-canary candidate/promotion/standard-entry 只证明当时冻结的单点树，不构成当前全正网格源码的运行证据，也不授权保留 rollout、Flash renderer 或兼容旁路。

### 2.2 地图 loot 单一权威护栏

- AS2 `LootContainerService` 是奖励、inventory、journal、revision、lease 与终态的唯一权威；Host 只做严格信封、exact binding、串行和 panel 生命周期，Web 只发意图。
- 地图箱 `panel_request` callback 按 `queued / definite_rejection / definite_no_send / delivery_uncertain` 四类裁决。只有 exact queued ACK 升格 accepted；明确拒绝或明确未发送可以直接恢复，timeout、send exception、socket closed、畸形或未知 ACK 必须先冻结 authority、退役当前 XMLSocket source，再复用既有 socket-detach causal proof 收束当前 `openAttemptSeq`。retired source 的迟到 `onData/onClose` 按对象身份隔离；这不是第二套恢复状态机，完整 wire 只在 S1/S2 ADR 维护。
- 正网格的初次、重开、mount、navigation 与 socket 故障统一保留同一 inventory/anchor 并收束到 `LOOT_SUSPENDED`，空箱为 `CONSUMED`，anchor 失效为 `EXPIRED`；未完成 journal/effects/proof 时保持 `LOOT_COMMIT_PENDING`。
- claim/close 的未知结果只允许 causal query，不得重放写；普通满包只在同一 loot panel、同一 instance 内进入 organizer，返回前必须取得 fresh `LOOT_ACTIVE` snapshot。
- Flash 网格 renderer、claim-only adapter、observer recovery、按地图 rollout 与失败后地面掉落均不是恢复路径。发布事务回滚只处理 runtime 字节原子性，不得恢复上述实现。
- wire shape、状态机、不变量和当前证据只在 [S1/S2 ADR](../docs/地图资源箱-S1S2真实战利品容器与Web双栏-ADR-2026-07-18.md) 维护；命令与人工矩阵只在 [testing-guide](testing-guide.md) 维护，本通用迁移文档不复制动态计数或历史哈希。

### 2.3 地图资源箱 S1/S2 全正网格 Web-only 路由（2026-07-22；已冻结）

维护者已批准 `APPROVED_S1_S2_ALL_POSITIVE_GRID_WEB_ONLY`：旧语义中所有正整数 `row/col` 都是 Web intent，由 `InteractionHandler → LootContainerService.beginMapChestOpen` 在 kill 前统一 reservation。这里的“所有”以 `BoxInteractionArbiter` 已通过六个资源箱 preset 完成**箱体领域准入**为前提；该白名单只防止投影召唤器等非箱元件因带有 `row/col` 被劫持，不是 Web rollout/shape 白名单，也不得扩大。进入箱体领域后，`1×1` 有效，当前能力上限为 `col<=8 && row*col<=64`；超界或畸形尺寸 fail-closed，不 kill、不滚奖、不显示 Flash UI。只有精确 `0×0` 的 direct 箱继续地面掉落；负数、单边零、混合或缺字段全部拒绝。箱型名与当前恰有的 `2×4 / 4×4 / 4×8` 不参与准入后的 Web 选择；生产 XML 和运行时都不再使用 rollout marker。

中央路由替换“正常交互 → 箱体结束时间轴 → Flash 网格 UI”。实际发布的地图元件 XFL Include closure 中，六个 canonical 箱体 symbol 都只调用统一根开启回调；所有可攻击且具有“破碎”标签的箱都必须在该标签帧调用统一破碎回调；本轮已补齐装备箱和生存箱原先缺失的 callback。破碎路径没有自身 opening reservation，所以继续直接地面爆落且不得请求 Web；break guard 只在正在破碎的 exact target 已有 reservation/materialized/active/suspended/pending authority 时截住重复奖励，另一 target 的合法 authored break 继续 direct drop，unsupported shape 始终 fail-closed。Host/Web wire、panel ID 与 inventory mux 不变；恢复契约改为 Web-only：初次、重开与断线故障保留同一 inventory/anchor 并进入 `LOOT_SUSPENDED`，空→`CONSUMED`，anchor 失效→`EXPIRED`，未收束 journal/effects 保持 `LOOT_COMMIT_PENDING`，绝不调用 Flash renderer。

静态门全量审计所有真实箱体声明、item catalog 闭包、难度 `CaseSwitch`、概率/总数和容量边界，并解析地图元件 `DOMDocument.xml` 的真实 Include closure：六个 canonical 箱体 linkage 必须唯一、统一初始化与开启回调、破碎拓扑符合资产语义，且旧 renderer/旁路不得进入发布闭包；不再把易漂移的时间轴帧号当准入条件。`最小数量/最大数量` 只有同时缺省才按明确默认 `1/1`；单边缺省或显式坏值在 Web、精确 `0×0` 直投与攻击破碎三条路径上都 fail-closed。准确计数、产物哈希、candidate identity、promotion 与当前剩余门统一维护在专题实施与验收基线，不在本 canonical 迁移规范复制动态快照。

实机采用“静态全量 + 代表性人工”，不造 9 站、不逐图重复战斗。集中场只验证装备箱正常领空、生存箱满包 organizer、保险箱 suspend/reopen，以及装备箱与生存箱各一次攻击破碎；若现场已有 direct 夹具可顺带目视，但不单独为它打一轮战斗。能力边界、物品目录、数量默认、材料/普通物品/情报及容量组合由自动门和克隆存档覆盖。人类只负责真实互动、确认 Flash 网格 UI 始终不出现、焦点/键盘手感与破碎观感；fixture 安装恢复、身份/日志/数值对账和冷启动回读自动化。

### 2.4 跨层契约与交互生命周期（2026-07-22）

NPC/KShop/Crafting/Hairdresser 的唯一可执行登记表为 [`launcher/contracts/panel-contracts.v2.json`](../launcher/contracts/panel-contracts.v2.json)。v2 把 `(wireDomain, cmd)` 冻结为全局唯一命令身份，并逐命令记录 cmd→全局唯一 AS2 action、`query|transaction` capability、read/write access 与唯一 `businessDecisionOwner=as2`；`query` 只能 read，铸造/消费短期计划的 preview 则保持 `transaction + read`，不能按 access 误降成 query。domain 的 nullable `flashCommandHandler` 只表达现役 wrapper binding：NpcShop/Crafting/Hairdresser 记录精确 delegated `handle` receiver，KShop 以 `null` 明确保持 inline；`action + flashCommandHandler + flashResponseTask + hostResponseHandler` 共同构成请求/回包 handler binding。validator 在剥离注释和字符串伪证据后对照 `HandleWebRequest` 的 command resolver/domain fail-closed 分支、Host command map、AS2 可执行注册和 `TaskRegistry`，拒绝未登记 Host 命令、跨域重复 action/response handler、错误 action→cmd/receiver dispatch、未执行裁决路径或跨 handler 错绑。`callId/fid` 只作现役 transport correlation；`shopId/category/lease/token` 等领域身份仍由各 Task/AS2 校验，不进入第二份通用 identity 表。Hairdresser 作为真实无数值边界 domain 使用空 `numericFields/sourceChecks` 且不填 vector 占位。NPC `purchaseQuantity.interactionPolicy` 仍机器化固定 `purchaseLimit` 为 preview 输入硬上限、`maxPurchasable` 为直接提交与可见“可用”目标（事件 reason 保持 `maximum`）、不可提交意图只预览不写，以及 preview 在途采用 `visible-lock`；字段缺失、两类上限混用或回退到静默吞点击都必须由契约变异测试拒绝。C# xUnit 直接读同一份 fixture；NPC 与 KShop 固定覆盖 `1/99/100/101/4549/999999` 与非法 `0/1000000`，Crafting 保持固定 `1..99`。契约只约束跨层语义与技术边界，不替代 AS2 对价格、持有量、容量与存档的最终裁决。详细 ADR 见 [Web Panel 跨层契约与交互可靠性专项治理](../docs/Web-Panel跨层契约与交互可靠性专项治理-2026-07-22.md)。

凡 preview 改变可见本地意图，必须同时定义成功 checkpoint、迟到回包 epoch 隔离、普通读失败恢复、权威失鲜刷新和写结果未知 reconcile 五条路径；不得用单一 `error/busy` 布尔值合并。共享 Tooltip 的可见性由“有效 owner + 触发物/浮层复合 hover”决定；grace 结束后必须用真实命中状态复核空白终态，panel close/scope dispose 立即清理 owner、surface、timer 与 focus restore。浏览器回归必须同时用 pointer 和 pen 的真实 `PointerEvent` 覆盖复合过桥/快速划入空白，并为仍调用 `showAtMouse/hideHover` 的 legacy 消费者保留物理鼠标探针；直接调内部函数不能替代浏览器事件链。

NpcShop、Crafting 与 Hairdresser 的 Host transport lifecycle 统一组合内部 sealed `PanelPendingCallTracker<TContext>`。helper 只拥有 backend/Web callId correlation、pending/Timer、active/recent 去重、readiness/send、timeout、迟到/重复抑制和 clear/dispose drain；`TContext` 对它完全 opaque，command、payload、read/write、token、业务 verdict、`writeState` 与何种读可解除 reconcile 全部留在领域 Task。response、timeout、send-false、clear 与 dispose 都通过同一个原子 take 竞争唯一终态，callback 在 helper 锁外执行；`XmlSocketServer.TrySend(false)` 内部保守记为 `DeliveryUnknown`，Task 对现役 wire 仍映射 `disconnected`，且只由领域自己的 `IsWrite` 决定是否返回 `requiresReconcile`。`ClearPending()` / shutdown dispose 不伪造 Web 回包，但已开始的写必须进入领域 `needs_reconcile`；dispose 是 shutdown-only 终态，返回后拒绝新的请求入队，三条进程退出路径都显式 dispose 三个 Task。Web 继续使用独立的 `PanelRequestMux` 做 browser generation/session 隔离；NpcShop/Crafting 的普通 browser close 不直接 drain Host helper，而 Hairdresser 的生产 close observer 会显式 clear 其 pending 并保留未知写对账门。Skill/Loot 的 execution lease 与恢复机制不接入本 helper。

### 2.5 角色构筑会话、默认入口与双向导航屏障（2026-07-28 工作树）

角色构筑使用顶层 `panel=workbench`，以 `profile=battlebox,view=build` 进入同一 PanelHost instance；`build ↔ storage` 是实例内部切页，不重开 panel、不换 pause lease。Native HUD `EQUIP_UI` 默认先做 AS2 opener preflight，再进入该 Character Build；只有显式 `CF7_WEB_INVENTORY_WORKBENCH=0` 才回退完整旧装备 Hub。业务 wire 独立为 `domain=loadout`：只读/收束命令为 `snapshot/candidates/flushLive/statsSnapshot/finalize`，写命令为 `equipEquipment/unequipEquipment/equipDrug/unequipDrug`。AS2 `sessionGeneration`、Host binding epoch、browser generation 与 transport ready generation 是不同水位，任何一层都不得互相替代；旧回包、旧 ready 或 foreign instance 不能清当前 pending/dirty/reconcile。candidate 资格、11 个装备槽、4 个药剂槽、三条 revision 与写后签名均由 AS2 投影和复核，Web 不复制物品规则。

普通 close、ESC 与 backdrop 必须先经 exact CharacterBuild pre-close：排空写/对账，必要时一次 live flush，再由本地 `flushNow` 取得 terminal receipt；之后才能视觉关闭和释放 captured pause。NavigationStarting/socket detach 先立 recovery barrier，再按 exact generation 发送一次 `characterBuildRecoverDetach`；同一 ready generation 不重复发送，一个 recovery cycle 最多自动 retire 一次，第二次失败进入可见 `fatal_blocked`。Host 的 visual-retire 是拥有独立 callback 的 exact primitive：匹配当前 tracked lease 时负责关闭/释放，替换实例不得被误关；无 lease 时也只允许 exact visual，callback 只能在 Host visual 真正 idle 后完成一次。它不得借 `PanelClosed` 的二次调度、普通队列拒绝或 generic unpause 冒充终态证明。stale Character binding 与另一个 active panel 同时存在时，恢复必须先收束 visual ownership；绝不能先释放旧 pause authority 再留下仍显示的 foreign panel。

Character Build → Skills 是 Host-owned 的 exact 退场交接，不是 Web 内部切页。Web 只有在 Character Build 本地 finalize 已取得终态后，才可发送严格 close envelope `{type:"panel",panel:"workbench",cmd:"close",panelInstanceId,reason:"navigate_skills"}`；Host 必须验证 exact 顶层键集、当前 active workbench、同一 `CharacterBuildTask` binding、`CanRebind` 与无待恢复状态，并在 `BeginNormalCloseBarrier` 之前按 exact instance 武装一次性交接。随后仍执行普通关闭链：清理域内 return stack、Host visual-retire、AS2 `characterBuildRecoverDetach` 确认、持久化证明与 pause release。只有 `CharacterBuildTask.SetCoordinatorSettled` 在 binding/recovery 已清且 Host visual 真正 idle 后，才可原子消费该 one-shot；消费时必须先丢弃 recovery 窗口内积累的 deferred barrier open，再创建短期 typed Skill open capability `{origin,expectedSource:"nativehud",expectedView:"manage",openRequestId,baselinePanel,baselineInstance}` 并发送携带 `openRequestId` 的 `skillPanelOpen`。新 Host 请求必须携带严格 opaque token，AS2 在顶层 `panel_request panel=skills` 原样回显；Host 只有在 nonce/source/view/baseline 全匹配时才消费并经 `RequestOpenPanel → OpenSkillsPanel` 实际打开。Host 不得从这条交接直接调用 `OpenPanel("skills")`，Web 不得模拟 Native HUD，Character 与 Skills 也不得共享 session、revision、generation、watermark 或写状态。

这条交接与刘海屏 `SKILLS` 的业务能力相同：最终业务 initData 固定为 `{mode:"runtime",source:"nativehud",debug:false,view:"manage"}`，不含 `trainerSession` 或 `canReturnTrainer=true`，不创建、恢复或继承任何教师 session/learnToken。玩家只能管理自身已学技能、快捷栏与被动配置；学习/升级仍必须从世界 NPC 的独立 `source=world_skill_trainer,view=trainer` capability 进入。两者的展示来源不相同：只有 `origin=character_build` 且成功绑定 Host 预留 exact Skills instance 的 manage 页，才可额外得到只读展示位 `canReturnCharacterBuild:true`；刘海屏直开、教师页、教师派生 manage、stale/rebound/foreign instance 都不得得到。该布尔值不携带 capability，不能授权返回；真正的一次性能力只保存在 Host，并由 `PanelHost` 在生成 `panelInstanceId` 后调用的 init enricher 与 `SkillTask.BindPanelInstance` 精确绑定。

Skills → Character Build 只允许玩家点击显式“← 返回构筑”。Web 必须发送严格 envelope `{type:"panel",panel:"skills",cmd:"close",panelInstanceId,reason:"navigate_character_build"}`；右上角 `×`、物理 Esc、Host/native backdrop 继续发送普通四键 close 并回到游戏，绝不能隐式返回构筑。当前 Host 把物理 Esc 与 native backdrop 都折叠为 `panel_esc`，在扩展 Host 协议前不得假装 Web 能区分二者；Skill 内部已打开的帮助/确认模态和展开搜索先按本域顺序消费 Esc，只有没有更高层时才普通关闭。Web 可据 `canReturnCharacterBuild` 决定是否显示入口，并在本地写/对账状态非 idle 时禁用，但 Host 仍必须复验 exact active Skills instance、`view=manage`、无教师 return session、write idle、零 pending/queued reconcile/cleanup 后才能原子消费能力并武装反向 one-shot。

反向 one-shot 武装后仍先走 Skills 的普通 authoritative close：视觉退场、exact panel close observer、`skillPanelClose`、未知写对账与教师 cleanup 都不能跳过。真正重开 Character Build 必须同时满足两个彼此独立的 settled gate：Host 的 tracked Skills visual 已完全 idle，且 `SkillTask` 已解除 exact binding 并处于 `writeState=idle`、零 pending、零 queued reconcile、零 cleanup/backoff。idle manage close 不保证产生 coordinator-settled callback，所以完成检查必须同时由 visual-retire/`PanelClosed` 路径与 Skill coordinator settled 路径触发，二者竞争同一个原子 consume，恰好打开一次。仍有 active/foreign visual、竞争 panel、超时、navigation/socket/shutdown cancel 时只撤销 one-shot，不可提前打开 workbench。

Native HUD `EQUIP_UI`、Skills 返回构筑和前向失败回滚共用 typed workbench preflight。`openRequestId` 只对 exact tuple `{panel:"workbench",source:"nativehud_equipment",profile:"battlebox",view:"build"}` 有意义：新 Host 每次生成独立 token，并记录 `origin`、active panel/instance、PanelHost 已排队命令、已预留 owner/instance 及 idle/processing fence 组成的完整 baseline；AS2 只校验并在该 tuple 的顶层 `panel_request` 原样回显，Host 只在 nonce 与整个 tuple、baseline 全匹配时消费。其他 workbench source/profile/view、其他 panel、缺失/畸形/错误 nonce、迟到 A 命中后来的 B，或 active/queued/reserved/idle 任一水位变化都必须 fail-closed，且不得消费正确 wait。

workbench nonce 没有滚动兼容分支：新 Host 配旧 `asLoader.swf` 时，旧 AS2 回包缺 nonce 必然 fail-closed；旧 Host 也不得借新 AS2 的 token 行为宣称兼容。任何引入该合同的 Host 与 `asLoader.swf` 必须进入同一个 immutable candidate，绑定同一 build identity / payload closure 完成执行和 E2E，不能只替换一侧或用源码/xUnit/Flash 单侧通过宣称可滚动部署。

导航失败语义必须有界且不伪造成功。前向 Character 已关闭后，Skill preflight 的 send-false/timeout、admission/请求拒绝、Host 消费后的业务拒绝或 `OpenPanel("skills")` 返回 false，只允许尝试一次 `origin=skill_open_rollback` 的原生 Character Build preflight；能准入时以 fresh Character session 重建，不能准入、失败、超时或被竞争 panel 阻断时停止且只 toast 一次，引导玩家从“装备”入口重开，绝不能同时重复 rollback/toast 或形成循环。旧 timeout callback 在准备回滚前还必须复验 lifecycle epoch，并确认没有更新的 opener wait、导航或 Notch 用户意图；任一更新 intent 已存在时静默 supersede，不得用旧回滚覆盖新动作。反向 Skills 已关闭后若 workbench preflight 失败，不自动复活 Skills，只明确提示重试。所有 `OpenPanel`/rebind 返回 false 都必须记录 failed/rejected，不能继续写 `*_opened` 成功日志。跨 panel 后旧 DOM opener 已销毁，不能保存元素引用；返回或前向回滚成功时仅允许 Host 下发无权限的 presentation correlation（例如 `navigationOrigin` 与 `returnFocusAction:"skills"`），新 Character Build 完成首屏渲染后把焦点落到稳定“技能配置”动作 key。

Character one-shot 只允许存活于“exact arm → coordinator settled / exact cancel”这一小段；它不跨 `panel_request`。其后独立的 typed Skill open capability 只保存 presentation correlation，不携带 Character session/revision/watermark 或写权限，并在 exact manage 请求、send-false、timeout、Web navigation/热重载、socket disconnect、shutdown 或 competing panel 任一事件上单次消费/撤销。Skills→Character one-shot 同样不持久化、不跨 rebind，并在 exact close settled 后消费或由 timeout/navigation/socket/shutdown/competition 撤销。迟到、缺 nonce、错 nonce、`nativehud+trainer`、`world_skill_trainer+manage` 均由新 Host 拒绝且不能取消正确 wait；Character/Notch pending 期间到达的合法教师请求也不能抢占，教师 capability 只允许在无 manage preflight 且 Skills 尚未 active 时以 `source=world_skill_trainer,view=trainer` 独立进入。manage 已打开后迟到的教师 `panel_request` 必须拒绝并清理其 session；active Skills 内的 trainer→manage→trainer 只走 exact-instance panel-control rebind，不能用新的外部 `panel_request` 替换当前页面。畸形、stale、foreign 或重复 close 在关闭前拒绝；调制/Character close race、visual-retire 不可用或续接失败、Web navigation、fatal detach recovery 会按 exact instance 取消 Character one-shot，但不得释放或越过原 Character authority、pause 与 recovery fence。settled 时仍有 active visual 也只取消交接、绝不打开 Skills；若 one-shot 在最终原子消费前已被取消/替换，该 callback 返回未消费并保留 deferred-open 恢复权。

Web navigation/热重载、socket disconnect 与 shutdown 是 lifecycle cancellation barrier，不只是“清当前 timer”。barrier 必须先推进 cancellation generation/epoch，再清 one-shot、opener wait、queued command、reservation 与未绑定 init context；所有完成回调在创建下一段 wait 或调用 open 前都要复验该 epoch。相邻导航 intent 采用 latest-intent-wins：被更新意图取代的 callback 即使稍后到达，也只能 no-op，不能越过 barrier 重新排队或打开面板。

滚动部署只为 Skills opener 保留一条临时单向兼容：新 AS2 在 `skillPanelOpen` 参数对象存在但缺少 `openRequestId` 时，仍可为尚未更新的旧 Host 发出不带 nonce 的 `nativehud/manage`；显式畸形 token 继续零发送。旧 Host 可按既有路径打开“我的技能”，而新 Host 永远发送 nonce，且其 typed capability 对无 nonce 回包继续 fail-closed，因此这条分支不能被 Character 交接、教师请求或 foreign source 借用。它明确不适用于上述 workbench tuple；workbench 必须配对 candidate。待正式 Host 与 `asLoader.swf` 完成配对部署后删除 Skill 兼容分支；删除前必须保留“旧 Host 可开 manage / 新 Host 拒绝无 nonce / trainer 不得携 nonce”三类回归。

Character recovery 期间，loot admission 必须在预入队、execution lease 与 UI 执行三处 fail-closed。Web→Host 通用 task bridge 采用正 allowlist；`panel_request`、`*_response`、panel/agent/cursor control 等不得借普通 task 通道绕过 Router。受支持的启动链每次由 Guardian 创建并跟踪新的 Flash 进程，正常退出也终止该 tracked process；若 Guardian 自身崩溃并遗留持有旧 AS2 authority 的孤儿 Flash，当前系统不支持重新接管，必须重启游戏。不得为这个异常边界增加跳过 session/generation 的强制接管后门。

Native HUD 展开区“游戏”行固定七项：战队、平板、战备箱、情报、材料、技能、商城。`MATERIALS` 不复用 Character Build session，而是只在无 Web panel/Character authority 冲突时发 `openMaterialUI`；AS2 随后发送 `panel_request panel=crafting initData.view=materials`，Host 以固定 runtime initData 打开 Web 材料目录。旧 `__legacyMaterialOnly` flag 与旧物品界面“材料”帧不再属于入口链，也不保留发送/挂载失败 fallback。发送失败或已有活动面板时 fail-closed 并给出可见提示，不能把旧 Flash UI 叠在 Web 会话上。

当前工作树已实现 B0–B4 的协议、mutation、已穿戴调制、默认入口、材料隔离和关闭/存盘屏障，并在施工 Character Build ↔ Skills exact 返回、workbench nonce 与热重载/断线撤销；该表述只说明源码目标与工作树范围，不代表相关自动门已经更新，更不代表 candidate 已执行、游戏内 E2E、GUI 人工验收、promotion 或部署。现役英雄 smoke、完整退出/重启回读和七按钮实图仍按角色构筑专题与 [testing-guide.md](testing-guide.md) 验收。

### 2.6 安全退出的持久化与确认能力

安全退出不是 `SAFEEXIT → ForceExit`。显式 `SAFEEXIT` 先 Arm UI，再尝试投递 AS2 `safeExit`；投递返回 false 或抛异常必须进入 Failed，并同步 Web fallback 的 `safe_exit_failed`，不能停在 Saving。AS2 `SaveManager.flushNow()` 用 `sv:1` 表示本次尝试开始、`sv:2` 表示成功、`sv:3` 表示失败；禁存、已有 save in-flight、写入 false 或异常都必须得到失败终态，失败不得设置存盘成功标志，dirty 继续保留。重复重试仍要产生一组新的 `sv:1 → sv:2|sv:3`，不能被旧状态去重。

只有 Armed 且收到 `sv:2` 的 Done 状态才能签发一次 `EXIT_CONFIRM` capability；Router 必须调用 widget 的 one-shot consume 后才执行普通退出。raw、重放、未 Arm、Saving、Failed 或已消费的 `EXIT_CONFIRM` 一律拒绝。Failed 只显示取消/重试，重试只重新派发 `SAFEEXIT`；Done 无操作自动收起也不得退出。Ctrl+Q 等明确 emergency、Flash 僵尸进程和 fatal shutdown 是独立止损路径，不继承 Done capability，也不能被写成普通安全退出成功。

## 3. C# 接入清单

新增生产 panel 的 C# 最小接入面：

- `launcher/src/Tasks/*Task.cs`：NpcShop/Crafting 是两个冻结参考消费者，Hairdresser 是已落地的第三消费者，三者组合同一 `PanelPendingCallTracker<TContext>`；不得另建 pending map、timer、backend callId mux 或第二套 transport cleanup。领域 Task 仍独占 payload/response 白名单、写门和 reconcile 裁决。三个消费者只是组合式先例，不是通用基类或批量迁移授权；未来领域须先以真实生命周期证明同构，并在冻结 Web-only 的同轮删除旧 renderer/fallback 与重复 pending 机制，不能先抽象后找用途。
- `launcher/src/Program.cs`：创建 Task，注入 `WebOverlayForm`，传入 `TaskRegistry.RegisterAll`。
- `launcher/src/Bus/TaskRegistry.cs`：注册 AS2 response task，例如 `xxx_response`。
- `launcher/src/Guardian/WebOverlayForm.cs`：
  - Task 字段（如 `_petTask`）与 `SetXTask()` 注入方法。
  - `HandlePanelMessage` 覆盖所有 Web cmd。
  - `OnSocketDisconnected()` 始终逐 Task 触发生命周期清理；采用 F2 helper 的 Task 由自己的 `ClearPending()` 委托 helper drain，不让 `WebOverlayForm` 直接依赖 helper，也不保留 Task/helper 双轨 pending。两种形态都必须在断线时清 pending，防止旧回包错配新会话。
  - `ResolvePanelCloseGameCommand()` 明确 close 是否通知 Flash。
- `launcher/CRAZYFLASHER7MercenaryEmpire.csproj`：当前 SDK-style 会自动包含 `.cs`，但迁移时仍要确认构建清单没有旧式残留假设。
- `launcher/tests/Tasks/*TaskTests.cs`：至少覆盖断连错误、cmd→action、Flash 回包重写、unsupported cmd；采用共享 helper 的 Task 另固定 ready=false、read/write send-false 与 timeout、active/recent duplicate、重复/迟到 response、response-timeout 单终态、`ClearPending()` / `Dispose()` drain 与 shutdown 后不复活。

禁止只新增 JS 和 AS2 service 而漏 C# 分发层。C# build 通过也不代表协议能到达 AS2，必须有 Task 级测试或游戏内验证。

## 4. AS2 接入清单

AS2 侧修改必须遵守：

- 新增 / 重建 `.as` 必须 UTF-8 with BOM；优先复制现有 `.as` 改名保留 BOM。
- 新增 boot 期 `.as` 入口：asLoader.xml 已塌成单帧 `#include _collapsed_frame.as`（见 [docs/asLoader-README.md](../docs/asLoader-README.md)），不再直接改时间轴。内容接入现有 live source；确需新增顶层 source 时只向生成器唯一 `BOOT_SOURCES` 表增加一行，不另建 frame / stage 清单。运行 `node tools/assemble-collapsed-frame.js` 后必须再跑 `node tools/assemble-collapsed-frame.js --check` 与 `node tools/check-bom.js`；根 `frameNN.as` exact-match、输入 BOM 和字节级生成一致性均为严格门。S0 / S5 / S9、异步与控制行为、S7 杂项加载顺序归 `BootSequencer`；被引用的 class 自动嵌入，无需手动 include。
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
- close 按钮、ESC、backdrop click 必须进入同一 `onRequestClose(reason)`，先把 exact owner 的关闭意图通知 Host；只有 Host 返回 authoritative close/force-close 后，`Panels.close()` 才先清 visual/owner 状态并调用幂等 `onClose`（强关另调用 `onForceClose`）。不得先本地销毁再发送，也不得因清理 callback 或 `Bridge.send` 抛错把 Overlay 留在半关闭状态。
- 任何 async callback 返回时要校验 session，避免旧面板回包污染新会话。
- 用户可输入文本进入 `innerHTML` 前必须 escape；优先用 `textContent`。
- 超长 tooltip 不得只写 `overflow:auto` 却让浮层 `pointer-events:none`。共享 `PanelTooltip` 把触发物与浮层作为复合 hover 区：pointer leave 使用短延迟 `hideHover()`，进入浮层可滚轮读取；`bindAsync` 同时让焦点触发物用 `PageUp/PageDown` 滚动、`Esc` 关闭。确定性生命周期仍立即 `hide()`；若浮层未来出现按钮/链接，必须升级为可聚焦 popover/dialog，不能继续冒充 `role=tooltip`。
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
| NPC/KShop/Crafting/Hairdresser 命令或数值边界 | `node tools/validate-panel-contracts.js` + `node tools/test-panel-contracts.js` + 适用领域的 shared contract vectors harness/xUnit；Hairdresser 不填占位 vector，另跑 `node tools/run-hairdresser-harness.js`；production policy 必须通过 `panel-cross-layer-contracts` |
| 共享 Tooltip / hover 生命周期 | `node tools/run-kshop-harness.js`；必须包含 pointer + pen 真实事件、复合过桥、空白终态和 legacy `showAtMouse/hideHover` 物理探针 |
| AS2 service / include / gameCommand | `scripts/compile_test.ps1` 的 fresh trace / fresh Output Panel 副本，或说明 IDE 复核状态；必须明确证据类型 |
| 写存档 / 金钱 / K点 / 背包 / 伙伴 / 宠物 | 游戏内端到端手测 + 回读存档状态 |
| 文档入口、协议、验证入口变化 | `node tools/validate-doc-governance.js` |

已退役 S0 的旧 xUnit、Node、Browser、Flash 与 candidate 记录只作历史审计，不再是当前迁移门。当前地图网格箱只认可最终 tree 上的 map-loot TestLoader、Host/Web loot 门、代表性 E2E 与正式发布证据。

无人值守入口遵循“受控直达 + 真实入口小门”双轨：

- 受控直达只可绕过旧 Flash 按钮查找；它必须从窄化 `agent_control` 动作进入正式 AS2 opener，再经 `panel_request`、Host 白名单、PanelHost 与领域 Task。不得直接开 Host/Web panel，也不得用 `/console` 调业务读写。迁移功能进入人工反馈期后，不得继续保留仅供测试环境切换的独立 feature flag/capability 分支；但尚未冻结为 Web-only 的其他领域，旧 AS2 入口可以按正式 `source` 语义有意保持服务化原生 renderer，而 Web 反馈面仅由另一个正常工作台入口进入。该隔离不是调试开关：两条路径必须共用领域服务，Host 在未放行切流前应 fail-closed 拒绝残留 legacy redirect；人工验收门通过后再单独裁决是否把旧入口切到 Web。**已明确冻结为 Web-only 的迁移（当前包括地图网格箱与基地理发店）不适用这条双入口规则：不得保留 legacy renderer、fallback 或对应专项；地图箱的 direct/break 是独立掉落语义，不是 UI 回退。**
- 动作必须绑定专用 `cf7_agent_*` 克隆槽、当前 attempt/save runtime ack 与本轮新鲜 handoff；live slot、旧 attempt 或未 ready 均应零发送。受控进档顺序固定为：记录本次 `start` 日志水位 → 在该水位后同时取得 fresh handoff 与真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`（watchdog 事件不计，缺失报 `title_frame_not_observed`）→ 仅调用一次 `agentEnterResolvedSave()` → helper fail-closed 调 `_root.notifyGameEntered()`，同包发送 attempt-bound `s:1|ga:<_bootstrapAttemptId>`，再以 `gotoAndStop` 进入“读盘”帧 → Host 排除 legacy 无 `ga` 包、将 receipt exact 绑定当前 attempt，且只有该 receipt 才设 `gameEnteredObserved=true` → runtime ready。每次 `start` 与后续 `s:0` 都重新加锁；裸 `s:1`、helper 已调用、watchdog 或 `revealPerformed` 均非成功证据。
- 直达 runner 可以只负责正式 opener、active instance 与首个权威 snapshot 的只读入口门；若它声明会继续执行 preview/commit/reconcile/存盘/重启回读，则必须显式列出写入 fixture、命令和回读证据，不能从 snapshot 推导业务写闭环。尚未冻结 Web-only 的领域可给旧 AS2 入口、Web 正常入口与故障边界保留限时专项；Web-only 地图箱与基地理发店只测 Web 成功或 fail-closed，不再测试 Flash fallback。入口搜索超过 60–90 秒或两次截图即停止并记缺陷，不让导航失败吞掉整轮验证时间。
- `agent_control` 的“已请求打开”不是业务成功；runner 至少等待 start 水位后的 fresh handoff 与真实 title-frame marker、随后单次 helper 的 exact-attempt game-enter receipt、runtime ready、Host active panel instance 及该实例首个领域 snapshot，才可继续。

结束汇报必须区分：

- 已跑 C# build。
- Launcher 当前状态、实际 Core 路径、build identity / payload closure；未到 `standard_entry_verified` 时明确写“未部署 / 未正式验收”。
- 已跑 xUnit。
- 已跑 Web harness / Node QA。
- 已取得哪一种 Flash 证据：fresh trace / fresh Output Panel 副本 / IDE 复核。
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
验证：build / xUnit / harness / Flash fresh trace 或 fresh Output Panel 副本（明确类型）/ IDE 复核 / 游戏内手测
Launcher 状态：compiled / candidate_built / candidate_executed / e2e_verified / promoted / standard_entry_verified；实际 Core 路径与身份
未验证：明确列出
文档：已更新的 canonical doc 与巡检结果
```

若缺上述任一种 fresh Flash 行为证据（或 IDE 复核）或游戏内手测，必须显式说“未做”，不能用 C# build 或 Web harness 替代。
