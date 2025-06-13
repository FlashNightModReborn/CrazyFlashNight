import org.flashNight.gesh.pratt.*;

// 一元表达式
class org.flashNight.gesh.pratt.UnaryExpression extends Expression {
    public var operator:String;
    public var operand:Expression;
    
    public function UnaryExpression(op:String, expr:Expression) {
        super("UNARY");
        operator = op;
        operand = expr;
    }
    
    public function evaluate(context:Object) {
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
    
    public function toString():String {
        return "[Unary:" + operator + operand.toString() + "]";
    }
}