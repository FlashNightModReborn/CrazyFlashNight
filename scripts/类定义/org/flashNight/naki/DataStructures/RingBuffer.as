/**
 * 环形队列 - 高效固定容量循环存储
 * 
 * 说明：
 * 1. 采用固定容量数组实现，当队列满时，新入队元素自动覆盖最旧数据。
 * 2. 支持随机访问（含负数索引）、批量入队、FIFO 弹出（pop）、遍历与调试输出。
 * 3. 提供动态调整容量（resize）功能，保留最新数据。
 * 4. 内部仅维护 _cursor（下一写入位置）与 _size（当前数据量），通过 _cursor 和 _size 动态计算队列头位置。
 *
 * 使用场景：
 * 适用于数据缓存、轨迹记录、日志收集、实时数据显示等需要固定容量和高效循环写入的场景。
 */
class org.flashNight.naki.DataStructures.RingBuffer {
    // 内部存储数组
    private var _buffer:Array;
    // 队列最大容量（固定值）
    private var _capacity:Number;
    // 当前已存储的数据量（≤ _capacity）
    private var _size:Number;
    // 下一次写入元素的位置索引，相当于队列的尾部
    private var _cursor:Number;
    
    /**
     * 构造函数
     * @param capacity    队列容量（必须 ≥ 1）
     * @param fillWith    预填充值（可选），当不传入初始数据时，使用该值填充整个队列
     * @param initialData 初始数据数组（可选），若数组长度超出容量则仅保留最新数据
     */
    public function RingBuffer(capacity:Number, fillWith:Object /* = null */, initialData:Array /* = null */) {
        if (capacity < 1) {
            throw new Error("Capacity must be ≥ 1");
        }
        this._capacity = capacity;
        this._buffer = new Array(capacity);
        this._size = 0;
        this._cursor = 0;
        
        // 若提供初始数据，则截取末尾部分作为初始数据
        if (initialData != null) {
            var dataToAdd:Array = initialData.slice(-capacity); // 保留最新数据
            for (var i:Number = 0; i < dataToAdd.length; i++) {
                this.push(dataToAdd[i]);
            }
        } else if (fillWith != null) {
            // 使用预填充值初始化整个队列
            for (i = 0; i < capacity; i++) {
                this._buffer[i] = fillWith;
            }
            this._size = capacity;
            this._cursor = 0; // 此时写入指针可视实际需求决定（这里置为0表示后续覆盖）
        }
    }
    
    // =====================================
    // 核心操作
    // =====================================
    
    /**
     * 添加单个元素（当队列已满时自动覆盖最旧的元素）
     * @param item 要添加的数据项（过滤 undefined 值）
     */
    public function push(item:Object):Void {
        if (item == undefined) return; // 过滤非法值
        this._buffer[this._cursor] = item;
        this._cursor = (this._cursor + 1) % this._capacity;
        if (this._size < this._capacity) {
            this._size++;
        }
    }
    
    /**
     * 批量添加元素（依次调用 push 操作）
     * @param items 数组形式的多个数据项
     */
    public function pushMany(items:Array):Void {
        if (items == null) return;
        for (var i:Number = 0; i < items.length; i++) {
            this.push(items[i]);
        }
    }
    
    /**
     * 获取指定索引处的元素（支持负数索引，负数索引表示从队尾反向取值）
     * @param index 索引号（范围：0 到 size-1；负数索引自动转换，例如 -1 表示最后一个元素）
     * @return 对应的元素，若队列为空则返回 undefined；索引越界则抛出 RangeError
     */
    public function get(index:Number):Object {
        if (this._size == 0) return undefined;
        // 处理负数索引
        if (index < 0) {
            index += this._size;
        }
        if (index < 0 || index >= this._size) {
            throw new RangeError("Index " + index + " out of bounds [0-" + (this._size - 1) + "]");
        }
        // 计算逻辑起始位置：(cursor - size + capacity) mod capacity 为队列头位置
        var pos:Number = (this._cursor - this._size + index + this._capacity) % this._capacity;
        return this._buffer[pos];
    }
    
    /**
     * 清空队列内容，并可选使用指定值重新填充队列
     * @param fillWith 如果提供该值，则以该值填充整个队列
     */
    public function clear(fillWith:Object /* = null */):Void {
        this._size = 0;
        this._cursor = 0;
        if (fillWith != null) {
            for (var i:Number = 0; i < this._capacity; i++) {
                this._buffer[i] = fillWith;
            }
            this._size = this._capacity;
        } else {
            this._buffer = new Array(this._capacity);
        }
    }
    
    // =====================================
    // FIFO 出队操作（删除队头元素）
    // =====================================
    
    /**
     * 从队列头部取出（删除）元素（先进先出）
     * @return 取出的元素；若队列为空则返回 undefined
     */
    public function pop():Object {
        if (this._size == 0) return undefined;
        // 队头位置：(_cursor - _size + capacity) mod capacity
        var headIndex:Number = (this._cursor - this._size + this._capacity) % this._capacity;
        var item:Object = this._buffer[headIndex];
        // 可选择清空该位置（非必要）
        this._buffer[headIndex] = undefined;
        this._size--;
        // 当队列为空时，可将 _cursor 重置为 0
        if (this._size == 0) {
            this._cursor = 0;
        }
        return item;
    }
    
    /**
     * 查看队列中指定位置的元素，但不移除（同 get 操作）
     * @param index 索引号，默认为 0（即队列头部元素）
     * @return 对应的元素
     */
    public function peek(index:Number /* = 0 */):Object {
        if (index == undefined) index = 0;
        return this.get(index);
    }
    
    // =====================================
    // 动态容量管理
    // =====================================
    
    /**
     * 调整队列容量，保留最新数据（若新容量小于现存数据，则截断最旧数据）
     * @param newCapacity 新的容量（必须 ≥ 1）
     */
    public function resize(newCapacity:Number):Void {
        if (newCapacity < 1) {
            throw new Error("Capacity must be ≥ 1");
        }
        if (newCapacity == this._capacity) return;
        // 先将现有数据转换为顺序数组
        var oldData:Array = this.toArray();
        // 新数组初始化
        this._buffer = new Array(newCapacity);
        this._capacity = newCapacity;
        // 保留最新数据：若旧数据量超过新容量，则截断前面的（最旧）的数据
        if (oldData.length > newCapacity) {
            oldData = oldData.slice(oldData.length - newCapacity);
        }
        this._size = oldData.length;
        // 重新设置 _cursor：指向下一个写入位置，即队列头 + size（取模）
        // 这里可以直接将 _cursor 设置为 _size，因为我们从下标 0 开始写入新数组即可
        this._cursor = this._size % newCapacity;
        for (var i:Number = 0; i < this._size; i++) {
            this._buffer[i] = oldData[i];
        }
    }
    
    // =====================================
    // 状态查询与转换
    // =====================================
    
    /**
     * 转换队列内数据为顺序数组（从最早到最新）
     * @return 顺序数组，若队列为空则返回空数组
     */
    public function toArray():Array {
        var arr:Array = [];
        if (this._size == 0) return arr;
        var start:Number = (this._cursor - this._size + this._capacity) % this._capacity;
        for (var i:Number = 0; i < this._size; i++) {
            arr.push(this._buffer[(start + i) % this._capacity]);
        }
        return arr;
    }
    
    /**
     * 遍历队列中所有元素，并调用回调函数
     * @param callback 回调函数，形式为 function(item, index, ringBuffer)
     */
    public function forEach(callback:Function):Void {
        if (this._size == 0) return;
        var start:Number = (this._cursor - this._size + this._capacity) % this._capacity;
        for (var i:Number = 0; i < this._size; i++) {
            var pos:Number = (start + i) % this._capacity;
            callback(this._buffer[pos], i, this);
        }
    }
    
    // =====================================
    // 调试与扩展方法
    // =====================================
    
    /**
     * 返回当前队列状态的字符串表示，便于调试
     * @return 包含容量、大小以及队列数据的描述字符串
     */
    public function toString():String {
        return "[RingBuffer capacity=" + this._capacity + " size=" + this._size + " data=" + this.toArray() + "]";
    }
    
    // =====================================
    // 只读属性与状态判断
    // =====================================
    
    /**
     * 获取队列头部元素（最早添加的元素）
     */
    public function get head():Object {
        return this.get(0);
    }
    
    /**
     * 获取队列尾部元素（最新添加的元素）
     */
    public function get tail():Object {
        return this.get(this._size - 1);
    }
    
    /**
     * 获取队列最大容量
     */
    public function get capacity():Number {
        return this._capacity;
    }
    
    /**
     * 获取队列当前存储的数据项数量
     */
    public function get size():Number {
        return this._size;
    }
    
    /**
     * 判断队列是否为空
     * @return 若为空则返回 true，否则 false
     */
    public function isEmpty():Boolean {
        return this._size == 0;
    }
    
    /**
     * 判断队列是否已满
     * @return 若已满则返回 true，否则 false
     */
    public function isFull():Boolean {
        return this._size == this._capacity;
    }
    
    /**
     * 检查队列中是否包含指定元素（使用严格相等 === 判断）
     * @param item 待检查的元素
     * @return 包含则返回 true，否则返回 false
     */
    public function contains(item:Object):Boolean {
        if (this._size == 0) return false;
        var start:Number = (this._cursor - this._size + this._capacity) % this._capacity;
        for (var i:Number = 0; i < this._size; i++) {
            if (this._buffer[(start + i) % this._capacity] === item) {
                return true;
            }
        }
        return false;
    }
}
