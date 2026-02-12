# ARCEnhancedLazyCache v3.1 使用指南

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
| 0 (MISS) | 完全未命中 | `evaluator(key)` → `super._putNew(key, computed)`（OPT-9，省一次 hash 查找） |
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
| — | SAFE-1 | (v3.1 移除) 不再使用 try/catch | 改为契约优先（C8/C9），与项目全局规范对齐 |
| P0 | OPT-9 | MISS 路径 `super._putNew()` | 跳过 nodeMap 存在性检查，省一次 hash 查找 |

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

## 契约与异常安全性

### 契约 C8：evaluator MUST NOT throw

v3.1 移除了 ghost 路径的 try/catch（原 SAFE-1），改为契约优先设计，与项目全局规范（避免异常影响性能）对齐。

**MISS 路径**：evaluator 抛异常时，`super._putNew()` 尚未执行，缓存状态不变。天然安全。

**GHOST 路径**：evaluator 抛异常时，`super.get()` 已将节点移入 T2（value = undefined），形成"僵尸节点"。异常传播给调用者，**僵尸不会自动清除**。

僵尸行为：
- `has(key)` 返回 `true`（节点在 T2 中）
- `get(key)` 返回 `undefined`（僵尸 HIT，不会重新计算）
- 恢复方式：`remove(key)` 后重试

```actionscript
// 如果 evaluator 违反 C8 抛异常后的恢复
cache.remove("problematicKey"); // 清除僵尸
var result = cache.get("problematicKey"); // 重新计算
```

### 契约 C9：evaluator MUST NOT 可重入

evaluator MUST NOT 对**同一缓存实例**调用 `get()`/`put()`/`remove()`。违反将导致 `_lastNode` 被覆盖，产生静默数据损坏（use-after-pool）。

通过 `map()` 链访问**父缓存**是安全的（不同实例，`_lastNode` 独立）。

---

## 注意事项

1. **evaluator MUST NOT 抛异常（C8）**：v3.1 移除了 try/catch 保护。GHOST 路径 evaluator 异常将产生 T2 僵尸节点。恢复方式：`remove(key)` + 重试。

2. **evaluator MUST NOT 可重入（C9）**：evaluator 不得对同一缓存实例调用 `get()`/`put()`/`remove()`。违反将导致静默数据损坏。通过 `map()` 链访问父缓存是安全的。

3. **键语义**：继承 ARCCache v3.0 的原始键语义。Number 与 String 表示相同时会碰撞。详见 ARCCache.md。

4. **null/undefined 返回值**：evaluator 返回 null 或 undefined 是合法的，会被正确缓存。后续 get 命中时返回 null/undefined（不再调用 evaluator）。

5. **GC 与 map 链**：map() 创建的缓存通过闭包持有对父缓存的引用，不会被 GC。多层 map 链需手动管理生命周期。

---

### v3.1 测试覆盖

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
| testGhostHitRoundTrip | ghost hit 回填完整链路（含 _hitType 断言） |
| testPutGetInteraction | put+get 交互（手动值优先） |
| testEvaluatorExceptionOnMiss | MISS 路径异常无副作用 |
| **testEvaluatorExceptionOnGhostHit** | **v3.1 C8 契约验证：僵尸行为 + remove 恢复** |
| testHasViaLazyCache | API-1：has() 不触发 evaluator |
| testRawKeyLazyCache | ARCH-1：原始键语义 |
| **testCapacity1LazyCache** | **v3.1 P2：capacity=1 边界（ghost/pool 密集交互）** |
| testPerformance | 10000 次命中 < 200ms |


## 运行测试

```actionscript

org.flashNight.gesh.func.ARCEnhancedLazyCacheTest.runTests();

```

```

=== ARCEnhancedLazyCacheTest v3.2: Starting Tests ===
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
[PASS] get('A') should be B1 ghost hit (_hitType=2)
[PASS] Evaluator should be called for ghost-hit key 'A'
[PASS] Recomputed value should be 'v5-A'
[PASS] Second get('A') should be HIT (_hitType=1)
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
[PASS] [C8] Exception should propagate to caller
[PASS] [C8] get('A') should be B1 ghost hit (_hitType=2) before evaluator threw
[PASS] Evaluator was called for ghost 'A' before throwing
[PASS] [C8/ZOMBIE] Zombie key 'A' should be in cache (has=true, in T2 with undefined value)
[PASS] [C8/ZOMBIE] Zombie 'A' should be T2 HIT (_hitType=1)
[PASS] [C8/ZOMBIE] Zombie 'A' should return undefined (not recompute)
[PASS] [C8/ZOMBIE] No evaluator call for zombie HIT
[PASS] [C8/RECOVER] After remove, 'A' should not be in cache
[PASS] [C8/RECOVER] After remove+retry, 'A' should be recomputed correctly
[PASS] [C8/RECOVER] Evaluator called again for 'A' after zombie removal
[PASS] Recovered 'A' should now be cached
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
Running: testCapacity1LazyCache
[PASS] c=1: A should be computed
[PASS] c=1: evaluator called once for A
[PASS] c=1: A should be HIT
[PASS] c=1: A should be HIT (_hitType=1)
[PASS] c=1: no extra evaluator call for HIT
[PASS] c=1: B should be computed
[PASS] c=1: evaluator called for B
[PASS] c=1: A should be B2 ghost hit (_hitType=3)
[PASS] c=1: A should be recomputed via ghost hit
[PASS] c=1: evaluator called again for ghost A
[PASS] c=1: A should be HIT after ghost refill
[PASS] c=1: no extra evaluator for cached A
[PASS] c=1: |T1|+|T2|=1 should be <= 1
Running: testRemoveAndGet
[PASS] remove+get: Initial get returns computed value
[PASS] remove+get: Evaluator called once
[PASS] remove+get: Cached value returned
[PASS] remove+get: No extra call on HIT
[PASS] remove+get: After remove, has() returns false
[PASS] remove+get: After remove, evaluator re-called
[PASS] remove+get: Evaluator called again after remove
[PASS] remove+get: Re-cached value returned
[PASS] remove+get: No extra call after re-cache
Running: testPutGhostPath
[PASS] putGhost: 4 evaluator calls after setup
[PASS] putGhost: A should be in cache after put on ghost
[PASS] putGhost: A should be HIT after ghost put
[PASS] putGhost: A should have manual value, not computed
[PASS] putGhost: Evaluator not called for manual put on ghost
[PASS] putGhost: |T1|+|T2|=3 should be <= 3
Running: testResetNullEvaluator
[PASS] resetNull: Evaluator called once for A
[PASS] resetNull: Original evaluator still works after reset(null, true)
[PASS] resetNull: Evaluator called again after cache clear
Running: testCapacity2Boundary
[PASS] c=2: Two evaluator calls
[PASS] c=2: Three evaluator calls
[PASS] c=2: A should be T2 HIT
[PASS] c=2: No extra call for cached A
[PASS] c=2: B should be B1 ghost hit
[PASS] c=2: Evaluator called for ghost B
[PASS] c=2: |T1|+|T2|=2 should be <= 2
[PASS] c=2: total=3 should be <= 2*2=4
Running: testMapParentReset
[PASS] mapReset: Child returns transformed value
[PASS] mapReset: Evaluator called once
[PASS] mapReset: Child cache HIT
[PASS] mapReset: No extra evaluator call
[PASS] mapReset: Child still returns stale cached value after parent reset
[PASS] mapReset: No evaluator call for stale child HIT
[PASS] mapReset: New key through child uses parent's new evaluator
[PASS] mapReset: New evaluator called for B
Running: testClearPoolDrain
[PASS] clearPool: 10 evaluator calls for initial fill
[PASS] clearPool: 10 more evaluator calls after reset
[PASS] clearPool: |T1|+|T2|=10 should be <= 10 after reset+refill
[PASS] clearPool: 15 more evaluator calls after second reset
[PASS] clearPool: capacity invariant holds after multiple reset cycles
Running: testPerformance
[PASS] Evaluator should be called 1000 times to fill cache
Performance: 10000 cache hits took 39ms
[PASS] 10000 cache hits should complete in under 200ms (actual: 39ms)
=== ARCEnhancedLazyCacheTest v3.2: 145 assertions, 145 passed, 0 failed ===

```
