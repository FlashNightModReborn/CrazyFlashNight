/*

# `DoublyLinkedList` 类 - 使用文档

## 概述

`DoublyLinkedList` 类实现了一个通用的双向链表数据结构。双向链表是一种链式数据结构，其中每个节点包含对前驱节点和后继节点的引用。该类提供了丰富的操作方法，包括节点插入、删除、查找、遍历、排序、分割、合并等功能，适用于各种开发场景。

## 主要功能

- **基础操作**：清空链表、判断链表是否为空、获取链表节点数量。
- **节点管理**：支持在链表头部、尾部插入节点，移除指定节点或值相同的所有节点。
- **查找与获取**：支持查找节点、获取链表的第一个节点和最后一个节点，以及根据索引获取节点。
- **遍历与操作**：提供了链表的正向和反向遍历方法，以及对节点的操作方法（如遍历执行回调、映射、过滤、累积）。
- **高级操作**：包括链表的反转、排序、合并、拆分、克隆等操作。
- **链表转换**：支持将链表转换为数组和从数组创建链表。

## 方法概述

### 构造函数与基础操作

- **`DoublyLinkedList()`**：构造函数，初始化为空链表。
- **`clear()`**：清空链表。
- **`isEmpty():Boolean`**：判断链表是否为空。
- **`getSize():Number`**：获取链表中节点的数量。

### 节点插入与删除

- **`addFirst(value:Object):Void`**：在链表头部插入一个新节点。
- **`addLast(value:Object):Void`**：在链表尾部插入一个新节点。
- **`removeFirst():Void`**：移除链表的第一个节点。
- **`removeLast():Void`**：移除链表的最后一个节点。
- **`insertAfter(existingNode:LLNode, value:Object):Void`**：在指定的现有节点之后插入一个新节点。
- **`insertBefore(existingNode:LLNode, value:Object):Void`**：在指定的现有节点之前插入一个新节点。
- **`remove(node:LLNode):Void`**：从链表中移除指定的节点。
- **`removeAll(value:Object):Void`**：移除链表中所有等于指定值的节点。

### 查找与获取

- **`find(value:Object):LLNode`**：查找包含指定值的节点。
- **`contains(value:Object):Boolean`**：判断链表中是否包含指定值。
- **`indexOf(value:Object):Number`**：获取指定值的索引。
- **`getNodeAt(index:Number):LLNode`**：根据索引获取节点。
- **`getFirst():LLNode`**：获取链表的第一个节点。
- **`getLast():LLNode`**：获取链表的最后一个节点。

### 遍历与操作

- **`traverseForward(callback:Function):Void`**：从 `head` 开始向 `tail` 遍历链表。
- **`traverseBackward(callback:Function):Void`**：从 `tail` 开始向 `head` 反向遍历链表。
- **`forEach(callback:Function):Void`**：遍历链表并对每个节点执行回调函数。
- **`map(callback:Function):DoublyLinkedList`**：对链表中的每个节点应用回调函数，并返回一个新的链表。
- **`filter(callback:Function):DoublyLinkedList`**：返回一个新的链表，其中包含所有满足条件的节点。
- **`reduce(callback:Function, initialValue:Object):Object`**：累积链表中的每个节点值，并返回累积结果。

### 链表转换

- **`toArray():Array`**：将链表转换为数组。
- **`fromArray(array:Array):Void`**：从数组创建链表。
- **`clone():DoublyLinkedList`**：克隆链表。
- **`join(separator:String):String`**：将链表节点值连接为字符串。

### 高级操作

- **`merge(list:DoublyLinkedList):Void`**：合并两个链表。
- **`split(index:Number):DoublyLinkedList`**：在指定索引位置拆分链表。
- **`splitAtNode(node:LLNode):DoublyLinkedList`**：根据指定节点拆分链表。
- **`sort(compareFunction:Function):Void`**：对链表中的节点进行排序。
- **`reverse():Void`**：反转链表。

### 辅助方法

- **`containsNode(node:LLNode):Boolean`**：检查节点是否存在于链表中。

## 使用示例

以下是如何使用 `DoublyLinkedList` 类的几个示例：

```actionscript
var list:DoublyLinkedList = new DoublyLinkedList();
list.addLast(1);
list.addLast(2);
list.addLast(3);

trace(list.getSize()); // 输出: 3

list.removeFirst();
trace(list.getFirst().getValue()); // 输出: 2

list.addFirst(0);
list.addLast(4);

trace(list.join(", ")); // 输出: 0, 2, 3, 4

var newList:DoublyLinkedList = list.split(2);
trace(list.join(", ")); // 输出: 0, 2
trace(newList.join(", ")); // 输出: 3, 4
```

## 注意事项

- **空链表处理**：在进行插入、删除等操作时，请确保正确处理空链表的情况，以避免意外错误。
- **内存管理**：对于频繁创建和删除节点的应用场景，建议定期调用 `clear()` 方法，释放内存。
- **排序方法**：`sort` 方法使用的是冒泡排序算法，适用于小规模链表排序。在处理大量数据时，可考虑优化排序算法。

## 扩展与维护

- **扩展性**：该类可以方便地进行扩展，比如添加自定义的节点处理逻辑或增加更多的辅助方法。
- **维护性**：代码风格统一，结构清晰，便于长期维护。建议在维护时保持现有的代码风格和结构，确保代码的可读性。

*/

import org.flashNight.naki.DataStructures.LLNode;

class org.flashNight.naki.DataStructures.DoublyLinkedList {
    private var head:LLNode = null;
    private var tail:LLNode = null;
    private var size:Number = 0;

    // 构造函数，初始化为空链表
    public function DoublyLinkedList() {
        // 初始化为空链表
    }

    // 清空链表
    public function clear():Void {
        head = null;
        tail = null;
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
        var newNode:LLNode = new LLNode(value);
        if (isEmpty()) {
            head = tail = newNode;
        } else {
            newNode.setNext(head);
            head.setPrev(newNode);
            head = newNode;
        }
        size++;
    }

    // 在链表尾部插入一个新节点
    public function addLast(value:Object):Void {
        var newNode:LLNode = new LLNode(value);
        if (isEmpty()) {
            head = tail = newNode;
        } else {
            newNode.setPrev(tail);
            tail.setNext(newNode);
            tail = newNode;
        }
        size++;
    }

    // 移除链表的第一个节点
    public function removeFirst():Void {
        if (isEmpty()) return;

        head = head.getNext();
        if (head != null) {
            head.setPrev(null);
        } else {
            tail = null;
        }
        size--;
    }

    // 移除链表的最后一个节点
    public function removeLast():Void {
        if (isEmpty()) return;

        tail = tail.getPrev();
        if (tail != null) {
            tail.setNext(null);
        } else {
            head = null;
        }
        size--;
    }

    // 在指定的现有节点之后插入一个新节点
    public function insertAfter(existingNode:LLNode, value:Object):Void {
        if (existingNode == null) return;

        var newNode:LLNode = new LLNode(value);
        var nextNode:LLNode = existingNode.getNext();

        newNode.setPrev(existingNode);
        newNode.setNext(nextNode);
        existingNode.setNext(newNode);

        if (nextNode != null) {
            nextNode.setPrev(newNode);
        } else {
            tail = newNode;
        }
        size++;
    }

    // 在指定的现有节点之前插入一个新节点
    public function insertBefore(existingNode:LLNode, value:Object):Void {
        if (existingNode == null) return;

        var newNode:LLNode = new LLNode(value);
        var prevNode:LLNode = existingNode.getPrev();

        newNode.setNext(existingNode);
        newNode.setPrev(prevNode);
        existingNode.setPrev(newNode);

        if (prevNode != null) {
            prevNode.setNext(newNode);
        } else {
            head = newNode;
        }
        size++;
    }

    // 从链表中移除指定的节点
    public function remove(node:LLNode):Void {
        if (node == null) return;

        if (node == head) {
            head = head.getNext();
            if (head != null) {
                head.setPrev(null);
            } else {
                tail = null;
            }
        } else if (node == tail) {
            tail = tail.getPrev();
            if (tail != null) {
                tail.setNext(null);
            } else {
                head = null;
            }
        } else {
            var prevNode:LLNode = node.getPrev();
            var nextNode:LLNode = node.getNext();
            prevNode.setNext(nextNode);
            nextNode.setPrev(prevNode);
        }
        size--;
    }

    // 移除链表中所有等于指定值的节点
    public function removeAll(value:Object):Void {
        var current:LLNode = head;
        
        while (current != null) {
            var next:LLNode = current.getNext();
            if (current.getValue() == value) {
                remove(current);
            }
            current = next;
        }
    }

    // 查找包含指定值的节点
    public function find(value:Object):LLNode {
        var current:LLNode = head;
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
        var current:LLNode = head;
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
    public function getNodeAt(index:Number):LLNode {
        if (index < 0 || index >= size) return null;

        var current:LLNode = head;
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
    public function getFirst():LLNode {
        return head;
    }

    // 获取链表的最后一个节点
    public function getLast():LLNode {
        return tail;
    }

    // 从head开始向tail遍历链表
    public function traverseForward(callback:Function):Void {
        var current:LLNode = head;
        while (current != null) {
            callback(current);
            current = current.getNext();
        }
    }

    // 从tail开始向head反向遍历链表
    public function traverseBackward(callback:Function):Void {
        var current:LLNode = tail;
        while (current != null) {
            callback(current);
            current = current.getPrev();
        }
    }

    // 反转链表
    public function reverse():Void {
        var current:LLNode = head;
        var temp:LLNode = null;

        while (current != null) {
            temp = current.getPrev();
            current.setPrev(current.getNext());
            current.setNext(temp);
            current = current.getPrev();
        }

        if (temp != null) {
            head = temp.getPrev();
        }
    }

    // 遍历链表并对每个节点执行回调函数
    public function forEach(callback:Function):Void {
        var current:LLNode = head;
        while (current != null) {
            callback(current.getValue());
            current = current.getNext();
        }
    }

    // 对链表中的每个节点应用回调函数，并返回一个新的链表
    public function map(callback:Function):DoublyLinkedList {
        var newList:DoublyLinkedList = new DoublyLinkedList();
        var current:LLNode = head;

        while (current != null) {
            newList.addLast(callback(current.getValue()));
            current = current.getNext();
        }

        return newList;
    }

    // 返回一个新的链表，其中包含所有满足条件的节点
    public function filter(callback:Function):DoublyLinkedList {
        var filteredList:DoublyLinkedList = new DoublyLinkedList();
        var current:LLNode = head;

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
        var current:LLNode = head;

        while (current != null) {
            accumulator = callback(accumulator, current.getValue());
            current = current.getNext();
        }

        return accumulator;
    }

    // 将链表转换为数组
    public function toArray():Array {
        var array:Array = [];
        var current:LLNode = head;

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
    public function clone():DoublyLinkedList {
        var clonedList:DoublyLinkedList = new DoublyLinkedList();
        var current:LLNode = head;
        
        while (current != null) {
            clonedList.addLast(current.getValue());
            current = current.getNext();
        }
        
        return clonedList;
    }

    // 合并两个链表
    public function merge(list:DoublyLinkedList):Void {
        if (list.isEmpty()) return;

        if (this.isEmpty()) {
            this.head = list.getFirst();
            this.tail = list.getLast();
        } else {
            this.tail.setNext(list.getFirst());
            list.getFirst().setPrev(this.tail);
            this.tail = list.getLast();
        }

        this.size += list.getSize();
    }

    // 将链表节点值连接为字符串
    public function join(separator:String):String {
        var result:String = "";
        var current:LLNode = head;

        while (current != null) {
            result += current.getString();
            if (current.getNext() != null) {
                result += separator;
            }
            current = current.getNext();
        }

        return result;
    }

    // 在指定索引位置拆分链表
    public function split(index:Number):DoublyLinkedList {
        if (index < 0 || index >= size) return null;

        var current:LLNode = getNodeAt(index);
        var newList:DoublyLinkedList = new DoublyLinkedList();
        
        if (current != null) {
            newList.head = current;
            newList.tail = this.tail;
            newList.size = this.size - index;

            this.tail = current.getPrev();
            if (this.tail != null) {
                this.tail.setNext(null);
            } else {
                this.head = null;
            }

            this.size = index;
            newList.head.setPrev(null);
        }

        return newList;
    }

    // 根据指定节点拆分链表
    public function splitAtNode(node:LLNode):DoublyLinkedList {
        if (node == null || !containsNode(node)) return null;

        var newList:DoublyLinkedList = new DoublyLinkedList();
        
        // 如果 node 是头部节点，则整个链表移到新的链表中
        if (node == head) {
            newList.head = head;
            newList.tail = tail;
            newList.size = size;
            
            // 清空原链表
            clear();
        } else {
            // 否则，处理普通情况
            var prevNode:LLNode = node.getPrev();
            
            // 分割点前的链表
            prevNode.setNext(null);
            tail = prevNode;
            
            // 分割点后的链表
            newList.head = node;
            newList.tail = tail;
            node.setPrev(null);
            
            // 更新两个链表的 size
            var current:LLNode = newList.head;
            var newSize:Number = 0;
            
            while (current != null) {
                newSize++;
                newList.tail = current;
                current = current.getNext();
            }
            
            newList.size = newSize;
            this.size -= newSize;
        }
        
        return newList;
    }

    // 辅助方法：检查节点是否存在于链表中
    public function containsNode(node:LLNode):Boolean {
        var current:LLNode = head;
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
            var current:LLNode = head;
            
            while (current != null && current.getNext() != null) {
                var next:LLNode = current.getNext();
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
