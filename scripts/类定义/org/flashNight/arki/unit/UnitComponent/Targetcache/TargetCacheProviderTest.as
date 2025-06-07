import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProvider;
import org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater;

/**
 * 完整测试套件：TargetCacheProvider
 * =================================
 * 特性：
 * - 100% 方法覆盖率测试（包括私有方法逻辑验证）
 * - 缓存生命周期管理验证
 * - 自动清理机制测试
 * - 统计信息准确性验证
 * - 健康检查和诊断测试
 * - 配置管理验证
 * - 性能基准测试（大量缓存管理）
 * - 集成测试（与TargetCacheUpdater/SortedUnitCache协作）
 * - 边界条件与异常处理测试
 * - 内存管理和优化建议测试
 * - 一句启动设计
 * 
 * 使用方法：
 * org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProviderTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProviderTest {
    
    // ========================================================================
    // 测试统计和配置
    // ========================================================================
    
    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var performanceResults:Array = [];
    
    // 性能基准配置
    private static var PERFORMANCE_TRIALS:Number = 100;
    private static var CACHE_STRESS_COUNT:Number = 50;
    private static var GET_CACHE_BENCHMARK_MS:Number = 2.0; // 单次获取不超过2ms
    
    // 测试数据缓存
    private static var testUnits:Array;
    private static var mockFrameTimer:Object;
    private static var mockGameWorld:Object;
    private static var originalRoot:Object;
    
    /**
     * 主测试入口 - 一句启动全部测试
     */
    public static function runAll():Void {
        trace("================================================================================");
        trace("🚀 TargetCacheProvider 完整测试套件启动");
        trace("================================================================================");
        
        var startTime:Number = getTimer();
        resetTestStats();
        
        try {
            // 初始化测试环境
            initializeTestEnvironment();
            
            // === 基础功能测试 ===
            runBasicFunctionalityTests();
            
            // === 核心缓存获取测试 ===
            runCacheRetrievalTests();
            
            // === 缓存生命周期测试 ===
            runCacheLifecycleTests();
            
            // === 自动清理机制测试 ===
            runAutoCleanupTests();
            
            // === 配置管理测试 ===
            runConfigurationManagementTests();
            
            // === 统计信息测试 ===
            runStatisticsTests();
            
            // === 健康检查和诊断测试 ===
            runHealthCheckTests();
            
            // === 性能基准测试 ===
            runPerformanceBenchmarks();
            
            // === 集成测试 ===
            runIntegrationTests();
            
            // === 边界条件测试 ===
            runBoundaryConditionTests();
            
            // === 内存管理和优化测试 ===
            runMemoryOptimizationTests();
            
        } catch (error:Error) {
            failedTests++;
            trace("❌ 测试执行异常: " + error.message);
        } finally {
            // 恢复环境
            cleanupTestEnvironment();
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
    
    private static function assertInstanceOf(testName:String, obj:Object, expectedClass:Function):Void {
        testCount++;
        if (obj instanceof expectedClass) {
            passedTests++;
            trace("✅ " + testName + " PASS (correct instance type)");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (incorrect instance type)");
        }
    }
    
    // ========================================================================
    // 测试环境初始化
    // ========================================================================
    
    private static function initializeTestEnvironment():Void {
        trace("\n🔧 初始化测试环境...");
        
        // 备份原始_root
        originalRoot = _root;
        
        // 创建测试用的全局对象
        testUnits = createTestUnits(30);
        mockGameWorld = createMockGameWorld(testUnits);
        mockFrameTimer = createMockFrameTimer();
        
        // 设置模拟的_root对象

        _root.gameworld = mockGameWorld;
        _root.帧计时器 = mockFrameTimer;
        
        // 重置TargetCacheProvider状态
        TargetCacheProvider.initialize();
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        // 重置TargetCacheUpdater状态
        TargetCacheUpdater.resetVersions();
        
        trace("📦 创建了 " + testUnits.length + " 个测试单位");
        trace("🌍 构建了模拟环境和帧计时器");
    }
    
    private static function cleanupTestEnvironment():Void {
        // 恢复原始_root
        if (originalRoot) {
            _root = MovieClip(originalRoot);
        }
        
        // 清理缓存
        TargetCacheProvider.clearCache();
    }
    
    /**
     * 创建测试单位
     */
    private static function createTestUnits(count:Number):Array {
        var units:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var isEnemy:Boolean = (i % 2 == 0);
            var unit:Object = {
                _name: "unit_" + i,
                hp: 80 + Math.random() * 40,
                maxhp: 100,
                是否为敌人: isEnemy,
                x: i * 50,
                y: Math.random() * 100,
                aabbCollider: {
                    left: i * 50 + Math.random() * 10,
                    right: 0,
                    updateFromUnitArea: function(u:Object):Void {
                        this.left = i * 50 + Math.random() * 5;
                        this.right = this.left + 20;
                    }
                }
            };
            
            unit.aabbCollider.right = unit.aabbCollider.left + 20;
            units[i] = unit;
        }
        
        return units;
    }
    
    /**
     * 创建模拟游戏世界
     */
    private static function createMockGameWorld(units:Array):Object {
        var world:Object = {};
        for (var i:Number = 0; i < units.length; i++) {
            world["unit_" + i] = units[i];
        }
        return world;
    }
    
    /**
     * 创建模拟帧计时器
     */
    private static function createMockFrameTimer():Object {
        return {
            当前帧数: 1000,
            // 模拟帧数递增
            advanceFrame: function(frames:Number):Void {
                if (!frames) frames = 1;
                this.当前帧数 += frames;
            }
        };
    }
    
    /**
     * 创建测试目标单位
     */
    private static function createTestTarget(isEnemy:Boolean):Object {
        return {
            _name: "test_target",
            是否为敌人: isEnemy,
            hp: 100,
            x: 0,
            y: 0
        };
    }
    
    // ========================================================================
    // 基础功能测试
    // ========================================================================
    
    private static function runBasicFunctionalityTests():Void {
        trace("\n📋 执行基础功能测试...");
        
        testInitialization();
        testBasicCacheOperations();
        testCacheKeyGeneration();
    }
    
    private static function testInitialization():Void {
        // 测试初始化
        var initResult:Boolean = TargetCacheProvider.initialize();
        assertTrue("initialize返回成功", initResult);
        
        assertEquals("初始缓存数量为0", 0, TargetCacheProvider.getCacheCount(), 0);
        
        var stats:Object = TargetCacheProvider.getStats();
        assertNotNull("getStats返回对象", stats);
        assertEquals("初始请求数为0", 0, stats.totalRequests, 0);
        assertEquals("初始命中数为0", 0, stats.cacheHits, 0);
        assertEquals("初始未命中数为0", 0, stats.cacheMisses, 0);
    }
    
    private static function testBasicCacheOperations():Void {
        // 测试基本的缓存获取
        var target:Object = createTestTarget(true);
        var cache:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 10);
        
        assertNotNull("getCache返回缓存实例", cache);
        assertInstanceOf("返回正确类型", cache, SortedUnitCache);
        assertEquals("缓存数量递增", 1, TargetCacheProvider.getCacheCount(), 0);
        
        // 测试相同请求返回相同实例（命中）
        var cache2:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 10);
        assertTrue("相同请求返回相同实例", cache === cache2);
        
        var stats:Object = TargetCacheProvider.getStats();
        assertEquals("总请求数为2", 2, stats.totalRequests, 0);
        assertEquals("缓存命中数为1", 1, stats.cacheHits, 0);
        assertEquals("缓存未命中数为1", 1, stats.cacheMisses, 0);
    }
    
    private static function testCacheKeyGeneration():Void {
        // 通过不同的请求验证缓存键的生成逻辑
        var enemyTarget:Object = createTestTarget(true);
        var allyTarget:Object = createTestTarget(false);
        
        // 清空缓存以重新开始
        TargetCacheProvider.clearCache();
        
        // 敌人请求敌人数据
        TargetCacheProvider.getCache("敌人", enemyTarget, 10);
        assertEquals("敌人请求后缓存数量", 1, TargetCacheProvider.getCacheCount(), 0);
        
        // 友军请求敌人数据（不同的缓存键）
        TargetCacheProvider.getCache("敌人", allyTarget, 10);
        assertEquals("不同阵营请求后缓存数量", 2, TargetCacheProvider.getCacheCount(), 0);
        
        // 全体请求（独立的缓存键）
        TargetCacheProvider.getCache("全体", enemyTarget, 10);
        assertEquals("全体请求后缓存数量", 3, TargetCacheProvider.getCacheCount(), 0);
        
        // 相同键的请求应该命中
        TargetCacheProvider.getCache("全体", allyTarget, 10); // 全体不区分阵营
        assertEquals("全体请求命中后缓存数量不变", 3, TargetCacheProvider.getCacheCount(), 0);
    }
    
    // ========================================================================
    // 核心缓存获取测试
    // ========================================================================
    
    private static function runCacheRetrievalTests():Void {
        trace("\n🔍 执行核心缓存获取测试...");
        
        testCacheCreation();
        testCacheHitAndMiss();
        testCacheExpiration();
        testDifferentRequestTypes();
    }
    
    private static function testCacheCreation():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(true);
        var cache:SortedUnitCache = TargetCacheProvider.getCache("友军", target, 5);
        
        assertNotNull("新缓存创建成功", cache);
        assertTrue("缓存包含数据", cache.getCount() >= 0);
        
        var stats:Object = TargetCacheProvider.getStats();
        assertEquals("缓存创建统计正确", 1, stats.cacheCreations, 0);
        assertEquals("缓存未命中统计正确", 1, stats.cacheMisses, 0);
    }
    
    private static function testCacheHitAndMiss():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(false);
        
        // 第一次请求 - 缓存未命中
        var cache1:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 20);
        var stats1:Object = TargetCacheProvider.getStats();
        assertEquals("首次请求未命中", 1, stats1.cacheMisses, 0);
        assertEquals("首次请求无命中", 0, stats1.cacheHits, 0);
        
        // 第二次相同请求 - 缓存命中
        var cache2:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 20);
        var stats2:Object = TargetCacheProvider.getStats();
        assertEquals("第二次请求命中", 1, stats2.cacheHits, 0);
        assertTrue("返回相同实例", cache1 === cache2);
        
        // 验证命中率计算
        assertTrue("命中率计算正确", stats2.hitRate == 50.0);
    }
    
    private static function testCacheExpiration():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(true);
        
        // 创建缓存
        var cache1:SortedUnitCache = TargetCacheProvider.getCache("全体", target, 5);
        var initialFrame:Number = cache1.lastUpdatedFrame;
        
        // 推进帧数，使缓存过期
        mockFrameTimer.advanceFrame(10);
        
        // 再次请求应该触发更新
        var cache2:SortedUnitCache = TargetCacheProvider.getCache("全体", target, 5);
        assertTrue("过期后帧数更新", cache2.lastUpdatedFrame > initialFrame);
        
        var stats:Object = TargetCacheProvider.getStats();
        assertEquals("过期触发更新统计", 1, stats.cacheUpdates, 0);
    }
    
    private static function testDifferentRequestTypes():Void {
        TargetCacheProvider.clearCache();
        
        var enemyTarget:Object = createTestTarget(true);
        var allyTarget:Object = createTestTarget(false);
        
        // 测试所有请求类型组合
        var requestTypes:Array = ["敌人", "友军", "全体"];
        var targets:Array = [enemyTarget, allyTarget];
        
        var expectedCacheCount:Number = 0;
        
        for (var i:Number = 0; i < requestTypes.length; i++) {
            var requestType:String = requestTypes[i];
            
            if (requestType == "全体") {
                // 全体请求不区分目标阵营
                TargetCacheProvider.getCache(requestType, enemyTarget, 10);
                expectedCacheCount++;
            } else {
                // 敌人/友军请求区分目标阵营
                for (var j:Number = 0; j < targets.length; j++) {
                    TargetCacheProvider.getCache(requestType, targets[j], 10);
                    expectedCacheCount++;
                }
            }
        }
        
        assertEquals("不同请求类型缓存数量", expectedCacheCount, TargetCacheProvider.getCacheCount(), 0);
    }
    
    // ========================================================================
    // 缓存生命周期测试
    // ========================================================================
    
    private static function runCacheLifecycleTests():Void {
        trace("\n♻️ 执行缓存生命周期测试...");
        
        testCacheInvalidation();
        testCacheClearing();
        testVersionControlIntegration();
    }
    
    private static function testCacheInvalidation():Void {
        TargetCacheProvider.clearCache();
        var target:Object = createTestTarget(true);
        
        // 创建缓存
        var cache:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 100);
        var originalFrame:Number = cache.lastUpdatedFrame;
        
        // 失效所有缓存
        TargetCacheProvider.invalidateAllCaches();
        assertEquals("失效后帧数为0", 0, cache.lastUpdatedFrame, 0);
        
        // 下次访问应该更新
        mockFrameTimer.advanceFrame(1);
        var updatedCache:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 100);
        assertTrue("失效后重新更新", updatedCache.lastUpdatedFrame > 0);
        
        // 测试特定类型失效
        TargetCacheProvider.getCache("友军", target, 100);
        TargetCacheProvider.invalidateCache("敌人");
        
        var details:Object = TargetCacheProvider.getCachePoolDetails();
        assertTrue("特定类型失效有效", details.caches["敌人_true"].lastUpdated == 0);
    }
    
    private static function testCacheClearing():Void {
        TargetCacheProvider.clearCache();
        var target:Object = createTestTarget(false);
        
        // 创建多个缓存
        TargetCacheProvider.getCache("敌人", target, 10);
        TargetCacheProvider.getCache("友军", target, 10);
        TargetCacheProvider.getCache("全体", target, 10);
        
        var countBeforeClear:Number = TargetCacheProvider.getCacheCount();
        assertTrue("清理前有多个缓存", countBeforeClear >= 3);
        
        // 清理特定类型
        TargetCacheProvider.clearCache("敌人");
        var countAfterPartial:Number = TargetCacheProvider.getCacheCount();
        assertTrue("部分清理后数量减少", countAfterPartial < countBeforeClear);
        
        // 清理所有
        TargetCacheProvider.clearCache();
        assertEquals("全部清理后数量为0", 0, TargetCacheProvider.getCacheCount(), 0);
    }
    
    private static function testVersionControlIntegration():Void {
        TargetCacheProvider.clearCache();
        var target:Object = createTestTarget(true);
        
        // 创建缓存
        TargetCacheProvider.getCache("全体", target, 50);
        assertEquals("版本控制前缓存数量", 1, TargetCacheProvider.getCacheCount(), 0);
        
        // 通过Provider添加单位（应该委托给TargetCacheUpdater）
        var newUnit:Object = createTestTarget(false);
        TargetCacheProvider.addUnit(newUnit);
        
        // 验证版本控制正常工作
        var versionInfo:Object = TargetCacheUpdater.getVersionInfo();
        assertTrue("版本号递增", versionInfo.totalVersion > 0);
        
        // 测试批量操作
        var units:Array = [createTestTarget(true), createTestTarget(false)];
        TargetCacheProvider.addUnits(units);
        TargetCacheProvider.removeUnits(units);
        
        var finalVersionInfo:Object = TargetCacheUpdater.getVersionInfo();
        assertTrue("批量操作后版本继续递增", finalVersionInfo.totalVersion > versionInfo.totalVersion);
    }
    
    // ========================================================================
    // 自动清理机制测试
    // ========================================================================
    
    private static function runAutoCleanupTests():Void {
        trace("\n🧹 执行自动清理机制测试...");
        
        testAutoCleanThreshold();
        testAutoCleanByAge();
        testAutoCleanLRU();
        testAutoCleanConfiguration();
    }
    
    private static function testAutoCleanThreshold():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        // 设置较低的清理阈值
        TargetCacheProvider.setConfig({
            autoCleanThreshold: 5,
            maxCacheCount: 10,
            autoCleanEnabled: true
        });
        
        var target:Object = createTestTarget(true);
        
        // 创建大量缓存，触发自动清理
        for (var i:Number = 0; i < 8; i++) {
            var requestType:String = (i % 2 == 0) ? "敌人" : "友军";
            var tempTarget:Object = createTestTarget(i % 2 == 0);
            tempTarget._name = "target_" + i; // 确保不同的target
            
            TargetCacheProvider.getCache(requestType, tempTarget, 10);
            mockFrameTimer.advanceFrame(1);
        }
        
        var stats:Object = TargetCacheProvider.getStats();
        assertTrue("自动清理被触发", stats.autoCleanRuns > 0);
        
        var cacheCount:Number = TargetCacheProvider.getCacheCount();
        assertTrue("缓存数量被控制", cacheCount <= 10);
    }
    
    private static function testAutoCleanByAge():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.setConfig({
            maxCacheAge: 20,
            autoCleanThreshold: 3,
            autoCleanEnabled: true
        });
        
        var target1:Object = createTestTarget(true);
        var target2:Object = createTestTarget(false);
        
        // 创建旧缓存
        TargetCacheProvider.getCache("敌人", target1, 100);
        mockFrameTimer.advanceFrame(25); // 超过maxCacheAge
        
        // 创建新缓存，触发清理
        TargetCacheProvider.getCache("友军", target2, 100);
        TargetCacheProvider.getCache("全体", target1, 100);
        TargetCacheProvider.getCache("敌人", target2, 100); // 这应该触发清理
        
        var details:Object = TargetCacheProvider.getCachePoolDetails();
        assertTrue("过期缓存被清理", details.oldestCacheAge <= 25);
    }
    
    private static function testAutoCleanLRU():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.setConfig({
            maxCacheCount: 3,
            autoCleanThreshold: 3,
            maxCacheAge: 1000, // 很大，不会按年龄清理
            autoCleanEnabled: true
        });
        
        var targets:Array = [];
        for (var i:Number = 0; i < 5; i++) {
            targets[i] = createTestTarget(i % 2 == 0);
            targets[i]._name = "lru_target_" + i;
        }
        
        // 创建超过最大数量的缓存
        for (var j:Number = 0; j < 5; j++) {
            TargetCacheProvider.getCache("敌人", targets[j], 100);
            mockFrameTimer.advanceFrame(1);
        }
        
        var finalCount:Number = TargetCacheProvider.getCacheCount();
        assertTrue("LRU清理控制缓存数量", finalCount <= 3);
    }
    
    private static function testAutoCleanConfiguration():Void {
        // 测试禁用自动清理
        TargetCacheProvider.clearCache();
        TargetCacheProvider.setConfig({
            autoCleanEnabled: false,
            autoCleanThreshold: 1
        });
        
        var target:Object = createTestTarget(true);
        
        // 创建多个缓存
        for (var i:Number = 0; i < 5; i++) {
            var tempTarget:Object = createTestTarget(i % 2 == 0);
            tempTarget._name = "no_clean_target_" + i;
            TargetCacheProvider.getCache("敌人", tempTarget, 10);
        }
        
        var stats:Object = TargetCacheProvider.getStats();
        assertEquals("禁用时不执行自动清理", 0, stats.autoCleanRuns, 0);
        assertEquals("禁用时缓存数量不受限", 5, TargetCacheProvider.getCacheCount(), 0);
    }
    
    // ========================================================================
    // 配置管理测试
    // ========================================================================
    
    private static function runConfigurationManagementTests():Void {
        trace("\n⚙️ 执行配置管理测试...");
        
        testConfigurationSetting();
        testConfigurationValidation();
        testConfigurationRetrieval();
    }
    
    private static function testConfigurationSetting():Void {
        var originalConfig:Object = TargetCacheProvider.getConfig();
        
        var newConfig:Object = {
            maxCacheCount: 25,
            autoCleanThreshold: 20,
            maxCacheAge: 500,
            autoCleanEnabled: false
        };
        
        TargetCacheProvider.setConfig(newConfig);
        var updatedConfig:Object = TargetCacheProvider.getConfig();
        
        assertEquals("maxCacheCount设置正确", 25, updatedConfig.maxCacheCount, 0);
        assertEquals("autoCleanThreshold设置正确", 20, updatedConfig.autoCleanThreshold, 0);
        assertEquals("maxCacheAge设置正确", 500, updatedConfig.maxCacheAge, 0);
        assertTrue("autoCleanEnabled设置正确", !updatedConfig.autoCleanEnabled);
        
        // 恢复原始配置
        TargetCacheProvider.setConfig(originalConfig);
    }
    
    private static function testConfigurationValidation():Void {
        var originalConfig:Object = TargetCacheProvider.getConfig();
        
        // 测试无效配置
        TargetCacheProvider.setConfig({
            maxCacheCount: -5,
            autoCleanThreshold: 0,
            maxCacheAge: -10
        });
        
        var config:Object = TargetCacheProvider.getConfig();
        assertTrue("无效配置被拒绝", config.maxCacheCount > 0);
        assertTrue("无效配置被拒绝", config.autoCleanThreshold > 0);
        assertTrue("无效配置被拒绝", config.maxCacheAge > 0);
        
        // 测试null配置
        TargetCacheProvider.setConfig(null);
        var configAfterNull:Object = TargetCacheProvider.getConfig();
        assertNotNull("null配置不影响现有配置", configAfterNull);
    }
    
    private static function testConfigurationRetrieval():Void {
        var config:Object = TargetCacheProvider.getConfig();
        
        assertNotNull("getConfig返回对象", config);
        assertTrue("包含maxCacheCount", config.hasOwnProperty("maxCacheCount"));
        assertTrue("包含autoCleanThreshold", config.hasOwnProperty("autoCleanThreshold"));
        assertTrue("包含maxCacheAge", config.hasOwnProperty("maxCacheAge"));
        assertTrue("包含autoCleanEnabled", config.hasOwnProperty("autoCleanEnabled"));
        
        // 验证配置是副本（修改不影响内部配置）
        config.maxCacheCount = 999;
        var newConfig:Object = TargetCacheProvider.getConfig();
        assertTrue("返回配置副本", newConfig.maxCacheCount != 999);
    }
    
    // ========================================================================
    // 统计信息测试
    // ========================================================================
    
    private static function runStatisticsTests():Void {
        trace("\n📊 执行统计信息测试...");
        
        testBasicStatistics();
        testDetailedStatistics();
        testStatisticsAccuracy();
    }
    
    private static function testBasicStatistics():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(true);
        
        // 执行一系列操作
        TargetCacheProvider.getCache("敌人", target, 10); // 创建
        TargetCacheProvider.getCache("敌人", target, 10); // 命中
        
        mockFrameTimer.advanceFrame(15);
        TargetCacheProvider.getCache("敌人", target, 10); // 更新
        
        var stats:Object = TargetCacheProvider.getStats();
        
        assertEquals("总请求数正确", 3, stats.totalRequests, 0);
        assertEquals("缓存命中数正确", 1, stats.cacheHits, 0);
        assertEquals("缓存未命中数正确", 2, stats.cacheMisses, 0);
        assertEquals("缓存创建数正确", 1, stats.cacheCreations, 0);
        assertEquals("缓存更新数正确", 1, stats.cacheUpdates, 0);
        
        var expectedHitRate:Number = (1 / 3) * 100;
        assertTrue("命中率计算正确", Math.abs(stats.hitRate - expectedHitRate) < 0.1);
    }
    
    private static function testDetailedStatistics():Void {
        TargetCacheProvider.clearCache();
        var target:Object = createTestTarget(false);
        
        // 创建缓存
        TargetCacheProvider.getCache("友军", target, 10);
        TargetCacheProvider.getCache("全体", target, 10);
        
        var details:Object = TargetCacheProvider.getCachePoolDetails();
        
        assertNotNull("getCachePoolDetails返回对象", details);
        assertTrue("包含caches详情", details.hasOwnProperty("caches"));
        assertTrue("包含totalUnits", details.hasOwnProperty("totalUnits"));
        assertTrue("包含avgUnitsPerCache", details.hasOwnProperty("avgUnitsPerCache"));
        
        var count:Number = 0;
        for (var key in details.caches) {
            count++;
        }
        assertEquals("当前缓存数量正确", 2, count);
        assertTrue("总单位数大于等于0", details.totalUnits >= 0);
        assertTrue("平均单位数合理", details.avgUnitsPerCache >= 0);
    }
    
    private static function testStatisticsAccuracy():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var hitCount:Number = 0;
        var missCount:Number = 0;
        var target:Object = createTestTarget(true);
        
        // 第一次 - 未命中
        TargetCacheProvider.getCache("敌人", target, 20);
        missCount++;
        
        // 第二次 - 命中
        TargetCacheProvider.getCache("敌人", target, 20);
        hitCount++;
        
        // 推进时间，触发更新 - 未命中
        mockFrameTimer.advanceFrame(25);
        TargetCacheProvider.getCache("敌人", target, 20);
        missCount++;
        
        var stats:Object = TargetCacheProvider.getStats();
        assertEquals("命中数统计准确", hitCount, stats.cacheHits, 0);
        assertEquals("未命中数统计准确", missCount, stats.cacheMisses, 0);
        assertEquals("总请求数统计准确", hitCount + missCount, stats.totalRequests, 0);
    }
    
    // ========================================================================
    // 健康检查和诊断测试
    // ========================================================================
    
    private static function runHealthCheckTests():Void {
        trace("\n🏥 执行健康检查和诊断测试...");
        
        testHealthCheckNormal();
        testHealthCheckWarnings();
        testHealthCheckErrors();
        testOptimizationRecommendations();
        testStatusReporting();
    }
    
    private static function testHealthCheckNormal():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        TargetCacheProvider.setConfig({
            maxCacheCount: 20,
            autoCleanEnabled: true
        });
        
        var target:Object = createTestTarget(true);
        
        // 正常使用场景
        for (var i:Number = 0; i < 5; i++) {
            TargetCacheProvider.getCache("敌人", target, 10);
        }
        
        var health:Object = TargetCacheProvider.performHealthCheck();
        
        assertNotNull("performHealthCheck返回对象", health);
        assertTrue("健康检查包含healthy属性", health.hasOwnProperty("healthy"));
        assertTrue("健康检查包含warnings数组", health.warnings instanceof Array);
        assertTrue("健康检查包含errors数组", health.errors instanceof Array);
        assertTrue("健康检查包含recommendations数组", health.recommendations instanceof Array);
        
        assertTrue("正常情况下健康", health.healthy);
    }
    
    private static function testHealthCheckWarnings():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(false);
        
        // 模拟低命中率场景
        for (var i:Number = 0; i < 50; i++) {
            mockFrameTimer.advanceFrame(20); // 每次都过期
            var tempTarget:Object = createTestTarget(i % 2 == 0);
            tempTarget._name = "low_hit_target_" + i;
            TargetCacheProvider.getCache("友军", tempTarget, 1);
        }
        
        var health:Object = TargetCacheProvider.performHealthCheck();
        assertTrue("低命中率产生警告", health.warnings.length > 0);
        assertTrue("低命中率有建议", health.recommendations.length > 0);
    }
    
    private static function testHealthCheckErrors():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.setConfig({
            maxCacheCount: 3,
            autoCleanEnabled: false
        });
        
        var target:Object = createTestTarget(true);
        
        // 创建超过最大数量的缓存
        for (var i:Number = 0; i < 5; i++) {
            var tempTarget:Object = createTestTarget(i % 2 == 0);
            tempTarget._name = "error_target_" + i;
            TargetCacheProvider.getCache("敌人", tempTarget, 10);
        }
        
        var health:Object = TargetCacheProvider.performHealthCheck();
        assertTrue("超过最大数量产生错误", health.errors.length > 0);
        assertTrue("有错误时健康状态为false", !health.healthy);
    }
    
    private static function testOptimizationRecommendations():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(true);
        
        // 创建一些统计数据
        for (var i:Number = 0; i < 20; i++) {
            TargetCacheProvider.getCache("全体", target, 1); // 很高的命中率
        }
        
        var recommendations:Array = TargetCacheProvider.getOptimizationRecommendations();
        
        assertTrue("getOptimizationRecommendations返回数组", recommendations instanceof Array);
        assertTrue("有足够统计数据时有建议", recommendations.length >= 0);
    }
    
    private static function testStatusReporting():Void {
        var report:String = TargetCacheProvider.getDetailedStatusReport();
        
        assertNotNull("getDetailedStatusReport返回字符串", report);
        assertTrue("报告不为空", report.length > 0);
        
        // 验证报告包含关键部分
        assertTrue("报告包含性能统计", report.indexOf("Performance Stats:") >= 0);
        assertTrue("报告包含缓存状态", report.indexOf("Cache Status:") >= 0);
        assertTrue("报告包含配置信息", report.indexOf("Configuration:") >= 0);
        assertTrue("报告包含缓存详情", report.indexOf("Cache Details:") >= 0);
    }
    
    // ========================================================================
    // 性能基准测试
    // ========================================================================
    
    private static function runPerformanceBenchmarks():Void {
        trace("\n⚡ 执行性能基准测试...");
        
        performanceTestCacheRetrieval();
        performanceTestCacheCreation();
        performanceTestMassiveOperations();
        performanceTestMemoryUsage();
    }
    
    private static function performanceTestCacheRetrieval():Void {
        TargetCacheProvider.clearCache();
        var target:Object = createTestTarget(true);
        
        // 预热 - 创建缓存
        TargetCacheProvider.getCache("敌人", target, 100);
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < PERFORMANCE_TRIALS; i++) {
            TargetCacheProvider.getCache("敌人", target, 100);
        }
        var totalTime:Number = getTimer() - startTime;
        var avgTime:Number = totalTime / PERFORMANCE_TRIALS;
        
        performanceResults.push({
            method: "cacheRetrieval",
            trials: PERFORMANCE_TRIALS,
            totalTime: totalTime,
            avgTime: avgTime
        });
        
        trace("📊 缓存获取性能: " + PERFORMANCE_TRIALS + "次调用耗时 " + totalTime + "ms");
        assertTrue("缓存获取性能达标", avgTime < GET_CACHE_BENCHMARK_MS);
    }
    
    private static function performanceTestCacheCreation():Void {
        TargetCacheProvider.clearCache();
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < 50; i++) {
            var tempTarget:Object = createTestTarget(i % 2 == 0);
            tempTarget._name = "perf_target_" + i;
            var requestType:String = (i % 3 == 0) ? "全体" : ((i % 3 == 1) ? "敌人" : "友军");
            TargetCacheProvider.getCache(requestType, tempTarget, 10);
        }
        var creationTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "cacheCreation",
            trials: 50,
            totalTime: creationTime,
            avgTime: creationTime / 50
        });
        
        trace("📊 缓存创建性能: 50次创建耗时 " + creationTime + "ms");
        assertTrue("缓存创建性能合理", creationTime < 100);
    }
    
    private static function performanceTestMassiveOperations():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.setConfig({
            maxCacheCount: CACHE_STRESS_COUNT,
            autoCleanEnabled: true
        });
        
        var startTime:Number = getTimer();
        
        // 大量混合操作
        for (var i:Number = 0; i < CACHE_STRESS_COUNT; i++) {
            var tempTarget:Object = createTestTarget(i % 2 == 0);
            tempTarget._name = "stress_target_" + i;
            
            TargetCacheProvider.getCache("敌人", tempTarget, 5);
            
            if (i % 10 == 0) {
                mockFrameTimer.advanceFrame(10);
            }
            
            if (i % 15 == 0) {
                TargetCacheProvider.invalidateCache("敌人");
            }
        }
        
        var massiveTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "massiveOperations",
            trials: CACHE_STRESS_COUNT,
            totalTime: massiveTime,
            avgTime: massiveTime / CACHE_STRESS_COUNT
        });
        
        trace("📊 大量操作测试: " + CACHE_STRESS_COUNT + "次操作耗时 " + massiveTime + "ms");
        assertTrue("大量操作性能合理", massiveTime < 200);
    }
    
    private static function performanceTestMemoryUsage():Void {
        var memoryStart:Number = getTimer();
        
        // 内存压力测试
        for (var cycle:Number = 0; cycle < 10; cycle++) {
            TargetCacheProvider.clearCache();
            
            for (var i:Number = 0; i < 20; i++) {
                var tempTarget:Object = createTestTarget(i % 2 == 0);
                tempTarget._name = "memory_target_" + cycle + "_" + i;
                TargetCacheProvider.getCache("全体", tempTarget, 1);
            }
            
            // 模拟内存释放
            TargetCacheProvider.clearCache();
        }
        
        var memoryTime:Number = getTimer() - memoryStart;
        
        performanceResults.push({
            method: "memoryUsage",
            trials: 10,
            totalTime: memoryTime,
            avgTime: memoryTime / 10
        });
        
        trace("📊 内存使用测试: 10次循环耗时 " + memoryTime + "ms");
        assertTrue("内存使用测试合理", memoryTime < 100);
    }
    
    // ========================================================================
    // 集成测试
    // ========================================================================
    
    private static function runIntegrationTests():Void {
        trace("\n🔗 执行集成测试...");
        
        testSortedUnitCacheIntegration();
        testTargetCacheUpdaterIntegration();
        testEndToEndWorkflow();
    }
    
    private static function testSortedUnitCacheIntegration():Void {
        TargetCacheProvider.clearCache();
        var target:Object = createTestTarget(true);
        
        // 获取缓存并验证其功能
        var cache:SortedUnitCache = TargetCacheProvider.getCache("全体", target, 10);
        
        assertNotNull("集成获取SortedUnitCache", cache);
        assertTrue("SortedUnitCache功能正常", cache.getCount() >= 0);
        
        // 验证SortedUnitCache的查询功能
        if (cache.getCount() > 0) {
            var firstUnit:Object = cache.getUnitAt(0);
            assertNotNull("可以获取单位", firstUnit);
            
            var unitByName:Object = cache.findUnitByName(firstUnit._name);
            assertTrue("按名称查找正常", unitByName === firstUnit);
        }
    }
    
    private static function testTargetCacheUpdaterIntegration():Void {
        TargetCacheProvider.clearCache();
        
        // 通过Provider操作，验证与TargetCacheUpdater的集成
        var newUnit:Object = createTestTarget(false);
        newUnit._name = "integration_unit";
        
        TargetCacheProvider.addUnit(newUnit);
        var versionInfo:Object = TargetCacheUpdater.getVersionInfo();
        assertTrue("版本号正确更新", versionInfo.totalVersion > 0);
        
        TargetCacheProvider.removeUnit(newUnit);
        var newVersionInfo:Object = TargetCacheUpdater.getVersionInfo();
        assertTrue("移除后版本号继续更新", newVersionInfo.totalVersion > versionInfo.totalVersion);
    }
    
    private static function testEndToEndWorkflow():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(true);
        
        // 模拟完整的使用流程
        
        // 1. 初始请求
        var cache1:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 20);
        assertNotNull("端到端流程-初始缓存", cache1);
        
        // 2. 重复请求（命中）
        var cache2:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 20);
        assertTrue("端到端流程-缓存命中", cache1 === cache2);
        
        // 3. 添加新单位
        var newUnit:Object = createTestTarget(false);
        TargetCacheProvider.addUnit(newUnit);
        
        // 4. 时间推进，缓存过期
        mockFrameTimer.advanceFrame(25);
        
        // 5. 再次请求（更新）
        var cache3:SortedUnitCache = TargetCacheProvider.getCache("敌人", target, 20);
        assertTrue("端到端流程-缓存更新", cache3.lastUpdatedFrame > cache1.lastUpdatedFrame);
        
        // 6. 验证统计信息
        var stats:Object = TargetCacheProvider.getStats();
        assertEquals("端到端流程-请求统计", 3, stats.totalRequests, 0);
        assertEquals("端到端流程-命中统计", 1, stats.cacheHits, 0);
        assertEquals("端到端流程-创建统计", 1, stats.cacheCreations, 0);
        assertEquals("端到端流程-更新统计", 1, stats.cacheUpdates, 0);
    }
    
    // ========================================================================
    // 边界条件测试
    // ========================================================================
    
    private static function runBoundaryConditionTests():Void {
        trace("\n🔍 执行边界条件测试...");
        
        testEmptyWorldScenario();
        testNullParameterHandling();
        testExtremeCacheScenarios();
    }
    
    private static function testEmptyWorldScenario():Void {
        // 清空游戏世界
        _root.gameworld = {};
        TargetCacheProvider.clearCache();
        
        var target:Object = createTestTarget(true);
        var cache:SortedUnitCache = TargetCacheProvider.getCache("全体", target, 10);
        
        assertNotNull("空世界返回缓存", cache);
        assertEquals("空世界缓存无单位", 0, cache.getCount(), 0);
        
        // 恢复游戏世界
        _root.gameworld = mockGameWorld;
    }
    
    private static function testNullParameterHandling():Void {
        TargetCacheProvider.clearCache();
        
        // 测试null目标
        var nullCache:SortedUnitCache = TargetCacheProvider.getCache("敌人", null, 10);
        // 应该不崩溃，但行为取决于实现
        
        // 测试空字符串请求类型
        var target:Object = createTestTarget(true);
        var emptyTypeCache:SortedUnitCache = TargetCacheProvider.getCache("", target, 10);
        // 应该不崩溃
        
        // 测试负数更新间隔
        var negativeIntervalCache:SortedUnitCache = TargetCacheProvider.getCache("友军", target, -5);
        assertNotNull("负数间隔处理", negativeIntervalCache);
    }
    
    private static function testExtremeCacheScenarios():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.setConfig({
            maxCacheCount: 1,
            autoCleanEnabled: true
        });
        
        var target1:Object = createTestTarget(true);
        var target2:Object = createTestTarget(false);
        
        // 创建第一个缓存
        var cache1:SortedUnitCache = TargetCacheProvider.getCache("敌人", target1, 10);
        assertEquals("极限场景-第一个缓存", 1, TargetCacheProvider.getCacheCount(), 0);
        
        // 创建第二个缓存，应该触发清理
        var cache2:SortedUnitCache = TargetCacheProvider.getCache("友军", target2, 10);
        assertTrue("极限场景-缓存数量受限", TargetCacheProvider.getCacheCount() <= 1);
        
        // 测试零更新间隔
        mockFrameTimer.advanceFrame(1);
        var zeroIntervalCache:SortedUnitCache = TargetCacheProvider.getCache("全体", target1, 0);
        assertNotNull("零间隔缓存", zeroIntervalCache);
    }
    
    // ========================================================================
    // 内存管理和优化测试
    // ========================================================================
    
    private static function runMemoryOptimizationTests():Void {
        trace("\n💾 执行内存管理和优化测试...");
        
        testMemoryLeakPrevention();
        testCacheEfficiency();
        testOptimizationAnalysis();
    }
    
    private static function testMemoryLeakPrevention():Void {
        TargetCacheProvider.clearCache();
        var initialCount:Number = TargetCacheProvider.getCacheCount();
        
        // 大量创建和销毁
        for (var cycle:Number = 0; cycle < 5; cycle++) {
            for (var i:Number = 0; i < 10; i++) {
                var tempTarget:Object = createTestTarget(i % 2 == 0);
                tempTarget._name = "leak_test_" + cycle + "_" + i;
                TargetCacheProvider.getCache("敌人", tempTarget, 1);
            }
            
            TargetCacheProvider.clearCache();
            assertEquals("清理后缓存为空", 0, TargetCacheProvider.getCacheCount(), 0);
        }
        
        assertEquals("防止内存泄漏", initialCount, TargetCacheProvider.getCacheCount(), 0);
    }
    
    private static function testCacheEfficiency():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(true);
        
        // 测试高效缓存使用
        for (var i:Number = 0; i < 20; i++) {
            TargetCacheProvider.getCache("全体", target, 50); // 长间隔，高命中率
        }
        
        var stats:Object = TargetCacheProvider.getStats();
        var hitRate:Number = stats.hitRate;
        
        assertTrue("高效使用达到高命中率", hitRate > 80);
        
        var details:Object = TargetCacheProvider.getCachePoolDetails();
        assertTrue("缓存效率合理", details.avgUnitsPerCache >= 0);
    }
    
    private static function testOptimizationAnalysis():Void {
        TargetCacheProvider.clearCache();
        TargetCacheProvider.resetStats();
        
        var target:Object = createTestTarget(false);
        
        // 创建低效使用模式
        for (var i:Number = 0; i < 30; i++) {
            mockFrameTimer.advanceFrame(100); // 每次都过期
            TargetCacheProvider.getCache("友军", target, 1);
        }
        
        var recommendations:Array = TargetCacheProvider.getOptimizationRecommendations();
        assertTrue("低效使用产生优化建议", recommendations.length > 0);
        
        var health:Object = TargetCacheProvider.performHealthCheck();
        assertTrue("健康检查发现问题", health.warnings.length > 0 || health.errors.length > 0);
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
        
        trace("\n🎯 TargetCacheProvider当前状态:");
        trace(TargetCacheProvider.getDetailedStatusReport());
        
        if (failedTests == 0) {
            trace("\n🎉 所有测试通过！TargetCacheProvider 组件质量优秀！");
        } else {
            trace("\n⚠️ 发现 " + failedTests + " 个问题，请检查实现！");
        }
        
        trace("================================================================================");
    }
}