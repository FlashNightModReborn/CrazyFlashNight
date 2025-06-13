import org.flashNight.gesh.pratt.*;

class org.flashNight.gesh.pratt.Expression {
    public var type:String;
    
    public function Expression(exprType:String) {
        type = exprType;
    }
    
    public function evaluate(context:Object) {
        // 子类重写
        return null;
    }
    
    public function toString():String {
        return "[Expression:" + type + "]";
    }
}