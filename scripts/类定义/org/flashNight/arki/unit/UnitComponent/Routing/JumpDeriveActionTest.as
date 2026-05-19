import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * JumpDeriveAction Test Suite
 *
 * 副作用断言：fake unit + fake man，spy 状态改变 / removeMovieClip。
 *   - execute(triggered=false) → 完全 no-op
 *   - execute(triggered=true) → 跳横移速度/跳跃中移动速度 写回 + 状态改变 + man remove
 *   - 状态改变收到 plan.targetState
 *   - tryDerive 一行入口 == build + execute 等价
 *
 * fake unit/man 全 untyped（见 [[feedback-as2-strict-function-param-dynamic-path]]）。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.JumpDeriveActionTest {

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

    // ====================================================================
    // fakes
    // ====================================================================

    private static function makeUnit(walkSpeed:Number) {
        var u = {
            行走X速度: walkSpeed,
            跳横移速度: undefined,
            跳跃中移动速度: undefined,
            飞行浮空: false,
            __spy_state_count: 0,
            __spy_state_last: undefined
        };
        u.状态改变 = function(s) {
            this.__spy_state_count++;
            this.__spy_state_last = s;
        };
        return u;
    }

    private static function makeMan() {
        var m = { __removed: false };
        m.removeMovieClip = function() {
            this.__removed = true;
        };
        return m;
    }

    // ====================================================================
    public static function runAll():Boolean {
        trace("================================================================");
        trace("JumpDeriveAction Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testExecute_NotTriggered_NoOp();
        testExecute_Triggered_WritesSpeeds();
        testExecute_Triggered_CallsStateChange();
        testExecute_Triggered_RemovesMan();
        testExecute_Triggered_ReturnsTrue();
        testExecute_TargetStateForwarded_兵器跳();
        testExecute_TargetStateForwarded_空手跳();
        testTryDerive_EndToEnd_Triggered();
        testTryDerive_EndToEnd_Flying_NoOp();
        testTryDerive_PolicyAlignment_BothPaths();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ====================================================================
    // execute
    // ====================================================================

    private static function testExecute_NotTriggered_NoOp():Void {
        trace("\n--- testExecute_NotTriggered_NoOp ---");
        var u = makeUnit(8);
        var m = makeMan();
        var plan:Object = { triggered: false, targetState: "兵器跳" };

        var ret:Boolean = JumpDeriveAction.execute(u, m, plan);

        assertEquals("returns false", false, ret);
        assertEquals("跳横移速度 未写", undefined, u.跳横移速度);
        assertEquals("跳跃中移动速度 未写", undefined, u.跳跃中移动速度);
        assertEquals("状态改变 未调用", 0, u.__spy_state_count);
        assertFalse("man 未 remove", m.__removed);
    }

    private static function testExecute_Triggered_WritesSpeeds():Void {
        trace("\n--- testExecute_Triggered_WritesSpeeds ---");
        var u = makeUnit(9);
        var m = makeMan();
        var plan:Object = { triggered: true, targetState: "兵器跳" };

        JumpDeriveAction.execute(u, m, plan);

        assertEquals("跳横移速度 = 行走X速度", 9, u.跳横移速度);
        assertEquals("跳跃中移动速度 = 行走X速度", 9, u.跳跃中移动速度);
    }

    private static function testExecute_Triggered_CallsStateChange():Void {
        trace("\n--- testExecute_Triggered_CallsStateChange ---");
        var u = makeUnit(8);
        var m = makeMan();
        var plan:Object = { triggered: true, targetState: "空手跳" };

        JumpDeriveAction.execute(u, m, plan);

        assertEquals("状态改变 调用 1 次", 1, u.__spy_state_count);
        assertEquals("状态改变 收到 targetState", "空手跳", u.__spy_state_last);
    }

    private static function testExecute_Triggered_RemovesMan():Void {
        trace("\n--- testExecute_Triggered_RemovesMan ---");
        var u = makeUnit(8);
        var m = makeMan();
        var plan:Object = { triggered: true, targetState: "兵器跳" };

        JumpDeriveAction.execute(u, m, plan);

        assertTrue("man 被 remove", m.__removed);
    }

    private static function testExecute_Triggered_ReturnsTrue():Void {
        trace("\n--- testExecute_Triggered_ReturnsTrue ---");
        var u = makeUnit(8);
        var m = makeMan();
        var plan:Object = { triggered: true, targetState: "兵器跳" };

        var ret:Boolean = JumpDeriveAction.execute(u, m, plan);

        assertEquals("returns true", true, ret);
    }

    private static function testExecute_TargetStateForwarded_兵器跳():Void {
        trace("\n--- testExecute_TargetStateForwarded_兵器跳 ---");
        var u = makeUnit(8);
        var m = makeMan();
        JumpDeriveAction.execute(u, m, { triggered: true, targetState: "兵器跳" });
        assertEquals("targetState=兵器跳 → 状态改变(兵器跳)", "兵器跳", u.__spy_state_last);
    }

    private static function testExecute_TargetStateForwarded_空手跳():Void {
        trace("\n--- testExecute_TargetStateForwarded_空手跳 ---");
        var u = makeUnit(8);
        var m = makeMan();
        JumpDeriveAction.execute(u, m, { triggered: true, targetState: "空手跳" });
        assertEquals("targetState=空手跳 → 状态改变(空手跳)", "空手跳", u.__spy_state_last);
    }

    // ====================================================================
    // tryDerive
    // ====================================================================

    private static function testTryDerive_EndToEnd_Triggered():Void {
        trace("\n--- testTryDerive_EndToEnd_Triggered ---");
        var u = makeUnit(10);
        u.飞行浮空 = false;
        var m = makeMan();
        var passive = { 启用: true };

        var ret:Boolean = JumpDeriveAction.tryDerive(u, m, passive, true, "空手跳");

        assertEquals("tryDerive 返回 true", true, ret);
        assertEquals("跳横移速度 = 行走X速度", 10, u.跳横移速度);
        assertEquals("跳跃中移动速度 = 行走X速度", 10, u.跳跃中移动速度);
        assertEquals("状态改变 收到 空手跳", "空手跳", u.__spy_state_last);
        assertTrue("man 被 remove", m.__removed);
    }

    private static function testTryDerive_EndToEnd_Flying_NoOp():Void {
        trace("\n--- testTryDerive_EndToEnd_Flying_NoOp ---");
        var u = makeUnit(10);
        u.飞行浮空 = true;
        var m = makeMan();
        var passive = { 启用: true };

        var ret:Boolean = JumpDeriveAction.tryDerive(u, m, passive, true, "空手跳");

        assertEquals("飞行浮空 → tryDerive 返回 false", false, ret);
        assertEquals("跳横移速度 未写", undefined, u.跳横移速度);
        assertEquals("状态改变 未调用", 0, u.__spy_state_count);
        assertFalse("man 未 remove", m.__removed);
    }

    /**
     * 关键反向断言：两条派生路径（兵器/空手）副作用模板必须完全等价，
     * 只有 targetState 字符串不同。任意一处副作用漂移都会被本测试发现。
     */
    private static function testTryDerive_PolicyAlignment_BothPaths():Void {
        trace("\n--- testTryDerive_PolicyAlignment_BothPaths ---");
        var passive = { 启用: true };

        // 兵器路径
        var uW = makeUnit(12);
        var mW = makeMan();
        JumpDeriveAction.tryDerive(uW, mW, passive, true, "兵器跳");

        // 空手路径
        var uB = makeUnit(12);
        var mB = makeMan();
        JumpDeriveAction.tryDerive(uB, mB, passive, true, "空手跳");

        // 两路除 targetState 外副作用必须等价
        assertEquals("两路 跳横移速度 一致", uW.跳横移速度, uB.跳横移速度);
        assertEquals("两路 跳跃中移动速度 一致", uW.跳跃中移动速度, uB.跳跃中移动速度);
        assertEquals("两路 状态改变 调用次数一致",
            uW.__spy_state_count, uB.__spy_state_count);
        assertTrue("两路 man 都被 remove",
            mW.__removed && mB.__removed);
        // 只 targetState 该不同
        assertFalse("targetState 两路不同（policy 区分点）",
            uW.__spy_state_last === uB.__spy_state_last);
    }
}
