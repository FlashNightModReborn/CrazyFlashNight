# 关卡结果与基地结算 C# / Web 分层 ADR

**文档角色**：关卡结束、玩家死亡复活、返回基地与关卡奖励领取的跨 AS2 / C# / Web canonical 深文档。
**状态**：2026-08-29 增量修复 `IMPLEMENTED / AUTOMATED_GATES_PASSED / HUMAN_ACCEPTANCE_PASSED / promoted`
**2026-08-30 测试反馈修复状态**：`IMPLEMENTED / RELEASE_AUTHORIZED / FIELD_REVALIDATION_PENDING / NOT_DEPLOYED`
**决策日期**：2026-08-27
**既有发布基线**：2026-08-27 A3 正式列车保留为历史基线；下述 2026-08-29 增量现已由独立 release source、双 signer / 双 faultDomain、原子 promotion、部署推送与远端 Audit 取代其“未部署”状态。两轮部署后的正式入口证据都没有重跑关卡业务，因此均不称本功能业务 `standard_entry_verified`。

## 0A. 2026-08-30 奖励持久化、立即投影与自动入栏增量

测试员实际遇到了关卡结束后“前往交付”迟出、返回基地后奖励无法安全收取、焦点异常时不敢触碰推荐链路，以及领取药剂落入背包。此次增量冻结以下现役合同：

- `FinishStage` 递归完成较低难度任务时延迟中间投影，只在最外层立即执行一次 `UpdateTaskProgress()` 与达成检测；NativeHud 不再等待后续偶然刷新才出现“前往交付”。
- `StageRunSession.prepareSettlement()` 在离开战斗场景前把一次性随机结果、行动报告、remaining manifest、单调 `settlementId` 与有界 operation receipts 写入 `_saveExt.stageSettlement.v=1`。只有 `_root.强制存盘() === true` 才允许转场；false、异常或缺失均保留同一奖励和同一 id，只允许重试，绝不重新随机。
- `SaveManager.unpackGameState()` 在资产恢复后重建 pending settlement。`LootContainerService.beginStageSettlement()` 同时读取 durable receipts，复原 operation journal、`authorityRevision` 与 `lastAppliedOperationId`；receipt 的 revision、领取数量或 remainingCount 不连续时 fail closed，不把损坏记录冒充成功领取。
- 单领在成功回包前、批领在批尾、结算终态在释放内存 authority 前分别执行 strict durable flush。flush 未确认时保持 `LOOT_COMMIT_PENDING`，只允许同 operation 或 causal query 续跑；终态把 pending 清成有界 terminal marker 后与玩家资产同次落盘。
- Loot command 升为 v2，目标为 AS2 权威的 `自动`，活跃响应固定返回 loot、背包、药剂栏三份快照。药剂按“最近耗尽的同名 affinity 空槽 → 已占用同名药剂最低物理槽 → 背包同名栈 → 背包最低空槽”规划；从未绑定的新药剂仍进背包，不擅自占用空药剂槽。

当前明确留给维护者讨论而未擅自施工的两点：持续存盘失败时是否提供“放弃本轮奖励并返回”的不可逆出口；畸形或未来版本 pending settlement 是否允许游戏内 quarantine/repair。二者都涉及丢奖励或改写诊断证据，不能由自动修复替玩家决定。

最新 fresh focused 证据为 runId `db4724af9f5c4e35b9f7f87054ba70d2`：Loot `165/165`、Planner `9/9`、StageRunSession `372/372`，总计 `546 passed / 0 failed`，Compiler `0/0`、32K retry `0`；包含 `claim(rev2) → suspend(rev3) → resume(rev4) → claim(rev5) → restart` 的真实状态迁移夹具，并证明 receipt 以原始/剩余 manifest 的精确数量链防复制或跳领，非资产生命周期只允许造成 revision 单调跳号。Character focused runId `66b0b0cf3cf8451b9f7d5cd6506e40b0` 为 SaveManager `231/231`、CharacterBuild `211/211`；PlayerAsset runId `96774078d4884214ab1be55c447284a4` 为 `113/113`，两者均 Compiler `0/0`、32K retry `0`。

最终自动闭包另含 Equipment AS2 runId `1564380c6a0b458aad719b7664e286b1` 的 `88/88 + Inventory 170/170`、Loot/Equipment/PanelFocus focused xUnit `317/317`（focus 子集 `61/61`）、Launcher 全量 `4449 pass + 3 explicit opt-in skip / 4452 total`、Panel contract `68/68`、Loot Node `58/58`、KShop Edge `155/155`、Equipment Tuning model `82/82`、offline journey `9 suites`，以及三视口各 `147/147`。fresh asLoader publish 由新鲜 Output Panel 与 SWF 刷新证明；publish-only flashlog 未刷新，故不拿旧 trace 冒充行为证据。产物为 `1,200,109 bytes`、SHA-256 `6638A70485BBC79D950458D11F69FE738DC7D41604945F66A729DAA90B780107`、`10,683 functions`、最大 `50,215B < 60,000B`。

异构复核前的早期隔离候选曾达到 `candidate_built / NOT_DEPLOYED`：root `tmp/runtime-candidates/v2/c-4b3dfec54046-08846e81b3-20260830t011547732z-cb9d862b`，Core SHA-256 `173EA2F77DF0B3BEB4BFFEB1AAE679B7B34608E1D5434449F44EDADB2F287593`，build identity `4B3DFEC54046494CFCC627212586D72F447D7E6E67FCDA9276569D3032A4FEB9`，payload closure `9CBEE0CDEA19B3B28BDDE9DB0B53489E816207A56175E06241DE93E683B855F2`。它未包含随后发现的 settlement revision-gap 与 Host detached-query v2 修复，现已 supersede，只保留为历史证据；当前修复树在正式不可变 request 前准确状态为 `compiled / NOT_DEPLOYED`。这些机器证据都不代签 QQ/直播前台切换、实际关卡返回、领取后重启读回或人类观感。

2026-08-30 维护者明确授权本增量进入不可变 source tag、双 signer / 双 faultDomain 共识与原子 promotion。开发机环境较干净，无法稳定制造 QQ 截图、直播工具或外部弹窗抢前台的现场；因此不伪造本地焦点验收，而是将该旅程记为 `FIELD_REVALIDATION_PENDING`，由测试员的实际软件环境回报收束。供应链发布授权不等于 `e2e_verified`、`HUMAN_ACCEPTANCE_PASSED` 或 `standard_entry_verified`；领奖重启读回、战斗空调制关闭和血瓶三来源回原槽同样保留为首轮现场回归项。

## 0. 2026-08-28 地图绕行、焦点与转场增量

测试反馈证明旧实现允许胜负终态仍从地图 Web 直接导航：AS2 已判定玩家留在战斗关卡，地图却把 `navigate/open_stage_select` 当普通热点动作发出；随后 Flash 已切到基地房间，而 `StageRunSession`、右上关卡决策和 NativeHud 手势仍保留战斗生命周期，形成“地图已离开、右上条残留、人物输入像失焦”的跨栈裂缝。帧率图继续变化只说明渲染循环仍在，不是卡死或性能归因。

本增量冻结以下合同：

- `StageRunSession` 是所有关卡开始、结束和返回基地的唯一会话权威。地图在活跃/结算中的关卡仍可打开和阅读，但 `navigate` 与 `open_stage_select` 必须显示锁定原因并零发送；选关、难度、任务直达、竞技场/外交入口、旧入口及新建角色转场都先取得 exact reservation，再允许首个破坏性写入或淡出。异步加载统一采用 pending → exact commit；失败、supersede 与迟到回调不能消费新请求。
- `_root.返回基地` 只有淡出成功后才清 `StageManager` 与战斗标志；淡出同步异常回滚 `新出生/场景进入位置名/关卡类型` 并保留可重试会话。HP/MP、限制、HUD 与 BGM 是 best-effort 投影，任一异常不得阻断同一次淡出。`_root.关卡结束` 先提交 outcome，视觉异常也不得阻止真实 `FinishStage` 恰好一次。
- NativeHud 按下时冻结 exact widget/action/revision；release 只接受同一命中。suspend、hide、owner/session 变化、capture loss 或在按钮外释放都取消手势，不能把地图卡拖到关闭、把旧 revision 的“回基地”重定向到新按钮，或在恢复后补发旧点击。
- Web Panel 关闭只在“关闭开始时 CF7 在前台”且“恢复前再次读取到 CF7 仍在前台”时恢复 Flash 焦点。玩家在关闭期间切到 QQ、浏览器或其他窗口时必须 fail closed，不得由延迟回调抢回前台。
- `remaining=0` 只在 `sourceKind=stage_settlement` 且存在有效冻结行动报告时允许进入 `LOOT_SUSPENDED`，以便零奖励结算仍可展示/关闭；地图箱零剩余继续拒绝，不能借空结算绕过 source/anchor authority。
- Stage Select、任务直达、竞技场与设置页返回基地的 AS2 回包在淡出前写入 class-level exact envelope，淡出后只发送预序列化 wire；Host 只接受正整数 `callId`，malformed、unknown、stale 响应均不得消费 pending。Stage Select 的普通关闭必须先让 `Bridge.send` 同步接纳关闭消息，再销毁本地 Panel；`false` 或抛错时保留 owner、pending/busy 与可见 `send_failed`，允许玩家重试。

该增量完成自动门和 isolated candidate 后必须停在真人复验：战斗中地图可读但不可离图、右上 exact 点击可返回且不残留、外部窗口不被抢焦、跨按钮拖放不误触。未通过前不得把既有 A3 的 `promoted` 状态外推给本增量，也不得创建 release tag、请求云端共识、promotion 或部署提交。

2026-08-28 自动门已闭合，但仍不代签上述真人复验：

- fresh map/loot runId `cc5d27693006498cb895c56633d79230` 为 Loot `154/154`、Planner `9/9`、StageRunSession `333/333`，唯一 block `496 PASS / 0 FAIL`；fresh Settings runId `c14e9ad00f1e47f3a8684d43ef7ab041` 为 `46/46`。两者均为 Compiler `0/0`、32K retry `0`；前者真实执行生产 `_root.返回基地/_root.关卡结束`，覆盖预载 staging、drop update 抛错不部分提交、同 MovieClip 连续两轮死亡/复活与技能门恢复。
- Launcher 全量在 exact SDK `10.0.300` 下为 `4346 pass + 3 explicit opt-in skip / 4349 total`；相关 Host focused 为 `143/143`，布局 focused 为 `42/42`。Web 为 Map `51/51`、Stage Select `55/55`、Tasks `63/63`、Settings `18/18`、Panel contracts `5 domains / 31 commands / 0 errors`、selftests `68/68`，全部无 page error、failed request 或 broken image。
- asLoader 精确 publish 只编逻辑注入层，产物 `scripts/asLoader.swf` 为 `1,179,458 bytes`、SHA-256 `04A0445EEF6F40EB079ED610D2F03F66E295B59C4A40983585DFD37FA8023451`、`10,549 functions`、最大函数体 `50,069B < 60,000B`、Compiler `0/0`；FFDec `21.1.1` 以 exit `0` 导出 `621` 个脚本，并定点确认 alive baseline、奖励 staging/提交顺序、四类 exact response envelope 与 Stage Select 预序列化回包已经进入产物。publish 模式未刷新 trace，行为结论只来自上述 fresh focused TestLoader。

维护者已在 fresh isolated candidate `stage-nav-revive-0829-v1` 完成下方 1–7 项真人功能矩阵并确认均有效；但复活按钮的 `复活×2.1万` 曾换行越出 32px 状态槽，因此该候选未进入发布，现已正常关闭并由布局修正版取代。

2026-08-29 fresh isolated candidate `stage-revive-layout-0829-v1` 在发布前达到 `e2e_verified / HUMAN_ACCEPTANCE_PASSED / NOT_DEPLOYED`；其 exact Core 字节随后进入正式 runtime：

- Core SHA-256 `B03C2F9453CEA7F29A986421BC7182761DEC59E80ADC1726B628B59690BB984A`；
- build identity `47001CF2926D0E47AF235AF3672BBEE984F69162570167029118FE61791A5B69`；
- payload closure `24C95A76AEF22CC40A3EE38F61EB916DF6AD664AF4F5006462452BDD80ED0296`；
- 首次启动 Guardian PID `10492`，复验重启 PID `23580`；candidate bundle integrity `33 files` 通过，两次均由窗口正常退出。维护者已确认复活行排版和两按钮点击区域有效、可工作；
- 最终 release source `b2385ee83ebd2511e501bc2b2fdd6131310aa663`、不可变 tag `runtime-build-v2/20260829-stage-nav-revive-v1`、request `C64342535E6D8CEBD88D2D359A118C75CEC967071EA00A22CEA4783A769C69E9` 已通过 39/39 production policy、本地 X509 与 GitHub Hosted OIDC/Sigstore run `33220240979` 的双签共识和原子 promotion；
- deployment commit `95dec8e1c770187c57c98be6256ece6260fbed79` 已推送，首次 post-promotion Audit run `33221250923` 明确输出 `state=promoted`、`deploymentChanged=true`。根 bootstrap `--verify-only` exit `0` 且没有产品进程残留；该验证不执行选关、死亡复活、返回基地或存档旅程。完整发布哈希只读 [runtime build reproducibility](runtime-build-reproducibility.md)、[runtime manifest](../runtime/cf7-runtime-manifest.tsv)与 [signed consensus](../config/build/runtime-release-consensus.json)。

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

关卡决策到达时，已排队的普通任务/公告不会丢失，其 5 秒计时被冻结。胜负决策保持常驻，不提供会把返回入口一起隐藏的伪“继续”按钮：游戏没有暂停，玩家直接忽略该条就是继续探索。胜利且没有已完成、可路由任务时只显示“回基地”；AS2 投影 `tdr=1` 时显示“前往交付 / 回基地”，失败仍只显示“回基地”。同轮后续 `dead` 会切换成复活决策；复活币大数按 `9999 / 2.1万 / 1亿 / 1万亿` 一类有界格式绘制。双按钮仍占用原有 128 逻辑像素总宽度，但按主/次操作分配为 `80/48`；动作文本使用 `NoWrap + LineLimit` 单行省略格式并缩入 1px，`复活×2.1万` 保持 11px，只有更长的合法金额使用 9px 紧凑字形，最大合法格式也不得换行。绘制与命中测试共享同一组可变矩形。复活、返回基地、前往交付和继续领取都必须发送新的 `intentId` 以及当前 `runId/expectedRevision`。

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
- 同一次 respawn 必须显式重建存活基线：`target.倒地=false`、`target._killed=false`、删除死亡诊断 latch，并调用 `WatchDogUpdater.reset(target)`。普通技能入口会同时受 `倒地/_killed/WatchDog` 约束，而小跳例外不经过同一技能门；因此“复活后只有小跳可用”不是焦点争夺，而是同一个英雄 MovieClip 的死亡标志未复位。
- 只有 `TargetCacheManager.findHero()` 返回的同一 MovieClip 且实际 `hp > 0` 才能清除玩家死亡；佣兵或敌人 respawn 不得误改 life。
- 重入时 `dead → reviving` 先发生，重复点击不能重复扣币。
- 禁复活、没有复活币、正在返回基地、hero/dispatcher 缺失均在写前失败。
- dispatcher 在实际恢复 HP 后才抛错时，以生命事实为准，不能错误退款并把已复活玩家重新标死。
- respawn 未生效时只经 `ItemUtil.singleAcquire` 返还本次复活币；无论退款是否抛错，life 都回到 `dead`，不得永久卡在 `reviving`。退款未得到 exact before/after 证明时返回具名错误，设置页提示玩家立即核对存量。
- C# 投影或 socket 发送异常不能越过 AS2 权威事务，不能中断扣币、退款、复活或结算终态。
- 设置页兜底不再“重新拉起旧弹窗”，而是调用同一共享事务；这直接覆盖用户反馈的关卡结束后死亡无法复活问题。

历史追查表明 MovieClip 复用不是本轮新增：旧 XFL 复活也复用当前英雄，但死亡动画 MovieClip 的 `onUnload` 往往顺带清掉 `倒地`，掩盖了显式 rearm 缺失；换图则会从模板重建单位，所以玩家观察到换图后恢复。2026-08-27 的 `32ae67a1c57` 把 `StageRunSession/C# HUD` 复活路由稳定为不换图的同实例路径，却没有同时建立上述 alive baseline；`_killed` 未显式复位又是更早即存在的缺口。修复因此落在唯一 respawn 生命周期，而不是给各技能逐个加旁路。

## 5. 返回基地与奖励一次性语义

所有 `_root.返回基地` 调用先执行 `StageRunSession.onReturnBaseStarted()`：

关卡 XML loader 不再在预载阶段直接覆盖 `_root.关卡可获得奖励品` 与场景掉落目录。`StageManager` 按 exact reservation 保存 staging；loader 失败、abort、supersede 或迟到回调只丢弃该 token 的 staging。首次 gameplay init 才提交，且先执行 `ItemObtainIndex.updateStageDrops`，成功后再替换奖励数组；若 drop 更新抛错，旧场景两份权威均保持不变并走 canonical failure return，避免“地图没切成、奖励表先被下一关污染”。空奖励数组也按同一事务提交。

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

- 待领奖励现以 `_saveExt.stageSettlement.v=1` 保存冻结 manifest、remaining manifest 与有界 receipt journal，并在读档后重建 AS2 authority；自动夹具已覆盖进程内重启模型和回包丢失窗口。真实产品仍未完成“领取一部分 → 杀进程/重启 → 继续领取 → 再重启核对资产”的标准入口旅程，因此当前只能声称持久化机制已实现并通过 focused gate，不能称 `standard_entry_verified`。
- 当前危险操作是一次性放弃所有剩余奖励，不提供逐奖励放弃；“全部收取”会先用单批请求收走所有可接收项，因此危险操作通常只作用于无法领取的剩余项。单批上限为 50，超过时由 Web 在上一批得到精确权威投影后再发下一批。
- 自动头像 harness 使用受控资源和浏览器环境；真实敌人 manifest、纸娃娃组合的构图与低分辨率可读性仍需人类验收。
- 32px 共用状态槽消除了独立结算卡对中央/底部立绘的遮挡面；真实关卡仍须覆盖窗口化、全屏、不同 DPI、按钮点击与普通任务播报恢复，不能把离屏位图视为最终验收。

## 8. 验证与发布门

当前自动证据包括（顶部增量段为本次 fresh 真值，以下历史数值不再作为当前工作树证据）：

- AS2 map/loot/stage focused：`496/496`，其中 Loot `154/154`、Planner `9/9`、StageRunSession `333/333`；Settings `46/46`。两条 runner 均为 Compiler `0/0`、32K retry `0`。
- asLoader 精确 publish：Compiler `0/0`，`scripts/asLoader.swf` 为 `1,179,458 bytes`、SHA-256 `04A0445EEF6F40EB079ED610D2F03F66E295B59C4A40983585DFD37FA8023451`；函数近墙门 `10,549` 项、最大 `50,069B < 60,000B`。FFDec `21.1.1` 导出 `621` 个脚本并以退出码 `0` 完成。
- 相关 Host focused：`143/143`；布局 focused：`42/42`；Launcher 全量在 exact SDK `10.0.300` 下为 `4346 pass + 3 explicit opt-in skip / 4349 total`。
- Web：Map `51/51`、Stage Select `55/55`、Tasks `63/63`、Settings `18/18`、panel contracts `68/68`；协议注册表为 `5` 个 domain / `31` 条 command、零错误。

自动门只证明当前源码、mock browser 和 Flash focused 闭环。2026-08-29 增量已经在 fresh isolated candidate 完成以下真人窄矩阵；任何一项失败都应回退到 `HUMAN_REVALIDATION_REQUIRED / NOT_DEPLOYED`：

1. 从基地地图选普通关卡：单击一次即关闭 Web 并露出战斗；不得出现 timeout、不得靠反复点击或再按叉才看见已启动的关卡。返回后再选第二关，不能遗留 busy/pending；可达时再覆盖任务/竞技场直达。
2. 同一张图内死亡并复活：普攻与数个普通技能立即可用，不能只有小跳；不换图再死亡/复活一次，建议连续 3 轮，死亡/复活 UI 各出现一次且复活币每轮只扣一次。
3. 分别记录设置页复活、NativeHud 复活、设置页返回基地与 NativeHud 返回基地从点击到画面可见动作的时间；把 intent/ACK/scene-ready 日志与体感对齐，未取证前不归因为电脑、网络或笼统“延迟高”。
4. 关闭/转场期间切到 QQ 或浏览器，CF7 不得抢回焦点；Stage Select 关闭发送失败时面板必须保留、显示 `send_failed` 并可重试。
5. 从地图、NativeHud 与设置页分别返回基地：右上战斗决策消失、人物可操作且不能残留战斗 lifecycle；通关有奖励/无奖励两条返回目的地均正确。
6. 战斗中地图可打开阅读，但 `navigate/open_stage_select` 必须显示锁定且零发送；不得再次制造“画面在基地、会话仍在战斗”的裂缝。
7. 本轮自动门已经覆盖 exact abort、loader failure、drop update 抛错、迟到回包与 malformed callId；人工无需刻意破坏文件，只需保留出现异常时的 `launcher.log` 与复现视频。

维护者已确认上述 1–7 项功能路径均有效。该轮额外发现的唯一问题是 `复活×2.1万` 在旧候选中换行越界；布局修正版随后完成复活文案单行居中、不裁切/重叠，以及“复活”“回基地”点击区域与可见按钮一致的真人复验。其 exact Core 已完成正式发布，当前准确状态为 `HUMAN_ACCEPTANCE_PASSED / promoted`；部署后只补了 supply-chain、根 bootstrap 与远端 Audit 证据，没有重跑业务旅程，不称本功能业务 `standard_entry_verified`。

既有 A3 完整功能矩阵及已发布结论仍作为历史基线，不代签上述增量。A3 隔离候选 Core SHA-256 `5B010C6040A5E80E1E8923FD02D6B632AB2D309511F8C6A54BA7D78B7516314F`、build identity `03F9825C2A2A248C73A7FA6FFB4E6C4305D49C4F97BD9E6042747B9BC5A0F5AA`、payload closure `5DA2B3053BF70EFCDCE74A503C33098774F9026AAD6E2D1F555C1A9EC5181D07`。

A3 在人工验收时达到 `e2e_verified / NOT_DEPLOYED`；其 exact Core SHA-256 `5B010C6040A5E80E1E8923FD02D6B632AB2D309511F8C6A54BA7D78B7516314F` 随后由 release source `732898b8aa1308cf820976324f47bba97f654e41`、不可变 tag `runtime-build-v2/20260827-stage-outcome-settlement-v2`、release tree `d498236a3ac06294f0c871dba73302bb24bc398e` 与 request `CB8268D83DB35DF3BC7D22587822F279C29A93CD12A15B1F10DF14759B000991` 进入正式列车。39/39 production receipt SHA-256 为 `977B2B2A7466C307198438C1F8362CE9ED06F3415977F664CB4E402B4192A181`；本地 X509 与 GitHub Hosted OIDC/Sigstore run `33070890481` 对 identity `03F9825C2A2A248C73A7FA6FFB4E6C4305D49C4F97BD9E6042747B9BC5A0F5AA`、closure `5DA2B3053BF70EFCDCE74A503C33098774F9026AAD6E2D1F555C1A9EC5181D07` 达成双签共识。deployment commit `339b15694d631d483736880c0dfd44429f6926a3` 已推送，post-promotion Audit run `33071572650` 明确输出 `state=promoted`、`deploymentChanged=true`。

无 candidate selector 的 `automation/start.ps1` 随后确认正式 Core、identity/closure 与 bus ready，并以 exact Guardian PID 正常关闭；本轮新增 Flash 与 WebView2 子进程、`launcher_ports.json` 均无残留。该次没有选择存档，预热在 45 秒 deadline 后以 Flash code 0 自行回收，未出现 fresh `bootstrap_reveal_ready`，也没有重跑复活、胜负、交付或奖励领取业务。因此准确状态是关卡结果与基地结算 `HUMAN_ACCEPTANCE_PASSED / promoted`；正式入口仅有身份、总线和正常退出的窄证据，不补写 `standard_entry_verified`。
