# AS2 UI 到 Web Panel 迁移护栏

**文档角色**：AS2 UI 迁移到 Launcher Web Panel 的专题 canonical doc。
**最后核对代码基线**：commit `b852c0eba1`（2026-06-17）；物品工作台 profile 路由另核对 2026-07-11 工作树。

本文用于所有“旧 Flash / AS2 UI 迁移到 Launcher WebView2 panel”的任务。它不是普通前端开发指南，而是跨 AS2、C# 总线、Web panel、Flash CS6 编译链的稳定性护栏。凡迁移旧 UI、替换运行态入口、扩展 panel 协议、把 dev harness 推向生产，都必须先读本文。

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

`checkoutPreview` 只接受 `{v:1,cart:[{idx,qty}]}`；AS2 按当前 `_root.kshop_list` 重解 item/价格/等级，装备单行上限 1、可堆叠行上限 999，并用 `ItemUtil.require` 做整单无副作用容量预检。预览逐行返回 `maxAffordable/maxByCapacity/maxPurchasable`，整单返回余额、总价、预计余额、`canCommit/blockingError` 与单次 token。`checkoutCommit` 不再信任 Web cart，只消费缓存 plan 并重新解析当前目录、余额与容量；复核成功后先由 `ItemUtil.acquire` 全量计划并交付，再扣 K 点、清空恢复影子并强制存盘。余额或容量不足零写，`balance == total` 合法。未知/畸形/超时 commit 仍进入 `needs_reconcile`，只允许 `bulkQuery + inventory snapshot` 对账，绝不重放 token。`_root.商城已购买物品` 和 legacy `shopCheckout/shopClaim` 保留存档/旧 Flash 兼容，但新 Web 只展示并领取既有历史记录，不再新增。

NPC 金币商店使用独立 `npcshop` domain 与 `NpcShopTask`，不复用 K 点商城 `ShopTask`，也不把买卖硬塞进通用 `InventoryTask`。左栏固定 NPC 目录；右栏顶层是并列的背包与收集品 owned View，收集品内部再切材料/情报，其中情报只读。wire 仍保留 `bag/material/intelligence` 三份权威 snapshot，不因 Web 复合层级合并 AS2 容器：

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `npcShopSnapshot` | `NPC商店WebView.executeSnapshot` | `npcshop_response` | `panel_resp domain=npcshop cmd=snapshot` | `NpcShopRequestMux` callback | 读 |
| `tooltip` | `npcShopTooltip` | `executeTooltip` | `npcshop_response` | `panel_resp domain=npcshop cmd=tooltip` | tooltip callback | 读 |
| `tradePreview` | `npcShopTradePreview` | `executeTradePreview` | `npcshop_response` | `panel_resp domain=npcshop cmd=tradePreview` | 二级结算页 callback | 读；铸造单次 trade token |
| `tradeCommit` | `npcShopTradeCommit` | `executeTradeCommit` | `npcshop_response` | `panel_resp domain=npcshop cmd=tradeCommit` | 二级结算页 callback | 背包/材料 + 实际买入容器 + 金钱原子写 |

KShop `bulkQuery.catalog[]` 与 NPC shop `snapshot.catalog[]` 的自动分类投影固定包含 `majorType/use/actionType/weaponType`：它们分别来自物品现有 `type/use/actiontype/weapontype`，Web 只据此建立 `大类 → use → 武器子类` 的互斥浏览树，不读取 XML 文件名、不复制物品定义。KShop 另保留 JSON entry 的 `type` 作为策划专柜名；NPC 人工 `layout.sections` 作为同等的策划专柜来源。两者都以“类别 / 专柜”两个一级入口并存，专柜不得覆盖或伪装成自动物品大类。NPC 未配置 sections 时只呈现自动类别；未知自动字段只能进入“其他”，不得过滤掉商品。以上展示投影不参与价格、购买落点、可售性或提交复核。

NPC 商店主页面只维护待购/待售意图，不直接改存档；二级结算页把 `{catalogIndex,quantity}` 与 lease-bound sale source 交给 `tradePreview`。精确出售使用 `scope=slot + quantity`；同名批售只允许背包 seed lease + `scope=same_name,policy=plain_only`，物品名、匹配范围、合格实例与强化/进阶/带插件保护数量由 AS2 扫描，Web/Host 不接受客户端 itemName 或价格。AS2 必须在批售展开后再按真实 `entry.identity` 全局去重，禁止同名批售与逐格出售重复结算同一槽；多个售出装备返还的同名插件必须先聚合数量再交给 `ItemUtil.acquire`。不可堆叠装备复数采购在 AS2 计划中展开为多个 `{name,value:1}` 独立实例，禁止把数量塞进单件装备的强化值；预览逐行返回 `purchaseLimit/maxAffordable/maxByCapacity/maxPurchasable`，整单返回 `requiredSlots/availableSlots/missingSlots`。价格、口才折扣、情报门槛、可售性、买入真实落点、容量与最终金钱变化全部由 AS2 重算。预览返回 opaque `tradeToken`、权威明细、买卖总额、预计余额与阻塞原因；`tradeCommit` 在同一次事务中复核余额、商品、引用、普通装备保护条件、槽位、数量和价格，允许所选售款抵扣购买，也允许售出腾出的背包格被同笔购买使用。令牌单次消费，提交失败不得留下部分出售；内部 inventory/ref 不得进入 wire。旧 `buy/sell/batchPreview/batchSell` 只保留 Flash 兼容入口，其中 legacy `buy` 装备仍限单次 1 件；新 Web 不调用。`NpcShopTask` 与 Web 均采用 `idle/write_pending/needs_reconcile`：超时、断线、发送失败、未知结果或畸形写回包后只准新发结构完整的 snapshot 对账，绝不自动重放 `tradeCommit`。Host 将畸形回包规范化为 `error=malformed_response, requiresReconcile=true`，旧 snapshot 回包不得解除仍在途的写门。

`inventory_full` 时结算页可进入嵌入式“背包—战备箱”整理子路由，但不得给 `npcshop` 新造库存写协议：它必须复用 `domain=inventory` 的 `InventoryCoordinator`、slot lease、`autoTransfer(mergeThenEmpty)` 与战备箱剧情可访问容量。返回结算前重新请求 NPC shop snapshot、按真实槽位/名称重绑仍存在的待售意图并重新 `tradePreview`；已移动且无法安全重绑的精确待售项必须移除并提示。采购意图以稳定 `catalogIndex` 保留。首轮不支持直接购买到战备箱。

`_root.UI系统` 是跨帧共享服务命名空间。任何后置 UI 初始化都必须使用 `_root.UI系统 = _root.UI系统 || {}` 或只补具体成员，禁止 `_root.UI系统 = {}` 整对象重置；否则会静默抹除早期注册的 Panel 服务，表现为 Host/Web 面板已打开但 snapshot 永不回包。迁移新增早期服务时，TestLoader 必须按实际 include/帧顺序加入“后置初始化后引用仍相同”的回归断言。

snapshot 请求的 `filterKey=all|weapon|armor|consumable|material|other` 由 C# 严格枚举后交给 AS2；带 `filterSpec` 时 Host 与 AS2 都必须校验映射一致（`collection → other`，其余 major 与 `filterKey` 同名），禁止接受“回显武器路径但实际走 all 分支”这类矛盾请求。AS2 必须扫描容器权威范围再分页，返回匹配项 `viewCapacity`、真实 `physicalSlot` 与 slot lease，禁止 Web 只筛当前页。背包、仓库和战备箱共用权威树筛选与权威整理组件；目录与背包的 Web 交互统一为行内单层 drilldown，武器不得截断 `use → actionType/weaponType` 第三级。纯 Web `displaySort` 已退役，未筛选窗口保持 `physicalSlot` 顺序，真实重排仍只经上述写闭环。`filterFacets/filterItemCount` 缓存命中前必须核对可访问前缀的槽位对象引用，并在 inventory-domain 写入时主动失效，确保拾取、购买、出售与跨容器移动后不会返回陈旧分类。战备箱 snapshot 同时返回物理 `capacity=400` 与剧情权威 `accessibleCapacity=0..240`、`pageSizeHint=40`；Web 分页与筛选只允许使用可访问前缀，`sortAndMerge` 也只重写该前缀并逐槽保留 240..399 锁定区。旧 Flash `计算战备箱总页数` 调用同一 AS2 权威函数，禁止在 JS/C# 复制主线、挑战或基建解锁公式。

`autoTransfer` 不接受目标槽位：Web 只提交 lease-bound `source`、`targetContainerId`、固定策略 `mergeThenEmpty` 与用于回显/重铸 lease 的当前 `windows`。AS2 在目标完整可访问范围内先找同名数字堆叠、再找首个空槽；目标已满时保持来源与 dirty 状态不变，绝不自动交换异类物品。`windows` 不能影响实际落位，也不能把仓库强制跳到真实目标页。宿舍 `warehouse` profile 首批开放 Ctrl+单击与“快速存入/快速取出”常驻模式；Web 队列最多 24 项并严格单飞，未发送项可再次点击取消，超时、断线、stale 或不确定提交必须停队并对账，不重放未知写入。

世界内入口统一调用 AS2 `openInventoryWorkbench({profile,source})`，发送 `panel_request panel=workbench initData.profile`；C# `LauncherCommandRouter` 再做一次 `warehouse|battlebox` 白名单并重建固定 runtime initData。XFL 不得直接传 `containerId`、容量或任意 `initData`。宿舍入口在 Launcher 不可用或发送失败时才回退旧 Flash 仓库 MovieClip；真实仓库不得重新暴露给商城或通用 HUD。

检查点：

- Web `cmd` 必须进入 `WebOverlayForm.HandlePanelMessage` 的 case 列表。
- C# Task 的 action 字符串必须与 AS2 `gameCommand` 分发一致。
- AS2 `task` 回包名必须与 `TaskRegistry` 注册名一致。
- C# 回包必须恢复 Web 原始 `callId`，不能把 Flash 内部 `fid` 泄漏给 JS。
- JS callback 必须在成功、失败、关闭时清理 pending / busy 状态。

战宠与佣兵迁移暴露过两类典型断链：Web cmd 没进 `HandlePanelMessage` 导致静默丢弃；AS2 委托其他 service 后回包 task 名不匹配导致 tooltip / 写操作永远收不到响应。新增 panel 时优先防这两类问题。

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

- 正式模块位于 `launcher/web/modules/`，不是只在 `dev/`。
- `Panels.register(id, ...)` 或懒注册表 `panels-lazy-registry.js` 已接入。
- `onOpen` 初始化 session、pending、busy、runtime snapshot。
- `onClose` 清理 pending、busy、timer、tooltip、hover、DOM 订阅。
- close 按钮、ESC、backdrop click 必须最终触发同一套本地 close 清理，再通知 C#。
- 任何 async callback 返回时要校验 session，避免旧面板回包污染新会话。
- 用户可输入文本进入 `innerHTML` 前必须 escape；优先用 `textContent`。
- 运行态 WebView2 是游戏 UI renderer，不是文档浏览器：Overlay 统一加载 `css/game-ui-behavior.css` + `modules/game-ui-behavior.js`，默认抑制文本选取、原生 `dragstart` 拖影与 `contextmenu`；真实编辑器只通过 `input/textarea/contenteditable/[data-browser-native]` 显式放行。不要在各 panel 重复绑一套互相冲突的 `selectstart` handler。
- 固定 1024×576 设计画布走 `.panel-scale-shell + PanelScale` 时，生产 CSS 必须为对应 `data-panel` 声明 `#panel-content { inset:0 }`；否则会静默继承通用 `4% 6%` 卡片内缩，在任何分辨率下都浪费一圈可用空间。dev harness 不得用全局 `#panel-content{inset:0}` 遮掉这项生产约束。
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

| 改动面 | 必跑 |
|--------|------|
| C# Task / router / PanelHost | `launcher/build.ps1` + `launcher/tests/run_tests.ps1` |
| Web module / CSS / harness | 对应 browser harness 或静态 QA；没有入口时先补入口 |
| AS2 service / include / gameCommand | `scripts/compile_test.ps1` fresh trace，或说明 IDE 人工复核状态 |
| 写存档 / 金钱 / K点 / 背包 / 伙伴 / 宠物 | 游戏内端到端手测 + 回读存档状态 |
| 文档入口、协议、验证入口变化 | `node tools/validate-doc-governance.js` |

结束汇报必须区分：

- 已跑 C# build。
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
未验证：明确列出
文档：已更新的 canonical doc 与巡检结果
```

如果缺 Flash fresh trace 或游戏内手测，必须显式说“未做”，不能用 C# build 或 Web harness 替代。
