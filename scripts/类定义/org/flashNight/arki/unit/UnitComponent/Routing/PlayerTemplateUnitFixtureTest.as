import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * PlayerTemplateUnitFixtureTest — 玩家模板路由夹具测试套件（第三阶段）
 *
 * ════════════════════════════════════════════════════════════════════
 * 两层结构 —— 防"复刻测试过度信心"（[[feedback-reproduction-test-overconfidence]]）
 * ════════════════════════════════════════════════════════════════════
 *   decision 层：直接调 runAnimationDone(unit)，验证 998 决策树分支表。
 *       **只证明复刻符合决策 spec，不证明 _root.主角函数.动画完毕 真这么跑**
 *       —— 复刻 ↔ 真函数 的保真度由"对 998 源码的人工 review"把关（review-gated）。
 *   integration 层：bindAnimationDoneReproduction 后用**真实**
 *       RoutingLifecycle.completeAnimation 驱动，验证 routing→玩家模板 的
 *       orchestration 接缝（completeAnimation 是真 production class，有真牙齿）。
 *
 * 覆盖：
 *   [decision]    夹具自检 3 + 动画完毕(998) 9 分支 + 启动跳跃浮空(883) 9（3 起跳分支+副作用）
 *   [integration] 真实 completeAnimation 链路 3（doubleJump / 普通落地 / 置位时序）
 *   [lifecycle]   启动跳跃浮空 onUnload 3（经真实 MockMovieClip.removeMovieClip 触发）
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
    // integration 层：RoutingRuntime air/scheduler spy
    // （completeAnimation → clearSkillFloatTask / startNaturalLandingTask 会触达）
    // ════════════════════════════════════════════════════════════════════

    private static function makeRuntimeSpy() {
        var spy = {
            closeSkillFloatCount: 0,
            closeNaturalLandingCount: 0,
            closeJumpFloatCount: 0,
            enableSkillFloatCount: 0,
            enableNaturalLandingCount: 0,
            removeTaskCount: 0
        };
        spy.air = {
            __spy: spy,
            关闭技能浮空: function(unit) { this.__spy.closeSkillFloatCount++; },
            关闭自然落地: function(unit) { this.__spy.closeNaturalLandingCount++; },
            关闭跳跃浮空: function(unit) { this.__spy.closeJumpFloatCount++; },
            启用技能浮空: function(unit, floatFlag, man) { this.__spy.enableSkillFloatCount++; },
            启用自然落地: function(unit) { this.__spy.enableNaturalLandingCount++; }
        };
        spy.scheduler = {
            __spy: spy,
            removeTask: function(taskID) { this.__spy.removeTaskCount++; }
        };
        return spy;
    }

    private static function installRuntimeSpy(spy):Void {
        RoutingRuntime.setAirControllerForTest(spy.air);
        RoutingRuntime.setSchedulerForTest(spy.scheduler);
    }

    private static function clearRuntimeSpy():Void {
        RoutingRuntime.clearAirControllerForTest();
        RoutingRuntime.clearSchedulerForTest();
    }

    // ════════════════════════════════════════════════════════════════════
    // 启动跳跃浮空 边界 stub（recorder-only，不假装实现行为）
    // ════════════════════════════════════════════════════════════════════

    private static function makeJumpScheduler() {
        var s = { removeTaskCount: 0, removedIds: [] };
        s.removeTask = function(id) {
            this.removeTaskCount++;
            this.removedIds.push(id);
        };
        return s;
    }

    private static function makeJumpAir() {
        var a = {
            closeNaturalLandingCount: 0,
            enableJumpFloatCount: 0,
            closeJumpFloatCount: 0,
            lastEnableUnit: undefined,
            lastEnableMan: undefined
        };
        a.关闭自然落地 = function(unit) { this.closeNaturalLandingCount++; };
        a.启用跳跃浮空 = function(unit, man) {
            this.enableJumpFloatCount++;
            this.lastEnableUnit = unit;
            this.lastEnableMan = man;
        };
        a.关闭跳跃浮空 = function(unit) { this.closeJumpFloatCount++; };
        return a;
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

        // ── decision 层：夹具自检 ──
        testFixture_Defaults();
        testFixture_StateChangeSpy_Records();
        testFixture_AabbSpy_Records();

        // ── decision 层：动画完毕(998) 决策树 ──
        testAnimDone_B1_HpZero_BloodyDeath();
        testAnimDone_B2_JumpToRun();
        testAnimDone_B2_SpeedMismatch_FallsToStand();
        testAnimDone_B3_FlyingGun_DoubleJump();
        testAnimDone_B3_FlyingGun_NoDoubleJump();
        testAnimDone_B4_BareHandJump();
        testAnimDone_B4_WeaponJump_DoubleJumpPrep();
        testAnimDone_B5_FloatingGun_NonFlying();
        testAnimDone_B6_NormalLanding();

        // ── integration 层：真实 RoutingLifecycle.completeAnimation 链路 ──
        testIntegration_CompleteAnimation_DoubleJumpInAir_RoutesWeaponJump();
        testIntegration_CompleteAnimation_NoDoubleJump_RoutesNormalLanding();
        testIntegration_CompleteAnimation_PreserveFlagSetBeforeAnimDone();

        // ── decision 层：启动跳跃浮空(883) 起跳分支 + 副作用 ──
        testJumpFloat_J1_SkillFloat_DoubleJump();
        testJumpFloat_J2_InAir_ViaFloatFlag();
        testJumpFloat_J2_InAir_ViaYBelowZ();
        testJumpFloat_J2_InAir_ViaTempY();
        testJumpFloat_J3_NormalTakeoff();
        testJumpFloat_UnconditionalEffects();
        testJumpFloat_StaleTaskCleanup();
        testJumpFloat_AirControllerCalls();
        testJumpFloat_AirControllerUndefined_NoCrash();

        // ── lifecycle 层：启动跳跃浮空 onUnload（经真实 MockMovieClip.removeMovieClip）──
        testJumpFloat_OnUnload_CleansUnitFloatState();
        testJumpFloat_OnUnload_ChainsPrevOnUnload();
        testJumpFloat_OnUnload_CleansJumpFloatTask();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ════════════════════════════════════════════════════════════════════
    // [decision] 夹具自检
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
    // [decision] 动画完毕(998) 决策树 —— 仅验证决策 spec，不证明 production 匹配
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

    // ════════════════════════════════════════════════════════════════════
    // [integration] 真实 RoutingLifecycle.completeAnimation 链路
    // 验证 production orchestration（completeAnimation 真实 class）→ 动画完毕 接缝
    // ════════════════════════════════════════════════════════════════════

    private static function testIntegration_CompleteAnimation_DoubleJumpInAir_RoutesWeaponJump():Void {
        trace("\n--- testIntegration_CompleteAnimation_DoubleJumpInAir_RoutesWeaponJump ---");
        var u = PlayerTemplateUnitFixture.makeUnit("int1");
        u.攻击模式 = "兵器";
        u.飞行浮空 = false;
        u._y = 200;
        u.Z轴坐标 = 300;          // _y < Z-0.5 → 在空中
        u.起跳速度 = -13;
        u.垂直速度 = 0;
        u.起始Y = 0;
        u.技能浮空 = false;
        u.__preserveFloatFlagOnUnload = undefined;
        PlayerTemplateUnitFixture.bindAnimationDoneReproduction(u);

        var man = new MockMovieClip();
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            // 真实 production class：completeAnimation 设 技能浮空/__preserve → 调 动画完毕() → remove man
            RoutingLifecycle.completeAnimation(man, u, true);
            assertEquals("completeAnimation→动画完毕 路由到 兵器跳", "兵器跳", lastState(u));
            assertEquals("兵器跳 doubleJump 补垂直速度",            -13,      u.垂直速度);
            assertEquals("兵器跳 doubleJump 补起始Y=Z",             300,      u.起始Y);
            assertTrue  ("completeAnimation 后 man 已 remove",       man.__removed);
            assertEquals("doubleJump+在空中 → 不启用自然落地",       0,        spy.enableNaturalLandingCount);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testIntegration_CompleteAnimation_NoDoubleJump_RoutesNormalLanding():Void {
        trace("\n--- testIntegration_CompleteAnimation_NoDoubleJump_RoutesNormalLanding ---");
        var u = PlayerTemplateUnitFixture.makeUnit("int2");
        u.攻击模式 = "空手";
        u._y = 200;
        u.Z轴坐标 = 300;          // 在空中
        u.技能浮空 = false;
        u.__preserveFloatFlagOnUnload = undefined;
        PlayerTemplateUnitFixture.bindAnimationDoneReproduction(u);

        var man = new MockMovieClip();
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            // enableDoubleJump=false → shouldPreserveDoubleJump(false,inAir)=false → 不设 技能浮空
            RoutingLifecycle.completeAnimation(man, u, false);
            assertFalse ("无 doubleJump → 技能浮空 保持 false",  u.技能浮空);
            assertEquals("技能浮空 false → 动画完毕 落到 B6 站立", "空手站立", lastState(u));
            assertEquals("B6 触发 aabb 更新",                    1,        u.__spy_aabbUpdateCount);
            assertTrue  ("completeAnimation 后 man 已 remove",    man.__removed);
            assertEquals("无 doubleJump+在空中 → 启用自然落地",   1,        spy.enableNaturalLandingCount);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testIntegration_CompleteAnimation_PreserveFlagSetBeforeAnimDone():Void {
        // 时序证明：真实 completeAnimation 必须在调 动画完毕() 之前写好 __preserve / 技能浮空。
        // 自定义 动画完毕 在被调瞬间快照这两个字段 —— 若 completeAnimation 顺序错了，快照会落空。
        trace("\n--- testIntegration_CompleteAnimation_PreserveFlagSetBeforeAnimDone ---");
        var u = PlayerTemplateUnitFixture.makeUnit("int3");
        u.攻击模式 = "空手";
        u._y = 200;
        u.Z轴坐标 = 300;          // 在空中
        u.技能浮空 = false;
        u.__preserveFloatFlagOnUnload = undefined;
        u.__spy_preserveAtAnimDone = "UNSET";
        u.__spy_floatAtAnimDone = "UNSET";
        u.动画完毕 = function() {
            this.__spy_preserveAtAnimDone = this.__preserveFloatFlagOnUnload;
            this.__spy_floatAtAnimDone = this.技能浮空;
            PlayerTemplateUnitFixture.runAnimationDone(this);
        };

        var man = new MockMovieClip();
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            RoutingLifecycle.completeAnimation(man, u, true);
            assertEquals("动画完毕被调时 __preserve 已置位", "技能浮空", u.__spy_preserveAtAnimDone);
            assertTrue  ("动画完毕被调时 技能浮空 已置位",    u.__spy_floatAtAnimDone);
        } finally {
            clearRuntimeSpy();
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // [decision] 启动跳跃浮空(883) 起跳分支 + 副作用
    // ════════════════════════════════════════════════════════════════════

    private static function testJumpFloat_J1_SkillFloat_DoubleJump():Void {
        trace("\n--- testJumpFloat_J1_SkillFloat_DoubleJump ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf1");
        u.技能浮空 = true;
        u.__preserveFloatFlagOnUnload = "技能浮空";
        u.起跳速度 = -14;
        u.Z轴坐标 = 250;
        u.垂直速度 = 0;
        u.起始Y = 0;
        var man = new MockMovieClip();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), makeJumpAir());
        assertFalse ("J1 技能浮空 清 false",         u.技能浮空);
        assertEquals("J1 __preserve 已 delete",      undefined, u.__preserveFloatFlagOnUnload);
        assertEquals("J1 二段跳补垂直速度=起跳速度",  -14,       u.垂直速度);
        assertEquals("J1 起始Y=Z轴坐标",             250,       u.起始Y);
        assertEquals("J1 不 gotoAndPlay",            undefined, man.__lastLabel);
    }

    private static function testJumpFloat_J2_InAir_ViaFloatFlag():Void {
        trace("\n--- testJumpFloat_J2_InAir_ViaFloatFlag ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf2");
        u.浮空 = true;          // 原本在空中 via 浮空 flag
        u.技能浮空 = false;
        u.temp_y = 0;
        u.Z轴坐标 = 200;
        u.垂直速度 = 7;
        var man = new MockMovieClip();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), makeJumpAir());
        assertEquals("J2 空中进入 → gotoAndPlay 跳跃状态", "跳跃状态", man.__lastLabel);
        assertEquals("J2 用 gotoAndPlay（play）",          "play",    man.__lastLabelOp);
        assertEquals("J2 起始Y=Z轴坐标",                   200,       u.起始Y);
        assertEquals("J2 不动垂直速度",                    7,         u.垂直速度);
    }

    private static function testJumpFloat_J2_InAir_ViaYBelowZ():Void {
        trace("\n--- testJumpFloat_J2_InAir_ViaYBelowZ ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf3");
        u.浮空 = false;
        u.技能浮空 = false;
        u.temp_y = 0;
        u._y = 100;
        u.Z轴坐标 = 300;        // 100 < 299.5 → 判定在空中
        var man = new MockMovieClip();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), makeJumpAir());
        assertEquals("J2 _y<Z-0.5 判定在空中 → gotoAndPlay", "跳跃状态", man.__lastLabel);
    }

    private static function testJumpFloat_J2_InAir_ViaTempY():Void {
        trace("\n--- testJumpFloat_J2_InAir_ViaTempY ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf4");
        u.浮空 = false;
        u.技能浮空 = false;
        u._y = 100;
        u.Z轴坐标 = 100;        // 不在空中
        u.temp_y = 50;          // 但 temp_y>0 → 仍走 J2
        var man = new MockMovieClip();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), makeJumpAir());
        assertEquals("J2 temp_y>0 → gotoAndPlay", "跳跃状态", man.__lastLabel);
    }

    private static function testJumpFloat_J3_NormalTakeoff():Void {
        // J3 可达本身即证明 原本在空中 在 浮空=true 之前判定（否则非二段跳恒走 J2）
        trace("\n--- testJumpFloat_J3_NormalTakeoff ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf5");
        u.浮空 = false;
        u.技能浮空 = false;
        u._y = 100;
        u.Z轴坐标 = 100;        // 不在空中
        u.temp_y = 0;
        u.起跳速度 = -15;
        u.垂直速度 = 0;
        var man = new MockMovieClip();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), makeJumpAir());
        assertEquals("J3 正常起跳补垂直速度=起跳速度", -15,       u.垂直速度);
        assertEquals("J3 起始Y=Z轴坐标",               100,       u.起始Y);
        assertEquals("J3 不 gotoAndPlay",              undefined, man.__lastLabel);
    }

    private static function testJumpFloat_UnconditionalEffects():Void {
        trace("\n--- testJumpFloat_UnconditionalEffects ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf6");   // 默认走 J3
        var man = new MockMovieClip();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), makeJumpAir());
        assertEquals("浮空 置 true",       true,  u.浮空);
        assertEquals("temp_y 清 0",        0,     u.temp_y);
        assertEquals("man.跳跃移动倍率=1",  1,     man.跳跃移动倍率);
        assertEquals("man.落地=false",      false, man.落地);
        assertEquals("man.坠地中=false",    false, man.坠地中);
    }

    private static function testJumpFloat_StaleTaskCleanup():Void {
        trace("\n--- testJumpFloat_StaleTaskCleanup ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf7");
        u.__跳跃浮空任务ID = 999;
        u.__技能浮空任务ID = 888;
        var man = new MockMovieClip();
        var sch = makeJumpScheduler();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, sch, makeJumpAir());
        assertEquals("__跳跃浮空任务ID 清 null",       null, u.__跳跃浮空任务ID);
        assertEquals("__技能浮空任务ID 清 null",       null, u.__技能浮空任务ID);
        assertEquals("scheduler.removeTask 调用 2 次", 2,    sch.removeTaskCount);
    }

    private static function testJumpFloat_AirControllerCalls():Void {
        trace("\n--- testJumpFloat_AirControllerCalls ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf8");
        var man = new MockMovieClip();
        var air = makeJumpAir();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), air);
        assertEquals("关闭自然落地 1 次",       1,   air.closeNaturalLandingCount);
        assertEquals("启用跳跃浮空 1 次",       1,   air.enableJumpFloatCount);
        assertEquals("启用跳跃浮空 透传 unit",  u,   air.lastEnableUnit);
        assertEquals("启用跳跃浮空 透传 man",   man, air.lastEnableMan);
    }

    private static function testJumpFloat_AirControllerUndefined_NoCrash():Void {
        trace("\n--- testJumpFloat_AirControllerUndefined_NoCrash ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf9");
        var man = new MockMovieClip();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), undefined);
        assertTrue  ("airController=undefined 不崩", true);
        assertEquals("浮空 仍置 true",                true, u.浮空);
    }

    // ════════════════════════════════════════════════════════════════════
    // [lifecycle] 启动跳跃浮空 onUnload —— 经真实 MockMovieClip.removeMovieClip 触发
    // ════════════════════════════════════════════════════════════════════

    private static function testJumpFloat_OnUnload_CleansUnitFloatState():Void {
        trace("\n--- testJumpFloat_OnUnload_CleansUnitFloatState ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf10");
        var man = new MockMovieClip();
        var air = makeJumpAir();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), air);
        // runJumpFloat 后 浮空=true；手动置 刚体/坠地中 以隔离验证 onUnload 的清理
        u.刚体 = true;
        man.坠地中 = true;
        man.removeMovieClip();   // 真实 MockMovieClip.removeMovieClip 触发 onUnload
        assertEquals("onUnload: unit.浮空 → false",  false, u.浮空);
        assertEquals("onUnload: unit.刚体 → false",  false, u.刚体);
        assertEquals("onUnload: man.坠地中 → false", false, man.坠地中);
        assertEquals("onUnload: 关闭跳跃浮空 1 次",   1,     air.closeJumpFloatCount);
    }

    private static function testJumpFloat_OnUnload_ChainsPrevOnUnload():Void {
        trace("\n--- testJumpFloat_OnUnload_ChainsPrevOnUnload ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf11");
        var man = new MockMovieClip();
        var prevFired = { count: 0 };
        man.onUnload = function() { prevFired.count++; };
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), makeJumpAir());
        man.removeMovieClip();
        assertEquals("prevOnUnload 被 chain 调用 1 次",      1,     prevFired.count);
        assertEquals("新 onUnload 逻辑也执行（浮空→false）", false, u.浮空);
    }

    private static function testJumpFloat_OnUnload_CleansJumpFloatTask():Void {
        trace("\n--- testJumpFloat_OnUnload_CleansJumpFloatTask ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf12");
        var man = new MockMovieClip();
        var sch = makeJumpScheduler();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, sch, makeJumpAir());
        // 模拟 float 期间又挂了新跳跃浮空任务
        u.__跳跃浮空任务ID = 555;
        var beforeCount:Number = sch.removeTaskCount;
        man.removeMovieClip();
        assertEquals("onUnload 清 __跳跃浮空任务ID → null", null,            u.__跳跃浮空任务ID);
        assertEquals("onUnload removeTask 调用 +1",         beforeCount + 1, sch.removeTaskCount);
    }
}
