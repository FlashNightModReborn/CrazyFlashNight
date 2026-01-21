// Import necessary classes (adjust paths if needed)
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.Event.EventBus; // Assuming EventBus might be needed for context
// import org.flashNight.neur.Event.Delegate; // Not directly used in tests
// import org.flashNight.naki.DataStructures.Dictionary; // Not directly used in tests
import flash.utils.getTimer;
// Assume ArgumentsUtil is available globally or imported correctly
// import org.flashNight.gesh.arguments.ArgumentsUtil;

/**
 * EventDispatcherExtendedTest 类提供对 EventDispatcher 的更全面、更深入的测试。
 * 它覆盖了基础测试之外的边界情况、复杂交互和潜在的故障点，
 * 以确保 EventDispatcher 在各种场景下的健壮性和正确性。
 * (版本 3: 调整了 trace 警告测试和 null scope 测试逻辑)
 */
class org.flashNight.neur.Event.EventDispatcherExtendedTest {
    private var dispatcher:EventDispatcher; // 待测试的 EventDispatcher 实例
    private var testResults:Array;           // 存储测试结果信息
    private var originalTrace:Function;      // Store original trace
    private var testLog:Array;               // Simple log for test progress/notes

    /**
     * 构造函数：初始化测试类和结果存储数组。
     */
    public function EventDispatcherExtendedTest() {
        this.testResults = [];
        this.testLog = [];
        // Keep original trace for reporting, but don't rely on capture for assertions
        this.originalTrace = trace;
        // Override trace for potential debugging insight, but not for assertions
        var self = this;
        trace = function(msg) {
            // self.testLog.push("TRACE: " + msg); // Optionally log traces
            self.originalTrace(msg); // Output normally
        };
    }

    /**
     * 运行所有扩展测试方法。
     */
    public function runAllTests():Void {
        this.log("=== EventDispatcherExtendedTest 开始 ===");

        // --- Run Extended Tests ---
        this.testGlobalAndLocalIsolation();
        this.testSubscribeSingleInteractions();
        this.testSubscribeSingleGlobalInteractions();
        this.testDestroyWithMixedSubscriptions();
        this.testUsageAfterDestroy(); // Focuses on behavior after destroy, not warnings
        this.testPublishWithVariousArguments();
        this.testNullScope(); // Revised test logic
        this.testUnsubscribeEdgeCases();
        this.testReentrantPublish();
        this.testEventNameVariations(); // Kept empty string test - may indicate bug in SUT
        this.testSubscribeOnceComplexScenarios();
        this.testSubscribeSingleWithSameCallback();
        this.testUnsubscribeNonExistent();
        this.testDestroyIdempotency(); // Verifies calling destroy multiple times is safe

        // --- [v2.3] 回归测试 - 三方交叉审查综合修复 ---
        this.testSubscribeReturnBoolean();
        this.testSubscribeSingleRefCount();
        this.testOnceFiredWithScope();

        // --- Restore original trace ---
        trace = this.originalTrace;

        // --- Report Results ---
        this.reportResults();
        this.log("=== EventDispatcherExtendedTest 结束 ===");
    }

    /**
     * Log messages using the original trace function.
     */
    private function log(message:String):Void {
        this.originalTrace(message);
        // this.testLog.push(message); // Optionally keep a log
    }

    /**
     * 自定义断言方法。
     */
    private function assert(condition:Boolean, message:String):Void {
        var fullMessage = "ExtendedTest: " + message;
        if (!condition) {
            this.testResults.push({ success: false, message: fullMessage });
            this.log("Assertion Failed: " + fullMessage); // Use original trace for assertion output
        } else {
            this.testResults.push({ success: true, message: fullMessage });
            // Optionally log success: // this.log("Assertion Passed: " + fullMessage);
        }
    }

    // Removed assertTraceWarning and clearCapturedTraces as warning checks are removed

    /**
     * 初始化一个新的 EventDispatcher 实例。
     */
    private function initializeDispatcher():Void {
        // Clean up previous instance if any, before creating new one
        this.cleanupDispatcher();
        this.dispatcher = new EventDispatcher();
        // this.testLog = []; // Reset log if using it per test
    }

    /**
     * 清理 EventDispatcher 实例。
     * destroy() 方法本身应该能安全地处理重复调用。
     */
    private function cleanupDispatcher():Void {
        if (this.dispatcher != null) {
            // Assume dispatcher.destroy() handles being called if already destroyed
            // And correctly unsubscribes its listeners from the static EventBus
            this.dispatcher.destroy();
        }
        this.dispatcher = null;
        // Avoid resetting static EventBus state unless absolutely necessary and tested
        // EventBus.getInstance().destroy(); // Use cautiously
    }

    // ==================================
    //      Extended Test Methods
    // ==================================

    /**
     * 测试本地事件和全局事件同名时的隔离性。
     */
    private function testGlobalAndLocalIsolation():Void {
        this.log("--- 测试全局与本地事件隔离 ---");
        this.initializeDispatcher();
        var dispatcher2 = new EventDispatcher(); // Need a second dispatcher

        var eventName:String = "sharedNameEvent_" + getTimer(); // Add timer for potential run-to-run isolation
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
        this.assert(localCallCount1 === 1, "Isolation: Local publish on d1 triggered d1 local. Count: " + localCallCount1);
        this.assert(globalCallCount1 === 0, "Isolation: Local publish on d1 did NOT trigger d1 global. Count: " + globalCallCount1);
        this.assert(localCallCount2 === 0, "Isolation: Local publish on d1 did NOT trigger d2 local. Count: " + localCallCount2);

        // 2. Publish globally (using dispatcher 1, but could be any or static)
        this.dispatcher.publishGlobal(eventName);
        this.assert(localCallCount1 === 1, "Isolation: Global publish did NOT trigger d1 local. Count: " + localCallCount1);
        this.assert(globalCallCount1 === 1, "Isolation: Global publish triggered d1 global. Count: " + globalCallCount1);
        this.assert(localCallCount2 === 0, "Isolation: Global publish did NOT trigger d2 local. Count: " + localCallCount2);

        // 3. Publish locally on dispatcher 2
        dispatcher2.publish(eventName);
        this.assert(localCallCount1 === 1, "Isolation: Local publish on d2 did NOT trigger d1 local. Count: " + localCallCount1);
        this.assert(globalCallCount1 === 1, "Isolation: Local publish on d2 did NOT trigger d1 global. Count: " + globalCallCount1);
        this.assert(localCallCount2 === 1, "Isolation: Local publish on d2 triggered d2 local. Count: " + localCallCount2);

        // Cleanup
        // Unsubscribe specific listeners before destroying dispatchers
        this.dispatcher.unsubscribe(eventName, localCallback1);
        this.dispatcher.unsubscribeGlobal(eventName, globalCallback1);
        dispatcher2.unsubscribe(eventName, localCallback2);
        this.cleanupDispatcher(); // Destroys dispatcher 1
        dispatcher2.destroy(); // Clean up the second dispatcher too
    }

    /**
     * 测试 subscribeSingle 与常规 subscribe 的交互。
     */
    private function testSubscribeSingleInteractions():Void {
        this.log("--- 测试 subscribeSingle 与 subscribe 交互 ---");
        this.initializeDispatcher();

        var eventName:String = "singleInteractionEvent_" + getTimer();
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
        this.assert(callCount1 === 1, "SingleInteraction (1): subscribeSingle followed by subscribe - single listener called.");
        this.assert(callCount3 === 1, "SingleInteraction (1): subscribeSingle followed by subscribe - regular listener also called.");

        // Reset counts for clarity
        callCount1 = 0; callCount2 = 0; callCount3 = 0;

        // Re-subscribe for part 2 setup (cb1 is still the 'single' listener)
        this.dispatcher.unsubscribe(eventName, cb3); // remove regular listener temporarily
        this.dispatcher.subscribeSingle(eventName, cb1, scope); // ensure cb1 is the single one
        this.dispatcher.subscribe(eventName, cb3, scope); // add regular back

        // 2. subscribe then subscribeSingle (should replace existing single, but not others)
        this.dispatcher.subscribeSingle(eventName, cb2, scope); // cb2 replaces cb1
        this.dispatcher.publish(eventName);
        // Check counts after second publish
        this.assert(callCount1 === 0, "SingleInteraction (2): subscribe then subscribeSingle - original single listener (cb1) NOT called.");
        this.assert(callCount2 === 1, "SingleInteraction (2): subscribe then subscribeSingle - new single listener (cb2) called.");
        this.assert(callCount3 === 1, "SingleInteraction (2): subscribe then subscribeSingle - regular listener (cb3) still called.");


        // Cleanup
        this.dispatcher.unsubscribe(eventName, cb2); // Unsubscribe the final single listener
        this.dispatcher.unsubscribe(eventName, cb3); // Unsubscribe the regular listener
        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingleGlobal 与常规 subscribeGlobal 的交互。
     */
    private function testSubscribeSingleGlobalInteractions():Void {
        this.log("--- 测试 subscribeSingleGlobal 与 subscribeGlobal 交互 ---");
        this.initializeDispatcher();
        var dispatcher2 = new EventDispatcher(); // Use another dispatcher to publish globally

        var eventName:String = "singleGlobalInteractionEvent_" + getTimer();
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
        this.assert(callCount1 === 1, "SingleGlobalInteraction (1): subscribeSingleGlobal followed by subscribeGlobal - single listener called.");
        this.assert(callCount3 === 1, "SingleGlobalInteraction (1): subscribeSingleGlobal followed by subscribeGlobal - regular global listener also called.");

        // Reset counts
        callCount1 = 0; callCount2 = 0; callCount3 = 0;

        // Re-subscribe for part 2 (cb1 is still single global, cb3 is regular global)
        this.dispatcher.unsubscribeGlobal(eventName, cb3); // remove regular global temporarily
        this.dispatcher.subscribeSingleGlobal(eventName, cb1, scope); // ensure cb1 is single global
        this.dispatcher.subscribeGlobal(eventName, cb3, scope); // add regular global back


        // 2. subscribeGlobal then subscribeSingleGlobal (should replace existing single global on THIS dispatcher, but not others)
        this.dispatcher.subscribeSingleGlobal(eventName, cb2, scope); // cb2 replaces cb1 for this dispatcher's single global slot
        dispatcher2.publishGlobal(eventName);
        this.assert(callCount1 === 0, "SingleGlobalInteraction (2): subscribeGlobal then subscribeSingleGlobal - original single listener (cb1) NOT called.");
        this.assert(callCount2 === 1, "SingleGlobalInteraction (2): subscribeGlobal then subscribeSingleGlobal - new single listener (cb2) called.");
        this.assert(callCount3 === 1, "SingleGlobalInteraction (2): subscribeGlobal then subscribeSingleGlobal - regular global listener (cb3) still called.");


        // Cleanup
        this.dispatcher.unsubscribeGlobal(eventName, cb2); // Unsubscribe final single global
        this.dispatcher.unsubscribeGlobal(eventName, cb3); // Unsubscribe regular global
        this.cleanupDispatcher();
        dispatcher2.destroy();
    }

    /**
     * 测试 destroy 方法是否能正确处理本地和全局混合订阅。
     * (通过检查回调是否在 destroy 后停止触发来验证)
     */
    private function testDestroyWithMixedSubscriptions():Void {
        this.log("--- 测试 destroy 处理混合订阅 ---");
        this.initializeDispatcher();
        var dispatcher2 = new EventDispatcher(); // To check global event after destroy

        var localEvent:String = "destroyLocal_" + getTimer();
        var globalEvent:String = "destroyGlobal_" + getTimer();
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
        // No need to call cleanupDispatcher() here, we test the destroyed state first

        // Verify after destroy by attempting to publish and checking callbacks
        // Local publish on destroyed dispatcher should do nothing
        this.dispatcher.publish(localEvent);
        this.assert(!localCalled, "MixedDestroy: Local callback should NOT fire after destroy.");

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
        this.assert(localCalled3, "MixedDestroy: Subscribing to same local event name on new dispatcher works after old one destroyed.");

        dispatcher2.publishGlobal(globalEvent); // Publish global again
        this.assert(globalCalled3, "MixedDestroy: Global listener on new dispatcher works after old one destroyed.");
        this.assert(!globalCalled, "MixedDestroy: Destroyed dispatcher's global listener remains inactive."); // Double check

        // Cleanup
        // dispatcher is already destroyed
        dispatcher2.destroy();
        // Explicitly unsubscribe from dispatcher3 before destroying it
        dispatcher3.unsubscribe(localEvent, cbLocal3);
        dispatcher3.unsubscribeGlobal(globalEvent, cbGlobal3);
        dispatcher3.destroy();
        this.dispatcher = null; // Ensure it's null for subsequent tests
    }

    /**
     * 测试在 destroy 后调用 dispatcher 的方法。
     * (验证方法无效果，不依赖 trace)
     */
    private function testUsageAfterDestroy():Void {
        this.log("--- 测试 destroy 后使用 Dispatcher ---");
        this.initializeDispatcher();

        var eventName:String = "postDestroyEvent_" + getTimer();
        var globalEventName:String = "postDestroyGlobalEvent_" + getTimer();
        var scope:Object = this;
        var callCount:Number = 0;
        var cbCounter:Function = function() { callCount++; };
        var cbShouldNotRun:Function = function() { this.assert(false, "UsageAfterDestroy: Callback should NOT be called after destroy."); };

        // Subscribe before destroy to test publish later
        this.dispatcher.subscribe(eventName, cbCounter, scope);
        this.dispatcher.subscribeGlobal(globalEventName, cbCounter, scope);

        // Destroy it
        this.dispatcher.destroy();
        // this.dispatcher reference still exists, but points to a destroyed object

        var didError:Boolean = false;
        try {
            // Test methods - they should be no-ops and not throw errors internally
            this.dispatcher.subscribe(eventName, cbShouldNotRun, scope);
            this.dispatcher.subscribeOnce(eventName, cbShouldNotRun, scope);
            this.dispatcher.unsubscribe(eventName, cbCounter); // Try unsubscribing original
            this.dispatcher.unsubscribe(eventName, cbShouldNotRun); // Try unsubscribing non-existent on destroyed
            this.dispatcher.subscribeGlobal(globalEventName, cbShouldNotRun, scope);
            this.dispatcher.unsubscribeGlobal(globalEventName, cbCounter);
            this.dispatcher.unsubscribeGlobal(globalEventName, cbShouldNotRun);
            this.dispatcher.subscribeSingle(eventName, cbShouldNotRun, scope);
            this.dispatcher.subscribeSingleGlobal(globalEventName, cbShouldNotRun, scope);

            // Test publish - should NOT call the cbCounter subscribed before destroy
            callCount = 0; // Reset before publish attempts
            this.dispatcher.publish(eventName);
            this.assert(callCount === 0, "UsageAfterDestroy: Local publish should have no effect after destroy.");

            this.dispatcher.publishGlobal(globalEventName);
            this.assert(callCount === 0, "UsageAfterDestroy: Global publish should have no effect after destroy.");

        } catch (e:Error) {
            didError = true;
            this.log("UsageAfterDestroy: Error occurred - " + e);
        }

        this.assert(!didError, "UsageAfterDestroy: Calling methods on destroyed dispatcher should not cause errors.");

        // Cleanup (already destroyed)
        this.dispatcher = null;
    }

    /**
     * 测试 publish 传递 null, undefined, 和零参数。
     */
    private function testPublishWithVariousArguments():Void {
        this.log("--- 测试 publish 使用不同参数 ---");
        this.initializeDispatcher();

        var eventName:String = "argsEvent_" + getTimer();
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
        receivedArgs = ["initial"]; callCount = 0; // Reset state
        this.dispatcher.publish(eventName, null);
        this.assert(callCount === 1, "PublishArgs: Callback called with null argument.");
        this.assert(receivedArgs != null && receivedArgs.length === 1, "PublishArgs: Received one argument for null publish. Got: " + receivedArgs.length);
        this.assert(receivedArgs[0] === null, "PublishArgs: Received argument should be null. Got: " + receivedArgs[0]);

        // 2. Publish with undefined
        receivedArgs = ["initial"]; callCount = 0;
        this.dispatcher.publish(eventName, undefined);
        this.assert(callCount === 1, "PublishArgs: Callback called with undefined argument.");
        this.assert(receivedArgs != null && receivedArgs.length === 1, "PublishArgs: Received one argument for undefined publish. Got: " + receivedArgs.length);
        this.assert(receivedArgs[0] === undefined, "PublishArgs: Received argument should be undefined. Got: " + receivedArgs[0]);

        // 3. Publish with zero arguments
        receivedArgs = ["initial"]; callCount = 0;
        this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "PublishArgs: Callback called with zero arguments.");
        this.assert(receivedArgs != null && receivedArgs.length === 0, "PublishArgs: Received zero arguments for zero-arg publish. Got: " + receivedArgs.length);

        // 4. Publish with multiple mixed arguments including null/undefined
        receivedArgs = ["initial"]; callCount = 0;
        var obj = { test: 1 };
        this.dispatcher.publish(eventName, 1, null, "hello", undefined, obj);
        this.assert(callCount === 1, "PublishArgs: Callback called with mixed arguments.");
        this.assert(receivedArgs != null && receivedArgs.length === 5, "PublishArgs: Received five arguments for mixed publish. Got: " + receivedArgs.length);
        this.assert(receivedArgs[0] === 1 && receivedArgs[1] === null && receivedArgs[2] === "hello" && receivedArgs[3] === undefined && receivedArgs[4] === obj, "PublishArgs: Received arguments match mixed publish.");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cb);
        this.cleanupDispatcher();
    }

    /**
     * 测试使用 null 作为回调函数的作用域。(Revised Test Logic)
     */
    private function testNullScope():Void {
        this.log("--- 测试 null 作用域 ---");
        this.initializeDispatcher();

        var eventName:String = "nullScopeEvent_" + getTimer();
        var initialScopeCheckValue:Object = new Object(); // Unique object
        var scopeCheck:Object = initialScopeCheckValue; // Variable to store 'this' from callback
        var callCount:Number = 0;

        var cb:Function = function() {
            callCount++;
            scopeCheck = this; // Capture 'this'
        };

        // Subscribe with null scope
        this.dispatcher.subscribe(eventName, cb, null);

        // Publish event
        this.dispatcher.publish(eventName);

        // Assertions:
        // 1. Callback must be called
        this.assert(callCount === 1, "NullScope: Callback should be called once.");
        // 2. 'this' (scopeCheck) should have been modified from its initial value
        this.assert(scopeCheck !== initialScopeCheckValue, "NullScope: Callback 'this' should have been assigned.");
        // 3. 'this' should be a valid object (likely _global in AS2), not null or undefined
        this.assert(scopeCheck !== null && scopeCheck !== undefined, "NullScope: Callback 'this' should not be null or undefined when scope is null.");
        // Optional, more specific AS2 check (can be brittle):
        // this.assert(scopeCheck === _global, "NullScope: Callback 'this' should be the global object (_global).");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cb); // Unsubscribe still needs the callback function
        this.cleanupDispatcher();
    }

    /**
     * 测试 unsubscribe 的各种边界情况。
     */
    private function testUnsubscribeEdgeCases():Void {
        this.log("--- 测试 unsubscribe 边界情况 ---");
        this.initializeDispatcher();

        var eventName:String = "unsubscribeEdgeEvent_" + getTimer();
        var globalEventName:String = "unsubscribeGlobalEdgeEvent_" + getTimer();
        var callCount:Number = 0;
        var cb:Function = function() { callCount++; };
        var cbGlobal:Function = function() { callCount++; };
        var scope:Object = this;

        this.dispatcher.subscribe(eventName, cb, scope);
        this.dispatcher.subscribeGlobal(globalEventName, cbGlobal, scope);

        var didError:Boolean;

        // 1. Unsubscribe with wrong event name
        didError = false;
        try { this.dispatcher.unsubscribe("wrongEvent", cb); } catch (e:Error) { didError = true; }
        this.assert(!didError, "UnsubscribeEdge: Unsubscribing with wrong event name should not error.");
        // Verify original subscription still works
        callCount = 0; this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "UnsubscribeEdge: Original subscription persists after wrong name unsubscribe attempt.");

        // 2. Unsubscribe with wrong callback
        didError = false;
        var wrongCb:Function = function() {};
        try { this.dispatcher.unsubscribe(eventName, wrongCb); } catch (e:Error) { didError = true; }
        this.assert(!didError, "UnsubscribeEdge: Unsubscribing with wrong callback should not error.");
        // Verify original subscription still works
        callCount = 0; this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "UnsubscribeEdge: Original subscription persists after wrong callback unsubscribe attempt.");

        // 3. Unsubscribe a local event using unsubscribeGlobal
        didError = false;
        try { this.dispatcher.unsubscribeGlobal(eventName, cb); } catch (e:Error) { didError = true; }
        this.assert(!didError, "UnsubscribeEdge: Unsubscribing local via unsubscribeGlobal should not error (but not work).");
        // Verify original subscription still works
        callCount = 0; this.dispatcher.publish(eventName);
        this.assert(callCount === 1, "UnsubscribeEdge: Local subscription persists after unsubscribeGlobal attempt.");

        // 4. Unsubscribe a global event using unsubscribe
        didError = false;
        try { this.dispatcher.unsubscribe(globalEventName, cbGlobal); } catch (e:Error) { didError = true; }
        this.assert(!didError, "UnsubscribeEdge: Unsubscribing global via unsubscribe should not error (but not work).");
        // Verify original subscription still works
        callCount = 0; this.dispatcher.publishGlobal(globalEventName); // Reset call count for global check
        this.assert(callCount === 1, "UnsubscribeEdge: Global subscription persists after unsubscribe attempt.");

        // 5. Correctly unsubscribe local
        callCount = 0; // Reset before final checks
        this.dispatcher.unsubscribe(eventName, cb);
        this.dispatcher.publish(eventName);
        this.assert(callCount === 0, "UnsubscribeEdge: Local subscription removed after correct unsubscribe.");

        // 6. Correctly unsubscribe global
        callCount = 0; // Reset again
        this.dispatcher.unsubscribeGlobal(globalEventName, cbGlobal);
        this.dispatcher.publishGlobal(globalEventName);
        this.assert(callCount === 0, "UnsubscribeEdge: Global subscription removed after correct unsubscribeGlobal.");

        // Cleanup
        this.cleanupDispatcher();
    }

    /**
     * 测试从回调内部发布同一事件（重入）。
     */
    private function testReentrantPublish():Void {
        this.log("--- 测试重入发布 ---");
        this.initializeDispatcher();

        var eventName:String = "reentrantEvent_" + getTimer();
        var maxCalls:Number = 5; // Limit recursion depth for test
        var callCount:Number = 0;
        var scope:Object = this;
        var self = this; // Need reference to test class instance inside callback

        var reentrantCallback:Function = function() {
            callCount++;
            if (callCount < maxCalls) {
                // Use the captured 'self.dispatcher' to publish
                if (self.dispatcher != null) { // Check if dispatcher wasn't destroyed mid-call
                   self.dispatcher.publish(eventName);
                }
            }
        };

        this.dispatcher.subscribe(eventName, reentrantCallback, scope);

        // Trigger the first publish
        this.dispatcher.publish(eventName);

        // Should have been called maxCalls times due to re-entrancy limit
        this.assert(callCount === maxCalls, "ReentrantPublish: Callback should be called " + maxCalls + " times. Got: " + callCount);

        // Verify it stops after maxCalls (reset count and publish again)
        callCount = 0;
        this.dispatcher.publish(eventName); // Publish again from outside
        this.assert(callCount === maxCalls, "ReentrantPublish: Publishing again should re-trigger limited re-entrancy. Got: " + callCount);

        // Cleanup
        this.dispatcher.unsubscribe(eventName, reentrantCallback);
        this.cleanupDispatcher();
    }

    /**
     * 测试使用特殊字符作为事件名称。
     * [v2.3.2] 空字符串和 null 现在会被拒绝（返回 false），不再作为有效事件名
     */
    private function testEventNameVariations():Void {
        this.log("--- 测试不同的事件名称 ---");
        this.initializeDispatcher();

        // [v2.3.2] 首先测试空字符串和 null 被正确拒绝
        var cb:Function = function() {};
        var scope:Object = this;

        // 测试空字符串被拒绝
        var emptyResult:Boolean = this.dispatcher.subscribe("", cb, scope);
        this.assert(emptyResult == false, "[v2.3.2] empty string eventName - subscribe should return false");

        // 测试 null 被拒绝
        var nullResult:Boolean = this.dispatcher.subscribe(null, cb, scope);
        this.assert(nullResult == false, "[v2.3.2] null eventName - subscribe should return false");

        // 测试 subscribeOnce 也拒绝空字符串
        var emptyOnceResult:Boolean = this.dispatcher.subscribeOnce("", cb, scope);
        this.assert(emptyOnceResult == false, "[v2.3.2] empty string eventName - subscribeOnce should return false");

        // 测试 unsubscribe 也拒绝空字符串（返回 false）
        var emptyUnsubResult:Boolean = this.dispatcher.unsubscribe("", cb, scope);
        this.assert(emptyUnsubResult == false, "[v2.3.2] empty string eventName - unsubscribe should return false");

        // Manually create long string for AS2 compatibility
        var longNameBase = "veryLongEventName";
        var longName = "";
        for (var k=0; k<10; k++) { longName += longNameBase; } // Reasonably long string

        // [v2.3.2] 有效的事件名称测试（移除空字符串，它现在被拒绝）
        var eventNames:Array = [
            "event with spaces",        // Spaces
            "event/with/slashes",       // Slashes
            "event.with.dots",          // Dots
            "event:with:colons",        // Colons (Note potential interaction with instanceID)
            "~!@#$%^&*()_+`-={}|[]\\;\':\"<>?,./", // Special chars
            longName                    // Use the manually created long name
        ];
        var callCount:Number = 0;
        var testCb:Function = function() { callCount++; };

        for (var i = 0; i < eventNames.length; i++) {
            var eventName = eventNames[i];
            callCount = 0;
            var didError:Boolean = false;
            var currentEventNameForTrace = eventName;
            // Basic length check for logging, avoid complex substring logic here
            if (currentEventNameForTrace.length > 60) { currentEventNameForTrace = "...long name..."; }

            try {
                // Subscribe
                this.dispatcher.subscribe(eventName, testCb, scope);

                // Publish and check if called
                this.dispatcher.publish(eventName);
                this.assert(callCount === 1, "EventNameVariation ["+i+"]: Callback called for event name '" + currentEventNameForTrace + "'. Count: " + callCount);

                // Unsubscribe
                this.dispatcher.unsubscribe(eventName, testCb);

                // Publish again and check NOT called
                callCount = 0; // Reset count
                this.dispatcher.publish(eventName);
                this.assert(callCount === 0, "EventNameVariation ["+i+"]: Callback NOT called after unsubscribe for event name '" + currentEventNameForTrace + "'. Count: " + callCount);

            } catch (e:Error) {
                didError = true;
                this.log("Error during test for event name: '" + currentEventNameForTrace + "' - " + e.toString());
            }
            this.assert(!didError, "EventNameVariation ["+i+"]: Using event name '" + currentEventNameForTrace + "' should not cause runtime errors.");

            // Add a note about potential colon issues without asserting based on private details
            if (typeof(eventName) == "string" && eventName.indexOf(":") != -1) {
                this.log("Note: Event name '" + currentEventNameForTrace + "' contains a colon. Ensure handling is correct.");
            }
        }

        // Cleanup
        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeOnce 回调中修改其他订阅的复杂场景。
     */
    private function testSubscribeOnceComplexScenarios():Void {
        this.log("--- 测试 subscribeOnce 复杂场景 ---");
        this.initializeDispatcher();

        var eventName:String = "onceComplexEvent_" + getTimer();
        var callOrder:Array = [];
        var scope:Object = this;
        var self = this; // Reference to test class instance

        // Define callbacks within the test method's scope
        var cbRegular:Function = function() { callOrder.push("regular"); };
        var cbOnceToRemoveRegular:Function = function() {
            callOrder.push("onceRemover");
            // Use captured self.dispatcher
            if (self.dispatcher != null) {
                self.dispatcher.unsubscribe(eventName, cbRegular);
            }
        };
        var cbOnceToAddRegular:Function = function() {
            callOrder.push("onceAdder");
            // Use captured self.dispatcher
            if (self.dispatcher != null) {
                self.dispatcher.subscribe(eventName, cbRegular, scope);
            }
        };

        // Scenario 1: Once removes regular during dispatch
        this.log("OnceComplex: Scenario 1 Setup");
        callOrder = [];
        this.dispatcher.subscribe(eventName, cbRegular, scope);
        this.dispatcher.subscribeOnce(eventName, cbOnceToRemoveRegular, scope);
        this.log("OnceComplex: Scenario 1 Publish 1");
        this.dispatcher.publish(eventName); // Should call regular, then onceRemover (which removes regular)
        this.log("OnceComplex: Scenario 1 Publish 2");
        this.dispatcher.publish(eventName); // Should call nothing (once is gone, regular was removed)
        var expectedOrder1 = "regular,onceRemover";
        this.assert(callOrder.join(",") === expectedOrder1, "OnceComplex: Scenario 1 - Call order incorrect. Expected '"+expectedOrder1+"', Got: '" + callOrder.join(",") + "'");

        // Cleanup between scenarios - important!
        this.dispatcher.unsubscribe(eventName, cbRegular); // Ensure clean state if remover failed
        // No need to unsubscribe cbOnceToRemoveRegular, it's already gone

        // Scenario 2: Once adds regular during dispatch
        this.log("OnceComplex: Scenario 2 Setup");
        callOrder = [];
        this.dispatcher.subscribeOnce(eventName, cbOnceToAddRegular, scope);
        this.log("OnceComplex: Scenario 2 Publish 1");
        this.dispatcher.publish(eventName); // Should call onceAdder (which adds regular)
        this.log("OnceComplex: Scenario 2 Publish 2");
        this.dispatcher.publish(eventName); // Should call regular (added by the 'once' callback)
        var expectedOrder2 = "onceAdder,regular";
        this.assert(callOrder.join(",") === expectedOrder2, "OnceComplex: Scenario 2 - Call order incorrect. Expected '"+expectedOrder2+"', Got: '" + callOrder.join(",") + "'");

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cbRegular); // Unsubscribe the one added in scenario 2
        // No need to unsubscribe cbOnceToAddRegular
        this.cleanupDispatcher();
    }

    /**
     * 测试 subscribeSingle 使用相同的回调函数多次。
     */
    private function testSubscribeSingleWithSameCallback():Void {
        this.log("--- 测试 subscribeSingle 使用相同回调 ---");
        this.initializeDispatcher();

        var eventName:String = "singleSameCbEvent_" + getTimer();
        var callCount:Number = 0;
        var cb:Function = function() { callCount++; };
        var scope:Object = this;

        // Subscribe single multiple times with the same callback
        this.dispatcher.subscribeSingle(eventName, cb, scope);
        this.dispatcher.subscribeSingle(eventName, cb, scope); // Call again

        // Publish
        this.dispatcher.publish(eventName);

        // Callback should only be called once per publish, as the second subscribeSingle
        // should effectively replace the first one with itself.
        this.assert(callCount === 1, "SingleSameCb: Callback should be called only once after first publish. Count: " + callCount);

        // Publish again
        this.dispatcher.publish(eventName);
        this.assert(callCount === 2, "SingleSameCb: Callback should be called again on subsequent publish. Count: " + callCount);

        // Cleanup
        this.dispatcher.unsubscribe(eventName, cb); // Need to unsubscribe the single listener
        this.cleanupDispatcher();
    }

    /**
     * 测试取消订阅一个从未订阅过的事件/回调。
     */
    private function testUnsubscribeNonExistent():Void {
        this.log("--- 测试取消订阅不存在的监听器 ---");
        this.initializeDispatcher();

        var eventName:String = "nonExistentSubEvent_" + getTimer();
        var cb:Function = function() {};
        var scope:Object = this;
        var didError:Boolean = false;

        // Try unsubscribing something that was never subscribed
        try {
            this.dispatcher.unsubscribe(eventName, cb);
            this.dispatcher.unsubscribeGlobal(eventName, cb);
            // Also try different variations
            this.dispatcher.unsubscribe("anotherNonExistentEvent", cb);
            this.dispatcher.unsubscribeGlobal("anotherNonExistentGlobal", cb);
        } catch (e:Error) {
            didError = true;
            this.log("UnsubscribeNonExistent: Error occurred - " + e);
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
        this.log("--- 测试 destroy 方法幂等性 ---");
        this.initializeDispatcher();

        var eventName:String = "destroyIdempotencyEvent_" + getTimer();
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
            this.log("DestroyIdempotency: Error occurred - " + e);
        }
        this.assert(!didError, "DestroyIdempotency: Calling destroy multiple times should not cause an error.");

        // Verify state is destroyed (by checking behavior, not warnings)
        callCount = 0;
        this.dispatcher.publish(eventName); // Should do nothing
        this.assert(callCount === 0, "DestroyIdempotency: Publish should have no effect after multiple destroys.");

        // Try subscribing after multiple destroys (should do nothing)
        var cbAfterDestroy:Function = function() { this.assert(false, "DestroyIdempotency: Callback subscribed after destroy should not run."); };
        this.dispatcher.subscribe(eventName, cbAfterDestroy, scope);
        this.dispatcher.publish(eventName); // Still should do nothing

        // Cleanup (already destroyed, just nullify)
        this.dispatcher = null;
    }

    // ==================================
    //    [v2.3] 回归测试方法
    // ==================================

    /**
     * [v2.3 回归测试 S2] 验证 EventDispatcher.subscribe 返回 Boolean
     * 修复问题：subscribe 方法应返回 Boolean 表示是否成功订阅
     */
    private function testSubscribeReturnBoolean():Void {
        this.log("--- [v2.3 S2] 测试 subscribe 返回 Boolean ---");
        this.initializeDispatcher();

        var eventName:String = "subscribeReturnBoolEvent_" + getTimer();
        var callback:Function = function():Void {};
        var scope:Object = this;

        // 首次订阅应返回 true
        var firstSubscribe:Boolean = this.dispatcher.subscribe(eventName, callback, scope);
        this.assert(firstSubscribe == true, "[v2.3 S2] subscribe return - first subscribe returns true");

        // 重复订阅应返回 false
        var duplicateSubscribe:Boolean = this.dispatcher.subscribe(eventName, callback, scope);
        this.assert(duplicateSubscribe == false, "[v2.3 S2] subscribe return - duplicate subscribe returns false");

        // 测试 subscribeGlobal 同样返回 Boolean
        var globalEventName:String = "globalReturnBoolEvent_" + getTimer();
        var firstGlobal:Boolean = this.dispatcher.subscribeGlobal(globalEventName, callback, scope);
        this.assert(firstGlobal == true, "[v2.3 S2] subscribeGlobal return - first subscribeGlobal returns true");

        var duplicateGlobal:Boolean = this.dispatcher.subscribeGlobal(globalEventName, callback, scope);
        this.assert(duplicateGlobal == false, "[v2.3 S2] subscribeGlobal return - duplicate subscribeGlobal returns false");

        // 测试 subscribeOnce 同样返回 Boolean
        var onceEventName:String = "onceReturnBoolEvent_" + getTimer();
        var firstOnce:Boolean = this.dispatcher.subscribeOnce(onceEventName, callback, scope);
        this.assert(firstOnce == true, "[v2.3 S2] subscribeOnce return - first subscribeOnce returns true");

        var duplicateOnce:Boolean = this.dispatcher.subscribeOnce(onceEventName, callback, scope);
        this.assert(duplicateOnce == false, "[v2.3 S2] subscribeOnce return - duplicate subscribeOnce returns false");

        // 清理
        this.dispatcher.unsubscribe(eventName, callback);
        this.dispatcher.unsubscribeGlobal(globalEventName, callback);
        this.cleanupDispatcher();
    }

    /**
     * [v2.3 回归测试 S3] 验证 subscribeSingle 正确维护 refCount
     * 修复问题：subscribeSingle 在替换旧订阅时应正确递减 eventNameMap 的 refCount
     */
    private function testSubscribeSingleRefCount():Void {
        this.log("--- [v2.3 S3] 测试 subscribeSingle refCount 维护 ---");
        this.initializeDispatcher();

        var eventName:String = "singleRefCountEvent_" + getTimer();
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        var callCount3:Number = 0;

        var cb1:Function = function():Void { callCount1++; };
        var cb2:Function = function():Void { callCount2++; };
        var cb3:Function = function():Void { callCount3++; };
        var scope:Object = this;

        // 第一次 subscribeSingle
        this.dispatcher.subscribeSingle(eventName, cb1, scope);
        this.dispatcher.publish(eventName);
        this.assert(callCount1 == 1, "[v2.3 S3] subscribeSingle refCount - cb1 called after first subscribe");

        // 第二次 subscribeSingle - 应该替换 cb1
        this.dispatcher.subscribeSingle(eventName, cb2, scope);
        callCount1 = 0;
        callCount2 = 0;
        this.dispatcher.publish(eventName);
        this.assert(callCount1 == 0, "[v2.3 S3] subscribeSingle refCount - cb1 NOT called after replacement");
        this.assert(callCount2 == 1, "[v2.3 S3] subscribeSingle refCount - cb2 called after replacement");

        // 第三次 subscribeSingle - 应该替换 cb2
        this.dispatcher.subscribeSingle(eventName, cb3, scope);
        callCount1 = 0;
        callCount2 = 0;
        callCount3 = 0;
        this.dispatcher.publish(eventName);
        this.assert(callCount1 == 0, "[v2.3 S3] subscribeSingle refCount - cb1 still NOT called");
        this.assert(callCount2 == 0, "[v2.3 S3] subscribeSingle refCount - cb2 NOT called after second replacement");
        this.assert(callCount3 == 1, "[v2.3 S3] subscribeSingle refCount - cb3 called after second replacement");

        // 验证 unsubscribe cb3 后事件名被正确清理
        this.dispatcher.unsubscribe(eventName, cb3);
        callCount3 = 0;
        this.dispatcher.publish(eventName);
        this.assert(callCount3 == 0, "[v2.3 S3] subscribeSingle refCount - cb3 NOT called after unsubscribe");

        // 重新订阅应该正常工作（验证 eventNameMap 没有被错误地提前删除）
        var callCount4:Number = 0;
        var cb4:Function = function():Void { callCount4++; };
        this.dispatcher.subscribe(eventName, cb4, scope);
        this.dispatcher.publish(eventName);
        this.assert(callCount4 == 1, "[v2.3 S3] subscribeSingle refCount - new subscribe works after unsubscribe");

        // 清理
        this.dispatcher.unsubscribe(eventName, cb4);
        this.cleanupDispatcher();
    }

    /**
     * [v2.3 回归测试 I1] 验证 subscribeOnce 触发时正确传递 scope
     * 修复问题：__onEventBusOnceFired 应接受并传递 scope 参数用于精确退订
     */
    private function testOnceFiredWithScope():Void {
        this.log("--- [v2.3 I1] 测试 subscribeOnce 触发时 scope 传递 ---");
        this.initializeDispatcher();

        var eventName:String = "onceScopeEvent_" + getTimer();
        var callCount1:Number = 0;
        var callCount2:Number = 0;

        // 创建两个不同的 scope 对象
        var scope1:Object = { name: "scope1" };
        var scope2:Object = { name: "scope2" };

        // 使用相同的回调函数但不同的 scope
        var sharedCallback:Function = function():Void {
            if (this.name == "scope1") {
                callCount1++;
            } else if (this.name == "scope2") {
                callCount2++;
            }
        };

        // 两个 subscribeOnce 使用相同 callback 但不同 scope
        this.dispatcher.subscribeOnce(eventName, sharedCallback, scope1);
        this.dispatcher.subscribeOnce(eventName, sharedCallback, scope2);

        // 第一次发布 - 两个都应该被调用（各自触发一次后自动退订）
        this.dispatcher.publish(eventName);
        this.assert(callCount1 == 1, "[v2.3 I1] onceFiredWithScope - scope1 callback called on first publish");
        this.assert(callCount2 == 1, "[v2.3 I1] onceFiredWithScope - scope2 callback called on first publish");

        // 第二次发布 - 两个都不应该被调用（已自动退订）
        callCount1 = 0;
        callCount2 = 0;
        this.dispatcher.publish(eventName);
        this.assert(callCount1 == 0, "[v2.3 I1] onceFiredWithScope - scope1 callback NOT called after once-fired");
        this.assert(callCount2 == 0, "[v2.3 I1] onceFiredWithScope - scope2 callback NOT called after once-fired");

        // 清理
        this.cleanupDispatcher();
    }

    /**
     * 输出所有测试结果。
     */
    private function reportResults():Void {
        var passed:Number = 0;
        var failed:Number = 0;
        var failedMessages:Array = [];

        this.log("---"); // Separator before results

        for (var i:Number = 0; i < this.testResults.length; i++) {
            var result:Object = this.testResults[i];
            if (result.success) {
                passed++;
            } else {
                failed++;
                failedMessages.push(result.message);
            }
        }

        this.log("=== Extended Test 结果 ===");
        this.log("通过: " + passed + " 条");
        this.log("失败: " + failed + " 条");
        if (failed > 0) {
            this.log("失败详情:");
            for (var j:Number = 0; j < failedMessages.length; j++) {
                this.log("- " + failedMessages[j]);
            }
             this.log("---");
            this.log("请检查失败的测试。[v2.3.2] 空字符串/null 事件名现在会被拒绝返回 false。");
        } else {
            this.log("所有扩展测试均通过。");
        }
    }
}
