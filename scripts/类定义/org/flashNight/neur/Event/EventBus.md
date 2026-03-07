# `org.flashNight.neur.Event.EventBus` 使用指南

## 版本历史

### v3.0 (2026-03) - 结构性性能重构
- **[PERF]** listeners 从 `Object{comboUID:poolIndex}` 改为并行数组 `fns[]/scopes[]`
  - 消除 publish 中的 `for..in` 枚举（H16: 2200~7800ns/iter → `while(i--)` ~35ns/iter）
  - 回调执行变为确定性逆序（后订阅先执行），原契约已声明"顺序不保证"
- **[PERF]** 去掉 `Delegate.create` 包装层，publish 时直接 `fn.call(scope, ...)`
  - 消除闭包双重调用（~1235ns 闭包 + ~1340ns call → 单次 ~1340ns call）
- **[PERF]** 去掉 `pool/availSpace` 对象池，改为直接数组存储
  - subscribe 路径不再需要池分配/Delegate 创建
- **[PERF]** unsubscribe 使用 swap-and-pop 替代线性查找删除（消除 splice 4231ns 开销）
- **[PERF]** 新增 `publish0/publish1/publish2` 特化入口，完全消除 `arguments` 开销
  - H09: arguments.length=1538ns, arguments读取=1306ns
- **[COMPAT]** 外部 API 签名完全不变，对 EventDispatcher 和业务代码透明
- **[COMPAT]** Delegate 缓存机制保留用于外部直接使用，EventBus 内部不再依赖

### v2.3.3 (2026-01) - 严重问题修复
- **[CRITICAL]** `expandPool()` 修复 do..while 边界错误（v3.0 已移除 expandPool）
- **[FIX]** `forceResetDispatchDepth()` 增强：同时清空栈数组中的残留引用

### v2.3.2 (2026-01) - 性能优化 + 参数验证
- **[CRITICAL]** 所有公共方法拒绝 null/空字符串 eventName，防止意外行为
- **[PERF]** `unsubscribe` 兼容模式：缓存前缀字符串，避免循环内重复拼接
- **[PERF]** `unsubscribe` 兼容模式：使用并行数组替代临时对象，减少内存分配
- **[PERF]** `subscribe/subscribeOnce`：UID 直接转为 String，避免重复类型转换

### v2.3.1 (2026-01) - 性能回归修复 + bug 修复
- **[CRITICAL PERF]** `_removeSubscription` 添加 eventName 参数，从 O(n) 优化为 O(1)
- **[FIX]** `unsubscribe` 兼容模式修复：subscribeOnce 的 funcToID 值是 wrappedUID，需用它查找 callbacks
- **[FIX]** `destroy()` 返回 false 当无内容需要清理

### v2.3 (2026-01) - 三方交叉审查综合修复
- **[CRITICAL]** 去重键改为 `(callback, scope)` 组合，修复同 callback 不同 scope 被静默忽略的问题
- **[CRITICAL]** `subscribe/subscribeOnce` 返回 Boolean，让调用方知道是否成功订阅
- **[CRITICAL]** `unsubscribe` 添加可选 scope 参数，支持精确退订
- **[PERF]** `publish/publishWithParam` 移除 try/finally，彻底消除热路径开销
- **[PERF]** 参数展开从 10 扩展到 15，>15参数时直接使用数组，移除 slice() 分配
- **[FIX]** `destroy()` 返回 Boolean 表示是否成功执行

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
- **[v3.0]** 回调执行顺序为确定性逆序（后订阅先执行），原契约声明"顺序不保证"
- 调用方需确保 `callback` 和 `scope` 的有效性
- **[v2.3]** `(callback, scope)` 组合唯一标识一个订阅，同 callback 不同 scope 可共存
- **[v2.3]** 回调中的异常不再被捕获，会直接抛出（let-it-crash 策略，无 try/finally）
- **[v2.3]** 不要在 publish 回调中调用 `destroy()`，会被拒绝执行并返回 false
- **[v3.0]** EventBus 内部不再使用 Delegate.create 包装，scope 通过 `fn.call(scope)` 绑定

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

### 4.4 `publish0/publish1/publish2` (v3.0)

```actionscript
public function publish0(eventName:String):Void
public function publish1(eventName:String, a1):Void
public function publish2(eventName:String, a1, a2):Void
```

**功能**：零/单/双参数特化发布，完全不创建 `arguments` 对象。热路径优先使用。

### 4.5 `publish(eventName:String, ...args):Void`

**功能**：通用发布，支持可变数量参数（3+ 参数时使用）。  
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

### 5.1 并行数组存储（v3.0）

- **[v3.0]** 每个事件维护 `fns[]` 和 `scopes[]` 两个并行数组，以及 `ids{}` 哈希索引用于去重和退订
- **ids 单键不变量**：每个数组槽位在 `ids` 中严格对应一个键（普通订阅为 comboUID，once 订阅为 wrappedComboUID）
- subscribe 时追加到数组末尾，O(1)
- unsubscribe 使用 swap-and-pop，O(1) 删除（替代 v2.x 的 splice，H20: 4231ns）
- publish 时使用 `while(i--)` 遍历数组（替代 v2.x 的 `for..in`，H16: 2200~7800ns/iter → ~35ns/iter）
- **[v3.0]** 不再使用 `Delegate.create` 包装，publish 时直接 `fn.call(scope, ...)`
  - 消除闭包调用层（~1235ns/回调），scope 绑定由 `call` 的第一个参数提供

### 5.2 参数展开与调用优化

- **[v3.0]** 新增 `publish0/publish1/publish2` 特化入口，完全不创建 `arguments` 对象
  - H09: arguments.length=1538ns, arguments读取=1306ns，特化版本零开销
- 通用 `publish` 对 0-15 个参数使用**手动展开** `fn.call(scope, ...)` 调用
- 当参数数量超过 15 个时，使用 `fn.apply(scope, args)`（极少数情况）

### 5.3 一次性订阅映射 (`onceCallbackMap`)

- **[v3.0 更新]** `onceCallbackMap` 采用按事件分桶的结构：`{ eventName -> { originalComboUID -> wrappedComboUID } }`
  - 键为 `originalComboUID`（原始 callback+scope 的组合标识）
  - 值为 `wrappedComboUID`（包装后闭包+scope 的组合标识，即 `ids` 中实际存储的键）
- **ids 单键不变量**：`ids` 中每个数组槽位严格对应一个键（wrappedComboUID），不再存储 originalComboUID
  - 这保证了 swap-and-pop 交换时只需更新一个键，可以安全 `break`
  - 去重检查：`subscribe` 查 `ids` + `onceCallbackMap`；`subscribeOnce` 查 `ids` + `onceCallbackMap`
- `unsubscribe` 时通过 `onceCallbackMap[originalComboUID]` 查到 `wrappedComboUID`，再用后者去 `ids` 中定位数组槽位
- 退订后 `onceCallbackMap` 中对应条目被 `delete`，同一 (callback, scope) 可立即重新订阅

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

4. **异常处理（let-it-crash 策略）**
   - **[v2.2+]** `EventBus` 采用 let-it-crash 策略：回调中的异常**不会被捕获**，会直接向上抛出
   - 这意味着：如果某个回调抛出异常，后续回调将不会执行
   - 设计理由：移除 try/catch 可显著提升热路径性能；异常应在业务层明确处理，而非静默忽略
   - 建议在回调内部自行添加 try/catch 处理预期异常，避免影响其他订阅者

---

## 9. 运行时保证清单

### 保证项

| 保证项 | 说明 |
|--------|------|
| 订阅去重 | 同一 `(callback, scope)` 组合只能订阅一次同一事件，重复订阅返回 false |
| 多 scope 共存 | 同一 callback 绑定不同 scope 可以分别订阅同一事件 |
| 嵌套发布安全 | 回调中可以再次 `publish`，每层递归有独立栈 |
| 参数展开优化 | 0-15 参数使用 `fn.call(scope, ...)` 手动展开，避免 apply 开销 |
| eventName 验证 | null 或空字符串 eventName 被拒绝，不会导致内部状态异常 |
| 直接 scope 绑定 | [v3.0] subscribe 时的 scope 参数在 publish 时通过 `fn.call(scope)` 绑定，无需 Delegate 包装 |
| 零 arguments 特化 | [v3.0] `publish0/publish1/publish2` 不创建 arguments 对象 |

### 不保证项

| 不保证项 | 说明 |
|----------|------|
| 回调执行顺序 | [v3.0] 实际为确定性逆序（`while(i--)`），但契约不保证 |
| 异常隔离 | let-it-crash 策略：一个回调抛异常会中断后续回调 |
| 递归 destroy 安全 | 回调中调用 `destroy()` 会被拒绝并返回 false |

---

## 10. 总结

`EventBus` 通过**全局单例**、**回调池**和**手动参数展开**等多重优化，实现了高性能、低耦合的事件管理。它非常适合需要在模块间进行灵活通信的中大型 Flash/AS2 项目，尤其是需要处理**大规模事件**或**高频发布**的场景。

- 统一的事件调度，方便调试与维护
- 灵活的订阅形式（普通、一次性、无参数、多参数）
- 广泛的单元测试和性能测试验证
- 适合各类模块间的解耦消息传递

如需更进一步了解测试细节及性能数据，可参考配套的 `EventBusTest` 类。

---

## 11. 测试验证

运行 `EventBusTest` 类验证所有功能：

```actionscript
import org.flashNight.neur.Event.EventBusTest;
var eventBusTester:EventBusTest = new org.flashNight.neur.Event.EventBusTest();
```

测试覆盖：订阅/退订、一次性订阅、参数传递、let-it-crash、scope 去重、expandPool 边界修复等 60+ 项测试用例。


```output

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
[PASS] [v2.3 S1] scope deduplication - first subscribe should succeed
[PASS] [v2.3 S1] scope deduplication - second subscribe with different scope should succeed
[PASS] [v2.3 S1] scope deduplication - scope1 callback called
[PASS] [v2.3 S1] scope deduplication - scope2 callback called
[PASS] [v2.3 S1] scope deduplication - duplicate (same callback+scope) should fail
[PASS] [v2.3 S1] scope deduplication - no duplicate calls after rejected duplicate
[PASS] [v2.3 S1] scope deduplication - scope2 still called once
[PASS] [v2.3 S2] subscribe return - first subscribe returns true
[PASS] [v2.3 S2] subscribe return - duplicate subscribe returns false
[PASS] [v2.3 S2] subscribeOnce return - first subscribeOnce returns true
[PASS] [v2.3 S2] subscribeOnce return - duplicate subscribeOnce returns false
[PASS] [v2.3 I5] destroy return - first destroy returns true
[PASS] [v2.3 I5] destroy return - duplicate destroy returns false
[PASS] [v2.3.2] empty eventName - subscribe returns false
[PASS] [v2.3.2] null eventName - subscribe returns false
[PASS] [v2.3.2] empty eventName - subscribeOnce returns false
[PASS] [v2.3.2] empty eventName - unsubscribe returns false
[PASS] [v2.3.2] empty/null eventName - publish does not throw
[PASS] [v2.3.3] expandPool-fix - all 2048 callbacks called once
[PASS] [v2.3.3] expandPool-fix - no callbacks after unsubscribe (no slot corruption)
[PASS] [v2.3.3] forceReset-stacks - nested publish occurred
[PASS] [v2.3.3] forceReset-stacks - _dispatchDepth is 0 after reset
[PASS] [v2.3.3] forceReset-stacks - stack arrays cleared
[PASS] [v3.0] publish0 - zero-arg callback called
[PASS] [v3.0] publish1 - single-arg callback received correct value
[PASS] [v3.0] publish2 - dual-arg callback received correct values
[PASS] [v3.0] direct-scope - scopeA.received is true
[PASS] [v3.0] direct-scope - scopeB.received is true
[PASS] [v3.0] direct-scope - scopeA not called after unsubscribe
[PASS] [v3.0] direct-scope - scopeB still called
[PASS] [v3.0] swap-and-pop - middle element removed correctly
[PASS] [v3.0] swap-and-pop - first element removed correctly
[PASS] [v3.0] swap-and-pop - last element removed correctly
[PASS] [v3.0] swap-and-pop - event cleaned up after all unsubscribes
[PASS] [v3.0] once-resub - first subscribeOnce succeeds
[PASS] [v3.0] once-resub - unsubscribe before fire succeeds
[PASS] [v3.0] once-resub - re-subscribeOnce after unsubscribe succeeds
[PASS] [v3.0] once-resub - callback fires exactly once after re-subscribe
[PASS] [v3.0] once-resub - callback not fired again (once consumed)
[PASS] [v3.0] once-resub - normal subscribe after once consumed succeeds
[PASS] [v3.0] once-resub - normal subscribe fires correctly
[PASS] [v3.0] swap-once - A not called after removal
[PASS] [v3.0] swap-once - B fires on first publish
[PASS] [v3.0] swap-once - C(once) fires on first publish after being swapped
[PASS] [v3.0] swap-once - B fires on second publish
[PASS] [v3.0] swap-once - C(once) not fired again after auto-unsubscribe
[PASS] [v3.0] swap-once - C can re-subscribeOnce after consumed
[PASS] [v3.0] swap-once - event cleaned up after all unsubscribes
[PASS] [v2.2 P1-1] let-it-crash - error callback was called
[PASS] Test 7: EventBus handles high volume of subscriptions and publishes correctly
[PERFORMANCE] Test 7: EventBus High Volume Subscriptions and Publish took 156 ms
[PASS] Test 8: EventBus handles high frequency publishes correctly
[PERFORMANCE] Test 8: EventBus High Frequency Publish took 1181 ms
[PASS] Test 9: EventBus handles concurrent subscriptions and publishes correctly
[PERFORMANCE] Test 9: EventBus Concurrent Subscriptions and Publishes took 268 ms
[PASS] Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly
[PERFORMANCE] Test 10: EventBus Mixed Subscribe and Unsubscribe took 1077 ms
[PASS] Test 11: EventBus handles nested event publishes correctly
[PERFORMANCE] Test 11: EventBus Nested Event Publish took 0 ms
[PASS] Test 12: EventBus handles parallel event processing correctly
[PERFORMANCE] Test 12: EventBus Parallel Event Processing took 773 ms
[PASS] Test 13: EventBus handles long-running subscriptions and cleanups correctly
[PERFORMANCE] Test 13: EventBus Long Running Subscriptions and Cleanups took 54 ms
[PASS] Test 14: EventBus handles complex argument passing correctly
[PERFORMANCE] Test 14: EventBus Complex Argument Passing took 0 ms
[PASS] Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly
[PERFORMANCE] Test 15: EventBus Bulk Subscribe and Unsubscribe took 1641 ms
All tests completed.



```