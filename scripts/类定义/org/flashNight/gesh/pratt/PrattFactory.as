
import org.flashNight.gesh.pratt.*;

/* -------------------------------------------------------------------------
 *  工厂类 —— 简化创建过程
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.PrattFactory {
    
    public static function createBuffEvaluator():ExpressionEvaluator {
        var evaluator:ExpressionEvaluator = new ExpressionEvaluator();
        
        // Buff系统相关的变量和函数
        evaluator.setFunction("SET_BASE", function(value) {
            return {type: "SET_BASE", value: value};
        });
        
        evaluator.setFunction("ADD_FLAT", function(value) {
            return {type: "ADD_FLAT", value: value};
        });
        
        evaluator.setFunction("ADD_PERCENT_BASE", function(value) {
            return {type: "ADD_PERCENT_BASE", value: value};
        });
        
        evaluator.setFunction("MUL_PERCENT", function(value) {
            return {type: "MUL_PERCENT", value: value};
        });
        
        evaluator.setFunction("CLAMP_MAX", function(value) {
            return {type: "CLAMP_MAX", value: value};
        });
        
        evaluator.setFunction("CLAMP_MIN", function(value) {
            return {type: "CLAMP_MIN", value: value};
        });
        
        return evaluator;
    }
    
    public static function createStandardEvaluator():ExpressionEvaluator {
        return new ExpressionEvaluator();
    }
}
