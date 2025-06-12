/* -------------------------------------------------------------------------
 *  PrattParser.as  —— 主解析器
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.PrattParser {
    private var _lex:org.flashNight.gesh.pratt.PrattLexer;

    function PrattParser(lex:org.flashNight.gesh.pratt.PrattLexer) {
        _lex = lex;
    }

    /* ----------------------------------------------------------------------------
     * 公共入口：parse()
     * 返回值：可执行函数 (Function) 或直接值，具体由 nud / led 的实现决定。
     * --------------------------------------------------------------------------*/
    public function parse() {
        var result = _parseExpression(0);
        var t = _lex.peek();
        if (t.type != org.flashNight.gesh.pratt.PrattToken.T_EOF) {
            throw new Error("PrattParser: 未消费完的输入 @ " + t.text);
        }
        return (typeof result == "function") ? result() : result;
    }

    /* ----------------------------------------------------------------------------
     * 内部：解析表达式（Iterative Pratt，右侧仍有一层递归用以处理右结合）
     * --------------------------------------------------------------------------*/
    private function _parseExpression(minBP:Number) {
        var tok = _lex.next();
        var nud = org.flashNight.gesh.pratt.PrattRegistry.getPrefix(tok.type);
        if (nud == null) {
            // 尝试直接把字面量作为前缀（数字 / 标识符）
            if (tok.type == org.flashNight.gesh.pratt.PrattToken.T_NUMBER) {
                var lit = Number(tok.value);
                nud = function(){ return lit; };
            } else if (tok.type == org.flashNight.gesh.pratt.PrattToken.T_LPAREN) {
                var inner = _parseExpression(0);
                var rp = _lex.next();
                if (rp.type != org.flashNight.gesh.pratt.PrattToken.T_RPAREN) {
                    throw new Error("PrattParser: 缺少右括号");
                }
                nud = function(){ return inner; };
            } else {
                throw new Error("PrattParser: 无前缀解析器[" + tok.text + "]");
            }
        }
        var left = nud(tok);

        while (true) {
            var look = _lex.peek();
            var infix = org.flashNight.gesh.pratt.PrattRegistry.getInfix(look.text);
            if (infix == null) break;
            var bp = infix.bp;
            if (bp < minBP) break;
            // consume operator
            var opTok = _lex.next();
            var nextMin = bp + (infix.rightAssoc ? 0 : 1);
            var right = _parseExpression(nextMin);
            left = infix.led(left, right, opTok.text);
        }
        return left;
    }
}