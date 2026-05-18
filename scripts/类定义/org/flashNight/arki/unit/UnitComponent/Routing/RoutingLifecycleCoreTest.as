import org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle;

import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * RoutingLifecycleCore Test Suite
 *
 * 纯值输入/输出，不依赖 _root、MovieClip 或帧时间推进。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycleCoreTest {

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
        trace("RoutingLifecycleCore Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testResolveBonusMode();
        testResolveTempY();
        testFloatPredicates();
        testEndCleanupPredicate();
        testAnimationPredicates();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    private static function testResolveBonusMode():Void {
        trace("\n--- testResolveBonusMode ---");
        assertEquals("拳系 → 空手", "空手", RoutingLifecycleCore.resolveBonusMode(true));
        assertEquals("非拳系 → 技能", "技能", RoutingLifecycleCore.resolveBonusMode(false));
    }

    private static function testResolveTempY():Void {
        trace("\n--- testResolveTempY ---");
        assertEquals("已有正 temp_y 保留", 50, RoutingLifecycleCore.resolveTempY(50, true, 80, 320));
        assertEquals("浮空标记命中 → y", 280, RoutingLifecycleCore.resolveTempY(0, true, 280, 320));
        assertEquals("y < Z 兜底 → y", 250, RoutingLifecycleCore.resolveTempY(0, false, 250, 320));
        assertEquals("站立 → 0", 0, RoutingLifecycleCore.resolveTempY(0, false, 320, 320));
        assertEquals("Z 为 NaN → 0", 0, RoutingLifecycleCore.resolveTempY(0, false, 250, Number("nan")));
    }

    private static function testFloatPredicates():Void {
        trace("\n--- testFloatPredicates ---");
        assertTrue("temp_y > 0 可应用浮空", RoutingLifecycleCore.shouldApplyFloat(1));
        assertFalse("temp_y = 0 不应用浮空", RoutingLifecycleCore.shouldApplyFloat(0));
        assertFalse("temp_y NaN 不应用浮空", RoutingLifecycleCore.shouldApplyFloat(Number("nan")));
        assertTrue("y 小于 Z-0.5 → inAir", RoutingLifecycleCore.isInAir(299, 300));
        assertFalse("y 在容差内 → not inAir", RoutingLifecycleCore.isInAir(299.7, 300));
    }

    private static function testEndCleanupPredicate():Void {
        trace("\n--- testEndCleanupPredicate ---");
        assertTrue("状态不同 → reset", RoutingLifecycleCore.shouldResetOnEndCleanup("技能", "战技"));
        assertFalse("状态相同 → preserve", RoutingLifecycleCore.shouldResetOnEndCleanup("战技", "战技"));
        assertFalse("excludeState undefined 且 state undefined → preserve", RoutingLifecycleCore.shouldResetOnEndCleanup(undefined, undefined));
    }

    private static function testAnimationPredicates():Void {
        trace("\n--- testAnimationPredicates ---");
        assertTrue("二段跳 + 空中 → preserve", RoutingLifecycleCore.shouldPreserveDoubleJump(true, true));
        assertFalse("二段跳 + 地面 → 不 preserve", RoutingLifecycleCore.shouldPreserveDoubleJump(true, false));
        assertFalse("非二段跳 + 空中 → 不 preserve", RoutingLifecycleCore.shouldPreserveDoubleJump(false, true));

        assertTrue("非二段跳 + 空中 → 自然落地", RoutingLifecycleCore.shouldStartNaturalLanding(false, true));
        assertTrue("undefined enableDoubleJump + 空中 → 自然落地", RoutingLifecycleCore.shouldStartNaturalLanding(undefined, true));
        assertFalse("二段跳 + 空中 → 不自然落地", RoutingLifecycleCore.shouldStartNaturalLanding(true, true));
    }
}
