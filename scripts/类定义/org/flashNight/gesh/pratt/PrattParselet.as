import org.flashNight.gesh.pratt.*;

/**
 * 统一的解析器类 - 合并所有Parselet功能
 * 使用策略模式处理不同的解析场景
 */
class org.flashNight.gesh.pratt.PrattParselet {
    // Parselet类型
    public static var PREFIX:String = "PREFIX";
    public static var INFIX:String = "INFIX";
    
    // 子类型
    public static var LITERAL:String = "LITERAL";
    public static var IDENTIFIER:String = "IDENTIFIER";
    public static var GROUP:String = "GROUP";
    public static var PREFIX_OPERATOR:String = "PREFIX_OPERATOR";
    public static var BINARY_OPERATOR:String = "BINARY_OPERATOR";
    public static var TERNARY_OPERATOR:String = "TERNARY_OPERATOR";
    public static var FUNCTION_CALL:String = "FUNCTION_CALL";
    public static var PROPERTY_ACCESS:String = "PROPERTY_ACCESS";
    public static var ARRAY_ACCESS:String = "ARRAY_ACCESS";
    public static var ARRAY_LITERAL:String = "ARRAY_LITERAL";
    public static var OBJECT_LITERAL:String = "OBJECT_LITERAL";
    
    private var _type:String;
    private var _subType:String;
    private var _precedence:Number;
    private var _rightAssociative:Boolean;
    
    public function PrattParselet(type:String, subType:String, precedence:Number, rightAssoc:Boolean) {
        _type = type;
        _subType = subType;
        _precedence = precedence || 0;
        _rightAssociative = rightAssoc || false;
    }
    
    // 静态工厂方法
    public static function literal():PrattParselet {
        return new PrattParselet(PREFIX, LITERAL, 0, false);
    }
    
    public static function identifier():PrattParselet {
        return new PrattParselet(PREFIX, IDENTIFIER, 0, false);
    }
    
    public static function group():PrattParselet {
        return new PrattParselet(PREFIX, GROUP, 0, false);
    }
        
    public static function prefixOperator(precedence:Number):PrattParselet {
        // 默认使用 7，让 **（8）优先于一元 -, +, !, typeof
        var prec:Number = (precedence != undefined) ? precedence : 7;
        return new PrattParselet(PREFIX, PREFIX_OPERATOR, prec, false);
    }
        
    public static function binaryOperator(precedence:Number, rightAssoc:Boolean):PrattParselet {
        return new PrattParselet(INFIX, BINARY_OPERATOR, precedence, rightAssoc);
    }
    
    public static function ternaryOperator():PrattParselet {
        return new PrattParselet(INFIX, TERNARY_OPERATOR, 1, true);
    }
    
    public static function functionCall():PrattParselet {
        return new PrattParselet(INFIX, FUNCTION_CALL, 10, false);
    }
    
    public static function propertyAccess():PrattParselet {
        return new PrattParselet(INFIX, PROPERTY_ACCESS, 10, false);
    }
    
    public static function arrayAccess():PrattParselet {
        return new PrattParselet(INFIX, ARRAY_ACCESS, 10, false);
    }

    public static function arrayLiteral():PrattParselet {
        return new PrattParselet(PREFIX, ARRAY_LITERAL, 0, false);
    }

    public static function objectLiteral():PrattParselet {
        return new PrattParselet(PREFIX, OBJECT_LITERAL, 0, false);
    }
    
    // 主要的解析方法
    public function parsePrefix(parser:PrattParser, token:PrattToken):PrattExpression {
        switch (_subType) {
            case LITERAL:
                return _parseLiteral(token);
                
            case IDENTIFIER:
                return PrattExpression.identifier(token.text);
                
            case GROUP:
                var expr:PrattExpression = parser.parseExpression(0);
                parser.consumeExpected(PrattToken.T_RPAREN);
                return expr;
                
            case PREFIX_OPERATOR:
                var operand:PrattExpression = parser.parseExpression(_precedence);
                return PrattExpression.unary(token.text, operand);

            case ARRAY_LITERAL:
                var elements:Array = [];
                
                // 在循环处理非空数组之前，先检查是否是空数组。
                // 这样可以避免在空数组上进入循环。
                if (!parser.match(PrattToken.T_RBRACKET)) {
                    while (true) {
                        // 在尝试解析表达式之前，先检查是否是结尾。
                        // 这能正确处理尾随逗号，如 [1, 2,]
                        if (parser.match(PrattToken.T_RBRACKET)) {
                            break;
                        }

                        // 解析一个元素
                        elements.push(parser.parseExpression(0));

                        // 如果下一个 token 不是逗号，说明元素列表结束了
                        if (!parser.match(PrattToken.T_COMMA)) {
                            break;
                        }

                        // 消耗逗号，准备下一次循环
                        parser.consume();
                    }
                }
                
                // 无论循环如何结束（或从未开始），下一个 token 都必须是右方括号。
                // 这能为 `[1, 2, 3` 这样的情况提供最准确的错误信息。
                parser.consumeExpected(PrattToken.T_RBRACKET);
                
                return PrattExpression.arrayLiteral(elements);

            case OBJECT_LITERAL:
                var properties:Array = [];

                if (!parser.match(PrattToken.T_RBRACE)) {
                    while (true) {
                        if (parser.match(PrattToken.T_RBRACE)) {
                            break; // 支持尾随逗号
                        }

                        // 解析键 (可以是标识符或字符串)
                        var keyToken:PrattToken = parser.consume();
                        var key:String;
                        if (keyToken.type == PrattToken.T_IDENTIFIER) {
                            key = keyToken.text;
                        } else if (keyToken.type == PrattToken.T_STRING) {
                            key = keyToken.getStringValue();
                        } else {
                            throw new Error("Invalid object key: " + keyToken.createError("Expected identifier or string"));
                        }

                        parser.consumeExpected(PrattToken.T_COLON);
                        var value:PrattExpression = parser.parseExpression(0);
                        properties.push({key: key, value: value});

                        if (!parser.match(PrattToken.T_COMMA)) break;
                        parser.consume();
                    }
                }
                parser.consumeExpected(PrattToken.T_RBRACE);
                return PrattExpression.objectLiteral(properties);
                
            default:
                throw new Error("Invalid prefix parselet subtype: " + _subType);
        }
    }
    
    public function parseInfix(parser:PrattParser, left:PrattExpression, token:PrattToken):PrattExpression {
        switch (_subType) {
            case BINARY_OPERATOR:
                var nextPrecedence:Number = _rightAssociative ? _precedence - 1 : _precedence;
                var right:PrattExpression = parser.parseExpression(nextPrecedence);
                return PrattExpression.binary(left, token.text, right);
                
            case TERNARY_OPERATOR:
                // 原来：then 在 precedence=0 下完全吃尽，else 在 precedence=1 下吃尽

                // 统一用 next-min-precedence，这里 _precedence=1 且 _rightAssociative=true
                // 所以 nextPrec = 1 - 1 = 0
                var nextPrec:Number        = _rightAssociative ? _precedence - 1 : _precedence;
                var trueExpr:PrattExpression  = parser.parseExpression(nextPrec);
                parser.consumeExpected(PrattToken.T_COLON);
                var falseExpr:PrattExpression = parser.parseExpression(nextPrec);
                return PrattExpression.ternary(left, trueExpr, falseExpr);
                
            case FUNCTION_CALL:
                var args:Array = [];
                
                // 解析参数列表
                if (!parser.match(PrattToken.T_RPAREN)) {
                    do {
                        args.push(parser.parseExpression(0));
                    } while (parser.match(PrattToken.T_COMMA) && parser.consume());
                }
                
                parser.consumeExpected(PrattToken.T_RPAREN);
                return PrattExpression.functionCall(left, args);
                
            case PROPERTY_ACCESS:
                var propertyToken:PrattToken = parser.consumeExpected(PrattToken.T_IDENTIFIER);
                return PrattExpression.propertyAccess(left, propertyToken.text);
                
            case ARRAY_ACCESS:
                var index:PrattExpression = parser.parseExpression(0);
                parser.consumeExpected(PrattToken.T_RBRACKET);
                return PrattExpression.arrayAccess(left, index);
                
            default:
                throw new Error("Invalid infix parselet subtype: " + _subType);
        }
    }
    
    // 解析字面量
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
                throw new Error("Invalid literal token: " + token.type);
        }
    }
    
    // 获取优先级
    public function getPrecedence():Number {
        return _precedence;
    }
    
    // 检查是否为前缀解析器
    public function isPrefix():Boolean {
        return _type == PREFIX;
    }
    
    // 检查是否为中缀解析器
    public function isInfix():Boolean {
        return _type == INFIX;
    }
}