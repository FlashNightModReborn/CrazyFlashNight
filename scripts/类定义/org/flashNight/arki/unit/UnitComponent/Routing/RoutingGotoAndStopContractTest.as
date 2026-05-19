import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * RoutingGotoAndStopContractTest — III.4 gotoAndStop 强契约 mock 双层 token
 *
 * 契约 §1 决议：分两层上下文
 *   (a) 旧帧 owned context (man / container / 旧帧闭包) — poison
 *   (b) 新帧/状态机 executor 内 post-goto self method 调用 — 放过
 *
 * 实现机制：frameEpoch / contextToken
 *   - MockMovieClip.gotoAndStop 时 __frameEpoch++
 *   - MockMovieClip.__requireCurrentEpoch(mc, token) 反向断言 helper
 *
 * 覆盖：
 *   - 基础：gotoAndStop bumps frameEpoch；post-goto self method 不带 epoch token 调用合法
 *   - 反向：业务代码显式 snapshot epoch + post-goto check → token 失效
 *   - 端到端：StateTransition.apply 整套 (snapshot → build → executor → gotoAndStop →
 *     post-goto self method × 2 → executeStateTransitionJob → cb(unit)) → frameEpoch+1，
 *     executor 内调用合规
 *   - callback 闭包内捕获预 gotoAndStop snapshot → 反向断言 FAIL
 *   - detached mc：epoch 检查也 FAIL
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingGotoAndStopContractTest {

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
        trace("Routing GotoAndStop Contract Test Suite (III.4)");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        RoutingRuntime.clearAttachMovieAdapterForTest();

        // 基础：frameEpoch + post-goto self method
        testFrameEpoch_BumpsOnGotoAndStop();
        testFrameEpoch_PostGotoSelfMethodOk();

        // requireCurrentEpoch helper
        testRequireCurrentEpoch_PassBeforeGoto();
        testRequireCurrentEpoch_FailAfterGoto();
        testRequireCurrentEpoch_FailOnDetached();
        testRequireCurrentEpoch_FailOnUndefined();
        testRequireCurrentEpoch_FailOnNonMockObject();

        // 反向断言：业务代码持有 oldEpoch token
        testBizCode_PreservesEpochSnapshot_InvalidAfterGoto();
        testBizCode_OldManRef_DetachedAfterRemove();

        // 端到端：StateTransition.apply
        testStateTransitionApply_BumpsFrameEpoch();
        testStateTransitionApply_PostGotoExecutorCallsValid();
        testStateTransitionApply_JobCallbackInvoked();
        testStateTransitionApply_CallbackOldEpochSnapshot_InvalidInsideCallback();

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

    /**
     * Hero unit（控制目标），具备 StateTransition.apply 端到端所需的全部 method spy。
     * 用 MockMovieClip 作 base，让 gotoAndStop 真正走 frameEpoch++。
     */
    private static function makeHeroUnit() {
        var u:MockMovieClip = new MockMovieClip();
        u.__name = "hero";
        u._name = "hero";
        u.兵种 = "杂兵";
        u.状态 = undefined;
        u.旧状态 = undefined;
        u.攻击模式 = "空手";
        u.__stateGotoLabel = undefined;
        u.__stateTransitionJob = undefined;
        u.man = undefined;
        u.飞行浮空 = undefined;
        u.__spy_read_count = 0;
        u.__spy_store_count = 0;
        u.__spy_store_last = undefined;
        u.读取当前飞行状态 = function() {
            this.__spy_read_count++;
        };
        u.存储当前飞行状态 = function(reason) {
            this.__spy_store_count++;
            this.__spy_store_last = reason;
        };
        return u;
    }

    // ════════════════════════════════════════════════════════════════════
    // 基础 frameEpoch
    // ════════════════════════════════════════════════════════════════════

    private static function testFrameEpoch_BumpsOnGotoAndStop():Void {
        trace("\n--- testFrameEpoch_BumpsOnGotoAndStop ---");
        var u:MockMovieClip = new MockMovieClip();
        assertEquals("初始 frameEpoch=0", 0, u.__frameEpoch);
        u.gotoAndStop("A");
        assertEquals("第 1 次 goto → epoch=1", 1, u.__frameEpoch);
        u.gotoAndStop("B");
        assertEquals("第 2 次 goto → epoch=2", 2, u.__frameEpoch);
        u.gotoAndStop("C");
        assertEquals("第 3 次 goto → epoch=3", 3, u.__frameEpoch);
    }

    private static function testFrameEpoch_PostGotoSelfMethodOk():Void {
        trace("\n--- testFrameEpoch_PostGotoSelfMethodOk ---");
        var u:MockMovieClip = new MockMovieClip();
        u.__spy_count = 0;
        u.doWork = function() { this.__spy_count++; };

        u.gotoAndStop("frame-X");
        // §1 决议：post-goto self method 调用合法（不带 epoch token，不被 poison）
        u.doWork();
        u.doWork();
        assertEquals("post-goto self method 可正常调", 2, u.__spy_count);
    }

    // ════════════════════════════════════════════════════════════════════
    // requireCurrentEpoch helper
    // ════════════════════════════════════════════════════════════════════

    private static function testRequireCurrentEpoch_PassBeforeGoto():Void {
        trace("\n--- testRequireCurrentEpoch_PassBeforeGoto ---");
        var u:MockMovieClip = new MockMovieClip();
        var token:Number = u.__frameEpoch;
        assertTrue("无 goto 之间 → token 仍有效",
            MockMovieClip.__requireCurrentEpoch(u, token));
    }

    private static function testRequireCurrentEpoch_FailAfterGoto():Void {
        trace("\n--- testRequireCurrentEpoch_FailAfterGoto ---");
        var u:MockMovieClip = new MockMovieClip();
        var token:Number = u.__frameEpoch;
        u.gotoAndStop("X");
        assertFalse("gotoAndStop 之后 → token 失效",
            MockMovieClip.__requireCurrentEpoch(u, token));
    }

    private static function testRequireCurrentEpoch_FailOnDetached():Void {
        trace("\n--- testRequireCurrentEpoch_FailOnDetached ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        var token:Number = child.__frameEpoch;
        child.removeMovieClip();
        assertFalse("detached mc → token FAIL",
            MockMovieClip.__requireCurrentEpoch(child, token));
    }

    private static function testRequireCurrentEpoch_FailOnUndefined():Void {
        trace("\n--- testRequireCurrentEpoch_FailOnUndefined ---");
        assertFalse("undefined ref → FAIL",
            MockMovieClip.__requireCurrentEpoch(undefined, 0));
    }

    private static function testRequireCurrentEpoch_FailOnNonMockObject():Void {
        trace("\n--- testRequireCurrentEpoch_FailOnNonMockObject ---");
        // 普通 Object 无 __frameEpoch 字段
        assertFalse("非 MockMovieClip 对象 → FAIL",
            MockMovieClip.__requireCurrentEpoch({foo: "bar"}, 0));
    }

    // ════════════════════════════════════════════════════════════════════
    // 反向断言：业务代码持有 oldEpoch token
    // ════════════════════════════════════════════════════════════════════

    private static function testBizCode_PreservesEpochSnapshot_InvalidAfterGoto():Void {
        trace("\n--- testBizCode_PreservesEpochSnapshot_InvalidAfterGoto ---");
        // 业务场景：旧帧脚本拿到 self 引用 + snapshot epoch token，
        // 中间调用 gotoAndStop，此后再用旧 token 验证应失败 — 提示业务代码不能跨 goto 引用
        var self:MockMovieClip = new MockMovieClip();
        var oldEpoch:Number = self.__frameEpoch;
        self.gotoAndStop("new-frame");
        // 模拟业务代码若在 gotoAndStop 之后 (旧帧闭包内) 又走老引用：
        assertFalse("oldEpoch 之后 goto → 反向断言失败",
            MockMovieClip.__requireCurrentEpoch(self, oldEpoch));
        // 同样 self 用当前 epoch 仍有效（证明 self 没被 poison，只是 token 失效）
        assertTrue("current epoch 仍有效",
            MockMovieClip.__requireCurrentEpoch(self, self.__frameEpoch));
    }

    private static function testBizCode_OldManRef_DetachedAfterRemove():Void {
        trace("\n--- testBizCode_OldManRef_DetachedAfterRemove ---");
        // 业务场景：旧 man 被 removeMovieClip，业务代码若仍持有旧 man 引用 → epoch check FAIL
        var unit:MockMovieClip = new MockMovieClip();
        var oldMan = unit.attachMovie("Lp", "man", 0, {});
        var oldManEpoch:Number = oldMan.__frameEpoch;
        // 模拟 StateTransition.apply removeDynamicMan 路径
        unit.man.removeMovieClip();
        // 业务代码若用 oldMan 引用 + oldManEpoch → 反向断言失败
        assertFalse("removed oldMan + oldManEpoch → FAIL",
            MockMovieClip.__requireCurrentEpoch(oldMan, oldManEpoch));
    }

    // ════════════════════════════════════════════════════════════════════
    // 端到端：StateTransition.apply
    // ════════════════════════════════════════════════════════════════════

    private static function testStateTransitionApply_BumpsFrameEpoch():Void {
        trace("\n--- testStateTransitionApply_BumpsFrameEpoch ---");
        var u = makeHeroUnit();
        u.状态 = "站立";
        var epochBefore:Number = u.__frameEpoch;
        StateTransition.apply(u, "兵器攻击");
        // 兵器攻击 → 走 transition 分支 → self.gotoAndStop 调用 → frameEpoch++
        assertEquals("frameEpoch 增 1", epochBefore + 1, u.__frameEpoch);
        assertEquals("lastLabel 是 plan.gotoLabel", "兵器攻击", u.__lastLabel);
        assertEquals("lastLabelOp = stop", "stop", u.__lastLabelOp);
    }

    private static function testStateTransitionApply_PostGotoExecutorCallsValid():Void {
        trace("\n--- testStateTransitionApply_PostGotoExecutorCallsValid ---");
        // §1 决议：apply 内 gotoAndStop 之后调用 self.读取当前飞行状态 + executeStateTransitionJob
        // 这些是 executor 上下文（不带 epoch token），应当正常执行
        var u = makeHeroUnit();
        u.状态 = "站立";
        StateTransition.apply(u, "兵器攻击");
        // self.读取当前飞行状态() 是 apply 内 gotoAndStop 之后调用的 self method
        assertEquals("post-goto self.读取当前飞行状态 被调", 1, u.__spy_read_count);
    }

    private static function testStateTransitionApply_JobCallbackInvoked():Void {
        trace("\n--- testStateTransitionApply_JobCallbackInvoked ---");
        var u = makeHeroUnit();
        u.状态 = "站立";

        // producer 写 job —— 此处直接构造（生产路径走 RoutingIntent.triggerStateTransitionJob）
        var cbHits:Number = 0;
        var cbReceivedUnit:Object = undefined;
        u.__stateTransitionJob = {
            gotoLabel: "兵器攻击容器",
            callback: function(unitArg) {
                cbHits++;
                cbReceivedUnit = unitArg;
            }
        };

        StateTransition.apply(u, "兵器攻击");
        assertEquals("callback 触发 1 次", 1, cbHits);
        assertEquals("callback 接到 unit", u, cbReceivedUnit);
    }

    private static function testStateTransitionApply_CallbackOldEpochSnapshot_InvalidInsideCallback():Void {
        trace("\n--- testStateTransitionApply_CallbackOldEpochSnapshot_InvalidInsideCallback ---");
        // 反向断言：若 callback 闭包捕获了"调 apply 之前"的 epoch snapshot，
        // 进入 callback 时 epoch 已 ++（gotoAndStop 已发生）→ epoch check 失败
        // 这是 §1 设计的"业务代码若错误地从旧帧闭包持有引用"的反向断言
        var u = makeHeroUnit();
        u.状态 = "站立";

        // 旧帧业务代码 snapshot（预 gotoAndStop）
        var snapshottedEpoch:Number = u.__frameEpoch;

        var checkResultInCallback:Boolean;
        u.__stateTransitionJob = {
            gotoLabel: "兵器攻击容器",
            callback: function(unitArg) {
                // callback 在 gotoAndStop 之后执行 — 这里用旧 snapshottedEpoch 反向断言
                checkResultInCallback = MockMovieClip.__requireCurrentEpoch(unitArg, snapshottedEpoch);
            }
        };

        StateTransition.apply(u, "兵器攻击");
        // 反向断言：snapshot 早于 apply 内 gotoAndStop → callback 内 check 应 FAIL
        assertFalse("callback 内旧 epoch token 反向断言 FAIL", checkResultInCallback);
        // 同时验证：callback 用 unitArg.__frameEpoch 自取的当前 token 仍有效
        assertTrue("callback 内用当前 epoch 仍有效",
            MockMovieClip.__requireCurrentEpoch(u, u.__frameEpoch));
    }
}