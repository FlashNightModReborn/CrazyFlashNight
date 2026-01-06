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
        startTest("Basic MULTIPLY Calculation");
        
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
            
            // 预期：50 * 1.5 * 1.2 = 90
            var expectedValue:Number = 90;
            var actualValue:Number = getCalculatedValue(mockTarget, "defense");
            
            assertCalculation(actualValue, expectedValue, "MULTIPLY calculation");
            
            trace("  ✓ MULTIPLY: 50 * 1.5 * 1.2 = " + actualValue);
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Basic MULTIPLY calculation failed: " + e.message);
        }
    }
    
    private static function testBasicPercentCalculation():Void {
        startTest("Basic PERCENT Calculation");
        
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
            
            // 预期：100 * 1.2 * 1.1 = 132
            var expectedValue:Number = 132;
            var actualValue:Number = getCalculatedValue(mockTarget, "speed");
            
            assertCalculation(actualValue, expectedValue, "PERCENT calculation");
            
            trace("  ✓ PERCENT: 100 * 1.2 * 1.1 = " + actualValue);
            
            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Basic PERCENT calculation failed: " + e.message);
        }
    }
    
    private static function testCalculationTypesPriority():Void {
        startTest("Calculation Types Priority");

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

            // 新计算顺序（对齐老系统: 基础值 × 倍率 + 加算）:
            // 100 * 1.5 * 1.1 + 20 = 185
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
            manager.addBuff(permanentBuff, null);
            
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

            // 移除永久buff：200
            manager.removeBuff(permanentBuff.getId());
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
            manager.addBuff(hugeBuff, null);
            manager.update(1);
            
            var hugeValue:Number = getCalculatedValue(mockTarget, "extreme");
            assertCalculation(hugeValue, 1000000, "Huge multiplier");
            
            // 测试极小值
            manager.removeBuff(hugeBuff.getId());
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
        startTest("Floating Point Accuracy");
        
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
            
            // 10 * 1.1 * 1.1 * 1.1 = 13.31
            var result:Number = getCalculatedValue(mockTarget, "floatTest");
            var expected:Number = 13.31;
            
            // 允许小的浮点误差
            assert(Math.abs(result - expected) < 0.01, 
                "Floating point calculation within tolerance: " + result);
            
            trace("  ✓ Floating point: 10 * 1.1³ = " + result + " (±0.01)");
            
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
            
            // 100 + (-30) + (-50) = 20
            var afterDebuffs:Number = getCalculatedValue(mockTarget, "balance");
            assertCalculation(afterDebuffs, 20, "Negative additions");
            
            // 测试负数百分比
            var percentDebuff:PodBuff = new PodBuff("balance", BuffCalculationType.PERCENT, -0.5);
            manager.addBuff(percentDebuff, null);
            manager.update(1);
            
            // 20 * (1 - 0.5) = 10
            var afterPercent:Number = getCalculatedValue(mockTarget, "balance");
            assertCalculation(afterPercent, 10, "Negative percentage");
            
            trace("  ✓ Negative values: 100 → 20 → 10");
            
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
            
            var afterAdd:Number = getCalculatedValue(mockTarget, "zeroTest");
            assertCalculation(afterAdd, 50, "Add to zero");
            
            // 测试乘以0
            mockTarget.zeroTest = 100;
            var zeroBuff:PodBuff = new PodBuff("zeroTest", BuffCalculationType.MULTIPLY, 0);
            manager.addBuff(zeroBuff, null);
            manager.update(1);
            
            var afterMultiply:Number = getCalculatedValue(mockTarget, "zeroTest");
            assertCalculation(afterMultiply, 0, "Multiply by zero");
            
            trace("  ✓ Zero handling: 0+50=50, 100*0=0");
            
            manager.destroy();
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
            manager.addBuff(meta, null);
            manager.update(0);

            // 注入后：存在且为 150
            assertPropertyExists(mockTarget, "hp", "after meta add");
            assertDefinedNumber(mockTarget, "hp", 150, "hp = 100 + 50");

            // 立刻移除
            manager.removeBuff(meta.getId());
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

        var A:PodBuff = new PodBuff("dmg", BuffCalculationType.ADD, 20);
        var M:PodBuff = new PodBuff("dmg", BuffCalculationType.MULTIPLY, 1.5);
        var P:PodBuff = new PodBuff("dmg", BuffCalculationType.PERCENT, 0.1);
        var X:PodBuff = new PodBuff("dmg", BuffCalculationType.MAX, 120); // 至少 120
        var N:PodBuff = new PodBuff("dmg", BuffCalculationType.MIN, 999); // 至多 999（此例不起作用）
        
        // 顺序1
        m1.addBuff(A, null); m1.addBuff(M, null); m1.addBuff(P, null); m1.addBuff(X, null); m1.addBuff(N, null);
        m1.update(0);
        var v1:Number = getCalculatedValue(t1, "dmg");

        // 顺序2（打乱顺序）
        m2.addBuff(N, null); m2.addBuff(P, null); m2.addBuff(A, null); m2.addBuff(X, null); m2.addBuff(M, null);
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
            m.addBuff(meta, null);
            m.update(0);
            assertPropertyExists(t, "energy", "after add meta (iter "+i+")");

            m.removeBuff(meta.getId());
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

}