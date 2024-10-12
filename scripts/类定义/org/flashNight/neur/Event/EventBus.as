import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * EventBus 类用于事件的订阅、发布和管理。
 * 采用饿汉式单例模式，确保在类加载时实例化。
 * 该类支持高效的事件管理，通过回调池和监听器字典进行优化，避免重复订阅和频繁内存分配。
 */
class org.flashNight.neur.Event.EventBus {
    private var listeners:Object;          // 存储事件监听器，结构为事件名 -> { callbacks: { callbackID: poolIndex }, funcToID: { funcID: callbackID }, count: Number }
    private var pool:Array;                // 回调函数池，用于存储回调函数的索引位置
    private var availSpace:Array;          // 可用索引列表，存储空闲的池位置
    private var tempArgs:Array = [];       // 参数缓存区，重用避免频繁创建
    private var tempCallbacks:Array = [];  // 重用的回调函数存储数组

    // 静态实例，类加载时初始化，采用饿汉式单例模式
    private static var instance:EventBus = new EventBus();

    /**
     * 私有化构造函数，防止外部直接创建对象。
     * 初始化回调池，并为可用空间列表预分配 1024 个空闲位置，以减少运行时扩展的开销。
     */
    private function EventBus() {
        this.listeners = {};           // 初始化监听器字典，用于存储各事件及其关联的回调函数
        this.pool = [];                // 初始化回调函数池
        this.availSpace = [];          // 初始化可用索引列表，用于记录回调函数池中空闲的位置

        // 预分配 1024 个空闲池位，减少运行时扩展的开销
        for (var i:Number = 0; i < 1024; i++) {
            this.pool.push(null);
            this.availSpace.push(i);
        }
    }

    /**
     * 初始化方法，用于初始化静态实例。
     * 此方法显式调用一次，后续直接返回唯一的实例，不再重复初始化。
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
     * 每个回调函数会生成一个唯一的 ID，并与事件名进行关联，避免重复订阅。
     * 
     * @param eventName 事件名称
     * @param callback 要订阅的回调函数
     * @param scope 回调函数执行时的作用域
     */
    public function subscribe(eventName:String, callback:Function, scope:Object):Void {
        // 如果事件监听器不存在，初始化监听器结构
        if (!this.listeners[eventName]) {
            this.listeners[eventName] = { callbacks: {}, funcToID: {}, count: 0 };  // 初始化监听器对象，包含回调字典、函数 ID 映射和计数器
        }

        var listenersForEvent:Object = this.listeners[eventName];
        var funcToID:Object = listenersForEvent.funcToID;

        // 使用 Dictionary 静态方法为回调函数生成唯一的 ID
        var funcID:String = String(Dictionary.getStaticUID(callback));

        // 如果该回调函数已存在，避免重复订阅
        if (funcToID[funcID] != undefined) {
            return;
        }

        // 使用 Dictionary 生成回调函数的唯一 ID
        var callbackID:Number = Dictionary.getStaticUID(callback);

        // 创建与作用域绑定的包装回调函数
        var wrappedCallback:Function = Delegate.create(scope, callback);

        // 从可用索引列表中分配一个空闲的位置给新的回调函数
        var allocIndex:Number;
        if (this.availSpace.length > 0) {
            allocIndex = Number(this.availSpace.pop());
            this.pool[allocIndex] = wrappedCallback;
        } else {
            // 如果池已满，采用双倍扩展策略扩展池的容量
            var newCapacity:Number = this.pool.length * 2;
            for (var j:Number = this.pool.length; j < newCapacity; j++) {
                this.pool.push(null);
                this.availSpace.push(j);
            }
            allocIndex = Number(this.availSpace.pop());
            this.pool[allocIndex] = wrappedCallback;
        }

        // 将回调 ID 和分配的索引位置存储起来
        listenersForEvent.callbacks[callbackID] = allocIndex;
        funcToID[funcID] = callbackID;

        listenersForEvent.count++;  // 增加该事件的回调计数
    }

    /**
     * 取消订阅事件，移除指定的回调函数。
     * 通过回调函数的唯一 ID 定位并移除回调。
     * 
     * @param eventName 事件名称
     * @param callback 要取消的回调函数
     */
    public function unsubscribe(eventName:String, callback:Function):Void {
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) return;

        var funcToID:Object = listenersForEvent.funcToID;

        // 获取回调函数的唯一 ID
        var funcID:String = String(Dictionary.getStaticUID(callback));

        var callbackID:Number = funcToID[funcID];
        if (callbackID == undefined) return;

        // 根据回调 ID 获取索引位置并释放该回调
        var allocIndex:Number = listenersForEvent.callbacks[callbackID];
        if (allocIndex != undefined) {
            this.pool[allocIndex] = null;
            this.availSpace.push(allocIndex);
            delete listenersForEvent.callbacks[callbackID];
            delete funcToID[funcID];
        }

        listenersForEvent.count--;  // 减少该事件的回调计数

        // 如果没有剩余的回调函数，则删除该事件的监听器对象
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

        this.tempCallbacks.length = 0;  // 清空并重用临时回调数组

        // 将所有回调函数存入 tempCallbacks 数组
        for (var cbID:String in callbacks) {
            var index:Number = callbacks[cbID];
            var callback:Function = poolRef[index];
            if (callback != null) {
                this.tempCallbacks.push(callback);
            }
        }

        var callbackCount:Number = this.tempCallbacks.length;
        var hasArguments:Boolean = arguments.length >= 2;

        // 如果存在额外参数，则将参数存入 tempArgs 缓存区
        if (hasArguments) {
            this.tempArgs.length = 0;
            var argsLen:Number = arguments.length;
            for (var i:Number = 1; i < argsLen; i++) {
                this.tempArgs.push(arguments[i]);
            }
        }

        // 倒序遍历并执行回调函数，确保回调函数正确响应事件
        for (var j:Number = callbackCount - 1; j >= 0; j--) {
            var cb:Function = this.tempCallbacks[j];
            try {
                if (hasArguments) {
                    // 手动展开常见参数情况，避免使用 apply 带来的性能损耗
                    switch (this.tempArgs.length) {
                        case 0: cb(); break;
                        case 1: cb(this.tempArgs[0]); break;
                        case 2: cb(this.tempArgs[0], this.tempArgs[1]); break;
                        case 3: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2]); break;
                        case 4: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3]); break;
                        case 5: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3], this.tempArgs[4]); break;
                        case 6: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3], this.tempArgs[4], this.tempArgs[5]); break;
                        case 7: cb(this.tempArgs[0], this.tempArgs[1], this.tempArgs[2], this.tempArgs[3], this.tempArgs[4], this.tempArgs[5], this.tempArgs[6]); break;
                        default: cb.apply(null, this.tempArgs);  // 参数超过 7 个时，使用 apply
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

        // 为回调函数生成唯一 ID
        var funcID:String = String(Dictionary.getStaticUID(originalCallback));

        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            listenersForEvent = { callbacks: {}, funcToID: {}, count: 0 };  // 初始化事件的监听器对象
            this.listeners[eventName] = listenersForEvent;
        }

        var funcToID:Object = listenersForEvent.funcToID;

        // 避免重复订阅
        if (funcToID[funcID] != undefined) {
            return;
        }

        var callbackID:Number = Dictionary.getStaticUID(originalCallback);

        // 创建一次性回调的包装函数，执行后自动取消订阅
        var wrappedOnceCallback:Function = function() {
            originalCallback.apply(scope, arguments);
            self.unsubscribe(eventName, originalCallback);  // 回调执行后自动取消订阅
        };

        // 使用 Delegate.create 创建包装后的回调函数
        var wrappedCallback:Function = Delegate.create(scope, wrappedOnceCallback);

        var allocIndex:Number;
        if (this.availSpace.length > 0) {
            allocIndex = Number(this.availSpace.pop());
            this.pool[allocIndex] = wrappedCallback;
        } else {
            // 如果池已满，扩展容量并分配新的索引位置
            var newCapacity:Number = this.pool.length * 2;
            for (var j:Number = this.pool.length; j < newCapacity; j++) {
                this.pool.push(null);
                this.availSpace.push(j);
            }
            allocIndex = Number(this.availSpace.pop());
            this.pool[allocIndex] = wrappedCallback;
        }

        listenersForEvent.callbacks[callbackID] = allocIndex;
        funcToID[funcID] = callbackID;
        listenersForEvent.count++;  // 增加该事件的回调计数
    }

    /**
     * 销毁事件总线，释放所有监听器和回调函数。
     * 清理回调池、可用索引列表及临时缓存，防止内存泄漏。
     */
    public function destroy():Void {
        for (var eventName:String in this.listeners) {
            var listenersForEvent:Object = this.listeners[eventName];
            for (var cbID:String in listenersForEvent.callbacks) {
                var index:Number = listenersForEvent.callbacks[cbID];
                if (index != undefined) {
                    this.pool[index] = null;
                    this.availSpace.push(index);
                }
            }
            delete this.listeners[eventName];
        }

        // 清空回调池中的所有剩余回调
        for (var i:Number = this.pool.length - 1; i >= 0; i--) {
            if (this.pool[i] != null) {
                this.pool[i] = null;
                this.availSpace.push(i);
            }
        }

        this.listeners = {};

        // 清空 Delegate 缓存中的包装回调函数
        Delegate.clearCache();

        // 清空临时参数和回调数组
        this.tempArgs.length = 0;
        this.tempCallbacks.length = 0;
    }
}
