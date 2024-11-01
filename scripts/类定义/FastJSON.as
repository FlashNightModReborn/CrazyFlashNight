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
        var cacheKey:String = this.generateCacheKey(arg);
        if (this.stringifyCache[cacheKey] != undefined) {
            return this.stringifyCache[cacheKey];
        }
        
        // 使用两个并行数组维护堆栈
        var stackTypes:Array = new Array(64); // 预创建 64 个容量用于中等复杂度对象
        var stackData:Array = new Array(64);
        var stackPtr:Number = 0; // 堆栈指针
        var resultStr:String = ""; // 使用字符串收集序列化片段，替代数组
        
        var current:Object = arg;
        
        // 推入初始元素（移除 parentType 和 isFirst）
        stackTypes[stackPtr] = "value";
        stackData[stackPtr++] = current;
        
        // 声明 propertyKeys 和 propertyValues 在循环外部，并在每次使用前清空
        var propertyKeys:Array = [];
        var propertyValues:Array = [];
        
        while (stackPtr > 0) {
            // 弹出堆栈顶部元素
            stackPtr--;
            var type:String = stackTypes[stackPtr];
            var data:Object = stackData[stackPtr];
            
            switch(type) {
                case "value":
                    switch(typeof data) {
                        case "object":
                            if (data == null) {
                                resultStr += "null";
                            } else if (data instanceof Array) {
                                resultStr += "[";
                                // 推入结束标记
                                stackTypes[stackPtr] = "closeArray";
                                stackData[stackPtr++] = null;
                                // 逆序推入数组元素和逗号
                                for (var i:Number = data.length - 1; i >= 0; i--) {
                                    stackTypes[stackPtr] = "value";
                                    stackData[stackPtr++] = data[i];
                                    if (i > 0) {
                                        stackTypes[stackPtr] = "comma";
                                        stackData[stackPtr++] = null;
                                    }
                                }
                            } else {
                                resultStr += "{";
                                // 推入结束标记
                                stackTypes[stackPtr] = "closeObject";
                                stackData[stackPtr++] = null;
                                // 清空并复用 propertyKeys 和 propertyValues
                                propertyKeys.length = 0;
                                propertyValues.length = 0;
                                for (var k:String in data) {
                                    if (!(k.charAt(0) == "_" && k.charAt(1) == "_")) {
                                        var value:Object = data[k];
                                        if (typeof value != "undefined" && typeof value != "function") {
                                            // 使用两个并行数组存储键和值
                                            propertyKeys[propertyKeys.length] = k;
                                            propertyValues[propertyValues.length] = value;
                                        }
                                    }
                                }
                                // 逆序遍历 propertyKeys 和 propertyValues，以便正确的序列化顺序
                                
                                var lastIndex:Number = propertyKeys.length - 1;
                                
                                // 提前处理最后一个键值对，不添加逗号
                                if (lastIndex >= 0) {
                                    var lastKey:String = propertyKeys[lastIndex];
                                    var lastVal:Object = propertyValues[lastIndex];
                                    
                                    stackTypes[stackPtr] = "value";
                                    stackData[stackPtr++] = lastVal;
                                    
                                    stackTypes[stackPtr] = "key";
                                    stackData[stackPtr++] = lastKey;
                                }
                                
                                // 处理剩余键值对，统一添加逗号
                                for (var pIndex:Number = lastIndex - 1; pIndex >= 0; pIndex--) {
                                    var key:String = propertyKeys[pIndex];
                                    var val:Object = propertyValues[pIndex];
                                    
                                    // 添加逗号
                                    stackTypes[stackPtr] = "comma";
                                    stackData[stackPtr++] = null;
                                    
                                    // 添加值
                                    stackTypes[stackPtr] = "value";
                                    stackData[stackPtr++] = val;
                                    
                                    // 添加键
                                    stackTypes[stackPtr] = "key";
                                    stackData[stackPtr++] = key;
                                }
                            }
                            break;
                        case "string":
                            // 序列化字符串并处理转义
                            var escStr:String = "\"";
                            var str:String = String(data);
                            var len:Number = str.length;
                            for (var si:Number = 0; si < len; si++) {
                                var c:String = str.charAt(si);
                                switch(c) {
                                    case "\\":
                                        escStr += "\\\\";
                                        break;
                                    case "\"":
                                        escStr += "\\\"";
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
                            resultStr += escStr;
                            break;
                        case "number":
                            resultStr += isFinite(data) ? String(data) : "null";
                            break;
                        case "boolean":
                            resultStr += String(data);
                            break;
                        default:
                            resultStr += "null";
                    }
                    break;
                case "key":
                    // 序列化键
                    var keyStr:String = "\"";
                    var keyVal:String = String(data);
                    var keyLen:Number = keyVal.length;
                    for (var ki:Number = 0; ki < keyLen; ki++) {
                        var kc:String = keyVal.charAt(ki);
                        switch(kc) {
                            case "\\":
                                keyStr += "\\\\";
                                break;
                            case "\"":
                                keyStr += "\\\"";
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
                    resultStr += keyStr + ":";
                    break;
                case "comma":
                    resultStr += ",";
                    break;
                case "closeObject":
                    resultStr += "}";
                    break;
                case "closeArray":
                    resultStr += "]";
                    break;
                default:
                    // 不处理其他类型
                    break;
            }
            
            /*
            // 检查是否超出堆栈容量（如果需要）
            if (stackPtr >= stackTypes.length) {
                // 扩展堆栈数组容量（每次增加64）
                var newSize:Number = stackTypes.length + 64;
                stackTypes.length = newSize;
                stackData.length = newSize;
            }
            */
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


