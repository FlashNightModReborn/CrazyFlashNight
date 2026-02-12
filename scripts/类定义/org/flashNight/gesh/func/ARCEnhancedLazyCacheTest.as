/**
 * ARCEnhancedLazyCacheTest v3.2
 *
 * 覆盖基础功能 + v2.0 修复 + v3.0/v3.1/v3.2 特性的所有边界场景：
 *   - CRITICAL-1 : evaluator 返回 null/undefined 时不再无限递归
 *   - HIGH-2     : 完全未命中走 _putNew() 触发淘汰，容量不会无界增长
 *   - 幽灵命中   : ghost hit 后 evaluator 计算、缓存、后续命中的完整链路
 *
 * v3.0 新增测试：
 *   - testEvaluatorExceptionOnMiss     : MISS 路径 evaluator 异常无副作用
 *   - testHasViaLazyCache              : P4 has() API 在懒加载缓存上的行为
 *   - testRawKeyLazyCache              : ARCH-1 原始键语义验证
 *
 * v3.1 新增/重写测试：
 *   - testEvaluatorExceptionOnGhostHit : C8 契约验证（僵尸行为 + remove 恢复）
 *   - testCapacity1LazyCache           : capacity=1 极端交互（ghost/pool 密集路径）
 *
 * v3.2 新增测试：
 *   - testRemoveAndGet                 : remove() 后 get() 触发 evaluator 重计算
 *   - testPutGhostPath                 : put() 对 B1 ghost key 的完整路径验证
 *   - testResetNullEvaluator           : reset(null, true) 保持原 evaluator
 *   - testCapacity2Boundary            : capacity=2 边界 + p 自适应极端行为
 *   - testMapParentReset               : map() 父缓存 reset 后子缓存 stale 行为
 *   - testClearPoolDrain               : OPT-A _clear() 池回收 + 多轮 reset 稳定性
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
     * v3.1+：MISS 走 _putNew()（触发淘汰），GHOST 走 OPT-5 直赋（_lastNode.value）。
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
        cache.get("A"); // evaluatorCallCount = 1, T1=[A]
        cache.get("B"); // evaluatorCallCount = 2, T1=[B,A]
        cache.get("C"); // evaluatorCallCount = 3, T1=[C,B,A]

        // Phase 2: 提升 C 到 T2，确保后续插入走 REPLACE 而非直接删除
        // 不提升的话 |T1|==c → Case A else → 直接删除 T1 tail（不进 ghost）
        cache.get("C"); // HIT: C T1→T2. T1=[B,A], T2=[C]. count 不变

        // Phase 3: 插入 D → Case B, REPLACE 淘汰 T1 tail (A)→B1
        cache.get("D"); // evaluatorCallCount = 4. T1=[D,B], T2=[C], B1=[A]

        // Phase 4: 访问 A → B1 ghost hit → evaluator 被调用
        var valA_recomputed = cache.get("A"); // evaluatorCallCount = 5
        assertEquals(cache._hitType, 2,
            "get('A') should be B1 ghost hit (_hitType=2)");
        assertEquals(evaluatorCallCount, 5, "Evaluator should be called for ghost-hit key 'A'");
        assertEquals(valA_recomputed, "v5-A", "Recomputed value should be 'v5-A'");

        // Phase 5: 再次访问 A → 应命中缓存
        var valA_cached = cache.get("A");
        assertEquals(cache._hitType, 1,
            "Second get('A') should be HIT (_hitType=1)");
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
     * C8 契约验证：GHOST 路径 evaluator 异常后的僵尸行为
     *
     * v3.1 契约优先：不使用 try/catch 保护 ghost 路径。
     * 当 evaluator 违反 C8 契约在 ghost hit 路径抛出异常时：
     *   - super.get() 已将节点移入 T2（value = undefined）
     *   - evaluator 异常传播，node.value = computed 未执行
     *   - T2 中留下僵尸节点（value=undefined 的 HIT）
     *   - 后续 get 同一 key 返回 undefined（僵尸 HIT），而非重新计算
     *   - 恢复方式：手动 remove(key) 后重试
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

        // Phase 1: 填满缓存
        cache.get("A"); // evaluatorCallCount = 1, T1=[A]
        cache.get("B"); // evaluatorCallCount = 2, T1=[B,A]
        cache.get("C"); // evaluatorCallCount = 3, T1=[C,B,A]

        // Phase 1.5: 提升 C 到 T2，构造 ghost
        cache.get("C"); // HIT: C T1→T2. T1=[B,A], T2=[C]. evaluatorCallCount 不变

        // 插入 D → Case B, REPLACE 淘汰 T1 tail (A)→B1
        cache.get("D"); // evaluatorCallCount = 4. T1=[D,B], T2=[C], B1=[A]

        // Phase 2: A 在 B1 ghost 中，evaluator 抛异常（违反 C8）
        shouldThrow = true;
        var caught:Boolean = false;
        try {
            cache.get("A"); // B1 ghost hit → evaluator throws → zombie in T2
        } catch (e) {
            caught = true;
        }
        assertTrue(caught, "[C8] Exception should propagate to caller");
        assertEquals(cache._hitType, 2,
            "[C8] get('A') should be B1 ghost hit (_hitType=2) before evaluator threw");
        assertEquals(evaluatorCallCount, 5, "Evaluator was called for ghost 'A' before throwing");

        // Phase 3: 验证僵尸行为（v3.1 契约优先 — 无自动清除）
        // A 现在在 T2 中，value=undefined（僵尸）
        assertEquals(cache.has("A"), true,
            "[C8/ZOMBIE] Zombie key 'A' should be in cache (has=true, in T2 with undefined value)");

        // 后续 get("A") 命中僵尸：返回 undefined 而非重新计算
        shouldThrow = false;
        var valZombie = cache.get("A");
        assertEquals(cache._hitType, 1,
            "[C8/ZOMBIE] Zombie 'A' should be T2 HIT (_hitType=1)");
        assertEquals(valZombie, undefined,
            "[C8/ZOMBIE] Zombie 'A' should return undefined (not recompute)");
        assertEquals(evaluatorCallCount, 5,
            "[C8/ZOMBIE] No evaluator call for zombie HIT");

        // Phase 4: 恢复 — remove + retry
        cache.remove("A");
        assertEquals(cache.has("A"), false,
            "[C8/RECOVER] After remove, 'A' should not be in cache");

        var valRecovered = cache.get("A");
        assertEquals(valRecovered, "val-A",
            "[C8/RECOVER] After remove+retry, 'A' should be recomputed correctly");
        assertEquals(evaluatorCallCount, 6,
            "[C8/RECOVER] Evaluator called again for 'A' after zombie removal");

        // Phase 5: 正常命中
        var valCached = cache.get("A");
        assertEquals(valCached, "val-A", "Recovered 'A' should now be cached");
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

    /**
     * P2 capacity=1 边界：LazyCache 层面的极端交互
     * capacity=1 时每次 MISS 必淘汰，pool 和 ghost 交互最密集。
     */
    public static function testCapacity1LazyCache():Void {
        trace("Running: testCapacity1LazyCache");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "val-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 1);

        // MISS: A → T1=[A]
        var valA = cache.get("A");
        assertEquals(valA, "val-A", "c=1: A should be computed");
        assertEquals(evaluatorCallCount, 1, "c=1: evaluator called once for A");

        // HIT: A → promote T1→T2. T1=[], T2=[A]
        var valA2 = cache.get("A");
        assertEquals(valA2, "val-A", "c=1: A should be HIT");
        assertEquals(cache._hitType, 1, "c=1: A should be HIT (_hitType=1)");
        assertEquals(evaluatorCallCount, 1, "c=1: no extra evaluator call for HIT");

        // MISS: B → _putNew triggers REPLACE, A evicted from T2 → B2
        // T1=[B], T2=[], B2=[A]
        var valB = cache.get("B");
        assertEquals(valB, "val-B", "c=1: B should be computed");
        assertEquals(evaluatorCallCount, 2, "c=1: evaluator called for B");

        // HIT: B → promote T1→T2. T1=[], T2=[B]
        cache.get("B");

        // GHOST: A → B2 ghost hit → evaluator re-called
        var valA3 = cache.get("A");
        assertEquals(cache._hitType, 3, "c=1: A should be B2 ghost hit (_hitType=3)");
        assertEquals(valA3, "val-A", "c=1: A should be recomputed via ghost hit");
        assertEquals(evaluatorCallCount, 3, "c=1: evaluator called again for ghost A");

        // HIT: A (now in T2)
        var valA4 = cache.get("A");
        assertEquals(cache._hitType, 1, "c=1: A should be HIT after ghost refill");
        assertEquals(evaluatorCallCount, 3, "c=1: no extra evaluator for cached A");

        // 容量不变式
        var t1s:Number = cache.getT1().length;
        var t2s:Number = cache.getT2().length;
        assertTrue(t1s + t2s <= 1,
            "c=1: |T1|+|T2|=" + (t1s + t2s) + " should be <= 1");
    }

    // ==================== v3.2 新增测试 ====================

    /**
     * P3: remove() 后 get() 应触发 evaluator 重新计算
     */
    public static function testRemoveAndGet():Void {
        trace("Running: testRemoveAndGet");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "val-" + evaluatorCallCount + "-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 5);

        // 填充
        var v1 = cache.get("A"); // evaluatorCallCount = 1
        assertEquals(v1, "val-1-A", "remove+get: Initial get returns computed value");
        assertEquals(evaluatorCallCount, 1, "remove+get: Evaluator called once");

        // 命中
        var v2 = cache.get("A");
        assertEquals(v2, "val-1-A", "remove+get: Cached value returned");
        assertEquals(evaluatorCallCount, 1, "remove+get: No extra call on HIT");

        // 移除
        cache.remove("A");
        assertEquals(cache.has("A"), false, "remove+get: After remove, has() returns false");

        // 重新获取 — 应触发 evaluator
        var v3 = cache.get("A"); // evaluatorCallCount = 2
        assertEquals(v3, "val-2-A", "remove+get: After remove, evaluator re-called");
        assertEquals(evaluatorCallCount, 2, "remove+get: Evaluator called again after remove");

        // 再次命中
        var v4 = cache.get("A");
        assertEquals(v4, "val-2-A", "remove+get: Re-cached value returned");
        assertEquals(evaluatorCallCount, 2, "remove+get: No extra call after re-cache");
    }

    /**
     * P3: put() 对 ghost 队列中 key 的处理路径
     * 验证手动 put() 命中 B1/B2 ghost 时正确执行 p 自适应 + REPLACE + 赋值
     */
    public static function testPutGhostPath():Void {
        trace("Running: testPutGhostPath");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "computed-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // Phase 1: 填满并构造 B1 ghost
        cache.get("A"); // T1=[A]
        cache.get("B"); // T1=[B,A]
        cache.get("C"); // T1=[C,B,A]
        cache.get("C"); // HIT: C T1→T2. T1=[B,A], T2=[C]
        cache.get("D"); // MISS: REPLACE A→B1. T1=[D,B], T2=[C], B1=[A]
        assertEquals(evaluatorCallCount, 4, "putGhost: 4 evaluator calls after setup");

        // Phase 2: 手动 put 到 B1 ghost key
        cache.put("A", "manual-A");

        // Phase 3: 验证 put 后的状态
        assertEquals(cache.has("A"), true, "putGhost: A should be in cache after put on ghost");

        var valA = cache.get("A");
        assertEquals(cache._hitType, 1, "putGhost: A should be HIT after ghost put");
        assertEquals(valA, "manual-A", "putGhost: A should have manual value, not computed");
        assertEquals(evaluatorCallCount, 4, "putGhost: Evaluator not called for manual put on ghost");

        // Phase 4: 容量不变式
        var t1s:Number = cache.getT1().length;
        var t2s:Number = cache.getT2().length;
        assertTrue(t1s + t2s <= 3,
            "putGhost: |T1|+|T2|=" + (t1s + t2s) + " should be <= 3");
    }

    /**
     * P3: reset(null, true) — null evaluator 保持原 evaluator 不变 + 清空缓存
     */
    public static function testResetNullEvaluator():Void {
        trace("Running: testResetNullEvaluator");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "val-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 3);

        // 填充
        cache.get("A"); // evaluatorCallCount = 1
        assertEquals(evaluatorCallCount, 1, "resetNull: Evaluator called once for A");

        // reset(null, true): 传 null evaluator 应保持原 evaluator，清空缓存
        cache.reset(null, true);

        // A 已被清空，应重新计算
        var v2 = cache.get("A"); // evaluatorCallCount = 2
        assertEquals(v2, "val-A", "resetNull: Original evaluator still works after reset(null, true)");
        assertEquals(evaluatorCallCount, 2, "resetNull: Evaluator called again after cache clear");
    }

    /**
     * P3: capacity=2 边界 — T1/T2 各最多 1-2 个条目，p 自适应行为极端
     */
    public static function testCapacity2Boundary():Void {
        trace("Running: testCapacity2Boundary");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "val-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 2);

        // A, B 填满
        cache.get("A"); // T1=[A]
        cache.get("B"); // T1=[B,A]
        assertEquals(evaluatorCallCount, 2, "c=2: Two evaluator calls");

        // 提升 A 到 T2
        cache.get("A"); // HIT: A T1→T2. T1=[B], T2=[A]

        // C 触发淘汰
        cache.get("C"); // MISS: REPLACE B→B1. T1=[C], T2=[A], B1=[B]
        assertEquals(evaluatorCallCount, 3, "c=2: Three evaluator calls");

        // A 仍在 T2
        var valA = cache.get("A");
        assertEquals(cache._hitType, 1, "c=2: A should be T2 HIT");
        assertEquals(evaluatorCallCount, 3, "c=2: No extra call for cached A");

        // B ghost hit
        var valB = cache.get("B");
        assertEquals(cache._hitType, 2, "c=2: B should be B1 ghost hit");
        assertEquals(evaluatorCallCount, 4, "c=2: Evaluator called for ghost B");

        // 容量不变式
        var t1s:Number = cache.getT1().length;
        var t2s:Number = cache.getT2().length;
        assertTrue(t1s + t2s <= 2,
            "c=2: |T1|+|T2|=" + (t1s + t2s) + " should be <= 2");
        var totalSize:Number = t1s + t2s + cache.getB1().length + cache.getB2().length;
        assertTrue(totalSize <= 4,
            "c=2: total=" + totalSize + " should be <= 2*2=4");
    }

    /**
     * P3: map() 父缓存 reset 后子缓存的 stale 行为
     * reset 父缓存后，子缓存的已缓存值不会自动失效
     */
    public static function testMapParentReset():Void {
        trace("Running: testMapParentReset");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return key + "-base-v" + evaluatorCallCount;
        };

        var parentCache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 5);
        var childCache:ARCEnhancedLazyCache = parentCache.map(function(baseValue:Object):Object {
            return String(baseValue).toUpperCase();
        }, 5);

        // 通过子缓存触发计算链
        var v1 = childCache.get("A"); // parent evaluator(A)="A-base-v1", child="A-BASE-V1"
        assertEquals(v1, "A-BASE-V1", "mapReset: Child returns transformed value");
        assertEquals(evaluatorCallCount, 1, "mapReset: Evaluator called once");

        // 子缓存命中
        var v2 = childCache.get("A");
        assertEquals(v2, "A-BASE-V1", "mapReset: Child cache HIT");
        assertEquals(evaluatorCallCount, 1, "mapReset: No extra evaluator call");

        // Reset 父缓存（换新 evaluator + 清空）
        parentCache.reset(function(key:Object):Object {
            evaluatorCallCount++;
            return key + "-newbase-v" + evaluatorCallCount;
        }, true);

        // 子缓存仍有旧值（stale）
        var v3 = childCache.get("A");
        assertEquals(v3, "A-BASE-V1",
            "mapReset: Child still returns stale cached value after parent reset");
        assertEquals(evaluatorCallCount, 1, "mapReset: No evaluator call for stale child HIT");

        // 访问子缓存中不存在的 key → 触发新的 parent evaluator
        var v4 = childCache.get("B"); // parent evaluator("B")="B-newbase-v2", child="B-NEWBASE-V2"
        assertEquals(v4, "B-NEWBASE-V2",
            "mapReset: New key through child uses parent's new evaluator");
        assertEquals(evaluatorCallCount, 2, "mapReset: New evaluator called for B");
    }

    /**
     * P3: OPT-A 验证 — _clear() 后池回收的节点可被后续插入复用
     * 通过观察容量不变式在多次 reset 后仍成立来间接验证。
     */
    public static function testClearPoolDrain():Void {
        trace("Running: testClearPoolDrain");

        var evaluatorCallCount:Number = 0;
        var evaluator:Function = function(key:Object):Object {
            evaluatorCallCount++;
            return "val-" + key;
        };

        var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, 10);

        // 第一轮：填满缓存
        for (var i:Number = 0; i < 10; i++) {
            cache.get("key" + i);
        }
        assertEquals(evaluatorCallCount, 10, "clearPool: 10 evaluator calls for initial fill");

        // reset → OPT-A 应将 10 个节点回收入池
        cache.reset(null, true);

        // 第二轮：重新填满（应复用池节点，不分配新对象）
        for (var j:Number = 0; j < 10; j++) {
            cache.get("newkey" + j);
        }
        assertEquals(evaluatorCallCount, 20, "clearPool: 10 more evaluator calls after reset");

        // 容量不变式
        var t1s:Number = cache.getT1().length;
        var t2s:Number = cache.getT2().length;
        assertTrue(t1s + t2s <= 10,
            "clearPool: |T1|+|T2|=" + (t1s + t2s) + " should be <= 10 after reset+refill");

        // 再 reset 一次验证稳定性
        cache.reset(null, true);
        for (var k:Number = 0; k < 15; k++) {
            cache.get("third" + k);
        }
        assertEquals(evaluatorCallCount, 35, "clearPool: 15 more evaluator calls after second reset");

        t1s = cache.getT1().length;
        t2s = cache.getT2().length;
        assertTrue(t1s + t2s <= 10,
            "clearPool: capacity invariant holds after multiple reset cycles");
    }

    // ==================== 入口 ====================

    public static function runTests():Void {
        trace("=== ARCEnhancedLazyCacheTest v3.2: Starting Tests ===");
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

        // v3.1 新增测试
        testCapacity1LazyCache();

        // v3.2 新增测试
        testRemoveAndGet();
        testPutGhostPath();
        testResetNullEvaluator();
        testCapacity2Boundary();
        testMapParentReset();
        testClearPoolDrain();

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
        trace("=== ARCEnhancedLazyCacheTest v3.2: " + testResults.length + " assertions, "
              + passCount + " passed, " + failCount + " failed ===");
    }
}
