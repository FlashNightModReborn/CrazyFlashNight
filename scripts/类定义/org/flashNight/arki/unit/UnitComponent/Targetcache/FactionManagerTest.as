import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;

/**
 * 完整测试套件：FactionManager
 * ==============================
 * 特性：
 * - 100% 方法覆盖率测试
 * - 三阵营关系完整验证
 * - 适配器功能准确性测试
 * - 向后兼容性验证
 * - 性能基准测试
 * - 复杂场景模拟
 * - 边界条件测试
 * - 一句启动设计
 * 
 * 使用方法：
 * org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManagerTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManagerTest {
    
    // ========================================================================
    // 测试统计和配置
    // ========================================================================
    
    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    private static var performanceResults:Array = [];
    
    // 性能基准配置
    private static var PERFORMANCE_TRIALS:Number = 10000;
    private static var FACTION_QUERY_BENCHMARK_MS:Number = 0.005; // 单次查询不超过0.005ms
    
    /**
     * 主测试入口 - 一句启动全部测试
     */
    public static function runAll():Void {
        trace("================================================================================");
        trace("🚀 FactionManager 完整测试套件启动");
        trace("================================================================================");
        
        var startTime:Number = getTimer();
        resetTestStats();
        
        try {
            // === 基础功能测试 ===
            runBasicFunctionalityTests();
            
            // === 阵营注册测试 ===
            runFactionRegistrationTests();
            
            // === 关系管理测试 ===
            runRelationshipManagementTests();
            
            // === 三阵营系统测试 ===
            runThreeFactionSystemTests();
            
            // === 适配器功能测试 ===
            runAdapterFunctionalityTests();
            
            // === 缓存集成测试 ===
            runCacheIntegrationTests();
            
            // === 高级功能测试 ===
            runAdvancedFeaturesTests();
            
            // === 性能基准测试 ===
            runPerformanceBenchmarks();
            
            // === 边界条件测试 ===
            runBoundaryConditionTests();
            
            // === 向后兼容性测试 ===
            runBackwardCompatibilityTests();
            
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
    
    private static function assertEquals(testName:String, expected:String, actual:String):Void {
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
    
    private static function assertFalse(testName:String, condition:Boolean):Void {
        testCount++;
        if (!condition) {
            passedTests++;
            trace("✅ " + testName + " PASS");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (condition is true)");
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
    
    private static function assertArrayContains(testName:String, array:Array, item:String):Void {
        testCount++;
        var found:Boolean = false;
        for (var i:Number = 0; i < array.length; i++) {
            if (array[i] == item) {
                found = true;
                break;
            }
        }
        
        if (found) {
            passedTests++;
            trace("✅ " + testName + " PASS (array contains \"" + item + "\")");
        } else {
            failedTests++;
            trace("❌ " + testName + " FAIL (array does not contain \"" + item + "\")");
        }
    }
    
    // ========================================================================
    // 基础功能测试
    // ========================================================================
    
    private static function runBasicFunctionalityTests():Void {
        trace("\n📋 执行基础功能测试...");
        
        testInitialization();
        testFactionConstants();
        testRelationConstants();
    }
    
    private static function testInitialization():Void {
        // 测试FactionManager是否正确初始化
        var allFactions:Array = FactionManager.getAllFactions();
        assertNotNull("getAllFactions返回数组", allFactions);
        assertTrue("默认阵营数量正确", allFactions.length >= 3);
        
        var status:Object = FactionManager.getStatus();
        assertNotNull("getStatus返回对象", status);
        assertTrue("初始化标志正确", status.initialized);
        assertEquals("阵营数量统计正确", allFactions.length.toString(), status.factionCount.toString());
    }
    
    private static function testFactionConstants():Void {
        // 验证阵营常量定义
        assertNotNull("FACTION_PLAYER常量", FactionManager.FACTION_PLAYER);
        assertNotNull("FACTION_ENEMY常量", FactionManager.FACTION_ENEMY);
        assertNotNull("FACTION_HOSTILE_NEUTRAL常量", FactionManager.FACTION_HOSTILE_NEUTRAL);
        
        assertEquals("玩家阵营常量值", "PLAYER", FactionManager.FACTION_PLAYER);
        assertEquals("敌人阵营常量值", "ENEMY", FactionManager.FACTION_ENEMY);
        assertEquals("中立敌对常量值", "HOSTILE_NEUTRAL", FactionManager.FACTION_HOSTILE_NEUTRAL);
    }
    
    private static function testRelationConstants():Void {
        // 验证关系常量定义
        assertNotNull("RELATION_ALLY常量", FactionManager.RELATION_ALLY);
        assertNotNull("RELATION_ENEMY常量", FactionManager.RELATION_ENEMY);
        assertNotNull("RELATION_NEUTRAL常量", FactionManager.RELATION_NEUTRAL);
        assertNotNull("RELATION_SELF常量", FactionManager.RELATION_SELF);
        
        assertEquals("盟友关系常量值", "ALLY", FactionManager.RELATION_ALLY);
        assertEquals("敌对关系常量值", "ENEMY", FactionManager.RELATION_ENEMY);
        assertEquals("中立关系常量值", "NEUTRAL", FactionManager.RELATION_NEUTRAL);
        assertEquals("自身关系常量值", "SELF", FactionManager.RELATION_SELF);
    }
    
    // ========================================================================
    // 阵营注册测试
    // ========================================================================
    
    private static function runFactionRegistrationTests():Void {
        trace("\n📝 执行阵营注册测试...");
        
        testFactionRegistration();
        testFactionMetadata();
        testDefaultFactions();
    }
    
    private static function testFactionRegistration():Void {
        // 测试新阵营注册
        var success:Boolean = FactionManager.registerFaction("TEST_FACTION", {
            name: "测试阵营",
            description: "用于测试的阵营"
        });
        assertTrue("新阵营注册成功", success);
        
        var allFactions:Array = FactionManager.getAllFactions();
        assertArrayContains("新阵营在列表中", allFactions, "TEST_FACTION");
        
        // 测试无效注册
        var invalidSuccess:Boolean = FactionManager.registerFaction("", {});
        assertFalse("空阵营ID注册失败", invalidSuccess);
        
        var nullSuccess:Boolean = FactionManager.registerFaction(null, {});
        assertFalse("null阵营ID注册失败", nullSuccess);
    }
    
    private static function testFactionMetadata():Void {
        // 测试元数据存储和获取
        var metadata:Object = FactionManager.getFactionMetadata("TEST_FACTION");
        assertNotNull("获取阵营元数据", metadata);
        assertEquals("元数据名称正确", "测试阵营", metadata.name);
        assertEquals("元数据描述正确", "用于测试的阵营", metadata.description);
        
        // 测试不存在阵营的元数据
        var emptyMetadata:Object = FactionManager.getFactionMetadata("NONEXISTENT");
        assertNotNull("不存在阵营返回空对象", emptyMetadata);
    }
    
    private static function testDefaultFactions():Void {
        // 验证默认阵营的元数据
        var playerMeta:Object = FactionManager.getFactionMetadata(FactionManager.FACTION_PLAYER);
        assertNotNull("玩家阵营元数据", playerMeta);
        assertEquals("玩家阵营legacy值", String(false), playerMeta.legacyValue);
        
        var enemyMeta:Object = FactionManager.getFactionMetadata(FactionManager.FACTION_ENEMY);
        assertNotNull("敌人阵营元数据", enemyMeta);
        assertEquals("敌人阵营legacy值", String(true), enemyMeta.legacyValue);
        
        var neutralMeta:Object = FactionManager.getFactionMetadata(FactionManager.FACTION_HOSTILE_NEUTRAL);
        assertNotNull("中立敌对阵营元数据", neutralMeta);
        assertEquals("中立敌对legacy值", String(null), neutralMeta.legacyValue);
    }
    
    // ========================================================================
    // 关系管理测试
    // ========================================================================
    
    private static function runRelationshipManagementTests():Void {
        trace("\n🤝 执行关系管理测试...");
        
        testRelationshipSetting();
        testRelationshipQuery();
        testRelationshipValidation();
    }
    
    private static function testRelationshipSetting():Void {
        // 测试关系设置
        var success:Boolean = FactionManager.setRelationship("TEST_FACTION", FactionManager.FACTION_PLAYER, FactionManager.RELATION_ALLY);
        assertTrue("设置关系成功", success);
        
        var relation:String = FactionManager.getRelationship("TEST_FACTION", FactionManager.FACTION_PLAYER);
        assertEquals("关系设置正确", FactionManager.RELATION_ALLY, relation);
        
        // 测试无效关系设置
        var invalidSuccess:Boolean = FactionManager.setRelationship("INVALID_FACTION", FactionManager.FACTION_PLAYER, FactionManager.RELATION_ALLY);
        assertFalse("无效阵营关系设置失败", invalidSuccess);
        
        var invalidRelationSuccess:Boolean = FactionManager.setRelationship("TEST_FACTION", FactionManager.FACTION_PLAYER, "INVALID_RELATION");
        assertFalse("无效关系状态设置失败", invalidRelationSuccess);
    }
    
    private static function testRelationshipQuery():Void {
        // 测试关系查询
        var selfRelation:String = FactionManager.getRelationship(FactionManager.FACTION_PLAYER, FactionManager.FACTION_PLAYER);
        assertEquals("自身关系查询", FactionManager.RELATION_SELF, selfRelation);
        
        var undefinedRelation:String = FactionManager.getRelationship("TEST_FACTION", "NONEXISTENT");
        assertEquals("未定义关系默认中立", FactionManager.RELATION_NEUTRAL, undefinedRelation);
    }
    
    private static function testRelationshipValidation():Void {
        // 测试关系矩阵验证
        var validation:Object = FactionManager.validateMatrix();
        assertNotNull("矩阵验证结果", validation);
        assertTrue("验证结果包含isValid", validation.hasOwnProperty("isValid"));
        assertTrue("验证结果包含errors", validation.hasOwnProperty("errors"));
        assertTrue("验证结果包含warnings", validation.hasOwnProperty("warnings"));
    }
    
    // ========================================================================
    // 三阵营系统测试
    // ========================================================================
    
    private static function runThreeFactionSystemTests():Void {
        trace("\n⚔️ 执行三阵营系统测试...");
        
        testDefaultThreeFactionRelations();
        testConvenienceQueryMethods();
        testFactionLists();
    }
    
    private static function testDefaultThreeFactionRelations():Void {
        // 验证默认的三阵营关系矩阵
        
        // 玩家阵营关系
        assertTrue("玩家vs玩家-盟友", FactionManager.areAllies(FactionManager.FACTION_PLAYER, FactionManager.FACTION_PLAYER));
        assertTrue("玩家vs敌人-敌对", FactionManager.areEnemies(FactionManager.FACTION_PLAYER, FactionManager.FACTION_ENEMY));
        assertTrue("玩家vs中立敌对-敌对", FactionManager.areEnemies(FactionManager.FACTION_PLAYER, FactionManager.FACTION_HOSTILE_NEUTRAL));
        
        // 敌人阵营关系
        assertTrue("敌人vs玩家-敌对", FactionManager.areEnemies(FactionManager.FACTION_ENEMY, FactionManager.FACTION_PLAYER));
        assertTrue("敌人vs敌人-盟友", FactionManager.areAllies(FactionManager.FACTION_ENEMY, FactionManager.FACTION_ENEMY));
        assertTrue("敌人vs中立敌对-敌对", FactionManager.areEnemies(FactionManager.FACTION_ENEMY, FactionManager.FACTION_HOSTILE_NEUTRAL));
        
        // 中立敌对阵营关系（与所有人敌对）
        assertTrue("中立敌对vs玩家-敌对", FactionManager.areEnemies(FactionManager.FACTION_HOSTILE_NEUTRAL, FactionManager.FACTION_PLAYER));
        assertTrue("中立敌对vs敌人-敌对", FactionManager.areEnemies(FactionManager.FACTION_HOSTILE_NEUTRAL, FactionManager.FACTION_ENEMY));
        assertTrue("中立敌对vs中立敌对-盟友", FactionManager.areAllies(FactionManager.FACTION_HOSTILE_NEUTRAL, FactionManager.FACTION_HOSTILE_NEUTRAL));
    }
    
    private static function testConvenienceQueryMethods():Void {
        // 测试便捷查询方法
        assertFalse("玩家vs敌人-非盟友", FactionManager.areAllies(FactionManager.FACTION_PLAYER, FactionManager.FACTION_ENEMY));
        assertFalse("玩家vs敌人-非中立", FactionManager.areNeutral(FactionManager.FACTION_PLAYER, FactionManager.FACTION_ENEMY));
        
        // 测试中立关系（需要先设置一个中立关系）
        FactionManager.setRelationship("TEST_FACTION", FactionManager.FACTION_PLAYER, FactionManager.RELATION_NEUTRAL);
        assertTrue("测试阵营vs玩家-中立", FactionManager.areNeutral("TEST_FACTION", FactionManager.FACTION_PLAYER));
    }
    
    private static function testFactionLists():Void {
        // 测试敌对阵营列表
        var playerEnemies:Array = FactionManager.getEnemyFactions(FactionManager.FACTION_PLAYER);
        assertArrayContains("玩家的敌人包含敌人阵营", playerEnemies, FactionManager.FACTION_ENEMY);
        assertArrayContains("玩家的敌人包含中立敌对", playerEnemies, FactionManager.FACTION_HOSTILE_NEUTRAL);
        
        // 测试盟友阵营列表
        var playerAllies:Array = FactionManager.getAllyFactions(FactionManager.FACTION_PLAYER);
        assertArrayContains("玩家的盟友包含自身", playerAllies, FactionManager.FACTION_PLAYER);
    }
    
    // ========================================================================
    // 适配器功能测试
    // ========================================================================

    private static function runAdapterFunctionalityTests():Void {
        trace("\n🔄 执行适配器功能测试...");

        testUnitFactionMapping();
        testLegacyValueMapping();
        testUnitRelationshipQueries();
        testNewFactionLegacyValueMethod();
        testCreateFactionUnitMethod();
    }
    
    private static function testUnitFactionMapping():Void {
        // 创建测试单位
        var playerUnit:Object = { 是否为敌人: false };
        var enemyUnit:Object = { 是否为敌人: true };
        var neutralUnit:Object = { 是否为敌人: null };
        var undefinedUnit:Object = { };
        
        // 测试阵营映射
        assertEquals("玩家单位阵营映射", FactionManager.FACTION_PLAYER, FactionManager.getFactionFromUnit(playerUnit));
        assertEquals("敌人单位阵营映射", FactionManager.FACTION_ENEMY, FactionManager.getFactionFromUnit(enemyUnit));
        assertEquals("中立单位阵营映射", FactionManager.FACTION_HOSTILE_NEUTRAL, FactionManager.getFactionFromUnit(neutralUnit));
        assertEquals("未定义单位阵营映射", FactionManager.FACTION_HOSTILE_NEUTRAL, FactionManager.getFactionFromUnit(undefinedUnit));
        
        // 测试null单位
        assertEquals("null单位阵营映射", FactionManager.FACTION_HOSTILE_NEUTRAL, FactionManager.getFactionFromUnit(null));
    }
    
    private static function testLegacyValueMapping():Void {
        // 测试反向映射
        assertEquals("玩家阵营legacy值", String(false), FactionManager.getLegacyValueFromFaction(FactionManager.FACTION_PLAYER));
        assertEquals("敌人阵营legacy值", String(true), FactionManager.getLegacyValueFromFaction(FactionManager.FACTION_ENEMY));
        assertEquals("中立敌对legacy值", String(null), FactionManager.getLegacyValueFromFaction(FactionManager.FACTION_HOSTILE_NEUTRAL));
    }

    private static function testNewFactionLegacyValueMethod():Void {
        // 测试新增的 getFactionLegacyValue 方法
        trace("  测试 getFactionLegacyValue 方法...");

        // 测试有效阵营
        var playerValue = FactionManager.getFactionLegacyValue(FactionManager.FACTION_PLAYER);
        assertEquals("getFactionLegacyValue-玩家", String(false), String(playerValue));

        var enemyValue = FactionManager.getFactionLegacyValue(FactionManager.FACTION_ENEMY);
        assertEquals("getFactionLegacyValue-敌人", String(true), String(enemyValue));

        var neutralValue = FactionManager.getFactionLegacyValue(FactionManager.FACTION_HOSTILE_NEUTRAL);
        assertEquals("getFactionLegacyValue-中立敌对", String(null), String(neutralValue));

        // 测试无效阵营
        var invalidValue = FactionManager.getFactionLegacyValue("INVALID_FACTION");
        assertEquals("getFactionLegacyValue-无效阵营", String(null), String(invalidValue));

        var nullValue = FactionManager.getFactionLegacyValue(null);
        assertEquals("getFactionLegacyValue-null输入", String(null), String(nullValue));

        var emptyValue = FactionManager.getFactionLegacyValue("");
        assertEquals("getFactionLegacyValue-空字符串", String(null), String(emptyValue));
    }

    private static function testCreateFactionUnitMethod():Void {
        // 测试新增的 createFactionUnit 方法
        trace("  测试 createFactionUnit 方法...");

        // 测试玩家阵营假单位
        var playerUnit:Object = FactionManager.createFactionUnit(FactionManager.FACTION_PLAYER, "test");
        assertNotNull("createFactionUnit-玩家单位创建", playerUnit);
        assertEquals("createFactionUnit-玩家单位名称", "test_PLAYER", playerUnit._name);
        assertEquals("createFactionUnit-玩家单位是否为敌人", String(false), String(playerUnit.是否为敌人));
        assertEquals("createFactionUnit-玩家单位阵营", FactionManager.FACTION_PLAYER, playerUnit.faction);

        // 测试敌人阵营假单位
        var enemyUnit:Object = FactionManager.createFactionUnit(FactionManager.FACTION_ENEMY, "queue");
        assertNotNull("createFactionUnit-敌人单位创建", enemyUnit);
        assertEquals("createFactionUnit-敌人单位名称", "queue_ENEMY", enemyUnit._name);
        assertEquals("createFactionUnit-敌人单位是否为敌人", String(true), String(enemyUnit.是否为敌人));
        assertEquals("createFactionUnit-敌人单位阵营", FactionManager.FACTION_ENEMY, enemyUnit.faction);

        // 测试中立敌对假单位
        var neutralUnit:Object = FactionManager.createFactionUnit(FactionManager.FACTION_HOSTILE_NEUTRAL, null);
        assertNotNull("createFactionUnit-中立单位创建", neutralUnit);
        assertEquals("createFactionUnit-中立单位名称前缀", "faction_unit_", neutralUnit._name.substr(0, 13));
        assertEquals("createFactionUnit-中立单位是否为敌人", String(null), String(neutralUnit.是否为敌人));
        assertEquals("createFactionUnit-中立单位阵营", FactionManager.FACTION_HOSTILE_NEUTRAL, neutralUnit.faction);

        // 测试创建的假单位能否正确被其他方法识别
        var mappedFaction:String = FactionManager.getFactionFromUnit(playerUnit);
        assertEquals("createFactionUnit-反向映射验证", FactionManager.FACTION_PLAYER, mappedFaction);

        // 测试假单位间的关系查询
        assertTrue("createFactionUnit-单位关系查询", FactionManager.areUnitsEnemies(playerUnit, enemyUnit));
        assertFalse("createFactionUnit-单位盟友查询", FactionManager.areUnitsAllies(playerUnit, enemyUnit));
    }
    
    private static function testUnitRelationshipQueries():Void {
        var playerUnit:Object = { 是否为敌人: false };
        var enemyUnit:Object = { 是否为敌人: true };
        var neutralUnit:Object = { 是否为敌人: null };
        
        // 测试单位间关系查询
        assertTrue("玩家vs敌人-敌对", FactionManager.areUnitsEnemies(playerUnit, enemyUnit));
        assertTrue("玩家vs中立-敌对", FactionManager.areUnitsEnemies(playerUnit, neutralUnit));
        assertTrue("敌人vs中立-敌对", FactionManager.areUnitsEnemies(enemyUnit, neutralUnit));
        
        assertTrue("玩家vs玩家-盟友", FactionManager.areUnitsAllies(playerUnit, playerUnit));
        assertTrue("敌人vs敌人-盟友", FactionManager.areUnitsAllies(enemyUnit, enemyUnit));
        
        assertFalse("玩家vs敌人-非盟友", FactionManager.areUnitsAllies(playerUnit, enemyUnit));
    }
    
    // ========================================================================
    // 缓存集成测试
    // ========================================================================
    
    private static function runCacheIntegrationTests():Void {
        trace("\n🎯 执行缓存集成测试...");
        
        testCacheQueryMethods();
        testCacheKeySuffix();
    }
    
    private static function testCacheQueryMethods():Void {
        var playerUnit:Object = { 是否为敌人: false };
        var enemyUnit:Object = { 是否为敌人: true };
        var neutralUnit:Object = { 是否为敌人: null };
        
        // 测试敌人查询判断
        assertTrue("玩家查询敌人-包含敌人单位", FactionManager.shouldIncludeInEnemyQuery(playerUnit, enemyUnit));
        assertTrue("玩家查询敌人-包含中立单位", FactionManager.shouldIncludeInEnemyQuery(playerUnit, neutralUnit));
        assertFalse("玩家查询敌人-不包含玩家单位", FactionManager.shouldIncludeInEnemyQuery(playerUnit, playerUnit));
        
        // 测试友军查询判断
        assertTrue("玩家查询友军-包含玩家单位", FactionManager.shouldIncludeInAllyQuery(playerUnit, playerUnit));
        assertFalse("玩家查询友军-不包含敌人单位", FactionManager.shouldIncludeInAllyQuery(playerUnit, enemyUnit));
        assertFalse("玩家查询友军-不包含中立单位", FactionManager.shouldIncludeInAllyQuery(playerUnit, neutralUnit));
    }
    
    private static function testCacheKeySuffix():Void {
        var playerUnit:Object = { 是否为敌人: false };
        var enemyUnit:Object = { 是否为敌人: true };
        var neutralUnit:Object = { 是否为敌人: null };
        
        // 测试缓存键后缀生成
        assertEquals("玩家单位缓存键后缀", FactionManager.FACTION_PLAYER, FactionManager.getCacheKeySuffix(playerUnit));
        assertEquals("敌人单位缓存键后缀", FactionManager.FACTION_ENEMY, FactionManager.getCacheKeySuffix(enemyUnit));
        assertEquals("中立单位缓存键后缀", FactionManager.FACTION_HOSTILE_NEUTRAL, FactionManager.getCacheKeySuffix(neutralUnit));
    }
    
    // ========================================================================
    // 高级功能测试
    // ========================================================================
    
    private static function runAdvancedFeaturesTests():Void {
        trace("\n🚀 执行高级功能测试...");
        
        testBatchRelationships();
        testMatrixOperations();
        testDiagnostics();
    }
    
    private static function testBatchRelationships():Void {
        // 测试批量关系设置
        var relationshipData:Array = [
            { from: "TEST_FACTION", to: FactionManager.FACTION_ENEMY, relation: FactionManager.RELATION_ALLY },
            { from: "TEST_FACTION", to: FactionManager.FACTION_HOSTILE_NEUTRAL, relation: FactionManager.RELATION_NEUTRAL }
        ];
        
        var successCount:Number = FactionManager.setBatchRelationships(relationshipData);
        assertEquals("批量关系设置成功数", relationshipData.length.toString(), successCount.toString());
        
        // 验证批量设置的关系
        assertEquals("批量设置关系1", FactionManager.RELATION_ALLY, FactionManager.getRelationship("TEST_FACTION", FactionManager.FACTION_ENEMY));
        assertEquals("批量设置关系2", FactionManager.RELATION_NEUTRAL, FactionManager.getRelationship("TEST_FACTION", FactionManager.FACTION_HOSTILE_NEUTRAL));
    }
    
    private static function testMatrixOperations():Void {
        // 测试关系矩阵快照
        var matrix:Object = FactionManager.getRelationshipMatrix();
        assertNotNull("关系矩阵快照", matrix);
        
        // 测试矩阵加载
        var success:Boolean = FactionManager.loadRelationshipMatrix(matrix);
        assertTrue("矩阵加载成功", success);
        
        // 测试无效矩阵加载
        var invalidSuccess:Boolean = FactionManager.loadRelationshipMatrix(null);
        assertFalse("无效矩阵加载失败", invalidSuccess);
    }
    
    private static function testDiagnostics():Void {
        // 测试诊断报告
        var report:String = FactionManager.getRelationshipReport();
        assertNotNull("关系报告生成", report);
        assertTrue("报告包含阵营信息", report.indexOf("已注册阵营") >= 0);
        assertTrue("报告包含关系矩阵", report.indexOf("关系矩阵") >= 0);
        
        // 测试状态信息
        var status:Object = FactionManager.getStatus();
        assertNotNull("状态信息获取", status);
        assertTrue("状态包含初始化标志", status.hasOwnProperty("initialized"));
        assertTrue("状态包含阵营数量", status.hasOwnProperty("factionCount"));
    }
    
    // ========================================================================
    // 性能基准测试
    // ========================================================================
    
    private static function runPerformanceBenchmarks():Void {
        trace("\n⚡ 执行性能基准测试...");
        
        performanceTestRelationshipQueries();
        performanceTestAdapterMethods();
        performanceTestVsLegacyComparison();
    }
    
    private static function performanceTestRelationshipQueries():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            FactionManager.areEnemies(FactionManager.FACTION_PLAYER, FactionManager.FACTION_ENEMY);
        }
        var queryTime:Number = getTimer() - startTime;
        var avgQueryTime:Number = queryTime / trials;
        
        performanceResults.push({
            method: "relationshipQueries",
            trials: trials,
            totalTime: queryTime,
            avgTime: avgQueryTime
        });
        
        trace("📊 关系查询性能: " + trials + "次查询耗时 " + queryTime + "ms (平均 " + 
              Math.round(avgQueryTime * 1000000) / 1000 + "μs/次)");
        
        assertTrue("关系查询性能达标", avgQueryTime < FACTION_QUERY_BENCHMARK_MS);
    }
    
    private static function performanceTestAdapterMethods():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var testUnit:Object = { 是否为敌人: false };
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            FactionManager.getFactionFromUnit(testUnit);
        }
        var adapterTime:Number = getTimer() - startTime;
        var avgAdapterTime:Number = adapterTime / trials;
        
        performanceResults.push({
            method: "adapterMethods",
            trials: trials,
            totalTime: adapterTime,
            avgTime: avgAdapterTime
        });
        
        trace("📊 适配器方法性能: " + trials + "次调用耗时 " + adapterTime + "ms (平均 " + 
              Math.round(avgAdapterTime * 1000000) / 1000 + "μs/次)");
        
        assertTrue("适配器方法性能达标", avgAdapterTime < FACTION_QUERY_BENCHMARK_MS);
    }
    
    private static function performanceTestVsLegacyComparison():Void {
        var trials:Number = PERFORMANCE_TRIALS;
        var unit1:Object = { 是否为敌人: false };
        var unit2:Object = { 是否为敌人: true };
        
        // 测试新方法性能
        var startTime1:Number = getTimer();
        for (var i:Number = 0; i < trials; i++) {
            FactionManager.areUnitsEnemies(unit1, unit2);
        }
        var newMethodTime:Number = getTimer() - startTime1;
        
        // 测试传统方法性能
        var startTime2:Number = getTimer();
        for (var j:Number = 0; j < trials; j++) {
            var legacyResult:Boolean = (unit1.是否为敌人 != unit2.是否为敌人);
        }
        var legacyTime:Number = getTimer() - startTime2;
        
        var overhead:Number = newMethodTime / legacyTime;
        
        performanceResults.push({
            method: "vsLegacyComparison",
            trials: trials,
            newMethodTime: newMethodTime,
            legacyTime: legacyTime,
            overhead: overhead
        });
        
        trace("📊 性能对比: 新方法=" + newMethodTime + "ms, 传统方法=" + legacyTime + "ms, 开销=" + 
              Math.round(overhead * 100) + "%");
        
        assertTrue("相对性能开销可接受", overhead < 30); // 新方法不应该超过传统方法30倍
    }
    
    // ========================================================================
    // 边界条件测试
    // ========================================================================
    
    private static function runBoundaryConditionTests():Void {
        trace("\n🔍 执行边界条件测试...");
        
        testInvalidInputHandling();
        testEdgeCaseScenarios();
        testErrorRecovery();
    }
    
    private static function testInvalidInputHandling():Void {
        // 测试无效输入处理
        assertFalse("无效阵营关系查询", FactionManager.areEnemies("INVALID1", "INVALID2"));
        assertEquals("无效阵营关系默认中立", FactionManager.RELATION_NEUTRAL, 
                    FactionManager.getRelationship("INVALID1", "INVALID2"));
        
        var emptyEnemies:Array = FactionManager.getEnemyFactions("INVALID");
        assertTrue("无效阵营敌人列表为空", emptyEnemies.length == 0);
        
        // 测试null输入
        assertEquals("null单位阵营映射", FactionManager.FACTION_HOSTILE_NEUTRAL, FactionManager.getFactionFromUnit(null));
    }
    
    private static function testEdgeCaseScenarios():Void {
        // 测试边界情况
        
        // 单一阵营世界
        var singleFactionUnit:Object = { 是否为敌人: false };
        var enemies:Array = FactionManager.getEnemyFactions(FactionManager.FACTION_PLAYER);
        assertTrue("单一阵营仍有敌人", enemies.length > 0);
        
        // 自身关系
        assertTrue("自身关系为盟友", FactionManager.areAllies(FactionManager.FACTION_PLAYER, FactionManager.FACTION_PLAYER));
        assertEquals("自身关系状态", FactionManager.RELATION_SELF, 
                    FactionManager.getRelationship(FactionManager.FACTION_PLAYER, FactionManager.FACTION_PLAYER));
    }
    
    private static function testErrorRecovery():Void {
        // 测试错误恢复能力
        
        // 损坏关系矩阵后的恢复
        var originalMatrix:Object = FactionManager.getRelationshipMatrix();
        
        // 加载损坏的矩阵
        var corruptMatrix:Object = { INVALID: { DATA: "CORRUPT" } };
        FactionManager.loadRelationshipMatrix(corruptMatrix);
        
        // 恢复原始矩阵
        var recoverySuccess:Boolean = FactionManager.loadRelationshipMatrix(originalMatrix);
        assertTrue("矩阵恢复成功", recoverySuccess);
        
        // 验证恢复后功能正常
        assertTrue("恢复后功能正常", FactionManager.areEnemies(FactionManager.FACTION_PLAYER, FactionManager.FACTION_ENEMY));
    }
    
    // ========================================================================
    // 向后兼容性测试
    // ========================================================================
    
    private static function runBackwardCompatibilityTests():Void {
        trace("\n⬅️ 执行向后兼容性测试...");
        
        testLegacyValueCompatibility();
        testMixedSystemCompatibility();
    }
    
    private static function testLegacyValueCompatibility():Void {
        // 创建使用旧系统值的单位
        var units:Array = [
            { 是否为敌人: true },    // 传统敌人
            { 是否为敌人: false },   // 传统友军
            { 是否为敌人: null },    // 新的中立敌对
            { 是否为敌人: undefined }, // 未定义
            { },                    // 无属性
            null                    // null单位
        ];
        
        // 验证所有单位都能正确映射
        for (var i:Number = 0; i < units.length; i++) {
            var unit:Object = units[i];
            var faction:String = FactionManager.getFactionFromUnit(unit);
            assertNotNull("单位" + i + "阵营映射", faction);
            
            // 验证可以获取legacy值
            var legacyValue = FactionManager.getLegacyValueFromFaction(faction);
            // legacy值可以是任何值，只要不导致错误
        }
    }
    
    private static function testMixedSystemCompatibility():Void {
        // 测试新旧系统混合使用
        var playerUnit:Object = { 是否为敌人: false };
        var enemyUnit:Object = { 是否为敌人: true };
        var neutralUnit:Object = { 是否为敌人: null };
        
        // 模拟旧系统的逻辑
        var legacyEnemyCheck:Boolean = (playerUnit.是否为敌人 != enemyUnit.是否为敌人);
        var newEnemyCheck:Boolean = FactionManager.areUnitsEnemies(playerUnit, enemyUnit);
        
        assertEquals("新旧系统敌对判断一致", String(legacyEnemyCheck), String(newEnemyCheck));
        
        // 验证新增的中立敌对逻辑
        assertTrue("玩家vs中立敌对-敌对", FactionManager.areUnitsEnemies(playerUnit, neutralUnit));
        assertTrue("敌人vs中立敌对-敌对", FactionManager.areUnitsEnemies(enemyUnit, neutralUnit));
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
        trace("\n📌 新增方法测试覆盖:");
        trace("  ✅ getFactionLegacyValue - 阵营到布尔值映射");
        trace("  ✅ createFactionUnit - 假单位创建工具");
        
        if (performanceResults.length > 0) {
            trace("\n⚡ 性能基准报告:");
            for (var i:Number = 0; i < performanceResults.length; i++) {
                var result:Object = performanceResults[i];
                
                if (result.method == "vsLegacyComparison") {
                    trace("  " + result.method + ": 开销 " + Math.round(result.overhead * 100) + "% (" + 
                          result.trials + "次对比)");
                } else {
                    var avgTimeStr:String = (isNaN(result.avgTime) || result.avgTime == undefined) ? 
                        "N/A" : String(Math.round(result.avgTime * 1000000) / 1000);
                    trace("  " + result.method + ": " + avgTimeStr + "μs/次 (" + 
                          result.trials + "次测试)");
                }
            }
        }
        
        trace("\n🎯 FactionManager当前状态:");
        trace(FactionManager.getRelationshipReport());
        
        if (failedTests == 0) {
            trace("\n🎉 所有测试通过！FactionManager 组件质量优秀！");
            trace("✅ 三阵营系统正常工作");
            trace("✅ 向后兼容性完美");
            trace("✅ 性能开销可接受");
            trace("✅ 为未来扩展做好准备");
        } else {
            trace("\n⚠️ 发现 " + failedTests + " 个问题，请检查实现！");
        }
        
        trace("================================================================================");
    }
}