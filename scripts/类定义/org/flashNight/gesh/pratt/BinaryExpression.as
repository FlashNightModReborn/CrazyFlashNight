import org.flashNight.gesh.pratt.*;

// 二元表达式
class org.flashNight.gesh.pratt.BinaryExpression extends Expression {
    public var left:Expression;
    public var operator:String;
    public var right:Expression;
    
    public function BinaryExpression(leftExpr:Expression, op:String, rightExpr:Expression) {
        super("BINARY");
        left = leftExpr;
        operator = op;
        right = rightExpr;
    }
    
    public function evaluate(context:Object) {
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
    
    public function toString():String {
        return "[Binary:" + left.toString() + " " + operator + " " + right.toString() + "]";
    }
}