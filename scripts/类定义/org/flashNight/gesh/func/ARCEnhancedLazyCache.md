# ARCEnhancedLazyCache v3.0 使用指南

## 目录

1. [简介](#简介)
2. [核心机制](#核心机制)
3. [API 参考](#api-参考)
4. [v3.0 变更摘要](#v30-变更摘要)
5. [使用指南](#使用指南)
6. [异常安全性](#异常安全性)
7. [注意事项](#注意事项)
8. [运行测试](#运行测试)

---

## 简介

**ARCEnhancedLazyCache v3.0** 继承自 `ARCCache v3.0`，在其基础上增加了**懒加载**能力：当 `get(key)` 缓存未命中时，自动调用 `evaluator(key)` 计算并缓存结果。

适用于"计算结果可缓存"的场景 —— 调用者只需提供一个计算函数和容量，之后对缓存的使用完全透明：首次 get 自动计算，后续 get 直接命中。

---

## 核心机制

### _hitType 三路分发

`get(key)` 通过父类 `ARCCache.get()` 返回的 `_hitType` 区分三种情况：

| _hitType | 含义 | LazyCache 行为 |
|----------|------|----------------|
| 1 (HIT) | T1/T2 命中 | 直接返回缓存值 |
| 0 (MISS) | 完全未命中 | `evaluator(key)` → `super.put(key, computed)`（触发淘汰） |
| 2/3 (GHOST) | B1/B2 幽灵命中 | `evaluator(key)` → `node.value = computed`（直赋，OPT-5） |

### ghost hit 直赋 (OPT-5)

ghost hit 时，`super.get()` 已将节点移入 T2（但 value 为 undefined）。LazyCache 通过 `_lastNode.value = computed` 直接赋值，跳过 `putNoEvict`，避免一次额外的 nodeMap 查找和链表操作。

### 可重入安全

`_lastNode` 在调用 evaluator 之前存入局部变量 `node`，防止 evaluator 内部的缓存操作覆盖 `_lastNode`。

---

## API 参考

### 构造函数

```actionscript
new ARCEnhancedLazyCache(evaluator:Function, capacity:Number)
```

- `evaluator`：计算函数 `(key) => value`，必须是 Function 类型
- `capacity`：ARC 缓存容量（至少 1，继承自 ARCCache VALID-1）

### get(key):Object

缓存命中直接返回；未命中则调用 `evaluator(key)` 计算后缓存并返回。

```actionscript
var cache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(
    function(k) { return expensiveComputation(k); },
    100
);
var result = cache.get("myKey"); // 自动计算或命中缓存
```

### reset(newEvaluator:Function, clearCache:Boolean):Void

重置 evaluator 和/或清空缓存。

- `newEvaluator`：新的计算函数（null/undefined 则保持不变）
- `clearCache`：是否清空缓存（默认/undefined/true = 清空；显式 `false` = 保留）

```actionscript
cache.reset(newEvaluator, true);   // 更换 evaluator + 清空缓存
cache.reset(null, true);           // 仅清空缓存
cache.reset(newEvaluator, false);  // 更换 evaluator，保留已有缓存
```

### map(transformer:Function, capacity:Number):ARCEnhancedLazyCache

创建转换缓存：新缓存的 evaluator 先从本缓存取值，再应用 `transformer`。

```actionscript
var upperCache = cache.map(function(baseValue) {
    return String(baseValue).toUpperCase();
}, 50);
var result = upperCache.get("key"); // 先从 cache 取 base，再 toUpperCase
```

**GC 注意**：返回的缓存通过闭包持有对本缓存的引用。多层 map 链形成引用链，所有层级都不会被 GC。如需释放，应手动将不再使用的中间缓存引用置为 null。

### 继承的 API

以下方法直接从 `ARCCache` 继承，无重写：

| 方法 | 说明 |
|------|------|
| `put(key, value)` | 手动放入值（后续 get 命中时返回手动值，不调用 evaluator） |
| `putNoEvict(key, value)` | 不触发淘汰的 put |
| `remove(key):Boolean` | 移除 key（含幽灵队列） |
| `has(key):Boolean` | 不变更状态的存在性检查（v3.0 新增） |
| `getT1/T2/B1/B2():Array` | 调试用：获取队列内容 |
| `getCapacity():Number` | 获取容量 |

---

## v3.0 变更摘要

### 自身变更

| 优先级 | 编号 | 变更 | 效果 |
|--------|------|------|------|
| P0 | ARCH-1 | 继承 ARCCache v3.0 原始键语义 | 无内部 UID 转换，key 直接传递给父类 |
| P1 | OPT-7 | `===` 严格比较替代 `==` | 消除 ActionEquals2 类型协商 |
| P3 | SAFE-1 | ghost hit 路径增加 try/catch | evaluator 异常时调用 `super.remove(key)` 清除 T2 中的僵尸节点后重抛 |

### 继承自 ARCCache v3.0 的变更

- ARCH-2：`nodeMap.__proto__ = null`
- OPT-6：节点池化
- ROBUST-1/2：空队列回退 + REPLACE 守卫
- OPT-8：`_clear()` 重用哨兵
- VALID-1：容量校验
- API-1：`has()` 方法

---

## 使用指南

### 基本用法

```actionscript
import org.flashNight.gesh.func.ARCEnhancedLazyCache;

// 创建：evaluator 是一个 key => value 的计算函数
var damageCache:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(
    function(bitmask:Number):Object {
        return computeDamageManager(bitmask);
    },
    64
);

// 使用：get 自动计算并缓存
var mgr = damageCache.get(attackBitmask);
```

### 配合 has() 使用

```actionscript
// has() 不触发 evaluator，可用于"仅在已缓存时取值"的场景
if (damageCache.has(bitmask)) {
    var mgr = damageCache.get(bitmask); // 保证命中
}
```

### 手动 put 覆盖

```actionscript
// 手动 put 的值优先于 evaluator
damageCache.put(specialBitmask, precomputedManager);
var mgr = damageCache.get(specialBitmask); // 返回 precomputedManager
```

### map 转换链

```actionscript
// 两级缓存链
var baseCache = new ARCEnhancedLazyCache(computeBase, 100);
var derivedCache = baseCache.map(function(base) {
    return deriveFromBase(base);
}, 50);

var result = derivedCache.get("key");
// 内部：derivedCache.evaluator("key")
//   → baseCache.get("key")
//     → computeBase("key")  [if miss]
//   → deriveFromBase(base)
```

---

## 异常安全性

### MISS 路径

evaluator 抛异常时，`super.put()` 尚未执行，缓存状态不变。异常直接传播给调用者。

### GHOST 路径 (SAFE-1)

evaluator 抛异常时，`super.get()` 已将节点移入 T2（value = undefined），形成"僵尸节点"。`catch` 中调用 `super.remove(key)` 清除僵尸后重抛异常。

这确保了：
- 缓存中不会保留 value 为 undefined 的僵尸节点
- 后续 `get(同一key)` 会得到完全 MISS（而非错误的 HIT 返回 undefined）
- 调用者可以 catch 异常后重试

```actionscript
try {
    var result = cache.get("problematicKey");
} catch (e) {
    // evaluator 抛异常
    // 缓存状态已清理（僵尸已移除）
    // 可安全重试
    trace("Error: " + e.message);
}
```

---

## 注意事项

1. **evaluator 不应抛异常**：虽然有 SAFE-1 保护，但异常路径有额外开销（remove 操作）。生产代码中 evaluator 应尽量确保不抛异常。

2. **同 key 可重入**：如果 evaluator 内部又调用 `get(同一key)`：
   - MISS 路径：会递归调用 evaluator（可能导致无限递归）
   - GHOST 路径：内层 get 会 HIT 并返回 undefined（因为节点已在 T2 但 value 未填充）
   - **建议**：evaluator 不应对同一缓存实例递归调用 `get()`

3. **键语义**：继承 ARCCache v3.0 的原始键语义。Number 与 String 表示相同时会碰撞。详见 ARCCache.md。

4. **null/undefined 返回值**：evaluator 返回 null 或 undefined 是合法的，会被正确缓存。后续 get 命中时返回 null/undefined（不再调用 evaluator）。

5. **GC 与 map 链**：map() 创建的缓存通过闭包持有对父缓存的引用，不会被 GC。多层 map 链需手动管理生命周期。

---

### v3.0 测试覆盖

| 测试 | 覆盖点 |
|------|--------|
| testBasicFunctionality | 基本 get/miss/hit |
| testEvictionStrategy | ARC 淘汰策略 + 热端保留 |
| testMapFunction | map() 转换链 |
| testResetFunction | reset() 清空/保留 |
| testEdgeCases | null 键、对象键、多次 reset |
| testNullValueEvaluator | CRITICAL-1：null 值正确缓存 |
| testUndefinedValueEvaluator | CRITICAL-1：undefined 值正确缓存 |
| testCapacityInvariantLazyCache | HIGH-2：容量不变式 |
| testGhostHitRoundTrip | ghost hit 回填完整链路 |
| testPutGetInteraction | put+get 交互（手动值优先） |
| **testEvaluatorExceptionOnMiss** | **v3.0 SAFE-1/MISS：异常无副作用** |
| **testEvaluatorExceptionOnGhostHit** | **v3.0 SAFE-1/GHOST：僵尸清除** |
| **testHasViaLazyCache** | **v3.0 API-1：has() 不触发 evaluator** |
| **testRawKeyLazyCache** | **v3.0 ARCH-1：原始键语义** |
| testPerformance | 10000 次命中 < 200ms |


## 运行测试

```actionscript
org.flashNight.gesh.func.ARCEnhancedLazyCacheTest.runTests();
```

```

=== ARCEnhancedLazyCacheTest v3.0: Starting Tests ===
Running: testBasicFunctionality
[PASS] Cache should compute and return Value-A for key 'A'
[PASS] Evaluator should be called once for key 'A'
[PASS] Cache should return cached Value-A for key 'A'
[PASS] Evaluator should not be called again for key 'A'
[PASS] Cache should compute and return Value-B for key 'B'
[PASS] Evaluator should be called once for key 'B'
[PASS] Cache should compute and return Value-C for key 'C'
[PASS] Evaluator should be called once for key 'C'
[PASS] Cache should compute and return Value-D for key 'D'
[PASS] Evaluator should be called once for key 'D'
[PASS] Cache should return Value-A (recomputed or cached)
Running: testEvictionStrategy
[PASS] Hot key 'A' should still be cached
[PASS] Evaluator should not be called again for hot key 'A'
[PASS] Key 'B' should return correct value (cached or recomputed)
[PASS] Key 'C' should return correct value (cached or recomputed)
Running: testMapFunction
[PASS] Mapped cache should return transformed value for key 'A'
[PASS] Evaluator should not be called again for cached key 'A'
[PASS] Mapped cache should compute and transform value for key 'C'
[PASS] Evaluator should be called once for key 'C'
[PASS] Original cache should return untransformed value
[PASS] Evaluator should not be called again
Running: testResetFunction
[PASS] Cache should return Initial-A for key 'A'
[PASS] Initial evaluator called once
[PASS] After reset, cache should return New-A
[PASS] New evaluator called once after reset
[PASS] New evaluator should compute New-B
[PASS] New evaluator called for key 'B'
[PASS] After reset without clear, cached 'A' should still return New-A
[PASS] Evaluator not called again for cached 'A'
Running: testEdgeCases
[PASS] Cache should return Value-null for null key
[PASS] Evaluator called once for null key
[PASS] Cache should hit for null key
[PASS] Evaluator not called again for null key
[PASS] Evaluator called for object key
[PASS] Evaluator not called again for same object key
[PASS] After first reset, returns Reset1-A
[PASS] Evaluator called once after first reset
[PASS] After second reset, returns Reset2-A
[PASS] Evaluator called once after second reset
Running: testNullValueEvaluator
[PASS] Evaluator returned null, get should return null
[PASS] Evaluator should be called once for 'A'
[PASS] Cached null should be returned on hit
[PASS] [CRITICAL-1] Evaluator must NOT be called again for cached null value
[PASS] All three null-value keys should be cached, no extra evaluator calls
Running: testUndefinedValueEvaluator
[PASS] Evaluator called once for 'X'
[PASS] [CRITICAL-1] Evaluator must NOT be called again for cached undefined value
Running: testCapacityInvariantLazyCache
  LazyCache: T1=50 T2=0 B1=0 B2=0
[PASS] [HIGH-2] |T1|+|T2|=50 should be <= capacity 50
[PASS] [HIGH-2] total=50 should be <= 2*capacity 100
Running: testGhostHitRoundTrip
[PASS] Evaluator should be called for ghost-hit key 'A'
[PASS] Recomputed value should be 'v5-A'
[PASS] After ghost-hit refill, 'A' should be cached — evaluator not called again
[PASS] Cached value should still be 'v5-A'
Running: testPutGetInteraction
[PASS] Manual put value should be returned, not evaluator result
[PASS] Evaluator should NOT be called for manually put key
[PASS] Manual put should override evaluator value
[PASS] Evaluator should not be called again after manual put
Running: testEvaluatorExceptionOnMiss
[PASS] Evaluator called once for 'A'
[PASS] [SAFE-1/MISS] Exception should propagate to caller
[PASS] Evaluator was called for 'B' before throwing
[PASS] [SAFE-1/MISS] Failed key 'B' should NOT be in cache
[PASS] [SAFE-1/MISS] Pre-existing key 'A' should be unaffected
[PASS] [SAFE-1/MISS] Retry key 'B' should succeed after error cleared
[PASS] Evaluator count: A(1) + B_throw(2) + A_hit(skip) + B_retry(3) = 3
Running: testEvaluatorExceptionOnGhostHit
[PASS] [SAFE-1/GHOST] Exception should propagate to caller
[PASS] Evaluator was called for ghost 'A' before throwing
[PASS] [SAFE-1/GHOST] Zombie key 'A' should NOT be in cache (has=false)
[PASS] [SAFE-1/GHOST] Retry ghost-failed key 'A' should recompute correctly
[PASS] Evaluator called again for 'A' (complete miss after zombie cleanup)
[PASS] Recomputed 'A' should now be cached
[PASS] No extra evaluator call for cached 'A'
Running: testHasViaLazyCache
[PASS] has() on empty cache should be false
[PASS] has() should NOT trigger evaluator
[PASS] has() after get should be true
[PASS] has() should NOT call evaluator again
[PASS] has() for uncached key should be false
[PASS] has() must NOT trigger evaluator for uncached key
[PASS] has() after manual put should be true
[PASS] has() after remove should be false
Running: testRawKeyLazyCache
[PASS] Number key 42 should work via lazy cache
[PASS] Evaluator called once for Number 42
[PASS] Number key 42 should hit cache
[PASS] Evaluator not called again for cached Number 42
[PASS] [Known] String '42' should hit same entry as Number 42
[PASS] Evaluator not called for '42' (collision with 42)
Running: testPerformance
[PASS] Evaluator should be called 1000 times to fill cache
Performance: 10000 cache hits took 40ms
[PASS] 10000 cache hits should complete in under 200ms (actual: 40ms)
=== ARCEnhancedLazyCacheTest v3.0: 86 assertions, 86 passed, 0 failed ===


```
