// Tier1ComponentTest.as - Tier 1生命周期组件测试套件
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * Tier 1生命周期组件测试
 *
 * 测试组件：
 * 1. StackLimitComponent - 层数限制
 * 2. CooldownComponent - 冷却时间
 * 3. ConditionComponent - 条件触发
 */
class org.flashNight.arki.component.Buff.test.Tier1ComponentTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;

    /**
     * 运行所有测试
     */
    public static function runAllTests():Void {
        trace("=== Tier 1 Component Test Suite ===\n");

        testCount = 0;
        passedCount = 0;
        failedCount = 0;

        trace("--- StackLimitComponent Tests ---");
        testStackLimitBasic();
        testStackLimitMaxStacks();
        testStackLimitDecay();
        testStackLimitWithMetaBuff();

        trace("\n--- CooldownComponent Tests ---");
        testCooldownBasic();
        testCooldownActivation();
        testCooldownReset();
        testCooldownReduction();

        trace("\n--- ConditionComponent Tests ---");
        testConditionBasic();
        testConditionDynamic();
        testConditionInvert();
        testConditionWithMetaBuff();

        printTestResults();
    }

    // ========== StackLimitComponent 测试 ==========

    private static function testStackLimitBasic():Void {
        startTest("StackLimit Basic Operations");

        try {
            var stackComp:StackLimitComponent = new StackLimitComponent(5, 0);

            // 初始层数应为1
            assert(stackComp.getCurrentStacks() == 1, "Initial stacks should be 1");
            assert(stackComp.getMaxStacks() == 5, "Max stacks should be 5");

            // 增加层数
            assert(stackComp.addStack() == true, "Should be able to add stack");
            assert(stackComp.getCurrentStacks() == 2, "Stacks should be 2");

            // 减少层数
            assert(stackComp.removeStack(1) == true, "Should be able to remove stack");
            assert(stackComp.getCurrentStacks() == 1, "Stacks should be 1 after removal");

            trace("  ✓ Basic: init=1, add→2, remove→1");

            passTest();
        } catch (e) {
            failTest("Stack basic test failed: " + e.message);
        }
    }

    private static function testStackLimitMaxStacks():Void {
        startTest("StackLimit Max Stacks");

        try {
            var stackComp:StackLimitComponent = new StackLimitComponent(3, 0);

            // 叠到上限
            stackComp.addStack(); // 2
            stackComp.addStack(); // 3

            assert(stackComp.isMaxStacks() == true, "Should be at max stacks");

            // 尝试超过上限
            var canAdd:Boolean = stackComp.addStack();
            assert(canAdd == false, "Should not be able to exceed max");
            assert(stackComp.getCurrentStacks() == 3, "Stacks should remain 3");

            trace("  ✓ Max: 1→2→3, cannot add 4th");

            passTest();
        } catch (e) {
            failTest("Stack max test failed: " + e.message);
        }
    }

    private static function testStackLimitDecay():Void {
        startTest("StackLimit Decay");

        try {
            // 每60帧衰减1层
            var stackComp:StackLimitComponent = new StackLimitComponent(5, 60);
            stackComp.addStack();
            stackComp.addStack(); // 3层

            // 更新30帧，不应衰减
            var alive:Boolean = stackComp.update(null, 30);
            assert(alive == true, "Should be alive after 30 frames");
            assert(stackComp.getCurrentStacks() == 3, "Stacks should still be 3");

            // 再更新30帧，总共60帧，应衰减1层
            alive = stackComp.update(null, 30);
            assert(alive == true, "Should be alive after decay");
            assert(stackComp.getCurrentStacks() == 2, "Stacks should decay to 2");

            trace("  ✓ Decay: 3 stacks, 60 frames → 2 stacks");

            passTest();
        } catch (e) {
            failTest("Stack decay test failed: " + e.message);
        }
    }

    private static function testStackLimitWithMetaBuff():Void {
        startTest("StackLimit with MetaBuff");

        try {
            var mockTarget:Object = {atk: 100};
            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 创建可叠加的攻击Buff
            var atkBuff:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
            var stackComp:StackLimitComponent = new StackLimitComponent(5, 0);
            var metaBuff:MetaBuff = new MetaBuff([atkBuff], [stackComp], 0);

            manager.addBuff(metaBuff, "stackable_atk");
            manager.update(1);

            // 初始：100 + 10 = 110
            var value1:Number = mockTarget.atk;
            assert(value1 == 110, "Initial value should be 110, got " + value1);

            // 增加层数 (需手动调整PodBuff值来模拟)
            stackComp.addStack(); // 2层
            atkBuff.setValue(20); // 2层 * 10 = 20
            manager.update(1);

            var value2:Number = mockTarget.atk;
            assert(value2 == 120, "With 2 stacks should be 120, got " + value2);

            trace("  ✓ MetaBuff: 1 stack=110, 2 stacks=120");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Stack+MetaBuff test failed: " + e.message);
        }
    }

    // ========== CooldownComponent 测试 ==========

    private static function testCooldownBasic():Void {
        startTest("Cooldown Basic Operations");

        try {
            var cdComp:CooldownComponent = new CooldownComponent(60, true, true);

            // 初始应就绪
            assert(cdComp.isReady() == true, "Should be ready initially");
            assert(cdComp.getRemainingFrames() == 0, "Remaining should be 0");

            // 激活后进入冷却
            var activated:Boolean = cdComp.tryActivate();
            assert(activated == true, "Should activate successfully");
            assert(cdComp.isReady() == false, "Should not be ready after activation");
            assert(cdComp.getRemainingFrames() == 60, "Remaining should be 60");

            trace("  ✓ Basic: ready → activate → cooling (60 frames)");

            passTest();
        } catch (e) {
            failTest("Cooldown basic test failed: " + e.message);
        }
    }

    private static function testCooldownActivation():Void {
        startTest("Cooldown Activation & Recovery");

        try {
            var cdComp:CooldownComponent = new CooldownComponent(60, true, true);

            cdComp.tryActivate(); // 进入冷却

            // 冷却中不应能再次激活
            var canActivate:Boolean = cdComp.tryActivate();
            assert(canActivate == false, "Should not activate during cooldown");

            // 更新30帧
            cdComp.update(null, 30);
            assert(cdComp.getRemainingFrames() == 30, "Remaining should be 30");
            assert(cdComp.isReady() == false, "Should still be cooling");

            // 再更新30帧，冷却完成
            cdComp.update(null, 30);
            assert(cdComp.getRemainingFrames() == 0, "Remaining should be 0");
            assert(cdComp.isReady() == true, "Should be ready after cooldown");

            trace("  ✓ Activation: cooling 60 frames → ready");

            passTest();
        } catch (e) {
            failTest("Cooldown activation test failed: " + e.message);
        }
    }

    private static function testCooldownReset():Void {
        startTest("Cooldown Reset");

        try {
            var cdComp:CooldownComponent = new CooldownComponent(60, true, true);

            cdComp.tryActivate();
            cdComp.update(null, 20); // 冷却20帧

            assert(cdComp.getRemainingFrames() == 40, "Should have 40 frames remaining");

            // 立即重置
            cdComp.resetCooldown();
            assert(cdComp.isReady() == true, "Should be ready after reset");
            assert(cdComp.getRemainingFrames() == 0, "Remaining should be 0");

            trace("  ✓ Reset: 40 frames remaining → instant reset → ready");

            passTest();
        } catch (e) {
            failTest("Cooldown reset test failed: " + e.message);
        }
    }

    private static function testCooldownReduction():Void {
        startTest("Cooldown Reduction");

        try {
            var cdComp:CooldownComponent = new CooldownComponent(100, true, true);

            cdComp.tryActivate(); // 100帧冷却

            // 减少30帧冷却
            cdComp.reduceCooldown(30);
            assert(cdComp.getRemainingFrames() == 70, "Should have 70 frames after reduction");

            // 再减少80帧，应直接就绪
            cdComp.reduceCooldown(80);
            assert(cdComp.isReady() == true, "Should be ready after over-reduction");
            assert(cdComp.getRemainingFrames() == 0, "Remaining should be 0");

            trace("  ✓ Reduction: 100 -30 = 70, -80 = 0 (ready)");

            passTest();
        } catch (e) {
            failTest("Cooldown reduction test failed: " + e.message);
        }
    }

    // ========== ConditionComponent 测试 ==========

    private static function testConditionBasic():Void {
        startTest("Condition Basic Operations");

        try {
            var testValue:Number = 50;

            // 条件: testValue > 30
            var condComp:ConditionComponent = new ConditionComponent(
                function():Boolean { return testValue > 30; },
                1,
                false
            );

            // 初始条件满足
            var alive:Boolean = condComp.update(null, 1);
            assert(alive == true, "Should be alive when condition met");
            assert(condComp.getLastCheckResult() == true, "Check result should be true");

            // 改变条件使其不满足
            testValue = 20;
            alive = condComp.update(null, 1);
            assert(alive == false, "Should fail when condition not met");

            trace("  ✓ Basic: value=50 (>30) alive, value=20 (<30) fail");

            passTest();
        } catch (e) {
            failTest("Condition basic test failed: " + e.message);
        }
    }

    private static function testConditionDynamic():Void {
        startTest("Condition Dynamic Check");

        try {
            var counter:Number = 0;

            // 条件: counter < 3
            var condComp:ConditionComponent = new ConditionComponent(
                function():Boolean { return counter < 3; },
                10, // 每10帧检查
                false
            );

            // 前9帧不检查
            var alive:Boolean = condComp.update(null, 9);
            counter = 5; // 改变值，但未检查
            assert(alive == true, "Should be alive (not checked yet)");

            // 第10帧检查，counter=5 不满足条件
            alive = condComp.update(null, 1);
            assert(alive == false, "Should fail after check (counter=5)");

            trace("  ✓ Dynamic: check interval=10, fails on 10th frame");

            passTest();
        } catch (e) {
            failTest("Condition dynamic test failed: " + e.message);
        }
    }

    private static function testConditionInvert():Void {
        startTest("Condition Invert");

        try {
            var flag:Boolean = true;

            // 反转条件: flag==true时失效
            var condComp:ConditionComponent = new ConditionComponent(
                function():Boolean { return flag; },
                1,
                true // 反转
            );

            // flag=true，反转后应失效
            var alive:Boolean = condComp.update(null, 1);
            assert(alive == false, "Should fail when inverted condition returns true");

            // flag=false，反转后应存活
            flag = false;
            var condComp2:ConditionComponent = new ConditionComponent(
                function():Boolean { return flag; },
                1,
                true
            );
            alive = condComp2.update(null, 1);
            assert(alive == true, "Should be alive when inverted condition returns false");

            trace("  ✓ Invert: flag=true → fail, flag=false → alive");

            passTest();
        } catch (e) {
            failTest("Condition invert test failed: " + e.message);
        }
    }

    private static function testConditionWithMetaBuff():Void {
        startTest("Condition with MetaBuff");

        try {
            var mockTarget:Object = {hp: 100, maxHp: 100, dmg: 50};
            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 背水一战: HP < 30% 时 +50% 伤害
            var dmgBuff:PodBuff = new PodBuff("dmg", BuffCalculationType.PERCENT, 0.5);
            var condComp:ConditionComponent = new ConditionComponent(
                function():Boolean { return mockTarget.hp < mockTarget.maxHp * 0.3; },
                1,
                false
            );
            var berserkMeta:MetaBuff = new MetaBuff([dmgBuff], [condComp], 0);

            manager.addBuff(berserkMeta, "berserk");
            manager.update(1);

            // HP=100 > 30，条件不满足，Buff应失效
            var debugInfo:Object = manager.getDebugInfo();
            assert(debugInfo.metaBuffs == 0, "MetaBuff should be removed (HP not low enough)");

            // 降低HP，重新添加Buff
            mockTarget.hp = 20; // < 30
            mockTarget.dmg = 50;
            var berserkMeta2:MetaBuff = new MetaBuff([dmgBuff], [
                new ConditionComponent(
                    function():Boolean { return mockTarget.hp < mockTarget.maxHp * 0.3; },
                    1,
                    false
                )
            ], 0);
            manager.addBuff(berserkMeta2, "berserk2");
            manager.update(1);

            // HP=20 < 30，条件满足，Buff应激活
            var value:Number = mockTarget.dmg;
            assert(value == 75, "Damage should be 75 (50 * 1.5), got " + value);

            trace("  ✓ Condition+MetaBuff: HP=100 no buff, HP=20 +50% damage");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Condition+MetaBuff test failed: " + e.message);
        }
    }

    // ========== 工具方法 ==========

    private static function startTest(testName:String):Void {
        testCount++;
        trace("🧪 Test " + testCount + ": " + testName);
    }

    private static function passTest():Void {
        passedCount++;
        trace("  ✅ PASSED\n");
    }

    private static function failTest(message:String):Void {
        failedCount++;
        trace("  ❌ FAILED: " + message + "\n");
    }

    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }

    private static function printTestResults():Void {
        trace("\n=== Tier 1 Component Test Results ===");
        trace("📊 Total tests: " + testCount);
        trace("✅ Passed: " + passedCount);
        trace("❌ Failed: " + failedCount);
        trace("📈 Success rate: " + Math.round((passedCount / testCount) * 100) + "%");

        if (failedCount == 0) {
            trace("🎉 All Tier 1 component tests passed!");
        } else {
            trace("⚠️  " + failedCount + " test(s) failed.");
        }
        trace("=========================================");
    }
}
