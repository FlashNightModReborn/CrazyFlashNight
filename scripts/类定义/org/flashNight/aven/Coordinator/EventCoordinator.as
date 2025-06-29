﻿/**
 * EventCoordinator.as
 * 全局事件协调器类，用于统一管理对象的事件监听器。
 *
 * 优化点：
 * 1. 修复 `onUnload` 重复调用的问题，确保用户自定义的卸载逻辑能够多次执行。
 * 2. 动态生成快捷方法，减少重复代码开销，提高代码可维护性。
 * 3. 提供事件监听器的启用/禁用功能，增强灵活性。
 * 4. 自动清理非 `onUnload` 事件的监听器，避免内存泄漏。
 * 5. 使用唯一标识符确保与其他库的兼容性，避免命名冲突。
 * 6. 【新增】事件转移功能，支持Boss多阶段切换时的监听器迁移。
 */

class org.flashNight.aven.Coordinator.EventCoordinator {
    
    // 保存所有目标对象的事件处理器信息
    private static var eventHandlers:Object = {};
    
    // 生成唯一 ID 的计数器
    private static var nextID:Number = 0;
    
    //======================================================================
    // 1. 添加事件监听器
    //======================================================================
    /**
     * 添加事件监听器到目标对象。
     * @param target 目标对象。
     * @param eventName 事件名称，如 "onPress"、"onMouseUp" 等。
     * @param handler 事件处理函数，当事件触发时调用。
     * @return 返回该监听器的唯一 ID，用于后续移除监听器。
     */
    public static function addEventListener(target:Object, eventName:String, handler:Function):String {
        // 参数验证：确保目标对象、事件名称和处理函数不为空
        // trace("Attempting to add event: " + eventName + " on target: " + target + " with handler: " + handler);
        if (!target || !eventName || !handler) {
            trace("Invalid parameters detected! target=" + target + ", eventName=" + eventName + ", handler=" + handler);
            return null;
        }

        // 获取目标对象的唯一标识符
        var targetKey:String = getTargetKey(target); 
        var localEventHandlers:Object = eventHandlers;
        var eventHandler:Object = localEventHandlers[targetKey];
        var eventInfo:Object = eventHandler[eventName];
        
        // 如果这是首次绑定该事件，需生成一个新的代理函数来管理自定义监听器
        if (eventInfo == undefined) {

            // 如果该目标对象尚未有事件处理器信息，初始化一个空对象
            if (eventHandler == undefined) {
                eventHandler = localEventHandlers[targetKey] = {}; 
            }

            // 保存目标对象原生的事件处理器（如果有的话）
            // 初始化该事件的处理器信息
            eventInfo = eventHandler[eventName] = {
                original: target[eventName], // 原生事件处理器
                handlers: [],                // 存放自定义事件处理器的数组
                isEnabled: true              // 标记自定义监听器是否启用
            };
            
            /**
             * 替换目标对象的事件处理器为代理函数。
             * 代理函数的职责：
             * - 倒序遍历并执行所有自定义监听器，以减少索引错乱的风险并可能提升高频事件的性能。
             * - 执行完自定义监听器后，再调用原生事件处理器（如果存在）。
             * - 根据 `isEnabled` 标记，决定是否执行自定义监听器。
             */
            target[eventName] = function() {
                var info:Object = eventHandlers[getTargetKey(this)][eventName];

                // 检查自定义监听器是否被禁用
                // 如果没有事件处理器信息，也在直接返回的逻辑中
                if (!info.isEnabled) {
                    if (info.original) {
                        // 如果禁用，则仅执行原生事件处理器
                        info.original.apply(this, arguments); 
                    }
                    return;
                }

                // 倒序遍历所有自定义监听器并执行
                var localHandlers:Array = info.handlers;
                for (var i:Number = localHandlers.length - 1; i >= 0; i--) {
                    localHandlers[i].func.apply(this, arguments);
                }

                // 最后执行原生事件处理器（如果存在）
                if (info.original) {
                    info.original.apply(this, arguments);
                }
            };

            // 让刚才挂载的这个属性变为"不可枚举"
            _global.ASSetPropFlags(target, [eventName], 1, false);

            // 如果事件不是 "onUnload"，则设置自动清理逻辑
            if (eventName != "onUnload") {
                // 确保只为每个目标对象设置一次自动清理标记
                if (!eventHandler.__EC_autoCleanup__) {
                    // 设置自动清理
                    eventHandler.__EC_autoCleanup__ = setupAutomaticCleanup(target); 
                }
            }
        }

        // 添加新的自定义事件处理器
        var handlerID:String = "HID" + (nextID++); // 生成唯一的处理器 ID
        var eih:Array = eventInfo.handlers;
        eih[eih.length] = { id: handlerID, func: handler };

        return handlerID; // 返回处理器的唯一 ID
    }

    //======================================================================
    // 2. 移除事件监听器
    //======================================================================
    /**
     * 移除目标对象的特定事件监听器。
     * @param target 目标对象。
     * @param eventName 事件名称。
     * @param handlerID 监听器的唯一 ID，由 addEventListener 返回。
     */
    public static function removeEventListener(target:Object, eventName:String, handlerID:String):Void {
        // 参数验证：确保目标对象、事件名称和处理器 ID 不为空
        if (!target || !eventName || !handlerID) {
            trace("错误：removeEventListener 参数无效。");
            return;
        }

        // 获取目标对象的唯一标识符
        var eventHandler:Object = eventHandlers[getTargetKey(target)];
        var eventInfo:Object = eventHandler ? eventHandler[eventName] : null;

        // 如果没有该事件的处理器信息，直接返回
        if (!eventInfo) {
            return; 
        }

        // 遍历处理器列表，找到并移除指定 ID 的处理器
        var handlers:Array = eventInfo.handlers;
        for (var i:Number = 0; i < handlers.length; i++) {
            if (handlers[i].id === handlerID) {
                handlers.splice(i, 1); // 移除处理器
                trace("监听器已移除：" + handlerID);
                break;
            }
        }

        // 如果处理器列表为空，则恢复原生事件处理器并清理记录
        if (handlers.length == 0) {
            target[eventName] = eventInfo.original; // 恢复原生事件处理器
            delete eventHandler[eventName]; // 删除该事件的处理器记录
            trace("所有监听器已移除：" + eventName + "，已恢复原生处理器。");
        }
    }

    //======================================================================
    // 3. 清除目标对象的所有事件监听器
    //======================================================================
    /**
     * 清除目标对象的所有事件监听器。
     * @param target 目标对象。
     */
    public static function clearEventListeners(target:Object):Void {
        // 获取目标对象的唯一标识符
        var targetKey:String = getTargetKey(target);
        var eventHandler:Object = eventHandlers[targetKey];
        if (!eventHandler) {
            return; // 如果没有事件处理器信息，直接返回
        }

        // 遍历所有事件，恢复原生处理器
        for (var eventName:String in eventHandler) {
            var eventInfo:Object = eventHandler[eventName];
            if (typeof eventInfo == "object" && eventInfo.handlers) {
                target[eventName] = eventInfo.original; // 恢复原生事件处理器
            }
        }

        // 删除该目标对象的所有事件处理器记录
        delete eventHandlers[targetKey];
        delete target.__EC_autoCleanup__; // 移除自动清理标记
        delete target.__EC_userUnload__;  // 移除用户卸载逻辑标记
        trace("所有事件监听器已清除。");
    }

    //======================================================================
    // 4. 启用或禁用目标对象的全部自定义监听器
    //======================================================================
    /**
     * 启用或禁用目标对象上的全部自定义事件监听器。
     * @param target 目标对象。
     * @param enable 是否启用监听器（true 为启用，false 为禁用）。
     */
    public static function enableEventListeners(target:Object, enable:Boolean):Void {
        var eventHandler:Object = eventHandlers[getTargetKey(target)];

        if (!eventHandler) {
            return; // 如果没有事件处理器信息，直接返回
        }

        // 遍历所有事件，设置启用/禁用状态
        for (var eventName:String in eventHandler) {
            var eventInfo:Object = eventHandler[eventName];
            if (eventInfo && eventInfo.handlers != undefined) {
                eventInfo.isEnabled = enable; // 设置是否启用自定义监听器
            }
        }
        
        // 输出启用/禁用状态
        trace("目标对象的所有自定义事件监听器已 " + (enable ? "启用。" : "禁用。"));
    }

    //======================================================================
    // 5. 【新增】事件转移功能
    //======================================================================
    /**
     * 将旧目标对象的所有自定义事件监听器迁移到新目标对象。
     * 适用场景：Boss多阶段切换时，避免重新绑定所有监听器。
     * 
     * @param oldTarget 旧目标对象（源）。
     * @param newTarget 新目标对象（目标）。
     * @param clearOld 是否清理旧对象的监听器（true=迁移后自动清理，false=保留）。
     * @return 返回旧ID到新ID的映射表 {oldID1:newID1, oldID2:newID2, ...}，
     *         用于后续可能的 removeEventListener 调用。若失败则返回 null。
     */
    public static function transferEventListeners(oldTarget:Object, newTarget:Object, clearOld:Boolean):Object {
        // 参数校验
        if (!oldTarget || !newTarget) {
            trace("transferEventListeners 错误：目标对象不能为空");
            return null;
        }
        
        if (oldTarget === newTarget) {
            trace("transferEventListeners 警告：源对象与目标对象相同，无需转移");
            return {};
        }

        // 获取旧对象的事件处理器信息
        var oldKey:String = getTargetKey(oldTarget);
        var oldEventHandler:Object = eventHandlers[oldKey];
        
        if (!oldEventHandler) {
            trace("transferEventListeners：旧对象无事件监听器，无需转移");
            return {};
        }

        var idMap:Object = {}; // 旧ID → 新ID 的映射表
        var transferCount:Number = 0;

        // 遍历旧对象的所有事件类型
        for (var eventName:String in oldEventHandler) {
            var eventInfo:Object = oldEventHandler[eventName];
            
            // 跳过非事件信息（如 __EC_autoCleanup__ 等标记）
            if (typeof eventInfo != "object" || !eventInfo.handlers) {
                continue;
            }

            var oldHandlers:Array = eventInfo.handlers;
            var wasEnabled:Boolean = eventInfo.isEnabled;
            var handlersLength:Number = oldHandlers.length;

            // 按原顺序迁移所有自定义处理器
            for (var i:Number = 0; i < handlersLength; i++) {
                var handlerRecord:Object = oldHandlers[i];
                var oldID:String = handlerRecord.id;
                var handlerFunc:Function = handlerRecord.func;

                // 在新对象上添加相同的处理器
                var newID:String = addEventListener(newTarget, eventName, handlerFunc);
                
                if (newID) {
                    idMap[oldID] = newID;
                    transferCount++;
                } else {
                    trace("transferEventListeners 警告：无法转移监听器 " + oldID);
                }
            }

            // 同步启用/禁用状态到新对象
            if (!wasEnabled) {
                // 如果旧对象的该事件类型被禁用，则在新对象上也禁用
                var newEventHandler:Object = eventHandlers[getTargetKey(newTarget)];
                if (newEventHandler && newEventHandler[eventName]) {
                    newEventHandler[eventName].isEnabled = false;
                }
            }
        }

        // 可选：清理旧对象的所有监听器
        if (clearOld) {
            clearEventListeners(oldTarget);
            trace("transferEventListeners：已清理旧对象的监听器");
        }

        trace("transferEventListeners 完成：已转移 " + transferCount + " 个监听器");
        return idMap;
    }

    //======================================================================
    // 6. 【新增】批量转移指定事件的监听器
    //======================================================================
    /**
     * 将旧目标对象的指定事件监听器迁移到新目标对象。
     * 提供更精细的控制，只转移特定事件而非全部事件。
     * 
     * @param oldTarget 旧目标对象（源）。
     * @param newTarget 新目标对象（目标）。
     * @param eventNames 要转移的事件名称数组，如 ["onEnterFrame", "onPress"]。
     * @param clearOld 是否清理旧对象上这些事件的监听器。
     * @return 返回旧ID到新ID的映射表。
     */
    public static function transferSpecificEventListeners(oldTarget:Object, newTarget:Object, 
                                                        eventNames:Array, clearOld:Boolean):Object {
        // 参数校验
        if (!oldTarget || !newTarget || !eventNames) {
            trace("transferSpecificEventListeners 错误：参数无效");
            return null;
        }

        if (oldTarget === newTarget) {
            trace("transferSpecificEventListeners 警告：源对象与目标对象相同");
            return {};
        }

        var oldEventHandler:Object = eventHandlers[getTargetKey(oldTarget)];
        if (!oldEventHandler) {
            return {};
        }

        var idMap:Object = {};
        var transferCount:Number = 0;
        var eventNamesLength:Number = eventNames.length;

        // 遍历指定的事件名称
        for (var i:Number = 0; i < eventNamesLength; i++) {
            var eventName:String = eventNames[i];
            var eventInfo:Object = oldEventHandler[eventName];
            
            if (!eventInfo || !eventInfo.handlers) {
                continue; // 该事件无监听器，跳过
            }

            var oldHandlers:Array = eventInfo.handlers;
            var wasEnabled:Boolean = eventInfo.isEnabled;
            var handlersLength:Number = oldHandlers.length;

            // 转移该事件的所有处理器
            for (var j:Number = 0; j < handlersLength; j++) {
                var handlerRecord:Object = oldHandlers[j];
                var newID:String = addEventListener(newTarget, eventName, handlerRecord.func);
                
                if (newID) {
                    idMap[handlerRecord.id] = newID;
                    transferCount++;
                }
            }

            // 同步启用/禁用状态
            if (!wasEnabled) {
                var newEventHandler:Object = eventHandlers[getTargetKey(newTarget)];
                if (newEventHandler && newEventHandler[eventName]) {
                    newEventHandler[eventName].isEnabled = false;
                }
            }

            // 可选：清理旧对象的该事件监听器
            if (clearOld) {
                // 恢复原生处理器
                oldTarget[eventName] = eventInfo.original;
                delete oldEventHandler[eventName];
            }
        }

        trace("transferSpecificEventListeners 完成：已转移 " + transferCount + " 个监听器");
        return idMap;
    }

    //======================================================================
    // 7. 设置 onUnload 自动清理及用户卸载逻辑
    //======================================================================
    /**
     * 设置目标对象的 onUnload 自动清理逻辑，并兼容用户自定义卸载逻辑。
     * 主要步骤：
     * 1. 记录用户原本的 onUnload 函数（如果有）。
     * 2. 替换目标对象的 onUnload 为代理函数，该代理函数负责：
     *    a. 清理所有事件监听器。
     *    b. 还原 onUnload 为用户原本的函数。
     *    c. 调用用户的卸载逻辑。
     * 3. 使用 watch() 监控 onUnload 属性，防止用户代码覆盖代理函数。
     * @param target 目标对象。
     * @return 恒定true，标志操作完成。
     */
    private static function setupAutomaticCleanup(target:Object):Boolean {
        var eventHandler:Object = eventHandlers[getTargetKey(target)];
        // 保存用户的初始卸载函数引用，防止后续清理后无法访问
        var originalUserUnload:Function = eventHandler.__EC_userUnload__;

        // 如果尚未记录用户的 onUnload 函数，则记录初始的用户卸载函数
        if (originalUserUnload == undefined) {
            originalUserUnload = eventHandler.__EC_userUnload__ = target.onUnload;
        }

        /**
         * 替换目标对象的 onUnload 为代理函数。
         * 代理函数逻辑：
         * 1. 获取当前用户的 onUnload 函数。
         * 2. 调用 clearEventListeners() 清理所有事件监听器。
         * 3. 还原 onUnload 为用户的原始卸载函数。
         * 4. 执行用户的卸载逻辑。
         */
        target.onUnload = function() {
            // 获取最新的用户卸载函数（可能已通过 watch() 修改）
            var userUnload:Function = eventHandlers[getTargetKey(this)].__EC_userUnload__ || originalUserUnload;

            // 1. 清理所有事件监听器
            EventCoordinator.clearEventListeners(this);

            // 2. 还原 onUnload 为用户原始卸载函数
            this.onUnload = userUnload;

            // 3. 执行用户卸载逻辑
            if (typeof userUnload == "function") {
                userUnload.apply(this);
            }

            _global.ASSetPropFlags(target, ["onUnload"], 1, false);
            trace("onUnload 已执行并清理所有事件监听器。");
        };

        /**
         * 使用 watch() 监控 onUnload 属性，防止用户代码覆盖代理函数。
         * 当用户尝试修改 onUnload 时，将新的函数保存到 __EC_userUnload__，并阻止覆盖。
         */
        if (typeof target.watch == "function") {
            target.watch("onUnload", function(prop:String, oldVal:Function, newVal:Function):Function {
                var eck:Object = eventHandlers[getTargetKey(this)];
                if (eck != undefined) {
                    // 更新 __EC_userUnload__ 为用户的新卸载函数
                    eck.__EC_userUnload__ = newVal;
                    trace("用户的 onUnload 函数已更新。");
                }
                // 返回旧值，保持代理函数不被覆盖
                return oldVal; 
            });
        }

        trace("自动清理及用户卸载逻辑已设置。");

        // 设置完成
        return true;
    }

    //======================================================================
    // 8. 获取目标对象的唯一标识
    //======================================================================
    /**
     * 获取或生成目标对象的唯一标识。
     * 使用隐藏属性 `__EC_uid__` 来存储唯一标识，防止与其他库冲突。
     * @param target 目标对象。
     * @return 目标对象的唯一标识字符串。
     */
    private static function getTargetKey(target:Object):String {
        var key:String = target.__EC_uid__;
        if (key == undefined) {
            // 生成唯一标识符，并赋值给目标对象的隐藏属性
            key = target.__EC_uid__ = "EC" + (nextID++);
            
            // 使用 ASSetPropFlags 防止 __EC_uid__ 被枚举或删除，增强兼容性
            // 当前环境默认不需要考虑超低版本的flashplayer的支持
            _global.ASSetPropFlags(target, ["__EC_uid__"], 1, false);
        }
        return key;
    }

    //======================================================================
    // 9. 【新增】调试和统计功能
    //======================================================================
    /**
     * 获取目标对象的事件监听器统计信息。
     * @param target 目标对象。
     * @return 包含统计信息的对象。
     */
    public static function getEventListenerStats(target:Object):Object {
        var eventHandler:Object = eventHandlers[getTargetKey(target)];
        if (!eventHandler) {
            return { totalEvents: 0, totalHandlers: 0, events: {} };
        }

        var stats:Object = {
            totalEvents: 0,
            totalHandlers: 0,
            events: {}
        };

        for (var eventName:String in eventHandler) {
            var eventInfo:Object = eventHandler[eventName];
            if (typeof eventInfo == "object" && eventInfo.handlers) {
                var handlerCount:Number = eventInfo.handlers.length;
                stats.events[eventName] = {
                    handlerCount: handlerCount,
                    isEnabled: eventInfo.isEnabled,
                    hasOriginal: (eventInfo.original != undefined)
                };
                stats.totalEvents++;
                stats.totalHandlers += handlerCount;
            }
        }

        return stats;
    }

    /**
     * 列出所有已注册的目标对象及其事件统计。
     * 用于调试和内存监控。
     */
    public static function listAllTargets():Void {
        trace("=== EventCoordinator 全局统计 ===");
        var targetCount:Number = 0;
        var totalHandlers:Number = 0;

        for (var targetKey:String in eventHandlers) {
            var eventHandler:Object = eventHandlers[targetKey];
            var stats:Object = {
                events: 0,
                handlers: 0
            };

            for (var eventName:String in eventHandler) {
                var eventInfo:Object = eventHandler[eventName];
                if (typeof eventInfo == "object" && eventInfo.handlers) {
                    stats.events++;
                    stats.handlers += eventInfo.handlers.length;
                }
            }

            if (stats.events > 0) {
                trace("目标 " + targetKey + ": " + stats.events + " 个事件, " + stats.handlers + " 个处理器");
                targetCount++;
                totalHandlers += stats.handlers;
            }
        }

        trace("总计: " + targetCount + " 个目标对象, " + totalHandlers + " 个监听器");
        trace("================================");
    }

    //======================================================================
    // 10. 快捷方法的优化处理
    //======================================================================
    
    /**
     * 动态生成添加事件处理器的快捷方法。
     * 通过工厂函数 `createCallbackMethod` 创建，避免手动编写多个几乎相同的函数体。
     * @param eventName 事件名称。
     * @return 匿名函数，用于添加指定事件的处理器。
     */
    private static function createCallbackMethod(eventName:String):Function {
        // 返回一个闭包，调用 addEventListener 并绑定特定的事件名称
        return function(target:Object, handler:Function):String {
            return EventCoordinator.addEventListener(target, eventName, handler);
        };
    }

    /**
     * 为常用事件动态创建添加监听器的快捷方法。
     * 这些方法保持原有的接口，确保编译期能够找到对应的方法。
     * 运行期这些方法只是简单的转发，减少了函数调用的开销。
     */
    public static var addUnloadCallback:Function       = createCallbackMethod("onUnload");
    public static var addLoadCallback:Function         = createCallbackMethod("onLoad");
    public static var addEnterFrameCallback:Function   = createCallbackMethod("onEnterFrame");
    public static var addPressCallback:Function        = createCallbackMethod("onPress");
    public static var addReleaseCallback:Function      = createCallbackMethod("onRelease");
    public static var addRollOverCallback:Function     = createCallbackMethod("onRollOver");
    public static var addRollOutCallback:Function      = createCallbackMethod("onRollOut");
    public static var addMouseMoveCallback:Function    = createCallbackMethod("onMouseMove");
    public static var addMouseDownCallback:Function    = createCallbackMethod("onMouseDown");
    public static var addMouseUpCallback:Function      = createCallbackMethod("onMouseUp");
    public static var addKeyDownCallback:Function      = createCallbackMethod("onKeyDown");
    public static var addKeyUpCallback:Function        = createCallbackMethod("onKeyUp");
    public static var addDragOutCallback:Function      = createCallbackMethod("onDragOut");
    public static var addDragOverCallback:Function     = createCallbackMethod("onDragOver");
    public static var addDataCallback:Function         = createCallbackMethod("onData");
    
    // 以上静态变量满足编译期"能找到这些方法"的要求，
    // 运行期的调用只是一层简单转发 -> overhead 非常低
}