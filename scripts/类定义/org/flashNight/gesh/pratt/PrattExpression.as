import org.flashNight.gesh.pratt.*;

/**
 * 统一的表达式类 - 合并所有表达式类型
 * 使用type字段区分不同的表达式类型
 */
class org.flashNight.gesh.pratt.PrattExpression {
    // 表达式类型常量
    public static var BINARY:String = "BINARY";
    public static var UNARY:String = "UNARY";
    public static var TERNARY:String = "TERNARY";
    public static var LITERAL:String = "LITERAL";
    public static var IDENTIFIER:String = "IDENTIFIER";
    public static var FUNCTION_CALL:String = "FUNCTION_CALL";
    public static var PROPERTY_ACCESS:String = "PROPERTY_ACCESS";
    public static var ARRAY_ACCESS:String = "ARRAY_ACCESS";
    
    // 通用属性
    public var type:String;
    
    // 根据不同类型使用的属性
    public var value;              // 用于LITERAL
    public var name:String;        // 用于IDENTIFIER
    public var left:PrattExpression;   // 用于BINARY, TERNARY等
    public var right:PrattExpression;  // 用于BINARY
    public var operator:String;    // 用于BINARY, UNARY
    public var operand:PrattExpression;    // 用于UNARY
    public var condition:PrattExpression;  // 用于TERNARY
    public var trueExpr:PrattExpression;   // 用于TERNARY
    public var falseExpr:PrattExpression;  // 用于TERNARY
    public var object:PrattExpression;     // 用于PROPERTY_ACCESS
    public var property:String;    // 用于PROPERTY_ACCESS
    public var array:PrattExpression;      // 用于ARRAY_ACCESS
    public var index:PrattExpression;      // 用于ARRAY_ACCESS
    public var functionExpr:PrattExpression;  // 用于FUNCTION_CALL
    public var arguments:Array;    // 用于FUNCTION_CALL
    
    public function PrattExpression(exprType:String) {
        type = exprType;
    }
    
    // 静态工厂方法
    public static function literal(literalValue):PrattExpression {
        var expr:PrattExpression = new PrattExpression(LITERAL);
        expr.value = literalValue;
        return expr;
    }
    
    public static function identifier(identifierName:String):PrattExpression {
        var expr:PrattExpression = new PrattExpression(IDENTIFIER);
        expr.name = identifierName;
        return expr;
    }
    
    public static function binary(leftExpr:PrattExpression, op:String, rightExpr:PrattExpression):PrattExpression {
        var expr:PrattExpression = new PrattExpression(BINARY);
        expr.left = leftExpr;
        expr.operator = op;
        expr.right = rightExpr;
        return expr;
    }
    
    public static function unary(op:String, operandExpr:PrattExpression):PrattExpression {
        var expr:PrattExpression = new PrattExpression(UNARY);
        expr.operator = op;
        expr.operand = operandExpr;
        return expr;
    }
    
    public static function ternary(cond:PrattExpression, trueExp:PrattExpression, falseExp:PrattExpression):PrattExpression {
        var expr:PrattExpression = new PrattExpression(TERNARY);
        expr.condition = cond;
        expr.trueExpr = trueExp;
        expr.falseExpr = falseExp;
        return expr;
    }
    
    public static function functionCall(funcExpr:PrattExpression, args:Array):PrattExpression {
        var expr:PrattExpression = new PrattExpression(FUNCTION_CALL);
        expr.functionExpr = funcExpr;
        expr.arguments = args || [];
        return expr;
    }
    
    public static function propertyAccess(obj:PrattExpression, prop:String):PrattExpression {
        var expr:PrattExpression = new PrattExpression(PROPERTY_ACCESS);
        expr.object = obj;
        expr.property = prop;
        return expr;
    }
    
    public static function arrayAccess(arr:PrattExpression, idx:PrattExpression):PrattExpression {
        var expr:PrattExpression = new PrattExpression(ARRAY_ACCESS);
        expr.array = arr;
        expr.index = idx;
        return expr;
    }
    
    // 求值方法
    public function evaluate(context:Object) {
        switch (type) {
            case LITERAL:
                return value;
                
            case IDENTIFIER:
                if (context && context[name] !== undefined) {
                    return context[name];
                }
                throw new Error("Undefined variable: " + name);
                
            case BINARY:
                return _evaluateBinary(context);
                
            case UNARY:
                return _evaluateUnary(context);
                
            case TERNARY:
                var condVal = condition.evaluate(context);
                return Boolean(condVal) ? trueExpr.evaluate(context) : falseExpr.evaluate(context);
                
            case FUNCTION_CALL:
                return _evaluateFunctionCall(context);
                
            case PROPERTY_ACCESS:
                return _evaluatePropertyAccess(context);
                
            case ARRAY_ACCESS:
                return _evaluateArrayAccess(context);
                
            default:
                throw new Error("Unknown expression type: " + type);
        }
    }
    
    private function _evaluateBinary(context:Object) {
        var leftVal = left.evaluate(context);
        var rightVal = right.evaluate(context);
        
        switch (operator) {
            case "+": return Number(leftVal) + Number(rightVal);
            case "-": return Number(leftVal) - Number(rightVal);
            case "*": return Number(leftVal) * Number(rightVal);
            case "/": 
                if (Number(rightVal) == 0) throw new Error("Division by zero");
                return Number(leftVal) / Number(rightVal);
            case "%": return Number(leftVal) % Number(rightVal);
            case "**": return Math.pow(Number(leftVal), Number(rightVal));
            case "==": return leftVal == rightVal;
            case "!=": return leftVal != rightVal;
            case "===": return leftVal === rightVal;
            case "!==": return leftVal !== rightVal;
            case "<": return Number(leftVal) < Number(rightVal);
            case ">": return Number(leftVal) > Number(rightVal);
            case "<=": return Number(leftVal) <= Number(rightVal);
            case ">=": return Number(leftVal) >= Number(rightVal);
            case "&&": return Boolean(leftVal) && Boolean(rightVal);
            case "||": return Boolean(leftVal) || Boolean(rightVal);
            case "??": 
                return (leftVal == null || leftVal == undefined) ? rightVal : leftVal;
            default:
                throw new Error("Unknown binary operator: " + operator);
        }
    }
    
    private function _evaluateUnary(context:Object) {
        var operandVal = operand.evaluate(context);
        
        switch (operator) {
            case "+": return Number(operandVal);
            case "-": return -Number(operandVal);
            case "!": return !Boolean(operandVal);
            case "typeof": return typeof operandVal;
            default:
                throw new Error("Unknown unary operator: " + operator);
        }
    }
    
    private function _evaluateFunctionCall(context:Object) {
        // 评估所有参数
        var evaluatedArgs:Array = [];
        
        // ================== FIX START ==================
        // 将 'arguments' 修改为 'this.arguments'
        for (var i:Number = 0; i < this.arguments.length; i++) {
            evaluatedArgs.push(this.arguments[i].evaluate(context));
        }
        // =================== FIX END ===================
        
        // 处理不同类型的函数调用
        if (functionExpr.type == IDENTIFIER) {
            var funcName:String = functionExpr.name;

            // 改进：统一通过上下文或对象方法调用
            var target;
            if (context && context[funcName] !== undefined && typeof context[funcName] == "function") {
                target = context;
            } else {
                // 对于 Math.xxx() 这种形式，由 _callObjectMethod 处理
                throw new Error("Unknown function: " + funcName);
            }
            return target[funcName].apply(target, evaluatedArgs);

        } else if (functionExpr.type == PROPERTY_ACCESS) {
            return _callObjectMethod(functionExpr, evaluatedArgs, context);
        }
        
        throw new Error("Invalid function call target");
    }
    
    private function _callObjectMethod(propAccess:PrattExpression, args:Array, context:Object) {
        var obj = propAccess.object.evaluate(context);
        var methodName:String = propAccess.property;
        
        // 通用对象方法调用（这也包括了Math对象）
        if (obj && typeof obj[methodName] == "function") {
            return obj[methodName].apply(obj, args);
        }
        
        throw new Error("Method '" + methodName + "' not found on object");
    }

    
    private function _evaluatePropertyAccess(context:Object) {
        var objVal = object.evaluate(context);
        
        if (objVal == null || objVal == undefined) {
            throw new Error("Cannot access property '" + property + "' of null or undefined");
        }
        
        return objVal[property];
    }
    
    private function _evaluateArrayAccess(context:Object) {
        var arrayVal = array.evaluate(context);
        var indexVal = index.evaluate(context);
        
        if (arrayVal == null || arrayVal == undefined) {
            throw new Error("Cannot access index of null or undefined");
        }
        
        return arrayVal[indexVal];
    }
    
    // toString方法用于调试
    public function toString():String {
        switch (type) {
            case LITERAL:
                return "[Literal:" + value + "]";
            case IDENTIFIER:
                return "[Identifier:" + name + "]";
            case BINARY:
                return "[Binary:" + left.toString() + " " + operator + " " + right.toString() + "]";
            case UNARY:
                return "[Unary:" + operator + operand.toString() + "]";
            case TERNARY:
                return "[Ternary:" + condition.toString() + " ? " + trueExpr.toString() + " : " + falseExpr.toString() + "]";
            case FUNCTION_CALL:
                var argStr:String = "";
                for (var i:Number = 0; i < arguments.length; i++) {
                    if (i > 0) argStr += ", ";
                    argStr += arguments[i].toString();
                }
                return "[FunctionCall:" + functionExpr.toString() + "(" + argStr + ")]";
            case PROPERTY_ACCESS:
                return "[PropertyAccess:" + object.toString() + "." + property + "]";
            case ARRAY_ACCESS:
                return "[ArrayAccess:" + array.toString() + "[" + index.toString() + "]]";
            default:
                return "[Expression:" + type + "]";
        }
    }
}