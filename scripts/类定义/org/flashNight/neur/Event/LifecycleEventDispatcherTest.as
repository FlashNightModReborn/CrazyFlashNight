/**
 * LifecycleEventDispatcherTest.as
 *
 * 测试 LifecycleEventDispatcher 的正确性，特别是新增的目标转移功能。
 * 涵盖Boss多阶段切换等实际应用场景。
 */

import org.flashNight.neur.Event.*;
import org.flashNight.aven.Coordinator.*;

class org.flashNight.neur.Event.LifecycleEventDispatcherTest {
    
    private static var totalAssertions:Number = 0;
    private static var passedAssertions:Number = 0;
    private static var failedAssertions:Number = 0;
    
    /**
     * 入口：运行所有测试
     */
    public static function runAllTests():Void {
        trace("\n=== Running LifecycleEventDispatcher Tests ===");
        
        // 基础功能测试
        testBasicLifecycle();
        testEventBridging();
        testDestroyAndCleanup();
        
        // 目标转移功能测试
        testBasicTransfer();
        testTransferModes();
        testTransferWithEventStates();
        testStaticTransferMethods();
        testTransferEdgeCases();
        
        // 实战场景测试
        testBossPhaseTransfer();
        testComplexTransferChain();
        testTransferPerformance();
        
        trace("\n=== LifecycleEventDispatcher Tests Completed ===");
        trace("Total Assertions: " + totalAssertions);
        trace("Passed Assertions: " + passedAssertions);
        trace("Failed Assertions: " + failedAssertions + "\n");
    }
    
    //--------------------------------------------------------------------------
    // 断言方法
    //--------------------------------------------------------------------------
    
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
    // 1. 基础生命周期测试
    //--------------------------------------------------------------------------
    
    private static function testBasicLifecycle():Void {
        trace("\n-- testBasicLifecycle --");
        
        // 创建测试目标
        var testMC:MovieClip = _root.createEmptyMovieClip("testLifecycleMC", _root.getNextHighestDepth());
        
        // 创建LifecycleEventDispatcher
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(testMC);
        
        // 验证基础状态
        assert(!dispatcher.isDestroyed(), "Dispatcher should not be destroyed initially");
        assert(dispatcher.getTarget() === testMC, "Target should be correctly set");
        assert(testMC.dispatcher === dispatcher, "Bidirectional reference should be established");
        
        // 测试EventDispatcher继承功能
        var eventCallCount:Number = 0;
        dispatcher.subscribe("testEvent", function() { eventCallCount++; }, null);
        dispatcher.publish("testEvent");
        assert(eventCallCount == 1, "EventDispatcher functionality should work");
        
        // 手动销毁测试
        dispatcher.destroy();
        assert(dispatcher.isDestroyed(), "Dispatcher should be destroyed after destroy() call");
        assert(testMC.dispatcher == null, "Target reference should be cleared");
        
        // 清理
        _root.removeMovieClip(testMC);
        
        trace("-- testBasicLifecycle Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 2. 事件桥接功能测试
    //--------------------------------------------------------------------------
    
    private static function testEventBridging():Void {
        trace("\n-- testEventBridging --");
        
        var testMC:MovieClip = _root.createEmptyMovieClip("testBridgeMC", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(testMC);
        
        // 测试目标事件订阅
        var pressCallCount:Number = 0;
        var releaseCallCount:Number = 0;
        
        var pressID:String = dispatcher.subscribeTargetEvent("onPress", function() { 
            pressCallCount++; 
        }, null);
        
        var releaseID:String = dispatcher.subscribeTargetEvent("onRelease", function() { 
            releaseCallCount++; 
        }, null);
        
        assert(pressID != null, "subscribeTargetEvent should return valid ID");
        assert(releaseID != null, "subscribeTargetEvent should return valid ID");
        
        // 触发事件
        testMC.onPress();
        testMC.onRelease();
        assert(pressCallCount == 1 && releaseCallCount == 1, "Target events should be triggered");
        
        // 测试事件禁用
        dispatcher.enableTargetEvents(false);
        testMC.onPress();
        testMC.onRelease();
        assert(pressCallCount == 1 && releaseCallCount == 1, "Events should be disabled");
        
        // 重新启用
        dispatcher.enableTargetEvents(true);
        testMC.onPress();
        assert(pressCallCount == 2, "Events should be re-enabled");
        
        // 测试单个事件移除
        dispatcher.unsubscribeTargetEvent("onPress", pressID);
        testMC.onPress();
        assert(pressCallCount == 2, "Unsubscribed event should not trigger");

        // 测试统计功能
        var stats:Object = dispatcher.getTargetEventStats();

        // 【修复】断言逻辑，现在我们知道 onUnload 和 onRelease 两个事件是存在的。
        var expectedTotalEvents:Number = 2; // onRelease 和 onUnload
        var expectedTotalHandlers:Number = 2; // onRelease 的一个处理器和 onUnload 的一个处理器

        assert(stats.totalEvents == expectedTotalEvents, 
            "Should show " + expectedTotalEvents + " remaining events (onRelease, onUnload)");

        assert(stats.totalHandlers == expectedTotalHandlers, 
            "Should show " + expectedTotalHandlers + " remaining handlers");

        assert(stats.events["onRelease"] != undefined && stats.events["onRelease"].handlerCount == 1,
            "onRelease event should have exactly 1 handler");

        // 清理
        dispatcher.destroy();
        _root.removeMovieClip(testMC);
        
        trace("-- testEventBridging Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 3. 销毁和清理测试
    //--------------------------------------------------------------------------
    
    private static function testDestroyAndCleanup():Void {
        trace("\n-- testDestroyAndCleanup --");
        
        var testMC:MovieClip = _root.createEmptyMovieClip("testDestroyMC", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(testMC);
        
        // 添加一些事件和订阅
        var callCount:Number = 0;
        dispatcher.subscribe("localEvent", function() { callCount++; }, null);
        dispatcher.subscribeTargetEvent("onPress", function() { callCount++; }, null);
        
        // 验证正常工作
        dispatcher.publish("localEvent");
        testMC.onPress();
        assert(callCount == 2, "Events should work before destroy");
        
        // 通过onUnload自动销毁测试
        testMC.onUnload();
        assert(dispatcher.isDestroyed(), "Dispatcher should be auto-destroyed on target unload");
        
        // 验证销毁后的状态
        dispatcher.publish("localEvent");
        testMC.onPress();
        assert(callCount == 2, "Events should not work after destroy");
        
        // 测试重复销毁的安全性
        dispatcher.destroy();
        assert(true, "Multiple destroy calls should be safe");
        
        // 清理
        _root.removeMovieClip(testMC);
        
        trace("-- testDestroyAndCleanup Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 4. 基础转移测试
    //--------------------------------------------------------------------------
    
    private static function testBasicTransfer():Void {
        trace("\n-- testBasicTransfer --");
        
        var oldMC:MovieClip = _root.createEmptyMovieClip("oldTransferMC", _root.getNextHighestDepth());
        var newMC:MovieClip = _root.createEmptyMovieClip("newTransferMC", _root.getNextHighestDepth());
        
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(oldMC);
        
        // 添加事件监听器到旧目标
        var pressCallCount:Number = 0;
        var releaseCallCount:Number = 0;
        
        dispatcher.subscribeTargetEvent("onPress", function() { pressCallCount++; }, null);
        dispatcher.subscribeTargetEvent("onRelease", function() { releaseCallCount++; }, null);
        
        // 验证旧目标工作正常
        oldMC.onPress();
        oldMC.onRelease();
        assert(pressCallCount == 1 && releaseCallCount == 1, "Old target should work before transfer");
        
        // 执行转移
        var idMap:Object = dispatcher.transferAll(newMC, true);
        assert(idMap != null, "Transfer should return ID mapping");
        assert(dispatcher.getTarget() === newMC, "Target should be updated after transfer");
        assert(newMC.dispatcher === dispatcher, "New target should have correct dispatcher reference");
        assert(oldMC.dispatcher == null, "Old target reference should be cleared");
        
        // 验证新目标工作，旧目标被清理
        newMC.onPress();
        newMC.onRelease();
        assert(pressCallCount == 2 && releaseCallCount == 2, "New target should work after transfer");
        
        oldMC.onPress();
        oldMC.onRelease();
        assert(pressCallCount == 2 && releaseCallCount == 2, "Old target should be cleaned after transfer");
        
        // 测试生命周期转移
        var destroyCalled:Boolean = false;
        var originalDestroy:Function = dispatcher.destroy;
        dispatcher.destroy = function() {
            destroyCalled = true;
            originalDestroy.apply(this);
        };
        
        newMC.onUnload();
        assert(destroyCalled, "Lifecycle should be transferred to new target");
        
        // 清理
        _root.removeMovieClip(oldMC);
        _root.removeMovieClip(newMC);
        
        trace("-- testBasicTransfer Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 5. 转移模式测试
    //--------------------------------------------------------------------------
    
    private static function testTransferModes():Void {
        trace("\n-- testTransferModes --");
        
        var oldMC:MovieClip = _root.createEmptyMovieClip("oldModeMC", _root.getNextHighestDepth());
        var newMC:MovieClip = _root.createEmptyMovieClip("newModeMC", _root.getNextHighestDepth());
        
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(oldMC);
        
        // 添加多种事件
        var callCounts:Object = { press: 0, release: 0, mouseMove: 0, keyDown: 0 };
        
        dispatcher.subscribeTargetEvent("onPress", function() { callCounts.press++; }, null);
        dispatcher.subscribeTargetEvent("onRelease", function() { callCounts.release++; }, null);
        dispatcher.subscribeTargetEvent("onMouseMove", function() { callCounts.mouseMove++; }, null);
        dispatcher.subscribeTargetEvent("onKeyDown", function() { callCounts.keyDown++; }, null);
        
        // 测试 specific 模式转移
        var specificEvents:Array = ["onPress", "onRelease"];
        var idMap:Object = dispatcher.transferSpecific(newMC, specificEvents, true);
        
        // 验证只有指定事件被转移
        newMC.onPress();
        newMC.onRelease();
        newMC.onMouseMove();
        newMC.onKeyDown();
        
        assert(callCounts.press == 1 && callCounts.release == 1, "Specific events should be transferred");
        assert(callCounts.mouseMove == 0 && callCounts.keyDown == 0, "Non-specific events should not be transferred");
        
        // 验证旧目标的非转移事件仍然存在
        oldMC.onMouseMove();
        oldMC.onKeyDown();
        assert(callCounts.mouseMove == 1 && callCounts.keyDown == 1, "Non-transferred events should remain on old target");
        
        // 创建新的dispatcher测试exclude模式
        var dispatcher2:LifecycleEventDispatcher = new LifecycleEventDispatcher(oldMC);
        var newMC2:MovieClip = _root.createEmptyMovieClip("newMode2MC", _root.getNextHighestDepth());
        
        // 重新添加事件（因为之前的被部分清理了）
        callCounts = { press: 0, release: 0, mouseMove: 0, keyDown: 0 };
        dispatcher2.subscribeTargetEvent("onPress", function() { callCounts.press++; }, null);
        dispatcher2.subscribeTargetEvent("onRelease", function() { callCounts.release++; }, null);
        dispatcher2.subscribeTargetEvent("onMouseMove", function() { callCounts.mouseMove++; }, null);
        dispatcher2.subscribeTargetEvent("onKeyDown", function() { callCounts.keyDown++; }, null);
        
        // 测试 exclude 模式
        var excludeEvents:Array = ["onMouseMove", "onKeyDown"];
        var idMap2:Object = dispatcher2.transferExclude(newMC2, excludeEvents, true);
        
        // 验证排除的事件没有被转移
        newMC2.onPress();
        newMC2.onRelease();
        newMC2.onMouseMove();
        newMC2.onKeyDown();
        
        assert(callCounts.press == 1 && callCounts.release == 1, "Non-excluded events should be transferred");
        assert(callCounts.mouseMove == 0 && callCounts.keyDown == 0, "Excluded events should not be transferred");
        
        // 清理
        dispatcher.destroy();
        dispatcher2.destroy();
        _root.removeMovieClip(oldMC);
        _root.removeMovieClip(newMC);
        _root.removeMovieClip(newMC2);
        
        trace("-- testTransferModes Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 6. 转移时事件状态测试
    //--------------------------------------------------------------------------
    
    private static function testTransferWithEventStates():Void {
        trace("\n-- testTransferWithEventStates --");
        
        var oldMC:MovieClip = _root.createEmptyMovieClip("oldStateMC", _root.getNextHighestDepth());
        var newMC:MovieClip = _root.createEmptyMovieClip("newStateMC", _root.getNextHighestDepth());
        
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(oldMC);
        
        // 添加事件监听器
        var callCount:Number = 0;
        dispatcher.subscribeTargetEvent("onPress", function() { callCount++; }, null);
        
        // 禁用事件
        dispatcher.enableTargetEvents(false);
        
        // 执行转移
        var idMap:Object = dispatcher.transferAll(newMC, true);
        
        // 验证新目标的事件状态被正确同步（应该是禁用的）
        newMC.onPress();
        assert(callCount == 0, "Disabled state should be transferred to new target");
        
        // 启用新目标的事件
        dispatcher.enableTargetEvents(true);
        newMC.onPress();
        assert(callCount == 1, "Events should work after enabling on new target");
        
        // 清理
        dispatcher.destroy();
        _root.removeMovieClip(oldMC);
        _root.removeMovieClip(newMC);
        
        trace("-- testTransferWithEventStates Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 7. 静态转移方法测试
    //--------------------------------------------------------------------------
    
    private static function testStaticTransferMethods():Void {
        trace("\n-- testStaticTransferMethods --");
        
        var mc1:MovieClip = _root.createEmptyMovieClip("staticMC1", _root.getNextHighestDepth());
        var mc2:MovieClip = _root.createEmptyMovieClip("staticMC2", _root.getNextHighestDepth());
        
        var dispatcher1:LifecycleEventDispatcher = new LifecycleEventDispatcher(mc1);
        var dispatcher2:LifecycleEventDispatcher = new LifecycleEventDispatcher(mc2);
        
        // 在dispatcher1上添加事件
        var callCount:Number = 0;
        dispatcher1.subscribeTargetEvent("onPress", function() { callCount++; }, null);
        
        // 使用静态方法转移
        var idMap:Object = LifecycleEventDispatcher.transferBetweenDispatchers(
            dispatcher1, dispatcher2, "all", null
        );
        
        assert(idMap != null, "Static transfer should return ID mapping");
        
        // 验证转移效果
        mc2.onPress();
        assert(callCount == 1, "Static transfer should work correctly");
        
        mc1.onPress();
        assert(callCount == 1, "Source should be cleared after static transfer");
        
        // 测试错误处理
        var nullMap:Object = LifecycleEventDispatcher.transferBetweenDispatchers(
            null, dispatcher2, "all", null
        );
        assert(nullMap == null, "Static transfer with null source should return null");

        
        // 清理
        dispatcher1.destroy();
        dispatcher2.destroy();
        _root.removeMovieClip(mc1);
        _root.removeMovieClip(mc2);
        
        trace("-- testStaticTransferMethods Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 8. 转移边界情况测试
    //--------------------------------------------------------------------------
    
    private static function testTransferEdgeCases():Void {
        trace("\n-- testTransferEdgeCases --");
        
        var mc1:MovieClip = _root.createEmptyMovieClip("edgeMC1", _root.getNextHighestDepth());
        var mc2:MovieClip = _root.createEmptyMovieClip("edgeMC2", _root.getNextHighestDepth());
        
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(mc1);
        
        // 1. 转移到相同目标
        var sameMap:Object = dispatcher.transferAll(mc1, false);
        assert(sameMap != null, "Transfer to same target should be handled gracefully");
        assert(dispatcher.getTarget() === mc1, "Target should remain unchanged");
        
        // 2. 转移到null目标
        var nullMap:Object = dispatcher.transferAll(null, false);
        assert(nullMap == null, "Transfer to null target should return null");
        
        // 3. 销毁后的转移尝试
        dispatcher.destroy();
        var destroyedMap:Object = dispatcher.transferAll(mc2, false);
        assert(destroyedMap == null, "Transfer on destroyed dispatcher should return null");
        
        // 4. 测试已销毁实例的其他方法
        var stats:Object = dispatcher.getTargetEventStats();
        assert(stats.totalEvents == 0, "Destroyed dispatcher should return empty stats");
        
        var handlerID:String = dispatcher.subscribeTargetEvent("onPress", function() {}, null);
        assert(handlerID == null, "Subscribe on destroyed dispatcher should return null");
        
        // 清理
        _root.removeMovieClip(mc1);
        _root.removeMovieClip(mc2);
        
        trace("-- testTransferEdgeCases Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 9. Boss多阶段转移实战测试
    //--------------------------------------------------------------------------
    
    private static function testBossPhaseTransfer():Void {
        trace("\n-- testBossPhaseTransfer --");
        
        // 创建Boss三个阶段
        var bossPhase1:MovieClip = _root.createEmptyMovieClip("bossPhase1", _root.getNextHighestDepth());
        var bossPhase2:MovieClip = _root.createEmptyMovieClip("bossPhase2", _root.getNextHighestDepth());
        var bossPhase3:MovieClip = _root.createEmptyMovieClip("bossPhase3", _root.getNextHighestDepth());
        
        // 创建生命周期管理器
        var bossDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(bossPhase1);
        
        // 模拟Boss的AI、UI、音效系统
        var aiCalls:Number = 0;
        var uiCalls:Number = 0;
        var soundCalls:Number = 0;
        var playerInputCalls:Number = 0;
        
        // 添加各种系统的事件监听器
        bossDispatcher.subscribeTargetEvent("onEnterFrame", function() { aiCalls++; }, null);      // AI系统
        bossDispatcher.subscribeTargetEvent("onPress", function() { uiCalls++; }, null);          // UI交互
        bossDispatcher.subscribeTargetEvent("onRelease", function() { soundCalls++; }, null);     // 音效触发
        bossDispatcher.subscribeTargetEvent("onKeyDown", function() { playerInputCalls++; }, null); // 玩家输入
        
        // 阶段1测试
        bossPhase1.onEnterFrame();
        bossPhase1.onPress();
        assert(aiCalls == 1 && uiCalls == 1, "Phase1 systems should work normally");
        
        // 阶段1→阶段2转移
        trace("[Boss] Phase1 → Phase2 transformation...");
        var idMap1to2:Object = bossDispatcher.transferAll(bossPhase2, true);
        assert(idMap1to2 != null, "Phase1 to Phase2 transfer should succeed");
        
        // 验证阶段2工作，阶段1被清理
        bossPhase2.onEnterFrame();
        bossPhase2.onPress();
        bossPhase1.onEnterFrame(); // 应该无效
        assert(aiCalls == 2 && uiCalls == 2, "Phase2 should work, Phase1 should be cleaned");
        
        // 阶段2→阶段3转移（只转移核心系统，排除音效）
        trace("[Boss] Phase2 → Phase3 transformation...");
        var criticalSystems:Array = ["onEnterFrame", "onPress", "onKeyDown"];
        var idMap2to3:Object = bossDispatcher.transferSpecific(bossPhase3, criticalSystems, true);
        
        // 验证阶段3的核心系统工作
        bossPhase3.onEnterFrame();
        bossPhase3.onPress();
        bossPhase3.onKeyDown(65); // 'A' key
        assert(aiCalls == 3 && uiCalls == 3 && playerInputCalls == 1, "Phase3 critical systems should work");
        
        // 验证音效系统没有被转移（因为使用了specific模式）
        bossPhase3.onRelease();
        assert(soundCalls == 0, "Sound system should not be transferred in Phase3");
        
        // 最终Boss战结束，测试销毁
        trace("[Boss] Boss defeated, cleaning up...");
        bossDispatcher.destroy();
        assert(bossDispatcher.isDestroyed(), "Boss dispatcher should be destroyed");
        
        // 清理
        _root.removeMovieClip(bossPhase1);
        _root.removeMovieClip(bossPhase2);
        _root.removeMovieClip(bossPhase3);
        
        trace("-- testBossPhaseTransfer Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 10. 复杂转移链测试
    //--------------------------------------------------------------------------
    
    private static function testComplexTransferChain():Void {
        trace("\n-- testComplexTransferChain --");
        
        // 创建多个目标对象
        var targets:Array = [];
        for (var i:Number = 0; i < 5; i++) {
            targets[i] = _root.createEmptyMovieClip("chainMC" + i, _root.getNextHighestDepth());
        }
        
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(targets[0]);
        
        // 添加累积计数器
        var totalCalls:Number = 0;
        dispatcher.subscribeTargetEvent("onPress", function() { totalCalls++; }, null);
        
        // 执行链式转移：0→1→2→3→4
        for (var j:Number = 1; j < targets.length; j++) {
            trace("[Chain] Transferring from target " + (j-1) + " to target " + j);
            var idMap:Object = dispatcher.transferAll(targets[j], true);
            assert(idMap != null, "Chain transfer " + (j-1) + "→" + j + " should succeed");
            
            // 验证当前目标工作
            targets[j].onPress();
            assert(totalCalls == j, "Target " + j + " should work after transfer");
            
            // 验证之前的目标被清理
            if (j > 1) {
                targets[j-2].onPress();
                assert(totalCalls == j, "Previous targets should be cleaned");
            }
        }
        
        // 验证最终状态
        assert(dispatcher.getTarget() === targets[4], "Final target should be targets[4]");
        assert(targets[4].dispatcher === dispatcher, "Final bidirectional reference should be correct");
        
        // 清理
        dispatcher.destroy();
        for (var k:Number = 0; k < targets.length; k++) {
            _root.removeMovieClip(targets[k]);
        }
        
        trace("-- testComplexTransferChain Completed --\n");
    }
    
    //--------------------------------------------------------------------------
    // 11. 转移性能测试
    //--------------------------------------------------------------------------
    
    private static function testTransferPerformance():Void {
        trace("\n-- testTransferPerformance --");
        
        var oldMC:MovieClip = _root.createEmptyMovieClip("perfOldMC", _root.getNextHighestDepth());
        var newMC:MovieClip = _root.createEmptyMovieClip("perfNewMC", _root.getNextHighestDepth());
        
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(oldMC);
        
        // 创建大量事件监听器
        var handlerCount:Number = 500;
        var callCounter:Number = 0;
        
        var startReg:Number = getTimer();
        for (var i:Number = 0; i < handlerCount; i++) {
            dispatcher.subscribeTargetEvent("onEnterFrame", function() {
                callCounter++;
            }, null);
        }
        var endReg:Number = getTimer();
        trace("[Transfer Performance] Registered " + handlerCount + " handlers in " + (endReg - startReg) + " ms");
        
        // 测试转移性能
        var startTransfer:Number = getTimer();
        var idMap:Object = dispatcher.transferAll(newMC, true);
        var endTransfer:Number = getTimer();
        trace("[Transfer Performance] Transferred " + handlerCount + " handlers in " + (endTransfer - startTransfer) + " ms");
        
        // 验证转移正确性
        newMC.onEnterFrame();
        assert(callCounter == handlerCount, "All transferred handlers should work");
        
        // 测试销毁性能
        var startDestroy:Number = getTimer();
        dispatcher.destroy();
        var endDestroy:Number = getTimer();
        trace("[Transfer Performance] Destroyed dispatcher in " + (endDestroy - startDestroy) + " ms");
        
        // 清理
        _root.removeMovieClip(oldMC);
        _root.removeMovieClip(newMC);
        
        trace("-- testTransferPerformance Completed --\n");
    }
}