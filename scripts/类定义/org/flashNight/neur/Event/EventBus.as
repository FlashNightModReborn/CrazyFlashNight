import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * EventBus 类用于事件的订阅、发布和管理。
 * 采用饿汉式单例模式，确保在类加载时实例化。
 * 通过预分配数组大小、索引操作和循环展开等优化措施，提高了性能。
 */
class org.flashNight.neur.Event.EventBus {
    private var listeners:Object;          // 存储事件监听器，结构为事件名 -> { callbacks: { callbackID: poolIndex }, funcToID: { funcID: callbackID }, count: Number }
    private var pool:Array;                // 回调函数池，用于存储回调函数的索引位置
    private var availSpace:Array;          // 可用索引列表，存储空闲的池位置
    private var availSpaceTop:Number;      // 可用索引列表的栈顶指针
    private var tempArgs:Array;            // 参数缓存区，重用避免频繁创建
    private var tempCallbacks:Array;       // 重用的回调函数存储数组
    private var tempCallbacksCount:Number; // tempCallbacks 数组中的有效元素计数

    // 静态实例，类加载时初始化，采用饿汉式单例模式
    // 脚本调用时可直接调用 instance 以避免一层函数调用开销
    public static var instance:EventBus = new EventBus();

    /**
     * 私有化构造函数，防止外部直接创建对象。
     * 初始化回调池，并为可用空间列表预分配固定大小，以减少运行时扩展的开销。
     */
    private function EventBus() {
        this.listeners = {};
        var initialCapacity:Number = 1024;

        // 预创建数组大小，避免动态扩容
        this.pool = new Array(initialCapacity);
        this.availSpace = new Array(initialCapacity);
        this.availSpaceTop = initialCapacity;
        this.tempArgs = new Array(10);          // 假设最大参数数量为 10，可根据需要调整
        this.tempCallbacks = new Array(initialCapacity);
        this.tempCallbacksCount = 0;

        // 使用循环展开初始化 pool 和 availSpace 数组
        var unrollFactor:Number = 8;
        var i:Number = 0;
        for (; i + unrollFactor <= initialCapacity; i += unrollFactor) {
            this.pool[i] = null;
            this.pool[i + 1] = null;
            this.pool[i + 2] = null;
            this.pool[i + 3] = null;
            this.pool[i + 4] = null;
            this.pool[i + 5] = null;
            this.pool[i + 6] = null;
            this.pool[i + 7] = null;

            this.availSpace[i] = i;
            this.availSpace[i + 1] = i + 1;
            this.availSpace[i + 2] = i + 2;
            this.availSpace[i + 3] = i + 3;
            this.availSpace[i + 4] = i + 4;
            this.availSpace[i + 5] = i + 5;
            this.availSpace[i + 6] = i + 6;
            this.availSpace[i + 7] = i + 7;
        }
        // 处理剩余的元素
        for (; i < initialCapacity; i++) {
            this.pool[i] = null;
            this.availSpace[i] = i;
        }
    }

    /**
     * 初始化方法，用于初始化静态实例。
     * 
     * @return EventBus 单例实例
     */
    public static function initialize():EventBus {
        Delegate.init();  // 初始化 Delegate 缓存
        return instance;
    }

    /**
     * 获取 EventBus 单例实例的静态方法。
     * 
     * @return EventBus 单例实例
     */
    public static function getInstance():EventBus {
        return instance;
    }

    /**
     * 订阅事件，将回调函数与特定事件绑定。
     * 
     * @param eventName 事件名称
     * @param callback 要订阅的回调函数
     * @param scope 回调函数执行时的作用域
     */
    public function subscribe(eventName:String, callback:Function, scope:Object):Void {
        if (!this.listeners[eventName]) {
            this.listeners[eventName] = { callbacks: {}, funcToID: {}, count: 0 };
        }

        var listenersForEvent:Object = this.listeners[eventName];
        var funcToID:Object = listenersForEvent.funcToID;

        var funcID:String = String(Dictionary.getStaticUID(callback));

        if (funcToID[funcID] != undefined) {
            return;
        }

        var callbackID:Number = Dictionary.getStaticUID(callback);
        var wrappedCallback:Function = Delegate.create(scope, callback);

        var allocIndex:Number;
        if (this.availSpaceTop > 0) {
            allocIndex = this.availSpace[--this.availSpaceTop];
            this.pool[allocIndex] = wrappedCallback;
        } else {
            // 扩展容量
            this.expandPool();
            allocIndex = this.availSpace[--this.availSpaceTop];
            this.pool[allocIndex] = wrappedCallback;
        }

        listenersForEvent.callbacks[callbackID] = allocIndex;
        funcToID[funcID] = callbackID;
        listenersForEvent.count++;
    }

    /**
     * 取消订阅事件，移除指定的回调函数。
     * 
     * @param eventName 事件名称
     * @param callback 要取消的回调函数
     */
    public function unsubscribe(eventName:String, callback:Function):Void {
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) return;

        var funcToID:Object = listenersForEvent.funcToID;
        var funcID:String = String(Dictionary.getStaticUID(callback));
        var callbackID:Number = funcToID[funcID];

        if (callbackID == undefined) return;

        var allocIndex:Number = listenersForEvent.callbacks[callbackID];
        if (allocIndex != undefined) {
            this.pool[allocIndex] = null;
            this.availSpace[this.availSpaceTop++] = allocIndex;
            delete listenersForEvent.callbacks[callbackID];
            delete funcToID[funcID];
        }

        listenersForEvent.count--;

        if (listenersForEvent.count === 0) {
            delete this.listeners[eventName];
        }
    }

    /**
     * 发布事件，通知所有订阅者，并传递可选的参数。
     * 
     * @param eventName 事件名称
     */
    public function publish(eventName:String):Void {
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) return;

        var callbacks:Object = listenersForEvent.callbacks;
        var poolRef:Array = this.pool;

        // 重置 tempCallbacksCount
        this.tempCallbacksCount = 0;

        // 收集回调函数，使用索引方式
        for (var cbID:String in callbacks) {
            var index:Number = callbacks[cbID];
            var callback:Function = poolRef[index];
            if (callback != null) {
                this.tempCallbacks[this.tempCallbacksCount++] = callback;
            }
        }

        var hasArguments:Boolean = arguments.length >= 2;
        var argsLength:Number = arguments.length - 1;

        // 如果有参数，使用索引方式复制参数到 tempArgs
        if (hasArguments) {
            for (var i:Number = 0; i < argsLength; i++) {
                this.tempArgs[i] = arguments[i + 1];
            }
        }

        // 倒序执行回调函数
        for (var j:Number = this.tempCallbacksCount - 1; j >= 0; j--) {
            var cb:Function = this.tempCallbacks[j];
            try {
                if (hasArguments) {
                    switch (argsLength) {
                        case 0: cb(); break;
                        case 1: cb(this.tempArgs[0]); break;
                        case 2: cb(this.tempArgs[0], this.tempArgs[1]); break;
                        case 3: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2]); break;
                        case 4: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3]); break;
                        case 5: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3], this.tempArgs[4]); break;
                        case 6: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3], this.tempArgs[4], this.tempArgs[5]); break;
                        case 7: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3], this.tempArgs[4], this.tempArgs[5], this.tempArgs[6]); break;
                        case 8: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3], this.tempArgs[4], this.tempArgs[5], this.tempArgs[6], this.tempArgs[7]); break;
                        case 9: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3], this.tempArgs[4], this.tempArgs[5], this.tempArgs[6], this.tempArgs[7], this.tempArgs[8]); break;
                        default: cb.apply(null, this.tempArgs.slice(0, argsLength));
                    }
                } else {
                    cb();
                }
            } catch (error:Error) {
                trace("Error executing callback for event '" + eventName + "': " + error.message);
            }
        }
    }

    /**
     * 一次性订阅事件，回调执行一次后即自动取消订阅。
     * 
     * @param eventName 事件名称
     * @param callback 要订阅的回调函数
     * @param scope 回调函数的作用域
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object):Void {
        var self:EventBus = this;
        var originalCallback:Function = callback;

        var funcID:String = String(Dictionary.getStaticUID(originalCallback));

        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            listenersForEvent = { callbacks: {}, funcToID: {}, count: 0 };
            this.listeners[eventName] = listenersForEvent;
        }

        var funcToID:Object = listenersForEvent.funcToID;

        if (funcToID[funcID] != undefined) {
            return;
        }

        var callbackID:Number = Dictionary.getStaticUID(originalCallback);

        var wrappedOnceCallback:Function = function() {
            originalCallback.apply(scope, arguments);
            self.unsubscribe(eventName, originalCallback);
        };

        var wrappedCallback:Function = Delegate.create(scope, wrappedOnceCallback);

        var allocIndex:Number;
        if (this.availSpaceTop > 0) {
            allocIndex = this.availSpace[--this.availSpaceTop];
            this.pool[allocIndex] = wrappedCallback;
        } else {
            // 扩展容量
            this.expandPool();
            allocIndex = this.availSpace[--this.availSpaceTop];
            this.pool[allocIndex] = wrappedCallback;
        }

        listenersForEvent.callbacks[callbackID] = allocIndex;
        funcToID[funcID] = callbackID;
        listenersForEvent.count++;
    }

    /**
     * 销毁事件总线，释放所有监听器和回调函数。
     */
    public function destroy():Void {
        for (var eventName:String in this.listeners) {
            var listenersForEvent:Object = this.listeners[eventName];
            for (var cbID:String in listenersForEvent.callbacks) {
                var index:Number = listenersForEvent.callbacks[cbID];
                if (index != undefined) {
                    this.pool[index] = null;
                    this.availSpace[this.availSpaceTop++] = index;
                }
            }
            delete this.listeners[eventName];
        }

        // 清空回调池中的所有剩余回调
        var poolLength:Number = this.pool.length;
        for (var i:Number = 0; i < poolLength; i++) {
            if (this.pool[i] != null) {
                this.pool[i] = null;
                this.availSpace[this.availSpaceTop++] = i;
            }
        }

        this.listeners = {};
        Delegate.clearCache();
        this.tempArgs = [];
        this.tempCallbacks = [];
        this.tempCallbacksCount = 0;
    }

    /**
     * 扩展回调池和可用空间数组的容量。
     * 采用倍增策略，减少频繁扩容的开销。
     */
    private function expandPool():Void {
        var oldCapacity:Number = this.pool.length;
        var newCapacity:Number = oldCapacity * 2;

        // 预创建新的数组并复制旧数据
        var newPool:Array = new Array(newCapacity);
        var newAvailSpace:Array = new Array(newCapacity);

        // 使用循环展开复制数组元素
        var unrollFactor:Number = 8;
        var i:Number = 0;
        for (; i + unrollFactor <= oldCapacity; i += unrollFactor) {
            newPool[i] = this.pool[i];
            newPool[i + 1] = this.pool[i + 1];
            newPool[i + 2] = this.pool[i + 2];
            newPool[i + 3] = this.pool[i + 3];
            newPool[i + 4] = this.pool[i + 4];
            newPool[i + 5] = this.pool[i + 5];
            newPool[i + 6] = this.pool[i + 6];
            newPool[i + 7] = this.pool[i + 7];
        }
        for (; i < oldCapacity; i++) {
            newPool[i] = this.pool[i];
        }

        // 初始化新扩展的部分
        for (i = oldCapacity; i < newCapacity; i++) {
            newPool[i] = null;
            newAvailSpace[this.availSpaceTop++] = i;
        }

        // 复制旧的可用空间索引
        for (i = 0; i < this.availSpaceTop; i++) {
            newAvailSpace[i] = this.availSpace[i];
        }

        this.pool = newPool;
        this.availSpace = newAvailSpace;
    }
}
