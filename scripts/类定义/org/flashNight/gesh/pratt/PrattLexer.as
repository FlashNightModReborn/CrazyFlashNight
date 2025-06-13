/**
 * @file PrattLexer.as
 * @description 定义了Pratt解析器使用的词法分析器（Lexer）。
 * 
 * 该文件中的 `PrattLexer` 类负责将原始的源代码字符串分解为一系列
 * 有意义的词法单元（`PrattToken`）。它是解析流程的第一步，为后续的
 * 语法分析（Parsing）提供输入。
 *
 * Lexer采用状态机模型，通过一次一个字符地扫描输入，来识别数字、字符串、
 * 标识符、关键字、运算符和分隔符。它还能够智能地跳过空白字符和注释，
 * 并精确地跟踪每个Token在源代码中的行号和列号，以便于生成准确的错误信息。
 */
import org.flashNight.gesh.pratt.*;

// ============================================================================
// Lexer类 - 词法分析器
// ============================================================================

/**
 * 一个词法分析器，将字符串源代码转换为 `PrattToken` 流。
 * 它实现了 "one-token lookahead"（单Token预读）功能，允许解析器通过 `peek()`
 * 查看下一个Token而不消费它。
 */
class org.flashNight.gesh.pratt.PrattLexer {
    /** 源代码字符串。 */
    private var _src:String;
    /** 当前在源代码字符串中的扫描位置索引。 */
    private var _idx:Number = 0;
    /** 源代码字符串的总长度，用于边界检查。 */
    private var _len:Number;
    /** 当前预读的词法单元（Token）。`peek()` 返回此Token，`next()` 消费此Token并预读下一个。 */
    private var _curr:PrattToken;
    /** 当前扫描到的行号，从1开始。 */
    private var _line:Number = 1;
    /** 当前扫描到的列号，从1开始。 */
    private var _column:Number = 1;
    /** 关键字查找表，用于将标识符快速识别为关键字。 */
    private var _keywords:Object;

    /**
     * 构造一个新的词法分析器实例。
     * @param src 要进行词法分析的源代码字符串。
     */
    function PrattLexer(src:String) {
        _src = src;
        _len = src.length;
        _initKeywords();
        _advance(); // "预热"：立即扫描第一个Token，为首次调用 peek() 或 next() 做准备。
    }

    /**
     * 初始化关键字查找表。
     * 将关键字文本映射到其对应的Token类型。
     */
    private function _initKeywords():Void {
        _keywords = {};

        // 使用字符串拼接 `"" + true` 是为了确保将布尔值 `true` 转换为字符串 "true" 作为键。
        _keywords["" + true] = PrattToken.T_BOOLEAN;
        _keywords["" + false] = PrattToken.T_BOOLEAN;
        _keywords["null"] = PrattToken.T_NULL;
        _keywords["undefined"] = PrattToken.T_UNDEFINED;
        _keywords["if"] = PrattToken.T_IF;
        _keywords["else"] = PrattToken.T_ELSE;
        _keywords["and"] = PrattToken.T_AND;
        _keywords["or"] = PrattToken.T_OR;
        _keywords["not"] = PrattToken.T_NOT;
        _keywords["typeof"] = PrattToken.T_TYPEOF;
    }

    /**
     * 查看（预读）下一个Token，但不消费它。
     * 多次调用 `peek()` 会返回同一个Token实例。
     * @return 当前待处理的 `PrattToken`。
     */
    public function peek():PrattToken {
        return _curr;
    }
    
    /**
     * 消费并返回当前Token，然后将词法分析器前进到下一个Token。
     * @return 被消费的 `PrattToken`。
     */
    public function next():PrattToken {
        var t:PrattToken = _curr;
        _advance();
        return t;
    }

    /**
     * 核心方法：使词法分析器前进到下一个Token。
     * 它会跳过空白和注释，然后根据当前字符决定调用哪个专门的扫描函数。
     */
    private function _advance():Void {
        _skipWhitespaceAndComments();
        
        // 检查是否到达源代码末尾
        if (_idx >= _len) {
            _curr = new PrattToken(PrattToken.T_EOF, "<eof>", _line, _column);
            return;
        }

        var ch:String = _src.charAt(_idx);
        var startLine:Number = _line;
        var startColumn:Number = _column;

        // --- Token识别逻辑调度 ---

        // 数字 (整数，或以小数点开头的浮点数如 .5)
        if (_isDigit(ch) || (ch == "." && _idx + 1 < _len && _isDigit(_src.charAt(_idx + 1)))) {
            _curr = _scanNumber(startLine, startColumn);
            return;
        }

        // 标识符或关键字 (以字母, _, 或 $ 开头)
        if (_isAlpha(ch) || ch == "_" || ch == "$") {
            _curr = _scanIdentifier(startLine, startColumn);
            return;
        }

        // 字符串 (以 " 或 ' 开头)
        if (ch == "\"" || ch == "'") {
            _curr = _scanString(ch, startLine, startColumn);
            return;
        }

        // 多字符运算符 (贪心匹配，例如 "==" 优先于 "=")
        var multiChar:String = _scanMultiCharOperator();
        if (multiChar != null) {
            _curr = new PrattToken(PrattToken.T_OPERATOR, multiChar, startLine, startColumn);
            return;
        }

        // 单字符分隔符
        switch (ch) {
            case "(": _advanceChar(); _curr = new PrattToken(PrattToken.T_LPAREN, "(", startLine, startColumn); return;
            case ")": _advanceChar(); _curr = new PrattToken(PrattToken.T_RPAREN, ")", startLine, startColumn); return;
            case "[": _advanceChar(); _curr = new PrattToken(PrattToken.T_LBRACKET, "[", startLine, startColumn); return;
            case "]": _advanceChar(); _curr = new PrattToken(PrattToken.T_RBRACKET, "]", startLine, startColumn); return;
            case "{": _advanceChar(); _curr = new PrattToken(PrattToken.T_LBRACE, "{", startLine, startColumn); return;
            case "}": _advanceChar(); _curr = new PrattToken(PrattToken.T_RBRACE, "}", startLine, startColumn); return;
            case ",": _advanceChar(); _curr = new PrattToken(PrattToken.T_COMMA, ",", startLine, startColumn); return;
            case ";": _advanceChar(); _curr = new PrattToken(PrattToken.T_SEMICOLON, ";", startLine, startColumn); return;
            case ".": _advanceChar(); _curr = new PrattToken(PrattToken.T_DOT, ".", startLine, startColumn); return;
            case "?": _advanceChar(); _curr = new PrattToken(PrattToken.T_QUESTION, "?", startLine, startColumn); return;
            case ":": _advanceChar(); _curr = new PrattToken(PrattToken.T_COLON, ":", startLine, startColumn); return;
        }

        // 如果以上都不匹配，则视为一个单字符运算符（兜底策略）。
        _advanceChar();
        _curr = new PrattToken(PrattToken.T_OPERATOR, ch, startLine, startColumn);
    }

    /**
     * 扫描一个数字字面量。
     * @param startLine 数字开始的行号。
     * @param startColumn 数字开始的列号。
     * @return 一个类型为 `T_NUMBER` 的 `PrattToken`。
     */
    private function _scanNumber(startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        var hasDot:Boolean = false;

        // 扫描整数部分
        while (_idx < _len && _isDigit(_src.charAt(_idx))) {
            _advanceChar();
        }

        // 扫描小数部分（如果存在）
        if (_idx < _len && _src.charAt(_idx) == ".") {
            hasDot = true;
            _advanceChar();
            while (_idx < _len && _isDigit(_src.charAt(_idx))) {
                _advanceChar();
            }
        }

        var numText:String = _src.substr(start, _idx - start);
        // 直接在词法分析阶段计算好值，并作为 `tokenValue` 传入构造函数，避免重复解析。
        var value:Number = hasDot ? parseFloat(numText) : parseInt(numText);
        
        return new PrattToken(PrattToken.T_NUMBER, numText, startLine, startColumn, value);
    }

    /**
     * 扫描一个标识符，并检查它是否为关键字。
     * @param startLine 标识符开始的行号。
     * @param startColumn 标识符开始的列号。
     * @return 一个 `PrattToken`，其类型为 `T_IDENTIFIER` 或一个特定的关键字类型。
     */
    private function _scanIdentifier(startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        // 标识符可以包含字母、数字、下划线和美元符号。
        while (_idx < _len && _isAlnum(_src.charAt(_idx))) {
            _advanceChar();
        }

        var text:String = _src.substr(start, _idx - start);
        // 在关键字表中查找，如果找到则使用关键字类型，否则默认为标识符。
        var tokenType:String = _keywords[text] || PrattToken.T_IDENTIFIER;
        
        // 对于关键字，Token的 value 会被自动转换（例如 "true" -> true）。
        return new PrattToken(tokenType, text, startLine, startColumn);
    }

    /**
     * 扫描一个字符串字面量，处理转义序列。
     * @param quote 字符串使用的引号类型（`"` 或 `'`）。
     * @param startLine 字符串开始的行号。
     * @param startColumn 字符串开始的列号。
     * @return 一个类型为 `T_STRING` 的 `PrattToken`。
     * @throws Error 如果字符串未正确终止。
     */
    private function _scanString(quote:String, startLine:Number, startColumn:Number):PrattToken {
        var start:Number = _idx;
        _advanceChar(); // 跳过开始的引号
        
        var value:String = ""; // 用于存放处理转义后的字符串值
        
        while (_idx < _len && _src.charAt(_idx) != quote) {
            var ch:String = _src.charAt(_idx);
            
            if (ch == "\\") { // 处理转义字符
                _advanceChar(); // 跳过反斜杠
                if (_idx < _len) {
                    var escaped:String = _src.charAt(_idx);
                    switch (escaped) {
                        case "n": value += "\n"; break;
                        case "t": value += "\t"; break;
                        case "r": value += "\r"; break;
                        case "\\": value += "\\"; break;
                        case "\"": value += "\""; break;
                        case "'": value += "'"; break;
                        default: value += escaped; break; // 对于未知转义，直接保留后面的字符
                    }
                    _advanceChar();
                }
            } else {
                value += ch;
                _advanceChar();
            }
        }

        // 检查字符串是否正确关闭
        if (_idx < _len && _src.charAt(_idx) == quote) {
            _advanceChar(); // 跳过结束的引号
        } else {
            // 如果循环结束时仍未找到结束引号，则抛出错误。
            throw new Error("未终止的字符串 at line " + startLine + ", column " + startColumn);
        }

        var fullText:String = _src.substr(start, _idx - start);
        // 传入原始文本 `fullText` 和处理后的值 `value`。
        return new PrattToken(PrattToken.T_STRING, fullText, startLine, startColumn, value);
    }

    /**
     * 尝试扫描一个多字符运算符。
     * @return 如果成功匹配，则返回运算符字符串；否则返回 `null`。
     */
    private function _scanMultiCharOperator():String {
        // 预读最多两个字符，以判断是单、双还是三字符运算符。
        var ch1:String = _src.charAt(_idx);
        var ch2:String = _idx + 1 < _len ? _src.charAt(_idx + 1) : "";
        var ch3:String = _idx + 2 < _len ? _src.charAt(_idx + 2) : "";

        // 优先匹配三字符运算符
        var triple:String = ch1 + ch2 + ch3;
        if (triple == "===" || triple == "!==") {
            _advanceChar(); _advanceChar(); _advanceChar();
            return triple;
        }

        // 其次匹配两字符运算符
        var double:String = ch1 + ch2;
        switch (double) {
            case "==": case "!=": case "<=": case ">=": case "&&": case "||":
            case "++": case "--": case "+=": case "-=": case "*=": case "/=":
            case "%=": case "**": case "??":
                _advanceChar(); _advanceChar();
                return double;
        }
        
        // 没有匹配到多字符运算符
        return null;
    }

    /**
     * 跳过所有连续的空白字符和注释。
     */
    private function _skipWhitespaceAndComments():Void {
        while (_idx < _len) {
            var ch:String = _src.charAt(_idx);
            
            // 跳过空白字符
            if (_isWhitespace(ch)) {
                _advanceChar();
                continue;
            }
            
            // 跳过单行注释 (`//...`)
            if (ch == "/" && _idx + 1 < _len && _src.charAt(_idx + 1) == "/") {
                _advanceChar(); _advanceChar();
                while (_idx < _len && _src.charAt(_idx) != "\n") {
                    _advanceChar();
                }
                continue;
            }
            
            // 跳过多行注释 (`/*...*/`)
            if (ch == "/" && _idx + 1 < _len && _src.charAt(_idx + 1) == "*") {
                _advanceChar(); _advanceChar();
                
                // 健壮地寻找 `*/`，即使注释未闭合也能安全地到达文件末尾。
                while (_idx < _len) { 
                    if (_idx + 1 < _len && _src.charAt(_idx) == "*" && _src.charAt(_idx + 1) == "/") {
                        _advanceChar(); _advanceChar();
                        break; // 找到注释结尾，跳出循环。
                    }
                    _advanceChar(); // 在注释内部前进。
                }
                continue;
            }
            
            // 如果不是空白或注释，则停止跳过。
            break;
        }
    }

    /**
     * 将扫描索引前进一个字符，并更新行号和列号。
     */
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

    /** 检查字符是否为空白字符。 */
    private function _isWhitespace(c:String):Boolean {
        return c == " " || c == "\t" || c == "\n" || c == "\r";
    }

    /** 检查字符是否为数字（0-9）。 */
    private function _isDigit(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        return code >= 48 && code <= 57;
    }

    /** 检查字符是否为字母（a-z, A-Z）。 */
    private function _isAlpha(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    }

    /** 检查字符是否为字母、数字、下划线或美元符号。 */
    private function _isAlnum(c:String):Boolean {
        return _isAlpha(c) || _isDigit(c) || c == "_" || c == "$";
    }
}