import org.flashNight.naki.DataStructures.SLNode;

class org.flashNight.naki.DataStructures.SinglyLinkedList {
    private var head:SLNode = null;
    private var size:Number = 0;

    // 构造函数，初始化为空链表
    public function SinglyLinkedList() {
        // 初始化为空链表
    }

    // 清空链表
    public function clear():Void {
        head = null;
        size = 0;
    }

    // 判断链表是否为空
    public function isEmpty():Boolean {
        return size == 0;
    }

    // 获取链表中节点的数量
    public function getSize():Number {
        return size;
    }

    // 在链表头部插入一个新节点
    public function addFirst(value:Object):Void {
        var newNode:SLNode = new SLNode(value);
        newNode.setNext(head);
        head = newNode;
        size++;
    }

    // 在链表尾部插入一个新节点
    public function addLast(value:Object):Void {
        var newNode:SLNode = new SLNode(value);
        if (isEmpty()) {
            head = newNode;
        } else {
            var current:SLNode = head;
            while (current.getNext() != null) {
                current = current.getNext();
            }
            current.setNext(newNode);
        }
        size++;
    }

    // 移除链表的第一个节点
    public function removeFirst():Void {
        if (isEmpty()) return;

        head = head.getNext();
        size--;
    }

    // 移除链表的最后一个节点
    public function removeLast():Void {
        if (isEmpty()) return;

        if (size == 1) {
            head = null;
        } else {
            var current:SLNode = head;
            var previous:SLNode = null;
            while (current.getNext() != null) {
                previous = current;
                current = current.getNext();
            }
            previous.setNext(null);
        }
        size--;
    }

    // 查找包含指定值的节点
    public function find(value:Object):SLNode {
        var current:SLNode = head;
        while (current != null) {
            if (current.getValue() == value) {
                return current;
            }
            current = current.getNext();
        }
        return null;
    }

    // 判断链表中是否包含指定值
    public function contains(value:Object):Boolean {
        return find(value) != null;
    }

    // 获取指定值的索引
    public function indexOf(value:Object):Number {
        var current:SLNode = head;
        var index:Number = 0;
        while (current != null) {
            if (current.getValue() == value) {
                return index;
            }
            current = current.getNext();
            index++;
        }
        return -1;
    }

    // 根据索引获取节点
    public function getNodeAt(index:Number):SLNode {
        if (index < 0 || index >= size) return null;

        var current:SLNode = head;
        var currentIndex:Number = 0;
        while (current != null) {
            if (currentIndex == index) {
                return current;
            }
            current = current.getNext();
            currentIndex++;
        }
        return null;
    }

    // 获取链表的第一个节点
    public function getFirst():SLNode {
        return head;
    }

    // 获取链表的最后一个节点
    public function getLast():SLNode {
        if (isEmpty()) return null;

        var current:SLNode = head;
        while (current.getNext() != null) {
            current = current.getNext();
        }
        return current;
    }

    // 从head开始遍历链表
    public function traverse(callback:Function):Void {
        var current:SLNode = head;
        while (current != null) {
            callback(current);
            current = current.getNext();
        }
    }

    // 反转链表
    public function reverse():Void {
        var previous:SLNode = null;
        var current:SLNode = head;
        var next:SLNode = null;

        while (current != null) {
            next = current.getNext();
            current.setNext(previous);
            previous = current;
            current = next;
        }
        head = previous;
    }

    // 遍历链表并对每个节点执行回调函数
    public function forEach(callback:Function):Void {
        var current:SLNode = head;
        while (current != null) {
            callback(current.getValue());
            current = current.getNext();
        }
    }

    // 对链表中的每个节点应用回调函数，并返回一个新的链表
    public function map(callback:Function):SinglyLinkedList {
        var newList:SinglyLinkedList = new SinglyLinkedList();
        var current:SLNode = head;

        while (current != null) {
            newList.addLast(callback(current.getValue()));
            current = current.getNext();
        }

        return newList;
    }

    // 返回一个新的链表，其中包含所有满足条件的节点
    public function filter(callback:Function):SinglyLinkedList {
        var filteredList:SinglyLinkedList = new SinglyLinkedList();
        var current:SLNode = head;

        while (current != null) {
            if (callback(current.getValue())) {
                filteredList.addLast(current.getValue());
            }
            current = current.getNext();
        }

        return filteredList;
    }

    // 累积链表中的每个节点值，并返回累积结果
    public function reduce(callback:Function, initialValue:Object):Object {
        var accumulator:Object = initialValue;
        var current:SLNode = head;

        while (current != null) {
            accumulator = callback(accumulator, current.getValue());
            current = current.getNext();
        }

        return accumulator;
    }

    // 将链表转换为数组
    public function toArray():Array {
        var array:Array = [];
        var current:SLNode = head;

        while (current != null) {
            array.push(current.getValue());
            current = current.getNext();
        }

        return array;
    }

    // 从数组创建链表
    public function fromArray(array:Array):Void {
        clear();
        for (var i:Number = 0; i < array.length; i++) {
            addLast(array[i]);
        }
    }

    // 克隆链表
    public function clone():SinglyLinkedList {
        var clonedList:SinglyLinkedList = new SinglyLinkedList();
        var current:SLNode = head;
        
        while (current != null) {
            clonedList.addLast(current.getValue());
            current = current.getNext();
        }
        
        return clonedList;
    }

    // 合并两个链表
    public function merge(list:SinglyLinkedList):Void {
        if (list.isEmpty()) return;

        if (this.isEmpty()) {
            this.head = list.getFirst();
        } else {
            var last:SLNode = getLast();
            last.setNext(list.getFirst());
        }

        this.size += list.getSize();
    }

    // 将链表节点值连接为字符串
    public function join(separator:String):String {
        var result:String = "";
        var current:SLNode = head;

        while (current != null) {
            result += current.getValue();
            if (current.getNext() != null) {
                result += separator;
            }
            current = current.getNext();
        }

        return result;
    }

    // 在指定索引位置拆分链表
    public function split(index:Number):SinglyLinkedList {
        if (index < 0 || index >= size) return null;

        var newList:SinglyLinkedList = new SinglyLinkedList();
        if (index == 0) {
            newList.head = head;
            clear();
            newList.size = size;
            size = 0;
            return newList;
        }

        var current:SLNode = getNodeAt(index - 1);
        newList.head = current.getNext();
        current.setNext(null);

        // 更新两个链表的 size
        newList.size = size - index;
        size = index;

        return newList;
    }

    // 根据指定节点拆分链表
    public function splitAtNode(node:SLNode):SinglyLinkedList {
        if (node == null || !containsNode(node)) return null;

        var newList:SinglyLinkedList = new SinglyLinkedList();
        if (node == head) {
            newList.head = head;
            clear();
            newList.size = size;
            size = 0;
            return newList;
        }

        var current:SLNode = head;
        while (current.getNext() != node) {
            current = current.getNext();
        }

        newList.head = node;
        current.setNext(null);

        // 更新两个链表的 size
        var newSize:Number = 0;
        current = newList.head;
        while (current != null) {
            newSize++;
            current = current.getNext();
        }
        newList.size = newSize;
        size -= newSize;

        return newList;
    }

    // 辅助方法：检查节点是否存在于链表中
    public function containsNode(node:SLNode):Boolean {
        var current:SLNode = head;
        while (current != null) {
            if (current == node) {
                return true;
            }
            current = current.getNext();
        }
        return false;
    }

    // 对链表中的节点进行排序
    public function sort(compareFunction:Function):Void {
        if (size < 2) return;

        var sorted:Boolean = false;
        while (!sorted) {
            sorted = true;
            var current:SLNode = head;
            
            while (current != null && current.getNext() != null) {
                var next:SLNode = current.getNext();
                if (compareFunction(current.getValue(), next.getValue()) > 0) {
                    // 交换值
                    var temp:Object = current.getValue();
                    current.setValue(next.getValue());
                    next.setValue(temp);
                    sorted = false;
                }
                current = next;
            }
        }
    }
}
