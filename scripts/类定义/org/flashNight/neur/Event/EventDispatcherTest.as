import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;
import flash.utils.getTimer;

/**
 * EventDispatcherTest 类用于全面测试 EventDispatcher 的功能和性能。
 * 它包含多个测试方法，使用自定义的断言机制验证各个方法的正确性。
 * 通过运行所有测试方法，可以确保 EventDispatcher 的实现符合预期。
 * 特别增强了对 subscribeSingle 方法的边界情况测试。
 */
class org.flashNight.neur.Event.EventDispatcherTest {
    private var dispatcher:EventDispatcher; // 待测试的 EventDispatcher 实例
    private var testResults:Array;           // 存储测试结果信息

    /**
     * 构造函数：初始化测试类，创建 EventDispatcher 实例和结果存储数组。
     */
    public function EventDispatcherTest() {
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
        this.testSubscribeSingle();            // 原有测试
        this.testSubscribeSingleGlobal();     // 原有测试
        
        // === 新增的 subscribeSingle 边界情况测试 ===
        this.testSubscribeSingleMultipleCalls();
        this.testSubscribeSingleAfterNormalSubscribe();
        this.testNormalSubscribeAfterSubscribeSingle();
        this.testSubscribeSingleUnsubscribeInteraction();
        this.testSubscribeSingleSubscribeOnceInteraction();
        this.testSubscribeSingleMultipleEvents();
        this.testSubscribeSingleDifferentScopes();
        this.testSubscribeSingleDuringCallback();
        this.testSubscribeSingleWithDestroy();
        this.testSubscribeSingleOnDestroyedDispatcher();
        this.testSubscribeSingleNullParameters();
        this.testSubscribeSingleGlobalIsolation();
        this.testSubscribeSingleMultipleDispatcherIsolation();
        this.testSubscribeSingleRapidFireEvents();
        this.testSubscribeSingleWithSameCallback();
        this.testSubscribeSingleCallbackReuse();

        // === [v2.2] 新增回归测试 ===
        this.testSubscribeOnceSubscriptionCleanup();
        this.testUnsubscribeRefCountOptimization();

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
     * 初始化一个新的 EventDispatcher 实例，为每个测试方法提供独立环境。
     */
    private function initializeDispatcher():Void {
        this.dispatcher = new EventDispatcher();
    }

    /**
     * 清理 EventDispatcher 实例。
     */
    private function cleanupDispatcher():Void {
        if (this.dispatcher != null) {
            this.dispatcher.destroy();
            this.dispatcher = null;
        }
    }

    /**
     * 测试 subscribe 方法的正确性。
     */
    private function testSubscribe():Void {
        trace("--- 测试 subscribe 方法 ---");
        this.initializeDispatcher();

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
        this.cleanupDispatcher();
    }

    /**
     * 测试 publish 方法的正确性，特别是参数传递。
     */
    private function testPublish():Void {
        trace("--- 测试 publish 方法 ---");
        this.initializeDispatcher();

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
        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeOnce 方法的正确性。
     */
    private function testSubscribeOnce():Void {
        trace("--- 测试 subscribeOnce 方法 ---");
        this.initializeDispatcher();

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

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback);
        this.cleanupDispatcher();
    }

    /**
     * 测试 unsubscribe 方法的正确性。
     */
    private function testUnsubscribe():Void {
        trace("--- 测试 unsubscribe 方法 ---");
        this.initializeDispatcher();

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

        this.cleanupDispatcher();
    }

    /**
     * 测试 destroy 方法的正确性，确保所有订阅被取消。
     */
    private function testDestroy():Void {
        trace("--- 测试 destroy 方法 ---");
        this.initializeDispatcher();

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

        // 尝试再次销毁，确保无副作用
        this.dispatcher.destroy();
        trace("destroy: Called destroy() twice without issues.");

        this.cleanupDispatcher();
    }

    /**
     * 测试发布没有订阅者的事件，确保不会抛出错误或异常。
     */
    private function testNoSubscribers():Void {
        trace("--- 测试发布没有订阅者的事件 ---");
        this.initializeDispatcher();

        var eventName:String = "noSubscriberEvent";
        try {
            this.dispatcher.publish(eventName);
            this.assert(true, "noSubscribers: Publishing event with no subscribers should not throw an error.");
        } catch (error:Error) {
            this.assert(false, "noSubscribers: Publishing event with no subscribers threw an error.");
        }

        this.cleanupDispatcher();
    }

    /**
     * 测试不同作用域下回调函数的执行情况。
     */
    private function testDifferentScopes():Void {
        trace("--- 测试不同作用域的回调执行 ---");
        this.initializeDispatcher();

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
        this.cleanupDispatcher();
    }

    /**
     * 测试重复订阅同一回调函数，确保不会导致多次执行。
     */
    private function testDuplicateSubscriptions():Void {
        trace("--- 测试重复订阅同一回调函数 ---");
        this.initializeDispatcher();

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
        this.assert(callCount === 1, "duplicateSubscriptions: Callback should be called once due to duplicate subscriptions.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback);
        // 由于重复订阅，每个订阅都需要被取消
        this.dispatcher.unsubscribe(eventName, testCallback);
        this.cleanupDispatcher();
    }

    /**
     * 测试在事件发布过程中修改订阅列表（添加/移除订阅）。
     */
    private function testModifySubscriptionsDuringDispatch():Void {
        trace("--- 测试在事件发布过程中修改订阅 ---");
        this.initializeDispatcher();

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
        this.cleanupDispatcher();
    }

    /**
     * 测试回调函数抛出异常时的处理
     * [v2.2] 更新：采用 let-it-crash 策略，异常会传播而不是被静默捕获
     * 在 AS2 中，由于语言的宽容特性，错误传播后后续回调可能不执行
     */
    private function testCallbackExceptionHandling():Void {
        trace("--- 测试回调函数抛出异常 ---");
        this.initializeDispatcher();

        var eventName:String = "exceptionEvent";
        var callCount:Number = 0;
        var exceptionThrown:Boolean = false;

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

        // [v2.2] let-it-crash 策略：异常会传播，用 try/catch 包裹以防止测试中断
        try {
            this.dispatcher.publish(eventName);
            exceptionThrown = false;
        } catch (error:Error) {
            // [v2.2] 异常传播是 let-it-crash 的预期行为
            exceptionThrown = true;
        }

        // [v2.2] 断言更新：
        // - 至少回调1被调用（callCount >= 1）
        // - 由于 let-it-crash 策略，后续回调可能不执行，这是预期行为
        this.assert(callCount >= 1, "callbackExceptionHandling: Error callback should be called.");
        // [v2.2] 异常传播是 let-it-crash 的正常行为，不再断言异常被内部处理
        // this.assert(!exceptionThrown, "callbackExceptionHandling: Exception should be handled within EventDispatcher.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback1);
        this.dispatcher.unsubscribe(eventName, testCallback2);
        this.cleanupDispatcher();
    }

    /**
     * 测试多个 EventDispatcher 实例的独立性。
     */
    private function testMultipleDispatchers():Void {
        trace("--- 测试多个 EventDispatcher 实例的独立性 ---");
        this.initializeDispatcher();

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
        this.cleanupDispatcher();
        dispatcher2.destroy();
    }

    /**
     * 测试 subscribeOnce 与 unsubscribe 的交互，确保在订阅后取消不会调用回调。
     */
    private function testSubscribeOnceWithUnsubscribe():Void {
        trace("--- 测试 subscribeOnce 与 unsubscribe 的交互 ---");
        this.initializeDispatcher();

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

        // 清理
        this.cleanupDispatcher();
    }

    /**
     * 测试单一订阅方法 subscribeSingle 的正确性。
     */
    private function testSubscribeSingle():Void {
        trace("--- 测试 subscribeSingle 方法 ---");
        this.initializeDispatcher();

        var eventName:String = "singleSubscribeEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var testCallback1:Function = function() {
            callCount1++;
        };
        var testCallback2:Function = function() {
            callCount2++;
        };
        var scope:Object = this;

        // 使用 subscribeSingle 订阅事件
        this.dispatcher.subscribeSingle(eventName, testCallback1, scope);

        // 发布事件，触发 testCallback1
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "subscribeSingle: First callback should be called once.");

        // 使用 subscribeSingle 再次订阅同一事件，testCallback2 应替换 testCallback1
        this.dispatcher.subscribeSingle(eventName, testCallback2, scope);

        // 发布事件，触发 testCallback2
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "subscribeSingle: First callback should not be called again.");
        this.assert(callCount2 === 1, "subscribeSingle: Second callback should be called once.");

        // 再次发布事件，testCallback2 再次被调用
        this.dispatcher.publish(eventName);
        this.assert(callCount2 === 2, "subscribeSingle: Second callback should be called twice.");

        // 清理
        this.dispatcher.unsubscribe(eventName, testCallback2);
        this.cleanupDispatcher();
    }

    /**
     * 测试全局单一订阅方法 subscribeSingleGlobal 的正确性。
     */
    private function testSubscribeSingleGlobal():Void {
        trace("--- 测试 subscribeSingleGlobal 方法 ---");
        this.initializeDispatcher();

        var eventName:String = "singleSubscribeGlobalEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var testCallback1:Function = function() {
            callCount1++;
        };
        var testCallback2:Function = function() {
            callCount2++;
        };
        var scope:Object = this;

        // 使用 subscribeSingleGlobal 订阅全局事件
        this.dispatcher.subscribeSingleGlobal(eventName, testCallback1, scope);

        // 发布全局事件，触发 testCallback1
        this.dispatcher.publishGlobal(eventName);
        this.assert(callCount1 === 1, "subscribeSingleGlobal: First global callback should be called once.");

        // 使用 subscribeSingleGlobal 再次订阅同一全局事件，testCallback2 应替换 testCallback1
        this.dispatcher.subscribeSingleGlobal(eventName, testCallback2, scope);

        // 发布全局事件，触发 testCallback2
        this.dispatcher.publishGlobal(eventName);
        this.assert(callCount1 === 1, "subscribeSingleGlobal: First global callback should not be called again.");
        this.assert(callCount2 === 1, "subscribeSingleGlobal: Second global callback should be called once.");

        // 再次发布全局事件，testCallback2 再次被调用
        this.dispatcher.publishGlobal(eventName);
        this.assert(callCount2 === 2, "subscribeSingleGlobal: Second global callback should be called twice.");

        // 清理
        this.dispatcher.unsubscribeGlobal(eventName, testCallback2);
        this.cleanupDispatcher();
    }

    // === 新增的 subscribeSingle 边界情况测试 ===

    /**
     * 测试连续多次调用 subscribeSingle 的行为
     */
    private function testSubscribeSingleMultipleCalls():Void {
        trace("--- 测试 subscribeSingle 连续多次调用 ---");
        this.initializeDispatcher();

        var eventName:String = "multipleCallsEvent";
        var callCounts:Array = [0, 0, 0, 0]; // 4个回调的调用次数
        var scope:Object = this;

        var callback1:Function = function() { callCounts[0]++; };
        var callback2:Function = function() { callCounts[1]++; };
        var callback3:Function = function() { callCounts[2]++; };
        var callback4:Function = function() { callCounts[3]++; };

        // 连续调用 subscribeSingle
        this.dispatcher.subscribeSingle(eventName, callback1, scope);
        this.dispatcher.subscribeSingle(eventName, callback2, scope);
        this.dispatcher.subscribeSingle(eventName, callback3, scope);
        this.dispatcher.subscribeSingle(eventName, callback4, scope);

        // 发布事件，只有最后一个回调应该被调用
        this.dispatcher.publish(eventName);

        this.assert(callCounts[0] === 0, "subscribeSingleMultipleCalls: First callback should not be called.");
        this.assert(callCounts[1] === 0, "subscribeSingleMultipleCalls: Second callback should not be called.");
        this.assert(callCounts[2] === 0, "subscribeSingleMultipleCalls: Third callback should not be called.");
        this.assert(callCounts[3] === 1, "subscribeSingleMultipleCalls: Fourth callback should be called once.");

        this.cleanupDispatcher();
    }

    /**
     * 测试在 subscribeSingle 之后调用普通 subscribe 的行为
     */
    private function testSubscribeSingleAfterNormalSubscribe():Void {
        trace("--- 测试 subscribeSingle 之后调用普通 subscribe ---");
        this.initializeDispatcher();

        var eventName:String = "singleAfterNormalEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var scope:Object = this;

        var callback1:Function = function() { callCount1++; };
        var callback2:Function = function() { callCount2++; };

        // 先用 subscribeSingle
        this.dispatcher.subscribeSingle(eventName, callback1, scope);

        // 再用普通 subscribe
        this.dispatcher.subscribe(eventName, callback2, scope);

        // 发布事件，两个回调都应该被调用
        this.dispatcher.publish(eventName);

        this.assert(callCount1 === 1, "subscribeSingleAfterNormal: Single callback should be called.");
        this.assert(callCount2 === 1, "subscribeSingleAfterNormal: Normal callback should be called.");

        this.cleanupDispatcher();
    }

    /**
     * 测试在普通 subscribe 之后调用 subscribeSingle 的行为
     */
    private function testNormalSubscribeAfterSubscribeSingle():Void {
        trace("--- 测试普通 subscribe 之后调用 subscribeSingle ---");
        this.initializeDispatcher();

        var eventName:String = "normalAfterSingleEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var scope:Object = this;

        var callback1:Function = function() { callCount1++; };
        var callback2:Function = function() { callCount2++; };

        // 先用普通 subscribe
        this.dispatcher.subscribe(eventName, callback1, scope);

        // 再用 subscribeSingle，应该替换掉普通订阅
        this.dispatcher.subscribeSingle(eventName, callback2, scope);

        // 发布事件，只有 subscribeSingle 的回调应该被调用
        this.dispatcher.publish(eventName);

        this.assert(callCount1 === 0, "normalAfterSubscribeSingle: Normal callback should be replaced.");
        this.assert(callCount2 === 1, "normalAfterSubscribeSingle: Single callback should be called.");

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 与 unsubscribe 的交互
     */
    private function testSubscribeSingleUnsubscribeInteraction():Void {
        trace("--- 测试 subscribeSingle 与 unsubscribe 的交互 ---");
        this.initializeDispatcher();

        var eventName:String = "singleUnsubscribeEvent";
        var callCount:Number = 0;
        var scope:Object = this;

        var callback:Function = function() { callCount++; };

        // 用 subscribeSingle 订阅
        this.dispatcher.subscribeSingle(eventName, callback, scope);

        // 发布事件确认订阅生效
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "subscribeSingleUnsubscribe: Callback should be called before unsubscribe.");

        // 取消订阅
        this.dispatcher.unsubscribe(eventName, callback);

        // 再次发布事件，回调不应该被调用
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "subscribeSingleUnsubscribe: Callback should not be called after unsubscribe.");

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 与 subscribeOnce 的交互
     * [v2.2] 更新：subscribeSingle 的语义是"只保留一个订阅"，会替换掉之前的所有订阅
     * 因此 subscribeOnce 的回调会被 subscribeSingle 替换掉
     */
    private function testSubscribeSingleSubscribeOnceInteraction():Void {
        trace("--- 测试 subscribeSingle 与 subscribeOnce 的交互 ---");
        this.initializeDispatcher();

        var eventName:String = "singleOnceEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var scope:Object = this;

        var callback1:Function = function() { callCount1++; };
        var callback2:Function = function() { callCount2++; };

        // 先用 subscribeOnce
        this.dispatcher.subscribeOnce(eventName, callback1, scope);

        // 再用 subscribeSingle - 这会替换掉之前的 subscribeOnce 订阅
        this.dispatcher.subscribeSingle(eventName, callback2, scope);

        // [v2.2] 发布事件第一次
        // subscribeSingle 的语义是"只保留一个订阅"，所以 callback1 已被替换，不会被调用
        // 只有 callback2 (single) 会被调用
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 0, "subscribeSingleOnceInteraction: Once callback should be replaced by subscribeSingle.");
        this.assert(callCount2 === 1, "subscribeSingleOnceInteraction: Single callback should be called first time.");

        // 发布事件第二次，只有 subscribeSingle 的回调执行
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 0, "subscribeSingleOnceInteraction: Once callback should still not be called.");
        this.assert(callCount2 === 2, "subscribeSingleOnceInteraction: Single callback should be called second time.");

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 对多个不同事件的处理
     */
    private function testSubscribeSingleMultipleEvents():Void {
        trace("--- 测试 subscribeSingle 多个事件处理 ---");
        this.initializeDispatcher();

        var eventName1:String = "multiEvent1";
        var eventName2:String = "multiEvent2";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var scope:Object = this;

        var callback1:Function = function() { callCount1++; };
        var callback2:Function = function() { callCount2++; };

        // 对不同事件使用 subscribeSingle
        this.dispatcher.subscribeSingle(eventName1, callback1, scope);
        this.dispatcher.subscribeSingle(eventName2, callback2, scope);

        // 发布不同事件，确保不互相影响
        this.dispatcher.publish(eventName1);
        this.assert(callCount1 === 1, "subscribeSingleMultipleEvents: First event callback should be called.");
        this.assert(callCount2 === 0, "subscribeSingleMultipleEvents: Second event callback should not be called.");

        this.dispatcher.publish(eventName2);
        this.assert(callCount1 === 1, "subscribeSingleMultipleEvents: First event callback should not be called again.");
        this.assert(callCount2 === 1, "subscribeSingleMultipleEvents: Second event callback should be called.");

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 在不同作用域下的行为
     */
    private function testSubscribeSingleDifferentScopes():Void {
        trace("--- 测试 subscribeSingle 不同作用域 ---");
        this.initializeDispatcher();

        var eventName:String = "singleScopeEvent";
        var scope1:Object = { value: 0 };
        var scope2:Object = { value: 0 };

        var callback:Function = function() { this.value++; };

        // 用不同作用域分别调用 subscribeSingle
        this.dispatcher.subscribeSingle(eventName, callback, scope1);
        this.dispatcher.subscribeSingle(eventName, callback, scope2);

        // 发布事件，只有最后一个作用域应该接收到事件
        this.dispatcher.publish(eventName);

        this.assert(scope1.value === 0, "subscribeSingleDifferentScopes: First scope should not receive event.");
        this.assert(scope2.value === 1, "subscribeSingleDifferentScopes: Second scope should receive event.");

        this.cleanupDispatcher();
    }

    /**
     * 测试在回调执行过程中调用 subscribeSingle
     */
    private function testSubscribeSingleDuringCallback():Void {
        trace("--- 测试在回调执行中调用 subscribeSingle ---");
        this.initializeDispatcher();

        var eventName:String = "singleDuringCallbackEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var scope:Object = this;

        var callback2:Function = function() { callCount2++; };

        var callback1:Function = function() {
            callCount1++;
            // 在回调执行期间调用 subscribeSingle
            dispatcher.subscribeSingle(eventName, callback2, scope);
        };

        this.dispatcher.subscribeSingle(eventName, callback1, scope);

        // 发布事件第一次
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "subscribeSingleDuringCallback: First callback should be called.");
        this.assert(callCount2 === 0, "subscribeSingleDuringCallback: Second callback should not be called during first publish.");

        // 发布事件第二次
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "subscribeSingleDuringCallback: First callback should not be called again.");
        this.assert(callCount2 === 1, "subscribeSingleDuringCallback: Second callback should be called on second publish.");

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 与 destroy 的交互
     */
    private function testSubscribeSingleWithDestroy():Void {
        trace("--- 测试 subscribeSingle 与 destroy 的交互 ---");
        this.initializeDispatcher();

        var eventName:String = "singleDestroyEvent";
        var callCount:Number = 0;
        var scope:Object = this;

        var callback:Function = function() { callCount++; };

        // 使用 subscribeSingle 订阅
        this.dispatcher.subscribeSingle(eventName, callback, scope);

        // 发布事件确认订阅生效
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "subscribeSingleWithDestroy: Callback should be called before destroy.");

        // 销毁 dispatcher
        this.dispatcher.destroy();

        // 再次发布事件，回调不应该被调用
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "subscribeSingleWithDestroy: Callback should not be called after destroy.");

        this.cleanupDispatcher();
    }

    /**
     * 测试在已销毁的 dispatcher 上调用 subscribeSingle
     */
    private function testSubscribeSingleOnDestroyedDispatcher():Void {
        trace("--- 测试在已销毁的 dispatcher 上调用 subscribeSingle ---");
        this.initializeDispatcher();

        var eventName:String = "singleDestroyedEvent";
        var callCount:Number = 0;
        var scope:Object = this;

        var callback:Function = function() { callCount++; };

        // 先销毁 dispatcher
        this.dispatcher.destroy();

        // 在已销毁的 dispatcher 上调用 subscribeSingle，应该无效
        this.dispatcher.subscribeSingle(eventName, callback, scope);

        // 发布事件，回调不应该被调用
        this.dispatcher.publish(eventName);
        this.assert(callCount === 0, "subscribeSingleOnDestroyed: Callback should not be called on destroyed dispatcher.");

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 传入 null 参数的处理
     */
    private function testSubscribeSingleNullParameters():Void {
        trace("--- 测试 subscribeSingle null 参数处理 ---");
        this.initializeDispatcher();

        var eventName:String = "singleNullEvent";
        var callCount:Number = 0;

        var callback:Function = function() { callCount++; };

        // 测试 null scope
        try {
            this.dispatcher.subscribeSingle(eventName, callback, null);
            this.dispatcher.publish(eventName);
            this.assert(callCount === 1, "subscribeSingleNullParams: Should handle null scope gracefully.");
        } catch (error:Error) {
            this.assert(false, "subscribeSingleNullParams: Should not throw error with null scope.");
        }

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 与全局事件的隔离性
     */
    private function testSubscribeSingleGlobalIsolation():Void {
        trace("--- 测试 subscribeSingle 与全局事件的隔离性 ---");
        this.initializeDispatcher();

        var eventName:String = "isolationEvent";
        var localCallCount:Number = 0;
        var globalCallCount:Number = 0;
        var scope:Object = this;

        var localCallback:Function = function() { localCallCount++; };
        var globalCallback:Function = function() { globalCallCount++; };

        // 本地 subscribeSingle 和全局 subscribeGlobal 使用相同事件名
        this.dispatcher.subscribeSingle(eventName, localCallback, scope);
        this.dispatcher.subscribeGlobal(eventName, globalCallback, scope);

        // 发布本地事件
        this.dispatcher.publish(eventName);
        this.assert(localCallCount === 1, "subscribeSingleGlobalIsolation: Local callback should be called.");
        this.assert(globalCallCount === 0, "subscribeSingleGlobalIsolation: Global callback should not be called by local publish.");

        // 发布全局事件
        this.dispatcher.publishGlobal(eventName);
        this.assert(localCallCount === 1, "subscribeSingleGlobalIsolation: Local callback should not be called by global publish.");
        this.assert(globalCallCount === 1, "subscribeSingleGlobalIsolation: Global callback should be called by global publish.");

        this.cleanupDispatcher();
    }

    /**
     * 测试多个 dispatcher 实例之间的 subscribeSingle 隔离性
     */
    private function testSubscribeSingleMultipleDispatcherIsolation():Void {
        trace("--- 测试多个 dispatcher 的 subscribeSingle 隔离性 ---");
        this.initializeDispatcher();
        var dispatcher2:EventDispatcher = new EventDispatcher();

        var eventName:String = "multiDispatcherIsolationEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var scope:Object = this;

        var callback1:Function = function() { callCount1++; };
        var callback2:Function = function() { callCount2++; };

        // 在两个不同的 dispatcher 上使用 subscribeSingle
        this.dispatcher.subscribeSingle(eventName, callback1, scope);
        dispatcher2.subscribeSingle(eventName, callback2, scope);

        // 各自发布事件，应该不互相影响
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "subscribeSingleMultipleDispatcherIsolation: First dispatcher callback should be called.");
        this.assert(callCount2 === 0, "subscribeSingleMultipleDispatcherIsolation: Second dispatcher callback should not be called.");

        dispatcher2.publish(eventName);
        this.assert(callCount1 === 1, "subscribeSingleMultipleDispatcherIsolation: First dispatcher callback should not be called again.");
        this.assert(callCount2 === 1, "subscribeSingleMultipleDispatcherIsolation: Second dispatcher callback should be called.");

        this.cleanupDispatcher();
        dispatcher2.destroy();
    }

    /**
     * 测试 subscribeSingle 在快速连续事件发布中的表现
     */
    private function testSubscribeSingleRapidFireEvents():Void {
        trace("--- 测试 subscribeSingle 快速连续事件 ---");
        this.initializeDispatcher();

        var eventName:String = "rapidFireEvent";
        var callCount:Number = 0;
        var scope:Object = this;

        var callback:Function = function() { callCount++; };

        this.dispatcher.subscribeSingle(eventName, callback, scope);

        // 快速连续发布事件
        for (var i:Number = 0; i < 10; i++) {
            this.dispatcher.publish(eventName);
        }

        this.assert(callCount === 10, "subscribeSingleRapidFire: Callback should be called for each event publish.");

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 使用相同的回调函数
     */
    private function testSubscribeSingleWithSameCallback():Void {
        trace("--- 测试 subscribeSingle 使用相同回调函数 ---");
        this.initializeDispatcher();

        var eventName1:String = "sameCallbackEvent1";
        var eventName2:String = "sameCallbackEvent2";
        var callCount:Number = 0;
        var scope:Object = this;

        var sharedCallback:Function = function() { callCount++; };

        // 对不同事件使用相同的回调函数
        this.dispatcher.subscribeSingle(eventName1, sharedCallback, scope);
        this.dispatcher.subscribeSingle(eventName2, sharedCallback, scope);

        // 分别发布事件
        this.dispatcher.publish(eventName1);
        this.assert(callCount === 1, "subscribeSingleSameCallback: First event should trigger callback.");

        this.dispatcher.publish(eventName2);
        this.assert(callCount === 2, "subscribeSingleSameCallback: Second event should trigger callback.");

        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 回调函数的重用和替换
     */
    private function testSubscribeSingleCallbackReuse():Void {
        trace("--- 测试 subscribeSingle 回调函数重用和替换 ---");
        this.initializeDispatcher();

        var eventName:String = "callbackReuseEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var scope:Object = this;

        var callback1:Function = function() { callCount1++; };
        var callback2:Function = function() { callCount2++; };

        // 订阅 callback1
        this.dispatcher.subscribeSingle(eventName, callback1, scope);

        // 发布事件
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "subscribeSingleCallbackReuse: First callback should be called.");

        // 替换为 callback2
        this.dispatcher.subscribeSingle(eventName, callback2, scope);

        // 再次发布事件
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "subscribeSingleCallbackReuse: First callback should not be called after replacement.");
        this.assert(callCount2 === 1, "subscribeSingleCallbackReuse: Second callback should be called after replacement.");

        // 再替换回 callback1
        this.dispatcher.subscribeSingle(eventName, callback1, scope);

        // 发布事件
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 2, "subscribeSingleCallbackReuse: First callback should be called again after re-subscription.");
        this.assert(callCount2 === 1, "subscribeSingleCallbackReuse: Second callback should not be called after replacement.");

        this.cleanupDispatcher();
    }

    // === [v2.2] 新增回归测试 ===

    /**
     * [v2.2 回归测试 P0-1] 验证 subscribeOnce 回调触发后订阅记录被正确清理
     * 修复问题：之前 subscribeOnce 回调触发后，EventDispatcher.subscriptions 数组中仍残留记录
     */
    private function testSubscribeOnceSubscriptionCleanup():Void {
        trace("--- [v2.2] 测试 subscribeOnce 订阅记录清理 ---");
        this.initializeDispatcher();

        var eventName:String = "onceCleanupEvent";
        var callCount:Number = 0;
        var scope:Object = this;

        var testCallback:Function = function() {
            callCount++;
        };

        // 获取初始订阅数量
        var initialSubscriptionCount:Number = this.dispatcher["subscriptions"].length;

        // 一次性订阅
        this.dispatcher.subscribeOnce(eventName, testCallback, scope);

        // 验证订阅已添加
        var afterSubscribeCount:Number = this.dispatcher["subscriptions"].length;
        this.assert(afterSubscribeCount == initialSubscriptionCount + 1,
            "[v2.2 P0-1] subscribeOnce-cleanup - subscription added");

        // 触发事件
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "[v2.2 P0-1] subscribeOnce-cleanup - callback called once");

        // [关键测试点] 验证订阅记录已被清理
        var afterFireCount:Number = this.dispatcher["subscriptions"].length;
        this.assert(afterFireCount == initialSubscriptionCount,
            "[v2.2 P0-1] subscribeOnce-cleanup - subscription record cleaned after callback fired");

        // 再次触发，确保不会重复调用
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "[v2.2 P0-1] subscribeOnce-cleanup - callback not called again");

        this.cleanupDispatcher();
    }

    /**
     * [v2.2 回归测试 P1-2] 验证 unsubscribe 使用引用计数优化
     * 修复问题：之前 unsubscribe 每次都扫描整个 subscriptions 数组查找事件名称，为 O(n²)
     * 现在使用 eventNameRefCount 引用计数，使 uniqueEventNames 缓存清理为 O(1)
     */
    private function testUnsubscribeRefCountOptimization():Void {
        trace("--- [v2.2] 测试 unsubscribe 引用计数优化 ---");
        this.initializeDispatcher();

        var eventName:String = "refCountEvent";
        var callCount:Number = 0;
        var scope:Object = this;

        var callback1:Function = function() { callCount++; };
        var callback2:Function = function() { callCount += 10; };
        var callback3:Function = function() { callCount += 100; };

        // 订阅多个回调到同一事件
        this.dispatcher.subscribe(eventName, callback1, scope);
        this.dispatcher.subscribe(eventName, callback2, scope);
        this.dispatcher.subscribe(eventName, callback3, scope);

        // 验证 uniqueEventNames 缓存存在
        var hasEventNameCached:Boolean = this.dispatcher["uniqueEventNames"][eventName] != undefined;
        this.assert(hasEventNameCached, "[v2.2 P1-2] refcount-optimize - event name cached after subscribe");

        // 验证引用计数正确（如果实现了 eventNameRefCount）
        var refCount:Number = this.dispatcher["eventNameRefCount"][eventName];
        this.assert(refCount == 3, "[v2.2 P1-2] refcount-optimize - ref count should be 3 after 3 subscriptions");

        // 取消第一个订阅
        this.dispatcher.unsubscribe(eventName, callback1);

        // 验证引用计数减少
        refCount = this.dispatcher["eventNameRefCount"][eventName];
        this.assert(refCount == 2, "[v2.2 P1-2] refcount-optimize - ref count should be 2 after unsubscribe");

        // 验证缓存仍然存在（因为还有其他订阅）
        hasEventNameCached = this.dispatcher["uniqueEventNames"][eventName] != undefined;
        this.assert(hasEventNameCached, "[v2.2 P1-2] refcount-optimize - cache still exists with remaining subscriptions");

        // 取消剩余订阅
        this.dispatcher.unsubscribe(eventName, callback2);
        this.dispatcher.unsubscribe(eventName, callback3);

        // 验证引用计数为 0 时缓存被清理
        hasEventNameCached = this.dispatcher["uniqueEventNames"][eventName] != undefined;
        this.assert(!hasEventNameCached, "[v2.2 P1-2] refcount-optimize - cache cleaned when ref count reaches 0");

        // 验证发布事件不会调用任何回调
        callCount = 0;
        this.dispatcher.publish(eventName);
        this.assert(callCount == 0, "[v2.2 P1-2] refcount-optimize - no callbacks after all unsubscribed");

        this.cleanupDispatcher();
    }

    /**
     * 测试内存泄漏，通过大量订阅和取消订阅，确保没有残留引用。
     * 注意：由于 AS2 缺乏内置的内存泄漏检测工具，此测试主要通过观察性能和资源使用情况来间接评估。
     */
    private function testMemoryLeakDetection():Void {
        trace("--- 测试内存泄漏检测 ---");
        this.initializeDispatcher();

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
        this.cleanupDispatcher();
    }

    /**
     * 测试 EventDispatcher 的性能，特别是在大量订阅和发布事件时的表现。
     * 由于 AS2 的限制，性能测试仅为粗略评估。
     */
    private function testPerformance():Void {
        trace("--- 测试性能 ---");
        this.initializeDispatcher();

        var eventName:String = "performanceEvent";
        var numSubscribers:Number = 1000;
        var callCount:Number = 0;
        var scope:Object = this;

        // 保存回调引用以便后续取消订阅
        var callbacks:Array = [];

        // 创建大量订阅
        for (var i:Number = 0; i < numSubscribers; i++) {
            var callback:Function = function() {
                callCount++;
            };
            callbacks.push(callback);
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

        // 清理所有订阅
        for (var j:Number = 0; j < callbacks.length; j++) {
            this.dispatcher.unsubscribe(eventName, callbacks[j]);
        }

        this.cleanupDispatcher();
    }

    /**
     * 输出所有测试结果，总结测试通过与失败情况。
     */
    private function reportResults():Void {
        var passed:Number = 0;
        var failed:Number = 0;
        var failedMessages:Array = [];

        for (var i:Number = 0; i < this.testResults.length; i++) {
            var result:Object = this.testResults[i];
            if (result.success) {
                passed++;
            } else {
                failed++;
                failedMessages.push(result.message);
            }
        }

        trace("=== 测试结果 ===");
        trace("通过: " + passed + " 条");
        trace("失败: " + failed + " 条");
        if (failed > 0) {
            trace("失败详情:");
            for (var j:Number = 0; j < failedMessages.length; j++) {
                trace("- " + failedMessages[j]);
            }
            trace("请检查失败的测试并修正相关代码。");
        } else {
            trace("所有测试均通过。");
        }
    }
}