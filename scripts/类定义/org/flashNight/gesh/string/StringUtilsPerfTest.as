import org.flashNight.gesh.string.StringUtils;

/**
 * StringUtils 性能测试套件
 * 
 * 启动方式（复制到 TestLoader.as）：
 *   import org.flashNight.gesh.string.StringUtilsPerfTest;
 *   var tester = new StringUtilsPerfTest();
 *   tester.run();
 * 
 * 典型日志输出：
 *   ===== StringUtilsPerfTest =====
 *   >>> Baseline: str.length
 *   Time: 140ms for 100000 ops
 *   >>> Optimized: length(str)
 *   Time: 76ms for 100000 ops
 *   >>> Speedup: 1.84x
 *   
 *   >>> Function Tests
 *   (3/3 PASS)
 *   
 *   >>> Method Performance
 *   trim: 459ms (20000 ops)
 *   endsWith: 51ms (20000 ops)
 *   
 *   ===== Test Complete =====
 */
class org.flashNight.gesh.string.StringUtilsPerfTest {
    
    private static var BASELINE_ITERATIONS = 100000;
    private static var METHOD_ITERATIONS = 20000;
    private static var TEST_STRING = "Hello, World! This is a test string.";
    private static var TRIM_STRING = "   Test String   ";
    
    private var passCount = 0;
    private var failCount = 0;
    
    public function StringUtilsPerfTest() {}
    
    public function run():Void {
        trace("===== StringUtilsPerfTest =====");
        
        this.runBaselineTest();
        this.runFunctionTests();
        this.runPerformanceTests();
        
        trace("");
        trace("===== Test Complete =====");
    }
    
    private function runBaselineTest():Void {
        var i;
        var startTime;
        var endTime;
        var dummy = 0;
        
        // 预热
        for (i = 0; i < 5000; i++) {
            dummy = TEST_STRING.length;
            dummy = length(TEST_STRING);
        }
        
        trace(">>> Baseline: str.length");
        startTime = getTimer();
        for (i = 0; i < BASELINE_ITERATIONS; i++) {
            dummy = TEST_STRING.length;
        }
        endTime = getTimer();
        var timeOld = endTime - startTime;
        trace("Time: " + timeOld + "ms for " + BASELINE_ITERATIONS + " ops");
        
        trace(">>> Optimized: length(str)");
        startTime = getTimer();
        for (i = 0; i < BASELINE_ITERATIONS; i++) {
            dummy = length(TEST_STRING);
        }
        endTime = getTimer();
        var timeNew = endTime - startTime;
        trace("Time: " + timeNew + "ms for " + BASELINE_ITERATIONS + " ops");
        
        var speedup = timeOld / timeNew;
        trace(">>> Speedup: " + Math.round(speedup * 100) / 100 + "x");
    }
    
    private function runFunctionTests():Void {
        trace("");
        trace(">>> Function Tests");
        
        var r1 = StringUtils.trim("  hello  ");
        if (r1 == "hello") this.passCount++; else this.failCount++;
        
        var r2 = StringUtils.startsWith("abc", "a");
        if (r2) this.passCount++; else this.failCount++;
        
        var r3 = StringUtils.endsWith("abc", "c");
        if (r3) this.passCount++; else this.failCount++;
        
        trace("(" + this.passCount + "/" + (this.passCount + this.failCount) + " PASS)");
    }
    
    private function runPerformanceTests():Void {
        trace("");
        trace(">>> Method Performance");
        
        var i;
        var startTime;
        var endTime;
        
        startTime = getTimer();
        for (i = 0; i < METHOD_ITERATIONS; i++) {
            StringUtils.trim(TRIM_STRING);
        }
        endTime = getTimer();
        trace("trim: " + (endTime - startTime) + "ms (" + METHOD_ITERATIONS + " ops)");
        
        startTime = getTimer();
        for (i = 0; i < METHOD_ITERATIONS; i++) {
            StringUtils.endsWith(TRIM_STRING, "ing");
        }
        endTime = getTimer();
        trace("endsWith: " + (endTime - startTime) + "ms (" + METHOD_ITERATIONS + " ops)");
    }
}
