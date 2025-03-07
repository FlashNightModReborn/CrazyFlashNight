import org.flashNight.neur.Event.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.gesh.arguments.*;

/**
 * EventDispatcher 类为业务逻辑提供一个轻量级的事件分发接口。
 * 它内部通过 EventBus 来实现具体的事件订阅与发布功能，
 * 通过为事件名称附加唯一的实例 ID 实现多实例的事件隔离。
 * 
 * 特性：
 * 1. **非单例**：可创建多个独立实例，每个实例独立维护自己的事件订阅。
 * 2. **事件隔离**：通过附加唯一 ID 到事件名称，确保多个实例的事件不互相干扰。
 * 3. **轻量级封装**：底层事件处理由 EventBus 完成，此类仅提供业务级接口。
 * 4. **可控销毁**：destroy 方法仅移除本实例订阅的事件，保证资源的合理释放。
 * 5. **业务友好**：使用简单的 subscribe、unsubscribe、publish、subscribeOnce 接口满足基本事件需求。
 * 6. **全局广播支持**：提供 subscribeGlobal、unsubscribeGlobal、publishGlobal 方法，实现跨实例事件广播。
 * 7. **单一订阅支持**：提供 subscribeSingle 和 subscribeSingleGlobal 方法，确保每个事件仅有一个订阅者。
 */
class org.flashNight.neur.Event.EventDispatcher {
    // -----------------------
    //  静态成员
    // -----------------------
    
    // 所有实例共享同一个 EventBus (全局单例)
    private static var bus:EventBus = EventBus.getInstance();
    
    // 静态计数器，用于生成唯一实例 ID
    private static var instanceCounter:Number = 0;
    
    // -----------------------
    //  实例成员
    // -----------------------
    
    private var subscriptions:Array;         // 存储当前实例所有订阅信息 { eventName:String, callback:Function, isGlobal?:Boolean }
    private var uniqueEventNames:Object;     // 缓存 eventName 到 uniqueEventName 的映射
    private var instanceID:String;           // 当前实例的唯一 ID，用于事件名称隔离
    private var _isDestroyed:Boolean;        // 标志是否已销毁，避免重复销毁

    /**
     * 构造函数：创建一个新的 EventDispatcher 实例。
     * 每个实例都有独立的订阅列表，方便在销毁时统一清理。
     * 通过附加唯一的实例 ID 实现事件名称的隔离。
     */
    public function EventDispatcher() {
        this.subscriptions = [];   
        this.uniqueEventNames = {};         // 初始化唯一事件名称缓存
        this.instanceID = ":" + (EventDispatcher.instanceCounter++);
        this._isDestroyed = false;
    }
    
    /**
     * 订阅特定事件，当事件触发时执行回调函数。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     * 
     * @param eventName 要订阅的事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     */
    public function subscribe(eventName:String, callback:Function, scope:Object):Void {
        if (this._isDestroyed) {
            trace("Warning: subscribe called on a destroyed EventDispatcher.");
            return;
        }
        
        // 检查是否已缓存 uniqueEventName
        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
        }
        
        EventDispatcher.bus.subscribe(uniqueEventName, callback, scope);
        
        this.subscriptions.push({
            eventName: uniqueEventName,
            callback: callback
        });
    }
    
    /**
     * 一次性订阅事件，事件触发一次后自动取消订阅。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     * 
     * @param eventName 要订阅的事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object):Void {
        if (this._isDestroyed) {
            trace("Warning: subscribeOnce called on a destroyed EventDispatcher.");
            return;
        }
        
        // 检查是否已缓存 uniqueEventName
        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
        }
        
        EventDispatcher.bus.subscribeOnce(uniqueEventName, callback, scope);
        
        // 记录到 subscriptions
        this.subscriptions.push({
            eventName: uniqueEventName,
            callback: callback
        });
    }
    
    /**
     * 取消某个事件的订阅。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     * 
     * @param eventName 要取消的事件名
     * @param callback 对应的回调函数
     */
    public function unsubscribe(eventName:String, callback:Function):Void {
        if (this._isDestroyed) {
            trace("Warning: unsubscribe called on a destroyed EventDispatcher.");
            return;
        }
        
        // 获取 cached uniqueEventName
        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            // 事件从未被订阅过，无需退订
            return;
        }
        
        // 通过静态 bus 取消订阅
        EventDispatcher.bus.unsubscribe(uniqueEventName, callback);
        
        // 从本实例的订阅记录中移除
        var len:Number = this.subscriptions.length;
        for (var i:Number = 0; i < len; i++) {
            var sub:Object = this.subscriptions[i];
            if (sub.eventName == uniqueEventName && sub.callback == callback) {
                this.subscriptions.splice(i, 1);
                // 如果没有其他订阅使用该 uniqueEventName，移除缓存
                var stillSubscribed:Boolean = false;
                for (var j:Number = 0; j < this.subscriptions.length; j++) {
                    if (this.subscriptions[j].eventName == uniqueEventName) {
                        stillSubscribed = true;
                        break;
                    }
                }
                if (!stillSubscribed) {
                    delete this.uniqueEventNames[eventName];
                }
                return;
            }
        }
    }
    
    /**
     * 发布事件，通知订阅该事件的所有回调函数执行。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     * 
     * @param eventName 事件名称
     * @param ...args 发布事件时传递的可选参数列表
     */
    public function publish(eventName:String):Void {
        if (this._isDestroyed) {
            trace("Warning: publish called on a destroyed EventDispatcher.");
            return;
        }
        
        // 获取 cached uniqueEventName
        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName == undefined) {
            // 如果事件从未被订阅过，本地事件可能没人监听，但仍需发布
            uniqueEventName = eventName + this.instanceID;
        }

        var bus:EventBus = EventDispatcher.bus;
        
        // 使用 apply 传递参数
        bus.publish.apply(bus, ArgumentsUtil.combineArgs([uniqueEventName], arguments, 1));
    }
    
    /**
     * 全局订阅特定事件，跨所有 EventDispatcher 实例。
     * 不附加实例 ID，实现全局事件隔离。
     * 
     * @param eventName 要订阅的全局事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     */
    public function subscribeGlobal(eventName:String, callback:Function, scope:Object):Void {
        if (this._isDestroyed) {
            trace("Warning: subscribeGlobal called on a destroyed EventDispatcher.");
            return;
        }
        
        EventDispatcher.bus.subscribe(eventName, callback, scope);
        
        // 标记 isGlobal 以便在 destroy() 时区分
        this.subscriptions.push({
            eventName: eventName,
            callback: callback,
            isGlobal: true
        });
    }
    
    /**
     * 取消全局事件的订阅。
     * 
     * @param eventName 要取消的全局事件名称
     * @param callback 对应的回调函数
     */
    public function unsubscribeGlobal(eventName:String, callback:Function):Void {
        if (this._isDestroyed) {
            trace("Warning: unsubscribeGlobal called on a destroyed EventDispatcher.");
            return;
        }
        
        EventDispatcher.bus.unsubscribe(eventName, callback);
        
        // 从本实例的订阅记录中移除
        var len:Number = this.subscriptions.length;
        for (var i:Number = 0; i < len; i++) {
            var sub:Object = this.subscriptions[i];
            if (sub.eventName == eventName && sub.callback == callback && sub.isGlobal) {
                this.subscriptions.splice(i, 1);
                return;
            }
        }
    }
    
    /**
     * 发布全局事件，通知所有订阅该事件的回调函数执行。
     * 不附加实例 ID，实现全局事件隔离。
     * 
     * @param eventName 全局事件名称
     * @param ...args 发布事件时传递的可选参数列表
     */
    public function publishGlobal(eventName:String):Void {
        if (this._isDestroyed) {
            trace("Warning: publishGlobal called on a destroyed EventDispatcher.");
            return;
        }
        var bus:EventBus = EventDispatcher.bus;
        
        // 使用 apply 传递参数
        bus.publish.apply(bus, ArgumentsUtil.combineArgs([eventName], arguments, 1));
    }
    
    /**
     * 单一订阅方法，确保每个事件只有一个订阅者。
     * 如果事件已被订阅，则取消之前的订阅并添加新的订阅。
     * 
     * @param eventName 要订阅的事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     */
    public function subscribeSingle(eventName:String, callback:Function, scope:Object):Void {
        if (this._isDestroyed) {
            trace("Warning: subscribeSingle called on a destroyed EventDispatcher.");
            return;
        }
        
        // 检查是否已有该事件的订阅
        var uniqueEventName:String = this.uniqueEventNames[eventName];
        if (uniqueEventName != undefined) {
            // 找到现有的订阅并取消
            var existingCallback:Function = null;
            for (var i:Number = 0; i < this.subscriptions.length; i++) {
                var sub:Object = this.subscriptions[i];
                if (sub.eventName == uniqueEventName && !sub.isGlobal) {
                    existingCallback = sub.callback;
                    // 取消订阅
                    EventDispatcher.bus.unsubscribe(uniqueEventName, existingCallback);
                    // 移除订阅记录
                    this.subscriptions.splice(i, 1);
                    break;
                }
            }
        } else {
            // 如果没有缓存的 uniqueEventName，则生成一个
            uniqueEventName = eventName + this.instanceID;
            this.uniqueEventNames[eventName] = uniqueEventName;
        }
        
        // 添加新的订阅
        EventDispatcher.bus.subscribe(uniqueEventName, callback, scope);
        
        // 记录新的订阅
        this.subscriptions.push({
            eventName: uniqueEventName,
            callback: callback
        });
    }
    
    /**
     * 全局单一订阅方法，确保每个全局事件只有一个订阅者。
     * 如果全局事件已被订阅，则取消之前的订阅并添加新的订阅。
     * 
     * @param eventName 要订阅的全局事件名称
     * @param callback 回调函数
     * @param scope 回调函数执行时的作用域 (this)
     */
    public function subscribeSingleGlobal(eventName:String, callback:Function, scope:Object):Void {
        if (this._isDestroyed) {
            trace("Warning: subscribeSingleGlobal called on a destroyed EventDispatcher.");
            return;
        }
        
        // 查找当前实例中是否已经有该全局事件的订阅
        var existingCallback:Function = null;
        for (var i:Number = 0; i < this.subscriptions.length; i++) {
            var sub:Object = this.subscriptions[i];
            if (sub.eventName == eventName && sub.isGlobal) {
                existingCallback = sub.callback;
                // 取消现有的全局订阅
                EventDispatcher.bus.unsubscribe(eventName, existingCallback);
                // 移除订阅记录
                this.subscriptions.splice(i, 1);
                break;
            }
        }
        
        // 添加新的全局订阅
        EventDispatcher.bus.subscribe(eventName, callback, scope);
        
        // 记录新的全局订阅
        this.subscriptions.push({
            eventName: eventName,
            callback: callback,
            isGlobal: true
        });
    }
    
    /**
     * 销毁当前 EventDispatcher 实例，取消所有由此实例订阅的事件。
     * 此操作仅影响本实例创建的订阅，不会影响全局 EventBus 或其他实例的订阅。
     */
    public function destroy():Void {
        if (this._isDestroyed) {
            return; // 避免重复销毁
        }
        this._isDestroyed = true;
        
        var len:Number = this.subscriptions.length;
        // 如果没有任何订阅，直接返回
        if (len == 0) {
            this.subscriptions = null;
            this.uniqueEventNames = null;
            return;
        }
        
        // 逐个退订
        for (var i:Number = 0; i < len; i++) {
            var sub:Object = this.subscriptions[i];
            if (sub.isGlobal == true) {
                EventDispatcher.bus.unsubscribe(sub.eventName, sub.callback);
            } else {
                EventDispatcher.bus.unsubscribe(sub.eventName, sub.callback);
                
                // 从 uniqueEventNames 缓存中移除
                // 需要找到原 eventName by removing instanceID
                var originalEventName:String = sub.eventName.substring(0, sub.eventName.indexOf(this.instanceID));
                // Check if any other subscriptions use this eventName
                var stillSubscribed:Boolean = false;
                for (var j:Number = 0; j < this.subscriptions.length; j++) {
                    if (this.subscriptions[j].eventName == sub.eventName && this.subscriptions[j].callback != sub.callback) {
                        stillSubscribed = true;
                        break;
                    }
                }
                if (!stillSubscribed) {
                    delete this.uniqueEventNames[originalEventName];
                }
            }
        }
        
        // 清空订阅列表和缓存
        this.subscriptions = null;
        this.uniqueEventNames = null;
    }
}
