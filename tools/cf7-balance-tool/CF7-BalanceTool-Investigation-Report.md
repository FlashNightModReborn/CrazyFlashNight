# CF7 数值平衡工具 — 调研报告

> 基于对仓库全量信息的调研，汇总待探索清单(Q1-Q25)结论，列出规格书修正和补充内容。
> v1.1 修订：修正 Q1文件计数、Q6 skill格式(多变体)、Q8插件运算符(6种+3Switch)、Q13怪物文件数(12)、Q14强化公式位置(EquipmentUtil.as)、Q15波动/暴击修正、Q25 magicElements(10种含基础/原体)；补充消耗品_药剂.md和README.md等设计资源引用。

---

## 一、待探索清单(Q1-Q25)完整结论

### 1.1 XML 结构相关 (Q1-Q10)

| # | 结论 |
|---|------|
| Q1 | **XML 文件分布**：主目录杂项 4(list/hairstyle/missileConfigs/bullets_cases) + 武器 37 + 防具 4 + 收集品 3 + 消耗品 6 + equipment_mods/ 22+1(list.xml) |
| Q2 | **规格书遗漏消耗品**。除武器_/防具_/收集品_外还有 **消耗品_**(6文件：货币/弹夹/药剂/药剂_食品/手雷/材料_食材) + 非前缀文件(list/hairstyle/missileConfigs/bullets_cases) |
| Q3 | **22 个武器文件使用 weapontype**。枪械类(手枪/长枪)使用，刀类不使用。值可为具体子类如"压制机枪" |
| Q4 | **不存在 data_5+**。最高 data_4。多阶仅在 3 个文件(防具_0-19级/防具_20-39级/武器_刀_重斩)共 168 处。**枪械无多阶** |
| Q5 | 三种 attr_ 变体：**attr_0**(26文件)、**attr_1**(2文件)、**attr_防具技能**(防具_20-39级) |
| Q6 | **skill 格式多变体**：主要为 skillname/cd/mp 结构，但存在至少4种变体（纯skillname、skillname+cd+mp、嵌套skill数组、内联参数）。HTML 只在 description 中。解析器需兼容多种格式 |
| Q7 | **`<n>` 标签不存在！实际用 `<name>`。规格书必须修正** |
| Q8 | equipment_mods 用 `<mod>` 非 `<item>`。结构：6种运算符(percentage/multiplier/flat/override/merge/cap) + 3种Switch(useSwitch/tagSwitch/bulletSwitch) + 5层安装条件。22 个 XML + list.xml。完整规格见 README.md(1081行) |
| Q9 | **均与数值平衡无关**。inputCommand=搓招配置(3XML)。intelligence=59个剧情文本。intelligenceMD=4个设计文档 |
| Q10 | **收集品无数值字段**。仅 name/displayname/icon/type/use/price/maxvalue/description。不需纳入平衡 |

### 1.2 Excel 与 XML 映射 (Q11-Q14)

| # | 结论 |
|---|------|
| Q11 | **确认映射**：子弹威力->power, 射击间隔->interval, 弹容量->capacity, 重量->weight。Excel 输入值可能经系数调整 |
| Q12 | Excel 防具表仅 ~8 行有效数据(代表性样本)。XML 有上百防具。Excel 是**参考计算器**非数据源 |
| Q13 | 怪物在 **data/enemy_properties/**(12个XML含list.xml)，不在 data/items/。完全不同结构：中文节点名、min/max区间字段 |
| Q14 | 强化查找表位于 **EquipmentUtil.as:44** (levelStatList)，公式：`delta = 1 + 0.01*(等级-1)*(等级+4)`。BuffCalculator.as 处理运行时 buff 计算。表5 无独立配置文件 |

### 1.3 公式与游戏逻辑 (Q15-Q18)

| # | 结论 |
|---|------|
| Q15 | **完整伤害管线已确认**：基础伤害→波动(设计±15%，代码有±30%bug待修)→物理减伤(300/(防御+300))→百分比伤害→固伤→承伤系数。暴击一般1.5但动态回调。12+ handler 支持物理/魔法/真伤/纳米毒素/暴击/吸血/联弹/跳弹/过穿等 |
| Q16 | 怪物公式为**参数化函数**(档次/成长/攻速等系数→HP/攻/防/经验区间)。652 公式可压缩为一个参数化函数 |
| Q17 | **不纳入**。AS2 代码生成辅助工具，非数值平衡 |
| Q18 | **仅作历史参考**。baseline 有旧平衡dps列但无独立数据行 |

### 1.4 工程与流程 (Q19-Q22)

| # | 结论 |
|---|------|
| Q19 | **根目录无 package.json**。Node.js 仅在 tools/Local Server/。需独立初始化 |
| Q20 | 标准 Flash .gitignore。所有 XML/JSON 数据文件都受版本控制 |
| Q21 | **无 review/ 目录**。关键设计文档：data/items/插件数值设计讨论.md + equipment_mods/射线插件数值建模_2026-02.md(495行) + weapon_weighting_workflow.md + weapon_classification_log.md |
| Q22 | **需要 Electron 壳**（用户已确认）。Phase 5 改为 Electron + React + Vite |

### 1.5 数据一致性 (Q23-Q25)

| # | 结论 |
|---|------|
| Q23 | 装备价格 baseline 仅 1 个防具示例，暂无法自动交叉验证 |
| Q24 | 防具 weight 负值(幻影头盔-5)属设计意图"减重"。全面 sanity check 需 validator 实现后做 |
| Q25 | 实际使用：**蚀/毒/冷/热/电/波/冲/全属性/基础/原体** 共 10 种。基础出现在防具_0-19级.xml 及 equipment_mods，原体出现在防具_20-39级.xml（共 65+ 处）。怪物魔抗用完全不同属性名(衍生/黑铁会/立场/模因/人类/电子体/盗贼/首领等) |

---

## 二、规格书需修正的错误

### 严重错误

**E1. 物品标识字段名错误**
- 规格书写 `<n>XM556-H-Stinger</n>`
- 实际 XML 为 `<name>XM556-H-Stinger</name>`
- 影响：1.1 XML 骨架、2.2.1 ParsedItem(id字段)、所有引用 `<n>` 处

**E2. 遗漏「消耗品」品类**
- 规格书只列出武器/防具/收集品
- 实际还有消耗品(药剂/弹夹/手雷/货币/食材/食品)6个XML
- 药剂结构不同于装备：`<data><effects><effect type="heal" hp="150" .../>`

**E3. 遗漏「插件系统」(equipment_mods)**
- 20 个 XML 文件用 `<mod>` 标签，结构完全不同
- 有 495 行活跃的数值建模文档
- ParsedItem 接口无法覆盖

### 中等错误

**E4. 多阶数据分布不准确** — 仅 3 个文件有 data_2/3/4，枪械无多阶

**E5. magicdefence 属性列表不准确** — 实际共 10 种：蚀/毒/冷/热/电/波/冲/全属性/基础/原体（基础和原体在防具 XML 中有 65+ 处使用）

**E6. baseline 数据量描述不准确** — 声称17+13+19+7+4，实际有效行 ~10+~8+6+2+2。遗漏 5 个 section(equipmentPrices/synthesis/dungeonRewards/potions/damageFormula)

### 轻微错误

**E7. skill 格式描述** — 主要为 skillname/cd/mp 结构，但存在多种变体（纯skillname、嵌套数组、内联参数等），解析器需兼容

**E8. weapontype 描述** — 枪械使用/刀类不使用，值可为具体子类

---

## 三、需补充的内容

### 3.1 新增品类 XML 结构

**消耗品（药剂）**：
```xml
<item>
  <name>普通hp药剂</name>
  <type>消耗品</type>
  <use>药剂</use>
  <price>100</price>
  <data>
    <effects>
      <effect type="heal" hp="150" mp="0" target="self" scaleWithAlchemy="true" />
      <effect type="playEffect" name="药剂动画" />
    </effects>
  </data>
</item>
```

**插件（equipment_mods）**：
```xml
<mod>
  <name>增效剂</name>
  <use>头部装备,上装装备,下装装备,手部装备,脚部装备,刀,手枪,长枪</use>
  <stats>
    <percentage>
      <defence>2</defence>
      <damage>2</damage>
      <power>2</power>
    </percentage>
  </stats>
  <description>表面强化药剂</description>
  <tag>表面涂层</tag>
</mod>
```

高级插件(射线类)还有：multiplier/override、installCondition、requireTags、excludeWeapontype、provideTags、tagSwitch 等。

**怪物属性（data/enemy_properties/）**：
```xml
<敌人-黑铁分身>
  <displayname>黑铁分身</displayname>
  <hp_min>600</hp_min>
  <hp_max>2600</hp_max>
  <空手攻击力_min>50</空手攻击力_min>
  <空手攻击力_max>180</空手攻击力_max>
  <基本防御力_min>150</基本防御力_min>
  <基本防御力_max>750</基本防御力_max>
  <韧性系数>0.8</韧性系数>
  <魔法抗性>
    <衍生>50</衍生>
    <黑铁会>50</黑铁会>
  </魔法抗性>
</敌人-黑铁分身>
```

### 3.2 AS2 伤害计算管线（新增 1.5 节）

```
伤害管线（DamageCalculator.as + 各 Handle）：
1. 基础伤害 = 子弹威力 + 伤害加成
2. 波动 = *(0.85 + 0.3 * random())          // 85%~115%
3. 物理减伤 = *(300 / (防御力 + 300))        // DamageResistanceHandler.as
4. 百分比伤害 = HP * bullet.百分比伤害 / 100  // 可选
5. 固伤 = + bullet.固伤                      // 可选
6. 承伤系数 = * hitTarget.damageTakenMultiplier

强化公式（BuffCalculator.as）：
delta = 1 + 0.01 * (强化等级-1) * (强化等级+4)
最终威力 = base * (delta + pct/100) * (1 + mult/100) * dtype_mult

伤害类型 handler：
- 物理(BasicDamageHandle) -> 防御减伤
- 魔法(MagicDamageHandle) -> 属性抗性
- 真伤(TrueDamageHandle) -> 绕过所有抗性
- 纳米毒素(NanoToxicDamageHandle) -> 特殊检测
- 暴击(CritDamageHandle) -> *1.5
- 处决(ExecuteDamageHandle)
- 吸血(LifeStealDamageHandle)
- 跳弹 -> max(floor(damage - defense/5), 1)
- 过穿 -> max(floor(damage * 300/(defense+300)), 1)
```

### 3.3 baseline.json 完整结构

实际包含 **9 个 section**（规格书只描述前 5 个）：

| Section | 有效数据行 | 注释行 | 输入列数 | 计算列数 |
|---------|-----------|--------|---------|---------|
| weapons | ~10 | ~6 | 14(示例类型->额外加权层数) | 25(平均dps->周期dps系数) |
| armor | ~8 | ~3 | 11(类型->额外加权层数) | 5(当前总分->法抗最高上限) |
| monsters | 6 | ~8 | 11(名称->高防低血系数) | 10(攻击MIN->K点价格) |
| melee | 2 | ~5 | 6(名称->加权层数) | 1(推荐锋利度) |
| explosives | 2 | ~1 | 6(名称->加权层级) | 1(推荐单发威力) |
| **equipmentPrices** | ~2 | 表头 | 7(类型->伤害类型系数) | 3(金币/K点/换算比例) |
| **synthesis** | ~1 | 结构说明 | 9(类型->掉落物折算价格) | 5(装备折算->列2) |
| **dungeonRewards** | 4 | ~1 | 9(名称->强化石) | 3(当前/期望收益/P) |
| **potions** | 6 | ~3 | 14(名称->buff-持续帧) | 11(hp->原始推荐价格) |

另有 **damageFormula** section，列名为原始列号(C/D/E/F/G/H/J/K/L/M/N/O/U/W)。

### 3.4 ParsedItem 接口重构

当前单一接口无法覆盖实际数据多样性，建议分层：

```typescript
// 基础接口
interface BaseItem {
  sourceFile: string;
  id: string;           // <name> 值（非 <n>）
  displayname: string;
  type: string;         // 武器/防具/收集品/消耗品
  use: string;
  price: number;
  description: string;
}

// 装备（武器+防具）
interface EquipmentItem extends BaseItem {
  baseData: Record<string, unknown>;
  tierData?: Record<string, Record<string, unknown>>[];  // 仅防具/部分刀
  magicDefence?: Record<string, number>;
  tierMagicDefence?: Record<string, number>[];
  lifecycleRaw: string;
  skillRaw?: string;
  weapontype?: string;
  helmet?: boolean;
  actiontype?: string;
  extraRaw: Record<string, string>;
}

// 消耗品
interface ConsumableItem extends BaseItem {
  effects: Array<{type: string; [key: string]: unknown}>;
}

// 插件（完全不同结构）
interface ModItem {
  sourceFile: string;
  name: string;
  use: string[];
  stats: {
    percentage?: Record<string, number>;
    flat?: Record<string, number>;
    override?: Record<string, unknown>;
    multiplier?: Record<string, number>;
  };
  installCondition?: Record<string, unknown>;
  requireTags?: string[];
  excludeWeapontype?: string[];
  // ... 更多射线特有字段
}
```

### 3.5 field-config.json 修正

```jsonc
{
  "numericFields": [
    "level", "weight", "price", "hp", "mp", "damage", "defence",
    "power", "interval", "capacity", "split", "diffusion", "velocity",
    "bulletsize", "impact", "evasion", "accuracy", "knifepower",
    "gunpower", "punch", "force", "vampirism", "toughness",
    "reloadPenalty", "criticalhit", "modslot"
  ],
  "passthroughFields": [
    "dressup", "bullet", "bulletrename", "sound", "muzzle",
    "bullethit", "clipname"
  ],
  "nestedNumericFields": ["magicdefence"],
  "magicElements": ["蚀", "毒", "冷", "热", "电", "波", "冲", "全属性", "基础", "原体"],
  "monsterMagicResistance": ["衍生", "黑铁会", "立场", "模因", "人类", "电子体", "盗贼", "首领"]
}
```

注：`基础` 在防具_0-19级.xml 和 equipment_mods 中出现，`原体` 在防具_20-39级.xml 中出现（共 65+ 处）。新增 `全属性`。共 10 种 magicElements。

### 3.6 技术栈与目录调整

**技术栈**：前端改为 Electron + React + Vite（用户确认需要独立桌面应用）

**项目位置**：`tools/cf7-balance-tool/`（与 Local Server 平级）

**目录结构**：
```
tools/cf7-balance-tool/
+-- baseline/
|   +-- baseline-extracted.json      已提取的校准基准
+-- packages/
|   +-- core/                        纯计算内核
|   |   +-- src/
|   |       +-- schema/
|   |       |   +-- equipment.ts     装备(武器+防具)
|   |       |   +-- consumable.ts    消耗品
|   |       |   +-- mod.ts           插件
|   |       |   +-- enemy.ts         怪物属性(P2)
|   |       |   +-- field-registry.ts
|   |       +-- formulas/
|   |           +-- weapons.ts       枪械 DPS (25列)
|   |           +-- melee.ts         近战锋利度
|   |           +-- armor.ts         防具总分
|   |           +-- explosives.ts    爆炸类
|   |           +-- economy.ts       价格/合成/副本
|   |           +-- potions.ts       药剂
|   |           +-- monsters.ts      怪物面板(P2)
|   |           +-- damage.ts        伤害减免
|   |           +-- experience.ts    经验曲线(P3)
|   +-- xml-io/                      XML 读写层
|   |   +-- src/
|   |       +-- parsers/
|   |       |   +-- equipment-parser.ts
|   |       |   +-- mod-parser.ts
|   |       |   +-- consumable-parser.ts
|   |       |   +-- enemy-parser.ts(P2)
|   |       +-- serializer.ts
|   |       +-- scanner.ts
|   |       +-- tier-resolver.ts
|   +-- excel-io/                    Legacy 导入
|   +-- cli/                         CLI
|   +-- web/                         Electron + React + Vite
+-- data/
|   +-- field-config.json
|   +-- formula-config.json
|   +-- changelog/
+-- CF7-BalanceTool-DevSpec-v2.md    开发规格书
+-- CF7-BalanceTool-Investigation-Report.md  本调研报告
+-- package.json                     pnpm workspace root
+-- tsconfig.json
+-- vitest.config.ts
```

---

## 四、设计取向决议

| # | 决议 | 理由 |
|---|------|------|
| D1 | 插件系统纳入(P1) | 已有活跃数值建模工作，pct/mult/falloff 直接影响武器平衡 |
| D2 | 怪物属性纳入(P2/P3) | Excel 有 712 个公式，但结构不同可延后 |
| D3 | 药剂纳入(P2)，其他消耗品否 | 药剂有 59 个公式和 baseline。弹夹/货币/食材纯配置 |
| D4 | 项目位于 tools/cf7-balance-tool/ | 与 Local Server 平级，便于访问 data/ |
| D5 | 使用 Electron 壳 | 用户确认 |
| D6 | 收集品不纳入 | 无数值字段 |
| D7 | hairstyle 不纳入 | 非数值平衡 |
| D8 | bullets_cases.xml 随插件纳入 | 射线子弹配置在此 |
| D9 | missileConfigs 暂不纳入 | 可后续按需加入 |

---

## 五、分阶段计划调整

### Phase 0 调整
- 增加：生成完整字段使用报告（按品类统计所有字段出现次数）
- baseline fixture 说明写入实际行数和 section

### Phase 1 调整
- XML 解析器支持 3 种格式：`<item>`(装备/消耗品)、`<mod>`(插件)、怪物(中文节点名)
- Round-trip 测试范围扩展到消耗品和插件

### Phase 2 调整
- 枪械校准行数修正为 ~10 行
- 增加防具校准（总分）和近战校准（推荐锋利度）

### Phase 3 调整
- 新增 P1：插件效率计算(pct/mult/falloff -> 回本等级/效率表)
- P2：药剂/合成/副本/经济
- P3：怪物面板/经验曲线

### Phase 5 调整
- Electron + React + Vite
- 增加插件编辑界面

---

## 六、公式反推笔记

### 6.1 武器表注释行设计规则

baseline row 17-21 包含重要规则（应提取到帮助文档）：
- **双枪系数**：短枪=2，长枪=1
- **穿刺系数**：喷火/次级穿刺/高弹速(60+)穿刺狙击=1.5，普通穿刺=2，非穿刺=1，高段数可填3+
- **伤害类型系数**：物理=1，魔法=2，真伤=3，混合可填中间值
- **霰弹值**：霰弹填对应数量，爆炸类填4，不含穿刺段数

### 6.2 防具公式结构

使用**加权总分模型**（非 DPS）：
```
平衡总分 = f(限制等级)
当前总分 = 防御 + HP*w_hp + MP*w_mp + 伤害加成*w_dmg + ...
加权总分 = 平衡总分 * 加权系数(额外加权层数)
法抗均值上限 = g(限制等级)
法抗最高上限 = h(限制等级)
```

### 6.3 近战公式

仅输出**推荐锋利度**：
- 等级13, 重量2, 系数1, 层数0 -> 136
- 等级35, 重量3, 系数1, 层数0 -> 359

换算公式(baseline注释)：1攻=1.5防=3hp=3mp, 1重量=3.3攻=5防=10hp=10mp

---

## 七、仓库相关设计资源

| 文件 | 位置 | 相关性 |
|------|------|--------|
| **消耗品_药剂.md** | data/items/ | **药剂数值理论(437行)**：StdHP体系/CD补偿/品类配额/buff计算类型 |
| **equipment_mods/README.md** | data/items/equipment_mods/ | **插件系统完整规格(1081行)**：6运算符/3Switch/安装条件/Tag依赖/命中率模型 |
| 插件数值设计讨论.md | data/items/ | 插件机制设计(百分比/固定/覆盖算子) |
| 射线插件数值建模_2026-02.md | data/items/equipment_mods/ | 495行射线数值模型含MC仿真 |
| 插件获取途径审阅报告.md | data/items/equipment_mods/ | 插件掉落/获取设计 |
| weapon_weighting_workflow.md | data/items/ | 武器加权工作流 + DPS公式 + weightlevel规范(226行) |
| weapon_classification_workflow.md | data/items/ | 武器分类工作流 |
| weapon_weighting_log.md | data/items/ | 武器加权标注日志 |
| weapon_classification_log.md | data/items/ | 武器分类日志 |
| ray_hitrate_validation.py | data/items/equipment_mods/ | 射线命中率仿真脚本 |
| **EquipmentUtil.as** | scripts/.../item/ | 强化查找表(levelStatList:44) + 插件计算(calculateData) |
| DamageResistanceHandler.as | scripts/.../StatHandler/ | 核心减伤公式 `300/(defense+300)` |
| DamageCalculator.as | scripts/.../Damage/ | 伤害管线 |
| BuffCalculator.as | scripts/.../Buff/ | 运行时Buff计算（非强化公式） |
