import org.flashNight.gesh.pratt.*;

/**
 * Pratt解析器 (Pratt Parser) 的核心实现。
 * 
 * 该类采用 "Top-Down Operator Precedence"（自顶向下运算符优先级）算法，也称为 Pratt 解析法。
 * 它通过将解析逻辑委托给与特定 Token 类型关联的 Parselet 对象，实现了高度可扩展和易于管理的表达式解析。
 * 
 * 核心职责：
 *   从 PrattLexer 获取 Token 流。
 *   管理一个前缀(prefix)和中缀(infix) Parselet 的注册表，这些Parselet定义了语言的语法。
 *   根据当前 Token 查找并调用相应的 Parselet 来构建抽象语法树 (AST)。
 *   处理运算符的优先级和结合性。
 *   提供公共API parse() 来解析完整的表达式字符串。
 * 
 * 
 * 工作流程：
 * 
 *   构造时，通过 _initializeDefaultParselets() 初始化一套标准的Gesh脚本语法规则。
 *   外部调用 parse() 方法启动解析过程。
 *   parse() 内部调用核心的 parseExpression() 方法。
 *   parseExpression() 首先查找并执行一个前缀 Parselet 来处理字面量、标识符、分组或前缀运算符。
 *   然后，它进入一个循环，只要当前的中缀运算符优先级高于传入的最小优先级，就持续查找并执行中缀 Parselet。
 *   这个过程递归地构建出一个完整的 PrattExpression 语法树。
 * 
 *
 * @see PrattParselet 用于定义具体解析行为的策略类。
 * @see PrattLexer 提供 Token 输入流。
 * @see PrattExpression 解析结果，即抽象语法树(AST)的节点。
 */
class org.flashNight.gesh.pratt.PrattParser {
    /**
     * Tokenizer 实例，用于提供 Token 输入流。
     * @private
     */
    private var _lexer:PrattLexer;
    
    /**
     * 前缀 Parselet 的注册表。
     * 键 (String): 通常是 Token 类型 (如 PrattToken.T_IDENTIFIER) 或特定的运算符文本 (如 "-")。
     * 值 (PrattParselet): 用于解析该前缀 Token 的 Parselet 实例。
     * 前缀 Token 是指那些可以开始一个表达式的 Token，例如数字、标识符、一元运算符等。
     * @private
     */
    private var _prefixParselets:Object;
    
    /**
     * 中缀/后缀 Parselet 的注册表。
     * 键 (String): 必须是 Token 的文本 (如 "+", "*", "(")。这是因为解析器需要根据 Token 文本来查询优先级。
     * 值 (PrattParselet): 用于解析该中缀 Token 的 Parselet 实例。
     * 中缀 Token 是指那些出现在两个表达式之间的 Token，例如二元运算符。
     * 后缀 Token (如函数调用的 `(`, 数组访问的 `[`) 在Pratt解析模型中也被当作中缀处理。
     * @private
     */
    private var _infixParselets:Object;

    /**
     * PrattParser 的构造函数。
     * 
     * @param lexer 一个已经初始化并准备好提供 Token 的 PrattLexer} 实例。
     */
    function PrattParser(lexer:PrattLexer) {
        _lexer = lexer;
        _prefixParselets = {};
        _infixParselets = {};
        // 初始化解析器时，自动注册所有默认支持的语法规则。
        _initializeDefaultParselets();
    }

    /* ----------------------------------------------------------------------------
     * 初始化默认解析器
     * --------------------------------------------------------------------------*/
    
    /**
     * 注册Gesh脚本语言的默认语法规则。
     * 此方法设置了所有内建的字面量、运算符、和语法结构的解析方式。
     * 它通过调用 registerPrefix 和 registerInfix 将 Token 与相应的 PrattParselet关联起来。
     * 
     * 定义的语法包括：
     * 
     *   前缀部分: 字面量 (数字, 字符串,布尔等), 标识符, 分组 `()`, 数组 `[]`, 对象 `{}`, 和一元运算符 `-, +, !, typeof`。
     *   中缀部分: 所有二元运算符 (按标准优先级和结合性), 三元运算符 `? :`, 以及访问操作 (函数调用 `()`, 属性访问 `.`, 数组访问 `[]`)。
     * 
     * @private
     */
    private function _initializeDefaultParselets():Void {
        // --- 前缀解析器 (Prefix Parselets) ---
        // 这些 Token 可以开始一个新的表达式。

        // 注册各种字面量类型
        registerPrefix(PrattToken.T_NUMBER, PrattParselet.literal());
        registerPrefix(PrattToken.T_STRING, PrattParselet.literal());
        registerPrefix(PrattToken.T_BOOLEAN, PrattParselet.literal());
        registerPrefix(PrattToken.T_NULL, PrattParselet.literal());
        registerPrefix(PrattToken.T_UNDEFINED, PrattParselet.literal());
        
        // 注册标识符 (如变量名)
        registerPrefix(PrattToken.T_IDENTIFIER, PrattParselet.identifier());
        
        // 注册分组表达式的开始符
        registerPrefix(PrattToken.T_LPAREN, PrattParselet.group());
        
        // 注册数组字面量的开始符
        registerPrefix(PrattToken.T_LBRACKET, PrattParselet.arrayLiteral())
        
        // 注册对象字面量的开始符
        registerPrefix(PrattToken.T_LBRACE, PrattParselet.objectLiteral());

        // --- 前缀运算符 (Prefix Operators) ---
        // 注意：一元运算符是按其文本注册的，因为它们的 Token 类型可能是通用的 T_OPERATOR。
        registerPrefix("-", PrattParselet.prefixOperator(7)); // 一元负号
        registerPrefix("+", PrattParselet.prefixOperator(7)); // 一元正号 (用于类型转换)
        registerPrefix("!", PrattParselet.prefixOperator(7)); // 逻辑非
        registerPrefix(PrattToken.T_TYPEOF, PrattParselet.prefixOperator(7)); // typeof 运算符 (按类型注册)
        
        // --- 中缀解析器 (Infix Parselets) ---
        // 注册顺序无关紧要，优先级由 PrattParselet 内部定义。
        
        // 三元运算符 (?:)，优先级 1，右结合
        registerInfix("?", PrattParselet.ternaryOperator());
        
        // 逻辑或和空值合并，优先级 2，左结合
        registerInfix("||", PrattParselet.binaryOperator(2, false));
        registerInfix("??", PrattParselet.binaryOperator(2, false));
        
        // 逻辑与，优先级 3，左结合
        registerInfix("&&", PrattParselet.binaryOperator(3, false));
        
        // 相等比较，优先级 4，左结合
        registerInfix("==", PrattParselet.binaryOperator(4, false));
        registerInfix("!=", PrattParselet.binaryOperator(4, false));
        registerInfix("===", PrattParselet.binaryOperator(4, false));
        registerInfix("!==", PrattParselet.binaryOperator(4, false));
        
        // 关系比较，优先级 5，左结合
        registerInfix("<", PrattParselet.binaryOperator(5, false));
        registerInfix(">", PrattParselet.binaryOperator(5, false));
        registerInfix("<=", PrattParselet.binaryOperator(5, false));
        registerInfix(">=", PrattParselet.binaryOperator(5, false));
        
        // 加减，优先级 6，左结合
        registerInfix("+", PrattParselet.binaryOperator(6, false));
        registerInfix("-", PrattParselet.binaryOperator(6, false));
        
        // 乘除模，优先级 7，左结合
        registerInfix("*", PrattParselet.binaryOperator(7, false));
        registerInfix("/", PrattParselet.binaryOperator(7, false));
        registerInfix("%", PrattParselet.binaryOperator(7, false));
        
        // 指数，优先级 8，右结合
        registerInfix("**", PrattParselet.binaryOperator(8, true));
        
        // 访问操作，优先级 10 (最高)，左结合
        registerInfix("(", PrattParselet.functionCall()); // 函数调用
        registerInfix(".", PrattParselet.propertyAccess()); // 属性访问
        registerInfix("[", PrattParselet.arrayAccess()); // 数组/成员访问
    }

    /* ----------------------------------------------------------------------------
     * 注册解析器 (公共API)
     * --------------------------------------------------------------------------*/
    
    /**
     * 注册一个前缀 Parselet。
     * 用于扩展解析器以支持新的前缀语法（如新的一元运算符或字面量类型）。
     * 
     * @param tokenType 触发此 Parselet 的 Token 类型或文本。
     *                  例如: PrattToken.T_IDENTIFIER, 或 "!"。
     * @param parselet  一个 PrattParselet实例，定义了如何解析此 Token。
     */
    public function registerPrefix(tokenType:String, parselet:PrattParselet):Void {
        _prefixParselets[tokenType] = parselet;
    }

    /**
     * 注册一个中缀 Parselet。
     * 用于扩展解析器以支持新的中缀语法（如新的二元运算符）。
     * 
     * @param tokenText 触发此 Parselet 的 Token 文本。
     *                  必须是文本，例如 "+", "&&", 因为解析器需要通过它来查询优先级。
     * @param parselet  一个 PrattParselet实例，定义了如何解析此 Token。
     */
    public function registerInfix(tokenText:String, parselet:PrattParselet):Void {
        _infixParselets[tokenText] = parselet;
    }

    /* ----------------------------------------------------------------------------
     * Token 流控制
     * --------------------------------------------------------------------------*/
    
    /**
     * 获取当前待处理的 Token，但不消费它（即 "窥视"）。
     * 
     * @return {PrattToken} 当前的 Token。
     */
    public function getCurrentToken():PrattToken {
        return _lexer.peek();
    }

    /**
     * 消费并返回当前 Token，使 Token 流前进一个位置。
     * 这是解析器在 Token 流中向前移动的主要方式。
     * 
     * @return {PrattToken} 被消费的 Token。
     */
    public function consume():PrattToken {
        return _lexer.next();
    }

    /**
     * 消费当前 Token，但首先验证其类型是否符合预期。
     * 这是确保语法结构正确性的关键方法。
     * 
     * @param expectedType 期望的 Token 类型常量，例如 `PrattToken.T_RPAREN`。
     * @return {PrattToken} 如果类型匹配，则返回被消费的 Token。
     * @throws {Error} 如果当前 Token 类型与期望不符，则抛出语法错误。
     */
    public function consumeExpected(expectedType:String):PrattToken {
        var token:PrattToken = getCurrentToken();
        if (token.type != expectedType) {
            throw new Error("Expected T_" + expectedType + " but got " + token.type +
                          " at " + token.createError(""));
        }
        return consume();
    }

    /* ----------------------------------------------------------------------------
     * Token 类型检查
     * --------------------------------------------------------------------------*/
    
    /**
     * 检查当前 Token 的类型是否与给定类型匹配。
     * 
     * @param tokenType 要检查的 Token 类型。
     * @return {Boolean} 如果匹配则为 true，否则为 false。
     */
    public function match(tokenType:String):Boolean {
        return getCurrentToken().type == tokenType;
    }

    /**
     * 检查当前 Token 的文本是否与给定文本匹配。
     * 
     * @param tokenText 要检查的 Token 文本。
     * @return {Boolean} 如果匹配则为 true，否则为 false。
     */
    public function matchText(tokenText:String):Boolean {
        return getCurrentToken().text == tokenText;
    }

    /* ----------------------------------------------------------------------------
     * 优先级管理
     * --------------------------------------------------------------------------*/
    
    /**
     * 获取当前 Token 作为中缀运算符时的优先级。
     * 这是 Pratt 解析算法的核心，用于决定是否将当前 Token 作为右侧表达式的一部分进行解析。
     * 
     * @return {Number} 如果当前 Token 注册为中缀操作符，则返回其优先级。否则返回 0。
     */
    public function getPrecedence():Number {
        var token:PrattToken = getCurrentToken();
        var infixParselet:PrattParselet = _infixParselets[token.text];
        
        // 确保 parselet 存在且有 getPrecedence 方法
        if (infixParselet && infixParselet.getPrecedence) {
            return infixParselet.getPrecedence();
        }
        
        return 0; // 默认优先级为0，表示不是一个中缀运算符
    }

    /* ----------------------------------------------------------------------------
     * 核心解析方法
     * --------------------------------------------------------------------------*/
    
    /**
     * 核心解析循环，根据给定的最小优先级解析表达式。
     * 
     * 这是 Pratt 解析算法的 "心脏"。它首先解析一个前缀表达式 (如一个数字或变量)，
     * 然后进入一个循环，只要后续的中缀运算符的优先级高于 minPrecedence，
     * 它就会持续地将这些中缀运算合并到左侧的表达式中，形成一个更大的AST节点。
     * 
     * @param minPrecedence 当前解析上下文的最小运算符优先级。调用者用此参数来控制
     *                      此方法能“吃掉”多长的表达式。例如，在解析 `a + b * c` 时，
     *                      当解析完 `a +` 后，会以 `+` 的优先级递归调用 `parseExpression`
     *                      来解析右侧，这样 `*` (更高优先级) 就会被优先处理。
     * @return {PrattExpression} 解析生成的表达式AST节点。
     * @throws {Error} 如果遇到无法解析的 Token，则抛出语法错误。
     */
    public function parseExpression(minPrecedence:Number):PrattExpression {
        if (minPrecedence == undefined) minPrecedence = 0;
        
        // 1. 获取前缀表达式
        var token:PrattToken = consume();
        var prefixParselet:PrattParselet = _getPrefixParselet(token);
        
        if (prefixParselet == null) {
            throw new Error("Could not parse token: " + token.createError("Unexpected token"));
        }
        
        var left:PrattExpression = prefixParselet.parsePrefix(this, token);
        
        // 2. 循环处理优先级更高的中缀表达式
        while (minPrecedence < getPrecedence()) {
            token = consume(); // 消费中缀运算符
            var infixParselet:PrattParselet = _infixParselets[token.text];
            left = infixParselet.parseInfix(this, left, token);
        }
        
        return left;
    }

    /* ----------------------------------------------------------------------------
     * 主入口和辅助方法
     * --------------------------------------------------------------------------*/
    
    /**
     * 解析完整的表达式，并确保没有多余的 Token。
     * 这是提供给外部使用的主要入口点。
     * 
     * @return {PrattExpression} 完整的表达式AST。
     * @throws {Error} 如果表达式解析完毕后仍有剩余 Token (除了 T_EOF)，则抛出语法错误。
     */
    public function parse():PrattExpression {
        // 从最低优先级0开始解析，以捕获整个表达式。
        var expression:PrattExpression = parseExpression(0);
        
        // 验证表达式后面是否紧跟着文件结束符，确保没有非法尾随内容。
        if (!match(PrattToken.T_EOF)) {
            var token:PrattToken = getCurrentToken();
            throw new Error("Unexpected token after expression: " + token.createError(""));
        }
        
        return expression;
    }

    /**
     * 根据给定的 Token 获取相应的前缀 Parselet。
     * 
     * 查找顺序很重要：
     * 
     *   首先根据 Token 的文本查找。这用于处理特殊的运算符，如一元 `-`，
     *       它可能与二元 `-` 共享相同的 Token 类型 `T_OPERATOR`。
     *   如果按文本找不到，则根据 Token 的类型查找。这用于通用的 Token 类型，
     *       如 `T_NUMBER`, `T_IDENTIFIER` 等。
     * 
     * 
     * @param token 要为其查找 Parselet 的 Token。
     * @return PrattParselet 找到的 Parselet 实例，如果未找到则返回 null。
     * @private
     */
    private function _getPrefixParselet(token:PrattToken):PrattParselet {
        // 优先按文本查找，例如，区分前缀的 "-" 和中缀的 "-"
        var parselet:PrattParselet = _prefixParselets[token.text];
        if (parselet != null) {
            return parselet;
        }
        
        // 其次按类型查找，用于通用类型如数字、标识符等
        parselet = _prefixParselets[token.type];
        if (parselet != null) {
            return parselet;
        }
        
        return null;
    }
    
    /* ----------------------------------------------------------------------------
     * 自定义Buff运算符支持 (扩展示例)
     * --------------------------------------------------------------------------*/
    
    /**
     * 为解析器添加一套用于 "Buff系统" 的自定义运算符。
     * 这是一个展示解析器可扩展性的示例方法。
     * 通过调用此方法，可以动态地向解析器实例中添加新的语法规则。
     * 
     * 添加的运算符包括：
     * 
     *   `@` (中缀): Buff应用运算符，优先级为9。
     *   `~>` (中缀): Buff链式运算符，优先级为3，右结合。
     *   `$` (前缀): Buff变量引用，优先级为8。
     * 
     */
    public function addBuffOperators():Void {
        // Buff系统专用运算符
        registerInfix("@", PrattParselet.binaryOperator(9, false)); // Buff应用运算符
        registerInfix("~>", PrattParselet.binaryOperator(3, true)); // Buff链式运算符
        registerPrefix("$", PrattParselet.prefixOperator(8)); // Buff变量引用
    }
}