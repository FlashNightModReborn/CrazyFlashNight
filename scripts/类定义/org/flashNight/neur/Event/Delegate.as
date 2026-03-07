import org.flashNight.naki.DataStructures.Dictionary;

/**
 * Delegate 类用于创建绑定作用域的委托函数。
 *
 * 版本历史:
 * v3.0 (2026-03) - 特化版本优化
 *   [PERF] 新增 create0/create1/create2 特化方法，消除 wrapper 中 arguments 对象开销 (~1538ns/次)
 *   [PERF] 删除冗余 init() 调用，静态初始化器已足够
 *   [API] create() 保持完全向后兼容，作为可变参数 fallback
 *
 * v2.1 (2026-01) - 三方交叉审查修复
 *   [FIX] createWithParams 的 paramsUID 添加长度前缀，修复缓存键碰撞风险
 *         例如 ["a|b"] 和 ["a", "b"] 之前都会生成 "a|b"，现在分别生成 "1:a|b" 和 "2:a|b"
 *   [CLEAN] 移除未使用的 import 语句
 *
 * v2.0 (2026-01) - 内存泄漏修复
 *   [FIX] 将缓存从静态全局迁移到 scope 对象自身 (__delegateCache)
 *   [FIX] 当 scope 被 GC 时，其缓存自然释放，彻底解决内存泄漏
 *   [COMPAT] scope==null 的情况仍使用全局缓存（无泄漏风险）
 *   [PERF] 保持 O(1) 缓存查找性能
 *
 * 性能说明:
 *   - create0/create1/create2: 零 arguments 开销，适用于已知参数数量的调用站点
 *   - create: 通用版本，通过 arguments 对象分发，适用于参数数量不确定的场景
 *   - 缓存键的生成是性能-稳定性的权衡
 *   - 简单类型参数使用 String() 转换而非 getStaticUID，以减少 UID 分配开销
 *   - v2.1 通过添加长度前缀大幅降低了碰撞概率，但仍非完全零碰撞
 */
class org.flashNight.neur.Event.Delegate {
    /** [v2.0] 仅用于 scope==null 的全局作用域委托 */
    private static var cacheCreate:Object = {};

    /** [v2.0] 仅用于 scope==null 的带参数委托 */
    private static var cacheCreateWithParams:Object = {};

    /**
     * [v3.0] 零参数特化版本。
     * wrapper 不创建 arguments 对象，直接 method.call(scope)，
     * 消除每次调用 ~1538ns 的 arguments 开销。
     *
     * 适用场景：RendererVM 命令分发、FrameTimer、状态回调等。
     *
     * @param scope 函数执行时 this 指向的对象。如果为 null，则在全局作用域执行。
     * @param method 需要创建委托的方法。
     * @return 绑定了指定作用域的零参数委托函数。
     */
    public static function create0(scope:Object, method:Function):Function {
        var methodUID:String = String(Dictionary.getStaticUID(method));

        if (scope == null) {
            var cached:Function = cacheCreate[methodUID];
            if (cached != undefined) return cached;

            var f:Function = function() {
                return method.call(null);
            };
            cacheCreate[methodUID] = f;
            return f;
        }

        var scopeCache:Object = scope.__delegateCache;
        if (scopeCache == null) {
            scopeCache = scope.__delegateCache = {};
            _global.ASSetPropFlags(scope, ["__delegateCache"], 1, true);
        }

        var cachedScope:Function = scopeCache[methodUID];
        if (cachedScope != undefined) return cachedScope;

        var fs:Function = function() {
            return method.call(scope);
        };
        scopeCache[methodUID] = fs;
        return fs;
    }

    /**
     * [v3.0] 单参数特化版本。
     * wrapper 不创建 arguments 对象，直接透传单个参数。
     *
     * 适用场景：BulletFactory、XMLSocketClient 回调、ObjectPool 等。
     *
     * @param scope 函数执行时 this 指向的对象。
     * @param method 需要创建委托的方法。
     * @return 绑定了指定作用域的单参数委托函数。
     */
    public static function create1(scope:Object, method:Function):Function {
        var methodUID:String = String(Dictionary.getStaticUID(method));

        if (scope == null) {
            var cached:Function = cacheCreate[methodUID];
            if (cached != undefined) return cached;

            var f:Function = function(a) {
                return method.call(null, a);
            };
            cacheCreate[methodUID] = f;
            return f;
        }

        var scopeCache:Object = scope.__delegateCache;
        if (scopeCache == null) {
            scopeCache = scope.__delegateCache = {};
            _global.ASSetPropFlags(scope, ["__delegateCache"], 1, true);
        }

        var cachedScope:Function = scopeCache[methodUID];
        if (cachedScope != undefined) return cachedScope;

        var fs:Function = function(a) {
            return method.call(scope, a);
        };
        scopeCache[methodUID] = fs;
        return fs;
    }

    /**
     * [v3.0] 双参数特化版本。
     * wrapper 不创建 arguments 对象，直接透传两个参数。
     *
     * 适用场景：双参数事件回调、ServerManager 等。
     *
     * @param scope 函数执行时 this 指向的对象。
     * @param method 需要创建委托的方法。
     * @return 绑定了指定作用域的双参数委托函数。
     */
    public static function create2(scope:Object, method:Function):Function {
        var methodUID:String = String(Dictionary.getStaticUID(method));

        if (scope == null) {
            var cached:Function = cacheCreate[methodUID];
            if (cached != undefined) return cached;

            var f:Function = function(a, b) {
                return method.call(null, a, b);
            };
            cacheCreate[methodUID] = f;
            return f;
        }

        var scopeCache:Object = scope.__delegateCache;
        if (scopeCache == null) {
            scopeCache = scope.__delegateCache = {};
            _global.ASSetPropFlags(scope, ["__delegateCache"], 1, true);
        }

        var cachedScope:Function = scopeCache[methodUID];
        if (cachedScope != undefined) return cachedScope;

        var fs:Function = function(a, b) {
            return method.call(scope, a, b);
        };
        scopeCache[methodUID] = fs;
        return fs;
    }

    /**
     * 创建一个函数委托，将方法绑定到指定的作用域 (scope)。
     * 如果已为相同的作用域和方法创建过委托，则返回缓存中的委托函数，以提高性能。
     *
     * [v3.0] 这是可变参数的通用版本，作为 create0/create1/create2 的 fallback。
     * 当调用时参数数量已知且固定时，优先使用对应的特化版本以避免 arguments 开销。
     *
     * @param scope 函数执行时 this 指向的对象。如果为 null，则函数将在全局作用域执行。
     * @param method 需要创建委托的方法。
     * @return 绑定了指定作用域的委托函数。
     * @throws Error 如果 method 为 null 或 undefined。
     */
    public static function create(scope:Object, method:Function):Function {
        if (method == null) {
            throw new Error("The provided method is undefined or null");
        }

        var methodUID:String = String(Dictionary.getStaticUID(method));

        // --- 处理 scope == null 的情况 ---
        if (scope == null) {
            var cachedFunction:Function = cacheCreate[methodUID];
            if (cachedFunction != undefined) {
                return cachedFunction;
            }

            var wrappedGlobalFunction:Function = function() {
                var len:Number = arguments.length;
                if (len == 0) return method.call(null);
                else if (len == 1) return method.call(null, arguments[0]);
                else if (len == 2) return method.call(null, arguments[0], arguments[1]);
                else if (len == 3) return method.call(null, arguments[0], arguments[1], arguments[2]);
                else if (len == 4) return method.call(null, arguments[0], arguments[1], arguments[2], arguments[3]);
                else if (len == 5) return method.call(null, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4]);
                else return method.apply(null, arguments);
            };

            cacheCreate[methodUID] = wrappedGlobalFunction;
            return wrappedGlobalFunction;
        }
        // --- 处理 scope != null 的情况 ---
        else {
            // [v2.0 FIX] 将缓存存储在 scope 对象自身
            var scopeCache:Object = scope.__delegateCache;
            if (scopeCache == null) {
                scopeCache = scope.__delegateCache = {};
                _global.ASSetPropFlags(scope, ["__delegateCache"], 1, true);
            }

            var cachedFunctionScope:Function = scopeCache[methodUID];
            if (cachedFunctionScope != undefined) {
                return cachedFunctionScope;
            }

            var wrappedFunctionScope:Function = function() {
                var len:Number = arguments.length;
                if (len == 0) return method.call(scope);
                else if (len == 1) return method.call(scope, arguments[0]);
                else if (len == 2) return method.call(scope, arguments[0], arguments[1]);
                else if (len == 3) return method.call(scope, arguments[0], arguments[1], arguments[2]);
                else if (len == 4) return method.call(scope, arguments[0], arguments[1], arguments[2], arguments[3]);
                else if (len == 5) return method.call(scope, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4]);
                else return method.apply(scope, arguments);
            };

            scopeCache[methodUID] = wrappedFunctionScope;
            return wrappedFunctionScope;
        }
    }

    /**
     * 创建一个带有预定义参数的委托函数。
     *
     * [v2.1 FIX] paramsUID 添加长度前缀，修复缓存键碰撞风险
     * 性能说明：缓存键生成是性能-稳定性权衡，详见类文档
     *
     * @param scope 将作为 `this` 绑定的对象。如果为 `null`，则函数将在全局作用域中执行。
     * @param method 需要绑定的函数。必须为非空的有效函数。
     * @param params 预定义的参数数组。
     * @return 返回一个新函数，该函数可以使用预定义参数在指定的作用域内执行。
     */
    public static function createWithParams(scope:Object, method:Function, params:Array):Function {
        if (method == null) {
            throw new Error("The provided method is undefined or null");
        }

        var cacheKey:String;
        var methodUID:String = String(Dictionary.getStaticUID(method));

        // [v2.1 FIX] 生成 paramsUID，添加长度前缀避免碰撞
        // 例如 ["a|b"] -> "1:a|b", ["a", "b"] -> "2:a|b"
        var paramsUID:String;
        var paramsLen:Number = params.length;

        if (paramsLen > 4) {
            // 参数数组长度超过 4 时，直接使用 getStaticUID
            paramsUID = String(paramsLen) + ":" + String(Dictionary.getStaticUID(params));
        } else if (paramsLen == 0) {
            paramsUID = "0:";
        } else if (paramsLen == 1) {
            var elem0 = params[0];
            if (typeof elem0 == "object" || typeof elem0 == "function") {
                paramsUID = "1:" + String(Dictionary.getStaticUID(elem0));
            } else {
                // [v2.1 NOTE] 简单类型使用 String() 是权宜之计，存在极低概率碰撞
                paramsUID = "1:" + String(elem0);
            }
        } else if (paramsLen == 2) {
            var elem0 = params[0];
            var elem1 = params[1];
            if ((typeof elem0 == "object" || typeof elem0 == "function") ||
                (typeof elem1 == "object" || typeof elem1 == "function")) {
                var uid0:String = (typeof elem0 == "object" || typeof elem0 == "function") ? String(Dictionary.getStaticUID(elem0)) : String(elem0);
                var uid1:String = (typeof elem1 == "object" || typeof elem1 == "function") ? String(Dictionary.getStaticUID(elem1)) : String(elem1);
                paramsUID = "2:" + uid0 + "|" + uid1;
            } else {
                paramsUID = "2:" + String(elem0) + "|" + String(elem1);
            }
        } else if (paramsLen == 3) {
            var elem0 = params[0];
            var elem1 = params[1];
            var elem2 = params[2];
            if ((typeof elem0 == "object" || typeof elem0 == "function") ||
                (typeof elem1 == "object" || typeof elem1 == "function") ||
                (typeof elem2 == "object" || typeof elem2 == "function")) {
                paramsUID = "3:" + String(Dictionary.getStaticUID(params));
            } else {
                paramsUID = "3:" + String(elem0) + "|" + String(elem1) + "|" + String(elem2);
            }
        } else { // paramsLen == 4
            var elem0 = params[0];
            var elem1 = params[1];
            var elem2 = params[2];
            var elem3 = params[3];
            if ((typeof elem0 == "object" || typeof elem0 == "function") ||
                (typeof elem1 == "object" || typeof elem1 == "function") ||
                (typeof elem2 == "object" || typeof elem2 == "function") ||
                (typeof elem3 == "object" || typeof elem3 == "function")) {
                paramsUID = "4:" + String(Dictionary.getStaticUID(params));
            } else {
                paramsUID = "4:" + String(elem0) + "|" + String(elem1) + "|" + String(elem2) + "|" + String(elem3);
            }
        }

        // 如果作用域为 null，使用全局缓存
        if (scope == null) {
            cacheKey = methodUID + "^" + paramsUID;

            var cachedFunctionWithParams:Function = cacheCreateWithParams[cacheKey];
            if (cachedFunctionWithParams != undefined) {
                return cachedFunctionWithParams;
            }

            var wrappedFunctionWithParams:Function = function() {
                var len:Number = params.length;
                if (len == 0) return method();
                else if (len == 1) return method(params[0]);
                else if (len == 2) return method(params[0], params[1]);
                else if (len == 3) return method(params[0], params[1], params[2]);
                else if (len == 4) return method(params[0], params[1], params[2], params[3]);
                else if (len == 5) return method(params[0], params[1], params[2], params[3], params[4]);
                else return method.apply(null, params);
            };

            cacheCreateWithParams[cacheKey] = wrappedFunctionWithParams;
            return wrappedFunctionWithParams;
        } else {
            // [v2.0 FIX] 将缓存存储在 scope 对象自身
            var scopeCache:Object = scope.__delegateCacheWithParams;
            if (scopeCache == null) {
                scopeCache = scope.__delegateCacheWithParams = {};
                _global.ASSetPropFlags(scope, ["__delegateCacheWithParams"], 1, true);
            }

            cacheKey = methodUID + "^" + paramsUID;

            var cachedFunctionWithParamsScope:Function = scopeCache[cacheKey];
            if (cachedFunctionWithParamsScope != undefined) {
                return cachedFunctionWithParamsScope;
            }

            var wrappedFunctionWithParamsScope:Function = function() {
                var len:Number = params.length;
                if (len == 0) return method.call(scope);
                else if (len == 1) return method.call(scope, params[0]);
                else if (len == 2) return method.call(scope, params[0], params[1]);
                else if (len == 3) return method.call(scope, params[0], params[1], params[2]);
                else if (len == 4) return method.call(scope, params[0], params[1], params[2], params[3]);
                else if (len == 5) return method.call(scope, params[0], params[1], params[2], params[3], params[4]);
                else return method.apply(scope, params);
            };

            scopeCache[cacheKey] = wrappedFunctionWithParamsScope;
            return wrappedFunctionWithParamsScope;
        }
    }

    /**
     * 清理全局缓存中的所有委托函数。
     *
     * [v2.0] 此方法现在只清理 scope==null 的全局缓存。
     */
    public static function clearCache():Void {
        for (var key:String in cacheCreate) {
            delete cacheCreate[key];
        }
        for (var key:String in cacheCreateWithParams) {
            delete cacheCreateWithParams[key];
        }
    }

    /**
     * [v2.0] 手动清理指定 scope 对象的委托缓存
     * 通常不需要调用此方法，因为缓存会随 scope 对象自动释放。
     *
     * @param scope 要清理缓存的对象
     */
    public static function clearScopeCache(scope:Object):Void {
        if (scope == null) return;
        if (scope.__delegateCache != null) {
            for (var key:String in scope.__delegateCache) {
                delete scope.__delegateCache[key];
            }
            delete scope.__delegateCache;
        }
        if (scope.__delegateCacheWithParams != null) {
            for (var key2:String in scope.__delegateCacheWithParams) {
                delete scope.__delegateCacheWithParams[key2];
            }
            delete scope.__delegateCacheWithParams;
        }
    }
}
