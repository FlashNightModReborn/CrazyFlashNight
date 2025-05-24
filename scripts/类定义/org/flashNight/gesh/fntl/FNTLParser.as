import org.flashNight.gesh.regexp.RegExp;
import org.flashNight.gesh.fntl.FNTLLexer; // Ensure Lexer class path is correct
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
    
    // Log output toggle
    private var debug:Boolean;

    /**
     * Constructor
     * @param tokens The list of tokens to parse.
     * @param text The original text.
     * @param debugFlag Optional parameter to set the debug flag (default is false).
     */
    public function FNTLParser(tokens:Array, text:String, debugFlag:Boolean) {
        this.tokens = tokens;
        this.text = text;
        this.position = 0;
        this.root = new Object();
        this.hasErrorFlag = false;
        this.debug = debugFlag;
        
        // Initialize this.current to this.root
        this.current = this.root;
        
        if (this.debug) {
            trace("FNTLParser Initialized. Total Tokens: " + this.tokens.length);
        }
    }

    /**
     * Parses the list of tokens and constructs the FNTL object.
     * @return The parsed FNTL object.
     */
    public function parse():Object {
        if (this.debug) {
            trace("Starting to parse FNTL text.");
        }

        var tempRoot:Object = new Object(); // Use a temporary object for parsing
        var originalRoot:Object = this.root; // Save the original root object
        this.root = tempRoot; // Temporarily point root to tempRoot
        this.current = this.root; // Reset current context

        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];
            
            // 检测是否为 ERROR token
            if (token.type == "ERROR") {
                this.error(token.value, {line: token.line, column: token.column});
                this.root = originalRoot;
                return null; // 立即停止解析
            }

            if (this.debug) {
                trace("Current Token[" + this.position + "]: Type = " + token.type + ", Value = " + token.value);
            }

            switch (token.type) {
                case "KEY":
                    if (!this.handleKeyValuePair()) {
                        // Error occurred, restore original root and return null
                        if (this.debug) {
                            trace("Error occurred while handling key-value pair. Stopping parsing.");
                        }
                        this.root = originalRoot;
                        return null;
                    }
                    break;
                case "LBRACKET":
                    // Handle table headers and table arrays
                    if (!this.handleTable()) {
                        if (this.debug) {
                            trace("Error occurred while handling table. Stopping parsing.");
                        }
                        this.root = originalRoot;
                        return null;
                    }
                    break;
                case "INLINE_TABLE":
                    var inlineTable:Object = this.parseInlineTable();
                    if (inlineTable !== undefined) {
                        for (var key:String in inlineTable) {
                            if (this.current[key] !== undefined) {
                                this.error("Duplicate key '" + key + "'", {line: 0, column: 0});
                            } else {
                                this.current[key] = inlineTable[key];
                                if (this.debug) {
                                    trace("Added inline table key-value pair to current context: " + key + " = " + ObjectUtil.toString(inlineTable[key]));
                                }
                            }
                        }
                    }
                    this.position++;
                    break;
                case "NEWLINE":
                    // Skip NEWLINE tokens
                    if (this.debug) {
                        trace("Skipping NEWLINE token.");
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
                    // These token types should be handled in context; encountering them here is an error
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
                    trace("Error flag detected. Stopping parsing.");
                }
                this.root = originalRoot;
                return null; // Critical error occurred, return null
            }

            if (this.position >= this.tokens.length) {
            if (this.debug) {
                trace("End of tokens reached.");
            }
            break; // 退出循环，停止进一步解析
}
        }

        if (this.debug) {
            trace("Parsing completed. Constructed Object: " + ObjectUtil.toString(this.root));
        }
        return this.root;
    }


    /**
     * Handles table headers and table arrays.
     * @return Returns true if successfully handled, false otherwise.
     */
    private function handleTable():Boolean {
        var startToken:Object = this.tokens[this.position];
        var isArray:Boolean = false;
        var tableNameTokens:Array = [];
        this.position++; // Skip the first '['

        // Check if it's a table array by looking for a second '['
        if (this.position < this.tokens.length && this.tokens[this.position].type == "LBRACKET") {
            isArray = true;
            this.position++; // Skip the second '['
        }

        // Collect table name tokens until ']' is encountered
        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];
            if (token.type == "RBRACKET") {
                // If it's a table array, ensure there are two closing ']'
                if (isArray && this.position + 1 < this.tokens.length && this.tokens[this.position + 1].type == "RBRACKET") {
                    this.position += 2; // Skip both ']'
                } else {
                    this.position++; // Skip single ']'
                }
                break;
            } else {
                tableNameTokens.push(token);
                this.position++;
            }
        }

        // Construct table name by concatenating token values with dots
        var tableName:String = "";
        for (var i:Number = 0; i < tableNameTokens.length; i++) {
            tableName += tableNameTokens[i].value;
        }

        if (this.debug) {
            if (isArray) {
                trace("Handling table array: " + tableName);
            } else {
                trace("Handling table header: " + tableName);
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
     * Checks if the parser has encountered an error.
     * @return Returns true if an error has been encountered, false otherwise.
     */
    public function hasError():Boolean {
        return this.hasErrorFlag;
    }

    /**
     * Handles a key-value pair token.
     * @return Returns true if successfully handled, false otherwise.
     */
    private function handleKeyValuePair():Boolean {
        var keyToken:Object = this.tokens[this.position];
        var key:String;

        // 允许 INTEGER 类型的键，将其转换为字符串
        if (keyToken.type == "INTEGER") {
            key = String(keyToken.value);
        } else {
            key = keyToken.value;
        }

        this.position++;

        if (this.debug) {
            trace("Handling key-value pair, Key: " + key);
        }

        // 检查是否有 '='
        if (this.position >= this.tokens.length || this.tokens[this.position].type != "EQUALS") {
            this.error("Expected '=' after key '" + key + "'", keyToken);
            // 跳过到下一个有意义的标记（如 NEWLINE）
            this.skipToNextMeaningfulToken();
            return true; // 继续解析后续内容
        }
        this.position++; // 跳过 '=' 标记

        if (this.position >= this.tokens.length) {
            this.error("Missing value for key '" + key + "'", keyToken);
            return true; // 继续解析后续内容
        }

        var value:Object = this.parseValue();

        // 检查值解析是否出错
        if (value === undefined || this.hasErrorFlag) {
            // 跳过到下一个有意义的标记
            this.skipToNextMeaningfulToken();
            return true; // 继续解析后续内容
        }

        if (this.debug) {
            trace("Parsed key-value pair, Key: " + key + ", Value: " + ObjectUtil.toString(value));
        }

        if (value !== undefined) { // 仅在值成功解析时设置键值对
            if (this.current[key] !== undefined) {
                this.error("Duplicate key '" + key + "'", keyToken);
                // 跳过到下一个有意义的标记
                this.skipToNextMeaningfulToken();
                return true; // 继续解析后续内容
            } else {
                this.current[key] = value;
            }
        }
        return true;
    }


    /**
     * Skips to the next meaningful token (e.g., NEWLINE).
     */
    private function skipToNextMeaningfulToken():Void {
        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];
            if (token.type == "NEWLINE") {
                this.position++;
                break;
            }
            this.position++;
        }
        if (this.position >= this.tokens.length) {
            trace("End of tokens reached while skipping to next meaningful token.");
        }
    }


    /**
     * Parses a value starting from the current position.
     * @return The parsed value object or undefined (if an error occurs).
     */
    private function parseValue():Object {
        var token:Object = this.tokens[this.position];
        if (this.debug) {
            trace("Parsing value, Token Type: " + token.type + ", Value: " + token.value);
        }

        switch(token.type) {
            case "STRING":
                var strValue:String = StringUtils.unescape(token.value); // 解析转义字符
                this.position++;
                return strValue;

            case "MULTILINE_STRING":
                this.position++;
                return token.value;

            case "INTEGER":
                if (token.value == "-") { // 识别负号
                    if (this.position + 1 < this.tokens.length) {
                        var nextToken:Object = this.tokens[this.position + 1];
                        if (nextToken.type == "FLOAT") {
                            var negFloat:Number = -this.parseSpecialFloat(nextToken.value);
                            this.position += 2; // 跳过 '-' 和 FLOAT
                            if (this.debug) {
                                trace("Parsed negative float value: " + negFloat);
                            }
                            return negFloat;
                        } else if (nextToken.type == "INTEGER") {
                            var negInt:Number = -Number(nextToken.value);
                            this.position += 2; // 跳过 '-' 和 INTEGER
                            if (this.debug) {
                                trace("Parsed negative integer value: " + negInt);
                            }
                            return negInt;
                        }
                    }
                    // 如果没有下一个标记或下一个标记不是数字
                    this.error("Invalid minus usage", token);
                    return undefined;
                }

                // 检查是否为浮点数（INTEGER DOT INTEGER）
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
                        trace("Parsed float value: " + floatVal);
                    }

                    return floatVal;
                }

                // 处理独立的 INTEGER
                var intVal:Number = Number(token.value);
                this.position++;
                if (isNaN(intVal)) {
                    this.error("Invalid integer value: " + token.value, token);
                    return undefined;
                }
                if (this.debug) {
                    trace("Parsed integer value: " + intVal);
                }
                return intVal;

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

        // 如果没有匹配的情况
        this.error("Invalid value type: " + token.type, token);

        if (this.position >= this.tokens.length) {
            this.error("Unexpected end of input while parsing value", token);
            return undefined;
        }
        return undefined;
    }



    /**
     * Parses special floating point numbers (NaN, Infinity, -Infinity).
     * @param value The string representation.
     * @return The corresponding AS2 number.
     */
    private function parseSpecialFloat(value:String):Object {
        if (this.debug) {
            trace("Parsing special float value: " + value);
        }
        switch(value.toLowerCase()) {
            case "nan":
                return Number.NaN;
            case "inf":
                return Number.POSITIVE_INFINITY;
            case "-inf":
                return Number.NEGATIVE_INFINITY;
            default:
                var num:Number = Number(value);
                if (isNaN(num)) {
                    this.error("Invalid float value: " + value, {line: 0, column: 0});
                    return undefined;
                }
                return num;
        }
    }


    /**
     * Parses a datetime string and returns it in ISO8601 format.
     * @param dateTimeStr The datetime string.
     * @return The formatted ISO8601 datetime string or null (if parsing fails).
     */
    private function parseDateTime(dateTimeStr:String):String {
        if (this.debug) {
            trace("Parsing datetime string: " + dateTimeStr);
        }
        // 使用 FNTLLexer 的 dateTimeRegExp
        var regex:RegExp = FNTLLexer.dateTimeRegExp;
        if (!regex.test(dateTimeStr)) {
            this.error("Invalid datetime format: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        // 使用 exec 提取组件
        var components:Array = regex.exec(dateTimeStr);
        if (components == null || components.length < 7) { // 确保所有必要的捕获组都存在
            this.error("Invalid datetime format: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        // 根据正则表达式的捕获组调整索引
        var year:Number = Number(components[1]);
        var month:Number = Number(components[2]);
        var day:Number = Number(components[3]);
        var hour:Number = Number(components[4]);
        var minute:Number = Number(components[5]);
        var second:Number = Number(components[6]);

        // 验证组件范围
        if (month < 1 || month > 12) {
            this.error("Invalid month in datetime: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        if (day < 1 || day > 31) { // 可以根据月份进一步细化天数验证
            this.error("Invalid day in datetime: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        // 根据月份调整天数的最大值
        var maxDay:Number = 31;
        if (month == 4 || month == 6 || month == 9 || month == 11) {
            maxDay = 30;
        } else if (month == 2) {
            // 简单的闰年判断
            if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) {
                maxDay = 29;
            } else {
                maxDay = 28;
            }
        }

        if (day > maxDay) {
            this.error("Invalid day in datetime: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        if (hour < 0 || hour > 23) {
            this.error("Invalid hour in datetime: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        if (minute < 0 || minute > 59) {
            this.error("Invalid minute in datetime: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        if (second < 0 || second > 59) {
            this.error("Invalid second in datetime: " + dateTimeStr, {line: 0, column: 0});
            return null;
        }

        // 如果需要，可以添加更多验证，如时区格式等

        // 如果所有组件都有效，返回日期时间字符串
        return dateTimeStr;
    }


    /**
     * Parses an array starting from the current position.
     * @return The parsed array or null (if an error occurs).
     */
    private function parseArray():Array {
        if (this.debug) {
            trace("Starting to parse array.");
        }

        var array:Array = new Array();
        this.position++; // Skip '['

        var expectValue:Boolean = true; // 期待值标志

        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];

            // 检查数组结束
            if (token.type == "RBRACKET") {
                this.position++; // Skip ']'
                break;
            }

            if (expectValue) {
                // 期待一个值
                var value:Object = this.parseValue();
                if (value !== undefined) {
                    array.push(value);
                    if (this.debug) {
                        trace("Array element parsed: " + ObjectUtil.toString(value));
                    }
                    expectValue = false; // 解析值后，不再期待值，期待逗号
                } else {
                    this.error("Failed to parse array element", token);
                    return null;
                }
            } else {
                // 期待一个逗号或数组结束符
                if (token.type == "COMMA") {
                    this.position++; // Skip ','
                    expectValue = true; // 下一个应该是值
                } else {
                    this.error("Expected ',' or ']' after array element", token);
                    return null;
                }
            }
        }

        if (expectValue && array.length > 0) {
            this.error("Trailing comma in array", token);
            return null;
        }

        return array;
    }



    /**
     * Parses an inline table starting from the current position.
     * @return The parsed inline table object or undefined (if an error occurs).
     */
    private function parseInlineTable():Object {
        if (this.debug) {
            trace("Starting to parse inline table.");
        }

        var table:Object = new Object();
        this.position++; // Skip '{'

        var expectKey:Boolean = true;

        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];

            // 检查表结束
            if (token.type == "RBRACE") {
                this.position++; // Skip '}'
                break;
            }

            if (expectKey) {
                // 期待一个键
                if (token.type == "KEY" || token.type == "INTEGER") { // 允许整数作为键
                    var key:String = String(token.value);
                    this.position++;

                    // 检查是否有 '='
                    if (this.position >= this.tokens.length || this.tokens[this.position].type != "EQUALS") {
                        this.error("Expected '=' after key '" + key + "'", token);
                        return undefined;
                    }
                    this.position++; // Skip '='

                    // 解析值
                    var value:Object = this.parseValue();
                    if (value !== undefined) {
                        if (table[key] !== undefined) {
                            this.error("Duplicate key '" + key + "' in inline table", token);
                            return undefined;
                        }
                        table[key] = value;
                        if (this.debug) {
                            trace("Inline table key-value pair: " + key + " = " + ObjectUtil.toString(value));
                        }
                    } else {
                        this.error("Failed to parse value for key '" + key + "' in inline table", token);
                        return undefined;
                    }

                    expectKey = false; // 解析完值后，期待逗号
                } else {
                    this.error("Expected a key or integer in inline table", token);
                    return undefined;
                }
            } else {
                // 期待一个逗号或表结束符
                if (token.type == "COMMA") {
                    this.position++; // Skip ','
                    expectKey = true; // 下一个应该是键
                } else {
                    this.error("Expected ',' or '}' after inline table entry", token);
                    return undefined;
                }
            }
        }

        if (expectKey && ObjectUtil.size(table) > 0) {
            this.error("Trailing comma in inline table", token);
            return undefined;
        }

        return table;
    }



    /**
     * Handles table header tokens, updating the current context.
     * Supports nested table paths, correctly navigating through arrays and objects.
     * @param tableName The name of the table.
     */
    private function handleTableHeader(tableName:String):Void {
        if (this.debug) {
            trace("Handling table header: " + tableName);
        }
        var path:Array = tableName.split(".");
        var current:Object = this.root;

        for (var i:Number = 0; i < path.length; i++) {
            var part:String = path[i];

            // If current is an array, reference the last element
            if (current instanceof Array) {
                if (current.length == 0) {
                    // Push a new table into the array
                    var newObj:Object = new Object();
                    current.push(newObj);
                    current = newObj;
                    if (this.debug) {
                        trace("Added new table to array.");
                    }
                } else {
                    current = current[current.length - 1];
                    if (this.debug) {
                        trace("Referencing last table in array.");
                    }
                }
            }

            // Ensure the current path segment is an object
            if (current[part] == undefined || current[part] == null) {
                current[part] = new Object();
                if (this.debug) {
                    trace("Created new table: " + part);
                }
            } else if (!(current[part] instanceof Object)) {
                this.error("Key conflict: Cannot convert non-table type to table '" + part + "'", {line: 0, column: 0});
                return;
            }
            current = current[part];
        }
        this.current = current;
        if (this.debug) {
            trace("Current context updated to: " + tableName);
        }
    }

    /**
    * Handles table array tokens by adding new tables to the array.
    * Correctly navigates through paths that include arrays and objects.
    * @param arrayName The name of the table array.
    */
    private function handleTableArray(arrayName:String):Void {
        if (this.debug) {
            trace("Handling table array: " + arrayName);
        }
        var path:Array = arrayName.split(".");
        var current:Object = this.root;

        for (var i:Number = 0; i < path.length; i++) {
            var part:String = path[i];
            if (i < path.length - 1) {
                if (current[part] instanceof Array) {
                    if (current[part].length == 0) {
                        var newObj:Object = new Object();
                        current[part].push(newObj);
                        current = newObj;
                        if (this.debug) {
                            trace("Added new table to array '" + part + "'.");
                        }
                    } else {
                        current = current[part][current[part].length - 1];
                        if (this.debug) {
                            trace("Referencing last table in array '" + part + "'.");
                        }
                    }
                } else if (current[part] instanceof Object) {
                    current = current[part];
                } else {
                    current[part] = new Object();
                    current = current[part];
                    if (this.debug) {
                        trace("Created new table: " + part);
                    }
                }
            } else {
                if (!(current[part] instanceof Array)) {
                    current[part] = new Array();
                    if (this.debug) {
                        trace("Created new table array: " + part);
                    }
                }
                var newTable:Object = new Object();
                current[part].push(newTable);
                if (this.debug) {
                    trace("Added new table to table array '" + part + "'.");
                }
                current = newTable;
            }
        }
        this.current = current;
        if (this.debug) {
            trace("Current context updated to: " + arrayName);
        }
    }

    /**
     * Handles inline table tokens by parsing and merging them into the current context.
     * @param inlineTableStr The inline table string.
     */
    private function handleInlineTable(inlineTableStr:String):Void {
        if (this.debug) {
            trace("Handling inline table: " + inlineTableStr);
        }
        var inlineTable:Object = this.parseInlineTable();
        if (inlineTable === undefined) {
            if (this.debug) {
                trace("Failed to parse inline table: " + inlineTableStr);
            }
            return;
        }
        for (var key:String in inlineTable) {
            if (this.current[key] !== undefined) {
                this.error("Duplicate key '" + key + "'", {line: 0, column: 0});
            } else {
                this.current[key] = inlineTable[key];
                if (this.debug) {
                    trace("Added inline table key-value pair to current context: " + key + " = " + ObjectUtil.toString(inlineTable[key]));
                }
            }
        }
    }

    /**
     * Handles parsing errors by setting the error flag and logging the error message.
     * @param message The error message.
     * @param token The relevant token object for error location.
     */
    private function error(message:String, token:Object):Void {
        var lineInfo:String = "Line: " + (token.line != undefined ? token.line : "?") + ", Column: " + (token.column != undefined ? token.column : "?");
        trace("Error: " + message + " at " + lineInfo);
        this.hasErrorFlag = true;
        if (this.debug) {
            trace("Current parsing position: " + this.position + "/" + this.tokens.length);
        }
    }
}
