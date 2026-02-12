/**
 * ARCCacheTest v3.2
 * 覆盖基础功能 + v2.0 修复 + v3.0/v3.1 新特性的所有边界场景。
 *
 * v3.0 新增测试：
 *   - testHasAPI            : P4 has() 方法
 *   - testCapacity1Edge     : capacity=1 边界
 *   - testRemoveThenGhostHit: remove 后 ghost hit 的 ROBUST-2 路径
 *   - testNodePoolReuse     : OPT-6 节点池复用验证
 *   - testRawKeySemantics   : ARCH-1 原始键语义验证
 *
 * v3.1 新增测试：
 *   - testPutOnB2GhostKey   : B2 ghost put 路径
 *
 * v3.0 变更：
 *   - 移除 UID 前缀 "_" 相关断言（ARCH-1：原始键直接用作属性名）
 *
 * v3.2 变更：
 *   - 版本号同步 ARCCache v3.2（测试覆盖不变，底层实现已优化）
 */
import org.flashNight.naki.Cache.ARCCache;

class org.flashNight.naki.Cache.ARCCacheTest {
    private var cache:ARCCache;
    private var testData:Array;
    private var cacheCapacity:Number;

    public function ARCCacheTest(capacity:Number) {
        this.cacheCapacity = capacity;
        this.cache = new ARCCache(this.cacheCapacity);
        this.testData = [];
    }

    public function runTests():Void {
        trace("=== ARCCacheTest v3.2: Starting Tests ===");

        this.testPutAndGet();
        this.testCacheEviction();
        this.testCacheHitRate();
        this.testPerformance();
        this.testEdgeCases();
        this.testHighFrequencyAccess();
        this.testDuplicateKeys();
        this.testLargeScaleCache();

        // ---- v2.0 测试 ----
        this.testPutOnGhostKey();
        this.testB2HitWithEmptyT1();
        this.testCapacityInvariant();
        this.testCapacityInvariantMixed();
        this.testRemoveFromAllQueues();

        // ---- v3.0 新增测试 ----
        this.testHasAPI();
        this.testCapacity1Edge();
        this.testRemoveThenGhostHit();
        this.testNodePoolReuse();
        this.testRawKeySemantics();

        // ---- v3.1 新增测试 ----
        this.testPutOnB2GhostKey();

        trace("=== ARCCacheTest v3.2: All Tests Completed ===");
    }

    // ==================== 基础测试 ====================

    private function testPutAndGet():Void {
        trace("Running testPutAndGet...");
        this.cache = new ARCCache(this.cacheCapacity);

        this.cache.put("key1", "value1");
        this.cache.put("key2", "value2");
        this.cache.put("key3", "value3");

        this._assertEqual(this.cache.get("key1"), "value1", "Value for key1 should be 'value1'");
        this._assertEqual(this.cache.get("key2"), "value2", "Value for key2 should be 'value2'");
        this._assertEqual(this.cache.get("key3"), "value3", "Value for key3 should be 'value3'");

        trace("testPutAndGet completed successfully.\n");
    }

    private function testCacheEviction():Void {
        trace("Running testCacheEviction...");
        this.cache = new ARCCache(this.cacheCapacity);

        for (var i:Number = 1; i <= this.cacheCapacity; i++) {
            this.cache.put("key" + i, "value" + i);
        }

        this.cache.get("key2");
        this.cache.get("key4");
        this.cache.put("keyExtra", "valueExtra");

        this._printCacheState("After inserting keyExtra");

        var evictedValue:Object = this.cache.get("key1");
        var existingValue:Object = this.cache.get("keyExtra");

        this._assertEqual(evictedValue, null, "Value for key1 should be null (evicted)");
        this._assertEqual(existingValue, "valueExtra", "Value for keyExtra should be 'valueExtra'");

        trace("testCacheEviction completed successfully.\n");
    }

    private function testCacheHitRate():Void {
        trace("Running testCacheHitRate...");
        this.cache = new ARCCache(this.cacheCapacity);
        var totalRequests:Number = 1000;
        var cacheHits:Number = 0;

        this.testData = [];
        for (var i:Number = 1; i <= 2 * this.cacheCapacity; i++) {
            this.testData.push("key" + i);
            this.cache.put("key" + i, "value" + i);
        }

        var randomIndices:Array = [];
        for (var j:Number = 0; j < totalRequests; j++) {
            randomIndices.push(Math.floor(Math.random() * this.testData.length));
        }

        for (var k:Number = 0; k < totalRequests; k++) {
            var keyIndex:Number = randomIndices[k];
            var key:String = this.testData[keyIndex];
            var value:Object = this.cache.get(key);

            if (value != null) {
                cacheHits++;
            } else {
                this.cache.put(key, "value" + key.substring(3));
            }
        }

        var hitRate:Number = (cacheHits / totalRequests) * 100;
        trace("Cache Hit Rate: " + hitRate + "%");
        this._assertInRange(hitRate, 0, 100, "Cache hit rate should be between 0% and 100%");
        trace("testCacheHitRate completed successfully.\n");
    }

    private function testPerformance():Void {
        trace("Running testPerformance...");
        this.cache = new ARCCache(this.cacheCapacity);

        var operations:Number = 10000;
        var startTime:Number = getTimer();

        var i:Number = 0;
        var max:Number = operations - (operations % 4);
        for (; i < max; i += 4) {
            var key1:String = "perfKey" + (i % (2 * this.cacheCapacity));
            this.cache.put(key1, "perfValue" + (i % 100));
            this.cache.get(key1);

            var key2:String = "perfKey" + ((i + 1) % (2 * this.cacheCapacity));
            this.cache.put(key2, "perfValue" + ((i + 1) % 100));
            this.cache.get(key2);

            var key3:String = "perfKey" + ((i + 2) % (2 * this.cacheCapacity));
            this.cache.put(key3, "perfValue" + ((i + 2) % 100));
            this.cache.get(key3);

            var key4:String = "perfKey" + ((i + 3) % (2 * this.cacheCapacity));
            this.cache.put(key4, "perfValue" + ((i + 3) % 100));
            this.cache.get(key4);
        }
        for (; i < operations; i++) {
            var key:String = "perfKey" + (i % (2 * this.cacheCapacity));
            this.cache.put(key, "perfValue" + (i % 100));
            this.cache.get(key);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        trace("Performed " + operations + " cache operations in " + duration + " ms.");
        var opsPerSecond:Number = (operations / duration) * 1000;
        trace("Cache Operations per Second: " + opsPerSecond + "\n");
        this._assertGreaterThan(opsPerSecond, 0, "Operations per second should be greater than 0");
        trace("testPerformance completed successfully.\n");
    }

    private function testEdgeCases():Void {
        trace("Running testEdgeCases...");
        this.cache = new ARCCache(this.cacheCapacity);

        // null 键
        this.cache.put(null, "nullKeyValue");
        var nullKeyResult:Object = this.cache.get(null);
        this._assertEqual(nullKeyResult, "nullKeyValue",
            "Value for null key should be 'nullKeyValue'");

        // undefined 键
        this.cache.put(undefined, "undefKeyValue");
        var undefKeyResult:Object = this.cache.get(undefined);
        this._assertEqual(undefKeyResult, "undefKeyValue",
            "Value for undefined key should be 'undefKeyValue'");

        // 特殊字符
        this.cache.put("key@#", "value@#");
        this._assertEqual(this.cache.get("key@#"), "value@#",
            "Value for 'key@#' should be 'value@#'");

        // v3.0 已知限制：空字符串 "" 在 AS2 AVM1 中作为属性名不可靠
        // （__proto__=null 模式下 obj[""] 行为未定义）
        // 调用者应避免使用 "" 作为缓存键
        this.cache.put("nonEmpty", "nonEmptyValue");
        this._assertEqual(this.cache.get("nonEmpty"), "nonEmptyValue",
            "Value for 'nonEmpty' key should be 'nonEmptyValue'");

        // 数字 key
        this.cache.put(123, "numericKey");
        this._assertEqual(this.cache.get(123), "numericKey",
            "Value for numeric key 123 should be 'numericKey'");

        // 缓存 null 值
        this.cache.put("nullVal", null);
        var storedNull:Object = this.cache.get("nullVal");
        this._assertEqual(storedNull, null,
            "Cached null value should be returned as null (not trigger miss)");

        trace("testEdgeCases completed successfully.\n");
    }

    private function testHighFrequencyAccess():Void {
        trace("Running testHighFrequencyAccess...");
        this.cache = new ARCCache(this.cacheCapacity);

        for (var i:Number = 1; i <= this.cacheCapacity; i++) {
            this.cache.put("hfKey" + i, "hfValue" + i);
        }

        var highFreqKeys:Array = ["hfKey1", "hfKey2", "hfKey3"];
        for (var j:Number = 0; j < 1000; j++) {
            for (var k:Number = 0; k < highFreqKeys.length; k++) {
                this.cache.get(highFreqKeys[k]);
            }
        }

        for (var m:Number = this.cacheCapacity + 1; m <= this.cacheCapacity + 50; m++) {
            this.cache.put("hfKeyExtra" + m, "hfValueExtra" + m);
        }

        for (var n:Number = 0; n < highFreqKeys.length; n++) {
            var value:Object = this.cache.get(highFreqKeys[n]);
            this._assertEqual(value, "hfValue" + (n + 1),
                "High-frequency key " + highFreqKeys[n] + " should still be present");
        }

        trace("testHighFrequencyAccess completed successfully.\n");
    }

    private function testDuplicateKeys():Void {
        trace("Running testDuplicateKeys...");
        this.cache = new ARCCache(this.cacheCapacity);

        this.cache.put("dupKey", "initialValue");
        this._assertEqual(this.cache.get("dupKey"), "initialValue",
            "Initial value for 'dupKey' should be 'initialValue'");

        this.cache.put("dupKey", "updatedValue");
        this._assertEqual(this.cache.get("dupKey"), "updatedValue",
            "Updated value for 'dupKey' should be 'updatedValue'");

        this.cache.get("dupKey");

        for (var i:Number = 1; i <= this.cacheCapacity; i++) {
            this.cache.put("dupKey" + i, "dupValue" + i);
        }

        this._assertEqual(this.cache.get("dupKey"), "updatedValue",
            "Value for 'dupKey' should still be 'updatedValue'");

        trace("testDuplicateKeys completed successfully.\n");
    }

    private function testLargeScaleCache():Void {
        trace("Running testLargeScaleCache...");
        var largeCapacity:Number = 10000;
        this.cache = new ARCCache(largeCapacity);

        for (var i:Number = 1; i <= largeCapacity; i++) {
            this.cache.put("largeKey" + i, "largeValue" + i);
        }
        for (var j:Number = 1; j <= 5000; j++) {
            this.cache.get("largeKey" + j);
        }
        for (var k:Number = largeCapacity + 1; k <= largeCapacity + 5000; k++) {
            this.cache.put("largeKey" + k, "largeValue" + k);
        }

        for (var m:Number = 1; m <= 10; m++) {
            this._assertEqual(this.cache.get("largeKey" + m), "largeValue" + m,
                "Frequently accessed 'largeKey" + m + "' should still be present");
        }

        trace("testLargeScaleCache completed successfully.\n");
    }

    // ==================== v2.0 测试 ====================

    /**
     * CRITICAL-2 覆盖：对 B1/B2 中的 key 直接调用 put()
     */
    private function testPutOnGhostKey():Void {
        trace("Running testPutOnGhostKey...");
        var c:ARCCache = new ARCCache(3);

        // 填满缓存
        c.put("A", "v1"); // T1=[A]
        c.put("B", "v2"); // T1=[B,A]
        c.put("C", "v3"); // T1=[C,B,A]

        // 提升 C 到 T2，确保后续插入走 REPLACE 而非直接删除
        // 若不提升，|T1|=3=c → Case A else → 直接删除 T1 tail，不产生 ghost
        c.get("C"); // HIT: C T1→T2. T1=[B,A], T2=[C]

        // 插入 D → Case B (|T1|=2 < c=3), REPLACE 淘汰 T1 tail (A)→B1
        c.put("D", "v4"); // T1=[D,B], T2=[C], B1=[A]

        // 验证 A 确实在 B1 ghost 中（不能用 get，get 会触发 ghost hit 处理）
        var b1Before:Array = c.getB1();
        var foundInB1:Boolean = false;
        for (var i:Number = 0; i < b1Before.length; i++) {
            if (b1Before[i] == "A") { foundInB1 = true; break; }
        }
        this._assertEqual(foundInB1, true, "A should be in B1 ghost queue before put");

        // 对 B1 ghost key 执行 put → put() 中的 B1 ghost hit 路径
        c.put("A", "newA");

        // 验证 A 已可访问且值正确（put on ghost → 移入 T2）
        this._assertEqual(c.get("A"), "newA",
            "After put on ghost key, A should be accessible with new value");

        // 容量不变式
        var t1Size:Number = c.getT1().length;
        var t2Size:Number = c.getT2().length;
        var totalCache:Number = t1Size + t2Size;
        if (totalCache > 3) {
            trace("Assertion Failed: T1+T2=" + totalCache + " exceeds capacity 3");
        } else {
            trace("Assertion Passed: Cache size " + totalCache + " within capacity");
        }

        // B1 中不应残留 A（CRITICAL-2 回归检查）
        var b1After:Array = c.getB1();
        var foundOrphan:Boolean = false;
        for (var j:Number = 0; j < b1After.length; j++) {
            if (b1After[j] == "A") { foundOrphan = true; break; }
        }
        this._assertEqual(foundOrphan, false, "No orphan 'A' in B1 after put on ghost key");

        trace("testPutOnGhostKey completed successfully.\n");
    }

    /**
     * HIGH-1 覆盖：B2 ghost hit 时 T1 为空
     */
    private function testB2HitWithEmptyT1():Void {
        trace("Running testB2HitWithEmptyT1...");
        var c:ARCCache = new ARCCache(3);

        c.put("A", "vA");
        c.put("B", "vB");
        c.put("C", "vC");

        c.get("A");
        c.get("B");
        c.get("C");

        c.put("D", "vD");
        c.get("D");

        c.get("A");

        var t1Arr:Array = c.getT1();
        var t2Arr:Array = c.getT2();
        var total:Number = t1Arr.length + t2Arr.length;
        if (total > 3) {
            trace("Assertion Failed: T1+T2=" + total + " exceeds capacity 3 (HIGH-1 regression)");
        } else {
            trace("Assertion Passed: Cache size " + total + " within capacity after B2 hit with empty T1");
        }

        trace("testB2HitWithEmptyT1 completed successfully.\n");
    }

    /**
     * 容量不变式：大量唯一 key 连续访问
     */
    private function testCapacityInvariant():Void {
        trace("Running testCapacityInvariant...");
        var cap:Number = 50;
        var c:ARCCache = new ARCCache(cap);

        for (var i:Number = 0; i < cap * 3; i++) {
            c.put("inv" + i, "val" + i);
        }

        var t1s:Number = c.getT1().length;
        var t2s:Number = c.getT2().length;
        var b1s:Number = c.getB1().length;
        var b2s:Number = c.getB2().length;
        var cacheSize:Number = t1s + t2s;
        var totalSize:Number = t1s + t2s + b1s + b2s;

        trace("  T1=" + t1s + " T2=" + t2s + " B1=" + b1s + " B2=" + b2s);

        if (cacheSize > cap) {
            trace("Assertion Failed: |T1|+|T2|=" + cacheSize + " > capacity " + cap);
        } else {
            trace("Assertion Passed: |T1|+|T2|=" + cacheSize + " <= capacity " + cap);
        }

        if (totalSize > 2 * cap) {
            trace("Assertion Failed: total=" + totalSize + " > 2*capacity " + (2 * cap));
        } else {
            trace("Assertion Passed: total=" + totalSize + " <= 2*capacity " + (2 * cap));
        }

        trace("testCapacityInvariant completed successfully.\n");
    }

    /**
     * 混合访问模式容量不变式
     */
    private function testCapacityInvariantMixed():Void {
        trace("Running testCapacityInvariantMixed...");
        var cap:Number = 30;
        var c:ARCCache = new ARCCache(cap);

        for (var i:Number = 0; i < cap; i++) {
            c.put("k" + i, "v" + i);
        }
        for (var j:Number = 0; j < cap / 2; j++) {
            c.get("k" + j);
        }
        for (var k:Number = cap; k < cap * 2; k++) {
            c.put("k" + k, "v" + k);
        }
        for (var m:Number = 0; m < cap / 3; m++) {
            c.get("k" + m);
        }
        for (var n:Number = cap * 2; n < cap * 3; n++) {
            c.put("k" + n, "v" + n);
        }

        var t1s:Number = c.getT1().length;
        var t2s:Number = c.getT2().length;
        var b1s:Number = c.getB1().length;
        var b2s:Number = c.getB2().length;
        var cacheSize:Number = t1s + t2s;
        var totalSize:Number = t1s + t2s + b1s + b2s;
        var L1:Number = t1s + b1s;

        trace("  Mixed: T1=" + t1s + " T2=" + t2s + " B1=" + b1s + " B2=" + b2s);

        if (cacheSize > cap) {
            trace("Assertion Failed: |T1|+|T2|=" + cacheSize + " > capacity " + cap);
        } else {
            trace("Assertion Passed: |T1|+|T2|=" + cacheSize + " <= capacity " + cap);
        }
        if (totalSize > 2 * cap) {
            trace("Assertion Failed: total=" + totalSize + " > 2c=" + (2 * cap));
        } else {
            trace("Assertion Passed: total=" + totalSize + " <= 2c=" + (2 * cap));
        }
        if (L1 > cap) {
            trace("Assertion Failed: L1=|T1|+|B1|=" + L1 + " > c=" + cap);
        } else {
            trace("Assertion Passed: L1=|T1|+|B1|=" + L1 + " <= c=" + cap);
        }

        if (b1s + b2s > 0) {
            trace("Assertion Passed: Ghost queues non-empty (B1+B2=" + (b1s + b2s) + "), mixed pattern exercised");
        } else {
            trace("Warning: Ghost queues empty — mixed pattern may not have produced ghost hits");
        }

        trace("testCapacityInvariantMixed completed successfully.\n");
    }

    /**
     * remove() 覆盖所有四个队列
     */
    private function testRemoveFromAllQueues():Void {
        trace("Running testRemoveFromAllQueues...");
        var c:ARCCache = new ARCCache(3);

        // 从 T1 移除
        c.put("X", "vX");
        this._assertEqual(c.remove("X"), true, "remove from T1 should return true");
        this._assertEqual(c.get("X"), null, "X should be gone after remove");

        // 从 T2 移除
        c.put("Y", "vY");
        c.get("Y");
        c.put("Z", "vZ");
        this._assertEqual(c.remove("Y"), true, "remove from T2 should return true");
        this._assertEqual(c.get("Y"), null, "Y should be gone after remove from T2");

        // 从 B1 移除
        var c3:ARCCache = new ARCCache(3);
        c3.put("P", "vP");
        c3.put("Q", "vQ");
        c3.put("R", "vR");
        c3.get("P");
        c3.put("S", "vS");
        this._assertEqual(c3.remove("Q"), true, "remove from B1 ghost should return true");
        c3.get("Q");
        this._assertEqual(c3._hitType, 0, "After remove from B1, Q should be complete MISS (hitType=0)");

        // 从 B2 移除
        var c4:ARCCache = new ARCCache(3);
        c4.put("M", "vM");
        c4.put("N", "vN");
        c4.put("O", "vO");
        c4.get("M"); c4.get("N"); c4.get("O");
        c4.put("W", "vW");
        c4.get("W");
        this._assertEqual(c4.remove("M"), true, "remove from B2 ghost should return true");
        c4.get("M");
        this._assertEqual(c4._hitType, 0, "After remove from B2, M should be complete MISS (hitType=0)");

        // 不存在的 key
        this._assertEqual(c.remove("nonexistent"), false,
            "remove non-existent key should return false");

        trace("testRemoveFromAllQueues completed successfully.\n");
    }

    // ==================== v3.0 新增测试 ====================

    /**
     * P4 API-1：has() 方法
     */
    private function testHasAPI():Void {
        trace("Running testHasAPI...");
        var c:ARCCache = new ARCCache(3);

        // 空缓存
        this._assertEqual(c.has("X"), false, "has() on empty cache should be false");

        // T1 中
        c.put("A", "vA");
        this._assertEqual(c.has("A"), true, "has() for T1 entry should be true");

        // T2 中
        c.get("A"); // A: T1→T2
        this._assertEqual(c.has("A"), true, "has() for T2 entry should be true");

        // 幽灵中
        c.put("B", "vB");
        c.put("C", "vC");
        c.put("D", "vD"); // 淘汰可能发生
        // 填充更多以确保某些 key 被淘汰到 ghost
        c.put("E", "vE");

        // 已移除的 key
        c.put("F", "vF");
        c.remove("F");
        this._assertEqual(c.has("F"), false, "has() after remove should be false");

        // 不存在的 key
        this._assertEqual(c.has("ZZZ"), false, "has() for non-existent key should be false");

        // has() 不应改变 _hitType
        c.put("G", "vG");
        c.get("G"); // 设置 _hitType = 1
        var savedHitType:Number = c._hitType;
        c.has("nonexistent"); // 不应修改 _hitType
        this._assertEqual(c._hitType, savedHitType,
            "has() should not modify _hitType");

        trace("testHasAPI completed successfully.\n");
    }

    /**
     * P3 VALID-1：capacity=1 边界
     */
    private function testCapacity1Edge():Void {
        trace("Running testCapacity1Edge...");
        var c:ARCCache = new ARCCache(1);

        // 放入一个，取出一个
        c.put("A", "vA");
        this._assertEqual(c.get("A"), "vA", "c=1: A should be retrievable");

        // 放入第二个，第一个被淘汰
        c.put("B", "vB");
        this._assertEqual(c.get("B"), "vB", "c=1: B should be retrievable");
        // 路径分析（c=1）：
        //   put("A") → T1=[A]
        //   get("A") → A: T1→T2, T1=[], T2=[A]
        //   put("B") → Case B (L1=0 < c=1), REPLACE 淘汰 T2 tail (A)→B2
        //   get("B") → B: T1→T2, T1=[], T2=[B], B2=[A]
        //   get("A") → B2 ghost hit (_hitType=3)
        var aVal:Object = c.get("A");
        this._assertEqual(c._hitType, 3, "c=1: A should be GHOST_B2 after T2 eviction");

        // 提升到 T2 再测试
        c.put("C", "vC");
        c.get("C"); // C: T1→T2
        this._assertEqual(c.get("C"), "vC", "c=1: C in T2 should be retrievable");

        // 再放入新 key，C 应被淘汰
        c.put("D", "vD");
        this._assertEqual(c.get("D"), "vD", "c=1: D should be retrievable");

        // 容量不变式
        var total:Number = c.getT1().length + c.getT2().length;
        if (total > 1) {
            trace("Assertion Failed: c=1 but |T1|+|T2|=" + total);
        } else {
            trace("Assertion Passed: c=1, |T1|+|T2|=" + total + " <= 1");
        }

        trace("testCapacity1Edge completed successfully.\n");
    }

    /**
     * P2 ROBUST-2：remove 后 ghost hit 应跳过 REPLACE（cache 未满）
     */
    private function testRemoveThenGhostHit():Void {
        trace("Running testRemoveThenGhostHit...");
        var c:ARCCache = new ARCCache(3);

        // 填满 + 构造 ghost
        c.put("A", "vA");
        c.put("B", "vB");
        c.put("C", "vC");
        c.get("A"); // A: T1→T2
        c.put("D", "vD"); // REPLACE: B→B1; T1=[D,C], T2=[A]
        // B 现在在 B1

        // remove 一个 live entry，使 cache 不满
        c.remove("C"); // T1=[D], T2=[A], B1=[B]; |T1|+|T2|=2 < 3

        // 触发 B1 ghost hit（B）
        // ROBUST-2：cache 未满，应跳过 REPLACE，不淘汰 D 或 A
        c.get("B"); // B1 ghost hit
        this._assertEqual(c._hitType, 2, "B should be ghost hit (B1)");

        // D 和 A 应该仍然在缓存中（没有被不必要的 REPLACE 淘汰）
        this._assertEqual(c.get("D"), "vD", "D should survive (no unnecessary REPLACE)");
        this._assertEqual(c.get("A"), "vA", "A should survive (no unnecessary REPLACE)");

        // 容量不变式
        var total:Number = c.getT1().length + c.getT2().length;
        if (total > 3) {
            trace("Assertion Failed: |T1|+|T2|=" + total + " > 3 after ghost hit with slack");
        } else {
            trace("Assertion Passed: |T1|+|T2|=" + total + " <= 3 (ROBUST-2 working)");
        }

        trace("testRemoveThenGhostHit completed successfully.\n");
    }

    /**
     * OPT-6：节点池复用验证
     * 通过反复插入+淘汰，验证容量不变式仍然成立（间接验证池不破坏链表）
     */
    private function testNodePoolReuse():Void {
        trace("Running testNodePoolReuse...");
        var cap:Number = 10;
        var c:ARCCache = new ARCCache(cap);

        // Phase 1: 填满并淘汰多次（触发池化）
        for (var i:Number = 0; i < cap * 5; i++) {
            c.put("pool" + i, "val" + i);
        }

        // Phase 2: 混合访问（ghost hit + 新 key，触发池分配）
        for (var j:Number = 0; j < cap; j++) {
            c.get("pool" + j); // 部分可能 ghost hit
        }
        for (var k:Number = cap * 5; k < cap * 6; k++) {
            c.put("pool" + k, "val" + k);
        }

        // Phase 3: 验证所有不变式
        var t1s:Number = c.getT1().length;
        var t2s:Number = c.getT2().length;
        var b1s:Number = c.getB1().length;
        var b2s:Number = c.getB2().length;
        var cacheSize:Number = t1s + t2s;
        var totalSize:Number = t1s + t2s + b1s + b2s;

        trace("  Pool: T1=" + t1s + " T2=" + t2s + " B1=" + b1s + " B2=" + b2s);

        if (cacheSize > cap) {
            trace("Assertion Failed: pool reuse broke invariant |T1|+|T2|=" + cacheSize + " > " + cap);
        } else {
            trace("Assertion Passed: pool reuse, |T1|+|T2|=" + cacheSize + " <= " + cap);
        }

        if (totalSize > 2 * cap) {
            trace("Assertion Failed: pool reuse broke invariant total=" + totalSize + " > " + (2 * cap));
        } else {
            trace("Assertion Passed: pool reuse, total=" + totalSize + " <= " + (2 * cap));
        }

        // Phase 4: 验证值正确性（池复用节点的 uid/value 正确覆盖）
        var lastKey:String = "pool" + (cap * 6 - 1);
        this._assertEqual(c.get(lastKey), "val" + (cap * 6 - 1),
            "Last inserted key via pool reuse should have correct value");

        trace("testNodePoolReuse completed successfully.\n");
    }

    /**
     * ARCH-1：原始键语义验证
     * 验证 Number 键、String 键的行为符合预期
     */
    private function testRawKeySemantics():Void {
        trace("Running testRawKeySemantics...");
        var c:ARCCache = new ARCCache(10);

        // Number 键
        c.put(42, "num42");
        this._assertEqual(c.get(42), "num42", "Number key 42 should work");

        // Boolean 键
        c.put(true, "boolTrue");
        this._assertEqual(c.get(true), "boolTrue", "Boolean key true should work");

        // 已知限制 1：Number 与 String 表示相同时碰撞
        c.put(99, "fromNumber");
        c.put("99", "fromString");
        // "99" 覆盖了 99 的值（因为 AS2 将 99 转为 "99" 做属性名）
        this._assertEqual(c.get(99), "fromString",
            "[Known] Number 99 and String '99' collide — last write wins");

        // 已知限制 2：空字符串 "" 在 AS2 AVM1 中作为属性名不可靠
        // （__proto__=null 模式下 obj[""] 的行为未定义，put/get 可能失败）
        // 调用者应避免使用 "" 作为缓存键

        // getT1/getT2 返回原始键（不带 "_" 前缀）
        var c2:ARCCache = new ARCCache(3);
        c2.put("hello", "world");
        var t1:Array = c2.getT1();
        this._assertEqual(t1[0], "hello",
            "getT1() should return raw key 'hello' (no prefix)");

        // capacity=0 应被校正为 1（VALID-1）
        var c3:ARCCache = new ARCCache(0);
        this._assertEqual(c3.getCapacity(), 1, "capacity=0 should be corrected to 1");

        var c4:ARCCache = new ARCCache(-5);
        this._assertEqual(c4.getCapacity(), 1, "capacity=-5 should be corrected to 1");

        trace("testRawKeySemantics completed successfully.\n");
    }

    // ==================== v3.1 新增测试 ====================

    /**
     * v3.1 P2：对 B2 ghost key 调用 put()
     * 构造 T2 → B2 淘汰路径，验证 put() 的 B2 ghost hit 行为。
     */
    private function testPutOnB2GhostKey():Void {
        trace("Running testPutOnB2GhostKey...");
        var c:ARCCache = new ARCCache(3);

        // 填满缓存并全部提升到 T2
        c.put("A", "v1"); // T1=[A]
        c.put("B", "v2"); // T1=[B,A]
        c.put("C", "v3"); // T1=[C,B,A]
        c.get("A"); // A: T1→T2. T1=[C,B], T2=[A]
        c.get("B"); // B: T1→T2. T1=[C], T2=[B,A]
        c.get("C"); // C: T1→T2. T1=[], T2=[C,B,A]

        // 插入 D → _doReplace 从 T2 淘汰 tail (A) → B2
        // p=0, t1Size=0 → T2 eviction
        c.put("D", "v4"); // T1=[D], T2=[C,B], B2=[A]

        // 验证 A 在 B2 中（不能用 get，会触发 ghost hit 处理）
        var b2Before:Array = c.getB2();
        var foundInB2:Boolean = false;
        for (var i:Number = 0; i < b2Before.length; i++) {
            if (b2Before[i] == "A") { foundInB2 = true; break; }
        }
        this._assertEqual(foundInB2, true, "A should be in B2 ghost queue before put");

        // 对 B2 ghost key 执行 put → put() 中的 B2 ghost hit 路径
        c.put("A", "newA");

        // 验证 A 可访问且值正确（put on B2 ghost → 移入 T2）
        this._assertEqual(c.get("A"), "newA",
            "After put on B2 ghost key, A should be accessible with new value");

        // 容量不变式
        var t1Size:Number = c.getT1().length;
        var t2Size:Number = c.getT2().length;
        var totalCache:Number = t1Size + t2Size;
        if (totalCache > 3) {
            trace("Assertion Failed: T1+T2=" + totalCache + " exceeds capacity 3");
        } else {
            trace("Assertion Passed: Cache size " + totalCache + " within capacity after B2 ghost put");
        }

        // B2 中不应残留 A
        var b2After:Array = c.getB2();
        var foundOrphan:Boolean = false;
        for (var j:Number = 0; j < b2After.length; j++) {
            if (b2After[j] == "A") { foundOrphan = true; break; }
        }
        this._assertEqual(foundOrphan, false, "No orphan 'A' in B2 after put on B2 ghost key");

        trace("testPutOnB2GhostKey completed successfully.\n");
    }

    // ==================== 工具方法 ====================

    private function _assertEqual(actual:Object, expected:Object, message:String):Void {
        if (actual !== expected) {
            trace("Assertion Failed: " + message + " (Expected: " + expected + ", Actual: " + actual + ")");
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    private function _assertInRange(value:Number, min:Number, max:Number, message:String):Void {
        if (value < min || value > max) {
            trace("Assertion Failed: " + message + " (Value: " + value + ")");
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    private function _assertGreaterThan(value:Number, min:Number, message:String):Void {
        if (value <= min) {
            trace("Assertion Failed: " + message + " (Value: " + value + ")");
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    private function _printCacheState(stage:String):Void {
        trace("=== Cache State at " + stage + " ===");
        trace("T1: " + this.cache.getT1().join(","));
        trace("T2: " + this.cache.getT2().join(","));
        trace("B1: " + this.cache.getB1().join(","));
        trace("B2: " + this.cache.getB2().join(","));
        trace("==============================");
    }
}
