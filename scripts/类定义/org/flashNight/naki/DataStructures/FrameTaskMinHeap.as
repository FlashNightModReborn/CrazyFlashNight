/*

---

#### 1. 类简介
`FrameTaskMinHeap` 是一个基于帧的任务调度管理器，它使用最小堆结构来高效地优先处理和执行任务。通过最小堆保持任务按帧索引排序，允许对大量任务进行有效的调度。任务以帧为单位进行延迟执行，适合游戏等需要基于帧定时操作的场景。

---

#### 2. 类的私有属性与实现

- **`heap:Array`**  
  - 用于存储帧索引的最小堆数组。每个帧索引对应一个或多个任务。堆的性质保证了最小帧索引总是位于堆顶。
  
- **`frameMap:Object`**  
  - 将帧索引映射到 `TaskIDLinkedList` 链表。每个帧索引对应一个任务链表，用来存储该帧的任务节点。
  
- **`frameIndexToHeapIndex:Object`**  
  - 帧索引映射到堆中的索引位置，用来跟踪帧在堆中的位置，以便快速更新或删除帧任务。
  
- **`currentFrame:Number`**  
  - 当前正在处理的帧索引，任务调度基于此值进行帧延迟计算。
  
- **`nodePool:Array`**  
  - 一个可重用的 `TaskIDNode` 实例池，用于减少频繁创建和销毁节点带来的性能开销。未使用的节点会被回收到池中以供以后重用。

##### 私有方法

1. **`initializeNodePool(size:Number):Void`**  
   初始化 `nodePool`，预分配 `size` 数量的 `TaskIDNode` 节点，减少运行时的内存分配开销。

2. **`getNode(taskID:String):TaskIDNode`**  
   从节点池中获取一个可用节点，若池中为空则新建一个节点。此节点被用于存储新的任务。

3. **`recycleNode(node:TaskIDNode):Void`**  
   将已完成或被移除的节点重置，并返回节点池，以便后续任务重用。

4. **`bubbleUp(index:Number):Void`**  
   维护最小堆的性质，通过上浮操作使插入的帧索引回到正确位置，确保堆的有序性。

5. **`bubbleDown(index:Number):Void`**  
   通过下沉操作，维护堆的性质，处理删除任务或堆顶任务完成后的堆调整。

6. **`swap(i:Number, j:Number):Void`**  
   交换堆中两个帧索引的位置，并同步更新它们在 `frameIndexToHeapIndex` 中的映射关系。

---

#### 3. 类的公共方法与属性

- **`FrameTaskMinHeap()`**
  - 构造函数，用于初始化 `FrameTaskMinHeap` 的堆数组、帧映射表、节点池等。默认预分配100个 `TaskIDNode` 节点以供重用。

- **`insert(taskID:String, delay:Number):Void`**  
  插入一个新的任务，该任务将在 `delay` 帧后执行。方法会计算任务的目标帧索引，并将任务添加到 `frameMap` 对应的链表中，同时维护最小堆的结构。

- **`insertNode(node:TaskIDNode, delay:Number):Void`**  
  与 `insert` 方法类似，但允许直接插入已经存在的任务节点。该方法用于任务的重新安排或复杂调度场景。

- **`addTimerByID(taskID:String, delay:Number):TaskIDNode`**  
  创建并插入一个新的任务，返回该任务的 `TaskIDNode` 节点。便于后续操作，如取消或重新安排任务。

- **`addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode`**  
  允许基于已有的任务节点设置计时器，并返回该节点。

- **`removeById(taskID:String):Void`**  
  根据任务 ID 移除指定任务。如果找到该任务，将调用 `removeNode` 方法从调度中移除。

- **`removeDirectly(node:TaskIDNode):Void`**  
  直接移除指定的任务节点，省去查找任务 ID 的步骤。

- **`removeNode(node:TaskIDNode):Void`**  
  移除给定的任务节点，维护帧链表与最小堆的正确性，并将节点回收到节点池中以便重用。

- **`findNodeById(taskID:String):TaskIDNode`**  
  在所有预定任务中搜索指定任务 ID 的节点，返回找到的节点或者 `null`。

- **`rescheduleTimerByID(taskID:String, newDelay:Number):Void`**  
  重新安排指定任务，使其在新的延迟时间后执行。此方法先移除当前任务，再将其重新插入到新的帧索引中。

- **`rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void`**  
  类似于 `rescheduleTimerByID`，但操作的目标是现有的任务节点。

- **`tick():TaskIDLinkedList`**  
  推进帧计数，并处理到期的任务。返回到期任务的链表，供外部调用处理。

- **`peekMin():Object`**  
  查看最小帧索引对应的任务信息，而不移除它。用于查询最早的任务及其帧索引。

- **`extractTasksAtMinFrame():TaskIDLinkedList`**  
  提取并移除最早帧的任务链表，维护堆结构，并返回该帧的任务。

---

#### 4. 示例用法

```actionscript
import org.flashNight.naki.DataStructures.*;

// 创建一个 FrameTaskMinHeap 实例
var taskScheduler:FrameTaskMinHeap = new FrameTaskMinHeap();

// 添加一个任务ID为 "task1"，延迟 5 帧执行
taskScheduler.addTimerByID("task1", 5);

// 模拟帧推进，并执行到期任务
for (var i:Number = 0; i < 10; i++) {
    trace("当前帧: " + i);
    var dueTasks:TaskIDLinkedList = taskScheduler.tick();
    if (dueTasks != null) {
        trace("到期任务: " + dueTasks.toString());
    }
}

// 移除任务
taskScheduler.removeById("task1");

// 重新安排任务
taskScheduler.rescheduleTimerByID("task1", 10);
```

---

*/
import org.flashNight.naki.DataStructures.*;

// 使用最小堆结构管理基于帧的任务调度，以高效地优先处理和执行任务
class org.flashNight.naki.DataStructures.FrameTaskMinHeap {
    private var heap:Array;                     // 存储帧索引的最小堆数组
    private var frameMap:Object;                // 将帧索引映射到任务的链表
    private var frameIndexToHeapIndex:Object;   // 将帧索引映射到堆中的索引
    public var currentFrame:Number;            // 跟踪当前帧数
    private var nodePool:Array;                 // 可重用的TaskIDNode实例池

    // 构造函数：初始化最小堆及相关结构
    public function FrameTaskMinHeap() {
        this.heap = [];
        this.frameMap = {};
        this.frameIndexToHeapIndex = {};
        this.currentFrame = 0;
        initializeNodePool(100);  // 预分配100个节点以便重用
    }

    // 初始化节点池，预分配指定数量的TaskIDNode对象
    private function initializeNodePool(size:Number):Void {
        nodePool = [];
        for (var i:Number = 0; i < size; i++) {
            nodePool.push(new TaskIDNode(null));  // 初始化时不指定任务ID
        }
    }

    // 从节点池中获取一个节点或在池为空时创建一个新节点
    private function getNode(taskID:String):TaskIDNode {
        if (nodePool.length > 0) {
            var node:TaskIDNode = TaskIDNode(nodePool.pop());
            node.reset(taskID);  // 重新初始化节点的任务ID
            return node;
        } else {
            return new TaskIDNode(taskID);  // 池为空时直接创建新节点
        }
    }

    // 重置节点并将其返回到节点池中以便未来重用
    private function recycleNode(node:TaskIDNode):Void {
        node.reset(null);  // 清除任务ID及其他属性
        nodePool.push(node);
    }


    // 查询节点池的大小
    public function getNodePoolSize():Number {
        return this.nodePool.length;
    }

    // 填充节点池：向节点池中增加指定数量的空闲节点
    public function fillNodePool(size:Number):Void {
        for (var i:Number = 0; i < size; i++) {
            this.nodePool.push(new TaskIDNode(null));  // 添加空节点
        }
    }

    // 缩小节点池的大小
    public function trimNodePool(size:Number):Void {
        if (this.nodePool.length > size) {
            this.nodePool.length = size;  // 直接调整数组长度，超出的部分会被自动移除
        }
    }

    // 在指定延迟后安排新任务的执行
    public function insert(taskID:String, delay:Number):Void {
        var frameIndex:Number = this.currentFrame + delay;  // 计算目标帧索引
        if (!frameMap[frameIndex]) {
            frameMap[frameIndex] = new TaskIDLinkedList();
            heap.push(frameIndex);
            frameIndexToHeapIndex[frameIndex] = heap.length - 1;
            this.bubbleUp(heap.length - 1);  // 维护堆的性质
        }
        var newNode:TaskIDNode = getNode(taskID);
        newNode.slotIndex = frameIndex;  // 存储帧索引到节点中
        frameMap[frameIndex].appendNode(newNode);  // 将节点添加到链表中
    }

    // 直接插入已存在的节点，并在指定延迟后执行
    public function insertNode(node:TaskIDNode, delay:Number):Void {
        var frameIndex:Number = this.currentFrame + delay;
        if (!frameMap[frameIndex]) {
            frameMap[frameIndex] = new TaskIDLinkedList();
            heap.push(frameIndex);
            frameIndexToHeapIndex[frameIndex] = heap.length - 1;
            this.bubbleUp(heap.length - 1);
        }
        node.slotIndex = frameIndex;
        frameMap[frameIndex].appendNode(node);
    }

    // 根据任务ID添加计时器，创建一个新节点
    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        var node:TaskIDNode = getNode(taskID);
        insertNode(node, delay);
        return node;
    }

    // 根据节点直接添加计时器
    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        insertNode(node, delay);
        return node;
    }

    // 根据任务ID从调度系统中移除任务
    public function removeById(taskID:String):Void {
        var node:TaskIDNode = findNodeById(taskID);
        if (node != null) {
            removeNode(node);
        }
    }

    // 直接从调度系统中移除节点
    public function removeDirectly(node:TaskIDNode):Void {
        removeNode(node);
    }

    // 移除节点的核心方法，处理链表和堆的更新
    public function removeNode(node:TaskIDNode):Void {
        var frameIndex:Number = node.slotIndex;
        var list:TaskIDLinkedList = frameMap[frameIndex];
        list.remove(node);
        if (list.getFirst() == null) {  // 检查链表是否为空
            var index:Number = frameIndexToHeapIndex[frameIndex];
            swap(index, heap.length - 1);  // 与最后一个项交换
            delete frameIndexToHeapIndex[frameIndex];
            frameIndexToHeapIndex[heap[index]] = index;
            heap.pop();  // 移除最后一个项
            if (index < heap.length) {
                bubbleDown(index);  // 维护堆的性质
            }
        }
        recycleNode(node);  // 回收节点以便重用
    }

    // 跨所有预定任务搜索指定任务ID的节点
    public function findNodeById(taskID:String):TaskIDNode {
        for (var i:Number = 0; i < heap.length; i++) {
            var frameIndex:Number = heap[i];
            var list:TaskIDLinkedList = frameMap[frameIndex];
            var currentNode:TaskIDNode = list.getFirst();
            while (currentNode != null) {
                if (currentNode.taskID == taskID) {
                    return currentNode;
                }
                currentNode = currentNode.next;
            }
        }
        return null;
    }

    // 将现有任务根据新的延迟重新安排
    public function rescheduleTimerByID(taskID:String, newDelay:Number):Void {
        var node:TaskIDNode = findNodeById(taskID);
        if (node != null) {
            removeNode(node);
            node.reset(taskID);
            insertNode(node, newDelay);
        }
    }

    // 将节点移动到新的延迟以重新安排任务
    public function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void {
        if (node != null) {
            removeNode(node);
            insertNode(node, newDelay);
        }
    }

    // 处理到期的任务，并推进帧计数
    public function tick():TaskIDLinkedList {
        this.currentFrame++;
        if (heap.length > 0 && heap[0] <= this.currentFrame) {
            return this.extractTasksAtMinFrame();
        }
        return null;
    }

    // 不移除地返回最早帧的任务信息
    public function peekMin():Object {
        if (heap.length == 0) return null;
        return {frame: heap[0], tasks: frameMap[heap[0]]};
    }

    // 提取并移除最早帧的任务
    public function extractTasksAtMinFrame():TaskIDLinkedList {
        if (heap.length == 0) return null;
        var minFrame:Number = heap[0];
        swap(0, heap.length - 1);
        heap.pop();
        this.bubbleDown(0);
        var tasks:TaskIDLinkedList = frameMap[minFrame];
        delete frameMap[minFrame];
        return tasks;
    }

    // 维护最小堆性质，通过上浮新加入或更新的节点
    private function bubbleUp(index:Number):Void {
        while (index > 0) {
            var parentIndex:Number = (index - 1) >> 1;
            if (heap[index] < heap[parentIndex]) {
                swap(index, parentIndex);
                index = parentIndex;
            } else {
                break;
            }
        }
    }

    // 维护最小堆性质，通过下沉可能出现顺序错误的节点
    private function bubbleDown(index:Number):Void {
        var length:Number = heap.length;
        var element:Number = heap[index];
        var leftChildIndex:Number, rightChildIndex:Number, smallerChildIndex:Number;

        while (true) {
            leftChildIndex = (index << 1) + 1;  // 计算左子节点索引
            rightChildIndex = leftChildIndex + 1;  // 计算右子节点索引
            smallerChildIndex = index;

            if (leftChildIndex < length && heap[leftChildIndex] < element) {
                smallerChildIndex = leftChildIndex;
            }

            if (rightChildIndex < length && heap[rightChildIndex] < heap[smallerChildIndex]) {
                smallerChildIndex = rightChildIndex;
            }

            if (smallerChildIndex != index) {
                swap(index, smallerChildIndex);
                index = smallerChildIndex;
                element = heap[index];  // 更新当前元素为交换后的元素
            } else {
                break;
            }
        }
    }

    // 交换堆中的两个元素，并更新帧索引到堆索引的映射
    private function swap(i:Number, j:Number):Void {
        var temp:Number = heap[i];
        heap[i] = heap[j];
        heap[j] = temp;
        
        frameIndexToHeapIndex[heap[i]] = i;
        frameIndexToHeapIndex[heap[j]] = j;
    }
}
