import org.flashNight.neur.TimeWheel.*;
import org.flashNight.naki.DataStructures.*;

/**
 * SingleLevelTimeWheel 类实现了一个单级时间轮，用于高效地管理和调度定时任务。
 * 时间轮通过将任务分配到不同的槽位中，以固定的时间步长循环执行任务，适用于高频定时任务的场景。
 *
 * [NEW v1.5] 支持外部节点池提供者注入，实现多时间轮共享统一节点池
 */
class org.flashNight.neur.TimeWheel.SingleLevelTimeWheel implements ITimeWheel {
    private var slots:Array; // 时间轮的槽位数组，每个槽位存储一个任务链表
    private var currentPointer:Number = 0; // 当前指针，指向当前处理的槽位
    private var wheelSize:Number; // 时间轮的大小，即槽位的总数
    private var nodePool:Array; // 节点池，用于存储可重用的 TaskIDNode 节点，减少频繁的内存分配
    private var nodePoolTop:Number = 0; // 节点池的堆栈顶指针，指示下一个可用节点的位置

    /**
     * [NEW v1.5] 外部节点池提供者引用
     * 如果设置了该引用，所有节点池操作将委托给提供者
     * 用于实现多时间轮共享统一节点池，避免节点池不均衡问题
     */
    private var _nodePoolProvider:SingleLevelTimeWheel = null;

    /**
     * 构造函数，初始化时间轮和节点池。
     * @param wheelSize 时间轮的大小，即槽位的总数。
     * @param nodePoolProvider [NEW v1.5] 可选的外部节点池提供者。
     *        如果传入，则本时间轮不创建自己的节点池，所有节点操作委托给提供者。
     *        用于 CerberusScheduler 中让二级、三级时间轮共享单层时间轮的节点池。
     */
    public function SingleLevelTimeWheel(wheelSize:Number, nodePoolProvider:SingleLevelTimeWheel) {
        this.wheelSize = wheelSize;
        this.slots = new Array(wheelSize); // 初始化槽位数组，每个槽位初始为 null

        // [NEW v1.5] 如果传入了外部节点池提供者，委托所有节点操作
        if (nodePoolProvider != null) {
            this._nodePoolProvider = nodePoolProvider;
            // 不创建自己的节点池，节省内存
            this.nodePool = null;
            this.nodePoolTop = 0;
            return;
        }

        // 原有逻辑：创建自己的节点池
        // 预先分配节点池的大小，假设会需要 wheelSize * 5 个节点，利用 5 倍数顺便做循环展开
        // 这样可以避免频繁扩容操作，提高效率
        var initialNodePoolSize:Number = wheelSize * 5;
        this.nodePool = new Array(initialNodePoolSize);

        // 初始化节点池，使用循环展开技术提高初始化效率
        var unrollFactor:Number = 5; // 循环展开因子，每次处理 5 个节点
        var i:Number = 0;
        while (i < initialNodePoolSize) {
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
            nodePool[i++] = new TaskIDNode(null);
        }
        nodePoolTop = initialNodePoolSize; // 初始化堆栈顶指针，指向节点池的末尾
    }

    /**
     * 获取时间轮的当前状态，包括当前指针位置、轮大小、每个槽位的任务数量和节点池的大小。
     * [UPDATE v1.5] nodePoolSize 现在通过 getNodePoolSize() 获取，支持共享节点池。
     * @return 一个包含时间轮状态信息的对象。
     */
    public function getTimeWheelStatus():Object {
        var taskCounts:Array = new Array(wheelSize); // 存储每个槽位的任务数量
        for (var i:Number = 0; i < wheelSize; i++) {
            if (slots[i] == null) {
                taskCounts[i] = 0; // 如果槽位为空，任务数量为 0
            } else {
                taskCounts[i] = slots[i].getSize(); // 获取槽位中的任务数量
            }
        }
        return {
            currentPointer: this.currentPointer, // 当前指针位置
            wheelSize: this.wheelSize, // 时间轮的大小
            taskCounts: taskCounts, // 每个槽位的任务数量
            nodePoolSize: this.getNodePoolSize() // [UPDATE v1.5] 使用方法调用以支持共享池
        };
    }

    /**
     * 查询节点池的当前大小。
     * @return 节点池中可用的节点数量。
     */
    public function getNodePoolSize():Number {
        // [NEW v1.5] 如果有外部提供者，委托给提供者
        if (this._nodePoolProvider != null) {
            return this._nodePoolProvider.getNodePoolSize();
        }
        return this.nodePoolTop; // 返回节点池顶指针的位置，即可用节点的数量
    }

    /**
     * [FIX v1.1] 从节点池获取一个可用节点，供外部调度器复用。
     * 如果节点池为空，则创建新节点。
     * [UPDATE v1.5] 支持委托给外部节点池提供者。
     * @param taskID 任务的唯一标识符。
     * @return 获取到的 TaskIDNode 节点（已初始化 taskID）。
     */
    public function acquireNode(taskID:String):TaskIDNode {
        // [NEW v1.5] 如果有外部提供者，委托给提供者
        if (this._nodePoolProvider != null) {
            return this._nodePoolProvider.acquireNode(taskID);
        }

        var node:TaskIDNode;
        if (nodePoolTop > 0) {
            node = nodePool[--nodePoolTop]; // 从节点池中取出一个节点
            node.reset(taskID); // 初始化节点，设置 taskID
        } else {
            node = new TaskIDNode(taskID); // 节点池为空，创建新节点
        }
        return node;
    }

    /**
     * [FIX v1.2] 将节点回收到节点池中，供后续复用。
     * 作为统一的节点回收入口，供 CerberusScheduler 等外部调度器使用。
     * [UPDATE v1.5] 支持委托给外部节点池提供者。
     *
     * @param node 要回收的 TaskIDNode 节点（调用前应已从链表中移除并 reset）。
     */
    public function releaseNode(node:TaskIDNode):Void {
        // [NEW v1.5] 如果有外部提供者，委托给提供者
        if (this._nodePoolProvider != null) {
            this._nodePoolProvider.releaseNode(node);
            return;
        }

        if (nodePoolTop < nodePool.length) {
            nodePool[nodePoolTop++] = node; // 将节点回收到节点池中
        }
        // 节点池已满时静默丢弃，由 GC 回收（符合性能优先的设计原则）
    }

    /**
     * 填充节点池，确保有足够的节点可用以避免频繁的内存分配。
     * 使用循环展开技术优化填充效率。
     * [UPDATE v1.5] 支持委托给外部节点池提供者。
     * @param size 需要填充的节点数量。
     */
    public function fillNodePool(size:Number):Void {
        // [NEW v1.5] 如果有外部提供者，委托给提供者
        if (this._nodePoolProvider != null) {
            this._nodePoolProvider.fillNodePool(size);
            return;
        }

        var unrollFactor:Number = 5; // 循环展开因子，每次处理 5 个节点
        var remainder:Number = size % unrollFactor; // 计算余数，处理不能被展开因子整除的部分
        var loopCount:Number = Math.floor(size / unrollFactor); // 计算完整循环的次数

        // 确保节点池容量足够，如果不足则扩容，避免频繁扩容操作
        while (nodePoolTop + size > nodePool.length) {
            nodePool.length += 1000; // 每次扩充 1000 个节点
        }

        var i:Number = 0; // 当前填充的节点数量

        // 使用达夫设备的方式处理余数部分，减少循环次数
        switch (remainder) {
            case 4: nodePool[nodePoolTop++] = new TaskIDNode(null); i++;
            case 3: nodePool[nodePoolTop++] = new TaskIDNode(null); i++;
            case 2: nodePool[nodePoolTop++] = new TaskIDNode(null); i++;
            case 1: nodePool[nodePoolTop++] = new TaskIDNode(null); i++;
        }

        // 完整的循环展开，批量填充节点池
        while (i < size) {
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            nodePool[nodePoolTop++] = new TaskIDNode(null);
            i += unrollFactor; // 每次处理 5 个节点
        }
    }

    /**
     * [FIX v1.2] 缩小节点池的大小，释放多余的节点以节省内存。
     * 通过调整堆栈顶指针并释放超出部分的引用，使 GC 可以回收这些节点。
     * 不需要实际缩短数组长度，避免内存重新分配的开销。
     * [UPDATE v1.5] 支持委托给外部节点池提供者。
     * @param size 节点池的新大小。
     */
    public function trimNodePool(size:Number):Void {
        // [NEW v1.5] 如果有外部提供者，委托给提供者
        if (this._nodePoolProvider != null) {
            this._nodePoolProvider.trimNodePool(size);
            return;
        }

        if (nodePoolTop > size) {
            // [FIX v1.2] 释放超出部分的引用，使 GC 可以回收
            for (var i:Number = size; i < nodePoolTop; i++) {
                nodePool[i] = null;
            }
            nodePoolTop = size; // 调整堆栈顶指针
        }
    }

    /**
     * 获取时间轮的当前数据，包括当前指针位置和轮大小。
     * @return 一个包含当前指针和轮大小的对象。
     */
    public function getTimeWheelData():Object {
        return { 
            currentPointer: this.currentPointer, // 当前指针位置
            wheelSize: this.wheelSize // 时间轮的大小
        };
    }

    /**
     * 通过任务ID添加定时器。
     * 获取一个可用节点，规范化延迟并将节点添加到对应的槽位。
     * @param taskID 任务的唯一标识符。
     * @param delay 延迟的时间步数。
     * @return 添加到时间轮中的 TaskIDNode 节点。
     */
    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        // 获取一个可用节点
        var node:TaskIDNode;
        if (nodePoolTop > 0) {
            node = nodePool[--nodePoolTop]; // 从节点池中取出一个节点
            node.reset(taskID); // 初始化节点，设置 taskID
        } else {
            node = new TaskIDNode(taskID); // 节点池为空，创建新节点
        }

        // 规范化延迟，确保 slotIndex 非负且小于 wheelSize
        var slotIndex:Number = (currentPointer + ((delay % wheelSize) + wheelSize) % wheelSize) % wheelSize;

        // 获取槽位，如果槽位未初始化则创建新的链表
        var slot:TaskIDLinkedList;
        if (slots[slotIndex] == null) {
            slots[slotIndex] = new TaskIDLinkedList();
        }
        slot = slots[slotIndex];

        // 将节点添加到槽位的链表中
        slot.appendNode(node);
        node.slotIndex = slotIndex; // 记录节点所在的槽位索引

        return node; // 返回添加的节点
    }

    /**
     * 通过节点添加定时器。
     * 规范化延迟并将节点添加到对应的槽位。
     * @param node 要添加的 TaskIDNode 节点。
     * @param delay 延迟的时间步数。
     * @return 添加到时间轮中的 TaskIDNode 节点。
     */
    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        // 规范化延迟，确保 slotIndex 非负且小于 wheelSize
        var slotIndex:Number = (currentPointer + ((delay % wheelSize) + wheelSize) % wheelSize) % wheelSize;

        // 获取槽位，如果槽位未初始化则创建新的链表
        var slot:TaskIDLinkedList;
        if (slots[slotIndex] == null) {
            slots[slotIndex] = new TaskIDLinkedList();
        }
        slot = slots[slotIndex];

        // 将节点添加到槽位的链表中
        slot.appendNode(node);
        node.slotIndex = slotIndex; // 记录节点所在的槽位索引

        return node; // 返回添加的节点
    }

    /**
     * 通过任务ID移除定时器。
     * 遍历所有槽位，找到对应的节点并移除，同时将节点回收到节点池中。
     * @param taskID 要移除的任务的唯一标识符。
     */
    public function removeTimerByID(taskID:String):Void {
        for (var i:Number = 0; i < wheelSize; i++) { // 遍历所有槽位
            var tasks:TaskIDLinkedList = slots[i];
            if (tasks != null) { // 如果槽位中有任务
                var node:TaskIDNode = tasks.getFirst(); // 获取链表中的第一个节点
                while (node != null) { // 遍历链表中的所有节点
                    if (node.taskID == taskID) { // 找到匹配的任务
                        tasks.remove(node); // 从链表中移除节点

                        // 回收节点
                        node.reset(null); // 重置节点数据
                        if (nodePoolTop < nodePool.length) {
                            nodePool[nodePoolTop++] = node; // 将节点回收到节点池中
                        } else {
                            // 节点池已满，直接丢弃该节点，避免动态扩容
                            // 可以根据需要记录日志或处理内存泄漏
                        }

                        return; // 成功移除后退出函数
                    }
                    node = node.next; // 移动到下一个节点
                }
            }
        }
    }

    /**
     * 通过节点移除定时器。
     * 根据节点的槽位索引，直接从对应的槽位链表中移除节点，并将节点回收到节点池中。
     * @param node 要移除的 TaskIDNode 节点。
     */
    public function removeTimerByNode(node:TaskIDNode):Void {
        var slot:TaskIDLinkedList = slots[node.slotIndex]; // 获取节点所在的槽位链表
        if (slot != null) { // 如果槽位中有任务
            slot.remove(node); // 从链表中移除节点

            // 回收节点
            node.reset(null); // 重置节点数据
            if (nodePoolTop < nodePool.length) {
                nodePool[nodePoolTop++] = node; // 将节点回收到节点池中
            } else {
                // 节点池已满，直接丢弃该节点，避免动态扩容
                // 可以根据需要记录日志或处理内存泄漏
            }
        }
    }

    /**
     * 通过任务ID重新调度定时器。
     * 查找对应的节点，如果找到则根据新的延迟值重新分配到新的槽位。
     * @param taskID 要重新调度的任务的唯一标识符。
     * @param newDelay 新的延迟时间步数。
     */
    public function rescheduleTimerByID(taskID:String, newDelay:Number):Void {
        // 查找节点
        var node:TaskIDNode = null;
        for (var i:Number = 0; i < wheelSize; i++) { // 遍历所有槽位
            var slot:TaskIDLinkedList = slots[i];
            if (slot != null) { // 如果槽位中有任务
                var tempNode:TaskIDNode = slot.getFirst(); // 获取链表中的第一个节点
                while (tempNode != null) { // 遍历链表中的所有节点
                    if (tempNode.taskID == taskID) { // 找到匹配的任务
                        node = tempNode;
                        break; // 退出内层循环
                    }
                    tempNode = tempNode.next; // 移动到下一个节点
                }
                if (node != null) { // 如果找到节点，退出外层循环
                    break;
                }
            }
        }

        if (node != null) { // 如果找到节点
            // 重新调度
            var oldSlotIndex:Number = node.slotIndex; // 记录旧的槽位索引
            // 合并规范化延迟和计算槽位索引
            var newSlotIndex:Number = (currentPointer + ((newDelay % wheelSize) + wheelSize) % wheelSize) % wheelSize;

            if (oldSlotIndex != newSlotIndex) { // 如果新的槽位与旧的不同
                // 移除节点
                var oldSlot:TaskIDLinkedList = slots[oldSlotIndex];
                if (oldSlot != null) {
                    oldSlot.remove(node); // 从旧的槽位链表中移除节点
                }

                node.reset(node.taskID); // 确保 taskID 保持不变

                // 添加到新槽位
                var newSlot:TaskIDLinkedList = slots[newSlotIndex];
                if (newSlot == null) { // 如果新的槽位未初始化
                    newSlot = slots[newSlotIndex] = new TaskIDLinkedList(); // 创建新的链表并赋值
                }
                newSlot.appendNode(node); // 将节点添加到新的槽位链表中
                node.slotIndex = newSlotIndex; // 更新节点的槽位索引
            }
        }
    }

    /**
     * 通过节点重新调度定时器。
     * 根据节点的当前槽位索引和新的延迟值，重新分配到新的槽位。
     * @param node 要重新调度的 TaskIDNode 节点。
     * @param newDelay 新的延迟时间步数。
     */
    public function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void {
        var oldSlotIndex:Number = node.slotIndex; // 记录旧的槽位索引
        // 合并规范化延迟和计算槽位索引
        var newSlotIndex:Number = (currentPointer + ((newDelay % wheelSize) + wheelSize) % wheelSize) % wheelSize;

        if (oldSlotIndex != newSlotIndex) { // 如果新的槽位与旧的不同
            // 移除节点
            var oldSlot:TaskIDLinkedList = slots[oldSlotIndex];
            if (oldSlot != null) {
                oldSlot.remove(node); // 从旧的槽位链表中移除节点
            }

            node.reset(node.taskID); // 确保 taskID 保持不变

            // 添加到新槽位
            var newSlot:TaskIDLinkedList = slots[newSlotIndex];
            if (newSlot == null) { // 如果新的槽位未初始化
                newSlot = slots[newSlotIndex] = new TaskIDLinkedList(); // 创建新的链表并赋值
            }
            newSlot.appendNode(node); // 将节点添加到新的槽位链表中
            node.slotIndex = newSlotIndex; // 更新节点的槽位索引
        }
    }

    /**
     * 通过任务ID输出定时器信息。
     * 遍历所有槽位，找到对应的节点。
     * @param taskID 目标任务的唯一标识符。
     */
    public function printTimerInfoByID(taskID:String):String {
        if(taskID == null){
            return "TaskID is null";
        }
        for (var i:Number = 0; i < wheelSize; i++) { // 遍历所有槽位
            var tasks:TaskIDLinkedList = slots[i];
            if (tasks != null) { // 如果槽位中有任务
                var node:TaskIDNode = tasks.getFirst(); // 获取链表中的第一个节点
                while (node != null) { // 遍历链表中的所有节点
                    if (node.taskID == taskID) { // 找到匹配的任务
                        var strArr = ["TaskID["+ taskID+"]"];
                        strArr.push("Slot["+i+"]");
                        var dist = (i - currentPointer) % wheelSize;
                        strArr.push("Distance["+dist+"]");
                        return strArr.join(", ");
                    }
                    node = node.next; // 移动到下一个节点
                }
            }
        }
        return "TaskID " + taskID + " not found";
    }


    /**
     * 执行 tick 操作，推进时间轮的当前指针，并获取当前槽位中的任务。
     * @return 当前槽位中的 TaskIDLinkedList 链表，包含所有待执行的任务。
     */
    public function tick():TaskIDLinkedList {
        var tasks:TaskIDLinkedList = slots[currentPointer]; // 获取当前槽位中的任务链表
        slots[currentPointer] = null; // 清空当前槽位，推迟链表的销毁到必要时
        currentPointer = (currentPointer + 1) % wheelSize; // 推进指针，循环回绕

        return tasks; // 返回当前槽位中的任务链表
    }
}
