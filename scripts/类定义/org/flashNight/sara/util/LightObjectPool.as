/**
 * LightObjectPool
 * 
 * 一个极简化、轻量级的对象池类，适用于需要高性能对象重用的场景。
 * 通过构造函数指定对象的创建函数，提供获取和释放对象的基本功能。
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
    public function getObject():Object {
        var obj:Object;

        // 如果池中有对象可用
        if (this.topIndex > 0) {
            this.topIndex--;
            obj = this.pool[this.topIndex];
            this.pool[this.topIndex] = undefined;
        } else {
            // 池为空，创建新对象
            obj = this.createFunc();
        }

        return obj;
    }

    /**
     * 将对象释放回对象池中
     * 
     * @param obj 要释放的对象
     */
    public function releaseObject(obj:Object):Void {
        if (obj == undefined) return;

        // 将对象放回池中
        this.pool[this.topIndex] = obj;
        this.topIndex++;
    }

    /**
     * 清空对象池，释放所有对象
     */
    public function clearPool():Void {
        for (var i:Number = 0; i < this.topIndex; i++) {
            this.pool[i] = undefined;
        }
        this.pool = [];
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
