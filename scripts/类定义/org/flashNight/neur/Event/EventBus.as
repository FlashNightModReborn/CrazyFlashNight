import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * EventBus 类用于事件的订阅、发布和管理。
 * 采用饿汉式单例模式，确保在类加载时实例化。
 * 通过预分配数组大小、索引操作和循环展开等优化措施，提高了性能。
 *
 * 版本历史:
 * v2.3.3 (2026-01) - 严重问题修复
 *   [CRITICAL] expandPool() 修复 do..while 边界错误
 *     问题：当 availSpaceTop==0 时（池满载触发扩容），复制旧空闲栈的 do..while 仍会执行一次
 *     后果：新槽位索引被旧值覆盖，导致高负载下回调被覆盖、串台、退订失败
 *     修复：改用 for 循环，copyEnd==0 时不执行；调整执行顺序，先复制再追加
 *   [FIX] forceResetDispatchDepth() 增强：同时清空栈数组中的残留引用
 *     避免异常后栈数组持有对象引用更久，拖慢 GC 回收
 *
 * v2.3.2 (2026-01) - 性能优化 + 参数验证
 *   [CRITICAL] 所有公共方法拒绝 null/空字符串 eventName，防止意外行为
 *   [PERF] unsubscribe 兼容模式：缓存前缀字符串，避免循环内重复拼接
 *   [PERF] unsubscribe 兼容模式：使用并行数组替代临时对象，减少内存分配
 *   [PERF] subscribe/subscribeOnce：UID 直接转为 String，避免重复类型转换
 *
 * v2.3.1 (2026-01) - 性能回归修复 + bug 修复
 *   [CRITICAL PERF] _removeSubscription 添加 eventName 参数，从 O(n) 优化为 O(1)
 *     修复：之前清理空事件时遍历所有 listeners 查找 eventName，导致批量退订 O(n²) 复杂度
 *   [FIX] unsubscribe 兼容模式修复：subscribeOnce 的 funcToID 值是 wrappedUID，需用它查找 callbacks
 *     修复：之前用 originalUID 查找 callbacks 导致 subscribeOnce 退订失败
 *   [FIX] destroy() 返回 false 当无内容需要清理（第二次调用返回 false）
 *
 * v2.3 (2026-01) - 三方交叉审查综合修复
 *   [CRITICAL] 去重键改为 (callback, scope) 组合，修复同callback不同scope被静默忽略的问题
 *   [CRITICAL] subscribe/subscribeOnce 返回 Boolean，让调用方知道是否成功订阅
 *   [CRITICAL] unsubscribe 添加可选 scope 参数，支持精确退订
 *   [PERF] publish/publishWithParam 移除 try/finally，彻底消除热路径开销
 *   [PERF] >15参数时直接使用数组，移除 slice() 分配
 *   [FIX] destroy() 返回 Boolean 表示是否成功执行
 *
 * v2.2 (2026-01) - 三方交叉审查综合修复
 *   [CRITICAL] subscribeOnce 添加 owner 参数，触发后通知 owner 清理订阅记录
 *   [PERF] publish/publishWithParam 移除 try/catch，采用 let-it-crash 策略提升热路径性能
 *   [FIX] destroy() 添加 _dispatchDepth 检查，防止递归 publish 时调用导致状态不一致
 *
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
 *   - [v2.3] (callback, scope) 组合唯一标识一个订阅，同callback不同scope可共存
 *   - [v2.3] 回调中的异常不再被捕获，会直接抛出（let-it-crash 策略，无 try/finally）
 *   - [v2.3] 不要在 publish 回调中调用 destroy()，会被拒绝执行并返回 false
 */
class org.flashNight.neur.Event.EventBus {
    /**
     * 存储事件监听器
     * [v2.3] 结构改为支持 (callback, scope) 组合键:
     * eventName -> {
     *   callbacks: { comboUID: poolIndex },     // comboUID = callbackUID + "|" + scopeUID
     *   funcToID: { comboUID: comboUID },       // 用于去重检查
     *   scopeMap: { comboUID: scopeUID },       // [v2.3] 存储 scope 信息用于精确退订
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
     * [v2.3 CRITICAL] 使用 (callback, scope) 组合键进行去重，同callback不同scope可共存
     * [v2.3 CRITICAL] 返回 Boolean 表示是否成功订阅，调用方据此决定是否记账
     *
     * @param eventName 事件名称
     * @param callback 要订阅的回调函数
     * @param scope 回调函数执行时的作用域
     * @return Boolean 是否成功订阅（false 表示重复订阅被忽略）
     */
    public function subscribe(eventName:String, callback:Function, scope:Object):Boolean {
        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        if (!this.listeners[eventName]) {
            this.listeners[eventName] = {callbacks: {}, funcToID: {}, scopeMap: {}, count: 0};
        }

        var listenersForEvent:Object = this.listeners[eventName];
        var funcToID:Object = listenersForEvent.funcToID;

        // [v2.3 CRITICAL] 使用 (callback, scope) 组合键
        // scope 为 null 时使用 "0" 作为 scopeUID，避免所有 null scope 共享同一个 UID
        // [v2.3.2 PERF] 直接转为 String，避免后续重复转换
        var callbackUID:String = String(Dictionary.getStaticUID(callback));
        var scopeUID:String = (scope != null) ? String(Dictionary.getStaticUID(scope)) : "0";
        var comboUID:String = callbackUID + "|" + scopeUID;

        // 检查重复订阅
        if (funcToID[comboUID] != undefined) {
            return false;
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
        listenersForEvent.callbacks[comboUID] = allocIndex;
        funcToID[comboUID] = comboUID;
        listenersForEvent.scopeMap[comboUID] = scopeUID;
        listenersForEvent.count++;
        return true;
    }

    /**
     * 取消订阅事件，移除指定的回调函数。
     *
     * [v2.3 CRITICAL] 添加可选的 scope 参数，支持精确退订
     * - 如果传入 scope，则精确匹配 (callback, scope) 组合
     * - 如果不传 scope（undefined），则删除该 callback 的所有订阅（兼容旧行为）
     *
     * @param eventName 事件名称
     * @param callback 要取消的回调函数
     * @param scope [v2.3] 可选，回调函数的作用域，用于精确匹配
     * @return Boolean 是否成功退订
     */
    public function unsubscribe(eventName:String, callback:Function, scope:Object):Boolean {
        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            return false;
        }

        var funcToID:Object = listenersForEvent.funcToID;
        var callbackUID:String = String(Dictionary.getStaticUID(callback));
        var removed:Boolean = false;

        // [v2.3] 检查一次性回调映射（按事件分桶）
        var onceMapForEvent:Object = this.onceCallbackMap[eventName];

        // [v2.3] 根据是否传入 scope 决定退订策略
        if (scope !== undefined) {
            // 精确匹配模式：只删除特定 (callback, scope) 组合
            var scopeUID:String = (scope != null) ? String(Dictionary.getStaticUID(scope)) : "0";
            var comboUID:String = callbackUID + "|" + scopeUID;

            // 检查是否是一次性订阅
            if (onceMapForEvent != null) {
                var mappedCallback:Function = onceMapForEvent[comboUID];
                if (mappedCallback != null) {
                    var originalCombo:String = comboUID;
                    comboUID = String(Dictionary.getStaticUID(mappedCallback)) + "|" + scopeUID;
                    delete onceMapForEvent[originalCombo];
                    // 清理空的 onceMap
                    var hasOnce:Boolean = false;
                    for (var k:String in onceMapForEvent) { hasOnce = true; break; }
                    if (!hasOnce) delete this.onceCallbackMap[eventName];
                }
            }

            removed = this._removeSubscription(eventName, listenersForEvent, comboUID, callbackUID + "|" + scopeUID);
        } else {
            // 兼容模式：删除该 callback 的所有订阅（遍历所有 scope）
            // [v2.3.2 PERF] 缓存前缀字符串，避免循环内重复拼接
            var prefix:String = callbackUID + "|";

            // [v2.3.2 PERF] 使用并行数组替代临时对象，减少内存分配
            var toRemoveOriginal:Array = [];
            var toRemoveActual:Array = [];
            var toRemoveCount:Number = 0;

            for (var uid:String in funcToID) {
                // [v2.3.2 PERF] 使用缓存的前缀
                if (uid.indexOf(prefix) == 0) {
                    toRemoveOriginal[toRemoveCount] = uid;
                    toRemoveActual[toRemoveCount] = funcToID[uid];
                    toRemoveCount++;
                }
            }

            // 处理一次性订阅映射
            if (onceMapForEvent != null) {
                for (var onceKey:String in onceMapForEvent) {
                    // [v2.3.2 PERF] 使用缓存的前缀
                    if (onceKey.indexOf(prefix) == 0) {
                        delete onceMapForEvent[onceKey];
                    }
                }
                var hasOnce:Boolean = false;
                for (var k:String in onceMapForEvent) { hasOnce = true; break; }
                if (!hasOnce) delete this.onceCallbackMap[eventName];
            }

            for (var i:Number = 0; i < toRemoveCount; i++) {
                // [v2.3.1 FIX] 用 actual（可能是 wrappedUID）查找 callbacks，用 original 清理 funcToID
                if (this._removeSubscription(eventName, listenersForEvent, toRemoveActual[i], toRemoveOriginal[i])) {
                    removed = true;
                }
            }
        }

        return removed;
    }

    /**
     * [v2.3] 内部方法：移除单个订阅
     * [v2.3.1 PERF] 添加 eventName 参数，避免 O(n) 遍历查找事件名
     *
     * @param eventName 事件名称（用于直接删除空事件）
     * @param listenersForEvent 该事件的监听器对象
     * @param comboUID 组合键（可能是 wrapped 的）
     * @param originalComboUID 原始组合键
     * @return Boolean 是否成功移除
     */
    private function _removeSubscription(eventName:String, listenersForEvent:Object, comboUID:String, originalComboUID:String):Boolean {
        var allocIndex:Number = listenersForEvent.callbacks[comboUID];
        if (allocIndex != undefined) {
            // 释放池空间
            this.pool[allocIndex] = null;
            this.availSpace[this.availSpaceTop++] = allocIndex;

            // 清理映射
            delete listenersForEvent.funcToID[originalComboUID];
            if (comboUID != originalComboUID) {
                delete listenersForEvent.funcToID[comboUID];
            }
            delete listenersForEvent.scopeMap[comboUID];
            delete listenersForEvent.callbacks[comboUID];
            listenersForEvent.count--;

            // [v2.3.1 PERF] 清理空事件 - 直接使用传入的 eventName，O(1) 复杂度
            if (listenersForEvent.count === 0) {
                delete this.listeners[eventName];
            }
            return true;
        }
        return false;
    }

    /**
     * 发布事件，通知所有订阅者，并传递可选的参数。
     *
     * [v2.3 PERF] 移除 try/finally，彻底消除热路径开销
     * [v2.3 PERF] >15参数时直接使用复用数组，移除 slice() 分配
     * [v2.1 PERF] 参数使用 _argsStack 深度复用，消除每次分配
     *
     * @param eventName 事件名称
     */
    public function publish(eventName:String):Void {
        // [v2.3.2] 参数验证：拒绝空字符串事件名（静默返回）
        if (eventName == null || eventName == "") {
            return;
        }

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
        var localTempArgs:Array = null;

        // [v2.3 PERF] 移除 try/finally，let-it-crash 策略
        if (argsLength >= 1) {
            // [v2.1 PERF] 使用深度栈复用参数数组
            localTempArgs = this._argsStack[depth];
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
                    // [v2.3 PERF] 直接使用复用数组，不再 slice()
                    // 契约：回调不应修改传入的参数数组
                    cb.apply(null, localTempArgs);
                }
            }

            // 清理参数数组
            localTempArgs.length = 0;
        } else {
            // 无参数时的执行
            for (; j >= 0; j--) {
                cb = localTempCallbacks[j];
                cb();
            }
        }

        // 清理回调数组并递减深度
        localTempCallbacks.length = 0;
        this._dispatchDepth--;
    }

    /**
     * 发布事件（带显式参数数组），通知所有订阅者，并传递参数数组。
     *
     * [v2.3 PERF] 移除 try/finally，彻底消除热路径开销
     * [v2.3 PERF] >15参数时直接使用传入数组，移除 slice() 分配
     *
     * @param eventName 事件名称
     * @param paramArray 显式传入的参数数组
     */
    public function publishWithParam(eventName:String, paramArray:Array):Void {
        // [v2.3.2] 参数验证：拒绝空字符串事件名（静默返回）
        if (eventName == null || eventName == "") {
            return;
        }

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

        // [v2.3 PERF] 移除 try/finally，let-it-crash 策略
        if (argsLength >= 1) {
            // 内联展开参数传递
            for (; j >= 0; j--) {
                callback = localTempCallbacks[j];
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
                    // [v2.3 PERF] 直接使用传入数组，不再 slice()
                    // 契约：回调不应修改传入的参数数组
                    callback.apply(null, paramArray);
                }
            }
        } else {
            for (; j >= 0; j--) {
                callback = localTempCallbacks[j];
                callback();
            }
        }

        // 清理回调数组并递减深度
        localTempCallbacks.length = 0;
        this._dispatchDepth--;
    }

    /**
     * 一次性订阅事件，回调执行一次后即自动取消订阅。
     *
     * [v2.3 CRITICAL] 使用 (callback, scope) 组合键，返回 Boolean
     * [v2.2 CRITICAL] 添加 owner 参数，触发后通知 owner 清理其内部订阅记录
     *                 owner 需实现 __onEventBusOnceFired(eventName, callback, scope) 方法
     *
     * @param eventName 事件名称
     * @param callback 要订阅的回调函数
     * @param scope 回调函数执行时的作用域
     * @param owner [v2.2] 可选，订阅的所有者对象，触发后会调用其 __onEventBusOnceFired 方法
     * @return Boolean 是否成功订阅（false 表示重复订阅被忽略）
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object, owner:Object):Boolean {
        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        var self:EventBus = this;
        var originalCallback:Function = callback;

        // [v2.3 CRITICAL] 使用 (callback, scope) 组合键
        // [v2.3.2 PERF] 直接转为 String，避免后续重复转换
        var callbackUID:String = String(Dictionary.getStaticUID(originalCallback));
        var scopeUID:String = (scope != null) ? String(Dictionary.getStaticUID(scope)) : "0";
        var originalComboUID:String = callbackUID + "|" + scopeUID;

        // 确保事件监听器结构存在
        var listenersForEvent:Object = this.listeners[eventName];
        if (!listenersForEvent) {
            listenersForEvent = {callbacks: {}, funcToID: {}, scopeMap: {}, count: 0};
            this.listeners[eventName] = listenersForEvent;
        }

        // 检查重复订阅
        if (listenersForEvent.funcToID[originalComboUID] != undefined) {
            return false;
        }

        // 确保该事件的 onceMap 存在
        var onceMapForEvent:Object = this.onceCallbackMap[eventName];
        if (onceMapForEvent == null) {
            onceMapForEvent = this.onceCallbackMap[eventName] = {};
        }

        // [v2.3] 创建一次性包装器，触发后通知 owner 清理订阅记录
        var wrappedOnceCallback:Function = function():Void {
            // 先退订再执行，确保回调执行过程中即使再次 publish 也不会重复触发
            // [v2.3] 传入 scope 进行精确退订
            self.unsubscribe(eventName, originalCallback, scope);

            // [v2.3] 通知 owner 清理其内部订阅记录，传入 scope 用于精确匹配
            if (owner != null && typeof(owner.__onEventBusOnceFired) == "function") {
                owner.__onEventBusOnceFired(eventName, originalCallback, scope);
            }

            // 使用 apply 绑定 scope 并传递所有参数
            originalCallback.apply(scope, arguments);
        };

        var wrappedCallbackUID:String = String(Dictionary.getStaticUID(wrappedOnceCallback));
        var wrappedComboUID:String = wrappedCallbackUID + "|" + scopeUID;

        // 建立原始回调到包装回调的映射（按事件分桶）
        onceMapForEvent[originalComboUID] = wrappedOnceCallback;

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
        listenersForEvent.callbacks[wrappedComboUID] = allocIndex;
        listenersForEvent.funcToID[originalComboUID] = wrappedComboUID;
        listenersForEvent.scopeMap[wrappedComboUID] = scopeUID;
        listenersForEvent.count++;
        return true;
    }

    /**
     * 销毁事件总线，释放所有监听器和回调函数。
     *
     * [v2.3.1 FIX] 返回 Boolean 表示是否实际执行了清理（状态变化语义）
     *   - true: 实际清理了监听器或回调
     *   - false: 被拒绝（dispatch中）或无需清理（已是空状态）
     * [v2.2 FIX] 添加 _dispatchDepth 检查，防止在 publish 回调中调用导致状态不一致
     *
     * @return Boolean true 表示实际执行了清理，false 表示被拒绝或无需清理
     */
    public function destroy():Boolean {
        // [v2.2 FIX] 防止在 publish 过程中调用 destroy
        if (this._dispatchDepth > 0) {
            trace("[EventBus] Warning: destroy() called during dispatch (depth=" + this._dispatchDepth + "), operation rejected");
            return false;
        }

        // [v2.3.1] 检查是否有需要清理的内容
        var hasListeners:Boolean = false;
        for (var key:String in this.listeners) {
            hasListeners = true;
            break;
        }

        // 检查 pool 中是否有回调
        var hasPoolCallbacks:Boolean = false;
        var poolLength:Number = this.pool.length;
        for (var i:Number = 0; i < poolLength; i++) {
            if (this.pool[i] != null) {
                hasPoolCallbacks = true;
                break;
            }
        }

        // [v2.3.1 FIX] 如果没有任何需要清理的内容，返回 false
        if (!hasListeners && !hasPoolCallbacks) {
            return false;
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
        for (var j:Number = 0; j < poolLength; j++) {
            if (this.pool[j] != null) {
                this.pool[j] = null;
                this.availSpace[this.availSpaceTop++] = j;
            }
        }

        this.listeners = {};
        Delegate.clearCache();
        this.onceCallbackMap = {};

        // 清理深度栈复用结构
        this._dispatchDepth = 0;
        this._cbStack = [];
        this._argsStack = [];
        return true;
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
     * [v2.3] 强制重置 dispatch 深度计数器
     * [v2.3.3] 增强：同时清空栈数组中的残留引用
     *
     * 警告：此方法仅用于测试目的和异常恢复！
     *
     * 由于 v2.3 移除了 publish 中的 try/finally（为了性能），
     * 当回调抛出错误时 _dispatchDepth 不会被递减。
     * 此方法允许测试套件在 let-it-crash 测试后重置状态。
     *
     * [v2.3.3] 新增：清空 _cbStack 和 _argsStack 中可能残留的引用
     * 如果异常发生在嵌套 publish 的较深层，深层数组可能持有对象引用更久，
     * 这会拖慢 GC 回收、加重内存压力。
     *
     * 生产代码中可在每帧开始时检查并重置（如果 _dispatchDepth != 0）。
     */
    public function forceResetDispatchDepth():Void {
        // 清空所有深度层的临时数组引用
        var cbStack:Array = this._cbStack;
        var argsStack:Array = this._argsStack;
        var len:Number = cbStack.length;

        for (var i:Number = 0; i < len; i++) {
            if (cbStack[i] != undefined) {
                cbStack[i].length = 0;
            }
            if (argsStack[i] != undefined) {
                argsStack[i].length = 0;
            }
        }

        this._dispatchDepth = 0;
    }

    /**
     * 扩展回调池和可用空间数组的容量。
     * 采用倍增策略，减少频繁扩容的开销。
     *
     * [v2.3.3 CRITICAL FIX] 修复 do..while 边界错误：
     * - 当 availSpaceTop == 0 时（池满载触发扩容），旧的 do..while 会错误执行一次
     * - 这会将 oldAvail[0]（历史残留值，通常为0）覆盖到 newAvail[0]
     * - 而 newAvail[0] 刚被设置为新槽位索引（oldCapacity），导致：
     *   1. 新槽位 oldCapacity 的索引丢失
     *   2. 旧槽位 0（正在使用）被错误放入空闲栈
     * - 后果：高负载下回调被覆盖、串台、退订失败
     *
     * 修复方案：
     * 1. 先复制旧的空闲栈（使用 for 循环，copyEnd==0 时不执行）
     * 2. 再追加新扩展的槽位索引
     */
    private function expandPool():Void {
        var oldPool:Array = this.pool;
        var oldAvail:Array = this.availSpace;
        var oldCapacity:Number = oldPool.length;
        var newCapacity:Number = oldCapacity * 2;

        var newPool:Array = new Array(newCapacity);
        var newAvail:Array = new Array(newCapacity);

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
        while (i < end) {
            newPool[i] = oldPool[i];
            i++;
        }

        // 2. [v2.3.3 FIX] 先复制旧的空闲栈（使用 for 循环，避免 do..while 边界问题）
        var copyEnd:Number = this.availSpaceTop;
        for (j = 0; j < copyEnd; j++) {
            newAvail[j] = oldAvail[j];
        }
        var newTop:Number = copyEnd;

        // 3. 追加新扩展的槽位索引（双元素展开，倍增保证偶数差）
        i = oldCapacity;
        end = newCapacity;
        while (i < end) {
            newPool[i] = null;
            newAvail[newTop++] = i++;
            newPool[i] = null;
            newAvail[newTop++] = i++;
        }

        this.pool = newPool;
        this.availSpace = newAvail;
        this.availSpaceTop = newTop;

        trace("[EventBus] Pool expanded: " + oldCapacity + " -> " + newCapacity);
    }
}
