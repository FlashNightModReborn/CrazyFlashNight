import org.flashNight.naki.DataStructures.TaskIDNode;

class org.flashNight.naki.DataStructures.TaskIDLinkedList {
    private var head:TaskIDNode = null;
    private var tail:TaskIDNode = null;

    public function TaskIDLinkedList() {
    }


    // 在链表尾部添加一个新节点
    public function addLast(taskID:String):TaskIDNode {
        return appendNode(new TaskIDNode(taskID));
    }

    // 直接将现有节点挂载到链表尾部，并设置节点的 list 引用
    public function appendNode(node:TaskIDNode):TaskIDNode {
        if (tail == null) {
            head = tail = node;
        } else {
            tail.next = node;
            node.prev = tail;
            tail = node;
        }
        node.list = this;  // 设置节点对链表的引用
        return node;
    }

    // 合并另一个链表的节点到当前链表，并更新节点的 list 引用
    public function merge(otherList:TaskIDLinkedList):Void {
        var otherFirst:TaskIDNode = otherList.getFirst();
        if (otherFirst == null) {
            return; // 另一个链表为空，不需要合并
        }
        if (this.tail == null) {
            this.head = otherFirst; // 当前链表为空，直接引用另一个链表
        } else {
            this.tail.next = otherFirst;
            otherFirst.prev = this.tail;
        }

        // 更新新合并的节点的 list 引用
        var currentNode:TaskIDNode = otherFirst;
        while (currentNode != null) {
            currentNode.list = this;
            currentNode = currentNode.next;
        }

        this.tail = otherList.tail; // 更新链表尾部
    }

    // 从链表中移除指定的节点，并断开与链表的引用
    public function remove(node:TaskIDNode):Void {
        // 快速检查节点是否属于当前链表
        if (node.list != this) {
            trace("Error: Attempting to remove a node that does not belong to this list.");
            return;
        }

        if (node == head && node == tail) {
            head = tail = null;
        } else if (node == head) {
            head = node.next;
            if (head != null) head.prev = null;
        } else if (node == tail) {
            tail = node.prev;
            if (tail != null) tail.next = null;
        } else {
            var prevNode:TaskIDNode = node.prev;
            var nextNode:TaskIDNode = node.next;
            if (prevNode != null) prevNode.next = nextNode;
            if (nextNode != null) nextNode.prev = prevNode;
        }

        // 断开当前节点的连接，并清除对链表的引用
        node.next = null;
        node.prev = null;
        node.list = null;
    }


    // 获取链表的第一个节点
    public function getFirst():TaskIDNode {
        return head;
    }

    // 获取链表的最后一个节点
    public function getLast():TaskIDNode {
        return tail;
    }

    // 获取链表中的节点数量
    public function getSize():Number {
        var count:Number = 0;
        var currentNode:TaskIDNode = head;

        while (currentNode != null) {
            count++;
            currentNode = currentNode.next;
        }

        return count;
    }

    // 清空链表并清除所有节点的 list 引用
    public function clear():Void {
        var currentNode:TaskIDNode = head;
        while (currentNode != null) {
            currentNode.list = null;  // 清除节点对链表的引用
            currentNode = currentNode.next;
        }
        head = tail = null;
    }

    // 查找任务ID对应的节点
    public function findNodeByID(taskID:String):TaskIDNode {
        var currentNode:TaskIDNode = head;
        while (currentNode != null) {
            if (currentNode.taskID == taskID) {
                return currentNode;
            }
            currentNode = currentNode.next;
        }
        return null;  // 找不到对应的任务节点
    }

    // 在指定位置插入节点，并设置节点的 list 引用
    public function insertAt(node:TaskIDNode, position:Number):Void {
        if (position <= 0 || head == null) {
            node.next = head;
            if (head != null) head.prev = node;
            head = node;
            if (tail == null) tail = node;
        } else {
            var currentNode:TaskIDNode = head;
            var index:Number = 0;

            while (currentNode != null && index < position) {
                currentNode = currentNode.next;
                index++;
            }

            if (currentNode == null) {
                this.appendNode(node);  // 插入到链表尾部
            } else {
                var prevNode:TaskIDNode = currentNode.prev;
                node.next = currentNode;
                node.prev = prevNode;
                currentNode.prev = node;
                if (prevNode != null) prevNode.next = node;
            }
        }
        node.list = this;  // 设置节点对链表的引用
    }

    // 检查节点是否存在于链表中
    public function containsNode(node:TaskIDNode):Boolean {
        var currentNode:TaskIDNode = head;
        while (currentNode != null) {
            if (currentNode == node) {
                return true;
            }
            currentNode = currentNode.next;
        }
        return false;
    }

    // 将链表内容转换为字符串表示，便于调试
    public function toString():String {
        var result:String = "TaskIDLinkedList [";
        var currentNode:TaskIDNode = head;

        while (currentNode != null) {
            result += currentNode.toString();
            currentNode = currentNode.next;
            if (currentNode != null) {
                result += " -> "; // 添加节点之间的分隔符
            }
        }

        result += "]";
        return result;
    }
}
