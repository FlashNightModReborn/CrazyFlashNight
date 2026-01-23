import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.TimeWheel.*;
/*
# CerberusScheduler（地狱三头犬调度器）使用说明


## 概述

**CerberusScheduler** 是一个高级的定时任务调度器，利用多级时间轮和最小堆的数据结构，实现对不同延迟和精度要求的任务进行高效管理。它能够处理从即时执行到远期执行的各种任务，满足高性能和高精度的任务调度需求，适用于需要大量定时任务和精确计时的应用场景。

---

## 设计思想

### 多级时间轮

为了高效管理不同延迟的任务，CerberusScheduler 采用了三层时间轮结构，每一层时间轮负责不同范围的任务调度：

1. **单层时间轮（Single-Level Time Wheel）**：
   - **用途**：处理短期任务（例如 0-149 帧的任务）。
   - **特点**：精度高，无时间偏差，适用于需要快速响应的任务。
   - **实现细节**：基于数组的循环队列，每个槽位对应一个帧。

2. **第二级时间轮（Second-Level Time Wheel）**：
   - **用途**：处理中期任务（以秒为单位的任务）。
   - **特点**：降低了任务管理的复杂度，将帧数转换为秒数进行调度。
   - **实现细节**：每个槽位代表一秒，使用计数器推进时间。

3. **第三级时间轮（Third-Level Time Wheel）**：
   - **用途**：处理长期任务（以分钟为单位的任务）。
   - **特点**：进一步降低了长期任务的管理开销，将秒数转换为分钟数进行调度。
   - **实现细节**：每个槽位代表一分钟，通过二级计数器推进时间。

### 最小堆（Min Heap）

- **用途**：处理超出时间轮范围或精度要求高的任务。
- **特点**：能够精确地管理任务的执行时间，适用于无法满足精度要求的任务。
- **实现细节**：基于二叉堆的数据结构，按照任务的执行时间进行排序。

### 任务哈希表（v1.4 已废弃）

- **状态**：已在 v1.4 中废弃，任务 ID 管理完全由 TaskManager 负责。
- **原用途**：通过任务 ID 快速查找、删除和重新调度任务。
- **废弃原因**：TaskManager 已维护 taskTable[taskID] → Task 映射，CerberusScheduler 再维护一层是冗余的。
- **迁移指南**：使用 TaskManager.getTask(taskID) 代替 CerberusScheduler.findTaskInTable(taskID)。

---

## 实现细节

### 属性详解

#### 时间轮相关属性

- **singleLevelTimeWheel**：`SingleLevelTimeWheel` 类型的实例，表示单层时间轮，用于处理短期任务。

- **secondLevelTimeWheel**：`SingleLevelTimeWheel` 类型的实例，表示第二级时间轮，用于处理中期任务。

- **thirdLevelTimeWheel**：`SingleLevelTimeWheel` 类型的实例，表示第三级时间轮，用于处理长期任务。

- **multiLevelCounter**：多级时间轮的第一级计数器，用于控制第二级时间轮的推进。

- **multiLevelCounterLimit**：多级时间轮第一级计数器的上限，一般设置为每秒帧数。

- **secondLevelCounter**：多级时间轮的第二级计数器，用于控制第三级时间轮的推进。

- **secondLevelCounterLimit**：多级时间轮第二级计数器的上限，一般设置为第二级时间轮的大小（秒数）。

#### 最小堆相关属性

- **minHeap**：`FrameTaskMinHeap` 类型的实例，用于管理超出时间轮范围或精度要求高的任务。

#### 帧率和时间计算相关属性

- **framesPerSecond**：每秒帧数，决定了时间轮的粒度和任务延迟的计算。

- **firstWhileSecond**：单层时间轮的范围（秒），用于确定任务应插入的时间轮。

- **singleWheelMaxFrames**：单层时间轮的最大帧数，等于 `singleWheelSize`。

- **secondLevelMaxSeconds**：第二级时间轮的最大秒数，等于 `multiLevelSecondsSize`。

- **thirdLevelMaxMinutes**：第三级时间轮的最大分钟数，等于 `multiLevelMinutesSize`。

#### 精度控制相关属性

- **precisionThreshold**（v1.7 废弃）：原精度阈值参数，已不再影响路由决策。保留参数签名以维持 API 兼容性。

#### Never-Early 路由参数（v1.7 新增）

- **_thirdTickPeriod**：三级时间轮的 tick 周期（帧数），等于 `secondLevelCounterLimit * multiLevelCounterLimit`。用于 `evaluateAndInsertTask` 的 never-early 公式，避免热路径重复乘法。

#### 任务管理相关属性

- **taskTable**（v1.4 废弃）：原用于存储任务 ID 与任务节点的映射，现已迁移至 TaskManager。

### 方法详解

#### 初始化方法

```actionscript
public function initialize(singleWheelSize:Number, 
                           multiLevelSecondsSize:Number, 
                           multiLevelMinutesSize:Number, 
                           framesPerSecond:Number, 
                           precisionThreshold:Number)
```

- **功能**：初始化调度器，配置各个时间轮和相关参数。

- **参数**：

  - `singleWheelSize`（Number）：单层时间轮的大小（帧数），决定了可处理的最短延迟范围。默认值为 150。

  - `multiLevelSecondsSize`（Number）：第二级时间轮的大小（秒数），决定了中期任务的时间范围。默认值为 60。

  - `multiLevelMinutesSize`（Number）：第三级时间轮的大小（分钟数），决定了长期任务的时间范围。默认值为 60。

  - `framesPerSecond`（Number）：每秒帧数（FPS），影响时间轮的推进速度和延迟计算。默认值为 30。

  - `precisionThreshold`（Number）：[DEPRECATED v1.7] 精度阈值参数已废弃，不再影响路由决策。保留以维持 API 兼容性。

- **实现细节**：

  - 初始化各级时间轮的实例，设置计数器和计数器上限。

  - 计算时间轮的范围和最大值，用于后续任务评估。

  - 初始化最小堆和任务哈希表，为任务管理做好准备。

#### 任务评估与插入

```actionscript
public function evaluateAndInsertTask(taskID:String, delayInFrames:Number):TaskIDNode
```

- **功能**：根据任务的延迟时间评估其应插入的时间轮或最小堆。

- **参数**：

  - `taskID`（String）：任务的唯一标识符。

  - `delayInFrames`（Number）：任务的延迟时间（帧）。

- **返回值**：`TaskIDNode`，表示插入的任务节点。

- **实现细节**：

  `[UPDATE v1.7]` 路由算法已从"精度阈值"模式改为 **Never-Early（绝不提前）** 模式。
  不再评估精度损失，而是使用 `ceil` 公式保证任务绝不会提前触发（允许延后）。

  1. **检查单层时间轮**（短路径，无除法）：

     - 如果 `delayInFrames < singleWheelMaxFrames`，直接插入单层时间轮（帧精度，零误差）。

  2. **检查第二级时间轮**（Never-Early ceil 公式）：

     - `delaySlot2 = ceil((delayInFrames + multiLevelCounter) / multiLevelCounterLimit)`
     - 如果 `delaySlot2 <= secondLevelMaxSeconds`，插入第二级时间轮。
     - 保证：实际触发帧 = `delaySlot2 * counterLimit - counter >= delayInFrames`。

  3. **检查第三级时间轮**（Never-Early 两级偏移公式）：

     - `thirdLevelOffset = secondLevelCounter * counterLimit + counter`
     - `delaySlot3 = ceil((delayInFrames + thirdLevelOffset) / _thirdTickPeriod)`
     - 如果 `delaySlot3 <= thirdLevelMaxMinutes`，插入第三级时间轮。
     - 保证：实际触发帧 >= `delayInFrames`。

  4. **使用最小堆**：

     - 超出所有时间轮范围的任务，插入最小堆（帧精度，O(log n)）。

  **注意**：`precisionThreshold` 参数已废弃（v1.7），保留签名仅为 API 兼容性。

#### 时间推进与任务执行

```actionscript
public function tick():TaskIDLinkedList
```

- **功能**：推进时间轮，提取到期需要执行的任务。

- **返回值**：`TaskIDLinkedList`，包含到期任务的链表。

- **实现细节**：

  1. **推进单层时间轮**：

     - 调用 `singleLevelTimeWheel.tick()`，获取当前帧的到期任务。

     - 将到期任务添加到结果列表。

  2. **推进最小堆**：

     - 调用 `minHeap.tick()`，获取到期的高精度任务。

     - 将到期任务合并到结果列表。

  3. **推进多级时间轮**：

     - 增加 `multiLevelCounter`，当其达到 `multiLevelCounterLimit` 时，重置计数器并推进第二级时间轮。

     - 增加 `secondLevelCounter`，当其达到 `secondLevelCounterLimit` 时，重置计数器并推进第三级时间轮。

     - 在每次推进第三级时间轮时，调用 `manageNodePools()` 方法管理节点池。

  4. **清理任务哈希表**：

     - 对于已执行的任务，从 `taskTable` 中移除，释放内存。

#### 节点池管理

```actionscript
private function manageNodePools():Void
```

- **功能**：管理各级时间轮和最小堆的节点池，优化内存使用。

- **实现细节**：

  - 定义 `minThreshold` 和 `maxThreshold`，控制节点池的最小和最大容量。

  - 检查每个数据结构的节点池大小，决定是填充还是缩减节点池。

  - 调用各数据结构的 `fillNodePool` 或 `trimNodePool` 方法进行节点池管理。

#### 任务管理方法

- **删除任务**：

  ```actionscript
  public function removeTaskByID(taskID:String):Void
  ```

  - **功能**：通过任务 ID 删除任务。

  - **实现细节**：

    - 从 `taskTable` 中获取任务节点。

    - 调用 `removeTaskByNode` 方法删除任务节点。

- **重新调度任务**：

  ```actionscript
  public function rescheduleTaskByID(taskID:String, newDelayInFrames:Number):Void
  ```

  - **功能**：通过任务 ID 重新调度任务。

  - **实现细节**：

    - 从 `taskTable` 中获取任务节点。

    - 调用 `rescheduleTaskByNode` 方法重新调度任务节点。

- **通过节点删除任务**：

  ```actionscript
  public function removeTaskByNode(node:TaskIDNode):Void
  ```

  - **功能**：通过任务节点删除任务。

  - **实现细节**：

    - 从任务所在的链表中移除节点。

    - 从 `taskTable` 中移除任务 ID。

- **通过节点重新调度任务**：

  ```actionscript
  public function rescheduleTaskByNode(node:TaskIDNode, newDelayInFrames:Number):Void
  ```

  - **功能**：通过任务节点重新调度任务。

  - **实现细节**：

    - 调用 `removeTaskByNode` 删除任务节点。

    - 调用 `evaluateAndInsertTask` 重新评估并插入任务。

#### 工具方法

- **获取时间轮槽大小**：

  - `getSingleLevelSlotSize()`：获取单层时间轮的槽大小。

  - `getMultiLevelSecondSlotSize()`：获取第二级时间轮的槽大小。

  - `getMultiLevelMinuteSlotSize()`：获取第三级时间轮的槽大小。

- **获取计数器上限**：

  - `getMultiLevelCounterLimit()`：获取多级时间轮第一级计数器的上限。

  - `getSecondLevelCounterLimit()`：获取第二级时间轮计数器的上限。

- **任务哈希表管理**：

  - `addTaskToTable(taskID:String, node:TaskIDNode)`：添加任务到哈希表。

  - `removeTaskFromTable(taskID:String)`：从哈希表中移除任务。

  - `findTaskInTable(taskID:String):TaskIDNode`：从哈希表中查找任务。

---

## 使用示例

### 初始化调度器

```actionscript
// 创建调度器实例
var scheduler:CerberusScheduler = new CerberusScheduler();

// 初始化调度器，使用默认参数
scheduler.initialize(150, 60, 60, 30, 0.1);
```

### 添加任务

```actionscript
// 添加一个延迟 100 帧的任务 "task1"
scheduler.evaluateAndInsertTask("task1", 100);

// 添加一个延迟 2000 帧的任务 "task2"
scheduler.evaluateAndInsertTask("task2", 2000);

// 添加一个延迟 36000 帧的任务 "task3"
scheduler.evaluateAndInsertTask("task3", 36000);
```

### 删除任务

```actionscript
// 删除任务 "task1"
scheduler.removeTaskByID("task1");
```

### 重新调度任务

```actionscript
// 将任务 "task2" 重新调度为延迟 5000 帧
scheduler.rescheduleTaskByID("task2", 5000);
```

### 运行调度器并执行任务

```actionscript
// 在每一帧的循环中调用调度器的 tick 方法
_root.onEnterFrame = function() {
    var tasks:TaskIDLinkedList = scheduler.tick();
    if (tasks != null) {
        var node:TaskIDNode = tasks.getFirst();
        while (node != null) {
            // 在这里执行任务的逻辑，例如调用回调函数等
            trace("Executing task: " + node.taskID + " at frame: " + currentFrame);

            // 移动到下一个任务节点
            node = node.next;
        }
    }

    // 更新当前帧数（假设有一个 currentFrame 变量）
    currentFrame++;
};
```

---

## 测试框架的实现与使用

### 测试框架概述

为了验证 CerberusScheduler 的功能和性能，我们提供了一个测试框架，模拟了各种任务的添加、执行、删除和重新调度。测试框架包括以下内容：

- **任务配置**：定义一系列任务，涵盖不同的延迟范围和精度要求。

- **任务跟踪**：使用 `TextField` 显示当前帧数和任务的执行情况，便于观察。

- **任务删除和重新调度测试**：验证调度器对任务管理操作的正确性。

### 实现步骤

#### 1. 初始化调度器和测试环境

```actionscript
// 创建调度器实例
var scheduler:CerberusScheduler = new CerberusScheduler();
scheduler.initialize(150, 60, 60, 30, 0.1); // 使用默认参数

// 初始化当前帧数和已执行任务计数
var currentFrame:Number = 0;
var executedTasksCount:Number = 0;

// 创建 TextField 显示帧数和任务状态
var frameCountDisplay:TextField = _root.createTextField("frameCountDisplay", _root.getNextHighestDepth(), 10, 10, 700, 800);
// 设置 TextField 属性（边框、背景、颜色等）
```

#### 2. 配置测试任务

```actionscript
// 定义任务配置数组，涵盖不同类型的任务
var tasksConfig:Array = [
    // 单层时间轮任务
    {taskID: "task1", delayInFrames: 10, expectedFrame: 10},
    {taskID: "task2", delayInFrames: 149, expectedFrame: 149},
    // 第二级时间轮任务
    {taskID: "task3", delayInFrames: 150, expectedFrame: 150},
    {taskID: "task4", delayInFrames: 500, expectedFrame: 500},
    // 第三级时间轮任务
    {taskID: "task5", delayInFrames: 36000, expectedFrame: 36000},
    // 最小堆任务
    {taskID: "task6", delayInFrames: 108000, expectedFrame: 108000},
    // 更多任务配置
];
```

#### 3. 添加任务到调度器

```actionscript
function evaluateAndInsertTasks():Void {
    for (var i:Number = 0; i < tasksConfig.length; i++) {
        var task = tasksConfig[i];
        // 添加任务到调度器
        scheduler.evaluateAndInsertTask(task.taskID, task.delayInFrames);
        trace(task.taskID + " inserted with delay " + task.delayInFrames + " frames");
    }
}
```

#### 4. 运行调度器并监控任务执行

```actionscript
_root.onEnterFrame = function() {
    currentFrame++; // 增加当前帧数

    // 调用调度器的 tick 方法
    var tasks:TaskIDLinkedList = scheduler.tick();
    if (tasks != null) {
        var node:TaskIDNode = tasks.getFirst();
        while (node != null) {
            trace("Executing task: " + node.taskID + " at frame: " + currentFrame);
            executedTasksCount++; // 增加已执行任务计数

            // 更新任务状态（如果有任务跟踪表）
            updateActualFrame(node.taskID, currentFrame);

            node = node.next;
        }
    }

    // 在第一帧添加任务
    if (currentFrame == 1) {
        evaluateAndInsertTasks();
    }

    // 根据需要进行任务删除和重新调度测试
    if (currentFrame == 2) {
        deleteTasks();
    }
    if (currentFrame == 3) {
        rescheduleTasks();
    }

    // 显示任务状态
    displayTaskTable();

    // 根据需要停止测试
    if (executedTasksCount >= tasksConfig.length) {
        _root.onEnterFrame = undefined; // 停止测试
        trace("Test completed.");
    }
};
```

#### 5. 执行任务删除和重新调度测试

```actionscript
// 定义需要删除的任务 ID
var deleteTasksConfig:Array = ["task3", "task5"];

// 定义需要重新调度的任务
var rescheduleTasksConfig:Array = [
    {taskID: "task2", newDelayInFrames: 200},
    {taskID: "task6", newDelayInFrames: 50000}
];

// 删除任务函数
function deleteTasks():Void {
    for (var i:Number = 0; i < deleteTasksConfig.length; i++) {
        var taskID = deleteTasksConfig[i];
        scheduler.removeTaskByID(taskID);
        trace("Deleted task: " + taskID);
    }
}

// 重新调度任务函数
function rescheduleTasks():Void {
    for (var i:Number = 0; i < rescheduleTasksConfig.length; i++) {
        var task = rescheduleTasksConfig[i];
        scheduler.rescheduleTaskByID(task.taskID, task.newDelayInFrames);
        trace("Rescheduled task: " + task.taskID + " to new delay: " + task.newDelayInFrames);
    }
}
```

### 使用教程

1. **将测试脚本添加到项目中**，确保所有类和依赖项已正确导入。

2. **根据需要修改 `tasksConfig`**，配置不同的任务和延迟时间，覆盖更多的测试场景。

3. **运行项目**，观察输出日志和 `TextField` 显示的任务执行情况，验证调度器的功能。

4. **根据测试结果**，调整调度器的参数或修复潜在的问题，确保其行为符合预期。

---

## 注意事项

- **Never-Early 路由保证（v1.7）**：

  - 路由算法保证任务绝不会提前触发（`actualDelay >= requestedDelay`）。
  - 任务可能延后触发，最大延后量取决于对应时间轮的 tick 周期。
  - 二级时间轮最大延后：`multiLevelCounterLimit - 1` 帧（即不超过 1 秒）。
  - 三级时间轮最大延后：`_thirdTickPeriod - 1` 帧（即不超过 `secondLevelCounterLimit` 秒）。
  - 对于需要帧精度的任务，可使用 `addToMinHeapByID()` 强制路由至最小堆。

- **精度阈值设置（已废弃）**：

  - `precisionThreshold` 参数已在 v1.7 中废弃，不再影响路由决策。
  - 保留参数签名以维持 API 兼容性，传入任意值均不影响行为。

- **帧率一致性**：

  - 确保 `framesPerSecond` 参数与实际运行环境的帧率一致。

  - 如果帧率不一致，可能导致任务的执行时间出现偏差。

- **任务唯一性**：

  - 任务 ID 应该是全局唯一的，避免重复，防止任务管理中的冲突。

  - 可以考虑使用 GUID（全局唯一标识符）或其他唯一性算法生成任务 ID。

- **节点池管理**：

  - 调度器会自动管理节点池，但在大量任务的情况下，可以适当调整 `minThreshold` 和 `maxThreshold`。

  - 通过优化节点池的大小，提高内存使用效率和性能。

---

*/

/**
 * CerberusScheduler（地狱三头犬调度器）
 * 
 * 这是一个高级定时调度器，使用多级时间轮和最小堆来高效管理不同延迟的任务。
 * 它能够处理从即时执行到远期执行的各种任务，提供了高精度和高性能的任务调度能力。
 */
class org.flashNight.neur.ScheduleTimer.CerberusScheduler {
    // ==========================
    // 三内核数据结构
    // ==========================
    
    /** 单层时间轮，处理短期任务（例如0-149帧的任务） */
    private var singleLevelTimeWheel:SingleLevelTimeWheel;

    /** 第一级多级时间轮计数器 */
    private var multiLevelCounter:Number;

    /** 第一级计数器的上限 */
    private var multiLevelCounterLimit:Number;

    /** 第二级时间轮的计数器 */
    private var secondLevelCounter:Number;

    /** 第二级时间轮的上限 */
    private var secondLevelCounterLimit:Number;

    /** 第二级时间轮，处理中期任务（秒级任务） */
    private var secondLevelTimeWheel:SingleLevelTimeWheel;

    /** 第三级时间轮，处理长期任务（分钟级任务） */
    private var thirdLevelTimeWheel:SingleLevelTimeWheel;

    /** 最小堆，处理超出时间轮范围或精度要求高的任务 */
    private var minHeap:FrameTaskMinHeap;

    // ==========================
    // 时间轮参数
    // ==========================
    
    /** 每秒帧数，决定时间轮的粒度 */
    private var framesPerSecond:Number;

    /** 单层时间轮最大帧数 */
    private var singleWheelMaxFrames:Number;

    /** 第二级时间轮最大秒数 */
    private var secondLevelMaxSeconds:Number;

    /** 第三级时间轮最大分钟数 */
    private var thirdLevelMaxMinutes:Number;

    // ==========================
    // Never-Early 路由参数
    // ==========================

    // [FIX v1.7] 预计算三级时间轮的 tick 周期（帧数）
    // = secondLevelCounterLimit * multiLevelCounterLimit
    // 用于 evaluateAndInsertTask 的 never-early 公式，避免热路径重复乘法
    private var _thirdTickPeriod:Number;

    // ==========================
    // 初始化函数
    // ==========================

    // [FIX v1.4] 移除 taskTable 字段
    // 原设计中 CerberusScheduler 维护 taskTable[taskID] → TaskIDNode 的映射，
    // 但 TaskManager 已经维护 taskTable[taskID] → Task（包含 task.node）的映射，
    // 存在冗余。现在将任务ID管理职责完全交给 TaskManager，CerberusScheduler 专注于调度内核。
    
    /**
     * 初始化调度器，设置并配置各个参数
     *
     * @param singleWheelSize           单层时间轮的大小（帧数）
     * @param multiLevelSecondsSize     第二级时间轮的大小（秒数）
     * @param multiLevelMinutesSize     第三级时间轮的大小（分钟数）
     * @param framesPerSecond           每秒帧数（FPS）
     * @param precisionThreshold        [DEPRECATED v1.6] 精度阈值参数已废弃，不再参与路由决策。
     *                                  任务路由现在直接基于时间轮边界：
     *                                  - 0 ~ singleWheelSize 帧 → 单层时间轮（帧精度）
     *                                  - singleWheelSize ~ multiLevelSecondsSize 秒 → 二级时间轮（秒精度）
     *                                  - multiLevelSecondsSize ~ multiLevelMinutesSize 分 → 三级时间轮（分精度）
     *                                  - 超出范围 → 最小堆（帧精度）
     *                                  如需强制帧精度，请直接使用 addToMinHeapByID/addToMinHeapByNode。
     */
    public function initialize(singleWheelSize:Number,
                               multiLevelSecondsSize:Number,
                               multiLevelMinutesSize:Number,
                               framesPerSecond:Number,
                               precisionThreshold:Number) {
        
        // 设置默认参数
        if (singleWheelSize == undefined) {
            singleWheelSize = 150;  // 默认单层时间轮大小
        }
        if (multiLevelSecondsSize == undefined) {
            multiLevelSecondsSize = 60;  // 默认第二级时间轮大小
        }
        if (multiLevelMinutesSize == undefined) {
            multiLevelMinutesSize = 60;  // 默认第三级时间轮大小
        }
        if (framesPerSecond == undefined) {
            framesPerSecond = 30;  // 默认每秒帧数
        }
        // [FIX v1.7] precisionThreshold 参数已废弃，不再影响路由决策
        // 保留参数签名以维持 API 兼容性

        // 初始化单层时间轮（作为统一节点池的持有者）
        this.singleLevelTimeWheel = new SingleLevelTimeWheel(singleWheelSize, null);

        // 初始化多级时间轮计数器和限制
        this.multiLevelCounter = 0;
        this.multiLevelCounterLimit = framesPerSecond;      // 第一级计数器的上限为每秒帧数

        this.secondLevelCounter = 0;
        this.secondLevelCounterLimit = multiLevelSecondsSize;  // 第二级计数器的上限为第二级时间轮大小

        // [FIX v1.5] 初始化第二级和第三级时间轮，共享单层时间轮的节点池
        // 通过传入 singleLevelTimeWheel 作为节点池提供者，实现统一节点池管理
        // 解决了之前节点池不均衡的问题：所有时间轮共用一个节点池
        this.secondLevelTimeWheel = new SingleLevelTimeWheel(multiLevelSecondsSize, this.singleLevelTimeWheel);
        this.thirdLevelTimeWheel = new SingleLevelTimeWheel(multiLevelMinutesSize, this.singleLevelTimeWheel); 

        // 初始化最小堆，用于处理精度要求高的任务
        this.minHeap = new FrameTaskMinHeap();

        // [FIX v1.4] 移除 taskTable 初始化，任务ID管理由 TaskManager 负责

        // 设置帧率和相关参数
        this.framesPerSecond = framesPerSecond;

        // 计算并初始化相关最大值
        this.singleWheelMaxFrames = singleWheelSize;         // 单层时间轮最大帧数
        this.secondLevelMaxSeconds = multiLevelSecondsSize;  // 第二级时间轮最大秒数
        this.thirdLevelMaxMinutes = multiLevelMinutesSize;   // 第三级时间轮最大分钟数

        // [FIX v1.7] 预计算三级时间轮的 tick 周期（帧数）
        // = secondLevelCounterLimit * multiLevelCounterLimit = 秒轮大小 * fps
        this._thirdTickPeriod = multiLevelSecondsSize * framesPerSecond;
    }

    // ==========================
    // 任务评估与插入
    // ==========================

    /**
     * 评估任务的延迟并将其插入到适当的内核（时间轮或最小堆）
     *
     * @param taskID           任务的唯一标识符
     * @param delayInFrames    任务的延迟时间（以帧为单位），最小值为 1
     * @return                 插入的任务节点
     */
    public function evaluateAndInsertTask(taskID:String, delayInFrames:Number):TaskIDNode {
        // [FIX v1.3] 边界保护：确保 delayInFrames 最小为 1
        if (delayInFrames < 1) {
            delayInFrames = 1;
        }

        // [FIX v1.1] 从单层时间轮的节点池获取节点，减少 GC 压力
        var node:TaskIDNode = this.singleLevelTimeWheel.acquireNode(taskID);

        // [FIX v1.7] 短路径优化：单层时间轮是最常见的情况，无需除法
        // 1. 检查任务是否适合单层时间轮（帧精度，零误差）
        if (delayInFrames < this.singleWheelMaxFrames) {
            return addToSingleLevelByNode(node, delayInFrames);
        }

        // [FIX v1.7] Never-Early 公式：确保任务不会提前触发
        //
        // 问题分析（原 S3 bug）：
        // 原代码使用 Math.floor(delayInFrames / fps) 计算槽位，但二级时间轮的下一次 tick
        // 在 (counterLimit - counter) 帧之后，而非整数秒之后。当 counter 接近 limit 时，
        // 实际延迟 = slot * counterLimit - counter，可能远小于 delayInFrames。
        //
        // Never-Early 推导：
        //   实际触发帧数 = delaySlot * counterLimit - counter >= delayInFrames
        //   => delaySlot >= (delayInFrames + counter) / counterLimit
        //   => delaySlot = ceil((delayInFrames + counter) / counterLimit)
        //
        // 对于三级时间轮同理，但 offset 包含两级计数器的贡献。

        var counterLimit:Number = this.multiLevelCounterLimit;
        var counter:Number = this.multiLevelCounter;

        // 2. 检查任务是否适合第二级时间轮（秒精度，never-early 保证）
        var delaySlot2:Number = Math.ceil((delayInFrames + counter) / counterLimit);
        if (delaySlot2 <= this.secondLevelMaxSeconds) {
            return addToSecondLevelByNode(node, delaySlot2);
        }

        // 3. 检查任务是否适合第三级时间轮（分钟精度，never-early 保证）
        // thirdLevelOffset = 当前在三级 tick 周期内已消耗的帧数
        var thirdLevelOffset:Number = this.secondLevelCounter * counterLimit + counter;
        var thirdTickPeriod:Number = this._thirdTickPeriod;
        var delaySlot3:Number = Math.ceil((delayInFrames + thirdLevelOffset) / thirdTickPeriod);
        if (delaySlot3 <= this.thirdLevelMaxMinutes) {
            return addToThirdLevelByNode(node, delaySlot3);
        }

        // 4. 超出所有时间轮范围，插入最小堆（帧精度，O(log n)）
        return addToMinHeapByNode(node, delayInFrames);
    }



    // ==========================
    // 时间推进与任务执行
    // ==========================

    /**
     * tick 函数：推进时间轮并提取到期任务
     *
     * 该函数是调度器的核心，用于在每个帧调用时推进时间轮并执行到期任务
     *
     * 【重要约定】返回的 TaskIDLinkedList 仅用于遍历读取 taskID，
     * 不可对其中的节点调用 remove()，因为 mergeDirect 不更新节点的 list 引用。
     * 如需移除任务，请通过 removeTaskByID/removeTaskByNode 方法，
     * 或在 TaskManager 层通过 taskID 查找 taskTable 后操作。
     *
     * @return    到期需要执行的任务列表（只读遍历用）
     */
    public function tick():TaskIDLinkedList {
        var resultList:TaskIDLinkedList = null; // 用于存储到期执行的任务列表

        // 1. 从单层时间轮中提取当前帧的到期任务
        var singleWheelTasks:TaskIDLinkedList = this.singleLevelTimeWheel.tick();
        if (singleWheelTasks != null) {
            resultList = singleWheelTasks; // 如果有到期任务，将其加入结果列表
        }

        // 2. 从最小堆中提取到期任务
        var heapTasks:TaskIDLinkedList = this.minHeap.tick();
        if (heapTasks != null) {
            if (resultList == null) {
                resultList = heapTasks; // 如果结果列表为空，直接赋值为堆任务
            } else {
                resultList.mergeDirect(heapTasks); // 否则，合并堆任务到结果列表
            }
        }

        // 3. 推进多级时间轮并提取到期任务
        this.multiLevelCounter++;
        if (this.multiLevelCounter >= this.multiLevelCounterLimit) {
            this.multiLevelCounter = 0; // 重置多级时间轮的第一级计数器

            // 推进第二级时间轮，检查到期任务
            var secondLevelTasks:TaskIDLinkedList = this.secondLevelTimeWheel.tick();
            if (secondLevelTasks != null) {
                if (resultList == null) {
                    resultList = secondLevelTasks; // 如果结果列表为空，直接赋值为第二级时间轮任务
                } else {
                    resultList.mergeDirect(secondLevelTasks); // 否则，合并任务到结果列表
                }
            }

            // 推进第三级时间轮的计数器
            this.secondLevelCounter++;
            if (this.secondLevelCounter >= this.secondLevelCounterLimit) {
                this.secondLevelCounter = 0; // 重置第三级时间轮计数器

                // 推进第三级时间轮并检查到期任务
                var thirdLevelTasks:TaskIDLinkedList = this.thirdLevelTimeWheel.tick();
                if (thirdLevelTasks != null) {
                    if (resultList == null) {
                        resultList = thirdLevelTasks; // 如果结果列表为空，直接赋值为第三级时间轮任务
                    } else {
                        resultList.mergeDirect(thirdLevelTasks); // 否则，合并任务到结果列表
                    }
                }

                // 在第三级时间轮触发时维护节点池
                manageNodePools();
            }
        }

        // [FIX v1.4] 移除 cleanUpHashTable 调用
        // 任务ID管理已完全由 TaskManager 负责，CerberusScheduler 不再维护 taskTable

        // 返回到期执行的任务列表
        return resultList;
    }

    // ==========================
    // 节点池管理
    // ==========================

    /**
     * 管理所有内核的节点池，定期清理和填充节点池以优化内存使用
     * [UPDATE v1.5] 移除二级、三级时间轮的节点池管理，它们现在共享单层时间轮的节点池
     */
    private function manageNodePools():Void {
        var minThreshold:Number = 10;  // 节点池的最低限值
        var maxThreshold:Number = 100; // 节点池的最高限值

        // 1. 管理单层时间轮的统一节点池
        // [UPDATE v1.5] 这个池现在同时供给单层、二级、三级时间轮使用
        var singlePoolSize:Number = this.singleLevelTimeWheel.getNodePoolSize();
        if (singlePoolSize < minThreshold) {
            this.singleLevelTimeWheel.fillNodePool(minThreshold - singlePoolSize);  // 填充节点池
        } else if (singlePoolSize > maxThreshold) {
            this.singleLevelTimeWheel.trimNodePool(maxThreshold);  // 缩减节点池
        }

        // 2. 管理最小堆的节点池（独立节点池，不与时间轮共享）
        var heapPoolSize:Number = this.minHeap.getNodePoolSize();
        if (heapPoolSize < minThreshold) {
            this.minHeap.fillNodePool(minThreshold - heapPoolSize);  // 填充节点池
        } else if (heapPoolSize > maxThreshold) {
            this.minHeap.trimNodePool(maxThreshold);  // 缩减节点池
        }

        // [REMOVED v1.5] 二级、三级时间轮不再需要单独管理节点池
        // 它们现在委托给单层时间轮的节点池，调用会自动转发
    }

    // ==========================
    // 任务管理函数
    // ==========================

    /**
     * 通过任务节点删除任务
     *
     * [FIX v1.2] 修复节点回收：删除任务后将节点回收到统一节点池，
     * 避免每次重调度都分配新节点导致的 GC 压力。
     *
     * @param node    要删除的任务节点
     */
    public function removeTaskByNode(node:TaskIDNode):Void {
        // [FIX v1.4] 根据节点归属类型分派到正确的内核进行删除
        // 关键修复：堆节点删除必须调用 minHeap.removeNode 以正确维护堆结构
        // 原逻辑仅调用 node.list.remove(node)，导致堆中残留"幽灵 frameIndex"
        var ownerType:Number = node.ownerType;

        if (ownerType == 4) {
            // 堆节点：必须调用 minHeap.removeNode 以维护堆结构
            // 该方法会：1) 从链表移除 2) 如果链表空则从堆移除 frameIndex
            //          3) 重平衡堆 4) 清理 frameMap 5) 回收节点到 minHeap.nodePool
            this.minHeap.removeNode(node);
            // 注意：节点已被 minHeap 回收到其 nodePool，不再需要额外回收
        } else {
            // 时间轮节点：从链表移除即可
            // 时间轮的槽位会在 tick 时自然清理，无需额外维护
            if (node.list != null) {
                node.list.remove(node);
            }

            // 重置节点以清理引用
            node.reset(null);

            // [FIX v1.2] 将节点回收到单层时间轮的节点池（作为统一节点池使用）
            this.singleLevelTimeWheel.releaseNode(node);
        }

        // [FIX v1.4] 移除 removeTaskFromTable 调用，任务ID管理由 TaskManager 负责
    }

    /**
     * [DEPRECATED v1.4] 通过任务ID删除任务
     *
     * 此方法已废弃，因为 CerberusScheduler 不再维护 taskTable。
     * 请通过 TaskManager 层的 removeTask(taskID) 进行任务删除，
     * 它会通过 task.node 调用 removeTaskByNode。
     *
     * @param taskID    要删除的任务的ID
     * @deprecated 使用 TaskManager.removeTask(taskID) 代替
     */
    public function removeTaskByID(taskID:String):Void {
        trace("[CerberusScheduler] WARNING: removeTaskByID is deprecated. Use TaskManager.removeTask instead.");
        // 不再支持，因为没有 taskTable
    }

    /**
     * [DEPRECATED v1.4] 通过任务ID重新调度任务
     *
     * 此方法已废弃，因为 CerberusScheduler 不再维护 taskTable。
     * 请通过 TaskManager 层进行重调度操作。
     *
     * @param taskID               要重新调度的任务ID
     * @param newDelayInFrames     新的延迟时间（帧）
     */
    public function rescheduleTaskByID(taskID:String, newDelayInFrames:Number):Void {
        trace("[CerberusScheduler] WARNING: rescheduleTaskByID is deprecated. Use TaskManager.delayTask instead.");
        // 不再支持，因为没有 taskTable
    }

    /**
     * 通过任务节点重新调度任务
     *
     * [FIX v1.1] 修改返回类型为 TaskIDNode，返回新创建的节点
     * 调用方必须使用返回值更新其持有的节点引用，否则会导致节点引用失效
     *
     * @param node                 要重新调度的任务节点
     * @param newDelayInFrames     新的延迟时间（帧）
     * @return                     新插入的任务节点（调用方应更新其引用）
     */
    public function rescheduleTaskByNode(node:TaskIDNode, newDelayInFrames:Number):TaskIDNode {
        // 保存taskID，因为removeTaskByNode会reset节点
        var taskID:String = node.taskID;

        // 1. 从当前内核中删除该任务节点
        this.removeTaskByNode(node);

        // 2. 重新插入任务，利用现有的 evaluateAndInsertTask 评估合适的内核
        // 返回新节点供调用方更新引用
        return this.evaluateAndInsertTask(taskID, newDelayInFrames);
    }

    /**
     * [NEW v1.4] 回收已到期的节点到节点池
     *
     * 在 TaskManager 处理完 tick() 返回的任务后调用，用于回收不再需要的节点。
     *
     * 使用场景：
     * - 任务执行完毕后删除（repeatCount === 1 或 repeatCount <= 0）
     * - 任务重调度后旧节点需要回收（新节点由 evaluateAndInsertTask 分配）
     *
     * 注意：如果任务在回调中已被 removeTask 删除，则节点已被回收，不应再次调用此方法。
     * TaskManager 应检查 taskTable[taskID] 是否存在来判断是否已被回调删除。
     *
     * [FIX v1.5] 添加防御性检查：如果节点已被回收（ownerType == 0），则跳过回收
     * 防止同一节点被放入节点池两次，导致后续 acquireNode 返回重复引用
     *
     * @param node 要回收的已到期节点
     */
    public function recycleExpiredNode(node:TaskIDNode):Void {
        // [FIX v1.5] 防止重复回收
        // 如果 ownerType 已经是 0，说明节点已被回收（可能在回调中调用了 removeTask）
        if (node.ownerType == 0) {
            return;
        }

        // 重置节点以清理引用（会将 ownerType 设为 0）
        node.reset(null);

        // 回收到统一节点池（单层时间轮的节点池）
        // 【跨池回收说明 v1.7.1】
        // 当前设计统一回收到 singleLevelTimeWheel 节点池。
        //
        // 注意：evaluateAndInsertTask 路径无跨池问题——该方法始终从 singleLevelTimeWheel.acquireNode
        // 获取节点，即使路由至堆（addToMinHeapByNode），节点也来自轮池，回收至此处是正确的归还。
        //
        // 跨池仅发生在直接调用 addToMinHeapByID 时：
        // 该 API 从 minHeap.nodePool 创建节点，但到期后回收至此处（轮池），
        // 导致 minHeap.nodePool 无法复用这些节点，需反复创建新节点。
        // 当前场景下 addToMinHeapByID 使用频率低（仅超长延迟任务），跨池开销可忽略。
        // 若后续高频使用该 API，应按 ownerType 分发回收到对应池：
        //   ownerType 1/2/3 → singleLevelTimeWheel.releaseNode（当前行为）
        //   ownerType 4     → minHeap.releaseNode (需新增此方法)
        this.singleLevelTimeWheel.releaseNode(node);
    }

    // ==========================
    // 工具函数
    // ==========================

    /**
     * 获取单层时间轮的当前槽大小
     * 
     * @return    单层时间轮的槽大小
     */
    public function getSingleLevelSlotSize():Number {
        var data:Object = this.singleLevelTimeWheel.getTimeWheelData();
        return data.slotSize;
    }

    /**
     * 获取第二级时间轮的槽大小
     * 
     * @return    第二级时间轮的槽大小
     */
    public function getMultiLevelSecondSlotSize():Number {
        var data:Object = this.secondLevelTimeWheel.getTimeWheelData();
        return data.slotSize;
    }

    /**
     * 获取第三级时间轮的槽大小
     * 
     * @return    第三级时间轮的槽大小
     */
    public function getMultiLevelMinuteSlotSize():Number {
        var data:Object = this.thirdLevelTimeWheel.getTimeWheelData();
        return data.slotSize;
    }

    /**
     * 获取第一级多级时间轮计数器的上限值
     * 
     * @return    第一级计数器的上限值
     */
    public function getMultiLevelCounterLimit():Number {
        return this.multiLevelCounterLimit;
    }

    /**
     * 获取第二级时间轮计数器的上限值
     * 
     * @return    第二级计数器的上限值
     */
    public function getSecondLevelCounterLimit():Number {
        return this.secondLevelCounterLimit;
    }

    // ==========================
    // 任务哈希表管理
    // ==========================

    // ==========================
    // [DEPRECATED v1.4] 以下方法已废弃
    // 任务ID管理已完全由 TaskManager 负责
    // 保留方法签名以保持 API 兼容性
    // ==========================

    /**
     * @deprecated v1.4 - 已废弃，任务ID管理由 TaskManager 负责
     */
    private function addTaskToTable(taskID:String, node:TaskIDNode):Void {
        // 空实现 - 功能已迁移至 TaskManager
    }

    /**
     * @deprecated v1.4 - 已废弃，任务ID管理由 TaskManager 负责
     */
    private function removeTaskFromTable(taskID:String):Void {
        // 空实现 - 功能已迁移至 TaskManager
    }

    /**
     * @deprecated v1.4 - 已废弃，请使用 TaskManager.getTask() 代替
     * @return 始终返回 null
     */
    public function findTaskInTable(taskID:String):TaskIDNode {
        return null;
    }

    // ==========================
    // 任务插入函数
    // ==========================

    /**
     * 通过任务ID插入任务到最小堆
     *
     * [RECOMMENDED v1.6] 高精度任务调度推荐API
     * 当需要精确的帧级延迟控制时，直接使用此方法绕过时间轮的精度损失。
     * 最小堆保证任务在精确的延迟帧数后执行，无舍入误差。
     *
     * 使用场景：
     * - 需要精确帧数延迟的动画/技能效果
     * - 对时间敏感的游戏逻辑（如无敌帧、冷却精确计算）
     * - 延迟超出时间轮范围（>60分钟）的长期任务
     *
     * 注意：最小堆的 O(log n) 插入/删除开销高于时间轮的 O(1)，
     * 对于大量非精确任务，建议使用 evaluateAndInsertTask 自动路由。
     *
     * 【跨池回收注意 v1.7.1】
     * 此方法从 minHeap.nodePool 获取节点，但到期回收时统一进入 singleLevelTimeWheel 池。
     * 高频使用时 minHeap.nodePool 无法复用已回收节点，需持续分配新对象。
     * 详见 recycleExpiredNode 中的跨池回收说明。
     *
     * @param taskID    任务ID
     * @param delay     延迟时间（帧）
     * @return          插入的任务节点
     */
    public function addToMinHeapByID(taskID:String, delay:Number):TaskIDNode {
        // [FIX v1.7] 使用 minHeap 自身的节点池获取节点，避免绕过节点池直接 new
        // minHeap.addTimerByID 内部会从 minHeap.nodePool 中获取或创建节点
        var node:TaskIDNode = this.minHeap.addTimerByID(taskID, delay);
        // [FIX v1.4] 设置节点归属类型为最小堆
        node.ownerType = 4;
        return node;
    }

    /**
     * 通过节点插入任务到最小堆
     * 
     * @param node      任务节点
     * @param delay     延迟时间（帧）
     * @return          插入的任务节点
     */
    public function addToMinHeapByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        // [FIX v1.4] 设置节点归属类型为最小堆
        node.ownerType = 4;

        // 插入节点到最小堆
        this.minHeap.addTimerByNode(node, delay);

        // [FIX v1.4] 移除 addTaskToTable 调用，任务ID管理由 TaskManager 负责

        return node;
    }

    /**
     * 通过任务ID插入任务到单层时间轮
     * 
     * @param taskID           任务ID
     * @param delayInFrames    延迟时间（帧）
     * @return                 插入的任务节点
     */
    public function addToSingleLevelByID(taskID:String, delayInFrames:Number):TaskIDNode {
        // [FIX v1.7] 通过节点池获取节点，避免绕过节点池直接 new
        var node:TaskIDNode = this.singleLevelTimeWheel.acquireNode(taskID);
        return addToSingleLevelByNode(node, delayInFrames);
    }

    /**
     * 通过节点插入任务到单层时间轮
     *
     * 【S3 文档强化 v1.6：Off-by-One 语义说明】
     * 时间轮的延迟采用 "N-1" 语义：传入 delayInFrames 时，实际存入槽位 delayInFrames - 1。
     * 这是因为时间轮的 tick() 在当前帧末尾执行，任务需要在"第 N 帧结束时"触发。
     *
     * 举例（30 FPS，singleWheelSize = 150）：
     * - 调用 addToSingleLevelByNode(node, 1)：存入槽位 0，下一次 tick 即触发
     * - 调用 addToSingleLevelByNode(node, 30)：存入槽位 29，约 1 秒后触发
     * - 调用 addToSingleLevelByNode(node, 149)：存入槽位 148，约 4.93 秒后触发
     *
     * 注意：delayInFrames 最小为 1，传入 0 或负数会导致意外行为（已在 evaluateAndInsertTask 中防护）。
     *
     * @param node             任务节点
     * @param delayInFrames    延迟时间（帧），最小为 1
     * @return                 插入的任务节点
     */
    public function addToSingleLevelByNode(node:TaskIDNode, delayInFrames:Number):TaskIDNode {
        // [FIX v1.4] 设置节点归属类型为单层时间轮
        node.ownerType = 1;

        // 插入任务节点到单层时间轮，使用 N-1 语义
        this.singleLevelTimeWheel.addTimerByNode(node, delayInFrames - 1);

        // [FIX v1.4] 移除 addTaskToTable 调用，任务ID管理由 TaskManager 负责

        return node;
    }

    /**
     * 通过任务ID插入任务到第二级时间轮
     * 
     * @param taskID           任务ID
     * @param delayInSeconds   延迟时间（秒）
     * @return                 插入的任务节点
     */
    public function addToSecondLevelByID(taskID:String, delayInSeconds:Number):TaskIDNode {
        // [FIX v1.7] 通过统一节点池获取节点
        var node:TaskIDNode = this.singleLevelTimeWheel.acquireNode(taskID);
        return addToSecondLevelByNode(node, delayInSeconds);
    }

    /**
     * 通过节点插入任务到第二级时间轮
     *
     * 【S3 文档强化 v1.6：Off-by-One 语义说明】
     * 与单层时间轮相同，采用 "N-1" 语义存入槽位。
     * 二级时间轮每秒 tick 一次（由 multiLevelCounter 触发），精度为 1 秒。
     *
     * 举例：
     * - 调用 addToSecondLevelByNode(node, 5)：存入槽位 4，约 5 秒后触发
     * - 调用 addToSecondLevelByNode(node, 60)：存入槽位 59，约 60 秒后触发
     *
     * @param node             任务节点
     * @param delayInSeconds   延迟时间（秒），最小为 1
     * @return                 插入的任务节点
     */
    public function addToSecondLevelByNode(node:TaskIDNode, delayInSeconds:Number):TaskIDNode {
        // [FIX v1.4] 设置节点归属类型为秒级时间轮
        node.ownerType = 2;

        // 插入任务节点到第二级时间轮，使用 N-1 语义
        this.secondLevelTimeWheel.addTimerByNode(node, delayInSeconds - 1);

        // [FIX v1.4] 移除 addTaskToTable 调用，任务ID管理由 TaskManager 负责

        return node;
    }

    /**
     * 通过任务ID插入任务到第三级时间轮
     * 
     * @param taskID            任务ID
     * @param delayInMinutes    延迟时间（分钟）
     * @return                  插入的任务节点
     */
    public function addToThirdLevelByID(taskID:String, delayInMinutes:Number):TaskIDNode {
        // [FIX v1.7] 通过统一节点池获取节点
        var node:TaskIDNode = this.singleLevelTimeWheel.acquireNode(taskID);
        return addToThirdLevelByNode(node, delayInMinutes);
    }

    /**
     * 通过节点插入任务到第三级时间轮
     *
     * 【S3 文档强化 v1.6：Off-by-One 语义说明】
     * 与前两级时间轮相同，采用 "N-1" 语义存入槽位。
     * 三级时间轮每分钟 tick 一次（由 secondLevelCounter 触发），精度为 1 分钟。
     *
     * 举例：
     * - 调用 addToThirdLevelByNode(node, 1)：存入槽位 0，约 1 分钟后触发
     * - 调用 addToThirdLevelByNode(node, 60)：存入槽位 59，约 60 分钟后触发
     *
     * @param node              任务节点
     * @param delayInMinutes    延迟时间（分钟），最小为 1
     * @return                  插入的任务节点
     */
    public function addToThirdLevelByNode(node:TaskIDNode, delayInMinutes:Number):TaskIDNode {
        // [FIX v1.4] 设置节点归属类型为分钟级时间轮
        node.ownerType = 3;

        // 插入任务节点到第三级时间轮，使用 N-1 语义
        this.thirdLevelTimeWheel.addTimerByNode(node, delayInMinutes - 1);

        // [FIX v1.4] 移除 addTaskToTable 调用，任务ID管理由 TaskManager 负责

        return node;
    }

    /**
     * @deprecated v1.4 - 已废弃，任务ID管理由 TaskManager 负责
     */
    private function cleanUpHashTable(taskList:TaskIDLinkedList):Void {
        // 空实现 - 功能已迁移至 TaskManager
    }

    /**
     * 获取单层时间轮
     * @return 单层时间轮实例
     */
    public function getSingleLevelTimeWheel():SingleLevelTimeWheel {
        return this.singleLevelTimeWheel;
    }

    /**
     * 获取第二级时间轮
     * @return 第二级时间轮实例
     */
    public function getSecondLevelTimeWheel():SingleLevelTimeWheel {
        return this.secondLevelTimeWheel;
    }

    /**
     * 获取第三级时间轮
     * @return 第三级时间轮实例
     */
    public function getThirdLevelTimeWheel():SingleLevelTimeWheel {
        return this.thirdLevelTimeWheel;
    }
}



/*
import org.flashNight.neur.ScheduleTimer.CerberusScheduler;
import org.flashNight.naki.DataStructures.*;
var enableDeleteTasksTest:Boolean = true;
var enableRescheduleTasksTest:Boolean = true;

// Initialize the scheduler
var scheduler:CerberusScheduler = new CerberusScheduler();
scheduler.initialize(150, 60, 60, 30, 0.1); // Initialize with default values

var currentFrame:Number = 0; // Keep track of the current frame count
var executedTasksCount:Number = 0; // Track the number of executed tasks

// Create a text field to display frame count and task status
var frameCountDisplay:TextField = _root.createTextField("frameCountDisplay", _root.getNextHighestDepth(), 10, 10, 700, 800);
frameCountDisplay.border = true;
frameCountDisplay.background = true;
frameCountDisplay.text = "Frame: 0";
frameCountDisplay.textColor = 0xFFFFFF; // White text
frameCountDisplay.backgroundColor = 0x000000; // Black background
frameCountDisplay.wordWrap = true; // Enable word wrap for text display
frameCountDisplay.multiline = true; // Allow multiple lines
frameCountDisplay.autoSize = true; // Auto resize to fit content

// Task table to track expected and actual execution frames
var taskTable:Array = []; // Array to store task info (ID, expected frame, actual frame)

// Function to add a task to the task table
function addTaskToTable(taskID:String, expectedFrame:Number):Void {
    taskTable.push({taskID: taskID, expectedFrame: expectedFrame, actualFrame: null});
}

// Function to update the actual frame in the task table
function updateActualFrame(taskID:String, actualFrame:Number):Void {
    for (var i:Number = 0; i < taskTable.length; i++) {
        if (taskTable[i].taskID == taskID) {
            taskTable[i].actualFrame = actualFrame;
            break;
        }
    }
}

// Function to display task tracking information in the text box
function displayTaskTable():Void {
    var displayText:String = "Frame: " + currentFrame + "\nTasks Executed: " + executedTasksCount + "\n\n";
    displayText += "TaskID\tExpected\tActual\n";
    for (var i:Number = 0; i < taskTable.length; i++) {
        displayText += taskTable[i].taskID + "\t" + taskTable[i].expectedFrame + "\t" + (taskTable[i].actualFrame != null ? taskTable[i].actualFrame : "Pending") + "\n";
    }
    
    // Display deleted tasks
    displayText += "\nDeleted Tasks:\n";
    for (var j:Number = 0; j < deletedTasks.length; j++) {
        displayText += deletedTasks[j] + "\n";
    }
    
    // Display rescheduled tasks
    displayText += "\nRescheduled Tasks:\n";
    for (var k:Number = 0; k < rescheduledTasks.length; k++) {
        displayText += rescheduledTasks[k].taskID + "\tNew Expected Frame: " + rescheduledTasks[k].newExpectedFrame + "\n";
    }

    frameCountDisplay.text = displayText;
}

// Task configuration array (expanded for more comprehensive coverage)
var tasksConfig:Array = [
    // Single-level time wheel tasks
    {taskID: "task1", delayInFrames: 10, expectedFrame: 10},  
    {taskID: "task2", delayInFrames: 149, expectedFrame: 149},
    {taskID: "task3", delayInFrames: 150, expectedFrame: 150}, 
    {taskID: "task15", delayInFrames: 1, expectedFrame: 1},    // Immediate execution

    // Second-level time wheel tasks
    {taskID: "task4", delayInFrames: 151, expectedFrame: 151},
    {taskID: "task5", delayInFrames: 500, expectedFrame: 500},
    {taskID: "task6", delayInFrames: 1800, expectedFrame: 1800},
    {taskID: "task16", delayInFrames: 300, expectedFrame: 300}, // Mid-second-level

    // Third-level time wheel tasks
    {taskID: "task7", delayInFrames: 1801, expectedFrame: 1801},
    {taskID: "task8", delayInFrames: 36000, expectedFrame: 36000},
    {taskID: "task9", delayInFrames: 72000, expectedFrame: 72000},
    {taskID: "task17", delayInFrames: 54000, expectedFrame: 54000}, // Mid-third-level

    // Min heap (extended tasks)
    {taskID: "task10", delayInFrames: 108000, expectedFrame: 108000}, 
    {taskID: "task11", delayInFrames: 108001, expectedFrame: 108001}, 
    {taskID: "task18", delayInFrames: 200000, expectedFrame: 200000}, // Extreme delay

    // Concurrent tasks (testing concurrency at the same frame)
    {taskID: "task12", delayInFrames: 150, expectedFrame: 150},
    {taskID: "task13", delayInFrames: 1800, expectedFrame: 1800},
    {taskID: "task14", delayInFrames: 1801, expectedFrame: 1801},

    // Additional edge and concurrent cases
    {taskID: "task19", delayInFrames: 149, expectedFrame: 149}, // Concurrent with task2
    {taskID: "task20", delayInFrames: 108001, expectedFrame: 108001}, // Concurrent with task11

    // Tasks that should fall into the min heap due to precision threshold
    {taskID: "task21", delayInFrames: 1650, expectedFrame: 1650}, // Nearing second-level threshold but with precision issue
    {taskID: "task22", delayInFrames: 36600, expectedFrame: 36600}, // Just above 20-minute mark
    {taskID: "task23", delayInFrames: 36601, expectedFrame: 36601}, // Slightly over the 20-minute boundary
    {taskID: "task24", delayInFrames: 499, expectedFrame: 499},
    {taskID: "task25", delayInFrames: 500, expectedFrame: 500},
    {taskID: "task26", delayInFrames: 600, expectedFrame: 600},
    {taskID: "task27", delayInFrames: 1799, expectedFrame: 1799},
    {taskID: "task28", delayInFrames: 1800, expectedFrame: 1800},
    {taskID: "task29", delayInFrames: 1801, expectedFrame: 1801},
    {taskID: "task30", delayInFrames: 71999, expectedFrame: 71999},
    {taskID: "task31", delayInFrames: 72000, expectedFrame: 72000},
    {taskID: "task32", delayInFrames: 72001, expectedFrame: 72001},

    // Precision threshold tasks
    {taskID: "task33", delayInFrames: 599, expectedFrame: 599},
    {taskID: "task34", delayInFrames: 600, expectedFrame: 600}
];

// 删除任务配置
var deleteTasksConfig:Array = [
    "task3",  // 将在第一帧被删除
    "task7",  // 在第三层时间轮中删除
    "task10"  // 最小堆任务删除
];

// 删除任务表
var deletedTasks:Array = [];

// Function to delete tasks from the scheduler
function deleteTasks():Void {
    trace("Executing task deletion at frame: " + currentFrame);
    for (var i:Number = 0; i < deleteTasksConfig.length; i++) {
        var taskID = deleteTasksConfig[i];
        scheduler.removeTaskByID(taskID);
        deletedTasks.push(taskID);
    }
}


// 重新调度任务配置
var rescheduleTasksConfig:Array = [
    {taskID: "task4", newDelayInFrames: 3000},  // 从第二层时间轮移到第三层时间轮
    {taskID: "task19", newDelayInFrames: 200},  // 从单层时间轮重新调度到第二层时间轮
    {taskID: "task11", newDelayInFrames: 50000} // 最小堆任务调整
];

// 重新调度任务表
var rescheduledTasks:Array = [];

// Function to reschedule tasks in the scheduler
function rescheduleTasks():Void {
    trace("Executing task rescheduling at frame: " + currentFrame);
    for (var i:Number = 0; i < rescheduleTasksConfig.length; i++) {
        var task = rescheduleTasksConfig[i];
        scheduler.rescheduleTaskByID(task.taskID, task.newDelayInFrames);
        rescheduledTasks.push({taskID: task.taskID, newExpectedFrame: currentFrame + task.newDelayInFrames});
        trace("Rescheduled task: " + task.taskID + " to new delay: " + task.newDelayInFrames);
    }
}


// Function to evaluate and insert tasks based on the configuration array
function evaluateAndInsertTasks():Void {
    for (var i:Number = 0; i < tasksConfig.length; i++) {
        var task = tasksConfig[i];
        addTaskToTable(task.taskID, task.expectedFrame);
        scheduler.evaluateAndInsertTask(task.taskID, task.delayInFrames);
        trace(task.taskID + " inserted with delay " + task.delayInFrames + " frames, expected to go into appropriate time wheel");
    }
}

// OnEnterFrame loop to simulate the progression of time and tick execution
_root.onEnterFrame = function() {
    currentFrame++; // Increment the current frame count
    displayTaskTable(); // Display the task table in the text box

    // Call the scheduler's tick method to simulate task execution at this frame
    var tasks:TaskIDLinkedList = scheduler.tick();
    if (tasks != null) {
        var node:TaskIDNode = tasks.getFirst();
        while (node != null) {
            trace("Executing task: " + node.taskID + " at frame: " + currentFrame);
            executedTasksCount++; // Increment the executed tasks counter
            updateActualFrame(node.taskID, currentFrame); // Update the actual frame in the task table
            node = node.next;
        }
    }

    // Add tasks and test scheduling at frame 1 
    if (currentFrame == 1) {
        evaluateAndInsertTasks();
    }

    // Execute delete operations at frame 2 if enabled
if (currentFrame == 2 && enableDeleteTasksTest) {
    trace("Deleting tasks at frame 2");
    deleteTasks();
}


    // Execute reschedule operations at frame 3 if enabled
if (currentFrame == 3 && enableRescheduleTasksTest) {
    trace("Rescheduling tasks at frame 3");
    rescheduleTasks();
}


    // Stop the simulation after all tasks are executed
    if (executedTasksCount >= taskTable.length) {
        _root.onEnterFrame = undefined; // End the test
        trace("Test completed.");
    }
};

*/