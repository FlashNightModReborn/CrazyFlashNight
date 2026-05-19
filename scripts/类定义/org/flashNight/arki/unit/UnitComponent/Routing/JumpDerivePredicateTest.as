import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * JumpDerivePredicate Test Suite
 * 真值表：飞行浮空 × 被动技能存在 × 被动技能.启用 × 按键命中
 */
class org.flashNight.arki.unit.UnitComponent.Routing.JumpDerivePredicateTest {

    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    private static function assertEquals(name:String, expected, actual):Void {
        testCount++;
        if (expected === actual) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (exp=" + expected + " act=" + actual + ")");
        }
    }

    private static function assertTrue(name:String, cond:Boolean):Void {
        testCount++;
        if (cond) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name);
        }
    }

    private static function assertFalse(name:String, cond:Boolean):Void {
        assertTrue(name, !cond);
    }

    public static function runAll():Boolean {
        trace("================================================================");
        trace("JumpDerivePredicate Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testTrigger_AllConditions();
        testTrigger_FlyingBlocks();
        testTrigger_NoPassiveEntry();
        testTrigger_PassiveNotEnabled();
        testTrigger_KeyNotPressed();
        testTrigger_PassiveEnabledFalsey();
        testTrigger_NullPassive();
        testTrigger_UndefinedKey();
        testTrigger_UndefinedFlying();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    private static function testTrigger_AllConditions():Void {
        trace("\n--- testTrigger_AllConditions ---");
        var passive = {启用: true};
        assertTrue("全条件命中 → 触发",
            JumpDerivePredicate.shouldTrigger(passive, false, true));
    }

    private static function testTrigger_FlyingBlocks():Void {
        trace("\n--- testTrigger_FlyingBlocks ---");
        var passive = {启用: true};
        assertFalse("飞行浮空时 → 不触发",
            JumpDerivePredicate.shouldTrigger(passive, true, true));
    }

    private static function testTrigger_NoPassiveEntry():Void {
        trace("\n--- testTrigger_NoPassiveEntry ---");
        assertFalse("被动技能 undefined → 不触发",
            JumpDerivePredicate.shouldTrigger(undefined, false, true));
    }

    private static function testTrigger_PassiveNotEnabled():Void {
        trace("\n--- testTrigger_PassiveNotEnabled ---");
        var passive = {启用: false};
        assertFalse("被动技能.启用 = false → 不触发",
            JumpDerivePredicate.shouldTrigger(passive, false, true));
    }

    private static function testTrigger_KeyNotPressed():Void {
        trace("\n--- testTrigger_KeyNotPressed ---");
        var passive = {启用: true};
        assertFalse("按键未命中 → 不触发",
            JumpDerivePredicate.shouldTrigger(passive, false, false));
    }

    private static function testTrigger_PassiveEnabledFalsey():Void {
        trace("\n--- testTrigger_PassiveEnabledFalsey ---");
        // 启用 undefined / 0 / "" 都视为不启用
        assertFalse("启用 undefined", JumpDerivePredicate.shouldTrigger({}, false, true));
        assertFalse("启用 0", JumpDerivePredicate.shouldTrigger({启用: 0}, false, true));
        assertFalse("启用 空字符串", JumpDerivePredicate.shouldTrigger({启用: ""}, false, true));
    }

    private static function testTrigger_NullPassive():Void {
        trace("\n--- testTrigger_NullPassive ---");
        assertFalse("被动技能 null → 不触发",
            JumpDerivePredicate.shouldTrigger(null, false, true));
    }

    private static function testTrigger_UndefinedKey():Void {
        trace("\n--- testTrigger_UndefinedKey ---");
        var passive = {启用: true};
        // undefined 按 === true 比较为 false
        assertFalse("按键 undefined → 不触发",
            JumpDerivePredicate.shouldTrigger(passive, false, undefined));
    }

    private static function testTrigger_UndefinedFlying():Void {
        trace("\n--- testTrigger_UndefinedFlying ---");
        var passive = {启用: true};
        // undefined !== true，飞行视为 false → 允许触发
        assertTrue("飞行 undefined + 全条件 → 触发",
            JumpDerivePredicate.shouldTrigger(passive, undefined, true));
    }
}
