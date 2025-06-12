/* -------------------------------------------------------------------------
 *  PrattLexer.as  —— 简易词法分析器（默认实现）
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.PrattLexer {
    private var _src:String;
    private var _idx:Number = 0;
    private var _len:Number;
    private var _curr:org.flashNight.gesh.pratt.PrattToken;

    function PrattLexer(src:String) {
        _src = src;
        _len = src.length;
        _advance();
    }

    /* 对外接口 */
    public function peek() {
        return _curr;
    }
    public function next() {
        var t = _curr;
        _advance();
        return t;
    }

    /* 内部：扫描下一个 token */
    private function _advance() {
        // 跳过空白
        while (_idx < _len && _isBlank(_src.charAt(_idx))) ++_idx;
        if (_idx >= _len) {
            _curr = new PrattToken(PrattToken.T_EOF, "<eof>");
            return;
        }
        var ch = _src.charAt(_idx);
        // 数字
        if (_isDigit(ch)) {
            var start = _idx;
            while (_idx < _len && _isDigit(_src.charAt(_idx))) ++_idx;
            var numText = _src.substr(start, _idx - start);
            _curr = new PrattToken(PrattToken.T_NUMBER, numText);
            return;
        }
        // 标识符 / 关键字
        if (_isAlpha(ch) || ch == "_") {
            var s = _idx;
            while (_idx < _len && _isAlnum(_src.charAt(_idx))) ++_idx;
            var idText = _src.substr(s, _idx - s);
            _curr = new PrattToken(PrattToken.T_IDENTIFIER, idText);
            return;
        }
        // 括号
        if (ch == "(") {
            ++_idx; _curr = new PrattToken(PrattToken.T_LPAREN, "("); return; }
        if (ch == ")") {
            ++_idx; _curr = new PrattToken(PrattToken.T_RPAREN, ")"); return; }
        // 其它单字符当作运算符
        ++_idx;
        _curr = new PrattToken(PrattToken.T_OPERATOR, ch);
    }

    /* ── 字符类别判定 ───────────────────────────────────────────────── */
    private function _isBlank(c:String){ return c == " " || c == "\t" || c == "\n" || c == "\r"; }
    private function _isDigit(c:String){ var code = c.charCodeAt(0); return code >= 48 && code <= 57; }
    private function _isAlpha(c:String){ var code = c.charCodeAt(0); return (code >= 65 && code <= 90) || (code >= 97 && code <= 122); }
    private function _isAlnum(c:String){ return _isAlpha(c) || _isDigit(c) || c == "_"; }
}
