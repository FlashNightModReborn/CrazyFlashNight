// Import necessary classes (adjust paths if needed)
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.Event.EventBus; // Assuming EventBus might be needed for context or cleanup if static issues arise
// import org.flashNight.neur.Event.Delegate; // Not directly used in tests, but part of the system
// import org.flashNight.naki.DataStructures.Dictionary; // Not directly used in tests
import flash.utils.getTimer;

/**
 * EventDispatcherExtendedTest 类提供对 EventDispatcher 的更全面、更深入的测试。
 * 它覆盖了基础测试之外的边界情况、复杂交互和潜在的故障点，
 * 以确保 EventDispatcher 在各种场景下的健壮性和正确性。
 * (版本 2: 移除了对 EventDispatcher 私有成员的访问，并修复了 AS2 兼容性问题)
 */
class org.flashNight.neur.Event.EventDispatcherExtendedTest {
    private var dispatcher:EventDispatcher; // 待测试的 EventDispatcher 实例
    private var testResults:Array;           // 存储测试结果信息
    private var originalTrace:Function;      // Store original trace for suppression
    private var capturedTraces:Array;        // Store captured trace messages

    /**
     * 构造函数：初始化测试类和结果存储数组。
     */
    public function EventDispatcherExtendedTest() {
        this.testResults = [];
        this.capturedTraces = [];
        // Keep original trace if needed, or replace for capture
        this.originalTrace = trace;
    }

    /**
     * 运行所有扩展测试方法。
     */
    public function runAllTests():Void {
        trace("=== EventDispatcherExtendedTest 开始 ===");

        // --- Setup for trace capture ---
        var self = this;
        // Temporarily override trace to capture warnings
        trace = function(msg) {
            self.capturedTraces.push(msg);
            self.originalTrace(msg); // Also output normally
        };

        // --- Run Extended Tests ---
        this.testGlobalAndLocalIsolation();
        this.testSubscribeSingleInteractions();
        this.testSubscribeSingleGlobalInteractions();
        this.testDestroyWithMixedSubscriptions();
        this.testUsageAfterDestroy(); // This test now implicitly checks the destroyed state via warnings
        this.testPublishWithVariousArguments();
        this.testNullScope();
        this.testUnsubscribeEdgeCases();
        this.testReentrantPublish();
        this.testEventNameVariations(); // Updated to avoid String.repeat
        this.testSubscribeOnceComplexScenarios();
        this.testSubscribeSingleWithSameCallback();
        this.testUnsubscribeNonExistent();
        this.testDestroyIdempotency(); // Verify calling destroy multiple times is safe

        // --- Restore original trace ---
        trace = this.originalTrace;

        // --- Report Results ---
        this.reportResults();
        trace("=== EventDispatcherExtendedTest 结束 ===");
    }

    /**
     * 自定义断言方法。
     */
    private function assert(condition:Boolean, message:String):Void {
        var fullMessage = "ExtendedTest: " + message;
        if (!condition) {
            this.testResults.push({ success: false, message: fullMessage });
            this.originalTrace("Assertion Failed: " + fullMessage); // Use original trace for assertion output
        } else {
            this.testResults.push({ success: true, message: fullMessage });
            // Optionally trace success: // this.originalTrace("Assertion Passed: " + fullMessage);
        }
    }

    /**
     * 检查捕获的 trace 输出中是否包含特定警告。
     */
    private function assertTraceWarning(expectedWarning:String, message:String):Void {
        var found:Boolean = false;
        for (var i = 0; i < this.capturedTraces.length; i++) {
            // Check if the trace message is a string and contains the expected warning
            if (typeof(this.capturedTraces[i]) == "string" && this.capturedTraces[i].indexOf(expectedWarning) != -1) {
                found = true;
                break;
            }
        }
        this.assert(found, message + " (Expected warning containing: '" + expectedWarning + "')");
    }

    /**
     * 清空捕获的 trace 记录。
     */
    private function clearCapturedTraces():Void {
        this.capturedTraces = [];
    }


    /**
     * 初始化一个新的 EventDispatcher 实例。
     */
    private function initializeDispatcher():Void {
        // Ensure clean static state if EventBus has issues (less likely with instance IDs)
        // EventBus.getInstance().destroy(); // Use cautiously if EventBus needs reset
        this.dispatcher = new EventDispatcher();
        this.clearCapturedTraces(); // Clear traces for the new test
    }

    /**
     * 清理 EventDispatcher 实例。
     * 注意：不再检查 _isDestroyed，因为它是私有的。
     * destroy() 方法本身应该能安全地处理重复调用。
     */
    private function cleanupDispatcher():Void {
        if (this.dispatcher != null) {
             // Assume dispatcher.destroy() handles being called if already destroyed
             this.dispatcher.destroy();
        }
        this.dispatcher = null;
        // Consider clearing static EventBus state if necessary and safe
        // EventBus.getInstance().destroy();
    }

    // ==================================
    //      Extended Test Methods
    // ==================================

    /**
     * 测试本地事件和全局事件同名时的隔离性。
     * (此测试间接验证了实例 ID 机制的有效性)
     */
    private function testGlobalAndLocalIsolation():Void {
        this.originalTrace("--- 测试全局与本地事件隔离 ---");
        this.initializeDispatcher();
        var dispatcher2 = new EventDispatcher(); // Need a second dispatcher for isolation test

        var eventName:String = "sharedNameEvent";
        var localCallCount1:Number = 0;
        var globalCallCount1:Number = 0;
        var localCallCount2:Number = 0; // For dispatcher2

        var localCallback1:Function = function() { localCallCount1++; };
        var globalCallback1:Function = function() { globalCallCount1++; };
        var localCallback2:Function = function() { localCallCount2++; };
        var scope:Object = this;

        // Dispatcher 1 subscribes locally and globally
        this.dispatcher.subscribe(eventName, localCallback1, scope);
        this.dispatcher.subscribeGlobal(eventName, globalCallback1, scope);

        // Dispatcher 2 subscribes locally
        dispatcher2.subscribe(eventName, localCallback2, scope);

        // 1. Publish locally on dispatcher 1
        this.dispatcher.publish(eventName);
        this.assert(localCallCount1 === 1, "Isolation: Local publish on dispatcher1 should trigger its local listener.");
        this.assert(globalCallCount1 === 0, "Isolation: Local publish on dispatcher1 should NOT trigger its global listener.");
        this.assert(localCallCount2 === 0, "Isolation: Local publish on dispatcher1 should NOT trigger dispatcher2's local listener.");

        // 2. Publish globally (using dispatcher 1, but could be any or static)
        this.dispatcher.publishGlobal(eventName);
        this.assert(localCallCount1 === 1, "Isolation: Global publish should NOT trigger dispatcher1's local listener.");
        this.assert(globalCallCount1 === 1, "Isolation: Global publish should trigger dispatcher1's global listener.");
        this.assert(localCallCount2 === 0, "Isolation: Global publish should NOT trigger dispatcher2's local listener.");

        // 3. Publish locally on dispatcher 2
        dispatcher2.publish(eventName);
        this.assert(localCallCount1 === 1, "Isolation: Local publish on dispatcher2 should NOT trigger dispatcher1's local listener.");
        this.assert(globalCallCount1 === 1, "Isolation: Local publish on dispatcher2 should NOT trigger dispatcher1's global listener.");
        this.assert(localCallCount2 === 1, "Isolation: Local publish on dispatcher2 should trigger its own local listener.");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, localCallback1);
        this.dispatcher.unsubscribeGlobal(eventName, globalCallback1);
        dispatcher2.unsubscribe(eventName, localCallback2);
        this.cleanupDispatcher();
        dispatcher2.destroy(); // Clean up the second dispatcher too
    }

    /**
     * 测试 subscribeSingle 与常规 subscribe 的交互。
     */
    private function testSubscribeSingleInteractions():Void {
        this.originalTrace("--- 测试 subscribeSingle 与 subscribe 交互 ---");
        this.initializeDispatcher();

        var eventName:String = "singleInteractionEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var callCount3:Number = 0;
        var cb1:Function = function() { callCount1++; };
        var cb2:Function = function() { callCount2++; };
        var cb3:Function = function() { callCount3++; }; // Regular subscribe
        var scope:Object = this;

        // 1. subscribeSingle then subscribe
        this.dispatcher.subscribeSingle(eventName, cb1, scope);
        this.dispatcher.subscribe(eventName, cb3, scope); // Add another listener
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "SingleInteraction: subscribeSingle followed by subscribe - single listener called.");
        this.assert(callCount3 === 1, "SingleInteraction: subscribeSingle followed by subscribe - regular listener also called.");

        // 2. subscribe then subscribeSingle (should replace existing single, but not others)
        this.dispatcher.subscribeSingle(eventName, cb2, scope); // cb2 replaces cb1
        this.dispatcher.publish(eventName);
        this.assert(callCount1 === 1, "SingleInteraction: subscribe then subscribeSingle - original single listener NOT called again.");
        this.assert(callCount2 === 1, "SingleInteraction: subscribe then subscribeSingle - new single listener called.");
        this.assert(callCount3 === 2, "SingleInteraction: subscribe then subscribeSingle - regular listener still called.");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cb2);
        this.dispatcher.unsubscribe(eventName, cb3);
        this.cleanupDispatcher();
    }

     /**
     * 测试 subscribeSingleGlobal 与常规 subscribeGlobal 的交互。
     */
    private function testSubscribeSingleGlobalInteractions():Void {
        this.originalTrace("--- 测试 subscribeSingleGlobal 与 subscribeGlobal 交互 ---");
        this.initializeDispatcher();
        var dispatcher2 = new EventDispatcher(); // Use another dispatcher to publish globally

        var eventName:String = "singleGlobalInteractionEvent";
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var callCount3:Number = 0;
        var cb1:Function = function() { callCount1++; };
        var cb2:Function = function() { callCount2++; };
        var cb3:Function = function() { callCount3++; }; // Regular global subscribe
        var scope:Object = this;

        // 1. subscribeSingleGlobal then subscribeGlobal
        this.dispatcher.subscribeSingleGlobal(eventName, cb1, scope);
        this.dispatcher.subscribeGlobal(eventName, cb3, scope); // Add another global listener
        dispatcher2.publishGlobal(eventName); // Publish globally
        this.assert(callCount1 === 1, "SingleGlobalInteraction: subscribeSingleGlobal followed by subscribeGlobal - single listener called.");
        this.assert(callCount3 === 1, "SingleGlobalInteraction: subscribeSingleGlobal followed by subscribeGlobal - regular global listener also called.");

        // 2. subscribeGlobal then subscribeSingleGlobal (should replace existing single global, but not others)
        this.dispatcher.subscribeSingleGlobal(eventName, cb2, scope); // cb2 replaces cb1
        dispatcher2.publishGlobal(eventName);
        this.assert(callCount1 === 1, "SingleGlobalInteraction: subscribeGlobal then subscribeSingleGlobal - original single listener NOT called again.");
        this.assert(callCount2 === 1, "SingleGlobalInteraction: subscribeGlobal then subscribeSingleGlobal - new single listener called.");
        this.assert(callCount3 === 2, "SingleGlobalInteraction: subscribeGlobal then subscribeSingleGlobal - regular global listener still called.");

        // Cleanup
        this.dispatcher.unsubscribeGlobal(eventName, cb2);
        this.dispatcher.unsubscribeGlobal(eventName, cb3);
        this.cleanupDispatcher();
        dispatcher2.destroy();
    }

    /**
     * 测试 destroy 方法是否能正确处理本地和全局混合订阅。
     * (通过检查回调是否在 destroy 后停止触发来验证)
     */
    private function testDestroyWithMixedSubscriptions():Void {
        this.originalTrace("--- 测试 destroy 处理混合订阅 ---");
        this.initializeDispatcher();
        var dispatcher2 = new EventDispatcher(); // To check global event after destroy

        var localEvent:String = "destroyLocal";
        var globalEvent:String = "destroyGlobal";
        var localCalled:Boolean = false;
        var globalCalled:Boolean = false;
        var cbLocal:Function = function() { localCalled = true; };
        var cbGlobal:Function = function() { globalCalled = true; };
        var scope:Object = this;

        this.dispatcher.subscribe(localEvent, cbLocal, scope);
        this.dispatcher.subscribeGlobal(globalEvent, cbGlobal, scope);

        // Verify before destroy
        this.dispatcher.publish(localEvent);
        dispatcher2.publishGlobal(globalEvent); // Publish global from elsewhere
        this.assert(localCalled, "MixedDestroy: Local callback should fire before destroy.");
        this.assert(globalCalled, "MixedDestroy: Global callback should fire before destroy.");

        // Reset flags
        localCalled = false;
        globalCalled = false;

        // Destroy the dispatcher
        this.dispatcher.destroy();

        // Verify after destroy by attempting to publish and checking callbacks
        // Also check for expected warnings using the trace capture mechanism
        this.clearCapturedTraces();
        this.dispatcher.publish(localEvent); // Attempt local publish
        this.assert(!localCalled, "MixedDestroy: Local callback should NOT fire after destroy.");
        this.assertTraceWarning("called on a destroyed EventDispatcher", "MixedDestroy: Warning expected for local publish after destroy.");

        // Publish globally again (should NOT trigger the destroyed dispatcher's listener)
        dispatcher2.publishGlobal(globalEvent);
        this.assert(!globalCalled, "MixedDestroy: Global callback associated with destroyed dispatcher should NOT fire after destroy.");

        // Check if a NEW dispatcher can use the same event names without interference
        var dispatcher3 = new EventDispatcher();
        var localCalled3 = false;
        var globalCalled3 = false; // Need a global listener on dispatcher3 too
        var cbLocal3 = function() { localCalled3 = true; };
        var cbGlobal3 = function() { globalCalled3 = true; };
        dispatcher3.subscribe(localEvent, cbLocal3, scope); // Use same base name as destroyed one
        dispatcher3.subscribeGlobal(globalEvent, cbGlobal3, scope); // Use same global name

        dispatcher3.publish(localEvent);
        this.assert(localCalled3, "MixedDestroy: Subscribing to same local event name on new dispatcher should work after old one destroyed.");

        dispatcher2.publishGlobal(globalEvent); // Publish global again
        this.assert(globalCalled3, "MixedDestroy: Global listener on new dispatcher should work after old one destroyed.");
        this.assert(!globalCalled, "MixedDestroy: Destroyed dispatcher's global listener remains inactive."); // Double check


        // Cleanup
        // dispatcher is already destroyed
        dispatcher2.destroy();
        dispatcher3.unsubscribe(localEvent, cbLocal3);
        dispatcher3.unsubscribeGlobal(globalEvent, cbGlobal3);
        dispatcher3.destroy();
        // No need to call cleanupDispatcher() as it's already destroyed
        this.dispatcher = null; // Ensure it's null for subsequent tests
    }

    /**
     * 测试在 destroy 后调用 dispatcher 的方法。
     * (验证是否产生警告并且方法无效果)
     */
    private function testUsageAfterDestroy():Void {
        this.originalTrace("--- 测试 destroy 后使用 Dispatcher ---");
        this.initializeDispatcher();

        var eventName:String = "postDestroyEvent";
        var cb:Function = function() { this.assert(false, "UsageAfterDestroy: Callback should NOT be called after destroy."); };
        var scope:Object = this;
        var callCount:Number = 0;
        var cbCounter:Function = function() { callCount++; };


        // Subscribe *before* destroy to test publish later
        this.dispatcher.subscribe(eventName, cbCounter, scope);
        this.dispatcher.subscribeGlobal(eventName + "Global", cbCounter, scope);

        // Destroy it
        this.dispatcher.destroy();

        // Test methods and check for warnings AND lack of effect
        this.clearCapturedTraces();
        this.dispatcher.subscribe(eventName, cb, scope);
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for subscribe.");

        this.clearCapturedTraces();
        this.dispatcher.subscribeOnce(eventName, cb, scope);
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for subscribeOnce.");

        this.clearCapturedTraces();
        this.dispatcher.unsubscribe(eventName, cb); // Try unsubscribing a non-existent sub on destroyed dispatcher
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for unsubscribe.");

        // Test publish - should warn and NOT call the cbCounter subscribed before destroy
        callCount = 0;
        this.clearCapturedTraces();
        this.dispatcher.publish(eventName);
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for publish.");
        this.assert(callCount === 0, "UsageAfterDestroy: Publish should have no effect after destroy.");

        this.clearCapturedTraces();
        this.dispatcher.subscribeGlobal(eventName, cb, scope);
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for subscribeGlobal.");

        this.clearCapturedTraces();
        this.dispatcher.unsubscribeGlobal(eventName, cb);
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for unsubscribeGlobal.");

        // Test publishGlobal - should warn and NOT call the cbCounter subscribed before destroy
        callCount = 0;
        this.clearCapturedTraces();
        this.dispatcher.publishGlobal(eventName + "Global");
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for publishGlobal.");
        this.assert(callCount === 0, "UsageAfterDestroy: PublishGlobal should have no effect after destroy.");


        this.clearCapturedTraces();
        this.dispatcher.subscribeSingle(eventName, cb, scope);
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for subscribeSingle.");

        this.clearCapturedTraces();
        this.dispatcher.subscribeSingleGlobal(eventName, cb, scope);
        this.assertTraceWarning("called on a destroyed EventDispatcher", "UsageAfterDestroy: Warning expected for subscribeSingleGlobal.");

        // Cleanup (already destroyed)
        this.dispatcher = null;
    }

    /**
     * 测试 publish 传递 null, undefined, 和零参数。
     */
    private function testPublishWithVariousArguments():Void {
        this.originalTrace("--- 测试 publish 使用不同参数 ---");
        this.initializeDispatcher();

        var eventName:String = "argsEvent";
        var receivedArgs:Array = null; // Use null to differentiate from empty array
        var callCount:Number = 0;
        var cb:Function = function() {
            callCount++;
            // Convert arguments object to Array for easier checking
            receivedArgs = [];
            for (var i = 0; i < arguments.length; i++) {
                receivedArgs.push(arguments[i]);
            }
        };
        var scope:Object = this;
        this.dispatcher.subscribe(eventName, cb, scope);

        // 1. Publish with null
        receivedArgs = null; callCount = 0;
        this.dispatcher.publish(eventName, null);
        this.assert(callCount === 1, "PublishArgs: Callback called with null argument.");
        this.assert(receivedArgs != null && receivedArgs.length === 1, "PublishArgs: Received one argument for null publish.");
        this.assert(receivedArgs[0] === null, "PublishArgs: Received argument should be null.");

        // 2. Publish with undefined
        receivedArgs = null; callCount = 0;
        this.dispatcher.publish(eventName, undefined);
        this.assert(callCount === 1, "PublishArgs: Callback called with undefined argument.");
        this.assert(receivedArgs != null && receivedArgs.length === 1, "PublishArgs: Received one argument for undefined publish.");
        this.assert(receivedArgs[0] === undefined, "PublishArgs: Received argument should be undefined.");

        // 3. Publish with zero arguments
        receivedArgs = null; callCount = 0;
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "PublishArgs: Callback called with zero arguments.");
        this.assert(receivedArgs != null && receivedArgs.length === 0, "PublishArgs: Received zero arguments for zero-arg publish.");

        // 4. Publish with multiple mixed arguments including null/undefined
        receivedArgs = null; callCount = 0;
        var obj = { test: 1 };
        this.dispatcher.publish(eventName, 1, null, "hello", undefined, obj);
        this.assert(callCount === 1, "PublishArgs: Callback called with mixed arguments.");
        this.assert(receivedArgs != null && receivedArgs.length === 5, "PublishArgs: Received five arguments for mixed publish.");
        this.assert(receivedArgs[0] === 1 && receivedArgs[1] === null && receivedArgs[2] === "hello" && receivedArgs[3] === undefined && receivedArgs[4] === obj, "PublishArgs: Received arguments match mixed publish.");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cb);
        this.cleanupDispatcher();
    }

    /**
     * 测试使用 null 作为回调函数的作用域。
     */
    private function testNullScope():Void {
        this.originalTrace("--- 测试 null 作用域 ---");
        this.initializeDispatcher();

        var eventName:String = "nullScopeEvent";
        var scopeCheck:Object = null; // Variable to store 'this' from callback
        var cb:Function = function() {
            scopeCheck = this;
        };

        // Subscribe with null scope
        this.dispatcher.subscribe(eventName, cb, null);

        // Publish event
        this.dispatcher.publish(eventName);

        // AS2's Function.apply(null, ...) usually results in 'this' being the global object (_global)
        // We assert that it's not null/undefined, and potentially check if it's _global if needed.
        this.assert(scopeCheck !== null && scopeCheck !== undefined, "NullScope: Callback 'this' should not be null or undefined when scope is null.");
        // More specific check (might vary slightly based on exact Flash Player version/environment)
        // this.assert(scopeCheck === _global, "NullScope: Callback 'this' should be the global object when scope is null.");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cb); // Unsubscribe still needs the callback function
        this.cleanupDispatcher();
    }

    /**
     * 测试 unsubscribe 的各种边界情况。
     */
    private function testUnsubscribeEdgeCases():Void {
        this.originalTrace("--- 测试 unsubscribe 边界情况 ---");
        this.initializeDispatcher();

        var eventName:String = "unsubscribeEdgeEvent";
        var globalEventName:String = "unsubscribeGlobalEdgeEvent";
        var callCount:Number = 0;
        var cb:Function = function() { callCount++; };
        var cbGlobal:Function = function() { callCount++; };
        var scope:Object = this;

        this.dispatcher.subscribe(eventName, cb, scope);
        this.dispatcher.subscribeGlobal(globalEventName, cbGlobal, scope);

        var didError:Boolean;

        // 1. Unsubscribe with wrong event name
        didError = false;
        try {
            this.dispatcher.unsubscribe("wrongEvent", cb);
        } catch (e:Error) { didError = true; }
        this.assert(!didError, "UnsubscribeEdge: Unsubscribing with wrong event name should not error.");
        // Verify original subscription still works
        callCount = 0; this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "UnsubscribeEdge: Original subscription should persist after wrong name unsubscribe attempt.");

        // 2. Unsubscribe with wrong callback
        didError = false;
        var wrongCb:Function = function() {};
        try {
            this.dispatcher.unsubscribe(eventName, wrongCb);
        } catch (e:Error) { didError = true; }
        this.assert(!didError, "UnsubscribeEdge: Unsubscribing with wrong callback should not error.");
        // Verify original subscription still works
        callCount = 0; this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "UnsubscribeEdge: Original subscription should persist after wrong callback unsubscribe attempt.");

        // 3. Unsubscribe a local event using unsubscribeGlobal
        didError = false;
        try {
            this.dispatcher.unsubscribeGlobal(eventName, cb); // Using global method for local sub
        } catch (e:Error) { didError = true; }
        this.assert(!didError, "UnsubscribeEdge: Unsubscribing local event via unsubscribeGlobal should not error (but likely won't work).");
        // Verify original subscription still works
        callCount = 0; this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "UnsubscribeEdge: Local subscription should persist after unsubscribeGlobal attempt.");

        // 4. Unsubscribe a global event using unsubscribe
        didError = false;
        try {
            this.dispatcher.unsubscribe(globalEventName, cbGlobal); // Using local method for global sub
        } catch (e:Error) { didError = true; }
        this.assert(!didError, "UnsubscribeEdge: Unsubscribing global event via unsubscribe should not error (but likely won't work).");
        // Verify original subscription still works
        callCount = 0; this.dispatcher.publishGlobal(globalEventName);
        this.assert(callCount === 1, "UnsubscribeEdge: Global subscription should persist after unsubscribe attempt.");

        // 5. Correctly unsubscribe
        this.dispatcher.unsubscribe(eventName, cb);
        callCount = 0; this.dispatcher.publish(eventName);
        this.assert(callCount === 0, "UnsubscribeEdge: Local subscription should be removed after correct unsubscribe.");

        this.dispatcher.unsubscribeGlobal(globalEventName, cbGlobal);
        callCount = 0; this.dispatcher.publishGlobal(globalEventName);
        this.assert(callCount === 0, "UnsubscribeEdge: Global subscription should be removed after correct unsubscribeGlobal.");

        // Cleanup
        this.cleanupDispatcher();
    }

    /**
     * 测试从回调内部发布同一事件（重入）。
     */
    private function testReentrantPublish():Void {
        this.originalTrace("--- 测试重入发布 ---");
        this.initializeDispatcher();

        var eventName:String = "reentrantEvent";
        var maxCalls:Number = 5; // Limit recursion depth for test
        var callCount:Number = 0;
        var scope:Object = this;
        var self = this; // Need reference to test class instance inside callback

        var reentrantCallback:Function = function() {
            callCount++;
            if (callCount < maxCalls) {
                // Immediately publish the same event using the correct dispatcher instance
                self.dispatcher.publish(eventName);
            }
        };

        this.dispatcher.subscribe(eventName, reentrantCallback, scope);

        // Trigger the first publish
        this.dispatcher.publish(eventName);

        // Should have been called maxCalls times due to re-entrancy limit
        this.assert(callCount === maxCalls, "ReentrantPublish: Callback should be called " + maxCalls + " times due to re-entrancy.");

        // Verify it stops after maxCalls
        callCount = 0;
        this.dispatcher.publish(eventName); // Publish again from outside
        this.assert(callCount === maxCalls, "ReentrantPublish: Publishing again should re-trigger the limited re-entrancy.");


        // Cleanup
        this.dispatcher.unsubscribe(eventName, reentrantCallback);
        this.cleanupDispatcher();
    }

    /**
     * 测试使用特殊字符或空字符串作为事件名称。
     * (移除了 String.repeat 并简化了断言)
     */
    private function testEventNameVariations():Void {
        this.originalTrace("--- 测试不同的事件名称 ---");
        this.initializeDispatcher();

        // Manually create long string for AS2 compatibility
        var longNameBase = "veryLongEventName";
        var longName = "";
        for (var k=0; k<10; k++) { // Create a reasonably long string
            longName += longNameBase;
        }

        var eventNames:Array = [
            "",                         // Empty string
            "event with spaces",        // Spaces
            "event/with/slashes",       // Slashes
            "event.with.dots",          // Dots
            "event:with:colons",        // Colons (potential issue depending on internal implementation)
            "~!@#$%^&*()_+`-={}|[]\\:\";'<>?,./", // Special chars
            longName                    // Use the manually created long name
        ];
        var callCount:Number = 0;
        var cb:Function = function() { callCount++; };
        var scope:Object = this;

        for (var i = 0; i < eventNames.length; i++) {
            var eventName = eventNames[i];
            callCount = 0;
            var didError:Boolean = false;
            var currentEventNameForTrace = eventName.length > 50 ? eventName.substring(0, 50) + "..." : eventName; // Truncate long names for trace

            try {
                this.dispatcher.subscribe(eventName, cb, scope);
                this.dispatcher.publish(eventName);
                // Verify callback was called before unsubscribing
                this.assert(callCount === 1, "EventNameVariation: Callback should be called for event name '" + currentEventNameForTrace + "'.");
                this.dispatcher.unsubscribe(eventName, cb);
                // Verify callback is not called after unsubscribing
                callCount = 0;
                this.dispatcher.publish(eventName);
                this.assert(callCount === 0, "EventNameVariation: Callback should NOT be called after unsubscribe for event name '" + currentEventNameForTrace + "'.");

            } catch (e:Error) {
                didError = true;
                this.originalTrace("Error during test for event name: '" + currentEventNameForTrace + "' - " + e.toString());
            }
            this.assert(!didError, "EventNameVariation: Using event name '" + currentEventNameForTrace + "' should not cause runtime errors.");

             // Add a note about potential colon issues without asserting based on private details
            if (typeof(eventName) == "string" && eventName.indexOf(":") != -1) {
                this.originalTrace("Note: Event name '" + currentEventNameForTrace + "' contains a colon. Ensure EventDispatcher's internal mechanism handles this correctly.");
            }
        }

        // Cleanup
        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeOnce 回调中修改其他订阅的复杂场景。
     */
    private function testSubscribeOnceComplexScenarios():Void {
        this.originalTrace("--- 测试 subscribeOnce 复杂场景 ---");
        this.initializeDispatcher();

        var eventName:String = "onceComplexEvent";
        var callOrder:Array = [];
        var scope:Object = this;
        var self = this; // Reference to test class instance

        var cbRegular:Function = function() { callOrder.push("regular"); };
        var cbOnceToRemoveRegular:Function = function() {
            callOrder.push("onceRemover");
            // This 'once' callback removes the regular one
            self.dispatcher.unsubscribe(eventName, cbRegular);
        };
         var cbOnceToAddRegular:Function = function() {
            callOrder.push("onceAdder");
            // This 'once' callback adds the regular one back (or adds initially)
            self.dispatcher.subscribe(eventName, cbRegular, scope);
        };

        // Scenario 1: Once removes regular during dispatch
        callOrder = [];
        this.dispatcher.subscribe(eventName, cbRegular, scope);
        this.dispatcher.subscribeOnce(eventName, cbOnceToRemoveRegular, scope);
        this.dispatcher.publish(eventName); // Should call regular, then onceRemover (which removes regular)
        this.dispatcher.publish(eventName); // Should call nothing (once is gone, regular was removed)
        this.assert(callOrder.join(",") === "regular,onceRemover", "OnceComplex: Scenario 1 - Call order incorrect. Expected 'regular,onceRemover', Got: '" + callOrder.join(",") + "'");

        // Cleanup between scenarios
        this.dispatcher.unsubscribe(eventName, cbRegular); // Ensure clean state
        // No need to unsubscribe cbOnceToRemoveRegular, it's already gone

        // Scenario 2: Once adds regular during dispatch
        callOrder = [];
        this.dispatcher.subscribeOnce(eventName, cbOnceToAddRegular, scope);
        this.dispatcher.publish(eventName); // Should call onceAdder (which adds regular)
        this.dispatcher.publish(eventName); // Should call regular (added by the 'once' callback)
        this.assert(callOrder.join(",") === "onceAdder,regular", "OnceComplex: Scenario 2 - Call order incorrect. Expected 'onceAdder,regular', Got: '" + callOrder.join(",") + "'");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cbRegular);
        // No need to unsubscribe cbOnceToAddRegular
        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 使用相同的回调函数多次。
     */
    private function testSubscribeSingleWithSameCallback():Void {
        this.originalTrace("--- 测试 subscribeSingle 使用相同回调 ---");
        this.initializeDispatcher();

        var eventName:String = "singleSameCbEvent";
        var callCount:Number = 0;
        var cb:Function = function() { callCount++; };
        var scope:Object = this;

        // Subscribe single multiple times with the same callback
        this.dispatcher.subscribeSingle(eventName, cb, scope);
        this.dispatcher.subscribeSingle(eventName, cb, scope); // Call again

        // Publish
        this.dispatcher.publish(eventName);

        // Callback should only be called once, as the second subscribeSingle
        // should effectively replace the first one with itself.
        this.assert(callCount === 1, "SingleSameCb: Callback should be called only once after multiple subscribeSingle with same callback.");

        // Publish again
        this.dispatcher.publish(eventName);
        this.assert(callCount === 2, "SingleSameCb: Callback should be called again on subsequent publish.");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cb);
        this.cleanupDispatcher();
    }

    /**
     * 测试取消订阅一个从未订阅过的事件/回调。
     */
    private function testUnsubscribeNonExistent():Void {
        this.originalTrace("--- 测试取消订阅不存在的监听器 ---");
        this.initializeDispatcher();

        var eventName:String = "nonExistentSubEvent";
        var cb:Function = function() {};
        var scope:Object = this;
        var didError:Boolean = false;

        // Try unsubscribing something that was never subscribed
        try {
            this.dispatcher.unsubscribe(eventName, cb);
            this.dispatcher.unsubscribeGlobal(eventName, cb);
        } catch (e:Error) {
            didError = true;
        }

        this.assert(!didError, "UnsubscribeNonExistent: Unsubscribing a non-existent listener should not cause an error.");

        // Verify that subscribing after the failed unsubscribe works fine
        var callCount = 0;
        var cbActual:Function = function() { callCount++; };
        this.dispatcher.subscribe(eventName, cbActual, scope);
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "UnsubscribeNonExistent: Subscribing after a failed unsubscribe attempt should work correctly.");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cbActual);
        this.cleanupDispatcher();
    }

    /**
     * 测试 destroy 方法的幂等性 (调用多次是否安全)。
     */
    private function testDestroyIdempotency():Void {
        this.originalTrace("--- 测试 destroy 方法幂等性 ---");
        this.initializeDispatcher();

        var eventName:String = "destroyIdempotencyEvent";
        var callCount:Number = 0;
        var cb:Function = function() { callCount++; };
        var scope:Object = this;

        this.dispatcher.subscribe(eventName, cb, scope);

        // Call destroy multiple times
        var didError:Boolean = false;
        try {
            this.dispatcher.destroy();
            this.dispatcher.destroy(); // Call again
            this.dispatcher.destroy(); // And again
        } catch (e:Error) {
            didError = true;
        }
        this.assert(!didError, "DestroyIdempotency: Calling destroy multiple times should not cause an error.");

        // Verify state is destroyed (using warnings and lack of effect)
        callCount = 0;
        this.clearCapturedTraces();
        this.dispatcher.publish(eventName);
        this.assert(callCount === 0, "DestroyIdempotency: Publish should have no effect after multiple destroys.");
        this.assertTraceWarning("called on a destroyed EventDispatcher", "DestroyIdempotency: Warning expected for publish after multiple destroys.");

        // Cleanup (already destroyed)
        this.dispatcher = null;
    }


    /**
     * 输出所有测试结果。
     */
    private function reportResults():Void {
        var passed:Number = 0;
        var failed:Number = 0;
        var failedMessages:Array = [];

        this.originalTrace("---"); // Separator before results

        for (var i:Number = 0; i < this.testResults.length; i++) {
            var result:Object = this.testResults[i];
            if (result.success) {
                passed++;
            } else {
                failed++;
                failedMessages.push(result.message);
            }
        }

        this.originalTrace("=== Extended Test 结果 ===");
        this.originalTrace("通过: " + passed + " 条");
        this.originalTrace("失败: " + failed + " 条");
        if (failed > 0) {
            this.originalTrace("失败详情:");
            for (var j:Number = 0; j < failedMessages.length; j++) {
                this.originalTrace("- " + failedMessages[j]);
            }
            this.originalTrace("请检查失败的测试并修正 EventDispatcher 或测试代码。");
        } else {
            this.originalTrace("所有扩展测试均通过。");
        }
    }
}

// Example Usage:
// var tester = new org.flashNight.neur.Event.EventDispatcherExtendedTest();
// tester.runAllTests();