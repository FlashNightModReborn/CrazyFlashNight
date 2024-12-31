class org.flashNight.gesh.regexp.ASTNode {
    public var type:String;
    public var value:Object;
    public var child:ASTNode;
    public var children:Array;
    public var left:ASTNode;
    public var right:ASTNode;
    public var min:Number;
    public var max:Number;
    public var negated:Boolean;
    public var capturing:Boolean;
    public var greedy:Boolean; // 量词是否贪婪
    public var groupNumber:Number; // 捕获组编号

    public function ASTNode(type:String) {
        this.type = type;
        this.value = null;
        this.child = null;
        this.children = null;
        this.left = null;
        this.right = null;
        this.min = 1;
        this.max = 1;
        this.negated = false;
        this.capturing = false;
        this.greedy = true; // 默认贪婪匹配
        this.groupNumber = 0; // 初始化为0，表示非捕获组
    }

    /**
     * 获取固定长度的匹配（仅适用于固定长度的子节点）
     * @return 子节点的固定长度，或抛出错误。
     */
    public function getFixedLength():Number {
        switch(this.type) {
            case 'Literal':
                return 1;
            case 'CharacterClass':
                return 1;
            case 'PredefinedCharacterClass':
                return 1;
            case 'Sequence':
                var totalLength:Number = 0;
                for (var i:Number = 0; i < this.children.length; i++) {
                    totalLength += this.children[i].getFixedLength();
                }
                return totalLength;
            case 'Group':
                return this.child.getFixedLength();
            case 'Quantifier':
                if (this.min === this.max) {
                    return this.child.getFixedLength() * this.min;
                } else {
                    throw new Error("Cannot determine fixed length for Quantifier node with variable min and max.");
                }
            case 'Alternation':
                var leftLength:Number = this.left.getFixedLength();
                var rightLength:Number = this.right.getFixedLength();
                if (leftLength === rightLength) {
                    return leftLength;
                } else {
                    throw new Error("Cannot determine fixed length for Alternation node with differing alternation lengths.");
                }
            default:
                throw new Error("Cannot determine fixed length for ASTNode type: " + this.type);
        }
    }

    /**
     * 尝试匹配输入字符串，从指定位置开始。
     * 支持基本的回溯机制和断言。
     * @param input 输入字符串。
     * @param position 当前匹配位置。
     * @param captures 捕获组数组。
     * @param ignoreCase 是否忽略大小写。
     * @return 匹配结果对象。
     */
    public function match(input:String, position:Number, captures:Array, ignoreCase:Boolean):Object {
        var result:Object = { matched: false, position: position };
        if (position > input.length) {
            return result;
        }

        switch(this.type) {
            case 'Literal':
                if (position < input.length && charEquals(input.charAt(position), String(this.value), ignoreCase)) {
                    result.matched = true;
                    result.position = position + 1;
                }
                break;

            case 'Any':
                if (position < input.length) {
                    result.matched = true;
                    result.position = position + 1;
                }
                break;

            case 'Sequence':
                var currentPos:Number = position;
                var tempCapturesSeq:Array = captures.slice(); // 克隆 captures
                var allMatchedSeq:Boolean = true;

                for (var i:Number = 0; i < this.children.length; i++) {
                    var childResult:Object = this.children[i].match(input, currentPos, tempCapturesSeq, ignoreCase);
                    if (!childResult.matched) {
                        allMatchedSeq = false;
                        break;
                    }
                    currentPos = childResult.position;
                }

                if (allMatchedSeq) {
                    // 将 tempCapturesSeq 更新回 captures
                    for (var k:Number = 0; k < tempCapturesSeq.length; k++) {
                        captures[k] = tempCapturesSeq[k];
                    }
                    result.matched = true;
                    result.position = currentPos;
                }
                break;

            case 'CharacterClass':
                if (position < input.length) {
                    var char:String = input.charAt(position);
                    var inSet:Boolean = false;
                    for (var j:Number = 0; j < this.value.length; j++) {
                        if (charEquals(this.value[j], char, ignoreCase)) {
                            inSet = true;
                            break;
                        }
                    }
                    if (this.negated) {
                        inSet = !inSet;
                    }
                    if (inSet) {
                        result.matched = true;
                        result.position = position + 1;
                    }
                }
                break;

            case 'PredefinedCharacterClass':
                if (position < input.length) {
                    var preChar:String = input.charAt(position);
                    var matched:Boolean = false;
                    switch(this.value) {
                        case 'd':
                            matched = isDigit(preChar);
                            break;
                        case 'D':
                            matched = !isDigit(preChar);
                            break;
                        case 'w':
                            matched = isWordChar(preChar);
                            break;
                        case 'W':
                            matched = !isWordChar(preChar);
                            break;
                        case 's':
                            matched = isWhitespace(preChar);
                            break;
                        case 'S':
                            matched = !isWhitespace(preChar);
                            break;
                        default:
                            throw new Error("Unsupported predefined character class: \\" + this.value);
                    }
                    if (matched) {
                        result.matched = true;
                        result.position = position + 1;
                    }
                }
                break;

            case 'Quantifier':
                if (this.child == null) {
                    throw new Error("Quantifier node has no child.");
                }

                // 限制 maxPossible 不超过输入字符串的剩余长度
                var maxPossible:Number = Math.min(this.max, input.length - position);
                var minRequired:Number = this.min;
                var currentCount:Number = 0;
                var currentMatchPos:Number = position;
                var tempCaptures:Array;

                if (this.greedy) {
                    // 尽可能多地匹配
                    while (currentCount < maxPossible) {
                        var quantChildResult:Object = this.child.match(input, currentMatchPos, captures, ignoreCase);
                        if (quantChildResult.matched && quantChildResult.position > currentMatchPos) {
                            currentCount++;
                            currentMatchPos = quantChildResult.position;
                        } else {
                            break;
                        }
                    }

                    // 尝试回溯，从最大匹配数到最小
                    for (var count:Number = currentCount; count >= minRequired; count--) {
                        var tempPos:Number = position;
                        tempCaptures = captures.slice(); // 克隆 captures
                        var allMatched:Boolean = true;

                        for (var c:Number = 0; c < count; c++) {
                            var tempMatch:Object = this.child.match(input, tempPos, tempCaptures, ignoreCase);
                            if (tempMatch.matched) {
                                tempPos = tempMatch.position;
                            } else {
                                allMatched = false;
                                break;
                            }
                        }

                        if (allMatched) {
                            result.matched = true;
                            result.position = tempPos;
                            // 正确更新 captures 数组
                            for (var m:Number = 0; m < tempCaptures.length; m++) {
                                captures[m] = tempCaptures[m];
                            }
                            break;
                        }
                    }
                } else {
                    // 非贪婪匹配：尽可能少地匹配
                    while (currentCount < this.max) {
                        var quantChildResultNonGreedy:Object = this.child.match(input, currentMatchPos, captures, ignoreCase);
                        if (quantChildResultNonGreedy.matched && quantChildResultNonGreedy.position > currentMatchPos) {
                            currentCount++;
                            currentMatchPos = quantChildResultNonGreedy.position;
                            if (currentCount >= minRequired) {
                                result.matched = true;
                                result.position = currentMatchPos;
                                break;
                            }
                        } else {
                            break;
                        }
                    }

                    if (currentCount >= this.min) {
                        result.matched = true;
                        result.position = currentMatchPos;
                    }
                }
                break;

            case 'Alternation':
                var leftCaptures:Array = captures.slice(); // 克隆 captures
                var leftResult:Object = this.left.match(input, position, leftCaptures, ignoreCase);
                if (leftResult.matched) {
                    // 将左侧的 captures 更新回主 captures
                    for (var l:Number = 0; l < leftCaptures.length; l++) {
                        captures[l] = leftCaptures[l];
                    }
                    result.matched = true;
                    result.position = leftResult.position;
                } else {
                    var rightCaptures:Array = captures.slice(); // 克隆 captures
                    var rightResult:Object = this.right.match(input, position, rightCaptures, ignoreCase);
                    if (rightResult.matched) {
                        // 将右侧的 captures 更新回主 captures
                        for (var r:Number = 0; r < rightCaptures.length; r++) {
                            captures[r] = rightCaptures[r];
                        }
                        result.matched = true;
                        result.position = rightResult.position;
                    }
                }
                break;

            case 'Group':
                var groupStartPos:Number = position;
                var groupCaptures:Array = captures.slice(); // 克隆 captures
                var groupResult:Object = this.child.match(input, position, groupCaptures, ignoreCase);
                if (groupResult.matched) {
                    result.matched = true;
                    result.position = groupResult.position;
                    if (this.capturing) {
                        var groupMatch:String = input.substring(groupStartPos, groupResult.position);
                        if (this.groupNumber > 0) { // 确保是捕获组
                            groupCaptures[this.groupNumber] = groupMatch;
                        }
                    }
                    // 更新 captures 数组
                    for (var g:Number = 0; g < groupCaptures.length; g++) {
                        captures[g] = groupCaptures[g];
                    }
                }
                break;

            case 'BackReference':
                var groupNumber:Number = Number(this.value);
                if (captures.length > groupNumber && captures[groupNumber] != undefined) {
                    var groupContent:String = captures[groupNumber];
                    var endPosition:Number = position + groupContent.length;
                    if (endPosition <= input.length) {
                        var matchedStr:String = input.substring(position, endPosition);
                        if (charEquals(matchedStr, groupContent, ignoreCase)) {
                            result.matched = true;
                            result.position = endPosition;
                        }
                    }
                }
                break;

            case 'Anchor':
                if (this.value == 'start') {
                    if (position == 0) {
                        result.matched = true;
                        result.position = position;
                    }
                } else if (this.value == 'end') {
                    if (position == input.length) {
                        result.matched = true;
                        result.position = position;
                    }
                }
                break;

            // 新增处理 PositiveLookahead
            case 'PositiveLookahead':
                var lookaheadCaptures:Array = captures.slice(); // 克隆捕获组
                var lookaheadResult:Object = this.child.match(input, position, lookaheadCaptures, ignoreCase);
                if (lookaheadResult.matched) {
                    result.matched = true;
                    result.position = position; // 不消耗字符
                }
                break;

            // 新增处理 NegativeLookahead
            case 'NegativeLookahead':
                var negLookaheadCaptures:Array = captures.slice(); // 克隆捕获组
                var negLookaheadResult:Object = this.child.match(input, position, negLookaheadCaptures, ignoreCase);
                if (!negLookaheadResult.matched) {
                    result.matched = true;
                    result.position = position; // 不消耗字符
                }
                break;

            // 新增处理 PositiveLookbehind
            case 'PositiveLookbehind':
                try {
                    var lookbehindLength:Number = this.child.getFixedLength(); // 获取子节点固定长度
                } catch (e:Error) {
                    throw new Error("PositiveLookbehind requires a fixed-length pattern. " + e.message);
                }
                var lookbehindStartPos:Number = position - lookbehindLength;
                if (lookbehindStartPos >= 0) {
                    var lookbehindCaptures:Array = captures.slice(); // 克隆捕获组
                    var lookbehindResult:Object = this.child.match(input, lookbehindStartPos, lookbehindCaptures, ignoreCase);
                    if (lookbehindResult.matched && lookbehindResult.position == position) {
                        result.matched = true;
                        result.position = position; // 不消耗字符
                    }
                }
                break;

            // 新增处理 NegativeLookbehind
            case 'NegativeLookbehind':
                try {
                    var negLookbehindLength:Number = this.child.getFixedLength(); // 获取子节点固定长度
                } catch (e:Error) {
                    throw new Error("NegativeLookbehind requires a fixed-length pattern. " + e.message);
                }
                var negLookbehindStartPos:Number = position - negLookbehindLength;
                if (negLookbehindStartPos >= 0) {
                    var negLookbehindCaptures:Array = captures.slice(); // 克隆捕获组
                    var negLookbehindResult:Object = this.child.match(input, negLookbehindStartPos, negLookbehindCaptures, ignoreCase);
                    if (!negLookbehindResult.matched || negLookbehindResult.position != position) {
                        result.matched = true;
                        result.position = position; // 不消耗字符
                    }
                } else {
                    // 如果子模式长度大于当前位置，负向后顾成功
                    result.matched = true;
                    result.position = position;
                }
                break;

            default:
                throw new Error("Unsupported ASTNode type: " + this.type);
        }

        return result;
    }

    // 辅助方法：字符比较，考虑大小写
    private function charEquals(a:String, b:String, ignoreCase:Boolean):Boolean {
        if (ignoreCase) {
            return a.toLowerCase() == b.toLowerCase();
        } else {
            return a == b;
        }
    }

    // 辅助方法：判断是否为数字字符
    private function isDigit(char:String):Boolean {
        var code:Number = char.charCodeAt(0);
        return code >= 48 && code <= 57; // '0' to '9'
    }

    // 辅助方法：判断是否为单词字符
    private function isWordChar(char:String):Boolean {
        var code:Number = char.charCodeAt(0);
        return (code >= 48 && code <= 57) || // '0' to '9'
               (code >= 65 && code <= 90) || // 'A' to 'Z'
               (code >= 97 && code <= 122) || // 'a' to 'z'
               (char == '_');
    }

    // 辅助方法：判断是否为空白字符
    private function isWhitespace(char:String):Boolean {
        return char == ' ' || char == '\t' || char == '\n' || char == '\r' || char == '\f' || char == '\v';
    }

    // 辅助方法：获取转义字符
    private function getEscapedChar(char:String):String {
        switch(char) {
            case 'n': return "\n";
            case 't': return "\t";
            case 'r': return "\r";
            case '\\': return "\\";
            case '.': return ".";
            case '*': return "*";
            case '+': return "+";
            case '?': return "?";
            case '{': return "{";
            case '}': return "}";
            case '[': return "[";
            case ']': return "]";
            case '(': return "(";
            case ')': return ")";
            case '|': return "|";
            case '^': return "^";
            case '$': return "$";
            case '/': return "/";
            default: return char; // 未识别的转义字符按字面量处理
        }
    }
}
