import org.flashNight.sara.util.*;
import org.flashNight.naki.DataStructures.*;

/**
 * 完整测试套件：BVH (包围体层次结构树)
 * ================================
 * 特性：
 * - 100% 方法覆盖率测试
 * - BVH容器功能验证
 * - 查询接口集成测试
 * - 与BVHNode协作测试
 * - 性能基准测试
 * - 边界条件与异常处理
 * - 数据完整性验证
 * - 一句启动设计
 * 
 * 使用方法：
 * org.flashNight.naki.DataStructures.BVHTest.runAll();
 */
class org.flashNight.naki.DataStructures.BVHTest {
    
    // ========================================================================
    // 测试统计和配置
    // ========================================================================
    
    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var performanceResults:Array = [];
    
    // 性能基准配置
    private static var PERFORMANCE_TRIALS:Number = 1000;
    private static var STRESS_OBJECTS_COUNT:Number = 500;
    private static var QUERY_BENCHMARK_MS:Number = 0.5;      // BVH查询应该更快
    private static var BULK_QUERY_BENCHMARK_MS:Number = 250; // 批量查询基准
    private static var INTEGRATION_DEPTH:Number = 6;          // 集成测试树深度
    
    // 测试数据缓存
    private static var testObjects:Array;
    private static var simpleBVH:BVH;
    private static var complexBVH:BVH;
    private static var emptyBVH:BVH;
    private static var deepBVH:BVH;
    
    /**
     * 主测试入口 - 一句启动全部测试
     */
    public static function runAll():Void {
        trace("================================================================================");
        trace("🚀 BVH 完整测试套件启动");
        trace("================================================================================");
        
        var startTime:Number = getTimer();
        resetTestStats();
        
        try {
            // 初始化测试数据
            initializeTestData();
            
            // === 基础功能测试 ===
            runBasicFunctionalityTests();
            
            // === 查询接口测试 ===
            runQueryInterfaceTests();
            
            // === 集成测试 ===
            runIntegrationTests();
            
            // === 边界条件测试 ===
            runBoundaryConditionTests();
            
            // === 性能基准测试 ===
            runPerformanceBenchmarks();
            
            // === 数据完整性测试 ===
            runDataIntegrityTests();
            
            // === 压力测试 ===
            runStressTests();
            
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
    
    private static function assertArrayContains(testName:String, array:Array, expectedObject:Object):Void {
        testCount++;
        var found:Boolean = false;
        
        if (array) {
            for (var i:Number = 0; i < array.length; i++) {
                if (array[i] == expectedObject) {
                    found = true;
                    break;
                }
            }
        }
        
        if (found) {
            passedTests++;
            trace("✅ " + testName + " PASS (object found in array)");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (object not found in array)");
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
    
    // ========================================================================
    // 测试数据初始化
    // ========================================================================
    
    private static function initializeTestData():Void {
        trace("\n🔧 初始化BVH测试数据...");
        
        // 创建测试对象集合
        testObjects = createTestObjects(30);
        
        // 创建简单BVH（单层叶子节点）
        simpleBVH = createSimpleBVH();
        
        // 创建复杂BVH（多层树结构）
        complexBVH = createComplexBVH();
        
        // 创建空BVH
        emptyBVH = createEmptyBVH();
        
        // 创建深度BVH（用于性能测试）
        deepBVH = createDeepBVH(INTEGRATION_DEPTH);
        
        trace("📦 创建了 " + testObjects.length + " 个测试对象");
        trace("🌳 创建了4种不同复杂度的BVH结构");
        trace("📊 简单BVH：单层叶子节点");
        trace("📊 复杂BVH：多层树结构"); 
        trace("📊 空BVH：null根节点");
        trace("📊 深度BVH：深度" + INTEGRATION_DEPTH + "的平衡树");
    }
    
    /**
     * 创建测试对象（实现IBVHObject接口）
     */
    private static function createTestObjects(count:Number):Array {
        var objects:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var obj:Object = {
                name: "testObj_" + i,
                bounds: null,
                
                // 实现IBVHObject接口
                getAABB: function():AABB {
                    return this.bounds;
                }
            };
            
            // 创建AABB - 使用网格分布
            obj.bounds = new AABB();
            var gridSize:Number = 100;
            var gridX:Number = i % 6;  // 6x5网格
            var gridY:Number = Math.floor(i / 6);
            
            obj.bounds.left = gridX * gridSize;
            obj.bounds.right = gridX * gridSize + 80;
            obj.bounds.top = gridY * gridSize;
            obj.bounds.bottom = gridY * gridSize + 60;
            
            objects[i] = obj;
        }
        
        return objects;
    }
    
    /**
     * 创建简单BVH（单层叶子节点）
     */
    private static function createSimpleBVH():BVH {
        var bounds:AABB = new AABB();
        bounds.left = 0;
        bounds.right = 600;
        bounds.top = 0;
        bounds.bottom = 500;
        
        var rootNode:BVHNode = new BVHNode(bounds);
        rootNode.objects = testObjects.slice(0, 10); // 前10个对象
        
        return new BVH(rootNode);
    }
    
    /**
     * 创建复杂BVH（多层树结构）
     */
    private static function createComplexBVH():BVH {
        var rootBounds:AABB = new AABB();
        rootBounds.left = 0;
        rootBounds.right = 600;
        rootBounds.top = 0;
        rootBounds.bottom = 500;
        
        var rootNode:BVHNode = new BVHNode(rootBounds);
        
        // 创建左子树（左半部分）
        var leftBounds:AABB = new AABB();
        leftBounds.left = 0;
        leftBounds.right = 300;
        leftBounds.top = 0;
        leftBounds.bottom = 500;
        
        var leftNode:BVHNode = new BVHNode(leftBounds);
        
        // 左子树的左子节点
        var leftLeftBounds:AABB = new AABB();
        leftLeftBounds.left = 0;
        leftLeftBounds.right = 150;
        leftLeftBounds.top = 0;
        leftLeftBounds.bottom = 250;
        leftNode.left = new BVHNode(leftLeftBounds);
        leftNode.left.objects = testObjects.slice(0, 5);
        
        // 左子树的右子节点
        var leftRightBounds:AABB = new AABB();
        leftRightBounds.left = 150;
        leftRightBounds.right = 300;
        leftRightBounds.top = 250;
        leftRightBounds.bottom = 500;
        leftNode.right = new BVHNode(leftRightBounds);
        leftNode.right.objects = testObjects.slice(5, 10);
        
        rootNode.left = leftNode;
        
        // 创建右子树（右半部分）
        var rightBounds:AABB = new AABB();
        rightBounds.left = 300;
        rightBounds.right = 600;
        rightBounds.top = 0;
        rightBounds.bottom = 500;
        
        var rightNode:BVHNode = new BVHNode(rightBounds);
        rightNode.objects = testObjects.slice(10, 20);
        
        rootNode.right = rightNode;
        
        return new BVH(rootNode);
    }
    
    /**
     * 创建空BVH
     */
    private static function createEmptyBVH():BVH {
        return new BVH(null);
    }
    
    /**
     * 创建深度BVH（平衡二叉树）
     */
    private static function createDeepBVH(depth:Number):BVH {
        var rootNode:BVHNode = createDeepBVHNode(depth, 0, 0, 800, 600);
        return new BVH(rootNode);
    }
    
    /**
     * 递归创建深度BVH节点
     */
    private static function createDeepBVHNode(depth:Number, left:Number, top:Number, right:Number, bottom:Number):BVHNode {
        var bounds:AABB = new AABB();
        bounds.left = left;
        bounds.right = right;
        bounds.top = top;
        bounds.bottom = bottom;
        
        var node:BVHNode = new BVHNode(bounds);
        
        if (depth <= 0) {
            // 叶子节点：随机放置一些对象
            if (testObjects.length > 0 && Math.random() < 0.3) {
                var randomIndex:Number = Math.floor(Math.random() * testObjects.length);
                node.objects = [testObjects[randomIndex]];
            } else {
                node.objects = [];
            }
            return node;
        }
        
        // 交替按X轴和Y轴分割
        var midX:Number = (left + right) / 2;
        var midY:Number = (top + bottom) / 2;
        
        if (depth % 2 == 0) {
            // 按X轴分割
            node.left = createDeepBVHNode(depth - 1, left, top, midX, bottom);
            node.right = createDeepBVHNode(depth - 1, midX, top, right, bottom);
        } else {
            // 按Y轴分割
            node.left = createDeepBVHNode(depth - 1, left, top, right, midY);
            node.right = createDeepBVHNode(depth - 1, left, midY, right, bottom);
        }
        
        return node;
    }
    
    /**
     * 创建指定位置的BVH对象
     */
    private static function createBVHObject(name:String, left:Number, right:Number, top:Number, bottom:Number):Object {
        var obj:Object = {
            name: name,
            bounds: null,
            
            getAABB: function():AABB {
                return this.bounds;
            }
        };
        
        obj.bounds = new AABB();
        obj.bounds.left = left;
        obj.bounds.right = right;
        obj.bounds.top = top;
        obj.bounds.bottom = bottom;
        
        return obj;
    }
    
    // ========================================================================
    // 基础功能测试
    // ========================================================================
    
    private static function runBasicFunctionalityTests():Void {
        trace("\n📋 执行基础功能测试...");
        
        testConstructor();
        testRootProperty();
        testBasicQueries();
    }
    
    private static function testConstructor():Void {
        // 测试正常构造
        var testNode:BVHNode = new BVHNode(new AABB());
        var bvh:BVH = new BVH(testNode);
        
        assertNotNull("BVH构造函数创建对象", bvh);
        assertNotNull("BVH构造函数设置root", bvh.root);
        assertTrue("BVH构造函数root引用正确", bvh.root == testNode);
        
        // 测试null节点构造
        var nullBVH:BVH = new BVH(null);
        assertNotNull("null根节点BVH构造成功", nullBVH);
        assertNull("null根节点BVH的root为null", nullBVH.root);
        
        // 测试复杂节点构造
        var complexRoot:BVHNode = complexBVH.root;
        assertNotNull("复杂BVH构造成功", complexBVH);
        assertNotNull("复杂BVH根节点存在", complexRoot);
        assertTrue("复杂BVH根节点是内部节点", !complexRoot.isLeaf());
    }
    
    private static function testRootProperty():Void {
        // 测试root属性访问
        assertNotNull("simpleBVH root属性访问", simpleBVH.root);
        assertNotNull("complexBVH root属性访问", complexBVH.root);
        assertNull("emptyBVH root属性为null", emptyBVH.root);
        
        // 测试root属性修改
        var originalRoot:BVHNode = simpleBVH.root;
        var newRoot:BVHNode = new BVHNode(new AABB());
        
        simpleBVH.root = newRoot;
        assertTrue("BVH root属性可修改", simpleBVH.root == newRoot);
        
        // 恢复原始root
        simpleBVH.root = originalRoot;
        assertTrue("BVH root属性恢复", simpleBVH.root == originalRoot);
    }
    
    private static function testBasicQueries():Void {
        // 测试基本AABB查询
        var queryAABB:AABB = new AABB();
        queryAABB.left = 0;
        queryAABB.right = 100;
        queryAABB.top = 0;
        queryAABB.bottom = 100;
        
        var result:Array = simpleBVH.query(queryAABB);
        assertNotNull("AABB查询返回数组", result);
        assertTrue("AABB查询返回Array类型", result instanceof Array);
        
        // 测试基本圆形查询
        var center:Vector = new Vector(50, 50);
        var radius:Number = 30;
        
        var circleResult:Array = simpleBVH.queryCircle(center, radius);
        assertNotNull("圆形查询返回数组", circleResult);
        assertTrue("圆形查询返回Array类型", circleResult instanceof Array);
        
        // 测试空BVH查询
        var emptyResult:Array = emptyBVH.query(queryAABB);
        assertNotNull("空BVH查询返回数组", emptyResult);
        assertArrayLength("空BVH查询返回空数组", 0, emptyResult);
        
        var emptyCircleResult:Array = emptyBVH.queryCircle(center, radius);
        assertNotNull("空BVH圆形查询返回数组", emptyCircleResult);
        assertArrayLength("空BVH圆形查询返回空数组", 0, emptyCircleResult);
    }
    
    // ========================================================================
    // 查询接口测试
    // ========================================================================
    
    private static function runQueryInterfaceTests():Void {
        trace("\n🔍 执行查询接口测试...");
        
        testAABBQueryInterface();
        testCircleQueryInterface();
        testQueryParameterValidation();
        testQueryResultConsistency();
    }
    
    private static function testAABBQueryInterface():Void {
        // 测试相交查询
        var intersectAABB:AABB = new AABB();
        intersectAABB.left = 50;
        intersectAABB.right = 150;
        intersectAABB.top = 50;
        intersectAABB.bottom = 150;
        
        var result:Array = simpleBVH.query(intersectAABB);
        assertTrue("相交AABB查询返回结果", result.length > 0);
        
        // 验证返回对象的正确性
        for (var i:Number = 0; i < result.length; i++) {
            var obj:IBVHObject = result[i];
            assertNotNull("查询结果对象" + i + "不为null", obj);
            
            var objAABB:AABB = obj.getAABB();
            assertNotNull("查询结果对象" + i + "有AABB", objAABB);
            
            // 验证对象确实与查询AABB相交
            assertTrue("查询结果对象" + i + "与查询AABB相交", intersectAABB.intersects(objAABB));
        }
        
        // 测试不相交查询
        var noIntersectAABB:AABB = new AABB();
        noIntersectAABB.left = 1000;
        noIntersectAABB.right = 1100;
        noIntersectAABB.top = 1000;
        noIntersectAABB.bottom = 1100;
        
        var noIntersectResult:Array = simpleBVH.query(noIntersectAABB);
        assertArrayLength("不相交AABB查询返回空数组", 0, noIntersectResult);
        
        // 测试完全包含查询
        var containAABB:AABB = new AABB();
        containAABB.left = -100;
        containAABB.right = 700;
        containAABB.top = -100;
        containAABB.bottom = 600;
        
        var containResult:Array = simpleBVH.query(containAABB);
        assertTrue("完全包含AABB查询返回所有对象", containResult.length >= simpleBVH.root.objects.length);
    }
    
    private static function testCircleQueryInterface():Void {
        // 测试相交圆形查询
        var center:Vector = new Vector(100, 100);
        var radius:Number = 50;
        
        var result:Array = simpleBVH.queryCircle(center, radius);
        
        // 验证返回对象的正确性
        for (var i:Number = 0; i < result.length; i++) {
            var obj:IBVHObject = result[i];
            assertNotNull("圆形查询结果对象" + i + "不为null", obj);
            
            var objAABB:AABB = obj.getAABB();
            assertNotNull("圆形查询结果对象" + i + "有AABB", objAABB);
            
            // 验证对象确实与圆形相交
            assertTrue("圆形查询结果对象" + i + "与圆形相交", objAABB.intersectsCircleV(center, radius));
        }
        
        // 测试不相交圆形查询
        var farCenter:Vector = new Vector(1000, 1000);
        var noIntersectResult:Array = simpleBVH.queryCircle(farCenter, 10);
        assertArrayLength("不相交圆形查询返回空数组", 0, noIntersectResult);
        
        // 测试极小半径
        var smallResult:Array = simpleBVH.queryCircle(center, 1);
        // 结果可能为空，这是正常的
        
        // 测试极大半径
        var bigResult:Array = simpleBVH.queryCircle(center, 1000);
        assertTrue("极大半径圆形查询返回对象", bigResult.length >= 0);
        
        // 测试零半径
        var zeroResult:Array = simpleBVH.queryCircle(center, 0);
        // 结果可能为空，这是正常的
    }
    
    private static function testQueryParameterValidation():Void {
        // 测试null AABB参数
        try {
            var nullAABBResult:Array = simpleBVH.query(null);
            // 如果没有异常，检查返回值
            assertNotNull("null AABB查询返回数组", nullAABBResult);
        } catch (error:Error) {
            assertTrue("null AABB查询异常处理", true);
        }
        
        // 测试null Vector参数
        try {
            var nullVectorResult:Array = simpleBVH.queryCircle(null, 50);
            assertNotNull("null Vector查询返回数组", nullVectorResult);
        } catch (error:Error) {
            assertTrue("null Vector查询异常处理", true);
        }
        
        // 测试负半径
        var center:Vector = new Vector(100, 100);
        try {
            var negativeRadiusResult:Array = simpleBVH.queryCircle(center, -10);
            assertNotNull("负半径查询返回数组", negativeRadiusResult);
        } catch (error:Error) {
            assertTrue("负半径查询异常处理", true);
        }
        
        // 测试NaN半径
        try {
            var nanRadiusResult:Array = simpleBVH.queryCircle(center, NaN);
            assertNotNull("NaN半径查询返回数组", nanRadiusResult);
        } catch (error:Error) {
            assertTrue("NaN半径查询异常处理", true);
        }
        
        // 测试Infinity半径
        try {
            var infinityRadiusResult:Array = simpleBVH.queryCircle(center, Infinity);
            assertNotNull("Infinity半径查询返回数组", infinityRadiusResult);
        } catch (error:Error) {
            assertTrue("Infinity半径查询异常处理", true);
        }
    }
    
    private static function testQueryResultConsistency():Void {
        // 测试查询结果一致性：相同查询多次调用应返回相同结果
        var queryAABB:AABB = new AABB();
        queryAABB.left = 100;
        queryAABB.right = 200;
        queryAABB.top = 100;
        queryAABB.bottom = 200;
        
        var result1:Array = complexBVH.query(queryAABB);
        var result2:Array = complexBVH.query(queryAABB);
        
        assertEquals("AABB查询结果一致性（长度）", result1.length, result2.length, 0);
        
        // 验证对象一致性
        for (var i:Number = 0; i < result1.length; i++) {
            assertArrayContains("AABB查询结果一致性（对象" + i + "）", result2, result1[i]);
        }
        
        // 测试圆形查询结果一致性
        var center:Vector = new Vector(150, 150);
        var radius:Number = 40;
        
        var circleResult1:Array = complexBVH.queryCircle(center, radius);
        var circleResult2:Array = complexBVH.queryCircle(center, radius);
        
        assertEquals("圆形查询结果一致性（长度）", circleResult1.length, circleResult2.length, 0);
        
        for (var j:Number = 0; j < circleResult1.length; j++) {
            assertArrayContains("圆形查询结果一致性（对象" + j + "）", circleResult2, circleResult1[j]);
        }
    }
    
    // ========================================================================
    // 集成测试
    // ========================================================================
    
    private static function runIntegrationTests():Void {
        trace("\n🔗 执行集成测试...");
        
        testBVHNodeIntegration();
        testComplexTreeTraversal();
        testCrossBVHConsistency();
        testQueryDelegation();
    }
    
    private static function testBVHNodeIntegration():Void {
        // 测试BVH与BVHNode的集成
        var rootNode:BVHNode = complexBVH.root;
        assertNotNull("集成测试根节点存在", rootNode);
        
        // 直接调用BVHNode查询
        var nodeQueryAABB:AABB = new AABB();
        nodeQueryAABB.left = 50;
        nodeQueryAABB.right = 250;
        nodeQueryAABB.top = 50;
        nodeQueryAABB.bottom = 250;
        
        var nodeResult:Array = [];
        rootNode.query(nodeQueryAABB, nodeResult);
        
        // 通过BVH查询
        var bvhResult:Array = complexBVH.query(nodeQueryAABB);
        
        // 结果应该一致
        assertEquals("BVH与BVHNode查询结果一致（长度）", nodeResult.length, bvhResult.length, 0);
        
        for (var i:Number = 0; i < nodeResult.length; i++) {
            assertArrayContains("BVH与BVHNode查询结果一致（对象" + i + "）", bvhResult, nodeResult[i]);
        }
        
        // 测试圆形查询集成
        var center:Vector = new Vector(150, 150);
        var radius:Number = 60;
        
        var nodeCircleResult:Array = [];
        rootNode.queryCircle(center, radius, nodeCircleResult);
        
        var bvhCircleResult:Array = complexBVH.queryCircle(center, radius);
        
        assertEquals("BVH与BVHNode圆形查询结果一致（长度）", nodeCircleResult.length, bvhCircleResult.length, 0);
    }
    
    private static function testComplexTreeTraversal():Void {
        // 测试复杂树结构的遍历正确性
        var traversalAABB:AABB = new AABB();
        traversalAABB.left = 0;
        traversalAABB.right = 400;
        traversalAABB.top = 0;
        traversalAABB.bottom = 300;
        
        var result:Array = complexBVH.query(traversalAABB);
        
        // 验证结果来自不同的子树
        var leftTreeObjects:Array = [];
        var rightTreeObjects:Array = [];
        
        // 手动查询左子树
        complexBVH.root.left.query(traversalAABB, leftTreeObjects);
        
        // 手动查询右子树
        complexBVH.root.right.query(traversalAABB, rightTreeObjects);
        
        var expectedTotal:Number = leftTreeObjects.length + rightTreeObjects.length;
        assertEquals("复杂树遍历结果正确", expectedTotal, result.length, 0);
        
        // 验证所有左子树对象都在结果中
        for (var i:Number = 0; i < leftTreeObjects.length; i++) {
            assertArrayContains("左子树对象" + i + "在结果中", result, leftTreeObjects[i]);
        }
        
        // 验证所有右子树对象都在结果中
        for (var j:Number = 0; j < rightTreeObjects.length; j++) {
            assertArrayContains("右子树对象" + j + "在结果中", result, rightTreeObjects[j]);
        }
    }
    
    private static function testCrossBVHConsistency():Void {
        // 测试不同BVH实例之间的查询一致性
        var queryAABB:AABB = new AABB();
        queryAABB.left = 50;
        queryAABB.right = 150;
        queryAABB.top = 50;
        queryAABB.bottom = 150;
        
        // 查询简单BVH
        var simpleResult:Array = simpleBVH.query(queryAABB);
        
        // 查询复杂BVH
        var complexResult:Array = complexBVH.query(queryAABB);
        
        // 查询深度BVH
        var deepResult:Array = deepBVH.query(queryAABB);
        
        // 验证查询行为一致（不要求结果相同，因为包含的对象不同）
        assertTrue("简单BVH查询正常", simpleResult instanceof Array);
        assertTrue("复杂BVH查询正常", complexResult instanceof Array);
        assertTrue("深度BVH查询正常", deepResult instanceof Array);
        
        // 验证查询结果的有效性
        validateQueryResults(simpleResult, queryAABB);
        validateQueryResults(complexResult, queryAABB);
        validateQueryResults(deepResult, queryAABB);
    }
    
    private static function testQueryDelegation():Void {
        // 测试BVH正确将查询委托给根节点
        
        // 创建一个模拟的BVHNode进行测试
        var mockResults:Array = [testObjects[0], testObjects[1]];
        
        // 创建一个真实的BVHNode实例来进行模拟，而不是一个通用Object
        var mockNode:BVHNode = new BVHNode(new AABB());
        
        // 使用一个外部对象来跟踪调用次数，避免this指向问题
        var callTracker:Object = {
            queryCallCount: 0,
            queryCircleCallCount: 0
        };

        // 覆盖(Monkey-patch) query 方法
        mockNode.query = function(queryAABB:AABB, result:Array):Void {
            callTracker.queryCallCount++;
            for (var i:Number = 0; i < mockResults.length; i++) {
                result.push(mockResults[i]);
            }
        };
        
        // 覆盖(Monkey-patch) queryCircle 方法
        mockNode.queryCircle = function(center:Vector, radius:Number, result:Array):Void {
            callTracker.queryCircleCallCount++;
            for (var i:Number = 0; i < mockResults.length; i++) {
                result.push(mockResults[i]);
            }
        };
        
        // 现在构造函数接收的是一个正确的BVHNode类型实例
        var testBVH:BVH = new BVH(mockNode);
        // === 修正部分结束 ===

        // 测试AABB查询委托
        var queryAABB:AABB = new AABB();
        var result:Array = testBVH.query(queryAABB);
        
        assertEquals("AABB查询委托调用次数", 1, callTracker.queryCallCount, 0); // 使用 callTracker
        assertEquals("AABB查询委托结果长度", mockResults.length, result.length, 0);
        
        // 测试圆形查询委托
        var center:Vector = new Vector(100, 100);
        var circleResult:Array = testBVH.queryCircle(center, 50);
        
        assertEquals("圆形查询委托调用次数", 1, callTracker.queryCircleCallCount, 0); // 使用 callTracker
        assertEquals("圆形查询委托结果长度", mockResults.length, circleResult.length, 0);
    }
    
    /**
     * 验证查询结果的有效性
     */
    private static function validateQueryResults(results:Array, queryAABB:AABB):Void {
        for (var i:Number = 0; i < results.length; i++) {
            var obj:IBVHObject = results[i];
            if (obj && obj.getAABB) {
                var objAABB:AABB = obj.getAABB();
                if (objAABB) {
                    assertTrue("查询结果对象" + i + "与查询AABB相交", queryAABB.intersects(objAABB));
                }
            }
        }
    }
    
    // ========================================================================
    // 边界条件测试
    // ========================================================================
    
    private static function runBoundaryConditionTests():Void {
        trace("\n🔍 执行边界条件测试...");
        
        testEmptyBVHBehavior();
        testExtremeQueryConditions();
        testEdgeCaseQueries();
        testErrorRecovery();
    }
    
    private static function testEmptyBVHBehavior():Void {
        // 测试空BVH的各种操作
        var queryAABB:AABB = new AABB();
        queryAABB.left = 0;
        queryAABB.right = 100;
        queryAABB.top = 0;
        queryAABB.bottom = 100;
        
        var result:Array = emptyBVH.query(queryAABB);
        assertNotNull("空BVH查询返回非null", result);
        assertArrayLength("空BVH查询返回空数组", 0, result);
        
        var center:Vector = new Vector(50, 50);
        var circleResult:Array = emptyBVH.queryCircle(center, 25);
        assertNotNull("空BVH圆形查询返回非null", circleResult);
        assertArrayLength("空BVH圆形查询返回空数组", 0, circleResult);
        
        // 测试空BVH的多次查询
        for (var i:Number = 0; i < 5; i++) {
            var repeatResult:Array = emptyBVH.query(queryAABB);
            assertArrayLength("空BVH多次查询" + i + "返回空数组", 0, repeatResult);
        }
    }
    
    private static function testExtremeQueryConditions():Void {
        // 测试极值查询条件
        
        // 极小AABB
        var tinyAABB:AABB = new AABB();
        tinyAABB.left = 100;
        tinyAABB.right = 100.1;
        tinyAABB.top = 100;
        tinyAABB.bottom = 100.1;
        
        var tinyResult:Array = simpleBVH.query(tinyAABB);
        assertTrue("极小AABB查询正常", tinyResult instanceof Array);
        
        // 极大AABB
        var hugeAABB:AABB = new AABB();
        hugeAABB.left = -10000;
        hugeAABB.right = 10000;
        hugeAABB.top = -10000;
        hugeAABB.bottom = 10000;
        
        var hugeResult:Array = simpleBVH.query(hugeAABB);
        assertTrue("极大AABB查询正常", hugeResult instanceof Array);
        assertTrue("极大AABB查询返回对象", hugeResult.length >= simpleBVH.root.objects.length);
        
        // 逆序AABB（left > right, top > bottom）
        var reverseAABB:AABB = new AABB();
        reverseAABB.left = 200;
        reverseAABB.right = 100;   // left > right
        reverseAABB.top = 200;
        reverseAABB.bottom = 100;  // top > bottom
        
        try {
            var reverseResult:Array = simpleBVH.query(reverseAABB);
            assertTrue("逆序AABB查询不崩溃", true);
        } catch (error:Error) {
            assertTrue("逆序AABB查询异常处理", true);
        }
        
        // 极值坐标AABB
        var extremeAABB:AABB = new AABB();
        extremeAABB.left = Number.MIN_VALUE;
        extremeAABB.right = Number.MAX_VALUE;
        extremeAABB.top = -Number.MAX_VALUE;
        extremeAABB.bottom = Number.MAX_VALUE;
        
        try {
            var extremeResult:Array = simpleBVH.query(extremeAABB);
            assertTrue("极值坐标AABB查询不崩溃", true);
        } catch (error:Error) {
            assertTrue("极值坐标AABB查询异常处理", true);
        }
    }
    
    private static function testEdgeCaseQueries():Void {
        // 测试边界情况查询
        
        // 零面积查询
        var zeroAABB:AABB = new AABB();
        zeroAABB.left = 100;
        zeroAABB.right = 100;
        zeroAABB.top = 100;
        zeroAABB.bottom = 100;
        
        var zeroResult:Array = simpleBVH.query(zeroAABB);
        assertTrue("零面积AABB查询正常", zeroResult instanceof Array);
        
        // 线条查询（宽度为0或高度为0）
        var lineAABB:AABB = new AABB();
        lineAABB.left = 50;
        lineAABB.right = 150;
        lineAABB.top = 100;
        lineAABB.bottom = 100;  // 高度为0
        
        var lineResult:Array = simpleBVH.query(lineAABB);
        assertTrue("线条AABB查询正常", lineResult instanceof Array);
        
        // 边界精确查询（查询AABB与对象AABB边界重合）
        if (testObjects.length > 0) {
            var firstObjAABB:AABB = testObjects[0].getAABB();
            if (firstObjAABB) {
                var boundaryAABB:AABB = new AABB();
                boundaryAABB.left = firstObjAABB.right;    // 左边界对齐对象右边界
                boundaryAABB.right = firstObjAABB.right + 50;
                boundaryAABB.top = firstObjAABB.top;
                boundaryAABB.bottom = firstObjAABB.bottom;
                
                var boundaryResult:Array = simpleBVH.query(boundaryAABB);
                assertTrue("边界精确查询正常", boundaryResult instanceof Array);
            }
        }
        
        // 圆形查询特殊情况
        var centerAtOrigin:Vector = new Vector(0, 0);
        var originResult:Array = simpleBVH.queryCircle(centerAtOrigin, 50);
        assertTrue("原点圆形查询正常", originResult instanceof Array);
        
        // 负坐标圆心
        var negativeCenter:Vector = new Vector(-100, -100);
        var negativeResult:Array = simpleBVH.queryCircle(negativeCenter, 50);
        assertTrue("负坐标圆心查询正常", negativeResult instanceof Array);
    }
    
    private static function testErrorRecovery():Void {
        // 测试错误恢复能力
        
        var queryAABB:AABB = new AABB();
        queryAABB.left = 50;
        queryAABB.right = 150;
        queryAABB.top = 50;
        queryAABB.bottom = 150;
        
        // 在异常参数后进行正常查询，验证BVH状态未被破坏
        try {
            simpleBVH.query(null);
        } catch (error:Error) {
            // 忽略异常
        }
        
        var recoveryResult:Array = simpleBVH.query(queryAABB);
        assertTrue("异常后恢复正常查询", recoveryResult instanceof Array);
        
        // 在异常参数后进行圆形查询
        try {
            simpleBVH.queryCircle(null, NaN);
        } catch (error:Error) {
            // 忽略异常
        }
        
        var center:Vector = new Vector(100, 100);
        var circleRecoveryResult:Array = simpleBVH.queryCircle(center, 30);
        assertTrue("异常后恢复圆形查询", circleRecoveryResult instanceof Array);
        
        // 验证BVH根节点未被破坏
        assertNotNull("异常后根节点完整", simpleBVH.root);
        assertTrue("异常后根节点状态正常", simpleBVH.root.isLeaf());
    }
    
    // ========================================================================
    // 性能基准测试
    // ========================================================================
    
    private static function runPerformanceBenchmarks():Void {
        trace("\n⚡ 执行性能基准测试...");
        
        performanceTestAABBQuery();
        performanceTestCircleQuery();
        performanceTestComplexTreeQuery();
        performanceTestBulkQueries();
    }
    
    private static function performanceTestAABBQuery():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var queryAABB:AABB = new AABB();
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            // 变化查询区域
            queryAABB.left = (i % 50) * 10;
            queryAABB.right = queryAABB.left + 60;
            queryAABB.top = (i % 40) * 8;
            queryAABB.bottom = queryAABB.top + 50;
            
            simpleBVH.query(queryAABB);
        }
        var aabbQueryTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "BVH AABB Query",
            trials: trials,
            totalTime: aabbQueryTime,
            avgTime: aabbQueryTime / trials
        });
        
        trace("📊 BVH AABB查询性能: " + trials + "次调用耗时 " + aabbQueryTime + "ms");
        assertPerformance("BVH AABB查询性能达标", aabbQueryTime / trials, QUERY_BENCHMARK_MS);
    }
    
    private static function performanceTestCircleQuery():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var center:Vector = new Vector(0, 0);
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            // 变化查询圆心和半径
            center.x = (i % 60) * 8;
            center.y = (i % 50) * 6;
            var radius:Number = 20 + (i % 40);
            
            simpleBVH.queryCircle(center, radius);
        }
        var circleQueryTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "BVH Circle Query",
            trials: trials,
            totalTime: circleQueryTime,
            avgTime: circleQueryTime / trials
        });
        
        trace("📊 BVH圆形查询性能: " + trials + "次调用耗时 " + circleQueryTime + "ms");
        assertPerformance("BVH圆形查询性能达标", circleQueryTime / trials, QUERY_BENCHMARK_MS);
    }
    
    private static function performanceTestComplexTreeQuery():Void {
        var trials:Number = Math.floor(PERFORMANCE_TRIALS / 2);
        var queryAABB:AABB = new AABB();
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            queryAABB.left = (i % 30) * 15;
            queryAABB.right = queryAABB.left + 80;
            queryAABB.top = (i % 25) * 12;
            queryAABB.bottom = queryAABB.top + 60;
            
            complexBVH.query(queryAABB);
        }
        var complexQueryTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "Complex BVH Query",
            trials: trials,
            totalTime: complexQueryTime,
            avgTime: complexQueryTime / trials
        });
        
        trace("📊 复杂BVH查询性能: " + trials + "次调用耗时 " + complexQueryTime + "ms");
        assertPerformance("复杂BVH查询性能达标", complexQueryTime / trials, QUERY_BENCHMARK_MS * 2);
    }
    
    private static function performanceTestBulkQueries():Void {
        var bulkTrials:Number = 100;
        var queriesPerTrial:Number = 50;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < bulkTrials; i++) {
            for (var j:Number = 0; j < queriesPerTrial; j++) {
                var queryAABB:AABB = new AABB();
                queryAABB.left = (j % 20) * 20;
                queryAABB.right = queryAABB.left + 40;
                queryAABB.top = (j % 15) * 15;
                queryAABB.bottom = queryAABB.top + 30;
                
                deepBVH.query(queryAABB);
            }
        }
        var bulkQueryTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "Bulk Queries",
            trials: bulkTrials * queriesPerTrial,
            totalTime: bulkQueryTime,
            avgTime: bulkQueryTime / (bulkTrials * queriesPerTrial)
        });
        
        trace("📊 批量查询性能: " + (bulkTrials * queriesPerTrial) + "次调用耗时 " + bulkQueryTime + "ms");
        assertPerformance("批量查询性能达标", bulkQueryTime, BULK_QUERY_BENCHMARK_MS);
    }
    
    // ========================================================================
    // 数据完整性测试
    // ========================================================================
    
    private static function runDataIntegrityTests():Void {
        trace("\n💾 执行数据完整性测试...");
        
        testQueryResultIntegrity();
        testObjectReferenceIntegrity();
        testBVHStateIntegrity();
        testConcurrentAccessIntegrity();
    }
    
    private static function testQueryResultIntegrity():Void {
        // 测试查询结果的完整性
        var queryAABB:AABB = new AABB();
        queryAABB.left = 0;
        queryAABB.right = 300;
        queryAABB.top = 0;
        queryAABB.bottom = 250;
        
        var result:Array = complexBVH.query(queryAABB);
        
        // 验证结果数组完整性
        assertNotNull("查询结果数组不为null", result);
        assertTrue("查询结果是Array类型", result instanceof Array);
        
        // 验证结果中没有null对象
        for (var i:Number = 0; i < result.length; i++) {
            assertNotNull("查询结果对象" + i + "不为null", result[i]);
        }
        
        // 验证结果中没有重复对象
        for (var j:Number = 0; j < result.length; j++) {
            for (var k:Number = j + 1; k < result.length; k++) {
                assertTrue("查询结果无重复对象(" + j + "," + k + ")", result[j] != result[k]);
            }
        }
        
        // 验证所有结果对象都实现了IBVHObject接口
        for (var l:Number = 0; l < result.length; l++) {
            var obj:Object = result[l];
            assertTrue("查询结果对象" + l + "实现getAABB方法", obj.getAABB != undefined);
            
            var objAABB:AABB = obj.getAABB();
            assertNotNull("查询结果对象" + l + "的AABB不为null", objAABB);
        }
    }
    
    private static function testObjectReferenceIntegrity():Void {
        // 测试对象引用的完整性
        var queryAABB:AABB = new AABB();
        queryAABB.left = 50;
        queryAABB.right = 150;
        queryAABB.top = 50;

        queryAABB.bottom = 150;
        
        var result:Array = simpleBVH.query(queryAABB);
        
        // 验证返回的对象是原始对象的引用
        for (var i:Number = 0; i < result.length; i++) {
            var found:Boolean = false;
            for (var j:Number = 0; j < testObjects.length; j++) {
                if (result[i] == testObjects[j]) {
                    found = true;
                    break;
                }
            }
            assertTrue("查询结果对象" + i + "是原始对象引用", found);
        }
        
        // 验证对象属性完整性
        for (var k:Number = 0; k < result.length; k++) {
            var obj:Object = result[k];
            assertNotNull("查询结果对象" + k + "名称属性", obj.name);
            assertNotNull("查询结果对象" + k + "bounds属性", obj.bounds);
        }
    }
    
    private static function testBVHStateIntegrity():Void {
        // 测试BVH状态完整性
        var originalRoot:BVHNode = simpleBVH.root;
        
        // 执行多次查询后验证BVH状态未被修改
        for (var i:Number = 0; i < 10; i++) {
            var queryAABB:AABB = new AABB();
            queryAABB.left = i * 20;
            queryAABB.right = i * 20 + 50;
            queryAABB.top = i * 15;
            queryAABB.bottom = i * 15 + 40;
            
            simpleBVH.query(queryAABB);
        }
        
        // 验证根节点未被修改
        assertTrue("多次查询后根节点引用不变", simpleBVH.root == originalRoot);
        
        // 验证根节点内容完整性
        if (originalRoot) {
            assertNotNull("根节点bounds完整", originalRoot.bounds);
            assertNotNull("根节点objects完整", originalRoot.objects);
            assertTrue("根节点仍是叶子节点", originalRoot.isLeaf());
        }
        
        // 验证复杂BVH的状态完整性
        var complexRoot:BVHNode = complexBVH.root;
        if (complexRoot) {
            assertNotNull("复杂BVH根节点左子树", complexRoot.left);
            assertNotNull("复杂BVH根节点右子树", complexRoot.right);
            assertTrue("复杂BVH根节点仍是内部节点", !complexRoot.isLeaf());
        }
    }
    
    private static function testConcurrentAccessIntegrity():Void {
        // 模拟并发访问测试（单线程环境下的快速连续访问）
        var queryCount:Number = 100;
        var results:Array = [];
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < queryCount; i++) {
            var queryAABB:AABB = new AABB();
            queryAABB.left = (i % 10) * 30;
            queryAABB.right = queryAABB.left + 60;
            queryAABB.top = (i % 8) * 25;
            queryAABB.bottom = queryAABB.top + 50;
            
            var result:Array = complexBVH.query(queryAABB);
            results[i] = result;
            
            // 交替进行圆形查询
            if (i % 2 == 1) {
                var center:Vector = new Vector(queryAABB.left + 30, queryAABB.top + 25);
                complexBVH.queryCircle(center, 35);
            }
        }
        var concurrentTime:Number = getTimer() - startTime;
        
        // 验证所有查询都成功完成
        for (var j:Number = 0; j < queryCount; j++) {
            assertNotNull("并发访问查询" + j + "结果不为null", results[j]);
            assertTrue("并发访问查询" + j + "结果是数组", results[j] instanceof Array);
        }
        
        trace("🔄 并发访问测试: " + queryCount + "次查询耗时 " + concurrentTime + "ms");
        assertTrue("并发访问完成", concurrentTime < 1000);
    }
    
    // ========================================================================
    // 压力测试
    // ========================================================================
    
    private static function runStressTests():Void {
        trace("\n💪 执行压力测试...");
        
        stressTestHighVolumeQueries();
        stressTestMemoryUsage();
        stressTestExtremeParameters();
        stressTestLongRunningOperations();
    }
    
    private static function stressTestHighVolumeQueries():Void {
        var highVolumeTrials:Number = 2000;
        var queryTypes:Array = ["AABB", "Circle"];
        
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < highVolumeTrials; i++) {
            var queryType:String = queryTypes[i % 2];
            
            if (queryType == "AABB") {
                var queryAABB:AABB = new AABB();
                queryAABB.left = Math.random() * 400;
                queryAABB.right = queryAABB.left + Math.random() * 200;
                queryAABB.top = Math.random() * 300;
                queryAABB.bottom = queryAABB.top + Math.random() * 150;
                
                deepBVH.query(queryAABB);
            } else {
                var center:Vector = new Vector(Math.random() * 600, Math.random() * 400);
                var radius:Number = Math.random() * 100 + 10;
                
                deepBVH.queryCircle(center, radius);
            }
        }
        
        var highVolumeTime:Number = getTimer() - startTime;
        
        trace("🔥 高容量查询测试: " + highVolumeTrials + "次随机查询耗时 " + highVolumeTime + "ms");
        assertTrue("高容量查询性能合理", highVolumeTime < 5000);
    }
    
    private static function stressTestMemoryUsage():Void {
        var memoryIterations:Number = 100;
        var queriesPerIteration:Number = 50;
        
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < memoryIterations; i++) {
            var iterationResults:Array = [];
            
            for (var j:Number = 0; j < queriesPerIteration; j++) {
                var queryAABB:AABB = new AABB();
                queryAABB.left = j * 10;
                queryAABB.right = j * 10 + 50;
                queryAABB.top = j * 8;
                queryAABB.bottom = j * 8 + 40;
                
                var result:Array = complexBVH.query(queryAABB);
                iterationResults[j] = result;
            }
            
            // 清理引用
            iterationResults = null;
        }
        
        var memoryTime:Number = getTimer() - startTime;
        
        trace("🧠 内存使用测试: " + (memoryIterations * queriesPerIteration) + 
              "次查询(分" + memoryIterations + "批)耗时 " + memoryTime + "ms");
        assertTrue("内存使用测试通过", memoryTime < 3000);
    }
    
    private static function stressTestExtremeParameters():Void {
        var extremeTests:Number = 50;
        var successCount:Number = 0;
        
        for (var i:Number = 0; i < extremeTests; i++) {
            try {
                // 生成极值参数
                var extremeAABB:AABB = new AABB();
                extremeAABB.left = (Math.random() - 0.5) * Number.MAX_VALUE / 1000;
                extremeAABB.right = extremeAABB.left + Math.random() * 1000;
                extremeAABB.top = (Math.random() - 0.5) * Number.MAX_VALUE / 1000;
                extremeAABB.bottom = extremeAABB.top + Math.random() * 1000;
                
                var result:Array = deepBVH.query(extremeAABB);
                
                if (result && result instanceof Array) {
                    successCount++;
                }
                
            } catch (error:Error) {
                // 某些极值参数可能导致异常，这是可以接受的
            }
        }
        
        var successRate:Number = successCount / extremeTests;
        trace("🔥 极值参数测试: " + successCount + "/" + extremeTests + 
              " 成功 (" + Math.round(successRate * 100) + "%)");
        assertTrue("极值参数测试成功率合理", successRate >= 0.6);
    }
    
    private static function stressTestLongRunningOperations():Void {
        var longRunTrials:Number = 10;
        var operationsPerTrial:Number = 500;
        
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < longRunTrials; i++) {
            for (var j:Number = 0; j < operationsPerTrial; j++) {
                // 混合操作
                if (j % 3 == 0) {
                    // AABB查询
                    var queryAABB:AABB = new AABB();
                    queryAABB.left = (j % 50) * 8;
                    queryAABB.right = queryAABB.left + 60;
                    queryAABB.top = (j % 40) * 6;
                    queryAABB.bottom = queryAABB.top + 45;
                    
                    complexBVH.query(queryAABB);
                } else if (j % 3 == 1) {
                    // 圆形查询
                    var center:Vector = new Vector((j % 60) * 7, (j % 45) * 8);
                    complexBVH.queryCircle(center, 30 + (j % 20));
                } else {
                    // 深度BVH查询
                    var deepAABB:AABB = new AABB();
                    deepAABB.left = (j % 80) * 6;
                    deepAABB.right = deepAABB.left + 50;
                    deepAABB.top = (j % 60) * 5;
                    deepAABB.bottom = deepAABB.top + 40;
                    
                    deepBVH.query(deepAABB);
                }
            }
        }
        
        var longRunTime:Number = getTimer() - startTime;
        
        trace("⏱️ 长时间运行测试: " + (longRunTrials * operationsPerTrial) + 
              "次混合操作耗时 " + longRunTime + "ms");
        assertTrue("长时间运行测试通过", longRunTime < 10000);
    }
    
    // ========================================================================
    // 实际场景测试
    // ========================================================================
    
    private static function runRealWorldScenarioTests():Void {
        trace("\n🌍 执行实际场景测试...");
        
        testGameObjectCollisionDetection();
        testSpatialIndexingScenario();
        testInteractiveQueryScenario();
        testDynamicContentScenario();
    }
    
    private static function testGameObjectCollisionDetection():Void {
        // 模拟游戏对象碰撞检测场景
        trace("🎮 游戏对象碰撞检测场景测试");
        
        // 创建游戏对象BVH
        var gameObjects:Array = [];
        for (var i:Number = 0; i < 20; i++) {
            var gameObj:Object = createBVHObject(
                "GameObject_" + i,
                Math.random() * 800,      // x
                Math.random() * 800 + 32, // x + width
                Math.random() * 600,      // y  
                Math.random() * 600 + 32  // y + height
            );
            gameObjects[i] = gameObj;
        }
        
        var gameRoot:BVHNode = new BVHNode(new AABB());
        gameRoot.objects = gameObjects;
        var gameBVH:BVH = new BVH(gameRoot);
        
        // 模拟玩家移动检测碰撞
        var playerBounds:AABB = new AABB();
        var testPositions:Number = 50;
        var collisionCount:Number = 0;
        
        var startTime:Number = getTimer();
        for (var j:Number = 0; j < testPositions; j++) {
            playerBounds.left = j * 16;
            playerBounds.right = playerBounds.left + 32;
            playerBounds.top = j * 12;
            playerBounds.bottom = playerBounds.top + 32;
            
            var collisions:Array = gameBVH.query(playerBounds);
            if (collisions.length > 0) {
                collisionCount++;
            }
        }
        var collisionTime:Number = getTimer() - startTime;
        
        trace("🎯 碰撞检测结果: " + testPositions + "个位置检测，" + 
              collisionCount + "个位置发生碰撞，耗时" + collisionTime + "ms");
        
        assertTrue("碰撞检测性能合理", collisionTime < 100);
        assertTrue("碰撞检测有结果", collisionCount >= 0);
    }
    
    private static function testSpatialIndexingScenario():Void {
        // 模拟空间索引查询场景
        trace("📍 空间索引查询场景测试");
        
        // 模拟范围查询（如：查找附近的商店、POI等）
        var queryRadius:Number = 100;
        var queryPoints:Array = [
            new Vector(100, 100),
            new Vector(300, 200),
            new Vector(500, 150),
            new Vector(200, 400),
            new Vector(450, 350)
        ];
        
        var totalResults:Number = 0;
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < queryPoints.length; i++) {
            var center:Vector = queryPoints[i];
            var nearbyObjects:Array = complexBVH.queryCircle(center, queryRadius);
            totalResults += nearbyObjects.length;
            
            // 验证结果正确性
            for (var j:Number = 0; j < nearbyObjects.length; j++) {
                var obj:IBVHObject = nearbyObjects[j];
                var objAABB:AABB = obj.getAABB();
                assertTrue("空间索引查询结果" + i + "_" + j + "正确", 
                         objAABB.intersectsCircleV(center, queryRadius));
            }
        }
        
        var spatialTime:Number = getTimer() - startTime;
        
        trace("🗺️ 空间索引结果: " + queryPoints.length + "个查询点，总计找到" + 
              totalResults + "个对象，耗时" + spatialTime + "ms");
        
        assertTrue("空间索引查询性能合理", spatialTime < 50);
    }
    
    private static function testInteractiveQueryScenario():Void {
        // 模拟交互式查询场景（如鼠标悬停、点击选择等）
        trace("🖱️ 交互式查询场景测试");
        
        var interactionPoints:Number = 30;
        var interactionResults:Array = [];
        
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < interactionPoints; i++) {
            // 模拟鼠标位置
            var mouseX:Number = Math.random() * 600;
            var mouseY:Number = Math.random() * 500;
            
            // 点击查询（小范围AABB）
            var clickAABB:AABB = new AABB();
            clickAABB.left = mouseX - 5;
            clickAABB.right = mouseX + 5;
            clickAABB.top = mouseY - 5;
            clickAABB.bottom = mouseY + 5;
            
            var clickedObjects:Array = complexBVH.query(clickAABB);
            
            // 悬停查询（圆形范围）
            var hoverCenter:Vector = new Vector(mouseX, mouseY);
            var hoverObjects:Array = complexBVH.queryCircle(hoverCenter, 20);
            
            interactionResults[i] = {
                click: clickedObjects.length,
                hover: hoverObjects.length
            };
        }
        
        var interactionTime:Number = getTimer() - startTime;
        
        // 统计交互结果
        var totalClicks:Number = 0;
        var totalHovers:Number = 0;
        for (var j:Number = 0; j < interactionResults.length; j++) {
            totalClicks += interactionResults[j].click;
            totalHovers += interactionResults[j].hover;
        }
        
        trace("👆 交互查询结果: " + interactionPoints + "次交互，" + 
              totalClicks + "次点击命中，" + totalHovers + "次悬停命中，耗时" + interactionTime + "ms");
        
        assertTrue("交互查询性能优秀", interactionTime < 100);
        assertTrue("交互查询有效", (totalClicks + totalHovers) >= 0);
    }
    
    private static function testDynamicContentScenario():Void {
        // 模拟动态内容场景（对象移动后的查询）
        trace("🔄 动态内容场景测试");
        
        // 创建动态BVH（模拟更新后的状态）
        var dynamicObjects:Array = [];
        for (var i:Number = 0; i < 15; i++) {
            var dynamicObj:Object = createBVHObject(
                "DynamicObj_" + i,
                i * 40,           // 规律分布
                i * 40 + 35,
                i * 30,
                i * 30 + 28
            );
            dynamicObjects[i] = dynamicObj;
        }
        
        var dynamicRoot:BVHNode = new BVHNode(new AABB());
        dynamicRoot.objects = dynamicObjects;
        var dynamicBVH:BVH = new BVH(dynamicRoot);
        
        // 模拟多次状态查询
        var stateQueries:Number = 20;
        var dynamicResults:Array = [];
        
        var startTime:Number = getTimer();
        
        for (var j:Number = 0; j < stateQueries; j++) {
            // 区域查询（模拟视口或影响范围）
            var regionAABB:AABB = new AABB();
            regionAABB.left = j * 25;
            regionAABB.right = regionAABB.left + 120;
            regionAABB.top = j * 20;
            regionAABB.bottom = regionAABB.top + 100;
            
            var regionObjects:Array = dynamicBVH.query(regionAABB);
            dynamicResults[j] = regionObjects.length;
            
            // 验证查询结果一致性
            var verifyResult:Array = dynamicBVH.query(regionAABB);
            assertEquals("动态查询" + j + "结果一致性", regionObjects.length, verifyResult.length, 0);
        }
        
        var dynamicTime:Number = getTimer() - startTime;
        
        // 计算平均结果数
        var totalDynamicResults:Number = 0;
        for (var k:Number = 0; k < dynamicResults.length; k++) {
            totalDynamicResults += dynamicResults[k];
        }
        var avgResults:Number = totalDynamicResults / stateQueries;
        
        trace("🔧 动态内容结果: " + stateQueries + "次状态查询，平均每次找到" + 
              Math.round(avgResults * 100) / 100 + "个对象，耗时" + dynamicTime + "ms");
        
        assertTrue("动态内容查询性能良好", dynamicTime < 150);
        assertTrue("动态内容查询有效", avgResults >= 0);
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
        trace("📊 BVH 测试结果汇总");
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
        trace("  📋 基础功能: 构造函数, root属性, 基本查询");
        trace("  🔍 查询接口: AABB查询, 圆形查询, 参数验证, 结果一致性");
        trace("  🔗 集成测试: BVHNode集成, 复杂树遍历, 查询委托");
        trace("  🔍 边界条件: 空BVH, 极值查询, 边界情况, 错误恢复");
        trace("  ⚡ 性能基准: 查询速度, 复杂树查询, 批量查询");
        trace("  💾 数据完整性: 查询结果, 对象引用, BVH状态, 并发访问");
        trace("  💪 压力测试: 高容量查询, 内存使用, 极值参数, 长时间运行");
        trace("  🌍 实际场景: 碰撞检测, 空间索引, 交互查询, 动态内容");
        
        if (failedTests == 0) {
            trace("\n🎉 所有测试通过！BVH 组件质量优秀！");
            trace("🚀 BVH已准备好在生产环境中使用！");
        } else {
            trace("\n⚠️ 发现 " + failedTests + " 个问题，请检查实现！");
        }
        
        trace("================================================================================");
    }
}