import org.flashNight.gesh.func.*;

class org.flashNight.gesh.func.LazyValueTest {
    private static var testResults:Array = [];

    /**
     * 断言方法：用于验证实际值是否等于期望值
     * @param {*} actual 实际值
     * @param {*} expected 期望值
     * @param {String} message 测试用例描述
     */
    private static function assertEquals(actual, expected, message:String):Void {
        if (actual === expected) {
            trace("[PASS] " + message);
            testResults.push({ result: "PASS", message: message });
        } else {
            trace("[FAIL] " + message + " - Expected: " + expected + ", Got: " + actual);
            testResults.push({ result: "FAIL", message: message });
        }
    }

    /**
     * 测试 LazyValue 的基本功能
     */
    public static function testBasicFunctionality():Void {
        trace("Running: testBasicFunctionality");

        var evaluatorCallCount:Number = 0;  // 计数器

        var lazyValue = new LazyValue(function() {
            evaluatorCallCount++;
            trace("Evaluator executed");
            return 42;
        });

        // 确保初始时不执行 evaluator
        assertEquals(evaluatorCallCount, 0, "Evaluator should not be executed initially");

        // 第一次获取值时执行 evaluator
        var value = lazyValue.get();
        assertEquals(value, 42, "LazyValue should return 42 on first evaluation");
        assertEquals(evaluatorCallCount, 1, "Evaluator should be executed once after first get");

        // 确保 evaluator 只执行一次
        value = lazyValue.get();
        assertEquals(value, 42, "LazyValue should return cached value on subsequent calls");
        assertEquals(evaluatorCallCount, 1, "Evaluator should not be executed again on subsequent get");
    }

    /**
     * 测试 LazyValue 的 map 功能
     */
    public static function testMapFunction():Void {
        trace("Running: testMapFunction");

        var baseEvaluatorCallCount:Number = 0;  // 基础 evaluator 的计数器

        var baseValue = new LazyValue(function() {
            baseEvaluatorCallCount++;
            trace("Base evaluator executed");
            return 10;
        });

        var mappedEvaluatorCallCount:Number = 0;  // 映射 evaluator 的计数器

        var mappedValue = baseValue.map(function(value) {
            mappedEvaluatorCallCount++;
            return value * 2;
        });

        // 确保 map 不执行原始 evaluator
        assertEquals(baseEvaluatorCallCount, 0, "Base evaluator should not be executed initially");

        // 第一次获取 mappedValue，执行 base evaluator 和转换函数
        var result = mappedValue.get();
        assertEquals(result, 20, "Mapped value should be 20 after transformation");
        assertEquals(baseEvaluatorCallCount, 1, "Base evaluator should be executed once");
        assertEquals(mappedEvaluatorCallCount, 1, "Mapped transformer should be executed once");

        // 确保 baseValue 没有再次执行 evaluator
        var baseResult = baseValue.get();
        assertEquals(baseResult, 10, "Base value should remain 10");
        assertEquals(baseEvaluatorCallCount, 1, "Base evaluator should not be executed again");
    }

    /**
     * 测试 LazyValue 的重置功能
     */
    public static function testResetFunction():Void {
        trace("Running: testResetFunction");

        var initialEvaluatorCallCount:Number = 0;
        var lazyValue = new LazyValue(function() {
            initialEvaluatorCallCount++;
            return 1;
        });

        var value = lazyValue.get();
        assertEquals(value, 1, "Initial value should be 1");
        assertEquals(initialEvaluatorCallCount, 1, "Initial evaluator should be executed once");

        // 重置后，检查新的 evaluator 是否生效
        var newEvaluatorCallCount:Number = 0;
        lazyValue.reset(function() {
            newEvaluatorCallCount++;
            return 100;
        });

        // 在重置后，newEvaluator 还未被执行
        assertEquals(newEvaluatorCallCount, 0, "New evaluator should not be executed after reset");

        // 调用 get，执行新的 evaluator
        var newValue = lazyValue.get();
        assertEquals(newValue, 100, "Value should be updated to 100 after reset");
        assertEquals(newEvaluatorCallCount, 1, "New evaluator should be executed once after reset");

        // 确保新的 evaluator 不再执行
        newValue = lazyValue.get();
        assertEquals(newValue, 100, "Value should remain 100 after subsequent calls");
        assertEquals(newEvaluatorCallCount, 1, "New evaluator should not be executed again");
    }

    /**
     * 测试边界情况
     */
    public static function testEdgeCases():Void {
        trace("Running: testEdgeCases");

        // 测试空 evaluator
        try {
            var invalidValue = new LazyValue(null);
            trace("[FAIL] Should throw an error when evaluator is null");
            testResults.push({ result: "FAIL", message: "Should throw an error when evaluator is null" });
        } catch (e:Error) {
            trace("[PASS] Throws error on null evaluator");
            testResults.push({ result: "PASS", message: "Throws error on null evaluator" });
        }

        // 测试多次 reset
        var resetEvaluatorCallCount:Number = 0;
        var lazyValue = new LazyValue(function() {
            return "Initial";
        });

        // 重置多次
        lazyValue.reset(function() {
            resetEvaluatorCallCount++;
            return "Reset1";
        });
        lazyValue.reset(function() {
            resetEvaluatorCallCount++;
            return "Reset2";
        });

        // 在重置后，调用 get 应该执行最后一个 evaluator
        assertEquals(resetEvaluatorCallCount, 0, "After multiple resets, evaluators should not be executed yet");

        var finalValue = lazyValue.get();
        assertEquals(finalValue, "Reset2", "Value should be 'Reset2' after multiple resets");
        assertEquals(resetEvaluatorCallCount, 1, "Only the last reset evaluator should be executed once");

        // 确保再次调用 get 不会再次执行 evaluator
        finalValue = lazyValue.get();
        assertEquals(finalValue, "Reset2", "Value should remain 'Reset2' after subsequent calls");
        assertEquals(resetEvaluatorCallCount, 1, "Evaluator should not be executed again after subsequent calls");
    }

    /**
     * 性能测试：评估 LazyValue 的性能
     */
    public static function testPerformance():Void {
        trace("Running: testPerformance");

        var start:Number = getTimer();
        var lazyValue = new LazyValue(function() {
            return 42;
        });

        // 第一次调用 get() 会执行 evaluator
        lazyValue.get();

        // 记录第一次调用后的时间
        var afterFirstGet:Number = getTimer();

        // 多次调用 get() 应该是直接返回缓存值
        for (var i:Number = 0; i < 2000; i++) {
            lazyValue.get();
            lazyValue.get();
            lazyValue.get();
            lazyValue.get();
            lazyValue.get();
        }
        var duration:Number = getTimer() - start;
        trace("Performance Test: 10000 calls took " + duration + "ms");

        // 惰性求值 get() 非常快速，设置一个合理的阈值
        // 设计来说可能需要以10ms为阈值
        var performanceThreshold:Number = 10;  // 50ms
        var pass:Boolean = duration < performanceThreshold;
        assertEquals(pass, true, "LazyValue should be performant for repeated calls");
    }

    /**
     * 运行所有测试
     */
    public static function runTests():Void {
        trace("Starting LazyValue Tests...");

        testBasicFunctionality();
        testMapFunction();
        testResetFunction();
        testEdgeCases();
        testPerformance();

        trace("Test Results: " + testResults.length + " cases executed");
        for (var i:Number = 0; i < testResults.length; i++) {
            trace(testResults[i].result + ": " + testResults[i].message);
        }
    }
}
