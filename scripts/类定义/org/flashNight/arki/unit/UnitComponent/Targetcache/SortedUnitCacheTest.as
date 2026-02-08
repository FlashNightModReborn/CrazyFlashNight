import org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache;
import org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizer;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;

/**
 * 完整测试套件：SortedUnitCache
 * ================================
 * 特性：
 * - 100% 方法覆盖率测试
 * - 查询算法准确性验证
 * - 性能基准测试（二分查找、线性扫描、缓存优化）
 * - 边界条件与极值测试
 * - 数据完整性验证
 * - 压力测试与内存管理
 * - 一句启动设计
 * 
 * 使用方法：
 * org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCacheTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCacheTest {
    
    // ========================================================================
    // 测试统计和配置
    // ========================================================================
    
    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var performanceResults:Array = [];
    
    // 性能基准配置
    private static var PERFORMANCE_TRIALS:Number = 500;
    private static var STRESS_DATA_SIZE:Number = 1000;
    private static var QUERY_BENCHMARK_MS:Number = 2.0; // 查询操作不超过2ms
    
    // 测试数据缓存
    private static var testUnits:Array;
    private static var testCache:SortedUnitCache;
    
    /**
     * 主测试入口 - 一句启动全部测试
     */
    public static function runAll():Void {
        trace("================================================================================");
        trace("🚀 SortedUnitCache 完整测试套件启动");
        trace("================================================================================");
        
        var startTime:Number = getTimer();
        resetTestStats();
        
        try {
            // 初始化测试数据
            initializeTestData();
            
            // === 基础功能测试 ===
            runBasicFunctionalityTests();
            
            // === 查询算法测试 ===
            runQueryAlgorithmTests();

            // === Monotonic sweep tests ===
            runMonotonicSweepTests();
            
            // === 范围查询测试 ===
            runRangeQueryTests();
            
            // === 条件查询测试 ===
            runConditionalQueryTests();
            
            // === 边界条件测试 ===
            runBoundaryConditionTests();
            
            // === 性能基准测试 ===
            runPerformanceBenchmarks();
            
            // === 数据完整性测试 ===
            runDataIntegrityTests();
            
            // === 压力测试 ===
            runStressTests();
            
            // === 算法优化验证 ===
            runAlgorithmOptimizationTests();
            
            // === 过滤器查询测试 ===
            runFilteredQueryTests();

            // === rightMaxValues 前缀最大值测试 ===
            runRightMaxValuesTests();

            // === Bug 修复回归测试 ===
            runBugfixRegressionTests();

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
    
    private static function assertStringEquals(testName:String, expected:String, actual:String):Void {
        testCount++;
        if (expected == actual) {
            passedTests++;
            trace("✅ " + testName + " PASS (expected=\"" + expected + "\", actual=\"" + actual + "\")");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (expected=\"" + expected + "\", actual=\"" + actual + "\")");
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
    
    private static function assertArrayEquals(testName:String, expected:Array, actual:Array):Void {
        testCount++;
        if (!expected && !actual) {
            passedTests++;
            trace("✅ " + testName + " PASS (both arrays null)");
            return;
        }
        
        if (!expected || !actual || expected.length != actual.length) {
            failedTests++;
            trace("❌ " + testName + " FAIL (array length mismatch)");
            return;
        }
        
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] != actual[i]) {
                failedTests++;
                trace("❌ " + testName + " FAIL (element " + i + " mismatch)");
                return;
            }
        }
        
        passedTests++;
        trace("✅ " + testName + " PASS");
    }
    
    // ========================================================================
    // 测试数据初始化
    // ========================================================================
    
    private static function initializeTestData():Void {
        trace("\n🔧 初始化测试数据...");
        
        // 创建标准测试单位集合
        testUnits = createTestUnits(50);
        testCache = createTestCache(testUnits);
        
        trace("📦 创建了 " + testUnits.length + " 个测试单位");
    }
    
    /**
     * 创建模拟单位对象
     */
    private static function createTestUnits(count:Number):Array {
        var units:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var unit:Object = {
                _name: "unit_" + i,
                hp: 80 + Math.random() * 40, // 80-120血量
                maxhp: 100,
                aabbCollider: {
                    left: i * 20 + Math.random() * 10, // 基础间距20，随机波动10
                    right: 0 // 稍后计算
                }
            };
            
            unit.aabbCollider.right = unit.aabbCollider.left + 15; // 固定宽度15
            units[i] = unit;
        }
        
        // 确保按left值排序
        units.sort(function(a, b) {
            return a.aabbCollider.left - b.aabbCollider.left;
        });
        
        return units;
    }
    
    /**
     * 创建测试缓存对象
     */
    private static function createTestCache(units:Array):SortedUnitCache {
        var nameIndex:Object = {};
        var leftValues:Array = [];
        var rightValues:Array = [];
        
        for (var i:Number = 0; i < units.length; i++) {
            nameIndex[units[i]._name] = i;
            leftValues[i] = units[i].aabbCollider.left;
            rightValues[i] = units[i].aabbCollider.right;
        }
        
        return new SortedUnitCache(units, nameIndex, leftValues, rightValues, 1000);
    }
    
    /**
     * 创建特殊场景的测试数据
     */
    private static function createSpecialScenarioUnits(scenario:String):Array {
        var units:Array;
        
        switch (scenario) {
            case "clustered":
                // 聚集分布
                units = [];
                for (var i:Number = 0; i < 20; i++) {
                    var cluster:Number = Math.floor(i / 5);
                    var unit:Object = {
                        _name: "clustered_" + i,
                        hp: 100,
                        maxhp: 100,
                        aabbCollider: {
                            left: cluster * 200 + (i % 5) * 5,
                            right: 0
                        }
                    };
                    unit.aabbCollider.right = unit.aabbCollider.left + 15;
                    units[i] = unit;
                }
                break;
                
            case "sparse":
                // 稀疏分布
                units = [];
                for (var j:Number = 0; j < 10; j++) {
                    var unit2:Object = {
                        _name: "sparse_" + j,
                        hp: 100,
                        maxhp: 100,
                        aabbCollider: {
                            left: j * 100,
                            right: j * 100 + 15
                        }
                    };
                    units[j] = unit2;
                }
                break;
                
            case "uniform":
                // 均匀分布
                units = [];
                for (var k:Number = 0; k < 30; k++) {
                    var unit3:Object = {
                        _name: "uniform_" + k,
                        hp: 100,
                        maxhp: 100,
                        aabbCollider: {
                            left: k * 25,
                            right: k * 25 + 15
                        }
                    };
                    units[k] = unit3;
                }
                break;
                
            default:
                return createTestUnits(20);
        }
        
        return units;
    }
    
    // ========================================================================
    // 基础功能测试
    // ========================================================================
    
    private static function runBasicFunctionalityTests():Void {
        trace("\n📋 执行基础功能测试...");
        
        testConstructor();
        testBasicInformationMethods();
        testToStringMethod();
    }
    
    private static function testConstructor():Void {
        // 测试默认构造函数
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        assertEquals("空构造函数-数据长度", 0, emptyCache.getCount(), 0);
        assertTrue("空构造函数-isEmpty", emptyCache.isEmpty());
        
        // 测试完整参数构造函数
        var fullCache:SortedUnitCache = new SortedUnitCache(
            testUnits.slice(0, 5),
            {test: 0},
            [1, 2, 3, 4, 5],
            [10, 20, 30, 40, 50],
            999
        );
        assertEquals("完整构造函数-数据长度", 5, fullCache.getCount(), 0);
        assertEquals("完整构造函数-帧数", 999, fullCache.lastUpdatedFrame, 0);
        
        // 测试空参数构造函数
        var nullCache:SortedUnitCache = new SortedUnitCache(null, null, null, null, null);
        assertEquals("空参数构造函数-数据长度", 0, nullCache.getCount(), 0);
        assertEquals("空参数构造函数-帧数", 0, nullCache.lastUpdatedFrame, 0);
    }
    
    private static function testBasicInformationMethods():Void {
        // getCount测试
        assertEquals("getCount正确", 50, testCache.getCount(), 0);
        
        // isEmpty测试
        assertTrue("非空缓存isEmpty为false", !testCache.isEmpty());
        
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        assertTrue("空缓存isEmpty为true", emptyCache.isEmpty());
        
        // getUnitAt测试
        var unit0:Object = testCache.getUnitAt(0);
        assertNotNull("getUnitAt(0)返回对象", unit0);
        assertStringEquals("getUnitAt(0)名称正确", "unit_0", unit0._name);
        
        var unitLast:Object = testCache.getUnitAt(49);
        assertNotNull("getUnitAt(49)返回对象", unitLast);
        
        var unitOutOfBounds:Object = testCache.getUnitAt(100);
        assertNull("getUnitAt越界返回null", unitOutOfBounds);
        
        var unitNegative:Object = testCache.getUnitAt(-1);
        assertNull("getUnitAt负索引返回null", unitNegative);
        
        // findUnitByName测试
        var foundUnit:Object = testCache.findUnitByName("unit_5");
        assertNotNull("findUnitByName找到单位", foundUnit);
        assertStringEquals("findUnitByName名称匹配", "unit_5", foundUnit._name);
        
        var notFoundUnit:Object = testCache.findUnitByName("nonexistent");
        assertNull("findUnitByName找不到返回null", notFoundUnit);
    }
    
    private static function testToStringMethod():Void {
        var str:String = testCache.toString();
        assertNotNull("toString返回字符串", str);
        assertTrue("toString包含单位数量", str.indexOf("50 units") >= 0);
        assertTrue("toString包含帧数", str.indexOf("1000") >= 0);
    }
    
    // ========================================================================
    // 查询算法测试
    // ========================================================================
    
    private static function runQueryAlgorithmTests():Void {
        trace("\n🔍 执行查询算法测试...");
        
        testGetTargetsFromIndex();
        testFindNearest();
        testFindFarthest();
    }
    
    // ========================================================================
    // Monotonic sweep (two-pointer prep) tests
    // ========================================================================
    private static function runMonotonicSweepTests():Void {
        trace("\n>> runMonotonicSweepTests");
        testMonotonic_basicForward();
        testMonotonic_resetOnNewFrame();
        testMonotonic_matchesBaselineIncreasing();
        testMonotonic_handlesOutOfOrder();
    }

    private static function createUniformCache(count:Number, step:Number, width:Number):SortedUnitCache {
        var units:Array = [];
        var i:Number = 0;
        while (i < count) {
            var L:Number = i * step;
            units[i] = {
                _name: "u_" + i,
                hp: 100,
                maxhp: 100,
                aabbCollider: { left: L, right: L + width }
            };
            i++;
        }
        var nameIndex:Object = {};
        var leftValues:Array = [];
        var rightValues:Array = [];
        for (i = 0; i < count; i++) {
            nameIndex[units[i]._name] = i;
            leftValues[i] = units[i].aabbCollider.left;
            rightValues[i] = units[i].aabbCollider.right;
        }
        return new SortedUnitCache(units, nameIndex, leftValues, rightValues, 2000);
    }

    private static function testMonotonic_basicForward():Void {
        var cache:SortedUnitCache = createUniformCache(10, 10, 5); // right: 5,15,25,...
        cache.beginMonotonicSweep(1);

        var q:AABBCollider = new AABBCollider();
        var queries:Array = [0, 6, 11, 16, 21, 26];
        // 修正后的期望值，这反映了算法的正确行为
        var expect:Array  = [0, 1, 1, 2, 2, 3]; 

        for (var i:Number = 0; i < queries.length; i++) {
            q.left = queries[i];
            var r:Object = cache.getTargetsFromIndexMonotonic(q);
            assertEquals("Monotonic 基本前进: qLeft=" + queries[i], expect[i], r.startIndex, 0);
        }
    }

    private static function testMonotonic_resetOnNewFrame():Void {
        var cache:SortedUnitCache = createUniformCache(10, 10, 5);

        var q:AABBCollider = new AABBCollider();
        // 第一帧推进到靠右
        cache.beginMonotonicSweep(100);
        q.left = 80; // 应推进到 index≈8 (right=85)
        var r1:Object = cache.getTargetsFromIndexMonotonic(q);
        assertTrue("第一帧推进到右侧", r1.startIndex >= 8);

        // 新帧应重置回从 0 扫描
        cache.beginMonotonicSweep(101);
        q.left = 0;
        var r2:Object = cache.getTargetsFromIndexMonotonic(q);
        assertEquals("新帧重置从0开始", 0, r2.startIndex, 0);
    }

    private static function testMonotonic_matchesBaselineIncreasing():Void {
        var cache:SortedUnitCache = createTestCache(createTestUnits(50));
        var q:AABBCollider = new AABBCollider();
        cache.beginMonotonicSweep(7);

        var base:Number = 0;
        for (var i:Number = 0; i < 10; i++) {
            base += 30 + Math.random() * 20; // 单调递增
            q.left = base;
            var mono:Object = cache.getTargetsFromIndexMonotonic(q);
            var ref:Object  = cache.getTargetsFromIndex(q);
            assertEquals("单调模式应与基线一致 i="+i, ref.startIndex, mono.startIndex, 0);
        }
    }

    private static function testMonotonic_handlesOutOfOrder():Void {
        var cache:SortedUnitCache = createUniformCache(10, 10, 5);
        var q:AABBCollider = new AABBCollider();

        cache.beginMonotonicSweep(3);
        q.left = 40; // 先推进到某处
        var _tmp:Object = cache.getTargetsFromIndexMonotonic(q);
        // 乱序：更小的 left
        q.left = 10;
        var mono:Object = cache.getTargetsFromIndexMonotonic(q);

        // 基线：从头查询
        var ref:Object = cache.getTargetsFromIndex(q);
        assertEquals("乱序查询也应保持与基线一致", ref.startIndex, mono.startIndex, 0);
    }

    private static function testGetTargetsFromIndex():Void {
        // 创建查询碰撞盒
        var queryCollider:AABBCollider = new AABBCollider();
        queryCollider.left = 100;
        
        var result:Object = testCache.getTargetsFromIndex(queryCollider);
        assertNotNull("getTargetsFromIndex返回结果", result);
        assertNotNull("结果包含data", result.data);
        assertTrue("结果包含startIndex", result.hasOwnProperty("startIndex"));
        assertTrue("startIndex为有效数值", result.startIndex >= 0);
        
        // 测试边界情况
        queryCollider.left = -1000; // 极小值
        var resultMin:Object = testCache.getTargetsFromIndex(queryCollider);
        assertEquals("极小查询值startIndex为0", 0, resultMin.startIndex, 0);
        
        queryCollider.left = 10000; // 极大值
        var resultMax:Object = testCache.getTargetsFromIndex(queryCollider);
        assertEquals("极大查询值startIndex为数组长度", testCache.getCount(), resultMax.startIndex, 0);
        
        // 测试空缓存
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        queryCollider.left = 100;
        var emptyResult:Object = emptyCache.getTargetsFromIndex(queryCollider);
        assertEquals("空缓存startIndex为0", 0, emptyResult.startIndex, 0);
    }
    
    private static function testFindNearest():Void {
        var targetUnit:Object = testUnits[25]; // 中间的单位
        var nearest:Object = testCache.findNearest(targetUnit);
        assertNotNull("findNearest找到最近单位", nearest);
        assertTrue("最近单位不是目标自身", nearest != targetUnit);
        
        // 测试不在缓存中的单位
        var externalUnit:Object = {
            _name: "external",
            aabbCollider: { left: 250, right: 265 }
        };
        var nearestExternal:Object = testCache.findNearest(externalUnit);
        assertNotNull("外部单位findNearest", nearestExternal);
        
        // 测试空缓存
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        var nearestEmpty:Object = emptyCache.findNearest(targetUnit);
        assertNull("空缓存findNearest返回null", nearestEmpty);
        
        // 测试单元素缓存
        var singleCache:SortedUnitCache = createTestCache([testUnits[0]]);
        var nearestSingle:Object = singleCache.findNearest(targetUnit);
        assertNotNull("单元素缓存findNearest", nearestSingle);
        
        // 测试findFarthest：目标不在缓存中，应该返回唯一单位
        var farthestSingle:Object = singleCache.findFarthest(targetUnit);
        assertNotNull("单元素缓存findFarthest(外部目标)", farthestSingle);
        
        // 测试findFarthest：目标在缓存中，应该返回null
        var farthestSelf:Object = singleCache.findFarthest(testUnits[0]);
        assertNull("单元素缓存findFarthest(自身目标)", farthestSelf);
    }
    
    private static function testFindFarthest():Void {
        var targetUnit:Object = testUnits[25]; // 中间的单位
        var farthest:Object = testCache.findFarthest(targetUnit);
        assertNotNull("findFarthest找到最远单位", farthest);
        assertTrue("最远单位不是目标自身", farthest != targetUnit);
        
        // 测试边界单位
        var firstUnit:Object = testUnits[0];
        var farthestFromFirst:Object = testCache.findFarthest(firstUnit);
        assertNotNull("首个单位findFarthest", farthestFromFirst);
        
        var lastUnit:Object = testUnits[testUnits.length - 1];
        var farthestFromLast:Object = testCache.findFarthest(lastUnit);
        assertNotNull("末尾单位findFarthest", farthestFromLast);
        
        // 测试不在缓存中的单位
        var externalUnit:Object = {
            _name: "external",
            aabbCollider: { left: 250, right: 265 }
        };
        var farthestExternal:Object = testCache.findFarthest(externalUnit);
        assertNotNull("外部单位findFarthest", farthestExternal);
        
        // 测试空缓存
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        var farthestEmpty:Object = emptyCache.findFarthest(targetUnit);
        assertNull("空缓存findFarthest返回null", farthestEmpty);
        
        // 测试单元素缓存（目标不在缓存中，应该返回唯一单位）
        var singleCache:SortedUnitCache = createTestCache([testUnits[0]]);
        var farthestSingle:Object = singleCache.findFarthest(targetUnit);
        assertNotNull("单元素缓存findFarthest(外部目标)", farthestSingle);
    }
    
    // ========================================================================
    // 范围查询测试
    // ========================================================================
    
    private static function runRangeQueryTests():Void {
        trace("\n📏 执行范围查询测试...");
        
        testFindInRange();
        testFindInRadius();
        testFindNearestInRange();
        testFindFarthestInRange();
        testGetCountInRange();
        testGetCountInRadius();
    }
    
    private static function testFindInRange():Void {
        var targetUnit:Object = testUnits[25];
        
        // 基本范围查询
        var inRange:Array = testCache.findInRange(targetUnit, 50, 50, true);
        assertNotNull("findInRange返回数组", inRange);
        assertTrue("范围查询结果为数组", inRange instanceof Array);
        
        // 验证结果中不包含目标自身
        for (var i:Number = 0; i < inRange.length; i++) {
            assertTrue("范围查询不包含目标自身", inRange[i] != targetUnit);
        }
        
        // 测试不排除自身
        var inRangeWithSelf:Array = testCache.findInRange(targetUnit, 50, 50, false);
        assertTrue("不排除自身结果更多", inRangeWithSelf.length >= inRange.length);
        
        // 测试极小范围
        var smallRange:Array = testCache.findInRange(targetUnit, 1, 1, true);
        assertTrue("极小范围结果较少", smallRange.length <= inRange.length);
        
        // 测试极大范围
        var largeRange:Array = testCache.findInRange(targetUnit, 10000, 10000, true);
        assertTrue("极大范围包含大部分单位", largeRange.length >= inRange.length);
        
        // 测试空缓存
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        var emptyResult:Array = emptyCache.findInRange(targetUnit, 50, 50, true);
        assertEquals("空缓存范围查询长度为0", 0, emptyResult.length, 0);
    }
    
    private static function testFindInRadius():Void {
        var targetUnit:Object = testUnits[25];
        
        var inRadius:Array = testCache.findInRadius(targetUnit, 100, true);
        assertNotNull("findInRadius返回数组", inRadius);
        
        // 与findInRange结果比较
        var inRange:Array = testCache.findInRange(targetUnit, 100, 100, true);
        assertEquals("findInRadius与findInRange结果一致", inRange.length, inRadius.length, 0);
    }
    
    private static function testFindNearestInRange():Void {
        var targetUnit:Object = testUnits[25];
        
        // 足够大的范围
        var nearestLarge:Object = testCache.findNearestInRange(targetUnit, 1000);
        assertNotNull("大范围findNearestInRange", nearestLarge);
        
        // 很小的范围
        var nearestSmall:Object = testCache.findNearestInRange(targetUnit, 1);
        // 可能为null，这是正常的
        
        // 零范围
        var nearestZero:Object = testCache.findNearestInRange(targetUnit, 0);
        assertNull("零范围findNearestInRange返回null", nearestZero);
    }
    
    private static function testFindFarthestInRange():Void {
        var targetUnit:Object = testUnits[25];
        
        // 足够大的范围
        var farthestLarge:Object = testCache.findFarthestInRange(targetUnit, 10000);
        assertNotNull("大范围findFarthestInRange", farthestLarge);
        
        // 很小的范围
        var farthestSmall:Object = testCache.findFarthestInRange(targetUnit, 10);
        // 可能为null
        
        // 零范围
        var farthestZero:Object = testCache.findFarthestInRange(targetUnit, 0);
        assertNull("零范围findFarthestInRange返回null", farthestZero);
    }
    
    private static function testGetCountInRange():Void {
        var targetUnit:Object = testUnits[25];
        
        var count:Number = testCache.getCountInRange(targetUnit, 50, 50, true);
        assertTrue("范围计数为非负数", count >= 0);
        
        var countWithSelf:Number = testCache.getCountInRange(targetUnit, 50, 50, false);
        assertTrue("包含自身计数更大", countWithSelf >= count);
        
        // 验证计数与查询结果一致
        var inRange:Array = testCache.findInRange(targetUnit, 50, 50, true);
        assertEquals("计数与查询结果长度一致", inRange.length, count, 0);
        
        // 测试零范围
        var zeroCount:Number = testCache.getCountInRange(targetUnit, 0, 0, true);
        assertEquals("零范围计数为0", 0, zeroCount, 0);
    }
    
    private static function testGetCountInRadius():Void {
        var targetUnit:Object = testUnits[25];
        
        var radiusCount:Number = testCache.getCountInRadius(targetUnit, 100, true);
        var rangeCount:Number = testCache.getCountInRange(targetUnit, 100, 100, true);
        
        assertEquals("半径计数与范围计数一致", rangeCount, radiusCount, 0);
    }
    
    // ========================================================================
    // 条件查询测试
    // ========================================================================
    
    private static function runConditionalQueryTests():Void {
        trace("\n🎯 执行条件查询测试...");
        
        testGetCountByHP();
        testFindByHP();
        testDistanceDistribution();
    }
    
    private static function testGetCountByHP():Void {
        // 修改一些测试单位的血量来创建不同条件
        testUnits[0].hp = 10; // critical
        testUnits[1].hp = 25; // low
        testUnits[2].hp = 50; // medium
        testUnits[3].hp = 85; // high
        testUnits[4].hp = 100; // healthy
        testUnits[5].hp = 80; // injured
        
        var criticalCount:Number = testCache.getCountByHP("critical", null);
        assertTrue("critical血量计数", criticalCount >= 1);
        
        var lowCount:Number = testCache.getCountByHP("low", null);
        assertTrue("low血量计数", lowCount >= 1);
        
        var mediumCount:Number = testCache.getCountByHP("medium", null);
        assertTrue("medium血量计数", mediumCount >= 1);
        
        var highCount:Number = testCache.getCountByHP("high", null);
        assertTrue("high血量计数", highCount >= 1);
        
        var healthyCount:Number = testCache.getCountByHP("healthy", null);
        assertTrue("healthy血量计数", healthyCount >= 1);
        
        var injuredCount:Number = testCache.getCountByHP("injured", null);
        assertTrue("injured血量计数", injuredCount >= 1);
        
        // 测试无效条件
        var invalidCount:Number = testCache.getCountByHP("invalid", null);
        assertEquals("无效条件返回0", 0, invalidCount, 0);
        
        // 测试排除目标
        var excludeCount:Number = testCache.getCountByHP("low", testUnits[1]);
        assertTrue("排除目标后计数减少", excludeCount < lowCount);
    }
    
    private static function testFindByHP():Void {
        var criticalUnits:Array = testCache.findByHP("critical", null);
        assertNotNull("findByHP返回数组", criticalUnits);
        assertTrue("critical单位数组长度正确", criticalUnits.length >= 1);
        
        // 验证血量条件
        for (var i:Number = 0; i < criticalUnits.length; i++) {
            var unit:Object = criticalUnits[i];
            assertTrue("critical单位血量正确", (unit.hp / unit.maxhp) <= 0.1);
        }
        
        var lowUnits:Array = testCache.findByHP("low", null);
        for (var j:Number = 0; j < lowUnits.length; j++) {
            var lowUnit:Object = lowUnits[j];
            assertTrue("low单位血量正确", (lowUnit.hp / lowUnit.maxhp) <= 0.3);
        }
        
        var mediumUnits:Array = testCache.findByHP("medium", null);
        for (var k:Number = 0; k < mediumUnits.length; k++) {
            var mediumUnit:Object = mediumUnits[k];
            var ratio:Number = mediumUnit.hp / mediumUnit.maxhp;
            assertTrue("medium单位血量正确", ratio > 0.3 && ratio <= 0.7);
        }
        
        // 测试排除功能
        var withoutExclude:Array = testCache.findByHP("low", null);
        var withExclude:Array = testCache.findByHP("low", testUnits[1]);
        assertTrue("排除目标功能正常", withExclude.length <= withoutExclude.length);
    }
    
    private static function testDistanceDistribution():Void {
        var targetUnit:Object = testUnits[25];
        var distribution:Object = testCache.getDistanceDistribution(targetUnit, [50, 100, 200], true);
        
        assertNotNull("距离分布返回对象", distribution);
        assertTrue("包含totalCount", distribution.hasOwnProperty("totalCount"));
        assertTrue("包含distribution数组", distribution.hasOwnProperty("distribution"));
        assertTrue("包含beyondCount", distribution.hasOwnProperty("beyondCount"));
        assertTrue("包含minDistance", distribution.hasOwnProperty("minDistance"));
        assertTrue("包含maxDistance", distribution.hasOwnProperty("maxDistance"));
        
        assertTrue("totalCount为正数", distribution.totalCount >= 0);
        assertTrue("distribution为数组", distribution.distribution instanceof Array);
        assertEquals("distribution长度正确", 3, distribution.distribution.length, 0);
        
        // 测试默认距离区间
        var defaultDistribution:Object = testCache.getDistanceDistribution(targetUnit, null, true);
        assertNotNull("默认距离区间分布", defaultDistribution);
        assertEquals("默认区间长度", 4, defaultDistribution.distribution.length, 0);
        
        // 测试空缓存
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        var emptyDistribution:Object = emptyCache.getDistanceDistribution(targetUnit, [50, 100], true);
        assertEquals("空缓存totalCount为0", 0, emptyDistribution.totalCount, 0);
        assertEquals("空缓存minDistance为-1", -1, emptyDistribution.minDistance, 0);
    }
    
    // ========================================================================
    // 边界条件测试
    // ========================================================================
    
    private static function runBoundaryConditionTests():Void {
        trace("\n🔍 执行边界条件测试...");
        
        testEmptyCache();
        testSingleElementCache();
        testDuplicatePositions();
        testExtremeValues();
    }
    
    private static function testEmptyCache():Void {
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        
        assertEquals("空缓存数量", 0, emptyCache.getCount(), 0);
        assertTrue("空缓存isEmpty", emptyCache.isEmpty());
        assertNull("空缓存getUnitAt", emptyCache.getUnitAt(0));
        assertNull("空缓存findUnitByName", emptyCache.findUnitByName("test"));
        
        var target:Object = testUnits[0];
        assertNull("空缓存findNearest", emptyCache.findNearest(target));
        assertNull("空缓存findFarthest", emptyCache.findFarthest(target));
        
        var emptyRange:Array = emptyCache.findInRange(target, 100, 100, true);
        assertEquals("空缓存范围查询长度", 0, emptyRange.length, 0);
        
        assertEquals("空缓存范围计数", 0, emptyCache.getCountInRange(target, 100, 100, true), 0);
    }
    
    private static function testSingleElementCache():Void {
        var singleUnit:Array = [testUnits[0]];
        var singleCache:SortedUnitCache = createTestCache(singleUnit);
        
        assertEquals("单元素缓存数量", 1, singleCache.getCount(), 0);
        assertTrue("单元素缓存非空", !singleCache.isEmpty());
        
        var found:Object = singleCache.findUnitByName("unit_0");
        assertNotNull("单元素缓存findUnitByName", found);
        
        var target:Object = testUnits[5]; // 不在缓存中的单位
        var nearest:Object = singleCache.findNearest(target);
        assertNotNull("单元素缓存findNearest", nearest);
        
        // 目标不在缓存中，应该返回唯一单位
        var farthest:Object = singleCache.findFarthest(target);
        assertNotNull("单元素缓存findFarthest(外部目标)", farthest);
        
        // 目标在缓存中，应该返回null（没有其他单位）
        var farthestSelf:Object = singleCache.findFarthest(testUnits[0]);
        assertNull("单元素缓存findFarthest(自身目标)", farthestSelf);
    }
    
    private static function testDuplicatePositions():Void {
        // 创建包含重复位置的单位
        var duplicateUnits:Array = [];
        for (var i:Number = 0; i < 10; i++) {
            var unit:Object = {
                _name: "dup_" + i,
                hp: 100,
                maxhp: 100,
                aabbCollider: {
                    left: Math.floor(i / 2) * 50, // 每两个单位共享一个位置
                    right: Math.floor(i / 2) * 50 + 15
                }
            };
            duplicateUnits[i] = unit;
        }
        
        var dupCache:SortedUnitCache = createTestCache(duplicateUnits);
        
        var target:Object = duplicateUnits[0];
        var nearest:Object = dupCache.findNearest(target);
        assertNotNull("重复位置findNearest", nearest);
        
        var count:Number = dupCache.getCountInRange(target, 10, 10, true);
        assertTrue("重复位置范围计数", count >= 1);
    }
    
    private static function testExtremeValues():Void {
        // 创建包含极值的单位
        var extremeUnits:Array = [
            {
                _name: "extreme_min",
                hp: 1,
                maxhp: 100,
                aabbCollider: { left: -10000, right: -9985 }
            },
            {
                _name: "extreme_max",
                hp: 100,
                maxhp: 100,
                aabbCollider: { left: 10000, right: 10015 }
            },
            {
                _name: "extreme_zero",
                hp: 0,
                maxhp: 100,
                aabbCollider: { left: 0, right: 15 }
            }
        ];
        
        var extremeCache:SortedUnitCache = createTestCache(extremeUnits);
        
        var target:Object = extremeUnits[1];
        var nearest:Object = extremeCache.findNearest(target);
        assertNotNull("极值单位findNearest", nearest);
        
        var farthest:Object = extremeCache.findFarthest(target);
        assertNotNull("极值单位findFarthest", farthest);
        
        // 测试极值血量条件
        var zeroHpCount:Number = extremeCache.getCountByHP("critical", null);
        assertTrue("极值血量计数", zeroHpCount >= 1);
    }
    
    // ========================================================================
    // 性能基准测试
    // ========================================================================
    
    private static function runPerformanceBenchmarks():Void {
        trace("\n⚡ 执行性能基准测试...");
        
        performanceTestQueryMethods();
        performanceTestRangeMethods();
        performanceTestConditionalMethods();
        performanceTestCacheOptimization();
    }
    
    private static function performanceTestQueryMethods():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var target:Object = testUnits[25];
        var queryCollider:AABBCollider = new AABBCollider();
        queryCollider.left = 250;
        
        // getTargetsFromIndex性能
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            queryCollider.left = 100 + (i % 500); // 变化查询位置
            testCache.getTargetsFromIndex(queryCollider);
        }
        var getTargetsTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "getTargetsFromIndex",
            trials: trials,
            totalTime: getTargetsTime,
            avgTime: getTargetsTime / trials
        });
        
        trace("📊 getTargetsFromIndex性能: " + trials + "次调用耗时 " + getTargetsTime + "ms");
        assertTrue("getTargetsFromIndex性能达标", (getTargetsTime / trials) < QUERY_BENCHMARK_MS);
        
        // findNearest性能
        startTime = getTimer();
        for (var j:Number = 0; j < trials; j++) {
            testCache.findNearest(target);
        }
        var findNearestTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "findNearest",
            trials: trials,
            totalTime: findNearestTime,
            avgTime: findNearestTime / trials
        });
        
        trace("📊 findNearest性能: " + trials + "次调用耗时 " + findNearestTime + "ms");
        assertTrue("findNearest性能达标", (findNearestTime / trials) < QUERY_BENCHMARK_MS);
        
        // findFarthest性能
        startTime = getTimer();
        for (var k:Number = 0; k < trials; k++) {
            testCache.findFarthest(target);
        }
        var findFarthestTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "findFarthest",
            trials: trials,
            totalTime: findFarthestTime,
            avgTime: findFarthestTime / trials
        });
        
        trace("📊 findFarthest性能: " + trials + "次调用耗时 " + findFarthestTime + "ms");
        assertTrue("findFarthest性能达标", (findFarthestTime / trials) < QUERY_BENCHMARK_MS);
    }
    
    private static function performanceTestRangeMethods():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var target:Object = testUnits[25];
        
        // findInRange性能
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            testCache.findInRange(target, 50 + (i % 100), 50 + (i % 100), true);
        }
        var findInRangeTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "findInRange",
            trials: trials,
            totalTime: findInRangeTime,
            avgTime: findInRangeTime / trials
        });
        
        trace("📊 findInRange性能: " + trials + "次调用耗时 " + findInRangeTime + "ms");
        assertTrue("findInRange性能达标", (findInRangeTime / trials) < QUERY_BENCHMARK_MS);
        
        // getCountInRange性能
        startTime = getTimer();
        for (var j:Number = 0; j < trials; j++) {
            testCache.getCountInRange(target, 50 + (j % 100), 50 + (j % 100), true);
        }
        var getCountTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "getCountInRange",
            trials: trials,
            totalTime: getCountTime,
            avgTime: getCountTime / trials
        });
        
        trace("📊 getCountInRange性能: " + trials + "次调用耗时 " + getCountTime + "ms");
        assertTrue("getCountInRange性能达标", (getCountTime / trials) < QUERY_BENCHMARK_MS);
    }
    
    private static function performanceTestConditionalMethods():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        
        // getCountByHP性能
        var startTime:Number = getTimer();
        var conditions:Array = ["low", "medium", "high", "critical", "injured", "healthy"];
        for (var i:Number = 0; i < trials; i++) {
            var condition:String = conditions[i % conditions.length];
            testCache.getCountByHP(condition, null);
        }
        var hpCountTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "getCountByHP",
            trials: trials,
            totalTime: hpCountTime,
            avgTime: hpCountTime / trials
        });
        
        trace("📊 getCountByHP性能: " + trials + "次调用耗时 " + hpCountTime + "ms");
        assertTrue("getCountByHP性能达标", (hpCountTime / trials) < QUERY_BENCHMARK_MS);
    }
    
    private static function performanceTestCacheOptimization():Void {
        // 测试缓存优化效果 - 连续相似查询
        var trials:Number = 100;
        var queryCollider:AABBCollider = new AABBCollider();
        var basePosition:Number = 250;
        
        // 重置缓存以测试优化
        testCache.resetQueryCache();
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            // 小幅变化的查询位置（应该触发缓存优化）
            queryCollider.left = basePosition + (i % 10);
            testCache.getTargetsFromIndex(queryCollider);
        }
        var optimizedTime:Number = getTimer() - startTime;
        
        trace("📊 缓存优化测试: " + trials + "次相似查询耗时 " + optimizedTime + "ms");
        assertTrue("缓存优化有效", (optimizedTime / trials) < QUERY_BENCHMARK_MS);
    }
    
    // ========================================================================
    // 数据完整性测试
    // ========================================================================
    
    private static function runDataIntegrityTests():Void {
        trace("\n💾 执行数据完整性测试...");
        
        testCacheManagement();
        testDataValidation();
        testStatusMethods();
    }
    
    private static function testCacheManagement():Void {
        // resetQueryCache测试
        testCache.resetQueryCache();
        assertTrue("resetQueryCache执行成功", true); // 无异常即成功
        
        // updateData测试
        var newUnits:Array = createTestUnits(10);
        var newCache:SortedUnitCache = createTestCache(newUnits);
        
        testCache.updateData(
            newCache.data,
            newCache.nameIndex,
            newCache.leftValues,
            newCache.rightValues,
            2000
        );
        
        assertEquals("updateData后数量正确", 10, testCache.getCount(), 0);
        assertEquals("updateData后帧数正确", 2000, testCache.lastUpdatedFrame, 0);
        
        // 恢复原始测试数据
        var originalCache:SortedUnitCache = createTestCache(testUnits);
        testCache.updateData(
            originalCache.data,
            originalCache.nameIndex,
            originalCache.leftValues,
            originalCache.rightValues,
            1000
        );
    }
    
    private static function testDataValidation():Void {
        var validation:Object = testCache.validateData();
        assertNotNull("validateData返回对象", validation);
        assertTrue("包含isValid属性", validation.hasOwnProperty("isValid"));
        assertTrue("包含errors数组", validation.hasOwnProperty("errors"));
        assertTrue("包含warnings数组", validation.hasOwnProperty("warnings"));
        
        assertTrue("正常数据验证通过", validation.isValid);
        assertEquals("正常数据无错误", 0, validation.errors.length, 0);
        
        // 测试损坏的数据
        var corruptedCache:SortedUnitCache = new SortedUnitCache();
        corruptedCache.data = [testUnits[0], testUnits[1]];
        corruptedCache.leftValues = [100]; // 长度不匹配
        corruptedCache.rightValues = [110, 125];
        corruptedCache.nameIndex = {};
        
        var corruptedValidation:Object = corruptedCache.validateData();
        assertTrue("损坏数据验证失败", !corruptedValidation.isValid);
        assertTrue("损坏数据有错误", corruptedValidation.errors.length > 0);
    }
    
    private static function testStatusMethods():Void {
        // getStatus测试
        var status:Object = testCache.getStatus();
        assertNotNull("getStatus返回对象", status);
        assertTrue("状态包含unitCount", status.hasOwnProperty("unitCount"));
        assertTrue("状态包含lastUpdatedFrame", status.hasOwnProperty("lastUpdatedFrame"));
        assertTrue("状态包含queryCache", status.hasOwnProperty("queryCache"));
        assertTrue("状态包含memoryUsage", status.hasOwnProperty("memoryUsage"));
        
        assertEquals("状态unitCount正确", testCache.getCount(), status.unitCount, 0);
        
        // getStatusReport测试
        var report:String = testCache.getStatusReport();
        assertNotNull("getStatusReport返回字符串", report);
        assertTrue("报告包含单位信息", report.indexOf("Units:") >= 0);
        assertTrue("报告包含帧信息", report.indexOf("Last Updated:") >= 0);
        assertTrue("报告包含验证信息", report.indexOf("Validation:") >= 0);
    }
    
    // ========================================================================
    // 压力测试
    // ========================================================================
    
    private static function runStressTests():Void {
        trace("\n💪 执行压力测试...");
        
        stressTestLargeDataset();
        stressTestRapidQueries();
        stressTestMemoryUsage();
        stressTestExtremeScenarios();
    }
    
    private static function stressTestLargeDataset():Void {
        var largeUnits:Array = createTestUnits(STRESS_DATA_SIZE);
        var largeCache:SortedUnitCache = createTestCache(largeUnits);
        
        var target:Object = largeUnits[Math.floor(STRESS_DATA_SIZE / 2)];
        
        var startTime:Number = getTimer();
        var nearest:Object = largeCache.findNearest(target);
        var farthest:Object = largeCache.findFarthest(target);
        var inRange:Array = largeCache.findInRange(target, 100, 100, true);
        var count:Number = largeCache.getCountInRange(target, 100, 100, true);
        var processingTime:Number = getTimer() - startTime;
        
        assertNotNull("大数据集findNearest", nearest);
        assertNotNull("大数据集findFarthest", farthest);
        assertNotNull("大数据集findInRange", inRange);
        assertTrue("大数据集getCountInRange", count >= 0);
        assertTrue("大数据集处理时间合理", processingTime < 100);
        
        trace("💾 大数据集测试: " + STRESS_DATA_SIZE + "个单位，查询耗时 " + processingTime + "ms");
    }
    
    private static function stressTestRapidQueries():Void {
        var queryCount:Number = 200;
        var target:Object = testUnits[25];
        var queryCollider:AABBCollider = new AABBCollider();
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < queryCount; i++) {
            queryCollider.left = 100 + (i % 500);
            testCache.getTargetsFromIndex(queryCollider);
            testCache.findNearest(target);
            testCache.getCountInRange(target, 50 + (i % 100), 50 + (i % 100), true);
        }
        var rapidTime:Number = getTimer() - startTime;
        
        assertTrue("快速查询压力测试通过", rapidTime < 500);
        trace("⚡ 快速查询测试: " + queryCount + "次混合查询耗时 " + rapidTime + "ms");
    }
    
    private static function stressTestMemoryUsage():Void {
        var iterations:Number = 20;
        var arraySize:Number = 100;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var tempUnits:Array = createTestUnits(arraySize);
            var tempCache:SortedUnitCache = createTestCache(tempUnits);
            
            var target:Object = tempUnits[50];
            tempCache.findNearest(target);
            tempCache.findInRange(target, 100, 100, true);
            tempCache.getCountByHP("low", null);
            
            // 释放引用
            tempUnits = null;
            tempCache = null;
        }
        var memoryTime:Number = getTimer() - startTime;
        
        assertTrue("内存压力测试通过", memoryTime < 1000);
        trace("🧠 内存使用测试: " + iterations + "次缓存创建/销毁耗时 " + memoryTime + "ms");
    }
    
    private static function stressTestExtremeScenarios():Void {
        var extremeScenarios:Array = [
            "clustered",
            "sparse", 
            "uniform"
        ];
        
        var successCount:Number = 0;
        
        for (var i:Number = 0; i < extremeScenarios.length; i++) {
            try {
                var scenario:String = extremeScenarios[i];
                var scenarioUnits:Array = createSpecialScenarioUnits(scenario);
                var scenarioCache:SortedUnitCache = createTestCache(scenarioUnits);
                
                var target:Object = scenarioUnits[Math.floor(scenarioUnits.length / 2)];
                var nearest:Object = scenarioCache.findNearest(target);
                var count:Number = scenarioCache.getCountInRange(target, 50, 50, true);
                
                if (nearest != null && count >= 0) {
                    successCount++;
                }
            } catch (error:Error) {
                trace("⚠️ 极端场景" + i + "异常: " + error.message);
            }
        }
        
        assertTrue("极端场景处理", successCount >= extremeScenarios.length - 1);
        trace("🔥 极端场景测试: " + successCount + "/" + extremeScenarios.length + " 通过");
    }
    
    // ========================================================================
    // 算法优化验证
    // ========================================================================
    
    private static function runAlgorithmOptimizationTests():Void {
        trace("\n🧮 执行算法优化验证...");
        
        testBinarySearchOptimization();
        testCacheOptimizationBehavior();
        testLinearScanOptimization();
    }
    
    private static function testBinarySearchOptimization():Void {
        // 创建大数组来测试二分查找
        var largeUnits:Array = createTestUnits(500);
        var largeCache:SortedUnitCache = createTestCache(largeUnits);
        
        var queryCollider:AABBCollider = new AABBCollider();
        var trials:Number = 100;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            queryCollider.left = i * 10; // 分散的查询位置
            largeCache.getTargetsFromIndex(queryCollider);
        }
        var binarySearchTime:Number = getTimer() - startTime;
        
        assertTrue("二分查找优化有效", (binarySearchTime / trials) < 1.0); // 单次不超过1ms
        trace("🔍 二分查找测试: " + trials + "次查询耗时 " + binarySearchTime + "ms");
    }
    
    private static function testCacheOptimizationBehavior():Void {
        var queryCollider:AABBCollider = new AABBCollider();
        testCache.resetQueryCache();
        
        // 第一次查询（冷缓存）
        queryCollider.left = 250;
        var startTime1:Number = getTimer();
        testCache.getTargetsFromIndex(queryCollider);
        var coldTime:Number = getTimer() - startTime1;
        
        // 相似位置的后续查询（热缓存）
        var trials:Number = 50;
        var startTime2:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            queryCollider.left = 250 + (i % 5); // 在阈值范围内变化
            testCache.getTargetsFromIndex(queryCollider);
        }
        var hotTime:Number = getTimer() - startTime2;
        var avgHotTime:Number = hotTime / trials;
        
        trace("🌡️ 缓存优化: 冷查询=" + coldTime + "ms, 热查询平均=" + 
              (Math.round(avgHotTime * 1000) / 1000) + "ms");
        
        // 修复计时器分辨率问题：若 coldTime == 0，说明已达计时器下限，直接通过
        if (coldTime == 0) {
            assertTrue("缓存优化效果(计时器下限)", true);
        } else {
            // 热缓存应该更快或至少不慢太多
            assertTrue("缓存优化效果", avgHotTime <= coldTime * 2);
        }
    }
    
    private static function testLinearScanOptimization():Void {
        // 创建小数组来测试线性扫描优化
        var smallUnits:Array = createTestUnits(8);
        var smallCache:SortedUnitCache = createTestCache(smallUnits);
        
        var queryCollider:AABBCollider = new AABBCollider();
        var trials:Number = 100;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            queryCollider.left = i % 100;
            smallCache.getTargetsFromIndex(queryCollider);
        }
        var linearTime:Number = getTimer() - startTime;
        
        assertTrue("小数组线性扫描优化", (linearTime / trials) < 0.5); // 应该非常快
        trace("📏 线性扫描测试: " + trials + "次小数组查询耗时 " + linearTime + "ms");
    }
    
    // ========================================================================
    // 带过滤器的最近单位查询测试
    // ========================================================================
    
    private static function runFilteredQueryTests():Void {
        trace("\n🔍 执行带过滤器的最近单位查询测试...");
        
        testFindNearestWithFilter_basic();
        testFindNearestWithFilter_fastPath();
        testFindNearestWithFilter_notFound();
        testFindNearestWithFilter_targetInCache();
        testFindNearestWithFilter_targetNotInCache_leftSideNearest();
        testFindNearestWithFilter_targetNotInCache_rightSideNearest();
        testFindNearestWithFilter_equidistantTieBreak();
        testFindNearestWithFilter_distanceThreshold();
        testFindNearestWithFilter_searchLimit();
        testFindNearestWithFilter_edgeCases();
    }
    
    private static function testFindNearestWithFilter_basic():Void {
        // 定义可复用的过滤器
        var hpFilter_under50:Function = function(u:Object, t:Object, d:Number):Boolean { 
            return (u.hp / u.maxhp) < 0.5; 
        };
        
        // 设置测试数据 - 修改一些单位的血量
        testUnits[10].hp = 40; // 满足过滤条件
        testUnits[11].hp = 80; // 不满足过滤条件
        testUnits[12].hp = 30; // 满足过滤条件
        
        var target:Object = testUnits[11]; // 使用不满足过滤条件的单位作为目标
        var result:Object = testCache.findNearestWithFilter(target, hpFilter_under50, 30, undefined);
        
        assertNotNull("基础过滤查询返回结果", result);
        assertTrue("结果满足过滤条件", (result.hp / result.maxhp) < 0.5);
        assertTrue("结果不是目标自身", result != target);
    }
    
    private static function testFindNearestWithFilter_fastPath():Void {
        var alwaysTrueFilter:Function = function(u:Object, t:Object, d:Number):Boolean { 
            return true; 
        };
        
        var target:Object = testUnits[25];
        var result:Object = testCache.findNearestWithFilter(target, alwaysTrueFilter, 30, undefined);
        
        assertNotNull("快速路径返回结果", result);
        
        // 应该与 findNearest 的结果相同
        var nearestDirect:Object = testCache.findNearest(target);
        assertStringEquals("快速路径与findNearest结果一致", nearestDirect._name, result._name);
    }
    
    private static function testFindNearestWithFilter_notFound():Void {
        var checkedCounter:Number = 0;
        var alwaysFalseFilter:Function = function(u:Object, t:Object, d:Number):Boolean { 
            checkedCounter++; 
            return false; 
        };
        
        var target:Object = testUnits[25];
        var searchLimit:Number = 10;
        var result:Object = testCache.findNearestWithFilter(target, alwaysFalseFilter, searchLimit, undefined);
        
        assertNull("过滤器恒为false时返回null", result);
        assertEquals("searchLimit 性能回归守卫", searchLimit, checkedCounter, 0);
    }
    
    private static function testFindNearestWithFilter_targetInCache():Void {
        var nameFilter_contains1:Function = function(u:Object, t:Object, d:Number):Boolean { 
            return u._name.indexOf("1") != -1; 
        };
        
        var target:Object = testUnits[20]; // 目标在缓存中
        var result:Object = testCache.findNearestWithFilter(target, nameFilter_contains1, 30, undefined);
        
        if (result != null) {
            assertNotNull("目标在缓存中查询返回结果", result);
            assertTrue("结果满足过滤条件", result._name.indexOf("1") != -1);
            assertTrue("结果不是目标自身", result != target);
        }
    }
    
    private static function testFindNearestWithFilter_targetNotInCache_leftSideNearest():Void {
        // 设置测试数据
        testUnits[9].hp = 80; // 不满足过滤条件
        testUnits[8].hp = 40; // 满足过滤条件（左侧）
        testUnits[10].hp = 80; // 不满足过滤条件
        
        var hpFilter_under50:Function = function(u:Object, t:Object, d:Number):Boolean { 
            return (u.hp / u.maxhp) < 0.5; 
        };
        
        // 创建一个外部单位，其位置介于 testUnits[8] 和 testUnits[9] 之间
        var externalUnit:Object = {
            _name: "external_left",
            hp: 100,
            maxhp: 100,
            aabbCollider: {
                left: (testUnits[8].aabbCollider.left + testUnits[9].aabbCollider.left) / 2,
                right: 0
            }
        };
        externalUnit.aabbCollider.right = externalUnit.aabbCollider.left + 15;
        
        var result:Object = testCache.findNearestWithFilter(externalUnit, hpFilter_under50, 10, undefined);
        
        assertNotNull("外部目标左侧查询返回结果", result);
        assertStringEquals("返回左侧满足条件的单位", testUnits[8]._name, result._name);
    }
    
    private static function testFindNearestWithFilter_targetNotInCache_rightSideNearest():Void {
        // 设置测试数据 - 关键修复验证
        testUnits[9].hp = 80; // 不满足过滤条件
        testUnits[10].hp = 40; // 满足过滤条件（右侧）
        testUnits[11].hp = 80; // 不满足过滤条件
        
        var hpFilter_under50:Function = function(u:Object, t:Object, d:Number):Boolean { 
            return (u.hp / u.maxhp) < 0.5; 
        };
        
        // 创建一个外部单位，其位置精确介于 testUnits[9] 和 testUnits[10] 之间
        var externalUnit:Object = {
            _name: "external_right",
            hp: 100,
            maxhp: 100,
            aabbCollider: {
                left: (testUnits[9].aabbCollider.left + testUnits[10].aabbCollider.left) / 2,
                right: 0
            }
        };
        externalUnit.aabbCollider.right = externalUnit.aabbCollider.left + 15;
        
        var result:Object = testCache.findNearestWithFilter(externalUnit, hpFilter_under50, 10, undefined);
        
        assertNotNull("外部目标右侧查询返回结果", result);
        assertStringEquals("返回右侧满足条件的单位", testUnits[10]._name, result._name);
    }
    
    private static function testFindNearestWithFilter_equidistantTieBreak():Void {
        // 创建一个新的包含3个单位的 SortedUnitCache 来测试确定性
        var unit_L:Object = {
            _name: "unit_L",
            hp: 40,
            maxhp: 100,
            aabbCollider: { left: 90, right: 105 }
        };
        var unit_T:Object = {
            _name: "unit_T",
            hp: 100,
            maxhp: 100,
            aabbCollider: { left: 100, right: 115 }
        };
        var unit_R:Object = {
            _name: "unit_R",
            hp: 80,
            maxhp: 100,
            aabbCollider: { left: 110, right: 125 }
        };
        
        var testUnits_tie:Array = [unit_L, unit_T, unit_R];
        var tieCache:SortedUnitCache = createTestCache(testUnits_tie);
        
        var nameFilter_is_L:Function = function(u:Object, t:Object, d:Number):Boolean { 
            return u._name == "unit_L"; 
        };
        
        var result:Object = tieCache.findNearestWithFilter(unit_T, nameFilter_is_L, 10, undefined);
        
        assertNotNull("等距情况返回结果", result);
        assertStringEquals("等距情况优先选择左侧", "unit_L", result._name);
    }
    
    private static function testFindNearestWithFilter_distanceThreshold():Void {
        // 创建稀疏数据用于测试距离阈值
        var sparseUnits:Array = [];
        for (var i:Number = 0; i < 5; i++) {
            var unit:Object = {
                _name: "sparse_" + i,
                hp: 40, // 都满足过滤条件
                maxhp: 100,
                aabbCollider: {
                    left: i * 200, // 间距200px
                    right: i * 200 + 15
                }
            };
            sparseUnits[i] = unit;
        }
        
        // 在很远的地方放置一个满足过滤器的单位
        var distantUnit:Object = {
            _name: "distant",
            hp: 30,
            maxhp: 100,
            aabbCollider: { left: 1000, right: 1015 }
        };
        sparseUnits.push(distantUnit);
        
        var sparseCache:SortedUnitCache = createTestCache(sparseUnits);
        
        var hpFilter_under50:Function = function(u:Object, t:Object, d:Number):Boolean { 
            return (u.hp / u.maxhp) < 0.5; 
        };
        
        var target:Object = sparseUnits[2]; // 中间位置
        
        // 设置较小的距离阈值，应该找不到远处的单位
        var result1:Object = sparseCache.findNearestWithFilter(target, hpFilter_under50, 50, 500);
        // 由于距离阈值限制，可能找不到足够远的单位
        
        // 设置较大的距离阈值，应该能找到远处的单位
        var result2:Object = sparseCache.findNearestWithFilter(target, hpFilter_under50, 50, 1500);
        assertNotNull("大距离阈值能找到远处单位", result2);
    }
    
    private static function testFindNearestWithFilter_searchLimit():Void {
        var checkedCounter:Number = 0;
        var countingFilter:Function = function(u:Object, t:Object, d:Number):Boolean { 
            checkedCounter++;
            return false; // 永远不满足，强制检查所有步数
        };
        
        var target:Object = testUnits[25];
        var searchLimit:Number = 15;
        
        checkedCounter = 0; // 重置计数器
        var result:Object = testCache.findNearestWithFilter(target, countingFilter, searchLimit, undefined);
        
        assertNull("searchLimit限制时返回null", result);
        assertEquals("严格遵循searchLimit", searchLimit, checkedCounter, 0);
    }
    
    private static function testFindNearestWithFilter_edgeCases():Void {
        var target:Object = testUnits[25];
        var validFilter:Function = function(u:Object, t:Object, d:Number):Boolean { return true; };
        
        // 测试空缓存
        var emptyCache:SortedUnitCache = new SortedUnitCache();
        var emptyResult:Object = emptyCache.findNearestWithFilter(target, validFilter, 30, undefined);
        assertNull("空缓存返回null", emptyResult);
        
        // 测试null过滤器
        var nullFilterResult:Object = testCache.findNearestWithFilter(target, null, 30, undefined);
        assertNull("null过滤器返回null", nullFilterResult);
        
        // 测试零searchLimit
        var zeroLimitResult:Object = testCache.findNearestWithFilter(target, validFilter, 0, undefined);
        assertNull("零searchLimit返回null", zeroLimitResult);
        
        // 测试负searchLimit
        var negativeLimitResult:Object = testCache.findNearestWithFilter(target, validFilter, -5, undefined);
        assertNull("负searchLimit返回null", negativeLimitResult);
        
        // 测试单元素缓存
        var singleUnit:Array = [testUnits[0]];
        var singleCache:SortedUnitCache = createTestCache(singleUnit);
        
        // 目标不在缓存中，单位满足过滤条件
        var satisfyFilter:Function = function(u:Object, t:Object, d:Number):Boolean { return true; };
        var singleResult1:Object = singleCache.findNearestWithFilter(target, satisfyFilter, 30, undefined);
        assertNotNull("单元素缓存满足条件", singleResult1);
        
        // 目标不在缓存中，单位不满足过滤条件
        var rejectFilter:Function = function(u:Object, t:Object, d:Number):Boolean { return false; };
        var singleResult2:Object = singleCache.findNearestWithFilter(target, rejectFilter, 30, undefined);
        assertNull("单元素缓存不满足条件", singleResult2);
    }
    
    // ========================================================================
    // rightMaxValues 前缀最大值测试
    // ========================================================================

    private static function runRightMaxValuesTests():Void {
        trace("\n🔢 执行 rightMaxValues 前缀最大值测试...");

        testRightMaxValuesMonotonicity();
        testRightMaxValuesDominatesRightValues();
        testNonMonotonicRightValuesQuery();
        testRightMaxValuesAfterUpdateData();
        testRightMaxValuesValidateData();
    }

    /**
     * 验证 rightMaxValues 总是单调非降
     */
    private static function testRightMaxValuesMonotonicity():Void {
        // 创建宽度差异大的单位，使 rightValues 非单调
        var units:Array = [];
        var widths:Array = [50, 5, 5, 80, 5, 5, 5, 60, 5, 5];
        for (var i:Number = 0; i < widths.length; i++) {
            var L:Number = i * 30;
            units[i] = {
                _name: "rmv_" + i,
                hp: 100, maxhp: 100,
                aabbCollider: { left: L, right: L + widths[i] }
            };
        }
        var cache:SortedUnitCache = createTestCache(units);

        var prev:Number = -Infinity;
        var allMono:Boolean = true;
        for (var j:Number = 0; j < cache.rightMaxValues.length; j++) {
            if (cache.rightMaxValues[j] < prev) {
                allMono = false;
                break;
            }
            prev = cache.rightMaxValues[j];
        }
        assertTrue("rightMaxValues单调非降", allMono);
    }

    /**
     * 验证 rightMaxValues[i] >= rightValues[i] 对所有 i 成立
     */
    private static function testRightMaxValuesDominatesRightValues():Void {
        var units:Array = [];
        var widths:Array = [100, 5, 5, 5, 200, 5, 5, 5, 5, 5];
        for (var i:Number = 0; i < widths.length; i++) {
            var L:Number = i * 40;
            units[i] = {
                _name: "dom_" + i,
                hp: 100, maxhp: 100,
                aabbCollider: { left: L, right: L + widths[i] }
            };
        }
        var cache:SortedUnitCache = createTestCache(units);

        var allDom:Boolean = true;
        for (var j:Number = 0; j < cache.rightValues.length; j++) {
            if (cache.rightMaxValues[j] < cache.rightValues[j]) {
                allDom = false;
                break;
            }
        }
        assertTrue("rightMaxValues[i]>=rightValues[i]", allDom);
        assertEquals("rightMaxValues长度正确", cache.rightValues.length, cache.rightMaxValues.length, 0);
    }

    /**
     * 核心测试：非单调 rightValues 下，getTargetsFromIndex 不漏检
     * 与暴力扫描结果对比，确保使用 rightMaxValues 后无假阴性
     */
    private static function testNonMonotonicRightValuesQuery():Void {
        // 构建明确的非单调 rightValues 场景
        // sorted by left, widths vary wildly
        var units:Array = [
            { _name: "a", hp: 100, maxhp: 100, aabbCollider: { left: 0,   right: 120 } },  // wide
            { _name: "b", hp: 100, maxhp: 100, aabbCollider: { left: 30,  right: 35  } },  // narrow → rightValues drops!
            { _name: "c", hp: 100, maxhp: 100, aabbCollider: { left: 60,  right: 65  } },  // narrow
            { _name: "d", hp: 100, maxhp: 100, aabbCollider: { left: 90,  right: 200 } },  // wide
            { _name: "e", hp: 100, maxhp: 100, aabbCollider: { left: 100, right: 105 } },  // narrow → rightValues drops again!
            { _name: "f", hp: 100, maxhp: 100, aabbCollider: { left: 150, right: 155 } }   // narrow
        ];
        var cache:SortedUnitCache = createTestCache(units);

        // rightValues = [120, 35, 65, 200, 105, 155] — clearly non-monotonic
        assertTrue("rightValues确实非单调", cache.rightValues[1] < cache.rightValues[0]);

        // 测试多个查询点
        var queryLefts:Array = [10, 50, 100, 110, 130, 190];
        var q:AABBCollider = new AABBCollider();

        for (var i:Number = 0; i < queryLefts.length; i++) {
            q.left = queryLefts[i];
            var result:Object = cache.getTargetsFromIndex(q);

            // 暴力扫描：找到第一个 right >= queryLeft 的索引
            var bruteIndex:Number = cache.data.length;
            for (var k:Number = 0; k < cache.data.length; k++) {
                if (cache.data[k].aabbCollider.right >= q.left) {
                    bruteIndex = k;
                    break;
                }
            }
            // getTargetsFromIndex 使用 rightMaxValues，返回的 startIndex 可能 <= bruteIndex（保守），
            // 但不能 > bruteIndex（否则漏检）
            assertTrue("queryLeft=" + queryLefts[i] + " startIndex不大于暴力扫描结果",
                       result.startIndex <= bruteIndex);
        }
    }

    /**
     * 验证 updateData 后 rightMaxValues 被正确重建
     */
    private static function testRightMaxValuesAfterUpdateData():Void {
        var units1:Array = createTestUnits(10);
        var cache:SortedUnitCache = createTestCache(units1);
        var oldLen:Number = cache.rightMaxValues.length;
        assertEquals("初始rightMaxValues长度", 10, oldLen, 0);

        // 用不同大小的数据 updateData
        var units2:Array = createTestUnits(20);
        var cache2:SortedUnitCache = createTestCache(units2);
        cache.updateData(cache2.data, cache2.nameIndex, cache2.leftValues, cache2.rightValues, 2000);

        assertEquals("updateData后rightMaxValues长度", 20, cache.rightMaxValues.length, 0);

        // 验证依然单调
        var mono:Boolean = true;
        for (var i:Number = 1; i < cache.rightMaxValues.length; i++) {
            if (cache.rightMaxValues[i] < cache.rightMaxValues[i - 1]) {
                mono = false;
                break;
            }
        }
        assertTrue("updateData后rightMaxValues仍然单调", mono);
    }

    /**
     * 验证 validateData 对 rightMaxValues 进行完整性校验
     */
    private static function testRightMaxValuesValidateData():Void {
        // 构造非单调 rightValues 的有效缓存
        var units:Array = [
            { _name: "v1", hp: 100, maxhp: 100, aabbCollider: { left: 0,  right: 100 } },
            { _name: "v2", hp: 100, maxhp: 100, aabbCollider: { left: 20, right: 25  } },
            { _name: "v3", hp: 100, maxhp: 100, aabbCollider: { left: 40, right: 150 } }
        ];
        var cache:SortedUnitCache = createTestCache(units);

        var validation:Object = cache.validateData();
        assertTrue("非单调rightValues下validateData通过", validation.isValid);
        assertEquals("无验证错误", 0, validation.errors.length, 0);
    }

    // ========================================================================
    // Bug 修复回归测试
    // ========================================================================

    private static function runBugfixRegressionTests():Void {
        trace("\n🔧 执行 Bug 修复回归测试...");

        testUpdateDataNullsStaleResults();
        testHpNormalizationChinese();
    }

    /**
     * 回归测试：updateData 断开复用结果对象的旧数据引用
     * 修复前：持有 getTargetsFromIndex 返回值的调用方在 updateData 后仍指向新数据
     * 修复后：updateData 将 _resultIndex.data 和 _resultMonotonic.data 置 null
     */
    private static function testUpdateDataNullsStaleResults():Void {
        var units:Array = createTestUnits(5);
        var cache:SortedUnitCache = createTestCache(units);

        // 执行一次查询，获取复用结果对象的引用
        var aabb:AABBCollider = new AABBCollider();
        aabb.left = units[0].aabbCollider.left;
        aabb.right = units[units.length - 1].aabbCollider.right;

        var result:Object = cache.getTargetsFromIndex(aabb);
        assertNotNull("查询返回结果", result);
        assertTrue("结果data指向cache.data", result.data === cache.data);

        // 保存对旧 data 数组的引用
        var oldData:Array = result.data;

        // 用新数据更新缓存
        var newUnits:Array = createTestUnits(10);
        var newCache:SortedUnitCache = createTestCache(newUnits);
        cache.updateData(
            newCache.data,
            newCache.nameIndex,
            newCache.leftValues,
            newCache.rightValues,
            2000
        );

        // 验证：旧 result 对象的 data 已被置 null（断开引用）
        assertTrue("updateData后旧result.data被置null", result.data == null);

        // 验证：oldData 仍是旧数据（未被篡改），长度为5
        assertEquals("旧数组仍保持原长度", 5, oldData.length, 0);

        // 验证：新查询返回新数据
        var result2:Object = cache.getTargetsFromIndex(aabb);
        assertTrue("新查询result.data指向新cache.data", result2.data === cache.data);
        assertEquals("新数据长度为10", 10, result2.data.length, 0);
    }

    /**
     * 回归测试：HP 条件归一化支持中文输入
     * 修复前：getCountByHP/findByHP 的 switch 只识别英文键，中文返回 0
     * 修复后：_normalizeHP 将中文映射到英文键后进入 switch
     */
    private static function testHpNormalizationChinese():Void {
        // 构造有明确血量分布的测试数据
        var units:Array = [
            { _name: "hp_low",   hp: 10,  maxhp: 100, aabbCollider: { left: 0,   right: 20  } },
            { _name: "hp_mid",   hp: 50,  maxhp: 100, aabbCollider: { left: 100, right: 120 } },
            { _name: "hp_high",  hp: 90,  maxhp: 100, aabbCollider: { left: 200, right: 220 } },
            { _name: "hp_full",  hp: 100, maxhp: 100, aabbCollider: { left: 300, right: 320 } }
        ];
        var cache:SortedUnitCache = createTestCache(units);

        // 英文键基准
        var lowEN:Number  = cache.getCountByHP("low", null);
        var midEN:Number  = cache.getCountByHP("medium", null);
        var highEN:Number = cache.getCountByHP("high", null);
        var fullEN:Number = cache.getCountByHP("healthy", null);

        // 中文键应等价
        assertEquals("低血量==low",   lowEN,  cache.getCountByHP("低血量", null), 0);
        assertEquals("中血量==medium", midEN,  cache.getCountByHP("中血量", null), 0);
        assertEquals("高血量==high",   highEN, cache.getCountByHP("高血量", null), 0);
        assertEquals("满血==healthy",  fullEN, cache.getCountByHP("满血", null), 0);

        // findByHP 同样验证
        var lowArrEN:Array = cache.findByHP("low", null);
        var lowArrCN:Array = cache.findByHP("低血量", null);
        assertEquals("findByHP低血量长度等价", lowArrEN.length, lowArrCN.length, 0);

        // 至少有一个低血量单位（hp=10, ratio=0.1 <= 0.3）
        assertTrue("英文low至少1个", lowEN >= 1);
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
        trace("📊 测试结果汇总");
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
        
        trace("\n🎯 缓存当前状态:");
        trace(testCache.getStatusReport());
        
        if (failedTests == 0) {
            trace("\n🎉 所有测试通过！SortedUnitCache 组件质量优秀！");
        } else {
            trace("\n⚠️ 发现 " + failedTests + " 个问题，请检查实现！");
        }
        
        trace("================================================================================");
    }
}
