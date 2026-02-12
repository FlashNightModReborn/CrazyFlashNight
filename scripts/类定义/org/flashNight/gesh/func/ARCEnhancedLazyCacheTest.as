/**
 * ARCEnhancedLazyCacheTest v3.0
 *
 * 覆盖基础功能 + v2.0 修复 + v3.0 新特性的所有边界场景：
 *   - CRITICAL-1 : evaluator 返回 null/undefined 时不再无限递归
 *   - HIGH-2     : 完全未命中走 put() 触发淘汰，容量不会无界增长
 *   - 幽灵命中   : ghost hit 后 evaluator 计算、缓存、后续命中的完整链路
 *
 * v3.0 新增测试：
 *   - testEvaluatorExceptionOnMiss     : MISS 路径 evaluator 异常无副作用
 *   - testEvaluatorExceptionOnGhostHit : GHOST 路径 SAFE-1 僵尸清除
 *   - testHasViaLazyCache              : P4 has() API 在懒加载缓存上的行为
 *   - testRawKeyLazyCache              : ARCH-1 原始键语义验证
 */
import org.flashNight.gesh.func.ARCEnhancedLazyCache;

class org.flashNight.gesh.func.ARCEnhancedLazyCacheTest {
    private static var testResults:Array = [];

    // ==================== 断言工具 ====================

    private static function assertEquals(actual, expected, message:String):Void {
        if (actual === expected) {
            trace("[PASS] " + message);
            testResults.push({ result: "PASS", message: message });
        } else {
            trace("[FAIL] " + message + " - Expected: " + expected + ", Got: " + actual);
            testResults.push({ result: "FAIL", message: message });
        }
    }

    private static function assertTrue(condition:Boolean, message:String):Void {
        if (condition) {
            trace("[PASS] " + message);
            testResults.push({ result: "PASS", message: message });
        } else {
            trace("[FAIL] " + message);
            testResults.push({ result: "FAIL", message: message });
        }
    }

    // ==================== 基础测试（保留原版） ====================

    /**
     * 测试 ARCEnhancedLazyCache 的基本功能
     * 包括缓存命中、未命中以及自动计算和缓存
     */
    public static function testBasicFunctionality():Void {
        trace("Running: testBasicFunctionality");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
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

        // 重新获取可能被淘汰的键
        var valueA3 = cache.get("A");
        assertEquals(valueA3, "Value-A", "Cache should return Value-A (recomputed or cached)");
    }

    /**
     * 测试 ARCEnhancedLazyCache 的缓存淘汰策略
     */
    public static function testEvictionStrategy():Void {
        trace("Running: testEvictionStrategy");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "Value-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 插入三个键
        cache.get("A"); // evaluatorCallCount = 1
        cache.get("B"); // evaluatorCallCount = 2
        cache.get("C"); // evaluatorCallCount = 3

        // 访问键 'A' 以增加其优先级（T1 → T2）
        cache.get("A"); // 命中，evaluatorCallCount 不变

        // 插入第四个键，触发淘汰
        cache.get("D"); // evaluatorCallCount = 4

        // 'A' 应仍在缓存中（T2 热端），其他键状态取决于 ARC 策略
        var valueA = cache.get("A");
        assertEquals(valueA, "Value-A", "Hot key 'A' should still be cached");
        assertEquals(evaluatorCallCount, 4, "Evaluator should not be called again for hot key 'A'");

        // 'B' 或 'C' 可能被淘汰 — 无论如何，懒加载层应正确重计算
        var valueB = cache.get("B");
        assertEquals(valueB, "Value-B", "Key 'B' should return correct value (cached or recomputed)");
        var valueC = cache.get("C");
        assertEquals(valueC, "Value-C", "Key 'C' should return correct value (cached or recomputed)");
    }

    /**
     * 测试 map 功能
     */
    public static function testMapFunction():Void {
        trace("Running: testMapFunction");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return key + "-base";
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        cache.get("A"); // evaluatorCallCount = 1
        cache.get("B"); // evaluatorCallCount = 2

        // 创建 map 缓存
        var upperCache:ARCEnhancedLazyCache = cache.map(function(baseValue:Object):Object {
            return String(baseValue).toUpperCase();
        }, 3);

        // 'A' 在原缓存中命中，转换器应用
        var upperValueA = upperCache.get("A");
        assertEquals(upperValueA, "A-BASE", "Mapped cache should return transformed value for key 'A'");
        assertEquals(evaluatorCallCount, 2, "Evaluator should not be called again for cached key 'A'");

        // 'C' 不在原缓存中，evaluator 被调用
        var upperValueC = upperCache.get("C");
        assertEquals(upperValueC, "C-BASE", "Mapped cache should compute and transform value for key 'C'");
        assertEquals(evaluatorCallCount, 3, "Evaluator should be called once for key 'C'");

        // 原缓存不受影响
        var originalValueA = cache.get("A");
        assertEquals(originalValueA, "A-base", "Original cache should return untransformed value");
        assertEquals(evaluatorCallCount, 3, "Evaluator should not be called again");
    }

    /**
     * 测试 reset 功能
     */
    public static function testResetFunction():Void {
        trace("Running: testResetFunction");

        var initialEvaluatorCallCount:Number = 0;
        var newEvaluatorCallCount:Number = 0;

        var initialEvaluator:Function = function(key:Object):Object {
            initialEvaluatorCallCount++;
            return "Initial-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(initialEvaluator, 3);

        var valueA = cache.get("A");
        assertEquals(valueA, "Initial-A", "Cache should return Initial-A for key 'A'");
        assertEquals(initialEvaluatorCallCount, 1, "Initial evaluator called once");

        // 重置 evaluator，清空缓存
        cache.reset(function(key:Object):Object {
            newEvaluatorCallCount++;
            return "New-" + key;
        }, true);

        var valueA2 = cache.get("A");
        assertEquals(valueA2, "New-A", "After reset, cache should return New-A");
        assertEquals(newEvaluatorCallCount, 1, "New evaluator called once after reset");

        var valueB = cache.get("B");
        assertEquals(valueB, "New-B", "New evaluator should compute New-B");
        assertEquals(newEvaluatorCallCount, 2, "New evaluator called for key 'B'");

        // 重置 evaluator，保留缓存
        cache.reset(function(key:Object):Object {
            newEvaluatorCallCount++;
            return "New2-" + key;
        }, false);

        // 'A' 仍在缓存中，不调用新 evaluator
        var valueA3 = cache.get("A");
        assertEquals(valueA3, "New-A", "After reset without clear, cached 'A' should still return New-A");
        assertEquals(newEvaluatorCallCount, 2, "Evaluator not called again for cached 'A'");
    }

    /**
     * 测试边界条件
     */
    public static function testEdgeCases():Void {
        trace("Running: testEdgeCases");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return key ? "Value-" + key.toString() : "Value-null";
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // null 键
        var valueNull = cache.get(null);
        assertEquals(valueNull, "Value-null", "Cache should return Value-null for null key");
        assertEquals(evaluatorCallCount, 1, "Evaluator called once for null key");

        // null 键命中
        var valueNull2 = cache.get(null);
        assertEquals(valueNull2, "Value-null", "Cache should hit for null key");
        assertEquals(evaluatorCallCount, 1, "Evaluator not called again for null key");

        // 复杂对象键
        var objKey:Object = { id: 1 };
        var valueObj = cache.get(objKey);
        assertEquals(evaluatorCallCount, 2, "Evaluator called for object key");

        var valueObj2 = cache.get(objKey);
        assertEquals(evaluatorCallCount, 2, "Evaluator not called again for same object key");

        // 多次重置
        cache.reset(function(key:Object):Object {
            evaluatorCallCount++;
            return "Reset1-" + key;
        }, true);

        var valueA = cache.get("A");
        assertEquals(valueA, "Reset1-A", "After first reset, returns Reset1-A");
        assertEquals(evaluatorCallCount, 3, "Evaluator called once after first reset");

        cache.reset(function(key:Object):Object {
            evaluatorCallCount++;
            return "Reset2-" + key;
        }, true);

        var valueA2 = cache.get("A");
        assertEquals(valueA2, "Reset2-A", "After second reset, returns Reset2-A");
        assertEquals(evaluatorCallCount, 4, "Evaluator called once after second reset");
    }

    // ==================== v2.0 新增测试 ====================

    /**
     * CRITICAL-1 覆盖：evaluator 返回 null
     *
     * 旧版使用 cachedValue == null 判断未命中，
     * 如果 evaluator 返回 null → 每次 get 都重新计算 → 无限递归或永远 miss。
     * 新版使用 _hitType，null 值被正确缓存。
     */
    public static function testNullValueEvaluator():Void {
        trace("Running: testNullValueEvaluator");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return null; // 合法返回 null
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 第一次 get：miss → evaluator 返回 null → 缓存 null
        var v1 = cache.get("A");
        assertEquals(v1, null, "Evaluator returned null, get should return null");
        assertEquals(evaluatorCallCount, 1, "Evaluator should be called once for 'A'");

        // 第二次 get：应命中缓存（值是 null），evaluator 不被再次调用
        var v2 = cache.get("A");
        assertEquals(v2, null, "Cached null should be returned on hit");
        assertEquals(evaluatorCallCount, 1,
            "[CRITICAL-1] Evaluator must NOT be called again for cached null value");

        // 多个 null 值 key
        cache.get("B"); // evaluatorCallCount = 2
        cache.get("C"); // evaluatorCallCount = 3

        cache.get("B"); // 命中
        cache.get("C"); // 命中
        assertEquals(evaluatorCallCount, 3,
            "All three null-value keys should be cached, no extra evaluator calls");
    }

    /**
     * CRITICAL-1 覆盖 (变体)：evaluator 返回 undefined
     *
     * AS2 中 undefined == null 为 true，旧版同样会误判。
     * 新版应正确缓存 undefined 值。
     */
    public static function testUndefinedValueEvaluator():Void {
        trace("Running: testUndefinedValueEvaluator");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return undefined; // 合法返回 undefined
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        var v1 = cache.get("X");
        // AS2: undefined === undefined → true; 但 v1 的类型应为 undefined
        assertEquals(evaluatorCallCount, 1, "Evaluator called once for 'X'");

        var v2 = cache.get("X");
        assertEquals(evaluatorCallCount, 1,
            "[CRITICAL-1] Evaluator must NOT be called again for cached undefined value");
    }

    /**
     * HIGH-2 覆盖：懒加载缓存的容量不变式
     *
     * 旧版对完全未命中统一使用 putNoEvict → 缓存无界增长。
     * 新版对 MISS 使用 put()（触发淘汰），GHOST 使用 putNoEvict()。
     *
     * 验证：连续访问 3x 容量的唯一 key 后，|T1|+|T2| 仍 ≤ capacity。
     */
    public static function testCapacityInvariantLazyCache():Void {
        trace("Running: testCapacityInvariantLazyCache");

        var evaluator:Function = function(key:Object):Object {
            return "val-" + key;
        };

        var cap:Number = 50;
        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, cap);

        // 连续访问 3x capacity 的唯一 key
        for (var i:Number = 0; i < cap * 3; i++) {
            cache.get("ukey" + i);
        }

        // 通过继承的 getT1/getT2 检查不变式
        var t1s:Number = cache.getT1().length;
        var t2s:Number = cache.getT2().length;
        var b1s:Number = cache.getB1().length;
        var b2s:Number = cache.getB2().length;
        var cacheSize:Number = t1s + t2s;
        var totalSize:Number = t1s + t2s + b1s + b2s;

        trace("  LazyCache: T1=" + t1s + " T2=" + t2s + " B1=" + b1s + " B2=" + b2s);

        assertTrue(cacheSize <= cap,
            "[HIGH-2] |T1|+|T2|=" + cacheSize + " should be <= capacity " + cap);
        assertTrue(totalSize <= 2 * cap,
            "[HIGH-2] total=" + totalSize + " should be <= 2*capacity " + (2 * cap));
    }

    /**
     * Ghost hit 回填正确性：
     *   1. key 首次访问 → evaluator → 缓存
     *   2. key 被淘汰 → 进入 B1/B2
     *   3. key 再次访问 → ghost hit → evaluator → 缓存
     *   4. key 第三次访问 → 命中缓存（evaluator 不调用）
     */
    public static function testGhostHitRoundTrip():Void {
        trace("Running: testGhostHitRoundTrip");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "v" + evaluatorCallCount + "-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // Phase 1: 填满缓存
        cache.get("A"); // evaluatorCallCount = 1, returns "v1-A"
        cache.get("B"); // evaluatorCallCount = 2
        cache.get("C"); // evaluatorCallCount = 3

        // Phase 2: 插入新 key 触发淘汰 A
        cache.get("D"); // evaluatorCallCount = 4, A 被淘汰到 B1

        // Phase 3: 再次访问 A → ghost hit → evaluator 被调用
        var valA_recomputed = cache.get("A"); // evaluatorCallCount = 5
        assertEquals(evaluatorCallCount, 5, "Evaluator should be called for ghost-hit key 'A'");
        assertEquals(valA_recomputed, "v5-A", "Recomputed value should be 'v5-A'");

        // Phase 4: 再次访问 A → 应命中缓存
        var valA_cached = cache.get("A");
        assertEquals(evaluatorCallCount, 5,
            "After ghost-hit refill, 'A' should be cached — evaluator not called again");
        assertEquals(valA_cached, "v5-A", "Cached value should still be 'v5-A'");
    }

    /**
     * 混合场景：put() + get() 交互
     * 确保手动 put 的值不会被 evaluator 覆盖。
     *
     * 注意：ARCEnhancedLazyCache 继承了 put()，
     * 手动 put 后 get 应命中缓存，不调用 evaluator。
     */
    public static function testPutGetInteraction():Void {
        trace("Running: testPutGetInteraction");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "computed-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 手动 put
        cache.put("X", "manual-X");

        // get 应命中手动 put 的值
        var val = cache.get("X");
        assertEquals(val, "manual-X", "Manual put value should be returned, not evaluator result");
        assertEquals(evaluatorCallCount, 0, "Evaluator should NOT be called for manually put key");

        // 覆盖测试：evaluator 填充后手动 put 覆盖
        cache.get("Y"); // evaluatorCallCount = 1, returns "computed-Y"
        cache.put("Y", "override-Y");
        var val2 = cache.get("Y");
        assertEquals(val2, "override-Y", "Manual put should override evaluator value");
        assertEquals(evaluatorCallCount, 1, "Evaluator should not be called again after manual put");
    }

    // ==================== v3.0 新增测试 ====================

    /**
     * SAFE-1 覆盖：MISS 路径 evaluator 异常无副作用
     *
     * 当 evaluator 在 MISS 路径抛出异常时：
     *   - super.put() 尚未调用，缓存状态不变
     *   - 异常正常传播到调用者
     *   - 后续正常 get 不受影响
     */
    public static function testEvaluatorExceptionOnMiss():Void {
        trace("Running: testEvaluatorExceptionOnMiss");

        var evaluatorCallCount:Number = 0;
        var shouldThrow:Boolean = false;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            if (shouldThrow) {
                throw new Error("Evaluator MISS error for key: " + key);
            }
            return "val-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 正常填充一个 key
        cache.get("A");
        assertEquals(evaluatorCallCount, 1, "Evaluator called once for 'A'");

        // 开启异常模式
        shouldThrow = true;
        var caught:Boolean = false;
        try {
            cache.get("B"); // MISS → evaluator throws
        } catch (e) {
            caught = true;
        }
        assertTrue(caught, "[SAFE-1/MISS] Exception should propagate to caller");
        assertEquals(evaluatorCallCount, 2, "Evaluator was called for 'B' before throwing");

        // 验证缓存状态未被污染
        // 'B' 不应在缓存中（put 未执行）
        assertEquals(cache.has("B"), false,
            "[SAFE-1/MISS] Failed key 'B' should NOT be in cache");

        // 'A' 应仍然正常
        shouldThrow = false;
        var valA = cache.get("A");
        assertEquals(valA, "val-A", "[SAFE-1/MISS] Pre-existing key 'A' should be unaffected");

        // 重试 'B' 应该成功
        var valB = cache.get("B");
        assertEquals(valB, "val-B", "[SAFE-1/MISS] Retry key 'B' should succeed after error cleared");
        assertEquals(evaluatorCallCount, 3,
            "Evaluator count: A(1) + B_throw(2) + A_hit(skip) + B_retry(3) = 3");
    }

    /**
     * SAFE-1 覆盖：GHOST 路径 evaluator 异常后僵尸清除
     *
     * 当 evaluator 在 ghost hit 路径抛出异常时：
     *   - super.get() 已将节点移入 T2（value = undefined）
     *   - catch 中调用 super.remove(key) 清除僵尸节点
     *   - 异常重抛给调用者
     *   - 后续 get 同一 key 应为完全 MISS，不返回 undefined
     */
    public static function testEvaluatorExceptionOnGhostHit():Void {
        trace("Running: testEvaluatorExceptionOnGhostHit");

        var evaluatorCallCount:Number = 0;
        var shouldThrow:Boolean = false;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            if (shouldThrow) {
                throw new Error("Evaluator GHOST error for key: " + key);
            }
            return "val-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // Phase 1: 填满缓存 + 构造 ghost
        cache.get("A"); // evaluatorCallCount = 1, T1=[A]
        cache.get("B"); // evaluatorCallCount = 2, T1=[B,A]
        cache.get("C"); // evaluatorCallCount = 3, T1=[C,B,A]

        // 插入 D 触发 A 淘汰到 B1
        cache.get("D"); // evaluatorCallCount = 4, T1=[D,C,B?], A→B1

        // Phase 2: A 在 ghost 中，设置 evaluator 抛异常
        shouldThrow = true;
        var caught:Boolean = false;
        try {
            cache.get("A"); // ghost hit → evaluator throws → remove zombie
        } catch (e) {
            caught = true;
        }
        assertTrue(caught, "[SAFE-1/GHOST] Exception should propagate to caller");
        assertEquals(evaluatorCallCount, 5, "Evaluator was called for ghost 'A' before throwing");

        // Phase 3: 验证僵尸已被清除
        // A 不应在缓存或 ghost 中（remove 已清除）
        assertEquals(cache.has("A"), false,
            "[SAFE-1/GHOST] Zombie key 'A' should NOT be in cache (has=false)");

        // 重新 get A 应是完全 MISS，不是返回 undefined
        shouldThrow = false;
        var valA = cache.get("A");
        assertEquals(valA, "val-A",
            "[SAFE-1/GHOST] Retry ghost-failed key 'A' should recompute correctly");
        assertEquals(evaluatorCallCount, 6,
            "Evaluator called again for 'A' (complete miss after zombie cleanup)");

        // Phase 4: 正常命中
        var valA2 = cache.get("A");
        assertEquals(valA2, "val-A", "Recomputed 'A' should now be cached");
        assertEquals(evaluatorCallCount, 6, "No extra evaluator call for cached 'A'");
    }

    /**
     * P4 API-1：has() 方法在懒加载缓存上的行为
     *
     * has() 检查 key 是否在 T1/T2 中，不触发 evaluator。
     */
    public static function testHasViaLazyCache():Void {
        trace("Running: testHasViaLazyCache");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "val-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 空缓存
        assertEquals(cache.has("A"), false, "has() on empty cache should be false");
        assertEquals(evaluatorCallCount, 0, "has() should NOT trigger evaluator");

        // get 填充后
        cache.get("A"); // evaluatorCallCount = 1
        assertEquals(cache.has("A"), true, "has() after get should be true");
        assertEquals(evaluatorCallCount, 1, "has() should NOT call evaluator again");

        // has() 对不存在的 key 不触发计算
        assertEquals(cache.has("B"), false, "has() for uncached key should be false");
        assertEquals(evaluatorCallCount, 1, "has() must NOT trigger evaluator for uncached key");

        // 手动 put 后
        cache.put("X", "manual-X");
        assertEquals(cache.has("X"), true, "has() after manual put should be true");

        // remove 后
        cache.remove("X");
        assertEquals(cache.has("X"), false, "has() after remove should be false");
    }

    /**
     * ARCH-1：原始键语义验证（通过懒加载缓存）
     *
     * 验证 Number 键在懒加载缓存中的行为符合预期。
     */
    public static function testRawKeyLazyCache():Void {
        trace("Running: testRawKeyLazyCache");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "computed-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 10);

        // Number 键
        var val1 = cache.get(42);
        assertEquals(val1, "computed-42", "Number key 42 should work via lazy cache");
        assertEquals(evaluatorCallCount, 1, "Evaluator called once for Number 42");

        // 命中
        var val2 = cache.get(42);
        assertEquals(val2, "computed-42", "Number key 42 should hit cache");
        assertEquals(evaluatorCallCount, 1, "Evaluator not called again for cached Number 42");

        // 已知限制：Number 与 String 碰撞
        // get(42) 已缓存 "computed-42"，get("42") 应命中同一个条目
        var val3 = cache.get("42");
        assertEquals(val3, "computed-42",
            "[Known] String '42' should hit same entry as Number 42");
        assertEquals(evaluatorCallCount, 1,
            "Evaluator not called for '42' (collision with 42)");
    }

    /**
     * 性能测试 v3.0
     * 调整阈值：AS2 VM 下 10000 次命中在 200ms 内为合理预期。
     */
    public static function testPerformance():Void {
        trace("Running: testPerformance");

        var evaluatorCallCount:Number = 0;

        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "Value-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 1000);

        // 预填充
        for (var i:Number = 0; i < 1000; i++) {
            cache.get(i);
        }
        assertEquals(evaluatorCallCount, 1000, "Evaluator should be called 1000 times to fill cache");

        // 高频命中测试
        var start:Number = getTimer();

        for (var j:Number = 0; j < 10000; j++) {
            cache.get(j % 1000);
        }

        var duration:Number = getTimer() - start;
        trace("Performance: 10000 cache hits took " + duration + "ms");

        // v3.0 阈值：AS2 VM 下 200ms 为合理上限（sentinel + pool 优化后应明显低于此值）
        var performanceThreshold:Number = 200;
        assertTrue(duration < performanceThreshold,
            "10000 cache hits should complete in under " + performanceThreshold + "ms (actual: " + duration + "ms)");
    }

    // ==================== 入口 ====================

    public static function runTests():Void {
        trace("=== ARCEnhancedLazyCacheTest v3.0: Starting Tests ===");
        testResults = [];

        // 基础测试
        testBasicFunctionality();
        testEvictionStrategy();
        testMapFunction();
        testResetFunction();
        testEdgeCases();

        // v2.0 新增测试
        testNullValueEvaluator();
        testUndefinedValueEvaluator();
        testCapacityInvariantLazyCache();
        testGhostHitRoundTrip();
        testPutGetInteraction();

        // v3.0 新增测试
        testEvaluatorExceptionOnMiss();
        testEvaluatorExceptionOnGhostHit();
        testHasViaLazyCache();
        testRawKeyLazyCache();

        // 性能测试
        testPerformance();

        // 汇总
        var passCount:Number = 0;
        var failCount:Number = 0;
        for (var i:Number = 0; i < testResults.length; i++) {
            if (testResults[i].result == "PASS") {
                passCount++;
            } else {
                failCount++;
            }
        }
        trace("=== ARCEnhancedLazyCacheTest v3.0: " + testResults.length + " assertions, "
              + passCount + " passed, " + failCount + " failed ===");
    }
}
