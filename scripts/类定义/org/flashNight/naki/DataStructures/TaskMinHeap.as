import org.flashNight.naki.DataStructures.*;

/**
 * @class TaskMinHeap
 * @package org.flashNight.naki.DataStructures
 * @description 这是一个四叉最小堆（4-ary Min Heap）的实现，用于管理任务（Task）的优先级。
 *              通过预分配堆数组、内联化冒泡操作、手动展开循环、减少局部变量、优化自增操作以及缓存优先级等优化手段，
 *              进一步减少逻辑判断和变量声明带来的开销，提高了堆的性能。
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
        this.heapSize++;                    // 堆大小增加

        // 内联化的冒泡上升（bubbleUp）逻辑，用于维护堆的最小堆性质
        var currentIndex:Number = index;
        var currentNode:HeapNode = node;
        var currentPriority:Number = currentNode.priority; // 缓存当前节点的优先级

        var parentIndex:Number;
        var parentNode:HeapNode;
        var parentPriority:Number;

        while (currentIndex > 0) {
            // 计算父节点的索引，四叉堆中父节点索引为 (currentIndex - 1) >> 2
            parentIndex = (currentIndex - 1) >> 2; // 相当于除以 4
            parentNode = this.heap[parentIndex];
            parentPriority = parentNode.priority; // 缓存父节点的优先级

            if (currentPriority >= parentPriority) {
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
            var lastPriority:Number = lastNode.priority; // 缓存最后一个节点的优先级

            if (index > 0 && this.heap[parentIndex].priority > lastPriority) {
                // 如果最后一个节点的优先级更高（数值更小），进行冒泡上升
                var currentIndex:Number = index;
                var currentNode:HeapNode = lastNode;
                var currentPriority:Number = lastPriority; // 缓存当前节点的优先级

                var parentIdx:Number;
                var parentN:HeapNode;
                var parentPriorityU:Number;

                while (currentIndex > 0) {
                    parentIdx = (currentIndex - 1) >> 2; // 父节点索引
                    parentN = this.heap[parentIdx];
                    parentPriorityU = parentN.priority; // 缓存父节点的优先级

                    if (currentPriority >= parentPriorityU) {
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
                var currentNode:HeapNode = lastNode;
                var currentPriority:Number = lastPriority; // 缓存当前节点的优先级

                var minIdx:Number;
                var baseChildIdx:Number;
                var remaining:Number;
                var childIdx:Number;
                var childNode:HeapNode;
                var childPriority:Number;
                var minPriority:Number;

                while (true) {
                    minIdx = currentIdx;
                    baseChildIdx = (currentIdx << 2); // currentIdx * 4

                    // 计算剩余元素数量
                    remaining = this.heapSize - baseChildIdx - 1;

                    minPriority = currentPriority;

                    // 手动展开所有可能的子节点比较，按照子节点数量从多到少的顺序，减少逻辑判断次数
                    if (remaining >= 4) {
                        // 子节点数量为 4
                        childIdx = baseChildIdx + 1;

                        // 比较第一个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }

                        // 比较第二个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }

                        // 比较第三个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }

                        // 比较第四个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }
                    } else if (remaining == 3) {
                        // 子节点数量为 3
                        childIdx = baseChildIdx + 1;

                        // 比较第一个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }

                        // 比较第二个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }

                        // 比较第三个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }
                    } else if (remaining == 2) {
                        // 子节点数量为 2
                        childIdx = baseChildIdx + 1;

                        // 比较第一个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }

                        // 比较第二个子节点
                        childNode = this.heap[childIdx++];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx - 1;
                            minPriority = childPriority;
                        }
                    } else if (remaining == 1) {
                        // 子节点数量为 1
                        childIdx = baseChildIdx + 1;

                        // 比较唯一的子节点
                        childNode = this.heap[childIdx];
                        childPriority = childNode.priority;
                        if (childPriority < minPriority) {
                            minIdx = childIdx;
                            minPriority = childPriority;
                        }
                    } else {
                        // 无子节点，退出循环
                        break;
                    }

                    if (minIdx == currentIdx) {
                        break; // 当前节点已在正确位置，无需进一步交换
                    }

                    // 将当前节点与最小的子节点交换
                    var smallestChild:HeapNode = this.heap[minIdx];
                    this.heap[currentIdx] = smallestChild;
                    this.taskMap[smallestChild.taskID] = smallestChild; // 更新映射表中子节点的引用
                    currentIdx = minIdx; // 更新当前索引为最小子节点索引，继续向下检查
                    currentPriority = minPriority; // 更新当前节点的优先级
                }
                this.heap[currentIdx] = currentNode; // 将当前节点放置在正确位置
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
            var currentIndex:Number = index;
            var currentNode:HeapNode = node;
            var currentPriority:Number = newPriority; // 缓存当前节点的优先级

            var parentIndex:Number;
            var parentNode:HeapNode;
            var parentPriority:Number;

            while (currentIndex > 0) {
                parentIndex = (currentIndex - 1) >> 2; // 父节点索引
                parentNode = this.heap[parentIndex];
                parentPriority = parentNode.priority; // 缓存父节点的优先级

                if (currentPriority >= parentPriority) {
                    break; // 当前节点已在正确位置
                }

                // 将父节点下移到当前节点的位置
                this.heap[currentIndex] = parentNode;
                this.taskMap[parentNode.taskID] = parentNode; // 更新映射表中父节点的引用
                currentIndex = parentIndex; // 更新当前索引为父节点索引，继续向上检查
            }
            this.heap[currentIndex] = currentNode; // 将当前节点放置在正确位置
        } else if (newPriority > oldPriority) {
            // 如果新的优先级更低（数值更大），进行冒泡下降
            var currentIdx:Number = index;
            var currentNode:HeapNode = node;
            var currentPriority:Number = newPriority; // 缓存当前节点的优先级

            var minIdx:Number;
            var baseChildIdx:Number;
            var remaining:Number;
            var childIdx:Number;
            var childNode:HeapNode;
            var childPriority:Number;
            var minPriority:Number;

            while (true) {
                minIdx = currentIdx;
                baseChildIdx = (currentIdx << 2); // currentIdx * 4

                // 计算剩余元素数量
                remaining = this.heapSize - baseChildIdx - 1;

                minPriority = currentPriority;

                // 手动展开所有可能的子节点比较，按照子节点数量从多到少的顺序，减少逻辑判断次数
                if (remaining >= 4) {
                    // 子节点数量为 4
                    childIdx = baseChildIdx + 1;

                    // 比较第一个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第二个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第三个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第四个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }
                } else if (remaining == 3) {
                    // 子节点数量为 3
                    childIdx = baseChildIdx + 1;

                    // 比较第一个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第二个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第三个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }
                } else if (remaining == 2) {
                    // 子节点数量为 2
                    childIdx = baseChildIdx + 1;

                    // 比较第一个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第二个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }
                } else if (remaining == 1) {
                    // 子节点数量为 1
                    childIdx = baseChildIdx + 1;

                    // 比较唯一的子节点
                    childNode = this.heap[childIdx];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx;
                        minPriority = childPriority;
                    }
                } else {
                    // 无子节点，退出循环
                    break;
                }

                if (minIdx == currentIdx) {
                    break; // 当前节点已在正确位置，无需进一步交换
                }

                // 将当前节点与最小的子节点交换
                var smallestChild:HeapNode = this.heap[minIdx];
                this.heap[currentIdx] = smallestChild;
                this.taskMap[smallestChild.taskID] = smallestChild; // 更新映射表中子节点的引用
                currentIdx = minIdx; // 更新当前索引为最小子节点索引，继续向下检查
                currentPriority = minPriority; // 更新当前节点的优先级
            }
            this.heap[currentIdx] = currentNode; // 将当前节点放置在正确位置
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
        this.heapSize--;                     // 堆大小减少
        if (this.heapSize > 0) {
            var lastNode:HeapNode = this.heap[this.heapSize]; // 获取最后一个节点
            this.heap[0] = lastNode;                         // 将最后一个节点移动到堆顶
            this.taskMap[lastNode.taskID] = lastNode;        // 更新映射表中最后一个节点的引用

            // 内联化的冒泡下降（bubbleDown）逻辑，手动展开所有可能的子节点比较，减少逻辑判断次数
            var currentIdx:Number = 0;
            var currentNode:HeapNode = lastNode;
            var currentPriority:Number = lastNode.priority; // 缓存当前节点的优先级

            var minIdx:Number;
            var baseChildIdx:Number;
            var remaining:Number;
            var childIdx:Number;
            var childNode:HeapNode;
            var childPriority:Number;
            var minPriority:Number;

            while (true) {
                minIdx = currentIdx;
                baseChildIdx = (currentIdx << 2); // currentIdx * 4

                // 计算剩余元素数量
                remaining = this.heapSize - baseChildIdx - 1;

                minPriority = currentPriority;

                // 手动展开所有可能的子节点比较，按照子节点数量从多到少的顺序，减少逻辑判断次数
                if (remaining >= 4) {
                    // 子节点数量为 4
                    childIdx = baseChildIdx + 1;

                    // 比较第一个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第二个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第三个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第四个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }
                } else if (remaining == 3) {
                    // 子节点数量为 3
                    childIdx = baseChildIdx + 1;

                    // 比较第一个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第二个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第三个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }
                } else if (remaining == 2) {
                    // 子节点数量为 2
                    childIdx = baseChildIdx + 1;

                    // 比较第一个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }

                    // 比较第二个子节点
                    childNode = this.heap[childIdx++];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx - 1;
                        minPriority = childPriority;
                    }
                } else if (remaining == 1) {
                    // 子节点数量为 1
                    childIdx = baseChildIdx + 1;

                    // 比较唯一的子节点
                    childNode = this.heap[childIdx];
                    childPriority = childNode.priority;
                    if (childPriority < minPriority) {
                        minIdx = childIdx;
                        minPriority = childPriority;
                    }
                } else {
                    // 无子节点，退出循环
                    break;
                }

                if (minIdx == currentIdx) {
                    break; // 当前节点已在正确位置，无需进一步交换
                }

                // 将当前节点与最小的子节点交换
                var smallestChild:HeapNode = this.heap[minIdx];
                this.heap[currentIdx] = smallestChild;
                this.taskMap[smallestChild.taskID] = smallestChild; // 更新映射表中子节点的引用
                currentIdx = minIdx; // 更新当前索引为最小子节点索引，继续向下检查
                currentPriority = minPriority; // 更新当前节点的优先级
            }
            this.heap[currentIdx] = currentNode; // 将当前节点放置在正确位置
        }
        delete this.taskMap[minNode.taskID]; // 从映射表中删除被移除的最小节点
        return minNode; // 返回被移除的最小节点
    }
}













