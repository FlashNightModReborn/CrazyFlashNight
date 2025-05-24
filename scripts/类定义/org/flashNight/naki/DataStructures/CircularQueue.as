class org.flashNight.naki.DataStructures.CircularQueue {
    
    // 队列的数组
    private var items:Array;
    
    // 队列的容量
    private var capacity:Number;
    
    // 队列的头部指针
    private var front:Number;
    
    // 队列的尾部指针
    private var rear:Number;
    
    // 队列中元素的数量
    private var count:Number;
    
    /**
     * 构造函数，初始化循环队列
     * @param capacity 队列的容量
     */
    public function CircularQueue(capacity:Number) {
        this.capacity = capacity;
        this.items = new Array(capacity);
        this.front = 0;
        this.rear = 0;
        this.count = 0;
    }
    
    /**
     * 入队操作，将元素添加到队列的尾部
     * @param value 要添加的元素
     * @return 如果成功入队，返回 true；如果队列已满，返回 false
     */
    public function enqueue(value:Object):Boolean {
        if (this.isFull()) {
            return false; // 队列已满
        }
        this.items[this.rear] = value;
        this.rear = (this.rear + 1) % this.capacity; // 循环移动尾部指针
        this.count++;
        return true;
    }
    
    /**
     * 出队操作，移除并返回队列的头部元素
     * @return 队列头部的元素，如果队列为空则返回 null
     */
    public function dequeue():Object {
        if (this.isEmpty()) {
            return null; // 队列为空
        }
        var value:Object = this.items[this.front];
        this.front = (this.front + 1) % this.capacity; // 循环移动头部指针
        this.count--;
        return value;
    }
    
    /**
     * 查看队列头部的元素但不移除
     * @return 队列头部的元素，如果队列为空则返回 null
     */
    public function peek():Object {
        if (this.isEmpty()) {
            return null;
        }
        return this.items[this.front];
    }
    
    /**
     * 检查队列是否为空
     * @return 如果队列为空，返回 true；否则返回 false
     */
    public function isEmpty():Boolean {
        return this.count == 0;
    }
    
    /**
     * 检查队列是否已满
     * @return 如果队列已满，返回 true；否则返回 false
     */
    public function isFull():Boolean {
        return this.count == this.capacity;
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
        this.front = 0;
        this.rear = 0;
        this.count = 0;
    }
    
    /**
     * 遍历队列中的所有元素，并对每个元素执行回调函数
     * @param callback 需要执行的回调函数，格式为 function(value:Object)
     */
    public function forEach(callback:Function):Void {
        for (var i:Number = 0; i < this.count; i++) {
            var index:Number = (this.front + i) % this.capacity; // 计算元素实际位置
            callback(this.items[index]);
        }
    }
}
