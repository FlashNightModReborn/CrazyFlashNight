# CF7 数值平衡工具 — 开发规格书 v3

> 供 Agent 执行的完整开发任务书。
> 基于 v2 + 两轮仓库全量调研结论修订。所有 v2 待探索清单(Q1-Q25)已解决，结论内联在相应章节。
> 完整调研过程见 CF7-BalanceTool-Investigation-Report.md。
> v3.1 修订：修正波动公式、magicElements、字段分类、文件计数等多处错误；补充插件6运算符规格、消耗品数值理论引用、武器DPS公式。

---

## 0. 项目定位

### 0.1 是什么

一个数值平衡管理工具，直接读写游戏项目的 XML 数据文件，内置从 Excel 翻译的平衡计算引擎。
取代当前「Excel 离线算 -> 手动抄回 XML」的工作流。

### 0.2 当前工作流的问题

```
WPS Excel（离线计算器）──人工对照──> data/items/*.xml（游戏数据）──> AS2 运行时
```

- Excel 只是计算器，不是数据源，改完还要手动同步回 XML
- Python 调用 Excel 公式求值库失败（原因已确认，见 $1.5）
- XML 结构自由度极高，Excel 无法覆盖所有物品的所有字段
- Agent 无法自动化任何环节

### 0.3 目标工作流

```
游戏 XML 数据 <──双向读写──> 平衡工具 <──公式引擎──> 计算内核
                                 |
                   CLI / Electron GUI / Agent 均可操作
```

### 0.4 五条核心约束

| # | 约束 | 具体含义 |
|---|------|---------|
| C1 | 向前兼容 | 内部用 JSON 做计算中间态；Excel 作为 legacy import 通道（仅迁移期用）；XML 是真正的数据源 |
| C2 | 人类友好 | Electron GUI 表格编辑；数值关联可视化；校验即时反馈 |
| C3 | Agent 友好 | headless 计算内核 + CLI 入口；Agent 无需 GUI 即可完成全量增删查改和批量重平衡 |
| C4 | LLM 预留 | 不提前实现但不堵死：纯 JSON I/O、CLI 已存在、proposed_changes 审批流 |
| C5 | 可审计 | 变更 changelog；纯文本格式可 git diff；任意版本间数值对比 |

### 0.5 技术栈

| 层 | 选型 | 原因 |
|----|------|------|
| 语言 | TypeScript (strict) | 与 AS2 互译难度最低；类型系统辅助 Agent 自动纠错 |
| 运行时 | Node.js >=18, tsx 直接执行 | 零编译开发循环 |
| 测试 | Vitest | 输出结构化、Agent 解析友好 |
| XML | fast-xml-parser | 解析/序列化快，preserveOrder 模式可保留原始结构 |
| Excel I/O | SheetJS (xlsx) | 仅用于 legacy import |
| 前端 | **Electron + React + Vite** | 独立桌面应用，无需浏览器 |
| Schema | Zod | 运行时校验 + 类型推导 |

### 0.6 项目位置

```
仓库根/tools/cf7-balance-tool/     与 tools/Local Server/ 平级
```

---

## 1. 数据源分析

### 1.1 XML 数据目录总览

游戏数据分布在多个目录，本工具涉及的数据源如下：

| 目录 | 文件数 | 用途 | 工具支持方式 |
|------|--------|------|------------|
| `data/items/` (杂项) | 4 | 物品主索引(list.xml) + hairstyle/missileConfigs/bullets_cases | 扫描 + 按需 CRUD |
| `data/items/武器_*.xml` | 37 | 枪械(手枪10/长枪12) + 近战(刀15) | **公式引擎 + CRUD** |
| `data/items/防具_*.xml` | 4 | 防具(按等级范围/颈部) | **公式引擎 + CRUD** |
| `data/items/消耗品_*.xml` | 6 | 药剂/弹夹/手雷/货币/食材/食品 | 药剂: 公式引擎; 其余: CRUD |
| `data/items/收集品_*.xml` | 3 | 材料/情报/插件 | 不纳入(无数值字段) |
| `data/items/equipment_mods/` | 22+1 | 插件系统(低/中/高/特殊 × 通用/防具/刀/拳/枪械/下挂) + list.xml | **仅 CRUD**（暂无数值理论） |
| `data/items/bullets_cases.xml` | 1 | 子弹/射线配置（`<bullet>` 结构） | **仅 CRUD**（暂无数值理论） |
| `data/enemy_properties/` | 12 | 怪物属性（含list.xml） | **延后(P3)**，CRUD 优先 |

> **收集品** 仅含 name/displayname/icon/type/use/price/description，无数值字段，不纳入。
> **inputCommand** 是搓招系统、**intelligence/intelligenceMD** 是剧情文本，均与数值平衡无关。

### 1.2 装备 XML 结构（武器 + 防具）

**文件命名规则：**
```
防具_0-19级.xml / 防具_20-39级.xml / 防具_40+级.xml / 防具_颈部装备.xml
武器_刀_刀剑.xml / 武器_刀_短兵.xml / 武器_刀_镰刀.xml / ...（15种刀类子类）
武器_手枪_冲锋枪.xml / 武器_手枪_霰弹枪.xml / ...（10种手枪子类）
武器_长枪_突击步枪.xml / 武器_长枪_狙击步枪.xml / ...（12种长枪子类）
```

**XML 通用骨架（基于实际文件验证）：**

> **注意**：节点顺序不固定。实际 XML 中 `<lifecycle>` 可出现在 `<data>` 之前（如 XM556-H-Stinger）。解析器不能假设固定顺序。

```xml
<root>
  <item weapontype="压制机枪">        <!-- weapontype: 枪械使用，刀类不使用 -->
    <!-- === 元信息层 === -->
    <name>XM556-H-Stinger</name>      <!-- 唯一标识（非 <n>） -->
    <displayname>XM556-H-Stinger</displayname>
    <icon>XM556-H-Stinger</icon>
    <type>武器</type>                  <!-- 大类：武器/防具 -->
    <use>手枪</use>                    <!-- 子类/装备位 -->
    <price>442010</price>
    <description>...</description>
    <helmet>true</helmet>              <!-- 可选，防具头部特有 -->
    <actiontype>截拳</actiontype>      <!-- 可选，防具手部特有 -->
    <inherentTags>电力,NOAH</inherentTags>  <!-- 可选，装备固有结构标签 -->
    <blockedTags>...</blockedTags>     <!-- 可选，禁止安装的插件标签 -->

    <!-- === 数值层（核心）=== -->
    <data>
      <level>35</level>
      <weight>10</weight>
      <dressup>枪-手枪-XM556</dressup>
      <capacity>25</capacity>          <!-- 枪械特有 -->
      <power>40</power>                <!-- 枪械特有 -->
      <split>5</split>                 <!-- 枪械特有 -->
      <interval>200</interval>         <!-- 枪械特有 -->
      <damagetype>魔法</damagetype>    <!-- 可选，伤害类型 -->
      <magictype>电</magictype>        <!-- 可选，魔法属性 -->
      <weightlevel>0</weightlevel>     <!-- 可选，加权等级 -1~4 -->
      <hp>50</hp>                      <!-- 防具特有 -->
      <defence>170</defence>           <!-- 防具特有 -->
      <magicdefence>                   <!-- 嵌套，子节点名为中文 -->
        <蚀>10</蚀>
      </magicdefence>
      <skillmultipliers>               <!-- 可选，嵌套，刀类特有 -->
        <瞬步斩>2.5</瞬步斩>
      </skillmultipliers>
    </data>

    <!-- === 多阶数据（可选，仅防具和部分刀类）=== -->
    <data_2>                           <!-- 只覆盖变化字段，继承 data 其余值 -->
      <modslot>3</modslot>
      <level>28</level>
      <hp>45</hp>
      <defence>155</defence>
    </data_2>
    <data_3>...</data_3>               <!-- 最高到 data_4，无 data_5+ -->
    <data_4>...</data_4>

    <!-- === 行为逻辑层（透传）=== -->
    <lifecycle>
      <attr_0>                         <!-- 也可能是 attr_1 -->
        <init>
          <initRoutines>XXX初始化</initRoutines>
          <initParam>...</initParam>
        </init>
        <cycle>
          <cycleRoutines>XXX周期</cycleRoutines>
        </cycle>
        <skill>                        <!-- 格式一：结构化 skillname/cd/mp -->
          <skillname>凶斩</skillname>
          <cd>8000</cd>
          <mp>25</mp>
        </skill>
        <bullet>...</bullet>
      </attr_0>
    </lifecycle>
  </item>
</root>
```

**已确认的字段分类：**

| 分类 | 字段 | 说明 |
|------|------|------|
| 通用数值 | level, weight, price | 所有品类共有 |
| 枪械数值 | power, interval, capacity, split, diffusion, velocity, bulletsize, impact, reloadPenalty, criticalhit | data 内 |
| 防具数值 | hp, mp, damage, defence, evasion, accuracy, knifepower, gunpower, punch, force, vampirism, toughness, lazymiss | data 内 |
| 刀类数值 | slay, bladeCount, rout | data 内，少数刀类使用 |
| 类型标识 | damagetype(148次), magictype(137次) | data 内，伤害/魔法类型字符串 |
| 加权等级 | weightlevel | data 内，-1~4，影响 DPS 计算（部分武器已标注） |
| 法抗（嵌套） | magicdefence.{蚀,毒,冷,热,电,波,冲,全属性,基础,原体} | 子节点名为中文，共 10 种 |
| 技能倍率（嵌套） | skillmultipliers.{技能名} | data 内，刀类特有，嵌套数值结构 |
| 枪械资源 | bullet, bulletrename, sound, muzzle, bullethit, clipname, singleshoot, reloadType | 纯透传 |
| 外观 | dressup, icon | 纯透传 |
| 结构标签（item级） | inherentTags(72次), blockedTags(22次) | 不在 data 内，在 item 级别 |
| 行为逻辑 | lifecycle 整个子树 | 纯透传 |
| 多阶强化 | data_2, data_3, data_4 | 继承 data 未覆盖字段。仅 3 个文件有(防具x2 + 武器_刀_重斩) |
| 强化插槽 | modslot | data_N 内 |

**关键特性：**
1. **Schema-less**: 不同物品的 data 字段集合不同，不能硬编码
2. **多阶继承**: data_2/3/4 只写变化字段，继承 data 基础值。最高 data_4，无更高阶。**枪械无多阶**
3. **中文节点名**: magicdefence 子节点（蚀/毒/冷/热/电/波/冲/全属性）
4. **混合内容**: lifecycle 含复杂嵌套参数，必须原样保留
5. **DPS 不在 XML 中**: XML 只存基础参数，DPS 是公式引擎的参考计算值
6. **weapontype**: 枪械类(手枪/长枪)使用此属性，值可为具体子类(如"压制机枪")；刀类不使用

### 1.3 消耗品 XML 结构

消耗品使用 `<item>` 标签但内部结构不同，药剂用效果声明：

```xml
<item>
  <name>普通hp药剂</name>
  <type>消耗品</type>
  <use>药剂</use>
  <price>100</price>
  <description>...</description>
  <data>
    <effects>
      <effect type="heal" hp="150" mp="0" target="self" scaleWithAlchemy="true" />
      <effect type="playEffect" name="药剂动画" />
    </effects>
  </data>
</item>
```

消耗品子类：药剂/药剂_食品/弹夹/手雷/货币/材料_食材。
仅**药剂**有对应的 Excel 公式(59个)和 baseline 数据，其余为纯配置。

**药剂数值理论（详见 `data/items/消耗品_药剂.md`，437行）：**

- **9 种效果词条**：heal(即时恢复)、regen(缓释)、state(状态修改)、purify(净化)、buff(属性增减益)、playEffect、message、grantItem、global
- **StdHP 换算体系**：1HP = 1MP = 1StdHP，1防御 = 2StdHP，1攻击 = 3StdHP
- **金币基准**：1金币 ≈ 1 StdHP（瞬间回复、self目标）
- **CD补偿函数**：`m_cd(t) = 1 + 0.208795 × t^0.522879`（锚点：0s→1.0, 2s→1.3, 20s→2.0）
- **buff计算类型**：叠加型(add/multiply/percent)、独占型(add_positive/add_negative/mult_positive/mult_negative)、边界控制(override/max/min)
- **品类配额系数**：药剂 quota=1.0（恢复最优）、食品 0.5~0.75、菜品 1.25~1.5（合成门槛换取高性价比）
- **速度buff理论**：按档位定价，详见原文档

> 公式引擎实现药剂模块时，需将上述理论转为 `formulas/potions.ts`。

### 1.4 插件 XML 结构（equipment_mods/）

使用 `<mod>` 标签，与 `<item>` 完全不同。本工具**仅做 CRUD，不做公式计算**（当前无数值平衡理论）。

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

**六种核心运算符（按执行顺序）：**

| # | 运算符 | 运算方式 | 说明 |
|---|--------|---------|------|
| 1 | percentage | `base × (1 + Σpct/100)` | 加法合并乘区，与强化等级共享 |
| 2 | multiplier | `× Π(1 + mult_i/100)` | 独立乘区，每个配件独立相乘 |
| 3 | flat | `+ Σflat` | 固定值加法 |
| 4 | override | 直接替换 | 浅层覆盖，慎用于嵌套对象 |
| 5 | merge | 递归深度合并 | 智能数值合并(正取max/负取min)，字符串前缀保留拼接 |
| 6 | cap | 增益上限/减益下限 | 最终安全阀 |

**三种条件分支系统（Switch）：**

| Switch | 触发条件 | 判定时机 | 典型用途 |
|--------|---------|---------|---------|
| useSwitch | 装备的 use/weapontype | 固定 | 武器类型专精 |
| tagSwitch | 装备的 presentTags | 动态(受配件影响) | 结构依赖加成 |
| bulletSwitch | 装备的子弹类型 | 原始子弹(不含配件override) | 弹药类型适配 |

三种 Switch 均支持 default(兜底)分支：省略 name 属性的节点仅在无命名分支命中时生效。

**安装条件体系（5层检查链）：**
```
1. use / weapontype        ← 类型层（装备大类/子类）
2. requireTags / provideTags ← 结构层（Tag 依赖链）
3. excludeBulletTypes       ← 子弹层（弹药排斥，8种类型标识）
4. requireBulletTypes       ← 子弹层（弹药要求）
5. installCondition         ← 数值层（12种运算符的属性精准控制）
```

**其他重要特性**：grantsWeapontype(授予武器类型)、detachPolicy(级联卸载)、小数处理规则(weight/rout/vampirism 保留1位小数，其余取整)。

文件组织：4 等级(低级/中等/高等/特殊) × 6 类型(通用/防具/刀/拳/枪械/下挂武器) = 22 个 XML + list.xml。

> 完整规格见 `data/items/equipment_mods/README.md`（1081行）。
> 设计参考：`data/items/插件数值设计讨论.md` + `data/items/equipment_mods/射线插件数值建模_2026-02.md`(495行)
> 本工具**仅做 CRUD**，当前无数值平衡理论指导，需后续实测积累后再建模。

### 1.5 怪物属性 XML 结构（data/enemy_properties/）

**延后(P3)**。结构与物品完全不同，用中文节点名作为 tag name：

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

包含 12 个 XML 文件（含 list.xml）。注意怪物魔法抗性的属性名体系与物品 magicdefence 完全不同，使用阵营/流派名（如 衍生/黑铁会/立场/模因/人类/电子体/盗贼/首领 等），非元素名。

### 1.6 AS2 伤害计算管线（已从源码确认）

```
伤害管线（DamageCalculator.as + 各 Handle）：
1. 基础伤害 = 子弹威力 + 伤害加成
2. 波动 = *(0.85 + 0.3 * random())          // 设计意图 ±15%
   注意：当前代码实际调用 PinkNoiseEngine.randomFluctuation(30)，
   得到 0.7~1.3 (±30%)，属已知 bug，后续将修正为 ±15%。
   平衡工具以 ±15% 为准。
3. 物理减伤 = *(300 / (防御力 + 300))        // DamageResistanceHandler.as:38
4. 百分比伤害 = HP * bullet.百分比伤害 / 100  // 可选
5. 固伤 = + bullet.固伤                      // 可选
6. 承伤系数 = * hitTarget.damageTakenMultiplier

强化公式（EquipmentUtil.as:44 levelStatList 查找表）：
delta = 1 + 0.01 * (强化等级-1) * (强化等级+4)
常用 delta 值: Lv1=1.0, Lv5=1.36, Lv7=1.66, Lv9=2.04, Lv13=3.04

插件增幅公式（EquipmentUtil.as calculateData 方法）：
最终属性 = base * (delta + Σpercentage/100) * Π(1+multiplier_i/100) + Σflat
→ 之后依序应用 override → merge → cap
详见 §1.4 运算符优先级。

暴击倍率：一般为 1.5（50%增幅），但实际通过 bullet.暴击(bullet) 动态回调，
部分武器/插件可自定义暴击倍率。平衡计算以 1.5 为默认值。

伤害类型 handler（scripts/类定义/org/flashNight/arki/component/Damage/）：
- BasicDamageHandle   物理 -> 防御减伤
- MagicDamageHandle   魔法 -> 属性抗性优先
- TrueDamageHandle    真伤 -> 绕过所有抗性
- NanoToxicDamageHandle  纳米毒素 -> 特殊检测
- CritDamageHandle    暴击 -> *1.5（默认）
- ExecuteDamageHandle  处决
- LifeStealDamageHandle  吸血
- MultiShotDamageHandle  联弹分段
- 跳弹 -> max(floor(damage - defense/5), 1)
- 过穿 -> max(floor(damage * 300/(defense+300)), 1)
- 共 12+ handler
```

### 1.7 Excel 公式分析

原始 Excel 含 15 个 Sheet，共 ~1800 个公式。

**Sheet 总览：**

| Sheet | 公式数 | 核心职责 | 工具实现优先级 |
|-------|--------|---------|---------------|
| 枪械 | 299 | DPS/周期伤害/吃拐率等 25 个计算列 | **P0** |
| 防具 | 53 | 加权总分/平衡总分 | **P1** |
| 刀 | 4 | 推荐锋利度 | **P1** |
| 爆炸类 | 5 | 推荐单发威力 | **P1** |
| 装备价格 | 24 | 经济定价 | **P1** |
| 伤害公式 | 192 | 伤害减免验证 | **P1** |
| 合成表成本 | 26 | 合成成本 | P2 |
| 副本收益 | 29 | 收益计算 | P2 |
| 药剂面板 | 59 | 药剂效果/推荐价格 | P2 |
| 怪物大致面板 | 60 | 怪物属性 | P3（延后） |
| 等级计算怪物属性 | 652 | 按等级展开怪物 | P3（延后） |
| 经验辅助计算 | 57 | 经验曲线 | P3 |
| 其余计算 | 341 | 杂项 | P3 |
| 旧版-枪械 | 70 | 历史参考 | 不实现 |
| 技能格式 | 9 | AS2 代码生成 | 不实现 |

**公式特征：**
- 结构化表格引用 `表2_5[[#This Row],[列名]]`：361 处
- `_xlfn.FLOOR.MATH` 前缀：怪物面板 + 其余计算
- 无跨 Sheet 引用（每 Sheet 公式自包含）
- 枪械表公式链最深 6+ 层

### 1.8 武器 DPS 计算公式（来自 weapon_weighting_workflow.md）

**平均DPS：**
```
平均DPS = 1000 × 单发伤害 / (射击间隔 × (弹夹容量 - 1) + 900 × 双枪系数)
```

**加权DPS：**
```
加权DPS = 平均DPS × 弹道系数 × 对攻系数 × 1.1^加权等级
```

**关键系数：**

| 系数 | 值 | 条件 |
|------|-----|------|
| 双枪系数 | 1.0 | 单枪 |
| | 2.0 | 双枪(手枪类) |
| | 1.5 | 双枪(长枪类) |
| 弹道系数 | 1.0 | 激光/能量 |
| | 1.5 | 连发/制导 |
| | 2.0 | 普通弹道 |
| 伤害类型系数 | 1.0 | 物理 |
| | 2.0 | 魔法 |
| | 3.0 | 真伤 |
| 对攻系数 | 1.0 | 默认 |

**加权等级（weightlevel）字段**：整数 -1~4，存储在 `<data>` 内。

| 等级 | 含义 | 获取方式 |
|------|------|---------|
| -1 | 负加权(新手/练习) | 新手武器 |
| 0 | 标准 | 普通掉落/商店 |
| 1 | 优质 | K点/合成 |
| 2 | 精良 | 高价/稀有掉落 |
| 3 | 史诗 | K点+合成+高价 |
| 4 | 传奇 | 特殊活动/开发者武器 |

> 公式引擎实现时需映射到 `formulas/weapons.ts` 中的 DPS 计算列。

### 1.9 Excel 列名 -> 字段映射（枪械表）

| Excel 列 | 位置 | 类型 | 建议字段名 |
|----------|------|------|-----------|
| 示例类型 (B) | input | string | type |
| 具体武器 (C) | input | string | name |
| 限制等级 (D) | input | number | levelReq |
| 子弹威力 (E) | input | number | bulletPower |
| 射击间隔 (F) | input | number | shootInterval |
| 弹容量 (G) | input | number | magSize |
| 弹夹价格 (H) | input | number | magPrice |
| 重量 (I) | input | number | weight |
| 双枪系数 (J) | input | number | dualWieldFactor |
| 穿刺系数 (K) | input | number | pierceFactor |
| 伤害类型系数 (L) | input | number | damageTypeFactor |
| 霰弹值 (M) | input | number | shotgunValue |
| 冲击力 (N) | input | number | impact |
| 额外加权层数 (O) | input | number | extraWeightLayers |
| 平均dps (Q) | computed | number | averageDPS |
| 加权dps (S) | computed | number | weightedDPS |
| 平衡dps (V) | computed | number | balanceDPS |
| 周期伤害 (W) | computed | number | cycleDamage |
| ... | ... | ... | （共 25 个计算列，完整映射见 baseline JSON） |

**Excel 注释行包含的设计规则（应提取到帮助文档）：**
- 双枪系数：短枪=2，长枪=1
- 穿刺系数：喷火/次级穿刺/高弹速(60+)穿刺狙击=1.5，普通穿刺=2，非穿刺=1
- 伤害类型系数：物理=1，魔法=2，真伤=3，混合可填中间值
- 霰弹值：霰弹填对应数量，爆炸类填4，不含穿刺段数

### 1.10 Python 计算不一致的已确认根因

| 问题 | 影响范围 | 说明 |
|------|---------|------|
| 结构化表格引用 `#This Row` | 361 处 | Python 公式求值库不支持 |
| `_xlfn.FLOOR.MATH` | 怪物面板 + 其余计算 | Python 库不识别前缀 |
| 公式链拓扑排序 | 枪械表 6+ 层 | 中间值可能用了未计算的默认 0 |

**结论：本工具用 TS 重新实现公式，用 Excel 缓存值做校准基准。**

---

## 2. 架构设计

### 2.1 数据管辖范围

工具对不同品类提供两个层次的支持：

| 层次 | 品类 | 能力 |
|------|------|------|
| **公式引擎 + CRUD** | 枪械、防具、近战(刀)、爆炸类、装备价格、伤害公式、合成/副本、药剂 | 读写 XML + 公式计算参考值 + 校准 |
| **仅 CRUD** | 插件(equipment_mods)、bullets_cases、消耗品(非药剂)、怪物(延后) | 读写 XML + 查询/编辑，不做公式计算 |
| **不纳入** | 收集品、hairstyle、missileConfigs、inputCommand、intelligence | 无数值字段 / 与平衡无关 |

### 2.2 目录结构

```
tools/cf7-balance-tool/
|-- packages/
|   |-- core/                        <-- 纯计算内核（零 UI/IO 依赖）
|   |   |-- src/
|   |   |   |-- schema/              <-- Zod schema
|   |   |   |   |-- equipment.ts         装备(武器+防具)通用结构
|   |   |   |   |-- consumable.ts        消耗品
|   |   |   |   |-- mod.ts               插件
|   |   |   |   |-- field-registry.ts    字段分类注册表
|   |   |   |   +-- index.ts
|   |   |   |-- formulas/            <-- 从 Excel 翻译的公式
|   |   |   |   |-- weapons.ts           枪械 25 列
|   |   |   |   |-- armor.ts             防具总分
|   |   |   |   |-- melee.ts             近战锋利度
|   |   |   |   |-- explosives.ts        爆炸类
|   |   |   |   |-- economy.ts           价格/合成/副本
|   |   |   |   |-- potions.ts           药剂
|   |   |   |   |-- damage.ts            伤害减免
|   |   |   |   +-- index.ts
|   |   |   |-- engine/              <-- 计算引擎
|   |   |   |   |-- calculator.ts        全量计算调度
|   |   |   |   |-- diff.ts              版本对比 / changelog
|   |   |   |   +-- validator.ts         业务规则校验
|   |   |   |-- rules/               <-- 平衡规则
|   |   |   |   |-- types.ts
|   |   |   |   |-- builtin/
|   |   |   |   |   |-- scale-by-level.ts
|   |   |   |   |   |-- align-dps.ts
|   |   |   |   |   +-- economy-balance.ts
|   |   |   |   +-- index.ts
|   |   |   +-- index.ts
|   |   |-- tests/
|   |   |   |-- calibration/         <-- Excel 缓存值校准
|   |   |   |   |-- fixtures/
|   |   |   |   |   +-- baseline.json
|   |   |   |   +-- *.calibration.test.ts
|   |   |   |-- formulas/
|   |   |   +-- rules/
|   |   +-- package.json
|   |
|   |-- xml-io/                      <-- XML 读写层
|   |   |-- src/
|   |   |   |-- parsers/
|   |   |   |   |-- equipment-parser.ts   装备 <item>（武器+防具）
|   |   |   |   |-- consumable-parser.ts  消耗品 <item>（药剂/弹夹等）
|   |   |   |   +-- mod-parser.ts         插件 <mod>
|   |   |   |-- serializer.ts            XML 回写（保留原始格式）
|   |   |   |-- scanner.ts               目录扫描 + 文件分类
|   |   |   |-- tier-resolver.ts         多阶继承展开 (data -> data_2/3/4)
|   |   |   |-- field-classifier.ts      自动字段分类
|   |   |   +-- index.ts
|   |   |-- tests/
|   |   +-- package.json
|   |
|   |-- excel-io/                    <-- Excel 导入导出（仅迁移期）
|   |   |-- src/
|   |   |   |-- importer.ts
|   |   |   |-- exporter.ts
|   |   |   +-- index.ts
|   |   +-- package.json
|   |
|   |-- cli/                         <-- CLI（Agent 调用层）
|   |   |-- src/
|   |   |   |-- commands/
|   |   |   |   |-- project.ts           open / list / scan / fields
|   |   |   |   |-- calc.ts              全量计算
|   |   |   |   |-- query.ts             查询 item/mod
|   |   |   |   |-- edit.ts              修改字段值
|   |   |   |   |-- diff.ts              版本对比
|   |   |   |   |-- validate.ts          数据校验
|   |   |   |   |-- rebalance.ts         执行平衡规则
|   |   |   |   |-- calibrate.ts         Excel 基准对比
|   |   |   |   |-- import-excel.ts      legacy 导入
|   |   |   |   +-- export.ts            导出
|   |   |   +-- index.ts
|   |   +-- package.json
|   |
|   +-- web/                         <-- Electron + React + Vite
|       |-- src/
|       |   |-- main/                    Electron 主进程
|       |   |-- renderer/                React 渲染进程
|       |   |   |-- App.tsx
|       |   |   |-- components/
|       |   |   |   |-- DataGrid/        表格编辑
|       |   |   |   |-- FormulaBar/      公式预览
|       |   |   |   |-- TierView/        多阶数据展示
|       |   |   |   |-- DiffViewer/      版本对比
|       |   |   |   |-- ValidationPanel/ 校验面板
|       |   |   |   +-- Sidebar/         文件/品类导航
|       |   |   +-- hooks/
|       |   +-- preload/
|       +-- package.json
|
|-- data/                            <-- 工具自身数据
|   |-- field-config.json
|   |-- formula-config.json
|   +-- changelog/
|
|-- baseline/                        <-- Excel 校准基准
|   |-- baseline-extracted.json          已提取（随项目提供）
|   +-- 武器-技能数值-价格-合成表.xlsx    原始 Excel
|
|-- package.json                     pnpm workspace root
|-- tsconfig.json
+-- vitest.config.ts
```

### 2.3 关键设计决策

#### 2.3.1 分层 XML 解析器（非单一 adapter）

不同品类的 XML 结构不同，需要分层解析：

```typescript
// packages/xml-io/src/parsers/equipment-parser.ts

interface EquipmentItem {
  sourceFile: string;
  /** XML 内 <name> 值，作为唯一标识 */
  id: string;
  meta: {
    displayname: string;
    type: '武器' | '防具';
    use: string;         // 手枪 / 头部装备 / ...
    price: number;
    description: string;
    weapontype?: string; // 仅枪械：压制机枪/霰弹枪/...
    helmet?: boolean;
    actiontype?: string;
  };
  /** 基础阶数值（data 节点展平） */
  baseData: Record<string, unknown>;
  /** 多阶数值（已做继承展开）- 仅防具和部分刀 */
  tierData: Record<string, Record<string, unknown>>[];
  /** magicdefence 单独提取 */
  magicDefence: Record<string, number>;  // { 蚀: 10, ... }
  /** 多阶 magicDefence */
  tierMagicDefence: Record<string, number>[];
  /** lifecycle 原样保留 */
  lifecycleRaw: string;
  /** skill 原样保留 */
  skillRaw?: string;
  /** 其他未识别节点原样保留 */
  extraRaw: Record<string, string>;
}

// packages/xml-io/src/parsers/mod-parser.ts

/** 六种运算符的统一容器 */
interface StatsBlock {
  percentage?: Record<string, number>;
  multiplier?: Record<string, number>;
  flat?: Record<string, number>;
  override?: Record<string, unknown>;
  merge?: Record<string, unknown>;
  cap?: Record<string, number>;
  /** 条件性 provideTags（仅 useSwitch 分支内有效） */
  provideTags?: string[];
}

/** Switch 分支 */
interface SwitchBranch {
  name?: string;  // 省略 name = default 分支
  stats: StatsBlock;
}

interface ModItem {
  sourceFile: string;
  name: string;
  use: string[];                    // 适用装备类型列表
  stats: StatsBlock & {
    useSwitch?: SwitchBranch[];     // 按装备 use/weapontype 条件分支
    tagSwitch?: SwitchBranch[];     // 按 presentTags 条件分支
    bulletSwitch?: SwitchBranch[];  // 按子弹类型条件分支
  };
  description: string;
  tag?: string;                     // 互斥挂点标签
  weapontype?: string[];            // 白名单：限定武器子类
  excludeWeapontype?: string[];     // 黑名单：排除武器子类
  excludeBulletTypes?: string[];    // 子弹类型排斥(pierce/melee/chain/...)
  requireBulletTypes?: string[];    // 子弹类型要求
  installCondition?: unknown;       // 12种运算符的属性条件树
  requireTags?: string[];           // 结构依赖标签
  provideTags?: string[];           // 提供的结构标签
  grantsWeapontype?: string;        // 授予武器类型
  detachPolicy?: 'cascade';         // 拆卸策略
  skill?: unknown;                  // 赋予技能(skillname/cd/mp)
  /** 其他未识别节点原样保留 */
  extraRaw: Record<string, string>;
}

// packages/xml-io/src/parsers/consumable-parser.ts

interface ConsumableItem {
  sourceFile: string;
  id: string;
  meta: {
    displayname: string;
    type: '消耗品';
    use: string;  // 药剂/弹夹/手雷/...
    price: number;
    description: string;
  };
  effects: Array<{type: string; [key: string]: unknown}>;
  extraRaw: Record<string, string>;
}
```

#### 2.3.2 字段分类注册表（数据驱动）

```jsonc
// data/field-config.json
{
  "numericFields": [
    "level", "weight", "price", "hp", "mp", "damage", "defence",
    "power", "interval", "capacity", "split", "diffusion", "velocity",
    "bulletsize", "impact", "evasion", "accuracy", "knifepower",
    "gunpower", "punch", "force", "vampirism", "toughness",
    "reloadPenalty", "criticalhit", "modslot",
    "slay", "bladeCount", "rout", "lazymiss", "weightlevel"
  ],
  "stringFields": [
    "damagetype", "magictype"
  ],
  "passthroughFields": [
    "dressup", "bullet", "bulletrename", "sound", "muzzle",
    "bullethit", "clipname", "singleshoot", "reloadType"
  ],
  "nestedNumericFields": ["magicdefence", "skillmultipliers"],
  "magicElements": ["蚀", "毒", "冷", "热", "电", "波", "冲", "全属性", "基础", "原体"],
  "itemLevelFields": ["inherentTags", "blockedTags"]
}
```

#### 2.3.3 多阶继承展开

```typescript
// data_2 只覆盖变化字段，其余继承 data
// 展开后每个 tier 都是完整字段集
// 注意：仅防具和武器_刀_重斩有多阶，枪械无多阶

function resolveTier(baseData: Record<string, unknown>,
                     tierData: Record<string, unknown>): Record<string, unknown> {
  return { ...baseData, ...tierData };
}
```

#### 2.3.4 XML 回写保留格式

使用 fast-xml-parser 的 `preserveOrder` 模式解析，修改目标字段值后原样序列化。
关键：不能改变节点顺序、不能丢失注释、不能改变缩进风格。

#### 2.3.5 公式引擎与 XML 的关系

```
XML item (baseData) -> 提取 balance-relevant 字段 -> 公式引擎计算 -> 输出参考值
                                                                      |
                                                              不回写 XML
                                                              仅用于 GUI 展示和平衡决策
```

公式引擎计算的 DPS 等值是**参考指标**，不写入 XML。
实际修改 XML 的是用户/Agent 对 baseData 字段的直接编辑。

#### 2.3.6 校准策略

```
Excel 缓存值 -> baseline.json -> 校准测试 -> 逐公式对比 -> 标记偏差
```

```typescript
describe('weapons calibration', () => {
  // baseline 约 10 行有效数据（排除注释行 input 全为 null 的）
  const dataRows = baseline.weapons.filter(r => r.input['子弹威力'] != null);
  for (const row of dataRows) {
    it(`${row.input['具体武器']}`, () => {
      const computed = computeWeaponRow(row.input);
      expect(computed.averageDPS).toBeCloseTo(row.cached['平均dps'], 2);
      // 逐列断言...
    });
  }
});
```

---

## 3. CLI 接口设计

### 3.1 项目管理

```bash
# 打开项目（扫描多个 XML 目录）
npx cf7-balance project open --items ../../data/items --mods ../../data/items/equipment_mods

# 列出发现的文件和物品
npx cf7-balance project list
# -> 防具_20-39级.xml: 86 items (防具)
# -> 武器_手枪_压制机枪.xml: 2 items (武器/手枪)
# -> equipment_mods/高等材料_枪械专用.xml: 9 mods (插件)
# -> ...

# 扫描字段使用情况
npx cf7-balance project fields
# -> 发现 42 个数值字段，3 个未分类字段
```

### 3.2 查询与编辑

```bash
# 查询单个物品
npx cf7-balance query --name "XM556-H-Stinger"
# -> 输出 JSON（含 baseData + 计算参考值）

# 按条件查询
npx cf7-balance query --type 防具 --use 头部装备 --level-range 20-35

# 查询插件
npx cf7-balance query --mod --name "增效剂"

# 编辑字段
npx cf7-balance edit --name "XM556-H-Stinger" --set "power=50" --set "interval=180"

# 批量编辑
npx cf7-balance edit --type 武器 --use 手枪 --set "power*=1.1"
```

### 3.3 计算与平衡

```bash
# 全量计算（输出参考指标）
npx cf7-balance calc --output /tmp/balance-report.json

# 执行平衡规则
npx cf7-balance rebalance --rule align-dps \
  --params '{"target":"rifle","ratio":0.8,"scope":"shotgun"}' \
  --dry-run

# 查看变更
npx cf7-balance diff --before snapshot-v1.json --after snapshot-v2.json

# 校验
npx cf7-balance validate
```

### 3.4 导入导出

```bash
# Legacy: Excel -> baseline
npx cf7-balance import-excel --input baseline/武器-技能数值-价格-合成表.xlsx \
  --output baseline/baseline-extracted.json

# 导出快照
npx cf7-balance export --format json --output snapshot.json
```

---

## 4. 数据格式

### 4.1 项目配置（project.json）

```jsonc
{
  "version": "1.0.0",
  "dataDirs": {
    "items": "../../data/items",
    "mods": "../../data/items/equipment_mods",
    "enemies": "../../data/enemy_properties"  // P3 延后
  },
  "fieldConfig": "data/field-config.json",
  "formulaConfig": "data/formula-config.json"
}
```

### 4.2 baseline.json 结构

包含 9 个 section + damageFormula 验证数据：

| Section | 有效数据行 | 输入列 | 计算列 |
|---------|-----------|--------|--------|
| weapons | ~10 | 14(示例类型->额外加权层数) | 25(平均dps->周期dps系数) |
| armor | ~8 | 11(类型->额外加权层数) | 5(当前总分->法抗最高上限) |
| monsters | 6 | 11(名称->高防低血系数) | 10(攻击MIN->K点价格) |
| melee | 2 | 6(名称->加权层数) | 1(推荐锋利度) |
| explosives | 2 | 6(名称->加权层级) | 1(推荐单发威力) |
| equipmentPrices | ~2 | 7(类型->伤害类型系数) | 3(金币/K点/换算比例) |
| synthesis | ~1 | 9(类型->掉落物折算价格) | 5(装备折算->列2) |
| dungeonRewards | 4 | 9(名称->强化石) | 3(当前/期望收益) |
| potions | 6 | 14(名称->buff-持续帧) | 11(hp->原始推荐价格) |
| damageFormula | ~15 | 4(E/R/伤害/T) | 14(C~W列) |

> 注意：baseline 中部分行的 input 全为 null，这些是注释/设计规则行，校准时应过滤。

### 4.3 Changelog

```jsonc
{
  "timestamp": "2026-03-06T12:00:00Z",
  "author": "agent",
  "description": "批量调整手枪 power +10%",
  "changes": [
    {
      "file": "武器_手枪_压制机枪.xml",
      "itemId": "XM556-H-Stinger",
      "field": "data.power",
      "oldValue": 40,
      "newValue": 44,
      "reason": "rule:scale-by-ratio"
    }
  ]
}
```

---

## 5. 分阶段实施计划

### Phase 0: 骨架 + 字段报告（Day 1）

**目标**: monorepo 能跑通测试；字段使用报告生成。

1. 初始化 pnpm workspace + TS strict + Vitest
2. 扫描 `data/items/` 全量 XML，统计所有字段、所有 type/use 值，生成字段使用报告
3. baseline.json 已在 `baseline/` 目录（无需复制）
4. 建立 Zod schema 骨架（equipment/consumable/mod 三层）

**验收**: `npm test` 通过；字段使用报告生成。

### Phase 1: XML 读写层（Day 2-3）

**目标**: 能正确解析和回写所有 XML，不丢失任何信息。

1. 装备解析器 equipment-parser.ts（武器+防具 `<item>`)
2. 消耗品解析器 consumable-parser.ts
3. 插件解析器 mod-parser.ts（`<mod>` 格式）
4. 多阶继承展开（仅防具和武器_刀_重斩需要）
5. XML 回写（round-trip 测试：解析 -> 序列化 -> 与原文件 diff 无变化）
6. 目录扫描器（识别 item/mod/consumable 三种格式）

**验收**: 所有 XML 文件 round-trip 无 diff；`project list` 输出正确。

### Phase 2: 枪械计算内核 + 校准（Day 4-5）

**目标**: 枪械 25 个计算列通过校准。

1. 翻译枪械表全部公式到 `formulas/weapons.ts`
2. 校准测试：~10 行有效数据 x 25 列 vs baseline
3. 目标校准通过率 > 90%

**验收**: 校准测试通过率 > 90%。

### Phase 3: 其余公式模块（Day 6-8）

**P1 批次**（Day 6-7）：
- 防具总分（armor.ts）：加权总分模型，~8 行校准
- 近战锋利度（melee.ts）：2 行校准
- 爆炸类（explosives.ts）：2 行校准
- 装备价格（economy.ts）
- 伤害减免（damage.ts）

**P2 批次**（Day 8）：
- 合成/副本收益（economy.ts 续）
- 药剂（potions.ts）：6 行校准

**验收**: 所有模块校准 > 85%。

### Phase 4: CLI 完善 + 规则系统（Day 9-10）

1. CLI 全部命令（含 mod 查询/编辑）
2. 2-3 个内置规则
3. diff + changelog
4. XML 回写集成

**验收**: Agent 能纯 CLI 完成完整操作流程。

### Phase 5: Electron 前端（Day 11-14）

1. Electron + Vite + React 骨架
2. DataGrid / FormulaBar / TierView / DiffViewer
3. 插件 CRUD 界面
4. 文件/品类导航

**验收**: Electron 桌面应用可编辑数据并保存回 XML。

### Phase 6: 打磨（Day 15+）

- 校准偏差修复
- UI 美化
- 撤销/重做
- 怪物属性支持（P3）
- 文档

---

## 6. 附件清单

随本规格书一同提供（位于 `baseline/` 目录）：

| 文件 | 说明 |
|------|------|
| `baseline/baseline-extracted.json` | 9 个 section + damageFormula 的校准基准 |
| `baseline/武器-技能数值-价格-合成表.xlsx` | 原始 Excel 文件 |

调研报告：

| 文件 | 说明 |
|------|------|
| `CF7-BalanceTool-Investigation-Report.md` | Q1-Q25 完整结论 + 错误修正清单 |

仓库中的相关设计资源（供公式翻译参考）：

| 文件 | 位置 | 用途 |
|------|------|------|
| 消耗品_药剂.md | data/items/ | **药剂数值理论**(437行)：StdHP体系/CD补偿/品类配额/buff计算类型 |
| equipment_mods/README.md | data/items/equipment_mods/ | **插件系统完整规格**(1081行)：6运算符/3Switch/安装条件/Tag依赖/命中率模型 |
| 插件数值设计讨论.md | data/items/ | 插件机制设计（百分比/固定/覆盖算子） |
| 射线插件数值建模_2026-02.md | data/items/equipment_mods/ | 射线数值模型(495行) |
| 插件获取途径审阅报告.md | data/items/equipment_mods/ | 插件掉落/获取设计 |
| weapon_weighting_workflow.md | data/items/ | 武器加权工作流 + DPS公式 + weightlevel规范(226行) |
| weapon_classification_workflow.md | data/items/ | 武器分类工作流 |
| weapon_weighting_log.md | data/items/ | 武器加权标注日志 |
| EquipmentUtil.as | scripts/.../item/ | 强化查找表(levelStatList) + 插件计算(calculateData) |
| DamageResistanceHandler.as | scripts/.../StatHandler/ | 核心减伤公式 `300/(defense+300)` |
| DamageCalculator.as | scripts/.../Damage/ | 伤害管线 |
| BuffCalculator.as | scripts/.../Buff/ | Buff 计算（非强化公式） |

---

## 7. Agent 执行入口

```bash
# Step 1: 进入项目目录
cd tools/cf7-balance-tool

# Step 2: 初始化
pnpm init
# 配置 workspace, tsconfig, vitest...

# Step 3: 按 Phase 0 -> 5 顺序推进
# 每完成一个 Phase 跑 npm test 确认

# Step 4: 遇到校准偏差时
# 标记具体公式和偏差值，不要卡在单个公式上
# 用 CALIBRATION_TODO 注释标记，继续推进

# Step 5: 插件/bullets_cases 仅实现 CRUD
# 不做公式计算，等待后续数值理论指导
```
