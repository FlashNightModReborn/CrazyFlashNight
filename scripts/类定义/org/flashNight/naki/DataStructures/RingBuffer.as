/**
 * 环形队列 - 高效固定容量循环存储
 * 
 * 说明：
 * 1. 采用固定容量数组实现，当队列满时，新入队元素自动覆盖最旧数据。
 * 2. 支持随机访问（含负数索引）、批量入队、FIFO 弹出（pop）、遍历与调试输出。
 * 3. 提供动态调整容量（resize）功能，保留最新数据。
 * 4. 内部维护 _head（队列头，下一个被读取的最旧元素下标）、_cursor（下一写入位置）与 _size（当前数据量），
 *    通过 _head 直接获得队列头，减少重复计算的开销。
 *
 * 使用场景：
 * 适用于数据缓存、轨迹记录、日志收集、实时数据显示等需要固定容量和高效循环写入的场景。
 */
class org.flashNight.naki.DataStructures.RingBuffer {
    // --------------------------
    // 内部状态变量
    // --------------------------
    
    /** 内部存储数组 */
    private var _buffer:Array;
    /** 队列最大容量（固定值） */
    private var _capacity:Number;
    /** 当前已存储的数据量（≤ _capacity） */
    private var _size:Number;
    /**
     * 指向下一次写入元素的位置索引，相当于队列的尾部；
     * 当队列未满时，_cursor 随着 push 递增，
     * 当队列已满时，新数据覆盖 _cursor 同时更新 _head。
     */
    private var _cursor:Number;
    /**
     * 队列头，下标指向最旧数据所在位置，
     * 用于快速计算 get() 时的真实索引。维护不必每次计算。
     */
    private var _head:Number;
    
    // --------------------------
    // 构造函数
    // --------------------------
    
    /**
     * 构造函数
     * @param capacity    队列容量（必须 ≥ 1）
     * @param fillWith    预填充值（可选），若不提供初始数据时，使用该值填充整个队列
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
        this._head = 0;
        
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
            // 此时队列头为 0，下一写入位置也为 0，后续 push 会覆盖最旧数据
            this._cursor = 0;
            this._head = 0;
        }
    }
    
    // --------------------------
    // 核心操作方法
    // --------------------------
    
    /**
     * 添加单个元素（当队列已满时自动覆盖最旧的元素）
     * @param item 要添加的数据项（若 item 为 undefined，则不做入队操作）
     */
    public function push(item:Object):Void {
        if (item !== undefined) {
            // 缓存局部变量
            var cap:Number = this._capacity;
            var c:Number = this._cursor;

            // 写入元素到 _cursor 所指位置
            this._buffer[c] = item;
            
            // 在队列已满时，把 head 加 1
            if (this._size < cap) {
                this._size++;
            } else {
                // 队列已满，新数据覆盖时，需要“丢掉”最旧的数据
                this._head = (this._head + 1) % cap;
            }
            this._buffer[c] = item;
            this._cursor = (c + 1) % cap;
                
        };
    }
    
    /**
     * 批量添加元素（依次调用 push 操作）
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
            var it:Object = items[i];
            if (it === undefined) continue;

            buf[cur] = it;

            if (s < cap) {
                s++;
            } else {
                // 队列满：丢弃最旧数据，head 往前移一格
                head = (head + 1) % cap;
            }

            cur = (cur + 1) % cap;
        }

        this._cursor = cur;
        this._size = s;
        this._head = head;
    }

    
    /**
     * 获取指定索引处的元素（支持负数索引，负数索引表示从队尾反向取值）
     * @param index 索引号（范围：0 到 size-1；若 index 为负，自动转换，例如 -1 表示最后一个元素）
     * @return 对应的元素；若队列为空则返回 undefined；索引越界抛出 Error
     */
    public function get(index:Number):Object {
        // 若队列为空则直接返回 undefined
        if (this._size == 0) return undefined;
        var s:Number = this._size;
        // 处理负数索引
        if (index < 0) {
            index += s;
        }
        if (index < 0 || index >= s) {
            throw new Error("Index " + index + " out of bounds [0-" + (s - 1) + "]");
        }
        // 利用 _head 直接计算真实索引（仅一次取模操作）
        return this._buffer[(this._head + index) % this._capacity];
    }
    
    /**
     * 清空队列内容，并可选使用指定值重新填充队列
     * @param fillWith 如果提供该值，则以该值填充整个队列
     */
    public function clear(fillWith:Object /* = null */):Void {
        var cap:Number = this._capacity;
        if (fillWith != null) {
            // 预填充值方式：直接填充整个数组
            for (var i:Number = 0; i < cap; i++) {
                this._buffer[i] = fillWith;
            }
            this._size = cap;
            // 重置头部与游标，后续 push 会覆盖最旧数据
            this._head = 0;
            this._cursor = 0;
        } else {
            // 不预填时，避免重新创建数组，直接将每个元素赋值为 undefined
            for (i = 0; i < cap; i++) {
                this._buffer[i] = undefined;
            }
            this._size = 0;
            this._head = 0;
            this._cursor = 0;
        }
    }
    
    /**
     * 从队列头部取出（删除）元素（先进先出）
     * @return 取出的元素；若队列为空则返回 undefined
     */
    public function pop():Object {
        if (this._size == 0) return undefined;
        // 直接获取队列头处的元素
        var item:Object = this._buffer[this._head];
        // 清空该位置（可选）
        this._buffer[this._head] = undefined;
        // 更新头部索引：加1后取模
        this._head = (this._head + 1) % this._capacity;
        this._size--;
        // 若队列清空，则将 _cursor 与 _head 重置为 0
        if (this._size == 0) {
            this._head = 0;
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
    
    // --------------------------
    // 动态容量管理方法
    // --------------------------
    
    /**
     * 调整队列容量，保留最新数据（若新容量小于现存数据，则截断最旧数据）
     * @param newCapacity 新的容量（必须 ≥ 1）
     */
    public function resize(newCapacity:Number):Void {
        if (newCapacity < 1) {
            throw new Error("Capacity must be ≥ 1");
        }
        if (newCapacity == this._capacity) return;
        // 先将现有数据按顺序保存在新数组中
        var oldData:Array = this.toArray();
        // 新数组初始化
        this._buffer = new Array(newCapacity);
        this._capacity = newCapacity;
        // 保留最新数据：若旧数据量超过新容量，则截断最旧的数据
        if (oldData.length > newCapacity) {
            oldData = oldData.slice(oldData.length - newCapacity);
        }
        this._size = oldData.length;
        // 重新设置 _head 与 _cursor：从 0 开始重新写入新数组
        this._head = 0;
        this._cursor = this._size % newCapacity;
        for (var i:Number = 0; i < this._size; i++) {
            this._buffer[i] = oldData[i];
        }
    }
    
    // --------------------------
    // 状态查询与转换方法
    // --------------------------
    
    /**
     * 转换队列内数据为顺序数组（从最早到最新）
     * @return 顺序数组；若队列为空则返回空数组
     */
    public function toArray():Array {
        var arr:Array = [];
        if (this._size == 0) return arr;
        var s:Number = this._size;
        var cap:Number = this._capacity;
        // 从 _head 开始按顺序取出数据
        for (var i:Number = 0; i < s; i++) {
            arr.push(this._buffer[(this._head + i) % cap]);
        }
        return arr;
    }
    
    /**
     * 遍历队列中所有元素，并调用回调函数
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
    
    // --------------------------
    // 调试与扩展方法
    // --------------------------
    
    /**
     * 返回当前队列状态的字符串表示，便于调试
     * @return 包含容量、大小以及队列数据的描述字符串
     */
    public function toString():String {
        var dataStr:String = "[]";
        if (this._size > 0) {
            dataStr = "[" + this.toArray().join(",") + "]";
        }
        return "[RingBuffer capacity=" + this._capacity + " size=" + this._size + " data=" + dataStr + "]";
    }
    
    // --------------------------
    // 只读属性与状态判断
    // --------------------------
    
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
        var cap:Number = this._capacity;
        for (var i:Number = 0; i < this._size; i++) {
            if (this._buffer[(this._head + i) % cap] === item) {
                return true;
            }
        }
        return false;
    }
}
