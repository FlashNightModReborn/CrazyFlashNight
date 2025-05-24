/**
 * LightObjectPool
 * 
 * 一个极简化、轻量级的对象池类，适用于需要高性能对象重用的场景。
 */
class org.flashNight.sara.util.LightObjectPool {
    private var pool:Array;           // 存储可重用对象的数组
    private var topIndex:Number;      // 当前池顶索引（指向下一个可用对象的位置）
    private var createFunc:Function;  // 创建新对象的函数

    /**
     * 构造函数
     * 
     * @param createFunc 创建新对象的函数，必须返回一个实例对象
     */
    public function LightObjectPool(createFunc:Function) {
        this.createFunc = createFunc;
        this.pool = [];
        this.topIndex = 0;
    }

    /**
     * 从对象池获取一个对象
     * 如果池中有空闲对象，则取出；否则创建新对象
     * 
     * @return 对象实例
     */
    public function getObject() {
        return (this.topIndex > 0) ? this.pool[--this.topIndex] : this.createFunc();
    }


    /**
     * 将对象释放回对象池中
     * 
     * @param obj 要释放的对象
     */
    public function releaseObject(obj:Object):Void {
        if (obj == undefined) return;

        // 将对象放回池中
        this.pool[this.topIndex++] = obj;
    }

    /**
     * 清空对象池，释放所有对象
     */
    public function clearPool():Void {
        this.pool.length = 0;
        this.topIndex = 0;
    }

    /**
     * 获取当前对象池中存储的对象数量
     * 
     * @return 对象池中对象的数量
     */
    public function getPoolSize():Number {
        return this.topIndex;
    }
}
