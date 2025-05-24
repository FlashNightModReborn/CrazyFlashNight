import org.flashNight.gesh.object.*;
import org.flashNight.gesh.string.*;
class org.flashNight.gesh.toml.TOMLParser {
    private var tokens:Array;        // 词法分析器生成的标记列表
    private var position:Number;     // 当前标记位置
    private var current:Object;      // 当前正在处理的对象
    private var root:Object;         // 最终解析后的结果对象
    private var hasErrorFlag:Boolean; // 错误标志
    private var text:String;         // 原始 TOML 文本

    // 修改构造函数，接收 TOML 文本作为输入
    public function TOMLParser(tokens:Array, text:String) {
        this.tokens = tokens;
        this.position = 0;
        this.root = {};
        this.current = this.root;
        this.hasErrorFlag = false;
        this.text = text;  // 保存原始 TOML 文本
    }

    public function parse():Object {
        // trace("TOMLParser.parse: 开始解析");
        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];
            // trace("TOMLParser.parse: 处理 token " + this.position + ": " + token.type + " => " + token.value);

            switch (token.type) {
                case "KEY":
                    this.handleKey(token);
                    break;
                case "TABLE_HEADER":
                    this.handleTableHeader(token.value);
                    this.position++;
                    break;
                case "TABLE_ARRAY":
                    this.handleTableArray(token.value);
                    this.position++;
                    break;
                default:
                    this.error("未处理的 token 类型: " + token.type, "");
                    this.position++;
                    break;
            }

            if (this.hasErrorFlag) {
                // trace("TOMLParser.parse: 解析过程中遇到错误，停止解析");
                break; // 停止解析
            }
        }
        // trace("TOMLParser.parse: 解析完成");
        return this.root;
    }


    public function hasError():Boolean {
        return this.hasErrorFlag;
    }

    private function handleKey(token:Object):Void {
        var key:String = token.value;
        // trace("TOMLParser.handleKey: 处理键: " + key);

        var nextPos:Number = this.position + 1;
        if (nextPos >= this.tokens.length || this.tokens[nextPos].type != "EQUALS") {
            this.error("期望 EQUALS 标记", key);
            return;
        }

        var valuePos:Number = nextPos + 1;
        if (valuePos >= this.tokens.length) {
            this.error("值缺失", key);
            return;
        }

        var valueToken:Object = this.tokens[valuePos];
        var value:Object = this.parseValue(valueToken);
        // trace("TOMLParser.handleKey: 解析键 '" + key + "' 的值: " + ObjectUtil.toString(value));

        // 允许 null 值，不再将其视为错误
        this.current[key] = value;

        // 更新位置到值标记之后
        this.position = valuePos + 1;
    }

    private function parseValue(token:Object):Object {
        // trace("TOMLParser.parseValue: 解析值 - 类型: " + token.type + ", 值: " + token.value);
        switch (token.type) {
            case "STRING":
                return token.value;
            case "INTEGER":
                return Number(token.value);
            case "FLOAT":
                return this.parseSpecialFloat(token.value);
            case "BOOLEAN":
                return token.value == true;
            case "DATETIME":
                var isoDateStr:String = this.parseDateTime(token.value);
                return isoDateStr; // 返回格式化后的日期时间字符串
            case "ARRAY":
                return this.parseArray(token.value);
            case "INLINE_TABLE":
                return this.parseInlineTable(token.value);
            case "NULL":
                return null;
            default:
                this.error("未知的值类型: " + token.type, "");
                return null;
        }
    }


    // 添加 parseDateTime 方法
    private function parseDateTime(dateTimeStr:String):String {
        // 检查并移除结尾的 'Z'（表示 UTC 时间）
        var hasZ:Boolean = (dateTimeStr.charAt(dateTimeStr.length - 1) == "Z");
        if (hasZ) {
            dateTimeStr = dateTimeStr.substring(0, dateTimeStr.length - 1);
        }

        // 查找分隔符 'T' 或空格 ' '
        var separatorPos:Number = dateTimeStr.indexOf("T");
        if (separatorPos == -1) {
            separatorPos = dateTimeStr.indexOf(" ");
        }

        var datePart:String;
        var timePart:String;

        if (separatorPos == -1) {
            // 如果没有找到分隔符，则假设只有日期部分
            datePart = dateTimeStr;
            timePart = "00:00:00"; // 默认时间为午夜
        } else {
            // 分割日期和时间部分
            datePart = dateTimeStr.substring(0, separatorPos);
            timePart = dateTimeStr.substring(separatorPos + 1);
        }

        // 解析日期部分
        var dateComponents:Array = datePart.split("-");
        if (dateComponents.length != 3) {
            this.error("无效的日期格式: " + datePart);
            return null;
        }
        var year:Number = Number(dateComponents[0]);
        var month:Number = Number(dateComponents[1]) - 1; // AS2 中月份从 0 开始
        var day:Number = Number(dateComponents[2]);

        // 解析时间部分
        var timeComponents:Array = timePart.split(":");
        if (timeComponents.length < 2) {
            this.error("无效的时间格式: " + timePart);
            return null;
        }
        var hours:Number = Number(timeComponents[0]);
        var minutes:Number = Number(timeComponents[1]);
        var seconds:Number = 0;
        if (timeComponents.length >= 3) {
            seconds = Number(timeComponents[2]);
        }

        var dateObj:Date;
        if (hasZ) {
            // 使用 Date.UTC 创建 UTC 时间
            var utcTime:Number = Date.UTC(year, month, day, hours, minutes, seconds);
            dateObj = new Date(utcTime);
        } else {
            // 创建本地时间
            dateObj = new Date(year, month, day, hours, minutes, seconds);
        }

        // 格式化为 ISO8601 字符串
        var isoStr:String = this.formatDateToISO8601(dateObj, hasZ);
        return isoStr;
    }

    // 修改 formatDateToISO8601 方法，支持 UTC 和本地时间
    private function formatDateToISO8601(dateObj:Date, isUTC:Boolean):String {
        var year:String = String(isUTC ? dateObj.getUTCFullYear() : dateObj.getFullYear());
        var month:String = this.padZero(isUTC ? dateObj.getUTCMonth() + 1 : dateObj.getMonth() + 1);
        var day:String = this.padZero(isUTC ? dateObj.getUTCDate() : dateObj.getDate());
        var hours:String = this.padZero(isUTC ? dateObj.getUTCHours() : dateObj.getHours());
        var minutes:String = this.padZero(isUTC ? dateObj.getUTCMinutes() : dateObj.getMinutes());
        var seconds:String = this.padZero(isUTC ? dateObj.getUTCSeconds() : dateObj.getSeconds());
        var timezoneSuffix:String = isUTC ? "Z" : "";
        return year + "-" + month + "-" + day + "T" + hours + ":" + minutes + ":" + seconds + timezoneSuffix;
    }


    private function padZero(value:Number):String {
        return value < 10 ? "0" + value : String(value);
    }

    /**
     * 解析特殊浮点数值
     * @param value 字符串形式的浮点数值
     * @return AS2 中的数值类型（NaN, Infinity, -Infinity）
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


    private function parseArray(arrayData:Array):Array {
        // trace("TOMLParser.parseArray: 解析数组");
        var array:Array = [];
        var elementType:String = null;

        for (var i:Number = 0; i < arrayData.length; i++) {
            var token:Object = arrayData[i];
            var value:Object = this.parseValue(token);

            // 确定数组元素的类型
            if (elementType == null && value != null) {
                elementType = typeof(value);
            } else if (value != null && typeof(value) != elementType) {
                this.error("数组元素类型不一致，预期: " + elementType + "，实际: " + typeof(value));
                return null;
            }

            array.push(value);
        }

        return array;
    }


    private function skipWhitespaceAndComments():Void {
        while (this.position < this.tokens.length) {
            var token:Object = this.tokens[this.position];
            if (token.type == "WHITESPACE" || token.type == "COMMENT") {
                this.position++;
            } else {
                break;
            }
        }
    }



    private function parseInlineTable(tableStr:String):Object {
        // trace("TOMLParser.parseInlineTable: 解析内联表格");
        var table:Object = {};

        if (tableStr.charAt(0) == "{" && tableStr.charAt(tableStr.length - 1) == "}") {
            tableStr = tableStr.substring(1, tableStr.length - 1);
        }

        var pairs:Array = tableStr.split(",");
        for (var i:Number = 0; i < pairs.length; i++) {
            var pairStr:String = org.flashNight.gesh.string.StringUtils.trim(pairs[i]);
            // trace("TOMLParser.parseInlineTable: 解析键值对 " + i + ": " + pairStr);
            if (pairStr.length == 0) continue;

            var eqIndex:Number = pairStr.indexOf("=");
            if (eqIndex == -1) {
                this.error("内联表格中的键值对缺少 '=': " + pairs[i], "");
                continue;
            }
            var key:String = org.flashNight.gesh.string.StringUtils.trim(pairStr.substring(0, eqIndex));
            var valueStr:String = org.flashNight.gesh.string.StringUtils.trim(pairStr.substring(eqIndex + 1));

            if (key.length == 0) {
                this.error("内联表格中的键为空: " + pairs[i], "");
                continue;
            }

            var value:Object;
            if (valueStr.charAt(0) == "\"" || valueStr.charAt(0) == "'") {
                value = this.stripQuotes(valueStr);
            } else if (valueStr == "true" || valueStr == "false") {
                value = valueStr == "true";
            } else if (valueStr == "nan") {
                value = NaN;
            } else if (valueStr == "inf") {
                value = Infinity;
            } else if (valueStr == "-inf") {
                value = -Infinity;
            } else if (!isNaN(Number(valueStr))) {
                value = Number(valueStr);
            } else {
                value = valueStr;
            }

            // trace("TOMLParser.parseInlineTable: 解析结果 - " + key + " = " + value);
            table[key] = value;
        }
        return table;
    }

    private function handleTableHeader(tableName:String):Void {
        // trace("TOMLParser.handleTableHeader: 处理表格头 - " + tableName);
        var path:Array = tableName.split(".");
        var current:Object = this.root;
        for (var i:Number = 0; i < path.length; i++) {
            var part:String = path[i];
            if (current[part] == undefined || current[part] == null) {
                current[part] = {};
                // trace("TOMLParser.handleTableHeader: 创建嵌套表格 - " + part);
            } else if (!(current[part] instanceof Object)) {
                this.error("键名冲突，无法将非表格类型转换为表格：" + part);
                return;
            }
            current = current[part];
        }
        this.current = current;
    }


    // 修改 handleTableArray 方法
    private function handleTableArray(arrayName:String):Void {
        // trace("TOMLParser.handleTableArray: 处理表格数组 - " + arrayName);
        var path:Array = arrayName.split(".");
        var current:Object = this.root;
        for (var i:Number = 0; i < path.length; i++) {
            var part:String = path[i];
            if (i == path.length - 1) {
                if (!(current[part] instanceof Array)) {
                    current[part] = [];
                    // trace("TOMLParser.handleTableArray: 创建表格数组 - " + part);
                }
                var newTable:Object = {};
                current[part].push(newTable);
                // trace("TOMLParser.handleTableArray: 添加新表格到数组 - " + part);
                current = newTable;
            } else {
                if (current[part] == undefined || current[part] == null) {
                    current[part] = {};
                } else if (current[part] instanceof Array) {
                    current = current[part][current[part].length - 1];
                } else {
                    current = current[part];
                }
            }
        }
        this.current = current;
    }

    private function stripQuotes(str:String):String {
        if ((str.charAt(0) == "\"" && str.charAt(str.length - 1) == "\"") ||
            (str.charAt(0) == "'" && str.charAt(str.length - 1) == "'")) {
            return str.substring(1, str.length - 1);
        }
        return str;
    }

    private function removeLineBreaks(str:String):String {
        // trace("TOMLParser.removeLineBreaks: 移除换行符");
        // 确保 str 是字符串
        if (typeof(str) != "string") {
            str = String(str);
        }
        var result:String = "";
        for (var i:Number = 0; i < str.length; i++) {
            var c:String = str.charAt(i);
            if (c != "\n" && c != "\r") {
                result += c;
            }
        }
        // trace("TOMLParser.removeLineBreaks: 结果 - " + result);
        return result;
    }

    private function error(message:String):Void {
        var lineInfo:String = "行: " + this.getLineNumber() + ", 列: " + this.getColumnNumber();
        // trace("Error: " + message + " 在 " + lineInfo);
    }

    // 添加获取行号和列号的方法
    private function getLineNumber():Number {
        // 计算当前字符位置对应的行号
        var lines:Array = this.text.substring(0, this.position).split("\n");
        return lines.length;
    }

    private function getColumnNumber():Number {
        // 计算当前字符位置对应的列号
        var lines:Array = this.text.substring(0, this.position).split("\n");
        var lastLine:String = lines[lines.length - 1];
        return lastLine.length + 1;
    }
}
