class LiteJSON implements IJSON{
    private var parseFrameTypes:Array;
    private var parseFrameStates:Array;
    private var parseFrameRefs:Array;
    private var parseFrameKeys:Array;
    private var parseFrameIndices:Array;
    private var parseDigitValues:Array;

    /**
     * 构造函数
     */
    public function LiteJSON() {
        this.parseFrameTypes = new Array(64);
        this.parseFrameTypes.length = 0;
        this.parseFrameStates = new Array(64);
        this.parseFrameStates.length = 0;
        this.parseFrameRefs = new Array(64);
        this.parseFrameRefs.length = 0;
        this.parseFrameKeys = new Array(64);
        this.parseFrameKeys.length = 0;
        this.parseFrameIndices = new Array(64);
        this.parseFrameIndices.length = 0;
        this.parseDigitValues = [];
        this.parseDigitValues["0"] = 0;
        this.parseDigitValues["1"] = 1;
        this.parseDigitValues["2"] = 2;
        this.parseDigitValues["3"] = 3;
        this.parseDigitValues["4"] = 4;
        this.parseDigitValues["5"] = 5;
        this.parseDigitValues["6"] = 6;
        this.parseDigitValues["7"] = 7;
        this.parseDigitValues["8"] = 8;
        this.parseDigitValues["9"] = 9;
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
        var text:String = inputText;
        var textLength:Number = length(text);
        var chars:Array = text.split("");
        var at:Number = 0;

        var FRAME_OBJECT:Number = 1;
        var FRAME_ARRAY:Number = 2;

        var STATE_OBJECT_KEY_OR_END:Number = 0;
        var STATE_OBJECT_COLON:Number = 1;
        var STATE_OBJECT_VALUE:Number = 2;
        var STATE_OBJECT_COMMA_OR_END:Number = 3;

        var STATE_ARRAY_VALUE_OR_END:Number = 0;
        var STATE_ARRAY_COMMA_OR_END:Number = 1;

        var TARGET_NONE:Number = 0;
        var TARGET_ROOT:Number = 1;
        var TARGET_OBJECT:Number = 2;
        var TARGET_ARRAY:Number = 3;

        var stackTypes:Array = this.parseFrameTypes;
        var stackStates:Array = this.parseFrameStates;
        var stackRefs:Array = this.parseFrameRefs;
        var stackKeys:Array = this.parseFrameKeys;
        var stackIndices:Array = this.parseFrameIndices;
        var digitValues:Array = this.parseDigitValues;
        var stackPtr:Number = 0;

        var rootParsed:Boolean = false;
        var rootValue;
        var failed:Boolean = false;

        var currentCh:String;
        var frameIndex:Number;
        var frameType:Number;
        var frameState:Number;
        var frameRef;
        var object:Object;
        var array:Array;

        var targetKind:Number;
        var targetObject:Object;
        var targetArray:Array;
        var targetKey:String;
        var targetIndex:Number;

        var stringValue:String;
        var segmentStart:Number;
        var numberStart:Number;
        var numValue:Number;
        var isNegative:Boolean;
        var fractionDigits:Number;

        while (!failed) {
            while (at < textLength) {
                currentCh = chars[at];
                if (currentCh > " ") {
                    break;
                }
                at++;
            }

            if (at < textLength) {
                currentCh = chars[at];
            } else {
                currentCh = "";
            }

            targetKind = TARGET_NONE;

            if (!rootParsed) {
                targetKind = TARGET_ROOT;
            } else if (stackPtr === 0) {
                break;
            } else {
                frameIndex = stackPtr - 1;
                frameType = stackTypes[frameIndex];
                frameState = stackStates[frameIndex];
                frameRef = stackRefs[frameIndex];

                if (frameType === FRAME_OBJECT) {
                    if (frameState === STATE_OBJECT_KEY_OR_END) {
                        if (currentCh === "}") {
                            at++;
                            stackPtr--;
                            continue;
                        }
                        if (currentCh !== "\"") {
                            failed = true;
                            break;
                        }

                        stringValue = null;
                        at++;
                        segmentStart = at;
                        while (at < textLength) {
                            currentCh = chars[at];
                            if (currentCh === "\"") {
                                if (stringValue == null) {
                                    stringValue = text.substring(segmentStart, at);
                                } else if (at > segmentStart) {
                                    stringValue += text.substring(segmentStart, at);
                                }
                                at++;
                                break;
                            }
                            if (currentCh === "\\") {
                                if (stringValue == null) {
                                    stringValue = "";
                                }
                                if (at > segmentStart) {
                                    stringValue += text.substring(segmentStart, at);
                                }
                                at++;
                                if (at >= textLength) {
                                    failed = true;
                                    break;
                                }

                                currentCh = chars[at];
                                if (currentCh === "\"") {
                                    stringValue += "\"";
                                } else if (currentCh === "\\") {
                                    stringValue += "\\";
                                } else if (currentCh === "/") {
                                    stringValue += "/";
                                } else if (currentCh === "n") {
                                    stringValue += "\n";
                                } else if (currentCh === "r") {
                                    stringValue += "\r";
                                } else if (currentCh === "t") {
                                    stringValue += "\t";
                                } else {
                                    // \b \f \uXXXX 等不支持，直接输出原字符
                                    stringValue += currentCh;
                                }
                                at++;
                                segmentStart = at;
                                continue;
                            }
                            at++;
                        }
                        if (at >= textLength && currentCh !== "\"") {
                            failed = true;
                            break;
                        }

                        stackKeys[frameIndex] = stringValue;
                        stackStates[frameIndex] = STATE_OBJECT_COLON;
                        continue;
                    }

                    if (frameState === STATE_OBJECT_COLON) {
                        if (currentCh !== ":") {
                            failed = true;
                            break;
                        }
                        at++;
                        stackStates[frameIndex] = STATE_OBJECT_VALUE;
                        continue;
                    }

                    if (frameState === STATE_OBJECT_VALUE) {
                        targetKind = TARGET_OBJECT;
                        targetObject = frameRef;
                        targetKey = stackKeys[frameIndex];
                        stackStates[frameIndex] = STATE_OBJECT_COMMA_OR_END;
                    } else {
                        if (currentCh === ",") {
                            at++;
                            stackStates[frameIndex] = STATE_OBJECT_KEY_OR_END;
                            continue;
                        }
                        if (currentCh === "}") {
                            at++;
                            stackPtr--;
                            continue;
                        }
                        failed = true;
                        break;
                    }
                } else {
                    if (frameState === STATE_ARRAY_VALUE_OR_END) {
                        if (currentCh === "]") {
                            at++;
                            stackPtr--;
                            continue;
                        }
                        targetKind = TARGET_ARRAY;
                        targetArray = frameRef;
                        targetIndex = stackIndices[frameIndex];
                        stackIndices[frameIndex] = targetIndex + 1;
                        stackStates[frameIndex] = STATE_ARRAY_COMMA_OR_END;
                    } else {
                        if (currentCh === ",") {
                            at++;
                            stackStates[frameIndex] = STATE_ARRAY_VALUE_OR_END;
                            continue;
                        }
                        if (currentCh === "]") {
                            at++;
                            stackPtr--;
                            continue;
                        }
                        failed = true;
                        break;
                    }
                }
            }

            if (at >= textLength) {
                failed = true;
                break;
            }

            if (currentCh === "\"") {
                stringValue = null;
                at++;
                segmentStart = at;
                while (at < textLength) {
                    currentCh = chars[at];
                    if (currentCh === "\"") {
                        if (stringValue == null) {
                            stringValue = text.substring(segmentStart, at);
                        } else if (at > segmentStart) {
                            stringValue += text.substring(segmentStart, at);
                        }
                        at++;
                        break;
                    }
                    if (currentCh === "\\") {
                        if (stringValue == null) {
                            stringValue = "";
                        }
                        if (at > segmentStart) {
                            stringValue += text.substring(segmentStart, at);
                        }
                        at++;
                        if (at >= textLength) {
                            failed = true;
                            break;
                        }

                        currentCh = chars[at];
                        if (currentCh === "\"") {
                            stringValue += "\"";
                        } else if (currentCh === "\\") {
                            stringValue += "\\";
                        } else if (currentCh === "/") {
                            stringValue += "/";
                        } else if (currentCh === "n") {
                            stringValue += "\n";
                        } else if (currentCh === "r") {
                            stringValue += "\r";
                        } else if (currentCh === "t") {
                            stringValue += "\t";
                        } else {
                            // \b \f \uXXXX 等不支持，直接输出原字符
                            stringValue += currentCh;
                        }
                        at++;
                        segmentStart = at;
                        continue;
                    }
                    at++;
                }
                if (at >= textLength && currentCh !== "\"") {
                    failed = true;
                    break;
                }

                if (targetKind === TARGET_ROOT) {
                    rootValue = stringValue;
                    rootParsed = true;
                } else if (targetKind === TARGET_OBJECT) {
                    targetObject[targetKey] = stringValue;
                } else {
                    targetArray[targetIndex] = stringValue;
                }
                continue;
            }

            if (currentCh === "{") {
                object = {};
                object.__proto__ = null;
                at++;

                if (targetKind === TARGET_ROOT) {
                    rootValue = object;
                    rootParsed = true;
                } else if (targetKind === TARGET_OBJECT) {
                    targetObject[targetKey] = object;
                } else {
                    targetArray[targetIndex] = object;
                }

                stackTypes[stackPtr] = FRAME_OBJECT;
                stackStates[stackPtr] = STATE_OBJECT_KEY_OR_END;
                stackRefs[stackPtr] = object;
                stackPtr++;
                continue;
            }

            if (currentCh === "[") {
                array = [];
                at++;

                if (targetKind === TARGET_ROOT) {
                    rootValue = array;
                    rootParsed = true;
                } else if (targetKind === TARGET_OBJECT) {
                    targetObject[targetKey] = array;
                } else {
                    targetArray[targetIndex] = array;
                }

                stackTypes[stackPtr] = FRAME_ARRAY;
                stackStates[stackPtr] = STATE_ARRAY_VALUE_OR_END;
                stackRefs[stackPtr] = array;
                stackIndices[stackPtr] = 0;
                stackPtr++;
                continue;
            }

            if (currentCh === "t" && at + 3 < textLength && chars[at + 1] === "r" && chars[at + 2] === "u" && chars[at + 3] === "e") {
                at += 4;
                if (targetKind === TARGET_ROOT) {
                    rootValue = true;
                    rootParsed = true;
                } else if (targetKind === TARGET_OBJECT) {
                    targetObject[targetKey] = true;
                } else {
                    targetArray[targetIndex] = true;
                }
                continue;
            }

            if (currentCh === "f" && at + 4 < textLength && chars[at + 1] === "a" && chars[at + 2] === "l" && chars[at + 3] === "s" && chars[at + 4] === "e") {
                at += 5;
                if (targetKind === TARGET_ROOT) {
                    rootValue = false;
                    rootParsed = true;
                } else if (targetKind === TARGET_OBJECT) {
                    targetObject[targetKey] = false;
                } else {
                    targetArray[targetIndex] = false;
                }
                continue;
            }

            if (currentCh === "n" && at + 3 < textLength && chars[at + 1] === "u" && chars[at + 2] === "l" && chars[at + 3] === "l") {
                at += 4;
                if (targetKind === TARGET_ROOT) {
                    rootValue = null;
                    rootParsed = true;
                } else if (targetKind === TARGET_OBJECT) {
                    targetObject[targetKey] = null;
                } else {
                    targetArray[targetIndex] = null;
                }
                continue;
            }

            if (currentCh === "-" || (currentCh >= "0" && currentCh <= "9")) {
                numberStart = at;
                isNegative = false;

                if (currentCh === "-") {
                    isNegative = true;
                    at++;
                    if (at >= textLength) {
                        failed = true;
                        break;
                    }
                    currentCh = chars[at];
                }

                if (currentCh === "0") {
                    numValue = 0;
                    at++;
                    // currentCh 留在 "0"，下面用 at < textLength 判断是否还有后续字符
                } else if (currentCh >= "1" && currentCh <= "9") {
                    numValue = digitValues[currentCh];
                    at++;
                    while (at < textLength) {
                        currentCh = chars[at];
                        if (currentCh < "0" || currentCh > "9") {
                            break;
                        }
                        numValue = numValue * 10 + digitValues[currentCh];
                        at++;
                    }
                } else {
                    failed = true;
                    break;
                }

                // 整数快速路径：仅当下一个字符是 '.' 时才进入浮点解析
                // 科学计数法不支持（实际数据从未使用，由 JSON.as / FastJSON.as 兜底）
                if (at < textLength && chars[at] === ".") {
                    at++;
                    fractionDigits = 0;
                    while (at < textLength) {
                        currentCh = chars[at];
                        if (currentCh < "0" || currentCh > "9") {
                            break;
                        }
                        fractionDigits++;
                        at++;
                    }
                    if (fractionDigits === 0) {
                        failed = true;
                        break;
                    }
                    numValue = Number(text.substring(numberStart, at));
                } else if (isNegative) {
                    numValue = -numValue;
                }

                if (targetKind === TARGET_ROOT) {
                    rootValue = numValue;
                    rootParsed = true;
                } else if (targetKind === TARGET_OBJECT) {
                    targetObject[targetKey] = numValue;
                } else {
                    targetArray[targetIndex] = numValue;
                }
                continue;
            }

            failed = true;
            break;
        }

        if (!failed) {
            while (at < textLength) {
                currentCh = chars[at];
                if (currentCh > " ") {
                    failed = true;
                    break;
                }
                at++;
            }
        }

        if (stackRefs.length > 256) {
            this.parseFrameTypes = new Array(64);
            this.parseFrameTypes.length = 0;
            this.parseFrameStates = new Array(64);
            this.parseFrameStates.length = 0;
            this.parseFrameRefs = new Array(64);
            this.parseFrameRefs.length = 0;
            this.parseFrameKeys = new Array(64);
            this.parseFrameKeys.length = 0;
            this.parseFrameIndices = new Array(64);
            this.parseFrameIndices.length = 0;
        } else {
            stackTypes.length = 0;
            stackStates.length = 0;
            stackRefs.length = 0;
            stackKeys.length = 0;
            stackIndices.length = 0;
        }

        if (failed || !rootParsed) {
            return undefined;
        }
        return rootValue;
    }
}


