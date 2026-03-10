import org.flashNight.gesh.string.StringUtils;

/**
 * StringUtils 全覆盖测试套件
 * 
 * 启动方式（复制到 TestLoader.as）：
 *   import org.flashNight.gesh.string.StringUtilsFullTest;
 *   var tester = new StringUtilsFullTest();
 *   tester.run();
 * 
 * 日志输出示例：
 *   ===== StringUtilsFullTest =====
 *   [PERF] Baseline: str.length=142ms, length(str)=74ms (1.92x)
 *   
 *   [FUNC] Running tests...
 *   [FUNC] 20/20 tests passed
 *   
 *   [PERF] Method performance (20000 ops):
 *     trim: 458ms
 *     endsWith: 52ms
 *     replaceAll: 210ms
 *     reverse: 352ms
 *   
 *   [SUMMARY] 20/20 PASS
 *   ===== Test Complete =====
 */
class org.flashNight.gesh.string.StringUtilsFullTest {
    
    private static var PERF_ITERATIONS = 100000;
    private static var METHOD_ITERATIONS = 20000;
    
    private var pass = 0;
    private var fail = 0;
    
    public function StringUtilsFullTest() {}
    
    public function run():Void {
        trace("===== StringUtilsFullTest =====");
        
        this.baselineTest();
        this.functionTests();
        this.performanceTests();
        
        trace("");
        trace("[SUMMARY] " + this.pass + "/" + (this.pass + this.fail) + " PASS");
        trace("===== Test Complete =====");
    }
    
    private function baselineTest():Void {
        var s = "Hello, World! This is a test string.";
        var i;
        var d = 0;
        
        for (i = 0; i < 5000; i++) { d = s.length; d = length(s); }
        
        var t1 = getTimer();
        for (i = 0; i < PERF_ITERATIONS; i++) { d = s.length; }
        t1 = getTimer() - t1;
        
        var t2 = getTimer();
        for (i = 0; i < PERF_ITERATIONS; i++) { d = length(s); }
        t2 = getTimer() - t2;
        
        trace("[PERF] Baseline: str.length=" + t1 + "ms, length(str)=" + t2 + "ms (" + Math.round((t1/t2)*100)/100 + "x)");
    }
    
    private function functionTests():Void {
        trace("");
        trace("[FUNC] Running tests...");
        
        this.test("includes", StringUtils.includes("hello", "ll"), true);
        this.test("startsWith", StringUtils.startsWith("abc", "a"), true);
        this.test("endsWith", StringUtils.endsWith("abc", "c"), true);
        this.test("isEmpty", StringUtils.isEmpty("   "), true);
        this.test("count", StringUtils.countOccurrences("banana", "a"), 3);
        this.test("trim", StringUtils.trim("  hello  "), "hello");
        this.test("trimLeft", StringUtils.trimLeft("  hello  "), "hello  ");
        this.test("trimRight", StringUtils.trimRight("  hello  "), "  hello");
        this.test("padStart", StringUtils.padStart("5", 3, "0"), "005");
        this.test("padEnd", StringUtils.padEnd("5", 3, "0"), "500");
        this.test("repeat", StringUtils.repeat("ab", 3), "ababab");
        this.test("replaceAll", StringUtils.replaceAll("hello", "l", "x"), "hexxo");
        this.test("reverse", StringUtils.reverse("abc"), "cba");
        this.test("capitalize", StringUtils.capitalize("hello"), "Hello");
        this.test("remove", StringUtils.remove("banana", "a"), "bnn");
        this.test("escapeHTML", StringUtils.escapeHTML("<div>"), "&lt;div&gt;");
        this.test("unescapeHTML", StringUtils.unescapeHTML("&lt;div&gt;"), "<div>");
        this.test("decodeHTMLFast", StringUtils.decodeHTMLFast("&lt;&gt;"), "<>");
        this.test("toFixed", StringUtils.toFixed(3.14159, 2), "3.14");
        this.test("formatNumber", StringUtils.formatNumber(1234567, ",", "."), "1,234,567");
        
        trace("[FUNC] " + this.pass + "/" + (this.pass + this.fail) + " tests passed");
    }
    
    private function performanceTests():Void {
        trace("");
        trace("[PERF] Method performance (" + METHOD_ITERATIONS + " ops):");
        
        var ts = "   Hello World   ";
        var i;
        var st, et;
        
        st = getTimer();
        for (i = 0; i < METHOD_ITERATIONS; i++) StringUtils.trim(ts);
        et = getTimer();
        trace("  trim: " + (et-st) + "ms");
        
        st = getTimer();
        for (i = 0; i < METHOD_ITERATIONS; i++) StringUtils.endsWith(ts, "ld");
        et = getTimer();
        trace("  endsWith: " + (et-st) + "ms");
        
        st = getTimer();
        for (i = 0; i < METHOD_ITERATIONS; i++) StringUtils.replaceAll(ts, "l", "x");
        et = getTimer();
        trace("  replaceAll: " + (et-st) + "ms");
        
        st = getTimer();
        for (i = 0; i < METHOD_ITERATIONS; i++) StringUtils.reverse(ts);
        et = getTimer();
        trace("  reverse: " + (et-st) + "ms");
    }
    
    private function test(name, actual, expected):Void {
        if (actual === expected) this.pass++;
        else { this.fail++; trace("[FAIL] " + name); }
    }
}
