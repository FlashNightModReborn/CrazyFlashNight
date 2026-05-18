import org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle;
import org.flashNight.arki.unit.UnitComponent.Routing.RoutingRuntime;

/**
 * RoutingLifecycle Test Suite
 *
 * 覆盖 RoutingLifecycle 中可以用 mock 隔离的部分：
 *   - ensureTempY        — 纯函数，四分支
 *   - preparePoseAndBonus — HeroUtil.isFistSkill 真实分支
 *   - bindMovement       — 8 字段写入（setup/teardown _root.技能函数 spy）
 *   - bindEndCleanup     — onUnload 闭包行为（excludeState / __preserveFloat / dispatcher / prev chain）
 *
 * 额外覆盖：
 *   - handleFloat / clear* / startNaturalLanding / completeAnimation
 *     — 通过 RoutingRuntime 注入 mock air/scheduler，不依赖真实空中控制器或帧时间
 *
 * **故意不测**：
 *   - buildPublicContainerInit — 依赖 ContainerInitScratch.getPublic 的 self-replacing first-call
 *     语义，testloader 上 first-call 不可保证；与 ContainerInitScratch 专项测试一起做。
 *
 * AS2 strict 类型注意：见 [[feedback-as2-strict-function-param-dynamic-path]] —
 * fake unit/man/container 全部 untyped 传递给签名 :MovieClip 的 method。
 *
 * 用法： org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycleTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycleTest {

    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    // ====================================================================
    // 断言工具
    // ====================================================================

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

    private static function assertSame(name:String, expectedRef, actualRef):Void {
        testCount++;
        if (expectedRef === actualRef) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (ref mismatch)");
        }
    }

    // ====================================================================
    // 夹具构造
    // ====================================================================

    private static function makeUnit(name:String) {
        var u = {
            _name: name,
            状态: undefined,
            技能名: undefined,
            攻击模式: undefined,
            temp_y: 0,
            浮空: false,
            _y: 100,
            Z轴坐标: 100,
            起始Y: undefined,
            格斗架势: false,
            无敌: true,
            __preserveFloatFlagOnUnload: undefined,
            __spy_bonusModeCount: 0,
            __spy_bonusModeLast: undefined,
            __spy_bigStateCount: 0,
            __spy_bigStateLastBig: undefined,
            __spy_bigStateLastSmall: undefined,
            __spy_dispatcherEvents: 0,
            __spy_dispatcherLastEvent: undefined,
            __spy_animationDone: 0,
            __技能浮空任务ID: undefined,
            __自然落地任务ID: undefined
        };
        u.根据模式重新读取武器加成 = function(mode) {
            this.__spy_bonusModeCount++;
            this.__spy_bonusModeLast = mode;
        };
        u.UpdateBigSmallState = function(big, small) {
            this.__spy_bigStateCount++;
            this.__spy_bigStateLastBig = big;
            this.__spy_bigStateLastSmall = small;
        };
        u.动画完毕 = function() {
            this.__spy_animationDone++;
        };
        return u;
    }

    private static function attachDispatcher(unit) {
        // 单独 attach，因为部分测试需要"无 dispatcher"分支
        unit.dispatcher = {
            __owner: unit,
            publish: function(eventName, payload) {
                this.__owner.__spy_dispatcherEvents++;
                this.__owner.__spy_dispatcherLastEvent = eventName;
            }
        };
    }

    private static function makeClip() {
        // 模拟 attachMovie 返回的容器或 man：plain object，onUnload 可手动触发
        return {
            __isDynamicMan: true,
            onUnload: undefined,
            __removed: false,
            removeMovieClip: function() {
                this.__removed = true;
            }
        };
    }

    private static function makeRuntimeSpy() {
        var spy = {
            closeSkillFloatCount: 0,
            closeNaturalLandingCount: 0,
            closeJumpFloatCount: 0,
            enableSkillFloatCount: 0,
            enableNaturalLandingCount: 0,
            lastSkillFloatFlag: undefined,
            lastSkillFloatMan: undefined,
            removeTaskCount: 0,
            lastRemovedTask: undefined
        };
        spy.air = {
            __spy: spy,
            关闭技能浮空: function(unit) {
                this.__spy.closeSkillFloatCount++;
            },
            关闭自然落地: function(unit) {
                this.__spy.closeNaturalLandingCount++;
            },
            关闭跳跃浮空: function(unit) {
                this.__spy.closeJumpFloatCount++;
            },
            启用技能浮空: function(unit, floatFlag, man) {
                this.__spy.enableSkillFloatCount++;
                this.__spy.lastSkillFloatFlag = floatFlag;
                this.__spy.lastSkillFloatMan = man;
            },
            启用自然落地: function(unit) {
                this.__spy.enableNaturalLandingCount++;
            }
        };
        spy.scheduler = {
            __spy: spy,
            removeTask: function(taskID) {
                this.__spy.removeTaskCount++;
                this.__spy.lastRemovedTask = taskID;
            }
        };
        return spy;
    }

    // ====================================================================
    // 测试入口
    // ====================================================================

    public static function runAll():Boolean {
        trace("================================================================");
        trace("RoutingLifecycle Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testEnsureTempY_AlreadyPositive();
        testEnsureTempY_FloatingFlag();
        testEnsureTempY_YBelowZ();
        testEnsureTempY_FallbackZero();

        testPreparePoseAndBonus_FistSkill();
        testPreparePoseAndBonus_NonFistSkill();
        testPreparePoseAndBonus_UndefinedSkillName();

        testBindMovement_AllFieldsWired();

        testBindEndCleanup_DefaultPath();
        testBindEndCleanup_ExcludeStateMatched();
        testBindEndCleanup_PreserveFloatFlag();
        testBindEndCleanup_NoDispatcher();
        testBindEndCleanup_PrevOnUnloadChained();
        testHandleFloat_MockRuntime();
        testHandleFloat_NoTempYSkipsRuntime();
        testClearNaturalLandingTask_MockRuntime();
        testStartNaturalLandingTask_MockRuntime();
        testCompleteAnimation_DoubleJumpPreservesFloat();
        testCompleteAnimation_StartsNaturalLanding();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ====================================================================
    // ensureTempY — 纯函数，四分支
    // ====================================================================

    private static function testEnsureTempY_AlreadyPositive():Void {
        trace("\n--- testEnsureTempY_AlreadyPositive ---");
        var u = makeUnit("ety1");
        u.temp_y = 50;     // 已有正值
        u._y = 80;
        u.浮空 = true;
        RoutingLifecycle.ensureTempY(u);
        assertEquals("temp_y 保留 50（早退）", 50, u.temp_y);
    }

    private static function testEnsureTempY_FloatingFlag():Void {
        trace("\n--- testEnsureTempY_FloatingFlag ---");
        var u = makeUnit("ety2");
        u.temp_y = 0;
        u._y = 280;
        u.浮空 = true;
        u.Z轴坐标 = 320;
        RoutingLifecycle.ensureTempY(u);
        assertEquals("浮空=true → temp_y=_y", 280, u.temp_y);
    }

    private static function testEnsureTempY_YBelowZ():Void {
        trace("\n--- testEnsureTempY_YBelowZ ---");
        var u = makeUnit("ety3");
        u.temp_y = 0;
        u._y = 250;
        u.浮空 = false;       // 浮空标记没同步
        u.Z轴坐标 = 320;       // y < Z → 在空中
        RoutingLifecycle.ensureTempY(u);
        assertEquals("y<Z 兜底 → temp_y=_y", 250, u.temp_y);
    }

    private static function testEnsureTempY_FallbackZero():Void {
        trace("\n--- testEnsureTempY_FallbackZero ---");
        var u = makeUnit("ety4");
        u.temp_y = 0;
        u._y = 320;
        u.浮空 = false;
        u.Z轴坐标 = 320;      // 站立
        RoutingLifecycle.ensureTempY(u);
        assertEquals("站立兜底 → temp_y=0", 0, u.temp_y);
    }

    // ====================================================================
    // preparePoseAndBonus — HeroUtil.isFistSkill 真实分支
    // ====================================================================

    private static function testPreparePoseAndBonus_FistSkill():Void {
        trace("\n--- testPreparePoseAndBonus_FistSkill ---");
        var u = makeUnit("pose1");
        u.格斗架势 = false;
        u.技能名 = "破极拳1连招";   // 含"拳" → isFistSkill=true → 空手

        RoutingLifecycle.preparePoseAndBonus(u);

        assertTrue("格斗架势 = true", u.格斗架势);
        assertEquals("根据模式 调用 1 次", 1, u.__spy_bonusModeCount);
        assertEquals("mode = 空手",       "空手", u.__spy_bonusModeLast);
    }

    private static function testPreparePoseAndBonus_NonFistSkill():Void {
        trace("\n--- testPreparePoseAndBonus_NonFistSkill ---");
        var u = makeUnit("pose2");
        u.技能名 = "刀剑1连招";   // 无"拳" → isFistSkill=false → 技能

        RoutingLifecycle.preparePoseAndBonus(u);

        assertTrue("格斗架势 = true", u.格斗架势);
        assertEquals("mode = 技能", "技能", u.__spy_bonusModeLast);
    }

    private static function testPreparePoseAndBonus_UndefinedSkillName():Void {
        // skillName=undefined → isFistSkill 返回 false → 走"技能"
        trace("\n--- testPreparePoseAndBonus_UndefinedSkillName ---");
        var u = makeUnit("pose3");
        u.技能名 = undefined;

        RoutingLifecycle.preparePoseAndBonus(u);

        assertEquals("undefined 技能名兜底 mode = 技能", "技能", u.__spy_bonusModeLast);
    }

    // ====================================================================
    // bindMovement — 8 字段写入；setup/teardown _root.技能函数 spy
    // ====================================================================

    private static function testBindMovement_AllFieldsWired():Void {
        trace("\n--- testBindMovement_AllFieldsWired ---");

        // setup：testloader 上 _root.技能函数 通常未初始化，挂 8 个 spy fn
        var sentinel = {};   // 唯一识别引用
        var prev = _root.技能函数;
        _root.技能函数 = {
            攻击时移动: sentinel,
            攻击时按键四向移动: sentinel,
            攻击时可改变移动方向: sentinel,
            攻击时可斜向改变移动方向: sentinel,
            攻击时斜向移动: sentinel,
            攻击时可斜向改变移动方向2: sentinel,
            获取移动方向: sentinel
        };

        try {
            var man = makeClip();
            RoutingLifecycle.bindMovement(man);

            // 8 个字段都应指向 sentinel
            assertSame("攻击时移动",               sentinel, man.攻击时移动);
            assertSame("攻击时后退移动 = 攻击时移动", sentinel, man.攻击时后退移动);
            assertSame("攻击时按键四向移动",         sentinel, man.攻击时按键四向移动);
            assertSame("攻击时可改变移动方向",       sentinel, man.攻击时可改变移动方向);
            assertSame("攻击时可斜向改变移动方向",   sentinel, man.攻击时可斜向改变移动方向);
            assertSame("攻击时斜向移动",             sentinel, man.攻击时斜向移动);
            assertSame("攻击时可斜向改变移动方向2",  sentinel, man.攻击时可斜向改变移动方向2);
            assertSame("获取移动方向",               sentinel, man.获取移动方向);
        } finally {
            // teardown：还原 _root.技能函数（即便 prev=undefined 也要 delete）
            if (prev == undefined) {
                delete _root.技能函数;
            } else {
                _root.技能函数 = prev;
            }
        }
    }

    // ====================================================================
    // bindEndCleanup — onUnload 闭包行为
    // ====================================================================

    private static function testBindEndCleanup_DefaultPath():Void {
        // 普通技能结束：状态 != excludeState → reset temp_y + 清浮空标记
        trace("\n--- testBindEndCleanup_DefaultPath ---");
        var u = makeUnit("ec1");
        u.状态 = "技能";        // != excludeState("战技") → needReset=true
        u.temp_y = 80;
        u.技能浮空 = true;
        u.攻击模式 = "兵器";
        attachDispatcher(u);

        var clip = makeClip();
        RoutingLifecycle.bindEndCleanup(clip, u, "战技", "技能结束", "技能浮空");

        clip.onUnload();

        assertEquals("无敌 = false",         false, u.无敌);
        assertEquals("temp_y = 0",            0,     u.temp_y);
        assertEquals("UpdateBigSmallState 调用 1 次", 1, u.__spy_bigStateCount);
        assertEquals("big = 技能结束",        "技能结束", u.__spy_bigStateLastBig);
        assertEquals("small = 技能结束",      "技能结束", u.__spy_bigStateLastSmall);
        assertEquals("根据模式调用 1 次",      1, u.__spy_bonusModeCount);
        assertEquals("mode = 兵器（unit.攻击模式）", "兵器", u.__spy_bonusModeLast);
        assertEquals("技能浮空 = false",       false, u.技能浮空);
        assertEquals("dispatcher.publish 1 次", 1, u.__spy_dispatcherEvents);
        assertEquals("dispatcher event = skillEnd", "skillEnd", u.__spy_dispatcherLastEvent);
    }

    private static function testBindEndCleanup_ExcludeStateMatched():Void {
        // 状态 == excludeState → 不 reset temp_y、不清浮空标记
        // 用例：战技 onUnload 时状态已被改为"技能"，状态==excludeState → 跳过 reset
        trace("\n--- testBindEndCleanup_ExcludeStateMatched ---");
        var u = makeUnit("ec2");
        u.状态 = "战技";          // == excludeState → needReset=false
        u.temp_y = 80;
        u.技能浮空 = true;
        u.攻击模式 = "空手";

        var clip = makeClip();
        RoutingLifecycle.bindEndCleanup(clip, u, "战技", "技能结束", "技能浮空");

        clip.onUnload();

        assertEquals("无敌 = false（无论分支）", false, u.无敌);
        assertEquals("temp_y 保留 80（needReset=false）", 80, u.temp_y);
        assertEquals("UpdateBigSmallState 仍调用", 1, u.__spy_bigStateCount);
        assertEquals("技能浮空 保留 true",         true, u.技能浮空);
    }

    private static function testBindEndCleanup_PreserveFloatFlag():Void {
        // __preserveFloatFlagOnUnload 命中 → delete 标记字段，**不**清浮空
        // 用例：enableDoubleJump 场景，技能浮空要带到跳跃状态 load 阶段
        trace("\n--- testBindEndCleanup_PreserveFloatFlag ---");
        var u = makeUnit("ec3");
        u.状态 = "技能";          // != excludeState → 进 needReset 分支
        u.技能浮空 = true;
        u.__preserveFloatFlagOnUnload = "技能浮空";    // 命中

        var clip = makeClip();
        RoutingLifecycle.bindEndCleanup(clip, u, "战技", "技能结束", "技能浮空");

        clip.onUnload();

        assertEquals("__preserve 已 delete", undefined, u.__preserveFloatFlagOnUnload);
        assertEquals("技能浮空 保留 true（跳过清零）", true, u.技能浮空);
    }

    private static function testBindEndCleanup_NoDispatcher():Void {
        // 无 dispatcher 时不抛异常
        trace("\n--- testBindEndCleanup_NoDispatcher ---");
        var u = makeUnit("ec4");
        u.状态 = "技能";
        // 故意不 attachDispatcher

        var clip = makeClip();
        RoutingLifecycle.bindEndCleanup(clip, u, "战技", "技能结束", "技能浮空");

        clip.onUnload();
        assertTrue("无 dispatcher 不抛异常", true);
        assertEquals("dispatcher 事件计数 = 0", 0, u.__spy_dispatcherEvents);
    }

    private static function testBindEndCleanup_PrevOnUnloadChained():Void {
        // bind 前若 clip.onUnload 已有内容，chain 而非覆盖
        trace("\n--- testBindEndCleanup_PrevOnUnloadChained ---");
        var u = makeUnit("ec5");
        u.状态 = "技能";

        var clip = makeClip();
        var prevCount:Number = 0;
        clip.onUnload = function() { prevCount++; };

        RoutingLifecycle.bindEndCleanup(clip, u, "战技", "技能结束", "技能浮空");
        clip.onUnload();

        assertEquals("前序 onUnload 被调用 1 次", 1, prevCount);
        assertEquals("新逻辑也执行（UpdateBigSmallState 1 次）", 1, u.__spy_bigStateCount);
    }

    // ====================================================================
    // float / scheduler / animation — RoutingRuntime mock
    // ====================================================================

    private static function installRuntimeSpy(spy):Void {
        RoutingRuntime.setAirControllerForTest(spy.air);
        RoutingRuntime.setSchedulerForTest(spy.scheduler);
    }

    private static function clearRuntimeSpy():Void {
        RoutingRuntime.clearAirControllerForTest();
        RoutingRuntime.clearSchedulerForTest();
    }

    private static function testHandleFloat_MockRuntime():Void {
        trace("\n--- testHandleFloat_MockRuntime ---");
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            var u = makeUnit("hf1");
            var man = makeClip();
            u.temp_y = 240;
            u._y = 320;
            u.Z轴坐标 = 360;
            u.__技能浮空任务ID = 77;

            RoutingLifecycle.handleFloat(man, u, "技能浮空");

            assertEquals("man.落地 = false", false, man.落地);
            assertEquals("unit.技能浮空 = true", true, u.技能浮空);
            assertEquals("unit._y 回到 temp_y", 240, u._y);
            assertEquals("unit.起始Y = Z", 360, u.起始Y);
            assertEquals("unit.浮空 = true", true, u.浮空);
            assertEquals("关闭技能浮空 1 次", 1, spy.closeSkillFloatCount);
            assertEquals("关闭自然落地 1 次", 1, spy.closeNaturalLandingCount);
            assertEquals("关闭跳跃浮空 1 次", 1, spy.closeJumpFloatCount);
            assertEquals("启用技能浮空 1 次", 1, spy.enableSkillFloatCount);
            assertEquals("floatFlag 透传", "技能浮空", spy.lastSkillFloatFlag);
            assertSame("man 透传", man, spy.lastSkillFloatMan);
            assertEquals("旧任务 remove 1 次", 1, spy.removeTaskCount);
            assertEquals("旧任务 id 77", 77, spy.lastRemovedTask);
            assertEquals("unit.__技能浮空任务ID 清空", null, u.__技能浮空任务ID);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testHandleFloat_NoTempYSkipsRuntime():Void {
        trace("\n--- testHandleFloat_NoTempYSkipsRuntime ---");
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            var u = makeUnit("hf2");
            var man = makeClip();
            u.temp_y = 0;

            RoutingLifecycle.handleFloat(man, u, "技能浮空");

            assertEquals("man.落地 = true", true, man.落地);
            assertEquals("不启用技能浮空", 0, spy.enableSkillFloatCount);
            assertEquals("不关闭自然落地", 0, spy.closeNaturalLandingCount);
            assertEquals("不移除任务", 0, spy.removeTaskCount);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testClearNaturalLandingTask_MockRuntime():Void {
        trace("\n--- testClearNaturalLandingTask_MockRuntime ---");
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            var u = makeUnit("nl1");
            u.__自然落地任务ID = 88;

            RoutingLifecycle.clearNaturalLandingTask(u);

            assertEquals("关闭自然落地 1 次", 1, spy.closeNaturalLandingCount);
            assertEquals("removeTask 1 次", 1, spy.removeTaskCount);
            assertEquals("removeTask id 88", 88, spy.lastRemovedTask);
            assertEquals("__自然落地任务ID 清空", null, u.__自然落地任务ID);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testStartNaturalLandingTask_MockRuntime():Void {
        trace("\n--- testStartNaturalLandingTask_MockRuntime ---");
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            var u = makeUnit("nl2");
            u.__自然落地任务ID = 89;

            RoutingLifecycle.startNaturalLandingTask(u);

            assertEquals("先关闭自然落地", 1, spy.closeNaturalLandingCount);
            assertEquals("旧自然落地任务已 remove", 1, spy.removeTaskCount);
            assertEquals("启用自然落地 1 次", 1, spy.enableNaturalLandingCount);
            assertEquals("__自然落地任务ID 清空", null, u.__自然落地任务ID);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testCompleteAnimation_DoubleJumpPreservesFloat():Void {
        trace("\n--- testCompleteAnimation_DoubleJumpPreservesFloat ---");
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            var u = makeUnit("ca1");
            var man = makeClip();
            u._y = 220;
            u.Z轴坐标 = 300;
            u.__技能浮空任务ID = 101;

            RoutingLifecycle.completeAnimation(man, u, true);

            assertEquals("动画完毕调用 1 次", 1, u.__spy_animationDone);
            assertEquals("man 已 remove", true, man.__removed);
            assertEquals("技能浮空 = true", true, u.技能浮空);
            assertEquals("__preserve = 技能浮空", "技能浮空", u.__preserveFloatFlagOnUnload);
            assertEquals("旧技能浮空任务 remove", 1, spy.removeTaskCount);
            assertEquals("不启用自然落地", 0, spy.enableNaturalLandingCount);
        } finally {
            clearRuntimeSpy();
        }
    }

    private static function testCompleteAnimation_StartsNaturalLanding():Void {
        trace("\n--- testCompleteAnimation_StartsNaturalLanding ---");
        var spy = makeRuntimeSpy();
        installRuntimeSpy(spy);
        try {
            var u = makeUnit("ca2");
            var man = makeClip();
            u._y = 220;
            u.Z轴坐标 = 300;

            RoutingLifecycle.completeAnimation(man, u, false);

            assertEquals("动画完毕调用 1 次", 1, u.__spy_animationDone);
            assertEquals("man 已 remove", true, man.__removed);
            assertEquals("未设置 preserve", undefined, u.__preserveFloatFlagOnUnload);
            assertEquals("关闭技能浮空 1 次", 1, spy.closeSkillFloatCount);
            assertEquals("启用自然落地 1 次", 1, spy.enableNaturalLandingCount);
        } finally {
            clearRuntimeSpy();
        }
    }
}
