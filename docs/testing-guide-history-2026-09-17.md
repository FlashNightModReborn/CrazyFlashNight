# testing-guide 历史归档（2026-09-17 一次性迁移）

<a id="archive-meta"></a>
## 档案属性与冻结来源

本档案是 2026-09-17 的一次性迁移档案，**不建立后续追加惯例**：以后的发布收据、验收证据按各专题 ADR 与 `docs/evidence/` 的既有通道归档，不回写本文件。

- 冻结来源：`agentsDoc/testing-guide.md` 全 114 个物理行，source SHA-256 `5eb88fb231eb2c8858cf96f7bff310e3fcee247eb85dcf30006d8e8b3002ccc0`，冻结 HEAD `2e5e32321506fa1fb2693f3928205f8c45b4235e`。
- 逐行处置台账：`tmp/docs-decision-return-20260917/evidence/TESTING_MIGRATION_LEDGER.json`；决断与边界见同回包 `DECISION.md` §6.2。
- 本档案收录的是**历史证据**：旧 release tag/request/identity/closure/deployment/audit、旧通过计数、旧候选状态、已被取代口径。它们**不是**当前权限、规则或部署状态。当前规则正文在 `agentsDoc/testing-details.md`；当前发布身份只读 `config/build/runtime-release-consensus.json`、`runtime/cf7-runtime-manifest.tsv` 与 `docs/runtime-build-reproducibility.md`。
- 既有 ADR 更完整时只引用 ADR 路径，不复制整段长收据；混合行中已拆到 details 的活跃规则，本档案最多指向 details 对应锚点，不复制。
- 每条注明来源行号（「原 L n」指冻结 testing-guide.md 的第 n 个物理行）。

<a id="archive-receipts"></a>
## 按专题/对象记录的历史证据

### 发布列车收据（按日期）

**原 L1：2026-08-30 测试反馈稳定性修复列车**（本页标题基线）：release source `5789d597fbb7af32753fe4a35887b1f2a3a34e10`，deployment `3e23bda255dae09e20e309a12c5b21d86b28f347`，当时状态 `promoted / FIELD_REVALIDATION_PENDING`，post-promotion Audit 输出 `state=promoted`、`deploymentChanged=true`；部署后只执行根 bootstrap `--verify-only`。完整收据见「SaveManager /
测试反馈」段（原 L108）。

**原 L1：2026-08-28 斗兽星期级全量标定 Gate F 正式发布门**：tag `runtime-build-v2/20260828-arena-calibration-gate-f-v3`、request `62E4E1537771F0638DB9204A950DD19598962F7E8BBE7D73E2916FAB519982FE`、identity `48E2ACEA81194C0D6C3A89226DEC2748192612B5514D3F3ADB8444FA4AF6C528`、
closure `DA7E5BD135FF2407ED7CE459F521BEA95C9CB6F5CC63AA5291ABAC795DAF59F1`、39/39 production policy、双 signer / 双 faultDomain、deployment `693baf7051d9e67be8930b309dc14eea65c0eab6`、post-promotion audit run `33130680653`。首轮 `gate-f-week-full-v2` campaign 的 `f-soak-01/02` 为 20/20 finished，`f-soak-03` 为 8 finished +
B11/C12 原向 2 timeout；三轮 exact formal runtime、JSONL、正常关闭、零 recovery 与受保护存档不变均成立，失败只来自候选 timeoutRate。v4 的三份 fresh soak 已 30/30 clean；全量累计 16 个 completed shard + 1 个 F2 anomaly shard、280 条 durable row。F2 p2 原向 10/10 finished、换边 5 finished + 5 timeout，0 error；旧 driver 把纯 timeout-rate 误作基础设施失败。
修正后的 tracked `gate-f-week-full-v2` plan / `gate-f-week-full-v5` campaign 固定 58 个 scheduled candidate + `B12` quarantine、198 个 10–25 run shard / 3,255 run；v5 草案当时未 `freeze/arm` 或实跑。

**原 L1：2026-08-27 库存真批量转移正式发布门**：tag `runtime-build-v2/20260827-inventory-batch-transfer-v1`、request `BA233DEDA6FC141F195C2F58E0D71C47872C0ADF309128E3D1B06BCBD127E774`、identity `E746A365F2715556A3298C4CBF1E926F039BC147625D4612F850768C9A52ADA3`、closure `8175440099ECF58708CD35F81F9C4A0B81390EC64EF2896D96EB885779A20475`、
39/39 policy、deployment `4d5fd254752a149ce07006f8f48391ab26485f61`、audit run `33034014440`。当时 fresh 门：inventory runtime 87/87、workbench modules 36/36、KShop Edge 153/153、Inventory Host 271/271、Authority/Inventory focused 324/324、Launcher 4257 pass + 3 opt-in skip / 4260、Shared TestLoader EquipmentInventory 28/28 +
Inventory 170/170、Compiler 0/0、32K retry 0、KShop visual atlas 66/66、item-grid 20/20、strict workbench audit 0/0。publish-only `scripts/asLoader.swf` 为 1,148,358 bytes、SHA-256 `9D19F227F580F7E4B71B623A2AA2F9CF50F9027E14852F19E5881781D7528B8B`、10,320 functions、最大 48,872B。同进程对照：50 件旧逐项约 673 ms、新 batch 约 20 ms；
维护者隔离 candidate 实测 10/31 件约 423/277 ms 返回 success。专项 `HUMAN_ACCEPTANCE_PASSED / promoted`；未执行写后重启读回，不外推持久化 `standard_entry_verified`。promotion 后第一次 formal smoke 的 trusted runner `exit 2` 未采信；第二次独立 fresh run 窄纵切 `standard_entry_verified`（未执行库存写）。「下文未带后续日期的 Inventory `144/147` 现役门槛均由本段 170/170 取代」——该 170/170 此后又被取代，
当前机器钉值见 details [库存 suite](../agentsDoc/testing-details.md#suite-inventory)。

**原 L1：2026-08-26 打击伤害数字 C# 原生化正式发布门**：tag `runtime-build-v2/20260826-hit-numbers-csharp-v1`、request `99FA28B523CB89C3F68B14DEBE2DEC4A1C6B6E2A966DBEB665F605753290890A`、identity `3B075D1FD1E429137253315E5B2095B4D3C942FE42D039E43D55C93625FDA187`、closure `8E25D01458A05334FF1CFF44CB9A1F0E8B1BCE6420A4DE21D41B4D648479CF1D`。
当时门槛：Hit Number focused 97/97、Settings Host/Web 20/20 + 18/18、Launcher 4213 pass + 3 skip / 4216，视觉样本 26 图 + 2 视频、平均 0.910 ms/frame、GDI 3→3。维护者已接受与正式 Core 同字节的 D8 候选；专项 `HUMAN_ACCEPTANCE_PASSED / promoted`，不称业务 `standard_entry_verified`。

**原 L1：2026-08-25 限时关卡 TimePool 列车**：tag `runtime-build-v2/20260825-stage-time-pools-v3`、request `ADDBA21EF66AA9429D00D349E0ACD33F27BE55641CB3B9F541ACB6BEAC47D043`、identity `50ED16457B8C82787A495F957259A9544AD96C819E8D1EF11087D5AF06E0BFB0`、closure `60981913A1D18682C06B6ABF2CC6DB7EC0F57345BAF8B1D372E67D7EC3ADE5EB`。当时门槛：
configured=3 / pools=3 / refs=9、AS2 46/46（8 cases）、Launcher T 投影 16/16、全量 4115+3/4118、Compiler 0/0、runtime v2 181/181、policy 39/39。部署后 formal attempt `eb0d6743820512eccccfc6138cdf5605` 只覆盖身份/生命周期，明确未执行 JK、核电站或断壁残垣业务；限时关卡 `HUMAN_ACCEPTANCE_PASSED / promoted`，仅身份窄纵切 `standard_entry_verified`。

**原 L1：2026-08-24 LoadoutPicker scope/anchor 纠偏 fresh 证据**：Character production 370/370×3、standalone 218/218、session 36/36、projection 8/8、Team 222/222×3、Host 定向 228/228、Launcher 4085+3/4088、Merc AS2 113/113、Character focused 六套 580/580（含 CharacterBuildService 194/194）、两次 Compiler 0/0、32K retry 0。
当时 `run-character-build-tests.ps1` 的 writer dirty/readiness 静态前置因与本修复无关的 DrugInputService/ItemUtil 文本合同失配而提前报红；该轮只用其 exact focused runner/suite 取动态证据，不把 wrapper 冒称全绿。

**原 L3：2026-08-28 双药剂组正式发布门**：release source `b2bc05775c621616fe64be55354aebe21c63a2af`、tag `runtime-build-v2/20260827-dual-drug-banks-v1`、request `9FE68E5BEB945B969A2D4CDAA1D20B2D2838A4208DB8773EF7344918B0383658`、identity `6C9CF4699C217CC65083038D3AA69B0D6640C4E8DF5A50D367D0628E366D379D`、
closure `1D0C3A1272CD084ECC9532B0565E017E07A233C1511B4372C091FF081701252F`、39/39 policy、deployment `6902b2b6ed067c4882e9a67267d055ce0db90b34`、audit run `33092179946`。当时 fresh：player manual 486/486 + 57/57 + 55/55 + 14/14、Settings 44/44、Character focused 674/674（Save 208、Equipment 28、Inventory 170、transaction 19、
RuntimeProjection 17、Character 205、PlayerInfo 27）、EquipmentTuning 78/78 + Inventory 170/170、item-panel 437/437、KShop 32/32、Host focused 266/266、Launcher exact SDK 10.0.300 全量 4308+3/4311、Web session 37/37、projection 8/8、facets 16/16、三视口 222/222、workbench 1110/1110 + 12/12 + 18/18、Settings 18/18、Settings visual 116/116。
PlayerInfo `○ / × + 1 / 2` SWF 105,013 bytes / SHA-256 `63FAD7E1DFCB28E2928FC6B7B7514D355ADDDA0286EFB936C0037FB948C2D764`；asLoader publish-only 1,165,754 bytes / SHA-256 `0CEBD6FAE41DE4CDF7DAB26926E0536968609F714432BE7E8403A52B43DF1415` / 10,439 functions / 最大 48,921B。
部署后前两次 formal smoke 因 Default input desktop `GetForegroundWindow()==0` 按 30 秒门 fail closed 不计成功；第三次 run `2478a9f25873043318f2402f80105b52` 窄纵切 `standard_entry_verified`，`businessJourneyExecuted=false`。注意：
player manual 文本中 DrugInput 55/55 已被当前 runner 钉值 58/58 取代（见 details [设置面板](../agentsDoc/testing-details.md#suite-settings)）。

**原 L3：2026-08-27 角色构筑运行态装备投影 fresh**：runId `415c05624d63408ba283bfbeee2a7046` 为 626/626（SaveManager 165、EquipmentInventory 28、InventoryPanelService 170、transaction spike 19、RuntimeEquipmentProjection 17、CharacterBuildService 200、PlayerInfoProvider 27），Compiler 0/0、32K retry 0；Node session 36/36、projection 8/8、
production workbench 370/370×3 + 1110/1110 + 12/12 + 18/18；asLoader 1,151,292 bytes / SHA-256 `BBFE72BA6CE5691EA3B0EF84AAF86D77B9FF2C2C03E30C236D0D48E4E0A7B20D` / 10,340 functions / 最大 48,872B。维护者确认「打开构筑不再清空现有 Buff」窄行为 `HUMAN_ACCEPTANCE_PASSED`，不代签物理 WebView2 协议、存档重启、candidate、promotion、部署或 `standard_entry_verified`。

**原 L3：2026-09-16 现场对白与审阅修复**代码基线 `7497f5cf429c81a787b06d9485b0cf5c9c422377`；**2026-09-12 原生交互增量**基线 `cde09af935`（当时未人验或部署）；**2026-09-10 问题 4/5 修复增量**基线 `d872090711`：玩家资产事务 runner 由 117/117 更新为 124/124（当前机器钉值一致），StageRunSessionTest 由 519 更新为 527 项（原 519 + 返回身份 8 项；此后又被 594 钉值取代）。

**原 L5：玩家物资异常安全门列车（2026-08-23）**：实现基线 `8e785dd7cbeb`；当时门槛 117/117（静态门冻结 production begin 26 个、direct-authority caller 22 个，其中 21 个 direct-authority caller 与 2 个 XFL facade begin——原文如此）；
focused/TestLoader/publish 证据进入 source `416c4441947d40bc27ae3854178e87e2c5cf1ac9` 与 deployment `df060eac491c7251b261a3f5626960a8ea18911a`；部署后 formal smoke 只验证身份/生命周期。117/117 后被 124/124 取代。

**原 L6：AS2 审阅收口门（2026-08-23）**：ManagedLongGun 126/126（当前钉值一致）、combat-hp-impact 当时 153/153（当前钉值 159，见 details [关卡、输入与战斗](../agentsDoc/testing-details.md#stage-input)）；最终 fresh runId managed `328c2a73b0854ebc9190166db5e06f78`、combat `6e23c0624d0f48c5bfc97f26c8321ee2`；下方 68/68、140/140、43 条当时已声明为发布前历史。字体冻结前证据分层：
Node fontctl 33/33、Edge fixture 17/17、Launcher `RuntimeFontCatalogTests|PetCatalogTests` 21/21、cf7-packer 字体配置门 2/2。AS2 冻结前 focused 门：Settings 42/42、ManagedLongGun 68/68、combat 140/140（均被取代）。文档历史基线 commit `d049daed44a537ef586f9e6254fcb824b98c4ee1`（2026-08-22）。

**原 L6：2026-08-22 三列车发布状态**——T800 托管长枪：tag `runtime-build-v2/20260822-t800-managed-longgun-v1` / request `1643570AB50AE207B2D09AC55D6D1F374DD72990070B71423372B6F184497C8A`，physical-host-b + github-hosted-windows（run `32577704317`），identity `0A4478EF7C9D18BCF560B6AB8F2EBA66C255930FCDC361F5FECC36469509A522` /
closure `B18AB5EC8A2161621D55ED35C860C96248B9081772CC1DD4B911444815C2169C`，deployment `a22490867ebd03b931c3066141c0954b02be25da`，audit `32578381540`；正式 smoke 未重跑 weapon_tooltip/equip_weapon/withdraw_weapon，只称 `HUMAN_ACCEPTANCE_PASSED / promoted`。玩家物资事务：tag `runtime-build-v2/20260822-player-asset-transactions-v2` /
request `DD030AC6C7D780FBECC827D11828BD4959191AF182E46921CB480E3B08D4B8FD`，run `32548053397`，identity `6CD9AEB99B3B5A3DF470F1CDDD99DF11CF7F706394F9FD3AF6D5594ABC03BC78` / closure `60EA3AACDBFAAE178866317448FCEA0BEC0D3AA73E808AD4952ACF695571F62D`，deployment `b7f075e53c31c5d4b67e02dcda1978695321d33d`，audit `32548688437`；
未重跑无 candidate-id 业务标准入口。设置 Web Panel：tag `runtime-build-v2/20260822-settings-web-panel-v1` / request `9B9982BB290DF8E0132F52DD4CA842100E9003FB6ADAB71908D5797FB3C198D7`，run `32512318147`，identity `AD4B23A7489EB011EA4FC54004DC343F4FA5AF1FCA1D3BBD9452760D18EF1D78` /
closure `24747E9C71B31E1D7A82356D028A88C3D741CA7AF71D10AC2C97A920649A6051`，deployment `de24f449fba0f004193392a273d09b875a4c3935`，audit `32513484781`；`settings_camera_preview` 1600×900 WebOverlay WGC 单屏窄纵切 `standard_entry_verified`，不外推 Flash pixels/input、真实设置写入/存档重启、物理 WebView2 键鼠、听感、救援业务效果或全游戏 E2E。

**原 L6：设置镜头预览第五/六轮（历史）**：第五轮移除模拟器遗留 `max-width:720px`，Edge 1024×576 与 1600×900 各 50/50；当时日志的 `1600×900` 是输出位图尺寸，不能证明每像素由 Flash client DC 写入。第六轮 Agent Runtime 闭环：启动 surface 从 `200×101` 收敛为约 `1601×900`；修复前输出整体纯黑 55.96%、右 1/3 96.09%、下 1/3 98.13%；DPI Unaware Flash `windowDpi=96 / monitorDpi=144×144`，
物理 output 1600×900 而 GDI source 仅应取 1067×600；Host 逐轴换算 source 并 `StretchBlt` 后降为整体 4.50%、右 7.84%、下 3.65%，有效活动范围超过宽高 99%。该闭环不授予 Flash pixels/input，不代签缩放观感、真实设置写入或存档重启。

**原 L6：字体目录 Gate E**：维护者已于 2026-08-21 接受 HUD/Combo/伤害数字/符号/中文基线和艺术选择；机器与人工 Gate 均不代签许可证法律结论、runtime 双故障域共识、promotion、部署或标准入口。

**原 L7：合成持有量/标记/采购联动当时闭包（2026-08-30 NPC catalog 显式费率修复后）**：282/282 recipeId、Panel contract 5 domains / 31 commands 与 68/68 变异门、Crafting runtime 36/36、Panel runtime 41/41、Crafting 三视口各 `150+15+8+10+6+9+26+12+9+17`、NPC `133/133 + 23/23 + 2/2`、KShop `155/155`、AS2 Equipment 28/28 + Inventory 170/170 + Crafting 158/158 +
Synthesis 18/18 + NPC 66/66、Launcher 4449+3/4452。focused runId `c7106ac4298642479a1b47fc7fc92aa5`（850‰ 下材料详情 120→102 等），全量 runId `6d5dbe9f03be42af9068ff34e19a99f7`。publish-only asLoader 1,200,234 bytes / SHA-256 `2BB97CF1F2A364EAAA7C8C42691659D21DA647932193EEC712C9E29656CFD0A8` / 10,684 functions / 最大 50,215B。
维护者真实游戏确认「车辆已购仍无法导航」窄行为 `HUMAN_ACCEPTANCE_PASSED`。panel contract 5/31 口径已被 7/42 取代（当前机器钉值，见 details [K 店与 NPC 物品商店](../agentsDoc/testing-details.md#suite-kshop-npc)）。

### 选关、启动前门与战斗焦点

**原 L14：2026-08-29 启动前门最终候选与发布证据**：Launcher 4439 pass + 3 explicit opt-in skip / 4442 total、Frontdoor BGM focused 16/16；Web 建角 23/23、Bootstrap 9/9、Hairdresser 39/39、entry contract pass；AS2 建角 40/40、Character Build 共用链 692/692，均 Compiler 0/0、32K retry 0。publish-only `scripts/asLoader.swf` 1,186,360 bytes /
SHA-256 `ABFD2CA909916C8C3F0496ED8D777D2432A13CDCF2D899881656EF522A3869A8`；主 SWF 221,069 bytes / SHA-256 `D841F289FA999103D39580C7C84D98B3882DC32B2C044CF3E86D3F4E7311EA91`。XFL audit 与 HEAD 基线保持相同的 2 类历史问题，rename/fix dry-run 无写入，linkage map 重扫无差异；FFDec 确认 frame 82 reveal-ready、83–126 迁出页停帧与 130 旧读盘网关进入新 SWF。
source `95019c7e63492d9cb88c010d1ee06376281c590b`、tag `runtime-build-v2/20260829-frontdoor-authority-migration-v1`、request `86DC638511BFE275791BB2A2DEAC525F8B2CC51675DDD917C44F07F57C34E9DA`、identity `DBA565EFC247492C9921C24D664BC896083366346551F3145C993397304C4F4E` /
closure `B72DC4721E9062C3FE357259DCD41DB5DC2D74DA0CC524F781E89147FE872801`，deployment `fdb4fe30aa911bbac91d60d7c349c217fa71a78c`，audit `33255727460`；专项 `HUMAN_ACCEPTANCE_PASSED / promoted`，未从正式入口重跑普通读档等业务，不称业务 `standard_entry_verified`。

**原 L8：2026-08-29 战斗地图绕行、复活与焦点增量门**：维护者在与正式 Core 逐字节相同的 isolated candidate 确认地图锁定、返回后 HUD 清除、QQ/浏览器不被抢焦、跨按钮拖放不误触、同图重复复活后的普通技能恢复，以及 `复活×2.1万` 单行排版和两按钮命中均有效；当时为 `HUMAN_ACCEPTANCE_PASSED / promoted`，部署后只有 supply-chain、根 bootstrap `--verify-only` 与 post-promotion Audit 证据，不称业务 `standard_entry_verified`。
现役规则正文在 details [关卡、输入与战斗](../agentsDoc/testing-details.md#stage-input)。

**原 L101：Stage Select 通关返回口径沿革**：2026-08-26 纠偏门取代 2026-08-24 自动回流合同；纠偏门现役规则见 details [选关 suite](../agentsDoc/testing-details.md#suite-stage)。

**原 L100：Stage Select QA 计数增长史（历史）**：P2 起 40 例、P3 起 46 例、2026-08-16 逐关锁定原因专项 47、打磨批 50、打磨批二轮 53、2026-09-09 废城固定镜头后保留 57 项行为回归；计数基线 golden 于 2026-08-16 为 166 / 14 / 2 / 28 / 164（单一真值 `launcher/web/modules/stage-select/dev/stage-select-golden.js`，当前值以文件为准）。`run-map-loot-tests.ps1` 的 StageRunSessionTest 当时 519 项（整体 798 项）
，后被 527、再被机器钉值 594 取代。

**原 L72：屏外尸体 / 场景碰撞 2026-07-25 落地证据**：屏外尸体初次落地 static 19/19，fresh TestLoader 15/15、7/7 cases、0 failed、Compiler 0/0、32K retry=0，asLoader publish-only smoke 0/0 且 SWF 刷新；SceneCollisionManager 该轮 static 35/35，最终 fresh 回归 21/21、4/4 cases、0 failed。当前钉值见 details [关卡、输入与战斗](../agentsDoc/testing-details.md#stage-input)。

### 角色构筑 / 技能往返的历史证据

**原 L12：口径说明与 2026-07-30 AS2 fallback 退役 cut**：表内增量前 `138/138` 由 2026-07-28 增量基线 `142/142` 覆盖（其后又被更新钉值取代）；上游 PlayerInfo clean `1737 pass + 3 opt-in skip / 1740` 与本地 Workbench `1729/1729` 均为合并前 scoped evidence，`9118eb…` 冻结树须以当时 fresh rerun 为准。退役 cut 最终 fresh 汇总：Launcher 全量 `1896 pass + 3 explicit opt-in skip / 1899`、
0 fail（相对 `9118eb…` 减少的 6 个用例是随 fallback 物理删除而退役的测试）；Web 门为 Crafting 三视口各 120/120、Tuning 三视口各 115/115（model 61/61、runtime 25/25、confirmation 4/4、interaction 7/7、source-marker leaf 2/2）、Character standalone 218/218×3、production workbench 867/867 + 12/12 + 18/18、inventory modules 30/30、dressup 222/222、Loot 77/77 +
lazy 6/6、KShop 135/135、NPC 106/106 + reduced 2/2、Skills 150/150、focus integration 15/15、lazy closure 24/24、atlas 48/48、ratchet 66/66，profile contract 通过，strict audit 0/0。四轮 CS6 focused：Tuning runId `023878476c2b40148a31e8f895635a15`（55/55 + 144/144）、Item Panels runId `eb0e77b5337243f3976548fa7f3a8c37`（28/28 + 46/46 +
144/144 + 36/36）、Skills runId `57e94a734d264d66b6860a870fc2db4b`（50/50 + 48/48）、Character runId `d742450109cf4036882282c3ff4e61c8`（六套 539/539）。publish：`CRAZYFLASHER7MercenaryEmpire.swf` 472,599 bytes / `51EAEC3F27396255028AE17C96C5BFE2FE8545694C962FEC18A7EBB1E095E2EF`，`flashswf/UI/玩家信息界面.swf` 104,788 bytes /
`F5654B2932FFD62D703F38330D393163266F9EC6E8DFB0B3D7517E258FEB8990`，`flashswf/levels/基地场景合集.swf` 2,975,861 bytes / `B7F12C7AD9ECBA0C23FFDCCE86C460A1D5C2E9CC1D473A03D56706319E1293A4`，`scripts/asLoader.swf` 1,047,668 bytes / `DB5236FF20598186AFF131324BB22B5F15558FD8766FDB4279B37851658AD0F5`。该轮实际发布 main，
不能沿用 `9118eb…`「未编 main」的历史描述。GUI 人工验收已通过；source `f01f4b121a4ceebd7dae051f14bb511c5ae3f1cb` 经 tag `runtime-build-v2/20260730-workbench-no-as2-fallback-v1`、request `3BEBE136773D2C09022F01E5B3C176A788FE3D84E453F6500C6C560F03184C7B` 双 signer/双 faultDomain quorum 与 promotion 闭环，

由无参正式入口 attempt `8baf52bbcceb452da32da641e58d2922` 在 build identity `58F1C3F3B128B22CEA4EDAEF74B402976D13ACB09D4A934240FCCFF3FA7C0465` / closure `B529199F6CC00BC0687E8EED6950C6490F239C56E2A2D4AC27E90366CE2C8CAF` / Core `565C1F9710421E6B6CC5CB6DDA05DE36B8F1B22B3D7A7CA19617F9786C7D8A4B` 下复验到 `standard_entry_verified`；
首轮 watchdog fail-closed attempt `bfb6bfe515f14af58f9b4096c8c539dd` 保留为原始失败证据。

**原 L56：2026-07-28 历史体验优化增量基线**：clean `40853287…` 同源最终 Launcher 全量 1747 通过 + 3 opt-in 跳过 / 1750；Panel contract 4 domains / 23 commands、变异 62/62；Panel runtime 27/27；Launcher xUnit 1651+1/1652；KShop 三视口 111/111；NPC Shop 89/89；Crafting 三视口 99/99；Skills 三视口 148/148；共享 components 12/12、focus 12/12、focus integration 13/13、
inventory workbench modules 15/15、视觉 atlas 48/48、strict UI audit 0/0。CSS bundle 18 imports / 17,795 lines / 667,554 bytes / SHA-256 `3edf4d9adf25da206aa991336d3a58f4abb51fecd9c08e82e8ab9cd0d371161e`。情报溢出当时扫描 59 个情报配置；item-panel fresh：EquipmentInventory 28/28、NPC 46/46、Inventory 142/142、Crafting 34/34，
TestLoader 最大函数体 19,072B；publish-only asLoader 1,064,450 bytes / SHA-256 `7ABDAE15848FF516A622142D75A630FA6A8783AA541C1B4DFBB6BC7B81451BD8` / 9,719 functions / 最大 46,025B；独立 `flashswf/UI/物品与技能相关界面.swf` 65,521 bytes / SHA-256 `C92BEAF595A751171C13D6F8EC75C7F4A4A38E1698AB7A517581DEF69CF5403C`，
FFDec 确认 `__legacyMaterialOnly` 与旧提示串不存在。**本轮体验优化最终关闭**：exact source `7d869c5eadf224953b2c61ec7a6ceee2ca03055f` 依次达到 `candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`；build identity `3F7887ADF9041DFEDA74EEA26040A3628919A725B04D322FCE667791425F7B44`、
payload closure `A9B142A417CF2AC45EA19845144569391FCDEE8DF4235F5279A1EC5F0F9022F2`、Core SHA-256 `DADE2CC2206B9981FF390250BD0DF8FB5CC7393E8EF9FA378567B5FB9009CCA1`；证据统一见 [材料、商城与战备箱关闭证据](evidence/material-kshop-battlebox-workbench-closure-2026-07-28.md)。

**原 L58：2026-07-28 单向收口与当时双向施工证据**：单向收口：Launcher `1548/1548`（三类定向 `141/141`）；workbench 三视口 630/630 + hidden-body 4/4、standalone 194/194、tuning 83/83×3、dressup 211/211、Skills 132/132×3、KShop 93/93、item-grid 17/17、atlas 48/48、slot transition 18/18；
CSS bundle SHA256 `c629efdd46e0ddf758025f315aea3416cebd1a696faee1796e59507d82be044d`；Skill fresh 50/50 + 48/48；asLoader 1,061,235 bytes / SHA256 `33291ED41C14DA709A706831114C2E299C56641DC378D70A8439D7096EF1D45F`；rolling 证据见 `docs/evidence/character-build-skills-navigation-closure-2026-07-28.md`。当时双向施工 fresh 自动门（历史，
尚未构建 candidate）：Launcher `1579/1579`；Panel runtime 27/27；workbench 642/642 + 4/4、standalone 195/195、dressup 211/211、tuning 83/83×3；Skills 148/148×3、KShop 100/100、Crafting 79/79×3；skills modules 65/65、inventory workbench modules 14/14、session 22/22、tuning capability 25/25、slot transition 18/18、tuning runtime 25/25 /
model 51/51、inventory runtime 24/24、safe exit 7/7、components 7/7、viewport 4/4、item filter 22/22、lifecycle 8/8、focus 11/11、focus integration 12/12；CSS bundle SHA256 `00f7ba0d19201823e6c14e7db8215a34eb270ec93908436411154657c4aa8d54`；Character TestLoader 533/533；asLoader 1,061,358 bytes /
SHA256 `3FA6C69D8C762EB6198C31C3DAD92843E8E3EB7C1EA4C3EC51F8FE08D275F321`、9,707 functions、最大 45,868B；K3 终审 session `bc2345d4-42eb-47aa-9b03-5ea627bd5e3c` 裁决 GO（0 Blocker / 0 High / 0 Medium），但自动门与异构审阅都不等于 candidate_built/candidate_executed/e2e_verified/promotion/标准入口。

**原 L59：2026-07-28 双向最终关闭**：exact source `c4faf14460238c7ea3e85983f31dee8be1b79afa` 依次达到 `candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`；build identity `4E5EEE4AB5BE0CC8D084254C54F23AC4D6269C11CFED987409EA6BBE171CE191`、
payload closure `7460D8D4FC4416EDBDDFE7577403CBA7233ECC347BDF2D605BC5D2252AF39507`；证据见 [双向导航关闭证据](evidence/character-build-skills-bidirectional-navigation-closure-2026-07-28.md)。

**原 L62：角色构筑 focused 历史 Output Panel 收据**：2026-07-26 fresh Output Panel 副本 529/529（SaveManager 162、EquipmentInventory 28、InventoryPanelService 138、transaction spike 19、CharacterBuildService 163、PlayerInfoProvider 19），Compiler 0/0；
证据副本 `tmp/flash-character-build-final-20260726-1910/compile_output.txt` SHA-256 `9E8699823508B323444D0730C4C2619ABD9EA709189A61A275B0B18E90DB6D7A`（这不是 trace，不得外推后续源码）。2026-07-28 补充 533/533 + asLoader 1,061,358 bytes / SHA-256 `3FA6C69D8C762EB6198C31C3DAD92843E8E3EB7C1EA4C3EC51F8FE08D275F321`。
2026-07-29 C1 分类计数 fresh（未 publish）：runId `7c6da8cc494747ad979b899eaeb87b85`，539/539，Launcher 全量 1646/1646，focused `CharacterBuildTaskTests` 172/172；只证明同源码树 TestLoader 与 Host/Web 自动行为。

**原 L63：2026-07-29 C2 候选 rich tooltip fresh（未构建 candidate）**：C2 Node leaf 6/6，Character session 22/22、projection 4/4、facet 16/16、slot transition 18/18；Host focused xUnit 226/226、Release build 0 error；standalone 215/215，production workbench 256/256×3 = 768/768 + hidden-body 4/4，dressup 211/211；strict UI audit 0/0。
未修改 `.as` 或 SWF，未运行 CS6、未 publish。

**原 L64：2026-07-29 C3 候选直接调制 fresh（未构建 candidate）**：candidate leaf 11/11、facet 16/16、tuning capability 28/28、projection 4/4、tooltip 6/6、Inventory workbench modules 26/26；standalone 215/215，production workbench 262/262×3 = 786/786 + hidden-body 5/5；Equipment Tuning 三视口 96/96；
default/release-tree `--strict-warnings` UI audit 均 0/0。

**原 L67：2026-07-29 B2 独立装备调制 opener fresh**：runId `dc1909f0ff9d43e19c099c4bf9f7a413`，EquipmentTuningServiceTest 55/55、InventoryPanelServiceTest 144/144、Compiler 0/0、32K retry 0；`scripts/flashlog.txt` SHA-256 `1FBBB8478F869665DD0F235F9EA60887BAFCC5C8F573E8CD107FE38FA0431287`；`scripts/TestLoader.swf` 455,078 bytes、
3,656 functions、最大 19,072B；asLoader 1,064,484 bytes、SHA-256 `57C99E3AB1F511EBA16E3139B9CE42F2C382638E45BD2C185A270E7D44972E24`、9,719 functions、最大 46,025B。原文强调：此前 `142/142` 等段落均是带日期的历史证据，不得改写成当前 runner 合同。

**原 L9：手雷/药剂堆叠 fresh（2026-08-17）**：Host `CharacterBuildTaskTests` 227/227，Launcher 全量 3760+3/3763；Web session 36/36、projection 8/8、slot transition 18/18、candidate tooltip 6/6、facet 16/16、candidate tuning 11/11、tuning capability 28/28、standalone 218/218、production controller 1059/1059 + 12/12 + 18/18；
Flash runId `5eae3cb6c63b4efdb92a0f85d3d7ee5d` 六套 569/569（CharacterBuildService 194/194）。当时未构建 candidate、未 promotion、未做正式入口游戏 E2E。

**原 L10：强化度交换 fresh（2026-08-17）**：model 80/80、tuning capability 34/34、slot transition 18/18、candidate tuning 11/11、strict UI audit 0/0、tuning browser 137/137×3、Character Build production controller 1095/1095 + 12/12 + 18/18、Host `EquipmentTuningTaskTests` 132/132；
Flash runId `f2233cbd501c435cbedd4637d90c400e` 为 Equipment 72/72 + Inventory 147/147；asLoader 1,087,271 bytes / SHA-256 `D6E9EB9D41A19B336FD63F052377ABF8233C95A3593462805BA95D770542C0A2`；自动函数体门读取 9,881 个函数，最大 46,025B。

**原 L11：设置 Web Panel 开发完成门（2026-08-21，历史状态）**：第四轮 C#/Web 体验闭包 Settings Node 16/16、Edge 1024×576 与 1600×900 各 49/49（合计 98/98）、Settings/preview focused C# 21/21、Launcher 3920+3/3923、KShop 152/152、Workbench audit 0/0、CSS bundle pass、panel contract 5 domains / 31 commands + 66/66 mutation；
Settings AS2 run `48bc616624e546a2ba3de33f66ce0d21` 为 36/36，player-manual-input run `86adb7d4ce8140ac944bdab3797f7958` 为 474/474 + 50/50 + 19/19；当时 `scripts/asLoader.swf` 为 1,103,301 bytes、SHA-256 `69401CF72120F29043C542685626217412AB4AE382A5439B3BD9452760D18EF1D78`、10,023 functions、最大 46,004B。
当时状态 `DEVELOPMENT_COMPLETE / HUMAN_ACCEPTANCE_REQUIRED / NOT_COMMITTED / NOT_DEPLOYED`，禁止 commit、正式 deployment build 或 push（该列车此后已另行发布，状态以 runtime 文档为准）。

**原 L24：tooltip/布局交互增量历史计数**：2026-08-10 fresh：Character session 35/35、candidate tooltip 6/6、projection 6/6、Inventory modules 31/31、standalone 218/218×3、生产三视口 1047/1047 + 12/12 + 18/18、dressup 224/224、item-grid 20/20、CSS bundle 通过、strict UI audit 0/0、ratchet 66/66。2026-08-06 current-tree：session 32/32、tooltip 6/6、
projection 5/5、modules 31/31、standalone 218/218、生产 963/963 + 12/12 + 18/18；Host focused 202/202、Launcher 3279+3/3282；fresh Character AS2 runId `0334705c32a24d698df191aec1aad29a` 561/561（CharacterBuildService 186/186）；asLoader 1,054,034 bytes、SHA-256 `317641F843D15BD600AA554D586C041B7B4D30BC65106CE1EECAA485EED6FB43`、
9,644 functions、最大 46,025B，未编 main；首次目标切换未刷新 SWF 且按失败保留，随后单次重试才形成成功 publish。当时非严格 audit 为 0 error / 4 WB112 warnings（后被取代，见下「工作台审计口径」）。isolated candidate 只读 smoke 后仍为 `NOT_DEPLOYED`。

**原 L26：2026-07-29 B6 fresh**：Host focused 257/257、全量 1715/1715；inventory modules 26/26、Character standalone 215/215、production workbench 786/786 + hidden-body 5/5、Panel runtime 27/27、Panel contracts 4 domains / 23 commands。B5 历史 fresh Flash run `bec9c608004d48e0bcb18a7f1c0f5708`：EquipmentInventory 28/28、NPC 46/46、
Inventory 144/144、Crafting 36/36，Compiler 0/0、32K retry 0；B6 未修改 AS2/Flash，故未运行 CS6、未刷新 TestLoader、未 publish asLoader；未构建 candidate。

### Agent Runtime / Wings 列车

**原 L18：F8 current formal（2026-07-31）**：本轮 fresh：SDK resolver 7/7；Launcher 2724 passed + 3 explicit opt-in skipped / 2727 total，0 fail；Node 37/37；TrustedRunner 57/57；production policy 26/26；Runtime Lane C 11/11、scalar 572。
implementation source `53caabc90941826ddacf626f536b0f473adbf049` 的 exact isolated candidate 先绑定 identity `0F4C92F237ABD7785C957F3CD135ABF2EFB1EB5D9AB5671B869F39D00970675C` / closure `54FBCCBA7C90ACF407B09E38FFB874C13DE3CDFB80CF62D0F8D4E239A42962F0` 达到 `e2e_verified / NOT_DEPLOYED`；
随后 release source `6f3d50a52413c747b05b74be88d6ee46650f4597` 由 tag `runtime-build-v2/20260731-agent-runtime-wings-f8-v1`、request `A9B33601805709DBB5EAE6DAF312C2B7B0B502096FDD3BDCEA9CBE26D8B1299C`、本地 X509 + GitHub run `30602046108` 双故障域共识完成 v2 promotion。
正式入口证据为 `tmp/manual-agent-acceptance/formal-f8/agent-runtime-help-20260731T040942Z.json`、同目录 transcript/completion 与 `formal-residue-comparison.json`。当时通过口径：单屏 Help-panel 窄纵切 `standard_entry_verified`；不外推物理双屏、「13/13」、Flash pixels/input、Hair/Wings 完整产品、业务写或维护者目视签收。
完整证据契约见 [CF7 Agent Runtime 一期范围冻结 ADR](CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md)；现役断言见 details [专项资格](../agentsDoc/testing-details.md#specialized)。

**原 L21：F7 immutable C1（历史）**：source `dd84230a1d262c6478591cae2d11051b7a8aa7b1` fresh evidence：Launcher 2678+3/2681、SDK resolver 7/7（精确解析 `.NET SDK 10.0.300`）、Node client 37/37、`FullyQualifiedName~AgentRuntime.TrustedRunner` 48/48。
exact C1 tree `7362881e96d8ed0f9c20ccae580426c522f14946` 的 production policy 26/26 达到 `candidate_built / NOT_DEPLOYED`：identity `F67F1054E7DD19600138C3196D0798CFA487701CB7143C4DDFD2DC426D26E372`、closure `3C2CA3E6E935BF23A061228ED3D9BDA3823E81186057E8C86118FAD5C7CEBF0D`、
Core EXE SHA-256 `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD`、receipt SHA-256 `CC7ED850D18D2C72947DA69E74C28E529A6DC988CA37AAE4D486C43954FAB79B`。当时无前台会话的严格入口返回 `trusted_runner_credential_timeout` 且无 completion evidence/进程/端口/live credential 残留，故不晋级 `candidate_executed` 或 E2E。

### A2 / A3 收口与身份三连的历史基线

**原 L60：2026-08-02 A2 Inventory fault/proof 收口基线（取代此前 A2 中间计数）**：唯一聚合入口 `powershell -ExecutionPolicy Bypass -File tools/run-inventory-fault-gate.ps1`；独立从零运行 174.5s、exit 0、末行 `PG-INVENTORY-FAULT PASS`。子门：Panel runtime 36/36，panel contracts validator 4 domains / 23 commands / 3 numericFields / 3 vectors /
7 sourceChecks / 0 errors、selftests 63/63，Inventory runtime 60/60、modules 31/31、lazy 12/12，Loot 47/47 + 79/79 + 6/6，Tuning 120/120×3，Skills 150/150×3，Character 867/867 + 12/12 + 18/18，Crafting (120/120 + 15/15 + 8/8)×3，KShop 138/138，NPC 109/109 + 2/2，Hairdresser 39/39×3，Host focused 781/781；异质子门不相加为伪总数。
独立 frozen Release DLL 全量 Launcher 2998+3/3001。fresh TestLoader runId `a24cf4b1635f4824923078945612eb0a`：28/28 + 46/46 + 144/144 + 36/36，Compiler 0/0、32K retry 0；`TestLoader.swf` 465,687 bytes / 3,709 functions / max 19,072B，未编 main。
可见 smoke 绑定 isolated candidate `c-acb7d341bf25-08846e81b3-20260802t112923788z-0de05d30` / identity `ACB7D341BF2524AD9FA4B2FBBBF48DC3B48020FEE799899C70FAA0FD7DA4C090` / closure `DE073A8934696B62DF95741779EA2B99AE27F5E1C294C74687AAA53D4711EFA3` / Core `639944974F1A6F9A521540DF4F7907FEBEB22F9FF3ECF28BC7AE0485D3BFF09D`，
只证明真实 WebView2 可见/同步、tooltip 命中、Esc 普通关闭、fresh tuple rebind 与 supported shutdown 零残留。Agent Runtime 无该 surface 的 panel.open/Flash pixels/input，故按授权回退 Codex computer-use；安全门拒绝对子进程坐标点击，所以不签 source selection/业务写。

**原 L60：2026-08-02 A2 authority/data live 补证**：同一 isolated candidate 完成一条正常生产 Inventory 写：exact workbench owner 的 Web `autoTransfer` 经 Host/`InventoryTask` 映射为 AS2 callId `3`，把 clone 的 `背包/0 手枪通用弹药×87` 移到 `战备箱/9`；安全存档后不重新播种，以同一候选新进程从既有 SOL 加载并取得 fresh Inventory snapshots，
最终 JSON SHA-256 `2D0CD5B49EDD25C4AD7D8FD771473A2C61E625FFA4FBAE69A8C511451FD5B9CE` 精确读回 source absent/destination occupied。独立终局审阅 `GO / 0 Blocker / 0 High / 0 Medium / 0 Low`，严格状态 `e2e_verified / NOT_DEPLOYED`。动作由生产 DOM synthetic Ctrl+click 触发且 `isTrusted=false`；只签 authority/data、Archive 与未重播种重启读回，不签 physical hit-test、
trusted pointer/keyboard、A4/A5、promotion 或标准入口。

**原 L55：2026-08-03 A3 终局审计与 canonical 串行基线**：默认并行下红项在 Revocation、Equipment Router、WindowCapture、Gateway 与 GameLaunch 间漂移的历史证据保留；相关精确/整类复跑通过只用于归因。fresh canonical 连续两轮均为 3149 passed + 3 explicit opt-in skipped / 3152 total、0 fail，marker 各恰好一次、stderr 均为 0 bytes；这只闭合 Launcher 自动门。

**原 L55：2026-08-05 A3 Crafting v8 作者侧历史基线（曾取代 v7，后因共享字节变化再次 Superseded / Reopened）**：`node tools/workbench-live-e2e/crafting/bootstrap.js --check` fresh 265/265（20 positive + 245 negative）、`ADMITTED`，manifest `e18d7cd08fc62ae96c4e68866634d9f79afac11e85c46108adc33f504e88d911`、
journal `56c56ad13a33927befb302dd0fad1c16ba336e06a3f2bbbf42d288ff88e6d84e`；AS2 结构锚 384/384，Inventory Web 70/70、Crafting Web 20/20，Host focused 286/286，三视口生产 harness 各 baseline 120/120 + current 15/15 + owner 8/8 + identity 10/10。当时记录 `AUTHOR OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`，没有 fresh CS6 trace，
也未取得不同作者终局审阅。

**原 L55：2026-08-05 A3 shared page-preservation current 作者侧基线**：共享 `InventoryRuntime` 定向回归 71/71；KShop canonical 241/241、`ADMITTED`、journal `79ba38f9aef20bc2b2bbb9605b34eb0a5936ce6e4a66e6c42d494fdb266aa5c3`，browser 146/146、presenters 30/30、workbench modules 31/31、Panel runtime 36/36、Host Shop/Inventory focused 399/399。
共享生产字节变化使 Equipment/NPC/Crafting/KShop 的 prior closure 全部 `Superseded / Reopened`；四面必须在同一当前树重跑并重新终审。仅为 `AUTHOR OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`，不关闭 A3、不授权 candidate/live 或 A4。

**原 L46：2026-08-03 current automated baseline（现为 Superseded / Reopened）**：fresh `-CompileAs2` 末行 `PG-IDENTITY-TRIPLE PASS (AS2 fresh behavior + Host + Web)`、Compiler 0/0、32K retry 0，并连续两轮完成 canonical serial Launcher full：各 3149 pass + 3 explicit opt-in skip / 3152 total、0 fail、
运行时 `parallel test collections = off` marker 各恰好一次。不得据此声明 A3 Closed、A4 准入、E2E 或部署；A3 现役关闭条件见 details [Item identity triple 聚合门](../agentsDoc/testing-details.md#cross-layer)。

### 工作台审计口径沿革

**原 L103：2026-08-06 双栏工作台按职责拆分后**：default 与 `--release-tree` 两条 `node tools/audit-workbench-ui.js --strict-warnings` 均为 `0 error / 0 warning`，`node tools/test-workbench-ui-ratchet.js` 为 `66/66`；这取代上方 Character tooltip 行内「`4 WB112 warnings`、strict 未通过」的旧 current-tree 数量结论，旧文字仍是失败列车历史。当时定向回归：session 35/35、projection 6/6、
candidate tooltip 6/6、facet 16/16、candidate tuning 11/11、tuning capability 28/28、slot transition 18/18、Inventory modules 31/31、lazy closure 24/24、canonical presentation 6/6、Panel contract mutation 66/66；browser：Character standalone 218/218、production controller 1002/1002 + 12/12 + 18/18、Dressup 222/222、
Equipment Tuning 135/135×3。该证据只证明当时源码树的 Web/协议/结构闭环。

### Boot / 材料 catalog loader 历史基线

**原 L61**：2026-08-11 fresh runId `631b5a64fa7c41e682431ab6956818f2` 取得 86/86 + 12/12、Compiler 0/0、32K retry 0；`scripts/flashlog.txt` SHA-256 `FB1E36D19F36611BDC33E3029FDCC48D657274E1FF97661A32776D5EF7ABBD6A`；旧的 36/47/58 计数为更早历史基线（当前钉值 91/91 + 12/12，见 details [Boot suite](../agentsDoc/testing-details.md#suite-boot)）。
`material_catalog.xml` 2026-08-11 fresh runId `fb4a32924fc6436fa21376a969b41d73` 的 DirectPurpose 1 / order 0 只作历史；2026-08-15 合并树由生产 loader 实际 `reload()` 取得 catalog 224、legacy 58、DirectPurpose 2、`authoredDirectPurposeId` refs 27、Compiler 0/0。

### Audio Platform v2 历史

**原 L75/L87：通用发布前置的取代关系**：旧口径「H2 前严禁 promotion/deployment」及通用 promotion 依赖 Audio H1/H2/E3 的说法，已被现役「Audio 通用发布解耦门」（原 L87）取代——通用 promotion 不承载 Audio H1/H2/E3/截图/听感证据；真正影响 DLL 的音频源码/配方/toolchain 仍进闭包。现役口径正文见 details [正式 runtime 发布](../agentsDoc/testing-details.md#runtime)；专项资格义务（A1–A6、sleep_resume ticks 等）
见 [专项资格](../agentsDoc/testing-details.md#specialized)。2026-08-15 current formal runtime 经 owner-emergency 明示 bypass E1/H2/E3 后发布；它未满足或伪造 H2，不能反向补签 A6/E2/E3。

**原 L76：S10/S11 历史诊断（NOT_DEPLOYED）**：S10 frozen source 是 commit `82d2fe1d92aab9fb86677f37a3c3ebe2211fb4ff` / tree `0aa6ad2b0b1a564bb31f8b63e497633f21b7f398`；双 clean repro 与 isolated candidate 本身 GO，绑定 build identity `E28139CDC0AB7CCB34B0B19D9CDD88E3B85D65EB265010A4302578CCC849E671`、
payload closure `FE874BA9CAC43B4ED944A1B5606DFDD03176C02A89F510338CEC251B2C768793`、runtime manifest `4089` B / SHA-256 `A59BE52C567DA5C20A12F069F02CB7D0EB1BFF96AC369D91E5142C2208CECA10`。但 A6 run `b0672e56197642c5b89860d61ae59a03` 在 case 13 被 frozen observer 误判：production/player 实际以两个 bounded episode 完成 TWS→Realtek→
TWS 并回原 pre digest，旧证据实现却要求每 episode endpoint digest 不变。故该 run diagnostic invalidated，case 14、E1、H2 均不存在，全部 capture 不得复用；连同此前九次，共十个不可复用 runId/capture。S11 已完成 fresh unattended non-device Source matrix：observer 26/26、runner 29/29、materializer 8/8、operator 12/12、assembler 5/5、updater 5/5、contract 673/673、
Launcher 3547 passed + 3 opt-in skipped / 3550、audio-focused 240/240、native ABI 57 及 native support/backend 编译运行门、MF 78/78、AS2 `-SkipCompile` static 185/185、Jukebox Edge 30/30、shipped 12/12、发布控制面 108/108 + 65/65 + 109/109 + 16/16 + 13/13 + 48/48；qualification dependency 是 568 entries /
closure `F1DAB211BDFCB77B344FC05DF86B7E977C97E92FBD8E1DF75CA73155343F7A15` / manifest 142054 B / SHA-256 `E8E286E6455B61F1E2F5CFC8A2AC3F2B1C6F6BF2AA4099413F6BE7EE6BCE2272`。真实 endpoint enumeration 与 runtime playback contract 当时刻意未跑，所以 physical Source、candidate 与全新完整 A6 都未闭合；R3 frozen manifest/validator bytes 未改且无需新 H1。

**原 L86：R7 content-sniff 当时口径**：runner 35/35、全 795 tracked mismatch=0、dependency manifest 568 项、closure `658DC91B344B7630D35D7F9DD362C23573B9C0EE5F7CFB0DECA0A9E3EC1B22A1`；P7 frozen validator 的 exact-chain 已知宽松不得作为 H2/E1 oracle。

### 军阀 / 斗兽历史

**原 L15/L95：Slice 6.1 r10→r11 沿革**：r10 真人确认动作战斗可进入，但玩家不可操作、装备未加载并呈现裸体女性回退；同一存档在正常游戏无异常，故故障收敛到战棋适配层（玩家 loader 后过早把 `_root.控制目标` 改成镜头，令延迟初始化永久按 AI 分流且跳过纸娃娃装备）。r11 现役合同见 details [军阀 suite](../agentsDoc/testing-details.md#suite-warlord)。r11 当时 fresh：ActionEncounterRunner 63/63（3 cases，当前钉值 97/97 + 4/4）、
asLoader 1,244,629 bytes / SHA-256 `A98C7645EA0C2E65811E51DDD2C93A6C69B59A63433D4FED15357285195E6FC5`、Web 194/194 + Edge/CDP PASS、Host Warlord 88/88、Launcher 4583+3/4586。候选 `warlord-s6-capture-r11` 状态 `candidate_executed / HUMAN_ACCEPTANCE_PENDING / NOT_DEPLOYED`，
identity `29606003E974A75ECA28000A288FD0FC0D1D7AF32163E5A7156D022DF8C93C47`、closure `5C2D37472D8B15C3BAF0DBFBADBCAFE52CB5ABF5FC525A1F03CD95E891868752`；正式 runtime 未变。r8–r14 数量和候选指令保留于 [基础闭环施工交接](军阀-基础闭环施工交接-2026-09-05.md)。

**原 L94：军阀 Slice 2/3 距离纵切前基线**：Node 24.19.0 下 runtime 104 + vendor 4、closure 107 / 1,790,619 bytes、Node 122/122、Edge 20/20；另跑 Warlord QA 3/3、minigame final-state、Launcher 4531+3/4534 与文档治理。覆盖动态 Map/Scenario、24 节点、Organization digest、2～4 人编组/全部 22 种真子集拆分、守恒、AI 不切组、免费重组不扰动 RNG、Replay 摘要，以及父 token/五阵型/拆分零 AP 流程。
Demo 1 divisor=1 保持 Host v1；N 阵营、预算与 AS2 DeploymentPlan 未完成。`warlord-slice3-0901` 仅 candidate_built / integrity-only 33 files / NOT_DEPLOYED；native 与 Web manifest `816CD27C…F212F` 分绑。Slice 2/3 无 `.as` 改动。

**原 L108：2026-09-02 斗兽标定生产目录与正式发布收尾**：`gate-f-week-full-v9` closeout 固定 195 个 completed shard / 3,230 条 selected durable row / 3,170 条数值样本；36 个 candidate 达到机器完成门，33 个兼容默认 `650 / line / line / 54` 生产 profile 并去重为 55 个 exact roster；`G2` 两组以真人 PVE 固定为 `Lv10 / arena-2`；`B11/C11/C7` context-only，
21 个 timeout candidate provisional，`D10/B12` quarantine。合并后 exact bundle `sha256:6ed3c7461330657f4770abc454b9c6ccdf280c5c2190f347d798c19fa5f21b43` 获批，在 revision `06e554e762d3bae83ccd20c264c78e7fa74ec92c` / closure `sha256:d876f02c1e52eba7d8b89bb0d41c9fec2e1992449c0bcaa305f3d0ebaa6026e7` 上取得 `APPLIED_VERIFIED`；
目标 SHA-256 `sha256:f9bfb2d2496da9648b5bbe4227c3fb0e5828c3456b16b9115a76456eb98d41e5`、catalog hash `sha256:c667bbb1d7da4263ffb93cc916a251774af8e1cc41df1bbc667a9611f7035eb4`、receipt hash `sha256:8f6b152a3289c72e3d20bd8cb723f3d7dcec37a85a747e159280fe4ea6d56a68`，Host 7/7、Arena browser 36/36。
正式发布绑定 source `8b71d81f3777157d924f7023c55219c75d695238`、tag `runtime-build-v2/20260902-arena-calibration-production-v1`、tree `0b2172f023c7e192d003e47d432a278063870b59`、request `45C86C4FA3AB947C4CE0E9249F8BC5A5BE52AA4CE81F3BE5BECF3FA05732108B`、
identity `491CF53B1D6447335D7798EBE4018C575B4BFC25277FCD5FA0138A550370007B` 与 closure `73040C84F9ACCAAA6E1A9DF5D89F87AC3E30D3ABEE0DE85031D8BE69C4E2260D`；本地 X509 `physical-host-b` 与 GitHub OIDC `github-hosted-windows`（run `33578482626`）对同一 33-file payload 达成共识，
39/39 final receipt SHA-256 `E21067C501DCD21C410F89809F2A9028C6EC71D0F262009619265BF99DD76DB7`；deployment `59212346e3b43d75924babcde4d1ee1cfaa9c860`、audit run `33579694615`。部署后尚未重跑 Arena 正式入口业务旅程或新一轮真人 PVE，不称业务 `standard_entry_verified`。

### SaveManager / 存档 / 测试反馈列车

**原 L108：2026-09-04 R1 步骤 6→9 调用点迁移 fresh 证据**：character-build SaveManager 334/334 + 其余六套零失败、map-loot 648/648、K 店 37/37、PAT 117/117、settings 47/47、建角 40/40、NPC 66/66，均 Compiler 0/0、32K retry 0；check-callsites 数量断言与 `--verify-swf-hashes` 全过；asLoader publish-only 1,236,813 bytes /
SHA-256 `B63C7FFB54B44E395ED316B484124166A1FF9D91D47EF462408D4F17925CA70F` / 10,953 functions / 最大 55,767B，single-ownership 主 0 / loader 625 / 交集 0。当时声明：只证明 focused TestLoader、静态门与 publish-only 产物；步骤 10（A2 Reward）、11（B1 SceneChanged）、12/13（XFL）另轮施工——这些步骤此后已完成（见下）。

**原 L108：2026-09-04 R1 Slice 1–4（四层语义分层）**：fresh character-build runId `09fc7d3f32fc4a2387a188dae57afd1e`：SaveManager 334/334（取代上段 231/231）+ Equipment 28/28 + Inventory 170/170 + transaction 19/19 + RuntimeProjection 17/17 + CharacterBuild 211/211 + PlayerInfo 27/27，合计 806/806；map-loot 同轮 648/648；
asLoader 1,236,590 bytes / SHA-256 `83DDEBDE7225207C64BF67131EFB26B8374030C89820C2EE08819924458C325F` / 10,953 functions / 最大 55,767B；当时 D1/D2 及后续调用点迁移属 Slice 2+ 另轮施工。

**原 L108：2026-09-05 R1 步骤 10–14**：新门 `node tools/save-api-migration/test-callsites.js`（当时 17/17）与 `check-callsites.js`（当时 38 物理 / 32 逻辑，scripts/XFL 旧入口归零；当前 manifest 机器真值为 38 物理 / strict 18 + debounce 14 逻辑，旧「36 物理 / 17 strict + 15 debounce」「37 / 32」口径作废）。R1 基础 Map loot 676/676（补 N=50）、
character-build 824/824（SaveManager 352/352，真实 wrapper→SOL N+1 与 SceneChanged clean/pending）、PAT 117/117 且 direct-authority 23。9 月 5 日大规模开包反馈增量：map-loot 684/684（267+12+405，含冻结 RNG 后合并、装备不合并、数量/容量与分段重启），Loot state 80/80、生产 Edge 104/104、lazy cancel 6/6；复现命令为 run-map-loot-tests.ps1、
loot/dev/test-loot-state.js 与 loot/dev/run-harness.js。编译可达与现场旅程不能混称，完整状态见 [R1 收尾记录](R1存盘API迁移收尾-2026-09-05.md)。

**原 L108：2026-08-30 测试反馈修复专项门**：当时 runId `db4724af9f5c4e35b9f7f87054ba70d2` 为 Loot 165/165 + Planner 9/9 + StageRunSession 372/372 = 546/546；存档/药剂 current fresh 为 SaveManager 231/231 + CharacterBuild 211/211（runId `66b0b0cf3cf8451b9f7d5cd6506e40b0`）与 PlayerAsset 113/113（runId `96774078d4884214ab1be55c447284a4`）；
Loot Web 58/58、KShop Edge 155/155、Panel contract 68/68、Loot/Equipment/PanelFocus focused xUnit 317/317（其中 focus 61/61），Launcher 全量 4449+3/4452；fresh asLoader 1,200,109 bytes / SHA-256 `6638A70485BBC79D950458D11F69FE738DC7D41604945F66A729DAA90B780107` / 10,683 functions / 最大 50,215B。
早期隔离 candidate identity `4B3DFEC54046494CFCC627212586D72F447D7E6E67FCDA9276569D3032A4FEB9`、closure `9CBEE0CDEA19B3B28BDDE9DB0B53489E816207A56175E06241DE93E683B855F2` 已被 B1/B2 修复 supersede，只保留为历史 `candidate_built / NOT_DEPLOYED`。最终 release source `5789d597fbb7af32753fe4a35887b1f2a3a34e10`、
tag `runtime-build-v2/20260830-tester-feedback-stability-v2`、request `90E4BFB9875C73EE6672E89F404763C68E2BF33184AD2ED68421D5C975ECEED6`、identity `9B146D22C82925853757DCA8D63CDDBECD31CD19C43EC1771F6B26D8F5824CEE`、closure `C8B22C4532AD259E4C514BED30C87DC016E2FE17F9C001158F4CF18F900E1C94`、39/39 policy、
deployment `3e23bda255dae09e20e309a12c5b21d86b28f347`、audit run `33289302965`。直播+QQ 抢焦、战斗空调制关闭、通关后立刻前往交付、领取后重启继续、槽4血瓶三来源回原槽仍为 `FIELD_REVALIDATION_PENDING`（该口径仍有效，见 details [持久写与恢复](../agentsDoc/testing-details.md#save)）。

**原 L108：2026-08-30 角色构筑纸娃娃稳定与调制源提示增量（当时未部署）**：fresh Web 证据为 tuning capability 34/34、Inventory modules 37/37、Character standalone 222/222、production controller 374/374×3 = 1122/1122 + hidden-body 12/12 + preparation 18/18、Dressup 224/224、Equipment Tuning 147/147×3、UI ratchet 67/67、
default/release-tree strict audit 均 0/0、item-grid 20/20、visual atlas 66/66 / 0 warning；Tooltip fresh TestLoader 为 3677 records / 0 compose failure / 105/105 mod definitions；解析后布局审计 88,248/88,248 item instances + 396/396 skills、0 viewport/pointer/profile failure，交互门 static 19/19 + browser 15/15。

### Reward / A5 材料商店历史

**原 L104：A5 存档闭包数量沿革**：现役口径（迁移时）为 277/277，取代旧 251/251、266/266 与 274/274 数量（含 archive/restart 字节等值）；该 277/277 为文本阈值，未找到当前机器真源（details [持久写与恢复](../agentsDoc/testing-details.md#save) 保留义务并标待核）。v2 历史收据仍按原 schema 验证。

**原 L104/L105：A5 h3 机器 acceptance（历史，已被后续真人失败 supersede）**：2026-08-14 exact run `a5-0814-h3` 曾以 24-step/16-key intent、两段 trusted session、fresh restart、三视口 static gate 与独立 16 PNG / 14 claim review 达到当时的 `e2e_verified / NOT_DEPLOYED`；acceptance/replay SHA `DB130A3E90E52232985A16ADB1E115669DD003C9FAE1158CFDC4A9CF51629E5`。
其后真人操作暴露两个自动 evidence 未覆盖的产品终态：配方页无法一跳返回原材料，以及关闭合成后游戏 UI 不可交互；因此 h3 acceptance 只作历史机器证据，当时状态改为 `A5_REOPENED / NOT_DEPLOYED / RELEASE_HOLD`。随后 UI 将动作改为「前往合成」，配方卡收敛为产物、静态材料格带与右侧动作同卡，并补上一跳返回与 InputShield telemetry mask 收尾。2026-08-15 维护者发布授权解除了这个历史 HOLD，但没有恢复 h3 acceptance，也没有签署 material formal journey。

**原 L107：2026-08-15 材料历史 closure（只约束该冻结列车）**：基建分档固定为「自行车及以上解锁前往商店、摩托车及以上解锁前往合成」，越野车兼容两者；`infrastructureUses[]` 只显示已发现项目并按 `Level[]` 物理顺序投影需求、缺口与完成/当前/后续状态，总持有量只在详情标题显示一次，仍无「前往基建」按钮、新导航协议或 XML `Level.id` 信任。合并树 fresh Flash：material loader 224/58/2/27、Boot 86/86 + 12/12、Equipment 28/28、NPC 48/48、Inventory 147/147、
Crafting 133/133、Synthesis 13/13、Audio 185/185，全部 Compiler 0/0；publish-only asLoader 1,082,305 bytes / SHA-256 `B9EFB7B4AE615E548868BD8D3CE7C9B9AA13009688B6BF2DE4C75BCD94C68F2A`。Web：Crafting runtime 32/32，基建/配方/商店三视口各 9/9、26/26、12/12；Host material-focused 119/119，Launcher 全量 3723+3。
source `b298138fbac1b17ceaab2540729735f2d64d81d1` / tree `87cf3bb16250f02c9a2b396c1184a75064089e80` 由 tag `runtime-build-v2/20260815-material-archive-v1`、request `8D87E3CE74FEBB33F739F486BB18AEC3C4DB81E92416D61B991402E8AB69AEFD`、双 signer/双 faultDomain、strict v2 verifier 与原子 promotion/rollback 当时部署；
identity `6437070BD78C64713FCBC1CDC681EAC581636BDA07372DDE78299B798515A113`、closure `B61AE1F3A3F3B7A3041D7ED7798471A8B9F363224B3CC213EADE7C72EBA9F6FE`、deployment commit `539fa306181da40d092c03508afdbddef18eff8d`、cloud build `31854335888`、audit `31855597166`。owner non-H2 明示 bypass Audio E1/H2/E3，Audio H2 仍未满足；
generic no-candidate formal smoke 在 reveal stable 后可信 shutdown，`exit 0` 且 slot/SOL 不变，immediate EOF before reveal 的 pre-reveal exit 竞态保留为已知边界。当时状态 `SOURCE_FIX_ACCEPTED_FOR_RELEASE / RELEASE_AUTHORIZED / RUNTIME_DLL_PROMOTED / MATERIAL_FORMAL_JOURNEY_OPEN / PG-MAT-RELEASE-01_OPEN`；该部署不恢复 h3 acceptance，
generic smoke 不能代签材料 24-step journey 或构成材料专项 `standard_entry_verified`。

**原 L107：Reward H-A 首次失败证据（2026-09-03）**：首次 H-A 的 AS2 存档已正确形成 4 项 applied / 7 项 `target_full` remaining，但旧 Web 因 retained slot lease 权威轮换误判无进展、没有显示「整理背包」，故该次为失败证据；修复门与现役 H-A 合同见 details [奖励、礼包与统一暂存](../agentsDoc/testing-details.md#suite-reward)。

**原 L114：Reward/O1 当时收据与人验结论**：Reward/O1 current 当时为 AS2 596/596（Loot 205/205、planner 9/9、StageRunSession 382/382）、Compiler 0/0、Loot state 69/69、生产 Edge harness 102/102、lazy cancel 6/6、blackmarket 25/25、panel contracts 68/68、Launcher 4541+3/4544。2026-08-29 增量已通过自动门、原功能真人矩阵及布局修正版复验；与正式 Core 逐字节相同的隔离候选已进入正式 runtime，
当时 `HUMAN_ACCEPTANCE_PASSED / promoted`，部署后仅执行根 bootstrap `--verify-only` 与 post-promotion Audit，未重跑选关、死亡复活或返回基地业务。既有 A3 exact Core 历史状态 `HUMAN_ACCEPTANCE_PASSED / promoted`；部署后无 candidate 入口只确认 formal identity/closure、bus ready、正常关闭与零新增残留，未选存档且没有 fresh reveal，详见 [关卡结果与基地结算 ADR](关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md)。
Reward 首次 H-A 因 partial 后缺少 organizer CTA 失败；修复后的全新 exact candidate 完成 4 applied / 7 remaining、正确 CTA、正常关闭与同槽重启 exact 7、角色构筑「待领取 7」主动重开、整理后 7/7 全部领取，维护者确认安全且无卡住。同候选正确启用 O1 后取得 13 个同实例连续观测，第 2–13 个 exact tuple 均持续推进且 `business_outstanding=0`，合法结论为 `no_outstanding_operation`；维护者玩两轮未卡住，H-S 通过但不声称故障 owner；
H-A/H-S 均为 `HUMAN_ACCEPTANCE_PASSED`。独立第二列车：source `0b71d91987bee27f399bedc90a2c648a8bcbf44e`、tag `runtime-build-v2/20260903-reward-root-o1-v1`、request `A0DA1D0F5E3E91EF9A53BC8D81419E5917016B860EB49AC655DA4D83EDAF7367`，本地 X509 `physical-host-c` 与 GitHub OIDC `github-hosted-windows`（run `33701115609`）
对 identity `1E09139852A981BBDA4A99E65F4FCF5BDBDD71E44DDE39EE13FC5B71ABF29709` / closure `81DE32947F126EEC968280C4771C427140A82268CA042F91BE945F60A441F76B` 达成双故障域共识并原子 promotion；deployment `95ea7e8f7c862ea28f6b8c7c906173a701d71336`，首次 Audit run `33702253144` 输出 `state=promoted`、`deploymentChanged=true`。
当时为 `HUMAN_ACCEPTANCE_PASSED / promoted / FORMAL_BUSINESS_REVALIDATION_PENDING`；人工候选不充当 builder vote，部署后也不自动获得 A/S 专项 `standard_entry_verified`。

**原 L114：StageRunSession 计数沿革**：2026-09-08 基线 `63d2f13deb` 加工作树时为 496 项；此前 372（2026-08-30）、382（Reward/O1）、419（2026-08-29 前后）、519（2026-09-09 选关）、527（2026-09-10 问题 4/5）；当前机器钉值 594（`scripts/run-map-loot-tests.ps1`），见 details [Loot / 关卡结算 runner](../agentsDoc/testing-details.md#suite-loot)。

### 头像 campaign 历史

**原 L112：P4 两阶段/方向/扩容的过程回执（历史）**：r103 冻结 7 pass / 4 adjustment / 1 wrong_pose 后，下一 identity shard 由维护者明确从 12 翻倍到 24。r113 以诺亚虔信者 `平a frame 22` 实证换帧恢复链并取得 pass receipt `483883F2…62BFE`。24 身份 r125 的 render/review digest 为 `8E531D95…2F46 / 4BC613FF…2832`，48 路含 5 个 `flip_x`、7 个精确 occupancy 人审恢复和 2 个独狼近阈值对应；
真人回执 `106A8816…EAFE` 冻结 16 pass / 6 adjustment / 2 wrong_pose。6 个 adjustment 的 fresh r127 guidance/receipt digest 为 `72842662…EC85 / 47042E62…44F6`。r128 按人工框选无模型重渲染 6/6，report `479AF12F…1580`、最大 MAE `4.161664≤8`；汽车炸弹以更晚的人类决定锁定车尾发动机为焦点，覆盖父回执里「强调车头」的旧语义。r129 镜像 ArmsArius 后恢复源图朝右，report `51AB99AF…A355`、MAE 0。方向反例：
ArmsArius 原始 `e19-c01/f1` 已朝右，但 r121 两路都错误输出 `flip_x` 并生成朝左结果——A/B 一致不是正确性证明。黑白无常 r130 `expand_search` 后，维护者以 `血腥死 → Symbol 597 / DefineSprite 591 → frame 249 → flip_x` 给出精确指令。r134 的有界 `16384²` retry render `B7BFC006…4CD` 取得人审 pass receipt `01F0D648…B458`，方向一致性回执 `38042FCC…535`。迷你黑洞保留 r125 frame 10；
r136 提供 A/B 两种构图 × gamma `0.50/0.75/1.00` 三档，6 项黑底合成最大误差均≤`1/255`，dataset `3266ABA3…A8FE`。文本记录的 atlas v6 / compact retrieval v4 要求（168 条当前标签、105 条几何、3 条 superseded negative 等）为当时口径，现役校验以 campaign 工具为准。

**原 L113：Team / Arena 头像 promotion 证据包口径（2026-08-09，历史）**：通用包闭合 226 identity / 227 variant / 221 个全 variant 已接受 identity / 222 human-accepted variant / 2 pending / 1 excluded / 2 aliases；manifest digest `EFDBD928…06E5`、receipt digest `17FC0D9B…0EDF`、supplement closure digest `C70B03A8…8AD3`、
base manifest digest `EED4D8DC…01D0`。evidence pack 闭合 353 条显式 records + 211 条 digest-bound selected-master 派生记录 = 564 条（560 条 `tmp/portrait-pilot` 生产证据、4 条 tracked controller provenance），25 项不可稳定重建的原始 JSON/PNG 进入逐 blob 校验 sidecar。
subjects exact-set 由 442 个唯一 runtime 文件与 17 条 hash-bound preserved 声明组成（12 orientation-only + 5 SVG reconstruction basis，后 5 条同时属于最终 runtime；evidence pack 的 `preservedSubjects` 只含前 12 条），去重并集、disk、tracked 均为 454，extra/missing 为 0。增量门绑定五项真人 4 pass + 家用机器人 1 explicit `flip_x`、
以及 `敌人-锡蒙利范围光环发生器 → 敌人-锡蒙利::default` 的签名 alias receipt `AF29A2B5…9ED`。Team 门确认原 98 identity / 99 variant 子集、JK `orange/white`、最终 10 个 Team 翻转 variant、Lady/巨臂僵尸/方舟爪豪尾项及未实装不知火舞均未退化。r221 digest `DDC843A4…0576` 当时得到 222/222、178 model keep / 39 human audit / 4 direct human pass / 1 explicit human flip，
以及 0 action/SVG/PNG mismatch / 0 legacy；r210（217 项）与 r220（旧 controller 的 222 项）只保留为历史基线，不得在 controller/manifest 合法演进后继续冒充 current。当时 `audit-arena-portrait-coverage.js --check` 口径：450 条目录 / 217 个消费身份 / 217 ready / 0 locked fallback，222 个 accepted variant 的 444 个 SVG/PNG 绑定 / 442 个唯一文件。
现役门与命令见 details [头像专项](../agentsDoc/testing-details.md#portrait)。

### 计数与口径取代链（速查）

以下为迁移时核对出的取代关系；「当前」一律以 runner 脚本机器钉值或机器真源为准（details 各节有指针），本表只是历史导航：

- `InventoryPanelServiceTest`：131 → 138 → 142 → 144/147 → 170（原 L1 宣布取代）→ **194（当前机器钉死，`scripts/run-item-panel-tests.ps1`）**。
- `PlayerAssetTransactionTest`：113 → 117（原 L5）→ **124（原 L3 更新，当前机器钉死一致）**。
- 玩家手动输入：474+50+28（原 L29）→ 486+57+**55**+14（原 L3）→ **486+57+58+14（当前机器钉死）**。
- combat-hp-impact：140（原 L6 冻结前）→ 153（原 L6）→ **159 assertions（当前机器钉死）**。
- map-loot：698=267+12+419（原 L67）→ 546=165+9+372（原 L108）→ 596=205+9+382（原 L114）→ 676/684（原 L108 R1）→ **795=189+12+594（当前机器钉死）**。
- Settings AS2：36 → 42 → **47（当前机器钉死）**；Settings harness 18/18、visual 116/116 等文本计数待核。
- ManagedLongGun：68 → **126（当前机器钉死）**；weapon-laser 89 → **97（钉死）**；warlord ActionEncounter 63(3 cases) → **97(4 cases)（钉死）**；map-domain 59 → **60（钉死）**。
- panel contracts：4 domains/23 commands → 5/31 → **7/42（`tools/test-panel-contracts.js` 断言钉死）**；变异门 62 → 66 → 68 → 70（文本，待核）。
- Character Build 六套合计：529 → 533 → 539 → 569 → 580 → 626 → 674 → 806 → 824（各轮文本；runner 只钉非零通过 + 0 failed，见 details [角色构筑](../agentsDoc/testing-details.md#suite-character-build)）。
- A5 material-shop 离线门：251 → 266 → 274 → 277（文本，待核）。
- KShop harness：93 → 100 → 135 → 138 → 152 → 153 → 155（各轮文本，待核）；NPC harness 89 → 106 → 109 → 133（文本，待核）；Crafting 三视口 79 → 99 → 120 → 150 基线（文本，待核）。
- panel runtime：27 → 36 → 40 → 41（文本，runner 自计数，待核）。
- dressup 只读基线（原 L12）：items 1292、skinKeys 2853、covered/export 2712、missing 141 等为当时冻结值，manifest 由生成器维护，不运行测试重生成。
- 通用 Audio 发布前置：「H2 前严禁 promotion/deployment」（原 L75/L85 历史语句）→ 被原 L87「Audio 通用发布解耦门」取代（现役，见 details [正式 runtime 发布](../agentsDoc/testing-details.md#runtime)）。
- Stage Select 通关返回：2026-08-24 自动回流合同 → 2026-08-26 纠偏门取代（原 L101）；pinned 检查器直接提交语义 → 双栏 Enter/Space 只选择、独立按钮提交取代（原 L100）。
- 军阀战棋适配：r10 故障口径 → r11 现役门取代（原 L95）；Slice 2/3 前基线 → Slice 6.1（原 L15/L94）。

- A3 四消费面 closure：2026-08-03/08-05 作者侧基线 → Superseded / Reopened（原 L46/L55），现役关闭条件见 details [跨层协议与权威](../agentsDoc/testing-details.md#cross-layer)。
- A5 材料商店：h3 机器 acceptance（原 L104）→ 被真人失败 supersede；v3 review → v4（原 L104）；v3/20 步与 v7 → key-only control-plan v4（1024 步，原 L106）。
- workbench audit：「0 error / 4 WB112 warnings、strict 未通过」（原 L24 旧结论）→ 2026-08-06 拆分后双树 0/0 取代（原 L103）。
- asLoader/TestLoader publish 字节与 hash：各轮记录全部只作历史，以当前工作树 fresh publish 为准。

<a id="archive-index"></a>
## 旧片段到当前 owner 的索引

原 testing-guide.md 没有显式锚点；下表把旧片段映射到当前 owner。选择层（任务 → 必跑/视改动追加的触发矩阵）由 `agentsDoc/testing-guide.md` 承担；本档案与 details 是被链接的正文/证据层。

- 原标题行与各「正式发布状态/发布证据」段落（原 L1、L3、L5、L6、L12、L14、L18、L56、L59、L104、L107、L108、L114 的收据部分）→ 当前状态唯一真源：`config/build/runtime-release-consensus.json`、`runtime/cf7-runtime-manifest.tsv`、`docs/runtime-build-reproducibility.md`；收据本体在本档案上半部分。
- 原「任务 → 验证入口矩阵」表行：L18/L21 → details [#specialized](../agentsDoc/testing-details.md#specialized)；L19 → [#suite-hairdresser](../agentsDoc/testing-details.md#suite-hairdresser)；L20/L26/L30/L46 → [#cross-layer](../agentsDoc/testing-details.md#cross-layer)；L22/L34 → [#data](../agentsDoc/testing-details.md#data)；L23 →
   [#save](../agentsDoc/testing-details.md#save) 与 [#suite-character-build](../agentsDoc/testing-details.md#suite-character-build)；L24/L25 → [#web](../agentsDoc/testing-details.md#web) 与 #suite-character-build；L27/L44/L45/L47/L48 → [#art](../agentsDoc/testing-details.md#art)；L28/L41/L97/L98/L99 →
   [#suite-map](../agentsDoc/testing-details.md#suite-map)；L29/L72 → [#stage-input](../agentsDoc/testing-details.md#stage-input)；L31 → [#suite-kshop-npc](../agentsDoc/testing-details.md#suite-kshop-npc)；L32 → [#suite-crafting](../agentsDoc/testing-details.md#suite-crafting)；L33 →
   [#suite-skills](../agentsDoc/testing-details.md#suite-skills)；L35 → #specialized（导弹）；L36/L39/L81–L83 → [#host](../agentsDoc/testing-details.md#host)；L37/L61 → #specialized（斗兽 campaign）；L38 → [#suite-arena](../agentsDoc/testing-details.md#suite-arena)；L40/L92 →
   [#suite-minigame](../agentsDoc/testing-details.md#suite-minigame)；L42/L100/L101 → [#suite-stage](../agentsDoc/testing-details.md#suite-stage)；L43 → [#suite-intelligence](../agentsDoc/testing-details.md#suite-intelligence)；L49/L111（头像段）/L112/L113 → [#portrait](../agentsDoc/testing-details.md#portrait)；L50/L52 →
   [#suite-tasks](../agentsDoc/testing-details.md#suite-tasks)；L51 → [#suite-team](../agentsDoc/testing-details.md#suite-team)；L53 → #suite-character-build；L54 → [#docs](../agentsDoc/testing-details.md#docs) 与 [#suite-equipment-set](../agentsDoc/testing-details.md#suite-equipment-set)。

- 原 §2 AS2/Flash 验证（原 L61 尾部、L62、L65–L71、L74）→ details [#flash-core](../agentsDoc/testing-details.md#flash-core) 与 [#flash-recovery](../agentsDoc/testing-details.md#flash-recovery)；操作链路 owner 仍是 `scripts/FlashCS6自动化编译.md`。
- 原 §3 Launcher Host 验证（原 L75–L89）→ details [#runtime](../agentsDoc/testing-details.md#runtime)（发布/解耦）与 [#specialized](../agentsDoc/testing-details.md#specialized)（Audio、Native HUD、PlayerInfo 专项）。
- 原 §4 小游戏与 Web harness 段（原 L92–L103）→ details [#web](../agentsDoc/testing-details.md#web) 与 #suite-minigame、#suite-map、#suite-stage。
- 原 §5 自动化与文档治理（原 L104–L108 及 L114 对应段）→ details [#save](../agentsDoc/testing-details.md#save)、[#docs](../agentsDoc/testing-details.md#docs)、[#runtime](../agentsDoc/testing-details.md#runtime)、[#diagnostics](../agentsDoc/testing-details.md#diagnostics)。
- 原 L109–L114 工具表 → details [#art](../agentsDoc/testing-details.md#art)、[#portrait](../agentsDoc/testing-details.md#portrait)、[#stage-input](../agentsDoc/testing-details.md#stage-input)、[#derived](../agentsDoc/testing-details.md#derived)。
- 旧文件标题式 fragment（如「任务 → 验证入口矩阵」「2. AS2 / Flash 验证」等）的入链由入口切换工作包在新矩阵页保留别名/转介；本档案不登记为常驻入口，也不承接新入链。
