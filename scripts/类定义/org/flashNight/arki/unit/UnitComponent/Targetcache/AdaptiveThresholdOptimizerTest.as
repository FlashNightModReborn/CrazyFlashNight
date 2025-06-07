import org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizer;

/**
 * 测试套件：AdaptiveThresholdOptimizerTest
 * 100% 方法覆盖，内建断言，性能评估组件
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizerTest {
    public static function runAll():Void {
        trace("=== AdaptiveThresholdOptimizer Tests Start ===");
        testInitialize();
        testValidateParams();
        testSetAndGetParams();
        testApplyPreset();
        testThresholdBounds();
        testUpdateThreshold();
        testCalculateRecommendedThreshold();
        testAnalyzeDistribution();
        testResetMethods();
        performanceTest();
        trace("=== All Tests Passed ===");
    }

    private static function assertEquals(desc:String, expected:Number, actual:Number):Void {
        if (expected !== actual) {
            throw new Error(desc + " fail: expected=" + expected + ", actual=" + actual);
        }
    }

    private static function assertTrue(desc:String, cond:Boolean):Void {
        if (!cond) {
            throw new Error(desc + " fail: condition is false");
        }
    }

    private static function testInitialize():Void {
        // 静态初始化会自动调用initialize()
        var before:Number = AdaptiveThresholdOptimizer.getThreshold();
        assertTrue("Initial threshold in bounds", before >= AdaptiveThresholdOptimizer.getParams().minThreshold && before <= AdaptiveThresholdOptimizer.getParams().maxThreshold);
    }

    private static function testValidateParams():Void {
        // 强制设置非法参数后验证修正
        AdaptiveThresholdOptimizer.setParams( -1, -5, -10, -20);
        var p:Object = AdaptiveThresholdOptimizer.getParams();
        assertTrue("Alpha reset to default", p.alpha > 0 && p.alpha <= 1);
        assertTrue("DensityFactor > 0", p.densityFactor > 0);
        assertTrue("minThreshold > 0", p.minThreshold > 0);
        assertTrue("maxThreshold > minThreshold", p.maxThreshold > p.minThreshold);
    }

    private static function testSetAndGetParams():Void {
        var ok:Boolean = AdaptiveThresholdOptimizer.setParams(0.5, 2.5, 20, 200);
        assertTrue("setParams returns true on valid", ok);
        var p:Object = AdaptiveThresholdOptimizer.getParams();
        assertEquals("alpha matches", 0.5, p.alpha);
        assertEquals("densityFactor matches", 2.5, p.densityFactor);
        assertEquals("minThreshold matches", 20, p.minThreshold);
        assertEquals("maxThreshold matches", 200, p.maxThreshold);
    }

    private static function testApplyPreset():Void {
        assertTrue("applyPreset dense", AdaptiveThresholdOptimizer.applyPreset("dense"));
        var pd:Object = AdaptiveThresholdOptimizer.getParams();
        assertEquals("dense densityFactor", 2.0, pd.densityFactor);
        assertTrue("applyPreset invalid returns false", !AdaptiveThresholdOptimizer.applyPreset("unknown"));
    }

    private static function testThresholdBounds():Void {
        // 测试applyThresholdBounds间接通过calculateRecommendedThreshold
        var arr:Array = [0, 1, 2];
        var rec:Number = AdaptiveThresholdOptimizer.calculateRecommendedThreshold(arr);
        var p:Object = AdaptiveThresholdOptimizer.getParams();
        assertTrue("recommended within bounds", rec >= p.minThreshold && rec <= p.maxThreshold);
    }

    private static function testUpdateThreshold():Void {
        var original:Number = AdaptiveThresholdOptimizer.getThreshold();
        // 使用已知分布[0,10,20,...]
        var vals:Array = [];
        for (var i:Number = 0; i < 5; i++) { vals.push(i * 10); }
        var updated:Number = AdaptiveThresholdOptimizer.updateThreshold(vals);
        assertTrue("threshold updated or unchanged", updated >= AdaptiveThresholdOptimizer.getParams().minThreshold);
        assertTrue("avgDensity adjusted", AdaptiveThresholdOptimizer.getAvgDensity() > 0);
    }

    private static function testCalculateRecommendedThreshold():Void {
        var sample:Array = [0, 50, 100];
        var rec1:Number = AdaptiveThresholdOptimizer.calculateRecommendedThreshold(sample);
        var rec2:Number = AdaptiveThresholdOptimizer.calculateRecommendedThreshold(sample);
        assertEquals("recommend deterministic", rec1, rec2);
    }

    private static function testAnalyzeDistribution():Void {
        var sample:Array = [0, 100, 200];
        var report:Object = AdaptiveThresholdOptimizer.analyzeDistribution(sample);
        assertTrue("analyzeDistribution returns proper object", report.hasOwnProperty("suggestion"));
        assertTrue("differencePercent non-negative", report.differencePercent >= 0);
    }

    private static function testResetMethods():Void {
        AdaptiveThresholdOptimizer.setParams(0.4, 2.2, 15, 250);
        AdaptiveThresholdOptimizer.reset();
        var p:Object = AdaptiveThresholdOptimizer.getParams();
        assertEquals("reset alpha default", 0.2, p.alpha);
        assertEquals("reset densityFactor default", 3.0, p.densityFactor);
        AdaptiveThresholdOptimizer.resetAvgDensity(300);
        assertEquals("resetAvgDensity custom", 300, AdaptiveThresholdOptimizer.getAvgDensity());
    }

    private static function performanceTest():Void {
        // 性能评估：多次调用updateThreshold测量耗时
        var trials:Number = 1000;
        var data:Array = [];
        for (var i:Number = 0; i < 100; i++) { data.push(Math.random() * 500); }
        var start:Number = getTimer();
        for (var j:Number = 0; j < trials; j++) {
            AdaptiveThresholdOptimizer.updateThreshold(data);
        }
        var duration:Number = getTimer() - start;
        trace("[Performance] updateThreshold x" + trials + " took " + duration + "ms");
        // 基本断言：单次调用应小于1ms
        assertTrue("performance per call <1ms", duration / trials < 1);
    }
}
