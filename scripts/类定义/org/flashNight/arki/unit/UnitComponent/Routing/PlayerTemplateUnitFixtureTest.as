import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * PlayerTemplateUnitFixtureTest — 玩家模板路由夹具测试套件（第三阶段）
 *
 * 覆盖：
 *   - 夹具自检：makeUnit 默认字段 / 状态改变 spy / aabbCollider spy
 *   - 动画完毕(998) 决策树 9 分支（runAnimationDone 复刻）：
 *       B1 死亡 / B2 跳→跑 / B2 速度不匹配兜底 /
 *       B3 飞行持枪(doubleJump|非doubleJump) /
 *       B4 空手跳 / B4 兵器跳 doubleJump 预补 / B5 浮空非飞行兜底 / B6 普通落地
 *
 * 用法：org.flashNight.arki.unit.UnitComponent.Routing.PlayerTemplateUnitFixtureTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Routing.PlayerTemplateUnitFixtureTest {

    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    // ════════════════════════════════════════════════════════════════════
    // 断言工具
    // ════════════════════════════════════════════════════════════════════

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

    // 取最后一次 状态改变 的目标状态名
    private static function lastState(u):String {
        return u.__spy_stateChanges[u.__spy_stateChanges.length - 1];
    }

    // ════════════════════════════════════════════════════════════════════
    // 测试入口
    // ════════════════════════════════════════════════════════════════════

    public static function runAll():Boolean {
        trace("================================================================");
        trace("PlayerTemplateUnitFixture Test Suite (III - 玩家模板路由夹具)");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        // 夹具自检
        testFixture_Defaults();
        testFixture_StateChangeSpy_Records();
        testFixture_AabbSpy_Records();

        // 动画完毕(998) 决策树
        testAnimDone_B1_HpZero_BloodyDeath();
        testAnimDone_B2_JumpToRun();
        testAnimDone_B2_SpeedMismatch_FallsToStand();
        testAnimDone_B3_FlyingGun_DoubleJump();
        testAnimDone_B3_FlyingGun_NoDoubleJump();
        testAnimDone_B4_BareHandJump();
        testAnimDone_B4_WeaponJump_DoubleJumpPrep();
        testAnimDone_B5_FloatingGun_NonFlying();
        testAnimDone_B6_NormalLanding();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ════════════════════════════════════════════════════════════════════
    // 夹具自检
    // ════════════════════════════════════════════════════════════════════

    private static function testFixture_Defaults():Void {
        trace("\n--- testFixture_Defaults ---");
        var u = PlayerTemplateUnitFixture.makeUnit("p1");
        assertEquals("_name = p1",         "p1",     u._name);
        assertEquals("hp 默认 100",         100,      u.hp);
        assertEquals("状态 默认 空手站立",   "空手站立", u.状态);
        assertEquals("攻击模式 默认 空手",   "空手",   u.攻击模式);
        assertEquals("跑X速度 默认 5",       5,        u.跑X速度);
        assertEquals("起跳速度 默认 -10",    -10,      u.起跳速度);
        assertFalse ("技能浮空 默认 false",  u.技能浮空);
        assertFalse ("飞行浮空 默认 false",  u.飞行浮空);
        assertEquals("状态改变 计数初始 0",   0,        u.__spy_stateChangeCount);
        assertEquals("aabb 更新计数初始 0",   0,        u.__spy_aabbUpdateCount);
    }

    private static function testFixture_StateChangeSpy_Records():Void {
        trace("\n--- testFixture_StateChangeSpy_Records ---");
        var u = PlayerTemplateUnitFixture.makeUnit("p2");
        u.状态改变("空手跑");
        u.状态改变("空手站立");
        assertEquals("状态改变 计数 2",      2,        u.__spy_stateChangeCount);
        assertEquals("首次记录 空手跑",       "空手跑", u.__spy_stateChanges[0]);
        assertEquals("末次记录 空手站立",     "空手站立", lastState(u));
    }

    private static function testFixture_AabbSpy_Records():Void {
        trace("\n--- testFixture_AabbSpy_Records ---");
        var u = PlayerTemplateUnitFixture.makeUnit("p3");
        u.aabbCollider.updateFromUnitArea(u);
        assertEquals("aabb 更新计数 1",      1,        u.__spy_aabbUpdateCount);
    }

    // ════════════════════════════════════════════════════════════════════
    // 动画完毕(998) 决策树
    // ════════════════════════════════════════════════════════════════════

    private static function testAnimDone_B1_HpZero_BloodyDeath():Void {
        trace("\n--- testAnimDone_B1_HpZero_BloodyDeath ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b1");
        u.hp = 0;
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("hp<=0 → 状态改变 1 次",  1,        u.__spy_stateChangeCount);
        assertEquals("路由到 血腥死",          "血腥死", lastState(u));
        assertEquals("技能名 已清 null",       null,     u.技能名);
    }

    private static function testAnimDone_B2_JumpToRun():Void {
        trace("\n--- testAnimDone_B2_JumpToRun ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b2");
        u.状态 = "空手跳";
        u.攻击模式 = "空手";
        u.跳横移速度 = 5;
        u.跑X速度 = 5;          // 跳横移速度 === 跑X速度
        u.左行 = true;
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("跳→跑 衔接",            "空手跑", lastState(u));
        assertEquals("状态改变 1 次（早退）",  1,        u.__spy_stateChangeCount);
        assertEquals("aabb 未更新（早退）",    0,        u.__spy_aabbUpdateCount);
    }

    private static function testAnimDone_B2_SpeedMismatch_FallsToStand():Void {
        // 状态为"跳"但 跳横移速度 != 跑X速度 → B2 不命中，技能浮空=false → 落到 B6
        trace("\n--- testAnimDone_B2_SpeedMismatch_FallsToStand ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b2b");
        u.状态 = "空手跳";
        u.攻击模式 = "空手";
        u.跳横移速度 = 3;
        u.跑X速度 = 5;          // 不匹配
        u.左行 = true;
        u.技能浮空 = false;
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("速度不匹配 → 落到 B6 站立", "空手站立", lastState(u));
        assertEquals("aabb 更新 1 次（B6）",       1,         u.__spy_aabbUpdateCount);
    }

    private static function testAnimDone_B3_FlyingGun_DoubleJump():Void {
        trace("\n--- testAnimDone_B3_FlyingGun_DoubleJump ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b3a");
        u.技能浮空 = true;
        u.飞行浮空 = true;
        u.攻击模式 = "长枪";
        u.__preserveFloatFlagOnUnload = "技能浮空";   // wantsDoubleJump = true
        u.起跳速度 = -12;
        u.Z轴坐标 = 200;
        u.垂直速度 = 0;
        u.起始Y = 0;
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("doubleJump 补垂直速度",     -12,      u.垂直速度);
        assertEquals("doubleJump 补起始Y=Z",      200,      u.起始Y);
        assertEquals("__preserve 已 delete",      undefined, u.__preserveFloatFlagOnUnload);
        assertFalse ("技能浮空 已清 false",        u.技能浮空);
        assertEquals("持枪族保持站立继续射击",     "长枪站立", lastState(u));
    }

    private static function testAnimDone_B3_FlyingGun_NoDoubleJump():Void {
        trace("\n--- testAnimDone_B3_FlyingGun_NoDoubleJump ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b3b");
        u.技能浮空 = true;
        u.飞行浮空 = true;
        u.攻击模式 = "手枪";
        u.__preserveFloatFlagOnUnload = undefined;    // wantsDoubleJump = false
        u.垂直速度 = 0;
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("非 doubleJump 不补垂直速度",  0,        u.垂直速度);
        assertFalse ("技能浮空 已清 false",          u.技能浮空);
        assertEquals("持枪族保持站立",               "手枪站立", lastState(u));
    }

    private static function testAnimDone_B4_BareHandJump():Void {
        trace("\n--- testAnimDone_B4_BareHandJump ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b4a");
        u.技能浮空 = true;
        u.攻击模式 = "空手";
        u.飞行浮空 = false;
        u.__preserveFloatFlagOnUnload = undefined;
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("空手 → 空手跳",          "空手跳", lastState(u));
        // B4 不清 技能浮空（留给跳跃状态 load 处理），仅 B3 清
        assertTrue  ("技能浮空 B4 不清",        u.技能浮空);
    }

    private static function testAnimDone_B4_WeaponJump_DoubleJumpPrep():Void {
        trace("\n--- testAnimDone_B4_WeaponJump_DoubleJumpPrep ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b4b");
        u.技能浮空 = true;
        u.攻击模式 = "兵器";
        u.飞行浮空 = false;
        u.__preserveFloatFlagOnUnload = "技能浮空";   // wantsDoubleJump = true
        u.起跳速度 = -11;
        u.Z轴坐标 = 150;
        u.垂直速度 = 0;
        u.起始Y = 0;
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("兵器 doubleJump 预补垂直速度", -11,      u.垂直速度);
        assertEquals("兵器 doubleJump 预补起始Y=Z",  150,      u.起始Y);
        assertEquals("兵器 → 兵器跳",                "兵器跳", lastState(u));
        // B4-prep 不 delete __preserve（仅 B3 delete）
        assertEquals("__preserve B4 路径保留",       "技能浮空", u.__preserveFloatFlagOnUnload);
        assertTrue  ("技能浮空 B4 不清",              u.技能浮空);
    }

    private static function testAnimDone_B5_FloatingGun_NonFlying():Void {
        // 技能浮空 + 非飞行 + 持枪族（攻击模式 不属于 空手/兵器）→ else 分支 → 空手跳
        trace("\n--- testAnimDone_B5_FloatingGun_NonFlying ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b5");
        u.技能浮空 = true;
        u.攻击模式 = "手枪";
        u.飞行浮空 = false;
        u.__preserveFloatFlagOnUnload = undefined;
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("浮空非飞行持枪 → 空手跳兜底", "空手跳", lastState(u));
        assertTrue  ("技能浮空 B5 不清",            u.技能浮空);
    }

    private static function testAnimDone_B6_NormalLanding():Void {
        trace("\n--- testAnimDone_B6_NormalLanding ---");
        var u = PlayerTemplateUnitFixture.makeUnit("b6");
        u.技能浮空 = false;
        u.hp = 100;
        u.状态 = "空手站立";
        u.攻击模式 = "兵器";
        PlayerTemplateUnitFixture.runAnimationDone(u);
        assertEquals("普通落地 → 攻击模式+站立",  "兵器站立", lastState(u));
        assertEquals("B6 触发 aabb 更新 1 次",     1,         u.__spy_aabbUpdateCount);
        assertEquals("状态改变 1 次",              1,         u.__spy_stateChangeCount);
        assertEquals("技能名 已清 null",           null,      u.技能名);
    }
}
