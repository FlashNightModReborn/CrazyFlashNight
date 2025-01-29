/**
 * EventCoordinator.as
 * 全局事件协调器类，用于统一管理对象的事件监听器。
 *
 * 优化点：
 * 1. 修复 `onUnload` 重复调用的问题。
 * 2. 动态生成快捷方法，减少重复代码开销。
 * 3. 良好的扩展性，支持事件监听器的启用/禁用和自动清理。
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
     * @param eventName 事件名称。
     * @param handler 事件处理函数。
     * @return 返回该监听器的唯一 ID，用于后续移除。
     */
    public static function addEventListener(target:Object, eventName:String, handler:Function):String {
        if (!target || !eventName || !handler) {
            trace("错误：addEventListener 参数无效。");
            return null;
        }

        var targetKey:String = getTargetKey(target); // 获取目标对象的唯一标识

        if (eventHandlers[targetKey] == undefined) {
            eventHandlers[targetKey] = {}; // 初始化目标对象的事件处理器存储
        }

        // 如果这是首次绑定该事件，生成一个新的代理函数
        if (eventHandlers[targetKey][eventName] == undefined) {
            var originalHandler:Function = target[eventName]; // 保存原生事件处理器

            eventHandlers[targetKey][eventName] = {
                original: originalHandler, // 原生处理器
                handlers: [],             // 自定义处理器列表
                isEnabled: true           // 事件处理器是否启用
            };

            // 替换目标对象的事件处理器为代理函数
            target[eventName] = function() {
                var tKey:String = getTargetKey(this); // 获取当前目标的唯一标识
                var info:Object = eventHandlers[tKey] ? eventHandlers[tKey][eventName] : null;

                if (!info) {
                    return; // 没有事件处理器信息，直接返回
                }

                if (!info.isEnabled) {
                    if (info.original) {
                        info.original.apply(this, arguments); // 如果禁用，仅执行原生处理器
                    }
                    return;
                }

                // 倒序执行所有自定义处理器
                var localHandlers:Array = info.handlers;
                for (var i:Number = localHandlers.length - 1; i >= 0; i--) {
                    localHandlers[i].func.apply(this, arguments);
                }

                // 最后执行原生处理器
                if (info.original) {
                    info.original.apply(this, arguments);
                }
            };

            // 如果不是 onUnload 事件，则设置自动清理（onUnload 事件由专门逻辑处理）
            if (eventName != "onUnload") {
                if (!eventHandlers[targetKey].__EC_autoCleanup__) {
                    eventHandlers[targetKey].__EC_autoCleanup__ = true;
                    setupAutomaticCleanup(target); // 设置自动清理
                }
            }
        }

        // 添加新的自定义处理器
        var infoObj:Object = eventHandlers[targetKey][eventName];
        var handlerID:String = "HID" + (nextID++);
        infoObj.handlers.push({ id: handlerID, func: handler });

        return handlerID;
    }

    //======================================================================
    // 2. 移除事件监听器
    //======================================================================
    /**
     * 移除目标对象的特定事件监听器。
     * @param target 目标对象。
     * @param eventName 事件名称。
     * @param handlerID 监听器的唯一 ID。
     */
    public static function removeEventListener(target:Object, eventName:String, handlerID:String):Void {
        if (!target || !eventName || !handlerID) {
            trace("错误：removeEventListener 参数无效。");
            return;
        }

        var targetKey:String = getTargetKey(target);
        var eventInfo:Object = eventHandlers[targetKey] ? eventHandlers[targetKey][eventName] : null;

        if (!eventInfo) {
            return; // 没有该事件处理器信息，直接返回
        }

        // 遍历处理器列表，移除指定 ID 的处理器
        var handlers:Array = eventInfo.handlers;
        for (var i:Number = 0; i < handlers.length; i++) {
            if (handlers[i].id === handlerID) {
                handlers.splice(i, 1);
                trace("监听器已移除：" + handlerID);
                break;
            }
        }

        // 如果处理器列表为空，恢复原生事件处理器并清理记录
        if (handlers.length == 0) {
            target[eventName] = eventInfo.original;
            delete eventHandlers[targetKey][eventName];
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
        var targetKey:String = getTargetKey(target);
        if (!eventHandlers[targetKey]) {
            return; // 没有事件处理器信息，直接返回
        }

        // 遍历所有事件，恢复原生处理器
        for (var eventName:String in eventHandlers[targetKey]) {
            var eventInfo:Object = eventHandlers[targetKey][eventName];
            if (typeof eventInfo == "object" && eventInfo.handlers) {
                target[eventName] = eventInfo.original; // 恢复原生处理器
            }
        }

        // 清理该目标对象的所有事件处理器记录
        delete eventHandlers[targetKey];
        delete target.__EC_autoCleanup__;
        delete target.__EC_userUnload__;
    }

    //======================================================================
    // 4. 启用或禁用目标对象的全部自定义监听器
    //======================================================================
    /**
     * 启用或禁用目标对象上的全部自定义事件监听器。
     * @param target 目标对象。
     * @param enable 是否启用监听器。
     */
    public static function enableEventListeners(target:Object, enable:Boolean):Void {
        var targetKey:String = getTargetKey(target);
        if (!eventHandlers[targetKey]) {
            return; // 没有事件处理器信息，直接返回
        }

        // 遍历所有事件，设置启用/禁用状态
        for (var eventName:String in eventHandlers[targetKey]) {
            var eventInfo:Object = eventHandlers[targetKey][eventName];
            if (eventInfo && eventInfo.handlers != undefined) {
                eventInfo.isEnabled = enable;
            }
        }
    }

    //======================================================================
    // 5. 设置 onUnload 自动清理及用户卸载逻辑
    //======================================================================
    /**
     * 设置目标对象的 onUnload 自动清理逻辑，并兼容用户自定义卸载逻辑。
     * @param target 目标对象。
     */
    private static function setupAutomaticCleanup(target:Object):Void {
        var tKey:String = getTargetKey(target);

        // 保存用户的初始 onUnload 函数
        if (eventHandlers[tKey].__EC_userUnload__ == undefined) {
            eventHandlers[tKey].__EC_userUnload__ = target.onUnload;
        }

        // 保存初始引用，防止后续清理后拿不到
        var originalUserUnload:Function = eventHandlers[tKey].__EC_userUnload__;

        // 替换 onUnload 为代理函数
        target.onUnload = function() {
            var currentKey:String = getTargetKey(this);
            var userUnload:Function = originalUserUnload;

            // 获取最新的用户卸载函数
            if (eventHandlers[currentKey] != undefined) {
                var ecData:Object = eventHandlers[currentKey];
                if (ecData.__EC_userUnload__ != undefined) {
                    userUnload = ecData.__EC_userUnload__;
                }
            }

            // 1. 清理所有事件监听器
            EventCoordinator.clearEventListeners(this);

            // 2. 还原 onUnload 为用户初始函数
            this.onUnload = userUnload;

            // 3. 执行用户卸载逻辑
            if (typeof userUnload == "function") {
                userUnload.apply(this);
            }
        };

        // 监控 onUnload 属性，防止用户代码覆盖
        if (typeof target.watch == "function") {
            target.watch("onUnload", function(prop, oldVal, newVal) {
                var currentKey:String = getTargetKey(this);
                if (eventHandlers[currentKey] != undefined) {
                    eventHandlers[currentKey].__EC_userUnload__ = newVal;
                }
                return oldVal; // 返回旧值，防止用户覆盖
            });
        }
    }

    //======================================================================
    // 6. 获取目标对象的唯一标识
    //======================================================================
    /**
     * 获取或生成目标对象的唯一标识。
     * @param target 目标对象。
     * @return 目标对象的唯一标识。
     */
    private static function getTargetKey(target:Object):String {
        if (target.__EC_uid__ == undefined) {
            target.__EC_uid__ = "EC" + (nextID++);
            // 防止 __EC_uid__ 被枚举或删除
            if (_global.ASSetPropFlags) {
                _global.ASSetPropFlags(target, ["__EC_uid__"], 1, true);
            }
        }
        return target.__EC_uid__;
    }

    //======================================================================
    // 7. 快捷方法的优化处理
    //======================================================================

    /**
     * 动态生成添加事件处理器的快捷方法。
     * @param eventName 事件名称。
     * @return 匿名函数，用于添加事件处理器。
     */
    private static function createCallbackMethod(eventName:String):Function {
        return function(target:Object, handler:Function):String {
            return EventCoordinator.addEventListener(target, eventName, handler);
        };
    }

    // 为常用事件动态创建快捷方法
    public static var addUnloadCallback:Function = createCallbackMethod("onUnload");
    public static var addLoadCallback:Function = createCallbackMethod("onLoad");
    public static var addEnterFrameCallback:Function = createCallbackMethod("onEnterFrame");
    public static var addPressCallback:Function = createCallbackMethod("onPress");
    public static var addReleaseCallback:Function = createCallbackMethod("onRelease");
    public static var addRollOverCallback:Function = createCallbackMethod("onRollOver");
    public static var addRollOutCallback:Function = createCallbackMethod("onRollOut");
    public static var addMouseMoveCallback:Function = createCallbackMethod("onMouseMove");
    public static var addMouseDownCallback:Function = createCallbackMethod("onMouseDown");
    public static var addMouseUpCallback:Function = createCallbackMethod("onMouseUp");
    public static var addKeyDownCallback:Function = createCallbackMethod("onKeyDown");
    public static var addKeyUpCallback:Function = createCallbackMethod("onKeyUp");
    public static var addDragOutCallback:Function = createCallbackMethod("onDragOut");
    public static var addDragOverCallback:Function = createCallbackMethod("onDragOver");
    public static var addDataCallback:Function = createCallbackMethod("onData");
}