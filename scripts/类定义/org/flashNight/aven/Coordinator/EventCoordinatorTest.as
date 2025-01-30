/**
 * EventCoordinatorTest.as
 *
 * 测试 org.flashNight.aven.Coordinator.EventCoordinator 的正确性和性能。
 * 
 * 附加：testClosureCapture() 主要用于验证事件名称在闭包中是否正确锁定，
 *      防止潜在的“变量覆盖 / 闭包共享”问题。
 */

import org.flashNight.aven.Coordinator.*;

class org.flashNight.aven.Coordinator.EventCoordinatorTest {
    
    private static var totalAssertions:Number = 0;
    private static var passedAssertions:Number = 0;
    private static var failedAssertions:Number = 0;
    
    /**
     * 入口：运行所有测试
     */
    public static function runAllTests():Void {
        trace("\n=== Running EventCoordinator Tests ===");
        testCoreFunctions();
        testEdgeCases();
        testOriginalHandlers();
        testMultipleTargets();
        testUnloadHandling();
        testClosureCapture();   // <-- 新增的闭包测试
        performanceTest();
        trace("\n=== Tests Completed ===");
        trace("Total Assertions: " + totalAssertions);
        trace("Passed Assertions: " + passedAssertions);
        trace("Failed Assertions: " + failedAssertions + "\n");
    }
    
    //--------------------------------------------------------------------------
    // 1. 核心断言方法
    //--------------------------------------------------------------------------
    
    /**
     * 基础断言：若 condition 为 false，则输出失败信息
     * @param condition 要测试的条件
     * @param message   断言描述
     */
    private static function assert(condition:Boolean, message:String):Void {
        totalAssertions++;
        if (!condition) {
            failedAssertions++;
            trace("[ASSERTION FAILED]: " + message);
        } else {
            passedAssertions++;
            trace("[ASSERTION PASSED]: " + message);
        }
    }
    
    
    //--------------------------------------------------------------------------
    // 2. 核心功能测试
    //--------------------------------------------------------------------------
    
    private static function testCoreFunctions():Void {
        trace("\n-- testCoreFunctions --");
        
        var testTarget:Object = {};
        
        // 1) 测试 addEventListener & removeEventListener
        var callCount:Number = 0;
        var handler1:Function = function() { callCount++; };
        
        // 添加监听器
        var hid1:String = EventCoordinator.addEventListener(testTarget, "onPress", handler1);
        assert(hid1 != null, "addEventListener should return a non-null handler ID");
        
        // 模拟触发一次 onPress
        if (testTarget.onPress) {
            testTarget.onPress(); 
        }
        assert(callCount == 1, "Handler1 should have been called exactly once");
        
        // 再添加一个监听器
        var callCount2:Number = 0;
        var handler2:Function = function() { callCount2++; };
        var hid2:String = EventCoordinator.addEventListener(testTarget, "onPress", handler2);
        assert(hid2 != null, "addEventListener should return a non-null handler ID for handler2");
        
        // 再次触发
        testTarget.onPress();
        assert(callCount == 2 && callCount2 == 1,
            "After second handler added, total calls should be callCount=2, callCount2=1");
        
        // 移除 handler1
        EventCoordinator.removeEventListener(testTarget, "onPress", hid1);
        // 再触发
        testTarget.onPress();
        assert(callCount == 2 && callCount2 == 2,
            "After removing handler1, only handler2 should be called. So callCount=2, callCount2=2.");
        
        // 2) 测试 clearEventListeners
        EventCoordinator.clearEventListeners(testTarget);
        // 触发 onPress 不应再调用任何回调
        testTarget.onPress();
        assert(callCount2 == 2, "After clearEventListeners, no callbacks should be invoked");
        
        // 3) 测试 enableEventListeners
        //    再次添加2个监听器，然后禁用再启用
        callCount = 0; 
        callCount2 = 0;
        EventCoordinator.addEventListener(testTarget, "onPress", function(){ callCount++; });
        EventCoordinator.addEventListener(testTarget, "onPress", function(){ callCount2++; });
        
        // 禁用
        EventCoordinator.enableEventListeners(testTarget, false);
        testTarget.onPress(); // 此时回调应不执行
        assert(callCount == 0 && callCount2 == 0,
               "After enableEventListeners(false), no callbacks should be triggered");
        
        // 启用
        EventCoordinator.enableEventListeners(testTarget, true);
        testTarget.onPress(); // 现在应恢复
        assert(callCount == 1 && callCount2 == 1,
               "After enableEventListeners(true), both callbacks should be triggered again");
        
        trace("-- testCoreFunctions Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 3. 边界情况测试
    //--------------------------------------------------------------------------
    
    private static function testEdgeCases():Void {
        trace("\n-- testEdgeCases --");
        
        var testTarget:Object = {};
        
        // 1) 测试添加相同的处理器多次
        var callCount:Number = 0;
        var handler:Function = function() { callCount++; };
        
        var hid1:String = EventCoordinator.addEventListener(testTarget, "onMouseMove", handler);
        var hid2:String = EventCoordinator.addEventListener(testTarget, "onMouseMove", handler);
        
        // 期望两次添加返回不同的 handler IDs，允许重复绑定
        assert(hid1 != null && hid2 != null && hid1 != hid2, "Adding the same handler twice should return different IDs");
        
        // 触发事件
        testTarget.onMouseMove(100, 200);
        assert(callCount == 2, "Handler should have been called twice for two bindings");
        
        // 移除其中一个处理器
        EventCoordinator.removeEventListener(testTarget, "onMouseMove", hid1);
        testTarget.onMouseMove(150, 250);
        assert(callCount == 3, "After removing one handler, only one should be called");
        
        // 移除另一个处理器
        EventCoordinator.removeEventListener(testTarget, "onMouseMove", hid2);
        testTarget.onMouseMove(200, 300);
        assert(callCount == 3, "After removing both handlers, none should be called");
        
        // 2) 移除不存在的处理器
        EventCoordinator.removeEventListener(testTarget, "onMouseMove", "NonExistentID");
        trace("[INFO] Removing non-existent handler should not affect existing handlers.");
        assert(true, "Removing a non-existent handler should not throw errors");
        
        // 3) 在事件触发期间添加/移除处理器
        var dynamicCallCount:Number = 0;
        var dynamicHandler1:Function = function() { 
            dynamicCallCount++; 
            // 在触发时添加另一个处理器
            EventCoordinator.addEventListener(testTarget, "onKeyDown", dynamicHandler2);
        };
        var dynamicHandler2:Function = function() { 
            dynamicCallCount++; 
        };
        
        EventCoordinator.addEventListener(testTarget, "onKeyDown", dynamicHandler1);
        testTarget.onKeyDown(65); // Simulate KeyDown with keyCode 65 ('A')
        assert(dynamicCallCount == 1, "DynamicHandler1 should have been called once");
        
        // 触发 onKeyDown 再次，动态添加的 handler2 也应被调用
        testTarget.onKeyDown(66); // KeyCode 66 ('B')
        assert(dynamicCallCount == 3, "After dynamic addition, both handlers should be called");
        
        // 清理
        EventCoordinator.clearEventListeners(testTarget);
        
        trace("-- testEdgeCases Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 4. 原生事件处理器兼容性测试
    //--------------------------------------------------------------------------
    
    private static function testOriginalHandlers():Void {
        trace("\n-- testOriginalHandlers --");
        
        var testTarget:Object = {};
        var originalCallCount:Number = 0;
        
        // 设置原生事件处理器
        testTarget.onRelease = function() { originalCallCount++; };
        
        // 添加自定义监听器
        var customCallCount:Number = 0;
        EventCoordinator.addEventListener(testTarget, "onRelease", function() { customCallCount++; });
        
        // 触发事件
        testTarget.onRelease();
        assert(originalCallCount == 1, "Original handler should have been called once");
        assert(customCallCount == 1, "Custom handler should have been called once");
        
        // 禁用自定义监听器
        EventCoordinator.enableEventListeners(testTarget, false);
        testTarget.onRelease();
        assert(originalCallCount == 2, "Original handler should have been called twice");
        assert(customCallCount == 1, "Custom handler should not have been called when disabled");
        
        // 启用自定义监听器
        EventCoordinator.enableEventListeners(testTarget, true);
        testTarget.onRelease();
        assert(originalCallCount == 3, "Original handler should have been called three times");
        assert(customCallCount == 2, "Custom handler should have been called twice");
        
        // 清理
        EventCoordinator.clearEventListeners(testTarget);
        
        trace("-- testOriginalHandlers Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 5. 多目标对象测试
    //--------------------------------------------------------------------------
    
    private static function testMultipleTargets():Void {
        trace("\n-- testMultipleTargets --");
        
        var target1:Object = {};
        var target2:Object = {};
        
        var callCount1:Number = 0;
        var callCount2:Number = 0;
        
        EventCoordinator.addEventListener(target1, "onPress", function() { callCount1++; });
        EventCoordinator.addEventListener(target2, "onPress", function() { callCount2++; });
        
        // 触发 target1 的 onPress
        target1.onPress();
        assert(callCount1 == 1, "Target1's handler should have been called once");
        assert(callCount2 == 0, "Target2's handler should not have been called");
        
        // 触发 target2 的 onPress
        target2.onPress();
        assert(callCount1 == 1, "Target1's handler should remain at one call");
        assert(callCount2 == 1, "Target2's handler should have been called once");
        
        // 清理 target1
        EventCoordinator.clearEventListeners(target1);
        target1.onPress();
        target2.onPress();
        assert(callCount1 == 1, "After clearing, Target1's handler should not be called again");
        assert(callCount2 == 2, "Target2's handler should have been called twice");
        
        // 清理 target2
        EventCoordinator.clearEventListeners(target2);
        target2.onPress();
        assert(callCount2 == 2, "After clearing, Target2's handler should not be called again");
        
        trace("-- testMultipleTargets Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 6. onUnload 与用户自定义卸载逻辑测试
    //--------------------------------------------------------------------------
    
    private static function testUnloadHandling():Void {
        trace("\n-- testUnloadHandling --");
        
        // 此处假设在舞台可用的环境下
        var testTarget:MovieClip = _root.createEmptyMovieClip("testUnloadMC", _root.getNextHighestDepth());
        var unloadCallCount:Number = 0;
        var userUnloadCallCount:Number = 0;
        
        // 用户自定义卸载逻辑
        var userUnload:Function = function() { userUnloadCallCount++; };
        testTarget.onUnload = userUnload;
        
        // 添加事件监听器
        var handlerID:String = EventCoordinator.addEventListener(testTarget, "onMouseUp", function() { unloadCallCount++; });
        
        // 触发 onMouseUp
        testTarget.onMouseUp();
        assert(unloadCallCount == 1, "Handler should have been called once before unload");
        
        // 触发 onUnload
        testTarget.onUnload();
        // 触发事件后应被清理
        testTarget.onMouseUp();
        assert(unloadCallCount == 1, "Handler should not be called after unload");
        assert(userUnloadCallCount == 1, "User's onUnload should have been called once");
        
        // 再次执行用户卸载逻辑，确保仍可用
        testTarget.onUnload();
        assert(userUnloadCallCount == 2, "User's onUnload should have been called twice");
        
        // 清理
        _root.removeMovieClip(testTarget);
        
        trace("-- testUnloadHandling Completed --\n");
    }

    //--------------------------------------------------------------------------
    // 7. 新增：闭包捕获问题测试
    //--------------------------------------------------------------------------
    private static function testClosureCapture():Void {
        trace("\n-- testClosureCapture --");

        /**
        * 目标：验证对不同事件的 addEventListener，不应出现事件名“串线”或共享闭包的问题。
        * 做法：一次性注册多个不同事件，各自累加自己的计数器。
        * 然后单独触发，检查只对应的计数器被 +1。
        */

        var testTarget:Object = {};

        // 定义多种事件名
        var eventNames:Array = ["onPress", "onRelease", "onMouseUp", "onMouseDown"];

        // 为每个事件准备一个计数器
        var counters:Object = {};

        // “工厂函数”形式：返回一个新的处理器，内部捕获 lockedEvent
        var createHandler:Function = function(lockedEvent:String, counters:Object) {
            return function() {
                counters[lockedEvent]++;
            };
        };

        // 注册监听器
        for (var i:Number = 0; i < eventNames.length; i++) {
            var en:String = eventNames[i];
            counters[en] = 0;

            // 使用 createHandler() 创建并返回一个闭包
            var handler:Function = createHandler(en, counters);

            // 传给 addEventListener
            EventCoordinator.addEventListener(testTarget, en, handler);
        }

        // 依次触发事件，并检查只有对应计数器被 +1
        for (var j:Number = 0; j < eventNames.length; j++) {
            var triggerEvent:String = eventNames[j];

            // 调用 testTarget[triggerEvent]()：模拟事件触发
            testTarget[triggerEvent]();

            // 检查 counters
            for (var k:Number = 0; k < eventNames.length; k++) {
                var checkEvent:String = eventNames[k];
                var expected:Number = (k == j) ? 1 : 0;
                var actual:Number = counters[checkEvent];
                
                assert(
                    actual == expected,
                    "When calling " + triggerEvent + ", counters[" + checkEvent + "] should be " + expected + 
                    ", got " + actual
                );
            }

            // 重置所有 counters，以便下次触发测试更干净
            for (var m:Number = 0; m < eventNames.length; m++) {
                counters[eventNames[m]] = 0;
            }
        }

        // 清理
        EventCoordinator.clearEventListeners(testTarget);
        
        trace("-- testClosureCapture Completed --\n");
    }

    
    //--------------------------------------------------------------------------
    // 8. 性能测试
    //--------------------------------------------------------------------------
    
    private static function performanceTest():Void {
        trace("\n-- performanceTest --");
        
        // 建立目标对象 & 用于计数
        var testTarget:Object = {};
        var callCounter:Number = 0;
        
        // 1) 测试大批量注册
        var totalHandlers:Number = 5000;  // 可根据实际情况调大/调小
        var startReg:Number = getTimer();
        
        for (var i:Number = 0; i < totalHandlers; i++) {
            EventCoordinator.addEventListener(testTarget, "onPress", function() {
                // 累加计数器
                callCounter++;
            });
        }
        
        var endReg:Number = getTimer();
        var regTime:Number = endReg - startReg;
        trace("[Performance] Registered " + totalHandlers + " handlers in " + regTime + " ms.");
        
        // 2) 测试触发性能
        var startCall:Number = getTimer();
        // 触发多次
        var triggerCount:Number = 10;
        for (var j:Number = 0; j < triggerCount; j++) {
            if (testTarget.onPress) {
                testTarget.onPress();
            }
        }
        var endCall:Number = getTimer();
        var callTime:Number = endCall - startCall;
        trace("[Performance] Called onPress " + triggerCount + " times in " + callTime + " ms.");
        
        // 期望 callCounter == totalHandlers * triggerCount
        trace("[Performance] CallCounter = " + callCounter + 
              " (expected " + (totalHandlers * triggerCount) + ")");
        
        // 3) 测试大批量移除
        var startClear:Number = getTimer();
        EventCoordinator.clearEventListeners(testTarget);
        var endClear:Number = getTimer();
        trace("[Performance] Cleared all handlers in " + (endClear - startClear) + " ms.");
        
        trace("-- performanceTest Completed --\n");
    }
}
