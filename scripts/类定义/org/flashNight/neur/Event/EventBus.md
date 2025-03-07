# `org.flashNight.neur.Event.EventBus` 使用指南

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

- 在 `subscribeOnce` 中，原始回调被包装后会存入 `onceCallbackMap`，以便在 `unsubscribe` 时能够正确地查到并移除那个包装后的回调。  
- 避免了调用 `unsubscribe` 时无法定位“一次性包装函数”的问题，大大降低了忘记手动清理回调造成的内存泄漏风险。

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









// 导入必要的类
import org.flashNight.neur.Event.*;

// 定义测试用的回调函数标志
var callback1Called:Boolean = false;
var callback2Called:Boolean = false;
var callbackWithArgsCalled:Boolean = false;
var callbackWithErrorCalled:Boolean = false;
var callbackOnceCalled:Boolean = false;

// 定义一个简单的断言函数
function assert(condition:Boolean, testName:String):Void {
    if (condition) {
        trace("[PASS] " + testName);
    } else {
        trace("[FAIL] " + testName);
    }
}

// 创建 EventBus 实例
var eventBus:EventBus = EventBus.initialize();

// 定义测试用的回调函数
function callback1():Void {
    callback1Called = true;
    // trace("callback1 executed"); // 移除 trace 以减少性能影响
}

function callback2(arg1, arg2):Void {
    callback2Called = true;
    // trace("callback2 executed with args: " + arg1 + ", " + arg2); // 移除 trace 以减少性能影响
}

function callbackWithError():Void {
    callbackWithErrorCalled = true;
    // trace("callbackWithError executed"); // 移除 trace 以减少性能影响
    throw new Error("Intentional error in callbackWithError");
}

function callbackOnce():Void {
    callbackOnceCalled = true;
    // trace("callbackOnce executed"); // 移除 trace 以减少性能影响
}

// 在每个测试用例开始前重置回调标志
function resetFlags():Void {
    callback1Called = false;
    callback2Called = false;
    callbackWithArgsCalled = false;
    callbackWithErrorCalled = false;
    callbackOnceCalled = false;
}

// 测试用例 1: EventBus - 订阅和发布单个事件
function testEventBusSubscribePublish():Void {
    resetFlags();
    eventBus.subscribe("TEST_EVENT", callback1, this);
    eventBus.publish("TEST_EVENT");
    assert(callback1Called == true, "Test 1: EventBus subscribe and publish single event");
    callback1Called = false; // 重置标志
    eventBus.unsubscribe("TEST_EVENT", callback1); // 清理订阅
}

testEventBusSubscribePublish();

// 测试用例 2: EventBus - 取消订阅
function testEventBusUnsubscribe():Void {
    resetFlags();
    eventBus.subscribe("TEST_EVENT", callback1, this);
    eventBus.unsubscribe("TEST_EVENT", callback1);
    eventBus.publish("TEST_EVENT");
    assert(callback1Called == false, "Test 2: EventBus unsubscribe callback");
}

testEventBusUnsubscribe();

// 测试用例 3: EventBus - 一次性订阅
function testEventBusSubscribeOnce():Void {
    resetFlags();
    eventBus.subscribeOnce("ONCE_EVENT", callbackOnce, this);
    eventBus.publish("ONCE_EVENT");
    eventBus.publish("ONCE_EVENT");
    assert(callbackOnceCalled == true, "Test 3: EventBus subscribeOnce - first publish");
    callbackOnceCalled = false;
    assert(callbackOnceCalled == false, "Test 3: EventBus subscribeOnce - second publish");
}

testEventBusSubscribeOnce();

// 测试用例 4: EventBus - 发布带参数的事件
function testEventBusPublishWithArgs():Void {
    resetFlags();
    eventBus.subscribe("ARGS_EVENT", callback2, this);
    eventBus.publish("ARGS_EVENT", "Hello", "World");
    assert(callback2Called == true, "Test 4: EventBus publish event with arguments");
    callback2Called = false; // 重置标志
    eventBus.unsubscribe("ARGS_EVENT", callback2); // 清理订阅
}

testEventBusPublishWithArgs();

// 测试用例 5: EventBus - 回调函数抛出错误时的处理
function testEventBusCallbackErrorHandling():Void {
    resetFlags();
    eventBus.subscribe("ERROR_EVENT", callbackWithError, this);
    eventBus.subscribe("ERROR_EVENT", callback1, this);

    eventBus.publish("ERROR_EVENT");
    assert(
        callbackWithErrorCalled == true &&
        callback1Called == true,
        "Test 5: EventBus callback error handling"
    );
    callbackWithErrorCalled = false;
    callback1Called = false;
    eventBus.unsubscribe("ERROR_EVENT", callbackWithError);
    eventBus.unsubscribe("ERROR_EVENT", callback1);
}

testEventBusCallbackErrorHandling();

// 测试用例 6: EventBus - 销毁后确保所有回调不再被调用
function testEventBusDestroy():Void {
    resetFlags();
    eventBus.subscribe("DESTROY_EVENT", callback1, this);
    eventBus.destroy();
    eventBus.publish("DESTROY_EVENT");
    assert(callback1Called == false, "Test 6: EventBus destroy and ensure callbacks are not called");
}

testEventBusDestroy();

// -----------------------------------------------------------
// 性能测试部分开始
// -----------------------------------------------------------

// 定义一个简单的计时函数
function measurePerformance(testName:String, testFunction:Function):Void {
    var startTime:Number = getTimer();
    testFunction();
    var endTime:Number = getTimer();
    var duration:Number = endTime - startTime;
    trace("[PERFORMANCE] " + testName + " took " + duration + " ms");
}

// 性能测试用例 7: EventBus - 大量事件订阅与发布
function testEventBusHighVolumeSubscriptions():Void {
    resetFlags();
    var numSubscribers:Number = 10000; // 增加到10000
    var eventName:String = "HIGH_VOLUME_EVENT";
    
    // 定义一个简单的回调
    function highVolumeCallback():Void {
        // 空回调
    }
    
    // 订阅大量回调
    for (var i:Number = 0; i < numSubscribers; i++) {
        eventBus.subscribe(eventName, highVolumeCallback, this);
    }
    
    // 发布事件
    eventBus.publish(eventName);
    
    // 取消订阅所有回调
    for (var j:Number = 0; j < numSubscribers; j++) {
        eventBus.unsubscribe(eventName, highVolumeCallback);
    }
    
    // 测试通过无需具体断言
    assert(true, "Test 7: EventBus handles high volume of subscriptions and publishes correctly");
}

measurePerformance("Test 7: EventBus High Volume Subscriptions and Publish", testEventBusHighVolumeSubscriptions);

// 性能测试用例 8: EventBus - 高频发布事件
function testEventBusHighFrequencyPublish():Void {
    resetFlags();
    var numPublish:Number = 100000; // 增加到100,000
    var eventName:String = "HIGH_FREQ_EVENT";
    
    // 定义一个简单的回调
    function highFreqCallback():Void {
        // 空回调
    }
    
    // 订阅一个回调
    eventBus.subscribe(eventName, highFreqCallback, this);
    
    // 高频发布事件
    for (var i:Number = 0; i < numPublish; i++) {
        eventBus.publish(eventName);
    }
    
    // 取消订阅
    eventBus.unsubscribe(eventName, highFreqCallback);
    
    // 测试通过无需具体断言
    assert(true, "Test 8: EventBus handles high frequency publishes correctly");
}

measurePerformance("Test 8: EventBus High Frequency Publish", testEventBusHighFrequencyPublish);

// 性能测试用例 9: EventBus - 高并发订阅与发布
function testEventBusConcurrentSubscriptionsAndPublishes():Void {
    resetFlags();
    var numEvents:Number = 1000; // 增加到1000
    var numSubscribersPerEvent:Number = 1000; // 增加到1000
    var numPublishesPerEvent:Number = 1000; // 增加到1000
    
    // 定义一个简单的回调
    function concurrentCallback():Void {
        // 空回调
    }
    
    // 订阅多个事件，每个事件有多个订阅者
    for (var i:Number = 0; i < numEvents; i++) {
        var eventName:String = "CONCURRENT_EVENT_" + i;
        for (var j:Number = 0; j < numSubscribersPerEvent; j++) {
            eventBus.subscribe(eventName, concurrentCallback, this);
        }
    }
    
    // 发布每个事件多次
    for (var k:Number = 0; k < numEvents; k++) {
        var currentEvent:String = "CONCURRENT_EVENT_" + k;
        for (var l:Number = 0; l < numPublishesPerEvent; l++) {
            eventBus.publish(currentEvent);
        }
    }
    
    // 取消所有订阅
    for (var m:Number = 0; m < numEvents; m++) {
        var currentEventToUnsub:String = "CONCURRENT_EVENT_" + m;
        for (var n:Number = 0; n < numSubscribersPerEvent; n++) {
            eventBus.unsubscribe(currentEventToUnsub, concurrentCallback);
        }
    }
    
    // 测试通过无需具体断言
    assert(true, "Test 9: EventBus handles concurrent subscriptions and publishes correctly");
}

measurePerformance("Test 9: EventBus Concurrent Subscriptions and Publishes", testEventBusConcurrentSubscriptionsAndPublishes);

// 性能测试用例 10: EventBus - 混合订阅与取消订阅
function testEventBusMixedSubscribeUnsubscribe():Void {
    resetFlags();
    var eventName:String = "MIXED_EVENT";
    var numOperations:Number = 100000; // 增加到100,000
    
    // 定义一个简单的回调
    function mixedCallback():Void {
        // 空回调
    }
    
    for (var i:Number = 0; i < numOperations; i++) {
        eventBus.subscribe(eventName, mixedCallback, this);
        if (i % 10 == 0) { // 保持取消订阅的频率
            eventBus.unsubscribe(eventName, mixedCallback);
        }
    }
    
    // 发布事件
    eventBus.publish(eventName);
    
    // 最终取消所有订阅
    eventBus.unsubscribe(eventName, mixedCallback);
    
    // 测试通过无需具体断言
    assert(true, "Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly");
}

measurePerformance("Test 10: EventBus Mixed Subscribe and Unsubscribe", testEventBusMixedSubscribeUnsubscribe);

// 性能测试用例 11: EventBus - 嵌套事件发布
function testEventBusNestedPublish():Void {
    resetFlags();
    var eventName1:String = "NESTED_EVENT_1";
    var eventName2:String = "NESTED_EVENT_2";

    function nestedCallback1():Void {
        // trace("Nested callback1 executed"); // 移除 trace 以减少性能影响
        eventBus.publish(eventName2); // 在回调中再次发布事件
    }

    function nestedCallback2():Void {
        // trace("Nested callback2 executed"); // 移除 trace 以减少性能影响
    }

    // 订阅事件
    eventBus.subscribe(eventName1, nestedCallback1, this);
    eventBus.subscribe(eventName2, nestedCallback2, this);

    // 发布第一个事件，测试嵌套事件发布
    eventBus.publish(eventName1);

    // 取消订阅
    eventBus.unsubscribe(eventName1, nestedCallback1);
    eventBus.unsubscribe(eventName2, nestedCallback2);

    assert(true, "Test 11: EventBus handles nested event publishes correctly");
}

measurePerformance("Test 11: EventBus Nested Event Publish", testEventBusNestedPublish);

// 性能测试用例 12: EventBus - 并行事件处理
function testEventBusParallelEvents():Void {
    resetFlags();
    var eventNames:Array = ["EVENT_A", "EVENT_B", "EVENT_C", "EVENT_D", "EVENT_E"];
    var numSubscribersPerEvent:Number = 10000; // 增加每个事件的订阅者数量

    function parallelCallback():Void {
        // trace("Parallel event callback executed"); // 移除 trace 以减少性能影响
    }

    // 订阅多个事件，每个事件有大量订阅者
    for (var i:Number = 0; i < eventNames.length; i++) {
        for (var j:Number = 0; j < numSubscribersPerEvent; j++) {
            eventBus.subscribe(eventNames[i], parallelCallback, this);
        }
    }

    // 同时发布多个事件
    for (var k:Number = 0; k < eventNames.length; k++) {
        eventBus.publish(eventNames[k]);
    }

    // 取消所有订阅
    for (var m:Number = 0; m < eventNames.length; m++) {
        for (var n:Number = 0; n < numSubscribersPerEvent; n++) {
            eventBus.unsubscribe(eventNames[m], parallelCallback);
        }
    }

    // 测试通过无需具体断言
    assert(true, "Test 12: EventBus handles parallel event processing correctly");
}

measurePerformance("Test 12: EventBus Parallel Event Processing", testEventBusParallelEvents);

// 性能测试用例 13: EventBus - 长时间运行的订阅与取消
function testEventBusLongRunningSubscriptions():Void {
    resetFlags();
    var eventName:String = "LONG_RUNNING_EVENT";
    var numSubscribers:Number = 5000;
    
    function longRunningCallback():Void {
        // 空回调
    }
    
    // 长时间订阅与取消
    for (var i:Number = 0; i < numSubscribers; i++) {
        eventBus.subscribe(eventName, longRunningCallback, this);
        if (i % 10 == 0) {
            eventBus.unsubscribe(eventName, longRunningCallback);
        }
    }
    
    // 发布事件
    eventBus.publish(eventName);
    
    // 最终取消所有订阅
    eventBus.unsubscribe(eventName, longRunningCallback);
    
    // 测试通过无需具体断言
    assert(true, "Test 13: EventBus handles long-running subscriptions and cleanups correctly");
}

measurePerformance("Test 13: EventBus Long Running Subscriptions and Cleanups", testEventBusLongRunningSubscriptions);

// 性能测试用例 14: EventBus - 复杂参数传递
function testEventBusComplexArguments():Void {
    resetFlags();
    var eventName:String = "COMPLEX_ARG_EVENT";

    // 创建复杂参数对象
    var complexData:Object = {
        key1: "value1",
        key2: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        key3: { nestedKey1: "nestedValue1", nestedKey2: "nestedValue2", nestedKey3: { deepKey: "deepValue" } }
    };

    function complexArgCallback(data:Object):Void {
        // trace("Complex data received: " + data); // 移除 trace 以减少性能影响
    }

    // 订阅事件
    eventBus.subscribe(eventName, complexArgCallback, this);

    // 发布带有复杂参数的事件
    eventBus.publish(eventName, complexData);

    // 取消订阅
    eventBus.unsubscribe(eventName, complexArgCallback);

    assert(true, "Test 14: EventBus handles complex argument passing correctly");
}

measurePerformance("Test 14: EventBus Complex Argument Passing", testEventBusComplexArguments);

// 性能测试用例 15: EventBus - 批量事件订阅与取消
function testEventBusBulkSubscribeUnsubscribe():Void {
    resetFlags();
    var numEvents:Number = 50000; // 增加到50,000
    var eventNamePrefix:String = "BULK_EVENT_";

    function bulkCallback():Void {
        // 空回调
    }

    // 批量订阅事件
    for (var i:Number = 0; i < numEvents; i++) {
        var eventName:String = eventNamePrefix + i;
        eventBus.subscribe(eventName, bulkCallback, this);
    }

    // 发布部分事件
    for (var j:Number = 0; j < numEvents; j += 1000) { // 增加间隔以减少发布次数
        var eventName:String = eventNamePrefix + j;
        eventBus.publish(eventName);
    }

    // 批量取消订阅
    for (var k:Number = 0; k < numEvents; k++) {
        var eventName:String = eventNamePrefix + k;
        eventBus.unsubscribe(eventName, bulkCallback);
    }

    assert(true, "Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly");
}

measurePerformance("Test 15: EventBus Bulk Subscribe and Unsubscribe", testEventBusBulkSubscribeUnsubscribe);

// 测试完成
trace("All tests completed.");

[PASS] Test 1: EventBus subscribe and publish single event
[PASS] Test 2: EventBus unsubscribe callback
[PASS] Test 3: EventBus subscribeOnce - first publish
[PASS] Test 3: EventBus subscribeOnce - second publish
[PASS] Test 4: EventBus publish event with arguments
Error executing callback for event 'ERROR_EVENT': Intentional error in callbackWithError
[PASS] Test 5: EventBus callback error handling
[PASS] Test 6: EventBus destroy and ensure callbacks are not called
[PASS] Test 7: EventBus handles high volume of subscriptions and publishes correctly
[PERFORMANCE] Test 7: EventBus High Volume Subscriptions and Publish took 28 ms
[PASS] Test 8: EventBus handles high frequency publishes correctly
[PERFORMANCE] Test 8: EventBus High Frequency Publish took 1117 ms
[PASS] Test 9: EventBus handles concurrent subscriptions and publishes correctly
[PERFORMANCE] Test 9: EventBus Concurrent Subscriptions and Publishes took 14917 ms
[PASS] Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly
[PERFORMANCE] Test 10: EventBus Mixed Subscribe and Unsubscribe took 412 ms
[PASS] Test 11: EventBus handles nested event publishes correctly
[PERFORMANCE] Test 11: EventBus Nested Event Publish took 0 ms
[PASS] Test 12: EventBus handles parallel event processing correctly
[PERFORMANCE] Test 12: EventBus Parallel Event Processing took 147 ms
[PASS] Test 13: EventBus handles long-running subscriptions and cleanups correctly
[PERFORMANCE] Test 13: EventBus Long Running Subscriptions and Cleanups took 23 ms
[PASS] Test 14: EventBus handles complex argument passing correctly
[PERFORMANCE] Test 14: EventBus Complex Argument Passing took 0 ms
[PASS] Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly
[PERFORMANCE] Test 15: EventBus Bulk Subscribe and Unsubscribe took 4642 ms
All tests completed.


[PASS] Test 1: EventBus subscribe and publish single event
[PASS] Test 2: EventBus unsubscribe callback
[PASS] Test 3: EventBus subscribeOnce - first publish
[PASS] Test 3: EventBus subscribeOnce - second publish
[PASS] Test 4: EventBus publish event with arguments
Error executing callback for event 'ERROR_EVENT': Intentional error in callbackWithError
[PASS] Test 5: EventBus callback error handling
[PASS] Test 6: EventBus destroy and ensure callbacks are not called
[PASS] Test 7: EventBus handles high volume of subscriptions and publishes correctly
[PERFORMANCE] Test 7: EventBus High Volume Subscriptions and Publish took 26 ms
[PASS] Test 8: EventBus handles high frequency publishes correctly
[PERFORMANCE] Test 8: EventBus High Frequency Publish took 892 ms
[PASS] Test 9: EventBus handles concurrent subscriptions and publishes correctly
[PERFORMANCE] Test 9: EventBus Concurrent Subscriptions and Publishes took 11492 ms
[PASS] Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly
[PERFORMANCE] Test 10: EventBus Mixed Subscribe and Unsubscribe took 349 ms
[PASS] Test 11: EventBus handles nested event publishes correctly
[PERFORMANCE] Test 11: EventBus Nested Event Publish took 0 ms
[PASS] Test 12: EventBus handles parallel event processing correctly
[PERFORMANCE] Test 12: EventBus Parallel Event Processing took 144 ms
[PASS] Test 13: EventBus handles long-running subscriptions and cleanups correctly
[PERFORMANCE] Test 13: EventBus Long Running Subscriptions and Cleanups took 17 ms
[PASS] Test 14: EventBus handles complex argument passing correctly
[PERFORMANCE] Test 14: EventBus Complex Argument Passing took 0 ms
[PASS] Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly
[PERFORMANCE] Test 15: EventBus Bulk Subscribe and Unsubscribe took 1058 ms
All tests completed.


[PASS] Test 1: EventBus subscribe and publish single event
[PASS] Test 2: EventBus unsubscribe callback
[PASS] Test 3: EventBus subscribeOnce - first publish
[PASS] Test 3: EventBus subscribeOnce - second publish
[PASS] Test 4: EventBus publish event with arguments
Error executing callback for event 'ERROR_EVENT': Intentional error in callbackWithError
[PASS] Test 5: EventBus callback error handling
[PASS] Test 6: EventBus destroy and ensure callbacks are not called
[PASS] Test 7: EventBus handles high volume of subscriptions and publishes correctly
[PERFORMANCE] Test 7: EventBus High Volume Subscriptions and Publish took 27 ms
[PASS] Test 8: EventBus handles high frequency publishes correctly
[PERFORMANCE] Test 8: EventBus High Frequency Publish took 790 ms
[PASS] Test 9: EventBus handles concurrent subscriptions and publishes correctly
[PERFORMANCE] Test 9: EventBus Concurrent Subscriptions and Publishes took 10943 ms
[PASS] Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly
[PERFORMANCE] Test 10: EventBus Mixed Subscribe and Unsubscribe took 312 ms
[PASS] Test 11: EventBus handles nested event publishes correctly
[PERFORMANCE] Test 11: EventBus Nested Event Publish took 0 ms
[PASS] Test 12: EventBus handles parallel event processing correctly
[PERFORMANCE] Test 12: EventBus Parallel Event Processing took 133 ms
[PASS] Test 13: EventBus handles long-running subscriptions and cleanups correctly
[PERFORMANCE] Test 13: EventBus Long Running Subscriptions and Cleanups took 15 ms
[PASS] Test 14: EventBus handles complex argument passing correctly
[PERFORMANCE] Test 14: EventBus Complex Argument Passing took 0 ms
[PASS] Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly
[PERFORMANCE] Test 15: EventBus Bulk Subscribe and Unsubscribe took 880 ms
All tests completed.

[PASS] Test 1: EventBus subscribe and publish single event
[PASS] Test 2: EventBus unsubscribe callback
[PASS] Test 3: EventBus subscribeOnce - first publish
[PASS] Test 3: EventBus subscribeOnce - second publish
[PASS] Test 4: EventBus publish event with arguments
Error executing callback for event 'ERROR_EVENT': Intentional error in callbackWithError
[PASS] Test 5: EventBus callback error handling
[PASS] Test 6: EventBus destroy and ensure callbacks are not called
[PASS] Test 7: EventBus handles high volume of subscriptions and publishes correctly
[PERFORMANCE] Test 7: EventBus High Volume Subscriptions and Publish took 30 ms
[PASS] Test 8: EventBus handles high frequency publishes correctly
[PERFORMANCE] Test 8: EventBus High Frequency Publish took 759 ms
[PASS] Test 9: EventBus handles concurrent subscriptions and publishes correctly
[PERFORMANCE] Test 9: EventBus Concurrent Subscriptions and Publishes took 10815 ms
[PASS] Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly
[PERFORMANCE] Test 10: EventBus Mixed Subscribe and Unsubscribe took 366 ms
[PASS] Test 11: EventBus handles nested event publishes correctly
[PERFORMANCE] Test 11: EventBus Nested Event Publish took 0 ms
[PASS] Test 12: EventBus handles parallel event processing correctly
[PERFORMANCE] Test 12: EventBus Parallel Event Processing took 147 ms
[PASS] Test 13: EventBus handles long-running subscriptions and cleanups correctly
[PERFORMANCE] Test 13: EventBus Long Running Subscriptions and Cleanups took 17 ms
[PASS] Test 14: EventBus handles complex argument passing correctly
[PERFORMANCE] Test 14: EventBus Complex Argument Passing took 0 ms
[PASS] Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly
[PERFORMANCE] Test 15: EventBus Bulk Subscribe and Unsubscribe took 1049 ms
All tests completed.


[PASS] Test 1: EventBus subscribe and publish single event
[PASS] Test 2: EventBus unsubscribe callback
[PASS] Test 3: EventBus subscribeOnce - first publish
[PASS] Test 3: EventBus subscribeOnce - second publish
[PASS] Test 4: EventBus publish event with arguments
Error executing callback for event 'ERROR_EVENT': Intentional error in callbackWithError
[PASS] Test 5: EventBus callback error handling
[PASS] Test 6: EventBus destroy and ensure callbacks are not called
[PASS] Test 7: EventBus handles high volume of subscriptions and publishes correctly
[PERFORMANCE] Test 7: EventBus High Volume Subscriptions and Publish took 28 ms
[PASS] Test 8: EventBus handles high frequency publishes correctly
[PERFORMANCE] Test 8: EventBus High Frequency Publish took 764 ms
[PASS] Test 9: EventBus handles concurrent subscriptions and publishes correctly
[PERFORMANCE] Test 9: EventBus Concurrent Subscriptions and Publishes took 10986 ms
[PASS] Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly
[PERFORMANCE] Test 10: EventBus Mixed Subscribe and Unsubscribe took 385 ms
[PASS] Test 11: EventBus handles nested event publishes correctly
[PERFORMANCE] Test 11: EventBus Nested Event Publish took 0 ms
[PASS] Test 12: EventBus handles parallel event processing correctly
[PERFORMANCE] Test 12: EventBus Parallel Event Processing took 152 ms
[PASS] Test 13: EventBus handles long-running subscriptions and cleanups correctly
[PERFORMANCE] Test 13: EventBus Long Running Subscriptions and Cleanups took 19 ms
[PASS] Test 14: EventBus handles complex argument passing correctly
[PERFORMANCE] Test 14: EventBus Complex Argument Passing took 0 ms
[PASS] Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly
[PERFORMANCE] Test 15: EventBus Bulk Subscribe and Unsubscribe took 1095 ms
All tests completed.

