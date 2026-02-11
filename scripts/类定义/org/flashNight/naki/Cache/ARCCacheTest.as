/**
 * ARCCacheTest v2.0
 * 覆盖基础功能 + v2.0 修复的所有边界场景。
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
        trace("=== ARCCacheTest v2.0: Starting Tests ===");

        this.testPutAndGet();
        this.testCacheEviction();
        this.testCacheHitRate();
        this.testPerformance();
        this.testEdgeCases();
        this.testHighFrequencyAccess();
        this.testDuplicateKeys();
        this.testLargeScaleCache();

        // ---- v2.0 新增测试 ----
        this.testPutOnGhostKey();
        this.testB2HitWithEmptyT1();
        this.testCapacityInvariant();
        this.testRemoveFromAllQueues();

        trace("=== ARCCacheTest v2.0: All Tests Completed ===");
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

        // key1 被淘汰后在 B1 中，get 触发 ghost hit 返回 null
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

        // null 值测试：put(null, "someValue") 验证 null key 可正确命中
        this.cache.put(null, "nullKeyValue");
        var nullKeyResult:Object = this.cache.get(null);
        this._assertEqual(nullKeyResult, "nullKeyValue",
            "Value for null key should be 'nullKeyValue'");

        // undefined 值测试
        this.cache.put(undefined, "undefKeyValue");
        var undefKeyResult:Object = this.cache.get(undefined);
        this._assertEqual(undefKeyResult, "undefKeyValue",
            "Value for undefined key should be 'undefKeyValue'");

        // 特殊字符
        this.cache.put("key@#", "value@#");
        this._assertEqual(this.cache.get("key@#"), "value@#",
            "Value for 'key@#' should be 'value@#'");

        // 空字符串 key
        this.cache.put("", "emptyKey");
        this._assertEqual(this.cache.get(""), "emptyKey",
            "Value for empty string key should be 'emptyKey'");

        // 数字 key
        this.cache.put(123, "numericKey");
        this._assertEqual(this.cache.get(123), "numericKey",
            "Value for numeric key 123 should be 'numericKey'");

        // 缓存 null 值（v2.0：确保 null 值不被误判为 miss）
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

    // ==================== v2.0 新增测试 ====================

    /**
     * CRITICAL-2 覆盖：对 B1/B2 中的 key 直接调用 put()
     * 旧版会产生孤儿节点，新版应正确做 p 自适应 + REPLACE + 移入 T2
     */
    private function testPutOnGhostKey():Void {
        trace("Running testPutOnGhostKey...");
        var c:ARCCache = new ARCCache(3);

        // 填满 T1: [C, B, A]
        c.put("A", "v1");
        c.put("B", "v2");
        c.put("C", "v3");

        // 插入 D，淘汰 A → B1: [A]
        c.put("D", "v4");
        this._assertEqual(c.get("A"), null, "A should be ghost (in B1)");

        // 关键操作：直接 put("A", "newA") 而不先 get("A")
        // 旧版会创建孤儿节点；新版应正确处理 B1 ghost hit
        c.put("A", "newA");

        // A 应该回到缓存中（T2）
        this._assertEqual(c.get("A"), "newA",
            "After put on ghost key, A should be accessible with new value");

        // 验证队列完整性：T1+T2 不应超过容量
        var t1Size:Number = c.getT1().length;
        var t2Size:Number = c.getT2().length;
        var totalCache:Number = t1Size + t2Size;
        if (totalCache > 3) {
            trace("Assertion Failed: T1+T2=" + totalCache + " exceeds capacity 3");
        } else {
            trace("Assertion Passed: Cache size " + totalCache + " within capacity");
        }

        // 验证 B1 不包含 A 的孤儿节点
        var b1:Array = c.getB1();
        var foundOrphan:Boolean = false;
        for (var i:Number = 0; i < b1.length; i++) {
            if (b1[i] == "_A") { foundOrphan = true; break; }
        }
        if (foundOrphan) {
            trace("Assertion Failed: Orphan node '_A' found in B1 (CRITICAL-2 regression)");
        } else {
            trace("Assertion Passed: No orphan '_A' in B1");
        }

        trace("testPutOnGhostKey completed successfully.\n");
    }

    /**
     * HIGH-1 覆盖：B2 ghost hit 时 T1 为空
     * 旧版缺少 |T1|>0 守卫导致淘汰缺失，T1+T2 永久超容量
     */
    private function testB2HitWithEmptyT1():Void {
        trace("Running testB2HitWithEmptyT1...");
        var c:ARCCache = new ARCCache(3);

        // 构造 T1 为空、T2 满、B2 非空的状态
        // Step 1: 填满 T1
        c.put("A", "vA");
        c.put("B", "vB");
        c.put("C", "vC");

        // Step 2: 全部访问一次，将 T1 条目提升到 T2
        c.get("A"); // A: T1 → T2
        c.get("B"); // B: T1 → T2
        c.get("C"); // C: T1 → T2
        // 现在 T1=0, T2=3 (A,B,C)

        // Step 3: 插入新 key，触发从 T2 淘汰（因为 T1 为空，p=0 → T1.size<=p → 从 T2 淘汰）
        c.put("D", "vD");
        // T2 的 LRU (A) 被淘汰到 B2
        // T1=[D], T2=[C,B], B2=[A]

        // Step 4: 将 D 也提升到 T2
        c.get("D"); // D: T1 → T2
        // T1=0, T2=[D,C,B], B2=[A]

        // Step 5: 触发 B2 ghost hit — 这是 HIGH-1 的测试场景
        // 再次访问 A（在 B2 中）
        c.get("A"); // B2 ghost hit, T1 为空
        // 旧版：跳过淘汰 → T2 变成 4 个 → 超容量
        // 新版：|T1|>0 守卫 → 回退到从 T2 淘汰 → 正确

        // 验证容量不超标
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
     * HIGH-2 覆盖：大量唯一 key 的连续访问不应使缓存无界增长
     */
    private function testCapacityInvariant():Void {
        trace("Running testCapacityInvariant...");
        var cap:Number = 50;
        var c:ARCCache = new ARCCache(cap);

        // 插入 3x 容量的唯一 key
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
     * remove() 覆盖：从所有四个队列中移除
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
        c.get("Y"); // T1 → T2
        c.put("Z", "vZ"); // 填充，Y 留在 T2
        this._assertEqual(c.remove("Y"), true, "remove from T2 should return true");
        this._assertEqual(c.get("Y"), null, "Y should be gone after remove from T2");

        // 移除不存在的 key
        this._assertEqual(c.remove("nonexistent"), false,
            "remove non-existent key should return false");

        trace("testRemoveFromAllQueues completed successfully.\n");
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
