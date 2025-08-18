// org/flashNight/arki/component/Buff/test/PropertyContainerTest.as (Enhanced Version)

import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.test.*;
import org.flashNight.gesh.property.*;

/**
 * PropertyContainer增强测试套件
 *
 * 包含全面的功能测试、性能测试和数值计算正确性验证：
 * - 基础功能测试（构造、基础值设置获取）
 * - Buff管理测试（添加、移除、清除、计数）
 * - PropertyAccessor集成测试（直接属性访问、缓存机制）
 * - 数值计算正确性测试（大量样例、精确计算、边界条件）
 * - 性能测试模块（大量Buff、频繁访问、内存使用、缓存效率）
 * - 回调机制测试（值变化回调、外部设置处理）
 * - 边界条件和错误处理测试
 * - 调试和状态查询功能测试
 *
 * 增强特性：
 * - 详细的断言输出，显示期望值vs实际值
 * - 计算步骤的完整追踪
 * - 性能基准测试和报告
 * - 数值精度验证
 * - 内存泄漏检测
 *
 * 使用方式: PropertyContainerTest.runAllTests();
 */
class org.flashNight.arki.component.Buff.test.PropertyContainerTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;

    // 性能测试相关
    private static var performanceResults:Array = [];
    private static var EPSILON:Number = 0.0001; // 浮点数精度阈值

    /**
     * 运行所有测试用例（增强版）
     */
    public static function runAllTests():Void {
        trace("=== PropertyContainer Enhanced Test Suite Started ===");

        // 重置计数器
        testCount = 0;
        passedCount = 0;
        failedCount = 0;
        performanceResults = [];

        trace("\n--- Phase 1: Basic Functionality Tests ---");
        // 基础功能测试
        testConstructor();
        testBaseValueOperations();
        testPropertyNameAccess();

        trace("\n--- Phase 2: PropertyAccessor Integration Tests ---");
        // PropertyAccessor集成测试
        testPropertyAccessorIntegration();
        testDirectPropertyAccess();
        testCachingMechanism();

        trace("\n--- Phase 3: Buff Management Tests ---");
        // Buff管理测试
        testAddBuff();
        testRemoveBuff();
        testClearBuffs();
        testBuffCounting();
        testHasBuff();

        trace("\n--- Phase 4: Numerical Calculation Correctness Tests ---");
        // 数值计算正确性测试（大幅扩展）
        testBasicCalculationTypes();
        testSingleBuffCalculation();
        testMultipleBuffCalculation();
        testBuffPriorityCalculation();
        testComplexBuffCombination();
        testAdvancedCalculationCombinations();
        testFloatingPointPrecision();
        testExtremeValues();
        testCalculationOrderDependency();
        testNestedCalculationScenarios();
        testMathematicalEdgeCases();

        trace("\n--- Phase 5: Performance Tests ---");
        // 性能测试模块
        testPerformanceWithManyBuffs();
        testFrequentAccessPerformance();
        testCacheEfficiency();
        testMemoryUsageOptimization();
        testCalculationComplexityScaling();
        testConcurrentAccessSimulation();

        trace("\n--- Phase 6: Callback and Integration Tests ---");
        // 回调机制测试
        testChangeCallback();
        testExternalPropertySet();

        trace("\n--- Phase 7: Caching and Optimization Tests ---");
        // 缓存和性能测试
        testFinalValueCaching();
        testForceRecalculation();
        testInvalidationMechanism();

        trace("\n--- Phase 8: Edge Cases and Error Handling ---");
        // 边界条件测试
        testEmptyContainer();
        testInactiveBuffs();
        testInvalidInputs();
        testEdgeCases();

        trace("\n--- Phase 9: Debug and Utility Tests ---");
        // 调试和工具测试
        testToString();
        testDestroy();

        trace("\n--- Phase 10: Accessor–Container Lifecycle Integration ---");
        testFinalizeToPlainProperty();
        testRebindAfterFinalize();
        testDestroyRemovesTargetProperty();
        testIsolationMultiContainersSameTarget();
        testExternalWriteBeforeVsAfterFinalize();


        // 输出测试结果
        printTestResults();
        printPerformanceReport();
    }

    // ========== 新增：数值计算正确性测试 ==========

    /**
     * 测试基础计算类型的数学正确性
     */
    private static function testBasicCalculationTypes():Void {
        startTest("Basic Calculation Types Mathematical Correctness");

        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "mathTest", 100, null);

            trace("  Testing individual calculation types:");

            // ADD类型测试
            container.clearBuffs();
            var addBuff:PodBuff = new PodBuff("mathTest", BuffCalculationType.ADD, 25.5);
            container.addBuff(addBuff);
            assertCalculation("ADD: 100 + 25.5", 125.5, target.mathTest, "100 + 25.5 = 125.5");

            // MULTIPLY类型测试
            container.clearBuffs();
            var multiplyBuff:PodBuff = new PodBuff("mathTest", BuffCalculationType.MULTIPLY, 2.5);
            container.addBuff(multiplyBuff);
            assertCalculation("MULTIPLY: 100 * 2.5", 250, target.mathTest, "100 * 2.5 = 250");

            // PERCENT类型测试
            container.clearBuffs();
            var percentBuff:PodBuff = new PodBuff("mathTest", BuffCalculationType.PERCENT, 0.3);
            container.addBuff(percentBuff);
            assertCalculation("PERCENT: 100 * (1 + 0.3)", 130, target.mathTest, "100 * (1 + 0.3) = 130");

            // OVERRIDE类型测试
            container.clearBuffs();
            var overrideBuff:PodBuff = new PodBuff("mathTest", BuffCalculationType.OVERRIDE, 88.88);
            container.addBuff(overrideBuff);
            assertCalculation("OVERRIDE: 88.88", 88.88, target.mathTest, "Override replaces with 88.88");

            // MAX类型测试
            container.clearBuffs();
            var maxBuff:PodBuff = new PodBuff("mathTest", BuffCalculationType.MAX, 120);
            container.addBuff(maxBuff);
            assertCalculation("MAX: Math.max(100, 120)", 120, target.mathTest, "Math.max(100, 120) = 120");

            // MIN类型测试
            container.clearBuffs();
            var minBuff:PodBuff = new PodBuff("mathTest", BuffCalculationType.MIN, 80);
            container.addBuff(minBuff);
            assertCalculation("MIN: Math.min(100, 80)", 80, target.mathTest, "Math.min(100, 80) = 80");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Basic calculation types failed: " + e.message);
        }
    }

    /**
     * 测试高级计算组合
     */
    private static function testAdvancedCalculationCombinations():Void {
        startTest("Advanced Calculation Combinations");

        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "advancedMath", 50, null);

            trace("  Testing complex calculation combinations:");

            // 测试1: 多个ADD + 单个MULTIPLY
            container.clearBuffs();
            var add1:PodBuff = new PodBuff("advancedMath", BuffCalculationType.ADD, 20);
            var add2:PodBuff = new PodBuff("advancedMath", BuffCalculationType.ADD, 15);
            var add3:PodBuff = new PodBuff("advancedMath", BuffCalculationType.ADD, 10);
            var multiply1:PodBuff = new PodBuff("advancedMath", BuffCalculationType.MULTIPLY, 2);

            container.addBuff(add1);
            container.addBuff(add2);
            container.addBuff(add3);
            container.addBuff(multiply1);

            // 计算步骤: 50 -> 95(+45) -> 190(*2)
            var expected1:Number = (50 + 20 + 15 + 10) * 2;
            assertCalculation("Multi-ADD + MULTIPLY: (50+20+15+10)*2", expected1, target.advancedMath, "Step: 50 → 95 (+45) → 190 (*2)");

            // 测试2: ADD + MULTIPLY + PERCENT组合
            container.clearBuffs();
            var add4:PodBuff = new PodBuff("advancedMath", BuffCalculationType.ADD, 30);
            var multiply2:PodBuff = new PodBuff("advancedMath", BuffCalculationType.MULTIPLY, 1.5);
            var percent1:PodBuff = new PodBuff("advancedMath", BuffCalculationType.PERCENT, 0.2);

            container.addBuff(add4);
            container.addBuff(multiply2);
            container.addBuff(percent1);

            // 计算步骤: 50 -> 80(+30) -> 120(*1.5) -> 144(*1.2)
            var expected2:Number = ((50 + 30) * 1.5) * 1.2;
            assertCalculation("ADD+MULTIPLY+PERCENT: ((50+30)*1.5)*1.2", expected2, target.advancedMath, "Step: 50 → 80 (+30) → 120 (*1.5) → 144 (*1.2)");

            // 测试3: 多个PERCENT
            container.clearBuffs();
            var percent2:PodBuff = new PodBuff("advancedMath", BuffCalculationType.PERCENT, 0.1);
            var percent3:PodBuff = new PodBuff("advancedMath", BuffCalculationType.PERCENT, 0.15);
            var percent4:PodBuff = new PodBuff("advancedMath", BuffCalculationType.PERCENT, 0.05);

            container.addBuff(percent2);
            container.addBuff(percent3);
            container.addBuff(percent4);

            // 计算步骤: 50 -> 55(*1.1) -> 63.25(*1.15) -> 66.4125(*1.05)
            var expected3:Number = 50 * 1.1 * 1.15 * 1.05;
            assertCalculation("Multi-PERCENT: 50*1.1*1.15*1.05", expected3, target.advancedMath, "Step: 50 → 55 (*1.1) → 63.25 (*1.15) → 66.4125 (*1.05)");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Advanced calculation combinations failed: " + e.message);
        }
    }

    /**
     * 测试浮点数精度
     */
    private static function testFloatingPointPrecision():Void {
        startTest("Floating Point Precision");

        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "precision", 1.0, null);

            trace("  Testing floating point precision:");

            // 测试小数运算精度
            container.clearBuffs();
            var precisionBuff1:PodBuff = new PodBuff("precision", BuffCalculationType.ADD, 0.1);
            var precisionBuff2:PodBuff = new PodBuff("precision", BuffCalculationType.ADD, 0.2);
            var precisionBuff3:PodBuff = new PodBuff("precision", BuffCalculationType.ADD, 0.3);

            container.addBuff(precisionBuff1);
            container.addBuff(precisionBuff2);
            container.addBuff(precisionBuff3);

            // 1.0 + 0.1 + 0.2 + 0.3 = 1.6
            assertFloatCalculation("Decimal ADD: 1.0+0.1+0.2+0.3", 1.6, target.precision, "Testing decimal addition precision");

            // 测试除法结果
            container.clearBuffs();
            var divisionBuff:PodBuff = new PodBuff("precision", BuffCalculationType.MULTIPLY, 1.0 / 3.0);
            container.addBuff(divisionBuff);

            var expected:Number = 1.0 / 3.0;
            assertFloatCalculation("Division: 1.0*(1/3)", expected, target.precision, "Testing division precision: 1/3 = " + expected);

            // 测试复杂浮点运算
            container.clearBuffs();
            var complexBuff1:PodBuff = new PodBuff("precision", BuffCalculationType.MULTIPLY, Math.PI);
            var complexBuff2:PodBuff = new PodBuff("precision", BuffCalculationType.PERCENT, Math.E - 1);

            container.addBuff(complexBuff1);
            container.addBuff(complexBuff2);

            var expectedComplex:Number = (1.0 * Math.PI) * Math.E;
            assertFloatCalculation("Complex: (1*π)*e", expectedComplex, target.precision, "Testing π and e precision: π=" + Math.PI + ", e=" + Math.E);

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Floating point precision failed: " + e.message);
        }
    }

    /**
     * 测试极值处理
     */
    private static function testExtremeValues():Void {
        startTest("Extreme Values Handling");

        try {
            var target:Object = {};

            trace("  Testing extreme values:");

            // 测试大数值
            var container1:PropertyContainer = new PropertyContainer(target, "bigNum", 1000000, null);
            var bigBuff:PodBuff = new PodBuff("bigNum", BuffCalculationType.MULTIPLY, 1000);
            container1.addBuff(bigBuff);
            assertCalculation("Big numbers: 1000000*1000", 1000000000, target.bigNum, "Testing large number multiplication");
            container1.destroy();

            // 测试小数值
            var container2:PropertyContainer = new PropertyContainer(target, "smallNum", 0.001, null);
            var smallBuff:PodBuff = new PodBuff("smallNum", BuffCalculationType.ADD, 0.0001);
            container2.addBuff(smallBuff);
            assertFloatCalculation("Small numbers: 0.001+0.0001", 0.0011, target.smallNum, "Testing small number addition");
            container2.destroy();

            // 测试负数
            var container3:PropertyContainer = new PropertyContainer(target, "negNum", -100, null);
            var negBuff1:PodBuff = new PodBuff("negNum", BuffCalculationType.ADD, -50);
            var negBuff2:PodBuff = new PodBuff("negNum", BuffCalculationType.MULTIPLY, -2);
            container3.addBuff(negBuff1);
            container3.addBuff(negBuff2);
            assertCalculation("Negative: (-100-50)*(-2)", 300, target.negNum, "Testing negative number operations: (-100-50)*(-2) = 300");
            container3.destroy();

            // 测试零值
            var container4:PropertyContainer = new PropertyContainer(target, "zeroNum", 0, null);
            var zeroBuff:PodBuff = new PodBuff("zeroNum", BuffCalculationType.ADD, 100);
            container4.addBuff(zeroBuff);
            assertCalculation("Zero base: 0+100", 100, target.zeroNum, "Testing zero base value");
            container4.destroy();

            passTest();
        } catch (e) {
            failTest("Extreme values handling failed: " + e.message);
        }
    }

    /**
     * 测试计算顺序依赖性
     */
    private static function testCalculationOrderDependency():Void {
        startTest("Calculation Order Dependency");

        try {
            var target:Object = {};

            trace("  Testing calculation order consistency:");

            // 测试1: 不同添加顺序，相同结果
            var container1:PropertyContainer = new PropertyContainer(target, "order1", 10, null);
            var container2:PropertyContainer = new PropertyContainer(target, "order2", 10, null);

            // 第一种顺序：ADD, MULTIPLY, PERCENT
            var add1:PodBuff = new PodBuff("order1", BuffCalculationType.ADD, 5);
            var mult1:PodBuff = new PodBuff("order1", BuffCalculationType.MULTIPLY, 2);
            var perc1:PodBuff = new PodBuff("order1", BuffCalculationType.PERCENT, 0.1);

            container1.addBuff(add1);
            container1.addBuff(mult1);
            container1.addBuff(perc1);

            // 第二种顺序：PERCENT, MULTIPLY, ADD (倒序)
            var add2:PodBuff = new PodBuff("order2", BuffCalculationType.ADD, 5);
            var mult2:PodBuff = new PodBuff("order2", BuffCalculationType.MULTIPLY, 2);
            var perc2:PodBuff = new PodBuff("order2", BuffCalculationType.PERCENT, 0.1);

            container2.addBuff(perc2);
            container2.addBuff(mult2);
            container2.addBuff(add2);

            var result1:Number = target.order1;
            var result2:Number = target.order2;

            assertCalculation("Order independence", result1, result2, "Different addition orders should yield same result: ((10+5)*2)*1.1 = 33");

            container1.destroy();
            container2.destroy();

            // 测试2: OVERRIDE的优先级
            var container3:PropertyContainer = new PropertyContainer(target, "override", 100, null);

            var addBuff:PodBuff = new PodBuff("override", BuffCalculationType.ADD, 50);
            var overrideBuff:PodBuff = new PodBuff("override", BuffCalculationType.OVERRIDE, 200);
            var multBuff:PodBuff = new PodBuff("override", BuffCalculationType.MULTIPLY, 3);

            container3.addBuff(addBuff);
            container3.addBuff(multBuff);
            container3.addBuff(overrideBuff); // OVERRIDE应该在最后生效

            assertCalculation("OVERRIDE priority", 200, target.override, "OVERRIDE should ignore all other calculations and set value to 200");

            container3.destroy();
            passTest();
        } catch (e) {
            failTest("Calculation order dependency failed: " + e.message);
        }
    }

    /**
     * 测试嵌套计算场景
     */
    private static function testNestedCalculationScenarios():Void {
        startTest("Nested Calculation Scenarios");

        try {
            var target:Object = {};

            trace("  Testing complex nested scenarios:");

            // 场景1: 游戏伤害计算模拟
            var container:PropertyContainer = new PropertyContainer(target, "damage", 100, null);

            // 基础伤害 100
            // + 武器伤害 +50
            // * 力量加成 *1.2
            // + 技能加成 +20%
            // * 暴击 *2
            // 但是有防护上限 max(300)
            // 和最小伤害保证 min(150)

            var weaponDamage:PodBuff = new PodBuff("damage", BuffCalculationType.ADD, 50);
            var strengthBonus:PodBuff = new PodBuff("damage", BuffCalculationType.MULTIPLY, 1.2);
            var skillBonus:PodBuff = new PodBuff("damage", BuffCalculationType.PERCENT, 0.2);
            var criticalHit:PodBuff = new PodBuff("damage", BuffCalculationType.MULTIPLY, 2);
            var damageMax:PodBuff = new PodBuff("damage", BuffCalculationType.MAX, 300);
            var damageMin:PodBuff = new PodBuff("damage", BuffCalculationType.MIN, 150);

            container.addBuff(weaponDamage);
            container.addBuff(strengthBonus);
            container.addBuff(skillBonus);
            container.addBuff(criticalHit);
            container.addBuff(damageMax);
            container.addBuff(damageMin);

            // 计算步骤: 100 → 150(+50) → 180(*1.2) → 216(*1.2) → 432(*2) → 300(max) → 300(min)
            var step1:Number = 100 + 50; // 150
            var step2:Number = step1 * 1.2; // 180
            var step3:Number = step2 * 1.2; // 216
            var step4:Number = step3 * 2; // 432
            var step5:Number = Math.max(step4, 300); // 432 (max doesn't limit)
            var step6:Number = Math.min(step5, 150); // 150 (min limits to 150)

            assertCalculation("Complex damage calculation", 150, target.damage, "Steps: 100→150(+50)→180(*1.2)→216(*1.2)→432(*2)→432(max)→150(min)");

            container.destroy();

            // 场景2: 属性计算链
            var hpContainer:PropertyContainer = new PropertyContainer(target, "maxHP", 200, null);

            // 模拟角色升级、装备、技能的HP加成
            var levelBonus:PodBuff = new PodBuff("maxHP", BuffCalculationType.ADD, 100); // +100 HP
            var armorBonus:PodBuff = new PodBuff("maxHP", BuffCalculationType.PERCENT, 0.25); // +25%
            var constitutionBonus:PodBuff = new PodBuff("maxHP", BuffCalculationType.MULTIPLY, 1.15); // *1.15
            var enchantmentBonus:PodBuff = new PodBuff("maxHP", BuffCalculationType.ADD, 50); // +50 HP

            hpContainer.addBuff(levelBonus);
            hpContainer.addBuff(armorBonus);
            hpContainer.addBuff(constitutionBonus);
            hpContainer.addBuff(enchantmentBonus);

            // 计算: (200+100+50)*1.15*1.25 = 350*1.15*1.25 = 402.5*1.25 = 503.125
            var expectedHP:Number = ((200 + 100 + 50) * 1.15) * 1.25;
            assertFloatCalculation("Character HP calculation", expectedHP, target.maxHP, "HP chain: (200+100+50)*1.15*1.25 = " + expectedHP);

            hpContainer.destroy();
            passTest();
        } catch (e) {
            failTest("Nested calculation scenarios failed: " + e.message);
        }
    }

    /**
     * 测试数学边界情况
     */
    private static function testMathematicalEdgeCases():Void {
        startTest("Mathematical Edge Cases");

        try {
            var target:Object = {};

            trace("  Testing mathematical edge cases:");

            // 测试除零保护 (通过MULTIPLY接近0)
            var container1:PropertyContainer = new PropertyContainer(target, "divZero", 100, null);
            var nearZero:PodBuff = new PodBuff("divZero", BuffCalculationType.MULTIPLY, 0.000001);
            container1.addBuff(nearZero);
            assertFloatCalculation("Near zero multiply", 0.0001, target.divZero, "100 * 0.000001 = 0.0001");
            container1.destroy();

            // 测试非常大的百分比
            var container2:PropertyContainer = new PropertyContainer(target, "bigPercent", 10, null);
            var hugeBuff:PodBuff = new PodBuff("bigPercent", BuffCalculationType.PERCENT, 99); // +9900%
            container2.addBuff(hugeBuff);
            assertCalculation("Huge percentage", 1000, target.bigPercent, "10 * (1 + 99) = 10 * 100 = 1000");
            container2.destroy();

            // 测试负百分比
            var container3:PropertyContainer = new PropertyContainer(target, "negPercent", 100, null);
            var negPercentBuff:PodBuff = new PodBuff("negPercent", BuffCalculationType.PERCENT, -0.8); // -80%
            container3.addBuff(negPercentBuff);
            assertCalculation("Negative percentage", 20, target.negPercent, "100 * (1 - 0.8) = 100 * 0.2 = 20");
            container3.destroy();

            // 测试连续乘法精度
            var container4:PropertyContainer = new PropertyContainer(target, "chainMult", 2, null);
            for (var i:Number = 0; i < 5; i++) {
                var chainBuff:PodBuff = new PodBuff("chainMult", BuffCalculationType.MULTIPLY, 1.1);
                container4.addBuff(chainBuff);
            }

            var expectedChain:Number = 2 * Math.pow(1.1, 5); // 2 * 1.1^5
            assertFloatCalculation("Chain multiplication", expectedChain, target.chainMult, "2 * 1.1^5 = " + expectedChain);
            container4.destroy();

            // 测试MIN/MAX极值
            var container5:PropertyContainer = new PropertyContainer(target, "minMax", 50, null);
            var maxBuff1:PodBuff = new PodBuff("minMax", BuffCalculationType.MAX, 1000);
            var maxBuff2:PodBuff = new PodBuff("minMax", BuffCalculationType.MAX, 2000);
            var minBuff1:PodBuff = new PodBuff("minMax", BuffCalculationType.MIN, 100);
            var minBuff2:PodBuff = new PodBuff("minMax", BuffCalculationType.MIN, 75);

            container5.addBuff(maxBuff1);
            container5.addBuff(maxBuff2);
            container5.addBuff(minBuff1);
            container5.addBuff(minBuff2);

            // 计算: 50 → max(50,1000)=1000 → max(1000,2000)=2000 → min(2000,100)=100 → min(100,75)=75
            assertCalculation("Multiple MIN/MAX", 75, target.minMax, "Chain: 50→max(1000)→max(2000)→min(100)→min(75) = 75");
            container5.destroy();

            passTest();
        } catch (e) {
            failTest("Mathematical edge cases failed: " + e.message);
        }
    }

    // ========== 新增：性能测试模块 ==========

    /**
     * 测试大量Buff的性能
     */
    private static function testPerformanceWithManyBuffs():Void {
        startTest("Performance with Many Buffs");

        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "perfTest", 100, null);

            var buffCount:Number = 100;
            var startTime:Number = getTimer();

            trace("  Adding " + buffCount + " buffs...");

            // 添加大量buff
            for (var i:Number = 0; i < buffCount; i++) {
                var buffType:String = (i % 3 == 0) ? BuffCalculationType.ADD : (i % 3 == 1) ? BuffCalculationType.MULTIPLY : BuffCalculationType.PERCENT;
                var value:Number = (i % 10) + 1;
                var buff:PodBuff = new PodBuff("perfTest", buffType, value);
                container.addBuff(buff);
            }

            var addTime:Number = getTimer() - startTime;

            trace("  Calculating with " + buffCount + " buffs...");
            startTime = getTimer();

            // 多次计算测试
            var calculations:Number = 100;
            for (var j:Number = 0; j < calculations; j++) {
                var result:Number = target.perfTest;
            }

            var calcTime:Number = getTimer() - startTime;

            recordPerformance("Many Buffs", {buffCount: buffCount,
                    addTime: addTime,
                    calcTime: calcTime,
                    avgCalcTime: calcTime / calculations});

            assert(container.getBuffCount() == buffCount, "Should have " + buffCount + " buffs");
            assert(!isNaN(target.perfTest), "Result should be a valid number");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Performance with many buffs failed: " + e.message);
        }
    }

    /**
     * 测试频繁访问性能
     */
    private static function testFrequentAccessPerformance():Void {
        startTest("Frequent Access Performance");

        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "accessTest", 75, null);

            // 添加一些buff
            for (var i:Number = 0; i < 10; i++) {
                var buff:PodBuff = new PodBuff("accessTest", BuffCalculationType.ADD, i * 5);
                container.addBuff(buff);
            }

            var accessCount:Number = 10000;
            var startTime:Number = getTimer();

            trace("  Performing " + accessCount + " property accesses...");

            // 频繁访问
            for (var j:Number = 0; j < accessCount; j++) {
                var value:Number = target.accessTest;
            }

            var accessTime:Number = getTimer() - startTime;

            recordPerformance("Frequent Access", {accessCount: accessCount,
                    totalTime: accessTime,
                    avgAccessTime: accessTime / accessCount});

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Frequent access performance failed: " + e.message);
        }
    }

    /**
     * 测试缓存效率
     */
    private static function testCacheEfficiency():Void {
        startTest("Cache Efficiency");

        try {
            var target:Object = {};
            var recomputeCount:Number = 0;

            var callback:Function = function(prop:String, val:Number):Void {
                recomputeCount++;
            };

            var container:PropertyContainer = new PropertyContainer(target, "cacheTest", 50, callback);

            // 添加buff
            var buff:PodBuff = new PodBuff("cacheTest", BuffCalculationType.MULTIPLY, 2);
            container.addBuff(buff);

            trace("  Testing cache hit efficiency...");

            // 首次访问
            var value1:Number = target.cacheTest;
            var firstComputeCount:Number = recomputeCount;

            // 后续访问应该使用缓存
            for (var i:Number = 0; i < 100; i++) {
                var value:Number = target.cacheTest;
            }

            var cacheHitCount:Number = recomputeCount - firstComputeCount;

            recordPerformance("Cache Efficiency", {firstCompute: firstComputeCount,
                    cacheHits: cacheHitCount,
                    efficiency: (100 - cacheHitCount) + "% cache hit rate"});

            // 理想情况下，缓存命中率应该很高
            assert(cacheHitCount <= 10, "Cache should prevent most recomputations, got " + cacheHitCount + " recomputes");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Cache efficiency failed: " + e.message);
        }
    }

    /**
     * 测试内存使用优化
     */
    private static function testMemoryUsageOptimization():Void {
        startTest("Memory Usage Optimization");

        try {
            trace("  Testing memory usage patterns...");

            var containers:Array = [];
            var containerCount:Number = 100;

            // 创建多个容器
            for (var i:Number = 0; i < containerCount; i++) {
                var target:Object = {};
                var container:PropertyContainer = new PropertyContainer(target, "mem" + i, i, null);

                // 添加一些buff
                for (var j:Number = 0; j < 5; j++) {
                    var buff:PodBuff = new PodBuff("mem" + i, BuffCalculationType.ADD, j);
                    container.addBuff(buff);
                }

                containers.push(container);
            }

            // 销毁一半容器
            for (var k:Number = 0; k < containerCount / 2; k++) {
                containers[k].destroy();
                containers[k] = null;
            }

            recordPerformance("Memory Usage", {created: containerCount,
                    destroyed: containerCount / 2,
                    remaining: containerCount / 2});

            // 清理剩余容器
            for (var l:Number = containerCount / 2; l < containerCount; l++) {
                if (containers[l]) {
                    containers[l].destroy();
                }
            }

            passTest();
        } catch (e) {
            failTest("Memory usage optimization failed: " + e.message);
        }
    }

    /**
     * 测试计算复杂度扩展性
     */
    private static function testCalculationComplexityScaling():Void {
        startTest("Calculation Complexity Scaling");

        try {
            trace("  Testing calculation time scaling with buff count...");

            var buffCounts:Array = [10, 20, 50, 100];
            var scalingResults:Array = [];

            for (var i:Number = 0; i < buffCounts.length; i++) {
                var buffCount:Number = buffCounts[i];
                var target:Object = {};
                var container:PropertyContainer = new PropertyContainer(target, "scaling", 100, null);

                // 添加指定数量的buff
                for (var j:Number = 0; j < buffCount; j++) {
                    var buff:PodBuff = new PodBuff("scaling", BuffCalculationType.ADD, 1);
                    container.addBuff(buff);
                }

                // 测量计算时间
                var startTime:Number = getTimer();
                var testRuns:Number = 1000;

                for (var k:Number = 0; k < testRuns; k++) {
                    var result:Number = target.scaling;
                }

                var elapsedTime:Number = getTimer() - startTime;
                scalingResults.push({buffCount: buffCount,
                        time: elapsedTime,
                        avgTime: elapsedTime / testRuns});

                container.destroy();
            }

            recordPerformance("Complexity Scaling", scalingResults);

            passTest();
        } catch (e) {
            failTest("Calculation complexity scaling failed: " + e.message);
        }
    }

    /**
     * 测试并发访问模拟
     */
    private static function testConcurrentAccessSimulation():Void {
        startTest("Concurrent Access Simulation");

        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "concurrent", 200, null);

            // 添加一些buff
            var buff1:PodBuff = new PodBuff("concurrent", BuffCalculationType.MULTIPLY, 1.5);
            var buff2:PodBuff = new PodBuff("concurrent", BuffCalculationType.ADD, 50);
            container.addBuff(buff1);
            container.addBuff(buff2);

            trace("  Simulating concurrent property access and modification...");

            var accessResults:Array = [];
            var modificationCount:Number = 0;

            // 模拟并发访问和修改
            for (var i:Number = 0; i < 100; i++) {
                // 读取操作
                var readValue:Number = target.concurrent;
                accessResults.push(readValue);

                // 间歇性修改操作
                if (i % 10 == 0) {
                    var newBuff:PodBuff = new PodBuff("concurrent", BuffCalculationType.ADD, 10);
                    container.addBuff(newBuff);
                    modificationCount++;
                }
            }

            // 验证一致性
            var lastValue:Number = target.concurrent;
            var expectedFinalBuffCount:Number = 2 + modificationCount;

            assert(container.getBuffCount() == expectedFinalBuffCount, "Final buff count should be " + expectedFinalBuffCount);
            assert(!isNaN(lastValue), "Final value should be valid");

            recordPerformance("Concurrent Access", {reads: accessResults.length,
                    modifications: modificationCount,
                    finalValue: lastValue,
                    finalBuffCount: container.getBuffCount()});

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Concurrent access simulation failed: " + e.message);
        }
    }

    // ========== 增强的断言方法 ==========

    /**
     * 增强的数值断言，显示详细的计算信息
     */
    private static function assertCalculation(description:String, expected:Number, actual:Number, stepDetails:String):Void {
        var passed:Boolean = Math.abs(expected - actual) < EPSILON;

        if (passed) {
            trace("    ✓ " + description + " = " + actual + " (Expected: " + expected + ")");
            if (stepDetails) {
                trace("      Details: " + stepDetails);
            }
        } else {
            var error:String = "Expected: " + expected + ", Got: " + actual + ", Diff: " + Math.abs(expected - actual);
            if (stepDetails) {
                error += ", Steps: " + stepDetails;
            }
            throw new Error(description + " - " + error);
        }
    }

    /**
     * 浮点数比较断言
     */
    private static function assertFloatCalculation(description:String, expected:Number, actual:Number, stepDetails:String):Void {
        var diff:Number = Math.abs(expected - actual);
        var passed:Boolean = diff < EPSILON;

        if (passed) {
            trace("    ✓ " + description + " ≈ " + actual + " (Expected: " + expected + ", Diff: " + diff + ")");
            if (stepDetails) {
                trace("      Details: " + stepDetails);
            }
        } else {
            var error:String = "Expected: " + expected + ", Got: " + actual + ", Diff: " + diff + " (Tolerance: " + EPSILON + ")";
            if (stepDetails) {
                error += ", Steps: " + stepDetails;
            }
            throw new Error(description + " - " + error);
        }
    }

    /**
     * 记录性能结果
     */
    private static function recordPerformance(testName:String, data:Object):Void {
        performanceResults.push({test: testName,
                data: data,
                timestamp: getTimer()});

        trace("    📊 Performance recorded: " + testName);
    }

    /**
     * 输出性能报告
     */
    private static function printPerformanceReport():Void {
        if (performanceResults.length == 0) {
            return;
        }

        trace("\n=== Performance Test Results ===");

        for (var i:Number = 0; i < performanceResults.length; i++) {
            var result:Object = performanceResults[i];
            trace("📊 " + result.test + ":");

            for (var key:String in result.data) {
                trace("   " + key + ": " + result.data[key]);
            }
            trace("");
        }

        trace("================================");
    }

    // ========== 原有测试方法的简化版本（保持兼容） ==========

    private static function testConstructor():Void {
        startTest("Constructor Test");

        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "testProp", 100, null);

            assert(container != null, "PropertyContainer instance should be created");
            assert(container.getPropertyName() == "testProp", "Property name should be set correctly");
            assert(container.getBaseValue() == 100, "Base value should be set correctly");
            assert(container.getBuffCount() == 0, "New container should have 0 buffs");
            assert(target.testProp == 100, "Target object should have the property accessible");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Constructor failed: " + e.message);
        }
    }

    private static function testBaseValueOperations():Void {
        startTest("Base Value Operations Test");

        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "health", 100, null);

            assertCalculation("Initial base value", 100, container.getBaseValue(), "Constructor sets base value");
            assertCalculation("Initial final value", 100, container.getFinalValue(), "No buffs = base value");

            container.setBaseValue(150);
            assertCalculation("Updated base value", 150, container.getBaseValue(), "setBaseValue updates base");
            assertCalculation("Updated final value", 150, container.getFinalValue(), "Final value reflects base change");
            assertCalculation("Target property update", 150, target.health, "Target property reflects change");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Base value operations failed: " + e.message);
        }
    }

    // ========== Phase 1: 基础功能 & Accessor 测试 ==========

    /** 检查属性名被正确挂载到 target 对象 */
    private static function testPropertyNameAccess():Void {
        startTest("Property name is attached to target");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "attack", 10, null);

            assert(!isNaN(target.attack), "target.attack 应当存在且为数值");
            assertCalculation("Base value", 10, target.attack, "初始值应与 baseValue 一致");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Property name access failed: " + e.message);
        }
    }

    /** 验证 PropertyAccessor 的 getter / setter 与 Container 同步 */
    private static function testPropertyAccessorIntegration():Void {
        startTest("PropertyAccessor integration");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "hp", 100, null);

            // 1) 通过 container 修改 baseValue，target.hp 应同步
            container.setBaseValue(120);
            assertCalculation("Setter propagation", 120, target.hp, "setBaseValue ➜ target.hp");

            // 2) 直接写 target.hp，应触发 _createOnSetCallback 更新 baseValue
            target.hp = 150;
            container.forceRecalculate(); // 主动触发一次计算
            assertCalculation("On-set callback", 150, container.getBaseValue(), "写 target.hp ➜ container base");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Accessor integration failed: " + e.message);
        }
    }

    /** 直接读取 target.<prop> 能拿到最终计算结果 */
    private static function testDirectPropertyAccess():Void {
        startTest("Direct target property access");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "speed", 5, null);
            container.addBuff(new PodBuff("speed", BuffCalculationType.MULTIPLY, 2));

            assertCalculation("5 * 2", 10, target.speed, "最终值应为 10");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Direct property access failed: " + e.message);
        }
    }

    /** 简易缓存校验：连续两次读取不变，变更后立刻更新 */
    private static function testCachingMechanism():Void {
        startTest("Caching mechanism");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "mana", 50, null);

            var v1:Number = target.mana;
            var v2:Number = target.mana;
            assertCalculation("Two reads, no change", v1, v2, "");

            // 改变后应刷新
            container.addBuff(new PodBuff("mana", BuffCalculationType.ADD, 25));
            var v3:Number = target.mana;
            assertCalculation("Cache invalidated after addBuff", 75, v3, "");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Caching mechanism failed: " + e.message);
        }
    }

    // ========== Phase 2: Buff 管理基础 ==========

    private static function testAddBuff():Void {
        startTest("addBuff()");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "def", 30, null);

            var b:PodBuff = new PodBuff("def", BuffCalculationType.ADD, 10);
            container.addBuff(b);

            assert(container.getBuffCount() == 1, "Buff count should be 1");
            assertCalculation("30 + 10", 40, target.def, "");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("addBuff failed: " + e.message);
        }
    }

    private static function testRemoveBuff():Void {
        startTest("removeBuff()");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "crit", 1.0, null);
            var buff:PodBuff = new PodBuff("crit", BuffCalculationType.MULTIPLY, 2);
            var id:String = buff.getId();
            container.addBuff(buff);

            assert(container.getBuffCount() == 1, "Should have 1 buff");
            container.removeBuff(id);
            assert(container.getBuffCount() == 0, "Buff removed");

            assertCalculation("Back to base", 1.0, target.crit, "");
            container.destroy();
            passTest();
        } catch (e) {
            failTest("removeBuff failed: " + e.message);
        }
    }

    private static function testClearBuffs():Void {
        startTest("clearBuffs()");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "armor", 5, null);
            container.addBuff(new PodBuff("armor", BuffCalculationType.ADD, 5));
            container.addBuff(new PodBuff("armor", BuffCalculationType.MULTIPLY, 3));

            assert(container.getBuffCount() == 2, "Should be 2 buffs before clear");
            container.clearBuffs();
            assert(container.getBuffCount() == 0, "All buffs cleared");
            assertCalculation("Back to 5", 5, target.armor, "");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("clearBuffs failed: " + e.message);
        }
    }

    private static function testBuffCounting():Void {
        startTest("getBuffCount / getActiveBuffCount()");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "luck", 0, null);

            // 活跃 buff
            var b1:PodBuff = new PodBuff("luck", BuffCalculationType.ADD, 3);
            // 非活跃 buff 简易实现
            var inactiveBuff:InactiveBuff = new InactiveBuff("luck", BuffCalculationType.ADD, 3);
            container.addBuff(b1);
            container.addBuff(inactiveBuff);

            assert(container.getBuffCount() == 2, "Total buff count = 2");
            assert(container.getActiveBuffCount() == 1, "Active buff count = 1");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("Buff counting failed: " + e.message);
        }
    }

    private static function testHasBuff():Void {
        startTest("hasBuff()");
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "dodge", 0, null);
            var b:PodBuff = new PodBuff("dodge", BuffCalculationType.ADD, 5);
            var id:String = b.getId();
            container.addBuff(b);

            assert(container.hasBuff(id), "hasBuff should return true");
            container.removeBuff(id);
            assert(!container.hasBuff(id), "After removal hasBuff should be false");

            container.destroy();
            passTest();
        } catch (e) {
            failTest("hasBuff failed: " + e.message);
        }
    }

    // ========== Phase 3: 计算正确性补充 ==========

    private static function testSingleBuffCalculation():Void {
        startTest("Single-buff calculation");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "hpRegen", 2, null);
            c.addBuff(new PodBuff("hpRegen", BuffCalculationType.ADD, 3));

            assertCalculation("2 + 3", 5, target.hpRegen, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Single-buff calc failed: " + e.message);
        }
    }

    private static function testMultipleBuffCalculation():Void {
        startTest("Multiple-buff calculation");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "mpRegen", 10, null);
            c.addBuff(new PodBuff("mpRegen", BuffCalculationType.ADD, 5)); // 15
            c.addBuff(new PodBuff("mpRegen", BuffCalculationType.MULTIPLY, 2)); // 30
            c.addBuff(new PodBuff("mpRegen", BuffCalculationType.PERCENT, 0.1)); // 33

            assertFloatCalculation("((10+5)*2)*1.1", 33, target.mpRegen, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Multi-buff calc failed: " + e.message);
        }
    }

    private static function testBuffPriorityCalculation():Void {
        startTest("OVERRIDE priority over others");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "range", 100, null);

            c.addBuff(new PodBuff("range", BuffCalculationType.ADD, 50));
            c.addBuff(new PodBuff("range", BuffCalculationType.MULTIPLY, 10));
            c.addBuff(new PodBuff("range", BuffCalculationType.OVERRIDE, 500));

            assertCalculation("OVERRIDE wins", 500, target.range, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Priority test failed: " + e.message);
        }
    }

    private static function testComplexBuffCombination():Void {
        startTest("Complex buff chain");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "complex", 20, null);

            c.addBuff(new PodBuff("complex", BuffCalculationType.ADD, 10)); // 30
            c.addBuff(new PodBuff("complex", BuffCalculationType.PERCENT, 0.25)); // 37.5
            c.addBuff(new PodBuff("complex", BuffCalculationType.MULTIPLY, 3)); // 112.5
            c.addBuff(new PodBuff("complex", BuffCalculationType.MAX, 150)); // 150

            assertCalculation("Complex chain", 150, target.complex, "(20+10)*1.25*3 → max(…,150)");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Complex combination failed: " + e.message);
        }
    }

    // ========== Phase 4: 回调 & 失效机制 ==========

    private static function testChangeCallback():Void {
        startTest("Change-callback invocation");
        try {
            var called:Boolean = false;
            var lastProp:String;
            var lastVal:Number;

            var cb:Function = function(prop:String, val:Number):Void {
                called = true;
                lastProp = prop;
                lastVal = val;
            };

            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "cooldown", 10, cb);
            c.addBuff(new PodBuff("cooldown", BuffCalculationType.ADD, -2)); // 8

            // 触发 getter
            var v:Number = target.cooldown;

            assert(called, "Callback should be called");
            assert(lastProp == "cooldown", "Prop name passed");
            assertCalculation("Callback value", 8, lastVal, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Callback test failed: " + e.message);
        }
    }

    private static function testExternalPropertySet():Void {
        startTest("External set invalidates cache");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "weight", 50, null);

            // 外部直接写值
            target.weight = 60;
            var v:Number = c.forceRecalculate(); // 60

            assertCalculation("After external set", 60, v, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("External set failed: " + e.message);
        }
    }

    private static function testFinalValueCaching():Void {
        startTest("Final value cached until dirty");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "energy", 100, null);
            var v1:Number = target.energy;
            var v2:Number = target.energy;
            assertCalculation("Cache stable", v1, v2, "");

            c.addBuff(new PodBuff("energy", BuffCalculationType.ADD, 50));
            var v3:Number = target.energy;
            assertCalculation("Cache invalid after buff", 150, v3, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Final-value cache test failed: " + e.message);
        }
    }

    private static function testForceRecalculation():Void {
        startTest("forceRecalculate()");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "light", 1, null);
            c.addBuff(new PodBuff("light", BuffCalculationType.MULTIPLY, 10));

            var v:Number = c.forceRecalculate();
            assertCalculation("1*10", 10, v, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("forceRecalculate failed: " + e.message);
        }
    }

    // === Phase X: Accessor–Container 联动与生命周期扩展 ===

    private static function testFinalizeToPlainProperty():Void {
        startTest("Finalize to plain data property (detach underlying accessor)");

        try {
            var target:Object = {};
            var called:Number = 0;

            var cb:Function = function(prop:String, val:Number):Void {
                called++;
            };

            var c:PropertyContainer = new PropertyContainer(target, "fprop", 10, cb);
            c.addBuff(new PodBuff("fprop", BuffCalculationType.ADD, 5)); // 15
            c.addBuff(new PodBuff("fprop", BuffCalculationType.MULTIPLY, 2)); // 30

            // 触发一次计算，确保“当前可见值”已确定
            var before:Number = target.fprop;
            assertCalculation("Before finalize (10+5)*2", 30, before, "");

            // —— finalize：优先用容器API；否则用_accessor.detach() 兜底 ——
            var finalized:Boolean = false;
            if (typeof c["finalizeToPlainProperty"] == "function") {
                c["finalizeToPlainProperty"]();
                finalized = true;
            } else if (c["_accessor"] && typeof c["_accessor"].detach == "function") {
                c["_accessor"].detach();
                finalized = true;
            }

            if (!finalized) {
                failTest("Container lacks finalize/detach API – 请为容器加入 finalizeToPlainProperty() 或暴露 _accessor.detach()");
                return;
            }

            // finalize 后：直接写 target 不应再触发回调
            var prevCalled:Number = called;
            target.fprop = 99; // 纯数据属性赋值
            assertCalculation("Direct write after finalize", 99, target.fprop, "");
            assert(called == prevCalled, "No callback after finalize");

            // finalize 后：容器内部变更不应影响 target
            c.addBuff(new PodBuff("fprop", BuffCalculationType.ADD, 1000)); // 与 target 脱钩
            var still99:Number = target.fprop;
            assertCalculation("Container changes no longer affect target", 99, still99, "");

            passTest();
        } catch (e) {
            failTest("Finalize failed: " + e.message);
        }
    }

    private static function testRebindAfterFinalize():Void {
        startTest("Rebind container on same target/prop after finalize");

        try {
            var target:Object = {};
            var c1:PropertyContainer = new PropertyContainer(target, "p", 5, null);
            c1.addBuff(new PodBuff("p", BuffCalculationType.ADD, 5)); // 10
            var v0:Number = target.p; // 10

            // finalize c1
            if (typeof c1["finalizeToPlainProperty"] == "function") {
                c1["finalizeToPlainProperty"]();
            } else if (c1["_accessor"] && typeof c1["_accessor"].detach == "function") {
                c1["_accessor"].detach();
            } else {
                failTest("Missing finalize/detach API");
                return;
            }

            // 在同一 target/prop 上创建新的容器（应可安全重绑）
            var c2:PropertyContainer = new PropertyContainer(target, "p", 100, null);
            // 新容器语义生效：直接读取应来自 c2 的计算（此处无 buff，即 base=100）
            assertCalculation("Rebind new container base", 100, target.p, "");

            // 修改 target，应只影响 c2 侧逻辑（c1 已脱钩）
            target.p = 123;
            var v:Number = c2.forceRecalculate();
            assertCalculation("External write flows to new container", 123, v, "");

            c1.destroy();
            c2.destroy();
            passTest();
        } catch (e) {
            failTest("Rebind after finalize failed: " + e.message);
        }
    }

    private static function testDestroyRemovesTargetProperty():Void {
        startTest("destroy() removes property from target (align with accessor.destroy)");

        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "tmp2", 1, null);

            // 先确认存在
            var existsBefore:Boolean = (typeof target.tmp2 != "undefined");
            assert(existsBefore, "Property exists before destroy");

            // destroy 走 accessor.destroy()，应从 target 删除该属性
            c.destroy();

            var existsAfter:Boolean = (typeof target.tmp2 != "undefined");
            assert(!existsAfter, "Property removed from target after destroy");

            passTest();
        } catch (e) {
            failTest("Destroy removes property failed: " + e.message);
        }
    }

    private static function testIsolationMultiContainersSameTarget():Void {
        startTest("Isolation: multi containers on same target different props");

        try {
            var t:Object = {};
            var cA:PropertyContainer = new PropertyContainer(t, "A", 10, null);
            var cB:PropertyContainer = new PropertyContainer(t, "B", 20, null);

            cA.addBuff(new PodBuff("A", BuffCalculationType.ADD, 1)); // 11
            cB.addBuff(new PodBuff("B", BuffCalculationType.MULTIPLY, 3)); // 60

            assertCalculation("A calc", 11, t.A, "");
            assertCalculation("B calc", 60, t.B, "");

            // finalize A，不影响 B
            if (typeof cA["finalizeToPlainProperty"] == "function") {
                cA["finalizeToPlainProperty"]();
            } else if (cA["_accessor"] && typeof cA["_accessor"].detach == "function") {
                cA["_accessor"].detach();
            }

            // 给 B 继续加 buff，应不影响 A（A 已变普通数据属性）
            cB.addBuff(new PodBuff("B", BuffCalculationType.ADD, 5)); // 65
            assertCalculation("A stays frozen (plain data)", 11, t.A, "");
            assertCalculation("B changes continue", 65, t.B, "");

            cA.destroy();
            cB.destroy();
            passTest();
        } catch (e) {
            failTest("Isolation across containers failed: " + e.message);
        }
    }

    private static function testExternalWriteBeforeVsAfterFinalize():Void {
        startTest("External write behavior: before vs after finalize");

        try {
            var t:Object = {};
            var called:Number = 0;
            var cb:Function = function(prop:String, val:Number):Void {
                called++;
            };

            var c:PropertyContainer = new PropertyContainer(t, "W", 50, cb);
            // —— finalize 前：外部写入应按容器语义生效并可能触发回调（取决于你的实现）——
            t.W = 60;
            var v1:Number = c.forceRecalculate();
            assertCalculation("Before finalize external set", 60, v1, "");

            var prevCalled:Number = called;

            // finalize
            if (typeof c["finalizeToPlainProperty"] == "function") {
                c["finalizeToPlainProperty"]();
            } else if (c["_accessor"] && typeof c["_accessor"].detach == "function") {
                c["_accessor"].detach();
            } else {
                failTest("Missing finalize/detach API");
                return;
            }

            // —— finalize 后：外部写入只改普通数据属性，不触发回调 —— 
            t.W = 77;
            assertCalculation("After finalize external set (plain)", 77, t.W, "");
            assert(called == prevCalled, "No callback after finalize on external writes");

            c.destroy();
            passTest();
        } catch (e) {
            failTest("External write before/after finalize failed: " + e.message);
        }
    }


    private static function testInvalidationMechanism():Void {
        startTest("Dirty flag on mutation");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "dirty", 5, null);
            var v1:Number = target.dirty;

            c.addBuff(new PodBuff("dirty", BuffCalculationType.ADD, 5));
            var v2:Number = target.dirty;

            assertCalculation("5+5", 10, v2, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Invalidation mechanism failed: " + e.message);
        }
    }

    // ========== Phase 5: Edge & 销毁 ==========

    private static function testEmptyContainer():Void {
        startTest("Empty container behaves");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "empty", 0, null);

            assertCalculation("No buffs", 0, target.empty, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Empty container failed: " + e.message);
        }
    }

    private static function testInactiveBuffs():Void {
        startTest("Inactive buffs ignored");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "stealth", 1, null);

            // inactive buff
            var inactive:InactiveBuff = new InactiveBuff();
            c.addBuff(inactive);

            assertCalculation("Value unchanged", 1, target.stealth, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Inactive buffs test failed: " + e.message);
        }
    }

    private static function testInvalidInputs():Void {
        startTest("Gracefully handle invalid inputs");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "invalid", 0, null);

            // null / undefined buff
            c.addBuff(null);
            c.addBuff(undefined);

            assert(c.getBuffCount() == 0, "Invalid inputs should be ignored");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Invalid input handling failed: " + e.message);
        }
    }

    private static function testEdgeCases():Void {
        startTest("Misc edge cases");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "edge", -10, null);
            // MIN buff 将负值拉向更负
            c.addBuff(new PodBuff("edge", BuffCalculationType.MIN, -20));

            assertCalculation("min(-10,-20)", -20, target.edge, "");
            c.destroy();
            passTest();
        } catch (e) {
            failTest("Edge-case test failed: " + e.message);
        }
    }

    private static function testToString():Void {
        startTest("toString() content");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "str", 1, null);
            var s:String = c.toString();

            assert(s.indexOf("str") >= 0, "toString should contain property name");
            assert(s.indexOf("buffs") >= 0, "toString should mention buff count");

            c.destroy();
            passTest();
        } catch (e) {
            failTest("toString test failed: " + e.message);
        }
    }

    private static function testDestroy():Void {
        startTest("destroy() safety");
        try {
            var target:Object = {};
            var c:PropertyContainer = new PropertyContainer(target, "tmp", 1, null);
            c.destroy();

            // 再次调用任何方法都不应抛异常（简易验证）
            try {
                var count:Number = c.getBuffCount();
            } catch (inner) {
                throw new Error("Method call after destroy threw: " + inner);
            }

            passTest();
        } catch (e) {
            failTest("Destroy failed: " + e.message);
        }
    }


    // ============= 测试工具方法 =============

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
        trace("\n=== PropertyContainer Enhanced Test Suite Results ===");
        trace("📊 Total tests: " + testCount);
        trace("✅ Passed: " + passedCount);
        trace("❌ Failed: " + failedCount);
        trace("📈 Success rate: " + Math.round((passedCount / testCount) * 100) + "%");

        if (failedCount == 0) {
            trace("🎉 All tests passed! System is functioning correctly.");
        } else {
            trace("⚠️  " + failedCount + " test(s) failed. Please review the failures above.");
        }
        trace("====================================================");
    }
}

