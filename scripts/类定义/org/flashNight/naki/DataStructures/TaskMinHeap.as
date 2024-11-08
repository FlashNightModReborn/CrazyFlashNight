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
    private var heap:Array;       // 用于存储堆中节点的数组
    private var taskMap:Object;   // 用于快速查找任务的映射
    private var heapSize:Number;  // 当前堆的大小

    // 构造函数，初始化堆和任务映射
    public function TaskMinHeap() {
        this.heap = [];
        this.taskMap = {};
        this.heapSize = 0;
    }

    // 插入新任务到堆中
    public function insert(taskID:String, priority:Number):Void {
        var existingNode:HeapNode = this.taskMap[taskID];
        if (existingNode != null) {
            // Update the existing task's priority and rebalance the heap
            //  trace("Insert detected duplicate taskID, updating priority for " + taskID);
            this.update(taskID, priority);
            return;
        }
        
        var node:HeapNode = new HeapNode(taskID, priority);
        this.heap[this.heapSize] = node;
        this.taskMap[taskID] = node;
        this.bubbleUp(this.heapSize);
        this.heapSize++;
    }


    // 根据 taskID 查找任务
    public function find(taskID:String):HeapNode {
        return this.taskMap[taskID];
    }

    // 查看堆顶任务
    public function peekMin():HeapNode {
        if (this.heapSize == 0) {
            return null;
        }
        return this.heap[0];
    }

    // 根据 taskID 移除特定任务
    public function remove(taskID:String):Void {
        var node:HeapNode = this.taskMap[taskID];
        if (node == null) {
            return;  // 如果任务不存在，直接返回
        }

        var index:Number = this.findIndexByTaskID(taskID);
        //  trace("Removing taskID: " + taskID + " at index: " + index);
        if (index == -1) {
            return;  // 如果找不到节点，直接返回
        }

        this.heapSize--;
        if (index != this.heapSize) {  // 如果不是最后一个节点
            var lastNode:HeapNode = this.heap[this.heapSize];
            this.heap[index] = lastNode;
            this.taskMap[lastNode.taskID] = lastNode;
            //  trace("Replaced with lastNode: " + lastNode.taskID + " with priority: " + lastNode.priority);

            var parentIndex:Number = (index - 1) >> 1;
            if (parentIndex >= 0 && this.heap[parentIndex].priority > lastNode.priority) {
                //  trace("Bubbling up node: " + lastNode.taskID);
                this.bubbleUp(index);
            } else {
                //  trace("Bubbling down node: " + lastNode.taskID);
                this.bubbleDown(index);
            }
        }
        delete this.taskMap[taskID];  // 删除 taskMap 中的对应项
        //  trace("Task removed: " + taskID);
    }

    // 更新任务的优先级
    public function update(taskID:String, newPriority:Number):Void {
        var node:HeapNode = this.taskMap[taskID];
        if (node == null) {
            return;  // 如果任务不存在，直接返回
        }

        var index:Number = this.findIndexByTaskID(taskID);
        //  trace("Updating taskID: " + taskID + " at index: " + index + " from priority: " + node.priority + " to: " + newPriority);
        if (index == -1) {
            return;  // 如果找不到节点，直接返回
        }

        var oldPriority:Number = node.priority;
        node.priority = newPriority;

        if (newPriority < oldPriority) {
            //  trace("Bubbling up node: " + taskID);
            this.bubbleUp(index);
        } else if (newPriority > oldPriority) {
            //  trace("Bubbling down node: " + taskID);
            this.bubbleDown(index);
        }
        // 如果优先级未改变，则无需重新平衡
    }

    // 当任务被取出执行
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

    // 上浮操作，维护堆的性质
    private function bubbleUp(index:Number):Void {
        var node:HeapNode = this.heap[index];
        while (index > 0) {
            var parentIndex:Number = (index - 1) >> 1;
            var parentNode:HeapNode = this.heap[parentIndex];
            if (node.priority >= parentNode.priority) {
                break;  // 如果当前节点的优先级不小于父节点，退出循环
            }
            this.heap[index] = parentNode;  // 上浮当前节点
            index = parentIndex;
        }
        this.heap[index] = node;  // 将节点放在最终确定的位置
    }

    // 下沉操作，维护堆的性质
    private function bubbleDown(index:Number):Void {
        var node:HeapNode = this.heap[index];
        var halfSize:Number = this.heapSize >> 1; // 只需要遍历到最后一个父节点
        while (index < halfSize) {
            var left:Number = (index << 1) + 1;
            var right:Number = left + 1;
            var smallest:Number = left;

            if (right < this.heapSize && this.heap[right].priority < this.heap[left].priority) {
                smallest = right;
            }

            if (this.heap[smallest].priority >= node.priority) {
                break;  // 如果当前节点已经是最小，退出循环
            }

            this.heap[index] = this.heap[smallest];  // 下沉节点
            index = smallest;
        }
        this.heap[index] = node;  // 将节点放在最终确定的位置
    }

    // 自定义的 indexOf 方法，用于 AS2
    private function customIndexOf(node:HeapNode):Number {
        for (var i:Number = 0; i < this.heapSize; i++) {
            if (this.heap[i] == node) { // 使用 == 比较对象引用
                return i;
            }
        }
        return -1; // 如果未找到，返回-1
    }

    // 查找任务在堆中的索引
    private function findIndexByTaskID(taskID:String):Number {
        var node:HeapNode = this.taskMap[taskID];
        if (node == null) {
            return -1;
        }
        return this.customIndexOf(node);
    }
}
