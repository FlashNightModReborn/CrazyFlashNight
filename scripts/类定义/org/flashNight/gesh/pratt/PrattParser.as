import org.flashNight.gesh.pratt.*;

/**
 * 修改后的Pratt解析器 - 适配新的统一类结构
 */
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
        // 前缀解析器
        registerPrefix(PrattToken.T_NUMBER, PrattParselet.literal());
        registerPrefix(PrattToken.T_STRING, PrattParselet.literal());
        registerPrefix(PrattToken.T_BOOLEAN, PrattParselet.literal());
        registerPrefix(PrattToken.T_NULL, PrattParselet.literal());
        registerPrefix(PrattToken.T_UNDEFINED, PrattParselet.literal());
        registerPrefix(PrattToken.T_IDENTIFIER, PrattParselet.identifier());
        registerPrefix(PrattToken.T_LPAREN, PrattParselet.group());

        // 前缀运算符
        registerPrefix("-", PrattParselet.prefixOperator(7)); // 按文本注册
        registerPrefix("+", PrattParselet.prefixOperator(7)); // 按文本注册
        registerPrefix("!", PrattParselet.prefixOperator(7)); // 按文本注册
        registerPrefix(PrattToken.T_TYPEOF, PrattParselet.prefixOperator(7)); // 按类型注册
        
        // 中缀解析器 - 按优先级从低到高
        
        // 三元运算符 (优先级1)
        registerInfix("?", PrattParselet.ternaryOperator());
        
        // 逻辑或 (优先级2)
        registerInfix("||", PrattParselet.binaryOperator(2, false));
        registerInfix("??", PrattParselet.binaryOperator(2, false)); // 空值合并
        
        // 逻辑与 (优先级3)
        registerInfix("&&", PrattParselet.binaryOperator(3, false));
        
        // 相等比较 (优先级4)
        registerInfix("==", PrattParselet.binaryOperator(4, false));
        registerInfix("!=", PrattParselet.binaryOperator(4, false));
        registerInfix("===", PrattParselet.binaryOperator(4, false));
        registerInfix("!==", PrattParselet.binaryOperator(4, false));
        
        // 关系比较 (优先级5)
        registerInfix("<", PrattParselet.binaryOperator(5, false));
        registerInfix(">", PrattParselet.binaryOperator(5, false));
        registerInfix("<=", PrattParselet.binaryOperator(5, false));
        registerInfix(">=", PrattParselet.binaryOperator(5, false));
        
        // 加减 (优先级6)
        registerInfix("+", PrattParselet.binaryOperator(6, false));
        registerInfix("-", PrattParselet.binaryOperator(6, false));
        
        // 乘除模 (优先级7)
        registerInfix("*", PrattParselet.binaryOperator(7, false));
        registerInfix("/", PrattParselet.binaryOperator(7, false));
        registerInfix("%", PrattParselet.binaryOperator(7, false));
        
        // 指数 (优先级8, 右结合)
        registerInfix("**", PrattParselet.binaryOperator(8, true));
        
        // 最高优先级访问操作 (优先级10)
        registerInfix("(", PrattParselet.functionCall()); // 函数调用
        registerInfix(".", PrattParselet.propertyAccess()); // 属性访问
        registerInfix("[", PrattParselet.arrayAccess()); // 数组访问
    }

    /* ----------------------------------------------------------------------------
     * 注册解析器
     * --------------------------------------------------------------------------*/
    public function registerPrefix(tokenType:String, parselet:PrattParselet):Void {
        _prefixParselets[tokenType] = parselet;
    }

    public function registerInfix(tokenText:String, parselet:PrattParselet):Void {
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
            throw new Error("Expected T_" + expectedType + " but got " + token.type +
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
        var infixParselet:PrattParselet = _infixParselets[token.text];
        
        if (infixParselet && infixParselet.getPrecedence) {
            return infixParselet.getPrecedence();
        }
        
        return 0;
    }

    /* ----------------------------------------------------------------------------
     * 核心解析方法
     * --------------------------------------------------------------------------*/
    public function parseExpression(minPrecedence:Number):PrattExpression {
        if (minPrecedence == undefined) minPrecedence = 0;
        
        var token:PrattToken = consume();
        var prefixParselet:PrattParselet = _getPrefixParselet(token);
        
        if (prefixParselet == null) {
            throw new Error("Could not parse token: " + token.createError("Unexpected token"));
        }
        
        var left:PrattExpression = prefixParselet.parsePrefix(this, token);
        
        while (minPrecedence < getPrecedence()) {
            token = consume();
            var infixParselet:PrattParselet = _infixParselets[token.text];
            left = infixParselet.parseInfix(this, left, token);
        }
        
        return left;
    }

    /* ----------------------------------------------------------------------------
     * 解析完整表达式
     * --------------------------------------------------------------------------*/
    public function parse():PrattExpression {
        var expression:PrattExpression = parseExpression(0);
        
        if (!match(PrattToken.T_EOF)) {
            var token:PrattToken = getCurrentToken();
            throw new Error("Unexpected token after expression: " + token.createError(""));
        }
        
        return expression;
    }

    /* ----------------------------------------------------------------------------
     * 获取前缀解析器
     * --------------------------------------------------------------------------*/
    private function _getPrefixParselet(token:PrattToken):PrattParselet {
        // 首先检查token文本（用于特殊关键字和运算符）
        var parselet:PrattParselet = _prefixParselets[token.text];
        if (parselet != null) {
            return parselet;
        }
        
        // 然后检查token类型
        parselet = _prefixParselets[token.type];
        if (parselet != null) {
            return parselet;
        }
        
        return null;
    }
    
    /* ----------------------------------------------------------------------------
     * 自定义Buff运算符支持
     * --------------------------------------------------------------------------*/
    public function addBuffOperators():Void {
        // Buff系统专用运算符
        registerInfix("@", PrattParselet.binaryOperator(9, false)); // Buff应用运算符
        registerInfix("~>", PrattParselet.binaryOperator(3, true)); // Buff链式运算符
        registerPrefix("$", PrattParselet.prefixOperator(8)); // Buff变量引用
    }
}