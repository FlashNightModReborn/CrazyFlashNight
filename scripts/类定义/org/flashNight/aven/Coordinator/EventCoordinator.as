/**
 * org.flashNight.aven.Coordinator.EventCoordinator
 *
 * 改进要点：
 * 1) 事件监听器触发时倒序遍历，提高高频事件 (如 onEnterFrame) 性能，并避免移除时索引错乱。
 * 2) 支持用户在添加监听器后再次修改 onUnload：利用 watch() 劫持属性，
 *    将新的用户 onUnload 存入 eventHandlers 并在代理函数最后调用，
 *    以确保自动清理逻辑始终生效且不会被覆盖。
 * 3) 仍使用隐藏的 __EC_uid__ 属性来避免与其他库冲突，并在 clearEventListeners 里清理自动清理标记。
 */
class org.flashNight.aven.Coordinator.EventCoordinator {
    // eventHandlers[targetKey][eventName] = {
    //    original:Function,   // 初次发现的原生事件处理器（若有）
    //    handlers:Array,      // 自定义监听器数组
    //    isEnabled:Boolean,   // 是否启用自定义监听器
    //    ...
    // }
    private static var eventHandlers:Object = {};
    private static var nextID:Number = 0;

    //======================================================================
    // ============   1. 添加事件监听器核心方法   =============
    //======================================================================
    public static function addEventListener(target:Object, eventName:String, handler:Function):String {
        if (target == null || eventName == null || handler == null) {
            trace("Error: Invalid arguments in addEventListener.");
            return null;
        }

        var targetKey:String = getTargetKey(target);

        // 若还没为此 target 建立事件数据，先初始化空对象
        if (eventHandlers[targetKey] == undefined) {
            eventHandlers[targetKey] = {};
        }

        // 初始化并替换 target[eventName] (只一次)
        if (eventHandlers[targetKey][eventName] == undefined) {
            var originalHandler:Function = target[eventName];
            eventHandlers[targetKey][eventName] = {
                original:  originalHandler,
                handlers:  [],
                isEnabled: true
            };

            // === 事件代理函数 ===
            target[eventName] = function() {
                var tKey:String = getTargetKey(this);    
                var info:Object = eventHandlers[tKey][eventName];
                if (!info) {
                    // 如果 info 已被清理，直接返回
                    return;
                }

                // 如果禁用自定义监听，则仅执行原生事件处理器
                if (!info.isEnabled) {
                    if (info.original) {
                        info.original.apply(this);
                    }
                    return;
                }

                // 倒序遍历监听器，减少索引错乱风险 & 可能提升性能
                var localHandlers:Array = info.handlers;
                for (var i:Number = localHandlers.length - 1; i >= 0; i--) {
                    localHandlers[i].func.apply(this);
                }

                // 再执行原生事件处理器
                if (info.original) {
                    info.original.apply(this);
                }
            };

            // 若事件名不是 onUnload，则设置自动清理
            if (eventName != "onUnload") {
                if (!eventHandlers[targetKey].__EC_autoCleanup__) {
                    eventHandlers[targetKey].__EC_autoCleanup__ = true;
                    setupAutomaticCleanup(target);
                }
            }
        }

        // 插入新的监听器
        var infoObj:Object = eventHandlers[targetKey][eventName];
        var handlerID:String = "HID" + (nextID++);
        infoObj.handlers.push({id: handlerID, func: handler});

        return handlerID;
    }

    //======================================================================
    // ============   2. 移除特定的事件监听器    =============
    //======================================================================
    public static function removeEventListener(target:Object, eventName:String, handlerID:String):Void {
        if (target == null || eventName == null || handlerID == null) {
            trace("Error: Invalid arguments in removeEventListener.");
            return;
        }

        var targetKey:String = getTargetKey(target);
        var eventInfo:Object = (eventHandlers[targetKey] != undefined)
                               ? eventHandlers[targetKey][eventName]
                               : null;
        if (!eventInfo) {
            return; // 未添加或已被清理
        }

        var handlers:Array = eventInfo.handlers;
        for (var i:Number = 0; i < handlers.length; i++) {
            if (handlers[i].id === handlerID) {
                handlers.splice(i, 1);
                trace("Handler removed: " + handlerID);
                break;
            }
        }

        // 若无自定义监听器，则恢复原生并删除记录
        if (handlers.length == 0) {
            target[eventName] = eventInfo.original;
            delete eventHandlers[targetKey][eventName];
            trace("All handlers for " + eventName + " removed. Restored original handler.");
        }
    }

    //======================================================================
    // ============   3. 清除对象上的所有事件监听器   =============
    //======================================================================
    public static function clearEventListeners(target:Object):Void {
        var targetKey:String = getTargetKey(target);
        if (!eventHandlers[targetKey]) {
            return;
        }

        // 恢复该 target 下所有事件的原生处理器
        for (var eventName:String in eventHandlers[targetKey]) {
            var eventInfo:Object = eventHandlers[targetKey][eventName];
            if (typeof eventInfo == "object" && eventInfo.handlers != undefined) {
                target[eventName] = eventInfo.original;
            }
        }

        // 删除全部记录
        delete eventHandlers[targetKey];
        delete target.__EC_autoCleanup__;

        trace("All event listeners cleared for target.");
    }

    //======================================================================
    // ============   4. 启用或禁用对象上的所有事件监听器   =============
    //======================================================================
    /**
     * 启用或禁用 target 的所有自定义监听器。禁用时原生事件处理器仍会执行。
     */
    public static function enableEventListeners(target:Object, enable:Boolean):Void {
        var targetKey:String = getTargetKey(target);
        if (!eventHandlers[targetKey]) {
            return;
        }

        for (var eventName:String in eventHandlers[targetKey]) {
            var eventInfo:Object = eventHandlers[targetKey][eventName];
            if (eventInfo && eventInfo.handlers != undefined) {
                eventInfo.isEnabled = enable;
            }
        }
    }

    //======================================================================
    // ============   5. 自动清理 (onUnload)逻辑 + 用户覆盖检测  =============
    //======================================================================
    /**
     * 设置自动清理：
     *   - 替换 onUnload
     *   - 若用户在之后修改 onUnload，则用 watch() 捕获并存储到 __EC_userUnload__，最终在代理中统一调用
     */
    private static function setupAutomaticCleanup(target:Object):Void {
        if (!eventHandlers[getTargetKey(target)].__EC_userUnload__) {
            // 先记录初始 userUnload
            eventHandlers[getTargetKey(target)].__EC_userUnload__ = target.onUnload;
        }

        // === 最终代理 ===
        target.onUnload = function() {
            var tKey:String = getTargetKey(this);

            // 执行清理
            EventCoordinator.clearEventListeners(this);

            // 再调用用户最新版 onUnload
            var userUnload:Function = (eventHandlers[tKey] != undefined)
                ? eventHandlers[tKey].__EC_userUnload__
                : null;
            if (typeof userUnload == "function") {
                userUnload.apply(this);
            }
        };

        // watch onUnload 以捕获用户二次赋值
        if (typeof target.watch == "function") {
            target.watch("onUnload", function(prop, oldVal, newVal) {
                var tKey:String = getTargetKey(this);
                // 若 eventHandlers 已被清理，可能说明对象不再使用
                if (eventHandlers[tKey] != undefined) {
                    eventHandlers[tKey].__EC_userUnload__ = newVal;
                }
                // 使 onUnload 保持代理函数，不被用户覆盖
                return oldVal; 
            });
        }
    }

    //======================================================================
    // ============   6. 为目标生成(或获取)唯一标识符Key   =============
    //======================================================================
    private static function getTargetKey(target:Object):String {
        if (target.__EC_uid__ == undefined) {
            target.__EC_uid__ = "EC" + (nextID++);
            _global.ASSetPropFlags(target, ["__EC_uid__"], 1, true);
        }
        return target.__EC_uid__;
    }

    //======================================================================
    // ============   7. 常用事件的快捷方法   =============
    //======================================================================
    public static function addUnloadCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onUnload", handler);
    }
    public static function addLoadCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onLoad", handler);
    }
    public static function addEnterFrameCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onEnterFrame", handler);
    }
    public static function addPressCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onPress", handler);
    }
    public static function addReleaseCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onRelease", handler);
    }
    public static function addRollOverCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onRollOver", handler);
    }
    public static function addRollOutCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onRollOut", handler);
    }
    public static function addMouseMoveCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onMouseMove", handler);
    }
    public static function addMouseDownCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onMouseDown", handler);
    }
    public static function addMouseUpCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onMouseUp", handler);
    }
    public static function addKeyDownCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onKeyDown", handler);
    }
    public static function addKeyUpCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onKeyUp", handler);
    }
    public static function addDragOutCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onDragOut", handler);
    }
    public static function addDragOverCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onDragOver", handler);
    }
    public static function addDataCallback(target:Object, handler:Function):String {
        return addEventListener(target, "onData", handler);
    }
}
