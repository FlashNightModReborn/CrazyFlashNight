import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * StateTransitionCore Test Suite
 *
 * 纯值输入/输出，不依赖 _root、MovieClip 或帧时间推进。
 * 覆盖 6 个决策函数的真值表分支。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.StateTransitionCoreTest {

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
        trace("StateTransitionCore Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testShouldStoreFlyState();
        testShouldEarlyReturnOnFlyingRun();
        testResolveAttackMode();
        testResolvePrevGotoLabel();
        testResolveGotoLabel();
        testShouldTransition();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    private static function testShouldStoreFlyState():Void {
        trace("\n--- testShouldStoreFlyState ---");
        // 控制目标 + 空手攻击/站立 命中
        assertTrue("控制目标 + 空手攻击 → 命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "空手攻击", "空手"));
        assertTrue("控制目标 + 空手站立 → 命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "空手站立", "空手"));
        // 兵器模式同理
        assertTrue("控制目标 + 兵器攻击 → 命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "兵器攻击", "兵器"));
        assertTrue("控制目标 + 兵器站立 → 命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "兵器站立", "兵器"));
        // 非控制目标
        assertFalse("非控制目标 → 不命中",
            StateTransitionCore.shouldStoreFlyState("enemy", "hero", "空手攻击", "空手"));
        // 同 unit 但状态不是 X攻击/X站立
        assertFalse("受伤 → 不命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "受伤", "空手"));
        assertFalse("血腥死 → 不命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "血腥死", "空手"));
        assertFalse("技能 → 不命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "技能", "空手"));
        // 攻击模式与状态前缀不匹配
        assertFalse("空手模式下兵器攻击 → 不命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "兵器攻击", "空手"));
        assertFalse("兵器模式下空手站立 → 不命中",
            StateTransitionCore.shouldStoreFlyState("hero", "hero", "空手站立", "兵器"));
    }

    private static function testShouldEarlyReturnOnFlyingRun():Void {
        trace("\n--- testShouldEarlyReturnOnFlyingRun ---");
        assertTrue("飞行中切空手跑 → 早退",
            StateTransitionCore.shouldEarlyReturnOnFlyingRun(true, "空手跑"));
        assertTrue("飞行中切兵器跑 → 早退",
            StateTransitionCore.shouldEarlyReturnOnFlyingRun(true, "兵器跑"));
        assertTrue("飞行中切跑 → 早退（含子串）",
            StateTransitionCore.shouldEarlyReturnOnFlyingRun(true, "跑"));
        assertFalse("飞行中切空手攻击 → 不早退",
            StateTransitionCore.shouldEarlyReturnOnFlyingRun(true, "空手攻击"));
        assertFalse("飞行中切空手站立 → 不早退",
            StateTransitionCore.shouldEarlyReturnOnFlyingRun(true, "空手站立"));
        assertFalse("非飞行 + 空手跑 → 不早退",
            StateTransitionCore.shouldEarlyReturnOnFlyingRun(false, "空手跑"));
        assertFalse("undefined 飞行标记 → 不早退",
            StateTransitionCore.shouldEarlyReturnOnFlyingRun(undefined, "空手跑"));
    }

    private static function testResolveAttackMode():Void {
        trace("\n--- testResolveAttackMode ---");
        assertEquals("已有 空手 保留", "空手", StateTransitionCore.resolveAttackMode("空手"));
        assertEquals("已有 兵器 保留", "兵器", StateTransitionCore.resolveAttackMode("兵器"));
        assertEquals("undefined → 兜底空手", "空手", StateTransitionCore.resolveAttackMode(undefined));
        assertEquals("null → 兜底空手", "空手", StateTransitionCore.resolveAttackMode(null));
        assertEquals("空字符串 → 兜底空手", "空手", StateTransitionCore.resolveAttackMode(""));
    }

    private static function testResolvePrevGotoLabel():Void {
        trace("\n--- testResolvePrevGotoLabel ---");
        assertEquals("有 __stateGotoLabel → 用其值", "容器",
            StateTransitionCore.resolvePrevGotoLabel("容器", "技能"));
        assertEquals("无 __stateGotoLabel → 退回 oldState", "受伤",
            StateTransitionCore.resolvePrevGotoLabel(undefined, "受伤"));
        // 注：空字符串 != undefined，应当原样返回
        assertEquals("空字符串视为有值", "",
            StateTransitionCore.resolvePrevGotoLabel("", "受伤"));
    }

    private static function testResolveGotoLabel():Void {
        trace("\n--- testResolveGotoLabel ---");
        // 非主角男：直传
        assertEquals("非主角男 + 技能 → 直传", "技能",
            StateTransitionCore.resolveGotoLabel("技能", false, null));
        assertEquals("非主角男 + 战技 → 直传", "战技",
            StateTransitionCore.resolveGotoLabel("战技", false, null));
        assertEquals("非主角男 + 受伤 → 直传", "受伤",
            StateTransitionCore.resolveGotoLabel("受伤", false, null));
        // 主角男 + 容器化别名 → 容器
        assertEquals("主角男 + 技能 → 容器", "容器",
            StateTransitionCore.resolveGotoLabel("技能", true, null));
        assertEquals("主角男 + 战技 → 容器", "容器",
            StateTransitionCore.resolveGotoLabel("战技", true, null));
        assertEquals("主角男 + 兵器攻击容器 → 容器", "容器",
            StateTransitionCore.resolveGotoLabel("兵器攻击容器", true, null));
        // 主角男 + 非容器化状态 → 直传
        assertEquals("主角男 + 受伤 → 直传", "受伤",
            StateTransitionCore.resolveGotoLabel("受伤", true, null));
        assertEquals("主角男 + 空手攻击 → 直传", "空手攻击",
            StateTransitionCore.resolveGotoLabel("空手攻击", true, null));
        assertEquals("主角男 + 兵器攻击 → 直传", "兵器攻击",
            StateTransitionCore.resolveGotoLabel("兵器攻击", true, null));
        // 主角男 + job override
        assertEquals("主角男 + 技能 + override容器 → 容器", "容器",
            StateTransitionCore.resolveGotoLabel("技能", true, "容器"));
        assertEquals("主角男 + 受伤 + override自定义 → 自定义",
            "自定义帧", StateTransitionCore.resolveGotoLabel("受伤", true, "自定义帧"));
        // override 优先级压过容器别名
        assertEquals("主角男 + 战技 + override覆盖容器别名 → override 胜",
            "特殊", StateTransitionCore.resolveGotoLabel("战技", true, "特殊"));
    }

    private static function testShouldTransition():Void {
        trace("\n--- testShouldTransition ---");
        // 逻辑状态变化
        assertTrue("oldState != newLogical → transition",
            StateTransitionCore.shouldTransition("空手站立", "空手攻击", "空手站立", "空手攻击"));
        // 显示帧变化（容器化场景：logical 不变，goto 变）
        assertTrue("prev != new gotoLabel → transition",
            StateTransitionCore.shouldTransition("技能", "技能", "容器", "受伤"));
        assertTrue("容器化场景：logical不变但gotoLabel跳 → transition",
            StateTransitionCore.shouldTransition("空手攻击", "空手攻击", "空手站立", "容器"));
        // 完全相同
        assertFalse("完全一致 → 不 transition",
            StateTransitionCore.shouldTransition("空手站立", "空手站立", "空手站立", "空手站立"));
        assertFalse("容器化稳态：logical+goto 都一致 → 不 transition",
            StateTransitionCore.shouldTransition("技能", "技能", "容器", "容器"));
    }
}
