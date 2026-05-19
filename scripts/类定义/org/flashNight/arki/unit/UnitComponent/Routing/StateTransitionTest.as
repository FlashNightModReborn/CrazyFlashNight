import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * StateTransition Test Suite
 *
 * 端到端覆盖 producer-set → StateTransition.apply → gotoAndStop → executeStateTransitionJob
 * 同步嵌套契约。fake unit 是 plain object，spy gotoAndStop / 读取当前飞行状态 / 存储当前飞行状态
 * / man.removeMovieClip / 状态改变 等 instance method 来拦截副作用。
 *
 * 不依赖真实 `_root.帧计时器`，但会临时写 `_root.控制目标` 供 shouldStoreFlyState 判定使用，
 * 每个 case 用 try-finally 还原。
 *
 * AS2 strict 类型注意：见 [[feedback-as2-strict-function-param-dynamic-path]] —
 *   fake unit/man 全部 untyped 传递给签名 :MovieClip 的 method。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.StateTransitionTest {

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

    private static function assertSame(name:String, expected, actual):Void {
        testCount++;
        if (expected === actual) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (not same ref)");
        }
    }

    // ====================================================================
    // fake unit / man factory
    // ====================================================================

    private static function makeUnit(name:String) {
        var u = {
            _name: name,
            兵种: "杂兵",
            状态: undefined,
            旧状态: undefined,
            攻击模式: "空手",
            __stateGotoLabel: undefined,
            __stateTransitionJob: undefined,
            man: undefined,
            飞行浮空: undefined,
            __spy_gotoAndStop_count: 0,
            __spy_gotoAndStop_last: undefined,
            __spy_read_count: 0,
            __spy_store_count: 0,
            __spy_store_last: undefined
        };
        u.gotoAndStop = function(label) {
            this.__spy_gotoAndStop_count++;
            this.__spy_gotoAndStop_last = label;
        };
        u.读取当前飞行状态 = function() {
            this.__spy_read_count++;
        };
        u.存储当前飞行状态 = function(reason) {
            this.__spy_store_count++;
            this.__spy_store_last = reason;
        };
        return u;
    }

    private static function makeDynamicMan() {
        var m = {
            __isDynamicMan: true,
            __removed: false
        };
        m.removeMovieClip = function() {
            this.__removed = true;
        };
        return m;
    }

    private static function makeStaticMan() {
        var m = {
            __isDynamicMan: undefined,
            __removed: false
        };
        m.removeMovieClip = function() {
            this.__removed = true;
        };
        return m;
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

    // ====================================================================
    // 测试入口
    // ====================================================================

    public static function runAll():Boolean {
        trace("================================================================");
        trace("StateTransition Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testBasicTransition_NonHero();
        testAttackModeFallback();
        testFlyingRunEarlyReturn();
        testStoreFlyState_HitOnHero();
        testStoreFlyState_MissOnNonControlTarget();
        testHeroMale_ContainerAlias_技能();
        testHeroMale_ContainerAlias_战技();
        testHeroMale_ContainerAlias_兵器攻击容器();
        testHeroMale_NonContainerState_直传();
        testJobOverride_主角男_压过别名();
        testNoTransition_ClearJob();
        testTransition_OnlyGotoLabelChanged();
        testDynamicMan_Cleanup();
        testStaticMan_NotCleaned();
        testProducerConsumer_EndToEnd();
        testProducerConsumer_ContainerAliasWithJob();
        testOldStateRecorded();
        testStateGotoLabelRecorded();
        testReadFlyStateAfterGoto();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ====================================================================
    // 基本 transition：非主角-男，直接跳转
    // ====================================================================

    private static function testBasicTransition_NonHero():Void {
        trace("\n--- testBasicTransition_NonHero ---");
        withControlTarget("hero", function() {
            var u = StateTransitionTest.makeUnit("enemy");
            u.状态 = "空手站立";

            StateTransition.apply(u, "受伤");

            StateTransitionTest.assertEquals("状态切换至 受伤", "受伤", u.状态);
            StateTransitionTest.assertEquals("旧状态 = 空手站立", "空手站立", u.旧状态);
            StateTransitionTest.assertEquals("gotoAndStop 1 次", 1, u.__spy_gotoAndStop_count);
            StateTransitionTest.assertEquals("gotoLabel = 受伤", "受伤", u.__spy_gotoAndStop_last);
            StateTransitionTest.assertEquals("__stateGotoLabel 写入", "受伤", u.__stateGotoLabel);
            StateTransitionTest.assertEquals("读取飞行状态 1 次", 1, u.__spy_read_count);
            StateTransitionTest.assertEquals("存储飞行状态 0 次（非控制目标）", 0, u.__spy_store_count);
        });
    }

    // ====================================================================
    // 攻击模式兜底
    // ====================================================================

    private static function testAttackModeFallback():Void {
        trace("\n--- testAttackModeFallback ---");
        var u = makeUnit("e1");
        u.攻击模式 = undefined;
        u.状态 = "空手站立";

        StateTransition.apply(u, "受伤");

        assertEquals("攻击模式 兜底为 空手", "空手", u.攻击模式);
    }

    // ====================================================================
    // 飞行浮空 + 跑：早退
    // ====================================================================

    private static function testFlyingRunEarlyReturn():Void {
        trace("\n--- testFlyingRunEarlyReturn ---");
        var u = makeUnit("e1");
        u.状态 = "空手站立";
        u.飞行浮空 = true;

        StateTransition.apply(u, "空手跑");

        assertEquals("状态未变化", "空手站立", u.状态);
        assertEquals("gotoAndStop 未调用", 0, u.__spy_gotoAndStop_count);
        assertEquals("__stateGotoLabel 未写入", undefined, u.__stateGotoLabel);
    }

    // ====================================================================
    // 存储飞行状态：控制目标 + 同攻击模式攻击/站立
    // ====================================================================

    private static function testStoreFlyState_HitOnHero():Void {
        trace("\n--- testStoreFlyState_HitOnHero ---");
        withControlTarget("hero", function() {
            var u = StateTransitionTest.makeUnit("hero");
            u.攻击模式 = "空手";
            u.状态 = "空手站立";

            StateTransition.apply(u, "空手攻击");

            StateTransitionTest.assertEquals("存储飞行状态 1 次", 1, u.__spy_store_count);
            StateTransitionTest.assertEquals("存储 reason = 状态改变", "状态改变", u.__spy_store_last);
        });
    }

    private static function testStoreFlyState_MissOnNonControlTarget():Void {
        trace("\n--- testStoreFlyState_MissOnNonControlTarget ---");
        withControlTarget("hero", function() {
            var u = StateTransitionTest.makeUnit("enemy");
            u.攻击模式 = "空手";
            u.状态 = "空手站立";

            StateTransition.apply(u, "空手攻击");

            StateTransitionTest.assertEquals("非控制目标 不存储", 0, u.__spy_store_count);
        });
    }

    // ====================================================================
    // 主角-男容器化别名
    // ====================================================================

    private static function testHeroMale_ContainerAlias_技能():Void {
        trace("\n--- testHeroMale_ContainerAlias_技能 ---");
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";

        StateTransition.apply(u, "技能");

        assertEquals("逻辑状态 = 技能", "技能", u.状态);
        assertEquals("显示帧 = 容器", "容器", u.__spy_gotoAndStop_last);
        assertEquals("__stateGotoLabel = 容器", "容器", u.__stateGotoLabel);
    }

    private static function testHeroMale_ContainerAlias_战技():Void {
        trace("\n--- testHeroMale_ContainerAlias_战技 ---");
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";

        StateTransition.apply(u, "战技");

        assertEquals("逻辑状态 = 战技", "战技", u.状态);
        assertEquals("显示帧 = 容器", "容器", u.__spy_gotoAndStop_last);
    }

    private static function testHeroMale_ContainerAlias_兵器攻击容器():Void {
        trace("\n--- testHeroMale_ContainerAlias_兵器攻击容器 ---");
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";

        StateTransition.apply(u, "兵器攻击容器");

        assertEquals("逻辑状态 = 兵器攻击容器", "兵器攻击容器", u.状态);
        assertEquals("显示帧 = 容器", "容器", u.__spy_gotoAndStop_last);
    }

    private static function testHeroMale_NonContainerState_直传():Void {
        trace("\n--- testHeroMale_NonContainerState_直传 ---");
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";

        StateTransition.apply(u, "受伤");

        assertEquals("逻辑状态 = 受伤", "受伤", u.状态);
        assertEquals("显示帧 = 受伤（无别名）", "受伤", u.__spy_gotoAndStop_last);
    }

    // ====================================================================
    // Job override：producer-set 写入 job 后，apply 应消费 jobGotoLabel
    // ====================================================================

    private static function testJobOverride_主角男_压过别名():Void {
        trace("\n--- testJobOverride_主角男_压过别名 ---");
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";

        // producer-set：触发"战技"应跳"容器"，但 jobGotoLabel 强制改成 "特殊帧"
        var job:Object = RoutingIntent.createStateTransitionJob(u, "特殊帧", function(unit) {});

        StateTransition.apply(u, "战技");

        assertEquals("逻辑状态 = 战技", "战技", u.状态);
        assertEquals("显示帧 = 特殊帧（job 覆盖容器别名）", "特殊帧", u.__spy_gotoAndStop_last);
        // executeStateTransitionJob 取走 callback → job 字段置 undefined
        assertEquals("job.callback 取走后 = undefined", undefined, u.__stateTransitionJob.callback);
        assertEquals("job.gotoLabel 取走后 = undefined", undefined, u.__stateTransitionJob.gotoLabel);
    }

    // ====================================================================
    // 无变化：不 transition，走 clearJob 兜底
    // ====================================================================

    private static function testNoTransition_ClearJob():Void {
        trace("\n--- testNoTransition_ClearJob ---");
        var u = makeUnit("e1");
        u.状态 = "空手站立";
        u.__stateGotoLabel = "空手站立";
        u.旧状态 = "空手站立";
        // 模拟残留 job
        var capturedCount:Number = 0;
        var job:Object = RoutingIntent.createStateTransitionJob(u, "labelX", function(unit) {
            capturedCount++;
        });

        StateTransition.apply(u, "空手站立");

        assertEquals("gotoAndStop 未调用", 0, u.__spy_gotoAndStop_count);
        assertEquals("callback 未触发", 0, capturedCount);
        assertEquals("job.callback 被 clearJob 置 undefined", undefined, u.__stateTransitionJob.callback);
        assertEquals("job.gotoLabel 被 clearJob 置 undefined", undefined, u.__stateTransitionJob.gotoLabel);
    }

    private static function testTransition_OnlyGotoLabelChanged():Void {
        trace("\n--- testTransition_OnlyGotoLabelChanged ---");
        // 主角男容器化场景：logicalState 不变，但因 job override 让 gotoLabel 跳了
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "技能";
        u.__stateGotoLabel = "容器";

        // 再次调用 状态改变("技能") + job override "新帧" → 应当 transition
        var job:Object = RoutingIntent.createStateTransitionJob(u, "新帧", function(unit) {});

        StateTransition.apply(u, "技能");

        assertEquals("gotoAndStop 调用 1 次", 1, u.__spy_gotoAndStop_count);
        assertEquals("跳到新帧", "新帧", u.__spy_gotoAndStop_last);
    }

    // ====================================================================
    // 动态 man 清理
    // ====================================================================

    private static function testDynamicMan_Cleanup():Void {
        trace("\n--- testDynamicMan_Cleanup ---");
        var u = makeUnit("e1");
        u.状态 = "空手站立";
        var m = makeDynamicMan();
        u.man = m;

        StateTransition.apply(u, "受伤");

        assertTrue("动态 man 被 remove", m.__removed);
    }

    private static function testStaticMan_NotCleaned():Void {
        trace("\n--- testStaticMan_NotCleaned ---");
        var u = makeUnit("e1");
        u.状态 = "空手站立";
        var m = makeStaticMan();
        u.man = m;

        StateTransition.apply(u, "受伤");

        assertFalse("静态 man 不应 remove", m.__removed);
    }

    // ====================================================================
    // 端到端：producer-set → apply → consumer callback
    // ====================================================================

    private static function testProducerConsumer_EndToEnd():Void {
        trace("\n--- testProducerConsumer_EndToEnd ---");
        // 模拟拳刀行走状态机触发兵器攻击容器化的完整链：
        //   producer-set (createStateTransitionJob 写 job)
        //   → 调用方触发 状态改变 → StateTransition.apply
        //   → apply 内 shouldTransition true → gotoAndStop → executeStateTransitionJob → callback
        // fake unit 没挂 `状态改变` facade，直接走 apply 路径。

        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";

        var callbackCount:Number = 0;
        var callbackUnit = undefined;
        var callbackOrder = [];
        // 在 gotoAndStop 期间记录顺序：spy gotoAndStop push 'goto'，callback push 'cb'
        var origGoto = u.gotoAndStop;
        u.gotoAndStop = function(label) {
            callbackOrder.push("goto:" + label);
            origGoto.apply(this, [label]);
        };

        var cb = function(unit) {
            callbackCount++;
            callbackUnit = unit;
            callbackOrder.push("cb");
        };

        // producer-set：写 job
        RoutingIntent.createStateTransitionJob(u, "容器", cb);

        // consumer：状态改变 → apply
        StateTransition.apply(u, "兵器攻击容器");

        assertEquals("callback 触发 1 次", 1, callbackCount);
        assertSame("callback 收到 self", u, callbackUnit);
        // 顺序：gotoAndStop 在前，cb 在后（apply 第 8 步先 gotoAndStop，再 executeJob）
        assertEquals("gotoAndStop 在 cb 之前", "goto:容器", callbackOrder[0]);
        assertEquals("cb 在 gotoAndStop 之后", "cb", callbackOrder[1]);
    }

    private static function testProducerConsumer_ContainerAliasWithJob():Void {
        trace("\n--- testProducerConsumer_ContainerAliasWithJob ---");
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";

        var callbackHits:Number = 0;
        // producer-set：jobGotoLabel = 容器 (=== alias)
        RoutingIntent.createStateTransitionJob(u, "容器", function(unit) {
            callbackHits++;
        });

        // 进入"技能"：容器化别名 → 容器；job override 也是 容器；最终 = 容器
        StateTransition.apply(u, "技能");

        assertEquals("gotoAndStop 1 次", 1, u.__spy_gotoAndStop_count);
        assertEquals("显示帧 = 容器", "容器", u.__spy_gotoAndStop_last);
        assertEquals("callback 触发 1 次", 1, callbackHits);
    }

    // ====================================================================
    // 字段记录
    // ====================================================================

    private static function testOldStateRecorded():Void {
        trace("\n--- testOldStateRecorded ---");
        var u = makeUnit("e1");
        u.状态 = "空手攻击";

        StateTransition.apply(u, "空手站立");

        assertEquals("旧状态 = 空手攻击", "空手攻击", u.旧状态);
        assertEquals("新状态 = 空手站立", "空手站立", u.状态);
    }

    private static function testStateGotoLabelRecorded():Void {
        trace("\n--- testStateGotoLabelRecorded ---");
        var u = makeUnit("hero");
        u.兵种 = "主角-男";
        u.状态 = "空手站立";

        StateTransition.apply(u, "战技");

        assertEquals("__stateGotoLabel = 容器", "容器", u.__stateGotoLabel);
    }

    private static function testReadFlyStateAfterGoto():Void {
        trace("\n--- testReadFlyStateAfterGoto ---");
        var u = makeUnit("e1");
        u.状态 = "空手站立";

        StateTransition.apply(u, "受伤");

        // 真发生跳转时 读取当前飞行状态 应被调用 1 次
        assertEquals("读取当前飞行状态 1 次", 1, u.__spy_read_count);
    }
}
