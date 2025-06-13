import org.flashNight.gesh.pratt.*;

// 字面量表达式
class org.flashNight.gesh.pratt.LiteralExpression extends Expression {
    public var value;
    
    public function LiteralExpression(literalValue) {
        super("LITERAL");
        value = literalValue;
    }
    
    public function evaluate(context:Object) {
        return value;
    }
    
    public function toString():String {
        return "[Literal:" + value + "]";
    }
}