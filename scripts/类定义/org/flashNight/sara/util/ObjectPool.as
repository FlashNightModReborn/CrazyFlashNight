import org.flashNight.naki.DataStructures.Dictionary;  // 引入字典类
import org.flashNight.neur.Event.Delegate;             // 引入优化后的 Delegate 类

class org.flashNight.sara.util.ObjectPool {
    private var pool:Array;                  // 对象池数组，用于存储可重用的对象
    private var prototype:MovieClip;         // 原型对象，用于克隆新对象
    private var createFunc:Function;         // 创建新对象的函数
    private var resetFunc:Function;          // 重置对象状态的函数
    private var releaseFunc:Function;        // 释放对象时的自定义清理函数
    private var maxPoolSize:Number;          // 对象池的最大容量
    private var preloadSize:Number;          // 预加载对象的数量
    private var parentClip:MovieClip;        // 父级影片剪辑，用于确定创建对象的层次
    private var isLazyLoaded:Boolean;        // 是否启用懒加载模式
    private var isPrototypeEnabled:Boolean;  // 是否启用原型模式
    private var prototypeInitArgs:Array;     // 原型初始化所需的额外参数

    // 堆栈管理
    private var topIndex:Number;             // 当前堆栈顶索引

    /**
     * 构造函数，用于初始化对象池的各项参数
     * @param createFunc 创建新对象的函数，必须返回一个 MovieClip 实例
     * @param resetFunc  重置对象状态的函数，在获取对象时调用
     * @param releaseFunc 释放对象时调用的自定义清理函数
     * @param parentClip 父级影片剪辑，用于创建对象时的层次绑定
     * @param maxPoolSize 对象池的最大容量（可选，默认30）
     * @param preloadSize 预加载对象的数量（可选，默认5）
     * @param isLazyLoaded 是否启用懒加载模式（可选，默认 true）
     * @param isPrototypeEnabled 是否启用原型模式（可选，默认 true）
     * @param prototypeInitArgs 原型初始化所需的额外参数（可选，默认空数组）
     */
    public function ObjectPool(
        createFunc:Function,
        resetFunc:Function,
        releaseFunc:Function,
        parentClip:MovieClip,
        maxPoolSize:Number,
        preloadSize:Number,
        isLazyLoaded:Boolean,
        isPrototypeEnabled:Boolean,
        prototypeInitArgs:Array
    ) {
        this.pool = [];  // 初始化对象池数组
        this.topIndex = -1;  // 初始化堆栈顶索引
        this.createFunc = createFunc;  // 创建新对象的函数
        this.resetFunc = resetFunc;  // 重置对象的函数
        this.releaseFunc = releaseFunc;  // 释放对象的函数
        this.parentClip = parentClip;  // 父级影片剪辑
        this.maxPoolSize = (maxPoolSize != undefined) ? maxPoolSize : 30;  // 设置最大容量，默认为30
        this.preloadSize = (preloadSize != undefined) ? preloadSize : 5;  // 设置预加载数量，默认为5
        this.isLazyLoaded = (isLazyLoaded != undefined) ? isLazyLoaded : true;  // 是否启用懒加载，默认为 true
        this.isPrototypeEnabled = (isPrototypeEnabled != undefined) ? isPrototypeEnabled : true;  // 是否启用原型模式，默认为 true
        this.prototypeInitArgs = prototypeInitArgs || [];  // 原型初始化所需的额外参数，默认为空

        // 如果启用了原型模式，则初始化原型对象
        if (this.isPrototypeEnabled) {
            // 使用 createFunc 和初始化参数创建原型对象
            this.prototype = this.createFunc.apply(null, [this.parentClip].concat(this.prototypeInitArgs));
            this.prototype._visible = false;  // 原型对象不可见
        }
    }

    /**
     * 创建新对象
     * 如果启用了原型模式，将通过克隆原型对象创建新对象；否则直接调用 createFunc 创建新对象
     * @return 新创建的 MovieClip 对象
     */
    private function createNewObject():MovieClip {
        var newObj:MovieClip;

        // 如果启用了原型模式且原型对象存在，通过克隆原型创建新对象
        if (this.isPrototypeEnabled && this.prototype != undefined) {
            newObj = this.prototype.duplicateMovieClip("cloneMC" + this.parentClip.getNextHighestDepth(), this.parentClip.getNextHighestDepth());
        } else {
            // 否则直接调用 createFunc 创建新对象，传递 parentClip 和 prototypeInitArgs
            newObj = this.createFunc.apply(null, [this.parentClip].concat(this.prototypeInitArgs));
        }

        // 使用 Delegate 创建 recycle 方法，并绑定到当前对象池
        var recycleDelegate:Function = Delegate.create(this, releaseObject, newObj);
        newObj.recycle = recycleDelegate;

        // 使用 _global.ASSetPropFlags 将 _pool 和 recycle 设置为不可枚举
        newObj._pool = this;
        _global.ASSetPropFlags(newObj, ["_pool", "recycle"], 1, 0);  // 1表示不可枚举

        return newObj;
    }

    /**
     * 设置对象池的最大容量
     * @param maxPoolSize 最大容量值
     */
    public function setPoolCapacity(maxPoolSize:Number):Void {
        this.maxPoolSize = maxPoolSize;
        // 如果当前池大小超过新的最大容量，销毁多余的对象
        while (this.topIndex + 1 > this.maxPoolSize) {
            var obj:MovieClip = this.pool[this.topIndex];
            if (obj != undefined) {
                obj.__isDestroyed = true;
                obj.removeMovieClip();
                this.pool[this.topIndex] = undefined;
            }
            this.topIndex--;
        }
    }

    /**
     * 预加载对象到池中，以减少运行时的创建开销
     * 只有在禁用懒加载时才会进行预加载
     * @param preloadSize 要预加载的对象数量
     */
    public function preload(numToPreload:Number):Void {
        if (!this.isLazyLoaded) {
            for (var i:Number = 0; i < numToPreload; i++) {
                if (this.topIndex + 1 < this.maxPoolSize) {
                    var obj:MovieClip = this.createNewObject();
                    this.topIndex++;
                    this.pool[this.topIndex] = obj;
                } else {
                    break;
                }
            }
        }
    }

    /**
     * 从对象池中获取一个对象，如果池为空则根据配置创建新对象
     * @param ...args 额外的参数，可传递给 resetFunc
     * @return 一个可用的 MovieClip 对象
     */
    public function getObject():MovieClip {
        var obj:MovieClip;

        // 如果池中有对象，则取出顶部对象；否则创建新对象
        if (this.topIndex >= 0) {
            obj = MovieClip(this.pool[this.topIndex]);
            this.pool[this.topIndex] = undefined;  // 清除引用
            this.topIndex--;
        } else {
            obj = this.createNewObject();
        }

        // 重置对象状态，传递所有参数给 resetFunc
        this.resetFunc.apply(obj, arguments);

        return obj;
    }

    /**
     * 将对象释放回对象池中，或在池满时销毁对象
     * @param obj 要释放的对象
     */
    public function releaseObject(obj:MovieClip):Void {
        // 检查对象是否有效或已被销毁
        if (obj == undefined || obj.__isDestroyed) {
            return;
        }

        // 调用自定义的释放函数，传递除第一个参数外的所有参数
        if (this.releaseFunc != undefined) {
            // 使用 Delegate 创建释放函数的调用
            this.releaseFunc.apply(obj, Array.prototype.slice.call(arguments, 1));
        }

        // 清理对象的 _pool 引用，防止内存泄漏
        obj._pool = undefined;
        obj.recycle = undefined;
        _global.ASSetPropFlags(obj, ["_pool", "recycle"], 1, 0);  // 1表示不可枚举

        // 检查对象池是否已满
        if (this.topIndex + 1 < this.maxPoolSize) {
            this.topIndex++;
            this.pool[this.topIndex] = obj;  // 将对象放回池中
        } else {
            obj.__isDestroyed = true;  // 标记对象已被销毁
            obj.removeMovieClip();  // 从舞台上移除对象，释放内存
        }
    }

    /**
     * 获取池中的对象数量
     * @return 对象池中的当前对象数量
     */
    public function getPoolSize():Number {
        return this.topIndex + 1;
    }

    /**
     * 获取对象池的最大容量
     * @return 最大容量值
     */
    public function getMaxPoolSize():Number {
        return this.maxPoolSize;
    }

    /**
     * 检查是否启用了懒加载
     * @return 是否启用懒加载模式
     */
    public function isLazyLoadingEnabled():Boolean {
        return this.isLazyLoaded;
    }

    /**
     * 检查是否启用了原型模式
     * @return 是否启用原型模式
     */
    public function isPrototypeModeEnabled():Boolean {
        return this.isPrototypeEnabled;
    }

    /**
     * 清空对象池，销毁所有池中的对象并释放内存
     */
    public function clearPool():Void {
        for (var i:Number = 0; i <= this.topIndex; i++) {
            var obj:MovieClip = this.pool[i];
            if (obj != undefined) {
                obj.__isDestroyed = true;  // 标记对象已被销毁
                obj.removeMovieClip();  // 销毁对象，释放内存
                this.pool[i] = undefined;
            }
        }
        this.pool = [];
        this.topIndex = -1;
    }

    /**
     * 检查对象池是否为空
     * @return 如果对象池为空则返回 true，否则返回 false
     */
    public function isPoolEmpty():Boolean {
        return this.topIndex < 0;
    }

    /**
     * 检查对象池是否已满
     * @return 如果对象池已满则返回 true，否则返回 false
     */
    public function isPoolFull():Boolean {
        return this.topIndex + 1 >= this.maxPoolSize;
    }

    /**
     * 获取当前对象池中未被使用的对象数量
     * @return 当前对象池中的空闲对象数量
     */
    public function getIdleObjectCount():Number {
        return this.getPoolSize();
    }

    /**
     * 批量回收多个对象，将它们一次性放回对象池
     * @param objects 一个包含需要回收对象的数组
     */
    public function releaseObjects(objects:Array):Void {
        for (var i:Number = 0; i < objects.length; i++) {
            var obj:MovieClip = objects[i];
            this.releaseObject(obj);  // 使用现有的 releaseObject 方法回收对象
        }
    }
}
