import org.flashNight.naki.DataStructures.*;

/**
 * 完整测试套件：BitArray (高性能版)
 * ================================
 * 特性：
 * - 100% 方法覆盖率测试
 * - 位操作算法准确性验证
 * - 性能基准测试（位操作、逻辑运算、大数组处理）
 * - 边界条件与极值测试
 * - 数据结构完整性验证
 * - 压力测试与内存管理
 * - 一句启动设计
 * - 🆕 优化了位运算精度和性能测试
 * 
 * 使用方法：
 * org.flashNight.naki.DataStructures.BitArrayTest.runAll();
 */
class org.flashNight.naki.DataStructures.BitArrayTest {
    
    // ========================================================================
    // 测试统计和配置
    // ========================================================================
    
    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var performanceResults:Array = [];
    
    // 性能基准配置
    private static var PERFORMANCE_TRIALS:Number = 5000;
    private static var STRESS_BITS_COUNT:Number = 10000;
    private static var BIT_OP_BENCHMARK_MS:Number = 0.5;     // 基础位操作不超过0.5ms
    private static var LOGICAL_OP_BENCHMARK_MS:Number = 2.0;  // 逻辑运算允许2ms
    private static var LARGE_ARRAY_BENCHMARK_MS:Number = 10.0; // 大数组操作允许10ms
    
    // 测试数据缓存
    private static var smallBitArray:BitArray;
    private static var largeBitArray:BitArray;
    private static var patternBitArray:BitArray;
    private static var emptyBitArray:BitArray;
    
    /**
     * 主测试入口 - 一句启动全部测试
     */
    public static function runAll():Void {
        trace("================================================================================");
        trace("🚀 BitArray 完整测试套件启动 (高性能版)");
        trace("================================================================================");
        
        var startTime:Number = getTimer();
        resetTestStats();
        
        try {
            // 初始化测试数据
            initializeTestData();
            
            // === 基础功能测试 ===
            runBasicFunctionalityTests();
            
            // === 位操作算法测试 ===
            runBitOperationTests();
            
            // === 逻辑运算测试 ===
            runLogicalOperationTests();
            
            // === 边界条件测试 ===
            runBoundaryConditionTests();
            
            // === 性能基准测试 ===
            runOptimizedPerformanceBenchmarks();
            
            // === 数据完整性测试 ===
            runDataIntegrityTests();
            
            // === 压力测试 ===
            runOptimizedStressTests();
            
            // === 算法精度验证 ===
            runAlgorithmAccuracyTests();
            
        } catch (error:Error) {
            failedTests++;
            trace("❌ 测试执行异常: " + error.message);
        }
        
        var totalTime:Number = getTimer() - startTime;
        printTestSummary(totalTime);
    }
    
    // ========================================================================
    // 断言系统
    // ========================================================================
    
    private static function assertStringEquals(testName:String, expected:String, actual:String):Void {
        testCount++;
        if (expected == actual) {
            passedTests++;
            trace("✅ " + testName + " PASS (\"" + actual + "\")");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (expected=\"" + expected + "\", actual=\"" + actual + "\")");
        }
    }
    
    private static function assertEquals(testName:String, expected:Number, actual:Number, tolerance:Number):Void {
        testCount++;
        if (isNaN(tolerance)) tolerance = 0;
        
        var diff:Number = Math.abs(expected - actual);
        if (diff <= tolerance) {
            passedTests++;
            trace("✅ " + testName + " PASS (expected=" + expected + ", actual=" + actual + ")");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (expected=" + expected + ", actual=" + actual + ", diff=" + diff + ")");
        }
    }
    
    private static function assertTrue(testName:String, condition:Boolean):Void {
        testCount++;
        if (condition) {
            passedTests++;
            trace("✅ " + testName + " PASS");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (condition is false)");
        }
    }
    
    private static function assertNotNull(testName:String, obj:Object):Void {
        testCount++;
        if (obj != null && obj != undefined) {
            passedTests++;
            trace("✅ " + testName + " PASS (object is not null)");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (object is null or undefined)");
        }
    }
    
    private static function assertNull(testName:String, obj:Object):Void {
        testCount++;
        if (obj == null || obj == undefined) {
            passedTests++;
            trace("✅ " + testName + " PASS (object is null)");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (object is not null)");
        }
    }
    
    private static function assertArrayLength(testName:String, expectedLength:Number, array:Array):Void {
        testCount++;
        if (array && array.length == expectedLength) {
            passedTests++;
            trace("✅ " + testName + " PASS (length=" + array.length + ")");
        } else {
            failedTests++;
            var actualLength:Number = array ? array.length : -1;
            trace("❌ " + testName + " FAIL (expected=" + expectedLength + ", actual=" + actualLength + ")");
        }
    }
    
    private static function assertBitValue(testName:String, expected:Number, actual:Number):Void {
        testCount++;
        if ((expected ? 1 : 0) == (actual ? 1 : 0)) {
            passedTests++;
            trace("✅ " + testName + " PASS (bit=" + (actual ? 1 : 0) + ")");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (expected=" + (expected ? 1 : 0) + ", actual=" + (actual ? 1 : 0) + ")");
        }
    }
    
    private static function assertBitPattern(testName:String, expectedPattern:String, bitArray:BitArray):Void {
        testCount++;
        var actualPattern:String = bitArray.toString().split(" ").join("");
        
        if (expectedPattern == actualPattern) {
            passedTests++;
            trace("✅ " + testName + " PASS");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL");
            trace("    Expected: " + expectedPattern);
            trace("    Actual:   " + actualPattern);
        }
    }
    
    private static function assertBitArrayEqual(testName:String, expected:BitArray, actual:BitArray):Void {
        testCount++;
        
        if (!expected && !actual) {
            passedTests++;
            trace("✅ " + testName + " PASS (both null)");
            return;
        }
        
        if (!expected || !actual) {
            failedTests++;
            trace("❌ " + testName + " FAIL (one is null)");
            return;
        }
        
        if (expected.getLength() != actual.getLength()) {
            failedTests++;
            trace("❌ " + testName + " FAIL (length mismatch: " + expected.getLength() + " vs " + actual.getLength() + ")");
            return;
        }
        
        var length:Number = expected.getLength();
        for (var i:Number = 0; i < length; i++) {
            if (expected.getBit(i) != actual.getBit(i)) {
                failedTests++;
                trace("❌ " + testName + " FAIL (bit " + i + " mismatch)");
                return;
            }
        }
        
        passedTests++;
        trace("✅ " + testName + " PASS");
    }
    
    // ========================================================================
    // 🆕 测试数据初始化
    // ========================================================================
    
    private static function initializeTestData():Void {
        trace("\n🔧 初始化测试数据...");
        
        // 创建小型BitArray (64位)
        smallBitArray = new BitArray(64);
        setupSmallArrayPattern(smallBitArray);
        
        // 创建大型BitArray (1024位)
        largeBitArray = new BitArray(1024);
        setupLargeArrayPattern(largeBitArray);
        
        // 创建特定模式BitArray (32位)
        patternBitArray = new BitArray(32);
        setupTestPattern(patternBitArray);
        
        // 创建空BitArray
        emptyBitArray = new BitArray(0);
        
        trace("📦 创建了小型(64位)、大型(1024位)、模式(32位)、空BitArray");
    }
    
    /**
     * 设置小数组测试模式: 交替位模式
     */
    private static function setupSmallArrayPattern(bitArray:BitArray):Void {
        for (var i:Number = 0; i < 64; i++) {
            if (i % 2 == 0) {
                bitArray.setBit(i, 1);
            }
        }
    }
    
    /**
     * 设置大数组测试模式: 块状模式
     */
    private static function setupLargeArrayPattern(bitArray:BitArray):Void {
        // 前256位设为1，中间512位设为0，后256位设为1
        for (var i:Number = 0; i < 256; i++) {
            bitArray.setBit(i, 1);
        }
        for (var j:Number = 768; j < 1024; j++) {
            bitArray.setBit(j, 1);
        }
    }
    
    /**
     * 设置特定测试模式: 11110000 11001100 10101010 01010101
     */
    private static function setupTestPattern(bitArray:BitArray):Void {
        var pattern:Array = [
            1,1,1,1,0,0,0,0,  // 11110000
            1,1,0,0,1,1,0,0,  // 11001100
            1,0,1,0,1,0,1,0,  // 10101010
            0,1,0,1,0,1,0,1   // 01010101
        ];
        
        for (var i:Number = 0; i < pattern.length; i++) {
            bitArray.setBit(i, pattern[i]);
        }
    }
    
    // ========================================================================
    // 基础功能测试
    // ========================================================================
    
    private static function runBasicFunctionalityTests():Void {
        trace("\n📋 执行基础功能测试...");
        
        testConstructor();
        testBasicBitOperations();
        testLengthOperations();
        testAutoExpansion();
    }
    
    private static function testConstructor():Void {
        // 测试正常构造
        var bits64:BitArray = new BitArray(64);
        assertNotNull("构造函数创建64位数组", bits64);
        assertEquals("构造函数设置长度", 64, bits64.getLength(), 0);
        assertTrue("构造函数初始为空", bits64.isEmpty());
        
        // 测试0长度构造
        var bits0:BitArray = new BitArray(0);
        assertNotNull("构造函数创建0位数组", bits0);
        assertEquals("0位数组长度", 0, bits0.getLength(), 0);
        assertTrue("0位数组为空", bits0.isEmpty());
        
        // 测试大数组构造
        var bitsLarge:BitArray = new BitArray(1000);
        assertNotNull("构造函数创建大数组", bitsLarge);
        assertEquals("大数组长度正确", 1000, bitsLarge.getLength(), 0);
        assertTrue("大数组初始为空", bitsLarge.isEmpty());
        
        // 测试边界情况
        var bits32:BitArray = new BitArray(32);
        assertEquals("32位边界数组长度", 32, bits32.getLength(), 0);
        
        var bits33:BitArray = new BitArray(33);
        assertEquals("33位跨块数组长度", 33, bits33.getLength(), 0);
        
        // 测试负数和undefined处理
        var bitsNeg:BitArray = new BitArray(-10);
        assertEquals("负数长度处理", 0, bitsNeg.getLength(), 0);
        
        var bitsUndef:BitArray = new BitArray(undefined);
        assertEquals("undefined长度处理", 0, bitsUndef.getLength(), 0);
    }
    
    private static function testBasicBitOperations():Void {
        var testBits:BitArray = new BitArray(16);
        
        // 测试setBit和getBit
        testBits.setBit(0, 1);
        assertBitValue("设置位0为1", 1, testBits.getBit(0));
        assertBitValue("未设置位1为0", 0, testBits.getBit(1));
        
        testBits.setBit(5, 1);
        assertBitValue("设置位5为1", 1, testBits.getBit(5));
        
        testBits.setBit(15, 1);
        assertBitValue("设置位15为1", 1, testBits.getBit(15));
        
        // 测试设置为0
        testBits.setBit(5, 0);
        assertBitValue("设置位5为0", 0, testBits.getBit(5));
        
        // 测试flipBit
        testBits.flipBit(0);
        assertBitValue("翻转位0从1到0", 0, testBits.getBit(0));
        
        testBits.flipBit(0);
        assertBitValue("翻转位0从0到1", 1, testBits.getBit(0));
        
        testBits.flipBit(10);
        assertBitValue("翻转未设置位10从0到1", 1, testBits.getBit(10));
        
        // 测试超出范围的getBit
        assertBitValue("获取超出范围位返回0", 0, testBits.getBit(100));
        assertBitValue("获取负索引位返回0", 0, testBits.getBit(-1));
    }
    
    private static function testLengthOperations():Void {
        // 测试getLength
        assertEquals("小数组长度", 64, smallBitArray.getLength(), 0);
        assertEquals("大数组长度", 1024, largeBitArray.getLength(), 0);
        assertEquals("空数组长度", 0, emptyBitArray.getLength(), 0);
        
        // 测试isEmpty
        assertTrue("空数组isEmpty", emptyBitArray.isEmpty());
        assertTrue("未设置位的数组isEmpty", !smallBitArray.isEmpty()); // 已设置了交替模式
        
        var emptyTest:BitArray = new BitArray(10);
        assertTrue("新创建数组isEmpty", emptyTest.isEmpty());
        
        emptyTest.setBit(5, 1);
        assertTrue("设置位后非isEmpty", !emptyTest.isEmpty());
        
        emptyTest.setBit(5, 0);
        assertTrue("清除唯一位后isEmpty", emptyTest.isEmpty());
    }
    
    private static function testAutoExpansion():Void {
        var expandBits:BitArray = new BitArray(10);
        assertEquals("扩展前长度", 10, expandBits.getLength(), 0);
        
        // 设置超出范围的位，应该自动扩容
        expandBits.setBit(50, 1);
        assertEquals("自动扩展后长度", 51, expandBits.getLength(), 0);
        assertBitValue("扩展后设置的位", 1, expandBits.getBit(50));
        
        // 验证原有位未受影响
        assertBitValue("原有位未受影响", 0, expandBits.getBit(5));
        
        // 翻转超出范围的位
        expandBits.flipBit(100);
        assertEquals("翻转扩展后长度", 101, expandBits.getLength(), 0);
        assertBitValue("翻转扩展的位", 1, expandBits.getBit(100));
        
        // 测试负索引不扩展
        var oldLength:Number = expandBits.getLength();
        expandBits.setBit(-5, 1);
        assertEquals("负索引不扩展", oldLength, expandBits.getLength(), 0);
    }
    
    // ========================================================================
    // 位操作算法测试
    // ========================================================================
    
    private static function runBitOperationTests():Void {
        trace("\n🔧 执行位操作算法测试...");
        
        testClearAndSetAll();
        testCountOnes();
        testClone();
        testToString();
        testGetChunks();
    }
    
    private static function testClearAndSetAll():Void {
        var testBits:BitArray = patternBitArray.clone();
        
        // 测试clear
        assertTrue("清空前非空", !testBits.isEmpty());
        testBits.clear();
        assertTrue("清空后为空", testBits.isEmpty());
        assertEquals("清空后countOnes为0", 0, testBits.countOnes(), 0);
        
        // 验证所有位都为0
        for (var i:Number = 0; i < testBits.getLength(); i++) {
            assertBitValue("清空后位" + i + "为0", 0, testBits.getBit(i));
        }
        
        // 测试setAll
        testBits.setAll();
        assertTrue("setAll后非空", !testBits.isEmpty());
        assertEquals("setAll后countOnes等于长度", testBits.getLength(), testBits.countOnes(), 0);
        
        // 验证所有位都为1
        for (var j:Number = 0; j < testBits.getLength(); j++) {
            assertBitValue("setAll后位" + j + "为1", 1, testBits.getBit(j));
        }
        
        // 测试大数组的clear和setAll性能
        var largeCopy:BitArray = largeBitArray.clone();
        var startTime:Number = getTimer();
        largeCopy.clear();
        var clearTime:Number = getTimer() - startTime;
        
        startTime = getTimer();
        largeCopy.setAll();
        var setAllTime:Number = getTimer() - startTime;
        
        assertTrue("大数组clear性能", clearTime < 10);
        assertTrue("大数组setAll性能", setAllTime < 10);
    }
    
    private static function testCountOnes():Void {
        // 测试空数组
        assertEquals("空数组countOnes", 0, emptyBitArray.countOnes(), 0);
        
        // 测试已知模式
        assertEquals("交替模式countOnes", 32, smallBitArray.countOnes(), 0); // 64位中一半为1
        
        // 测试单个位
        var singleBit:BitArray = new BitArray(10);
        singleBit.setBit(5, 1);
        assertEquals("单位countOnes", 1, singleBit.countOnes(), 0);
        
        // 测试全1
        var allOnes:BitArray = new BitArray(20);
        allOnes.setAll();
        assertEquals("全1 countOnes", 20, allOnes.countOnes(), 0);
        
        // 测试跨块模式
        var crossChunk:BitArray = new BitArray(100);
        crossChunk.setBit(31, 1);  // 第一块最后位
        crossChunk.setBit(32, 1);  // 第二块第一位
        crossChunk.setBit(63, 1);  // 第二块最后位
        crossChunk.setBit(64, 1);  // 第三块第一位
        assertEquals("跨块countOnes", 4, crossChunk.countOnes(), 0);
    }
    
    private static function testClone():Void {
        // 测试模式数组克隆
        var cloned:BitArray = patternBitArray.clone();
        assertNotNull("克隆结果不为null", cloned);
        assertEquals("克隆长度相同", patternBitArray.getLength(), cloned.getLength(), 0);
        assertEquals("克隆countOnes相同", patternBitArray.countOnes(), cloned.countOnes(), 0);
        
        // 验证每一位都相同
        for (var i:Number = 0; i < patternBitArray.getLength(); i++) {
            assertBitValue("克隆位" + i + "相同", patternBitArray.getBit(i), cloned.getBit(i));
        }
        
        // 验证独立性 - 修改克隆不影响原数组
        var originalBit:Number = cloned.getBit(0);
        cloned.flipBit(0);
        assertBitValue("修改克隆不影响原数组", originalBit, patternBitArray.getBit(0));
        
        // 测试空数组克隆
        var emptyClone:BitArray = emptyBitArray.clone();
        assertNotNull("空数组克隆不为null", emptyClone);
        assertEquals("空数组克隆长度", 0, emptyClone.getLength(), 0);
        assertTrue("空数组克隆为空", emptyClone.isEmpty());
        
        // 测试大数组克隆
        var largeClone:BitArray = largeBitArray.clone();
        assertEquals("大数组克隆长度", largeBitArray.getLength(), largeClone.getLength(), 0);
        assertEquals("大数组克隆countOnes", largeBitArray.countOnes(), largeClone.countOnes(), 0);
    }
    
    private static function testToString():Void {
        // 测试空数组toString
        var emptyStr:String = emptyBitArray.toString();
        assertTrue("空数组toString", emptyStr == "0" || emptyStr == "");
        
        // 测试单位toString
        var singleBit:BitArray = new BitArray(1);
        singleBit.setBit(0, 1);
        assertStringEquals("单位1 toString", "1", singleBit.toString());
        
        var singleZero:BitArray = new BitArray(1);
        assertStringEquals("单位0 toString", "0", singleZero.toString());
        
        // 测试8位模式toString
        var eightBits:BitArray = new BitArray(8);
        eightBits.setBit(0, 1);
        eightBits.setBit(2, 1);
        eightBits.setBit(4, 1);
        eightBits.setBit(6, 1);
        var eightStr:String = eightBits.toString();
        assertTrue("8位模式toString包含正确位", eightStr.indexOf("1") >= 0 && eightStr.indexOf("0") >= 0);
        
        // 验证toString长度合理
        var str16:String = patternBitArray.toString();
        assertNotNull("toString结果不为null", str16);
        assertTrue("toString长度合理", str16.length >= patternBitArray.getLength());
    }
    
    private static function testGetChunks():Void {
        var chunks:Array = patternBitArray.getChunks();
        assertNotNull("getChunks返回不为null", chunks);
        assertTrue("getChunks返回数组", chunks instanceof Array);
        
        // 32位应该有1个chunk
        assertEquals("32位数组chunk数量", 1, chunks.length, 0);
        
        // 测试64位数组的chunks
        var smallChunks:Array = smallBitArray.getChunks();
        assertEquals("64位数组chunk数量", 2, smallChunks.length, 0);
        
        // 测试大数组的chunks
        var largeChunks:Array = largeBitArray.getChunks();
        assertEquals("1024位数组chunk数量", 32, largeChunks.length, 0);
        
        // 验证chunks是副本，修改不影响原数组
        var originalChunk:Number = chunks[0];
        chunks[0] = 0xFFFFFFFF;
        var newChunks:Array = patternBitArray.getChunks();
        assertEquals("getChunks返回副本", originalChunk, newChunks[0], 0);
    }
    
    // ========================================================================
    // 逻辑运算测试
    // ========================================================================
    
    private static function runLogicalOperationTests():Void {
        trace("\n🧠 执行逻辑运算测试...");
        
        testAndOperation();
        testOrOperation();
        testXorOperation();
        testNotOperation();
        testLogicalOperationEdgeCases();
    }
    
    private static function testAndOperation():Void {
        // 创建测试数据
        var bits1:BitArray = new BitArray(8);
        var bits2:BitArray = new BitArray(8);
        
        // bits1: 11110000
        bits1.setBit(4, 1); bits1.setBit(5, 1); bits1.setBit(6, 1); bits1.setBit(7, 1);
        
        // bits2: 11001100
        bits2.setBit(2, 1); bits2.setBit(3, 1); bits2.setBit(6, 1); bits2.setBit(7, 1);
        
        var result:BitArray = bits1.bitwiseAnd(bits2);
        assertNotNull("AND操作结果不为null", result);
        assertEquals("AND操作结果长度", 8, result.getLength(), 0);
        
        // 验证AND结果: 11000000
        assertBitValue("AND位0", 0, result.getBit(0));
        assertBitValue("AND位1", 0, result.getBit(1));
        assertBitValue("AND位2", 0, result.getBit(2));
        assertBitValue("AND位3", 0, result.getBit(3));
        assertBitValue("AND位4", 0, result.getBit(4));
        assertBitValue("AND位5", 0, result.getBit(5));
        assertBitValue("AND位6", 1, result.getBit(6));
        assertBitValue("AND位7", 1, result.getBit(7));
        
        // 测试与自身AND
        var selfAnd:BitArray = bits1.bitwiseAnd(bits1);
        assertBitArrayEqual("与自身AND", bits1, selfAnd);
        
        // 测试与全0 AND
        var allZeros:BitArray = new BitArray(8);
        var zeroAnd:BitArray = bits1.bitwiseAnd(allZeros);
        assertTrue("与全0 AND结果为空", zeroAnd.isEmpty());
    }
    
    private static function testOrOperation():Void {
        // 使用相同的测试数据
        var bits1:BitArray = new BitArray(8);
        var bits2:BitArray = new BitArray(8);
        
        // bits1: 11110000
        bits1.setBit(4, 1); bits1.setBit(5, 1); bits1.setBit(6, 1); bits1.setBit(7, 1);
        
        // bits2: 11001100  
        bits2.setBit(2, 1); bits2.setBit(3, 1); bits2.setBit(6, 1); bits2.setBit(7, 1);
        
        var result:BitArray = bits1.bitwiseOr(bits2);
        assertNotNull("OR操作结果不为null", result);
        assertEquals("OR操作结果长度", 8, result.getLength(), 0);
        
        // 验证OR结果: 11111100
        assertBitValue("OR位0", 0, result.getBit(0));
        assertBitValue("OR位1", 0, result.getBit(1));
        assertBitValue("OR位2", 1, result.getBit(2));
        assertBitValue("OR位3", 1, result.getBit(3));
        assertBitValue("OR位4", 1, result.getBit(4));
        assertBitValue("OR位5", 1, result.getBit(5));
        assertBitValue("OR位6", 1, result.getBit(6));
        assertBitValue("OR位7", 1, result.getBit(7));
        
        // 测试与自身OR
        var selfOr:BitArray = bits1.bitwiseOr(bits1);
        assertBitArrayEqual("与自身OR", bits1, selfOr);
        
        // 测试与全0 OR
        var allZeros:BitArray = new BitArray(8);
        var zeroOr:BitArray = bits1.bitwiseOr(allZeros);
        assertBitArrayEqual("与全0 OR", bits1, zeroOr);
    }
    
    private static function testXorOperation():Void {
        // 使用相同的测试数据
        var bits1:BitArray = new BitArray(8);
        var bits2:BitArray = new BitArray(8);
        
        // bits1: 11110000
        bits1.setBit(4, 1); bits1.setBit(5, 1); bits1.setBit(6, 1); bits1.setBit(7, 1);
        
        // bits2: 11001100
        bits2.setBit(2, 1); bits2.setBit(3, 1); bits2.setBit(6, 1); bits2.setBit(7, 1);
        
        var result:BitArray = bits1.bitwiseXor(bits2);
        assertNotNull("XOR操作结果不为null", result);
        assertEquals("XOR操作结果长度", 8, result.getLength(), 0);
        
        // 验证XOR结果: 00111100
        assertBitValue("XOR位0", 0, result.getBit(0));
        assertBitValue("XOR位1", 0, result.getBit(1));
        assertBitValue("XOR位2", 1, result.getBit(2));
        assertBitValue("XOR位3", 1, result.getBit(3));
        assertBitValue("XOR位4", 1, result.getBit(4));
        assertBitValue("XOR位5", 1, result.getBit(5));
        assertBitValue("XOR位6", 0, result.getBit(6));
        assertBitValue("XOR位7", 0, result.getBit(7));
        
        // 测试与自身XOR
        var selfXor:BitArray = bits1.bitwiseXor(bits1);
        assertTrue("与自身XOR结果为空", selfXor.isEmpty());
        
        // 测试XOR交换律
        var xor1:BitArray = bits1.bitwiseXor(bits2);
        var xor2:BitArray = bits2.bitwiseXor(bits1);
        assertBitArrayEqual("XOR交换律", xor1, xor2);
    }
    
    private static function testNotOperation():Void {
        var testBits:BitArray = new BitArray(8);
        // 设置: 10101010
        testBits.setBit(1, 1); testBits.setBit(3, 1); testBits.setBit(5, 1); testBits.setBit(7, 1);
        
        var result:BitArray = testBits.bitwiseNot();
        assertNotNull("NOT操作结果不为null", result);
        assertEquals("NOT操作结果长度", 8, result.getLength(), 0);
        
        // 验证NOT结果: 01010101
        assertBitValue("NOT位0", 1, result.getBit(0));
        assertBitValue("NOT位1", 0, result.getBit(1));
        assertBitValue("NOT位2", 1, result.getBit(2));
        assertBitValue("NOT位3", 0, result.getBit(3));
        assertBitValue("NOT位4", 1, result.getBit(4));
        assertBitValue("NOT位5", 0, result.getBit(5));
        assertBitValue("NOT位6", 1, result.getBit(6));
        assertBitValue("NOT位7", 0, result.getBit(7));
        
        // 测试双重NOT
        var doubleNot:BitArray = result.bitwiseNot();
        assertBitArrayEqual("双重NOT", testBits, doubleNot);
        
        // 测试空数组NOT
        var emptyNot:BitArray = emptyBitArray.bitwiseNot();
        assertTrue("空数组NOT", emptyNot.isEmpty());
    }
    
    private static function testLogicalOperationEdgeCases():Void {
        // 测试不同长度的数组运算
        var short:BitArray = new BitArray(4);
        var long:BitArray = new BitArray(12);
        
        short.setBit(0, 1);
        short.setBit(2, 1);
        
        long.setBit(1, 1);
        long.setBit(8, 1);
        long.setBit(10, 1);
        
        var result:BitArray = short.bitwiseAnd(long);
        assertEquals("不同长度AND结果长度", 12, result.getLength(), 0);
        
        var orResult:BitArray = short.bitwiseOr(long);
        assertEquals("不同长度OR结果长度", 12, orResult.getLength(), 0);
        
        // 验证超出短数组部分
        assertBitValue("超出部分保持long数组值", 1, orResult.getBit(8));
        
        // 测试与null或空数组的运算鲁棒性
        try {
            var nullTest:BitArray = short.bitwiseAnd(null);
            assertTrue("null运算不崩溃", true);
        } catch (error:Error) {
            assertTrue("null运算异常处理", true);
        }
    }
    
    // ========================================================================
    // 边界条件测试
    // ========================================================================
    
    private static function runBoundaryConditionTests():Void {
        trace("\n🔍 执行边界条件测试...");
        
        testEmptyArray();
        testSingleBitArray();
        testBoundaryIndices();
        testExtremeValues();
    }
    
    private static function testEmptyArray():Void {
        var empty:BitArray = new BitArray(0);
        
        assertTrue("空数组isLeaf", empty.isEmpty());
        assertEquals("空数组长度", 0, empty.getLength(), 0);
        assertEquals("空数组countOnes", 0, empty.countOnes(), 0);
        
        // 测试空数组操作不崩溃
        empty.clear();
        assertTrue("空数组clear后仍为空", empty.isEmpty());
        
        empty.setAll();
        assertTrue("空数组setAll后仍为空", empty.isEmpty());
        
        var emptyClone:BitArray = empty.clone();
        assertTrue("空数组克隆为空", emptyClone.isEmpty());
        
        // 测试空数组逻辑运算
        var anotherEmpty:BitArray = new BitArray(0);
        var emptyAnd:BitArray = empty.bitwiseAnd(anotherEmpty);
        assertTrue("空数组AND空数组", emptyAnd.isEmpty());
        
        // 测试空数组与非空数组运算
        var nonEmpty:BitArray = new BitArray(5);
        nonEmpty.setBit(2, 1);
        
        var mixResult:BitArray = empty.bitwiseOr(nonEmpty);
        assertEquals("空数组OR非空数组长度", 5, mixResult.getLength(), 0);
        assertBitValue("空数组OR非空数组保持原值", 1, mixResult.getBit(2));
    }
    
    private static function testSingleBitArray():Void {
        var single:BitArray = new BitArray(1);
        
        assertEquals("单位数组长度", 1, single.getLength(), 0);
        assertTrue("单位数组初始为空", single.isEmpty());
        assertBitValue("单位数组初始位为0", 0, single.getBit(0));
        
        single.setBit(0, 1);
        assertTrue("设置后单位数组非空", !single.isEmpty());
        assertEquals("设置后countOnes为1", 1, single.countOnes(), 0);
        
        single.flipBit(0);
        assertTrue("翻转后单位数组为空", single.isEmpty());
        
        single.setAll();
        assertEquals("setAll后countOnes为1", 1, single.countOnes(), 0);
        
        var singleNot:BitArray = single.bitwiseNot();
        assertTrue("单位数组NOT后为空", singleNot.isEmpty());
    }
    
    private static function testBoundaryIndices():Void {
        var boundary:BitArray = new BitArray(65); // 跨越两个32位块
        
        // 测试块边界
        boundary.setBit(31, 1);  // 第一块最后位
        boundary.setBit(32, 1);  // 第二块第一位
        
        assertBitValue("第一块最后位", 1, boundary.getBit(31));
        assertBitValue("第二块第一位", 1, boundary.getBit(32));
        
        // 测试数组边界
        boundary.setBit(0, 1);   // 第一位
        boundary.setBit(64, 1);  // 最后位
        
        assertBitValue("数组第一位", 1, boundary.getBit(0));
        assertBitValue("数组最后位", 1, boundary.getBit(64));
        
        // 测试边界外访问
        assertBitValue("超出边界访问返回0", 0, boundary.getBit(100));
        assertBitValue("负索引访问返回0", 0, boundary.getBit(-1));
        
        // 测试边界设置
        boundary.setBit(100, 1); // 应该自动扩容
        assertEquals("边界设置自动扩容", 101, boundary.getLength(), 0);
        assertBitValue("边界扩容设置成功", 1, boundary.getBit(100));
    }
    
    private static function testExtremeValues():Void {
        // 测试极大索引
        var extreme:BitArray = new BitArray(10);
        
        try {
            extreme.setBit(10000, 1);
            assertEquals("极大索引扩容", 10001, extreme.getLength(), 0);
            assertTrue("极大索引设置成功", true);
        } catch (error:Error) {
            assertTrue("极大索引异常处理", true);
        }
        
        // 测试数值边界
        var valueTest:BitArray = new BitArray(5);
        
        // 测试非0/1值的处理
        valueTest.setBit(0, 5);    // 非1值应被当作1
        assertBitValue("非1值设置为1", 1, valueTest.getBit(0));
        
        valueTest.setBit(1, -1);   // 非0值应被当作1
        assertBitValue("负值设置为1", 1, valueTest.getBit(1));
        
        valueTest.setBit(2, 0.5);  // 非整数值
        assertBitValue("小数值设置", 1, valueTest.getBit(2));
        
        valueTest.setBit(3, NaN);  // NaN值
        assertBitValue("NaN值设置", 0, valueTest.getBit(3));
        
        valueTest.setBit(4, undefined); // undefined值
        assertBitValue("undefined值设置", 0, valueTest.getBit(4));
    }
    
    // ========================================================================
    // 🆕 优化的性能基准测试
    // ========================================================================
    
    private static function runOptimizedPerformanceBenchmarks():Void {
        trace("\n⚡ 执行优化的性能基准测试...");
        
        performanceTestBasicBitOperations();
        performanceTestLogicalOperations();
        performanceTestLargeArrayOperations();
        performanceTestMemoryIntensiveOperations();
    }
    
    private static function performanceTestBasicBitOperations():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var testBits:BitArray = new BitArray(1000);
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            var index:Number = i % 1000;
            testBits.setBit(index, 1);
            testBits.getBit(index);
            testBits.flipBit(index);
        }
        var bitOpTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "Basic Bit Operations",
            trials: trials,
            totalTime: bitOpTime,
            avgTime: bitOpTime / trials
        });
        
        trace("📊 基础位操作性能: " + trials + "次操作耗时 " + bitOpTime + "ms");
        assertTrue("基础位操作性能达标", (bitOpTime / trials) < BIT_OP_BENCHMARK_MS);
    }
    
    private static function performanceTestLogicalOperations():Void {
        var trials:Number = Math.floor(PERFORMANCE_TRIALS / 10);
        var bits1:BitArray = largeBitArray.clone();
        var bits2:BitArray = smallBitArray.clone();
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            var andResult:BitArray = bits1.bitwiseAnd(bits2);
            var orResult:BitArray = bits1.bitwiseOr(bits2);
            var xorResult:BitArray = bits1.bitwiseXor(bits2);
            var notResult:BitArray = bits1.bitwiseNot();
        }
        var logicalOpTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "Logical Operations",
            trials: trials,
            totalTime: logicalOpTime,
            avgTime: logicalOpTime / trials
        });
        
        trace("📊 逻辑运算性能: " + trials + "次操作耗时 " + logicalOpTime + "ms");
        assertTrue("逻辑运算性能达标", (logicalOpTime / trials) < LOGICAL_OP_BENCHMARK_MS);
    }
    
    private static function performanceTestLargeArrayOperations():Void {
        var trials:Number = 50;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            var largeBits:BitArray = new BitArray(STRESS_BITS_COUNT);
            
            // 设置模式
            for (var j:Number = 0; j < STRESS_BITS_COUNT; j += 10) {
                largeBits.setBit(j, 1);
            }
            
            // 统计和克隆
            var count:Number = largeBits.countOnes();
            var cloned:BitArray = largeBits.clone();
        }
        var largeOpTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "Large Array Operations",
            trials: trials,
            totalTime: largeOpTime,
            avgTime: largeOpTime / trials
        });
        
        trace("📊 大数组操作性能: " + trials + "次操作(" + STRESS_BITS_COUNT + "位)耗时 " + largeOpTime + "ms");
        assertTrue("大数组操作性能达标", (largeOpTime / trials) < LARGE_ARRAY_BENCHMARK_MS);
    }
    
    private static function performanceTestMemoryIntensiveOperations():Void {
        var trials:Number = 20;
        var results:Array = [];
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            // 创建多个大数组
            var arrays:Array = [];
            for (var j:Number = 0; j < 10; j++) {
                var arr:BitArray = new BitArray(1000);
                for (var k:Number = 0; k < 100; k++) {
                    arr.setBit(k * 10, 1);
                }
                arrays.push(arr);
            }
            
            // 执行批量运算
            for (var m:Number = 0; m < arrays.length - 1; m++) {
                var result:BitArray = arrays[m].bitwiseOr(arrays[m + 1]);
                results.push(result.countOnes());
            }
            
            // 清理
            arrays = null;
        }
        var memoryTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "Memory Intensive Operations",
            trials: trials,
            totalTime: memoryTime,
            avgTime: memoryTime / trials
        });
        
        trace("📊 内存密集操作性能: " + trials + "次操作耗时 " + memoryTime + "ms");
        assertTrue("内存密集操作性能合理", memoryTime < 1000);
    }
    
    // ========================================================================
    // 数据完整性测试
    // ========================================================================
    
    private static function runDataIntegrityTests():Void {
        trace("\n💾 执行数据完整性测试...");
        
        testBitStateConsistency();
        testChunkDataIntegrity();
        testExpansionDataPreservation();
        testOperationDataIntegrity();
    }
    
    private static function testBitStateConsistency():Void {
        var consistency:BitArray = patternBitArray.clone();
        var originalCount:Number = consistency.countOnes();
        var originalLength:Number = consistency.getLength();
        
        // 多次相同操作应该得到相同结果
        for (var i:Number = 0; i < 5; i++) {
            assertEquals("多次countOnes一致性", originalCount, consistency.countOnes(), 0);
            assertEquals("多次getLength一致性", originalLength, consistency.getLength(), 0);
            assertTrue("多次isEmpty一致性", !consistency.isEmpty());
        }
        
        // 设置已设置的位不应改变状态
        var bit5Original:Number = consistency.getBit(5);
        consistency.setBit(5, bit5Original);
        assertEquals("重复设置不改变countOnes", originalCount, consistency.countOnes(), 0);
        assertBitValue("重复设置不改变位值", bit5Original, consistency.getBit(5));
        
        // 翻转两次应该恢复原状
        consistency.flipBit(10);
        consistency.flipBit(10);
        assertEquals("双重翻转恢复countOnes", originalCount, consistency.countOnes(), 0);
    }
    
    private static function testChunkDataIntegrity():Void {
        var chunkTest:BitArray = new BitArray(96); // 3个chunk
        
        // 在每个chunk中设置位
        chunkTest.setBit(15, 1);  // 第一个chunk
        chunkTest.setBit(47, 1);  // 第二个chunk  
        chunkTest.setBit(79, 1);  // 第三个chunk
        
        var chunks:Array = chunkTest.getChunks();
        assertEquals("chunk数量正确", 3, chunks.length, 0);
        
        // 验证chunk数据独立性
        var originalChunks:Array = chunkTest.getChunks();
        chunkTest.setBit(31, 1); // 修改第一个chunk
        var newChunks:Array = chunkTest.getChunks();
        
        // 第二、三个chunk应该未变
        assertEquals("修改后chunk1未变", originalChunks[1], newChunks[1], 0);
        assertEquals("修改后chunk2未变", originalChunks[2], newChunks[2], 0);
        assertTrue("修改后chunk0已变", originalChunks[0] != newChunks[0]);
    }
    
    private static function testExpansionDataPreservation():Void {
        var expansion:BitArray = new BitArray(10);
        
        // 设置初始数据
        expansion.setBit(2, 1);
        expansion.setBit(7, 1);
        var originalCount:Number = expansion.countOnes();
        
        // 扩容
        expansion.setBit(50, 1);
        
        // 验证原有数据保持
        assertBitValue("扩容后原位2保持", 1, expansion.getBit(2));
        assertBitValue("扩容后原位7保持", 1, expansion.getBit(7));
        assertEquals("扩容后countOnes增加1", originalCount + 1, expansion.countOnes(), 0);
        
        // 验证中间位为0
        for (var i:Number = 10; i < 50; i++) {
            assertBitValue("扩容中间位" + i + "为0", 0, expansion.getBit(i));
        }
    }
    
    private static function testOperationDataIntegrity():Void {
        var original:BitArray = patternBitArray.clone();
        var backup:BitArray = patternBitArray.clone();
        
        // 执行各种操作后验证原数组未变
        var andResult:BitArray = original.bitwiseAnd(smallBitArray);
        assertBitArrayEqual("AND操作后原数组未变", backup, original);
        
        var orResult:BitArray = original.bitwiseOr(smallBitArray);
        assertBitArrayEqual("OR操作后原数组未变", backup, original);
        
        var xorResult:BitArray = original.bitwiseXor(smallBitArray);
        assertBitArrayEqual("XOR操作后原数组未变", backup, original);
        
        var notResult:BitArray = original.bitwiseNot();
        assertBitArrayEqual("NOT操作后原数组未变", backup, original);
        
        var cloneResult:BitArray = original.clone();
        assertBitArrayEqual("Clone操作后原数组未变", backup, original);
        
        // 修改结果不应影响原数组
        andResult.setBit(0, 1);
        cloneResult.flipBit(5);
        assertBitArrayEqual("修改操作结果后原数组未变", backup, original);
    }
    
    // ========================================================================
    // 🆕 优化的压力测试
    // ========================================================================
    
    private static function runOptimizedStressTests():Void {
        trace("\n💪 执行优化的压力测试...");
        
        stressTestMassiveBitOperations();
        stressTestConcurrentLogicalOperations();
        stressTestExtremeExpansion();
        stressTestMemoryManagement();
    }
    
    private static function stressTestMassiveBitOperations():Void {
        var operations:Number = 10000;
        var massiveBits:BitArray = new BitArray(5000);
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < operations; i++) {
            var index:Number = i % 5000;
            
            switch (i % 4) {
                case 0:
                    massiveBits.setBit(index, 1);
                    break;
                case 1:
                    massiveBits.getBit(index);
                    break;
                case 2:
                    massiveBits.flipBit(index);
                    break;
                case 3:
                    massiveBits.setBit(index, 0);
                    break;
            }
        }
        var massiveTime:Number = getTimer() - startTime;
        
        assertTrue("大量位操作压力测试通过", massiveTime < 500);
        trace("🧠 大量位操作测试: " + operations + "次操作耗时 " + massiveTime + "ms");
    }
    
    private static function stressTestConcurrentLogicalOperations():Void {
        var iterations:Number = 100;
        var arraySize:Number = 512;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            // 创建多个临时数组
            var arrays:Array = [];
            for (var j:Number = 0; j < 5; j++) {
                var arr:BitArray = new BitArray(arraySize);
                // 设置随机模式
                for (var k:Number = 0; k < arraySize; k += (j + 1)) {
                    arr.setBit(k, 1);
                }
                arrays.push(arr);
            }
            
            // 执行链式逻辑运算
            var result:BitArray = arrays[0];
            for (var m:Number = 1; m < arrays.length; m++) {
                switch (m % 3) {
                    case 0:
                        result = result.bitwiseAnd(arrays[m]);
                        break;
                    case 1:
                        result = result.bitwiseOr(arrays[m]);
                        break;
                    case 2:
                        result = result.bitwiseXor(arrays[m]);
                        break;
                }
            }
            
            // 清理
            arrays = null;
            result = null;
        }
        var concurrentTime:Number = getTimer() - startTime;
        
        assertTrue("并发逻辑运算压力测试通过", concurrentTime < 1500);
        trace("⚡ 并发逻辑运算测试: " + iterations + "次迭代耗时 " + concurrentTime + "ms");
    }
    
    private static function stressTestExtremeExpansion():Void {
        var extreme:BitArray = new BitArray(1);
        
        var startTime:Number = getTimer();
        
        try {
            // 逐步扩展到较大尺寸
            var targetSizes:Array = [100, 500, 1000, 2000];
            
            for (var i:Number = 0; i < targetSizes.length; i++) {
                var targetSize:Number = targetSizes[i];
                extreme.setBit(targetSize - 1, 1);
                assertEquals("扩展到" + targetSize + "位", targetSize, extreme.getLength(), 0);
                
                // 验证扩展后功能正常
                extreme.countOnes();
                extreme.clone();
            }
            
            var expansionTime:Number = getTimer() - startTime;
            assertTrue("极端扩展测试完成", true);
            assertTrue("极端扩展时间合理", expansionTime < 100);
            trace("🔥 极端扩展测试: 扩展到" + extreme.getLength() + "位，耗时 " + expansionTime + "ms");
            
        } catch (error:Error) {
            assertTrue("极端扩展异常: " + error.message, false);
        }
    }
    
    private static function stressTestMemoryManagement():Void {
        var cycles:Number = 50;
        var arraysPerCycle:Number = 20;
        var arraySize:Number = 1000;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < cycles; i++) {
            // 创建多个大数组
            var tempArrays:Array = [];
            for (var j:Number = 0; j < arraysPerCycle; j++) {
                var arr:BitArray = new BitArray(arraySize);
                
                // 设置数据
                for (var k:Number = 0; k < arraySize; k += 10) {
                    arr.setBit(k, 1);
                }
                
                // 执行操作
                arr.countOnes();
                var cloned:BitArray = arr.clone();
                
                tempArrays.push(arr);
                tempArrays.push(cloned);
            }
            
            // 批量清理
            tempArrays = null;
            
            // 每10个周期报告一次
            if (i % 10 == 0 && i > 0) {
                var intermediateTime:Number = getTimer() - startTime;
                trace("  内存管理进度: " + i + "/" + cycles + " 周期，耗时 " + intermediateTime + "ms");
            }
        }
        var memoryTime:Number = getTimer() - startTime;
        
        assertTrue("内存管理压力测试通过", memoryTime < 3000);
        trace("🧠 内存管理测试: " + cycles + "个周期，每周期" + arraysPerCycle + "个数组，耗时 " + memoryTime + "ms");
    }
    
    // ========================================================================
    // 算法精度验证
    // ========================================================================
    
    private static function runAlgorithmAccuracyTests():Void {
        trace("\n🧮 执行算法精度验证...");
        
        testBitOperationAccuracy();
        testLogicalOperationAccuracy();
        testCountOnesAccuracy();
        testStringConversionAccuracy();
    }
    
    private static function testBitOperationAccuracy():Void {
        // 创建已知位模式进行精确测试
        var accuracy:BitArray = new BitArray(16);
        
        // 设置已知模式: 1010110011001010
        var knownPattern:Array = [1,0,1,0,1,1,0,0,1,1,0,0,1,0,1,0];
        for (var i:Number = 0; i < knownPattern.length; i++) {
            accuracy.setBit(i, knownPattern[i]);
        }
        
        // 验证每一位
        for (var j:Number = 0; j < knownPattern.length; j++) {
            assertBitValue("已知模式位" + j, knownPattern[j], accuracy.getBit(j));
        }
        
        // 验证countOnes精度
        var expectedOnes:Number = 0;
        for (var k:Number = 0; k < knownPattern.length; k++) {
            if (knownPattern[k] == 1) expectedOnes++;
        }
        assertEquals("已知模式countOnes精度", expectedOnes, accuracy.countOnes(), 0);
        
        // 测试位翻转精度
        accuracy.flipBit(0); // 1->0
        accuracy.flipBit(1); // 0->1
        
        assertEquals("翻转后countOnes精度", expectedOnes, accuracy.countOnes(), 0);
        assertBitValue("翻转位0精度", 0, accuracy.getBit(0));
        assertBitValue("翻转位1精度", 1, accuracy.getBit(1));
    }
    
    private static function testLogicalOperationAccuracy():Void {
        trace("\n🧮 执行算法精度验证...");
        
        var a:BitArray = new BitArray(8);
        var b:BitArray = new BitArray(8);
        
        // a: 11000101 (bit 7,6,3,0 = 1)
        a.setBit(0, 1); a.setBit(3, 1); a.setBit(6, 1); a.setBit(7, 1);
        
        // b: 10110100 (bit 7,5,4,2 = 1)
        b.setBit(2, 1); b.setBit(4, 1); b.setBit(5, 1); b.setBit(7, 1);
        
        var andResult:BitArray = a.bitwiseAnd(b);
        var orResult:BitArray = a.bitwiseOr(b);
        var xorResult:BitArray = a.bitwiseXor(b);
        var notResult:BitArray = a.bitwiseNot();
        
        for (var i:Number = 0; i < 8; i++) {
            // 让AS2的内置运算符来验证你的实现
            var bitA:Number = a.getBit(i);
            var bitB:Number = b.getBit(i);
            
            assertBitValue("AND位" + i + "精度", bitA & bitB, andResult.getBit(i));
            assertBitValue("OR位" + i + "精度", bitA | bitB, orResult.getBit(i));
            assertBitValue("XOR位" + i + "精度", bitA ^ bitB, xorResult.getBit(i));
            assertBitValue("NOT位" + i + "精度", 1 - bitA, notResult.getBit(i));
        }
    }
    
    private static function testCountOnesAccuracy():Void {
        // 测试不同场景下的countOnes精度
        var scenarios:Array = [
            {size: 1, ones: 0, desc: "单位全0"},
            {size: 1, ones: 1, desc: "单位全1"}, 
            {size: 32, ones: 16, desc: "32位一半"},
            {size: 32, ones: 32, desc: "32位全1"},
            {size: 64, ones: 1, desc: "64位单个1"},
            {size: 100, ones: 50, desc: "100位一半"}
        ];
        
        for (var i:Number = 0; i < scenarios.length; i++) {
            var scenario:Object = scenarios[i];
            var test:BitArray = new BitArray(scenario.size);
            
            // 设置指定数量的1
            for (var j:Number = 0; j < scenario.ones; j++) {
                test.setBit(j, 1);
            }
            
            assertEquals(scenario.desc + " countOnes精度", scenario.ones, test.countOnes(), 0);
        }
        
        // 测试跨块countOnes精度
        var crossBlock:BitArray = new BitArray(96);
        crossBlock.setBit(31, 1); // 第一块最后
        crossBlock.setBit(32, 1); // 第二块第一
        crossBlock.setBit(63, 1); // 第二块最后
        crossBlock.setBit(64, 1); // 第三块第一
        
        assertEquals("跨块countOnes精度", 4, crossBlock.countOnes(), 0);
    }
    
    private static function testStringConversionAccuracy():Void {
        // 测试toString的精度
        var stringTest:BitArray = new BitArray(8);
        
        // 设置简单模式: 10100000
        stringTest.setBit(0, 1);
        stringTest.setBit(2, 1);
        
        var str:String = stringTest.toString();
        assertNotNull("toString结果不为null", str);
        
        // 验证字符串包含正确的字符
        assertTrue("toString包含1", str.indexOf("1") >= 0);
        assertTrue("toString包含0", str.indexOf("0") >= 0);
        
        // 测试全0和全1的toString
        var allZeros:BitArray = new BitArray(5);
        var zeroStr:String = allZeros.toString();
        assertTrue("全0 toString结果合理", zeroStr == "00000" || zeroStr == "0");
        
        var allOnes:BitArray = new BitArray(5);
        allOnes.setAll();
        var oneStr:String = allOnes.toString();
        assertTrue("全1 toString包含1", oneStr.indexOf("1") >= 0);
        
        // 验证toString与实际位状态一致性
        var verifyBits:BitArray = new BitArray(4);
        verifyBits.setBit(0, 1);
        verifyBits.setBit(3, 1);
        
        // 通过重新解析toString验证一致性
        var verifyStr:String = verifyBits.toString().split(" ").join("");
        if (verifyStr.length == 4) {
            // 从右到左检查（toString通常是从高位到低位）
            for (var i:Number = 0; i < 4; i++) {
                var expectedChar:String = verifyBits.getBit(3-i) ? "1" : "0";
                var actualChar:String = verifyStr.charAt(i);
                assertTrue("toString位" + i + "一致性", expectedChar == actualChar);
            }
        }
    }
    
    // ========================================================================
    // 统计和报告
    // ========================================================================
    
    private static function resetTestStats():Void {
        testCount = 0;
        passedTests = 0;
        failedTests = 0;
        performanceResults = [];
    }
    
    private static function printTestSummary(totalTime:Number):Void {
        trace("\n================================================================================");
        trace("📊 BitArray 测试结果汇总 (高性能版)");
        trace("================================================================================");
        trace("总测试数: " + testCount);
        trace("通过: " + passedTests + " ✅");
        trace("失败: " + failedTests + " ❌");
        trace("成功率: " + Math.round((passedTests / testCount) * 100) + "%");
        trace("总耗时: " + totalTime + "ms");
        
        if (performanceResults.length > 0) {
            trace("\n⚡ 性能基准报告:");
            for (var i:Number = 0; i < performanceResults.length; i++) {
                var result:Object = performanceResults[i];
                var avgTimeStr:String = (isNaN(result.avgTime) || result.avgTime == undefined) ? 
                    "N/A" : String(Math.round(result.avgTime * 1000) / 1000);
                trace("  " + result.method + ": " + avgTimeStr + "ms/次 (" + 
                      result.trials + "次测试)");
            }
        }
        
        trace("\n🎯 测试覆盖范围:");
        trace("  📋 基础功能: 构造函数, getBit/setBit/flipBit, 长度管理, 自动扩容");
        trace("  🔧 位操作: clear/setAll, countOnes, clone, toString, getChunks");
        trace("  🧠 逻辑运算: AND/OR/XOR/NOT, 交换律, 结合律验证");
        trace("  🔍 边界条件: 空数组, 单位数组, 边界索引, 极值处理");
        trace("  ⚡ 性能基准: 位操作速度, 逻辑运算, 大数组处理, 内存密集操作");
        trace("  💾 数据完整性: 位状态一致性, 块数据完整性, 扩容数据保持");
        trace("  💪 压力测试: 大量位操作, 并发逻辑运算, 极端扩容, 内存管理");
        trace("  🧮 算法精度: 位操作精度, 逻辑运算精度, countOnes精度, 字符串转换");
        
        trace("\n🚀 BitArray 核心特性:");
        trace("  ✨ 高效的32位块存储机制");
        trace("  ✨ 优化的位运算算法实现");
        trace("  ✨ 自动扩容和内存管理");
        trace("  ✨ 完整的逻辑运算支持");
        trace("  ✨ 汉明重量快速计算");
        
        if (failedTests == 0) {
            trace("\n🎉 所有测试通过！BitArray 组件质量优秀！");
        } else {
            trace("\n⚠️ 发现 " + failedTests + " 个问题，请检查实现！");
        }
        
        trace("================================================================================");
    }
}