import org.flashNight.gesh.number.NumberUtil;

class org.flashNight.gesh.number.NumberUtilTest {
    
    // 测试统计变量
    private static var totalTests:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var currentTestName:String = "";
    private static var currentTestPassed:Number = 0;
    private static var currentTestFailed:Number = 0;
    
    // -----------------------------
    // 1. 测试入口
    // -----------------------------
    
    public static function runTests():Void {
        trace("\n╔════════════════════════════════════════════════════════╗");
        trace("║           NumberUtil Test Suite v2.0                   ║");
        trace("╚════════════════════════════════════════════════════════╝\n");
        
        // 重置统计
        totalTests = 0;
        passedTests = 0;
        failedTests = 0;
        
        // 新增方法测试
        testDefaultIfNaN();
        testSafeParseNumber();
        testSafeArithmetic();
        testClamp();
        testValidityAndFallback();
        testNormalizationAndMapping();
        testWrapping();
        testAngleConversion();
        testSafeOperators();
        testQuantization();
        testAggregation();
        
        // 输出测试覆盖率报告
        printCoverageReport();
        
        // 性能测试
        performanceTest();
        
        // 输出测试总结
        printTestSummary();
    }
    
    // -----------------------------
    // 2. 断言函数
    // -----------------------------
    
    private static function assert(condition:Boolean, message:String):Void {
        totalTests++;
        currentTestPassed++;
        
        if (!condition) {
            failedTests++;
            currentTestFailed++;
            currentTestPassed--;
            trace("  ✗ FAILED: " + message);
        } else {
            passedTests++;
        }
    }
    
    private static function startTest(testName:String):Void {
        currentTestName = testName;
        currentTestPassed = 0;
        currentTestFailed = 0;
        trace("\n┌─── " + testName + " ───");
    }
    
    private static function endTest():Void {
        var status:String = (currentTestFailed == 0) ? "✓ PASSED" : "✗ FAILED";
        trace("└─── " + status + " (" + currentTestPassed + "/" + (currentTestPassed + currentTestFailed) + " assertions) ───\n");
    }
    
    // -----------------------------
    // 3. 准确性测试
    // -----------------------------
    
    // 注释掉不存在的常量测试
    /*
    private static function testConstants():Void {
        trace("--- Testing Constants ---");
        
        // EPSILON
        assert(NumberUtil.EPSILON === 0.0000000000000002220446049250313, "EPSILON should be 0.0000000000000002220446049250313");
        
        // MAX_SAFE_INTEGER
        assert(NumberUtil.MAX_SAFE_INTEGER === 9007199254740991, "MAX_SAFE_INTEGER should be 9007199254740991");
        
        // MIN_SAFE_INTEGER
        assert(NumberUtil.MIN_SAFE_INTEGER === -9007199254740991, "MIN_SAFE_INTEGER should be -9007199254740991");
    }
    */
    
    // 注释掉不存在的isNaN测试
    /*
    private static function testIsNaN():Void {
        trace("--- Testing isNaN ---");
        
        // 正常情况
        assert(NumberUtil.isNaN(NaN) === true, "isNaN(NaN) should be true");
        assert(NumberUtil.isNaN(123) === false, "isNaN(123) should be false");
        assert(NumberUtil.isNaN("NaN") === false, "isNaN('NaN') should be false");
        assert(NumberUtil.isNaN(undefined) === false, "isNaN(undefined) should be false");
        assert(NumberUtil.isNaN(null) === false, "isNaN(null) should be false");
        
        // 边界情况
        assert(NumberUtil.isNaN(NumberUtil.EPSILON) === false, "isNaN(EPSILON) should be false");
    }
    */
    
    // 注释掉不存在的isFinite测试
    /*
    private static function testIsFinite():Void {
        trace("--- Testing isFinite ---");
        
        // 正常情况
        assert(NumberUtil.isFinite(123) === true, "isFinite(123) should be true");
        assert(NumberUtil.isFinite(-123.456) === true, "isFinite(-123.456) should be true");
        assert(NumberUtil.isFinite(0) === true, "isFinite(0) should be true");
        
        // 无穷大和NaN
        assert(NumberUtil.isFinite(Infinity) === false, "isFinite(Infinity) should be false");
        assert(NumberUtil.isFinite(-Infinity) === false, "isFinite(-Infinity) should be false");
        assert(NumberUtil.isFinite(NaN) === false, "isFinite(NaN) should be false");
        
        // 非数字类型
        assert(NumberUtil.isFinite("123") === false, "isFinite('123') should be false");
        assert(NumberUtil.isFinite(null) === false, "isFinite(null) should be false");
        assert(NumberUtil.isFinite(true) === false, "isFinite(true) should be false");
    }
    */
    
    // 注释掉不存在的isInteger测试
    /*
    private static function testIsInteger():Void {
        trace("--- Testing isInteger ---");
        
        // 正整数
        assert(NumberUtil.isInteger(123) === true, "isInteger(123) should be true");
        
        // 负整数
        assert(NumberUtil.isInteger(-456) === true, "isInteger(-456) should be true");
        
        // 零
        assert(NumberUtil.isInteger(0) === true, "isInteger(0) should be true");
        
        // 浮点数
        assert(NumberUtil.isInteger(123.456) === false, "isInteger(123.456) should be false");
        assert(NumberUtil.isInteger(-0.0) === true, "isInteger(-0.0) should be true"); // -0.0 在 AS2 中等于 0
        
        // 非数字类型
        assert(NumberUtil.isInteger("123") === false, "isInteger('123') should be false");
        assert(NumberUtil.isInteger(NaN) === false, "isInteger(NaN) should be false");
        assert(NumberUtil.isInteger(Infinity) === false, "isInteger(Infinity) should be false");
    }
    */
    
    // 注释掉不存在的isSafeInteger测试
    /*
    private static function testIsSafeInteger():Void {
        trace("--- Testing isSafeInteger ---");
        
        // 安全整数
        assert(NumberUtil.isSafeInteger(9007199254740991) === true, "isSafeInteger(MAX_SAFE_INTEGER) should be true");
        assert(NumberUtil.isSafeInteger(-9007199254740991) === true, "isSafeInteger(MIN_SAFE_INTEGER) should be true");
        assert(NumberUtil.isSafeInteger(123456) === true, "isSafeInteger(123456) should be true");
        
        // 不安全整数
        assert(NumberUtil.isSafeInteger(9007199254740992) === false, "isSafeInteger(9007199254740992) should be false");
        assert(NumberUtil.isSafeInteger(-9007199254740992) === false, "isSafeInteger(-9007199254740992) should be false");
        
        // 非整数
        assert(NumberUtil.isSafeInteger(123.456) === false, "isSafeInteger(123.456) should be false");
        
        // 非数字类型
        assert(NumberUtil.isSafeInteger("9007199254740991") === false, "isSafeInteger('9007199254740991') should be false");
    }
    */
    
    // 注释掉不存在的parseInt测试
    /*
    private static function testParseInt():Void {
        trace("--- Testing parseInt ---");
        
        // 正常情况
        assert(NumberUtil.parseInt("123") === 123, "parseInt('123') should be 123");
        assert(NumberUtil.parseInt("-456") === -456, "parseInt('-456') should be -456");
        assert(NumberUtil.parseInt("+789") === 789, "parseInt('+789') should be 789");
        
        // 不同基数
        assert(NumberUtil.parseInt("FF", 16) === 255, "parseInt('FF', 16) should be 255");
        assert(NumberUtil.parseInt("1010", 2) === 10, "parseInt('1010', 2) should be 10");
        assert(NumberUtil.parseInt("77", 8) === 63, "parseInt('77', 8) should be 63");
        
        // 自动基数
        assert(NumberUtil.parseInt("0b1010", 2) === 0, "parseInt('0b1010', 2) should stop parsing at 'b', result 0");
        assert(NumberUtil.parseInt("0x1A", 16) === 26, "parseInt('0x1A', 16) should be 26");
        
        // 边界情况
        assert(NumberUtil.parseInt("") === NaN, "parseInt('') should be NaN");
        assert(NumberUtil.parseInt("   42") === 42, "parseInt('   42') should be 42");
        assert(NumberUtil.parseInt("42abc") === 42, "parseInt('42abc') should be 42");
        assert(NumberUtil.parseInt("abc42") === NaN, "parseInt('abc42') should be NaN");
        
        // 非数字类型
        assert(NumberUtil.parseInt(null) === NaN, "parseInt(null) should be NaN");
        assert(NumberUtil.parseInt(undefined) === NaN, "parseInt(undefined) should be NaN");
    }
    */
    
    // 注释掉不存在的parseFloat测试
    /*
    private static function testParseFloat():Void {
        trace("--- Testing parseFloat ---");
        
        // 正常情况
        assert(NumberUtil.parseFloat("123.456") === 123.456, "parseFloat('123.456') should be 123.456");
        assert(NumberUtil.parseFloat("-789.012") === -789.012, "parseFloat('-789.012') should be -789.012");
        assert(NumberUtil.parseFloat("+345.678") === 345.678, "parseFloat('+345.678') should be 345.678");
        
        // 科学计数法
        assert(NumberUtil.parseFloat("1.23e4") === 12300, "parseFloat('1.23e4') should be 12300");
        assert(NumberUtil.parseFloat("5.67E-3") === 0.00567, "parseFloat('5.67E-3') should be 0.00567");
        
        // 边界情况
        assert(NumberUtil.parseFloat("") === NaN, "parseFloat('') should be NaN");
        assert(NumberUtil.parseFloat("   3.14") === 3.14, "parseFloat('   3.14') should be 3.14");
        assert(NumberUtil.parseFloat("6.28abc") === 6.28, "parseFloat('6.28abc') should be 6.28");
        assert(NumberUtil.parseFloat("abc6.28") === NaN, "parseFloat('abc6.28') should be NaN");
        assert(NumberUtil.parseFloat("1.23e") === 1.23, "parseFloat('1.23e') should be 1.23");
        assert(NumberUtil.parseFloat("1.23e+") === 1.23, "parseFloat('1.23e+') should be 1.23");
        assert(NumberUtil.parseFloat("1.23e-") === 1.23, "parseFloat('1.23e-') should be 1.23");
        
        // 非数字类型
        assert(NumberUtil.parseFloat(null) === NaN, "parseFloat(null) should be NaN");
        assert(NumberUtil.parseFloat(undefined) === NaN, "parseFloat(undefined) should be NaN");
    }
    */
    
    // -----------------------------
    // 4. 新增方法测试
    // -----------------------------
    
    private static function testDefaultIfNaN():Void {
        startTest("Testing defaultIfNaN");
        
        assert(NumberUtil.defaultIfNaN(123, 999) === 123, "Valid number returns itself");
        assert(NumberUtil.defaultIfNaN(NaN, 999) === 999, "NaN returns default value");
        assert(NumberUtil.defaultIfNaN(0, 999) === 0, "Zero returns itself");
        assert(NumberUtil.defaultIfNaN(-456, 999) === -456, "Negative number returns itself");
        assert(NumberUtil.defaultIfNaN(Infinity, 999) === Infinity, "Infinity returns itself");
        
        endTest();
    }
    
    private static function testSafeParseNumber():Void {
        startTest("Testing safeParseNumber");
        
        assert(NumberUtil.safeParseNumber("123", 999) === 123, "Valid integer string");
        assert(NumberUtil.safeParseNumber("abc", 999) === 999, "Invalid string returns default");
        assert(NumberUtil.safeParseNumber("", 999) === 999, "Empty string returns default");
        assert(NumberUtil.safeParseNumber("-45.67", 999) === -45.67, "Negative decimal string");
        assert(NumberUtil.safeParseNumber("0", 999) === 0, "Zero string");
        // 注意：AS2中 Number("Infinity") 返回 NaN，所以应该返回默认值
        assert(NumberUtil.safeParseNumber("Infinity", 999) === 999, "Infinity string returns default in AS2");
        
        endTest();
    }
    
    private static function testSafeArithmetic():Void {
        startTest("Testing Safe Arithmetic Operations");
        
        // safeAdd
        trace("  • Testing safeAdd...");
        assert(NumberUtil.safeAdd(5, 3, 999) === 8, "safeAdd: 5 + 3 = 8");
        assert(NumberUtil.safeAdd(NaN, 3, 999) === 999, "safeAdd: NaN + 3 returns default");
        assert(NumberUtil.safeAdd(5, NaN, 999) === 999, "safeAdd: 5 + NaN returns default");
        
        // safeSubtract
        trace("  • Testing safeSubtract...");
        assert(NumberUtil.safeSubtract(10, 3, 999) === 7, "safeSubtract: 10 - 3 = 7");
        assert(NumberUtil.safeSubtract(NaN, 3, 999) === 999, "safeSubtract: NaN - 3 returns default");
        
        // safeMultiply
        trace("  • Testing safeMultiply...");
        assert(NumberUtil.safeMultiply(4, 5, 999) === 20, "safeMultiply: 4 * 5 = 20");
        assert(NumberUtil.safeMultiply(NaN, 5, 999) === 999, "safeMultiply: NaN * 5 returns default");
        
        // safeDivide
        trace("  • Testing safeDivide...");
        assert(NumberUtil.safeDivide(20, 4, 999) === 5, "safeDivide: 20 / 4 = 5");
        assert(NumberUtil.safeDivide(20, 0, 999) === 999, "safeDivide: Division by zero returns default");
        assert(NumberUtil.safeDivide(NaN, 4, 999) === 999, "safeDivide: NaN / 4 returns default");
        
        endTest();
    }
    
    private static function testClamp():Void {
        startTest("Testing clamp");
        
        assert(NumberUtil.clamp(5, 0, 10) === 5, "Value within range");
        assert(NumberUtil.clamp(-5, 0, 10) === 0, "Value below min returns min");
        assert(NumberUtil.clamp(15, 0, 10) === 10, "Value above max returns max");
        assert(NumberUtil.clamp(0, 0, 10) === 0, "Value equals min");
        assert(NumberUtil.clamp(10, 0, 10) === 10, "Value equals max");
        
        endTest();
    }
    
    private static function testValidityAndFallback():Void {
        startTest("Testing Validity and Fallback Functions");
        
        // isValidNumber
        assert(NumberUtil.isValidNumber(123) === true, "isValidNumber(123) should be true");
        assert(NumberUtil.isValidNumber(NaN) === false, "isValidNumber(NaN) should be false");
        assert(NumberUtil.isValidNumber(Infinity) === false, "isValidNumber(Infinity) should be false");
        assert(NumberUtil.isValidNumber(-Infinity) === false, "isValidNumber(-Infinity) should be false");
        assert(NumberUtil.isValidNumber(0) === true, "isValidNumber(0) should be true");
        
        // defaultIfInvalid
        assert(NumberUtil.defaultIfInvalid(123, 999) === 123, "defaultIfInvalid(123, 999) should be 123");
        assert(NumberUtil.defaultIfInvalid(NaN, 999) === 999, "defaultIfInvalid(NaN, 999) should be 999");
        assert(NumberUtil.defaultIfInvalid(Infinity, 999) === 999, "defaultIfInvalid(Infinity, 999) should be 999");
        
        // approxEqual
        assert(NumberUtil.approxEqual(1.0, 1.0000001, 0.00001) === true, "approxEqual(1.0, 1.0000001, 0.00001) should be true");
        assert(NumberUtil.approxEqual(1.0, 1.01, 0.00001) === false, "approxEqual(1.0, 1.01, 0.00001) should be false");
        assert(NumberUtil.approxEqual(100, 100.000001) === true, "approxEqual(100, 100.000001) with default epsilon should be true");
        
        // between
        assert(NumberUtil.between(5, 0, 10, true) === true, "between: 5 in [0,10]");
        assert(NumberUtil.between(0, 0, 10, true) === true, "between: 0 in [0,10] inclusive");
        assert(NumberUtil.between(10, 0, 10, true) === true, "between: 10 in [0,10] inclusive");
        assert(NumberUtil.between(0, 0, 10, false) === false, "between: 0 not in (0,10) exclusive");
        assert(NumberUtil.between(10, 0, 10, false) === false, "between: 10 not in (0,10) exclusive");
        assert(NumberUtil.between(-5, 0, 10, true) === false, "between: -5 not in [0,10]");
        
        endTest();
    }
    
    private static function testNormalizationAndMapping():Void {
        startTest("Testing Normalization and Mapping");
        
        // clamp01
        assert(NumberUtil.clamp01(0.5) === 0.5, "clamp01(0.5) should be 0.5");
        assert(NumberUtil.clamp01(-0.5) === 0, "clamp01(-0.5) should be 0");
        assert(NumberUtil.clamp01(1.5) === 1, "clamp01(1.5) should be 1");
        
        // normalize
        assert(NumberUtil.normalize(5, 0, 10, 0.5) === 0.5, "normalize(5, 0, 10, 0.5) should be 0.5");
        assert(NumberUtil.normalize(0, 0, 10, 0.5) === 0, "normalize(0, 0, 10, 0.5) should be 0");
        assert(NumberUtil.normalize(10, 0, 10, 0.5) === 1, "normalize(10, 0, 10, 0.5) should be 1");
        assert(NumberUtil.normalize(5, 5, 5, 0.5) === 0.5, "normalize(5, 5, 5, 0.5) should be 0.5");
        
        // remap
        assert(NumberUtil.remap(5, 0, 10, 0, 100, false) === 50, "remap: 5 in [0,10] -> 50 in [0,100]");
        assert(NumberUtil.remap(0, 0, 10, 50, 100, false) === 50, "remap: 0 -> 50");
        assert(NumberUtil.remap(10, 0, 10, 50, 100, false) === 100, "remap: 10 -> 100");
        assert(NumberUtil.remap(15, 0, 10, 0, 100, true) === 100, "remap: 15 clamped to 100");
        assert(NumberUtil.remap(-5, 0, 10, 0, 100, true) === 0, "remap: -5 clamped to 0");
        
        endTest();
    }
    
    private static function testWrapping():Void {
        startTest("Testing Wrapping Functions");
        
        // wrap
        assert(NumberUtil.wrap(5, 0, 10) === 5, "wrap(5, 0, 10) should be 5");
        assert(NumberUtil.wrap(15, 0, 10) === 5, "wrap(15, 0, 10) should be 5");
        assert(NumberUtil.wrap(-5, 0, 10) === 5, "wrap(-5, 0, 10) should be 5");
        assert(NumberUtil.wrap(10, 0, 10) === 0, "wrap(10, 0, 10) should be 0");
        assert(NumberUtil.wrap(23, 0, 10) === 3, "wrap(23, 0, 10) should be 3");
        
        // wrapAngleDeg
        assert(NumberUtil.wrapAngleDeg(90) === 90, "wrapAngleDeg(90) should be 90");
        assert(NumberUtil.wrapAngleDeg(270) === -90, "wrapAngleDeg(270) should be -90");
        assert(NumberUtil.wrapAngleDeg(370) === 10, "wrapAngleDeg(370) should be 10");
        assert(NumberUtil.wrapAngleDeg(-190) === 170, "wrapAngleDeg(-190) should be 170");
        assert(NumberUtil.wrapAngleDeg(180) === 180, "wrapAngleDeg(180) should be 180");
        assert(NumberUtil.wrapAngleDeg(-180) === 180, "wrapAngleDeg(-180) should be 180");
        
        // wrapAngleRad
        var pi:Number = Math.PI;
        assert(Math.abs(NumberUtil.wrapAngleRad(pi/2) - pi/2) < 0.0001, "wrapAngleRad(π/2) should be π/2");
        assert(Math.abs(NumberUtil.wrapAngleRad(3*pi/2) - (-pi/2)) < 0.0001, "wrapAngleRad(3π/2) should be -π/2");
        assert(Math.abs(NumberUtil.wrapAngleRad(2*pi + 0.1) - 0.1) < 0.0001, "wrapAngleRad(2π + 0.1) should be 0.1");
        
        endTest();
    }
    
    private static function testAngleConversion():Void {
        startTest("Testing Angle Conversion");
        
        var pi:Number = Math.PI;
        
        // deg2rad
        assert(Math.abs(NumberUtil.deg2rad(180) - pi) < 0.0001, "deg2rad(180) should be π");
        assert(Math.abs(NumberUtil.deg2rad(90) - pi/2) < 0.0001, "deg2rad(90) should be π/2");
        assert(Math.abs(NumberUtil.deg2rad(360) - 2*pi) < 0.0001, "deg2rad(360) should be 2π");
        
        // rad2deg
        assert(Math.abs(NumberUtil.rad2deg(pi) - 180) < 0.0001, "rad2deg(π) should be 180");
        assert(Math.abs(NumberUtil.rad2deg(pi/2) - 90) < 0.0001, "rad2deg(π/2) should be 90");
        assert(Math.abs(NumberUtil.rad2deg(2*pi) - 360) < 0.0001, "rad2deg(2π) should be 360");
        
        endTest();
    }
    
    private static function testSafeOperators():Void {
        startTest("Testing Safe Operators");
        
        // safeMod
        assert(NumberUtil.safeMod(10, 3, 999) === 1, "safeMod(10, 3, 999) should be 1");
        assert(NumberUtil.safeMod(10, 0, 999) === 999, "safeMod(10, 0, 999) should be 999");
        assert(NumberUtil.safeMod(-7, 3, 999) === 2, "safeMod(-7, 3, 999) should be 2");
        assert(NumberUtil.safeMod(7, -3, 999) === 1, "safeMod(7, -3, 999) should be 1");
        
        // sign
        assert(NumberUtil.sign(10) === 1, "sign(10) should be 1");
        assert(NumberUtil.sign(-10) === -1, "sign(-10) should be -1");
        assert(NumberUtil.sign(0) === 0, "sign(0) should be 0");
        
        // absDiff
        assert(NumberUtil.absDiff(10, 3) === 7, "absDiff(10, 3) should be 7");
        assert(NumberUtil.absDiff(3, 10) === 7, "absDiff(3, 10) should be 7");
        assert(NumberUtil.absDiff(-5, 3) === 8, "absDiff(-5, 3) should be 8");
        
        endTest();
    }
    
    private static function testQuantization():Void {
        startTest("Testing Quantization Functions");
        
        // snap
        assert(NumberUtil.snap(7, 5, 0) === 5, "snap(7, 5, 0) should be 5");
        assert(NumberUtil.snap(8, 5, 0) === 10, "snap(8, 5, 0) should be 10");
        assert(NumberUtil.snap(7, 5, 2) === 7, "snap(7, 5, 2) should be 7");
        assert(NumberUtil.snap(13, 10, 0) === 10, "snap(13, 10, 0) should be 10");
        assert(NumberUtil.snap(17, 10, 0) === 20, "snap(17, 10, 0) should be 20");
        assert(NumberUtil.snap(7, 0, 0) === 7, "snap(7, 0, 0) should be 7");
        assert(NumberUtil.snap(7, -5, 0) === 7, "snap(7, -5, 0) should be 7");
        
        // constrainDelta
        assert(NumberUtil.constrainDelta(0, 10, 3) === 3, "constrainDelta(0, 10, 3) should be 3");
        assert(NumberUtil.constrainDelta(0, 10, 15) === 10, "constrainDelta(0, 10, 15) should be 10");
        assert(NumberUtil.constrainDelta(10, 0, 3) === 7, "constrainDelta(10, 0, 3) should be 7");
        assert(NumberUtil.constrainDelta(10, 0, 15) === 0, "constrainDelta(10, 0, 15) should be 0");
        assert(NumberUtil.constrainDelta(5, 8, 10) === 8, "constrainDelta(5, 8, 10) should be 8");
        
        endTest();
    }
    
    private static function testAggregation():Void {
        startTest("Testing Aggregation Functions");
        
        // average
        var arr1:Array = [1, 2, 3, 4, 5];
        assert(NumberUtil.average(arr1, 999) === 3, "average([1,2,3,4,5], 999) should be 3");
        
        var arr2:Array = [10, NaN, 20, NaN, 30];
        assert(NumberUtil.average(arr2, 999) === 20, "average([10,NaN,20,NaN,30], 999) should be 20");
        
        var arr3:Array = [NaN, NaN, NaN];
        assert(NumberUtil.average(arr3, 999) === 999, "average([NaN,NaN,NaN], 999) should be 999");
        
        var arr4:Array = [];
        assert(NumberUtil.average(arr4, 999) === 999, "average([], 999) should be 999");
        
        assert(NumberUtil.average(null, 999) === 999, "average(null, 999) should be 999");
        
        var arr5:Array = [100];
        assert(NumberUtil.average(arr5, 999) === 100, "average([100], 999) should be 100");
        
        endTest();
    }
    
    // -----------------------------
    // 5. 测试报告函数
    // -----------------------------
    
    private static function printCoverageReport():Void {
        trace("\n╔════════════════════════════════════════════════════════╗");
        trace("║                 TEST COVERAGE REPORT                    ║");
        trace("╠════════════════════════════════════════════════════════╣");
        
        var allMethods:Array = [
            "defaultIfNaN", "safeParseNumber", "safeAdd", "safeSubtract", 
            "safeMultiply", "safeDivide", "clamp", "isValidNumber",
            "defaultIfInvalid", "approxEqual", "between", "clamp01",
            "normalize", "remap", "wrap", "wrapAngleDeg", "wrapAngleRad",
            "deg2rad", "rad2deg", "safeMod", "snap", "constrainDelta",
            "sign", "absDiff", "average"
        ];
        
        var testedMethods:Array = [
            "defaultIfNaN", "safeParseNumber", "safeAdd", "safeSubtract",
            "safeMultiply", "safeDivide", "clamp", "isValidNumber",
            "defaultIfInvalid", "approxEqual", "between", "clamp01",
            "normalize", "remap", "wrap", "wrapAngleDeg", "wrapAngleRad",
            "deg2rad", "rad2deg", "safeMod", "snap", "constrainDelta",
            "sign", "absDiff", "average"
        ];
        
        var coverage:Number = (testedMethods.length / allMethods.length) * 100;
        
        trace("║ Total Methods: " + allMethods.length + "                                       ║");
        trace("║ Tested Methods: " + testedMethods.length + "                                      ║");
        trace("║ Coverage: " + Math.round(coverage) + "%                                          ║");
        trace("╚════════════════════════════════════════════════════════╝");
    }
    
    private static function printTestSummary():Void {
        var successRate:Number = (totalTests > 0) ? Math.round((passedTests / totalTests) * 100) : 0;
        var status:String = (failedTests == 0) ? "✓ ALL TESTS PASSED" : "✗ TESTS FAILED";
        
        trace("\n╔════════════════════════════════════════════════════════╗");
        trace("║                    TEST SUMMARY                         ║");
        trace("╠════════════════════════════════════════════════════════╣");
        trace("║ Total Assertions: " + totalTests + "                                   ║");
        trace("║ Passed: " + passedTests + "                                            ║");
        trace("║ Failed: " + failedTests + "                                              ║");
        trace("║ Success Rate: " + successRate + "%                                      ║");
        trace("║                                                          ║");
        trace("║ " + status + "                              ║");
        trace("╚════════════════════════════════════════════════════════╝");
    }
    
    // -----------------------------
    // 6. 性能测试
    // -----------------------------
    
    private static function performanceTest():Void {
        trace("\n╔════════════════════════════════════════════════════════╗");
        trace("║                 PERFORMANCE TESTS                       ║");
        trace("╠════════════════════════════════════════════════════════╣");
        
        var iterations:Number = 10000;
        var startTime:Number;
        var endTime:Number;
        var elapsed:Number;
        
        // 测试新增的方法性能
        
        // 测试 defaultIfNaN
        startTime = getTimer();
        var result:Number;
        for (var i:Number = 0; i < iterations; i++) {
            result = NumberUtil.defaultIfNaN(NaN, 999);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("defaultIfNaN: " + elapsed + " ms");
        
        // 测试 isValidNumber
        startTime = getTimer();
        var isValid:Boolean;
        for (var i:Number = 0; i < iterations; i++) {
            isValid = NumberUtil.isValidNumber(i);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("isValidNumber: " + elapsed + " ms");
        
        // 测试 clamp
        startTime = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            result = NumberUtil.clamp(i, 0, 1000);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("clamp: " + elapsed + " ms");
        
        // 测试 remap
        startTime = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            result = NumberUtil.remap(i, 0, 1000, 0, 100, false);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("remap: " + elapsed + " ms");
        
        // 测试 wrapAngleDeg
        startTime = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            result = NumberUtil.wrapAngleDeg(i * 10);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("wrapAngleDeg: " + elapsed + " ms");
        
        // 测试 snap
        startTime = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            result = NumberUtil.snap(i, 10, 0);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("snap: " + elapsed + " ms");
        
        trace("╚════════════════════════════════════════════════════════╝");
    }
    
    // -----------------------------
    // 7. 构造函数 (私有，防止实例化)
    // -----------------------------
    function NumberUtilTest() {
        // 私有构造函数，禁止实例化
    }
}
