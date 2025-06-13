
import org.flashNight.gesh.pratt.*;

/* -------------------------------------------------------------------------
 *  表达式评估器 —— 高级API
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.ExpressionEvaluator {
    private var _context:Object;

    function ExpressionEvaluator() {
        _context = {};
        _initializeBuiltins();
    }

    private function _initializeBuiltins():Void {
        // 数学常量
        _context["Math"] = Math;
        _context["PI"] = Math.PI;
        _context["E"] = Math.E;
        
        // 内置函数
        _context["isNaN"] = function(value) { return isNaN(Number(value)); };
        _context["parseInt"] = function(str, radix) { return parseInt(String(str), radix || 10); };
        _context["parseFloat"] = function(str) { return parseFloat(String(str)); };
        _context["String"] = function(value) { return String(value); };
        _context["Number"] = function(value) { return Number(value); };
        _context["Boolean"] = function(value) { return Boolean(value); };
        
        // Buff系统专用函数
        _context["max"] = function() {
            return Math.max.apply(null, arguments);
        };
        _context["min"] = function() {
            return Math.min.apply(null, arguments);
        };
        _context["clamp"] = function(value, min, max) {
            return Math.max(min, Math.min(max, value));
        };
    }

    public function setVariable(name:String, value):Void {
        _context[name] = value;
    }

    public function setFunction(name:String, func:Function):Void {
        _context[name] = func;
    }

    public function getContext():Object {
        return _context;
    }

    public function clearContext():Void {
        _context = {};
        _initializeBuiltins();
    }

    public function evaluate(expression:String) {
        var lexer:PrattLexer = new PrattLexer(expression);
        var parser:PrattParser = new PrattParser(lexer);
        var ast:Expression = parser.parse();
        return ast.evaluate(_context);
    }

    public function parse(expression:String):Expression {
        var lexer:PrattLexer = new PrattLexer(expression);
        var parser:PrattParser = new PrattParser(lexer);
        return parser.parse();
    }
}
