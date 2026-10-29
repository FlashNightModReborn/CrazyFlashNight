# cf6-roguelike-content — K3 内容线 B 工具

CF6 肉鸽（cf6-sting 史实路线）遭遇与经济源片段生成器。只写
`data/stages/books/cf6-sting-source/`；不直接写 `data/stages/books/cf6-sting.json`
（主控集成），不改现役 units/items/AS2/共享 shops。

```powershell
chcp.com 65001
# 1) 原版遭遇事实表(SWF 反编译逐实例证据 -> encounter-facts.v1.json)
python tools/cf6-roguelike-content/build-encounter-facts.py
# 1.5) r6 几何落点适配表(最终环境 walkBounds/Collision -> placement-adaptation.v1.json;
#      仅 5 个声明落点,源点/事实表/几何身份不匹配即拒绝)
python -X utf8 tools/cf6-roguelike-content/build-placement-adaptation.py
# 2) 生成 maps/economy/shops/choice-rewards 四个源片段(自动应用适配表)
python -X utf8 tools/cf6-roguelike-content/build-sting-fragments.py
# 3) 只校验不写(单位/物品/弹药/精英配额/bossEncounter合同/商店档位/
#    配给merge真实校验/技能排除闭包/适配条目已应用)
python -X utf8 tools/cf6-roguelike-content/build-sting-fragments.py --check
# 3.5) 适配前后断言(仅5字段坐标变化/经济零漂移/几何复验)
python -X utf8 tools/cf6-roguelike-content/verify-adaptation-r6.py
python -X utf8 tools/cf6-roguelike-content/build-placement-adaptation.py --check
# 4) 组装候选章节到 tmp(保留 bossEncounter)并跑真实 validate_cf6+validate_cf6_boss
python -X utf8 tools/cf6-roguelike-content/check-chapter.py
```

依赖输入（只读）：

- `tmp/cf6-soldier-20261016/knife-audit/deobfuscated-export/scripts/`（原版 SWF 反编译，
  SWF sha256=b52af10e…，身份见 tools/cf6-soldier-assets/evidence/20261016-threat/original/source-identity.json）
- `tools/cf6-map-runtime/generated/<MAP>-original-geometry.json`（逐摆放坐标）
- `tools/cf6-tutorial/tutorial-map.fragment.json`（独立教学室，直接复用为 TUTORIAL；旧手工事实草案的教学出生点不再作为此图输入）
- `tools/cf6-actor-template/actor.fragment.json`（actor 片段真源，本线不复制）
- `data/items/list.xml` + `data/items/*.xml`（物品索引由生成器从现役数据确定性派生，
  不依赖 tmp 索引）；`data/units/units.json`；`data/skills/skills.xml`
- `data/rewards/choice-rewards.json`（配给 merge 校验底表）

产物（均在 cf6-sting-source/，候选性质）：

- `encounter-facts.v1.json`：逐图原版遭遇事实表（remainingDeathBudget 口径，r2 已纠正 transform/A16）
- `placement-adaptation.v1.json`：r6 几何失败 5 落点的显式 CF7 适配表
  （原字段路径/原 x,y/目的世界坐标/反算 native 新 x,y/碰撞理由/脚底盒验证证据）；
  事实表与原坐标保持历史来源不变，root 组装仍只减 nativeBounds 原点一次；
  生成器按 map+kind+原坐标+兵种 身份匹配应用，未消费/重复命中/身份不符即拒绝
- `maps.fragment.json`：21 图；bossEncounter（A06/A17/A20/A22）走 Astra 控制器确定接口；
  E1-E5 精英载体带 `Parameters.cf6EliteQuota='E#'`（A17 E4 在 bossEncounter hpRatio=1 组，
  无 InstanceName）；coordinateSpace=native-original，主控集成时统一变换一次
- `economy.fragment.json`：v3，`chapterEconomy={randomWeapons,eliteWeapons,choices}` 严格按
  `tools/cf6-prototype/economy-input-contract.json`（cf6-economy-input.v1），静态门为
  `tools/cf6_economy.validate_economy`；金币单杠杆、逐图预算、60 级边界、K点价差提案保留为证据
- `shops.fragment.json`：v2，4 档 npc-shop.v2 + 真实 level/goodsLevels 元数据 +
  主控裁定累计投放节奏（35@A01/40@A08/45@A11/55@A16/60@A19）+ NPC 模板
- `choice-rewards.fragment.json`：choice-rewards.v1，路径已被
  `tools/choice_reward_catalog.py BOOK_SOURCES` 登记，merge 即真实校验；kCost 必须为 0；
  配给包物品已在 `data/items/消耗品_自选配给.xml`（use=礼包，主控已生成）
- `source-evidence/`：逐图实例解析切片 + MANIFEST（EXE/SWF/提取器 hash）；
  完整反编译树与原件保留 tmp/原 EXE 只读，不入版本目录

已知边界：停止态生成器仅 1868 触发区可证实激活（A09/A14/A18），其余记 unknown；
异形以暴君克隆兽 460 作 prototype-reuse（主控试作采纳：外观/体型/行为与原作异形
明确不同源，不称原版等价；专用异形资产不进本轮 24–48h 资产扩张；真实消费者待验）；
zombie_turret→461 已验证仅普通僵尸适配，原炮台子弹受击通道 CF7 侧未实现，说明保留，
后续装配炮台机制需另核；A09/A14 精英载体占原 467 名额、图敌人总数不变（各 9）；
r6 落点适配 5 处见 placement-adaptation.v1.json，A06/A17 屏外对称增援、A17 Boss
原作高度、教学既有门保持不改列实机待核；
A01 的 461×20 是按 20 死亡阈值的 prototypeDerived 有限化，不称原版固定 20；
背景 SWF 20 张已全部真实 CS6 编译（地图线 canonical 批次回执，Compiler 0/0），原“缺 13 张”状态已解除；但全游戏 20 图尚未走通，教学关当前为练习场占位，待 K3 maps r10 以宿舍床/工作台/门灯等矢量素材复刻教学室后替换；
金币总账由 root+Astra 另行冻结 balance-input.json（本线不加金币、不改单价）；
设计§5点名的钛合金P90/KRISS印花集现役 use=手枪，不满足消费合同长枪约束，
不进 randomWeapons（钛合金P90 留商店二档采购），A11/A12 以同级真实长枪补足。

## 史实武器试用池（2026-10-24）

`weapon-pools.source.json` 保留报告白名单、4项精确名称映射、21项未确认名称与6项现役来源/占位排除；`weapon_pools.py` 从现役 `items/list.xml` 和 `equipment_config.xml` 解析真实等级、使用槽和弹药。报告只作候选依据，不替代 XML，也不把合成树当作已交付实例。80个技术候选（45基础、35进阶）完整保留为资料；用户明确史实线守住年代，后期装备留给61线，本轮不实现61线。

`historicalPolicy.acceptedWeaponNames` 是当前史实投放白名单，`historyEvidence` 保留报告行号/分级。当前史实高级基础枪共33种；E1—E5与固定枪械保持各自免费配额，扣除这些独占来源后五个配给共29个bundles（19枪械、10技能/补给），全局97，继续使用原128套/每组32项上限。五档候选14/14/19/19/21，每次无放回抽3选1；六个随机池9/12/12/12/5/5。50级强力重武器可服务后段，不能按等级硬塞统合后期枪。

地面与配给可共享普通候选，单池去重。短枪生成两条独立 Value=1，弹药为两把总量；固定A01/A15同样按双持交付。E2用TTI Gen 12/AA12丧尸，E4保留MG42战术版（2026-10-28按用户要求移除暴力版M134，后者仅保留K点购买），E5用量子能量枪/战术版喷火器；A10固定SPAS12，A15固定MP7极品战术版。所有技能、金币、SP、K和已有冻结offer语义保持原合同，不拓展地面Value、配给tier或局内合成。

生成前静态门同时检查源片段、预算实际商店、保守购物路径和压力样例；实际章节验证继续检查actor/fixed/random/elite/enemy/choice枪名。报告Tier B不自动成为史实准入；墨冰/狱火/重锤及成熟钛合金装备均保留后续审阅资料。报告Tier A中的战术版MGL因现役文字为ShopGirl修复自制且缺行动前来源也暂缓；不以泛称“末日前”代替毒刺行动前。

生成顺序由主控串行执行：本目录 `build-sting-fragments.py` → `tools/build-choice-rewards.py` → 章节装配与书籍生成；预算正文由 `tools/cf6-prototype/economy-budget.py --write-readme` 再生，并分别执行对应 `--check`。`python tools/test-choice-rewards.py` 与 `python tools/test-cf6-economy.py` 覆盖年代拒绝、双短枪和候选共享。真实CS6与实际开包/拾取另验；源码与静态通过不代表已交付或手感通过。

## 章节难度适配（2026-10-24）

`difficulty.source.json` 是本轮必清波编成、原作登场顺序和有限同屏配置的编辑源；`difficulty_plan.py` 实施并生成 `data/stages/books/cf6-sting-source/difficulty.audit.json`。先对原始生成模型执行既有全部事实/配额校验，再应用显式章节设计；原作事实表、单位面板、武器XML、玩家初装和61线不改。该适配不会把原作数量改写成新原作事实。

A06/A17/A20分别为3/4/6个标准必清SubWave，最后波独占原Boss。主要精锐/重型预算放在Boss出现前，A20的5个前波共72个primary单位，再进入原生人形→机器人；Boss死亡仍取消可选旁支，没有新增阶段无敌或改写原生93帧接续。A17 E4从可选旁支迁入必清前波，依靠唯一`cf6EliteQuota`，不依赖InstanceName。

保护预算单独记账：A01炮塔可命中标记仍恰20只兼容461，其余新增僵尸/保安不扩大标记；A15原5培养皿仍在wave0真实触发、后加两波；A17原5培养皿仍归maxAlive4/interval45初始可选支援。A09/A14/A18运输车仍拥有wave1原5/7/5及原Type/Level、frame29与Cf6TransportReady，新增波不复制车内预算。A08/A16整备、教学和A07车战保持原入口与内容。

并发上界按WaveSpawner实际语义计算：每个**去重SpawnPoint**取`min(本波分配量,QuantityMax)`后求和，再加地图桶/静态单位；不把多个entry共享的同一点容量重复相加。除电梯预置战外，新增普通编成只用两侧受控点，装配时优先原可见门或显式左右出生线，并验证24×12脚底包围盒与碰撞。单波多entry保持400ms节拍及200ms逐队列错峰；最大14个普通producer槽，原生变身后继和尸体过渡不等同已测同屏峰值。

上一轮外部报告仅作历史设计参考：其35枪应区分33高级基础枪与两把原普通士兵枪；报告使用的旧版17个战斗房中13个单SubWave，A10/A12/A14/A17/A19等报告敌数还混入469后继；新的编成表中A10列举25却标26、A11列举26却标30、A20列举60护卫+两Boss却标88，不能照抄总数。0.25穿刺系数、几秒秒杀及相对主线倍率都只是外部模型，本审计只给primary预算、可选预算、后继可能数量与结构上界，不称实玩难度结论。

第五轮以 `encounter-facts.v1.json` 的已证实静态单位、活跃生成器、真实触发器与培养皿推导首次登场；未证明激活的停止态模板不解锁兵种。普通特种兵从A06、盾兵从A09、变身保安从A10、直接异形从A15、大刀机器人从A17、敌方Wings从A18开始。蛮斧的A06首领与A18普通再现、大头的A17首领与原A22终局支援分开约束。提前兵种改成更多已登场敌人，保留精英、运输车、培养皿及奖励配额。A10/A13各一波12个Quantity=1的预置单位，无SpawnIndex、Delay、Interval或增援事件，站位经过现役碰撞盒与登梯终点检查；现役StageInfo归一化后在首轮最小堆调度完成，不等待击杀补位。

`python tools/cf6-roguelike-content/test-difficulty.py` 检查源事实仍先验、逐波编成、必清条件、配额守恒、源不可变、共享点容量、完整内存装配后的真触发和碰撞。继续运行spawn/transport/scene现有静态测试；完整章节与BookDefinition由主控统一生成并做真实CS6及独立实玩验证。

2026-10-28金币目录按非书中无额外条件金币店追溯，经典低等级枪只加入 `acceptedShopWeaponNames`，不因此扩大原免费池。`kOnlyWeaponNames`同时限制普通随机池和配给，E4单一候选仍只交付原一把枪；已冻结offer与已取得物品不重写。渠道生成与预算校验共享 `tools/cf6_acquisition.py`。
