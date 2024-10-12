import org.flashNight.naki.DataStructures.Dictionary;  // 引入字典类

class org.flashNight.neur.Event.Delegate {
    private static var cacheCreate:Object = {}; // 不带预定义参数的委托函数缓存
    private static var cacheCreateWithParams:Object = {}; // 带预定义参数的委托函数缓存
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
        }
    }

    /**
     * 创建一个委托函数，将指定方法绑定到给定的作用域。
     * 该方法通过缓存机制优化委托函数的创建，避免重复生成相同的委托。
     * 
     * @param scope 作用域对象。如果为 `null`，则函数将在全局作用域中执行。
     * @param method 需要绑定的函数。必须为非空的有效函数。
     * @return 返回一个新函数，可以带参数调用，并在指定的作用域内执行。
     * 
     * 性能优化说明：
     * 1. 使用 `Dictionary.getStaticUID` 为函数和作用域生成唯一的 UID，避免重复计算。
     * 2. 缓存委托函数，当相同作用域和方法组合再次使用时，直接返回缓存中的委托函数。
     * 3. 对于参数数量较少的场景，手动展开参数调用，避免使用 apply 调用带来的性能损耗。
     */
    public static function create(scope:Object, method:Function):Function {
        init();  // 确保缓存已初始化

        // 检查 method 是否为 null，防止无效的函数绑定
        if (method == null) {
            throw new Error("The provided method is undefined or null");
        }

        var cacheKey:String; 
        var loccache = cacheCreate; // 本地化缓存对象，减少全局访问的开销

        // 使用 Dictionary 静态方法生成 method 的唯一标识符 UID
        var methodUID:String = String(Dictionary.getStaticUID(method));

        // 如果作用域为 null，则函数将在全局作用域中执行
        if (scope == null) {
            cacheKey = methodUID;  // 使用方法的 UID 作为缓存键

            // 尝试从缓存中获取已存在的委托函数
            var cachedFunction:Function = loccache[cacheKey];
            if (cachedFunction != undefined) {
                return cachedFunction;
            }

            // 创建新的委托函数，针对不同参数数量优化调用逻辑
            var wrappedFunction:Function = function() {
                var len:Number = arguments.length;
                if (len == 0) return method();
                else if (len == 1) return method(arguments[0]);
                else if (len == 2) return method(arguments[0], arguments[1]);
                else if (len == 3) return method(arguments[0], arguments[1], arguments[2]);
                else if (len == 4) return method(arguments[0], arguments[1], arguments[2], arguments[3]);
                else if (len == 5) return method(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4]);
                else return method.apply(null, arguments);  // 对于超过5个参数的情况，使用 apply 调用
            };

            // 将新创建的委托函数缓存起来，供后续调用复用
            loccache[cacheKey] = wrappedFunction;
            return wrappedFunction;
        } else {
            // 为作用域生成唯一的 UID，并与方法 UID 组合生成缓存键
            var scopeUID:String = String(Dictionary.getStaticUID(scope));
            cacheKey = scopeUID + "|" + methodUID;  // 将作用域和方法的 UID 组合成缓存键

            // 尝试从缓存中获取已存在的委托函数
            var cachedFunctionScope:Function = loccache[cacheKey];
            if (cachedFunctionScope != undefined) {
                return cachedFunctionScope;
            }

            // 创建新的委托函数，绑定到指定的作用域并针对参数数量优化调用逻辑
            var wrappedFunctionScope:Function = function() {
                var len:Number = arguments.length;
                if (len == 0) return method.call(scope);
                else if (len == 1) return method.call(scope, arguments[0]);
                else if (len == 2) return method.call(scope, arguments[0], arguments[1]);
                else if (len == 3) return method.call(scope, arguments[0], arguments[1], arguments[2]);
                else if (len == 4) return method.call(scope, arguments[0], arguments[1], arguments[2], arguments[3]);
                else if (len == 5) return method.call(scope, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4]);
                else return method.apply(scope, arguments);  // 对于超过5个参数的情况，使用 apply 调用
            };

            // 将新创建的委托函数缓存起来，供后续调用复用
            loccache[cacheKey] = wrappedFunctionScope;
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
        var paramsUID:String = params.toString();  // 使用 `toString()` 生成唯一的参数组合标识符

        // 如果作用域为 null，则函数将在全局作用域中执行
        if (scope == null) {
            cacheKey = methodUID + "|" + paramsUID;  // 组合方法 UID 和参数 UID 生成缓存键

            // 尝试从缓存中获取已存在的委托函数
            var cachedFunctionWithParams:Function = loccache[cacheKey];
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
                else return method.apply(null, params);  // 对于超过5个参数的情况，使用 apply 调用
            };

            // 将新创建的委托函数缓存起来，供后续调用复用
            loccache[cacheKey] = wrappedFunctionWithParams;
            return wrappedFunctionWithParams;
        } else {
            // 为作用域生成 UID，并与 methodUID 和 paramsUID 组合
            var scopeUID:Number = Dictionary.getStaticUID(scope);
            // 使用位运算生成缓存键，将 scopeUID、methodUID 和 paramsUID 组合
            cacheKey = String((scopeUID << 24) | (methodUID << 8) | (paramsUID & 0xFF));

            // 尝试从缓存中获取已存在的委托函数
            var cachedFunctionWithParamsScope:Function = loccache[cacheKey];
            if (cachedFunctionWithParamsScope != undefined) {
                return cachedFunctionWithParamsScope;
            }

            // 创建新的委托函数，绑定作用域并传递预定义参数，针对参数数量优化调用逻辑
            var wrappedFunctionWithParamsScope:Function = function() {
                var len:Number = params.length;
                if (len == 0) return method.call(scope);
                else if (len == 1) return method.call(scope, params[0]);
                else if (len == 2) return method.call(scope, params[0], params[1]);
                else if (len == 3) return method.call(scope, params[0], params[1], params[2]);
                else if (len == 4) return method.call(scope, params[0], params[1], params[2], params[3]);
                else if (len == 5) return method.call(scope, params[0], params[1], params[2], params[3], params[4]);
                else return method.apply(scope, params);  // 对于超过5个参数的情况，使用 apply 调用
            };

            // 将新创建的委托函数缓存起来，供后续调用复用
            loccache[cacheKey] = wrappedFunctionWithParamsScope;
            return wrappedFunctionWithParamsScope;
        }
    }

    /**
     * 清理缓存中的所有委托函数。
     * 该方法用于在适当的时机清空缓存，防止内存泄漏。
     */
    public static function clearCache():Void {
        for (var key:String in cacheCreate) {
            delete cacheCreate[key];
        }
        for (var key:String in cacheCreateWithParams) {
            delete cacheCreateWithParams[key];
        }
    }
}
