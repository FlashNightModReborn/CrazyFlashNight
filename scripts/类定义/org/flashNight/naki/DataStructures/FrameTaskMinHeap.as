/*

### 概述

`FrameTaskMinHeap` 类通过升级为 **4-叉堆** 结构，大幅提升了任务调度系统的性能。在传统的 **二叉堆** 基础上，4-叉堆每个节点最多有 4 个子节点，从而减少堆的高度，在插入和删除操作中减少了比较和调整的次数。此外，该类还引入了一系列针对性能的优化：

1. **循环展开**：在处理堆节点的调整操作（如 `bubbleUp` 和 `sinkDown`）时，对固定次数的循环进行了手动展开，减少了循环控制的开销。
2. **逻辑分支优化**：通过提前退出循环或减少不必要的条件判断，降低了分支预测失败的可能性。
3. **链式赋值交换**：在堆中进行节点交换时，使用链式赋值的方式，避免使用临时变量，从而降低内存分配的开销。
4. **节点池复用**：引入了 `nodePool` 以复用 `TaskIDNode` 实例，从而显著减少了频繁创建和销毁对象所带来的垃圾回收压力。
5. **属性访问优化**：在方法内部将 `this` 引用的对象赋值为局部变量，减少属性访问的开销。
6. **延迟堆平衡**：仅在需要时对堆进行重新平衡，避免了不必要的调整操作，进一步提升了效率。

### 类的适用场景

该类特别适合需要 **高任务吞吐量** 和 **低延迟** 的场景，例如：
- 游戏中的帧调度系统
- 动画的定时任务管理
- 高效的事件触发机制

然而，由于该类采用了较多复杂的性能优化技巧，其代码的可读性和可维护性有所下降。建议在实际应用中，结合注释和测试用例，平衡性能需求与代码复杂度。

*/
import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.FrameTaskMinHeap {
    private var heap:Array;                     // 存储4叉堆中的帧索引
    private var frameMap:Object;                // 映射帧索引到任务链表
    private var frameIndexToHeapIndex:Object;   // 映射帧索引到堆中的索引
    public var currentFrame:Number;             // 当前帧数
    private var nodePool:Array;                 // 可复用的TaskIDNode实例池
    private var poolSize:Number;                // 节点池中当前节点数量
    private var heapSize:Number;                // 堆的当前大小

    // D固定为4，表示4叉堆（每个节点最多有4个子节点）

    /**
     * Constructor: 初始化4叉堆及相关结构
     */
    public function FrameTaskMinHeap() {
        this.heap = new Array(128); // 预分配堆数组以提升性能
        this.frameMap = {};
        this.frameIndexToHeapIndex = {};
        this.currentFrame = 0;
        this.nodePool = [];
        this.poolSize = 0;
        this.heapSize = 0;

        // 循环展开，批量添加节点到节点池中
        var i:Number = 0;
        while (i < 128) {
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            i += 4;
        }
    }


    /**
     * 查询节点池的大小
     */
    public function getNodePoolSize():Number {
        return this.poolSize;
    }

    /**
     * 向节点池中添加指定数量的空闲节点
     * @param size 要添加的节点数量
     */
    public function fillNodePool(size:Number):Void {
        var n:Number = Math.floor(size / 8); // 每组包含 8 次操作
        var remainder:Number = size % 8; // 处理不足 8 次的剩余部分

        // 处理剩余部分
        switch (remainder) {
            case 7: this.nodePool[this.poolSize++] = new TaskIDNode(null);
            case 6: this.nodePool[this.poolSize++] = new TaskIDNode(null);
            case 5: this.nodePool[this.poolSize++] = new TaskIDNode(null);
            case 4: this.nodePool[this.poolSize++] = new TaskIDNode(null);
            case 3: this.nodePool[this.poolSize++] = new TaskIDNode(null);
            case 2: this.nodePool[this.poolSize++] = new TaskIDNode(null);
            case 1: this.nodePool[this.poolSize++] = new TaskIDNode(null);
        }

        // 处理完整的 8 次分组
        while (n-- > 0) {
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
        }
    }


    /**
     * 减少节点池的大小
     * @param size 新的节点池大小
     */
    public function trimNodePool(size:Number):Void {
        if (this.poolSize > size) {
            // 释放多余节点的引用，允许 GC 回收
            var pool:Array = this.nodePool;
            for (var i:Number = size; i < this.poolSize; i++) {
                pool[i] = null;
            }
            this.poolSize = size;
        }
    }

    /**
     * [FIX v1.8] 释放一个已重置的节点回到堆节点池。
     * 用于跨池回收：CerberusScheduler.recycleExpiredNode 根据 ownerType
     * 将来自 minHeap 的节点（ownerType==4）归还到此池，而非时间轮池。
     *
     * @param node 已调用过 reset() 的节点
     */
    public function releaseNode(node:TaskIDNode):Void {
        this.nodePool[this.poolSize++] = node;
    }

    /**
     * 调度在指定延迟后执行的新任务
     * @param taskID 任务的唯一标识符
     * @param delay 延迟的帧数
     */
    public function insert(taskID:String, delay:Number):Void {
        var frameIndex:Number = this.currentFrame + delay; // 计算任务应执行的帧索引
        var locFrameMap = this.frameMap;
        var linkedList = locFrameMap[frameIndex];

        // 如果该帧索引还没有任务，需插入到堆中
        if (!linkedList) {

            var locHeap = this.heap;
            var locFrameIndexToHeapIndex = this.frameIndexToHeapIndex;
            var heapIndex:Number = this.heapSize++;
            linkedList = locFrameMap[frameIndex] = new TaskIDLinkedList(); // 创建新的任务链表
            locHeap[heapIndex] = frameIndex; // 将帧索引插入堆的末尾
            
            locFrameIndexToHeapIndex[frameIndex] = heapIndex; // 更新帧索引到堆索引的映射

            // 内联的bubbleUp操作，使用循环展开和逻辑分支优化
            var currentIndex:Number = heapIndex;
            var currentValue:Number = frameIndex;

            var parentIndex:Number;
            var parentValue:Number;

            while (currentIndex > 0) {
                // 使用位运算快速计算父节点索引，等同于Math.floor((currentIndex - 1) / 4)
                parentIndex = (currentIndex - 1) >> 2; 
                parentValue = locHeap[parentIndex];

                if (currentValue >= parentValue) {
                    break; // 当前节点已在正确位置，无需继续
                }

                // 延迟写入bubbleUp: 只移动父节点下来，currentValue最终写入正确位置
                // 链式赋值读取parent并写入current，结果用于更新映射
                locFrameIndexToHeapIndex[locHeap[currentIndex] = locHeap[parentIndex]] = currentIndex;

                // 更新currentIndex到parentIndex，继续向上调整
                currentIndex = parentIndex;
            }

            // 最终将当前值放置在正确位置，并更新映射
            locHeap[currentIndex] = currentValue;
            locFrameIndexToHeapIndex[currentValue] = currentIndex;
        }

        // 从节点池中获取一个节点
        var newNode:TaskIDNode;
        if (this.poolSize > 0) {
            newNode = TaskIDNode(this.nodePool[--this.poolSize]); // 从池中弹出一个节点
            newNode.reset(taskID); // 重置节点状态
        } else {
            newNode = new TaskIDNode(taskID); // 如果池中无可用节点，则新建
        }

        // 设置节点的slotIndex并将其添加到对应帧的任务链表中
        newNode.slotIndex = frameIndex;
        linkedList.appendNode(newNode);
    }

    /**
     * 直接插入一个现有节点并在指定延迟后调度
     * @param node 要插入的TaskIDNode节点
     * @param delay 延迟的帧数
     */
    public function insertNode(node:TaskIDNode, delay:Number):Void {
        var frameIndex:Number = this.currentFrame + delay;
        var locFrameMap = this.frameMap;
        var linkedList = locFrameMap[frameIndex];
        // 如果该帧索引尚未存在，则需要将其插入堆中
        if (!linkedList) {
            var locHeap = this.heap;
            var locFrameIndexToHeapIndex = this.frameIndexToHeapIndex;
            var heapIndex:Number = this.heapSize++;

            linkedList = locFrameMap[frameIndex] = new TaskIDLinkedList();
            locHeap[heapIndex] = frameIndex;
            
            locFrameIndexToHeapIndex[frameIndex] = heapIndex;

            // 内联的bubbleUp操作，优化同上
            var currentIndex:Number = heapIndex;
            var currentValue:Number = frameIndex;

            var parentIndex:Number;
            var parentValue:Number;

            while (currentIndex > 0) {
                parentIndex = (currentIndex - 1) >> 2;
                parentValue = locHeap[parentIndex];

                if (currentValue >= parentValue) {
                    break;
                }

                // 延迟写入bubbleUp: 只移动父节点下来，currentValue最终写入正确位置
                // 链式赋值读取parent并写入current，结果用于更新映射
                locFrameIndexToHeapIndex[locHeap[currentIndex] = locHeap[parentIndex]] = currentIndex;

                // 更新currentIndex到parentIndex
                currentIndex = parentIndex;
            }

            // 将当前值放在正确位置，并更新映射
            locHeap[currentIndex] = currentValue;
            locFrameIndexToHeapIndex[currentValue] = currentIndex;
        }

        // 设置节点的slotIndex并将其添加到对应帧的任务链表中
        node.slotIndex = frameIndex;
        linkedList.appendNode(node);
    }

    /**
     * 通过任务ID添加一个定时器，创建一个新节点
     * @param taskID 任务的唯一标识符
     * @param delay 延迟的帧数
     * @return 新创建或复用的TaskIDNode节点
     */
    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        var node:TaskIDNode;
        if (this.poolSize > 0) {
            node = TaskIDNode(this.nodePool[--this.poolSize]); // 从池中弹出一个节点
            node.reset(taskID); // 重置节点状态
        } else {
            node = new TaskIDNode(taskID); // 如果池中无可用节点，则新建
        }

        // 调度任务，与insert方法类似
        var frameIndex:Number = this.currentFrame + delay;
        var locFrameMap = this.frameMap;
        var linkedList = locFrameMap[frameIndex];

        if (!linkedList) {
            var locHeap = this.heap;
            var locFrameIndexToHeapIndex = this.frameIndexToHeapIndex;
            var heapIndex:Number = this.heapSize++;

            linkedList = locFrameMap[frameIndex] = new TaskIDLinkedList();
            locHeap[heapIndex] = frameIndex;
            
            locFrameIndexToHeapIndex[frameIndex] = heapIndex;

            // 内联的bubbleUp操作，优化同上
            var currentIndex:Number = heapIndex;
            var currentValue:Number = frameIndex;

            var parentIndex:Number;
            var parentValue:Number;

            while (currentIndex > 0) {
                parentIndex = (currentIndex - 1) >> 2;
                parentValue = locHeap[parentIndex];

                if (currentValue >= parentValue) {
                    break;
                }

                // 延迟写入bubbleUp: 只移动父节点下来，currentValue最终写入正确位置
                // 链式赋值读取parent并写入current，结果用于更新映射
                locFrameIndexToHeapIndex[locHeap[currentIndex] = locHeap[parentIndex]] = currentIndex;

                // 更新currentIndex到parentIndex
                currentIndex = parentIndex;
            }

            // 将当前值放在正确位置，并更新映射
            locHeap[currentIndex] = currentValue;
            locFrameIndexToHeapIndex[currentValue] = currentIndex;
        }

        // 设置节点的slotIndex并将其添加到对应帧的任务链表中
        node.slotIndex = frameIndex;
        linkedList.appendNode(node);

        return node;
    }

    /**
     * 直接使用节点添加一个定时器
     * @param node 要添加的TaskIDNode节点
     * @param delay 延迟的帧数
     * @return 添加后的TaskIDNode节点
     */
    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        var frameIndex:Number = this.currentFrame + delay;
        var locFrameMap = this.frameMap;
        var linkedList = locFrameMap[frameIndex];

        // 如果该帧索引尚未存在，则需插入到堆中
        if (!linkedList) {
            var locHeap = this.heap;
            var locFrameIndexToHeapIndex = this.frameIndexToHeapIndex;
            var heapIndex:Number = this.heapSize++;

            linkedList = locFrameMap[frameIndex] = new TaskIDLinkedList();
            locHeap[heapIndex] = frameIndex;
            
            locFrameIndexToHeapIndex[frameIndex] = heapIndex;

            // 内联的bubbleUp操作，优化同上
            var currentIndex:Number = heapIndex;
            var currentValue:Number = frameIndex;

            var parentIndex:Number;
            var parentValue:Number;

            while (currentIndex > 0) {
                parentIndex = (currentIndex - 1) >> 2;
                parentValue = locHeap[parentIndex];

                if (currentValue >= parentValue) {
                    break;
                }

                // 延迟写入bubbleUp: 只移动父节点下来，currentValue最终写入正确位置
                // 链式赋值读取parent并写入current，结果用于更新映射
                locFrameIndexToHeapIndex[locHeap[currentIndex] = locHeap[parentIndex]] = currentIndex;

                // 更新currentIndex到parentIndex
                currentIndex = parentIndex;
            }

            // 将当前值放在正确位置，并更新映射
            locHeap[currentIndex] = currentValue;
            locFrameIndexToHeapIndex[currentValue] = currentIndex;
        }

        // 设置节点的slotIndex并将其添加到对应帧的任务链表中
        node.slotIndex = frameIndex;
        linkedList.appendNode(node);

        return node;
    }

    /**
     * 通过任务ID从调度系统中移除任务
     * @param taskID 要移除的任务的唯一标识符
     */
    public function removeById(taskID:String):Void {
        var node:TaskIDNode = findNodeById(taskID); // 查找对应的节点
        if (node != null) {
            removeNode(node); // 如果找到，则移除
        }
    }

    /**
     * 直接从调度系统中移除一个节点
     * @param node 要移除的TaskIDNode节点
     */
    public function removeDirectly(node:TaskIDNode):Void {
        removeNode(node);
    }

    /**
     * 核心方法：移除一个节点，并处理链表和堆的更新
     * @param node 要移除的TaskIDNode节点
     *
     * [FIX v1.6] 添加防御性检查：当 frameIndex 对应的 frameMap 条目不存在时，
     * 说明该帧的任务列表已被 extractTasksAtMinFrame() 提取并删除。
     * 这种情况发生在任务回调中调用 removeTask() 删除自身时。
     * 此时只需回收节点到节点池，无需进行堆操作。
     */
    public function removeNode(node:TaskIDNode):Void {
        var frameIndex:Number = node.slotIndex; // 获取节点所属的帧索引
        var locFrameMap:Object = this.frameMap;
        var list:TaskIDLinkedList = locFrameMap[frameIndex];

        // [FIX v1.6] 防御性检查：如果 frameIndex 已被 extractTasksAtMinFrame 删除
        // 则 list 为 undefined，此时节点实际上已不在堆中，只需回收即可
        if (list == undefined) {
            // 回收节点，准备复用
            node.reset(null);
            this.nodePool[this.poolSize++] = node;
            return;
        }

        list.remove(node); // 从链表中移除节点

        if (list.getFirst() == null) {
            // 如果该帧索引下没有更多任务，需从堆中移除该帧索引
            var locHeap:Array = this.heap;
            var locFrameIndexToHeapIndex:Object = this.frameIndexToHeapIndex;
            var heapIndex:Number = locFrameIndexToHeapIndex[frameIndex];
            var lastIndex:Number = --this.heapSize; // 获取堆的最后一个元素索引
            var lastValue:Number = locHeap[lastIndex];

            if (heapIndex != lastIndex) {
                locHeap[heapIndex] = lastValue; // 将最后一个元素移动到要删除的位置
                locFrameIndexToHeapIndex[lastValue] = heapIndex; // 更新映射
            }

            // 移除最后一个元素的引用
            locHeap[lastIndex] = null;
            delete locFrameIndexToHeapIndex[frameIndex];

            if (heapIndex < lastIndex) {
                // 如果移动后的元素不是堆末尾元素，需重新平衡堆
                var currentIndex:Number = heapIndex;
                var currentValue:Number = locHeap[currentIndex];

                // 首先检查是否需要bubbleUp（移动的元素可能比父节点小）
                var needBubbleUp:Boolean = false;
                if (currentIndex > 0) {
                    var parentIndex:Number = (currentIndex - 1) >> 2;
                    if (currentValue < locHeap[parentIndex]) {
                        needBubbleUp = true;
                    }
                }

                if (needBubbleUp) {
                    // 执行bubbleUp（延迟写入模式）
                    var parentIdx:Number;
                    var parentVal:Number;

                    while (currentIndex > 0) {
                        parentIdx = (currentIndex - 1) >> 2;
                        parentVal = locHeap[parentIdx];

                        if (currentValue >= parentVal) {
                            break;
                        }

                        // 延迟写入bubbleUp: 只移动父节点下来
                        locFrameIndexToHeapIndex[locHeap[currentIndex] = locHeap[parentIdx]] = currentIndex;
                        currentIndex = parentIdx;
                    }

                    // 最终将当前值放置在正确位置
                    locHeap[currentIndex] = currentValue;
                    locFrameIndexToHeapIndex[currentValue] = currentIndex;
                } else {
                    // 执行sinkDown
                    var minIndex:Number;
                    var baseChildIndex:Number;
                    var remaining:Number;
                    var childIndex:Number;
                    var childValue:Number;
                    var minValue:Number;
                    // lastIndex 位置已被清空，有效最大索引是 lastIndex - 1
                    var maxValidIndex:Number = lastIndex - 1;

                    while (true) {
                        minIndex = currentIndex;
                        baseChildIndex = (currentIndex << 2); // 相当于currentIndex * 4
                        remaining = maxValidIndex - baseChildIndex;

                        minValue = currentValue;

                        childIndex = baseChildIndex;

                        if (remaining >= 4) { // 当前节点有4个子节点
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        } else if (remaining == 3) { // 当前节点有3个子节点
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        } else if (remaining == 2) { // 当前节点有2个子节点
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        } else if (remaining == 1) { // 当前节点有1个子节点
                            minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        }


                        if (minIndex == currentIndex) {
                            break; // 当前节点已在正确位置
                        }

                        // 使用链式赋值交换heap[currentIndex]和heap[minIndex]
                        // a = b + (b = a) - a 模式触发AVM1寄存器优化
                        var heapCurrentIndexCache = locHeap[currentIndex];
                        var locCurrentIndex = locHeap[currentIndex] = locHeap[minIndex] + (locHeap[minIndex] = heapCurrentIndexCache) - heapCurrentIndexCache;

                        // 更新frameIndexToHeapIndex中的索引
                        locFrameIndexToHeapIndex[locCurrentIndex] = currentIndex;
                        locFrameIndexToHeapIndex[heapCurrentIndexCache] = minIndex;

                        // 更新currentIndex和currentValue，继续向下调整
                        // heapCurrentIndexCache是被下沉的元素，现在位于minIndex
                        currentIndex = minIndex;
                        currentValue = heapCurrentIndexCache;
                    }
                    // 注：循环结束时 minIndex == currentIndex，说明未发生交换，
                    // locHeap[currentIndex] 已等于 currentValue，无需冗余写入
                }
            }

            delete locFrameMap[frameIndex]; // 从frameMap中删除该帧索引
        }

        // 回收节点，准备复用
        node.reset(null);
        this.nodePool[this.poolSize++] = node;
    }


    /**
     * 在所有调度任务中查找具有指定任务ID的节点
     * @param taskID 要查找的任务的唯一标识符
     * @return 找到的TaskIDNode节点，若未找到则返回null
     */
    public function findNodeById(taskID:String):TaskIDNode {
        var locHeap = this.heap;
        var locFrameMap = this.frameMap;
        var heapSize = this.heapSize;

        // 遍历堆中的所有帧索引
        for (var i:Number = 0; i < heapSize; i++) {
            var currentNode:TaskIDNode = locFrameMap[locHeap[i]].getFirst();

            // 遍历每个帧索引下的任务链表
            while (currentNode != null) {
                if (currentNode.taskID == taskID) {
                    return currentNode; // 找到匹配的节点
                }
                currentNode = currentNode.next;
            }
        }
        return null; // 未找到
    }

    /**
     * 根据新的延迟重新调度现有任务
     * @param taskID 要重新调度的任务的唯一标识符
     * @param newDelay 新的延迟帧数
     */
    public function rescheduleTimerByID(taskID:String, newDelay:Number):Void {
        var node:TaskIDNode = findNodeById(taskID); // 查找对应的节点
        if (node != null) {
            removeNode(node); // 移除现有节点
            node.reset(taskID); // 重置节点
            insertNode(node, newDelay); // 重新插入节点并调度
        }
    }

    /**
     * 通过移动节点到新的延迟位置重新调度任务
     * @param node 要重新调度的TaskIDNode节点
     * @param newDelay 新的延迟帧数
     */
    public function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void {
        if (node != null) {
            removeNode(node); // 移除现有节点
            insertNode(node, newDelay); // 重新插入节点并调度
        }
    }

    /**
     * 处理到期任务并推进帧计数
     * @return 到期任务的TaskIDLinkedList链表，若无任务到期则返回null
     */
    public function tick():TaskIDLinkedList {
        if (this.heapSize > 0 && this.heap[0] <= ++this.currentFrame) {
            return extractTasksAtMinFrame(); // 提取并移除最早帧的任务
        }
        return null; // 无任务到期
    }

    /**
     * 查看最早帧的任务而不移除它们
     * @return 包含最早帧索引和任务链表的对象，若堆为空则返回null
     */
    public function peekMin():Object {
        if (this.heapSize == 0) return null;
        var heapZero:Number = this.heap[0];
        return {frame: heapZero, tasks: this.frameMap[heapZero]};
    }


    /**
     * 提取并移除最早帧的任务
     * @return 最早帧的TaskIDLinkedList链表，若堆为空则返回null
     */
    public function extractTasksAtMinFrame():TaskIDLinkedList {
        if (this.heapSize == 0) return null;

        var locHeap:Array = this.heap;
        var minFrame:Number = locHeap[0]; // 获取堆顶最小帧索引
        var lastIndex:Number = --this.heapSize; // 获取堆的最后一个元素索引
        var lastValue:Number = locHeap[lastIndex];
        var locFrameMap:Object = this.frameMap;

        if (lastIndex >= 0) {
            var locFrameIndexToHeapIndex:Object = this.frameIndexToHeapIndex;

            locHeap[0] = lastValue; // 将最后一个元素移动到堆顶
            locFrameIndexToHeapIndex[lastValue] = 0;
            locHeap[lastIndex] = null; // 移除最后一个元素的引用
            delete locFrameIndexToHeapIndex[minFrame];

            if (lastIndex > 0) {
                // 重新平衡堆，确保堆的最小性质
                var currentIndex:Number = 0;
                var currentValue:Number = locHeap[currentIndex];
                // lastIndex 位置已被清空，有效最大索引是 lastIndex - 1
                var maxValidIndex:Number = lastIndex - 1;

                var minIndex:Number;
                var baseChildIndex:Number;
                var remaining:Number;
                var childIndex:Number;
                var childValue:Number;
                var minValue:Number;

                while (true) {
                    minIndex = currentIndex;
                    baseChildIndex = (currentIndex << 2); // 相当于currentIndex * 4
                    remaining = maxValidIndex - baseChildIndex;

                    minValue = currentValue;

                    childIndex = baseChildIndex;

                    if (remaining >= 4) { // 当前节点有4个子节点
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                    } else if (remaining == 3) { // 当前节点有3个子节点
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                    } else if (remaining == 2) { // 当前节点有2个子节点
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                    } else if (remaining == 1) { // 当前节点有1个子节点
                        minIndex = (locHeap[++childIndex] < minValue ? (minValue = locHeap[childIndex], childIndex) : minIndex);
                    }

                    if (minIndex == currentIndex) {
                        break; // 当前节点已在正确位置
                    }

                    // 使用链式赋值交换heap[currentIndex]和heap[minIndex]
                    // a = b + (b = a) - a 模式触发AVM1寄存器优化
                    var heapCurrentIndexCache = locHeap[currentIndex];
                    var locCurrentIndex = locHeap[currentIndex] = locHeap[minIndex] + (locHeap[minIndex] = heapCurrentIndexCache) - heapCurrentIndexCache;

                    // 更新frameIndexToHeapIndex中的索引
                    locFrameIndexToHeapIndex[locCurrentIndex] = currentIndex;
                    locFrameIndexToHeapIndex[heapCurrentIndexCache] = minIndex;

                    // 更新currentIndex和currentValue，继续向下调整
                    // heapCurrentIndexCache是被下沉的元素，现在位于minIndex
                    currentIndex = minIndex;
                    currentValue = heapCurrentIndexCache;
                }
                // 注：循环结束时 minIndex == currentIndex，说明未发生交换，
                // locHeap[currentIndex] 已等于 currentValue，无需冗余写入
            }
        }

        var tasks:TaskIDLinkedList = locFrameMap[minFrame]; // 获取最早帧的任务链表
        delete locFrameMap[minFrame]; // 从frameMap中删除该帧索引
        return tasks;
    }


}
