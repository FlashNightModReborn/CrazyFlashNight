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

- **precisionThreshold**：精度阈值，任务允许的最大时间偏差，用于决定任务是否应插入时间轮或最小堆。

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

  - `precisionThreshold`（Number）：精度阈值，任务允许的最大时间偏差。默认值为 0.1。

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

  1. **检查单层时间轮**：

     - 如果 `delayInFrames` 小于 `singleWheelMaxFrames`，则任务适合放入单层时间轮，无需考虑精度损失。

     - 调用 `addToSingleLevelByNode` 方法将任务节点插入单层时间轮。

  2. **检查第二级时间轮**：

     - 将 `delayInFrames` 转换为秒，得到 `delayInSeconds`。

     - 如果 `delayInSeconds` 在 `firstWhileSecond` 和 `secondLevelMaxSeconds` 之间，任务可能适合放入第二级时间轮。

     - 评估将任务插入到槽位 N-1 和 N 的精度损失，选择精度损失最小的槽位。

     - 如果最小精度损失小于等于 `precisionThreshold`，则调用 `addToSecondLevelByNode` 方法将任务节点插入第二级时间轮。

  3. **检查第三级时间轮**：

     - 将 `delayInSeconds` 转换为分钟，得到 `delayInMinutes`。

     - 如果 `delayInMinutes` 在 1 和 `thirdLevelMaxMinutes` 之间，任务可能适合放入第三级时间轮。

     - 评估将任务插入到槽位 N-1 和 N 的精度损失，选择精度损失最小的槽位。

     - 如果最小精度损失小于等于 `precisionThreshold`，则调用 `addToThirdLevelByNode` 方法将任务节点插入第三级时间轮。

  4. **使用最小堆**：

     - 如果任务无法满足时间轮的精度要求，或超出了时间轮的范围，则将任务节点插入最小堆。

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

- **精度阈值设置**：

  - `precisionThreshold` 参数决定了任务插入时间轮时允许的最大时间偏差。

  - 如果应用对任务的执行时间要求非常严格，可以将该值设置得更小，以增加使用最小堆的任务数量，保证精度。

  - 需要权衡精度和性能，过小的阈值可能增加最小堆的负担。

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

    /** 第一级时间轮的范围（秒） */
    private var firstWhileSecond:Number;

    /** 单层时间轮最大帧数 */
    private var singleWheelMaxFrames:Number;

    /** 第二级时间轮最大秒数 */
    private var secondLevelMaxSeconds:Number;

    /** 第三级时间轮最大分钟数 */
    private var thirdLevelMaxMinutes:Number;

    // ==========================
    // 精度评估阈值
    // ==========================
    
    /** 允许的最大精度偏差（相对百分比，例如0.1表示10%） */
    private var precisionThreshold:Number;

    /** 第二级时间轮的最大绝对精度损失（秒） */
    private var maxPrecisionLossSecondLevel:Number;

    /** 第三级时间轮的最大绝对精度损失（秒） */
    private var maxPrecisionLossThirdLevel:Number;

    /** 插入第二级时间轮所需的最小延迟时间（秒） */
    private var minDelaySecondLevel:Number;

    /** 插入第三级时间轮所需的最小延迟时间（秒） */
    private var minDelayThirdLevel:Number;

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
     * @param precisionThreshold        精度阈值（允许的最大偏差，相对百分比）
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
        if (precisionThreshold == undefined) {
            precisionThreshold = 0.1;  // 默认精度阈值（10%）
        }

        // 初始化单层时间轮
        this.singleLevelTimeWheel = new SingleLevelTimeWheel(singleWheelSize);

        // 初始化多级时间轮计数器和限制
        this.multiLevelCounter = 0;                         
        this.multiLevelCounterLimit = framesPerSecond;      // 第一级计数器的上限为每秒帧数

        this.secondLevelCounter = 0;                        
        this.secondLevelCounterLimit = multiLevelSecondsSize;  // 第二级计数器的上限为第二级时间轮大小

        // 初始化第二级和第三级时间轮
        this.secondLevelTimeWheel = new SingleLevelTimeWheel(multiLevelSecondsSize);  
        this.thirdLevelTimeWheel = new SingleLevelTimeWheel(multiLevelMinutesSize); 

        // 初始化最小堆，用于处理精度要求高的任务
        this.minHeap = new FrameTaskMinHeap();

        // [FIX v1.4] 移除 taskTable 初始化，任务ID管理由 TaskManager 负责

        // 设置帧率和相关参数
        this.framesPerSecond = framesPerSecond;
        this.firstWhileSecond = singleWheelSize / framesPerSecond; // 计算第一级时间轮范围（秒）
        this.precisionThreshold = precisionThreshold;

        // 计算并初始化相关最大值
        this.singleWheelMaxFrames = singleWheelSize;         // 单层时间轮最大帧数
        this.secondLevelMaxSeconds = multiLevelSecondsSize;  // 第二级时间轮最大秒数
        this.thirdLevelMaxMinutes = multiLevelMinutesSize;   // 第三级时间轮最大分钟数

        // ==========================
        // 添加的部分：预计算精度相关参数
        // ==========================

        // [FIX v1.2] 设置第二级和第三级时间轮的最大绝对精度损失
        // 由于 evaluateAndInsertTask 使用 Math.floor 取整，最大误差接近 1 个槽位
        // 而非之前假设的半个槽位（0.5秒/30秒）
        this.maxPrecisionLossSecondLevel = 1.0;  // 第二级时间轮槽位大小为1秒，floor 最大误差接近 1 秒
        this.maxPrecisionLossThirdLevel = 60;    // 第三级时间轮槽位大小为60秒，floor 最大误差接近 60 秒

        // [FIX v1.4] 修复任务路由间隙问题
        // 原逻辑：minDelaySecondLevel = maxPrecisionLoss / threshold = 1.0 / 0.1 = 10秒
        // 问题：单层时间轮处理 0-4.97秒，但二级时间轮要求 >=10秒，导致 5-10秒的任务被错误路由到最小堆
        // 修复：确保各级时间轮无缝衔接，使用 Math.max 保证最小延迟不低于上一级时间轮的边界
        var precisionBasedMinSecond:Number = this.maxPrecisionLossSecondLevel / this.precisionThreshold;
        var precisionBasedMinMinute:Number = this.maxPrecisionLossThirdLevel / this.precisionThreshold / 60; // 转换为分钟

        // 二级时间轮的最小延迟 = max(单层时间轮边界, 精度要求的最小延迟)
        // 这样确保超出单层时间轮范围的任务能进入二级时间轮，而非被推入最小堆
        this.minDelaySecondLevel = this.firstWhileSecond; // 直接使用单层时间轮的边界（秒）

        // 三级时间轮的最小延迟 = max(二级时间轮边界, 精度要求的最小延迟)
        // secondLevelMaxSeconds 是二级时间轮的最大秒数（默认60），超出则进入三级
        this.minDelayThirdLevel = this.secondLevelMaxSeconds; // 直接使用二级时间轮的边界（秒），后续比较时转为分钟
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
        // 防止 delayInFrames <= 0 导致 addToSingleLevelByNode 传入负数延迟，
        // 从而使任务被错误地放入距当前指针 149 帧的槽位
        if (delayInFrames < 1) {
            delayInFrames = 1;
        }

        // [FIX v1.1] 从单层时间轮的节点池获取节点，而不是每次都 new
        // 这样可以复用节点池中的对象，减少 GC 压力
        var node:TaskIDNode = this.singleLevelTimeWheel.acquireNode(taskID);

        // 将延迟转换为秒和分钟
        var delayInSeconds:Number = delayInFrames / this.framesPerSecond;
        var delayInMinutes:Number = delayInSeconds / 60;

        // 1. 检查任务是否适合单层时间轮
        if (delayInFrames < this.singleWheelMaxFrames) {
            // 直接插入单层时间轮
            return addToSingleLevelByNode(node, delayInFrames);
        }

        // 2. 检查任务是否适合第二级时间轮
        if (delayInSeconds >= this.minDelaySecondLevel && delayInSeconds < this.secondLevelMaxSeconds) {
            // 计算槽位索引
            var delaySlot:Number = Math.floor(delayInSeconds);
            return addToSecondLevelByNode(node, delaySlot);
        }

        // 3. 检查任务是否适合第三级时间轮
        if (delayInMinutes >= this.minDelayThirdLevel / 60 && delayInMinutes < this.thirdLevelMaxMinutes) {
            // 计算槽位索引
            var delaySlot:Number = Math.floor(delayInMinutes);
            return addToThirdLevelByNode(node, delaySlot);
        }

        // 4. 如果精度要求无法满足，插入到最小堆
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
     */
    private function manageNodePools():Void {
        var minThreshold:Number = 10;  // 节点池的最低限值
        var maxThreshold:Number = 100; // 节点池的最高限值

        // 1. 管理单层时间轮的节点池
        var singlePoolSize:Number = this.singleLevelTimeWheel.getNodePoolSize();
        if (singlePoolSize < minThreshold) {
            this.singleLevelTimeWheel.fillNodePool(minThreshold - singlePoolSize);  // 填充节点池
        } else if (singlePoolSize > maxThreshold) {
            this.singleLevelTimeWheel.trimNodePool(maxThreshold);  // 缩减节点池
        }

        // 2. 管理最小堆的节点池
        var heapPoolSize:Number = this.minHeap.getNodePoolSize();
        if (heapPoolSize < minThreshold) {
            this.minHeap.fillNodePool(minThreshold - heapPoolSize);  // 填充节点池
        } else if (heapPoolSize > maxThreshold) {
            this.minHeap.trimNodePool(maxThreshold);  // 缩减节点池
        }

        // 3. 管理第二级和第三级时间轮的节点池
        var secondPoolSize:Number = this.secondLevelTimeWheel.getNodePoolSize();
        if (secondPoolSize < minThreshold) {
            this.secondLevelTimeWheel.fillNodePool(minThreshold - secondPoolSize);  // 填充节点池
        } else if (secondPoolSize > maxThreshold) {
            this.secondLevelTimeWheel.trimNodePool(maxThreshold);  // 缩减节点池
        }

        var thirdPoolSize:Number = this.thirdLevelTimeWheel.getNodePoolSize();
        if (thirdPoolSize < minThreshold) {
            this.thirdLevelTimeWheel.fillNodePool(minThreshold - thirdPoolSize);  // 填充节点池
        } else if (thirdPoolSize > maxThreshold) {
            this.thirdLevelTimeWheel.trimNodePool(maxThreshold);  // 缩减节点池
        }
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
     * @param node 要回收的已到期节点
     */
    public function recycleExpiredNode(node:TaskIDNode):Void {
        // 重置节点以清理引用
        node.reset(null);

        // 回收到统一节点池（单层时间轮的节点池）
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
     * @param taskID    任务ID
     * @param delay     延迟时间（帧）
     * @return          插入的任务节点
     */
    public function addToMinHeapByID(taskID:String, delay:Number):TaskIDNode {
        var node:TaskIDNode = new TaskIDNode(taskID);  // 创建新任务节点
        return addToMinHeapByNode(node, delay);        // 调用通过节点插入的方法
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
        var node:TaskIDNode = new TaskIDNode(taskID);  // 创建任务节点
        return addToSingleLevelByNode(node, delayInFrames);  // 调用通过节点插入的方法
    }

    /**
     * 通过节点插入任务到单层时间轮
     * 
     * @param node             任务节点
     * @param delayInFrames    延迟时间（帧）
     * @return                 插入的任务节点
     */
    public function addToSingleLevelByNode(node:TaskIDNode, delayInFrames:Number):TaskIDNode {
        // [FIX v1.4] 设置节点归属类型为单层时间轮
        node.ownerType = 1;

        // 插入任务节点到单层时间轮
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
        var node:TaskIDNode = new TaskIDNode(taskID);  // 创建任务节点
        return addToSecondLevelByNode(node, delayInSeconds);  // 调用通过节点插入的方法
    }

    /**
     * 通过节点插入任务到第二级时间轮
     * 
     * @param node             任务节点
     * @param delayInSeconds   延迟时间（秒）
     * @return                 插入的任务节点
     */
    public function addToSecondLevelByNode(node:TaskIDNode, delayInSeconds:Number):TaskIDNode {
        // [FIX v1.4] 设置节点归属类型为秒级时间轮
        node.ownerType = 2;

        // 插入任务节点到第二级时间轮
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
        var node:TaskIDNode = new TaskIDNode(taskID);  // 创建任务节点
        return addToThirdLevelByNode(node, delayInMinutes);  // 调用通过节点插入的方法
    }

    /**
     * 通过节点插入任务到第三级时间轮
     * 
     * @param node              任务节点
     * @param delayInMinutes    延迟时间（分钟）
     * @return                  插入的任务节点
     */
    public function addToThirdLevelByNode(node:TaskIDNode, delayInMinutes:Number):TaskIDNode {
        // [FIX v1.4] 设置节点归属类型为分钟级时间轮
        node.ownerType = 3;

        // 插入任务节点到第三级时间轮
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