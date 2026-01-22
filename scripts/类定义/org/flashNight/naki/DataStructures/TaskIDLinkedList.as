import org.flashNight.naki.DataStructures.TaskIDNode;

class org.flashNight.naki.DataStructures.TaskIDLinkedList {
    public var head:TaskIDNode = null;
    public var tail:TaskIDNode = null;

    public function TaskIDLinkedList() {
    }

    /**
     * 在链表尾部添加一个新节点
     * @param taskID 任务ID
     * @return 新添加的TaskIDNode
     */
    public function addLast(taskID:String):TaskIDNode {
        return appendNode(new TaskIDNode(taskID));
    }

    /**
     * 将现有节点挂载到链表尾部，并设置节点的list引用
     * @param node 要添加的节点
     * @return 添加的TaskIDNode
     */
    public function appendNode(node:TaskIDNode):TaskIDNode {
        if (node == null) {
            throw new Error("Cannot append a null node.");
        }

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

    /**
     * 合并另一个链表的节点到当前链表，并更新节点的list引用
     * @param otherList 要合并的另一个TaskIDLinkedList
     */
    public function merge(otherList:TaskIDLinkedList):Void {
        if (otherList == null) {
            throw new Error("Cannot merge a null list.");
        }

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

        // 更新新合并的节点的list引用
        var currentNode:TaskIDNode = otherFirst;
        while (currentNode != null) {
            currentNode.list = this;
            if (currentNode.next == null) {
                this.tail = currentNode; // 更新链表尾部
            }
            currentNode = currentNode.next;
        }

        // 清空otherList的头尾引用
        otherList.head = null;
        otherList.tail = null;
    }

    /**
     * 直接快速合并另一个链表的节点到当前链表，忽略节点的list引用
     *
     * 【重要限制 - FIX v1.2 文档补充】
     * 此方法出于性能考虑，不会更新被合并节点的 list 引用。
     * 这意味着被合并的节点的 node.list 仍然指向原链表（已被清空的 otherList）。
     *
     * 使用场景限制：
     * - 仅适用于"一次性消费"场景，如 CerberusScheduler.tick() 返回的到期任务列表
     * - 调用方遍历执行后即丢弃整个链表，不再对单个节点调用 remove()
     *
     * 如果需要在合并后对单个节点进行 remove() 操作，请使用 merge() 方法，
     * 它会遍历更新所有节点的 list 引用（O(n) 开销）。
     *
     * @param otherList 要合并的另一个TaskIDLinkedList
     */
    public function mergeDirect(otherList:TaskIDLinkedList):Void {
        if (otherList == null) {
            throw new Error("Cannot merge a null list.");
        }

        // 提取头尾节点为局部变量，减少重复访问
        var otherHead:TaskIDNode = otherList.head;
        var otherTail:TaskIDNode = otherList.tail;

        if (otherHead == null) {
            return; // 另一个链表为空，不需要操作
        }

        // 如果当前链表为空
        if (this.tail == null) {
            this.head = otherHead;
        } else {
            // 当前链表非空，直接连接链表尾部
            this.tail.next = otherHead;
            otherHead.prev = this.tail;
        }

        // 更新当前链表的尾部
        this.tail = otherTail;

        // 清空otherList的头尾引用
        otherList.head = null;
        otherList.tail = null;
    }



    /**
     * 从链表中移除指定的节点，并断开与链表的引用
     * @param node 要移除的节点
     */
    public function remove(node:TaskIDNode):Void {
        if (node == null) {
            throw new Error("Cannot remove a null node.");
        }

        // 快速检查节点是否属于当前链表
        if (node.list !== this) {
            throw new Error("Attempting to remove a node that does not belong to this list.");
        }

        if (node == head && node == tail) {
            head = tail = null;
        } else if (node == head) {
            head = node.next;
            if (head != null) {
                head.prev = null;
            }
        } else if (node == tail) {
            tail = node.prev;
            if (tail != null) {
                tail.next = null;
            }
        } else {
            var prevNode:TaskIDNode = node.prev;
            var nextNode:TaskIDNode = node.next;
            if (prevNode != null) {
                prevNode.next = nextNode;
            }
            if (nextNode != null) {
                nextNode.prev = prevNode;
            }
        }

        // 断开当前节点的连接，并清除对链表的引用
        node.next = null;
        node.prev = null;
        node.list = null;
    }

    /**
     * 获取链表的第一个节点
     * @return 第一个TaskIDNode
     */
    public function getFirst():TaskIDNode {
        return head;
    }

    /**
     * 获取链表的最后一个节点
     * @return 最后一个TaskIDNode
     */
    public function getLast():TaskIDNode {
        return tail;
    }

    /**
     * 获取链表中的节点数量
     * @return 节点数量
     */
    public function getSize():Number {
        var count:Number = 0;
        var currentNode:TaskIDNode = head;

        while (currentNode != null) {
            count++;
            currentNode = currentNode.next;
        }

        return count;
    }

    /**
     * 清空链表并清除所有节点的list引用
     */
    public function clear():Void {
        var currentNode:TaskIDNode = head;
        while (currentNode != null) {
            var nextNode:TaskIDNode = currentNode.next;
            currentNode.list = null;  // 清除节点对链表的引用
            currentNode.prev = null;
            currentNode.next = null;
            currentNode = nextNode;
        }
        head = tail = null;
    }

    /**
     * 查找任务ID对应的节点
     * @param taskID 要查找的任务ID
     * @return 对应的TaskIDNode，如果未找到则返回null
     */
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

    /**
     * 在指定位置插入节点，并设置节点的list引用
     * @param node 要插入的节点
     * @param position 插入的位置，从0开始
     */
    public function insertAt(node:TaskIDNode, position:Number):Void {
        if (node == null) {
            throw new Error("Cannot insert a null node.");
        }

        if (position <= 0 || head == null) {
            // 插入到链表头部
            node.next = head;
            node.prev = null;
            if (head != null) {
                head.prev = node;
            }
            head = node;
            if (tail == null) {
                tail = node;
            }
        } else {
            var currentNode:TaskIDNode = head;
            var index:Number = 0;

            // 找到插入位置的节点
            while (currentNode != null && index < position) {
                currentNode = currentNode.next;
                index++;
            }

            if (currentNode == null) {
                // 插入到链表尾部
                appendNode(node);
                return;
            } else {
                var prevNode:TaskIDNode = currentNode.prev;
                node.next = currentNode;
                node.prev = prevNode;
                currentNode.prev = node;
                if (prevNode != null) {
                    prevNode.next = node;
                } else {
                    // 如果prevNode为null，说明插入位置为头部
                    head = node;
                }
            }
        }
        node.list = this;  // 设置节点对链表的引用
    }

    /**
     * 检查节点是否存在于链表中
     * @param node 要检查的节点
     * @return 如果节点存在于链表中则返回true，否则返回false
     */
    public function containsNode(node:TaskIDNode):Boolean {
        if (node == null) {
            return false;
        }
        return node.list === this;
    }

    /**
     * 将链表内容转换为字符串表示，便于调试
     * @return 链表的字符串表示
     */
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
