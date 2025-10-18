/**
 * LightObjectPool (Ring/FIFO)
 * 环形对象池：固定容量的 FIFO 复用，空则 create，满则丢弃归还。
 * 关键点：cap 为 2 的幂，mask = cap-1，用按位与实现回绕，无取模。
 */
class org.flashNight.sara.util.LightObjectPool {
    private var pool:Array;          // 固定容量环形缓冲区
    private var mask:Number;         // cap - 1（cap 必须为 2 的幂）
    private var head:Number;         // 下一个读出索引
    private var tail:Number;         // 下一个写入索引
    private var createFunc:Function; // 创建新对象

    /**
     * @param createFunc 创建函数：返回一个实例
     * @param capacity   期望容量（可选）。若非 2 的幂，将向上取最近的 2 次幂。默认 64。
     */
    public function LightObjectPool(createFunc:Function, capacity:Number) {
        this.createFunc = createFunc;

        // ---- 一次性初始化开销，不在热路径 ----
        var cap:Number = (capacity > 0) ? capacity : 64;
        // 向上取 2 的幂（仅构造时执行，不影响运行时“零额外”）
        var p:Number = 1;
        while (p < cap) { p = (p << 1); }
        cap = p;

        this.pool = new Array(cap); // 预设长度，避免 push 触发的扩容
        this.mask = cap - 1;
        this.head = 0;
        this.tail = 0;
        // -------------------------------------
    }

    /**
     * 借出对象：池非空 => 取 head；池空 => createFunc()
     */
    public function getObject() {
        var h:Number = this.head;
        var t:Number = this.tail;
        if (h != t) {
            var obj = this.pool[h];
            this.pool[h] = undefined;        // 断开引用，避免高水位残留
            this.head = (h + 1) & this.mask; // 回绕
            return obj;
        }
        return this.createFunc(); // 池空：创建
    }

    /**
     * 归还对象：池未满 => 写 tail；池满 => 丢弃（让 GC 回收）
     */
    public function releaseObject(obj:Object):Void {
        if (obj == undefined) return;

        var t:Number = this.tail;
        var nextT:Number = (t + 1) & this.mask;
        if (nextT != this.head) {
            this.pool[t] = obj;
            this.tail = nextT;
        } else {
            // 池满：丢弃归还对象（不扩容、不搬移，保持“零额外”）
        }
    }

    /**
     * 清空对象池（保持容量不变）
     */
    public function clearPool():Void {
        var cap:Number = this.mask + 1;
        this.pool = new Array(cap); // 重建数组，避免逐槽清空开销
        this.head = 0;
        this.tail = 0;
    }

    /**
     * 当前池内可借出的数量（O(1) 按位运算）
     */
    public function getPoolSize():Number {
        // (tail - head) 在无符号意义下的差值
        return (this.tail - this.head) & this.mask;
    }
}
