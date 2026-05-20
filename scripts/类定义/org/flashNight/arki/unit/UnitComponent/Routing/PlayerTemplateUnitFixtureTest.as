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
 *   [decision]    夹具自检 3 + 动画完毕 9 + 启动跳跃浮空 9 + 飞行状态读写 14 + 攻击模式切换 12
 *   [integration] completeAnimation 链路 3（doubleJump / 普通落地 / 置位时序）
 *                 + completeAnimation↔bindEndCleanup 浮空标记握手 2（命中 / 清错）
 *                 + 攻击模式切换↔飞行状态 round-trip 1（真 runStoreFlyState 实写槽位）
 *   [lifecycle]   启动跳跃浮空 onUnload 5（经真实 MockMovieClip.removeMovieClip 触发；含 air live-read）
 *   [contract]    ContainerFrameScriptContract _parent.* 序列 2 + 末帧 route handoff 3
 *                 （真 RoutingLifecycle.completeAnimation 驱动容器末帧→路由 接缝）
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

    // airProvider 工厂：把固定 air stub 包成 ():air 函数（多数 jumpfloat 测试用）
    private static function airProviderOf(air) {
        return function() { return air; };
    }

    // ════════════════════════════════════════════════════════════════════
    // 飞行状态读写 stub —— _root 桩 + 飞行字段播种
    // ════════════════════════════════════════════════════════════════════

    // _root 桩：代 _root.控制目标 + _root.fly_* 飞行状态寄存器（全部初值 undefined）
    private static function makeRootStub() {
        return {
            控制目标: undefined,
            玩家信息界面: undefined,
            fly_isFly1: undefined, fly_isFly2: undefined,
            fly_flySpeed1: undefined, fly_leftFlySpeed1: undefined, fly_rightFlySpeed1: undefined,
            fly_upFlySpeed1: undefined, fly_downFlySpeed1: undefined,
            fly_y1: undefined, fly_起始Y1: undefined, fly_Z轴坐标1: undefined,
            fly_flySpeed2: undefined, fly_leftFlySpeed2: undefined, fly_rightFlySpeed2: undefined,
            fly_upFlySpeed2: undefined, fly_downFlySpeed2: undefined,
            fly_y2: undefined, fly_起始Y2: undefined, fly_Z轴坐标2: undefined
        };
    }

    // 给 unit 的 8 个飞行源字段播种递增值（base..base+7），便于断言 slot 快照对应
    private static function seedFlySource(u, base:Number):Void {
        u.flySpeed      = base;
        u.leftFlySpeed  = base + 1;
        u.rightFlySpeed = base + 2;
        u.upFlySpeed    = base + 3;
        u.downFlySpeed  = base + 4;
        u._y            = base + 5;
        u.起始Y         = base + 6;
        u.Z轴坐标       = base + 7;
    }

    // ════════════════════════════════════════════════════════════════════
    // 攻击模式切换 / 容器帧脚本契约 stub
    // ════════════════════════════════════════════════════════════════════

    private static function makeDpsSpy() {
        return { count: 0, lastUnit: undefined };
    }

    // dpsInvalidator 形参：复刻 PlayerInfoProvider.invalidateDpsCache 的注入点
    private static function dpsInvalidatorOf(spy) {
        return function(u) { spy.count++; spy.lastUnit = u; };
    }

    private static function makePlayerInfoUI() {
        var ui = { refreshCount: 0, lastMode: undefined };
        ui.刷新攻击模式 = function(mode) {
            this.refreshCount++;
            this.lastMode = mode;
        };
        return ui;
    }

    // 容器帧脚本契约 spy：装 UpdateSmallState / UpdateBigSmallState / 动画完毕 recorder
    private static function installComboSpies(u):Void {
        u.__spy_comboCalls = [];
        u.UpdateSmallState = function(s) {
            this.__spy_comboCalls.push("USS:" + s);
        };
        u.UpdateBigSmallState = function(b, s) {
            this.__spy_comboCalls.push("UBSS:" + b + "/" + s);
        };
        u.动画完毕 = function() {
            this.__spy_comboCalls.push("动画完毕");
        };
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

        // ── integration 层：completeAnimation↔bindEndCleanup 浮空标记握手 ──
        testEndCleanup_CompleteAnimationPreserve_MatchedFlagSurvives();
        testEndCleanup_CompleteAnimationPreserve_MismatchedFlagClearsWrong();

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
        testJumpFloat_OnUnload_AirReplacedBeforeUnload_ReadsCurrentAir();
        testJumpFloat_OnUnload_AirNulledBeforeUnload_SkipsGracefully();

        // ── decision 层：飞行状态读写(1442/1476) 存储 / 读取 / round-trip ──
        testStoreFly_Slot1_OnWeaponSwitch();
        testStoreFly_Slot2_OnStateChange();
        testStoreFly_DefaultType_IsStateChange();
        testStoreFly_GateFail_NotControlTarget();
        testStoreFly_GateFail_NotFlying();
        testStoreFly_GateFail_FlyTypeNot1();
        testStoreFly_Slot1_BlockedWhenIsFly1AlreadyTrue();
        testLoadFly_Slot1_OnWeaponSwitch();
        testLoadFly_Slot2_OnStateChange();
        testLoadFly_GateFail_NotControlTarget();
        testLoadFly_Slot2_BlockedWhenIsFly1True();
        testLoadFly_Slot1_NoopWhenIsFly1NotTrue();
        testFlyState_RoundTrip_Slot1();
        testFlyState_RoundTrip_Slot2();

        // ── decision 层：攻击模式切换(1104) ──
        testAttackMode_BareHand();
        testAttackMode_Rifle_Owned();
        testAttackMode_Rifle_NotOwned();
        testAttackMode_Blade_Owned();
        testAttackMode_Grenade_OwnedOffline();
        testAttackMode_Grenade_OnlineBlocked();
        testAttackMode_Pistol_DualWield();
        testAttackMode_Pistol_SingleP1();
        testAttackMode_Pistol_SingleP2();
        testAttackMode_Pistol_NoneOwned();
        testAttackMode_StoresFlyState_WhenFlyingControlled();
        testAttackMode_TailEffects_DpsAndRefresh();

        // ── integration 层：攻击模式切换 ↔ 飞行状态 round-trip ──
        testAttackMode_FlyStateRoundTrip_WeaponSwitchSlot1();

        // ── contract 层：容器帧脚本契约回放 ──
        testContainerContract_WeaponCombo_ShapeIsStable();
        testContainerContract_WeaponCombo_DrivesPlayerTemplateInOrder();
        testContainerContract_RouteHandoff_ShapeIsStable();
        testContainerContract_RouteHandoff_DrivesCompleteAnimation_InAir();
        testContainerContract_RouteHandoff_ClearsResidualSkillFloatTask();

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
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(makeJumpAir()));
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
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(makeJumpAir()));
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
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(makeJumpAir()));
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
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(makeJumpAir()));
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
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(makeJumpAir()));
        assertEquals("J3 正常起跳补垂直速度=起跳速度", -15,       u.垂直速度);
        assertEquals("J3 起始Y=Z轴坐标",               100,       u.起始Y);
        assertEquals("J3 不 gotoAndPlay",              undefined, man.__lastLabel);
    }

    private static function testJumpFloat_UnconditionalEffects():Void {
        trace("\n--- testJumpFloat_UnconditionalEffects ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf6");   // 默认走 J3
        var man = new MockMovieClip();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(makeJumpAir()));
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
        PlayerTemplateUnitFixture.runJumpFloat(u, man, sch, airProviderOf(makeJumpAir()));
        assertEquals("__跳跃浮空任务ID 清 null",       null, u.__跳跃浮空任务ID);
        assertEquals("__技能浮空任务ID 清 null",       null, u.__技能浮空任务ID);
        assertEquals("scheduler.removeTask 调用 2 次", 2,    sch.removeTaskCount);
    }

    private static function testJumpFloat_AirControllerCalls():Void {
        trace("\n--- testJumpFloat_AirControllerCalls ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf8");
        var man = new MockMovieClip();
        var air = makeJumpAir();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(air));
        assertEquals("关闭自然落地 1 次",       1,   air.closeNaturalLandingCount);
        assertEquals("启用跳跃浮空 1 次",       1,   air.enableJumpFloatCount);
        assertEquals("启用跳跃浮空 透传 unit",  u,   air.lastEnableUnit);
        assertEquals("启用跳跃浮空 透传 man",   man, air.lastEnableMan);
    }

    private static function testJumpFloat_AirControllerUndefined_NoCrash():Void {
        trace("\n--- testJumpFloat_AirControllerUndefined_NoCrash ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf9");
        var man = new MockMovieClip();
        // airProvider 直接传 undefined（无 provider）→ body/onUnload 均安全跳过
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), undefined);
        assertTrue  ("airProvider=undefined 不崩", true);
        assertEquals("浮空 仍置 true",              true, u.浮空);
    }

    // ════════════════════════════════════════════════════════════════════
    // [lifecycle] 启动跳跃浮空 onUnload —— 经真实 MockMovieClip.removeMovieClip 触发
    // ════════════════════════════════════════════════════════════════════

    private static function testJumpFloat_OnUnload_CleansUnitFloatState():Void {
        trace("\n--- testJumpFloat_OnUnload_CleansUnitFloatState ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf10");
        var man = new MockMovieClip();
        var air = makeJumpAir();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(air));
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
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), airProviderOf(makeJumpAir()));
        man.removeMovieClip();
        assertEquals("prevOnUnload 被 chain 调用 1 次",      1,     prevFired.count);
        assertEquals("新 onUnload 逻辑也执行（浮空→false）", false, u.浮空);
    }

    private static function testJumpFloat_OnUnload_CleansJumpFloatTask():Void {
        trace("\n--- testJumpFloat_OnUnload_CleansJumpFloatTask ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf12");
        var man = new MockMovieClip();
        var sch = makeJumpScheduler();
        PlayerTemplateUnitFixture.runJumpFloat(u, man, sch, airProviderOf(makeJumpAir()));
        // 模拟 float 期间又挂了新跳跃浮空任务
        u.__跳跃浮空任务ID = 555;
        var beforeCount:Number = sch.removeTaskCount;
        man.removeMovieClip();
        assertEquals("onUnload 清 __跳跃浮空任务ID → null", null,            u.__跳跃浮空任务ID);
        assertEquals("onUnload removeTask 调用 +1",         beforeCount + 1, sch.removeTaskCount);
    }

    private static function testJumpFloat_OnUnload_AirReplacedBeforeUnload_ReadsCurrentAir():Void {
        // 不可靠边界：启动时 air=airAtStart，卸载前被替换为 airAtUnload。
        // onUnload 必须 live-read airProvider —— 关闭跳跃浮空 应落到 *当前* air。
        trace("\n--- testJumpFloat_OnUnload_AirReplacedBeforeUnload_ReadsCurrentAir ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf13");
        var man = new MockMovieClip();
        var airAtStart = makeJumpAir();
        var airAtUnload = makeJumpAir();
        var airSlot = { current: airAtStart };
        var provider = function() { return airSlot.current; };
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), provider);
        assertEquals("启动期 air=airAtStart 收到 启用跳跃浮空", 1, airAtStart.enableJumpFloatCount);
        // 卸载前 air 被替换（模拟空中控制器重建 / 不可靠）
        airSlot.current = airAtUnload;
        man.removeMovieClip();
        assertEquals("onUnload live-read → airAtUnload 收到 关闭跳跃浮空", 1, airAtUnload.closeJumpFloatCount);
        assertEquals("onUnload 不读旧 air → airAtStart 未收到 关闭跳跃浮空", 0, airAtStart.closeJumpFloatCount);
    }

    private static function testJumpFloat_OnUnload_AirNulledBeforeUnload_SkipsGracefully():Void {
        // 不可靠边界：air 在卸载前被置空 —— onUnload live-read 得到 undefined，安全跳过。
        trace("\n--- testJumpFloat_OnUnload_AirNulledBeforeUnload_SkipsGracefully ---");
        var u = PlayerTemplateUnitFixture.makeUnit("jf14");
        var man = new MockMovieClip();
        var air = makeJumpAir();
        var airSlot = { current: air };
        var provider = function() { return airSlot.current; };
        PlayerTemplateUnitFixture.runJumpFloat(u, man, makeJumpScheduler(), provider);
        airSlot.current = undefined;   // 卸载前 air 置空
        man.removeMovieClip();
        assertTrue  ("air 卸载前置空 → onUnload 不崩",          true);
        assertEquals("air 置空 → 关闭跳跃浮空 不被调",          0,     air.closeJumpFloatCount);
        assertEquals("onUnload 其余清理仍执行（浮空→false）",   false, u.浮空);
    }

    // ════════════════════════════════════════════════════════════════════
    // [decision] 飞行状态读写(1442/1476) —— 存储 存储当前飞行状态
    // ════════════════════════════════════════════════════════════════════

    private static function testStoreFly_Slot1_OnWeaponSwitch():Void {
        trace("\n--- testStoreFly_Slot1_OnWeaponSwitch ---");
        var u = PlayerTemplateUnitFixture.makeUnit("sf1");
        u.飞行浮空 = true;
        u.flyType = 1;
        seedFlySource(u, 100);
        var root = makeRootStub();
        root.控制目标 = u._name;          // unit 是控制目标
        PlayerTemplateUnitFixture.runStoreFlyState(u, "切换武器", root);
        assertEquals("S1 fly_isFly1 = true",  true,  root.fly_isFly1);
        assertEquals("S1 fly_isFly2 = false", false, root.fly_isFly2);
        assertEquals("S1 slot1.flySpeed",     100,   root.fly_flySpeed1);
        assertEquals("S1 slot1.downFlySpeed", 104,   root.fly_downFlySpeed1);
        assertEquals("S1 slot1.fly_y1",       105,   root.fly_y1);
        assertEquals("S1 slot1.起始Y1",       106,   root.fly_起始Y1);
        assertEquals("S1 slot1.Z轴坐标1",     107,   root.fly_Z轴坐标1);
    }

    private static function testStoreFly_Slot2_OnStateChange():Void {
        trace("\n--- testStoreFly_Slot2_OnStateChange ---");
        var u = PlayerTemplateUnitFixture.makeUnit("sf2");
        u.飞行浮空 = true;
        u.flyType = 1;
        seedFlySource(u, 200);
        var root = makeRootStub();
        root.控制目标 = u._name;
        PlayerTemplateUnitFixture.runStoreFlyState(u, "状态改变", root);
        assertEquals("S2 fly_isFly2 = true",  true,      root.fly_isFly2);
        assertEquals("S2 slot2.flySpeed",     200,       root.fly_flySpeed2);
        assertEquals("S2 slot2.fly_y2",       205,       root.fly_y2);
        assertEquals("S2 slot2.Z轴坐标2",     207,       root.fly_Z轴坐标2);
        assertEquals("S2 不触 slot1 标志",    undefined, root.fly_isFly1);
    }

    private static function testStoreFly_DefaultType_IsStateChange():Void {
        trace("\n--- testStoreFly_DefaultType_IsStateChange ---");
        var u = PlayerTemplateUnitFixture.makeUnit("sf3");
        u.飞行浮空 = true;
        u.flyType = 1;
        seedFlySource(u, 300);
        var root = makeRootStub();
        root.控制目标 = u._name;
        PlayerTemplateUnitFixture.runStoreFlyState(u, undefined, root);   // type 空 → 兜底 状态改变
        assertEquals("默认 type → 走 slot2",      true, root.fly_isFly2);
        assertEquals("默认 type slot2.flySpeed",  300,  root.fly_flySpeed2);
    }

    private static function testStoreFly_GateFail_NotControlTarget():Void {
        trace("\n--- testStoreFly_GateFail_NotControlTarget ---");
        var u = PlayerTemplateUnitFixture.makeUnit("sf4");
        u.飞行浮空 = true;
        u.flyType = 1;
        seedFlySource(u, 400);
        var root = makeRootStub();
        root.控制目标 = "someoneElse";          // unit 非控制目标
        PlayerTemplateUnitFixture.runStoreFlyState(u, "状态改变", root);
        assertEquals("非控制目标 → 不写 slot 标志",    undefined, root.fly_isFly2);
        assertEquals("非控制目标 → slot2.flySpeed 不写", undefined, root.fly_flySpeed2);
    }

    private static function testStoreFly_GateFail_NotFlying():Void {
        trace("\n--- testStoreFly_GateFail_NotFlying ---");
        var u = PlayerTemplateUnitFixture.makeUnit("sf5");
        u.飞行浮空 = false;          // 不在飞行
        u.flyType = 1;
        var root = makeRootStub();
        root.控制目标 = u._name;
        PlayerTemplateUnitFixture.runStoreFlyState(u, "状态改变", root);
        assertEquals("非飞行浮空 → 不写 slot", undefined, root.fly_isFly2);
    }

    private static function testStoreFly_GateFail_FlyTypeNot1():Void {
        trace("\n--- testStoreFly_GateFail_FlyTypeNot1 ---");
        var u = PlayerTemplateUnitFixture.makeUnit("sf6");
        u.飞行浮空 = true;
        u.flyType = 2;               // flyType≠1
        var root = makeRootStub();
        root.控制目标 = u._name;
        PlayerTemplateUnitFixture.runStoreFlyState(u, "状态改变", root);
        assertEquals("flyType≠1 → 不写 slot", undefined, root.fly_isFly2);
    }

    private static function testStoreFly_Slot1_BlockedWhenIsFly1AlreadyTrue():Void {
        // fly_isFly1 已 true → S1 条件 fly_isFly1!=true 不满足 → 不覆盖 slot1
        trace("\n--- testStoreFly_Slot1_BlockedWhenIsFly1AlreadyTrue ---");
        var u = PlayerTemplateUnitFixture.makeUnit("sf7");
        u.飞行浮空 = true;
        u.flyType = 1;
        seedFlySource(u, 700);
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.fly_isFly1 = true;          // slot1 已占用
        root.fly_flySpeed1 = 999;        // 旧值
        PlayerTemplateUnitFixture.runStoreFlyState(u, "切换武器", root);
        assertEquals("fly_isFly1 已 true → S1 不覆盖 slot1", 999, root.fly_flySpeed1);
    }

    // ════════════════════════════════════════════════════════════════════
    // [decision] 飞行状态读写(1442/1476) —— 读取 读取当前飞行状态
    // ════════════════════════════════════════════════════════════════════

    private static function testLoadFly_Slot1_OnWeaponSwitch():Void {
        trace("\n--- testLoadFly_Slot1_OnWeaponSwitch ---");
        var u = PlayerTemplateUnitFixture.makeUnit("lf1");
        u.飞行浮空 = false;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.fly_isFly1 = true;
        root.fly_flySpeed1 = 100; root.fly_leftFlySpeed1 = 101; root.fly_rightFlySpeed1 = 102;
        root.fly_upFlySpeed1 = 103; root.fly_downFlySpeed1 = 104;
        root.fly_y1 = 105; root.fly_起始Y1 = 106; root.fly_Z轴坐标1 = 107;
        PlayerTemplateUnitFixture.runLoadFlyState(u, "切换武器", root);
        assertEquals("L1 fly_isFly1 → false",     false, root.fly_isFly1);
        assertEquals("L1 unit.flySpeed = slot1",  100,   u.flySpeed);
        assertEquals("L1 unit.downFlySpeed",      104,   u.downFlySpeed);
        assertEquals("L1 unit._y = slot1.y",      105,   u._y);
        assertEquals("L1 unit.Z轴坐标 = slot1",   107,   u.Z轴坐标);
        assertEquals("L1 飞行浮空 → true",        true,  u.飞行浮空);
    }

    private static function testLoadFly_Slot2_OnStateChange():Void {
        trace("\n--- testLoadFly_Slot2_OnStateChange ---");
        var u = PlayerTemplateUnitFixture.makeUnit("lf2");
        u.飞行浮空 = false;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.fly_isFly2 = true;          // fly_isFly1 保持 undefined（≠true）
        root.fly_flySpeed2 = 200; root.fly_leftFlySpeed2 = 201; root.fly_rightFlySpeed2 = 202;
        root.fly_upFlySpeed2 = 203; root.fly_downFlySpeed2 = 204;
        root.fly_y2 = 205; root.fly_起始Y2 = 206; root.fly_Z轴坐标2 = 207;
        PlayerTemplateUnitFixture.runLoadFlyState(u, "状态改变", root);
        assertEquals("L2 fly_isFly2 → false",     false, root.fly_isFly2);
        assertEquals("L2 unit.flySpeed = slot2",  200,   u.flySpeed);
        assertEquals("L2 unit._y = slot2.y",      205,   u._y);
        assertEquals("L2 unit.Z轴坐标 = slot2",   207,   u.Z轴坐标);
        assertEquals("L2 飞行浮空 → true",        true,  u.飞行浮空);
    }

    private static function testLoadFly_GateFail_NotControlTarget():Void {
        trace("\n--- testLoadFly_GateFail_NotControlTarget ---");
        var u = PlayerTemplateUnitFixture.makeUnit("lf3");
        u.flySpeed = 0;
        u.飞行浮空 = false;
        var root = makeRootStub();
        root.控制目标 = "someoneElse";
        root.fly_isFly1 = true;
        root.fly_flySpeed1 = 100;
        PlayerTemplateUnitFixture.runLoadFlyState(u, "切换武器", root);
        assertEquals("非控制目标 → unit.flySpeed 不变", 0,     u.flySpeed);
        assertEquals("非控制目标 → 飞行浮空 不变",      false, u.飞行浮空);
    }

    private static function testLoadFly_Slot2_BlockedWhenIsFly1True():Void {
        // L2 条件含 fly_isFly1!=true：slot1 占用时阻断 slot2 读取
        trace("\n--- testLoadFly_Slot2_BlockedWhenIsFly1True ---");
        var u = PlayerTemplateUnitFixture.makeUnit("lf4");
        u.flySpeed = 0;
        u.飞行浮空 = false;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.fly_isFly2 = true;
        root.fly_flySpeed2 = 200;
        root.fly_isFly1 = true;          // isFly1 真 → 阻断 slot2 读取
        PlayerTemplateUnitFixture.runLoadFlyState(u, "状态改变", root);
        assertEquals("fly_isFly1 真 → slot2 读取被阻断, flySpeed 不变", 0,    u.flySpeed);
        assertEquals("slot2 未消费 → fly_isFly2 仍 true",               true, root.fly_isFly2);
    }

    private static function testLoadFly_Slot1_NoopWhenIsFly1NotTrue():Void {
        trace("\n--- testLoadFly_Slot1_NoopWhenIsFly1NotTrue ---");
        var u = PlayerTemplateUnitFixture.makeUnit("lf5");
        u.flySpeed = 0;
        var root = makeRootStub();
        root.控制目标 = u._name;
        // fly_isFly1 保持 undefined（≠true）
        root.fly_flySpeed1 = 100;
        PlayerTemplateUnitFixture.runLoadFlyState(u, "切换武器", root);
        assertEquals("切换武器 但 fly_isFly1≠true → no-op", 0, u.flySpeed);
    }

    // ════════════════════════════════════════════════════════════════════
    // [decision] 飞行状态读写 round-trip —— 存储→读取 经同一 root 桩往返
    // ════════════════════════════════════════════════════════════════════

    private static function testFlyState_RoundTrip_Slot1():Void {
        trace("\n--- testFlyState_RoundTrip_Slot1 ---");
        var u = PlayerTemplateUnitFixture.makeUnit("rt1");
        u.飞行浮空 = true;
        u.flyType = 1;
        seedFlySource(u, 500);
        var root = makeRootStub();
        root.控制目标 = u._name;
        PlayerTemplateUnitFixture.runStoreFlyState(u, "切换武器", root);   // 存 slot1
        seedFlySource(u, 0);                                              // 模拟切换期间字段被改
        u.飞行浮空 = false;
        PlayerTemplateUnitFixture.runLoadFlyState(u, "切换武器", root);    // 读 slot1 还原
        assertEquals("RT1 flySpeed 还原",      500,  u.flySpeed);
        assertEquals("RT1 leftFlySpeed 还原",  501,  u.leftFlySpeed);
        assertEquals("RT1 rightFlySpeed 还原", 502,  u.rightFlySpeed);
        assertEquals("RT1 upFlySpeed 还原",    503,  u.upFlySpeed);
        assertEquals("RT1 downFlySpeed 还原",  504,  u.downFlySpeed);
        assertEquals("RT1 _y 还原",            505,  u._y);
        assertEquals("RT1 起始Y 还原",         506,  u.起始Y);
        assertEquals("RT1 Z轴坐标 还原",       507,  u.Z轴坐标);
        assertEquals("RT1 飞行浮空 → true",    true, u.飞行浮空);
    }

    private static function testFlyState_RoundTrip_Slot2():Void {
        trace("\n--- testFlyState_RoundTrip_Slot2 ---");
        var u = PlayerTemplateUnitFixture.makeUnit("rt2");
        u.飞行浮空 = true;
        u.flyType = 1;
        seedFlySource(u, 600);
        var root = makeRootStub();
        root.控制目标 = u._name;
        PlayerTemplateUnitFixture.runStoreFlyState(u, "状态改变", root);   // 存 slot2
        seedFlySource(u, 0);
        u.飞行浮空 = false;
        PlayerTemplateUnitFixture.runLoadFlyState(u, "状态改变", root);    // 读 slot2 还原
        assertEquals("RT2 flySpeed 还原",     600,  u.flySpeed);
        assertEquals("RT2 downFlySpeed 还原", 604,  u.downFlySpeed);
        assertEquals("RT2 _y 还原",           605,  u._y);
        assertEquals("RT2 起始Y 还原",        606,  u.起始Y);
        assertEquals("RT2 Z轴坐标 还原",      607,  u.Z轴坐标);
        assertEquals("RT2 飞行浮空 → true",   true, u.飞行浮空);
    }

    // ════════════════════════════════════════════════════════════════════
    // [decision] 攻击模式切换(1104) —— 武器持有门控 + 双枪合并
    // ════════════════════════════════════════════════════════════════════

    private static function testAttackMode_BareHand():Void {
        trace("\n--- testAttackMode_BareHand ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am1");
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "空手", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("空手 → 攻击模式=空手",        "空手",         u.攻击模式);
        assertEquals("状态改变 1 次",               1,              u.__spy_stateChangeCount);
        assertEquals("状态改变 → 攻击模式切换",     "攻击模式切换", lastState(u));
        assertEquals("mode!=手枪 → 根据模式(空手)", "空手",         u.__spy_bonusModeReads[0]);
    }

    private static function testAttackMode_Rifle_Owned():Void {
        trace("\n--- testAttackMode_Rifle_Owned ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am2");
        u.长枪 = true;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "长枪", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("长枪持有 → 攻击模式=长枪", "长枪", u.攻击模式);
        assertEquals("状态改变 1 次",            1,      u.__spy_stateChangeCount);
    }

    private static function testAttackMode_Rifle_NotOwned():Void {
        trace("\n--- testAttackMode_Rifle_NotOwned ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am3");
        u.长枪 = false;
        u.攻击模式 = "空手";
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "长枪", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("长枪未持有 → 攻击模式 不变",  "空手", u.攻击模式);
        assertEquals("长枪未持有 → 状态改变 0 次",  0,      u.__spy_stateChangeCount);
    }

    private static function testAttackMode_Blade_Owned():Void {
        trace("\n--- testAttackMode_Blade_Owned ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am4");
        u.刀 = true;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "兵器", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("刀持有 → 攻击模式=兵器", "兵器", u.攻击模式);
        assertEquals("状态改变 1 次",          1,      u.__spy_stateChangeCount);
    }

    private static function testAttackMode_Grenade_OwnedOffline():Void {
        trace("\n--- testAttackMode_Grenade_OwnedOffline ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am5");
        u.手雷 = true;
        u.是否允许发送联机数据 = false;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "手雷", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("手雷持有+非联机 → 攻击模式=手雷", "手雷", u.攻击模式);
        assertEquals("状态改变 1 次",                   1,      u.__spy_stateChangeCount);
    }

    private static function testAttackMode_Grenade_OnlineBlocked():Void {
        trace("\n--- testAttackMode_Grenade_OnlineBlocked ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am6");
        u.手雷 = true;
        u.是否允许发送联机数据 = true;          // 联机数据 → 阻断
        u.攻击模式 = "空手";
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "手雷", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("手雷+联机数据 → 攻击模式 不变",  "空手", u.攻击模式);
        assertEquals("手雷+联机数据 → 状态改变 0 次",  0,      u.__spy_stateChangeCount);
    }

    private static function testAttackMode_Pistol_DualWield():Void {
        trace("\n--- testAttackMode_Pistol_DualWield ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am7");
        u.手枪 = true;
        u.手枪2 = true;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "手枪", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("双持 → 攻击模式=双枪",   "双枪", u.攻击模式);
        assertEquals("根据模式 调 2 次",        2,      u.__spy_bonusModeReads.length);
        assertEquals("根据模式[0]=手枪2",       "手枪2", u.__spy_bonusModeReads[0]);
        assertEquals("根据模式[1]=手枪",        "手枪",  u.__spy_bonusModeReads[1]);
        assertEquals("状态改变 1 次",           1,      u.__spy_stateChangeCount);
    }

    private static function testAttackMode_Pistol_SingleP1():Void {
        trace("\n--- testAttackMode_Pistol_SingleP1 ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am8");
        u.手枪 = true;
        u.手枪2 = false;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "手枪", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("仅手枪 → 攻击模式=手枪", "手枪", u.攻击模式);
        assertEquals("根据模式 1 次",          1,      u.__spy_bonusModeReads.length);
        assertEquals("根据模式[0]=手枪",       "手枪", u.__spy_bonusModeReads[0]);
    }

    private static function testAttackMode_Pistol_SingleP2():Void {
        trace("\n--- testAttackMode_Pistol_SingleP2 ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am9");
        u.手枪 = false;
        u.手枪2 = true;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "手枪", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("仅手枪2 → 攻击模式=手枪2", "手枪2", u.攻击模式);
        assertEquals("根据模式[0]=手枪2",        "手枪2", u.__spy_bonusModeReads[0]);
    }

    private static function testAttackMode_Pistol_NoneOwned():Void {
        trace("\n--- testAttackMode_Pistol_NoneOwned ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am10");
        u.手枪 = false;
        u.手枪2 = false;
        u.攻击模式 = "空手";
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "手枪", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("无手枪 → 攻击模式 不变",                 "空手", u.攻击模式);
        assertEquals("无手枪 → 状态改变 0 次",                 0,      u.__spy_stateChangeCount);
        assertEquals("mode==手枪 跳过早装配 → 根据模式 0 次",  0,      u.__spy_bonusModeReads.length);
    }

    private static function testAttackMode_StoresFlyState_WhenFlyingControlled():Void {
        trace("\n--- testAttackMode_StoresFlyState_WhenFlyingControlled ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am11");
        u.飞行浮空 = true;
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "空手", root, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("飞行+控制目标 → 存储飞行状态 1 次", 1,        u.__spy_flyStoreCalls.length);
        assertEquals("存储类型 = 切换武器",              "切换武器", u.__spy_flyStoreCalls[0]);
        // 非飞行变体：不存储
        var u2 = PlayerTemplateUnitFixture.makeUnit("am11b");
        u2.飞行浮空 = false;
        var root2 = makeRootStub();
        root2.控制目标 = u2._name;
        root2.玩家信息界面 = makePlayerInfoUI();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u2, "空手", root2, dpsInvalidatorOf(makeDpsSpy()));
        assertEquals("非飞行 → 不存储飞行状态", 0, u2.__spy_flyStoreCalls.length);
    }

    private static function testAttackMode_TailEffects_DpsAndRefresh():Void {
        trace("\n--- testAttackMode_TailEffects_DpsAndRefresh ---");
        var u = PlayerTemplateUnitFixture.makeUnit("am12");
        var root = makeRootStub();
        root.控制目标 = u._name;
        var ui = makePlayerInfoUI();
        root.玩家信息界面 = ui;
        var dps = makeDpsSpy();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "空手", root, dpsInvalidatorOf(dps));
        assertEquals("dpsInvalidator 恒调用",       1,      dps.count);
        assertEquals("控制目标 → 刷新攻击模式 调用", 1,      ui.refreshCount);
        assertEquals("刷新攻击模式 收到当前 攻击模式", "空手", ui.lastMode);
        // 非控制目标变体
        var u2 = PlayerTemplateUnitFixture.makeUnit("am12b");
        var root2 = makeRootStub();
        root2.控制目标 = "other";
        var ui2 = makePlayerInfoUI();
        root2.玩家信息界面 = ui2;
        var dps2 = makeDpsSpy();
        PlayerTemplateUnitFixture.runAttackModeSwitch(u2, "空手", root2, dpsInvalidatorOf(dps2));
        assertEquals("非控制目标 dpsInvalidator 仍调用", 1, dps2.count);
        assertEquals("非控制目标 → 刷新攻击模式 不调用", 0, ui2.refreshCount);
    }

    // ════════════════════════════════════════════════════════════════════
    // [contract] 容器帧脚本契约 —— ContainerFrameScriptContract 回放
    // ════════════════════════════════════════════════════════════════════

    private static function testContainerContract_WeaponCombo_ShapeIsStable():Void {
        trace("\n--- testContainerContract_WeaponCombo_ShapeIsStable ---");
        var c:Array = ContainerFrameScriptContract.weaponComboFullSequence();
        assertEquals("契约 10 步", 10, c.length);
        var animDone:Number = 0;
        var uss:Number = 0;
        for (var i:Number = 0; i < c.length; i++) {
            if (c[i].call === "动画完毕") animDone++;
            if (c[i].call === "UpdateSmallState") uss++;
        }
        assertEquals("动画完毕 出现 4 次",            4,                     animDone);
        assertEquals("UpdateSmallState 出现 5 次",    5,                     uss);
        assertEquals("末步 call = UpdateBigSmallState", "UpdateBigSmallState", c[9].call);
        assertEquals("末步 big arg = 普攻结束",        "普攻结束",            c[9].args[0]);
        assertEquals("末步 small arg = 兵器五段结束",  "兵器五段结束",        c[9].args[1]);
    }

    private static function testContainerContract_WeaponCombo_DrivesPlayerTemplateInOrder():Void {
        trace("\n--- testContainerContract_WeaponCombo_DrivesPlayerTemplateInOrder ---");
        var u = PlayerTemplateUnitFixture.makeUnit("cc1");
        installComboSpies(u);
        ContainerFrameScriptContract.replay(u, ContainerFrameScriptContract.weaponComboFullSequence());
        assertEquals("契约 10 步全回放",   10,                           u.__spy_comboCalls.length);
        assertEquals("step1 一段中",       "USS:兵器一段中",             u.__spy_comboCalls[0]);
        assertEquals("step2 动画完毕",      "动画完毕",                   u.__spy_comboCalls[1]);
        assertEquals("step9 五段中",       "USS:兵器五段中",             u.__spy_comboCalls[8]);
        assertEquals("step10 末帧 UBSS",   "UBSS:普攻结束/兵器五段结束", u.__spy_comboCalls[9]);
    }

    // ════════════════════════════════════════════════════════════════════
    // [contract] 容器末帧 route handoff —— _root.兵器攻击路由.动画完毕(this,_parent)
    // 委派 = RoutingLifecycle.completeAnimation；replayRouteHandoff 驱动真 class
    // ════════════════════════════════════════════════════════════════════

    private static function testContainerContract_RouteHandoff_ShapeIsStable():Void {
        trace("\n--- testContainerContract_RouteHandoff_ShapeIsStable ---");
        var h:Object = ContainerFrameScriptContract.weaponComboRouteHandoff();
        assertEquals("route handoff 触发帧 = 72",            72,             h.frameIndex);
        assertEquals("route handoff routeObject = 兵器攻击路由", "兵器攻击路由", h.routeObject);
        assertEquals("route handoff call = 动画完毕",         "动画完毕",      h.call);
        assertEquals("route handoff 实参 2 项 (this/_parent)", 2,             h.argShape.length);
        assertEquals("route handoff 委派 completeAnimation",
                     "RoutingLifecycle.completeAnimation", h.delegate);
        assertEquals("普攻 route handoff enableDoubleJump=false", false,      h.delegateEnableDoubleJump);
    }

    private static function testContainerContract_RouteHandoff_DrivesCompleteAnimation_InAir():Void {
        // 容器末帧 → 路由：跳跃落地瞬间触发普攻（在空中完成）→ 真 completeAnimation
        //   走自然落地兜底，而非裸 removeMovieClip 留下不一致 _y。
        trace("\n--- testContainerContract_RouteHandoff_DrivesCompleteAnimation_InAir ---");
        var u = PlayerTemplateUnitFixture.makeUnit("rh1");
        u.攻击模式 = "空手";
        u._y = 200;
        u.Z轴坐标 = 300;          // _y < Z-0.5 → 在空中
        u.技能浮空 = false;
        PlayerTemplateUnitFixture.bindAnimationDoneReproduction(u);

        var man = new MockMovieClip();
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            ContainerFrameScriptContract.replayRouteHandoff(man, u);
            assertEquals("末帧 route handoff → 动画完毕 路由到 空手站立", "空手站立", lastState(u));
            assertTrue  ("route handoff 后 man 已 remove",                man.__removed);
            assertEquals("在空中完成普攻 → 启用自然落地 1 次",            1, spy.enableNaturalLandingCount);
            assertEquals("route handoff → clearSkillFloatTask 关技能浮空", 1, spy.closeSkillFloatCount);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testContainerContract_RouteHandoff_ClearsResidualSkillFloatTask():Void {
        // 跨容器残留浮空标记：容器末帧 route handoff 时 unit 仍挂着上个容器的技能浮空任务，
        //   completeAnimation→clearSkillFloatTask 应把它清掉，避免孤儿任务卡住浮空。
        trace("\n--- testContainerContract_RouteHandoff_ClearsResidualSkillFloatTask ---");
        var u = PlayerTemplateUnitFixture.makeUnit("rh2");
        u.攻击模式 = "空手";
        u._y = 100;
        u.Z轴坐标 = 100;          // 落地
        u.__技能浮空任务ID = 777;  // 跨容器残留的技能浮空任务
        PlayerTemplateUnitFixture.bindAnimationDoneReproduction(u);

        var man = new MockMovieClip();
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            ContainerFrameScriptContract.replayRouteHandoff(man, u);
            assertEquals("残留 __技能浮空任务ID 被清 null",       null, u.__技能浮空任务ID);
            assertEquals("clearSkillFloatTask removeTask 1 次",   1,    spy.removeTaskCount);
            assertEquals("落地完成普攻 → 不启用自然落地",          0,    spy.enableNaturalLandingCount);
        } finally {
            clearRuntimeSpy();
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // [integration] 攻击模式切换 ↔ 飞行状态 round-trip
    // 把 存储当前飞行状态 spy 换成真 runStoreFlyState 委派，验"实写 root.fly_*"
    // ════════════════════════════════════════════════════════════════════

    private static function testAttackMode_FlyStateRoundTrip_WeaponSwitchSlot1():Void {
        // 集成夹具：攻击模式切换 → 真 runStoreFlyState(slot1) 实写 root.fly_* →
        //   扰动飞行字段 → runLoadFlyState(slot1) 还原。验"实际写入 root.fly_*"，
        //   而非仅 spy 调用计数（玩家卡死集中在浮空转换 → 槽位读写须有真往返断言）。
        trace("\n--- testAttackMode_FlyStateRoundTrip_WeaponSwitchSlot1 ---");
        var u = PlayerTemplateUnitFixture.makeUnit("amrt1");
        u.飞行浮空 = true;
        u.flyType = 1;
        seedFlySource(u, 800);          // 飞行字段 = 800..807
        var root = makeRootStub();
        root.控制目标 = u._name;
        root.玩家信息界面 = makePlayerInfoUI();
        // 关键：把 makeUnit 的 存储当前飞行状态 recorder-spy 换成真 runStoreFlyState 委派，
        //       让 攻击模式切换 真正写 root.fly_*（spy 版本只记调用、不写槽位）。
        u.存储当前飞行状态 = function(type) {
            PlayerTemplateUnitFixture.runStoreFlyState(this, type, root);
        };

        PlayerTemplateUnitFixture.runAttackModeSwitch(u, "空手", root, dpsInvalidatorOf(makeDpsSpy()));
        // 攻击模式切换 前置：飞行浮空+控制目标 → 存储当前飞行状态("切换武器") → 写 slot1
        assertEquals("攻击模式切换 → slot1 fly_isFly1 实写", true, root.fly_isFly1);
        assertEquals("slot1 实写 flySpeed 快照",            800,  root.fly_flySpeed1);
        assertEquals("slot1 实写 _y 快照",                  805,  root.fly_y1);
        assertEquals("slot1 实写 Z轴坐标 快照",             807,  root.fly_Z轴坐标1);

        // 切换武器期间飞行字段被扰动
        seedFlySource(u, 0);
        u.飞行浮空 = false;
        // 读回 slot1 还原
        PlayerTemplateUnitFixture.runLoadFlyState(u, "切换武器", root);
        assertEquals("round-trip flySpeed 还原",     800,  u.flySpeed);
        assertEquals("round-trip downFlySpeed 还原", 804,  u.downFlySpeed);
        assertEquals("round-trip _y 还原",           805,  u._y);
        assertEquals("round-trip Z轴坐标 还原",      807,  u.Z轴坐标);
        assertEquals("round-trip 飞行浮空 → true",   true, u.飞行浮空);
        assertEquals("round-trip 后 slot1 标志释放", false, root.fly_isFly1);
    }

    // ════════════════════════════════════════════════════════════════════
    // [integration] completeAnimation ↔ bindEndCleanup 浮空标记握手
    // completeAnimation 写 __preserveFloatFlagOnUnload，真 bindEndCleanup onUnload 读。
    // 注：bindEndCleanup onUnload 的隔离行为另由 RoutingLifecycleTest 覆盖；本层验的是
    //     "写方(completeAnimation) ↔ 读方(bindEndCleanup) 字面量端到端配对"。
    //     兵器容器末帧走 RoutingIntent.bindContainerEndState（不碰 preserve flag），
    //     bindEndCleanup 是技能/战技路由的结束清理 —— 故本握手属技能路由侧。
    // ════════════════════════════════════════════════════════════════════

    private static function testEndCleanup_CompleteAnimationPreserve_MatchedFlagSurvives():Void {
        // 命中：completeAnimation 写 __preserveFloatFlagOnUnload="技能浮空"，真 bindEndCleanup
        //   onUnload 以 floatFlag="技能浮空" 读 → 命中 → delete 标记、技能浮空 存活
        //   （二段跳浮空带到下个状态）。动画完毕 设 no-op 以隔离握手本身。
        trace("\n--- testEndCleanup_CompleteAnimationPreserve_MatchedFlagSurvives ---");
        var u = PlayerTemplateUnitFixture.makeUnit("ec1");
        u.状态 = "技能";              // != excludeState("战技") → needReset=true
        u.攻击模式 = "空手";
        u._y = 200;
        u.Z轴坐标 = 300;             // 在空中 → completeAnimation 置 preserve
        u.技能浮空 = false;
        u.__preserveFloatFlagOnUnload = undefined;
        u.动画完毕 = function() {};   // no-op：隔离 completeAnimation→bindEndCleanup 握手
        u.UpdateBigSmallState = function(b, s) {
            this.__spy_endBig = b;
            this.__spy_endSmall = s;
        };

        var man = new MockMovieClip();
        RoutingLifecycle.bindEndCleanup(man, u, "战技", "技能结束", "技能浮空");
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            // completeAnimation(enableDoubleJump=true)+在空中 → 写 preserve="技能浮空" →
            //   man.removeMovieClip() → 触发 bindEndCleanup onUnload 读 preserve
            RoutingLifecycle.completeAnimation(man, u, true);
            assertTrue  ("completeAnimation 后 man 已 remove",         man.__removed);
            assertEquals("onUnload 命中 preserve → delete 标记",       undefined, u.__preserveFloatFlagOnUnload);
            assertTrue  ("preserve 命中 → 技能浮空 存活（带到下个状态）", u.技能浮空);
            assertEquals("onUnload 仍写结束状态 big = 技能结束",       "技能结束", u.__spy_endBig);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testEndCleanup_CompleteAnimationPreserve_MismatchedFlagClearsWrong():Void {
        // 清错：completeAnimation 写 preserve="技能浮空"，但 bindEndCleanup 以
        //   floatFlag="飞行浮空" 绑定 → onUnload 字面量不匹配 → unit["飞行浮空"]=false
        //   （清错了标记）+ preserve 残留未 delete。记录"写/读两侧 flag 名不一致"的危害。
        trace("\n--- testEndCleanup_CompleteAnimationPreserve_MismatchedFlagClearsWrong ---");
        var u = PlayerTemplateUnitFixture.makeUnit("ec2");
        u.状态 = "技能";
        u.攻击模式 = "空手";
        u._y = 200;
        u.Z轴坐标 = 300;             // 在空中
        u.技能浮空 = false;
        u.飞行浮空 = true;           // 将被 onUnload 的 else 分支清掉
        u.__preserveFloatFlagOnUnload = undefined;
        u.动画完毕 = function() {};
        u.UpdateBigSmallState = function(b, s) {};

        var man = new MockMovieClip();
        // floatFlag="飞行浮空" 与 completeAnimation 硬编码写的 "技能浮空" 不一致
        RoutingLifecycle.bindEndCleanup(man, u, "战技", "技能结束", "飞行浮空");
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            RoutingLifecycle.completeAnimation(man, u, true);
            assertFalse ("flag 不匹配 → onUnload 清掉 floatFlag 标记(飞行浮空)", u.飞行浮空);
            assertEquals("flag 不匹配 → preserve 残留未 delete", "技能浮空", u.__preserveFloatFlagOnUnload);
            assertTrue  ("completeAnimation 设的 技能浮空 无人清 → 残留 true",   u.技能浮空);
        } finally {
            clearRuntimeSpy();
        }
    }
}
