 import org.flashNight.neur.Server.ServerManager;  
 
class JSON implements IJSON{
    public var text;
    public var ch = "";
    public var at = 0;
    public var errors = []; // 用于收集错误信息
    public var lenient; // 宽容解析模式开关

    // 最大解析深度，防止过深嵌套导致的栈溢出
    public var maxDepth = 256; 
    private var currentDepth = 0;

    // 用于跟踪未闭合的结构
    private var stack = [];

    /**
     * 构造函数
     * @param lenientMode 是否启用宽容模式（默认启用）
     */
    public function JSON(lenientMode) {
        this.lenient = (lenientMode != undefined) ? lenientMode : true;
    }

    /**
     * 将 AS2 对象序列化为 JSON 字符串
     * @param arg 要序列化的对象
     * @return JSON 字符串
     */
    public function stringify(arg):String {
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
                                result += ","; // 使用字符串拼接而非数组
                            }
                            result += serializedValue;
                        }
                        return result + "]"; // 拼接数组结束符
                    }
                    if (typeof arg.toString != "undefined") {
                        result = "{";
                        var isFirst = true; // 控制逗号的添加
                        for (index in arg) {
                            if (arg.hasOwnProperty(index)) {
                                serializedValue = arg[index];
                                if (typeof serializedValue != "undefined" && typeof serializedValue != "function") {
                                    if (!isFirst) {
                                        result += ",";
                                    }
                                    isFirst = false;
                                    result += this.stringifyString(index) + ":" + this.stringify(serializedValue);
                                }
                            }
                        }
                        return result + "}"; // 拼接对象结束符
                    }
                }
                return "null";
            case "number":
                return !isFinite(arg) ? "null" : String(arg);
            case "string":
                return this.stringifyString(arg);
            case "boolean":
                return String(arg);
            default:
                return "null";
        }
    }


    /**
     * 将字符串中的特殊字符进行转义并包裹在双引号中
     * @param value 要处理的字符串
     * @return 处理后的字符串
     */
    public function stringifyString(value) {
        var result = "\"";
        var length = value.length;
        var index = 0;
        var char;

        while (index < length) {
            char = value.charAt(index);
            if (char >= " ") {
                if (char == "\\" || char == "\"") {
                    result += "\\" + char; // 直接拼接转义符
                } else {
                    result += char; // 直接拼接字符
                }
            } else {
                switch (char) {
                    case "\b":
                        result += "\\b";
                        break;
                    case "\f":
                        result += "\\f";
                        break;
                    case "\n":
                        result += "\\n";
                        break;
                    case "\r":
                        result += "\\r";
                        break;
                    case "\t":
                        result += "\\t";
                        break;
                    default:
                        var charCode = char.charCodeAt();
                        var hexCode = charCode.toString(16);
                        while (hexCode.length < 4) {
                            hexCode = "0" + hexCode;
                        }
                        result += "\\u" + hexCode;
                }
            }
            index += 1;
        }
        return result + "\"";
    }


    /**
     * 跳过空白字符和注释
     */
    public function white() {
        while (this.ch) {
            if (this.ch <= " ") {
                this.next();
            } else {
                if (this.ch != "/") {
                    break;
                }
                switch (this.next()) {
                    case "/":
                        while (this.next() && this.ch != "\n" && this.ch != "\r") {
                        }
                        break;
                    case "*":
                        this.next();
                        while (true) {
                            if (this.ch) {
                                if (this.ch == "*") {
                                    if (this.next() == "/") {
                                        break;
                                    }
                                } else {
                                    this.next();
                                }
                            } else {
                                this.recordError("Unterminated comment");
                                if (!this.lenient)
                                    this.error("Unterminated comment");
                                break;
                            }
                        }
                        this.next();
                        continue;
                    default:
                        this.recordError("Syntax error");
                        if (!this.lenient)
                            this.error("Syntax error");
                        else
                            return;
                }
            }
        }
    }

    /**
     * 抛出错误（严格模式下使用）
     * @param message 错误信息
     */
    public function error(message) {
        throw {name: "JSONError", message: message, at: this.at - 1, text: this.text};
    }

    /**
     * 记录错误信息（宽容模式下使用）
     * @param message 错误信息
     */
    public function recordError(message) {
        // 避免在相同位置重复记录错误
        if (this.errors.length == 0 || this.errors[this.errors.length - 1].at != this.at - 1) {
            this.errors.push({message: message, at: this.at - 1});
        }
    }

    /**
     * 获取下一个字符
     * @return 当前字符
     */
    public function next() {
        if (this.at >= this.text.length) {
            this.ch = ""; // 表示EOF
            return this.ch;
        }
        this.ch = this.text.charAt(this.at);
        this.at += 1;
        return this.ch;
    }

    /**
     * 解析字符串
     * @return 解析后的字符串
     */
    public function str() {
        var resultParts = [];
        var unicodeValue;

        if (this.ch == "\"") {
            while (this.next()) {
                if (this.ch == "\"") {
                    this.next();
                    return resultParts.join("");
                }
                if (this.ch == "\\") {
                    switch (this.next()) {
                        case "b":
                            resultParts.push("\b");
                            break;
                        case "f":
                            resultParts.push("\f");
                            break;
                        case "n":
                            resultParts.push("\n");
                            break;
                        case "r":
                            resultParts.push("\r");
                            break;
                        case "t":
                            resultParts.push("\t");
                            break;
                        case "u":
                            unicodeValue = 0;
                            for (var i = 0; i < 4; i++) {
                                if (this.ch == "") {
                                    this.recordError("Unexpected end of input in Unicode escape");
                                    if (!this.lenient)
                                        this.error("Unexpected end of input in Unicode escape");
                                    else
                                        break;
                                }
                                var hexDigit = parseInt(this.next(), 16);
                                if (!isFinite(hexDigit)) {
                                    this.recordError("Invalid Unicode escape sequence");
                                    if (!this.lenient)
                                        this.error("Invalid Unicode escape sequence");
                                    else
                                        break;
                                }
                                unicodeValue = unicodeValue * 16 + hexDigit;
                            }
                            resultParts.push(String.fromCharCode(unicodeValue));
                            break;
                        default:
                            resultParts.push(this.ch);
                    }
                } else if (this.ch == "") {
                    // 处理EOF
                    this.recordError("Unterminated string");
                    if (!this.lenient)
                        this.error("Unterminated string");
                    else
                        return resultParts.join("");
                } else {
                    resultParts.push(this.ch);
                }
            }
        }
        this.recordError("Bad string");
        if (!this.lenient)
            this.error("Bad string");
        else
            return resultParts.join("");
    }

    /**
     * 解析数组
     * @return 解析后的数组
     */
    public function arr() {
        var array = [];
        if (this.ch == "[") {
            // 将 '[' 推入栈中
            this.stack.push(']');
            this.next();
            this.white();
            if (this.ch == "]") {
                this.stack.pop(); // 匹配到结束符，弹出栈顶符号
                this.next();
                return array;
            }
            while (this.ch) {
                array.push(this.value());
                this.white();
                if (this.ch == "]") {
                    this.stack.pop(); // 匹配到结束符，弹出栈顶符号
                    this.next();
                    return array;
                }
                if (this.ch != ",") {
                    this.recordError("Expected ',' or ']'");
                    if (!this.lenient)
                        this.error("Expected ',' or ']'");
                    else {
                        if (this.ch == "") {
                            // 处理EOF，自动补全
                            this.recordError("Unexpected end of input in array");
                            this.autoComplete(); // 自动补全缺失的结束符
                            return array;
                        } else {
                            // 跳过意外字符并继续
                            this.next();
                        }
                    }
                } else {
                    this.next();
                    this.white();
                    // 在宽容模式下允许末尾的逗号
                    if (this.lenient && this.ch == "]") {
                        this.stack.pop(); // 匹配到结束符，弹出栈顶符号
                        this.next();
                        return array;
                    }
                }
            }
            // 处理EOF，自动补全
            this.recordError("Unterminated array");
            this.autoComplete(); // 自动补全缺失的结束符
            return array;
        }
        this.recordError("Bad array");
        if (!this.lenient)
            this.error("Bad array");
        else
            return array;
    }

    /**
     * 解析对象
     * @return 解析后的对象
     */
    public function obj() {
        var object = {};
        var key;

        if (this.ch == "{") {
            // 将 '{' 推入栈中
            this.stack.push('}');
            this.next();
            this.white();
            if (this.ch == "}") {
                this.stack.pop(); // 匹配到结束符，弹出栈顶符号
                this.next();
                return object;
            }
            while (this.ch) {
                key = this.str();
                this.white();
                if (this.ch != ":") {
                    this.recordError("Expected ':' after key");
                    if (!this.lenient)
                        this.error("Expected ':' after key");
                    else {
                        if (this.ch == "") {
                            // 处理EOF，自动补全
                            this.recordError("Unexpected end of input after key");
                            this.autoComplete(); // 自动补全缺失的结束符
                            return object;
                        } else {
                            // 尝试跳过意外字符
                            this.next();
                        }
                    }
                } else {
                    this.next();
                }
                object[key] = this.value();
                this.white();
                if (this.ch == "}") {
                    this.stack.pop(); // 匹配到结束符，弹出栈顶符号
                    this.next();
                    return object;
                }
                if (this.ch != ",") {
                    this.recordError("Expected ',' or '}'");
                    if (!this.lenient)
                        this.error("Expected ',' or '}'");
                    else {
                        if (this.ch == "") {
                            // 处理EOF，自动补全
                            this.recordError("Unexpected end of input in object");
                            this.autoComplete(); // 自动补全缺失的结束符
                            return object;
                        } else {
                            // 跳过意外字符并继续
                            this.next();
                        }
                    }
                } else {
                    this.next();
                    this.white();
                    // 在宽容模式下允许末尾的逗号
                    if (this.lenient && this.ch == "}") {
                        this.stack.pop(); // 匹配到结束符，弹出栈顶符号
                        this.next();
                        return object;
                    }
                }
            }
            // 处理EOF，自动补全
            this.recordError("Unterminated object");
            this.autoComplete(); // 自动补全缺失的结束符
            return object;
        }
        this.recordError("Bad object");
        if (!this.lenient)
            this.error("Bad object");
        else
            return object;
    }

    /**
     * 自动补全未闭合的结构
     */
    public function autoComplete() {
        while (this.stack.length > 0) {
            var missingChar = this.stack.pop();
            this.recordError("Auto-completing missing '" + missingChar + "'");
            // 这里可以选择将自动补全的字符添加到文本中，但由于输入已经结束，直接记录错误即可
        }
    }

    /**
     * 解析数字
     * @return 解析后的数字
     */
    public function num() {
        var numberStr = "";
        var numValue;

        if (this.ch == "-") {
            numberStr = "-";
            this.next();
        }
        while (this.ch >= "0" && this.ch <= "9") {
            numberStr += this.ch;
            this.next();
        }
        if (this.ch == ".") {
            numberStr += ".";
            this.next();
            while (this.ch >= "0" && this.ch <= "9") {
                numberStr += this.ch;
                this.next();
            }
        }
        if (this.ch == "e" || this.ch == "E") {
            numberStr += this.ch;
            this.next();
            if (this.ch == "-" || this.ch == "+") {
                numberStr += this.ch;
                this.next();
            }
            while (this.ch >= "0" && this.ch <= "9") {
                numberStr += this.ch;
                this.next();
            }
        }
        numValue = Number(numberStr);
        if (isNaN(numValue)) {
            this.recordError("Bad number");
            if (!this.lenient)
                this.error("Bad number");
            else
                return null;
        }
        return numValue;
    }

    /**
     * 解析布尔值和 null
     * @return 解析后的值
     */
    public function word() {
        var word = "";
        while (this.ch >= "a" && this.ch <= "z") {
            word += this.ch;
            this.next();
        }
        switch (word) {
            case "true":
                return true;
            case "false":
                return false;
            case "null":
                return null;
            default:
                this.recordError("Unexpected token: " + word);
                if (!this.lenient)
                    this.error("Unexpected token: " + word);
                else
                    return null;
        }
    }

    /**
     * 解析值
     * @return 解析后的值
     */
    public function value() {
        this.white();
        this.currentDepth += 1;
        if (this.currentDepth > this.maxDepth) {
            this.recordError("Maximum parsing depth exceeded");
            if (!this.lenient)
                this.error("Maximum parsing depth exceeded");
            else {
                this.currentDepth -= 1;
                return null;
            }
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
                result = this.num();
                break;
            default:
                if (this.ch >= "0" && this.ch <= "9") {
                    result = this.num();
                } else if (this.ch >= "a" && this.ch <= "z") {
                    result = this.word();
                } else if (this.ch == "") {
                    // 处理EOF
                    if (this.stack.length > 0) {
                        this.recordError("Unexpected end of input");
                        this.autoComplete(); // 自动补全缺失的结束符
                    }
                    if (!this.lenient)
                        this.error("Unexpected end of input");
                    else
                        result = null;
                } else {
                    this.recordError("Unexpected character: " + this.ch);
                    if (!this.lenient) {
                        this.error("Unexpected character: " + this.ch);
                    } else {
                        // 尝试通过跳过意外字符来恢复
                        this.next();
                        result = null;
                    }
                }
        }
        this.currentDepth -= 1;
        return result;
    }

    /**
     * 解析 JSON 文本
     * @param inputText 要解析的 JSON 字符串
     * @return 解析后的 AS2 对象
     */
    public function parse(inputText:String) {
        this.text = inputText;
        this.at = 0;
        this.ch = " ";
        this.errors = []; // 重置错误记录
        this.currentDepth = 0; // 重置深度计数器
        this.stack = []; // 重置栈
        
        var result = null;

        try {
            result = this.value();
            this.white();
            // 自动补全可能的缺失结束符
            if (this.stack.length > 0) {
                this.recordError("Unexpected end of input");
                this.autoComplete(); // 补全缺失的结束符
            }
            if (this.ch) {
                this.recordError("Unexpected trailing characters");
                if (!this.lenient) {
                    this.error("Unexpected trailing characters");
                }
            }
        } catch (e) {
            // 捕获异常并继续执行
            this.recordError(e.message); 
            
            // 使用 ServerManager 记录异常信息
            ServerManager.getInstance().sendServerMessage("Error during JSON parsing: " + e.message);

            // 尝试返回部分已解析的内容
            if (!result) {
                result = {}; // 返回空对象作为默认结果
            }
        }

        // 返回解析结果，即使发生错误也能返回部分数据
        return result;
    }
}



/*

// 实例化JSON类，启用宽容模式（默认）
var json = new JSON(true); 

// --- 正常测试案例 ---

// 测试对象
var obj = new Object();
obj.name = "Alice";
obj.age = 30;
obj.isActive = true;
obj.scores = new Array(95, 88, 76);

var jsonString = json.stringify(obj);
trace("Object stringified: " + jsonString); // 输出：{"scores":[95,88,76],"isActive":true,"age":30,"name":"Alice"}

// 测试解析
var parsedObj = json.parse(jsonString);
trace("Parsed object name: " + parsedObj.name); // 输出：Alice
trace("Parsed object age: " + parsedObj.age);   // 输出：30

// 测试包含特殊字符的字符串
var specialStr = "Line1\nLine2\tTabbed";
jsonString = json.stringify(specialStr);
trace("String with special characters: " + jsonString); // 输出："Line1\nLine2\tTabbed"

// --- 额外测试案例 ---

// 测试空数组
var emptyArray = new Array();
jsonString = json.stringify(emptyArray);
trace("Empty array stringified: " + jsonString); // 输出：[]

// 手动组装嵌套数组，避免null问题
var nestedArray = new Array();
nestedArray.push(1); // 第一个元素是数字 1
nestedArray.push([2, 3]); // 第二个元素是数组 [2, 3]
nestedArray.push([[4], 5]); // 第三个元素是包含 [4] 和 5 的嵌套数组

// 序列化嵌套数组
jsonString = json.stringify(nestedArray);
trace("Nested array stringified: " + jsonString); // 输出：[1,[2,3],[[4],5]]

// 测试对象数组
var arrayOfObjects = new Array();
arrayOfObjects.push({id: 1, value: "a"});
arrayOfObjects.push({id: 2, value: "b"});
arrayOfObjects.push({id: 3, value: "c"});

jsonString = json.stringify(arrayOfObjects);
trace("Array of objects stringified: " + jsonString); // 输出：[{"id":1,"value":"a"},{"id":2,"value":"b"},{"id":3,"value":"c"}]

// 测试稀疏数组（AS2 不支持稀疏数组，使用 null 代替）
var sparseArray = new Array(1, null, 3);
jsonString = json.stringify(sparseArray);
trace("Sparse array stringified: " + jsonString); // 输出：[1,null,3]

// 测试包含特殊字符的字符串数组
var specialCharArray = new Array("one", "two\nthree", "four\tfive");
jsonString = json.stringify(specialCharArray);
trace("Array with special characters stringified: " + jsonString); // 输出：["one","two\nthree","four\tfive"]

// 测试深层嵌套的对象/数组结构
var deepStructure = new Object();
deepStructure.level1 = new Object();
deepStructure.level1.level2 = new Object();
deepStructure.level1.level2.level3 = new Object();
deepStructure.level1.level2.level3.array = new Array();
deepStructure.level1.level2.level3.array.push({id: 1});
deepStructure.level1.level2.level3.array.push({id: 2});

jsonString = json.stringify(deepStructure);
trace("Deeply nested structure stringified: " + jsonString); // 输出：{"level1":{"level2":{"level3":{"array":[{"id":1},{"id":2}]}}}}

// 测试解析深层嵌套的结构
var parsedDeep = json.parse(jsonString);
trace("Parsed deep structure: " + json.stringify(parsedDeep)); // 输出：{"level1":{"level2":{"level3":{"array":[{"id":1},{"id":2}]}}}}

// --- 错误测试案例 ---

// 测试解析错误的 JSON（宽容模式下处理）
trace("\n--- 测试案例：解析错误的 JSON ---");
var malformedJSON = '{"name": "Alice", "age": 30, "scores": [95, 88, 76'; // 缺少结束括号
var parsedMalformed = json.parse(malformedJSON);
trace("Parsed malformed JSON: " + json.stringify(parsedMalformed)); // 输出部分解析结果

// 输出所有记录的错误
trace("\n--- 解析错误信息 ---");
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// --- 新增测试案例 ---

// 测试缺少逗号
trace("\n--- 测试案例：缺少逗号 ---");
var missingCommaJSON = '{"name": "Bob" "age":25}';
var parsedMissingComma = json.parse(missingCommaJSON);
trace("Parsed missing comma JSON: " + json.stringify(parsedMissingComma)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试多余的逗号
trace("\n--- 测试案例：多余的逗号 ---");
var extraCommaJSON = '{"name": "Charlie", "age":30,}';
var parsedExtraComma = json.parse(extraCommaJSON);
trace("Parsed extra comma JSON: " + json.stringify(parsedExtraComma)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试缺少结束括号
trace("\n--- 测试案例：缺少结束括号 ---");
var missingBraceJSON = '{"user": {"name": "Dave", "age":40}';
var parsedMissingBrace = json.parse(missingBraceJSON);
trace("Parsed missing brace JSON: " + json.stringify(parsedMissingBrace)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试多余的括号
trace("\n--- 测试案例：多余的括号 ---");
var extraBraceJSON = '{"name": "Eve", "age":25}}';
var parsedExtraBrace = json.parse(extraBraceJSON);
trace("Parsed extra brace JSON: " + json.stringify(parsedExtraBrace)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试未结束的字符串
trace("\n--- 测试案例：未结束的字符串 ---");
var unterminatedStringJSON = '{"message": "Hello, world}';
var parsedUnterminatedString = json.parse(unterminatedStringJSON);
trace("Parsed unterminated string JSON: " + json.stringify(parsedUnterminatedString)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试无效的数字格式
trace("\n--- 测试案例：无效的数字格式 ---");
var invalidNumberJSON = '{"value": 01234}';
var parsedInvalidNumber = json.parse(invalidNumberJSON);
trace("Parsed invalid number JSON: " + json.stringify(parsedInvalidNumber)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试不正确的布尔值和 null
trace("\n--- 测试案例：不正确的布尔值和 null ---");
var invalidBoolNullJSON = '{"isActive": tru, "data": nul}';
var parsedInvalidBoolNull = json.parse(invalidBoolNullJSON);
trace("Parsed invalid bool and null JSON: " + json.stringify(parsedInvalidBoolNull)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试嵌套结构中的错误
trace("\n--- 测试案例：嵌套结构中的错误 ---");
var nestedErrorJSON = '{"user": {"name": "Frank", "details": {"age": 28, "city": "New York"}';
var parsedNestedError = json.parse(nestedErrorJSON);
trace("Parsed nested error JSON: " + json.stringify(parsedNestedError)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试带有 Unicode 转义字符的字符串
trace("\n--- 测试案例：带有 Unicode 转义字符的字符串 ---");
var unicodeJSON = '{"text": "Hello\\u002C World\\u0021"}';
var parsedUnicode = json.parse(unicodeJSON);
trace("Parsed Unicode JSON: " + json.stringify(parsedUnicode)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试重复的键名
trace("\n--- 测试案例：重复的键名 ---");
var duplicateKeysJSON = '{"id":1, "id":2, "name":"Grace"}';
var parsedDuplicateKeys = json.parse(duplicateKeysJSON);
trace("Parsed duplicate keys JSON: " + json.stringify(parsedDuplicateKeys)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试混合数据类型数组中的错误
trace("\n--- 测试案例：混合数据类型数组中的错误 ---");
var mixedArrayErrorJSON = '[1, "two", {invalid: "object"}, true, ]';
var parsedMixedArrayError = json.parse(mixedArrayErrorJSON);
trace("Parsed mixed array with errors JSON: " + json.stringify(parsedMixedArrayError)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试意外字符
trace("\n--- 测试案例：意外字符 ---");
var unexpectedCharJSON = '{"name": "Heidi", "age":30, "active": true@}';
var parsedUnexpectedChar = json.parse(unexpectedCharJSON);
trace("Parsed unexpected character JSON: " + json.stringify(parsedUnexpectedChar)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}

// 测试不完整的嵌套对象和数组
trace("\n--- 测试案例：不完整的嵌套对象和数组 ---");
var incompleteNestedJSON = '{"config": {"settings": [true, false, {"mode": "auto"} ';
var parsedIncompleteNested = json.parse(incompleteNestedJSON);
trace("Parsed incomplete nested JSON: " + json.stringify(parsedIncompleteNested)); 
for (var i = 0; i < json.errors.length; i++) {
    var err = json.errors[i];
    trace("Error at position " + err.at + ": " + err.message);
}



*/