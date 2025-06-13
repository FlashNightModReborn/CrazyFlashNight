/**
 * @file PrattExpression.as
 * @description 定义了用于表示抽象语法树（AST）节点的统一表达式类。
 * 
 * 该文件中的 `PrattExpression` 类是Pratt解析器生成的结果的核心。
 * 它采用了一种“统一类”的设计模式，即用一个类来表示所有类型的表达式
 * （如二元运算、函数调用、字面量等），并通过一个 `type` 字段来区分它们。
 * 
 * 这种设计简化了AST的结构，使得遍历和求值等操作可以通过一个统一的接口进行。
 * 类中提供了静态工厂方法来安全、便捷地构造各种类型的表达式节点，并包含一个
 * 功能完备的 `evaluate` 方法，用于在给定的上下文中计算表达式的值。
 */
import org.flashNight.gesh.pratt.*;

/**
 * 代表一个抽象语法树（AST）中的表达式节点。
 * 这是一个统一的类，能够表示语言中所有可能的表达式结构。
 */
class org.flashNight.gesh.pratt.PrattExpression {
    
    // ============= 表达式类型常量 =============
    /** 二元表达式, 例如: a + b */
    public static var BINARY:String = "BINARY";
    /** 一元表达式, 例如: -a, !b */
    public static var UNARY:String = "UNARY";
    /** 三元（条件）表达式, 例如: a ? b : c */
    public static var TERNARY:String = "TERNARY";
    /** 字面量表达式, 例如: 123, "hello", true */
    public static var LITERAL:String = "LITERAL";
    /** 标识符（变量）表达式, 例如: myVar */
    public static var IDENTIFIER:String = "IDENTIFIER";
    /** 函数调用表达式, 例如: myFunction(a, b) */
    public static var FUNCTION_CALL:String = "FUNCTION_CALL";
    /** 属性访问表达式, 例如: myObject.property */
    public static var PROPERTY_ACCESS:String = "PROPERTY_ACCESS";
    /** 数组访问表达式, 例如: myArray[0] */
    public static var ARRAY_ACCESS:String = "ARRAY_ACCESS";
    /** 数组字面量表达式, 例如: [1, 2, 3] */
    public static var ARRAY_LITERAL:String = "ARRAY_LITERAL";
    /** 对象字面量表达式, 例如: { a: 1, b: 2 } */
    public static var OBJECT_LITERAL:String = "OBJECT_LITERAL";
    
    // ============= 通用属性 =============
    /** 表达式的类型, 其值为本类中定义的常量之一。 */
    public var type:String;
    
    // ============= 各类型专用属性 =============
    // 为了节省内存和简化类结构，所有可能的属性都在这里定义，但只在特定类型下有意义。
    
    public var value;              // 用于 LITERAL: 存储字面量的实际值。
    public var name:String;        // 用于 IDENTIFIER: 存储标识符的名称。
    public var left:PrattExpression;   // 用于 BINARY: 左操作数。
    public var right:PrattExpression;  // 用于 BINARY: 右操作数。
    public var operator:String;    // 用于 BINARY, UNARY: 运算符的文本表示, 如 "+", "!"。
    public var operand:PrattExpression;    // 用于 UNARY: 操作数。
    public var condition:PrattExpression;  // 用于 TERNARY: 条件部分。
    public var trueExpr:PrattExpression;   // 用于 TERNARY: 条件为真时执行的表达式。
    public var falseExpr:PrattExpression;  // 用于 TERNARY: 条件为假时执行的表达式。
    public var object:PrattExpression;     // 用于 PROPERTY_ACCESS: 被访问的对象。
    public var property:String;    // 用于 PROPERTY_ACCESS: 属性的名称。
    public var array:PrattExpression;      // 用于 ARRAY_ACCESS: 被访问的数组。
    public var index:PrattExpression;      // 用于 ARRAY_ACCESS: 数组索引表达式。
    public var functionExpr:PrattExpression;  // 用于 FUNCTION_CALL: 指向函数的表达式 (可以是标识符或属性访问)。
    public var arguments:Array;    // 用于 FUNCTION_CALL: 参数列表，每个元素都是 PrattExpression。
    public var elements:Array;     // 用于 ARRAY_LITERAL: 数组元素列表，每个元素都是 PrattExpression。
    public var properties:Array;   // 用于 OBJECT_LITERAL: 属性列表, 格式为 [{key:String, value:PrattExpression}, ...]。
    
    /**
     * 基础构造函数。通常不直接调用，而是通过静态工厂方法创建实例。
     * @param exprType 表达式的类型。
     */
    public function PrattExpression(exprType:String) {
        this.type = exprType;
    }
    
    // ============= 静态工厂方法 =============
    // 使用静态工厂方法可以提高代码的可读性，并确保表达式对象被正确地初始化。

    /**
     * 创建一个字面量表达式。
     * @param literalValue 字面量的实际值 (例如: 42, "hello", true)。
     * @return 一个类型为 LITERAL 的新 PrattExpression 实例。
     */
    public static function literal(literalValue):PrattExpression {
        var expr:PrattExpression = new PrattExpression(LITERAL);
        expr.value = literalValue;
        return expr;
    }
    
    /**
     * 创建一个标识符表达式。
     * @param identifierName 标识符的名称 (例如: "myVar")。
     * @return 一个类型为 IDENTIFIER 的新 PrattExpression 实例。
     */
    public static function identifier(identifierName:String):PrattExpression {
        var expr:PrattExpression = new PrattExpression(IDENTIFIER);
        expr.name = identifierName;
        return expr;
    }
    
    /**
     * 创建一个二元表达式。
     * @param leftExpr 左操作数表达式。
     * @param op 运算符字符串 (例如: "+", "==")。
     * @param rightExpr 右操作数表达式。
     * @return 一个类型为 BINARY 的新 PrattExpression 实例。
     */
    public static function binary(leftExpr:PrattExpression, op:String, rightExpr:PrattExpression):PrattExpression {
        var expr:PrattExpression = new PrattExpression(BINARY);
        expr.left = leftExpr;
        expr.operator = op;
        expr.right = rightExpr;
        return expr;
    }
    
    /**
     * 创建一个一元表达式。
     * @param op 运算符字符串 (例如: "-", "!")。
     * @param operandExpr 操作数表达式。
     * @return 一个类型为 UNARY 的新 PrattExpression 实例。
     */
    public static function unary(op:String, operandExpr:PrattExpression):PrattExpression {
        var expr:PrattExpression = new PrattExpression(UNARY);
        expr.operator = op;
        expr.operand = operandExpr;
        return expr;
    }
    
    /**
     * 创建一个三元表达式。
     * @param cond 条件表达式。
     * @param trueExp 条件为真时求值的表达式。
     * @param falseExp 条件为假时求值的表达式。
     * @return 一个类型为 TERNARY 的新 PrattExpression 实例。
     */
    public static function ternary(cond:PrattExpression, trueExp:PrattExpression, falseExp:PrattExpression):PrattExpression {
        var expr:PrattExpression = new PrattExpression(TERNARY);
        expr.condition = cond;
        expr.trueExpr = trueExp;
        expr.falseExpr = falseExp;
        return expr;
    }
    
    /**
     * 创建一个函数调用表达式。
     * @param funcExpr 指向函数的表达式。
     * @param args 参数表达式数组。如果为 null 或 undefined，则默认为空数组。
     * @return 一个类型为 FUNCTION_CALL 的新 PrattExpression 实例。
     */
    public static function functionCall(funcExpr:PrattExpression, args:Array):PrattExpression {
        var expr:PrattExpression = new PrattExpression(FUNCTION_CALL);
        expr.functionExpr = funcExpr;
        expr.arguments = args || []; 
        return expr;
    }
    
    /**
     * 创建一个属性访问表达式。
     * @param obj 被访问的对象表达式。
     * @param prop 属性名称字符串。
     * @return 一个类型为 PROPERTY_ACCESS 的新 PrattExpression 实例。
     */
    public static function propertyAccess(obj:PrattExpression, prop:String):PrattExpression {
        var expr:PrattExpression = new PrattExpression(PROPERTY_ACCESS);
        expr.object = obj;
        expr.property = prop;
        return expr;
    }
    
    /**
     * 创建一个数组访问表达式。
     * @param arr 被访问的数组表达式。
     * @param idx 索引表达式。
     * @return 一个类型为 ARRAY_ACCESS 的新 PrattExpression 实例。
     */
    public static function arrayAccess(arr:PrattExpression, idx:PrattExpression):PrattExpression {
        var expr:PrattExpression = new PrattExpression(ARRAY_ACCESS);
        expr.array = arr;
        expr.index = idx;
        return expr;
    }
    
    /**
     * 创建一个数组字面量表达式。
     * @param elements 数组元素的表达式数组。如果为 null 或 undefined，则默认为空数组。
     * @return 一个类型为 ARRAY_LITERAL 的新 PrattExpression 实例。
     */
    public static function arrayLiteral(elements:Array):PrattExpression {
        var expr:PrattExpression = new PrattExpression(ARRAY_LITERAL);
        expr.elements = elements || []; 
        return expr;
    }

    /**
     * 创建一个对象字面量表达式。
     * @param props 属性描述对象的数组，格式为 `[{key:String, value:PrattExpression}]`。如果为 null 或 undefined，则默认为空数组。
     * @return 一个类型为 OBJECT_LITERAL 的新 PrattExpression 实例。
     */
    public static function objectLiteral(props:Array):PrattExpression {
        var expr:PrattExpression = new PrattExpression(OBJECT_LITERAL);
        expr.properties = props || []; 
        return expr;
    }

    // ============= 求值方法 =============
    /**
     * 在给定的上下文中递归地求值此表达式。
     * 这是整个AST求值引擎的核心。
     * 
     * @param context 一个对象，作为变量查找的作用域。例如，当求值一个IDENTIFIER时，会在此对象上查找同名属性。
     * @return 表达式的计算结果。
     * @throws Error 当发生求值错误时（如变量未定义、除零、调用非函数等），抛出异常。
     */
    public function evaluate(context:Object) {
        switch (type) {
            case LITERAL:
                // 字面量直接返回其存储的值。
                return value;
                
            case IDENTIFIER:
                // 在AS2中，`context[name] === undefined`无法区分“属性不存在”和“属性存在但其值为undefined”。
                // 因此，需要通过遍历键来100%准确地判断属性是否存在。这虽然慢，但是是唯一可靠的方法。
                if (context != null) {
                    var keyExists:Boolean = false;
                    for (var k in context) {
                        if (k == name) {
                            keyExists = true;
                            break;
                        }
                    }
                    if (keyExists) {
                        return context[name]; // 属性存在，返回其值（可能是undefined）。
                    }
                }
                // 如果上下文为null或属性不存在，则变量未定义。
                throw new Error("Undefined variable: " + name);
                
            case BINARY:
                return _evaluateBinary(context);
                
            case UNARY:
                return _evaluateUnary(context);
                
            case TERNARY:
                // 先求值条件部分，然后根据其布尔值决定求值哪个分支。
                var condVal = condition.evaluate(context);
                return Boolean(condVal) ? trueExpr.evaluate(context) : falseExpr.evaluate(context);
                
            case FUNCTION_CALL:
                return _evaluateFunctionCall(context);
                
            case PROPERTY_ACCESS:
                return _evaluatePropertyAccess(context);
                
            case ARRAY_ACCESS:
                return _evaluateArrayAccess(context);

            case ARRAY_LITERAL:
                // 创建一个新数组，并递归求值其所有元素表达式，将结果放入新数组。
                var evaluatedElements:Array = [];
                for (var i:Number = 0; i < this.elements.length; i++) {
                    evaluatedElements.push(this.elements[i].evaluate(context));
                }
                return evaluatedElements;

            case OBJECT_LITERAL:
                // 创建一个新对象，并递归求值其所有属性的值表达式，构建新对象。
                var obj:Object = {};
                for (var i:Number = 0; i < this.properties.length; i++) {
                    var prop = this.properties[i];
                    var key:String = prop.key;
                    obj[key] = prop.value.evaluate(context);
                }
                return obj;
                
            default:
                // 如果遇到未知的表达式类型，说明解析器或AST构建过程有误。
                throw new Error("Unknown expression type: " + type);
        }
    }

    /**
     * 工具函数：抹平因浮点数运算产生的微小误差，使结果更符合整数预期。
     * @param n 一个数字。
     * @return 如果数字与最近的整数差值极小，则返回该整数，否则返回原数字。
     */
    private static function _normalize(n:Number):Number {
        return Math.abs(n - Math.round(n)) < 1e-9 ? Math.round(n) : n;
    }

    /**
     * 工具函数：严格检查一个值是否为真正的 NaN (Not-a-Number)。
     * ActionScript 2 的 isNaN('abc') 会返回 true，此函数避免了这种情况。
     * @param v 待检查的值。
     * @return 如果值是 number 类型且为 NaN，则返回 true。
     */
    private static function _isRealNaN(v):Boolean {
        return (typeof v == "number") && isNaN(v);
    }
    
    /**
     * 内部方法：处理二元表达式的求值。
     * @param context 求值上下文。
     * @return 二元运算的结果。
     */
    private function _evaluateBinary(context:Object) {
        // 为 && 和 || 实现短路求值。
        if (operator == "&&") {
            var leftValAnd = left.evaluate(context);
            if (!leftValAnd) {
                return leftValAnd; // 短路，立即返回第一个falsy值。
            }
            return right.evaluate(context); // 否则，继续求值并返回右侧的值。
        }

        if (operator == "||") {
            var leftValOr = left.evaluate(context);
            if (leftValOr) {
                return leftValOr; // 短路，立即返回第一个truthy值。
            }
            return right.evaluate(context); // 否则，继续求值并返回右侧的值。
        }

        // 对于非短路运算符，先计算两边的值。
        var leftVal = left.evaluate(context);
        var rightVal = right.evaluate(context);
        
        switch (operator) {
            case "+":
                // `+` 运算符行为复杂：优先数字加法，否则字符串拼接。
                // 1. 尝试将两边都转为数字。
                var leftNum:Number  = Number(leftVal);
                var rightNum:Number = Number(rightVal);
                // 2. 如果两边都是有效数字，则进行数字加法。
                if (!isNaN(leftNum) && !isNaN(rightNum)) {
                    return _normalize(leftNum + rightNum);
                }
                // 3. 如果任一侧是字符串，则进行字符串拼接。
                if (typeof leftVal == "string" || typeof rightVal == "string") {
                    return String(leftVal) + String(rightVal);
                }
                // 4. 兜底情况（例如 undefined + 1），按数字加法处理，结果可能为 NaN。
                return _normalize(leftNum + rightNum);

            case "-": return _normalize(Number(leftVal) - Number(rightVal));
            case "*": return _normalize(Number(leftVal) * Number(rightVal));
            case "/":
                if (Number(rightVal) == 0) throw new Error("Division by zero");
                return _normalize(Number(leftVal) / Number(rightVal));
            case "%": return Number(leftVal) % Number(rightVal);
            case "**": return Math.pow(Number(leftVal), Number(rightVal));
            
            // 比较运算符
            case "==": 
                if (_isRealNaN(leftVal) || _isRealNaN(rightVal)) return false; // NaN 与任何值（包括自身）比较都应为 false。
                return leftVal == rightVal; // 使用AS2的 `==`，它会自动处理类型转换。
            case "!=":
                if (_isRealNaN(leftVal) || _isRealNaN(rightVal)) return true; // NaN 与任何值不等。
                return leftVal != rightVal;
            
            // 严格比较运算符
            case "===":
                return leftVal === rightVal; // 类型和值都必须相等。
            case "!==":
                return leftVal !== rightVal;

            case "<": return Number(leftVal) < Number(rightVal);
            case ">": return Number(leftVal) > Number(rightVal);
            case "<=": return Number(leftVal) <= Number(rightVal);
            case ">=": return Number(leftVal) >= Number(rightVal);
            
            // 空值合并运算符
            case "??": 
                // 仅当左侧是 null 或 undefined 时，才返回右侧的值。
                return (leftVal == null || leftVal == undefined) ? rightVal : leftVal;
            default:
                throw new Error("Unknown binary operator: " + operator);
        }
    }
    
    /**
     * 内部方法：处理一元表达式的求值。
     * @param context 求值上下文。
     * @return 一元运算的结果。
     */
    private function _evaluateUnary(context:Object) {
        var operandVal = operand.evaluate(context);
        
        switch (operator) {
            case "+": return Number(operandVal);
            case "-": return -Number(operandVal);
            case "!": return !Boolean(operandVal);
            case "typeof": 
                // 模拟JavaScript的历史行为：typeof null 返回 "object"。
                if (operandVal === null) {
                    return "object";
                }
                return typeof operandVal;
            default:
                throw new Error("Unknown unary operator: " + operator);
        }
    }
    
    /**
     * 内部方法：处理函数调用表达式的求值。
     * @param context 求值上下文。
     * @return 函数调用的返回值。
     */
    private function _evaluateFunctionCall(context:Object) {
        // 1. 递归求值所有参数表达式。
        var evaluatedArgs:Array = [];
        // 使用 `this.arguments` 避免与函数内部的 `arguments` 关键字冲突。
        for (var i:Number = 0; i < this.arguments.length; i++) {
            evaluatedArgs.push(this.arguments[i].evaluate(context));
        }
        
        // 2. 根据函数表达式的类型处理调用。
        if (functionExpr.type == IDENTIFIER) { // 例如: myFunction(...)
            var funcName:String = functionExpr.name;
            if (context && typeof context[funcName] == "function") {
                // 在上下文中找到函数，使用 apply 调用以确保 `this` 指向 context。
                return context[funcName].apply(context, evaluatedArgs);
            } else if (context && context[funcName] !== undefined) {
                throw new Error(funcName + " is not a function");
            }
            throw new Error("Unknown function: " + funcName);

        } else if (functionExpr.type == PROPERTY_ACCESS) { // 例如: myObj.myMethod(...)
            return _callObjectMethod(functionExpr, evaluatedArgs, context);
        }
        
        throw new Error("Invalid function call target");
    }
    
    /**
     * 内部方法：专门处理对象方法的调用。
     * @param propAccess 指向对象方法的属性访问表达式。
     * @param args 已求值的参数数组。
     * @param context 求值上下文。
     * @return 方法调用的返回值。
     */
    private function _callObjectMethod(propAccess:PrattExpression, args:Array, context:Object) {
        // 1. 求值得到对象实例。
        var obj = propAccess.object.evaluate(context);
        var methodName:String = propAccess.property;
        
        if (obj && typeof obj[methodName] == "function") {
             // 找到方法，使用 apply 调用以确保 `this` 指向该对象。
            return obj[methodName].apply(obj, args);
        } else if (obj && obj[methodName] !== undefined) {
             throw new Error(methodName + " is not a function");
        }
        throw new Error("Method '" + methodName + "' not found on object");
    }
    
    /**
     * 内部方法：处理属性访问表达式的求值。
     * @param context 求值上下文。
     * @return 属性的值。
     */
    private function _evaluatePropertyAccess(context:Object) {
        var objVal = object.evaluate(context);
        
        // 禁止访问 null 或 undefined 的属性。
        if (objVal == null || objVal == undefined) {
            throw new Error("Cannot access property '" + property + "' of null or undefined");
        }
        
        return objVal[property];
    }
    
    /**
     * 内部方法：处理数组访问表达式的求值。
     * @param context 求值上下文。
     * @return 数组元素的值。
     */
    private function _evaluateArrayAccess(context:Object) {
        var arrayVal = array.evaluate(context);
        var indexVal = index.evaluate(context);
        
        // 禁止访问 null 或 undefined 的索引。
        if (arrayVal == null || arrayVal == undefined) {
            throw new Error("Cannot access index of null or undefined");
        }
        
        return arrayVal[indexVal];
    }
    
    /**
     * 返回表达式的字符串表示形式，主要用于调试。
     * @return 一个描述表达式结构和内容的字符串。
     */
    public function toString():String {
        switch (type) {
            case LITERAL:
                var valStr = (typeof value == "string") ? "'" + value + "'" : String(value);
                return "[Literal:" + valStr + "]";
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
                for (var i:Number = 0; i < this.arguments.length; i++) {
                    if (i > 0) argStr += ", ";
                    argStr += this.arguments[i].toString();
                }
                return "[FunctionCall:" + functionExpr.toString() + "(" + argStr + ")]";
            case PROPERTY_ACCESS:
                return "[PropertyAccess:" + object.toString() + "." + property + "]";
            case ARRAY_ACCESS:
                return "[ArrayAccess:" + array.toString() + "[" + index.toString() + "]]";
            case ARRAY_LITERAL:
                var elemStr:String = "";
                for (var i:Number = 0; i < this.elements.length; i++) {
                    if (i > 0) elemStr += ", ";
                    elemStr += this.elements[i].toString();
                }
                return "[ArrayLiteral:[" + elemStr + "]]";
                
            case OBJECT_LITERAL:
                    var propStr:String = "";
                    for (var i:Number = 0; i < this.properties.length; i++) {
                        if (i > 0) propStr += ", ";
                        var prop = this.properties[i];
                        propStr += prop.key + ":" + prop.value.toString();
                    }
                    return "[ObjectLiteral:{" + propStr + "}]";
            default:
                return "[Expression:" + type + "]";
        }
    }
}