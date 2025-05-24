class org.flashNight.naki.DataStructures.SlidingWindowBuffer {
    public var max:Number;     // 当前最大值
    public var min:Number;     // 当前最小值
    public var average:Number; // 当前平均值
    public var data:Array;     // 环形缓冲区存储数据

    public var size:Number; 
    private var sum:Number; 
    private var head:Number;
    private var count:Number;

    private var minQueue:Array; // 存储可能的最小值的索引
    private var minQueueHead:Number; // 最小值队列的头部索引
    private var minQueueTail:Number; // 最小值队列的尾部索引

    private var maxQueue:Array; // 存储可能的最大值的索引
    private var maxQueueHead:Number; // 最大值队列的头部索引
    private var maxQueueTail:Number; // 最大值队列的尾部索引

    /**
     * 构造函数
     * @param size 缓冲区大小
     */
    public function SlidingWindowBuffer(size:Number) {
        // 初始化缓冲区大小，防止非法值
        if (size <= 0 || isNaN(size)) {
            trace("[Error] Buffer size must be a positive number. Defaulting to size=1.");
            size = 1;
        }

        // 缓存缓冲区大小，取整确保是整数
        var locSize = this.size = Math.floor(size);

        // 初始化缓冲区数据并预分配数组，避免动态分配带来的性能开销
        this.data = new Array(locSize);
        for (var i:Number = 0; i < locSize; i++) {
            this.data[i] = 0;
        }

        // 初始化最小值和最大值的单调队列
        this.minQueue = new Array(locSize);
        this.maxQueue = new Array(locSize);
        for (var j:Number = 0; j < locSize; j++) {
            this.minQueue[j] = j; // 初始索引填充
            this.maxQueue[j] = j;
        }

        // 初始化队列头尾指针和其他变量
        this.minQueueHead = 0;
        this.minQueueTail = locSize;
        this.maxQueueHead = 0;
        this.maxQueueTail = locSize;
        this.count = locSize;
        this.sum = 0;
        this.min = 0;
        this.max = 0;
        this.average = 0;
        this.head = 0;
    }

    /**
     * 插入新数据
     * @param value 插入的数据
     */
    public function insert(value:Number):Void {
        // 使用局部变量访问实例变量，减少多次查找带来的性能开销
        var localSize:Number = this.size;
        var headPos:Number = this.head;
        var localData:Array = this.data;
        var localSum:Number = this.sum - localData[headPos]; // 从总和中减去被覆盖的旧值
        var localMinQueue:Array = this.minQueue;
        var localMaxQueue:Array = this.maxQueue;
        var minHead:Number = this.minQueueHead;
        var minTail:Number = this.minQueueTail;
        var maxHead:Number = this.maxQueueHead;
        var maxTail:Number = this.maxQueueTail;

        // 利用条件表达式的数值特性，将布尔值转化为 0 或 1，优化递增逻辑
        minHead = minHead + (localMinQueue[minHead] == headPos);
        maxHead = maxHead + (localMaxQueue[maxHead] == headPos);

        // 更新缓冲区数据并调整 head 位置，使用三元运算符减少条件判断
        localData[headPos] = value;
        this.head = (++headPos < localSize) ? headPos : 0;

        // 更新总和并计算平均值，避免多次求和操作
        localSum += value;
        this.sum = localSum;
        this.average = Math.round((localSum / localSize) * 100) / 100;

        // 更新 minQueue 和 maxQueue，移除无用的索引以保持单调性
        while (minTail > minHead && localData[localMinQueue[minTail - 1]] >= value) minTail--;
        while (maxTail > maxHead && localData[localMaxQueue[maxTail - 1]] <= value) maxTail--;

        // 插入新值索引到队列尾部
        localMinQueue[minTail++] = localMaxQueue[maxTail++] = (headPos > 0) ? headPos - 1 : localSize - 1;

        // 更新当前最小值和最大值
        this.min = localData[localMinQueue[this.minQueueHead = minHead]];
        this.max = localData[localMaxQueue[this.maxQueueHead = maxHead]];

        // 更新队列尾部索引
        this.minQueueTail = minTail;
        this.maxQueueTail = maxTail;
    }

    /**
     * 遍历数据并执行函数
     * @param callback 要执行的回调函数，格式为 function(value:Number):Void
     */
    public function forEach(callback:Function):Void {
        // 使用局部变量提升循环性能
        var localHead:Number = this.head;
        var localSize:Number = this.size;
        var localCount:Number = this.count;
        var localData:Array = this.data;
        var delta:Number = localSize - localHead;

        // 第一段：从 head 到缓冲区末尾，避免每次循环判断分段逻辑
        var firstSegmentLength:Number = (localCount < delta) ? localCount : delta;
        while (firstSegmentLength-- > 0) {
            callback(localData[localHead++]);
        }

        // 第二段：从缓冲区起始位置遍历剩余数据
        localHead = 0; // 回绕到数组起始位置
        var secondSegmentLength:Number = localCount - (localSize - this.head);
        while (secondSegmentLength-- > 0) {
            callback(localData[localHead++]);
        }
    }
}
