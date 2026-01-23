### `SingleLevelTimeWheel` 类中文文档

---

#### 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| v1.7 | 2026-01 | addTimerByID/removeTimerByID/removeTimerByNode 统一通过 acquireNode/releaseNode 操作节点池，正确支持节点池提供者委托 |
| v1.5 | 2026-01 | 新增节点池提供者注入功能，支持多时间轮共享统一节点池 |
| v1.2 | 2026-01 | 修复 trimNodePool 引用释放问题，新增 acquireNode/releaseNode 方法 |
| v1.0 | - | 初始版本 |

---

#### 目录

1. **概述**
   - 时间轮技术简介
   - 时间轮的优势
   - 单层时间轮的特点
2. **实现细节**
   - 类结构概览
   - 成员变量说明
   - 方法详解
3. **参数规范**
   - 构造函数参数
   - 方法参数与返回值
4. **优化手段**
   - 节点池管理
   - 节点池提供者模式（v1.5）
   - 循环展开技术
   - 取模运算优化
   - 懒加载与预初始化
5. **使用方法**
   - 初始化时间轮
   - 共享节点池模式（v1.5）
   - 添加定时任务
   - 移除定时任务
   - 重新调度定时任务
   - 执行定时任务
6. **实践建议**
   - 适用场景
   - 性能优势分析
   - 注意事项
7. **总结**

---

### 1. 概述

#### **时间轮技术简介**

时间轮（Time Wheel）是一种高效的定时任务调度数据结构，广泛应用于需要大量定时任务管理的系统中。它通过将时间分片（slot），将定时任务映射到对应的时间片上，以循环的方式执行任务。

#### **时间轮的优势**

- **常数级性能**：时间轮在添加、移除和执行任务时，复杂度均为 O(1)，即常数时间。这在需要处理大量定时任务的情况下，性能优势明显。
- **资源占用低**：相比于基于最小堆的定时器，时间轮的内存占用和CPU消耗更低。
- **易于实现**：时间轮的逻辑相对简单，易于理解和实现，且便于扩展。

#### **单层时间轮的特点**

`SingleLevelTimeWheel` 实现了单层时间轮的结构，适用于定时范围在一定范围内的场景（例如，0 到 `wheelSize - 1` 的时间步长）。它的特点包括：

- **简单高效**：单层结构避免了多层时间轮的复杂性，适合于延迟范围可控的应用。
- **易于维护**：代码结构清晰，模块化设计，便于维护和扩展。
- **性能优化**：通过多种优化手段，进一步提升了时间轮的执行效率。

---

### 2. 实现细节

#### **类结构概览**

`SingleLevelTimeWheel` 类主要由以下部分组成：

- **成员变量**：用于存储时间轮的核心数据结构和辅助工具，如槽位数组、当前指针、节点池等。
- **核心方法**：实现添加、移除、重新调度定时任务，以及时间轮的推进（`tick`）操作。
- **辅助方法**：提供状态查询、节点池管理等功能，支持时间轮的高效运行。

#### **成员变量说明**

1. **slots:Array**
   - **作用**：存储时间轮的槽位，每个槽位包含一个 `TaskIDLinkedList` 链表，用于存放在该时间步需要执行的任务。
   - **类型**：`Array`

2. **currentPointer:Number**
   - **作用**：当前时间指针，指示当前执行的时间步。
   - **类型**：`Number`

3. **wheelSize:Number**
   - **作用**：时间轮的总大小，即槽位的数量。
   - **类型**：`Number`

4. **nodePool:Array**
   - **作用**：节点池，存储可重用的 `TaskIDNode` 节点，减少频繁的内存分配和垃圾回收。
   - **类型**：`Array`

5. **nodePoolTop:Number**
   - **作用**：节点池的堆栈顶指针，指示下一个可用节点的位置。
   - **类型**：`Number`

6. **_nodePoolProvider:SingleLevelTimeWheel** `[NEW v1.5]`
   - **作用**：外部节点池提供者引用。如果设置了该引用，所有节点池操作将委托给提供者，用于实现多时间轮共享统一节点池。
   - **类型**：`SingleLevelTimeWheel`
   - **默认值**：`null`（表示使用自己的节点池）

#### **方法详解**

**1. 构造函数**

```actionscript
public function SingleLevelTimeWheel(wheelSize:Number, nodePoolProvider:SingleLevelTimeWheel)
```

- **功能**：初始化时间轮和节点池。
- **参数**：
  - `wheelSize:Number`：时间轮的大小，即槽位的总数。
  - `nodePoolProvider:SingleLevelTimeWheel` `[NEW v1.5]`：可选的外部节点池提供者。如果传入非 null 值，则本时间轮不创建自己的节点池，所有节点操作委托给提供者。
- **实现细节**：
  - 初始化 `slots` 数组，每个槽位初始为 `null`。
  - `[NEW v1.5]` 如果传入了 `nodePoolProvider`，则设置 `_nodePoolProvider` 引用，不创建本地节点池（`nodePool = null`），所有节点操作将委托给提供者。
  - 如果未传入 `nodePoolProvider`（或传入 `null`），则预分配节点池的大小为 `wheelSize * 5`，并使用循环展开技术初始化节点池，提升初始化效率。
  - 设置 `nodePoolTop` 指向节点池的末尾。

**2. addTimerByID**

```actionscript
public function addTimerByID(taskID:String, delay:Number):TaskIDNode
```

- **功能**：根据任务ID和延迟时间添加定时任务到时间轮。
- **参数**：
  - `taskID:String`：任务的唯一标识符。
  - `delay:Number`：延迟的时间步数。
- **返回值**：`TaskIDNode`，添加到时间轮中的节点。
- **实现细节**：
  - `[UPDATE v1.7]` 通过 `acquireNode(taskID)` 获取节点（正确委托给节点池提供者）。
  - 规范化延迟时间，确保计算出的槽位索引非负且在时间轮范围内。
  - 将节点添加到对应槽位的链表中，并记录槽位索引。

**3. removeTimerByID**

```actionscript
public function removeTimerByID(taskID:String):Void
```

- **功能**：根据任务ID从时间轮中移除定时任务。
- **参数**：
  - `taskID:String`：要移除的任务的唯一标识符。
- **实现细节**：
  - 遍历所有槽位，查找匹配的任务节点。
  - 从槽位链表中移除节点。
  - `[UPDATE v1.7]` 通过 `releaseNode(node)` 回收节点（正确委托给节点池提供者）。

**4. addTimerByNode**

```actionscript
public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode
```

- **功能**：通过已有节点直接添加定时任务到时间轮。
- **参数**：
  - `node:TaskIDNode`：已分配的任务节点。
  - `delay:Number`：延迟的时间步数。
- **返回值**：`TaskIDNode`，添加到时间轮中的节点（同传入节点）。
- **实现细节**：
  - 规范化延迟时间，计算目标槽位索引。
  - 将节点添加到对应槽位的链表中，并设置 `ownerType = 1`。
  - 与 `addTimerByID` 不同，此方法不从节点池获取节点，适用于调用方已通过 `acquireNode()` 获取节点的场景。

**5. removeTimerByNode**

```actionscript
public function removeTimerByNode(node:TaskIDNode):Void
```

- **功能**：通过节点引用直接从时间轮中移除定时任务。
- **参数**：
  - `node:TaskIDNode`：要移除的任务节点。
- **实现细节**：
  - 根据节点的 `slotIndex` 定位到对应槽位链表。
  - 从链表中移除节点。
  - `[UPDATE v1.7]` 通过 `releaseNode(node)` 回收节点（正确委托给节点池提供者）。
  - 相比 `removeTimerByID` 的 O(n) 遍历查找，此方法为 O(1)。

**6. rescheduleTimerByID**

```actionscript
public function rescheduleTimerByID(taskID:String, newDelay:Number):Void
```

- **功能**：重新调度指定任务ID的定时任务。
- **参数**：
  - `taskID:String`：要重新调度的任务的唯一标识符。
  - `newDelay:Number`：新的延迟时间步数。
- **实现细节**：
  - 查找任务节点。
  - 计算新的槽位索引。
  - 如果槽位发生变化，将节点从旧槽位移除，添加到新槽位。

**7. tick**

```actionscript
public function tick():TaskIDLinkedList
```

- **功能**：推进时间轮的当前指针，获取当前槽位的任务。
- **返回值**：`TaskIDLinkedList`，当前槽位的任务链表。
- **实现细节**：
  - 获取并清空当前槽位的任务。
  - 前移 `currentPointer`，循环回绕。

---

### 3. 参数规范

#### **构造函数参数**

- **wheelSize:Number**
  - **含义**：时间轮的大小，即槽位的数量。
  - **取值范围**：正整数，建议根据任务的最大延迟时间和精度需求选择。

- **nodePoolProvider:SingleLevelTimeWheel** `[NEW v1.5]`
  - **含义**：外部节点池提供者。传入后，本时间轮将委托所有节点池操作给提供者。
  - **取值范围**：`null`（使用自己的节点池）或另一个 `SingleLevelTimeWheel` 实例（共享其节点池）。
  - **使用场景**：在 CerberusScheduler 中，二级和三级时间轮可以共享单层时间轮的节点池，避免节点池不均衡问题。

#### **方法参数与返回值**

1. **addTimerByID**
   - **taskID:String**
     - 唯一标识任务的字符串，不可重复。
   - **delay:Number**
     - 延迟的时间步数，可以是正数、零或负数。
   - **返回值**：`TaskIDNode`，表示添加到时间轮中的任务节点。

2. **removeTimerByID**
   - **taskID:String**
     - 要移除的任务ID。

3. **rescheduleTimerByID**
   - **taskID:String**
     - 要重新调度的任务ID。
   - **newDelay:Number**
     - 新的延迟时间步数。

4. **tick**
   - **无参数**
   - **返回值**：`TaskIDLinkedList`，当前槽位的任务列表。

---

### 4. 优化手段

#### **1. 节点池管理**

- **目的**：减少频繁的内存分配和垃圾回收，提高系统性能。
- **实现**：
  - 预先分配一定数量的 `TaskIDNode` 节点，存放在 `nodePool` 中。
  - 在添加任务时，从 `nodePool` 中获取节点；在移除任务时，将节点回收到 `nodePool`。

#### **2. 节点池提供者模式（v1.5）**

- **目的**：解决多时间轮场景下节点池不均衡的问题。
- **问题背景**：
  - 在 CerberusScheduler 等多级时间轮架构中，如果每个时间轮维护独立的节点池，会出现以下问题：
    - 单层时间轮的节点池可能膨胀后被裁剪
    - 二级、三级时间轮的节点池永远为空，每次获取节点都触发 `new TaskIDNode()`
    - 增加不必要的 GC 压力
- **解决方案**：
  - 引入 `_nodePoolProvider` 字段，允许时间轮委托节点池操作给外部提供者
  - 所有节点池方法（`acquireNode`、`releaseNode`、`fillNodePool`、`trimNodePool`、`getNodePoolSize`）在有提供者时自动委托
- **优势**：
  - 统一节点池管理，消除不均衡问题
  - 减少内存碎片和 GC 压力
  - 简化节点生命周期管理

#### **4. 循环展开技术**

- **目的**：减少循环控制的开销，提升批量处理效率。
- **应用场景**：
  - 初始化节点池时，采用循环展开，将循环体内的操作重复多次，减少循环次数。

#### **5. 取模运算优化**

- **目的**：确保延迟时间规范化，同时减少取模运算次数。
- **实现**：
  - 使用公式 `((delay % wheelSize) + wheelSize) % wheelSize` 确保延迟为非负数。
  - 在计算槽位索引时，将取模运算合并，减少计算步骤。

#### **6. 懒加载与预初始化**

- **懒加载**：
  - 仅在需要时才初始化槽位的链表，节省内存开销。
- **预初始化**：
  - 在任务较多的情况下，可以预先初始化所有槽位，避免在添加任务时初始化槽位带来的性能开销。

---

### 5. 使用方法

#### **1. 初始化时间轮**

```actionscript
var wheelSize:Number = 30; // 根据需求选择合适的槽位数量
var timeWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(wheelSize, null);
```

- **注意**：`wheelSize` 的选择应考虑最大延迟时间和任务分布。
- `[UPDATE v1.5]` 构造函数现在接受第二个参数 `nodePoolProvider`，传入 `null` 表示使用独立节点池。

#### **2. 共享节点池模式（v1.5）**

在多级时间轮架构中，可以让多个时间轮共享同一个节点池：

```actionscript
// 创建主时间轮（拥有节点池）
var primaryWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(150, null);

// 创建从属时间轮（共享主时间轮的节点池）
var secondaryWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(60, primaryWheel);
var tertiaryWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(60, primaryWheel);

// 所有时间轮现在共享同一个节点池
trace(primaryWheel.getNodePoolSize());   // 输出节点池大小
trace(secondaryWheel.getNodePoolSize()); // 输出相同的值
trace(tertiaryWheel.getNodePoolSize());  // 输出相同的值

// 从任意时间轮获取/回收节点都操作同一个池
var node:TaskIDNode = secondaryWheel.acquireNode("task1");
tertiaryWheel.releaseNode(node); // 可以通过其他时间轮回收
```

**典型应用场景（CerberusScheduler）：**

```actionscript
// 单层时间轮持有节点池
this.singleLevelTimeWheel = new SingleLevelTimeWheel(singleWheelSize, null);

// 二级、三级时间轮委托给单层时间轮
this.secondLevelTimeWheel = new SingleLevelTimeWheel(secondWheelSize, this.singleLevelTimeWheel);
this.thirdLevelTimeWheel = new SingleLevelTimeWheel(thirdWheelSize, this.singleLevelTimeWheel);
```

#### **3. 添加定时任务**

- **通过任务ID添加**

```actionscript
var taskID:String = "task1";
var delay:Number = 10; // 延迟10个时间步
timeWheel.addTimerByID(taskID, delay);
```

- **通过节点添加**

```actionscript
var node:TaskIDNode = new TaskIDNode("task2");
timeWheel.addTimerByNode(node, 5); // 延迟5个时间步
```

#### **4. 移除定时任务**

- **通过任务ID移除**

```actionscript
timeWheel.removeTimerByID("task1");
```

- **通过节点移除**

```actionscript
timeWheel.removeTimerByNode(node);
```

#### **5. 重新调度定时任务**

- **通过任务ID重新调度**

```actionscript
timeWheel.rescheduleTimerByID("task1", 15); // 新的延迟为15个时间步
```

- **通过节点重新调度**

```actionscript
timeWheel.rescheduleTimerByNode(node, 20); // 新的延迟为20个时间步
```

#### **6. 执行定时任务**

```actionscript
var tasks:TaskIDLinkedList = timeWheel.tick();
// 遍历并执行任务
var currentNode:TaskIDNode = tasks.getFirst();
while (currentNode != null) {
    // 执行任务逻辑
    // ...

    currentNode = currentNode.next;
}
```

- **说明**：`tick` 方法应在固定的时间间隔调用，例如在主循环或定时器中。

---

### 6. 实践建议

#### **适用场景**

- **游戏开发**：技能冷却、Buff持续时间、定时触发事件等。
- **服务器开发**：会话超时、定时任务调度、资源管理等。
- **实时系统**：需要高效处理大量定时任务的任何场景。

#### **性能优势分析**

- **常数级复杂度**：添加、移除、执行任务的时间复杂度均为 $O(1)$。
- **内存效率高**：节点池的使用减少了内存分配次数，降低了垃圾回收的频率。
- **CPU开销低**：优化的取模运算和循环展开技术减少了CPU的计算负担。

#### **注意事项**

- **任务延迟范围**：由于是单层时间轮，延迟时间超过 `wheelSize` 的任务会循环回绕，需要确保 `wheelSize` 足够大以满足最大延迟需求。
- **线程安全性**：该实现未考虑线程安全，若在多线程环境中使用，需要添加同步机制。
- **节点池管理**：合理设置节点池大小，避免频繁扩容或节点不足。
- **节点池提供者模式（v1.5）**：
  - 使用共享节点池时，确保提供者的生命周期覆盖所有从属时间轮
  - 从属时间轮的 `nodePool` 为 `null`，直接操作会导致错误
  - 所有节点池操作都会自动委托，无需手动处理
- **节点池一致性（v1.7）**：
  - `addTimerByID`、`removeTimerByID`、`removeTimerByNode` 均已统一通过 `acquireNode()`/`releaseNode()` 操作节点池
  - 修复了 v1.5 引入共享节点池后，上述方法仍直接访问本地 `nodePool` 数组导致的不一致问题
  - 升级后，从属时间轮的所有增删操作都能正确委托给节点池提供者

---

### 7. 总结

`SingleLevelTimeWheel` 类提供了一个高效、简洁的定时任务调度方案，适用于需要管理大量定时任务的系统。通过精心设计的数据结构和优化手段，实现了常数级的性能表现。在使用过程中，结合具体应用场景，合理设置参数和优化策略，可以充分发挥时间轮的优势。





// ============================================
// 测试启动示例
// ============================================

// 创建 SingleLevelTimeWheelTest 实例
var timeWheelTester:org.flashNight.neur.TimeWheel.SingleLevelTimeWheelTest = new org.flashNight.neur.TimeWheel.SingleLevelTimeWheelTest();

// 方式1: 一键运行所有测试（推荐）
timeWheelTester.runAllTests();

// 方式2: 分别运行各类测试
// timeWheelTester.runFunctionTests();      // 功能测试
// timeWheelTester.runPerformanceTests();   // 性能测试
// timeWheelTester.runFixV12Tests();        // FIX v1.2 验证测试
// timeWheelTester.runFixV15Tests();        // FIX v1.5 节点池提供者验证测试

╔════════════════════════════════════════╗
║  SingleLevelTimeWheel 完整测试套件     ║
╚════════════════════════════════════════╝

=== Running Functional Tests ===
PASS: addTimerByID places task2 at correct slot
PASS: addTimerByID places task1 at correct slot
PASS: addTimerByNode places task3 at correct slot
PASS: removeTimerByID correctly removes task2
PASS: removeTimerByNode correctly removes task1
PASS: rescheduleTimerByID correctly moves task1
PASS: rescheduleTimerByNode correctly moves task2
PASS: tick retrieves tasks at current pointer
PASS: tick retrieves tasks at next pointer
PASS: getTimeWheelStatus returns correct currentPointer
PASS: getTimeWheelStatus returns correct wheelSize
PASS: getTimeWheelStatus returns correct taskCounts
PASS: getTimeWheelData returns correct currentPointer
PASS: getTimeWheelData returns correct wheelSize
PASS: fillNodePool correctly increases node pool size
PASS: trimNodePool correctly trims node pool size
PASS: removeTimerByID handles non-existent task gracefully
PASS: rescheduleTimerByID handles non-existent task gracefully
PASS: addTimerByID with negative delay wraps around correctly
PASS: addTimerByID with large delay wraps around correctly
PASS: tick wraps around wheel correctly after multiple overflows
=== Functional Tests Completed ===

=== Running Performance Tests ===
Add Timer Performance: 89 ms for 10,000 adds (loop unrolled by 4)
Remove Timer Performance: 3029 ms for 5,000 removals (loop unrolled by 4)
Tick Performance: 12 ms for 10,000 ticks (loop unrolled by 4)
fillNodePool Performance: 38 ms for filling 10,000 nodes (loop unrolled by 4)
trimNodePool Performance: 5 ms for trimming to 1,000 nodes (loop unrolled by 4)
=== Performance Tests Completed ===

=== Running Practical Task Combinations Test ===
PASS: Practical Task Combination: taskE placed at slot 0
PASS: Practical Task Combination: taskA placed at slot 5
PASS: Practical Task Combination: taskB placed at slot 10
PASS: Practical Task Combination: taskC placed at slot 15
PASS: Practical Task Combination: taskD and taskF placed at slot 25
PASS: Practical Task Combination: taskA removed from slot 5
PASS: Practical Task Combination: taskB removed from slot 10
PASS: Practical Task Combination: taskA and taskB placed at slot 20
PASS: Practical Task Combination: taskD and taskF remain at slot 25
=== Practical Task Combinations Test Completed ===

=== Running FIX v1.2 Verification Tests ===
PASS: [FIX v1.2] fillNodePool correctly fills pool
PASS: [FIX v1.2] trimNodePool correctly reduces pool size to 10
PASS: [FIX v1.2] Pool can be refilled after trim, size = 30
[FIX v1.2] trimNodePool reference release test completed
PASS: [FIX v1.2] acquireNode reduces pool size by 1
PASS: [FIX v1.2] acquireNode correctly initializes taskID
PASS: [FIX v1.2] releaseNode restores pool size
[FIX v1.2] Node recycling test completed
=== FIX v1.2 Verification Tests Completed ===

=== Running FIX v1.5 Verification Tests (Node Pool Provider) ===
PASS: [NEW v1.5] Provider wheel has its own node pool
PASS: [NEW v1.5] Delegate wheel reports same pool size as provider
[NEW v1.5] Node pool provider creation test completed
PASS: [NEW v1.5] acquireNode via delegate returns valid node
PASS: [NEW v1.5] acquireNode via delegate sets correct taskID
PASS: [NEW v1.5] acquireNode via delegate reduces provider's pool size
PASS: [NEW v1.5] Delegate wheel reflects provider's pool size change
[NEW v1.5] acquireNode delegation test completed
PASS: [NEW v1.5] releaseNode via delegate restores provider's pool size
PASS: [NEW v1.5] Delegate wheel reflects provider's pool restoration
[NEW v1.5] releaseNode delegation test completed
PASS: [NEW v1.5] fillNodePool via delegate increases provider's pool size
PASS: [NEW v1.5] Delegate wheel reflects provider's pool increase
[NEW v1.5] fillNodePool delegation test completed
PASS: [NEW v1.5] trimNodePool via delegate reduces provider's pool to target size
PASS: [NEW v1.5] Delegate wheel reflects provider's pool trim
[NEW v1.5] trimNodePool delegation test completed
PASS: [NEW v1.5] Multiple wheels share same pool - 3 nodes acquired
PASS: [NEW v1.5] wheel1 reports correct shared pool size
PASS: [NEW v1.5] wheel2 reports correct shared pool size
PASS: [NEW v1.5] Node acquired via wheel1 can be released via wheel2
PASS: [NEW v1.5] Node acquired via provider can be released via delegate wheel
[NEW v1.5] Multiple wheels sharing provider test completed
PASS: [NEW v1.5] Delegate wheel status reports provider's nodePoolSize
PASS: [NEW v1.5] Delegate wheel status reports its own wheelSize
PASS: [NEW v1.5] Provider wheel status reports its own wheelSize
PASS: [NEW v1.5] After fillNodePool, both report same nodePoolSize
[NEW v1.5] getTimeWheelStatus with provider test completed
=== FIX v1.5 Verification Tests Completed ===

╔════════════════════════════════════════╗
║  所有测试完成                          ║
╚════════════════════════════════════════╝
