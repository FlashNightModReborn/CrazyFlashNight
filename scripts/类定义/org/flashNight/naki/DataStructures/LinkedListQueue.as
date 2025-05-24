
import org.flashNight.naki.DataStructures.SLNode;

class org.flashNight.naki.DataStructures.LinkedListQueue {
    
    // 队列的头部节点
    private var front:SLNode = null;
    
    // 队列的尾部节点
    private var rear:SLNode = null;
    
    // 队列中元素的数量
    private var count:Number = 0;
    
    /**
     * 构造函数，初始化队列
     */
    public function LinkedListQueue() {
        // 初始时，队列为空
        this.front = null;
        this.rear = null;
        this.count = 0;
    }
    
    /**
     * 入队操作，将元素添加到队列的尾部
     * @param value 要添加的元素
     */
    public function enqueue(value:Object):Void {
        var newNode:SLNode = new SLNode(value);
        if (this.rear == null) {
            // 如果队列为空，新节点同时作为头部和尾部
            this.front = newNode;
            this.rear = newNode;
        } else {
            // 将新节点添加到队列的尾部
            this.rear.setNext(newNode);
            this.rear = newNode;
        }
        this.count++;
    }
    
    /**
     * 出队操作，移除并返回队列的头部元素
     * @return 队列头部的元素，如果队列为空则返回 null
     */
    public function dequeue():Object {
        if (this.front == null) {
            // 如果队列为空，无法出队
            return null;
        }
        var value:Object = this.front.getValue();
        this.front = this.front.getNext();
        if (this.front == null) {
            // 如果出队后队列为空，重置尾部指针
            this.rear = null;
        }
        this.count--;
        return value;
    }
    
    /**
     * 查看队列头部的元素但不移除
     * @return 队列头部的元素，如果队列为空则返回 null
     */
    public function peek():Object {
        if (this.front == null) {
            return null;
        }
        return this.front.getValue();
    }
    
    /**
     * 检查队列是否为空
     * @return 如果队列为空，返回 true；否则返回 false
     */
    public function isEmpty():Boolean {
        return this.count == 0;
    }
    
    /**
     * 获取队列中元素的数量
     * @return 队列中元素的数量
     */
    public function getCount():Number {
        return this.count;
    }
    
    /**
     * 清空队列
     */
    public function clear():Void {
        this.front = null;
        this.rear = null;
        this.count = 0;
    }
    
    /**
     * 遍历队列中的所有元素，并对每个元素执行回调函数
     * @param callback 需要执行的回调函数，格式为 function(value:Object)
     */
    public function forEach(callback:Function):Void {
        var current:SLNode = this.front;
        while (current != null) {
            callback(current.getValue());
            current = current.getNext();
        }
    }
}
