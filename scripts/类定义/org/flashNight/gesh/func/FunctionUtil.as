// File: org/flashNight/gesh/func/FunctionUtil.as
class org.flashNight.gesh.func.FunctionUtil {

    // 静态方法：添加重载方法
    public static function addMethod(func:Function):Function {
        // 检查至少需要两个参数：至少一个参数类型和一个方法函数
        if (arguments.length < 2) {
            throw new Error("addMethod requires at least two arguments: param types and the method function.");
        }

        // 获取参数类型和执行函数
        var numArgs:Number = arguments.length;
        var method:Function = arguments[numArgs - 1];
        var paramTypes:Array = [];

        // 手动通过索引提取参数类型，避免使用 pop/push
        for (var i:Number = 1; i < numArgs - 1; i++) {
            paramTypes.push(arguments[i].toLowerCase());
        }

        // 初始化方法存储数组
        if (func.__methods == undefined) {
            func.__methods = [];

            // 保存原始函数
            func.__originalFunction = func;

            // 创建一个代理函数来处理重载
            var dispatcher:Function = function() {
                trace("[Dispatcher] Called with arguments: " + arguments);

                // 手动通过索引将 arguments 转换为真正的 Array
                var args:Array = [];
                for (var j:Number = 0; j < arguments.length; j++) {
                    trace("[Dispatcher] Argument " + j + ": " + arguments[j]);
                    args[j] = arguments[j];
                }

                var methods:Array = arguments.callee.__methods;

                // 优先级 1：完全匹配参数数量和类型
                for (var k:Number = 0; k < methods.length; k++) {
                    var methodObj:Object = methods[k];
                    if (methodObj.paramTypes.length == args.length) {
                        var isExactMatch:Boolean = true;
                        for (var m:Number = 0; m < args.length; m++) {
                            var expectedType:String = methodObj.paramTypes[m];
                            var actualType:String;
                            if (args[m] === null || args[m] === undefined) {
                                actualType = "undefined";
                            } else {
                                actualType = typeof(args[m]).toLowerCase();
                            }

                            trace("[matchArgs] Expected type: " + expectedType + ", Actual type: " + actualType + " (" + args[m] + ") at position " + m);
                            if (expectedType != actualType) {
                                isExactMatch = false;
                                trace("[matchArgs] Type mismatch at position " + m);
                                break;
                            }
                        }
                        if (isExactMatch) {
                            trace("[Dispatcher] Exact match found. Calling overloaded function.");
                            return methodObj.func.apply(this, args);
                        }
                    }
                }

                // 优先级 2：仅匹配参数数量
                for (var k2:Number = 0; k2 < methods.length; k2++) {
                    var methodObj2:Object = methods[k2];
                    if (methodObj2.paramTypes.length == args.length) {
                        trace("[Dispatcher] Parameter count match found. Calling overloaded function.");
                        return methodObj2.func.apply(this, args);
                    }
                }

                // 优先级 3：调用原始函数
                if (arguments.callee.__originalFunction != null) {
                    trace("[Dispatcher] No matching overloaded method found. Calling original function.");
                    return arguments.callee.__originalFunction.apply(this, args);
                } else {
                    throw new Error("No matching method found for the given arguments: " + args);
                }
            };

            // 复制原函数的属性到代理函数
            for (var prop in func) {
                dispatcher[prop] = func[prop];
            }
            dispatcher.__methods = func.__methods;
            dispatcher.__originalFunction = func.__originalFunction;

            // 将代理函数赋值回 func
            func = dispatcher;
        }

        // 添加新的重载方法
        func.__methods.push({ paramTypes: paramTypes, func: method });
        trace("[FunctionUtil] Added method with paramTypes: " + paramTypes.join(", "));

        // 返回修改后的函数
        return func;
    }

    // 辅助方法：匹配参数类型和数量
    private static function matchArgs(args:Array, paramTypes:Array):Boolean {
        trace("[matchArgs] Matching args: " + args + " with paramTypes: " + paramTypes);
        if (args.length != paramTypes.length) {
            trace("[matchArgs] Argument length mismatch.");
            return false;
        }
        for (var i:Number = 0; i < args.length; i++) {
            var expectedType:String = paramTypes[i].toLowerCase();
            var actualType:String;
            if (args[i] === null || args[i] === undefined) {
                actualType = "undefined";
            } else {
                actualType = typeof(args[i]).toLowerCase();
            }
            trace("[matchArgs] Expected type: " + expectedType + ", Actual type: " + actualType + " (" + args[i] + ")");
            if (actualType != expectedType) {
                trace("[matchArgs] Type mismatch at position " + i);
                return false;
            }
        }
        return true;
    }
}
