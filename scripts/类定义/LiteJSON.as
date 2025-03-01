class LiteJSON implements IJSON{
    public var text:String;
    public var ch:String = "";
    public var at:Number = 0;

    // 存储 text.length 的变量
    private var textLength:Number = 0;
    
    // 字符数组缓存
    private var charArray:Array;

    /**
     * 构造函数
     */
    public function LiteJSON() {
        // 此简化版本无需初始化
    }


    /**
     * 将 AS2 对象序列化为 LiteJSON 字符串
     * @param arg 要序列化的对象
     * @return LiteJSON 字符串
     */
    public function stringify(arg):String {
        // 定义堆栈类型常量（直接使用硬编码数值）
        // 0: VALUE, 1: KEY, 2: COMMA, 3: COLON, 4: END_OBJECT, 5: END_ARRAY

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
                        var value:Object = data[key];
                        if (typeof value !== "undefined" && typeof value !== "function") {
                            propertyKeys[index] = key;
                            propertyValues[index] = value;
                            index++;
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

        return resultStr;
    }

    /**
     * 解析 LiteJSON 文本
     * @param inputText 要解析的 LiteJSON 字符串
     * @return 解析后的 AS2 对象
     */
    public function parse(inputText:String) {
        // 初始化解析器状态
        this.text = inputText;
        this.at = 0;
        this.ch = " ";
        this.textLength = this.text.length; // 将 length 缓存为局部变量
        this.charArray = this.text.split(""); // 初始化字符数组

        // 内联 next() 方法
        if (this.at >= this.textLength) {
            this.ch = "";
        } else {
            this.ch = this.charArray[this.at++];
        }

        // 定义堆栈类型常量（直接使用硬编码数值）
        // 0: VALUE, 1: OBJECT_BEGIN, 2: ARRAY_BEGIN, 5: OBJECT_VALUE, 7: ARRAY_VALUE
        var stackTypes:Array = new Array(512); // 预分配堆栈容量
        var stackData:Array = new Array(512);
        var stackPtr:Number = 0;

        var numberStr:String;
        var word:String;
        var numValue:Number;
        var currentCh:String = this.ch;
        var currentAt:Number = this.at;
        var currentTextLength:Number = this.textLength;
        var currentCharArray:Array = this.charArray;

        // 内联 white() 方法
        while (currentCh <= " " && currentCh != "") {
            if (currentAt >= currentTextLength) {
                currentCh = "";
            } else {
                currentCh = currentCharArray[currentAt++];
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

                if (currentCh === "{") {
                    object = {};
                    // 内联 next() 方法
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                    // 内联 white() 方法
                    while (currentCh <= " " && currentCh != "") {
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                    }
                    if (currentCh == "}") {
                        // 内联 next() 方法
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                        tempValue = object;
                        continue;
                    }
                    // 推入对象开始状态
                    stackTypes[stackPtr] = 1; // OBJECT_BEGIN
                    stackData[stackPtr++] = object;
                } else if (currentCh === "[") {
                    array = [];
                    // 内联 next() 方法
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                    // 内联 white() 方法
                    while (currentCh <= " " && currentCh != "") {
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                    }
                    if (currentCh == "]") {
                        // 内联 next() 方法
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }

                        tempValue = array;
                        continue;
                    }
                    // 推入数组开始状态
                    stackTypes[stackPtr] = 2; // ARRAY_BEGIN
                    stackData[stackPtr++] = array;
                } else if (currentCh === "\"") {
                    resultStrParts = [];
                    // 内联 next() 方法，跳过开头的引号
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                    while (currentCh) {
                        if (currentCh == "\"") {
                            // 内联 next() 方法，跳过结尾的引号
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                            break;
                        }
                        if (currentCh == "\\") {
                            // 内联 next() 方法，处理转义字符
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                            switch (currentCh) {
                                case "n":
                                    resultStrParts.push("\n");
                                    break;
                                case "r":
                                    resultStrParts.push("\r");
                                    break;
                                case "t":
                                    resultStrParts.push("\t");
                                    break;
                                default:
                                    resultStrParts.push(currentCh);
                                    break;
                            }
                            // 内联 next() 方法
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                        } else {
                            resultStrParts.push(currentCh);
                            // 内联 next() 方法
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                        }
                    }
                    tempValue = resultStrParts.join("");

                    continue;
                } else if (currentCh === "-") {
                    // 解析负数
                    numberStr = "-";
                    // 内联 next() 方法
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                    while (currentCh >= "0" && currentCh <= "9") {
                        numberStr += currentCh;
                        // 内联 next() 方法
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                    }
                    if (currentCh == ".") {
                        numberStr += ".";
                        // 内联 next() 方法
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                        while (currentCh >= "0" && currentCh <= "9") {
                            numberStr += currentCh;
                            // 内联 next() 方法
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                        }
                    }

                    numValue = Number(numberStr);
                    tempValue = numValue;

                    continue;
                } else if (currentCh >= "0" && currentCh <= "9") {
                    // 解析正数
                    numberStr = "";
                    while (currentCh >= "0" && currentCh <= "9") {
                        numberStr += currentCh;
                        // 内联 next() 方法
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                    }
                    if (currentCh == ".") {
                        numberStr += ".";
                        // 内联 next() 方法
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                        while (currentCh >= "0" && currentCh <= "9") {
                            numberStr += currentCh;
                            // 内联 next() 方法
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                        }
                    }

                    numValue = Number(numberStr);

                    tempValue = numValue;
                    continue;
                } else if (currentCh >= "a" && currentCh <= "z") {
                    // 解析字面量：true, false, null
                    word = "";
                    while (currentCh >= "a" && currentCh <= "z") {
                        word += currentCh;
                        // 内联 next() 方法
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                    }
                    if (word == "true") {
                        tempValue = true;
                        continue;
                    } else if (word == "false") {
                        tempValue = false;
                        continue;
                    } else if (word == "null") {
                        tempValue = null;
                        continue;
                    }
                }
            } else if (type === 1) { // OBJECT_BEGIN
                object = data;
                // 处理键值对
                while (true) {
                    // 内联 white() 方法
                    while (currentCh <= " " && currentCh != "") {
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                    }
                    if (currentCh == "}") {
                        // 内联 next() 方法
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                        tempValue = object;
                        break;
                    }

                    // 解析键
                    keyStrParts = [];
                    // 内联 next() 方法，跳过开头的引号
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                    while (currentCh) {
                        if (currentCh == "\"") {
                            // 内联 next() 方法，跳过结尾的引号
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                            break;
                        }
                        if (currentCh == "\\") {
                            // 内联 next() 方法，处理转义字符
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                            switch (currentCh) {
                                case "n":
                                    keyStrParts.push("\n");
                                    break;
                                case "r":
                                    keyStrParts.push("\r");
                                    break;
                                case "t":
                                    keyStrParts.push("\t");
                                    break;
                                default:
                                    keyStrParts.push(currentCh);
                                    break;
                            }
                            // 内联 next() 方法
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                        } else {
                            keyStrParts.push(currentCh);
                            // 内联 next() 方法
                            if (currentAt >= currentTextLength) {
                                currentCh = "";
                            } else {
                                currentCh = currentCharArray[currentAt++];
                            }
                        }
                    }
                    key = keyStrParts.join("");

                    // 内联 white() 方法
                    while (currentCh <= " " && currentCh != "") {
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
                        }
                    }

                    // 内联 next() 方法，跳过 ':'
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }

                    // 内联 white() 方法
                    while (currentCh <= " " && currentCh != "") {
                        if (currentAt >= currentTextLength) {
                            currentCh = "";
                        } else {
                            currentCh = currentCharArray[currentAt++];
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
                while (currentCh <= " " && currentCh != "") {
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                }

                if (currentCh == "}") {
                    // 内联 next() 方法，跳过 '}'
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                    tempValue = object;
                    continue;
                }

                // 内联 next() 方法，跳过 ','
                if (currentAt >= currentTextLength) {
                    currentCh = "";
                } else {
                    currentCh = currentCharArray[currentAt++];
                }

                // 内联 white() 方法
                while (currentCh <= " " && currentCh != "") {
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
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
                array[array.length] = tempValue;

                // 内联 white() 方法
                while (currentCh <= " " && currentCh != "") {
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                }

                if (currentCh == "]") {
                    // 内联 next() 方法，跳过 ']'
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
                    }
                    tempValue = array;
                    continue;
                }

                // 内联 next() 方法，跳过 ','
                if (currentAt >= currentTextLength) {
                    currentCh = "";
                } else {
                    currentCh = currentCharArray[currentAt++];
                }

                // 内联 white() 方法
                while (currentCh <= " " && currentCh != "") {
                    if (currentAt >= currentTextLength) {
                        currentCh = "";
                    } else {
                        currentCh = currentCharArray[currentAt++];
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


        // 内联 white() 方法，确保解析结束后没有多余字符
        while (this.ch <= " " && this.ch != "") {
            // 内联 next() 方法
            if (this.at >= this.textLength) {
                this.ch = "";
            } else {
                this.ch = this.charArray[this.at++];
            }
        }

        return tempValue;
    }
}


