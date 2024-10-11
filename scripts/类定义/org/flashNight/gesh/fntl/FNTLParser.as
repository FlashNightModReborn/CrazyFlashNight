import org.flashNight.gesh.regexp.RegExp; // 确保您有自定义的 RegExp 类，或使用 AS2 的原生 RegExp（如果可用）
import org.flashNight.gesh.fntl.FNTLLexer; // 确保 Lexer 类路径正确
import org.flashNight.gesh.string.StringUtils;

/**
 * FNTLParser 类用于解析 FNTL（FlashNight Text Language）输入。
 * 
 * 功能：
 * - 解析键值对、嵌套表格和数组。
 * - 处理内联表格。
 * - 支持多种数据类型，包括字符串、数字、布尔值和日期时间。
 * - 提供稳健的错误处理和报告。
 */
class org.flashNight.gesh.fntl.FNTLParser {
    private var tokens:Array;
    private var position:Number;
    private var current:Object;
    private var root:Object;
    private var hasErrorFlag:Boolean;
    private var text:String;

    private function isAlpha(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        // 检查ASCII字母
        if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
            return true;
        }
        // 检查扩展拉丁字母
        if (code >= 0x00C0 && code <= 0x017F) {
            return true;
        }
        // 检查中文字符
        if (code >= 0x4E00 && code <= 0x9FFF) {
            return true;
        }
        // 可根据需要添加更多范围
        return false;
    }


    private function isAlphaNumeric(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        // 检查数字
        if (code >= 48 && code <= 57) {
            return true;
        }
        // 检查下划线
        if (code == 95) {
            return true;
        }
        // 使用 isAlpha 方法
        return isAlpha(c);
    }


    /**
     * 解析 Token 列表并构建 FNTL 对象。
     * @return 解析后的 FNTL 对象。
     */
    public function parse():Object {
        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];

            switch (token.type) {
                case "KEY":
                    if (!this.handleKeyValuePair()) {
                        // 如果在处理键值对时发生错误，停止解析
                        return null;
                    }
                    break;
                case "TABLE_HEADER":
                    this.handleTableHeader(token.value);
                    this.position++;
                    break;
                case "TABLE_ARRAY":
                    this.handleTableArray(token.value);
                    this.position++;
                    break;
                case "INLINE_TABLE":
                    this.handleInlineTable(token.value);
                    this.position++;
                    break;
                case "LBRACKET":
                case "RBRACKET":
                case "COMMA":
                case "DOT":
                case "COLON":
                case "LBRACE":
                case "RBRACE":
                case "EQUALS":
                    // 这些 Token 类型应该在处理上下文时被解析，若出现在此处则为语法错误
                    this.error("Unexpected token: " + token.type, token);
                    this.position++;
                    break;
                default:
                    this.error("Unhandled token type: " + token.type, token);
                    this.position++;
                    break;
            }

            if (this.hasErrorFlag) {
                break; // 如果发生关键错误，停止解析
            }
        }
        return this.root;
    }

    /**
     * 检查解析器是否遇到错误。
     * @return 如果存在错误则为 true，否则为 false。
     */
    public function hasError():Boolean {
        return this.hasErrorFlag;
    }

    /**
     * 处理一个键值对 Token。
     * @return 如果成功处理则返回 true，否则返回 false。
     */
    private function handleKeyValuePair():Boolean {
        var keyToken:Object = this.tokens[this.position];
        var key:String = keyToken.value;
        this.position++;

        // 检查是否有 EQUALS Token
        if (this.position >= this.tokens.length || this.tokens[this.position].type != "EQUALS") {
            this.error("Expected '=' after key '" + key + "'", keyToken);
            return false;
        }
        this.position++; // 跳过 EQUALS Token

        if (this.position >= this.tokens.length) {
            this.error("Missing value for key '" + key + "'", keyToken);
            return false;
        }

        var valueToken:Object = this.tokens[this.position];
        var value:Object = this.parseValue(valueToken);

        if (value !== undefined) { // 仅在成功解析值时设置键值
            if (this.current[key] !== undefined) {
                this.error("Duplicate key '" + key + "'", keyToken);
            } else {
                this.current[key] = value;
            }
        }
        this.position++; // 移动到下一个 Token
        return true;
    }

    /**
     * 解析一个值 Token 并返回对应的 AS2 对象。
     * @param token 要解析的值 Token。
     * @return 解析后的值对象。
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
                this.error("Unknown value type: " + token.type, token);
                return undefined;
        }
    }

    /**
     * 解析特殊浮点数值（NaN, Infinity, -Infinity）。
     * @param value 字符串表示。
     * @return 对应的 AS2 数字。
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
     * 解析日期时间字符串并返回 ISO8601 格式。
     * @param dateTimeStr 日期时间字符串。
     * @return 格式化后的 ISO8601 日期时间字符串或 null（如果解析失败）。
     */
    private function parseDateTime(dateTimeStr:String):String {
        // 使用 FNTLLexer 中定义的 dateTimeRegExp
        if (!FNTLLexer.dateTimeRegExp.test(dateTimeStr)) {
            this.error("Invalid datetime format: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        // 直接返回日期时间字符串，保留分数秒和时区信息
        return dateTimeStr;
    }


    /**
     * 解析数组 Token 为 AS2 数组。
     * @param arrayData 数组 Token 的值。
     * @return 解析后的数组或 null（如果有错误）。
     */
    private function parseArray(arrayData:Array):Array {
        var array:Array = new Array();

        for (var i:Number = 0; i < arrayData.length; i++) {
            var elementToken:Object = arrayData[i];
            var value:Object = this.parseValue(elementToken);

            if (value !== undefined) { // 仅在成功解析值时添加到数组
                array.push(value);
            } else {
                this.error("Failed to parse array element", elementToken);
                return null;
            }
        }

        return array;
    }

    /**
     * 解析内联表格字符串为对象。
     * @param tableStr 内联表格字符串。
     * @return 解析后的内联表格对象或 undefined（如果有错误）。
     */
    private function parseInlineTable(tableStr:String):Object {
        var lexer:FNTLLexer = new FNTLLexer(tableStr);
        var tokens:Array = [];
        var tok:Object;

        while ((tok = lexer.getNextToken()) != null) {
            tokens.push(tok);
        }

        var parser:FNTLParser = new FNTLParser(tokens, tableStr);
        var parsedTable:Object = parser.parse();

        if (parser.hasError()) {
            this.error("Failed to parse inline table: " + tableStr, {line: 0, column: 0});
            return undefined;
        }

        return parsedTable;
    }

    /**
     * 处理表格头 Token，更新当前上下文。
     * 支持嵌套的表格路径。
     * @param tableName 表格名。
     */
    private function handleTableHeader(tableName:String):Void {
        var path:Array = tableName.split(".");
        var current:Object = this.root;

        for (var i:Number = 0; i < path.length; i++) {
            var part:String = path[i];
            if (current[part] == undefined || current[part] == null) {
                current[part] = new Object();
            } else if (!(current[part] instanceof Object)) {
                this.error("Key conflict: Cannot convert non-table type to table '" + part + "'", {line: 0, column: 0});
                return;
            }
            current = current[part];
        }
        this.current = current;
    }

    /**
     * 处理表格数组 Token，向数组中添加新的表格。
     * @param arrayName 表格数组名。
     */
    private function handleTableArray(arrayName:String):Void {
        var path:Array = arrayName.split(".");
        var current:Object = this.root;

        for (var i:Number = 0; i < path.length; i++) {
            var part:String = path[i];
            if (i == path.length - 1) {
                if (!(current[part] instanceof Array)) {
                    current[part] = new Array();
                }
                var newTable:Object = new Object();
                current[part].push(newTable);
                current = newTable;
            } else {
                if (current[part] == undefined || current[part] == null) {
                    current[part] = new Object();
                } else if (current[part] instanceof Array) {
                    current = current[part][current[part].length - 1];
                } else {
                    current = current[part];
                }
            }
        }
        this.current = current;
    }

    /**
     * 处理内联表格 Token，将其解析并合并到当前上下文。
     * @param inlineTableStr 内联表格字符串。
     */
    private function handleInlineTable(inlineTableStr:String):Void {
        var inlineTable:Object = this.parseInlineTable(inlineTableStr);
        for (var key:String in inlineTable) {
            if (this.current[key] !== undefined) {
                this.error("Duplicate key '" + key + "'", {line: 0, column: 0});
            } else {
                this.current[key] = inlineTable[key];
            }
        }
    }

    /**
     * 处理解析错误，通过设置错误标志并记录错误信息。
     * @param message 错误消息。
     * @param token 相关的 Token 对象，用于定位错误位置。
     */
    private function error(message:String, token:Object):Void {
        var lineInfo:String = "行: " + (token.line != undefined ? token.line : "?") + ", 列: " + (token.column != undefined ? token.column : "?");
        trace("错误: " + message + " 在 " + lineInfo);
        this.hasErrorFlag = true;
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
}
