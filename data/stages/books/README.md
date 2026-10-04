# 书中历险关卡配置

`repair-campus.json` 是《修理大学》的人工编辑源。关卡、波次、掉落、经济、技能与奖励字段沿用原有配置，本轮迁移没有改变数值。

1. 编辑源 JSON。`maps` 按关卡顺序排列；自选池定义继续维护在 `data/rewards/choice-rewards.json`。
2. 在仓库根运行 `python tools/build-book-definition.py`，再运行 `python tools/build-book-definition.py --check`。生成器检查真实物品、技能、敌人、插件与配套弹药，并输出本目录的 `repair-campus.runtime.json`、兼容配给物品/配方及测试用 AS2 基线。
3. 重启开发入口并从书架新开一局。已安装本轮加载器后，现有配置字段的修改不需要再次编译 SWF；程序、schema 或自选池自己的 AS2 定义变化仍需要对应编译。

运行时先读取 `repair-campus.runtime.json` 并校验结构。加载失败时“进入书中”会给出配置错误，不先创建临时角色；普通阅读、角色返回和已发生的结算恢复仍可使用。加载后的配置在当前进程固定，局内计划不热替换。

每张地图可维护 `dialogue` 数组，单段最多 32 句，每句只有 `speaker`（最多 40 字符）和 `text`（1–160 字符）。标题先展示，随后点击或按当前互动键逐句继续，也可点击“跳过本段”。空数组保留约 4.2 秒的自动章节卡。现有七段留空，等待核对《闪客快打1》的原作文本；未用新写台词冒充原作。计时和奖励口径本轮保持原样，正式加入较长对白前需与玩法合作者一起确认是否扣除演出耗时。

修改后至少运行 `tools/test-book-definition.py`、`tools/test-choice-rewards.py` 以及相关生成器的 `--check`。这些检查不代替新局实机体验。
