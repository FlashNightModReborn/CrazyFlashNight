# 武器加权计算工作流文档

## 概述
本文档定义了武器加权等级（Weapon Weighting Level）的计算和标注流程。加权等级用于评估武器的综合价值，影响武器的最终DPS评分和定价。

## 加权等级英文命名
- **字段名**: `weightlevel` 
- **数据类型**: Integer (-1 到 4)
- **XML位置**: `<data>` 标签内

## 加权等级定义

| 等级 | 含义 | 获取方式 |
|------|------|----------|
| -1 | 负加权 | 新手/练习武器，性能低于标准 |
| 0 | 标准 | 普通掉落，商店购买 |
| 1 | 优质 | K点购买/合成获得 |
| 2 | 精良 | 高价商品/稀有掉落 |
| 3 | 史诗 | K点+合成+高价 |
| 4 | 传奇 | 特殊活动/开发者武器 |

## 核心计算公式

### 1. 平均DPS计算
```
平均DPS = 1000 × 单发伤害 / (射击间隔 × (弹夹容量 - 1) + 900 × 双枪系数)
```

### 2. 加权DPS计算
```
加权DPS = 平均DPS × 弹道系数 × 对攻系数 × 1.1^加权等级
```

### 3. 关键系数说明

#### 双枪系数
- 单枪：1.0
- 双枪：2.0（手枪类）
- 双枪：1.5（长枪类）

#### 弹道系数
- 激光/能量：1.0
- 连发/制导：1.5
- 普通弹道：2.0

#### 伤害类型系数
- 物理伤害：1.0
- 魔法伤害：2.0
- 真实伤害：3.0

#### 对攻系数
- 默认：1.0
- 可根据特殊属性调整

## 逆向计算工作流

### 步骤1：提取武器属性
```python
# 从XML提取基础属性
weapon_data = {
    'id': weapon_id,
    'name': weapon_name,
    'level': level,
    'price': price,
    'power': power,
    'interval': interval,
    'capacity': capacity,
    'split': split,  # 连发数
    'weapontype': weapontype
}
```

### 步骤2：计算平均DPS
```python
def calculate_avg_dps(power, interval, capacity, double_gun_coef=1):
    return 1000 * power / (interval * (capacity - 1) + 900 * double_gun_coef)
```

### 步骤3：确定系数
```python
def determine_coefficients(weapon_data):
    # 双枪系数
    if '双枪' in weapon_data['name'] or 'dual' in weapon_data['name'].lower():
        double_gun_coef = 2.0 if weapon_data['use'] == '手枪' else 1.5
    else:
        double_gun_coef = 1.0
    
    # 弹道系数
    if weapon_data['split'] >= 3:  # 连发
        ballistic_coef = 1.5
    elif '激光' in weapon_data['bullet'] or '能量' in weapon_data['bullet']:
        ballistic_coef = 1.0
    else:
        ballistic_coef = 2.0
    
    # 对攻系数（默认）
    attack_coef = 1.0
    
    return double_gun_coef, ballistic_coef, attack_coef
```

### 步骤4：逆向推算加权等级
```python
def calculate_weight_level(weapon_data, target_price):
    avg_dps = calculate_avg_dps(...)
    coefficients = determine_coefficients(weapon_data)
    
    # 根据价格推算加权等级
    price_ratio = target_price / base_price_for_level
    
    # 尝试不同的加权等级
    for weight_level in range(-1, 5):
        weighted_dps = avg_dps * ballistic_coef * attack_coef * (1.1 ** weight_level)
        estimated_price = calculate_price_from_dps(weighted_dps, level)
        
        if abs(estimated_price - target_price) / target_price < 0.15:  # 15%误差范围
            return weight_level
    
    return 0  # 默认返回标准加权
```

### 步骤5：验证计算结果
```python
def validate_weight_level(weapon_data, calculated_weight_level):
    # 价格合理性检查
    if weapon_data['price'] > 100000 and calculated_weight_level < 2:
        print(f"警告：高价武器{weapon_data['name']}加权等级偏低")
    
    # 等级与加权匹配检查
    if weapon_data['level'] < 10 and calculated_weight_level > 2:
        print(f"警告：低等级武器{weapon_data['name']}加权等级偏高")
    
    return True
```

## XML标注示例

### 标注前
```xml
<item>
  <id>8218</id>
  <name>M93R</name>
  <level>21</level>
  <data>
    <weapontype>冲锋枪</weapontype>
    <power>690</power>
    <interval>300</interval>
    <capacity>7</capacity>
  </data>
</item>
```

### 标注后
```xml
<item>
  <id>8218</id>
  <name>M93R</name>
  <level>21</level>
  <data>
    <weapontype>冲锋枪</weapontype>
    <weightlevel>0</weightlevel>  <!-- 新增加权等级字段 -->
    <power>690</power>
    <interval>300</interval>
    <capacity>7</capacity>
  </data>
</item>
```

## 批量处理脚本

```python
import xml.etree.ElementTree as ET

def batch_calculate_weight_levels(xml_file):
    tree = ET.parse(xml_file)
    root = tree.getroot()
    
    results = []
    for item in root.findall('item'):
        weapon_data = extract_weapon_data(item)
        weight_level = calculate_weight_level(weapon_data)
        
        # 添加weightlevel标签
        data_elem = item.find('data')
        if data_elem is not None:
            weight_elem = ET.SubElement(data_elem, 'weightlevel')
            weight_elem.text = str(weight_level)
        
        results.append({
            'id': weapon_data['id'],
            'name': weapon_data['name'],
            'calculated_weight': weight_level
        })
    
    return results
```

## 日志记录格式

每次计算应记录以下信息：
```markdown
| ID | 名称 | 等级 | 价格 | 平均DPS | 加权DPS | 计算加权 | 状态 |
|----|------|------|------|---------|---------|----------|------|
| 8218 | M93R | 21 | 54200 | 255.56 | 383.33 | 0 | 已完成 |
```

## 特殊情况处理

1. **开发者武器**：自动设置为加权等级4
2. **新手武器**（0-5级）：通常为加权等级-1或0
3. **活动限定武器**：根据获取难度设置2-3级
4. **压制类武器**（弹容>150）：额外考虑压制加成

## 质量保证

- 每把武器计算后需验证：
  - [ ] DPS计算正确性
  - [ ] 系数选择合理性
  - [ ] 价格与加权匹配度
  - [ ] 特殊属性考虑完整

## 更新记录

- 2025-08-29：创建加权计算工作流文档
- 定义weightlevel字段规范
- 建立完整计算公式体系