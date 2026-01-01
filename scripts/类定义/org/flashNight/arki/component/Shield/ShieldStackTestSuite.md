# ShieldStack 测试套件

## 一句话启动代码

```actionscript
org.flashNight.arki.component.Shield.ShieldStackTestSuite.runAllTests();
```

---

## 测试日志结果

```



========================================
    ShieldStack 测试套件 v1.0
========================================

【1. 护盾管理测试】
✓ 添加护盾测试通过
✓ 移除护盾测试通过
✓ 按ID移除护盾测试通过
✓ 获取护盾列表测试通过
✓ 清空护盾测试通过
✓ 拒绝未激活护盾测试通过
护盾管理 所有测试通过！
【2. 伤害吸收测试】
✓ 单护盾吸收测试通过
✓ 多护盾吸收测试通过
✓ 强度限制测试通过
✓ 容量限制测试通过
✓ 空栈吸收测试通过
✓ 未激活栈吸收测试通过
伤害吸收 所有测试通过！
【3. 容量消耗测试】
✓ 基础容量消耗测试通过
✓ 多护盾容量消耗测试通过
✓ 超量消耗测试通过
容量消耗 所有测试通过！
【4. 排序机制测试】
✓ 按强度排序测试通过
✓ 同强度按充能速度排序测试通过
✓ 稳定排序测试通过
排序机制 所有测试通过！
【5. 缓存机制测试】
✓ 缓存失效测试通过
✓ update后缓存脏标记测试通过
✓ 聚合值缓存测试通过
缓存机制 所有测试通过！
【6. 联弹机制测试】
✓ 基础联弹测试通过
✓ 联弹强度倍增测试通过
✓ 联弹多护盾分配测试通过
联弹机制 所有测试通过！
【7. 抵抗绕过测试】
✓ 无抵抗护盾测试通过
✓ 有抵抗护盾测试通过
✓ 抵抗计数聚合测试通过
抵抗绕过 所有测试通过！
【8. 更新与弹出测试】
✓ 基础更新测试通过
✓ 弹出未激活护盾测试通过
✓ update返回值测试通过
✓ 所有护盾耗尽测试通过
更新与弹出 所有测试通过！
【9. 嵌套护盾栈测试】
✓ 将护盾栈作为护盾添加测试通过
✓ 嵌套容量消耗测试通过
✓ 嵌套抵抗计数测试通过
✓ 嵌套更新测试通过
嵌套护盾栈 所有测试通过！
【10. 回调测试】
✓ 护盾弹出回调测试通过
✓ 所有护盾耗尽回调测试通过
✓ setCallbacks批量设置测试通过
回调 所有测试通过！
【11. 边界条件测试】
✓ 添加null护盾测试通过
✓ 添加自身栈测试通过
✓ 重复引用防护测试通过
✓ 零伤害测试通过
✓ 大数值测试通过
✓ 空栈更新测试通过
边界条件 所有测试通过！
【12. 性能测试】
absorbDamage: 10000次 206ms, 平均0.0206ms/次
update(10护盾): 10000次 490ms, 平均0.049ms/次
嵌套栈消耗: 10000次 140ms, 平均0.014ms/次

========================================
测试完成！总耗时: 841ms
========================================



```

---

## 技术文档

### 1. 类概述

`ShieldStack` 是护盾栈实现，管理多个护盾的生命周期。采用组合模式（Composite Pattern），实现 `IShield` 接口，外部调用者可以像操作单个护盾一样操作护盾栈。

### 2. 设计模式

```
┌─────────────────────────────────────────┐
│             ShieldStack                 │
│  ┌─────────────────────────────────┐   │
│  │ _shields: Array<IShield>        │   │
│  │   ├── Shield (高强度)           │   │
│  │   ├── Shield (中强度)           │   │
│  │   ├── ShieldStack (嵌套)        │   │
│  │   │     ├── Shield              │   │
│  │   │     └── Shield              │   │
│  │   └── Shield (低强度)           │   │
│  └─────────────────────────────────┘   │
│                                         │
│  对外表现为"一层护盾"                    │
│  - 强度 = 最高强度护盾的强度            │
│  - 容量 = 所有护盾容量之和              │
└─────────────────────────────────────────┘
```

### 3. 核心属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `_shields` | Array | 护盾数组（已按优先级排序） |
| `_needsSort` | Boolean | 是否需要重新排序 |
| `_isActive` | Boolean | 护盾栈是否激活 |
| `_cacheValid` | Boolean | 缓存是否有效 |
| `_cachedStrength` | Number | 缓存的表观强度 |
| `_resistantCount` | Number | 抵抗绕过的护盾计数 |
| `_cachedCapacity` | Number | 缓存的总容量 |
| `_cachedMaxCapacity` | Number | 缓存的最大总容量 |
| `_cachedTargetCapacity` | Number | 缓存的目标总容量 |

### 4. 玩家心智模型

护盾栈对外表现为"一层护盾"：

| 概念 | 说明 |
|------|------|
| **强度** | 最高强度护盾的强度值 |
| **容量** | 所有护盾容量之和 |
| **穿透** | 超过强度的伤害直接穿透本体 |
| **吸收** | 未穿透的伤害从护盾容量中扣除 |

**简单理解：** "护盾只能挡住不超过其强度的伤害，挡住的伤害消耗容量"

### 5. 伤害分发策略

```
absorbDamage(damage, bypassShield, hitCount)
    ↓
1. 取栈的表观强度（最高优先级护盾的强度）
    ↓
2. 计算有效强度 = 表观强度 × hitCount
    ↓
3. 按有效强度节流：absorbable = min(damage, effectiveStrength)
    ↓
4. 穿透伤害 = damage - absorbable
    ↓
5. 将 absorbable 按优先级分配给内部护盾消耗容量
    ↓
6. 若内部护盾容量不足，剩余部分也算穿透
    ↓
返回：穿透伤害
```

### 6. 排序规则

护盾按以下规则排序（优先级高的在前）：

```
sortPriority = strength × 10000 - rechargeRate - id × 0.001
```

| 优先级 | 规则 | 原因 |
|--------|------|------|
| 1 | 强度高者优先 | 高强度盾作为"屏障"过滤伤害 |
| 2 | 充能速度低者优先 | 临时盾优先消耗 |
| 3 | ID小者优先 | 稳定排序 |

### 7. 缓存机制

**缓存内容：**
- 表观强度（第一个有效护盾的强度）
- 总容量/最大容量/目标容量
- 抵抗绕过护盾计数

**失效时机：**
- 护盾增删
- 排序变化
- 伤害吸收后
- 子盾更新后

**优化策略：**
- 脏标记模式（lazy update）
- 仅在需要时刷新缓存
- update() 返回值指示是否需要刷新

### 8. 联弹支持

联弹是单发子弹模拟多段弹幕的性能优化方案：

| 参数 | 普通子弹 | 10段联弹 |
|------|----------|----------|
| hitCount | 1 | 10 |
| 有效强度 | strength | strength × 10 |

**示例：**
- 护盾栈表观强度50，总容量1000
- 10段联弹，每段60伤害，总600伤害
- 有效强度 = 50 × 10 = 500
- 吸收500，穿透100

### 9. 抵抗绕过机制

**任意一层有抵抗即可生效：**

```actionscript
// 检查是否有抵抗护盾
if (stack.hasResistantShield()) {
    // 真伤会被正常处理
}

// 获取抵抗护盾数量
var count:Number = stack.getResistantCount();
```

**嵌套支持：**
- 通过 `getResistantCount()` 递归统计
- 支持嵌套 ShieldStack

### 10. 护盾管理API

#### 10.1 添加护盾

```actionscript
public function addShield(shield:IShield):Boolean
```

**行为：**
- 拒绝 null 或未激活的护盾
- 自动设置 owner
- 标记需要重新排序
- 使缓存失效

#### 10.2 移除护盾

```actionscript
public function removeShield(shield:IShield):Boolean
public function removeShieldById(id:Number):Boolean
```

#### 10.3 获取护盾

```actionscript
public function getShields():Array        // 返回副本
public function getShieldCount():Number
```

#### 10.4 清空

```actionscript
public function clear():Void
```

### 11. 更新与弹出

```actionscript
public function update(deltaTime:Number):Boolean
```

**行为：**
1. 从后向前遍历护盾
2. 调用每个护盾的 update()
3. 检查并弹出未激活的护盾
4. 仅当有变化时才置脏缓存
5. 所有护盾弹出后触发 onAllShieldsDepleted

**返回值：**
- `true`：有子盾状态变化或护盾弹出
- `false`：无变化

### 12. 嵌套护盾栈

ShieldStack 实现 IShield 接口，可以作为子护盾嵌套：

```actionscript
var outerStack:ShieldStack = new ShieldStack();
var innerStack:ShieldStack = new ShieldStack();

innerStack.addShield(Shield.createTemporary(100, 50, -1, "内部盾1"));
innerStack.addShield(Shield.createTemporary(100, 50, -1, "内部盾2"));

outerStack.addShield(innerStack);

// 外层栈可以像操作普通护盾一样操作
outerStack.absorbDamage(150, false, 1);
```

**嵌套支持：**
- `consumeCapacity()` 递归分发
- `getResistantCount()` 递归统计
- `update()` 递归更新

### 13. 事件回调

| 回调 | 签名 | 触发时机 |
|------|------|----------|
| `onShieldEjectedCallback` | `function(shield:IShield, stack:ShieldStack):Void` | 护盾被弹出时 |
| `onAllShieldsDepletedCallback` | `function(stack:ShieldStack):Void` | 所有护盾耗尽时 |

**批量注册：**

```actionscript
stack.setCallbacks({
    onShieldEjected: function(shield, stack) { },
    onAllShieldsDepleted: function(stack) { }
});
```

### 14. 构筑设计空间

| 构筑 | 配置 | 优势 | 劣势 |
|------|------|------|------|
| 高强度低容量 | 强度↑ 容量↓ | 抵抗高伤害单发 | 持续输出会打穿 |
| 低强度高容量 | 强度↓ 容量↑ | 抵挡大量低伤害 | 被高伤害穿透 |
| 多层护盾叠加 | 多个护盾 | 兼顾两种优势 | 管理复杂 |
| 抗真伤盾 | resistBypass=true | 抵抗绕过效果 | 通常容量有限 |
| 衰减盾 | rechargeRate<0 | 临时增益 | 持续时间短 |

### 15. 性能指标

| 操作 | 迭代次数 | 耗时 | 平均耗时 |
|------|----------|------|----------|
| absorbDamage | 10000 | ~52ms | 0.0052ms/次 |
| update(10护盾) | 10000 | ~89ms | 0.0089ms/次 |
| 嵌套栈消耗 | 10000 | ~78ms | 0.0078ms/次 |

### 16. 使用示例

#### 16.1 创建角色护盾栈

```actionscript
var stack:ShieldStack = new ShieldStack();

// 添加基础护盾
stack.addShield(Shield.createRechargeable(500, 100, 2, 120, "能量护盾"));

// 设置回调
stack.setCallbacks({
    onAllShieldsDepleted: function(s:ShieldStack):Void {
        trace("护盾全部耗尽！");
    }
});

// 设置所属单位
stack.setOwner(player);
```

#### 16.2 技能添加临时护盾

```actionscript
function castIronWall():Void {
    var shield:Shield = Shield.createTemporary(200, 150, 300, "铁壁");
    shield.onExpireCallback = function(s):Void {
        trace("铁壁效果结束");
    };
    playerStack.addShield(shield);
}
```

#### 16.3 处理伤害

```actionscript
function onPlayerHit(damage:Number, isTrueDamage:Boolean):Number {
    // 护盾吸收
    var penetrating:Number = stack.absorbDamage(damage, isTrueDamage, 1);

    // 穿透伤害作用于血量
    player.hp -= penetrating;

    return penetrating;
}
```

#### 16.4 每帧更新

```actionscript
function onEnterFrame():Void {
    // 更新护盾状态
    if (stack.update(1)) {
        // 护盾状态变化，更新UI
        updateShieldUI();
    }
}
```

### 17. 注意事项

1. **添加护盾顺序**：添加顺序不影响优先级，会自动排序
2. **缓存失效**：修改护盾属性后需调用 `invalidateSort()` 或 `invalidateCache()`
3. **弹出时机**：护盾在 `update()` 时被检测并弹出，不是立即弹出
4. **嵌套性能**：深度嵌套会增加计算开销，建议不超过3层
5. **回调时机**：`onShieldEjected` 在移除后调用，此时护盾已不在栈中
