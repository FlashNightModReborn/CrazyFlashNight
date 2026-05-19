import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * StateTransitionPlan Test Suite
 *
 * 两组覆盖：
 *   - snapshot(self) 字段提取：fake unit + _root.控制目标 + job override inline lookup
 *   - build(snapshot, newStateName) 各分支：earlyReturn / storeFlyState /
 *     removeDynamicMan / gotoLabel（直传/别名/jobOverride/非主角男） /
 *     transition（oldState 比较 / prevGotoLabel 比较）
 *
 * 加上 validate() 结构性不变式。
 *
 * StateTransitionTest 端到端断言副作用与时序；本套件锁住 Plan 层值与字段。
 *
 * AS2 strict（见 [[feedback-as2-strict-function-param-dynamic-path]]）：fake unit/man 全 untyped。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.StateTransitionPlanTest {

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

    private static function assertUndefined(name:String, actual):Void {
        testCount++;
        if (actual === undefined) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (act=" + actual + ")");
        }
    }

    // ====================================================================
    // helpers
    // ====================================================================

    private static function makeUnit(name:String) {
        return {
            _name: name,
            兵种: "杂兵",
            状态: undefined,
            攻击模式: "空手",
            __stateGotoLabel: undefined,
            __stateTransitionJob: undefined,
            man: undefined,
            飞行浮空: undefined
        };
    }

    private static function makeDynamicMan() {
        return { __isDynamicMan: true };
    }

    private static function makeStaticMan() {
        return { __isDynamicMan: undefined };
    }

    private static function withControlTarget(target:String, body:Function):Void {
        var saved = _root.控制目标;
        _root.控制目标 = target;
        try {
            body();
        } finally {
            _root.控制目标 = saved;
        }
    }

    private static function fakeSnap(over:Object):Object {
        var s:Object = {
            name:             "e1",
            兵种:             "杂兵",
            攻击模式:         "空手",
            状态:             "空手站立",
            __stateGotoLabel: undefined,
            飞行浮空:         undefined,
            controlTarget:    undefined,
            hasDynamicMan:    false,
            jobGotoOverride:  null
        };
        for (var k in over) {
            s[k] = over[k];
        }
        return s;
    }

    // ====================================================================
    // 测试入口
    // ====================================================================

    public static function runAll():Boolean {
        trace("================================================================");
        trace("StateTransitionPlan Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        // snapshot
        testSnapshot_BasicFields();
        testSnapshot_ControlTarget();
        testSnapshot_JobOverride_Inline();
        testSnapshot_JobOverride_NoJob();
        testSnapshot_JobOverride_NoGotoLabel();
        testSnapshot_HasDynamicMan_True();
        testSnapshot_HasDynamicMan_StaticMan();
        testSnapshot_HasDynamicMan_NoMan();

        // buildPlan
        testBuild_EarlyReturn_FlyingRun();
        testBuild_EarlyReturn_FieldsUndefined();
        testBuild_StoreFlyState_HitOnControlTarget();
        testBuild_StoreFlyState_MissOnNonControl();
        testBuild_AttackMode_Fallback();
        testBuild_AttackMode_Keep();
        testBuild_OldState();
        testBuild_RemoveDynamicMan_True();
        testBuild_RemoveDynamicMan_False();
        testBuild_GotoLabel_NonHero_直传();
        testBuild_GotoLabel_HeroMale_技能Alias();
        testBuild_GotoLabel_HeroMale_战技Alias();
        testBuild_GotoLabel_HeroMale_兵器攻击容器Alias();
        testBuild_GotoLabel_HeroMale_NonContainer直传();
        testBuild_GotoLabel_JobOverride_PressAlias();
        testBuild_GotoLabel_JobOverride_NonHero忽略();
        testBuild_Transition_SameStateSameLabel();
        testBuild_Transition_DiffState();
        testBuild_Transition_OnlyLabelChanged();
        testBuild_NewLogicalState();

        // validate
        testValidate_EarlyReturn();
        testValidate_TransitionMissingGotoLabel();
        testValidate_NormalOk();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ====================================================================
    // snapshot
    // ====================================================================

    private static function testSnapshot_BasicFields():Void {
        trace("\n--- testSnapshot_BasicFields ---");
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";
        u.攻击模式 = "兵器";
        u.__stateGotoLabel = "容器";
        u.飞行浮空 = true;

        var snap:Object = StateTransitionPlan.snapshot(u);

        assertEquals("name", "hero", snap.name);
        assertEquals("兵种", "主角-男", snap.兵种);
        assertEquals("状态", "空手站立", snap.状态);
        assertEquals("攻击模式", "兵器", snap.攻击模式);
        assertEquals("__stateGotoLabel", "容器", snap.__stateGotoLabel);
        assertEquals("飞行浮空", true, snap.飞行浮空);
    }

    private static function testSnapshot_ControlTarget():Void {
        trace("\n--- testSnapshot_ControlTarget ---");
        withControlTarget("hero", function() {
            var u = StateTransitionPlanTest.makeUnit("hero");
            var snap:Object = StateTransitionPlan.snapshot(u);
            StateTransitionPlanTest.assertEquals("controlTarget = hero", "hero", snap.controlTarget);
        });
    }

    private static function testSnapshot_JobOverride_Inline():Void {
        trace("\n--- testSnapshot_JobOverride_Inline ---");
        var u = makeUnit("hero");
        u.__stateTransitionJob = { gotoLabel: "特殊帧", callback: function() {} };

        var snap:Object = StateTransitionPlan.snapshot(u);

        assertEquals("jobGotoOverride = 特殊帧", "特殊帧", snap.jobGotoOverride);
    }

    private static function testSnapshot_JobOverride_NoJob():Void {
        trace("\n--- testSnapshot_JobOverride_NoJob ---");
        var u = makeUnit("hero");
        var snap:Object = StateTransitionPlan.snapshot(u);
        assertEquals("无 job → jobGotoOverride = null", null, snap.jobGotoOverride);
    }

    private static function testSnapshot_JobOverride_NoGotoLabel():Void {
        trace("\n--- testSnapshot_JobOverride_NoGotoLabel ---");
        var u = makeUnit("hero");
        u.__stateTransitionJob = { gotoLabel: undefined, callback: undefined };
        var snap:Object = StateTransitionPlan.snapshot(u);
        assertEquals("job 存在但 gotoLabel=undefined → jobGotoOverride = null",
            null, snap.jobGotoOverride);
    }

    private static function testSnapshot_HasDynamicMan_True():Void {
        trace("\n--- testSnapshot_HasDynamicMan_True ---");
        var u = makeUnit("e1");
        u.man = makeDynamicMan();
        var snap:Object = StateTransitionPlan.snapshot(u);
        assertEquals("hasDynamicMan = true", true, snap.hasDynamicMan);
    }

    private static function testSnapshot_HasDynamicMan_StaticMan():Void {
        trace("\n--- testSnapshot_HasDynamicMan_StaticMan ---");
        var u = makeUnit("e1");
        u.man = makeStaticMan();
        var snap:Object = StateTransitionPlan.snapshot(u);
        assertEquals("static man → hasDynamicMan = false", false, snap.hasDynamicMan);
    }

    private static function testSnapshot_HasDynamicMan_NoMan():Void {
        trace("\n--- testSnapshot_HasDynamicMan_NoMan ---");
        var u = makeUnit("e1");
        var snap:Object = StateTransitionPlan.snapshot(u);
        assertEquals("no man → hasDynamicMan = false", false, snap.hasDynamicMan);
    }

    // ====================================================================
    // buildPlan
    // ====================================================================

    private static function testBuild_EarlyReturn_FlyingRun():Void {
        trace("\n--- testBuild_EarlyReturn_FlyingRun ---");
        var snap:Object = fakeSnap({ 飞行浮空: true, 状态: "空手站立" });
        var plan:Object = StateTransitionPlan.build(snap, "空手跑");
        assertEquals("earlyReturn = true", true, plan.earlyReturn);
    }

    private static function testBuild_EarlyReturn_FieldsUndefined():Void {
        trace("\n--- testBuild_EarlyReturn_FieldsUndefined ---");
        var snap:Object = fakeSnap({ 飞行浮空: true });
        var plan:Object = StateTransitionPlan.build(snap, "空手跑");
        assertUndefined("attackMode undefined", plan.attackMode);
        assertUndefined("oldState undefined", plan.oldState);
        assertUndefined("removeDynamicMan undefined", plan.removeDynamicMan);
        assertUndefined("gotoLabel undefined", plan.gotoLabel);
        assertUndefined("transition undefined", plan.transition);
        assertUndefined("newLogicalState undefined", plan.newLogicalState);
    }

    private static function testBuild_StoreFlyState_HitOnControlTarget():Void {
        trace("\n--- testBuild_StoreFlyState_HitOnControlTarget ---");
        var snap:Object = fakeSnap({
            name: "hero", controlTarget: "hero", 攻击模式: "空手", 状态: "空手站立"
        });
        var plan:Object = StateTransitionPlan.build(snap, "空手攻击");
        assertEquals("storeFlyState true", true, plan.storeFlyState);
    }

    private static function testBuild_StoreFlyState_MissOnNonControl():Void {
        trace("\n--- testBuild_StoreFlyState_MissOnNonControl ---");
        var snap:Object = fakeSnap({
            name: "enemy", controlTarget: "hero", 攻击模式: "空手", 状态: "空手站立"
        });
        var plan:Object = StateTransitionPlan.build(snap, "空手攻击");
        assertEquals("storeFlyState false", false, plan.storeFlyState);
    }

    private static function testBuild_AttackMode_Fallback():Void {
        trace("\n--- testBuild_AttackMode_Fallback ---");
        var snap:Object = fakeSnap({ 攻击模式: undefined });
        var plan:Object = StateTransitionPlan.build(snap, "受伤");
        assertEquals("attackMode 兜底 = 空手", "空手", plan.attackMode);
    }

    private static function testBuild_AttackMode_Keep():Void {
        trace("\n--- testBuild_AttackMode_Keep ---");
        var snap:Object = fakeSnap({ 攻击模式: "兵器" });
        var plan:Object = StateTransitionPlan.build(snap, "受伤");
        assertEquals("attackMode 保留 = 兵器", "兵器", plan.attackMode);
    }

    private static function testBuild_OldState():Void {
        trace("\n--- testBuild_OldState ---");
        var snap:Object = fakeSnap({ 状态: "空手攻击" });
        var plan:Object = StateTransitionPlan.build(snap, "空手站立");
        assertEquals("oldState = 空手攻击", "空手攻击", plan.oldState);
    }

    private static function testBuild_RemoveDynamicMan_True():Void {
        trace("\n--- testBuild_RemoveDynamicMan_True ---");
        var snap:Object = fakeSnap({ hasDynamicMan: true });
        var plan:Object = StateTransitionPlan.build(snap, "受伤");
        assertEquals("removeDynamicMan true", true, plan.removeDynamicMan);
    }

    private static function testBuild_RemoveDynamicMan_False():Void {
        trace("\n--- testBuild_RemoveDynamicMan_False ---");
        var snap:Object = fakeSnap({ hasDynamicMan: false });
        var plan:Object = StateTransitionPlan.build(snap, "受伤");
        assertEquals("removeDynamicMan false", false, plan.removeDynamicMan);
    }

    private static function testBuild_GotoLabel_NonHero_直传():Void {
        trace("\n--- testBuild_GotoLabel_NonHero_直传 ---");
        var snap:Object = fakeSnap({ 兵种: "杂兵" });
        var plan:Object = StateTransitionPlan.build(snap, "技能");
        assertEquals("非主角男 → 直传 newStateName", "技能", plan.gotoLabel);
    }

    private static function testBuild_GotoLabel_HeroMale_技能Alias():Void {
        trace("\n--- testBuild_GotoLabel_HeroMale_技能Alias ---");
        var snap:Object = fakeSnap({ 兵种: "主角-男" });
        var plan:Object = StateTransitionPlan.build(snap, "技能");
        assertEquals("主角男 + 技能 → 容器", "容器", plan.gotoLabel);
    }

    private static function testBuild_GotoLabel_HeroMale_战技Alias():Void {
        trace("\n--- testBuild_GotoLabel_HeroMale_战技Alias ---");
        var snap:Object = fakeSnap({ 兵种: "主角-男" });
        var plan:Object = StateTransitionPlan.build(snap, "战技");
        assertEquals("主角男 + 战技 → 容器", "容器", plan.gotoLabel);
    }

    private static function testBuild_GotoLabel_HeroMale_兵器攻击容器Alias():Void {
        trace("\n--- testBuild_GotoLabel_HeroMale_兵器攻击容器Alias ---");
        var snap:Object = fakeSnap({ 兵种: "主角-男" });
        var plan:Object = StateTransitionPlan.build(snap, "兵器攻击容器");
        assertEquals("主角男 + 兵器攻击容器 → 容器", "容器", plan.gotoLabel);
    }

    private static function testBuild_GotoLabel_HeroMale_NonContainer直传():Void {
        trace("\n--- testBuild_GotoLabel_HeroMale_NonContainer直传 ---");
        var snap:Object = fakeSnap({ 兵种: "主角-男" });
        var plan:Object = StateTransitionPlan.build(snap, "受伤");
        assertEquals("主角男 非容器化状态 → 直传", "受伤", plan.gotoLabel);
    }

    private static function testBuild_GotoLabel_JobOverride_PressAlias():Void {
        trace("\n--- testBuild_GotoLabel_JobOverride_PressAlias ---");
        var snap:Object = fakeSnap({ 兵种: "主角-男", jobGotoOverride: "特殊帧" });
        var plan:Object = StateTransitionPlan.build(snap, "战技");
        assertEquals("jobOverride 压过容器别名", "特殊帧", plan.gotoLabel);
    }

    private static function testBuild_GotoLabel_JobOverride_NonHero忽略():Void {
        trace("\n--- testBuild_GotoLabel_JobOverride_NonHero忽略 ---");
        var snap:Object = fakeSnap({ 兵种: "杂兵", jobGotoOverride: "特殊帧" });
        var plan:Object = StateTransitionPlan.build(snap, "战技");
        assertEquals("非主角男 → jobOverride 忽略，直传", "战技", plan.gotoLabel);
    }

    private static function testBuild_Transition_SameStateSameLabel():Void {
        trace("\n--- testBuild_Transition_SameStateSameLabel ---");
        var snap:Object = fakeSnap({
            状态: "空手站立",
            __stateGotoLabel: "空手站立"
        });
        var plan:Object = StateTransitionPlan.build(snap, "空手站立");
        assertEquals("oldState=newState 且 prevGoto=newGoto → transition=false",
            false, plan.transition);
    }

    private static function testBuild_Transition_DiffState():Void {
        trace("\n--- testBuild_Transition_DiffState ---");
        var snap:Object = fakeSnap({ 状态: "空手站立" });
        var plan:Object = StateTransitionPlan.build(snap, "受伤");
        assertEquals("状态不同 → transition=true", true, plan.transition);
    }

    private static function testBuild_Transition_OnlyLabelChanged():Void {
        trace("\n--- testBuild_Transition_OnlyLabelChanged ---");
        var snap:Object = fakeSnap({
            兵种: "主角-男",
            状态: "技能",
            __stateGotoLabel: "容器",
            jobGotoOverride: "新帧"
        });
        var plan:Object = StateTransitionPlan.build(snap, "技能");
        assertEquals("逻辑态相同但 gotoLabel 变 → transition=true",
            true, plan.transition);
        assertEquals("gotoLabel=新帧", "新帧", plan.gotoLabel);
    }

    private static function testBuild_NewLogicalState():Void {
        trace("\n--- testBuild_NewLogicalState ---");
        var snap:Object = fakeSnap({});
        var plan:Object = StateTransitionPlan.build(snap, "受伤");
        assertEquals("newLogicalState = newStateName", "受伤", plan.newLogicalState);
    }

    // ====================================================================
    // validate
    // ====================================================================

    private static function testValidate_EarlyReturn():Void {
        trace("\n--- testValidate_EarlyReturn ---");
        var snap:Object = fakeSnap({ 飞行浮空: true });
        var plan:Object = StateTransitionPlan.build(snap, "空手跑");
        assertTrue("earlyReturn 分支 validate=true", StateTransitionPlan.validate(plan));
        plan.gotoLabel = "脏数据";
        assertFalse("earlyReturn 分支字段污染 validate=false", StateTransitionPlan.validate(plan));
    }

    private static function testValidate_TransitionMissingGotoLabel():Void {
        trace("\n--- testValidate_TransitionMissingGotoLabel ---");
        var plan:Object = {
            storeFlyState: false, earlyReturn: false,
            attackMode: "空手", oldState: "X",
            removeDynamicMan: false,
            gotoLabel: "", transition: true, newLogicalState: "Y"
        };
        assertFalse("transition=true 但 gotoLabel='' → validate=false",
            StateTransitionPlan.validate(plan));
    }

    private static function testValidate_NormalOk():Void {
        trace("\n--- testValidate_NormalOk ---");
        var snap:Object = fakeSnap({ 状态: "空手站立" });
        var plan:Object = StateTransitionPlan.build(snap, "受伤");
        assertTrue("正常 plan validate=true", StateTransitionPlan.validate(plan));
    }
}
