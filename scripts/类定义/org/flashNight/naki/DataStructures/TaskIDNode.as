import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TaskIDNode extends TaskNode {
    public var prev:TaskIDNode = null;
    public var next:TaskIDNode = null;
    public var slotIndex:Number = -1;
    public var list:TaskIDLinkedList = null;  // Reference to the parent linked list

    public function TaskIDNode(taskID:String) {
        super(taskID);
    }

    public function reset(newTaskID:String):Void {
        if (newTaskID != null) {
            this.taskID = newTaskID;  // Reset task ID if provided
        }
        this.prev = null;
        this.next = null;
        this.slotIndex = -1;
        this.list = null;  // Clear reference to the list
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
