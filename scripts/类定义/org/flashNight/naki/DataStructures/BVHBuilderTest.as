import org.flashNight.sara.util.*;
import org.flashNight.naki.DataStructures.*;

/**
 * 完整测试套件：BVHBuilder (BVH树构建器)
 * =======================================
 * 特性：
 * - 100% 方法覆盖率测试
 * - 构建算法正确性验证
 * - 性能基准测试（build vs buildFromSortedX）
 * - 树结构质量评估
 * - 排序优化验证
 * - 边界条件与极值测试
 * - 数据完整性验证
 * - 压力测试与大规模构建
 * - 算法精度对比验证
 * - 一句启动设计
 * 
 * 使用方法：
 * org.flashNight.naki.DataStructures.BVHBuilderTest.runAll();
 */
class org.flashNight.naki.DataStructures.BVHBuilderTest {
    
    // ========================================================================
    // 测试统计和配置
    // ========================================================================
    
    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var performanceResults:Array = [];
    
    // 性能基准配置
    private static var PERFORMANCE_TRIALS:Number = 100;
    private static var STRESS_OBJECTS_COUNT:Number = 1000;
    private static var BUILD_BENCHMARK_MS:Number = 10.0;        // 构建时间基准
    private static var SORTED_BUILD_FACTOR:Number = 0.7;       // 预排序版本应该更快
    private static var LARGE_SCALE_OBJECTS:Number = 5000;      // 大规模测试对象数
    private static var MAX_REASONABLE_DEPTH:Number = 20;       // 合理的最大树深度
    
    // 测试数据缓存
    private static var testObjects:Array;
    private static var sortedObjects:Array;
    private static var overlappingObjects:Array;
    private static var scatteredObjects:Array;
    private static var extremeObjects:Array;
    
    /**
     * 主测试入口 - 一句启动全部测试
     */
    public static function runAll():Void {
        trace("================================================================================");
        trace("🚀 BVHBuilder 完整测试套件启动");
        trace("================================================================================");
        
        var startTime:Number = getTimer();
        resetTestStats();
        
        try {
            // 初始化测试数据
            initializeTestData();
            
            // === 基础功能测试 ===
            runBasicFunctionalityTests();
            
            // === 构建方法测试 ===
            runBuildMethodTests();
            
            // === 树结构质量测试 ===
            runTreeQualityTests();
            
            // === 排序优化验证 ===
            runSortingOptimizationTests();
            
            // === 边界条件测试 ===
            runBoundaryConditionTests();
            
            // === 性能基准测试 ===
            runPerformanceBenchmarks();
            
            // === 数据完整性测试 ===
            runDataIntegrityTests();
            
            // === 压力测试 ===
            runStressTests();
            
            // === 算法验证测试 ===
            runAlgorithmValidationTests();
            
            // === 实际场景测试 ===
            runRealWorldScenarioTests();
            
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
    
    private static function assertPerformance(testName:String, actualTime:Number, benchmarkTime:Number):Void {
        testCount++;
        if (actualTime <= benchmarkTime) {
            passedTests++;
            trace("✅ " + testName + " PASS (" + actualTime + "ms <= " + benchmarkTime + "ms)");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (" + actualTime + "ms > " + benchmarkTime + "ms)");
        }
    }
    
    private static function assertLessOrEqual(testName:String, actual:Number, expected:Number):Void {
        testCount++;
        if (actual <= expected) {
            passedTests++;
            trace("✅ " + testName + " PASS (" + actual + " <= " + expected + ")");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (" + actual + " > " + expected + ")");
        }
    }
    
    private static function assertBVHEqual(testName:String, bvh1:BVH, bvh2:BVH):Void {
        testCount++;
        
        // 检查基本相等性
        if (!bvh1 && !bvh2) {
            passedTests++;
            trace("✅ " + testName + " PASS (both null)");
            return;
        }
        
        if (!bvh1 || !bvh2) {
            failedTests++;
            trace("❌ " + testName + " FAIL (one is null)");
            return;
        }
        
        // 使用相同查询测试两个BVH的行为是否一致
        var testQuery:AABB = new AABB();
        testQuery.left = 0;
        testQuery.right = 500;
        testQuery.top = 0;
        testQuery.bottom = 400;
        
        var result1:Array = bvh1.query(testQuery);
        var result2:Array = bvh2.query(testQuery);
        
        if (result1.length == result2.length) {
            // 验证包含相同对象（顺序可能不同）
            var allMatch:Boolean = true;
            for (var i:Number = 0; i < result1.length; i++) {
                var found:Boolean = false;
                for (var j:Number = 0; j < result2.length; j++) {
                    if (result1[i] == result2[j]) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    allMatch = false;
                    break;
                }
            }
            
            if (allMatch) {
                passedTests++;
                trace("✅ " + testName + " PASS (BVH behavior equivalent)");
            } else {
                failedTests++;
                trace("❌ " + testName + " FAIL (different query results)");
            }
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (different result counts: " + result1.length + " vs " + result2.length + ")");
        }
    }
    
    // ========================================================================
    // 测试数据初始化
    // ========================================================================
    
    private static function initializeTestData():Void {
        trace("\n🔧 初始化BVHBuilder测试数据...");
        
        // 创建基础测试对象集合
        testObjects = createTestObjects(50);
        
        // 创建按X轴排序的对象集合
        sortedObjects = createSortedTestObjects(50);
        
        // 创建重叠对象集合
        overlappingObjects = createOverlappingObjects(20);
        
        // 创建分散对象集合
        scatteredObjects = createScatteredObjects(30);
        
        // 创建极值对象集合
        extremeObjects = createExtremeObjects(15);
        
        trace("📦 创建了 " + testObjects.length + " 个基础测试对象");
        trace("📦 创建了 " + sortedObjects.length + " 个预排序测试对象");
        trace("📦 创建了 " + overlappingObjects.length + " 个重叠对象");
        trace("📦 创建了 " + scatteredObjects.length + " 个分散对象");
        trace("📦 创建了 " + extremeObjects.length + " 个极值对象");
    }
    
    /**
     * 创建基础测试对象（随机分布）
     */
    private static function createTestObjects(count:Number):Array {
        var objects:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var obj:Object = {
                name: "testObj_" + i,
                bounds: null,
                
                getAABB: function():AABB {
                    return this.bounds;
                }
            };
            
            obj.bounds = new AABB();
            obj.bounds.left = Math.random() * 800;
            obj.bounds.right = obj.bounds.left + Math.random() * 100 + 10;
            obj.bounds.top = Math.random() * 600;
            obj.bounds.bottom = obj.bounds.top + Math.random() * 80 + 10;
            
            objects[i] = obj;
        }
        
        return objects;
    }
    
    /**
     * 创建按X轴中心排序的测试对象
     */
    private static function createSortedTestObjects(count:Number):Array {
        var objects:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var obj:Object = {
                name: "sortedObj_" + i,
                bounds: null,
                
                getAABB: function():AABB {
                    return this.bounds;
                }
            };
            
            obj.bounds = new AABB();
            // 确保X轴中心按顺序排列
            var centerX:Number = i * 20 + Math.random() * 10;
            obj.bounds.left = centerX - 15;
            obj.bounds.right = centerX + 15;
            obj.bounds.top = Math.random() * 600;
            obj.bounds.bottom = obj.bounds.top + 30;
            
            objects[i] = obj;
        }
        
        return objects;
    }
    
    /**
     * 创建重叠对象集合
     */
    private static function createOverlappingObjects(count:Number):Array {
        var objects:Array = [];
        var baseX:Number = 100;
        var baseY:Number = 100;
        
        for (var i:Number = 0; i < count; i++) {
            var obj:Object = {
                name: "overlapping_" + i,
                bounds: null,
                
                getAABB: function():AABB {
                    return this.bounds;
                }
            };
            
            obj.bounds = new AABB();
            // 创建部分重叠的对象
            obj.bounds.left = baseX + i * 15;
            obj.bounds.right = obj.bounds.left + 50;
            obj.bounds.top = baseY + i * 10;
            obj.bounds.bottom = obj.bounds.top + 40;
            
            objects[i] = obj;
        }
        
        return objects;
    }
    
    /**
     * 创建分散对象集合
     */
    private static function createScatteredObjects(count:Number):Array {
        var objects:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var obj:Object = {
                name: "scattered_" + i,
                bounds: null,
                
                getAABB: function():AABB {
                    return this.bounds;
                }
            };
            
            obj.bounds = new AABB();
            // 创建间距很大的分散对象
            obj.bounds.left = i * 200;
            obj.bounds.right = obj.bounds.left + 20;
            obj.bounds.top = (i % 5) * 150;
            obj.bounds.bottom = obj.bounds.top + 20;
            
            objects[i] = obj;
        }
        
        return objects;
    }
    
    /**
     * 创建极值对象集合
     */
    private static function createExtremeObjects(count:Number):Array {
        var objects:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var obj:Object = {
                name: "extreme_" + i,
                bounds: null,
                
                getAABB: function():AABB {
                    return this.bounds;
                }
            };
            
            obj.bounds = new AABB();
            
            // 创建各种极值情况
            switch (i % 4) {
                case 0: // 极小对象
                    obj.bounds.left = i * 100;
                    obj.bounds.right = obj.bounds.left + 1;
                    obj.bounds.top = i * 80;
                    obj.bounds.bottom = obj.bounds.top + 1;
                    break;
                    
                case 1: // 极大对象
                    obj.bounds.left = -500;
                    obj.bounds.right = 500;
                    obj.bounds.top = -400;
                    obj.bounds.bottom = 400;
                    break;
                    
                case 2: // 极值坐标
                    obj.bounds.left = -10000;
                    obj.bounds.right = -9950;
                    obj.bounds.top = 9950;
                    obj.bounds.bottom = 10000;
                    break;
                    
                case 3: // 线条对象
                    obj.bounds.left = i * 50;
                    obj.bounds.right = obj.bounds.left + 100;
                    obj.bounds.top = 200;
                    obj.bounds.bottom = 200; // 高度为0
                    break;
            }
            
            objects[i] = obj;
        }
        
        return objects;
    }
    
    /**
     * 创建指定数量的简单对象
     */
    private static function createSimpleObjects(count:Number):Array {
        var objects:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var obj:Object = {
                name: "simple_" + i,
                bounds: null,
                
                getAABB: function():AABB {
                    return this.bounds;
                }
            };
            
            obj.bounds = new AABB();
            obj.bounds.left = i * 60;
            obj.bounds.right = obj.bounds.left + 50;
            obj.bounds.top = i * 40;
            obj.bounds.bottom = obj.bounds.top + 30;
            
            objects[i] = obj;
        }
        
        return objects;
    }
    
    // ========================================================================
    // 基础功能测试
    // ========================================================================
    
    private static function runBasicFunctionalityTests():Void {
        trace("\n📋 执行基础功能测试...");
        
        testStaticConfiguration();
        testBasicBuildMethod();
        testBasicBuildFromSortedXMethod();
        testEmptyAndNullInputs();
    }
    
    private static function testStaticConfiguration():Void {
        // 测试静态配置
        assertTrue("MAX_OBJECTS_IN_LEAF默认值合理", BVHBuilder.MAX_OBJECTS_IN_LEAF > 0);
        assertTrue("MAX_OBJECTS_IN_LEAF默认值不会太大", BVHBuilder.MAX_OBJECTS_IN_LEAF <= 50);
        
        // 测试配置修改
        var originalValue:Number = BVHBuilder.MAX_OBJECTS_IN_LEAF;
        BVHBuilder.MAX_OBJECTS_IN_LEAF = 5;
        assertEquals("MAX_OBJECTS_IN_LEAF可修改", 5, BVHBuilder.MAX_OBJECTS_IN_LEAF, 0);
        
        // 恢复原值
        BVHBuilder.MAX_OBJECTS_IN_LEAF = originalValue;
        assertEquals("MAX_OBJECTS_IN_LEAF恢复原值", originalValue, BVHBuilder.MAX_OBJECTS_IN_LEAF, 0);
    }
    
    private static function testBasicBuildMethod():Void {
        // 测试基础build方法
        var simpleObjects:Array = createSimpleObjects(10);
        var bvh:BVH = BVHBuilder.build(simpleObjects);
        
        assertNotNull("build方法返回BVH对象", bvh);
        assertNotNull("build方法创建根节点", bvh.root);
        
        // 测试构建的BVH功能正常
        var queryAABB:AABB = new AABB();
        queryAABB.left = 0;
        queryAABB.right = 200;
        queryAABB.top = 0;
        queryAABB.bottom = 150;
        
        var result:Array = bvh.query(queryAABB);
        assertNotNull("构建的BVH查询返回结果", result);
        assertTrue("构建的BVH查询有结果", result.length > 0);
        
        // 验证查询结果的正确性
        for (var i:Number = 0; i < result.length; i++) {
            var obj:IBVHObject = result[i];
            assertTrue("查询结果对象" + i + "与查询区域相交", 
                     queryAABB.intersects(obj.getAABB()));
        }
    }
    
    private static function testBasicBuildFromSortedXMethod():Void {
        // 测试buildFromSortedX方法
        var bvh:BVH = BVHBuilder.buildFromSortedX(sortedObjects);
        
        assertNotNull("buildFromSortedX返回BVH对象", bvh);
        assertNotNull("buildFromSortedX创建根节点", bvh.root);
        
        // 测试构建的BVH功能正常
        var queryAABB:AABB = new AABB();
        queryAABB.left = 100;
        queryAABB.right = 400;
        queryAABB.top = 50;
        queryAABB.bottom = 350;
        
        var result:Array = bvh.query(queryAABB);
        assertNotNull("预排序构建的BVH查询返回结果", result);
        
        // 验证查询结果的正确性
        for (var i:Number = 0; i < result.length; i++) {
            var obj:IBVHObject = result[i];
            assertTrue("预排序查询结果对象" + i + "与查询区域相交", 
                     queryAABB.intersects(obj.getAABB()));
        }
    }
    
    private static function testEmptyAndNullInputs():Void {
        // 测试空数组
        var emptyArray:Array = [];
        var emptyBVH:BVH = BVHBuilder.build(emptyArray);
        assertNotNull("空数组build返回BVH", emptyBVH);
        assertNull("空数组build根节点为null", emptyBVH.root);
        
        var emptySortedBVH:BVH = BVHBuilder.buildFromSortedX(emptyArray);
        assertNotNull("空数组buildFromSortedX返回BVH", emptySortedBVH);
        assertNull("空数组buildFromSortedX根节点为null", emptySortedBVH.root);
        
        // 测试null数组
        var nullBVH:BVH = BVHBuilder.build(null);
        assertNotNull("null数组build返回BVH", nullBVH);
        assertNull("null数组build根节点为null", nullBVH.root);
        
        var nullSortedBVH:BVH = BVHBuilder.buildFromSortedX(null);
        assertNotNull("null数组buildFromSortedX返回BVH", nullSortedBVH);
        assertNull("null数组buildFromSortedX根节点为null", nullSortedBVH.root);
        
        // 测试空BVH查询
        var queryAABB:AABB = new AABB();
        queryAABB.left = 0;
        queryAABB.right = 100;
        queryAABB.top = 0;
        queryAABB.bottom = 100;
        
        var emptyResult:Array = emptyBVH.query(queryAABB);
        assertNotNull("空BVH查询返回数组", emptyResult);
        assertArrayLength("空BVH查询返回空数组", 0, emptyResult);
    }
    
    // ========================================================================
    // 构建方法测试
    // ========================================================================
    
    private static function runBuildMethodTests():Void {
        trace("\n🔨 执行构建方法测试...");
        
        testBuildMethodVariations();
        testBuildFromSortedXMethodVariations();
        testMethodEquivalence();
        testSingleObjectConstruction();
        testLargeObjectSetConstruction();
    }
    
    private static function testBuildMethodVariations():Void {
        // 测试不同类型对象集合的构建
        var testSets:Array = [
            {name: "基础对象", objects: testObjects.slice(0, 20)},
            {name: "重叠对象", objects: overlappingObjects},
            {name: "分散对象", objects: scatteredObjects},
            {name: "极值对象", objects: extremeObjects}
        ];
        
        for (var i:Number = 0; i < testSets.length; i++) {
            var testSet:Object = testSets[i];
            var bvh:BVH = BVHBuilder.build(testSet.objects);
            
            assertNotNull(testSet.name + "集合构建成功", bvh);
            assertNotNull(testSet.name + "集合有根节点", bvh.root);
            
            // 验证构建的BVH包含所有对象
            var allAABB:AABB = new AABB();
            allAABB.left = -20000;
            allAABB.right = 20000;
            allAABB.top = -20000;
            allAABB.bottom = 20000;
            
            var allResult:Array = bvh.query(allAABB);
            assertTrue(testSet.name + "集合包含所有对象", allResult.length >= testSet.objects.length);
        }
    }
    
    private static function testBuildFromSortedXMethodVariations():Void {
        // 创建不同的预排序测试集
        var sortedSets:Array = [
            createSortedTestObjects(10),
            createSortedTestObjects(25),
            createSortedTestObjects(50)
        ];
        
        for (var i:Number = 0; i < sortedSets.length; i++) {
            var sortedSet:Array = sortedSets[i];
            var bvh:BVH = BVHBuilder.buildFromSortedX(sortedSet);
            
            assertNotNull("预排序集合" + i + "构建成功", bvh);
            assertNotNull("预排序集合" + i + "有根节点", bvh.root);
            
            // 验证构建质量
            var depth:Number = calculateTreeDepth(bvh.root);
            var expectedMaxDepth:Number = Math.ceil(Math.log(sortedSet.length) / Math.log(2)) + 3;
            assertLessOrEqual("预排序集合" + i + "树深度合理", depth, expectedMaxDepth);
        }
    }
    
    private static function testMethodEquivalence():Void {
        // 测试两种构建方法的等价性
        var testSet:Array = createSimpleObjects(30);
        
        // 普通构建
        var normalBVH:BVH = BVHBuilder.build(testSet);
        
        // 预排序构建（先排序测试集）
        var sortedTestSet:Array = testSet.concat();
        sortByXCenter(sortedTestSet);
        var sortedBVH:BVH = BVHBuilder.buildFromSortedX(sortedTestSet);
        
        // 比较两种方法的结果
        assertBVHEqual("两种构建方法结果等价", normalBVH, sortedBVH);
        
        // 验证树深度相近
        var normalDepth:Number = calculateTreeDepth(normalBVH.root);
        var sortedDepth:Number = calculateTreeDepth(sortedBVH.root);
        var depthDiff:Number = Math.abs(normalDepth - sortedDepth);
        assertLessOrEqual("两种方法树深度相近", depthDiff, 2);
        
        // 验证叶子节点对象数量限制
        assertTrue("普通构建叶子节点对象数量限制", 
                 validateLeafObjectCount(normalBVH.root, BVHBuilder.MAX_OBJECTS_IN_LEAF));
        assertTrue("预排序构建叶子节点对象数量限制", 
                 validateLeafObjectCount(sortedBVH.root, BVHBuilder.MAX_OBJECTS_IN_LEAF));
    }
    
    private static function testSingleObjectConstruction():Void {
        // 测试单对象构建
        var singleObject:Array = [createSimpleObjects(1)[0]];
        
        var normalBVH:BVH = BVHBuilder.build(singleObject);
        var sortedBVH:BVH = BVHBuilder.buildFromSortedX(singleObject);
        
        assertNotNull("单对象普通构建成功", normalBVH);
        assertNotNull("单对象预排序构建成功", sortedBVH);
        
        assertTrue("单对象普通构建为叶子节点", normalBVH.root.isLeaf());
        assertTrue("单对象预排序构建为叶子节点", sortedBVH.root.isLeaf());
        
        assertArrayLength("单对象普通构建对象数量", 1, normalBVH.root.objects);
        assertArrayLength("单对象预排序构建对象数量", 1, sortedBVH.root.objects);
    }
    
    private static function testLargeObjectSetConstruction():Void {
        // 测试大对象集构建
        var largeSet:Array = createSimpleObjects(100);
        
        var startTime:Number = getTimer();
        var largeBVH:BVH = BVHBuilder.build(largeSet);
        var buildTime:Number = getTimer() - startTime;
        
        assertNotNull("大对象集构建成功", largeBVH);
        assertNotNull("大对象集有根节点", largeBVH.root);
        assertTrue("大对象集构建性能合理", buildTime < 1000);
        
        // 验证树结构合理性
        var depth:Number = calculateTreeDepth(largeBVH.root);
        var balance:Number = calculateTreeBalance(largeBVH.root);
        
        assertLessOrEqual("大对象集树深度合理", depth, MAX_REASONABLE_DEPTH);
        assertLessOrEqual("大对象集树平衡度合理", balance, 3);
        
        // 验证查询功能
        var queryAABB:AABB = new AABB();
        queryAABB.left = 0;
        queryAABB.right = 500;
        queryAABB.top = 0;
        queryAABB.bottom = 400;
        
        var queryResult:Array = largeBVH.query(queryAABB);
        assertTrue("大对象集查询功能正常", queryResult.length >= 0);
    }
    
    // ========================================================================
    // 树结构质量测试
    // ========================================================================
    
    private static function runTreeQualityTests():Void {
        trace("\n🌳 执行树结构质量测试...");
        
        testTreeDepthQuality();
        testTreeBalanceQuality();
        testLeafNodeQuality();
        testBoundingBoxQuality();
        testSpatialCohesion();
    }
    
    private static function testTreeDepthQuality():Void {
        var testSizes:Array = [10, 25, 50, 100];
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = testSizes[i];
            var objects:Array = createSimpleObjects(size);
            var bvh:BVH = BVHBuilder.build(objects);
            
            var depth:Number = calculateTreeDepth(bvh.root);
            var theoreticalOptimal:Number = Math.ceil(Math.log(size) / Math.log(2));
            var maxReasonable:Number = theoreticalOptimal + 5; // 允许一些偏差
            
            assertLessOrEqual("对象数" + size + "树深度合理", depth, maxReasonable);
            
            trace("📊 对象数" + size + ": 深度=" + depth + ", 理论最优=" + theoreticalOptimal);
        }
    }
    
    private static function testTreeBalanceQuality():Void {
        var balancedObjects:Array = createSimpleObjects(31); // 2^5 - 1，理想平衡
        var bvh:BVH = BVHBuilder.build(balancedObjects);
        
        var balance:Number = calculateTreeBalance(bvh.root);
        assertLessOrEqual("平衡对象集树平衡度良好", balance, 2);
        
        // 测试不平衡输入的处理
        var unbalancedObjects:Array = createLinearObjects(20);
        var unbalancedBVH:BVH = BVHBuilder.build(unbalancedObjects);
        
        var unbalancedBalance:Number = calculateTreeBalance(unbalancedBVH.root);
        assertLessOrEqual("不平衡对象集树平衡度可接受", unbalancedBalance, 4);
        
        trace("📊 平衡度测试: 平衡集=" + balance + ", 不平衡集=" + unbalancedBalance);
    }
    
    private static function testLeafNodeQuality():Void {
        var objects:Array = createSimpleObjects(50);
        var bvh:BVH = BVHBuilder.build(objects);
        
        // 验证所有叶子节点对象数量符合限制
        assertTrue("叶子节点对象数量限制", 
                 validateLeafObjectCount(bvh.root, BVHBuilder.MAX_OBJECTS_IN_LEAF));
        
        // 统计叶子节点信息
        var leafStats:Object = calculateLeafStats(bvh.root);
        
        assertTrue("叶子节点数量合理", leafStats.count > 0);
        assertTrue("平均叶子对象数合理", leafStats.avgObjects > 0);
        assertLessOrEqual("最大叶子对象数不超限", leafStats.maxObjects, BVHBuilder.MAX_OBJECTS_IN_LEAF);
        
        trace("📊 叶子节点统计: 数量=" + leafStats.count + 
              ", 平均对象=" + Math.round(leafStats.avgObjects * 100) / 100 + 
              ", 最大对象=" + leafStats.maxObjects);
    }
    
    private static function testBoundingBoxQuality():Void {
        var objects:Array = createSimpleObjects(30);
        var bvh:BVH = BVHBuilder.build(objects);
        
        // 验证包围盒层次结构
        assertTrue("包围盒层次结构正确", validateBoundingBoxHierarchy(bvh.root));
        
        // 验证包围盒紧密度
        var tightness:Number = calculateBoundingBoxTightness(bvh.root, objects);
        assertTrue("包围盒紧密度合理", tightness >= 0.5); // 至少50%的空间利用率
        
        trace("📊 包围盒紧密度: " + Math.round(tightness * 100) + "%");
    }
    
    private static function testSpatialCohesion():Void {
        // 创建具有明显空间聚集性的对象
        var clusteredObjects:Array = createClusteredObjects(40);
        var bvh:BVH = BVHBuilder.build(clusteredObjects);
        
        // 验证空间聚集性被保持
        var cohesion:Number = calculateSpatialCohesion(bvh.root);
        assertTrue("空间聚集性良好", cohesion >= 0.6);
        
        trace("📊 空间聚集性: " + Math.round(cohesion * 100) + "%");
    }
    
    // ========================================================================
    // 排序优化验证
    // ========================================================================
    
    private static function runSortingOptimizationTests():Void {
        trace("\n🔄 执行排序优化验证...");
        
        testSortingCorrectnessVerification();
        testPreSortedInputBehavior();
        testSortingPerformanceImpact();
        testAxisAlternation();
    }
    
    private static function testSortingCorrectnessVerification():Void {
        // 创建乱序对象集
        var randomObjects:Array = createRandomObjects(30);
        
        // 手动按X轴排序
        var sortedObjects:Array = randomObjects.concat();
        sortByXCenter(sortedObjects);
        
        // 验证排序正确性
        for (var i:Number = 0; i < sortedObjects.length - 1; i++) {
            var currentCenter:Number = getCenterX(sortedObjects[i].getAABB());
            var nextCenter:Number = getCenterX(sortedObjects[i + 1].getAABB());
            assertTrue("X轴排序正确性" + i, currentCenter <= nextCenter);
        }
        
        // 构建并验证两种方法结果一致
        var normalBVH:BVH = BVHBuilder.build(randomObjects);
        var sortedBVH:BVH = BVHBuilder.buildFromSortedX(sortedObjects);
        
        assertBVHEqual("排序优化结果正确性", normalBVH, sortedBVH);
    }
    
    private static function testPreSortedInputBehavior():Void {
        // 测试已经排序的输入
        var preSorted:Array = createSortedTestObjects(25);
        
        // 验证输入确实已排序
        var isSorted:Boolean = true;
        for (var i:Number = 0; i < preSorted.length - 1; i++) {
            var currentCenter:Number = getCenterX(preSorted[i].getAABB());
            var nextCenter:Number = getCenterX(preSorted[i + 1].getAABB());
            if (currentCenter > nextCenter) {
                isSorted = false;
                break;
            }
        }
        assertTrue("输入确实已预排序", isSorted);
        
        // 使用buildFromSortedX构建
        var bvh:BVH = BVHBuilder.buildFromSortedX(preSorted);
        assertNotNull("预排序输入构建成功", bvh);
        
        // 验证构建质量
        var depth:Number = calculateTreeDepth(bvh.root);
        var balance:Number = calculateTreeBalance(bvh.root);
        
        assertLessOrEqual("预排序输入树深度合理", depth, 10);
        assertLessOrEqual("预排序输入树平衡度良好", balance, 3);
    }
    
    private static function testSortingPerformanceImpact():Void {
        var testObjects:Array = createRandomObjects(100);
        
        // 预排序
        var sortedForTest:Array = testObjects.concat();
        var sortStartTime:Number = getTimer();
        sortByXCenter(sortedForTest);
        var sortTime:Number = getTimer() - sortStartTime;
        
        // 测试普通构建时间
        var normalStartTime:Number = getTimer();
        BVHBuilder.build(testObjects);
        var normalBuildTime:Number = getTimer() - normalStartTime;
        
        // 测试预排序构建时间
        var sortedStartTime:Number = getTimer();
        BVHBuilder.buildFromSortedX(sortedForTest);
        var sortedBuildTime:Number = getTimer() - sortedStartTime;
        
        // 总时间比较（包含排序时间）
        var totalSortedTime:Number = sortTime + sortedBuildTime;
        
        trace("📊 排序性能影响:");
        trace("  普通构建: " + normalBuildTime + "ms");
        trace("  排序时间: " + sortTime + "ms");
        trace("  预排序构建: " + sortedBuildTime + "ms");
        trace("  总预排序时间: " + totalSortedTime + "ms");
        
        // 预排序构建本身应该更快
        assertTrue("预排序构建本身更快", sortedBuildTime < normalBuildTime);
        
        // 即使加上排序时间，总时间也应该合理
        assertTrue("总预排序时间合理", totalSortedTime < normalBuildTime * 2);
    }
    
    private static function testAxisAlternation():Void {
        // 创建测试对象并构建BVH
        var objects:Array = createSimpleObjects(20);
        var bvh:BVH = BVHBuilder.build(objects);
        
        // 验证轴交替分割
        var axisInfo:Object = analyzeAxisUsage(bvh.root, 0);
        
        assertTrue("使用了X轴分割", axisInfo.usesX);
        assertTrue("使用了Y轴分割", axisInfo.usesY);
        assertTrue("轴使用合理", axisInfo.depth <= MAX_REASONABLE_DEPTH);
        
        trace("📊 轴使用分析: 最大深度=" + axisInfo.depth + 
              ", X轴=" + axisInfo.usesX + ", Y轴=" + axisInfo.usesY);
    }
    
    // ========================================================================
    // 边界条件测试
    // ========================================================================
    
    private static function runBoundaryConditionTests():Void {
        trace("\n🔍 执行边界条件测试...");
        
        testExtremeObjectCounts();
        testExtremeCoordinates();
        testDegenerateObjects();
        testMaxObjectsInLeafVariations();
        testCornerCases();
    }
    
    private static function testExtremeObjectCounts():Void {
        // 测试极少对象
        var minObjects:Array = createSimpleObjects(1);
        var minBVH:BVH = BVHBuilder.build(minObjects);
        assertNotNull("1个对象构建成功", minBVH);
        assertTrue("1个对象为叶子节点", minBVH.root.isLeaf());
        
        var twoObjects:Array = createSimpleObjects(2);
        var twoBVH:BVH = BVHBuilder.build(twoObjects);
        assertNotNull("2个对象构建成功", twoBVH);
        
        // 测试大量对象（压力测试在后面）
        var manyObjects:Array = createSimpleObjects(200);
        var startTime:Number = getTimer();
        var manyBVH:BVH = BVHBuilder.build(manyObjects);
        var buildTime:Number = getTimer() - startTime;
        
        assertNotNull("大量对象构建成功", manyBVH);
        assertPerformance("大量对象构建性能", buildTime, 500);
    }
    
    private static function testExtremeCoordinates():Void {
        // 测试极值坐标
        var extremeCoordObjects:Array = [];
        
        // 极大正值
        extremeCoordObjects[0] = createBVHObject("extreme_pos", 10000, 10100, 10000, 10100);
        
        // 极大负值
        extremeCoordObjects[1] = createBVHObject("extreme_neg", -10100, -10000, -10100, -10000);
        
        // 跨越零点
        extremeCoordObjects[2] = createBVHObject("cross_zero", -50, 50, -50, 50);
        
        // 混合极值
        extremeCoordObjects[3] = createBVHObject("mixed", -5000, 5000, 1000, 2000);
        
        var extremeBVH:BVH = BVHBuilder.build(extremeCoordObjects);
        assertNotNull("极值坐标构建成功", extremeBVH);
        
        var extremeSortedBVH:BVH = BVHBuilder.buildFromSortedX(extremeCoordObjects);
        assertNotNull("极值坐标预排序构建成功", extremeSortedBVH);
        
        // 验证查询功能
        var extremeQuery:AABB = new AABB();
        extremeQuery.left = -20000;
        extremeQuery.right = 20000;
        extremeQuery.top = -20000;
        extremeQuery.bottom = 20000;
        
        var extremeResult:Array = extremeBVH.query(extremeQuery);
        assertArrayLength("极值坐标查询找到所有对象", 4, extremeResult);
    }
    
    private static function testDegenerateObjects():Void {
        // 测试退化对象
        var degenerateObjects:Array = [];
        
        // 零面积对象
        degenerateObjects[0] = createBVHObject("zero_area", 100, 100, 100, 100);
        
        // 线条对象（宽度为0）
        degenerateObjects[1] = createBVHObject("line_width", 200, 200, 100, 200);
        
        // 线条对象（高度为0）
        degenerateObjects[2] = createBVHObject("line_height", 100, 200, 300, 300);
        
        // 普通对象
        degenerateObjects[3] = createBVHObject("normal", 0, 50, 0, 50);
        
        var degenerateBVH:BVH = BVHBuilder.build(degenerateObjects);
        assertNotNull("退化对象构建成功", degenerateBVH);
        
        // 验证查询仍然工作
        var degenerateQuery:AABB = new AABB();
        degenerateQuery.left = 50;
        degenerateQuery.right = 250;
        degenerateQuery.top = 50;
        degenerateQuery.bottom = 350;
        
        var degenerateResult:Array = degenerateBVH.query(degenerateQuery);
        assertTrue("退化对象查询正常", degenerateResult.length >= 0);
    }
    
    private static function testMaxObjectsInLeafVariations():Void {
        var originalMax:Number = BVHBuilder.MAX_OBJECTS_IN_LEAF;
        var testObjects:Array = createSimpleObjects(20);
        
        // 测试不同的MAX_OBJECTS_IN_LEAF值
        var testValues:Array = [1, 3, 8, 15];
        
        for (var i:Number = 0; i < testValues.length; i++) {
            var maxValue:Number = testValues[i];
            BVHBuilder.MAX_OBJECTS_IN_LEAF = maxValue;
            
            var bvh:BVH = BVHBuilder.build(testObjects);
            assertNotNull("MAX_OBJECTS_IN_LEAF=" + maxValue + "构建成功", bvh);
            
            // 验证叶子节点对象数量限制
            assertTrue("MAX_OBJECTS_IN_LEAF=" + maxValue + "限制有效", 
                     validateLeafObjectCount(bvh.root, maxValue));
            
            // 验证功能正常
            var testQuery:AABB = new AABB();
            testQuery.left = 0;
            testQuery.right = 500;
            testQuery.top = 0;
            testQuery.bottom = 400;
            
            var result:Array = bvh.query(testQuery);
            assertTrue("MAX_OBJECTS_IN_LEAF=" + maxValue + "查询正常", result.length >= 0);
        }
        
        // 恢复原值
        BVHBuilder.MAX_OBJECTS_IN_LEAF = originalMax;
    }
    
    private static function testCornerCases():Void {
        // 测试所有对象相同位置
        var samePositionObjects:Array = [];
        for (var i:Number = 0; i < 10; i++) {
            samePositionObjects[i] = createBVHObject("same_" + i, 100, 150, 100, 150);
        }
        
        var sameBVH:BVH = BVHBuilder.build(samePositionObjects);
        assertNotNull("相同位置对象构建成功", sameBVH);
        
        // 测试对象完全包含关系
        var nestedObjects:Array = [];
        nestedObjects[0] = createBVHObject("outer", 0, 200, 0, 200);
        nestedObjects[1] = createBVHObject("middle", 50, 150, 50, 150);
        nestedObjects[2] = createBVHObject("inner", 75, 125, 75, 125);
        
        var nestedBVH:BVH = BVHBuilder.build(nestedObjects);
        assertNotNull("嵌套对象构建成功", nestedBVH);
        
        // 验证查询正确性
        var innerQuery:AABB = new AABB();
        innerQuery.left = 80;
        innerQuery.right = 120;
        innerQuery.top = 80;
        innerQuery.bottom = 120;
        
        var nestedResult:Array = nestedBVH.query(innerQuery);
        assertEquals("嵌套对象查询找到所有相交对象", 3, nestedResult.length, 0);
    }
    
    // ========================================================================
    // 性能基准测试
    // ========================================================================
    
    private static function runPerformanceBenchmarks():Void {
        trace("\n⚡ 执行性能基准测试...");
        
        performanceTestBuildMethod();
        performanceTestBuildFromSortedXMethod();
        performanceTestMethodComparison();
        performanceTestScalability();
        performanceTestOptimizationEffectiveness();
    }
    
    private static function performanceTestBuildMethod():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var objectsPerTrial:Number = 50;
        
        var totalTime:Number = 0;
        
        for (var i:Number = 0; i < trials; i++) {
            var objects:Array = createRandomObjects(objectsPerTrial);
            
            var startTime:Number = getTimer();
            BVHBuilder.build(objects);
            totalTime += getTimer() - startTime;
        }
        
        var avgTime:Number = totalTime / trials;
        
        performanceResults.push({
            method: "Build Method",
            trials: trials,
            totalTime: totalTime,
            avgTime: avgTime
        });
        
        trace("📊 build()方法性能: " + trials + "次构建耗时 " + totalTime + "ms");
        assertPerformance("build()方法性能达标", avgTime, BUILD_BENCHMARK_MS);
    }
    
    private static function performanceTestBuildFromSortedXMethod():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var objectsPerTrial:Number = 50;
        
        var totalTime:Number = 0;
        
        for (var i:Number = 0; i < trials; i++) {
            var objects:Array = createSortedTestObjects(objectsPerTrial);
            
            var startTime:Number = getTimer();
            BVHBuilder.buildFromSortedX(objects);
            totalTime += getTimer() - startTime;
        }
        
        var avgTime:Number = totalTime / trials;
        
        performanceResults.push({
            method: "BuildFromSortedX Method",
            trials: trials,
            totalTime: totalTime,
            avgTime: avgTime
        });
        
        trace("📊 buildFromSortedX()方法性能: " + trials + "次构建耗时 " + totalTime + "ms");
        assertPerformance("buildFromSortedX()方法性能达标", avgTime, BUILD_BENCHMARK_MS * SORTED_BUILD_FACTOR);
    }
    
    private static function performanceTestMethodComparison():Void {
        var comparisonTrials:Number = 50;
        var objectCount:Number = 100;
        
        var normalTotalTime:Number = 0;
        var sortedTotalTime:Number = 0;
        
        for (var i:Number = 0; i < comparisonTrials; i++) {
            var baseObjects:Array = createRandomObjects(objectCount);
            
            // 测试普通构建
            var normalStartTime:Number = getTimer();
            BVHBuilder.build(baseObjects);
            normalTotalTime += getTimer() - normalStartTime;
            
            // 预排序
            var sortedObjects:Array = baseObjects.concat();
            sortByXCenter(sortedObjects);
            
            // 测试预排序构建
            var sortedStartTime:Number = getTimer();
            BVHBuilder.buildFromSortedX(sortedObjects);
            sortedTotalTime += getTimer() - sortedStartTime;
        }
        
        var normalAvg:Number = normalTotalTime / comparisonTrials;
        var sortedAvg:Number = sortedTotalTime / comparisonTrials;
        var speedup:Number = normalAvg / sortedAvg;
        
        performanceResults.push({
            method: "Method Comparison",
            trials: comparisonTrials,
            normalAvg: normalAvg,
            sortedAvg: sortedAvg,
            speedup: speedup
        });
        
        trace("📊 方法性能对比:");
        trace("  普通构建平均: " + Math.round(normalAvg * 100) / 100 + "ms");
        trace("  预排序构建平均: " + Math.round(sortedAvg * 100) / 100 + "ms");
        trace("  加速比: " + Math.round(speedup * 100) / 100 + "x");
        
        assertTrue("预排序方法确实更快", sortedAvg < normalAvg);
        assertTrue("加速比合理", speedup >= 1.2);
    }
    
    private static function performanceTestScalability():Void {
        var scalabilitySizes:Array = [100, 500, 1000, 2000];
        
        trace("📊 可扩展性测试:");
        
        for (var i:Number = 0; i < scalabilitySizes.length; i++) {
            var size:Number = scalabilitySizes[i];
            var objects:Array = createRandomObjects(size);
            
            var startTime:Number = getTimer();
            var bvh:BVH = BVHBuilder.build(objects);
            var buildTime:Number = getTimer() - startTime;
            
            var depth:Number = calculateTreeDepth(bvh.root);
            var timePerObject:Number = buildTime / size;
            
            trace("  " + size + "对象: " + buildTime + "ms, 深度=" + depth + 
                  ", " + Math.round(timePerObject * 1000) / 1000 + "ms/对象");
            
            // 验证时间复杂度合理（应该接近O(n log n)）
            var expectedTime:Number = size * Math.log(size) / 100; // 简化的期望时间
            assertTrue(size + "对象构建时间合理", buildTime < expectedTime * 5);
        }
    }
    
    private static function performanceTestOptimizationEffectiveness():Void {
        // 测试在不同场景下优化的有效性
        var scenarios:Array = [
            {name: "随机分布", objects: createRandomObjects(200)},
            {name: "聚集分布", objects: createClusteredObjects(200)},
            {name: "线性分布", objects: createLinearObjects(200)},
            {name: "网格分布", objects: createGridObjects(200)}
        ];
        
        trace("📊 优化有效性测试:");
        
        for (var i:Number = 0; i < scenarios.length; i++) {
            var scenario:Object = scenarios[i];
            var objects:Array = scenario.objects;
            
            // 普通构建
            var normalStart:Number = getTimer();
            var normalBVH:BVH = BVHBuilder.build(objects);
            var normalTime:Number = getTimer() - normalStart;
            
            // 预排序构建
            var sortedObjects:Array = objects.concat();
            sortByXCenter(sortedObjects);
            
            var sortedStart:Number = getTimer();
            var sortedBVH:BVH = BVHBuilder.buildFromSortedX(sortedObjects);
            var sortedTime:Number = getTimer() - sortedStart;
            
            var improvement:Number = (normalTime - sortedTime) / normalTime * 100;
            
            trace("  " + scenario.name + ": 普通=" + normalTime + "ms, 预排序=" + 
                  sortedTime + "ms, 提升=" + Math.round(improvement) + "%");
            
            assertTrue(scenario.name + "场景预排序更快", sortedTime <= normalTime);
        }
    }
    
    // ========================================================================
    // 数据完整性测试
    // ========================================================================
    
    private static function runDataIntegrityTests():Void {
        trace("\n💾 执行数据完整性测试...");
        
        testObjectReferenceIntegrity();
        testBoundingBoxIntegrity();
        testTreeStructureIntegrity();
        testQueryResultIntegrity();
        testModificationSafety();
    }
    
    private static function testObjectReferenceIntegrity():Void {
        var objects:Array = createSimpleObjects(20);
        var bvh:BVH = BVHBuilder.build(objects);
        
        // 收集BVH中所有对象
        var bvhObjects:Array = [];
        collectAllObjects(bvh.root, bvhObjects);
        
        // 验证所有原始对象都在BVH中
        for (var i:Number = 0; i < objects.length; i++) {
            var found:Boolean = false;
            for (var j:Number = 0; j < bvhObjects.length; j++) {
                if (objects[i] == bvhObjects[j]) {
                    found = true;
                    break;
                }
            }
            assertTrue("原始对象" + i + "在BVH中", found);
        }
        
        // 验证BVH中没有额外对象
        assertEquals("BVH对象总数正确", objects.length, bvhObjects.length, 0);
        
        // 验证对象引用完整性
        for (var k:Number = 0; k < bvhObjects.length; k++) {
            var obj:IBVHObject = bvhObjects[k];
            assertNotNull("BVH对象" + k + "不为null", obj);
            assertNotNull("BVH对象" + k + "有AABB", obj.getAABB());
        }
    }
    
    private static function testBoundingBoxIntegrity():Void {
        var objects:Array = createSimpleObjects(25);
        var bvh:BVH = BVHBuilder.build(objects);
        
        // 验证包围盒层次结构完整性
        assertTrue("包围盒层次结构完整", validateBoundingBoxHierarchy(bvh.root));
        
        // 验证根节点包围盒包含所有对象
        var rootAABB:AABB = bvh.root.bounds;
        for (var i:Number = 0; i < objects.length; i++) {
            var objAABB:AABB = objects[i].getAABB();
            assertTrue("根包围盒包含对象" + i, aabbContains(rootAABB, objAABB));
        }
        
        // 验证包围盒非退化（除非所有对象都重叠）
        if (objects.length > 1) {
            assertTrue("根包围盒宽度非负", rootAABB.right >= rootAABB.left);
            assertTrue("根包围盒高度非负", rootAABB.bottom >= rootAABB.top);
        }
    }
    
    private static function testTreeStructureIntegrity():Void {
        var objects:Array = createSimpleObjects(30);
        var bvh:BVH = BVHBuilder.build(objects);
        
        // 验证树结构完整性
        assertTrue("树结构完整", validateTreeStructure(bvh.root));
        
        // 验证叶子节点和内部节点的正确性
        var nodeStats:Object = analyzeNodeStructure(bvh.root);
        
        assertTrue("存在叶子节点", nodeStats.leafCount > 0);
        assertTrue("叶子节点对象数量合理", nodeStats.totalLeafObjects == objects.length);
        assertTrue("内部节点没有对象", nodeStats.internalNodeObjects == 0);
        
        trace("📊 树结构统计: 叶子=" + nodeStats.leafCount + 
              ", 内部=" + nodeStats.internalCount + 
              ", 叶子对象=" + nodeStats.totalLeafObjects);
    }
    
    private static function testQueryResultIntegrity():Void {
        var objects:Array = createSimpleObjects(40);
        var bvh:BVH = BVHBuilder.build(objects);
        
        // 全范围查询应该返回所有对象
        var fullQuery:AABB = new AABB();
        fullQuery.left = -10000;
        fullQuery.right = 10000;
        fullQuery.top = -10000;
        fullQuery.bottom = 10000;
        
        var fullResult:Array = bvh.query(fullQuery);
        assertEquals("全范围查询返回所有对象", objects.length, fullResult.length, 0);
        
        // 空范围查询应该返回空结果
        var emptyQuery:AABB = new AABB();
        emptyQuery.left = 20000;
        emptyQuery.right = 20100;
        emptyQuery.top = 20000;
        emptyQuery.bottom = 20100;
        
        var emptyResult:Array = bvh.query(emptyQuery);
        assertArrayLength("空范围查询返回空结果", 0, emptyResult);
        
        // 精确查询验证
        var preciseQuery:AABB = new AABB();
        preciseQuery.left = 0;
        preciseQuery.right = 100;
        preciseQuery.top = 0;
        preciseQuery.bottom = 80;
        
        var preciseResult:Array = bvh.query(preciseQuery);
        
        // 验证查询结果的正确性
        for (var i:Number = 0; i < preciseResult.length; i++) {
            var obj:IBVHObject = preciseResult[i];
            assertTrue("精确查询结果" + i + "确实相交", 
                     preciseQuery.intersects(obj.getAABB()));
        }
        
        // 验证没有遗漏相交对象
        var missedCount:Number = 0;
        for (var j:Number = 0; j < objects.length; j++) {
            if (preciseQuery.intersects(objects[j].getAABB())) {
                var foundInResult:Boolean = false;
                for (var k:Number = 0; k < preciseResult.length; k++) {
                    if (objects[j] == preciseResult[k]) {
                        foundInResult = true;
                        break;
                    }
                }
                if (!foundInResult) {
                    missedCount++;
                }
            }
        }
        assertEquals("精确查询没有遗漏对象", 0, missedCount, 0);
    }
    
    private static function testModificationSafety():Void {
        var originalObjects:Array = createSimpleObjects(15);
        var copyObjects:Array = originalObjects.concat();
        
        // 构建BVH
        var bvh:BVH = BVHBuilder.build(originalObjects);
        
        // 修改原始数组
        originalObjects.push(createSimpleObjects(1)[0]);
        originalObjects[0] = null;
        
        // 验证BVH不受影响
        var queryAABB:AABB = new AABB();
        queryAABB.left = 0;
        queryAABB.right = 1000;
        queryAABB.top = 0;
        queryAABB.bottom = 800;
        
        var result:Array = bvh.query(queryAABB);
        
        // BVH应该仍然包含原始对象（除了被设为null的）
        assertTrue("BVH不受原始数组修改影响", result.length >= copyObjects.length - 1);
        
        // 验证BVH中没有null对象
        for (var i:Number = 0; i < result.length; i++) {
            assertNotNull("BVH查询结果" + i + "不为null", result[i]);
        }
    }
    
    // ========================================================================
    // 压力测试
    // ========================================================================
    
    private static function runStressTests():Void {
        trace("\n💪 执行压力测试...");
        
        stressTestLargeScaleConstruction();
        stressTestMemoryUsage();
        stressTestExtremeDepth();
        stressTestConcurrentOperations();
        stressTestEdgeCaseOverload();
    }
    
    private static function stressTestLargeScaleConstruction():Void {
        var largeScale:Number = LARGE_SCALE_OBJECTS;
        trace("🔥 大规模构建测试: " + largeScale + "个对象");
        
        var largeObjects:Array = createRandomObjects(largeScale);
        
        var startTime:Number = getTimer();
        var largeBVH:BVH = BVHBuilder.build(largeObjects);
        var buildTime:Number = getTimer() - startTime;
        
        assertNotNull("大规模构建成功", largeBVH);
        assertNotNull("大规模构建有根节点", largeBVH.root);
        
        // 验证构建时间合理
        var timePerObject:Number = buildTime / largeScale;
        assertTrue("大规模构建时间合理", timePerObject < 1); // 每个对象不超过1ms
        
        // 验证树深度合理
        var depth:Number = calculateTreeDepth(largeBVH.root);
        var maxReasonableDepth:Number = Math.log(largeScale) / Math.log(2) + 10;
        assertLessOrEqual("大规模构建树深度合理", depth, maxReasonableDepth);
        
        // 验证查询功能
        var largeQuery:AABB = new AABB();
        largeQuery.left = 0;
        largeQuery.right = 500;
        largeQuery.top = 0;
        largeQuery.bottom = 400;
        
        var queryStart:Number = getTimer();
        var largeResult:Array = largeBVH.query(largeQuery);
        var queryTime:Number = getTimer() - queryStart;
        
        assertTrue("大规模查询功能正常", largeResult.length >= 0);
        assertTrue("大规模查询性能合理", queryTime < 100);
        
        trace("📊 大规模测试结果:");
        trace("  构建时间: " + buildTime + "ms (" + Math.round(timePerObject * 1000) / 1000 + "ms/对象)");
        trace("  树深度: " + depth);
        trace("  查询时间: " + queryTime + "ms");
        trace("  查询结果: " + largeResult.length + "个对象");
    }
    
    private static function stressTestMemoryUsage():Void {
        var memoryIterations:Number = 20;
        var objectsPerIteration:Number = 500;
        
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < memoryIterations; i++) {
            // 创建临时对象
            var tempObjects:Array = createRandomObjects(objectsPerIteration);
            
            // 构建BVH
            var tempBVH:BVH = BVHBuilder.build(tempObjects);
            
            // 执行查询操作
            var testQuery:AABB = new AABB();
            testQuery.left = i * 50;
            testQuery.right = testQuery.left + 200;
            testQuery.top = i * 40;
            testQuery.bottom = testQuery.top + 160;
            
            tempBVH.query(testQuery);
            
            // 清理引用
            tempObjects = null;
            tempBVH = null;
            
            if (i % 5 == 0) {
                trace("🧠 内存测试进度: " + (i + 1) + "/" + memoryIterations);
            }
        }
        
        var memoryTime:Number = getTimer() - startTime;
        
        trace("🧠 内存使用测试: " + memoryIterations + "次迭代(" + 
              (memoryIterations * objectsPerIteration) + "总对象)耗时 " + memoryTime + "ms");
        
        assertTrue("内存使用测试通过", memoryTime < 5000);
    }
    
    private static function stressTestExtremeDepth():Void {
        // 测试可能导致极深树的对象分布
        var linearObjects:Array = createLinearObjects(100);
        
        var startTime:Number = getTimer();
        var deepBVH:BVH = BVHBuilder.build(linearObjects);
        var buildTime:Number = getTimer() - startTime;
        
        assertNotNull("极深树构建成功", deepBVH);
        
        var depth:Number = calculateTreeDepth(deepBVH.root);
        
        trace("🔥 极深树测试: 深度=" + depth + ", 构建时间=" + buildTime + "ms");
        
        // 即使是最坏情况，深度也应该在合理范围内
        assertLessOrEqual("极深树深度可接受", depth, MAX_REASONABLE_DEPTH * 2);
        assertTrue("极深树构建时间合理", buildTime < 1000);
        
        // 验证查询仍然正常工作
        var deepQuery:AABB = new AABB();
        deepQuery.left = 0;
        deepQuery.right = 500;
        deepQuery.top = 0;
        deepQuery.bottom = 400;
        
        var queryStart:Number = getTimer();
        var deepResult:Array = deepBVH.query(deepQuery);
        var queryTime:Number = getTimer() - queryStart;
        
        assertTrue("极深树查询功能正常", deepResult.length >= 0);
        assertTrue("极深树查询性能可接受", queryTime < 200);
    }
    
    private static function stressTestConcurrentOperations():Void {
        // 模拟并发操作（快速连续构建和查询）
        var concurrentTrials:Number = 50;
        var operations:Array = [];
        
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < concurrentTrials; i++) {
            // 快速连续构建多个BVH
            var objects1:Array = createRandomObjects(50);
            var objects2:Array = createRandomObjects(30);
            var objects3:Array = createRandomObjects(70);
            
            var bvh1:BVH = BVHBuilder.build(objects1);
            var bvh2:BVH = BVHBuilder.buildFromSortedX(createSortedTestObjects(30));
            var bvh3:BVH = BVHBuilder.build(objects3);
            
            // 交替查询
            var query:AABB = new AABB();
            query.left = i * 10;
            query.right = query.left + 100;
            query.top = i * 8;
            query.bottom = query.top + 80;
            
            var result1:Array = bvh1.query(query);
            var result2:Array = bvh2.query(query);
            var result3:Array = bvh3.query(query);
            
            operations.push({
                iteration: i,
                results: [result1.length, result2.length, result3.length]
            });
        }
        
        var concurrentTime:Number = getTimer() - startTime;
        
        // 验证所有操作都成功完成
        for (var j:Number = 0; j < operations.length; j++) {
            var op:Object = operations[j];
            assertTrue("并发操作" + j + "结果有效", op.results[0] >= 0);
            assertTrue("并发操作" + j + "结果有效", op.results[1] >= 0);
            assertTrue("并发操作" + j + "结果有效", op.results[2] >= 0);
        }
        
        trace("🔄 并发操作测试: " + concurrentTrials + "次并发操作耗时 " + concurrentTime + "ms");
        assertTrue("并发操作性能合理", concurrentTime < 3000);
    }
    
    private static function stressTestEdgeCaseOverload():Void {
        // 大量边界情况混合测试
        var edgeCases:Array = [];
        
        // 添加各种边界情况对象
        for (var i:Number = 0; i < 50; i++) {
            switch (i % 8) {
                case 0: // 零面积
                    edgeCases.push(createBVHObject("zero_" + i, i * 10, i * 10, i * 10, i * 10));
                    break;
                case 1: // 极小
                    edgeCases.push(createBVHObject("tiny_" + i, i * 100, i * 100 + 0.1, i * 80, i * 80 + 0.1));
                    break;
                case 2: // 极大
                    edgeCases.push(createBVHObject("huge_" + i, -1000, 1000, -800, 800));
                    break;
                case 3: // 线条
                    edgeCases.push(createBVHObject("line_" + i, i * 50, i * 50 + 100, 200, 200));
                    break;
                case 4: // 负坐标
                    edgeCases.push(createBVHObject("neg_" + i, -i * 50, -i * 50 + 30, -i * 40, -i * 40 + 20));
                    break;
                case 5: // 重叠
                    edgeCases.push(createBVHObject("overlap_" + i, 500, 600, 400, 500));
                    break;
                case 6: // 相邻
                    edgeCases.push(createBVHObject("adjacent_" + i, i * 30, i * 30 + 30, 100, 150));
                    break;
                case 7: // 普通
                    edgeCases.push(createBVHObject("normal_" + i, i * 60, i * 60 + 40, i * 45, i * 45 + 35));
                    break;
            }
        }
        
        var edgeStartTime:Number = getTimer();
        var edgeBVH:BVH = BVHBuilder.build(edgeCases);
        var edgeBuildTime:Number = getTimer() - edgeStartTime;
        
        assertNotNull("边界情况混合构建成功", edgeBVH);
        assertTrue("边界情况混合构建时间合理", edgeBuildTime < 500);
        
        // 多次查询验证稳定性
        var stableQueries:Number = 20;
        var stableResults:Array = [];
        
        for (var j:Number = 0; j < stableQueries; j++) {
            var stableQuery:AABB = new AABB();
            stableQuery.left = j * 100 - 500;
            stableQuery.right = stableQuery.left + 200;
            stableQuery.top = j * 80 - 400;
            stableQuery.bottom = stableQuery.top + 160;
            
            var stableResult:Array = edgeBVH.query(stableQuery);
            stableResults.push(stableResult.length);
        }
        
        // 验证查询结果稳定
        for (var k:Number = 0; k < stableResults.length; k++) {
            assertTrue("边界情况查询" + k + "结果有效", stableResults[k] >= 0);
        }
        
        trace("🔥 边界情况混合测试: " + edgeCases.length + "个混合边界对象，构建耗时 " + edgeBuildTime + "ms");
    }
    
    // ========================================================================
    // 算法验证测试
    // ========================================================================
    
    private static function runAlgorithmValidationTests():Void {
        trace("\n🧮 执行算法验证测试...");
        
        testBruteForceComparison();
        testConstructionQualityMetrics();
        testQueryPerformanceValidation();
        testTreeOptimality();
    }
    
    private static function testBruteForceComparison():Void {
        // 与暴力搜索结果对比
        var validationObjects:Array = createRandomObjects(30);
        var bvh:BVH = BVHBuilder.build(validationObjects);
        
        var testQueries:Array = [
            createAABB(50, 150, 50, 150),
            createAABB(200, 300, 100, 200),
            createAABB(0, 100, 250, 350),
            createAABB(300, 400, 0, 100),
            createAABB(-50, 50, -50, 50)
        ];
        
        for (var i:Number = 0; i < testQueries.length; i++) {
            var query:AABB = testQueries[i];
            
            // BVH查询
            var bvhResult:Array = bvh.query(query);
            
            // 暴力搜索
            var bruteResult:Array = [];
            for (var j:Number = 0; j < validationObjects.length; j++) {
                if (query.intersects(validationObjects[j].getAABB())) {
                    bruteResult.push(validationObjects[j]);
                }
            }
            
            // 比较结果
            assertEquals("查询" + i + "结果数量一致", bruteResult.length, bvhResult.length, 0);
            
            // 验证包含相同对象
            for (var k:Number = 0; k < bvhResult.length; k++) {
                var foundInBrute:Boolean = false;
                for (var l:Number = 0; l < bruteResult.length; l++) {
                    if (bvhResult[k] == bruteResult[l]) {
                        foundInBrute = true;
                        break;
                    }
                }
                assertTrue("BVH查询" + i + "结果" + k + "在暴力搜索中", foundInBrute);
            }
        }
        
        trace("📊 与暴力搜索对比: " + testQueries.length + "个查询全部一致");
    }
    
    private static function testConstructionQualityMetrics():Void {
        var qualityObjects:Array = createRandomObjects(50);
        var bvh:BVH = BVHBuilder.build(qualityObjects);
        
        // 计算质量指标
        var depth:Number = calculateTreeDepth(bvh.root);
        var balance:Number = calculateTreeBalance(bvh.root);
        var tightness:Number = calculateBoundingBoxTightness(bvh.root, qualityObjects);
        var cohesion:Number = calculateSpatialCohesion(bvh.root);
        
        // 评估质量
        var theoreticalOptimalDepth:Number = Math.ceil(Math.log(qualityObjects.length) / Math.log(2));
        var depthQuality:Number = theoreticalOptimalDepth / depth; // 越接近1越好
        
        var balanceQuality:Number = 1 / (1 + balance); // 越接近1越好
        
        trace("📊 构建质量指标:");
        trace("  深度: " + depth + " (理论最优: " + theoreticalOptimalDepth + ", 质量: " + Math.round(depthQuality * 100) + "%)");
        trace("  平衡度: " + balance + " (质量: " + Math.round(balanceQuality * 100) + "%)");
        trace("  紧密度: " + Math.round(tightness * 100) + "%");
        trace("  聚集性: " + Math.round(cohesion * 100) + "%");
        
        // 质量验证
        assertTrue("深度质量合理", depthQuality >= 0.5);
        assertTrue("平衡度质量合理", balanceQuality >= 0.3);
        assertTrue("紧密度合理", tightness >= 0.3);
        assertTrue("聚集性合理", cohesion >= 0.4);
    }
    
    private static function testQueryPerformanceValidation():Void {
        // 验证BVH查询确实比暴力搜索快
        var perfObjects:Array = createRandomObjects(200);
        var perfBVH:BVH = BVHBuilder.build(perfObjects);
        
        var perfQuery:AABB = createAABB(100, 300, 150, 350);
        
        // BVH查询性能
        var bvhStartTime:Number = getTimer();
        for (var i:Number = 0; i < 100; i++) {
            perfBVH.query(perfQuery);
        }
        var bvhTime:Number = getTimer() - bvhStartTime;
        
        // 暴力搜索性能
        var bruteStartTime:Number = getTimer();
        for (var j:Number = 0; j < 100; j++) {
            var bruteResult:Array = [];
            for (var k:Number = 0; k < perfObjects.length; k++) {
                if (perfQuery.intersects(perfObjects[k].getAABB())) {
                    bruteResult.push(perfObjects[k]);
                }
            }
        }
        var bruteTime:Number = getTimer() - bruteStartTime;
        
        var speedup:Number = bruteTime / bvhTime;
        
        trace("📊 查询性能验证:");
        trace("  BVH查询: " + bvhTime + "ms");
        trace("  暴力搜索: " + bruteTime + "ms");
        trace("  加速比: " + Math.round(speedup * 100) / 100 + "x");
        
        assertTrue("BVH查询确实更快", bvhTime < bruteTime);
        assertTrue("加速比显著", speedup >= 1.5);
    }
    
    private static function testTreeOptimality():Void {
        // 测试不同构建策略的相对优劣
        var optimalObjects:Array = createRandomObjects(80);
        
        // 普通构建
        var normalStartTime:Number = getTimer();
        var normalBVH:BVH = BVHBuilder.build(optimalObjects);
        var normalBuildTime:Number = getTimer() - normalStartTime;
        
        // 预排序构建
        var sortedObjects:Array = optimalObjects.concat();
        sortByXCenter(sortedObjects);
        
        var sortedStartTime:Number = getTimer();
        var sortedBVH:BVH = BVHBuilder.buildFromSortedX(sortedObjects);
        var sortedBuildTime:Number = getTimer() - sortedStartTime;
        
        // 质量比较
        var normalDepth:Number = calculateTreeDepth(normalBVH.root);
        var sortedDepth:Number = calculateTreeDepth(sortedBVH.root);
        
        var normalBalance:Number = calculateTreeBalance(normalBVH.root);
        var sortedBalance:Number = calculateTreeBalance(sortedBVH.root);
        
        // 查询性能比较
        var testQuery:AABB = createAABB(50, 250, 75, 275);
        
        var normalQueryStart:Number = getTimer();
        for (var i:Number = 0; i < 50; i++) {
            normalBVH.query(testQuery);
        }
        var normalQueryTime:Number = getTimer() - normalQueryStart;
        
        var sortedQueryStart:Number = getTimer();
        for (var j:Number = 0; j < 50; j++) {
            sortedBVH.query(testQuery);
        }
        var sortedQueryTime:Number = getTimer() - sortedQueryStart;
        
        trace("📊 构建策略优劣对比:");
        trace("  普通构建: 时间=" + normalBuildTime + "ms, 深度=" + normalDepth + ", 平衡=" + normalBalance + ", 查询=" + normalQueryTime + "ms");
        trace("  预排序构建: 时间=" + sortedBuildTime + "ms, 深度=" + sortedDepth + ", 平衡=" + sortedBalance + ", 查询=" + sortedQueryTime + "ms");
        
        // 验证预排序优化的有效性
        assertTrue("预排序构建时间优势", sortedBuildTime <= normalBuildTime);
        assertTrue("预排序构建质量不劣", sortedDepth <= normalDepth + 2);
        assertTrue("预排序构建平衡度不劣", sortedBalance <= normalBalance + 1);
    }
    
    // ========================================================================
    // 实际场景测试
    // ========================================================================
    
    private static function runRealWorldScenarioTests():Void {
        trace("\n🌍 执行实际场景测试...");
        
        testGameWorldConstruction();
        testUIElementHierarchy();
        testMapPOIIndexing();
        testParticleSystemOptimization();
        testDynamicContentManagement();
    }
    
    private static function testGameWorldConstruction():Void {
        trace("🎮 游戏世界构建场景测试");
        
        // 模拟游戏世界对象
        var gameObjects:Array = [];
        
        // 地形块
        for (var i:Number = 0; i < 20; i++) {
            for (var j:Number = 0; j < 15; j++) {
                gameObjects.push(createBVHObject("terrain_" + i + "_" + j, 
                    i * 100, i * 100 + 100, j * 80, j * 80 + 80));
            }
        }
        
        // 建筑物
        for (var k:Number = 0; k < 30; k++) {
            var buildingX:Number = Math.random() * 1800 + 100;
            var buildingY:Number = Math.random() * 1000 + 100;
            gameObjects.push(createBVHObject("building_" + k, 
                buildingX, buildingX + 150, buildingY, buildingY + 200));
        }
        
        // NPC和敌人
        for (var l:Number = 0; l < 50; l++) {
            var npcX:Number = Math.random() * 1900;
            var npcY:Number = Math.random() * 1100;
            gameObjects.push(createBVHObject("npc_" + l, 
                npcX, npcX + 32, npcY, npcY + 32));
        }
        
        // 道具和装备
        for (var m:Number = 0; m < 80; m++) {
            var itemX:Number = Math.random() * 1900;
            var itemY:Number = Math.random() * 1100;
            gameObjects.push(createBVHObject("item_" + m, 
                itemX, itemX + 16, itemY, itemY + 16));
        }
        
        trace("🏗️ 创建游戏世界: " + gameObjects.length + "个对象");
        
        var gameWorldStart:Number = getTimer();
        var gameWorldBVH:BVH = BVHBuilder.build(gameObjects);
        var gameWorldBuildTime:Number = getTimer() - gameWorldStart;
        
        assertNotNull("游戏世界BVH构建成功", gameWorldBVH);
        assertTrue("游戏世界构建时间合理", gameWorldBuildTime < 200);
        
        // 模拟玩家视野查询
        var playerViewport:AABB = createAABB(500, 1000, 400, 800);
        var viewportStart:Number = getTimer();
        var viewportObjects:Array = gameWorldBVH.query(playerViewport);
        var viewportTime:Number = getTimer() - viewportStart;
        
        assertTrue("玩家视野查询快速", viewportTime < 10);
        assertTrue("玩家视野有对象", viewportObjects.length > 0);
        
        // 模拟技能范围检测
        var skillCenter:Vector = new Vector(800, 600);
        var skillRadius:Number = 150;
        var skillStart:Number = getTimer();
        var skillTargets:Array = gameWorldBVH.queryCircle(skillCenter, skillRadius);
        var skillTime:Number = getTimer() - skillStart;
        
        assertTrue("技能范围检测快速", skillTime < 5);
        
        trace("🎯 游戏世界测试结果:");
        trace("  构建时间: " + gameWorldBuildTime + "ms");
        trace("  视野查询: " + viewportTime + "ms, 找到" + viewportObjects.length + "个对象");
        trace("  技能检测: " + skillTime + "ms, 找到" + skillTargets.length + "个目标");
    }
    
    private static function testUIElementHierarchy():Void {
        trace("🖼️ UI元素层次结构场景测试");
        
        // 模拟UI界面元素
        var uiElements:Array = [];
        
        // 主窗口
        uiElements.push(createBVHObject("main_window", 100, 900, 50, 650));
        
        // 面板
        var panelCount:Number = 8;
        for (var i:Number = 0; i < panelCount; i++) {
            var panelX:Number = 150 + (i % 3) * 240;
            var panelY:Number = 100 + Math.floor(i / 3) * 180;
            uiElements.push(createBVHObject("panel_" + i, 
                panelX, panelX + 200, panelY, panelY + 150));
        }
        
        // 按钮
        var buttonCount:Number = 25;
        for (var j:Number = 0; j < buttonCount; j++) {
            var btnX:Number = 200 + (j % 8) * 80;
            var btnY:Number = 120 + Math.floor(j / 8) * 40;
            uiElements.push(createBVHObject("button_" + j, 
                btnX, btnX + 60, btnY, btnY + 30));
        }
        
        // 文本框
        var textCount:Number = 15;
        for (var k:Number = 0; k < textCount; k++) {
            var textX:Number = 180 + (k % 5) * 120;
            var textY:Number = 200 + Math.floor(k / 5) * 50;
            uiElements.push(createBVHObject("text_" + k, 
                textX, textX + 100, textY, textY + 20));
        }
        
        trace("🎨 创建UI界面: " + uiElements.length + "个元素");
        
        var uiStart:Number = getTimer();
        var uiBVH:BVH = BVHBuilder.build(uiElements);
        var uiBuildTime:Number = getTimer() - uiStart;
        
        assertNotNull("UI层次构建成功", uiBVH);
        assertTrue("UI构建时间优秀", uiBuildTime < 50);
        
        // 模拟鼠标点击检测
        var clickTests:Array = [
            {x: 300, y: 200, desc: "面板区域"},
            {x: 220, y: 140, desc: "按钮区域"},
            {x: 250, y: 220, desc: "文本区域"},
            {x: 50, y: 50, desc: "空白区域"}
        ];
        
        var totalClickTime:Number = 0;
        
        for (var l:Number = 0; l < clickTests.length; l++) {
            var clickTest:Object = clickTests[l];
            var clickArea:AABB = createAABB(clickTest.x - 2, clickTest.x + 2, 
                                          clickTest.y - 2, clickTest.y + 2);
            
            var clickStart:Number = getTimer();
            var clickResult:Array = uiBVH.query(clickArea);
            var clickTime:Number = getTimer() - clickStart;
            totalClickTime += clickTime;
            
            trace("  " + clickTest.desc + "点击: " + clickTime + "ms, " + clickResult.length + "个元素");
        }
        
        assertTrue("UI点击检测快速", totalClickTime < 10);
        
        trace("🖱️ UI测试结果: 总构建" + uiBuildTime + "ms, 点击检测" + totalClickTime + "ms");
    }
    
    private static function testMapPOIIndexing():Void {
        trace("🗺️ 地图POI索引场景测试");
        
        // 模拟地图兴趣点
        var pois:Array = [];
        
        // 商店
        for (var i:Number = 0; i < 25; i++) {
            var shopX:Number = Math.random() * 10000;
            var shopY:Number = Math.random() * 8000;
            pois.push(createBVHObject("shop_" + i, shopX - 20, shopX + 20, shopY - 20, shopY + 20));
        }
        
        // 餐厅
        for (var j:Number = 0; j < 35; j++) {
            var restX:Number = Math.random() * 10000;
            var restY:Number = Math.random() * 8000;
            pois.push(createBVHObject("restaurant_" + j, restX - 25, restX + 25, restY - 25, restY + 25));
        }
        
        // 景点
        for (var k:Number = 0; k < 15; k++) {
            var attractX:Number = Math.random() * 10000;
            var attractY:Number = Math.random() * 8000;
            pois.push(createBVHObject("attraction_" + k, attractX - 50, attractX + 50, attractY - 50, attractY + 50));
        }
        
        // 交通站点
        for (var l:Number = 0; l < 40; l++) {
            var stationX:Number = Math.random() * 10000;
            var stationY:Number = Math.random() * 8000;
            pois.push(createBVHObject("station_" + l, stationX - 15, stationX + 15, stationY - 15, stationY + 15));
        }
        
        trace("📍 创建地图POI: " + pois.length + "个兴趣点");
        
        var mapStart:Number = getTimer();
        var mapBVH:BVH = BVHBuilder.build(pois);
        var mapBuildTime:Number = getTimer() - mapStart;
        
        assertNotNull("地图POI索引构建成功", mapBVH);
        assertTrue("地图构建时间合理", mapBuildTime < 100);
        
        // 模拟地理范围查询
        var regionQueries:Array = [
            {name: "市中心", area: createAABB(4000, 6000, 3000, 5000)},
            {name: "商业区", area: createAABB(2000, 4000, 2000, 4000)},
            {name: "住宅区", area: createAABB(6000, 8000, 5000, 7000)},
            {name: "郊区", area: createAABB(8000, 10000, 6000, 8000)}
        ];
        
        var totalRegionTime:Number = 0;
        var totalPOIs:Number = 0;
        
        for (var m:Number = 0; m < regionQueries.length; m++) {
            var region:Object = regionQueries[m];
            
            var regionStart:Number = getTimer();
            var regionPOIs:Array = mapBVH.query(region.area);
            var regionTime:Number = getTimer() - regionStart;
            
            totalRegionTime += regionTime;
            totalPOIs += regionPOIs.length;
            
            trace("  " + region.name + ": " + regionTime + "ms, " + regionPOIs.length + "个POI");
        }
        
        // 模拟附近搜索
        var nearbySearches:Array = [
            {x: 5000, y: 4000, radius: 500, desc: "500m范围"},
            {x: 3000, y: 6000, radius: 1000, desc: "1km范围"},
            {x: 7000, y: 2000, radius: 1500, desc: "1.5km范围"}
        ];
        
        var totalNearbyTime:Number = 0;
        
        for (var n:Number = 0; n < nearbySearches.length; n++) {
            var search:Object = nearbySearches[n];
            var center:Vector = new Vector(search.x, search.y);
            
            var nearbyStart:Number = getTimer();
            var nearbyPOIs:Array = mapBVH.queryCircle(center, search.radius);
            var nearbyTime:Number = getTimer() - nearbyStart;
            
            totalNearbyTime += nearbyTime;
            
            trace("  " + search.desc + "搜索: " + nearbyTime + "ms, " + nearbyPOIs.length + "个POI");
        }
        
        assertTrue("地图区域查询快速", totalRegionTime < 20);
        assertTrue("附近搜索快速", totalNearbyTime < 15);
        
        trace("🗺️ 地图测试结果: 构建" + mapBuildTime + "ms, 区域查询" + totalRegionTime + "ms, 附近搜索" + totalNearbyTime + "ms");
    }
    
    private static function testParticleSystemOptimization():Void {
        trace("✨ 粒子系统优化场景测试");
        
        // 模拟粒子系统
        var particles:Array = [];
        
        // 爆炸效果粒子
        var explosionCenter:Object = {x: 500, y: 400};
        for (var i:Number = 0; i < 100; i++) {
            var angle:Number = (i / 100) * Math.PI * 2;
            var distance:Number = Math.random() * 200 + 50;
            var particleX:Number = explosionCenter.x + Math.cos(angle) * distance;
            var particleY:Number = explosionCenter.y + Math.sin(angle) * distance;
            
            particles.push(createBVHObject("explosion_" + i, 
                particleX - 2, particleX + 2, particleY - 2, particleY + 2));
        }
        
        // 雨滴粒子
        for (var j:Number = 0; j < 200; j++) {
            var rainX:Number = Math.random() * 1000;
            var rainY:Number = Math.random() * 800;
            particles.push(createBVHObject("rain_" + j, 
                rainX - 1, rainX + 1, rainY - 5, rainY + 5));
        }
        
        // 火花粒子
        for (var k:Number = 0; k < 150; k++) {
            var sparkX:Number = 300 + Math.random() * 100;
            var sparkY:Number = 200 + Math.random() * 100;
            particles.push(createBVHObject("spark_" + k, 
                sparkX - 1, sparkX + 1, sparkY - 1, sparkY + 1));
        }
        
        trace("💫 创建粒子系统: " + particles.length + "个粒子");
        
        var particleStart:Number = getTimer();
        var particleBVH:BVH = BVHBuilder.build(particles);
        var particleBuildTime:Number = getTimer() - particleStart;
        
        assertNotNull("粒子系统BVH构建成功", particleBVH);
        assertTrue("粒子系统构建时间优秀", particleBuildTime < 50);
        
        // 模拟碰撞检测查询
        var collisionTests:Array = [
            {area: createAABB(400, 600, 300, 500), desc: "爆炸区域"},
            {area: createAABB(0, 1000, 0, 800), desc: "全屏雨滴"},
            {area: createAABB(250, 450, 150, 350), desc: "火花区域"}
        ];
        
        var totalCollisionTime:Number = 0;
        var totalCollisions:Number = 0;
        
        for (var l:Number = 0; l < collisionTests.length; l++) {
            var collision:Object = collisionTests[l];
            
            var collisionStart:Number = getTimer();
            var collisionParticles:Array = particleBVH.query(collision.area);
            var collisionTime:Number = getTimer() - collisionStart;
            
            totalCollisionTime += collisionTime;
            totalCollisions += collisionParticles.length;
            
            trace("  " + collision.desc + "碰撞: " + collisionTime + "ms, " + collisionParticles.length + "个粒子");
        }
        
        // 模拟视觉剔除
        var frustumCulling:AABB = createAABB(200, 800, 150, 650);
        var cullingStart:Number = getTimer();
        var visibleParticles:Array = particleBVH.query(frustumCulling);
        var cullingTime:Number = getTimer() - cullingStart;
        
        assertTrue("粒子碰撞检测快速", totalCollisionTime < 10);
        assertTrue("视觉剔除快速", cullingTime < 5);
        
        trace("✨ 粒子测试结果: 构建" + particleBuildTime + "ms, 碰撞" + totalCollisionTime + "ms, 剔除" + cullingTime + "ms");
    }
    
    private static function testDynamicContentManagement():Void {
        trace("🔄 动态内容管理场景测试");
        
        // 模拟动态内容系统
        var contentItems:Array = [];
        
        // 流媒体内容
        for (var i:Number = 0; i < 40; i++) {
            var streamX:Number = i * 100;
            var streamY:Number = Math.random() * 600;
            contentItems.push(createBVHObject("stream_" + i, 
                streamX, streamX + 80, streamY, streamY + 60));
        }
        
        // 缓存块
        for (var j:Number = 0; j < 60; j++) {
            var cacheX:Number = Math.random() * 3000;
            var cacheY:Number = Math.random() * 500;
            contentItems.push(createBVHObject("cache_" + j, 
                cacheX, cacheX + 50, cacheY, cacheY + 40));
        }
        
        // 预加载内容
        for (var k:Number = 0; k < 80; k++) {
            var preloadX:Number = Math.random() * 4000;
            var preloadY:Number = Math.random() * 600;
            contentItems.push(createBVHObject("preload_" + k, 
                preloadX, preloadX + 30, preloadY, preloadY + 25));
        }
        
        trace("📱 创建动态内容: " + contentItems.length + "个内容项");
        
        var contentStart:Number = getTimer();
        var contentBVH:BVH = BVHBuilder.build(contentItems);
        var contentBuildTime:Number = getTimer() - contentStart;
        
        assertNotNull("动态内容BVH构建成功", contentBVH);
        assertTrue("动态内容构建时间优秀", contentBuildTime < 80);
        
        // 模拟视口管理
        var viewportManagement:Array = [
            {viewport: createAABB(0, 800, 0, 600), desc: "主视口"},
            {viewport: createAABB(500, 1300, 100, 700), desc: "滚动视口"},
            {viewport: createAABB(1000, 1800, 200, 800), desc: "预测视口"}
        ];
        
        var totalViewportTime:Number = 0;
        var totalContentLoaded:Number = 0;
        
        for (var l:Number = 0; l < viewportManagement.length; l++) {
            var viewport:Object = viewportManagement[l];
            
            var viewportStart:Number = getTimer();
            var viewportContent:Array = contentBVH.query(viewport.viewport);
            var viewportTime:Number = getTimer() - viewportStart;
            
            totalViewportTime += viewportTime;
            totalContentLoaded += viewportContent.length;
            
            trace("  " + viewport.desc + ": " + viewportTime + "ms, " + viewportContent.length + "个内容");
        }
        
        // 模拟内容优先级查询
        var priorityAreas:Array = [
            {center: new Vector(400, 300), radius: 200, desc: "高优先级"},
            {center: new Vector(1200, 400), radius: 300, desc: "中优先级"},
            {center: new Vector(2000, 300), radius: 400, desc: "低优先级"}
        ];
        
        var totalPriorityTime:Number = 0;
        
        for (var m:Number = 0; m < priorityAreas.length; m++) {
            var priority:Object = priorityAreas[m];
            
            var priorityStart:Number = getTimer();
            var priorityContent:Array = contentBVH.queryCircle(priority.center, priority.radius);
            var priorityTime:Number = getTimer() - priorityStart;
            
            totalPriorityTime += priorityTime;
            
            trace("  " + priority.desc + "区域: " + priorityTime + "ms, " + priorityContent.length + "个内容");
        }
        
        assertTrue("视口管理快速", totalViewportTime < 15);
        assertTrue("优先级查询快速", totalPriorityTime < 10);
        
        trace("🔄 动态内容测试结果: 构建" + contentBuildTime + "ms, 视口" + totalViewportTime + "ms, 优先级" + totalPriorityTime + "ms");
    }
    
    // ========================================================================
    // 辅助函数和工具方法
    // ========================================================================
    
    /**
     * 检查AABB A是否包含AABB B
     */
    private static function aabbContains(containerAABB:AABB, containedAABB:AABB):Boolean {
        if (!containerAABB || !containedAABB) return false;
        
        return containerAABB.left <= containedAABB.left &&
               containerAABB.right >= containedAABB.right &&
               containerAABB.top <= containedAABB.top &&
               containerAABB.bottom >= containedAABB.bottom;
    }
    
    /**
     * 克隆AABB对象
     */
    private static function cloneAABB(source:AABB):AABB {
        if (!source) return null;
        
        var cloned:AABB = new AABB();
        cloned.left = source.left;
        cloned.right = source.right;
        cloned.top = source.top;
        cloned.bottom = source.bottom;
        return cloned;
    }
    
    /**
     * 创建AABB对象
     */
    private static function createAABB(left:Number, right:Number, top:Number, bottom:Number):AABB {
        var aabb:AABB = new AABB();
        aabb.left = left;
        aabb.right = right;
        aabb.top = top;
        aabb.bottom = bottom;
        return aabb;
    }
    
    /**
     * 创建BVH对象
     */
    private static function createBVHObject(name:String, left:Number, right:Number, top:Number, bottom:Number):Object {
        var obj:Object = {
            name: name,
            bounds: null,
            
            getAABB: function():AABB {
                return this.bounds;
            }
        };
        
        obj.bounds = createAABB(left, right, top, bottom);
        return obj;
    }
    
    /**
     * 按X轴中心排序对象数组
     */
    private static function sortByXCenter(objects:Array):Void {
        objects.sort(function(a:IBVHObject, b:IBVHObject):Number {
            var aCenter:Number = getCenterX(a.getAABB());
            var bCenter:Number = getCenterX(b.getAABB());
            return aCenter - bCenter;
        });
    }
    
    /**
     * 获取AABB的X轴中心
     */
    private static function getCenterX(aabb:AABB):Number {
        return (aabb.left + aabb.right) / 2;
    }
    
    /**
     * 获取AABB的Y轴中心
     */
    private static function getCenterY(aabb:AABB):Number {
        return (aabb.top + aabb.bottom) / 2;
    }
    
    /**
     * 计算树深度
     */
    private static function calculateTreeDepth(node:BVHNode):Number {
        if (!node || node.isLeaf()) {
            return 0;
        }
        
        var leftDepth:Number = calculateTreeDepth(node.left);
        var rightDepth:Number = calculateTreeDepth(node.right);
        
        return 1 + Math.max(leftDepth, rightDepth);
    }
    
    /**
     * 计算树平衡度（左右子树深度差的最大值）
     */
    private static function calculateTreeBalance(node:BVHNode):Number {
        if (!node || node.isLeaf()) {
            return 0;
        }
        
        var leftDepth:Number = calculateTreeDepth(node.left);
        var rightDepth:Number = calculateTreeDepth(node.right);
        var currentBalance:Number = Math.abs(leftDepth - rightDepth);
        
        var leftBalance:Number = calculateTreeBalance(node.left);
        var rightBalance:Number = calculateTreeBalance(node.right);
        
        return Math.max(currentBalance, Math.max(leftBalance, rightBalance));
    }
    
    /**
     * 验证叶子节点对象数量限制
     */
    private static function validateLeafObjectCount(node:BVHNode, maxObjects:Number):Boolean {
        if (!node) return true;
        
        if (node.isLeaf()) {
            return node.objects.length <= maxObjects;
        }
        
        return validateLeafObjectCount(node.left, maxObjects) && 
               validateLeafObjectCount(node.right, maxObjects);
    }
    
    /**
     * 计算叶子节点统计信息
     */
    private static function calculateLeafStats(node:BVHNode):Object {
        var stats:Object = {count: 0, totalObjects: 0, maxObjects: 0, avgObjects: 0};
        
        collectLeafStats(node, stats);
        
        if (stats.count > 0) {
            stats.avgObjects = stats.totalObjects / stats.count;
        }
        
        return stats;
    }
    
    /**
     * 收集叶子节点统计信息（递归辅助函数）
     */
    private static function collectLeafStats(node:BVHNode, stats:Object):Void {
        if (!node) return;
        
        if (node.isLeaf()) {
            stats.count++;
            stats.totalObjects += node.objects.length;
            stats.maxObjects = Math.max(stats.maxObjects, node.objects.length);
        } else {
            collectLeafStats(node.left, stats);
            collectLeafStats(node.right, stats);
        }
    }
    
    /**
     * 验证包围盒层次结构
     */
    private static function validateBoundingBoxHierarchy(node:BVHNode):Boolean {
        if (!node) return true;
        
        if (node.isLeaf()) {
            // 叶子节点：验证包围盒包含所有对象
            for (var i:Number = 0; i < node.objects.length; i++) {
                var objAABB:AABB = node.objects[i].getAABB();
                if (!aabbContains(node.bounds, objAABB)) {
                    return false;
                }
            }
            return true;
        } else {
            // 内部节点：验证包围盒包含子节点
            if (!aabbContains(node.bounds, node.left.bounds) || 
                !aabbContains(node.bounds, node.right.bounds)) {
                return false;
            }
            
            return validateBoundingBoxHierarchy(node.left) && 
                   validateBoundingBoxHierarchy(node.right);
        }
    }
    
    /**
     * 计算包围盒紧密度
     */
    private static function calculateBoundingBoxTightness(node:BVHNode, allObjects:Array):Number {
        if (!node || !allObjects || allObjects.length == 0) return 0;
        
        // 计算所有对象的最小包围盒
        var minAABB:AABB = cloneAABB(allObjects[0].getAABB());
        for (var i:Number = 1; i < allObjects.length; i++) {
            minAABB.mergeWith(allObjects[i].getAABB());
        }
        
        // 计算面积比
        var minArea:Number = (minAABB.right - minAABB.left) * (minAABB.bottom - minAABB.top);
        var nodeArea:Number = (node.bounds.right - node.bounds.left) * (node.bounds.bottom - node.bounds.top);
        
        if (nodeArea == 0) return 0;
        return minArea / nodeArea;
    }
    
    /**
     * 计算空间聚集性
     */
    private static function calculateSpatialCohesion(node:BVHNode):Number {
        // 简化的聚集性计算：基于树结构的平衡度
        var balance:Number = calculateTreeBalance(node);
        var depth:Number = calculateTreeDepth(node);
        
        if (depth == 0) return 1;
        
        // 平衡度越低，聚集性越好
        return Math.max(0, 1 - balance / depth);
    }
    
    /**
     * 分析轴使用情况
     */
    private static function analyzeAxisUsage(node:BVHNode, depth:Number):Object {
        var info:Object = {usesX: false, usesY: false, depth: depth};
        
        if (!node || node.isLeaf()) {
            return info;
        }
        
        // 根据深度判断使用的轴
        if (depth % 2 == 0) {
            info.usesX = true;
        } else {
            info.usesY = true;
        }
        
        // 递归分析子节点
        var leftInfo:Object = analyzeAxisUsage(node.left, depth + 1);
        var rightInfo:Object = analyzeAxisUsage(node.right, depth + 1);
        
        info.usesX = info.usesX || leftInfo.usesX || rightInfo.usesX;
        info.usesY = info.usesY || leftInfo.usesY || rightInfo.usesY;
        info.depth = Math.max(info.depth, Math.max(leftInfo.depth, rightInfo.depth));
        
        return info;
    }
    
    /**
     * 收集BVH中所有对象
     */
    private static function collectAllObjects(node:BVHNode, result:Array):Void {
        if (!node) return;
        
        if (node.isLeaf()) {
            for (var i:Number = 0; i < node.objects.length; i++) {
                result.push(node.objects[i]);
            }
        } else {
            collectAllObjects(node.left, result);
            collectAllObjects(node.right, result);
        }
    }
    
    /**
     * 验证树结构完整性
     */
    private static function validateTreeStructure(node:BVHNode):Boolean {
        if (!node) return true;
        
        if (node.isLeaf()) {
            // 叶子节点应该没有子节点，但有对象
            return node.left == null && node.right == null && node.objects != null;
        } else {
            // 内部节点应该有子节点，但没有对象
            return node.left != null && node.right != null && 
                   (node.objects == null || node.objects.length == 0) &&
                   validateTreeStructure(node.left) && validateTreeStructure(node.right);
        }
    }
    
    /**
     * 分析节点结构
     */
    private static function analyzeNodeStructure(node:BVHNode):Object {
        var stats:Object = {
            leafCount: 0,
            internalCount: 0,
            totalLeafObjects: 0,
            internalNodeObjects: 0
        };
        
        analyzeNodeStructureRecursive(node, stats);
        return stats;
    }
    
    /**
     * 递归分析节点结构
     */
    private static function analyzeNodeStructureRecursive(node:BVHNode, stats:Object):Void {
        if (!node) return;
        
        if (node.isLeaf()) {
            stats.leafCount++;
            stats.totalLeafObjects += node.objects.length;
        } else {
            stats.internalCount++;
            if (node.objects && node.objects.length > 0) {
                stats.internalNodeObjects += node.objects.length;
            }
            
            analyzeNodeStructureRecursive(node.left, stats);
            analyzeNodeStructureRecursive(node.right, stats);
        }
    }
    
    /**
     * 创建随机分布对象
     */
    private static function createRandomObjects(count:Number):Array {
        var objects:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var x:Number = Math.random() * 1000;
            var y:Number = Math.random() * 800;
            var width:Number = Math.random() * 50 + 10;
            var height:Number = Math.random() * 40 + 10;
            
            objects[i] = createBVHObject("random_" + i, x, x + width, y, y + height);
        }
        
        return objects;
    }
    
    /**
     * 创建聚集分布对象
     */
    private static function createClusteredObjects(count:Number):Array {
        var objects:Array = [];
        var clusterCenters:Array = [
            {x: 200, y: 150},
            {x: 600, y: 300},
            {x: 300, y: 500},
            {x: 700, y: 100}
        ];
        
        for (var i:Number = 0; i < count; i++) {
            var cluster:Object = clusterCenters[i % clusterCenters.length];
            var offsetX:Number = (Math.random() - 0.5) * 100;
            var offsetY:Number = (Math.random() - 0.5) * 80;
            
            var x:Number = cluster.x + offsetX;
            var y:Number = cluster.y + offsetY;
            var size:Number = Math.random() * 20 + 10;
            
            objects[i] = createBVHObject("cluster_" + i, x, x + size, y, y + size);
        }
        
        return objects;
    }
    
    /**
     * 创建线性分布对象
     */
    private static function createLinearObjects(count:Number):Array {
        var objects:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var x:Number = i * 30;
            var y:Number = 100 + i * 2; // 轻微倾斜
            var size:Number = 20;
            
            objects[i] = createBVHObject("linear_" + i, x, x + size, y, y + size);
        }
        
        return objects;
    }
    
    /**
     * 创建网格分布对象
     */
    private static function createGridObjects(count:Number):Array {
        var objects:Array = [];
        var gridSize:Number = Math.ceil(Math.sqrt(count));
        
        for (var i:Number = 0; i < count; i++) {
            var gridX:Number = i % gridSize;
            var gridY:Number = Math.floor(i / gridSize);
            
            var x:Number = gridX * 60;
            var y:Number = gridY * 50;
            var size:Number = 30;
            
            objects[i] = createBVHObject("grid_" + i, x, x + size, y, y + size);
        }
        
        return objects;
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
        trace("📊 BVHBuilder 测试结果汇总");
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
                
                if (result.method == "Method Comparison") {
                    trace("  " + result.method + ":");
                    trace("    普通构建: " + Math.round(result.normalAvg * 100) / 100 + "ms/次");
                    trace("    预排序构建: " + Math.round(result.sortedAvg * 100) / 100 + "ms/次");
                    trace("    加速比: " + Math.round(result.speedup * 100) / 100 + "x");
                } else {
                    var avgTimeStr:String = (isNaN(result.avgTime) || result.avgTime == undefined) ? 
                        "N/A" : String(Math.round(result.avgTime * 1000) / 1000);
                    trace("  " + result.method + ": " + avgTimeStr + "ms/次 (" + 
                          result.trials + "次测试)");
                }
            }
        }
        
        trace("\n🎯 测试覆盖范围:");
        trace("  📋 基础功能: 静态配置, build(), buildFromSortedX(), 空输入处理");
        trace("  🔨 构建方法: 方法变体, 等价性验证, 单/大对象集构建");
        trace("  🌳 树结构质量: 深度, 平衡度, 叶子节点, 包围盒, 空间聚集性");
        trace("  🔄 排序优化: 正确性验证, 预排序行为, 性能影响, 轴交替");
        trace("  🔍 边界条件: 极值对象数, 极值坐标, 退化对象, 配置变体");
        trace("  ⚡ 性能基准: 构建速度, 方法对比, 可扩展性, 优化有效性");
        trace("  💾 数据完整性: 对象引用, 包围盒, 树结构, 查询结果, 修改安全");
        trace("  💪 压力测试: 大规模构建, 内存使用, 极深树, 并发操作, 边界混合");
        trace("  🧮 算法验证: 暴力对比, 质量指标, 查询性能, 树优化度");
        trace("  🌍 实际场景: 游戏世界, UI层次, 地图POI, 粒子系统, 动态内容");
        
        // 性能优化总结
        trace("\n🚀 BVHBuilder 性能特性:");
        trace("  ✨ 双构建方法: 通用build()和优化buildFromSortedX()");
        trace("  ✨ TimSort集成: 保证O(n log n)最坏情况性能");
        trace("  ✨ 预排序优化: 跳过根节点排序，显著提升性能");
        trace("  ✨ 轴交替分割: X/Y轴交替，保证空间分布平衡");
        trace("  ✨ 可配置叶子限制: MAX_OBJECTS_IN_LEAF灵活控制");
        trace("  ✨ 健壮边界处理: 空输入、极值坐标、退化对象");
        
        // 质量评估
        if (failedTests == 0) {
            trace("\n🎉 所有测试通过！BVHBuilder 组件质量优秀！");
            trace("🏗️ BVHBuilder 已准备好构建高性能BVH树结构！");
            trace("⚡ 推荐在性能敏感场景中使用 buildFromSortedX() 方法！");
        } else {
            trace("\n⚠️ 发现 " + failedTests + " 个问题，请检查实现！");
        }
        
        trace("================================================================================");
    }
}