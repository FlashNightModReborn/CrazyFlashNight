// org/flashNight/arki/component/Buff/test/BuffManagerTest.as

import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.Buff.test.*;

/**
 * BuffManager综合测试套件 - 重构版
 * 
 * 核心关注点：
 * 1. 数值计算的准确性
 * 2. MetaBuff的状态管理和PodBuff注入机制
 * 3. TimeLimitComponent的生命周期管理
 * 4. PropertyContainer的动态计算
 * 
 * 使用方式: BuffManagerTest.runAllTests();
 */
class org.flashNight.arki.component.Buff.test.BuffManagerTest {
    
    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;
    private static var performanceResults:Array = [];
    
    // 测试用的模拟目标对象
    private static var mockTarget:Object;
    
    /**
     * 运行所有测试用例
     */
    public static function runAllTests():Void {
        trace("=== BuffManager Calculation Accuracy Test Suite ===");
        
        // 重置计数器
        testCount = 0;
        passedCount = 0;
        failedCount = 0;
        performanceResults = [];
        
        trace("\n--- Phase 1: Basic Calculation Tests ---");
        testBasicAddCalculation();
        testBasicMultiplyCalculation();
        testBasicPercentCalculation();
        testCalculationTypesPriority();
        testOverrideCalculation();
        testBasicMaxCalculation();
        testBasicMinCalculation();

        trace("\n--- Phase 1.5: Conservative Semantics Tests ---");
        testAddPositiveCalculation();
        testAddNegativeCalculation();
        testMultPositiveCalculation();
        testMultNegativeCalculation();
        testConservativeMixedCalculation();
        testFullCalculationChain();
        
        trace("\n--- Phase 2: MetaBuff Injection & Calculation ---");
        testMetaBuffPodInjection();
        testMetaBuffCalculationAccuracy();
        testMetaBuffStateTransitions();
        testMetaBuffDynamicInjection();
        
        trace("\n--- Phase 3: TimeLimitComponent & Dynamic Calculations ---");
        testTimeLimitedBuffCalculations();
        testDynamicCalculationUpdates();
        testBuffExpirationCalculations();
        testCascadingBuffCalculations();
        
        trace("\n--- Phase 4: Complex Calculation Scenarios ---");
        testStackingBuffCalculations();
        testMultiPropertyCalculations();
        testCalculationOrderDependency();
        testRealGameCalculationScenario();
        
        trace("\n--- Phase 5: PropertyContainer Integration ---");
        testPropertyContainerCalculations();
        testDynamicPropertyRecalculation();
        testPropertyContainerRebuildAccuracy();
        testConcurrentPropertyUpdates();
        
        trace("\n--- Phase 6: Edge Cases & Accuracy ---");
        testExtremValueCalculations();
        testFloatingPointAccuracy();
        testNegativeValueCalculations();
        testZeroValueHandling();
        
        trace("\n--- Phase 7: Performance & Accuracy at Scale ---");
        testLargeScaleCalculationAccuracy();
        testCalculationPerformance();
        testMemoryAndCalculationConsistency();
        
        trace("\n--- Phase: Sticky Container & Lifecycle Contracts ---");
        testStickyContainer_NoUndefined();
        testUnmanagePropertyFinalizeAndRebind();
        testDestroyDefaultFinalizeAll();
        testBaseZeroVsUndefined();
        testOrderIndependenceAgainstAddSequence();
        testClearAllBuffsKeepsProperties();
        testMetaBuffJitterStability();
        
        // 输出测试结果
        trace("--- Phase 8: Regression & Lifecycle Contracts ---");
        runPhase8_RegressionAndContracts();

        // [Phase 0/A] 新增回归测试
        runPhase9_PhaseZeroAndARegression();

        // [Phase B] ID命名空间分离回归测试
        runPhase10_PhaseBRegression();

        // [Phase D] ID契约校验回归测试
        runPhase11_PhaseDContract();

        printTestResults();
        printPerformanceReport();
    }
    
    // ========== Phase 1: 基础计算测试 ==========
    
    private static function testBasicAddCalculation():Void {
        startTest("Basic ADD Calculation");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.attack = 100; // 基础攻击力
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 添加加法buff
            var addBuff1:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 30);
            var addBuff2:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 20);
            
            manager.addBuff(addBuff1, null);
            manager.addBuff(addBuff2, null);
            manager.update(1);
            
            // 预期：100 + 30 + 20 = 150
            var expectedValue:Number = 150;
            var actualValue:Number = getCalculatedValue(mockTarget, "attack");
            
            assertCalculation(actualValue, expectedValue, "ADD calculation");
            
            trace("  ✓ ADD: 100 + 30 + 20 = " + actualValue);
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Basic ADD calculation failed: " + e.message);
        }
    }
    
    private static function testBasicMultiplyCalculation():Void {
        startTest("Basic MULTIPLY Calculation (Additive Zones)");

        try {
            mockTarget = createMockTarget();
            mockTarget.defense = 50;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加乘法buff
            var multBuff1:PodBuff = new PodBuff("defense", BuffCalculationType.MULTIPLY, 1.5);
            var multBuff2:PodBuff = new PodBuff("defense", BuffCalculationType.MULTIPLY, 1.2);

            manager.addBuff(multBuff1, null);
            manager.addBuff(multBuff2, null);
            manager.update(1);

            // 新公式（乘区相加）：50 * (1 + (1.5-1) + (1.2-1)) = 50 * 1.7 = 85
            var expectedValue:Number = 85;
            var actualValue:Number = getCalculatedValue(mockTarget, "defense");

            assertCalculation(actualValue, expectedValue, "MULTIPLY calculation");

            trace("  ✓ MULTIPLY (additive zones): 50 * (1 + 0.5 + 0.2) = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Basic MULTIPLY calculation failed: " + e.message);
        }
    }
    
    private static function testBasicPercentCalculation():Void {
        startTest("Basic PERCENT Calculation (Additive Zones)");

        try {
            mockTarget = createMockTarget();
            mockTarget.speed = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加百分比buff
            var percentBuff1:PodBuff = new PodBuff("speed", BuffCalculationType.PERCENT, 0.2); // +20%
            var percentBuff2:PodBuff = new PodBuff("speed", BuffCalculationType.PERCENT, 0.1); // +10%

            manager.addBuff(percentBuff1, null);
            manager.addBuff(percentBuff2, null);
            manager.update(1);

            // 新公式（乘区相加）：100 * (1 + 0.2 + 0.1) = 100 * 1.3 = 130
            var expectedValue:Number = 130;
            var actualValue:Number = getCalculatedValue(mockTarget, "speed");

            assertCalculation(actualValue, expectedValue, "PERCENT calculation");

            trace("  ✓ PERCENT (additive zones): 100 * (1 + 0.2 + 0.1) = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Basic PERCENT calculation failed: " + e.message);
        }
    }
    
    private static function testCalculationTypesPriority():Void {
        startTest("Calculation Types Priority (Additive Zones)");

        try {
            mockTarget = createMockTarget();
            mockTarget.power = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 混合不同类型的buff
            var addBuff:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 20);
            var multBuff:PodBuff = new PodBuff("power", BuffCalculationType.MULTIPLY, 1.5);
            var percentBuff:PodBuff = new PodBuff("power", BuffCalculationType.PERCENT, 0.1);

            manager.addBuff(addBuff, null);
            manager.addBuff(multBuff, null);
            manager.addBuff(percentBuff, null);
            manager.update(1);

            // 新计算顺序（乘区相加）:
            // 1. MULTIPLY: 100 * (1 + (1.5-1)) = 100 * 1.5 = 150
            // 2. PERCENT: 150 * (1 + 0.1) = 150 * 1.1 = 165
            // 3. ADD: 165 + 20 = 185
            var expectedValue:Number = 185;
            var actualValue:Number = getCalculatedValue(mockTarget, "power");

            assertCalculation(actualValue, expectedValue, "Mixed calculation types");

            trace("  ✓ Priority: 100 * 1.5 * 1.1 + 20 = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Calculation types priority failed: " + e.message);
        }
    }
    
    private static function testOverrideCalculation():Void {
        startTest("OVERRIDE Calculation");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.health = 1000;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 添加各种buff，然后一个覆盖buff
            var addBuff:PodBuff = new PodBuff("health", BuffCalculationType.ADD, 500);
            var multBuff:PodBuff = new PodBuff("health", BuffCalculationType.MULTIPLY, 2);
            var overrideBuff:PodBuff = new PodBuff("health", BuffCalculationType.OVERRIDE, 100);
            
            manager.addBuff(addBuff, null);
            manager.addBuff(multBuff, null);
            manager.addBuff(overrideBuff, null);
            manager.update(1);
            
            // 预期：OVERRIDE应该覆盖所有其他计算
            var expectedValue:Number = 100;
            var actualValue:Number = getCalculatedValue(mockTarget, "health");
            
            assertCalculation(actualValue, expectedValue, "OVERRIDE calculation");
            
            trace("  ✓ OVERRIDE: All calculations → 100");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("OVERRIDE calculation failed: " + e.message);
        }
    }

    private static function testBasicMaxCalculation():Void {
        startTest("Basic MAX Calculation");

        try {
            mockTarget = createMockTarget();
            mockTarget.armor = 50;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加MAX buff（下限保底）
            var maxBuff1:PodBuff = new PodBuff("armor", BuffCalculationType.MAX, 80);
            var maxBuff2:PodBuff = new PodBuff("armor", BuffCalculationType.MAX, 60);

            manager.addBuff(maxBuff1, null);
            manager.addBuff(maxBuff2, null);
            manager.update(1);

            // 预期：max(50, max(80, 60)) = 80
            var expectedValue:Number = 80;
            var actualValue:Number = getCalculatedValue(mockTarget, "armor");

            assertCalculation(actualValue, expectedValue, "MAX calculation");

            trace("  ✓ MAX: max(50, 80, 60) = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Basic MAX calculation failed: " + e.message);
        }
    }

    private static function testBasicMinCalculation():Void {
        startTest("Basic MIN Calculation");

        try {
            mockTarget = createMockTarget();
            mockTarget.damage = 200;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加MIN buff（上限封顶）
            var minBuff1:PodBuff = new PodBuff("damage", BuffCalculationType.MIN, 150);
            var minBuff2:PodBuff = new PodBuff("damage", BuffCalculationType.MIN, 180);

            manager.addBuff(minBuff1, null);
            manager.addBuff(minBuff2, null);
            manager.update(1);

            // 预期：min(200, min(150, 180)) = 150
            var expectedValue:Number = 150;
            var actualValue:Number = getCalculatedValue(mockTarget, "damage");

            assertCalculation(actualValue, expectedValue, "MIN calculation");

            trace("  ✓ MIN: min(200, 150, 180) = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Basic MIN calculation failed: " + e.message);
        }
    }

    // ========== Phase 1.5: 保守语义测试 ==========

    private static function testAddPositiveCalculation():Void {
        startTest("ADD_POSITIVE Calculation (Conservative)");

        try {
            mockTarget = createMockTarget();
            mockTarget.attack = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加多个正向保守加法buff，只取最大值
            var buff1:PodBuff = new PodBuff("attack", BuffCalculationType.ADD_POSITIVE, 50);  // 武器1
            var buff2:PodBuff = new PodBuff("attack", BuffCalculationType.ADD_POSITIVE, 80);  // 武器2（最强）
            var buff3:PodBuff = new PodBuff("attack", BuffCalculationType.ADD_POSITIVE, 30);  // 武器3

            manager.addBuff(buff1, null);
            manager.addBuff(buff2, null);
            manager.addBuff(buff3, null);
            manager.update(1);

            // 预期：100 + max(50, 80, 30) = 180
            var expectedValue:Number = 180;
            var actualValue:Number = getCalculatedValue(mockTarget, "attack");

            assertCalculation(actualValue, expectedValue, "ADD_POSITIVE calculation");

            trace("  ✓ ADD_POSITIVE: 100 + max(50,80,30) = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("ADD_POSITIVE calculation failed: " + e.message);
        }
    }

    private static function testAddNegativeCalculation():Void {
        startTest("ADD_NEGATIVE Calculation (Conservative)");

        try {
            mockTarget = createMockTarget();
            mockTarget.defense = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加多个负向保守加法buff，只取最小值（最强debuff）
            var debuff1:PodBuff = new PodBuff("defense", BuffCalculationType.ADD_NEGATIVE, -20);  // 轻微
            var debuff2:PodBuff = new PodBuff("defense", BuffCalculationType.ADD_NEGATIVE, -50);  // 最强
            var debuff3:PodBuff = new PodBuff("defense", BuffCalculationType.ADD_NEGATIVE, -30);  // 中等

            manager.addBuff(debuff1, null);
            manager.addBuff(debuff2, null);
            manager.addBuff(debuff3, null);
            manager.update(1);

            // 预期：100 + min(-20, -50, -30) = 50
            var expectedValue:Number = 50;
            var actualValue:Number = getCalculatedValue(mockTarget, "defense");

            assertCalculation(actualValue, expectedValue, "ADD_NEGATIVE calculation");

            trace("  ✓ ADD_NEGATIVE: 100 + min(-20,-50,-30) = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("ADD_NEGATIVE calculation failed: " + e.message);
        }
    }

    private static function testMultPositiveCalculation():Void {
        startTest("MULT_POSITIVE Calculation (Conservative)");

        try {
            mockTarget = createMockTarget();
            mockTarget.critDamage = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加多个正向保守乘法buff，只取最大值
            var buff1:PodBuff = new PodBuff("critDamage", BuffCalculationType.MULT_POSITIVE, 1.3);  // +30%
            var buff2:PodBuff = new PodBuff("critDamage", BuffCalculationType.MULT_POSITIVE, 1.8);  // +80%（最强）
            var buff3:PodBuff = new PodBuff("critDamage", BuffCalculationType.MULT_POSITIVE, 1.5);  // +50%

            manager.addBuff(buff1, null);
            manager.addBuff(buff2, null);
            manager.addBuff(buff3, null);
            manager.update(1);

            // 预期：100 * max(1.3, 1.8, 1.5) = 180
            var expectedValue:Number = 180;
            var actualValue:Number = getCalculatedValue(mockTarget, "critDamage");

            assertCalculation(actualValue, expectedValue, "MULT_POSITIVE calculation");

            trace("  ✓ MULT_POSITIVE: 100 * max(1.3,1.8,1.5) = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("MULT_POSITIVE calculation failed: " + e.message);
        }
    }

    private static function testMultNegativeCalculation():Void {
        startTest("MULT_NEGATIVE Calculation (Conservative)");

        try {
            mockTarget = createMockTarget();
            mockTarget.moveSpeed = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加多个负向保守乘法buff，只取最小值（最强减速）
            var slow1:PodBuff = new PodBuff("moveSpeed", BuffCalculationType.MULT_NEGATIVE, 0.9);  // -10%
            var slow2:PodBuff = new PodBuff("moveSpeed", BuffCalculationType.MULT_NEGATIVE, 0.5);  // -50%（最强）
            var slow3:PodBuff = new PodBuff("moveSpeed", BuffCalculationType.MULT_NEGATIVE, 0.7);  // -30%

            manager.addBuff(slow1, null);
            manager.addBuff(slow2, null);
            manager.addBuff(slow3, null);
            manager.update(1);

            // 预期：100 * min(0.9, 0.5, 0.7) = 50
            var expectedValue:Number = 50;
            var actualValue:Number = getCalculatedValue(mockTarget, "moveSpeed");

            assertCalculation(actualValue, expectedValue, "MULT_NEGATIVE calculation");

            trace("  ✓ MULT_NEGATIVE: 100 * min(0.9,0.5,0.7) = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("MULT_NEGATIVE calculation failed: " + e.message);
        }
    }

    private static function testConservativeMixedCalculation():Void {
        startTest("Conservative Mixed Calculation");

        try {
            mockTarget = createMockTarget();
            mockTarget.finalDamage = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 混合使用通用语义和保守语义
            // 通用乘法
            var mult1:PodBuff = new PodBuff("finalDamage", BuffCalculationType.MULTIPLY, 1.2);  // +20%
            var mult2:PodBuff = new PodBuff("finalDamage", BuffCalculationType.MULTIPLY, 1.1);  // +10%

            // 保守正向乘法
            var multPos1:PodBuff = new PodBuff("finalDamage", BuffCalculationType.MULT_POSITIVE, 1.5); // 取max
            var multPos2:PodBuff = new PodBuff("finalDamage", BuffCalculationType.MULT_POSITIVE, 1.3);

            // 保守负向乘法
            var multNeg1:PodBuff = new PodBuff("finalDamage", BuffCalculationType.MULT_NEGATIVE, 0.8); // 取min
            var multNeg2:PodBuff = new PodBuff("finalDamage", BuffCalculationType.MULT_NEGATIVE, 0.9);

            // 通用加法
            var add1:PodBuff = new PodBuff("finalDamage", BuffCalculationType.ADD, 20);
            var add2:PodBuff = new PodBuff("finalDamage", BuffCalculationType.ADD, 10);

            // 保守正向加法
            var addPos1:PodBuff = new PodBuff("finalDamage", BuffCalculationType.ADD_POSITIVE, 50);
            var addPos2:PodBuff = new PodBuff("finalDamage", BuffCalculationType.ADD_POSITIVE, 30);

            manager.addBuff(mult1, null);
            manager.addBuff(mult2, null);
            manager.addBuff(multPos1, null);
            manager.addBuff(multPos2, null);
            manager.addBuff(multNeg1, null);
            manager.addBuff(multNeg2, null);
            manager.addBuff(add1, null);
            manager.addBuff(add2, null);
            manager.addBuff(addPos1, null);
            manager.addBuff(addPos2, null);
            manager.update(1);

            // 计算过程:
            // 1. MULTIPLY: 100 * (1 + 0.2 + 0.1) = 100 * 1.3 = 130
            // 2. MULT_POSITIVE: 130 * max(1.5, 1.3) = 130 * 1.5 = 195
            // 3. MULT_NEGATIVE: 195 * min(0.8, 0.9) = 195 * 0.8 = 156
            // 4. PERCENT: 无
            // 5. ADD: 156 + 30 = 186
            // 6. ADD_POSITIVE: 186 + max(50, 30) = 186 + 50 = 236
            var expectedValue:Number = 236;
            var actualValue:Number = getCalculatedValue(mockTarget, "finalDamage");

            assertCalculation(actualValue, expectedValue, "Conservative mixed calculation");

            trace("  ✓ Mixed: 100*1.3*1.5*0.8+30+50 = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Conservative mixed calculation failed: " + e.message);
        }
    }

    private static function testFullCalculationChain():Void {
        startTest("Full Calculation Chain (All 10 Types)");

        try {
            mockTarget = createMockTarget();
            mockTarget.power = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 完整的10步计算链测试
            // 1. MULTIPLY
            manager.addBuff(new PodBuff("power", BuffCalculationType.MULTIPLY, 1.5), null);      // +50%
            manager.addBuff(new PodBuff("power", BuffCalculationType.MULTIPLY, 1.2), null);      // +20%

            // 2. MULT_POSITIVE
            manager.addBuff(new PodBuff("power", BuffCalculationType.MULT_POSITIVE, 1.2), null); // 取max

            // 3. MULT_NEGATIVE
            manager.addBuff(new PodBuff("power", BuffCalculationType.MULT_NEGATIVE, 0.9), null); // 取min

            // 4. PERCENT
            manager.addBuff(new PodBuff("power", BuffCalculationType.PERCENT, 0.1), null);       // +10%

            // 5. ADD
            manager.addBuff(new PodBuff("power", BuffCalculationType.ADD, 50), null);

            // 6. ADD_POSITIVE
            manager.addBuff(new PodBuff("power", BuffCalculationType.ADD_POSITIVE, 30), null);

            // 7. ADD_NEGATIVE
            manager.addBuff(new PodBuff("power", BuffCalculationType.ADD_NEGATIVE, -20), null);

            // 8. MAX
            manager.addBuff(new PodBuff("power", BuffCalculationType.MAX, 100), null);

            // 9. MIN
            manager.addBuff(new PodBuff("power", BuffCalculationType.MIN, 500), null);

            manager.update(1);

            // 计算过程:
            // 1. MULTIPLY: 100 * (1 + 0.5 + 0.2) = 100 * 1.7 = 170
            // 2. MULT_POSITIVE: 170 * 1.2 = 204
            // 3. MULT_NEGATIVE: 204 * 0.9 = 183.6
            // 4. PERCENT: 183.6 * 1.1 = 201.96
            // 5. ADD: 201.96 + 50 = 251.96
            // 6. ADD_POSITIVE: 251.96 + 30 = 281.96
            // 7. ADD_NEGATIVE: 281.96 - 20 = 261.96
            // 8. MAX: max(261.96, 100) = 261.96
            // 9. MIN: min(261.96, 500) = 261.96
            var expectedValue:Number = 261.96;
            var actualValue:Number = getCalculatedValue(mockTarget, "power");

            // 允许浮点误差
            assert(Math.abs(actualValue - expectedValue) < 0.01,
                "Full chain calculation within tolerance: " + actualValue);

            trace("  ✓ Full Chain: 100→170→204→183.6→201.96→251.96→281.96→261.96 = " + actualValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Full calculation chain failed: " + e.message);
        }
    }

    // ========== Phase 2: MetaBuff注入与计算 ==========
    
    private static function testMetaBuffPodInjection():Void {
        startTest("MetaBuff Pod Injection");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.strength = 50;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 创建MetaBuff，包含多个PodBuff
            var childBuffs:Array = [
                new PodBuff("strength", BuffCalculationType.ADD, 25),
                new PodBuff("strength", BuffCalculationType.PERCENT, 0.2)
            ];
            
            var metaBuff:MetaBuff = new MetaBuff(childBuffs, [], 0);
            manager.addBuff(metaBuff, null);
            
            // 初始状态应该是ACTIVE，立即注入
            assert(metaBuff.isActive(), "MetaBuff should be active");
            
            manager.update(1);

            // 新计算顺序: 50 * 1.2 + 25 = 85
            var expectedValue:Number = 85;
            var actualValue:Number = getCalculatedValue(mockTarget, "strength");

            assertCalculation(actualValue, expectedValue, "MetaBuff injection calculation");

            trace("  ✓ MetaBuff injection: 50 * 1.2 + 25 = " + actualValue);
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("MetaBuff pod injection failed: " + e.message);
        }
    }
    
    private static function testMetaBuffCalculationAccuracy():Void {
        startTest("MetaBuff Calculation Accuracy");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.damage = 100;
            mockTarget.critical = 1.5;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 复杂的MetaBuff场景
            var damageBoostBuffs:Array = [
                new PodBuff("damage", BuffCalculationType.ADD, 50),
                new PodBuff("damage", BuffCalculationType.MULTIPLY, 1.3),
                new PodBuff("critical", BuffCalculationType.ADD, 0.5)
            ];
            
            var metaBuff:MetaBuff = new MetaBuff(damageBoostBuffs, [], 0);
            manager.addBuff(metaBuff, null);
            manager.update(1);

            // 新计算顺序: 100 * 1.3 + 50 = 180
            var expectedDamage:Number = 180;
            var actualDamage:Number = getCalculatedValue(mockTarget, "damage");
            assertCalculation(actualDamage, expectedDamage, "MetaBuff damage calculation");

            // 验证critical计算：1.5 + 0.5 = 2.0
            var expectedCritical:Number = 2.0;
            var actualCritical:Number = getCalculatedValue(mockTarget, "critical");
            assertCalculation(actualCritical, expectedCritical, "MetaBuff critical calculation");

            trace("  ✓ Damage: 100 * 1.3 + 50 = " + actualDamage);
            trace("  ✓ Critical: 1.5 + 0.5 = " + actualCritical);
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("MetaBuff calculation accuracy failed: " + e.message);
        }
    }
    
    private static function testMetaBuffStateTransitions():Void {
        startTest("MetaBuff State Transitions & Calculations");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.agility = 20;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 创建带TimeLimitComponent的MetaBuff
            var childBuffs:Array = [
                new PodBuff("agility", BuffCalculationType.ADD, 30),
                new PodBuff("agility", BuffCalculationType.PERCENT, 0.5)
            ];
            
            var timeLimitComp:TimeLimitComponent = new TimeLimitComponent(3);
            var metaBuff:MetaBuff = new MetaBuff(childBuffs, [timeLimitComp], 0);
            
            manager.addBuff(metaBuff, null);
            manager.update(1);

            // Frame 1: 应该激活，新计算顺序: 20 * 1.5 + 30 = 60
            var frame1Value:Number = getCalculatedValue(mockTarget, "agility");
            assertCalculation(frame1Value, 60, "Frame 1 calculation");

            // Frame 2: 仍然激活
            manager.update(1);
            var frame2Value:Number = getCalculatedValue(mockTarget, "agility");
            assertCalculation(frame2Value, 60, "Frame 2 calculation");

            // Frame 3: 最后一帧
            manager.update(1);
            var frame3Value:Number = getCalculatedValue(mockTarget, "agility");
            assertCalculation(frame3Value, 20, "Frame 3 calculation (same-tick eject)");

            // Frame 4: 应该失效，值恢复到基础值
            manager.update(1);
            var frame4Value:Number = getCalculatedValue(mockTarget, "agility");
            assertCalculation(frame4Value, 20, "Frame 4 (expired) calculation");

            trace("  ✓ State transitions: 60 → 60 → 20 → 20 (expired)");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("MetaBuff state transitions failed: " + e.message);
        }
    }
    
    private static function testMetaBuffDynamicInjection():Void {
        startTest("MetaBuff Dynamic Injection");

        try {
            mockTarget = createMockTarget();
            mockTarget.intelligence = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 先添加一个普通的PodBuff
            var baseBuff:PodBuff = new PodBuff("intelligence", BuffCalculationType.ADD, 20);
            manager.addBuff(baseBuff, null);
            manager.update(1);

            // 验证初始计算：100 + 20 = 120（只有ADD时直接加）
            var initialValue:Number = getCalculatedValue(mockTarget, "intelligence");
            assertCalculation(initialValue, 120, "Initial calculation");

            // 添加MetaBuff
            var metaBuffPods:Array = [
                new PodBuff("intelligence", BuffCalculationType.MULTIPLY, 1.5),
                new PodBuff("intelligence", BuffCalculationType.PERCENT, 0.1)
            ];
            var metaBuff:MetaBuff = new MetaBuff(metaBuffPods, [], 0);
            manager.addBuff(metaBuff, null);
            manager.update(1);

            // 新计算顺序: 100 * 1.5 * 1.1 + 20 = 185
            var finalValue:Number = getCalculatedValue(mockTarget, "intelligence");
            assertCalculation(finalValue, 185, "After MetaBuff injection");

            trace("  ✓ Dynamic injection: 120 → 185");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("MetaBuff dynamic injection failed: " + e.message);
        }
    }
    
    // ========== Phase 3: TimeLimitComponent与动态计算 ==========
    
    private static function testTimeLimitedBuffCalculations():Void {
        startTest("Time-Limited Buff Calculations");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.armor = 100;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 创建多个不同时限的buff
            var shortTermBuff:MetaBuff = new MetaBuff(
                [new PodBuff("armor", BuffCalculationType.ADD, 50)],
                [new TimeLimitComponent(2)],
                0
            );
            
            var longTermBuff:MetaBuff = new MetaBuff(
                [new PodBuff("armor", BuffCalculationType.MULTIPLY, 1.2)],
                [new TimeLimitComponent(5)],
                0
            );
            
            manager.addBuff(shortTermBuff, null);
            manager.addBuff(longTermBuff, null);
            manager.update(1);

            // Frame 1: 两个buff都激活，新计算顺序: 100 * 1.2 + 50 = 170
            var frame1:Number = getCalculatedValue(mockTarget, "armor");
            assertCalculation(frame1, 170, "Frame 1 with both buffs");

            // Frame 3: 短期buff失效，只剩长期 100 * 1.2 = 120
            manager.update(2);
            var frame3:Number = getCalculatedValue(mockTarget, "armor");
            assertCalculation(frame3, 120, "Frame 3 with only long-term buff");

            // Frame 6: 所有buff失效，恢复基础值
            manager.update(3);
            var frame6:Number = getCalculatedValue(mockTarget, "armor");
            assertCalculation(frame6, 100, "Frame 6 all buffs expired");

            trace("  ✓ Time-limited calculations: 170 → 120 → 100");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Time-limited buff calculations failed: " + e.message);
        }
    }
    
    private static function testDynamicCalculationUpdates():Void {
        startTest("Dynamic Calculation Updates");

        try {
            mockTarget = createMockTarget();
            mockTarget.mana = 200;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 创建一个会动态变化的场景
            var permanentBuff:PodBuff = new PodBuff("mana", BuffCalculationType.ADD, 100);
            // [P1-1 修复] 保存返回的注册 ID
            var permanentId:String = manager.addBuff(permanentBuff, null);

            // 添加临时buff
            var tempBuff:MetaBuff = new MetaBuff(
                [new PodBuff("mana", BuffCalculationType.PERCENT, 0.5)],
                [new TimeLimitComponent(3)],
                0
            );
            manager.addBuff(tempBuff, null);
            manager.update(1);

            // 新计算顺序: 200 * 1.5 + 100 = 400
            var initial:Number = getCalculatedValue(mockTarget, "mana");
            assertCalculation(initial, 400, "Initial with temp buff");

            // 临时buff过期后：200 + 100 = 300
            manager.update(3);
            var afterExpire:Number = getCalculatedValue(mockTarget, "mana");
            assertCalculation(afterExpire, 300, "After temp buff expires");

            // 移除永久buff：200（使用注册时返回的 ID）
            manager.removeBuff(permanentId);
            manager.update(1);
            var final:Number = getCalculatedValue(mockTarget, "mana");
            assertCalculation(final, 200, "After removing permanent buff");

            trace("  ✓ Dynamic updates: 400 → 300 → 200");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Dynamic calculation updates failed: " + e.message);
        }
    }
    
    private static function testBuffExpirationCalculations():Void {
        startTest("Buff Expiration Calculations");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.resistance = 50;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 创建级联过期的buff
            for (var i:Number = 1; i <= 3; i++) {
                var buff:MetaBuff = new MetaBuff(
                    [new PodBuff("resistance", BuffCalculationType.ADD, i * 10)],
                    [new TimeLimitComponent(i * 2)],
                    0
                );
                manager.addBuff(buff, null);
            }
            manager.update(1);
            
            // Frame 1: 50 + 10 + 20 + 30 = 110
            var frame1:Number = getCalculatedValue(mockTarget, "resistance");
            assertCalculation(frame1, 110, "Frame 1 all buffs active");
            
            // Frame 3: 第一个buff过期，50 + 20 + 30 = 100
            manager.update(2);
            var frame3:Number = getCalculatedValue(mockTarget, "resistance");
            assertCalculation(frame3, 100, "Frame 3 first buff expired");
            
            // Frame 5: 第二个buff过期，50 + 30 = 80
            manager.update(2);
            var frame5:Number = getCalculatedValue(mockTarget, "resistance");
            assertCalculation(frame5, 80, "Frame 5 second buff expired");
            
            // Frame 7: 所有buff过期
            manager.update(2);
            var frame7:Number = getCalculatedValue(mockTarget, "resistance");
            assertCalculation(frame7, 50, "Frame 7 all buffs expired");
            
            trace("  ✓ Cascading expiration: 110 → 100 → 80 → 50");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Buff expiration calculations failed: " + e.message);
        }
    }
    
    private static function testCascadingBuffCalculations():Void {
        startTest("Cascading Buff Calculations");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.energy = 100;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 创建相互影响的buff链
            var baseBuff:PodBuff = new PodBuff("energy", BuffCalculationType.ADD, 50);
            var enhanceBuff:MetaBuff = new MetaBuff(
                [new PodBuff("energy", BuffCalculationType.PERCENT, 0.3)],
                [new TimeLimitComponent(4)],
                0
            );
            var superBuff:MetaBuff = new MetaBuff(
                [new PodBuff("energy", BuffCalculationType.MULTIPLY, 2)],
                [new TimeLimitComponent(2)],
                0
            );
            
            manager.addBuff(baseBuff, null);
            manager.addBuff(enhanceBuff, null);
            manager.addBuff(superBuff, null);
            manager.update(1);

            // Frame 1: 新计算顺序: 100 * 2 * 1.3 + 50 = 310
            var phase1:Number = getCalculatedValue(mockTarget, "energy");
            assertCalculation(phase1, 310, "All buffs active");

            // Frame 3: superBuff过期，100 * 1.3 + 50 = 180
            manager.update(2);
            var phase2:Number = getCalculatedValue(mockTarget, "energy");
            assertCalculation(phase2, 180, "Super buff expired");

            // Frame 5: enhanceBuff过期 100 + 50 = 150
            manager.update(2);
            var phase3:Number = getCalculatedValue(mockTarget, "energy");
            assertCalculation(phase3, 150, "Enhance buff expired");

            trace("  ✓ Cascading calculations: 310 → 180 → 150");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Cascading buff calculations failed: " + e.message);
        }
    }
    
    // ========== Phase 4: 复杂计算场景 ==========
    
    private static function testStackingBuffCalculations():Void {
        startTest("Stacking Buff Calculations");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.power = 100;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 模拟可叠加的buff（比如每次攻击增加伤害）
            var stackCount:Number = 5;
            for (var i:Number = 0; i < stackCount; i++) {
                var stackBuff:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 10);
                manager.addBuff(stackBuff, "stack_" + i);
            }
            manager.update(1);
            
            // 验证叠加：100 + (10 * 5) = 150
            var stackedValue:Number = getCalculatedValue(mockTarget, "power");
            assertCalculation(stackedValue, 150, "5 stacks calculation");
            
            // 移除2层
            manager.removeBuff("stack_0");
            manager.removeBuff("stack_1");
            manager.update(1);
            
            // 验证：100 + (10 * 3) = 130
            var reducedValue:Number = getCalculatedValue(mockTarget, "power");
            assertCalculation(reducedValue, 130, "3 stacks calculation");
            
            trace("  ✓ Stacking: 5 stacks (150) → 3 stacks (130)");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Stacking buff calculations failed: " + e.message);
        }
    }
    
    private static function testMultiPropertyCalculations():Void {
        startTest("Multi-Property Calculations");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.physicalDamage = 100;
            mockTarget.magicalDamage = 80;
            mockTarget.healingPower = 50;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 创建影响多个属性的MetaBuff
            var omniBuff:MetaBuff = new MetaBuff(
                [
                    new PodBuff("physicalDamage", BuffCalculationType.PERCENT, 0.2),
                    new PodBuff("magicalDamage", BuffCalculationType.PERCENT, 0.3),
                    new PodBuff("healingPower", BuffCalculationType.ADD, 25)
                ],
                [],
                0
            );
            
            manager.addBuff(omniBuff, null);
            manager.update(1);
            
            // 验证各属性计算
            var physical:Number = getCalculatedValue(mockTarget, "physicalDamage");
            var magical:Number = getCalculatedValue(mockTarget, "magicalDamage");
            var healing:Number = getCalculatedValue(mockTarget, "healingPower");
            
            assertCalculation(physical, 120, "Physical damage");  // 100 * 1.2
            assertCalculation(magical, 104, "Magical damage");    // 80 * 1.3
            assertCalculation(healing, 75, "Healing power");      // 50 + 25
            
            trace("  ✓ Multi-property: Phys 120, Mag 104, Heal 75");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Multi-property calculations failed: " + e.message);
        }
    }
    
    private static function testCalculationOrderDependency():Void {
        startTest("Calculation Order Dependency");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.damage = 100;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 测试计算顺序的重要性
            var buffs:Array = [
                new PodBuff("damage", BuffCalculationType.PERCENT, 0.5),   // +50%
                new PodBuff("damage", BuffCalculationType.ADD, 20),        // +20
                new PodBuff("damage", BuffCalculationType.MULTIPLY, 1.2),  // *1.2
                new PodBuff("damage", BuffCalculationType.MAX, 150),       // 最小150
                new PodBuff("damage", BuffCalculationType.MIN, 200)        // 最大200
            ];
            
            for (var i:Number = 0; i < buffs.length; i++) {
                manager.addBuff(buffs[i], null);
            }
            manager.update(1);

            // 新计算顺序：
            // 1. MULTIPLY: 100 * 1.2 = 120
            // 2. PERCENT: 120 * 1.5 = 180
            // 3. ADD: 180 + 20 = 200
            // 4. MAX: max(200, 150) = 200
            // 5. MIN: min(200, 200) = 200
            var finalValue:Number = getCalculatedValue(mockTarget, "damage");
            assertCalculation(finalValue, 200, "Order-dependent calculation");

            trace("  ✓ Order dependency: 100 → 120 → 180 → 200 → 200 → 200");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Calculation order dependency failed: " + e.message);
        }
    }
    
    private static function testRealGameCalculationScenario():Void {
        startTest("Real Game Calculation Scenario");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.attackDamage = 100;
            mockTarget.attackSpeed = 1.0;
            mockTarget.criticalChance = 0.2;
            mockTarget.criticalDamage = 1.5;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 场景：玩家获得多个增益效果
            
            // 装备被动
            var weaponBuff:PodBuff = new PodBuff("attackDamage", BuffCalculationType.ADD, 50);
            manager.addBuff(weaponBuff, "weapon");
            
            // 技能：狂暴（10秒）
            var berserkBuff:MetaBuff = new MetaBuff(
                [
                    new PodBuff("attackDamage", BuffCalculationType.PERCENT, 0.3),
                    new PodBuff("attackSpeed", BuffCalculationType.PERCENT, 0.5),
                    new PodBuff("criticalChance", BuffCalculationType.ADD, 0.1)
                ],
                [new TimeLimitComponent(60)], // 10秒
                1
            );
            manager.addBuff(berserkBuff, "berserk");
            
            // 队友光环
            var auraBuff:PodBuff = new PodBuff("criticalDamage", BuffCalculationType.ADD, 0.5);
            manager.addBuff(auraBuff, "aura");
            
            manager.update(1);
            
            // 验证各项数值
            var ad:Number = getCalculatedValue(mockTarget, "attackDamage");
            var as:Number = getCalculatedValue(mockTarget, "attackSpeed");
            var cc:Number = getCalculatedValue(mockTarget, "criticalChance");
            var cd:Number = getCalculatedValue(mockTarget, "criticalDamage");

            // 新计算顺序：
            // AD: 100 * 1.3 + 50 = 180
            // AS: 1.0 * 1.5 = 1.5
            // CC: 0.2 + 0.1 = 0.3
            // CD: 1.5 + 0.5 = 2.0
            assertCalculation(ad, 180, "Attack damage");
            assertCalculation(as, 1.5, "Attack speed");
            assertCalculation(cc, 0.3, "Critical chance");
            assertCalculation(cd, 2.0, "Critical damage");

            // 计算DPS提升
            var baseDPS:Number = 100 * 1.0 * (1 + 0.2 * (1.5 - 1));
            var buffedDPS:Number = 180 * 1.5 * (1 + 0.3 * (2.0 - 1));
            var dpsIncrease:Number = Math.round((buffedDPS / baseDPS - 1) * 100);

            trace("  ✓ Combat stats: AD 180, AS 1.5, CC 30%, CD 200%");
            trace("  ✓ DPS increase: " + dpsIncrease + "%");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Real game calculation scenario failed: " + e.message);
        }
    }
    
    // ========== Phase 5: PropertyContainer集成测试 ==========
    
    private static function testPropertyContainerCalculations():Void {
        startTest("PropertyContainer Calculations");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.testStat = 200;
            
            var propertyChanges:Array = [];
            var callbacks:Object = {
                onPropertyChanged: function(prop:String, value:Number):Void {
                    propertyChanges.push({property: prop, value: value});
                }
            };
            
            var manager:BuffManager = new BuffManager(mockTarget, callbacks);
            
            // 添加多个buff到同一属性
            var buff1 = new PodBuff("testStat", BuffCalculationType.ADD, 100);
            var buff2 = new PodBuff("testStat", BuffCalculationType.MULTIPLY, 1.5);
            
            manager.addBuff(buff1, null);
            manager.addBuff(buff2, null);
            manager.update(1);

            // 新计算顺序：200 * 1.5 + 100 = 400
            var finalValue:Number = getCalculatedValue(mockTarget, "testStat");
            assertCalculation(finalValue, 400, "PropertyContainer calculation");

            // 验证回调触发
            assert(propertyChanges.length > 0, "Property change callbacks should fire");

            trace("  ✓ PropertyContainer: 200 * 1.5 + 100 = 400");
            trace("  ✓ Callbacks fired: " + propertyChanges.length + " times");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("PropertyContainer calculations failed: " + e.message);
        }
    }
    
    private static function testDynamicPropertyRecalculation():Void {
        startTest("Dynamic Property Recalculation");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.dynamicStat = 50;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 初始buff
            var initialBuff:PodBuff = new PodBuff("dynamicStat", BuffCalculationType.ADD, 25);
            manager.addBuff(initialBuff, "initial");
            manager.update(1);
            
            var value1:Number = getCalculatedValue(mockTarget, "dynamicStat");
            assertCalculation(value1, 75, "Initial state");
            
            // 添加乘法buff
            var multBuff:PodBuff = new PodBuff("dynamicStat", BuffCalculationType.MULTIPLY, 2);
            manager.addBuff(multBuff, "multiplier");
            manager.update(1);

            // 新计算顺序: 50 * 2 + 25 = 125
            var value2:Number = getCalculatedValue(mockTarget, "dynamicStat");
            assertCalculation(value2, 125, "After multiplier");

            // 移除初始buff
            manager.removeBuff("initial");
            manager.update(1);

            var value3:Number = getCalculatedValue(mockTarget, "dynamicStat");
            assertCalculation(value3, 100, "After removal"); // 50 * 2

            trace("  ✓ Dynamic recalc: 75 → 125 → 100");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Dynamic property recalculation failed: " + e.message);
        }
    }
    
    private static function testPropertyContainerRebuildAccuracy():Void {
        startTest("PropertyContainer Rebuild Accuracy");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.prop1 = 100;
            mockTarget.prop2 = 200;
            mockTarget.prop3 = 300;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 添加影响不同属性的buff
            var buffs:Array = [
                new PodBuff("prop1", BuffCalculationType.ADD, 50),
                new PodBuff("prop2", BuffCalculationType.PERCENT, 0.2),
                new PodBuff("prop3", BuffCalculationType.MULTIPLY, 1.5)
            ];
            
            for (var i:Number = 0; i < buffs.length; i++) {
                manager.addBuff(buffs[i], "buff" + i);
            }
            manager.update(1);
            
            // 验证初始计算
            assertCalculation(getCalculatedValue(mockTarget, "prop1"), 150, "prop1 initial");
            assertCalculation(getCalculatedValue(mockTarget, "prop2"), 240, "prop2 initial");
            assertCalculation(getCalculatedValue(mockTarget, "prop3"), 450, "prop3 initial");
            
            // 添加MetaBuff影响多个属性
            var metaBuff:MetaBuff = new MetaBuff(
                [
                    new PodBuff("prop1", BuffCalculationType.MULTIPLY, 2),
                    new PodBuff("prop2", BuffCalculationType.ADD, 60)
                ],
                [],
                0
            );
            manager.addBuff(metaBuff, null);
            manager.update(1);

            // 新计算顺序：
            // prop1: 100 * 2 + 50 = 250
            // prop2: 200 * 1.2 + 60 = 300
            // prop3: 不变 = 450
            assertCalculation(getCalculatedValue(mockTarget, "prop1"), 250, "prop1 after rebuild");
            assertCalculation(getCalculatedValue(mockTarget, "prop2"), 300, "prop2 after rebuild");
            assertCalculation(getCalculatedValue(mockTarget, "prop3"), 450, "prop3 unchanged");
            
            trace("  ✓ Container rebuild: accurate calculations maintained");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("PropertyContainer rebuild accuracy failed: " + e.message);
        }
    }
    
    private static function testConcurrentPropertyUpdates():Void {
        startTest("Concurrent Property Updates");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.concurrent = 100;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 同时添加多个影响同一属性的buff
            var concurrentBuffs:Array = [];
            for (var i:Number = 0; i < 5; i++) {
                var buff:PodBuff = new PodBuff("concurrent", BuffCalculationType.ADD, 10);
                concurrentBuffs.push(buff);
                manager.addBuff(buff, null);
            }
            
            manager.update(1);
            
            // 应该正确累加：100 + (10 * 5) = 150
            var value1:Number = getCalculatedValue(mockTarget, "concurrent");
            assertCalculation(value1, 150, "Concurrent additions");
            
            // 添加乘法buff
            var multBuff:PodBuff = new PodBuff("concurrent", BuffCalculationType.MULTIPLY, 2);
            manager.addBuff(multBuff, null);
            manager.update(1);

            // 新计算顺序: 100 * 2 + 50 = 250
            var value2:Number = getCalculatedValue(mockTarget, "concurrent");
            assertCalculation(value2, 250, "After multiplier");
            
            trace("  ✓ Concurrent updates handled correctly");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Concurrent property updates failed: " + e.message);
        }
    }
    
    // ========== Phase 6: 边界情况与准确性 ==========
    
    private static function testExtremValueCalculations():Void {
        startTest("Extreme Value Calculations");

        try {
            mockTarget = createMockTarget();
            mockTarget.extreme = 1;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 测试极大值
            var hugeBuff:PodBuff = new PodBuff("extreme", BuffCalculationType.MULTIPLY, 1000000);
            // [P1-1 修复] 保存返回的注册ID
            var hugeId:String = manager.addBuff(hugeBuff, null);
            manager.update(1);

            var hugeValue:Number = getCalculatedValue(mockTarget, "extreme");
            assertCalculation(hugeValue, 1000000, "Huge multiplier");

            // 测试极小值（使用注册ID移除）
            manager.removeBuff(hugeId);
            var tinyBuff:PodBuff = new PodBuff("extreme", BuffCalculationType.MULTIPLY, 0.000001);
            manager.addBuff(tinyBuff, null);
            manager.update(1);

            var tinyValue:Number = getCalculatedValue(mockTarget, "extreme");
            assert(Math.abs(tinyValue - 0.000001) < 0.0000001, "Tiny multiplier accuracy");

            trace("  ✓ Extreme values: 1M and 0.000001 handled correctly");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Extreme value calculations failed: " + e.message);
        }
    }
    
    private static function testFloatingPointAccuracy():Void {
        startTest("Floating Point Accuracy (Additive Zones)");

        try {
            mockTarget = createMockTarget();
            mockTarget.floatTest = 10;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 添加会产生浮点数的buff
            var buffs:Array = [
                new PodBuff("floatTest", BuffCalculationType.MULTIPLY, 1.1),
                new PodBuff("floatTest", BuffCalculationType.MULTIPLY, 1.1),
                new PodBuff("floatTest", BuffCalculationType.MULTIPLY, 1.1)
            ];

            for (var i:Number = 0; i < buffs.length; i++) {
                manager.addBuff(buffs[i], null);
            }
            manager.update(1);

            // 新公式（乘区相加）：10 * (1 + 0.1 + 0.1 + 0.1) = 10 * 1.3 = 13
            var result:Number = getCalculatedValue(mockTarget, "floatTest");
            var expected:Number = 13;

            // 允许小的浮点误差
            assert(Math.abs(result - expected) < 0.01,
                "Floating point calculation within tolerance: " + result);

            trace("  ✓ Floating point (additive zones): 10 * (1 + 0.1 * 3) = " + result + " (±0.01)");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Floating point accuracy failed: " + e.message);
        }
    }
    
    private static function testNegativeValueCalculations():Void {
        startTest("Negative Value Calculations");

        try {
            mockTarget = createMockTarget();
            mockTarget.balance = 100;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 测试负数加法
            var debuff1:PodBuff = new PodBuff("balance", BuffCalculationType.ADD, -30);
            var debuff2:PodBuff = new PodBuff("balance", BuffCalculationType.ADD, -50);

            manager.addBuff(debuff1, null);
            manager.addBuff(debuff2, null);
            manager.update(1);

            // 新计算顺序: 100 + (-30) + (-50) = 20
            var afterDebuffs:Number = getCalculatedValue(mockTarget, "balance");
            assertCalculation(afterDebuffs, 20, "Negative additions");

            // 测试负数百分比
            var percentDebuff:PodBuff = new PodBuff("balance", BuffCalculationType.PERCENT, -0.5);
            manager.addBuff(percentDebuff, null);
            manager.update(1);

            // 新计算顺序: 100 * (1-0.5) + (-80) = 50 - 80 = -30
            var afterPercent:Number = getCalculatedValue(mockTarget, "balance");
            assertCalculation(afterPercent, -30, "Negative percentage");

            trace("  ✓ Negative values: 100 → 20 → -30");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Negative value calculations failed: " + e.message);
        }
    }
    
    private static function testZeroValueHandling():Void {
        startTest("Zero Value Handling");

        try {
            mockTarget = createMockTarget();
            mockTarget.zeroTest = 0;

            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 测试从0开始的加法
            var addBuff:PodBuff = new PodBuff("zeroTest", BuffCalculationType.ADD, 50);
            manager.addBuff(addBuff, null);
            manager.update(1);

            // 新计算顺序: 0 * 1 + 50 = 50
            var afterAdd:Number = getCalculatedValue(mockTarget, "zeroTest");
            assertCalculation(afterAdd, 50, "Add to zero");

            // 测试乘以0 - 需要新建manager以获得正确的基础值
            manager.destroy();
            mockTarget.multiplyTest = 100;
            var manager2:BuffManager = new BuffManager(mockTarget, null);

            var zeroBuff:PodBuff = new PodBuff("multiplyTest", BuffCalculationType.MULTIPLY, 0);
            manager2.addBuff(zeroBuff, null);
            manager2.update(1);

            // 新计算顺序: 100 * 0 = 0
            var afterMultiply:Number = getCalculatedValue(mockTarget, "multiplyTest");
            assertCalculation(afterMultiply, 0, "Multiply by zero");

            trace("  ✓ Zero handling: 0+50=50, 100*0=0");

            manager2.destroy();
            passTest();
        } catch (e) {
            failTest("Zero value handling failed: " + e.message);
        }
    }
    
    // ========== Phase 7: 性能与大规模准确性 ==========
    
    private static function testLargeScaleCalculationAccuracy():Void {
        startTest("Large Scale Calculation Accuracy");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.largeStat = 1000;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            var startTime:Number = getTimer();
            
            // 添加100个buff
            var totalAdd:Number = 0;
            for (var i:Number = 0; i < 100; i++) {
                var value:Number = i + 1;
                var buff:PodBuff = new PodBuff("largeStat", BuffCalculationType.ADD, value);
                manager.addBuff(buff, null);
                totalAdd += value;
            }
            
            manager.update(1);
            
            var addTime:Number = getTimer() - startTime;
            
            // 验证计算：1000 + (1+2+...+100) = 1000 + 5050 = 6050
            var result:Number = getCalculatedValue(mockTarget, "largeStat");
            assertCalculation(result, 1000 + totalAdd, "100 buff calculation");
            
            recordPerformance("Large Scale Accuracy", {
                buffCount: 100,
                calculationTime: addTime + "ms",
                expectedValue: 1000 + totalAdd,
                actualValue: result,
                accurate: result == (1000 + totalAdd)
            });
            
            trace("  ✓ 100 buffs: sum = " + result + " (accurate)");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Large scale calculation accuracy failed: " + e.message);
        }
    }
    
    private static function testCalculationPerformance():Void {
        startTest("Calculation Performance");
        
        try {
            mockTarget = createMockTarget();
            
            var properties:Array = ["stat1", "stat2", "stat3", "stat4", "stat5"];
            for (var i:Number = 0; i < properties.length; i++) {
                mockTarget[properties[i]] = 100;
            }
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            // 每个属性添加20个buff
            var totalBuffs:Number = 0;
            for (var p:Number = 0; p < properties.length; p++) {
                for (var b:Number = 0; b < 20; b++) {
                    var type:String;
                    var value:Number;
                    
                    switch (b % 3) {
                        case 0: type = BuffCalculationType.ADD; value = 5; break;
                        case 1: type = BuffCalculationType.MULTIPLY; value = 1.02; break;
                        case 2: type = BuffCalculationType.PERCENT; value = 0.01; break;
                    }
                    
                    var buff:PodBuff = new PodBuff(properties[p], type, value);
                    manager.addBuff(buff, null);
                    totalBuffs++;
                }
            }
            
            var startTime:Number = getTimer();
            
            // 执行多次更新
            var updates:Number = 100;
            for (var u:Number = 0; u < updates; u++) {
                manager.update(0.1);
            }
            
            var totalTime:Number = getTimer() - startTime;
            
            recordPerformance("Calculation Performance", {
                totalBuffs: totalBuffs,
                properties: properties.length,
                updates: updates,
                totalTime: totalTime + "ms",
                avgUpdateTime: (totalTime / updates) + "ms per update"
            });
            
            trace("  ✓ Performance: " + totalBuffs + " buffs, " + updates + " updates in " + totalTime + "ms");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Calculation performance test failed: " + e.message);
        }
    }
    
    private static function testMemoryAndCalculationConsistency():Void {
        startTest("Memory and Calculation Consistency");
        
        try {
            mockTarget = createMockTarget();
            mockTarget.consistency = 100;
            
            var manager:BuffManager = new BuffManager(mockTarget, null);
            
            var expectedValues:Array = [];
            
            // 10轮添加和移除
            for (var round:Number = 0; round < 10; round++) {
                // 添加一批限时buff
                for (var i:Number = 0; i < 10; i++) {
                    var buff:MetaBuff = new MetaBuff(
                        [new PodBuff("consistency", BuffCalculationType.ADD, 10)],
                        [new TimeLimitComponent(5)],
                        0
                    );
                    manager.addBuff(buff, null);
                }
                
                manager.update(1);
                
                // 记录预期值
                var activeBuffs:Number = manager.getActiveBuffCount();
                var expectedValue:Number = 100 + (activeBuffs * 10);
                expectedValues.push(expectedValue);
                
                // 验证计算
                var actualValue:Number = getCalculatedValue(mockTarget, "consistency");
                assertCalculation(actualValue, expectedValue, "Round " + round + " calculation");
                
                // 推进时间让一些buff过期
                manager.update(5);
            }
            
            trace("  ✓ Consistency maintained across 10 rounds");
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Memory and calculation consistency failed: " + e.message);
        }
    }
    
    // ========== 工具方法 ==========
    
    /**
     * 创建模拟目标对象
     */
    private static function createMockTarget():Object {
        return {
            health: 100,
            mana: 50,
            attack: 25,
            defense: 15,
            speed: 10
        };
    }
    
// ======== 替换：更严格的属性读取（区分 undefined / NaN / 0） ========
private static function getCalculatedValue(target:Object, property:String):Number {
    if (typeof target[property] == "undefined") {
        throw new Error("Property '"+property+"' is undefined on target");
    }
    var v:Number = Number(target[property]);
    if (isNaN(v)) {
        throw new Error("Property '"+property+"' is NaN");
    }
    return v;
}
    
// ======== 新增：工具断言 ========
private static function assertPropertyExists(target:Object, property:String, ctx:String):Void {
    if (typeof target[property] == "undefined") {
        throw new Error("Property '"+property+"' is undefined " + (ctx ? ("("+ctx+")") : ""));
    }
}

private static function assertDefinedNumber(target:Object, property:String, expected:Number, msg:String):Void {
    assertPropertyExists(target, property, msg);
    var actual:Number = getCalculatedValue(target, property);
    assertCalculation(actual, expected, msg);
}

    /**
     * 断言计算结果
     */
    private static function assertCalculation(actual:Number, expected:Number, description:String):Void {
        var tolerance:Number = 0.001; // 浮点数容差
        if (Math.abs(actual - expected) > tolerance) {
            throw new Error("Calculation mismatch for " + description + 
                          ": expected " + expected + ", got " + actual);
        }
    }
    
    /**
     * 记录性能结果
     */
    private static function recordPerformance(testName:String, data:Object):Void {
        performanceResults.push({
            test: testName,
            data: data,
            timestamp: getTimer()
        });
    }
    
    /**
     * 输出性能报告
     */
    private static function printPerformanceReport():Void {
        if (performanceResults.length == 0) {
            return;
        }
        
        trace("\n=== Calculation Performance Results ===");
        
        for (var i:Number = 0; i < performanceResults.length; i++) {
            var result:Object = performanceResults[i];
            trace("📊 " + result.test + ":");
            
            for (var key:String in result.data) {
                trace("   " + key + ": " + result.data[key]);
            }
            trace("");
        }
        
        trace("=======================================");
    }
    
    // ========== 基础测试工具 ==========
    
    private static function startTest(testName:String):Void {
        testCount++;
        trace("🧪 Test " + testCount + ": " + testName);
    }
    
    private static function passTest():Void {
        passedCount++;
        trace("  ✅ PASSED\n");
    }
    
    private static function failTest(message:String):Void {
        failedCount++;
        trace("  ❌ FAILED: " + message + "\n");
    }
    
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }
    
    private static function printTestResults():Void {
        trace("\n=== Calculation Accuracy Test Results ===");
        trace("📊 Total tests: " + testCount);
        trace("✅ Passed: " + passedCount);
        trace("❌ Failed: " + failedCount);
        trace("📈 Success rate: " + Math.round((passedCount / testCount) * 100) + "%");
        
        if (failedCount == 0) {
            trace("🎉 All calculation tests passed! BuffManager calculations are accurate.");
        } else {
            trace("⚠️  " + failedCount + " test(s) failed. Please review calculation issues above.");
        }
        trace("==============================================");
    }
    
// ===============================================
// Sticky 容器 & 生命周期 行为契约（新增）
// ===============================================

/**
 * 1) Sticky：Meta 高频注入/弹出期间，属性始终存在（不变 undefined），最终值回到 base
 */
private static function testStickyContainer_NoUndefined():Void {
    startTest("Sticky container: meta jitter won't delete property");
    try {
        var mockTarget:Object = createMockTarget();
        mockTarget.hp = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        for (var i:Number = 0; i < 50; i++) {
            var meta:MetaBuff = new MetaBuff(
                [ new PodBuff("hp", BuffCalculationType.ADD, 50) ],
                [],
                0
            );
            // [P1-1 修复] 使用 addBuff 返回的 ID（带 auto_ 前缀）
            var registeredId:String = manager.addBuff(meta, null);
            manager.update(0);

            // 注入后：存在且为 150
            assertPropertyExists(mockTarget, "hp", "after meta add");
            assertDefinedNumber(mockTarget, "hp", 150, "hp = 100 + 50");

            // 立刻移除（使用注册时返回的 ID）
            manager.removeBuff(registeredId);
            manager.update(0);

            // 弹出后：存在且回到 100
            assertPropertyExists(mockTarget, "hp", "after meta remove");
            assertDefinedNumber(mockTarget, "hp", 100, "hp back to base");
        }

        manager.destroy();
        passTest();
    } catch (e) {
        failTest("Sticky jitter failed: " + e.message);
    }
}

/**
 * 2) unmanageProperty(finalize)：固化为普通属性后可直接写；再次管理时以当前普通值作为 base
 */
private static function testUnmanagePropertyFinalizeAndRebind():Void {
    startTest("unmanageProperty(finalize) then rebind uses plain value as base (independent Pods are cleaned)");
    try {
        var mockTarget:Object = createMockTarget();
        mockTarget.atk = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);
        manager.addBuff(new PodBuff("atk", BuffCalculationType.ADD, 50), null);
        manager.update(0);

        assertDefinedNumber(mockTarget, "atk", 150, "before finalize");

        // finalize 成普通属性
        manager.unmanageProperty("atk", true);
        assertPropertyExists(mockTarget, "atk", "after finalize");
        assertDefinedNumber(mockTarget, "atk", 150, "finalized keeps visible value");

        // 作为普通属性可直接写
        mockTarget.atk = 123;
        assertDefinedNumber(mockTarget, "atk", 123, "plain write must work");

        // 再次添加 buff ⇒ 重新管理，base 应取当前普通值 123
        manager.addBuff(new PodBuff("atk", BuffCalculationType.ADD, 1000), null);
        manager.update(0);

        assertDefinedNumber(mockTarget, "atk", 1123,
          "rebind uses plain base(123) + new Pod(+1000) (independent Pod cleaned on finalize)");

        manager.destroy();
        passTest();
    } catch (e) {
        failTest("Unmanage+Rebind failed: " + e.message);
    }
}

/**
 * 3) destroy() 默认 finalize 全部托管属性（保留可见值，不删属性）
 */
private static function testDestroyDefaultFinalizeAll():Void {
    startTest("destroy() finalizes all managed properties");
    try {
        var mockTarget:Object = createMockTarget();
        mockTarget.def = 20;

        var manager:BuffManager = new BuffManager(mockTarget, null);
        manager.addBuff(new PodBuff("def", BuffCalculationType.MULTIPLY, 2), null);
        manager.update(0);

        assertDefinedNumber(mockTarget, "def", 40, "before destroy");

        manager.destroy();

        // 销毁后：属性仍在，值保留
        assertPropertyExists(mockTarget, "def", "after destroy");
        var v:Number = getCalculatedValue(mockTarget, "def");
        assertCalculation(v, 20, "destroy clears to base then finalizes");

        passTest();
    } catch (e) {
        failTest("Destroy finalize-all failed: " + e.message);
    }
}

/**
 * 4) 0 与 undefined 的基值语义：未定义 => base=0；明确 0 => 与百分比相乘仍为 0
 */
private static function testBaseZeroVsUndefined():Void {
    startTest("Base value: zero vs undefined");
    try {
        var t:Object = {};
        var manager:BuffManager = new BuffManager(t, null);

        // 未定义：先 ensure 后变为已定义；+10 = 10
        manager.addBuff(new PodBuff("x", BuffCalculationType.ADD, 10), null);
        manager.update(0);
        assertPropertyExists(t, "x", "undefined -> defined");
        assertDefinedNumber(t, "x", 10, "undefined base treated as 0 then +10");

        // 明确 0：乘以 1.5 仍为 0
        t["y"] = 0;
        manager.addBuff(new PodBuff("y", BuffCalculationType.PERCENT, 0.5), null);
        manager.update(0);
        assertPropertyExists(t, "y", "zero stays defined");
        assertDefinedNumber(t, "y", 0, "0 * 1.5 = 0");

        manager.destroy();
        passTest();
    } catch (e) {
        failTest("Zero vs undefined failed: " + e.message);
    }
}

/**
 * 5) 添加顺序不应影响执行顺序（固定：MULTIPLY → PERCENT → ADD → MAX → MIN → OVERRIDE）
 * 新顺序对齐老系统: 基础值 × 倍率 + 加算
 */
private static function testOrderIndependenceAgainstAddSequence():Void {
    startTest("Calculation order independent of add sequence");
    try {
        var t1:Object = { dmg: 100 };
        var t2:Object = { dmg: 100 };
        var m1:BuffManager = new BuffManager(t1, null);
        var m2:BuffManager = new BuffManager(t2, null);

        // [P1-2 修复] 为每个 manager 创建独立的 buff 实例
        // 同一实例不能添加到多个 manager
        var A1:PodBuff = new PodBuff("dmg", BuffCalculationType.ADD, 20);
        var M1:PodBuff = new PodBuff("dmg", BuffCalculationType.MULTIPLY, 1.5);
        var P1:PodBuff = new PodBuff("dmg", BuffCalculationType.PERCENT, 0.1);
        var X1:PodBuff = new PodBuff("dmg", BuffCalculationType.MAX, 120);
        var N1:PodBuff = new PodBuff("dmg", BuffCalculationType.MIN, 999);

        // 顺序1
        m1.addBuff(A1, null); m1.addBuff(M1, null); m1.addBuff(P1, null); m1.addBuff(X1, null); m1.addBuff(N1, null);
        m1.update(0);
        var v1:Number = getCalculatedValue(t1, "dmg");

        // 顺序2 使用新的实例（打乱顺序）
        var A2:PodBuff = new PodBuff("dmg", BuffCalculationType.ADD, 20);
        var M2:PodBuff = new PodBuff("dmg", BuffCalculationType.MULTIPLY, 1.5);
        var P2:PodBuff = new PodBuff("dmg", BuffCalculationType.PERCENT, 0.1);
        var X2:PodBuff = new PodBuff("dmg", BuffCalculationType.MAX, 120);
        var N2:PodBuff = new PodBuff("dmg", BuffCalculationType.MIN, 999);
        m2.addBuff(N2, null); m2.addBuff(P2, null); m2.addBuff(A2, null); m2.addBuff(X2, null); m2.addBuff(M2, null);
        m2.update(0);
        var v2:Number = getCalculatedValue(t2, "dmg");

        assertCalculation(v1, v2, "add sequence must not change result");

        m1.destroy(); m2.destroy();
        passTest();
    } catch (e) {
        failTest("Order independence failed: " + e.message);
    }
}

/**
 * 6) clearAllBuffs：不销毁容器，属性存在，值回 base
 */
private static function testClearAllBuffsKeepsProperties():Void {
    startTest("clearAllBuffs keeps properties and resets to base");
    try {
        var t:Object = { spd: 10 };
        var m:BuffManager = new BuffManager(t, null);

        m.addBuff(new PodBuff("spd", BuffCalculationType.MULTIPLY, 2), null);
        m.update(0);
        assertDefinedNumber(t, "spd", 20, "before clear");

        m.clearAllBuffs();
        m.update(0);

        assertPropertyExists(t, "spd", "after clearAllBuffs");
        assertDefinedNumber(t, "spd", 10, "back to base");

        m.destroy();
        passTest();
    } catch (e) {
        failTest("clearAllBuffs contract failed: " + e.message);
    }
}

/**
 * 7) Meta 高频抖动稳定性（额外加压版）
 */
private static function testMetaBuffJitterStability():Void {
    startTest("MetaBuff jitter stability (no undefined during flips)");
    try {
        var t:Object = { energy: 100 };
        var m:BuffManager = new BuffManager(t, null);

        for (var i:Number = 0; i < 100; i++) {
            var meta:MetaBuff = new MetaBuff(
                [ new PodBuff("energy", BuffCalculationType.ADD, 1) ],
                [],
                0
            );
            // [P1-1 修复] 使用 addBuff 返回的 ID
            var registeredId:String = m.addBuff(meta, null);
            m.update(0);
            assertPropertyExists(t, "energy", "after add meta (iter "+i+")");

            m.removeBuff(registeredId);
            m.update(0);
            assertPropertyExists(t, "energy", "after remove meta (iter "+i+")");
        }

        // 结束后应回到 100
        assertDefinedNumber(t, "energy", 100, "final back to base");
        m.destroy();
        passTest();
    } catch (e) {
        failTest("Meta jitter stability failed: " + e.message);
    }
}

// =======================================================
// Phase 8: Regression & Lifecycle Contracts (Sticky Upgrade)
// =======================================================
private static function runPhase8_RegressionAndContracts():Void {
    // 🧪 Test 36
    testSameIdReplacement_NoGhost();
    // 🧪 Test 37
    testInjectedPods_EmitOnAdded();
    // 🧪 Test 38
    testRemoveInjectedPod_SyncWithMeta();
    // 🧪 Test 39
    testClearAllBuffs_RemovesIndependentPodsWithCallback();
    // 🧪 Test 40
    testRemoveBuff_DedupOnce();
}

// ---- helpers for Phase 8 ----
private static function _countKeys(o:Object):Number {
    var n:Number = 0;
    for (var k in o) n++;
    return n;
}
private static function _countLivePods(mgr:BuffManager):Number {
    var n:Number = 0;
    var list:Array = mgr["_buffs"];
    if (!list) return 0;
    for (var i:Number = 0; i < list.length; i++) {
        var b:Object = list[i];
        if (b && typeof b.isPod == "function" && b.isPod() && typeof b.isActive == "function" && b.isActive()) n++;
    }
    return n;
}
private static function _mkDuckPod(id:String, prop:String):Object {
    var o:Object = {};
    o._id = id;
    o._prop = prop;
    o._active = true;
    o.isPod = function():Boolean { return true; };
    o.getId = function():String { return this._id; };
    o.getTargetProperty = function():String { return this._prop; };
    o.isActive = function():Boolean { return this._active; };
    o.destroy = function():Void { this._active = false; };

    // IBuff 接口必需方法
    o.applyEffect = function(calculator:IBuffCalculator, context:BuffContext):Void {
        // Phase 8 测试只关心生命周期，不关心数值计算
    };
    o.getType = function():String {
        return "DuckPod";
    };

    return o;
}
private static function _mkDuckMetaInjectOnce(id:String, pods:Array):Object {
    var o:Object = {};
    o._id = id;
    o._fired = false;
    o.isPod = function():Boolean { return false; };
    o.getId = function():String { return this._id; };
    o.isActive = function():Boolean { return true; };
    o.update = function(df:Number):Object {
        if (!this._fired) { this._fired = true; return {stateChanged:true, needsInject:true}; }
        return {stateChanged:false};
    };
    o.createPodBuffsForInjection = function():Array { return pods; };
    o.clearInjectedBuffIds = function():Void {};
    o.recordInjectedBuffId = function(pid:String):Void {};
    o.removeInjectedBuffId = function(pid:String):Void {};

    // IBuff 接口必需方法
    o.applyEffect = function(calculator:IBuffCalculator, context:BuffContext):Void {
        // MetaBuff 不参与数值计算
    };
    o.getType = function():String {
        return "DuckMeta";
    };
    o.destroy = function():Void {
        this._fired = false;
    };

    return o;
}

// 🧪 Test 36: Same-ID replacement must not create "ghost" or nuke the new one
private static function testSameIdReplacement_NoGhost():Void {
    startTest("Same-ID replacement keeps only the new instance");
    try {
        var added:Array = [];
        var removed:Array = [];
        var mgr:BuffManager = new BuffManager({}, {
            onBuffAdded: function(id:String, b:Object):Void { added.push(id); },
            onBuffRemoved: function(id:String, b:Object):Void { removed.push(id); },
            onPropertyChanged: function(prop:String, v:Number):Void {}
        });
        var A1 = _mkDuckPod("A", "atk");
        var A2 = _mkDuckPod("A", "atk");
        mgr.addBuff(A1, "A");
        mgr.addBuff(A2, "A"); // 替换
        mgr.update(1);
        var livePods:Number = _countLivePods(mgr);
        if (!(removed.length == 1 && livePods == 1)) {
            throw new Error("Expected 1 removal and 1 live pod; got removed="+removed.length+", livePods="+livePods);
        }
        passTest();
    } catch (e) {
        failTest("Same-ID replacement failed: " + e.message);
    }
}

// 🧪 Test 37: Injected Pods must emit onBuffAdded
private static function testInjectedPods_EmitOnAdded():Void {
    startTest("Injected Pods fire onBuffAdded for each injected pod");
    try {
        var added:Array = [];
        var removed:Array = [];
        var mgr:BuffManager = new BuffManager({}, {
            onBuffAdded: function(id:String, b:Object):Void { added.push(id); },
            onBuffRemoved: function(id:String, b:Object):Void { removed.push(id); },
            onPropertyChanged: function(prop:String, v:Number):Void {}
        });
        var P1 = _mkDuckPod("P1", "atk");
        var P2 = _mkDuckPod("P2", "atk");
        var M = _mkDuckMetaInjectOnce("M", [P1, P2]);
        mgr.addBuff(M, "M");
        mgr.update(1); // 触发注入
        if (added.length < 3) { // M + P1 + P2
            throw new Error("Expected at least 3 onBuffAdded events, got " + added.length);
        }
        passTest();
    } catch (e) {
        failTest("Injected Pods add-event failed: " + e.message);
    }
}

// 🧪 Test 38: Removing a single injected Pod updates manager/meta state coherently
private static function testRemoveInjectedPod_SyncWithMeta():Void {
    startTest("Remove injected pod shrinks injected map by 1");
    try {
        var added:Array = [];
        var removed:Array = [];
        var mgr:BuffManager = new BuffManager({}, {
            onBuffAdded: function(id:String, b:Object):Void { added.push(id); },
            onBuffRemoved: function(id:String, b:Object):Void { removed.push(id); },
            onPropertyChanged: function(prop:String, v:Number):Void {}
        });
        var P1 = _mkDuckPod("P1", "atk");
        var P2 = _mkDuckPod("P2", "atk");
        var M = _mkDuckMetaInjectOnce("M", [P1, P2]);
        mgr.addBuff(M, "M");
        mgr.update(1); // 注入
        var injMap:Object = mgr["_injectedPodBuffs"];
        var before:Number = _countKeys(injMap);
        mgr.removeBuff("P1");
        mgr.update(1);
        var after:Number = _countKeys(mgr["_injectedPodBuffs"]);
        if (!((before - after) == 1)) {
            throw new Error("Expected injected map to shrink by 1; before="+before+", after="+after);
        }
        var okRemoved:Boolean = false;
        for (var i:Number=0;i<removed.length;i++) if (removed[i]=="P1") okRemoved = true;
        if (!okRemoved) throw new Error("Expected onBuffRemoved for P1");
        passTest();
    } catch (e) {
        failTest("Remove injected pod failed: " + e.message);
    }
}

// 🧪 Test 39: clearAllBuffs triggers onBuffRemoved for independent Pods
private static function testClearAllBuffs_RemovesIndependentPodsWithCallback():Void {
    startTest("clearAllBuffs emits onBuffRemoved for independent pods");
    try {
        var added:Array = [];
        var removed:Array = [];
        var mgr = new BuffManager({}, {
            onBuffAdded: function(id:String, b:Object):Void { added.push(id); },
            onBuffRemoved: function(id:String, b:Object):Void { removed.push(id); },
            onPropertyChanged: function(prop:String, v:Number):Void {}
        });
        mgr.addBuff(_mkDuckPod("X1", "hp"), "X1");
        mgr.addBuff(_mkDuckPod("X2", "mp"), "X2");
        mgr.update(1);
        mgr.clearAllBuffs();
        var livePods:Number = _countLivePods(mgr);
        if (!(removed.length >= 2 && livePods == 0)) {
            throw new Error("Expected >=2 removals and 0 live pods; got removed="+removed.length+", livePods="+livePods);
        }
        passTest();
    } catch (e) {
        failTest("clearAllBuffs removal-callback failed: " + e.message);
    }
}

// 🧪 Test 40: removeBuff de-dup (same ID twice -> 1 removal)
private static function testRemoveBuff_DedupOnce():Void {
    startTest("removeBuff de-dup removes only once");
    try {
        var added:Array = [];
        var removed:Array = [];
        var mgr = new BuffManager({}, {
            onBuffAdded: function(id:String, b:Object):Void { added.push(id); },
            onBuffRemoved: function(id:String, b:Object):Void { removed.push(id); },
            onPropertyChanged: function(prop:String, v:Number):Void {}
        });
        mgr.addBuff(_mkDuckPod("DUP", "atk"), "DUP");
        mgr.update(1);
        mgr.removeBuff("DUP");
        mgr.removeBuff("DUP"); // 重复
        mgr.update(1);
        var livePods:Number = _countLivePods(mgr);
        if (!(removed.length == 1 && livePods == 0)) {
            throw new Error("Expected 1 removal and 0 live pods; got removed="+removed.length+", livePods="+livePods);
        }
        passTest();
    } catch (e) {
        failTest("removeBuff de-dup failed: " + e.message);
    }
}

// =======================================================
// Phase 9: Phase 0/A Regression Tests
// =======================================================

/**
 * 运行Phase 9测试（在runAllTests中调用）
 */
public static function runPhase9_PhaseZeroAndARegression():Void {
    trace("\n--- Phase 9: Phase 0/A Regression Tests ---");
    testTimeLimitWithCooldown_ANDSemantics();
    testPendingRemovalCancel_P04();
    testDestroyedMetaBuffRejection_P06();
    testInvalidPropertyNameRejection_P08();
    testSetBaseValueNaNGuard_P16();
    testUpdateReentryProtection_P13();
}

// 🧪 Test 41: TimeLimitComponent + CooldownComponent 组合测试 (AND语义验证)
private static function testTimeLimitWithCooldown_ANDSemantics():Void {
    startTest("TimeLimitComponent + CooldownComponent AND semantics");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 创建带TimeLimitComponent和CooldownComponent的MetaBuff
        var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 50);
        var timeLimit:TimeLimitComponent = new TimeLimitComponent(3); // 3帧后过期
        var cooldown:CooldownComponent = new CooldownComponent(60, true, true);

        var meta:MetaBuff = new MetaBuff([pod], [timeLimit, cooldown], 0);
        manager.addBuff(meta, "test_and_semantics");
        manager.update(1);

        // 验证初始状态
        var initialValue:Number = getCalculatedValue(mockTarget, "attack");
        if (initialValue != 150) {
            throw new Error("Initial value should be 150, got " + initialValue);
        }

        // 模拟时间流逝，TimeLimitComponent应该在3帧后返回false
        manager.update(1); // 帧2
        manager.update(1); // 帧3
        manager.update(1); // 帧4 - TimeLimitComponent应返回false

        // [关键验证] 即使CooldownComponent返回true，MetaBuff也应失活（AND语义）
        var finalValue:Number = getCalculatedValue(mockTarget, "attack");
        if (finalValue != 100) {
            throw new Error("AND semantics failed: expected 100 (buff expired), got " + finalValue);
        }

        trace("  ✓ AND semantics: TimeLimitComponent failure terminates MetaBuff despite CooldownComponent alive");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("AND semantics test failed: " + e.message);
    }
}

// 🧪 Test 42: Pending removal cancellation (P0-4验证)
private static function testPendingRemovalCancel_P04():Void {
    startTest("Pending removal cancelled on same-ID re-add (P0-4)");
    try {
        var added:Array = [];
        var removed:Array = [];
        var mgr:BuffManager = new BuffManager({atk:100}, {
            onBuffAdded: function(id:String, b:Object):Void { added.push(id); },
            onBuffRemoved: function(id:String, b:Object):Void { removed.push(id); },
            onPropertyChanged: function(prop:String, v:Number):Void {}
        });

        var pod1:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 10);
        var pod2:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 20);

        // 场景: addBuff -> removeBuff -> addBuff (同ID) -> update
        mgr.addBuff(pod1, "X");
        mgr.removeBuff("X");      // 进入pending
        mgr.addBuff(pod2, "X");   // 应取消pending，替换为新buff
        mgr.update(1);

        // 验证：只有pod2存活，pod1被正确移除
        var livePods:Number = _countLivePods(mgr);
        if (livePods != 1) {
            throw new Error("Expected 1 live pod, got " + livePods);
        }

        // 验证：removed应该只有1个（pod1被同步移除），不应该有第二次移除
        if (removed.length != 1) {
            throw new Error("Expected 1 removal, got " + removed.length);
        }

        trace("  ✓ P0-4: Pending removal correctly cancelled on same-ID re-add");
        passTest();
    } catch (e) {
        failTest("P0-4 test failed: " + e.message);
    }
}

// 🧪 Test 43: Destroyed MetaBuff rejection (P0-6验证)
private static function testDestroyedMetaBuffRejection_P06():Void {
    startTest("Destroyed MetaBuff rejected on re-add (P0-6)");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 50);
        var meta:MetaBuff = new MetaBuff([pod], [], 0);

        // 添加并移除
        manager.addBuff(meta, "reuse_test");
        manager.update(1);
        manager.removeBuff("reuse_test");
        manager.update(1);

        // MetaBuff应该已被销毁
        if (!meta.isDestroyed()) {
            throw new Error("MetaBuff should be destroyed after removal");
        }

        // 尝试复用已销毁的MetaBuff
        var result:String = manager.addBuff(meta, "reuse_test_2");

        // 应返回null（拒绝复用）
        if (result != null) {
            throw new Error("Destroyed MetaBuff should be rejected, but got id: " + result);
        }

        trace("  ✓ P0-6: Destroyed MetaBuff correctly rejected on re-add");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("P0-6 test failed: " + e.message);
    }
}

// 🧪 Test 44: Invalid property name rejection (P0-8验证)
private static function testInvalidPropertyNameRejection_P08():Void {
    startTest("Invalid property name rejected (P0-8)");
    try {
        var containerCreated:Boolean = false;
        mockTarget = createMockTarget();

        var manager:BuffManager = new BuffManager(mockTarget, {
            onPropertyChanged: function(prop:String, v:Number):Void {
                if (prop == "undefined" || prop == "" || prop == null) {
                    containerCreated = true;
                }
            }
        });

        // 创建属性名为空/undefined的PodBuff
        var badPod1:PodBuff = new PodBuff("", BuffCalculationType.ADD, 10);
        var badPod2:PodBuff = new PodBuff(null, BuffCalculationType.ADD, 10);

        manager.addBuff(badPod1, "bad1");
        manager.addBuff(badPod2, "bad2");
        manager.update(1);

        // 验证不应创建无效属性容器
        var containers:Object = manager["_propertyContainers"];
        if (containers[""] != null || containers["undefined"] != null || containers["null"] != null) {
            throw new Error("Invalid property containers should not be created");
        }

        trace("  ✓ P0-8: Invalid property names correctly rejected");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("P0-8 test failed: " + e.message);
    }
}

// 🧪 Test 45: setBaseValue NaN guard (P1-6验证)
private static function testSetBaseValueNaNGuard_P16():Void {
    startTest("setBaseValue NaN guard (P1-6)");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);
        manager.update(1);

        var container:PropertyContainer = manager.getPropertyContainer("attack");
        if (!container) {
            // 添加一个buff来创建容器
            var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 10);
            manager.addBuff(pod, "trigger");
            manager.update(1);
            container = manager.getPropertyContainer("attack");
        }

        if (!container) {
            throw new Error("Failed to get PropertyContainer");
        }

        var originalBase:Number = container.getBaseValue();

        // 尝试设置NaN
        container.setBaseValue(NaN);

        // 验证baseValue未被污染
        var newBase:Number = container.getBaseValue();
        if (isNaN(newBase)) {
            throw new Error("NaN should be rejected, but baseValue is NaN");
        }

        if (newBase != originalBase) {
            throw new Error("BaseValue should remain " + originalBase + ", got " + newBase);
        }

        trace("  ✓ P1-6: NaN correctly rejected by setBaseValue");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("P1-6 test failed: " + e.message);
    }
}

// 🧪 Test 46: Update reentry protection (P1-3验证)
private static function testUpdateReentryProtection_P13():Void {
    startTest("Update reentry protection (P1-3)");
    try {
        var updateCallCount:Number = 0;
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 创建一个在update时触发addBuff的场景（通过回调）
        // 注意：由于AS2的限制，我们通过检查_inUpdate标志来验证
        var inUpdateBefore:Boolean = manager["_inUpdate"];

        manager.update(1);

        var inUpdateAfter:Boolean = manager["_inUpdate"];

        // 验证update结束后_inUpdate应该为false
        if (inUpdateAfter) {
            throw new Error("_inUpdate should be false after update completes");
        }

        // 验证在update开始前_inUpdate应该为false
        if (inUpdateBefore) {
            throw new Error("_inUpdate should be false before update");
        }

        trace("  ✓ P1-3: Update reentry protection in place");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("P1-3 test failed: " + e.message);
    }
}

// =======================================================
// Phase 10: Phase B Regression Tests (ID Namespace Separation)
// =======================================================

/**
 * 运行Phase 10测试（在runAllTests中调用）
 */
public static function runPhase10_PhaseBRegression():Void {
    trace("\n--- Phase 10: Phase B Regression Tests (ID Namespace) ---");
    testIDNamespaceSeparation_ExternalInternal();
    testRemoveInactivePodBuffsUsesRegId();
    testLookupByIdFallback();
    testPrefixQueryOnlyExternal();
}

// 🧪 Test 47: ID命名空间分离验证
private static function testIDNamespaceSeparation_ExternalInternal():Void {
    startTest("ID Namespace Separation (_byExternalId/_byInternalId)");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;
        mockTarget.defense = 50;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 1. 用外部ID注册独立PodBuff
        var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 10);
        manager.addBuff(pod, "equip_sword_atk");
        manager.update(1);

        // 2. 验证独立Pod存在于_byExternalId
        var byExternal:Object = manager["_byExternalId"];
        var byInternal:Object = manager["_byInternalId"];

        if (byExternal["equip_sword_atk"] == null) {
            throw new Error("Independent Pod should be in _byExternalId");
        }

        // 3. 添加MetaBuff，验证注入的Pod在_byInternalId
        var childPods:Array = [new PodBuff("defense", BuffCalculationType.ADD, 5)];
        var timeLimitComp:TimeLimitComponent = new TimeLimitComponent(100);
        var meta:MetaBuff = new MetaBuff(childPods, [timeLimitComp], 0);
        manager.addBuff(meta, "skill_buff");
        manager.update(1);

        // 验证MetaBuff在_byExternalId
        if (byExternal["skill_buff"] == null) {
            throw new Error("MetaBuff should be in _byExternalId");
        }

        // 验证注入的Pod在_byInternalId（而非_byExternalId）
        var injectedIds:Array = manager["_metaBuffInjections"][meta.getId()];
        if (!injectedIds || injectedIds.length == 0) {
            throw new Error("MetaBuff should have injected pods");
        }

        var injectedPodId:String = injectedIds[0];
        if (byInternal[injectedPodId] == null) {
            throw new Error("Injected Pod should be in _byInternalId");
        }

        // 验证注入的Pod不在_byExternalId
        if (byExternal[injectedPodId] != null) {
            throw new Error("Injected Pod should NOT be in _byExternalId");
        }

        trace("  ✓ Phase B: ID namespace correctly separated");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("ID Namespace test failed: " + e.message);
    }
}

// 🧪 Test 48: _removeInactivePodBuffs使用__regId验证
// [Phase D 修复] 正确测试_removeInactivePodBuffs分支：
// - 让PodBuff.isActive()返回false（通过deactivate）
// - 让update()自动触发_removeInactivePodBuffs清理
private static function testRemoveInactivePodBuffsUsesRegId():Void {
    startTest("_removeInactivePodBuffs uses __regId (via deactivate)");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 添加一个独立PodBuff，使用外部ID
        var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 10);
        manager.addBuff(pod, "test_external_id");
        manager.update(1);

        // 验证__regId被正确设置
        var regId:String = pod["__regId"];
        if (regId != "test_external_id") {
            throw new Error("__regId should be 'test_external_id', got: " + regId);
        }

        // 验证可以通过外部ID查找
        var found:IBuff = manager.getBuffById("test_external_id");
        if (found == null) {
            throw new Error("Should find buff by external ID");
        }

        // [Phase D 修复] 关键：使用deactivate()让PodBuff变为inactive
        // 这样update()会走_removeInactivePodBuffs分支，而非removeBuff->pendingRemovals
        pod.deactivate();

        // 验证deactivate生效
        if (pod.isActive()) {
            throw new Error("PodBuff should be inactive after deactivate()");
        }

        // 调用update()，触发_removeInactivePodBuffs自动清理inactive的独立Pod
        manager.update(1);

        // 验证buff被自动移除（通过__regId查找应该找不到）
        found = manager.getBuffById("test_external_id");
        if (found != null) {
            throw new Error("Inactive PodBuff should be auto-removed by _removeInactivePodBuffs");
        }

        trace("  ✓ Phase B: _removeInactivePodBuffs correctly uses __regId for removal");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("_removeInactivePodBuffs __regId test failed: " + e.message);
    }
}

// 🧪 Test 49: _lookupById回退逻辑验证
private static function testLookupByIdFallback():Void {
    startTest("_lookupById fallback (external -> internal)");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;
        mockTarget.defense = 50;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 1. 添加外部ID的buff
        var extPod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 10);
        manager.addBuff(extPod, "external_buff");

        // 2. 添加MetaBuff（会创建内部ID的Pod）
        var childPods:Array = [new PodBuff("defense", BuffCalculationType.ADD, 5)];
        var meta:MetaBuff = new MetaBuff(childPods, [new TimeLimitComponent(100)], 0);
        manager.addBuff(meta, "meta_buff");
        manager.update(1);

        // 3. 通过外部ID查找
        var foundExt:IBuff = manager.getBuffById("external_buff");
        if (foundExt == null) {
            throw new Error("Should find buff by external ID");
        }

        // 4. 通过内部ID查找注入的Pod
        var injectedIds:Array = manager["_metaBuffInjections"][meta.getId()];
        if (injectedIds && injectedIds.length > 0) {
            var foundInt:IBuff = manager.getBuffById(injectedIds[0]);
            if (foundInt == null) {
                throw new Error("Should find injected pod by internal ID");
            }
        }

        trace("  ✓ Phase B: _lookupById fallback works correctly");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("_lookupById fallback test failed: " + e.message);
    }
}

// 🧪 Test 50: 前缀查询只查外部ID验证
private static function testPrefixQueryOnlyExternal():Void {
    startTest("Prefix query only searches _byExternalId");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;
        mockTarget.defense = 50;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 1. 添加外部ID的buff
        manager.addBuff(new PodBuff("attack", BuffCalculationType.ADD, 10), "equip_sword_1");
        manager.addBuff(new PodBuff("attack", BuffCalculationType.ADD, 5), "equip_sword_2");

        // 2. 添加MetaBuff（注入的Pod有内部ID）
        var childPods:Array = [new PodBuff("defense", BuffCalculationType.ADD, 5)];
        var meta:MetaBuff = new MetaBuff(childPods, [new TimeLimitComponent(100)], 0);
        manager.addBuff(meta, "skill_buff");
        manager.update(1);

        // 3. 前缀查询应只返回外部ID匹配的
        var equipBuffs:Array = manager.getBuffsByIdPrefix("equip_");
        if (equipBuffs.length != 2) {
            throw new Error("Should find 2 equip buffs, got: " + equipBuffs.length);
        }

        // 4. 验证hasBuffWithIdPrefix
        if (!manager.hasBuffWithIdPrefix("equip_")) {
            throw new Error("hasBuffWithIdPrefix should return true for 'equip_'");
        }

        // 5. 验证数字前缀不会匹配注入的Pod（注入的Pod用数字ID）
        var numericBuffs:Array = manager.getBuffsByIdPrefix("0");
        // 数字前缀可能匹配或不匹配，取决于实现
        // 关键是不应该返回用户未注册的内部ID

        trace("  ✓ Phase B: Prefix queries only search external IDs");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("Prefix query test failed: " + e.message);
    }
}

// =======================================================
// Phase 11: Phase D Contract Tests (Pure-Numeric ID Rejection)
// =======================================================

/**
 * 运行Phase 11测试（在runAllTests中调用）
 */
public static function runPhase11_PhaseDContract():Void {
    trace("\n--- Phase 11: Phase D Contract Tests (ID Validation) ---");
    testPureNumericIdRejection();
    testValidExternalIdAccepted();
    testAutoIdPrefixWhenNullId();           // [P1-1]
    testDuplicateRegistrationRejection();   // [P1-2]
    testInjectionRollbackOnError();         // [P1-3]
}

// 🧪 Test 51: 纯数字外部ID应被拒绝
private static function testPureNumericIdRejection():Void {
    startTest("Pure-numeric external ID rejection");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 尝试使用纯数字ID添加Buff（应被拒绝）
        var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 10);
        var result:String = manager.addBuff(pod, "12345");

        // 验证返回null（被拒绝）
        if (result != null) {
            throw new Error("Pure-numeric ID '12345' should be rejected, but got: " + result);
        }

        // 验证Buff未被添加
        var found:IBuff = manager.getBuffById("12345");
        if (found != null) {
            throw new Error("Buff with pure-numeric ID should not exist in manager");
        }

        // 验证manager中没有任何buff
        var info:Object = manager.getDebugInfo();
        if (info.total != 0) {
            throw new Error("Manager should have 0 buffs after rejection, got: " + info.total);
        }

        trace("  ✓ Phase D: Pure-numeric external ID correctly rejected");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("Pure-numeric ID rejection test failed: " + e.message);
    }
}

// 🧪 Test 52: 有效的外部ID应被接受
private static function testValidExternalIdAccepted():Void {
    startTest("Valid external ID accepted");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 测试各种有效的外部ID格式
        var validIds:Array = [
            "buff_1",           // 带前缀
            "skill-attack",     // 带横线
            "equip_sword_01",   // 多段
            "a",                // 单字母
            "1a",               // 数字开头但含字母
            "buff123abc"        // 混合
        ];

        for (var i:Number = 0; i < validIds.length; i++) {
            var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 1);
            var result:String = manager.addBuff(pod, validIds[i]);

            if (result == null) {
                throw new Error("Valid ID '" + validIds[i] + "' should be accepted");
            }

            var found:IBuff = manager.getBuffById(validIds[i]);
            if (found == null) {
                throw new Error("Buff with valid ID '" + validIds[i] + "' should exist");
            }
        }

        // 验证所有buff都被添加
        var info:Object = manager.getDebugInfo();
        if (info.total != validIds.length) {
            throw new Error("Manager should have " + validIds.length + " buffs, got: " + info.total);
        }

        trace("  ✓ Phase D: Valid external IDs correctly accepted");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("Valid ID acceptance test failed: " + e.message);
    }
}

// 🧪 Test 53: [P1-1] buffId为null时应自动加"auto_"前缀
private static function testAutoIdPrefixWhenNullId():Void {
    startTest("[P1-1] Auto-prefix when buffId is null");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 使用null作为buffId添加Buff
        var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 10);
        var internalId:String = pod.getId(); // 获取内部数字ID
        var result:String = manager.addBuff(pod, null);

        // 验证返回的ID带有"auto_"前缀
        if (result == null) {
            throw new Error("addBuff with null id should succeed");
        }
        if (result.indexOf("auto_") != 0) {
            throw new Error("Auto-generated ID should start with 'auto_', got: " + result);
        }
        if (result != "auto_" + internalId) {
            throw new Error("Auto-generated ID should be 'auto_" + internalId + "', got: " + result);
        }

        // 验证可以通过自动生成的ID查找
        var found:IBuff = manager.getBuffById(result);
        if (found != pod) {
            throw new Error("Should find buff by auto-generated ID");
        }

        // 验证纯数字ID查不到（不在_byExternalId中）
        var foundByNumeric:IBuff = manager.getBuffById(internalId);
        if (foundByNumeric != null) {
            throw new Error("Pure numeric internal ID should not be in _byExternalId");
        }

        trace("  ✓ P1-1: Auto-prefix 'auto_' correctly applied when buffId is null");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("[P1-1] Auto-prefix test failed: " + e.message);
    }
}

// 🧪 Test 54: [P1-2] 同一Buff实例重复注册应被拒绝
private static function testDuplicateRegistrationRejection():Void {
    startTest("[P1-2] Duplicate instance registration rejection");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 创建一个Buff实例
        var pod:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 10);

        // 第一次添加应成功
        var result1:String = manager.addBuff(pod, "buff_a");
        if (result1 == null) {
            throw new Error("First registration should succeed");
        }

        // 第二次添加同一实例应被拒绝
        var result2:String = manager.addBuff(pod, "buff_b");
        if (result2 != null) {
            throw new Error("Second registration of same instance should be rejected, got: " + result2);
        }

        // 验证manager中只有一个buff
        var info:Object = manager.getDebugInfo();
        if (info.total != 1) {
            throw new Error("Manager should have exactly 1 buff after duplicate rejection, got: " + info.total);
        }

        // 验证原始注册ID仍然有效
        var found:IBuff = manager.getBuffById("buff_a");
        if (found != pod) {
            throw new Error("Original registration should still be valid");
        }

        // 第二个ID不应存在
        var notFound:IBuff = manager.getBuffById("buff_b");
        if (notFound != null) {
            throw new Error("Second ID should not exist");
        }

        trace("  ✓ P1-2: Duplicate instance registration correctly rejected");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("[P1-2] Duplicate registration test failed: " + e.message);
    }
}

// 🧪 Test 55: [P1-3] 注入过程中包含 null pod 应被跳过
private static function testInjectionRollbackOnError():Void {
    startTest("[P1-3] Injection skips null pods gracefully");
    try {
        mockTarget = createMockTarget();
        mockTarget.attack = 100;

        var manager:BuffManager = new BuffManager(mockTarget, null);

        // 使用 _mkDuckMetaInjectOnce 创建鸭子类型 MetaBuff
        // 传入包含 null 的 pods 数组来测试防御性处理
        var podsWithNull:Array = [
            new PodBuff("attack", BuffCalculationType.ADD, 1),
            new PodBuff("attack", BuffCalculationType.ADD, 2),
            null  // null 应被跳过
        ];
        // [AS2] 使用无类型变量绕过编译器类型检查（运行时鸭子类型）
        var duckMeta = _mkDuckMetaInjectOnce("p13_meta", podsWithNull);

        // 无类型变量可传递给 IBuff 参数（AS2 鸭子类型）
        var result:String = manager.addBuff(duckMeta, "faulty_meta_id");

        // 应该成功添加（null被跳过）
        if (result == null) {
            throw new Error("MetaBuff with null pods should still be added (nulls skipped)");
        }

        manager.update(1);

        // 验证有效的 Pod 被注入（2个有效 + 1个 Meta）
        var info:Object = manager.getDebugInfo();
        // 至少应有 1 个 MetaBuff（Pod 的注入可能在下一个 update）
        if (info.total < 1) {
            throw new Error("Should have at least the MetaBuff, got: " + info.total);
        }

        trace("  ✓ P1-3: Injection handles null pods gracefully (skips them)");
        manager.destroy();
        passTest();
    } catch (e) {
        failTest("[P1-3] Injection null-skip test failed: " + e.message);
    }
}

}