import org.flashNight.neur.TimeWheel.*;
import org.flashNight.naki.DataStructures.*;

class org.flashNight.neur.TimeWheel.TimeWheel implements ITimeWheel {
    private var slots:Array;
    private var currentPointer:Number = 0;
    private var slotSize:Number;
    private var wheelSize:Number;
    private var nextLevelWheel:ITimeWheel;
    private var levelSizes:Array;
    private var nodePool:Array; // 用于存储移除的节点以便重用
    private var cumulativeDelay:Number = 0; // 初始化累积延迟

    // 当任务传递到下一级时更新
    private function updateCumulativeDelay(delay:Number):Void {
        cumulativeDelay += delay; // 累加延迟
    }

    // 构造函数，初始化时间轮
    public function TimeWheel(slotSize:Number, levelSizes:Array) {
        this.slotSize = slotSize;
        this.levelSizes = levelSizes;
        this.wheelSize = Number(levelSizes.shift());
        this.slots = new Array(wheelSize);
        this.nodePool = []; // 初始化节点池

        initializeSlots();
    }

    // 初始化每个槽为一个新的双向链表
    private function initializeSlots():Void {
        for (var i:Number = 0; i < wheelSize; i++) {
            slots[i] = new TaskIDLinkedList();
        }
    }

        // 获取节点所在的槽索引
    private function getSlotIndexByNode(node:TaskIDNode):Number 
    {
        for (var i:Number = 0; i < wheelSize; i++) 
        {
            var tasks:TaskIDLinkedList = slots[i];
            if (tasks.containsNode(node))
            { 
                return i;
            }
        }
        return -1;
    }

    public function getSlotSize():Number {
        return this.slotSize;
    }

    public function getCurrentPointer():Number {
        return this.currentPointer;
    }

    public function getWheelSize():Number
    {
        return this.wheelSize;
    }

    public function getCumulativeDelay():Number
    {
        return this.cumulativeDelay;
    }
    

    public function setCumulativeDelay(CumulativeDelay:Number):Void
    {
        this.cumulativeDelay = CumulativeDelay;
    }

    // 从对象池中获取节点或创建新节点
    private function getNode(taskID:String):TaskIDNode {
        if (nodePool.length > 0) {
            var node:TaskIDNode = TaskIDNode(nodePool.pop()); // 强制类型转换为 TaskIDNode
            node.taskID = taskID;
            node.next = null;
            node.prev = null;
            return node;
        } else {
            return new TaskIDNode(taskID);
        }
    }


    // 将节点放回对象池
    private function recycleNode(node:TaskIDNode):Void {
        node.taskID = null;
        node.prev = null;
        node.next = null;
        nodePool.push(node);
    }

    // 添加任务到时间轮，通过任务ID
    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        var node:TaskIDNode = getNode(taskID); // 通过任务ID获取或创建节点
        return addTimer(node, delay);
    }

    // 添加任务到时间轮，通过节点
    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        return addTimer(node, delay);
    }

    // 公共的添加任务逻辑
    private function addTimer(node:TaskIDNode, delay:Number):TaskIDNode {
        var ticks:Number = Math.floor(delay / slotSize);
        var slotIndex:Number = (currentPointer + ticks) % wheelSize;
        var totalDelay:Number = cumulativeDelay + delay; // 总延迟正确计算

        trace("Adding taskID:" + node.taskID + " with initial delay:" + delay +
            " calculated ticks:" + ticks + " totalDelay:" + totalDelay +
            " initial slotIndex:" + slotIndex);

        if (ticks >= wheelSize) { // 当延迟足够跨越当前时间轮
            if (nextLevelWheel == null) {
                initializeNextLevelWheel();
            }
            nextLevelWheel.setCumulativeDelay(totalDelay); // 正确传递累积延迟到下一层级

            return nextLevelWheel.addTimerByNode(node, delay - ticks * slotSize);
        } else {
            slots[slotIndex].appendNode(node);
            scheduleTask(node, totalDelay); // 使用累积延迟安排任务
            return node;
        }
    }


    // 在调度任务时使用总延迟
    public function scheduleTask(node:TaskIDNode, totalDelay:Number):Void {
        // 安排任务在 totalDelay 帧执行
        trace("Scheduled taskID:" + node.taskID + " at frame:" + totalDelay);
    }





    // 时间推进并返回当前槽的任务链表
    public function tick():TaskIDLinkedList {
        var tasks:TaskIDLinkedList = slots[currentPointer];
        slots[currentPointer] = new TaskIDLinkedList(); // 清空当前槽

        advance(); // 推进指针

        // 检查并处理下一级时间轮的任务
        if (currentPointer == 0 && nextLevelWheel != null) {
            var nextLevelTasks:TaskIDLinkedList = nextLevelWheel.tick(); // 获取下一级时间轮的任务
            mergeTasks(tasks, nextLevelTasks); // 合并任务列表
        }

        return tasks; // 返回当前槽的任务链表
    }

    // 合并两个任务链表，将第二个链表的任务追加到第一个链表后面
    private function mergeTasks(primary:TaskIDLinkedList, secondary:TaskIDLinkedList):Void {
        var node:TaskIDNode = secondary.getFirst();
        while (node != null) {
            var nextNode:TaskIDNode = node.next;
            primary.appendNode(node); // 追加节点到primary链表
            node = nextNode;
        }
        secondary.clear(); // 清空secondary链表（可选，取决于你是否想保留次级任务）
    }



    // 初始化下一级时间轮
    private function initializeNextLevelWheel():Void {
        //trace("Initialize next level wheel");
        var nextWheelSize:Number;
        if (levelSizes.length > 0) {
            nextWheelSize = Number(levelSizes.shift());
        } else {
            nextWheelSize = wheelSize * 2;
        }
        nextLevelWheel = new TimeWheel(slotSize * wheelSize, [nextWheelSize].concat(levelSizes));
    }

    // 移除任务，通过任务ID
    public function removeTimerByID(taskID:String):Void {
        removeTimerByIDInternal(taskID);
    }

    // 移除任务，通过节点
    public function removeTimerByNode(node:TaskIDNode):Void {
        removeTimerByNodeInternal(node);
    }

    // 公共的通过任务ID移除任务逻辑
    private function removeTimerByIDInternal(taskID:String):Void {
        for (var i:Number = 0; i < wheelSize; i++) {
            var tasks:TaskIDLinkedList = slots[i];
            var node:TaskIDNode = tasks.getFirst();
            while (node != null) {
                if (node.taskID == taskID) {
                    tasks.remove(node);
                    recycleNode(node); // 回收节点
                    return;
                }
                node = node.next;
            }
        }
        if (nextLevelWheel != null) {
            nextLevelWheel.removeTimerByID(taskID);
        }
    }

    // 公共的通过节点移除任务逻辑
    private function removeTimerByNodeInternal(node:TaskIDNode):Void 
    {
        var slotIndex:Number = getSlotIndexByNode(node);
        if (slotIndex >= 0) 
        {
            slots[slotIndex].remove(node);
            recycleNode(node); // 回收节点
        } 
        else if (nextLevelWheel != null) 
        {
            nextLevelWheel.removeTimerByNode(node);
        }
    }

    // 重新安排任务，通过任务ID
    public function rescheduleTimerByID(taskID:String, newDelay:Number):Void 
    {
        rescheduleTimerByIDInternal(taskID, newDelay);
    }

    // 重新安排任务，通过节点
    public function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void 
    {
        rescheduleTimerByNodeInternal(node, newDelay);
    }

    // 公共的通过任务ID重新安排任务逻辑
    private function rescheduleTimerByIDInternal(taskID:String, newDelay:Number):Void 
    {
        removeTimerByIDInternal(taskID);
        addTimerByID(taskID, newDelay);
    }

    // 公共的通过节点重新安排任务逻辑
    private function rescheduleTimerByNodeInternal(node:TaskIDNode, newDelay:Number):Void 
    {
        removeTimerByNodeInternal(node);
        addTimerByNode(node, newDelay);
    }


    // 移动指针
    private function advance():Void 
    {
        currentPointer = (currentPointer + 1) % wheelSize;
        if (currentPointer == 0 && nextLevelWheel != null) 
        {
            nextLevelWheel.tick(); // 递归推进下一层时间轮
        }
    }
}