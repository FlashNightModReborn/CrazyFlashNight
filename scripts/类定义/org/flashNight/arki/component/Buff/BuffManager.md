# BuffManager 技术文档

> **文档版本**: 2.9
> **最后更新**: 2026-01-20
> **状态**: 核心引擎稳定可用，v2.9新增base值操作API和批量操作API

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
14. [附录 D: 设计契约](#附录-d-设计契约)

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

### 1.3 立即生效 Buff 示例（addBuffImmediate）

当添加 buff 后需要立即读取更新后的属性值时（如播报数值），使用 `addBuffImmediate`：

```actionscript
// 场景：技能发动时播报更新后的攻击力
var attackBuff:PodBuff = new PodBuff("空手攻击力", BuffCalculationType.MULT_POSITIVE, 1.5);
var metaBuff:MetaBuff = new MetaBuff([attackBuff], [], 0);

// 使用 addBuffImmediate，buff 效果立即应用
unit.buffManager.addBuffImmediate(metaBuff, "狮子之力");

// 此时可以立即读取更新后的值（无需等待下一帧）
_root.发布消息("攻击力提升至" + unit.空手攻击力 + "点！");
```

**`addBuff` vs `addBuffImmediate` 对比：**

| 方法 | 效果生效时机 | 使用场景 |
|------|-------------|----------|
| `addBuff` | 下一次 `update()` 调用时 | 一般情况，性能更好 |
| `addBuffImmediate` | 立即（内部自动调用 `update(0)`） | 需要立即读取更新后的值 |

**注意**：如果在 `update()` 期间调用 `addBuffImmediate`（如在回调中），buff 会进入延迟队列，不会立即生效（重入安全设计）。

### 1.4 集成到现有单位系统

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
| 数值叠加 | 支持 10 种计算类型：通用语义（ADD/MULTIPLY/PERCENT）+ 保守语义（ADD_POSITIVE/ADD_NEGATIVE/MULT_POSITIVE/MULT_NEGATIVE）+ 边界控制（MAX/MIN/OVERRIDE） |
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

#### 3.2.1 设计理念：防止数值膨胀

为了防止数值膨胀，系统将语义分为两类：

| 语义类型 | 特点 | 适用场景 |
|----------|------|----------|
| **通用语义（叠加型）** | 同类型多个 Buff 会叠加/累积 | 装备加成、常规技能效果 |
| **保守语义（独占型）** | 同类型多个 Buff 只取极值（最强效果） | 限制膨胀的关键增益/减益 |

**乘区相加设计**：MULTIPLY 和 PERCENT 使用乘区相加而非连乘，防止指数膨胀：
- 旧方案（连乘）：`base × 1.1 × 1.2 × 1.3 = base × 1.716` (3个+10%/+20%/+30% = 71.6%增幅)
- 新方案（乘区相加）：`base × (1 + 0.1 + 0.2 + 0.3) = base × 1.6` (60%增幅，更可控)

#### 3.2.2 计算类型一览

**通用语义（叠加型）**：
| 类型 | 公式 | 示例 | 说明 |
|------|------|------|------|
| `MULTIPLY` | `base × (1 + Σ(m-1))` | 1.5 + 1.2 → ×1.7 | 乘区相加，所有乘数-1后累加 |
| `PERCENT` | `result × (1 + Σp)` | +20% + +10% → ×1.3 | 乘区相加，所有百分比累加 |
| `ADD` | `result += Σvalue` | +30 + +20 = +50 | 所有加值累加 |

**保守语义（独占型）**：
| 类型 | 公式 | 示例 | 说明 |
|------|------|------|------|
| `MULT_POSITIVE` | `result × max(m)` | 1.5, 1.3 → ×1.5 | 正向乘法取最大值 |
| `MULT_NEGATIVE` | `result × min(m)` | 0.7, 0.8 → ×0.7 | 负向乘法取最小值 |
| `ADD_POSITIVE` | `result += max(v)` | +50, +30 → +50 | 正向加法取最大值 |
| `ADD_NEGATIVE` | `result += min(v)` | -20, -30 → -30 | 负向加法取最小值 |

**边界控制**：
| 类型 | 公式 | 示例 | 说明 |
|------|------|------|------|
| `MAX` | `result = max(result, value)` | 最低保底 100 | 结果不低于此值 |
| `MIN` | `result = min(result, value)` | 最高上限 999 | 结果不高于此值 |
| `OVERRIDE` | `result = value` | 强制覆盖为 50 | 无视其他计算 |

#### 3.2.3 计算顺序（固定，与添加顺序无关）

```
MULTIPLY → MULT_POSITIVE → MULT_NEGATIVE → PERCENT → ADD → ADD_POSITIVE → ADD_NEGATIVE → MAX → MIN → OVERRIDE
```

**完整计算公式**：
```
result = base
result = result × (1 + Σ(multiply-1))      // 通用乘法（乘区相加）
result = result × multPositiveMax          // 保守正向乘法（取最大）
result = result × multNegativeMin          // 保守负向乘法（取最小）
result = result × (1 + Σpercent)           // 通用百分比（乘区相加）
result = result + Σadd                     // 通用加法
result = result + addPositiveMax           // 保守正向加法（取最大）
result = result + addNegativeMin           // 保守负向加法（取最小）
result = max(result, maxValue)             // 下限
result = min(result, minValue)             // 上限
result = overrideValue                     // 强制覆盖（如有）
```

#### 3.2.4 计算示例

**示例 1：通用语义叠加**
```
base = 100
MULTIPLY ×1.5, ×1.2 → 100 × (1 + 0.5 + 0.2) = 170
PERCENT +10%        → 170 × (1 + 0.1) = 187
ADD +20             → 187 + 20 = 207
```

**示例 2：保守语义防膨胀**
```
base = 100
MULT_POSITIVE ×1.5, ×1.3 → 100 × 1.5 = 150 (只取最大的1.5)
ADD_POSITIVE +50, +30    → 150 + 50 = 200 (只取最大的50)
```

**示例 3：混合使用**
```
base = 100
MULTIPLY ×1.2           → 100 × 1.2 = 120
MULT_POSITIVE ×1.5      → 120 × 1.5 = 180
MULT_NEGATIVE ×0.8      → 180 × 0.8 = 144
ADD +30                 → 144 + 30 = 174
ADD_NEGATIVE -20        → 174 - 20 = 154
```

> **设计说明**：
> - ADD 在乘法之后应用，可以有效抑制数值膨胀——加算是固定值，不会被乘法放大
> - 保守语义适用于需要严格控制膨胀的场景，如"暴击伤害加成上限"
> - 乘区相加让策划更容易预测和控制最终数值

### 3.3 注入机制（Injection）

MetaBuff **不直接参与计算**，而是在激活时将其包含的 PodBuff "注入"到 BuffManager：

```
MetaBuff 状态机:
  INACTIVE ──[激活]──► ACTIVE ──[失效]──► PENDING_DEACTIVATE ──► INACTIVE
                         │                        │
                    注入 PodBuff              弹出 PodBuff
```

#### P1-3: 注入容错与回滚

注入过程具有以下安全保障：

1. **跳过无效 Pod**：`createPodBuffsForInjection()` 返回数组中的 `null`、无 `isPod` 方法的对象、或 `isPod()` 返回 `false` 的元素会被静默跳过（使用鸭子类型检查避免抛异常），不会中断注入流程。

2. **异常回滚**：若注入过程中抛出异常，已注入的 Pod **引用会被移除**（从 `_buffs`、`_byInternalId`、`_injectedPodBuffs` 中清理）。

```actionscript
// 示例：即使 pods 数组包含无效元素，也能安全注入
var pods:Array = [
    new PodBuff("atk", BuffCalculationType.ADD, 10),
    null,  // 被跳过
    {foo: "bar"},  // 无 isPod 方法，被跳过
    new PodBuff("def", BuffCalculationType.ADD, 5)
];
// 只有 atk 和 def 两个有效 Pod 被注入
```

**回滚限制（非 ACID 事务）**：
- 回滚**不会** `destroy()` 已注入的 Pod（避免影响可能被其他地方引用的对象）
- 回滚**不会**撤销已触发的 `onBuffAdded` 回调（外部监听器可能短暂看到"加了但没移除事件"）
- 回滚**不会**撤销 `recordInjectedBuffId()` 调用（若 MetaBuff 实现了该方法）

这是"尽力回滚"策略，足以保证 BuffManager 内部数据一致性，但外部副作用无法完全撤销。

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
| `addBuff(buff:IBuff, buffId:String):String` | 添加 Buff，返回**注册 ID**。**⚠️ 必须保存返回值用于移除，禁止用 buff.getId()** |
| `addBuffImmediate(buff:IBuff, buffId:String):String` | 添加 Buff 并**立即应用效果**。适用于需要立即读取更新后属性值的场景（如播报数值） |
| `addBuffs(buffs:Array, ids:Array):Array` | **[v2.9]** 批量添加Buff，返回注册ID数组。buffs和ids数组一一对应 |
| `removeBuff(buffId:String):Boolean` | 延迟移除 Buff。**必须传入 addBuff 返回值，不要传 buff.getId()** |
| `removeBuffsByProperty(propertyName:String):Number` | **[v2.9]** 移除指定属性上的所有独立PodBuff，返回移除数量 |
| `getBaseValue(propertyName:String):Number` | **[v2.9]** 获取属性的base值（未经Buff计算的原始值） |
| `setBaseValue(propertyName:String, value:Number):Void` | **[v2.9]** 直接设置属性的base值，跳过Buff计算 |
| `addBaseValue(propertyName:String, delta:Number):Void` | **[v2.9]** 对base值进行增量操作，避免`+=`陷阱 |
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

#### TimeLimitComponent v1.1 新增接口

```actionscript
var timeLimit:TimeLimitComponent = new TimeLimitComponent(150);

// 暂停/恢复
timeLimit.pause();              // 暂停计时，update不消耗时间
timeLimit.resume();             // 恢复计时
timeLimit.isPaused();           // 检查是否暂停

// 时间操作
timeLimit.getRemaining();       // 获取剩余帧数
timeLimit.setRemaining(frames); // 设置剩余帧数
timeLimit.addTime(deltaFrames); // 增加/减少剩余时间（正数延长，负数缩短）
```

**使用场景**：
- 时停技能：暂停场上所有buff的计时
- 时间延长道具：通过 `addTime()` 延长buff持续时间
- UI显示：通过 `getRemaining()` 显示剩余时间

### 4.5 BuffCalculationType 常量

```actionscript
// ==================== 通用语义（叠加型） ====================
BuffCalculationType.ADD       // "add"           - 加法累加
BuffCalculationType.MULTIPLY  // "multiply"      - 乘区相加: base × (1 + Σ(m-1))
BuffCalculationType.PERCENT   // "percent"       - 乘区相加: result × (1 + Σp)

// ==================== 保守语义（独占型） ====================
BuffCalculationType.ADD_POSITIVE   // "add_positive"   - 正向加法取最大值
BuffCalculationType.ADD_NEGATIVE   // "add_negative"   - 负向加法取最小值
BuffCalculationType.MULT_POSITIVE  // "mult_positive"  - 正向乘法取最大值
BuffCalculationType.MULT_NEGATIVE  // "mult_negative"  - 负向乘法取最小值

// ==================== 边界控制 ====================
BuffCalculationType.OVERRIDE  // "override"      - 强制覆盖
BuffCalculationType.MAX       // "max"           - 下限保底
BuffCalculationType.MIN       // "min"           - 上限封顶
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

#### buffId vs buff.getId()（重要）

| 概念 | 来源 | 用途 | 可用于 removeBuff? |
|------|------|------|-------------------|
| `addBuff()` 返回值 | 系统分配 | **唯一正确的移除 ID** | ✅ 是 |
| `buffId` 参数 | 业务层指定 | 逻辑 ID | ✅ 是（与返回值相同） |
| `buff.getId()` | 内部自增 | 内部追踪 | ❌ **禁止** |

**⚠️ 关键陷阱**：`buff.getId()` 返回的是内部 ID（如 `"42"`），与 `addBuff()` 返回的外部 ID（如 `"auto_42"` 或用户指定的 ID）**不同**！

```actionscript
// ✅ 推荐：显式指定 ID
var regId:String = buffManager.addBuff(buff, "equip_weapon_atk");
// regId == "equip_weapon_atk"

// ✅ 正确移除
buffManager.removeBuff(regId);  // 使用 addBuff 返回值
buffManager.removeBuff("equip_weapon_atk");  // 或原始传入的 ID

// ❌ 错误：使用 buff.getId()
buffManager.removeBuff(buff.getId());  // 找不到！buff.getId() 是内部 ID
```

```actionscript
// ⚠️ 不推荐但可用：不传 ID
var regId:String = buffManager.addBuff(buff, null);
// regId == "auto_42"（自动前缀）

// ✅ 必须保存返回值用于移除
buffManager.removeBuff(regId);  // ✅ 正确
buffManager.removeBuff(buff.getId());  // ❌ 错误："42" != "auto_42"
```

#### ⚠️ 外部 ID 禁止使用纯数字（Phase D 契约）

**硬性规则**：用户显式传入的 `buffId` **禁止使用纯数字**（如 `"123"`、`"999"`），否则 `addBuff()` 返回 `null` 并拒绝添加。

**原因**：内部自增 ID（`BaseBuff.nextID`）生成纯数字字符串（如 `"42"`），存储在 `_byInternalId`。如果允许外部 ID 也使用纯数字，会导致命名空间碰撞风险。

```actionscript
// ❌ 错误：纯数字 ID 被拒绝
buffManager.addBuff(buff, "12345");  // 返回 null

// ✅ 正确：包含非数字字符
buffManager.addBuff(buff, "buff_12345");
buffManager.addBuff(buff, "equip_sword");
buffManager.addBuff(buff, "1a");  // 含字母，允许

// ✅ 正确：不传 ID，自动生成带前缀的 ID
buffManager.addBuff(buff, null);  // 返回 "auto_" + buff.getId()
buffManager.addBuff(buff);        // 同上
```

#### P1-1: 自动前缀机制

当 `buffId` 为 `null` 或未传时，系统**不再**直接使用纯数字的 `buff.getId()`，而是自动添加 `"auto_"` 前缀：

```actionscript
var buff:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
// buff.getId() == "42"（内部自增ID）

var regId:String = buffManager.addBuff(buff, null);
// regId == "auto_42"（带前缀的外部ID）

// 移除时必须使用返回的 regId
buffManager.removeBuff(regId);  // ✅ 正确
buffManager.removeBuff(buff.getId());  // ❌ 错误：找不到 "42"
```

**关键点**：
- `addBuff()` 返回值是实际注册的外部 ID，务必保存
- 内部 ID（`buff.getId()`）与外部 ID（`regId`）现在完全分离
- 这彻底杜绝了数字 ID 进入 `_byExternalId` 的风险

#### P1-2: 重复注册防护

同一个 Buff 实例**禁止重复注册**。系统使用 `__inManager` 标记追踪：

```actionscript
var buff:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
var id1:String = buffManager.addBuff(buff, "buff_a");  // ✅ 成功
var id2:String = buffManager.addBuff(buff, "buff_b");  // ❌ 返回 null

// 需要复用同一配置？创建新实例
var buff2:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
var id3:String = buffManager.addBuff(buff2, "buff_b");  // ✅ 成功
```

**原因**：重复注册会导致"幽灵 buff"——`_buffs` 数组中存在多个引用，但 `_byExternalId` 只记录最后一个，移除时无法完全清理。

**附加约束**：
- **buffId 参数类型**：必须传 `String` 或 `null`。虽然 AS2 会自动将 `Number` 转为字符串，但传入 `addBuff(buff, 12345)` 会被转为 `"12345"` 并被拒绝。
- **deactivate() 方法**：目前仅 `BaseBuff` 及其子类（`PodBuff`、`MetaBuff`）支持。若需对 `IBuff` 引用调用，使用鸭子类型：
  ```actionscript
  if (typeof buff["deactivate"] == "function") {
      buff["deactivate"]();
  }
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

MetaBuff 注入的 PodBuff 使用 `BaseBuff.nextID` 生成的递增数字 ID（如 `"42"`、`"43"`），**仅供内部使用**：
- ID 来自 `podBuff.getId()`，由 `BaseBuff` 构造时自动分配
- 存储在 `_byInternalId` 映射中，与用户注册的 `_byExternalId` 分离
- 不应在业务层引用这些数字 ID
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
```

### 6.5 ✅ base值操作API（v2.9新增，推荐）

**v2.9引入了显式的base值操作API**，从根本上解决属性接管的读写陷阱：

```actionscript
// ❌ 危险：使用 += 会污染base值
unit.attack += 30;  // 实际：base = (base + buff效果) + 30

// ✅ 安全：使用 addBaseValue()
buffManager.addBaseValue("attack", 30);  // 仅修改base，buff效果自动叠加

// ✅ 安全：使用 setBaseValue() 直接设置
buffManager.setBaseValue("attack", 100); // base = 100，最终值 = 100 + buff效果

// ✅ 安全：使用 getBaseValue() 获取原始值
var baseAttack:Number = buffManager.getBaseValue("attack"); // 返回未加成的base值
```

**API说明**：

| API | 用途 | 示例 |
|-----|------|------|
| `getBaseValue(prop)` | 获取未经Buff计算的原始值 | 显示"基础攻击力" |
| `setBaseValue(prop, value)` | 设置base值（不触发buff重算外的副作用） | 装备切换时重置base |
| `addBaseValue(prop, delta)` | base值增量操作，替代危险的 `+=` | 升级加点、消耗扣减 |

**⚠️ 重要**：如果属性尚未被托管（没有任何buff），这些API会使用当前属性值作为base值并开始托管。

#### 何时使用base值API vs Buff

| 场景 | 推荐方案 | 原因 |
|------|----------|------|
| 升级/加点的永久加成 | `addBaseValue()` | 这是真正的"基础成长" |
| 装备提供的属性加成 | `addBuff()` | 装备卸下时需要移除，用buff管理更方便 |
| 技能的临时增益 | `addBuff() + MetaBuff` | 有持续时间，需要生命周期管理 |
| 角色初始属性设置 | `setBaseValue()` | 设置初始base值 |
| 永久消耗（如技能消耗MP） | 不要用BuffManager | 消耗值不应被托管

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

| 旧系统 | 新系统 | 说明 |
|--------|--------|------|
| `base × 倍率 + 加算` | `base × (1+Σ(m-1)) × (1+Σp) + Σadd` | 乘区相加，防止膨胀 |
| 倍率连乘 | MULTIPLY 乘区相加 | `×1.5 × 1.2` → `×1.7` 而非 `×1.8` |
| 倍率/加算分开存储 | 统一计算链（10步） | 更灵活、可控 |
| 增益/减益取极值 | 保守语义类型实现 | MULT_POSITIVE/NEGATIVE, ADD_POSITIVE/NEGATIVE |

**映射关系**：
- 老系统 `倍率` → 新系统 `MULTIPLY`（乘区相加）
- 老系统 `加算` → 新系统 `ADD`（在乘法之后应用）
- 需要防止膨胀时 → 使用 `MULT_POSITIVE`/`ADD_POSITIVE` 等保守语义

**计算顺序**：
```
MULTIPLY → MULT_POSITIVE → MULT_NEGATIVE → PERCENT → ADD → ADD_POSITIVE → ADD_NEGATIVE → MAX → MIN → OVERRIDE
```

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
│  - _byExternalId: Object   用户注册 ID → Buff          │
│  - _byInternalId: Object   系统内部 ID → Buff          │
│  - _propertyContainers     属性 → 容器映射              │
│  - _metaBuffInjections     Meta → 注入的 Pod ID        │
│  - _injectedPodBuffs       Pod ID → 父 Meta ID         │
│  - _pendingRemovals        延迟移除队列                 │
│  - _pendingAddsA/B: Array  双缓冲延迟添加队列（v2.3）  │
│  - _inUpdate: Boolean      update() 执行标志           │
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
    ├─► 0. _inUpdate = true （设置重入保护标志）
    │
    ├─► 1. _processPendingRemovals()
    │       处理延迟移除队列
    │
    ├─► 2. _updateMetaBuffsWithInjection(deltaFrames)
    │       │
    │       ├─► 更新所有 MetaBuff（带 try/catch 异常隔离）
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
    ├─► 4. if (_isDirty)
    │       │
    │       ├─► _redistributeDirtyProps() 或 _redistributePodBuffs()
    │       │       重新分配 PodBuff 到对应 PropertyContainer
    │       │
    │       └─► PropertyContainer.forceRecalculate()
    │               触发数值重算
    │
    ├─► 5. _inUpdate = false （解除重入保护）
    │
    └─► 6. _flushPendingAdds()
            处理 update 期间收集的延迟添加请求
```

#### 重入保护机制（v2.3 双缓冲队列）

当 `_inUpdate = true` 时，调用 `addBuff()` 不会立即添加 Buff，而是将请求放入双缓冲队列：

```actionscript
// update() 执行期间的 addBuff 调用会被延迟
if (this._inUpdate) {
    this._pendingAdds.push({buff: buff, id: finalId});
    return finalId;  // 立即返回 ID，但 Buff 尚未生效
}
```

**v2.3 双缓冲队列设计**：

旧实现的问题：在 `_flushPendingAdds()` 处理队列期间，若回调触发新的 `addBuff()`，新增项可能被跳过。

新实现使用双缓冲队列解决：
```actionscript
// 双缓冲循环
while (A.length > 0 || B.length > 0) {
    if (A.length > 0) {
        处理 A 队列，新增写入 B 队列
    } else {
        处理 B 队列，新增写入 A 队列
    }
}
```

**设计意图**：
- 防止在迭代 `_buffs` 数组时修改数组导致索引错乱
- 确保单次 update 的状态一致性
- **重入安全**：回调中调用 `addBuff()` 不会丢失（写入另一缓冲区）
- 延迟添加的 Buff 在当前 update 结束后立即生效

**注意事项**：
- `addBuff()` 在 update 期间仍会返回 Buff ID
- 但该 Buff 在 `_flushPendingAdds()` 执行前不会参与计算
- 如果需要 Buff 立即生效，应在 update 完成后调用 `addBuff()`
- **契约**：见[附录 D.3](#d3-重入安全保证契约3)

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
            ├─► 通用乘法: base × (1 + Σ(multiply-1))     乘区相加
            ├─► 保守正向乘法: × multPositiveMax           取最大值
            ├─► 保守负向乘法: × multNegativeMin           取最小值
            ├─► 通用百分比: × (1 + Σpercent)             乘区相加
            ├─► 通用加法: + Σadd                         累加
            ├─► 保守正向加法: + addPositiveMax            取最大值
            ├─► 保守负向加法: + addNegativeMin            取最小值
            ├─► 下限: max(result, maxValue)
            ├─► 上限: min(result, minValue)
            └─► 强制覆盖: OVERRIDE（如有）
```

---

## 9. 测试与验证

### 9.1 运行测试

```actionscript
// 核心功能测试（63 个用例）
org.flashNight.arki.component.Buff.test.BuffManagerTest.runAllTests();

// Bugfix 回归测试（15 个用例，含 v2.3 重入安全 + 双缓冲测试）
org.flashNight.arki.component.Buff.test.BugfixRegressionTest.runAllTests();

// BuffCalculator 单元测试
org.flashNight.arki.component.Buff.test.BuffCalculatorTest.runAllTests();

// 组件测试（12 个用例，2 个已知失败）
org.flashNight.arki.component.Buff.test.Tier1ComponentTest.runAllTests();
```

### 9.2 测试覆盖状态

| 测试类别 | 通过/总数 | 状态 |
|----------|-----------|------|
| 基础计算 (ADD/MULTIPLY/PERCENT/OVERRIDE) | 5/5 | ✅ |
| 边界控制 (MAX/MIN) | 2/2 | ✅ |
| **保守语义** | **6/6** | ✅ |
| MetaBuff 注入 | 4/4 | ✅ |
| 限时组件 | 4/4 | ✅ |
| 复杂场景 | 4/4 | ✅ |
| PropertyContainer | 4/4 | ✅ |
| 边界情况 | 4/4 | ✅ |
| 性能测试 | 3/3 | ✅ |
| Sticky 容器 | 7/7 | ✅ |
| 回归测试 Phase 8 | 5/5 | ✅ |
| 回归测试 Phase 9 (0/A) | 6/6 | ✅ |
| 回归测试 Phase 10 (B) | 4/4 | ✅ |
| 回归测试 Phase 11 (D/P1) | 5/5 | ✅ |
| **回归测试 v2.3 (重入安全+双缓冲)** | **6/6** | ✅ |
| **核心功能总计** | **63/63** | ✅ |
| **Bugfix 回归测试总计** | **15/15** | ✅ |
| 组件集成测试 | 10/12 | ⚠️ |

**保守语义测试详情**（Phase 1.5）：
- `ADD_POSITIVE`: 正向保守加法取最大值
- `ADD_NEGATIVE`: 负向保守加法取最小值
- `MULT_POSITIVE`: 正向保守乘法取最大值
- `MULT_NEGATIVE`: 负向保守乘法取最小值
- `Conservative Mixed`: 通用+保守语义混合计算
- `Full Calculation Chain`: 完整10步计算链验证

**v2.3 重入安全测试详情**（BugfixRegressionTest）：
- `test_v23_ReentrantAddBuff_OnBuffAdded`: 回调中 addBuff 不丢失
- `test_v23_ReentrantAddBuff_ChainedCallbacks`: 链式回调 A→B→C 不丢失
- `test_v23_ReentrantAddBuff_MultipleWaves`: 多波重入 addBuff 不丢失
- `test_v23_DoubleBuffer_FlushPhaseReentry`: **双缓冲核心验证** - flush 阶段二次入队不丢失
- `test_v23_Contract_DelayedAddTiming`: 延迟添加时机契约验证
- `test_v23_Contract_OverrideTraversalOrder`: OVERRIDE 遍历顺序契约验证

### 9.3 已知失败的测试

| 测试 | 失败原因 | 影响 |
|------|----------|------|
| StackLimit with MetaBuff | `setValue()` 不触发重算 | 使用同 ID 替换规避 |
| Condition with MetaBuff | 组件语义不支持条件门控 | 业务层控制 add/remove |

### 9.4 性能基准

```
100 Buffs + 100 Updates = 59ms
平均每次 update: 0.59ms per update
单次大规模计算: 10ms (100 Buffs)
```

---

## 10. 常见问题

### Q1: 为什么我修改了 PodBuff 的值，属性没变化？

`PodBuff.setValue()` 不会触发重算。使用同 ID 替换：
```actionscript
buffManager.addBuff(new PodBuff(..., newValue), sameId);
```

### Q2: 为什么 `removeBuff(buff.getId())` 没有效果？

**这是最常见的错误**。`buff.getId()` 返回的是内部 ID，不是 `addBuff()` 的注册 ID：
```actionscript
// ❌ 错误用法
var buff:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
buffManager.addBuff(buff, null);  // 返回 "auto_42"
buffManager.removeBuff(buff.getId());  // 传入 "42"，找不到！

// ✅ 正确用法
var regId:String = buffManager.addBuff(buff, null);  // 保存返回值
buffManager.removeBuff(regId);  // 使用保存的 ID
```

详见 [5.0 节 buffId vs buff.getId()](#buffid-vs-buffgetid重要)。

### Q3: 如何实现"HP低于30%时+50%伤害"？

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

### Q4: 如何实现"倍率取最大值"（防止倍率膨胀）？

使用保守语义类型 `MULT_POSITIVE`，多个同类型 Buff 只取最大值：
```actionscript
// 多个倍率 Buff 只有最强的生效
addBuff(new PodBuff("attack", MULT_POSITIVE, 1.5), "buff1"); // ×1.5
addBuff(new PodBuff("attack", MULT_POSITIVE, 1.3), "buff2"); // ×1.3
// 结果：只取 ×1.5，而非 ×1.5 × 1.3

// 如果需要减益也只取最强
addBuff(new PodBuff("speed", MULT_NEGATIVE, 0.7), "slow1"); // ×0.7
addBuff(new PodBuff("speed", MULT_NEGATIVE, 0.8), "slow2"); // ×0.8
// 结果：只取 ×0.7（最小值=最强减速）
```

### Q5: 能否管理 `unit.长枪属性.power`？

不能直接管理。方案：
1. 创建代理属性 `unit._gunPower`
2. 在 `onPropertyChanged` 回调中同步到嵌套属性

### Q6: Buff 添加顺序会影响计算结果吗？

不会。计算顺序固定为 10 步，与添加顺序无关：
```
MULTIPLY → MULT_POSITIVE → MULT_NEGATIVE → PERCENT → ADD → ADD_POSITIVE → ADD_NEGATIVE → MAX → MIN → OVERRIDE
```

公式: `base × (1+Σ(m-1)) × multPosMax × multNegMin × (1+Σp) + Σadd + addPosMax + addNegMin`

其中 MULTIPLY 和 PERCENT 使用乘区相加（而非连乘），保守语义类型只取极值。

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

| 问题 | 影响 | 建议处理方式 | 状态 |
|------|------|--------------|------|
| `PodBuff.setValue()` 不触发重算 | 需要用同 ID 替换 | **业务层绕过**，或移除该方法避免误用 | 待处理 |
| 组件语义（Active vs Alive 未分离） | 不支持条件门控 | **已实现 `isLifeGate()` 门控协议** | ✅ Phase 0 |
| 回调参数顺序不一致 | 潜在 bug | 修复 BuffManagerInitializer | 待处理 |
| 注入 Pod ID 暴露给回调 | 回调噪音 | 可选：增加过滤参数 | 待处理 |
| 优先级字段未使用 | MetaBuff._priority 无效 | 未来实现或移除 | 待处理 |
| `_removeInactivePodBuffs` 使用 `buff.getId()` | 内部 ID 可能与用户注册 ID 冲突 | **已修复**：使用 `__regId` 获取注册 ID | ✅ Phase B |
| `_idMap` 混合存储内外部 ID | ID 命名空间污染 | **已废弃**：完全使用 `_byExternalId`/`_byInternalId` | ✅ Phase B |
| 外部 ID 与内部数字 ID 碰撞风险 | 命名空间冲突 | **已修复**：禁止纯数字外部 ID | ✅ Phase D |
| `PropertyContainer.removeBuff()` 默认销毁 | 误销毁 BuffManager 拥有的 buff | **已修复**：默认 `shouldDestroy=false` | ✅ Phase D |
| `BaseBuff` 缺少 `deactivate()` | 无法手动停用 PodBuff | **已添加**：`_active` 字段和 `deactivate()` 方法 | ✅ Phase D |
| buffId 为 null 时数字 ID 进入外部映射 | 破坏"禁止数字 externalId"约定 | **已修复**：自动添加 `auto_` 前缀 | ✅ P1-1 |
| 同一 Buff 实例可重复注册 | 产生"幽灵 buff"（无法通过 ID 移除） | **已修复**：`__inManager` 标记防重复 | ✅ P1-2 |
| 注入过程非事务化 | 异常时可能半注入 | **已修复**：鸭子类型跳过无效 pod，异常时尽力回滚（非 ACID） | ✅ P1-3 |
| `_flushPendingAdds` 重入期间丢失 buff | 回调中 addBuff 可能被跳过 | **已修复**：双缓冲队列方案 | ✅ v2.3 |
| `_removeInactivePodBuffs` 重复扫描 | O(n²) 性能问题 | **已修复**：`_removePodBuffCore` 消除重复扫描 | ✅ v2.3 |
| BuffCalculator 调试数组生产开销 | 无条件分配内存 | **已修复**：人肉注释启用，生产环境零开销 | ✅ v2.3 |

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
| 回调中添加 buff | v2.3 已支持重入安全，可放心使用 |

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

🧪 Test 2: Basic MULTIPLY Calculation (Additive Zones)
  ✓ MULTIPLY (additive zones): 50 * (1 + 0.5 + 0.2) = 85
  ✅ PASSED

🧪 Test 3: Basic PERCENT Calculation (Additive Zones)
  ✓ PERCENT (additive zones): 100 * (1 + 0.2 + 0.1) = 130
  ✅ PASSED

🧪 Test 4: Calculation Types Priority (Additive Zones)
  ✓ Priority: 100 * 1.5 * 1.1 + 20 = 185
  ✅ PASSED

🧪 Test 5: OVERRIDE Calculation
  ✓ OVERRIDE: All calculations → 100
  ✅ PASSED

🧪 Test 6: Basic MAX Calculation
  ✓ MAX: max(50, 80, 60) = 80
  ✅ PASSED

🧪 Test 7: Basic MIN Calculation
  ✓ MIN: min(200, 150, 180) = 150
  ✅ PASSED


--- Phase 1.5: Conservative Semantics Tests ---
🧪 Test 8: ADD_POSITIVE Calculation (Conservative)
  ✓ ADD_POSITIVE: 100 + max(50,80,30) = 180
  ✅ PASSED

🧪 Test 9: ADD_NEGATIVE Calculation (Conservative)
  ✓ ADD_NEGATIVE: 100 + min(-20,-50,-30) = 50
  ✅ PASSED

🧪 Test 10: MULT_POSITIVE Calculation (Conservative)
  ✓ MULT_POSITIVE: 100 * max(1.3,1.8,1.5) = 180
  ✅ PASSED

🧪 Test 11: MULT_NEGATIVE Calculation (Conservative)
  ✓ MULT_NEGATIVE: 100 * min(0.9,0.5,0.7) = 50
  ✅ PASSED

🧪 Test 12: Conservative Mixed Calculation
  ✓ Mixed: 100*1.3*1.5*0.8+30+50 = 236
  ✅ PASSED

🧪 Test 13: Full Calculation Chain (All 10 Types)
  ✓ Full Chain: 100→170→204→183.6→201.96→251.96→281.96→261.96 = 261.96
  ✅ PASSED


--- Phase 2: MetaBuff Injection & Calculation ---
🧪 Test 14: MetaBuff Pod Injection
  ✓ MetaBuff injection: 50 * 1.2 + 25 = 85
  ✅ PASSED

🧪 Test 15: MetaBuff Calculation Accuracy
  ✓ Damage: 100 * 1.3 + 50 = 180
  ✓ Critical: 1.5 + 0.5 = 2
  ✅ PASSED

🧪 Test 16: MetaBuff State Transitions & Calculations
  ✓ State transitions: 60 → 60 → 20 → 20 (expired)
  ✅ PASSED

🧪 Test 17: MetaBuff Dynamic Injection
  ✓ Dynamic injection: 120 → 185
  ✅ PASSED


--- Phase 3: TimeLimitComponent & Dynamic Calculations ---
🧪 Test 18: Time-Limited Buff Calculations
  ✓ Time-limited calculations: 170 → 120 → 100
  ✅ PASSED

🧪 Test 19: Dynamic Calculation Updates
  ✓ Dynamic updates: 400 → 300 → 200
  ✅ PASSED

🧪 Test 20: Buff Expiration Calculations
  ✓ Cascading expiration: 110 → 100 → 80 → 50
  ✅ PASSED

🧪 Test 21: Cascading Buff Calculations
  ✓ Cascading calculations: 310 → 180 → 150
  ✅ PASSED


--- Phase 4: Complex Calculation Scenarios ---
🧪 Test 22: Stacking Buff Calculations
  ✓ Stacking: 5 stacks (150) → 3 stacks (130)
  ✅ PASSED

🧪 Test 23: Multi-Property Calculations
  ✓ Multi-property: Phys 120, Mag 104, Heal 75
  ✅ PASSED

🧪 Test 24: Calculation Order Dependency
  ✓ Order dependency: 100 → 120 → 180 → 200 → 200 → 200
  ✅ PASSED

🧪 Test 25: Real Game Calculation Scenario
  ✓ Combat stats: AD 180, AS 1.5, CC 30%, CD 200%
  ✓ DPS increase: 219%
  ✅ PASSED


--- Phase 5: PropertyContainer Integration ---
🧪 Test 26: PropertyContainer Calculations
  ✓ PropertyContainer: 200 * 1.5 + 100 = 400
  ✓ Callbacks fired: 25 times
  ✅ PASSED

🧪 Test 27: Dynamic Property Recalculation
  ✓ Dynamic recalc: 75 → 125 → 100
  ✅ PASSED

🧪 Test 28: PropertyContainer Rebuild Accuracy
  ✓ Container rebuild: accurate calculations maintained
  ✅ PASSED

🧪 Test 29: Concurrent Property Updates
  ✓ Concurrent updates handled correctly
  ✅ PASSED


--- Phase 6: Edge Cases & Accuracy ---
🧪 Test 30: Extreme Value Calculations
  ✓ Extreme values: 1M and 0.000001 handled correctly
  ✅ PASSED

🧪 Test 31: Floating Point Accuracy (Additive Zones)
  ✓ Floating point (additive zones): 10 * (1 + 0.1 * 3) = 13 (±0.01)
  ✅ PASSED

🧪 Test 32: Negative Value Calculations
  ✓ Negative values: 100 → 20 → -30
  ✅ PASSED

🧪 Test 33: Zero Value Handling
  ✓ Zero handling: 0+50=50, 100*0=0
  ✅ PASSED


--- Phase 7: Performance & Accuracy at Scale ---
🧪 Test 34: Large Scale Calculation Accuracy
  ✓ 100 buffs: sum = 6050 (accurate)
  ✅ PASSED

🧪 Test 35: Calculation Performance
  ✓ Performance: 100 buffs, 100 updates in 57ms
  ✅ PASSED

🧪 Test 36: Memory and Calculation Consistency
  ✓ Consistency maintained across 10 rounds
  ✅ PASSED


--- Phase: Sticky Container & Lifecycle Contracts ---
🧪 Test 37: Sticky container: meta jitter won't delete property
  ✅ PASSED

🧪 Test 38: unmanageProperty(finalize) then rebind uses plain value as base (independent Pods are cleaned)
  ✅ PASSED

🧪 Test 39: destroy() finalizes all managed properties
  ✅ PASSED

🧪 Test 40: Base value: zero vs undefined
  ✅ PASSED

🧪 Test 41: Calculation order independent of add sequence
  ✅ PASSED

🧪 Test 42: clearAllBuffs keeps properties and resets to base
  ✅ PASSED

🧪 Test 43: MetaBuff jitter stability (no undefined during flips)
  ✅ PASSED

--- Phase 8: Regression & Lifecycle Contracts ---
🧪 Test 44: Same-ID replacement keeps only the new instance
[BuffManager] 警告：PodBuff属性名无效: undefined
[BuffManager] 警告：PodBuff属性名无效: undefined
  ✅ PASSED

🧪 Test 45: Injected Pods fire onBuffAdded for each injected pod
  ✅ PASSED

🧪 Test 46: Remove injected pod shrinks injected map by 1
  ✅ PASSED

🧪 Test 47: clearAllBuffs emits onBuffRemoved for independent pods
[BuffManager] 警告：PodBuff属性名无效: undefined
[BuffManager] 警告：PodBuff属性名无效: undefined
  ✅ PASSED

🧪 Test 48: removeBuff de-dup removes only once
[BuffManager] 警告：PodBuff属性名无效: undefined
  ✅ PASSED


--- Phase 9: Phase 0/A Regression Tests ---
🧪 Test 49: TimeLimitComponent + CooldownComponent AND semantics
  ✓ AND semantics: TimeLimitComponent failure terminates MetaBuff despite CooldownComponent alive
  ✅ PASSED

🧪 Test 50: Pending removal cancelled on same-ID re-add (P0-4)
  ✓ P0-4: Pending removal correctly cancelled on same-ID re-add
  ✅ PASSED

🧪 Test 51: Destroyed MetaBuff rejected on re-add (P0-6)
[BuffManager] 警告：尝试添加已销毁的MetaBuff，已拒绝
  ✓ P0-6: Destroyed MetaBuff correctly rejected on re-add
  ✅ PASSED

🧪 Test 52: Invalid property name rejected (P0-8)
[BuffManager] 警告：PodBuff属性名无效: 
[BuffManager] 警告：PodBuff属性名无效: null
  ✓ P0-8: Invalid property names correctly rejected
  ✅ PASSED

🧪 Test 53: setBaseValue NaN guard (P1-6)
[PropertyContainer] 警告：setBaseValue收到NaN，已忽略
  ✓ P1-6: NaN correctly rejected by setBaseValue
  ✅ PASSED

🧪 Test 54: Update reentry protection (P1-3)
  ✓ P1-3: Update reentry protection in place
  ✅ PASSED


--- Phase 10: Phase B Regression Tests (ID Namespace) ---
🧪 Test 55: ID Namespace Separation (_byExternalId/_byInternalId)
  ✓ Phase B: ID namespace correctly separated
  ✅ PASSED

🧪 Test 56: _removeInactivePodBuffs uses __regId (via deactivate)
  ✓ Phase B: _removeInactivePodBuffs correctly uses __regId for removal
  ✅ PASSED

🧪 Test 57: _lookupById fallback (external -> internal)
  ✓ Phase B: _lookupById fallback works correctly
  ✅ PASSED

🧪 Test 58: Prefix query only searches _byExternalId
  ✓ Phase B: Prefix queries only search external IDs
  ✅ PASSED


--- Phase 11: Phase D Contract Tests (ID Validation) ---
🧪 Test 59: Pure-numeric external ID rejection
[BuffManager] 错误：外部ID禁止使用纯数字（与内部ID命名空间冲突风险），已拒绝: 12345
  ✓ Phase D: Pure-numeric external ID correctly rejected
  ✅ PASSED

🧪 Test 60: Valid external ID accepted
  ✓ Phase D: Valid external IDs correctly accepted
  ✅ PASSED

🧪 Test 61: [P1-1] Auto-prefix when buffId is null
  ✓ P1-1: Auto-prefix 'auto_' correctly applied when buffId is null
  ✅ PASSED

🧪 Test 62: [P1-2] Duplicate instance registration rejection
[BuffManager] 警告：同一Buff实例已在管理中，拒绝重复注册。旧ID: buff_a, 新ID: buff_b
  ✓ P1-2: Duplicate instance registration correctly rejected
  ✅ PASSED

🧪 Test 63: [P1-3] Injection skips null pods gracefully
[BuffManager] 警告：跳过无效的注入Pod（null或非PodBuff）
[BuffManager] 警告：跳过无效的注入Pod（null或非PodBuff）
  ✓ P1-3: Injection handles null pods gracefully (skips them)
  ✅ PASSED


--- Phase 12: Bugfix Regression Tests (2026-01) ---
=== Bugfix Regression Test Suite ===
Testing fixes from 2026-01 review

--- P0 Critical Fixes ---

[Test 1] P0-1: unmanageProperty should not recreate container next frame
  PASSED

[Test 2] P0-1: unmanageProperty blacklist prevents container creation
  Final defense value after re-adding buff: 175
  PASSED

[Test 3] P0-1: Re-adding buff after unmanage should work
  Final speed value: 25
  PASSED

[Test 4] P0-2: MetaBuff with faulty component should be handled gracefully
  Active buffs after first update: 2
    Faulty MetaBuff removed via callback
  Active buffs after expiry: 1
  Final HP value: 150
  PASSED

[Test 5] P0-3: Invalid property names (empty/null/undefined) should be rejected gracefully
  Valid buff added with ID: valid
[BuffManager] 警告：PodBuff属性名无效: 
  Empty property buff result: accepted with ID empty_prop
[BuffManager] 警告：PodBuff属性名无效: null
  Null property buff result: accepted with ID null_prop
[BuffManager] 警告：PodBuff属性名无效: undefined
  Undefined property buff result: accepted with ID undef_prop
  Final validProp value: 110
  PASSED

--- v2.3 Critical: Reentry Safety ---

[Test 6] v2.3: Reentrant addBuff in onBuffAdded should not be lost
  Final damage value: 175
  Reentrant buff added: true
  PASSED

[Test 7] v2.3: Chained callbacks (A->B->C) should not lose any buff
  Added buffs: buff_A -> buff_B -> buff_C
  Final power: 30
  PASSED

[Test 8] v2.3: Multiple waves of reentrant addBuff
  Waves triggered: 3
  Final count: 5
  PASSED

[Test 9] v2.3: Double-buffer flush phase reentry (真正的 pending 队列测试)
  Step 1: Added trigger_buff
    [onPropertyChanged] Added pending_first during update (should go to pending queue)
    [onBuffAdded] Added pending_second during flush (should go to buffer B)
  Step 2: First update, score = 0, phase = 2
  Step 3: Second update, score = 110
  Final score: 110
  pendingFirstAdded: true
  pendingSecondAdded: true
  final phase: 2
  PASSED

--- v2.3 Contract Verification ---

[Test 10] v2.3 Contract: Delayed add timing (buff added during update takes effect end of update)
  Value before update: 100
  Value after update: 150
  Values during callbacks: 1 records
  PASSED

[Test 11] v2.3 Contract: OVERRIDE traversal order (earliest added wins)
  Final stat with two OVERRIDEs (500 first, 999 second): 500
  PASSED

--- P1 Important Fixes ---

[Test 12] P1-1: _flushPendingAdds performance with index traversal
  Added 100 buffs in 14ms
  Final power value: 100
  PASSED

[Test 13] P1-2: Callbacks during update should not cause reentry issues
  Callback count: 1
  Final callback count: 2
  PASSED

[Test 14] P1-3: changeCallback should only trigger on value change
    Callback triggered: testProp = 100
  After first access: callbackCount = 1
  After repeated access: callbackCount = 1
    Callback triggered: testProp = 150
  After adding buff: callbackCount = 2, value = 150
  PASSED

--- P2 Optimizations ---

[Test 15] P2-2: Boundary controls (MAX/MIN/OVERRIDE) should work even at limit
  Final damage with 250 ADD buffs + MAX(200) + MIN(500): 350
  PASSED

--- v2.4 Fixes ---

[Test 16] v2.4: MetaBuff.removeInjectedBuffId should sync injected list
  Initial injected count: 2
  manager.removeBuff('1543'): true
  After remove, injected count: 1
  PASSED

[Test 17] v2.4: Component no-throw contract verification
  Stat after 5 updates: 150
  Stat after expiry: 100
  PASSED

[Test 18] v2.4: PodBuff.applyEffect contract (no redundant check)
  atk value: 180 (expected 180)
  def value: 100 (expected 100)
  atk container buff count: 2
  def container buff count: 1
  PASSED

--- v2.6 Fixes ---

[Test 19] v2.6: Injected PodBuff should have __inManager and __regId flags
  Injected IDs: 2
    Pod[0] id=1554, __inManager=true, __regId=1554
    Pod[1] id=1555, __inManager=true, __regId=1555
  After removing first injected pod, hp=100
  PASSED

[Test 20] v2.6: PodBuff.getType() should return 'PodBuff'
  PodBuff.getType() = 'PodBuff'
  MetaBuff.getType() = 'MetaBuff'
  PASSED

[Test 21] v2.6: MetaBuff gate component expiry should terminate MetaBuff
  Frame 1: stat = 150, metaBuff active = true
  Frame 2: stat = 100, metaBuff active = true
  Frame 3: stat = 100, metaBuff active = false
  After expiry: activeBuffCount = 0, stat = 100
  PASSED

[Test 22] v2.6: _removePodBuffCore O(1) lookup correctness
  After adding 20 MetaBuffs with 5 pods each
  Total injected pods: 100
  Power value: 100
  After removing 10 MetaBuffs:
  Power value: 50 (expected: 50)
  Time elapsed: 6ms (for reference only, no hard assertion)
  PASSED

--- v2.9 New APIs & Fixes ---

[Test 23] v2.9: getBaseValue/setBaseValue should work correctly
  Final value: 150, Base value: 100
  After setBaseValue(200): Final=250, Base=200
  PASSED

[Test 24] v2.9: addBaseValue should avoid += trap
  Initial: Final=150, Base=100
  After addBaseValue(30): Final=180, Base=130
  [INFO] If using 'target.damage += 30' instead:
         Would read 150 (final), add 30 = 180, write to base
         Result: base=180, final=230 (WRONG!)
  [INFO] addBaseValue correctly modifies only the base value
  PASSED

[Test 25] v2.9: addBuffs batch operation should work
  Returned IDs: batch_atk, batch_def, batch_spd
  Values: atk=120, def=60, spd=20
  PASSED

[Test 26] v2.9: removeBuffsByProperty should remove all buffs on property
  Value with 3 buffs: 180
  Removed count: 3
  Value after removeBuffsByProperty: 100
  PASSED

[Test 27] v2.9: MetaBuff PENDING_DEACTIVATE should skip component updates
    [TrackingComponent] update called, count=1
  After frame 1: componentUpdateCount=1, stat=150
    [TrackingComponent] update called, count=2
  After frame 2: componentUpdateCount=2, stat=100
  After frame 3 (PENDING_DEACTIVATE): componentUpdateCount=2, stat=100
  After frame 4: componentUpdateCount=2, stat=100
  Component update counts: frame1=1, frame2=2, frame3=2, frame4=2
  PASSED

[Test 28] v2.9: TimeLimitComponent pause/resume should work
  Frame 1: remaining=4, value=150
  After 3 paused updates: remaining=4, value=150
  After resume + 1 update: remaining=3
  PASSED

[Test 29] v2.9: TimeLimitComponent time operations (getRemaining/setRemaining/addTime)
  All time operations work correctly
  PASSED

[Test 30] v2.9: StateInfo.instance should be statically initialized
  StateInfo.instance is correctly initialized statically
  PASSED

=== Bugfix Regression Test Results ===
Total: 30
Passed: 30
Failed: 0
Success Rate: 100%

All bugfix regression tests passed!
======================================

--- Phase 13: addBuffImmediate API Tests ---
🧪 Test 64: addBuffImmediate basic functionality
  ✓ addBuffImmediate: Basic add successful
  ✅ PASSED

🧪 Test 65: addBuffImmediate value immediately readable
  ✓ addBuffImmediate: Value immediately readable (100 + 50 = 150)
  ✅ PASSED

🧪 Test 66: addBuffImmediate safety during update
  ✓ addBuffImmediate: Safe during update (delayed add works)
  ✅ PASSED

🧪 Test 67: addBuffImmediate handles invalid buff
  ✓ addBuffImmediate: Handles null buff correctly
  ✅ PASSED


=== Calculation Accuracy Test Results ===
📊 Total tests: 67
✅ Passed: 67
❌ Failed: 0
📈 Success rate: 100%
🎉 All calculation tests passed! BuffManager calculations are accurate.
==============================================

=== Calculation Performance Results ===
📊 Large Scale Accuracy:
   buffCount: 100
   calculationTime: 10ms
   expectedValue: 6050
   actualValue: 6050
   accurate: true

📊 Calculation Performance:
   totalBuffs: 100
   properties: 5
   updates: 100
   totalTime: 57ms
   avgUpdateTime: 0.57ms per update

=======================================


```

---

## 附录 D: 设计契约

本节记录 BuffManager 系统的核心设计契约，这些契约是系统行为的**不变式**，任何修改都应保持这些契约不变。

### D.1 延迟添加生效时机（契约1）

```
在 update() 期间调用 addBuff/removeBuff，效果从本次 update() 结束时生效
```

**时序**：
```
update() 开始
  ├─► 处理延迟移除
  ├─► 更新 MetaBuff（注入/弹出）
  ├─► 移除失效 PodBuff
  ├─► 重算脏属性
  ├─► flush 延迟添加  ← 回调期间新增的 buff 在此处理
  └─► _inUpdate 复位
update() 结束
```

**影响**：
- 新增的 buff 在本帧末尾被添加，但**不参与本帧的属性重算**
- 若需"同帧立即生效"，应在 `update()` 外部调用 `addBuff()`

### D.2 OVERRIDE 冲突决策（契约2）

```
多个 OVERRIDE 并存时，添加顺序最早的 OVERRIDE 生效
```

**原因**：
- `PropertyContainer._computeFinalValue()` 使用 `while(i--)` **逆序遍历** buff 列表
- 即：后添加的 buff 先 `apply`，先添加的 buff 后 `apply`
- `BuffCalculator` 的 OVERRIDE 采用"最后写入 wins"语义
- 组合效果：先添加的 OVERRIDE 最后写入，因此先添加的生效

**示例**：
```actionscript
buffManager.addBuff(OVERRIDE_500_buff, "first");   // 先添加
buffManager.addBuff(OVERRIDE_999_buff, "second");  // 后添加
// 最终值 = 500（因为 first 最后 apply）
```

**若需"新覆盖旧"语义**：
- 使用同 ID 替换机制（`addBuff` 同 ID 会先移除旧 buff）
- 或确保同时只存在一个 OVERRIDE buff

### D.3 重入安全保证（契约3）

```
在任何回调中调用 addBuff() 是安全的，使用双缓冲队列保证不丢失
```

**v2.3 修复**：
- 旧实现在 `_flushPendingAdds` 期间，回调触发的 `addBuff` 直接写入正在处理的数组，导致新增 buff 被跳过
- 新实现使用双缓冲队列（A/B）：处理 A 时新增写入 B，反之亦然，交替处理直到两队列都空

**实现**：
```actionscript
// 双缓冲循环
while (A.length > 0 || B.length > 0) {
    if (A.length > 0) {
        处理 A，新增写入 B
    } else {
        处理 B，新增写入 A
    }
}
```

**测试覆盖**：
- `test_v23_ReentrantAddBuff_OnBuffAdded`
- `test_v23_ReentrantAddBuff_ChainedCallbacks`
- `test_v23_ReentrantAddBuff_MultipleWaves`

### D.4 ID 命名空间（契约4）

```
外部 ID 禁止纯数字，内部 ID 仅用于注入 PodBuff
```

| 映射 | 存储内容 | ID 格式 | 来源 |
|------|----------|---------|------|
| `_byExternalId` | 独立 Pod + MetaBuff | 用户指定或 `auto_` 前缀 | `addBuff(buff, id)` |
| `_byInternalId` | 注入的 PodBuff | 纯数字（自增） | `BaseBuff.nextID` |

**规则**：
- 用户显式传入的 `buffId` 若为纯数字，`addBuff()` 返回 `null` 并拒绝
- `buffId` 为 `null` 时，自动生成 `"auto_" + buff.getId()` 作为外部 ID
- 注入 Pod 的 ID 来自 `podBuff.getId()`，是纯数字，仅存入 `_byInternalId`

### D.5 MAX/MIN 语义（BuffCalculator 契约）

```
MAX: 取所有值中的最大值作为下限保底
MIN: 取所有值中的最小值作为上限封顶
```

**应用顺序**：
```
... → MAX（下限）→ MIN（上限）→ OVERRIDE
```

**示例**：
```actionscript
// 计算结果为 80，有 MAX(100) 和 MIN(150)
result = 80
result = max(80, 100) = 100  // MAX 保底
result = min(100, 150) = 100 // MIN 不变
// 最终 = 100
```

### D.6 组件不得 throw 异常（契约5，v2.4 新增）

```
IBuffComponent 的 update() / onAttach() / onDetach() / isLifeGate() 不得 throw 异常
```

**背景**：
- AS2 中显式 `throw` 极少使用，大多数错误表现为 `undefined` 返回值
- 原 `MetaBuff._updateComponents()` 中的 `try/catch` 对性能有开销
- 按契约化设计原则，移除 `try/catch`，由组件实现保证不抛异常

**影响**：
- 组件实现需自行处理内部错误，不得向外抛出
- 如果组件逻辑可能出错，应在内部捕获并返回 `false`（表示失败）
- 移除 `try/catch` 后，热路径性能提升

**测试覆盖**：
- `test_v24_Component_NoThrowContract`

### D.7 PodBuff.applyEffect 属性匹配由调用方保证（契约6，v2.4 新增）

```
PropertyContainer.addBuff() 已验证属性匹配，PodBuff.applyEffect() 无需重复检查
```

**背景**：
- `PropertyContainer.addBuff()` 在添加 buff 时已验证 `podBuff.getTargetProperty() == this._propertyName`
- 原 `PodBuff.applyEffect()` 中的属性检查 `if (this._targetProperty == context.propertyName)` 是冗余的
- 移除后减少每次计算的字符串比较开销

**影响**：
- 通过 `BuffManager` 正常添加的 PodBuff 无影响
- **禁止**绕过 `PropertyContainer.addBuff()` 直接将 PodBuff 放入容器

**测试覆盖**：
- `test_v24_PodBuff_applyEffect_Contract`

---

## 附录 E: v2.3 变更日志

### E.1 重入安全修复（P0-CRITICAL）

**问题**：`_flushPendingAdds` 在处理延迟添加队列时，若回调触发新的 `addBuff()`，新增 buff 会被跳过。

**场景**：
```actionscript
callbacks.onBuffAdded = function(id, buff) {
    // 这里的 addBuff 可能丢失
    manager.addBuff(anotherBuff, "triggered");
};
```

**解决方案**：双缓冲队列
- `_pendingAddsA` 和 `_pendingAddsB` 交替使用
- 处理 A 时新增写入 B，处理完 A 再处理 B，循环直到两队列都空

### E.2 性能优化（PERF）

**问题**：`_removeInactivePodBuffs` 在移除每个 PodBuff 时都调用 `_removePodBuff`，而 `_removePodBuff` 内部再次线性扫描 `_buffs` 数组，导致 O(n²) 复杂度。

**解决方案**：
- 新增 `_removePodBuffCore(buff, regId)` 方法，直接操作传入的 buff 引用，无需重复扫描
- `_removeInactivePodBuffs` 遍历时已持有 buff 引用，直接传递给核心方法

### E.3 调试数组优化（BuffCalculator）

**问题**：`BuffCalculator` 的 `_types` 和 `_values` 数组用于调试，但生产环境有额外开销。

**解决方案**：
- AS2 无条件编译能力，采用"人肉注释"方式
- 生产环境注释掉相关代码，需要调试时手动取消注释
- 相关代码标记为 `[v2.3]` 注释块

### E.4 测试新增

| 测试名称 | 验证内容 |
|----------|----------|
| `test_v23_ReentrantAddBuff_OnBuffAdded` | 回调中 addBuff 不丢失 |
| `test_v23_ReentrantAddBuff_ChainedCallbacks` | 链式回调 A→B→C 不丢失 |
| `test_v23_ReentrantAddBuff_MultipleWaves` | 多波重入不丢失 |
| `test_v23_DoubleBuffer_FlushPhaseReentry` | **双缓冲核心** - flush 阶段二次入队 |
| `test_v23_Contract_DelayedAddTiming` | 延迟添加时机契约 |
| `test_v23_Contract_OverrideTraversalOrder` | OVERRIDE 遍历顺序契约 |

### E.5 内联文档补充（DOC）

强化 `buff.getId()` 与 `addBuff()` 返回值的区分说明，避免使用方常见陷阱：

| 文件 | 更新内容 |
|------|----------|
| `BuffManager.as` | `addBuff()` 添加警告注释，说明返回值用途 |
| `BuffManager.as` | `removeBuff()` 添加参数说明，强调必须使用 addBuff 返回值 |
| `BuffManager.as` | `getBuffById()` 添加提示 |
| `BaseBuff.as` | `getId()` 添加禁止用于 removeBuff 的警告 |
| `IBuff.as` | `getId()` 接口文档添加同样警告 |

---

## 附录 F: v2.4 变更日志

### F.1 导入路径大小写修复（FIX）

**问题**：`BuffManager.as` 第 53 行导入路径使用小写 `component`，但实际目录是大写 `Component`。

**影响**：
- Windows 下大小写不敏感，不影响编译
- Linux/Mac 等大小写敏感系统上会编译失败

**解决方案**：
```diff
- import org.flashNight.arki.component.Buff.component.*;
+ import org.flashNight.arki.component.Buff.Component.*;
```

### F.2 MetaBuff.removeInjectedBuffId 方法新增（FIX）

**问题**：当注入的 PodBuff 被独立移除（如通过 `deactivate()` 失活后被清理），`MetaBuff._injectedBuffIds` 列表不会同步更新。

**原因**：
- `BuffManager._removePodBuffCore()` 尝试调用 `metaRef.removeInjectedBuffId(podId)`
- 但 `MetaBuff` 只有 `clearInjectedBuffIds()` 和 `getInjectedBuffIds()`，缺少单个移除方法

**解决方案**：
在 `MetaBuff.as` 中添加：
```actionscript
public function removeInjectedBuffId(buffId:String):Boolean {
    if (this._injectedBuffIds == null) return false;
    for (var i:Number = this._injectedBuffIds.length - 1; i >= 0; i--) {
        if (this._injectedBuffIds[i] == buffId) {
            this._injectedBuffIds.splice(i, 1);
            return true;
        }
    }
    return false;
}
```

**测试覆盖**：
- `test_v24_MetaBuff_removeInjectedBuffId`

### F.3 MetaBuff 移除 try/catch（PERF）

**问题**：`MetaBuff._updateComponents()` 和 `destroy()` 中对每个组件调用都包裹 `try/catch`，在热路径上有性能开销。

**背景**：
- AS2 中显式 `throw` 极少使用
- 现有组件（`TimeLimitComponent`、`CooldownComponent` 等）均不会 throw

**解决方案**：
- 移除 `_updateComponents()` 中 3 处 `try/catch`
- 移除 `destroy()` 中 1 处 `try/catch`
- 添加契约文档说明组件不得 throw

**测试覆盖**：
- `test_v24_Component_NoThrowContract`

### F.4 PodBuff.applyEffect 移除冗余检查（PERF）

**问题**：`PodBuff.applyEffect()` 中检查 `this._targetProperty == context.propertyName` 是冗余的。

**原因**：
- `PropertyContainer.addBuff()` 已在添加时验证属性匹配
- 该检查在每次属性重算时执行，累积开销可观

**解决方案**：
```diff
  public function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void {
-     if (this._targetProperty == context.propertyName) {
-         calculator.addModification(this._calculationType, this._value);
-     }
+     calculator.addModification(this._calculationType, this._value);
  }
```

**测试覆盖**：
- `test_v24_PodBuff_applyEffect_Contract`

### F.5 测试新增

| 测试名称 | 验证内容 |
|----------|----------|
| `test_v24_MetaBuff_removeInjectedBuffId` | 注入列表单个移除方法 |
| `test_v24_Component_NoThrowContract` | 组件契约化（无 try/catch） |
| `test_v24_PodBuff_applyEffect_Contract` | applyEffect 契约化（无冗余检查） |
