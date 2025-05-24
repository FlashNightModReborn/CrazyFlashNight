import org.flashNight.neur.Event.Allocable.*;

/**
 * Allocator 类实现了一个对象池管理器，用于高效地分配和回收对象。它维护了一个对象池（pool）和一个可用索引列表（availSpace），
 * 通过重用已经分配的对象来减少内存分配的开销。
 */
class org.flashNight.neur.Event.Allocator {
    private var pool: Array;      // 对象池，用于存储分配的对象
    private var availSpace: Array; // 可用索引列表，用于跟踪对象池中未被占用的索引

    /**
     * 构造函数
     * 
     * @param _pool 初始对象池
     * @param initialCapacity 初始化对象池的容量
     */
    public function Allocator(_pool: Array, initialCapacity:Number) {
        this.pool = _pool;       // 初始化对象池
        this.availSpace = [];    // 初始化可用索引列表
        for (var i:Number = 0; i < initialCapacity; i++) {
            this.pool.push(null);    // 将初始容量的所有位置设为 null
            this.availSpace.push(i); // 将每个位置的索引添加到可用索引列表
        }
    }

    /**
     * 分配对象
     * 
     * @return 返回分配的对象在池中的索引
     */
    public function Alloc(): Number {
        var ref:Object = arguments[0]; // 接收一个对象，该对象可以是任意类型
        var initArgs:Array = [];       // 初始化参数数组

        // 获取所有传递给分配函数的初始化参数
        for (var i:Number = 1; i < arguments.length; i++) {
            initArgs.push(arguments[i]);
        }

        var index:Number;
        if (this.availSpace.length > 0) {
            // 从可用索引列表中取出一个可用的索引，分配给对象
            index = Number(this.availSpace.shift()); 
            this.pool[index] = ref;    // 在池中存储该对象
        } else {
            // 如果没有可用索引，将对象添加到池的末尾
            this.pool.push(ref);
            index = this.pool.length - 1;
        }

        // 如果对象实现了 initialize 方法，则调用该方法进行初始化
        if (typeof ref.initialize == "function") {
            ref.initialize.apply(ref, initArgs);
        }

        // 输出分配的索引
        //trace("Allocated index: " + index);
        return index; // 返回分配对象的索引
    }

    /**
     * 释放对象
     * 
     * @param index 要释放的对象在池中的索引
     */
    public function Free(index: Number): Void {
        // 检查该索引是否已经被释放或未分配
        if (this.pool[index] == null) {
            trace("Warning: Attempted to free an unallocated or already freed index: " + index);
            return;
        }

        var obj:Object = this.pool[index];
        // 如果对象实现了 reset 方法，则调用该方法重置对象状态
        if (typeof obj.reset == "function") {
            obj.reset();
        }

        // 将该索引在对象池中设为 null，并将其添加到可用索引列表中
        this.pool[index] = null;
        this.availSpace.push(index); // 使用 push 将释放的索引添加到可用索引的末尾
    }

    /**
     * 释放所有对象
     * 
     * 该方法遍历对象池中的所有对象，重置它们的状态并将其释放。所有释放的索引会被加入可用索引列表中。
     */
    public function FreeAll(): Void {
        for (var i:Number = 0; i < this.pool.length; i++) {
            if (this.pool[i] != null && this.pool[i] != undefined) {
                var obj:Object = this.pool[i];
                // 如果对象有 reset 方法，调用它重置对象
                if (typeof obj.reset == "function") {
                    obj.reset();
                }
                this.pool[i] = null; // 将池中的对象设为 null
            }
        }
        this.availSpace = [];  // 清空可用索引列表
        for (var i:Number = 0; i < this.pool.length; i++) {
            this.availSpace.push(i);  // 将所有的索引重新加入到可用索引列表
        }
    }

    /**
     * 获取指定索引的回调函数
     * 
     * @param index 对象在池中的索引
     * @return 返回该索引对应的回调函数
     */
    public function getCallback(index:Number): Function {
        return this.pool[index];
    }

    /**
     * 获取对象池的大小
     * 
     * @return 返回对象池当前的大小
     */
    public function getPoolSize(): Number {
        return this.pool.length;
    }

    /**
     * 获取当前可用索引的数量
     * 
     * @return 返回可用索引的数量
     */
    public function getAvailSpaceCount(): Number {
        return this.availSpace.length;
    }

    /**
     * 检查索引是否可用
     * 
     * @param index 要检查的索引
     * @return 如果索引在可用索引列表中，返回 true，否则返回 false
     */
    public function isIndexAvailable(index:Number):Boolean {
        return this.availSpace.indexOf(index) >= 0;
    }
}
