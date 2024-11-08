/*
# TaskMinHeap 类

## 简介

`TaskMinHeap` 是一个最小堆实现，用于管理基于任务优先级的调度。该类允许你插入、查找、更新和删除任务，并且能够高效地获取优先级最低的任务。通过维护一个堆结构，`TaskMinHeap` 保证了在 `O(log n)` 时间复杂度内完成插入和删除操作，是实现任务调度、优先队列等场景的理想选择。

## 特性

- **插入任务**：可以根据任务 ID 和优先级插入新任务。
- **删除任务**：根据任务 ID 从堆中移除特定任务。
- **更新优先级**：动态调整任务的优先级，并维护堆的性质。
- **获取最小任务**：快速获取并移除优先级最低的任务。
- **查看堆顶任务**：无需移除即可查看优先级最低的任务。
- **任务查找**：可以根据任务 ID 快速查找到对应的任务节点。

## 使用方法

### 1. 创建实例

首先，导入 `TaskMinHeap` 类并创建一个实例。

```actionscript
import org.flashNight.naki.DataStructures.TaskMinHeap;

var taskHeap:TaskMinHeap = new TaskMinHeap();
```

### 2. 插入任务

使用 `insert` 方法插入一个新任务，需要指定任务 ID 和优先级。

```actionscript
taskHeap.insert("task1", 10);
taskHeap.insert("task2", 5);
```

### 3. 获取并执行优先级最低的任务

使用 `extractMin` 方法获取并移除优先级最低的任务。

```actionscript
var minTask:HeapNode = taskHeap.extractMin();
trace("Executing task: " + minTask.taskID + " with priority: " + minTask.priority);
```

### 4. 更新任务的优先级

使用 `update` 方法更新某个任务的优先级。

```actionscript
taskHeap.update("task1", 3);
```

### 5. 删除特定任务

使用 `remove` 方法根据任务 ID 删除任务。

```actionscript
taskHeap.remove("task2");
```

### 6. 查看堆顶任务

使用 `peekMin` 方法查看当前堆顶任务（优先级最低），但不移除它。

```actionscript
var topTask:HeapNode = taskHeap.peekMin();
trace("Top task: " + topTask.taskID + " with priority: " + topTask.priority);
```

### 7. 查找任务

使用 `find` 方法根据任务 ID 查找任务节点。

```actionscript
var task:HeapNode = taskHeap.find("task1");
if (task != null) {
    trace("Found task: " + task.taskID + " with priority: " + task.priority);
} else {
    trace("Task not found.");
}
```

## 代码结构

- `heap:Array`：存储堆中节点的数组。
- `taskMap:Object`：用于快速查找任务的映射。
- `insert(taskID:String, priority:Number):Void`：插入新任务。
- `remove(taskID:String):Void`：根据任务 ID 移除特定任务。
- `update(taskID:String, newPriority:Number):Void`：更新任务的优先级。
- `extractMin():HeapNode`：获取并移除优先级最低的任务。
- `peekMin():HeapNode`：查看优先级最低的任务，但不移除它。
- `find(taskID:String):HeapNode`：根据任务 ID 查找任务节点。
- `bubbleUp(index:Number):Void`：上浮操作，维护堆的性质。
- `bubbleDown(index:Number):Void`：下沉操作，维护堆的性质。
- `swap(index1:Number, index2:Number):Void`：交换堆中两个节点的位置。
- `rebalance(node:HeapNode):Void`：重新平衡堆。
- `findIndexByTaskID(taskID:String):Number`：查找任务在堆中的索引。

## 注意事项

1. **`trace` 调试**：在代码中，所有的 `trace` 语句默认是被注释掉的。可以在需要调试时解除注释以查看详细的运行时信息。
2. **索引更新**：堆的上浮和下沉操作会自动维护节点的索引，确保堆的性质不被破坏。
3. **优先级更新**：在使用 `update` 方法更新任务优先级时，堆会自动重新平衡，以确保最小堆的结构。

## 扩展

此类可以作为基础数据结构，扩展用于实现更多复杂的任务调度系统，如带有定时器的优先队列或多任务系统中的任务管理模块。

*/

import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TaskMinHeap {
    private var heap:Array;       // Used to store the heap nodes
    private var taskMap:Object;   // Maps taskID to HeapNode for quick lookup
    private var heapSize:Number;  // Current size of the heap
    // D is hardcoded to 4

    // Constructor
    public function TaskMinHeap() {
        this.heap = [];
        this.taskMap = {};
        this.heapSize = 0;
    }

    // Inserts a new task into the heap
    public function insert(taskID:String, priority:Number):Void {
        var existingNode:HeapNode = this.taskMap[taskID];
        if (existingNode != null) {
            // Update the existing task's priority and rebalance the heap
            this.update(taskID, priority);
            return;
        }

        var node:HeapNode = new HeapNode(taskID, priority);
        this.heap[this.heapSize] = node;
        this.taskMap[taskID] = node;
        this.bubbleUp(this.heapSize);
        this.heapSize++;
    }

    // Finds a task by taskID
    public function find(taskID:String):HeapNode {
        return this.taskMap[taskID];
    }

    // Peeks at the minimum task in the heap
    public function peekMin():HeapNode {
        if (this.heapSize == 0) {
            return null;
        }
        return this.heap[0];
    }

    // Removes a task by taskID
    public function remove(taskID:String):Void {
        var node:HeapNode = this.taskMap[taskID];
        if (node == null) {
            return;  // Task does not exist
        }

        // Inline customIndexOf logic to find index
        var index:Number = -1;
        for (var i:Number = 0; i < this.heapSize; i++) {
            if (this.heap[i] == node) { // Compare object references
                index = i;
                break;
            }
        }
        if (index == -1) {
            return;  // Node not found
        }

        this.heapSize--;
        if (index != this.heapSize) {  // If not the last node
            var lastNode:HeapNode = this.heap[this.heapSize];
            this.heap[index] = lastNode;
            this.taskMap[lastNode.taskID] = lastNode;

            var parentIndex:Number = (index - 1) >> 2; // Optimized division by 4
            if (index > 0 && this.heap[parentIndex].priority > lastNode.priority) {
                this.bubbleUp(index);
            } else {
                this.bubbleDown(index);
            }
        }
        delete this.taskMap[taskID];  // Remove from taskMap
    }

    // Updates the priority of a task
    public function update(taskID:String, newPriority:Number):Void {
        var node:HeapNode = this.taskMap[taskID];
        if (node == null) {
            return;  // Task does not exist
        }

        // Inline customIndexOf logic to find index
        var index:Number = -1;
        for (var i:Number = 0; i < this.heapSize; i++) {
            if (this.heap[i] == node) { // Compare object references
                index = i;
                break;
            }
        }
        if (index == -1) {
            return;  // Node not found
        }

        var oldPriority:Number = node.priority;
        node.priority = newPriority;

        if (newPriority < oldPriority) {
            this.bubbleUp(index);
        } else if (newPriority > oldPriority) {
            this.bubbleDown(index);
        }
        // No need to rebalance if priority is unchanged
    }

    // Extracts the minimum task from the heap
    public function extractMin():HeapNode {
        if (this.heapSize == 0) {
            return null;
        }
        var minNode:HeapNode = this.heap[0];
        this.heapSize--;
        if (this.heapSize > 0) {
            var lastNode:HeapNode = this.heap[this.heapSize];
            this.heap[0] = lastNode;
            this.taskMap[lastNode.taskID] = lastNode;
            this.bubbleDown(0);
        }
        delete this.taskMap[minNode.taskID];
        return minNode;
    }

    // Bubble up operation to maintain heap property
    private function bubbleUp(index:Number):Void {
        var node:HeapNode = this.heap[index];
        while (index > 0) {
            var parentIndex:Number = (index - 1) >> 2; // Division by 4 using bitwise shift
            var parentNode:HeapNode = this.heap[parentIndex];
            if (node.priority >= parentNode.priority) {
                break;  // Node is in correct position
            }
            this.heap[index] = parentNode;
            index = parentIndex;
        }
        this.heap[index] = node;
    }

    // Bubble down operation to maintain heap property
    private function bubbleDown(index:Number):Void {
        var node:HeapNode = this.heap[index];
        while (true) {
            var minIndex:Number = index;
            // Loop through all 4 children
            for (var i:Number = 1; i <= 4; i++) {
                var childIndex:Number = (index << 2) + i; // Multiplication by 4 using bitwise shift
                if (childIndex < this.heapSize) {
                    if (this.heap[childIndex].priority < this.heap[minIndex].priority) {
                        minIndex = childIndex;
                    }
                } else {
                    break; // No more children
                }
            }
            if (minIndex == index) {
                break; // Node is in correct position
            }
            // Swap with smallest child
            this.heap[index] = this.heap[minIndex];
            index = minIndex;
        }
        this.heap[index] = node;
    }
}
