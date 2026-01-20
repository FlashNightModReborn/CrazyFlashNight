import org.flashNight.naki.DataStructures.Dictionary;  // 引入字典类
import org.flashNight.neur.Server.ServerManager;  
import org.flashNight.gesh.object.*;
import org.flashNight.gesh.string.*;

/**
 * Delegate 类用于创建绑定作用域的委托函数。
 *
 * 版本历史:
 * v2.0 (2026-01) - 内存泄漏修复
 *   [FIX] 将缓存从静态全局迁移到 scope 对象自身 (__delegateCache)
 *   [FIX] 当 scope 被 GC 时，其缓存自然释放，彻底解决内存泄漏
 *   [COMPAT] scope==null 的情况仍使用全局缓存（无泄漏风险）
 *   [PERF] 保持 O(1) 缓存查找性能
 */
class org.flashNight.neur.Event.Delegate {
    private static var cacheCreate:Object = {}; // [v2.0] 仅用于 scope==null 的全局作用域委托
    private static var cacheCreateWithParams:Object = {}; // [v2.0] 仅用于 scope==null 的带参数委托
    private static var isInitialized:Boolean = false; // 标记缓存是否已初始化

    /**
     * 初始化缓存。确保初始化只进行一次。
     * 为了防止重复初始化，isInitialized 标志位用于跟踪缓存是否已经初始化。
     */
    public static function init():Void {
        if (!isInitialized) {
            cacheCreate = {};
            cacheCreateWithParams = {};
            isInitialized = true;
            //trace("Delegate init!")
        }
        else
        {
            //trace("Delegate init again")
        }
    }

    /**
     * 创建一个函数委托，将方法绑定到指定的作用域 (scope)。
     * 如果已为相同的作用域和方法创建过委托，则返回缓存中的委托函数，以提高性能。
     *
     * @param scope 函数执行时 this 指向的对象。如果为 null，则函数将在全局作用域执行。
     * @param method 需要创建委托的方法。
     * @return 绑定了指定作用域的委托函数。
     * @throws Error 如果 method 为 null 或 undefined。
     */
    public static function create(scope:Object, method:Function):Function {
        // 确保类已初始化
        init();

        // 检查方法是否有效
        if (method == null) {
            throw new Error("The provided method is undefined or null");
        }

        // 获取方法的唯一标识符
        var methodUID:String = String(Dictionary.getStaticUID(method));

        // --- 处理 scope == null 的情况 ---
        if (scope == null) {
            // 当 scope 为 null 时，使用全局静态缓存（无泄漏风险，因为不持有对象引用）
            var cachedFunction:Function = cacheCreate[methodUID];
            if (cachedFunction != undefined) {
                return cachedFunction;
            }

            // 缓存未命中，创建一个新的委托函数
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
            // [v2.0 FIX] 将缓存存储在 scope 对象自身，而非全局静态缓存
            // 这样当 scope 被 GC 时，其缓存自然释放，彻底解决内存泄漏
            var scopeCache:Object = scope.__delegateCache;
            if (scopeCache == null) {
                scopeCache = scope.__delegateCache = {};
                // 设置 __delegateCache 为不可枚举，避免污染 for..in 循环
                _global.ASSetPropFlags(scope, ["__delegateCache"], 1, true);
            }

            // 检查 scope 的缓存中是否已存在该方法的委托
            var cachedFunctionScope:Function = scopeCache[methodUID];
            if (cachedFunctionScope != undefined) {
                return cachedFunctionScope;
            }

            // 缓存未命中，创建一个新的委托函数
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

            // 存入 scope 的缓存
            scopeCache[methodUID] = wrappedFunctionScope;
            return wrappedFunctionScope;
        }
    }

    /**
     * 创建一个带有预定义参数的委托函数。
     * 
     * @param scope 将作为 `this` 绑定的对象。如果为 `null`，则函数将在全局作用域中执行。
     * @param method 需要绑定的函数。必须为非空的有效函数。
     * @param params 预定义的参数数组。
     * @return 返回一个新函数，该函数可以使用预定义参数在指定的作用域内执行。
     * 
     * 性能优化说明：
     * 1. 将预定义参数通过缓存机制减少重复创建。
     * 2. 手动展开参数传递的过程，减少 apply 的性能开销。
     */
    public static function createWithParams(scope:Object, method:Function, params:Array):Function {
        init();  // 确保缓存已初始化

        // 检查 method 是否为 null，防止无效的函数绑定
        if (method == null) {
            throw new Error("The provided method is undefined or null");
        }

        var cacheKey:String;
        var loccache = cacheCreateWithParams; // 本地化缓存对象，减少全局访问的开销

        // 使用 Dictionary 静态方法生成 methodUID 和 paramsUID
        var methodUID:String = String(Dictionary.getStaticUID(method));

        // 生成 paramsUID 的优化逻辑
        var paramsUID:String;
        if (params.length > 4) {
            // 当参数数组长度超过 4 时，直接使用 Dictionary.getStaticUID 来生成该数组的唯一标识符
            // 这样可以简化处理，并避免为每个参数分别生成 UID 的额外开销。
            paramsUID = String(Dictionary.getStaticUID(params));
        } else {
            // 如果参数数组的长度小于等于 4，那么可以手动展开参数处理逻辑
            // 目的是通过拼接每个参数的 UID 或其本身的字符串值来生成一个唯一的缓存键
            // 这样可以避免直接使用 getStaticUID 而带来的性能开销，尤其是对于简单类型的参数

            if (params.length == 0) {
                // 如果参数数组为空，那么直接返回空字符串作为 paramsUID
                paramsUID = ""; // 空数组
            }
            else if (params.length == 1) {
                // 如果参数数组中只有一个元素
                var elem0 = params[0];
                if (typeof elem0 == "object" || typeof elem0 == "function") {
                    // 如果该元素是对象或函数，使用 Dictionary.getStaticUID 获取它的唯一标识符
                    paramsUID = String(Dictionary.getStaticUID(elem0));
                } else {
                    // 如果该元素是简单类型（如字符串或数字），直接使用它的字符串值作为 UID
                    paramsUID = String(elem0);
                }
            }
            else if (params.length == 2) {
                // 如果参数数组中有两个元素
                var elem0 = params[0];
                var elem1 = params[1];
                if ((typeof elem0 == "object" || typeof elem0 == "function") ||
                    (typeof elem1 == "object" || typeof elem1 == "function")) {
                    // 如果其中任何一个元素是对象或函数，则为每个对象或函数单独生成 UID
                    // 使用 "|" 分隔符将两个 UID 拼接，保证生成的缓存键唯一且明确
                    var uid0:String = (typeof elem0 == "object" || typeof elem0 == "function") ? String(Dictionary.getStaticUID(elem0)) : String(elem0);
                    var uid1:String = (typeof elem1 == "object" || typeof elem1 == "function") ? String(Dictionary.getStaticUID(elem1)) : String(elem1);
                    paramsUID = uid0 + "|" + uid1;
                } else {
                    // 如果两个元素都是简单类型，则直接拼接它们的字符串值
                    paramsUID = String(elem0) + "|" + String(elem1);
                }
            }
            else if (params.length == 3) {
                // 如果参数数组中有三个元素
                var elem0 = params[0];
                var elem1 = params[1];
                var elem2 = params[2];
                if ((typeof elem0 == "object" || typeof elem0 == "function") ||
                    (typeof elem1 == "object" || typeof elem1 == "function") ||
                    (typeof elem2 == "object" || typeof elem2 == "function")) {
                    // 如果其中任何一个元素是对象或函数，直接使用 getStaticUID 获取整个数组的 UID
                    // 这样可以简化逻辑并保持高性能
                    paramsUID = String(Dictionary.getStaticUID(params));
                } else {
                    // 如果三个元素都是简单类型，则手动拼接它们的字符串值
                    paramsUID = String(elem0) + "|" + String(elem1) + "|" + String(elem2);
                }
            }
            else if (params.length == 4) {
                // 如果参数数组中有四个元素
                var elem0 = params[0];
                var elem1 = params[1];
                var elem2 = params[2];
                var elem3 = params[3];
                if ((typeof elem0 == "object" || typeof elem0 == "function") ||
                    (typeof elem1 == "object" || typeof elem1 == "function") ||
                    (typeof elem2 == "object" || typeof elem2 == "function") ||
                    (typeof elem3 == "object" || typeof elem3 == "function")) {
                    // 如果其中任何一个元素是对象或函数，直接为整个数组生成 UID
                    // 通过 getStaticUID 来简化操作
                    paramsUID = String(Dictionary.getStaticUID(params));
                } else {
                    // 如果四个元素都是简单类型，则拼接它们的字符串值作为 UID
                    paramsUID = String(elem0) + "|" + String(elem1) + "|" + String(elem2) + "|" + String(elem3);
                }
            }
            else {
                // 其他情况（理论上不会达到这里，因为已经处理了 params.length <= 4 和 > 4）
                // 如果长度超出，使用 getStaticUID 确保生成唯一标识符
                paramsUID = String(Dictionary.getStaticUID(params));
            }
        }



        // 如果作用域为 null，则函数将在全局作用域中执行
        if (scope == null) {
            cacheKey = methodUID + "^" + paramsUID;  // 组合方法 UID 和参数 UID 生成缓存键

            // 尝试从全局缓存中获取已存在的委托函数
            var cachedFunctionWithParams:Function = cacheCreateWithParams[cacheKey];
            if (cachedFunctionWithParams != undefined) {
                return cachedFunctionWithParams;
            }

            // 创建新的委托函数，传递预定义参数并针对参数数量优化调用逻辑
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

            // 将新创建的委托函数缓存到全局缓存
            cacheCreateWithParams[cacheKey] = wrappedFunctionWithParams;
            return wrappedFunctionWithParams;
        } else {
            // [v2.0 FIX] 将缓存存储在 scope 对象自身，而非全局静态缓存
            var scopeCache:Object = scope.__delegateCacheWithParams;
            if (scopeCache == null) {
                scopeCache = scope.__delegateCacheWithParams = {};
                _global.ASSetPropFlags(scope, ["__delegateCacheWithParams"], 1, true);
            }

            // 使用 methodUID + paramsUID 作为缓存键
            cacheKey = methodUID + "^" + paramsUID;

            // 尝试从 scope 的缓存中获取已存在的委托函数
            var cachedFunctionWithParamsScope:Function = scopeCache[cacheKey];
            if (cachedFunctionWithParamsScope != undefined) {
                return cachedFunctionWithParamsScope;
            }

            // 创建新的委托函数，绑定作用域并传递预定义参数
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

            // 存入 scope 的缓存
            scopeCache[cacheKey] = wrappedFunctionWithParamsScope;
            return wrappedFunctionWithParamsScope;
        }
    }

    /**
     * 清理全局缓存中的所有委托函数。
     *
     * [v2.0] 此方法现在只清理 scope==null 的全局缓存。
     * scope!=null 的委托缓存存储在各 scope 对象的 __delegateCache 属性中，
     * 当 scope 对象被 GC 时自动释放，无需手动清理。
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
     * 仅在需要提前释放内存时使用。
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