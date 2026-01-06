// org/flashNight/arki/component/Buff/test/BuffCalculatorTest.as

import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.test.*;

/**
 * BuffCalculator测试套件
 * 
 * 全面测试BuffCalculator类的所有功能，包括：
 * - 基础计算功能
 * - 不同计算类型处理 (ADD, MULTIPLY, PERCENT, OVERRIDE, MAX, MIN)
 * - 计算优先级顺序验证
 * - 复杂组合计算
 * - 边界条件和错误处理
 * - 与PodBuff的集成测试
 * 
 * 使用方式: BuffCalculatorTest.runAllTests();
 */
class org.flashNight.arki.component.Buff.test.BuffCalculatorTest {
    
    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;
    
    /**
     * 运行所有测试用例
     * 一句话启动: BuffCalculatorTest.runAllTests();
     */
    public static function runAllTests():Void {
        trace("=== BuffCalculator Test Suite Started ===");
        
        // 重置测试计数器
        testCount = 0;
        passedCount = 0;
        failedCount = 0;
        
        // 基础功能测试
        testConstructor();
        testBasicCalculation();
        testReset();
        testGetModificationCount();
        
        // 计算类型测试
        testAddModification();
        testMultiplyModification();
        testPercentModification();
        testOverrideModification();
        testMaxModification();
        testMinModification();
        
        // 优先级和组合测试
        testCalculationPriority();
        testComplexCombination();
        testMultipleSameType();
        
        // PodBuff集成测试
        testPodBuffIntegration();
        testMultiplePodBuffs();
        
        // 边界条件测试
        testEmptyCalculation();
        testInvalidInputs();
        testLargeNumbers();
        testEdgeCases();
        
        // 性能和限制测试
        testMaxModificationLimit();
        
        // 输出测试结果
        printTestResults();
    }
    
    /**
     * 测试构造函数
     */
    private static function testConstructor():Void {
        startTest("Constructor Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            
            assert(calculator != null, "BuffCalculator instance should be created");
            assert(calculator.getModificationCount() == 0, "New calculator should have 0 modifications");
            assert(calculator.calculate(100) == 100, "Empty calculator should return base value");
            
            passTest();
        } catch (e) {
            failTest("Constructor failed: " + e.message);
        }
    }
    
    /**
     * 测试基础计算功能
     */
    private static function testBasicCalculation():Void {
        startTest("Basic Calculation Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // 测试空计算器
            assert(calculator.calculate(baseValue) == baseValue, "Empty calculator should return base value");
            
            // 添加一个修改并测试
            calculator.addModification(BuffCalculationType.ADD, 50);
            assert(calculator.calculate(baseValue) == 150, "ADD 50 should result in 150");
            
            passTest();
        } catch (e) {
            failTest("Basic calculation failed: " + e.message);
        }
    }
    
    /**
     * 测试reset功能
     */
    private static function testReset():Void {
        startTest("Reset Functionality Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            
            // 添加一些修改
            calculator.addModification(BuffCalculationType.ADD, 50);
            calculator.addModification(BuffCalculationType.MULTIPLY, 2);
            assert(calculator.getModificationCount() == 2, "Should have 2 modifications");
            
            // 重置
            calculator.reset();
            assert(calculator.getModificationCount() == 0, "Should have 0 modifications after reset");
            assert(calculator.calculate(100) == 100, "Should return base value after reset");
            
            passTest();
        } catch (e) {
            failTest("Reset test failed: " + e.message);
        }
    }
    
    /**
     * 测试修改计数功能
     */
    private static function testGetModificationCount():Void {
        startTest("Modification Count Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            
            assert(calculator.getModificationCount() == 0, "Initial count should be 0");
            
            calculator.addModification(BuffCalculationType.ADD, 10);
            assert(calculator.getModificationCount() == 1, "Count should be 1 after first modification");
            
            calculator.addModification(BuffCalculationType.MULTIPLY, 1.5);
            assert(calculator.getModificationCount() == 2, "Count should be 2 after second modification");
            
            calculator.reset();
            assert(calculator.getModificationCount() == 0, "Count should be 0 after reset");
            
            passTest();
        } catch (e) {
            failTest("Modification count test failed: " + e.message);
        }
    }
    
    /**
     * 测试ADD类型修改
     */
    private static function testAddModification():Void {
        startTest("ADD Modification Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // 单个ADD
            calculator.addModification(BuffCalculationType.ADD, 25);
            assert(calculator.calculate(baseValue) == 125, "100 + 25 should equal 125");
            
            calculator.reset();
            
            // 多个ADD
            calculator.addModification(BuffCalculationType.ADD, 10);
            calculator.addModification(BuffCalculationType.ADD, 20);
            calculator.addModification(BuffCalculationType.ADD, 30);
            assert(calculator.calculate(baseValue) == 160, "100 + 10 + 20 + 30 should equal 160");
            
            // 负数ADD
            calculator.reset();
            calculator.addModification(BuffCalculationType.ADD, -25);
            assert(calculator.calculate(baseValue) == 75, "100 + (-25) should equal 75");
            
            passTest();
        } catch (e) {
            failTest("ADD modification test failed: " + e.message);
        }
    }
    
    /**
     * 测试MULTIPLY类型修改
     */
    private static function testMultiplyModification():Void {
        startTest("MULTIPLY Modification Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // 单个MULTIPLY
            calculator.addModification(BuffCalculationType.MULTIPLY, 1.5);
            assert(calculator.calculate(baseValue) == 150, "100 * 1.5 should equal 150");
            
            calculator.reset();
            
            // 多个MULTIPLY
            calculator.addModification(BuffCalculationType.MULTIPLY, 2);
            calculator.addModification(BuffCalculationType.MULTIPLY, 1.5);
            assert(calculator.calculate(baseValue) == 300, "100 * 2 * 1.5 should equal 300");
            
            // 小数MULTIPLY
            calculator.reset();
            calculator.addModification(BuffCalculationType.MULTIPLY, 0.5);
            assert(calculator.calculate(baseValue) == 50, "100 * 0.5 should equal 50");
            
            passTest();
        } catch (e) {
            failTest("MULTIPLY modification test failed: " + e.message);
        }
    }
    
    /**
     * 测试PERCENT类型修改
     */
    private static function testPercentModification():Void {
        startTest("PERCENT Modification Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // 单个PERCENT (50%增加)
            calculator.addModification(BuffCalculationType.PERCENT, 0.5);
            assert(calculator.calculate(baseValue) == 150, "100 * (1 + 0.5) should equal 150");
            
            calculator.reset();
            
            // 多个PERCENT
            calculator.addModification(BuffCalculationType.PERCENT, 0.2); // +20%
            calculator.addModification(BuffCalculationType.PERCENT, 0.3); // +30%
            // 结果应该是 100 * (1 + 0.2) * (1 + 0.3) = 100 * 1.2 * 1.3 = 156
            assert(calculator.calculate(baseValue) == 156, "100 * 1.2 * 1.3 should equal 156");
            
            // 负PERCENT (减少)
            calculator.reset();
            calculator.addModification(BuffCalculationType.PERCENT, -0.25); // -25%
            assert(calculator.calculate(baseValue) == 75, "100 * (1 - 0.25) should equal 75");
            
            passTest();
        } catch (e) {
            failTest("PERCENT modification test failed: " + e.message);
        }
    }
    
    /**
     * 测试OVERRIDE类型修改
     */
    private static function testOverrideModification():Void {
        startTest("OVERRIDE Modification Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // 单个OVERRIDE
            calculator.addModification(BuffCalculationType.OVERRIDE, 200);
            assert(calculator.calculate(baseValue) == 200, "OVERRIDE should set value to 200");
            
            calculator.reset();
            
            // 多个OVERRIDE (最后一个生效)
            calculator.addModification(BuffCalculationType.OVERRIDE, 150);
            calculator.addModification(BuffCalculationType.OVERRIDE, 175);
            calculator.addModification(BuffCalculationType.OVERRIDE, 200);
            assert(calculator.calculate(baseValue) == 200, "Last OVERRIDE should win");
            
            // OVERRIDE与其他类型混合 (OVERRIDE应该最后应用)
            calculator.reset();
            calculator.addModification(BuffCalculationType.ADD, 50);
            calculator.addModification(BuffCalculationType.MULTIPLY, 2);
            calculator.addModification(BuffCalculationType.OVERRIDE, 300);
            assert(calculator.calculate(baseValue) == 300, "OVERRIDE should ignore all other modifications");
            
            passTest();
        } catch (e) {
            failTest("OVERRIDE modification test failed: " + e.message);
        }
    }
    
    /**
     * 测试MAX类型修改
     */
    private static function testMaxModification():Void {
        startTest("MAX Modification Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // MAX大于计算结果
            calculator.addModification(BuffCalculationType.ADD, 20); // 结果120
            calculator.addModification(BuffCalculationType.MAX, 150);
            assert(calculator.calculate(baseValue) == 150, "MAX 150 should override lower result 120");
            
            calculator.reset();
            
            // MAX小于计算结果
            calculator.addModification(BuffCalculationType.ADD, 80); // 结果180
            calculator.addModification(BuffCalculationType.MAX, 150);
            assert(calculator.calculate(baseValue) == 180, "MAX 150 should not affect higher result 180");
            
            // 多个MAX
            calculator.reset();
            calculator.addModification(BuffCalculationType.ADD, 10); // 结果110
            calculator.addModification(BuffCalculationType.MAX, 120);
            calculator.addModification(BuffCalculationType.MAX, 130);
            calculator.addModification(BuffCalculationType.MAX, 125);
            assert(calculator.calculate(baseValue) == 130, "Highest MAX should be applied");
            
            passTest();
        } catch (e) {
            failTest("MAX modification test failed: " + e.message);
        }
    }
    
    /**
     * 测试MIN类型修改
     */
    private static function testMinModification():Void {
        startTest("MIN Modification Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // MIN小于计算结果
            calculator.addModification(BuffCalculationType.ADD, 50); // 结果150
            calculator.addModification(BuffCalculationType.MIN, 120);
            assert(calculator.calculate(baseValue) == 120, "MIN 120 should limit higher result 150");
            
            calculator.reset();
            
            // MIN大于计算结果
            calculator.addModification(BuffCalculationType.ADD, 10); // 结果110
            calculator.addModification(BuffCalculationType.MIN, 120);
            assert(calculator.calculate(baseValue) == 110, "MIN 120 should not affect lower result 110");
            
            // 多个MIN
            calculator.reset();
            calculator.addModification(BuffCalculationType.ADD, 100); // 结果200
            calculator.addModification(BuffCalculationType.MIN, 180);
            calculator.addModification(BuffCalculationType.MIN, 170);
            calculator.addModification(BuffCalculationType.MIN, 175);
            assert(calculator.calculate(baseValue) == 170, "Lowest MIN should be applied");
            
            passTest();
        } catch (e) {
            failTest("MIN modification test failed: " + e.message);
        }
    }
    
    /**
     * 测试计算优先级顺序
     * 新顺序（对齐老系统: 基础值 × 倍率 + 加算）:
     * 1. MULTIPLY (乘算)
     * 2. PERCENT (百分比)
     * 3. ADD (加算) - 在乘法之后
     * 4. MAX (最小保底)
     * 5. MIN (最大封顶)
     * 6. OVERRIDE (覆盖)
     */
    private static function testCalculationPriority():Void {
        startTest("Calculation Priority Test");

        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;

            // 测试固定顺序：基础值 -> 乘法 -> 百分比 -> 加法 -> 最大值 -> 最小值 -> 覆盖
            // 添加顺序故意打乱，验证内部排序
            calculator.addModification(BuffCalculationType.MULTIPLY, 2);      // 第1步: 100 * 2 = 200
            calculator.addModification(BuffCalculationType.MIN, 350);         // 第5步: min(360, 350) = 350
            calculator.addModification(BuffCalculationType.ADD, 100);         // 第3步: 260 + 100 = 360
            calculator.addModification(BuffCalculationType.PERCENT, 0.3);     // 第2步: 200 * 1.3 = 260
            calculator.addModification(BuffCalculationType.MAX, 300);         // 第4步: max(360, 300) = 360

            var result:Number = calculator.calculate(baseValue);
            // 预期计算过程: 100 -> 200(*2) -> 260(*1.3) -> 360(+100) -> 360(max) -> 350(min) = 350
            assert(result == 350, "Priority calculation should result in 350, got: " + result);

            passTest();
        } catch (e) {
            failTest("Calculation priority test failed: " + e.message);
        }
    }
    
    /**
     * 测试复杂组合计算
     * 新顺序: 基础值 × MULTIPLY × (1+PERCENT) + ADD
     */
    private static function testComplexCombination():Void {
        startTest("Complex Combination Test");

        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 50;

            // 复杂场景：武器基础攻击力50，暴击2倍，技能增加50%，装备+30，但不超过200
            // 新计算顺序: 50 * 2 * 1.5 + 30 = 180，min(180, 200) = 180
            calculator.addModification(BuffCalculationType.ADD, 30);         // 装备加成（后置）: 150 + 30 = 180
            calculator.addModification(BuffCalculationType.PERCENT, 0.5);    // 技能增加: 100 * 1.5 = 150
            calculator.addModification(BuffCalculationType.MULTIPLY, 2);     // 暴击倍数: 50 * 2 = 100
            calculator.addModification(BuffCalculationType.MIN, 200);        // 伤害上限: min(180, 200) = 180

            var result:Number = calculator.calculate(baseValue);
            // 预期计算过程: 50 -> 100(*2) -> 150(*1.5) -> 180(+30) -> 180(min) = 180
            assert(result == 180, "Complex combination should result in 180, got: " + result);

            passTest();
        } catch (e) {
            failTest("Complex combination test failed: " + e.message);
        }
    }
    
    /**
     * 测试相同类型的多个修改
     */
    private static function testMultipleSameType():Void {
        startTest("Multiple Same Type Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // 多个ADD
            calculator.addModification(BuffCalculationType.ADD, 10);
            calculator.addModification(BuffCalculationType.ADD, 20);
            calculator.addModification(BuffCalculationType.ADD, 30);
            assert(calculator.calculate(baseValue) == 160, "Multiple ADD: 100+10+20+30=160");
            
            calculator.reset();
            
            // 多个MULTIPLY
            calculator.addModification(BuffCalculationType.MULTIPLY, 1.2);
            calculator.addModification(BuffCalculationType.MULTIPLY, 1.5);
            calculator.addModification(BuffCalculationType.MULTIPLY, 2);
            assert(calculator.calculate(baseValue) == 360, "Multiple MULTIPLY: 100*1.2*1.5*2=360");
            
            passTest();
        } catch (e) {
            failTest("Multiple same type test failed: " + e.message);
        }
    }
    
    /**
     * 测试与PodBuff的集成
     */
    private static function testPodBuffIntegration():Void {
        startTest("PodBuff Integration Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            
            // 创建PodBuff
            var attackBuff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 25);
            var context:BuffContext = new BuffContext("attack", null, null, {});
            
            // 应用PodBuff
            attackBuff.applyEffect(calculator, context);
            assert(calculator.calculate(baseValue) == 125, "PodBuff ADD should work: 100+25=125");
            
            calculator.reset();
            
            // 测试不匹配的属性
            var defenseContext:BuffContext = new BuffContext("defense", null, null, {});
            attackBuff.applyEffect(calculator, defenseContext);
            assert(calculator.calculate(baseValue) == baseValue, "PodBuff should not affect different property");
            
            passTest();
        } catch (e) {
            failTest("PodBuff integration test failed: " + e.message);
        }
    }
    
    /**
     * 测试多个PodBuff
     * 新顺序: 基础值 × MULTIPLY × (1+PERCENT) + ADD
     */
    private static function testMultiplePodBuffs():Void {
        startTest("Multiple PodBuffs Test");

        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var baseValue:Number = 100;
            var context:BuffContext = new BuffContext("attack", null, null, {});

            // 创建多个PodBuff
            var addBuff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 20);
            var multiplyBuff:PodBuff = new PodBuff("attack", BuffCalculationType.MULTIPLY, 1.5);
            var percentBuff:PodBuff = new PodBuff("attack", BuffCalculationType.PERCENT, 0.2);

            // 依次应用
            addBuff.applyEffect(calculator, context);
            multiplyBuff.applyEffect(calculator, context);
            percentBuff.applyEffect(calculator, context);

            // 新计算顺序: 100 -> 150(*1.5) -> 180(*1.2) -> 200(+20)
            var result:Number = calculator.calculate(baseValue);
            assert(result == 200, "Multiple PodBuffs should result in 200, got: " + result);

            passTest();
        } catch (e) {
            failTest("Multiple PodBuffs test failed: " + e.message);
        }
    }
    
    /**
     * 测试空计算
     */
    private static function testEmptyCalculation():Void {
        startTest("Empty Calculation Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            
            // 测试各种基础值
            assert(calculator.calculate(0) == 0, "Empty calculator with 0 should return 0");
            assert(calculator.calculate(100) == 100, "Empty calculator with 100 should return 100");
            assert(calculator.calculate(-50) == -50, "Empty calculator with -50 should return -50");
            assert(calculator.calculate(0.5) == 0.5, "Empty calculator with 0.5 should return 0.5");
            
            passTest();
        } catch (e) {
            failTest("Empty calculation test failed: " + e.message);
        }
    }
    
    /**
     * 测试无效输入
     */
    private static function testInvalidInputs():Void {
        startTest("Invalid Inputs Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var initialCount:Number = calculator.getModificationCount();
            
            // 测试无效的type (null和空字符串应该被拒绝)
            calculator.addModification(null, 10);
            calculator.addModification("", 10);
            assert(calculator.getModificationCount() == initialCount, "Null and empty types should be rejected");
            
            // 测试无效的value
            calculator.addModification(BuffCalculationType.ADD, NaN);
            assert(calculator.getModificationCount() == initialCount, "NaN values should be rejected");
            
            // 测试有效输入仍然工作
            calculator.addModification(BuffCalculationType.ADD, 10);
            assert(calculator.getModificationCount() == initialCount + 1, "Valid input should still work");
            
            // 注意：无效的type字符串(如"invalid_type")会被接受但在计算时被忽略
            // 这是设计上的选择，因为BuffCalculator只验证null和NaN，而不是所有可能的无效值
            
            passTest();
        } catch (e) {
            failTest("Invalid inputs test failed: " + e.message);
        }
    }
    
    /**
     * 测试大数值
     */
    private static function testLargeNumbers():Void {
        startTest("Large Numbers Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            var largeBase:Number = 999999;
            
            calculator.addModification(BuffCalculationType.ADD, 1000000);
            calculator.addModification(BuffCalculationType.MULTIPLY, 2);

            var result:Number = calculator.calculate(largeBase);
            // 新计算顺序: 999999 * 2 + 1000000 = 2999998
            var expected:Number = largeBase * 2 + 1000000;
            assert(result == expected, "Large number calculation should work correctly");
            
            passTest();
        } catch (e) {
            failTest("Large numbers test failed: " + e.message);
        }
    }
    
    /**
     * 测试边界情况
     */
    private static function testEdgeCases():Void {
        startTest("Edge Cases Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            
            // 测试零乘法
            calculator.addModification(BuffCalculationType.MULTIPLY, 0);
            assert(calculator.calculate(100) == 0, "Multiply by 0 should result in 0");
            
            calculator.reset();
            
            // 测试负数基础值
            calculator.addModification(BuffCalculationType.ADD, 150);
            assert(calculator.calculate(-100) == 50, "Negative base value should work: -100+150=50");
            
            calculator.reset();
            
            // 测试浮点数精度
            calculator.addModification(BuffCalculationType.ADD, 0.1);
            calculator.addModification(BuffCalculationType.ADD, 0.2);
            var result:Number = calculator.calculate(0);
            assert(Math.abs(result - 0.3) < 0.0001, "Floating point precision should be acceptable");
            
            passTest();
        } catch (e) {
            failTest("Edge cases test failed: " + e.message);
        }
    }
    
    /**
     * 测试修改数量限制
     */
    private static function testMaxModificationLimit():Void {
        startTest("Max Modification Limit Test");
        
        try {
            var calculator:BuffCalculator = new BuffCalculator();
            
            // 先测试一个小数量确保正常工作
            calculator.addModification(BuffCalculationType.ADD, 1);
            assert(calculator.getModificationCount() == 1, "Should accept first modification");
            
            // 重置并开始限制测试
            calculator.reset();
            var maxLimit:Number = 100; // 根据实际的BuffCalculator.MAX_MODIFICATIONS调整
            var addedCount:Number = 0;
            
            // 添加到限制数量 - 循环添加直到被拒绝
            for (var i:Number = 0; i < maxLimit + 10; i++) { // 多试几个确保到达限制
                var beforeCount:Number = calculator.getModificationCount();
                calculator.addModification(BuffCalculationType.ADD, 1);
                var afterCount:Number = calculator.getModificationCount();
                
                if (afterCount > beforeCount) {
                    addedCount++;
                } else {
                    // 第一次被拒绝，说明到达了限制
                    break;
                }
            }
            
            assert(addedCount >= 50, "Should accept reasonable number of modifications (at least 50)");
            assert(addedCount <= 200, "Should have some limit (not more than 200)");
            
            // 验证确实到达了限制
            var finalCount:Number = calculator.getModificationCount();
            calculator.addModification(BuffCalculationType.ADD, 1);
            assert(calculator.getModificationCount() == finalCount, "Should reject modifications at limit");
            
            passTest();
        } catch (e) {
            failTest("Max modification limit test failed: " + e.message);
        }
    }
    
    // ============= 测试工具方法 =============
    
    private static function startTest(testName:String):Void {
        testCount++;
        trace("Running test " + testCount + ": " + testName);
    }
    
    private static function passTest():Void {
        passedCount++;
        trace("  ✓ PASSED");
    }
    
    private static function failTest(message:String):Void {
        failedCount++;
        trace("  ✗ FAILED: " + message);
    }
    
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }
    
    private static function printTestResults():Void {
        trace("=== BuffCalculator Test Suite Results ===");
        trace("Total tests: " + testCount);
        trace("Passed: " + passedCount);
        trace("Failed: " + failedCount);
        trace("Success rate: " + Math.round((passedCount / testCount) * 100) + "%");
        
        if (failedCount == 0) {
            trace("🎉 All tests passed!");
        } else {
            trace("❌ " + failedCount + " test(s) failed");
        }
        trace("========================================");
    }
}