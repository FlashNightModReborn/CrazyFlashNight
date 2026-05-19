import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * JumpDerivePlan Test Suite
 *
 * 验证 build(passiveEntry, isFlying, keyComboPressed, targetState) 输出字段：
 *   - triggered 与 JumpDerivePredicate.shouldTrigger 严格同义
 *   - targetState 不依赖 triggered，始终保留
 */
class org.flashNight.arki.unit.UnitComponent.Routing.JumpDerivePlanTest {

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
        trace("JumpDerivePlan Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testBuild_Triggered_AllConditions();
        testBuild_Triggered_FlyingBlocks();
        testBuild_Triggered_NoEntry();
        testBuild_Triggered_NotEnabled();
        testBuild_Triggered_KeyNotPressed();
        testBuild_TargetState_Retained_OnTriggered();
        testBuild_TargetState_Retained_OnNotTriggered();
        testBuild_PolicyDifferentiation_兵器跳_vs_空手跳();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    private static function testBuild_Triggered_AllConditions():Void {
        trace("\n--- testBuild_Triggered_AllConditions ---");
        var passive = {启用: true};
        var plan:Object = JumpDerivePlan.build(passive, false, true, "兵器跳");
        assertEquals("triggered = true", true, plan.triggered);
    }

    private static function testBuild_Triggered_FlyingBlocks():Void {
        trace("\n--- testBuild_Triggered_FlyingBlocks ---");
        var passive = {启用: true};
        var plan:Object = JumpDerivePlan.build(passive, true, true, "兵器跳");
        assertEquals("飞行浮空 → triggered = false", false, plan.triggered);
    }

    private static function testBuild_Triggered_NoEntry():Void {
        trace("\n--- testBuild_Triggered_NoEntry ---");
        var plan:Object = JumpDerivePlan.build(undefined, false, true, "兵器跳");
        assertEquals("passiveEntry undefined → triggered = false", false, plan.triggered);
    }

    private static function testBuild_Triggered_NotEnabled():Void {
        trace("\n--- testBuild_Triggered_NotEnabled ---");
        var passive = {启用: false};
        var plan:Object = JumpDerivePlan.build(passive, false, true, "兵器跳");
        assertEquals("启用 false → triggered = false", false, plan.triggered);
    }

    private static function testBuild_Triggered_KeyNotPressed():Void {
        trace("\n--- testBuild_Triggered_KeyNotPressed ---");
        var passive = {启用: true};
        var plan:Object = JumpDerivePlan.build(passive, false, false, "兵器跳");
        assertEquals("按键未命中 → triggered = false", false, plan.triggered);
    }

    private static function testBuild_TargetState_Retained_OnTriggered():Void {
        trace("\n--- testBuild_TargetState_Retained_OnTriggered ---");
        var passive = {启用: true};
        var plan:Object = JumpDerivePlan.build(passive, false, true, "兵器跳");
        assertEquals("targetState 命中分支保留", "兵器跳", plan.targetState);
    }

    private static function testBuild_TargetState_Retained_OnNotTriggered():Void {
        trace("\n--- testBuild_TargetState_Retained_OnNotTriggered ---");
        var plan:Object = JumpDerivePlan.build(undefined, false, true, "空手跳");
        assertEquals("targetState 失败分支也保留", "空手跳", plan.targetState);
    }

    private static function testBuild_PolicyDifferentiation_兵器跳_vs_空手跳():Void {
        trace("\n--- testBuild_PolicyDifferentiation_兵器跳_vs_空手跳 ---");
        var passive = {启用: true};
        var planWeapon:Object = JumpDerivePlan.build(passive, false, true, "兵器跳");
        var planBare:Object   = JumpDerivePlan.build(passive, false, true, "空手跳");
        assertEquals("weapon plan.targetState=兵器跳", "兵器跳", planWeapon.targetState);
        assertEquals("bare plan.targetState=空手跳",   "空手跳", planBare.targetState);
        assertTrue("两路 plan 都 triggered=true",
            planWeapon.triggered === true && planBare.triggered === true);
    }
}
