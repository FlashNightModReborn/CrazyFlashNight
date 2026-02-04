import org.flashNight.neur.PerformanceOptimizer.test.IntervalSamplerTest;
import org.flashNight.neur.PerformanceOptimizer.test.AdaptiveKalmanStageTest;
import org.flashNight.neur.PerformanceOptimizer.test.HysteresisQuantizerTest;
import org.flashNight.neur.PerformanceOptimizer.test.PerformanceActuatorTest;
import org.flashNight.neur.PerformanceOptimizer.test.FPSVisualizationTest;
import org.flashNight.neur.PerformanceOptimizer.test.PerformanceSchedulerTest;

/**
 * PerformanceOptimizerTestSuite — 性能调度系统全局测试入口
 *
 * 一句话启动全部测试:
 *   trace(org.flashNight.neur.PerformanceOptimizer.test.PerformanceOptimizerTestSuite.run());
 *
 * 功能:
 *   - 依次执行所有子模块的测试套件
 *   - 统计每个套件的通过/失败数与耗时
 *   - 输出汇总报告（总通过数、总失败数、总耗时）
 *   - 任何失败项会在最后列出，便于快速定位
 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceOptimizerTestSuite {

    // ===== 统计状态 =====
    private static var _totalPass:Number;
    private static var _totalFail:Number;
    private static var _totalTime:Number;
    private static var _failures:Array;

    /**
     * 一句话启动全部测试
     * @return String 完整的测试报告
     */
    public static function run():String {
        _totalPass = 0;
        _totalFail = 0;
        _totalTime = 0;
        _failures = [];

        var report:String = "";
        report += "╔══════════════════════════════════════════════════╗\n";
        report += "║   PerformanceOptimizer Test Suite                ║\n";
        report += "╚══════════════════════════════════════════════════╝\n\n";

        // ── 依次执行各子套件 ──
        report += _runSuite("IntervalSampler",       IntervalSamplerTest);
        report += _runSuite("AdaptiveKalmanStage",   AdaptiveKalmanStageTest);
        report += _runSuite("HysteresisQuantizer",   HysteresisQuantizerTest);
        report += _runSuite("PerformanceActuator",   PerformanceActuatorTest);
        report += _runSuite("FPSVisualization",      FPSVisualizationTest);
        report += _runSuite("PerformanceScheduler",  PerformanceSchedulerTest);

        // ── 汇总 ──
        report += "══════════════════════════════════════════════════\n";

        var total:Number = _totalPass + _totalFail;
        var allPassed:Boolean = (_totalFail == 0);

        report += (allPassed ? "ALL PASSED" : "FAILURES DETECTED") + "\n";
        report += "  Total : " + total + "  |  ";
        report += "Pass : " + _totalPass + "  |  ";
        report += "Fail : " + _totalFail + "  |  ";
        report += "Time : " + _totalTime + " ms\n";

        if (!allPassed) {
            report += "\n── Failed Items ─────────────────────────────\n";
            for (var i:Number = 0; i < _failures.length; i++) {
                report += "  " + (i + 1) + ". " + _failures[i] + "\n";
            }
        }

        report += "══════════════════════════════════════════════════\n";

        return report;
    }

    /**
     * 兼容旧接口（直接调用 run）
     */
    public static function runAllTests():String {
        return run();
    }

    // ===== 内部方法 =====

    /**
     * 执行单个子套件并收集统计数据
     * @param name 套件名称
     * @param testClass 测试类（需有静态 runAllTests():String 方法）
     * @return String 该套件的报告段
     */
    private static function _runSuite(name:String, testClass:Function):String {
        var t0:Number = getTimer();
        var output:String = testClass.runAllTests();
        var elapsed:Number = getTimer() - t0;
        _totalTime += elapsed;

        // 解析通过/失败数
        var counts:Object = _countResults(output, name);
        _totalPass += counts.pass;
        _totalFail += counts.fail;

        // 构建该套件的报告头
        var suiteTotal:Number = counts.pass + counts.fail;
        var status:String = (counts.fail == 0) ? "PASS" : "FAIL";
        var header:String = "── " + name + " ── " + status +
                            " (" + counts.pass + "/" + suiteTotal + ", " + elapsed + "ms)\n";

        return header + output + "\n";
    }

    /**
     * 解析测试输出中的通过/失败标记
     * 约定: 每行含 "✓" 为通过, 含 "✗" 为失败
     * @param output 测试输出文本
     * @param suiteName 套件名（用于失败项定位）
     * @return Object {pass:Number, fail:Number}
     */
    private static function _countResults(output:String, suiteName:String):Object {
        var pass:Number = 0;
        var fail:Number = 0;

        var lines:Array = output.split("\n");
        for (var i:Number = 0; i < lines.length; i++) {
            var line:String = lines[i];
            if (_contains(line, "\u2713")) {
                // ✓ 通过
                pass++;
            } else if (_contains(line, "\u2717")) {
                // ✗ 失败
                fail++;
                // 记录失败项: [套件名] 具体描述
                var desc:String = _trim(line);
                _failures.push("[" + suiteName + "] " + desc);
            }
        }

        return { pass: pass, fail: fail };
    }

    /**
     * 字符串包含检测（AS2 无 String.indexOf 的 includes）
     */
    private static function _contains(str:String, sub:String):Boolean {
        return str.indexOf(sub) >= 0;
    }

    /**
     * 去除首尾空白
     */
    private static function _trim(str:String):String {
        var start:Number = 0;
        var end:Number = str.length - 1;
        while (start <= end && (str.charAt(start) == " " || str.charAt(start) == "\t")) {
            start++;
        }
        while (end >= start && (str.charAt(end) == " " || str.charAt(end) == "\t")) {
            end--;
        }
        return str.substring(start, end + 1);
    }
}
