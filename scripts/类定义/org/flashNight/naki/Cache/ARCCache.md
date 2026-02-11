# ARCCache v2.0 使用指南

## 目录

1. [简介](#简介)
2. [算法原理](#算法原理)
3. [实现细节](#实现细节)
   - [数据结构设计](#数据结构设计)
   - [核心方法解析](#核心方法解析)
     - [`get` 方法](#get-方法)
     - [`put` 方法](#put-方法)
     - [`putNoEvict` 方法](#putnoevict-方法)
     - [`remove` 方法](#remove-方法)
4. [v2.0 变更摘要](#v20-变更摘要)
5. [使用指南](#使用指南)
   - [初始化缓存](#初始化缓存)
   - [缓存数据](#缓存数据)
   - [检索数据](#检索数据)
   - [复杂对象键的使用注意事项](#复杂对象键的使用注意事项)
   - [调试与测试](#调试与测试)
6. [优势与局限性](#优势与局限性)
   - [优势](#优势)
   - [局限性](#局限性)
7. [注意事项](#注意事项)
8. [完整代码结构](#完整代码结构)
9. [结语](#结语)

---

## 简介

**ARCCache v2.0** 是一个基于 **自适应替换缓存（Adaptive Replacement Cache，ARC）** 算法（Megiddo & Modha, 2003）的完整实现，旨在提供高效的缓存策略，适应多种访问模式，提高缓存命中率。该实现使用 **ActionScript 2（AS2）**，采用哨兵节点和全内联优化，适用于对性能和资源敏感的环境。

---

## 算法原理

### 什么是 ARC 算法？

ARC 算法是一种高级缓存替换策略，结合了 **LRU（最近最少使用）** 和 **LFU（最不经常使用）** 的优点。它通过动态调整缓存中冷数据和热数据的比例，适应不同的工作负载，提高缓存命中率。

### ARC 的核心概念

- **T1 队列**：存储最近访问但未被频繁使用的数据（冷数据）。
- **T2 队列**：存储被频繁访问的数据（热数据）。
- **B1 队列**：记录从 T1 中被移除的缓存项的 UID（幽灵条目），不存储实际数据。
- **B2 队列**：记录从 T2 中被移除的缓存项的 UID（幽灵条目），不存储实际数据。
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
- **节点结构**：`{ uid: String, prev: Object, next: Object, list: Object, value: * }`
  - 值直接存储在节点上（v2.0 消除了独立的 `cacheStore` 哈希表）
  - 幽灵节点的 `value` 为 `undefined`
- **节点映射（`nodeMap`）**：将 UID 映射到对应的链表节点，方便快速访问和更新。
- **命中类型（`_hitType`）**：`get()` 后设置，供子类判断命中情况（0=MISS, 1=HIT, 2=GHOST_B1, 3=GHOST_B2）。

### 核心方法解析

#### `get` 方法

**功能**：根据给定的键从缓存中检索数据，并根据 ARC 算法调整缓存结构。

**实现步骤**：

1. **生成 UID**：根据键生成唯一标识符 UID。对于对象类型的键，使用 `Dictionary.getStaticUID()` 获取唯一的引用 ID；对于基本类型的键，将其转换为字符串。

2. **查找节点**：在 `nodeMap` 中查找对应的节点。

3. **判断所在队列**：
   - **在 T1 中**：
     - 从 T1 中移除节点。
     - 将节点添加到 T2 的头部。
     - 更新节点的列表引用为 T2。
     - 返回缓存的值。
   - **在 T2 中**：
     - 将节点移至 T2 的头部。
     - 返回缓存的值。
   - **在 B1 中（幽灵命中）**：
     - 增大 `p` 的值，倾向于增加 T1 的容量。
     - 根据 ARC 策略，从 T1 或 T2 中移除尾部节点，移至对应的幽灵队列。
     - 将命中的节点从 B1 移至 T2 的头部。
     - 返回 `null`，因为幽灵队列中不存储实际值。
   - **在 B2 中（幽灵命中）**：
     - 减小 `p` 的值，倾向于增加 T2 的容量。
     - 根据 ARC 策略，从 T1 或 T2 中移除尾部节点，移至对应的幽灵队列。
     - 将命中的节点从 B2 移至 T2 的头部。
     - 返回 `null`。
   - **不在任何队列中**：
     - 返回 `null`。

#### `put` 方法

**功能**：将数据插入缓存，并根据 ARC 算法进行必要的替换和调整。

**实现步骤**：

1. **生成 UID**：同 `get` 方法。

2. **检查是否已存在**：
   - **T2 中**：更新值，移到 T2 头部。
   - **T1 中**：更新值，从 T1 移除并添加到 T2 头部。
   - **B1 中**（v2.0 CRITICAL-2 fix）：执行标准 ARC 的 p 自适应（增大）、REPLACE 淘汰、从 B1 移除并带值添加到 T2。
   - **B2 中**（v2.0 CRITICAL-2 fix）：执行标准 ARC 的 p 自适应（减小）、REPLACE 淘汰、从 B2 移除并带值添加到 T2。

3. **完全新 key（标准 ARC Case IV）**：
   - **Case A**（|L1| == c）：如果 |T1| < c，删除 B1 尾部最老幽灵 + REPLACE；否则（|T1| == c）直接从 T1 删除（不进 B1）。
   - **Case B**（|L1| < c）：如果总量 ≥ 2c，删除 B2 尾部最老幽灵；如果缓存已满则 REPLACE。
   - 创建新节点插入 T1 头部。

4. **队列不变式**（所有操作维护）：
   - `0 <= |T1|+|T2| <= c`
   - `0 <= |T1|+|B1| <= c` (L1)
   - `0 <= |T1|+|T2|+|B1|+|B2| <= 2c` (总量)
   - `0 <= p <= c`

#### `putNoEvict` 方法

**功能**：不触发淘汰的 put — 专为子类（如 ARCEnhancedLazyCache）在幽灵命中后存储计算值设计。

**v2.0 修复**：
- 不再调用 `this.get()`（消除虚调用导致的无限递归风险）
- 所有 promote 逻辑全部内联
- 正确处理 B1/B2 节点（先断链再插入 T1）

#### `remove` 方法

**功能**：从缓存中移除一个项目（包括幽灵队列中的记录）。哨兵节点使断链无需分支。返回 true/false 表示是否成功。

---

## v2.0 变更摘要

### 正确性修复

| 优先级 | 编号 | 问题 | 修复 |
|--------|------|------|------|
| P0 | CRITICAL-1 | `putNoEvict` 通过 `this.get()` 虚调用子类重写 → 无限递归/栈溢出 | 全内联 promote 逻辑，不再调用 `this.get()` |
| P0 | CRITICAL-2 | `put()` 对 B1/B2 中的 key 创建孤儿节点 → 数据损坏 | `put()` 正确处理 B1/B2 幽灵命中（p 自适应 + REPLACE + 移入 T2） |
| P0 | HIGH-1 | B2 ghost hit + T1 空时跳过淘汰 → 永久超容量 | `_doReplace` 增加 `|T1|>0` 前置守卫 |
| P0 | HIGH-2 | `ARCEnhancedLazyCache` 对完全未命中使用 `putNoEvict` → 无界增长 | 新增 `_hitType` 字段区分 MISS/GHOST/HIT，MISS 走 `put()` |

### 性能优化

| 编号 | 优化 | 效果 |
|------|------|------|
| OPT-1 | 值存储在 `node.value` 上，消除 `cacheStore` 哈希表 | 每次操作少一次哈希查找 |
| OPT-2 | put/putNoEvict 更新路径全部内联 | 消除虚调用开销 |
| OPT-3 | T2 head 快速路径 | 头部命中跳过 remove+addToHead |
| sentinel | 哨兵节点 | 消除所有 head/tail null 分支 |

### 算法对齐（标准 ARC）

- **p 自适应**：`delta = max(1, |B_other|/|B_self|)` 替代 ±1
- **Case IV 幽灵清理**：标准 L1/L2 不变式替代 `B1+B2 <= 2c`
- **REPLACE 条件**：严格遵循论文公式，含 `isB2Hit` 参数

---

## 使用指南

### 初始化缓存

```actionscript
import org.flashNight.naki.Cache.ARCCache;

// 创建一个容量为 100 的缓存实例
var cache:ARCCache = new ARCCache(100);
```

### 缓存数据

```actionscript
// 缓存简单键值对
cache.put("username", "Alice");

// 缓存复杂对象键
var user:Object = { id: 123, name: "Bob" };
cache.put(user, "User Data");
```

### 检索数据

```actionscript
// 检索简单键
var username:String = cache.get("username");
if (username != null) {
    trace("Username: " + username);
} else {
    trace("Username not found in cache.");
}

// 检索复杂对象键
var userData:String = cache.get(user);
if (userData != null) {
    trace("User Data: " + userData);
} else {
    trace("User Data not found in cache.");
}
```

### 复杂对象键的使用注意事项

**重要提示**：

- **UID 基于对象引用**：在缓存中，对象键的 UID 是基于对象的引用地址，而不是对象的内容。这意味着：

  - 如果使用临时创建的对象作为键，即使内容相同，缓存也无法命中。
  - 为了保证缓存命中率，**应尽可能重用同一个对象实例**，而不是在每次访问时创建新的对象。

**示例**：

```actionscript
// 错误用法：每次创建新的对象，缓存无法命中
var tempUser:Object = { id: 123, name: "Bob" };
var data:String = cache.get(tempUser); // 始终返回 null

// 正确用法：重用对象实例
var user:Object = { id: 123, name: "Bob" };
cache.put(user, "User Data");
var data:String = cache.get(user); // 成功命中缓存
```

### 调试与测试

**查看缓存内部状态**：

```actionscript
// 查看四个队列的 UID 列表（从头到尾）
trace("T1 Queue: " + cache.getT1());
trace("T2 Queue: " + cache.getT2());
trace("B1 Queue: " + cache.getB1());
trace("B2 Queue: " + cache.getB2());

// 获取容量
trace("Capacity: " + cache.getCapacity());
```

> **v2.0 变更**：`_getCacheContents()` 和 `_getNodeMapContents()` 已移除。值现在直接存储在节点上，无独立的 `cacheStore`。

---

## 优势与局限性

### 优势

1. **高缓存命中率**：ARC 算法能自适应调整缓存策略，适应不同的访问模式，提高命中率。

2. **自适应能力强**：无需手动调整参数，算法根据访问模式自动调整 `p` 值。

3. **性能优化**：通过局部化变量、合并操作等方式，降低了解引用和堆栈操作的开销，提升性能。

4. **支持复杂键类型**：能够缓存以对象、函数等复杂类型作为键的数据。

### 局限性

1. **对象键的 UID 基于引用**：需要注意对象键的使用方式，避免因为对象实例不同导致缓存未命中。

2. **代码可读性降低**：为性能优化，代码牺牲了一定的可读性，理解起来可能较为复杂。

3. **内存占用**：四个队列（T1、T2、B1、B2）和节点映射会占用一定的内存空间。

4. **仅适用于 AS2**：该实现基于 AS2，不适用于现代的 ActionScript 版本或其他语言环境。

---

## 注意事项

1. **对象键的正确使用**：当使用对象作为键时，确保在整个应用中重用同一个对象实例。

2. **缓存容量的合理设置**：根据实际需求设置 `maxCapacity`，避免过小导致频繁缓存替换，过大导致内存浪费。

3. **调试方法的使用**：`getT1()`、`getT2()` 等方法仅用于调试，不建议在生产环境中频繁调用。

4. **理解算法机制**：在深入使用该缓存之前，建议详细理解 ARC 算法的机制，以便更好地利用其优势。

---

## 完整代码结构

**ARCCache.as** 文件包含以下主要部分：

1. **成员变量**：`maxCapacity`、`p`、`_hitType`、四个队列（T1/T2/B1/B2）、`nodeMap`。

2. **构造函数**：初始化缓存容量、哨兵节点和各队列。

3. **内部工具**：`_createQueue()`（创建带哨兵的空队列）、`_clear()`（重置所有状态）、`_doReplace()`（标准 ARC REPLACE 淘汰）。

4. **`get` 方法**：检索数据，设置 `_hitType`，处理 T1/T2 命中和 B1/B2 幽灵命中。

5. **`put` 方法**：插入数据，处理 T1/T2 更新、B1/B2 幽灵命中、标准 Case IV 新 key 插入。

6. **`putNoEvict` 方法**：不触发淘汰的写入，全内联逻辑（不走虚调用）。

7. **`remove` 方法**：从任意队列中移除项目。

8. **调试方法**：`getT1()`、`getT2()`、`getB1()`、`getB2()`、`getCapacity()`。

---

## 结语

**ARCCache** 提供了一种高效的缓存解决方案，适用于需要在 AS2 环境下优化缓存性能的应用程序。通过理解其实现原理和使用注意事项，开发者可以充分利用其优势，提高应用的性能和响应速度。

在使用过程中，请务必注意对象键的特殊性，以及缓存容量的合理设置。希望本指南能帮助您更好地理解和使用 **ARCCache**。

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
=== ARCCacheTest v2.0: Starting Tests ===
Running testPutAndGet...
Assertion Passed: Value for key1 should be 'value1'
Assertion Passed: Value for key2 should be 'value2'
Assertion Passed: Value for key3 should be 'value3'
testPutAndGet completed successfully.

Running testCacheEviction...
=== Cache State at After inserting keyExtra ===
T1: _keyExtra,_key100,_key99,_key98,_key97,_key96,_key95,_key94,_key93,_key92,_key91,_key90,_key89,_key88,_key87,_key86,_key85,_key84,_key83,_key82,_key81,_key80,_key79,_key78,_key77,_key76,_key75,_key74,_key73,_key72,_key71,_key70,_key69,_key68,_key67,_key66,_key65,_key64,_key63,_key62,_key61,_key60,_key59,_key58,_key57,_key56,_key55,_key54,_key53,_key52,_key51,_key50,_key49,_key48,_key47,_key46,_key45,_key44,_key43,_key42,_key41,_key40,_key39,_key38,_key37,_key36,_key35,_key34,_key33,_key32,_key31,_key30,_key29,_key28,_key27,_key26,_key25,_key24,_key23,_key22,_key21,_key20,_key19,_key18,_key17,_key16,_key15,_key14,_key13,_key12,_key11,_key10,_key9,_key8,_key7,_key6,_key5,_key3
T2: _key4,_key2
B1: _key1
B2: 
==============================
Assertion Passed: Value for key1 should be null (evicted)
Assertion Passed: Value for keyExtra should be 'valueExtra'
testCacheEviction completed successfully.

Running testCacheHitRate...
Cache Hit Rate: 51.5%
Assertion Passed: Cache hit rate should be between 0% and 100%
testCacheHitRate completed successfully.

Running testPerformance...
Performed 10000 cache operations in 104 ms.
Cache Operations per Second: 96153.8461538461

Assertion Passed: Operations per second should be greater than 0
testPerformance completed successfully.

Running testEdgeCases...
Assertion Passed: Value for null key should be 'nullKeyValue'
Assertion Passed: Value for undefined key should be 'undefKeyValue'
Assertion Passed: Value for 'key@#' should be 'value@#'
Assertion Passed: Value for empty string key should be 'emptyKey'
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
Assertion Passed: A should be ghost (in B1)
Assertion Passed: After put on ghost key, A should be accessible with new value
Assertion Passed: Cache size 3 within capacity
Assertion Passed: No orphan '_A' in B1
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

=== ARCCacheTest v2.0: All Tests Completed ===


```