import org.flashNight.gesh.pratt.*;

/**
 * 统一的解析策略类 (Unified Parselet)。
 * 
 * 该类是 Pratt 解析器框架的核心策略单元。它没有采用为每种语法规则创建单独子类的传统方式，
 * 而是使用策略模式，通过内部状态 (_type, _subType) 来封装所有不同的解析逻辑。
 * 每个 PrattParselet 实例都定义了如何处理一种特定的 Token 或语法结构。
 * 
 * 设计目标：
 * - 将解析逻辑从主解析器 (PrattParser) 中解耦。
 * - 通过统一的类和静态工厂方法，简化新语法规则的创建和管理。
 * - 集中处理所有与特定 Token 相关的解析行为，包括其优先级和结合性。
 * 
 * @see PrattParser 持有并调用这些 Parselet 实例的主解析器。
 */
class org.flashNight.gesh.pratt.PrattParselet {
    // --- Parselet 主类型 ---

    /** 标识一个前缀 Parselet，用于处理可以开始一个表达式的 Token (如字面量、一元运算符)。 */
    public static var PREFIX:String = "PREFIX";
    /** 标识一个中缀/后缀 Parselet，用于处理出现在两个表达式之间的 Token (如二元运算符、函数调用符 `(`)。 */
    public static var INFIX:String = "INFIX";
    
    // --- Parselet 子类型 (具体的解析策略) ---

    /** 解析字面量，如 123, "hello", true, null。 */
    public static var LITERAL:String = "LITERAL";
    /** 解析标识符，如变量名 myVar。 */
    public static var IDENTIFIER:String = "IDENTIFIER";
    /** 解析分组表达式，即 `(...)`。 */
    public static var GROUP:String = "GROUP";
    /** 解析前缀运算符，如 `-a`, `!b`。 */
    public static var PREFIX_OPERATOR:String = "PREFIX_OPERATOR";
    /** 解析二元运算符，如 `a + b`。 */
    public static var BINARY_OPERATOR:String = "BINARY_OPERATOR";
    /** 解析三元条件运算符，如 `a ? b : c`。 */
    public static var TERNARY_OPERATOR:String = "TERNARY_OPERATOR";
    /** 解析函数调用，如 `func(...)`。 */
    public static var FUNCTION_CALL:String = "FUNCTION_CALL";
    /** 解析属性访问，如 `obj.prop`。 */
    public static var PROPERTY_ACCESS:String = "PROPERTY_ACCESS";
    /** 解析数组成员访问，如 `arr[...]`。 */
    public static var ARRAY_ACCESS:String = "ARRAY_ACCESS";
    /** 解析数组字面量，如 `[...]`。 */
    public static var ARRAY_LITERAL:String = "ARRAY_LITERAL";
    /** 解析对象字面量，如 `{...}`。 */
    public static var OBJECT_LITERAL:String = "OBJECT_LITERAL";
    
    /** Parselet 的主类型 (PREFIX 或 INFIX)。 */
    private var _type:String;
    /** Parselet 的具体解析策略子类型。 */
    private var _subType:String;
    /** 对于中缀操作符，此为其优先级 (binding power)，决定了运算顺序。 */
    private var _precedence:Number;
    /** 标记中缀操作符是否为右结合 (如幂运算 `**` 和三元运算 `?:`)。 */
    private var _rightAssociative:Boolean;
    
    /**
     * PrattParselet 的内部构造函数。
     * 通常不直接调用，应优先使用本类提供的静态工厂方法。
     * 
     * @param type 主类型 (PREFIX 或 INFIX)。
     * @param subType 子类型，定义具体解析行为。
     * @param precedence 运算符优先级，默认为 0。
     * @param rightAssoc 是否右结合，默认为 false (即左结合)。
     */
    public function PrattParselet(type:String, subType:String, precedence:Number, rightAssoc:Boolean) {
        _type = type;
        _subType = subType;
        _precedence = precedence || 0;
        _rightAssociative = rightAssoc || false;
    }
    
    // --- 静态工厂方法 (推荐的创建方式) ---

    /** 创建一个用于解析字面量 (数字、字符串、布尔等) 的前缀 Parselet。 */
    public static function literal():PrattParselet {
        return new PrattParselet(PREFIX, LITERAL, 0, false);
    }
    
    /** 创建一个用于解析标识符 (变量名) 的前缀 Parselet。 */
    public static function identifier():PrattParselet {
        return new PrattParselet(PREFIX, IDENTIFIER, 0, false);
    }
    
    /** 创建一个用于解析分组表达式 `(...)` 的前缀 Parselet。 */
    public static function group():PrattParselet {
        return new PrattParselet(PREFIX, GROUP, 0, false);
    }
        
    /** 
     * 创建一个用于解析前缀运算符 (如 `!`, `-`) 的 Parselet。
     * @param precedence 运算符的优先级。
     *                   默认值为 7，此设计是为了让它的优先级低于指数运算符 `**` (优先级8)，
     *                   从而正确解析 `-2 ** 2` 为 `-(2 ** 2)`。
     */
    public static function prefixOperator(precedence:Number):PrattParselet {
        var prec:Number = (precedence != undefined) ? precedence : 7;
        return new PrattParselet(PREFIX, PREFIX_OPERATOR, prec, false);
    }
        
    /** 
     * 创建一个用于解析二元运算符 (如 `+`, `*`) 的中缀 Parselet。
     * @param precedence 运算符的优先级。
     * @param rightAssoc 是否为右结合。
     */
    public static function binaryOperator(precedence:Number, rightAssoc:Boolean):PrattParselet {
        return new PrattParselet(INFIX, BINARY_OPERATOR, precedence, rightAssoc);
    }
    
    /** 创建一个用于解析三元运算符 `?` 的中缀 Parselet。优先级为1，右结合。 */
    public static function ternaryOperator():PrattParselet {
        return new PrattParselet(INFIX, TERNARY_OPERATOR, 1, true);
    }
    
    /** 创建一个用于解析函数调用 `()` 的中缀 Parselet。优先级高，为10。 */
    public static function functionCall():PrattParselet {
        return new PrattParselet(INFIX, FUNCTION_CALL, 10, false);
    }
    
    /** 创建一个用于解析属性访问 `.` 的中缀 Parselet。优先级高，为10。 */
    public static function propertyAccess():PrattParselet {
        return new PrattParselet(INFIX, PROPERTY_ACCESS, 10, false);
    }
    
    /** 创建一个用于解析数组成员访问 `[]` 的中缀 Parselet。优先级高，为10。 */
    public static function arrayAccess():PrattParselet {
        return new PrattParselet(INFIX, ARRAY_ACCESS, 10, false);
    }

    /** 创建一个用于解析数组字面量 `[...]` 的前缀 Parselet。 */
    public static function arrayLiteral():PrattParselet {
        return new PrattParselet(PREFIX, ARRAY_LITERAL, 0, false);
    }

    /** 创建一个用于解析对象字面量 `{...}` 的前缀 Parselet。 */
    public static function objectLiteral():PrattParselet {
        return new PrattParselet(PREFIX, OBJECT_LITERAL, 0, false);
    }
    
    // --- 主要的解析方法 ---
    
    /**
     * 执行前缀解析。当 PrattParser 遇到一个可以开始表达式的 Token 时调用此方法。
     * 
     * @param parser 主解析器实例，用于递归调用以解析子表达式。
     * @param token 触发此前缀解析的 Token。
     * @return {PrattExpression} 解析生成的 AST 节点。
     */
    public function parsePrefix(parser:PrattParser, token:PrattToken):PrattExpression {
        switch (_subType) {
            case LITERAL:
                return _parseLiteral(token);
                
            case IDENTIFIER:
                return PrattExpression.identifier(token.text);
                
            case GROUP:
                // 解析括号内的表达式，优先级设为0以解析完整内容
                var expr:PrattExpression = parser.parseExpression(0);
                // 必须消费一个右括号来匹配
                parser.consumeExpected(PrattToken.T_RPAREN);
                return expr;
                
            case PREFIX_OPERATOR:
                // 递归解析右侧的操作数，使用当前运算符的优先级作为最小优先级
                var operand:PrattExpression = parser.parseExpression(_precedence);
                return PrattExpression.unary(token.text, operand);

            case ARRAY_LITERAL:
                var elements:Array = [];
                
                // 检查是否为空数组 `[]`
                if (!parser.match(PrattToken.T_RBRACKET)) {
                    while (true) {
                        // 支持尾随逗号，如 `[1, 2,]`。先检查是否到达结尾。
                        if (parser.match(PrattToken.T_RBRACKET)) {
                            break;
                        }

                        // 解析一个数组元素
                        elements.push(parser.parseExpression(0));

                        // 如果下一个不是逗号，则元素列表结束
                        if (!parser.match(PrattToken.T_COMMA)) {
                            break;
                        }

                        // 消费逗号，为下一个元素做准备
                        parser.consume();
                    }
                }
                
                // 必须以右方括号结束
                parser.consumeExpected(PrattToken.T_RBRACKET);
                
                return PrattExpression.arrayLiteral(elements);

            case OBJECT_LITERAL:
                var properties:Array = [];

                // 检查是否为空对象 `{}`
                if (!parser.match(PrattToken.T_RBRACE)) {
                    while (true) {
                        // 支持尾随逗号
                        if (parser.match(PrattToken.T_RBRACE)) {
                            break; 
                        }

                        // 解析属性键，可以是无引号的标识符或带引号的字符串
                        var keyToken:PrattToken = parser.consume();
                        var key:String;
                        if (keyToken.type == PrattToken.T_IDENTIFIER) {
                            key = keyToken.text;
                        } else if (keyToken.type == PrattToken.T_STRING) {
                            key = keyToken.getStringValue();
                        } else {
                            throw new Error("Invalid object key: " + keyToken.createError("Expected identifier or string"));
                        }

                        // 键后面必须是冒号
                        parser.consumeExpected(PrattToken.T_COLON);
                        
                        // 解析属性值
                        var value:PrattExpression = parser.parseExpression(0);
                        properties.push({key: key, value: value});

                        // 如果下一个不是逗号，则属性列表结束
                        if (!parser.match(PrattToken.T_COMMA)) break;
                        
                        // 消费逗号
                        parser.consume();
                    }
                }
                
                // 必须以右大括号结束
                parser.consumeExpected(PrattToken.T_RBRACE);
                return PrattExpression.objectLiteral(properties);
                
            default:
                throw new Error("Invalid prefix parselet subtype: " + _subType);
        }
    }
    
    /**
     * 执行中缀解析。当 PrattParser 解析完一个表达式后，遇到一个中缀 Token 时调用此方法。
     * 
     * @param parser 主解析器实例，用于递归调用。
     * @param left 已经解析好的、位于当前中缀 Token 左侧的表达式 (AST)。
     * @param token 触发此中缀解析的 Token。
     * @return {PrattExpression} 将 `left` 与新解析的部分组合成一个新的、更大的 AST 节点。
     */
    public function parseInfix(parser:PrattParser, left:PrattExpression, token:PrattToken):PrattExpression {
        switch (_subType) {
            case BINARY_OPERATOR:
                // 计算右侧表达式的最小优先级，这是处理结合性的关键。
                // - 对于左结合 (`a+b+c` -> `(a+b)+c`)，右侧的优先级不能低于当前操作符。
                // - 对于右结合 (`a**b**c` -> `a**(b**c)`)，右侧的优先级可以低于当前操作符，所以减1。
                var nextPrecedence:Number = _rightAssociative ? _precedence - 1 : _precedence;
                var right:PrattExpression = parser.parseExpression(nextPrecedence);
                return PrattExpression.binary(left, token.text, right);
                
            case TERNARY_OPERATOR:
                // 三元运算符是右结合的，`_precedence`为1，所以 nextPrec = 1 - 1 = 0。
                // 这意味着 `then` 和 `else` 分支中的表达式都会被完整解析（直到遇到更低优先级的运算符或结尾）。
                var nextPrec:Number        = _rightAssociative ? _precedence - 1 : _precedence;
                var trueExpr:PrattExpression  = parser.parseExpression(nextPrec);
                parser.consumeExpected(PrattToken.T_COLON);
                var falseExpr:PrattExpression = parser.parseExpression(nextPrec);
                return PrattExpression.ternary(left, trueExpr, falseExpr);
                
            case FUNCTION_CALL:
                var args:Array = [];
                
                // 解析由逗号分隔的参数列表
                if (!parser.match(PrattToken.T_RPAREN)) {
                    do {
                        // 每个参数都是一个完整的表达式
                        args.push(parser.parseExpression(0));
                    } while (parser.match(PrattToken.T_COMMA) && parser.consume());
                }
                
                parser.consumeExpected(PrattToken.T_RPAREN);
                return PrattExpression.functionCall(left, args);
                
            case PROPERTY_ACCESS:
                // `.` 后面必须跟一个标识符作为属性名
                var propertyToken:PrattToken = parser.consumeExpected(PrattToken.T_IDENTIFIER);
                return PrattExpression.propertyAccess(left, propertyToken.text);
                
            case ARRAY_ACCESS:
                // `[` 和 `]` 之间是一个完整的表达式作为索引
                var index:PrattExpression = parser.parseExpression(0);
                parser.consumeExpected(PrattToken.T_RBRACKET);
                return PrattExpression.arrayAccess(left, index);
                
            default:
                throw new Error("Invalid infix parselet subtype: " + _subType);
        }
    }
    
    /**
     * 解析字面量 Token，将其转换为包含实际值的 LiteralExpression。
     * 这是一个内部辅助方法，由 `parsePrefix` 在 `_subType` 为 `LITERAL` 时调用。
     * 
     * @param token 要解析的字面量 Token。
     * @return {PrattExpression} 一个字面量表达式节点。
     * @private
     */
    private function _parseLiteral(token:PrattToken):PrattExpression {
        switch (token.type) {
            case PrattToken.T_NUMBER:
                return PrattExpression.literal(token.getNumberValue());
            case PrattToken.T_STRING:
                return PrattExpression.literal(token.getStringValue());
            case PrattToken.T_BOOLEAN:
                return PrattExpression.literal(token.getBooleanValue());
            case PrattToken.T_NULL:
                return PrattExpression.literal(null);
            case PrattToken.T_UNDEFINED:
                return PrattExpression.literal(undefined);
            default:
                // 这是一个逻辑错误，因为调用此方法时已确认是字面量类型。
                throw new Error("Invalid literal token: " + token.type);
        }
    }
    
    // --- 访问器方法 ---
    
    /**
     * 获取此 Parselet (如果作为中缀) 的优先级。
     * PrattParser 使用此值来决定运算顺序。
     * @return {Number} 优先级数值。
     */
    public function getPrecedence():Number {
        return _precedence;
    }
    
    /**
     * 检查此 Parselet 是否为前缀类型。
     * @return {Boolean} 如果是前缀类型则为 true。
     */
    public function isPrefix():Boolean {
        return _type == PREFIX;
    }
    
    /**
     * 检查此 Parselet 是否为中缀类型。
     * @return {Boolean} 如果是中缀类型则为 true。
     */
    public function isInfix():Boolean {
        return _type == INFIX;
    }
}