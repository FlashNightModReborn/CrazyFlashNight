# 玩家持久属性投影合同

本文件是持久属性更新的唯一接口合同。代码核对基线为 `4cacdc76c1c21e953344d3bb515ebad19fa0656e` 上的玩家属性施工差异；候选编译、实际旅程和正式部署分别验收，本文件不授予发布权限。领域原有资产、保存、未知结果合同继续生效。

## 权威与成功屏障

| 输入 | 唯一规则/提交 owner | 投影时点 |
|---|---|---|
| 技能学习、等级、被动启用 | SkillLoadoutService | 事实提交后；奖励 prepare 不发布，resolve(committed) 才发布 |
| 装备与在身调制 | CharacterBuildService / EquipmentTuningService | 真实容器提交后；原 generation/loadoutRevision/proof 与最终属性屏障同时满足 |
| 快捷拾取、legacy 装备移动 | PickUpManager / ItemUtil | 真实容器成功后；失败投影不能返回为“物品未取得” |
| 健身 | GymTrainingPanelService | 精确 session 的 durable 确认后；save_pending 候选不可供属性、装备或转场消费 |
| 经脉 | MeridianPanelService | 内存点亮后立即投影；save_pending 保留事实，精确保存重试不再扣币 |
| 佣兵/战宠条件 | 原 flag 的领域 owner | 决定原独行者谓词的 flag 实际变化后；场景加载合批 |
| 升级 | LevelUpRecovery 与任务/经验 owner | 已提交的跨级事实；一次回满、一次特效独立于可恢复投影 |
| 读档/书中构筑/临时玩法 | SaveManager 与对应场景服务 | 真正替换输入前 reset/detach；全部新输入和身体就绪后才 bind/ready |

PlayerStatRefreshCoordinator 只拥有投影水位、身份、有限恢复检查点和自己的动作屏障。它不扣费、发奖、保存、移动物品或重放领域请求。Skill 的版本、CharacterBuild 的两个 revision、SaveManager 的耐久回执各有权威，不能用 statRevision 代替。

Gym 在准备入口及创建候选之前登记专用的只读消费门，协调器通过该端口阻止未耐久成长进入 STATS、完整装备初始化和场景初始化。数值核心不反向加载 Gym 的保存/库存依赖。普通角色保存及其他领域查询不受这个候选消费门接管。

技能奖励 prepare 同样在候选表/缓存写入前登记专用消费门；resolve(committed) 清掉候选身份后才投影，明确回滚则恢复旧技能。其他域迟到配置或完整装备初始化不能消费尚未确认的技能奖励；原保存未知锁继续归保存 owner。

这两个候选消费门约束玩家数值及转场。NPC 的独立完整初始化不读取玩家健身/技能候选，保持自己的现役流程，不能因玩家等待保存而丢失同场景晚到的单位加载。

## 三种工作与稳定来源

`STATS=1` 用于持久数值、经脉和条件被动；`SKILLS=2` 用于实际技能事实变化；`EQUIPMENT=4` 用于计划内完整装备生命周期。纯槽位重排不重建属性。派生缓存、资源结算和 UI 是同一尾部，无额外 bit。

11 槽的未受修改数据由实际装载时冻结。引用及 level/tier/mods 等语义改变会使来源过期。普通投影不调用 getData、不从 live final 反推 base。DressupInitializer.buildPersistentSnapshot 在隔离对象上算完并校验必要数值，再由 applyPersistentSnapshot 通过现有 BuffManager base API 提交。旧 Buff 保留自身倍率、加算、定时记录；套装静态贡献按已提交记录重放，不重复安装 lifecycle。

合法装备负加成不是无效输入。`punch` 的正负值均参与空手攻击力；佣兵 AI 的非负抑制权重仅累计正加成的平方根，不能对负加成开平方并把生成的 NaN 传播成整个人物初始化失败。非有限输入仍在提交 live 前拒绝，回归需覆盖负值、零值、混合正负与重复刷新。

`佣兵技能概率抑制基数` 是 AI 辅助输出，不属于玩家必需属性、Buff 基底或属性后验。它仍随成功投影更新，不能因移出校验而保留上一次装备的值。旧帧 AI 通过 `LegacyUnarmedSkillChance` 消费：合法权重保持原概率公式，无效权重只拒绝本次可选技能抽取并沿原分支执行普通攻击。手动操控及已由 unitAI 接管的路径保留原入口判断。装备 `punch`、HP/MP 与其他必需输入的非法值仍由原数值边界拒绝；不补满资源，不放宽身份，不用辅助字段失败解除保存等待。

兼容名 DressupInitializer.updateProperties 现在走普通冷投影。完整装扮的数值和弹药建基是 initialize 的私有子阶段。新业务不能复制该子阶段，也不能调用 StaticInitializer、Buff reset 或 BuffManager.update(0) 来充当普通刷新。

普通 STATS 保持原 manager、dispatcher、body、Buff 剩余时长、当前护盾容量、射击/装填/动作任务和已发生的损伤。击溃扣掉的实际最终上限点数有独立运行来源；黑犀转换用一对通用 ADD，只有真实转换命令安装/移除。已定位的武器模式只投影数值及其缓存，弹药换算仍由真实模式命令执行一次。M7 只修改自己持有的 alias，通用刷新不覆盖 XM214 的旋转/间隔状态。

## 身份、重入与完整生命周期

context/body 是不可复用的普通 Object；world 复用 StageReturnFlow.worldIdentity。槽号、MovieClip 引用/路径和同帧 version 都不能独立证明实例。reset 立即 detach，丢弃旧检查点，不自动绑定旧 Hero，也不回写旧 MovieClip。

角色 generation 由 SaveManager 的真实输入替换及临时玩法 owner 显式更新；普通奖励事务的 ext 克隆不换角色。经脉以该 generation 隔离回执，ext 克隆只令收益缓存重读。同槽重读仍须走显式 reset，不能以槽名相同跳过。reset 先安装已 detach 的新身份和水位，再释放自己旧的暂停租约，确保同步订阅者不能恢复写旧体。

首次出生、模板、Static、模式组件、状态跳转和转场资源共同拥有外层初始化范围。开始即撤销 ready；UnitInitialized 和 SceneReady 保持原阶段含义。只有外层、转场资源及必要模式组件完成、数值/派生后验成立，才设置最终 ready。Dominator 的独立 SWF 用捕获的 body 通知模式组件就绪，不能以延迟若干帧代替。

每个 bit 记录 requested/completed 水位。flush 只接纳所捕获的工作；同 bit 的再失效仍留下工作。同步最多四轮，重入只返回 pending，不递归或每帧轮询。读取没有变化时为 unchanged，零投影写。

领域读取门恢复后，即使没有 dirty，成功返回 unchanged 也归还协调器自己因等待取得的暂停与禁射；不能越过权威检查提前宣告成功，也不为纯技能点保存伪造属性 dirty。释放在 flush 重入保护内执行，先交出旧 lease，再允许同步回调；随后重验身份、读取门和新增工作。其他 owner 的暂停继续保留，旧 context 的释放不能擦掉新 context 取得的 lease。

首次完整初始化和首次进场通知分别完成：若尾部 `initial_ready` 因合批或领域权威返回 pending，原 owner 后续 flush 达到 applied/unchanged 时补发一次出生就绪通知，不重放属性初始化或资源恢复。通知在 flush 的重入保护释放后执行；同一身体后续读取不重复发布。投影失败的 stage/reason 首次出现或改变时写入现有服务器日志，避免只留下 Host 的进场超时。

首次初始化明确失败时，通过窄失败 hook 通知场景 owner；同步 scene scope 的返回值同样必须消费。场景 owner 延后至下一帧接管失败，属性协调器不负责跳帧、重读档或发放资源。旧 scope 的失败不得撤销新身体。后续换装/成长仍按原 owner 的 checkpoint 恢复；出生失败不会靠发布部分成功的 SceneReady/Start 来解锁。

合法 EQUIPMENT 的领域 owner 先冻结原装备 proof 并预分配一次性 ticket 的目标 body。Static 开始时激活一次，最终必须恰为该目标及原 context/world/actor/proof。完整重建已覆盖的 STATS/SKILLS 合批吸收。任意另一个 body 仍失败；不能为了装备通过而放宽原 manager/dispatcher 替换后置条件。

## 资源与分阶段恢复

小提交段只写已验证的数值和既定资源结算，不包含领域回调。普通资源检查点在同一身体首次写前捕获有效 current/oldMax，900/1000 降到 800 结算为 800，合法 1300/1000 溢出则为 1200。部分 max 写失败继续使用原检查点，不能重采半成品上限。已完成资源结算不重复执行；派生失败只续派生。新伤害/治疗改变窗口后，旧恢复不得覆盖它。

固定尾部为：稳定基底/新旧效果/运行损伤 → 必要路径及武器/护盾/副武器缓存 → Heal → Impact → DPS/HUD → 后验。释放 PauseManager 也可能同步回调，因此释放后再次验证。普通派生更新只合并现有子弹属性的相关字段，不替换活动任务、付费弹药或护盾资源。

失败保留 dirty、具体 reason/stage 和协调器自己的暂停 lease；一般面板解除暂停不能释放它。读取与动作恢复必须检查 flush 的 applied/unchanged，pending/failed 不能伪装 clean。没有 Hero 为 pending_actor；缺身体/最终 ready 保留待做工作。

ticket started 后普通 flush 禁止再安装完整 lifecycle。原 owner 的显式恢复先尝试已保存的纯最终尾部；较早失败才在原 proof、身体和有效完整资源窗口下显式中止并创建新受控 ticket。CharacterBuild 的既有 flushLive/finalize 以精确 Boolean recoverProjection 表示已知失败后的恢复；结果未知只走原 reconcile watermark，不能带此许可。Host-only orphan 恢复仍需原精确 authority/pause/保存证明。

legacy 装备使用玩家属性投影.恢复遗留装备；它只重投影已提交的容器，不再拾取/移动物品。快捷拾取的原定攻击模式以 context/world/目标 body 回执保留，恢复完成后消费一次。成长使用玩家属性投影.恢复已提交成长，原成长 owner 保留早期 scope、分字段的一次性消费标志和最多一个更高等级意图；不再次执行经验、奖励或收费。缺 Hero 的成长意图不向后来新体追发治疗/特效。上述窄入口不提供 Web 任意 invalidate 权限。

ItemUtil 在 legacy 容器移动前调用已安装的玩家属性投影.允许遗留装备变更 Boolean 端口。端口缺失或未就绪即明确拒绝，叶层不反向装载协调器及其装备依赖；实际成功后才声明装备工作，提示音异常不能把已成功的移动伪装成未执行。

快捷拾取实体先占用，再调用领域；明确拒绝才释放占用，已成功或结果未知不能重复取得。模式后续意图只能在原 owner 验证、中止旧 ticket 并预分配新 ticket 时转移到这个目标身体；任意新体不会继承旧模式回执。合法场景或身体替换后，旧成长的回满和排队回满退休，恢复只检查新体自己的数值屏障；以后新提交的等级使用新 owner。

## 各域结果与恢复界面

技能复用现有 `diagnostics` 中的 `renderer_failed` 和受限 message 表示投影状态/原因；领域事实和 SP 不因此回退，现有刷新查询及关闭屏障可重试投影。装备使用原构筑 revision、dirty/result 与明确的 `recoverProjection`，未知 finalize 仍先对账。

Gym 的已保存结果携带封闭的 `projection:{status,reason}`。v2 开窗快照的 `pendingProjection` 在无恢复工作时为 null，旧 v2 可省略；Host 的 opener 与 session binder 必须同时接受该形状。失败重开只给出原 session 的 `pendingProjection`，校验精确 token、当前器材及目录项目、applied 阶段和待恢复投影，不能同时携带待保存 session；恢复按钮发送 `query` 加精确 Boolean `recoverProjection:true`，不发送 start、finish 或 retrySave。普通 query 读取缓存，未知恢复结果先查询对账。等级成长的恢复还要求原保存 session 持有的 growth owner。耐久失败仍由原 `save_pending` / `retrySave` 处理。

经脉在现有 applied/savePending 之外携带相同的封闭 projection 字段。恢复只请求 state，重试纯投影；保存确认继续使用原节点操作回执，不再点亮或扣币。三个状态在 AS2、Host validator 和生产 Web consumer 同批维护；关闭界面不能解除协调器或未知写的恢复门。

## 新领域接入

在领域成功收口接一次，先按原权威拒绝失败/未知写。异步领域在开始前冻结 context，并在可见提交时确认仍属于该 context。示例位于 class 方法中，不能让卸载后的帧脚本持有异步闭包：

```actionscript
// 已按本域合同提交；不要把收费函数包进 projection retry。
var c:org.flashNight.arki.unit.PlayerStatRefreshCoordinator =
    org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
c.invalidate(1,"growth",capturedContext);
var projection:Object=c.flush("domain_committed");
// 原领域成功保持成功；使用本域既有 diagnostics 表示 projection 的 pending/failed。
// 恢复操作只续原 owner 的保存或投影，不再调用收费/奖励提交。
```

reason 是封闭的领域标签集合；新独立领域应在公共成功收口明确登记标签和保存政策，不在 UI/剧情里挑选 Dressup、Heal、Impact 排列。装备领域还必须使用原装备 proof 的 ticket，不能把本例改成通用 full refresh。

## 有限静态审读和证据

tools/player-stat-refresh/check-writes.js 默认检查 HEAD 到当前树新增/修改的行，包括未跟踪源文件。--base 指定比较基线；--baseline 分类当前完整 AS2 与 XFL script CDATA。只对已明确的普通属性函数内 live final 复合写、manager/lifecycle 重建/tick、UI/普通 STATS 直接 full refresh 报硬错误；其他持久输入和运行态复合写输出候选，按 write-owners.json 定位 owner。owner 表不是豁免表。合法伤害、治疗、初始化、runtime alias 和显示排序夹具必须继续通过。词法检查不证明动态字段类型、可达性或异步身份。

专项命令与恢复前置见 [验证正文](../agentsDoc/testing-details.md#suite-player-stat-refresh)；探针来源与替身见 [工具说明](../tools/player-stat-refresh/README.md)。原审计 ZIP 未提供，重建探针必须标当前来源。源码、Node、真实 CS6 编译、原生 focused suite、实际游戏/Host 旅程分别记证，不能互相代签。

回滚按领域 adapter、完整身份/ready 接缝、数值来源和单域跨层协议分别整组处理。已提交的资产、已点亮的经脉、耐久训练和已消费的升级恢复不反向重放。生成器输出与所属 SWF 同批核对；候选不自动推广到正式 runtime。
