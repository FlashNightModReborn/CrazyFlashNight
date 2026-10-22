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
