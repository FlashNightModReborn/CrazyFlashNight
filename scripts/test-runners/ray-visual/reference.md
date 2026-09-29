# 原版射线对照板

`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-ray-reference.ps1`

此 focused runner 只临时替换 TestLoader，走仓库已有 scratch/编译锁/恢复合同。
它读生产 `data/items/bullets_cases.xml`，经 `TeslaRayConfig.fromXML` 合并真实 preset，调用原始 AS2 renderer。
不启动游戏、不载入存档、不修改生产 AS2、XFL 或配置。真正执行和 Compiler 0/0 证据由统一 CS6 编译提供。

- `[RAY_GPU_SCENE] <id>` 与 `[RAY_GPU_WIRE] <payload>`：每个场景独立 fresh c/l/s + 时钟，来自生产桥原样输出。
- `[RAY_REFERENCE_CASE] <JSON>`：实际 bullet/style/age/phaseAge/start/end/length/width/LOD 与总览位置。
- `[RAY_REFERENCE_XML]` / `[RAY_REFERENCE_CONFIG]`：XML 显式字段和解析后的配置；runner stdout 记录 XML SHA256。
- `[RAY_REFERENCE_ORIGINAL]`：原画法实际 drawAge、alpha、固定表现 RNG seed 与几何 bounds。
- `[RAY_REFERENCE_VIEWPORT]` / `[RAY_REFERENCE_VIEW]`：舞台尺寸、缩放及当前页。

场景名和键位：

| 场景 | 实际子弹 | 原长度 | 年龄 | 按键 |
|---|---|---:|---:|---|
| bagua_age0 / bagua_age4 / bagua_age8 / bagua_fade11 | 镇暴射线 | 300 | 0 / 4 / 8 / 11 | 1 / 2 / 3 / 4 |
| tesla_age0 / tesla_age2 | 磁暴射线-强化 | 900 | 0 / 2 | 5 / 6 |
| resonance_age0 / resonance_age2 | 谐振波射线-强化 | 900 | 0 / 2 | 7 / 8 |
| tesla_basic_age2 | 磁暴射线 | 700 | 2 | 9 |
| flame_field | 喷火束 | 620 | 存活 1 / 相位 12 | F |
| thermal_field | 热能射线 | 800 | 2 | T |
| thermal_enhanced_field | 热能射线-强化 | 1200 | 2 | H |
| prism_field | 光棱射线-强化 | 900 | 2 | P |

全场景 wire 起点 `(60,288)`，横向终点 `60 + XML rayLength`。命中标记关闭，单看束体；照明使用独立车库夹具。
图板保留在 TestLoader，按 `0` 回到总览，按钮或相应按键查看独立场景。纯黑底，逻辑尺寸 1024×576。
TestLoader 原 XFL 为 500×500，此测试不修改它；按 Stage 实际尺寸等比适配，可放大 TestMovie 窗口后截图。
总览 Bagua 缩至 65%，其余五行主样例束体保留原尺度；独立视图只有 1200px 热能束按 75% 适配，wire 长度保持 1200。
对比原生黑底截图时使用 metadata 的位置/比例，排除标题按钮区域，不能把缩略图线宽直接当游戏像素宽。

生命周期边界：首帧 age0 不加 manager flicker；正常更新按原 renderer 重绘；进入淡出后保留最后 hold 帧几何，只改 MC alpha。
所以八门 age11 是 age9 绘制结果（burstFrame8）×50% alpha，不是再调用 renderer(age11) 得到双重淡出。
喷火使用实际 620/14 配置，持续 12 个显示刷新/flush，比较已达到给定长度的束体；不模拟伤害、长度增长或实体战斗。
表现 RNG 在夹具内固定并恢复；Math.random 探针确认参考绘制和原生桥未消费战斗随机数。
Tesla 的原 LCG 折线与 native hash 折线不是同一采样序列，比较几何结构、层次和颜色，不能要求逐像素 hash 相同。

运行完成和非空 bounds 只证明原 renderer 执行、元数据与 wire 生成，不替代实际截图审查和人类美术验收。