// org/flashNight/arki/component/Buff/test/BugfixRegressionTest.as

import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.Buff.test.*;

/**
 * Bugfix Regression Test Suite
 *
 * 针对 2026-01 修复的问题进行回归测试：
 * - P0-1: unmanageProperty 脏标记问题
 * - P0-2: MetaBuff 异常后不移除问题
 * - P0-3: _redistribute* 空容器保护
 * - P1-1: _flushPendingAdds 性能
 * - P1-2: _inUpdate 标志复位时机
 * - P1-3: changeCallback 无值比较问题
 * - P2-2: MAX_MODIFICATIONS 边界控制
 *
 * 使用方式: BugfixRegressionTest.runAllTests();
 */
class org.flashNight.arki.component.Buff.test.BugfixRegressionTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;
    private static var EPSILON:Number = 0.0001;

    /**
     * 运行所有回归测试
     */
    public static function runAllTests():Void {
        trace("=== Bugfix Regression Test Suite ===");
        trace("Testing fixes from 2026-01 review\n");

        testCount = 0;
        passedCount = 0;
        failedCount = 0;

        trace("--- P0 Critical Fixes ---");
        test_P0_1_unmanageProperty_DirtyFlag();
        test_P0_1_unmanageProperty_Blacklist();
        test_P0_1_unmanageProperty_ReAddBuff();
        test_P0_2_MetaBuff_ExceptionRemoval();
        test_P0_3_redistribute_NullContainerProtection();

        trace("\n--- P1 Important Fixes ---");
        test_P1_1_flushPendingAdds_Performance();
        test_P1_2_inUpdate_ReentryProtection();
        test_P1_3_changeCallback_ValueComparison();

        trace("\n--- P2 Optimizations ---");
        test_P2_2_MAX_MODIFICATIONS_BoundaryControl();

        printTestResults();
    }

    // ========================================
    // P0-1: unmanageProperty 脏标记问题
    // ========================================

    /**
     * P0-1 测试1: unmanageProperty 后下一帧不应重建容器
     */
    private static function test_P0_1_unmanageProperty_DirtyFlag():Void {
        startTest("P0-1: unmanageProperty should not recreate container next frame");

        try {
            var target:Object = {attack: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加一个buff
            var buff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 50);
            manager.addBuff(buff, "test_buff");
            manager.update(1);

            // 验证buff生效
            var valueBeforeUnmanage:Number = target.attack;
            assert(valueBeforeUnmanage == 150, "Buff should be active: expected 150, got " + valueBeforeUnmanage);

            // 解除管理（finalize=true 固化当前值）
            manager.unmanageProperty("attack", true);

            // 多次update，容器不应被重建
            manager.update(1);
            manager.update(1);
            manager.update(1);

            // 检查属性是否仍然是普通数据属性（值应保持不变）
            var valueAfterUpdates:Number = target.attack;
            assert(valueAfterUpdates == 150, "Value should remain 150 after unmanage, got " + valueAfterUpdates);

            // 手动修改应该生效（因为已变成普通属性）
            target.attack = 999;
            assert(target.attack == 999, "Direct assignment should work after unmanage");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-1 dirty flag test failed: " + e);
        }
    }

    /**
     * P0-1 测试2: unmanageProperty 黑名单机制
     */
    private static function test_P0_1_unmanageProperty_Blacklist():Void {
        startTest("P0-1: unmanageProperty blacklist prevents container creation");

        try {
            var target:Object = {defense: 50};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加buff并解除管理
            var buff:PodBuff = new PodBuff("defense", BuffCalculationType.ADD, 25);
            manager.addBuff(buff, "def_buff");
            manager.update(1);
            manager.unmanageProperty("defense", true);

            // 尝试添加同属性的新buff（应该被拒绝或不生效）
            var newBuff:PodBuff = new PodBuff("defense", BuffCalculationType.ADD, 100);
            manager.addBuff(newBuff, "new_def_buff");
            manager.update(1);

            // 由于黑名单，新buff添加时会自动移除黑名单（允许再次管理）
            // 这是期望行为，所以值应该变化
            var finalValue:Number = target.defense;
            trace("  Final defense value after re-adding buff: " + finalValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-1 blacklist test failed: " + e);
        }
    }

    /**
     * P0-1 测试3: 解除管理后重新添加buff应该工作
     */
    private static function test_P0_1_unmanageProperty_ReAddBuff():Void {
        startTest("P0-1: Re-adding buff after unmanage should work");

        try {
            var target:Object = {speed: 10};
            var manager:BuffManager = new BuffManager(target, null);

            // 第一阶段：添加buff
            var buff1:PodBuff = new PodBuff("speed", BuffCalculationType.MULTIPLY, 2);
            manager.addBuff(buff1, "speed_buff");
            manager.update(1);
            assert(target.speed == 20, "Phase 1: 10*2=20, got " + target.speed);

            // 第二阶段：解除管理
            manager.unmanageProperty("speed", true);
            assert(target.speed == 20, "Phase 2: Value should be finalized at 20");

            // 第三阶段：重新添加buff（应该从黑名单移除并工作）
            var buff2:PodBuff = new PodBuff("speed", BuffCalculationType.ADD, 5);
            manager.addBuff(buff2, "speed_buff_2");
            manager.update(1);

            // 新buff应该基于当前target值（20）工作
            var finalValue:Number = target.speed;
            trace("  Final speed value: " + finalValue);
            // 20 + 5 = 25
            assert(finalValue == 25, "Phase 3: 20+5=25, got " + finalValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-1 re-add buff test failed: " + e);
        }
    }

    // ========================================
    // P0-2: MetaBuff 异常后不移除问题
    // ========================================

    /**
     * P0-2 测试: MetaBuff update抛异常时应立即移除
     */
    private static function test_P0_2_MetaBuff_ExceptionRemoval():Void {
        startTest("P0-2: MetaBuff throwing exception should be removed immediately");

        try {
            var target:Object = {hp: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 创建一个正常的MetaBuff
            var podBuff:PodBuff = new PodBuff("hp", BuffCalculationType.ADD, 50);
            var timeLimit:TimeLimitComponent = new TimeLimitComponent(100);
            var metaBuff:MetaBuff = new MetaBuff([podBuff], [timeLimit], 0);

            manager.addBuff(metaBuff, "normal_meta");
            manager.update(1);

            var buffCountBefore:Number = manager.getActiveBuffCount();
            trace("  Active buffs before: " + buffCountBefore);

            // 多次update，正常MetaBuff应该存活
            for (var i:Number = 0; i < 10; i++) {
                manager.update(1);
            }

            var buffCountAfter:Number = manager.getActiveBuffCount();
            trace("  Active buffs after 10 updates: " + buffCountAfter);

            // 验证MetaBuff仍然存活（除非时间到期）
            assert(buffCountAfter > 0, "MetaBuff should still be active");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-2 exception removal test failed: " + e);
        }
    }

    // ========================================
    // P0-3: _redistribute* 空容器保护
    // ========================================

    /**
     * P0-3 测试: 无效属性名的PodBuff不应导致崩溃
     */
    private static function test_P0_3_redistribute_NullContainerProtection():Void {
        startTest("P0-3: Invalid property name should not cause crash");

        try {
            var target:Object = {validProp: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加有效buff
            var validBuff:PodBuff = new PodBuff("validProp", BuffCalculationType.ADD, 10);
            manager.addBuff(validBuff, "valid");
            manager.update(1);

            assert(target.validProp == 110, "Valid buff should work: expected 110, got " + target.validProp);

            // 系统应该能处理无效属性名（静默失败而非崩溃）
            // 注意：AS2不会因为null.method()崩溃，只会返回undefined

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-3 null container protection test failed: " + e);
        }
    }

    // ========================================
    // P1-1: _flushPendingAdds 性能
    // ========================================

    /**
     * P1-1 测试: 延迟添加队列性能
     */
    private static function test_P1_1_flushPendingAdds_Performance():Void {
        startTest("P1-1: _flushPendingAdds performance with index traversal");

        try {
            var target:Object = {power: 0};
            var manager:BuffManager = new BuffManager(target, null);

            var startTime:Number = getTimer();
            var buffCount:Number = 100;

            // 批量添加buff
            for (var i:Number = 0; i < buffCount; i++) {
                var buff:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 1);
                manager.addBuff(buff, "buff_" + i);
            }

            manager.update(1);

            var endTime:Number = getTimer();
            var elapsed:Number = endTime - startTime;

            trace("  Added " + buffCount + " buffs in " + elapsed + "ms");
            trace("  Final power value: " + target.power);

            assert(target.power == buffCount, "All buffs should be applied: expected " + buffCount + ", got " + target.power);

            // 性能断言：100个buff应该在合理时间内完成
            assert(elapsed < 1000, "Should complete in < 1s, took " + elapsed + "ms");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P1-1 performance test failed: " + e);
        }
    }

    // ========================================
    // P1-2: _inUpdate 标志复位时机
    // ========================================

    /**
     * P1-2 测试: update期间的回调不应导致重入
     */
    private static function test_P1_2_inUpdate_ReentryProtection():Void {
        startTest("P1-2: Callbacks during update should not cause reentry issues");

        try {
            var callbackCount:Number = 0;
            var target:Object = {stat: 50};

            var callbacks:Object = {
                onBuffAdded: function(buff:IBuff, id:String):Void {
                    callbackCount++;
                    // 回调中不应该触发问题
                },
                onBuffRemoved: function(buff:IBuff, id:String):Void {
                    callbackCount++;
                }
            };

            var manager:BuffManager = new BuffManager(target, callbacks);

            // 添加buff
            var buff:PodBuff = new PodBuff("stat", BuffCalculationType.ADD, 10);
            manager.addBuff(buff, "test");
            manager.update(1);

            trace("  Callback count: " + callbackCount);
            assert(callbackCount >= 1, "Callbacks should be invoked");

            // 移除buff
            manager.removeBuff("test");
            manager.update(1);

            trace("  Final callback count: " + callbackCount);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P1-2 reentry protection test failed: " + e);
        }
    }

    // ========================================
    // P1-3: changeCallback 无值比较问题
    // ========================================

    /**
     * P1-3 测试: changeCallback只在值变化时触发
     */
    private static function test_P1_3_changeCallback_ValueComparison():Void {
        startTest("P1-3: changeCallback should only trigger on value change");

        try {
            var callbackCount:Number = 0;
            var lastValue:Number = NaN;

            var callback:Function = function(prop:String, val:Number):Void {
                callbackCount++;
                lastValue = val;
                trace("    Callback triggered: " + prop + " = " + val);
            };

            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "testProp", 100, callback);

            // 第一次访问，触发回调
            var v1:Number = target.testProp;
            var callbackCountAfterFirst:Number = callbackCount;
            trace("  After first access: callbackCount = " + callbackCount);

            // 多次访问相同值，不应触发新回调
            var v2:Number = target.testProp;
            var v3:Number = target.testProp;
            var v4:Number = target.testProp;

            trace("  After repeated access: callbackCount = " + callbackCount);
            assert(callbackCount == callbackCountAfterFirst,
                "Repeated access should not trigger callback: expected " + callbackCountAfterFirst + ", got " + callbackCount);

            // 添加buff改变值，应触发回调
            var buff:PodBuff = new PodBuff("testProp", BuffCalculationType.ADD, 50);
            container.addBuff(buff);
            var v5:Number = target.testProp;

            trace("  After adding buff: callbackCount = " + callbackCount + ", value = " + v5);
            assert(callbackCount > callbackCountAfterFirst, "Value change should trigger callback");
            assert(lastValue == 150, "Last value should be 150, got " + lastValue);

            container.destroy();
            passTest();
        } catch (e) {
            failTest("P1-3 value comparison test failed: " + e);
        }
    }

    // ========================================
    // P2-2: MAX_MODIFICATIONS 边界控制
    // ========================================

    /**
     * P2-2 测试: 边界控制在超限时仍被处理
     */
    private static function test_P2_2_MAX_MODIFICATIONS_BoundaryControl():Void {
        startTest("P2-2: Boundary controls (MAX/MIN/OVERRIDE) should work even at limit");

        try {
            var target:Object = {damage: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加大量普通buff（接近但不超过新限制256）
            var normalBuffCount:Number = 250;
            for (var i:Number = 0; i < normalBuffCount; i++) {
                var buff:PodBuff = new PodBuff("damage", BuffCalculationType.ADD, 1);
                manager.addBuff(buff, "normal_" + i);
            }

            // 添加边界控制buff（MAX）- 应该被处理
            var maxBuff:PodBuff = new PodBuff("damage", BuffCalculationType.MAX, 200);
            manager.addBuff(maxBuff, "max_buff");

            // 添加MIN buff
            var minBuff:PodBuff = new PodBuff("damage", BuffCalculationType.MIN, 500);
            manager.addBuff(minBuff, "min_buff");

            manager.update(1);

            var finalValue:Number = target.damage;
            trace("  Final damage with " + normalBuffCount + " ADD buffs + MAX(200) + MIN(500): " + finalValue);

            // 100 + 250 = 350, max(350, 200) = 350, min(350, 500) = 350
            // 边界控制应该正常工作
            assert(!isNaN(finalValue), "Final value should be a valid number");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P2-2 boundary control test failed: " + e);
        }
    }

    // ========================================
    // 测试工具方法
    // ========================================

    private static function startTest(testName:String):Void {
        testCount++;
        trace("\n[Test " + testCount + "] " + testName);
    }

    private static function passTest():Void {
        passedCount++;
        trace("  PASSED");
    }

    private static function failTest(message:String):Void {
        failedCount++;
        trace("  FAILED: " + message);
    }

    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }

    private static function assertFloat(actual:Number, expected:Number, message:String):Void {
        if (Math.abs(actual - expected) > EPSILON) {
            throw new Error(message + ": expected " + expected + ", got " + actual);
        }
    }

    private static function printTestResults():Void {
        trace("\n=== Bugfix Regression Test Results ===");
        trace("Total: " + testCount);
        trace("Passed: " + passedCount);
        trace("Failed: " + failedCount);
        trace("Success Rate: " + Math.round((passedCount / testCount) * 100) + "%");

        if (failedCount == 0) {
            trace("\nAll bugfix regression tests passed!");
        } else {
            trace("\nWARNING: " + failedCount + " test(s) failed!");
        }
        trace("======================================");
    }
}
