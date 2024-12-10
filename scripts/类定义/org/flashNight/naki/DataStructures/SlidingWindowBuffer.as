class org.flashNight.naki.DataStructures.SlidingWindowBuffer {
    public var max:Number; // 当前最大值
    public var min:Number; // 当前最小值
    public var average:Number; // 当前平均值
    public var data:Array; // 环形缓冲区存储数据

    private var size:Number; // 缓冲区最大大小
    private var sum:Number; // 数据总和
    private var head:Number; // 环形缓冲区的头指针
    private var count:Number; // 当前数据量

    /**
     * 构造函数
     * @param size 缓冲区大小
     */
    public function SlidingWindowBuffer(size:Number) {
        this.size = size;
        this.data = new Array(size);
        this.max = -Infinity;
        this.min = Infinity;
        this.average = 0;
        this.sum = 0;
        this.head = 0;
        this.count = 0;
    }

    /**
     * 插入新数据
     * @param value 插入的数据
     */
    public function insert(value:Number):Void {
        // 如果缓冲区满了，需要移除最旧的数据
        if (this.count == this.size) {
            var oldValue:Number = this.data[this.head];
            this.sum -= oldValue;

            // 如果被移除的值是当前的 max 或 min，重新计算
            if (oldValue == this.max || oldValue == this.min) {
                this.recalculateMinMax();
            }
        } else {
            this.count++;
        }

        // 更新缓冲区
        this.data[this.head] = value;
        this.head = (this.head + 1) % this.size;

        // 更新统计数据
        this.sum += value;
        this.average = this.sum / this.count;

        if (value > this.max) this.max = value;
        if (value < this.min) this.min = value;
    }

    /**
     * 重新计算 max 和 min
     */
    private function recalculateMinMax():Void {
        this.max = -Infinity;
        this.min = Infinity;
        for (var i:Number = 0; i < this.count; i++) {
            var index:Number = (this.head + i) % this.size;
            var currentValue:Number = this.data[index];
            if (currentValue > this.max) this.max = currentValue;
            if (currentValue < this.min) this.min = currentValue;
        }
    }

    /**
     * 遍历数据并执行函数
     * @param callback 要执行的回调函数，格式为 function(value:Number):Void
     */
    public function forEach(callback:Function):Void {
        for (var i:Number = 0; i < this.count; i++) {
            var index:Number = (this.head + i) % this.size;
            callback(this.data[index]);
        }
    }
}
