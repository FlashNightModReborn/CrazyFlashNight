# 书中历险关卡配置

`repair-campus.json` 是《修理大学》重制关卡的人工编辑源，归入《闪客快打》第1章；`id=repair-campus` 保持局次和既有记录兼容。关卡、波次、掉落、经济、技能与奖励在这里维护。

1. 编辑源 JSON。`maps` 按关卡顺序排列；自选池定义继续维护在 `data/rewards/choice-rewards.json`。
2. 在仓库根运行 `python tools/build-book-definition.py`，再运行 `python tools/build-book-definition.py --check`。生成器检查真实物品、技能、敌人、插件与配套弹药，并输出本目录的 `repair-campus.runtime.json`、兼容配给物品/配方及测试用 AS2 基线。
3. 重启开发入口并从书架新开一局。已安装本轮加载器后，现有配置字段的修改不需要再次编译 SWF；程序、schema 或自选池自己的 AS2 定义变化仍需要对应编译。

运行时先读取 `repair-campus.runtime.json` 并校验结构。加载失败时“进入书中”会给出配置错误，不先创建临时角色；普通阅读、角色返回和已发生的结算恢复仍可使用。加载后的配置在当前进程固定，局内计划不热替换。

每张地图可维护 `dialogue` 数组，单段最多 32 句，每句只有 `speaker`（最多 40 字符）和 `text`（1–160 字符）。标题先展示，随后点击或按当前互动键逐句继续，也可点击“跳过本段”。空数组保留约 4.2 秒的自动章节卡。现有七段留空，等待核对《闪客快打1》的原作文本；未用新写台词冒充原作。用时按整局经过的时间计算，包含暂停、商店与过场。

| 配置 | 当前用途 |
| --- | --- |
| `skills` | 盔甲君可教的11项基础技能；功能技能由卡片直接授予指定等级 |
| `buildChoices` / `minorChoices` | 第二、四图的大配给，以及第一、三、五、六图的小配给；`afterMap` 从0开始 |
| `kBudget` | 前六图末波各200＋0–100 K点；金币不再随机转K点，普通世界规则不变 |
| `optionalLoot` | 第三至六图可选武器和材料按原概率的75%投放；基础防具、恢复、弹药、经验和SP保留 |
| `recordSp` / `regularSp` | 首通或严格刷新个人最佳45 SP，其余成功通关5 SP；旧分钟档字段仅保留记录兼容 |

地图可选维护 `wavePlan`：`baseTotal` 是本地图基础兵种总数区间，生成时按 `waves` 分摊到每一波；前三波从 `addTypes` 按 `addCount` 追加 2–3 个混编单位，末波改为 `eliteTypes` 全套精英，精英等级由 `eliteLevel` 指定。配置 `wavePlan` 时 `count` 仅保留兼容，实际基础兵种总数读 `baseTotal`。`carBombType` 指定会携带一辆自爆汽车的兵种，每波至多一辆。未配置 `wavePlan` 的地图继续使用 `enemies` 池逐只混编与 `count` 区间；`enemyWeights` 可给同一 `enemies` 池设置整数权重，展开后仍按逐只轮转，不新增兵种。`enemyPower` 与 `enemies` 同序，1–10 表示相对战力：波次越早越偏向低战力，非末波排除最高战力，末波放开；同时每波数量按图内进度从 `count` 下限递增到上限。`wavePlan` 地图的学生总数分摊和追加单位也偏向后几波。

卡片价格、指定技能等级和完整武器套装维护在奖励目录。短枪构筑指定 `weaponCount:2`，插件按两把配齐，弹药数量为整套总额。付费卡只扣临时角色K点，原版章节没有SP奖励。

修改后至少运行 `tools/test-book-definition.py`、`tools/test-choice-rewards.py` 以及相关生成器的 `--check`。这些检查不代替新局实机体验。
