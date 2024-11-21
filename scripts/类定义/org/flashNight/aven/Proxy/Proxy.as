class org.flashNight.aven.Proxy.Proxy {
    // UID 计数器，用于为每个对象分配唯一的标识符
    private static var uidCounter:Number = 1; // UID 计数器
    private static var uidMap:Object = {}; // UID 映射到对象

    /**
     * 获取对象的唯一标识符（UID）。
     * 如果对象尚未分配 UID，则为其分配一个新的 UID 并存储在 uidMap 中。
     * @param key 需要获取 UID 的对象。
     * @return 对象的 UID。
     */
    private static function getStaticUID(key:Object):Number {
        var uid:Number = key.__proxyUID__;
        if (uid === undefined) {
            uid = key.__proxyUID__ = uidCounter++;
            uidMap[uid] = key;
            // 将 __proxyUID__ 属性设为不可枚举，防止外部访问
            _global.ASSetPropFlags(key, ["__proxyUID__"], 1, true);
        }
        return uid;
    }

    // 哈希表，用于存储属性回调函数，键为对象的 UID
    private static var propertyCallbacks:Object = {}; // 属性回调集合
    private static var functionCallbacks:Object = {}; // 函数回调集合

    /**
     * 添加属性的 Setter 监视器。
     * 当对象的指定属性被修改时，触发回调函数。
     * @param obj 需要监视的对象。
     * @param propName 需要监视的属性名。
     * @param callback 属性被修改时调用的回调函数。
     */
    public static function addPropertySetterWatcher(obj:Object, propName:String, callback:Function):Void {
        setupProperty(obj, propName); // 确保属性已设置代理
        var uid = getStaticUID(obj);
        propertyCallbacks[uid][propName].setters.push(callback);
        // trace("[DEBUG] 添加 Setter 回调: " + propName + " (UID: " + uid + ")");
    }

    /**
     * 添加属性的 Getter 监视器。
     * 当对象的指定属性被访问时，触发回调函数。
     * @param obj 需要监视的对象。
     * @param propName 需要监视的属性名。
     * @param callback 属性被访问时调用的回调函数。
     */
    public static function addPropertyGetterWatcher(obj:Object, propName:String, callback:Function):Void {
        setupProperty(obj, propName);
        var uid = getStaticUID(obj);
        propertyCallbacks[uid][propName].getters.push(callback);
        // trace("[DEBUG] 添加 Getter 回调: " + propName + " (UID: " + uid + ")");
    }

    /**
     * 移除属性的 Setter 监视器。
     * @param obj 需要移除监视器的对象。
     * @param propName 被监视的属性名。
     * @param callback 需要移除的回调函数。
     */
    public static function removePropertySetterWatcher(obj:Object, propName:String, callback:Function):Void {
        removeCallback(obj, propName, "setters", callback);
    }

    /**
     * 移除属性的 Getter 监视器。
     * @param obj 需要移除监视器的对象。
     * @param propName 被监视的属性名。
     * @param callback 需要移除的回调函数。
     */
    public static function removePropertyGetterWatcher(obj:Object, propName:String, callback:Function):Void {
        removeCallback(obj, propName, "getters", callback);
    }

    /**
     * 添加函数调用的监视器。
     * 当对象的方法被调用时，触发回调函数。
     * @param obj 需要监视的方法所属的对象。
     * @param funcName 需要监视的方法名。
     * @param callback 方法被调用时执行的回调函数。
     */
    public static function addFunctionCallWatcher(obj:Object, funcName:String, callback:Function):Void {
        var func:Function = obj[funcName];
        var uid:Number = getStaticUID(func);
        setupFunction(obj, funcName, uid);
        functionCallbacks[uid].push(callback);
        // trace("[DEBUG] 函数调用回调被添加: " + funcName + " (UID: " + uid + ")");
    }

    /**
     * 移除函数调用的监视器。
     * @param obj 需要移除监视器的方法所属的对象。
     * @param funcName 被监视的方法名。
     * @param callback 需要移除的回调函数。
     */
    public static function removeFunctionCallWatcher(obj:Object, funcName:String, callback:Function):Void {
        var func:Function = obj[funcName];
        var uid:Number = getStaticUID(func);
        var callbacks:Array = functionCallbacks[uid];
        if (callbacks) {
            for (var i:Number = 0; i < callbacks.length; i++) {
                if (callbacks[i] == callback) {
                    callbacks.splice(i, 1);
                    break;
                }
            }
        }
    }

    /**
     * 内部方法，设置属性的 Getter 和 Setter，并初始化回调数组。
     * 如果属性尚未被代理，则为其创建代理 Getter 和 Setter。
     * @param obj 需要设置代理的对象。
     * @param propName 需要代理的属性名。
     */
    private static function setupProperty(obj:Object, propName:String):Void {
        var uid:Number = getStaticUID(obj);
        if (!propertyCallbacks[uid]) {
            propertyCallbacks[uid] = {};
        }

        if (!propertyCallbacks[uid][propName]) {
            propertyCallbacks[uid][propName] = { getters: [], setters: [] };

            var internalPropName:String = "__" + propName + "__"; // 内部存储属性名

            // 初始化实际值
            obj[internalPropName] = obj[propName];

            // 将内部属性设为不可枚举，防止外部访问
            _global.ASSetPropFlags(obj, [internalPropName], 1, true);

            // 创建自定义的 Getter 和 Setter
            var getter:Function = createGetter(obj, propName, internalPropName);
            var setter:Function = createSetter(obj, propName, internalPropName);

            // 使用 addProperty 为属性添加自定义的 Getter 和 Setter
            obj.addProperty(propName, getter, setter);
        }
    }

    /**
     * 创建自定义的 Getter 函数。
     * 当属性被访问时，调用所有注册的 Getter 回调函数。
     * @param obj 属性所属的对象。
     * @param propName 属性名。
     * @param internalPropName 内部存储属性名。
     * @return 自定义的 Getter 函数。
     */
    private static function createGetter(obj:Object, propName:String, internalPropName:String):Function {
        return function() {
            var value = obj[internalPropName];
            var uid:Number = Proxy.getStaticUID(obj);
            var callbacks:Array = Proxy.propertyCallbacks[uid][propName].getters;
            // trace("[DEBUG] Getter 被调用: " + propName + " (UID: " + uid + "), 回调数量: " + callbacks.length);
            for (var i:Number = 0; i < callbacks.length; i++) {
                callbacks[i].call(obj, value);
            }
            return value;
        };
    }

    /**
     * 创建自定义的 Setter 函数。
     * 当属性被修改时，调用所有注册的 Setter 回调函数，并传递新值和旧值。
     * @param obj 属性所属的对象。
     * @param propName 属性名。
     * @param internalPropName 内部存储属性名。
     * @return 自定义的 Setter 函数。
     */
    private static function createSetter(obj:Object, propName:String, internalPropName:String):Function {
        return function(newValue):Void {
            var oldValue = obj[internalPropName];
            obj[internalPropName] = newValue;
            var uid:Number = Proxy.getStaticUID(obj);
            var callbacks:Array = Proxy.propertyCallbacks[uid][propName].setters;
            // trace("[DEBUG] Setter 被调用: " + propName + " (UID: " + uid + "), 回调数量: " + callbacks.length);
            for (var i:Number = 0; i < callbacks.length; i++) {
                callbacks[i].call(obj, newValue, oldValue);
            }
        };
    }

    /**
     * 内部方法，移除回调函数。
     * @param obj 需要移除回调的对象。
     * @param propName 被监视的属性名。
     * @param type 回调的类型（"getters" 或 "setters"）。
     * @param callback 需要移除的回调函数。
     */
    private static function removeCallback(obj:Object, propName:String, type:String, callback:Function):Void {
        var uid:Number = getStaticUID(obj);
        if (propertyCallbacks[uid] && propertyCallbacks[uid][propName]) {
            var callbacks:Array = propertyCallbacks[uid][propName][type];
            for (var i:Number = 0; i < callbacks.length; i++) {
                if (callbacks[i] == callback) {
                    callbacks.splice(i, 1);
                    break;
                }
            }
        }
    }

    /**
     * 内部方法，设置函数的代理，并初始化回调数组。
     * 如果函数尚未被代理，则为其创建代理函数。
     * @param obj 函数所属的对象。
     * @param funcName 函数名。
     * @param uid 函数的 UID。
     */
    private static function setupFunction(obj:Object, funcName:String, uid:Number):Void {
        var func:Function = obj[funcName];
        if (!functionCallbacks[uid]) {
            functionCallbacks[uid] = [];

            // 创建代理函数
            var proxyFunction:Function = function() {
                var args:Array = arguments;
                var callbacks:Array = Proxy.functionCallbacks[uid];
                // trace("[DEBUG] 函数调用回调被触发: " + funcName + " (UID: " + uid + "), 回调数量: " + callbacks.length);
                for (var i:Number = 0; i < callbacks.length; i++) {
                    callbacks[i].apply(this, args);
                }
                // 调用原始函数，并返回其结果
                return func.apply(this, args);
            };

            // 将代理函数的 UID 设为与原始函数相同
            proxyFunction.__proxyUID__ = uid;
            _global.ASSetPropFlags(proxyFunction, ["__proxyUID__"], 1, true); // 设置不可枚举

            // 替换对象上的原始函数为代理函数
            obj[funcName] = proxyFunction;
        }
    }
}
