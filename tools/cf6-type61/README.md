# CF6 61计划内容与验证入口

## 固定158火力候选

最新配装以 `soldier-loadout-plan.source.json` 为后续审阅真源：145把可正常改装长枪均为战术鱼骨零件加两个功能插件，13把封闭长枪保留工厂限制。124把短枪逐把独立配置，封闭或零槽例外保留；不用卡宾转换，不跨手组合结构标签。共19种完整组合；保留原34个下挂武器及其动作和弹体预算。短枪单插件是本轮固定敌人的配装约束；部分进阶短枪仍按现役引擎继承原型槽数，未调整全局武器规则。目录仍允许4个Beretta90TWO槽使用卡宾套件，本候选明确不用。`loadout_rules.py` 只支持这10种已准入插件的有限生成校验，不代替生产装备引擎。

新增 `run-cf6-loadout-oracle-tests.ps1` 从现役XML、强化和进阶配置加载全部282槽，经过真实 `BaseItem`、候选菜单、逐步安装门和最终计算，核对威力、槽位、原射击动作与投射物数。完整插件后的基础威力由有限XML运算独立复算，B/C预期值用二分求预算边界，并由原生火力测试交叉核验；不再把更新后的数值称为原始Pro预期。`test-loadout-plan.py` 覆盖扩槽顺序、封闭例外、标签互斥与两手隔离。

`soldier-firepower.source.json` 保存按身份、枪槽隔离的补偿及数值锚点；原始方案 SHA-256 为 `bbb415835015a6ade900e542a5debf13e4d2bcd624a2ac09030ba4f2a0b7f2b5`。`fixed-roster.source.json` 只回填配枪、实际插件材料候选和 `programWeapon`；后者固定原AI射程类别，生成程序必须与原版相同。身份、生成、强化、危险效果和弹体预算不改。

精确准入使用 `name + form + tier`，装备属性遵循真实 `TierSystem` 的覆盖语义。`Cf6SoldierFirepower` 只在正常枪械模板建立或刷新时读取实际基础威力、已有倍率与固定加成，并缓存同一预算下的成长、火控牌、被动和毒。既有被动不重复叠加；不修改全局伤害、人物技能、BaseItem或缴获快照。高危、射线及未解决多段不追加补偿。VI的毒上限为4，仍经过原生门槛和护盾吸收；0.025有效物理系数是其预算适用范围，并不证明任意极端防御构筑的增幅上界。

默认C档。A仅换枪，B加成长/火控牌，C只给枚举的教官槽追加共同预算内的被动与毒；这些分档用于验证，不新增玩家设置。没有安装插件的席位只移除材料类别，其正常武器缴获门保留。NA45的本地准入失败与5席替代集中在 `firepower-local-adaptations.source.json`；全局武器配置保持原值。

后续配装先运行 `apply-loadout-plan.py`（校验加 `--check`），再按生成顺序：`build-route.py` → `tools/build-book-definition.py` → `build-fixed-roster-fixture.py`、`build-fixed-actions-fixture.py`、`build-soldier-loot-fixture.py`、`build-firepower-fixture.py`。各生成器支持 `--check`。原始方案导入用 `import-firepower-plan.py --proposal <JSON>`，首次本地适配用 `apply-firepower-adaptations.py` 并以 `--check`复证。原始导入与5席换枪证据保持不可变，不能在后续配装上重跑旧导入覆盖。

`run-cf6-fixed-native-tests.ps1` 联合实际158席装备/枪模、正常动作场景和282槽独立数值锚点。`run-cf6-fixed-projectile-tests.ps1 -AllForms` 还检查每个最终精确形态的真实弹体、碰撞和退场：附加准入夹具通过实际许可启动已有主枪/双枪分支，持盾副枪先走真实破盾；它不证明AI会在所有实战情形主动选择该分支。伤害幅度仍由夹具控制，真人构筑强度与手感留待可玩候选验收。

`route.source.json` 是61路线配额、初装、技能与补给的编辑源。地形、原战波、机关和有限Boss支援引用现役 `data/stages/books/cf6-sting.json`，生成独立的 `cf6-type61.json`，不覆盖史实源。设计依据见[完整施工方案](../../docs/闪客快打6肉鸽-61路线完整施工方案-2026-10-25.md)，执行状态见[施工与验证记录](../../docs/闪客快打6肉鸽-61路线施工与验证-2026-10-26.md)。

## 生成归属

| 输入或消费者 | 归属 |
| --- | --- |
| `route.source.json`、`build-route.py` | 61配置、分阶段取得入口与确定性装配；额度变更需同步重算设计底账 |
| `../cf6_acquisition.py`、`acquisition.generated.json` | 从非书中金币店、K店、原配方追溯渠道；金币售价不能自动授予金币购买入口 |
| `acquisition-budget.py`、`acquisition-budget.generated.json` | 当前渠道、含项链十件11强化的固定配额采购差额；不计死亡收入或售枪 |
| `data/stages/books/cf6-type61.json` | 独立章节源投影；书籍生成器再生成同名 runtime JSON |
| `choice-rewards.fragment.json` | `choice_reward_catalog.BOOK_SOURCES` 显式合并的61候选；自选生成器生成共享目录与道具 |
| `recipes.generated.json` | 章内钛合金升级；书籍生成器追加到既有“书中配给”分类 |
| `data/shops/npcs/书中-CF6六一-*.json` | 整备节点的金币目录；注册到 shops/list 和 local 访问策略 |
| `data/items/消耗品_CF6六一配给.xml` | 随机星座箱及即时补给；即时补给不入背包 |
| `Cf6Type61Fixture.as` | 从同一源派生的测试专用地图、配置和演员元数据；生产入口不引用 |
| `manifest.generated.json` | 输入、生成物与预期 runtime sidecar 的SHA-256及体积；不证明SWF编译或发布 |

```powershell
chcp.com 65001 > $null
python -X utf8 tools/cf6-type61/build-route.py
python -X utf8 tools/build-choice-rewards.py
python -X utf8 tools/build-book-definition.py
python -X utf8 tools/derive-material-catalog.py derive
python -X utf8 tools/cf6-type61/acquisition-budget.py

python -X utf8 tools/cf6-type61/build-route.py --check
python -X utf8 tools/build-choice-rewards.py --check
python -X utf8 tools/build-book-definition.py --check
python -X utf8 tools/derive-material-catalog.py --check
python -X utf8 tools/cf6-type61/acquisition-budget.py --check
python -X utf8 tools/cf6-type61/test-route.py
python -X utf8 tools/test-book-definition.py
python -X utf8 tools/test-cf6-economy.py
python -X utf8 tools/test-choice-rewards.py
node tools/validate-reward-packs.js
node tools/audit-grade-colors.js
```

生成器拒绝额度求和漂移、非法初始枪械、缺失弹种、重复战波补给，以及电梯名单、禁学清单、强化阶段或候选钛合金价格漂移。测试数据按地图拆分函数并设置单段大小门；实际AVM1函数大小仍须在真实编译后检查。体积和哈希以manifest为准，不手改生成物。

新增商店身份同时在商店肖像baker和资产校验器的显式共享表中登记，指向迷之盔甲君。复算沿用既有provenance的采样倍率，本轮为1；FFDec使用本机已有Java环境。先在候选目录生成，确认旧记录和所有PNG逐字节相同，再由既有 `promote_stage` 写入工作树资产，最后执行完整 `bake-shop-portraits.py --check --ffdec tools/ffdec/ffdec.bat --supersample 1` 及头像/懒加载门。这是本地Web资源更新，不是正式runtime promotion。

## 运行权威

书架游玩目标 `cf6-sting.type61` 映射到 `bookId=cf6-sting / routeId=type61`。暂存候选、进出身份、待结算记录及战绩分别保留路线；历史CF6自选候选缺 `routeId` 时只属于 `historical`。没有新增Web命令。

`Cf6Type61Service` 在实际清场后、出口开放前，用 `RewardStashService` 同次保存金币、K、经验补差、自然/额外SP、物品及领取标记。A07须等车辆终点完成；其他地图保留Boss/机关本身的清场门。未知结果只查询原操作，暂停保持到清场真正续接，防止车辆提前消费一次性转场。A19沿原手动出口保留最终整备机会。

教程开场在原有配给事务中，按局种子从光剑天秤、光斧金牛、光刀狮子、光刃摩羯中等概率直接发一把武器；教程领取标记同时约束这次发放，保存未知或重复回调不重抽、不重复领取。A01不再发普通星座箱。旧箱的物品定义保留，已有箱子仍可正常使用。四次后续机缘箱及血剑概率不变。

出场主枪箱同时发放所选主仓的8次备用弹。A04/A08主枪份额按当前已装备枪械弹种交付，未装备时使用出场选择；M4基准与既定预算一致。副仓榴弹、电池独立配给；高压即时补弹只补已装备枪械及支持的副仓，不生成备用库存。

A04仍使用原随机枪名额，从原结果与HKSL8EX中选择一项。2026-10-28起，首次开包若某项同名主枪已在背包、装备、仓库、战备箱或奖励暂存中，则优先替换为现有A04枪池内未持有、当前等级可装备、出售价值不低于原项的枪；优先最接近的价值，同价等概率，且避开同箱其他选项。无合适替代时保留原项。短枪原结果仍是两把独立实例，插件按原需求允许重复，已冻结选项不重抽。插件箱开包前使用现役 `EquipmentUtil` 检查实际宿主、槽位和标签；中级箱须有可用枪械宿主，无合法宿主时箱子保留。药品、材料和货币独立于这些选择。A16收到星座箱后应先开箱，再决定统合/钛合金转向。

Boss与专属支援、电梯名单的倍率由出生参数冻结；原生变身后继核对世界、阶段与子体身份后继承。普通波、角色成长模式及全局难度保持原合同。战场补给按局次、地图、波、阶段与类别识别唯一投放；随机Buff优先来自有限载体击杀，后备计时与快速清场补齐不重复发放。

学习、合成、金币/K购物、商品导航及强化上限均在AS2领域裁决。61装备出售使用未强化基础标价的25%；敌人死亡金币携来源标记恢复原随机转K，固定配额精确入账。主线与史实路线保留各自规则。

## 验证入口

Host全量使用[受控资源窗口入口](../run-focus-sol-recheck.ps1)，保留无资格失败和后续原件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-focus-sol-recheck.ps1 -Phase integration -Canonical
node tools/test-bookshelf-runtime.js
node tools/test-character-build-item-use.js
node tools/run-bookshelf-flow-harness.js --shot-dir=tmp/cf6-type61-ui
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-type61-tests.ps1
```

新Flash专项覆盖真实成长函数、SaveManager初装预检、候选/未知结果/回滚、局部倍率、变身归属、补给幂等、实际拾取货币分支和售卖报价。测试使用新生成且确认为空的nonce槽，不打开玩家槽。`-SkipCompile`只校验runner和源文件，不构成测试通过。

受影响旧域继续运行书架、CF6经济、自选奖励、奖励暂存、技能、强化、战场补给及史实初装回归，见[原方案验证清单](../../docs/闪客快打6肉鸽-61路线完整施工方案-2026-10-25.md)。编译遵守[CS6操作合同](../../scripts/FlashCS6自动化编译.md)：测试用 `-Target test`，逻辑交付用 `-Target publish`；编译锁、未知marker与共享配置恢复不能绕过。

真实新局仍须验证35级初装/快捷栏、M4主副仓装填、171电池补仓、电梯与变身、A19整备及退出恢复。源码、Host或浏览器通过均不替代游戏证据，也不授予正式runtime发布权限。

## 2026-10-28 取得入口修正

点击场内61计划整备商人，选择“装备合成”打开既有合成工作台。A01默认进入武器合成，A05默认进入进阶防具，A11起默认进入书中配给；同一菜单另有武器、插件、铁枪会、项链与统合修复等已解锁分类的直达按钮；同类入口不重复，空分类不显示。执行动作时仍复核同一NPC、菜单请求、场景和本局准入，重复或迟到菜单动作不能再次打开。

统合61在A05消耗普通61对应部件与配给材料；铁匠1开启时五件共285,000金币和25,650 K。钛合金61在A11消耗对应统合部件，五件再需475,000金币和42,750 K。合成材料中的插件先沿现有拆卸流程取回，原配方费用与装备继承规则不变。

金币武器必须已有非书中、无额外条件的金币店来源。普通M134为31级，已补回A01目录，同批补齐机枪、发射器、长短枪等经典类别；低于35级不构成剔除理由。暴力版M134在A16开放原50,000 K入口，并从后续免费随机池与E4候选移除；E4仍保留一份MG42战术版配额。已冻结奖励和已得物品不重写。仅合成、K点或有限掉落的枪不再凭物品标价进入金币店；除用户明确点名的暴力版M134外，有限奖励池的配额不随商店扩充增加；已有冻结选项不重抽。

插件按A01/A05/A11展开，覆盖导轨、电力、下挂、卡宾转换、换弹、弹种与近战技能。现成插件配方开放原费用和所需材料，灰蛊弹与金属风暴下挂等保留合成渠道；所有新增下挂弹种与现役弹药目录核对。安装仍由装备的类型、结构标签、互斥组和槽位裁决，目录可购不等于任何枪均可安装。

新开61局直接装备35级战斗狂人军牌、强化1，并提供按构筑选择的项链取得链。含项链、刀、长枪和双短枪后，全装备11强化共十件、19,280颗强化石；固定10,002颗以外还需9,278颗。旧九件毕业表和暴力M134低金币分支的概率余款已失去当前采购前提，只保留为历史方案。当前指定配装的固定配额差额见[采购底账](acquisition-budget.generated.json)。2026-10-28教官编排修订后，固定金币（含出场）为4,750,000，固定K为100,000。五甲钛合金、双钛合金P90、普通星座和项链十件全11，沿已核对插件方案并预留150,000、完全不计死亡收入或售枪时：普通M134余744,200金币，暴力版仍差613,400，钛合金171仍差1,309,600。沿有限武器配额最低出售收入和默认掉钱规则重算的情景见[遭遇与经济模型](encounter-budget.generated.json)，不把随机收入当作固定配给或通关概率。

星座箱采用本局获得记录与实际背包、装备、仓库、战备箱、暂存共同防重。新局首发也写入该记录，卖出后仍算获得过；旧局只回填实际持有物品，不推断已经丢失的历史。血剑尚未取得时保留10%机会，普通星座优先补齐；普通四种集齐后才允许重复，已经获得血剑后不再重复发血剑。记录与扣箱、发物资在同一个奖励保存候选中冻结，批量开箱逐包排除本批先前结果；未曝光失败回滚，未知写只确认原操作。

本轮编译、回归及剩余实机边界记入[当前修复回执](../../docs/reports/cf6-acquisition-repair-2026-10-28.json)。

## 固定158配置与缴获

2026-11-04候选将Pro v2的96名普通兵、40名精英、22名教官接入12张地图。`fixed-roster.source.json`保留审阅输入，`fixed_roster.py`编译每个出生席位的身份、等级、装备实例和动作配置；`soldier_programs.py`给出22种可执行战术。`build-route.py`在原章节基础上生成固定席位，`build-book-definition.py`同时核验原坐标、原生成节奏与逐席数据。运行侧通过`WaveSpawner`与`Cf6BossEncounter`消费席位，不由出生顺序随机挑选装备。

明确迁移仅三席：A17的`CF6-C-PE-R-06`与`CF6-N-SW-01`移入首领增援，A20的`CF6-M-IX`移入机器人阶段增援，保持45帧间隔。其余原调度保留。装备强化、两把独立短枪、实际插件和G1111布尔模式在出生时恢复；教官称号显示固定身份。

2026-11-07复审按用户指定，将`CF6-M-XIX`和`CF6-N-PE-07`的普通M134换为50级M134暴力版，保留原强化、鱼骨与功能插件、AI程序及五段射击预算。这是仍超7级差的部分等级改善；60级PIG版对59级超装、对60级增加分裂，不能直接套入原预算。原方案的“有条件保留、未补偿”不等于同级压力已验证，强化与已有武器属性也不能当作额外成长补偿。其他等级例外在候选验收报告中逐项说明。

缴获替换固定158的旧E1–E5保证武器名额。`soldier-loot-policy.source.json`是当前概率设置：普通/精英/教官基础名义缴获包概率5%/8%/12%，沿用现役掉落PRD及逆向技能加成。每身份只裁决一次，从长枪、双短枪、插件材料或无掉落中选择一个结果；整章上限为6包、2对双枪、8件武器实例、2包材料。取消增援、破盾和退场不等同于二阶段战斗死亡。

若此前未缴获武器，第8次有效固定兵死亡提供首把长枪保护（需要当前完整武器及备用弹可交付），占同一身份和原配额。正常PRD门仍只执行一次，保留自然推进；保护只替换本次类别，不倒退或重复随机。判据和自然命中写入同一个冻结裁决，未知写只查询原操作。旧局已保存的未命中不改判，若其已超过门槛，下一名新的有效击杀可触发保护。5%是整包名义概率；普通包通常仍按70%长枪/30%材料分流，并非每枪独立5%。缴获进入奖励暂存，沿用提示，不生成地面装备，也未新增防具掉落。

死亡时冻结实际`BaseItem`的完整`name/value`，保留已用弹数、插件及未知扩展；同包按真实普通付费装填成本发放每把武器与安装副武器的一次备用弹，两手同弹种相加。先持久保存裁决和配额，再经`RewardStashService`原子接纳；保存结果未知时查原操作，不重抽、不重复奖励、不提前报告安全退出成功。AMF空数组归一化仅接受已知空字段，不重写未来版本。旧局已冻结的历史奖励不追溯回收。

六项武器说明只更新description节点，不增加商店、开局池或虚构物品。具体采用文本与原值校验见`apply-soldier-descriptions.py`及`soldier-description-application.json`。

定向检查：

```powershell
python -X utf8 -B tools/cf6-type61/test-fixed-roster.py
python -X utf8 -B tools/cf6-type61/test-route.py
node tools/cf6-type61/test-soldier-program-contract.js
node tools/cf6-type61/test-soldier-loot-rules.js
node tools/cf6-type61/test-soldier-loot-service.js
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-soldier-loot-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-fixed-chapter-tests.ps1
```

真正重启持久化验证用`prepare-loot-cold-host.py`生成独立测试宿主，依次运行`run-cf6-soldier-loot-cold-tests.ps1`和`run-loot-cold-read.ps1`。只接受本轮随机测试槽；16个独立播放器验证长枪/双枪/未掉落/首把武器保护的裁决、接纳、领取、冷读回。若使用`-ProbeSwf`，必须与本轮编译SWF哈希相同。可用`-CandidateRoot`显式绑定本仓`tmp/runtime-candidates/v2`下的直接子候选，使用其Core存储环境；不传时保持现役`runtime`，实际Core路径与哈希进入报告，不为测试覆盖正式二进制。该工具需PowerShell7与本机运行库；不使用真实玩家存档。冷读入口默认生成并核验同哈希的隔离短路径副本，完成16进程读回后仅清理其自建副本及空目录；避免深工程路径进入Flash本地SharedObject命名空间。

2026-11-07用户完成候选试玩并授权合并上游、提交、部署与推送。正式部署状态以runtime manifest及consensus为准。缴获提示在Host沿用精确来源`cf6_type61`；未登记来源仍拒绝，不扩大到任意来源。中级插件箱预检没有可用选项时保留原库存对象和箱子，面板只在需要写入时进入保存通道。

本批未包含机枪持续连射、Wings属性环境单位或地面装备拾取方案。两席M134升级仍不消除所有超过7级的武器等级差；其余例外和独立补偿不得视为已验证充足。下文历史经济模型按旧有限武器名额计算，不能据其概率余款推断固定158缴获的收益或难度；整章经济和战斗节奏仍需后续精算及专项体验。

合并后的机器验证和测试修正边界见[固定158合并验证记录](../../docs/reports/cf6-fixed158-merge-validation-2026-11-08.json)。部署身份仍读取正式manifest和consensus，不由这份源码验证记录代签。

## 教官递进与前置防具经济

兵种替换由 `encounters.source.json` 绑定原地图、波次、条目、原兵种及原数量，生成器拒绝源场景漂移。坐标、事件钩子、载具与原有Boss机关保持原归属；新增特种兵不复制E1至E5有限掉落。普通兵和精英带“精英”抗性键，接受黑爪扩张弹的类别增伤；教官以阶段8、档次系数9正算面板，只有“首领”类别，不带“精英”。

维护者在2026-10-28补充了既有同面板斗兽结果：教官凭AI已有显著优势。因此初见按Boss对待，不能用HP或攻击倍率直接折算人数。A13首见仅一名持盾教官；其2.5倍电梯难度仍保留。

| 地图 | 普通兵 | 精英 | 教官 |
|---|---:|---:|---:|
| A06（含2名有限Boss支援） | 10 | 0 | 0 |
| A09 | 15 | 1 | 0 |
| A10第一电梯 | 0 | 4 | 0 |
| A11 / A12 | 14 / 20 | 2 / 3 | 0 |
| A13第二电梯 | 0 | 0 | 1 |
| A14 / A15 / A17 | 20 / 4 / 13 | 7 / 1 / 4 | 2 / 1 / 2 |
| A18 / A19 / A20（含有限支援） | 0 / 0 / 0 | 5 / 7 / 6 | 5 / 7 / 4 |
| **合计（整副塔罗编制 158 人）** | **96** | **40** | **22** |

历史基线曾采用统一装备与E1–E5保证武器名额；固定158候选现按逐席配置装备、有限投掷物和烟雾，并使用上节概率缴获。人数与原有教官面板保留。

钛合金61的物品需求为45级，本路线配方提前至A11。新增K前移到A08至A11；第一电梯A10清场即交付所需货币，进入A11后即可在当地商人完成升级；不用先清A11再回头，也不提前计入A12收入。固定资源硬检查如下，均含150,000补给预留、不计死亡收入和出售：

| 整备时点 | 下一威胁 | 可完成的基准构筑 | 固定金币 / K | 支出后余款 |
|---|---|---|---:|---:|
| A10清场领取，进入A11即整备 | A13教官 | 钛合金61五件、M134、双钛合金P90、普通星座、初始军牌与预算插件；十位全7 | 1,500,000 / 78,000 | 40,000 |
| A16清场后、离开商人前 | A17混编与后续教官编队 | 同上，五件防具11、其余五位9 | 3,550,000 / 100,000 | 564,200 |

这是可购买且可支付的构筑路径；额外购物会占用其预算。原物品价格、铁匠1继承强化、强化上限节点与已有领取标记保持原规则；旧局已领取节点不补发新增配额，完整新配给需要新开一局。

玩家投掷物沿现有配给事务发放：教程高爆手雷6、燃烧弹4；A04 BBPLAYER手雷6、寒铁镖24；A08 BBPLAYER手雷8、翼炎钉针40；A12 BBPLAYER手雷8、导弹信标3；A16核弹手雷2及BBPLAYER手雷8；A19核弹手雷3及BBPLAYER手雷10。商店按原等级和价格提供补购，核弹手雷到A16才开放。投掷物出售收益未计入毕业预算。

复算和一致性检查：`python -X utf8 tools/cf6-type61/encounter-budget.py`，生成后再运行同命令加 `--check`。该模型按真实等级插值、有限名额、固定费用和默认死亡货币概率计算；不包含AI胜率、原生变身追加体、随机装备额外掉落或真人体验结论。

运行时的固定额度校验同时采用节点金币4,720,000（另加出场30,000）和K点100,000；真实AVM1必须接受本轮生成配置并继续拒绝额度漂移。编译、候选与剩余实机边界见[教官与保存修订报告](../../docs/reports/cf6-instructor-save-rebalance-2026-10-28.json)。
