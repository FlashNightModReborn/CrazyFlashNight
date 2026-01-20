import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * EventBus 类用于事件的订阅、发布和管理。
 * 采用饿汉式单例模式，确保在类加载时实例化。
 * 通过预分配数组大小、索引操作和循环展开等优化措施，提高了性能。
 *
 * 版本历史:
 * v2.1 (2026-01) - 三方交叉审查修复
 *   [CRITICAL] subscribeOnce 的 onceCallbackMap 改为按事件分桶，修复多事件覆盖问题
 *   [PERF] subscribeOnce 移除多余的 Delegate.create 包装，减少函数跳转
 *   [FIX] subscribeOnce 添加 funcToID 映射，统一订阅/退订语义
 *   [PERF] publish 参数使用 _argsStack 深度复用，消除每次分配
 *   [PERF] subscribe 中 UID 计算合并，减少冗余调用
 *   [CLEAN] 移除未使用的 tempArgs/tempCallbacks 死代码
 *   [CLEAN] publish 中移除冗余的逐个置 null，length=0 已足够
 *
 * v2.0 (2026-01) - 代码审查修复
 *   [FIX] unsubscribe 清理 funcToID 映射，修复"退订后无法再订阅"问题
 *   [FIX] subscribeOnce 传递 originalCallback 给 unsubscribe，修复 onceCallbackMap 泄漏
 *   [PERF] publish 使用深度栈复用替代 slice()，减少 GC 压力
 *
 * 契约说明:
 *   - 回调执行顺序不保证（for..in 枚举 Object key 在 AS2 中无序）
 *   - 调用方需确保 callback 和 scope 的有效性
 *   - 同一 callback 不可同时用于同一事件的 subscribe 和 subscribeOnce
 */
class org.flashNight.neur.Event.EventBus {
    /**
     * 存储事件监听器
     * 结构: eventName -> {
     *   callbacks: { callbackUID: poolIndex },  // callbackUID 是回调函数的 UID 字符串
     *   funcToID: { funcUID: callbackUID },     // funcUID 映射到 callbackUID（用于去重和退订）
     *   count: Number
     * }
     */
    private var listeners:Object;

    /** 回调函数池，用于存储回调函数的索引位置 */
    private var pool:Array;

    /** 可用索引列表，存储空闲的池位置（栈结构） */
    private var availSpace:Array;

    /** 可用索引列表的栈顶指针 */
    private var availSpaceTop:Number;

    /**
     * [v2.1] 一次性回调的映射，按事件名分桶
     * 结构: eventName -> { originalFuncUID -> wrappedCallback }
     * 修复: 之前是全局单表会导致不同事件的映射互相覆盖
     */
    private var onceCallbackMap:Object;

    /** [v2.0] 当前 publish 递归深度 */
    private var _dispatchDepth:Number;

    /** [v2.0] 每层递归独立的回调数组栈 */
    private var _cbStack:Array;

    /** [v2.1] 每层递归独立的参数数组栈，避免每次 publish 分配新数组 */
    private var _argsStack:Array;

    /** 静态实例，类加载时初始化，采用饿汉式单例模式 */
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

        // [v2.1] 改为按事件分桶的结构
        this.onceCallbackMap = {};

        // [v2.0] 初始化深度栈复用结构
        this._dispatchDepth = 0;
        this._cbStack = [];

        // [v2.1] 初始化参数栈复用结构
        this._argsStack = [];

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
     * @return EventBus 单例实例
     */
    public static function initialize():EventBus {
        Delegate.init();
        return instance;
    }

    /**
     * 获取 EventBus 单例实例的静态方法。
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

        // [v2.1 PERF] 合并 UID 计算，避免重复调用 Dictionary.getStaticUID
        // callbackUID: Number 类型的原始 UID
        // funcUID: String 类型，用于 Object 键查找
        var callbackUID:Number = Dictionary.getStaticUID(callback);
        var funcUID:String = String(callbackUID);

        // 检查重复订阅
        if (funcToID[funcUID] != undefined) {
            return;
        }

        var wrappedCallback:Function = Delegate.create(scope, callback);

        // 分配池索引
        var allocIndex:Number;
        if (this.availSpaceTop > 0) {
            allocIndex = this.availSpace[--this.availSpaceTop];
        } else {
            this.expandPool();
            allocIndex = this.availSpace[--this.availSpaceTop];
        }
        this.pool[allocIndex] = wrappedCallback;

        // 存入监听器结构
        // callbacks 使用 callbackUID（Number 转 String）作为键
        listenersForEvent.callbacks[callbackUID] = allocIndex;
        funcToID[funcUID] = callbackUID;
        listenersForEvent.count++;
    }

    /**
     * 取消订阅事件，移除指定的回调函数。
     *
     * [v2.1] 修复了 onceCallbackMap 按事件分桶后的查找逻辑
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
        var originalFuncUID:String = String(Dictionary.getStaticUID(callback));
        var unsubUID:String = originalFuncUID;

        // [v2.1] 检查一次性回调映射（按事件分桶）
        var onceMapForEvent:Object = this.onceCallbackMap[eventName];
        if (onceMapForEvent != null) {
            var mappedCallback:Function = onceMapForEvent[originalFuncUID];
            if (mappedCallback != null) {
                unsubUID = String(Dictionary.getStaticUID(mappedCallback));
                delete onceMapForEvent[originalFuncUID];

                // 如果该事件的 onceMap 为空，清理它
                var hasOnceCallbacks:Boolean = false;
                for (var k:String in onceMapForEvent) {
                    hasOnceCallbacks = true;
                    break;
                }
                if (!hasOnceCallbacks) {
                    delete this.onceCallbackMap[eventName];
                }
            }
        }

        // 在 callbacks 中查找
        var allocIndex:Number = listenersForEvent.callbacks[unsubUID];
        if (allocIndex != undefined) {
            // 释放池空间
            this.pool[allocIndex] = null;
            this.availSpace[this.availSpaceTop++] = allocIndex;

            // [v2.0 FIX] 清理 funcToID 映射
            delete funcToID[originalFuncUID];
            if (unsubUID != originalFuncUID) {
                delete funcToID[unsubUID];
            }

            // 清理数据结构
            delete listenersForEvent.callbacks[unsubUID];
            listenersForEvent.count--;

            // 清理空事件
            if (listenersForEvent.count === 0) {
                delete this.listeners[eventName];
            }
        }
    }

    /**
     * 发布事件，通知所有订阅者，并传递可选的参数。
     *
     * [v2.1 PERF] 参数使用 _argsStack 深度复用，消除每次分配
     * [v2.1 CLEAN] 移除冗余的逐个置 null，length=0 已足够解除引用
     *
     * @param eventName 事件名称
     */
    public function publish(eventName:String):Void {
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            return;
        }

        var callbacks:Object = listenersForEvent.callbacks;
        var poolRef:Array = this.pool;
        var tempCallbacksCount:Number = 0;
        var callback:Function;

        // [v2.0 PERF] 深度栈复用：每层递归使用独立数组
        var depth:Number = this._dispatchDepth++;
        var localTempCallbacks:Array = this._cbStack[depth];
        if (localTempCallbacks == null) {
            this._cbStack[depth] = localTempCallbacks = [];
        }

        // 收集回调函数
        // 注意：for..in 枚举顺序在 AS2 中不稳定，回调执行顺序不保证
        for (var cbID:String in callbacks) {
            callback = poolRef[callbacks[cbID]];
            if (callback != null) {
                localTempCallbacks[tempCallbacksCount++] = callback;
            }
        }

        var argsLength:Number = arguments.length - 1;
        var j:Number = tempCallbacksCount - 1;
        var cb:Function;

        if (argsLength >= 1) {
            // [v2.1 PERF] 使用深度栈复用参数数组
            var localTempArgs:Array = this._argsStack[depth];
            if (localTempArgs == null) {
                this._argsStack[depth] = localTempArgs = [];
            }

            // 复制参数到复用数组
            var i:Number = 0;
            do {
                localTempArgs[i] = arguments[i + 1];
            } while (++i < argsLength);

            // 执行回调函数（倒序执行）
            // 内联展开参数传递以避免 apply 开销，这是性能关键路径
            for (; j >= 0; j--) {
                cb = localTempCallbacks[j];
                try {
                    if (argsLength < 3) {
                        if (argsLength == 1) {
                            cb(localTempArgs[0]);
                        } else {
                            cb(localTempArgs[0], localTempArgs[1]);
                        }
                    } else if (argsLength < 7) {
                        if (argsLength == 3) {
                            cb(localTempArgs[0], localTempArgs[1], localTempArgs[2]);
                        } else if (argsLength == 4) {
                            cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3]);
                        } else if (argsLength == 5) {
                            cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4]);
                        } else {
                            cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5]);
                        }
                    } else if (argsLength < 11) {
                        if (argsLength == 7) {
                            cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6]);
                        } else if (argsLength == 8) {
                            cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7]);
                        } else if (argsLength == 9) {
                            cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8]);
                        } else {
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
                        } else {
                            cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11], localTempArgs[12], localTempArgs[13], localTempArgs[14]);
                        }
                    } else {
                        cb.apply(null, localTempArgs.slice(0, argsLength));
                    }
                } catch (error:Error) {
                    // 异常隔离：单个回调异常不影响其他回调执行
                }
            }

            // [v2.1] 清理参数数组（只需设置 length，无需逐个置 null）
            localTempArgs.length = 0;
        } else {
            // 无参数时的执行
            for (; j >= 0; j--) {
                cb = localTempCallbacks[j];
                try {
                    cb();
                } catch (error:Error) {
                    // 异常隔离
                }
            }
        }

        // [v2.1 CLEAN] 清理回调数组（length=0 已足够解除引用，无需逐个置 null）
        localTempCallbacks.length = 0;
        this._dispatchDepth--;
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
        var callback:Function;

        var depth:Number = this._dispatchDepth++;
        var localTempCallbacks:Array = this._cbStack[depth];
        if (localTempCallbacks == null) {
            this._cbStack[depth] = localTempCallbacks = [];
        }

        for (var cbID:String in callbacks) {
            callback = poolRef[callbacks[cbID]];
            if (callback != null) {
                localTempCallbacks[tempCallbacksCount++] = callback;
            }
        }

        var argsLength:Number = (paramArray != null) ? paramArray.length : 0;
        var j:Number = tempCallbacksCount - 1;

        if (argsLength >= 1) {
            // 内联展开参数传递
            for (; j >= 0; j--) {
                callback = localTempCallbacks[j];
                try {
                    if (argsLength < 3) {
                        if (argsLength == 1) {
                            callback(paramArray[0]);
                        } else {
                            callback(paramArray[0], paramArray[1]);
                        }
                    } else if (argsLength < 7) {
                        if (argsLength == 3) {
                            callback(paramArray[0], paramArray[1], paramArray[2]);
                        } else if (argsLength == 4) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3]);
                        } else if (argsLength == 5) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4]);
                        } else {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5]);
                        }
                    } else if (argsLength < 11) {
                        if (argsLength == 7) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6]);
                        } else if (argsLength == 8) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7]);
                        } else if (argsLength == 9) {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8]);
                        } else {
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
                        } else {
                            callback(paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11], paramArray[12], paramArray[13], paramArray[14]);
                        }
                    } else {
                        callback.apply(null, paramArray.slice(0, argsLength));
                    }
                } catch (error:Error) {
                    // 异常隔离
                }
            }
        } else {
            for (; j >= 0; j--) {
                callback = localTempCallbacks[j];
                try {
                    callback();
                } catch (error:Error) {
                    // 异常隔离
                }
            }
        }

        localTempCallbacks.length = 0;
        this._dispatchDepth--;
    }

    /**
     * 一次性订阅事件，回调执行一次后即自动取消订阅。
     *
     * [v2.1 CRITICAL] onceCallbackMap 改为按事件分桶 { eventName -> { funcUID -> wrappedCallback } }
     *                 修复了同一回调用于不同事件时的映射覆盖问题
     * [v2.1 PERF] 移除多余的 Delegate.create 包装，wrappedOnceCallback 已经处理 scope 绑定
     * [v2.1 FIX] 添加 funcToID 映射，防止重复订阅并统一退订语义
     *
     * @param eventName 事件名称
     * @param callback 要订阅的回调函数
     * @param scope 回调函数执行时的作用域
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object):Void {
        var self:EventBus = this;
        var originalCallback:Function = callback;
        var originalFuncUID:String = String(Dictionary.getStaticUID(originalCallback));

        // 确保事件监听器结构存在
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            listenersForEvent = {callbacks: {}, funcToID: {}, count: 0};
            this.listeners[eventName] = listenersForEvent;
        }

        // [v2.1 FIX] 检查重复订阅（与 subscribe 行为一致）
        if (listenersForEvent.funcToID[originalFuncUID] != undefined) {
            return;
        }

        // [v2.1 CRITICAL] 确保该事件的 onceMap 存在
        var onceMapForEvent:Object = this.onceCallbackMap[eventName];
        if (onceMapForEvent == null) {
            onceMapForEvent = this.onceCallbackMap[eventName] = {};
        }

        // [v2.1 PERF] 创建一次性包装器，内部已经处理 scope 绑定
        // 不再需要额外的 Delegate.create 包装，减少一层函数跳转
        var wrappedOnceCallback:Function = function():Void {
            // 先退订再执行，确保回调执行过程中即使再次 publish 也不会重复触发
            self.unsubscribe(eventName, originalCallback);
            // 使用 apply 绑定 scope 并传递所有参数
            originalCallback.apply(scope, arguments);
        };

        var wrappedCallbackUID:String = String(Dictionary.getStaticUID(wrappedOnceCallback));

        // [v2.1 CRITICAL] 建立原始回调到包装回调的映射（按事件分桶）
        onceMapForEvent[originalFuncUID] = wrappedOnceCallback;

        // 分配池索引
        var allocIndex:Number;
        if (this.availSpaceTop > 0) {
            allocIndex = this.availSpace[--this.availSpaceTop];
        } else {
            this.expandPool();
            allocIndex = this.availSpace[--this.availSpaceTop];
        }

        // 存入池并更新监听器结构
        this.pool[allocIndex] = wrappedOnceCallback;
        listenersForEvent.callbacks[wrappedCallbackUID] = allocIndex;

        // [v2.1 FIX] 添加 funcToID 映射，使用原始回调的 UID 映射到包装回调的 UID
        // 这样 unsubscribe 时可以通过原始回调找到包装回调
        listenersForEvent.funcToID[originalFuncUID] = wrappedCallbackUID;
        listenersForEvent.count++;
    }

    /**
     * 销毁事件总线，释放所有监听器和回调函数。
     * 此方法是幂等的，多次调用不会产生副作用。
     */
    public function destroy():Void {
        // 幂等检查
        var hasListeners:Boolean = false;
        for (var key:String in this.listeners) {
            hasListeners = true;
            break;
        }

        if (hasListeners) {
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
        this.onceCallbackMap = {};

        // 清理深度栈复用结构
        this._dispatchDepth = 0;
        this._cbStack = [];
        this._argsStack = [];
    }

    /**
     * 清理所有事件订阅（幂等）
     * 用于游戏重启时的彻底清理
     */
    public function clear():Void {
        destroy();
    }

    /**
     * 重置事件总线状态（幂等）
     * 用于游戏重启后重新初始化
     */
    public function reset():Void {
        destroy();
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

        var i:Number;
        var j:Number;
        var end:Number;

        // 复制旧池数据（循环展开4倍）
        i = 0;
        end = oldCapacity;
        while (i <= end - 4) {
            newPool[i] = oldPool[i];
            newPool[i+1] = oldPool[i+1];
            newPool[i+2] = oldPool[i+2];
            newPool[i+3] = oldPool[i+3];
            i += 4;
        }
        while (i < end) {
            newPool[i] = oldPool[i];
            i++;
        }

        // 初始化新扩展空间（双元素展开）
        i = oldCapacity;
        end = newCapacity;
        do {
            newPool[i] = null;
            newAvail[newTop++] = i++;
            newPool[i] = null;
            newAvail[newTop++] = i++;
        } while (i < end);

        // 复制旧可用空间
        var copyEnd:Number = this.availSpaceTop;
        j = 0;
        do {
            newAvail[j] = oldAvail[j];
        } while (++j < copyEnd);

        this.pool = newPool;
        this.availSpace = newAvail;
        this.availSpaceTop = newTop;
    }
}
