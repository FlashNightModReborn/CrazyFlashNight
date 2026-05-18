import org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle;

/**
 * RoutingLifecycle Test Suite
 *
 * 覆盖 RoutingLifecycle 中**不依赖 _root.空中控制器** 的部分：
 *   - ensureTempY        — 纯函数，四分支
 *   - preparePoseAndBonus — HeroUtil.isFistSkill 真实分支
 *   - bindMovement       — 8 字段写入（setup/teardown _root.技能函数 spy）
 *   - bindEndCleanup     — onUnload 闭包行为（excludeState / __preserveFloat / dispatcher / prev chain）
 *
 * **故意不测**：
 *   - buildPublicContainerInit — 依赖 ContainerInitScratch.getPublic 的 self-replacing first-call
 *     语义，testloader 上 first-call 不可保证；与 ContainerInitScratch 专项测试一起做。
 *   - handleFloat / clearSkillFloatTask / clearNaturalLandingTask / startNaturalLandingTask
 *     / completeAnimation — 依赖 _root.空中控制器，留给空中控制器解耦工程。
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
            __spy_dispatcherLastEvent: undefined
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
            onUnload: undefined
        };
    }

    // ====================================================================
    // 测试入口
    // ====================================================================

    public static function runAll():Void {
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

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
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
}
