// 文件: org/flashNight/gesh/func/FunctionUtil.as
class org.flashNight.gesh.func.FunctionUtil {
    
    // 调试模式标志，设置为 true 时会输出调试信息
    public static var DEBUG_MODE:Boolean = false;
    
    /**
     * 静态方法：添加重载方法
     * @param func 原始函数
     * @return 修改后的函数，支持重载
     * @throws Error 当参数不足时抛出错误
     */
    public static function addMethod(func:Function):Function {
        // 确保至少有两个参数：参数类型和方法函数
        if (arguments.length < 2) {
            throw new Error("addMethod 需要至少两个参数：参数类型和方法函数。");
        }

        var numArgs:Number = arguments.length;
        var method:Function = arguments[numArgs - 1]; // 获取最后一个参数作为方法函数
        var paramTypes:Array = [];

        // 提取参数类型，并转换为小写
        for (var i:Number = 1; i < numArgs - 1; i++) {
            paramTypes.push(arguments[i].toLowerCase());
        }

        // 如果函数尚未有重载方法，则初始化重载方法存储数组
        if (func.__methods == undefined) {
            func.__methods = [];

            // 保存原始函数，以便在没有匹配重载时调用
            func.__originalFunction = func;

            // 创建一个分派器函数，用于处理重载调用
            var dispatcher:Function = function() {
                if (FunctionUtil.DEBUG_MODE) {
                    trace("[Dispatcher] 调用参数: " + arguments);
                }

                var methods:Array = arguments.callee.__methods; // 获取所有重载方法
                var argsLength:Number = arguments.length; // 获取传入参数的数量
                var methodFound:Boolean = false; // 标记是否找到匹配的方法

                // 优先级1：精确匹配参数数量和类型
                for (var k:Number = 0; k < methods.length; k++) {
                    var methodObj:Object = methods[k];
                    if (methodObj.paramTypes.length == argsLength) {
                        if (FunctionUtil.matchArgs(arguments, methodObj.paramTypes)) {
                            if (FunctionUtil.DEBUG_MODE) {
                                trace("[Dispatcher] 找到精确匹配。调用重载方法。");
                            }
                            methodFound = true;
                            return methodObj.func.apply(this, arguments); // 调用匹配的重载方法
                        }
                    }
                }

                // 优先级2：仅匹配参数数量
                if (!methodFound) {
                    for (var k2:Number = 0; k2 < methods.length; k2++) {
                        var methodObj2:Object = methods[k2];
                        if (methodObj2.paramTypes.length == argsLength) {
                            if (FunctionUtil.DEBUG_MODE) {
                                trace("[Dispatcher] 找到参数数量匹配。调用重载方法。");
                            }
                            methodFound = true;
                            return methodObj2.func.apply(this, arguments); // 调用参数数量匹配的重载方法
                        }
                    }
                }

                // 优先级3：未找到匹配的方法，调用原始函数
                if (!methodFound && arguments.callee.__originalFunction != null) {
                    if (FunctionUtil.DEBUG_MODE) {
                        trace("[Dispatcher] 未找到匹配的重载方法。调用原始函数。");
                    }
                    return arguments.callee.__originalFunction.apply(this, arguments);
                } else {
                    throw new Error("未找到匹配的方法，无法处理给定的参数。");
                }
            };

            // 复制原始函数的属性到分派器函数
            for (var prop in func) {
                dispatcher[prop] = func[prop];
            }
            dispatcher.__methods = func.__methods; // 复制重载方法数组
            dispatcher.__originalFunction = func.__originalFunction; // 复制原始函数

            // 用分派器函数替换原始函数
            func = dispatcher;
        }

        // 将新的重载方法添加到方法存储数组中
        func.__methods.push({ paramTypes: paramTypes, func: method });
        if (FunctionUtil.DEBUG_MODE) {
            trace("[FunctionUtil] 添加重载方法，参数类型: " + paramTypes.join(", "));
        }

        // 返回修改后的函数
        return func;
    }

    /**
     * 辅助方法：匹配参数类型与预期类型
     * @param args 实际传入的参数对象
     * @param paramTypes 预期的参数类型数组
     * @return 如果匹配成功则返回 true，否则返回 false
     */
    public static function matchArgs(args:Object, paramTypes:Array):Boolean {
        if (FunctionUtil.DEBUG_MODE) {
            trace("[matchArgs] 匹配参数类型: " + paramTypes);
        }

        // 检查参数数量是否一致
        if (args.length != paramTypes.length) {
            if (FunctionUtil.DEBUG_MODE) {
                trace("[matchArgs] 参数数量不匹配。");
            }
            return false;
        }

        // 遍历每个参数，检查其类型是否匹配
        for (var i:Number = 0; i < args.length; i++) {
            var expectedType:String = paramTypes[i];
            var actualType:String;

            var arg = args[i];

            // 增强型类型检测
            if (arg === null) {
                actualType = "null";
            } else if (arg === undefined) {
                actualType = "undefined";
            } else if (typeof(arg) === "object") {
                if (arg instanceof Array) {
                    actualType = "array";
                } else {
                    actualType = "object";
                }
            } else {
                actualType = typeof(arg);
            }

            // 特殊处理 NaN，将其类型设为 'nan'
            if (actualType == "number" && isNaN(arg)) {
                actualType = "nan";
            }

            if (FunctionUtil.DEBUG_MODE) {
                trace("[matchArgs] 预期类型: " + expectedType + ", 实际类型: " + actualType + " (" + arg + ")");
            }

            // 允许 'null' 匹配 'object' 类型
            if (expectedType == "object" && actualType == "null") {
                actualType = "object";
            }

            // 比较实际类型与预期类型
            if (actualType != expectedType) {
                if (FunctionUtil.DEBUG_MODE) {
                    trace("[matchArgs] 类型不匹配，位置: " + i);
                }
                return false;
            }
        }

        // 所有参数类型匹配成功
        return true;
    }
}
