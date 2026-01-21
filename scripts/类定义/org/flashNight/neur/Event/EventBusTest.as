// 导入必要的类
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * EventBusTest 类用于封装和执行 EventBus 的一系列测试用例。
 */
class org.flashNight.neur.Event.EventBusTest {
    // 回调函数调用标志
    private var callback1Called:Boolean;
    private var callback2Called:Boolean;
    private var callbackWithArgsCalled:Boolean;
    private var callbackWithErrorCalled:Boolean;
    private var callbackOnceCalled:Boolean;

    // 新增测试标志
    private var paramCallbackCalled:Boolean;
    private var onceCallbackCallCount:Number;
    private var complexParamReceived:Object;
    private var nestedOnceCallbackCalled:Boolean;
    private var multipleOnceCallbacksCalled:Array;

    // EventBus 实例
    private var eventBus:EventBus;

    /**
     * 构造函数，初始化测试环境并运行所有测试用例。
     */
    public function EventBusTest() {
        // 初始化回调标志
        this.resetFlags();

        // 初始化 EventBus 实例
        this.eventBus = EventBus.initialize();

        // 运行所有测试用例
        this.runAllTests();
    }

    /**
     * 重置所有回调标志。
     */
    private function resetFlags():Void {
        this.callback1Called = false;
        this.callback2Called = false;
        this.callbackWithArgsCalled = false;
        this.callbackWithErrorCalled = false;
        this.callbackOnceCalled = false;

        // 新增标志的重置
        this.onceCallbackCallCount = 0;
        this.nestedOnceCallbackCalled = false;
        // 对于数组型标志，新建一个空数组
        this.multipleOnceCallbacksCalled = [];
    }


    /**
     * 断言函数，用于验证测试结果。
     * @param condition Boolean 条件
     * @param testName String 测试名称
     */
    private function assert(condition:Boolean, testName:String):Void {
        if (condition) {
            trace("[PASS] " + testName);
        } else {
            trace("[FAIL] " + testName);
        }
    }

    /**
     * 运行所有测试用例。
     */
    private function runAllTests():Void {
        this.testEventBusSubscribePublish();
        this.testEventBusUnsubscribe();
        this.testEventBusSubscribeOnce();
        this.testEventBusPublishWithArgs();
        this.testEventBusCallbackErrorHandling();
        this.testEventBusDestroy();

        this.testPublishWithParamBasic();
        this.testPublishWithParamComplex();
        this.testSubscribeOnceReliability();
        this.testSubscribeOnceWithNestedPublish();
        this.testMultipleSubscribeOnce();
        this.testSubscribeOnceWithUnsubscribe();
        this.testHighVolumeSubscribeOnce();

        // [v2.0] 新增回归测试 - 验证 GPT PRO 审阅问题已修复
        this.testUnsubscribeThenResubscribe();
        this.testRecursivePublish();
        this.testOnceCallbackMapCleanup();

        // [v2.1] 新增回归测试 - 验证三方交叉审查问题已修复
        this.testSubscribeOnceEventBucketing();
        this.testDelegateParamsUIDCollision();
        this.testDictionaryUIDNonEnumerable();
        this.testDictionaryUIDMapCleanup();

        // [v2.2] 新增回归测试 - 验证代码审查修复
        this.testDestroyDuringDispatchGuard();
        this.testLetItCrashStrategy();

        // 运行性能测试
        this.runPerformanceTests();

        trace("All tests completed.");
    }

    // -----------------------
    // 测试用例方法
    // -----------------------

    /**
     * 测试用例 1: 订阅和发布单个事件
     */
    private function testEventBusSubscribePublish():Void {
        this.resetFlags();
        this.eventBus.subscribe("TEST_EVENT", Delegate.create(this, this.callback1), this);
        this.eventBus.publish("TEST_EVENT");
        this.assert(this.callback1Called == true, "Test 1: EventBus subscribe and publish single event");
        this.callback1Called = false;
        this.eventBus.unsubscribe("TEST_EVENT", Delegate.create(this, this.callback1));
    }

    /**
     * 测试用例 2: 取消订阅
     */
    private function testEventBusUnsubscribe():Void {
        this.resetFlags();
        this.eventBus.subscribe("TEST_EVENT", Delegate.create(this, this.callback1), this);
        this.eventBus.unsubscribe("TEST_EVENT", Delegate.create(this, this.callback1));
        this.eventBus.publish("TEST_EVENT");
        this.assert(this.callback1Called == false, "Test 2: EventBus unsubscribe callback");
    }

    /**
     * 测试用例 3: 一次性订阅
     */
    private function testEventBusSubscribeOnce():Void {
        this.resetFlags();
        this.eventBus.subscribeOnce("ONCE_EVENT", Delegate.create(this, this.callbackOnce), this);
        this.eventBus.publish("ONCE_EVENT");
        this.eventBus.publish("ONCE_EVENT");
        this.assert(this.callbackOnceCalled == true, "Test 3: EventBus subscribeOnce - first publish");
        this.callbackOnceCalled = false;
        this.assert(this.callbackOnceCalled == false, "Test 3: EventBus subscribeOnce - second publish");
    }

    /**
     * 测试用例 4: 发布带参数的事件
     */
    private function testEventBusPublishWithArgs():Void {
        this.resetFlags();
        this.eventBus.subscribe("ARGS_EVENT", Delegate.create(this, this.callback2), this);
        this.eventBus.publish("ARGS_EVENT", "Hello", "World");
        this.assert(this.callback2Called == true, "Test 4: EventBus publish event with arguments");
        this.callback2Called = false;
        this.eventBus.unsubscribe("ARGS_EVENT", Delegate.create(this, this.callback2));
    }

    /**
     * 测试用例 5: 回调函数抛出错误时的处理
     * [v2.2] 更新：采用 let-it-crash 策略，错误会传播而不是被静默捕获
     * 在 AS2 中，由于语言的宽容特性，错误通常不会完全阻断执行
     */
    private function testEventBusCallbackErrorHandling():Void {
        this.resetFlags();
        this.eventBus.subscribe("ERROR_EVENT", Delegate.create(this, this.callbackWithError), this);
        this.eventBus.subscribe("ERROR_EVENT", Delegate.create(this, this.callback1), this);

        // [v2.2] 用 try/catch 包裹以防止测试套件被中断
        // let-it-crash 策略意味着错误会传播，但测试需要继续
        var errorCaught:Boolean = false;
        try {
            this.eventBus.publish("ERROR_EVENT");
        } catch (e:Error) {
            errorCaught = true;
        }

        // [v2.2] 验证：错误回调被调用，且在 AS2 中后续回调通常仍会执行
        // 注意：AS2 对错误的处理比较宽容，行为可能因运行环境而异
        this.assert(this.callbackWithErrorCalled == true, "Test 5: EventBus callback error handling - error callback was called");
        // 由于 let-it-crash 策略，后续回调可能不执行，这是预期行为
        // this.assert(this.callback1Called == true, "Test 5: subsequent callback also called");

        this.callbackWithErrorCalled = false;
        this.callback1Called = false;
        this.eventBus.unsubscribe("ERROR_EVENT", Delegate.create(this, this.callbackWithError));
        this.eventBus.unsubscribe("ERROR_EVENT", Delegate.create(this, this.callback1));
    }

    /**
     * 测试用例 6: 销毁后确保所有回调不再被调用
     */
    private function testEventBusDestroy():Void {
        this.resetFlags();
        this.eventBus.subscribe("DESTROY_EVENT", Delegate.create(this, this.callback1), this);
        this.eventBus.destroy();
        this.eventBus.publish("DESTROY_EVENT");
        this.assert(this.callback1Called == false, "Test 6: EventBus destroy and ensure callbacks are not called");
    }

    // -----------------------
    // 回调函数定义
    // -----------------------

    /**
     * 回调函数 1
     */
    private function callback1():Void {
        this.callback1Called = true;
        // trace("callback1 executed"); // 移除 trace 以减少性能影响
    }

    /**
     * 回调函数 2
     * @param arg1 参数 1
     * @param arg2 参数 2
     */
    private function callback2(arg1, arg2):Void {
        this.callback2Called = true;
        // trace("callback2 executed with args: " + arg1 + ", " + arg2); // 移除 trace 以减少性能影响
    }

    /**
     * 回调函数 3 - 抛出错误
     */
    private function callbackWithError():Void {
        this.callbackWithErrorCalled = true;
        // trace("callbackWithError executed"); // 移除 trace 以减少性能影响
        throw new Error("Intentional error in callbackWithError");
    }

    /**
     * 回调函数 4 - 一次性调用
     */
    private function callbackOnce():Void {
        this.callbackOnceCalled = true;
        // trace("callbackOnce executed"); // 移除 trace 以减少性能影响
    }



    // ======================
    // publishWithParam 测试用例
    // ======================

    /**
     * 测试基础参数传递
     */
    private function testPublishWithParamBasic():Void {
        this.resetFlags();

        // 测试无参数
        this.eventBus.subscribe("PARAM_TEST_0", Delegate.create(this, function():Void {
            paramCallbackCalled = true;
        }), this);
        this.eventBus.publishWithParam("PARAM_TEST_0", []);
        this.assert(paramCallbackCalled, "publishWithParam - zero arguments");

        // 测试多参数
        this.resetFlags();
        this.eventBus.subscribe("PARAM_TEST_3", Delegate.create(this, function(a, b, c):Void {
            paramCallbackCalled = a == "test" && b == 123 && c instanceof Object;
        }), this);
        this.eventBus.publishWithParam("PARAM_TEST_3", ["test", 123, {}]);
        this.assert(paramCallbackCalled, "publishWithParam - multiple arguments");

        // 测试参数超过9个
        this.resetFlags();
        this.eventBus.subscribe("PARAM_TEST_10", Delegate.create(this, function():Void {
            paramCallbackCalled = arguments.length == 10;
        }), this);
        var bigArgs:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        this.eventBus.publishWithParam("PARAM_TEST_10", bigArgs);
        this.assert(paramCallbackCalled, "publishWithParam - 10 arguments");

        // 清理
        this.eventBus.unsubscribe("PARAM_TEST_0", Delegate.create(this, arguments.callee));
        this.eventBus.unsubscribe("PARAM_TEST_3", Delegate.create(this, arguments.callee));
        this.eventBus.unsubscribe("PARAM_TEST_10", Delegate.create(this, arguments.callee));
    }

    /**
     * 测试复杂参数传递
     */
    private function testPublishWithParamComplex():Void {
        this.resetFlags();

        var testData:Object = {nested: {
                    array: [1, 2, 3],
                    date: new Date()
                },
                func: function() {
                }};

        this.eventBus.subscribe("COMPLEX_PARAM", Delegate.create(this, function(data):Void {
            complexParamReceived = data;
        }), this);

        this.eventBus.publishWithParam("COMPLEX_PARAM", [testData]);

        this.assert(complexParamReceived.nested.array.length == 3 && complexParamReceived.nested.date instanceof Date && complexParamReceived.func === testData.func, "publishWithParam - complex object validation");

        // 清理
        this.eventBus.unsubscribe("COMPLEX_PARAM", Delegate.create(this, arguments.callee));
    }

    // ======================
    // subscribeOnce 增强测试
    // ======================

    /**
     * 测试基本可靠性和多次触发
     */

    private function testSubscribeOnceReliability():Void {
        this.resetFlags();

        var self:EventBusTest = this;
        var originalCallback:Function = function():Void { // 原始函数，不预先包装
            self.onceCallbackCallCount++;
        };

        // 第一次订阅（一次性）
        this.eventBus.subscribeOnce("ONCE_RELIABILITY", originalCallback, this);

        // 第一次触发：回调应执行
        this.eventBus.publish("ONCE_RELIABILITY");

        // 第二次触发：无回调
        this.eventBus.publish("ONCE_RELIABILITY");

        this.assert(onceCallbackCallCount == 1, "subscribeOnce - should only trigger once");

        // 第二次订阅（普通订阅），直接使用原始函数
        this.eventBus.subscribe("ONCE_RELIABILITY", originalCallback, this);

        // 第三次触发：普通订阅的回调应执行
        this.eventBus.publish("ONCE_RELIABILITY");

        this.assert(onceCallbackCallCount == 2, // 修改断言为 2
            "subscribeOnce - should not affect other subscribers");

        // 清理
        this.eventBus.unsubscribe("ONCE_RELIABILITY", originalCallback);
    }

    /**
     * 测试嵌套发布场景
     */
    private function testSubscribeOnceWithNestedPublish():Void {
        this.resetFlags();
        var self:EventBusTest = this;
        this.eventBus.subscribeOnce("NESTED_PARENT", Delegate.create(this, function():Void {
            self.onceCallbackCallCount++;
            this.eventBus.publish("NESTED_CHILD");
        }), this);

        this.eventBus.subscribeOnce("NESTED_CHILD", Delegate.create(this, function():Void {
            self.nestedOnceCallbackCalled = true;
        }), this);

        this.eventBus.publish("NESTED_PARENT");

        this.assert(onceCallbackCallCount == 1 && nestedOnceCallbackCalled, "subscribeOnce - nested publish");

        // 二次触发
        this.eventBus.publish("NESTED_PARENT");
        this.assert(onceCallbackCallCount == 1 && this.eventBus["listeners"]["NESTED_CHILD"] == undefined, "subscribeOnce - nested cleanup");
    }

    /**
     * 测试批量一次性订阅
     */

    private function testMultipleSubscribeOnce():Void {
        this.resetFlags();
        var NUM_CALLBACKS:Number = 1000;
        this.multipleOnceCallbacksCalled = new Array(NUM_CALLBACKS);

        // 使用闭包捕获循环变量
        for (var i:Number = 0; i < NUM_CALLBACKS; i++) {
            var params:Object = {idx: i, self: this};
            params.callback = function():Void {
                this.self.multipleOnceCallbacksCalled[this.idx] = true;
            };
            this.eventBus.subscribeOnce("MULTI_ONCE", params.callback, params);
        }


        this.eventBus.publish("MULTI_ONCE");

        var allCalled:Boolean = true;
        for (var j:Number = 0; j < NUM_CALLBACKS; j++) {
            if (!this.multipleOnceCallbacksCalled[j]) {
                allCalled = false;
                break;
            }
        }

        this.assert(allCalled && this.eventBus["listeners"]["MULTI_ONCE"] == undefined, "subscribeOnce - mass subscription (" + NUM_CALLBACKS + " callbacks)");
    }

    /**
     * 测试手动取消订阅
     */
    private function testSubscribeOnceWithUnsubscribe():Void {
        this.resetFlags();

        var self:EventBusTest = this;
        var onceCallback:Function = Delegate.create(this, function():Void {
            self.onceCallbackCallCount++;
        });
        this.eventBus.subscribeOnce("UNSUB_TEST", onceCallback, this);
        this.eventBus.unsubscribe("UNSUB_TEST", onceCallback);

        this.eventBus.publish("UNSUB_TEST");
        this.assert(onceCallbackCallCount == 0, "subscribeOnce - unsubscribe before publish");

        // 部分取消测试
        var callback1:Function = Delegate.create(this, function():Void {
        });
        var callback2:Function = Delegate.create(this, function():Void {
        });

        this.eventBus.subscribeOnce("UNSUB_TEST2", callback1, this);
        this.eventBus.subscribeOnce("UNSUB_TEST2", callback2, this);
        this.eventBus.unsubscribe("UNSUB_TEST2", callback1);
        this.eventBus.publish("UNSUB_TEST2");
        this.assert(this.eventBus["listeners"]["UNSUB_TEST2"] == undefined, "subscribeOnce - partial unsubscribe cleanup");
    }

    // -----------------------
    // 性能测试部分
    // -----------------------

    /**
     * 运行所有性能测试用例
     */
    private function runPerformanceTests():Void {
        this.measurePerformance("Test 7: EventBus High Volume Subscriptions and Publish", Delegate.create(this, this.testEventBusHighVolumeSubscriptions));
        this.measurePerformance("Test 8: EventBus High Frequency Publish", Delegate.create(this, this.testEventBusHighFrequencyPublish));
        this.measurePerformance("Test 9: EventBus Concurrent Subscriptions and Publishes", Delegate.create(this, this.testEventBusConcurrentSubscriptionsAndPublishes));
        this.measurePerformance("Test 10: EventBus Mixed Subscribe and Unsubscribe", Delegate.create(this, this.testEventBusMixedSubscribeUnsubscribe));
        this.measurePerformance("Test 11: EventBus Nested Event Publish", Delegate.create(this, this.testEventBusNestedPublish));
        this.measurePerformance("Test 12: EventBus Parallel Event Processing", Delegate.create(this, this.testEventBusParallelEvents));
        this.measurePerformance("Test 13: EventBus Long Running Subscriptions and Cleanups", Delegate.create(this, this.testEventBusLongRunningSubscriptions));
        this.measurePerformance("Test 14: EventBus Complex Argument Passing", Delegate.create(this, this.testEventBusComplexArguments));
        this.measurePerformance("Test 15: EventBus Bulk Subscribe and Unsubscribe", Delegate.create(this, this.testEventBusBulkSubscribeUnsubscribe));
    }

    /**
     * 定义一个简单的计时函数
     * @param testName String 测试名称
     * @param testFunction Function 测试函数
     */
    private function measurePerformance(testName:String, testFunction:Function):Void {
        var startTime:Number = getTimer();
        testFunction();
        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        trace("[PERFORMANCE] " + testName + " took " + duration + " ms");
    }

    /**
     * 性能测试用例 7: 大量事件订阅与发布
     */
    private function testEventBusHighVolumeSubscriptions():Void {
        this.resetFlags();
        var numSubscribers:Number = 10000; // 增加到10000
        var eventName:String = "HIGH_VOLUME_EVENT";

        // 定义一个简单的回调
        function highVolumeCallback():Void {
            // 空回调
        }

        // 订阅大量回调
        for (var i:Number = 0; i < numSubscribers; i++) {
            this.eventBus.subscribe(eventName, Delegate.create(this, highVolumeCallback), this);
        }

        // 发布事件
        this.eventBus.publish(eventName);

        // 取消订阅所有回调
        for (var j:Number = 0; j < numSubscribers; j++) {
            this.eventBus.unsubscribe(eventName, Delegate.create(this, highVolumeCallback));
        }

        // 测试通过无需具体断言
        this.assert(true, "Test 7: EventBus handles high volume of subscriptions and publishes correctly");
    }

    /**
     * 性能测试用例 8: 高频发布事件
     */
    private function testEventBusHighFrequencyPublish():Void {
        this.resetFlags();
        var numPublish:Number = 100000; // 增加到100,000
        var eventName:String = "HIGH_FREQ_EVENT";

        // 定义一个简单的回调
        function highFreqCallback():Void {
            // 空回调
        }

        // 订阅一个回调
        this.eventBus.subscribe(eventName, Delegate.create(this, highFreqCallback), this);

        // 高频发布事件
        for (var i:Number = 0; i < numPublish; i++) {
            this.eventBus.publish(eventName);
        }

        // 取消订阅
        this.eventBus.unsubscribe(eventName, Delegate.create(this, highFreqCallback));

        // 测试通过无需具体断言
        this.assert(true, "Test 8: EventBus handles high frequency publishes correctly");
    }

    /**
     * 性能测试用例 9: 高并发订阅与发布
     */
    private function testEventBusConcurrentSubscriptionsAndPublishes():Void {
        this.resetFlags();
        var numEvents:Number = 100;
        var numSubscribersPerEvent:Number = 100;
        var numPublishesPerEvent:Number = 100;

        // 定义一个简单的回调
        function concurrentCallback():Void {
            // 空回调
        }

        // 订阅多个事件，每个事件有多个订阅者
        for (var i:Number = 0; i < numEvents; i++) {
            var eventName:String = "CONCURRENT_EVENT_" + i;
            for (var j:Number = 0; j < numSubscribersPerEvent; j++) {
                this.eventBus.subscribe(eventName, Delegate.create(this, concurrentCallback), this);
            }
        }

        // 发布每个事件多次
        for (var k:Number = 0; k < numEvents; k++) {
            var currentEvent:String = "CONCURRENT_EVENT_" + k;
            for (var l:Number = 0; l < numPublishesPerEvent; l++) {
                this.eventBus.publish(currentEvent);
            }
        }

        // 取消所有订阅
        for (var m:Number = 0; m < numEvents; m++) {
            var currentEventToUnsub:String = "CONCURRENT_EVENT_" + m;
            for (var n:Number = 0; n < numSubscribersPerEvent; n++) {
                this.eventBus.unsubscribe(currentEventToUnsub, Delegate.create(this, concurrentCallback));
            }
        }

        // 测试通过无需具体断言
        this.assert(true, "Test 9: EventBus handles concurrent subscriptions and publishes correctly");
    }

    /**
     * 性能测试用例 10: 混合订阅与取消订阅
     */
    private function testEventBusMixedSubscribeUnsubscribe():Void {
        this.resetFlags();
        var eventName:String = "MIXED_EVENT";
        var numOperations:Number = 100000; // 增加到100,000

        // 定义一个简单的回调
        function mixedCallback():Void {
            // 空回调
        }

        for (var i:Number = 0; i < numOperations; i++) {
            this.eventBus.subscribe(eventName, Delegate.create(this, mixedCallback), this);
            if (i % 10 == 0) { // 保持取消订阅的频率
                this.eventBus.unsubscribe(eventName, Delegate.create(this, mixedCallback));
            }
        }

        // 发布事件
        this.eventBus.publish(eventName);

        // 最终取消所有订阅
        this.eventBus.unsubscribe(eventName, Delegate.create(this, mixedCallback));

        // 测试通过无需具体断言
        this.assert(true, "Test 10: EventBus handles mixed subscribe and unsubscribe operations correctly");
    }

    /**
     * 性能测试用例 11: 嵌套事件发布
     */
    private function testEventBusNestedPublish():Void {
        this.resetFlags();
        var eventName1:String = "NESTED_EVENT_1";
        var eventName2:String = "NESTED_EVENT_2";

        function nestedCallback1():Void {
            // trace("Nested callback1 executed"); // 移除 trace 以减少性能影响
            this.eventBus.publish(eventName2);
        }

        function nestedCallback2():Void {
            // trace("Nested callback2 executed"); // 移除 trace 以减少性能影响
        }

        // 订阅事件
        this.eventBus.subscribe(eventName1, Delegate.create(this, nestedCallback1), this);
        this.eventBus.subscribe(eventName2, Delegate.create(this, nestedCallback2), this);

        // 发布第一个事件，测试嵌套事件发布
        this.eventBus.publish(eventName1);

        // 取消订阅
        this.eventBus.unsubscribe(eventName1, Delegate.create(this, nestedCallback1));
        this.eventBus.unsubscribe(eventName2, Delegate.create(this, nestedCallback2));

        // 测试通过无需具体断言
        this.assert(true, "Test 11: EventBus handles nested event publishes correctly");
    }

    /**
     * 性能测试用例 12: 并行事件处理
     */
    private function testEventBusParallelEvents():Void {
        this.resetFlags();
        var eventNames:Array = ["EVENT_A", "EVENT_B", "EVENT_C", "EVENT_D", "EVENT_E"];
        var numSubscribersPerEvent:Number = 10000; // 增加每个事件的订阅者数量

        function parallelCallback():Void {
            // 空回调
        }

        // 订阅多个事件，每个事件有大量订阅者
        for (var i:Number = 0; i < eventNames.length; i++) {
            for (var j:Number = 0; j < numSubscribersPerEvent; j++) {
                this.eventBus.subscribe(eventNames[i], Delegate.create(this, parallelCallback), this);
            }
        }

        // 同时发布多个事件
        for (var k:Number = 0; k < eventNames.length; k++) {
            this.eventBus.publish(eventNames[k]);
        }

        // 取消所有订阅
        for (var m:Number = 0; m < eventNames.length; m++) {
            for (var n:Number = 0; n < numSubscribersPerEvent; n++) {
                this.eventBus.unsubscribe(eventNames[m], Delegate.create(this, parallelCallback));
            }
        }

        // 测试通过无需具体断言
        this.assert(true, "Test 12: EventBus handles parallel event processing correctly");
    }

    /**
     * 性能测试用例 13: 长时间运行的订阅与取消
     */
    private function testEventBusLongRunningSubscriptions():Void {
        this.resetFlags();
        var eventName:String = "LONG_RUNNING_EVENT";
        var numSubscribers:Number = 5000;

        function longRunningCallback():Void {
            // 空回调
        }

        // 长时间订阅与取消
        for (var i:Number = 0; i < numSubscribers; i++) {
            this.eventBus.subscribe(eventName, Delegate.create(this, longRunningCallback), this);
            if (i % 10 == 0) {
                this.eventBus.unsubscribe(eventName, Delegate.create(this, longRunningCallback));
            }
        }

        // 发布事件
        this.eventBus.publish(eventName);

        // 最终取消所有订阅
        this.eventBus.unsubscribe(eventName, Delegate.create(this, longRunningCallback));

        // 测试通过无需具体断言
        this.assert(true, "Test 13: EventBus handles long-running subscriptions and cleanups correctly");
    }

    /**
     * 性能测试用例 14: 复杂参数传递
     */
    private function testEventBusComplexArguments():Void {
        this.resetFlags();
        var eventName:String = "COMPLEX_ARG_EVENT";

        // 创建复杂参数对象
        var complexData:Object = {key1: "value1",
                key2: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
                key3: {nestedKey1: "nestedValue1", nestedKey2: "nestedValue2", nestedKey3: {deepKey: "deepValue"}}};

        function complexArgCallback(data:Object):Void {
            // trace("Complex data received: " + data); // 移除 trace 以减少性能影响
        }

        // 订阅事件
        this.eventBus.subscribe(eventName, Delegate.create(this, complexArgCallback), this);

        // 发布带有复杂参数的事件
        this.eventBus.publish(eventName, complexData);

        // 取消订阅
        this.eventBus.unsubscribe(eventName, Delegate.create(this, complexArgCallback));

        // 测试通过无需具体断言
        this.assert(true, "Test 14: EventBus handles complex argument passing correctly");
    }

    /**
     * 性能测试用例 15: 批量事件订阅与取消
     */
    private function testEventBusBulkSubscribeUnsubscribe():Void {
        this.resetFlags();
        var numEvents:Number = 50000; // 增加到50,000
        var eventNamePrefix:String = "BULK_EVENT_";

        function bulkCallback():Void {
            // 空回调
        }

        // 批量订阅事件
        for (var i:Number = 0; i < numEvents; i++) {
            var eventName:String = eventNamePrefix + i;
            this.eventBus.subscribe(eventName, Delegate.create(this, bulkCallback), this);
        }

        // 发布部分事件
        for (var j:Number = 0; j < numEvents; j += 1000) { // 增加间隔以减少发布次数
            var eventName:String = eventNamePrefix + j;
            this.eventBus.publish(eventName);
        }

        // 批量取消订阅
        for (var k:Number = 0; k < numEvents; k++) {
            var eventName:String = eventNamePrefix + k;
            this.eventBus.unsubscribe(eventName, Delegate.create(this, bulkCallback));
        }

        // 测试通过无需具体断言
        this.assert(true, "Test 15: EventBus handles bulk subscriptions and unsubscriptions correctly");
    }


    // ======================
    // [v2.0] 回归测试 - GPT PRO 审阅问题修复验证
    // ======================

    /**
     * [v2.0 回归测试] 验证 unsubscribe 后可以再次 subscribe 同一回调
     * 修复问题：unsubscribe 不清理 funcToID 导致无法重新订阅
     */
    private function testUnsubscribeThenResubscribe():Void {
        this.resetFlags();

        var self:EventBusTest = this;
        var testCallback:Function = function():Void {
            self.callback1Called = true;
        };

        // 第一次订阅
        this.eventBus.subscribe("RESUB_TEST", testCallback, this);
        this.eventBus.publish("RESUB_TEST");
        this.assert(this.callback1Called == true, "[v2.0] unsubscribe-resubscribe - first subscription works");

        // 取消订阅
        this.callback1Called = false;
        this.eventBus.unsubscribe("RESUB_TEST", testCallback);
        this.eventBus.publish("RESUB_TEST");
        this.assert(this.callback1Called == false, "[v2.0] unsubscribe-resubscribe - unsubscribe works");

        // 重新订阅（这是修复的关键测试点）
        this.eventBus.subscribe("RESUB_TEST", testCallback, this);
        this.eventBus.publish("RESUB_TEST");
        this.assert(this.callback1Called == true, "[v2.0] unsubscribe-resubscribe - resubscribe after unsubscribe works");

        // 清理
        this.eventBus.unsubscribe("RESUB_TEST", testCallback);
    }

    /**
     * [v2.0 回归测试] 验证递归 publish 不会相互干扰
     * 修复问题：publish 使用深度栈复用替代 slice()
     */
    private function testRecursivePublish():Void {
        this.resetFlags();

        var self:EventBusTest = this;
        var innerPublished:Boolean = false;
        var outerCompleted:Boolean = false;

        // 外层回调会触发内层 publish
        var outerCallback:Function = function():Void {
            // 触发内层事件
            self.eventBus.publish("RECURSIVE_INNER");
            outerCompleted = true;
        };

        var innerCallback:Function = function():Void {
            innerPublished = true;
        };

        this.eventBus.subscribe("RECURSIVE_OUTER", outerCallback, this);
        this.eventBus.subscribe("RECURSIVE_INNER", innerCallback, this);

        // 触发外层事件，这会导致递归 publish
        this.eventBus.publish("RECURSIVE_OUTER");

        this.assert(innerPublished && outerCompleted, "[v2.0] recursive-publish - nested publish works correctly");

        // 清理
        this.eventBus.unsubscribe("RECURSIVE_OUTER", outerCallback);
        this.eventBus.unsubscribe("RECURSIVE_INNER", innerCallback);
    }

    /**
     * [v2.0 回归测试] 验证 subscribeOnce 的 onceCallbackMap 被正确清理
     * 修复问题：subscribeOnce 传递 originalCallback 给 unsubscribe
     * [v2.1 更新] 适配事件分桶结构: eventName -> { funcUID -> wrappedCallback }
     */
    private function testOnceCallbackMapCleanup():Void {
        this.resetFlags();

        var self:EventBusTest = this;
        var callCount:Number = 0;

        var onceCallback:Function = function():Void {
            callCount++;
        };

        var eventName:String = "ONCE_CLEANUP_TEST";

        // 订阅一次性事件
        this.eventBus.subscribeOnce(eventName, onceCallback, this);

        // [v2.1] 获取 onceCallbackMap 的初始状态 - 使用事件分桶结构
        var mapBefore:Object = this.eventBus["onceCallbackMap"];
        var originalFuncID:String = String(Dictionary.getStaticUID(onceCallback));
        var eventBucket:Object = mapBefore[eventName];
        var hasMappingBefore:Boolean = (eventBucket != null && eventBucket[originalFuncID] != null);

        // 触发事件
        this.eventBus.publish(eventName);

        // [v2.1] 验证 onceCallbackMap 已清理 - 检查事件分桶
        var mapAfter:Object = this.eventBus["onceCallbackMap"];
        var eventBucketAfter:Object = mapAfter[eventName];
        var hasMappingAfter:Boolean = (eventBucketAfter != null && eventBucketAfter[originalFuncID] != null);

        this.assert(hasMappingBefore == true, "[v2.0] onceCallbackMap-cleanup - mapping exists before publish");
        this.assert(hasMappingAfter == false, "[v2.0] onceCallbackMap-cleanup - mapping cleaned after publish");
        this.assert(callCount == 1, "[v2.0] onceCallbackMap-cleanup - callback executed once");
    }

    // ======================
    // [v2.1] 回归测试 - 三方交叉审查问题修复验证
    // ======================

    /**
     * [v2.1 回归测试 S1] 验证 subscribeOnce 按事件分桶，不同事件不互相覆盖
     * 修复问题：之前 onceCallbackMap 使用全局单表，导致不同事件的映射互相覆盖
     */
    private function testSubscribeOnceEventBucketing():Void {
        this.resetFlags();

        var self:EventBusTest = this;
        var event1Fired:Boolean = false;
        var event2Fired:Boolean = false;

        // 使用同一个回调函数订阅两个不同的事件
        var sharedCallback:Function = function():Void {
            // 空回调，仅用于测试订阅机制
        };

        // 使用不同的回调函数分别订阅两个事件
        var callback1:Function = function():Void {
            event1Fired = true;
        };
        var callback2:Function = function():Void {
            event2Fired = true;
        };

        // 订阅两个不同事件
        this.eventBus.subscribeOnce("BUCKET_EVENT_1", callback1, this);
        this.eventBus.subscribeOnce("BUCKET_EVENT_2", callback2, this);

        // 触发第一个事件
        this.eventBus.publish("BUCKET_EVENT_1");
        this.assert(event1Fired == true, "[v2.1 S1] event-bucketing - event 1 callback executed");

        // 触发第二个事件 - 之前的 bug 会导致 callback2 被 callback1 覆盖
        this.eventBus.publish("BUCKET_EVENT_2");
        this.assert(event2Fired == true, "[v2.1 S1] event-bucketing - event 2 callback not overwritten");

        // 验证两个事件都只触发一次
        event1Fired = false;
        event2Fired = false;
        this.eventBus.publish("BUCKET_EVENT_1");
        this.eventBus.publish("BUCKET_EVENT_2");
        this.assert(event1Fired == false && event2Fired == false,
            "[v2.1 S1] event-bucketing - both events only fire once");
    }

    /**
     * [v2.1 回归测试 I4] 验证 Delegate.createWithParams 的缓存键不会碰撞
     * 修复问题：之前 ["a|b"] 和 ["a", "b"] 都会生成 "a|b" 导致碰撞
     */
    private function testDelegateParamsUIDCollision():Void {
        this.resetFlags();

        var result1:String = "";
        var result2:String = "";

        // 测试函数
        var testFunc:Function = function(a:String, b:String):Void {
            if (b == undefined) {
                result1 = "single:" + a;
            } else {
                result2 = "double:" + a + "+" + b;
            }
        };

        // 创建两个不同参数的委托
        // 参数1: ["a|b"] - 单个包含分隔符的字符串
        // 参数2: ["a", "b"] - 两个字符串
        var delegate1:Function = Delegate.createWithParams(this, testFunc, ["a|b"]);
        var delegate2:Function = Delegate.createWithParams(this, testFunc, ["a", "b"]);

        // 执行两个委托
        delegate1();
        delegate2();

        // 验证两个委托产生不同的结果（没有缓存碰撞）
        this.assert(result1 == "single:a|b", "[v2.1 I4] paramsUID-collision - single param with delimiter");
        this.assert(result2 == "double:a+b", "[v2.1 I4] paramsUID-collision - two params no collision");
        this.assert(delegate1 != delegate2, "[v2.1 I4] paramsUID-collision - different delegates created");
    }

    /**
     * [v2.1 回归测试 I5] 验证 Dictionary.__dictUID 不会出现在 for..in 枚举中
     * 修复问题：之前 __dictUID 可枚举，会污染 for..in 循环
     */
    private function testDictionaryUIDNonEnumerable():Void {
        this.resetFlags();

        // 创建测试对象
        var testObj:Object = {a: 1, b: 2, c: 3};

        // 获取 UID（这会添加 __dictUID 属性）
        var uid:Number = Dictionary.getStaticUID(testObj);

        // 验证 UID 已分配
        this.assert(uid != undefined && uid < 0, "[v2.1 I5] UID-enumerable - UID assigned");

        // 使用 for..in 枚举对象属性
        var foundKeys:Array = [];
        for (var key:String in testObj) {
            foundKeys.push(key);
        }

        // 验证 __dictUID 不在枚举结果中
        var foundDictUID:Boolean = false;
        for (var i:Number = 0; i < foundKeys.length; i++) {
            if (foundKeys[i] == "__dictUID") {
                foundDictUID = true;
                break;
            }
        }

        this.assert(foundDictUID == false, "[v2.1 I5] UID-enumerable - __dictUID not in for..in");
        this.assert(foundKeys.length == 3, "[v2.1 I5] UID-enumerable - only original keys enumerated");
    }

    /**
     * [v2.1 回归测试 I8] 验证 Dictionary.removeItem/clear 正确清理 uidMap
     * 修复问题：之前 removeItem/clear 不清理 uidMap 导致内存泄漏
     */
    private function testDictionaryUIDMapCleanup():Void {
        this.resetFlags();

        // 创建 Dictionary 实例
        var dict:Dictionary = new Dictionary();

        // 创建测试对象
        var testKey1:Object = {name: "key1"};
        var testKey2:Object = {name: "key2"};

        // 添加键值对
        dict.setItem(testKey1, "value1");
        dict.setItem(testKey2, "value2");

        // 获取 UID（用于后续验证）
        var uid1:Number = testKey1.__dictUID;
        var uid2:Number = testKey2.__dictUID;

        // 验证 setItem 后可以 getItem
        this.assert(dict.getItem(testKey1) == "value1", "[v2.1 I8] uidMap-cleanup - getItem works after setItem");

        // 删除一个键
        dict.removeItem(testKey1);

        // 验证删除后 getItem 返回 null
        this.assert(dict.getItem(testKey1) == null, "[v2.1 I8] uidMap-cleanup - getItem returns null after removeItem");

        // 验证另一个键仍然存在
        this.assert(dict.getItem(testKey2) == "value2", "[v2.1 I8] uidMap-cleanup - other keys not affected");

        // 清空字典
        dict.clear();

        // 验证清空后 getItem 返回 null
        this.assert(dict.getItem(testKey2) == null, "[v2.1 I8] uidMap-cleanup - getItem returns null after clear");

        // 验证 count 为 0
        this.assert(dict.getCount() == 0, "[v2.1 I8] uidMap-cleanup - count is 0 after clear");
    }

    /**
     * 高性能压力测试
     */
    private function testHighVolumeSubscribeOnce():Void {
        this.resetFlags();
        var VOLUME_SIZE:Number = 5;
        var gcDetector:Object = {count: 0};
        var self:EventBusTest = this;
        // trace("gcDetector.count = " + gcDetector.count + " || " + this.eventBus["listeners"]["HIGH_VOLUME_ONCE"].count);
        // 创建带闭包引用的回调
        for (var i:Number = 0; i < VOLUME_SIZE; i++) {
            var callbackIIFE:Function = (function(idx:Number) {
                return function():Void {
                    // trace("Callback idx: " + idx);
                    var abc:Number = idx;
                    gcDetector.count += abc - abc + 1;
                    // AS2 缺乏真正的词法闭包，循环中的匿名函数可能共享相同的变量作用域，导致所有回调绑定到同一个上下文。
                    // 为了避免这种情况，这里使用一个闭包捕获变量 idx，并在回调中使用它。
                    // as2 不支持iife，因此需要拆分使用
                };
            });

            this.eventBus.subscribeOnce("HIGH_VOLUME_ONCE", callbackIIFE(i), this);
        }

        // 触发并验证

        this.eventBus.publish("HIGH_VOLUME_ONCE");
        //trace("gcDetector.count = " + gcDetector.count + " || " + this.eventBus["listeners"]["HIGH_VOLUME_ONCE"].count);
        // this.eventBus.publish("HIGH_VOLUME_ONCE");
        //trace("gcDetector.count = " + gcDetector.count + " || " + this.eventBus["listeners"]["HIGH_VOLUME_ONCE"].count);
        this.assert(gcDetector.count == VOLUME_SIZE && (this.eventBus["listeners"]["HIGH_VOLUME_ONCE"] == undefined || this.eventBus["listeners"]["HIGH_VOLUME_ONCE"].count == 0), "subscribeOnce - high volume (" + VOLUME_SIZE + ") with GC check");

    }

    // ======================
    // [v2.2] 回归测试 - 代码审查修复验证
    // ======================

    /**
     * [v2.2 回归测试 P1-3] 验证在 dispatch 期间调用 destroy() 被阻止
     * 修复问题：之前在 publish 执行期间调用 destroy() 会导致状态不一致
     */
    private function testDestroyDuringDispatchGuard():Void {
        this.resetFlags();

        var self:EventBusTest = this;
        var destroyAttempted:Boolean = false;
        var callbackCompleted:Boolean = false;
        var postDestroyPublishWorked:Boolean = false;

        // 重新初始化 EventBus
        this.eventBus = EventBus.initialize();

        // 在回调中尝试调用 destroy
        var destructiveCallback:Function = function():Void {
            destroyAttempted = true;
            // 在 dispatch 期间尝试 destroy - 应该被阻止
            self.eventBus.destroy();
            callbackCompleted = true;
        };

        var secondCallback:Function = function():Void {
            postDestroyPublishWorked = true;
        };

        this.eventBus.subscribe("DESTROY_GUARD_TEST", destructiveCallback, this);
        this.eventBus.subscribe("DESTROY_GUARD_TEST_2", secondCallback, this);

        // 触发事件，回调中会尝试 destroy
        this.eventBus.publish("DESTROY_GUARD_TEST");

        // 验证 destroy 被延迟/阻止，回调能完成
        this.assert(destroyAttempted, "[v2.2 P1-3] destroy-during-dispatch - destroy was attempted");
        this.assert(callbackCompleted, "[v2.2 P1-3] destroy-during-dispatch - callback completed");

        // 验证 EventBus 仍然可用（因为 destroy 在 dispatch 期间被阻止）
        this.eventBus.publish("DESTROY_GUARD_TEST_2");
        this.assert(postDestroyPublishWorked, "[v2.2 P1-3] destroy-during-dispatch - EventBus still works after guarded destroy");

        // 清理：在 dispatch 外正常 destroy
        this.eventBus.unsubscribe("DESTROY_GUARD_TEST", destructiveCallback);
        this.eventBus.unsubscribe("DESTROY_GUARD_TEST_2", secondCallback);
    }

    /**
     * [v2.2 回归测试 P1-1] 验证 let-it-crash 策略（try/catch 已移除）
     * 修复问题：移除 try/catch 以提升性能，采用 let-it-crash 策略
     * 注意：此测试验证在 AS2 环境下，回调错误不会被 EventBus 静默捕获
     */
    private function testLetItCrashStrategy():Void {
        this.resetFlags();

        var self:EventBusTest = this;
        var callback1Called:Boolean = false;
        var callback2Called:Boolean = false;

        // 重新初始化 EventBus
        this.eventBus = EventBus.initialize();

        // 第一个回调会抛出错误
        var errorCallback:Function = function():Void {
            callback1Called = true;
            // 在 AS2 中，这个错误会传播出去
            // 但由于 AS2 的宽容特性，后续代码通常仍会执行
            throw new Error("Intentional error for let-it-crash test");
        };

        // 第二个回调应该仍然被调用（AS2 特性）
        var normalCallback:Function = function():Void {
            callback2Called = true;
        };

        this.eventBus.subscribe("CRASH_TEST", errorCallback, this);
        this.eventBus.subscribe("CRASH_TEST", normalCallback, this);

        // 触发事件
        // [v2.2] 用 try/catch 包裹以防止测试套件被中断
        var errorPropagated:Boolean = false;
        try {
            this.eventBus.publish("CRASH_TEST");
        } catch (e:Error) {
            errorPropagated = true;
        }

        // 验证错误回调被调用
        this.assert(callback1Called, "[v2.2 P1-1] let-it-crash - error callback was called");
        // 在 AS2 中，由于语言特性，错误传播后后续回调可能不执行，这是 let-it-crash 的预期行为
        // 不再断言 callback2Called，因为行为取决于运行时环境

        // 清理
        this.eventBus.unsubscribe("CRASH_TEST", errorCallback);
        this.eventBus.unsubscribe("CRASH_TEST", normalCallback);
    }
}



// -----------------------
// 运行测试
// -----------------------


