import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater;
import org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizer;

/**
 * 完整测试套件：TargetCacheUpdater
 * ================================
 * 特性：
 * - 100% 方法覆盖率测试（包括私有方法逻辑验证）
 * - 缓存管理核心逻辑验证
 * - 版本控制系统测试
 * - AdaptiveThresholdOptimizer集成测试
 * - 性能基准测试（大数据集处理）
 * - 缓存池管理验证
 * - 状态监控和自检测试
 * - 复杂场景模拟（批量操作、阵营切换）
 * - 边界条件与极值测试
 * - 一句启动设计
 * 
 * 使用方法：
 * org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdaterTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdaterTest {
    
    // ========================================================================
    // 测试统计和配置
    // ========================================================================
    
    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var performanceResults:Array = [];
    
    // 性能基准配置
    private static var PERFORMANCE_TRIALS:Number = 100;
    private static var STRESS_UNIT_COUNT:Number = 500;
    private static var UPDATE_BENCHMARK_MS:Number = 5.0; // 单次更新不超过5ms
    
    // 测试数据缓存
    private static var mockGameWorld:Object;
    private static var testUnits:Array;
    private static var testCacheEntry:Object;
    
    /**
     * 主测试入口 - 一句启动全部测试
     */
    public static function runAll():Void {
        trace("================================================================================");
        trace("🚀 TargetCacheUpdater 完整测试套件启动");
        trace("================================================================================");
        
        var startTime:Number = getTimer();
        resetTestStats();
        
        try {
            // 初始化测试环境
            initializeTestEnvironment();
            
            // === 基础功能测试 ===
            runBasicFunctionalityTests();
            
            // === 核心更新逻辑测试 ===
            runCoreUpdateLogicTests();
            
            // === 版本控制系统测试 ===
            runVersionControlTests();
            
            // === AdaptiveThresholdOptimizer集成测试 ===
            runThresholdOptimizerIntegrationTests();
            
            // === 缓存池管理测试 ===
            runCachePoolManagementTests();
            
            // === 批量操作测试 ===
            runBatchOperationTests();
            
            // === 性能基准测试 ===
            runPerformanceBenchmarks();
            
            // === 调试监控测试 ===
            runDebugMonitoringTests();
            
            // === 边界条件测试 ===
            runBoundaryConditionTests();
            
            // === 注册表系统测试 ===
            runRegistryTests();

            // === 校验重排（Reconciliation）测试 ===
            runReconciliationTests();

            // === 复杂场景集成测试 ===
            runComplexScenarioTests();
            
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
    // 测试环境初始化
    // ========================================================================
    
    private static function initializeTestEnvironment():Void {
        trace("\n🔧 初始化测试环境...");
        
        // 重置TargetCacheUpdater状态
        TargetCacheUpdater.resetVersions();
        
        // 创建测试单位和游戏世界
        testUnits = createTestUnits(50);
        mockGameWorld = createMockGameWorld(testUnits);
        testCacheEntry = createTestCacheEntry();
        
        trace("📦 创建了 " + testUnits.length + " 个测试单位");
        trace("🌍 构建了模拟游戏世界");
    }
    
    /**
     * 创建测试单位
     */
    private static function createTestUnits(count:Number):Array {
        var units:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var isEnemy:Boolean = (i % 2 == 0); // 交替设置敌友
            var unit:Object = {
                _name: "unit_" + i,
                hp: 80 + Math.random() * 40, // 80-120血量
                maxhp: 100,
                是否为敌人: isEnemy,
                aabbCollider: {
                    left: i * 25 + Math.random() * 10,
                    right: 0,
                    updateFromUnitArea: function(u:Object):Void {
                        // 模拟碰撞器更新
                        this.left = i * 25 + Math.random() * 5;
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
     * 创建测试缓存条目
     */
    private static function createTestCacheEntry():Object {
        return {
            data: [],
            nameIndex: {},
            rightValues: [],
            leftValues: [],
            lastUpdatedFrame: 0
        };
    }
    
    /**
     * 创建特殊场景的单位
     */
    private static function createSpecialUnits(scenario:String, count:Number):Array {
        var units:Array = [];
        
        for (var i:Number = 0; i < count; i++) {
            var isEnemy:Boolean;
            var hp:Number = 100;
            
            switch (scenario) {
                case "all_enemies":
                    isEnemy = true;
                    break;
                case "all_allies":
                    isEnemy = false;
                    break;
                case "mixed_hp":
                    isEnemy = (i % 2 == 0);
                    hp = (i % 3 == 0) ? 0 : (50 + Math.random() * 50); // 1/3概率死亡
                    break;
                case "clustered":
                    isEnemy = (i < count / 2);
                    break;
                default:
                    isEnemy = (i % 2 == 0);
            }
            
            var unit:Object = {
                _name: scenario + "_unit_" + i,
                hp: hp,
                maxhp: 100,
                是否为敌人: isEnemy,
                aabbCollider: {
                    left: i * 10,
                    right: i * 10 + 15,
                    updateFromUnitArea: function(u:Object):Void {
                        // 模拟更新
                    }
                }
            };
            
            units[i] = unit;
        }
        
        return units;
    }
    
    // ========================================================================
    // 基础功能测试
    // ========================================================================
    
    private static function runBasicFunctionalityTests():Void {
        trace("\n📋 执行基础功能测试...");
        
        testVersionInfoAccess();
        testThresholdAccess();
        testBasicUnitOperations();
    }
    
    private static function testVersionInfoAccess():Void {
        // 测试版本信息获取
        var versionInfo:Object = TargetCacheUpdater.getVersionInfo();
        assertNotNull("getVersionInfo返回对象", versionInfo);
        assertTrue("版本信息包含enemyVersion", versionInfo.hasOwnProperty("enemyVersion"));
        assertTrue("版本信息包含allyVersion", versionInfo.hasOwnProperty("allyVersion"));
        assertTrue("版本信息包含totalVersion", versionInfo.hasOwnProperty("totalVersion"));
        
        assertEquals("初始enemyVersion为0", 0, versionInfo.enemyVersion, 0);
        assertEquals("初始allyVersion为0", 0, versionInfo.allyVersion, 0);
        assertEquals("初始totalVersion为0", 0, versionInfo.totalVersion, 0);
    }
    
    private static function testThresholdAccess():Void {
        // 测试阈值访问
        var threshold:Number = TargetCacheUpdater.getCurrentThreshold();
        assertTrue("getCurrentThreshold返回有效值", threshold > 0);
        
        var thresholdStatus:Object = TargetCacheUpdater.getThresholdStatus();
        assertNotNull("getThresholdStatus返回对象", thresholdStatus);
        
        // 测试静态访问器
        var staticThreshold:Number = TargetCacheUpdater._THRESHOLD;
        assertEquals("静态访问器与方法一致", threshold, staticThreshold, 0.1);
    }
    
    private static function testBasicUnitOperations():Void {
        // 测试单个单位添加
        var enemyUnit:Object = testUnits[0]; // 第一个单位是敌人
        var allyUnit:Object = testUnits[1];  // 第二个单位是友军
        
        TargetCacheUpdater.addUnit(enemyUnit);
        var versionAfterEnemyAdd:Object = TargetCacheUpdater.getVersionInfo();
        assertEquals("添加敌人后enemyVersion递增", 1, versionAfterEnemyAdd.enemyVersion, 0);
        assertEquals("添加敌人后allyVersion不变", 0, versionAfterEnemyAdd.allyVersion, 0);
        
        TargetCacheUpdater.addUnit(allyUnit);
        var versionAfterAllyAdd:Object = TargetCacheUpdater.getVersionInfo();
        assertEquals("添加友军后allyVersion递增", 1, versionAfterAllyAdd.allyVersion, 0);
        
        // 测试单个单位移除
        TargetCacheUpdater.removeUnit(enemyUnit);
        var versionAfterEnemyRemove:Object = TargetCacheUpdater.getVersionInfo();
        assertEquals("移除敌人后enemyVersion再次递增", 2, versionAfterEnemyRemove.enemyVersion, 0);
        
        // 重置版本以避免影响后续测试
        TargetCacheUpdater.resetVersions();
    }
    
    // ========================================================================
    // 核心更新逻辑测试
    // ========================================================================
    
    private static function runCoreUpdateLogicTests():Void {
        trace("\n🔍 执行核心更新逻辑测试...");
        
        testEnemyRequestUpdate();
        testAllyRequestUpdate();
        testAllRequestUpdate();
        testCacheVersioning();
        testUpdateDataStructures();
    }
    
    private static function testEnemyRequestUpdate():Void {
        // 测试敌人请求更新
        var enemyRequester:Object = testUnits[0]; // 敌人请求者
        
        TargetCacheUpdater.updateCache(
            mockGameWorld,
            100,
            "敌人",
            enemyRequester.是否为敌人,
            testCacheEntry
        );
        
        assertNotNull("敌人请求后data不为空", testCacheEntry.data);
        assertNotNull("敌人请求后nameIndex不为空", testCacheEntry.nameIndex);
        assertNotNull("敌人请求后leftValues不为空", testCacheEntry.leftValues);
        assertNotNull("敌人请求后rightValues不为空", testCacheEntry.rightValues);
        assertEquals("敌人请求后帧数正确", 100, testCacheEntry.lastUpdatedFrame, 0);
        
        // 验证只包含友军单位
        var data:Array = testCacheEntry.data;
        for (var i:Number = 0; i < data.length; i++) {
            assertTrue("敌人请求结果只包含友军", !data[i].是否为敌人);
            assertTrue("结果中单位血量大于0", data[i].hp > 0);
        }
        
        // 验证数组长度一致性
        assertEquals("data与leftValues长度一致", data.length, testCacheEntry.leftValues.length, 0);
        assertEquals("data与rightValues长度一致", data.length, testCacheEntry.rightValues.length, 0);
    }
    
    private static function testAllyRequestUpdate():Void {
        // 测试友军请求更新
        var enemyRequester:Object = testUnits[0]; // 敌人请求者
        
        TargetCacheUpdater.updateCache(
            mockGameWorld,
            200,
            "友军",
            enemyRequester.是否为敌人,
            testCacheEntry
        );
        
        // 验证只包含敌军单位
        var data:Array = testCacheEntry.data;
        for (var i:Number = 0; i < data.length; i++) {
            assertTrue("友军请求结果只包含敌军", data[i].是否为敌人);
        }
        
        assertEquals("友军请求后帧数正确", 200, testCacheEntry.lastUpdatedFrame, 0);
    }
    
    private static function testAllRequestUpdate():Void {
        // 测试全体请求更新
        TargetCacheUpdater.updateCache(
            mockGameWorld,
            300,
            "全体",
            true,
            testCacheEntry
        );
        
        var data:Array = testCacheEntry.data;
        assertTrue("全体请求返回多个单位", data.length > 1);
        
        // 验证包含敌友双方
        var hasEnemy:Boolean = false;
        var hasAlly:Boolean = false;
        for (var i:Number = 0; i < data.length; i++) {
            if (data[i].是否为敌人) hasEnemy = true;
            else hasAlly = true;
        }
        assertTrue("全体请求包含敌军", hasEnemy);
        assertTrue("全体请求包含友军", hasAlly);
        
        assertEquals("全体请求后帧数正确", 300, testCacheEntry.lastUpdatedFrame, 0);
    }
    
    private static function testCacheVersioning():Void {
        // 测试缓存版本控制逻辑
        var initialFrame:Number = testCacheEntry.lastUpdatedFrame;
        
        // 第一次更新
        TargetCacheUpdater.updateCache(
            mockGameWorld,
            400,
            "敌人",
            true,
            testCacheEntry
        );
        
        var firstUpdateFrame:Number = testCacheEntry.lastUpdatedFrame;
        assertTrue("首次更新后帧数改变", firstUpdateFrame > initialFrame);
        
        // 不改变单位，再次更新（应该使用缓存）
        TargetCacheUpdater.updateCache(
            mockGameWorld,
            500,
            "敌人",
            true,
            testCacheEntry
        );
        
        assertEquals("缓存命中时仍更新帧数", 500, testCacheEntry.lastUpdatedFrame, 0);
        
        // 添加新单位，触发版本更新
        var newUnit:Object = createTestUnits(1)[0];
        newUnit.是否为敌人 = false;
        mockGameWorld["new_unit"] = newUnit;
        TargetCacheUpdater.addUnit(newUnit);
        
        TargetCacheUpdater.updateCache(
            mockGameWorld,
            600,
            "敌人",
            true,
            testCacheEntry
        );
        
        // 应该重新收集单位
        assertEquals("版本更新后重新收集", 600, testCacheEntry.lastUpdatedFrame, 0);
        
        // 清理
        delete mockGameWorld["new_unit"];
    }
    
    private static function testUpdateDataStructures():Void {
        TargetCacheUpdater.updateCache(
            mockGameWorld,
            700,
            "全体",
            true,
            testCacheEntry
        );
        
        var data:Array = testCacheEntry.data;
        var nameIndex:Object = testCacheEntry.nameIndex;
        var leftValues:Array = testCacheEntry.leftValues;
        var rightValues:Array = testCacheEntry.rightValues;
        
        // 验证排序
        for (var i:Number = 1; i < leftValues.length; i++) {
            assertTrue("leftValues按升序排列", leftValues[i] >= leftValues[i-1]);
        }
        
        // 验证nameIndex正确性
        for (var j:Number = 0; j < data.length; j++) {
            var unit:Object = data[j];
            var indexedPosition:Number = nameIndex[unit._name];
            assertEquals("nameIndex映射正确", j, indexedPosition, 0);
        }
        
        // 验证坐标值一致性
        for (var k:Number = 0; k < data.length; k++) {
            var unitK:Object = data[k];
            assertEquals("leftValues与实际坐标一致", unitK.aabbCollider.left, leftValues[k], 0.1);
            assertEquals("rightValues与实际坐标一致", unitK.aabbCollider.right, rightValues[k], 0.1);
        }
    }
    
    // ========================================================================
    // 版本控制系统测试
    // ========================================================================
    
    private static function runVersionControlTests():Void {
        trace("\n📊 执行版本控制系统测试...");

        testSingleUnitVersioning();
        testVersionReset();
        testVersionConsistency();
        testGetVersionForRequest();
    }
    
    private static function testSingleUnitVersioning():Void {
        TargetCacheUpdater.resetVersions();
        
        var enemyUnit:Object = createSpecialUnits("all_enemies", 1)[0];
        var allyUnit:Object = createSpecialUnits("all_allies", 1)[0];
        
        // 测试敌人单位操作
        TargetCacheUpdater.addUnit(enemyUnit);
        var v1:Object = TargetCacheUpdater.getVersionInfo();
        assertEquals("添加敌人版本递增", 1, v1.enemyVersion, 0);
        assertEquals("添加敌人友军版本不变", 0, v1.allyVersion, 0);
        
        TargetCacheUpdater.removeUnit(enemyUnit);
        var v2:Object = TargetCacheUpdater.getVersionInfo();
        assertEquals("移除敌人版本再次递增", 2, v2.enemyVersion, 0);
        
        // 测试友军单位操作
        TargetCacheUpdater.addUnit(allyUnit);
        var v3:Object = TargetCacheUpdater.getVersionInfo();
        assertEquals("添加友军版本递增", 1, v3.allyVersion, 0);
        assertEquals("添加友军敌人版本不变", 2, v3.enemyVersion, 0);
        
        TargetCacheUpdater.removeUnit(allyUnit);
        var v4:Object = TargetCacheUpdater.getVersionInfo();
        assertEquals("移除友军版本递增", 2, v4.allyVersion, 0);
        assertEquals("总版本正确", 4, v4.totalVersion, 0);
    }
    
    private static function testVersionReset():Void {
        // 确保有一些版本号
        var testUnit:Object = createTestUnits(1)[0];
        TargetCacheUpdater.addUnit(testUnit);
        
        var beforeReset:Object = TargetCacheUpdater.getVersionInfo();
        assertTrue("重置前有版本号", beforeReset.totalVersion > 0);
        
        // 测试重置
        TargetCacheUpdater.resetVersions();
        var afterReset:Object = TargetCacheUpdater.getVersionInfo();
        
        assertEquals("重置后enemyVersion为0", 0, afterReset.enemyVersion, 0);
        assertEquals("重置后allyVersion为0", 0, afterReset.allyVersion, 0);
        assertEquals("重置后totalVersion为0", 0, afterReset.totalVersion, 0);
    }
    
    private static function testVersionConsistency():Void {
        TargetCacheUpdater.resetVersions();
        
        // 执行一系列操作
        var units:Array = createTestUnits(10);
        for (var i:Number = 0; i < units.length; i++) {
            TargetCacheUpdater.addUnit(units[i]);
        }
        
        var versionInfo:Object = TargetCacheUpdater.getVersionInfo();
        var expectedTotal:Number = versionInfo.enemyVersion + versionInfo.allyVersion;
        
        assertEquals("totalVersion计算正确", expectedTotal, versionInfo.totalVersion, 0);
        assertTrue("enemyVersion非负", versionInfo.enemyVersion >= 0);
        assertTrue("allyVersion非负", versionInfo.allyVersion >= 0);
    }

    /**
     * 测试 getVersionForRequest —— 精细化版本号隔离
     * 验证敌人阵营变化不影响友军版本号，反之亦然
     */
    private static function testGetVersionForRequest():Void {
        TargetCacheUpdater.resetVersions();

        // 初始状态：所有版本为 0
        var v_enemy_P:Number = TargetCacheUpdater.getVersionForRequest("敌人", "PLAYER");
        var v_ally_P:Number = TargetCacheUpdater.getVersionForRequest("友军", "PLAYER");
        var v_all_P:Number = TargetCacheUpdater.getVersionForRequest("全体", "PLAYER");
        assertEquals("初始敌人版本=0", 0, v_enemy_P, 0);
        assertEquals("初始友军版本=0", 0, v_ally_P, 0);
        assertEquals("初始全体版本=0", 0, v_all_P, 0);

        // 添加一个敌方单位 → 只有敌人版本和全体版本应变化
        var enemyUnit:Object = createSpecialUnits("all_enemies", 1)[0];
        TargetCacheUpdater.addUnit(enemyUnit);

        var v_enemy_after:Number = TargetCacheUpdater.getVersionForRequest("敌人", "PLAYER");
        var v_ally_after:Number = TargetCacheUpdater.getVersionForRequest("友军", "PLAYER");
        var v_all_after:Number = TargetCacheUpdater.getVersionForRequest("全体", "PLAYER");

        assertTrue("添加敌人后敌人版本递增", v_enemy_after > v_enemy_P);
        assertEquals("添加敌人后友军版本不变", v_ally_P, v_ally_after, 0);
        assertTrue("添加敌人后全体版本递增", v_all_after > v_all_P);

        // 添加一个友方单位 → 只有友军版本和全体版本应变化
        var allyUnit:Object = createSpecialUnits("all_allies", 1)[0];
        TargetCacheUpdater.addUnit(allyUnit);

        var v_enemy_final:Number = TargetCacheUpdater.getVersionForRequest("敌人", "PLAYER");
        var v_ally_final:Number = TargetCacheUpdater.getVersionForRequest("友军", "PLAYER");
        var v_all_final:Number = TargetCacheUpdater.getVersionForRequest("全体", "PLAYER");

        assertEquals("添加友军后敌人版本不变", v_enemy_after, v_enemy_final, 0);
        assertTrue("添加友军后友军版本递增", v_ally_final > v_ally_after);
        assertTrue("添加友军后全体版本递增", v_all_final > v_all_after);

        // 全体版本 = 所有阵营版本之和
        assertTrue("全体版本>=敌人版本", v_all_final >= v_enemy_final);
        assertTrue("全体版本>=友军版本", v_all_final >= v_ally_final);

        TargetCacheUpdater.resetVersions();
    }

    // ========================================================================
    // AdaptiveThresholdOptimizer集成测试
    // ========================================================================
    
    private static function runThresholdOptimizerIntegrationTests():Void {
        trace("\n⚙️ 执行AdaptiveThresholdOptimizer集成测试...");
        
        testThresholdParameterSetting();
        testThresholdPresets();
        testThresholdStatusReporting();
        testThresholdUpdateIntegration();
    }
    
    private static function testThresholdParameterSetting():Void {
        // 测试参数设置方法
        var originalThreshold:Number = TargetCacheUpdater.getCurrentThreshold();
        
        TargetCacheUpdater.setAdaptiveParams(0.3, 2.5, 10, 500);
        
        // 验证参数设置生效（通过状态检查）
        var status:Object = TargetCacheUpdater.getThresholdStatus();
        assertNotNull("参数设置后状态可获取", status);
        
        // 恢复默认参数
        TargetCacheUpdater.applyThresholdPreset("default");
    }
    
    private static function testThresholdPresets():Void {
        // 测试预设应用
        var presets:Array = ["dense", "sparse", "dynamic", "stable", "default"];
        
        for (var i:Number = 0; i < presets.length; i++) {
            var presetName:String = presets[i];
            var success:Boolean = TargetCacheUpdater.applyThresholdPreset(presetName);
            assertTrue("预设\"" + presetName + "\"应用成功", success);
            
            var threshold:Number = TargetCacheUpdater.getCurrentThreshold();
            assertTrue("预设\"" + presetName + "\"阈值有效", threshold > 0);
        }
        
        // 测试无效预设
        var invalidSuccess:Boolean = TargetCacheUpdater.applyThresholdPreset("invalid_preset");
        assertTrue("无效预设应该失败", !invalidSuccess);
    }
    
    private static function testThresholdStatusReporting():Void {
        var status:Object = TargetCacheUpdater.getThresholdStatus();
        assertNotNull("getThresholdStatus返回对象", status);
        
        // 验证状态对象包含必要信息
        assertTrue("状态包含currentThreshold", status.hasOwnProperty("currentThreshold"));
        assertTrue("currentThreshold为有效数值", status.currentThreshold > 0);
    }
    
    private static function testThresholdUpdateIntegration():Void {
        // 测试更新缓存时阈值优化的集成
        var beforeThreshold:Number = TargetCacheUpdater.getCurrentThreshold();
        
        TargetCacheUpdater.updateCache(
            mockGameWorld,
            800,
            "全体",
            true,
            testCacheEntry
        );
        
        var afterThreshold:Number = TargetCacheUpdater.getCurrentThreshold();
        
        // 阈值应该被分析和可能更新
        assertTrue("更新后阈值仍为有效值", afterThreshold > 0);
        
        // 验证leftValues确实被传递给优化器进行分析
        assertNotNull("leftValues生成成功", testCacheEntry.leftValues);
        assertTrue("leftValues非空", testCacheEntry.leftValues.length > 0);
    }
    
    // ========================================================================
    // 缓存池管理测试
    // ========================================================================
    
    private static function runCachePoolManagementTests():Void {
        trace("\n🏊 执行缓存池管理测试...");
        
        testCachePoolStats();
        testCachePoolClearing();
        testCachePoolGrowth();
    }
    
    private static function testCachePoolStats():Void {
        TargetCacheUpdater.resetVersions(); // 清空缓存池
        
        var initialStats:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("初始缓存池数量为0", 0, initialStats.totalPools, 0);
        assertEquals("初始内存使用为0", 0, initialStats.memoryUsage, 0);
        
        // 触发一些缓存创建
        TargetCacheUpdater.updateCache(mockGameWorld, 900, "敌人", true, testCacheEntry);
        TargetCacheUpdater.updateCache(mockGameWorld, 901, "友军", true, testCacheEntry);
        TargetCacheUpdater.updateCache(mockGameWorld, 902, "全体", true, testCacheEntry);
        
        var afterStats:Object = TargetCacheUpdater.getCachePoolStats();
        assertTrue("创建缓存后池数量增加", afterStats.totalPools > initialStats.totalPools);
        assertTrue("创建缓存后内存使用增加", afterStats.memoryUsage > initialStats.memoryUsage);
        
        assertNotNull("缓存池详情不为空", afterStats.poolDetails);
        assertTrue("缓存池详情为对象", typeof(afterStats.poolDetails) == "object");
    }
    
    private static function testCachePoolClearing():Void {
        // 先创建一些缓存
        TargetCacheUpdater.updateCache(mockGameWorld, 1000, "敌人", true, testCacheEntry);
        TargetCacheUpdater.updateCache(mockGameWorld, 1001, "友军", false, testCacheEntry);
        
        var beforeClear:Object = TargetCacheUpdater.getCachePoolStats();
        assertTrue("清理前有缓存池", beforeClear.totalPools > 0);
        
        // 测试清理特定类型
        TargetCacheUpdater.clearCachePool("敌人");
        var afterPartialClear:Object = TargetCacheUpdater.getCachePoolStats();
        assertTrue("部分清理后池数量减少", afterPartialClear.totalPools <= beforeClear.totalPools);
        
        // 测试清理所有
        TargetCacheUpdater.clearCachePool();
        var afterFullClear:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("全部清理后池数量为0", 0, afterFullClear.totalPools, 0);
    }
    
    private static function testCachePoolGrowth():Void {
        TargetCacheUpdater.resetVersions();
        
        var requestTypes:Array = ["敌人", "友军", "全体"];
        var factionTypes:Array = [true, false];
        
        // 创建多种类型的缓存
        for (var i:Number = 0; i < requestTypes.length; i++) {
            var requestType:String = requestTypes[i];
            if (requestType == "全体") {
                TargetCacheUpdater.updateCache(mockGameWorld, 1100 + i, requestType, true, testCacheEntry);
            } else {
                for (var j:Number = 0; j < factionTypes.length; j++) {
                    TargetCacheUpdater.updateCache(mockGameWorld, 1100 + i * 10 + j, requestType, factionTypes[j], testCacheEntry);
                }
            }
        }
        
        var finalStats:Object = TargetCacheUpdater.getCachePoolStats();
        assertTrue("多样化请求创建多个缓存池", finalStats.totalPools >= 3);
        
        // 验证每个缓存池都有合理的数据
        for (var poolKey:String in finalStats.poolDetails) {
            var poolDetail:Object = finalStats.poolDetails[poolKey];
            assertTrue("缓存池有单位数据", poolDetail.listLength >= 0);
            assertTrue("缓存池有版本号", poolDetail.version >= 0);
        }
    }
    
    // ========================================================================
    // 批量操作测试
    // ========================================================================
    
    private static function runBatchOperationTests():Void {
        trace("\n📦 执行批量操作测试...");
        
        testBatchAddUnits();
        testBatchRemoveUnits();
        testMixedBatchOperations();
    }
    
    private static function testBatchAddUnits():Void {
        TargetCacheUpdater.resetVersions();
        
        var mixedUnits:Array = createSpecialUnits("clustered", 20);
        var enemyCount:Number = 0;
        var allyCount:Number = 0;
        
        for (var i:Number = 0; i < mixedUnits.length; i++) {
            if (mixedUnits[i].是否为敌人) enemyCount++;
            else allyCount++;
        }
        
        TargetCacheUpdater.addUnits(mixedUnits);
        var versionInfo:Object = TargetCacheUpdater.getVersionInfo();
        
        assertEquals("批量添加敌人版本正确", enemyCount, versionInfo.enemyVersion, 0);
        assertEquals("批量添加友军版本正确", allyCount, versionInfo.allyVersion, 0);
        assertEquals("批量添加总版本正确", enemyCount + allyCount, versionInfo.totalVersion, 0);
    }
    
    private static function testBatchRemoveUnits():Void {
        TargetCacheUpdater.resetVersions();
        
        // 先添加一些单位
        var initialUnits:Array = createSpecialUnits("mixed_hp", 15);
        TargetCacheUpdater.addUnits(initialUnits);
        
        var afterAdd:Object = TargetCacheUpdater.getVersionInfo();
        var initialTotal:Number = afterAdd.totalVersion;
        
        // 移除部分单位
        var unitsToRemove:Array = initialUnits.slice(0, 10);
        var removeEnemyCount:Number = 0;
        var removeAllyCount:Number = 0;
        
        for (var i:Number = 0; i < unitsToRemove.length; i++) {
            if (unitsToRemove[i].是否为敌人) removeEnemyCount++;
            else removeAllyCount++;
        }
        
        TargetCacheUpdater.removeUnits(unitsToRemove);
        var afterRemove:Object = TargetCacheUpdater.getVersionInfo();
        
        assertEquals("批量移除敌人版本递增", afterAdd.enemyVersion + removeEnemyCount, afterRemove.enemyVersion, 0);
        assertEquals("批量移除友军版本递增", afterAdd.allyVersion + removeAllyCount, afterRemove.allyVersion, 0);
    }
    
    private static function testMixedBatchOperations():Void {
        TargetCacheUpdater.resetVersions();
        
        var allEnemies:Array = createSpecialUnits("all_enemies", 5);
        var allAllies:Array = createSpecialUnits("all_allies", 7);
        
        // 先添加敌人
        TargetCacheUpdater.addUnits(allEnemies);
        var v1:Object = TargetCacheUpdater.getVersionInfo();
        
        // 再添加友军
        TargetCacheUpdater.addUnits(allAllies);
        var v2:Object = TargetCacheUpdater.getVersionInfo();
        
        // 验证版本累加正确
        assertEquals("混合添加敌人版本", 5, v2.enemyVersion, 0);
        assertEquals("混合添加友军版本", 7, v2.allyVersion, 0);
        
        // 批量移除
        TargetCacheUpdater.removeUnits(allEnemies);
        TargetCacheUpdater.removeUnits(allAllies);
        var v3:Object = TargetCacheUpdater.getVersionInfo();
        
        assertEquals("混合移除后敌人版本", 10, v3.enemyVersion, 0);
        assertEquals("混合移除后友军版本", 14, v3.allyVersion, 0);
    }
    
    // ========================================================================
    // 性能基准测试
    // ========================================================================
    
    private static function runPerformanceBenchmarks():Void {
        trace("\n⚡ 执行性能基准测试...");

        performanceTestUpdateCache();
        performanceTestBatchOperations();
        performanceTestCachePoolOperations();
        performanceTestLargeDataset();
        performanceTestRegistryVsReconciliation();
    }
    
    private static function performanceTestUpdateCache():Void {
        var largeWorld:Object = createMockGameWorld(createTestUnits(STRESS_UNIT_COUNT));
        var cacheEntry:Object = createTestCacheEntry();
        var trials:Number = PERFORMANCE_TRIALS;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            var requestType:String = (i % 3 == 0) ? "全体" : ((i % 3 == 1) ? "敌人" : "友军");
            var isEnemy:Boolean = (i % 2 == 0);
            
            TargetCacheUpdater.updateCache(
                largeWorld,
                2000 + i,
                requestType,
                isEnemy,
                cacheEntry
            );
        }
        var totalTime:Number = getTimer() - startTime;
        var avgTime:Number = totalTime / trials;
        
        performanceResults.push({
            method: "updateCache",
            trials: trials,
            totalTime: totalTime,
            avgTime: avgTime
        });
        
        trace("📊 updateCache性能: " + trials + "次调用耗时 " + totalTime + "ms");
        assertTrue("updateCache性能达标", avgTime < UPDATE_BENCHMARK_MS);
    }
    
    private static function performanceTestBatchOperations():Void {
        var batchSize:Number = 100;
        var batchUnits:Array = createTestUnits(batchSize);
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < 50; i++) {
            TargetCacheUpdater.addUnits(batchUnits);
            TargetCacheUpdater.removeUnits(batchUnits);
        }
        var batchTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "batchOperations",
            trials: 100,
            totalTime: batchTime,
            avgTime: batchTime / 100
        });
        
        trace("📊 批量操作性能: 100次批量操作耗时 " + batchTime + "ms");
        assertTrue("批量操作性能合理", batchTime < 500);
    }
    
    private static function performanceTestCachePoolOperations():Void {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < 100; i++) {
            TargetCacheUpdater.getCachePoolStats();
            if (i % 10 == 0) {
                TargetCacheUpdater.clearCachePool();
            }
        }
        var poolTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "cachePoolOps",
            trials: 100,
            totalTime: poolTime,
            avgTime: poolTime / 100
        });
        
        trace("📊 缓存池操作性能: 100次操作耗时 " + poolTime + "ms");
        assertTrue("缓存池操作性能合理", poolTime < 50);
    }
    
    private static function performanceTestLargeDataset():Void {
        var massiveUnits:Array = createTestUnits(STRESS_UNIT_COUNT * 2);
        var massiveWorld:Object = createMockGameWorld(massiveUnits);
        var cacheEntry:Object = createTestCacheEntry();
        
        var startTime:Number = getTimer();
        TargetCacheUpdater.updateCache(
            massiveWorld,
            3000,
            "全体",
            true,
            cacheEntry
        );
        var massiveTime:Number = getTimer() - startTime;
        
        performanceResults.push({
            method: "largeDataset",
            trials: 1,
            totalTime: massiveTime,
            avgTime: massiveTime
        });
        
        trace("📊 大数据集测试: " + (STRESS_UNIT_COUNT * 2) + "个单位处理耗时 " + massiveTime + "ms");
        assertTrue("大数据集处理时间合理", massiveTime < 300);
        
        // 验证结果完整性
        assertTrue("大数据集结果非空", cacheEntry.data.length > 0);
        assertEquals("大数据集数组长度一致", cacheEntry.data.length, cacheEntry.leftValues.length, 0);
    }
    
    /**
     * 注册表路径 vs reconciliation 路径的性能对比
     * 验证注册表路径（常规收集）快于全量扫描（reconciliation 中的 gameWorld 遍历）
     */
    private static function performanceTestRegistryVsReconciliation():Void {
        TargetCacheUpdater.resetVersions();

        // 构建大规模世界：含大量非单位对象模拟真实 gameWorld
        var unitCount:Number = 100;
        var noiseCount:Number = 500; // 非单位对象（地图、效果、子弹等）
        var bigWorld:Object = {};

        var bigUnits:Array = createTestUnits(unitCount);
        for (var i:Number = 0; i < bigUnits.length; i++) {
            bigWorld[bigUnits[i]._name] = bigUnits[i];
            TargetCacheUpdater.addUnit(bigUnits[i]);
        }
        // 添加大量非单位对象（无 hp 属性）
        for (var j:Number = 0; j < noiseCount; j++) {
            bigWorld["noise_obj_" + j] = { _name: "noise_obj_" + j, type: "effect" };
        }

        var cacheEntry:Object = createTestCacheEntry();

        // 首次 updateCache 触发 reconciliation（全量扫描）
        var startReconcile:Number = getTimer();
        TargetCacheUpdater.updateCache(bigWorld, 17000, "全体", true, cacheEntry);
        var reconcileTime:Number = getTimer() - startReconcile;

        // 后续调用在 RECONCILE_INTERVAL 内，走注册表路径
        var trials:Number = 50;
        var startRegistry:Number = getTimer();
        for (var t:Number = 0; t < trials; t++) {
            // bump 版本以强制每次重新收集
            TargetCacheUpdater.addUnit(bigUnits[0]);
            TargetCacheUpdater.updateCache(bigWorld, 17001 + t, "全体", true, cacheEntry);
        }
        var registryTime:Number = getTimer() - startRegistry;
        var avgRegistryTime:Number = registryTime / trials;

        performanceResults.push({
            method: "registryCollection",
            trials: trials,
            totalTime: registryTime,
            avgTime: avgRegistryTime
        });

        trace("📊 注册表收集性能: " + trials + "次收集耗时 " + registryTime + "ms (avg " +
              Math.round(avgRegistryTime * 1000) / 1000 + "ms)");
        trace("📊 含" + noiseCount + "个噪声对象的世界, reconciliation耗时 " + reconcileTime + "ms");

        // 验证结果正确性
        assertEquals("大规模世界单位数正确", unitCount, cacheEntry.data.length, 0);
        assertTrue("注册表平均收集时间合理(<5ms)", avgRegistryTime < 5);
    }

    // ========================================================================
    // 调试监控测试
    // ========================================================================
    
    private static function runDebugMonitoringTests():Void {
        trace("\n🔍 执行调试监控测试...");
        
        testDetailedStatusReport();
        testSelfCheck();
        testStatusReportContent();
    }
    
    private static function testDetailedStatusReport():Void {
        var report:String = TargetCacheUpdater.getDetailedStatusReport();
        assertNotNull("getDetailedStatusReport返回字符串", report);
        assertTrue("报告不为空", report.length > 0);

        // 验证报告包含关键信息
        assertTrue("报告包含版本信息", report.indexOf("Version Numbers:") >= 0);
        assertTrue("报告包含缓存池信息", report.indexOf("Cache Pool Stats:") >= 0);
        assertTrue("报告包含阈值信息", report.indexOf("Threshold Optimizer:") >= 0);
        assertTrue("报告包含注册表信息", report.indexOf("Unit Registry:") >= 0);
        assertTrue("报告包含Reconcile帧信息", report.indexOf("Last Reconcile Frame:") >= 0);
        assertTrue("报告包含Reconcile间隔信息", report.indexOf("Reconcile Interval:") >= 0);
    }
    
    private static function testSelfCheck():Void {
        var checkResult:Object = TargetCacheUpdater.performSelfCheck();
        assertNotNull("performSelfCheck返回对象", checkResult);
        
        assertTrue("自检结果包含passed", checkResult.hasOwnProperty("passed"));
        assertTrue("自检结果包含errors", checkResult.hasOwnProperty("errors"));
        assertTrue("自检结果包含warnings", checkResult.hasOwnProperty("warnings"));
        assertTrue("自检结果包含performance", checkResult.hasOwnProperty("performance"));
        
        assertTrue("自检错误数组为数组", checkResult.errors instanceof Array);
        assertTrue("自检警告数组为数组", checkResult.warnings instanceof Array);
        assertNotNull("自检性能信息不为空", checkResult.performance);
        
        // 在正常情况下，自检应该通过
        assertTrue("正常情况下自检通过", checkResult.passed);
    }
    
    private static function testStatusReportContent():Void {
        // 先触发一些活动以产生有意义的状态
        TargetCacheUpdater.addUnit(testUnits[0]);
        TargetCacheUpdater.updateCache(mockGameWorld, 4000, "敌人", true, testCacheEntry);

        var report:String = TargetCacheUpdater.getDetailedStatusReport();

        // 验证具体内容
        assertTrue("报告提及Enemy Version", report.indexOf("ENEMY:") >= 0);
        assertTrue("报告提及Active Pools", report.indexOf("Active Pools:") >= 0);
        assertTrue("报告提及Current Threshold", report.indexOf("Current Threshold:") >= 0);
        assertTrue("报告提及Total Units", report.indexOf("Total Units:") >= 0);

        var selfCheck:Object = TargetCacheUpdater.performSelfCheck();
        assertTrue("自检包含缓存池数量", selfCheck.performance.hasOwnProperty("cachePoolCount"));
        assertTrue("自检包含当前阈值", selfCheck.performance.hasOwnProperty("currentThreshold"));
        assertTrue("自检包含registryCount", selfCheck.performance.hasOwnProperty("registryCount"));
        assertTrue("自检包含lastReconcileFrame", selfCheck.performance.hasOwnProperty("lastReconcileFrame"));
    }
    
    // ========================================================================
    // 边界条件测试
    // ========================================================================
    
    private static function runBoundaryConditionTests():Void {
        trace("\n🔍 执行边界条件测试...");
        
        testEmptyWorld();
        testSingleUnitWorld();
        testDeadUnitsFiltering();
        testExtremeCacheOperations();
    }
    
    private static function testEmptyWorld():Void {
        // 重置注册表，首次 updateCache 触发 reconciliation 扫描空世界 → 注册表清空
        TargetCacheUpdater.resetVersions();

        var emptyWorld:Object = {};
        var cacheEntry:Object = createTestCacheEntry();

        TargetCacheUpdater.updateCache(
            emptyWorld,
            5000,
            "全体",
            true,
            cacheEntry
        );
        
        assertEquals("空世界data长度为0", 0, cacheEntry.data.length, 0);
        assertEquals("空世界leftValues长度为0", 0, cacheEntry.leftValues.length, 0);
        assertEquals("空世界rightValues长度为0", 0, cacheEntry.rightValues.length, 0);
        assertEquals("空世界帧数正确", 5000, cacheEntry.lastUpdatedFrame, 0);
    }
    
    private static function testSingleUnitWorld():Void {
        var singleUnit:Object = createTestUnits(1)[0];
        var singleWorld:Object = {};
        singleWorld[singleUnit._name] = singleUnit;
        var cacheEntry:Object = createTestCacheEntry();
        
        // 重置版本号以确保缓存重新收集
        TargetCacheUpdater.resetVersions();
        // 添加单位以触发版本更新
        TargetCacheUpdater.addUnit(singleUnit);
        
        TargetCacheUpdater.updateCache(
            singleWorld,
            5100,
            "全体",
            true,
            cacheEntry
        );
        
        assertEquals("单单位世界data长度为1", 1, cacheEntry.data.length, 0);
        assertEquals("单单位世界leftValues长度为1", 1, cacheEntry.leftValues.length, 0);
        assertStringEquals("单单位世界nameIndex正确", singleUnit._name, cacheEntry.data[0]._name);
        assertEquals("单单位世界nameIndex映射正确", 0, cacheEntry.nameIndex[singleUnit._name], 0);
    }
    
    private static function testDeadUnitsFiltering():Void {
        var mixedHpUnits:Array = createSpecialUnits("mixed_hp", 20);
        var mixedWorld:Object = createMockGameWorld(mixedHpUnits);
        var cacheEntry:Object = createTestCacheEntry();
        
        // 重置版本号以确保缓存重新收集
        TargetCacheUpdater.resetVersions();
        // 添加所有单位以触发版本更新
        TargetCacheUpdater.addUnits(mixedHpUnits);
        
        TargetCacheUpdater.updateCache(
            mixedWorld,
            5200,
            "全体",
            true,
            cacheEntry
        );
        
        // 验证只包含活着的单位
        var data:Array = cacheEntry.data;
        for (var i:Number = 0; i < data.length; i++) {
            assertTrue("结果中单位血量大于0", data[i].hp > 0);
        }
        
        // 验证死亡单位被过滤
        var aliveCount:Number = 0;
        for (var j:Number = 0; j < mixedHpUnits.length; j++) {
            if (mixedHpUnits[j].hp > 0) aliveCount++;
        }
        assertEquals("存活单位数量正确", aliveCount, data.length, 0);
    }
    
    private static function testExtremeCacheOperations():Void {
        // 测试大量版本操作
        TargetCacheUpdater.resetVersions();
        for (var i:Number = 0; i < 1000; i++) {
            var unit:Object = createTestUnits(1)[0];
            unit.是否为敌人 = (i % 2 == 0);
            TargetCacheUpdater.addUnit(unit);
        }
        
        var extremeVersions:Object = TargetCacheUpdater.getVersionInfo();
        assertTrue("极端操作后版本号合理", extremeVersions.totalVersion == 1000);
        
        // 测试大量缓存池创建
        var testWorld:Object = createMockGameWorld(createTestUnits(50));
        var cacheEntry:Object = createTestCacheEntry();
        
        for (var j:Number = 0; j < 20; j++) {
            var reqType:String = (j % 3 == 0) ? "全体" : ((j % 3 == 1) ? "敌人" : "友军");
            var isEnemy:Boolean = (j % 2 == 0);
            TargetCacheUpdater.updateCache(testWorld, 6000 + j, reqType, isEnemy, cacheEntry);
        }
        
        var poolStats:Object = TargetCacheUpdater.getCachePoolStats();
        assertTrue("大量操作后缓存池合理", poolStats.totalPools <= 20);
    }
    
    // ========================================================================
    // 注册表系统测试
    // ========================================================================

    private static function runRegistryTests():Void {
        trace("\n📋 执行注册表系统测试...");

        testRegistryPopulationViaAddUnit();
        testRegistryRemoveUnit();
        testRegistryDuplicateRegistration();
        testRegistryFactionChangeDuringReAdd();
        testRegistryResetClears();
        testRegistryBatchAddRemove();
        testRegistrySelfCheckConsistency();
        testRegistryCollectionAccuracy();
        testDeadUnitFilteringFromRegistry();
    }

    /**
     * 添加单位后注册表统计应正确反映
     */
    private static function testRegistryPopulationViaAddUnit():Void {
        TargetCacheUpdater.resetVersions();

        var enemies:Array = createSpecialUnits("all_enemies", 5);
        var allies:Array = createSpecialUnits("all_allies", 3);

        for (var i:Number = 0; i < enemies.length; i++) {
            TargetCacheUpdater.addUnit(enemies[i]);
        }
        for (var j:Number = 0; j < allies.length; j++) {
            TargetCacheUpdater.addUnit(allies[j]);
        }

        var stats:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("注册表总数=8", 8, stats.registryCount, 0);
        assertTrue("注册表含ENEMY桶", stats.registryBuckets.hasOwnProperty("ENEMY"));
        assertTrue("注册表含PLAYER桶", stats.registryBuckets.hasOwnProperty("PLAYER"));
        assertEquals("ENEMY桶数量=5", 5, stats.registryBuckets["ENEMY"], 0);
        assertEquals("PLAYER桶数量=3", 3, stats.registryBuckets["PLAYER"], 0);
    }

    /**
     * removeUnit 后注册表统计应递减
     */
    private static function testRegistryRemoveUnit():Void {
        TargetCacheUpdater.resetVersions();

        var units:Array = createSpecialUnits("all_enemies", 4);
        for (var i:Number = 0; i < units.length; i++) {
            TargetCacheUpdater.addUnit(units[i]);
        }

        var statsBefore:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("移除前registryCount=4", 4, statsBefore.registryCount, 0);

        TargetCacheUpdater.removeUnit(units[0]);
        TargetCacheUpdater.removeUnit(units[1]);

        var statsAfter:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("移除2个后registryCount=2", 2, statsAfter.registryCount, 0);
        assertEquals("ENEMY桶减少到2", 2, statsAfter.registryBuckets["ENEMY"], 0);
    }

    /**
     * 同阵营重复注册（如 respawn）不应导致桶内重复条目
     */
    private static function testRegistryDuplicateRegistration():Void {
        TargetCacheUpdater.resetVersions();

        var unit:Object = createSpecialUnits("all_enemies", 1)[0];
        TargetCacheUpdater.addUnit(unit);
        TargetCacheUpdater.addUnit(unit); // 再次添加，同阵营

        var stats:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("重复注册后registryCount仍=1", 1, stats.registryCount, 0);
        assertEquals("重复注册后ENEMY桶仍=1", 1, stats.registryBuckets["ENEMY"], 0);

        // 版本应该 bump 两次（每次 addUnit 一次）
        var vi:Object = TargetCacheUpdater.getVersionInfo();
        assertEquals("重复注册版本bump=2", 2, vi.enemyVersion, 0);
    }

    /**
     * 单位阵营变更后重新 addUnit，应从旧桶移到新桶
     */
    private static function testRegistryFactionChangeDuringReAdd():Void {
        TargetCacheUpdater.resetVersions();

        var unit:Object = {
            _name: "faction_changer",
            hp: 100,
            maxhp: 100,
            是否为敌人: true,
            aabbCollider: {
                left: 50, right: 70,
                updateFromUnitArea: function(u:Object):Void {}
            }
        };

        // 以敌人身份注册
        TargetCacheUpdater.addUnit(unit);
        var s1:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("初始ENEMY桶=1", 1, s1.registryBuckets["ENEMY"], 0);

        // 变更阵营为友军
        unit.是否为敌人 = false;
        TargetCacheUpdater.addUnit(unit);

        var s2:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("变更后ENEMY桶=0", 0, s2.registryBuckets["ENEMY"], 0);
        assertEquals("变更后PLAYER桶=1", 1, s2.registryBuckets["PLAYER"], 0);
        assertEquals("变更后registryCount仍=1", 1, s2.registryCount, 0);
    }

    /**
     * resetVersions 应完全清空注册表
     */
    private static function testRegistryResetClears():Void {
        // 先填充一些数据
        var units:Array = createTestUnits(10);
        for (var i:Number = 0; i < units.length; i++) {
            TargetCacheUpdater.addUnit(units[i]);
        }

        var statsBefore:Object = TargetCacheUpdater.getCachePoolStats();
        assertTrue("重置前有注册表数据", statsBefore.registryCount > 0);

        TargetCacheUpdater.resetVersions();

        var statsAfter:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("重置后registryCount=0", 0, statsAfter.registryCount, 0);
        assertEquals("重置后lastReconcileFrame=-1", -1, statsAfter.lastReconcileFrame, 0);

        // 所有桶应为空
        for (var fid:String in statsAfter.registryBuckets) {
            assertEquals("重置后桶" + fid + "为空", 0, statsAfter.registryBuckets[fid], 0);
        }
    }

    /**
     * 批量 addUnits/removeUnits 后注册表统计正确
     */
    private static function testRegistryBatchAddRemove():Void {
        TargetCacheUpdater.resetVersions();

        var enemies:Array = createSpecialUnits("all_enemies", 6);
        var allies:Array = createSpecialUnits("all_allies", 4);
        var all:Array = enemies.concat(allies);

        TargetCacheUpdater.addUnits(all);

        var s1:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("批量添加后registryCount=10", 10, s1.registryCount, 0);
        assertEquals("批量添加后ENEMY桶=6", 6, s1.registryBuckets["ENEMY"], 0);
        assertEquals("批量添加后PLAYER桶=4", 4, s1.registryBuckets["PLAYER"], 0);

        // 批量移除敌人
        TargetCacheUpdater.removeUnits(enemies);

        var s2:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("批量移除敌人后registryCount=4", 4, s2.registryCount, 0);
        assertEquals("批量移除敌人后ENEMY桶=0", 0, s2.registryBuckets["ENEMY"], 0);
        assertEquals("批量移除敌人后PLAYER桶不变=4", 4, s2.registryBuckets["PLAYER"], 0);
    }

    /**
     * performSelfCheck 应报告注册表一致（无 warning）
     */
    private static function testRegistrySelfCheckConsistency():Void {
        TargetCacheUpdater.resetVersions();

        var units:Array = createTestUnits(20);
        for (var i:Number = 0; i < units.length; i++) {
            TargetCacheUpdater.addUnit(units[i]);
        }

        var check:Object = TargetCacheUpdater.performSelfCheck();
        assertTrue("自检通过（注册表一致）", check.passed);

        // 检查是否有注册表相关 warning
        var hasRegistryWarning:Boolean = false;
        for (var w:Number = 0; w < check.warnings.length; w++) {
            if (String(check.warnings[w]).indexOf("Registry") >= 0) {
                hasRegistryWarning = true;
            }
        }
        assertTrue("无注册表不一致警告", !hasRegistryWarning);

        // 验证自检包含注册表性能字段
        assertTrue("自检含registryCount", check.performance.hasOwnProperty("registryCount"));
        assertTrue("自检含lastReconcileFrame", check.performance.hasOwnProperty("lastReconcileFrame"));
        assertEquals("自检registryCount=20", 20, check.performance.registryCount, 0);
    }

    /**
     * 注册表收集路径的正确性：结果应与手动按阵营过滤一致
     */
    private static function testRegistryCollectionAccuracy():Void {
        TargetCacheUpdater.resetVersions();

        // 创建确定性测试数据
        var units:Array = [];
        for (var i:Number = 0; i < 20; i++) {
            var unit:Object = {
                _name: "acc_test_" + i,
                hp: 100,
                maxhp: 100,
                是否为敌人: (i % 2 == 0),
                aabbCollider: {
                    left: i * 30,
                    right: i * 30 + 20,
                    updateFromUnitArea: function(u:Object):Void {}
                }
            };
            units.push(unit);
        }

        var world:Object = {};
        for (var j:Number = 0; j < units.length; j++) {
            world[units[j]._name] = units[j];
            TargetCacheUpdater.addUnit(units[j]);
        }

        // 触发一次 updateCache 让 reconciliation 初始化完成
        var cacheEntry:Object = createTestCacheEntry();
        TargetCacheUpdater.updateCache(world, 10000, "全体", true, cacheEntry);

        // 手动计算期望的敌人数量（对于 ENEMY 请求者，敌人是 PLAYER 即 是否为敌人==false）
        var expectedAllyForEnemy:Number = 0;
        for (var k:Number = 0; k < units.length; k++) {
            if (units[k].是否为敌人 && units[k].hp > 0) expectedAllyForEnemy++;
        }

        // 请求敌人（请求者为PLAYER，即是否为敌人=false）
        var enemyCacheEntry:Object = createTestCacheEntry();
        TargetCacheUpdater.updateCache(world, 10001, "敌人", false, enemyCacheEntry);

        assertEquals(
            "注册表收集:敌人数量正确",
            expectedAllyForEnemy,
            enemyCacheEntry.data.length,
            0
        );

        // 验证排序正确性
        for (var m:Number = 1; m < enemyCacheEntry.leftValues.length; m++) {
            assertTrue(
                "注册表收集:敌人结果排序正确",
                enemyCacheEntry.leftValues[m] >= enemyCacheEntry.leftValues[m - 1]
            );
        }

        // 请求友军（请求者为PLAYER）
        var allyCacheEntry:Object = createTestCacheEntry();
        TargetCacheUpdater.updateCache(world, 10002, "友军", false, allyCacheEntry);

        var expectedAllyForPlayer:Number = 0;
        for (var n:Number = 0; n < units.length; n++) {
            if (!units[n].是否为敌人 && units[n].hp > 0) expectedAllyForPlayer++;
        }
        assertEquals(
            "注册表收集:友军数量正确",
            expectedAllyForPlayer,
            allyCacheEntry.data.length,
            0
        );

        // 全体 = 敌人 + 友军
        assertEquals(
            "注册表收集:全体=敌人+友军",
            cacheEntry.data.length,
            enemyCacheEntry.data.length + allyCacheEntry.data.length,
            0
        );
    }

    /**
     * 注册表中 hp<=0 的单位应在收集时被过滤（安全网）
     */
    private static function testDeadUnitFilteringFromRegistry():Void {
        TargetCacheUpdater.resetVersions();

        var units:Array = [];
        for (var i:Number = 0; i < 10; i++) {
            var unit:Object = {
                _name: "dead_filter_" + i,
                hp: 100,
                maxhp: 100,
                是否为敌人: true,
                aabbCollider: {
                    left: i * 20,
                    right: i * 20 + 15,
                    updateFromUnitArea: function(u:Object):Void {}
                }
            };
            units.push(unit);
        }

        var world:Object = {};
        for (var j:Number = 0; j < units.length; j++) {
            world[units[j]._name] = units[j];
            TargetCacheUpdater.addUnit(units[j]);
        }

        // 首次 updateCache 触发 reconciliation
        var cacheEntry:Object = createTestCacheEntry();
        TargetCacheUpdater.updateCache(world, 11000, "全体", true, cacheEntry);
        assertEquals("初始全部10个单位", 10, cacheEntry.data.length, 0);

        // 模拟3个单位死亡（hp=0）但不调用 removeUnit — 模拟漏删场景
        units[2].hp = 0;
        units[5].hp = 0;
        units[8].hp = 0;

        // bump 版本以强制重新收集
        TargetCacheUpdater.addUnit({
            _name: "version_bumper",
            hp: 0,
            是否为敌人: true,
            aabbCollider: { left: 0, right: 0, updateFromUnitArea: function():Void {} }
        });

        TargetCacheUpdater.updateCache(world, 11001, "全体", true, cacheEntry);
        assertEquals("死亡单位被hp>0安全网过滤,剩余7个", 7, cacheEntry.data.length, 0);

        // 验证所有返回的单位都 hp > 0
        for (var k:Number = 0; k < cacheEntry.data.length; k++) {
            assertTrue("结果单位hp>0", cacheEntry.data[k].hp > 0);
        }
    }

    // ========================================================================
    // 校验重排（Reconciliation）测试
    // ========================================================================

    private static function runReconciliationTests():Void {
        trace("\n🔄 执行校验重排测试...");

        testReconciliationTriggersOnFirstUpdate();
        testReconciliationPeriodicTrigger();
        testReconciliationSelfHealing();
        testReconciliationPreSortBenefit();
        testReconciliationWithEmptyWorld();
    }

    /**
     * 首次 updateCache 应触发 reconciliation（lastReconcileFrame 从 -1 变为 currentFrame）
     */
    private static function testReconciliationTriggersOnFirstUpdate():Void {
        TargetCacheUpdater.resetVersions();

        var stats0:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("重置后lastReconcileFrame=-1", -1, stats0.lastReconcileFrame, 0);

        var world:Object = createMockGameWorld(createTestUnits(5));
        var cacheEntry:Object = createTestCacheEntry();

        TargetCacheUpdater.updateCache(world, 12000, "全体", true, cacheEntry);

        var stats1:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("首次更新后lastReconcileFrame=12000", 12000, stats1.lastReconcileFrame, 0);
        assertTrue("首次更新后registryCount>0", stats1.registryCount > 0);
    }

    /**
     * 超过 RECONCILE_INTERVAL 帧后应再次触发 reconciliation
     */
    private static function testReconciliationPeriodicTrigger():Void {
        TargetCacheUpdater.resetVersions();

        var world:Object = createMockGameWorld(createTestUnits(10));
        var cacheEntry:Object = createTestCacheEntry();

        // 首次更新：触发 reconciliation 在 frame 13000
        TargetCacheUpdater.updateCache(world, 13000, "全体", true, cacheEntry);
        var stats1:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("第一次校验帧=13000", 13000, stats1.lastReconcileFrame, 0);

        // 在 RECONCILE_INTERVAL 内更新（不触发 reconciliation）
        TargetCacheUpdater.addUnit(createSpecialUnits("all_enemies", 1)[0]); // bump 版本
        TargetCacheUpdater.updateCache(world, 13100, "全体", true, cacheEntry);
        var stats2:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("间隔内不触发校验,帧仍=13000", 13000, stats2.lastReconcileFrame, 0);

        // 超过 RECONCILE_INTERVAL（默认300帧）后更新
        TargetCacheUpdater.addUnit(createSpecialUnits("all_enemies", 1)[0]); // bump 版本
        TargetCacheUpdater.updateCache(world, 13301, "全体", true, cacheEntry);
        var stats3:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("超出间隔后触发校验,帧=13301", 13301, stats3.lastReconcileFrame, 0);
    }

    /**
     * 自愈测试：手动向 gameWorld 添加单位（不通过 addUnit），
     * reconciliation 应在下次触发时发现并纳入注册表
     */
    private static function testReconciliationSelfHealing():Void {
        TargetCacheUpdater.resetVersions();

        var units:Array = createTestUnits(5);
        var world:Object = createMockGameWorld(units);
        var cacheEntry:Object = createTestCacheEntry();

        // 通过 addUnit 注册
        for (var i:Number = 0; i < units.length; i++) {
            TargetCacheUpdater.addUnit(units[i]);
        }

        // 首次更新（触发 reconciliation，此时 world 和 registry 一致）
        TargetCacheUpdater.updateCache(world, 14000, "全体", true, cacheEntry);
        var stats1:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("初始registryCount=5", 5, stats1.registryCount, 0);

        // 偷偷向 gameWorld 添加3个单位，不调用 addUnit
        var sneakyUnits:Array = [];
        for (var j:Number = 0; j < 3; j++) {
            var su:Object = {
                _name: "sneaky_" + j,
                hp: 100,
                maxhp: 100,
                是否为敌人: true,
                aabbCollider: {
                    left: 500 + j * 20,
                    right: 520 + j * 20,
                    updateFromUnitArea: function(u:Object):Void {}
                }
            };
            world["sneaky_" + j] = su;
            sneakyUnits.push(su);
        }

        // 在 RECONCILE_INTERVAL 内更新 — sneaky 单位不在注册表中
        TargetCacheUpdater.addUnit(createSpecialUnits("all_enemies", 1)[0]); // bump 版本
        TargetCacheUpdater.updateCache(world, 14050, "全体", true, cacheEntry);
        // 注册表不含 sneaky 单位，但它们在 world 中
        // 收集仅来自注册表，所以结果中没有 sneaky

        // 超过 RECONCILE_INTERVAL 触发 reconciliation — 自愈
        TargetCacheUpdater.addUnit(createSpecialUnits("all_enemies", 1)[0]); // bump 版本
        TargetCacheUpdater.updateCache(world, 14301, "全体", true, cacheEntry);

        var stats2:Object = TargetCacheUpdater.getCachePoolStats();
        // reconciliation 从 gameWorld 重建注册表，应包含所有 hp>0 的单位
        assertTrue("自愈后registryCount包含sneaky单位", stats2.registryCount >= 8);

        // 验证 sneaky 单位出现在结果中
        var foundSneaky:Number = 0;
        for (var k:Number = 0; k < cacheEntry.data.length; k++) {
            if (String(cacheEntry.data[k]._name).indexOf("sneaky_") == 0) {
                foundSneaky++;
            }
        }
        assertEquals("自愈后3个sneaky单位均被收集", 3, foundSneaky, 0);
    }

    /**
     * reconciliation 后桶应预排序，使后续 TimSort 能利用 natural runs
     */
    private static function testReconciliationPreSortBenefit():Void {
        TargetCacheUpdater.resetVersions();

        // 创建逆序单位（故意 left 从大到小）
        var units:Array = [];
        for (var i:Number = 0; i < 30; i++) {
            var unit:Object = {
                _name: "presort_" + i,
                hp: 100,
                maxhp: 100,
                是否为敌人: true,
                aabbCollider: {
                    left: (30 - i) * 20, // 逆序
                    right: (30 - i) * 20 + 15,
                    updateFromUnitArea: function(u:Object):Void {}
                }
            };
            units.push(unit);
        }

        var world:Object = createMockGameWorld(units);
        var cacheEntry:Object = createTestCacheEntry();

        // 首次 updateCache 触发 reconciliation → 预排序
        TargetCacheUpdater.updateCache(world, 15000, "全体", true, cacheEntry);

        // 验证结果排序正确
        assertTrue("预排序后结果非空", cacheEntry.data.length > 0);
        for (var j:Number = 1; j < cacheEntry.leftValues.length; j++) {
            assertTrue(
                "reconciliation预排序: leftValues升序",
                cacheEntry.leftValues[j] >= cacheEntry.leftValues[j - 1]
            );
        }

        // 验证 nameIndex 与 data 一致
        for (var k:Number = 0; k < cacheEntry.data.length; k++) {
            assertEquals(
                "预排序后nameIndex正确",
                k,
                cacheEntry.nameIndex[cacheEntry.data[k]._name],
                0
            );
        }
    }

    /**
     * 空世界 reconciliation 后注册表应为空
     */
    private static function testReconciliationWithEmptyWorld():Void {
        TargetCacheUpdater.resetVersions();

        // 先添加一些单位到注册表
        var units:Array = createTestUnits(5);
        for (var i:Number = 0; i < units.length; i++) {
            TargetCacheUpdater.addUnit(units[i]);
        }
        var sb:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("空世界测试:初始registryCount=5", 5, sb.registryCount, 0);

        // 用空世界触发 reconciliation
        var emptyWorld:Object = {};
        var cacheEntry:Object = createTestCacheEntry();
        TargetCacheUpdater.updateCache(emptyWorld, 16000, "全体", true, cacheEntry);

        var sa:Object = TargetCacheUpdater.getCachePoolStats();
        assertEquals("空世界reconciliation后registryCount=0", 0, sa.registryCount, 0);
        assertEquals("空世界reconciliation后data为空", 0, cacheEntry.data.length, 0);
    }

    // ========================================================================
    // 复杂场景集成测试
    // ========================================================================
    
    private static function runComplexScenarioTests():Void {
        trace("\n🎯 执行复杂场景集成测试...");
        
        testDynamicWorldChanges();
        testConcurrentCacheRequests();
        testMemoryEfficiency();
    }
    
    private static function testDynamicWorldChanges():Void {
        TargetCacheUpdater.resetVersions();
        
        var dynamicWorld:Object = createMockGameWorld(createTestUnits(30));
        var cacheEntry:Object = createTestCacheEntry();
        
        // 初始更新
        TargetCacheUpdater.updateCache(dynamicWorld, 7000, "敌人", true, cacheEntry);
        var initialCount:Number = cacheEntry.data.length;
        
        // 添加新单位
        var newUnits:Array = createTestUnits(10);
        for (var i:Number = 0; i < newUnits.length; i++) {
            var newUnit:Object = newUnits[i];
            newUnit._name = "dynamic_" + i;
            dynamicWorld[newUnit._name] = newUnit;
            TargetCacheUpdater.addUnit(newUnit);
        }
        
        // 重新更新
        TargetCacheUpdater.updateCache(dynamicWorld, 7100, "敌人", true, cacheEntry);
        var afterAddCount:Number = cacheEntry.data.length;
        
        assertTrue("添加单位后数量可能变化", afterAddCount >= 0);
        
        // 移除一些单位
        for (var j:Number = 0; j < 5; j++) {
            var unitToRemove:Object = newUnits[j];
            delete dynamicWorld[unitToRemove._name];
            TargetCacheUpdater.removeUnit(unitToRemove);
        }
        
        // 再次更新
        TargetCacheUpdater.updateCache(dynamicWorld, 7200, "敌人", true, cacheEntry);
        var afterRemoveCount:Number = cacheEntry.data.length;
        
        // 验证数据一致性
        assertEquals("移除后数组长度一致", cacheEntry.data.length, cacheEntry.leftValues.length, 0);
        assertEquals("移除后帧数正确", 7200, cacheEntry.lastUpdatedFrame, 0);
    }
    
    private static function testConcurrentCacheRequests():Void {
        var sharedWorld:Object = createMockGameWorld(createTestUnits(40));
        var cacheEntries:Array = [];
        
        // 创建多个缓存条目
        for (var i:Number = 0; i < 5; i++) {
            cacheEntries[i] = createTestCacheEntry();
        }
        
        var requestConfigs:Array = [
            {type: "敌人", isEnemy: true},
            {type: "友军", isEnemy: true},
            {type: "全体", isEnemy: true},
            {type: "敌人", isEnemy: false},
            {type: "友军", isEnemy: false}
        ];
        
        // 并发更新（模拟同一帧内多个请求）
        var frame:Number = 8000;
        for (var j:Number = 0; j < requestConfigs.length; j++) {
            var config:Object = requestConfigs[j];
            TargetCacheUpdater.updateCache(
                sharedWorld,
                frame,
                config.type,
                config.isEnemy,
                cacheEntries[j]
            );
        }
        
        // 验证所有缓存都已更新
        for (var k:Number = 0; k < cacheEntries.length; k++) {
            var entry:Object = cacheEntries[k];
            assertEquals("并发更新帧数正确", frame, entry.lastUpdatedFrame, 0);
            assertNotNull("并发更新data不为空", entry.data);
            assertTrue("并发更新数据一致性", entry.data.length == entry.leftValues.length);
        }
        
        // 验证不同请求类型产生不同结果
        var enemyRequestData:Array = cacheEntries[0].data;
        var allyRequestData:Array = cacheEntries[1].data;
        var allRequestData:Array = cacheEntries[2].data;
        
        assertTrue("全体请求数据最多", allRequestData.length >= enemyRequestData.length);
        assertTrue("全体请求数据最多", allRequestData.length >= allyRequestData.length);
    }
    
    private static function testMemoryEfficiency():Void {
        var memoryTestStart:Number = getTimer();
        
        // 创建和销毁大量缓存
        for (var cycle:Number = 0; cycle < 10; cycle++) {
            var tempWorld:Object = createMockGameWorld(createTestUnits(100));
            var tempCache:Object = createTestCacheEntry();
            
            TargetCacheUpdater.updateCache(tempWorld, 9000 + cycle, "全体", true, tempCache);
            
            // 模拟内存释放
            tempWorld = null;
            tempCache = null;
            
            if (cycle % 3 == 0) {
                TargetCacheUpdater.clearCachePool();
            }
        }
        
        var memoryTestTime:Number = getTimer() - memoryTestStart;
        
        performanceResults.push({
            method: "memoryEfficiency",
            trials: 10,
            totalTime: memoryTestTime,
            avgTime: memoryTestTime / 10
        });
        
        trace("📊 内存效率测试: 10次循环耗时 " + memoryTestTime + "ms");
        assertTrue("内存效率测试时间合理", memoryTestTime < 200);
        
        // 检查最终状态
        var finalStats:Object = TargetCacheUpdater.getCachePoolStats();
        assertTrue("内存效率测试后缓存池合理", finalStats.totalPools <= 10);
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
        
        trace("\n🎯 TargetCacheUpdater当前状态:");
        trace(TargetCacheUpdater.getDetailedStatusReport());
        
        if (failedTests == 0) {
            trace("\n🎉 所有测试通过！TargetCacheUpdater 组件质量优秀！");
        } else {
            trace("\n⚠️ 发现 " + failedTests + " 个问题，请检查实现！");
        }
        
        trace("================================================================================");
    }
}