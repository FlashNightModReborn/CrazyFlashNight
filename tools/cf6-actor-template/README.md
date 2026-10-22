# CF6 史实 Andy 初始模板

`actor.fragment.json` 是可汇入章节源的 `actor` 片段。它不修改主章节、库存、真实存档或全局物品属性。`selection.json` 固定已核对的取样身份和本期产品选择；`source-audit.json` 保存来源摘要、技能组成、装备引用与未验证边界。

```powershell
python -X utf8 tools/cf6-actor-template/build.py
python -X utf8 tools/cf6-actor-template/build.py --check
python -X utf8 tools/cf6-actor-template/test_template.py
```

来源为 `data/units/units.json` 的 NPC `213 / Andy`，敌对镜像 `275` 的数据配装一致：男、185 身高、60 级。累计经验按现役公式为 157,526,193。六防具为 Andy 领子／上装／下装／手套的 NPC 版本、黑色板鞋、东区最强战士项链，逐槽 11 强化；原刀由已批准的镜之虎彻替换。

NPC 原长枪“黄金QBZ的Andy版”要求 70 级，不能直接继承为 60 级玩家的合法初装。本期按主控明确选择使用 **M4A1战术版、11 强化**；这是首版候选，不下调 NPC 原枪等级，也不改其全局属性。演员模板已经装备此枪，开局配给不得再免费发第二把。`initial-supply-requirements.json` 把主枪的“突击步枪通用弹药”和副武器的“榴弹弹药”交给章节经济线决定数量；工具不会猜补给数量。副武器字段原样取自 XML，其 onLoadGroup/onReloadCommit、每组消耗及初始装填值是来源事实，不代表已经实机验证。

技能取样固定为 **名字 Andy、60 级、原 NPC 有枪有刀、无显式技能覆写**。工具按当前 AS2 装备桶的等级／源顺序和 LCG 抽样重算 15 项 NPC 自用技能，与 `npc_skills.json` 中 `Andy Law` 的 24 项授技去重，得到 35 项。每项玩家初始等级取 `skills.xml` 的 `MaxLevel`，不是统一填 10。教师技能满级等价 9,900 SP，并集 12,310 SP；不生成对应可花费 SP。技能名和等级写成固定列表，运行时不再按显示名随机生成。

该重算是有来源约束的 Python 参考模型，不冒充真实 AVM1 执行。关键 AS2 算法片段摘要钉在 `selection.json`；算法变化时生成器拒绝，需先复核后更新该输入。当前静态检查验证片段满足真实 `build-book-definition.py` 的 CF6 消费合同，包括空发型与 TUTORIAL 大写编号；角色初始化和装备渲染仍由主控实机链验证。

保留的附属条件：

- NPC 头部物品声明 `helmet=true`，现役 DressupInitializer 会隐藏头发。模板显式空发型；没有虚构新的外观资源。
- 镜之虎彻保留原 XML 的技能倍率与消耗 MP 的生命周期，不将其附属能力改写成免费常驻属性。
- 玩家能量盾仍需能量电池；NPC 的免材料规则不复制。
- 主动技能不自动编造快捷栏，进入现役玩家技能表后沿正常装备操作。
- 四件 Andy NPC 防具及东区最强战士项链没有对应的图标 asset-source-map 登记；实机图标降级显示尚未验证，不能由物品存在推断 UI 图标完整。

教学地图统一使用 `TUTORIAL`；其后保留 A01—A06、A08—A20、A22 编号。初始金币、可花费 SP、弹药数量及后续卡池仍属于主章节／经济源，本工具不占用其写入范围。
