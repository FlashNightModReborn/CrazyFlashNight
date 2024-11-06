import org.flashNight.naki.DataStructures.Dictionary;
import org.flashNight.naki.Sort.InsertionSort;

class FastJSON {
    public var text:String;
    public var ch:String = "";
    public var at:Number = 0;

    // 最大解析深度以防止栈溢出
    public var maxDepth:Number = 256; 
    private var currentDepth:Number = 0;
    
    // 存储 text.length 的变量
    private var textLength:Number = 0;
    
    // 字符数组缓存
    private var charArray:Array;
    
    // 缓存对象
    private var parseCache:Object = {};         // 解析缓存
    private var stringifyCache:Object = {};     // 序列化缓存
    private var cacheMaxSize:Number = 1024;    // 缓存最大容量

    // 缓存键的插入顺序，用于FIFO清理
    private var parseCacheKeys:Array = [];
    private var stringifyCacheKeys:Array = [];

    // 缓存计数器
    private var parseCacheCount:Number = 0;
    private var stringifyCacheCount:Number = 0;

    /**
     * 构造函数
     */
    public function FastJSON() {
        // 此简化版本无需初始化
    }

    /**
     * 将对象转换为唯一的缓存键
     * 使用Dictionary.getStaticUID为对象分配唯一UID
     * 对于基本类型，直接转换为字符串
     * @param arg 要生成键的对象
     * @return 生成的唯一键字符串
     */
    private function generateCacheKey(arg):String {
        switch (typeof arg) {
            case "object":
                if (arg === null) {
                    return "null";
                }
                return "obj_" + Dictionary.getStaticUID(arg);
            case "string":
                return "str_" + arg;
            case "number":
                return "num_" + arg;
            case "boolean":
                return "bool_" + arg;
            default:
                return "undefined";
        }
    }

    /**
     * 清理缓存（FIFO策略）
     * @param cache 要清理的缓存对象
     * @param cacheKeys 缓存键的顺序数组
     * @param cacheCountRef 缓存计数器引用
     */
    private function cleanCache(cache:Object, cacheKeys:Array, cacheCountRef:Object):Void {
        while (cacheCountRef.count > this.cacheMaxSize) {
            var oldestKey = cacheKeys.shift();
            if (oldestKey !== undefined) {
                delete cache[oldestKey];
                cacheCountRef.count--;
            }
        }
    }

    /**
     * 将 AS2 对象序列化为 FastJSON 字符串
     * @param arg 要序列化的对象
     * @return FastJSON 字符串
     */
    public function stringify(arg):String {
        // 定义堆栈类型常量（直接使用硬编码数值）
        // 0: VALUE, 1: KEY, 2: COMMA, 3: COLON, 4: END_OBJECT, 5: END_ARRAY
        
        // 缓存检查
        var cacheKey:String = this.generateCacheKey(arg);
        if (this.stringifyCache[cacheKey] != undefined) {
            return this.stringifyCache[cacheKey];
        }

        // 初始化结果字符串
        var resultStr:String = "";

        // 初始化手动管理的堆栈
        var stackTypes:Array = new Array(64); // 预分配容量
        var stackData:Array = new Array(64);
        var stackPtr:Number = 0;

        // 推入初始值（类型: VALUE = 0）
        stackTypes[stackPtr] = 0; // VALUE
        stackData[stackPtr++] = arg;

        // 声明 propertyKeys 和 propertyValues
        var propertyKeys:Array = [];
        var propertyValues:Array = [];

        // 主循环，替代递归
        while (stackPtr > 0) {
            // 弹出堆栈顶部元素
            stackPtr--;
            var type:Number = stackTypes[stackPtr];
            var data:Object = stackData[stackPtr];

            if (type === 0) { // VALUE
                if (typeof data === "object") {
                    if (data == null) {
                        resultStr += "null";
                    } else if (data instanceof Array) {
                        var len:Number = data.length;
                        resultStr += "[";
                        if (len > 0) {
                            // 推入结束标记（END_ARRAY = 5）
                            stackTypes[stackPtr] = 5; // END_ARRAY
                            stackData[stackPtr++] = null;
                            // 倒序推入数组元素和逗号
                            for (var i:Number = len - 1; i >= 0; i--) {
                                if (i < len - 1) {
                                    stackTypes[stackPtr] = 2; // COMMA
                                    stackData[stackPtr++] = null;
                                }
                                stackTypes[stackPtr] = 0; // VALUE
                                stackData[stackPtr++] = data[i];
                            }
                        } else {
                            resultStr += "]";
                        }
                    } else {
                        // 处理对象
                    resultStr += "{";
                    propertyKeys.length = 32;
                    propertyValues.length = 32;

                    var index:Number = 0;
                    for (var key:String in data) {
                        if (!(key.charAt(0) == "_" && key.charAt(1) == "_")) {
                            var value:Object = data[key];
                            if (typeof value !== "undefined" && typeof value !== "function") {
                                propertyKeys[index] = key;
                                propertyValues[index] = value;
                                index++;
                            }
                        }
                    }

                    // Adjust length to match the number of added entries, if necessary.
                    propertyKeys.length = index;
                    propertyValues.length = index;

                        var numKeys:Number = propertyKeys.length;
                        if (numKeys > 0) {
                            // 推入结束标记（END_OBJECT = 4）
                            stackTypes[stackPtr] = 4; // END_OBJECT
                            stackData[stackPtr++] = null;
                            // 倒序推入键值对和逗号
                            for (var k:Number = numKeys - 1; k >= 0; k--) {
                                var propKey:String = propertyKeys[k];
                                var propValue:Object = propertyValues[k];
                                if (k < numKeys - 1) {
                                    stackTypes[stackPtr] = 2; // COMMA
                                    stackData[stackPtr++] = null;
                                }
                                // 推入值（VALUE = 0）
                                stackTypes[stackPtr] = 0; // VALUE
                                stackData[stackPtr++] = propValue;
                                // 推入冒号（COLON = 3）
                                stackTypes[stackPtr] = 3; // COLON
                                stackData[stackPtr++] = null;
                                // 推入键（KEY = 1）
                                stackTypes[stackPtr] = 1; // KEY
                                stackData[stackPtr++] = propKey;
                            }
                        } else {
                            resultStr += "}";
                        }
                    }
                } else if (typeof data === "string") {
                    // 处理字符串并转义（优化部分）
                    var str = data;
                    var escStr:String = "\"";
                    var chars:Array = str.split(""); // 使用 split("") 转换成字符数组
                    var strLen:Number = chars.length;
                    for (var si:Number = 0; si < strLen; si++) {
                        var c:String = chars[si];
                        if (c >= " ") {
                            if (c === "\\" || c === "\"") {
                                escStr += "\\" + c;
                            } else {
                                escStr += c;
                            }
                        } else {
                            switch (c) {
                                case "\b":
                                    escStr += "\\b";
                                    break;
                                case "\f":
                                    escStr += "\\f";
                                    break;
                                case "\n":
                                    escStr += "\\n";
                                    break;
                                case "\r":
                                    escStr += "\\r";
                                    break;
                                case "\t":
                                    escStr += "\\t";
                                    break;
                                default:
                                    var cc:Number = c.charCodeAt(0);
                                    var hc:String = cc.toString(16);
                                    while (hc.length < 4) {
                                        hc = "0" + hc;
                                    }
                                    escStr += "\\u" + hc;
                            }
                        }
                    }
                    escStr += "\"";
                    resultStr += escStr;
                } else if (typeof data === "number") {
                    resultStr += isFinite(data) ? String(data) : "null";
                } else if (typeof data === "boolean") {
                    resultStr += String(data);
                } else {
                    resultStr += "null";
                }
            } else if (type === 1) { // KEY
                // 处理键并转义（优化部分）
                var keyStr:String = "\"";
                var keyVal:String = String(data);
                var keyChars:Array = keyVal.split(""); // 使用 split("") 转换成字符数组
                var keyLen:Number = keyChars.length;
                for (var ki:Number = 0; ki < keyLen; ki++) {
                    var kc:String = keyChars[ki];
                    if (kc >= " ") {
                        if (kc === "\\" || kc === "\"") {
                            keyStr += "\\" + kc;
                        } else {
                            keyStr += kc;
                        }
                    } else {
                        switch (kc) {
                            case "\b":
                                keyStr += "\\b";
                                break;
                            case "\f":
                                keyStr += "\\f";
                                break;
                            case "\n":
                                keyStr += "\\n";
                                break;
                            case "\r":
                                keyStr += "\\r";
                                break;
                            case "\t":
                                keyStr += "\\t";
                                break;
                            default:
                                var kcc:Number = kc.charCodeAt(0);
                                var khc:String = kcc.toString(16);
                                while (khc.length < 4) {
                                    khc = "0" + khc;
                                }
                                keyStr += "\\u" + khc;
                        }
                    }
                }
                keyStr += "\"";
                resultStr += keyStr;
            } else if (type === 2) { // COMMA
                resultStr += ",";
            } else if (type === 3) { // COLON
                resultStr += ":";
            } else if (type === 4) { // END_OBJECT
                resultStr += "}";
            } else if (type === 5) { // END_ARRAY
                resultStr += "]";
            }
        }

        // 缓存序列化结果
        this.stringifyCache[cacheKey] = resultStr;
        this.stringifyCacheKeys.push(cacheKey);
        this.stringifyCacheCount++;

        // 检查并清理缓存
        if (this.stringifyCacheCount > this.cacheMaxSize) {
            this.cleanCache(this.stringifyCache, this.stringifyCacheKeys, {count: this.stringifyCacheCount});
            this.stringifyCacheCount = this.stringifyCacheKeys.length;
        }

        return resultStr;
    }

    /**
     * 解析值
     * @return 解析后的值
     */
    public function value() {
        var stackTypes:Array = new Array(64); // 预分配堆栈容量
        var stackData:Array = new Array(64);
        var stackPtr:Number = 0;

        var result;
        var numberStr:String;
        var word:String;
        var numValue:Number;
        var unicodeValue:Number;
        var hexDigit:Number;
        var ch:String = this.ch;
        var at:Number = this.at;
        var textLength:Number = this.textLength;
        var charArray:Array = this.charArray;
        var currentDepth:Number = this.currentDepth;

        // 内联 white() 方法
        while (ch <= " " && ch != "") {
            // 内联 next() 方法
            if (at >= textLength) {
                ch = "";
            } else {
                ch = charArray[at];
                at += 1;
            }
        }

        // 初始化堆栈
        stackTypes[stackPtr] = 0; // VALUE
        stackData[stackPtr++] = null; // 初始值

        var key:String;
        var object:Object;
        var array:Array;
        var tempValue;
        var keyStrParts:Array;
        var resultStrParts:Array;
        var i:Number;
        var len:Number;

        while (stackPtr > 0) {
            // 弹出堆栈顶部元素
            stackPtr--;
            var type:Number = stackTypes[stackPtr];
            var data = stackData[stackPtr];

            if (type === 0) { // VALUE
                currentDepth += 1;
                if (currentDepth > this.maxDepth) {
                    this.error("Maximum parsing depth exceeded");
                }

                if (ch === "{") {
                    object = {};
                    // 内联 next() 方法
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                    // 内联 white() 方法
                    while (ch <= " " && ch != "") {
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                    }
                    if (ch == "}") {
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                        currentDepth -= 1;
                        tempValue = object;
                        continue;
                    }
                    // 推入对象开始状态
                    stackTypes[stackPtr] = 1; // OBJECT_BEGIN
                    stackData[stackPtr++] = object;
                } else if (ch === "[") {
                    array = [];
                    // 内联 next() 方法
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                    // 内联 white() 方法
                    while (ch <= " " && ch != "") {
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                    }
                    if (ch == "]") {
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                        currentDepth -= 1;
                        tempValue = array;
                        continue;
                    }
                    // 推入数组开始状态
                    stackTypes[stackPtr] = 2; // ARRAY_BEGIN
                    stackData[stackPtr++] = array;
                } else if (ch === "\"") {
                    resultStrParts = [];
                    // 内联 next() 方法，跳过开头的引号
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                    while (ch) {
                        if (ch == "\"") {
                            // 内联 next() 方法，跳过结尾的引号
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                            break;
                        }
                        if (ch == "\\") {
                            // 内联 next() 方法，处理转义字符
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                            switch (ch) {
                                case "b":
                                    resultStrParts.push("\b");
                                    break;
                                case "f":
                                    resultStrParts.push("\f");
                                    break;
                                case "n":
                                    resultStrParts.push("\n");
                                    break;
                                case "r":
                                    resultStrParts.push("\r");
                                    break;
                                case "t":
                                    resultStrParts.push("\t");
                                    break;
                                case "u":
                                    unicodeValue = 0;
                                    for (i = 0; i < 4; i++) {
                                        if (at >= textLength) {
                                            ch = "";
                                        } else {
                                            ch = charArray[at];
                                            at += 1;
                                        }
                                        hexDigit = parseInt(ch, 16);
                                        if (!isFinite(hexDigit)) {
                                            this.error("Invalid Unicode escape sequence");
                                        }
                                        unicodeValue = unicodeValue * 16 + hexDigit;
                                    }
                                    resultStrParts.push(String.fromCharCode(unicodeValue));
                                    continue;
                                default:
                                    resultStrParts.push(ch);
                                    break;
                            }
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        } else {
                            resultStrParts.push(ch);
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        }
                    }
                    tempValue = resultStrParts.join("");
                    currentDepth -= 1;
                    continue;
                } else if (ch === "-") {
                    // 解析负数
                    numberStr = "-";
                    // 内联 next() 方法
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                    while (ch >= "0" && ch <= "9") {
                        numberStr += ch;
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                    }
                    if (ch == ".") {
                        numberStr += ".";
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                        while (ch >= "0" && ch <= "9") {
                            numberStr += ch;
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        }
                    }
                    if (ch == "e" || ch == "E") {
                        numberStr += ch;
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                        if (ch == "-" || ch == "+") {
                            numberStr += ch;
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        }
                        while (ch >= "0" && ch <= "9") {
                            numberStr += ch;
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        }
                    }
                    numValue = Number(numberStr);
                    if (isNaN(numValue)) {
                        this.error("Bad number");
                    }
                    tempValue = numValue;
                    currentDepth -= 1;
                    continue;
                } else if (ch >= "0" && ch <= "9") {
                    // 解析正数
                    numberStr = "";
                    while (ch >= "0" && ch <= "9") {
                        numberStr += ch;
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                    }
                    if (ch == ".") {
                        numberStr += ".";
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                        while (ch >= "0" && ch <= "9") {
                            numberStr += ch;
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        }
                    }
                    if (ch == "e" || ch == "E") {
                        numberStr += ch;
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                        if (ch == "-" || ch == "+") {
                            numberStr += ch;
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        }
                        while (ch >= "0" && ch <= "9") {
                            numberStr += ch;
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        }
                    }
                    numValue = Number(numberStr);
                    if (isNaN(numValue)) {
                        this.error("Bad number");
                    }
                    tempValue = numValue;
                    currentDepth -= 1;
                    continue;
                } else if (ch >= "a" && ch <= "z") {
                    // 解析字面量：true, false, null
                    word = "";
                    while (ch >= "a" && ch <= "z") {
                        word += ch;
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                    }
                    if (word == "true") {
                        tempValue = true;
                        currentDepth -= 1;
                        continue;
                    } else if (word == "false") {
                        tempValue = false;
                        currentDepth -= 1;
                        continue;
                    } else if (word == "null") {
                        tempValue = null;
                        currentDepth -= 1;
                        continue;
                    } else {
                        this.error("Unexpected token: " + word);
                    }
                } else {
                    this.error("Unexpected character: " + ch);
                }
            } else if (type === 1) { // OBJECT_BEGIN
                object = data;
                // 处理键值对
                while (true) {
                    // 内联 white() 方法
                    while (ch <= " " && ch != "") {
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                    }
                    if (ch == "}") {
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                        currentDepth -= 1;
                        tempValue = object;
                        break;
                    }
                    if (ch != "\"") {
                        this.error("Expected '\"' at the beginning of a key");
                    }
                    // 解析键
                    keyStrParts = [];
                    // 内联 next() 方法，跳过开头的引号
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                    while (ch) {
                        if (ch == "\"") {
                            // 内联 next() 方法，跳过结尾的引号
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                            break;
                        }
                        if (ch == "\\") {
                            // 内联 next() 方法，处理转义字符
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                            switch (ch) {
                                case "b":
                                    keyStrParts.push("\b");
                                    break;
                                case "f":
                                    keyStrParts.push("\f");
                                    break;
                                case "n":
                                    keyStrParts.push("\n");
                                    break;
                                case "r":
                                    keyStrParts.push("\r");
                                    break;
                                case "t":
                                    keyStrParts.push("\t");
                                    break;
                                case "u":
                                    unicodeValue = 0;
                                    for (i = 0; i < 4; i++) {
                                        if (at >= textLength) {
                                            ch = "";
                                        } else {
                                            ch = charArray[at];
                                            at += 1;
                                        }
                                        hexDigit = parseInt(ch, 16);
                                        if (!isFinite(hexDigit)) {
                                            this.error("Invalid Unicode escape sequence");
                                        }
                                        unicodeValue = unicodeValue * 16 + hexDigit;
                                    }
                                    keyStrParts.push(String.fromCharCode(unicodeValue));
                                    continue;
                                default:
                                    keyStrParts.push(ch);
                                    break;
                            }
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        } else {
                            keyStrParts.push(ch);
                            // 内联 next() 方法
                            if (at >= textLength) {
                                ch = "";
                            } else {
                                ch = charArray[at];
                                at += 1;
                            }
                        }
                    }
                    key = keyStrParts.join("");

                    // 内联 white() 方法
                    while (ch <= " " && ch != "") {
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                    }
                    if (ch != ":") {
                        this.error("Expected ':' after key");
                    }
                    // 内联 next() 方法，跳过 ':'
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }

                    // 内联 white() 方法
                    while (ch <= " " && ch != "") {
                        // 内联 next() 方法
                        if (at >= textLength) {
                            ch = "";
                        } else {
                            ch = charArray[at];
                            at += 1;
                        }
                    }

                    // 推入对象值状态
                    stackTypes[stackPtr] = 5; // OBJECT_VALUE
                    stackData[stackPtr++] = {object: object, key: key};

                    // 推入值状态
                    stackTypes[stackPtr] = 0; // VALUE
                    stackData[stackPtr++] = null;
                    break; // 跳出循环，等待值解析
                }
            } else if (type === 5) { // OBJECT_VALUE
                var objInfo = data;
                object = objInfo.object;
                key = objInfo.key;
                object[key] = tempValue;

                // 内联 white() 方法
                while (ch <= " " && ch != "") {
                    // 内联 next() 方法
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                }

                if (ch == "}") {
                    // 内联 next() 方法，跳过 '}'
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                    currentDepth -= 1;
                    tempValue = object;
                    continue;
                }
                if (ch != ",") {
                    this.error("Expected ',' or '}'");
                }
                // 内联 next() 方法，跳过 ','
                if (at >= textLength) {
                    ch = "";
                } else {
                    ch = charArray[at];
                    at += 1;
                }

                // 内联 white() 方法
                while (ch <= " " && ch != "") {
                    // 内联 next() 方法
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                }

                // 继续处理下一个键值对
                // 推入对象开始状态
                stackTypes[stackPtr] = 1; // OBJECT_BEGIN
                stackData[stackPtr++] = object;
            } else if (type === 2) { // ARRAY_BEGIN
                array = data;

                // 推入数组值状态
                stackTypes[stackPtr] = 7; // ARRAY_VALUE
                stackData[stackPtr++] = array;

                // 推入值状态
                stackTypes[stackPtr] = 0; // VALUE
                stackData[stackPtr++] = null;
            } else if (type === 7) { // ARRAY_VALUE
                array = data;
                array.push(tempValue);

                // 内联 white() 方法
                while (ch <= " " && ch != "") {
                    // 内联 next() 方法
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                }

                if (ch == "]") {
                    // 内联 next() 方法，跳过 ']'
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                    currentDepth -= 1;
                    tempValue = array;
                    continue;
                }
                if (ch != ",") {
                    this.error("Expected ',' or ']'");
                }
                // 内联 next() 方法，跳过 ','
                if (at >= textLength) {
                    ch = "";
                } else {
                    ch = charArray[at];
                    at += 1;
                }

                // 内联 white() 方法
                while (ch <= " " && ch != "") {
                    // 内联 next() 方法
                    if (at >= textLength) {
                        ch = "";
                    } else {
                        ch = charArray[at];
                        at += 1;
                    }
                }

                // 推入数组值状态
                stackTypes[stackPtr] = 7; // ARRAY_VALUE
                stackData[stackPtr++] = array;

                // 推入值状态
                stackTypes[stackPtr] = 0; // VALUE
                stackData[stackPtr++] = null;
            }
        }

        // 更新解析器状态
        this.ch = ch;
        this.at = at;
        this.currentDepth = currentDepth;

        return tempValue;
    }


    /**
     * 解析 FastJSON 文本
     * @param inputText 要解析的 FastJSON 字符串
     * @return 解析后的 AS2 对象
     */
    public function parse(inputText:String) {
        // 检查解析缓存
        var cacheKey:String = this.generateCacheKey(inputText);
        if (this.parseCache[cacheKey] != undefined) {
            return this.parseCache[cacheKey];
        }

        this.text = inputText;
        this.at = 0;
        this.ch = " ";
        this.currentDepth = 0; // 重置深度计数器
        this.textLength = this.text.length; // 将 length 缓存为局部变量
        this.charArray = this.text.split(""); // 初始化字符数组

        // 内联 next() 方法
        if (this.at >= this.textLength) {
            this.ch = "";
        } else {
            this.ch = this.charArray[this.at];
            this.at += 1;
        }

        var result = this.value();
        // 内联 white() 方法
        while (this.ch <= " " && this.ch != "") {
            // 内联 next() 方法
            if (this.at >= this.textLength) {
                this.ch = "";
            } else {
                this.ch = this.charArray[this.at];
                this.at += 1;
            }
        }
        if (this.ch) {
            this.error("Unexpected trailing characters");
        }

        // 缓存解析结果
        this.parseCache[cacheKey] = result;
        this.parseCacheKeys.push(cacheKey);
        this.parseCacheCount++;

        // 检查并清理缓存
        if (this.parseCacheCount > this.cacheMaxSize) {
            this.cleanCache(this.parseCache, this.parseCacheKeys, {count: this.parseCacheCount});
            // 更新 parseCacheCount
            this.parseCacheCount = this.parseCacheKeys.length;
        }

        return result;
    }

    /**
     * 抛出错误
     * @param message 错误信息
     */
    public function error(message:String):Void {
        throw {name: "FastJSONError", message: message, at: this.at - 1, text: this.text};
    }
}


