import org.flashNight.arki.render.RayVfxManager;
import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;

/**
 * RayVfxManager 射线段延迟策略回归测试
 * @class RayVfxManagerTest
 * @package org.flashNight.arki.render
 *
 * 覆盖：
 * - chain 分段延迟
 * - fork 统一 1 帧延迟
 * - chainDelay=0 的退化行为
 */
class org.flashNight.arki.render.RayVfxManagerTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    private static function assertEqualsNumber(expected:Number, actual:Number, message:String):Void {
        testsRun++;
        if (Math.abs(expected - actual) < 0.0001) {
            testsPassed++;
            trace("[PASS] " + message);
        } else {
            testsFailed++;
            trace("[FAIL] " + message + " expected=" + expected + " actual=" + actual);
        }
    }

    private static function test_chainDelay():Void {
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 2;

        assertEqualsNumber(
            0,
            RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "chain", hitIndex: 0}),
            "chain 主命中不延迟"
        );

        assertEqualsNumber(
            6,
            RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "chain", hitIndex: 3}),
            "chain 延迟=hitIndex*chainDelay"
        );
    }

    private static function test_forkDelay():Void {
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 3;

        assertEqualsNumber(
            1,
            RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "fork", hitIndex: 0}),
            "fork 第一条折射统一延迟 1 帧"
        );

        assertEqualsNumber(
            1,
            RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "fork", hitIndex: 5}),
            "fork 其他折射统一延迟 1 帧"
        );
    }

    private static function test_disableDelay():Void {
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 0;

        assertEqualsNumber(
            0,
            RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "chain", hitIndex: 2}),
            "chainDelay=0 时 chain 不延迟"
        );

        assertEqualsNumber(
            0,
            RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "fork", hitIndex: 0}),
            "chainDelay=0 时 fork 不延迟"
        );

        assertEqualsNumber(
            0,
            RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "pierce", hitIndex: 0}),
            "pierce 不延迟"
        );
    }

    public static function runAllTests():Void {
        testsRun = 0;
        testsPassed = 0;
        testsFailed = 0;

        trace("===== RayVfxManagerTest 开始 =====");
        test_chainDelay();
        test_forkDelay();
        test_disableDelay();
        trace("===== RayVfxManagerTest 结束: run=" + testsRun + ", pass=" + testsPassed + ", fail=" + testsFailed + " =====");
    }

    public static function main():Void {
        runAllTests();
    }
}
