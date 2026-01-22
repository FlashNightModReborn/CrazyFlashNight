import org.flashNight.naki.DataStructures.*;

/**
 * TaskIDNode - 任务节点，用于时间轮和最小堆的任务调度
 *
 * 版本历史:
 * v1.1 (2026-01) - 添加 ownerType 字段支持多内核调度
 *   [NEW] ownerType 字段标识节点归属的调度内核
 *   [FIX] reset(null) 现在会清除 taskID，避免池中节点持有历史字符串引用
 *
 * ownerType 取值:
 *   0 - 未分配/已回收
 *   1 - SingleLevelTimeWheel（单层时间轮）
 *   2 - SecondLevelTimeWheel（秒级时间轮）
 *   3 - ThirdLevelTimeWheel（分钟级时间轮）
 *   4 - FrameTaskMinHeap（最小堆）
 */
class org.flashNight.naki.DataStructures.TaskIDNode extends TaskNode {
    public var prev:TaskIDNode = null;
    public var next:TaskIDNode = null;
    public var slotIndex:Number = -1;
    public var list:TaskIDLinkedList = null;  // Reference to the parent linked list

    /**
     * [NEW v1.1] 节点归属的调度内核类型
     * 用于 CerberusScheduler.removeTaskByNode 等方法正确分派到对应内核
     */
    public var ownerType:Number = 0;

    public function TaskIDNode(taskID:String) {
        super(taskID);
    }

    /**
     * 重置节点状态，准备复用
     * @param newTaskID 新的任务ID，如果为 null 则清除 taskID
     *
     * [FIX v1.1] 当 newTaskID 为 null 时，现在会清除 taskID
     * 这样可以避免池中节点持有历史 taskID 字符串引用，减少内存驻留
     */
    public function reset(newTaskID:String):Void {
        // [FIX v1.1] 无论 newTaskID 是否为 null，都直接赋值
        // 原逻辑只在 newTaskID != null 时赋值，导致池中节点残留历史 taskID
        this.taskID = newTaskID;
        this.prev = null;
        this.next = null;
        this.slotIndex = -1;
        this.list = null;
        this.ownerType = 0;  // [NEW v1.1] 重置归属类型
    }

    public function equals(other:TaskIDNode):Boolean {
        return this.taskID == other.taskID;
    }

    public function remove():Void {
        // 局部化 list
        var currentList:TaskIDLinkedList = this.list;
        if (currentList == null) {
            throw new Error("Cannot remove a node that is not part of a list.");
        }

        // 局部化 prev 和 next
        var previousNode:TaskIDNode = this.prev;
        var nextNode:TaskIDNode = this.next;

        // 更新前一个节点的 next 引用
        if (previousNode != null) {
            previousNode.next = nextNode;
        } else {
            // 如果没有前一个节点，说明是头节点，更新链表的 head
            currentList.head = nextNode;
        }

        // 更新下一个节点的 prev 引用
        if (nextNode != null) {
            nextNode.prev = previousNode;
        } else {
            // 如果没有下一个节点，说明是尾节点，更新链表的 tail
            currentList.tail = previousNode;
        }

        // 清除当前节点的引用
        this.prev = null;
        this.next = null;
        this.list = null;
    }



    public function toString():String {
        var taskIDStr:String = this.taskID != null ? this.taskID : "N";
        var prevTaskIDStr:String = this.prev != null ? this.prev.taskID : "P";
        var nextTaskIDStr:String = this.next != null ? this.next.taskID : "N";
        var listStr:String = this.list != null ? "L" : "NoListRef";
        
        return "TaskIDNode [ID " + taskIDStr + ", p " + prevTaskIDStr + ", n " + nextTaskIDStr + ", l " + listStr + "]";
    }
}
