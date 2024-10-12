import org.flashNight.gesh.regexp.RegExp;
import org.flashNight.gesh.fntl.FNTLLexer; // 确保 Lexer 类路径正确
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * FNTLParser 类用于解析 FNTL（FlashNight Text Language）输入。
 * 
 * 功能：
 * - 解析键值对、嵌套表格和数组。
 * - 处理内联表格。
 * - 支持多种数据类型，包括字符串、数字、布尔值和日期时间。
 * - 提供稳健的错误处理和报告。
 * - 增强的日志输出能力，便于调试和测试。
 */
class org.flashNight.gesh.fntl.FNTLParser {
    private var tokens:Array;
    private var position:Number;
    private var current:Object;
    private var root:Object;
    private var hasErrorFlag:Boolean;
    private var text:String;
    
    // 日志输出开关
    private var debug:Boolean;

    /**
     * 构造函数
     * @param tokens 要解析的 Token 列表。
     * @param text 原始文本。
     * @param debugFlag 可选参数，设置日志输出开关（默认为 false）。
     */
    public function FNTLParser(tokens:Array, text:String, debugFlag:Boolean) {
        this.tokens = tokens;
        this.text = text;
        this.position = 0;
        this.current = null;
        this.root = new Object();
        this.hasErrorFlag = false;
        this.debug = debugFlag;
        
        // 初始化 this.current 为 this.root
        this.current = this.root;
        
        if (this.debug) {
            trace("FNTLParser 初始化。总 Token 数: " + this.tokens.length);
        }
    }

    /**
     * 解析 Token 列表并构建 FNTL 对象。
     * @return 解析后的 FNTL 对象。
     */
    public function parse():Object {
        if (this.debug) {
            trace("开始解析 FNTL 文本。");
        }
        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];
            if (this.debug) {
                trace("当前 Token[" + this.position + "]: Type = " + token.type + ", Value = " + token.value);
            }

            switch (token.type) {
                case "KEY":
                    if (!this.handleKeyValuePair()) {
                        // 如果在处理键值对时发生错误，停止解析
                        if (this.debug) {
                            trace("处理键值对时发生错误，停止解析。");
                        }
                        return null;
                    }
                    break;
                case "LBRACKET":
                    // 处理表头和表数组
                    if (!this.handleTable()) {
                        return null;
                    }
                    break;
                case "INLINE_TABLE":
                    this.handleInlineTable(token.value);
                    this.position++;
                    break;
                case "NEWLINE":
                    // 跳过 NEWLINE token
                    if (this.debug) {
                        trace("跳过 NEWLINE token。");
                    }
                    this.position++;
                    break;
                case "EQUALS":
                case "RBRACKET":
                case "COMMA":
                case "DOT":
                case "COLON":
                case "LBRACE":
                case "RBRACE":
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
                if (this.debug) {
                    trace("检测到错误标志，停止解析。");
                }
                break; // 如果发生关键错误，停止解析
            }
        }
        if (this.debug) {
            trace("解析完成。构建的对象: " + ObjectUtil.toString(this.root));
        }
        return this.root;
    }

    /**
     * 处理表头和表数组
     * @return 如果成功处理返回 true，否则返回 false。
     */
    private function handleTable():Boolean {
        var startToken:Object = this.tokens[this.position];
        var isArray:Boolean = false;
        var tableNameTokens:Array = [];
        this.position++; // 跳过第一个 '['

        // 检查是否为表数组
        if (this.position < this.tokens.length && this.tokens[this.position].type == "LBRACKET") {
            isArray = true;
            this.position++; // 跳过第二个 '['
        }

        // 收集表名的 Token
        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];
            if (token.type == "RBRACKET") {
                // 如果是表数组，还需要检查第二个 ']'
                if (isArray && this.position + 1 < this.tokens.length && this.tokens[this.position + 1].type == "RBRACKET") {
                    this.position += 2; // 跳过两个 ']'
                } else {
                    this.position++; // 跳过 ']'
                }
                break;
            } else {
                tableNameTokens.push(token);
                this.position++;
            }
        }

        // 构建表名
        var tableName:String = "";
        for (var i:Number = 0; i < tableNameTokens.length; i++) {
            tableName += tableNameTokens[i].value;
        }

        if (this.debug) {
            if (isArray) {
                trace("处理表数组: " + tableName);
            } else {
                trace("处理表头: " + tableName);
            }
        }

        if (isArray) {
            this.handleTableArray(tableName);
        } else {
            this.handleTableHeader(tableName);
        }

        return true;
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

        if (this.debug) {
            trace("处理键值对，键: " + key);
        }

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

        var value:Object = this.parseValue();

        if (this.debug) {
            trace("解析键值对，键: " + key + ", 值: " + ObjectUtil.toString(value));
        }

        if (value !== undefined) { // 仅在成功解析值时设置键值
            if (this.current[key] !== undefined) {
                this.error("Duplicate key '" + key + "'", keyToken);
            } else {
                this.current[key] = value;
            }
        }
        return true;
    }

    /**
     * 解析一个值，从当前 position 开始。
     * @return 解析后的值对象。
     */
    private function parseValue():Object {
        var token:Object = this.tokens[this.position];
        if (this.debug) {
            trace("解析值，Token Type: " + token.type + ", Value: " + token.value);
        }

        // 处理浮点数：INTEGER DOT INTEGER
        if (token.type == "INTEGER") {
            if (this.position + 2 < this.tokens.length &&
                this.tokens[this.position + 1].type == "DOT" &&
                this.tokens[this.position + 2].type == "INTEGER") {

                var integerPart:String = token.value;
                var dot:String = this.tokens[this.position + 1].value;
                var fractionalPart:String = this.tokens[this.position + 2].value;

                var floatStr:String = integerPart + dot + fractionalPart;
                var floatVal:Number = Number(floatStr);
                this.position += 3; // 跳过 INTEGER, DOT, INTEGER

                if (isNaN(floatVal)) {
                    this.error("Invalid float value: " + floatStr, token);
                    return undefined;
                }

                if (this.debug) {
                    trace("解析浮点数值: " + floatVal);
                }

                return floatVal;
            }
        }

        // 处理负浮点数：'-' FLOAT
        if (token.type == "INTEGER" && token.value == "-") {
            if (this.position + 1 < this.tokens.length &&
                this.tokens[this.position + 1].type == "FLOAT") {

                var floatToken:Object = this.tokens[this.position + 1];
                var floatValue:String = floatToken.value.toLowerCase();
                var negativeFloat:Number;

                switch(floatValue) {
                    case "inf":
                        negativeFloat = Number.NEGATIVE_INFINITY;
                        break;
                    case "nan":
                        negativeFloat = Number.NaN;
                        break;
                    default:
                        negativeFloat = Number("-" + floatValue);
                        break;
                }

                this.position += 2; // 跳过 '-' 和 FLOAT

                if (this.debug) {
                    trace("解析负浮点数值: " + negativeFloat);
                }

                return negativeFloat;
            }
        }

        // 处理其他类型
        switch(token.type) {
            case "STRING":
                this.position++;
                return token.value;
            case "INTEGER":
                this.position++;
                return Number(token.value);
            case "FLOAT":
                this.position++;
                return this.parseSpecialFloat(token.value);
            case "BOOLEAN":
                this.position++;
                return token.value;
            case "DATETIME":
                this.position++;
                return this.parseDateTime(token.value);
            case "LBRACKET":
                return this.parseArray();
            case "LBRACE":
                return this.parseInlineTable();
            case "NULL":
                this.position++;
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
        if (this.debug) {
            trace("解析特殊浮点数值: " + value);
        }
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
        if (this.debug) {
            trace("解析日期时间字符串: " + dateTimeStr);
        }
        // 使用 FNTLLexer 中定义的 dateTimeRegExp
        if (!FNTLLexer.dateTimeRegExp.test(dateTimeStr)) {
            this.error("Invalid datetime format: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        // 直接返回日期时间字符串，保留分数秒和时区信息
        return dateTimeStr;
    }

    /**
     * 解析数组，从当前 position 开始。
     * @return 解析后的数组或 null（如果有错误）。
     */
    private function parseArray():Array {
        if (this.debug) {
            trace("开始解析数组。");
        }
        var array:Array = new Array();
        this.position++; // 跳过 '['

        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];

            if (token.type == "RBRACKET") {
                this.position++; // 跳过 ']'
                break;
            } else if (token.type == "COMMA") {
                this.position++; // 跳过逗号
                continue;
            } else if (token.type == "NEWLINE") {
                // 跳过 NEWLINE token
                if (this.debug) {
                    trace("跳过数组中的 NEWLINE token。");
                }
                this.position++;
                continue;
            } else {
                var value:Object = this.parseValue();
                if (value !== undefined) {
                    array.push(value);
                    if (this.debug) {
                        trace("数组元素: " + ObjectUtil.toString(value));
                    }
                } else {
                    this.error("Failed to parse array element", token);
                    return null;
                }
            }
        }

        return array;
    }

    /**
     * 解析内联表格，从当前 position 开始。
     * @return 解析后的内联表格对象或 undefined（如果有错误）。
     */
    private function parseInlineTable():Object {
        if (this.debug) {
            trace("开始解析内联表格。");
        }
        var table:Object = new Object();
        this.position++; // 跳过 '{'

        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];

            if (token.type == "RBRACE") {
                this.position++; // 跳过 '}'
                break;
            } else if (token.type == "COMMA") {
                this.position++; // 跳过逗号
                continue;
            } else if (token.type == "KEY" || token.type == "INTEGER") { // 允许 KEY 和 INTEGER 类型的键
                var key:String = token.value.toString(); // 将键转换为字符串
                this.position++;

                // 检查 '='
                if (this.position >= this.tokens.length || this.tokens[this.position].type != "EQUALS") {
                    this.error("Expected '=' after key '" + key + "'", token);
                    return undefined;
                }
                this.position++; // 跳过 '='

                var value:Object = this.parseValue();
                if (value !== undefined) {
                    if (table[key] !== undefined) {
                        this.error("Duplicate key '" + key + "' in inline table", token);
                        return undefined;
                    }
                    table[key] = value;
                    if (this.debug) {
                        trace("内联表格键值对: " + key + " = " + ObjectUtil.toString(value));
                    }
                } else {
                    this.error("Failed to parse value for key '" + key + "' in inline table", token);
                    return undefined;
                }
            } else if (token.type == "NEWLINE") {
                // 跳过 NEWLINE token
                if (this.debug) {
                    trace("跳过内联表格中的 NEWLINE token。");
                }
                this.position++;
                continue;
            } else {
                this.error("Unexpected token in inline table: " + token.type, token);
                return undefined;
            }
        }

        return table;
    }

    /**
     * 处理表格头 Token，更新当前上下文。
     * 支持嵌套的表格路径。
     * @param tableName 表格名。
     */
    private function handleTableHeader(tableName:String):Void {
        if (this.debug) {
            trace("处理表格头: " + tableName);
        }
        var path:Array = tableName.split(".");
        var current:Object = this.root;

        for (var i:Number = 0; i < path.length; i++) {
            var part:String = path[i];
            if (current[part] == undefined || current[part] == null) {
                current[part] = new Object();
                if (this.debug) {
                    trace("创建新表格: " + part);
                }
            } else if (!(current[part] instanceof Object)) {
                this.error("Key conflict: Cannot convert non-table type to table '" + part + "'", {line: 0, column: 0});
                return;
            }
            current = current[part];
        }
        this.current = current;
        if (this.debug) {
            trace("当前上下文更新到: " + tableName);
        }
    }

    /**
    * 处理表格数组 Token，向数组中添加新的表格。
    * @param arrayName 表格数组名。
    */
    private function handleTableArray(arrayName:String):Void {
        if (this.debug) {
            trace("处理表格数组: " + arrayName);
        }
        var path:Array = arrayName.split(".");
        var current:Object = this.root;

        for (var i:Number = 0; i < path.length; i++) {
            var part:String = path[i];
            if (i < path.length - 1) {
                // 处理中间部分，确保它是一个数组，并指向最后一个元素
                if (!(current[part] instanceof Array)) {
                    current[part] = new Array();
                    if (this.debug) {
                        trace("创建新表格数组: " + part);
                    }
                }
                if (current[part].length == 0) {
                    var nestedTable:Object = new Object();
                    current[part].push(nestedTable);
                    if (this.debug) {
                        trace("向表格数组 '" + part + "' 添加新表格。");
                    }
                    current = nestedTable;
                } else {
                    current = current[part][current[part].length - 1];
                    if (this.debug) {
                        trace("当前表格数组 '" + part + "' 的最新表格。");
                    }
                }
            } else {
                // 处理最后一部分，确保它是一个数组，并添加新表格
                if (!(current[part] instanceof Array)) {
                    current[part] = new Array();
                    if (this.debug) {
                        trace("创建新表格数组: " + part);
                    }
                }
                var newTable:Object = new Object();
                current[part].push(newTable);
                if (this.debug) {
                    trace("向表格数组 '" + part + "' 添加新表格。");
                }
                current = newTable;
            }
        }
        this.current = current;
        if (this.debug) {
            trace("当前上下文更新到: " + arrayName);
        }
    }



    /**
     * 处理内联表格 Token，将其解析并合并到当前上下文。
     * @param inlineTableStr 内联表格字符串。
     */
    private function handleInlineTable(inlineTableStr:String):Void {
        if (this.debug) {
            trace("处理内联表格: " + inlineTableStr);
        }
        var inlineTable:Object = this.parseInlineTable();
        if (inlineTable === undefined) {
            if (this.debug) {
                trace("内联表格解析失败: " + inlineTableStr);
            }
            return;
        }
        for (var key:String in inlineTable) {
            if (this.current[key] !== undefined) {
                this.error("Duplicate key '" + key + "'", {line: 0, column: 0});
            } else {
                this.current[key] = inlineTable[key];
                if (this.debug) {
                    trace("将内联表格的键值对添加到当前上下文: " + key + " = " + ObjectUtil.toString(inlineTable[key]));
                }
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
        if (this.debug) {
            trace("当前解析位置: " + this.position + "/" + this.tokens.length);
        }
    }
}
