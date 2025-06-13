import org.flashNight.gesh.pratt.*;

// ============================================================================
// 专用解析器（Parselets）
// ============================================================================

// 字面量解析器
class org.flashNight.gesh.pratt.LiteralParselet {
    public function parse(parser:PrattParser, token:PrattToken):Expression {
        switch (token.type) {
            case PrattToken.T_NUMBER:
                return new LiteralExpression(token.getNumberValue());
            case PrattToken.T_STRING:
                return new LiteralExpression(token.getStringValue());
            case PrattToken.T_BOOLEAN:
                return new LiteralExpression(token.getBooleanValue());
            case PrattToken.T_NULL:
                return new LiteralExpression(null);
            case PrattToken.T_UNDEFINED:
                return new LiteralExpression(undefined);
            default:
                throw new Error("Invalid literal token: " + token.type);
        }
    }
}