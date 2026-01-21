import org.flashNight.neur.Event.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.gesh.arguments.*;

/**
 * EventDispatcher 类为业务逻辑提供一个轻量级的事件分发接口。
 * 它内部通过 EventBus 来实现具体的事件订阅与发布功能，
 * 通过为事件名称附加唯一的实例 ID 实现多实例的事件隔离。
 *
 * 版本历史:
 * v2.3.2 (2026-01) - 兼容性修复 + 参数验证
 *   [CRITICAL] 所有公共方法拒绝 null/空字符串 eventName，防止意外行为
 *   [FIX] unsubscribe/unsubscribeGlobal 当 scope 为 undefined 时使用兼容模式
 *     修复：之前 scope === undefined 时无法匹配已记录的 subscriptions，导致退订失败
 *   [FIX] 从后往前遍历 subscriptions，支持兼容模式下删除多个匹配项
 *
 * v2.3 (2026-01) - 三方交叉审查综合修复
 *   [CRITICAL] subscribe/subscribeOnce/subscribeGlobal 根据 EventBus 返回值条件记账，修复幽灵订阅问题
 *   [CRITICAL] subscribeSingle 移除旧订阅时正确递减 eventNameRefCount
 *   [FIX] __onEventBusOnceFired 更新签名以接收 scope 参数，匹配 EventBus v2.3 的调用方式
 *   [FIX] unsubscribe 调用 EventBus.unsubscribe 时传递 scope 参数
 *
 * v2.2 (2026-01) - 三方交叉审查综合修复
 *   [CRITICAL] subscribeOnce 传递 this 作为 owner，实现 __onEventBusOnceFired 回调清理订阅记录
 *   [PERF] unsubscribe 使用 eventNameRefCount 引用计数替代 O(n²) 扫描
 *   [FIX] 修复一次性订阅触发后 subscriptions 数组泄漏问题
 *
 * v2.1 (2026-01) - 三方交叉审查修复
 *   [CRITICAL] publish/publishGlobal 改用参数展开直接调用，避免 apply + combineArgs 的性能损耗
 *   [PERF] destroy 简化为 O(n)，移除不必要的 uniqueEventNames 维护逻辑
 *
 * 特性：
 * 1. **非单例**：可创建多个独立实例，每个实例独立维护自己的事件订阅。
 * 2. **事件隔离**：通过附加唯一 ID 到事件名称，确保多个实例的事件不互相干扰。
 * 3. **轻量级封装**：底层事件处理由 EventBus 完成，此类仅提供业务级接口。
 * 4. **可控销毁**：destroy 方法仅移除本实例订阅的事件，保证资源的合理释放。
 * 5. **业务友好**：使用简单的 subscribe、unsubscribe、publish、subscribeOnce 接口满足基本事件需求。
 * 6. **全局广播支持**：提供 subscribeGlobal、unsubscribeGlobal、publishGlobal 方法，实现跨实例事件广播。
 * 7. **单一订阅支持**：提供 subscribeSingle 和 subscribeSingleGlobal 方法，确保每个事件仅有一个订阅者。
 *
 * 契约说明:
 *   - 回调执行顺序不保证（继承自 EventBus 的 for..in 枚举特性）
 *   - 调用方需确保 callback 和 scope 的有效性
 */
class org.flashNight.neur.Event.EventDispatcher {
    // -----------------------
    //  静态成员
    // -----------------------

    /** 所有实例共享同一个 EventBus (全局单例) */
    private static var bus:EventBus = EventBus.getInstance();

    /** 静态计数器，用于生成唯一实例 ID */
    private static var instanceCounter:Number = 0;

    // -----------------------
    //  实例成员
    // -----------------------

    /** 存储当前实例所有订阅信息 { eventName:String, callback:Function, isGlobal?:Boolean, isOnce?:Boolean } */
    private var subscriptions:Array;

    /** 缓存 eventName 到 uniqueEventName 的映射 */
    private var uniqueEventNames:Object;

    /** [v2.2] 事件名引用计数，用于 O(1) 判断是否可以删除 uniqueEventNames 缓存 */
    private var eventNameRefCount:Object;

    /** 当前实例的唯一 ID，用于事件名称隔离 */
    private var instanceID:String;

    /** 标志是否已销毁，避免重复销毁 */
    private var _isDestroyed:Boolean;

    /**
     * 构造函数：创建一个新的 EventDispatcher 实例。
     * 每个实例都有独立的订阅列表，方便在销毁时统一清理。
     * 通过附加唯一的实例 ID 实现事件名称的隔离。
     */
    public function EventDispatcher() {
        this.subscriptions = [];
        this.uniqueEventNames = {};
        this.eventNameRefCount = {};  // [v2.2] 初始化引用计数
        this.instanceID = ":" + (EventDispatcher.instanceCounter++);
        this._isDestroyed = false;
    }

    /**
     * 订阅特定事件，当事件触发时执行回调函数。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     *
     * [v2.3 CRITICAL] 根据 EventBus.subscribe 返回值条件记账，避免幽灵订阅
     *
     * @param eventName 要订阅的事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     * @return Boolean 是否成功订阅（false 表示重复订阅被忽略）
     */
    public function subscribe(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribe called on a destroyed EventDispatcher.");
            return false;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
            this.eventNameRefCount[eventName] = 0;  // [v2.2] 初始化引用计数
        }

        // [v2.3 CRITICAL] 只有 EventBus 成功订阅时才记账
        if (!EventDispatcher.bus.subscribe(uniqueEventName, callback, scope)) {
            return false;
        }

        // [v2.2] 增加引用计数
        this.eventNameRefCount[eventName]++;

        this.subscriptions.push({
            eventName: uniqueEventName,
            callback: callback,
            scope: scope  // [v2.3] 记录 scope 用于精确退订
        });
        return true;
    }

    /**
     * 一次性订阅事件，事件触发一次后自动取消订阅。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     *
     * [v2.3 CRITICAL] 根据 EventBus.subscribeOnce 返回值条件记账
     * [v2.2 CRITICAL] 传递 this 作为 owner，使 EventBus 在触发后回调 __onEventBusOnceFired
     *                 自动清理 subscriptions 数组中的记录，修复内存泄漏
     *
     * @param eventName 要订阅的事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     * @return Boolean 是否成功订阅（false 表示重复订阅被忽略）
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribeOnce called on a destroyed EventDispatcher.");
            return false;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
            this.eventNameRefCount[eventName] = 0;  // [v2.2] 初始化引用计数
        }

        // [v2.3 CRITICAL] 只有 EventBus 成功订阅时才记账
        // [v2.2 CRITICAL] 传递 this 作为 owner，触发后会调用 __onEventBusOnceFired
        if (!EventDispatcher.bus.subscribeOnce(uniqueEventName, callback, scope, this)) {
            return false;
        }

        // [v2.2] 增加引用计数
        this.eventNameRefCount[eventName]++;

        this.subscriptions.push({
            eventName: uniqueEventName,
            callback: callback,
            scope: scope,     // [v2.3] 记录 scope 用于精确退订
            isOnce: true      // [v2.2] 标记为一次性订阅
        });
        return true;
    }

    /**
     * [v2.3] EventBus 一次性回调触发后的通知方法
     * 由 EventBus.subscribeOnce 的包装器在执行后调用，用于清理 subscriptions 数组
     *
     * [v2.3 FIX] 更新签名以接收 scope 参数，匹配 EventBus v2.3 的调用方式
     *
     * @param uniqueEventName 触发的唯一事件名称（包含实例ID后缀）
     * @param callback 触发的回调函数
     * @param scope [v2.3] 回调函数的作用域
     */
    public function __onEventBusOnceFired(uniqueEventName:String, callback:Function, scope:Object):Void {
        if (this._isDestroyed) {
            return;
        }

        // 从 subscriptions 数组中移除对应的记录
        // [v2.3] 需要同时匹配 callback 和 scope
        var len:Number = this.subscriptions.length;
        for (var i:Number = 0; i < len; i++) {
            var sub:Object = this.subscriptions[i];
            if (sub.eventName == uniqueEventName && sub.callback == callback && sub.scope === scope) {
                this.subscriptions.splice(i, 1);

                // [v2.2] 递减引用计数
                // 从 uniqueEventName 反推 eventName（移除实例ID后缀）
                var eventName:String = uniqueEventName.substring(0, uniqueEventName.length - this.instanceID.length);
                if (--this.eventNameRefCount[eventName] == 0) {
                    delete this.uniqueEventNames[eventName];
                    delete this.eventNameRefCount[eventName];
                }
                return;
            }
        }
    }

    /**
     * 取消某个事件的订阅。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     *
     * [v2.3.2 FIX] scope 为 undefined 时使用兼容模式，删除该 callback 的所有订阅
     * [v2.3 FIX] 添加可选 scope 参数，传递给 EventBus.unsubscribe 进行精确匹配
     * [v2.2 PERF] 使用 eventNameRefCount 引用计数替代 O(n²) 扫描
     *
     * @param eventName 要取消的事件名
     * @param callback 对应的回调函数
     * @param scope [v2.3] 可选，回调函数的作用域。不传时删除该 callback 的所有订阅
     * @return Boolean 是否成功退订
     */
    public function unsubscribe(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: unsubscribe called on a destroyed EventDispatcher.");
            return false;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            return false;
        }

        // [v2.3] 传递 scope 进行精确退订（EventBus 会处理兼容模式）
        EventDispatcher.bus.unsubscribe(uniqueEventName, callback, scope);

        var removed:Boolean = false;
        // [v2.3.2 FIX] 从后往前遍历，支持在循环中删除元素
        for (var i:Number = this.subscriptions.length - 1; i >= 0; i--) {
            var sub:Object = this.subscriptions[i];
            // [v2.3.2 FIX] scope === undefined 时匹配任意 scope（兼容模式）
            if (sub.eventName == uniqueEventName && sub.callback == callback &&
                (scope === undefined || sub.scope === scope)) {
                this.subscriptions.splice(i, 1);

                // [v2.2 PERF] 使用引用计数 O(1) 替代 O(n) 扫描
                if (--this.eventNameRefCount[eventName] == 0) {
                    delete this.uniqueEventNames[eventName];
                    delete this.eventNameRefCount[eventName];
                }
                removed = true;

                // [v2.3.2] 精确匹配模式只删除一个；兼容模式继续删除所有
                if (scope !== undefined) break;
            }
        }
        return removed;
    }

    /**
     * 发布事件，通知订阅该事件的所有回调函数执行。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     *
     * [v2.1 CRITICAL] 使用参数展开直接调用 EventBus.publish，避免 apply + combineArgs 的性能损耗
     * 这是性能关键路径，内联展开是刻意的设计决策，牺牲可维护性换取极致性能
     *
     * @param eventName 事件名称
     * @param ...args 发布事件时传递的可选参数列表
     */
    public function publish(eventName:String):Void {
        if (this._isDestroyed) {
            trace("Warning: publish called on a destroyed EventDispatcher.");
            return;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名（静默返回）
        if (eventName == null || eventName == "") {
            return;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
        }

        var bus:EventBus = EventDispatcher.bus;
        var len:Number = arguments.length;

        // [v2.1 CRITICAL] 参数展开直接调用，避免 apply + combineArgs 的开销
        // 这是性能关键路径，展开是刻意为之
        if (len == 1) {
            bus.publish(uniqueEventName);
        } else if (len == 2) {
            bus.publish(uniqueEventName, arguments[1]);
        } else if (len == 3) {
            bus.publish(uniqueEventName, arguments[1], arguments[2]);
        } else if (len == 4) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3]);
        } else if (len == 5) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4]);
        } else if (len == 6) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5]);
        } else if (len == 7) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6]);
        } else if (len == 8) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7]);
        } else if (len == 9) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8]);
        } else if (len == 10) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9]);
        } else {
            // 超过 10 个参数时退化为 apply（极少数情况）
            bus.publish.apply(bus, ArgumentsUtil.combineArgs([uniqueEventName], arguments, 1));
        }
    }

    /**
     * 全局订阅特定事件，跨所有 EventDispatcher 实例。
     * 不附加实例 ID，实现全局事件隔离。
     *
     * [v2.3 CRITICAL] 根据 EventBus.subscribe 返回值条件记账
     *
     * @param eventName 要订阅的全局事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     * @return Boolean 是否成功订阅
     */
    public function subscribeGlobal(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribeGlobal called on a destroyed EventDispatcher.");
            return false;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        // [v2.3 CRITICAL] 只有 EventBus 成功订阅时才记账
        if (!EventDispatcher.bus.subscribe(eventName, callback, scope)) {
            return false;
        }

        this.subscriptions.push({
            eventName: eventName,
            callback: callback,
            scope: scope,  // [v2.3] 记录 scope
            isGlobal: true
        });
        return true;
    }

    /**
     * 取消全局事件的订阅。
     *
     * [v2.3 FIX] 添加可选 scope 参数，传递给 EventBus.unsubscribe 进行精确匹配
     *
     * @param eventName 要取消的全局事件名称
     * @param callback 对应的回调函数
     * @param scope [v2.3] 可选，回调函数的作用域
     * @return Boolean 是否成功退订
     */
    public function unsubscribeGlobal(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: unsubscribeGlobal called on a destroyed EventDispatcher.");
            return false;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        // [v2.3] 传递 scope 进行精确退订（EventBus 会处理兼容模式）
        EventDispatcher.bus.unsubscribe(eventName, callback, scope);

        var removed:Boolean = false;
        // [v2.3.2 FIX] 从后往前遍历，支持在循环中删除元素
        for (var i:Number = this.subscriptions.length - 1; i >= 0; i--) {
            var sub:Object = this.subscriptions[i];
            // [v2.3.2 FIX] scope === undefined 时匹配任意 scope（兼容模式）
            if (sub.eventName == eventName && sub.callback == callback && sub.isGlobal &&
                (scope === undefined || sub.scope === scope)) {
                this.subscriptions.splice(i, 1);
                removed = true;

                // [v2.3.2] 精确匹配模式只删除一个；兼容模式继续删除所有
                if (scope !== undefined) break;
            }
        }
        return removed;
    }

    /**
     * 发布全局事件，通知所有订阅该事件的回调函数执行。
     * 不附加实例 ID，实现全局事件隔离。
     *
     * [v2.1 CRITICAL] 使用参数展开直接调用，避免 apply + combineArgs 的性能损耗
     *
     * @param eventName 全局事件名称
     * @param ...args 发布事件时传递的可选参数列表
     */
    public function publishGlobal(eventName:String):Void {
        if (this._isDestroyed) {
            trace("Warning: publishGlobal called on a destroyed EventDispatcher.");
            return;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名（静默返回）
        if (eventName == null || eventName == "") {
            return;
        }

        var bus:EventBus = EventDispatcher.bus;
        var len:Number = arguments.length;

        // [v2.1 CRITICAL] 参数展开直接调用
        if (len == 1) {
            bus.publish(eventName);
        } else if (len == 2) {
            bus.publish(eventName, arguments[1]);
        } else if (len == 3) {
            bus.publish(eventName, arguments[1], arguments[2]);
        } else if (len == 4) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3]);
        } else if (len == 5) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4]);
        } else if (len == 6) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5]);
        } else if (len == 7) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6]);
        } else if (len == 8) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7]);
        } else if (len == 9) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8]);
        } else if (len == 10) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9]);
        } else {
            bus.publish.apply(bus, ArgumentsUtil.combineArgs([eventName], arguments, 1));
        }
    }

    /**
     * 单一订阅方法，确保每个事件只有一个订阅者。
     * 如果事件已被订阅，则取消之前的订阅并添加新的订阅。
     *
     * [v2.3 CRITICAL] 移除旧订阅时正确递减 eventNameRefCount
     * [v2.3 CRITICAL] 根据 EventBus.subscribe 返回值条件记账
     *
     * @param eventName 要订阅的事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     * @return Boolean 是否成功订阅
     */
    public function subscribeSingle(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribeSingle called on a destroyed EventDispatcher.");
            return false;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName != undefined) {
            // 查找并移除已存在的订阅
            for (var i:Number = 0; i < this.subscriptions.length; i++) {
                var sub:Object = this.subscriptions[i];
                if (sub.eventName == uniqueEventName && !sub.isGlobal) {
                    // [v2.3] 传递 scope 进行精确退订
                    EventDispatcher.bus.unsubscribe(uniqueEventName, sub.callback, sub.scope);
                    this.subscriptions.splice(i, 1);
                    // [v2.3 CRITICAL] 递减引用计数
                    this.eventNameRefCount[eventName]--;
                    break;
                }
            }
        } else {
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
            this.eventNameRefCount[eventName] = 0;  // [v2.3] 初始化引用计数
        }

        // [v2.3 CRITICAL] 只有 EventBus 成功订阅时才记账
        if (!EventDispatcher.bus.subscribe(uniqueEventName, callback, scope)) {
            // 如果订阅失败且引用计数为0，清理映射
            if (this.eventNameRefCount[eventName] == 0) {
                delete this.uniqueEventNames[eventName];
                delete this.eventNameRefCount[eventName];
            }
            return false;
        }

        // [v2.3] 增加引用计数
        this.eventNameRefCount[eventName]++;

        this.subscriptions.push({
            eventName: uniqueEventName,
            callback: callback,
            scope: scope  // [v2.3] 记录 scope
        });
        return true;
    }

    /**
     * 全局单一订阅方法，确保每个全局事件只有一个订阅者。
     * 如果全局事件已被订阅，则取消之前的订阅并添加新的订阅。
     *
     * [v2.3 CRITICAL] 根据 EventBus.subscribe 返回值条件记账
     *
     * @param eventName 要订阅的全局事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     * @return Boolean 是否成功订阅
     */
    public function subscribeSingleGlobal(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribeSingleGlobal called on a destroyed EventDispatcher.");
            return false;
        }

        // [v2.3.2] 参数验证：拒绝空字符串事件名
        if (eventName == null || eventName == "") {
            return false;
        }

        // 查找并移除已存在的全局订阅
        for (var i:Number = 0; i < this.subscriptions.length; i++) {
            var sub:Object = this.subscriptions[i];
            if (sub.eventName == eventName && sub.isGlobal) {
                // [v2.3] 传递 scope 进行精确退订
                EventDispatcher.bus.unsubscribe(eventName, sub.callback, sub.scope);
                this.subscriptions.splice(i, 1);
                break;
            }
        }

        // [v2.3 CRITICAL] 只有 EventBus 成功订阅时才记账
        if (!EventDispatcher.bus.subscribe(eventName, callback, scope)) {
            return false;
        }

        this.subscriptions.push({
            eventName: eventName,
            callback: callback,
            scope: scope,  // [v2.3] 记录 scope
            isGlobal: true
        });
        return true;
    }

    /**
     * 销毁当前 EventDispatcher 实例，取消所有由此实例订阅的事件。
     * 此操作仅影响本实例创建的订阅，不会影响全局 EventBus 或其他实例的订阅。
     *
     * [v2.3 FIX] 传递 scope 进行精确退订
     * [v2.1 PERF] 简化为 O(n)，destroy 时不需要维护 uniqueEventNames 的干净性
     * 整个实例都要销毁，清理 uniqueEventNames 缓存没有意义
     */
    public function destroy():Void {
        if (this._isDestroyed) {
            return;
        }
        this._isDestroyed = true;

        var len:Number = this.subscriptions.length;
        if (len == 0) {
            this.subscriptions = null;
            this.uniqueEventNames = null;
            this.eventNameRefCount = null;  // [v2.2]
            return;
        }

        // [v2.1 PERF] 简化为单层循环 O(n)，直接退订所有
        // destroy 时不需要检查"是否还有其他订阅使用该 eventName"
        // 因为整个实例都要销毁，uniqueEventNames 缓存也会被清空
        for (var i:Number = 0; i < len; i++) {
            var sub:Object = this.subscriptions[i];
            // [v2.3] 传递 scope 进行精确退订
            EventDispatcher.bus.unsubscribe(sub.eventName, sub.callback, sub.scope);
        }

        // 直接清空，无需逐个检查
        this.subscriptions = null;
        this.uniqueEventNames = null;
        this.eventNameRefCount = null;  // [v2.2]
    }
}
