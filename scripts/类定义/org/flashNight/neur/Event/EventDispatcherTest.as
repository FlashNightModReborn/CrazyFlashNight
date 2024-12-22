import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;
import flash.utils.getTimer;

/**
 * EventDispatcherTest 类用于全面测试 EventDispatcher 的功能和性能。
 * 它包含多个测试方法，使用自定义的断言机制验证各个方法的正确性。
 * 通过运行所有测试方法，可以确保 EventDispatcher 的实现符合预期。
 */
class org.flashNight.neur.Event.EventDispatcherTest {
    private var dispatcher:EventDispatcher; // 待测试的 EventDispatcher 实例
    private var testResults:Array;           // 存储测试结果信息

    /**
     * 构造函数：初始化测试类，创建 EventDispatcher 实例和结果存储数组。
     */
    public function EventDispatcherTest() {
        this.dispatcher = new EventDispatcher();
        this.testResults = [];
    }

    /**
     * 运行所有测试方法。
     */
    public function runAllTests():Void {
        trace("=== EventDispatcherTest 开始 ===");
        this.testSubscribe();
        this.testPublish();
        this.testSubscribeOnce();
        this.testUnsubscribe();
        this.testDestroy();
        this.testNoSubscribers();
        this.testDifferentScopes();
        this.testDuplicateSubscriptions();
        this.testModifySubscriptionsDuringDispatch();
        this.testCallbackExceptionHandling();
        this.testMultipleDispatchers();
        this.testSubscribeOnceWithUnsubscribe();
        this.testMemoryLeakDetection();
        this.testPerformance();
        this.reportResults();
        trace("=== EventDispatcherTest 结束 ===");
    }

    /**
     * 自定义断言方法，用于验证条件是否为真。
     * 如果条件不满足，则记录失败信息。
     * 
     * @param condition 要验证的条件
     * @param message 失败时输出的消息
     */
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            this.testResults.push({ success: false, message: message });
            trace("Assertion Failed: " + message);
        } else {
            this.testResults.push({ success: true, message: message });
            trace("Assertion Passed: " + message);
        }
    }

    /**
     * 测试 subscribe 方法的正确性。
     */
    private function testSubscribe():Void {
        trace("--- 测试 subscribe 方法 ---");
        var eventName:String = "testEvent";
        var callbackCalled:Boolean = false;
        var testCallback:Function = function() {
            callbackCalled = true;
        };
        var scope:Object = this;

        // 订阅事件
        this.dispatcher.subscribe(eventName, testCallback, scope);

        // 发布事件
        this.dispatcher.publish(eventName);

        // 断言回调被调用
        this.assert(callbackCalled, "subscribe: Callback should be called upon event publish.");

        // 重置标志
        callbackCalled = false;

        // 订阅同一事件再次发布
        this.dispatcher.publish(eventName);
        this.assert(callbackCalled, "subscribe: Callback should be called on subsequent event publish.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback);
    }

    /**
     * 测试 publish 方法的正确性，特别是参数传递。
     */
    private function testPublish():Void {
        trace("--- 测试 publish 方法 ---");
        var eventName:String = "paramEvent";
        var receivedParams:Array = [];
        var testCallback:Function = function(a, b, c) {
            receivedParams.push(a, b, c);
        };
        var scope:Object = this;

        // 订阅事件
        this.dispatcher.subscribe(eventName, testCallback, scope);

        // 发布事件并传递参数
        this.dispatcher.publish(eventName, 1, "two", { three: 3 });

        // 断言参数正确接收
        this.assert(receivedParams.length === 3, "publish: Should receive three parameters.");
        this.assert(receivedParams[0] === 1, "publish: First parameter should be 1.");
        this.assert(receivedParams[1] === "two", "publish: Second parameter should be 'two'.");
        this.assert(receivedParams[2].three === 3, "publish: Third parameter should be an object with three=3.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback);
    }

    /**
     * 测试 subscribeOnce 方法的正确性。
     */
    private function testSubscribeOnce():Void {
        trace("--- 测试 subscribeOnce 方法 ---");
        var eventName:String = "onceEvent";
        var callCount:Number = 0;
        var testCallback:Function = function() {
            callCount++;
        };
        var scope:Object = this;

        // 一次性订阅事件
        this.dispatcher.subscribeOnce(eventName, testCallback, scope);

        // 发布事件第一次
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "subscribeOnce: Callback should be called once.");

        // 发布事件第二次
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "subscribeOnce: Callback should not be called a second time.");
    }

    /**
     * 测试 unsubscribe 方法的正确性。
     */
    private function testUnsubscribe():Void {
        trace("--- 测试 unsubscribe 方法 ---");
        var eventName:String = "unsubscribeEvent";
        var callCount:Number = 0;
        var testCallback:Function = function() {
            callCount++;
        };
        var scope:Object = this;

        // 订阅事件
        this.dispatcher.subscribe(eventName, testCallback, scope);

        // 发布事件
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "unsubscribe: Callback should be called once before unsubscribe.");

        // 取消订阅
        this.dispatcher.unsubscribe(eventName, testCallback);

        // 发布事件再次
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "unsubscribe: Callback should not be called after unsubscribe.");
    }

    /**
     * 测试 destroy 方法的正确性，确保所有订阅被取消。
     */
    private function testDestroy():Void {
        trace("--- 测试 destroy 方法 ---");
        var eventName1:String = "destroyEvent1";
        var eventName2:String = "destroyEvent2";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var testCallback1:Function = function() {
            callCount1++;
        };
        var testCallback2:Function = function() {
            callCount2++;
        };
        var scope:Object = this;

        // 订阅多个事件
        this.dispatcher.subscribe(eventName1, testCallback1, scope);
        this.dispatcher.subscribe(eventName2, testCallback2, scope);

        // 发布事件
        this.dispatcher.publish(eventName1);
        this.dispatcher.publish(eventName2);
        this.assert(callCount1 === 1, "destroy: Callback1 should be called once before destroy.");
        this.assert(callCount2 === 1, "destroy: Callback2 should be called once before destroy.");

        // 调用 destroy
        this.dispatcher.destroy();

        // 发布事件再次
        this.dispatcher.publish(eventName1);
        this.dispatcher.publish(eventName2);
        this.assert(callCount1 === 1, "destroy: Callback1 should not be called after destroy.");
        this.assert(callCount2 === 1, "destroy: Callback2 should not be called after destroy.");
    }

    /**
     * 测试发布没有订阅者的事件，确保不会抛出错误或异常。
     */
    private function testNoSubscribers():Void {
        trace("--- 测试发布没有订阅者的事件 ---");
        var eventName:String = "noSubscriberEvent";
        try {
            this.dispatcher.publish(eventName);
            this.assert(true, "noSubscribers: Publishing event with no subscribers should not throw an error.");
        } catch (error:Error) {
            this.assert(false, "noSubscribers: Publishing event with no subscribers threw an error.");
        }
    }

    /**
     * 测试不同作用域下回调函数的执行情况。
     */
    private function testDifferentScopes():Void {
        trace("--- 测试不同作用域的回调执行 ---");
        var eventName:String = "scopeEvent";
        var testObject1:Object = { value: 0 };
        var testObject2:Object = { value: 0 };

        var testCallback1:Function = function() {
            this.value += 1;
        };
        var testCallback2:Function = function() {
            this.value += 2;
        };

        // 订阅事件，使用不同的作用域
        this.dispatcher.subscribe(eventName, testCallback1, testObject1);
        this.dispatcher.subscribe(eventName, testCallback2, testObject2);

        // 发布事件
        this.dispatcher.publish(eventName);

        // 断言不同作用域下的值是否正确
        this.assert(testObject1.value === 1, "differentScopes: Callback1 should increment testObject1.value by 1.");
        this.assert(testObject2.value === 2, "differentScopes: Callback2 should increment testObject2.value by 2.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback1);
        this.dispatcher.unsubscribe(eventName, testCallback2);
    }

    /**
     * 测试重复订阅同一回调函数，确保不会导致多次执行。
     */
    private function testDuplicateSubscriptions():Void {
        trace("--- 测试重复订阅同一回调函数 ---");
        var eventName:String = "duplicateEvent";
        var callCount:Number = 0;
        var testCallback:Function = function() {
            callCount++;
        };
        var scope:Object = this;

        // 订阅同一事件多次
        this.dispatcher.subscribe(eventName, testCallback, scope);
        this.dispatcher.subscribe(eventName, testCallback, scope); // 重复订阅

        // 发布事件
        this.dispatcher.publish(eventName);

        // 断言回调只被调用一次
        this.assert(callCount === 1, "duplicateSubscriptions: Callback should be called only once despite multiple subscriptions.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback);
    }

    /**
     * 测试在事件发布过程中修改订阅列表（添加/移除订阅）。
     */
    private function testModifySubscriptionsDuringDispatch():Void {
        trace("--- 测试在事件发布过程中修改订阅 ---");
        var eventName:String = "modifyDuringDispatchEvent";
        var callOrder:Array = [];

        var testCallback1:Function = function() {
            callOrder.push("callback1");
            // 在回调执行期间添加另一个回调
            dispatcher.subscribe(eventName, testCallback3, this);
        };
        var testCallback2:Function = function() {
            callOrder.push("callback2");
            // 在回调执行期间移除另一个回调
            dispatcher.unsubscribe(eventName, testCallback1);
        };
        var testCallback3:Function = function() {
            callOrder.push("callback3");
        };
        var scope:Object = this;

        // 订阅事件
        this.dispatcher.subscribe(eventName, testCallback1, scope);
        this.dispatcher.subscribe(eventName, testCallback2, scope);

        // 发布事件第一次
        this.dispatcher.publish(eventName);

        // 发布事件第二次
        this.dispatcher.publish(eventName);

        // 预期 callOrder:
        // 第一次发布: callback1, callback2 (callback3 尚未订阅)
        // 第二次发布: callback2, callback3 (callback1 已被移除)
        var expectedOrder:Array = ["callback1", "callback2", "callback2", "callback3"];
        var isOrderCorrect:Boolean = true;
        if (callOrder.length !== expectedOrder.length) {
            isOrderCorrect = false;
        } else {
            for (var i:Number = 0; i < expectedOrder.length; i++) {
                if (callOrder[i] !== expectedOrder[i]) {
                    isOrderCorrect = false;
                    break;
                }
            }
        }

        this.assert(isOrderCorrect, "modifySubscriptionsDuringDispatch: Call order should match expected order.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback2);
        this.dispatcher.unsubscribe(eventName, testCallback3);
    }

    /**
     * 测试回调函数抛出异常时的处理，确保不影响其他回调执行。
     */
    private function testCallbackExceptionHandling():Void {
        trace("--- 测试回调函数抛出异常 ---");
        var eventName:String = "exceptionEvent";
        var callCount:Number = 0;
        var errorCaught:Boolean = false;

        var testCallback1:Function = function() {
            callCount++;
            throw new Error("Test exception");
        };
        var testCallback2:Function = function() {
            callCount++;
        };
        var scope:Object = this;

        // 订阅事件
        this.dispatcher.subscribe(eventName, testCallback1, scope);
        this.dispatcher.subscribe(eventName, testCallback2, scope);

        // 发布事件
        // EventDispatcher 已经在 publish 方法中捕获异常，所以不需要额外处理
        this.dispatcher.publish(eventName);

        // 断言：
        // - 回调1被调用并抛出异常
        // - 回调2依然被调用
        // - 异常被捕获并记录（通过 trace 输出）
        this.assert(callCount === 2, "callbackExceptionHandling: Both callbacks should be called.");
        // 无法直接测试是否捕获异常，只能通过观察 trace 输出

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback1);
        this.dispatcher.unsubscribe(eventName, testCallback2);
    }

    /**
     * 测试多个 EventDispatcher 实例的独立性。
     */
    private function testMultipleDispatchers():Void {
        trace("--- 测试多个 EventDispatcher 实例的独立性 ---");
        var dispatcher2:EventDispatcher = new EventDispatcher();
        var eventName:String = "multipleDispatchersEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;

        var testCallback1:Function = function() {
            callCount1++;
        };
        var testCallback2:Function = function() {
            callCount2++;
        };
        var scope:Object = this;

        // 订阅事件在不同的 dispatcher 实例
        this.dispatcher.subscribe(eventName, testCallback1, scope);
        dispatcher2.subscribe(eventName, testCallback2, scope);

        // 发布事件通过第一个 dispatcher
        this.dispatcher.publish(eventName);

        // 发布事件通过第二个 dispatcher
        dispatcher2.publish(eventName);

        // 断言各自的回调只被各自的 dispatcher 调用
        this.assert(callCount1 === 1, "multipleDispatchers: Callback1 should be called once by dispatcher1.");
        this.assert(callCount2 === 1, "multipleDispatchers: Callback2 should be called once by dispatcher2.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback1);
        dispatcher2.unsubscribe(eventName, testCallback2);
    }

    /**
     * 测试 subscribeOnce 与 unsubscribe 的交互，确保在订阅后取消不会调用回调。
     */
    private function testSubscribeOnceWithUnsubscribe():Void {
        trace("--- 测试 subscribeOnce 与 unsubscribe 的交互 ---");
        var eventName:String = "subscribeOnceWithUnsubscribeEvent";
        var callCount:Number = 0;

        var testCallback:Function = function() {
            callCount++;
        };
        var scope:Object = this;

        // 一次性订阅事件
        this.dispatcher.subscribeOnce(eventName, testCallback, scope);

        // 取消订阅前发布事件
        this.dispatcher.unsubscribe(eventName, testCallback);

        // 发布事件
        this.dispatcher.publish(eventName);

        // 断言回调未被调用
        this.assert(callCount === 0, "subscribeOnceWithUnsubscribe: Callback should not be called after unsubscribe.");

        // 再次发布事件，确保无影响
        this.dispatcher.publish(eventName);
        this.assert(callCount === 0, "subscribeOnceWithUnsubscribe: Callback should not be called after unsubscribe.");
    }

    /**
     * 测试内存泄漏，通过大量订阅和取消订阅，确保没有残留引用。
     * 注意：由于 AS2 缺乏内置的内存泄漏检测工具，此测试主要通过观察性能和资源使用情况来间接评估。
     */
    private function testMemoryLeakDetection():Void {
        trace("--- 测试内存泄漏检测 ---");
        var eventName:String = "memoryLeakEvent";
        var numIterations:Number = 10000;
        var callCount:Number = 0;
        var scope:Object = this;

        var testCallback:Function = function() {
            callCount++;
        };

        // 反复订阅和取消订阅
        for (var i:Number = 0; i < numIterations; i++) {
            this.dispatcher.subscribe(eventName, testCallback, scope);
            this.dispatcher.unsubscribe(eventName, testCallback);
        }

        // 发布事件，回调不应被调用
        this.dispatcher.publish(eventName);
        this.assert(callCount === 0, "memoryLeakDetection: Callback should not be called after repeated subscribe/unsubscribe.");

        // 进一步订阅并确保正常工作
        this.dispatcher.subscribe(eventName, testCallback, scope);
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "memoryLeakDetection: Callback should be called after final subscribe.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback);
    }

    /**
     * 测试 EventDispatcher 的性能，特别是在大量订阅和发布事件时的表现。
     * 由于 AS2 的限制，性能测试仅为粗略评估。
     */
    private function testPerformance():Void {
        trace("--- 测试性能 ---");
        var eventName:String = "performanceEvent";
        var numSubscribers:Number = 1000;
        var callCount:Number = 0;
        var scope:Object = this;

        // 创建大量订阅
        for (var i:Number = 0; i < numSubscribers; i++) {
            var callback:Function = function() {
                callCount++;
            };
            this.dispatcher.subscribe(eventName, callback, scope);
        }

        // 记录开始时间
        var startTime:Number = getTimer();

        // 发布事件
        this.dispatcher.publish(eventName);

        // 记录结束时间
        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;

        // 断言所有回调被调用
        this.assert(callCount === numSubscribers, "performance: All " + numSubscribers + " callbacks should be called.");

        // 输出执行时间
        trace("Performance Test: Publishing event to " + numSubscribers + " subscribers took " + duration + " ms.");

        // 清理
        // 注意：由于回调是匿名函数，无法一一取消订阅，这里暂不清理
        // 在实际使用中，建议保留对回调的引用以便取消订阅
    }

    /**
     * 输出所有测试结果，总结测试通过与失败情况。
     */
    private function reportResults():Void {
        var passed:Number = 0;
        var failed:Number = 0;
        for (var i:Number = 0; i < this.testResults.length; i++) {
            var result:Object = this.testResults[i];
            if (result.success) {
                passed++;
            } else {
                failed++;
            }
        }
        trace("=== 测试结果 ===");
        trace("通过: " + passed + " 条");
        trace("失败: " + failed + " 条");
        if (failed > 0) {
            trace("请检查失败的测试并修正相关代码。");
        } else {
            trace("所有测试均通过。");
        }
    }
}
