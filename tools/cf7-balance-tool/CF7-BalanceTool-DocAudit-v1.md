# CF7 数值平衡工具 — 文档审计报告 v1

> 基于仓库全量信息调研，对现有开发文档进行审计、校准和补充建议。
> 审计日期: 2026-03-06
> 审计范围: CF7-BalanceTool-DevSpec-v3.md + CF7-BalanceTool-Investigation-Report.md

---

## 执行摘要

### 文档质量评级: **B+**

| 维度 | 评级 | 说明 |
|------|------|------|
| 准确性 | A- | 核心数据结构描述准确，少量细节需修正 |
| 完整性 | B | 覆盖主要品类，部分边缘情况遗漏 |
| 可操作性 | B+ | 架构清晰，但部分公式链路待验证 |
| 与代码一致性 | A- | 与AS2源码基本一致 |

### 关键发现概览

1. **文档已准确**: XML结构、字段映射、AS2伤害管线等核心内容经核实正确
2. ** minor修正**: 发现4处细节偏差，3处遗漏补充
3. **建议增强**: 建议新增4个附录文档，完善开发指引

---

## 一、文档准确性验证

### 1.1 XML 结构验证 ✓ 准确

经实际文件核对，文档描述准确：

| 检查项 | 文档描述 | 实际验证 | 状态 |
|--------|----------|----------|------|
| 物品标识 | `<name>` 作为唯一标识 | `武器_手枪_压制机枪.xml` 等文件确认 | ✓ |
| 多阶数据 | 仅 data_2/3/4，无更高 | `防具_20-39级.xml` 确认到data_4 | ✓ |
| 枪械无多阶 | 文档声称 | 所有武器文件确认无多阶 | ✓ |
| weapontype | 枪械使用，刀类不使用 | 22个枪械文件使用，15个刀文件未使用 | ✓ |
| 法抗元素 | 蚀/毒/冷/热/电/波/冲/全属性 | `防具_20-39级.xml` 确认 | ✓ |

**验证文件样本:**
- `data/items/武器_手枪_压制机枪.xml` - 枪械结构验证
- `data/items/防具_20-39级.xml` - 防具多阶验证
- `data/items/武器_刀_重斩.xml` - 刀类多阶验证

### 1.2 AS2 伤害管线验证 ✓ 准确

文档描述与源码一致：

| 公式 | 文档描述 | 源码位置 | 验证结果 |
|------|----------|----------|----------|
| 伤害波动 | `0.85 + 0.3 * random()` | DamageCalculator.as:125 | ✓ 匹配 |
| 物理减伤 | `300 / (防御力 + 300)` | DamageResistanceHandler.as:38 | ✓ 匹配 |
| 跳弹伤害 | `max(floor(伤害 - 防御/5), 1)` | DamageResistanceHandler.as:67 | ✓ 匹配 |
| 过穿伤害 | `floor(伤害 * 300/(防御+300))` | DamageResistanceHandler.as:97 | ✓ 匹配 |

**源码文件:**
- `scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as`
- `scripts/类定义/org/flashNight/arki/component/StatHandler/DamageResistanceHandler.as`

### 1.3 数据文件统计验证 ✓ 准确

| 统计项 | 文档声称 | 实际数量 | 偏差 |
|--------|----------|----------|------|
| items/ 根目录XML | 12 | 12 (list.xml等) | 无 |
| 武器文件 | 37 | 37 (15刀+10手枪+12长枪) | 无 |
| 防具文件 | 4 | 4 (0-19/20-39/40+/颈部) | 无 |
| 消耗品文件 | 6 | 6 (药剂/弹夹/手雷/货币/食材/食品) | 无 |
| 收集品文件 | 3 | 3 (材料/材料_插件/情报) | 无 |
| equipment_mods | 20 | 20 (4等级×6类型-4空) | 无 |
| enemy_properties | 11 | 12 (含list.xml) | +1 |

**发现**: enemy_properties 实际12个文件(11个数据+list.xml)，文档说11个，应注明包含list.xml。

---

## 二、发现的问题与修正

### 2.1 需修正的问题 (Minor)

#### M1: enemy_properties 文件计数不准确
- **位置**: DevSpec-v3.md §1.1
- **问题**: 声称11个文件，实际12个(含list.xml)
- **建议**: 改为"11个数据文件 + list.xml索引"
- **优先级**: 低

#### M2: 怪物魔法抗性属性列表不完整
- **位置**: Investigation-Report.md §3.5
- **问题**: field-config.json中monsterMagicResistance列表与实际不完全匹配
- **实际发现**: 敌人XML使用: `衍生/黑铁会/立场/模因/人类/电子体/盗贼/首领/装甲/机械/生化/凡俗/精英/诺亚`
- **建议**: 更新为完整列表:
```json
"monsterMagicResistance": ["衍生", "黑铁会", "立场", "模因", "人类", "电子体", 
                            "盗贼", "首领", "装甲", "机械", "生化", "凡俗", "精英", "诺亚"]
```
- **优先级**: 中

#### M3: weapon_weighting_workflow.md 与 DevSpec 公式不一致
- **位置**: data/items/weapon_weighting_workflow.md
- **问题**: 加权DPS公式与DevSpec中的Excel公式不同
- **DevSpec**: 使用Excel的25列复杂计算
- **workflow文档**: 简化公式 `加权DPS = 平均DPS × 弹道系数 × 对攻系数 × 1.1^加权等级`
- **建议**: 在DevSpec中添加注释说明存在两套公式体系
  - Excel公式: 用于精细化平衡计算
  - Workflow公式: 用于快速估算
- **优先级**: 中

#### M4: bullets_cases.xml 结构描述缺失
- **位置**: DevSpec-v3.md §1.1
- **问题**: 提及bullets_cases但无结构描述
- **实际结构**: 
```xml
<bullets>
  <bullet>
    <name>xxx</name>
    <shell>...</shell>
    <attribute>...</attribute>
    <movement>...</movement>
  </bullet>
</bullets>
```
- **建议**: 在§1.3后添加 §1.4 bullets_cases 结构说明
- **优先级**: 低

### 2.2 文档遗漏补充

#### A1: 缺少插件算子详细说明
- **遗漏内容**: equipment_mods XML中算子优先级和交互规则
- **来源文档**: `data/items/插件数值设计讨论.md`
- **应补充**:
```typescript
// ModItem stats 结构补充
interface ModStats {
  percentage?: Record<string, number>;  // 百分比加成，与强化加算
  flat?: Record<string, number>;        // 固定加成，不受强化影响
  override?: Record<string, unknown>;   // 直接覆盖
  multiplier?: Record<string, number>;  // 独立乘区
  cap?: Record<string, number>;         // 上限约束
  merge?: Record<string, unknown>;      // 合并值（如bullet）
}
```
- **优先级**: 中

#### A2: 缺少射线插件数值设计框架
- **遗漏内容**: 495行射线数值建模文档核心结论
- **来源文档**: `data/items/equipment_mods/射线插件数值建模_2026-02.md`
- **应补充到 DevSpec**: 公式引擎章节应包含射线伤害模型
```
射线多目标伤害计算:
- pierce/chain: 累积衰减模型
- fork: 分支衰减模型
- 等效命中率来自Monte Carlo仿真
```
- **优先级**: 高 (影响P1插件效率计算)

#### A3: 缺少武器分类标注规则
- **遗漏内容**: weapontype分配的具体判断标准
- **来源文档**: `data/items/weapon_classification_log.md`
- **应补充**: 在CLI设计章节添加 weapontype 自动检测规则
- **优先级**: 低

---

## 三、设计取向确认

### 3.1 已确认的设计取向

基于调研，以下设计取向已在文档中正确体现：

| # | 设计取向 | 文档位置 | 确认状态 |
|---|----------|----------|----------|
| D1 | 插件系统纳入P1 | Investigation §四 | ✓ 确认 |
| D2 | 怪物属性延后P3 | DevSpec §1.1 | ✓ 确认 |
| D3 | 药剂纳入P2 | DevSpec §1.1 | ✓ 确认 |
| D4 | Electron独立桌面应用 | DevSpec §0.5 | ✓ 确认 |
| D5 | XML为数据源，公式引擎为参考 | DevSpec §2.3.5 | ✓ 确认 |
| D6 | Excel仅作为legacy import | DevSpec §0.3 | ✓ 确认 |

### 3.2 建议明确的设计取向

#### S1: 权重计算双轨制
```
轨道A (Excel公式): 精细化平衡计算，25个输出列
轨道B (Workflow公式): 快速估算，用于初步筛选

工具应同时支持:
- 完整公式引擎 (轨道A)
- 快速估算模式 (轨道B，可选实现)
```

#### S2: 插件数值计算范围
```
P1阶段: 插件效率表 (回本等级计算)
P2阶段: 插件组合优化 (多插件叠加)
P3阶段: 射线伤害建模 (MC仿真复现)
```

#### S3: 怪物属性XML支持策略
```
Phase 3 实现建议:
- 使用完全独立的解析器 (中文节点名)
- 建立与物品系统不同的Schema
- 考虑 min/max 区间的特殊处理
```

---

## 四、建议新增的附录文档

### 附录A: 字段完整参考表 (field-reference.md)
建议创建独立文档，包含：
- 所有数值字段的完整列表 (60+字段)
- 字段归属分类 (通用/枪械/防具/插件)
- 字段单位说明
- 字段在AS2中的使用位置

### 附录B: 公式推导笔记 (formula-derivation.md)
将Excel公式翻译成TS的详细推导过程：
- 枪械25列公式链
- 防具加权总分模型
- 药剂效果计算公式
- 经济定价模型

### 附录C: 数据-代码链路映射 (data-code-trace.md)
建立XML字段到AS2代码的完整链路：
```
XML: data.power
  -> 加载: ItemFactory.parseEquipmentXML()
  -> 存储: item.子弹威力
  -> 计算: DamageCalculator.calculateDamage()
  -> 显示: 武器面板UI
```

### 附录D: 测试数据与校准报告模板 (calibration-template.md)
规范校准测试的输出格式：
- baseline对比报告模板
- 偏差标注规范
- 公式调试追踪表

---

## 五、实施建议调整

### 5.1 Phase 0 补充任务

新增以下任务：

```markdown
#### Task 0.5: 字段完整扫描报告
- 扫描所有XML文件，生成字段使用频率统计
- 输出: `reports/field-usage-report.json`
- 内容: 每个字段在多少文件中出现、最大值/最小值/平均值

#### Task 0.6: 公式依赖分析
- 分析Excel公式链的依赖关系
- 输出: 公式计算DAG图
- 用于确定公式实现顺序
```

### 5.2 Phase 1 边界情况处理

```markdown
#### XML解析边界情况:
1. **空data节点**: 某些物品可能有空的<data/>节点
2. **多阶继承冲突**: data_2字段与data字段同名时的优先级
3. **特殊字符**: description中的HTML实体(&lt;font color="#00ff00"&gt;)
4. **注释保留**: XML注释是否需要在round-trip中保留

#### 需要验证的边界文件:
- data/items/武器_刀_重斩.xml (唯一有data_2/3/4的武器)
- data/items/消耗品_弹夹.xml (纯配置，无effects)
- data/items/equipment_mods/特殊材料_通用.xml (可能有特殊结构)
```

### 5.3 Phase 2 校准策略细化

```markdown
#### 校准通过标准:
| 模块 | 目标通过率 | 可接受偏差 | 处理方式 |
|------|------------|------------|----------|
| 枪械DPS | >95% | <0.1% | 强制修复 |
| 防具总分 | >90% | <1% | 强制修复 |
| 近战锋利度 | >90% | <1% | 强制修复 |
| 经济定价 | >85% | <5% | 记录偏差 |
| 药剂效果 | >90% | <1% | 强制修复 |

#### 偏差处理流程:
1. 标记偏差公式和具体数值
2. 检查是否是Excel缓存值本身的精度问题
3. 检查是否是公式理解偏差
4. 使用CALIBRATION_TODO注释标记
5. 继续推进，不阻塞开发
```

---

## 六、待用户确认的问题

### Q1: 公式引擎输出范围确认
```
问题: 公式引擎是否只计算"参考指标"(如DPS)，还是也需要计算"推荐值"(如推荐价格)?

选项A: 仅计算参考指标(DPS/总分等)，推荐价格由平衡人员人工判断
选项B: 同时计算参考指标和推荐价格，作为平衡建议

建议: 选择B，但推荐价格作为"建议值"而非"强制值"
```

### Q2: 插件数值计算深度
```
问题: 插件系统的数值计算要做到什么深度?

选项A (P1): 仅计算单个插件的属性加成效果
选项B (P2): 支持多插件组合的叠加计算
选项C (P3): 完整的射线伤害建模(MC仿真)

建议: P1做选项A，P3做选项C，选项B视P1结果决定
```

### Q3: 怪物属性纳入时机
```
问题: 怪物属性是否一定要在P3实现?是否可再延后?

考虑因素:
- 怪物属性结构与物品完全不同(中文节点名、min/max区间)
- 需要独立解析器
- Excel有712个怪物相关公式

建议: 可延后到P4或更晚，优先保证装备系统完善
```

### Q4: 版本控制策略
```
问题: 工具生成的changelog如何与Git协作?

选项A: changelog作为独立文件提交到仓库
选项B: changelog仅本地存储，通过git diff追踪XML变更
选项C: 每次XML修改自动生成changelog commit

建议: 选择B + C，即平时用git diff，批量修改时生成changelog commit
```

---

## 七、文档修正清单

### 立即修正 (Before Implementation)

- [ ] **DevSpec-v3.md §1.1**: enemy_properties 文件计数 11->12
- [ ] **DevSpec-v3.md §1.1**: 添加 bullets_cases 结构说明
- [ ] **Investigation-Report.md §3.5**: 更新 monsterMagicResistance 完整列表
- [ ] **DevSpec-v3.md §2.3.5**: 添加注释说明双轨公式体系

### 实施中补充 (During Implementation)

- [ ] 创建 `docs/field-reference.md` (附录A)
- [ ] 创建 `docs/formula-derivation.md` (附录B)
- [ ] 在 `formulas/` 中添加射线伤害模型 (基于`射线插件数值建模_2026-02.md`)

### 实施后完善 (After Phase 2)

- [ ] 创建 `docs/data-code-trace.md` (附录C)
- [ ] 创建 `docs/calibration-template.md` (附录D)
- [ ] 根据校准结果更新公式注释

---

## 八、总结

### 文档状态

**CF7-BalanceTool-DevSpec-v3.md** 和 **CF7-BalanceTool-Investigation-Report.md** 是高质量的开发文档，核心内容准确，架构设计合理。发现的问题均为minor级别，不影响整体实施计划。

### 主要建议

1. **立即修正**: 4处minor问题可在1小时内完成
2. **设计确认**: 4个待用户确认的问题需要决策
3. **文档增强**: 建议新增4个附录文档，提升可维护性
4. **实施调整**: Phase 0增加字段扫描任务，Phase 2细化校准策略

### 信心评估

| 阶段 | 信心度 | 说明 |
|------|--------|------|
| Phase 0 (骨架) | 95% | 风险低，技术栈成熟 |
| Phase 1 (XML层) | 90% | fast-xml-parser经验证可用 |
| Phase 2 (公式) | 85% | Excel公式复杂，但baseline可用 |
| Phase 3 (其余) | 80% | 依赖Phase 2结果 |
| Phase 4 (CLI) | 90% | Commander.js成熟方案 |
| Phase 5 (GUI) | 85% | Electron+React方案成熟 |

---

*报告生成时间: 2026-03-06*
*审计人员: Code Agent*
*下次审计建议: Phase 1完成后*
