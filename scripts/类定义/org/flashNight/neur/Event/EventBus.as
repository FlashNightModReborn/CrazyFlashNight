import org.flashNight.naki.DataStructures.Dictionary;

/**
 * EventBus 类用于事件的订阅、发布和管理。
 * 采用饿汉式单例模式，确保在类加载时实例化。
 *
 * 版本历史:
 * v3.0 (2026-03) - 结构性性能重构
 *   [PERF] listeners 从 Object{comboUID:poolIndex} 改为并行数组 fns[]/scopes[]
 *     消除 publish 中的 for..in 枚举（H16: 2200~7800ns/iter → while(i--) ~35ns/iter）
 *   [PERF] 去掉 Delegate.create 包装层，publish 时直接 fn.call(scope, ...)
 *     消除闭包双重调用（~1235ns 闭包 + ~1340ns call → 单次 ~1340ns call）
 *   [PERF] 去掉 pool/availSpace 对象池，改为直接数组存储
 *     subscribe 路径不再需要池分配/Delegate创建
 *   [PERF] unsubscribe 使用 swap-and-pop 替代线性查找删除
 *     消除 splice（H20: 4231ns）开销
 *   [PERF] publish0/publish1/publish2 特化入口，消除 arguments 开销
 *     H09: arguments.length=1538ns, arguments读取=1306ns
 *   [COMPAT] 外部 API 签名完全不变，对 EventDispatcher 透明
 *   [COMPAT] Delegate 缓存机制保留用于外部直接使用，EventBus 内部不再依赖
 *
 * v2.3.3 (2026-01) - 严重问题修复
 *   [CRITICAL] expandPool() 修复 do..while 边界错误
 *   [FIX] forceResetDispatchDepth() 增强：同时清空栈数组中的残留引用
 *
 * v2.3.2 (2026-01) - 性能优化 + 参数验证
 *   [CRITICAL] 所有公共方法拒绝 null/空字符串 eventName
 *
 * v2.3 (2026-01) - 三方交叉审查综合修复
 *   [CRITICAL] 去重键改为 (callback, scope) 组合
 *   [CRITICAL] subscribe/subscribeOnce 返回 Boolean
 *   [CRITICAL] unsubscribe 添加可选 scope 参数
 *   [PERF] publish 移除 try/finally，let-it-crash 策略
 *
 * 契约说明:
 *   - [v3.0] 回调执行顺序为逆序（后订阅先执行），与 v2.x for..in 无序行为兼容
 *     原契约已声明"顺序不保证"，逆序是 while(i--) 的自然结果
 *   - 调用方需确保 callback 和 scope 的有效性
 *   - [v2.3] (callback, scope) 组合唯一标识一个订阅
 *   - [v2.3] 回调中的异常不再被捕获（let-it-crash）
 *   - [v2.3] 不要在 publish 回调中调用 destroy()
 */
class org.flashNight.neur.Event.EventBus {
    /**
     * [v3.0] 存储事件监听器
     * 结构:
     * eventName -> {
     *   fns:    Function[],                // 回调函数数组
     *   scopes: Object[],                  // 对应的 scope 数组（并行）
     *   ids:    Object{comboUID: index},    // comboUID → 数组索引，用于去重和退订
     *   count:  Number                     // 当前订阅者数量
     * }
     */
    private var listeners:Object;

    /**
     * [v2.1] 一次性回调的映射，按事件名分桶
     * 结构: eventName -> { originalComboUID -> wrappedCallback }
     * [v3.0] wrappedCallback 不再用 Delegate 包装，直接是闭包
     */
    private var onceCallbackMap:Object;

    /** [v2.0] 当前 publish 递归深度 */
    private var _dispatchDepth:Number;

    /** [v2.0] 每层递归独立的回调数组栈 */
    private var _cbStack:Array;

    /** [v3.0] 每层递归独立的 scope 数组栈 */
    private var _scStack:Array;

    /** [v2.1] 每层递归独立的参数数组栈 */
    private var _argsStack:Array;

    /** 静态实例，饿汉式单例 */
    public static var instance:EventBus = new EventBus();

    /**
     * 构造函数。
     */
    private function EventBus() {
        this.listeners = {};
        this.onceCallbackMap = {};
        this._dispatchDepth = 0;
        this._cbStack = [];
        this._scStack = [];
        this._argsStack = [];
    }

    public static function initialize():EventBus {
        return instance;
    }

    public static function getInstance():EventBus {
        return instance;
    }

    /**
     * 订阅事件。
     *
     * [v3.0] 去掉 Delegate.create 包装，直接存储 fn+scope 对
     * [v2.3] (callback, scope) 组合键去重，返回 Boolean
     *
     * @param eventName 事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域
     * @return Boolean 是否成功订阅
     */
    public function subscribe(eventName:String, callback:Function, scope:Object):Boolean {
        if (eventName == null || eventName == "") {
            return false;
        }

        var le_:Object = this.listeners[eventName];
        if (!le_) {
            le_ = new Object();
            le_.fns = [];
            le_.scopes = [];
            le_.ids = new Object();
            le_.count = 0;
            this.listeners[eventName] = le_;
        }

        var callbackUID:String = String(Dictionary.getStaticUID(callback));
        var scopeUID:String = (scope != null) ? String(Dictionary.getStaticUID(scope)) : "0";
        var comboUID:String = callbackUID + "|" + scopeUID;

        // 去重：检查 ids（普通订阅）和 onceCallbackMap（once 订阅）
        if (le_.ids[comboUID] !== undefined) {
            return false;
        }
        var onceMap:Object = this.onceCallbackMap[eventName];
        if (onceMap != null && onceMap[comboUID] !== undefined) {
            return false;
        }

        // [v3.0] 直接追加到并行数组末尾
        var idx:Number = le_.count;
        le_.fns[idx] = callback;
        le_.scopes[idx] = scope;
        le_.ids[comboUID] = idx;
        le_.count = idx + 1;
        return true;
    }

    /**
     * 取消订阅事件。
     *
     * [v3.0] 使用 swap-and-pop 替代线性删除，O(1)
     * [v2.3] 可选 scope 参数，支持精确退订
     *
     * @param eventName 事件名称
     * @param callback 回调函数
     * @param scope 可选，精确匹配
     * @return Boolean 是否成功退订
     */
    public function unsubscribe(eventName:String, callback:Function, scope:Object):Boolean {
        if (eventName == null || eventName == "") {
            return false;
        }

        var le_:Object = this.listeners[eventName];
        if (!le_) {
            return false;
        }

        var callbackUID:String = String(Dictionary.getStaticUID(callback));
        var removed:Boolean = false;

        // 检查一次性回调映射
        var onceMapForEvent:Object = this.onceCallbackMap[eventName];

        if (scope !== undefined) {
            // 精确匹配模式
            var scopeUID:String = (scope != null) ? String(Dictionary.getStaticUID(scope)) : "0";
            var comboUID:String = callbackUID + "|" + scopeUID;

            // 检查是否是一次性订阅
            if (onceMapForEvent != null) {
                var wrappedCombo:String = onceMapForEvent[comboUID];
                if (wrappedCombo != null) {
                    // once 订阅：ids 中只有 wrappedComboUID
                    removed = this._removeByCombo(eventName, le_, wrappedCombo);
                    delete onceMapForEvent[comboUID];
                    // 清理空的 onceMap
                    var hasOnce:Boolean = false;
                    for (var k:String in onceMapForEvent) { hasOnce = true; break; }
                    if (!hasOnce) delete this.onceCallbackMap[eventName];
                    return removed;
                }
            }

            // 普通订阅
            removed = this._removeByCombo(eventName, le_, comboUID);
        } else {
            // 兼容模式：删除该 callback 的所有订阅
            var prefix:String = callbackUID + "|";
            var idsRef:Object = le_.ids;

            // 收集普通订阅的 comboUID
            var toRemove:Array = [];
            var toRemoveCount:Number = 0;
            for (var uid:String in idsRef) {
                if (uid.indexOf(prefix) == 0) {
                    toRemove[toRemoveCount++] = uid;
                }
            }

            // 收集 once 订阅的 wrappedComboUID（ids 中只有 wrapped 键）
            if (onceMapForEvent != null) {
                for (var onceKey:String in onceMapForEvent) {
                    if (onceKey.indexOf(prefix) == 0) {
                        var wrappedKey:String = onceMapForEvent[onceKey];
                        // wrappedKey 已经在 ids 中，可能已被上面收集（不会，因为 wrapped 的 prefix 不同）
                        // 需要额外加入删除列表
                        toRemove[toRemoveCount++] = wrappedKey;
                        delete onceMapForEvent[onceKey];
                    }
                }
                var hasOnce2:Boolean = false;
                for (var k2:String in onceMapForEvent) { hasOnce2 = true; break; }
                if (!hasOnce2) delete this.onceCallbackMap[eventName];
            }

            // 逐个删除
            for (var i:Number = 0; i < toRemoveCount; i++) {
                if (this._removeByCombo(eventName, le_, toRemove[i])) {
                    removed = true;
                }
            }
        }

        return removed;
    }

    /**
     * [v3.0] 内部方法：通过 comboUID 移除单个订阅，使用 swap-and-pop
     *
     * 不变量：ids 中每个数组槽位只有一个键（1:1 映射）
     * 因此交换后只需更新一个键，可以 break
     *
     * @param eventName 事件名称
     * @param le_ 该事件的监听器对象
     * @param comboUID 要删除的 comboUID（ids 中的键）
     * @return Boolean 是否成功移除
     */
    private function _removeByCombo(eventName:String, le_:Object, comboUID:String):Boolean {
        var idx:Number = le_.ids[comboUID];
        if (idx === undefined) {
            return false;
        }

        var lastIdx:Number = le_.count - 1;
        var fns:Array = le_.fns;
        var scopes:Array = le_.scopes;
        var ids:Object = le_.ids;

        if (idx != lastIdx) {
            // swap with last
            fns[idx] = fns[lastIdx];
            scopes[idx] = scopes[lastIdx];

            // 更新被交换元素的索引（1:1 不变量，只有一个键）
            for (var k:String in ids) {
                if (ids[k] === lastIdx) {
                    ids[k] = idx;
                    break;
                }
            }
        }

        // pop last
        fns[lastIdx] = null;
        scopes[lastIdx] = null;
        fns.length = lastIdx;
        scopes.length = lastIdx;

        // 清理 ids
        delete ids[comboUID];
        le_.count = lastIdx;

        // 清理空事件
        if (lastIdx === 0) {
            delete this.listeners[eventName];
        }
        return true;
    }

    /**
     * [v3.0] 零参数特化发布，完全不触碰 arguments。
     * H09: 消除 arguments.length(1538ns) + arguments[i](1306ns) 开销
     *
     * @param eventName 事件名称
     */
    public function publish0(eventName:String):Void {
        if (eventName == null || eventName == "") {
            return;
        }

        var le_:Object = this.listeners[eventName];
        if (!le_) {
            return;
        }

        var fns:Array = le_.fns;
        var scopes:Array = le_.scopes;
        var cnt:Number = le_.count;

        // 快照到栈复用数组，防止回调中修改订阅列表导致问题
        var depth:Number = this._dispatchDepth++;
        var localCb:Array = this._cbStack[depth];
        var localSc:Array = this._scStack[depth];
        if (localCb == null) {
            this._cbStack[depth] = localCb = [];
            this._scStack[depth] = localSc = [];
        }

        var i:Number = cnt;
        while (i--) {
            localCb[i] = fns[i];
            localSc[i] = scopes[i];
        }

        // 执行（倒序）
        i = cnt;
        while (i--) {
            localCb[i].call(localSc[i]);
        }

        localCb.length = 0;
        localSc.length = 0;
        this._dispatchDepth--;
    }

    /**
     * [v3.0] 单参数特化发布。
     *
     * @param eventName 事件名称
     * @param a1 参数1
     */
    public function publish1(eventName:String, a1):Void {
        if (eventName == null || eventName == "") {
            return;
        }

        var le_:Object = this.listeners[eventName];
        if (!le_) {
            return;
        }

        var fns:Array = le_.fns;
        var scopes:Array = le_.scopes;
        var cnt:Number = le_.count;

        var depth:Number = this._dispatchDepth++;
        var localCb:Array = this._cbStack[depth];
        var localSc:Array = this._scStack[depth];
        if (localCb == null) {
            this._cbStack[depth] = localCb = [];
            this._scStack[depth] = localSc = [];
        }

        var i:Number = cnt;
        while (i--) {
            localCb[i] = fns[i];
            localSc[i] = scopes[i];
        }

        i = cnt;
        while (i--) {
            localCb[i].call(localSc[i], a1);
        }

        localCb.length = 0;
        localSc.length = 0;
        this._dispatchDepth--;
    }

    /**
     * [v3.0] 双参数特化发布。
     *
     * @param eventName 事件名称
     * @param a1 参数1
     * @param a2 参数2
     */
    public function publish2(eventName:String, a1, a2):Void {
        if (eventName == null || eventName == "") {
            return;
        }

        var le_:Object = this.listeners[eventName];
        if (!le_) {
            return;
        }

        var fns:Array = le_.fns;
        var scopes:Array = le_.scopes;
        var cnt:Number = le_.count;

        var depth:Number = this._dispatchDepth++;
        var localCb:Array = this._cbStack[depth];
        var localSc:Array = this._scStack[depth];
        if (localCb == null) {
            this._cbStack[depth] = localCb = [];
            this._scStack[depth] = localSc = [];
        }

        var i:Number = cnt;
        while (i--) {
            localCb[i] = fns[i];
            localSc[i] = scopes[i];
        }

        i = cnt;
        while (i--) {
            localCb[i].call(localSc[i], a1, a2);
        }

        localCb.length = 0;
        localSc.length = 0;
        this._dispatchDepth--;
    }

    /**
     * 发布事件（通用版本，支持可变参数）。
     *
     * [v3.0] 去掉 for..in，使用 while(i--) 遍历并行数组
     *        去掉 Delegate 包装，直接 fn.call(scope, ...)
     *
     * @param eventName 事件名称
     */
    public function publish(eventName:String):Void {
        if (eventName == null || eventName == "") {
            return;
        }

        var le_:Object = this.listeners[eventName];
        if (!le_) {
            return;
        }

        var fns:Array = le_.fns;
        var scopes:Array = le_.scopes;
        var cnt:Number = le_.count;

        // 快照到栈复用数组
        var depth:Number = this._dispatchDepth++;
        var localCb:Array = this._cbStack[depth];
        var localSc:Array = this._scStack[depth];
        if (localCb == null) {
            this._cbStack[depth] = localCb = [];
            this._scStack[depth] = localSc = [];
        }

        var i:Number = cnt;
        while (i--) {
            localCb[i] = fns[i];
            localSc[i] = scopes[i];
        }

        var argsLength:Number = arguments.length - 1;
        var j:Number;
        var localTempArgs:Array;

        if (argsLength >= 1) {
            localTempArgs = this._argsStack[depth];
            if (localTempArgs == null) {
                this._argsStack[depth] = localTempArgs = [];
            }

            // 复制参数
            i = 0;
            do {
                localTempArgs[i] = arguments[i + 1];
            } while (++i < argsLength);

            // 执行回调（倒序）
            // [v3.0] 直接 fn.call(scope, ...) 替代调用 Delegate 包装的闭包
            j = cnt;
            while (j--) {
                var cb:Function = localCb[j];
                var sc:Object = localSc[j];
                if (argsLength < 3) {
                    if (argsLength == 1) {
                        cb.call(sc, localTempArgs[0]);
                    } else {
                        cb.call(sc, localTempArgs[0], localTempArgs[1]);
                    }
                } else if (argsLength < 7) {
                    if (argsLength == 3) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2]);
                    } else if (argsLength == 4) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3]);
                    } else if (argsLength == 5) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4]);
                    } else {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5]);
                    }
                } else if (argsLength < 11) {
                    if (argsLength == 7) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6]);
                    } else if (argsLength == 8) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7]);
                    } else if (argsLength == 9) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8]);
                    } else {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9]);
                    }
                } else if (argsLength < 16) {
                    if (argsLength == 11) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10]);
                    } else if (argsLength == 12) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11]);
                    } else if (argsLength == 13) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11], localTempArgs[12]);
                    } else if (argsLength == 14) {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11], localTempArgs[12], localTempArgs[13]);
                    } else {
                        cb.call(sc, localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8], localTempArgs[9], localTempArgs[10], localTempArgs[11], localTempArgs[12], localTempArgs[13], localTempArgs[14]);
                    }
                } else {
                    cb.apply(sc, localTempArgs);
                }
            }

            localTempArgs.length = 0;
        } else {
            // 无参数
            j = cnt;
            while (j--) {
                localCb[j].call(localSc[j]);
            }
        }

        localCb.length = 0;
        localSc.length = 0;
        this._dispatchDepth--;
    }

    /**
     * 发布事件（带显式参数数组）。
     *
     * [v3.0] 同 publish，使用并行数组遍历
     *
     * @param eventName 事件名称
     * @param paramArray 参数数组
     */
    public function publishWithParam(eventName:String, paramArray:Array):Void {
        if (eventName == null || eventName == "") {
            return;
        }

        var le_:Object = this.listeners[eventName];
        if (!le_) {
            return;
        }

        var fns:Array = le_.fns;
        var scopes:Array = le_.scopes;
        var cnt:Number = le_.count;

        var depth:Number = this._dispatchDepth++;
        var localCb:Array = this._cbStack[depth];
        var localSc:Array = this._scStack[depth];
        if (localCb == null) {
            this._cbStack[depth] = localCb = [];
            this._scStack[depth] = localSc = [];
        }

        var i:Number = cnt;
        while (i--) {
            localCb[i] = fns[i];
            localSc[i] = scopes[i];
        }

        var argsLength:Number = (paramArray != null) ? paramArray.length : 0;
        var j:Number;

        if (argsLength >= 1) {
            j = cnt;
            while (j--) {
                var cb:Function = localCb[j];
                var sc:Object = localSc[j];
                if (argsLength < 3) {
                    if (argsLength == 1) {
                        cb.call(sc, paramArray[0]);
                    } else {
                        cb.call(sc, paramArray[0], paramArray[1]);
                    }
                } else if (argsLength < 7) {
                    if (argsLength == 3) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2]);
                    } else if (argsLength == 4) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3]);
                    } else if (argsLength == 5) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4]);
                    } else {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5]);
                    }
                } else if (argsLength < 11) {
                    if (argsLength == 7) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6]);
                    } else if (argsLength == 8) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7]);
                    } else if (argsLength == 9) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8]);
                    } else {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9]);
                    }
                } else if (argsLength < 16) {
                    if (argsLength == 11) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10]);
                    } else if (argsLength == 12) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11]);
                    } else if (argsLength == 13) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11], paramArray[12]);
                    } else if (argsLength == 14) {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11], paramArray[12], paramArray[13]);
                    } else {
                        cb.call(sc, paramArray[0], paramArray[1], paramArray[2], paramArray[3], paramArray[4], paramArray[5], paramArray[6], paramArray[7], paramArray[8], paramArray[9], paramArray[10], paramArray[11], paramArray[12], paramArray[13], paramArray[14]);
                    }
                } else {
                    cb.apply(sc, paramArray);
                }
            }
        } else {
            j = cnt;
            while (j--) {
                localCb[j].call(localSc[j]);
            }
        }

        localCb.length = 0;
        localSc.length = 0;
        this._dispatchDepth--;
    }

    /**
     * 一次性订阅事件。
     *
     * [v3.0] 去掉 Delegate 包装，wrappedOnceCallback 是普通闭包
     * [v2.3] (callback, scope) 组合键，返回 Boolean
     * [v2.2] owner 参数通知 EventDispatcher 清理
     *
     * @param eventName 事件名称
     * @param callback 回调函数
     * @param scope 作用域
     * @param owner 可选，触发后通知清理
     * @return Boolean 是否成功订阅
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object, owner:Object):Boolean {
        if (eventName == null || eventName == "") {
            return false;
        }

        var self:EventBus = this;
        var originalCallback:Function = callback;

        var callbackUID:String = String(Dictionary.getStaticUID(originalCallback));
        var scopeUID:String = (scope != null) ? String(Dictionary.getStaticUID(scope)) : "0";
        var originalComboUID:String = callbackUID + "|" + scopeUID;

        // 确保监听器结构存在
        var le_:Object = this.listeners[eventName];
        if (!le_) {
            le_ = new Object();
            le_.fns = [];
            le_.scopes = [];
            le_.ids = new Object();
            le_.count = 0;
            this.listeners[eventName] = le_;
        }

        // 去重：检查 ids（普通订阅）和 onceCallbackMap（once 订阅）
        if (le_.ids[originalComboUID] !== undefined) {
            return false;
        }
        var onceMapForEvent:Object = this.onceCallbackMap[eventName];
        if (onceMapForEvent != null && onceMapForEvent[originalComboUID] !== undefined) {
            return false;
        }

        // 确保 onceMap 存在
        if (onceMapForEvent == null) {
            onceMapForEvent = new Object();
            this.onceCallbackMap[eventName] = onceMapForEvent;
        }

        // [v3.0] 创建一次性包装器（不再用 Delegate，直接闭包）
        var wrappedOnceCallback:Function = function():Void {
            // 先退订再执行
            self.unsubscribe(eventName, originalCallback, scope);

            // 通知 owner 清理
            if (owner != null && typeof(owner.__onEventBusOnceFired) == "function") {
                owner.__onEventBusOnceFired(eventName, originalCallback, scope);
            }

            originalCallback.apply(scope, arguments);
        };

        var wrappedCallbackUID:String = String(Dictionary.getStaticUID(wrappedOnceCallback));
        var wrappedComboUID:String = wrappedCallbackUID + "|" + scopeUID;

        // 映射：originalComboUID -> wrappedComboUID（用于 unsubscribe 查找）
        onceMapForEvent[originalComboUID] = wrappedComboUID;

        // ids 只存 wrappedComboUID（1:1 不变量）
        var idx:Number = le_.count;
        le_.fns[idx] = wrappedOnceCallback;
        le_.scopes[idx] = scope;
        le_.ids[wrappedComboUID] = idx;
        le_.count = idx + 1;
        return true;
    }

    /**
     * 销毁事件总线。
     *
     * [v3.0] 简化：直接清空 listeners 对象
     * [v2.2] _dispatchDepth 检查
     *
     * @return Boolean 是否成功执行
     */
    public function destroy():Boolean {
        if (this._dispatchDepth > 0) {
            trace("[EventBus] Warning: destroy() called during dispatch (depth=" + this._dispatchDepth + "), operation rejected");
            return false;
        }

        // 检查是否有需要清理的内容
        var hasListeners:Boolean = false;
        for (var key:String in this.listeners) {
            hasListeners = true;
            break;
        }

        if (!hasListeners) {
            return false;
        }

        // [v3.0] 直接清空
        this.listeners = {};
        this.onceCallbackMap = {};
        this._dispatchDepth = 0;
        this._cbStack = [];
        this._scStack = [];
        this._argsStack = [];
        return true;
    }

    /**
     * 清理所有事件订阅（幂等）
     */
    public function clear():Void {
        destroy();
    }

    /**
     * 重置事件总线状态（幂等）
     */
    public function reset():Void {
        destroy();
    }

    /**
     * 强制重置 dispatch 深度计数器。
     * [v3.0] 同时清空 _cbStack/_scStack/_argsStack 中的残留引用
     */
    public function forceResetDispatchDepth():Void {
        var cbStack:Array = this._cbStack;
        var scStack:Array = this._scStack;
        var argsStack:Array = this._argsStack;
        var len:Number = cbStack.length;

        for (var i:Number = 0; i < len; i++) {
            if (cbStack[i] != undefined) {
                cbStack[i].length = 0;
            }
            if (scStack[i] != undefined) {
                scStack[i].length = 0;
            }
            if (argsStack[i] != undefined) {
                argsStack[i].length = 0;
            }
        }

        this._dispatchDepth = 0;
    }
}
