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
        return new PrattParselet(PREFIX, PREFIX_OPERATOR, precedence || 8, false);
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
                var trueExpr:PrattExpression = parser.parseExpression(0);
                parser.consumeExpected(PrattToken.T_COLON);
                var falseExpr:PrattExpression = parser.parseExpression(1);
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