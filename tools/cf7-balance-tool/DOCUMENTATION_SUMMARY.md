# CF7 数值平衡工具 — 文档完善总结

> 本次会话对 `tools/cf7-balance-tool` 进行了全面调研、审计和文档完善。

---

## 一、已完成的工作

### 1.1 现有文档审计

对以下文档进行了全面验证：

| 文档 | 审计结果 | 质量评级 |
|------|----------|----------|
| CF7-BalanceTool-DevSpec-v3.md | 核心准确，4处minor修正 | A- |
| CF7-BalanceTool-Investigation-Report.md | 调研完整，结论可靠 | A |

### 1.2 新增文档

| 文档 | 用途 | 字数 |
|------|------|------|
| CF7-BalanceTool-DocAudit-v1.md | 审计报告，含修正清单 | ~14KB |
| docs/field-reference.md | 70个字段完整参考 | ~15KB |
| docs/design-decisions.md | 关键决策记录(ADR) | ~7KB |
| README.md | 项目入口文档 | ~6KB |

### 1.3 验证的关键数据点

- **XML文件统计**: 77个items文件 + 12个enemy_properties文件，与文档一致
- **字段映射**: Excel列名->XML字段名->AS2属性名，链路清晰
- **伤害公式**: 验证与AS2源码(DamageCalculator.as等)一致
- **多阶数据**: 确认仅3个文件有data_2/3/4，枪械无多阶

---

## 二、发现的问题 (全部Minor)

### 2.1 需立即修正 (Before Implementation)

| # | 问题 | 位置 | 修正建议 |
|---|------|------|----------|
| M1 | enemy_properties计数11->12 | DevSpec §1.1 | 注明"11数据+list.xml" |
| M2 | 怪物魔抗属性列表不完整 | Investigation §3.5 | 更新为14个完整属性 |
| M3 | 公式体系说明缺失 | DevSpec §2.3.5 | 添加双轨公式注释 |
| M4 | bullets_cases结构缺失 | DevSpec §1.1 | 添加结构说明 |

### 2.2 需用户确认的设计决策

| # | 问题 | 选项 | 建议 |
|---|------|------|------|
| Q1 | 公式引擎输出范围 | A:仅参考值 / B:含推荐价格 | 建议B |
| Q2 | 撤销/重做支持 | A:P5 / B:P6 / C:Git代替 | 建议C |
| Q3 | 怪物属性时机 | A:P3 / B:延后 | 建议B |
| Q4 | 版本控制策略 | A:独立文件 / B:Git / C:结合 | 建议C |

---

## 三、关键设计取向确认

### 3.1 已确认 (文档正确)

- ✅ XML是单一数据源
- ✅ 公式引擎输出只读参考值
- ✅ 分层XML解析器架构
- ✅ Electron独立桌面应用
- ✅ 插件系统P1纳入，怪物P3延后

### 3.2 新发现 (需明确)

- ⚠️ **双轨公式体系**: Excel精细公式 + Workflow快速估算
- ⚠️ **插件计算深度**: 单插件(P1) -> 多插件(P2) -> 射线建模(P3)
- ⚠️ **校准标准**: 枪械>95%，防具>90%，经济>85%

---

## 四、数值计算链路验证

### 4.1 武器DPS计算链路

```
Excel输入列 (14列)
  ├── 具体武器, 限制等级, 子弹威力, 射击间隔, 弹容量, 弹夹价格, 重量
  ├── 双枪系数, 穿刺系数, 伤害类型系数, 霰弹值, 冲击力, 额外加权层数
  └── 中间计算 -> 25个输出列 (平均dps/加权dps/平衡dps/...)

AS2运行时
  XML (power/interval/capacity/split) -> DamageCalculator
    -> 基础伤害 = 子弹威力 + 伤害加成
    -> 波动 = 0.85~1.15随机
    -> 物理减伤 = 300/(防御+300)
```

### 4.2 防具评分链路

```
Excel加权总分模型
  当前总分 = 防御 + HP*w_hp + MP*w_mp + ...
  加权总分 = 平衡总分 × 加权系数
  法抗上限 = f(限制等级)

AS2运行时
  XML (defence/hp/mp/...) -> 属性加成 -> 实际防御/HP
```

### 4.3 插件加成链路

```
最终威力 = base × (delta + pct/100) × (1 + mult/100) × dtype_mult
delta = 1 + 0.01 × (强化等级-1) × (强化等级+4)

常用delta值: Lv5=1.36, Lv7=1.66, Lv9=2.04, Lv13=3.04
```

---

## 五、实施建议调整

### 5.1 Phase 0 补充

新增任务：
- **字段完整扫描报告**: 统计所有字段出现频率、极值、分布
- **公式依赖分析**: 输出公式计算DAG图，确定实现顺序

### 5.2 Phase 1 边界情况

需测试的边界文件：
- `武器_刀_重斩.xml` (唯一有data_2/3/4的武器)
- `防具_20-39级.xml` (多阶魔法抗性)
- `消耗品_弹夹.xml` (纯配置，无effects)
- `equipment_mods/特殊材料_通用.xml` (特殊结构)

### 5.3 Phase 2 校准策略

| 模块 | 目标 | 偏差处理 |
|------|------|----------|
| 枪械DPS | >95% | <0.1%强制修复 |
| 防具总分 | >90% | <1%强制修复 |
| 经济定价 | >85% | <5%记录偏差 |

偏差处理流程：标记->检查->CALIBRATION_TODO->继续推进

---

## 六、配套资源确认

### 6.1 已就位

| 资源 | 位置 | 状态 |
|------|------|------|
| baseline-extracted.json | baseline/ | ✅ 9 section完整 |
| 原始Excel | baseline/ | ✅ 可用 |
| 插件数值设计 | data/items/插件数值设计讨论.md | ✅ 37行 |
| 射线数值建模 | data/items/equipment_mods/ | ✅ 495行 |
| 武器加权工作流 | data/items/weapon_weighting_workflow.md | ✅ 226行 |

### 6.2 需确认

- [ ] Excel公式是否有更新版本？
- [ ] 是否有未纳入的数值设计文档？
- [ ] 武器分类标注是否完整？

---

## 七、下一步行动清单

### 用户侧 (需决策)

- [ ] 确认Q1-Q4设计决策
- [ ] 确认是否立即修正4处minor问题
- [ ] 确认Phase 0开始时间

### 开发侧 (准备就绪)

- [ ] 初始化monorepo骨架 (pnpm workspace)
- [ ] 配置TS strict + Vitest
- [ ] 实施字段扫描报告
- [ ] 建立Zod schema骨架

---

## 八、信心评估

| 阶段 | 信心度 | 主要风险 |
|------|--------|----------|
| P0 骨架 | 95% | 无 |
| P1 XML层 | 90% | fast-xml-parser保格式 |
| P2 枪械公式 | 85% | Excel公式链复杂 |
| P3 其余公式 | 80% | 依赖P2 |
| P4 CLI | 90% | 无 |
| P5 GUI | 85% | Electron打包 |

**总体评估**: 文档准备充分，可以进入实施阶段。

---

## 九、文档结构总览

```
tools/cf7-balance-tool/
├── README.md                              [入口文档 - 新增]
├── CF7-BalanceTool-DevSpec-v3.md          [主规格书 - 已审计]
├── CF7-BalanceTool-Investigation-Report.md [调研报告 - 已审计]
├── CF7-BalanceTool-DocAudit-v1.md         [审计报告 - 新增]
├── DOCUMENTATION_SUMMARY.md               [本文件 - 新增]
├── baseline/
│   ├── baseline-extracted.json            [校准基准 - 已就位]
│   └── 武器-技能数值-价格-合成表.xlsx      [原始Excel - 已就位]
└── docs/
    ├── field-reference.md                 [字段参考 - 新增]
    └── design-decisions.md                [决策记录 - 新增]
```

---

## 十、联系与反馈

如发现文档问题或有疑问，请查阅：
- 审计详情: [CF7-BalanceTool-DocAudit-v1.md](./CF7-BalanceTool-DocAudit-v1.md)
- 字段详情: [docs/field-reference.md](./docs/field-reference.md)
- 决策背景: [docs/design-decisions.md](./docs/design-decisions.md)

---

*总结生成时间: 2026-03-06*
*文档状态: 就绪待开发*
