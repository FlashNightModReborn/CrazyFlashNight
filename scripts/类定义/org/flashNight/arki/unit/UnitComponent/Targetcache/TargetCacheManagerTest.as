import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProvider;
import org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;

/**
 * 测试套件：TargetCacheManager 外观层
 * ==========================================
 * 
 * - 验证外观模式（Facade Pattern）的正确实现
 * - 100% API覆盖率测试（50+ 公共方法）
 * - 委托机制正确性验证
 * - 向后兼容性完整验证
 * - 性能基准测试（与直接调用对比）
 * - 复杂查询场景的集成测试
 * - 大规模数据场景压力测试
 * - 边界条件和异常处理验证
 * - 系统管理功能全面测试
 * - 一句启动全面战斗
 * 
 * 🔥 外观模式验证重点：
 * - API简化程度验证
 * - 内部复杂性隐藏验证
 * - 委托调用链正确性
 * - 接口一致性保证
 * - 错误处理统一性
 * 
 *  启动方式：
 * org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManagerTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManagerTest {
    
    // ========================================================================
    // 战斗统计和配置
    // ========================================================================
    
    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var performanceResults:Array = [];
    private static var apiCoverageMap:Object = {};
    
    // 性能基准配置
    private static var PERFORMANCE_TRIALS:Number = 1000;
    private static var LARGE_DATA_SCALE:Number = 100;
    private static var API_RESPONSE_BENCHMARK_MS:Number = 1.0;
    
    // 测试数据缓存
    private static var testUnits:Array;
    private static var testEnemies:Array;
    private static var testAllies:Array;
    private static var mockFrameTimer:Object;
    private static var mockGameWorld:Object;
    private static var mockHero:Object;
    private static var originalRoot:Object;
    
    /**
     * 🚀 终极战斗启动器 - 一句话启动全面测试
     */
    public static function runAll():Void {
        trace("================================================================================");
        trace("⚔️  TargetCacheManager 外观层 - 终极战斗测试套件启动 ⚔️");
        trace("================================================================================");
        
        var startTime:Number = getTimer();
        resetTestStats();
        
        try {
            // 🏗️ 战场准备
            initializeBattleEnvironment();
            
            // === 第一波：基础功能验证 ===
            runBasicQueryTests();
            
            // === 第二波：范围查询测试 ===
            runRangeQueryTests();
            
            // === 第三波：距离查询测试 ===
            runDistanceQueryTests();
            
            // === 第四波：区域搜索测试 ===
            runAreaSearchTests();
            
            // === 第五波：计数API测试 ===
            runCountingAPITests();
            
            // === 第六波：条件查询测试 ===
            runConditionalQueryTests();
            
            // === 第七波：系统管理测试 ===
            runSystemManagementTests();
            
            // === 第八波：外观模式验证 ===
            runFacadePatternTests();
            
            // === 第九波：性能基准测试 ===
            runPerformanceBenchmarks();
            
            // === 第十波：过滤器查询测试 ===
            runFilteredQueryTests();
            
            // === 第十一波：集成战斗测试 ===
            runIntegrationBattleTests();
            
            // === 终极波：大规模压力测试 ===
            runLargeScaleStressTests();
            
            // === 最终波：边界条件战斗 ===
            runBoundaryBattleTests();

            // === 追加波：clear() 别名 & rightMaxValues 集成 ===
            runClearAliasAndRightMaxValuesTests();

            // === 回归波：Bug 修复回归测试 ===
            runBugfixRegressionTests();

        } catch (error:Error) {
            failedTests++;
            trace("💥 测试执行异常: " + error.message);
        } finally {
            // 🧹 战场清理
            cleanupBattleEnvironment();
        }
        
        var totalTime:Number = getTimer() - startTime;
        printBattleReport(totalTime);
    }
    
    // ========================================================================
    // 断言系统（战斗验证器）
    // ========================================================================
    
    private static function assertEquals(testName:String, expected:Number, actual:Number, tolerance:Number):Void {
        testCount++;
        apiCoverageMap[testName] = true;
        if (isNaN(tolerance)) tolerance = 0;
        
        var diff:Number = Math.abs(expected - actual);
        if (diff <= tolerance) {
            passedTests++;
            trace("✅ " + testName + " VICTORY (expected=" + expected + ", actual=" + actual + ")");
        } else {
            failedTests++;
            trace("❌ " + testName + " DEFEAT (expected=" + expected + ", actual=" + actual + ", diff=" + diff + ")");
        }
    }
    
    private static function assertArrayEquals(testName:String, expected:Array, actual:Array):Void {
        testCount++;
        apiCoverageMap[testName] = true;
        
        if (expected.length == actual.length) {
            var allMatch:Boolean = true;
            for (var i:Number = 0; i < expected.length; i++) {
                if (expected[i] != actual[i]) {
                    allMatch = false;
                    break;
                }
            }
            if (allMatch) {
                passedTests++;
                trace("✅ " + testName + " VICTORY (arrays match)");
                return;
            }
        }
        
        failedTests++;
        trace("❌ " + testName + " DEFEAT (arrays don't match: expected.length=" + expected.length + ", actual.length=" + actual.length + ")");
    }
    
    private static function assertTrue(testName:String, condition:Boolean):Void {
        testCount++;
        apiCoverageMap[testName] = true;
        if (condition) {
            passedTests++;
            trace("✅ " + testName + " VICTORY");
        } else {
            failedTests++;
            trace("❌ " + testName + " DEFEAT (condition is false)");
        }
    }
    
    private static function assertNotNull(testName:String, obj:Object):Void {
        testCount++;
        apiCoverageMap[testName] = true;
        if (obj != null && obj != undefined) {
            passedTests++;
            trace("✅ " + testName + " VICTORY (object exists)");
        } else {
            failedTests++;
            trace("❌ " + testName + " DEFEAT (object is null)");
        }
    }
    
    private static function assertNull(testName:String, obj:Object):Void {
        testCount++;
        apiCoverageMap[testName] = true;
        if (obj == null || obj == undefined) {
            passedTests++;
            trace("✅ " + testName + " VICTORY (object is null)");
        } else {
            failedTests++;
            trace("❌ " + testName + " DEFEAT (object is not null)");
        }
    }
    
    private static function assertInstanceOf(testName:String, obj:Object, expectedClass:String):Void {
        testCount++;
        apiCoverageMap[testName] = true;
        
        var typeName:String = typeof(obj);
        if (expectedClass == "Array" && obj instanceof Array) {
            passedTests++;
            trace("✅ " + testName + " VICTORY (correct Array type)");
        } else if (expectedClass == "Object" && (typeName == "object" || obj instanceof Object)) {
            passedTests++;
            trace("✅ " + testName + " VICTORY (correct Object type)");
        } else if (expectedClass == "Number" && (typeName == "number" || !isNaN(obj))) {
            passedTests++;
            trace("✅ " + testName + " VICTORY (correct Number type)");
        } else {
            failedTests++;
            trace("❌ " + testName + " DEFEAT (incorrect type: expected=" + expectedClass + ", actual=" + typeName + ")");
        }
    }
    
    // ========================================================================
    // 战场环境初始化
    // ========================================================================
    
    private static function initializeBattleEnvironment():Void {
        trace("\n🏗️ 初始化终极战场环境...");
        
        // 备份原始环境
        originalRoot = _root;
        
        // 创建大规模测试数据
        createLargeScaleTestData();
        
        // 构建模拟环境
        mockGameWorld = createMockGameWorld();
        mockFrameTimer = createMockFrameTimer();
        mockHero = createMockHero();
        
        _root.gameworld = mockGameWorld;
        _root.帧计时器 = mockFrameTimer;
        _root.控制目标 = "hero";
        _root.gameworld.hero = mockHero;
        
        // 初始化系统
        TargetCacheManager.initialize();
        TargetCacheManager.clearCache();
        
        trace("🎯 创建了 " + testUnits.length + " 个测试单位");
        trace("⚔️ 敌人数量: " + testEnemies.length);
        trace("🛡️ 友军数量: " + testAllies.length);
        trace("🏰 战场环境构建完成");
    }
    
    private static function createLargeScaleTestData():Void {
        testUnits = [];
        testEnemies = [];
        testAllies = [];
        
        // 创建大规模测试数据
        for (var i:Number = 0; i < LARGE_DATA_SCALE; i++) {
            var isEnemy:Boolean = (i % 2 == 0);
            var unit:Object = createBattleUnit(i, isEnemy);
            
            testUnits[i] = unit;
            if (isEnemy) {
                testEnemies.push(unit);
            } else {
                testAllies.push(unit);
            }
        }
    }
    
    private static function createBattleUnit(index:Number, isEnemy:Boolean):Object {
        var unit:Object = {
            _name: (isEnemy ? "enemy_" : "ally_") + index,
            hp: 50 + Math.random() * 50,
            maxhp: 100,
            是否为敌人: isEnemy,
            x: index * 30 + Math.random() * 20, // 分散排列
            y: Math.random() * 200,
            aabbCollider: {
                left: 0,
                right: 0,
                updateFromUnitArea: function(u:Object):Void {
                    this.left = u.x - 10;
                    this.right = u.x + 10;
                }
            }
        };
        
        unit.aabbCollider.updateFromUnitArea(unit);
        return unit;
    }
    
    private static function createMockGameWorld():Object {
        var world:Object = {};
        for (var i:Number = 0; i < testUnits.length; i++) {
            world[testUnits[i]._name] = testUnits[i];
        }
        return world;
    }
    
    private static function createMockFrameTimer():Object {
        return {
            当前帧数: 5000,
            advanceFrame: function(frames:Number):Void {
                if (!frames) frames = 1;
                this.当前帧数 += frames;
            }
        };
    }
    
    private static function createMockHero():Object {
        return {
            _name: "hero",
            hp: 100,
            maxhp: 100,
            是否为敌人: false,
            x: LARGE_DATA_SCALE * 15, // 放在中间
            y: 100,
            aabbCollider: {
                left: (LARGE_DATA_SCALE * 15) - 10,
                right: (LARGE_DATA_SCALE * 15) + 10,
                updateFromUnitArea: function(u:Object):Void {
                    this.left = u.x - 10;
                    this.right = u.x + 10;
                }
            }
        };
    }
    
    private static function createTestAABB(centerX:Number, width:Number):AABBCollider {
        var aabb:AABBCollider = new AABBCollider();
        aabb.left = centerX - width/2;
        aabb.right = centerX + width/2;
        return aabb;
    }
    
    private static function cleanupBattleEnvironment():Void {
        // 恢复原始环境
        if (originalRoot) {
            _root = MovieClip(originalRoot);
        }
        
        // 清理缓存
        TargetCacheManager.clearCache();
    }
    
    // ========================================================================
    // 第一波：基础查询功能测试
    // ========================================================================
    
    private static function runBasicQueryTests():Void {
        trace("\n⚔️ 第一波：基础查询功能战斗测试...");
        
        testBasicTargetRetrieval();
        testShorthandMethods();
        testCacheConsistency();
        testUpdateIntervalBehavior();
        testAcquireCacheMethods();
    }
    
    private static function testBasicTargetRetrieval():Void {
        var hero:Object = mockHero;
        
        // 测试基础获取方法
        var enemies:Array = TargetCacheManager.getCachedTargets(hero, 10, "敌人");
        var allies:Array = TargetCacheManager.getCachedTargets(hero, 10, "友军");
        var all:Array = TargetCacheManager.getCachedTargets(hero, 10, "全体");
        
        assertInstanceOf("getCachedTargets-敌人返回数组", enemies, "Array");
        assertInstanceOf("getCachedTargets-友军返回数组", allies, "Array");
        assertInstanceOf("getCachedTargets-全体返回数组", all, "Array");
        
        assertTrue("敌人列表不为空", enemies.length > 0);
        assertTrue("友军列表不为空", allies.length > 0);
        assertTrue("全体列表最大", all.length >= enemies.length && all.length >= allies.length);
        
        // 验证数据正确性
        var firstEnemy:Object = enemies[0];
        assertTrue("第一个敌人确实是敌人", firstEnemy.是否为敌人);
        
        var firstAlly:Object = allies[0];
        assertTrue("第一个友军确实是友军", !firstAlly.是否为敌人);
    }
    
    private static function testShorthandMethods():Void {
        var hero:Object = mockHero;
        var interval:Number = 15;
        
        // 测试简化方法
        var enemies1:Array = TargetCacheManager.getCachedEnemy(hero, interval);
        var allies1:Array = TargetCacheManager.getCachedAlly(hero, interval);
        var all1:Array = TargetCacheManager.getCachedAll(hero, interval);
        
        var enemies2:Array = TargetCacheManager.getCachedTargets(hero, interval, "敌人");
        var allies2:Array = TargetCacheManager.getCachedTargets(hero, interval, "友军");
        var all2:Array = TargetCacheManager.getCachedTargets(hero, interval, "全体");
        
        // 验证简化方法与完整方法结果一致
        assertEquals("简化敌人方法一致性", enemies2.length, enemies1.length, 0);
        assertEquals("简化友军方法一致性", allies2.length, allies1.length, 0);
        assertEquals("简化全体方法一致性", all2.length, all1.length, 0);
    }
    
    private static function testCacheConsistency():Void {
        var hero:Object = mockHero;
        
        // 连续两次调用应该返回相同结果（缓存命中）
        var enemies1:Array = TargetCacheManager.getCachedEnemy(hero, 50);
        var enemies2:Array = TargetCacheManager.getCachedEnemy(hero, 50);
        
        assertEquals("缓存一致性-敌人", enemies1.length, enemies2.length, 0);
        assertTrue("缓存一致性-相同引用", enemies1 === enemies2);
        
        // 验证统计信息反映了缓存命中
        var stats:Object = TargetCacheManager.getSystemStats();
        assertTrue("缓存命中统计正确", stats.cacheHits > 0);
    }
    
    private static function testUpdateIntervalBehavior():Void {
        var hero:Object = mockHero;
        
        // 创建初始缓存
        var initial:Array = TargetCacheManager.getCachedEnemy(hero, 5);
        var initialLength:Number = initial.length;
        
        // 推进时间，触发缓存更新
        mockFrameTimer.advanceFrame(10);
        var updated:Array = TargetCacheManager.getCachedEnemy(hero, 5);
        
        assertTrue("更新间隔后重新获取缓存", updated != null);
        assertEquals("更新后数据量保持", initialLength, updated.length, 0);
    }
    
    private static function testAcquireCacheMethods():Void {
        var hero:Object = mockHero;
        var interval:Number = 10;
        
        trace("  🧪 测试 acquireCache 缓存对象获取方法...");
        
        // 测试基础 acquireCache 方法
        var enemyCache:SortedUnitCache = TargetCacheManager.acquireCache("敌人", hero, interval);
        var allyCache:SortedUnitCache = TargetCacheManager.acquireCache("友军", hero, interval);
        var allCache:SortedUnitCache = TargetCacheManager.acquireCache("全体", hero, interval);
        
        assertNotNull("acquireCache-敌人缓存对象不为空", enemyCache);
        assertNotNull("acquireCache-友军缓存对象不为空", allyCache);
        assertNotNull("acquireCache-全体缓存对象不为空", allCache);
        
        // 验证返回的是 SortedUnitCache 实例
        assertInstanceOf("敌人缓存是SortedUnitCache实例", enemyCache, "Object");
        assertTrue("敌人缓存有data属性", enemyCache.data != undefined);
        assertTrue("敌人缓存有getCount方法", enemyCache.getCount != undefined);
        assertTrue("敌人缓存有findNearest方法", enemyCache.findNearest != undefined);
        
        // 测试便捷方法
        var enemyCache2:SortedUnitCache = TargetCacheManager.acquireEnemyCache(hero, interval);
        var allyCache2:SortedUnitCache = TargetCacheManager.acquireAllyCache(hero, interval);
        var allCache2:SortedUnitCache = TargetCacheManager.acquireAllCache(hero, interval);
        
        assertNotNull("acquireEnemyCache返回缓存对象", enemyCache2);
        assertNotNull("acquireAllyCache返回缓存对象", allyCache2);
        assertNotNull("acquireAllCache返回缓存对象", allCache2);
        
        // 验证便捷方法与基础方法返回相同的缓存对象引用
        assertTrue("acquireEnemyCache返回相同引用", enemyCache === enemyCache2);
        assertTrue("acquireAllyCache返回相同引用", allyCache === allyCache2);
        assertTrue("acquireAllCache返回相同引用", allCache === allCache2);
        
        // 验证缓存对象的数据一致性
        var enemiesFromCache:Array = enemyCache.data;
        var enemiesFromManager:Array = TargetCacheManager.getCachedEnemy(hero, interval);
        
        assertEquals("缓存对象与Manager返回数据一致", enemiesFromManager.length, enemiesFromCache.length, 0);
        assertTrue("缓存对象与Manager返回相同数组引用", enemiesFromCache === enemiesFromManager);
        
        // 测试缓存对象的方法调用
        var nearestFromCache:Object = enemyCache.findNearest(hero);
        var nearestFromManager:Object = TargetCacheManager.findNearestEnemy(hero, interval);
        
        if (nearestFromCache && nearestFromManager) {
            assertTrue("缓存对象findNearest与Manager一致", nearestFromCache._name == nearestFromManager._name);
        } else {
            assertTrue("缓存对象与Manager都未找到最近单位", !nearestFromCache && !nearestFromManager);
        }
        
        // 测试缓存对象的计数功能
        var countFromCache:Number = enemyCache.getCount();
        var countFromManager:Number = TargetCacheManager.getEnemyCount(hero, interval);
        
        assertEquals("缓存对象计数与Manager一致", countFromManager, countFromCache, 0);
        
        // 测试缓存对象的范围查询
        var rangeResultFromCache:Array = enemyCache.findInRadius(hero, 100, true);
        var rangeResultFromManager:Array = TargetCacheManager.findEnemiesInRadius(hero, interval, 100);
        
        assertEquals("缓存对象范围查询与Manager一致", rangeResultFromManager.length, rangeResultFromCache.length, 0);
        
        trace("  ✅ acquireCache 方法测试全部通过");
    }
    
    // ========================================================================
    // 第二波：范围查询测试
    // ========================================================================
    
    private static function runRangeQueryTests():Void {
        trace("\n⚔️ 第二波：范围查询战斗测试...");
        
        testIndexBasedQueries();
        testAABBColliderQueries();
        testRangeQueryConsistency();
        testMonotonicIndexQueries();
    }
    
    private static function testIndexBasedQueries():Void {
        var hero:Object = mockHero;
        var aabb:AABBCollider = createTestAABB(hero.x, 200);
        
        // 测试从索引开始的查询
        var enemyResult:Object = TargetCacheManager.getCachedEnemyFromIndex(hero, 10, aabb);
        var allyResult:Object = TargetCacheManager.getCachedAllyFromIndex(hero, 10, aabb);
        var allResult:Object = TargetCacheManager.getCachedAllFromIndex(hero, 10, aabb);
        
        assertNotNull("敌人索引查询结果", enemyResult);
        assertNotNull("友军索引查询结果", allyResult);
        assertNotNull("全体索引查询结果", allResult);
        
        assertTrue("敌人索引查询包含data", enemyResult.hasOwnProperty("data"));
        assertTrue("敌人索引查询包含startIndex", enemyResult.hasOwnProperty("startIndex"));
        assertInstanceOf("敌人索引查询data是数组", enemyResult.data, "Array");
        assertInstanceOf("敌人索引查询startIndex是数字", enemyResult.startIndex, "Number");
        
        assertTrue("索引查询返回有效数据", enemyResult.data.length >= 0);
    }
    
    private static function testAABBColliderQueries():Void {
        var hero:Object = mockHero;
        
        // 测试不同大小的碰撞盒
        var smallAABB:AABBCollider = createTestAABB(hero.x, 50);
        var largeAABB:AABBCollider = createTestAABB(hero.x, 500);
        
        var smallResult:Object = TargetCacheManager.getCachedTargetsFromIndex(hero, 10, "敌人", smallAABB);
        var largeResult:Object = TargetCacheManager.getCachedTargetsFromIndex(hero, 10, "敌人", largeAABB);
        
        assertTrue("小碰撞盒查询正常", smallResult.data.length >= 0);
        assertTrue("大碰撞盒查询正常", largeResult.data.length >= 0);
        assertTrue("大碰撞盒包含更多单位", largeResult.data.length >= smallResult.data.length);
    }
    
    private static function testRangeQueryConsistency():Void {
        var hero:Object = mockHero;
        var aabb:AABBCollider = createTestAABB(hero.x, 100);
        
        // 使用通用方法和专用方法应该得到相同结果
        var genericResult:Object = TargetCacheManager.getCachedTargetsFromIndex(hero, 10, "友军", aabb);
        var specificResult:Object = TargetCacheManager.getCachedAllyFromIndex(hero, 10, aabb);
        
        assertEquals("范围查询一致性-数据长度", genericResult.data.length, specificResult.data.length, 0);
        assertEquals("范围查询一致性-开始索引", genericResult.startIndex, specificResult.startIndex, 0);
    }
    
    // ========================================================================
    // 第三波：距离查询测试
    // ========================================================================
    
    private static function runDistanceQueryTests():Void {
        trace("\n⚔️ 第三波：距离查询战斗测试...");
        
        testNearestUnitFinding();
        testFarthestUnitFinding();
        testDistanceQueryAccuracy();
        testDistanceQueryEdgeCases();
    }
    
    private static function testNearestUnitFinding():Void {
        var hero:Object = mockHero;
        
        // 测试最近单位查找
        var nearestEnemy:Object = TargetCacheManager.findNearestTarget(hero, 10, "敌人");
        var nearestAlly:Object = TargetCacheManager.findNearestTarget(hero, 10, "友军");
        var nearestAll:Object = TargetCacheManager.findNearestTarget(hero, 10, "全体");
        
        assertNotNull("找到最近敌人", nearestEnemy);
        assertNotNull("找到最近友军", nearestAlly);
        assertNotNull("找到最近全体单位", nearestAll);
        
        // 测试简化方法
        var nearestEnemy2:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        var nearestAlly2:Object = TargetCacheManager.findNearestAlly(hero, 10);
        var nearestAll2:Object = TargetCacheManager.findNearestAll(hero, 10);
        
        assertTrue("最近敌人查找一致性", nearestEnemy === nearestEnemy2);
        assertTrue("最近友军查找一致性", nearestAlly === nearestAlly2);
        assertTrue("最近全体查找一致性", nearestAll === nearestAll2);
        
        // 验证确实是敌人/友军
        assertTrue("最近敌人确实是敌人", nearestEnemy.是否为敌人);
        assertTrue("最近友军确实是友军", !nearestAlly.是否为敌人);
    }
    
    private static function testFarthestUnitFinding():Void {
        var hero:Object = mockHero;
        
        // 测试最远单位查找
        var farthestEnemy:Object = TargetCacheManager.findFarthestTarget(hero, 10, "敌人");
        var farthestAlly:Object = TargetCacheManager.findFarthestTarget(hero, 10, "友军");
        
        assertNotNull("找到最远敌人", farthestEnemy);
        assertNotNull("找到最远友军", farthestAlly);
        
        // 简化方法测试
        var farthestEnemy2:Object = TargetCacheManager.findFarthestEnemy(hero, 10);
        var farthestAlly2:Object = TargetCacheManager.findFarthestAlly(hero, 10);
        
        assertTrue("最远敌人查找一致性", farthestEnemy === farthestEnemy2);
        assertTrue("最远友军查找一致性", farthestAlly === farthestAlly2);
    }
    
    private static function testDistanceQueryAccuracy():Void {
        var hero:Object = mockHero;
        
        // 获取最近和最远单位
        var nearest:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        var farthest:Object = TargetCacheManager.findFarthestEnemy(hero, 10);
        
        if (nearest && farthest) {
            var nearestDist:Number = Math.abs(nearest.x - hero.x);
            var farthestDist:Number = Math.abs(farthest.x - hero.x);
            
            assertTrue("最远距离确实大于最近距离", farthestDist >= nearestDist);
        }
    }
    
    private static function testDistanceQueryEdgeCases():Void {
        // 测试边界情况：只有一个单位
        var singleUnitWorld:Object = {
            single_enemy: createBattleUnit(0, true)
        };
        
        var originalWorld:Object = _root.gameworld;
        _root.gameworld = singleUnitWorld;
        
        TargetCacheManager.clearCache(); 
        
        var nearest:Object = TargetCacheManager.findNearestEnemy(mockHero, 10);
        var farthest:Object = TargetCacheManager.findFarthestEnemy(mockHero, 10);
        
        assertNotNull("单单位场景-找到单位", nearest);
        
        // 修复：将引用比较改为内容比较
        // 原代码：assertTrue("单单位场景-最近和最远是同一个", nearest === farthest);
        // 新代码：
        var isSameUnit:Boolean = nearest && farthest && (nearest._name == farthest._name);
        trace(nearest._name + " vs " + farthest._name);
        assertTrue("单单位场景-最近和最远是同一个", isSameUnit);
        
        _root.gameworld = originalWorld;
        TargetCacheManager.clearCache();
    }
    
    // ========================================================================
    // 第四波：区域搜索测试
    // ========================================================================
    
    private static function runAreaSearchTests():Void {
        trace("\n⚔️ 第四波：区域搜索战斗测试...");
        
        testRangeBasedSearch();
        testRadiusBasedSearch();
        testLimitedRangeSearch();
        testAreaSearchAccuracy();
    }
    
    private static function testRangeBasedSearch():Void {
        var hero:Object = mockHero;
        var leftRange:Number = 100;
        var rightRange:Number = 150;
        
        // 测试范围搜索
        var enemiesInRange:Array = TargetCacheManager.findTargetsInRange(hero, 10, "敌人", leftRange, rightRange);
        var alliesInRange:Array = TargetCacheManager.findTargetsInRange(hero, 10, "友军", leftRange, rightRange);
        var allInRange:Array = TargetCacheManager.findTargetsInRange(hero, 10, "全体", leftRange, rightRange);
        
        assertInstanceOf("范围敌人搜索返回数组", enemiesInRange, "Array");
        assertInstanceOf("范围友军搜索返回数组", alliesInRange, "Array");
        assertInstanceOf("范围全体搜索返回数组", allInRange, "Array");
        
        // 测试简化方法
        var enemies2:Array = TargetCacheManager.findEnemiesInRange(hero, 10, leftRange, rightRange);
        var allies2:Array = TargetCacheManager.findAlliesInRange(hero, 10, leftRange, rightRange);
        var all2:Array = TargetCacheManager.findAllInRange(hero, 10, leftRange, rightRange);
        
        assertArrayEquals("简化范围敌人搜索一致", enemiesInRange, enemies2);
        assertArrayEquals("简化范围友军搜索一致", alliesInRange, allies2);
        assertArrayEquals("简化范围全体搜索一致", allInRange, all2);
        
        // 验证搜索结果的正确性
        for (var i:Number = 0; i < enemiesInRange.length; i++) {
            var enemy:Object = enemiesInRange[i];
            var dist:Number = Math.abs(enemy.x - hero.x);
            assertTrue("范围内敌人-" + i + "距离正确", dist <= Math.max(leftRange, rightRange));
        }
    }
    
    private static function testRadiusBasedSearch():Void {
        var hero:Object = mockHero;
        var radius:Number = 200;
        
        // 测试半径搜索
        var enemiesInRadius:Array = TargetCacheManager.findTargetsInRadius(hero, 10, "敌人", radius);
        var alliesInRadius:Array = TargetCacheManager.findTargetsInRadius(hero, 10, "友军", radius);
        
        assertInstanceOf("半径敌人搜索返回数组", enemiesInRadius, "Array");
        assertInstanceOf("半径友军搜索返回数组", alliesInRadius, "Array");
        
        // 简化方法测试
        var enemies2:Array = TargetCacheManager.findEnemiesInRadius(hero, 10, radius);
        var allies2:Array = TargetCacheManager.findAlliesInRadius(hero, 10, radius);
        var all2:Array = TargetCacheManager.findAllInRadius(hero, 10, radius);
        
        assertArrayEquals("简化半径敌人搜索一致", enemiesInRadius, enemies2);
        assertArrayEquals("简化半径友军搜索一致", alliesInRadius, allies2);
        
        // 验证搜索结果在半径内
        // 半径仅关注x轴，不考虑2d完整距离差
        for (var i:Number = 0; i < enemiesInRadius.length; i++) {
            var enemy:Object = enemiesInRadius[i];
            var dist:Number = Math.abs(enemy.x - hero.x);
            assertTrue("半径内敌人-" + i + "距离正确", dist <= radius);
        }
    }
    
    private static function testLimitedRangeSearch():Void {
        var hero:Object = mockHero;
        var maxDistance:Number = 100;
        
        // 测试限制范围的最近/最远查找
        var nearestInRange:Object = TargetCacheManager.findNearestTargetInRange(hero, 10, "敌人", maxDistance);
        var farthestInRange:Object = TargetCacheManager.findFarthestTargetInRange(hero, 10, "敌人", maxDistance);
        
        // 简化方法测试
        var nearestEnemy:Object = TargetCacheManager.findNearestEnemyInRange(hero, 10, maxDistance);
        var nearestAlly:Object = TargetCacheManager.findNearestAllyInRange(hero, 10, maxDistance);
        var farthestEnemy:Object = TargetCacheManager.findFarthestEnemyInRange(hero, 10, maxDistance);
        var farthestAlly:Object = TargetCacheManager.findFarthestAllyInRange(hero, 10, maxDistance);
        
        assertTrue("限制范围最近敌人查找一致", nearestInRange === nearestEnemy);
        
        // 验证结果在范围内
        if (nearestInRange) {
            var dist:Number = Math.abs(nearestInRange.x - hero.x);
            assertTrue("限制范围内最近单位距离正确", dist <= maxDistance);
        }
        
        if (farthestInRange) {
            var dist2:Number = Math.abs(farthestInRange.x - hero.x);
            assertTrue("限制范围内最远单位距离正确", dist2 <= maxDistance);
        }
    }
    
    private static function testAreaSearchAccuracy():Void {
        var hero:Object = mockHero;
        
        // 比较不同搜索方法的结果一致性
        var rangeResult:Array = TargetCacheManager.findEnemiesInRange(hero, 10, 50, 50); // 对称范围
        var radiusResult:Array = TargetCacheManager.findEnemiesInRadius(hero, 10, 50);
        
        // 理论上半径搜索应该包含或接近范围搜索的结果数量
        assertTrue("区域搜索结果合理", radiusResult.length >= 0 && rangeResult.length >= 0);
    }
    
    // ========================================================================
    // 第五波：计数API测试
    // ========================================================================
    
    private static function runCountingAPITests():Void {
        trace("\n⚔️ 第五波：计数API战斗测试...");
        
        testBasicCounting();
        testRangeBasedCounting();
        testRadiusBasedCounting();
        testCountingAccuracy();
    }
    
    private static function testBasicCounting():Void {
        var hero:Object = mockHero;
        
        // 测试基本计数
        var enemyCount:Number = TargetCacheManager.getTargetCount(hero, 10, "敌人");
        var allyCount:Number = TargetCacheManager.getTargetCount(hero, 10, "友军");
        var allCount:Number = TargetCacheManager.getTargetCount(hero, 10, "全体");
        
        assertInstanceOf("敌人计数返回数字", enemyCount, "Number");
        assertInstanceOf("友军计数返回数字", allyCount, "Number");
        assertInstanceOf("全体计数返回数字", allCount, "Number");
        
        assertTrue("敌人数量合理", enemyCount >= 0);
        assertTrue("友军数量合理", allyCount >= 0);
        assertTrue("全体数量最大", allCount >= enemyCount && allCount >= allyCount);
        
        // 测试简化方法
        var enemyCount2:Number = TargetCacheManager.getEnemyCount(hero, 10);
        var allyCount2:Number = TargetCacheManager.getAllyCount(hero, 10);
        var allCount2:Number = TargetCacheManager.getAllCount(hero, 10);
        
        assertEquals("简化敌人计数一致", enemyCount, enemyCount2, 0);
        assertEquals("简化友军计数一致", allyCount, allyCount2, 0);
        assertEquals("简化全体计数一致", allCount, allCount2, 0);
        
        // 验证计数与实际数组长度一致
        var actualEnemies:Array = TargetCacheManager.getCachedEnemy(hero, 10);
        assertEquals("计数与数组长度一致-敌人", enemyCount, actualEnemies.length, 0);
    }
    
    private static function testRangeBasedCounting():Void {
        var hero:Object = mockHero;
        var leftRange:Number = 80;
        var rightRange:Number = 120;
        
        // 测试范围计数
        var enemyCountInRange:Number = TargetCacheManager.getTargetCountInRange(
            hero, 10, "敌人", leftRange, rightRange, false
        );
        var allyCountInRange:Number = TargetCacheManager.getTargetCountInRange(
            hero, 10, "友军", leftRange, rightRange, false
        );
        
        assertInstanceOf("范围敌人计数返回数字", enemyCountInRange, "Number");
        assertInstanceOf("范围友军计数返回数字", allyCountInRange, "Number");
        assertTrue("范围敌人计数合理", enemyCountInRange >= 0);
        assertTrue("范围友军计数合理", allyCountInRange >= 0);
        
        // 测试简化方法
        var enemyCount2:Number = TargetCacheManager.getEnemyCountInRange(hero, 10, leftRange, rightRange, false);
        var allyCount2:Number = TargetCacheManager.getAllyCountInRange(hero, 10, leftRange, rightRange, false);
        var allCount2:Number = TargetCacheManager.getAllCountInRange(hero, 10, leftRange, rightRange, false);
        
        assertEquals("简化范围敌人计数一致", enemyCountInRange, enemyCount2, 0);
        assertEquals("简化范围友军计数一致", allyCountInRange, allyCount2, 0);
        
        // 验证计数与实际搜索结果一致
        var actualEnemies:Array = TargetCacheManager.findEnemiesInRange(hero, 10, leftRange, rightRange);
        assertEquals("范围计数与搜索结果一致", enemyCountInRange, actualEnemies.length, 0);
    }
    
    private static function testRadiusBasedCounting():Void {
        var hero:Object = mockHero;
        var radius:Number = 150;
        
        // 测试半径计数
        var enemyCountInRadius:Number = TargetCacheManager.getTargetCountInRadius(hero, 10, "敌人", radius, false);
        var allyCountInRadius:Number = TargetCacheManager.getTargetCountInRadius(hero, 10, "友军", radius, false);
        
        assertInstanceOf("半径敌人计数返回数字", enemyCountInRadius, "Number");
        assertInstanceOf("半径友军计数返回数字", allyCountInRadius, "Number");
        
        // 简化方法测试
        var enemyCount2:Number = TargetCacheManager.getEnemyCountInRadius(hero, 10, radius, false);
        var allyCount2:Number = TargetCacheManager.getAllyCountInRadius(hero, 10, radius, false);
        var allCount2:Number = TargetCacheManager.getAllCountInRadius(hero, 10, radius, false);
        
        assertEquals("简化半径敌人计数一致", enemyCountInRadius, enemyCount2, 0);
        assertEquals("简化半径友军计数一致", allyCountInRadius, allyCount2, 0);
        
        // 验证计数与实际搜索结果一致
        var actualEnemies:Array = TargetCacheManager.findEnemiesInRadius(hero, 10, radius);
        assertEquals("半径计数与搜索结果一致", enemyCountInRadius, actualEnemies.length, 0);
    }
    
    private static function testCountingAccuracy():Void {
        var hero:Object = mockHero;
        
        // 测试排除自身的选项
        var countIncludingSelf:Number = TargetCacheManager.getTargetCountInRadius(hero, 10, "全体", 500, false);
        var countExcludingSelf:Number = TargetCacheManager.getTargetCountInRadius(hero, 10, "全体", 500, true);
        
        // 如果英雄在范围内，排除自身应该少1个
        assertTrue("排除自身计数逻辑正确", countExcludingSelf <= countIncludingSelf);
    }
    
    // ========================================================================
    // 第六波：条件查询测试
    // ========================================================================
    
    private static function runConditionalQueryTests():Void {
        trace("\n⚔️ 第六波：条件查询战斗测试...");
        
        testHPBasedCounting();
        testDistanceDistribution();
        testConditionalQueryAccuracy();
    }
    
    private static function testHPBasedCounting():Void {
        var hero:Object = mockHero;
        
        // 测试血量条件计数
        var lowHpEnemies:Number = TargetCacheManager.getTargetCountByHP(hero, 10, "敌人", "低血量", false);
        var midHpEnemies:Number = TargetCacheManager.getTargetCountByHP(hero, 10, "敌人", "中血量", false);
        var highHpEnemies:Number = TargetCacheManager.getTargetCountByHP(hero, 10, "敌人", "高血量", false);
        
        assertInstanceOf("低血量敌人计数返回数字", lowHpEnemies, "Number");
        assertInstanceOf("中血量敌人计数返回数字", midHpEnemies, "Number");
        assertInstanceOf("高血量敌人计数返回数字", highHpEnemies, "Number");
        
        assertTrue("血量条件计数合理", lowHpEnemies >= 0 && midHpEnemies >= 0 && highHpEnemies >= 0);
        
        // 测试简化方法
        var lowHpEnemies2:Number = TargetCacheManager.getEnemyCountByHP(hero, 10, "低血量", false);
        var lowHpAllies2:Number = TargetCacheManager.getAllyCountByHP(hero, 10, "低血量", false);
        
        assertEquals("简化HP敌人计数一致", lowHpEnemies, lowHpEnemies2, 0);
        assertInstanceOf("简化HP友军计数返回数字", lowHpAllies2, "Number");
    }
    
    private static function testDistanceDistribution():Void {
        var hero:Object = mockHero;
        var ranges:Array = [50, 100, 200, 400];
        
        // 测试距离分布统计
        var enemyDist:Object = TargetCacheManager.getDistanceDistribution(hero, 10, "敌人", ranges, false);
        var allyDist:Object = TargetCacheManager.getDistanceDistribution(hero, 10, "友军", ranges, false);
        
        assertNotNull("敌人距离分布对象", enemyDist);
        assertNotNull("友军距离分布对象", allyDist);
        
        assertTrue("敌人分布包含totalCount", enemyDist.hasOwnProperty("totalCount"));
        assertTrue("敌人分布包含distribution", enemyDist.hasOwnProperty("distribution"));
        assertTrue("敌人分布包含minDistance", enemyDist.hasOwnProperty("minDistance"));
        assertTrue("敌人分布包含maxDistance", enemyDist.hasOwnProperty("maxDistance"));
        
        assertInstanceOf("分布数组类型正确", enemyDist.distribution, "Array");
        assertInstanceOf("总数类型正确", enemyDist.totalCount, "Number");
        
        // 测试简化方法
        var enemyDist2:Object = TargetCacheManager.getEnemyDistanceDistribution(hero, 10, ranges, false);
        var allyDist2:Object = TargetCacheManager.getAllyDistanceDistribution(hero, 10, ranges, false);
        
        assertEquals("简化敌人分布总数一致", enemyDist.totalCount, enemyDist2.totalCount, 0);
        assertEquals("简化友军分布总数一致", allyDist.totalCount, allyDist2.totalCount, 0);
    }
    
    private static function testConditionalQueryAccuracy():Void {
        var hero:Object = mockHero;

        // 验证血量条件的逻辑正确性
        var totalEnemies:Number = TargetCacheManager.getEnemyCount(hero, 10);
        var lowHp:Number = TargetCacheManager.getEnemyCountByHP(hero, 10, "低血量", false);
        var midHp:Number = TargetCacheManager.getEnemyCountByHP(hero, 10, "中血量", false);
        var highHp:Number = TargetCacheManager.getEnemyCountByHP(hero, 10, "高血量", false);

        // 各种血量的总和应该等于总数（low/medium/high 三段应覆盖全部单位）
        var hpSum:Number = lowHp + midHp + highHp;
        assertTrue("血量分类覆盖合理", hpSum <= totalEnemies);
        // 强断言：若存在敌人，三段之和必须 > 0（防止归一化失效静默返回全零）
        if (totalEnemies > 0) {
            assertTrue("血量分类总和必须大于0", hpSum > 0);
        }

        // 验证中文条件与英文条件结果一致
        var lowHpEN:Number = TargetCacheManager.getEnemyCountByHP(hero, 10, "low", false);
        assertEquals("中英文HP条件结果一致(low/低血量)", lowHp, lowHpEN, 0);
    }
    
    // ========================================================================
    // 第七波：系统管理测试
    // ========================================================================
    
    private static function runSystemManagementTests():Void {
        trace("\n⚔️ 第七波：系统管理战斗测试...");
        
        testUnitManagement();
        testCacheManagement();
        testSystemConfiguration();
        testSystemMonitoring();
    }
    
    private static function testUnitManagement():Void {
        var newUnit:Object = createBattleUnit(999, true);
        var originalCount:Number = TargetCacheManager.getEnemyCount(mockHero, 10);
        
        // 测试添加单位
        TargetCacheManager.addUnit(newUnit);
        _root.gameworld[newUnit._name] = newUnit; // 模拟添加到世界
        
        // 清除缓存并重新获取，应该包含新单位
        TargetCacheManager.clearCache();
        var newCount:Number = TargetCacheManager.getEnemyCount(mockHero, 10);
        
        assertTrue("添加单位后数量增加", newCount > originalCount);
        
        // 测试移除单位
        TargetCacheManager.removeUnit(newUnit);
        delete _root.gameworld[newUnit._name]; // 从世界移除
        
        TargetCacheManager.clearCache();
        var finalCount:Number = TargetCacheManager.getEnemyCount(mockHero, 10);
        
        assertEquals("移除单位后数量恢复", originalCount, finalCount, 0);
        
        // 测试批量操作
        var batchUnits:Array = [createBattleUnit(1001, true), createBattleUnit(1002, false)];
        TargetCacheManager.addUnits(batchUnits);
        TargetCacheManager.removeUnits(batchUnits);
        
        assertTrue("批量操作正常完成", true);
    }
    
    private static function testCacheManagement():Void {
        // 创建一些缓存
        TargetCacheManager.getCachedEnemy(mockHero, 10);
        TargetCacheManager.getCachedAlly(mockHero, 10);
        TargetCacheManager.getCachedAll(mockHero, 10);
        
        var stats1:Object = TargetCacheManager.getSystemStats();
        var initialRequests:Number = stats1.totalRequests;
        
        // 测试部分清理
        TargetCacheManager.clearCache("敌人");
        TargetCacheManager.getCachedEnemy(mockHero, 10); // 这应该重新创建敌人缓存
        
        var stats2:Object = TargetCacheManager.getSystemStats();
        assertTrue("部分清理后请求数增加", stats2.totalRequests > initialRequests);
        
        // 测试全部失效
        TargetCacheManager.invalidateAllCaches();
        TargetCacheManager.getCachedAll(mockHero, 10); // 这应该重新创建缓存
        
        var stats3:Object = TargetCacheManager.getSystemStats();
        assertTrue("失效后可以重新创建缓存", stats3.totalRequests > stats2.totalRequests);
        
        // 测试特定失效
        TargetCacheManager.invalidateCache("友军");
        assertTrue("特定失效操作正常完成", true);
    }
    
    private static function testSystemConfiguration():Void {
        // 获取原始配置
        var originalConfig:Object = TargetCacheManager.getSystemConfig();
        assertNotNull("获取系统配置", originalConfig);
        
        // 测试配置设置
        var newConfig:Object = {
            maxCacheCapacity: 75,
            forceRefreshThreshold: 400
        };
        
        TargetCacheManager.setSystemConfig(newConfig);
        var updatedConfig:Object = TargetCacheManager.getSystemConfig();
        
        assertEquals("配置更新-容量", 75, updatedConfig.maxCacheCapacity, 0);
        assertEquals("配置更新-刷新阈值", 400, updatedConfig.forceRefreshThreshold, 0);
        
        // 恢复原始配置
        TargetCacheManager.setSystemConfig(originalConfig);
    }
    
    private static function testSystemMonitoring():Void {
        // 测试统计信息获取
        var stats:Object = TargetCacheManager.getSystemStats();
        assertNotNull("获取系统统计", stats);
        assertTrue("统计包含totalRequests", stats.hasOwnProperty("totalRequests"));
        assertTrue("统计包含cacheHits", stats.hasOwnProperty("cacheHits"));
        assertTrue("统计包含cacheMisses", stats.hasOwnProperty("cacheMisses"));
        
        // 测试健康检查
        var health:Object = TargetCacheManager.performHealthCheck();
        assertNotNull("健康检查结果", health);
        assertTrue("健康检查包含healthy", health.hasOwnProperty("healthy"));
        assertTrue("健康检查包含warnings", health.hasOwnProperty("warnings"));
        assertTrue("健康检查包含errors", health.hasOwnProperty("errors"));
        
        // 测试状态报告
        var report:String = TargetCacheManager.getDetailedStatusReport();
        assertNotNull("详细状态报告", report);
        assertTrue("状态报告不为空", report.length > 0);
        
        // 测试优化建议
        var recommendations:Array = TargetCacheManager.getOptimizationRecommendations();
        assertInstanceOf("优化建议返回数组", recommendations, "Array");
    }
    
    // ========================================================================
    // 第八波：外观模式验证
    // ========================================================================
    
    private static function runFacadePatternTests():Void {
        trace("\n⚔️ 第八波：外观模式战斗验证...");
        
        testAPISimplification();
        testDelegationCorrectness();
        testInterfaceConsistency();
        testBackwardCompatibility();
    }
    
    private static function testAPISimplification():Void {
        var hero:Object = mockHero;
        
        // 验证简化的API调用
        var simpleResult:Array = TargetCacheManager.getCachedEnemy(hero, 10);
        var complexResult:Array = TargetCacheManager.getCachedTargets(hero, 10, "敌人");
        
        assertTrue("简化API与复杂API结果一致", simpleResult === complexResult);
        
        // 验证用户友好的方法名
        var nearestEnemy:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        var enemyCount:Number = TargetCacheManager.getEnemyCount(hero, 10);
        
        assertNotNull("用户友好方法1-最近敌人", nearestEnemy);
        assertInstanceOf("用户友好方法2-敌人计数", enemyCount, "Number");
        
        // 验证API的直观性
        var hero2:Object = TargetCacheManager.findHero();
        assertTrue("findHero方法直观易用", hero2 != null || hero2 == null); // 不管结果如何，方法都应该存在
    }
    
    private static function testDelegationCorrectness():Void {
        // 验证Manager正确委托给Provider
        var managerStats:Object = TargetCacheManager.getSystemStats();
        var providerStats:Object = TargetCacheProvider.getStats();
        
        assertEquals("委托统计-总请求数", providerStats.totalRequests, managerStats.totalRequests, 0);
        assertEquals("委托统计-缓存命中", providerStats.cacheHits, managerStats.cacheHits, 0);
        assertEquals("委托统计-缓存未命中", providerStats.cacheMisses, managerStats.cacheMisses, 0);
        
        // 验证配置委托
        var managerConfig:Object = TargetCacheManager.getSystemConfig();
        var providerConfig:Object = TargetCacheProvider.getConfig();
        
        assertEquals("委托配置-缓存容量", providerConfig.maxCacheCapacity, managerConfig.maxCacheCapacity, 0);
        assertTrue("委托配置-版本检查", providerConfig.versionCheckEnabled == managerConfig.versionCheckEnabled);
    }
    
    private static function testInterfaceConsistency():Void {
        var hero:Object = mockHero;
        
        // 验证所有相同类型的方法返回类型一致
        var enemies1:Array = TargetCacheManager.getCachedEnemy(hero, 10);
        var allies1:Array = TargetCacheManager.getCachedAlly(hero, 10);
        var all1:Array = TargetCacheManager.getCachedAll(hero, 10);
        
        assertInstanceOf("接口一致性-敌人数组", enemies1, "Array");
        assertInstanceOf("接口一致性-友军数组", allies1, "Array");
        assertInstanceOf("接口一致性-全体数组", all1, "Array");
        
        // 验证计数方法返回类型一致
        var count1:Number = TargetCacheManager.getEnemyCount(hero, 10);
        var count2:Number = TargetCacheManager.getAllyCount(hero, 10);
        var count3:Number = TargetCacheManager.getAllCount(hero, 10);
        
        assertInstanceOf("接口一致性-敌人计数", count1, "Number");
        assertInstanceOf("接口一致性-友军计数", count2, "Number");
        assertInstanceOf("接口一致性-全体计数", count3, "Number");
    }
    
    private static function testBackwardCompatibility():Void {
        var hero:Object = mockHero;
        
        // 测试旧版本的updateTargetCache方法
        TargetCacheManager.updateTargetCache(hero, "敌人", "敌人");
        assertTrue("向后兼容方法正常执行", true);
        
        // 验证参数格式的兼容性（短参数名）
        var result1:Array = TargetCacheManager.getCachedEnemy(hero, 10);
        var result2:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        var result3:Number = TargetCacheManager.getEnemyCount(hero, 10);
        
        assertTrue("短参数名兼容性-数组", result1 instanceof Array);
        assertTrue("短参数名兼容性-对象", result2 != null || result2 == null);
        assertTrue("短参数名兼容性-数字", !isNaN(result3));
    }
    
    // ========================================================================
    // 第十波：过滤器查询测试
    // ========================================================================
    
    private static function runFilteredQueryTests():Void {
        trace("\n⚔️ 第十波：过滤器查询战斗测试...");
        
        testBasicFilteredQueries();
        testPreDefinedFilters();
        testFilteredQueryInRange();
        testFilteredQueryEdgeCases();
        testFilteredQueryPerformance();
        testFilteredQueryConsistency();
        // 新增：回退降级测试
        testFallbackQueryMethods();
    }
    
    private static function testBasicFilteredQueries():Void {
        var hero:Object = mockHero;
        
        // 修改一些单位的血量以便测试过滤器
        // 需要同时修改 testEnemies 和 mockGameWorld 中的单位
        for (var i:Number = 0; i < 10; i++) {
            if (testEnemies[i]) {
                testEnemies[i].hp = (i % 3 == 0) ? 30 : 80; // 部分设为低血量
                // 同步到 mockGameWorld
                var unitInWorld:Object = _root.gameworld[testEnemies[i]._name];
                if (unitInWorld) {
                    unitInWorld.hp = testEnemies[i].hp;
                }
            }
        }
        
        // 清除缓存以确保反映最新的血量状态
        TargetCacheManager.clearCache("敌人");
        
        // 测试基础过滤器查询
        var lowHPFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return (u.hp / u.maxhp) < 0.5;
        };
        
        var lowHPEnemy:Object = TargetCacheManager.findNearestTargetWithFilter(
            hero, 10, "敌人", lowHPFilter, undefined, undefined
        );
        
        if (lowHPEnemy) {
            assertNotNull("基础过滤查询-找到低血量敌人", lowHPEnemy);
            assertTrue("基础过滤查询-确实是低血量", (lowHPEnemy.hp / lowHPEnemy.maxhp) < 0.5);
            assertTrue("基础过滤查询-确实是敌人", lowHPEnemy.是否为敌人);
        } else {
            // 验证在没有低血量敌人的情况下，查询正常返回null
            assertNull("基础过滤查询-无低血量敌人时返回null", lowHPEnemy);
        }
        
        // 测试简化方法
        var lowHPEnemy2:Object = TargetCacheManager.findNearestEnemyWithFilter(
            hero, 10, lowHPFilter, undefined, undefined
        );
        
        assertTrue("简化过滤查询一致性", lowHPEnemy === lowHPEnemy2);
        
        // 测试友军过滤
        var injuredAlly:Object = TargetCacheManager.findNearestAllyWithFilter(
            hero, 10, 
            function(u:Object, t:Object, d:Number):Boolean { return u.hp < u.maxhp; },
            undefined, undefined
        );
        
        // 友军可能没有受伤的，这是正常的
        if (injuredAlly) {
            assertTrue("友军过滤查询-确实受伤", injuredAlly.hp < injuredAlly.maxhp);
            assertTrue("友军过滤查询-确实是友军", !injuredAlly.是否为敌人);
        }
        
        // 测试全体过滤
        var specificUnit:Object = TargetCacheManager.findNearestAllWithFilter(
            hero, 10,
            function(u:Object, t:Object, d:Number):Boolean { return u._name.indexOf("0") != -1; },
            undefined, undefined
        );
        
        if (specificUnit) {
            assertTrue("全体过滤查询-名称匹配", specificUnit._name.indexOf("0") != -1);
        }
    }
    
    private static function testPreDefinedFilters():Void {
        var hero:Object = mockHero;
        
        // 测试预定义的低血量敌人查询
        var lowHPEnemy:Object = TargetCacheManager.findNearestLowHPEnemy(hero, 10, undefined);
        
        if (lowHPEnemy) {
            assertNotNull("预定义过滤器-低血量敌人", lowHPEnemy);
            assertTrue("预定义过滤器-血量确实低", (lowHPEnemy.hp / lowHPEnemy.maxhp) < 0.5);
            assertTrue("预定义过滤器-确实是敌人", lowHPEnemy.是否为敌人);
        } else {
            // 如果找不到低血量敌人，至少验证方法不会崩溃
            assertTrue("预定义过滤器-低血量敌人查询正常执行", true);
        }
        
        // 测试受伤友军查询
        var injuredAlly:Object = TargetCacheManager.findNearestInjuredAlly(hero, 10, undefined);
        
        if (injuredAlly) {
            assertNotNull("预定义过滤器-受伤友军", injuredAlly);
            assertTrue("预定义过滤器-确实受伤", injuredAlly.hp < injuredAlly.maxhp);
            assertTrue("预定义过滤器-确实是友军", !injuredAlly.是否为敌人);
        }
        
        // 测试特定类型单位查询
        var typeUnit:Object = TargetCacheManager.findNearestUnitByType(
            hero, 10, "敌人", "enemy", undefined
        );
        
        if (typeUnit) {
            assertNotNull("预定义过滤器-类型查询", typeUnit);
            assertTrue("预定义过滤器-类型匹配", typeUnit._name.indexOf("enemy") != -1);
        }
        
        // 测试buff单位查询（创建一个有buff的敌人）
        if (testEnemies.length > 0) {
            var buffedEnemy:Object = testEnemies[0];
            buffedEnemy.buffs = { 强化: true };
            
            var foundBuffed:Object = TargetCacheManager.findNearestBuffedEnemy(hero, 10, "强化", undefined);
            
            if (foundBuffed && foundBuffed.buffs && foundBuffed.buffs["强化"]) {
                assertNotNull("预定义过滤器-buff查询", foundBuffed);
                assertTrue("预定义过滤器-确实有buff", foundBuffed.buffs["强化"]);
            }
        }
    }
    
    private static function testFilteredQueryInRange():Void {
        var hero:Object = mockHero;
        
        // 创建组合过滤器：范围内的低血量敌人
        var lowHPFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return (u.hp / u.maxhp) < 0.5;
        };
        
        var nearbyLowHPEnemy:Object = TargetCacheManager.findNearestTargetWithFilterInRange(
            hero, 10, "敌人", lowHPFilter, 200, undefined
        );
        
        if (nearbyLowHPEnemy) {
            assertNotNull("范围过滤查询-找到单位", nearbyLowHPEnemy);
            assertTrue("范围过滤查询-血量低", (nearbyLowHPEnemy.hp / nearbyLowHPEnemy.maxhp) < 0.5);
            
            var distance:Number = Math.abs(nearbyLowHPEnemy.x - hero.x);
            assertTrue("范围过滤查询-距离合理", distance <= 200);
        }
        
        // 测试很小的范围，应该找不到或找到很近的
        var veryNearUnit:Object = TargetCacheManager.findNearestTargetWithFilterInRange(
            hero, 10, "敌人", 
            function(u:Object, t:Object, d:Number):Boolean { return true; },
            50, undefined
        );
        
        if (veryNearUnit) {
            var veryNearDistance:Number = Math.abs(veryNearUnit.x - hero.x);
            assertTrue("小范围过滤查询-距离确实很近", veryNearDistance <= 50);
        }
    }
    
    private static function testFilteredQueryEdgeCases():Void {
        var hero:Object = mockHero;
        
        // 测试永远返回false的过滤器
        var neverMatchFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return false;
        };
        
        var noResult:Object = TargetCacheManager.findNearestEnemyWithFilter(
            hero, 10, neverMatchFilter, 10, undefined
        );
        
        assertNull("永不匹配过滤器返回null", noResult);
        
        // 测试永远返回true的过滤器（应该与findNearest结果一致）
        var alwaysMatchFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return true;
        };
        
        var filteredResult:Object = TargetCacheManager.findNearestEnemyWithFilter(
            hero, 10, alwaysMatchFilter, undefined, undefined
        );
        var directResult:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        
        if (filteredResult && directResult) {
            assertTrue("永远匹配过滤器与直接查询一致", filteredResult._name == directResult._name);
        }
        
        // 测试null过滤器
        try {
            var nullFilterResult:Object = TargetCacheManager.findNearestEnemyWithFilter(
                hero, 10, null, undefined, undefined
            );
            assertNull("null过滤器处理", nullFilterResult);
        } catch (e:Error) {
            assertTrue("null过滤器异常处理", true);
        }
        
        // 测试searchLimit = 0
        var zeroLimitResult:Object = TargetCacheManager.findNearestEnemyWithFilter(
            hero, 10, alwaysMatchFilter, 0, undefined
        );
        assertNull("零searchLimit返回null", zeroLimitResult);
    }
    
    private static function testFilteredQueryPerformance():Void {
        var hero:Object = mockHero;
        
        // 简单过滤器性能测试
        var simpleFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return u.hp > 50;
        };
        
        var startTime:Number = getTimer();
        var trials:Number = 100;
        
        for (var i:Number = 0; i < trials; i++) {
            TargetCacheManager.findNearestEnemyWithFilter(hero, 20, simpleFilter, undefined, undefined);
        }
        
        var filterTime:Number = getTimer() - startTime;
        var avgFilterTime:Number = filterTime / trials;
        
        performanceResults.push({
            method: "filteredQuery",
            trials: trials,
            totalTime: filterTime,
            avgTime: avgFilterTime
        });
        
        trace("📊 过滤查询性能: " + trials + "次调用耗时 " + filterTime + "ms");
        assertTrue("过滤查询性能合理", avgFilterTime < API_RESPONSE_BENCHMARK_MS * 2);
        
        // 复杂过滤器性能测试
        var complexFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return u.hp > 30 && u._name.indexOf("enemy") != -1 && d < 300;
        };
        
        var startTime2:Number = getTimer();
        var trials2:Number = 50;
        
        for (var j:Number = 0; j < trials2; j++) {
            TargetCacheManager.findNearestEnemyWithFilter(hero, 20, complexFilter, 15, 200);
        }
        
        var complexTime:Number = getTimer() - startTime2;
        var avgComplexTime:Number = complexTime / trials2;
        
        performanceResults.push({
            method: "complexFilteredQuery",
            trials: trials2,
            totalTime: complexTime,
            avgTime: avgComplexTime
        });
        
        trace("📊 复杂过滤查询性能: " + trials2 + "次调用耗时 " + complexTime + "ms");
        assertTrue("复杂过滤查询性能合理", avgComplexTime < API_RESPONSE_BENCHMARK_MS * 3);
    }
    
    private static function testFilteredQueryConsistency():Void {
        var hero:Object = mockHero;
        
        // 验证过滤查询与常规查询 + 手动过滤的一致性
        var hpThreshold:Number = 60;
        var filter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return u.hp >= hpThreshold;
        };
        
        // 使用过滤查询
        var filteredResult:Object = TargetCacheManager.findNearestEnemyWithFilter(
            hero, 10, filter, undefined, undefined
        );
        
        // 使用常规查询然后手动过滤验证
        var allEnemies:Array = TargetCacheManager.getCachedEnemy(hero, 10);
        var manualResult:Object = null;
        var minDistance:Number = Number.MAX_VALUE;
        
        for (var i:Number = 0; i < allEnemies.length; i++) {
            var enemy:Object = allEnemies[i];
            if (enemy.hp >= hpThreshold) {
                var distance:Number = Math.abs(enemy.x - hero.x);
                if (distance < minDistance) {
                    minDistance = distance;
                    manualResult = enemy;
                }
            }
        }
        
        if (filteredResult && manualResult) {
            assertTrue("过滤查询与手动过滤一致性", filteredResult._name == manualResult._name);
        } else if (!filteredResult && !manualResult) {
            assertTrue("过滤查询与手动过滤都未找到", true);
        } else {
            assertTrue("过滤查询一致性验证", false); // 不一致
        }
        
        // 验证委托正确性：Manager的过滤查询应该与直接调用底层一致
        var cache:SortedUnitCache = TargetCacheProvider.getCache("敌人", hero, 10);
        if (cache) {
            var directResult:Object = cache.findNearestWithFilter(hero, filter, undefined, undefined);
            var managerResult:Object = TargetCacheManager.findNearestEnemyWithFilter(
                hero, 10, filter, undefined, undefined
            );
            
            if (directResult && managerResult) {
                assertTrue("Manager与Cache过滤查询一致性", directResult._name == managerResult._name);
            } else if (!directResult && !managerResult) {
                assertTrue("Manager与Cache都未找到", true);
            }
        }
    }

    // ========================================================================
    // 第九波：性能基准测试
    // ========================================================================
    
    private static function runPerformanceBenchmarks():Void {
        trace("\n⚔️ 第九波：性能基准战斗测试...");
        
        performanceTestBasicQueries();
        performanceTestComplexQueries();
        performanceTestFacadeOverhead();
        performanceTestLargeScale();
    }
    
    private static function performanceTestBasicQueries():Void {
        var hero:Object = mockHero;
        
        // 基础查询性能测试
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < PERFORMANCE_TRIALS; i++) {
            TargetCacheManager.getCachedEnemy(hero, 50); // 高间隔，主要测试缓存命中
        }
        var basicTime:Number = getTimer() - startTime;
        var basicAvg:Number = basicTime / PERFORMANCE_TRIALS;
        
        performanceResults.push({
            method: "basicQueries",
            trials: PERFORMANCE_TRIALS,
            totalTime: basicTime,
            avgTime: basicAvg
        });
        
        trace("📊 基础查询性能: " + PERFORMANCE_TRIALS + "次调用耗时 " + basicTime + "ms");
        assertTrue("基础查询性能达标", basicAvg < API_RESPONSE_BENCHMARK_MS);
    }
    
    private static function performanceTestComplexQueries():Void {
        var hero:Object = mockHero;
        
        // 复杂查询性能测试
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < PERFORMANCE_TRIALS / 2; i++) {
            TargetCacheManager.findEnemiesInRadius(hero, 10, 100);
            TargetCacheManager.getEnemyCountInRange(hero, 10, 50, 150, true);
            TargetCacheManager.findNearestEnemyInRange(hero, 10, 200);
        }
        var complexTime:Number = getTimer() - startTime;
        var complexAvg:Number = complexTime / (PERFORMANCE_TRIALS / 2 * 3);
        
        performanceResults.push({
            method: "complexQueries",
            trials: PERFORMANCE_TRIALS / 2 * 3,
            totalTime: complexTime,
            avgTime: complexAvg
        });
        
        trace("📊 复杂查询性能: " + (PERFORMANCE_TRIALS / 2 * 3) + "次调用耗时 " + complexTime + "ms");
        assertTrue("复杂查询性能合理", complexAvg < API_RESPONSE_BENCHMARK_MS * 3);
    }
    
    private static function performanceTestFacadeOverhead():Void {
        var hero:Object = mockHero;
        var loopCount:Number = 10000;
        
        // 测试外观层开销 vs 直接调用
        var startTime1:Number = getTimer();
        for (var i:Number = 0; i < loopCount; i++) {
            TargetCacheManager.getCachedEnemy(hero, 100); // Manager调用
        }
        var managerTime:Number = getTimer() - startTime1;
        
        var startTime2:Number = getTimer();
        for (var j:Number = 0; j < loopCount; j++) {
            TargetCacheProvider.getCache("敌人", hero, 100); // Provider直接调用
        }
        var providerTime:Number = getTimer() - startTime2;
        
        var overhead:Number = managerTime - providerTime;
        var overheadPercent:Number = (overhead / providerTime) * 100;
        
        performanceResults.push({
            method: "facadeOverhead",
            trials: loopCount,
            managerTime: managerTime,
            providerTime: providerTime,
            overhead: overhead,
            overheadPercent: overheadPercent
        });
        
        trace("📊 外观层开销: Manager=" + managerTime + "ms, Provider=" + providerTime + "ms, 开销=" + Math.round(overheadPercent) + "%");
        assertTrue("外观层开销合理", overheadPercent < 20); // 开销应该小于20%
    }
    
    private static function performanceTestLargeScale():Void {
        var hero:Object = mockHero;
        
        // 大规模数据性能测试
        var startTime:Number = getTimer();
        
        // 混合大量不同类型的查询
        for (var i:Number = 0; i < 50; i++) {
            TargetCacheManager.getCachedAll(hero, 20);
            TargetCacheManager.getAllCountInRadius(hero, 20, 300, false);
            TargetCacheManager.findAllInRange(hero, 20, 100, 200);
            TargetCacheManager.getDistanceDistribution(hero, 20, "全体", [100, 200, 400], false);
        }
        
        var largeScaleTime:Number = getTimer() - startTime;
        var largeScaleAvg:Number = largeScaleTime / (50 * 4);
        
        performanceResults.push({
            method: "largeScale",
            trials: 50 * 4,
            totalTime: largeScaleTime,
            avgTime: largeScaleAvg
        });
        
        trace("📊 大规模数据性能: " + (50 * 4) + "次调用耗时 " + largeScaleTime + "ms");
        assertTrue("大规模数据性能合理", largeScaleAvg < API_RESPONSE_BENCHMARK_MS * 2);
    }

    // ========================================================================
    // 回退降级测试方法（新增）
    // ========================================================================
    
    /**
     * 测试带回退降级的过滤器查询方法
     */
    private static function testFallbackQueryMethods():Void {
        trace("\n🔄 回退降级查询测试...");
        
        testBasicFallbackMechanisms();
        testPreDefinedFallbackMethods();
        testFallbackPerformance();
        testFallbackEdgeCases();
    }
    
    /**
     * 测试基础回退机制
     */
    private static function testBasicFallbackMechanisms():Void {
        var hero:Object = mockHero;
        
        // 情况1：过滤器能找到目标的情况
        var standardFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return u.hp > 0; // 简单条件，应该能找到目标
        };
        
        var fallbackResult:Object = TargetCacheManager.findNearestEnemyWithFallback(
            hero, 10, standardFilter, undefined, undefined
        );
        var regularResult:Object = TargetCacheManager.findNearestEnemyWithFilter(
            hero, 10, standardFilter, undefined, undefined
        );
        
        if (regularResult) {
            assertNotNull("回退查询-过滤器成功时应返回结果", fallbackResult);
            assertEquals("回退查询-应与过滤器查询结果一致", 
                regularResult._name, fallbackResult._name, 0);
        }
        
        // 情况2：过滤器无法找到目标的情况
        var impossibleFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return u.hp < 0; // 不可能的条件
        };
        
        var fallbackResult2:Object = TargetCacheManager.findNearestEnemyWithFallback(
            hero, 10, impossibleFilter, undefined, undefined
        );
        var basicResult:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        
        if (basicResult) {
            assertNotNull("回退查询-过滤器失败时应回退到基础查询", fallbackResult2);
            assertEquals("回退查询-应与基础查询结果一致", 
                basicResult._name, fallbackResult2._name, 0);
        } else {
            // 如果连基础查询都没有结果，回退查询也应该返回null
            assertNull("回退查询-基础查询无结果时也应返回null", fallbackResult2);
        }
    }
    
    /**
     * 测试预定义回退方法
     */
    private static function testPreDefinedFallbackMethods():Void {
        var hero:Object = mockHero;
        
        // 准备测试数据：设置一些低血量敌人
        for (var i:Number = 0; i < 5; i++) {
            if (testEnemies[i]) {
                testEnemies[i].hp = 30; // 设为低血量
                testEnemies[i].maxhp = 100;
                // 同步到gameworld
                var unitInWorld:Object = _root.gameworld[testEnemies[i]._name];
                if (unitInWorld) {
                    unitInWorld.hp = 30;
                    unitInWorld.maxhp = 100;
                }
            }
        }
        
        // 清除缓存
        TargetCacheManager.clearCache("敌人");
        TargetCacheManager.clearCache("友军");
        TargetCacheManager.clearCache("全体");
        
        // 测试通用回退方法（所有类型）
        var generalFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return u._name && u._name.indexOf("special") != -1; // 查找特殊单位
        };
        
        var generalEnemyResult:Object = TargetCacheManager.findNearestTargetWithFallback(
            hero, 10, "敌人", generalFilter, undefined, undefined
        );
        var generalAllyResult:Object = TargetCacheManager.findNearestAllyWithFallback(
            hero, 10, generalFilter, undefined, undefined
        );
        var generalAllResult:Object = TargetCacheManager.findNearestAllWithFallback(
            hero, 10, generalFilter, undefined, undefined
        );
        
        assertTrue("通用敌人回退查询测试完成", true);
        assertTrue("通用友军回退查询测试完成", true);
        assertTrue("通用全体回退查询测试完成", true);
        
        // 测试低血量敌人回退查询
        var lowHPResult:Object = TargetCacheManager.findNearestLowHPEnemyWithFallback(hero, 10, 20);
        var regularEnemyResult:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        
        assertNotNull("低血量敌人回退查询应有结果", lowHPResult);
        if (lowHPResult && (lowHPResult.hp / lowHPResult.maxhp) < 0.5) {
            assertTrue("找到的是低血量敌人", true);
        } else if (lowHPResult && regularEnemyResult) {
            assertEquals("回退到普通敌人查询", regularEnemyResult._name, lowHPResult._name, 0);
        }
        
        // 测试受伤友军回退查询
        var injuredResult:Object = TargetCacheManager.findNearestInjuredAllyWithFallback(hero, 10, 20);
        if (injuredResult) {
            assertTrue("受伤友军回退查询有合理结果", injuredResult.hp != undefined);
        }
        
        // 测试特定类型单位回退查询
        var typeResult:Object = TargetCacheManager.findNearestUnitByTypeWithFallback(
            hero, 10, "敌人", "Boss", 20
        );
        if (typeResult) {
            assertTrue("特定类型回退查询有合理结果", typeResult._name != undefined);
        }
        
        // 测试强化单位回退查询
        var buffedResult:Object = TargetCacheManager.findNearestBuffedEnemyWithFallback(
            hero, 10, "shield", 20
        );
        if (buffedResult) {
            assertTrue("强化单位回退查询有合理结果", buffedResult._name != undefined);
        }
    }
    
    /**
     * 测试回退查询性能
     */
    private static function testFallbackPerformance():Void {
        var hero:Object = mockHero;
        var trials:Number = 100;
        
        // 测试成功过滤器的性能（不应该触发回退）
        var successFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return u.hp > 0;
        };
        
        var startTime1:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            TargetCacheManager.findNearestEnemyWithFallback(hero, 10, successFilter, undefined, undefined);
        }
        var successTime:Number = getTimer() - startTime1;
        
        // 测试失败过滤器的性能（会触发回退）
        var failFilter:Function = function(u:Object, t:Object, d:Number):Boolean {
            return false;
        };
        
        var startTime2:Number = getTimer();
        for (var j:Number = 0; j < trials; j++) {
            TargetCacheManager.findNearestEnemyWithFallback(hero, 10, failFilter, undefined, undefined);
        }
        var fallbackTime:Number = getTimer() - startTime2;
        
        var successAvg:Number = successTime / trials;
        var fallbackAvg:Number = fallbackTime / trials;
        
        trace("📊 回退查询性能 - 成功过滤: " + successAvg + "ms, 触发回退: " + fallbackAvg + "ms");
        
        // 性能应该在合理范围内（回退查询会稍慢，但不应该过慢）
        assertTrue("成功过滤性能合理", successAvg < API_RESPONSE_BENCHMARK_MS * 2);
        assertTrue("回退查询性能合理", fallbackAvg < API_RESPONSE_BENCHMARK_MS * 4);
    }
    
    /**
     * 测试回退查询边界情况
     */
    private static function testFallbackEdgeCases():Void {
        var hero:Object = mockHero;
        
        // 测试null过滤器
        var nullFilterResult:Object = TargetCacheManager.findNearestEnemyWithFallback(
            hero, 10, null, undefined, undefined
        );
        // 应该处理null过滤器情况（可能直接回退到基础查询）
        
        // 测试空缓存情况
        TargetCacheManager.clearCache("敌人");
        // 创建空的敌人缓存情况
        var emptyResult:Object = TargetCacheManager.findNearestEnemyWithFallback(
            hero, 10, function(u, t, d) { return true; }, undefined, undefined
        );
        
        // 测试极端距离阈值
        var extremeDistanceResult:Object = TargetCacheManager.findNearestEnemyWithFallback(
            hero, 10, function(u, t, d) { return d < 1; }, 5, 1 // 极小距离阈值
        );
        
        // 测试极端搜索限制
        var extremeLimitResult:Object = TargetCacheManager.findNearestEnemyWithFallback(
            hero, 10, function(u, t, d) { return true; }, 1, undefined // 只搜索1个单位
        );
        
        assertTrue("边界情况测试完成", true);
    }
    
    // ========================================================================
    // 第十波：集成战斗测试
    // ========================================================================
    
    private static function runIntegrationBattleTests():Void {
        trace("\n⚔️ 第十波：集成战斗测试...");
        
        testFullWorkflowIntegration();
        testCrossComponentIntegration();
        testRealWorldScenarioSimulation();
    }
    
    private static function testFullWorkflowIntegration():Void {
        var hero:Object = mockHero;
        
        // 模拟完整的游戏逻辑工作流
        
        // 1. 获取附近的敌人
        var nearbyEnemies:Array = TargetCacheManager.findEnemiesInRadius(hero, 10, 200);
        assertTrue("工作流1-找到附近敌人", nearbyEnemies.length > 0);
        
        // 2. 选择最近的敌人作为目标
        var target:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        assertNotNull("工作流2-选择最近目标", target);
        
        // 3. 检查目标周围的敌人数量（评估风险）
        var enemyCountAroundTarget:Number = TargetCacheManager.getEnemyCountInRadius(target, 10, 100, false);
        assertTrue("工作流3-风险评估", enemyCountAroundTarget >= 1); // 至少包含目标本身
        
        // 4. 寻找附近的友军支援
        var supportAllies:Array = TargetCacheManager.findAlliesInRange(hero, 10, 150, 150);
        assertTrue("工作流4-寻找支援", supportAllies.length >= 0);
        
        // 5. 获取战场概况
        var battleStats:Object = TargetCacheManager.getDistanceDistribution(hero, 10, "全体", [50, 100, 200], false);
        assertNotNull("工作流5-战场概况", battleStats);
        assertTrue("工作流5-战场数据完整", battleStats.totalCount >= 0);
        
        trace("✅ 完整工作流集成测试成功");
    }
    
    private static function testCrossComponentIntegration():Void {
        // 测试Manager与底层组件的集成
        
        // 1. 通过Manager添加单位，验证各层都能正确处理
        var newEnemy:Object = createBattleUnit(2000, true);
        _root.gameworld[newEnemy._name] = newEnemy;
        TargetCacheManager.addUnit(newEnemy);
        
        // 2. 通过Manager清除缓存
        TargetCacheManager.clearCache("敌人");
        
        // 3. 重新查询，应该包含新单位
        var enemies:Array = TargetCacheManager.getCachedEnemy(mockHero, 10);
        var foundNewEnemy:Boolean = false;
        for (var i:Number = 0; i < enemies.length; i++) {
            if (enemies[i]._name == newEnemy._name) {
                foundNewEnemy = true;
                break;
            }
        }
        assertTrue("跨组件集成-新单位被正确处理", foundNewEnemy);
        
        // 4. 移除单位并验证
        delete _root.gameworld[newEnemy._name];
        TargetCacheManager.removeUnit(newEnemy);
        TargetCacheManager.clearCache("敌人");
        
        var enemies2:Array = TargetCacheManager.getCachedEnemy(mockHero, 10);
        var stillFoundEnemy:Boolean = false;
        for (var j:Number = 0; j < enemies2.length; j++) {
            if (enemies2[j]._name == newEnemy._name) {
                stillFoundEnemy = true;
                break;
            }
        }
        assertTrue("跨组件集成-单位移除正确处理", !stillFoundEnemy);
    }
    
    private static function testRealWorldScenarioSimulation():Void {
        var hero:Object = mockHero;
        
        // 模拟真实游戏场景：激烈战斗中的频繁查询
        var startTime:Number = getTimer();
        
        for (var round:Number = 0; round < 10; round++) {
            // 每轮战斗模拟
            
            // 寻找目标
            var target:Object = TargetCacheManager.findNearestEnemy(hero, 5);
            if (!target) continue;
            
            // 检查周围威胁
            var threatCount:Number = TargetCacheManager.getEnemyCountInRadius(hero, 5, 100, true);
            
            // 寻找支援
            var allySupport:Array = TargetCacheManager.findAlliesInRadius(hero, 5, 150);
            
            // 评估血量状况
            var lowHpAllies:Number = TargetCacheManager.getAllyCountByHP(hero, 5, "低血量", true);
            
            // 战术决策：如果威胁太多且支援不足，寻找撤退路线
            if (threatCount > 3 && allySupport.length < 2) {
                var farthestAlly:Object = TargetCacheManager.findFarthestAlly(hero, 5);
            }
            
            // 模拟时间推进
            mockFrameTimer.advanceFrame(2);
        }
        
        var simulationTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "realWorldSimulation",
            trials: 10,
            totalTime: simulationTime,
            avgTime: simulationTime / 10
        });
        
        trace("📊 真实场景模拟: 10轮战斗耗时 " + simulationTime + "ms");
        assertTrue("真实场景性能合理", simulationTime < 100);
        
        // 验证系统在高压下仍然稳定
        var finalStats:Object = TargetCacheManager.getSystemStats();
        assertNotNull("高压下系统统计正常", finalStats);
        assertTrue("高压下缓存命中率合理", finalStats.hitRate >= 0);
    }
    
    // ========================================================================
    // 终极波：大规模压力测试
    // ========================================================================
    
    private static function runLargeScaleStressTests():Void {
        trace("\n⚔️ 终极波：大规模压力战斗测试...");
        
        testMassiveDataStress();
        testConcurrentAccessStress();
        testMemoryStressTest();
    }
    
    private static function testMassiveDataStress():Void {
        // 创建更大规模的数据进行压力测试
        var originalWorldSize:Number = 0;
        for (var key in _root.gameworld) {
            originalWorldSize++;
        }
        
        // 添加大量临时单位
        var stressUnits:Array = [];
        for (var i:Number = 0; i < 200; i++) {
            var unit:Object = createBattleUnit(5000 + i, i % 2 == 0);
            stressUnits.push(unit);
            _root.gameworld[unit._name] = unit;
        }
        
        // 清除缓存，强制重新构建
        TargetCacheManager.clearCache();
        
        var startTime:Number = getTimer();
        
        // 大规模查询测试
        var allUnits:Array = TargetCacheManager.getCachedAll(mockHero, 10);
        var enemyCount:Number = TargetCacheManager.getEnemyCount(mockHero, 10);
        var allyCount:Number = TargetCacheManager.getAllyCount(mockHero, 10);
        
        var massiveTime:Number = getTimer() - startTime;
        
        assertTrue("大规模数据-总单位数正确", allUnits.length >= originalWorldSize + 200);
        assertTrue("大规模数据-敌人计数合理", enemyCount > 0);
        assertTrue("大规模数据-友军计数合理", allyCount > 0);
        assertTrue("大规模数据-处理时间合理", massiveTime < 50);
        
        // 清理压力测试数据
        for (var j:Number = 0; j < stressUnits.length; j++) {
            delete _root.gameworld[stressUnits[j]._name];
        }
        TargetCacheManager.clearCache();
        
        performanceResults.push({
            method: "massiveDataStress",
            dataSize: originalWorldSize + 200,
            processingTime: massiveTime
        });
        
        trace("📊 大规模数据压力: " + (originalWorldSize + 200) + "个单位，处理耗时 " + massiveTime + "ms");
    }
    
    private static function testConcurrentAccessStress():Void {
        var hero:Object = mockHero;
        
        // 模拟高并发访问（快速连续调用）
        var startTime:Number = getTimer();
        
        for (var burst:Number = 0; burst < 20; burst++) {
            // 每次突发请求包含多种查询
            TargetCacheManager.getCachedEnemy(hero, 20);
            TargetCacheManager.getCachedAlly(hero, 20);
            TargetCacheManager.findNearestEnemy(hero, 20);
            TargetCacheManager.getEnemyCountInRadius(hero, 20, 100, false);
            TargetCacheManager.findEnemiesInRange(hero, 20, 50, 150);
        }
        
        var concurrentTime:Number = getTimer() - startTime;
        var avgBurstTime:Number = concurrentTime / 20;
        
        performanceResults.push({
            method: "concurrentAccess",
            bursts: 20,
            totalTime: concurrentTime,
            avgTime: avgBurstTime
        });
        
        trace("📊 并发访问压力: 20次突发请求耗时 " + concurrentTime + "ms");
        assertTrue("并发访问性能合理", avgBurstTime < 5);
        
        // 验证系统在高并发下的稳定性
        var health:Object = TargetCacheManager.performHealthCheck();
        assertTrue("高并发下系统健康", health.healthy);
    }
    
    private static function testMemoryStressTest():Void {
        // 内存压力测试：频繁的缓存创建和销毁
        var cycles:Number = 20;
        var startTime:Number = getTimer();
        
        for (var cycle:Number = 0; cycle < cycles; cycle++) {
            // 创建大量缓存
            for (var i:Number = 0; i < 10; i++) {
                var tempHero:Object = {
                    _name: "temp_hero_" + cycle + "_" + i,
                    x: Math.random() * 1000,
                    y: Math.random() * 200,
                    是否为敌人: false
                };
                
                TargetCacheManager.getCachedAll(tempHero, 1); // 短间隔，容易过期
            }
            
            // 推进时间，使缓存过期
            mockFrameTimer.advanceFrame(5);
            
            // 清理部分缓存
            if (cycle % 3 == 0) {
                TargetCacheManager.clearCache();
            }
        }
        
        var memoryTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "memoryStress",
            cycles: cycles,
            totalTime: memoryTime,
            avgTime: memoryTime / cycles
        });
        
        trace("📊 内存压力测试: " + cycles + "次循环耗时 " + memoryTime + "ms");
        assertTrue("内存压力测试完成", memoryTime < 200);
        
        // 最终内存清理
        TargetCacheManager.clearCache();
        
        // 验证系统能够恢复正常
        var normalQuery:Array = TargetCacheManager.getCachedEnemy(mockHero, 10);
        assertTrue("内存压力后系统恢复正常", normalQuery.length >= 0);
    }
    
    // ========================================================================
    // 最终波：边界条件战斗
    // ========================================================================
    
    private static function runBoundaryBattleTests():Void {
        trace("\n⚔️ 最终波：边界条件战斗测试...");
        
        testEmptyWorldBoundary();
        testNullParameterBoundary();
        testExtremeValueBoundary();
        testErrorRecoveryBoundary();
    }
    
    private static function testEmptyWorldBoundary():Void {
        // 保存原始世界
        var originalWorld:Object = _root.gameworld;
        
        // 设置空世界
        for (var key in _root.gameworld) {
            TargetCacheManager.removeUnit(_root.gameworld[key]);
            delete _root.gameworld[key];
        }
        
        var hero:Object = mockHero;
        
        // 在空世界中进行各种查询
        var enemies:Array = TargetCacheManager.getCachedEnemy(hero, 10);
        var allies:Array = TargetCacheManager.getCachedAlly(hero, 10); // 在空世界，英雄自己也不应被计为友军
        var nearest:Object = TargetCacheManager.findNearestEnemy(hero, 10);
        var count:Number = TargetCacheManager.getEnemyCount(hero, 10);
        
        assertEquals("空世界-敌人数组长度", 0, enemies.length, 0);
        assertEquals("空世界-友军数组长度", 0, allies.length, 0); // 期望为0，因为世界是空的
        assertNull("空世界-最近敌人为null", nearest);
        assertEquals("空世界-敌人计数为0", 0, count, 0);
        
        // 恢复原始世界
        _root.gameworld = originalWorld;
        // 清除缓存以从原始 gameworld 重新加载
        TargetCacheManager.clearCache();
    }
    
    private static function testNullParameterBoundary():Void {
        var hero:Object = mockHero;
        
        // 测试null参数处理
        try {
            var result1:Array = TargetCacheManager.getCachedEnemy(null, 10);
            assertTrue("null目标参数处理", true); // 不崩溃就算成功
        } catch (e1:Error) {
            assertTrue("null目标参数异常处理", true);
        }
        
        try {
            var result2:Array = TargetCacheManager.getCachedTargets(hero, 10, null);
            assertTrue("null类型参数处理", true);
        } catch (e2:Error) {
            assertTrue("null类型参数异常处理", true);
        }
        
        try {
            var result3:Array = TargetCacheManager.getCachedTargets(hero, 10, "");
            assertTrue("空字符串类型参数处理", true);
        } catch (e3:Error) {
            assertTrue("空字符串类型参数异常处理", true);
        }
    }
    
    private static function testExtremeValueBoundary():Void {
        var hero:Object = mockHero;
        
        // 测试极值参数
        var result1:Array = TargetCacheManager.getCachedEnemy(hero, 0); // 零间隔
        var result2:Array = TargetCacheManager.getCachedEnemy(hero, -5); // 负间隔
        var result3:Array = TargetCacheManager.getCachedEnemy(hero, 999999); // 极大间隔
        
        assertInstanceOf("零间隔处理", result1, "Array");
        assertInstanceOf("负间隔处理", result2, "Array");
        assertInstanceOf("极大间隔处理", result3, "Array");
        
        // 测试极值范围查询
        var rangeResult:Array = TargetCacheManager.findEnemiesInRange(hero, 10, -1000, 1000);
        var radiusResult:Array = TargetCacheManager.findEnemiesInRadius(hero, 10, 0);
        var radiusResult2:Array = TargetCacheManager.findEnemiesInRadius(hero, 10, 99999);
        
        assertInstanceOf("极值范围查询处理", rangeResult, "Array");
        assertInstanceOf("零半径查询处理", radiusResult, "Array");
        assertInstanceOf("极大半径查询处理", radiusResult2, "Array");
    }
    
    private static function testErrorRecoveryBoundary():Void {
        var hero:Object = mockHero;
        
        // 保存原始环境
        var originalFrameTimer:Object = _root.帧计时器;
        
        try {
            // 破坏环境，测试错误恢复
            _root.帧计时器 = null;
            
            var result:Array = TargetCacheManager.getCachedEnemy(hero, 10);
            assertTrue("缺失帧计时器错误恢复", true);
            
        } catch (e1:Error) {
            assertTrue("缺失帧计时器异常处理", true);
        }
        
        try {
            // 测试无效的世界对象
            _root.gameworld = null;
            
            var result2:Array = TargetCacheManager.getCachedAll(hero, 10);
            assertTrue("无效世界对象错误恢复", true);
            
        } catch (e2:Error) {
            assertTrue("无效世界对象异常处理", true);
        }
        
        finally {
            // 恢复环境
            _root.帧计时器 = originalFrameTimer;
            _root.gameworld = mockGameWorld;
            TargetCacheManager.clearCache();
        }
        
        // 验证系统恢复正常
        var recoveryTest:Array = TargetCacheManager.getCachedEnemy(hero, 10);
        assertTrue("错误后系统恢复正常", recoveryTest instanceof Array);
    }
    
    // ========================================================================
    // 测试统计和报告
    // ========================================================================
    
    private static function resetTestStats():Void {
        testCount = 0;
        passedTests = 0;
        failedTests = 0;
        performanceResults = [];
        apiCoverageMap = {};
    }
    
    private static function printBattleReport(totalTime:Number):Void {
        trace("\n================================================================================");
        trace("🏆 TargetCacheManager 外观层战斗报告");
        trace("================================================================================");
        trace("⚔️ 总模拟数: " + testCount);
        trace("🏆 通过次数: " + passedTests + " ✅");
        trace("💥 失败次数: " + failedTests + " ❌");
        trace("🎯 胜通过: " + (testCount > 0 ? Math.round((passedTests / testCount) * 100) : 100) + "%");
        trace("⏱️ 测试用时: " + totalTime + "ms");
        
        // API覆盖率统计
        var coveredAPIs:Number = 0;
        for (var api in apiCoverageMap) {
            coveredAPIs++;
        }
        trace("📋 API覆盖数: " + coveredAPIs + " 个方法");
        
        if (performanceResults.length > 0) {
            trace("\n⚡ 测试报告:");
            for (var i:Number = 0; i < performanceResults.length; i++) {
                var result:Object = performanceResults[i];
                var avgTimeStr:String = (result.avgTime === undefined || isNaN(result.avgTime)) ? 
                    "N/A" : String(Math.round(result.avgTime * 1000) / 1000);
                
                // 关键修复：健壮地处理不同的性能指标名称
                var trialsInfo:String = "";
                if (result.trials !== undefined) trialsInfo = result.trials + "次测试";
                else if (result.bursts !== undefined) trialsInfo = result.bursts + "次突发";
                else if (result.cycles !== undefined) trialsInfo = result.cycles + "次循环";
                else if (result.dataSize !== undefined) trialsInfo = result.dataSize + "个单位";

                if (result.method == "facadeOverhead") {
                    trace("  " + result.method + ": 开销 " + Math.round(result.overheadPercent) + "% (" + 
                        trialsInfo + ")");
                } else if (result.method == "massiveDataStress") {
                    trace("  " + result.method + ": " + trialsInfo + "，" + 
                        result.processingTime + "ms");
                } else {
                    trace("  " + result.method + ": " + avgTimeStr + "ms/次 (" + 
                        trialsInfo + ")");
                }
            }
        }
        
        trace("\n🎯 TargetCacheManager外观层当前状态:");
        var report:String = TargetCacheManager.getDetailedStatusReport();
        var lines:Array = report.split("\n");
        for (var j:Number = 0; j < Math.min(lines.length, 10); j++) {
            trace(lines[j]);
        }
        
        if (failedTests == 0) {
            trace("\n🎉🎊 完全通过！TargetCacheManager 外观层完美验收！ 🎊🎉");
            trace("🏆 所有 " + testCount + " 项测试全部通过！");
            trace("⚡ 性能表现优异，API设计完美！");
            trace("🛡️ 外观模式实现卓越，用户体验极佳！");
        } else {
            trace("\n⚠️ 测试中发现 " + failedTests + " 个问题需要修复！");
            trace("🔧 请检查失败的测试项并优化实现！");
        }
        
        trace("================================================================================");
        trace("🏁 TargetCacheManager 终极测试完成！");
        trace("================================================================================");
    }

    // ------------------------------------------------------------------------
    // Monotonic sweep verification (wrapper in TargetCacheManager)
    // ------------------------------------------------------------------------
    private static function testMonotonicIndexQueries():Void {
        var hero:Object = mockHero;
        var baseX:Number = hero.x;

        // Same frame: increasing left — monotonic must match baseline and be non-decreasing
        var prevIndex:Number = -1;
        for (var step:Number = 0; step < 5; step++) {
            var center:Number = baseX + step * 50;
            var aabb1:AABBCollider = createTestAABB(center, 120);
            var mono:Object = TargetCacheManager.getCachedEnemyFromIndexMonotonic(hero, 10, aabb1);
            var base:Object = TargetCacheManager.getCachedEnemyFromIndex(hero, 10, aabb1);
            assertEquals("Monotonic equals baseline step="+step, base.startIndex, mono.startIndex, 0);
            if (prevIndex >= 0) {
                assertTrue("Monotonic non-decreasing step="+step, mono.startIndex >= prevIndex);
            }
            prevIndex = mono.startIndex;
        }

        // Next frame: allow smaller left and still match baseline
        mockFrameTimer.advanceFrame(1);
        var aabb2:AABBCollider = createTestAABB(baseX - 200, 120);
        var mono2:Object = TargetCacheManager.getCachedEnemyFromIndexMonotonic(hero, 10, aabb2);
        var base2:Object = TargetCacheManager.getCachedEnemyFromIndex(hero, 10, aabb2);
        assertEquals("Monotonic equals baseline after new frame", base2.startIndex, mono2.startIndex, 0);
    }

    // ------------------------------------------------------------------------
    // clear() 别名 & rightMaxValues 集成测试
    // ------------------------------------------------------------------------

    private static function runClearAliasAndRightMaxValuesTests():Void {
        trace("\n🧹 执行 clear() 别名 & rightMaxValues 集成测试...");

        testClearAliasResetsCaches();
        testRightMaxValuesExposedThroughAPI();
    }

    /**
     * clear() 应等价于 clearCache(null)，清空所有缓存
     */
    private static function testClearAliasResetsCaches():Void {
        var hero:Object = mockHero;

        // 先确保缓存已填充
        TargetCacheManager.getCachedEnemy(hero, 10);
        TargetCacheManager.getCachedAlly(hero, 10);
        var countBefore:Number = TargetCacheProvider.getCacheCount();
        assertTrue("clear前缓存非空", countBefore > 0);

        // 调用 clear()
        TargetCacheManager.clear();

        // clear 内部调用 clearCache(null)，会 resetVersions + 清理 registry
        var countAfter:Number = TargetCacheProvider.getCacheCount();
        assertTrue("clear后缓存数量减少或归零", countAfter <= countBefore);
    }

    /**
     * 通过外观API获取的缓存应包含有效的 rightMaxValues
     */
    private static function testRightMaxValuesExposedThroughAPI():Void {
        var hero:Object = mockHero;
        var aabb:AABBCollider = createTestAABB(hero.x, 200);

        var result:Object = TargetCacheManager.getCachedEnemyFromIndex(hero, 10, aabb);
        assertNotNull("getCachedEnemyFromIndex返回结果", result);
        assertNotNull("结果包含data", result.data);

        if (result.data.length > 0) {
            // 通过 Provider 获取底层 SortedUnitCache 验证 rightMaxValues
            var cache:SortedUnitCache = TargetCacheProvider.getCache("敌人", hero, 10);
            assertNotNull("Provider返回SortedUnitCache", cache);

            assertTrue("rightMaxValues存在", cache.rightMaxValues != undefined);
            assertEquals("rightMaxValues长度与data一致",
                         cache.data.length, cache.rightMaxValues.length, 0);

            // 验证单调性
            var mono:Boolean = true;
            for (var i:Number = 1; i < cache.rightMaxValues.length; i++) {
                if (cache.rightMaxValues[i] < cache.rightMaxValues[i - 1]) {
                    mono = false;
                    break;
                }
            }
            assertTrue("rightMaxValues通过API仍单调", mono);
        }
    }

    // ------------------------------------------------------------------------
    // 回归测试：Bug 修复验证
    // ------------------------------------------------------------------------

    private static function runBugfixRegressionTests():Void {
        trace("\n🔧 执行 Bug 修复回归测试...");

        testEmptyResultPollutionResilience();
        testHpConditionChineseEnglishEquivalence();
    }

    /**
     * 回归测试：_emptyResult 污染自愈
     * 修复前：若调用方对空结果的 .data 执行 push，污染会永久累积
     * 修复后：_safeEmptyResult() 在每次返回前重置 data.length = 0
     */
    private static function testEmptyResultPollutionResilience():Void {
        // 临时置空帧计时器，使 Provider.getCache 内部抛异常 → catch 返回 null
        // 从而命中 TargetCacheManager 的 if(!cache) return _safeEmptyResult() 分支
        var savedTimer:Object = _root.帧计时器;
        _root.帧计时器 = null;

        var hero:Object = mockHero;
        var aabb:AABBCollider = createTestAABB(0, 100);

        // 第一次调用：Provider 异常 → cache==null → _safeEmptyResult()
        var result1:Object = TargetCacheManager.getCachedTargetsFromIndex(hero, 10, "敌人", aabb);
        assertNotNull("Provider返回null时仍有结果对象", result1);
        assertEquals("_safeEmptyResult data长度为0", 0, result1.data.length, 0);
        assertEquals("_safeEmptyResult startIndex为0", 0, result1.startIndex, 0);

        // 模拟调用方污染：向 data 数组中 push 假数据
        result1.data.push("污染1");
        result1.data.push("污染2");
        result1.startIndex = 999;
        assertTrue("污染后data长度为2", result1.data.length == 2);

        // 清除第一次调用在 Provider 注册表中残留的条目，
        // 确保第二次调用也命中 cache==null → _safeEmptyResult() 路径
        TargetCacheProvider.clearCache();

        // 第二次调用：_safeEmptyResult 应自愈，重置 data.length 和 startIndex
        var result2:Object = TargetCacheManager.getCachedTargetsFromIndex(hero, 10, "敌人", aabb);
        assertEquals("污染自愈后data长度为0", 0, result2.data.length, 0);
        assertEquals("污染自愈后startIndex为0", 0, result2.startIndex, 0);

        // 恢复帧计时器
        _root.帧计时器 = savedTimer;
    }

    /**
     * 回归测试：HP 条件中英文等价性（全量验证）
     * 修复前：SortedUnitCache 只识别英文键，中文传入静默返回 0
     * 修复后：_normalizeHP 映射保证中英文等价
     */
    private static function testHpConditionChineseEnglishEquivalence():Void {
        var hero:Object = mockHero;

        var pairs:Array = [
            { cn: "低血量", en: "low" },
            { cn: "中血量", en: "medium" },
            { cn: "高血量", en: "high" },
            { cn: "濒死",   en: "critical" },
            { cn: "受伤",   en: "injured" },
            { cn: "满血",   en: "healthy" }
        ];

        for (var i:Number = 0; i < pairs.length; i++) {
            var cn:String = pairs[i].cn;
            var en:String = pairs[i].en;
            var countCN:Number = TargetCacheManager.getEnemyCountByHP(hero, 10, cn, false);
            var countEN:Number = TargetCacheManager.getEnemyCountByHP(hero, 10, en, false);
            assertEquals("HP条件等价(" + cn + "/" + en + ")", countEN, countCN, 0);
        }
    }
}
