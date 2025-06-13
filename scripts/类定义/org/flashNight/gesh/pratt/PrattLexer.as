import org.flashNight.gesh.pratt.*;

/* -------------------------------------------------------------------------
 *  增强版 PrattLexer.as —— 支持更多词法特性
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.PrattLexer {
    private var _src:String;
    private var _idx:Number = 0;
    private var _len:Number;
    private var _curr:PrattToken;
    private var _line:Number = 1;    // 行号
    private var _column:Number = 1;  // 列号
    private var _keywords:Object;    // 关键字映射

    function PrattLexer(src:String) {
        _src = src;
        _len = src.length;
        _initKeywords();
        _advance();
    }

    private function _initKeywords():Void {
        _keywords = {
            "true": PrattToken.T_BOOLEAN,
            "false": PrattToken.T_BOOLEAN,
            "null": PrattToken.T_NULL,
            "undefined": PrattToken.T_UNDEFINED,
            "if": PrattToken.T_IF,
            "else": PrattToken.T_ELSE,
            "and": PrattToken.T_AND,
            "or": PrattToken.T_OR,
            "not": PrattToken.T_NOT
        };
    }

    /* 对外接口 */
    public function peek():PrattToken {
        return _curr;
    }
    
    public function next():PrattToken {
        var t:PrattToken = _curr;
        _advance();
        return t;
    }

    public function getCurrentPosition():Object {
        return {line: _line, column: _column};
    }

    /* 内部：扫描下一个 token */
    private function _advance():Void {
        _skipWhitespaceAndComments();
        
        if (_idx >= _len) {
            _curr = new PrattToken(PrattToken.T_EOF, "<eof>", _line, _column);
            return;
        }

        var ch:String = _src.charAt(_idx);
        var startLine:Number = _line;
        var startColumn:Number = _column;

        // 数字（支持小数）
        if (_isDigit(ch)) {
            _curr = _scanNumber(startLine, startColumn);
            return;
        }

        // 标识符/关键字
        if (_isAlpha(ch) || ch == "_" || ch == "$") {
            _curr = _scanIdentifier(startLine, startColumn);
            return;
        }

        // 字符串
        if (ch == "\"" || ch == "'") {
            _curr = _scanString(ch, startLine, startColumn);
            return;
        }

        // 多字符运算符
        var multiChar:String = _scanMultiCharOperator();
        if (multiChar != null) {
            _curr = new PrattToken(PrattToken.T_OPERATOR, multiChar, startLine, startColumn);
            return;
        }

        // 特殊字符
        switch (ch) {
            case "(":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_LPAREN, "(", startLine, startColumn);
                return;
            case ")":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_RPAREN, ")", startLine, startColumn);
                return;
            case "[":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_LBRACKET, "[", startLine, startColumn);
                return;
            case "]":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_RBRACKET, "]", startLine, startColumn);
                return;
            case "{":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_LBRACE, "{", startLine, startColumn);
                return;
            case "}":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_RBRACE, "}", startLine, startColumn);
                return;
            case ",":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_COMMA, ",", startLine, startColumn);
                return;
            case ";":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_SEMICOLON, ";", startLine, startColumn);
                return;
            case ".":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_DOT, ".", startLine, startColumn);
                return;
            case "?":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_QUESTION, "?", startLine, startColumn);
                return;
            case ":":
                _advanceChar();
                _curr = new PrattToken(PrattToken.T_COLON, ":", startLine, startColumn);
                return;
        }

        // 单字符运算符
        _advanceChar();
        _curr = new PrattToken(PrattToken.T_OPERATOR, ch, startLine, startColumn);
    }

    /* 扫描数字（支持小数、科学计数法） */
    private function _scanNumber(startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        var hasDot:Boolean = false;
        var hasExp:Boolean = false;

        // 整数部分
        while (_idx < _len && _isDigit(_src.charAt(_idx))) {
            _advanceChar();
        }

        // 小数部分
        if (_idx < _len && _src.charAt(_idx) == "." && !hasDot) {
            hasDot = true;
            _advanceChar(); // 跳过小数点
            while (_idx < _len && _isDigit(_src.charAt(_idx))) {
                _advanceChar();
            }
        }

        // 科学计数法
        if (_idx < _len && (_src.charAt(_idx) == "e" || _src.charAt(_idx) == "E")) {
            hasExp = true;
            _advanceChar(); // 跳过 e/E
            if (_idx < _len && (_src.charAt(_idx) == "+" || _src.charAt(_idx) == "-")) {
                _advanceChar(); // 跳过符号
            }
            while (_idx < _len && _isDigit(_src.charAt(_idx))) {
                _advanceChar();
            }
        }

        var numText:String = _src.substr(start, _idx - start);
        var value:Number = hasDot || hasExp ? parseFloat(numText) : parseInt(numText);
        
        return new PrattToken(PrattToken.T_NUMBER, numText, startLine, startColumn, value);
    }

    /* 扫描标识符/关键字 */
    private function _scanIdentifier(startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        
        while (_idx < _len && _isAlnum(_src.charAt(_idx))) {
            _advanceChar();
        }

        var text:String = _src.substr(start, _idx - start);
        var tokenType:String = _keywords[text] || PrattToken.T_IDENTIFIER;
        
        return new PrattToken(tokenType, text, startLine, startColumn);
    }

    /* 扫描字符串 */
    private function _scanString(quote:String, startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        _advanceChar(); // 跳过开始引号
        
        var value:String = "";
        
        while (_idx < _len && _src.charAt(_idx) != quote) {
            var ch:String = _src.charAt(_idx);
            
            if (ch == "\\") {
                _advanceChar();
                if (_idx < _len) {
                    var escaped:String = _src.charAt(_idx);
                    switch (escaped) {
                        case "n": value += "\n"; break;
                        case "t": value += "\t"; break;
                        case "r": value += "\r"; break;
                        case "\\": value += "\\"; break;
                        case "\"": value += "\""; break;
                        case "'": value += "'"; break;
                        case "0": value += "\0"; break;
                        default: value += escaped; break;
                    }
                    _advanceChar();
                }
            } else {
                value += ch;
                _advanceChar();
            }
        }

        if (_idx < _len && _src.charAt(_idx) == quote) {
            _advanceChar(); // 跳过结束引号
        } else {
            throw new Error("未终止的字符串 at line " + startLine + ", column " + startColumn);
        }

        var fullText:String = _src.substr(start, _idx - start);
        return new PrattToken(PrattToken.T_STRING, fullText, startLine, startColumn, value);
    }

    /* 扫描多字符运算符 */
    private function _scanMultiCharOperator():String {
        var ch1:String = _src.charAt(_idx);
        var ch2:String = _idx + 1 < _len ? _src.charAt(_idx + 1) : "";
        var ch3:String = _idx + 2 < _len ? _src.charAt(_idx + 2) : "";

        // 三字符运算符
        var triple:String = ch1 + ch2 + ch3;
        if (triple == "===" || triple == "!==") {
            _advanceChar();
            _advanceChar();
            _advanceChar();
            return triple;
        }

        // 两字符运算符
        var double:String = ch1 + ch2;
        switch (double) {
            case "==":
            case "!=":
            case "<=":
            case ">=":
            case "&&":
            case "||":
            case "++":
            case "--":
            case "+=":
            case "-=":
            case "*=":
            case "/=":
            case "%=":
            case "**":
            case "<<":
            case ">>":
            case "??":
                _advanceChar();
                _advanceChar();
                return double;
        }

        return null;
    }

    /* 跳过空白和注释 */
    private function _skipWhitespaceAndComments():Void {
        while (_idx < _len) {
            var ch:String = _src.charAt(_idx);
            
            // 空白字符
            if (_isWhitespace(ch)) {
                _advanceChar();
                continue;
            }
            
            // 单行注释 //
            if (ch == "/" && _idx + 1 < _len && _src.charAt(_idx + 1) == "/") {
                _advanceChar();
                _advanceChar();
                while (_idx < _len && _src.charAt(_idx) != "\n") {
                    _advanceChar();
                }
                continue;
            }
            
            // 多行注释 /* */
            if (ch == "/" && _idx + 1 < _len && _src.charAt(_idx + 1) == "*") {
                _advanceChar();
                _advanceChar();
                while (_idx + 1 < _len) {
                    if (_src.charAt(_idx) == "*" && _src.charAt(_idx + 1) == "/") {
                        _advanceChar();
                        _advanceChar();
                        break;
                    }
                    _advanceChar();
                }
                continue;
            }
            
            break;
        }
    }

    /* 前进一个字符并更新位置 */
    private function _advanceChar():Void {
        if (_idx < _len) {
            if (_src.charAt(_idx) == "\n") {
                _line++;
                _column = 1;
            } else {
                _column++;
            }
            _idx++;
        }
    }

    /* 字符类别判定 */
    private function _isWhitespace(c:String):Boolean {
        return c == " " || c == "\t" || c == "\n" || c == "\r";
    }

    private function _isDigit(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        return code >= 48 && code <= 57; // 0-9
    }

    private function _isAlpha(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        return (code >= 65 && code <= 90) || (code >= 97 && code <= 122); // A-Z, a-z
    }

    private function _isAlnum(c:String):Boolean {
        return _isAlpha(c) || _isDigit(c) || c == "_" || c == "$";
    }

    /* 十六进制数字支持（扩展） */
    private function _isHexDigit(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        return _isDigit(c) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102); // A-F, a-f
    }

    /* 扫描十六进制数字 */
    private function _scanHexNumber(startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        _advanceChar(); // 跳过 '0'
        _advanceChar(); // 跳过 'x'

        while (_idx < _len && _isHexDigit(_src.charAt(_idx))) {
            _advanceChar();
        }

        var hexText:String = _src.substr(start, _idx - start);
        var value:Number = parseInt(hexText, 16);
        
        return new PrattToken(PrattToken.T_NUMBER, hexText, startLine, startColumn, value);
    }

    /* 添加自定义操作符支持 */
    public function addCustomOperator(operator:String):Void {
        // 可以在这里添加自定义操作符的识别逻辑
        // 这为buff系统提供了灵活性
    }

    /* 词法分析错误 */
    private function _lexError(message:String):Void {
        throw new Error("词法分析错误 at line " + _line + ", column " + _column + ": " + message);
    }

    /* 调试方法：获取所有tokens */
    public function getAllTokens():Array {
        var tokens:Array = [];
        var originalIdx:Number = _idx;
        var originalLine:Number = _line;
        var originalColumn:Number = _column;
        
        // 重置到开始
        _idx = 0;
        _line = 1;
        _column = 1;
        _advance();
        
        while (_curr.type != PrattToken.T_EOF) {
            tokens.push(_curr);
            _advance();
        }
        tokens.push(_curr); // 添加EOF
        
        // 恢复原始状态
        _idx = originalIdx;
        _line = originalLine;
        _column = originalColumn;
        
        return tokens;
    }
}