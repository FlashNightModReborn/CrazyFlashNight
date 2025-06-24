/**
 * CircularJSON - 增强型JSON解析器
 * 第一阶段：标准JSON解析功能
 * 后续阶段将支持循环引用处理
 * 
 * 设计原则：
 * 1. 清晰的模块化结构
 * 2. 便于扩展和维护
 * 3. 符合AS2语法规范
 * 4. 为循环引用功能预留接口
 */

class CircularJSON implements IJSON {
    
    // ========================
    // 配置选项
    // ========================
    
    /** 是否启用严格模式 */
    public var strictMode:Boolean;
    
    /** 序列化时的缩进字符 */
    public var indentChar:String;
    
    /** 是否美化输出 */
    public var prettyPrint:Boolean;
    
    // ========================
    // 解析状态
    // ========================
    
    /** 当前解析的文本 */
    private var sourceText:String;
    
    /** 当前字符位置 */
    private var position:Number;
    
    /** 当前字符 */
    private var currentChar:String;
    
    /** 当前行号（用于错误报告） */
    private var lineNumber:Number;
    
    /** 当前列号（用于错误报告） */
    private var columnNumber:Number;
    
    // ========================
    // 构造函数
    // ========================
    
    /**
     * 构造函数
     * @param strictMode 是否启用严格模式，默认false
     */
    public function CircularJSON(strictMode:Boolean) {
        this.strictMode = (strictMode != undefined) ? strictMode : false;
        this.indentChar = "  ";
        this.prettyPrint = false;
        this.resetParseState();
    }
    
    // ========================
    // 公共API
    // ========================
    
    /**
     * 将对象序列化为JSON字符串
     * @param value 要序列化的值
     * @return JSON字符串
     */
    public function stringify(value):String {
        try {
            return this.serializeValue(value, 0);
        } catch (error) {
            this.throwError("Serialization failed: " + error.message);
            return null;
        }
    }
    
    /**
     * 将JSON字符串解析为对象
     * @param jsonText JSON字符串
     * @return 解析后的对象
     */
    public function parse(jsonText:String) {
        if (jsonText == null || jsonText == undefined) {
            this.throwError("Input text cannot be null or undefined");
            return null;
        }
        
        this.initializeParsing(jsonText);
        
        try {
            var result = this.parseValue();
            this.skipWhitespace();
            
            if (this.currentChar != "") {
                this.throwError("Unexpected characters after JSON");
            }
            
            return result;
        } catch (error) {
            this.throwError("Parse failed: " + error.message);
            return null;
        }
    }
    
    // ========================
    // 序列化模块
    // ========================
    
    /**
     * 序列化任意值
     * @param value 要序列化的值
     * @param depth 当前嵌套深度
     * @return 序列化后的字符串
     */
    private function serializeValue(value, depth:Number):String {
        var valueType:String = typeof value;
        
        switch (valueType) {
            case "string":
                return this.serializeString(value);
                
            case "number":
                return this.serializeNumber(value);
                
            case "boolean":
                return this.serializeBoolean(value);
                
            case "object":
                return this.serializeObject(value, depth);
                
            case "undefined":
            default:
                return "null";
        }
    }
    
    /**
     * 序列化字符串
     * @param str 字符串值
     * @return 序列化后的字符串
     */
    private function serializeString(str:String):String {
        var result:String = "\"";
        var length:Number = str.length;
        var i:Number;
        var char:String;
        
        for (i = 0; i < length; i++) {
            char = str.charAt(i);
            
            switch (char) {
                case "\"":
                    result += "\\\"";
                    break;
                case "\\":
                    result += "\\\\";
                    break;
                case "\b":
                    result += "\\b";
                    break;
                case "\f":
                    result += "\\f";
                    break;
                case "\n":
                    result += "\\n";
                    break;
                case "\r":
                    result += "\\r";
                    break;
                case "\t":
                    result += "\\t";
                    break;
                default:
                    if (char < " ") {
                        result += this.encodeUnicodeEscape(char);
                    } else {
                        result += char;
                    }
                    break;
            }
        }
        
        return result + "\"";
    }
    
    /**
     * 序列化数字
     * @param num 数字值
     * @return 序列化后的字符串
     */
    private function serializeNumber(num:Number):String {
        if (isNaN(num) || !isFinite(num)) {
            return "null";
        }
        return String(num);
    }
    
    /**
     * 序列化布尔值
     * @param bool 布尔值
     * @return 序列化后的字符串
     */
    private function serializeBoolean(bool:Boolean):String {
        return bool ? "true" : "false";
    }
    
    /**
     * 序列化对象（包括数组）
     * @param obj 对象值
     * @param depth 当前嵌套深度
     * @return 序列化后的字符串
     */
    private function serializeObject(obj, depth:Number):String {
        if (obj == null) {
            return "null";
        }
        
        if (obj instanceof Array) {
            return this.serializeArray(obj, depth);
        } else {
            return this.serializeObjectLiteral(obj, depth);
        }
    }
    
    /**
     * 序列化数组
     * @param arr 数组
     * @param depth 当前嵌套深度
     * @return 序列化后的字符串
     */
    private function serializeArray(arr:Array, depth:Number):String {
        var result:String = "[";
        var length:Number = arr.length;
        var i:Number;
        
        for (i = 0; i < length; i++) {
            if (i > 0) {
                result += ",";
            }
            
            if (this.prettyPrint) {
                result += this.getNewlineAndIndent(depth + 1);
            }
            
            result += this.serializeValue(arr[i], depth + 1);
        }
        
        if (this.prettyPrint && length > 0) {
            result += this.getNewlineAndIndent(depth);
        }
        
        return result + "]";
    }
    
    /**
     * 序列化对象字面量
     * @param obj 对象
     * @param depth 当前嵌套深度
     * @return 序列化后的字符串
     */
    private function serializeObjectLiteral(obj:Object, depth:Number):String {
        var result:String = "{";
        var isFirst:Boolean = true;
        var key:String;
        var value;
        
        for (key in obj) {
            if (obj.hasOwnProperty(key)) {
                value = obj[key];
                
                // 跳过函数和undefined值
                if (typeof value == "function" || typeof value == "undefined") {
                    continue;
                }
                
                if (!isFirst) {
                    result += ",";
                }
                isFirst = false;
                
                if (this.prettyPrint) {
                    result += this.getNewlineAndIndent(depth + 1);
                }
                
                result += this.serializeString(key) + ":";
                
                if (this.prettyPrint) {
                    result += " ";
                }
                
                result += this.serializeValue(value, depth + 1);
            }
        }
        
        if (this.prettyPrint && !isFirst) {
            result += this.getNewlineAndIndent(depth);
        }
        
        return result + "}";
    }
    
    // ========================
    // 解析模块
    // ========================
    
    /**
     * 解析任意值
     * @return 解析后的值
     */
    private function parseValue() {
        this.skipWhitespace();
        
        switch (this.currentChar) {
            case "\"":
                return this.parseString();
                
            case "{":
                return this.parseObject();
                
            case "[":
                return this.parseArray();
                
            case "t":
            case "f":
            case "n":
                return this.parseKeyword();
                
            case "-":
            case "0":
            case "1":
            case "2":
            case "3":
            case "4":
            case "5":
            case "6":
            case "7":
            case "8":
            case "9":
                return this.parseNumber();
                
            default:
                this.throwError("Unexpected character '" + this.currentChar + "'");
                return null;
        }
    }
    
    /**
     * 解析字符串
     * @return 解析后的字符串
     */
    private function parseString():String {
        if (this.currentChar != "\"") {
            this.throwError("Expected '\"' at start of string");
            return null;
        }
        
        this.nextChar();
        var result:String = "";
        
        while (this.currentChar != "" && this.currentChar != "\"") {
            if (this.currentChar == "\\") {
                this.nextChar();
                result += this.parseEscapeSequence();
            } else {
                result += this.currentChar;
                this.nextChar();
            }
        }
        
        if (this.currentChar != "\"") {
            this.throwError("Unterminated string");
            return null;
        }
        
        this.nextChar();
        return result;
    }
    
    /**
     * 解析对象
     * @return 解析后的对象
     */
    private function parseObject():Object {
        if (this.currentChar != "{") {
            this.throwError("Expected '{' at start of object");
            return null;
        }
        
        this.nextChar();
        this.skipWhitespace();
        
        var result:Object = {};
        
        if (this.currentChar == "}") {
            this.nextChar();
            return result;
        }
        
        while (true) {
            this.skipWhitespace();
            
            // 解析键
            var key:String = this.parseString();
            
            this.skipWhitespace();
            
            if (this.currentChar != ":") {
                this.throwError("Expected ':' after object key");
                return null;
            }
            
            this.nextChar();
            
            // 解析值
            var value = this.parseValue();
            result[key] = value;
            
            this.skipWhitespace();
            
            if (this.currentChar == "}") {
                this.nextChar();
                break;
            }
            
            if (this.currentChar != ",") {
                this.throwError("Expected ',' or '}' in object");
                return null;
            }
            
            this.nextChar();
        }
        
        return result;
    }
    
    /**
     * 解析数组
     * @return 解析后的数组
     */
    private function parseArray():Array {
        if (this.currentChar != "[") {
            this.throwError("Expected '[' at start of array");
            return null;
        }
        
        this.nextChar();
        this.skipWhitespace();
        
        var result:Array = [];
        
        if (this.currentChar == "]") {
            this.nextChar();
            return result;
        }
        
        while (true) {
            var value = this.parseValue();
            result.push(value);
            
            this.skipWhitespace();
            
            if (this.currentChar == "]") {
                this.nextChar();
                break;
            }
            
            if (this.currentChar != ",") {
                this.throwError("Expected ',' or ']' in array");
                return null;
            }
            
            this.nextChar();
        }
        
        return result;
    }
    
    /**
     * 解析数字
     * @return 解析后的数字
     */
    private function parseNumber():Number {
        var numberText:String = "";
        
        // 处理负号
        if (this.currentChar == "-") {
            numberText += this.currentChar;
            this.nextChar();
        }
        
        // 处理整数部分
        if (this.currentChar == "0") {
            numberText += this.currentChar;
            this.nextChar();
        } else if (this.currentChar >= "1" && this.currentChar <= "9") {
            while (this.currentChar >= "0" && this.currentChar <= "9") {
                numberText += this.currentChar;
                this.nextChar();
            }
        } else {
            this.throwError("Invalid number format");
            return NaN;
        }
        
        // 处理小数部分
        if (this.currentChar == ".") {
            numberText += this.currentChar;
            this.nextChar();
            
            if (this.currentChar < "0" || this.currentChar > "9") {
                this.throwError("Invalid number format: expected digit after '.'");
                return NaN;
            }
            
            while (this.currentChar >= "0" && this.currentChar <= "9") {
                numberText += this.currentChar;
                this.nextChar();
            }
        }
        
        // 处理指数部分
        if (this.currentChar == "e" || this.currentChar == "E") {
            numberText += this.currentChar;
            this.nextChar();
            
            if (this.currentChar == "+" || this.currentChar == "-") {
                numberText += this.currentChar;
                this.nextChar();
            }
            
            if (this.currentChar < "0" || this.currentChar > "9") {
                this.throwError("Invalid number format: expected digit in exponent");
                return NaN;
            }
            
            while (this.currentChar >= "0" && this.currentChar <= "9") {
                numberText += this.currentChar;
                this.nextChar();
            }
        }
        
        var result:Number = Number(numberText);
        if (isNaN(result)) {
            this.throwError("Invalid number: " + numberText);
        }
        
        return result;
    }
    
    /**
     * 解析关键字（true、false、null）
     * @return 解析后的值
     */
    private function parseKeyword() {
        var keyword:String = "";
        
        while ((this.currentChar >= "a" && this.currentChar <= "z") || 
               (this.currentChar >= "A" && this.currentChar <= "Z")) {
            keyword += this.currentChar;
            this.nextChar();
        }
        
        switch (keyword) {
            case "true":
                return true;
            case "false":
                return false;
            case "null":
                return null;
            default:
                this.throwError("Unknown keyword: " + keyword);
                return null;
        }
    }
    
    // ========================
    // 工具方法
    // ========================
    
    /**
     * 重置解析状态
     */
    private function resetParseState():Void {
        this.sourceText = "";
        this.position = 0;
        this.currentChar = "";
        this.lineNumber = 1;
        this.columnNumber = 1;
    }
    
    /**
     * 初始化解析
     * @param text 要解析的文本
     */
    private function initializeParsing(text:String):Void {
        this.sourceText = text;
        this.position = 0;
        this.lineNumber = 1;
        this.columnNumber = 1;
        this.nextChar();
    }
    
    /**
     * 移动到下一个字符
     */
    private function nextChar():Void {
        if (this.position >= this.sourceText.length) {
            this.currentChar = "";
            return;
        }
        
        this.currentChar = this.sourceText.charAt(this.position);
        this.position++;
        
        if (this.currentChar == "\n") {
            this.lineNumber++;
            this.columnNumber = 1;
        } else {
            this.columnNumber++;
        }
    }
    
    /**
     * 跳过空白字符
     */
    private function skipWhitespace():Void {
        while (this.currentChar == " " || 
               this.currentChar == "\t" || 
               this.currentChar == "\n" || 
               this.currentChar == "\r") {
            this.nextChar();
        }
    }
    
    /**
     * 解析转义序列
     * @return 转义后的字符
     */
    private function parseEscapeSequence():String {
        switch (this.currentChar) {
            case "\"":
                this.nextChar();
                return "\"";
            case "\\":
                this.nextChar();
                return "\\";
            case "/":
                this.nextChar();
                return "/";
            case "b":
                this.nextChar();
                return "\b";
            case "f":
                this.nextChar();
                return "\f";
            case "n":
                this.nextChar();
                return "\n";
            case "r":
                this.nextChar();
                return "\r";
            case "t":
                this.nextChar();
                return "\t";
            case "u":
                return this.parseUnicodeEscape();
            default:
                this.throwError("Invalid escape sequence: \\" + this.currentChar);
                return "";
        }
    }
    
    /**
     * 解析Unicode转义序列
     * @return Unicode字符
     */
    private function parseUnicodeEscape():String {
        this.nextChar(); // 跳过 'u'
        
        var hexValue:Number = 0;
        var i:Number;
        
        for (i = 0; i < 4; i++) {
            var hexDigit:Number = this.parseHexDigit();
            if (hexDigit == -1) {
                this.throwError("Invalid Unicode escape sequence");
                return "";
            }
            hexValue = hexValue * 16 + hexDigit;
            this.nextChar();
        }
        
        return String.fromCharCode(hexValue);
    }
    
    /**
     * 解析十六进制数字
     * @return 十六进制值，-1表示无效
     */
    private function parseHexDigit():Number {
        if (this.currentChar >= "0" && this.currentChar <= "9") {
            return Number(this.currentChar);
        } else if (this.currentChar >= "a" && this.currentChar <= "f") {
            return this.currentChar.charCodeAt(0) - "a".charCodeAt(0) + 10;
        } else if (this.currentChar >= "A" && this.currentChar <= "F") {
            return this.currentChar.charCodeAt(0) - "A".charCodeAt(0) + 10;
        } else {
            return -1;
        }
    }
    
    /**
     * 编码Unicode转义序列
     * @param char 要编码的字符
     * @return 转义序列字符串
     */
    private function encodeUnicodeEscape(char:String):String {
        var charCode:Number = char.charCodeAt(0);
        var hex:String = charCode.toString(16).toUpperCase();
        
        while (hex.length < 4) {
            hex = "0" + hex;
        }
        
        return "\\u" + hex;
    }
    
    /**
     * 获取换行和缩进字符串
     * @param depth 缩进深度
     * @return 格式化字符串
     */
    private function getNewlineAndIndent(depth:Number):String {
        var result:String = "\n";
        var i:Number;
        
        for (i = 0; i < depth; i++) {
            result += this.indentChar;
        }
        
        return result;
    }
    
    /**
     * 抛出错误
     * @param message 错误信息
     */
    private function throwError(message:String):Void {
        var errorMessage:String = message + " at line " + this.lineNumber + ", column " + this.columnNumber;
        
        if (this.strictMode) {
            throw {
                name: "CircularJSONError",
                message: errorMessage,
                line: this.lineNumber,
                column: this.columnNumber,
                position: this.position
            };

        } else {
            // 在非严格模式下，可以选择记录错误而不是抛出
            trace("CircularJSON Warning: " + errorMessage);
        }
    }
}