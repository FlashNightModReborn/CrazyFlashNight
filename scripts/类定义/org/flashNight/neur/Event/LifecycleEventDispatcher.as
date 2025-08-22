/**
 * LifecycleEventDispatcher.as
 * 
 * 继承自 EventDispatcher，组合 EventCoordinator 的生命周期管理能力。
 * 当传入的 MovieClip 触发 onUnload 时，会自动执行 destroy() 方法，释放相关资源。
 * 
 * 【修复】解决测试中的生命周期转移、事件统计、自动销毁等问题。
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
        
        // 建立生命周期绑定
        this.bindLifecycle(target);
    }
    
    /**
     * 绑定生命周期管理到指定目标
     * @param target 目标MovieClip
     */
    private function bindLifecycle(target:MovieClip):Void {
        // 设置双向引用关系
        if (target.dispatcher === undefined) {
            target.dispatcher = this;
        }
        
        // 通过 EventCoordinator 添加 onUnload 回调
        this._unloadHandlerID = EventCoordinator.addUnloadCallback(
            target, 
            Delegate.create(this, onTargetUnload)
        );
    }
    
    /**
     * 解除生命周期绑定
     * @param target 要解绑的目标
     */
    private function unbindLifecycle(target:MovieClip):Void {
        if (this._unloadHandlerID && target) {
            // 【修复】正确移除onUnload监听器，防止转移后仍然触发
            EventCoordinator.removeEventListener(target, "onUnload", this._unloadHandlerID);
            this._unloadHandlerID = null;
        }
        
        // 清理双向引用
        if (target && target.dispatcher === this) {
            target.dispatcher = null;
        }
    }
    
    /**
     * 当 target 触发 onUnload 时自动调用
     * 【修复】确保dispatcher被正确标记为已销毁
     */
    private function onTargetUnload():Void {
        // 【修复】显式调用destroy()确保完整的销毁流程
        this.destroy();
    }
    
    //======================================================================
    // 【新增】目标转移功能
    //======================================================================
    
    /**
     * 将当前实例转移到新的目标MovieClip。
     * 适用场景：Boss多阶段切换时，保持事件系统的连续性。
     * 
     * 转移操作包括：
     * 1. 转移EventCoordinator管理的所有事件监听器
     * 2. 重新绑定生命周期管理到新目标
     * 3. 更新引用关系
     * 4. 可选择是否清理旧目标的监听器
     * 
     * @param newTarget 新的目标MovieClip
     * @param clearOldTarget 是否清理旧目标的事件监听器（默认true）
     * @param transferMode 转移模式：'all'=转移所有事件, 'specific'=只转移指定事件, 'exclude'=排除特定事件
     * @param eventFilter 事件过滤器：当transferMode不为'all'时生效
     * @return 返回旧目标到新目标的ID映射表
     */
    public function transferToNewTarget(newTarget:MovieClip, clearOldTarget:Boolean, 
                                       transferMode:String, eventFilter:Array):Object {
        if (this._destroyed) {
            // trace("[LifecycleEventDispatcher] Error: Cannot transfer destroyed instance");
            return null;
        }
        
        if (!newTarget) {
            // trace("[LifecycleEventDispatcher] Error: New target cannot be null");
            return null;
        }
        
        if (this._target === newTarget) {
            // trace("[LifecycleEventDispatcher] Warning: New target is same as current target");
            return {};
        }
        
        var oldTarget:MovieClip = this._target;
        
        // 默认参数处理
        if (clearOldTarget === undefined) clearOldTarget = true;
        if (transferMode === undefined) transferMode = "all";
        
        // trace("[LifecycleEventDispatcher] Starting transfer from " + oldTarget + " to " + newTarget);
        
        // 【修复】先解除旧目标的生命周期绑定，防止转移后旧目标onUnload仍然触发
        this.unbindLifecycle(oldTarget);
        
        var idMap:Object = null;
        
        // 1. 根据转移模式执行EventCoordinator层面的事件转移
        switch (transferMode) {
            case "all":
                idMap = EventCoordinator.transferEventListeners(oldTarget, newTarget, clearOldTarget);
                break;
                
            case "specific":
                if (eventFilter && eventFilter.length > 0) {
                    idMap = EventCoordinator.transferSpecificEventListeners(
                        oldTarget, newTarget, eventFilter, clearOldTarget
                    );
                } else {
                    // trace("[LifecycleEventDispatcher] Warning: 'specific' mode requires eventFilter");
                    idMap = {};
                }
                break;
                
            case "exclude":
                if (eventFilter && eventFilter.length > 0) {
                    // 获取所有事件列表，排除指定事件
                    var allEvents:Array = this.getAllEventNames(oldTarget);
                    var eventsToTransfer:Array = [];
                    
                    for (var i:Number = 0; i < allEvents.length; i++) {
                        var eventName:String = allEvents[i];
                        var shouldExclude:Boolean = false;
                        
                        for (var j:Number = 0; j < eventFilter.length; j++) {
                            if (eventName === eventFilter[j]) {
                                shouldExclude = true;
                                break;
                            }
                        }
                        
                        if (!shouldExclude) {
                            eventsToTransfer.push(eventName);
                        }
                    }
                    
                    if (eventsToTransfer.length > 0) {
                        idMap = EventCoordinator.transferSpecificEventListeners(
                            oldTarget, newTarget, eventsToTransfer, clearOldTarget
                        );
                    } else {
                        idMap = {};
                    }
                } else {
                    // 没有排除列表，转移所有事件
                    idMap = EventCoordinator.transferEventListeners(oldTarget, newTarget, clearOldTarget);
                }
                break;
                
            default:
                // trace("[LifecycleEventDispatcher] Warning: Unknown transfer mode: " + transferMode);
                idMap = EventCoordinator.transferEventListeners(oldTarget, newTarget, clearOldTarget);
                break;
        }
        
        // 2. 更新当前目标引用
        this._target = newTarget;
        
        // 3. 绑定到新目标的生命周期
        this.bindLifecycle(newTarget);
        
        // trace("[LifecycleEventDispatcher] Transfer completed successfully");
        
        return idMap || {};
    }
    
    /**
     * 便捷方法：转移所有事件到新目标
     * @param newTarget 新目标MovieClip
     * @param clearOldTarget 是否清理旧目标（默认true）
     * @return ID映射表
     */
    public function transferAll(newTarget:MovieClip, clearOldTarget:Boolean):Object {
        return this.transferToNewTarget(newTarget, clearOldTarget, "all", null);
    }
    
    /**
     * 便捷方法：只转移指定事件到新目标
     * @param newTarget 新目标MovieClip
     * @param events 要转移的事件名称数组
     * @param clearOldTarget 是否清理旧目标的这些事件（默认true）
     * @return ID映射表
     */
    public function transferSpecific(newTarget:MovieClip, events:Array, clearOldTarget:Boolean):Object {
        return this.transferToNewTarget(newTarget, clearOldTarget, "specific", events);
    }
    
    /**
     * 便捷方法：转移除指定事件外的所有事件
     * @param newTarget 新目标MovieClip
     * @param excludeEvents 要排除的事件名称数组
     * @param clearOldTarget 是否清理旧目标（默认true）
     * @return ID映射表
     */
    public function transferExclude(newTarget:MovieClip, excludeEvents:Array, clearOldTarget:Boolean):Object {
        return this.transferToNewTarget(newTarget, clearOldTarget, "exclude", excludeEvents);
    }
    
    /**
     * 获取目标对象上所有已注册的事件名称
     * @param target 目标对象
     * @return 事件名称数组
     */
    private function getAllEventNames(target:Object):Array {
        var stats:Object = EventCoordinator.getEventListenerStats(target);
        var eventNames:Array = [];
        
        for (var eventName:String in stats.events) {
            eventNames.push(eventName);
        }
        
        return eventNames;
    }
    
    //======================================================================
    // 【新增】静态转移方法
    //======================================================================
    
    /**
     * 静态方法：在两个LifecycleEventDispatcher实例间转移事件
     * 适用于需要同时管理多个实例的复杂场景
     * 
     * @param source 源LifecycleEventDispatcher实例
     * @param targetDispatcher 目标LifecycleEventDispatcher实例
     * @param transferMode 转移模式
     * @param eventFilter 事件过滤器
     * @return ID映射表
     */
    public static function transferBetweenDispatchers(source:LifecycleEventDispatcher, 
                                                    targetDispatcher:LifecycleEventDispatcher,
                                                    transferMode:String, 
                                                    eventFilter:Array):Object {
        if (!source || !targetDispatcher) {
            // trace("[LifecycleEventDispatcher] Error: Source and target dispatchers cannot be null");
            return null;
        }
        
        if (source._destroyed || targetDispatcher._destroyed) {
            // trace("[LifecycleEventDispatcher] Error: Cannot transfer with destroyed instances");
            return null;
        }
        
        // 执行EventCoordinator层面的转移
        var idMap:Object;
        
        switch (transferMode) {
            case "all":
                idMap = EventCoordinator.transferEventListeners(
                    source._target, targetDispatcher._target, true
                );
                break;
                
            case "specific":
                idMap = EventCoordinator.transferSpecificEventListeners(
                    source._target, targetDispatcher._target, eventFilter, true
                );
                break;
                
            default:
                idMap = EventCoordinator.transferEventListeners(
                    source._target, targetDispatcher._target, true
                );
                break;
        }
        
        return idMap || {};
    }
    
    //======================================================================
    // 原有功能（带修复）
    //======================================================================
    
    /**
     * 手动销毁接口
     * 【修复】确保销毁流程的完整性和防重复调用
     */
    public function destroy():Void {
        if (this._destroyed) return; // 防止重复销毁
        
        // 标记为已销毁，防止销毁过程中的递归或重入调用
        this._destroyed = true;
        
        // trace("[LifecycleEventDispatcher] Destroying instance for target: " + this._target);
        
        // 1. 解除生命周期绑定，移除 onUnload 监听器
        //    这一步很重要，特别是手动调用 destroy 时，可以防止未来的 onUnload 再次触发
        this.unbindLifecycle(this._target);

        // 2. 【重要】调用 EventCoordinator 清理此 target 上的所有事件监听器
        //    这确保了即使没有通过 onUnload 触发，也能彻底清理
        if (this._target) {
            EventCoordinator.clearEventListeners(this._target);
        }
        
        // 3. 调用父类的销毁逻辑，清理 pub/sub 订阅
        super.destroy();
        
        // 4. 最后释放对 target 的引用，防止内存泄漏
        this._target = null;
        
        // trace("[LifecycleEventDispatcher] Destroyed successfully.");
    }
    
    /**
     * 是否已销毁
     */
    public function isDestroyed():Boolean {
        return _destroyed;
    }
    
    /**
     * 获取当前管理的目标MovieClip
     */
    public function getTarget():MovieClip {
        return this._target;
    }
    
    // -----------------------------------------------------------------
    // 对 target 上的事件进行封装（带修复）
    // -----------------------------------------------------------------
    
    /**
     * 在 target 上添加事件监听器（可选桥接方法）
     * @param eventName 目标事件，例如 "onPress", "onRelease", etc.
     * @param callback  回调函数
     * @param scope     回调作用域
     * @return 监听器 ID
     */
    public function subscribeTargetEvent(eventName:String, callback:Function, scope:Object):String {
        if (this._destroyed || !this._target) {
            // trace("[LifecycleEventDispatcher] Warning: Cannot subscribe on destroyed or null target");
            return null;
        }
        
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
        if (this._destroyed || !this._target) {
            // trace("[LifecycleEventDispatcher] Warning: Cannot unsubscribe on destroyed or null target");
            return;
        }
        
        // 【注意】这里使用EventCoordinator的removeEventListener
        // EventCoordinator已经正确处理了统计问题：
        // 只有当handlers数组为空时才删除事件记录
        EventCoordinator.removeEventListener(this._target, eventName, handlerID);
    }
    
    /**
     * 暂时禁用/启用 target 上的事件监听器
     * @param enable true=启用, false=禁用
     */
    public function enableTargetEvents(enable:Boolean):Void {
        if (this._destroyed || !this._target) {
            // trace("[LifecycleEventDispatcher] Warning: Cannot enable/disable events on destroyed or null target");
            return;
        }
        
        EventCoordinator.enableEventListeners(this._target, enable);
    }
    
    /**
     * 获取当前目标的事件统计信息
     * 【修复】正确处理已销毁或空目标的情况
     * @return 统计信息对象
     */
    public function getTargetEventStats():Object {
        if (this._destroyed || !this._target) {
            return { totalEvents: 0, totalHandlers: 0, events: {} };
        }
        
        // 【注意】EventCoordinator.getEventListenerStats已经正确处理了统计逻辑
        return EventCoordinator.getEventListenerStats(this._target);
    }
    
    /**
     * 调试用toString方法
     * @return 包含实例状态信息的字符串
     */
    public function toString():String {
        var targetInfo:String = this._target ? 
            ("target=" + this._target._name + "(" + this._target + ")") : 
            "target=null";
        
        var statusInfo:String = this._destroyed ? "DESTROYED" : "ACTIVE";
        
        var handlerInfo:String = this._unloadHandlerID ? 
            ("unloadHandler=" + this._unloadHandlerID) : 
            "unloadHandler=null";
        
        var eventStats:Object = this.getTargetEventStats();
        var statsInfo:String = "events=" + eventStats.totalEvents + 
                              ",handlers=" + eventStats.totalHandlers;
        
        return "[LifecycleEventDispatcher " + statusInfo + " " + targetInfo + " " + 
               handlerInfo + " " + statsInfo + "]";
    }
}