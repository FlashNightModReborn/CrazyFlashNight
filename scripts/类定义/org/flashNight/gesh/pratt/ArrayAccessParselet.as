import org.flashNight.gesh.pratt.*;
// 数组访问解析器
class org.flashNight.gesh.pratt.ArrayAccessParselet {
    public function parse(parser:PrattParser, left:Expression, token:PrattToken):Expression {
        var index:Expression = parser.parseExpression(0);
        parser.consumeExpected(PrattToken.T_RBRACKET);
        return new ArrayAccessExpression(left, index);
    }
    
    public function getPrecedence():Number {
        return 10; // 数组访问最高优先级
    }
}