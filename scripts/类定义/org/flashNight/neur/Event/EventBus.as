import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * EventBus 类用于事件的订阅、发布和管理。
 * 采用饿汉式单例模式，确保在类加载时实例化。
 * 通过预分配数组大小、索引操作和循环展开等优化措施，提高了性能。
 */
class org.flashNight.neur.Event.EventBus {
    private var listeners:Object; // 存储事件监听器，结构为事件名 -> { callbacks: { callbackID: poolIndex }, funcToID: { funcID: callbackID }, count: Number }
    private var pool:Array; // 回调函数池，用于存储回调函数的索引位置
    private var availSpace:Array; // 可用索引列表，存储空闲的池位置
    private var availSpaceTop:Number; // 可用索引列表的栈顶指针
    private var tempArgs:Array; // 参数缓存区，重用避免频繁创建
    private var tempCallbacks:Array; // 重用的回调函数存储数组
    private var onceCallbackMap:Object; // 一次性回调的映射，key是 "原函数" 的UID，value是 "包装函数"

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
        this.tempArgs = new Array(10); // 假设最大参数数量为 10，可根据需要调整
        this.tempCallbacks = new Array(initialCapacity);
        this.onceCallbackMap = {};

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
        Delegate.init(); // 初始化 Delegate 缓存
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
            this.listeners[eventName] = {callbacks: {}, funcToID: {}, count: 0};
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
     * 先用 onceCallbackMap 查询，如果有，就替换为真正存进池的那个引用。
     *
     * @param eventName 事件名称
     * @param callback 要取消的回调函数
     */

    public function unsubscribe(eventName:String, callback:Function):Void {
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            return;
        }

        var funcToID:Object = listenersForEvent.funcToID;

        // 先拿到 "用户给的函数" 的 UID
        var unsubUID:String = String(Dictionary.getStaticUID(callback));

        // 检查是否在 onceCallbackMap 中。如果是一次性回调，就能在这里找到
        var mappedCallback:Function = this.onceCallbackMap[unsubUID];
        if (mappedCallback != null) {
            // 找到真正的包装函数引用
            // 用包装函数的 UID 才能在 listenersForEvent 里匹配到
            var mappedUID:String = String(Dictionary.getStaticUID(mappedCallback));

            // 用完就删掉映射，避免内存滞留
            delete this.onceCallbackMap[unsubUID];

            unsubUID = mappedUID; 
        }

        // 再去 funcToID 里找 callbackID
        var callbackID:Number = funcToID[unsubUID];
        if (callbackID == undefined) {
            return; // 根本没订阅过，不做事
        }

        // 拿到具体的 pool index
        var allocIndex:Number = listenersForEvent.callbacks[callbackID];
        if (allocIndex != undefined) {
            // 从池里移除
            this.pool[allocIndex] = null;
            this.availSpace[this.availSpaceTop++] = allocIndex;

            delete listenersForEvent.callbacks[callbackID];
            delete funcToID[unsubUID];
            listenersForEvent.count--;

            // 如果该事件名下所有回调都删光了，就把该事件也移除
            if (listenersForEvent.count === 0) {
                delete this.listeners[eventName];
            }
        }
    }

    /**
     * 发布事件，通知所有订阅者，并传递可选的参数。
     *
     * @param eventName 事件名称
     */
    public function publish(eventName:String):Void {
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent)
            return;

        var callbacks:Object = listenersForEvent.callbacks;
        var poolRef:Array = this.pool;
        var tempCallbacksCount:Number = 0;
        var localTempCallbacks:Array = this.tempCallbacks;
        var callback:Function;

        // 收集回调函数，使用索引方式
        for (var cbID:String in callbacks) {
            callback = poolRef[callbacks[cbID]];
            if (callback != null) {
                localTempCallbacks[tempCallbacksCount++] = callback;
            }
        }

        var argsLength:Number = arguments.length - 1;
        var j:Number = tempCallbacksCount - 1;
        var cb:Function;
        var localTempArgs:Array;

        // 如果有参数，使用索引方式复制参数到 tempArgs
        if (argsLength >= 1) {
            var i:Number = 0;
            do {
                localTempArgs[i] = arguments[i + 1];
            } while (++i < argsLength);

            for (; j >= 0; j--) {
                cb = localTempCallbacks[j];
                try {

                if (argsLength < 3) {
                    // argsLength 为 1 或 2
                    if (argsLength == 1) {
                        cb(localTempArgs[0]);
                    } else { // argsLength == 2
                        cb(localTempArgs[0], localTempArgs[1]);
                    }
                } else if (argsLength < 7) {
                    // argsLength 为 3 ~ 6
                    if (argsLength == 3) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2]);
                    } else if (argsLength == 4) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3]);
                    } else if (argsLength == 5) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4]);
                    } else { // argsLength == 6
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5]);
                    }
                } else if (argsLength < 11) {
                    // argsLength 为 7 ~ 10
                    if (argsLength == 7) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6]);
                    } else if (argsLength == 8) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7]);
                    } else if (argsLength == 9) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8]);
                    } else { // argsLength == 10
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9]);
                    }
                } else if (argsLength < 16) {
                    // argsLength 为 11 ~ 15
                    if (argsLength == 11) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10]);
                    } else if (argsLength == 12) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11]);
                    } else if (argsLength == 13) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11], localTempArgs[12]);
                    } else if (argsLength == 14) {
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11], localTempArgs[12], localTempArgs[13]);
                    } else { // argsLength == 15
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11], localTempArgs[12], localTempArgs[13], localTempArgs[14]);
                    }
                } else {
                    // 超出显式支持范围时，退回 apply 方式
                    cb.apply(null, localTempArgs.slice(0, argsLength));
                }

                } catch (error:Error) {
                    trace("Error executing callback for event '" + eventName + "': " + error.message);
                }
            }
        } else {
            // 倒序执行回调函数
            for (; j >= 0; j--) {
                cb = localTempCallbacks[j];
                try {
                    cb();
                } catch (error:Error) {
                    trace("Error executing callback for event '" + eventName + "': " + error.message);
                }
            }
        }
    }


    /**
     * 一次性订阅事件，回调执行一次后即自动取消订阅。
     * @param eventName 事件名称
     * @param callback  要订阅的回调函数（用户传进的实际函数/Delegate.create(...)）
     * @param scope     回调函数执行时的作用域
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object):Void {
        var self:EventBus = this;
        var originalCallback:Function = callback; 

        // 先用用户的callback生成UID —— 这是“原函数”的UID
        var originalFuncID:String = String(Dictionary.getStaticUID(originalCallback));

        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            listenersForEvent = {callbacks: {}, funcToID: {}, count: 0};
            this.listeners[eventName] = listenersForEvent;
        }

        // var funcToID:Object = listenersForEvent.funcToID;
        // if (funcToID[originalFuncID] != undefined) {
        //     return;
        // }

        // 包装一个函数：执行后自动退订
        var wrappedOnceCallback:Function = function() {
            originalCallback.apply(scope, arguments);
            self.unsubscribe(eventName, originalCallback);
        };
        // 再用 Delegate.create 得到实际放进回调池的包装函数
        var wrappedCallback:Function = Delegate.create(scope, wrappedOnceCallback);

        // ---- 记录“原函数UID -> 最终包装函数” 的映射 ----
        this.onceCallbackMap[originalFuncID] = wrappedCallback;

        // 生成包装函数UID
        var wrappedCallbackID:Number = Dictionary.getStaticUID(wrappedCallback);

        // 分配池索引
        var allocIndex:Number;
        if (this.availSpaceTop > 0) {
            allocIndex = this.availSpace[--this.availSpaceTop];
        } else {
            // 扩展容量
            this.expandPool();
            allocIndex = this.availSpace[--this.availSpaceTop];
        }

        // 存入池
        this.pool[allocIndex] = wrappedCallback;

        // 将“wrappedCallbackID”登记到监听器结构中
        listenersForEvent.callbacks[wrappedCallbackID] = allocIndex;
        // 或许可以 funcToID 中也存一份，并非必需
        // listenersForEvent.funcToID[String(wrappedCallbackID)] = wrappedCallbackID;

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
        this.onceCallbackMap = {};
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
