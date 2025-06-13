import org.flashNight.gesh.pratt.*;

// 标识符解析器
class org.flashNight.gesh.pratt.IdentifierParselet {
    public function parse(parser:PrattParser, token:PrattToken):Expression {
        return new IdentifierExpression(token.text);
    }
}