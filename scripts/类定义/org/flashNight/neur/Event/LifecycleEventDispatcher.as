/**
 * LifecycleEventDispatcher.as
 * 
 * 继承自 EventDispatcher，组合 EventCoordinator 的生命周期管理能力。
 * 当传入的 MovieClip 触发 onUnload 时，会自动执行 destroy() 方法，释放相关资源。
 */

import org.flashNight.neur.Event.*;
import org.flashNight.aven.Coordinator.*;

class org.flashNight.neur.Event.LifecycleEventDispatcher extends EventDispatcher {
    
    private var _target:MovieClip;                     // 需要托管生命周期的影片剪辑
    private var _unloadHandlerID:String;               // 记录 onUnload 回调的唯一 ID
    private var _destroyed:Boolean;                    // 标记是否已销毁
    
    /**
     * 构造函数
     * @param target 要被托管生命周期的 MovieClip
     */
    public function LifecycleEventDispatcher(target:MovieClip) {
        super();
        this._target = target;
        this._destroyed = false;
        
        // 通过 EventCoordinator 添加 onUnload 回调
        _unloadHandlerID = EventCoordinator.addUnloadCallback(
            target, 
            Delegate.create(this, onTargetUnload)
        );
    }
    
    /**
     * 当 target 触发 onUnload 时自动调用
     */
    private function onTargetUnload():Void {
        // 调用 destroy() 做相应清理
        this.destroy();
    }
    
    /**
     * 手动销毁接口，如果需要在卸载前显式销毁，也可以在此处调用
     */
    public function destroy():Void {
        if (_destroyed) return; // 避免重复销毁
        _destroyed = true;
        // _root.发布消息("[LifecycleEventDispatcher] Destroyed successfully.");
        // 1. 先移除本类对 target onUnload 的监听
        //    避免残留回调（如果 target 不再使用了）
        EventCoordinator.removeEventListener(_target, "onUnload", _unloadHandlerID);

        // 2. 若需要一并清除 target 自身的所有事件监听器，可在此调用
        EventCoordinator.clearEventListeners(_target);
        
        // 3. 释放对 target 的引用（并试图释放 target 对自身的引用），防止内存泄漏
        if(this._target.dispatcher === this) this._target.dispatcher = null;
        this._target = null;
        
        // 4. 调用父类的销毁逻辑
        super.destroy();
        
        trace("[LifecycleEventDispatcher] Destroyed successfully.");
    }
    
    /**
     * 是否已销毁
     */
    public function isDestroyed():Boolean {
        return _destroyed;
    }
    
    // -----------------------------------------------------------------
    // 对 target 上的事件进行封装
    // -----------------------------------------------------------------
    
    /**
     * 在 target 上添加事件监听器（可选桥接方法）
     * @param eventName 目标事件，例如 "onPress", "onRelease", etc.
     * @param callback  回调函数
     * @param scope     回调作用域
     * @return 监听器 ID
     */
    public function subscribeTargetEvent(eventName:String, callback:Function, scope:Object):String {
        // 使用 EventCoordinator 来为 target 绑定事件
        return EventCoordinator.addEventListener(
            this._target, 
            eventName, 
            Delegate.create(scope, callback)
        );
    }
    
    /**
     * 移除 target 上的事件监听器
     * @param eventName 事件名称
     * @param handlerID 监听器 ID
     */
    public function unsubscribeTargetEvent(eventName:String, handlerID:String):Void {
        EventCoordinator.removeEventListener(this._target, eventName, handlerID);
    }
    
    /**
     * 暂时禁用/启用 target 上的事件监听器
     * @param enable true=启用, false=禁用
     */
    public function enableTargetEvents(enable:Boolean):Void {
        EventCoordinator.enableEventListeners(this._target, enable);
    }
}
