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

/**
 * @class TaskMinHeap
 * @package org.flashNight.naki.DataStructures
 * @description 这是一个四叉最小堆（4-ary Min Heap）的实现，用于管理任务（Task）的优先级。
 *              通过预分配堆数组、内联化冒泡操作以及手动展开循环等优化手段，提高了堆的性能。
 */
class org.flashNight.naki.DataStructures.TaskMinHeap {
    private var heap:Array;       // 用于存储堆节点的数组
    private var taskMap:Object;   // 映射 taskID 到 HeapNode 对象，便于快速查找
    private var heapSize:Number;  // 当前堆的大小（节点数量）

    // D 被硬编码为 4，表示四叉堆（每个节点最多有 4 个子节点）

    /**
     * @constructor
     * @description 构造函数，初始化堆数组、任务映射表和堆大小。
     */
    public function TaskMinHeap() {
        this.heap = new Array(128); // 预分配堆数组大小，提高性能，避免频繁扩展
        this.taskMap = {};          // 初始化任务映射表为空对象
        this.heapSize = 0;          // 初始堆大小为 0
    }

    /**
     * @method insert
     * @description 向堆中插入一个新任务。如果任务已存在，则更新其优先级并重新平衡堆。
     * @param {String} taskID - 任务的唯一标识符
     * @param {Number} priority - 任务的优先级（数值越小，优先级越高）
     */
    public function insert(taskID:String, priority:Number):Void {
        var existingNode:HeapNode = this.taskMap[taskID];
        if (existingNode != null) {
            // 如果任务已存在，更新其优先级并重新平衡堆
            this.update(taskID, priority);
            return;
        }

        // 创建一个新的 HeapNode 节点
        var node:HeapNode = new HeapNode(taskID, priority);
        this.heap[this.heapSize] = node;    // 将新节点添加到堆的末尾
        this.taskMap[taskID] = node;        // 在映射表中记录 taskID 对应的节点
        var index:Number = this.heapSize;   // 当前节点的索引
        this.heapSize++;                     // 堆大小增加

        // 内联化的冒泡上升（bubbleUp）逻辑，用于维护堆的最小堆性质
        var currentIndex:Number = index;
        var currentNode:HeapNode = node;
        while (currentIndex > 0) {
            // 计算父节点的索引，四叉堆中父节点索引为 (currentIndex - 1) >> 2
            var parentIndex:Number = (currentIndex - 1) >> 2; // 相当于除以 4
            var parentNode:HeapNode = this.heap[parentIndex];
            if (currentNode.priority >= parentNode.priority) {
                break; // 当前节点已在正确位置，无需进一步交换
            }
            // 将父节点下移到当前节点的位置
            this.heap[currentIndex] = parentNode;
            this.taskMap[parentNode.taskID] = parentNode; // 更新映射表中父节点的引用
            currentIndex = parentIndex; // 更新当前索引为父节点索引，继续向上检查
        }
        this.heap[currentIndex] = currentNode; // 将当前节点放置在正确位置
    }

    /**
     * @method find
     * @description 根据 taskID 查找对应的 HeapNode 节点。
     * @param {String} taskID - 任务的唯一标识符
     * @returns {HeapNode} - 返回对应的 HeapNode 节点，如果不存在则返回 null
     */
    public function find(taskID:String):HeapNode {
        return this.taskMap[taskID];
    }

    /**
     * @method peekMin
     * @description 查看堆中的最小任务（优先级最高的任务），但不移除它。
     * @returns {HeapNode} - 返回堆顶的 HeapNode 节点，如果堆为空则返回 null
     */
    public function peekMin():HeapNode {
        if (this.heapSize == 0) {
            return null; // 堆为空，返回 null
        }
        return this.heap[0]; // 返回堆顶节点
    }

    /**
     * @method remove
     * @description 根据 taskID 从堆中移除指定的任务，并重新平衡堆。
     * @param {String} taskID - 任务的唯一标识符
     */
    public function remove(taskID:String):Void {
        var node:HeapNode = this.taskMap[taskID];
        if (node == null) {
            return;  // 任务不存在，直接返回
        }

        // 在堆数组中查找节点的索引
        var index:Number = -1;
        for (var i:Number = 0; i < this.heapSize; i++) {
            if (this.heap[i] == node) { // 比较对象引用
                index = i;
                break;
            }
        }
        if (index == -1) {
            return;  // 节点未找到，直接返回
        }

        this.heapSize--; // 堆大小减少
        if (index != this.heapSize) {  // 如果要移除的节点不是堆中的最后一个节点
            var lastNode:HeapNode = this.heap[this.heapSize]; // 获取最后一个节点
            this.heap[index] = lastNode; // 将最后一个节点移动到要移除的位置
            this.taskMap[lastNode.taskID] = lastNode; // 更新映射表中最后一个节点的引用

            // 计算父节点的索引
            var parentIndex:Number = (index - 1) >> 2; // 相当于除以 4
            if (index > 0 && this.heap[parentIndex].priority > lastNode.priority) {
                // 如果最后一个节点的优先级比父节点低，则需要进行冒泡上升
                var currentIndex:Number = index;
                var currentNode:HeapNode = lastNode;
                while (currentIndex > 0) {
                    var parentIdx:Number = (currentIndex - 1) >> 2; // 父节点索引
                    var parentN:HeapNode = this.heap[parentIdx];
                    if (currentNode.priority >= parentN.priority) {
                        break; // 当前节点已在正确位置
                    }
                    // 将父节点下移到当前节点的位置
                    this.heap[currentIndex] = parentN;
                    this.taskMap[parentN.taskID] = parentN; // 更新映射表中父节点的引用
                    currentIndex = parentIdx; // 更新当前索引为父节点索引，继续向上检查
                }
                this.heap[currentIndex] = currentNode; // 将当前节点放置在正确位置
            } else {
                // 否则，进行冒泡下降
                var currentIdx:Number = index;
                var currentN:HeapNode = lastNode;
                while (true) {
                    var minIdx:Number = currentIdx;
                    var baseChildIdx:Number = (currentIdx << 2); // 计算子节点的基准索引，相当于 currentIdx * 4

                    // 手动展开循环，比较四个子节点，找出最小的子节点
                    var childIdx1:Number = baseChildIdx + 1;
                    if (childIdx1 < this.heapSize) {
                        if (this.heap[childIdx1].priority < this.heap[minIdx].priority) {
                            minIdx = childIdx1;
                        }

                        var childIdx2:Number = childIdx1 + 1;
                        if (childIdx2 < this.heapSize) {
                            if (this.heap[childIdx2].priority < this.heap[minIdx].priority) {
                                minIdx = childIdx2;
                            }

                            var childIdx3:Number = childIdx2 + 1;
                            if (childIdx3 < this.heapSize) {
                                if (this.heap[childIdx3].priority < this.heap[minIdx].priority) {
                                    minIdx = childIdx3;
                                }

                                var childIdx4:Number = childIdx3 + 1;
                                if (childIdx4 < this.heapSize) {
                                    if (this.heap[childIdx4].priority < this.heap[minIdx].priority) {
                                        minIdx = childIdx4;
                                    }
                                }
                            }
                        }
                    }

                    if (minIdx == currentIdx) {
                        break; // 当前节点已在正确位置，无需进一步交换
                    }

                    // 将当前节点与最小的子节点交换
                    var smallestChild:HeapNode = this.heap[minIdx];
                    this.heap[currentIdx] = smallestChild;
                    this.taskMap[smallestChild.taskID] = smallestChild; // 更新映射表中子节点的引用
                    currentIdx = minIdx; // 更新当前索引为最小子节点索引，继续向下检查
                }
                this.heap[currentIdx] = currentN; // 将当前节点放置在正确位置
            }
        }
        delete this.taskMap[taskID];  // 从映射表中删除该任务
    }

    /**
     * @method update
     * @description 更新指定任务的优先级，并重新平衡堆。
     * @param {String} taskID - 任务的唯一标识符
     * @param {Number} newPriority - 新的优先级
     */
    public function update(taskID:String, newPriority:Number):Void {
        var node:HeapNode = this.taskMap[taskID];
        if (node == null) {
            return;  // 任务不存在，直接返回
        }

        // 在堆数组中查找节点的索引
        var index:Number = -1;
        for (var i:Number = 0; i < this.heapSize; i++) {
            if (this.heap[i] == node) { // 比较对象引用
                index = i;
                break;
            }
        }
        if (index == -1) {
            return;  // 节点未找到，直接返回
        }

        var oldPriority:Number = node.priority; // 记录旧的优先级
        node.priority = newPriority;            // 更新优先级

        if (newPriority < oldPriority) {
            // 如果新的优先级更高（数值更小），进行冒泡上升
            var currentIndexU:Number = index;
            var currentNodeU:HeapNode = node;
            while (currentIndexU > 0) {
                var parentIndexU:Number = (currentIndexU - 1) >> 2; // 父节点索引
                var parentNodeU:HeapNode = this.heap[parentIndexU];
                if (currentNodeU.priority >= parentNodeU.priority) {
                    break; // 当前节点已在正确位置
                }
                // 将父节点下移到当前节点的位置
                this.heap[currentIndexU] = parentNodeU;
                this.taskMap[parentNodeU.taskID] = parentNodeU; // 更新映射表中父节点的引用
                currentIndexU = parentIndexU; // 更新当前索引为父节点索引，继续向上检查
            }
            this.heap[currentIndexU] = currentNodeU; // 将当前节点放置在正确位置
        } else if (newPriority > oldPriority) {
            // 如果新的优先级更低（数值更大），进行冒泡下降
            var currentIdxD:Number = index;
            var currentNodeD:HeapNode = node;
            while (true) {
                var minIdxD:Number = currentIdxD;
                var baseChildIdxD:Number = (currentIdxD << 2); // 计算子节点的基准索引，相当于 currentIdxD * 4

                // 手动展开循环，比较四个子节点，找出最小的子节点
                var childIdx1D:Number = baseChildIdxD + 1;
                if (childIdx1D < this.heapSize) {
                    if (this.heap[childIdx1D].priority < this.heap[minIdxD].priority) {
                        minIdxD = childIdx1D;
                    }

                    var childIdx2D:Number = childIdx1D + 1;
                    if (childIdx2D < this.heapSize) {
                        if (this.heap[childIdx2D].priority < this.heap[minIdxD].priority) {
                            minIdxD = childIdx2D;
                        }

                        var childIdx3D:Number = childIdx2D + 1;
                        if (childIdx3D < this.heapSize) {
                            if (this.heap[childIdx3D].priority < this.heap[minIdxD].priority) {
                                minIdxD = childIdx3D;
                            }

                            var childIdx4D:Number = childIdx3D + 1;
                            if (childIdx4D < this.heapSize) {
                                if (this.heap[childIdx4D].priority < this.heap[minIdxD].priority) {
                                    minIdxD = childIdx4D;
                                }
                            }
                        }
                    }
                }

                if (minIdxD == currentIdxD) {
                    break; // 当前节点已在正确位置，无需进一步交换
                }

                // 将当前节点与最小的子节点交换
                var smallestChildD:HeapNode = this.heap[minIdxD];
                this.heap[currentIdxD] = smallestChildD;
                this.taskMap[smallestChildD.taskID] = smallestChildD; // 更新映射表中子节点的引用
                currentIdxD = minIdxD; // 更新当前索引为最小子节点索引，继续向下检查
            }
            this.heap[currentIdxD] = currentNodeD; // 将当前节点放置在正确位置
        }
        // 如果优先级未变化，无需重新平衡堆
    }

    /**
     * @method extractMin
     * @description 移除并返回堆中的最小任务（优先级最高的任务）。
     * @returns {HeapNode} - 返回被移除的最小任务节点，如果堆为空则返回 null
     */
    public function extractMin():HeapNode {
        if (this.heapSize == 0) {
            return null; // 堆为空，返回 null
        }
        var minNode:HeapNode = this.heap[0]; // 获取堆顶的最小节点
        this.heapSize--;                      // 堆大小减少
        if (this.heapSize > 0) {
            var lastNode:HeapNode = this.heap[this.heapSize]; // 获取最后一个节点
            this.heap[0] = lastNode;                         // 将最后一个节点移动到堆顶
            this.taskMap[lastNode.taskID] = lastNode;         // 更新映射表中最后一个节点的引用

            // 内联化的冒泡下降（bubbleDown）逻辑，手动展开循环以减少开销
            var currentIdxE:Number = 0;
            var currentNodeE:HeapNode = lastNode;
            while (true) {
                var minIdxE:Number = currentIdxE;
                var baseChildIdxE:Number = (currentIdxE << 2); // 计算子节点的基准索引，相当于 currentIdxE * 4

                // 手动展开循环，比较四个子节点，找出最小的子节点
                var childIdx1E:Number = baseChildIdxE + 1;
                if (childIdx1E < this.heapSize) {
                    if (this.heap[childIdx1E].priority < this.heap[minIdxE].priority) {
                        minIdxE = childIdx1E;
                    }

                    var childIdx2E:Number = childIdx1E + 1;
                    if (childIdx2E < this.heapSize) {
                        if (this.heap[childIdx2E].priority < this.heap[minIdxE].priority) {
                            minIdxE = childIdx2E;
                        }

                        var childIdx3E:Number = childIdx2E + 1;
                        if (childIdx3E < this.heapSize) {
                            if (this.heap[childIdx3E].priority < this.heap[minIdxE].priority) {
                                minIdxE = childIdx3E;
                            }

                            var childIdx4E:Number = childIdx3E + 1;
                            if (childIdx4E < this.heapSize) {
                                if (this.heap[childIdx4E].priority < this.heap[minIdxE].priority) {
                                    minIdxE = childIdx4E;
                                }
                            }
                        }
                    }
                }

                if (minIdxE == currentIdxE) {
                    break; // 当前节点已在正确位置，无需进一步交换
                }

                // 将当前节点与最小的子节点交换
                var smallestChildE:HeapNode = this.heap[minIdxE];
                this.heap[currentIdxE] = smallestChildE;
                this.taskMap[smallestChildE.taskID] = smallestChildE; // 更新映射表中子节点的引用
                currentIdxE = minIdxE; // 更新当前索引为最小子节点索引，继续向下检查
            }
            this.heap[currentIdxE] = currentNodeE; // 将当前节点放置在正确位置
        }
        delete this.taskMap[minNode.taskID]; // 从映射表中删除被移除的最小节点
        return minNode; // 返回被移除的最小节点
    }
}
