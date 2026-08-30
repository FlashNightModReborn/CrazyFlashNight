# 装备配件模组配置目录

本目录采用 list + 子文件结构，便于维护和协作开发。

---

## 📁 文件结构

```
equipment_mods/
├── list.xml                # 主列表文件，列出所有材料档级/用途子文件与展示词典
├── ui_presentation.xml     # 档级/目录用途/角色的受控显示词典
├── 低级材料_*.xml          # 低级插件定义
├── 中等材料_*.xml          # 中等插件定义
├── 高等材料_*.xml          # 高等插件定义
├── 特殊材料_*.xml          # 特殊插件定义
└── README.md               # 本说明文件
```

---

## 🔄 加载流程

1. `EquipModListLoader` 读取 `list.xml`
2. 并行加载 `list.xml/<uiPresentation>` 与 `<items>` 子文件
3. 从每个子文件根层读取 `modGrade/catalogScope`，再用展示词典解析档级色、用途名与 `uiRole/uiSymbol`
4. 合并所有子文件中的 `<mod>` 节点
5. 将已带展示元数据的插件数组传递给 `EquipmentUtil.loadModData()` 初始化

---

## 📖 配置语法完整说明

> **注意：** 如需了解如何在佣兵装备上配置插件，请参阅：`data/merc/mercenaries_README.md`

---

### 【插件格展示元数据】

插件格使用四档固定标准色：低级 `#006600`、中等 `#996600`、高等 `#0099FF`、特殊 `#FFFF00`。这些颜色只驱动暗色金属槽内的角色符号与短辉光，不对整个插件槽填色。每个插件子文件必须在 `<root>` 下显式声明一次档级与目录用途，文件名只服务人类导航，不再参与运行时推断：

```xml
<root>
    <modGrade>high</modGrade>
    <catalogScope>blade</catalogScope>
    <mod>...</mod>
</root>
```

`modGrade` 仅允许 `low|medium|high|special`；`catalogScope` 仅允许 `armor|firearm|blade|fist|universal|underbarrel`。目录用途是 Web 候选浏览维度，不是安装权限；真正能否安装仍由每个 `<mod>` 的精确 `use/weapontype/excludeWeapontype` 及 `EquipmentUtil` 裁决。

`ui_presentation.xml` 只维护 `modGrade/catalogScope/uiRole` ID 的标签、色号、受控符号和 `tag` 默认角色，不重新分配某个插件属于哪一档或哪类。解析顺序为：插件显式 `<uiRole>` → `tagDefault`；未知用途、角色、符号、档级或未覆盖的 `tag` 会让加载/构建审计失败。符号 token 由形状与填充方式组成，白名单为 `triangle|square|circle|diamond|star` × `solid|outline`，例如火力使用 `triangle-solid`（▲）、精准与操控使用 `triangle-outline`（△）。稳定与防护、续航、结构与功能分别使用线框方形、圆形、菱形，特殊机制保留实心星。Web 使用 CSS 图形渲染，不直接执行 XML 中的任意 Unicode 或 HTML。

`data/items/收集品_材料_插件.xml` 以及 `收集品_材料.xml` 中的四个特殊材料仍只负责库存、经济、图标与说明，不重复维护档级/用途/定位。审计要求 105 个 mod 名称各自唯一对应一个物品条目，并要求 `收集品_材料_插件.xml` 的 101 个条目全部存在 mod 定义。

`<mod><name>` 是安装、库存与规则的稳定内部键，允许与物品条目的 `<displayname>` / `<icon>` 不同。装备调制 snapshot 必须同时投影 `itemName/displayName/icon`，Web 只用 `itemName` 发起操作，用后两者显示文案与图标。`node tools/audit-web-item-icon-closure.js` 会按 `equipment_mods/list.xml` 全量核对 mod 物品、manifest 键与实际图片文件闭包。

一般插件不需要重复声明角色；只有 `tag` 默认角色无法准确表达主要功能时才覆盖：

```xml
<mod>
  <name>示例插件</name>
  <use>长枪,手枪</use>
  <tag>枪口</tag>
  <uiRole>firepower</uiRole>
  <stats>...</stats>
</mod>
```

修改插件文件、展示词典或 `list.xml` 后运行：

```powershell
node tools/validate-equipment-mod-ui.js
```

该审计也已接入 `launcher/build.ps1`，会验证所有插件都能解析出档级、目录用途、角色和受控符号，并验证 mod↔材料物品唯一映射。

---

### 【七种基础运算符与两种覆盖级别】

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

#### 3A. softOverride / lockOverride - 确定性覆盖级别

二者与 `override` 一样是浅层覆盖，但解决多个插件改写同一多义字段时的槽位顺序依赖：

- `softOverride`：覆盖宿主原值，但一定让位于任意普通 `override`。适合“先设一个基础暴击档，之后允许专用暴击插件替换”。
- `lockOverride`：在普通 `override` 与 `merge` 之后最终生效。适合“锁定物理伤害类型”这类不可被同构插件改回的契约。

```xml
<stats>
    <softOverride>
        <criticalhit>10</criticalhit> <!-- 原生暴击先改为10；暴击镜仍可覆盖 -->
    </softOverride>
    <lockOverride>
        <damagetype>物理</damagetype> <!-- 不受插件数组遍历顺序影响 -->
    </lockOverride>
</stats>
```

同一级别内若多个插件覆盖同一字段，仍沿用既有 XML/插件数组顺序；需要跨插件确定性时应选不同级别或通过 `tag` 互斥，不得依赖玩家调整槽位顺序。

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
  * 如果是字符串：前缀保留拼接（通用规则，见下方说明）
  * 其他类型：直接覆盖

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
        <bullet>次级穿刺子弹</bullet>          <!-- 智能替换子弹类型（保留联弹前缀） -->
    </merge>
</stats>
```

**使用场景：**
- magicdefence（魔法防御）：多个配件修改不同的抗性
- skillmultipliers（技能倍率）：多个配件影响不同的技能
- bullet（子弹类型）：联弹格式的智能合并

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

**【字符串前缀保留拼接：通用规则】**

merge 对**所有字符串属性**应用前缀保留拼接规则，适用于任何 `{前缀}-{后缀}` 格式：

| 场景 | 原值 | 合并值 | 结果 |
|------|------|--------|------|
| 保留前缀 | `横向联弹-普通子弹` | `次级穿刺子弹` | `横向联弹-次级穿刺子弹` |
| 完整格式覆盖 | `横向联弹-普通子弹` | `纵向联弹-穿甲子弹` | `纵向联弹-穿甲子弹` |
| 无前缀直接替换 | `普通子弹` | `次级穿刺子弹` | `次级穿刺子弹` |
| 普通字符串 | `旧名称` | `新名称` | `新名称` |

**拼接规则：**
1. 如果新值包含 `-`：视为完整格式，直接覆盖
2. 如果原值包含 `-`：保留原值前缀，替换后缀
3. 否则：直接使用新值（等同于普通覆盖）

> **设计说明：** 对于不含 `-` 的普通字符串，行为与直接覆盖完全一致，无副作用。

**典型应用场景：**
- `bullet`：联弹格式 `{联弹类型}-{子弹类型}`
- 其他复合格式：`{分类}-{具体类型}`

**实际应用示例：**
```xml
<!-- 磁稳贯穿弹配件 -->
<mod>
    <name>磁稳贯穿弹</name>
    <use>手枪,长枪</use>
    <stats>
        <merge>
            <bullet>次级穿刺子弹</bullet>  <!-- 智能替换子弹类型 -->
        </merge>
    </stats>
</mod>

<!--
效果：
- 装到"横向联弹-普通子弹"的武器上 → "横向联弹-次级穿刺子弹"
- 装到"普通子弹"的武器上 → "次级穿刺子弹"
-->
```

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

#### 6. curve - 曲线压缩

**运算方式：** 对当前属性值应用非线性压缩，当前默认曲线为平方根压缩：

```
新值 = round(系数 × sqrt(当前值))
```

**示例：**
```xml
<stats>
    <curve>
        <diffusion>1.414</diffusion>  <!-- Tooltip 显示为“压缩等级 20” -->
    </curve>
</stats>
```

**Tooltip 展示：** 玩家侧不直接显示根号公式，而显示为可读强度标尺：

```
[曲线] 子弹散射度：压缩等级 20
```

压缩等级只表示“曲线压缩强度”，不是固定百分比。当前换算规则：

```
压缩等级 = round((2 - 系数) / (2 - 1.414) × 20)
```

因此 `1.414` 显示为压缩等级 20；系数越小，压缩等级越高，实际压缩力度越强。

**效果速查（diffusion）：**
```
1→1, 2→2, 3→2, 4→3, 5→3, 6→3, 7→4, 8→4
```

**特点：**
- 默认最小值为 1，但只压缩不放大，0/1 这类低散射不会被反向变差
- 适合“高数值更需要压缩、低数值少动”的属性，例如高扩散武器的压枪插件
- 当前数值写法等价于 `sqrtScale` 曲线；如需显式配置，可使用对象写法：

```xml
<curve>
    <diffusion>
        <type>sqrtScale</type>
        <coefficient>1.414</coefficient>
        <min>1</min>
    </diffusion>
</curve>
```

**用途：** 为顶级压枪、稳定化等配件提供非线性收益，避免低扩散武器过度受益。

---

#### 7. cap - 上限/下限值

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

计算严格按照以下顺序执行（代码位置：`EquipmentCalculator.as` applyOperatorsInOrder方法）：

```
1. percentage（百分比）   ← 优先级最高，先计算（加法合并乘区）
    ↓
2. multiplier（独立乘区） ← 在percentage之后应用（乘法增幅）
    ↓
3. curve（曲线压缩）      ← 在乘区后压缩当前值
    ↓
4. flat（固定值）
    ↓
5. softOverride（可覆盖设定）
    ↓
6. override（普通覆盖）
    ↓
7. merge（深度合并）
    ↓
8. lockOverride（最终锁定）
    ↓
9. cap（上限限制）        ← 优先级最低，最后执行
```

**为什么这样排序？**
- percentage先行：基于基础值和强化等级计算百分比增幅（加法合并，抑制膨胀）
- multiplier次之：在percentage基础上应用独立乘区（乘法增幅，精细控制）
- curve在乘区后：对已经形成的当前值做非线性压缩，适合高数值更强收益的属性
- flat再次：在所有百分比计算后加固定值
- softOverride设定宿主基础档：会改写原生值，但不与专用覆盖插件争夺最终解释权
- override覆盖：可以完全改变前面的计算结果，用于改变本质属性
- merge合并：深度合并嵌套对象，在override之后避免被覆盖影响
- lockOverride锁定：最后重申必须保持的字段，消除同字段插件的遍历顺序差异
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

#### hitBehavior - 声明式子弹命中行为

行为配置通过 `merge` 写入武器运行时数据，并由射击初始化透传到子弹。它与视觉命中特效字段相互独立；只允许注册表支持的封闭 `type`，禁止填写任意函数名或可执行字符串。

```xml
<stats>
    <merge>
        <hitBehavior>
            <type>grayGooPrimer</type>
            <stackGroup>grayGooVulnerability</stackGroup>
            <profileId>base</profileId>
            <decayDelay>90</decayDelay>
            <decayInterval>10</decayInterval>
            <maxStacks>18</maxStacks>
            <hitStacks>1</hitStacks>
            <breakStacks>1</breakStacks>
            <milestoneInterval>6</milestoneInterval>
            <damagePerStack>0.01</damagePerStack>
            <crumblePerMilestone>1</crumblePerMilestone>
            <executeAtMax>8</executeAtMax>
            <sameSourceOnly>true</sameSourceOnly>
        </hitBehavior>
    </merge>
</stats>
```

当前类型表示：有效命中按 `hitStacks` 沉积，真实破韧按 `breakStacks` 追加；联弹全段 MISS/直感不算有效命中。每格易伤为 `damagePerStack`，每跨过 `milestoneInterval` 格为当发配给 `crumblePerMilestone` 击溃，预测达到 `maxStacks` 时配给 `executeAtMax` 斩杀。停火 `decayDelay` 帧后每 `decayInterval` 帧退一格。击溃/斩杀字段使用原始百分比（`0.1` 即 0.1%，`5` 即 5%），`damagePerStack` 使用小数倍率（`0.01` 即 1%）。

`stackGroup` 定义共享最终输出的聚合域，`profileId` 定义同一来源下独立衰减的候选档位。同一组只对各候选的完整倍率取 MAX，不跨档拼接字段，也不把多来源相加。灰蛊裂隙弹基础档由冲锋枪使用：每命中 1 格、节点 `1%` 击溃、满层 `8%` 斩杀；精确 `weapontype:大威力手枪` 分支覆写为每命中 2 格，并显式锁回节点 `0.1%` 击溃与满层 `5%` 斩杀，避免深度 merge 继承冲锋枪补偿；精确 `weapontype:手枪` 分支覆写为每命中 3 格，并把衰减参数改为 `150/15` 帧、击溃改为 `0.3%`、斩杀改为 `8%`。Tooltip 不逐字段展开运行协议：基础档压缩为三条玩家语义，每个枪种分支只用一条摘要展示相对变化。`ToughnessBroken` 仅在非刚体真实破韧时发布；刚体越阈仍清槽，但不对灰蛊追加层数。

#### switchstrike - 切手技参数对象

`data.switchstrike` 由 `SwitchStrikeCore` 消费，用于调整攻击模式切换动画中的命中参数。时间轴只保留定位器与形态名，禁止在 XML 中填写公式字符串或函数名。

```xml
<stats>
    <useSwitch>
        <use name="weapontype:近战,weapontype:压制近战">
            <merge>
                <switchstrike>
                    <weightCoefficient>5</weightCoefficient>
                    <impactMultiplier>5</impactMultiplier>
                </switchstrike>
            </merge>
        </use>
    </useSwitch>
</stats>
```

- `weightCoefficient` 只替换长枪切手技公式中的重量系数，不整体放大空手攻击力项。
- `impactMultiplier` 按倒数缩小击倒率；长枪默认击倒率 5，配置 5 后得到 1。
- 各形态的默认公式、霰弹值、范围、伤害类型与击退参数统一定义在 `SwitchStrikeCore`，新增字段必须继续采用受控数值/枚举。

#### tag - 插件位置标签
**作用：** 同tag的插件不能同时装备（互斥机制）
**示例：** 挂饰、柄尾、枪机、表面涂层 等

#### use - 适用装备类型
**示例：** 头部装备,上装装备,下装装备,刀,手枪,长枪

#### weapontype - 武器子类限制（白名单）
**作用：** 限制配件只能用于指定的武器子类
**示例：** `<weapontype>突击步枪,冲锋枪</weapontype>` - 仅适用于这些子类武器

#### excludeWeapontype - 武器子类排除（黑名单）
**作用：** 排除特定武器子类，配件不能用于这些类型
**示例：** `<excludeWeapontype>发射器,霰弹枪</excludeWeapontype>` - 排除发射器和霰弹枪

**weapontype 与 excludeWeapontype 的组合使用：**
- 两者可以同时使用，黑名单优先级更高
- 检查顺序：先检查黑名单（excludeWeapontype），再检查白名单（weapontype）
- 如果武器在黑名单中，直接排除，不再检查白名单

**示例场景：**
```xml
<!-- 精密瞄具：仅适用于狙击枪和精确步枪，排除半自动类型 -->
<mod>
    <name>精密瞄具</name>
    <use>长枪</use>
    <weapontype>狙击枪,精确步枪</weapontype>
    <excludeWeapontype>半自动狙击枪</excludeWeapontype>
    <stats>...</stats>
</mod>
```

#### excludeBulletTypes - 子弹类型排斥
**作用：** 排斥特定类型的子弹，当装备当前的子弹属于指定类型时，配件不能安装
**检测时机：** 基于装备**计算后**的子弹类型（考虑已安装配件的效果）
**错误码：** -128（当前弹药与此配件不兼容）

**支持的类型标识符：**
| 标识符 | 说明 | 检测方法 |
|--------|------|----------|
| `pierce` | 穿刺子弹 | `BulletTypeUtil.isPierce()` |
| `melee` | 近战子弹 | `BulletTypeUtil.isMelee()` |
| `chain` | 联弹子弹 | `BulletTypeUtil.isChain()` |
| `grenade` | 手雷子弹 | `BulletTypeUtil.isGrenade()` |
| `explosive` | 爆炸子弹 | `BulletTypeUtil.isExplosive()` |
| `normal` | 普通子弹 | `BulletTypeUtil.isNormal()` |
| `vertical` | 纵向子弹 | `BulletTypeUtil.isVertical()` |
| `transparency` | 透明子弹 | `BulletTypeUtil.isTransparency()` |

**示例：**
```xml
<!-- 磁稳贯穿弹：提供穿刺能力，但不能装到已有穿刺子弹的武器上 -->
<mod>
    <name>磁稳贯穿弹</name>
    <use>手枪,长枪</use>
    <excludeWeapontype>发射器,近战,压制近战</excludeWeapontype>
    <excludeBulletTypes>pierce</excludeBulletTypes>
    <stats>
        <merge>
            <bullet>次级穿刺子弹</bullet>
        </merge>
    </stats>
</mod>
```

**多类型排斥：**
```xml
<!-- 排斥穿刺和爆炸类子弹 -->
<excludeBulletTypes>pierce,explosive</excludeBulletTypes>
```

**设计用途：**
- 防止重复提升同类型能力（如穿刺弹药不能装到已有穿刺的武器上）
- 实现子弹类型的互斥机制
- 平衡配件与武器的组合效果

#### requireBulletTypes - 子弹类型要求
**作用：** 要求装备的子弹属于指定类型之一，不满足则配件不能安装（与excludeBulletTypes相反）
**检测时机：** 基于装备**计算后**的子弹类型（考虑已安装配件的效果）
**错误码：** -512（当前弹药类型不满足此配件的要求）

**支持的类型标识符：** 与 excludeBulletTypes 相同（pierce, melee, chain, grenade, explosive, normal, vertical, transparency）

**逻辑：** OR要求 — 子弹匹配列表中**任意一种**类型即通过

**示例：**
```xml
<!-- 穿甲弹头强化件：仅限已有穿刺子弹的武器安装 -->
<mod>
    <name>穿甲弹头强化件</name>
    <use>手枪,长枪</use>
    <requireBulletTypes>pierce</requireBulletTypes>
    <stats>
        <percentage>
            <power>10</power>
        </percentage>
    </stats>
</mod>
```

**多类型要求（满足任一即可）：**
```xml
<!-- 要求子弹为穿刺或爆炸类型 -->
<requireBulletTypes>pierce,explosive</requireBulletTypes>
```

**与 excludeBulletTypes 的对比：**

| 特性 | excludeBulletTypes | requireBulletTypes |
|------|-------------------|-------------------|
| **语义** | 排斥：匹配则**拒绝** | 要求：匹配则**通过** |
| **逻辑** | OR排斥（任一命中→拒绝） | OR要求（任一命中→通过） |
| **错误码** | -128 | -512 |
| **用途** | 防止重复叠加同类能力 | 限定配件只能用于特定弹药的武器 |

**设计用途：**
- 让配件只能安装在使用特定弹药的武器上（如穿刺弹专用强化件）
- 实现弹药类型的正向适配机制
- 与excludeBulletTypes配合，精确控制配件与弹药的兼容性

#### installCondition - 安装条件（数值层校验）

**作用：** 基于装备的数值属性精准控制配件的安装资格

**错误码：** -256（装备属性不满足安装条件）

**基本结构：**
```xml
<installCondition>
    <cond op="运算符" path="属性路径" value="期望值"/>
    <cond op="运算符" path="属性路径" value="期望值"/>
</installCondition>
```

**默认行为：**
- `scope="base"`（默认）：基于装备**基础值**（含进阶/强化，不含配件效果）判定，无安装顺序依赖
- `scope="current"`：基于装备**当前计算值**（含已安装配件效果）判定
- `mode="all"`（默认）：所有条件都满足才通过（AND 逻辑）
- `mode="any"`：任一条件满足即通过（OR 逻辑）

**支持的运算符：**

| 运算符 | 含义 | 示例 | 说明 |
|--------|------|------|------|
| `is` | 等于 | `<cond op="is" path="data.damagetype" value="魔法"/>` | 字符串/数值相等比较 |
| `isNot` | 不等于 | `<cond op="isNot" path="data.damagetype" value="普通"/>` | 字符串/数值不等比较 |
| `above` | 大于 (>) | `<cond op="above" path="data.interval" value="200"/>` | 严格大于 |
| `atLeast` | 大于等于 (>=) | `<cond op="atLeast" path="data.interval" value="200"/>` | |
| `below` | 小于 (<) | `<cond op="below" path="data.weight" value="3"/>` | 严格小于 |
| `atMost` | 小于等于 (<=) | `<cond op="atMost" path="data.weight" value="3"/>` | |
| `oneOf` | 在列表中 | `<cond op="oneOf" path="data.damagetype" value="魔法,破击"/>` | 逗号分隔列表 |
| `noneOf` | 不在列表中 | `<cond op="noneOf" path="data.damagetype" value="普通"/>` | 逗号分隔列表 |
| `contains` | 包含子串 | `<cond op="contains" path="data.bullet" value="穿刺"/>` | 字符串包含检查 |
| `range` | 区间 | `<cond op="range" path="data.power" min="100" max="300"/>` | 闭区间 [min, max] |
| `exists` | 字段存在 | `<cond op="exists" path="data.magictype"/>` | 不需要 value |
| `missing` | 字段不存在 | `<cond op="missing" path="data.skill"/>` | 不需要 value |

> **注意：** 运算符名称刻意避开 AS2 保留关键字（eq/ne/gt/lt/ge/le/not），防止解析冲突。

**属性路径（path）：** 使用点号分隔的路径访问嵌套属性
- `data.damagetype` → 伤害类型
- `data.interval` → 攻击间隔
- `data.power` → 威力
- `data.weight` → 重量
- `data.magicdefence.电` → 电属性魔法防御（支持任意深度嵌套）

**缺失字段处理：**
- `exists` → 返回 false
- `missing` → 返回 true
- 其他运算符 → 一律返回 false（条件不满足）

**group 嵌套语法（高级）：**
```xml
<installCondition>
    <cond op="is" path="data.damagetype" value="魔法"/>
    <group mode="any">
        <cond op="above" path="data.interval" value="200"/>
        <cond op="atLeast" path="data.power" value="300"/>
    </group>
</installCondition>
```
语义：damagetype 是魔法 **AND** （interval > 200 **OR** power >= 300）

**实际应用示例：**
```xml
<!-- 非强化射线弹：仅限魔法属性武器且攻击间隔 > 200 -->
<mod>
    <name>磁暴射线弹</name>
    <use>长枪</use>
    <installCondition>
        <cond op="is" path="data.damagetype" value="魔法"/>
        <cond op="above" path="data.interval" value="200"/>
    </installCondition>
    <stats>...</stats>
</mod>

<!-- 轻武器专用：重量不超过3 -->
<mod>
    <name>轻量化套件</name>
    <use>手枪,长枪</use>
    <installCondition>
        <cond op="atMost" path="data.weight" value="3"/>
    </installCondition>
    <stats>...</stats>
</mod>

<!-- 使用当前计算值（含已装配件效果）判定 -->
<mod>
    <name>进阶模组</name>
    <use>长枪</use>
    <installCondition scope="current">
        <cond op="atLeast" path="data.power" value="500"/>
    </installCondition>
    <stats>...</stats>
</mod>
```

**与其他安装条件的层级关系：**
```
1. use / weapontype        ← 类型层（装备大类/子类）
2. requireTags / useSwitch.requireTags / provideTags ← 结构层（插件依赖链）
3. excludeBulletTypes       ← 子弹层（弹药排斥）
4. requireBulletTypes       ← 子弹层（弹药要求）
5. installCondition         ← 数值层（属性精准控制）
```
检查顺序：类型 → 结构 → 子弹排斥 → 子弹要求 → 数值，前面不通过则不会执行后面的检查。

---

#### grantsWeapontype - 授予武器类型
**作用：** 让装备可以安装其他子类的配件
**示例：** 突击步枪

#### detachPolicy - 拆卸策略
**cascade：** 拆卸时会级联影响依赖此配件的其他配件
**示例：** 拆卸扩展配件槽的配件时，会同时卸下多余槽位的配件

#### skill - 赋予技能
为装备添加主动或被动技能
**包含：** skillname（技能名）、cd（冷却）、mp（消耗）等

#### subweapon - 赋予长枪副武器
为长枪添加下挂 / 内置副武器。`subweapon` 与普通 `skill` 共享特殊槽，不能与普通长枪战技并存。

**基本结构：**
```xml
<mod>
    <subweapon>
        <name>M203榴弹发射器</name>
        <description>下挂榴弹发射模块。</description>
        <cd>1000</cd>
        <mp>0</mp>
        <power>3000</power>
        <powerMultiplier>1</powerMultiplier>
        <capacity>1</capacity>
        <reserveName>榴弹弹药</reserveName>
        <bullet>榴弹</bullet>
        <sound>shoot.wav</sound>
        <split>1</split>
        <diffusion>10</diffusion>
        <velocity>20</velocity>
        <range>50</range>
        <impact>10</impact>
        <damageType>物理</damageType>
        <consumeMode>onLoadGroup</consumeMode>
        <consumeTiming>onReloadCommit</consumeTiming>
        <clipCostPerLoad>1</clipCostPerLoad>
        <initialLoaded>1</initialLoaded>
        <manualReloadAnimation>longGun</manualReloadAnimation>
        <manualReloadBurden>25</manualReloadBurden>
    </subweapon>
</mod>
```

**消耗语义：**
- `consumeMode=onLoadGroup`：1 份 `reserveName` 支持一组 `capacity` 发。
- `consumeTiming=onReloadCommit`：R 联动补装与 F 快装都在换弹提交帧扣组弹药。
- `consumeTiming=linkedFirstFire`：可选延迟扣弹语义，R 联动补装后首次 K 发射扣组弹药。
- `consumeMode=onFire`：每次 K 发射按 `fireCost` 逐发扣弹药。

#### skillSwitch - 按装备类型切换技能
**作用：** 让同一个插件装在不同类型装备上时赋予不同主动战技。

**位置：** `skillSwitch` 是 `<mod>` 根层节点，与 `<skill>`、`<stats>` 同级；不要写在 `<stats>` 内。

**基本结构：**
```xml
<mod>
    <skillSwitch>
        <use>
            <skillname>黑刀斩术</skillname>   <!-- default：未命名分支，仅在其他分支未命中时使用 -->
            <cd>6000</cd>
            <mp>45</mp>
        </use>
        <use name="手部装备,手枪,长枪">
            <skillname>震地</skillname>
            <description>经过改装的装备可以使用震地。</description>
            <cd>5000</cd>
            <mp>30</mp>
            <level>1</level>
        </use>
    </skillSwitch>
</mod>
```

**语义说明：**
- 分支的 `name` 与装备的 `use` 或 `weapontype` 匹配，规则与 `useSwitch` 一致
- 命中 `skillSwitch` 时优先使用分支技能；无命名分支命中时使用省略 `name` 的 default 分支
- 多个分支同时匹配时，按 XML 顺序使用第一个命中的分支
- 根层 `<skill>` 仍可作为兼容回退；但插件存在条件战技时，建议把默认技能也写进 `<skillSwitch><use>`，避免 tooltip 看起来像能装载多个战技
- `level` 可选；主动战技包装技能容器时默认按 1 级处理
- `skillSwitch` 只决定技能，不会应用数值。条件属性仍应写在 `<stats><useSwitch>...</useSwitch></stats>` 中

#### provideTags - 结构支持标签
**作用：** 插件安装后提供的"结构能力"，用于满足其他插件的 requireTags
**特点：** 只提供结构，不占挂点（与 tag 不同，tag 会占用挂点位置）
**示例：** `<provideTags>电力,高级电力</provideTags>`

#### requireTags - 结构依赖标签
**作用：** 插件安装前必须已存在的结构标签
**判定：** 只看结构是否存在（由装备 inherentTags + 其他插件 provideTags 共同决定）
**限制：** 不满足时 UI 不会列出 / 安装返回错误码 -16
**范围：** 写在 `<mod>` 根层时对所有宿主生效；写在 `useSwitch.use` 分支内时仅对命中的装备类型生效

---

### 【baseSwitch - 按配件应用前基础属性选档】

`baseSwitch` 用于“同一插件根据宿主原始档位取得不同配额”的场景。它在 tier/强化完成后、任何配件数值尚未应用时读取 `path`，只应用第一个命中的命名 `<value>`；均未命中时应用省略 `name` 的 default 分支。

```xml
<stats>
    <baseSwitch path="data.damagetype">
        <value name="破击"><percentage><power>24</power></percentage></value>
        <value name="魔法"><percentage><power>50</power></percentage></value>
        <value><percentage><power>9</power></percentage></value>
    </baseSwitch>
    <lockOverride><damagetype>物理</damagetype></lockOverride>
</stats>
```

判定只看插件应用前的数据，因此其他插件把伤害类型改成破击/魔法不会改变本插件的配额，交换槽位顺序也不会改变结果。分支内支持全部数值运算符，但不支持 `provideTags` / `requireTags`；结构依赖仍使用 `useSwitch`。

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
- 分支内可使用所有运算符（percentage、multiplier、curve、flat、softOverride、override、merge、lockOverride、cap），也可声明条件性 `provideTags` / `requireTags`

**匹配规则：**
- 无前缀分支的 name 与装备的 use 或 weapontype 联合集合匹配；这是兼容既有数据的默认语义
- 需要精确字段时使用 `use:值` 或 `weapontype:值`，例如 `name="weapontype:手枪"` 只匹配普通手枪子类，不会因宿主共享 `use=手枪` 而命中大威力手枪或冲锋手枪
- `grantsUse` 扩展值同时参与无前缀匹配和 `use:` 限定匹配
- name支持多个类型，用逗号分隔（如 "发射器,榴弹发射器"）
- 装备的use/weapontype也可能是多值（如 use="步枪,发射器"）
- 只要分支name与装备use/weapontype有任一相同，分支就会生效
- 多个分支可以同时生效（按XML顺序累加效果）
- 支持 **default（兜底）分支**：省略 name 属性的 `<use>` 节点为 default 分支，仅在无命名分支命中时生效

```xml
<!-- 普通手枪专属；不匹配 use=手枪、weapontype=冲锋枪 的冲锋手枪 -->
<useSwitch>
    <use name="weapontype:手枪">
        <merge>
            <hitBehavior>
                <duration>240</duration>
                <maxDuration>360</maxDuration>
                <damagePerStack>0.07</damagePerStack>
            </hitBehavior>
        </merge>
    </use>
</useSwitch>
```

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

**【useSwitch 内的条件性 provideTags / requireTags】**

useSwitch 分支内还可以包含 `<provideTags>` 或 `<requireTags>`，分别实现基于装备类型的条件性结构提供与安装前置：

```xml
<stats>
    <useSwitch>
        <use name="突击步枪">
            <provideTags>NOAH,电力</provideTags>  <!-- 仅突击步枪获得这些结构 -->
            <percentage>
                <power>10</power>                 <!-- 同时可以有数值加成 -->
            </percentage>
        </use>
        <use name="weapontype:机枪,weapontype:压制机枪">
            <requireTags>电力</requireTags>       <!-- 仅机枪类宿主安装时需要电力 -->
        </use>
    </useSwitch>
</stats>
```

**语义说明：**
- 条件性 provideTags 仅在装备类型匹配时生效
- 与顶层 provideTags 叠加，不是替换
- 影响 tagSwitch 和 requireTags 的判定
- 条件性 requireTags 仅在分支命中时与根层 requireTags 合并，并统一影响候选过滤、安装检查、缺失标签提示和依赖拆卸
- Tooltip 的按装备类型追加效果会在对应分支下显示“条件性前置需求”

---

### 【tagSwitch - 基于结构的条件加成】

**作用：** 当宿主装备具备特定结构标签时，提供额外的 stats 加成

**基本结构：**
```xml
<stats>
    <percentage>...</percentage>   <!-- 基础效果：对所有装备生效 -->

    <tagSwitch>                    <!-- 结构触发效果：满足条件时追加 -->
        <tag name="结构标签1">
            <percentage>...</percentage>
            <flat>...</flat>
        </tag>
        <tag name="结构标签2,结构标签3">
            <multiplier>...</multiplier>
        </tag>
    </tagSwitch>
</stats>
```

**语义说明：**
- 顶层stats：对所有装备统一生效的基础效果
- tagSwitch内的分支：当装备的 presentTags 包含指定标签时，追加执行
- 分支内可使用所有运算符（percentage、multiplier、curve、flat、softOverride、override、merge、lockOverride、cap）

**匹配规则：**
- 分支的name与装备的 presentTags（固有结构 + 配件提供的结构）进行匹配
- name支持多个标签，用逗号分隔（如 "电力,高级电力"），满足任一即触发
- 多个分支可以同时生效（按XML顺序累加效果）
- 支持 **default（兜底）分支**：省略 name 属性的 `<tag>` 节点为 default 分支，仅在无命名分支命中时生效

**presentTags 的来源：**
```
presentTags = 装备固有 inherentTags
            + 已安装配件的静态 provideTags
            + 已安装配件通过 useSwitch 提供的条件性 provideTags
```

**实际示例：**
```xml
<!-- 战术鱼骨零件：为突击步枪提供额外结构，并基于结构提供加成 -->
<mod>
    <name>战术鱼骨零件</name>
    <use>长枪</use>
    <stats>
        <override><modslot>3</modslot></override>
        <flat><weight>1</weight></flat>

        <!-- 对突击步枪提供额外结构 -->
        <useSwitch>
            <use name="突击步枪">
                <provideTags>NOAH,电力</provideTags>
            </use>
        </useSwitch>

        <!-- 基于结构的条件加成 -->
        <tagSwitch>
            <tag name="电力">
                <percentage>
                    <power>8</power>
                </percentage>
            </tag>
            <tag name="NOAH">
                <flat>
                    <accuracy>10</accuracy>
                </flat>
            </tag>
        </tagSwitch>
    </stats>
    <grantsWeapontype>突击步枪</grantsWeapontype>
    <provideTags>导轨平台,下导轨挂点,侧导轨挂点,瞄具挂点,扩展模组槽</provideTags>
    <detachPolicy>cascade</detachPolicy>
    <description>...</description>
    <tag>导轨基座</tag>
</mod>
```

**效果分析：**
| 场景 | 突击步枪（如M4A1） | 非突击步枪（如狙击枪） |
|------|-------------------|----------------------|
| 基础 provideTags | 导轨平台等5个 | 导轨平台等5个 |
| 条件 provideTags | +NOAH, +电力 | 无 |
| tagSwitch 加成 | 威力+8%，精准+10 | 无 |

**与 useSwitch 的区别：**

| 特性 | useSwitch | tagSwitch |
|------|-----------|-----------|
| **触发条件** | 装备的 use/weapontype | 装备的 presentTags |
| **判定时机** | 装备类型固定 | 受配件影响动态变化 |
| **典型用途** | 武器类型专精 | 结构依赖加成 |
| **支持 provideTags** | ✅ 是 | ❌ 否（仅stats） |

**适用场景：**
- 让配件在特定结构环境下发挥更强效果
- 实现"协同"型配件（与其他配件组合时效果更好）
- 鼓励玩家构建特定的配件组合

---

### 【bulletSwitch - 基于弹药类型的条件加成】

**作用：** 当宿主装备使用特定类型的子弹时，提供额外的 stats 加成

**基本结构：**
```xml
<stats>
    <override>...</override>   <!-- 基础效果：对所有装备生效 -->

    <bulletSwitch>             <!-- 弹药类型触发效果：满足条件时追加 -->
        <bullet name="pierce">
            <override><split>2</split></override>
        </bullet>
        <bullet name="pierce,chain">
            <flat><accuracy>5</accuracy></flat>
        </bullet>
    </bulletSwitch>
</stats>
```

**语义说明：**
- 顶层stats：对所有装备统一生效的基础效果
- bulletSwitch内的分支：当装备的子弹类型匹配时，追加执行（而非替换）
- 分支内可使用所有运算符（percentage、multiplier、curve、flat、softOverride、override、merge、lockOverride、cap）

**支持的类型标识符：** 与 excludeBulletTypes 相同
| 标识符 | 说明 | 检测方法 |
|--------|------|----------|
| `pierce` | 穿刺子弹 | `BulletTypeUtil.isPierce()` |
| `melee` | 近战子弹 | `BulletTypeUtil.isMelee()` |
| `chain` | 联弹子弹 | `BulletTypeUtil.isChain()` |
| `grenade` | 手雷子弹 | `BulletTypeUtil.isGrenade()` |
| `explosive` | 爆炸子弹 | `BulletTypeUtil.isExplosive()` |
| `normal` | 普通子弹 | `BulletTypeUtil.isNormal()` |
| `vertical` | 纵向子弹 | `BulletTypeUtil.isVertical()` |
| `transparency` | 透明子弹 | `BulletTypeUtil.isTransparency()` |

**匹配规则：**
- name支持多个类型，用逗号分隔（如 "pierce,chain"），满足任一即触发
- 多个分支可以同时生效（按XML顺序累加效果）
- 检测时机：基于装备**原始子弹类型**（不含配件效果），即配件自身的 override.bullet 不影响判定
- 支持 **default（兜底）分支**：省略 name 属性的 `<bullet>` 节点为 default 分支，仅在无命名分支命中时生效

**检测时机说明：**
bulletSwitch 在数值计算的"累积修改器"阶段检测子弹类型。此时 override 尚未应用，
因此检测的是装备原本的子弹类型。这意味着：
- 射线弹插件的 `override.bullet` 不会影响 bulletSwitch 的判定
- bulletSwitch 判断的是"安装此插件之前武器使用什么子弹"

**实际应用示例：**
```xml
<!-- 非强化射线弹：穿刺子弹补偿段数，其他子弹收束散射 -->
<mod>
    <name>磁暴射线弹</name>
    <use>长枪</use>
    <stats>
        <override>
            <bullet>磁暴射线</bullet>
            <bulletrename>电弧射线</bulletrename>
        </override>
        <percentage><power>9</power></percentage>

        <bulletSwitch>
            <bullet name="pierce">
                <override><split>2</split></override>
            </bullet>
            <bullet>  <!-- 省略name → default分支 -->
                <percentage><diffusion>-90</diffusion></percentage>
            </bullet>
        </bulletSwitch>
    </stats>
</mod>

<!--
效果：
- 装到使用"穿刺子弹"的武器上 → 弹裂数覆盖为2（补偿段数），无散射收束
- 装到使用"普通子弹"的武器上 → 子弹散射度-90%（default分支生效）
- 穿刺子弹不获得散射收束，因为命名分支命中后default不再生效
-->
```

**与 useSwitch / tagSwitch 的区别：**

| 特性 | useSwitch | tagSwitch | bulletSwitch |
|------|-----------|-----------|--------------|
| **触发条件** | 装备的 use/weapontype | 装备的 presentTags | 装备的子弹类型 |
| **判定时机** | 装备类型固定 | 受配件影响动态变化 | 基于原始子弹类型 |
| **典型用途** | 武器类型专精 | 结构依赖加成 | 弹药类型适配 |
| **支持 provideTags** | ✅ 是 | ❌ 否 | ❌ 否 |

**适用场景：**
- 为射线弹等替换子弹类型的插件提供弹药适配效果
- 让配件对特定弹药类型的武器产生额外加成或惩罚
- 实现更精细的武器-弹药交互效果

**【三种 Switch 系统通用：default（兜底）分支】**

三种 Switch 系统（useSwitch / tagSwitch / bulletSwitch）均支持 default 分支：

```xml
<!-- useSwitch 示例 -->
<useSwitch>
    <use name="发射器"><percentage><power>10</power></percentage></use>
    <use><!-- 省略name → default --><flat><accuracy>5</accuracy></flat></use>
</useSwitch>

<!-- tagSwitch 示例 -->
<tagSwitch>
    <tag name="电力"><override><criticalhit>30</criticalhit></override></tag>
    <tag><!-- default --><flat><weight>-1</weight></flat></tag>
</tagSwitch>

<!-- bulletSwitch 示例 -->
<bulletSwitch>
    <bullet name="pierce"><override><split>2</split></override></bullet>
    <bullet><!-- default --><percentage><diffusion>-90</diffusion></percentage></bullet>
</bulletSwitch>
```

**语义规则：**
- 省略 `name` 属性的分支即为 default 分支
- default 分支**仅在无命名分支命中时生效**（互斥关系，非叠加）
- 一个 Switch 块内可有多个 default 分支（均会生效），但通常只需一个
- 命名分支优先级高于 default：只要有任一命名分支命中，所有 default 分支都不生效

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

### 【命中率与期望伤害公式（估算模型）】

> 本节用于把配件的 `<accuracy>`（命中加成，单位：%点）粗略换算为“因减少 MISS 带来的期望伤害增幅”，方便做数值平衡。

#### 0. 适用范围（本节的拟合假设）

1. **躲闪 = 纯 MISS**：把闪避判定当作 100% MISS（忽略“跳弹/过穿/格挡/懒闪避”等后续分支）。
2. **敌我同级**：攻击者等级 = 目标等级 = `L`。
3. **目标躲闪率曲线**：采用常见敌人模板 `躲闪率_min=10`、`躲闪率_max=2`，并按 `_root.根据等级计算值`（最大等级 60）线性插值得到：
   ```
   R(L) = 10 + (2-10)/(60-1) * L = 10 - 8L/59
   ```

> 对应代码：`scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as`、`scripts/类定义/org/flashNight/arki/component/StatHandler/DodgeHandler.as`、`scripts/引擎/引擎_lsy_等级与经验值.as`

#### 1. `<accuracy>` → 命中率

```
命中率 H(L, acc) = 基础命中率(=10) × (1 + acc/100) = 10 + acc/10
其中 acc 为配件提供的 <accuracy> 数值（+10 表示命中加成 +10%点）
```

#### 2. 躲闪(MISS)概率（sigmoid 结构）

```
dodgeIndex(L, acc) = (L*10/R(L) - L*H(L, acc)/3) / 40

p(L, acc) = 0.5 * sigmoid(dodgeIndex)
          = 0.5 / (1 + exp((K(L) + (L/30)*acc) / 40))

K(L) = L * (10/3 - 10/R(L))
```

#### 3. 期望伤害倍率（纯 MISS 模型）

```
F(L, acc) = 1 - p(L, acc)
相对提升 Gain(L, acc) = F(L, acc) / F(L, 0) - 1
```

#### 4. 快速参数表（10/20/30/40/50/60 级）

使用下面的简化形式快速估算：

```
p(L, acc) = 0.5 / (1 + exp((C + m*acc) / 40))
m = L/30
C = K(L)
```

| 等级 L | R(L) | m=L/30 | C=K(L) |
|-------:|-----:|-------:|-------:|
| 10 | 8.64 | 0.33 | 21.76 |
| 20 | 7.29 | 0.67 | 39.22 |
| 30 | 5.93 | 1.00 | 49.43 |
| 40 | 4.58 | 1.33 | 45.93 |
| 50 | 3.22 | 1.67 | 11.40 |
| 60 | 1.86 | 2.00 | -121.82 |

> 表中数值已四舍五入；若需要更高精度请直接代入上面的通用公式计算。

#### 5. 常见 `<accuracy>` 的期望伤害增幅（%）

（以 `acc=0` 为对照，单位为相对增幅）

| acc | L=10 | L=20 | L=30 | L=40 | L=50 | L=60 |
|----:|-----:|-----:|-----:|-----:|-----:|-----:|
| -10 | -1.20% | -1.98% | -2.62% | -3.75% | -6.60% | -1.66% |
| +10 | +1.17% | +1.84% | +2.29% | +3.16% | +6.23% | +2.61% |
| +15 | +1.75% | +2.70% | +3.31% | +4.52% | +9.05% | +4.41% |
| +30 | +3.43% | +5.06% | +5.89% | +7.75% | +16.04% | +12.47% |
| +35 | +3.97% | +5.77% | +6.60% | +8.58% | +17.85% | +16.22% |

#### 6. 攻击方等级低于受击方 10 级（ΔL = -10）

在保持「0. 适用范围」中的 **躲闪=纯 MISS** 与 **R(L) 曲线** 不变的前提下，设：

```
受击方等级 Lt = L
攻击方等级 La = max(1, L - 10)
```

则 DodgeHandler 的核心项变为：

```
dodgeIndex(L, acc) = (Lt*10/R(Lt) - La*H(L, acc)/3) / 40
                   = (L*10/R(L) - La*H(L, acc)/3) / 40
```

同样可以化成“线性参数 + sigmoid”的快速估算形式：

```
p(L, acc) = 0.5 / (1 + exp((C + m*acc) / 40))
m = La/30
C = La*10/3 - L*10/R(L)
```

> 说明：当 `L=10` 时原本会得到 `La=0`，这里用 `La=1` 替代（避免 0 级单位导致模型退化），因此 `L=10` 仍会得到一个很小但非 0 的命中收益。

**快速参数表（ΔL=-10）：**

| 受击方等级 L | 攻击方等级 La | R(L) | m=La/30 | C |
|------------:|--------------:|-----:|--------:|--:|
| 10 | 1 | 8.64 | 0.03 | -8.24 |
| 20 | 10 | 7.29 | 0.33 | 5.89 |
| 30 | 20 | 5.93 | 0.67 | 16.10 |
| 40 | 30 | 4.58 | 1.00 | 12.59 |
| 50 | 40 | 3.22 | 1.33 | -21.93 |
| 60 | 50 | 1.86 | 1.67 | -155.15 |

**常见 `<accuracy>` 的期望伤害增幅（ΔL=-10，%）：**

| acc | L=10 | L=20 | L=30 | L=40 | L=50 | L=60 |
|----:|-----:|-----:|-----:|-----:|-----:|-----:|
| -10 | -0.14% | -1.35% | -2.54% | -3.92% | -5.37% | -0.67% |
| +10 | +0.14% | +1.34% | +2.46% | +3.77% | +5.87% | +0.99% |
| +15 | +0.21% | +2.01% | +3.64% | +5.57% | +8.91% | +1.66% |
| +30 | +0.43% | +3.99% | +7.01% | +10.49% | +17.92% | +4.61% |
| +35 | +0.50% | +4.64% | +8.07% | +11.95% | +20.76% | +6.02% |

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
