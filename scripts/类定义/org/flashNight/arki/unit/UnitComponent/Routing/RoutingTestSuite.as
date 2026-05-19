import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * Routing Test Suite Aggregator
 *
 * 串联 Routing/* 模块的 11 个独立测试套件，统一打印聚合 sentinel。
 * 调用方（scripts/TestLoader.as）只需一行：RoutingTestSuite.runAll();
 *
 * 套件清单（基线 614 PASS + Pre.2 RoutingRuntimeTest 增量）：
 *   1. RoutingLifecycleCoreTest
 *   2. RoutingIntentTest
 *   3. RoutingLifecycleTest
 *   4. StateTransitionCoreTest
 *   5. StateTransitionPlanTest
 *   6. StateTransitionTest
 *   7. JumpDerivePredicateTest
 *   8. JumpDerivePlanTest
 *   9. JumpDeriveActionTest
 *  10. ContainerInitScratchTest
 *  11. ContainerSpecTest
 *  12. RoutingRuntimeTest         (Pre.2 attachMovie adapter, 2026-05-19)
 *  13. ContainerAttachActionTest  (Pre.3 高层 adapter,        2026-05-19)
 *  14. MockMovieClipTest          (III.1 黑箱夹具基础类,      2026-05-19)
 *  15. RoutingEndToEndTest        (III.2 端到端组合样例,      2026-05-19)
 *  16. RoutingCrossContainerTest  (III.3 跨容器跳转端到端,    2026-05-19)
 *  17. RoutingGotoAndStopContractTest (III.4 gotoAndStop 强契约 + frameEpoch, 2026-05-19)
 *
 * Sentinel 与旧入口一致：
 *   - 全 PASS → [TEST_PASS] Routing suites
 *   - 任一 FAIL → [TEST_FAIL] Routing suites
 *
 * 后续 Pre.3 / III.x 新增的套件（ContainerAttachAction / MockMovieClip 等）
 * 在此处追加 runAll() 一行即可，TestLoader.as 不需再改动。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingTestSuite {

    public static function runAll():Boolean {
        var t0:Number = getTimer();

        var ok:Boolean = true;
        ok = RoutingLifecycleCoreTest.runAll()   && ok;
        ok = RoutingIntentTest.runAll()          && ok;
        ok = RoutingLifecycleTest.runAll()       && ok;
        ok = StateTransitionCoreTest.runAll()    && ok;
        ok = StateTransitionPlanTest.runAll()    && ok;
        ok = StateTransitionTest.runAll()        && ok;
        ok = JumpDerivePredicateTest.runAll()    && ok;
        ok = JumpDerivePlanTest.runAll()         && ok;
        ok = JumpDeriveActionTest.runAll()       && ok;
        ok = ContainerInitScratchTest.runAll()   && ok;
        ok = ContainerSpecTest.runAll()          && ok;
        ok = RoutingRuntimeTest.runAll()         && ok;
        ok = ContainerAttachActionTest.runAll()  && ok;
        ok = MockMovieClipTest.runAll()          && ok;
        ok = RoutingEndToEndTest.runAll()        && ok;
        ok = RoutingCrossContainerTest.runAll()  && ok;
        ok = RoutingGotoAndStopContractTest.runAll() && ok;

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Routing Test Suite Aggregator - elapsed " + elapsed + "ms");
        trace("================================================================");
        if (ok) {
            trace("[TEST_PASS] Routing suites");
        } else {
            trace("[TEST_FAIL] Routing suites");
        }
        return ok;
    }
}