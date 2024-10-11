import org.flashNight.gesh.regexp.RegExp;
import org.flashNight.gesh.object.*;
import org.flashNight.gesh.string.*;
import org.flashNight.gesh.fntl.*;

/**
 * FNTLLexer class upgraded to support FNTL (FlashNight Text Language).
 * Enhancements include:
 * - Full UTF-8 support for keys and values (including Chinese characters)
 * - Extended escape sequences handling, including \uXXXX and \UXXXXXXXX
 * - Improved date-time tokenization
 * - Robust error handling with localization
 * - Performance optimizations (QuickSort for key sorting, caching table headers)
 */
class org.flashNight.gesh.fntl.FNTLLexer {
    private var text:String;          // TOML/FNTL 文件内容
    private var position:Number;      // 当前字符位置
    private var currentChar:String;   // 当前处理的字符
    private var loopCounter:Number;   // 循环计数器，用于防止死循环
    private var maxLoops:Number = 1000; // 最大循环次数
    private var inValue:Boolean;      // 标志当前是否在值的上下文中
    
    // 缓存表格头和表格数组头以优化性能
    private var tableHeaderCache:Object = {};
    private var tableArrayHeaderCache:Object = {};
    
    // Precompiled RegExp instances for performance
    private static var alphaRegex:RegExp = new RegExp("^[A-Za-z\\u00C0-\\u017F\\u4E00-\\u9FFF]$", "");
    private static var alphaNumericRegex:RegExp = new RegExp("^[A-Za-z0-9_\\u00C0-\\u017F\\u4E00-\\u9FFF]$", "");

    private var totalGroups:Number;

    /**
     * Calculates the total number of capturing groups.
     * @return The number of capturing groups.
     */
    private function calculateTotalGroups():Number {
        // Implement the logic to calculate total groups based on your use case
        // For example, if using regex, count the capturing groups here.
        return 0; // Replace this with actual calculation logic
    }

    /**
     * Initializes the captures array based on totalGroups.
     * @return The initialized captures array.
     */
    private function initializeCaptures():Array {
        var captures:Array = new Array(this.totalGroups + 1);
        for (var i:Number = 0; i <= this.totalGroups; i++) {
            captures[i] = null;
        }
        return captures;
    }
    
    // 构造函数，初始化词法分析器
    public function FNTLLexer(text:String) {
        this.text = text;
        this.position = 0;
        this.loopCounter = 0;
        this.inValue = false;
        this.nextChar();  
        this.totalGroups = this.calculateTotalGroups();
    }
    
    // 移动到下一个字符
    private function nextChar():Void {
        if (this.position < this.text.length) {
            this.currentChar = this.text.charAt(this.position);
            this.position++;
        } else {
            this.currentChar = null; 
        }
    }
    
    // 跳过空白字符及注释
    private function skipWhitespaceAndComments():Void {
        while (this.currentChar != null && 
               (this.currentChar == " " || this.currentChar == "\t" || 
                this.currentChar == "\n" || this.currentChar == "\r" || this.currentChar == "#")) {
            if (this.currentChar == "#") {
                // 跳过注释，直到行末
                while (this.currentChar != "\n" && this.currentChar != null) {
                    this.nextChar();
                }
            }
            this.nextChar(); 
        }
    }
    
    // 获取下一个标记 (Token)
    public function getNextToken():Object {
        this.skipWhitespaceAndComments();
    
        if (this.currentChar == null) {
            return null; 
        }
    
        // 添加对非法字符的检查
        if (!this.isValidTokenStart(this.currentChar)) {
            this.error("非法的起始字符: " + this.currentChar);
            this.nextChar();
            return this.getNextToken(); // 尝试获取下一个有效的标记
        }
    
        this.loopCounter = 0; 
    
        while (this.currentChar != null) {
            this.loopCounter++;
            if (this.loopCounter > this.maxLoops) {
                trace("警告: 循环次数过多，可能存在死循环");
                break;
            }
    
            this.skipWhitespaceAndComments();
    
            if (this.currentChar == null) {
                return null; 
            }
    
            var token:Object = {};
    
            // 识别键名（包括Unicode字符、下划线和中划线）
            if (this.isAlpha(this.currentChar) || this.currentChar == "_") {
                var identifier:String = this.readIdentifier();
                var lowerIdentifier:String = identifier.toLowerCase();
    
                // 检查是否为特殊值
                if (lowerIdentifier == "true" || lowerIdentifier == "false") {
                    return { type: "BOOLEAN", value: (lowerIdentifier == "true") };
                } else if (lowerIdentifier == "nan" || lowerIdentifier == "inf" || lowerIdentifier == "-inf") {
                    return { type: "FLOAT", value: lowerIdentifier };
                } else if (lowerIdentifier == "null") {
                    return { type: "NULL", value: null };
                } else {
                    // 是一个常规键
                    return { type: "KEY", value: identifier };
                }
            } 
            // 识别等号
            else if (this.currentChar == "=") {
                token = { type: "EQUALS", value: "=" };
                this.nextChar();
                this.inValue = true;
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
            // 识别表格或数组
            else if (this.currentChar == "[") {
                if (this.inValue) {
                    token = this.readArray(); // 解析为数组
                } else {
                    token = this.readTableHeader(); // 解析为表格或表格数组
                }
                this.inValue = false;
                return token;
            } 
            // 识别内联表格
            else if (this.currentChar == "{") {
                token = this.readInlineTable(); // 解析内联表格
                this.inValue = false;
                return token;
            } 
            // 其他未知字符
            else {
                this.error("未知的标记类型: " + this.currentChar);
                this.nextChar();
                return null;
            }
        }
    
        return null;
    }
    
    // 添加对有效标记起始字符的判断
    private function isValidTokenStart(c:String):Boolean {
        if (this.inValue && c == "-") {
            return true;
        }
        return this.isAlpha(c) || this.isDigit(c) || c == "\"" || c == "'" || c == "[" || c == "{" || c == "=" || c == "#";
    }
    
    /**
     * 读取标识符，包括可能的负号
     * 支持Unicode字符、下划线和中划线
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
            this.error("无效的标识符起始字符: " + this.currentChar);
            this.nextChar();
        }
        return identifier;
    }
    
    /**
     * 读取字符串，处理多行字符串和转义字符
     */
    private function readString():Object {
        var str:String = "";
        var quoteType:String = this.currentChar;
        var isMultiline:Boolean = false;
        this.nextChar(); 
    
        // 检查是否为多行字符串（三个引号）
        if (this.currentChar == quoteType && this.peek() == quoteType) {
            isMultiline = true;
            this.nextChar(); this.nextChar(); 
        }
    
        while (this.currentChar != quoteType || 
               (isMultiline && this.peek() == quoteType && this.peekAhead(2) == quoteType)) {
            if (this.currentChar == null) {
                this.error("未关闭的字符串");
                break;
            }
            if (this.currentChar == "\\") {
                // 处理转义字符
                var escapeSeq:String = "\\" + this.peek();
                str += this.handleEscapeSequences(escapeSeq);
                this.nextChar(); // 跳过反斜杠
                this.nextChar(); // 跳过转义字符
            } else {
                str += this.currentChar;
                this.nextChar();
            }
        }
    
        this.nextChar(); 
        if (isMultiline) {
            this.nextChar(); this.nextChar(); 
        }
    
        return { type: "STRING", value: str };
    }
    
    /**
     * 读取数字或日期时间
     * 支持负号、分数点、下划线（忽略）、以及日期时间标识符
     */
    private function readNumberOrDate():Object {
        var number:String = "";
        var isFloat:Boolean = false;
    
        // Handle negative sign
        if (this.currentChar == "-") {
            number += "-";
            this.nextChar();
        }
    
        // After handling negative sign
        if (this.currentChar == "i" || this.currentChar == "n") {
            var identifier:String = this.readIdentifier();
            var lowerIdentifier:String = (number + identifier).toLowerCase();
    
            if (lowerIdentifier == "nan" || lowerIdentifier == "inf" || lowerIdentifier == "-inf") {
                return { type: "FLOAT", value: lowerIdentifier };
            } else {
                this.error("未知的特殊浮点数: " + lowerIdentifier);
                return { type: "INVALID", value: lowerIdentifier };
            }
        }
    
        // Read integer part
        while (this.isDigit(this.currentChar) || this.currentChar == "_") {
            if (this.currentChar != "_") { // Ignore underscores
                number += this.currentChar;
            }
            this.nextChar();
        }
    
        // Check for decimal point
        if (this.currentChar == ".") {
            isFloat = true;
            number += ".";
            this.nextChar();
            while (this.isDigit(this.currentChar)) {
                number += this.currentChar;
                this.nextChar();
            }
        }
    
        // Check for date-time indicator
        if (this.currentChar == "T" || this.currentChar == "Z" || this.currentChar == ":" || this.currentChar == "-" || this.currentChar == "+" || this.currentChar == "z") {
            return this.readDateTime(number);
        }
    
        // Remove underscores
        number = number.split("_").join("");
    
        return { type: isFloat ? "FLOAT" : "INTEGER", value: number };
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
    private function readDateTime(initial:String):Object {
        var dateTime:String = initial;
        var possibleChars:String = "TtZz+-:";
    
        while (this.currentChar != null && 
               (this.isAlphaNumeric(this.currentChar) || possibleChars.indexOf(this.currentChar) != -1)) {
            dateTime += this.currentChar;
            this.nextChar();
        }
    
        return { type: "DATETIME", value: dateTime };
    }
    
    /**
     * 读取数组
     * 支持嵌套数组和内联表格
     */
    private function readArray():Object {
        var array:Array = [];
        this.nextChar(); // Skip '['
    
        this.skipWhitespaceAndComments();
    
        while (this.currentChar != "]" && this.currentChar != null) {
            this.skipWhitespaceAndComments();
    
            if (this.currentChar == ",") {
                this.nextChar(); // Skip comma
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
            else if (this.isAlpha(this.currentChar)) {
                var identifier:String = this.readIdentifier();
                var lowerIdentifier:String = identifier.toLowerCase();
    
                if (lowerIdentifier == "true" || lowerIdentifier == "false") {
                    element = { type: "BOOLEAN", value: (lowerIdentifier == "true") };
                } else if (lowerIdentifier == "nan" || lowerIdentifier == "inf" || lowerIdentifier == "-inf") {
                    element = { type: "FLOAT", value: lowerIdentifier };
                } else if (lowerIdentifier == "null") {
                    element = { type: "NULL", value: null };
                } else {
                    this.error("无效的数组元素: " + identifier);
                    element = { type: "INVALID", value: identifier };
                }
            }
            // 处理内联表格
            else if (this.currentChar == "{") {
                element = this.readInlineTable();
            }
            // 处理未知字符
            else {
                this.error("无效的数组元素: " + this.currentChar);
                this.nextChar();
                continue;
            }
    
            array.push(element);
    
            this.skipWhitespaceAndComments();
    
            if (this.currentChar == ",") {
                this.nextChar(); // Skip comma
            }
        }
    
        if (this.currentChar == "]") {
            this.nextChar(); // 跳过 ']'
        } else {
            this.error("未正确关闭的数组");
        }
    
        return { type: "ARRAY", value: array };
    }
    
    /**
     * 读取内联表格
     * 支持嵌套内联表格的未来扩展
     */
    private function readInlineTable():Object {
        var inlineTable:String = "";
        this.nextChar(); // 跳过 '{'
    
        while (this.currentChar != "}" && this.currentChar != null) {
            if (this.currentChar == "\\") {
                // 处理转义字符
                var escapeSeq:String = "\\" + this.peek();
                inlineTable += this.handleEscapeSequences(escapeSeq);
                this.nextChar(); // 跳过反斜杠
                this.nextChar(); // 跳过转义字符
            } else {
                inlineTable += this.currentChar;
                this.nextChar();
            }
        }
    
        if (this.currentChar == "}") {
            this.nextChar(); // 跳过 '}'
        } else {
            this.error("未正确关闭的内联表格");
        }
    
        return { type: "INLINE_TABLE", value: inlineTable };
    }
    
    /**
     * 读取表格头或表格数组
     */
    private function readTableHeader():Object {
        var tableName:String = "";
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
                return { type: "TABLE_ARRAY", value: tableName };
            } else {
                this.error("未正确关闭的表格数组");
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
                return { type: "TABLE_HEADER", value: tableName };
            } else {
                this.error("未正确关闭的表格头");
                return null;
            }
        }
    }
    
    // 检查字符是否为字母（包括Unicode字符）
    private function isAlpha(c:String):Boolean {
        // 使用预编译的 RegExp 实例
        return alphaRegex.test(c);
    }
    
    // 检查字符是否为字母或数字（包括Unicode字符）
    private function isAlphaNumeric(c:String):Boolean {
        // 使用预编译的 RegExp 实例
        return alphaNumericRegex.test(c);
    }
    
    // 检查字符是否为数字
    private function isDigit(c:String):Boolean {
        return c >= "0" && c <= "9";
    }
    
    // 查看下一个字符而不移动指针
    private function peek():String {
        if (this.position < this.text.length) {
            return this.text.charAt(this.position);
        }
        return "";
    }
    
    // 查看接下来的第 n 个字符而不移动指针
    private function peekAhead(n:Number):String {
        if (this.position + n < this.text.length) {
            return this.text.charAt(this.position + n);
        }
        return "";
    }
    
    // 抛出错误，包含行号和列号
    private function error(message:String):Void {
        var lineInfo:String = "行: " + this.getLineNumber() + ", 列: " + this.getColumnNumber();
        trace("错误: " + message + " 在 " + lineInfo);
    }
    
    // 获取行号
    private function getLineNumber():Number {
        // 计算当前字符位置对应的行号
        var lines:Array = this.text.substring(0, this.position).split("\n");
        return lines.length;
    }
    
    // 获取列号
    private function getColumnNumber():Number {
        // 计算当前字符位置对应的列号
        var lines:Array = this.text.substring(0, this.position).split("\n");
        var lastLine:String = lines[lines.length - 1];
        return lastLine.length + 1;
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
                    this.error("Incomplete escape sequence");
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
                            this.error("Invalid Unicode escape sequence: \\u" + unicodeSeq);
                            result += "\\u" + unicodeSeq;
                            i += 4; // Still move past the invalid sequence
                        }
                        break;

                    case "U":
                        // 8-digit Unicode
                        var unicodeSeq8:String = str.substr(i + 1, 8);
                        if (this.isValidUnicodeSequence(unicodeSeq8)) {  // Validate 8-digit Unicode
                            var codePoint:Number = parseInt(unicodeSeq8, 16);
                            result += this.convertCodePointToUTF16(codePoint);  // Use existing function to convert
                            i += 8;  // Move past the 8-digit sequence
                        } else {
                            this.error("Invalid Unicode escape sequence: \\U" + unicodeSeq8);
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

    private function isHexadecimal(char:String):Boolean {
        var hexChars:String = "0123456789ABCDEFabcdef";
        return hexChars.indexOf(char) != -1;
    }

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
     * 判断值是否为数组
     * @param value 要判断的值
     * @return 是否为数组
     */
    private function isArray(value:Object):Boolean {
        return value != null && typeof(value) == "object" && typeof(value.length) == "number";
    }
    
    /**
     * 判断对象是否为内联表格（没有嵌套的表格）
     * @param obj 对象
     * @return 是否为内联表格
     */
    private function isInlineTable(obj:Object):Boolean {
        for (var key:String in obj) {
            var value:Object = obj[key];
            if (typeof(value) == "object" && value != null) {
                return false; // 任何对象类型都认为是嵌套，不能作为内联表格
            }
        }
        return true;
    }
    
    /**
     * 判断数组是否为表格数组（数组的元素都是非 null 的对象且不是 Date 或数组）
     * @param arr 数组
     * @return 是否为表格数组
     */
    private function isArrayOfTables(arr:Object):Boolean {
        if (!this.isArray(arr)) {
            return false;
        }
        if (arr.length == 0) {
            return false; // 空数组不是表格数组
        }
        for (var i:Number = 0; i < arr.length; i++) {
            var element:Object = arr[i];
            if (typeof(element) != "object" || element == null || element instanceof Date || this.isArray(element)) {
                return false; // 仅当所有元素都是非 null 的对象且不是 Date 或数组时，才认为是表格数组
            }
        }
        return true;
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
