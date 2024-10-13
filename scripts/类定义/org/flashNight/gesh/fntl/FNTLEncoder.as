import org.flashNight.gesh.object.*;
import org.flashNight.gesh.string.*;
import org.flashNight.gesh.fntl.*;
import org.flashNight.naki.Sort.QuickSort;
import org.flashNight.gesh.regexp.RegExp;
/**
 * FNTLEncoder class upgraded to support FNTL (FlashNight Text Language).
 * Enhancements include:
 * - Full UTF-8 support for keys and values
 * - Extended escape sequences handling, including \UXXXXXXXX
 * - Enhanced date-time encoding with fractional seconds and time zone support
 * - Optimized key sorting using custom QuickSort (adaptiveSort)
 * - Caching for table headers and table array headers
 * - Improved error handling with localized messages
 * - Logging warnings for internal keys
 */

class org.flashNight.gesh.fntl.FNTLEncoder {
    
    private var MAX_RECURSION_DEPTH:Number = 256; // 递归深度限制
    private var tableHeaderCache:Object = {};      // 缓存表格头
    private var tableArrayHeaderCache:Object = {}; // 缓存表格数组头

    // 构造函数
    public function FNTLEncoder() {
        // 无需初始化缩进级别
    }

    /**
     * 编码 AS2 对象为 TOML/FNTL 格式字符串
     * @param obj 要编码的对象
     * @param pretty 是否进行美化输出
     * @return TOML/FNTL 格式的字符串
     */
    public function encode(obj:Object, pretty:Boolean):String {
        var result:Array = []; // 使用数组来高效拼接字符串
        var stack:Array = []; // 堆栈用于迭代处理
        var currentPath:Array = []; // 跟踪当前表格路径

        // 初始化堆栈，包含顶层对象和路径
        stack.push({ object: obj, path: currentPath, depth: 0, isArrayElement: false });

        while (stack.length > 0) {
            var state:Object = stack.pop();
            var currentObject:Object = state.object;
            var path:Array = state.path;
            var depth:Number = state.depth;
            var isArrayElement:Boolean = state.isArrayElement || false;

            if (depth > this.MAX_RECURSION_DEPTH) {
                throw new Error("递归深度超过限制 (" + this.MAX_RECURSION_DEPTH + ")，路径: " + path.join("."));
            }

            // 输出表格头
            if (isArrayElement) {
                var tableArrayHeader:String = this.buildTableArrayHeader(path);
                result.push(tableArrayHeader);
            } else if (path.length > 0) {
                var tableHeader:String = this.buildTableHeader(path);
                result.push(tableHeader);
            }

            // 获取并排序键
            var keys:Array = this.getKeys(currentObject);
            keys = QuickSort.adaptiveSort(keys, this.compareKeys);

            // 处理当前对象的每个键值对
            for (var keyIndex:Number = 0; keyIndex < keys.length; keyIndex++) {
                var key:String = keys[keyIndex];
                var value:Object = currentObject[key];

                if (this.isArray(value)) {
                    var arr = value;
                    if (this.isArrayOfTables(arr)) {
                        // 表格数组处理，逆序添加到堆栈中以保持顺序
                        for (var i:Number = arr.length - 1; i >= 0; i--) {
                            var tableObj:Object = arr[i];
                            var arrayPath:Array = path.concat([key]);
                            stack.push({ object: tableObj, path: arrayPath, depth: depth + 1, isArrayElement: true });
                        }
                    } else {
                        // 普通数组处理
                        var encodedArray:String = this.encodeArray(arr, pretty);
                        result.push(key + " = " + encodedArray);
                    }
                } else if (typeof(value) == "object" && value != null && !(value instanceof Date)) {
                    // 将嵌套对象作为独立表格处理
                    var newPath:Array = path.concat([key]);
                    stack.push({ object: value, path: newPath, depth: depth + 1, isArrayElement: false });
                    continue; // 不在当前表格中编码此键
                } else {
                    // 普通键值对处理，不添加缩进
                    var encodedValue:String = this.encodeValue(value);
                    result.push(key + " = " + encodedValue);
                }
            }
        }

        // 确保输出以换行符结尾
        return result.join("\n") + "\n";
    }

    /**
     * 比较键的函数，用于排序
     * @param a 第一个键
     * @param b 第二个键
     * @return 比较结果
     */
    private function compareKeys(a:String, b:String):Number {
        if (a < b) {
            return -1;
        } else if (a > b) {
            return 1;
        } else {
            return 0;
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
            if (typeof(element) != "object" || element == null || this.isArray(element) || element instanceof Date) {
                return false; // 仅当所有元素都是非 null 的对象且不是 Date 或数组时，才认为是表格数组
            }
        }
        return true;
    }

    /**
     * 构建表格头
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
     * 构建表格数组头
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

    /**
     * 编码数组
     * @param arr 数组
     * @param pretty 是否进行美化输出
     * @return TOML/FNTL 格式的数组字符串
     */
    private function encodeArray(arr:Array, pretty:Boolean):String {
        var result:Array = ["["];
        for (var i:Number = 0; i < arr.length; i++) {
            if (i > 0) {
                result.push(", ");
            }
            var element:Object = arr[i];
            if (typeof(element) == "object" && element != null && !this.isArray(element) && !(element instanceof Date)) {
                // Encode as inline table
                var encodedInline:String = this.encodeInlineTable(element);
                result.push(encodedInline);
            } else {
                var encodedVal:String = this.encodeValue(element);
                result.push(encodedVal);
            }
        }
        result.push("]");
        return result.join("");
    }

    /**
     * 编码内联表格
     * @param table 对象
     * @return TOML/FNTL 格式的内联表格字符串
     */
    private function encodeInlineTable(table:Object):String {
        var result:Array = ["{ "];
        var keys:Array = this.getKeys(table);
        keys = QuickSort.adaptiveSort(keys, this.compareKeys);
        var first:Boolean = true;
        for (var keyIndex:Number = 0; keyIndex < keys.length; keyIndex++) {
            var key:String = keys[keyIndex];
            var value:Object = table[key];
            if (!first) {
                result.push(", ");
            }
            var encodedValue:String = this.encodeValue(value);
            result.push(key + " = " + encodedValue);
            first = false;
        }
        result.push(" }");
        return result.join("");
    }

    /**
     * 编码具体的值：字符串、数字、布尔值等
     * @param value 值
     * @return TOML/FNTL 格式的字符串
     */
    private function encodeValue(value):String {
        if (typeof(value) == "string") {
            // Check if the string is a date-time format
            if (isDateTimeString(value)) {
                return this.encodeDateTimeString(value);
            } else {
                return this.encodeString(String(value));
            }
        } else if (typeof(value) == "number") {
            return this.encodeFloat(value);
        } else if (typeof(value) == "boolean") {
            return value ? "true" : "false";
        } else if (value instanceof Date) {
            return this.encodeDate(value);
        } else if (typeof(value) == "object" && value != null) {
            if (this.isArray(value)) {
                return this.encodeArray(value, false);
            } else {
                // For nested objects, handled separately
                return "";
            }
        } else {
            return value != null ? String(value) : "null";
        }
    }

    /**
     * 判断字符串是否为日期时间格式
     * @param value 字符串
     * @return 是否为日期时间格式
     */
    private function isDateTimeString(value:String):Boolean {
        var dateTimeRegExp:RegExp = new RegExp("^\\d{4}-\\d{2}-\\d{2}[Tt ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?([Zz]|[+-]\\d{2}:\\d{2})?$");
        return dateTimeRegExp.test(value);
    }

    /**
     * 编码日期时间字符串，返回不带引号的字符串
     * @param value 字符串
     * @return TOML/FNTL 格式的日期时间字符串
     */
    private function encodeDateTimeString(value:String):String {
        // Validate date-time string
        var dateTimeRegExp:RegExp = new RegExp("^\\d{4}-\\d{2}-\\d{2}[Tt ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?([Zz]|[+-]\\d{2}:\\d{2})?$");
        if (dateTimeRegExp.test(value)) {
            return value;
        } else {
            // Not a valid date-time string, treat as regular string
            return this.encodeString(value);
        }
    }

    /**
     * 编码浮点数，处理特殊数值
     * @param value 浮点数值
     * @return TOML/FNTL 格式的浮点数字符串
     */
    private function encodeFloat(value:Number):String {
        if (isNaN(value)) {
            return "nan";
        } else if (value == Infinity) {
            return "inf";
        } else if (value == -Infinity) {
            return "-inf";
        } else {
            return String(value);
        }
    }

    /**
     * 编码字符串，处理多行字符串和转义字符
     * @param value 字符串
     * @return TOML/FNTL 格式的字符串
     */
    private function encodeString(value:String):String {
        if (value.indexOf("\n") != -1 || value.indexOf("\r") != -1) {
            // 使用多行字符串
            // 处理字符串中的特殊字符，如连续的三个引号
            var escapedValue:String = value.split('"""').join('\\"""');
            return '"""' + escapedValue + '"""';
        } else {
            // 单行字符串，处理必要的转义
            var result:String = "";
            for (var i:Number = 0; i < value.length; i++) {
                var c:String = value.charAt(i);
                var code:Number = value.charCodeAt(i);
                if (c == "\\" || c == "\"") {
                    result += "\\" + c;
                } else if (code >= 0x0000 && code <= 0x001F) {
                    // 控制字符需要转义
                    switch (code) {
                        case 0x08: result += "\\b"; break;
                        case 0x09: result += "\\t"; break;
                        case 0x0A: result += "\\n"; break;
                        case 0x0C: result += "\\f"; break;
                        case 0x0D: result += "\\r"; break;
                        default:
                            var hex:String = code.toString(16).toUpperCase();
                            while (hex.length < 4) {
                                hex = "0" + hex;
                            }
                            result += "\\u" + hex;
                            break;
                    }
                } else if (code > 0xFFFF) {
                    // 处理基本多文种平面（BMP）之外的字符，使用 \UXXXXXXXX
                    var highSurrogate:Number = ((code - 0x10000) >> 10) + 0xD800;
                    var lowSurrogate:Number = ((code - 0x10000) % 0x400) + 0xDC00;
                    var highHex:String = highSurrogate.toString(16).toUpperCase();
                    var lowHex:String = lowSurrogate.toString(16).toUpperCase();
                    result += "\\U" + this.padZeroExtended(highHex, 8) + "\\U" + this.padZeroExtended(lowHex, 8);
                } else {
                    result += c;
                }
            }
            return '"' + result + '"';
        }
    }

    /**
     * 辅助函数：在16进制字符串前添加前导零以达到指定长度
     * @param hex 16进制字符串
     * @param length 目标长度
     * @return 前导零填充后的16进制字符串
     */
    private function padZeroExtended(hex:String, length:Number):String {
        while (hex.length < length) {
            hex = "0" + hex;
        }
        return hex;
    }

    /**
     * 编码日期时间
     * 支持:
     * - ISO8601格式
     * - 时区偏移（+/-HH:MM）
     * - 分数秒
     * @param date Date 对象
     * @return TOML/FNTL 格式的日期时间字符串
     */
    private function encodeDate(date:Object):String {
        var year:String = String(date.getFullYear());
        var month:String = this.padZero(date.getMonth() + 1);
        var day:String = this.padZero(date.getDate());
        var hours:String = this.padZero(date.getHours());
        var minutes:String = this.padZero(date.getMinutes());
        var seconds:String = this.padZero(date.getSeconds());
        
        // 处理分数秒
        var milliseconds:Number = date.getMilliseconds();
        var fractional:String = milliseconds > 0 ? "." + this.padZeroFraction(milliseconds) : "";
        
        // 获取时区信息（假设为本地时区，转换为 ISO8601 格式）
        var timezoneOffset:Number = -date.getTimezoneOffset(); // 分钟为单位
        var tzSign:String = timezoneOffset >= 0 ? "+" : "-";
        var tzHours:Number = Math.floor(Math.abs(timezoneOffset) / 60);
        var tzMinutes:Number = Math.abs(timezoneOffset) % 60;
        var timezoneSuffix:String = tzSign + this.padZero(tzHours) + ":" + this.padZero(tzMinutes);
        
        return year + "-" + month + "-" + day + "T" + hours + ":" + minutes + ":" + seconds + fractional + timezoneSuffix;
    }

    /**
     * 辅助函数：在小于10的数值前添加前导零
     * @param value 数值
     * @return 格式化后的字符串
     */
    private function padZero(value:Number):String {
        return value < 10 ? "0" + value : String(value);
    }

    /**
     * 辅助函数：在分数秒前添加前导零以确保三位数
     * @param milliseconds 数值
     * @return 格式化后的分数秒字符串
     */
    private function padZeroFraction(milliseconds:Number):String {
        var fraction:String = String(milliseconds);
        while (fraction.length < 3) {
            fraction = "0" + fraction;
        }
        return fraction;
    }

    /**
     * 获取对象的所有键，忽略内部键（如 __dictUID）
     * 并记录对内部键的警告
     * @param obj 对象
     * @return 键数组
     */
    private function getKeys(obj:Object):Array {
        var keys:Array = [];
        for (var key:String in obj) {
            if (!this.isInternalKey(key)) {
                keys.push(key);
            } else {
                trace("警告: 忽略内部键: " + key);
            }
        }
        return keys;
    }

    /**
     * 判断是否为内部键（如 __dictUID）
     * @param key 键名
     * @return 是否为内部键
     */
    private function isInternalKey(key:String):Boolean {
        return key.substr(0, 2) == "__";
    }

    /**
     * 编码键数组，使用自定义 QuickSort 的 adaptiveSort 方法
     * 已在 encode 和 encodeInlineTable 方法中使用
     */
    // 移除了内部 quickSort 方法，因为我们使用外部的 QuickSort 类

    /**
     * 编码内联表格字符串为对象
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
            this.error("内联表格解析失败: " + tableStr, {line: 0, column: 0});
            return undefined;
        }
        return parsedTable;
    }

    /**
     * 处理解析错误，通过设置错误标志并记录错误信息。
     * @param message 错误消息。
     * @param token 相关的 Token 对象，用于定位错误位置。
     */
    private function error(message:String, token:Object):Void {
        var lineInfo:String = "行: " + (token.line != undefined ? token.line : "?") + ", 列: " + (token.column != undefined ? token.column : "?");
        trace("错误: " + message + " 在 " + lineInfo);
        // 可以根据需要抛出异常或记录错误标志
    }

    /**
     * 获取对象的所有键，支持忽略内部键
     * @param obj 对象
     * @return 键数组
     */
    private function getSortedKeys(obj:Object):Array {
        var keys:Array = this.getKeys(obj);
        return QuickSort.adaptiveSort(keys, this.compareKeys);
    }
}
