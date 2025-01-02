import org.flashNight.gesh.number.NumberUtil;

class org.flashNight.gesh.number.NumberUtilTest {
    
    // -----------------------------
    // 1. 测试入口
    // -----------------------------
    
    public static function runTests():Void {
        trace("=== NumberUtil Test Suite Start ===");
        
        // 准确性测试
        testConstants();
        testIsNaN();
        testIsFinite();
        testIsInteger();
        testIsSafeInteger();
        testParseInt();
        testParseFloat();
        
        // 性能测试
        performanceTest();
        
        trace("=== NumberUtil Test Suite End ===");
    }
    
    // -----------------------------
    // 2. 断言函数
    // -----------------------------
    
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("Assertion Failed: " + message);
        } else {
            // Optional: Uncomment the next line to see passed assertions
            // trace("Assertion Passed: " + message);
        }
    }
    
    // -----------------------------
    // 3. 准确性测试
    // -----------------------------
    
    private static function testConstants():Void {
        trace("--- Testing Constants ---");
        
        // EPSILON
        assert(NumberUtil.EPSILON === 0.0000000000000002220446049250313, "EPSILON should be 0.0000000000000002220446049250313");
        
        // MAX_SAFE_INTEGER
        assert(NumberUtil.MAX_SAFE_INTEGER === 9007199254740991, "MAX_SAFE_INTEGER should be 9007199254740991");
        
        // MIN_SAFE_INTEGER
        assert(NumberUtil.MIN_SAFE_INTEGER === -9007199254740991, "MIN_SAFE_INTEGER should be -9007199254740991");
    }
    
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
    
    // -----------------------------
    // 4. 性能测试
    // -----------------------------
    
    private static function performanceTest():Void {
        trace("--- Starting Performance Tests ---");
        
        var iterations:Number = 100000;
        var startTime:Number;
        var endTime:Number;
        var elapsed:Number;
        
        // 测试 isNaN
        startTime = getTimer();
        var countNaN:Number = 0;
        for (var i:Number = 0; i < iterations; i++) {
            if (NumberUtil.isNaN(NaN)) {
                countNaN++;
            }
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("NumberUtil.isNaN: " + elapsed + " ms");
        
        // 测试 isFinite
        startTime = getTimer();
        var countFinite:Number = 0;
        for (var i:Number = 0; i < iterations; i++) {
            if (NumberUtil.isFinite(i)) {
                countFinite++;
            }
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("NumberUtil.isFinite: " + elapsed + " ms");
        
        // 测试 isInteger
        startTime = getTimer();
        var countInteger:Number = 0;
        for (var i:Number = 0; i < iterations; i++) {
            if (NumberUtil.isInteger(i)) {
                countInteger++;
            }
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("NumberUtil.isInteger: " + elapsed + " ms");
        
        trace("--- Testing isSafeInteger ---");

        // 1. 大步长采样
        startTime = getTimer();
        var countSafeInteger:Number = 0;
        var step:Number = 1000000000000; // 1 万亿步长
        for (var i:Number = -NumberUtil.MAX_SAFE_INTEGER; i <= NumberUtil.MAX_SAFE_INTEGER; i += step) {
            if (NumberUtil.isSafeInteger(i)) {
                countSafeInteger++;
            }
        }
        if (NumberUtil.isSafeInteger(NumberUtil.MAX_SAFE_INTEGER)) countSafeInteger++;
        if (NumberUtil.isSafeInteger(NumberUtil.MIN_SAFE_INTEGER)) countSafeInteger++;
        if (NumberUtil.isSafeInteger(0)) countSafeInteger++;
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("NumberUtil.isSafeInteger (Step Sampling): " + elapsed + " ms");

        // 2. 随机抽样
        startTime = getTimer();
        var countRandomSamples:Number = 0;
        var totalSamples:Number = 1000000; // 随机样本
        for (var j:Number = 0; j < totalSamples; j++) {
            var randSample:Number = Math.random() * (NumberUtil.MAX_SAFE_INTEGER * 2) - NumberUtil.MAX_SAFE_INTEGER;
            if (NumberUtil.isSafeInteger(randSample)) {
                countRandomSamples++;
            }
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("NumberUtil.isSafeInteger (Random Sampling): " + elapsed + " ms");

        
        // 测试 parseInt
        startTime = getTimer();
        var resultParseInt:Number;
        for (var i:Number = 0; i < iterations; i++) {
            resultParseInt = NumberUtil.parseInt("12345", 10);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("NumberUtil.parseInt: " + elapsed + " ms");
        
        // 测试 parseFloat
        startTime = getTimer();
        var resultParseFloat:Number;
        for (var i:Number = 0; i < iterations; i++) {
            resultParseFloat = NumberUtil.parseFloat("12345.6789");
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("NumberUtil.parseFloat: " + elapsed + " ms");
        
        trace("--- Performance Tests Completed ---");
    }
    
    // -----------------------------
    // 5. 构造函数 (私有，防止实例化)
    // -----------------------------
    function NumberUtilTest() {
        // 私有构造函数，禁止实例化
    }
}
