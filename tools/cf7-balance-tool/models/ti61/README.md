# 钛合金61套装原型模型

血浪试测版：`python -X utf8 -B tools/cf7-balance-tool/models/ti61/accepted.py --test`包含4项约束；输出的`bloodWave`从实际战技XFL读取两次刀口发射与7波联弹，不把霰弹数视为击溃次数。0.09%击溃、9%斩杀及每段固有负担倍率共读胸甲生产参数；输出只证明静态预算，玩家收益与性能仍待实测。当前施工/验收见[钛合金反馈调整](../../../../docs/钛合金61反馈调整-施工与验收-2026-09-10.md)。

工具本身只做离线计算，不写物品、存档、AS2或SWF；已接入的本地S1/S2运行原型与模型共读当前生产参数。业务定位和结论见[建模记录](../../../../docs/钛合金61式套装-原型建模-2026-09-08.md)，玩法状态机仍以[套装ADR](../../../../docs/钛合金61式装甲套装-玩法设计-ADR-2026-07-27.md)为准。

在仓库根使用 Python 3 标准库：

```powershell
chcp.com 65001 | Out-Null
python -X utf8 -B tools/cf7-balance-tool/models/ti61/test_model.py
python -X utf8 -B tools/cf7-balance-tool/models/ti61/model.py
python -X utf8 -B tools/cf7-balance-tool/models/ti61/model.py --check
```

默认输出 `tmp/ti61-model/report.md` 与 `report.json`，可以用 `--out <目录>` 指定。`--check` 重新计算并比对已有输出，任何输入、源摘要或模型输出漂移均失败，不写文件。

- `parameters.json`：强度目标、历史候选、玩家策略、压力脚本和指定配装。第三组保留原标识，由`runtimeProfile`指向；当前数值从胸甲与钛合金P90的XML初始化参数导入，不维护副本。在线固定盾强、满血免费初始盾、全状态治疗、基础C循环与额外G发电采用已确认语义。免费初始量和付费修复量分账，重初始化前残血不能借降低HP上限获得免费盾。
- `model.py`：逐件装备展开、强化、躲闪档位、护盾/HP/MP/弹药守恒与171逐发伤害。
- `reference.py`：所选插件的有限投影、合法槽位、剑圣指定配装与腕刃吸血；不是另一套通用装备计算器。新增未支持运算符应报错并复核现役核心。
- `test_model.py`：模型契约回归；不证明AS2、XFL发布产物或玩家体验。

注意现役普通百分比与强化倍率相加，负HP也参与强化；30级以上装备默认1槽，剑圣四阶显式3槽。扩槽件占槽且加重量，不能免费给其他套装三槽。刀与手甲吸血按槽位分开。

报告的无插件控制组和指定配装组不能混用；指定配装中钛合金遵守当前槽位，因此不复制剑圣全五件的三插件。171按鱼骨/水冷/扩容、双P90各枪盾完整装配；扩容增量上限、武器子类、条件tag、逐槽命中代价和韧性分别保留。压力脚本是已命中的减伤后伤害，不是敌人AI或生存概率模型。无缺失量时不加免费资源；武器切换只是模拟玩家策略，不代表新增自动切枪。

源端XFL只提取候选发射事件，`load`事件不按关键帧持续长度重复计数；模型不把发射数量等同实际接触次数。剑圣腕刃裸普攻输出不是其完整空手流派天花板，不能推翻维护者的实战强度锚点。

## 2026-09-10：JK、血剑与171副射推演

后续已进入本地实现。最新确认参数入口为 `python -X utf8 -B tools/cf7-balance-tool/models/ti61/accepted.py --test` 和 `python -X utf8 -B tools/cf7-balance-tool/models/ti61/accepted.py`，输出 `tmp/ti61-implementation/model.json`。它直接读取当前XML，采用枪械项链、60发171、1.5血剑盾系数、1MP换2盾、17发/1秒/75%且放大击溃的副射，核对当前HP献血的结算；`bonusSecondsAfterSlam`表示增益从砸地帧开始计时。下述 `jk_followup_parameters.json` 和大盾扫描保留早期候选，不再代表当前施工参数。详见[施工验收记录](../../../../docs/钛合金61反馈调整-施工与验收-2026-09-10.md)。

[本轮结论与待确认参数](../../../../docs/钛合金61与171-JK反馈后数值推演-2026-09-10.md)。这是新的候选扫描，不改变上面的历史配装或生产 XML。按维护者最新意见，171 使用鱼骨/水冷、**60 发且不扩容**；主样本统一 60 级。使用 Python 标准库和现有 Node，不安装依赖。

```powershell
chcp.com 65001 | Out-Null
python -X utf8 -B tools/cf7-balance-tool/models/ti61/jk_followup.py --refresh-sources
python -X utf8 -B tools/cf7-balance-tool/models/ti61/test_jk_followup.py
node tools/cf7-balance-tool/models/ti61/test_jk_sampler.js tmp/ti61-jk-20260910/source.json
python -X utf8 -B tools/cf7-balance-tool/models/ti61/jk_followup.py --check
```

默认输出 `tmp/ti61-jk-20260910/{source,attacks,report}.json` 和 `report.md`；`--out` 可更换目录。首次需要 `--refresh-sources`：读取 FLA、校验 ZIP 成员 CRC，并按当前配装防御重新投影帧脚本。之后直接运行复算参数；FLA 身份、防御或输入发生变化会拒绝沿用旧投影。`--check` 只比对，不刷新输入或写产物。

- `jk_source.py`：只读提取 JK FLA。兼容该 FLA 中央目录不可直接读取的情况；不解包到生产素材目录。
- `jk_script_sampler.js`：在 Node 中有限投影源帧脚本的算术、随机分支与发射事件，保留同关键帧子实例，另外计算回跳重建敏感性。不是 AVM1、显示列表或碰撞仿真。
- `jk_followup_parameters.json`：盾转换、接触假设、血剑战技、主副射和换弹策略的候选输入。包含源码明确数值与标明的设计假设，不是生产参数表。
- `jk_followup.py`：复用现有装备/插件展开，输出招式包络、完整两招、HP/MP 守恒、反制敏感性、弹量/换弹/到达时差、过载与外部药剂场景。
- `test_jk_followup.py` / `test_jk_sampler.js`：离线契约验证。包含真伤门、斩杀先于扣盾、低强化机会成本、技能无效调用、F 不补主仓、换弹不刷副射间隔及既有 M134 控制。

新导出的发布 SWF 只对端点和四组关键伤害帧做了抽查，不代表 FLA/SWF 全语义一致。复查可使用仓库 `tools/ffdec/ffdec.bat -export script <临时目录> flashswf/arts/new/武装JK.swf`。无真实命中录像时，任何条件 DPS、两招结果和反制种子分位数都不能标记为实测或通关概率。
