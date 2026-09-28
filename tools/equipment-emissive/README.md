# 装备自发光配置检查

运行时唯一配置为已注册物品 XML 的独立 `装备自发光初始化` lifecycle；动态兵器配套 `装备自发光周期`，静态防具只在穿戴/卸载时注册和注销。本工具不生成数据、不修改数值或素材。

```powershell
python -X utf8 tools/equipment-emissive/validate.py
python -X utf8 -m unittest discover -s tools/equipment-emissive -p test_validate.py
powershell -File scripts/run-equipment-emissive-tests.ps1
powershell -File scripts/run-equipment-emissive-asset-tests.ps1
```

检查分组/槽位、有限数值、独立生命周期及状态适配器对应的原初始化函数。类测试覆盖贡献归并、稳定身份、预算、条件状态和刀光包络；素材测试使用真实 XML、生产生命周期装载器、已发布 SWF 和原初始化函数，在隔离演员上验证接线。它们不操作玩家存档，不代替完整游戏观感和性能验收。

配置检查还要求 AS2 的组合峰值与 `local_lights.v1.json` 中普通“枪火”强度一致。身体与近色兵器合并后受同一峰值约束；异色源以点光衰减公式的上界控制重叠亮度，刀光脉冲包含在限额内。参数说明归[装备函数合同](../../scripts/逻辑/装备函数/README.md#skill-interaction)。

`scripts/run-equipment-lighting-tooltip-tests.ps1` 验证自动照明注释、真实来源条件、插件合成后的说明、内置灯不获得插件防御加成，以及共享原生文档；素材 suite 另从真实装备/插件 XML 验证生成结果。注释在悬停生成阶段构建，不加入战斗逐帧路径。

素材 suite 输出蓝晶全套、近色兵器组合、血剑组合三条真实 AS2 快照。可送入已有 GPU 夹具作普通枪火亮度对照：

```powershell
python -X utf8 tools/equipment-emissive/export-wires.py scripts/flashlog.txt tmp/equipment-light-visibility/gpu/equipment-lighting-wires.json
```

应紧接成功的素材 runner 执行，或使用该轮已保存的 `flashlog.txt`；随后按 [GPU 夹具](../../launcher/perf/combat-fx/README.md) 运行，将同一目录作为输出目录。导出器只接受完整成功的单个 run，不替代生产者的新鲜编译证明。

类测试另覆盖合并参数/径向记录缓存失效、同帧物品和插件替换、内置/插件来源交接、刀光并入后恢复，以及镜头和嵌套角色坐标。`PayloadBenchmark` 给出 120 次快照的均值及 P95（1 ms 墙钟粒度），包括 20 角色的 20/100 项静态贡献、1/5/20 角色移动中的全套贡献，以及 20 角色同时持用异色兵器的 120 来源/40 候选压力场景；实际仍最多 16 灯。只计 `payload()`，不含夹具移动、完整战斗、动态武器采样或 GPU 时间。`PayloadProfile` 是另一次固定姿态调用的分段样本，不与移动样本混算；优化后 `validation` 含静态来源收集，`collection` 只含动态来源路径。计时开关默认关闭，不把有调度噪声的毫秒阈值设成功能测试硬门。

参数与所有权见[装备函数合同](../../scripts/逻辑/装备函数/README.md#skill-interaction)；初筛线索与未纳入项见[扩展调查](../../docs/reports/equipment-emissive-expansion-audit-2026-09-28.md)。
