import org.flashNight.neur.Event.Delegate; 
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * EventBus 类用于事件的订阅、发布和管理。
 * 
 * 采用饿汉式单例模式，确保在类加载时实例化。
 * 
 * 通过预分配数组大小、索引操作、版本号缓存和循环展开等优化措施，提高性能。
 * 
 * 该类允许用户订阅事件、取消订阅事件，并发布事件，能够有效地管理和调用事件的回调函数。
 * 另外，提供了事件的版本管理与回调函数缓存功能，避免重复回调和内存浪费。
 */
class org.flashNight.neur.Event.EventBus {
    
    // 存储每个事件的回调函数及其相关数据
    // 结构：事件名 -> { callbacks: {id:poolIndex}, funcToID: {funcID:id}, count:Number, cacheVersion:Number, callbackCache:Array }
    private var listeners:Object; 
    
    // 回调函数对象池（预分配内存）
    private var pool:Array; 
    
    // 可用索引栈（内存复用）
    private var availSpace:Array; 
    
    // 可用索引栈顶指针
    private var availSpaceTop:Number; 
    
    // 参数缓存区（重用避免GC）
    private var tempArgs:Array; 
    
    // 回调缓存区（重用避免GC）
    private var tempCallbacks:Array;

    // 饿汉式单例直接初始化（节省首次调用开销）
    public static var instance:EventBus = new EventBus();

    /**
     * 构造函数（私有化）
     * 
     * 预分配内存池并初始化数据结构。
     * 
     * 初始化监听器对象、内存池、回收空间等相关数据结构，使用固定容量和优化策略避免运行时扩容。
     */
    private function EventBus() {
        this.listeners = {}; 
        var initialCapacity:Number = 1024;

        // 预分配固定大小数组（避免运行时扩容）
        this.pool = new Array(initialCapacity); 
        this.availSpace = new Array(initialCapacity); 
        this.availSpaceTop = initialCapacity; 
        this.tempArgs = new Array(10); // 假设最大参数数量为10 
        this.tempCallbacks = new Array(initialCapacity);

        // 使用循环展开初始化内存池（提升初始化速度）
        var unrollFactor:Number = 8; 
        var i:Number = 0; 
        for (; i + unrollFactor <= initialCapacity; i += unrollFactor) { 
            this.pool[i] = this.pool[i+1] = this.pool[i+2] = this.pool[i+3] = this.pool[i+4] = this.pool[i+5] = this.pool[i+6] = this.pool[i+7] = null;
            this.availSpace[i] = i; 
            this.availSpace[i+1] = i+1;
            this.availSpace[i+2] = i+2; 
            this.availSpace[i+3] = i+3;
            this.availSpace[i+4] = i+4; 
            this.availSpace[i+5] = i+5;
            this.availSpace[i+6] = i+6; 
            this.availSpace[i+7] = i+7;
        } 
        for (; i < initialCapacity; i++) { 
            this.pool[i] = null; 
            this.availSpace[i] = i; 
        }
    }

    /**
     * 初始化方法（脚本初始化时调用）
     * 
     * 调用 Delegate 类的初始化方法，进行 Delegate 缓存的初始化。
     * 
     * @return EventBus 实例
     */
    public static function initialize():EventBus { 
        Delegate.init(); // 初始化 Delegate 缓存
        return instance; 
    }

    /**
     * 单例访问方法
     * 
     * @return EventBus 实例
     */
    public static function getInstance():EventBus { 
        return instance; 
    }

    /**
     * 订阅事件（带版本号标记）
     * 
     * 订阅某一事件名的回调函数，且该事件会被记录版本号，当事件回调发生变化时进行更新。
     * 事件回调函数会被包装，并通过内存池进行分配。
     * 
     * @param eventName 事件名称
     * @param callback 回调函数
     * @param scope 执行域
     */
    public function subscribe(eventName:String, callback:Function, scope:Object):Void { 
        var listenersForEvent:Object = this.listeners[eventName]; 
        if (!listenersForEvent) { 
            listenersForEvent = { 
                callbacks: {}, // callbackID -> poolIndex
                funcToID: {}, // funcUID -> callbackID 
                count: 0, 
                cacheVersion: 0, // 新增：缓存版本号 
                callbackCache: null // 新增：缓存回调数组 
            }; 
            this.listeners[eventName] = listenersForEvent; 
        }

        var funcToID:Object = listenersForEvent.funcToID; 
        var funcID:String = String(Dictionary.getStaticUID(callback));

        // 重复订阅检测
        if (funcToID[funcID] != undefined) return;

        // 生成包装函数（带作用域绑定）
        var callbackID:Number = Dictionary.getStaticUID(callback); 
        var wrappedCallback:Function = Delegate.create(scope, callback);

        // 从对象池分配索引
        var allocIndex:Number; 
        if (this.availSpaceTop > 0) { 
            allocIndex = this.availSpace[--this.availSpaceTop]; 
        } else { 
            this.expandPool(); 
            allocIndex = this.availSpace[--this.availSpaceTop]; 
        } 
        this.pool[allocIndex] = wrappedCallback;

        // 更新数据结构并标记版本
        listenersForEvent.callbacks[callbackID] = allocIndex; 
        funcToID[funcID] = callbackID; 
        listenersForEvent.count++; 
        listenersForEvent.cacheVersion++; // 递增缓存版本 
        listenersForEvent.callbackCache = null; // 使旧缓存失效 
    }

    /**
     * 取消订阅事件（带版本号标记）
     * 
     * 取消订阅某一事件名的回调函数，释放相关资源并更新事件监听器状态。
     * 
     * @param eventName 事件名称
     * @param callback 回调函数
     */
    public function unsubscribe(eventName:String, callback:Function):Void { 
        var listenersForEvent:Object = this.listeners[eventName]; 
        if (!listenersForEvent) return;

        var funcToID:Object = listenersForEvent.funcToID; 
        var funcID:String = String(Dictionary.getStaticUID(callback)); 
        var callbackID:Number = funcToID[funcID];

        if (callbackID == undefined) return;

        // 回收对象池索引
        var allocIndex:Number = listenersForEvent.callbacks[callbackID]; 
        if (allocIndex != undefined) { 
            this.pool[allocIndex] = null; 
            this.availSpace[this.availSpaceTop++] = allocIndex; 
            delete listenersForEvent.callbacks[callbackID]; 
            delete funcToID[funcID]; 
        }

        // 更新状态并标记版本
        listenersForEvent.count--; 
        listenersForEvent.cacheVersion++; // 递增缓存版本 
        listenersForEvent.callbackCache = null; // 使旧缓存失效

        // 如果该事件没有回调函数，删除该事件的监听器
        if (listenersForEvent.count === 0) { 
            delete this.listeners[eventName]; 
        } 
    }

    /**
     * 发布事件（带版本号缓存优化）
     * 
     * 发布事件并执行所有已订阅的回调函数。如果回调函数有缓存且未过期，则直接使用缓存回调。
     * 
     * @param eventName 事件名称
     */
    public function publish(eventName:String):Void { 
        var listenersForEvent:Object = this.listeners[eventName]; 
        if (!listenersForEvent) return;

        var cache:Array = listenersForEvent.callbackCache; 
        var cacheVersion:Number = listenersForEvent.cacheVersion;

        // 缓存有效性检查
        if (!cache || cacheVersion !== cache._version) { 
            // 需要重新生成缓存 
            var callbacks:Object = listenersForEvent.callbacks; 
            var localTempCallbacks:Array = this.tempCallbacks; 
            var tempCount:Number = 0; 
            var poolRef:Array = this.pool; 
            var cbID:String; 
            var index:Number; 
            var cb:Function;

            // 收集有效回调
            for (cbID in callbacks) { 
                index = callbacks[cbID]; 
                cb = poolRef[index]; 
                if (cb != null) { 
                    localTempCallbacks[tempCount++] = cb; 
                } 
            }

            // 更新缓存（重用数组避免GC）
            cache = listenersForEvent.callbackCache = localTempCallbacks.slice(0, tempCount); 
            cache._version = cacheVersion;  // 嵌入版本标记
        }

        // 无回调直接返回
        var cacheLen:Number = cache.length; 
        if (cacheLen === 0) return;

        // 参数处理（重用tempArgs数组）
        var localTempArgs:Array = this.tempArgs; 
        var argsLen:Number = arguments.length - 1; 
        var hasArgs:Boolean = argsLen > 0;

        if (hasArgs) { 
            for (var i:Number = 0; i < argsLen; i++) { 
                localTempArgs[i] = arguments[i + 1]; 
            } 
        }

        // 执行回调（倒序执行避免正序删除问题）
        var j:Number = cacheLen; 
        while (j--) { 
            var cb:Function = cache[j]; 
            try { 
                // 参数分支展开（避免apply开销）
                if (hasArgs) { 
                    // 使用精确的if-else链代替switch
                    if (argsLen == 0) { 
                        cb(); 
                    } else if (argsLen == 1) { 
                        cb(localTempArgs[0]); 
                    } else if (argsLen == 2) { 
                        cb(localTempArgs[0], localTempArgs[1]); 
                    } else if (argsLen == 3) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2]); 
                    } else if (argsLen == 4) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3]); 
                    } else if (argsLen == 5) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4]); 
                    } else if (argsLen == 6) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5]); 
                    } else if (argsLen == 7) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6]); 
                    } else if (argsLen == 8) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7]); 
                    } else if (argsLen == 9) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8]); 
                    } else { 
                        // 参数超过9个时使用apply 
                        cb.apply(null, localTempArgs.slice(0, argsLen)); 
                    } 
                } else { 
                    // 无参数直接调用 
                    cb(); 
                } 
            } catch (e:Error) { 
                trace("EventBus Error:" + e.message); 
            } 
        }
    }


    /**
     * 发布事件（显式参数数组版本）
     * 
     * 通过显式参数数组传递事件参数，其余逻辑与publish()保持一致
     * 
     * @param eventName 事件名称
     * @param params 参数数组（可选）
     */
    public function publishWithParam(eventName:String, params:Array):Void { 
        var listenersForEvent:Object = this.listeners[eventName]; 
        if (!listenersForEvent) return;

        var cache:Array = listenersForEvent.callbackCache; 
        var cacheVersion:Number = listenersForEvent.cacheVersion;

        // 缓存有效性检查（与原方法完全一致）
        if (!cache || cacheVersion !== cache._version) { 
            var callbacks:Object = listenersForEvent.callbacks; 
            var localTempCallbacks:Array = this.tempCallbacks; 
            var tempCount:Number = 0; 
            var poolRef:Array = this.pool; 
            var cbID:String; 
            var index:Number; 
            var cb:Function;

            for (cbID in callbacks) { 
                index = callbacks[cbID]; 
                cb = poolRef[index]; 
                if (cb != null) { 
                    localTempCallbacks[tempCount++] = cb; 
                } 
            }

            cache = listenersForEvent.callbackCache = localTempCallbacks.slice(0, tempCount); 
            cache._version = cacheVersion;
        }

        var cacheLen:Number = cache.length; 
        if (cacheLen === 0) return;

        // 参数处理修改点（使用显式参数数组）
        var localTempArgs:Array = this.tempArgs; 
        var argsLen:Number = (params != null) ? params.length : 0; 
        var hasArgs:Boolean = argsLen > 0;

        if (hasArgs) { 
            // 直接拷贝参数数组内容
            for (var i:Number = 0; i < argsLen; i++) { 
                localTempArgs[i] = params[i]; 
            } 
        }

        // 回调执行逻辑（保持完全一致）
        var j:Number = cacheLen; 
        while (j--) { 
            var cb:Function = cache[j]; 
            try { 
                if (hasArgs) { 
                    if (argsLen == 0) { 
                        cb(); 
                    } else if (argsLen == 1) { 
                        cb(localTempArgs[0]); 
                    } else if (argsLen == 2) { 
                        cb(localTempArgs[0], localTempArgs[1]); 
                    } else if (argsLen == 3) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2]); 
                    } else if (argsLen == 4) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3]); 
                    } else if (argsLen == 5) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4]); 
                    } else if (argsLen == 6) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5]); 
                    } else if (argsLen == 7) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6]); 
                    } else if (argsLen == 8) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7]); 
                    } else if (argsLen == 9) { 
                        cb(localTempArgs[0], localTempArgs[1], localTempArgs[2], localTempArgs[3], localTempArgs[4], localTempArgs[5], localTempArgs[6], localTempArgs[7], localTempArgs[8]); 
                    } else { 
                        cb.apply(null, localTempArgs.slice(0, argsLen)); 
                    } 
                } else { 
                    cb(); 
                } 
            } catch (e:Error) { 
                trace("EventBus Error:" + e.message); 
            } 
        }
    }

    /**
     * 一次性订阅（继承版本号机制）
     * 
     * 订阅一次性事件，即回调函数执行一次后自动取消订阅。
     * 
     * @param eventName 事件名称
     * @param callback 回调函数
     * @param scope 执行域
     */
    public function subscribeOnce(eventName:String, callback:Function, scope:Object):Void { 
        var self:EventBus = this; 
        var originalID:String = String(Dictionary.getStaticUID(callback));

        // 利用Delegate的缓存机制确保匿名函数的唯一性，使其可以被正确取消订阅
        // 包装回调函数 
        var onceCallback:Function = function():Void { 
            callback.apply(scope, arguments); 
            self.unsubscribe(eventName, callback); 
        };

        this.subscribe(eventName, onceCallback, scope); 
    }

    /**
     * 销毁方法（增强版本清理）
     * 
     * 清理所有监听器和对象池中的资源，释放内存。
     */
    public function destroy():Void { 
        for (var eventName:String in this.listeners) { 
            var listenersForEvent:Object = this.listeners[eventName]; 
            for (var cbID:String in listenersForEvent.callbacks) { 
                var index:Number = listenersForEvent.callbacks[cbID]; 
                this.pool[index] = null; 
                this.availSpace[this.availSpaceTop++] = index; 
            } 
            delete this.listeners[eventName]; 
        }

        // 清空对象池
        var poolLen:Number = this.pool.length; 
        for (var i:Number = 0; i < poolLen; i++) { 
            this.pool[i] = null; 
            if (this.availSpaceTop < this.availSpace.length) { 
                this.availSpace[this.availSpaceTop++] = i; 
            } 
        }

        Delegate.clearCache(); 
        this.tempArgs.length = 0; 
        this.tempCallbacks.length = 0; 
    }

    /**
     * 扩展对象池（保持原有优化策略）
     * 
     * 扩展对象池的容量，确保能够容纳更多的回调函数。
     */
    private function expandPool():Void { 
        var oldCap:Number = this.pool.length; 
        var newCap:Number = oldCap << 1; // 容量翻倍

        // 扩展对象池数组
        var newPool:Array = new Array(newCap); 
        var newAvail:Array = new Array(newCap);

        // 复制旧数据（循环展开优化）
        var unroll:Number = 8; 
        var i:Number = 0; 
        for (; i + unroll <= oldCap; i += unroll) { 
            newPool[i] = this.pool[i]; 
            newPool[i+1] = this.pool[i+1]; 
            newPool[i+2] = this.pool[i+2]; 
            newPool[i+3] = this.pool[i+3]; 
            newPool[i+4] = this.pool[i+4]; 
            newPool[i+5] = this.pool[i+5]; 
            newPool[i+6] = this.pool[i+6]; 
            newPool[i+7] = this.pool[i+7]; 
        } 
        for (; i < oldCap; i++) newPool[i] = this.pool[i];

        // 初始化新空间
        for (i = oldCap; i < newCap; i++) { 
            newPool[i] = null; 
            newAvail[this.availSpaceTop++] = i; 
        }

        // 替换引用 
        this.pool = newPool; 
        this.availSpace = newAvail; 
    }
}
