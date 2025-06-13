import org.flashNight.gesh.pratt.*;

// 三元运算符解析器
class TernaryOperatorParselet {
    public function parse(parser:PrattParser, left:Expression, token:PrattToken):Expression {
        var trueExpr:Expression = parser.parseExpression(0);
        parser.consumeExpected(PrattToken.T_COLON);
        var falseExpr:Expression = parser.parseExpression(1);
        return new TernaryExpression(left, trueExpr, falseExpr);
    }
    
    public function getPrecedence():Number {
        return 1; // 三元运算符优先级很低
    }
}
