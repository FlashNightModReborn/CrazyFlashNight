# BaseShield 测试套件

## 一句话启动代码

```actionscript
org.flashNight.arki.component.Shield.BaseShieldTestSuite.runAllTests();
```

---

## 测试日志结果

```


========================================
    BaseShield 测试套件 v1.0
========================================

【1. 构造函数与初始化测试】
✓ 默认值初始化测试通过
✓ 自定义值初始化测试通过
✓ 无效值处理测试通过
✓ 唯一ID生成测试通过
构造函数 所有测试通过！
【2. 伤害吸收测试】
✓ 基础伤害吸收测试通过
✓ 强度限制测试通过
✓ 容量限制测试通过
✓ 绕过护盾测试通过
✓ 抵抗绕过测试通过
✓ 未激活护盾测试通过
伤害吸收 所有测试通过！
【3. 容量消耗测试】
✓ 基础容量消耗测试通过
✓ 超量消耗测试通过
✓ 零消耗测试通过
✓ 空护盾消耗测试通过
容量消耗 所有测试通过！
【4. 属性设置器测试】
✓ 容量设置器测试通过
✓ 最大容量设置器测试通过
✓ 目标容量设置器测试通过
✓ 强度设置器测试通过
✓ Owner设置器测试通过
属性设置器 所有测试通过！
【5. 充能机制测试】
✓ 基础充能测试通过
✓ 充能延迟测试通过
✓ 延迟重置测试通过
✓ 充能至目标容量测试通过
✓ update返回值测试通过
充能机制 所有测试通过！
【6. 衰减机制测试】
✓ 基础衰减测试通过
✓ 衰减不受延迟影响测试通过
✓ 衰减至零测试通过
✓ 零容量不再变化测试通过
衰减机制 所有测试通过！
【7. 事件回调测试】
✓ onHit回调测试通过
✓ onBreak回调测试通过
✓ onRechargeStart回调测试通过
✓ onRechargeFull回调测试通过
事件回调 所有测试通过！
【8. 边界条件测试】
✓ 零伤害测试通过
✓ 零强度测试通过
✓ 零容量测试通过
✓ 负伤害边界测试通过
✓ 大数值测试通过
边界条件 所有测试通过！
【9. 联弹机制测试】
✓ 基础联弹测试通过
✓ hitCount默认值测试通过
✓ 联弹强度倍增测试通过
✓ 联弹容量限制测试通过
联弹机制 所有测试通过！
【10. 性能测试】
absorbDamage: 10000次 30ms, 平均0.003ms/次
update(充能): 10000次 20ms, 平均0.002ms/次
创建BaseShield: 1000次 10ms, 平均0.01ms/次

========================================
测试完成！总耗时: 62ms
========================================


```

---

## 技术文档

### 1. 类概述

`BaseShield` 是护盾系统的抽象基类，实现了 `IShield` 接口，提供护盾的核心属性存储和默认行为实现。

### 2. 核心属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `_capacity` | Number | 当前护盾容量 |
| `_maxCapacity` | Number | 护盾最大容量 |
| `_targetCapacity` | Number | 目标容量（充能恢复到此值） |
| `_strength` | Number | 护盾强度（每次攻击最多吸收此值的伤害） |
| `_rechargeRate` | Number | 填充速度（正数充能，负数衰减） |
| `_rechargeDelay` | Number | 填充延迟时间（帧数） |
| `_resistBypass` | Boolean | 是否抵抗绕过（如抗真伤） |
| `_isActive` | Boolean | 护盾是否激活 |
| `_id` | Number | 唯一标识（用于稳定排序） |

### 3. 构造函数

```actionscript
public function BaseShield(
    maxCapacity:Number,    // 最大容量，默认100
    strength:Number,       // 护盾强度，默认50
    rechargeRate:Number,   // 填充速度，默认0
    rechargeDelay:Number   // 填充延迟，默认0
)
```

**行为说明：**
- `undefined` 或 `NaN` 参数会被替换为默认值
- 初始容量等于最大容量
- 每个护盾自动分配唯一ID

### 4. 核心方法

#### 4.1 absorbDamage - 伤害吸收

```actionscript
public function absorbDamage(
    damage:Number,         // 输入伤害
    bypassShield:Boolean,  // 是否绕过护盾
    hitCount:Number        // 命中段数（联弹支持）
):Number                   // 返回穿透伤害
```

**计算公式：**
```
effectiveStrength = strength × hitCount
absorbed = min(damage, effectiveStrength, capacity)
penetrating = damage - absorbed
```

**特殊行为：**
- `bypassShield=true` 且 `resistBypass=false`：直接穿透
- `bypassShield=true` 且 `resistBypass=true`：正常吸收
- 护盾未激活或容量为0：直接穿透

#### 4.2 consumeCapacity - 容量消耗

```actionscript
public function consumeCapacity(amount:Number):Number
```

**用途：** 供 `ShieldStack` 内部调用，仅消耗容量不做强度节流。

**区别：**
| 方法 | 强度节流 | 容量消耗 | 事件触发 |
|------|----------|----------|----------|
| absorbDamage | ✓ | ✓ | ✓ |
| consumeCapacity | ✗ | ✓ | ✓ |

#### 4.3 update - 帧更新

```actionscript
public function update(deltaTime:Number):Boolean
```

**返回值语义：**
- `true`：状态发生了影响缓存的变化（容量改变、激活状态改变）
- `false`：无变化（未激活、容量已满、延迟期间、衰减盾容量为0）

**充能护盾行为（rechargeRate > 0）：**
1. 受击后进入延迟状态
2. 延迟期间不充能
3. 延迟结束触发 `onRechargeStart`
4. 充满触发 `onRechargeFull`

**衰减护盾行为（rechargeRate < 0）：**
1. 不受延迟影响
2. 每帧持续衰减
3. 容量归零触发 `onBreak`

### 5. 事件回调

| 回调 | 签名 | 触发时机 |
|------|------|----------|
| `onHitCallback` | `function(shield:IShield, absorbed:Number):Void` | 每次吸收伤害后 |
| `onBreakCallback` | `function(shield:IShield):Void` | 容量降至0时 |
| `onRechargeStartCallback` | `function(shield:IShield):Void` | 延迟结束开始充能时 |
| `onRechargeFullCallback` | `function(shield:IShield):Void` | 充能到目标容量时 |

### 6. 排序优先级

```actionscript
sortPriority = strength × 10000 - rechargeRate - id × 0.001
```

**排序规则：**
1. 强度高者优先
2. 强度相同时，填充速度低者优先（临时盾优先消耗）
3. 以上都相同时，ID小者优先

### 7. 联弹机制

联弹是单发子弹模拟多段弹幕的性能优化方案：

| 场景 | hitCount | 有效强度 | 说明 |
|------|----------|----------|------|
| 普通子弹 | 1 | strength | 默认值 |
| 10段联弹 | 10 | strength × 10 | 强度按段数倍增 |

**示例：**
- 护盾强度50，容量1000
- 10段联弹，每段60伤害，总600伤害
- 有效强度 = 50 × 10 = 500
- 吸收500，穿透100

### 8. 性能指标

| 操作 | 10000次耗时 | 平均耗时 |
|------|-------------|----------|
| absorbDamage | ~45ms | 0.0045ms/次 |
| update | ~32ms | 0.0032ms/次 |
| 创建实例 | ~28ms/1000次 | 0.028ms/次 |

### 9. 使用示例

```actionscript
// 创建基础护盾
var shield:BaseShield = new BaseShield(100, 50, 5, 60);

// 设置回调
shield.onBreakCallback = function(s:IShield):Void {
    trace("护盾击碎！");
};

// 吸收伤害
var penetrating:Number = shield.absorbDamage(80, false, 1);
trace("穿透伤害: " + penetrating);

// 帧更新
if (shield.update(1)) {
    trace("护盾状态变化");
}
```

### 10. 注意事项

1. **ID唯一性**：每个BaseShield实例有唯一ID，由静态计数器自动分配
2. **容量边界**：setCapacity 会自动钳位到 [0, maxCapacity] 范围
3. **衰减盾**：负的 rechargeRate 表示衰减，不受延迟影响
4. **抵抗绕过**：需要手动调用 setResistBypass(true) 启用
