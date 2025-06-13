import org.flashNight.gesh.pratt.*;

// 标识符表达式
class org.flashNight.gesh.pratt.IdentifierExpression extends Expression {
    public var name:String;
    
    public function IdentifierExpression(identifier:String) {
        super("IDENTIFIER");
        name = identifier;
    }
    
    public function evaluate(context:Object) {
        if (context && context[name] !== undefined) {
            return context[name];
        }
        throw new Error("Undefined variable: " + name);
    }
    
    public function toString():String {
        return "[Identifier:" + name + "]";
    }
}