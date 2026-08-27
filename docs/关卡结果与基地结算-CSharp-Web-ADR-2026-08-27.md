# 关卡结果与基地结算 C# / Web 分层 ADR

**文档角色**：关卡结束、玩家死亡复活、返回基地与关卡奖励领取的跨 AS2 / C# / Web canonical 深文档。
**状态**：IMPLEMENTED / AUTOMATED_GATES_PASSED / HUMAN_ACCEPTANCE_PASSED / promoted
**决策日期**：2026-08-27
**实现边界**：维护者已确认 A3 隔离候选体验有效；与 A3 Core 逐字节相同的正式 runtime 已完成双 signer / 双 faultDomain 共识、原子 promotion、部署推送与远端 Audit。部署后的无 candidate 入口只确认 `formal_runtime`、exact identity/closure、bus ready、正常关闭与零新增残留；因为未选择存档，预热按 deadline 安全回收 Flash，未取得 fresh `bootstrap_reveal_ready`，因此不称本功能业务或完整正式入口 `standard_entry_verified`。

## 1. 决策摘要

本功能拆成两个生命周期不同的界面，不再让旧 Flash `关卡结束界面` 同时承担死亡、胜负、转场和奖励领取：

- 关卡仍在运行时，由 C# `StageOutcomeTask → RightContextWidget` 把死亡、复活、胜负、返回基地与任务交付捷径投影进常驻 HUD 已有的右上条件状态槽。它不暂停 Flash，也不创建新的浮窗；玩家忽略该条即可继续探索。
- 返回基地并且人物场景 ready 后，由 Web `loot` 工作台以 `sourceKind=stage_settlement` 展示行动报告和待领奖励。普通 Web Panel 继续由 `PanelHost` 暂停 Flash。
- AS2 `StageRunSession` 独占关卡会话、胜负/生命双状态、30 FPS 帧时、击杀与物资获得/消耗事实、复活币事务、返回基地与奖励一次性随机化。
- AS2 `LootContainerService` 独占奖励 inventory、claim、revision、lease、悬挂、放弃与终态；C# 和 Web 都不能自行增删玩家资产。
- 设置页“尝试复活”与 C# 卡片的复活按钮调用同一个 `StageRunSession.requestReviveLocal`，不再依赖旧 Flash 复活弹窗。

旧 `sprite/悬浮UI/Symbol 1861` 只保留在 XFL 作为归档素材。现役死亡检测、关卡成功/失败和 respawn 不再调用其 `询问复活/关卡结束/关卡失败/使用复活币`。

## 2. 状态与权威

胜负和生命是正交状态轴：

```text
outcome = active | victory | failure | retreat
life    = alive  | dead    | reviving
```

因此以下组合都合法：

- `victory + alive`：通关后可忽略常驻决策条继续探索；
- `victory + dead`：通关后死亡，仍可复活或返回基地；
- `active + dead`：中途死亡，可复活或撤离；
- `failure + alive/dead`：失败结论不会被后续复活覆盖。

奖励生命周期独立为：

```text
none → prepared → web_active → rewards_pending → web_active
                              └→ claimed | abandoned | error
```

`prepared` 之前不允许销毁战斗场景；`claimed/abandoned/error` 才释放冻结的奖励引用。奖励未终结时，所有现役关卡入口和 `StageManager.initStage` 后置门都拒绝开始新关卡，避免新会话覆盖唯一奖励对象。

| 事实或动作 | 唯一权威 | C# / Web 职责 |
|---|---|---|
| outcome、life、关卡名/难度 | `StageRunSession` | 严格校验并展示 |
| 通关时间 | `StageManager` 未暂停 tick，固定 30 FPS | 格式化，不读取现实时间 |
| 击杀与头像身份 | 现役 `_root.发布击杀播报` 的同一规范化投影 | Web 解析 static portrait 或受限 doll tuple |
| 拾取、获得与物品消耗 | 现役 `_root.发布物资变更消息` 在领域提交后的同一规范化投影 | Web 按 gain/loss 聚合展示，不把播报当资产写入 |
| 能否复活、扣/退复活币、respawn | `StageRunSession` + `ItemUtil` + `RespawnEventComponent` | 只发送带 run/revision 的意图 |
| 返回基地与奖励随机化 | `StageRunSession` | 只发送意图 |
| 已完成任务与交付目的地 | `MapTaskNpcRegistry` + `MapPanelService` | C# 只消费 `tdr` 可路由事实，不携带或猜测目的地 |
| 奖励领取、容量、悬挂、放弃 | `LootContainerService` | Host 严格桥接，Web 发受限命令 |
| 背包/战备箱整理和丢弃 | 既有 Inventory authority | Web 复用现役 organizer |
| 材料存量 | `MaterialArchiveProjector` 只读投影 | Web 搜索与展示，无写能力 |

## 3. C# 原生层挂载与层级

`StageOutcomeTask` 不再拥有独立 HWND；它把严格校验后的 `StageOutcomeState` 交给现役 `RightContextWidget`。后者已经挂在 `GuardianForm.FlashHostPanel` 对应的 `NativeHudOverlay`，并通过 `RightHudLayout` 使用 Flash `1024×576` 逻辑画布、右上动作行与小地图共用的坐标/缩放真源。关卡决策只占动作行下方既有的 `252×32` 条件状态槽，关卡内不提供“完整/紧凑”；该选择只属于返回基地后的 Web 工作台。

状态槽继续复用常驻 UI 的 `NativeHudTheme`：同一黑底、直角 device-pixel 框、分隔线、字体基线和 cyan/gold/danger 语义色。重伤、复活中、胜负与待领奖励都压成一行；只有右侧精确按钮矩形拥有命中，剩余条带不会形成覆盖游戏的大命中区。由于它与任务播报、小地图和六入口同属一个 NativeHud surface，不再存在独立窗口夺焦、额外 no-activate 消息栅栏或单独 z-order 上界。

右侧条件槽的唯一仲裁顺序为：

```text
stageDecision > transactionDecision > actionableNotice > contextHint > hidden
```

关卡决策到达时，已排队的普通任务/公告不会丢失，其 5 秒计时被冻结。胜负决策保持常驻，不提供会把返回入口一起隐藏的伪“继续”按钮：游戏没有暂停，玩家直接忽略该条就是继续探索。胜利且没有已完成、可路由任务时只显示“回基地”；AS2 投影 `tdr=1` 时显示“前往交付 / 回基地”，失败仍只显示“回基地”。同轮后续 `dead` 会切换成复活决策；复活币大数按 `9999 / 2.1万 / 1亿 / 1万亿` 一类有界格式绘制，避免动作文字越界。复活、返回基地、前往交付和继续领取都必须发送新的 `intentId` 以及当前 `runId/expectedRevision`。

NativeHud 原有 PanelHost 生命周期负责整体 suspend/resume，因此 Web 设置、库存或结算打开时，关卡状态仍可更新但不会浮在 Web 之上。socket 断开会清除该投影，重连后 `stageOutcomeSync` 向 AS2 请求当前权威快照。层级仍是 `native cursor > HitNumberOverlay > NativeHud / Flash`，本功能不抬高整个常驻 HUD。

## 4. 复活收口与旧故障处理

旧 Flash 按钮直接改写 HP，并且 `RespawnEventComponent` 在“关卡已结束”时把根时间轴跳回 `关卡结束`。这两条分叉会让“通关后死亡”的恢复路径与正常 respawn 生命周期不一致，也是本轮必须移除的风险源。

现役复活固定为：

```text
dead + exact current hero
  → life=reviving
  → ItemUtil.singleSubmit("复活币", 1)
  → hero.dispatcher.publish("respawn", hero)
  → RespawnEventComponent 恢复实际 HP/MP
  → StageRunSession.onHeroRespawn(exact hero)
  → life=alive
```

约束：

- `RespawnEventComponent` 的第一个形参就是目标单位；EventBus v3 的 scope 只绑定 `this`，不会把 scope 隐式注入形参。因此复活发布必须像 `ZeroHPDetector` 一样显式携带 `hero`。第一轮隔离候选的失败正是零参数发布导致监听入口拿到 `target=undefined`，异常被事务层捕获后退款并恢复 `dead`，于是玩家伏地且弹窗重现；现有 focused 门用真实 `EventDispatcher` 固定覆盖该生产分发形态。
- `RespawnEventComponent` 必须在恢复 HP/MP、动画与 TargetCache 的同一生命周期显式执行 `target._visible=true`。旧路径曾在英雄复活后无条件隐藏 MovieClip，形成“HP 已恢复、怪物可继续攻击，但玩家不可见”的半复活状态；C# 迁移后不能再依赖旧关卡结束时间轴替它恢复显示。
- 只有 `TargetCacheManager.findHero()` 返回的同一 MovieClip 且实际 `hp > 0` 才能清除玩家死亡；佣兵或敌人 respawn 不得误改 life。
- 重入时 `dead → reviving` 先发生，重复点击不能重复扣币。
- 禁复活、没有复活币、正在返回基地、hero/dispatcher 缺失均在写前失败。
- dispatcher 在实际恢复 HP 后才抛错时，以生命事实为准，不能错误退款并把已复活玩家重新标死。
- respawn 未生效时只经 `ItemUtil.singleAcquire` 返还本次复活币；无论退款是否抛错，life 都回到 `dead`，不得永久卡在 `reviving`。退款未得到 exact before/after 证明时返回具名错误，设置页提示玩家立即核对存量。
- C# 投影或 socket 发送异常不能越过 AS2 权威事务，不能中断扣币、退款、复活或结算终态。
- 设置页兜底不再“重新拉起旧弹窗”，而是调用同一共享事务；这直接覆盖用户反馈的关卡结束后死亡无法复活问题。

## 5. 返回基地与奖励一次性语义

所有 `_root.返回基地` 调用先执行 `StageRunSession.onReturnBaseStarted()`：

1. 活跃关卡按撤离冻结 outcome；
2. 胜利才读取 `_root.关卡可获得奖励品`，失败/撤离生成空奖励 inventory；
3. 一次性创建 4 列、8–64 格 `ArrayInventory` 和只读行动报告；
4. 冻结成功后才允许淡出、gameworld cleanup 与 `StageManager.clear()`；
5. 基地 `SceneReady` 后才把 inventory 交给 `LootContainerService.beginStageSettlement()`。

同一轮 `_returnRequested=true` 后的重复返回只作幂等确认。即使奖励已经 `claimed/abandoned` 且冻结引用已释放，也绝不能再次随机化该轮奖励。

奖励表非法行、未知物品、AVM1 `random()` 超过有符号 32 位跨度、超过 64 个奖励槽或 `BaseItem` 创建失败都 fail closed，并以 `rewardRollOmissions` 在报告中披露；不把遗漏项伪装成玩家已经获得。

“前往交付”使用 `return_deliverable` 意图，但不允许 C# 把 `hotspotId` 带回 AS2。AS2 在点击时先确认当前确有 `returnNavigable` 目标，再进入与“回基地”完全相同的冻结、转场和 Web 奖励流程；只有奖励到达 `claimed / abandoned / error`、Panel exact visual close 已完成且 `_webPanelPauseLease` 已释放后，`StageRunSession` 才重新解析此刻仍已完成的任务并调用 `MapPanelService.navigateToHotspot`。普通关闭形成 `LOOT_SUSPENDED` 时保留意图但不跳转，之后恢复领取并终结才继续；重复 close 证明不得重放导航。这样交付捷径不会绕过奖励权威，也不会在战斗场景或可见 Web 之下抢先切图。

## 6. Web 双栏工作台

关卡结算沿用 `panel=loot` 的现役 exact authority，但 admission 使用独立 `source=stage_settlement`，并额外携带严格报告：

视觉与关卡内原生卡分属两套已有真源：原生卡复用常驻 `NativeHudTheme`；返回基地后的 Web 结算复用 Launcher 首页与 Settings 的黑铁终端语言。`stage_settlement` 根单独挂 terminal skin，直接消费 `tokens.css` 的 `--launcher-* / --dls-* / --term-*` 及 `terminal.css` 的品牌铭牌/切角构件；黑底栅格、扫描线、锈红结构线、DLS 青主操作与骨金数字与启动器/设置保持同源。该 skin 不作用于 `map_chest`、普通库存或其他 Workbench。

- 左栏“行动报告”：在同一纵向滚屏里依次展示关卡、难度、outcome、关卡帧时、总击杀、最多 96 类敌人，以及物资获得/消耗；极端类型数由这一滚屏承接，不再用击杀/物资页签切断上下文；
- 物资记录复用领域提交后的现役物资播报投影，按 gain/loss 展示拾取、奖励、消耗等最多 96 种聚合事实及遗漏计数；断开 Native feed 不影响 `StageRunSession` 本地记录；
- “完整/紧凑”：复用一个 `GridDensityController`，全新偏好默认紧凑并同时作用于左栏敌人/物资卡、右栏奖励格和材料存量；紧凑档保留头像/图标、数量和 tooltip/ARIA 名称，完整档显示名称与明细；玩家选择按既有工作台偏好持久化；
- 敌人头像：有 doll tuple 时复用 `DollBake.renderTupleDataUrl`，并发上限 2、同 tuple promise 缓存；否则复用 `EnemyPortraits` 的 manifest/variant/fallback 链。头像内部不再放敌人名称首字作为 fallback；加载失败只显示中性占位，避免透明画像与文字叠印；
- 右栏在“待领取奖励 / 材料存量”之间切换；材料经只读 `materials` 命令获取 `MaterialArchiveProjector` 投影，默认展示持有项，搜索时可查看零库存；材料页上的 `Ctrl+A` 不得误触发领奖；
- “待领取奖励”中单击或 Enter 领取；`Ctrl+A/全部收取` 使用一次 `claimBatch` 跨 Web→Host→AS2 提交最多 50 个有序 exact lease，AS2 内部沿每件既有可恢复 journal 顺序提交并只在批尾重投影一次，不并发写；容量不足可跳过阻塞项继续领取后续可合并项，其他部分写异常必须进入 exact query reconcile；
- “库存整理”：在同一 Panel 内进入背包 ↔ 战备箱 organizer，可转移或丢弃已有物品，返回后重新查询奖励和材料；该子页明确复用 K 点商城跳入库存时的原始灰黑 `inventory` skin，不继承结算页的 Launcher/Settings 终端 skin；
- 普通关闭：提交 `LOOT_SUSPENDED`，保留同一 inventory，回到基地后由 C# 卡片提供“继续领取”；
- “放弃剩余”：显式确认后提交 `ABANDONED`，不可撤销；
- 全部处理：提交 `CONSUMED`，结束该轮结算。

地图箱 `source=map_chest` 的 8 键 admission、场景 anchor、拖拽/双击语义和关闭恢复合同保持原样；只有 `stage_settlement` 可使用 anchorless suspend 和材料只读命令。

## 7. 当前限制

- 待领奖励保存在当前进程内存权威中，不承诺 Launcher/系统崩溃后的跨进程恢复；在加入带存档 schema、幂等恢复和迁移策略的持久化前，不得宣称“崩溃不丢奖励”。
- 当前危险操作是一次性放弃所有剩余奖励，不提供逐奖励放弃；“全部收取”会先用单批请求收走所有可接收项，因此危险操作通常只作用于无法领取的剩余项。单批上限为 50，超过时由 Web 在上一批得到精确权威投影后再发下一批。
- 自动头像 harness 使用受控资源和浏览器环境；真实敌人 manifest、纸娃娃组合的构图与低分辨率可读性仍需人类验收。
- 32px 共用状态槽消除了独立结算卡对中央/底部立绘的遮挡面；真实关卡仍须覆盖窗口化、全屏、不同 DPI、按钮点击与普通任务播报恢复，不能把离屏位图视为最终验收。

## 8. 验证与发布门

当前自动证据包括：

- AS2 map/loot/stage focused：`53 + 151 + 9 + 88 = 301` 项全部通过，Compiler `0/0`、32K retry `0`；其中 StageRunSession 为 `88/88`，除以真实 `EventDispatcher` 锁定 `respawn` 必须携带 exact hero 参数外，还覆盖延迟交付意图在奖励终态、可见 Web、pause lease、重复 close 与最终重解析之间的顺序。
- Settings AS2：`42/42`，Compiler `0/0`、32K retry `0`。
- asLoader 精确 publish：Compiler `0/0`，`scripts/asLoader.swf` 刷新为 `1,161,797 bytes`、SHA-256 `BB7823F9FF61F1B390810A8AD46913159DDED0FEE2926186451B255B01CFDB97`；函数近墙门 `10,407` 项、最大 `48,921B < 60,000B`。FFDec `21.1.1` 导出 `621` 个脚本并以退出码 `0` 完成，定点确认 `StageRunSession.return_deliverable / onWebPanelClosed`、`MapPanelService.returnNavigable`、共享复活事务、`target._visible=true`、`lootClaimBatch` 和 `LootContainerService.beginStageSettlement` 已进入产物。
- C# StageOutcome/RightContext focused：`37/37`；Launcher 全量在 exact SDK `10.0.300` 下为 `4290 pass + 3 explicit opt-in skip / 4293 total`。
- Web：Loot browser `98/98`、lazy cancel `6/6`、state `57/57`、Settings functional `18/18`、Settings visual `116/116`、doll bake `9/9`、lazy closure `28/28`、panel lazy loader `17/17`、panel contracts `68/68`、Stage Select `53/53`、Tasks `63/63`；协议注册表为 `5` 个 domain / `31` 条 command、零错误。Workbench strict audit `0 error / 0 warning`，UI ratchet `67/67`，视觉 atlas `66/66`。

自动门只证明当前源码、mock browser 和 Flash focused 闭环。维护者先在第一版隔离候选确认底层复活功能可用，再于 A3 隔离候选确认最终交互有效；A3 为 `NOT_DEPLOYED`，Core SHA-256 `5B010C6040A5E80E1E8923FD02D6B632AB2D309511F8C6A54BA7D78B7516314F`、build identity `03F9825C2A2A248C73A7FA6FFB4E6C4305D49C4F97BD9E6042747B9BC5A0F5AA`、payload closure `5DA2B3053BF70EFCDCE74A503C33098774F9026AAD6E2D1F555C1A9EC5181D07`。以下项目继续作为正式入口与后续回归矩阵：

1. 活跃关卡死亡：扣一币、真实 respawn、继续操作；重复点击不重复扣币；
2. 通关后忽略常驻决策条继续探索再死亡：仍能复活，victory 不被覆盖；
3. 胜利/失败/撤离返回基地：目的地正确，结算只打开一次；
4. 重伤/胜负/待领奖励使用右上既有 32px 条件状态槽，不新增浮窗且没有完整/紧凑开关；只允许精确动作按钮命中，不抢焦点、不隐藏原生 HUD；胜负条保持常驻且不暂停，忽略即可继续探索，无可交付任务时只有“回基地”；打开设置/Web 后不穿透、不浮层；
5. 设置页“尝试复活”与原生按钮结果一致；
6. Web 首开默认为紧凑，完整/紧凑只在这里可切换并同时改变行动报告、奖励格和材料格；黑铁终端 skin 与 Launcher 首页/Settings 的品牌铭牌、栅格、锈红结构线、DLS 青切角操作一致，普通地图箱不被改色；左侧同一滚屏中的帧时、击杀、真实 static/doll 头像和物资 gain/loss 正确，右侧奖励/材料切换与搜索正确；
7. 单领、大量奖励一次批领、部分满背包、材料/情报/标量奖励、库存整理与丢弃正确；库存整理使用商城同源原始灰黑皮肤，批领无丢失、重复或逐项往返卡顿；
8. 普通关闭后“继续领取”恢复同一批奖励，明确放弃后不可恢复；
9. 奖励待处理时所有现役战斗入口可见拒绝，不覆盖上一轮；
10. 复活币至少覆盖个位、`20574` 一类万位数和极大合法值，确认缩略标签无截断、按钮点击区不变；
11. 已完成任务时出现“前往交付 / 回基地”，选择前者仍先完成基地奖励流程，普通关闭不提前跳转，最终领取/放弃并关闭后只导航一次；任务在结算期间失效或目的地不可达时安全停在基地；
12. 至少覆盖 `1024×576`、常用窗口尺寸与全屏/DPI，检查文字、点击区和低分辨率画像。

A3 在人工验收时达到 `e2e_verified / NOT_DEPLOYED`；其 exact Core SHA-256 `5B010C6040A5E80E1E8923FD02D6B632AB2D309511F8C6A54BA7D78B7516314F` 随后由 release source `732898b8aa1308cf820976324f47bba97f654e41`、不可变 tag `runtime-build-v2/20260827-stage-outcome-settlement-v2`、release tree `d498236a3ac06294f0c871dba73302bb24bc398e` 与 request `CB8268D83DB35DF3BC7D22587822F279C29A93CD12A15B1F10DF14759B000991` 进入正式列车。39/39 production receipt SHA-256 为 `977B2B2A7466C307198438C1F8362CE9ED06F3415977F664CB4E402B4192A181`；本地 X509 与 GitHub Hosted OIDC/Sigstore run `33070890481` 对 identity `03F9825C2A2A248C73A7FA6FFB4E6C4305D49C4F97BD9E6042747B9BC5A0F5AA`、closure `5DA2B3053BF70EFCDCE74A503C33098774F9026AAD6E2D1F555C1A9EC5181D07` 达成双签共识。deployment commit `339b15694d631d483736880c0dfd44429f6926a3` 已推送，post-promotion Audit run `33071572650` 明确输出 `state=promoted`、`deploymentChanged=true`。

无 candidate selector 的 `automation/start.ps1` 随后确认正式 Core、identity/closure 与 bus ready，并以 exact Guardian PID 正常关闭；本轮新增 Flash 与 WebView2 子进程、`launcher_ports.json` 均无残留。该次没有选择存档，预热在 45 秒 deadline 后以 Flash code 0 自行回收，未出现 fresh `bootstrap_reveal_ready`，也没有重跑复活、胜负、交付或奖励领取业务。因此准确状态是关卡结果与基地结算 `HUMAN_ACCEPTANCE_PASSED / promoted`；正式入口仅有身份、总线和正常退出的窄证据，不补写 `standard_entry_verified`。
