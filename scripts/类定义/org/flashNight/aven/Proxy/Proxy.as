class org.flashNight.aven.Proxy.Proxy {
    // UID counter for assigning unique identifiers to objects
    private static var uidCounter:Number = 1;

    /**
     * Retrieves the unique identifier (UID) for the object.
     * If the object hasn't been assigned a UID, it assigns a new one and attaches it to the object.
     * Also initializes the __proxyData__ object on the first call.
     * @param key The object to get the UID for.
     * @return The UID of the object.
     */
    private static function getStaticUID(key:Object):Number {
        if (key.__proxyUID__ === undefined) {
            key.__proxyUID__ = uidCounter++; // Assign a new UID
            key.__proxyData__ = { propertyCallbacks: {}, functionCallbacks: {} }; // Initialize proxy data storage
            // Set properties as non-enumerable to prevent external access
            _global.ASSetPropFlags(key, ["__proxyUID__", "__proxyData__"], 1, true);
            // trace("[DEBUG] Assigned UID: " + key.__proxyUID__ + " to object.");
        }
        return key.__proxyUID__;
    }

    /**
     * Adds a setter watcher for a property.
     * When the property is modified, the callback function is triggered.
     * @param obj The object whose property is being watched.
     * @param propName The name of the property to watch.
     * @param callback The callback function to invoke when the property is modified.
     */
    public static function addPropertySetterWatcher(obj:Object, propName:String, callback:Function):Void {
        setupProperty(obj, propName); // Ensure the property has a proxy set up
        var proxyData:Object = obj.__proxyData__;
        var setterCallback = proxyData.propertyCallbacks[propName].setter;

        if (setterCallback == null) {
            proxyData.propertyCallbacks[propName].setter = callback;
            // trace("[DEBUG] Added first Setter callback for property: " + propName + " on object with UID: " + obj.__proxyUID__);
        } else if (typeof setterCallback == "function") {
            proxyData.propertyCallbacks[propName].setter = [setterCallback, callback];
            // trace("[DEBUG] Converted Setter callback to array for property: " + propName + " on object with UID: " + obj.__proxyUID__);
        } else {
            setterCallback.push(callback);
            // trace("[DEBUG] Added additional Setter callback for property: " + propName + " on object with UID: " + obj.__proxyUID__);
        }
    }

    /**
     * Adds a getter watcher for a property.
     * When the property is accessed, the callback function is triggered.
     * @param obj The object whose property is being watched.
     * @param propName The name of the property to watch.
     * @param callback The callback function to invoke when the property is accessed.
     */
    public static function addPropertyGetterWatcher(obj:Object, propName:String, callback:Function):Void {
        setupProperty(obj, propName);
        var proxyData:Object = obj.__proxyData__;
        var getterCallback = proxyData.propertyCallbacks[propName].getter;

        if (getterCallback == null) {
            proxyData.propertyCallbacks[propName].getter = callback;
            // trace("[DEBUG] Added first Getter callback for property: " + propName + " on object with UID: " + obj.__proxyUID__);
        } else if (typeof getterCallback == "function") {
            proxyData.propertyCallbacks[propName].getter = [getterCallback, callback];
            // trace("[DEBUG] Converted Getter callback to array for property: " + propName + " on object with UID: " + obj.__proxyUID__);
        } else {
            getterCallback.push(callback);
            // trace("[DEBUG] Added additional Getter callback for property: " + propName + " on object with UID: " + obj.__proxyUID__);
        }
    }

    /**
     * Removes a setter watcher from a property.
     * @param obj The object whose property watcher is being removed.
     * @param propName The name of the property.
     * @param callback The callback function to remove.
     */
    public static function removePropertySetterWatcher(obj:Object, propName:String, callback:Function):Void {
        removeCallback(obj, propName, "setter", callback);
    }

    /**
     * Removes a getter watcher from a property.
     * @param obj The object whose property watcher is being removed.
     * @param propName The name of the property.
     * @param callback The callback function to remove.
     */
    public static function removePropertyGetterWatcher(obj:Object, propName:String, callback:Function):Void {
        removeCallback(obj, propName, "getter", callback);
    }

    /**
     * Adds a function call watcher.
     * When the function is called, the callback function is triggered.
     * @param obj The object whose method is being watched.
     * @param funcName The name of the method to watch.
     * @param callback The callback function to invoke when the method is called.
     */
    public static function addFunctionCallWatcher(obj:Object, funcName:String, callback:Function):Void {
        var uid:Number = getStaticUID(obj); // Ensure the object's UID exists
        setupFunction(obj, funcName);
        var proxyData:Object = obj.__proxyData__;
        var funcCallback = proxyData.functionCallbacks[funcName];

        if (funcCallback == null) {
            proxyData.functionCallbacks[funcName] = callback;
            // trace("[DEBUG] Added first function call callback for method: " + funcName + " on object with UID: " + uid);
        } else if (typeof funcCallback == "function") {
            proxyData.functionCallbacks[funcName] = [funcCallback, callback];
            // trace("[DEBUG] Converted function call callback to array for method: " + funcName + " on object with UID: " + uid);
        } else {
            funcCallback.push(callback);
            // trace("[DEBUG] Added additional function call callback for method: " + funcName + " on object with UID: " + uid);
        }
    }

    /**
     * Removes a function call watcher.
     * @param obj The object whose method watcher is being removed.
     * @param funcName The name of the method.
     * @param callback The callback function to remove.
     */
    public static function removeFunctionCallWatcher(obj:Object, funcName:String, callback:Function):Void {
        var uid:Number = getStaticUID(obj);
        var proxyData:Object = obj.__proxyData__;
        var funcCallback = proxyData.functionCallbacks[funcName];

        if (funcCallback != null) {
            if (typeof funcCallback == "function") {
                if (funcCallback == callback) {
                    proxyData.functionCallbacks[funcName] = null;
                    // trace("[DEBUG] Removed last function call callback for method: " + funcName + " on object with UID: " + uid);
                }
            } else {
                for (var i:Number = 0; i < funcCallback.length; i++) {
                    if (funcCallback[i] == callback) {
                        funcCallback.splice(i, 1);
                        // trace("[DEBUG] Removed a function call callback for method: " + funcName + " on object with UID: " + uid);
                        break;
                    }
                }
                // If only one callback remains, simplify storage
                if (funcCallback.length == 1) {
                    proxyData.functionCallbacks[funcName] = funcCallback[0];
                    // trace("[DEBUG] Simplified function call callback storage for method: " + funcName + " on object with UID: " + uid);
                } else if (funcCallback.length == 0) {
                    proxyData.functionCallbacks[funcName] = null;
                    // trace("[DEBUG] All function call callbacks removed for method: " + funcName + " on object with UID: " + uid);
                }
            }
        }
    }

    /**
     * Internal method to set up property getters and setters and initialize callback storage.
     * If the property hasn't been proxied yet, it creates proxy getters and setters.
     * @param obj The object whose property is being set up.
     * @param propName The name of the property.
     */
    private static function setupProperty(obj:Object, propName:String):Void {
        var uid:Number = getStaticUID(obj); // Ensure the object's UID exists
        var proxyData:Object = obj.__proxyData__;
        if (!proxyData.propertyCallbacks[propName]) {
            proxyData.propertyCallbacks[propName] = { getter: null, setter: null };

            var internalPropName:String = "__" + propName + "__"; // Internal storage for the property

            // Initialize the actual value
            obj[internalPropName] = obj[propName];

            // Set internal property as non-enumerable
            _global.ASSetPropFlags(obj, [internalPropName], 1, true);

            // Create custom Getter and Setter
            var getter:Function = createGetter(obj, propName, internalPropName);
            var setter:Function = createSetter(obj, propName, internalPropName);

            // Use addProperty to add custom Getter and Setter
            obj.addProperty(propName, getter, setter);

            // trace("[DEBUG] Set up property proxy for: " + propName + " on object with UID: " + uid);
        }
    }

    /**
     * Creates a custom Getter function.
     * When the property is accessed, all registered Getter callbacks are invoked.
     * @param obj The object to which the property belongs.
     * @param propName The name of the property.
     * @param internalPropName The internal storage name for the property.
     * @return The custom Getter function.
     */
    private static function createGetter(obj:Object, propName:String, internalPropName:String):Function {
        return function() {
            var value = obj[internalPropName];
            var getterCallback = obj.__proxyData__.propertyCallbacks[propName].getter;
            var uid:Number = obj.__proxyUID__;
            if (getterCallback != null) {
                // trace("[DEBUG] Getter called for property: " + propName + " on object with UID: " + uid);
                if (typeof getterCallback == "function") {
                    getterCallback.call(obj, value);
                } else {
                    for (var i:Number = 0; i < getterCallback.length; i++) {
                        getterCallback[i].call(obj, value);
                    }
                }
            }
            return value;
        };
    }

    /**
     * Creates a custom Setter function.
     * When the property is modified, all registered Setter callbacks are invoked with the new and old values.
     * @param obj The object to which the property belongs.
     * @param propName The name of the property.
     * @param internalPropName The internal storage name for the property.
     * @return The custom Setter function.
     */
    private static function createSetter(obj:Object, propName:String, internalPropName:String):Function {
        return function(newValue):Void {
            var oldValue = obj[internalPropName];
            obj[internalPropName] = newValue;
            var setterCallback = obj.__proxyData__.propertyCallbacks[propName].setter;
            var uid:Number = obj.__proxyUID__;
            if (setterCallback != null) {
                // trace("[DEBUG] Setter called for property: " + propName + " on object with UID: " + uid);
                if (typeof setterCallback == "function") {
                    setterCallback.call(obj, newValue, oldValue);
                } else {
                    for (var i:Number = 0; i < setterCallback.length; i++) {
                        setterCallback[i].call(obj, newValue, oldValue);
                    }
                }
            }
        };
    }

    /**
     * Internal method to remove a callback function.
     * @param obj The object from which to remove the callback.
     * @param propName The name of the property.
     * @param type The type of callback ("getter" or "setter").
     * @param callback The callback function to remove.
     */
    private static function removeCallback(obj:Object, propName:String, type:String, callback:Function):Void {
        var proxyData:Object = obj.__proxyData__;
        var callbackRef = proxyData.propertyCallbacks[propName][type];
        var uid:Number = obj.__proxyUID__;

        if (callbackRef != null) {
            if (typeof callbackRef == "function") {
                if (callbackRef == callback) {
                    proxyData.propertyCallbacks[propName][type] = null;
                    // trace("[DEBUG] Removed last " + type + " callback for property: " + propName + " on object with UID: " + uid);
                }
            } else {
                for (var i:Number = 0; i < callbackRef.length; i++) {
                    if (callbackRef[i] == callback) {
                        callbackRef.splice(i, 1);
                        // trace("[DEBUG] Removed a " + type + " callback for property: " + propName + " on object with UID: " + uid);
                        break;
                    }
                }
                // Simplify storage if only one callback remains
                if (callbackRef.length == 1) {
                    proxyData.propertyCallbacks[propName][type] = callbackRef[0];
                    // trace("[DEBUG] Simplified " + type + " callback storage for property: " + propName + " on object with UID: " + uid);
                } else if (callbackRef.length == 0) {
                    proxyData.propertyCallbacks[propName][type] = null;
                    // trace("[DEBUG] All " + type + " callbacks removed for property: " + propName + " on object with UID: " + uid);
                }
            }
        }
    }

    /**
     * Internal method to set up a function proxy and initialize callback storage.
     * If the function hasn't been proxied yet, it creates a proxy function.
     * @param obj The object whose function is being set up.
     * @param funcName The name of the function.
     */
    private static function setupFunction(obj:Object, funcName:String):Void {
        var proxyData:Object = obj.__proxyData__;
        if (proxyData.functionCallbacks[funcName] === undefined) {
            proxyData.functionCallbacks[funcName] = null;

            var originalFunction:Function = obj[funcName];

            // Create the proxy function
            var proxyFunction:Function = function() {
                var args:Array = arguments;
                var funcCallback = obj.__proxyData__.functionCallbacks[funcName];
                var uid:Number = obj.__proxyUID__;
                if (funcCallback != null) {
                    // trace("[DEBUG] Function called: " + funcName + " on object with UID: " + uid);
                    if (typeof funcCallback == "function") {
                        funcCallback.apply(this, args);
                    } else {
                        for (var i:Number = 0; i < funcCallback.length; i++) {
                            funcCallback[i].apply(this, args);
                        }
                    }
                }
                // Call the original function
                return originalFunction.apply(this, args);
            };

            // Set the proxy function's UID and make it non-enumerable
            proxyFunction.__proxyUID__ = obj.__proxyUID__;
            _global.ASSetPropFlags(proxyFunction, ["__proxyUID__"], 1, true);

            // Replace the original function with the proxy function
            obj[funcName] = proxyFunction;

            // trace("[DEBUG] Set up function proxy for method: " + funcName + " on object with UID: " + obj.__proxyUID__);
        }
    }
}
