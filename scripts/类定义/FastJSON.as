class FastJSON {
    public var text;
    public var ch = "";
    public var at = 0;

    // 最大解析深度以防止栈溢出
    public var maxDepth = 256; 
    private var currentDepth = 0;

    /**
     * 构造函数
     */
    public function FastJSON() {
        // 此简化版本无需初始化
    }

    /**
     * 将 AS2 对象序列化为 FastJSON 字符串
     * @param arg 要序列化的对象
     * @return FastJSON 字符串
     */
    public function stringify(arg) {
        var serializedValue;
        var result = ""; // 直接拼接字符串
        var index;

        switch (typeof arg) {
            case "object":
                if (arg) {
                    if (arg instanceof Array) {
                        result = "[";
                        for (index = 0; index < arg.length; index++) {
                            serializedValue = this.stringify(arg[index]);
                            if (index > 0) {
                                result += ",";
                            }
                            result += serializedValue;
                        }
                        return result + "]";
                    }
                    if (typeof arg.toString != "undefined") {
                        result = "{";
                        var isFirst = true;
                        for (index in arg) {
                            serializedValue = arg[index];
                            if (typeof serializedValue != "undefined" && typeof serializedValue != "function") {
                                if (!isFirst) {
                                    result += ",";
                                }
                                isFirst = false;
                                
                                // 内联 stringifyString 方法用于序列化键
                                var keyStr = "\"";
                                var key = index;
                                var keyLength = key.length;
                                var keyIndex = 0;
                                while (keyIndex < keyLength) {
                                    var keyChar = key.charAt(keyIndex);
                                    if (keyChar >= " ") {
                                        if (keyChar == "\\" || keyChar == "\"") {
                                            keyStr += "\\" + keyChar;
                                        } else {
                                            keyStr += keyChar;
                                        }
                                    } else {
                                        switch (keyChar) {
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
                                                var keyCharCode = keyChar.charCodeAt();
                                                var keyHexCode = keyCharCode.toString(16);
                                                while (keyHexCode.length < 4) {
                                                    keyHexCode = "0" + keyHexCode;
                                                }
                                                keyStr += "\\u" + keyHexCode;
                                        }
                                    }
                                    keyIndex += 1;
                                }
                                keyStr += "\"";
                                
                                // 序列化值
                                var valueStr = this.stringify(serializedValue);
                                result += keyStr + ":" + valueStr;
                            }
                        }
                        return result + "}";
                    }
                }
                return "null";
            case "number":
                return !isFinite(arg) ? "null" : String(arg);
            case "string":
                // 内联 stringifyString 方法
                var resultStr = "\"";
                var strLength = arg.length;
                var strIndex = 0;
                while (strIndex < strLength) {
                    var strChar = arg.charAt(strIndex);
                    if (strChar >= " ") {
                        if (strChar == "\\" || strChar == "\"") {
                            resultStr += "\\" + strChar;
                        } else {
                            resultStr += strChar;
                        }
                    } else {
                        switch (strChar) {
                            case "\b":
                                resultStr += "\\b";
                                break;
                            case "\f":
                                resultStr += "\\f";
                                break;
                            case "\n":
                                resultStr += "\\n";
                                break;
                            case "\r":
                                resultStr += "\\r";
                                break;
                            case "\t":
                                resultStr += "\\t";
                                break;
                            default:
                                var strCharCode = strChar.charCodeAt();
                                var strHexCode = strCharCode.toString(16);
                                while (strHexCode.length < 4) {
                                    strHexCode = "0" + strHexCode;
                                }
                                resultStr += "\\u" + strHexCode;
                        }
                    }
                    strIndex += 1;
                }
                resultStr += "\"";
                return resultStr;
            case "boolean":
                return String(arg);
            default:
                return "null";
        }
    }

    /**
     * 抛出错误
     * @param message 错误信息
     */
    public function error(message) {
        throw {name: "FastJSONError", message: message, at: this.at - 1, text: this.text};
    }

    /**
     * 解析字符串
     * @return 解析后的字符串
     */
    public function str() {
        var resultParts = [];
        var unicodeValue;

        if (this.ch == "\"") {
            resultParts.push(""); // 初始化字符串
            // 内联 next() 方法
            if (this.at >= this.text.length) {
                this.ch = ""; // 表示 EOF
            } else {
                this.ch = this.text.charAt(this.at);
                this.at += 1;
            }
            while (this.ch) {
                if (this.ch == "\"") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                    return resultParts.join("");
                }
                if (this.ch == "\\") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                    switch (this.ch) {
                        case "b":
                            resultParts.push("\b");
                            // 内联 next() 方法
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                            break;
                        case "f":
                            resultParts.push("\f");
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                            break;
                        case "n":
                            resultParts.push("\n");
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                            break;
                        case "r":
                            resultParts.push("\r");
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                            break;
                        case "t":
                            resultParts.push("\t");
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                            break;
                        case "u":
                            unicodeValue = 0;
                            // 内联 next() 方法
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                            for (var i = 0; i < 4; i++) {
                                var hexDigit = parseInt(this.ch, 16);
                                if (!isFinite(hexDigit)) {
                                    this.error("Invalid Unicode escape sequence");
                                }
                                unicodeValue = unicodeValue * 16 + hexDigit;
                                // 内联 next() 方法
                                if (this.at >= this.text.length) {
                                    this.ch = "";
                                } else {
                                    this.ch = this.text.charAt(this.at);
                                    this.at += 1;
                                }
                            }
                            resultParts.push(String.fromCharCode(unicodeValue));
                            break;
                        default:
                            resultParts.push(this.ch);
                            // 内联 next() 方法
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                    }
                } else if (this.ch == "") {
                    this.error("Unterminated string");
                } else {
                    resultParts.push(this.ch);
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                }
            }
        }
        this.error("Bad string");
    }

    /**
     * 解析数组
     * @return 解析后的数组
     */
    public function arr() {
        var array = [];
        if (this.ch == "[") {
            // 内联 next() 方法
            if (this.at >= this.text.length) {
                this.ch = "";
            } else {
                this.ch = this.text.charAt(this.at);
                this.at += 1;
            }

            // 内联 white() 方法
            while (this.ch <= " " && this.ch != "") {
                // 内联 next() 方法
                if (this.at >= this.text.length) {
                    this.ch = "";
                } else {
                    this.ch = this.text.charAt(this.at);
                    this.at += 1;
                }
            }

            if (this.ch == "]") {
                // 内联 next() 方法
                if (this.at >= this.text.length) {
                    this.ch = "";
                } else {
                    this.ch = this.text.charAt(this.at);
                    this.at += 1;
                }
                return array;
            }
            while (this.ch) {
                array.push(this.value());
                // 内联 white() 方法
                while (this.ch <= " " && this.ch != "") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                }
                if (this.ch == "]") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                    return array;
                }
                if (this.ch != ",") {
                    this.error("Expected ',' or ']'");
                }
                // 内联 next() 方法
                if (this.at >= this.text.length) {
                    this.ch = "";
                } else {
                    this.ch = this.text.charAt(this.at);
                    this.at += 1;
                }
                // 内联 white() 方法
                while (this.ch <= " " && this.ch != "") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                }
            }
            this.error("Unterminated array");
        }
        this.error("Bad array");
    }

    /**
     * 解析对象
     * @return 解析后的对象
     */
    public function obj() {
        var object = {};
        var key;

        if (this.ch == "{") {
            // 内联 next() 方法
            if (this.at >= this.text.length) {
                this.ch = "";
            } else {
                this.ch = this.text.charAt(this.at);
                this.at += 1;
            }

            // 内联 white() 方法
            while (this.ch <= " " && this.ch != "") {
                // 内联 next() 方法
                if (this.at >= this.text.length) {
                    this.ch = "";
                } else {
                    this.ch = this.text.charAt(this.at);
                    this.at += 1;
                }
            }

            if (this.ch == "}") {
                // 内联 next() 方法
                if (this.at >= this.text.length) {
                    this.ch = "";
                } else {
                    this.ch = this.text.charAt(this.at);
                    this.at += 1;
                }
                return object;
            }
            while (this.ch) {
                key = this.str();
                // 内联 white() 方法
                while (this.ch <= " " && this.ch != "") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                }
                if (this.ch != ":") {
                    this.error("Expected ':' after key");
                }
                // 内联 next() 方法
                if (this.at >= this.text.length) {
                    this.ch = "";
                } else {
                    this.ch = this.text.charAt(this.at);
                    this.at += 1;
                }
                object[key] = this.value();
                // 内联 white() 方法
                while (this.ch <= " " && this.ch != "") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                }
                if (this.ch == "}") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                    return object;
                }
                if (this.ch != ",") {
                    this.error("Expected ',' or '}'");
                }
                // 内联 next() 方法
                if (this.at >= this.text.length) {
                    this.ch = "";
                } else {
                    this.ch = this.text.charAt(this.at);
                    this.at += 1;
                }
                // 内联 white() 方法
                while (this.ch <= " " && this.ch != "") {
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                }
            }
            this.error("Unterminated object");
        }
        this.error("Bad object");
    }

    /**
     * 解析值
     * @return 解析后的值
     */
    public function value() {
        // 内联 white() 方法
        while (this.ch <= " " && this.ch != "") {
            // 内联 next() 方法
            if (this.at >= this.text.length) {
                this.ch = "";
            } else {
                this.ch = this.text.charAt(this.at);
                this.at += 1;
            }
        }

        this.currentDepth += 1;
        if (this.currentDepth > this.maxDepth) {
            this.error("Maximum parsing depth exceeded");
        }
        var result;

        switch (this.ch) {
            case "{":
                result = this.obj();
                break;
            case "[":
                result = this.arr();
                break;
            case "\"":
                result = this.str();
                break;
            case "-":
                // 内联 num() 方法
                var numberStr = "-";
                // 内联 next() 方法
                if (this.at >= this.text.length) {
                    this.ch = "";
                } else {
                    this.ch = this.text.charAt(this.at);
                    this.at += 1;
                }
                while (this.ch >= "0" && this.ch <= "9") {
                    numberStr += this.ch;
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                }
                if (this.ch == ".") {
                    numberStr += ".";
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                    while (this.ch >= "0" && this.ch <= "9") {
                        numberStr += this.ch;
                        // 内联 next() 方法
                        if (this.at >= this.text.length) {
                            this.ch = "";
                        } else {
                            this.ch = this.text.charAt(this.at);
                            this.at += 1;
                        }
                    }
                }
                if (this.ch == "e" || this.ch == "E") {
                    numberStr += this.ch;
                    // 内联 next() 方法
                    if (this.at >= this.text.length) {
                        this.ch = "";
                    } else {
                        this.ch = this.text.charAt(this.at);
                        this.at += 1;
                    }
                    if (this.ch == "-" || this.ch == "+") {
                        numberStr += this.ch;
                        // 内联 next() 方法
                        if (this.at >= this.text.length) {
                            this.ch = "";
                        } else {
                            this.ch = this.text.charAt(this.at);
                            this.at += 1;
                        }
                    }
                    while (this.ch >= "0" && this.ch <= "9") {
                        numberStr += this.ch;
                        // 内联 next() 方法
                        if (this.at >= this.text.length) {
                            this.ch = "";
                        } else {
                            this.ch = this.text.charAt(this.at);
                            this.at += 1;
                        }
                    }
                }
                var numValue = Number(numberStr);
                if (isNaN(numValue)) {
                    this.error("Bad number");
                }
                result = numValue;
                break;
            default:
                if (this.ch >= "0" && this.ch <= "9") {
                    // 内联 num() 方法
                    var numberStrDefault = "";
                    while (this.ch >= "0" && this.ch <= "9") {
                        numberStrDefault += this.ch;
                        // 内联 next() 方法
                        if (this.at >= this.text.length) {
                            this.ch = "";
                        } else {
                            this.ch = this.text.charAt(this.at);
                            this.at += 1;
                        }
                    }
                    if (this.ch == ".") {
                        numberStrDefault += ".";
                        // 内联 next() 方法
                        if (this.at >= this.text.length) {
                            this.ch = "";
                        } else {
                            this.ch = this.text.charAt(this.at);
                            this.at += 1;
                        }
                        while (this.ch >= "0" && this.ch <= "9") {
                            numberStrDefault += this.ch;
                            // 内联 next() 方法
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                        }
                    }
                    if (this.ch == "e" || this.ch == "E") {
                        numberStrDefault += this.ch;
                        // 内联 next() 方法
                        if (this.at >= this.text.length) {
                            this.ch = "";
                        } else {
                            this.ch = this.text.charAt(this.at);
                            this.at += 1;
                        }
                        if (this.ch == "-" || this.ch == "+") {
                            numberStrDefault += this.ch;
                            // 内联 next() 方法
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                        }
                        while (this.ch >= "0" && this.ch <= "9") {
                            numberStrDefault += this.ch;
                            // 内联 next() 方法
                            if (this.at >= this.text.length) {
                                this.ch = "";
                            } else {
                                this.ch = this.text.charAt(this.at);
                                this.at += 1;
                            }
                        }
                    }
                    var numValueDefault = Number(numberStrDefault);
                    if (isNaN(numValueDefault)) {
                        this.error("Bad number");
                    }
                    result = numValueDefault;
                } else if (this.ch >= "a" && this.ch <= "z") {
                    // 内联 word() 方法
                    var word = "";
                    while (this.ch >= "a" && this.ch <= "z") {
                        word += this.ch;
                        // 内联 next() 方法
                        if (this.at >= this.text.length) {
                            this.ch = "";
                        } else {
                            this.ch = this.text.charAt(this.at);
                            this.at += 1;
                        }
                    }
                    switch (word) {
                        case "true":
                            result = true;
                            break;
                        case "false":
                            result = false;
                            break;
                        case "null":
                            result = null;
                            break;
                        default:
                            this.error("Unexpected token: " + word);
                    }
                } else {
                    this.error("Unexpected character: " + this.ch);
                }
        }
        this.currentDepth -= 1;
        return result;
    }

    /**
     * 解析 FastJSON 文本
     * @param inputText 要解析的 FastJSON 字符串
     * @return 解析后的 AS2 对象
     */
    public function parse(inputText) {
        this.text = inputText;
        this.at = 0;
        this.ch = " ";
        this.currentDepth = 0; // 重置深度计数器

        var result = this.value();
        // 内联 white() 方法
        while (this.ch <= " " && this.ch != "") {
            // 内联 next() 方法
            if (this.at >= this.text.length) {
                this.ch = "";
            } else {
                this.ch = this.text.charAt(this.at);
                this.at += 1;
            }
        }
        if (this.ch) {
            this.error("Unexpected trailing characters");
        }

        return result;
    }

    /**
     * 获取下一个字符
     * @return 当前字符
     */
    // 已经内联到各个方法中，不再需要单独的 next() 方法
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
trace("Deserialized data example, userName (Original JSON): " + (jsonDeserializeTimes.length > 0 && jsonDeserStats.minTime >= 0 ? originalJSON.parse(serializedDataJson).userName : "null"));
trace("Serialized data example (FastJSON): " + serializedDataFastJSON);
trace("Deserialized data example, userName (FastJSON): " + (fastJsonDeserStats.minTime >= 0 ? fastJSON.parse(serializedDataFastJSON).userName : "null"));

*/