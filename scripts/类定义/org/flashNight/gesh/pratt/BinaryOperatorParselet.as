import org.flashNight.gesh.pratt.*;

// 二元运算符解析器
class org.flashNight.gesh.pratt.BinaryOperatorParselet {
    private var _precedence:Number;
    private var _rightAssociative:Boolean;
    
    public function BinaryOperatorParselet(precedence:Number, rightAssoc:Boolean) {
        _precedence = precedence;
        _rightAssociative = rightAssoc || false;
    }
    
    public function parse(parser:PrattParser, left:Expression, token:PrattToken):Expression {
        var nextPrecedence:Number = _rightAssociative ? _precedence - 1 : _precedence + 1;
        var right:Expression = parser.parseExpression(nextPrecedence);
        return new BinaryExpression(left, token.text, right);
    }
    
    public function getPrecedence():Number {
        return _precedence;
    }
}