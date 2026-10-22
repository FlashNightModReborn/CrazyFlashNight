# result-r5.md — K3 内容审查线 r5（最终装配内容只读审查）

日期 2026-10-21。授权边界遵守：全程只读章节/片段/现役数据与原作反编译证据；未改源生成器、源片段、
root 章节、AS2、美术；未提交/推送/发布；未触凭据/外部服务/安装依赖。
写入仅限 `tools/cf6-roguelike-content/integration-audit/` 与本线 `tmp/.../kimi-content/r5/`。

## 快照身份（SHA-256）

- 审查目标 `data/stages/books/cf6-sting.json`：**b15cbee0…489833**（审计运行首=尾，drift=0）。
- 披露：本轮会话首次接触该文件时为 `083be489…(133269B)`，root 于 16:13 集成后变为
  `b15cbee0…(133549B)`；本报告全部结论针对后者，运行内首尾一致。
- 其余 24 项输入（5 片段、balance-input、units/skills/items/shops/enemy_properties/
  asset_source_map、encounter-review 等）SHA 全量记录在 `audit-r5.json` 的
  `inputSha256Start/End`，首尾零漂移。报告为快照，不循环追写。

## 真实验证器证据（只读执行）

- `build-book-definition.validate_cf6`（对**现役章节**直接跑，非 tmp 候选）：
  strict 唯一失败 = 背景门；`require_backgrounds=False` 全过（含 validate_cf6_boss×4 +
  cf6_economy.validate_economy，catalog 经 `choice_reward_catalog.BOOK_SOURCES` 真实合并）。
- `tools/build-choice-rewards.py --check`：`catalog and item projection verified`（只读）。
- `tools/test-cf6-economy.py`：14/14 OK（未改 Astra 验证器）。
- 严格背景缺失单列（13 张，地图线交付，未剥字段/未建假 SWF 绕门）：
  cf6/CF6_A09..A20_BG.swf、CF6_A22_BG.swf（TUTORIAL 用现役 gk1_1_BG.swf 不缺）。

## 审查结论总览：pass-with-caveats（0 error / 1 warning / 2 info）

| 检查 | 结果 | 要点 |
| --- | --- | --- |
| C1 免费渠道同配额去重 | pass | random 13 枪 ∩ elite 9 候选 ∩ choice 5 枪 ∩ 固定拾取 5 枪 = 全空；无同图双随机行/配额重复；配给包未手塞固定 Pickups/掉落。商店为付费渠道，与随机/精英同型号（DD MK18战术版/M60E3/AA12丧尸/高斯枪/RShG4/钛合金QJZ171/战术-QBU-191等）保留属 r4 已裁定设计 |
| C2 精英载体唯一·最终死亡才发 | pass | E1@A09(466,elite_e1)/E2@A13(467,elite_e2)/E3@A14(466,elite_e3)/E4@A17(bossEncounter hpRatio=1.0 组,467,无InstanceName,控制器命名)/E5@A19(467,elite_e5)；每配额全章唯一、Quantity=1；掉落=候选首项枪 概率100 1/1/1 + 配套弹药×3，带 不掉装备+保留屏外尸体；仅经死亡掉落发放，无第二投递路径。注：A17 为 Boss-hp 出口，E4 载体可跳过→不发，符合"最终死亡才发"语义 |
| C3 初装 11 不传新枪 | pass | actor 8 槽全 enhancement=11；economy/choice bundles/全部 stage/bossEncounter 载荷递归扫描零 enhancement 字段；精英"抽定枪强化1"系消费端合同（economy.fragment eliteQuotas.rule），非内容侧装配 |
| C4 四 Boss 与增援身份 | pass | A06=463/A17=472/A20=473/A22=474 互不重复；主 Wave 各仅 Boss 一名且 InstanceName=cf6Boss_Axx；各图增援均不含本图 Boss 兵种；A22 增援无 474（构成 463/472/460/465 各15=原作构成）；A20 老头变身=false；增援无 InstanceName/保留参数；hpRatio 严格降序；支援总量 35/40/40/60；Boss 枪 长枪=G36 消费待实机核（r2 已标，非本轮新发现） |
| C5 60 级不投经验 | pass | actor 60 级/经验 157526193；全章拾取/掉落/choice bundles 无 经验值/技能点 免费投放；startingSkillPoints=0；商店以金币售"技能点"属设计内 SP 流通（economy.fragment level60Boundary） |
| C6 商店早晚档/真实弹药/技能白名单 | pass | 现役消费店=root 按 balance-input 生成的 书中-CF6毒刺-35/40/45/55/60级（已登记 list.xml），投放 A01/A08/A11/A16/A19 与章节商人 Instance 检索名一致；目录累计（后档含前档）；15 支在售枪等级均≤档顶且每枪配套 clipname 弹药同档在售；可学技能 14 项全在 skills.xml、与 35 项史实满级零交集、无驾驶；本线旧"N档"片段未登记，不重复注册 |
| C7 金币闭包 | pass | 章节金币拾取与 balance-input `goldPlans.beforeFinalMerchant` 逐图一致（A11/A16/A20/A22=0 无拾取）；合计 910000 + 起始 30000 = **94 万名义预算**；economy.fragment 旧"无金币"文本（goldIncomeGap）非最终状态，已按主控采用口径核对 |
| C8 自选奖励闭包 | pass | cf6.sting.t1–t5 在 choice-rewards.generated.json 合并投影（11 pools/83 bundles）；5 个配给包在 消耗品_自选配给.xml，use=礼包、rewardPack mode=playerChoice 且 poolId 与 economy.choices 行一致；kCost=0 全满足；枪捆武器真实、等级≤池顶、附配套弹药；技能捆（小跳/拳脚攻击/升龙拳/聚气/霸体）均非满级；choiceCheckpoints.afterMap 与 choices.mapId 一致 |
| C9 兵种身份（详下节） | pass-with-caveats | 1 warning：alien→460 为 candidate_reuse |
| C10 有限波次 vs encounter-review | pass | 全部硬指令满足（见下节）；2 info 为精英载体名额替换 |

## C10 数量口径核对（死亡预算/并发上限/初始数 → 有限波次）

原作语义以 encounter-review.json 为准：`僵尸型敌人总个数`=remainingDeathBudget（仅最终死亡-1，
出兵不减、补位不裁），`上场个数`=并发上限，摆放=初始数；不要求复制无限刷新。逐图核对结果：

- A01=461×20，波构成 [2,5,5,5,3]（2 初始+四组有限增援），与 review `minimalCandidateStageWaves`
  一致；不宣称原版固定 20（适配值）。
- A02=9 / A03=10 / A04=24 / A05=7 / A08=0 / A10=461+469（无额外 460）/ A11=462×1 /
  A12=15 / A13=467×1 / A15=460×5（=5 卵）/ A16=0（过渡图，路线 A16→A17 顺序正确）/
  A18=12 / A19=19：与 review finiteAllClearCandidate 完全一致。
- Boss 图采用 Boss 优先出口（review bossPriorityPreferred）：A06 支援 35（466×30=原两路各15上限
  +461×3+468×2）；A17 支援 40（含 5 卵位 460、变身 469 不重复计后继）；A20 支援 40；A22 支援 60。
- info×2：A09 建议 467×6 → 装配 467×5+466×1（E1 载体占 1 个持盾名额）；A14 建议 467×2 →
  467×1+466×1（E3 载体）。两图总数不变（9）；review 建议 status=proposal_not_implemented，
  精英配额分配见 economy.fragment eliteQuotas，属已记录偏差，建议主控集成记录注明即可。

## C9 zombie_turret→461 / alien→460 身份证据

**zombie_turret（aw-僵尸-可被炮台打，原作 charId 630）→ 兵种461：成立，带一条适配限制。**
- 原作证据（deobfuscated-export/scripts，SWF sha256=b52af10e…9b01）：
  `DefineSprite_630_aw-僵尸-可被炮台打` 与 `DefineSprite_477_aw-僵尸` 帧结构/脚本同构；
  frame_77 尸体剪辑 load 脚本逐行一致（`_root.电梯死亡敌人计数++`、产生源场上人数/总个数--、
  jiangshideadsound）；630 唯一差异=额外 `子弹区域击中检测`（检测 `_root.gameworld.子弹区域`，
  即炮台子弹通道），477 树内无此检测。encounter-review A01 statics：477/630 同 hp200/AI5/攻击20。
- CF7 证据：units.json 461=`敌人-CF6普通男僵尸`（CF6黄衣僵尸）；enemy_properties
  `CF6重制敌人.xml` 注明继承原版黄衣僵尸；asset_source_map linkage=
  `Antigravity/CF6普通男僵尸/敌人-CF6普通男僵尸`，SWF 存在（sha256=8166bc4a…98da）。
- 适配限制：本章节 0 处炮台（全章无"炮台"字段），630 的炮台受击通道在 CF7 侧未单独注册
  （encounter-review.turretVariant 已记为适配）；映射 461 仅保留外观/行为/死亡计数语义。
  若后续装配炮台机制，需另核该通道。

**alien（aw-异形，原作 charId 353）→ 兵种460：candidate_reuse，不能宣布等价。**（warning）
- 原作证据：`DefineSprite_353_aw-异形` 为近战爬行体（enterFrame 仅响应 man1 近战/抓投，
  无子弹区域检测），frame_77 尸体 load 同样记 `电梯死亡敌人计数++`、播"异形死"音效；
  卵（sprite 1939 frame24）attachMovie 单只 hp200；A22 自由生成器 hp250/预算15/并发1。
- CF7 证据：units.json 460=`敌人-完全体克隆兽`/暴君克隆兽（身高230，独立敌性面板
  γ-ECHO克隆兽.xml）；linkage=`Codex/γECHO克隆兽/完全体/敌人-完全体克隆兽`，
  Codex专用素材.swf 存在（sha256=b50a502e…d851）。与原作异形**不同源**：外观、体型、
  行为包均不同。
- 已批准用途边界：`tools/cf6-guard-assets/GuardTransform.as` 仅批准 469 变身后继复用 460
  （"先死亡后生成"、属性全按暴君模板重初始化）。本章节 460 直用=A15×5（卵位）+A17×5+A22×15，
  全部落在 encounter-review 标 `candidate_reuse` 的图上；review 原文："direct egg/add use
  needs explicit integration choice"。
- 最小修复建议（不替主控写文件）：主控在集成记录中显式采纳 460 直用（candidate_reuse→adopted），
  或退回专用异形资产；内容侧无需改动。

## 遗留（非本线范围，沿用前轮记录）

- 背景 SWF 缺 13 张（地图线；矢量仍装配中）。
- alien→460 candidate_reuse 待主控显式采纳（上节 warning）。
- Boss 枪 `Parameters.长枪=G36` 的消费待实机核（r2 起已标）。
- 本章结论为内容审查（compiled/candidate 级证据边界），不构成实机/标准入口复验。

## 产物

- `tools/cf6-roguelike-content/integration-audit/audit-sting-r5.py`（可复跑只读审查器）
- `tools/cf6-roguelike-content/integration-audit/audit-r5.json`（机器 JSON：全输入首尾 SHA、
  C0–C10 明细、findings）
- 同内容副本：`tmp/cf6-roguelike-20261021/kimi-content/r5/audit-r5.json` 与本报告。
