import org.flashNight.gesh.pratt.*;
// 函数调用解析器
class org.flashNight.gesh.pratt.FunctionCallParselet {
    public function parse(parser:PrattParser, left:Expression, token:PrattToken):Expression {
        var args:Array = [];
        
        // 解析参数列表
        if (!parser.match(PrattToken.T_RPAREN)) {
            do {
                args.push(parser.parseExpression(0));
            } while (parser.match(PrattToken.T_COMMA) && parser.consume());
        }
        
        parser.consumeExpected(PrattToken.T_RPAREN);
        return new FunctionCallExpression(left, args);
    }
    
    public function getPrecedence():Number {
        return 10; // 函数调用最高优先级
    }
}