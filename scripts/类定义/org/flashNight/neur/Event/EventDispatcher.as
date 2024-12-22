import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;

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
 */
class org.flashNight.neur.Event.EventDispatcher {
    private static var instanceCounter:Number = 0; // 静态计数器，用于生成唯一实例 ID
    
    private var bus:EventBus;          // 引用全局 EventBus 实例
    private var subscriptions:Array;   // 存储当前实例所有订阅信息 { eventName:String, callback:Function }
    private var instanceID:String;     // 当前实例的唯一 ID，用于事件名称隔离
    
    /**
     * 构造函数：创建一个新的 EventDispatcher 实例。
     * 每个实例都有独立的订阅列表，方便在销毁时统一清理。
     * 通过附加唯一的实例 ID 实现事件名称的隔离。
     */
    public function EventDispatcher() {
        this.bus = EventBus.getInstance(); // 获取全局的 EventBus 实例
        this.subscriptions = [];           // 初始化订阅记录数组
        this.instanceID = String(":" + EventDispatcher.instanceCounter++); // 分配唯一的实例 ID
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
        // 将事件名称附加上唯一的实例 ID，确保事件隔离
        var uniqueEventName:String = eventName + this.instanceID;
        
        // 通过 EventBus 订阅事件
        this.bus.subscribe(uniqueEventName, callback, scope);
        
        // 记录订阅信息，用于销毁时清理
        this.subscriptions.push({eventName: uniqueEventName, callback: callback});
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
        // 将事件名称附加上唯一的实例 ID，确保事件隔离
        var uniqueEventName:String = eventName + this.instanceID;
        
        // 通过 EventBus 一次性订阅事件
        this.bus.subscribeOnce(uniqueEventName, callback, scope);
        
        // 记录订阅信息，用于销毁时清理
        // 虽然 subscribeOnce 内部在事件触发后自动取消，但为安全起见，仍记录订阅。
        // 在 destroy 时尝试二次清除不会有副作用，只是无效操作。
        this.subscriptions.push({eventName: uniqueEventName, callback: callback});
    }
    
    /**
     * 取消某个事件的订阅。
     * 自动为事件名称附加实例 ID，实现事件隔离。
     * 
     * @param eventName 要取消的事件名
     * @param callback 对应的回调函数
     */
    public function unsubscribe(eventName:String, callback:Function):Void {
        // 将事件名称附加上唯一的实例 ID，确保事件隔离
        var uniqueEventName:String = eventName + this.instanceID;
        
        // 通过 EventBus 取消订阅
        this.bus.unsubscribe(uniqueEventName, callback);
        
        // 从本实例的订阅记录中移除指定事件和回调对应的记录
        var len:Number = this.subscriptions.length;
        for (var i:Number = 0; i < len; i++) {
            var sub:Object = this.subscriptions[i];
            if (sub.eventName == uniqueEventName && sub.callback == callback) {
                // 从数组中移除该订阅记录
                this.subscriptions.splice(i, 1);
                return; // 退出循环，一般一个事件只对应一个回调
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
        // 将事件名称附加上唯一的实例 ID，确保事件隔离
        var uniqueEventName:String = eventName + this.instanceID;
        
        // 利用 Array 构造函数将 arguments 转为数组，并从索引 1 开始裁剪
        var slicedArgs:Array = Array.prototype.slice.call(arguments, 1);
        
        // 使用 apply 传递所有参数，包括 uniqueEventName 和 slicedArgs
        this.bus.publish.apply(this.bus, [uniqueEventName].concat(slicedArgs));
    }

    
    /**
     * 销毁当前 EventDispatcher 实例，取消所有由此实例订阅的事件。
     * 此操作仅影响本实例创建的订阅，不会影响全局 EventBus 或其他实例。
     */
    public function destroy():Void {
        var len:Number = this.subscriptions.length;
        for (var i:Number = 0; i < len; i++) {
            var sub:Object = this.subscriptions[i];
            // 再次尝试取消订阅，如果已自动取消则不会产生问题
            this.bus.unsubscribe(sub.eventName, sub.callback);
        }
        // 清空订阅列表
        this.subscriptions = [];
    }
}
