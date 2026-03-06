# CF7 数值平衡工具 — 字段完整参考表

> 所有XML数据字段的完整清单、分类和说明。
> 供公式引擎、XML解析器和验证器使用。

---

## 一、字段分类总览

```
字段总数: 约70个
├── 通用字段 (12个)
├── 枪械专属 (18个)
├── 防具专属 (20个)
├── 插件专属 (15个)
├── 消耗品专属 (5个)
└── 透传字段 (10个)
```

---

## 二、通用字段 (所有物品)

| 字段名 | XML路径 | 数据类型 | 示例值 | 说明 |
|--------|---------|----------|--------|------|
| name | `<name>` | string | XM556-H-Stinger | 唯一标识符 |
| displayname | `<displayname>` | string | XM556-H-Stinger | 显示名称 |
| icon | `<icon>` | string | XM556-H-Stinger | 图标资源名 |
| type | `<type>` | enum | 武器/防具/消耗品/收集品 | 大类分类 |
| use | `<use>` | string | 手枪/头部装备/药剂 | 子类/装备位 |
| price | `<price>` | number | 442010 | 游戏内价格 |
| description | `<description>` | string | ... | HTML格式描述 |
| level | `<data><level>` | number | 35 | 限制等级 |
| weight | `<data><weight>` | number | 10 | 重量 |

### 2.1 通用可选字段

| 字段名 | XML路径 | 数据类型 | 出现条件 | 说明 |
|--------|---------|----------|----------|------|
| weapontype | `<item weapontype="xxx">` | string | 枪械类 | 具体子类型 |
| helmet | `<helmet>` | boolean | 防具头部 | 是否为头盔 |
| actiontype | `<actiontype>` | string | 防具手部 | 战技类型 |

---

## 三、枪械专属字段

### 3.1 核心数值字段

| 字段名 | XML路径 | 数据类型 | 单位 | Excel映射 | 说明 |
|--------|---------|----------|------|-----------|------|
| power | `<data><power>` | number | - | 子弹威力 | 基础伤害值 |
| interval | `<data><interval>` | number | ms | 射击间隔 | 两次射击间隔 |
| capacity | `<data><capacity>` | number | 发 | 弹容量 | 弹夹容量 |
| split | `<data><split>` | number | - | 连发数/霰弹值 | 每次射击发射数 |
| diffusion | `<data><diffusion>` | number | - | - | 扩散角度 |
| velocity | `<data><velocity>` | number | - | - | 子弹速度 |
| bulletsize | `<data><bulletsize>` | number | - | - | 判定大小 |
| impact | `<data><impact>` | number | - | 冲击力 | 击退/硬直 |
| reloadPenalty | `<data><reloadPenalty>` | number | % | - | 换弹时间惩罚 |
| criticalhit | `<data><criticalhit>` | number | % | - | 暴击率加成 |

### 3.2 资源引用字段 (透传)

| 字段名 | XML路径 | 示例值 | 说明 |
|--------|---------|--------|------|
| bullet | `<data><bullet>` | 纵向机枪联弹-铁枪能量子弹 | 子弹类型 |
| bulletrename | `<data><bulletrename>` | 铁枪能量子弹 | 子弹显示名 |
| sound | `<data><sound>` | laser_minigun.wav | 射击音效 |
| muzzle | `<data><muzzle>` | 铁枪能量弹枪火 | 枪口特效 |
| bullethit | `<data><bullethit>` | 铁枪能量弹火花 | 命中特效 |
| clipname | `<data><clipname>` | 能量电池 | 弹药名称 |
| dressup | `<data><dressup>` | 枪-手枪-XM556 | 外观资源 |

### 3.3 公式引擎计算字段 (只读)

| 字段名 | 来源 | 说明 |
|--------|------|------|
| averageDPS | Excel公式 | 平均DPS |
| weightedDPS | Excel公式 | 加权DPS |
| balanceDPS | Excel公式 | 平衡DPS |
| cycleDamage | Excel公式 | 周期伤害 |
| damagePerHit | Excel公式 | 单段伤害 |
| damageBonus | Excel公式 | 伤害加成 |
| attackSpeed | Excel公式 | 平均射速 |
|拐率 | Excel公式 | 吃拐率 |
| critFactor | Excel公式 | 冲击力系数 |
| cycleFactor | Excel公式 | 周期伤害系数 |

### 3.4 Excel输入系数字段

这些字段在Excel中作为输入，用于计算：

| 字段名 | Excel列 | 说明 |
|--------|---------|------|
| dualWieldFactor | 双枪系数 | 短枪=2, 长枪=1 |
| pierceFactor | 穿刺系数 | 喷火/次级穿刺=1.5, 普通穿刺=2, 非穿刺=1 |
| damageTypeFactor | 伤害类型系数 | 物理=1, 魔法=2, 真伤=3 |
| shotgunValue | 霰弹值 | 霰弹填数量，爆炸类填4 |
| weightLevel | 额外加权层数 | -1到4 |

---

## 四、防具专属字段

### 4.1 基础属性字段

| 字段名 | XML路径 | 数据类型 | 说明 |
|--------|---------|----------|------|
| hp | `<data><hp>` | number | 生命值加成 |
| mp | `<data><mp>` | number | 精力值加成 |
| damage | `<data><damage>` | number | 伤害加成 |
| defence | `<data><defence>` | number | 防御力 |

### 4.2 进阶属性字段

| 字段名 | XML路径 | 数据类型 | 说明 |
|--------|---------|----------|------|
| evasion | `<data><evasion>` | number | 闪避率 |
| accuracy | `<data><accuracy>` | number | 精准度 |
| knifepower | `<data><knifepower>` | number | 兵器加成 |
| gunpower | `<data><gunpower>` | number | 枪械加成 |
| punch | `<data><punch>` | number | 空手加成 |
| force | `<data><force>` | number | 内力 |
| vampirism | `<data><vampirism>` | number | 吸血 |
| toughness | `<data><toughness>` | number | 韧性 |

### 4.3 魔法抗性字段 (嵌套)

| 字段名 | XML路径 | 数据类型 | 说明 |
|--------|---------|----------|------|
| magicdefence.蚀 | `<magicdefence><蚀>` | number | 腐蚀抗性 |
| magicdefence.毒 | `<magicdefence><毒>` | number | 毒素抗性 |
| magicdefence.冷 | `<magicdefence><冷>` | number | 冰冻抗性 |
| magicdefence.热 | `<magicdefence><热>` | number | 火焰抗性 |
| magicdefence.电 | `<magicdefence><电>` | number | 电击抗性 |
| magicdefence.波 | `<magicdefence><波>` | number | 波动抗性 |
| magicdefence.冲 | `<magicdefence><冲>` | number | 冲击抗性 |
| magicdefence.全属性 | `<magicdefence><全属性>` | number | 全属性抗性 |

### 4.4 多阶强化字段

| 字段名 | XML路径 | 说明 |
|--------|---------|------|
| modslot | `<data_X><modslot>` | 插件槽数量 |
| tierData | `<data_2>`/`<data_3>`/`<data_4>` | 多阶数据，覆盖继承 |

### 4.5 公式引擎计算字段

| 字段名 | 来源 | 说明 |
|--------|------|------|
| currentScore | Excel公式 | 当前总分 |
| weightedScore | Excel公式 | 加权总分 |
| balanceScore | Excel公式 | 平衡总分 |
| magicDefAvgLimit | Excel公式 | 法抗均值上限 |
| magicDefMaxLimit | Excel公式 | 法抗最高上限 |

---

## 五、插件专属字段 (equipment_mods)

### 5.1 基础字段

| 字段名 | XML路径 | 数据类型 | 说明 |
|--------|---------|----------|------|
| name | `<name>` | string | 插件名称 |
| use | `<use>` | string[] | 适用装备类型，逗号分隔 |
| description | `<description>` | string | 描述 |
| tag | `<tag>` | string | 插件标签 |

### 5.2 属性加成字段 (stats)

| 字段名 | XML路径 | 算子类型 | 说明 |
|--------|---------|----------|------|
| stats.percentage.X | `<stats><percentage><X>` | 百分比加成 | 与强化加算 |
| stats.flat.X | `<stats><flat><X>` | 固定加成 | 不受强化影响 |
| stats.override.X | `<stats><override><X>` | 覆盖 | 直接替换 |
| stats.multiplier.X | `<stats><multiplier><X>` | 独立乘区 | 强化后增幅明显 |
| stats.cap.X | `<stats><cap><X>` | 上限 | 约束最大值 |
| stats.merge.X | `<stats><merge><X>` | 合并 | 字符串拼接 |

### 5.3 条件字段

| 字段名 | XML路径 | 说明 |
|--------|---------|------|
| weapontype | `<weapontype>` | 限定武器子类型 |
| requireTags | `<requireTags>` | 需要的标签 |
| excludeWeapontype | `<excludeWeapontype>` | 排除的武器子类型 |
| excludeBulletTypes | `<excludeBulletTypes>` | 排除的子弹类型 |
| provideTags | `<provideTags>` | 提供的标签 |
| grantsWeapontype | `<grantsWeapontype>` | 赋予的武器子类型 |
| detachPolicy | `<detachPolicy>` | 卸载策略 |

### 5.4 安装条件

| 字段名 | XML路径 | 说明 |
|--------|---------|------|
| installCondition | `<installCondition><cond>` | 复杂条件表达式 |

示例:
```xml
<installCondition>
    <cond op="is" path="data.damagetype" value="魔法" />
    <cond op="above" path="data.interval" value="200" />
    <cond op="is" path="data.split" value="1" />
</installCondition>
```

### 5.5 条件分支

| 字段名 | XML路径 | 说明 |
|--------|---------|------|
| useSwitch | `<useSwitch><use name="xxx">` | 根据use值切换 |
| tagSwitch | `<tagSwitch><tag name="xxx">` | 根据tag值切换 |
| bulletSwitch | `<bulletSwitch><bullet name="xxx">` | 根据bullet值切换 |

---

## 六、消耗品专属字段

### 6.1 药剂字段

| 字段名 | XML路径 | 数据类型 | 说明 |
|--------|---------|----------|------|
| effects | `<data><effects>` | array | 效果列表 |
| effect.type | `<effect type="xxx">` | enum | 效果类型 |
| effect.hp | `<effect hp="xxx">` | number | HP恢复量 |
| effect.mp | `<effect mp="xxx">` | number | MP恢复量 |
| effect.target | `<effect target="xxx">` | enum | 目标(self/group) |
| effect.scaleWithAlchemy | `<effect scaleWithAlchemy="xxx">` | boolean | 是否受炼金术加成 |

效果类型枚举:
- `heal`: 治疗
- `state`: 状态效果
- `purify`: 净化
- `playEffect`: 播放特效

### 6.2 弹夹/手雷字段

| 字段名 | XML路径 | 说明 |
|--------|---------|------|
| 弹夹配置 | `<data>`内自定义 | 纯配置，无数值公式 |

---

## 七、怪物属性字段 (enemy_properties)

> 注意：怪物XML使用完全不同的结构，中文节点名作为tag。

| 字段名 | XML节点 | 数据类型 | 说明 |
|--------|---------|----------|------|
| displayname | `<displayname>` | string | 显示名称 |
| hp_min | `<hp_min>` | number | 最小HP |
| hp_max | `<hp_max>` | number | 最大HP |
| 速度_min | `<速度_min>` | number | 最小速度 |
| 速度_max | `<速度_max>` | number | 最大速度 |
| 空手攻击力_min | `<空手攻击力_min>` | number | 最小攻击力 |
| 空手攻击力_max | `<空手攻击力_max>` | number | 最大攻击力 |
| 躲闪率_min | `<躲闪率_min>` | number | 最小闪避率 |
| 躲闪率_max | `<躲闪率_max>` | number | 最大闪避率 |
| 基本防御力_min | `<基本防御力_min>` | number | 最小防御 |
| 基本防御力_max | `<基本防御力_max>` | number | 最大防御 |
| 装备防御力 | `<装备防御力>` | number | 装备防御 |
| 韧性系数 | `<韧性系数>` | number | 韧性 |
| 重量 | `<重量>` | number | 重量 |
| 最小经验值 | `<最小经验值>` | number | 最小经验 |
| 最大经验值 | `<最大经验值>` | number | 最大经验 |

### 7.1 怪物魔法抗性

| 字段名 | XML节点 | 说明 |
|--------|---------|------|
| 魔法抗性.衍生 | `<魔法抗性><衍生>` | 衍生抗性 |
| 魔法抗性.黑铁会 | `<魔法抗性><黑铁会>` | 黑铁会抗性 |
| 魔法抗性.立场 | `<魔法抗性><立场>` | 立场抗性 |
| 魔法抗性.模因 | `<魔法抗性><模因>` | 模因抗性 |
| 魔法抗性.人类 | `<魔法抗性><人类>` | 人类抗性 |
| 魔法抗性.电子体 | `<魔法抗性><电子体>` | 电子体抗性 |
| 魔法抗性.盗贼 | `<魔法抗性><盗贼>` | 盗贼抗性 |
| 魔法抗性.首领 | `<魔法抗性><首领>` | 首领抗性 |
| 魔法抗性.装甲 | `<魔法抗性><装甲>` | 装甲抗性 |
| 魔法抗性.机械 | `<魔法抗性><机械>` | 机械抗性 |
| 魔法抗性.生化 | `<魔法抗性><生化>` | 生化抗性 |
| 魔法抗性.凡俗 | `<魔法抗性><凡俗>` | 凡俗抗性 |
| 魔法抗性.精英 | `<魔法抗性><精英>` | 精英抗性 |
| 魔法抗性.诺亚 | `<魔法抗性><诺亚>` | 诺亚抗性 |

---

## 八、bullets_cases 字段

| 字段名 | XML路径 | 说明 |
|--------|---------|------|
| name | `<bullet><name>` | 子弹名称 |
| casing | `<shell><casing>` | 弹壳类型 |
| xOffset | `<shell><xOffset>` | X偏移 |
| yOffset | `<shell><yOffset>` | Y偏移 |
| simulationMethod | `<shell><simulationMethod>` | 模拟方法 |
| hitMark | `<attribute><hitMark>` | 命中标记 |
| pierceLimit | `<attribute><pierceLimit>` | 穿透限制 |
| func | `<movement><func>` | 移动函数 |
| missileConfig | `<movement><param><missileConfig>` | 导弹配置 |

---

## 九、字段数值范围参考

### 9.1 武器数值范围 (从XML统计)

| 字段 | 最小值 | 最大值 | 常见范围 |
|------|--------|--------|----------|
| level | 1 | 50 | 1-45 |
| power | 10 | 3000 | 100-1500 |
| interval | 50 | 1000 | 80-300 |
| capacity | 1 | 3000 | 10-100 |
| weight | 0.5 | 30 | 2-10 |
| split | 1 | 20 | 1-5 |

### 9.2 防具数值范围

| 字段 | 最小值 | 最大值 | 常见范围 |
|------|--------|--------|----------|
| level | 1 | 50 | 1-45 |
| hp | 10 | 2000 | 50-500 |
| defence | 5 | 1500 | 50-400 |
| weight | -5 | 20 | 0.5-5 |

### 9.3 插件数值范围

| 字段 | 最小值 | 最大值 | 说明 |
|------|--------|--------|------|
| percentage | -90 | 100 | 百分比，可为负 |
| multiplier | -50 | 50 | 独立乘区百分比 |
| flat | -100 | 500 | 固定值 |

---

## 十、字段映射速查表

### 10.1 Excel列名 -> XML字段名

| Excel列名 | XML字段名 | 所属品类 |
|-----------|-----------|----------|
| 具体武器 | name | 通用 |
| 限制等级 | level | 通用 |
| 子弹威力 | power | 枪械 |
| 射击间隔 | interval | 枪械 |
| 弹容量 | capacity | 枪械 |
| 弹夹价格 | magPrice | 枪械(透传) |
| 重量 | weight | 通用 |
| 双枪系数 | dualWieldFactor | 枪械(Excel) |
| 穿刺系数 | pierceFactor | 枪械(Excel) |
| 伤害类型系数 | damageTypeFactor | 枪械(Excel) |
| 霰弹值 | shotgunValue | 枪械(Excel) |
| 冲击力 | impact | 枪械 |
| 额外加权层数 | weightLevel | 枪械(Excel) |

### 10.2 XML字段名 -> AS2属性名

| XML字段名 | AS2属性名 | 说明 |
|-----------|-----------|------|
| power | 子弹威力 | 基础伤害 |
| interval | 射击间隔 | 毫秒 |
| capacity | 弹容量 | 发数 |
| defence | 防御力 | 减伤计算 |
| hp | hp | 生命值 |
| damage | 伤害加成 | 额外伤害 |

---

## 十一、字段配置JSON Schema

```json
{
  "fieldRegistry": {
    "numericFields": {
      "universal": ["level", "weight", "price"],
      "weapon": ["power", "interval", "capacity", "split", "diffusion", 
                 "velocity", "bulletsize", "impact", "reloadPenalty", "criticalhit"],
      "armor": ["hp", "mp", "damage", "defence", "evasion", "accuracy",
                "knifepower", "gunpower", "punch", "force", "vampirism", "toughness"],
      "consumable": ["hp", "mp", "value"]
    },
    "passthroughFields": ["dressup", "bullet", "bulletrename", "sound", 
                          "muzzle", "bullethit", "clipname"],
    "nestedNumericFields": ["magicdefence"],
    "magicElements": ["蚀", "毒", "冷", "热", "电", "波", "冲", "全属性"],
    "monsterMagicResistance": ["衍生", "黑铁会", "立场", "模因", "人类", 
                               "电子体", "盗贼", "首领", "装甲", "机械", 
                               "生化", "凡俗", "精英", "诺亚"]
  }
}
```

---

*文档版本: v1.0*
*最后更新: 2026-03-06*
*配套: CF7-BalanceTool-DevSpec-v3.md*
