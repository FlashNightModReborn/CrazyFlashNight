# 装备配件模组配置目录

本目录采用 list + 子文件结构，便于维护和协作开发。

---

## 📁 文件结构

```
equipment_mods/
├── list.xml          # 主列表文件，列出所有子配件文件
├── README.md         # 本说明文件
└── all_mods.xml      # 所有配件数据（当前单文件，后续可拆分）
```

---

## 🔄 加载流程

1. `EquipModListLoader` 读取 `list.xml`
2. 根据 `list.xml` 中的 `<items>` 列表逐个加载子文件
3. 合并所有子文件中的 `<mod>` 节点
4. 传递给 `EquipmentUtil.loadModData()` 进行初始化

---

## 📖 配置语法完整说明

> **注意：** 如需了解如何在佣兵装备上配置插件，请参阅：`data/merc/mercenaries_README.md`

---

### 【六种核心运算符】

#### 1. flat - 固定值加成

**运算方式：** 直接加法（原值 + 固定值）

**示例：**
```xml
<stats>
    <flat>
        <defence>8</defence>        <!-- 防御力 +8 -->
        <hp>10</hp>                 <!-- 生命值 +10 -->
        <weight>2</weight>          <!-- 重量 +2 -->
    </flat>
</stats>
```

**用途：** 增加绝对数值，适用于基础属性提升

---

#### 2. percentage - 百分比加成

**运算方式：** 乘法（原值 × (1 + 百分比)）

**示例：**
```xml
<stats>
    <percentage>
        <power>5</power>            <!-- 威力 +5%，XML中数字5代表5% -->
        <defence>10</defence>       <!-- 防御 +10% -->
        <weight>-20</weight>        <!-- 重量 -20%，负数表示减少 -->
    </percentage>
</stats>
```

**注意：** XML中的数字会自动除以100转换为小数（5 → 0.05）

**用途：** 按比例提升或削弱属性

---

#### 3. override - 覆盖值

**运算方式：** 直接替换（原值 = 新值）

**示例：**
```xml
<stats>
    <override>
        <actiontype>狂野</actiontype>              <!-- 攻击类型改为"狂野" -->
        <damagetype>破击</damagetype>              <!-- 伤害类型改为"破击" -->
        <magictype>电</magictype>                  <!-- 魔法属性改为"电" -->
        <criticalhit>20</criticalhit>              <!-- 暴击率设为20 -->
        <criticalhit>满血暴击</criticalhit>        <!-- 暴击条件设为特殊机制 -->
        <modslot>3</modslot>                       <!-- 配件槽数量改为3 -->
        <skillmultipliers>                         <!-- 技能倍率覆盖 -->
            <瞬步斩>2.5</瞬步斩>                   <!-- 瞬步斩锋利度倍率=250% -->
        </skillmultipliers>
    </override>
</stats>
```

**用途：** 改变装备的本质属性，无视之前的计算结果

**注意：** override是浅层覆盖，会完全替换整个对象。对于嵌套对象（如magicdefence），建议使用merge运算符

---

#### 4. merge - 深度合并（推荐用于嵌套对象）

**运算方式：** 递归深度合并 + 智能数值合并

**合并规则：**
- 遇到不存在的键：直接添加
- 遇到已存在的键：
  * 如果是对象：递归合并（不覆盖整个对象）
  * 如果是数字：
    - 有负数存在：取最小值（保留最不利的debuff）
    - 都是正数：取最大值（保留最有利的buff）
  * 如果是字符串：直接覆盖

**示例：**
```xml
<stats>
    <merge>
        <magicdefence>                         <!-- 深度合并魔法防御 -->
            <热>-8</热>                        <!-- 只修改热抗，不影响其他抗性 -->
        </magicdefence>
        <skillmultipliers>                     <!-- 深度合并技能倍率 -->
            <瞬步斩>2.5</瞬步斩>               <!-- 只修改瞬步斩，不影响其他技能 -->
        </skillmultipliers>
    </merge>
</stats>
```

**使用场景：**
- magicdefence（魔法防御）：多个配件修改不同的抗性
- skillmultipliers（技能倍率）：多个配件影响不同的技能

**对比示例：**
```
装备基础属性：magicdefence: {冷:5, 热:10, 电:8}

使用 override（问题）：
<override><magicdefence><热>-8</热></magicdefence></override>
结果：magicdefence: {热:-8}  ❌ 丢失了冷和电

使用 merge（正确）：
<merge><magicdefence><热>-8</热></magicdefence></merge>
结果：magicdefence: {冷:5, 热:-8, 电:8}  ✅ 只改热抗，其他保留
```

**多配件叠加示例：**
```
装备基础：    magicdefence: {冷:0, 热:0, 电:0}
+ 配件A：     merge: {magicdefence: {热:5, 蚀:5}}
+ 配件B：     merge: {magicdefence: {热:-8}}
+ 配件C：     merge: {magicdefence: {冷:5, 电:10}}
最终结果：    {冷:5, 热:-8, 电:10, 蚀:5}
（热有负数-8和正数5，取最小值-8；冷、电、蚀只有正数，直接合并）
```

**用途：** 处理嵌套对象的部分更新，避免数据丢失

---

#### 5. multiplier - 独立乘区百分比（高级数值控制）

**运算方式：** 每个配件独立乘法（原值 × Π(1 + 百分比)）

**示例：**
```xml
<stats>
    <multiplier>
        <power>15</power>            <!-- 威力增幅，显示为 ×+15% -->
        <defence>20</defence>        <!-- 防御增幅，显示为 ×+20% -->
        <power>-35</power>           <!-- 威力削弱，显示为 ×0.65（倍率形式） -->
    </multiplier>
</stats>
```

**注意：**
- XML中的数字会自动除以100转换为小数（15 → 0.15）
- 正数显示为百分比形式（×+15%）
- 负数显示为倍率形式（×0.65），更直观地表示削弱效果

**与 percentage 的区别：**

| 运算符 | percentage（加法合并乘区） | multiplier（独立乘区） |
|--------|---------------------------|----------------------|
| **运算方式** | 所有百分比和强化倍率以"加法"累加到一个乘区 | 每个配件的百分比独立作为一个乘区 |
| **公式** | 最终倍率 = 1 + (强化倍率-1) + Σ百分比 | 最终倍率 = Π(1 + 单个百分比) |
| **特点** | 线性增长，抑制数值膨胀 | 乘法增长，更强大的数值控制 |
| **适用场景** | 常规属性提升 | 高级/稀有配件的特殊增幅 |

**实际计算示例：**

假设基础威力100，强化Lv13（倍率3.04）：

```
配件A：percentage.power = 20
配件B：percentage.power = 10
配件C：multiplier.power = 15
配件D：multiplier.power = 10

计算过程：
1. percentage阶段（加法合并）：
   倍率 = 1 + (3.04-1) + (0.20+0.10) = 3.34
   结果 = 100 × 3.34 = 334

2. multiplier阶段（独立乘区）：
   倍率 = (1+0.15) × (1+0.10) = 1.15 × 1.10 = 1.265
   结果 = 334 × 1.265 = 422.51 ≈ 423

最终威力：423

对比：如果全用percentage（加法合并）= 100 × (1+2.04+0.20+0.10+0.15+0.10) = 359
```

**用途：** 为高级配件提供更强的增幅效果，同时保持数值可控性

---

#### 6. cap - 上限/下限值

**运算方式：**
- 正数：增益上限（相对基础值，最多增加这么多）
- 负数：减益下限（相对基础值，最多减少这么多）

**示例：**
```xml
<stats>
    <cap>
        <capacity>50</capacity>     <!-- 弹匣容量增益上限 +50 -->
    </cap>
</stats>
```

**特点：**
- 多个配件的cap值会叠加
- 基于基础值计算变化量，防止属性过度膨胀

**用途：** 平衡性控制，防止某些属性过高或过低

---

### 【运算顺序与优先级】

计算严格按照以下顺序执行（代码位置：`EquipmentUtil.as` calculateData方法）：

```
1. percentage（百分比）   ← 优先级最高，先计算（加法合并乘区）
    ↓
2. multiplier（独立乘区） ← 在percentage之后应用（乘法增幅）
    ↓
3. flat（固定值）
    ↓
4. override（覆盖）
    ↓
5. merge（深度合并）
    ↓
6. cap（上限限制）        ← 优先级最低，最后执行
```

**为什么这样排序？**
- percentage先行：基于基础值和强化等级计算百分比增幅（加法合并，抑制膨胀）
- multiplier次之：在percentage基础上应用独立乘区（乘法增幅，精细控制）
- flat再次：在所有百分比计算后加固定值
- override覆盖：可以完全改变前面的计算结果，用于改变本质属性
- merge合并：深度合并嵌套对象，在override之后避免被覆盖影响
- cap兜底：作为最后的安全阀，防止数值异常

---

### 【实际计算示例】

假设一把枪基础威力100，装了3个配件：

```
配件1 - 弹簧：        percentage的power为5
配件2 - 螺丝套件：    flat的power为8
配件3 - 非栓式机构：  percentage的power为-35

计算过程：
  1. percentage阶段：100 × (1 + 0.05 - 0.35) = 100 × 0.7 = 70
  2. flat阶段：      70 + 8 = 78
  3. override阶段：  无override，跳过
  4. cap阶段：       检查是否超出上限（本例无威力cap）

最终威力：78
```

---

### 【其他重要标签说明】

#### tag - 插件位置标签
**作用：** 同tag的插件不能同时装备（互斥机制）
**示例：** 柄尾、枪机、表面涂层 等

#### use - 适用装备类型
**示例：** 头部装备,上装装备,下装装备,刀,手枪,长枪

#### weapontype - 武器子类限制
**示例：** 突击步枪,冲锋枪 - 仅适用于这些子类武器

#### grantsWeapontype - 授予武器类型
**作用：** 让装备可以安装其他子类的配件
**示例：** 突击步枪

#### detachPolicy - 拆卸策略
**cascade：** 拆卸时会级联影响依赖此配件的其他配件
**示例：** 拆卸扩展配件槽的配件时，会同时卸下多余槽位的配件

#### skill - 赋予技能
为装备添加主动或被动技能
**包含：** skillname（技能名）、cd（冷却）、mp（消耗）等

#### provideTags - 结构支持标签
**作用：** 插件安装后提供的"结构能力"，用于满足其他插件的 requireTags
**特点：** 只提供结构，不占挂点（与 tag 不同，tag 会占用挂点位置）
**示例：** `<provideTags>电力,高级电力</provideTags>`

#### requireTags - 结构依赖标签
**作用：** 插件安装前必须已存在的结构标签
**判定：** 只看结构是否存在（由装备 inherentTags + 其他插件 provideTags 共同决定）
**限制：** 不满足时 UI 不会列出 / 安装返回错误码 -16

---

### 【useSwitch - 按装备类型追加效果（条件分支机制）】

**作用：** 让配件对不同类型的装备产生不同的效果

**基本结构：**
```xml
<stats>
    <percentage>...</percentage>   <!-- 基础效果：对所有装备生效 -->

    <useSwitch>                    <!-- 条件效果：满足条件时追加 -->
        <use name="装备类型1">
            <multiplier>...</multiplier>
            <percentage>...</percentage>
        </use>
        <use name="装备类型2,装备类型3">
            <flat>...</flat>
        </use>
    </useSwitch>
</stats>
```

**语义说明：**
- 顶层stats：对所有装备统一生效的基础效果
- useSwitch内的分支：当装备类型匹配时，追加执行（而非替换）
- 分支内可使用所有运算符（percentage、multiplier、flat、override、merge、cap）

**匹配规则：**
- 分支的name与装备的use或weapontype字段进行匹配
- name支持多个类型，用逗号分隔（如 "发射器,榴弹发射器"）
- 装备的use/weapontype也可能是多值（如 use="步枪,发射器"）
- 只要分支name与装备use/weapontype有任一相同，分支就会生效
- 多个分支可以同时生效（按XML顺序累加效果）

**实际示例：**
```
非栓式机构对所有武器 -35% 威力（percentage）
但对发射器类武器额外再 -10% 威力（multiplier）
最终发射器装备此配件时威力计算：
  base × (1 + 强化倍率 - 0.35) × 0.9
```

**适用场景：**
- 让配件对特定武器类型有额外加成或惩罚
- 实现"专精"型配件（对某类武器效果更好）
- 平衡不同武器类型的配件效果

---

### 【Tag 依赖系统】

Tag 依赖系统允许插件之间建立前置要求关系，实现更复杂的装备改造逻辑。

**核心概念：**
```
presentTags（当前可用结构）= 装备 inherentTags + 已安装插件的 provideTags
依赖检查：插件的 requireTags 必须是 presentTags 的子集才能安装
```

**工作流程：**
1. 装备可能自带 inherentTags（如 M4A1战术版 自带"枪口,弹匣,下导轨,瞄具"）
2. 已安装的插件通过 provideTags 提供额外结构（如可充锂电池提供"电力"）
3. 新插件的 requireTags 检查当前是否满足（如电脑芯片需要"电力"）
4. 满足则可安装，不满足则 UI 过滤掉 / 安装返回错误码 -16

**依赖链示例：**
```
可充锂电池 → 提供"电力" → 电脑芯片（需要"电力"）→ 安装成功
纳米执行单元 → 提供"电力,高级电力" → 高级传感器（需要"高级电力"）
```

**级联卸载：**
当移除提供关键 provideTags 的插件时，系统会检查是否有其他插件依赖它
如有依赖，会提示用户并自动级联卸载所有依赖的插件

**与装备标签的关系：**
装备 XML（如 `data/items/武器_长枪.xml` 第3895行）可定义：
- **inherentTags（固有结构）：** 被 EquipmentUtil.buildTagContext 视为 presentTags
- **blockedTags（禁止挂点）：** 限制特定 tag 的插件安装（错误码 -64）

相关代码：`scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as` 第480-692行

---

### 【特殊机制】

#### 1. 小数处理规则：
- weight（重量）、rout、vampirism：保留1位小数
- 其他属性：四舍五入取整

#### 2. 多配件叠加：
- 同类型运算符的值会累加
- 例如2个配件都有 flat的defence为20，最终是 +40 防御

#### 3. 负数的含义：
- percentage中的负数：削弱属性（如 power为-35 表示威力 -35%）
- flat中的负数：减少属性（如 accuracy为-10 表示精准 -10）

#### 4. 相关代码文件：
- **主计算逻辑：** `scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as`
- **Buff计算系统：** `scripts/类定义/org/flashNight/arki/component/Buff/BuffCalculator.as`
- **显示逻辑：** `scripts/类定义/org/flashNight/gesh/tooltip/TooltipTextBuilder.as`

---

## 🚀 未来拆分建议

当配件数量增多后，可以按以下方式拆分子文件：

- `防具_通用改造.xml` - 布料/金属/涂层类
- `防具_电子系统.xml` - 电力/芯片/传感器类
- `近战_柄部组件.xml` - 柄芯/柄尾/柄侧/握柄核心
- `近战_刀身改造.xml` - 护手/刀身/刃面
- `枪械_核心组件.xml` - 枪机/枪管/弹匣/枪口
- `枪械_导轨系统.xml` - 导轨/瞄具/握把/侧导轨
- `枪械_下挂武器.xml` - M203/霰弹枪/微型导弹/铁血肩炮
- `特殊_属性改造.xml` - 毒素/魔法/月之碎片/成长勋章

拆分后记得更新 `list.xml` 中的文件列表。

---

## ⚠️ 注意事项

1. 所有 XML 文件必须使用 **UTF-8** 编码
2. 每个子文件必须包含 `<root>` 根节点
3. 配件节点统一使用 `<mod>` 标签
4. 单个配件时 XMLParser 会返回对象，多个配件时返回数组（加载器已自动处理）
5. 修改后重启游戏生效，会在启动时看到加载日志

---

## 📚 相关文件

- **加载器实现：** `scripts/类定义/org/flashNight/gesh/xml/LoadXml/EquipModListLoader.as`
- **数据处理：** `scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as`
- **启动调用：** `scripts/asLoader/LIBRARY/asLoader.xml` (第596行)
- **佣兵配置参考：** `data/merc/mercenaries_README.md`
