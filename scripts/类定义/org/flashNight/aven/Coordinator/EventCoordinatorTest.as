/**
 * EventCoordinatorTest.as
 * 
 * 测试 org.flashNight.aven.Coordinator.EventCoordinator 的正确性和性能。
 */

import org.flashNight.aven.Coordinator.*;


class org.flashNight.aven.Coordinator.EventCoordinatorTest {
    
    /**
     * 入口：运行所有测试
     */
    public static function runAllTests():Void {
        trace("\n=== Running EventCoordinator Tests ===");
        testCoreFunctions();
        performanceTest();
        trace("=== Tests Completed ===\n");
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
        if (!condition) {
            trace("[ASSERTION FAILED]: " + message);
        } else {
            trace("[ASSERTION PASSED]: " + message);
        }
    }
    
    
    //--------------------------------------------------------------------------
    // 2. 核心功能测试
    //--------------------------------------------------------------------------
    
    private static function testCoreFunctions():Void {
        trace("\n-- testCoreFunctions --");
        
        // 假设这是一个测试用的目标对象，可以是 MovieClip，也可以是简单的 Object
        // 若需要可换成: var testMC:MovieClip = _root.createEmptyMovieClip("testMC", _root.getNextHighestDepth());
        // 这里为了简化演示，仅用 Object 进行模拟：
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
        callCount = 0; callCount2 = 0;
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
        
        // 4) 测试 onUnload 自动清理
        //    这里模拟 target.onUnload()
        EventCoordinator.addEventListener(testTarget, "onRollOver", function(){ /* do nothing */ });
        testTarget.onUnload();
        // 现在 onPress / onRollOver 等都应被清理
        if (testTarget.onPress) {
            testTarget.onPress();
        }
        assert(callCount == 1 && callCount2 == 1,
            "After onUnload's auto-cleanup, onPress should not increment counters anymore.");
        
        trace("-- testCoreFunctions Completed --\n");
    }
    
    
    //--------------------------------------------------------------------------
    // 3. 性能测试
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
        var regTime = endReg - startReg;
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
        var callTime = endCall - startCall;
        trace("[Performance] Called onPress " + triggerCount + " times in " + callTime + " ms.");
        
        // 期望 callCounter == totalHandlers * triggerCount
        trace("[Performance] CallCounter = " + callCounter + 
              " (expected " + (totalHandlers * triggerCount) + ")");
        
        // 3) 测试大批量移除
        //    这里简单地 clearAll 来比较
        var startClear:Number = getTimer();
        EventCoordinator.clearEventListeners(testTarget);
        var endClear:Number = getTimer();
        trace("[Performance] Cleared all handlers in " + (endClear - startClear) + " ms.");
        
        trace("-- performanceTest Completed --\n");
    }
}
