# Slice 6 四阵营大地图人类验收单

> **当前验收范围与候选只看 [基础闭环施工交接](../../../../../../docs/军阀-基础闭环施工交接-2026-09-05.md)。** 下列 r8–r14 结论与指令为历史，r14 已人类验收失败。机器有主板故障，本轮禁止自动真实游玩及 GPU 压测；人类短时自然游玩，不要求制造高负载。

状态：`R8_THROUGH_R13_HUMAN_ACCEPTANCE_FAILED_AND_SUPERSEDED / R14_SOURCE_MACHINE_VERIFIED / R14_CANDIDATE_BUILT / R14_CANDIDATE_EXECUTED / HUMAN_ACCEPTANCE_PENDING / NEXT_HUMAN_GATE_SLICE_6_1 / NOT_DEPLOYED`

本单只收集不可替代的玩法感知。构建、协议、状态机、地图拓扑、AI 预算、渲染资源和清理均由自动化先完成，不要求维护者抄日志、填 receipt 或复核机器输出。

## 已失败并被替代的候选

### 初始候选

- 候选目录：`tmp/runtime-candidates/v2/warlord-s6-commanders-0901`
- 结论：`FAILED / SUPERSEDED / NOT_DEPLOYED`，不得继续用于 Slice 6 验收
- bootstrap SHA-256：`55EABB5C3280FDFEE8302843D969C6B6354808F1AF4DC24DB5E2397AA80499D8`
- Core SHA-256：`271B4EBCEC926A5FD3BDE49A6FD764CE0143276D53DCA15AEEDEBAC48C285DCA`
- build identity：`E7CB0D7D4995A91789D9599F4D562E3E0DF2196D5B280EBE7FD5DBF4A53DDE19`
- payload closure：`0647AFB152079B29116ABDE22EE55B9B7AFAC17139BF179A08E4548C977EBDAA`
- `scripts/asLoader.swf`：`1,245,959` bytes，SHA-256 `A29ED0339532F7477F2AE6723F3EA1AC7C2E1DA8196BA277F51A81D2775B54CB`
- Warlord Web runtime manifest：`127` files / `2,059,720` bytes，manifest SHA-256 `B6A3EAF36F602E137272F9ED376FAD7B1CF8633192693447542FE122125F4A00`

该候选曾通过 `integrity-only / 33 files`，随后从上述精确 Core 路径启动 Guardian PID `12940`；Bus `1192/1924`、两组 WebView2 与 Flash Player 已建立。这些事实只证明当时的候选身份和进程建立，不能覆盖后续真人失败结论。真人实际发现三个阻断缺陷：进攻摘要被 Host 拒绝、Host 明确返回未开战后 AI 约每 `500ms` 无限重试、玩家主角错误显示为狙击兵头像。因此该候选固定为 `FAILED / SUPERSEDED`，不能称 `e2e_verified`、人类验收通过或继续作为回归入口；正式根 EXE 与 `runtime/` 从未因此改变。

### r2 候选

- 候选目录：`tmp/runtime-candidates/v2/warlord-s6-battle-portrait-r2-0901`
- 结论：`FAILED / SUPERSEDED / NOT_DEPLOYED`
- bootstrap SHA-256：`55EABB5C3280FDFEE8302843D969C6B6354808F1AF4DC24DB5E2397AA80499D8`
- Core SHA-256：`4D80375F359E8A71AE034FE331F1FF97E8212D15D1CA712B6BD914229E3933A9`
- build identity：`63A294EC50CDD525624498A3E873FF57F3B38540EA6B45A6FA1BB1B490450711`
- payload closure：`03AEFC9980D0278B1536B9355E8E5E61265C1B4E2D2EFAF072046D70F5784D55`
- Warlord Web runtime：`126` runtime + `3` vendor，closure `129 files / 2,071,964 bytes`，manifest SHA-256 `E8CFD120D1DF0A2767793173C92088047110C1091EDE6CB432E5F1D53C403DA1`
- `scripts/asLoader.swf`：`1,246,538` bytes，SHA-256 `34B68FB6E7514E0E076CC48E8B7606FA9C9B80096C1846100CE15D7E8D13388F`

候选自身 `integrity-only / 33 files` 通过，并由精确 Core 路径启动 Guardian PID `12760`。真人验证发现：外层主角画像仍读取瞬态控制目标，装备为空且棋盘棋子继续复用狙击兵；首次进攻收到两次立即 `not_started`；随后 Web 的 `stage_terminal` 又因多包一层 payload 而被 Host 以 `invalid_web_envelope` 拒绝。因此 r2 固定为失败历史，不能继续验收。

### r3 候选

- 候选目录：`tmp/runtime-candidates/v2/warlord-s6-fresh-world-r3-0901`
- 结论：`FAILED / SUPERSEDED / NOT_DEPLOYED`
- bootstrap SHA-256：`55EABB5C3280FDFEE8302843D969C6B6354808F1AF4DC24DB5E2397AA80499D8`
- Core SHA-256：`4D80375F359E8A71AE034FE331F1FF97E8212D15D1CA712B6BD914229E3933A9`
- build identity：`63A294EC50CDD525624498A3E873FF57F3B38540EA6B45A6FA1BB1B490450711`
- payload closure：`03AEFC9980D0278B1536B9355E8E5E61265C1B4E2D2EFAF072046D70F5784D55`
- `scripts/asLoader.swf`：`1,247,100` bytes，SHA-256 `17F6C2DFBA2A6FEDEF8CEB211A1A5E3C4539245CBB477781D9DBD90336B72DB6`

r3 由精确 Core 启动 Guardian PID `14768`。真人先后进入 Demo 2 两次、Demo 1 一次；三次均在 `stage_outcome active / activeFrames=0` 后 `1～3ms` 内转为 failure，且 Host 全程没有收到 `warlord_stage_start`。原因是 r3 把 `wuxianguotu_1` 过渡世界在打开外层沙盘前当成硬前置清理；`SceneManager.removeGameWorld()` 的 Loot/transport 栅栏一旦不接受，就由 `handleInitStageFailure` 直接映射失败并返回结算。该清理所有权现已移回真正的 Action battle handoff。

### r4 候选

- 候选目录：`tmp/runtime-candidates/v2/warlord-s6-entry-handoff-r4-0901`
- 结论：`FAILED / SUPERSEDED / NOT_DEPLOYED`
- Core SHA-256：`4D80375F359E8A71AE034FE331F1FF97E8212D15D1CA712B6BD914229E3933A9`
- build identity：`63A294EC50CDD525624498A3E873FF57F3B38540EA6B45A6FA1BB1B490450711`
- payload closure：`03AEFC9980D0278B1536B9355E8E5E61265C1B4E2D2EFAF072046D70F5784D55`

r4 从精确 Core 启动 Guardian PID `31168` 后进入了真实 Action 交战，但 Action world 覆盖原游戏 HUD；战斗结束后恢复面板立即关闭并出现黑屏，“恢复演习”回到初始战略局，下一次进攻又被 `encounter_frozen` 拒绝。该结果已经推翻 r4 的待验收状态，不得继续使用。

### r5 候选

- 候选目录：`tmp/runtime-candidates/v2/warlord-s6-resume-r5-0901`
- 结论：`FAILED / SUPERSEDED / NOT_DEPLOYED`
- Core SHA-256：`9D64CA5A8767F3E698528C42D85006DBFBCE74AABCD1D8EE19062FC9C4245B03`
- build identity：`76014502B95546A582C932FBF427D10FBE9EE3406589CD6DDB92B04EFD80F1B4`
- payload closure：`C6FCDDF3CD2AA157BDF5699A1AB116A155DAAC77D45FC94780EA6C160751C6B2`

r5 把 locator depth、死亡效果等待、逐帧 teardown 重试、同一战略 checkpoint 和 `warlord.as2-resume-apply.v1` 接到一起，并曾通过自身完整性门后从精确 Core 启动 Guardian PID `22452`。真人仍复现：战斗期间原游戏 HUD 完全不可见；打一场后战局冻结；“恢复演习”无效；不能返回基地。该结果证明局部修复直接加载/删除 world 的调用顺序不足以恢复普通过图语义。r5 已固定为失败历史，不得继续启动或作为 r6 的验收入口。

### r6 候选

- 候选目录：`tmp/runtime-candidates/v2/warlord-s6-native-r6-0901`
- 结论：`candidate_executed / HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`
- bootstrap SHA-256：`55EABB5C3280FDFEE8302843D969C6B6354808F1AF4DC24DB5E2397AA80499D8`
- Core SHA-256：`34099D6E5B12D52C00AEC093B28422B4347C650DB62263B5D7DE678DFBB02E6F`
- build identity：`40A4F5678F6BC13A3547B9D1B95B8F2F82863FFD9C761FC93544A758449E64A2`
- payload closure：`BC3EA9ABA890B9A60E301C615C556011BB5D9A4A29A0CA914C4CBA34CEC9FBF4`
- `scripts/asLoader.swf`：`1,251,357` bytes，SHA-256 `A6DD891E1C1BCD00021CCE4614F934A44E62252E1117E710ABDD3DBF95E03424`

r6 确实进入了隔离候选产品旅程，但真人点击进攻后直接得到黑色 Action 场景和“场景未能接管；本局保持冻结”提示，因此机器门与完整性门均被真人结果覆盖。根因不是标准淡出时间轴或 `SceneManager` 单例失效，而是 AVM1 的 MovieClip 引用按 target path 解析：旧 `_root.gameworld` 引用在同名 world 重建后会软重绑到新实例。r6 把旧 MovieClip 句柄当作跨跳帧身份，第一次 frame 209 把真实 fresh Action world 误判为旧 world；冻结回程的第二次 frame 209 又因 runner 已冻结被拒绝，Host 因缺少唯一 Action terminal 长期停在 `awaiting_terminal`。r6 不得再次启动，也不得把刷新面板或“恢复演习”当作修复。

### r7 候选

- 候选目录：`tmp/runtime-candidates/v2/warlord-s6-native-r7-0902`
- 结论：`candidate_executed / HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`
- bootstrap SHA-256：`55EABB5C3280FDFEE8302843D969C6B6354808F1AF4DC24DB5E2397AA80499D8`
- Core SHA-256：`34099D6E5B12D52C00AEC093B28422B4347C650DB62263B5D7DE678DFBB02E6F`
- build identity：`40A4F5678F6BC13A3547B9D1B95B8F2F82863FFD9C761FC93544A758449E64A2`
- payload closure：`BC3EA9ABA890B9A60E301C615C556011BB5D9A4A29A0CA914C4CBA34CEC9FBF4`
- Warlord Web runtime：`128` runtime + `4` vendor，verifier closure `131 files / 2,096,625 bytes`，manifest SHA-256 `EA279EACF098566CA0D915812892EB2E609B0FE3418329DE45AE5626ECA5CCD0`
- `scripts/asLoader.swf`：`1,253,227` bytes，SHA-256 `B267D4CD1DA0561B0053263ECF3B260E2C8A94CF51F129BA70DB16AF8D53CA08`

r7 已由真人实际执行。Action 战斗可玩，原游戏 HUD 层级正常，返回基地与外层结算均通过；但 Action 结果无法确认，精确失败为 `action.teardown-incomplete`。根因是 frame 209 在同一调用栈内过早执行首次审计；随后出现的 clean quartet 属于 frozen recovery 的第二次审计，不能反证首次 Action teardown 已经完成。因此 r7 的正向感知证据不能覆盖结果回写失败，也不能称 E2E、人类验收通过或部署；该候选已经 superseded，不得继续作为验收入口。正式 runtime 从未因 r7 改变。

## r8～r13 失败结论与 r14 候选状态

- r8 已完成真人尝试但未通过 Slice 6.1，最终固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`；`tmp/runtime-candidates/v2/warlord-s6-native-r8-0902` 不得再作为验收入口。
- r8 的 generation、owner lease、teardown receipt、跨 root tick 重审与 90-frame pending 机器数字只绑定失败架构，不能迁移给当前源码。
- 对 `warlord-scene-lifecycle-20260902-v1.zip`（SHA-256 `1BA3367F9C5E883F903FFAA2E4336E81C703C1C91CC6EBA6320B82648C6EDEA5`）的 GPT Pro 外部审查结论为 `APPROVE_COLLAPSE / PREFER_B`；这只是架构输入，不是机器或真人验收。
- PREFER_B 要求 `StageManager` 把 encounter 物化为临时普通 `StageInfo`，并与标准 `wuxianguotu_1` / frame 209 独占场景生命周期；`SceneManager` 只做其物理 init/remove，不成为额外 Warlord owner。
- 四个逻辑 owner 是 `StageRunSession` 父 GameStage、`WarlordSubStageRunner` outer binding/result、`StageManager` 场景/临时 Action、`WarlordActionEncounterService` 战斗事实；验收预算锁定为 `owners=4 / clocks=1 / leases=0 / terminal rewrites=0`。Host 只校验、传输、关联和幂等，Web 是唯一战略提交者；新鲜静态、故障注入、Flash、Host 与 Web 机器门均已通过。
- r9 候选目录为 `tmp/runtime-candidates/v2/warlord-s6-collapse-r9`；Core SHA-256 `51FA3005CB0D7313618861172A69262DC6524BB980C8D9508693B4D4436A2631`，build identity `0D7D5EEF395F1955F15154333A6CC9D11D9A0E9A79119899E16CEF41694A5CFB`，payload closure `5166276165391634572413890E9D3661C00BFB17020C751F499C32EF5552755A`。其自身曾通过 `integrity-only / 33 files`，随后由维护者真实运行。
- r9 真人门发现四项阻断：连续敌方移动每次结束都立刻回主角，下一次又追敌，造成镜头往返抖动；真实主角虽然能正常战斗，结算卡却误显示精锐狙击；普通怪物演员在纸娃娃视觉就绪前就开始互战并瞬间结束，肉眼看似没有加载；设置强制返回基地后旧 outer owner 未退休，fresh Demo 1 被“恢复演习”/Host busy 阻断。r9 因此固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`，不得再次作为入口。
- r10 源码保留 PREFER_B 场景折叠，但删除整局 recovery/retry/revision+1 产品面。outer `not_started` 是吸收性父 GameStage 启动失败；Suspended/Unknown 只冻结诊断且不可复活。父 clear、返回基地、restart、reinitialize 与 setup/admission/calibration failure 唯一发送 `warlord_stage_outer_cancelled` + `warlord.stage-outer-cancellation.v1` exact 六字段 binding，只幂等退休 Host owner，不生成业务 terminal、不恢复 Web、不耦合 `stage_outcome` 或内层 Action cancellation。
- 连续非玩家移动现在共用一个 camera token 和批次前原视窗，逐次移动不归位，只在批次结束、交还玩家或结算时恢复一次；批次中禁止手动运镜。`player_avatar` 结算保留真实主角/纸娃娃身份。普通演员必须完成 exact world、`__unitInitializedVersion`、dispatcher/collider/shield/正尺寸和普通单位 `unitAI`，再等淡出 runtime frame 36 + 6 stable frames 后统一 release AI hold/prime；actor readiness 上限 90 帧，scene reveal 上限 180 帧。
- r10 fresh 机器门：Web Node `188/188`、Edge/CDP `26/26`；Host focused `138/138`、canonical 全量 `4583 passed + 3 explicit opt-in skipped / 4586 total`；Flash Action runId `82bd63ecd49a475e82837134f6cf11b5` 为 `60/60 assertions / 3/3 cases`，SubStage runId `089298531cb14aafa7d72481658640d5` 为 `78/78 assertions / 10/10 cases`，均为 Compiler `0/0`、32K retry `0`。publish `scripts/asLoader.swf` 为 `1,243,780` bytes、SHA-256 `9CCA43E3D44D33C33BE5AE2368494B897C59DADE759A2E56CD5E1E33B9BCEDA2`、`11,031` functions、最大 `54,560B`。
- r10 隔离 candidate 已构建并通过 `integrity-only / 33 files`：目录 `tmp/runtime-candidates/v2/warlord-s6-collapse-r10`，Core SHA-256 `DDC325441769B1BDA844276D64D4DF65A5221BFFDA8EEDACD4D2486AE45E10AE`，build identity `29606003E974A75ECA28000A288FD0FC0D1D7AF32163E5A7156D022DF8C93C47`，payload closure `5C2D37472D8B15C3BAF0DBFBADBCAFE52CB5ABF5FC525A1F03CD95E891868752`。当前准确状态是 `R10_SOURCE_MACHINE_VERIFIED / R10_CANDIDATE_BUILT / HUMAN_ACCEPTANCE_PENDING / NOT_DEPLOYED`；正式 Core 仍为 `51FE5E940EEABAC6FB691DF8865AC2F51046D419045561D513D96A53B6DFFA82`，formal closure 仍为 `C60EAC30F960BDB45E871E264669E28712DC14960F318B50DA1A4803A516FD73`，正式 runtime 未改变。
- r10 随后由维护者实际运行并失败：Action 世界和 HUD 层级已经正常，怪物能够生成并攻击，但真实主角变成未装扮的女性基础体、装备未加载、键盘不可操作；同一存档在正常游戏中无异常。运行日志同时出现主角名 `fs` 进入 `[AI]` 更新，证明故障局限于 Warlord Action 适配器。根因是 service 在 `_root.加载游戏世界人物` 返回后立即把 `_root.控制目标` 改为“军阀动作镜头”，而玩家模板、StaticInitializer、DressupInitializer 与更新事件会在后续帧继续按控制目标选择一次性主角分支。r10 因此固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`，不得再次作为入口。
- r11 保留标准过图折叠，不改正常游戏角色初始化。Warlord 生成玩家前绑定 exact 实例名，并用 `_root.控制目标全自动=true` 冻结手动输入；控制目标在整个延迟初始化期保持为玩家，镜头仅由 `HorizontalScroller` 独立跟随。所有投影演员从 attach 首帧携带 AI hold；service 只在 `操控编号=0`、`hasDressup=true` 且 `RuntimeEquipmentProjection.getStatus(...)=aligned` 与既有视觉门全部成立后，才解除 hold、绑定玩家输入并统一开战。
- r11 同时把地图染色收敛为行动边界规则：战斗胜利只移动幸存者；当前阵营结束行动时，唯一驻军节点直接占领；下一阵营获得行动权前，按写入前 owner 快照批量包围占领 degree>0 且全部邻点严格同色的节点。联盟颜色不合并，争夺节点不直占，包围改色不删除敌方驻军，总部目标在整批改色后统一求值。
- r11 fresh 机器门：Web runtime `128` files，完整性 closure `131 files / 2,154,123 bytes`，Node `194/194`、Edge/CDP PASS；Host Warlord focused `88/88`、canonical 全量 `4583 passed + 3 explicit opt-in skipped / 4586 total`；Flash Action runId `0b9c54e298654d22879e5fbe5371d835` 为 `63/63 assertions / 3/3 cases`、Compiler `0/0`、32K retry `0`。publish 后 `scripts/asLoader.swf` 为 `1,244,629` bytes、SHA-256 `A98C7645EA0C2E65811E51DDD2C93A6C69B59A63433D4FED15357285195E6FC5`、`11,035` functions、最大 `54,560B < 60,000B`。
- r11 隔离 candidate `tmp/runtime-candidates/v2/warlord-s6-capture-r11` 已通过 `integrity-only / 33 files`：Core SHA-256 `DDC325441769B1BDA844276D64D4DF65A5221BFFDA8EEDACD4D2486AE45E10AE`，build identity `29606003E974A75ECA28000A288FD0FC0D1D7AF32163E5A7156D022DF8C93C47`，payload closure `5C2D37472D8B15C3BAF0DBFBADBCAFE52CB5ABF5FC525A1F03CD95E891868752`。原生输入与 r10 相同，所以 identity/closure 相同；本轮 Warlord Web runtime 与 `asLoader.swf` 由上述独立门绑定。正式 Core、formal closure 与 deployment 仍未改变。
- 2026-09-03 08:39:38，根 `本地开发启动.cmd` 已按 active pointer 启动 r11；核验中的 Core PID `32076`，可执行文件精确位于 `tmp/runtime-candidates/v2/warlord-s6-capture-r11/runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe`，其子进程已启动 WebView2、`hotkey_guard.exe` 与仓库根 Flash Player。该事实只把候选提升到 `candidate_executed / HUMAN_ACCEPTANCE_PENDING / NOT_DEPLOYED`，不代签任何游戏内行为。
- r12 的 exact admission/terminal 与战斗结果已经真人跑通，但 7/7 结算把底部 controls 裁出固定高度 dialog，表面表现为卡死；同一战报播放还反复唤醒被 modal 遮住的沙盘，现场 Intel 核显约 `93%`。r12 固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`，不得再用于验收；现有证据不支持“terminal 后永久 rAF 泄漏”的扩大结论。
- r13 把结算 dialog 改为固定头尾、formation roster 内部滚动，并在 battle modal 期间 suspend/cancel 沙盘 rAF。这些布局门曾通过 Node `199/199` 与 Edge/CDP `26/26`，但真人首战结算仍卡死并观察到 Intel iGPU 持续打满，后续整机非正常重启。应用日志精确停在 `12:20:58.029 warlord_battle_resume_applied accepted`，`dev/browser-qa.js` 于 `12:21:00.297` 变为全 NUL 文件；系统后来只有 Kernel-Power 41/非正常关机，没有当轮新鲜 Display/WHEA/bugcheck/dump，所以只能确认 r13 人审失败，不把根因武断归结为 GPU 驱动。`warlord-s6-settle-r13` 现固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`，不得再用于验收。
- r14 将图形资源从“隐藏但保留”改为战斗交接、结算 modal 和 panel-close intent 即时退休：先停止帧链，再 dispose geometry/material/texture/renderer，`forceContextLoss`，缩小并移除 canvas；关闭超时才恢复且精确只建一个沙盘。AS2 resume 直接打开最终静态结算，不再每 `80/320ms` 重放战报；结算遮罩改为不透明、无 `backdrop-filter`。启动页 WebGL 在 game reveal 后执行单向 retire，不再等待不可观测的 `TrySuspendAsync`。敌方批次运镜携带仅留在 session 表现层，手动运镜仍锁定；移动和运镜的 rAF/超时 fallback 共用同一个 identity-fenced exact-once 收尾，防止 Promise 永久留在 `returning`。
- r14 fresh 机器门：Warlord runtime `128` + vendor `4`，verifier `131 files / 2,180,127 bytes`，Node `201/201`；每次 `npm run test:browser` 先强制 build + verify，Edge/CDP `29/29` 包含 30 次 resume/结算循环、modal 零 WebGL/零沙盘 rAF、头像/full-render 不增长、panel-close 超时单场景恢复、连续 AI 批次单次归位，以及确定性吞掉 action-move/action-return rAF 后的 fallback 精确收尾。Bootstrap harness `10/10`，GameLaunchFlow 全族 `71/71`、reveal-watchdog `11/11`；SDK `10.0.300` 的 Launcher 全量 `4628 passed + 3 explicit opt-in skipped / 4631 total`，Release build `0` error（仅保留既知 WindowsBase `MSB3277` warning）。本轮未改 AS2，沿用 r12 的 fresh Flash admission/terminal 基线，不用 Web/Host 门代签新鲜 Flash 玩法。
- r14 隔离 candidate 为 `tmp/runtime-candidates/v2/warlord-s6-gpu-r14`，Core SHA-256 `B4C0492043E66DA38A14DEA287F455424E708C0D33EC0DF5E236FF15124B365F`，build identity `DD8A23ED8D96F17DAE96ABCEC5679FDA05931F0FB47CD74C35F2F608F16E4731`，payload closure `1AA98BAC9DB304CED4A0239CCE6EDFB4C528376C578F16A58798A264FC4A9C6D`。候选已经 `integrity-only / 33 files`，并从根 `本地开发启动.cmd` 精确启动 Core PID `24552` 到 Bootstrap Ready；当前为 `R14_SOURCE_MACHINE_VERIFIED / R14_CANDIDATE_EXECUTED / HUMAN_ACCEPTANCE_PENDING / NOT_DEPLOYED`。正式 Core `AE0E56CFCA82E12DE54845636D36A3F2D5E9D9EFE94A7BFC30228B21E00F8E8B` 未改变。

## 进入方式

r14 exact identity 已在上节冻结，本轮已经由根 `本地开发启动.cmd` 启动到 Bootstrap Ready。如需重启，从同一根入口启动；当前 active pointer 精确选择 r14，不要直接运行正式根 EXE 或旧候选路径。随后进入 **刘海/其他 → 测试 → 军阀演习测试**。先选 Demo 2 完成战斗、结算/GPU、镜头和返回基地短门，再选 Demo 1 验证 fresh first try；两关都必须走 `stage-select enter → AS2 GameStage → Warlord SubStage`，不能直接构造军阀会话。

本入口只用于 Slice 6 玩法验收，默认生产选关目录保持不变；把军阀关卡放进正式可见目录属于 Slice 7 上线工作。

## Slice 6.1 必须先通过的最短旅程

先不要求完整游玩大地图；先完成一次 7 人防守编队的结算与 GPU 观察，再完成两次连续交战、一次连续敌方移动观察、一次安全退出和一次 Demo 1 fresh 启动：

- 第一次进入 Action 后，原游戏 HUD、技能栏和状态栏仍在场景上方，没有被背景或 gameworld 覆盖；
- 玩家主角必须保持正常游戏中的性别/脸型/发型和全部当前装备，方向键与攻击键可操作，且不能再由 AI 自动移动；若仍出现裸体基础体、装备缺失或 `[AI] <主角名>`，立即停止本候选；
- 使用真实主角参战后，结算进攻方必须显示“我方主角/主角指挥官”和当前纸娃娃，不得显示精锐狙击；普通战宠/怪物必须先肉眼可见，再正常移动、攻击和承伤，不能在未见演员时已经瞬间结束；
- 结算出现 7 名防守单位时，底部暂停/速度/立即结算/日志/返回沙盘与关闭按钮必须始终可见可点；仅编队列表内部滚动，展开日志后也不能把 controls 裁出窗口。进入结算后沙盘应停止且 WebGL context 已退休，不应有自动战报逐帧重放；观察任务管理器时 Intel 核显不得在静止结算中持续打满，若再出现长时间高占用或界面停止响应，立即停止并反馈可见现象；
- 敌方清零后，首战 Action 结果能够回写并自动返回刚才的同一战略沙盘；不得出现 `action.teardown-incomplete`、黑屏、基础游戏画面或任何“恢复演习”入口；回来后回合、棋子位置、伤亡、行动点和战况记录延续首战结果，并能选择另一据点进入第二个 fresh Action world、再次回写同一战略局；
- 至少观察一段包含多个连续移动的非玩家行动：镜头可以依次跟随敌军，但相邻移动间不得先回主角再追敌；只有后续确实没有移动、交还玩家或进入结算时，才一次恢复到玩家开始等待前的原视窗。跟随批次中拖拽、滚轮、方向键/WASD、全图/定位和缩放按钮都应被禁止，不能与自动镜头争抢；
- 点击返回基地后能正常离开本局并进入正常外层结算；随后从测试选关页选择九节点 Demo 1，应 first try 建立 fresh run，不冻结、不黑屏、不显示“恢复演习”或 Host busy。再返回测试页进入 Demo 2 时也应建立 fresh run。
- 顺手观察一次染色：进攻胜利后目标节点先只迁入幸存棋子，到当前阵营结束行动才改为本方颜色；若一个节点的所有相邻节点在下一阵营开始前已严格同属该阵营，则该节点应被包围改色。联盟邻点不能混作同色，双方同驻的争夺节点不能直接改色。

这些点任一失败就停止，r14 候选仍判阻断；只需描述看到的现象，日志与状态机取证交给自动化。全部通过后，再继续下面完整 Slice 6 自然游玩。新候选在真人实际完成前最多只能达到 `candidate_executed / HUMAN_ACCEPTANCE_PENDING / NOT_DEPLOYED`，不得称 E2E 或验收通过。

## 一次自然游玩重点

不需要逐项机械打勾；正常游玩到至少接触两条战线，并尝试向中央工业环推进。结束后只需给出总体结论和遇到的具体异常。

- 四角基地是否有明显纵深和防守价值，同时仍能从两条出口主动出击；
- 中央工业环的军费、人口、生产和行动点收益是否足以成为必争区，而不是唯一卡死全局的咽喉；
- 吴豫（Itinerant / 111）与阎凝儿（Gazer / 112）的共同胜负、过境和威胁方向是否能被理解；袁望（Surveyor / 113）虽是政治独立势力，但本局与其余三方全部敌对，这一关系是否表达清楚；
- 四名指挥官是否真正影响行动点与战线；三名 Boss 阵亡后重建、玩家真实主角倒地后撤回并重新出动是否自然；
- 玩家主角在顶栏、驻军、棋盘、战斗摘要与结算卡中是否始终显示当前纸娃娃形象，不再出现狙击兵头像或精锐狙击替身；
- 战区工具是否默认收起并可从节点导航栏随时展开，展开时不再长期遮挡棋盘，`Esc` 收起后焦点是否可继续操作；中文搜索、可跳转告警和六节点窗口是否让 80 节点地图仍可定位；
- 底部 8 张普通兵牌从 `120px` 折到 `32px` 后，增加的 `88px` 沙盘高度是否明显改善大图观察；展开态文字与按钮是否仍无普遍截断或溢出；
- 动作交战中是否由当前玩家主角而非宠物副本接受方向键/攻击等控制，主角作为进攻方和防守方都能操作；主角阵亡后存活友军是否继续战斗而不是错误终止；
- 首次进攻是否能通过摘要复验并完成旧沙盘精确关闭、战斗、同一 GameStage 新沙盘恢复；若内层 Action 明确未开战，AI 是否只收束一次而不连续弹出/重发，玩家是否仍能重新选兵。outer GameStage 启动失败不得出现恢复/revision+1 入口；
- 近 `180`、中 `360`、远 `650` 的据点交战是否让突击兵、弹药兵和狙击兵各有可感知的就业空间；
- 连续多场动作交战并重启读档后，是否出现旧单位、镜头、监听、贴图或战斗状态残留，或玩家装备、技能、BUFF、冷却、HP、药剂与存档发生异常漂移；
- 当前战略普通单位为 L1、真实主角可能为 L99，战斗速度与平衡只记录观察；本轮不得为了延长演出静默归一等级。

## 最小反馈

维护者只需回复类似：

> Slice 6 玩法有效；基地/中央争夺/四方关系/指挥官/导航均可理解。异常：……

若某项失败，请描述当时据点、操作和可见结果即可；其余取证由自动化接手。
