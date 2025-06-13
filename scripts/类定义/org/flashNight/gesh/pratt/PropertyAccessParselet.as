import org.flashNight.gesh.pratt.*;
// 属性访问解析器
class org.flashNight.gesh.pratt.PropertyAccessParselet {
    public function parse(parser:PrattParser, left:Expression, token:PrattToken):Expression {
        var propertyToken:PrattToken = parser.consumeExpected(PrattToken.T_IDENTIFIER);
        return new PropertyAccessExpression(left, propertyToken.text);
    }
    
    public function getPrecedence():Number {
        return 10; // 属性访问最高优先级
    }
}
