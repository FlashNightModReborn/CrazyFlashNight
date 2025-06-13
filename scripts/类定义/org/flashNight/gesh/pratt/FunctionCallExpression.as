import org.flashNight.gesh.pratt.*;

// 函数调用表达式
class org.flashNight.gesh.pratt.FunctionCallExpression extends Expression {
    public var functionExpr:Expression;
    public var arguments:Array;
    
    public function FunctionCallExpression(funcExpr:Expression, args:Array) {
        super("FUNCTION_CALL");
        functionExpr = funcExpr;
        arguments = args || [];
    }
    
    public function evaluate(context:Object) {
        // 评估所有参数
        var evaluatedArgs:Array = [];
        for (var i:Number = 0; i < arguments.length; i++) {
            evaluatedArgs.push(arguments[i].evaluate(context));
        }
        
        // 处理不同类型的函数调用
        if (functionExpr instanceof IdentifierExpression) {
            var funcName:String = IdentifierExpression(functionExpr).name;
            return _callBuiltinFunction(funcName, evaluatedArgs, context);
        } else if (functionExpr instanceof PropertyAccessExpression) {
            var propAccess:PropertyAccessExpression = PropertyAccessExpression(functionExpr);
            return _callObjectMethod(propAccess, evaluatedArgs, context);
        }
        
        throw new Error("Invalid function call target");
    }
    
    private function _callBuiltinFunction(funcName:String, args:Array, context:Object) {
        // 检查上下文中的自定义函数
        if (context && context[funcName] && typeof context[funcName] == "function") {
            var func:Function = context[funcName];
            return func.apply(null, args);
        }
        
        // 内置函数
        switch (funcName) {
            case "isNaN": return isNaN(Number(args[0]));
            case "parseInt": return parseInt(String(args[0]), args[1] || 10);
            case "parseFloat": return parseFloat(String(args[0]));
            case "String": return String(args[0]);
            case "Number": return Number(args[0]);
            case "Boolean": return Boolean(args[0]);
            default:
                throw new Error("Unknown function: " + funcName);
        }
    }
    
    private function _callObjectMethod(propAccess:PropertyAccessExpression, args:Array, context:Object) {
        var obj = propAccess.object.evaluate(context);
        var methodName:String = propAccess.property;
        
        // Math对象方法
        if (obj === Math || (typeof obj == "object" && obj.constructor === Math)) {
            switch (methodName) {
                case "max": return Math.max.apply(null, args);
                case "min": return Math.min.apply(null, args);
                case "abs": return Math.abs(Number(args[0]));
                case "sqrt": return Math.sqrt(Number(args[0]));
                case "pow": return Math.pow(Number(args[0]), Number(args[1]));
                case "floor": return Math.floor(Number(args[0]));
                case "ceil": return Math.ceil(Number(args[0]));
                case "round": return Math.round(Number(args[0]));
                default:
                    throw new Error("Unknown Math method: " + methodName);
            }
        }
        
        // 通用对象方法调用
        if (obj && typeof obj[methodName] == "function") {
            return obj[methodName].apply(obj, args);
        }
        
        throw new Error("Method '" + methodName + "' not found on object");
    }
    
    public function toString():String {
        var argStr:String = "";
        for (var i:Number = 0; i < arguments.length; i++) {
            if (i > 0) argStr += ", ";
            argStr += arguments[i].toString();
        }
        return "[FunctionCall:" + functionExpr.toString() + "(" + argStr + ")]";
    }
}