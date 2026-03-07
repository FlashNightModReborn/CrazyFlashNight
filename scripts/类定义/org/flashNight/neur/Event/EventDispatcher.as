import org.flashNight.neur.Event.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.gesh.arguments.*;

/**
 * EventDispatcher 类为业务逻辑提供一个轻量级的事件分发接口。
 * 它内部通过 EventBus 来实现具体的事件订阅与发布功能，
 * 通过为事件名称附加唯一的实例 ID 实现多实例的事件隔离。
 *
 * 版本历史:
 * v3.0 (2026-03) - 性能重构
 *   [PERF] 新增 publish0/publish1/publish2 特化方法，完全消除 arguments 开销
 *     直接调用 EventBus.publish0/publish1/publish2，双层零 arguments
 *     H09: arguments.length=1538ns, arguments读取=1306ns
 *   [PERF] subscriptions 的删除操作从 splice(4231ns) 改为 swap-and-pop(O(1))
 *     H20: 热路径禁止 splice
 *   [COMPAT] 原有 publish/publishGlobal 保持不变，作为可变参数 fallback
 *   [COMPAT] 所有公共 API 签名不变
 *
 * v2.3.3 (2026-01) - 性能对齐
 *   [PERF] publish/publishGlobal 参数展开从 10 扩展到 15
 *
 * v2.3.2 (2026-01) - 兼容性修复 + 参数验证
 *   [CRITICAL] 所有公共方法拒绝 null/空字符串 eventName
 *   [FIX] unsubscribe/unsubscribeGlobal scope 为 undefined 时使用兼容模式
 *
 * v2.3 (2026-01) - 三方交叉审查综合修复
 *   [CRITICAL] subscribe/subscribeOnce/subscribeGlobal 根据 EventBus 返回值条件记账
 *   [CRITICAL] subscribeSingle 移除旧订阅时正确递减 eventNameRefCount
 *
 * 特性：
 * 1. 非单例，可创建多个独立实例
 * 2. 事件隔离（附加唯一 ID）
 * 3. 轻量级封装
 * 4. 可控销毁
 * 5. 全局广播支持
 * 6. 单一订阅支持
 *
 * 契约说明:
 *   - 回调执行顺序不保证（继承自 EventBus）
 *   - 调用方需确保 callback 和 scope 的有效性
 */
class org.flashNight.neur.Event.EventDispatcher {

    /** 所有实例共享同一个 EventBus */
    private static var bus:EventBus = EventBus.getInstance();

    /** 静态计数器，用于生成唯一实例 ID */
    private static var instanceCounter:Number = 0;

    /**
     * [v3.0] 订阅记录并行数组（替代原 Object[] subscriptions）
     * 使用 SoA 布局，删除时 swap-and-pop
     */
    private var _subEvents:Array;     // uniqueEventName
    private var _subCallbacks:Array;  // callback
    private var _subScopes:Array;     // scope
    private var _subFlags:Array;      // 位标志: bit0=isGlobal, bit1=isOnce
    private var _subCount:Number;

    /** 缓存 eventName → uniqueEventName 的映射 */
    private var uniqueEventNames:Object;

    /** 事件名引用计数 */
    private var eventNameRefCount:Object;

    /** 当前实例的唯一 ID */
    private var instanceID:String;

    /** 标志是否已销毁 */
    private var _isDestroyed:Boolean;

    // 位标志常量
    private static var FLAG_GLOBAL:Number = 1;
    private static var FLAG_ONCE:Number = 2;

    public function EventDispatcher() {
        this._subEvents = [];
        this._subCallbacks = [];
        this._subScopes = [];
        this._subFlags = [];
        this._subCount = 0;
        this.uniqueEventNames = {};
        this.eventNameRefCount = {};
        this.instanceID = ":" + (EventDispatcher.instanceCounter++);
        this._isDestroyed = false;
    }

    /**
     * 订阅特定事件。
     */
    public function subscribe(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribe called on a destroyed EventDispatcher.");
            return false;
        }

        if (eventName == null || eventName == "") {
            return false;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
            this.eventNameRefCount[eventName] = 0;
        }

        if (!EventDispatcher.bus.subscribe(uniqueEventName, callback, scope)) {
            return false;
        }

        this.eventNameRefCount[eventName]++;

        var idx:Number = this._subCount;
        this._subEvents[idx] = uniqueEventName;
        this._subCallbacks[idx] = callback;
        this._subScopes[idx] = scope;
        this._subFlags[idx] = 0;
        this._subCount = idx + 1;
        return true;
    }

    /**
     * 一次性订阅事件。
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribeOnce called on a destroyed EventDispatcher.");
            return false;
        }

        if (eventName == null || eventName == "") {
            return false;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
            this.eventNameRefCount[eventName] = 0;
        }

        if (!EventDispatcher.bus.subscribeOnce(uniqueEventName, callback, scope, this)) {
            return false;
        }

        this.eventNameRefCount[eventName]++;

        var idx:Number = this._subCount;
        this._subEvents[idx] = uniqueEventName;
        this._subCallbacks[idx] = callback;
        this._subScopes[idx] = scope;
        this._subFlags[idx] = FLAG_ONCE;
        this._subCount = idx + 1;
        return true;
    }

    /**
     * EventBus 一次性回调触发后的通知方法。
     * [v3.0] 使用 swap-and-pop 删除
     */
    public function __onEventBusOnceFired(uniqueEventName:String, callback:Function, scope:Object):Void {
        if (this._isDestroyed) {
            return;
        }

        var evts:Array = this._subEvents;
        var cbs:Array = this._subCallbacks;
        var scs:Array = this._subScopes;
        var flgs:Array = this._subFlags;
        var cnt:Number = this._subCount;

        for (var i:Number = 0; i < cnt; i++) {
            if (evts[i] == uniqueEventName && cbs[i] == callback && scs[i] === scope) {
                // swap-and-pop
                var last:Number = cnt - 1;
                if (i != last) {
                    evts[i] = evts[last];
                    cbs[i] = cbs[last];
                    scs[i] = scs[last];
                    flgs[i] = flgs[last];
                }
                evts[last] = null;
                cbs[last] = null;
                scs[last] = null;
                this._subCount = last;

                // 递减引用计数
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
     * 取消订阅。
     * [v3.0] 使用 swap-and-pop 删除
     */
    public function unsubscribe(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: unsubscribe called on a destroyed EventDispatcher.");
            return false;
        }

        if (eventName == null || eventName == "") {
            return false;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            return false;
        }

        EventDispatcher.bus.unsubscribe(uniqueEventName, callback, scope);

        var evts:Array = this._subEvents;
        var cbs:Array = this._subCallbacks;
        var scs:Array = this._subScopes;
        var flgs:Array = this._subFlags;
        var removed:Boolean = false;

        // [v3.0] swap-and-pop 删除
        // 从后往前遍历，确保 swap-and-pop 安全
        for (var i:Number = this._subCount - 1; i >= 0; i--) {
            if (evts[i] == uniqueEventName && cbs[i] == callback &&
                (scope === undefined || scs[i] === scope)) {

                var last:Number = this._subCount - 1;
                if (i != last) {
                    evts[i] = evts[last];
                    cbs[i] = cbs[last];
                    scs[i] = scs[last];
                    flgs[i] = flgs[last];
                }
                evts[last] = null;
                cbs[last] = null;
                scs[last] = null;
                this._subCount = last;

                if (--this.eventNameRefCount[eventName] == 0) {
                    delete this.uniqueEventNames[eventName];
                    delete this.eventNameRefCount[eventName];
                }
                removed = true;

                if (scope !== undefined) break;
            }
        }
        return removed;
    }

    /**
     * [v3.0] 零参数特化发布。完全不触碰 arguments。
     */
    public function publish0(eventName:String):Void {
        if (this._isDestroyed) {
            return;
        }
        if (eventName == null || eventName == "") {
            return;
        }
        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
        }
        EventDispatcher.bus.publish0(uniqueEventName);
    }

    /**
     * [v3.0] 单参数特化发布。
     */
    public function publish1(eventName:String, a1):Void {
        if (this._isDestroyed) {
            return;
        }
        if (eventName == null || eventName == "") {
            return;
        }
        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
        }
        EventDispatcher.bus.publish1(uniqueEventName, a1);
    }

    /**
     * [v3.0] 双参数特化发布。
     */
    public function publish2(eventName:String, a1, a2):Void {
        if (this._isDestroyed) {
            return;
        }
        if (eventName == null || eventName == "") {
            return;
        }
        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
        }
        EventDispatcher.bus.publish2(uniqueEventName, a1, a2);
    }

    /**
     * 发布事件（通用版本，可变参数 fallback）。
     */
    public function publish(eventName:String):Void {
        if (this._isDestroyed) {
            trace("Warning: publish called on a destroyed EventDispatcher.");
            return;
        }

        if (eventName == null || eventName == "") {
            return;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
        }

        var bus:EventBus = EventDispatcher.bus;
        var len:Number = arguments.length;

        if (len == 1) {
            bus.publish0(uniqueEventName);
        } else if (len == 2) {
            bus.publish1(uniqueEventName, arguments[1]);
        } else if (len == 3) {
            bus.publish2(uniqueEventName, arguments[1], arguments[2]);
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
        } else if (len == 11) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10]);
        } else if (len == 12) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11]);
        } else if (len == 13) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12]);
        } else if (len == 14) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13]);
        } else if (len == 15) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14]);
        } else if (len == 16) {
            bus.publish(uniqueEventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15]);
        } else {
            bus.publish.apply(bus, ArgumentsUtil.combineArgs([uniqueEventName], arguments, 1));
        }
    }

    /**
     * 全局订阅。
     */
    public function subscribeGlobal(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribeGlobal called on a destroyed EventDispatcher.");
            return false;
        }

        if (eventName == null || eventName == "") {
            return false;
        }

        if (!EventDispatcher.bus.subscribe(eventName, callback, scope)) {
            return false;
        }

        var idx:Number = this._subCount;
        this._subEvents[idx] = eventName;
        this._subCallbacks[idx] = callback;
        this._subScopes[idx] = scope;
        this._subFlags[idx] = FLAG_GLOBAL;
        this._subCount = idx + 1;
        return true;
    }

    /**
     * 取消全局订阅。
     * [v3.0] 使用 swap-and-pop
     */
    public function unsubscribeGlobal(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: unsubscribeGlobal called on a destroyed EventDispatcher.");
            return false;
        }

        if (eventName == null || eventName == "") {
            return false;
        }

        EventDispatcher.bus.unsubscribe(eventName, callback, scope);

        var evts:Array = this._subEvents;
        var cbs:Array = this._subCallbacks;
        var scs:Array = this._subScopes;
        var flgs:Array = this._subFlags;
        var removed:Boolean = false;

        for (var i:Number = this._subCount - 1; i >= 0; i--) {
            if (evts[i] == eventName && cbs[i] == callback && (flgs[i] & FLAG_GLOBAL) &&
                (scope === undefined || scs[i] === scope)) {

                var last:Number = this._subCount - 1;
                if (i != last) {
                    evts[i] = evts[last];
                    cbs[i] = cbs[last];
                    scs[i] = scs[last];
                    flgs[i] = flgs[last];
                }
                evts[last] = null;
                cbs[last] = null;
                scs[last] = null;
                this._subCount = last;

                removed = true;
                if (scope !== undefined) break;
            }
        }
        return removed;
    }

    /**
     * 发布全局事件。
     */
    public function publishGlobal(eventName:String):Void {
        if (this._isDestroyed) {
            trace("Warning: publishGlobal called on a destroyed EventDispatcher.");
            return;
        }

        if (eventName == null || eventName == "") {
            return;
        }

        var bus:EventBus = EventDispatcher.bus;
        var len:Number = arguments.length;

        if (len == 1) {
            bus.publish0(eventName);
        } else if (len == 2) {
            bus.publish1(eventName, arguments[1]);
        } else if (len == 3) {
            bus.publish2(eventName, arguments[1], arguments[2]);
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
        } else if (len == 11) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10]);
        } else if (len == 12) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11]);
        } else if (len == 13) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12]);
        } else if (len == 14) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13]);
        } else if (len == 15) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14]);
        } else if (len == 16) {
            bus.publish(eventName, arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15]);
        } else {
            bus.publish.apply(bus, ArgumentsUtil.combineArgs([eventName], arguments, 1));
        }
    }

    /**
     * [v3.0] 零参数全局发布。
     */
    public function publishGlobal0(eventName:String):Void {
        if (this._isDestroyed) {
            return;
        }
        if (eventName == null || eventName == "") {
            return;
        }
        EventDispatcher.bus.publish0(eventName);
    }

    /**
     * [v3.0] 单参数全局发布。
     */
    public function publishGlobal1(eventName:String, a1):Void {
        if (this._isDestroyed) {
            return;
        }
        if (eventName == null || eventName == "") {
            return;
        }
        EventDispatcher.bus.publish1(eventName, a1);
    }

    /**
     * [v3.0] 双参数全局发布。
     */
    public function publishGlobal2(eventName:String, a1, a2):Void {
        if (this._isDestroyed) {
            return;
        }
        if (eventName == null || eventName == "") {
            return;
        }
        EventDispatcher.bus.publish2(eventName, a1, a2);
    }

    /**
     * 单一订阅方法，确保每个事件只有一个订阅者。
     * [v3.0] 使用 swap-and-pop 删除旧订阅
     */
    public function subscribeSingle(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribeSingle called on a destroyed EventDispatcher.");
            return false;
        }

        if (eventName == null || eventName == "") {
            return false;
        }

        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName != undefined) {
            // 查找并移除已存在的订阅
            var evts:Array = this._subEvents;
            var cbs:Array = this._subCallbacks;
            var scs:Array = this._subScopes;
            var flgs:Array = this._subFlags;

            for (var i:Number = 0; i < this._subCount; i++) {
                if (evts[i] == uniqueEventName && !(flgs[i] & FLAG_GLOBAL)) {
                    EventDispatcher.bus.unsubscribe(uniqueEventName, cbs[i], scs[i]);

                    // swap-and-pop
                    var last:Number = this._subCount - 1;
                    if (i != last) {
                        evts[i] = evts[last];
                        cbs[i] = cbs[last];
                        scs[i] = scs[last];
                        flgs[i] = flgs[last];
                    }
                    evts[last] = null;
                    cbs[last] = null;
                    scs[last] = null;
                    this._subCount = last;

                    this.eventNameRefCount[eventName]--;
                    break;
                }
            }
        } else {
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
            this.eventNameRefCount[eventName] = 0;
        }

        if (!EventDispatcher.bus.subscribe(uniqueEventName, callback, scope)) {
            if (this.eventNameRefCount[eventName] == 0) {
                delete this.uniqueEventNames[eventName];
                delete this.eventNameRefCount[eventName];
            }
            return false;
        }

        this.eventNameRefCount[eventName]++;

        var idx:Number = this._subCount;
        this._subEvents[idx] = uniqueEventName;
        this._subCallbacks[idx] = callback;
        this._subScopes[idx] = scope;
        this._subFlags[idx] = 0;
        this._subCount = idx + 1;
        return true;
    }

    /**
     * 全局单一订阅。
     * [v3.0] 使用 swap-and-pop
     */
    public function subscribeSingleGlobal(eventName:String, callback:Function, scope:Object):Boolean {
        if (this._isDestroyed) {
            trace("Warning: subscribeSingleGlobal called on a destroyed EventDispatcher.");
            return false;
        }

        if (eventName == null || eventName == "") {
            return false;
        }

        // 查找并移除已存在的全局订阅
        var evts:Array = this._subEvents;
        var cbs:Array = this._subCallbacks;
        var scs:Array = this._subScopes;
        var flgs:Array = this._subFlags;

        for (var i:Number = 0; i < this._subCount; i++) {
            if (evts[i] == eventName && (flgs[i] & FLAG_GLOBAL)) {
                EventDispatcher.bus.unsubscribe(eventName, cbs[i], scs[i]);

                var last:Number = this._subCount - 1;
                if (i != last) {
                    evts[i] = evts[last];
                    cbs[i] = cbs[last];
                    scs[i] = scs[last];
                    flgs[i] = flgs[last];
                }
                evts[last] = null;
                cbs[last] = null;
                scs[last] = null;
                this._subCount = last;
                break;
            }
        }

        if (!EventDispatcher.bus.subscribe(eventName, callback, scope)) {
            return false;
        }

        var idx:Number = this._subCount;
        this._subEvents[idx] = eventName;
        this._subCallbacks[idx] = callback;
        this._subScopes[idx] = scope;
        this._subFlags[idx] = FLAG_GLOBAL;
        this._subCount = idx + 1;
        return true;
    }

    /**
     * 销毁当前 EventDispatcher 实例。
     */
    public function destroy():Void {
        if (this._isDestroyed) {
            return;
        }
        this._isDestroyed = true;

        var cnt:Number = this._subCount;
        if (cnt == 0) {
            this._subEvents = null;
            this._subCallbacks = null;
            this._subScopes = null;
            this._subFlags = null;
            this.uniqueEventNames = null;
            this.eventNameRefCount = null;
            return;
        }

        var evts:Array = this._subEvents;
        var cbs:Array = this._subCallbacks;
        var scs:Array = this._subScopes;

        for (var i:Number = 0; i < cnt; i++) {
            EventDispatcher.bus.unsubscribe(evts[i], cbs[i], scs[i]);
        }

        this._subEvents = null;
        this._subCallbacks = null;
        this._subScopes = null;
        this._subFlags = null;
        this._subCount = 0;
        this.uniqueEventNames = null;
        this.eventNameRefCount = null;
    }
}
