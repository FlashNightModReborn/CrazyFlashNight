/**
 * EventCoordinatorTest.as
 *
 * 测试 org.flashNight.aven.Coordinator.EventCoordinator 的正确性和性能。
 * 
 * 附加：testClosureCapture() 主要用于验证事件名称在闭包中是否正确锁定，
 *      防止潜在的"变量覆盖 / 闭包共享"问题。
 * 
 * 【新增】事件转移功能的完整测试套件，涵盖Boss多阶段切换等实际场景。
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
        testClosureCapture();
        
        // 【新增】事件转移功能测试
        testBasicTransfer();
        testSpecificTransfer();
        testTransferWithStates();
        testTransferIDMapping();
        testTransferEdgeCases();
        testMultiPhaseTransfer();
        testTransferPerformance();
        
        // 【新增】统计和调试功能测试
        testStatisticsFeatures();

        // [v2.2] 代码审查修复回归测试
        testWatchUnwatchLifecycle();
        testClearRestoresUserOnUnload();

        // [v2.3] 三方交叉审查综合修复回归测试
        testRemoveEventListenerFullCleanup();

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
        * 目标：验证对不同事件的 addEventListener，不应出现事件名"串线"或共享闭包的问题。
        * 做法：一次性注册多个不同事件，各自累加自己的计数器。
        * 然后单独触发，检查只对应的计数器被 +1。
        */

        var testTarget:Object = {};

        // 定义多种事件名
        var eventNames:Array = ["onPress", "onRelease", "onMouseUp", "onMouseDown"];

        // 为每个事件准备一个计数器
        var counters:Object = {};

        // "工厂函数"形式：返回一个新的处理器，内部捕获 lockedEvent
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
    // 【新增】8. 基础事件转移测试
    //--------------------------------------------------------------------------
    
    private static function testBasicTransfer():Void {
        trace("\n-- testBasicTransfer --");
        
        var oldTarget:Object = {};
        var newTarget:Object = {};
        
        // 在旧目标上添加多个监听器
        var callCounts:Object = { press: 0, release: 0, enterFrame: 0 };
        
        EventCoordinator.addEventListener(oldTarget, "onPress", function() { callCounts.press++; });
        EventCoordinator.addEventListener(oldTarget, "onRelease", function() { callCounts.release++; });
        EventCoordinator.addEventListener(oldTarget, "onEnterFrame", function() { callCounts.enterFrame++; });
        
        // 验证旧目标的监听器工作正常
        oldTarget.onPress();
        oldTarget.onRelease();
        assert(callCounts.press == 1 && callCounts.release == 1, 
               "Old target handlers should work before transfer");
        
        // 执行转移
        var idMap:Object = EventCoordinator.transferEventListeners(oldTarget, newTarget, true);
        assert(idMap != null, "transferEventListeners should return an ID mapping object");
        
        // 验证新目标的监听器工作正常
        newTarget.onPress();
        newTarget.onRelease();
        assert(callCounts.press == 2 && callCounts.release == 2, 
               "New target handlers should work after transfer");
        
        // 验证旧目标的监听器已被清理（因为 clearOld=true）
        oldTarget.onPress();
        oldTarget.onRelease();
        assert(callCounts.press == 2 && callCounts.release == 2, 
               "Old target handlers should be cleared after transfer with clearOld=true");
        
        // 清理
        EventCoordinator.clearEventListeners(newTarget);
        
        trace("-- testBasicTransfer Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 【新增】9. 指定事件转移测试
    //--------------------------------------------------------------------------
    
    private static function testSpecificTransfer():Void {
        trace("\n-- testSpecificTransfer --");
        
        var oldTarget:Object = {};
        var newTarget:Object = {};
        
        // 在旧目标上添加多个不同事件的监听器
        var callCounts:Object = { press: 0, release: 0, mouseMove: 0, keyDown: 0 };
        
        EventCoordinator.addEventListener(oldTarget, "onPress", function() { callCounts.press++; });
        EventCoordinator.addEventListener(oldTarget, "onRelease", function() { callCounts.release++; });
        EventCoordinator.addEventListener(oldTarget, "onMouseMove", function() { callCounts.mouseMove++; });
        EventCoordinator.addEventListener(oldTarget, "onKeyDown", function() { callCounts.keyDown++; });
        
        // 只转移部分事件
        var eventsToTransfer:Array = ["onPress", "onRelease"];
        var idMap:Object = EventCoordinator.transferSpecificEventListeners(
            oldTarget, newTarget, eventsToTransfer, true
        );
        
        assert(idMap != null, "transferSpecificEventListeners should return an ID mapping object");
        
        // 验证转移的事件在新目标上工作
        newTarget.onPress();
        newTarget.onRelease();
        assert(callCounts.press == 1 && callCounts.release == 1, 
               "Transferred events should work on new target");
        
        // 验证未转移的事件在旧目标上仍然工作
        oldTarget.onMouseMove();
        oldTarget.onKeyDown();
        assert(callCounts.mouseMove == 1 && callCounts.keyDown == 1, 
               "Non-transferred events should still work on old target");
        
        // 验证转移的事件在旧目标上已被清理
        oldTarget.onPress();
        oldTarget.onRelease();
        assert(callCounts.press == 1 && callCounts.release == 1, 
               "Transferred events should be cleared from old target when clearOld=true");
        
        // 清理
        EventCoordinator.clearEventListeners(oldTarget);
        EventCoordinator.clearEventListeners(newTarget);
        
        trace("-- testSpecificTransfer Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 【新增】10. 转移时状态同步测试
    //--------------------------------------------------------------------------
    
    private static function testTransferWithStates():Void {
        trace("\n-- testTransferWithStates --");
        
        var oldTarget:Object = {};
        var newTarget:Object = {};
        
        // 设置原生事件处理器
        var originalCallCount:Number = 0;
        oldTarget.onPress = function() { originalCallCount++; };
        newTarget.onPress = function() { originalCallCount += 10; }; // 用不同数值区分
        
        // 添加自定义监听器
        var customCallCount:Number = 0;
        EventCoordinator.addEventListener(oldTarget, "onPress", function() { customCallCount++; });
        
        // 禁用旧目标的监听器
        EventCoordinator.enableEventListeners(oldTarget, false);
        
        // 执行转移
        var idMap:Object = EventCoordinator.transferEventListeners(oldTarget, newTarget, true);
        
        // 验证新目标的自定义监听器被禁用（状态同步）
        newTarget.onPress();
        assert(customCallCount == 0, "Custom handlers should be disabled on new target (state sync)");
        assert(originalCallCount == 10, "Original handler should work on new target");
        
        // 启用新目标的监听器
        EventCoordinator.enableEventListeners(newTarget, true);
        newTarget.onPress();
        assert(customCallCount == 1, "Custom handlers should work after enabling on new target");
        assert(originalCallCount == 20, "Original handler should continue working");
        
        // 清理
        EventCoordinator.clearEventListeners(newTarget);
        
        trace("-- testTransferWithStates Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 【新增】11. ID映射测试
    //--------------------------------------------------------------------------
    
    private static function testTransferIDMapping():Void {
        trace("\n-- testTransferIDMapping --");
        
        var oldTarget:Object = {};
        var newTarget:Object = {};
        
        // 添加监听器并记录原始ID
        var callCount:Number = 0;
        var oldID1:String = EventCoordinator.addEventListener(oldTarget, "onPress", function() { callCount++; });
        var oldID2:String = EventCoordinator.addEventListener(oldTarget, "onPress", function() { callCount += 10; });
        
        // 执行转移
        var idMap:Object = EventCoordinator.transferEventListeners(oldTarget, newTarget, false);
        
        // 验证ID映射的正确性
        assert(idMap[oldID1] != null, "Old ID1 should be mapped to a new ID");
        assert(idMap[oldID2] != null, "Old ID2 should be mapped to a new ID");
        assert(idMap[oldID1] != idMap[oldID2], "Different old IDs should map to different new IDs");
        
        // 验证可以通过新ID移除监听器
        var newID1:String = idMap[oldID1];
        EventCoordinator.removeEventListener(newTarget, "onPress", newID1);
        
        // 触发事件，只有第二个处理器应该被调用
        newTarget.onPress();
        assert(callCount == 10, "After removing first handler via new ID, only second should be called");
        
        // 清理
        EventCoordinator.clearEventListeners(oldTarget);
        EventCoordinator.clearEventListeners(newTarget);
        
        trace("-- testTransferIDMapping Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 【新增】12. 转移边界情况测试
    //--------------------------------------------------------------------------
    
    private static function testTransferEdgeCases():Void {
        trace("\n-- testTransferEdgeCases --");
        
        // 1) 空对象转移
        var emptyTarget:Object = {};
        var normalTarget:Object = {};
        var idMap:Object = EventCoordinator.transferEventListeners(emptyTarget, normalTarget, true);
        assert(idMap != null, "Transfer from empty target should return empty mapping");
        assert(typeof idMap == "object", "Should return object even for empty transfer");
        
        // 2) 相同对象转移
        var sameTarget:Object = {};
        EventCoordinator.addEventListener(sameTarget, "onPress", function() {});
        var sameMap:Object = EventCoordinator.transferEventListeners(sameTarget, sameTarget, false);
        assert(sameMap != null, "Transfer to same target should be handled gracefully");
        
        // 3) null/undefined 参数
        var nullMap:Object = EventCoordinator.transferEventListeners(null, normalTarget, true);
        assert(nullMap == null, "Transfer with null old target should return null");
        
        var undefinedMap:Object = EventCoordinator.transferEventListeners(normalTarget, undefined, true);
        assert(undefinedMap == null, "Transfer with undefined new target should return null");
        
        // 4) 转移不存在的事件
        var sourceTarget:Object = {};
        var targetObj:Object = {};
        var nonExistentEvents:Array = ["onNonExistent1", "onNonExistent2"];
        var specificMap:Object = EventCoordinator.transferSpecificEventListeners(
            sourceTarget, targetObj, nonExistentEvents, true
        );
        assert(specificMap != null, "Transfer of non-existent events should return empty mapping");
        
        // 清理
        EventCoordinator.clearEventListeners(sameTarget);
        EventCoordinator.clearEventListeners(normalTarget);
        
        trace("-- testTransferEdgeCases Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 【新增】13. 多阶段转移测试（Boss A→B→C 场景）
    //--------------------------------------------------------------------------
    
    private static function testMultiPhaseTransfer():Void {
        trace("\n-- testMultiPhaseTransfer --");
        
        // 模拟Boss三阶段切换
        var bossPhase1:Object = { name: "Phase1" };
        var bossPhase2:Object = { name: "Phase2" };
        var bossPhase3:Object = { name: "Phase3" };
        
        // 阶段1：添加AI、UI、音效监听器
        var aiCallCount:Number = 0;
        var uiCallCount:Number = 0;
        var soundCallCount:Number = 0;
        
        EventCoordinator.addEventListener(bossPhase1, "onEnterFrame", function() { aiCallCount++; }); // AI逻辑
        EventCoordinator.addEventListener(bossPhase1, "onPress", function() { uiCallCount++; });     // UI交互
        EventCoordinator.addEventListener(bossPhase1, "onRelease", function() { soundCallCount++; }); // 音效触发
        
        // 验证阶段1正常工作
        bossPhase1.onEnterFrame();
        bossPhase1.onPress();
        assert(aiCallCount == 1 && uiCallCount == 1, "Phase1 should work normally");
        
        // 阶段1→阶段2 转移
        var idMap1to2:Object = EventCoordinator.transferEventListeners(bossPhase1, bossPhase2, true);
        assert(idMap1to2 != null, "Phase1 to Phase2 transfer should succeed");
        
        // 验证阶段2工作，阶段1被清理
        bossPhase2.onEnterFrame();
        bossPhase2.onPress();
        bossPhase1.onEnterFrame(); // 应该无效
        assert(aiCallCount == 2 && uiCallCount == 2, "Phase2 should work, Phase1 should be cleared");
        
        // 阶段2→阶段3 转移
        var idMap2to3:Object = EventCoordinator.transferEventListeners(bossPhase2, bossPhase3, true);
        assert(idMap2to3 != null, "Phase2 to Phase3 transfer should succeed");
        
        // 验证阶段3工作，阶段2被清理
        bossPhase3.onEnterFrame();
        bossPhase3.onPress();
        bossPhase2.onEnterFrame(); // 应该无效
        assert(aiCallCount == 3 && uiCallCount == 3, "Phase3 should work, Phase2 should be cleared");
        
        // 最终清理
        EventCoordinator.clearEventListeners(bossPhase3);
        
        trace("-- testMultiPhaseTransfer Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 【新增】14. 统计功能测试
    //--------------------------------------------------------------------------
    
    private static function testStatisticsFeatures():Void {
        trace("\n-- testStatisticsFeatures --");
        
        var testTarget:Object = {};
        
        // 初始状态：无监听器
        var initialStats:Object = EventCoordinator.getEventListenerStats(testTarget);
        assert(initialStats.totalEvents == 0, "Initial stats should show 0 events");
        assert(initialStats.totalHandlers == 0, "Initial stats should show 0 handlers");
        
        // 添加多个事件的监听器
        EventCoordinator.addEventListener(testTarget, "onPress", function() {});
        EventCoordinator.addEventListener(testTarget, "onPress", function() {}); // 同事件多处理器
        EventCoordinator.addEventListener(testTarget, "onRelease", function() {});
        
        // 检查统计信息
        var stats:Object = EventCoordinator.getEventListenerStats(testTarget);
        assert(stats.totalEvents == 2, "Should show 2 different events");
        assert(stats.totalHandlers == 3, "Should show 3 total handlers");
        assert(stats.events["onPress"].handlerCount == 2, "onPress should have 2 handlers");
        assert(stats.events["onRelease"].handlerCount == 1, "onRelease should have 1 handler");
        assert(stats.events["onPress"].isEnabled == true, "Events should be enabled by default");
        
        // 测试禁用状态
        EventCoordinator.enableEventListeners(testTarget, false);
        var disabledStats:Object = EventCoordinator.getEventListenerStats(testTarget);
        assert(disabledStats.events["onPress"].isEnabled == false, "Events should show disabled state");
        
        // 测试原生处理器检测
        testTarget.onMouseMove = function() {}; // 设置原生处理器
        EventCoordinator.addEventListener(testTarget, "onMouseMove", function() {}); // 添加自定义
        var withOriginalStats:Object = EventCoordinator.getEventListenerStats(testTarget);
        assert(withOriginalStats.events["onMouseMove"].hasOriginal == true, 
               "Should detect original handler");
        
        // 测试全局统计（这里只验证不报错，实际输出在trace中）
        EventCoordinator.listAllTargets();
        assert(true, "listAllTargets should execute without errors");
        
        // 清理
        EventCoordinator.clearEventListeners(testTarget);
        
        trace("-- testStatisticsFeatures Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 【新增】15. 转移性能测试
    //--------------------------------------------------------------------------
    
    private static function testTransferPerformance():Void {
        trace("\n-- testTransferPerformance --");
        
        var oldTarget:Object = {};
        var newTarget:Object = {};
        
        // 创建大量监听器
        var handlerCount:Number = 1000;
        var callCounter:Number = 0;
        
        var startReg:Number = getTimer();
        for (var i:Number = 0; i < handlerCount; i++) {
            EventCoordinator.addEventListener(oldTarget, "onEnterFrame", function() {
                callCounter++;
            });
        }
        var endReg:Number = getTimer();
        trace("[Transfer Performance] Registered " + handlerCount + " handlers in " + (endReg - startReg) + " ms");
        
        // 测试转移性能
        var startTransfer:Number = getTimer();
        var idMap:Object = EventCoordinator.transferEventListeners(oldTarget, newTarget, true);
        var endTransfer:Number = getTimer();
        trace("[Transfer Performance] Transferred " + handlerCount + " handlers in " + (endTransfer - startTransfer) + " ms");
        
        // 验证转移正确性
        newTarget.onEnterFrame();
        assert(callCounter == handlerCount, "All transferred handlers should work");
        
        // 测试清理性能
        var startClear:Number = getTimer();
        EventCoordinator.clearEventListeners(newTarget);
        var endClear:Number = getTimer();
        trace("[Transfer Performance] Cleared " + handlerCount + " handlers in " + (endClear - startClear) + " ms");
        
        trace("-- testTransferPerformance Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // [v2.2] 16. watch/unwatch 生命周期测试
    //--------------------------------------------------------------------------

    /**
     * [v2.2 回归测试 P0-3] 验证 clearEventListeners 正确释放 watch 拦截器
     * 修复问题：之前 clearEventListeners 不调用 unwatch("onUnload")，
     *          导致 watch 拦截器残留，可能引发内存泄漏或意外行为
     */
    private static function testWatchUnwatchLifecycle():Void {
        trace("\n-- [v2.2 P0-3] testWatchUnwatchLifecycle --");

        // 创建测试 MovieClip
        var testMC:MovieClip = _root.createEmptyMovieClip("testWatchMC_" + getTimer(), _root.getNextHighestDepth());

        // 添加事件监听器（这会设置 watch 拦截器用于自动清理）
        var callCount:Number = 0;
        EventCoordinator.addEventListener(testMC, "onPress", function() { callCount++; });

        // 验证监听器工作
        testMC.onPress();
        assert(callCount == 1, "[v2.2 P0-3] Listener should work before clear");

        // 调用 clearEventListeners - 这应该释放 watch 拦截器
        EventCoordinator.clearEventListeners(testMC);

        // 验证监听器已被清理
        testMC.onPress();
        assert(callCount == 1, "[v2.2 P0-3] Listener should not work after clear");

        // [关键验证] 重新添加监听器应该正常工作
        // 如果 watch 拦截器没有被正确释放，重新添加可能会有问题
        var newCallCount:Number = 0;
        EventCoordinator.addEventListener(testMC, "onRelease", function() { newCallCount++; });

        testMC.onRelease();
        assert(newCallCount == 1, "[v2.2 P0-3] New listener should work after clear and re-add");

        // 清理
        EventCoordinator.clearEventListeners(testMC);
        testMC.removeMovieClip();

        trace("-- [v2.2 P0-3] testWatchUnwatchLifecycle Completed --\n");
    }

    /**
     * [v2.2 回归测试 P0-3 扩展] 验证 clearEventListeners 正确恢复用户原始 onUnload
     * 修复问题：之前 clearEventListeners 删除时目标对象错误，
     *          导致用户原始的 onUnload 函数无法正确恢复
     */
    private static function testClearRestoresUserOnUnload():Void {
        trace("\n-- [v2.2 P0-3] testClearRestoresUserOnUnload --");

        // 创建测试 MovieClip
        var testMC:MovieClip = _root.createEmptyMovieClip("testRestoreMC_" + getTimer(), _root.getNextHighestDepth());

        // 设置用户自定义的 onUnload 处理器
        var userUnloadCalled:Number = 0;
        var userOnUnload:Function = function() {
            userUnloadCalled++;
        };
        testMC.onUnload = userOnUnload;

        // 添加 EventCoordinator 监听器
        var customCallCount:Number = 0;
        EventCoordinator.addEventListener(testMC, "onPress", function() { customCallCount++; });

        // 验证监听器工作
        testMC.onPress();
        assert(customCallCount == 1, "[v2.2 P0-3 ext] Custom listener should work");

        // 清理 EventCoordinator 监听器
        EventCoordinator.clearEventListeners(testMC);

        // [关键验证] 用户的 onUnload 应该被恢复并可调用
        // 如果恢复逻辑有bug，testMC.onUnload 可能是 undefined 或错误的函数
        assert(testMC.onUnload != undefined, "[v2.2 P0-3 ext] onUnload should be restored after clear");

        // 调用 onUnload 验证是用户原始的函数
        testMC.onUnload();
        assert(userUnloadCalled == 1, "[v2.2 P0-3 ext] User's original onUnload should be called");

        // 再次调用确认仍然是用户的函数
        testMC.onUnload();
        assert(userUnloadCalled == 2, "[v2.2 P0-3 ext] User's onUnload should continue to work");

        // 清理
        testMC.removeMovieClip();

        trace("-- [v2.2 P0-3] testClearRestoresUserOnUnload Completed --\n");
    }

    //--------------------------------------------------------------------------
    // [v2.3] 17. removeEventListener 完整清理测试 (I2)
    //--------------------------------------------------------------------------

    /**
     * [v2.3 回归测试 I2] 验证 removeEventListener 在移除最后一个事件时执行完整清理
     * 修复问题：当所有事件都被移除后，应该调用 unwatch("onUnload") 并恢复用户的 onUnload
     */
    private static function testRemoveEventListenerFullCleanup():Void {
        trace("\n-- [v2.3 I2] testRemoveEventListenerFullCleanup --");

        // 创建测试 MovieClip
        var testMC:MovieClip = _root.createEmptyMovieClip("fullCleanupMC_" + getTimer(), _root.getNextHighestDepth());

        // 1. 设置用户的原始 onUnload 处理器
        var userOnUnloadCalled:Boolean = false;
        testMC.onUnload = function():Void {
            userOnUnloadCalled = true;
        };
        var originalOnUnload:Function = testMC.onUnload;

        // 2. 添加事件监听器（这会设置 watch 拦截器和自动清理）
        var pressCallCount:Number = 0;
        var releaseCallCount:Number = 0;

        var pressID:String = EventCoordinator.addEventListener(testMC, "onPress", function():Void {
            pressCallCount++;
        });

        var releaseID:String = EventCoordinator.addEventListener(testMC, "onRelease", function():Void {
            releaseCallCount++;
        });

        assert(pressID != null, "[v2.3 I2] addEventListener should return valid ID for onPress");
        assert(releaseID != null, "[v2.3 I2] addEventListener should return valid ID for onRelease");

        // 3. 验证监听器工作
        testMC.onPress();
        testMC.onRelease();
        assert(pressCallCount == 1, "[v2.3 I2] onPress handler should work");
        assert(releaseCallCount == 1, "[v2.3 I2] onRelease handler should work");

        // 4. 移除 onPress 监听器（不是最后一个事件，不应触发完整清理）
        var removeResult1:Boolean = EventCoordinator.removeEventListener(testMC, "onPress", pressID);
        assert(removeResult1 == true, "[v2.3 I2] removeEventListener should return true for valid removal");

        // 5. 验证 onPress 已被移除但 onRelease 仍然工作
        pressCallCount = 0;
        releaseCallCount = 0;
        testMC.onPress();
        testMC.onRelease();
        assert(pressCallCount == 0, "[v2.3 I2] onPress handler should be removed");
        assert(releaseCallCount == 1, "[v2.3 I2] onRelease handler should still work");

        // 6. 移除 onRelease 监听器（这是最后一个事件，应触发完整清理）
        var removeResult2:Boolean = EventCoordinator.removeEventListener(testMC, "onRelease", releaseID);
        assert(removeResult2 == true, "[v2.3 I2] removeEventListener should return true for last event removal");

        // 7. 验证 onRelease 已被移除
        releaseCallCount = 0;
        testMC.onRelease();
        assert(releaseCallCount == 0, "[v2.3 I2] onRelease handler should be removed after full cleanup");

        // 8. 关键验证：用户的原始 onUnload 应该被恢复
        // 注意：由于 watch 拦截器的特性，直接检查函数引用可能不准确
        // 我们通过触发 onUnload 来验证用户的处理器是否被恢复
        userOnUnloadCalled = false;
        testMC.onUnload();
        assert(userOnUnloadCalled == true, "[v2.3 I2] CRITICAL - User's original onUnload should be restored after full cleanup");

        // 9. 验证可以重新添加监听器（完整清理后状态应该是干净的）
        var newCallCount:Number = 0;
        var newID:String = EventCoordinator.addEventListener(testMC, "onMouseMove", function():Void {
            newCallCount++;
        });
        assert(newID != null, "[v2.3 I2] Should be able to add new listener after full cleanup");

        testMC.onMouseMove();
        assert(newCallCount == 1, "[v2.3 I2] New listener should work after full cleanup");

        // 清理
        EventCoordinator.clearEventListeners(testMC);
        _root.removeMovieClip(testMC);

        trace("-- [v2.3 I2] testRemoveEventListenerFullCleanup Completed --\n");
    }

    //--------------------------------------------------------------------------
    // 18. 原有性能测试
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