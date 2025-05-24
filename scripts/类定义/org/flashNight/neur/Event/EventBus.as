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
            // _root.发布消息("No callback StaticUID");
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
        // trace("[EventBus][" + eventName + "] unsubscribe() START");
        // trace(" |- Requested removal of callback UID: " + Dictionary.getStaticUID(callback));

        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            // trace(" |- No listeners found for event");
            // trace("[EventBus][" + eventName + "] unsubscribe() END (early exit)\n");
            return;
        }

        var funcToID:Object = listenersForEvent.funcToID;
        var unsubUID:String = String(Dictionary.getStaticUID(callback));
        // trace(" |- Original unsubUID: " + unsubUID);

        // 检查一次性回调映射
        var mappedCallback:Function = this.onceCallbackMap[unsubUID];
        if (mappedCallback != null) {
            var mappedUID:String = String(Dictionary.getStaticUID(mappedCallback));
            // trace(" |- Found mapped callback UID: " + mappedUID);
            // trace(" |- Cleaning onceCallbackMap entry for: " + unsubUID);
            delete this.onceCallbackMap[unsubUID];
            unsubUID = mappedUID;
        }

        // 直接使用 unsubUID（可能已替换为包装后的回调UID）在 callbacks 中查找
        var allocIndex:Number = listenersForEvent.callbacks[unsubUID];
        if (allocIndex != undefined) {
            // 释放池空间
            this.pool[allocIndex] = null;
            this.availSpace[this.availSpaceTop++] = allocIndex;
            // trace(" |- Freed pool index: " + allocIndex);
            // trace(" |- Avail space top: " + this.availSpaceTop);

            // 清理数据结构
            delete listenersForEvent.callbacks[unsubUID];
            listenersForEvent.count--;
            // trace(" |- Remaining listeners for event: " + listenersForEvent.count);

            // 清理空事件
            if (listenersForEvent.count === 0) {
                // trace(" |- Removing empty event listener structure");
                delete this.listeners[eventName];
            }
        }

        // trace("[EventBus][" + eventName + "] unsubscribe() END\n");
    }


    /**
     * 发布事件，通知所有订阅者，并传递可选的参数。
     *
     * @param eventName 事件名称
     */
    public function publish(eventName:String):Void {
        // trace("[EventBus][" + eventName + "] publish() START");

        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            // trace("[EventBus][" + eventName + "] publish() - No listeners found, returning");
            return;
        }

        var callbacks:Object = listenersForEvent.callbacks;
        var poolRef:Array = this.pool;
        var tempCallbacksCount:Number = 0;
        var localTempCallbacks:Array = this.tempCallbacks;
        var callback:Function;

        // 收集回调函数，使用索引方式
        // trace("[EventBus][" + eventName + "] publish() - Collecting callbacks...");
        for (var cbID:String in callbacks) {
            callback = poolRef[callbacks[cbID]];
            if (callback != null) {
                localTempCallbacks[tempCallbacksCount++] = callback;
            }
        }
        // trace("[EventBus][" + eventName + "] publish() - Collected " + tempCallbacksCount + " callbacks.");

        // 输出收集到的回调 UID 列表
        for (var k:Number = 0; k < tempCallbacksCount; k++) {
            // trace("    Callback[" + k + "] UID: " + Dictionary.getStaticUID(localTempCallbacks[k]));
        }

        var argsLength:Number = arguments.length - 1;
        // trace("[EventBus][" + eventName + "] publish() - Arguments count: " + argsLength);
        var j:Number = tempCallbacksCount - 1;
        var cb:Function;
        var localTempArgs:Array;

        // 如果有参数，使用索引方式复制参数到 tempArgs
        if (argsLength >= 1) {
            localTempArgs = []; // 每次复制新的数组，确保不受上次调用影响
            var i:Number = 0;
            do {
                localTempArgs[i] = arguments[i + 1];
            } while (++i < argsLength);
            // trace("[EventBus][" + eventName + "] publish() - Copied arguments: " + localTempArgs);

            // 执行回调函数（倒序执行）
            for (; j >= 0; j--) {
                cb = localTempCallbacks[j];
                // trace("[EventBus][" + eventName + "] publish() - Executing callback UID: " + Dictionary.getStaticUID(cb));
                try {
                    if (argsLength < 3) {
                        if (argsLength == 1) {
                            cb(localTempArgs[0]);
                        } else { // argsLength == 2
                            cb(localTempArgs[0], localTempArgs[1]);
                        }
                    } else if (argsLength < 7) {
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
                        cb.apply(null, localTempArgs.slice(0, argsLength));
                    }
                    // trace("[EventBus][" + eventName + "] publish() - Callback UID " + Dictionary.getStaticUID(cb) + " executed successfully.");
                } catch (error:Error) {
                    // trace("Error executing callback for event '" + eventName + "': " + error.message);
                }
            }
        } else {
            // 无参数时的倒序执行
            for (; j >= 0; j--) {
                cb = localTempCallbacks[j];
                // trace("[EventBus][" + eventName + "] publish() - Executing callback UID: " + Dictionary.getStaticUID(cb));
                try {
                    cb();
                    // trace("[EventBus][" + eventName + "] publish() - Callback UID " + Dictionary.getStaticUID(cb) + " executed successfully.");
                } catch (error:Error) {
                    // trace("Error executing callback for event '" + eventName + "': " + error.message);
                }
            }
        }

        // trace("[EventBus][" + eventName + "] publish() END");
    }

    /**
     * 发布事件（带显式参数数组），通知所有订阅者，并传递参数数组。
     *
     * @param eventName 事件名称
     * @param paramArray 显式传入的参数数组
     */
    public function publishWithParam(eventName:String, paramArray:Array):Void {
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            return;
        }
        
        var callbacks:Object = listenersForEvent.callbacks;
        var poolRef:Array = this.pool;
        var tempCallbacksCount:Number = 0;
        var localTempCallbacks:Array = this.tempCallbacks;
        var callback:Function;
        
        // 收集回调函数，使用索引方式遍历回调池
        for (var cbID:String in callbacks) {
            callback = poolRef[callbacks[cbID]];
            if (callback != null) {
                localTempCallbacks[tempCallbacksCount++] = callback;
            }
        }
        
        var argsLength:Number = (paramArray != null) ? paramArray.length : 0;
        var j:Number = tempCallbacksCount - 1;
        
        if (argsLength >= 1) {
            // 根据参数个数优化调用，避免 apply 的额外开销
            for (; j >= 0; j--) {
                callback = localTempCallbacks[j];
                try {
                    if (argsLength < 3) {
                        if (argsLength == 1) {
                            callback(paramArray[0]);
                        } else { // argsLength == 2
                            callback(paramArray[0], paramArray[1]);
                        }
                    } else if (argsLength < 7) {
                        if (argsLength == 3) {
                            callback(paramArray[0], paramArray[1], paramArray[2]);
                        } else if (argsLength == 4) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3]);
                        } else if (argsLength == 5) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4]);
                        } else { // argsLength == 6
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5]);
                        }
                    } else if (argsLength < 11) {
                        if (argsLength == 7) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6]);
                        } else if (argsLength == 8) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7]);
                        } else if (argsLength == 9) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8]);
                        } else { // argsLength == 10
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9]);
                        }
                    } else if (argsLength < 16) {
                        if (argsLength == 11) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10]);
                        } else if (argsLength == 12) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11]);
                        } else if (argsLength == 13) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11], paramArray[12]);
                        } else if (argsLength == 14) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11], paramArray[12], paramArray[13]);
                        } else { // argsLength == 15
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11], paramArray[12], paramArray[13], paramArray[14]);
                        }
                    } else {
                        callback.apply(null, paramArray.slice(0, argsLength));
                    }
                } catch (error:Error) {
                    // 出现异常时忽略当前回调的错误
                    // trace("Error executing callback for event '" + eventName + "': " + error.message);
                }
            }
        } else {
            // 当参数数组为空时，直接调用回调函数
            for (; j >= 0; j--) {
                callback = localTempCallbacks[j];
                try {
                    callback();
                } catch (error:Error) {
                    // trace("Error executing callback for event '" + eventName + "': " + error.message);
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
        // trace("[EventBus][" + eventName + "] subscribeOnce() START");
        // trace(" |- Original Callback UID: " + Dictionary.getStaticUID(callback));

        var self:EventBus = this;
        var originalCallback:Function = callback;
        var originalFuncID:String = String(Dictionary.getStaticUID(originalCallback));
        // trace(" |- Original FuncID: " + originalFuncID);

        // 确保事件监听器结构存在
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            listenersForEvent = {callbacks: {}, funcToID: {}, count: 0};
            this.listeners[eventName] = listenersForEvent;
            // trace(" |- Created new listeners structure for event: " + eventName);
        }

        // 创建一次性包装器，自动取消订阅自身
        var wrappedOnceCallback:Function = function():Void {
            // trace("[EventBus][" + eventName + "] wrappedOnceCallback EXECUTED");
            // trace(" |- Original Callback UID: " + originalFuncID + " is about to be unsubscribed");

            // 先取消订阅包装后的回调
            self.unsubscribe(eventName, wrappedCallback);
            // 再调用原始回调
            originalCallback.apply(scope, arguments);
            // trace(" |- Automatic unsubscription completed");
        };

        // 使用 Delegate 创建最终回调
        var wrappedCallback:Function = Delegate.create(scope, wrappedOnceCallback);
        var wrappedCallbackID:String = String(Dictionary.getStaticUID(wrappedCallback));
        // trace(" |- Wrapped Callback UID: " + wrappedCallbackID);

        // 建立原始回调到包装回调的映射
        this.onceCallbackMap[originalFuncID] = wrappedCallback;
        // trace(" |- onceCallbackMap[" + originalFuncID + "] = " + wrappedCallbackID);

        // 分配池索引
        var allocIndex:Number;
        if (this.availSpaceTop > 0) {
            allocIndex = this.availSpace[--this.availSpaceTop];
            // trace(" |- Reusing pool index: " + allocIndex);
        } else {
            this.expandPool();
            allocIndex = this.availSpace[--this.availSpaceTop];
            // trace(" |- Expanded pool, allocated index: " + allocIndex);
        }

        // 存入池并更新监听器结构
        this.pool[allocIndex] = wrappedCallback;
        listenersForEvent.callbacks[wrappedCallbackID] = allocIndex;
        listenersForEvent.count++;

        // trace(" |- Pool[" + allocIndex + "] assigned");
        // trace(" |- Current listener count for event: " + listenersForEvent.count);
        // trace("[EventBus][" + eventName + "] subscribeOnce() END\n");
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
        var oldPool:Array = this.pool;
        var oldAvail:Array = this.availSpace;
        var oldCapacity:Number = oldPool.length;
        var newCapacity:Number = oldCapacity * 2;
        
        var newPool:Array = new Array(newCapacity);
        var newAvail:Array = new Array(newCapacity);
        var newTop:Number = this.availSpaceTop;
        
        // 局部化循环变量
        var i:Number;
        var j:Number;
        var end:Number;

        // 1. 复制旧池数据（循环展开4倍）
        i = 0;
        end = oldCapacity;
        while (i <= end - 4) {
            newPool[i] = oldPool[i];
            newPool[i+1] = oldPool[i+1];
            newPool[i+2] = oldPool[i+2];
            newPool[i+3] = oldPool[i+3];
            i += 4;
        }
        // 处理剩余元素
        while (i < end) {
            newPool[i] = oldPool[i];
            i++;
        }

        // 2. 初始化新扩展空间（双元素展开）
        i = oldCapacity;
        end = newCapacity;
        do {
            newPool[i] = null;
            newAvail[newTop++] = i++;
            newPool[i] = null;
            newAvail[newTop++] = i++;
        } while (i < end);

        // 3. 复制旧可用空间（单循环展开）
        var copyEnd:Number = this.availSpaceTop;
        j = 0;
        do {
            newAvail[j] = oldAvail[j];
        } while (++j < copyEnd);

        // 更新对象属性
        this.pool = newPool;
        this.availSpace = newAvail;
        this.availSpaceTop = newTop;
    }

}
