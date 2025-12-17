# BuffManager 技术文档

> **文档版本**: 1.0
> **最后更新**: 2024-12
> **状态**: 核心引擎稳定可用，高级组件功能受限

---

## 接入决策指南（必读）

在开始使用前，请根据你的需求场景选择正确的实现方式：

| 需求场景 | 推荐方案 | 说明 |
|----------|----------|------|
| 装备/被动的固定数值加成 | ✅ 直接使用 PodBuff | 最简单，直接可用 |
| 限时技能效果（如冲刺+50%移速5秒） | ✅ MetaBuff + TimeLimitComponent | 稳定可用 |
| 多属性同时修改 | ✅ MetaBuff 包装多个 PodBuff | 便于统一管理生命周期 |
| 可叠加效果（如击杀叠层） | ⚠️ 业务层计数 + 同ID替换 | 不要用 StackLimitComponent |
| 条件触发（如低血量激活） | ⚠️ 业务层判断 + add/remove | 不要用 ConditionComponent |
| 动态变化的数值 | ⚠️ 同ID替换驱动重算 | 不要用 setValue() |
| 运行时状态量（当前HP） | ❌ 不要用 BuffManager | 会导致逻辑错误 |
| 嵌套属性（unit.武器.power） | ❌ 需要适配层 | 见 6.3 节 |

**核心原则**：把 BuffManager 当作底层"数值修饰器引擎"，复杂业务逻辑放在上层控制。

---

## 目录

1. [快速开始](#1-快速开始)
2. [系统定位与边界](#2-系统定位与边界)
3. [核心概念](#3-核心概念)
4. [API 参考](#4-api-参考)
5. [使用模式与最佳实践](#5-使用模式与最佳实践)
   - 5.0 [Buff ID 命名规范](#50-buff-id-命名规范重要)
   - 5.0.1 [时间单位与 update 步长](#501-时间单位与-update-步长)
6. [已知限制与规避方案](#6-已知限制与规避方案)
   - 6.4 [属性接管的读写契约](#64-️-属性接管的读写契约重要)
7. [与旧系统的迁移指南](#7-与旧系统的迁移指南)
8. [架构设计详解](#8-架构设计详解)
9. [测试与验证](#9-测试与验证)
10. [常见问题](#10-常见问题)
11. [附录 A: 扩展协议（鸭子类型）](#附录-a-扩展协议鸭子类型)
12. [附录 B: 技术债与 Roadmap](#附录-b-技术债与-roadmap)
13. [附录 C: 文件清单](#附录-c-文件清单)

---

## 1. 快速开始

### 1.1 最小可用示例

```actionscript
import org.flashNight.arki.component.Buff.*;

// 1. 创建 BuffManager（通常在单位初始化时）
var unit:Object = { attack: 100, defense: 50 };
var buffManager:BuffManager = new BuffManager(unit, null);

// 2. 添加一个 +30 攻击力的 Buff
var atkBuff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 30);
buffManager.addBuff(atkBuff, "equip_sword");

// 3. 每帧更新
buffManager.update(1);

// 4. 读取最终值（透明访问，无需特殊 API）
trace(unit.attack); // 输出: 130
```

### 1.2 限时 Buff 示例

```actionscript
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

// 创建 5 秒（150帧@30fps）的 +50% 移速 Buff
var speedPods:Array = [
    new PodBuff("speed", BuffCalculationType.PERCENT, 0.5)
];
var timeLimit:TimeLimitComponent = new TimeLimitComponent(150);
var sprintBuff:MetaBuff = new MetaBuff(speedPods, [timeLimit], 0);

buffManager.addBuff(sprintBuff, "skill_sprint");
// 150 帧后自动移除
```

### 1.3 集成到现有单位系统

BuffManager 已通过 `BuffManagerInitializer` 集成到单位初始化流程：

```actionscript
// 单位上已有 buffManager 实例
unit.buffManager.addBuff(someBuff, "buff_id");

// 在 UpdateEventComponent 中自动调用
// unit.buffManager.update(4); // 每帧步长为 4
```

---

## 2. 系统定位与边界

### 2.1 BuffManager 是什么

BuffManager 是一个 **"数值属性修饰器引擎"**，核心能力：

| 能力 | 说明 |
|------|------|
| 属性接管 | 将 `target[prop]` 变为惰性计算的派生属性 |
| 数值叠加 | 支持 ADD/MULTIPLY/PERCENT/OVERRIDE/MAX/MIN 六种计算类型 |
| 生命周期管理 | 通过 MetaBuff + Component 控制 Buff 的存活 |
| 增量重算 | 只重算变化的属性，性能优化 |
| 事件回调 | onBuffAdded / onBuffRemoved / onPropertyChanged |

### 2.2 BuffManager 不是什么

**不要期望它直接处理：**

- ❌ 复杂的叠层逻辑（如"每层+10攻击，最多5层"的动态数值）
- ❌ 条件触发的反复激活/失效（如"HP<30%时生效"的门控）
- ❌ 技能冷却管理
- ❌ 嵌套属性（如 `unit.长枪属性.power`）
- ❌ 运行时状态量（如当前HP、能量）的修饰

### 2.3 能力边界图

```
┌─────────────────────────────────────────────────────────────┐
│                     业务层（技能/状态机）                      │
│  - 叠层计数                                                  │
│  - 条件判断                                                  │
│  - 冷却管理                                                  │
│  - 通过 add/remove/replace 驱动下层                          │
└──────────────────────────┬──────────────────────────────────┘
                           │ addBuff / removeBuff
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              BuffManager（数值修饰器引擎）✅ 可用            │
│  - PodBuff 原子数值修改                                      │
│  - MetaBuff + TimeLimitComponent 限时效果                    │
│  - PropertyContainer 属性代理                                │
│  - BuffCalculator 计算链                                    │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    PropertyAccessor                         │
│              透明劫持 target[prop] 的 get/set                │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 核心概念

### 3.1 双层 Buff 架构

```
IBuff (接口)
  ├── PodBuff     原子数值 Buff，直接参与计算
  └── MetaBuff    容器 Buff，管理 PodBuff 的生命周期，不参与计算
```

| 类型 | 职责 | 参与计算 | 使用场景 |
|------|------|----------|----------|
| **PodBuff** | 单一属性的数值修改 | ✅ 是 | 装备加成、永久被动 |
| **MetaBuff** | 包装一组 PodBuff + 生命周期组件 | ❌ 否 | 限时Buff、技能效果 |

### 3.2 计算类型与优先级

计算顺序 **固定且与添加顺序无关**：

```
ADD → MULTIPLY → PERCENT → MAX → MIN → OVERRIDE
```

| 类型 | 公式 | 示例 |
|------|------|------|
| `ADD` | `result += value` | +50 攻击力 |
| `MULTIPLY` | `result *= value` | ×1.5 倍率 |
| `PERCENT` | `result *= (1 + value)` | +30% (value=0.3) |
| `MAX` | `result = Math.max(result, value)` | 最低保底 100 |
| `MIN` | `result = Math.min(result, value)` | 最高上限 999 |
| `OVERRIDE` | `result = value` | 强制覆盖为固定值 |

**计算示例：**
```
base = 100
ADD +20      → 120
MULTIPLY ×1.5 → 180
PERCENT +10% → 198
MAX 150      → 198 (不变，已超过)
MIN 200      → 198 (不变，未超过)
```

### 3.3 注入机制（Injection）

MetaBuff **不直接参与计算**，而是在激活时将其包含的 PodBuff "注入"到 BuffManager：

```
MetaBuff 状态机:
  INACTIVE ──[激活]──► ACTIVE ──[失效]──► PENDING_DEACTIVATE ──► INACTIVE
                         │                        │
                    注入 PodBuff              弹出 PodBuff
```

### 3.4 Sticky 容器策略

PropertyContainer 一旦创建 **永不销毁**（除非显式调用 `unmanageProperty` 或 `destroy`）：

- Buff 清空后，属性仍存在，值回到 base
- 避免高频增删 Buff 导致属性变 `undefined`

**生命周期契约（重要）：**

| 操作 | 属性最终值 | 容器状态 |
|------|-----------|----------|
| `clearAllBuffs()` | **回到 base** | 保留 |
| `destroy()` | **回到 base** | 销毁（先 clear 再 finalize） |
| `unmanageProperty(prop, true)` | **保留当前可见值** | 销毁 |
| `unmanageProperty(prop, false)` | 删除属性 | 销毁 |

> **⚠️ 注意**：`destroy()` **不会保留 Buff 叠加后的最终值**！它的执行顺序是：先 `clearAllBuffs()`（回到 base），再 finalize。如需保留最终值，应提前对每个属性调用 `unmanageProperty(prop, true)`。

---

## 4. API 参考

### 4.1 BuffManager

```actionscript
// 构造函数
new BuffManager(target:Object, callbacks:Object)

// callbacks 结构（可选）
{
    onBuffAdded: function(id:String, buff:IBuff):Void,
    onBuffRemoved: function(id:String, buff:IBuff):Void,
    onPropertyChanged: function(propertyName:String, newValue:Number):Void
}
```

| 方法 | 说明 |
|------|------|
| `addBuff(buff:IBuff, buffId:String):String` | 添加 Buff，返回最终 ID。**同 ID 会替换旧实例** |
| `removeBuff(buffId:String):Boolean` | 延迟移除 Buff（下次 update 生效） |
| `update(deltaFrames:Number):Void` | 帧更新，处理生命周期和重算 |
| `clearAllBuffs():Void` | 清空所有 Buff，属性回到 base，容器保留 |
| `unmanageProperty(prop:String, finalize:Boolean):Void` | 解除属性托管。finalize=true 保留当前值，false 删除属性 |
| `getActiveBuffCount():Number` | 获取激活 Buff 数量 |
| `getDebugInfo():Object` | 调试信息 |
| `destroy():Void` | 销毁管理器。**先 clearAllBuffs 再 finalize**，最终值为 base |

**`unmanageProperty` 详解：**
```actionscript
// 场景：单位死亡时需要保留当前战斗属性（用于结算/显示）
buffManager.unmanageProperty("attack", true);  // attack 固化为当前值
buffManager.unmanageProperty("defense", true); // defense 固化为当前值
buffManager.destroy(); // 其他属性回到 base

// 场景：动态移除某个属性的托管（如切换武器类型）
buffManager.unmanageProperty("gunPower", false); // 直接删除
```

**影响范围：**
- `finalize=true`：属性上的独立 PodBuff 被移除，注入 Pod 由 MetaBuff 生命周期维护
- `finalize=false`：属性及相关 Buff 全部删除

### 4.2 PodBuff

```actionscript
new PodBuff(targetProperty:String, calculationType:String, value:Number)
```

| 方法 | 说明 |
|------|------|
| `getId():String` | 获取唯一 ID（自动生成） |
| `getTargetProperty():String` | 目标属性名 |
| `getCalculationType():String` | 计算类型 |
| `getValue():Number` | 当前数值 |
| `setValue(value:Number):Void` | **⚠️ 不会触发重算，见限制章节** |

### 4.3 MetaBuff

```actionscript
new MetaBuff(childBuffs:Array, components:Array, priority:Number)
// childBuffs: PodBuff 数组（模板）
// components: IBuffComponent 数组
// priority: 优先级（当前未使用）
```

| 方法 | 说明 |
|------|------|
| `isActive():Boolean` | 是否激活 |
| `deactivate():Void` | 手动停用 |
| `addComponent(comp:IBuffComponent):Void` | 动态添加组件 |
| `getCurrentState():Number` | 当前状态（调试用） |

### 4.4 组件（IBuffComponent）

| 组件 | 用途 | 可用性 |
|------|------|--------|
| `TimeLimitComponent(frames)` | 限时自动移除 | ✅ 稳定可用 |
| `StackLimitComponent(max, decay)` | 层数管理 | ⚠️ 需配合同ID替换 |
| `ConditionComponent(func, interval)` | 条件触发 | ⚠️ 语义受限 |
| `CooldownComponent(frames)` | 冷却管理 | ⚠️ 不控制 Buff 存活 |

### 4.5 BuffCalculationType 常量

```actionscript
BuffCalculationType.ADD       // "add"
BuffCalculationType.MULTIPLY  // "multiply"
BuffCalculationType.PERCENT   // "percent"
BuffCalculationType.OVERRIDE  // "override"
BuffCalculationType.MAX       // "max"
BuffCalculationType.MIN       // "min"
```

---

## 5. 使用模式与最佳实践

### 5.0 Buff ID 命名规范（重要）

#### ID 的作用

| 场景 | 说明 |
|------|------|
| 同 ID 替换 | `addBuff(newBuff, existingId)` 会**同步移除**旧实例，这是动态更新数值的唯一入口 |
| 手动移除 | `removeBuff(id)` 需要知道 ID |
| 防止重复 | 同 ID 不会叠加，只会替换 |

#### buffId vs buff.getId()

- `buffId`（传入参数）：业务层指定的逻辑 ID，用于管理
- `buff.getId()`（自动生成）：PodBuff/MetaBuff 内部的唯一标识

```actionscript
// 推荐：显式指定 ID
buffManager.addBuff(buff, "equip_weapon_atk");

// 不推荐：依赖自动生成 ID（难以管理）
buffManager.addBuff(buff); // 返回 buff.getId()，需自行保存
```

#### 推荐 ID 前缀

| 前缀 | 用途 | 示例 |
|------|------|------|
| `equip_` | 装备加成 | `equip_sword_123_atk` |
| `skill_` | 技能效果 | `skill_rage`, `skill_sprint` |
| `aura_` | 光环/被动 | `aura_leadership` |
| `debuff_` | 负面效果 | `debuff_poison`, `debuff_slow` |
| `env_` | 环境效果 | `env_zone_fire` |
| `temp_` | 临时效果 | `temp_potion_hp` |

#### 注入 Pod 的 ID

MetaBuff 注入的 PodBuff 会自动生成内部 ID（格式：`injected_xxx`），**仅供内部使用**：
- 不应在业务层引用
- 随 MetaBuff 生命周期自动管理
- 会触发 `onBuffAdded`/`onBuffRemoved` 回调

### 5.0.1 时间单位与 update 步长

#### 核心概念

`update(deltaFrames)` 的参数单位是 **帧数**，不是毫秒或秒。

```actionscript
// 当前工程配置（UpdateEventComponent）
buffManager.update(4); // 每次调用推进 4 帧
```

#### 时间换算

| 目标时长 | @30fps | @60fps | 公式 |
|----------|--------|--------|------|
| 1 秒 | 30 帧 | 60 帧 | `seconds * fps` |
| 5 秒 | 150 帧 | 300 帧 | |
| 10 秒 | 300 帧 | 600 帧 | |

```actionscript
// 换算工具函数
function secondsToFrames(seconds:Number, fps:Number):Number {
    return Math.round(seconds * (fps || 30));
}

// 使用示例
var duration:Number = secondsToFrames(5, 30); // 150 帧
var timeLimit:TimeLimitComponent = new TimeLimitComponent(duration);
```

#### 步长影响

当前工程使用 `update(4)` 意味着：
- 实际精度为 4 帧（约 133ms @30fps）
- TimeLimitComponent 的 duration 会按 4 帧步进消耗
- 设置 `duration=150` 实际持续 `150/4 ≈ 37-38 次 update`

> **⚠️ 注意**：如果修改 update 步长，需要同步调整所有 duration 参数！

### 5.1 推荐模式：快照式修饰器 + 同 ID 替换

**核心原则**：任何数值变化都通过 `addBuff(new PodBuff(...), fixedId)` 覆盖旧实例。

```actionscript
// ❌ 错误：直接修改 PodBuff 的值（不会触发重算）
existingBuff.setValue(newValue);

// ✅ 正确：用新实例替换
var newBuff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, newValue);
buffManager.addBuff(newBuff, "stack_attack"); // 同 ID 自动替换
```

### 5.2 叠层 Buff 实现

```actionscript
// 业务层维护层数
var stacks:Number = 0;
var maxStacks:Number = 5;
var valuePerStack:Number = 10;

function onKillEnemy():Void {
    if (stacks < maxStacks) {
        stacks++;
        // 用同 ID 替换，驱动重算
        var buff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, stacks * valuePerStack);
        unit.buffManager.addBuff(buff, "kill_stack");
    }
}

function onStackDecay():Void {
    if (stacks > 0) {
        stacks--;
        if (stacks == 0) {
            unit.buffManager.removeBuff("kill_stack");
        } else {
            var buff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, stacks * valuePerStack);
            unit.buffManager.addBuff(buff, "kill_stack");
        }
    }
}
```

### 5.3 条件触发 Buff 实现

```actionscript
// 业务层判断条件，控制 Buff 的增删
function checkBerserkCondition():Void {
    var shouldActive:Boolean = unit.hp < unit.maxHp * 0.3;
    var hasBuff:Boolean = /* 自行维护状态 */;

    if (shouldActive && !hasBuff) {
        // 激活
        var buff:PodBuff = new PodBuff("damage", BuffCalculationType.PERCENT, 0.5);
        unit.buffManager.addBuff(buff, "berserk");
        hasBuff = true;
    } else if (!shouldActive && hasBuff) {
        // 失效
        unit.buffManager.removeBuff("berserk");
        hasBuff = false;
    }
}
```

### 5.4 多属性 Buff（使用 MetaBuff）

```actionscript
// 一个技能同时影响多个属性
var pods:Array = [
    new PodBuff("attack", BuffCalculationType.PERCENT, 0.3),
    new PodBuff("speed", BuffCalculationType.PERCENT, 0.2),
    new PodBuff("defense", BuffCalculationType.PERCENT, -0.1) // 负面效果
];
var timeLimit:TimeLimitComponent = new TimeLimitComponent(300); // 10秒
var skillBuff:MetaBuff = new MetaBuff(pods, [timeLimit], 0);

unit.buffManager.addBuff(skillBuff, "skill_rage");
```

### 5.5 装备被动（永久 Buff）

```actionscript
// 装备时添加
function onEquip(equipData:Object):Void {
    if (equipData.attackBonus) {
        var buff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, equipData.attackBonus);
        unit.buffManager.addBuff(buff, "equip_" + equipData.id + "_atk");
    }
}

// 卸装时移除
function onUnequip(equipData:Object):Void {
    unit.buffManager.removeBuff("equip_" + equipData.id + "_atk");
}
```

---

## 6. 已知限制与规避方案

### 6.1 ⚠️ PodBuff.setValue() 不触发重算

**问题**：直接调用 `podBuff.setValue(newValue)` 不会通知 BuffManager 重算。

**原因**：PodBuff 不持有对 BuffManager 的引用，无法触发 dirty 标记。

**规避方案**：使用同 ID 替换模式（见 5.1）。

### 6.2 ⚠️ MetaBuff 组件的语义限制

**问题**：`IBuffComponent.update()` 返回 `false` 会导致组件被卸载，不适合"条件门控"场景。

**原因**：组件设计为"生命周期控制器"，而非"激活状态控制器"。

**规避方案**：
- 条件判断放到业务层，通过 add/remove 控制 Buff
- MetaBuff 仅用于 `TimeLimitComponent` 等明确生命周期的场景

### 6.3 ⚠️ 不支持嵌套属性

**问题**：无法直接管理 `unit.长枪属性.power` 这类嵌套属性。

**规避方案**：
```actionscript
// 方案 1：在 target 上创建代理属性
unit._weaponPower = unit.长枪属性.power;

// 方案 2：在回调中同步
callbacks.onPropertyChanged = function(prop:String, val:Number):Void {
    if (prop == "_weaponPower") {
        unit.长枪属性.power = val;
        unit.man.初始化长枪射击函数(); // 级联触发
    }
};
```

### 6.4 ⚠️ 属性接管的读写契约（重要）

**问题本质**：PropertyAccessor 接管属性后，读取返回"计算后的最终值"，写入则设置"base 值"。

**危险示例**：
```actionscript
// 假设 hp 被接管，base=100，有 +50 的 Buff
// 读取：unit.hp → 150（最终值）
// 写入：unit.hp = x → 设置 base = x

unit.hp -= 30;
// 展开为：unit.hp = unit.hp - 30
//        = 150 - 30
//        = 120 → 设置 base = 120
// 结果：base=120，最终值=170（而非期望的 70）
```

#### ✅ DO: 可以托管的属性

| 属性类型 | 示例 | 说明 |
|----------|------|------|
| 战斗属性 | `attack`, `defense`, `critRate` | 只读或整体替换 |
| 派生属性 | `maxHp`, `maxMp`, `moveSpeed` | 由 base + Buff 计算 |
| 装备属性 | `weaponPower`, `armorValue` | 装备切换时整体替换 |

#### ❌ DON'T: 不要托管的属性

| 属性类型 | 示例 | 原因 |
|----------|------|------|
| 运行时状态 | `currentHp`, `currentMp`, `energy` | 频繁增减操作 |
| 位置坐标 | `x`, `y`, `z` | 每帧变化 |
| 累计值 | `killCount`, `damageDealt` | 只增不减 |
| 布尔状态 | `isDead`, `isStunned` | 非数值类型 |

#### 正确的架构设计

```actionscript
// ✅ 正确：分离"上限"和"当前值"
unit.maxHp = 100;           // 被 BuffManager 托管
unit.currentHp = 100;       // 普通属性，直接读写

// Buff 加成最大HP
buffManager.addBuff(new PodBuff("maxHp", ADD, 50), "equip_hp");
// unit.maxHp 现在返回 150

// 受伤
unit.currentHp -= 30;       // 正常：120

// 回血
unit.currentHp = Math.min(unit.currentHp + 20, unit.maxHp); // 正常：140
```

### 6.5 ⚠️ 回调参数顺序

**注意**：`BuffManagerInitializer` 中的回调参数顺序与实际调用不一致。

```actionscript
// BuffManager 实际调用顺序
onBuffAdded(id, buff)
onBuffRemoved(id, buff)

// 正确的回调写法
{
    onBuffAdded: function(id:String, buff:IBuff):Void { ... },
    onBuffRemoved: function(id:String, buff:IBuff):Void { ... }
}
```

---

## 7. 与旧系统的迁移指南

### 7.1 旧系统（主角模板数值buff）对照

| 旧 API | 新 API |
|--------|--------|
| `buff.赋值("攻击力", "加算", 50)` | `addBuff(new PodBuff("attack", ADD, 50), id)` |
| `buff.赋值("攻击力", "倍率", 1.2)` | `addBuff(new PodBuff("attack", MULTIPLY, 1.2), id)` |
| `buff.限时赋值(5000, ...)` | `MetaBuff + TimeLimitComponent(150)` |
| `buff.调整(...)` | 业务层累加 + 同 ID 替换 |
| `buff.删除("攻击力", "加算")` | `removeBuff(id)` |

### 7.2 计算模型差异

| 旧系统 | 新系统 |
|--------|--------|
| `base * 倍率 + 加算` | `(base + ADD) * MULTIPLY * (1+PERCENT)` |
| 倍率/加算分开存储 | 统一计算链 |
| 增益/减益取极值 | 使用 MAX/MIN 类型实现 |

### 7.3 级联触发迁移

旧系统的级联（如武器威力变化触发初始化函数）需要通过回调实现：

```actionscript
var callbacks:Object = {
    onPropertyChanged: function(prop:String, value:Number):Void {
        switch (prop) {
            case "长枪威力":
                unit.长枪属性.power = value;
                unit.man.初始化长枪射击函数();
                break;
            case "速度":
                unit.行走X速度 = value;
                unit.行走Y速度 = value / 2;
                // ... 其他级联
                break;
        }
    }
};
```

---

## 8. 架构设计详解

### 8.1 类图

```
┌─────────────┐      ┌─────────────┐
│   IBuff     │◄─────│  BaseBuff   │
└─────────────┘      └──────┬──────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
       ┌──────▼──────┐             ┌──────▼──────┐
       │   PodBuff   │             │  MetaBuff   │
       │             │             │             │
       │ - property  │             │ - childBuffs│
       │ - calcType  │             │ - components│
       │ - value     │             │ - state     │
       └─────────────┘             └─────────────┘
                                          │
                                          │ 包含
                                          ▼
                                   ┌─────────────┐
                                   │IBuffComponent│
                                   └──────┬──────┘
                                          │
              ┌───────────┬───────────┬───┴───────┐
              │           │           │           │
        ┌─────▼─────┐ ┌───▼───┐ ┌─────▼─────┐ ┌───▼───┐
        │TimeLimit  │ │Stack  │ │Condition  │ │Cooldown│
        └───────────┘ └───────┘ └───────────┘ └───────┘

┌─────────────────────────────────────────────────────────┐
│                    BuffManager                          │
│                                                         │
│  - _buffs: Array           所有 Buff                    │
│  - _idMap: Object          ID → Buff 映射              │
│  - _propertyContainers     属性 → 容器映射              │
│  - _metaBuffInjections     Meta → 注入的 Pod ID        │
│  - _injectedPodBuffs       Pod ID → 父 Meta ID         │
│  - _pendingRemovals        延迟移除队列                 │
│  - _dirtyProps             脏属性集合                   │
└─────────────────────────────────────────────────────────┘
              │
              │ 管理
              ▼
┌─────────────────────────────────────────────────────────┐
│                  PropertyContainer                      │
│                                                         │
│  - _baseValue              基础值                       │
│  - _buffs: Array           该属性的 PodBuff 列表        │
│  - _calculator             BuffCalculator 实例          │
│  - _accessor               PropertyAccessor 实例        │
│  - _isDirty                脏标记                       │
└─────────────────────────────────────────────────────────┘
```

### 8.2 update() 执行流程

```
BuffManager.update(deltaFrames)
    │
    ├─► 1. _processPendingRemovals()
    │       处理延迟移除队列
    │
    ├─► 2. _updateMetaBuffsWithInjection(deltaFrames)
    │       │
    │       ├─► 更新所有 MetaBuff
    │       │
    │       ├─► 检测状态变化
    │       │     needsInject → _injectMetaBuffPods()
    │       │     needsEject  → _ejectMetaBuffPods()
    │       │
    │       └─► 移除失效的 MetaBuff
    │
    ├─► 3. _removeInactivePodBuffs()
    │       移除失效的独立 PodBuff
    │
    └─► 4. if (_isDirty)
            │
            ├─► _redistributeDirtyProps() 或 _redistributePodBuffs()
            │       重新分配 PodBuff 到对应 PropertyContainer
            │
            └─► PropertyContainer.forceRecalculate()
                    触发数值重算
```

### 8.3 计算链路

```
PropertyContainer._computeFinalValue()
    │
    ├─► BuffCalculator.reset()
    │
    ├─► for each PodBuff in _buffs:
    │       if (buff.isActive())
    │           buff.applyEffect(calculator, context)
    │               │
    │               └─► calculator.addModification(type, value)
    │
    └─► BuffCalculator.calculate(baseValue)
            │
            ├─► 累加所有 ADD
            ├─► 依次应用 MULTIPLY
            ├─► 依次应用 PERCENT
            ├─► 应用 MAX
            ├─► 应用 MIN
            └─► 应用 OVERRIDE（如有）
```

---

## 9. 测试与验证

### 9.1 运行测试

```actionscript
// 核心功能测试（40 个用例）
org.flashNight.arki.component.Buff.test.BuffManagerTest.runAllTests();

// 组件测试（12 个用例，2 个已知失败）
org.flashNight.arki.component.Buff.test.Tier1ComponentTest.runAllTests();
```

### 9.2 测试覆盖状态

| 测试类别 | 通过/总数 | 状态 |
|----------|-----------|------|
| 基础计算 | 5/5 | ✅ |
| MetaBuff 注入 | 4/4 | ✅ |
| 限时组件 | 4/4 | ✅ |
| 复杂场景 | 4/4 | ✅ |
| PropertyContainer | 4/4 | ✅ |
| 边界情况 | 4/4 | ✅ |
| 性能测试 | 3/3 | ✅ |
| Sticky 容器 | 7/7 | ✅ |
| 回归测试 | 5/5 | ✅ |
| **核心功能总计** | **40/40** | ✅ |
| 组件集成测试 | 10/12 | ⚠️ |

### 9.3 已知失败的测试

| 测试 | 失败原因 | 影响 |
|------|----------|------|
| StackLimit with MetaBuff | `setValue()` 不触发重算 | 使用同 ID 替换规避 |
| Condition with MetaBuff | 组件语义不支持条件门控 | 业务层控制 add/remove |

### 9.4 性能基准

```
100 Buffs + 100 Updates = 63ms
平均每次 update: 0.63ms
单次大规模计算: 7ms (100 Buffs)
```

---

## 10. 常见问题

### Q1: 为什么我修改了 PodBuff 的值，属性没变化？

`PodBuff.setValue()` 不会触发重算。使用同 ID 替换：
```actionscript
buffManager.addBuff(new PodBuff(..., newValue), sameId);
```

### Q2: 如何实现"HP低于30%时+50%伤害"？

在业务层判断条件，控制 Buff 的增删：
```actionscript
// 在每帧或HP变化时检查
if (hp < maxHp * 0.3 && !hasBerserk) {
    buffManager.addBuff(berserkBuff, "berserk");
} else if (hp >= maxHp * 0.3 && hasBerserk) {
    buffManager.removeBuff("berserk");
}
```

### Q3: MetaBuff 移除后属性变成 undefined？

不会。Sticky 容器策略保证属性始终存在，Buff 清空后值回到 base。

### Q4: 如何实现旧系统的"倍率取最大值"？

使用两个 Buff 配合：
```actionscript
// 实际倍率 Buff
addBuff(new PodBuff("attack", MULTIPLY, 1.5), "mult_buff");
// 保底值（可选）
addBuff(new PodBuff("attack", MAX, baseAttack * 1.2), "mult_floor");
```

### Q5: 能否管理 `unit.长枪属性.power`？

不能直接管理。方案：
1. 创建代理属性 `unit._gunPower`
2. 在 `onPropertyChanged` 回调中同步到嵌套属性

### Q6: Buff 添加顺序会影响计算结果吗？

不会。计算顺序固定为 `ADD → MULTIPLY → PERCENT → MAX → MIN → OVERRIDE`。

---

## 附录 A: 扩展协议（鸭子类型）

BuffManager 使用鸭子类型检测来支持自定义实现。如果需要创建自定义 Buff 类型，必须实现以下协议：

### A.1 自定义 PodBuff 协议

```actionscript
// 必须实现的方法
function isPod():Boolean { return true; }
function getId():String { return _id; }
function getTargetProperty():String { return _property; }
function isActive():Boolean { return _active; }
function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void { ... }
```

### A.2 自定义 MetaBuff 协议

```actionscript
// 必须实现的方法
function isPod():Boolean { return false; }
function getId():String { return _id; }
function isActive():Boolean { return _state == STATE_ACTIVE; }
function update(deltaFrames:Number):Boolean { ... } // 返回 false 表示失效

// 可选：支持注入机制
function createPodBuffsForInjection():Array { ... } // 返回 PodBuff 数组
function needsInject():Boolean { ... }
function needsEject():Boolean { ... }
function clearInjectionFlags():Void { ... }
```

### A.3 自定义组件协议

```actionscript
// 必须实现 IBuffComponent
function onAttach(host:IBuff):Void { ... }
function onDetach():Void { ... }
function update(host:IBuff, deltaFrames:Number):Boolean { ... } // 返回 false 会被卸载
```

> **注意**：当前组件的 `update` 返回 `false` 表示"组件生命周期结束并被卸载"，而非"条件不满足暂时禁用"。

---

## 附录 B: 技术债与 Roadmap

### B.1 已知技术债

| 问题 | 影响 | 建议处理方式 |
|------|------|--------------|
| `PodBuff.setValue()` 不触发重算 | 需要用同 ID 替换 | **业务层绕过**，或移除该方法避免误用 |
| 组件语义（Active vs Alive 未分离） | 不支持条件门控 | **业务层绕过**，或重构组件协议 |
| 回调参数顺序不一致 | 潜在 bug | 修复 BuffManagerInitializer |
| 注入 Pod ID 暴露给回调 | 回调噪音 | 可选：增加过滤参数 |
| 优先级字段未使用 | MetaBuff._priority 无效 | 未来实现或移除 |

### B.2 可能的改进方向

1. **显式 invalidate API**
   ```actionscript
   // 方案：PodBuff 持有 manager 引用
   podBuff.setValue(newValue);
   podBuff.invalidate(); // 或 manager.markDirty(podBuff)
   ```

2. **组件协议重构**
   ```actionscript
   // 分离 Alive（生命周期）和 Active（激活状态）
   function isAlive():Boolean { ... }   // false = 组件销毁
   function isActive():Boolean { ... }  // false = 暂时禁用，不注入 Pod
   ```

3. **属性分组批量操作**
   ```actionscript
   buffManager.removeBuffsByTag("debuff"); // 移除所有 debuff
   ```

### B.3 接入建议

| 场景 | 建议 |
|------|------|
| 当前能正常工作 | 继续使用，在业务层绕过限制 |
| 需要条件门控 | 业务层控制 add/remove |
| 需要动态数值 | 同 ID 替换 |
| 遇到组件 bug | 优先在业务层处理，底层修复需评估影响 |

---

## 附录 C: 文件清单

| 文件 | 说明 |
|------|------|
| `BuffManager.as` | 核心管理器 |
| `IBuff.as` | Buff 接口 |
| `BaseBuff.as` | Buff 基类 |
| `PodBuff.as` | 原子数值 Buff |
| `MetaBuff.as` | 容器 Buff |
| `PropertyContainer.as` | 属性容器 |
| `BuffCalculator.as` | 计算引擎 |
| `BuffCalculationType.as` | 计算类型常量 |
| `BuffContext.as` | 计算上下文 |
| `IBuffCalculator.as` | 计算器接口 |
| `Component/IBuffComponent.as` | 组件接口 |
| `Component/TimeLimitComponent.as` | 限时组件 |
| `Component/StackLimitComponent.as` | 层数组件 |
| `Component/ConditionComponent.as` | 条件组件 |
| `Component/CooldownComponent.as` | 冷却组件 |

---

## 附录 B: 测试结果存档

```
=== BuffManager Calculation Accuracy Test Suite ===

--- Phase 1: Basic Calculation Tests ---
🧪 Test 1: Basic ADD Calculation
  ✓ ADD: 100 + 30 + 20 = 150
  ✅ PASSED

🧪 Test 2: Basic MULTIPLY Calculation
  ✓ MULTIPLY: 50 * 1.5 * 1.2 = 90
  ✅ PASSED

🧪 Test 3: Basic PERCENT Calculation
  ✓ PERCENT: 100 * 1.2 * 1.1 = 132
  ✅ PASSED

🧪 Test 4: Calculation Types Priority
  ✓ Priority: (100 + 20) * 1.5 * 1.1 = 198
  ✅ PASSED

🧪 Test 5: OVERRIDE Calculation
  ✓ OVERRIDE: All calculations → 100
  ✅ PASSED


--- Phase 2: MetaBuff Injection & Calculation ---
🧪 Test 6: MetaBuff Pod Injection
  ✓ MetaBuff injection: (50 + 25) * 1.2 = 90
  ✅ PASSED

🧪 Test 7: MetaBuff Calculation Accuracy
  ✓ Damage: (100 + 50) * 1.3 = 195
  ✓ Critical: 1.5 + 0.5 = 2
  ✅ PASSED

🧪 Test 8: MetaBuff State Transitions & Calculations
  ✓ State transitions: 75 → 75 → 75 → 20 (expired)
  ✅ PASSED

🧪 Test 9: MetaBuff Dynamic Injection
  ✓ Dynamic injection: 120 → 198
  ✅ PASSED


--- Phase 3: TimeLimitComponent & Dynamic Calculations ---
🧪 Test 10: Time-Limited Buff Calculations
  ✓ Time-limited calculations: 180 → 120 → 100
  ✅ PASSED

🧪 Test 11: Dynamic Calculation Updates
  ✓ Dynamic updates: 450 → 300 → 200
  ✅ PASSED

🧪 Test 12: Buff Expiration Calculations
  ✓ Cascading expiration: 110 → 100 → 80 → 50
  ✅ PASSED

🧪 Test 13: Cascading Buff Calculations
  ✓ Cascading calculations: 390 → 195 → 150
  ✅ PASSED


--- Phase 4: Complex Calculation Scenarios ---
🧪 Test 14: Stacking Buff Calculations
  ✓ Stacking: 5 stacks (150) → 3 stacks (130)
  ✅ PASSED

🧪 Test 15: Multi-Property Calculations
  ✓ Multi-property: Phys 120, Mag 104, Heal 75
  ✅ PASSED

🧪 Test 16: Calculation Order Dependency
  ✓ Order dependency: 100 → 120 → 144 → 216 → 216 → 200
  ✅ PASSED

🧪 Test 17: Real Game Calculation Scenario
  ✓ Combat stats: AD 195, AS 1.5, CC 30%, CD 200%
  ✓ DPS increase: 246%
  ✅ PASSED


--- Phase 5: PropertyContainer Integration ---
🧪 Test 18: PropertyContainer Calculations
  ✓ PropertyContainer: (200 + 100) * 1.5 = 450
  ✓ Callbacks fired: 22 times
  ✅ PASSED

🧪 Test 19: Dynamic Property Recalculation
  ✓ Dynamic recalc: 75 → 150 → 100
  ✅ PASSED

🧪 Test 20: PropertyContainer Rebuild Accuracy
  ✓ Container rebuild: accurate calculations maintained
  ✅ PASSED

🧪 Test 21: Concurrent Property Updates
  ✓ Concurrent updates handled correctly
  ✅ PASSED


--- Phase 6: Edge Cases & Accuracy ---
🧪 Test 22: Extreme Value Calculations
  ✓ Extreme values: 1M and 0.000001 handled correctly
  ✅ PASSED

🧪 Test 23: Floating Point Accuracy
  ✓ Floating point: 10 * 1.1³ = 13.31 (±0.01)
  ✅ PASSED

🧪 Test 24: Negative Value Calculations
  ✓ Negative values: 100 → 20 → 10
  ✅ PASSED

🧪 Test 25: Zero Value Handling
  ✓ Zero handling: 0+50=50, 100*0=0
  ✅ PASSED


--- Phase 7: Performance & Accuracy at Scale ---
🧪 Test 26: Large Scale Calculation Accuracy
  ✓ 100 buffs: sum = 6050 (accurate)
  ✅ PASSED

🧪 Test 27: Calculation Performance
  ✓ Performance: 100 buffs, 100 updates in 56ms
  ✅ PASSED

🧪 Test 28: Memory and Calculation Consistency
  ✓ Consistency maintained across 10 rounds
  ✅ PASSED


--- Phase: Sticky Container & Lifecycle Contracts ---
🧪 Test 29: Sticky container: meta jitter won't delete property
  ✅ PASSED

🧪 Test 30: unmanageProperty(finalize) then rebind uses plain value as base (independent Pods are cleaned)
  ✅ PASSED

🧪 Test 31: destroy() finalizes all managed properties
  ✅ PASSED

🧪 Test 32: Base value: zero vs undefined
  ✅ PASSED

🧪 Test 33: Calculation order independent of add sequence
  ✅ PASSED

🧪 Test 34: clearAllBuffs keeps properties and resets to base
  ✅ PASSED

🧪 Test 35: MetaBuff jitter stability (no undefined during flips)
  ✅ PASSED

--- Phase 8: Regression & Lifecycle Contracts ---
🧪 Test 36: Same-ID replacement keeps only the new instance
  ✅ PASSED

🧪 Test 37: Injected Pods fire onBuffAdded for each injected pod
  ✅ PASSED

🧪 Test 38: Remove injected pod shrinks injected map by 1
  ✅ PASSED

🧪 Test 39: clearAllBuffs emits onBuffRemoved for independent pods
  ✅ PASSED

🧪 Test 40: removeBuff de-dup removes only once
  ✅ PASSED


=== Calculation Accuracy Test Results ===
📊 Total tests: 40
✅ Passed: 40
❌ Failed: 0
📈 Success rate: 100%
🎉 All calculation tests passed! BuffManager calculations are accurate.
==============================================

=== Calculation Performance Results ===
📊 Large Scale Accuracy:
   buffCount: 100
   calculationTime: 6ms
   expectedValue: 6050
   actualValue: 6050
   accurate: true

📊 Calculation Performance:
   totalBuffs: 100
   properties: 5
   updates: 100
   totalTime: 56ms
   avgUpdateTime: 0.56ms per update

=======================================

```
