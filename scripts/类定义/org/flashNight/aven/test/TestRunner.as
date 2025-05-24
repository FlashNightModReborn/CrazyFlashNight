import org.flashNight.aven.test.TestSuite;
import org.flashNight.aven.test.TestCase;
import org.flashNight.aven.test.TestConfig;
import org.flashNight.aven.test.TestReporter;
import org.flashNight.aven.test.Assertions;
import org.flashNight.aven.test.TestUtils;

class org.flashNight.aven.test.TestRunner {
    private var suites:Array;
    private var config:TestConfig;
    private var reporter:TestReporter;

    public function TestRunner(config:TestConfig, reporter:TestReporter) {
        this.suites = [];
        this.config = config;
        this.reporter = reporter;
    }

    public function addSuite(suite:TestSuite):Void {
        this.suites.push(suite);
    }

    public function run():Void {
        for (var i:Number = 0; i < this.suites.length; i++) {
            var suite:TestSuite = this.suites[i];
            this.reporter.startSuite(suite.getName());
            var testCases:Array = suite.getTestCases();
            for (var j:Number = 0; j < testCases.length; j++) {
                var testCase:TestCase = testCases[j];
                if (this.config.shouldSkipTest(testCase)) {
                    this.reporter.skipTest(testCase.getDescription());
                    continue;
                }
                for (var r:Number = 0; r < this.config.getRepeat(); r++) {
                    var runDescription:String = testCase.getDescription() + " (Run " + (r + 1) + ")";
                    this.reporter.startTest(runDescription);
                    var startTime:Number = getTimer();
                    try {
                        var result:Object = testCase.getTestFunction().call(null, testCase.getInput());
                        var endTime:Number = getTimer();
                        Assertions.assertEquals(testCase.getExpected(), result, testCase.getDescription());
                        this.reporter.passTest(runDescription, endTime - startTime);
                    } catch (error:Error) {
                        var endTimeFail:Number = getTimer();
                        this.reporter.failTest(runDescription, endTimeFail - startTime, error);
                        if (this.config.isDebug()) {
                            throw error; // 如果需要调试，重新抛出错误
                        }
                    }
                }
            }
            this.reporter.endSuite(suite.getName());
        }
        this.reporter.generateReport();
    }
}
