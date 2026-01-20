# BuffManager 使用与设计说明

> **文档版本**: 2.9
> **最后更新**: 2026-01-20
> **运行环境**: ActionScript 2.0 / Flash Player 32
> **状态**: 核心引擎稳定可用

本文档描述 `BuffManager.as` 的对外契约、运行阶段、以及与 `PropertyContainer` / `MetaBuff` 的协作方式。
目标：让使用者能"按契约正确使用"，让维护者能"快速定位修改点"。

---

## 目录

1. [系统概览](#1-系统概览)
2. [关键概念与名词](#2-关键概念与名词)
3. [构造与回调](#3-构造与回调)
4. [对外 API](#4-对外-api)
5. [update() 内部阶段](#5-update-内部阶段)
6. [属性接管规则](#6-属性接管规则重要)
7. [MetaBuff 注入/弹出机制](#7-metabuff-注入弹出机制)
8. [组件接口](#8-组件接口)
9. [可重入与事件驱动](#9-可重入与事件驱动)
10. [性能建议](#10-性能建议)
11. [常见用法示例](#11-常见用法示例)
12. [调试](#12-调试)
13. [生产落地检查清单](#13-生产落地检查清单)
14. [测试与验证](#14-测试与验证)
15. [附录 A: 设计契约](#附录-a-设计契约)
16. [附录 B: 版本变更日志](#附录-b-版本变更日志)
17. [附录 C: 文件清单与版本](#附录-c-文件清单与版本)
18. [附录 D: 测试结果存档](#附录-d-测试结果存档)

---

## 1. 系统概览

BuffManager 管理一个目标对象（通常是角色/单位）的 Buff/Debuff，并把多个修改器按规则叠加到目标属性（攻击/防御/速度等）上。

系统核心由 4 个层组成：

| 层级 | 职责 |
|------|------|
| **PodBuff** | 原子数值修改器（轻量）。只描述"改哪个属性、怎么改、改多少" |
| **MetaBuff** | 复合 Buff（状态机 + 组件容器）。自身不直接改属性，而是在激活/失效时注入/弹出一组 PodBuff |
| **PropertyContainer** | 单属性聚合器。维护该属性的 baseValue 与 PodBuff 列表，负责计算最终值 |
| **PropertyAccessor** | 对目标对象的属性做 `addProperty` 劫持，实现"读属性=取最终值；写属性=更新 baseValue" |

BuffManager 的职责是"调度"：
- 管理 Buff 生命周期（加入/移除/更新/注入/弹出）
- 维护 PodBuff 按属性分发到各 PropertyContainer
- 驱动在合适时机重建与重算，保证数值一致

```
┌─────────────────────────────────────────────────────────────┐
│                     业务层（技能/状态机）                      │
│  - 叠层计数、条件判断、冷却管理                              │
│  - 通过 add/remove/replace 驱动下层                          │
└──────────────────────────┬──────────────────────────────────┘
                           │ addBuff / removeBuff
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              BuffManager（数值修饰器引擎）                    │
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

## 2. 关键概念与名词

### 2.1 ID：外部注册 ID 与内部 ID

| ID 类型 | 来源 | 格式 | 用途 | 可用于 removeBuff? |
|---------|------|------|------|-------------------|
| **外部注册 ID (regId)** | `addBuff()` 返回值 | 用户指定或 `auto_` 前缀 | **唯一正确的移除/查询 ID** | ✅ 是 |
| **内部 ID (internalId)** | `BaseBuff.getId()` | 纯数字（如 `"42"`） | 系统内部追踪 | ❌ **禁止** |

**强约束：外部注册 ID 禁止纯数字字符串**
- `addBuff(buff, "123")` 会被拒绝（与内部 ID 空间冲突）
- 若不传 id，系统自动生成 `"auto_" + internalId`

**常见陷阱**：
```actionscript
// ❌ 错误用法
var buff:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
buffManager.addBuff(buff, null);       // 返回 "auto_42"
buffManager.removeBuff(buff.getId());  // 传入 "42"，找不到！

// ✅ 正确用法
var regId:String = buffManager.addBuff(buff, "my_buff");
buffManager.removeBuff(regId);
```

### 2.2 PodBuff 与计算类型

PodBuff 由三部分决定效果：
- `targetProperty`：目标属性名，例如 `"atk"`
- `calculationType`：计算类型（见 `BuffCalculationType` 常量）
- `value`：数值

**计算类型一览**：

| 类别 | 类型 | 公式 | 说明 |
|------|------|------|------|
| 通用（叠加型） | `MULTIPLY` | `base × (1 + Σ(m-1))` | 乘区相加 |
| 通用（叠加型） | `PERCENT` | `result × (1 + Σp)` | 乘区相加 |
| 通用（叠加型） | `ADD` | `result += Σvalue` | 累加 |
| 保守（独占型） | `MULT_POSITIVE` | `result × max(m)` | 正向乘法取最大 |
| 保守（独占型） | `MULT_NEGATIVE` | `result × min(m)` | 负向乘法取最小 |
| 保守（独占型） | `ADD_POSITIVE` | `result += max(v)` | 正向加法取最大 |
| 保守（独占型） | `ADD_NEGATIVE` | `result += min(v)` | 负向加法取最小 |
| 边界控制 | `MAX` | `max(result, value)` | 下限保底 |
| 边界控制 | `MIN` | `min(result, value)` | 上限封顶 |
| 边界控制 | `OVERRIDE` | `result = value` | 强制覆盖 |

**计算顺序（固定）**：
```
MULTIPLY → MULT_POSITIVE → MULT_NEGATIVE → PERCENT → ADD → ADD_POSITIVE → ADD_NEGATIVE → MAX → MIN → OVERRIDE
```

### 2.3 MetaBuff：注入式复合 Buff

MetaBuff 由以下部分组成：
- `childBuffs:Array`：一组 PodBuff 模板（激活时克隆后注入）
- `components:Array`：组件列表（TimeLimit/Tick/Condition 等）
- `priority:Number`：当前版本**未使用**

MetaBuff 状态机：
```
INACTIVE ─[激活]─► ACTIVE ─[失效]─► PENDING_DEACTIVATE ─► INACTIVE
                     │                      │
                注入 PodBuff            弹出 PodBuff
```

> **v2.9**: PENDING_DEACTIVATE 状态下不再更新组件，只做状态推进

---

## 3. 构造与回调

### 3.1 构造

```actionscript
var mgr:BuffManager = new BuffManager(
    target,                  // 必填：被管理的对象
    onPropertyChanged,       // 可选：属性变化回调
    onBuffAdded,             // 可选：buff 加入回调
    onBuffRemoved,           // 可选：buff 移除回调
    config                   // 可选：调试/开关配置
);
```

### 3.2 回调时机注意

- 回调可能在 `update()` 内触发
- 回调里**允许** `addBuff/removeBuff`，会进入延迟队列（v2.3 双缓冲保证不丢失）
- 回调里**不要**递归调用 `update()`：会直接 return

---

## 4. 对外 API

### 4.1 Buff 管理

| 方法 | 说明 |
|------|------|
| `addBuff(buff:IBuff, id?:String):String` | 添加 Buff，返回注册 ID |
| `addBuffImmediate(buff:IBuff, id?:String):String` | 添加并**立即生效**（内部调用 `update(0)`） |
| `addBuffs(buffs:Array, ids?:Array):Array` | **[v2.9]** 批量添加，返回 ID 数组 |
| `removeBuff(id:String):Boolean` | 延迟移除 Buff |
| `removeBuffImmediate(id:String):Boolean` | 移除并**立即生效** |
| `removeBuffsByProperty(prop:String):Number` | **[v2.9]** 移除指定属性上的所有独立 PodBuff |
| `clearAllBuffs():Void` | 清空所有 Buff，属性回到 base |

**addBuff 行为**：
- **非 update 期**：立即注册，数值等下次 `update()` 生效
- **update 期**：进入待处理队列，本帧末尾 flush
- **同 ID 替换**：若 id 已存在，先移除旧 buff 再注册新 buff

### 4.2 Base 值操作（v2.9 新增）

| 方法 | 说明 |
|------|------|
| `getBaseValue(prop:String):Number` | 获取属性的 base 值（未经 Buff 计算） |
| `setBaseValue(prop:String, value:Number):Void` | 直接设置 base 值 |
| `addBaseValue(prop:String, delta:Number):Void` | 对 base 值增量操作，**避免 `+=` 陷阱** |

**为什么需要这些 API**？见 [6.2 节](#62-禁止对接管属性做-读-改-写)。

### 4.3 属性管理

| 方法 | 说明 |
|------|------|
| `unmanageProperty(prop:String, finalize:Boolean):Void` | 解除属性托管 |
| `destroy():Void` | 销毁管理器（先 `clearAllBuffs` 再 finalize） |

**unmanageProperty 详解**：
- `finalize=true`：将当前可见值固化为普通属性值
- `finalize=false`：销毁容器并删除属性

### 4.4 查询

| 方法 | 说明 |
|------|------|
| `getBuffById(id:String):IBuff` | 按 ID 查询 Buff |
| `getActiveBuffCount():Number` | 获取激活 Buff 数量 |
| `getInjectedPodIds(metaId:String):Array` | 获取 MetaBuff 注入的 PodBuff ID 列表 |
| `getDebugInfo():Object` | 调试信息 |

### 4.5 生命周期

| 方法 | 说明 |
|------|------|
| `update(deltaFrames:Number):Void` | 帧更新，处理生命周期和重算 |

---

## 5. update() 内部阶段

理解这个流程对于调试"为何本帧不生效"非常重要。

```
BuffManager.update(deltaFrames)
    │
    ├─► 0. _inUpdate = true （设置重入保护）
    │
    ├─► 1. _processPendingRemovals()
    │       处理延迟移除队列
    │
    ├─► 2. _updateMetaBuffsWithInjection(deltaFrames)
    │       ├─► 更新所有 MetaBuff
    │       ├─► needsInject → _injectMetaBuffPods()
    │       ├─► needsEject  → _ejectMetaBuffPods()
    │       └─► 移除失效的 MetaBuff
    │
    ├─► 3. _removeInactivePodBuffs()
    │       移除失效的独立 PodBuff
    │
    ├─► 4. if (_isDirty)
    │       ├─► _redistributeDirtyProps() 或 _redistributePodBuffs()
    │       └─► PropertyContainer.forceRecalculate()
    │
    ├─► 5. _inUpdate = false
    │
    └─► 6. _flushPendingAdds()  ← v2.3 双缓冲队列
            处理 update 期间收集的延迟添加请求
```

**关键结论**：
- update 期间 add 的 buff **不会在同一次 update 的重分发阶段生效**
- 如需"同帧立即可见"，在**非 update 期**使用 `addBuffImmediate`

---

## 6. 属性接管规则（重要）

### 6.1 读写语义：读=最终值，写=修改 baseValue

当某属性被接管后：
- `target[prop]` 的**读取**返回"叠加后的最终值"
- `target[prop] = x` 的**写入**更新 `PropertyContainer.baseValue = x`

### 6.2 禁止对接管属性做"读-改-写"

这是**生产落地的高风险点**：

```actionscript
// 假设 atk base=100，buff 让最终值变成 150
target.atk += 10;
// 读取 target.atk 得到 150
// 写回 160 => base 被设置为 160
// buff 仍在时，最终值会变得更大（错误）
```

**正确做法**：

```actionscript
// 方案 1：使用 v2.9 新增 API
buffManager.addBaseValue("atk", 10);  // 只修改 base，不读 final

// 方案 2：显式读写 base
var base:Number = buffManager.getBaseValue("atk");
buffManager.setBaseValue("atk", base + 10);
```

### 6.3 PropertyContainer 的"粘性"

- 某属性一旦被接管，容器**永不自动销毁**
- Buff 清空后，属性仍存在，值回到 base
- 避免高频增删 Buff 导致属性变 `undefined`

**生命周期契约**：

| 操作 | 属性最终值 | 容器状态 |
|------|-----------|----------|
| `clearAllBuffs()` | 回到 base | 保留 |
| `destroy()` | 回到 base | 销毁 |
| `unmanageProperty(prop, true)` | 保留当前可见值 | 销毁 |
| `unmanageProperty(prop, false)` | 删除属性 | 销毁 |

---

## 7. MetaBuff 注入/弹出机制

### 7.1 注入 PodBuff 的 ID

MetaBuff 激活时，`createPodBuffsForInjection()` 生成新 PodBuff，以其 **internalId** 作为注册 id 放入 `_byInternalId`。

- `getInjectedPodIds(metaInternalId)` 返回一组 **internalId**（数字字符串）
- 这些 id 可用于调试/定位/强制移除（不建议业务层依赖）

### 7.2 注入顺序与优先级

- 注入的 PodBuff 会被 `push()` 到管理器 buff 列表末尾
- 全系统的"叠加优先级"主要由"插入顺序 + PropertyContainer 反向遍历"决定
- 当前版本**没有全局 priority 排序**

### 7.3 PENDING_DEACTIVATE 状态（v2.9）

- ACTIVE → PENDING_DEACTIVATE 时弹出 PodBuff（效果移除）
- PENDING_DEACTIVATE 状态下**不更新组件**，避免"多跳一次"问题
- 下一帧 PENDING_DEACTIVATE → INACTIVE 时 MetaBuff 被移除

---

## 8. 组件接口

### 8.1 可用组件

| 组件 | 用途 | 可用性 |
|------|------|--------|
| `TimeLimitComponent(frames)` | 限时自动移除 | ✅ 稳定可用 |
| `StackLimitComponent(max, decay)` | 层数管理 | ⚠️ 需配合同ID替换 |
| `ConditionComponent(func, interval)` | 条件触发 | ⚠️ 语义受限 |
| `CooldownComponent(frames)` | 冷却管理 | ⚠️ 不控制 Buff 存活 |

### 8.2 TimeLimitComponent v1.1 新增接口

```actionscript
var timeLimit:TimeLimitComponent = new TimeLimitComponent(150);

// 暂停/恢复
timeLimit.pause();              // 暂停计时
timeLimit.resume();             // 恢复计时
timeLimit.isPaused();           // 检查是否暂停

// 时间操作
timeLimit.getRemaining();       // 获取剩余帧数
timeLimit.setRemaining(frames); // 设置剩余帧数
timeLimit.addTime(delta);       // 增加/减少剩余时间
```

**使用场景**：
- 时停技能：`pause()` 所有 buff 计时
- 时间延长道具：`addTime()` 延长 buff 持续时间
- UI 显示：`getRemaining()` 显示剩余时间

---

## 9. 可重入与事件驱动

BuffManager 策略：
- **update 不允许重入**（防止迭代中修改自身）
- update 期间的 add/remove 统一排队
- **v2.3 双缓冲队列**保证回调中 `addBuff()` 不丢失

MetaBuff 组件可能在 update 中触发回调：
- 回调可以请求 add/remove（会排队）
- 回调不应直接调用 update（无效）

---

## 10. 性能建议

1. **每帧只调用一次 update**
2. **避免滥用 addBuffImmediate**：会导致同帧强制重分发
3. **优先用 PodBuff** 处理纯数值修改（热路径友好）
4. **MetaBuff 只用于需要生命周期管理的场景**
5. **批量操作时**让业务侧集中 add/remove，最后一次 update

---

## 11. 常见用法示例

### 11.1 添加简单 PodBuff

```actionscript
var b:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
var id:String = mgr.addBuff(b, "equip_sword");
// 下一帧 update() 后 atk 按计算规则更新
```

### 11.2 立刻生效

```actionscript
mgr.addBuffImmediate(new PodBuff("spd", BuffCalculationType.MULTIPLY, 1.5));
// 立即可读到更新后的 spd 值
```

### 11.3 同 ID 替换（刷新/重置）

```actionscript
mgr.addBuff(new PodBuff("atk", BuffCalculationType.ADD, 10), "rage");
// ... later
mgr.addBuff(new PodBuff("atk", BuffCalculationType.ADD, 20), "rage");
// 自动移除旧的 rage，加入新的
```

### 11.4 MetaBuff 持续 150 帧

```actionscript
var atkBuff:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
var meta:MetaBuff = new MetaBuff([atkBuff], [new TimeLimitComponent(150)], 0);
mgr.addBuff(meta, "skill_powerup");
```

### 11.5 修改 base 值（避免 += 陷阱）

```actionscript
// ❌ 错误
target.atk += 10;  // 会把 final 值写进 base

// ✅ 正确
mgr.addBaseValue("atk", 10);
```

### 11.6 批量添加（v2.9）

```actionscript
var buffs:Array = [
    new PodBuff("atk", BuffCalculationType.ADD, 20),
    new PodBuff("def", BuffCalculationType.ADD, 10)
];
var ids:Array = mgr.addBuffs(buffs, ["buff_atk", "buff_def"]);
```

### 11.7 移除属性上的所有 Buff（v2.9）

```actionscript
var count:Number = mgr.removeBuffsByProperty("atk");
trace("移除了 " + count + " 个 atk 相关的 buff");
```

---

## 12. 调试

```actionscript
// 获取调试信息
trace(mgr.getDebugInfo());

// 检查某 ID 是否在管理器内
var buff:IBuff = mgr.getBuffById("my_buff");
```

---

## 13. 生产落地检查清单

| # | 规则 | 说明 |
|---|------|------|
| 1 | **禁止对被接管属性使用 `+=`/`-=`/`*=`/`++`** | 会导致属性永久漂移 |
| 2 | **修改 base 值走专用 API** | 使用 `addBaseValue()` 或 `setBaseValue()` |
| 3 | **removeBuff 必须用 addBuff 返回值** | 禁止用 `buff.getId()` |
| 4 | **外部 ID 禁止纯数字** | 会与内部 ID 冲突 |
| 5 | **同一 Buff 实例禁止重复注册** | 系统会拒绝 |

---

## 14. 测试与验证

### 14.1 运行测试

```actionscript
// 核心功能测试（67 个用例）
org.flashNight.arki.component.Buff.test.BuffManagerTest.runAllTests();

// Bugfix 回归测试（30 个用例，含 v2.9 新 API 测试）
org.flashNight.arki.component.Buff.test.BugfixRegressionTest.runAllTests();

// BuffCalculator 单元测试
org.flashNight.arki.component.Buff.test.BuffCalculatorTest.runAllTests();

// 组件测试
org.flashNight.arki.component.Buff.test.Tier1ComponentTest.runAllTests();

org.flashNight.arki.component.Buff.test.Tier2ComponentTest.runAllTests();
```

### 14.2 测试覆盖状态

| 测试类别 | 通过/总数 | 状态 |
|----------|-----------|------|
| 基础计算 (ADD/MULTIPLY/PERCENT/OVERRIDE) | 5/5 | ✅ |
| 边界控制 (MAX/MIN) | 2/2 | ✅ |
| 保守语义 | 6/6 | ✅ |
| MetaBuff 注入 | 4/4 | ✅ |
| 限时组件 | 4/4 | ✅ |
| 复杂场景 | 4/4 | ✅ |
| PropertyContainer | 4/4 | ✅ |
| 边界情况 | 4/4 | ✅ |
| 性能测试 | 3/3 | ✅ |
| Sticky 容器 | 7/7 | ✅ |
| v2.3 重入安全 | 6/6 | ✅ |
| v2.9 新 API | 8/8 | ✅ |
| **核心功能总计** | **67/67** | ✅ |
| **Bugfix 回归测试** | **30/30** | ✅ |

### 14.3 性能基准

```
100 Buffs + 100 Updates = 57ms
平均每次 update: 0.57ms
单次大规模计算: 10ms (100 Buffs)
```

---

## 附录 A: 设计契约

本节记录 BuffManager 系统的核心设计契约，任何修改都应保持这些契约不变。

### A.1 延迟添加生效时机（契约1）

```
在 update() 期间调用 addBuff/removeBuff，效果从本次 update() 结束时生效
```

### A.2 OVERRIDE 冲突决策（契约2）

```
多个 OVERRIDE 并存时，添加顺序最早的 OVERRIDE 生效
```

原因：`PropertyContainer._computeFinalValue()` 使用 `while(i--)` 逆序遍历，`BuffCalculator` 的 OVERRIDE 采用"最后写入 wins"语义，组合效果是先添加的生效。

### A.3 重入安全保证（契约3）

```
在任何回调中调用 addBuff() 是安全的，使用双缓冲队列保证不丢失
```

### A.4 ID 命名空间（契约4）

```
外部 ID 禁止纯数字，内部 ID 仅用于注入 PodBuff
```

| 映射 | 存储内容 | ID 格式 |
|------|----------|---------|
| `_byExternalId` | 独立 Pod + MetaBuff | 用户指定或 `auto_` 前缀 |
| `_byInternalId` | 注入的 PodBuff | 纯数字（自增） |

### A.5 MAX/MIN 语义（契约5）

```
MAX: 下限保底
MIN: 上限封顶
应用顺序: ... → MAX → MIN → OVERRIDE
```

### A.6 组件不得 throw 异常（契约6，v2.4）

```
IBuffComponent 的 update()/onAttach()/onDetach()/isLifeGate() 不得 throw
```

### A.7 PodBuff.applyEffect 属性匹配由调用方保证（契约7，v2.4）

```
PropertyContainer.addBuff() 已验证属性匹配，applyEffect() 无需重复检查
```

---

## 附录 B: 版本变更日志

### B.1 v2.9 (2026-01-20)

**新增 API**：
| API | 说明 |
|-----|------|
| `getBaseValue(prop)` | 获取属性 base 值 |
| `setBaseValue(prop, value)` | 设置属性 base 值 |
| `addBaseValue(prop, delta)` | 对 base 值增量操作 |
| `addBuffs(buffs, ids)` | 批量添加 Buff |
| `removeBuffsByProperty(prop)` | 移除属性上所有独立 PodBuff |

**MetaBuff 修复**：
- PENDING_DEACTIVATE 状态下跳过组件更新（避免"多跳一次"问题）

**TimeLimitComponent v1.1**：
- 新增 `pause()/resume()/isPaused()`
- 新增 `getRemaining()/setRemaining()/addTime()`

**StateInfo v1.2**：
- 改用静态初始化，消除首次调用的 null 检查

**PropertyContainer v2.4**：
- `_cachedFinalValue` 不显式初始化（AS2 默认 NaN）

### B.2 v2.3 重入安全修复

**问题**：`_flushPendingAdds` 在处理队列时，回调触发的 `addBuff()` 可能被跳过。

**解决方案**：双缓冲队列
- `_pendingAddsA` 和 `_pendingAddsB` 交替使用
- 处理 A 时新增写入 B，循环直到两队列都空

### B.3 v2.4 性能优化

- MetaBuff 移除 `try/catch`（契约化设计）
- PodBuff.applyEffect 移除冗余属性检查
- 新增 `MetaBuff.removeInjectedBuffId()` 方法

---

## 附录 C: 文件清单与版本

| 文件 | 版本 | 说明 |
|------|------|------|
| `BuffManager.as` | v2.9 | 核心管理器 |
| `PropertyContainer.as` | v2.4 | 属性容器 |
| `MetaBuff.as` | v1.6 | 复合 Buff |
| `PodBuff.as` | v1.2 | 原子数值 Buff |
| `BaseBuff.as` | v1.3 | Buff 基类 |
| `BuffCalculator.as` | v1.2 | 计算引擎 |
| `StateInfo.as` | v1.2 | MetaBuff 状态信息 |
| `TimeLimitComponent.as` | v1.1 | 限时组件 |
| `IBuff.as` | v1.1 | Buff 接口 |
| `IBuffComponent.as` | v1.0 | 组件接口 |
| `BuffCalculationType.as` | v1.1 | 计算类型常量 |
| `BuffContext.as` | v1.0 | 计算上下文 |

---

## 附录 D: 测试结果存档

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

🧪 Test 38: unmanageProperty(finalize) then rebind uses plain value as base
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


--- Phase 8-11: Regression Tests ---
🧪 Tests 44-63: All regression tests
  ✅ ALL PASSED


--- Phase 12: Bugfix Regression Tests ---
=== Bugfix Regression Test Suite ===
Testing fixes from 2026-01 review

--- P0 Critical Fixes ---
[Test 1-5] P0 Critical Fixes
  All PASSED

--- v2.3 Critical: Reentry Safety ---
[Test 6-9] v2.3 Reentry Safety
  All PASSED

--- v2.3 Contract Verification ---
[Test 10-11] v2.3 Contracts
  All PASSED

--- P1 Important Fixes ---
[Test 12-14] P1 Fixes
  All PASSED

--- P2 Optimizations ---
[Test 15] P2 Boundary Controls
  PASSED

--- v2.4 Fixes ---
[Test 16-18] v2.4 Fixes
  All PASSED

--- v2.6 Fixes ---
[Test 19-22] v2.6 Fixes
  All PASSED

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
  After frame 1: componentUpdateCount=1, stat=150
  After frame 2: componentUpdateCount=2, stat=100
  After frame 3 (PENDING_DEACTIVATE): componentUpdateCount=2, stat=100
  Component update counts: frame1=1, frame2=2, frame3=2, frame4=2
  PASSED

[Test 28] v2.9: TimeLimitComponent pause/resume should work
  Frame 1: remaining=4, value=150
  After 3 paused updates: remaining=4, value=150
  After resume + 1 update: remaining=3
  PASSED

[Test 29] v2.9: TimeLimitComponent time operations
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


--- Phase 13: addBuffImmediate API Tests ---
🧪 Tests 64-67: addBuffImmediate tests
  ✅ ALL PASSED


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
