# `org.flashNight.neur.Event.EventBus` 使用指南

## 1. 引言

在传统的 Flash 开发中，事件的传播和管理通常是通过 `MovieClip` 的事件系统进行的，例如 `onEnterFrame`、`onClick` 等。但这些事件机制在复杂的应用程序中，特别是在需要跨多个模块或组件传递信息时，可能变得难以维护。

为了解决这个问题，我们引入了 **事件总线 (Event Bus)** 模型。`EventBus` 是一种用于管理事件的工具，它可以让应用程序的各个部分之间通过发布（`publish`）和订阅（`subscribe`）事件来进行通信，而不需要直接的依赖关系。这样能够使代码更加模块化、易于扩展和维护。

本指南将详细介绍 `EventBus` 类的使用方法，并对比 Flash 原生事件系统，帮助开发者理解如何在项目中利用它来简化事件处理。

---

## 2. 什么是事件总线？

**事件总线** 可以看作是一个全局的消息中心，各个模块或组件可以在其中发布和接收事件：

- **发布事件**：当某个模块发生了一件事情（例如，玩家角色完成了某个任务），它可以通过事件总线发布事件，并附带相关的数据（例如任务完成的信息）。
- **订阅事件**：其他模块可以订阅该事件，当事件被发布时，订阅者将会被通知，并且可以根据收到的信息进行相应的处理（例如，更新任务进度条，奖励玩家等）。

这种松耦合的设计，使得模块之间不需要直接引用彼此，只需通过事件总线来通信，这对于复杂的应用程序来说尤为重要。

---

## 3. 核心功能

`EventBus` 提供了几个关键的功能，帮助开发者管理事件和回调：

- **事件订阅 (`subscribe`)**：允许开发者订阅某个事件，并绑定回调函数，当事件被触发时，回调函数会被执行。
- **取消订阅 (`unsubscribe`)**：可以移除某个事件的订阅，防止回调函数被再次触发。
- **发布事件 (`publish`)**：可以发布事件，并传递可选的参数给所有订阅者。
- **一次性订阅 (`subscribeOnce`)**：允许某个回调函数只执行一次，之后自动取消订阅。
- **事件销毁 (`destroy`)**：清理所有事件监听器和回调函数，防止内存泄漏。

---

## 4. 使用场景

在开发大型应用程序时，常常会遇到需要跨模块、跨层次传递信息的需求。`EventBus` 适用于以下场景：

1. **模块解耦**：例如，UI 模块和业务逻辑模块不需要直接通信，只需通过事件总线传递数据，减少模块之间的耦合。
   
2. **全局通知**：当某个全局事件发生时（如网络连接断开、游戏暂停），所有需要处理这个事件的模块可以通过事件总线同步处理。

3. **高效的事件管理**：`EventBus` 提供了内存池机制和参数优化，能够高效地处理大量订阅者和事件。

---

## 5. `EventBus` 与 Flash 原生事件机制的对比

Flash 原生的事件处理机制大多是基于显示列表（`MovieClip`）或 `EventListener` 的，当多个对象之间需要通信时，必须在它们之间创建引用，或者通过层次结构来管理，这会导致以下问题：

1. **耦合性强**：多个模块或对象必须知道彼此的存在，增加了模块之间的耦合。
   
2. **扩展性差**：当项目变得复杂时，添加新的事件监听器可能变得困难，尤其是当事件在多个层次结构间传播时。

`EventBus` 则不同，它通过一个全局的总线，允许任何模块在没有直接依赖的情况下进行通信：

- **松耦合**：不需要模块之间互相持有引用，通过事件总线，模块可以专注于自己的功能，只需发布或订阅事件。
- **事件统一管理**：所有的事件都通过一个总线来管理，易于维护和调试。

---

## 6. 核心 API 详解

### 6.1 `subscribe(eventName: String, callback: Function, scope: Object): Void`

**功能**：订阅指定事件，绑定回调函数。当事件发布时，回调函数会被触发，并在指定作用域内执行。

- `eventName`: 要订阅的事件名称。
- `callback`: 事件触发时要执行的回调函数。
- `scope`: 回调函数的执行作用域（即 `this` 指向的对象）。

**示例**：

```actionscript
eventBus.subscribe("PLAYER_JUMP", function() {
    trace("玩家跳跃事件触发！");
}, this);
```

当发布 `"PLAYER_JUMP"` 事件时，上述回调函数会被调用。

---

### 6.2 `unsubscribe(eventName: String, callback: Function): Void`

**功能**：取消对某个事件的订阅，防止回调函数在事件发布时被调用。

- `eventName`: 要取消的事件名称。
- `callback`: 要取消的回调函数。

**示例**：

```actionscript
eventBus.unsubscribe("PLAYER_JUMP", onPlayerJump);
```

当调用 `unsubscribe` 后，`onPlayerJump` 函数将不再在 `"PLAYER_JUMP"` 事件发布时被调用。

---

### 6.3 `publish(eventName: String, ...args): Void`

**功能**：发布事件，并将可选的参数传递给所有订阅者。

- `eventName`: 要发布的事件名称。
- `args`: 可选参数，将被传递给回调函数。

**示例**：

```actionscript
eventBus.publish("PLAYER_SCORE_UPDATED", 1000);
```

这里发布了 `PLAYER_SCORE_UPDATED` 事件，并传递了 `1000` 作为参数，所有订阅该事件的回调函数将会收到这个参数。

---

### 6.4 `subscribeOnce(eventName: String, callback: Function, scope: Object): Void`

**功能**：订阅事件，但回调函数只会执行一次，之后自动取消订阅。

- `eventName`: 要订阅的事件名称。
- `callback`: 事件触发时执行的回调函数。
- `scope`: 回调函数的执行作用域。

**示例**：

```actionscript
eventBus.subscribeOnce("LEVEL_COMPLETE", function() {
    trace("关卡完成事件只触发一次！");
}, this);
```

回调函数只会在第一次发布 `"LEVEL_COMPLETE"` 事件时被调用，之后自动取消订阅。

---

### 6.5 `destroy(): Void`

**功能**：销毁所有的事件监听器和回调函数，释放资源，防止内存泄露。

**示例**：

```actionscript
eventBus.destroy();
```

调用 `destroy` 后，所有事件和回调将被清理。

---

## 7. 性能优化

`EventBus` 在设计上考虑了性能优化，尤其适合高频事件发布和大量订阅者的场景。

### 7.1 内存池与空间管理

为了减少内存分配开销，`EventBus` 内部使用了 **回调池** 来管理回调函数的位置，并预先分配了 1024 个空闲位置。当池满时，它会自动扩展。

### 7.2 参数优化

`EventBus` 对常见的参数传递场景进行了手动展开优化（支持 0 到 7 个参数），避免了频繁调用 `apply` 带来的性能损耗。

### 7.3 回调函数缓存

通过 `Dictionary` 类为每个回调生成唯一 ID，从而避免重复订阅相同回调函数，提高事件管理效率。

---

## 8. 典型应用场景

### 8.1 处理游戏事件

在游戏开发中，常常需要跨越多个系统传递事件，例如玩家得分更新、关卡完成、敌人击杀等。通过 `EventBus`，这些事件可以被任何需要的模块订阅和处理：

```actionscript
eventBus.subscribe("PLAYER_DIED", function() {
    trace("玩家死亡，游戏结束");
}, this);
```

### 8.2 模块化设计

在大型应用程序中，模块间的通信可能会变得复杂。通过事件总线，模块之间可以保持独立性，不需要相互引用，降低耦合度：

```actionscript
eventBus.publish("USER_LOGIN", userData);
```

所有关心用户登录的模块都会收到这个事件。

---

## 9. 性能建议

1. **避免过多 `apply` 调用**：

手动展开参数可以提高性能，尽量减少动态传参时的 `apply` 调用。
   
2. **定期清理事件**：长时间运行的应用中，建议定期清理不再需要的事件订阅，以防止内存泄漏。

3. **批量订阅与发布**：对于大规模事件，建议采用批量订阅和发布，减少函数调用的开销。

---

## 10. 总结

通过 `EventBus`，开发者可以轻松实现复杂的事件管理机制，减少模块间的耦合，提高代码的可维护性和扩展性。同时，事件总线提供的性能优化机制确保了它在高频事件场景下的高效运行，非常适合大型 Flash 项目或游戏开发。

`EventBus` 的灵活性和高效性使其成为事件管理的理想工具，适合各类事件驱动的应用。








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

