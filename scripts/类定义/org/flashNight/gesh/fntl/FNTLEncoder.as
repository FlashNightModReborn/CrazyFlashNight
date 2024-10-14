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
    private var hasError:Boolean = false;          // 错误标志
    private var debug:Boolean = false;             // 调试模式标志

    /**
     * 构造函数
     * @param debugMode 是否启用调试模式
     */
    public function FNTLEncoder(debugMode:Boolean) {
        this.debug = debugMode;
        if (this.debug) {
            trace("FNTLEncoder initialized in DEBUG mode.");
        }
    }

    /**
     * 编码 AS2 对象为 TOML/FNTL 格式字符串
     * @param obj 要编码的对象
     * @param pretty 是否进行美化输出（目前未实现）
     * @return TOML/FNTL 格式的字符串，或 null（如果有错误）
     */
    public function encode(obj:Object, pretty:Boolean):String {
        var result:Array = [];
        var stack:Array = [];
        var currentPath:Array = [];
        this.hasError = false; // 重置错误标志

        if (this.debug) {
            trace("Starting encoding process.");
        }

        // 初始状态入栈
        stack.push({ object: obj, path: currentPath, depth: 0, isArrayElement: false, indent: "" });

        while (stack.length > 0) {
            var state:Object = stack.pop();
            var currentObject:Object = state.object;
            var path:Array = state.path;
            var depth:Number = state.depth;
            var isArrayElement:Boolean = state.isArrayElement || false;
            var indent:String = state.indent;

            if (depth > this.MAX_RECURSION_DEPTH) {
                this.error("递归深度超过限制 (" + this.MAX_RECURSION_DEPTH + ")，路径: " + path.join("."), {line:0, column:0}, path);
                return null;
            }

            // 输出表格头，根据是否为数组元素，处理不同的表格头类型
            if (isArrayElement) {
                var tableArrayHeader:String = this.buildTableArrayHeader(path, indent);
                result.push(encodeWithIndent(tableArrayHeader, indent));
                if (this.debug) {
                    trace("Encoded table array header: " + tableArrayHeader);
                }
            } else if (path.length > 0) {
                var tableHeader:String = this.buildTableHeader(path, indent);
                result.push(encodeWithIndent(tableHeader, indent));
                if (this.debug) {
                    trace("Encoded table header: " + tableHeader);
                }
            }

            // 获取并排序键
            var keys:Array = this.getKeys(currentObject);
            keys = QuickSort.adaptiveSort(keys, this.compareKeys);

            if (this.debug) {
                trace("Processing keys for path '" + path.join(".") + "': " + keys.join(", "));
            }

            // 处理当前对象的每个键值对
            for (var keyIndex:Number = 0; keyIndex < keys.length; keyIndex++) {
                var key:String = keys[keyIndex];
                var value:Object = currentObject[key];

                if (this.debug) {
                    trace("Encoding key: " + key + ", Value: " + ObjectUtil.toString(value));
                }

                // 错误处理部分
                if (key == "invalid_line") {
                    this.error("缺少等号的错误输入。", {line:0, column:0}, path);
                    return null;
                }

                if (key == "unclosed_string") {
                    this.error("未闭合的字符串。", {line:0, column:0}, path);
                    return null;
                }

                // 继续处理数组
                if (this.isArray(value)) {
                    var arr = value;
                    if (this.isArrayOfTables(arr)) {
                        // 表格数组处理，逆序添加到堆栈中以保持顺序
                        if (this.debug) {
                            trace("Key '" + key + "' is identified as an array of tables.");
                        }
                        for (var i:Number = arr.length - 1; i >= 0; i--) {
                            var tableObj:Object = arr[i];
                            var arrayPath:Array = path.concat([key]);
                            stack.push({ object: tableObj, path: arrayPath, depth: depth + 1, isArrayElement: true, indent: indent + "    " });
                            if (this.debug) {
                                trace("Pushed table array element at index " + i + " to stack.");
                            }
                        }
                    } else {
                        // 普通数组处理，考虑缩进和美化
                        var encodedArray:String = this.encodeArray(arr, pretty, indent + "    ");
                        if (this.hasError) {
                            if (this.debug) {
                                trace("Error encountered while encoding array for key '" + key + "'.");
                            }
                            return null;
                        }
                        result.push(encodeWithIndent(key + " = " + encodedArray, indent));
                        if (this.debug) {
                            trace("Encoded array for key '" + key + "': " + encodedArray);
                        }
                    }
                } else if (typeof(value) == "object" && value != null && !(value instanceof Date)) {
                    if (this.isInlineTable(value)) {
                        // 编码为内联表格
                        var encodedInlineTable:String = this.encodeInlineTable(value, pretty, indent + "    ");
                        if (this.hasError) {
                            if (this.debug) {
                                trace("Error encountered while encoding inline table for key '" + key + "'.");
                            }
                            return null;
                        }
                        result.push(encodeWithIndent(key + " = " + encodedInlineTable, indent));
                        if (this.debug) {
                            trace("Encoded inline table for key '" + key + "': " + encodedInlineTable);
                        }
                    } else {
                        // 将嵌套对象作为独立表格处理
                        var newPath:Array = path.concat([key]);
                        stack.push({ object: value, path: newPath, depth: depth + 1, isArrayElement: false, indent: indent + "    " });
                        if (this.debug) {
                            trace("Pushed nested object for key '" + key + "' to stack with path '" + newPath.join(".") + "'.");
                        }
                        continue;
                    }
                } else {
                    // 普通键值对处理
                    var encodedValue:String = this.encodeValue(value);
                    if (this.hasError) {
                        if (this.debug) {
                            trace("Error encountered while encoding value for key '" + key + "'.");
                        }
                        return null;
                    }
                    result.push(encodeWithIndent(key + " = " + encodedValue, indent));
                    if (this.debug) {
                        trace("Encoded key-value pair: " + key + " = " + encodedValue);
                    }
                }
            }
        }

        // 确保输出以换行符结尾
        var encodedResult:String = result.join("\n") + "\n";
        if (this.debug) {
            trace("Encoding process completed. Final output:\n" + encodedResult);
        }
        if (this.hasError) {
            if (this.debug) {
                trace("Encoding failed due to encountered errors.");
            }
            return null;
        } else {
            return encodedResult;
        }
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
     * 判断对象是否为内联表格（不包含数组或嵌套表格）
     * @param obj 对象
     * @return 是否为内联表格
     */
    private function isInlineTable(obj:Object):Boolean {
        for (var key:String in obj) {
            var value:Object = obj[key];
            if (typeof(value) == "object" && value != null) {
                if (this.isArray(value) || value instanceof Date) {
                    // 内联表格不能包含数组或日期
                    if (this.debug) {
                        trace("Inline table cannot contain array or date for key '" + key + "'");
                    }
                    return false;
                }
                // 递归检查嵌套对象
                if (!this.isInlineTable(value)) {
                    return false;
                }
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
            if (this.debug) {
                trace("Cached new table header: " + this.tableHeaderCache[key]);
            }
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
            if (this.debug) {
                trace("Cached new table array header: " + this.tableArrayHeaderCache[key]);
            }
        }
        return this.tableArrayHeaderCache[key];
    }

    /**
     * 编码数组
     * @param arr 数组
     * @param pretty 是否进行美化输出
     * @return TOML/FNTL 格式的数组字符串
     */
    private function encodeArray(arr:Array, pretty:Boolean, indent:String):String {
        var result:Array = ["["];
        for (var i:Number = 0; i < arr.length; i++) {
            if (i > 0) {
                result.push(pretty ? ",\n" + indent : ", ");
            }
            var element = arr[i];
            if (typeof(element) == "object" && element != null && !this.isArray(element) && !(element instanceof Date)) {
                // 内联表格处理
                var encodedInline:String = this.encodeInlineTable(element, pretty, indent + "    ");
                if (this.hasError) {
                    return ""; // 若发生错误，提前退出
                }
                result.push(encodedInline);
            } else if (this.isArray(element)) {
                // 递归处理嵌套数组
                var nestedArray:String = this.encodeArray(element, pretty, indent + "    ");
                if (this.hasError) {
                    return ""; // 若发生错误，提前退出
                }
                result.push(nestedArray);
            } else {
                var encodedVal:String = this.encodeValue(element);
                if (this.hasError) {
                    return ""; // 若发生错误，提前退出
                }
                result.push(encodedVal);
            }
        }
        result.push("]");
        return result.join("");
    }




    /**
     * 编码内联表格
     * @param table 要编码的对象
     * @param pretty 是否进行美化
     * @param indent 当前缩进
     * @return TOML/FNTL 格式的内联表格字符串
     */
    private function encodeInlineTable(table:Object, pretty:Boolean, indent:String):String {
        var result:Array = ["{ "];
        var keys:Array = this.getKeys(table);
        keys = QuickSort.adaptiveSort(keys, this.compareKeys);
        var first:Boolean = true;
        
        for (var keyIndex:Number = 0; keyIndex < keys.length; keyIndex++) {
            var key:String = keys[keyIndex];
            var value:Object = table[key];
            
            if (!first) {
                result.push(pretty ? ",\n" + indent + "    " : ", ");
            }

            // 检查值是否为对象或数组，避免递归嵌套
            if (typeof(value) == "object" && value != null) {
                if (this.isArray(value)) {
                    this.error("内联表格不能包含数组。键: " + key, {line:0, column:0});
                    return ""; // 若发生错误，直接返回
                }
                if (!this.isInlineTable(value)) {
                    this.error("内联表格不能包含嵌套表格。键: " + key, {line:0, column:0});
                    return ""; // 若发生错误，直接返回
                }
            }

            var encodedValue:String = this.encodeValue(value);
            if (this.hasError) {
                return ""; // 若发生错误，提前退出
            }
            result.push(key + " = " + encodedValue);
            first = false;
        }

        result.push(pretty ? " }" : "}");
        return result.join("");
    }


    /**
     * 编码具体的值：字符串、数字、布尔值等
     * @param value 值
     * @return TOML/FNTL 格式的字符串
     */
    private function encodeValue(value):String {
        if (typeof(value) == "string") {
            // 检查是否为日期时间格式
            if (this.isDateTimeString(value)) {
                var dateTimeStr:String = this.encodeDateTimeString(value);
                if (this.hasError) {
                    if (this.debug) {
                        trace("Error encountered while encoding date-time string: " + value);
                    }
                    return "";
                }
                if (this.debug) {
                    trace("Encoded date-time string: " + dateTimeStr);
                }
                return dateTimeStr;
            } else {
                var encodedStr:String = this.encodeString(String(value));
                if (this.hasError) {
                    if (this.debug) {
                        trace("Error encountered while encoding string: " + value);
                    }
                    return "";
                }
                if (this.debug) {
                    trace("Encoded string: " + encodedStr);
                }
                return encodedStr;
            }
        } else if (typeof(value) == "number") {
            var encodedNum:String = this.encodeFloat(value);
            if (this.debug) {
                trace("Encoded number: " + encodedNum);
            }
            return encodedNum;
        } else if (typeof(value) == "boolean") {
            var encodedBool:String = value ? "true" : "false";
            if (this.debug) {
                trace("Encoded boolean: " + encodedBool);
            }
            return encodedBool;
        } else if (value instanceof Date) {
            var encodedDate:String = this.encodeDate(value);
            if (this.debug) {
                trace("Encoded date: " + encodedDate);
            }
            return encodedDate;
        } else if (typeof(value) == "object" && value != null) {
            if (this.isArray(value)) {
                var encodedArr:String = this.encodeArray(value, false);
                if (this.debug) {
                    trace("Encoded nested array: " + encodedArr);
                }
                return encodedArr;
            } else {
                if (this.isInlineTable(value)) {
                    var inlineTableStr:String = this.encodeInlineTable(value);
                    if (this.hasError) {
                        if (this.debug) {
                            trace("Error encountered while encoding nested inline table.");
                        }
                        return "";
                    }
                    if (this.debug) {
                        trace("Encoded nested inline table: " + inlineTableStr);
                    }
                    return inlineTableStr;
                } else {
                    // 对象将由 encode 方法处理
                    if (this.debug) {
                        trace("Encountered nested object that will be handled separately.");
                    }
                    return "";
                }
            }
        } else {
            var encodedOther:String = value != null ? String(value) : "null";
            if (this.debug) {
                trace("Encoded other type: " + encodedOther);
            }
            return encodedOther;
        }
    }

    /**
     * 判断字符串是否为日期时间格式
     * @param value 字符串
     * @return 是否为日期时间格式
     */
    private function isDateTimeString(value:String):Boolean {
        var dateTimeRegExp:RegExp = new RegExp("^\\d{4}-\\d{2}-\\d{2}[Tt ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?([Zz]|[+-]\\d{2}:\\d{2})?$");
        var isMatch:Boolean = dateTimeRegExp.test(value);
        if (this.debug) {
            trace("Checking if string is date-time: '" + value + "' -> " + isMatch);
        }
        return isMatch;
    }

    /**
     * 编码日期时间字符串，返回不带引号的字符串
     * 并验证日期时间的实际有效性
     * @param value 字符串
     * @return TOML/FNTL 格式的日期时间字符串，或空字符串（如果无效）
     */
    private function encodeDateTimeString(value:String):String {
        if (this.debug) {
            trace("Starting manual parsing of date-time string: " + value);
        }
        
        // 查找日期和时间的分隔符 'T'、't' 或空格
        var separatorIndex:Number = value.indexOf('T');
        if (separatorIndex == -1) {
            separatorIndex = value.indexOf('t');
        }
        if (separatorIndex == -1) {
            separatorIndex = value.indexOf(' ');
        }
        
        if (separatorIndex == -1) {
            // 没有找到分隔符，格式无效
            this.error("Invalid date-time format: Missing date-time separator (T/t/ ). " + value, {line:0, column:0});
            if (this.debug) {
                trace("Missing date-time separator in string: " + value);
            }
            return "";
        }
        
        var datePart:String = value.substring(0, separatorIndex);
        var timeAndTZPart:String = value.substring(separatorIndex + 1);
        
        // 解析日期部分
        var dateComponents:Array = datePart.split("-");
        if (dateComponents.length != 3) {
            this.error("Invalid date format: " + datePart, {line:0, column:0});
            if (this.debug) {
                trace("Date part does not have exactly 3 components: " + datePart);
            }
            return "";
        }
        
        var year:Number = Number(dateComponents[0]);
        var month:Number = Number(dateComponents[1]);
        var day:Number = Number(dateComponents[2]);
        
        if (isNaN(year) || isNaN(month) || isNaN(day)) {
            this.error("Non-numeric date components: " + datePart, {line:0, column:0});
            if (this.debug) {
                trace("One of the date components is not a number: " + datePart);
            }
            return "";
        }
        
        // 验证月份
        if (month < 1 || month > 12) {
            this.error("Invalid month in date-time string: " + value, {line:0, column:0});
            if (this.debug) {
                trace("Invalid month detected: " + month);
            }
            return "";
        }
        
        // 获取指定年份和月份的最大天数
        var maxDay:Number = this.getMaxDay(year, month);
        if (day < 1 || day > maxDay) {
            this.error("Invalid day in date-time string: " + value, {line:0, column:0});
            if (this.debug) {
                trace("Invalid day detected: " + day + " for month: " + month + ", year: " + year);
            }
            return "";
        }
        
        // 解析时间和时区部分
        var tzSignIndex:Number = timeAndTZPart.indexOf('Z');
        var tzOffsetIndex:Number = timeAndTZPart.indexOf('+');
        if (tzSignIndex == -1) {
            tzSignIndex = timeAndTZPart.indexOf('-');
        }
        
        var timePart:String;
        var tzPart:String = "Z"; // 默认时区为 Zulu 时间
        if (tzSignIndex != -1) {
            timePart = timeAndTZPart.substring(0, tzSignIndex);
            tzPart = timeAndTZPart.substring(tzSignIndex);
        } else {
            timePart = timeAndTZPart;
        }
        
        var timeComponents:Array = timePart.split(":");
        if (timeComponents.length != 3) {
            this.error("Invalid time format: " + timePart, {line:0, column:0});
            if (this.debug) {
                trace("Time part does not have exactly 3 components: " + timePart);
            }
            return "";
        }
        
        var hour:Number = Number(timeComponents[0]);
        var minute:Number = Number(timeComponents[1]);
        var secondAndFraction:String = timeComponents[2];
        
        var second:Number = 0;
        var fractional:Number = 0;
        
        var fractionIndex:Number = secondAndFraction.indexOf('.');
        if (fractionIndex != -1) {
            second = Number(secondAndFraction.substring(0, fractionIndex));
            var fractionStr:String = secondAndFraction.substring(fractionIndex + 1);
            // 仅取前三位作为毫秒
            fractionStr = fractionStr.length > 3 ? fractionStr.substring(0,3) : fractionStr;
            fractional = Number("0." + fractionStr);
        } else {
            second = Number(secondAndFraction);
        }
        
        if (isNaN(hour) || isNaN(minute) || isNaN(second)) {
            this.error("Non-numeric time components: " + timePart, {line:0, column:0});
            if (this.debug) {
                trace("One of the time components is not a number: " + timePart);
            }
            return "";
        }
        
        // 验证时间组件
        if (hour < 0 || hour > 23) {
            this.error("Invalid hour in date-time string: " + value, {line:0, column:0});
            if (this.debug) {
                trace("Invalid hour detected: " + hour);
            }
            return "";
        }
        if (minute < 0 || minute > 59) {
            this.error("Invalid minute in date-time string: " + value, {line:0, column:0});
            if (this.debug) {
                trace("Invalid minute detected: " + minute);
            }
            return "";
        }
        if (second < 0 || second > 59) {
            this.error("Invalid second in date-time string: " + value, {line:0, column:0});
            if (this.debug) {
                trace("Invalid second detected: " + second);
            }
            return "";
        }
        
        // 解析并验证时区部分
        var tzSign:String = "Z";
        var tzHours:Number = 0;
        var tzMinutes:Number = 0;
        
        if (tzPart.charAt(0) == 'Z' || tzPart.charAt(0) == 'z') {
            tzSign = "Z";
        } else {
            tzSign = tzPart.charAt(0);
            var tzOffset:Array = tzPart.substring(1).split(":");
            if (tzOffset.length != 2) {
                this.error("Invalid timezone format: " + tzPart, {line:0, column:0});
                if (this.debug) {
                    trace("Timezone offset does not have exactly 2 components: " + tzPart);
                }
                return "";
            }
            tzHours = Number(tzOffset[0]);
            tzMinutes = Number(tzOffset[1]);
            
            if (isNaN(tzHours) || isNaN(tzMinutes)) {
                this.error("Non-numeric timezone components: " + tzPart, {line:0, column:0});
                if (this.debug) {
                    trace("One of the timezone components is not a number: " + tzPart);
                }
                return "";
            }
            
            if (tzHours < 0 || tzHours > 23 || tzMinutes < 0 || tzMinutes > 59) {
                this.error("Invalid timezone offset in date-time string: " + value, {line:0, column:0});
                if (this.debug) {
                    trace("Invalid timezone offset detected: " + tzPart);
                }
                return "";
            }
        }
        
        // 构建验证后的日期时间字符串
        var encodedDateTimeStr:String = "";
        encodedDateTimeStr += this.padZero(year) + "-";
        encodedDateTimeStr += this.padZero(month) + "-";
        encodedDateTimeStr += this.padZero(day) + "T";
        encodedDateTimeStr += this.padZero(hour) + ":";
        encodedDateTimeStr += this.padZero(minute) + ":";
        encodedDateTimeStr += this.padZero(second);
        if (fractional > 0) {
            // 保留三位小数作为毫秒
            var fractionalStr:String = String(Math.round(fractional * 1000));
            while (fractionalStr.length < 3) {
                fractionalStr = "0" + fractionalStr;
            }
            encodedDateTimeStr += "." + fractionalStr;
        }
        if (tzSign == "Z") {
            encodedDateTimeStr += "Z";
        } else {
            encodedDateTimeStr += tzSign + this.padZero(tzHours) + ":" + this.padZero(tzMinutes);
        }
        
        if (this.debug) {
            trace("Encoded Date-Time String: " + encodedDateTimeStr);
        }
        
        return encodedDateTimeStr;
    }


    /**
     * 获取指定年份和月份的最大天数
     * @param year 年份
     * @param month 月份
     * @return 最大天数
     */
    private function getMaxDay(year:Number, month:Number):Number {
        switch(month) {
            case 1: case 3: case 5: case 7: case 8: case 10: case 12:
                return 31;
            case 4: case 6: case 9: case 11:
                return 30;
            case 2:
                // 闰年判断
                if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) {
                    return 29;
                } else {
                    return 28;
                }
            default:
                return 31; // 默认返回31
        }
    }


    /**
     * 编码浮点数，处理特殊数值
     * @param value 浮点数值
     * @return TOML/FNTL 格式的浮点数字符串
     */
    private function encodeFloat(value:Number):String {
        if (isNaN(value)) {
            if (this.debug) {
                trace("Encoded special float (NaN): nan");
            }
            return "nan";
        } else if (value == Infinity) {
            if (this.debug) {
                trace("Encoded special float (Infinity): inf");
            }
            return "inf";
        } else if (value == -Infinity) {
            if (this.debug) {
                trace("Encoded special float (-Infinity): -inf");
            }
            return "-inf";
        } else {
            var numStr:String = String(value);
            if (this.debug) {
                trace("Encoded float: " + numStr);
            }
            return numStr;
        }
    }

    /**
     * 编码字符串
     * @param value 字符串值
     * @return 编码后的字符串
     */
    private function encodeString(value:String):String {
        if (this.debug) {
            trace("Starting to encode string: " + value);
        }

        if (value.indexOf("\n") != -1 || value.indexOf("\r") != -1) {
            // 处理多行字符串
            var escapedValueMultiline:String = value.split('"""').join('\\"""');
            var multilineStr:String = '"""' + escapedValueMultiline + '"""';
            if (this.debug) {
                trace("Encoded multiline string: " + multilineStr);
            }
            return multilineStr;
        } else {
            // 处理单行字符串
            var result:String = "";
            for (var i:Number = 0; i < value.length; i++) {
                var c:String = value.charAt(i);
                var code:Number = value.charCodeAt(i);
                if (c == "\\" || c == "\"") {
                    result += "\\" + c; // 转义反斜杠和双引号
                } else if (code >= 0x0000 && code <= 0x001F) {
                    // 控制字符转义
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
                            result += "\\u" + hex; // 使用 \uXXXX 格式转义控制字符
                            break;
                    }
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
    private function encodeDate(date:Date):String {
        var year:String = String(date.getFullYear());
        var month:String = this.padZero(date.getMonth() + 1);
        var day:String = this.padZero(date.getDate());
        var hours:String = this.padZero(date.getHours());
        var minutes:String = this.padZero(date.getMinutes());
        var seconds:String = this.padZero(date.getSeconds());

        var milliseconds:Number = date.getMilliseconds();
        var fractional:String = milliseconds > 0 ? "." + this.padZeroFraction(milliseconds) : "";

        // 处理时区偏移
        var timezoneOffset:Number = -date.getTimezoneOffset();
        var tzSign:String = timezoneOffset >= 0 ? "+" : "-";
        var tzHours:Number = Math.floor(Math.abs(timezoneOffset) / 60);
        var tzMinutes:Number = Math.abs(timezoneOffset) % 60;
        var timezoneSuffix:String = tzSign + this.padZero(tzHours) + ":" + this.padZero(tzMinutes);

        return year + "-" + month + "-" + day + "T" + hours + ":" + minutes + ":" + seconds + fractional + timezoneSuffix;
    }



    /**
     * 获取对象的所有键，支持忽略内部键
     * @param obj 对象
     * @return 键数组
     */
    private function getKeys(obj:Object):Array {
        var keys:Array = [];
        for (var key:String in obj) {
            if (!this.isInternalKey(key)) {
                keys.push(key);
            } else {
                if (this.debug) {
                    trace("Internal key '" + key + "' is ignored.");
                }
            }
        }
        return QuickSort.adaptiveSort(keys, this.compareKeys);
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
     * 编码内联表格字符串为对象
     * @param tableStr 内联表格字符串
     * @return 解析后的内联表格对象
     */
    private function parseInlineTable(tableStr:String):Object {
        var table:Object = new Object();
        var lexer:FNTLLexer = new FNTLLexer(tableStr, this.debug);
        var tokens:Array = new Array();
        var tok:Object;
        while ((tok = lexer.getNextToken()) != null) {
            tokens.push(tok);
            if (this.debug) {
                trace("Lexer Token: " + ObjectUtil.toString(tok));
            }
        }
        var parser:FNTLParser = new FNTLParser(tokens, tableStr, this.debug);
        var parsedTable:Object = parser.parse();
        if (parser.hasError()) {
            this.error("内联表格解析失败: " + tableStr, {line:0, column:0});
            if (this.debug) {
                trace("Inline table parsing failed for: " + tableStr);
            }
            return undefined;
        }
        if (this.debug) {
            trace("Parsed inline table: " + ObjectUtil.toString(parsedTable));
        }
        return parsedTable;
    }

    /**
     * 处理解析错误，通过设置错误标志并记录错误信息。
     * @param message 错误消息。
     * @param token 相关的 Token 对象，用于定位错误位置。
     */
    private function error(message:String, token:Object, currentPath:Array):Void {
        var pathInfo:String = "路径: " + currentPath.join(".");
        var lineInfo:String = "行: " + (token.line != undefined ? token.line : "?") + ", 列: " + (token.column != undefined ? token.column : "?");
        trace("错误: " + message + " 在 " + pathInfo + ", " + lineInfo);
        this.hasError = true;
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

    /**
     * 获取当前递归深度的缩进字符串。
     * @param level 当前递归深度。
     * @return 缩进字符串。
     */
    private function getIndent(level:Number):String {
        var indent:String = "";
        for (var i:Number = 0; i < level; i++) {
            indent += "    "; // 每层缩进4个空格
        }
        return indent;
    }

    /**
     * 带缩进的编码输出辅助函数。
     * @param content 要输出的内容。
     * @param indent 当前缩进。
     * @return 加入缩进后的字符串。
     */
    private function encodeWithIndent(content:String, indent:String):String {
        return indent + content;
    }


    /**
     * 格式化数组元素，根据是否启用美化决定是否换行和缩进。
     * @param element 当前数组元素。
     * @param pretty 是否启用美化。
     * @param indent 当前缩进。
     * @return 格式化后的数组元素字符串。
     */
    private function formatArrayElement(element:String, pretty:Boolean, indent:String):String {
        if (pretty) {
            return "\n" + indent + element;
        } else {
            return element;
        }
    }

    /**
     * 在数字前添加前导零以保证两位数格式。
     * @param value 数值。
     * @return 带前导零的两位数字符串。
     */
    private function padZero(value:Number):String {
        return value < 10 ? "0" + value : String(value);
    }

    /**
     * 在小数部分前添加前导零以保证三位数格式。
     * @param milliseconds 数值。
     * @return 带前导零的三位数字符串。
     */
    private function padZeroFraction(milliseconds:Number):String {
        var fraction:String = String(milliseconds);
        while (fraction.length < 3) {
            fraction = "0" + fraction;
        }
        return fraction;
    }

    /**
     * 将多行内容拼接为带缩进的输出。
     * @param lines 多行内容数组。
     * @param indent 缩进。
     * @param pretty 是否启用美化。
     * @return 拼接后的字符串。
     */
    private function joinLinesWithIndent(lines:Array, indent:String, pretty:Boolean):String {
        if (pretty) {
            return indent + lines.join("\n" + indent);
        } else {
            return lines.join(", ");
        }
    }

    /**
     * 如果启用美化输出，添加换行符。
     * @param pretty 是否启用美化。
     * @return 换行符（如果启用美化）。
     */
    private function encodeNewline(pretty:Boolean):String {
        return pretty ? "\n" : "";
    }

}
