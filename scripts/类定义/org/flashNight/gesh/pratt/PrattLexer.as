import org.flashNight.gesh.pratt.*;


// ============================================================================
// Lexer类 - 词法分析器
// ============================================================================
class org.flashNight.gesh.pratt.PrattLexer {
    private var _src:String;
    private var _idx:Number = 0;
    private var _len:Number;
    private var _curr:PrattToken;
    private var _line:Number = 1;
    private var _column:Number = 1;
    private var _keywords:Object;

    function PrattLexer(src:String) {
        _src = src;
        _len = src.length;
        _initKeywords();
        _advance();
    }

    private function _initKeywords():Void {
        _keywords = {};

        // 使用字符串拼接避免关键词字面量问题
        _keywords["" + true] = PrattToken.T_BOOLEAN;
        _keywords["" + false] = PrattToken.T_BOOLEAN;
        _keywords["null"] = PrattToken.T_NULL;
        _keywords["undefined"] = PrattToken.T_UNDEFINED;
        _keywords["if"] = PrattToken.T_IF;
        _keywords["else"] = PrattToken.T_ELSE;
        _keywords["and"] = PrattToken.T_AND;
        _keywords["or"] = PrattToken.T_OR;
        _keywords["not"] = PrattToken.T_NOT;
    }


    public function peek():PrattToken {
        return _curr;
    }
    
    public function next():PrattToken {
        var t:PrattToken = _curr;
        _advance();
        return t;
    }

    private function _advance():Void {
        _skipWhitespaceAndComments();
        
        if (_idx >= _len) {
            _curr = new PrattToken(PrattToken.T_EOF, "<eof>", _line, _column);
            return;
        }

        var ch:String = _src.charAt(_idx);
        var startLine:Number = _line;
        var startColumn:Number = _column;

        // 数字 (整数或小数点开头的浮点数)
        if (_isDigit(ch) || (ch == "." && _idx + 1 < _len && _isDigit(_src.charAt(_idx + 1)))) {
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

    private function _scanNumber(startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        var hasDot:Boolean = false;

        // 整数部分
        while (_idx < _len && _isDigit(_src.charAt(_idx))) {
            _advanceChar();
        }

        // 小数部分
        if (_idx < _len && _src.charAt(_idx) == "." && !hasDot) {
            hasDot = true;
            _advanceChar();
            while (_idx < _len && _isDigit(_src.charAt(_idx))) {
                _advanceChar();
            }
        }

        var numText:String = _src.substr(start, _idx - start);
        var value:Number = hasDot ? parseFloat(numText) : parseInt(numText);
        
        return new PrattToken(PrattToken.T_NUMBER, numText, startLine, startColumn, value);
    }

    private function _scanIdentifier(startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        
        while (_idx < _len && _isAlnum(_src.charAt(_idx))) {
            _advanceChar();
        }

        var text:String = _src.substr(start, _idx - start);
        var tokenType:String = _keywords[text] || PrattToken.T_IDENTIFIER;
        
        return new PrattToken(tokenType, text, startLine, startColumn);
    }

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
            case "??":
                _advanceChar();
                _advanceChar();
                return double;
        }

        return null;
    }

    private function _skipWhitespaceAndComments():Void {
        while (_idx < _len) {
            var ch:String = _src.charAt(_idx);
            
            if (_isWhitespace(ch)) {
                _advanceChar();
                continue;
            }
            
            // 单行注释
            if (ch == "/" && _idx + 1 < _len && _src.charAt(_idx + 1) == "/") {
                _advanceChar();
                _advanceChar();
                while (_idx < _len && _src.charAt(_idx) != "\n") {
                    _advanceChar();
                }
                continue;
            }
            
            // 多行注释
            if (ch == "/" && _idx + 1 < _len && _src.charAt(_idx + 1) == "*") {
                _advanceChar();
                _advanceChar();

                // ==================== FIX START (PrattLexer.as) ====================
                // 修正循环条件，允许 _idx 到达最后一个字符
                while (_idx < _len) { 
                    // 检查 `*/` 时，需要确保 `_idx+1` 不会越界
                    if (_idx + 1 < _len && _src.charAt(_idx) == "*" && _src.charAt(_idx + 1) == "/") {
                        _advanceChar();
                        _advanceChar();
                        break; // 找到结尾，跳出循环
                    }
                    _advanceChar(); // 在注释内部前进
                }
                // ===================== FIX END (PrattLexer.as) =====================

                continue;
            }
            
            break;
        }
    }

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

    private function _isWhitespace(c:String):Boolean {
        return c == " " || c == "\t" || c == "\n" || c == "\r";
    }

    private function _isDigit(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        return code >= 48 && code <= 57;
    }

    private function _isAlpha(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    }

    private function _isAlnum(c:String):Boolean {
        return _isAlpha(c) || _isDigit(c) || c == "_" || c == "$";
    }
}