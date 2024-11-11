import org.flashNight.neur.TimeWheel.*;
import org.flashNight.naki.DataStructures.*;

class org.flashNight.neur.TimeWheel.SingleLevelTimeWheel implements ITimeWheel {
    private var slots:Array;
    private var currentPointer:Number = 0;
    private var wheelSize:Number;
    private var nodePool:Array; // 节点池
    private var nodePoolTop:Number = 0; // 堆栈顶指针

    // 构造函数
    public function SingleLevelTimeWheel(wheelSize:Number) {
        this.wheelSize = wheelSize;
        this.slots = new Array(wheelSize);
        // 预先分配节点池大小，假设最大需要的节点数为 wheelSize * 5
        var initialNodePoolSize:Number = wheelSize * 5;
        this.nodePool = new Array(initialNodePoolSize);
        initializeNodePool(initialNodePoolSize); // 初始化节点池
    }

    // 初始化节点池
    private function initializeNodePool(size:Number):Void {
        var unrollFactor:Number = 5; // 循环展开因子
        var i:Number = 0;
        while (i < size) {
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
        }
        nodePoolTop = size; // 初始化堆栈顶指针
    }

    // 获取时间轮的当前状态
    public function getTimeWheelStatus():Object {
        var taskCounts:Array = new Array(wheelSize);
        for (var i:Number = 0; i < wheelSize; i++) {
            taskCounts[i] = slots[i] != null ? slots[i].getSize() : 0;
        }
        return {
            currentPointer: this.currentPointer,
            wheelSize: this.wheelSize,
            taskCounts: taskCounts,
            nodePoolSize: this.getNodePoolSize()
        };
    }

    // 查询节点池的大小
    public function getNodePoolSize():Number {
        return this.nodePoolTop;
    }

    // 填充节点池
    public function fillNodePool(size:Number):Void {
        var unrollFactor:Number = 5; // 展开因子
        var remainder:Number = size % unrollFactor; // 计算余数
        var loopCount:Number = Math.floor(size / unrollFactor); // 计算循环次数

        // 确保节点池容量足够，否则直接扩容
        while (nodePoolTop + size > nodePool.length) {
            // 每次扩充节点池的大小，以减少频繁的扩容操作
            nodePool.length += 1000; 
        }

        var i:Number = 0;

        // 使用达夫设备来优化循环
        switch (remainder) {
            case 4: nodePool[nodePoolTop++] = new TaskIDNode(null); i++;
            case 3: nodePool[nodePoolTop++] = new TaskIDNode(null); i++;
            case 2: nodePool[nodePoolTop++] = new TaskIDNode(null); i++;
            case 1: nodePool[nodePoolTop++] = new TaskIDNode(null); i++;
        }

        // 完整的循环展开
        while (i < size) {
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            i += unrollFactor;
        }
    }


    // 缩小节点池的大小
    public function trimNodePool(size:Number):Void {
        if (nodePoolTop > size) {
            nodePoolTop = size; // 调整堆栈顶指针，超出的部分将被忽略
            // 不需要调整数组长度，避免内存重新分配的开销
        }
    }

    // 懒加载机制：首次访问槽位时才初始化链表
    private function getSlot(index:Number):TaskIDLinkedList {
        if (slots[index] == null) {
            slots[index] = new TaskIDLinkedList();
        }
        return slots[index];
    }

    // 获取时间轮数据
    public function getTimeWheelData():Object {
        return { 
            currentPointer: this.currentPointer, 
            wheelSize: this.wheelSize
        };
    }

    // 添加定时器通过任务ID
    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        var node:TaskIDNode = getNode(taskID);
        return addTimer(node, delay);
    }

    // 添加定时器通过节点
    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        return addTimer(node, delay);
    }

    // 添加定时器的内部方法
    private function addTimer(node:TaskIDNode, delay:Number):TaskIDNode {
        // 规范化延迟，确保 slotIndex 非负且小于 wheelSize
        var normalizedDelay:Number = ((delay % wheelSize) + wheelSize) % wheelSize;
        var slotIndex:Number = (currentPointer + normalizedDelay) % wheelSize;

        // 获取槽位并添加节点
        var slot:TaskIDLinkedList = getSlot(slotIndex);
        slot.appendNode(node);
        node.slotIndex = slotIndex; // 记录槽位索引

        return node;
    }

    // 移除定时器通过任务ID
    public function removeTimerByID(taskID:String):Void {
        for (var i:Number = 0; i < wheelSize; i++) {
            var tasks:TaskIDLinkedList = slots[i];
            if (tasks != null) {
                var node:TaskIDNode = tasks.getFirst();
                while (node != null) {
                    if (node.taskID == taskID) {
                        tasks.remove(node);
                        recycleNode(node);
                        return;
                    }
                    node = node.next;
                }
            }
        }
    }

    // 移除定时器通过节点
    public function removeTimerByNode(node:TaskIDNode):Void {
        var slot:TaskIDLinkedList = slots[node.slotIndex];
        if (slot != null) {
            slot.remove(node); // 直接操作节点
            recycleNode(node);
        }
    }

    // 重新调度定时器通过任务ID
    public function rescheduleTimerByID(taskID:String, newDelay:Number):Void {
        var node:TaskIDNode = findNodeByID(taskID);
        if (node != null) {
            rescheduleTimerByNode(node, newDelay);
        }
    }

    // 重新调度定时器通过节点
    public function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void {
        var oldSlotIndex:Number = node.slotIndex;
        var normalizedDelay:Number = ((newDelay % wheelSize) + wheelSize) % wheelSize;
        var newSlotIndex:Number = (currentPointer + normalizedDelay) % wheelSize;

        if (oldSlotIndex != newSlotIndex) {
            removeTimerByNode(node); // 仅在槽位不同的情况下移除并重新添加
            node.reset(node.taskID); // 确保 taskID 保持不变
            addTimerByNode(node, newDelay);
        }
    }

    // 执行tick操作
    public function tick():TaskIDLinkedList {
        var tasks:TaskIDLinkedList = slots[currentPointer];
        slots[currentPointer] = null; // 清空当前槽，推迟链表的销毁到必要时
        currentPointer = (currentPointer + 1) % wheelSize; // 推进指针
        return tasks;
    }

    // 获取节点
    private function getNode(taskID:String):TaskIDNode {
        if (nodePoolTop > 0) {
            var node:TaskIDNode = nodePool[--nodePoolTop];
            node.reset(taskID); // 初始化节点
            return node;
        } else {
            // 节点池为空，直接创建新节点
            return new TaskIDNode(taskID);
        }
    }

    // 回收节点
    private function recycleNode(node:TaskIDNode):Void {
        node.reset(null); // 清空节点数据
        // 使用索引方式回收节点
        if (nodePoolTop < nodePool.length) {
            nodePool[nodePoolTop++] = node;
        } else {
            // 节点池已满，直接丢弃该节点，避免动态扩容
            // 可以根据需要记录日志或处理内存泄漏
        }
    }

    // 查找节点通过任务ID
    private function findNodeByID(taskID:String):TaskIDNode {
        for (var i:Number = 0; i < wheelSize; i++) {
            var slot:TaskIDLinkedList = slots[i];
            if (slot != null) {
                var node:TaskIDNode = slot.getFirst();
                while (node != null) {
                    if (node.taskID == taskID) {
                        return node;
                    }
                    node = node.next;
                }
            }
        }
        return null;
    }
}
