# Shield 测试套件

## 一句话启动代码

```actionscript
org.flashNight.arki.component.Shield.ShieldTestSuite.runAllTests();
```

---

## 测试日志结果

```

========================================
    Shield 测试套件 v1.0
========================================

【1. 构造函数测试】
✓ 基础构造测试通过
✓ 默认值测试通过
✓ 名称和类型测试通过
构造函数 所有测试通过！
【2. 工厂方法测试】
✓ createTemporary测试通过
✓ createRechargeable测试通过
✓ createDecaying测试通过
✓ createResistant测试通过
工厂方法 所有测试通过！
【3. 临时盾机制测试】
✓ 临时盾击碎后失活测试通过
✓ 永久盾击碎后保持活跃测试通过
✓ 设置临时属性测试通过
临时盾机制 所有测试通过！
【4. 持续时间测试】
✓ 持续时间倒计时测试通过
✓ 永久盾duration=-1测试通过
✓ 设置持续时间测试通过
持续时间 所有测试通过！
【5. 过期机制测试】
✓ 过期自动失活测试通过
✓ 过期回调测试通过
✓ 过期时update返回值测试通过
过期机制 所有测试通过！
【6. 回调注册测试】
✓ setCallbacks批量注册测试通过
✓ 链式调用测试通过
✓ 部分设置测试通过
回调注册 所有测试通过！
【7. 继承行为测试】
✓ 继承的伤害吸收测试通过
✓ 继承的容量消耗测试通过
✓ 继承的属性访问器测试通过
✓ 继承的排序优先级测试通过
继承行为 所有测试通过！
【8. 衰减盾测试】
✓ 基础衰减测试通过
✓ 衰减至零后触发break测试通过
✓ 衰减不受命中延迟影响测试通过
衰减盾 所有测试通过！
【9. 抗真伤盾测试】
✓ 抵抗绕过测试通过
✓ 普通伤害测试通过
✓ 带持续时间的抗真伤盾测试通过
抗真伤盾 所有测试通过！
【10. 性能测试】
工厂方法创建: 4000次 56ms, 平均0.014ms/次
update(带duration): 10000次 35ms, 平均0.0035ms/次
完整生命周期: 1000次 200ms, 平均0.2ms/次

========================================
测试完成！总耗时: 298ms
========================================

```

---

## 技术文档

### 1. 类概述

`Shield` 类是具体的护盾实现，继承自 `BaseShield`，提供完整的单个护盾功能。扩展了名称、类型、临时盾、持续时间等特性。

### 2. 继承关系

```
IShield (接口)
    ↑
BaseShield (抽象基类)
    ↑
Shield (具体实现)
```

### 3. 扩展属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `_name` | String | 护盾名称（用于UI显示和调试） |
| `_type` | String | 护盾类型标签（如"能量盾"、"物理盾"） |
| `_isTemporary` | Boolean | 是否为临时盾（耗尽后自动失活） |
| `_duration` | Number | 剩余持续时间（-1表示永久） |
| `onExpireCallback` | Function | 过期事件回调 |

### 4. 构造函数

```actionscript
public function Shield(
    maxCapacity:Number,    // 最大容量
    strength:Number,       // 护盾强度
    rechargeRate:Number,   // 填充速度
    rechargeDelay:Number,  // 填充延迟
    name:String,           // 护盾名称，默认"Shield"
    type:String            // 护盾类型，默认"default"
)
```

### 5. 工厂方法

Shield 类提供4个静态工厂方法，简化常见护盾类型的创建：

#### 5.1 createTemporary - 创建临时护盾

```actionscript
public static function createTemporary(
    maxCapacity:Number,  // 最大容量
    strength:Number,     // 护盾强度
    duration:Number,     // 持续时间帧数（-1为永久）
    name:String          // 护盾名称
):Shield
```

**特点：**
- 不充能（rechargeRate=0）
- 击碎后自动失活
- 持续时间结束后自动过期

**适用场景：**
- 技能临时护盾
- 道具提供的临时防护

#### 5.2 createRechargeable - 创建可充能护盾

```actionscript
public static function createRechargeable(
    maxCapacity:Number,    // 最大容量
    strength:Number,       // 护盾强度
    rechargeRate:Number,   // 每帧回充量
    rechargeDelay:Number,  // 受击后回充延迟帧数
    name:String            // 护盾名称
):Shield
```

**特点：**
- 可自动恢复
- 击碎后保持活跃
- 不会过期

**适用场景：**
- 角色基础护盾
- 永久装备护盾

#### 5.3 createDecaying - 创建衰减护盾

```actionscript
public static function createDecaying(
    maxCapacity:Number,  // 最大容量
    strength:Number,     // 护盾强度
    decayRate:Number,    // 每帧衰减量（正数）
    name:String          // 护盾名称
):Shield
```

**特点：**
- 容量随时间减少
- 不受命中影响
- 击碎后自动失活

**适用场景：**
- 技能增益效果
- 临时强化状态

#### 5.4 createResistant - 创建抗真伤护盾

```actionscript
public static function createResistant(
    maxCapacity:Number,  // 最大容量
    strength:Number,     // 护盾强度
    duration:Number,     // 持续时间帧数（-1为永久）
    name:String          // 护盾名称
):Shield
```

**特点：**
- 可抵抗绕过效果（如真伤）
- 临时护盾
- 通常容量有限

**适用场景：**
- 绝对防御技能
- 特殊防护效果

### 6. 护盾类型对比

| 类型 | 充能 | 临时 | 抗绕过 | 过期 |
|------|------|------|--------|------|
| temporary | ✗ | ✓ | ✗ | ✓ |
| rechargeable | ✓ | ✗ | ✗ | ✗ |
| decaying | ✗(衰减) | ✓ | ✗ | ✗ |
| resistant | ✗ | ✓ | ✓ | ✓ |

### 7. 持续时间机制

**duration 语义：**
- `duration > 0`：剩余帧数，每帧递减
- `duration = 0`：已过期，护盾失活
- `duration = -1`：永久，不会因时间过期

**过期处理流程：**
```
update() → duration -= deltaTime → duration <= 0
    → setActive(false)
    → onExpire()
    → return true
```

### 8. 临时盾 vs 永久盾

| 特性 | 临时盾 | 永久盾 |
|------|--------|--------|
| isTemporary | true | false |
| 击碎后 | 失活 | 保持活跃 |
| 可被移除 | 是（ShieldStack弹出） | 否 |
| 典型用途 | 技能/道具效果 | 装备/角色基础 |

### 9. 回调批量注册

```actionscript
shield.setCallbacks({
    onHit: function(shield:IShield, absorbed:Number):Void { },
    onBreak: function(shield:IShield):Void { },
    onRechargeStart: function(shield:IShield):Void { },
    onRechargeFull: function(shield:IShield):Void { },
    onExpire: function(shield:IShield):Void { }
});
```

**特点：**
- 支持链式调用
- 可部分设置
- 未设置的回调保持null

### 10. 重写方法

#### 10.1 update

```actionscript
public function update(deltaTime:Number):Boolean
```

**扩展行为：**
1. 先处理持续时间倒计时
2. 如果过期，失活并触发onExpire
3. 然后调用父类update处理充能/衰减

#### 10.2 onBreak

```actionscript
public function onBreak():Void
```

**扩展行为：**
- 如果是临时盾，自动调用 setActive(false)
- 然后调用父类onBreak

### 11. 性能指标

| 操作 | 迭代次数 | 耗时 | 平均耗时 |
|------|----------|------|----------|
| 工厂方法创建 | 4000 | ~112ms | 0.028ms/次 |
| update(带duration) | 10000 | ~38ms | 0.0038ms/次 |
| 完整生命周期 | 1000 | ~89ms | 0.089ms/次 |

### 12. 使用示例

#### 12.1 创建临时技能护盾

```actionscript
// 创建持续5秒(300帧)的技能护盾
var skillShield:Shield = Shield.createTemporary(200, 80, 300, "铁壁");

skillShield.setCallbacks({
    onBreak: function(s:IShield):Void {
        trace("铁壁被击碎！");
    },
    onExpire: function(s:IShield):Void {
        trace("铁壁效果结束");
    }
});
```

#### 12.2 创建角色基础护盾

```actionscript
// 创建可自动恢复的护盾
var baseShield:Shield = Shield.createRechargeable(500, 100, 2, 120, "能量护盾");

baseShield.setCallbacks({
    onRechargeFull: function(s:IShield):Void {
        trace("护盾充满");
    }
});
```

#### 12.3 创建衰减护盾

```actionscript
// 创建每秒衰减10点的护盾
var decayShield:Shield = Shield.createDecaying(300, 60, 0.17, "狂暴护盾");
// 0.17 * 60fps ≈ 10/秒
```

#### 12.4 创建抗真伤护盾

```actionscript
// 创建持续3秒的绝对防御
var resistShield:Shield = Shield.createResistant(100, 50, 180, "无敌护盾");

// 可抵抗真伤
var damage:Number = resistShield.absorbDamage(1000, true, 1);
// damage = 950 (仍然受强度限制)
```

### 13. 注意事项

1. **临时盾击碎**：临时盾击碎后会自动失活，会被ShieldStack弹出
2. **永久盾击碎**：永久盾击碎后保持活跃，可以继续充能
3. **duration=-1**：表示永久，不会因时间过期（但可能因击碎失活）
4. **衰减不受延迟**：衰减盾即使被命中也会继续衰减
5. **抗真伤有限制**：抗真伤只是让护盾能吸收真伤，仍受强度限制
