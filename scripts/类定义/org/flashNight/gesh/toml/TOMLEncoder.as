import org.flashNight.gesh.object.*;
import org.flashNight.gesh.string.*;
class org.flashNight.gesh.toml.TOMLEncoder {
    
    private var MAX_RECURSION_DEPTH:Number = 256; // 递归深度限制

    // 构造函数
    public function TOMLEncoder() {
        // 无需初始化缩进级别
    }

    /**
     * 编码 AS2 对象为 TOML 格式字符串
     * @param obj 要编码的对象
     * @param pretty 是否进行美化输出
     * @return TOML 格式的字符串
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
                throw new Error("Exceeded max recursion depth.");
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
            keys = this.sortKeys(keys);

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
                    if (this.isInlineTable(value) && path.length == 0) {
                        // 仅在顶层允许内联表格
                        var encodedInline:String = this.encodeInlineTable(value);
                        result.push(key + " = " + encodedInline);
                    } else {
                        // 将嵌套对象作为独立表格处理
                        var newPath:Array = path.concat([key]);
                        stack.push({ object: value, path: newPath, depth: depth + 1, isArrayElement: false });
                        continue; // 不在当前表格中编码此键
                    }
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
     * 构建表格头
     * @param path 当前表格路径数组
     * @return 表格头字符串
     */
    private function buildTableHeader(path:Array):String {
        return "[" + path.join(".") + "]";
    }

    /**
     * 构建表格数组头
     * @param path 当前表格路径数组
     * @return 表格数组头字符串
     */
    private function buildTableArrayHeader(path:Array):String {
        return "[[" + path.join(".") + "]]";
    }

    /**
     * 编码数组
     * @param arr 数组
     * @param pretty 是否进行美化输出
     * @return TOML 格式的数组字符串
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
     * @return TOML 格式的内联表格字符串
     */
    private function encodeInlineTable(table:Object):String {
        var result:Array = ["{ "];
        var keys:Array = this.getKeys(table);
        keys = this.sortKeys(keys);
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
     * @param value 值 不标注类型以过编译
     * @return TOML 格式的字符串
     */
    private function encodeValue(value):String {
        if (typeof(value) == "string") {
            return this.encodeString(String(value));
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
                // 对于嵌套对象，应已作为独立表格处理，这里不需要编码为内联表格
                return "";
            }
        } else {
            return value != null ? String(value) : "null";
        }
    }

    /**
     * 编码浮点数，处理特殊数值
     * @param value 浮点数值
     * @return TOML 格式的浮点数字符串
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
     * @return TOML 格式的字符串
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
                            var hex:String = code.toString(16);
                            while (hex.length < 4) {
                                hex = "0" + hex;
                            }
                            result += "\\u" + hex;
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
     * 编码日期时间
     * @param date Date 对象
     * @return TOML 格式的日期时间字符串
     */
    private function encodeDate(date:Object):String {
        var year:String = String(date.getFullYear());
        var month:String = this.padZero(date.getMonth() + 1);
        var day:String = this.padZero(date.getDate());
        var hours:String = this.padZero(date.getHours());
        var minutes:String = this.padZero(date.getMinutes());
        var seconds:String = this.padZero(date.getSeconds());
        return year + "-" + month + "-" + day + "T" + hours + ":" + minutes + ":" + seconds + "Z";
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
     * 获取对象的所有键，忽略内部键（如 __dictUID）
     */
    private function getKeys(obj:Object):Array {
        var keys:Array = [];
        for (var key:String in obj) {
            if (!this.isInternalKey(key)) {
                keys.push(key);
            }
        }
        return keys;
    }

    /**
     * 排序键数组
     * @param keys 键数组
     * @return 排序后的键数组
     */
    private function sortKeys(keys:Array):Array {
        // 简单的插入排序
        for (var i:Number = 1; i < keys.length; i++) {
            var keyToInsert:String = keys[i];
            var j:Number = i - 1;
            while (j >= 0 && keys[j] > keyToInsert) {
                keys[j + 1] = keys[j];
                j--;
            }
            keys[j + 1] = keyToInsert;
        }
        return keys;
    }

    /**
     * 判断是否为内部键（如 __dictUID）
     */
    private function isInternalKey(key:String):Boolean {
        return key.substr(0, 2) == "__";
    }
}
