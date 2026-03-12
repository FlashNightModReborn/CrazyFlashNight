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
import org.flashNight.gesh.tooltip.test.TestDataBootstrap;

/**
 * TooltipTestSuite - 注释系统测试总入口
 */
class org.flashNight.gesh.tooltip.test.TooltipTestSuite {

    public static function runAllTests(includeBenchmarks:Boolean):Void {
        if (includeBenchmarks == undefined) includeBenchmarks = true;

        trace("========================================");
        trace(" Tooltip Test Suite ");
        trace("========================================");

        TooltipRegressionTest.runAllTests();
        TooltipConstantsTest.runAllTests();
        ItemUseTypesTest.runAllTests();
        TooltipFormatterTest.runAllTests();
        TestDataBootstrap.runIsolated(TooltipDataSelectorTest.runAllTests);
        TestDataBootstrap.runIsolated(BuilderContractTest.runAllTests);
        TooltipBridgeTest.runAllTests();
        TooltipLayoutTest.runAllTests();
        TestDataBootstrap.runIsolated(TooltipIntegrationTest.runAllTests);

        if (includeBenchmarks) {
            TestDataBootstrap.runIsolated(TooltipPerfBenchmark.runAllTests);
        }

        trace("========================================");
        trace(" Tooltip Test Suite Finished ");
        trace("========================================");
    }
}
