import org.flashNight.neur.TimeWheel.*;
import org.flashNight.naki.DataStructures.*;

class org.flashNight.neur.TimeWheel.SingleLevelTimeWheel implements ITimeWheel {
    private var slots:Array;
    private var currentPointer:Number = 0;
    private var wheelSize:Number;
    private var nodePool:Array; // 用于存储移除的节点以便重用

    private function initializeNodePool(size:Number):Void {
        for (var i:Number = 0; i < size; i++) {
            nodePool.push(new TaskIDNode(null));
        }
    }

    // 获取时间轮的当前状态
    public function getTimeWheelStatus():Object {
        var taskCounts:Array = [];
        for (var i:Number = 0; i < wheelSize; i++) {
            taskCounts.push(slots[i] != null ? slots[i].getSize() : 0); // 使用 getSize() 代替 length
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
        return this.nodePool.length;
    }

    // 填充节点池
    public function fillNodePool(size:Number):Void {
        for (var i:Number = 0; i < size; i++) {
            this.nodePool.push(new TaskIDNode(null));  // 填充空节点
        }
    }

    // 缩小节点池的大小
    public function trimNodePool(size:Number):Void {
        if (this.nodePool.length > size) {
            this.nodePool.length = size;  // 直接调整数组长度，超出的部分会被自动移除
        }
    }

    // 构造函数，不再需要 slotSize
    public function SingleLevelTimeWheel(wheelSize:Number) {
        this.wheelSize = wheelSize;
        this.slots = new Array(wheelSize);
        this.nodePool = [];
        initializeNodePool(wheelSize * 3); // 预分配节点
    }

    // 懒加载机制：首次访问槽位时才初始化链表
    private function getSlot(index:Number):TaskIDLinkedList {
        if (slots[index] == null) {
            slots[index] = new TaskIDLinkedList();
        }
        return slots[index];
    }

    public function getTimeWheelData():Object {
        return { 
            currentPointer: this.currentPointer, 
            wheelSize: this.wheelSize
        };
    }

    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        var node:TaskIDNode = getNode(taskID);
        return addTimer(node, delay);
    }

    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        return addTimer(node, delay);
    }

    private function addTimer(node:TaskIDNode, delay:Number):TaskIDNode {
        // 规范化延迟，确保 slotIndex 非负且小于 wheelSize
        var normalizedDelay:Number = ((delay % wheelSize) + wheelSize) % wheelSize;
        var slotIndex:Number = (currentPointer + normalizedDelay) % wheelSize;

        // Log the calculated slot index and delay details
        //  trace("Adding task with ID: " + node.taskID);
        //  trace(" - Current pointer: " + currentPointer);
        //  trace(" - Delay: " + delay);
        //  trace(" - Normalized delay: " + normalizedDelay);
        //  trace(" - Calculated slot index: " + slotIndex);

        // Retrieve the slot and add the node
        var slot:TaskIDLinkedList = getSlot(slotIndex);
        slot.appendNode(node);
        node.slotIndex = slotIndex; // Record the slot index

        // Log the slot status after insertion
        //  trace(" - Task added to slot index: " + slotIndex);
        //  trace(" - Number of tasks in slot after insertion: " + slot.getSize());

        return node;
    }


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

    public function removeTimerByNode(node:TaskIDNode):Void {
        var slot:TaskIDLinkedList = slots[node.slotIndex];
        if (slot != null) {
            slot.remove(node); // 利用链表性质，直接操作节点
            recycleNode(node);
        }
    }

    public function rescheduleTimerByID(taskID:String, newDelay:Number):Void {
        var node:TaskIDNode = findNodeByID(taskID);
        if (node != null) {
            rescheduleTimerByNode(node, newDelay);
        }
    }

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

    public function tick():TaskIDLinkedList {
        var tasks:TaskIDLinkedList = getSlot(currentPointer);
        slots[currentPointer] = null; // 清空当前槽，推迟链表的销毁到必要时
        currentPointer = (currentPointer + 1) % wheelSize; // 推进指针
        return tasks;
    }

    private function getNode(taskID:String):TaskIDNode {
        if (nodePool.length > 0) {
            var node:TaskIDNode = TaskIDNode(nodePool.pop());
            node.reset(taskID); // 初始化节点
            return node;
        } else {
            return new TaskIDNode(taskID);
        }
    }

    private function recycleNode(node:TaskIDNode):Void {
        node.reset(null); // 清空节点数据
        nodePool.push(node);
    }

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
