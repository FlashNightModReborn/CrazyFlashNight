import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * RoutingCrossContainerTest — III.3 跨容器跳转端到端
 *
 * 复现 _root.空手攻击路由.__job_跨容器跳转(u) 的核心算法：
 *
 *   var job = u.__stateTransitionJob;
 *   var initObj = 构建空手攻击容器初始化对象(u.container);
 *   var result = ContainerAttachAction.attach(u, KIND_UNARMED, job.arg_containerName, initObj);
 *   if (result.status === STATUS_MISSING_ABORT) return;
 *   var man = result.man;
 *   // [skip 控制目标 + JumpDerive 分支 — 已由 JumpDeriveAction 套件覆盖]
 *   u.格斗架势 = true;
 *   bindContainerEndState(man, u, SMALL_END_BAREHAND);
 *   man.gotoAndPlay(job.arg_targetLabel);
 *
 * 在 testloader 内通过 MockMovieClip + MockContainer 重现该流程，不依赖
 * `_root.空手攻击路由` 时间线引擎 .as 是否加载。这是契约 §2 已知陷阱"attachMovie
 * 之后子级 MC 的 onClipEvent(load) 立即执行"的本地化等价：mock 端 attachMovie
 * 返回后子级 setup（gotoAndPlay、onUnload 链）同步可见。
 *
 * 覆盖：
 *   - HAPPY: 跨容器 attach + initObj 透传 + man.gotoAndPlay(targetLabel)
 *   - MISSING ABORT: missingSymbol 命中 → 不 attach + unit.man 不存在
 *   - bindContainerEndState 触发 SMALL_END_BAREHAND
 *   - job 参数透传链：arg_containerName / arg_targetLabel
 *   - 同帧二次 跨容器跳转 行为（前一个 man 被替换 + onUnload 触发）
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingCrossContainerTest {

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

    public static function runAll():Boolean {
        trace("================================================================");
        trace("Routing CrossContainer Test Suite (III.3)");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        RoutingRuntime.clearAttachMovieAdapterForTest();

        testCrossContainer_HappyAttach();
        testCrossContainer_MissingAbort();
        testCrossContainer_BindContainerEndStateOnRemove();
        testCrossContainer_JobParamsPassthrough();
        testCrossContainer_SecondJumpReplacesPriorMan();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ════════════════════════════════════════════════════════════════════
    // 夹具
    // ════════════════════════════════════════════════════════════════════

    private static function makeUnit() {
        var u:MockMovieClip = new MockMovieClip();
        u.__name = "hero";
        u._name = "hero";
        u.格斗架势 = false;
        u.__spy_bigStateCount = 0;
        u.__spy_bigStateLastBig = undefined;
        u.__spy_bigStateLastSmall = undefined;
        u.UpdateBigSmallState = function(big, small) {
            this.__spy_bigStateCount++;
            this.__spy_bigStateLastBig = big;
            this.__spy_bigStateLastSmall = small;
        };
        u.根据模式重新读取武器加成 = function(mode) {};
        return u;
    }

    /**
     * 复现 _root.空手攻击路由.__job_跨容器跳转 核心算法（剥离 控制目标 + JumpDerive
     * 分支，那已在 JumpDeriveActionTest 端到端覆盖）。
     */
    private static function runCrossContainerJob(u, containerInitObj:Object):Object {
        var job:Object = u.__stateTransitionJob;
        var attachResult:Object = ContainerAttachAction.attach(
            u, ContainerSpec.KIND_UNARMED, job.arg_containerName, containerInitObj);
        if (attachResult.status === ContainerAttachAction.STATUS_MISSING_ABORT) {
            return {status: "abort", man: undefined};
        }
        var man = attachResult.man;
        u.格斗架势 = true;
        RoutingIntent.bindContainerEndState(man, u, RoutingIntent.SMALL_END_BAREHAND);
        man.gotoAndPlay(job.arg_targetLabel);
        return {status: "ok", man: man};
    }

    // ════════════════════════════════════════════════════════════════════
    // 用例
    // ════════════════════════════════════════════════════════════════════

    private static function testCrossContainer_HappyAttach():Void {
        trace("\n--- testCrossContainer_HappyAttach ---");
        var u = makeUnit();
        u.__stateTransitionJob = {
            arg_containerName: "2连招",
            arg_targetLabel: "重击"
        };

        var ret:Object = runCrossContainerJob(u, {hp: 100, 招式: "2连招"});

        assertEquals("status = ok", "ok", ret.status);
        assertTrue("man 存在", ret.man != undefined);
        assertEquals("unit.man === man", ret.man, u.man);
        assertEquals("linkage 拼接", "空手攻击容器-2连招",
            u.__initObjectsReceived[0].linkage);
        assertEquals("man.gotoAndPlay 收到 targetLabel", "重击", u.man.__lastLabel);
        assertEquals("man.__lastLabelOp = play", "play", u.man.__lastLabelOp);
        assertEquals("u.格斗架势 = true", true, u.格斗架势);
        assertEquals("man.hp 字段透传", 100, u.man.hp);
    }

    private static function testCrossContainer_MissingAbort():Void {
        trace("\n--- testCrossContainer_MissingAbort ---");
        var u = makeUnit();
        u.__stateTransitionJob = {
            arg_containerName: "不存在的连招",
            arg_targetLabel: "重击"
        };
        u.__setMissingSymbol("空手攻击容器-不存在的连招");

        var ret:Object = runCrossContainerJob(u, {});

        assertEquals("status = abort", "abort", ret.status);
        assertTrue("man = undefined", ret.man === undefined);
        assertTrue("unit.man 未设置", u.man === undefined);
        // missingSymbol 路径仍记录到 initObjectsReceived（带 missing:true 标记）
        assertEquals("history 仍记录一次", 1, u.__initObjectsReceived.length);
        assertEquals("history 标记 missing", true, u.__initObjectsReceived[0].missing);
        // 没走到 bindContainerEndState / gotoAndPlay，u.格斗架势 不应被设置
        assertEquals("格斗架势 未被设置", false, u.格斗架势);
    }

    private static function testCrossContainer_BindContainerEndStateOnRemove():Void {
        trace("\n--- testCrossContainer_BindContainerEndStateOnRemove ---");
        var u = makeUnit();
        u.__stateTransitionJob = {
            arg_containerName: "1连招",
            arg_targetLabel: "1连招"
        };
        var ret:Object = runCrossContainerJob(u, {});

        // 触发 man 卸载 — 模拟容器动画完毕或 gotoAndStop 跳出容器帧
        ret.man.removeMovieClip();

        assertEquals("UpdateBigSmallState 被触发", 1, u.__spy_bigStateCount);
        assertEquals("big = BIG_END_PUNCH",
            RoutingIntent.BIG_END_PUNCH, u.__spy_bigStateLastBig);
        assertEquals("small = SMALL_END_BAREHAND",
            RoutingIntent.SMALL_END_BAREHAND, u.__spy_bigStateLastSmall);
    }

    private static function testCrossContainer_JobParamsPassthrough():Void {
        trace("\n--- testCrossContainer_JobParamsPassthrough ---");
        var u = makeUnit();
        u.__stateTransitionJob = {
            arg_containerName: "鹰拳",
            arg_targetLabel: "鹰拳3连"
        };
        var ret:Object = runCrossContainerJob(u, {flag: 1});

        // 验证 job.arg_containerName 走到了 linkage 拼接
        assertEquals("linkage 含 containerName",
            "空手攻击容器-鹰拳", u.__initObjectsReceived[0].linkage);
        // 验证 job.arg_targetLabel 走到了 gotoAndPlay
        assertEquals("man 跳到 targetLabel", "鹰拳3连", u.man.__lastLabel);
    }

    private static function testCrossContainer_SecondJumpReplacesPriorMan():Void {
        trace("\n--- testCrossContainer_SecondJumpReplacesPriorMan ---");
        var u = makeUnit();

        // 第一次跨容器跳转
        u.__stateTransitionJob = {arg_containerName: "1连招", arg_targetLabel: "1连"};
        var first:Object = runCrossContainerJob(u, {round: 1});
        var firstMan = first.man;

        // 模拟 firstMan 上的额外 onUnload 副作用（用户业务代码可能挂载）
        var firstUnloadFires:Number = 0;
        var prevOnUnload:Function = firstMan.onUnload;
        firstMan.onUnload = function() {
            if (prevOnUnload != undefined) prevOnUnload.apply(this);
            firstUnloadFires++;
        };

        // 第二次跨容器跳转（同名 attachMovie，按 MockMovieClip 语义：旧 man 先 remove
        // → onUnload 触发 → 再 attach 新 man）
        u.__stateTransitionJob = {arg_containerName: "2连招", arg_targetLabel: "2连"};
        var second:Object = runCrossContainerJob(u, {round: 2});
        var secondMan = second.man;

        assertEquals("status = ok", "ok", second.status);
        assertTrue("first man 已 removed", firstMan.__removed);
        assertEquals("first 的 onUnload 触发 1 次", 1, firstUnloadFires);
        assertEquals("first 的 bindContainerEndState 也被触发",
            1, u.__spy_bigStateCount);
        assertTrue("second man 是新对象", secondMan !== firstMan);
        assertEquals("u.man === secondMan", secondMan, u.man);
        assertEquals("secondMan.__lastLabel = 2连", "2连", secondMan.__lastLabel);
        assertEquals("secondMan.round = 2", 2, secondMan.round);
    }
}