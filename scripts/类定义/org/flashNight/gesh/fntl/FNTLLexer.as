import org.flashNight.gesh.regexp.RegExp;
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.fntl.*;

/**
 * FNTLLexer 类用于解析 FNTL（FlashNight Text Language）文件内容。
 * 
 * 功能增强包括：
 * - 对键和值的全面 UTF-8 支持（包括中文字符）
 * - 对转义序列的稳健处理，包括 \uXXXX 和 \UXXXXXXXX
 * - 遵循 ISO8601 的日期时间标记
 * - 增强的错误处理与精确定位
 * - 通过缓存和高效的解析策略进行性能优化
 */
class org.flashNight.gesh.fntl.FNTLLexer {
    private var text:String;
    private var position:Number;
    private var currentChar:String;
    private var loopCounter:Number;
    private var maxLoops:Number = 10000;
    private var inValue:Boolean;
    private var currentLine:Number;
    private var currentColumn:Number;

    private var tableHeaderCache:Object = {};
    private var tableArrayHeaderCache:Object = {};

    // 正则表达式定义
    public static var alphaRegex:RegExp = new RegExp("^[A-Za-z\\u00C0-\\u017F\\u4E00-\\u9FFF]$", "");
    public static var alphaNumericRegex:RegExp = new RegExp("^[A-Za-z0-9_\\u00C0-\\u017F\\u4E00-\\u9FFF]$", "");
    public static var dateTimeRegExp:RegExp = new RegExp("^\\d{4}-\\d{2}-\\d{2}[Tt ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?([Zz]|[+-]\\d{2}:\\d{2})?$");

    public function FNTLLexer(text:String) {
        this.text = text;
        this.position = 0;
        this.loopCounter = 0;
        this.inValue = false;
        this.currentLine = 1;
        this.currentColumn = 1;
        this.nextChar();  
    }
    private function nextChar():Void {
        if (this.position < this.text.length) {
            this.currentChar = this.text.charAt(this.position);
            this.position++;
            
            if (this.currentChar == "\n") {
                this.currentLine++;
                this.currentColumn = 1;
            } else {
                this.currentColumn++;
            }
        } else {
            this.currentChar = null; 
        }
    }

    private function isAlpha(c:String):Boolean {
        return FNTLLexer.alphaRegex.test(c);
    }

    private function isAlphaNumeric(c:String):Boolean {
        return FNTLLexer.alphaNumericRegex.test(c);
    }

    private function parseDateTime(dateTimeStr:String):String {
        if (!FNTLLexer.dateTimeRegExp.test(dateTimeStr)) {
            this.error("无效的日期时间格式: " + dateTimeStr, this.currentLine, this.currentColumn);
            return null;
        }

        return dateTimeStr;
    }
    
    /**
     * 跳过空白字符及注释
     */
    private function skipWhitespaceAndComments():Void {
        while (this.currentChar != null && 
               (this.isWhitespace(this.currentChar) || this.currentChar == "#")) {
            if (this.currentChar == "#") {
                // 跳过注释，直到行末
                while (this.currentChar != "\n" && this.currentChar != "\r" && this.currentChar != null) {
                    this.nextChar();
                }
            }
            this.nextChar(); 
        }
    }
    
    /**
     * 判断字符是否为空白字符
     * @param c 要判断的字符
     * @return 是否为空白字符
     */
    private function isWhitespace(c:String):Boolean {
        return c == " " || c == "\t" || c == "\n" || c == "\r";
    }
    
    /**
     * 获取下一个标记 (Token)
     * @return 下一个标记对象或 null
     */
    public function getNextToken():Object {
        this.skipWhitespaceAndComments();

        if (this.currentChar == null) {
            return null; 
        }

        this.loopCounter = 0; 

        while (this.currentChar != null) {
            this.loopCounter++;
            if (this.loopCounter > this.maxLoops) {
                this.error("警告: 循环次数过多，可能存在死循环", this.currentLine, this.currentColumn);
                break;
            }

            this.skipWhitespaceAndComments();

            if (this.currentChar == null) {
                return null; 
            }

            var token:Object = {};
            var tokenLine:Number = this.currentLine;
            var tokenColumn:Number = this.currentColumn;

            // 识别键名（包括Unicode字符、下划线和中划线）
            if (this.isAlpha(this.currentChar) || this.currentChar == "_") {
                var identifier:String = this.readIdentifier();
                var lowerIdentifier:String = identifier.toLowerCase();

                // 检查是否为特殊值
                if (lowerIdentifier == "true" || lowerIdentifier == "false") {
                    return { type: "BOOLEAN", value: (lowerIdentifier == "true"), line: tokenLine, column: tokenColumn };
                } else if (lowerIdentifier == "nan" || lowerIdentifier == "inf" || lowerIdentifier == "-inf") {
                    return { type: "FLOAT", value: lowerIdentifier, line: tokenLine, column: tokenColumn };
                } else if (lowerIdentifier == "null") {
                    return { type: "NULL", value: null, line: tokenLine, column: tokenColumn };
                } else {
                    // 是一个常规键
                    return { type: "KEY", value: identifier, line: tokenLine, column: tokenColumn };
                }
            } 
            // 新增对特殊字符的处理
            else if (this.currentChar == "=") {
                token = { type: "EQUALS", value: "=", line: tokenLine, column: tokenColumn };
                this.nextChar();
                this.inValue = true;
                return token;
            } 
            else if (this.currentChar == ",") {
                token = { type: "COMMA", value: ",", line: tokenLine, column: tokenColumn };
                this.nextChar();
                return token;
            } 
            else if (this.currentChar == "]") {
                token = { type: "RBRACKET", value: "]", line: tokenLine, column: tokenColumn };
                this.nextChar();
                return token;
            } 
            else if (this.currentChar == "[") {
                token = { type: "LBRACKET", value: "[", line: tokenLine, column: tokenColumn };
                this.nextChar();
                return token;
            } 
            else if (this.currentChar == "{") {
                token = { type: "LBRACE", value: "{", line: tokenLine, column: tokenColumn };
                this.nextChar();
                return token;
            } 
            else if (this.currentChar == "}") {
                token = { type: "RBRACE", value: "}", line: tokenLine, column: tokenColumn };
                this.nextChar();
                return token;
            } 
            else if (this.currentChar == ".") {
                token = { type: "DOT", value: ".", line: tokenLine, column: tokenColumn };
                this.nextChar();
                return token;
            } 
            else if (this.currentChar == ":") {
                token = { type: "COLON", value: ":", line: tokenLine, column: tokenColumn };
                this.nextChar();
                return token;
            } 
            // 识别字符串
            else if (this.currentChar == "\"" || this.currentChar == "'") {
                token = this.readString();
                this.inValue = false;
                return token;
            } 
            // 识别数字或日期时间
            else if (this.isDigit(this.currentChar) || (this.currentChar == "-" && this.inValue)) {
                token = this.readNumberOrDate();
                this.inValue = false;
                return token;
            } 
            else {
                this.error("未知的标记类型: '" + this.currentChar + "'", this.currentLine, this.currentColumn);
                this.nextChar();
            }
        }

        return null;
    }
    
    /**
     * 读取标识符，包括可能的负号
     * 支持Unicode字符、下划线和中划线
     * @return 读取到的标识符字符串
     */
    private function readIdentifier():String {
        var identifier:String = "";
        // 首字符应为字母、下划线或Unicode字符
        if (this.isAlpha(this.currentChar) || this.currentChar == "_") {
            while (this.isAlphaNumeric(this.currentChar) || this.currentChar == "_" || this.currentChar == "-") {
                identifier += this.currentChar;
                this.nextChar();
            }
        } else {
            this.error("无效的标识符起始字符: " + this.currentChar, this.currentLine, this.currentColumn);
            this.nextChar();
        }
        return identifier;
    }
    
    /**
     * 读取字符串，处理多行字符串和转义字符
     * @return 字符串类型的标记对象
     */
    private function readString():Object {
        var str:String = "";
        var quoteType:String = this.currentChar;
        var isMultiline:Boolean = false;
        var tokenLine:Number = this.currentLine;
        var tokenColumn:Number = this.currentColumn;
        this.nextChar(); 

        // 检查是否为多行字符串（三个引号）
        if (this.currentChar == quoteType && this.peek() == quoteType) {
            isMultiline = true;
            this.nextChar(); 
            this.nextChar(); 
        }

        while (true) {
            // 检查字符串结束条件
            if (isMultiline) {
                if (this.currentChar == quoteType && this.peek() == quoteType && this.peekAhead(2) == quoteType) {
                    break;
                }
            } else {
                if (this.currentChar == quoteType) {
                    break;
                }
            }

            if (this.currentChar == null) {
                this.error("未关闭的字符串", tokenLine, tokenColumn);
                break;
            }

            if (this.currentChar == "\\") {
                // 处理转义字符
                this.nextChar(); // 跳过反斜杠
                if (this.currentChar == null) {
                    this.error("Incomplete escape sequence at end of string", tokenLine, tokenColumn);
                    break;
                }
                var escapeSeq:String = "\\" + this.currentChar;
                str += this.handleEscapeSequences(escapeSeq);
                this.nextChar(); // 跳过转义字符
            } else {
                str += this.currentChar;
                this.nextChar();
            }
        }

        // 跳过结束引号
        this.nextChar(); 
        if (isMultiline) {
            this.nextChar(); 
            this.nextChar(); 
        }

        return { type: "STRING", value: str, line: tokenLine, column: tokenColumn };
    }
    
    /**
     * 读取数字或日期时间
     * 支持负号、分数点、下划线（忽略）、以及日期时间标识符
     * @return 数字或日期时间类型的标记对象
     */
    private function readNumberOrDate():Object {
        var number:String = "";
        var isFloat:Boolean = false;
        var tokenLine:Number = this.currentLine;
        var tokenColumn:Number = this.currentColumn;

        // 处理负号
        if (this.currentChar == "-") {
            number += "-";
            this.nextChar();
        }

        // 检查是否为特殊浮点数标识符
        if (this.currentChar == "i" || this.currentChar == "n") {
            var identifier:String = this.readIdentifier();
            var lowerIdentifier:String = (number + identifier).toLowerCase();

            if (lowerIdentifier == "nan" || lowerIdentifier == "inf" || lowerIdentifier == "-inf") {
                return { type: "FLOAT", value: lowerIdentifier, line: tokenLine, column: tokenColumn };
            } else {
                this.error("未知的特殊浮点数: " + lowerIdentifier, tokenLine, tokenColumn);
                return { type: "INVALID", value: lowerIdentifier, line: tokenLine, column: tokenColumn };
            }
        }

        // 读取整数部分，忽略下划线
        while (this.isDigit(this.currentChar) || this.currentChar == "_") {
            if (this.currentChar != "_") { // 忽略下划线
                number += this.currentChar;
            }
            this.nextChar();
        }

        // 检查小数点
        if (this.currentChar == ".") {
            isFloat = true;
            number += ".";
            this.nextChar();
            while (this.isDigit(this.currentChar)) {
                number += this.currentChar;
                this.nextChar();
            }
        }

        // 检查日期时间指示符
        if (this.currentChar == "T" || this.currentChar == "t" || this.currentChar == "Z" || 
            this.currentChar == "z" || this.currentChar == ":" || this.currentChar == "-" || 
            this.currentChar == "+") {
            return this.readDateTime(number, tokenLine, tokenColumn);
        }

        // 移除下划线
        number = number.split("_").join("");

        return { type: isFloat ? "FLOAT" : "INTEGER", value: number, line: tokenLine, column: tokenColumn };
    }
    
    /**
     * 读取日期时间
     * 支持：
     * - ISO8601格式
     * - 分数秒
     * - 时区偏移 (+/-HH:MM)
     * @param initial 初始数字字符串
     * @return DATETIME 类型的标记对象
     */
    private function readDateTime(initial:String, tokenLine:Number, tokenColumn:Number):Object {
        var dateTime:String = initial;
        var possibleChars:String = "TtZz+-:";

        while (this.currentChar != null && 
               (this.isAlphaNumeric(this.currentChar) || possibleChars.indexOf(this.currentChar) != -1)) {
            dateTime += this.currentChar;
            this.nextChar();
        }

        return { type: "DATETIME", value: dateTime, line: tokenLine, column: tokenColumn };
    }
    
    /**
     * 读取数组
     * 支持嵌套数组和内联表格
     * @return 数组类型的标记对象
     */
    private function readArray():Object {
        var array:Array = [];
        var tokenLine:Number = this.currentLine;
        var tokenColumn:Number = this.currentColumn;
        this.nextChar(); // 跳过 '['

        this.skipWhitespaceAndComments();

        while (this.currentChar != "]" && this.currentChar != null) {
            this.skipWhitespaceAndComments();

            if (this.currentChar == ",") {
                this.nextChar(); // 跳过逗号
                continue;
            }

            var element:Object;

            // 处理字符串
            if (this.currentChar == "\"" || this.currentChar == "'") {
                element = this.readString();
            }
            // 处理数组（递归调用）
            else if (this.currentChar == "[") {
                element = this.readArray();
            }
            // 处理数字或日期时间
            else if (this.isDigit(this.currentChar) || this.currentChar == "-") {
                element = this.readNumberOrDate();
            }
            // 处理布尔值和特殊浮点数
            else if (this.isAlpha(this.currentChar) || this.currentChar == "_") {
                var identifier:String = this.readIdentifier();
                var lowerIdentifier:String = identifier.toLowerCase();

                if (lowerIdentifier == "true" || lowerIdentifier == "false") {
                    element = { type: "BOOLEAN", value: (lowerIdentifier == "true"), line: this.currentLine, column: this.currentColumn };
                } else if (lowerIdentifier == "nan" || lowerIdentifier == "inf" || lowerIdentifier == "-inf") {
                    element = { type: "FLOAT", value: lowerIdentifier, line: this.currentLine, column: this.currentColumn };
                } else if (lowerIdentifier == "null") {
                    element = { type: "NULL", value: null, line: this.currentLine, column: this.currentColumn };
                } else {
                    this.error("无效的数组元素: " + identifier, this.currentLine, this.currentColumn);
                    element = { type: "INVALID", value: identifier, line: this.currentLine, column: this.currentColumn };
                }
            }
            // 处理内联表格
            else if (this.currentChar == "{") {
                element = this.readInlineTable();
            }
            // 处理未知字符
            else {
                this.error("无效的数组元素: " + this.currentChar, this.currentLine, this.currentColumn);
                this.nextChar();
                continue;
            }

            if (element !== undefined) { // 仅在成功解析值时添加到数组
                array.push(element);
            }

            this.skipWhitespaceAndComments();

            if (this.currentChar == ",") {
                this.nextChar(); // 跳过逗号
            }
        }

        if (this.currentChar == "]") {
            this.nextChar(); // 跳过 ']'
        } else {
            this.error("未正确关闭的数组", tokenLine, tokenColumn);
        }

        return { type: "ARRAY", value: array, line: tokenLine, column: tokenColumn };
    }
    
    /**
     * 读取内联表格
     * 支持嵌套内联表格的未来扩展
     * @return 内联表格类型的标记对象
     */
    private function readInlineTable():Object {
        var inlineTable:String = "";
        var tokenLine:Number = this.currentLine;
        var tokenColumn:Number = this.currentColumn;
        this.nextChar(); // 跳过 '{'

        while (this.currentChar != "}" && this.currentChar != null) {
            if (this.currentChar == "\\") {
                // 处理转义字符
                this.nextChar(); // 跳过反斜杠
                if (this.currentChar == null) {
                    this.error("Incomplete escape sequence in inline table", tokenLine, tokenColumn);
                    break;
                }
                var escapeSeq:String = "\\" + this.currentChar;
                inlineTable += this.handleEscapeSequences(escapeSeq);
                this.nextChar(); // 跳过转义字符
            } else {
                inlineTable += this.currentChar;
                this.nextChar();
            }
        }

        if (this.currentChar == "}") {
            this.nextChar(); // 跳过 '}'
        } else {
            this.error("未正确关闭的内联表格", tokenLine, tokenColumn);
        }

        return { type: "INLINE_TABLE", value: inlineTable, line: tokenLine, column: tokenColumn };
    }
    
    /**
     * 读取表格头或表格数组
     * @return 表格头或表格数组类型的标记对象
     */
    private function readTableHeader():Object {
        var tableName:String = "";
        var tokenLine:Number = this.currentLine;
        var tokenColumn:Number = this.currentColumn;
        this.nextChar(); // 跳过第一个 '['

        // 检查是否为表格数组
        if (this.currentChar == "[") {
            // 是表格数组
            this.nextChar(); // 跳过第二个 '['

            // 读取表名，直到遇到 ']]'
            while (this.currentChar != null && !(this.currentChar == ']' && this.peek() == ']')) {
                tableName += this.currentChar;
                this.nextChar();
            }

            if (this.currentChar == ']' && this.peek() == ']') {
                this.nextChar(); // 跳过第一个 ']'
                this.nextChar(); // 跳过第二个 ']'
                tableName = StringUtils.trim(tableName);
                trace("FNTLLexer.readTableHeader: 识别为 TABLE_ARRAY - " + tableName);
                return { type: "TABLE_ARRAY", value: tableName, line: tokenLine, column: tokenColumn };
            } else {
                this.error("未正确关闭的表格数组", tokenLine, tokenColumn);
                return null;
            }
        } else {
            // 普通表格
            while (this.currentChar != ']' && this.currentChar != null) {
                tableName += this.currentChar;
                this.nextChar();
            }

            if (this.currentChar == ']') {
                this.nextChar(); // 跳过 ']'
                tableName = StringUtils.trim(tableName);
                trace("FNTLLexer.readTableHeader: 识别为 TABLE_HEADER - " + tableName);
                return { type: "TABLE_HEADER", value: tableName, line: tokenLine, column: tokenColumn };
            } else {
                this.error("未正确关闭的表格头", tokenLine, tokenColumn);
                return null;
            }
        }
    }
    
    /**
     * 读取并解析一个标记的值
     * @param token 要解析的标记
     * @return 解析后的值
     */
    private function parseValue(token:Object):Object {
        switch (token.type) {
            case "STRING":
                return token.value;
            case "INTEGER":
                return Number(token.value);
            case "FLOAT":
                return this.parseSpecialFloat(token.value);
            case "BOOLEAN":
                return token.value;
            case "DATETIME":
                return this.parseDateTime(token.value);
            case "ARRAY":
                return this.parseArray(token.value);
            case "INLINE_TABLE":
                return this.parseInlineTable(token.value);
            case "NULL":
                return null;
            default:
                this.error("未知的值类型: " + token.type, token.line, token.column);
                return undefined;
        }
    }

    /**
     * 解析特殊浮点数值（NaN, Infinity, -Infinity）
     * @param value 字符串表示
     * @return 对应的 AS2 数字
     */
    private function parseSpecialFloat(value:String):Object {
        switch (value.toLowerCase()) {
            case "nan":
                return Number.NaN;
            case "inf":
                return Number.POSITIVE_INFINITY;
            case "-inf":
                return Number.NEGATIVE_INFINITY;
            default:
                return Number(value);
        }
    }

    /**
     * 解析数组标记为 AS2 数组
     * @param arrayData 数组标记的值
     * @return 解析后的数组或 null（如果有错误）
     */
    private function parseArray(arrayData:Array):Array {
        var array:Array = new Array();

        for (var i:Number = 0; i < arrayData.length; i++) {
            var elementToken:Object = arrayData[i];
            var value:Object = this.parseValue(elementToken);

            if (value !== undefined) { // 仅在成功解析值时添加到数组
                array.push(value);
            } else {
                this.error("数组元素解析失败", elementToken.line, elementToken.column);
                return null;
            }
        }

        return array;
    }

    /**
     * 解析内联表格字符串为对象
     * @param tableStr 内联表格字符串
     * @return 解析后的内联表格对象
     */
    private function parseInlineTable(tableStr:String):Object {
        var table:Object = new Object();
        var lexer:FNTLLexer = new FNTLLexer(tableStr);
        var tokens:Array = new Array();
        var tok:Object;
        while ((tok = lexer.getNextToken()) != null) {
            tokens.push(tok);
        }
        var parser:FNTLParser = new FNTLParser(tokens, tableStr);
        var parsedTable:Object = parser.parse();
        if (parser.hasError()) {
            this.error("内联表格解析失败: " + tableStr, this.currentLine, this.currentColumn);
            return undefined;
        }
        return parsedTable;
    }
    
    /**
     * 检查字符是否为数字
     * @param c 要检查的字符
     * @return 是否为数字
     */
    private function isDigit(c:String):Boolean {
        return c >= "0" && c <= "9";
    }
    
    /**
     * 查看下一个字符而不移动指针
     * @return 下一个字符或空字符串
     */
    private function peek():String {
        if (this.position < this.text.length) {
            return this.text.charAt(this.position);
        }
        return "";
    }
    
    /**
     * 查看接下来的第 n 个字符而不移动指针
     * @param n 要查看的字符位置偏移
     * @return 第 n 个字符或空字符串
     */
    private function peekAhead(n:Number):String {
        if (this.position + n < this.text.length) {
            return this.text.charAt(this.position + n);
        }
        return "";
    }
    
    /**
     * 抛出错误，包含行号和列号
     * @param message 错误消息
     * @param tokenLine 错误行号
     * @param tokenColumn 错误列号
     */
    private function error(message:String, tokenLine:Number, tokenColumn:Number):Void {
        var lineInfo:String = "行: " + (tokenLine != undefined ? tokenLine : this.currentLine) + ", 列: " + (tokenColumn != undefined ? tokenColumn : this.currentColumn);
        trace("错误: " + message + " 在 " + lineInfo);
    }
    
    /**
     * 处理转义序列，包括扩展的Unicode转义
     * @param str 转义后的字符串部分
     * @return 处理后的字符串
     */
    private function handleEscapeSequences(str:String):String {
        var result:String = "";
        var i:Number = 0;
        while (i < str.length) {
            var c:String = str.charAt(i);
            if (c == "\\") {
                i++;
                if (i >= str.length) {
                    this.error("Incomplete escape sequence", this.currentLine, this.currentColumn);
                    break;
                }
                var nextChar:String = str.charAt(i);
                switch (nextChar) {
                    case "b":
                        result += "\b";
                        break;
                    case "t":
                        result += "\t";
                        break;
                    case "n":
                        result += "\n";
                        break;
                    case "f":
                        result += "\f";
                        break;
                    case "r":
                        result += "\r";
                        break;
                    case "\"":
                        result += "\"";
                        break;
                    case "\\":
                        result += "\\";
                        break;
                    case "u":
                        // 4-digit Unicode
                        var unicodeSeq:String = str.substr(i + 1, 4);
                        if (this.isValidUnicodeSequence(unicodeSeq)) {
                            result += String.fromCharCode(parseInt(unicodeSeq, 16));
                            i += 4; // Move past the 4-digit sequence
                        } else {
                            this.error("Invalid Unicode escape sequence: \\u" + unicodeSeq, this.currentLine, this.currentColumn);
                            result += "\\u" + unicodeSeq;
                            i += 4; // Still move past the invalid sequence
                        }
                        break;

                    case "U":
                        // 8-digit Unicode
                        var unicodeSeq8:String = str.substr(i + 1, 8);
                        if (this.isValidUnicodeSequenceExtended(unicodeSeq8)) {  // Validate 8-digit Unicode
                            var codePoint:Number = parseInt(unicodeSeq8, 16);
                            result += this.convertCodePointToUTF16(codePoint);  // Use existing function to convert
                            i += 8;  // Move past the 8-digit sequence
                        } else {
                            this.error("Invalid Unicode escape sequence: \\U" + unicodeSeq8, this.currentLine, this.currentColumn);
                            result += "\\U" + unicodeSeq8;
                            i += 8;  // Still move past the invalid sequence
                        }
                        break;

                    default:
                        result += "\\" + nextChar;  // Handle unknown escape sequence
                        break;
                }
            } else {
                result += c;
            }
            i++;
        }
        return result;
    }
    
    /**
     * 检查字符是否为16进制字符
     * @param char 要检查的字符
     * @return 是否为16进制字符
     */
    private function isHexadecimal(char:String):Boolean {
        var hexChars:String = "0123456789ABCDEFabcdef";
        return hexChars.indexOf(char) != -1;
    }
    
    /**
     * 检查4位Unicode转义序列是否有效
     * @param seq 转义序列
     * @return 是否有效
     */
    private function isValidUnicodeSequence(seq:String):Boolean {
        if (seq.length != 4) {
            return false;
        }
        for (var i:Number = 0; i < seq.length; i++) {
            if (!this.isHexadecimal(seq.charAt(i))) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 检查8位Unicode转义序列是否有效
     * @param seq 转义序列
     * @return 是否有效
     */
    private function isValidUnicodeSequenceExtended(seq:String):Boolean {
        if (seq.length != 8) {
            return false;
        }
        for (var i:Number = 0; i < seq.length; i++) {
            if (!this.isHexadecimal(seq.charAt(i))) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 将Unicode码点转换为UTF-16编码字符串
     * @param codePoint Unicode码点
     * @return UTF-16编码的字符串
     */
    private function convertCodePointToUTF16(codePoint:Number):String {
        if (codePoint <= 0xFFFF) {
            return String.fromCharCode(codePoint);
        } else {
            codePoint -= 0x10000;
            var highSurrogate:Number = 0xD800 + (codePoint >> 10);
            var lowSurrogate:Number = 0xDC00 + (codePoint & 0x3FF);
            return String.fromCharCode(highSurrogate) + String.fromCharCode(lowSurrogate);
        }
    }

    /**
     * 构建并缓存表格头
     * @param path 当前表格路径数组
     * @return 表格头字符串
     */
    private function buildTableHeader(path:Array):String {
        var key:String = path.join(".");
        if (!this.tableHeaderCache.hasOwnProperty(key)) {
            this.tableHeaderCache[key] = "[" + key + "]";
        }
        return this.tableHeaderCache[key];
    }

    /**
     * 构建并缓存表格数组头
     * @param path 当前表格路径数组
     * @return 表格数组头字符串
     */
    private function buildTableArrayHeader(path:Array):String {
        var key:String = path.join(".");
        if (!this.tableArrayHeaderCache.hasOwnProperty(key)) {
            this.tableArrayHeaderCache[key] = "[[" + key + "]]";
        }
        return this.tableArrayHeaderCache[key];
    }
}
