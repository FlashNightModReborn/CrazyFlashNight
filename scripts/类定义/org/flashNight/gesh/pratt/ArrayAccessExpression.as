import org.flashNight.gesh.pratt.*;
// 数组访问表达式
class org.flashNight.gesh.pratt.ArrayAccessExpression extends Expression {
    public var array:Expression;
    public var index:Expression;
    
    public function ArrayAccessExpression(arr:Expression, idx:Expression) {
        super("ARRAY_ACCESS");
        array = arr;
        index = idx;
    }
    
    public function evaluate(context:Object) {
        var arrayVal = array.evaluate(context);
        var indexVal = index.evaluate(context);
        
        if (arrayVal == null || arrayVal == undefined) {
            throw new Error("Cannot access index of null or undefined");
        }
        
        return arrayVal[indexVal];
    }
    
    public function toString():String {
        return "[ArrayAccess:" + array.toString() + "[" + index.toString() + "]]";
    }
}