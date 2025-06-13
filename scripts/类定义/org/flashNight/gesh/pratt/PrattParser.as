import org.flashNight.gesh.pratt.*;

/* -------------------------------------------------------------------------
 *  增强版 PrattParser.as —— 完整的表达式解析器
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.PrattParser {
    private var _lexer:PrattLexer;
    private var _prefixParselets:Object;
    private var _infixParselets:Object;

    function PrattParser(lexer:PrattLexer) {
        _lexer = lexer;
        _prefixParselets = {};
        _infixParselets = {};
        _initializeDefaultParselets();
    }

    /* ----------------------------------------------------------------------------
     * 初始化默认解析器
     * --------------------------------------------------------------------------*/
    private function _initializeDefaultParselets():Void {
        var literalParselet:LiteralParselet = new LiteralParselet();
        var identifierParselet:IdentifierParselet = new IdentifierParselet();
        var groupParselet:GroupParselet = new GroupParselet();
        
        // 前缀解析器
        registerPrefix(PrattToken.T_NUMBER, literalParselet);
        registerPrefix(PrattToken.T_STRING, literalParselet);
        registerPrefix(PrattToken.T_BOOLEAN, literalParselet);
        registerPrefix(PrattToken.T_NULL, literalParselet);
        registerPrefix(PrattToken.T_UNDEFINED, literalParselet);
        registerPrefix(PrattToken.T_IDENTIFIER, identifierParselet);
        registerPrefix(PrattToken.T_MATH, identifierParselet); // Math作为标识符
        registerPrefix(PrattToken.T_LPAREN, groupParselet);
        
        // 前缀运算符
        registerPrefix("-", new PrefixOperatorParselet(8));
        registerPrefix("+", new PrefixOperatorParselet(8));
        registerPrefix("!", new PrefixOperatorParselet(8));
        registerPrefix("typeof", new PrefixOperatorParselet(8));
        
        // 中缀解析器 - 按优先级从低到高
        
        // 三元运算符 (优先级1)
        registerInfix("?", new TernaryOperatorParselet());
        
        // 逻辑或 (优先级2)
        registerInfix("||", new BinaryOperatorParselet(2, false));
        registerInfix("??", new BinaryOperatorParselet(2, false)); // 空值合并
        
        // 逻辑与 (优先级3)
        registerInfix("&&", new BinaryOperatorParselet(3, false));
        
        // 相等比较 (优先级4)
        registerInfix("==", new BinaryOperatorParselet(4, false));
        registerInfix("!=", new BinaryOperatorParselet(4, false));
        registerInfix("===", new BinaryOperatorParselet(4, false));
        registerInfix("!==", new BinaryOperatorParselet(4, false));
        
        // 关系比较 (优先级5)
        registerInfix("<", new BinaryOperatorParselet(5, false));
        registerInfix(">", new BinaryOperatorParselet(5, false));
        registerInfix("<=", new BinaryOperatorParselet(5, false));
        registerInfix(">=", new BinaryOperatorParselet(5, false));
        
        // 加减 (优先级6)
        registerInfix("+", new BinaryOperatorParselet(6, false));
        registerInfix("-", new BinaryOperatorParselet(6, false));
        
        // 乘除模 (优先级7)
        registerInfix("*", new BinaryOperatorParselet(7, false));
        registerInfix("/", new BinaryOperatorParselet(7, false));
        registerInfix("%", new BinaryOperatorParselet(7, false));
        
        // 指数 (优先级8, 右结合)
        registerInfix("**", new BinaryOperatorParselet(8, true));
        
        // 最高优先级访问操作 (优先级10)
        registerInfix("(", new FunctionCallParselet()); // 函数调用
        registerInfix(".", new PropertyAccessParselet()); // 属性访问
        registerInfix("[", new ArrayAccessParselet()); // 数组访问
    }

    /* ----------------------------------------------------------------------------
     * 注册解析器
     * --------------------------------------------------------------------------*/
    public function registerPrefix(tokenType:String, parselet):Void {
        _prefixParselets[tokenType] = parselet;
    }

    public function registerInfix(tokenText:String, parselet):Void {
        _infixParselets[tokenText] = parselet;
    }

    /* ----------------------------------------------------------------------------
     * 获取当前token
     * --------------------------------------------------------------------------*/
    public function getCurrentToken():PrattToken {
        return _lexer.peek();
    }

    /* ----------------------------------------------------------------------------
     * 消费token
     * --------------------------------------------------------------------------*/
    public function consume():PrattToken {
        return _lexer.next();
    }

    public function consumeExpected(expectedType:String):PrattToken {
        var token:PrattToken = getCurrentToken();
        if (token.type != expectedType) {
            throw new Error("Expected " + expectedType + " but got " + token.type + 
                          " at " + token.createError(""));
        }
        return consume();
    }

    /* ----------------------------------------------------------------------------
     * 检查token类型
     * --------------------------------------------------------------------------*/
    public function match(tokenType:String):Boolean {
        return getCurrentToken().type == tokenType;
    }

    public function matchText(tokenText:String):Boolean {
        return getCurrentToken().text == tokenText;
    }

    /* ----------------------------------------------------------------------------
     * 获取优先级
     * --------------------------------------------------------------------------*/
    public function getPrecedence():Number {
        var token:PrattToken = getCurrentToken();
        var infixParselet = _infixParselets[token.text];
        
        if (infixParselet && infixParselet.getPrecedence) {
            return infixParselet.getPrecedence();
        }
        
        return 0;
    }

    /* ----------------------------------------------------------------------------
     * 核心解析方法
     * --------------------------------------------------------------------------*/
    public function parseExpression(minPrecedence:Number):Expression {
        if (minPrecedence == undefined) minPrecedence = 0;
        
        var token:PrattToken = consume();
        var prefixParselet = _getPrefixParselet(token);
        
        if (prefixParselet == null) {
            throw new Error("Could not parse token: " + token.createError("Unexpected token"));
        }
        
        var left:Expression = prefixParselet.parse(this, token);
        
        while (minPrecedence < getPrecedence()) {
            token = consume();
            var infixParselet = _infixParselets[token.text];
            left = infixParselet.parse(this, left, token);
        }
        
        return left;
    }

    /* ----------------------------------------------------------------------------
     * 解析完整表达式
     * --------------------------------------------------------------------------*/
    public function parse():Expression {
        var expression:Expression = parseExpression(0);
        
        if (!match(PrattToken.T_EOF)) {
            var token:PrattToken = getCurrentToken();
            throw new Error("Unexpected token after expression: " + token.createError(""));
        }
        
        return expression;
    }

    /* ----------------------------------------------------------------------------
     * 获取前缀解析器
     * --------------------------------------------------------------------------*/
    private function _getPrefixParselet(token:PrattToken) {
        // 首先检查token类型
        var parselet = _prefixParselets[token.type];
        if (parselet != null) {
            return parselet;
        }
        
        // 然后检查token文本（用于运算符）
        parselet = _prefixParselets[token.text];
        if (parselet != null) {
            return parselet;
        }
        
        return null;
    }
}

/* -------------------------------------------------------------------------
 *  使用示例和测试
 * -------------------------------------------------------------------------*/
/*
// 基础使用示例
var evaluator = PrattFactory.createStandardEvaluator();

// 1. 基础数学表达式
trace(evaluator.evaluate("2 + 3 * 4")); // 输出: 14
trace(evaluator.evaluate("(2 + 3) * 4")); // 输出: 20

// 2. 比较和逻辑运算
trace(evaluator.evaluate("5 > 3 && 2 < 4")); // 输出: true
trace(evaluator.evaluate("10 == 5 * 2 ? 'yes' : 'no'")); // 输出: "yes"

// 3. 函数调用
trace(evaluator.evaluate("Math.max(10, 20, 15)")); // 输出: 20
trace(evaluator.evaluate("Math.min(5, 3, 8)")); // 输出: 3

// 4. 变量使用
evaluator.setVariable("x", 10);
evaluator.setVariable("y", 5);
trace(evaluator.evaluate("x * y + Math.sqrt(16)")); // 输出: 54

// 5. 对象属性访问
var player = {level: 15, baseAttack: 100};
evaluator.setVariable("player", player);
trace(evaluator.evaluate("player.baseAttack + player.level * 5")); // 输出: 175

// 6. 数组访问
var stats = [100, 200, 300];
evaluator.setVariable("stats", stats);
trace(evaluator.evaluate("stats[1] + stats[2]")); // 输出: 500

// 7. 复杂的Buff表达式
var buffEvaluator = PrattFactory.createBuffEvaluator();
buffEvaluator.setVariable("baseValue", 100);
buffEvaluator.setVariable("level", 10);

// 模拟buff计算逻辑
var buffResult = buffEvaluator.evaluate(
    "baseValue * (level > 5 ? 1.2 : 1.0) + (level >= 10 ? 50 : 0)"
);
trace("Buff计算结果: " + buffResult); // 输出: 170

// 8. 错误处理
try {
    trace(evaluator.evaluate("5 / 0")); // 抛出除零错误
} catch (e) {
    trace("错误: " + e.message);
}

// 9. 空值处理
evaluator.setVariable("maybeNull", null);
trace(evaluator.evaluate("maybeNull ?? 'default'")); // 输出: "default"

// 10. 类型检查
trace(evaluator.evaluate("typeof 'hello'")); // 输出: "string"
trace(evaluator.evaluate("isNaN('abc')")); // 输出: true
*/