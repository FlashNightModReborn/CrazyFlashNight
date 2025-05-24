/**
 * 环形队列 - 高效固定容量循环存储
 * 
 * 说明：
 * 1. 基于固定容量数组实现，当队列满时，新入队元素自动覆盖最旧数据；
 * 2. 支持随机访问、批量入队、FIFO 弹出、遍历和调试输出；
 * 3. 提供动态调整容量（resize）方法，保留最新数据；
 * 4. 内部使用 _head（队列头）、_cursor（下一写入位置）与 _size（当前数据量）来高效管理队列。
 * 
 * 使用场景：
 * 数据缓存、轨迹记录、日志收集、实时数据显示等需要固定容量和高效循环写入的应用场合。
 */
class org.flashNight.naki.DataStructures.RingBuffer  {
    // --------------------------
    // 内部状态变量
    // --------------------------
    
    /** 内部存储数组 */
    private var _buffer:Array;
    /** 队列最大容量（固定值） */
    private var _capacity:Number;
    /** 当前已存储的数据数量（≤ _capacity） */
    private var _size:Number;
    /**
     * 指向下一次写入的位置（队尾位置）；队列满时新数据将覆盖最旧的数据（并同时更新 _head）。
     */
    private var _cursor:Number;
    /**
     * 队列头，指向最旧数据所在位置，直接用于快速计算真实索引。
     */
    private var _head:Number;
    
    // --------------------------
    // 构造函数
    // --------------------------
    
    /**
     * 构造函数
     * @param capacity 队列容量，必须 ≥ 1
     * @param fillWith 预填充值（可选）；当未提供初始数据时使用该值填充整个队列
     * @param initialData 初始数据数组（可选），当数据长度超过容量时，仅保留最新数据
     */
    public function RingBuffer(capacity:Number, fillWith:Object, initialData:Array) {
        if (capacity < 1) {
            throw new Error("Capacity must be ≥ 1");
        }
        this._capacity = capacity;
        this._buffer = new Array(capacity);
        this._size = 0;
        this._cursor = 0;
        this._head = 0;
        
        if (initialData != null) {
            // 保留最新 capacity 个数据
            var dataToAdd:Array = initialData.slice(-capacity);
            this.pushMany(dataToAdd);
        } else if (fillWith != null) {
            // 使用预填充值填充整个队列
            for (var i:Number = 0; i < capacity; i++) {
                this._buffer[i] = fillWith;
            }
            this._size = capacity;
            this._cursor = 0;
            this._head = 0;
        }
    }
    
    // --------------------------
    // 核心操作方法
    // --------------------------
    
    /**
     * 添加单个数据项。当队列已满时会自动覆盖最旧数据。
     * @param item 要添加的数据项；若 item 为 undefined，则不做操作
     */
    public function push(item:Object):Void {
        if (item === undefined) return;
        var cap:Number = this._capacity;
        this._buffer[this._cursor] = item;
        if (this._size < cap) {
            this._size++;
        } else {
            // 队列已满，移动头部指针
            this._head = (this._head + 1) % cap;
        }
        this._cursor = (this._cursor + 1) % cap;
    }
    
    /**
     * 批量添加数据项。通过局部变量和一次性循环减少函数调用开销。
     * @param items 数组形式的多个数据项
     */
    public function pushMany(items:Array):Void {
        if (items == null) return;
        var cap:Number = this._capacity;
        var buf:Array = this._buffer;
        var s:Number = this._size;
        var cur:Number = this._cursor;
        var head:Number = this._head;
        
        for (var i:Number = 0, len:Number = items.length; i < len; i++) {
            var item:Object = items[i];
            if (item === undefined) continue;
            buf[cur] = item;
            if (s < cap) {
                s++;
            } else {
                head = (head + 1) % cap;
            }
            cur = (cur + 1) % cap;
        }
        this._size = s;
        this._cursor = cur;
        this._head = head;
    }
    
    /**
     * 获取指定索引处的数据项，支持负数索引（负数表示从队尾反向取值）。
     * @param index 索引号（范围：0 到 size-1）；若 index 为负，自动转换，例如 -1 表示最后一个元素
     * @return 对应的数据项；队列为空时返回 undefined；索引越界时抛出 Error
     */
    public function get(index:Number):Object {
        if (this._size == 0) return undefined;
        var s:Number = this._size;
        // 处理负数索引
        if (index < 0) {
            index += s;
        }
        if (index < 0 || index >= s) {
            throw new Error("Index " + index + " out of bounds [0-" + (s - 1) + "]");
        }
        return this._buffer[(this._head + index) % this._capacity];
    }
    
    /**
     * 清空队列内容，并可选使用指定的填充值重新填充队列。
     * @param fillWith 如果提供该值，则以该值填充整个队列
     */
    public function clear(fillWith:Object):Void {
        var cap:Number = this._capacity;
        if (fillWith != null) {
            for (var i:Number = 0; i < cap; i++) {
                this._buffer[i] = fillWith;
            }
            this._size = cap;
            this._head = 0;
            this._cursor = 0;
        } else {
            // 不预填时，直接置 undefined
            for (var j:Number = 0; j < cap; j++) {
                this._buffer[j] = undefined;
            }
            this._size = 0;
            this._head = 0;
            this._cursor = 0;
        }
    }

    /**
     * 使用新数据重置 RingBuffer 的状态。
     * @param newData 数据数组，若长度超过容量，则保留后面的部分
     */
    public function reset(newData:Array):Void {
        if (newData == null) return;

        // 若 newData 长度超过容量，则只保留最新数据
        if (newData.length > this._capacity) {
            newData = newData.slice(newData.length - this._capacity);
        }
        
        var len:Number = newData.length;
        // 更新内部存储数组：直接覆盖前 len 个数据，其余部分可以置为 undefined 或保留原数据（不影响逻辑）
        for (var i:Number = 0; i < len; i++) {
            this._buffer[i] = newData[i];
        }
        // 若 newData 少于容量，也可选择将剩余位置置为 undefined（视具体需求而定）
        for (i = len; i < this._capacity; i++) {
            this._buffer[i] = undefined;
        }
        
        // 更新状态变量
        this._head = 0;
        this._size = len;
        this._cursor = (len) % this._capacity;
    }

    /**
     * 用指定的单个数据项替换 RingBuffer 中所有数据。
     * 该方法先清空当前缓冲区，然后以最高效率将该单一数据项作为唯一数据存入，
     * 更新状态变量使得队列仅包含这一项。
     * @param item 要替换为的新数据项；如果 item 为 undefined，则不做操作
     */
    public function replaceSingle(item:Object):Void {
        if (item === undefined) return;
        
        // 清空内部数组：仅清空逻辑，不需要设置每个元素为 undefined（也可根据需求选择清空全部数组）
        // 这里选择直接重置状态变量，并将新数据填充到第一个位置
        this._buffer[0] = item;
        
        // 根据容量，将其他位置置为 undefined（可选：如果不关心未使用区域，可以省略此步骤）
        for (var i:Number = 1; i < this._capacity; i++) {
            this._buffer[i] = undefined;
        }
        
        // 更新 RingBuffer 内部状态：队头为 0，队尾指针为下一个位置（取模处理），数据数量为 1
        this._head = 0;
        this._cursor = 1 % this._capacity;
        this._size = 1;
    }


    
    /**
     * 移除并返回队列头部的数据项（先进先出）。
     * @return 取出的数据项；若队列为空则返回 undefined
     */
    public function pop():Object {
        if (this._size == 0) return undefined;
        var item:Object = this._buffer[this._head];
        this._buffer[this._head] = undefined;
        this._head = (this._head + 1) % this._capacity;
        this._size--;
        if (this._size == 0) {
            this._head = 0;
            this._cursor = 0;
        }
        return item;
    }
    
    /**
     * 查看队列中指定位置的数据项，但不移除（与 get 操作相同）。
     * @param index 索引号，默认为 0（即队列头部的数据项）
     * @return 对应的数据项
     */
    public function peek(index:Number):Object {
        if (index == undefined) index = 0;
        return this.get(index);
    }
    
    /**
     * 将队列中的数据项依次输出为数组（从最早到最新）。
     * @return 顺序数组；若队列为空则返回空数组
     */
    public function toArray():Array {
        var arr:Array = [];
        var s:Number = this._size;
        if (s == 0) return arr;
        var cap:Number = this._capacity;
        for (var i:Number = 0; i < s; i++) {
            arr.push(this._buffer[(this._head + i) % cap]);
        }
        return arr;
    }

    /**
     * 将队列中的数据项按逆序输出为数组（从最新到最旧）
     * @return 逆序数组；若队列为空则返回空数组
     */
    public function toReversedArray():Array {
        var arr:Array = [];
        var s:Number = this._size;
        if (s == 0) return arr;
        var cap:Number = this._capacity;
        // 从最新数据开始反向遍历
        for (var i:Number = 0; i < s; i++) {
            var idx:Number = (this._cursor - 1 - i + cap) % cap;
            arr.push(this._buffer[idx]);
        }
        return arr;
    }

    
    /**
     * 遍历队列中所有数据项，并调用回调函数。
     * @param callback 回调函数，形式为 function(item, index, ringBuffer)
     */
    public function forEach(callback:Function):Void {
        var s:Number = this._size;
        if (s == 0) return;
        var cap:Number = this._capacity;
        for (var i:Number = 0; i < s; i++) {
            callback(this._buffer[(this._head + i) % cap], i, this);
        }
    }
    
    /**
     * 返回当前队列状态的字符串表示，便于调试。
     * @return 包含容量、数据项数量以及队列内容的描述字符串
     */
    public function toString():String {
        var dataStr:String = "[]";
        if (this._size > 0) {
            var arr:Array = this.toArray();
            dataStr = "[" + arr.join(",") + "]";
        }
        return "[RingBuffer capacity=" + this._capacity + " size=" + this._size + " data=" + dataStr + "]";
    }
    
    // --------------------------
    // 只读属性与状态判断
    // --------------------------
    
    /**
     * 获取队列头部数据项（最早添加的）。
     */
    public function get head():Object {
        return this.get(0);
    }
    
    /**
     * 获取队列尾部数据项（最新添加的）。
     */
    public function get tail():Object {
        if (this._size == 0) return undefined;
        return this.get(this._size - 1);
    }
    
    /**
     * 获取队列最大容量。
     */
    public function get capacity():Number {
        return this._capacity;
    }
    
    /**
     * 获取队列当前存储的数据项数量。
     */
    public function get size():Number {
        return this._size;
    }
    
    /**
     * 判断队列是否为空。
     * @return 若队列为空则返回 true，否则 false
     */
    public function isEmpty():Boolean {
        return (this._size == 0);
    }
    
    /**
     * 判断队列是否已满。
     * @return 若队列已满则返回 true，否则 false
     */
    public function isFull():Boolean {
        return (this._size == this._capacity);
    }
    
    /**
     * 检查队列中是否包含指定数据项（使用严格相等 === 判断）。
     * @param item 待检查的数据项
     * @return 若包含则返回 true，否则 false
     */
    public function contains(item:Object):Boolean {
        var s:Number = this._size;
        if (s == 0) return false;
        var cap:Number = this._capacity;
        for (var i:Number = 0; i < s; i++) {
            if (this._buffer[(this._head + i) % cap] === item) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 调整队列容量，保留最新数据；若新容量小于当前存储数据的数量，则截断最旧数据。
     * @param newCapacity 新的容量，必须 ≥ 1
     */
    public function resize(newCapacity:Number):Void {
        if (newCapacity < 1) {
            throw new Error("Capacity must be ≥ 1");
        }
        if (newCapacity == this._capacity) return;
        // 先通过 toArray 获取现有数据（顺序排列）
        var oldData:Array = this.toArray();
        // 初始化新数组
        this._buffer = new Array(newCapacity);
        this._capacity = newCapacity;
        // 保留最新数据，若超出新容量则截断最旧的数据
        if (oldData.length > newCapacity) {
            oldData = oldData.slice(oldData.length - newCapacity);
        }
        this._size = oldData.length;
        this._head = 0;
        this._cursor = this._size % newCapacity;
        for (var i:Number = 0; i < this._size; i++) {
            this._buffer[i] = oldData[i];
        }
    }
}
