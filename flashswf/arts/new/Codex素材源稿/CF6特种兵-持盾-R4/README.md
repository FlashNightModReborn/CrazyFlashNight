# CF6 特种兵 R4：盾牌 CT 字样纠正

本版从冻结 R3 独立创建，只将盾牌 561 徽记右字由误画的 F 改为 T，并去掉旧 F 中横上的一小块印刷磨损。T 保持原顶横的倾斜透视。C、冠徽、红底、盾体、窗口、角色服装、头盔、手套、武器与其他美术不变。旧 R3 未覆盖。

## 范围

- 实际改变的 SVG：parts/561.svg、variants/575.svg、variants/577.svg、variants/578.svg。
- 共 152 个 SVG；其余 148 个与冻结 R3 逐字节一致。
- 575/577/578 通过原裁切与仿射映射继承 561 的新 CT；共 18 个盾牌碎片 fill。
- 原 timelines.json、viewBox、尺寸、注册坐标、裁切、矩阵、层级均保持不变。
- R3 身体/材质与原占位手枪沿用。本轮没有重绘其他美术。
- CF6 是项目名称；盾牌组织字样为 CT。对照中的 R3 CF 仅标示已纠正的历史错误。

## 本轮检查

- 152 SVG 结构与引用检查；43 个既有重绘/投影件映射检查。
- 561/575/577/578 的实际 SVG 仅含指定两处路径修改；四者 alpha 与 R3 完全一致。
- 窗口真实 alpha=0；18 个碎盾 fill 无缺片、无新增洞、无内部丢失。
- 本轮只抽查 17 个静态姿势：站姿562:1，走563:11，射击564:7，近战573:17，双受击574:6/19，碎盾579:1/3/6/9/10/11，撞车628:1/15/30/45/60。17 帧均非空且无画布切边。
- 559 全帧是上一轮 R3 的历史检查，本轮未重跑，不应写成本轮全量通过。
- 原/R3/R4 盾徽、全盾、三个碎盾及碎盾字样近景；原/R4 持盾整身与 17 个动作对照均已人工实看。
- 独立源包解压后删除生成资产冷重建，152/152 字节一致，见 qa/cold-rebuild-check.json。

## 重建

依赖：Python 3、Pillow、numpy、scipy、Inkscape。

- python source/rebuild.py --assets-only：从包内原始参考重建 152 SVG。
- python source/rebuild.py：重建资产、17 个指定静态姿势、对照图、18 fill 检查及 CT 范围检查。
- python source/cold_rebuild_check.py --archive ../cf6-special-soldier-r4-ct-source.zip：独立解包冷检。
- python source/package.py：生成一个普通独立 ZIP，严格小于 15,000,000 字节。

原 SVG 在 reference/original-svg-bundle.json.gz 中去重保存，restore_reference.py 会验证并恢复。reference/r3-baseline 是四个修改件的冻结基线，用于证明改动范围，不是生产替换件。source 中保留的其他旧 R3 检查工具不属于本轮默认流程。

## 验收边界

这是纯静态矢量与原显示列表装配检查。没有运行 ActionScript、SWF 或 EXE，没有操作 Windows/生产工程，没有进行 CS6 导入或游戏死亡衔接验收。579 的末帧按原列表只保留血烟效果；不代表游戏完整死亡状态已测试。
