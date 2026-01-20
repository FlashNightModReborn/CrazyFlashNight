# `org.flashNight.neur.Event.EventBus` 使用指南

## 版本历史

### v2.2 (2026-01) - 代码审查修复
- **[PERF]** `publish/publishWithParam` 移除 try/catch，采用 let-it-crash 策略提升热路径性能
- **[FIX]** `destroy()` 添加 `_dispatchDepth` 检查，阻止在回调执行期间销毁导致的状态不一致
- **[FIX]** `subscribeOnce` 添加 owner 参数，支持通知 EventDispatcher 清理订阅记录
- **[CONTRACT]** 明确 let-it-crash 策略：回调异常将直接传播，不再静默捕获

### v2.1 (2026-01) - 三方交叉审查修复
- **[CRITICAL]** `subscribeOnce` 的 `onceCallbackMap` 改为按事件分桶结构，修复多事件注册时互相覆盖的严重问题
- **[PERF]** `publish` 参数使用 `_argsStack` 深度复用，消除每次调用的数组分配
- **[PERF]** `subscribeOnce` 移除多余的 `Delegate.create` 包装，减少函数调用层级
- **[FIX]** `subscribeOnce` 添加 `funcToID` 映射，统一订阅/退订语义
- **[PERF]** `subscribe` 中 UID 计算合并，减少冗余调用
- **[CLEAN]** 移除未使用的 `tempArgs/tempCallbacks` 死代码

### v2.0 (2026-01) - 代码审查修复
- **[FIX]** `unsubscribe` 清理 `funcToID` 映射，修复"退订后无法再订阅"问题
- **[FIX]** `subscribeOnce` 传递 `originalCallback` 给 `unsubscribe`，修复 `onceCallbackMap` 泄漏
- **[PERF]** `publish` 使用深度栈复用替代 `slice()`，减少 GC 压力

### 契约说明
- **回调执行顺序不保证**：`for..in` 枚举 Object key 在 AS2 中无序
- 调用方需确保 `callback` 和 `scope` 的有效性
- 同一 `callback` 不可同时用于同一事件的 `subscribe` 和 `subscribeOnce`

---

## 1. 概述

在传统的 Flash 开发（ActionScript 2.0）中，事件的传播与管理常常依赖内置的事件系统（例如 `onEnterFrame`、`onClick` 等）或基于显示列表的广播。随着项目复杂度的提升，这种直接耦合的事件处理方式会导致模块间相互依赖，难以维护。

**`EventBus`** 提供了一个全局的“消息中心”，所有模块都可以通过**发布**（`publish` / `publishWithParam`）和**订阅**（`subscribe` / `subscribeOnce`）事件来进行解耦的通信。具体而言：
- 需要触发某个事件的模块通过 `publish` 或 `publishWithParam` 对外发布消息；
- 对该事件感兴趣的模块则通过 `subscribe` 或 `subscribeOnce` 注册回调函数；
- 事件触发后，所有订阅者都会收到通知，并可在各自的回调中进行业务逻辑处理。

此类**松耦合**的设计，让模块之间无需相互引用就能进行通信，大幅提高了代码的扩展性与可维护性。

---

## 2. 特性亮点

1. **饿汉式单例模式**  
   - 在类加载时即初始化单例 `EventBus.instance`，确保全局只有一个事件总线实例，避免重复创建。
   
2. **内存池与索引管理**  
   - 维护一个回调函数池（`pool`）与可用空间栈（`availSpace`），减少运行中对象的重复创建。  
   - 当内存池空间不足时，采用倍增策略进行扩容。
   
3. **多种发布方式**  
   - `publish`：直接传可变长参数（`...args`）。  
   - `publishWithParam`：显式传入一个 `paramArray`。  
   - 内部对不同数量的参数进行了手动展开与优化，提升高频调用时的效率。
   
4. **多种订阅方式**  
   - `subscribe`: 普通订阅，持续生效。  
   - `subscribeOnce`: 一次性订阅，回调函数只执行一次后自动取消。
   
5. **快速取消订阅**  
   - 通过维护回调函数的唯一 ID（`Dictionary.getStaticUID`），在取消订阅时能快速定位并释放回调。
   - 对一次性回调做了额外的映射处理，避免难以追踪的回调泄漏。
   
6. **全面的测试与性能验证**  
   - 自带 `EventBusTest` 测试类，涵盖功能测试与性能测试，确保在大量订阅、高频发布的场景下依旧表现良好。

---

## 3. 典型使用场景

- **跨组件或跨层级事件传递**：例如界面模块与逻辑模块、数据模块与动画模块之间的交互。
- **全局广播**：游戏或应用状态改变时，需要多处进行联动更新。
- **简化复杂事件流程**：避免传统事件监听中横向或纵向层级混杂导致的维护难题。

---

## 4. API 详解

以下为 `EventBus` 提供的主要方法及其用法说明。

### 4.1 获取单例

```actionscript
public static function getInstance():EventBus
```
或直接使用
```actionscript
EventBus.instance
```
**说明**：  
- 由于采用饿汉式单例，可以在程序任意处调用 `EventBus.instance` 来获取或使用事件总线。  
- 如果需要手动初始化，一般在程序入口处调用 `EventBus.initialize()`。两者效果相同。

---

### 4.2 `subscribe(eventName:String, callback:Function, scope:Object):Void`

**功能**：订阅指定事件，绑定回调函数。当 `eventName` 对应的事件被发布时，会在 `scope` 所指向的上下文执行 `callback`。  
- `eventName`: 字符串类型，事件名称。  
- `callback`: 事件触发时要执行的回调函数（普通函数或 `Delegate.create(...)` 生成的代理函数）。  
- `scope`: 回调函数的作用域（this 指向）。

**示例**：

```actionscript
// 假设我们有一个玩家跳跃事件 "PLAYER_JUMP"
EventBus.instance.subscribe("PLAYER_JUMP", onPlayerJump, this);

function onPlayerJump() {
    trace("玩家跳跃逻辑被触发！");
}
```

---

### 4.3 `unsubscribe(eventName:String, callback:Function):Void`

**功能**：取消订阅先前注册的回调，防止其在事件发布时被触发。  
- `eventName`: 字符串类型，要取消订阅的事件名称。  
- `callback`: 之前传给 `subscribe` 或 `subscribeOnce` 的回调函数。

**注意**：如果订阅时用了 `Delegate.create(this, someFunc)`，则在 `unsubscribe` 时，**也需要用相同的 `Delegate.create`** 来标识它。

**示例**：

```actionscript
EventBus.instance.unsubscribe("PLAYER_JUMP", onPlayerJump);
```

调用后，`onPlayerJump` 将不再响应 `"PLAYER_JUMP"` 事件。

---

### 4.4 `publish(eventName:String, ...args):Void`

**功能**：发布事件，并将可变数量的参数传给所有订阅者。  
- `eventName`: 字符串类型，事件名称。  
- `args`: 任意个数或类型的参数。

回调接收方式示例：
```actionscript
EventBus.instance.subscribe("PLAYER_SCORE_CHANGED", Delegate.create(this, onScoreChanged), this);

function onScoreChanged(newScore:Number, bonus:Number) {
    trace("分数变更: " + newScore + ", 奖励: " + bonus);
}

// 发布带两个参数的事件
EventBus.instance.publish("PLAYER_SCORE_CHANGED", 100, 20);
```

---

### 4.5 `publishWithParam(eventName:String, paramArray:Array):Void`

**功能**：以一个数组形式传参来发布事件。适合需要传递复杂或动态参数时使用。  
- `eventName`: 字符串类型，事件名称。  
- `paramArray`: 参数数组，将被传递给回调函数。

**示例**：

```actionscript
EventBus.instance.subscribe("PLAYER_STATUS_UPDATE", Delegate.create(this, onStatusUpdate), this);

function onStatusUpdate(health:Number, mana:Number, items:Array) {
    trace("生命值:" + health + ", 法力值:" + mana + ", 背包:" + items);
}

// 以数组方式传入
var args:Array = [80, 50, ["Sword", "Shield"]];
EventBus.instance.publishWithParam("PLAYER_STATUS_UPDATE", args);
```

---

### 4.6 `subscribeOnce(eventName:String, callback:Function, scope:Object):Void`

**功能**：一次性订阅某个事件，回调函数只执行一次后立即自动取消订阅。  
- `eventName`: 字符串类型，事件名称。  
- `callback`: 回调函数。  
- `scope`: 回调函数的作用域。

**实现原理**：内部会先将 `callback` 用包装函数代理，当该事件首次发布后，执行包装函数并自动调用 `unsubscribe` 移除回调。

**示例**：

```actionscript
EventBus.instance.subscribeOnce("LEVEL_COMPLETE", onLevelCompleteOnce, this);

function onLevelCompleteOnce() {
    trace("关卡完成，只在第一次触发时生效，之后自动移除。");
}
```

**注意**：如果需要手动取消一次性订阅，也需要使用原始的回调函数进行 `unsubscribe`。

---

### 4.7 `destroy():Void`

**功能**：销毁整个事件总线，释放所有事件监听器、回调函数以及内部缓存结构。通常只在应用结束、场景彻底销毁或调试场景下使用。

**示例**：

```actionscript
// 停止并清理所有事件监听
EventBus.instance.destroy();
```

调用后，`EventBus` 将清空内存池、可用空间数组和所有监听器记录。

---

## 5. 内部机制与优化

### 5.1 回调池 (`pool`) 与可用索引 (`availSpace`)

- 在构造时预先分配了一定大小（默认为 1024）的数组，所有回调函数会以索引的方式存储到 `pool` 中。  
- 当有新的回调要加入时，会从 `availSpace` 弹出一个空闲索引来存储该回调；当取消订阅时，再把该索引推回 `availSpace`，供后续使用。  
- **扩展容量**：当 `availSpace` 耗尽时，会自动调用 `expandPool` 进行容量倍增；并将旧池数据复制到新池中，保证大规模订阅时也能稳定运行。

### 5.2 参数展开与调用优化

- 对于常用的参数长度（0～10 以及部分更高值），`publish` / `publishWithParam` 中使用了**手动展开**方法调用，减少 `apply` 带来的性能损耗。  
- 当参数数量超过一定阈值时，才会使用 `Function.apply` 动态调用。  
- 在高频调用的场景下，这种“有针对性的手动展开”能够显著降低 CPU 开销。

### 5.3 一次性订阅映射 (`onceCallbackMap`)

- **[v2.1 更新]** `onceCallbackMap` 采用按事件分桶的结构：`{ eventName -> { funcUID -> wrappedCallback } }`
- 之前的全局单表结构会导致不同事件使用相同回调函数时互相覆盖，现已修复
- 在 `subscribeOnce` 中，原始回调被包装后会存入对应事件的桶中，以便在 `unsubscribe` 时能够正确地查到并移除那个包装后的回调
- 避免了调用 `unsubscribe` 时无法定位"一次性包装函数"的问题，大大降低了忘记手动清理回调造成的内存泄漏风险

### 5.4 高并发与高频测试覆盖

- 测试类 `EventBusTest` 包含了功能性测试（确保订阅、取消订阅、一次性订阅、参数传递、异常捕获等正常工作）和**高压性能测试**（大规模订阅、多事件并发、高频发布、批量取消等）。  
- 测试结果显示，`EventBus` 在 1 万以上订阅者、10 万次以上事件发布的场景中依旧具备较好的性能，能够应用于大型项目或高频事件场景（如游戏中的 AI、动画帧事件、多人同步更新等）。

---

## 6. 对比传统 Flash 事件模型

| 特性            | Flash 原生事件                       | `EventBus`                              |
|-----------------|--------------------------------------|-----------------------------------------|
| 事件管理方式    | 基于 `MovieClip` 或 `Listener`       | 统一的全局发布/订阅                     |
| 耦合度          | 多数情况下需要持有目标实例引用       | 松耦合，无需知道订阅者/发布者之间的关系 |
| 多模块通信      | 需要复杂的层级或引用传递             | 通过统一的事件名进行跨模块通讯          |
| 一次性订阅      | 无内置支持，需手动写逻辑             | 提供 `subscribeOnce`，自动取消          |
| 性能优化        | 参数传递一般需 `apply` 或原生支持    | 手动展开 + 回调池，适合高频、海量事件    |
| 大规模测试与验证| 仅有基础事件机制                    | 自带丰富的单元测试与性能测试            |

---

## 7. 典型用法示例

### 7.1 模块间通信

假设有一个**数据模块**负责加载并解析外部配置，一个**界面模块**需要在解析完成后更新界面。可以这样设计：

```actionscript
// 数据模块
function loadConfig() {
    // ... 执行加载和解析 ...
    EventBus.instance.publish("CONFIG_LOADED", configData); 
}

// UI 模块
EventBus.instance.subscribe("CONFIG_LOADED", onConfigLoaded, this);

function onConfigLoaded(data:Object) {
    // 根据 data 刷新界面
    trace("配置加载完成，开始更新界面...");
}
```

### 7.2 全局广播事件

当网络断开或玩家掉线，需要通知全局多个模块（UI、数据同步、提示框等）：

```actionscript
// 网络模块
function onNetworkDisconnected() {
    EventBus.instance.publish("NETWORK_DISCONNECTED");
}

// UI 模块
EventBus.instance.subscribe("NETWORK_DISCONNECTED", function() {
    trace("网络断开，弹出提示对话框");
}, this);

// 其他需要处理断网的模块也各自 subscribe 同一事件
```

### 7.3 一次性逻辑（动画播放完成、任务达成等）

```actionscript
EventBus.instance.subscribeOnce("MISSION_COMPLETED", function() {
    trace("任务完成，只处理一次的逻辑，比如领取奖励");
}, this);
```

---

## 8. 性能建议

1. **合理利用回调池**  
   - 不要频繁创建/销毁大量回调对象，尤其在性能敏感的场景中。  
   - 如果知道订阅会长期存在，就采用普通 `subscribe`；只执行一次的用 `subscribeOnce`。避免过度订阅又立即退订。

2. **减少过深的嵌套发布**  
   - 在回调内部再次 `publish` 可以实现嵌套事件，但要避免**无限或深度循环**发布，否则容易出现性能或逻辑问题。

3. **批量管理**  
   - 如果需要同时订阅/取消订阅一批回调，可以在循环中进行统一操作；如需初始化大量事件，可优先适当增大初始容量，以减少 `expandPool` 频次。

4. **异常处理**  
   - 回调若可能抛出异常，`EventBus` 内部会捕获并忽略，以保证不影响其他回调的执行。但请务必在业务层面进行合理的异常处理或记录。

---

## 9. 总结

`EventBus` 通过**全局单例**、**回调池**和**手动参数展开**等多重优化，实现了高性能、低耦合的事件管理。它非常适合需要在模块间进行灵活通信的中大型 Flash/AS2 项目，尤其是需要处理**大规模事件**或**高频发布**的场景。

- 统一的事件调度，方便调试与维护  
- 灵活的订阅形式（普通、一次性、无参数、多参数）  
- 广泛的单元测试和性能测试验证  
- 适合各类模块间的解耦消息传递

如需更进一步了解测试细节及性能数据，可参考配套的 `EventBusTest` 类。希望本指南能帮助您在项目中更好地使用并维护 `EventBus`！

---


// 导入 EventBusTest 类
import org.flashNight.neur.Event.EventBusTest;

// 创建 EventBusTest 实例，自动运行所有测试
var eventBusTester:EventBusTest = new org.flashNight.neur.Event.EventBusTest();

[PASS] Test 1: EventBus subscribe and publish single event
[PASS] Test 2: EventBus unsubscribe callback
[PASS] Test 3: EventBus subscribeOnce - first publish
[PASS] Test 3: EventBus subscribeOnce - second publish
[PASS] Test 4: EventBus publish event with arguments
[PASS] Test 5: EventBus callback error handling - error callback was called
[PASS] Test 6: EventBus destroy and ensure callbacks are not called
[PASS] publishWithParam - zero arguments
[PASS] publishWithParam - multiple arguments
[PASS] publishWithParam - 10 arguments
[PASS] publishWithParam - complex object validation
[PASS] subscribeOnce - should only trigger once
[PASS] subscribeOnce - should not affect other subscribers
[PASS] subscribeOnce - nested publish
[PASS] subscribeOnce - nested cleanup
[PASS] subscribeOnce - mass subscription (1000 callbacks)
[PASS] subscribeOnce - unsubscribe before publish
[PASS] subscribeOnce - partial unsubscribe cleanup
[PASS] subscribeOnce - high volume (5) with GC check
[PASS] [v2.0] unsubscribe-resubscribe - first subscription works
[PASS] [v2.0] unsubscribe-resubscribe - unsubscribe works
[PASS] [v2.0] unsubscribe-resubscribe - resubscribe after unsubscribe works
[PASS] [v2.0] recursive-publish - nested publish works correctly
[PASS] [v2.0] onceCallbackMap-cleanup - mapping exists before publish
[PASS] [v2.0] onceCallbackMap-cleanup - mapping cleaned after publish
[PASS] [v2.0] onceCallbackMap-cleanup - callback executed once
[PASS] [v2.1 S1] event-bucketing - event 1 callback executed
[PASS] [v2.1 S1] event-bucketing - event 2 callback not overwritten
[PASS] [v2.1 S1] event-bucketing - both events only fire once
[PASS] [v2.1 I4] paramsUID-collision - single param with delimiter
[PASS] [v2.1 I4] paramsUID-collision - two params no collision
[PASS] [v2.1 I4] paramsUID-collision - different delegates created
[PASS] [v2.1 I5] UID-enumerable - UID assigned
[PASS] [v2.1 I5] UID-enumerable - __dictUID not in for..in
[PASS] [v2.1 I5] UID-enumerable - only original keys enumerated
[PASS] [v2.1 I8] uidMap-cleanup - getItem works after setItem
[PASS] [v2.1 I8] uidMap-cleanup - getItem returns null after removeItem
[PASS] [v2.1 I8] uidMap-cleanup - other keys not affected
[PASS] [v2.1 I8] uidMap-cleanup - getItem returns null after clear
[PASS] [v2.1 I8] uidMap-cleanup - count is 0 after clear
[EventBus] Warning: destroy() called during dispatch (depth=1), operation rejected
[PASS] [v2.2 P1-3] destroy-during-dispatch - destroy was attempted
[PASS] [v2.2 P1-3] destroy-during-dispatch - callback completed
[PASS] [v2.2 P1-3] destroy-during-dispatch - EventBus still works after guarded destroy
[PASS] [v2.2 P1-1] let-it-crash - error callback was called
[PASS] Test 7: EventBus handles high volume of subscriptions and publishes correctly
[PERFORMANCE] Test 7: EventBus High Volume Subscriptions and Publish took 228 ms
[PASS] Test 8: EventBus handles high frequency publishes correctly
[PERFORMANCE] Test 8: EventBus High Frequency Publish took 1132 ms
[PASS] Test 9: EventBus handles concurrent subscriptions and publishes correctly
[PERFORMANCE] Test 9: EventBus Concurrent Subscriptions and Publishes took 332 ms
[PASS] Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly
[PERFORMANCE] Test 10: EventBus Mixed Subscribe and Unsubscribe took 1482 ms
[PASS] Test 11: EventBus handles nested event publishes correctly
[PERFORMANCE] Test 11: EventBus Nested Event Publish took 0 ms
[PASS] Test 12: EventBus handles parallel event processing correctly
[PERFORMANCE] Test 12: EventBus Parallel Event Processing took 1128 ms
[PASS] Test 13: EventBus handles long-running subscriptions and cleanups correctly
[PERFORMANCE] Test 13: EventBus Long Running Subscriptions and Cleanups took 76 ms
[PASS] Test 14: EventBus handles complex argument passing correctly
[PERFORMANCE] Test 14: EventBus Complex Argument Passing took 0 ms
[PASS] Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly
[PERFORMANCE] Test 15: EventBus Bulk Subscribe and Unsubscribe took 2271 ms
All tests completed.
