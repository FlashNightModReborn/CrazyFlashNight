import org.flashNight.gesh.pratt.*;
// 三元表达式
class org.flashNight.gesh.pratt.TernaryExpression extends Expression {
    public var condition:Expression;
    public var trueExpr:Expression;
    public var falseExpr:Expression;
    
    public function TernaryExpression(cond:Expression, trueExp:Expression, falseExp:Expression) {
        super("TERNARY");
        condition = cond;
        trueExpr = trueExp;
        falseExpr = falseExp;
    }
    
    public function evaluate(context:Object) {
        var condVal = condition.evaluate(context);
        return Boolean(condVal) ? trueExpr.evaluate(context) : falseExpr.evaluate(context);
    }
    
    public function toString():String {
        return "[Ternary:" + condition.toString() + " ? " + trueExpr.toString() + " : " + falseExpr.toString() + "]";
    }
}