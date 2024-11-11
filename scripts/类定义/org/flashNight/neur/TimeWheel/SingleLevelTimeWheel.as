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

        // 初始化节点池
        var unrollFactor:Number = 5; // 循环展开因子
        var i:Number = 0;
        while (i < initialNodePoolSize) {
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
        }
        nodePoolTop = initialNodePoolSize; // 初始化堆栈顶指针
    }

    // 获取时间轮的当前状态
    public function getTimeWheelStatus():Object {
        var taskCounts:Array = new Array(wheelSize);
        for (var i:Number = 0; i < wheelSize; i++) {
            if (slots[i] == null) {
                taskCounts[i] = 0;
            } else {
                taskCounts[i] = slots[i].getSize();
            }
        }
        return {
            currentPointer: this.currentPointer,
            wheelSize: this.wheelSize,
            taskCounts: taskCounts,
            nodePoolSize: this.nodePoolTop
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

    // 获取时间轮数据
    public function getTimeWheelData():Object {
        return { 
            currentPointer: this.currentPointer, 
            wheelSize: this.wheelSize
        };
    }

    // 添加定时器通过任务ID
    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        // 获取节点
        var node:TaskIDNode;
        if (nodePoolTop > 0) {
            node = nodePool[--nodePoolTop];
            node.reset(taskID); // 初始化节点
        } else {
            // 节点池为空，直接创建新节点
            node = new TaskIDNode(taskID);
        }

        // 规范化延迟，确保 slotIndex 非负且小于 wheelSize
        var normalizedDelay:Number = ((delay % wheelSize) + wheelSize) % wheelSize;
        var slotIndex:Number = (currentPointer + normalizedDelay) % wheelSize;

        // 获取槽位并添加节点
        var slot:TaskIDLinkedList;
        if (slots[slotIndex] == null) {
            slots[slotIndex] = new TaskIDLinkedList();
        }
        slot = slots[slotIndex];
        slot.appendNode(node);
        node.slotIndex = slotIndex; // 记录槽位索引

        return node;
    }

    // 添加定时器通过节点
    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        // 规范化延迟，确保 slotIndex 非负且小于 wheelSize
        var normalizedDelay:Number = ((delay % wheelSize) + wheelSize) % wheelSize;
        var slotIndex:Number = (currentPointer + normalizedDelay) % wheelSize;

        // 获取槽位并添加节点
        var slot:TaskIDLinkedList;
        if (slots[slotIndex] == null) {
            slots[slotIndex] = new TaskIDLinkedList();
        }
        slot = slots[slotIndex];
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

                        // 回收节点
                        node.reset(null); // 清空节点数据
                        if (nodePoolTop < nodePool.length) {
                            nodePool[nodePoolTop++] = node;
                        } else {
                            // 节点池已满，直接丢弃该节点，避免动态扩容
                            // 可以根据需要记录日志或处理内存泄漏
                        }

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

            // 回收节点
            node.reset(null); // 清空节点数据
            if (nodePoolTop < nodePool.length) {
                nodePool[nodePoolTop++] = node;
            } else {
                // 节点池已满，直接丢弃该节点，避免动态扩容
                // 可以根据需要记录日志或处理内存泄漏
            }
        }
    }

    // 重新调度定时器通过任务ID
    public function rescheduleTimerByID(taskID:String, newDelay:Number):Void {
        // 查找节点
        var node:TaskIDNode = null;
        for (var i:Number = 0; i < wheelSize; i++) {
            var slot:TaskIDLinkedList = slots[i];
            if (slot != null) {
                var tempNode:TaskIDNode = slot.getFirst();
                while (tempNode != null) {
                    if (tempNode.taskID == taskID) {
                        node = tempNode;
                        break;
                    }
                    tempNode = tempNode.next;
                }
                if (node != null) {
                    break;
                }
            }
        }

        if (node != null) {
            // 重新调度
            var oldSlotIndex:Number = node.slotIndex;
            var normalizedDelay:Number = ((newDelay % wheelSize) + wheelSize) % wheelSize;
            var newSlotIndex:Number = (currentPointer + normalizedDelay) % wheelSize;

            if (oldSlotIndex != newSlotIndex) {
                // 移除节点
                var oldSlot:TaskIDLinkedList = slots[oldSlotIndex];
                if (oldSlot != null) {
                    oldSlot.remove(node);
                }

                node.reset(node.taskID); // 确保 taskID 保持不变

                // 添加到新槽位
                if (slots[newSlotIndex] == null) {
                    slots[newSlotIndex] = new TaskIDLinkedList();
                }
                var newSlot:TaskIDLinkedList = slots[newSlotIndex];
                newSlot.appendNode(node);
                node.slotIndex = newSlotIndex; // 更新槽位索引
            }
        }
    }

    // 重新调度定时器通过节点
    public function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void {
        var oldSlotIndex:Number = node.slotIndex;
        var normalizedDelay:Number = ((newDelay % wheelSize) + wheelSize) % wheelSize;
        var newSlotIndex:Number = (currentPointer + normalizedDelay) % wheelSize;

        if (oldSlotIndex != newSlotIndex) {
            // 移除节点
            var oldSlot:TaskIDLinkedList = slots[oldSlotIndex];
            if (oldSlot != null) {
                oldSlot.remove(node);
            }

            node.reset(node.taskID); // 确保 taskID 保持不变

            // 添加到新槽位
            if (slots[newSlotIndex] == null) {
                slots[newSlotIndex] = new TaskIDLinkedList();
            }
            var newSlot:TaskIDLinkedList = slots[newSlotIndex];
            newSlot.appendNode(node);
            node.slotIndex = newSlotIndex; // 更新槽位索引
        }
    }

    // 执行tick操作
    public function tick():TaskIDLinkedList {
        var tasks:TaskIDLinkedList = slots[currentPointer];
        slots[currentPointer] = null; // 清空当前槽，推迟链表的销毁到必要时
        currentPointer = (currentPointer + 1) % wheelSize; // 推进指针
        return tasks;
    }
}
