import org.flashNight.gesh.pratt.*;

// 前缀运算符解析器
class org.flashNight.gesh.pratt.PrefixOperatorParselet {
    private var _precedence:Number;
    
    public function PrefixOperatorParselet(precedence:Number) {
        _precedence = precedence || 8;
    }
    
    public function parse(parser:PrattParser, token:PrattToken):Expression {
        var operand:Expression = parser.parseExpression(_precedence);
        return new UnaryExpression(token.text, operand);
    }
    
    public function getPrecedence():Number {
        return _precedence;
    }
}