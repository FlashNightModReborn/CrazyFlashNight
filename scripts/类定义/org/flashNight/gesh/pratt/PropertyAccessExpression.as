import org.flashNight.gesh.pratt.*;

// 属性访问表达式
class org.flashNight.gesh.pratt.PropertyAccessExpression extends Expression {
    public var object:Expression;
    public var property:String;
    
    public function PropertyAccessExpression(obj:Expression, prop:String) {
        super("PROPERTY_ACCESS");
        object = obj;
        property = prop;
    }
    
    public function evaluate(context:Object) {
        var objVal = object.evaluate(context);
        
        if (objVal == null || objVal == undefined) {
            throw new Error("Cannot access property '" + property + "' of null or undefined");
        }
        
        return objVal[property];
    }
    
    public function toString():String {
        return "[PropertyAccess:" + object.toString() + "." + property + "]";
    }
}