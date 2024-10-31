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
    private var cacheMaxSize:Number = 1000;    // 缓存最大容量

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
        var cacheKey:String = this.generateCacheKey(arg);
        if (this.stringifyCache[cacheKey] != undefined) {
            return this.stringifyCache[cacheKey];
        }
        
        var stack:Array = []; // 用于迭代序列化的堆栈
        var resultParts:Array = []; // 使用数组收集序列化片段，提高拼接效率
        var current:Object = arg;
        var isFirst:Boolean = true;
        
        // 推入初始元素
        stack.push({type: "value", data: current, parentType: null, isFirst: true});
        
        while (stack.length > 0) {
            var element:Object = stack.pop();
            var type:String = element.type;
            var data:Object = element.data;
            var parentType:String = element.parentType;
            var currentIsFirst:Boolean = element.isFirst;
            
            switch(type) {
                case "value":
                    switch(typeof data) {
                        case "object":
                            if (data == null) {
                                resultParts.push("null");
                            } else if (data instanceof Array) {
                                resultParts.push("[");
                                // 推入结束标记
                                stack.push({type: "closeArray"});
                                // 逆序推入数组元素
                                for (var i:Number = data.length - 1; i >= 0; i--) {
                                    stack.push({type: "value", data: data[i], parentType: "array", isFirst: (i == 0)});
                                    if (i > 0) {
                                        stack.push({type: "comma"});
                                    }
                                }
                            } else {
                                resultParts.push("{");
                                // 推入结束标记
                                stack.push({type: "closeObject"});
                                // 收集并过滤键
                                var keys:Array = [];
                                for (var k:String in data) {
                                    if (!(k.charAt(0) == "_" && k.charAt(1) == "_")) {
                                        keys.push(k);
                                    }
                                }
                                // 逆序推入键值对
                                for (var j:Number = keys.length - 1; j >= 0; j--) {
                                    var key:String = keys[j];
                                    var value:Object = data[key];
                                    if (typeof value != "undefined" && typeof value != "function") {
                                        stack.push({type: "value", data: value, parentType: "object", isFirst: (j == 0)});
                                        stack.push({type: "key", data: key});
                                        if (j > 0) {
                                            stack.push({type: "comma"});
                                        }
                                    }
                                }
                            }
                            break;
                        case "string":
                            // 序列化字符串并处理转义
                            var escStr:String = "\"";
                            var str = data;
                            var len:Number = str.length;
                            for (var si:Number = 0; si < len; si++) {
                                var c:String = str.charAt(si);
                                switch(c) {
                                    case "\\":
                                    case "\"":
                                        escStr += "\\" + c;
                                        break;
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
                                        if (c < " ") {
                                            var cc:Number = c.charCodeAt();
                                            var hc:String = cc.toString(16);
                                            while (hc.length < 4) {
                                                hc = "0" + hc;
                                            }
                                            escStr += "\\u" + hc;
                                        } else {
                                            escStr += c;
                                        }
                                }
                            }
                            escStr += "\"";
                            resultParts.push(escStr);
                            break;
                        case "number":
                            resultParts.push(isFinite(data) ? String(data) : "null");
                            break;
                        case "boolean":
                            resultParts.push(String(data));
                            break;
                        default:
                            resultParts.push("null");
                    }
                    break;
                case "key":
                    // 序列化键
                    var keyStr:String = "\"";
                    var keyVal:String = element.data;
                    var keyLen:Number = keyVal.length;
                    for (var ki:Number = 0; ki < keyLen; ki++) {
                        var kc:String = keyVal.charAt(ki);
                        switch(kc) {
                            case "\\":
                            case "\"":
                                keyStr += "\\" + kc;
                                break;
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
                                if (kc < " ") {
                                    var kcc:Number = kc.charCodeAt();
                                    var khc:String = kcc.toString(16);
                                    while (khc.length < 4) {
                                        khc = "0" + khc;
                                    }
                                    keyStr += "\\u" + khc;
                                } else {
                                    keyStr += kc;
                                }
                        }
                    }
                    keyStr += "\"";
                    resultParts.push(keyStr + ":");
                    break;
                case "comma":
                    resultParts.push(",");
                    break;
                case "closeObject":
                    resultParts.push("}");
                    break;
                case "closeArray":
                    resultParts.push("]");
                    break;
                default:
                    // 不处理其他类型
                    break;
            }
        }
        
        var result:String = resultParts.join("");
        
        // 缓存序列化结果
        this.stringifyCache[cacheKey] = result;
        this.stringifyCacheKeys.push(cacheKey);
        this.stringifyCacheCount++;
        
        // 检查并清理缓存
        if (this.stringifyCacheCount > this.cacheMaxSize) {
            this.cleanCache(this.stringifyCache, this.stringifyCacheKeys, {count: this.stringifyCacheCount});
            this.stringifyCacheCount = this.stringifyCacheKeys.length;
        }
        
        return result;
    }



    /**
     * 解析值
     * @return 解析后的值
     */
    public function value() {
        var result;
        var numberStr:String;
        var word:String;
        var numValue:Number;
        var numValueDefault:Number;
        var unicodeValue:Number;
        var hexDigit:Number;
        var keyChar:String;
        var keyCharCode:Number;
        var keyHexCode:String;
        var strChar:String;
        var strCharCode:Number;
        var strHexCode:String;
        var i:Number;
        var len:Number;

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

        this.currentDepth += 1;
        if (this.currentDepth > this.maxDepth) {
            this.error("Maximum parsing depth exceeded");
        }

        switch (this.ch) {
            case "{":
                // 解析对象
                var object:Object = {};
                // 内联 next() 方法
                if (this.at >= this.textLength) {
                    this.ch = "";
                } else {
                    this.ch = this.charArray[this.at];
                    this.at += 1;
                }

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

                if (this.ch == "}") {
                    // 内联 next() 方法
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }
                    this.currentDepth -= 1;
                    return object;
                }
                while (this.ch) {
                    // 解析键
                    if (this.ch != "\"") {
                        this.error("Expected '\"' at the beginning of a key");
                    }
                    var keyStrParts:Array = [];
                    // 初始化字符串解析
                    // 内联 str() 方法逻辑
                    // Assuming the current character is the starting quote
                    // Move past the opening quote
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }
                    while (this.ch) {
                        if (this.ch == "\"") {
                            // Move past the closing quote
                            if (this.at >= this.textLength) {
                                this.ch = "";
                            } else {
                                this.ch = this.charArray[this.at];
                                this.at += 1;
                            }
                            break;
                        }
                        if (this.ch == "\\") {
                            // Move past the backslash
                            if (this.at >= this.textLength) {
                                this.ch = "";
                            } else {
                                this.ch = this.charArray[this.at];
                                this.at += 1;
                            }
                            switch (this.ch) {
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
                                        if (this.at >= this.textLength) {
                                            this.ch = "";
                                        } else {
                                            this.ch = this.charArray[this.at];
                                            this.at += 1;
                                        }
                                        hexDigit = parseInt(this.ch, 16);
                                        if (!isFinite(hexDigit)) {
                                            this.error("Invalid Unicode escape sequence");
                                        }
                                        unicodeValue = unicodeValue * 16 + hexDigit;
                                    }
                                    keyStrParts.push(String.fromCharCode(unicodeValue));
                                    continue;
                                default:
                                    keyStrParts.push(this.ch);
                                    break;
                            }
                            // Move to the next character after escape
                            if (this.at >= this.textLength) {
                                this.ch = "";
                            } else {
                                this.ch = this.charArray[this.at];
                                this.at += 1;
                            }
                        } else {
                            keyStrParts.push(this.ch);
                            // Move to the next character
                            if (this.at >= this.textLength) {
                                this.ch = "";
                            } else {
                                this.ch = this.charArray[this.at];
                                this.at += 1;
                            }
                        }
                    }
                    var key:String = keyStrParts.join("");

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
                    if (this.ch != ":") {
                        this.error("Expected ':' after key");
                    }
                    // Move past ':'
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }

                    // Parse the value
                    result = this.value();
                    object[key] = result;

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

                    if (this.ch == "}") {
                        // Move past '}'
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                        this.currentDepth -= 1;
                        return object;
                    }
                    if (this.ch != ",") {
                        this.error("Expected ',' or '}'");
                    }
                    // Move past ','
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }

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
                }
                this.error("Unterminated object");
                break;
            case "[":
                // 解析数组
                var array:Array = [];
                // Move past '['
                if (this.at >= this.textLength) {
                    this.ch = "";
                } else {
                    this.ch = this.charArray[this.at];
                    this.at += 1;
                }

                // 内联 white() 方法
                while (this.ch <= " " && this.ch != "") {
                    // Move past whitespace
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }
                }

                if (this.ch == "]") {
                    // Move past ']'
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }
                    this.currentDepth -= 1;
                    return array;
                }
                while (this.ch) {
                    // Parse the value
                    array.push(this.value());

                    // 内联 white() 方法
                    while (this.ch <= " " && this.ch != "") {
                        // Move past whitespace
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    }

                    if (this.ch == "]") {
                        // Move past ']'
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                        this.currentDepth -= 1;
                        return array;
                    }
                    if (this.ch != ",") {
                        this.error("Expected ',' or ']'");
                    }
                    // Move past ','
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }

                    // 内联 white() 方法
                    while (this.ch <= " " && this.ch != "") {
                        // Move past whitespace
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    }
                }
                this.error("Unterminated array");
                break;
            case "\"":
                // 解析字符串
                var resultStrParts:Array = [];
                // Move past opening quote
                if (this.at >= this.textLength) {
                    this.ch = "";
                } else {
                    this.ch = this.charArray[this.at];
                    this.at += 1;
                }
                while (this.ch) {
                    if (this.ch == "\"") {
                        // Move past closing quote
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                        break;
                    }
                    if (this.ch == "\\") {
                        // Move past backslash
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                        switch (this.ch) {
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
                                    if (this.at >= this.textLength) {
                                        this.ch = "";
                                    } else {
                                        this.ch = this.charArray[this.at];
                                        this.at += 1;
                                    }
                                    hexDigit = parseInt(this.ch, 16);
                                    if (!isFinite(hexDigit)) {
                                        this.error("Invalid Unicode escape sequence");
                                    }
                                    unicodeValue = unicodeValue * 16 + hexDigit;
                                }
                                resultStrParts.push(String.fromCharCode(unicodeValue));
                                continue;
                            default:
                                resultStrParts.push(this.ch);
                                break;
                        }
                        // Move to the next character after escape
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    } else {
                        resultStrParts.push(this.ch);
                        // Move to the next character
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    }
                }
                this.currentDepth -= 1;
                return resultStrParts.join("");
            case "-":
                // 解析负数
                numberStr = "-";
                // Move past '-'
                if (this.at >= this.textLength) {
                    this.ch = "";
                } else {
                    this.ch = this.charArray[this.at];
                    this.at += 1;
                }
                while (this.ch >= "0" && this.ch <= "9") {
                    numberStr += this.ch;
                    // Move to next character
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }
                }
                if (this.ch == ".") {
                    numberStr += ".";
                    // Move past '.'
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }
                    while (this.ch >= "0" && this.ch <= "9") {
                        numberStr += this.ch;
                        // Move to next character
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    }
                }
                if (this.ch == "e" || this.ch == "E") {
                    numberStr += this.ch;
                    // Move past 'e' or 'E'
                    if (this.at >= this.textLength) {
                        this.ch = "";
                    } else {
                        this.ch = this.charArray[this.at];
                        this.at += 1;
                    }
                    if (this.ch == "-" || this.ch == "+") {
                        numberStr += this.ch;
                        // Move past '-' or '+'
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    }
                    while (this.ch >= "0" && this.ch <= "9") {
                        numberStr += this.ch;
                        // Move to next character
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    }
                }
                numValue = Number(numberStr);
                if (isNaN(numValue)) {
                    this.error("Bad number");
                }
                this.currentDepth -= 1;
                return numValue;
            default:
                if (this.ch >= "0" && this.ch <= "9") {
                    // 解析正数
                    var numberStrDefault:String = "";
                    while (this.ch >= "0" && this.ch <= "9") {
                        numberStrDefault += this.ch;
                        // Move to next character
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    }
                    if (this.ch == ".") {
                        numberStrDefault += ".";
                        // Move past '.'
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                        while (this.ch >= "0" && this.ch <= "9") {
                            numberStrDefault += this.ch;
                            // Move to next character
                            if (this.at >= this.textLength) {
                                this.ch = "";
                            } else {
                                this.ch = this.charArray[this.at];
                                this.at += 1;
                            }
                        }
                    }
                    if (this.ch == "e" || this.ch == "E") {
                        numberStrDefault += this.ch;
                        // Move past 'e' or 'E'
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                        if (this.ch == "-" || this.ch == "+") {
                            numberStrDefault += this.ch;
                            // Move past '-' or '+'
                            if (this.at >= this.textLength) {
                                this.ch = "";
                            } else {
                                this.ch = this.charArray[this.at];
                                this.at += 1;
                            }
                        }
                        while (this.ch >= "0" && this.ch <= "9") {
                            numberStrDefault += this.ch;
                            // Move to next character
                            if (this.at >= this.textLength) {
                                this.ch = "";
                            } else {
                                this.ch = this.charArray[this.at];
                                this.at += 1;
                            }
                        }
                    }
                    numValueDefault = Number(numberStrDefault);
                    if (isNaN(numValueDefault)) {
                        this.error("Bad number");
                    }
                    this.currentDepth -= 1;
                    return numValueDefault;
                } else if (this.ch >= "a" && this.ch <= "z") {
                    // 解析字面量：true, false, null
                    word = "";
                    while (this.ch >= "a" && this.ch <= "z") {
                        word += this.ch;
                        // Move to next character
                        if (this.at >= this.textLength) {
                            this.ch = "";
                        } else {
                            this.ch = this.charArray[this.at];
                            this.at += 1;
                        }
                    }
                    switch (word) {
                        case "true":
                            this.currentDepth -= 1;
                            return true;
                        case "false":
                            this.currentDepth -= 1;
                            return false;
                        case "null":
                            this.currentDepth -= 1;
                            return null;
                        default:
                            this.error("Unexpected token: " + word);
                    }
                } else {
                    this.error("Unexpected character: " + this.ch);
                }
        }
        this.currentDepth -= 1;
        return null; // 为了避免编译警告
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



/*
// --- 测试 JSON 和 FastJSON 类的正确性和性能 ---

// 定义测试数据
var tcpData:Object = new Object();
tcpData.userId = 12345;
tcpData.userName = "Player1";
tcpData.level = 10;
tcpData.stats = new Object();
tcpData.stats.hp = 100;
tcpData.stats.mp = 50;
tcpData.stats.attack = 15;
tcpData.stats.defense = 8;

// 添加 inventory 数组
tcpData.inventory = new Array();
var item1:Object = new Object();
item1.id = 101;
item1.name = "Health Potion";
item1.quantity = 3;
tcpData.inventory.push(item1);

var item2:Object = new Object();
item2.id = 102;
item2.name = "Mana Potion";
item2.quantity = 2;
tcpData.inventory.push(item2);

var item3:Object = new Object();
item3.id = 103;
item3.name = "Sword";
item3.quantity = 1;
tcpData.inventory.push(item3);

// 添加 quests 数组
tcpData.quests = new Array();
var quest1:Object = new Object();
quest1.id = 201;
quest1.title = "Defeat Goblins";
quest1.progress = new Object();
quest1.progress.current = 5;
quest1.progress.total = 10;
tcpData.quests.push(quest1);

// 定义复杂对象用于测试
var complexObject:Object = new Object();
complexObject.userId = 12345;
complexObject.userName = "Player1";
complexObject.level = 10;
complexObject.stats = new Object();
complexObject.stats.hp = 100;
complexObject.stats.mp = 50;
complexObject.stats.attack = 15;
complexObject.stats.defense = 8;
complexObject.inventory = [
    {id: 101, name: "Health Potion", quantity: 3},
    {id: 102, name: "Mana Potion", quantity: 2},
    {id: 103, name: "Sword", quantity: 1}
];
complexObject.quests = [
    {
        id: 201,
        title: "Defeat Goblins",
        progress: {
            current: 5,
            total: 10
        }
    }
];

// 定义测试用例
var testCases:Array = [
    // 原始测试用例
    {input: 12345, description: "Integer"},
    {input: 123.45, description: "Float"},
    {input: "hello world", description: "String"},
    {input: true, description: "Boolean true"},
    {input: false, description: "Boolean false"},
    {input: null, description: "Null"},
    {input: "Line1\nLine2\tTabbed", description: "Newline and tabbed"},
    {input: "Hello \"World\"", description: "Escaped quotes"},
    {input: "Hello 你好", description: "Unicode characters"},
    {input: {name:"Alice", age:30, isActive:true}, description: "Simple object"},
    {input: [1, 2, 3, 4, 5], description: "Simple array"},
    {input: {user:{id:123, info:{name:"Alice", active:true}}}, description: "Nested object"},
    {input: [[1, 2], [3, 4], [5, 6]], description: "Nested array"},
    {input: complexObject, description: "Complex object"},
    {input: {}, description: "Empty object"},
    {input: [], description: "Empty array"},
    {input: [1, null, 3, null, 5], description: "Sparse array"},
    {input: {id:123, name:null, active:true}, description: "Object with null"},
    // 无效 JSON 测试用例
    {input: "{\"name\":\"Alice\", \"age\":30", description: "Unfinished object"},
    {input: "[1, 2, 3", description: "Unfinished array"},
    {input: "{\"name\":\"Alice\", \"age\":30, \"active\":yes}", description: "Invalid JSON"}
];

// Helper function: 序列化输出对象为字符串用于显示
function serializeOutput(obj:Object):String {
    if (obj == null) return "null";
    if (typeof obj == "string") return "\"" + obj + "\"";
    if (typeof obj == "number" || typeof obj == "boolean") return String(obj);
    if (obj instanceof Array) {
        var arrStr:String = "[";
        for (var i:Number = 0; i < obj.length; i++) {
            if (i > 0) arrStr += ", ";
            arrStr += serializeOutput(obj[i]);
        }
        arrStr += "]";
        return arrStr;
    }
    if (typeof obj == "object") {
        var objStr:String = "{";
        var isFirst:Boolean = true;
        for (var key:String in obj) {
            if (!isFirst) objStr += ", ";
            isFirst = false;
            objStr += "\"" + key + "\":" + serializeOutput(obj[key]);
        }
        objStr += "}";
        return objStr;
    }
    return "";
}

// 创建 JSON 和 FastJSON 实例
var originalJSON = new JSON(false); // 假设原始 JSON 类支持构造函数参数控制模式
var fastJSON = new FastJSON(); // 假设 FastJSON 类无构造参数

// 执行功能测试
trace("=== 功能测试 ===");
for (var i:Number = 0; i < testCases.length; i++) {
    var testCase:Object = testCases[i];
    var input:Object = testCase.input;
    var description:String = testCase.description;
    var outputJSON:Object;
    var outputFastJSON:Object;
    var serializedJSON:String;
    var serializedFastJSON:String;
    
    trace("\n--- Test Case: " + description + " ---");
    
    try {
        // 使用原始 JSON 类序列化
        serializedJSON = originalJSON.stringify(input);
        // 使用原始 JSON 类反序列化
        outputJSON = originalJSON.parse(serializedJSON);
        
        // 显示原始 JSON 类结果
        trace("Original JSON | Serialized: " + serializedJSON);
        trace("Original JSON | Parsed Output: " + serializeOutput(outputJSON));
    } catch (e:Error) {
        trace("Original JSON | Error: " + e.message);
    }
    
    try {
        // 使用 FastJSON 类序列化
        serializedFastJSON = fastJSON.stringify(input);
        // 使用 FastJSON 类反序列化
        outputFastJSON = fastJSON.parse(serializedFastJSON);
        
        // 显示 FastJSON 类结果
        trace("FastJSON     | Serialized: " + serializedFastJSON);
        trace("FastJSON     | Parsed Output: " + serializeOutput(outputFastJSON));
    } catch (e:Error) {
        trace("FastJSON     | Error: " + e.message);
    }
}

// --- 性能测试：分别测量序列化和反序列化的时间 ---

// 设置迭代次数
var numIterations:Number = 100;
var jsonSerializeTimes:Array = [];
var jsonDeserializeTimes:Array = [];
var fastJsonSerializeTimes:Array = [];
var fastJsonDeserializeTimes:Array = [];

// 预先序列化一次数据以供反序列化测试使用
var serializedDataJson:String;
var serializedDataFastJSON:String;

try {
    serializedDataJson = originalJSON.stringify(tcpData);
} catch (e:Error) {
    trace("Error serializing with Original JSON: " + e.message);
}

try {
    serializedDataFastJSON = fastJSON.stringify(tcpData);
} catch (e:Error) {
    trace("Error serializing with FastJSON: " + e.message);
}

// 测试原始 JSON 类性能：序列化
trace("\n=== 性能测试：原始 JSON 类序列化 ===");
for (var j:Number = 0; j < numIterations; j++) {
    var startTime:Number = getTimer();

    // 使用原始 JSON 类序列化
    var tempSerializedJson:String = originalJSON.stringify(tcpData);

    var endTime:Number = getTimer();
    jsonSerializeTimes.push(endTime - startTime);
}

// 测试原始 JSON 类性能：反序列化
trace("\n=== 性能测试：原始 JSON 类反序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeDeser:Number = getTimer();

    // 使用原始 JSON 类反序列化
    var tempDeserializedJson:Object = originalJSON.parse(serializedDataJson);

    var endTimeDeser:Number = getTimer();
    jsonDeserializeTimes.push(endTimeDeser - startTimeDeser);
}

// 测试 FastJSON 类性能：序列化
trace("\n=== 性能测试：FastJSON 类序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeFastSer:Number = getTimer();

    // 使用 FastJSON 类序列化
    var tempSerializedFastJSON:String = fastJSON.stringify(tcpData);

    var endTimeFastSer:Number = getTimer();
    fastJsonSerializeTimes.push(endTimeFastSer - startTimeFastSer);
}

// 测试 FastJSON 类性能：反序列化
trace("\n=== 性能测试：FastJSON 类反序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeFastDeser:Number = getTimer();

    // 使用 FastJSON 类反序列化
    var tempDeserializedFastJSON:Object = fastJSON.parse(serializedDataFastJSON);

    var endTimeFastDeser:Number = getTimer();
    fastJsonDeserializeTimes.push(endTimeFastDeser - startTimeFastDeser);
}

// 定义统计函数
function calculateStatistics(times:Array):Object {
    var stats:Object = new Object();

    if (times.length == 0) {
        stats.totalTime = 0;
        stats.maxTime = 0;
        stats.minTime = 0;
        stats.avgTime = 0;
        stats.variance = 0;
        stats.stdDeviation = 0;
        return stats;
    }

    stats.totalTime = 0;
    stats.maxTime = times[0];
    stats.minTime = times[0];

    // Calculate total time, max, and min time
    for (var k:Number = 0; k < times.length; k++) {
        var cycleTime:Number = times[k];
        stats.totalTime += cycleTime;
        if (cycleTime > stats.maxTime) stats.maxTime = cycleTime;
        if (cycleTime < stats.minTime) stats.minTime = cycleTime;
    }

    // Calculate average time
    stats.avgTime = stats.totalTime / times.length;

    // Calculate variance and standard deviation
    var varianceSum:Number = 0;
    for (k = 0; k < times.length; k++) {
        varianceSum += Math.pow(times[k] - stats.avgTime, 2);
    }
    stats.variance = varianceSum / times.length;
    stats.stdDeviation = Math.sqrt(stats.variance);

    return stats;
}

// 计算并显示原始 JSON 类性能统计
var jsonSerStats:Object = calculateStatistics(jsonSerializeTimes);
var jsonDeserStats:Object = calculateStatistics(jsonDeserializeTimes);
trace("\n--- 原始 JSON 类性能统计 ---");
trace("序列化 - " + numIterations + " 次总时间: " + jsonSerStats.totalTime + " ms");
trace("序列化 - 平均每次时间: " + jsonSerStats.avgTime + " ms");
trace("序列化 - 最大时间: " + jsonSerStats.maxTime + " ms");
trace("序列化 - 最小时间: " + jsonSerStats.minTime + " ms");
trace("序列化 - 方差: " + jsonSerStats.variance + " ms^2");
trace("序列化 - 标准差: " + jsonSerStats.stdDeviation + " ms");

trace("反序列化 - " + numIterations + " 次总时间: " + jsonDeserStats.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + jsonDeserStats.avgTime + " ms");
trace("反序列化 - 最大时间: " + jsonDeserStats.maxTime + " ms");
trace("反序列化 - 最小时间: " + jsonDeserStats.minTime + " ms");
trace("反序列化 - 方差: " + jsonDeserStats.variance + " ms^2");
trace("反序列化 - 标准差: " + jsonDeserStats.stdDeviation + " ms");

// 计算并显示 FastJSON 类性能统计
var fastJsonSerStats:Object = calculateStatistics(fastJsonSerializeTimes);
var fastJsonDeserStats:Object = calculateStatistics(fastJsonDeserializeTimes);
trace("\n--- FastJSON 类性能统计 ---");
trace("序列化 - " + numIterations + " 次总时间: " + fastJsonSerStats.totalTime + " ms");
trace("序列化 - 平均每次时间: " + fastJsonSerStats.avgTime + " ms");
trace("序列化 - 最大时间: " + fastJsonSerStats.maxTime + " ms");
trace("序列化 - 最小时间: " + fastJsonSerStats.minTime + " ms");
trace("序列化 - 方差: " + fastJsonSerStats.variance + " ms^2");
trace("序列化 - 标准差: " + fastJsonSerStats.stdDeviation + " ms");

trace("反序列化 - " + numIterations + " 次总时间: " + fastJsonDeserStats.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + fastJsonDeserStats.avgTime + " ms");
trace("反序列化 - 最大时间: " + fastJsonDeserStats.maxTime + " ms");
trace("反序列化 - 最小时间: " + fastJsonDeserStats.minTime + " ms");
trace("反序列化 - 方差: " + fastJsonDeserStats.variance + " ms^2");
trace("反序列化 - 标准差: " + fastJsonDeserStats.stdDeviation + " ms");

// 显示示例序列化数据
trace("\nSerialized data example (Original JSON): " + serializedDataJson);
trace("Deserialized data example, userName (Original JSON): " + (jsonDeserStats.minTime >= 0 ? originalJSON.parse(serializedDataJson).userName : "null"));
trace("Serialized data example (FastJSON): " + serializedDataFastJSON);
trace("Deserialized data example, userName (FastJSON): " + (fastJsonDeserStats.minTime >= 0 ? fastJSON.parse(serializedDataFastJSON).userName : "null"));

// --- 扩展测试：缓存无效情况下的性能测试 ---

trace("\n=== 扩展测试：缓存无效情况下的性能测试 ===");

// 定义一个函数，用于生成全新的测试对象
function generateUniqueObject():Object {
    var obj:Object = new Object();
    obj.userId = Math.floor(Math.random() * 100000);
    obj.userName = "Player" + Math.floor(Math.random() * 1000);
    obj.level = Math.floor(Math.random() * 100);
    obj.stats = new Object();
    obj.stats.hp = Math.floor(Math.random() * 500);
    obj.stats.mp = Math.floor(Math.random() * 500);
    obj.stats.attack = Math.floor(Math.random() * 100);
    obj.stats.defense = Math.floor(Math.random() * 100);
    
    // 添加 inventory 数组
    obj.inventory = new Array();
    var numItems:Number = Math.floor(Math.random() * 10) + 1; // 1 到 10 个物品
    for (var m:Number = 0; m < numItems; m++) {
        var item:Object = new Object();
        item.id = 100 + m;
        item.name = "Item" + m;
        item.quantity = Math.floor(Math.random() * 20) + 1;
        obj.inventory.push(item);
    }
    
    // 添加 quests 数组
    obj.quests = new Array();
    var numQuests:Number = Math.floor(Math.random() * 5) + 1; // 1 到 5 个任务
    for (m = 0; m < numQuests; m++) {
        var quest:Object = new Object();
        quest.id = 200 + m;
        quest.title = "Quest " + m;
        quest.progress = new Object();
        quest.progress.current = Math.floor(Math.random() * 100);
        quest.progress.total = 100;
        obj.quests.push(quest);
    }
    
    return obj;
}

// 定义扩展测试用例数组（每次都是新对象）
var uniqueTestCases:Array = [];
for (i = 0; i < 50; i++) { // 创建 50 个唯一测试用例
    uniqueTestCases.push({input: generateUniqueObject(), description: "Unique object " + (i+1)});
}

// 执行扩展功能测试
trace("\n=== 扩展功能测试：缓存无效情况下 ===");
for (i = 0; i < uniqueTestCases.length; i++) {
    var uniqueTestCase:Object = uniqueTestCases[i];
    var uniqueInput:Object = uniqueTestCase.input;
    var uniqueDescription:String = uniqueTestCase.description;
    var uniqueOutputJSON:Object;
    var uniqueOutputFastJSON:Object;
    var uniqueSerializedJSON:String;
    var uniqueSerializedFastJSON:String;
    
    trace("\n--- Test Case: " + uniqueDescription + " ---");
    
    try {
        // 使用原始 JSON 类序列化
        uniqueSerializedJSON = originalJSON.stringify(uniqueInput);
        // 使用原始 JSON 类反序列化
        uniqueOutputJSON = originalJSON.parse(uniqueSerializedJSON);
        
        // 显示原始 JSON 类结果
        //trace("Original JSON | Serialized: " + uniqueSerializedJSON);
        //trace("Original JSON | Parsed Output: " + serializeOutput(uniqueOutputJSON));
    } catch (e:Error) {
        trace("Original JSON | Error: " + e.message);
    }
    
    try {
        // 使用 FastJSON 类序列化
        uniqueSerializedFastJSON = fastJSON.stringify(uniqueInput);
        // 使用 FastJSON 类反序列化
        uniqueOutputFastJSON = fastJSON.parse(uniqueSerializedFastJSON);
        
        // 显示 FastJSON 类结果
        //trace("FastJSON     | Serialized: " + uniqueSerializedFastJSON);
        //trace("FastJSON     | Parsed Output: " + serializeOutput(uniqueOutputFastJSON));
    } catch (e:Error) {
        trace("FastJSON     | Error: " + e.message);
    }
}

// --- 性能测试：缓存无效情况下的序列化和反序列化时间 ---

// 设置扩展测试迭代次数
var uniqueNumIterations:Number = 100;
var jsonSerializeTimesUnique:Array = [];
var jsonDeserializeTimesUnique:Array = [];
var fastJsonSerializeTimesUnique:Array = [];
var fastJsonDeserializeTimesUnique:Array = [];

// 生成独立的序列化和反序列化数据
var serializedDataJsonUnique:Array = [];
var serializedDataFastJSONUnique:Array = [];

for (i = 0; i < uniqueNumIterations; i++) {
    var uniqueObj:Object = generateUniqueObject();
    try {
        var serializedJsonUnique:String = originalJSON.stringify(uniqueObj);
        serializedDataJsonUnique.push(serializedJsonUnique);
    } catch (e:Error) {
        serializedDataJsonUnique.push("Error");
    }
    
    try {
        var serializedFastJSONUnique:String = fastJSON.stringify(uniqueObj);
        serializedDataFastJSONUnique.push(serializedFastJSONUnique);
    } catch (e:Error) {
        serializedDataFastJSONUnique.push("Error");
    }
}

// 测试原始 JSON 类性能：序列化（缓存无效）
trace("\n=== 扩展性能测试：原始 JSON 类序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var startTimeUniqueSer:Number = getTimer();

    // 使用原始 JSON 类序列化
    var tempSerializedJsonUnique:String = originalJSON.stringify(generateUniqueObject());

    var endTimeUniqueSer:Number = getTimer();
    jsonSerializeTimesUnique.push(endTimeUniqueSer - startTimeUniqueSer);
}

// 测试原始 JSON 类性能：反序列化（缓存无效）
trace("\n=== 扩展性能测试：原始 JSON 类反序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var uniqueSerializedJsonUnique:String = originalJSON.stringify(generateUniqueObject());
    var startTimeUniqueDeser:Number = getTimer();

    // 使用原始 JSON 类反序列化
    var tempDeserializedJsonUnique:Object = originalJSON.parse(uniqueSerializedJsonUnique);

    var endTimeUniqueDeser:Number = getTimer();
    jsonDeserializeTimesUnique.push(endTimeUniqueDeser - startTimeUniqueDeser);
}

// 测试 FastJSON 类性能：序列化（缓存无效）
trace("\n=== 扩展性能测试：FastJSON 类序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var startTimeFastSerUnique:Number = getTimer();

    // 使用 FastJSON 类序列化
    var tempSerializedFastJSONUnique:String = fastJSON.stringify(generateUniqueObject());

    var endTimeFastSerUnique:Number = getTimer();
    fastJsonSerializeTimesUnique.push(endTimeFastSerUnique - startTimeFastSerUnique);
}

// 测试 FastJSON 类性能：反序列化（缓存无效）
trace("\n=== 扩展性能测试：FastJSON 类反序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var uniqueSerializedFastJSONUnique:String = fastJSON.stringify(generateUniqueObject());
    var startTimeFastDeserUnique:Number = getTimer();

    // 使用 FastJSON 类反序列化
    var tempDeserializedFastJSONUnique:Object = fastJSON.parse(uniqueSerializedFastJSONUnique);

    var endTimeFastDeserUnique:Number = getTimer();
    fastJsonDeserializeTimesUnique.push(endTimeFastDeserUnique - startTimeFastDeserUnique);
}

// 计算并显示扩展测试性能统计
var jsonSerStatsUnique:Object = calculateStatistics(jsonSerializeTimesUnique);
var jsonDeserStatsUnique:Object = calculateStatistics(jsonDeserializeTimesUnique);
trace("\n--- 扩展测试：原始 JSON 类性能统计（缓存无效） ---");
trace("序列化 - " + uniqueNumIterations + " 次总时间: " + jsonSerStatsUnique.totalTime + " ms");
trace("序列化 - 平均每次时间: " + jsonSerStatsUnique.avgTime + " ms");
trace("序列化 - 最大时间: " + jsonSerStatsUnique.maxTime + " ms");
trace("序列化 - 最小时间: " + jsonSerStatsUnique.minTime + " ms");
trace("序列化 - 方差: " + jsonSerStatsUnique.variance + " ms^2");
trace("序列化 - 标准差: " + jsonSerStatsUnique.stdDeviation + " ms");

trace("反序列化 - " + uniqueNumIterations + " 次总时间: " + jsonDeserStatsUnique.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + jsonDeserStatsUnique.avgTime + " ms");
trace("反序列化 - 最大时间: " + jsonDeserStatsUnique.maxTime + " ms");
trace("反序列化 - 最小时间: " + jsonDeserStatsUnique.minTime + " ms");
trace("反序列化 - 方差: " + jsonDeserStatsUnique.variance + " ms^2");
trace("反序列化 - 标准差: " + jsonDeserStatsUnique.stdDeviation + " ms");

var fastJsonSerStatsUnique:Object = calculateStatistics(fastJsonSerializeTimesUnique);
var fastJsonDeserStatsUnique:Object = calculateStatistics(fastJsonDeserializeTimesUnique);
trace("\n--- 扩展测试：FastJSON 类性能统计（缓存无效） ---");
trace("序列化 - " + uniqueNumIterations + " 次总时间: " + fastJsonSerStatsUnique.totalTime + " ms");
trace("序列化 - 平均每次时间: " + fastJsonSerStatsUnique.avgTime + " ms");
trace("序列化 - 最大时间: " + fastJsonSerStatsUnique.maxTime + " ms");
trace("序列化 - 最小时间: " + fastJsonSerStatsUnique.minTime + " ms");
trace("序列化 - 方差: " + fastJsonSerStatsUnique.variance + " ms^2");
trace("序列化 - 标准差: " + fastJsonSerStatsUnique.stdDeviation + " ms");

trace("反序列化 - " + uniqueNumIterations + " 次总时间: " + fastJsonDeserStatsUnique.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + fastJsonDeserStatsUnique.avgTime + " ms");
trace("反序列化 - 最大时间: " + fastJsonDeserStatsUnique.maxTime + " ms");
trace("反序列化 - 最小时间: " + fastJsonDeserStatsUnique.minTime + " ms");
trace("反序列化 - 方差: " + fastJsonDeserStatsUnique.variance + " ms^2");
trace("反序列化 - 标准差: " + fastJsonDeserStatsUnique.stdDeviation + " ms");

// 显示示例序列化数据
trace("\nSerialized data example (Original JSON): " + serializedDataJson);
trace("Deserialized data example, userName (Original JSON): " + (jsonDeserStats.minTime >= 0 ? originalJSON.parse(serializedDataJson).userName : "null"));
trace("Serialized data example (FastJSON): " + serializedDataFastJSON);
trace("Deserialized data example, userName (FastJSON): " + (fastJsonDeserStats.minTime >= 0 ? fastJSON.parse(serializedDataFastJSON).userName : "null"));

*/