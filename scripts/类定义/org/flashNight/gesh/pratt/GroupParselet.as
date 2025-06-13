import org.flashNight.gesh.pratt.*;
// 分组解析器（括号）
class org.flashNight.gesh.pratt.GroupParselet {
    public function parse(parser:PrattParser, token:PrattToken):Expression {
        var expr:Expression = parser.parseExpression(0);
        parser.consumeExpected(PrattToken.T_RPAREN);
        return expr;
    }
}