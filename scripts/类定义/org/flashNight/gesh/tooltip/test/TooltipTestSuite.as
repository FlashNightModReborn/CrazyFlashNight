import org.flashNight.gesh.tooltip.test.BuilderContractTest;
import org.flashNight.gesh.tooltip.test.ItemUseTypesTest;
import org.flashNight.gesh.tooltip.test.TooltipBridgeTest;
import org.flashNight.gesh.tooltip.test.TooltipConstantsTest;
import org.flashNight.gesh.tooltip.test.TooltipDataSelectorTest;
import org.flashNight.gesh.tooltip.test.TooltipFormatterTest;
import org.flashNight.gesh.tooltip.test.TooltipIntegrationTest;
import org.flashNight.gesh.tooltip.test.TooltipLayoutTest;
import org.flashNight.gesh.tooltip.test.TooltipPerfBenchmark;
import org.flashNight.gesh.tooltip.test.TooltipRegressionTest;
import org.flashNight.gesh.tooltip.test.SkillTooltipComposerTest;
import org.flashNight.gesh.tooltip.test.SynthesisIndexTest;
import org.flashNight.gesh.tooltip.test.UpgradePathBuilderTest;
import org.flashNight.gesh.tooltip.test.TestDataBootstrap;

/**
 * TooltipTestSuite - 注释系统测试总入口
 *
 * 提供全局统计汇总，每个子套件运行后自动收集通过/失败计数。
 */
class org.flashNight.gesh.tooltip.test.TooltipTestSuite {

    public static var totalRun:Number = 0;
    public static var totalPassed:Number = 0;
    public static var totalFailed:Number = 0;
    public static var suiteCount:Number = 0;

    public static function runAllTests(includeBenchmarks:Boolean):Void {
        if (includeBenchmarks == undefined) includeBenchmarks = true;

        totalRun = totalPassed = totalFailed = suiteCount = 0;

        trace("========================================");
        trace(" Tooltip Test Suite ");
        trace("========================================");

        TooltipRegressionTest.runAllTests();
        collectStats(TooltipRegressionTest);
        TooltipConstantsTest.runAllTests();
        collectStats(TooltipConstantsTest);
        ItemUseTypesTest.runAllTests();
        collectStats(ItemUseTypesTest);
        TooltipFormatterTest.runAllTests();
        collectStats(TooltipFormatterTest);
        TestDataBootstrap.runIsolated(TooltipDataSelectorTest.runAllTests);
        collectStats(TooltipDataSelectorTest);
        TestDataBootstrap.runIsolated(BuilderContractTest.runAllTests);
        collectStats(BuilderContractTest);
        TooltipBridgeTest.runAllTests();
        collectStats(TooltipBridgeTest);
        TooltipLayoutTest.runAllTests();
        collectStats(TooltipLayoutTest);
        TestDataBootstrap.runIsolated(TooltipIntegrationTest.runAllTests);
        collectStats(TooltipIntegrationTest);
        SkillTooltipComposerTest.runAllTests();
        collectStats(SkillTooltipComposerTest);
        SynthesisIndexTest.runAllTests();
        collectStats(SynthesisIndexTest);
        UpgradePathBuilderTest.runAllTests();
        collectStats(UpgradePathBuilderTest);

        if (includeBenchmarks) {
            TestDataBootstrap.runIsolated(TooltipPerfBenchmark.runAllTests);
            collectStats(TooltipPerfBenchmark);
        }

        trace("========================================");
        if (totalFailed > 0) {
            trace(" FAILED: " + totalPassed + "/" + totalRun + " passed, " + totalFailed + " failed (" + suiteCount + " suites)");
        } else {
            trace(" ALL PASSED: " + totalPassed + "/" + totalRun + " (" + suiteCount + " suites)");
        }
        trace("========================================");
    }

    /**
     * 从子测试类收集统计。
     * 约定：每个子类暴露 testsRun/testsPassed/testsFailed 静态变量。
     */
    private static function collectStats(testClass:Function):Void {
        totalRun += testClass.testsRun;
        totalPassed += testClass.testsPassed;
        totalFailed += testClass.testsFailed;
        suiteCount++;
    }
}
