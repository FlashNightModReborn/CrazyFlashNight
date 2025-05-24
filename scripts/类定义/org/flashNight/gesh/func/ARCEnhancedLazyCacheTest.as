/**
 * ARCEnhancedLazyCacheTest 类
 * 用于测试 ARCEnhancedLazyCache 的各项功能，包括基本操作、缓存淘汰策略、map 和 reset 方法、边界条件以及性能。
 */
import org.flashNight.gesh.func.ARCEnhancedLazyCache;

class org.flashNight.gesh.func.ARCEnhancedLazyCacheTest {
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
     * 测试 ARCEnhancedLazyCache 的基本功能
     * 包括缓存命中、未命中以及自动计算和缓存
     */
    public static function testBasicFunctionality():Void {
        trace("Running: testBasicFunctionality");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            trace("[Evaluator] Computing value for key: " + key);
            return "Value-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 初始时缓存未命中，调用 evaluator
        var valueA = cache.get("A");
        assertEquals(valueA, "Value-A", "Cache should compute and return Value-A for key 'A'");
        assertEquals(evaluatorCallCount, 1, "Evaluator should be called once for key 'A'");

        // 再次获取同一键，应该命中缓存，不调用 evaluator
        var valueA2 = cache.get("A");
        assertEquals(valueA2, "Value-A", "Cache should return cached Value-A for key 'A'");
        assertEquals(evaluatorCallCount, 1, "Evaluator should not be called again for key 'A'");

        // 获取新的键，触发 evaluator 调用
        var valueB = cache.get("B");
        assertEquals(valueB, "Value-B", "Cache should compute and return Value-B for key 'B'");
        assertEquals(evaluatorCallCount, 2, "Evaluator should be called once for key 'B'");

        // 获取第三个键
        var valueC = cache.get("C");
        assertEquals(valueC, "Value-C", "Cache should compute and return Value-C for key 'C'");
        assertEquals(evaluatorCallCount, 3, "Evaluator should be called once for key 'C'");

        // 缓存容量为3，以下调用将触发淘汰
        var valueD = cache.get("D");
        assertEquals(valueD, "Value-D", "Cache should compute and return Value-D for key 'D'");
        assertEquals(evaluatorCallCount, 4, "Evaluator should be called once for key 'D'");

        // 重新获取被淘汰的键 'A' 或 'B' 或 'C'，具体取决于 ARC 淘汰策略
        var valueA3 = cache.get("A");
        // 如果 'A' 未被淘汰，则直接返回缓存值，否则重新计算
        if (valueA3 === "Value-A") {
            assertEquals(evaluatorCallCount, 4, "Key 'A' should remain cached, evaluator not called again");
        } else {
            assertEquals(valueA3, "Value-A", "Cache should recompute and return Value-A for key 'A' after eviction");
            assertEquals(evaluatorCallCount, 5, "Evaluator should be called again for key 'A' after eviction");
        }
    }

    /**
     * 测试 ARCEnhancedLazyCache 的缓存淘汰策略
     * 确保 ARC 策略正确淘汰最不常用的键，并维护幽灵队列
     */
    public static function testEvictionStrategy():Void {
        trace("Running: testEvictionStrategy");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            trace("[Evaluator] Computing value for key: " + key);
            return "Value-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 插入三个键
        cache.get("A"); // evaluatorCallCount = 1
        cache.get("B"); // evaluatorCallCount = 2
        cache.get("C"); // evaluatorCallCount = 3

        // 访问键 'A' 以增加其优先级
        cache.get("A"); // 命中，evaluatorCallCount 不变

        // 插入第四个键，触发淘汰
        cache.get("D"); // evaluatorCallCount = 4

        // 根据 ARC 策略，键 'B' 或 'C' 应该被淘汰
        var valueB = cache.get("B");
        var valueC = cache.get("C");

        if (valueB === "Value-B") {
            // 'B' 未被淘汰
            assertEquals(evaluatorCallCount, 4, "Key 'B' should remain cached, evaluator not called again");
        } else {
            // 'B' 被淘汰，重新计算
            assertEquals(valueB, "Value-B", "Cache should recompute and return Value-B for key 'B' after eviction");
            assertEquals(evaluatorCallCount, 5, "Evaluator should be called again for key 'B' after eviction");
        }

        if (valueC === "Value-C") {
            // 'C' 未被淘汰
            assertEquals(evaluatorCallCount, 4, "Key 'C' should remain cached, evaluator not called again");
        } else {
            // 'C' 被淘汰，重新计算
            assertEquals(valueC, "Value-C", "Cache should recompute and return Value-C for key 'C' after eviction");
            assertEquals(evaluatorCallCount, 5, "Evaluator should be called again for key 'C' after eviction");
        }
    }

    /**
     * 测试 ARCEnhancedLazyCache 的 map 功能
     * 确保 map 生成的新缓存正确地应用转换逻辑，并独立管理其自身的缓存
     */
    public static function testMapFunction():Void {
        trace("Running: testMapFunction");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            trace("[Evaluator] Computing value for key: " + key);
            return key + "-base";
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 插入键 'A' 和 'B'
        var valueA = cache.get("A"); // evaluatorCallCount = 1
        var valueB = cache.get("B"); // evaluatorCallCount = 2

        // 创建一个 map 缓存，转换逻辑为大写
        var upperCache:ARCEnhancedLazyCache = cache.map(function(baseValue:Object):Object {
            trace("[Transformer] Transforming " + baseValue);
            return String(baseValue).toUpperCase();
        }, 3);

        // 获取键 'A'，应通过原缓存获取并转换
        var upperValueA = upperCache.get("A"); // 不会调用 evaluator，转换器被调用
        assertEquals(upperValueA, "A-BASE".toUpperCase(), "Mapped cache should return transformed value for key 'A'");
        assertEquals(evaluatorCallCount, 2, "Evaluator should not be called again for key 'A'");

        // 获取键 'C'，应调用原 evaluator 并转换
        var upperValueC = upperCache.get("C"); // evaluatorCallCount = 3
        assertEquals(upperValueC, "C-base".toUpperCase(), "Mapped cache should compute and return transformed value for key 'C'");
        assertEquals(evaluatorCallCount, 3, "Evaluator should be called once for key 'C'");

        // 验证原缓存未受影响
        var originalValueA = cache.get("A"); // 命中缓存
        assertEquals(originalValueA, "A-base", "Original cache should return untransformed value for key 'A'");
        assertEquals(evaluatorCallCount, 3, "Evaluator should not be called again for key 'A'");
    }

    /**
     * 测试 ARCEnhancedLazyCache 的 reset 功能
     * 确保 reset 可以替换 evaluator 并根据参数清空缓存
     */
    public static function testResetFunction():Void {
        trace("Running: testResetFunction");

        var initialEvaluatorCallCount:Number = 0;
        var newEvaluatorCallCount:Number = 0;

        var initialEvaluator:Function = function(key:Object):Object {
            initialEvaluatorCallCount++;
            trace("[Initial Evaluator] Computing value for key: " + key);
            return "Initial-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(initialEvaluator, 3);

        // 插入键 'A'
        var valueA = cache.get("A"); // initialEvaluatorCallCount = 1
        assertEquals(valueA, "Initial-A", "Cache should compute and return Initial-A for key 'A'");
        assertEquals(initialEvaluatorCallCount, 1, "Initial evaluator should be called once for key 'A'");

        // 重置 evaluator，清空缓存
        cache.reset(function(key:Object):Object {
            newEvaluatorCallCount++;
            trace("[New Evaluator] Computing value for key: " + key);
            return "New-" + key;
        }, true);

        // 验证缓存已清空，调用 'A' 重新计算
        var valueA2 = cache.get("A"); // newEvaluatorCallCount = 1
        assertEquals(valueA2, "New-A", "Cache should compute and return New-A for key 'A' after reset");
        assertEquals(newEvaluatorCallCount, 1, "New evaluator should be called once for key 'A' after reset");

        // 验证其他键未缓存，调用 'B' 触发新 evaluator
        var valueB = cache.get("B"); // newEvaluatorCallCount = 2
        assertEquals(valueB, "New-B", "Cache should compute and return New-B for key 'B' after reset");
        assertEquals(newEvaluatorCallCount, 2, "New evaluator should be called once for key 'B' after reset");

        // 重置 evaluator，不清空缓存
        cache.reset(function(key:Object):Object {
            newEvaluatorCallCount++;
            trace("[New Evaluator 2] Computing value for key: " + key);
            return "New2-" + key;
        }, false);

        // 获取已缓存的键 'A'，应直接返回缓存值，不调用新的 evaluator
        var valueA3 = cache.get("A"); // newEvaluatorCallCount 不变
        assertEquals(valueA3, "New-A", "Cache should return cached New-A for key 'A' without calling new evaluator");
        assertEquals(newEvaluatorCallCount, 2, "New evaluator should not be called again for key 'A' after reset without clearing cache");
    }

    /**
     * 测试 ARCEnhancedLazyCache 的边界条件
     * 包括插入 null 键、复杂对象键、多次重置等
     */
    public static function testEdgeCases():Void {
        trace("Running: testEdgeCases");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            trace("[Evaluator] Computing value for key: " + key);
            return key ? "Value-" + key.toString() : "Value-null";
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 插入 null 键
        var valueNull = cache.get(null);
        assertEquals(valueNull, "Value-null", "Cache should compute and return Value-null for null key");
        assertEquals(evaluatorCallCount, 1, "Evaluator should be called once for null key");

        // 再次获取 null 键，命中缓存
        var valueNull2 = cache.get(null);
        assertEquals(valueNull2, "Value-null", "Cache should return cached Value-null for null key");
        assertEquals(evaluatorCallCount, 1, "Evaluator should not be called again for null key");

        // 使用复杂对象作为键
        var objKey:Object = { id: 1 };
        var valueObj = cache.get(objKey);
        assertEquals(valueObj, "Value-[object Object]", "Cache should compute and return Value-[object Object] for object key");
        assertEquals(evaluatorCallCount, 2, "Evaluator should be called once for object key");

        // 再次获取同一对象键，命中缓存
        var valueObj2 = cache.get(objKey);
        assertEquals(valueObj2, "Value-[object Object]", "Cache should return cached Value-[object Object] for object key");
        assertEquals(evaluatorCallCount, 2, "Evaluator should not be called again for object key");

        // 多次重置
        cache.reset(function(key:Object):Object {
            evaluatorCallCount++;
            return "Reset1-" + key;
        }, true);

        var valueA = cache.get("A"); // evaluatorCallCount = 3
        assertEquals(valueA, "Reset1-A", "Cache should compute and return Reset1-A for key 'A' after first reset");
        assertEquals(evaluatorCallCount, 3, "Evaluator should be called once for key 'A' after first reset");

        cache.reset(function(key:Object):Object {
            evaluatorCallCount++;
            return "Reset2-" + key;
        }, true);

        var valueA2 = cache.get("A"); // evaluatorCallCount = 4
        assertEquals(valueA2, "Reset2-A", "Cache should compute and return Reset2-A for key 'A' after second reset");
        assertEquals(evaluatorCallCount, 4, "Evaluator should be called once for key 'A' after second reset");
    }

    /**
     * 性能测试：评估 ARCEnhancedLazyCache 的性能
     * 测试在高频调用下的表现，确保缓存命中时性能优越
     */
    public static function testPerformance():Void {
        trace("Running: testPerformance");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "Value-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 1000);

        // 预先填充缓存
        for (var i:Number = 0; i < 1000; i++) {
            cache.get(i);
        }
        assertEquals(evaluatorCallCount, 1000, "Evaluator should be called 1000 times to fill the cache");

        // 测试高频缓存命中
        var start:Number = getTimer();

        for (var j:Number = 0; j < 10000; j++) {
            var key:Number = j % 1000; // 确保命中缓存
            cache.get(key);
        }

        var duration:Number = getTimer() - start;
        trace("Performance Test: 10000 cache hits took " + duration + "ms");

        // 设定一个合理的性能阈值，例如 50ms
        var performanceThreshold:Number = 50;
        var pass:Boolean = duration < performanceThreshold;
        assertEquals(pass, true, "ARCEnhancedLazyCache should handle 10000 cache hits in under " + performanceThreshold + "ms");
    }

    /**
     * 运行所有测试
     */
    public static function runTests():Void {
        trace("Starting ARCEnhancedLazyCache Tests...");

        testBasicFunctionality();
        testEvictionStrategy();
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
