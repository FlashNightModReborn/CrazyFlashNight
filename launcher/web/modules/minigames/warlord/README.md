# 军阀战术演习 3D 沙盘（Phase C）

本目录是军阀战术演习的 Launcher Web 正式模块。它保留原 Web Demo v0.1 的确定性规则、战斗、AI、录像和模拟层，彻底替换旧验证 UI，并以 Three.js 正交沙盘承接九节点教程与 80 节点 Demo 2 候选的路线、语义地标、战术徽章、节点拾取和移动过渡。

## 当前状态

**2026-09-05 起以 [基础闭环施工交接](../../../../../docs/军阀-基础闭环施工交接-2026-09-05.md) 为当前状态与候选入口。** r14 已因非主角参战无法准入而人类验收失败；下列截至 r14 的候选、启动指令及机器结果保留为历史。当前机器禁用 Computer Use 与自动真实游玩，集中由人类验收。

> 2026-09-04 最新运行事实：r13 已因首战结算卡死、Intel iGPU 持续高负载及随后非正常重启而由真人判定失败；替代 candidate `warlord-s6-gpu-r14` 已构建，并经根入口从 `dev.json` 安全恢复到真实游戏与首场 Action。当前为 `R14_SOURCE_MACHINE_VERIFIED / R14_CANDIDATE_EXECUTED / HUMAN_ACCEPTANCE_IN_PROGRESS / NOT_DEPLOYED`。正式 Core SHA-256 `AE0E56CFCA82E12DE54845636D36A3F2D5E9D9EFE94A7BFC30228B21E00F8E8B` 未改变，本条不代签结算稳定性、持续战斗、GPU 或 Slice 6 人类验收。

现役 Phase C：`PHASE_B_2_UI_HUMAN_ACCEPTED / PHASE_C_HUMAN_ACCEPTANCE_PASSED / PET_IDENTITY_AND_ECONOMY_OBSERVATION_CONNECTED / RESUME_FIX_PHYSICAL_E2E_PASSED / UPSTREAM_INTEGRATED / MERGED_FLASH_PUBLISH_AND_TESTS_PASSED / PRODUCTION_WRITES_FALSE / FORMAL_RUNTIME_PROMOTED / POST_PROMOTION_AUDIT_PASSED / FORMAL_IDENTITY_LIFECYCLE_SMOKE_PASSED`

2026-09-04 vNext 工作树：`SLICE_1_MACHINE_VERIFIED / SLICE_2_MACHINE_VERIFIED / SLICE_3_REWORK_MACHINE_VERIFIED / SLICE_3_1_DISTANCE_MACHINE_VERIFIED / SLICE_4_MACHINE_VERIFIED / SLICE_5_PRODUCT_BRIDGE_PREVIOUS_MACHINE_EVIDENCE / SLICE_6_MAP_MACHINE_VERIFIED / R8_HUMAN_ACCEPTANCE_FAILED_AND_SUPERSEDED / R9_HUMAN_ACCEPTANCE_FAILED_AND_SUPERSEDED / R10_HUMAN_ACCEPTANCE_FAILED_AND_SUPERSEDED / R11_HUMAN_ACCEPTANCE_FAILED_AND_SUPERSEDED / R12_HUMAN_ACCEPTANCE_FAILED_AND_SUPERSEDED / R13_HUMAN_ACCEPTANCE_FAILED_AND_SUPERSEDED / R14_SOURCE_MACHINE_VERIFIED / R14_CANDIDATE_EXECUTED / HUMAN_ACCEPTANCE_IN_PROGRESS / HUMAN_PHASE_C_VICTORY_PASSED / HUMAN_SLICE_3_DISTANCE_ACCEPTANCE_PASSED / NEXT_HUMAN_GATE_SLICE_6_1 / NOT_DEPLOYED / PRODUCT_RUNTIME_UNCHANGED`。维护者已确认 Demo 1 的编组、Formation、主体游玩与近 `180`/中 `360`/远 `650` 距离玩法有效。r13 只暂停渲染而保留两个 WebGL context、自动战报 tick 与模糊合成，真人首战仍卡死并观察到核显持续高负载。r14 在战斗交接、结算 modal 与 panel-close intent 时立即退休沙盘图形资源，AS2 resume 直接呈现最终静态结算；启动页 WebView2 在 game reveal 后单向销毁。机器门及真实 `dev.json → snapshot → game scene → Action admission` 已闭环，结算/GPU、连续战斗和完整 Slice 6 感知仍等待本轮真人完成。

Phase B.2 的全屏布局、相机/规划避让、高节点滚动与固定结束按钮已经维护者明确验收。Phase C 在该 UI 上接入 AS2 战斗权威：产品入口固定 `battleAuthority=as2`，战斗命令先冻结，不执行 JS resolver；Host 精确关闭沙盘并释放暂停租约后，串行调用竞技场，再以受校验 receipt 重开同一战略态。该链不写玩家存档、金币、K 点或玩家战宠，`productionWrites` 恒为 `false`。

Slice 2 已让现役 `createGame`、地图访问、AI、Three/DOM 呈现和回放入口消费经严格校验的 Demo 1 `MapDefinition + WarlordScenario + MapVisualDefinition`：NodeId 改为不透明字符串，九节点拓扑和内容仍保持教程语义；约 24 节点夹具证明没有隐藏九节点上限。96/128 节点仍只是解析/拓扑压力夹具，不能外推为产品大图。Slice 4 随后把 `GameState`、命令、AI、回放、结果和 UI 泛化为 opaque N 阵营；Demo 1 仍是同一通用核心上的两阵营配置，不保留 red/blue 专用状态分支。

Slice 4 已接通固定对称 `allied / neutral / hostile` 关系、确定 block turn、三组 VictoryGroup、指挥所失败与投降清理。Demo 2 四个阵营各有一个指挥官：玩家使用真实主角；`boss-pact-a = 吴豫 / Itinerant / cardId 111`，`boss-independent = 袁望 / Surveyor / cardId 113`，`boss-pact-b = 阎凝儿 / Gazer / cardId 112`。吴豫与阎凝儿同盟；袁望政治独立，但本局与其余三方关系均为 hostile。Boss 唯一卡遵守 available/queued/alive 互斥，PlayerAvatar 支持 Downed、撤离和从己方指挥所重部署；AP ledger 锁定前线加成先发、伤亡清零、同回合重部署不补发。同盟过境只允许原子两边路径，整条路径一次性复验完整 AP/容量/关系，盟友节点不落地，玩家和 AI 共用同一枚举器与 validator。

Slice 3 在现役底层 member 棋子之上增加不复制成员状态的 Organization sidecar。当前目录共 11 个 UnitTemplate：8 张普通兵卡进入底栏与排产，cardId `111/112/113` 三张唯一指挥官卡只由 Commander ledger 重建；`organizationConfigDigest` 固定为 `sha256:7FBBFE6B24592A7356B6AC9CACB14D49803FBA2214D8A9FFBD71599211114DA3`。每个 active member 恰好属于一个 CommandElement；同节点可零行动点把 2～4 支部队合成 TaskGroup、部分拆分或切换五种 Arena 语义阵型。移动、容量、攻宽、AI 与画布选择均以完整 CommandElement 为原子，父棋子点击/框选会展开全部成员；Replay 强制绑定该摘要。战斗 identity/seed 只取 round、battle ordinal 和排序后的参战身份，审计 `commandSequence` 不再让免费重组改变战果随机序列。`battleOrdinal` 已进入 Web/Host 共用的 canonical digest；真实 Demo 2 Host 合同导出与复验锁定相同摘要，旧候选的序号歧义已由机器回归覆盖。

Host 对应使用专用 `warlord_stage_start`，按 exact `scenarioRef` 固定 Demo 1 / Demo 2 各自 seed，并固定 preset/difficulty/theme 与 `battleAuthority=as2`。stage battle handoff 只在 exact close permit/commit 后运行，只采用匹配 binding 的 fresh tracked resume panel；提交后的 close 异常进入 Host-owned Unknown，并取消 prepared battle，不启动 AS2。内层 Action 的 `known-not-started` 只结束一次当前 AI 行动，玩家仍可在原战略态重新选兵；未知结果继续冻结。outer `not_started` 则是本父 GameStage 的吸收性启动失败，不能重试或 revision+1 复活。整局 `warlord_stage_recovery` 与 Native HUD“重试/恢复演习”面已删除；父 GameStage clear、返回基地、restart、reinitialize 或 setup/admission/calibration failure 唯一发送 `warlord_stage_outer_cancelled`，payload 为 `warlord.stage-outer-cancellation.v1` + exact 六字段 binding。Host 只幂等退休当前 outer owner，不生成业务 terminal、不恢复 Web、不裁决场景、不写战略态，也不耦合 `stage_outcome` 或 Action cancellation。通用 `panel_request("warlord")` 与旧 battle v1 继续分离，正式产品入口仍是旧 Phase C。

Slice 6 Host/Stage 候选新增独立 `warlord_demo_02_v1` / `demo2-thick-x-80` 权限边界与四阵营关系目录。地图采用 80 节点“厚 ×”：四角各 14 节点本土纵深和双独立出口，基地到前线约 4～6 跳；16 个臂节点通向中央 8 节点高价值工业环，臂间绕行且整图无割点。当前 Demo 2 Scenario/Map authoring 尚未发布稳定战略 config digest，因此 Host 不冒用 Demo 1 摘要，也不把浏览器携带的摘要称为已验证；该限制不外推到已稳定的 Organization/Encounter digest。临时权威是精确版本化 scenario/rules/map 三元组，阵营全集及六组对称关系仍由 Host 固化。首战投影另由 Host 登记全部 80 个目标节点，只接受冻结 encounter manifest 的 `near/180`、`medium/360`、`far/650` 精确组合；未知目标、缺失 sidecar 或字段错配均在启动 AS2 前拒绝。Demo 1 教程 XML 保留，Demo 2 使用另一份单 Warlord XML 和标明“Slice 6 验收候选”的选关项。

Slice 3 不升级外层 Host battle request schema/version。Demo 1 首个 Organization profile 固定 member `CommandLoad/DeploymentSize/APContribution=1`、TaskGroup `commandLoadDivisor=1`，因此 Host v1 的 `pieceIds.Count` 复验与新三量精确一致；聚合折扣要等 Host 协议同步升级，当前不能配置非 1 divisor。`EncounterCost` 已进入模型、预览与 AI 累计，但 EncounterBudget 正式上限尚未接线。五种 Formation 已从战略语义、回放和 UI 贯通到 Host/AS2：Host 对 present sidecar 做定义身份、存活成员分区、双向索引、参战完整性和每方统一阵型复验；vNext 使用 action binding/terminal v2，`StageManager` 将 encounter 物化为临时普通 `StageInfo`，`WarlordActionEncounterService` 只生成战斗事实。Slice 3.1 另以 `demo1-encounter-distance / warlord.encounter-distance.v1` 冻结目标节点距离；Host 按 NodeId 独立重算，AS2 使用并回显实际 `spawnDistance`。当前每方只接受一种统一阵型，混用会在 Web 与 Host 双重拒绝；逐 CommandElement/成员槽位与角色语义的完整 DeploymentPlan 保留为后续扩展。

同轮 UI 候选把现役命令拒绝从开发者错误字符串改为稳定 reasonCode + params，并由版本化 PlayerTextCatalog/HelpProfile 统一提供中文原因、下一步与帮助锚点；玩法帮助支持 Esc、Tab 围栏、初始焦点和关闭后焦点恢复，教学可跳过并重新打开。机器门只能证明 DOM/合同和普通 Edge 候选；“零英文、零战棋基础”的真实理解仍必须由新鲜零背景玩家验收，不能沿用 2026-08-25 的 Phase C 感知结论。

下一次人类节点使用 [Slice 6 Demo 2 验收](dev/slice-6-human-acceptance.md)；只能启动已冻结的 `warlord-s6-settle-r13`，不能继续使用 r12 或更早候选。维护者从仓库根标准开发入口进入 `其他 → 测试 → 军阀演习测试`：先验证首战 `7/7` 及更高内容压力下 footer/controls 始终可见可点，并观察播放前、播放中、关闭后 Intel GPU 与沙盘动画是否按预期停下、恢复；再完成建议 `30+` 次连续战斗，确认每次 exact admission/terminal/resume、主角完整装备与键盘控制、敌方批次镜头一次归位、主角结算身份、普通演员可见互战、行动边界染色及返回基地后 Demo 1 first try fresh。随后继续 Demo 2，自然判断四方关系、共同胜负、多指挥官、战线、导航、兵种就业及跨战污染。默认生产 Stage Select 不含军阀条目，正式可见入口仍属于 Slice 7。

2026-08-25 首次真实候选旅程已实际进入并完成 AS2 战斗，但没有回到战旗页面。结果文件证明 AS2 在约 17 秒内返回 `finished / winner=blue / errors=[]`；同一时刻 Host 日志明确记录 `[Router] RequestOpenPanel unsupported panel=warlord`。因此旧 `warlord-c3-0825` 只保留为失败证据。恢复动作现改走仅供 `WarlordBattleTask` 使用的 `TryOpenWarlordResumePanel` 内部能力：它校验只读/AS2 权威、请求摘要、session/request 身份、冻结状态/命令和客户端上下文，再经统一 `PanelHost` 打开；通用 `panel_request` 仍拒绝 `warlord`。替代候选 `warlord-c4-resume-0825` 已由维护者确认战斗结束会自动回到战旗页且体验有效。随后整合上游 7 个提交并重新发布合并 AS2 源；合并树 Launcher `4099 passed + 3 explicit opt-in skipped / 4102 total`、Node `75/75`、Edge/CDP `16/16`、共享 Minigame `57/57` 均通过。最终 release source `248cca7be212219655319c666304407b0568e658` 已完成双构建共识、promotion 和远端 audit，当前为 `HUMAN_ACCEPTANCE_PASSED / promoted`；部署后的 formal smoke 只覆盖身份和生命周期，不代签军阀专项 `standard_entry_verified`。

## 权威边界

- `src/core/**`、`src/battle/**`、`src/ai/**`、`src/data/**`、`src/replay/**`、`src/simulation/**` 以 `warlord-tactical-demo-v0.1` 的机械导入为基线。Phase A.6 只增加受限 `CANCEL_PRODUCTION` 状态转换；Phase A.7 只改变 presentation projection 和棋子几何；Phase A.8 只调整棋子缩放呈现策略。战斗、AI、经济、人口、生产推进与部署公式未改。
- `src/ui/App.ts`、旧 `src/ui/styles.css` 和旧 `src/main.ts` 没有导入。
- UI 和 Three.js 都只投影 `GameState`。非战斗战略写入仍通过 `applyCommand()`；产品战斗命令只由 `validateCommand()` 形成冻结请求，accepted receipt 返回前不改战略态。
- 产品战斗播放只消费已接受 receipt 的结果投影，不重新执行 AS2。旧 `BattleRecord.result.eventLog` 与 JS resolver 仅保留给显式 `battleAuthority=fixture` 的开发 harness 和规则回归。
- 卡牌目录共 11 张，`cardId` 就是 `data/merc/pets.xml` 中的 `petId`，产品联合身份为 `petId + Identifier`；其中 8 张普通兵卡在底栏显示并允许排产，111/112/113 是唯一指挥官卡，仅由 Commander ledger 重建。旧 `unitTypeId` 仅供 Demo 审计。普通兵与三名 Boss 的浏览器头像继续通过现有 `EnemyPortraits` manifest/resolver；玩家主角不得把控制投影中的 cardId 当作头像或结算 identity。主角只接收 Host 绑定的性别、脸型、发型与六个装备槽纸娃娃 tuple，并经共享 `MercPortraits` 渲染；`encounterProjectionKind=player_avatar` 从战斗快照贯穿结算 presenter，Node 与 Edge 门锁定主角显示“我方主角/主角指挥官”，不再降级到 `EnemyPortraits`、狙击兵头像或精锐狙击结算卡。

## 装载结构

`warlord-panel.js` 是 classic facade：脚本求值时同步调用 `Panels.register('warlord', ...)`，捕获自身 URL；`onOpen` 再动态 `import('./runtime/main.js')`。共享 LazyLoader 只加载 `host-bridge.js`、`portrait-resolver.js` 与该 facade，不需要改造成 module loader。

facade 与 ESM session 共同保证：

- open generation fencing，关闭或重绑后晚到的 import 不得重新挂载；
- `mount / rebind / resize / dispose` 明确生命周期；
- 关闭时释放 timeout、键盘/DOM listener、ResizeObserver、rAF、Three geometry/material/texture/renderer；
- `PanelScale.attach(shell, 1024, 576)` 固定逻辑画布；Demo 2 战区抽屉默认收起，由节点导航栏按钮展开；底部普通兵牌默认展开并可按需折叠；
- WebGL 初始化失败时切换为可完整操作的九节点 DOM fallback。

外层 `×` 和无内部状态可消费的 Esc 只发送携 active `panelInstanceId` 的 exact Host close；Bridge 投递成功不等于关闭确认。确认缺失时恢复同实例重试权，不本地 retire；generation、instance 与 Host active owner 共同保证迟到 A 不能关闭 replacement B。AS2 handoff 已 prepared 后，关闭按钮与 Esc 等待 Host 完成 exact close，避免 Web 先销毁实例、通用 pause 尚未释放而竞技场已启动。Esc 仍不越过当前交互层，由内向外依次消费：规则配置 → Demo 2 战区抽屉（收起并恢复触发按钮焦点）→ 解除进攻二次确认 → 战斗播放（未播完先跳到结尾，已播完关闭播放窗）→ 清除棋子编组。

## Phase C AS2 战斗权威边界

`wargame-demo-v0.1.1` resolver 仍只是验证战棋循环、指挥交互和结算节奏的 fixture，不是待调平的产品战斗规则，也不承担与真实 AS2 战果相等的兼容目标。产品入口已改为真实 AS2 MovieClip、AI、子弹和伤害链产生唯一战果；JS resolver 只在显式 fixture harness 可达。AS2 不可用时产品路径 fail closed，不静默回退。

Host 的 `WarlordBattleTask` 对 active panel instance、session、request/input digest、战略快照、邻接、AP、攻宽、棋子归属和卡牌状态做 exact 复验，再从 `PetCatalogLoader` 投影 roster。8 张普通兵卡对应宠物目录 id `12/13/14/15/82/83/84/85`；三名 Boss 使用 `111/112/113`。AS2 以 `_root.宠物库` 复核 `petId + Identifier` 并直接生成该 Identifier；普通战宠等级按棋子卡牌等级投影，已购升阶必须是正式宠物 `Promotion` 中“基础训练 / 强化药剂 / 超级血清”体质链的合法前缀。`warlord.action-encounter-control.v2` 仍以 `commander.player / character.player-avatar / player` 的 `player_avatar` 表达真实主角控制，不再允许其 cardId 兼任沙盘头像或结算来源；Host 从当前运行态冻结只含性别、脸型、发型与装备槽的纸娃娃 tuple，Web 交给 `MercPortraits` 呈现。动作场景继续从当前运行态等级、装备与能力创建 encounter-local 演员，在生成前绑定攻守侧控制；主角阵亡后转场景镜头，存活友军继续。所有演员 attach 前后均持有 `_warlordActionAiHeld=true`；只有 exact world parent、`__unitInitializedVersion === version`、dispatcher、aabbCollider、shield 与正尺寸均就绪，且非主角单位另有 `unitAI`，才通过 90-frame visual-ready 门。玩家在延迟初始化期间保持 `_root.控制目标` 为自身实例名并以 `控制目标全自动=true` 冻结输入；只有 `操控编号=0`、`hasDressup=true` 且 `RuntimeEquipmentProjection` 相对当前 11 槽返回 `aligned` 后才解冻。标准淡出到 runtime frame 36 后再稳定 6 帧，service 才统一 release 双方 AI hold、绑定目标并 prime；scene reveal 总上限为 180 帧。`WarlordActionEncounterService` 只恢复自己改动的控制、自动控制、存档开关、药剂函数和被动对象引用，不持有场景生命周期或改写 terminal；Host 拒绝 Web 自报纸娃娃 tuple、投影字段、缺 sidecar、alias 和终态 identity/等级/HP/控制侧漂移。r11/r12 的机器证据和失败历史均已冻结；r13 不改本段 AS2 权威，真实人物与普通演员观感继续留给 Slice 6 人类验收。

通用 Web Panel 会持有 `_webPanelPauseLease`，所以真实战斗采用异步 handoff：Web 以有界战略投影冻结 exact snapshot/input digest → Host 回 prepared ACK → stage-owned exact close → Host 在同一 ready generation 发送合并的 pause-release + start 命令并等待 exact admission → AS2 串行运行临时普通 Action StageInfo → 返回绑定 outerRunId/encounterId/requestId/inputDigest 的 v2 terminal → Host 复验并采用同 binding 的 fresh resume panel → 新沙盘单次应用。Host 未收到 admission 时每 1 秒只向所捕获 generation 重发同 binding，首次在内最多 4 次；旧 A 在 B active 后的 same-generation late retry 只按 stale 丢弃，不冻结或 terminal 污染 B，terminal absorption 在成功 send 后仍保留。内层 Action 确定未投递时返回 `not_started`；玩家回到原战略态并允许重新选兵，AI 只做一次有界行动收束，不自动重发同一进攻。一旦请求可能已投递，timeout、断线、非法 terminal 或 identity 漂移进入 `unknown`，保持战略态冻结且禁止自动重跑。outer attempt 的 `not_started` 是另一协议域的吸收性父启动失败，不得混写为可重试。整局不存在 recovery/revision+1 reopen；父关卡退出只走 outer cancellation 退休 Host owner。r12 已证明该交付链能进入首战，但其 `7/7` 结算弹层因 `510px / overflow:hidden` 裁掉 footer/controls，并在播放期观察到隐藏沙盘多余 rAF/update 与 Intel iGPU 约 `93%`，故已失败并被替代；该观测不证明关闭后永久 rAF 泄漏。r13 将 dialog 改为 grid、编队内部滚动，battle modal 期间 suspend/cancel 沙盘 rAF 并跳过 `scene.update`，关闭后恢复一帧。近期回放只记录并播放已接受 terminal 的结果；若要求同 seed 逐帧重算，必须另行隔离 LCG、PinkNoise、时间线 `random()` 和帧调度。

战旗同时承担战宠经济标定，但 Phase C 只建立 `warlord.pet-economy-observation.v1` 观测回执。它分别记录 `pets.xml Price/KPrice/IncreasePrice` 的目录基础价和 `piece.productionGoldValue` 的战旗战略造价，并汇总双方暴露/损失；二者币种与语义不合并。回执固定 `mode=observe_only`、`settlementPolicy=none`、`writesPlayerState=false`、`currentAs2SessionPriceSampled=false`，因此不扣玩家金币/K 点、不改领养价、不结算战宠损失。未来真实经济结算必须新增版本化的会话价格采样、写入、存档和对账协议，不能把本观测 schema 升格为暗写入口。

## 战术相机与大地图扩展边界

沙盘相机已经是独立于规则核心的 presentation capability：

- 鼠标或单指拖拽平移；拖拽超过阈值后不会误判为据点点击；
- 滚轮围绕光标锚点缩放；按钮、`+/-`、方向键/WASD 和 `0/Home` 提供等价入口；未聚焦输入控件且画布未持焦时，这些相机键由 session 全局转发（画布持焦时仍由场景自己处理，不会双触发）；
- `全图` 按 authored map bounds 自动适配，`定位` 聚焦当前据点；
- 全图/定位/按钮与 `+/-`、方向键/WASD 单步、`0/Home` 等程序性相机移动带 240ms ease-out 运镜过渡，过渡期间 HUD 读数连续刷新、`atFit` 仅在落位后为真；正常玩家阶段的新输入会打断旧过渡并以其时实际位置为起点。拖拽平移与滚轮缩放保持 1:1 即时跟手不做插值；`prefers-reduced-motion` 下上述主动程序性移动直接跳变；
- 非玩家阵营的一段连续合法机动/进攻共用同一个 camera token 与进入批次前的原视窗；只有起点/盟军过境点/终点越出中央舒适视区时才做最小平移并保持 zoom。逐次移动结束只释放命令 barrier，不立即返回主角；批次确实结束、交还玩家或进入结算时才一次恢复原视窗。批次中拖拽、滚轮、方向键/WASD、全图/定位和缩放按钮均锁定，避免手动输入与自动镜头争抢；`prefers-reduced-motion` 下完全禁用被动跟随；
- 相机控件空闲时缩成只保留 `全图 / 定位` 的 108×30px 操作岛；悬停、键盘聚焦或刚发生拖拽/滚轮/快捷键/按钮操作时，读数与 `− / +` 展开 1.4 秒，既保留即时反馈又减少长期遮挡；
- 操作岛固定在沙盘右上槽，结算规划层以明确的右侧保留宽度停在其左边；空闲与展开态都不得依靠 z-index 互相覆盖；
- 相机中心、缩放百分比与 `overview / operational / tactical` LOD 层级可观测；
- 边界据点在战术层级也能居中；节点与棋子标记会分别做缩放级别补偿。Phase A.8 让战术徽章按 `sqrt(cameraZoom)` 渐进增加屏幕尺寸，220% 时约为 1.483 倍，极端近距封顶 1.8 倍；放大能欣赏头像、包边和底盘，又不会按相机倍率线性吞没据点；
- 地图投影原点由 authored node bounds 推导，但保持固定世界单位密度。更大的坐标场会得到更大的 Three 世界，不会被重新挤压回九节点画幅。

Demo 1 九节点场景继续共享重复棋子几何且不启用大图 LOD。Demo 2 的 136 条路线已合并为最多 4 个绘制批次；overview 普通节点由 2 个 InstancedMesh 承载，只有高亮/交互节点保留详细对象，dispose 时同步释放批次、实例与材质资源。这是对象数与 teardown 的机器合同，不是 FPS 或目标设备观感证明。

Phase A.7 把原“透明全身头像直接插在圆柱底座”改成一体化战术徽章：程序化阵营背板裁入头像，配套金属包边、短连接座、八边形低底盘、地面阴影和选择环。头像 identity、拾取 `pieceId` 与移动插值均未改变；背板和裁切遮罩是运行时 CanvasTexture，不新增或复制美术文件。概览层以识别阵营/兵种为主，战术层放大地图与编队间距，而不是按相机倍率放大单枚头像。

Phase A.8 根据人类验收反馈撤销“近似固定屏幕尺寸”的过度补偿。棋子会随战术放大明显长大，但地图内编队间距仍按完整相机倍率展开，因此单位之间的相对空隙增长快于徽章，不会重新压成头像墙。

底部节点面不把整张图平铺成一排按钮：默认“局部”按图拓扑从当前据点向外广度展开，最多只渲染 6 个节点；“全域”索引同样每页只创建 6 个节点卡。整条导航压到 48px，名称与兵力/归属合并为两层信息，但单卡仍保留至少 40px 点击高度与完整 `aria-label/title`。Demo 2 实图以 14 页覆盖全部 80 节点，并增加中文节点名称/类型检索、当前行动/指挥所威胁/生产阻塞告警和跨战区定位；这些战区工具默认收在导航栏按钮后，展开后可由 `Esc` 关闭并回焦。底部 8 张普通兵牌默认占 `120px`，必要时可折为 `32px`，把 `88px` 交还沙盘；3 张指挥官卡不进入底栏。四阵营身份同时用颜色与线型表达，不能只靠色相理解。

## 地图直接指挥

Phase A.5 把“选择 → 预览 → 下令”压成沙盘上的主路径，同时保留左侧复选框和右侧路线按钮作为精确/键盘后备：

- 点击己方棋子建立单选；`Shift/Ctrl` 点击在同一据点内增减选择，双击己方棋子选中该据点全部己方棋子；
- 按住 `Shift` 左键拖拽绘制框选；普通左键、中键或右键拖拽仍然平移相机。框选结果只允许一个起点据点，优先保持既有编组起点，否则按命中数量和 node identity 确定性选组；跨据点命中会明确报告被忽略数量；
- 有编组时，相邻节点由 canonical `validateCommand()` 投影为绿色机动、红色进攻、琥珀容量受限或低亮阻断；点击 Three 节点、底部节点卡或右侧路线按钮都走同一 `MOVE_OR_ATTACK -> applyCommand()`；
- 进攻目标采用 arm-then-confirm 二次确认：首次点击只把意图条转为红色"确认进攻"警示并提示目标名，3 秒内再次点击同一目标才执行；点击他处、Esc 或超时都会解除武装。绿色机动目标保持单击即执行，避免误点敌节点直接触发不可撤销的 AS2 handoff；
- 所有通知除 sr-only live 区域外同步到命令意图条上方的可见 toast：错误/阻断类用警示色、信息/成功类用中性色，只保留最新一条，约 3 秒自动淡出；门禁文案按真实原因分流（战斗播放 / AS2 移交中 / 结果未知冻结 / 非红方行动阶段），handoff 与 blocked 另有常驻可见横幅；
- 非相邻或非法目标保留当前编组并显示精确阻断原因。友方容量不足会在下令前后显示实际生效 `X/Y`，不会静默清空整组；
- 命令完成后只跟随“实际收到命令且仍幸存”的棋子，并自动把检查节点移到其当前位置，以便继续点击下一个高亮节点；`Esc`、沙盘空白点击或右键单击取消编组（右键原生菜单已被沙盒画布压制），节点点击恢复为只读查看。双击空白不再触发全图适配——第一次单击本就会按空白语义取消编组，全图适配改用 `全图` 按钮或 `0/Home`；
- 点击敌方棋子在无编组时只查看其节点；已有编组时则按该棋子所在节点解释为目标意图。战斗播放期间仍由现有写门拒绝新命令，3D 命令高亮同步收口，节点点击降级为只读查看；
- 蓝方 AI 回合改为按节奏重放：先在行动前状态跑出整回合命令，再以 ≥460ms 间隔逐条经公开 `applyCommand` 投影中间态（与棋子补间对齐，不再齐飞）；多场战斗排队依次以 4× 播放，播完停留一拍自动关闭并继续，最后一并结束行动。as2 产品模式的 AI 正常派发间隔同样放宽到 450ms；Host 明确返回 `known-not-started` 时不再进入该计时器重发，而是有界结束当前 AI 行动。该失败恢复已有确定性回归，真人只需观察实际局内不再循环；
- 驻军栏头部提供"全选本据点"按钮（40px 命中，等同双击棋子）；行动阶段兵种蓝图栏提示"统一结算阶段开放排产 / 升阶"；驻军与战斗播放的 HP 条按 <50% / <25% 分色并带 120ms 宽度过渡；悬停 Three 节点/棋子显示名称、归属、兵力与 HP 信息芯片；首轮引导以三步教练点提示建组 → 下令 → 结束行动，完成一轮后不再显示。

选择策略只投影 `GameState`，不增加跨节点编组、路径寻路、队形或批量规则。营/连级版本应把大量底层棋子归入编制/命令层级和聚合 LOD，而不是要求玩家直接框选数百枚头像。

## 节点语义模型与主题迁移预览

当前低多边形地标直接由 `NodeKind` 决定，不把美术语义写进规则：

- `hq`：指挥掩体、屋顶与通信桅杆；
- `supply`：堆叠补给箱与标杆；
- `economy`：双储罐和联通管线；
- `choke`：双塔关门；
- `command`：雷达桅杆与天线盘；
- `depot`：军需帐篷与货箱。

`MapTheme` 把地表色相、细纹、雾、背景、三组光源、网格、等高线、路线和中立节点颜色收束为呈现令牌。`desert` 是军阀演习默认主题；`tundra` 是同一拓扑、模型、棋子和规则上的迁移预览。主题切换不会进入 `GameState`、录像或确定性摘要，也不会改变任何规则随机序列。

## 生产队列与部署调度

生产规则没有改动：每个槽是 FIFO 队列，只有队首推进；队首完成后若据点驻军容量或实际人口上限不足，会保持 `waiting_deployment` 并堵住同槽后续订单。失稳取消、金币不退、预留人口释放等行为仍完全由原规则核心负责。

Phase A.6 另增加玩家误排撤销：只在该阵营尚未提交的结算规划中开放，并且订单必须仍是 `building` 且 `remainingRounds` 等于卡牌完整工期，也就是从未获得任何生产进度。合法撤销全额返还订单冻结的金币成本并释放预留人口；队尾可按 `orderId` 精确撤销而不改变队首。一旦跨回合推进或进入 `waiting_deployment` 即永久锁定。该规则与节点失稳的系统取消不同，后者仍不退金币。

右侧生产台把这些状态直接投影出来：

- 行动阶段显示紧凑队列监控；统一结算规划时展开队首头像、生产进度、后续订单链、据点容量和人口阻断原因；
- 当前检查据点之外的订单仍进入“全网在制”头像带；每单显示头像、据点/槽号、队列位置、进度及可撤销/受阻标记。点击头像只定位真实 node/slot，不切换 `AUTO/EXACT`，也不产生排产或撤销命令；
- 队尾订单同样带头像缩略图，不再只靠兵种名称区分；
- 默认 `AUTO` 会在全部稳定、激活的己方生产据点中组合一条合法 `ENQUEUE_PRODUCTION`，依次偏好未受阻槽、较低剩余工期、较短队列、较大部署余量，再以 node/slot identity 确定性决胜；
- 玩家从任意地图节点直接点击兵种“排产”即可完成自动选址与入队，不再需要先找生产点、再点 radio；成功回执会明确写出实际据点和槽号；
- `EXACT` 保留生产据点下拉框和逐槽选择。点击任一槽会切入精确模式，后续排产严格使用该 node/slot；
- 自动与精确路径在提交前都调用同一个 `validateCommand()`，成功后仍只走 `applyCommand()`。UI 不拥有金币、人口、生产进度或部署写权。
- 新入队且尚未开工的订单会同时显示“撤销上一单”和订单内撤销入口；两者都提交同一个 `CANCEL_PRODUCTION`，成功回执明确列出退款与释放人口。仅点选 `EXACT` 槽位不会创建订单。

生产据点用单一下拉框承接扩容，DOM 只展开当前查看据点的槽位，不把未来大量生产节点铺成第二条卡片墙。“全网在制”最多创建 6 个紧凑单元；订单更多时保留 5 个确定性头像与一个 `+N` 汇总，避免排产量线性吞噬右栏。它是当前小规模订单的监视/定位面，不替代百级生产网络需要的搜索、告警与虚拟化。当前规则仍没有拖拽重排、跨槽迁移或已开工订单取消命令，本轮也没有用 UI 伪造这些能力。

纯相机策略继续用 10×10、100 节点合成坐标场回归全图适配、缩放和越界钳制；现役通用规则核心另有 80 节点 Demo 2 实图，不再局限于九节点。100 节点合成场仍只证明 presentation/camera 数学，不代签约 100 节点的产品内容、AI 预算或真人导航体验。

80 节点候选已经冻结通用节点 identity/schema、版本化图数据、虚拟化节点检索、route batching、overview instancing、编制/命令层级和确定性回归；旧 Slice 6 候选暴露的 canonical digest、内层 AI 明确未开战收束、主角纸娃娃身份与 stage battle exact close/resume lifecycle 已由替代工作树重新闭合机器门。r9～r13 均已由真人判定失败并 supersede；r14 源码机器门、隔离 candidate 构建和真实标准入口恢复/首场 Action 进入已经通过。仍未闭合的是结算 controls 实际操作、静止结算 GPU 行为、连续 WebView2/AS2 交战、存档无漂移和 Slice 6 人类玩法感知；这些边界不能由普通浏览器、对象数测试、fresh Flash harness 或 `candidate_executed` 代签。

## 依赖与可复验闭包

- Node engine：`>=22.0.0`
- TypeScript：精确 `5.8.3`
- Three.js：精确 `0.185.1`，MIT
- `package-lock.json` 固定 npm integrity；禁止提交 `node_modules`。
- `npm run build` 从安装包复制 `three.module.min.js`、其依赖的 `three.core.min.js` 和许可证，编译 `runtime/**`，并生成 `runtime-manifest.json` 与 `vendor/manifest.json`。manifest 为每个 runtime/vendor 文件记录字节数和 SHA-256。

规则身份：`wargame-demo-v0.1.1`。其中 `baseRulesVersion=wargame-demo-v0.1`，`rulesExtensionVersion=phase-a-production-cancel-v1`；旧录像不会被误标为兼容新取消命令。

```powershell
chcp.com 65001 | Out-Null
Set-Location launcher/web/modules/minigames/warlord
npm ci --ignore-scripts --no-audit --no-fund
npm test
npm run test:browser
npm run serve
```

开发页：

`http://127.0.0.1:4178/modules/minigames/warlord/dev/harness.html?qa=1`

Slice 3 的 `preset=all-units` 浏览器门还固定验证“红方补给 3 个 CommandElement → 选择 2 个合并为单一父 token → 父 token 射线点击与局部框选均展开完整 member → 依次切换五阵型 → 拆出 1 个 member 恢复 singleton”；合并、阵型与拆分全程行动点/已消费行动点不变，父/成员控制面不重复，并在路线预览同时显示行动消耗、规模、战斗负载。

可附加：`preset=all-units`、`difficulty=easy|normal|hard|extreme`、`seed=...`、`theme=desert|tundra`、`webgl=0`。`qa=1` 会执行 48px 局部/全域节点导航与 40px 命中区、Demo 1 九节点及 Demo 2 八十节点、11 个卡牌 identity / 8 张普通底栏卡分流、三名中文 Boss 指挥官、语义地标、主题重绑、Three/fallback、战术徽章、棋子选择/框选、直接下令、头像 identity、多视口排版、相机三级披露、高节点滚动、输入隔离、可见 toast、完整战斗播放和生产调度循环；Demo 2 另锁定四方紧凑顶栏、中文检索/告警、六节点虚拟窗口、14 页全图覆盖、颜色+线型双重阵营语义、战区抽屉默认收起/`Esc` 回焦和兵牌 `120px → 32px` 折叠，固定画布最小到 800×450 不得出现普遍文字溢出。

`npm run test:browser` 使用项目自带的 Microsoft Edge/CDP runner 和一次性 loopback 端口/profile，等待 QA 终态，抓取 Demo 1 多视口/编组/战斗/生产场景与 Demo 2 大图、检索、告警和四方顶栏，并将 QA、console、runtime、network、命令意图/战术相机/主题/生产状态与清理结果写入被忽略的 `artifacts/browser-qa/summary.json`。该命令仍是普通 Edge harness 证据，不是 WebView2 证据。

2026-08-24 Phase A.8 fresh 机器闭包为：runtime build `68` 文件、vendor `4` 文件，runtime verifier `71` 文件；Node `69/69`，纯相机测试锁定 220% 约 1.483 倍、极端近距最高 1.8 倍的渐进美术缩放，生产 presenter 继续锁定跨 node/slot/queuePosition 的头像订单投影；32 局模拟完成，红 `17` / 蓝 `15`、淘汰 `29` / 回合上限 `3`、`invalidStateCount=0`、`commandGuardHitCount=0`，战果数字与 Phase A.7 相同；Edge/CDP `15/15`，完整循环继续覆盖订单头像定位、撤销与 EXACT 不误下单，截图场景同时排入 `4` 种单位并投影 `4/4` 头像，220% 战术近距聚焦红方总部四枚徽章并记录 `pieceScreenGrowth≈1.483`。三视口无溢出，console/runtime/network/external failure 均为 `0`，browser/server/profile 均清理。应用内 Browser runtime 在本机没有可用 browser instance，因此可见证据来自项目 Edge runner；这些结果停在普通浏览器候选层，等待维护者实际操作验收。

2026-08-24 Phase B.1 fresh 源码门为：包内 build/verifier/Node 继续 `68 + 4 / 71 / 69/69`，Edge/CDP 继续 `15/15`；共享 Minigame QA 全套 `57/57`，其中 Warlord `3/3` 锁定 closure、同 seed 终局和 read-only exact close；Launcher focused `260/260`，全量 `4059 passed + 3 explicit opt-in skipped / 4062 total`，文档治理与 minigame final-state 均通过。以上证明 Launcher 源码闭包与普通浏览器候选，不证明真实 WebView2、AS2、部署或正式入口。

2026-08-24 Phase B.2 fresh 源码门为：包内 build/verifier/Node 继续 `68 + 4 / 71 / 69/69`；Edge/CDP 增至 `16/16`，新增压力场景注入 `14` 个额外行动节点，证明正文产生真实滚动而“结束红方行动”的屏幕位置不变，并在展开相机后证明相机卡与规划条矩形零交叠、右上锚定不漂移。三视口继续无 overflow，console/runtime/network/external failure 均为 `0`；共享 Minigame QA `57/57`、minigame final-state 通过；Launcher 全量 `4060 passed + 3 explicit opt-in skipped / 4063 total`。这些结果证明源码与普通 Edge 候选的布局合同，不代签真实 WebView2 人类观感、AS2 战斗、candidate、promotion 或部署。

2026-08-25 上游整合后的 Phase C fresh 门为：包内 runtime `70`、vendor `4`、closure `73`、Node `75/75`；本机 Node `20.12.2` 低于包声明 `>=22`，只记兼容性实跑。Edge/CDP `16/16`、共享 Minigame QA `57/57`、Warlord `3/3` 与 minigame final-state 均通过。Arena calibration checks `14` 项与 Agent entry contract 通过。仓库 resolver `7/7`，精确 .NET SDK `10.0.300`；Launcher Release/xUnit 为 `4099 passed + 3 explicit opt-in skipped / 4102 total`，testhost 串行。Flash CS6 从合并 AS2 源重新 publish：`225` 份 `.as` BOM 门、fresh Compiler `0/0`，`asLoader.swf` 为 `1,141,507` bytes / SHA-256 `690C1C871FFF915BCEFC17158146B79F805D70A69793014095343019F0454539`；publish-only 未刷新 `flashlog.txt`，不构成新增行为 trace。人类行为证据绑定替代候选 `warlord-c4-resume-0825`（identity `1044015BB54FA8BD989E812F8C7C381A84EF2E5007D53419C26DFE89D2FED4C7` / closure `BDB6E561A330841B923C37F2AA9EDAA39D61CB601DFEE6BC9B4E644EDB62B8E5`）。正式 runtime 现绑定 tag `runtime-build-v2/20260825-warlord-as2-battle-v2`、identity `6482B71F2811065A5537F5CDCB0E338D44C23C2BECDC13987D9924B289EC8C59` 与 closure `4B46C47478DAC64E038F574F2636AFDFF9E0E6EA16F807171FF5F31E21237062`；双构建、38/38 policy、promotion、远端 audit 及正式身份/生命周期 smoke 均通过。

2026-09-01 vNext Slice 1～3.1 调优后的 fresh Web 机器门使用 Node `24.19.0`：runtime `110`、vendor `4`、closure `113` / `1,833,859` bytes，Node `131/131`；两套严格 TypeScript 编译通过。Edge/CDP `21/21` 在 stage-v1、帮助、三视口、Three/fallback、行动/结算/排产/战斗和完整编组流程上，锁定九节点距离映射、选中据点紧凑摘要、完整无障碍/命令说明与精确 `180/360/650` 投影；1024×576 左栏滚动可用高度为 `256px`，console/runtime/network/external failure 为 `0`，browser/server/profile 均清理。共享 Warlord QA `3/3`、minigame final-state 和 runtime verifier 通过；精确 SDK `10.0.300` 的 Warlord+Arena focused 为 `37/37`，设置显式 `CF7_NODE_EXE` 后 Launcher 全量为 `4545 passed + 3 explicit opt-in skipped / 4548 total`。fresh Flash focused runId `bda3e940ce394913b027b2246443d460` 为 `115/115 assertions / 10/10 cases`、Compiler `0/0`、32K retry `0`，覆盖 `180/360/650`、2～4 人、五阵型、54/96 间距与三种中心位置的边界/唯一/不重叠；随后 publish 的 `scripts/asLoader.swf` 为 `1,230,798` bytes / SHA-256 `5C9E9FE639403C906E2CFA0FD96C3EC884C65DE08BB2164841971AA8DFAD5A87`、`10,939` functions、最大 `54,560B`。publish-only 未刷新行为 trace，行为结论来自前述 focused fresh run。

2026-09-01 Slice 6.1 原生跳帧重建后的 fresh Web 全量为 `175/175`，覆盖 N 阵营、固定关系、三个 VictoryGroup、四指挥官 ledger、11 个定义/8 张普通排产卡分流、玩家/AI 共用 validator、80 节点 thick-X、canonical digest、AI 未开战恢复、主角纸娃娃 tuple、玩家主角/战宠 receipt 分型、exact stage-terminal envelope，以及 strict `warlord.as2-resume-apply.v1` 与“inner frozen 不得自动 outer terminal”门；Organization digest 为 `sha256:7FBBFE6B24592A7356B6AC9CACB14D49803FBA2214D8A9FFBD71599211114DA3`。Edge/CDP `25/25` 另锁定 exact Demo 2、战区抽屉、兵牌折叠、三个固定画布、仅 exact fielded player-avatar 棋子使用 `MercPortraits`，普通狙击兵继续使用 `EnemyPortraits`；console/runtime/network/external failure 为 `0`，browser/server/profile 均清理。scene-perf `4/4` 继续锁定路线批次、overview instancing 与 teardown。

2026-09-02 r8 的 historical fresh 机器门曾记录：产品 `scripts/asLoader.swf` 为 `1,253,536` bytes / SHA-256 `9B444AD18B59C78B1D3DEAA393E2640F5C40F962914DAF94E0C26AC83ED962A4`，`11,143` functions、最大 `54,560B`；fresh Flash Action runId `e407360f32a1469f9741ac650d19cdcb` 为 `151/151`，SubStage 为 `122/122`。Web build 为 `128` runtime + `4` vendor，verifier closure `131 files / 2,106,570 bytes`，runtime manifest SHA-256 `A2C4C1CAF241FDBBACF4FA461AF849C66A485E8A30CB2BE8E772A2EDF0CB3FFA`，Node `178/178`、Edge/CDP `26/26`。这些数字只绑定后来真人失败并 supersede 的 r8 generation/lease/teardown/90-frame 方案，不能证明当前折叠源码。

失败候选 `warlord-s6-commanders-0901` 暴露摘要拒绝、AI 无限重试与错误头像；r2 暴露瞬态/空装备纸娃娃、狙击兵棋子、首次进攻双 `not_started` 与错误 terminal envelope；r3 因在外层沙盘启动前清理 `wuxianguotu_1`，三次真实 GameStage 均在 `activeFrames=0` 直接 failure；r4 暴露 Action world 覆盖 HUD、战后黑屏、伪恢复重置与后续 `encounter_frozen`；r5～r8 继续证明 locator/depth、同名 MovieClip 身份、generation/owner/teardown receipt 与跨 root tick/scene-level 90-frame 审计都未形成可维护闭环。r9 的 PREFER_B 场景折叠已能正常战斗和回沙盘，但真人仍发现连续敌方运镜往返抖动、主角结算误显示精锐狙击、普通演员在视觉就绪前开战并瞬间结束，以及返回基地后旧 outer owner 泄漏、fresh Demo 1 被“恢复演习”/Host busy 阻断。因此初始至 r9 均固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`。r10 保留 `StageManager + 临时普通 StageInfo + 标准 wuxianguotu_1/frame209`，删除整局 recovery/retry/revision+1，补齐 outer-only cancellation、批次相机、player-avatar 结算与 actor visual-ready 栅栏；源码机器门已通过，隔离 candidate 的 Core SHA-256 为 `DDC325441769B1BDA844276D64D4DF65A5221BFFDA8EEDACD4D2486AE45E10AE`、build identity 为 `29606003E974A75ECA28000A288FD0FC0D1D7AF32163E5A7156D022DF8C93C47`、payload closure 为 `5C2D37472D8B15C3BAF0DBFBADBCAFE52CB5ABF5FC525A1F03CD95E891868752`；该轮进入真人门前曾为 `R10_SOURCE_MACHINE_VERIFIED / R10_CANDIDATE_BUILT / HUMAN_ACCEPTANCE_PENDING / NOT_DEPLOYED`，随后由下述真人失败结论 supersede；正式 Core、formal closure 与 deployment 均未改变。

2026-09-02 r10 fresh 机器证据：Web Node `188/188`、Edge/CDP `26/26`；Host focused `138/138`、canonical 全量 `4583 passed + 3 explicit opt-in skipped / 4586 total`；Flash Action runId `82bd63ecd49a475e82837134f6cf11b5` 为 `60/60 assertions / 3/3 cases`，SubStage runId `089298531cb14aafa7d72481658640d5` 为 `78/78 assertions / 10/10 cases`，均为 Compiler `0/0`、32K retry `0`。publish 后 `scripts/asLoader.swf` 为 `1,243,780` bytes、SHA-256 `9CCA43E3D44D33C33BE5AE2368494B897C59DADE759A2E56CD5E1E33B9BCEDA2`、`11,031` functions、最大 `54,560B`。这些数字不代签 candidate build、真实 WebView2/AS2 旅程或人类验收。

2026-09-03 r10 真人失败：Action 的 world/HUD 层级与敌方生成正常，但主角装备未加载、显示女性基础体且不可操作；正常游戏中的同一存档无异常。日志显示 Host 取得的是完整女号男变装纸娃娃 tuple，而 Action 内 `fs` 进入 `[AI]` 更新。根因是 Warlord 在 `加载游戏世界人物` 返回后、延迟玩家初始化完成前，把 `_root.控制目标` 改为镜头；StaticInitializer、DressupInitializer 与 UpdateEventComponent 因而一次性选错分支。r10 固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`。

2026-09-03 r11 fresh 机器证据：Web build `128` runtime files，verifier `131 files / 2,154,123 bytes`，Node `194/194`、Edge/CDP PASS；Host Warlord focused `88/88`、canonical 全量 `4583 passed + 3 explicit opt-in skipped / 4586 total`；Flash Action runId `0b9c54e298654d22879e5fbe5371d835` 为 `63/63 assertions / 3/3 cases`、Compiler `0/0`、32K retry `0`。publish 后 `scripts/asLoader.swf` 为 `1,244,629` bytes、SHA-256 `A98C7645EA0C2E65811E51DDD2C93A6C69B59A63433D4FED15357285195E6FC5`、`11,035` functions、最大 `54,560B`。隔离 candidate `tmp/runtime-candidates/v2/warlord-s6-capture-r11` 已通过 `integrity-only / 33 files`，Core SHA-256 `DDC325441769B1BDA844276D64D4DF65A5221BFFDA8EEDACD4D2486AE45E10AE`、build identity `29606003E974A75ECA28000A288FD0FC0D1D7AF32163E5A7156D022DF8C93C47`、payload closure `5C2D37472D8B15C3BAF0DBFBADBCAFE52CB5ABF5FC525A1F03CD95E891868752`。正式 Core、formal closure 与 deployment 均未改变；机器证据不代签真实主角、染色观感或 Slice 6.1 人类验收。

2026-09-03 r11 真人持续战斗失败：同一局第 26 次 `battle_start` 已完成面板 exact close（generation `27`、`p:0`），Flash 仍约 `29.8 FPS`，但只有前 25 组 transition/frame 209/world/terminal/resume；第 26 次 `callId=wb.7.556.26.mtkuamzr` 无 AS2 start admission。`request len=485755` 是 UTF-16 字符口径，实际 UTF-8 已逼近 Host `512 KiB` 硬门；本地 `Write + Flush` 不是 AS2 receipt，也没有证据称 GameWorld 创建失败。r11 固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`。

2026-09-03 r12 机器证据：Web build `128` runtime + `4` vendor，verifier `131 files / 2,156,557 bytes`，Node `199/199`、Edge/CDP PASS；Host canonical `4623 passed + 3 explicit opt-in skipped / 4626 total`，其中一个 AgentRuntime 测试幂等清理竞态修复不是军阀产品逻辑。fresh Flash Action runId `58979c2d27b843618a13d9f0d4fe3265` 为 `97/97 assertions / 4/4 cases`，SubStage runId `93a43ea8763741c4a7ef361a83609a55` 为 `78/78 assertions / 10/10 cases`，Compiler 均 `0/0`；`scripts/asLoader.swf` 为 `1,255,514` bytes、SHA-256 `B5EA5E3B8FAB9B9D3C1EAAFBBCD9D4FE0458D987B6A67DC3B6A36A78B3207126`、`11,119` functions、最大 `54,560B`。`warlord-s6-handoff-r12` 通过 `integrity-only / 33 files`，并于 11:36:27 从标准根入口实际到达 Ready；Core PID `24268` 精确运行该 candidate，Flash PID `25604` 与 guard PID `16584` 为其子进程。该轮曾达到 `R12_SOURCE_MACHINE_VERIFIED / R12_CANDIDATE_EXECUTED / HUMAN_ACCEPTANCE_PENDING / NOT_DEPLOYED`。

2026-09-03 r12 真人结算失败：首战播放到 `7/7` 时，阵容内容把 footer/controls 挤出 battle dialog 可视区，`max-height: 510px; overflow: hidden` 将其确定性裁切；按钮仍在 DOM，故旧测试的 selector/脚本 click 没有发现实际不可命中。播放弹层期间隐藏沙盘还反复重启 rAF 窗并继续 update，同轮 Intel iGPU 约 `93%`；证据只覆盖播放期，不声称关闭后永久 rAF 泄漏。r12 固定为 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`。

2026-09-03 r13 失败证据：`warlord-s6-settle-r13` 虽通过 Web `199/199`、Edge/CDP `26/26`，真人首战结算仍卡死且 Intel iGPU 持续高负载，随后整机非正常重启。应用日志停在 `warlord_battle_resume_applied accepted`，系统只有 Kernel-Power 41，没有新鲜 Display/WHEA/bugcheck/dump；因此只确认 `HUMAN_ACCEPTANCE_FAILED / SUPERSEDED / NOT_DEPLOYED`，不武断声称 GPU 驱动根因。

2026-09-04 r14 当前证据：`warlord-s6-gpu-r14` 将沙盘从“隐藏但保留”改为交接/modal/close intent 即时销毁 WebGL 资源与 canvas；resume 直接打开最终静态结算，不再自动逐 tick 播放；结算遮罩无 `backdrop-filter`；启动页 WebView2 在 reveal 后单向退休。fresh runtime 为 `128` + vendor `4`，verifier `131 files / 2,180,127 bytes`，Node `201/201`、Edge/CDP `29/29`；Launcher 全量 `4628 passed + 3 explicit opt-in skipped / 4631 total`，Bootstrap harness `10/10`，GameLaunchFlow `71/71`、reveal-watchdog `11/11`。candidate Core DLL SHA-256 `B4C0492043E66DA38A14DEA287F455424E708C0D33EC0DF5E236FF15124B365F`、build identity `DD8A23ED8D96F17DAE96ABCEC5679FDA05931F0FB47CD74C35F2F608F16E4731`、payload closure `1AA98BAC9DB304CED4A0239CCE6EDFB4C528376C578F16A58798A264FC4A9C6D`。首次选择 `dev` 时，r13 死机留下的损坏 SOL 触发安全超时；原文件已按 SHA-256 `0D302C5CDA6FE8EA1481842F2DC56CC6B3DE0EDEB011FEADEC5225693A35C9AF` 可恢复隔离，合法 `dev.json` 保留。随后真实根入口精确记录 `snapshot source=json_shadow`、同 attempt `s:1|ga`、panel reveal、Bootstrap WebView2 retirement 与首场 Action admission；Flash 新写 SOL 已由当前解析器样例成功读取。准确状态为 `R14_SOURCE_MACHINE_VERIFIED / R14_CANDIDATE_EXECUTED / HUMAN_ACCEPTANCE_IN_PROGRESS / NOT_DEPLOYED`；正式 Core 未改变。

## 验收层级

1. Node：原 39 条 AC/AI 测试必须保持名称和行为；新增 presenter/lifecycle/portrait mapping/production projection/selection policy 测试不得替代它们。
2. 普通浏览器：Edge/CDP harness QA、console/runtime/network 零错误、三视口截图、WebGL 与强制 fallback。
3. Launcher 源码：共享 lazy registry、Overlay CSS、Host 精确关闭、测试菜单、focused tests 与 minigame QA 总入口。
4. Launcher 候选：实际 `https://overlay.local` 动态 import/MIME、WebView2 键鼠、关闭/重开与 GPU 资源释放。
5. AS2 源码：冻结 request/receipt、petId+Identifier、隔离升阶、暂停交接、内外层 `not_started/unknown` 分域、actor visual-ready、outer-only cancellation、只读经济观测与 receipt 回放的静态/单元合同。
6. AS2 物理链：Flash CS6 fresh 发布、runner、r12 admission 与 r14 Web/Host 图形退休机器门均已完成；r14 真实标准入口已到达同 attempt game scene 并进入首场 Action。真实主角完整装备/键盘控制、普通演员可见互战、静态结算 controls/GPU、连续战斗、最终返回基地以及玩家存档/货币/战宠无污染仍等待当前真人旅程完成。
7. 人类感知：沙盘 UI 与 AS2 战斗结束自动返回均已获维护者验收，且体验评价有效；该候选感知与随后 formal runtime 身份/生命周期 smoke 分属不同证据层，不能拼接成部署后的军阀业务 E2E。

现役 Phase C 已完成第 3 层、第 4 层 Warlord 面板主旅程、Phase B.2 UI 人类验收、第 5 层源码合同、第 6 层 AS2 战斗和恢复主闭环，以及正式 runtime 的双构建共识、promotion、post-promotion audit 与身份/生命周期 smoke，状态为 `HUMAN_ACCEPTANCE_PASSED / promoted`。vNext 的初始至 r13 候选均已 `FAILED / SUPERSEDED / NOT_DEPLOYED`：r11 停在第 26 次 admission，r12 停在首战 `7/7` 结算 controls 裁切及播放期多余渲染，r13 停在首战结算卡死/核显持续高负载。当前 r14 保留 ordinal canonical digest、内层 AI `known-not-started` 有界收束、有界 handoff、exact admission、权威装备纸娃娃、player-avatar 专用棋子与结算、stage exact terminal/close/resume，以及 `APPROVE_COLLAPSE / PREFER_B` 的四 owner/单时钟/零 lease/零 terminal rewrite；进一步在交接/modal/close intent 即时销毁沙盘图形资源、用最终静态结算替代自动重放，并在 game reveal 后单向退休 Bootstrap WebView2。Web `201/201`、Edge/CDP `29/29`、Host 全量与真实根入口恢复/首战 Action 已通过，但结算/GPU、连续战斗和 Slice 6 人类玩法尚未完成，不能继承现役 Phase C 或任何失败候选的部署/验收结论。正式 Core SHA-256 `AE0E56CFCA82E12DE54845636D36A3F2D5E9D9EFE94A7BFC30228B21E00F8E8B` 未改变；战宠经济仍只有 observe-only 双刻度标定，不授权任何正式玩家状态结算。
