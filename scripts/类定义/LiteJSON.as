class LiteJSON implements IJSON{
    private var parseFrameStates:Array;
    private var parseFrameRefs:Array;
    private var parseFrameAux:Array;
    private var parseDigitValues:Array;

    /**
     * 构造函数
     */
    public function LiteJSON() {
        this.parseFrameStates = new Array(64);
        this.parseFrameStates.length = 0;
        this.parseFrameRefs = new Array(64);
        this.parseFrameRefs.length = 0;
        this.parseFrameAux = new Array(64);
        this.parseFrameAux.length = 0;
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
        var tv:String = typeof arg;
        if (tv === "string") {
            // 不做任何转义：与 parse 的纯 indexOf('"') 扫描对齐
            // 含 " 的字符串不可表示（会破坏结构），\ 可透传（两端均不特殊处理）
            return "\"" + String(arg) + "\"";
        }
        if (tv === "number") {
            return isFinite(Number(arg)) ? String(arg) : "null";
        }
        if (tv === "boolean") {
            return arg ? "true" : "false";
        }
        if (tv !== "object" || arg == null) {
            return "null";
        }
        var r:String;
        var i:Number;
        if (arg instanceof Array) {
            i = arg.length;
            if (i === 0) return "[]";
            r = "[" + this.stringify(arg[0]);
            i = 1;
            while (i < arg.length) {
                r += "," + this.stringify(arg[i]);
                i++;
            }
            return r + "]";
        }
        // 对象：for..in 内联处理，无需收集 keys 数组
        var key:String;
        var first:Boolean = true;
        r = "{";
        for (key in arg) {
            tv = typeof arg[key];
            if (tv !== "undefined" && tv !== "function") {
                if (first) {
                    first = false;
                } else {
                    r += ",";
                }
                r += "\"" + key + "\":" + this.stringify(arg[key]);
            }
        }
        return r + "}";
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

        // 帧状态: 1=OBJ_KEY_OR_END  2=OBJ_COMMA_OR_END  3=ARR_VALUE_OR_END  4=ARR_COMMA_OR_END
        // 3 组并行数组（原 5 组：types+states→states, keys+indices→aux）
        var stackStates:Array = this.parseFrameStates;
        var stackRefs:Array = this.parseFrameRefs;
        var stackAux:Array = this.parseFrameAux;
        var digitValues:Array = this.parseDigitValues;
        var stackPtr:Number = 0;

        // rootWrapper 统一写入：tRef[tKey] = value 覆盖 root/object/array 三路分支
        var rootWrapper:Object = {};
        rootWrapper.__proto__ = null;
        var rootParsed:Boolean = false;
        var failed:Boolean = false;
        var tRef:Object = rootWrapper;
        var tKey = 0;

        var currentCh:String;
        var frameIndex:Number;
        var frameState:Number;
        var frameRef;
        var object:Object;
        var array:Array;

        var segmentStart:Number;
        var numberStart:Number;
        var numValue:Number;
        var isNegative:Boolean;
        var fractionDigits:Number;

        while (!failed) {
            // 跳过空白
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

            if (!rootParsed) {
                // tRef/tKey 已初始化为 rootWrapper/0
                rootParsed = true;
            } else if (stackPtr === 0) {
                break;
            } else {
                frameIndex = stackPtr - 1;
                frameState = stackStates[frameIndex];
                frameRef = stackRefs[frameIndex];

                if (frameState === 1) { // OBJ_KEY_OR_END
                    if (currentCh === "}") {
                        at++;
                        stackPtr--;
                        continue;
                    }
                    if (currentCh !== "\"") {
                        failed = true;
                        break;
                    }

                    // 解析 key — indexOf 原生扫描
                    at++;
                    segmentStart = at;
                    at = text.indexOf("\"", at);
                    if (at < 0) {
                        failed = true;
                        break;
                    }
                    stackAux[frameIndex] = text.substring(segmentStart, at);
                    at++;

                    // colon 内联：跳空白 → 消费 ':'
                    while (at < textLength) {
                        currentCh = chars[at];
                        if (currentCh > " ") {
                            break;
                        }
                        at++;
                    }
                    if (at >= textLength || chars[at] !== ":") {
                        failed = true;
                        break;
                    }
                    at++;

                    // value setup：跳空白 → 设 target → 直落 value 解析
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
                    tRef = frameRef;
                    tKey = stackAux[frameIndex];
                    stackStates[frameIndex] = 2; // OBJ_COMMA_OR_END

                } else if (frameState === 2) { // OBJ_COMMA_OR_END
                    if (currentCh === "}") {
                        at++;
                        stackPtr--;
                        continue;
                    }
                    if (currentCh !== ",") {
                        failed = true;
                        break;
                    }
                    // 内联：吃逗号 → 跳空白 → 解析 key → 吃冒号 → 设 target → 直落 value
                    at++;
                    while (at < textLength) {
                        currentCh = chars[at];
                        if (currentCh > " ") {
                            break;
                        }
                        at++;
                    }
                    if (at >= textLength || chars[at] !== "\"") {
                        failed = true;
                        break;
                    }
                    // 解析 key — indexOf 原生扫描
                    at++;
                    segmentStart = at;
                    at = text.indexOf("\"", at);
                    if (at < 0) {
                        failed = true;
                        break;
                    }
                    stackAux[frameIndex] = text.substring(segmentStart, at);
                    at++;
                    while (at < textLength) {
                        currentCh = chars[at];
                        if (currentCh > " ") {
                            break;
                        }
                        at++;
                    }
                    if (at >= textLength || chars[at] !== ":") {
                        failed = true;
                        break;
                    }
                    at++;
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
                    tRef = frameRef;
                    tKey = stackAux[frameIndex];

                } else if (frameState === 3) { // ARR_VALUE_OR_END
                    if (currentCh === "]") {
                        at++;
                        stackPtr--;
                        continue;
                    }
                    tRef = frameRef;
                    stackAux[frameIndex] = (tKey = stackAux[frameIndex]) + 1;
                    stackStates[frameIndex] = 4; // ARR_COMMA_OR_END

                } else {
                    // 4: ARR_COMMA_OR_END
                    if (currentCh === ",") {
                        at++;
                        // 内联：跳空白 → 设 target → 直落 value 解析
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
                        tRef = frameRef;
                        stackAux[frameIndex] = (tKey = stackAux[frameIndex]) + 1;
                        // 状态保持 4(ARR_COMMA_OR_END)，下轮直接判逗号/]
                    } else if (currentCh === "]") {
                        at++;
                        stackPtr--;
                        continue;
                    } else {
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
                // value 字符串 — indexOf 原生扫描
                segmentStart = ++at;
                at = text.indexOf("\"", at);
                if (at < 0) {
                    failed = true;
                    break;
                }
                tRef[tKey] = text.substring(segmentStart, at++);
                continue;
            }

            if (currentCh === "{") {
                object = {};
                object.__proto__ = null;
                at++;
                tRef[tKey] = object;
                stackStates[stackPtr] = 1; // OBJ_KEY_OR_END
                stackRefs[stackPtr++] = object;
                continue;
            }

            if (currentCh === "[") {
                array = [];
                at++;
                tRef[tKey] = array;
                stackStates[stackPtr] = 3; // ARR_VALUE_OR_END
                stackRefs[stackPtr] = array;
                stackAux[stackPtr++] = 0;
                continue;
            }

            if (currentCh === "t" && at + 3 < textLength && chars[at + 1] === "r" && chars[at + 2] === "u" && chars[at + 3] === "e") {
                at += 4;
                tRef[tKey] = true;
                continue;
            }

            if (currentCh === "f" && at + 4 < textLength && chars[at + 1] === "a" && chars[at + 2] === "l" && chars[at + 3] === "s" && chars[at + 4] === "e") {
                at += 5;
                tRef[tKey] = false;
                continue;
            }

            if (currentCh === "n" && at + 3 < textLength && chars[at + 1] === "u" && chars[at + 2] === "l" && chars[at + 3] === "l") {
                at += 4;
                tRef[tKey] = null;
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

                tRef[tKey] = numValue;
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
            this.parseFrameStates = new Array(64);
            this.parseFrameStates.length = 0;
            this.parseFrameRefs = new Array(64);
            this.parseFrameRefs.length = 0;
            this.parseFrameAux = new Array(64);
            this.parseFrameAux.length = 0;
        } else {
            stackStates.length = 0;
            stackRefs.length = 0;
            stackAux.length = 0;
        }

        if (failed || !rootParsed) {
            return undefined;
        }
        return rootWrapper[0];
    }
}


