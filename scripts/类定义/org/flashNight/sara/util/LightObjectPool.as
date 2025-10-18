/**
 * LightObjectPool - 轻量级对象池（环形缓冲区实现）
 *
 * 设计目标：
 * - 零额外开销：借出/归还操作不进行任何取模运算、边界检查或数组扩容
 * - 固定容量：容量为 2 的幂，使用按位与(&)实现高效的环形索引回绕
 * - FIFO 策略：先进先出，保证对象复用的平均磨损
 * - 内存可控：池满时丢弃归还对象，不扩容，避免内存无限增长
 *
 * 适用场景：
 * - 高频创建/销毁的临时对象（如向量、矩阵、粒子等）
 * - 对性能敏感的热路径代码
 * - 需要减少 GC 压力的场景
 *
 * 核心原理：
 * - head 指向下次读取位置，tail 指向下次写入位置
 * - head == tail 表示池空
 * - (tail + 1) & mask == head 表示池满
 * - 所有索引操作使用 (index + 1) & mask 代替 (index + 1) % capacity
 *
 */
class org.flashNight.sara.util.LightObjectPool {
    // ---- 私有成员变量 ----

    /** 环形缓冲区数组，固定容量，存储复用对象 */
    private var pool:Array;

    /** 容量掩码 (capacity - 1)，用于快速取模运算，要求 capacity 必须为 2 的幂 */
    private var mask:Number;

    /** 读取指针，指向下一个待借出对象的索引位置 */
    private var head:Number;

    /** 写入指针，指向下一个归还对象应存放的索引位置 */
    private var tail:Number;

    /** 对象创建函数，当池为空时调用此函数创建新对象 */
    private var createFunc:Function;

    /**
     * 构造函数 - 初始化对象池
     *
     * 功能说明：
     * - 接收一个对象创建函数和期望容量
     * - 自动将容量向上调整为最接近的 2 的幂（例：50 → 64，100 → 128）
     * - 预分配数组空间，避免运行时动态扩容
     *
     * 性能特性：
     * - 构造时一次性计算容量，运行时无额外开销
     * - 使用位移运算计算 2 的幂，比 Math.pow() 更快
     *
     * @param createFunc 对象创建函数，应返回一个可复用的对象实例
     *                   示例：function() { return new Point(); }
     * @param capacity   期望的池容量（可选），默认 64
     *                   - 传入非 2 的幂时会自动向上取整（如 50 → 64）
     *                   - 传入 ≤ 0 或不传时使用默认值 64
     *
     * @example
     * // 创建一个容量为 128 的 Point 对象池
     * var pointPool = new LightObjectPool(function() { return new Point(); }, 100);
     */
    public function LightObjectPool(createFunc:Function, capacity:Number) {
        this.createFunc = createFunc;

        // ---- 一次性初始化开销（不在热路径，仅构造时执行） ----

        // 容量默认值处理
        var cap:Number = (capacity > 0) ? capacity : 64;

        // 向上取最接近的 2 的幂（例：50 → 64，100 → 128）
        // 使用位移运算，效率高于 Math.pow()
        var p:Number = 1;
        while (p < cap) {
            p = (p << 1);  // 等价于 p *= 2
        }
        cap = p;

        // 预分配数组长度，避免运行时 push 触发的动态扩容
        this.pool = new Array(cap);

        // 计算掩码：capacity - 1（二进制全 1），用于快速取模
        // 例：cap=64 (0b1000000) → mask=63 (0b0111111)
        this.mask = cap - 1;

        // 初始化读写指针，均指向索引 0
        this.head = 0;
        this.tail = 0;
        // ---------------------------------------------------------
    }

    /**
     * 借出对象 - 从池中获取一个可用对象
     *
     * 执行逻辑：
     * 1. 检查池是否为空（head == tail）
     * 2. 如果池非空：
     *    - 从 head 位置取出对象
     *    - 清空该槽位引用（防止内存泄漏）
     *    - head 指针向前移动（回绕处理）
     * 3. 如果池为空：
     *    - 调用 createFunc 创建新对象
     *
     * 性能优化：
     * - 使用局部变量缓存 this.head、this.tail、this.pool，减少属性查找
     * - 使用按位与 (& mask) 代替取模运算 (% capacity)
     * - 先判断后取值，避免无效的数组访问
     *
     * 内存管理：
     * - 借出后立即将槽位设为 null，帮助 GC 及时回收无用对象
     * - 避免池在"曾经满过"的情况下保留过多引用
     *
     * @return Object 一个可用的对象实例（可能来自池，也可能是新创建的）
     *
     * @example
     * var point = pointPool.getObject();
     * point.x = 10;
     * point.y = 20;
     */
    public function getObject() {
        // 缓存属性到局部变量，减少属性查找开销（性能关键）
        var h:Number = this.head;
        var t:Number = this.tail;

        // 池非空判断：head != tail 表示有可用对象
        if (h != t) {
            var pool:Array = this.pool;       // 缓存数组引用
            var obj:Object = pool[h];         // 取出头部对象
            pool[h] = null;                   // 断开引用，避免高水位残留，帮助 GC
            this.head = (h + 1) & this.mask;  // 移动头指针，使用按位与实现环形回绕
            return obj;
        }

        // 池为空：调用创建函数生成新对象
        return this.createFunc();
    }

    /**
     * 归还对象 - 将用完的对象放回池中以便复用
     *
     * 执行逻辑：
     * 1. 检查参数合法性（拒绝 null）
     * 2. 计算下一个写入位置
     * 3. 如果池未满：
     *    - 将对象放入 tail 位置
     *    - tail 指针向前移动
     * 4. 如果池已满：
     *    - 丢弃对象，让 GC 回收
     *    - 不扩容、不搬移数据
     *
     * 设计哲学：
     * - 固定容量：满了就丢弃，保持"零额外开销"原则
     * - 防止内存无限增长：避免因大量归还导致池膨胀
     * - 适用于高频场景：少量丢弃换取稳定性能
     *
     * 性能优化：
     * - 提前计算 nextT，只判断一次边界条件
     * - 使用局部变量缓存 tail 和 mask
     *
     * @param obj 要归还的对象，不能为 null
     *            - 传入 null 会被忽略（提前返回）
     *            - 调用者应确保对象状态已重置（如需要）
     *
     * @example
     * point.x = 0;
     * point.y = 0;
     * pointPool.releaseObject(point);
     * point = null; // 解除外部引用
     */
    public function releaseObject(obj:Object):Void {
        // 参数检查：拒绝 null 或 undefined
        if (obj == null) return;

        // 缓存尾指针到局部变量
        var t:Number = this.tail;

        // 计算下一个写入位置（使用按位与实现环形回绕）
        var nextT:Number = (t + 1) & this.mask;

        // 检查池是否已满：nextT == head 表示满
        if (nextT != this.head) {
            // 池未满：存入对象，移动尾指针
            this.pool[t] = obj;
            this.tail = nextT;
        } else {
            // 池满：丢弃归还对象（不扩容、不搬移，保持零额外开销）
            // 对象会被 GC 回收，这是有意的设计选择：
            // 牺牲少量丢弃对象，换取固定内存占用和稳定性能
        }
    }

    /**
     * 清空对象池 - 移除所有池内对象，重置为初始状态
     *
     * 功能说明：
     * - 清空池内所有对象引用，帮助 GC 回收
     * - 重置读写指针到初始位置
     * - 保持容量不变（不重新分配）
     *
     * 实现细节：
     * - 通过重建数组实现快速清空，比逐个槽位赋 null 更高效
     * - 新数组自动填充 undefined，长度与原数组相同
     *
     * 适用场景：
     * - 关卡切换时清理资源
     * - 重置池状态以适应新的使用模式
     * - 强制释放池内所有对象引用
     *
     * @example
     * // 关卡结束，清空所有池对象
     * pointPool.clearPool();
     */
    public function clearPool():Void {
        // 通过 mask 反推容量（mask = capacity - 1）
        var cap:Number = this.mask + 1;

        // 重建数组：避免逐槽清空的循环开销，让旧数组被 GC 回收
        this.pool = new Array(cap);

        // 重置读写指针到起始位置
        this.head = 0;
        this.tail = 0;
    }

    /**
     * 获取池内对象数量 - 返回当前可借出的对象个数
     *
     * 计算原理：
     * - (tail - head) 表示两指针之间的距离
     * - 使用 & mask 处理环形回绕的情况
     * - 例如：head=60, tail=10, cap=64 时：
     *   (10 - 60) & 63 = (-50) & 63 = 14（实际有 14 个对象）
     *
     * 性能特性：
     * - O(1) 时间复杂度，纯位运算
     * - 无分支判断，CPU 流水线友好
     *
     * 注意事项：
     * - 返回值范围：[0, capacity-1]
     * - head == tail 时返回 0（池空）
     * - 不会返回 capacity（最多只能存 capacity-1 个对象，因为满判定需要预留一个槽位）
     *
     * @return Number 池内当前可用对象数量
     *
     * @example
     * var count = pointPool.getPoolSize();
     * trace("Pool has " + count + " objects available");
     */
    public function getPoolSize():Number {
        // (tail - head) 在无符号意义下的差值，通过 mask 实现环形计算
        // 位运算确保结果在 [0, capacity-1] 范围内
        return (this.tail - this.head) & this.mask;
    }
}
