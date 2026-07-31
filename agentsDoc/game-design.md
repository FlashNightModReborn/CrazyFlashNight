# 游戏设计参考

---

## 1. 数值平衡

- **核心公式最高权威**：`0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx`
- **武器 balance 落盘与复现契约**：`tools/cf7-balance-tool/docs/agent-balance-record-design.md`
- **武器平衡业务判据与条款 ID**：`tools/cf7-balance-tool/docs/weapon-balance-rulebook.md`
- **材料统计**：`0.说明文件与教程/材料的单位、关卡统计.xlsx`
- **机制属性记录**：`0.说明文件与教程/武器装备与敌人的机制属性伤害类型魔抗的实装记录.txt`
- **标签与属性**：`0.说明文件与教程/Label与魔法种类与装备属性加成的类型汇总.txt`
- **数据文件**：`data/items/`、`data/units/`
- **武器散射度口径**：`data/items/weapon-diffusion-guidelines.md`

## 2. 机制体系

- **战斗机制**：伤害类型与魔抗体系、Buff/Debuff 计算、子弹与攻击判定（详见 [game-systems.md](game-systems.md)）
- **套装系统**：[套装系统设计与剑圣一期验收](../docs/套装系统-设计与剑圣一期验收-2026-07-14.md)（抗性表项声明 + 定制行为双路由；抗性字段存在会开启对应定向特攻破击，剑圣五件套为第一阶段验收产物）
- **钛合金61式套装玩法**：[钛合金61式装甲套装玩法设计 ADR](../docs/钛合金61式装甲套装-玩法设计-ADR-2026-07-27.md)（五件防具门控；MP驱动护盾/维生/双枪补弹；P90发射发电；M134/P90/血剑机制亲和；高级夜视与应急自动注射边界）
- **武器异质化讨论备忘**：[冲锋枪错位竞争与双枪插件设计备忘](../docs/冲锋枪错位竞争与双枪插件-设计备忘-2026-07-13.md)（换弹负担、冲击曲线、`hitBehavior`、破韧增伤 MetaBuff、普通手枪行为型补弱；两波均已施工，运行态标定待做）
- **好感度系统**：`0.说明文件与教程/好感度系统思路方案.xlsx`

## 3. 世界观与叙事

- **对话数据**：`data/dialogues/`
- **支线规划**：`0.说明文件与教程/支线规划表.xlsx`
- **Wings 桌宠 / Agent 一期方向**：[CF7 Agent Runtime 与 Wings Network 一期范围冻结 ADR](../docs/CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md)（F7 C1 source freeze `dd84230a1d262c6478591cae2d11051b7a8aa7b1` 与其 `candidate_built / NOT_DEPLOYED` 凭据超时结论保留为历史证据。F8 current source `53caabc90941826ddacf626f536b0f473adbf049` 已用纯 Agent Runtime MCP 完成单屏可见人工验收：本轮实测观察 Launcher、玩家 HUD 与经授权打开的帮助 Web 面板；production structured opener 的关闭 allow-list 另含地图、任务、队伍和点唱机，但本轮没有把其余四个面板写成人工目视通过。Flash 游戏画面本身只暴露可见性与窗口元数据，不向 Agent 提供像素、激活或原生输入。该结论为 `e2e_verified / NOT_DEPLOYED`，不表示 Agent 可以代打、控制战斗、读取 Flash 画面、跨物理双屏操作，也不表示已 promotion 或通过正式入口验收。Wings 仍是复用项目中立底座的受限叙事客户端，自由文本永远零执行；桌宠口吻/视觉与最终 Boss 机制尚未冻结，既有剧情真相仍以 worldbuilding 权威路由为准）

## 4. 关卡与环境

- `data/stages/`、`data/environment/`、`0.说明文件与教程/无限过图背景配置教程.pdf`

## 5. 新内容添加

- `0.说明文件与教程/添加新物品和单位的详细基础教程宝宝可用.docx`
- `0.说明文件与教程/1.改动说明（含作弊码）.txt`

---

游戏设计决策和平衡调整应在此文档中记录理由。归档流程见 [self-optimization.md](self-optimization.md)。

