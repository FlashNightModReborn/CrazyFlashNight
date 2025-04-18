class org.flashNight.aven.Proxy.Proxy {
    // 用于为对象分配唯一标识符的计数器
    private static var uidCounter:Number = 1;

    /**
     * 为对象的属性添加 setter 监视器。
     * 当属性被修改时，会触发回调函数。
     * @param obj 需要监视属性的对象。
     * @param propName 需要监视的属性名称。
     * @param callback 当属性被修改时调用的回调函数。
     */
    public static function addPropertySetterWatcher(obj:Object, propName:String, callback:Function):Void {
        // 内联 getStaticUID 逻辑并进行变量本地化
        var proxyUID:String = "__proxyUID__";
        var proxyDataKey:String = "__proxyData__";
        if (obj[proxyUID] === undefined) {
            var uid:Number = uidCounter++; // 分配新的 UID
            obj[proxyUID] = uid;
            var proxyData:Object = { propertyCallbacks: {}, functionCallbacks: {} };
            obj[proxyDataKey] = proxyData; // 初始化代理数据存储
            // 将属性设置为不可枚举，以防止外部访问
            _global.ASSetPropFlags(obj, [proxyUID, proxyDataKey], 1, false);
            // trace("[DEBUG] Assigned UID: " + uid + " to object.");
        } else {
            var uid:Number = obj[proxyUID];
            var proxyData:Object = obj[proxyDataKey];
        }

        // 内联 setupProperty 逻辑并进行变量本地化
        var propertyCallbacks:Object = proxyData.propertyCallbacks;
        if (!propertyCallbacks[propName]) {
            var callbacks:Object = { getter: null, setter: null };
            propertyCallbacks[propName] = callbacks;

            var internalPropName:String = "__" + propName + "__"; // 内部存储属性的名称

            // 初始化实际的属性值
            obj[internalPropName] = obj[propName];

            // 将内部属性设置为不可枚举
            _global.ASSetPropFlags(obj, [internalPropName], 1, false);

            // 创建自定义的 Getter 和 Setter
            var getter:Function = function() {
                var value = obj[internalPropName];
                var getterCallback = callbacks.getter;
                if (getterCallback != null) {
                    // trace("[DEBUG] Getter 调用属性: " + propName + " 在对象 UID: " + uid);
                    if (typeof getterCallback == "function") {
                        getterCallback.call(obj, value);
                    } else {
                        for (var i:Number = getterCallback.length - 1; i >= 0; i--) {
                            getterCallback[i].call(obj, value);
                        }
                    }
                }
                return value;
            };

            var setter:Function = function(newValue):Void {
                var oldValue = obj[internalPropName];
                obj[internalPropName] = newValue;
                var setterCallback = callbacks.setter;
                if (setterCallback != null) {
                    // trace("[DEBUG] Setter 调用属性: " + propName + " 在对象 UID: " + uid);
                    if (typeof setterCallback == "function") {
                        setterCallback.call(obj, newValue, oldValue);
                    } else {
                        for (var i:Number = setterCallback.length - 1; i >= 0; i--) {
                            setterCallback[i].call(obj, newValue, oldValue);
                        }
                    }
                }
            };

            // 使用 addProperty 添加自定义的 Getter 和 Setter
            obj.addProperty(propName, getter, setter);

            // trace("[DEBUG] 设置属性代理: " + propName + " 在对象 UID: " + uid);
        } else {
            var callbacks:Object = propertyCallbacks[propName];
        }

        var setterCallback = callbacks.setter;

        // 添加回调并优化存储方式
        if (setterCallback == null) {
            callbacks.setter = callback;
            // trace("[DEBUG] 添加第一个 Setter 回调属性: " + propName + " 在对象 UID: " + uid);
        } else if (typeof setterCallback == "function") {
            callbacks.setter = [setterCallback, callback];
            // trace("[DEBUG] 将 Setter 回调转换为数组属性: " + propName + " 在对象 UID: " + uid);
        } else {
            setterCallback.push(callback);
            // trace("[DEBUG] 添加额外的 Setter 回调属性: " + propName + " 在对象 UID: " + uid);
        }
    }

    public static function addPropertySetterWatcherWithWatch(obj:Object, propName:String, callback:Function):Void {
        var proxyUID:String = "__proxyUID__";
        var proxyDataKey:String = "__proxyData__";

        // 初始化 UID 和代理数据
        if (obj[proxyUID] === undefined) {
            var uid:Number = uidCounter++; // 分配新的 UID
            obj[proxyUID] = uid;
            var proxyData:Object = { propertyCallbacks: {}, functionCallbacks: {} };
            obj[proxyDataKey] = proxyData; // 初始化代理数据存储
            _global.ASSetPropFlags(obj, [proxyUID, proxyDataKey], 1, false);
        } else {
            var proxyData:Object = obj[proxyDataKey];
        }

        // 获取或初始化属性回调
        var propertyCallbacks:Object = proxyData.propertyCallbacks;
        if (!propertyCallbacks[propName]) {
            propertyCallbacks[propName] = { setter: null, getter: null };
        }

        var setterCallback = propertyCallbacks[propName].setter;

        // 添加回调
        if (setterCallback == null) {
            propertyCallbacks[propName].setter = callback;
        } else if (typeof setterCallback == "function") {
            propertyCallbacks[propName].setter = [setterCallback, callback];
        } else {
            setterCallback.push(callback);
        }

        // 使用 watch 实现 setter 代理
        obj.watch(propName, function(prop, oldValue, newValue) {
            var callbacks = propertyCallbacks[propName].setter;
            if (callbacks != null) {
                if (typeof callbacks == "function") {
                    callbacks.call(obj, newValue, oldValue);
                } else {
                    for (var i:Number = callbacks.length - 1; i >= 0; i--) {
                        callbacks[i].call(obj, newValue, oldValue);
                    }
                }
            }
            return newValue; // 保持原行为
        });
    }


    /**
     * 为对象的属性添加 getter 监视器。
     * 当属性被访问时，会触发回调函数。
     * @param obj 需要监视属性的对象。
     * @param propName 需要监视的属性名称。
     * @param callback 当属性被访问时调用的回调函数。
     */
    public static function addPropertyGetterWatcher(obj:Object, propName:String, callback:Function):Void {
        // 内联 getStaticUID 逻辑并进行变量本地化
        var proxyUID:String = "__proxyUID__";
        var proxyDataKey:String = "__proxyData__";
        if (obj[proxyUID] === undefined) {
            var uid:Number = uidCounter++; // 分配新的 UID
            obj[proxyUID] = uid;
            var proxyData:Object = { propertyCallbacks: {}, functionCallbacks: {} };
            obj[proxyDataKey] = proxyData; // 初始化代理数据存储
            // 将属性设置为不可枚举，以防止外部访问
            _global.ASSetPropFlags(obj, [proxyUID, proxyDataKey], 1, false);
            // trace("[DEBUG] Assigned UID: " + uid + " to object.");
        } else {
            var uid:Number = obj[proxyUID];
            var proxyData:Object = obj[proxyDataKey];
        }

        // 内联 setupProperty 逻辑并进行变量本地化
        var propertyCallbacks:Object = proxyData.propertyCallbacks;
        if (!propertyCallbacks[propName]) {
            var callbacks:Object = { getter: null, setter: null };
            propertyCallbacks[propName] = callbacks;

            var internalPropName:String = "__" + propName + "__"; // 内部存储属性的名称

            // 初始化实际的属性值
            obj[internalPropName] = obj[propName];

            // 将内部属性设置为不可枚举
            _global.ASSetPropFlags(obj, [internalPropName], 1, false);

            // 创建自定义的 Getter 和 Setter
            var getter:Function = function() {
                var value = obj[internalPropName];
                var getterCallback = callbacks.getter;
                if (getterCallback != null) {
                    // trace("[DEBUG] Getter 调用属性: " + propName + " 在对象 UID: " + uid);
                    if (typeof getterCallback == "function") {
                        getterCallback.call(obj, value);
                    } else {
                        for (var i:Number = getterCallback.length - 1; i >= 0; i--) {
                            getterCallback[i].call(obj, value);
                        }
                    }
                }
                return value;
            };

            var setter:Function = function(newValue):Void {
                var oldValue = obj[internalPropName];
                obj[internalPropName] = newValue;
                var setterCallback = callbacks.setter;
                if (setterCallback != null) {
                    // trace("[DEBUG] Setter 调用属性: " + propName + " 在对象 UID: " + uid);
                    if (typeof setterCallback == "function") {
                        setterCallback.call(obj, newValue, oldValue);
                    } else {
                        for (var i:Number = setterCallback.length - 1; i >= 0; i--) {
                            setterCallback[i].call(obj, newValue, oldValue);
                        }
                    }
                }
            };

            // 使用 addProperty 添加自定义的 Getter 和 Setter
            obj.addProperty(propName, getter, setter);

            // trace("[DEBUG] 设置属性代理: " + propName + " 在对象 UID: " + uid);
        } else {
            var callbacks:Object = propertyCallbacks[propName];
        }

        var getterCallback = callbacks.getter;

        // 添加回调并优化存储方式
        if (getterCallback == null) {
            callbacks.getter = callback;
            // trace("[DEBUG] 添加第一个 Getter 回调属性: " + propName + " 在对象 UID: " + uid);
        } else if (typeof getterCallback == "function") {
            callbacks.getter = [getterCallback, callback];
            // trace("[DEBUG] 将 Getter 回调转换为数组属性: " + propName + " 在对象 UID: " + uid);
        } else {
            getterCallback.push(callback);
            // trace("[DEBUG] 添加额外的 Getter 回调属性: " + propName + " 在对象 UID: " + uid);
        }
    }

    public static function removePropertyWatcherWithWatch(obj:Object, propName:String):Void {
        obj.unwatch(propName); // 直接移除 watch 代理
    }


    /**
     * 从对象的属性中移除 setter 监视器。
     * @param obj 需要移除 setter 监视器的对象。
     * @param propName 需要移除监视器的属性名称。
     * @param callback 需要移除的回调函数。
     */
    public static function removePropertySetterWatcher(obj:Object, propName:String, callback:Function):Void {
        // 内联 getStaticUID 逻辑并进行变量本地化
        var proxyUID:String = "__proxyUID__";
        var proxyDataKey:String = "__proxyData__";
        if (obj[proxyUID] === undefined) {
            var uid:Number = uidCounter++; // 分配新的 UID
            obj[proxyUID] = uid;
            var proxyData:Object = { propertyCallbacks: {}, functionCallbacks: {} };
            obj[proxyDataKey] = proxyData; // 初始化代理数据存储
            // 将属性设置为不可枚举，以防止外部访问
            _global.ASSetPropFlags(obj, [proxyUID, proxyDataKey], 1, false);
            // trace("[DEBUG] Assigned UID: " + uid + " to object.");
        } else {
            var uid:Number = obj[proxyUID];
            var proxyData:Object = obj[proxyDataKey];
        }

        var propertyCallbacks:Object = proxyData.propertyCallbacks;
        var callbacks:Object = propertyCallbacks[propName];
        if (callbacks) {
            var setterCallback = callbacks.setter;
            if (setterCallback != null) {
                if (typeof setterCallback == "function") {
                    if (setterCallback == callback) {
                        callbacks.setter = null;
                        // trace("[DEBUG] 移除最后一个 Setter 回调属性: " + propName + " 在对象 UID: " + uid);
                    }
                } else {
                    for (var i:Number = setterCallback.length - 1; i >= 0; i--) {
                        if (setterCallback[i] == callback) {
                            setterCallback.splice(i, 1);
                            // trace("[DEBUG] 移除一个 Setter 回调属性: " + propName + " 在对象 UID: " + uid);
                            break;
                        }
                    }
                    // 如果只剩一个回调，简化存储
                    var len = setterCallback.length;

                    if (len == 1) {
                        callbacks.setter = setterCallback[0];
                        // trace("[DEBUG] 简化 Setter 回调存储属性: " + propName + " 在对象 UID: " + uid);
                    } else if (len == 0) {
                        callbacks.setter = null;
                        // trace("[DEBUG] 移除所有 Setter 回调属性: " + propName + " 在对象 UID: " + uid);
                    }
                }
            }
        }
    }

    /**
     * 从对象的属性中移除 getter 监视器。
     * @param obj 需要移除 getter 监视器的对象。
     * @param propName 需要移除监视器的属性名称。
     * @param callback 需要移除的回调函数。
     */
    public static function removePropertyGetterWatcher(obj:Object, propName:String, callback:Function):Void {
        // 内联 getStaticUID 逻辑并进行变量本地化
        var proxyUID:String = "__proxyUID__";
        var proxyDataKey:String = "__proxyData__";
        if (obj[proxyUID] === undefined) {
            var uid:Number = uidCounter++; // 分配新的 UID
            obj[proxyUID] = uid;
            var proxyData:Object = { propertyCallbacks: {}, functionCallbacks: {} };
            obj[proxyDataKey] = proxyData; // 初始化代理数据存储
            // 将属性设置为不可枚举，以防止外部访问
            _global.ASSetPropFlags(obj, [proxyUID, proxyDataKey], 1, false);
            // trace("[DEBUG] Assigned UID: " + uid + " to object.");
        } else {
            var uid:Number = obj[proxyUID];
            var proxyData:Object = obj[proxyDataKey];
        }

        var propertyCallbacks:Object = proxyData.propertyCallbacks;
        var callbacks:Object = propertyCallbacks[propName];
        if (callbacks) {
            var getterCallback = callbacks.getter;
            if (getterCallback != null) {
                if (typeof getterCallback == "function") {
                    if (getterCallback == callback) {
                        callbacks.getter = null;
                        // trace("[DEBUG] 移除最后一个 Getter 回调属性: " + propName + " 在对象 UID: " + uid);
                    }
                } else {
                    for (var i:Number = getterCallback.length - 1; i >= 0; i--) {
                        if (getterCallback[i] == callback) {
                            getterCallback.splice(i, 1);
                            // trace("[DEBUG] 移除一个 Getter 回调属性: " + propName + " 在对象 UID: " + uid);
                            break;
                        }
                    }
                    // 如果只剩一个回调，简化存储
                    var len = getterCallback.length;

                    if (len == 1) {
                        callbacks.getter = getterCallback[0];
                        // trace("[DEBUG] 简化 Getter 回调存储属性: " + propName + " 在对象 UID: " + uid);
                    } else if (len == 0) {
                        callbacks.getter = null;
                        // trace("[DEBUG] 移除所有 Getter 回调属性: " + propName + " 在对象 UID: " + uid);
                    }
                }
            }
        }
    }

    /**
     * 为对象的方法添加函数调用监视器。
     * 当方法被调用时，会触发回调函数。
     * @param obj 需要监视方法的对象。
     * @param funcName 需要监视的方法名称。
     * @param callback 当方法被调用时调用的回调函数。
     */
    public static function addFunctionCallWatcher(obj:Object, funcName:String, callback:Function):Void {
        // 内联 getStaticUID 逻辑并进行变量本地化
        var proxyUID:String = "__proxyUID__";
        var proxyDataKey:String = "__proxyData__";
        if (obj[proxyUID] === undefined) {
            var uid:Number = uidCounter++; // 分配新的 UID
            obj[proxyUID] = uid;
            var proxyData:Object = { propertyCallbacks: {}, functionCallbacks: {} };
            obj[proxyDataKey] = proxyData; // 初始化代理数据存储
            // 将属性设置为不可枚举，以防止外部访问
            _global.ASSetPropFlags(obj, [proxyUID, proxyDataKey], 1, false);
            // trace("[DEBUG] Assigned UID: " + uid + " to object.");
        } else {
            var uid:Number = obj[proxyUID];
            var proxyData:Object = obj[proxyDataKey];
        }

        var functionCallbacks:Object = proxyData.functionCallbacks;

        if (functionCallbacks[funcName] === undefined) {
            functionCallbacks[funcName] = null;

            var originalFunction:Function = obj[funcName];

            // 创建代理函数
            var proxyFunction:Function = function() {
                var args:Array = arguments;
                var funcCallback = functionCallbacks[funcName];
                if (funcCallback != null) {
                    // trace("[DEBUG] 函数调用: " + funcName + " 在对象 UID: " + uid);
                    if (typeof funcCallback == "function") {
                        funcCallback.apply(this, args);
                    } else {
                        for (var i:Number = funcCallback.length - 1; i >= 0; i--) {
                            funcCallback[i].apply(this, args);
                        }
                    }
                }
                // 调用原始函数
                return originalFunction.apply(this, args);
            };

            // 设置代理函数的 UID 并将其设为不可枚举
            proxyFunction.__proxyUID__ = uid;
            _global.ASSetPropFlags(proxyFunction, ["__proxyUID__"], 1, false);

            // 将原始函数替换为代理函数
            obj[funcName] = proxyFunction;

            // trace("[DEBUG] 设置函数代理: " + funcName + " 在对象 UID: " + uid);
        }

        var funcCallback = functionCallbacks[funcName];

        // 添加回调并优化存储方式
        if (funcCallback == null) {
            functionCallbacks[funcName] = callback;
            // trace("[DEBUG] 添加第一个函数调用回调方法: " + funcName + " 在对象 UID: " + uid);
        } else if (typeof funcCallback == "function") {
            functionCallbacks[funcName] = [funcCallback, callback];
            // trace("[DEBUG] 将函数调用回调转换为数组方法: " + funcName + " 在对象 UID: " + uid);
        } else {
            funcCallback.push(callback);
            // trace("[DEBUG] 添加额外的函数调用回调方法: " + funcName + " 在对象 UID: " + uid);
        }
    }

    /**
     * 从对象的方法中移除函数调用监视器。
     * @param obj 需要移除函数调用监视器的对象。
     * @param funcName 需要移除监视器的方法名称。
     * @param callback 需要移除的回调函数。
     */
    public static function removeFunctionCallWatcher(obj:Object, funcName:String, callback:Function):Void {
        // 内联 getStaticUID 逻辑并进行变量本地化
        var proxyUID:String = "__proxyUID__";
        var proxyDataKey:String = "__proxyData__";
        if (obj[proxyUID] === undefined) {
            var uid:Number = uidCounter++; // 分配新的 UID
            obj[proxyUID] = uid;
            var proxyData:Object = { propertyCallbacks: {}, functionCallbacks: {} };
            obj[proxyDataKey] = proxyData; // 初始化代理数据存储
            // 将属性设置为不可枚举，以防止外部访问
            _global.ASSetPropFlags(obj, [proxyUID, proxyDataKey], 1, false);
            // trace("[DEBUG] Assigned UID: " + uid + " to object.");
        } else {
            var uid:Number = obj[proxyUID];
            var proxyData:Object = obj[proxyDataKey];
        }

        var functionCallbacks:Object = proxyData.functionCallbacks;
        var funcCallback = functionCallbacks[funcName];

        if (funcCallback != null) {
            if (typeof funcCallback == "function") {
                if (funcCallback == callback) {
                    functionCallbacks[funcName] = null;
                    // trace("[DEBUG] 移除最后一个函数调用回调方法: " + funcName + " 在对象 UID: " + uid);
                }
            } else {
                for (var i:Number = funcCallback.length - 1; i >= 0; i--) {
                    if (funcCallback[i] == callback) {
                        funcCallback.splice(i, 1);
                        // trace("[DEBUG] 移除一个函数调用回调方法: " + funcName + " 在对象 UID: " + uid);
                        break;
                    }
                }
                // 如果只剩一个回调，简化存储
                var len = funcCallback.length;
                if (len == 1) {
                    functionCallbacks[funcName] = funcCallback[0];
                    // trace("[DEBUG] 简化函数调用回调存储方法: " + funcName + " 在对象 UID: " + uid);
                } else if (len == 0) {
                    functionCallbacks[funcName] = null;
                    // trace("[DEBUG] 移除所有函数调用回调方法: " + funcName + " 在对象 UID: " + uid);
                }
            }
        }
    }
}
