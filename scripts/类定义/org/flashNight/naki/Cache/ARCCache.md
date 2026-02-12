# ARCCache v3.1 使用指南

## 目录

1. [简介](#简介)
2. [算法原理](#算法原理)
3. [实现细节](#实现细节)
   - [数据结构设计](#数据结构设计)
   - [核心方法解析](#核心方法解析)
4. [v3.0 变更摘要](#v30-变更摘要)
5. [使用指南](#使用指南)
   - [初始化缓存](#初始化缓存)
   - [缓存数据](#缓存数据)
   - [检索数据](#检索数据)
   - [键的使用规范](#键的使用规范)
   - [存在性检查](#存在性检查)
   - [调试与测试](#调试与测试)
6. [优势与局限性](#优势与局限性)
7. [注意事项](#注意事项)
8. [完整代码结构](#完整代码结构)
9. [结语](#结语)

---

## 简介

**ARCCache v3.0** 是一个基于 **自适应替换缓存（Adaptive Replacement Cache，ARC）** 算法（Megiddo & Modha, 2003）的完整实现，旨在提供高效的缓存策略，适应多种访问模式，提高缓存命中率。该实现使用 **ActionScript 2（AS2）**，采用哨兵节点、原始键语义、节点池化等优化，适用于对性能和资源敏感的环境。

---

## 算法原理

### 什么是 ARC 算法？

ARC 算法是一种高级缓存替换策略，结合了 **LRU（最近最少使用）** 和 **LFU（最不经常使用）** 的优点。它通过动态调整缓存中冷数据和热数据的比例，适应不同的工作负载，提高缓存命中率。

### ARC 的核心概念

- **T1 队列**：存储最近访问但未被频繁使用的数据（冷数据）。
- **T2 队列**：存储被频繁访问的数据（热数据）。
- **B1 队列**：记录从 T1 中被移除的缓存项的键（幽灵条目），不存储实际数据。
- **B2 队列**：记录从 T2 中被移除的缓存项的键（幽灵条目），不存储实际数据。
- **平衡参数 `p`**：控制 T1 和 T2 队列的大小，根据访问模式动态调整。

### 工作原理

- **缓存命中**：
  - **在 T1 中命中**：将该项移至 T2 队列，提升其优先级。
  - **在 T2 中命中**：将该项移至 T2 队列的头部，保持其高优先级。
- **缓存未命中**：
  - **在 B1 中命中（幽灵命中）**：意味着最近重新访问了被移除的冷数据，增大 `p` 的值，扩大 T1 的容量。
  - **在 B2 中命中（幽灵命中）**：意味着最近重新访问了被移除的热数据，减小 `p` 的值，扩大 T2 的容量。
  - **不在任何队列中**：需要将新项插入缓存，根据当前的 `p` 值和队列大小决定从 T1 或 T2 中移除旧的缓存项。

---

## 实现细节

### 数据结构设计

- **缓存队列**：使用带**哨兵节点**的循环双向链表实现 T1、T2、B1、B2 队列。哨兵节点消除了所有 head/tail 的 null 分支检查。
  - 队列结构：`{ sentinel: Object, size: Number }`
  - 空队列：`sentinel.prev = sentinel.next = sentinel`
  - head = `sentinel.next`，tail = `sentinel.prev`
- **节点结构**：`{ uid: *, prev: Object, next: Object, list: Object, value: * }`
  - `uid` 为调用者传入的原始 key（v3.0 不做任何转换）
  - 值直接存储在节点上（v2.0 消除了独立的 `cacheStore` 哈希表）
  - 幽灵节点的 `value` 为 `undefined`
- **节点映射（`nodeMap`）**：将 key 直接映射到对应的链表节点。
  - v3.0：`nodeMap.__proto__ = null` 断开原型链（ARCH-2），避免 `Object.prototype` 上的属性冲突
- **节点池（`_pool`）**：v3.0 新增。被释放的节点通过 `.next` 串成单链表，新建节点优先从池中取（OPT-6），减少 GC 压力
- **命中类型（`_hitType`）**：`get()` 后设置，供子类判断命中情况：
  - `0` = 完全未命中 (MISS)
  - `1` = 缓存命中 (HIT，T1/T2)
  - `2` = 幽灵命中 B1 (GHOST_B1)
  - `3` = 幽灵命中 B2 (GHOST_B2)

### 核心方法解析

#### `get` 方法

**功能**：根据给定的键从缓存中检索数据，并根据 ARC 算法调整缓存结构。

**实现步骤**：

1. **查找节点**：在 `nodeMap` 中以原始 key 查找对应节点。
2. **判断所在队列**：
   - **T2 中命中**（最热路径，优先判断）：移至 T2 头部，返回值。
   - **T1 中命中**：从 T1 移除并添加到 T2 头部，返回值。
   - **B1 中幽灵命中**：调整 p（增大），在 cache 满时执行 REPLACE（ROBUST-2），移入 T2，设置 `_lastNode`，返回 `null`。
   - **B2 中幽灵命中**：调整 p（减小），在 cache 满时执行 REPLACE（ROBUST-2），移入 T2，设置 `_lastNode`，返回 `null`。
   - **不在任何队列中**：返回 `null`。

#### `put` 方法

**功能**：将数据插入缓存，并根据 ARC 算法进行必要的替换和调整。

**实现步骤**：

1. **检查是否已存在**：
   - **T2 中**：更新值，移到 T2 头部。
   - **T1 中**：更新值，从 T1 移除并添加到 T2 头部。
   - **B1 中**：执行标准 ARC 的 p 自适应（增大）、满时 REPLACE、从 B1 移除并带值添加到 T2。
   - **B2 中**：执行标准 ARC 的 p 自适应（减小）、满时 REPLACE、从 B2 移除并带值添加到 T2。

2. **完全新 key（标准 ARC Case IV）**：
   - **Case A**（|L1| == c）：如果 |T1| < c，删除 B1 尾部最老幽灵（入池）+ REPLACE；否则（|T1| == c）直接从 T1 删除（入池，不进 B1）。
   - **Case B**（|L1| < c）：如果总量 >= 2c，删除 B2 尾部最老幽灵（入池）；如果缓存满则 REPLACE。
   - 从池分配或新建节点，插入 T1 头部。

3. **队列不变式**（所有操作维护）：
   - `0 <= |T1|+|T2| <= c`
   - `0 <= |T1|+|B1| <= c` (L1)
   - `0 <= |T1|+|T2|+|B1|+|B2| <= 2c` (总量)
   - `0 <= p <= c`

#### `putNoEvict` 方法

**功能**：不触发淘汰的 put — 专为子类（如 ARCEnhancedLazyCache）在幽灵命中后存储计算值设计。

- T1/T2 中：更新值 + 正常 promote
- B1/B2 中：断链后插入 T1（不执行 p 自适应，不享受 T2 热端优先级）
- 新 key：从池分配或新建，直接插入 T1（不淘汰）

#### `remove` 方法

**功能**：从缓存中移除一个项目（包括幽灵队列中的记录）。哨兵节点使断链无需分支。移除的节点进入对象池（OPT-6）。返回 `true`/`false` 表示是否成功。

#### `has` 方法 (v3.0 新增)

**功能**：检查 key 是否在缓存中持有值（T1 或 T2），不触发任何状态变更。不影响 LRU 排序、不修改 `_hitType` 或 `_lastNode`。

```actionscript
if (cache.has("myKey")) {
    // key 在 T1 或 T2 中
}
```

---

## v3.0 变更摘要

### 架构变更

| 优先级 | 编号 | 变更 | 效果 |
|--------|------|------|------|
| P0 | ARCH-1 | 移除内部 UID 生成（typeof + "_" 前缀 + Dictionary.getStaticUID） | 消除热路径字符串拼接与类型分支，key 直接用作 nodeMap 属性名 |
| P0 | ARCH-2 | `nodeMap.__proto__ = null` | 断开原型链，避免 Object.prototype 属性冲突 |

### 健壮性增强

| 优先级 | 编号 | 变更 | 效果 |
|--------|------|------|------|
| P2 | ROBUST-1 | `_doReplace` 空队列回退 | 若首选队列为空则回退到另一队列，防止 remove() 打乱 ARC 状态后 REPLACE 空转 |
| P2 | ROBUST-2 | ghost hit 路径增加 `|T1|+|T2| >= c` 前置守卫 | cache 未满时（remove 导致）跳过 REPLACE，避免不必要的淘汰 |
| P3 | VALID-1 | 构造函数校验 `capacity >= 1` | 无效容量自动校正为 1 |

### 性能优化

| 编号 | 优化 | 效果 |
|------|------|------|
| OPT-6 | 节点池化（free list） | ghost 清理 / remove 时节点进池，新建时出池，减少 GC 压力 |
| OPT-7 | `== undefined` → `=== undefined` | 消除 ActionEquals2 类型协商，使用 ActionStrictEquals |
| OPT-8 | `_clear()` 重用哨兵节点 | 避免 8 次对象分配 |

### API 新增

| 优先级 | 编号 | API | 说明 |
|--------|------|-----|------|
| P4 | API-1 | `has(key):Boolean` | 不变更状态的存在性检查（仅 T1/T2） |

### v3.1 增量优化（交叉评审）

| 优先级 | 编号 | 变更 | 效果 |
|--------|------|------|------|
| P0 | OPT-9 | 新增 `_putNew(key, value)` | 纯新 key 快速插入，跳过 nodeMap 存在性检查。供 LazyCache MISS 路径使用 |
| P1 | OPT-10 | 入池仅清 `value` | uid/prev/list 在复用时覆盖，省 3 次赋值/次入池 |

### 保留自 v2.0 的优化

- OPT-1: 值直存节点（消除 `cacheStore` 哈希表）
- OPT-2: put/putNoEvict 更新路径全部内联
- OPT-3: T2 head 快速路径
- OPT-4: 链表局部变量缓存
- OPT-5: `_lastNode` ghost 直赋
- 哨兵节点消除所有 head/tail null 分支

### 保留自 v2.0 的正确性修复

- CRITICAL-1: `putNoEvict` 全内联，消除虚调用递归
- CRITICAL-2: `put()` 正确处理 B1/B2 幽灵命中
- HIGH-1: `_doReplace` 增加 T1 非空守卫
- HIGH-2: `_hitType` 区分 MISS/GHOST/HIT

### 算法对齐（标准 ARC）

- **p 自适应**：`delta = max(1, |B_other|/|B_self|)` 替代 ±1
- **Case IV 幽灵清理**：标准 L1/L2 不变式
- **REPLACE 条件**：严格遵循论文公式，含 `isB2Hit` 参数

---

## 使用指南

### 初始化缓存

```actionscript
import org.flashNight.naki.Cache.ARCCache;

// 创建一个容量为 100 的缓存实例
var cache:ARCCache = new ARCCache(100);

// 容量至少为 1（无效值自动校正）
var cache2:ARCCache = new ARCCache(0);  // 实际容量 = 1
```

### 缓存数据

```actionscript
// 缓存简单键值对
cache.put("username", "Alice");

// Number 键（AS2 自动转为 "123" 做属性名）
cache.put(123, "numericKey");
```

### 检索数据

```actionscript
// 检索简单键
var username = cache.get("username");
if (cache._hitType === 1) {
    trace("Hit: " + username);
} else {
    trace("Miss");
}
```

### 键的使用规范

> **v3.0 重要变更**：ARCCache 不再对 key 做任何转换，直接将 key 用作 `nodeMap` 属性名。

**规范**：

1. **推荐使用 String 或 Number 键**：这是最高性能的路径。
2. **类型碰撞**：AS2 将非字符串键自动转为字符串做属性名，因此 `Number 123` 与 `String "123"` 会碰撞到同一条目。如果业务中存在这种情况，调用者应手动加前缀区分。
3. **对象键**：不推荐直接使用对象作为 key（`toString()` 默认返回 `"[object Object]"`）。如需对象键，应先用 `Dictionary.getStaticUID(obj)` 转为唯一字符串再传入。
4. **禁止使用 `"__proto__"` 作为键**：这是 AS2 保留属性，`nodeMap.__proto__ = null` 已占用。
5. **禁止使用空字符串 `""` 作为键**：AS2 AVM1 中 `obj[""]` 在 `__proto__=null` 模式下行为未定义，put/get 可能失败。

**示例**：

```actionscript
// 正确：Number 键
cache.put(42, "answer");
var val = cache.get(42); // "answer"

// 注意：Number 与 String 碰撞
cache.put(42, "fromNumber");
cache.put("42", "fromString"); // 覆盖上面的值
cache.get(42); // "fromString"（last write wins）

// 对象键的正确用法
import org.flashNight.naki.DataStructures.Dictionary;
var obj:Object = { id: 1 };
var uid:String = Dictionary.getStaticUID(obj);
cache.put(uid, "objectData");
```

### 存在性检查

```actionscript
// v3.0 新增：has() 不触发状态变更
if (cache.has("username")) {
    // key 在 T1 或 T2 中（有值）
    var val = cache.get("username"); // 安全取值
}

// has() 不检查幽灵队列（B1/B2），不调用 evaluator
// has() 不影响 _hitType、_lastNode、LRU 排序
```

### 调试与测试

**查看缓存内部状态**：

```actionscript
// 查看四个队列的 key 列表（从头到尾）
trace("T1 Queue: " + cache.getT1());
trace("T2 Queue: " + cache.getT2());
trace("B1 Queue: " + cache.getB1());
trace("B2 Queue: " + cache.getB2());

// 获取容量
trace("Capacity: " + cache.getCapacity());
```

> **注意**：`getT1()` 等方法会遍历链表生成数组，仅用于调试，不建议在生产环境频繁调用。

---

## 优势与局限性

### 优势

1. **高缓存命中率**：ARC 算法能自适应调整缓存策略，适应不同的访问模式。
2. **自适应能力强**：无需手动调整参数，算法根据访问模式自动调整 `p` 值。
3. **极致性能**：原始键语义消除热路径字符串拼接；节点池化减少 GC；全内联消除虚调用。
4. **健壮性**：`_doReplace` 空队列回退 + ghost hit REPLACE 守卫，防止 `remove()` 打乱 ARC 不变式。
5. **GC 友好**：节点池化（free list）避免频繁分配/释放，降低 AS2 VM 的 GC 压力。

### 局限性

1. **键类型碰撞**：Number 与 String 表示相同时会碰撞（AS2 属性名为字符串）。调用者需自行处理。
2. **对象键需外部转换**：对象不能直接用作 key，需先转为唯一字符串。
3. **代码可读性**：为性能优化，大量逻辑内联，代码较为密集。
4. **仅适用于 AS2**：该实现基于 AS2，不适用于现代 ActionScript 版本或其他语言环境。

---

## 注意事项

1. **键类型一致性**：如果同一逻辑 key 可能以不同类型传入（如 Number 42 和 String "42"），需调用者保证类型一致或手动加前缀区分。
2. **缓存容量的合理设置**：根据实际需求设置容量，避免过小导致频繁替换，过大导致内存浪费。容量至少为 1。
3. **`__proto__` 键不可用**：这是 AS2 保留属性，已被 ARCH-2 占用。
4. **理解算法机制**：在深入使用该缓存之前，建议详细理解 ARC 算法的机制，以便更好地利用其优势。
5. **`_hitType` 和 `_lastNode`**：这些字段为 `public` 是因为 AS2 没有 `protected`。它们是内部 API，供子类（ARCEnhancedLazyCache）使用，外部代码不应依赖。

---

## 完整代码结构

**ARCCache.as** 文件包含以下主要部分：

1. **成员变量**：`maxCapacity`、`p`、`_hitType`、`_lastNode`、`_pool`、四个队列（T1/T2/B1/B2）、`nodeMap`。

2. **构造函数**：初始化缓存容量（VALID-1 校验）、哨兵节点、各队列、`nodeMap.__proto__ = null`。

3. **内部工具**：
   - `_createQueue()` — 创建带哨兵的空队列
   - `_clear()` — 重置所有状态（重用哨兵，OPT-8）
   - `_doReplace()` — 标准 ARC REPLACE 淘汰 + 空队列回退（ROBUST-1）

4. **`get` 方法**：检索数据，设置 `_hitType`/`_lastNode`，处理 T2/T1 命中和 B1/B2 幽灵命中（含 ROBUST-2 守卫）。

5. **`put` 方法**：插入数据，处理 T1/T2 更新、B1/B2 幽灵命中（含 ROBUST-2 守卫）、标准 Case IV 新 key 插入（含节点池化）。

6. **`putNoEvict` 方法**：不触发淘汰的写入，全内联逻辑。注：B1/B2 分支在当前 LazyCache 中为死代码（ghost hit 走 OPT-5）。

7. **`_putNew` 方法**（v3.1 新增）：纯新 key 快速插入，跳过 nodeMap 存在性检查，直接执行 Case IV 逻辑。调用者 MUST 保证 key 不在 nodeMap 中。

8. **`remove` 方法**：从任意队列移除项目，节点入池（OPT-10 仅清 value）。

9. **`has` 方法**（v3.0 新增）：不变更状态的存在性检查。

10. **调试方法**：`getT1()`、`getT2()`、`getB1()`、`getB2()`、`getCapacity()`。

---

## 结语

**ARCCache v3.1** 在 v3.0 基础上新增 `_putNew()` 快速插入方法（OPT-9，省 MISS 路径一次 hash 查找）和入池精简（OPT-10，省 3 次赋值/次入池）。这些变更来自 Claude/GPT 交叉评审的 P0-P1 建议。

---

### 运行测试

```actionscript
// ARCCache 基础测试
var cacheTest = new org.flashNight.naki.Cache.ARCCacheTest(100);
cacheTest.runTests();

// ARCEnhancedLazyCache 测试
org.flashNight.gesh.func.ARCEnhancedLazyCacheTest.runTests();
```

```

=== ARCCacheTest v3.1: Starting Tests ===
Running testPutAndGet...
Assertion Passed: Value for key1 should be 'value1'
Assertion Passed: Value for key2 should be 'value2'
Assertion Passed: Value for key3 should be 'value3'
testPutAndGet completed successfully.

Running testCacheEviction...
=== Cache State at After inserting keyExtra ===
T1: keyExtra,key100,key99,key98,key97,key96,key95,key94,key93,key92,key91,key90,key89,key88,key87,key86,key85,key84,key83,key82,key81,key80,key79,key78,key77,key76,key75,key74,key73,key72,key71,key70,key69,key68,key67,key66,key65,key64,key63,key62,key61,key60,key59,key58,key57,key56,key55,key54,key53,key52,key51,key50,key49,key48,key47,key46,key45,key44,key43,key42,key41,key40,key39,key38,key37,key36,key35,key34,key33,key32,key31,key30,key29,key28,key27,key26,key25,key24,key23,key22,key21,key20,key19,key18,key17,key16,key15,key14,key13,key12,key11,key10,key9,key8,key7,key6,key5,key3
T2: key4,key2
B1: key1
B2: 
==============================
Assertion Passed: Value for key1 should be null (evicted)
Assertion Passed: Value for keyExtra should be 'valueExtra'
testCacheEviction completed successfully.

Running testCacheHitRate...
Cache Hit Rate: 47.9%
Assertion Passed: Cache hit rate should be between 0% and 100%
testCacheHitRate completed successfully.

Running testPerformance...
Performed 10000 cache operations in 107 ms.
Cache Operations per Second: 93457.9439252336

Assertion Passed: Operations per second should be greater than 0
testPerformance completed successfully.

Running testEdgeCases...
Assertion Passed: Value for null key should be 'nullKeyValue'
Assertion Passed: Value for undefined key should be 'undefKeyValue'
Assertion Passed: Value for 'key@#' should be 'value@#'
Assertion Passed: Value for 'nonEmpty' key should be 'nonEmptyValue'
Assertion Passed: Value for numeric key 123 should be 'numericKey'
Assertion Passed: Cached null value should be returned as null (not trigger miss)
testEdgeCases completed successfully.

Running testHighFrequencyAccess...
Assertion Passed: High-frequency key hfKey1 should still be present
Assertion Passed: High-frequency key hfKey2 should still be present
Assertion Passed: High-frequency key hfKey3 should still be present
testHighFrequencyAccess completed successfully.

Running testDuplicateKeys...
Assertion Passed: Initial value for 'dupKey' should be 'initialValue'
Assertion Passed: Updated value for 'dupKey' should be 'updatedValue'
Assertion Passed: Value for 'dupKey' should still be 'updatedValue'
testDuplicateKeys completed successfully.

Running testLargeScaleCache...
Assertion Passed: Frequently accessed 'largeKey1' should still be present
Assertion Passed: Frequently accessed 'largeKey2' should still be present
Assertion Passed: Frequently accessed 'largeKey3' should still be present
Assertion Passed: Frequently accessed 'largeKey4' should still be present
Assertion Passed: Frequently accessed 'largeKey5' should still be present
Assertion Passed: Frequently accessed 'largeKey6' should still be present
Assertion Passed: Frequently accessed 'largeKey7' should still be present
Assertion Passed: Frequently accessed 'largeKey8' should still be present
Assertion Passed: Frequently accessed 'largeKey9' should still be present
Assertion Passed: Frequently accessed 'largeKey10' should still be present
testLargeScaleCache completed successfully.

Running testPutOnGhostKey...
Assertion Passed: A should be in B1 ghost queue before put
Assertion Passed: After put on ghost key, A should be accessible with new value
Assertion Passed: Cache size 3 within capacity
Assertion Passed: No orphan 'A' in B1 after put on ghost key
testPutOnGhostKey completed successfully.

Running testB2HitWithEmptyT1...
Assertion Passed: Cache size 3 within capacity after B2 hit with empty T1
testB2HitWithEmptyT1 completed successfully.

Running testCapacityInvariant...
  T1=50 T2=0 B1=0 B2=0
Assertion Passed: |T1|+|T2|=50 <= capacity 50
Assertion Passed: total=50 <= 2*capacity 100
testCapacityInvariant completed successfully.

Running testCapacityInvariantMixed...
  Mixed: T1=15 T2=15 B1=15 B2=0
Assertion Passed: |T1|+|T2|=30 <= capacity 30
Assertion Passed: total=45 <= 2c=60
Assertion Passed: L1=|T1|+|B1|=30 <= c=30
Assertion Passed: Ghost queues non-empty (B1+B2=15), mixed pattern exercised
testCapacityInvariantMixed completed successfully.

Running testRemoveFromAllQueues...
Assertion Passed: remove from T1 should return true
Assertion Passed: X should be gone after remove
Assertion Passed: remove from T2 should return true
Assertion Passed: Y should be gone after remove from T2
Assertion Passed: remove from B1 ghost should return true
Assertion Passed: After remove from B1, Q should be complete MISS (hitType=0)
Assertion Passed: remove from B2 ghost should return true
Assertion Passed: After remove from B2, M should be complete MISS (hitType=0)
Assertion Passed: remove non-existent key should return false
testRemoveFromAllQueues completed successfully.

Running testHasAPI...
Assertion Passed: has() on empty cache should be false
Assertion Passed: has() for T1 entry should be true
Assertion Passed: has() for T2 entry should be true
Assertion Passed: has() after remove should be false
Assertion Passed: has() for non-existent key should be false
Assertion Passed: has() should not modify _hitType
testHasAPI completed successfully.

Running testCapacity1Edge...
Assertion Passed: c=1: A should be retrievable
Assertion Passed: c=1: B should be retrievable
Assertion Passed: c=1: A should be GHOST_B2 after T2 eviction
Assertion Passed: c=1: C in T2 should be retrievable
Assertion Passed: c=1: D should be retrievable
Assertion Passed: c=1, |T1|+|T2|=1 <= 1
testCapacity1Edge completed successfully.

Running testRemoveThenGhostHit...
Assertion Passed: B should be ghost hit (B1)
Assertion Passed: D should survive (no unnecessary REPLACE)
Assertion Passed: A should survive (no unnecessary REPLACE)
Assertion Passed: |T1|+|T2|=3 <= 3 (ROBUST-2 working)
testRemoveThenGhostHit completed successfully.

Running testNodePoolReuse...
  Pool: T1=10 T2=0 B1=0 B2=0
Assertion Passed: pool reuse, |T1|+|T2|=10 <= 10
Assertion Passed: pool reuse, total=10 <= 20
Assertion Passed: Last inserted key via pool reuse should have correct value
testNodePoolReuse completed successfully.

Running testRawKeySemantics...
Assertion Passed: Number key 42 should work
Assertion Passed: Boolean key true should work
Assertion Passed: [Known] Number 99 and String '99' collide — last write wins
Assertion Passed: getT1() should return raw key 'hello' (no prefix)
Assertion Passed: capacity=0 should be corrected to 1
Assertion Passed: capacity=-5 should be corrected to 1
testRawKeySemantics completed successfully.

Running testPutOnB2GhostKey...
Assertion Passed: A should be in B2 ghost queue before put
Assertion Passed: After put on B2 ghost key, A should be accessible with new value
Assertion Passed: Cache size 3 within capacity after B2 ghost put
Assertion Passed: No orphan 'A' in B2 after put on B2 ghost key
testPutOnB2GhostKey completed successfully.

=== ARCCacheTest v3.1: All Tests Completed ===


```