import org.flashNight.gesh.regexp.ASTNode;

class org.flashNight.gesh.regexp.Parser {
    private var pattern:String;
    private var index:Number;
    private var length:Number;
    private var ignoreCase:Boolean;
    private var groupCount:Number;
    private var groupNames:Array;

    public function Parser(pattern:String, flags:String) {
        this.pattern = pattern;
        this.index = 0;
        this.length = pattern.length;
        this.ignoreCase = flags.indexOf('i') >= 0;
        this.groupCount = 0;
        this.groupNames = [];
    }

    /**
     * 入口方法，开始解析过程，返回 AST 树
     */
    public function parse():ASTNode {
        var ast:ASTNode = parseExpression();
        if (this.index < this.length) {
            throw new Error("Unexpected character '" + peek() + "' at position " + this.index);
        }
        return ast;
    }

    /**
     * 解析表达式，处理 alternation（|）
     */
    private function parseExpression():ASTNode {
        var term:ASTNode = parseSequence();
        while (this.index < this.length && peek() == '|') {
            consume(); // 跳过 '|'
            var rightTerm:ASTNode = parseSequence();
            var alternationNode:ASTNode = new ASTNode('Alternation');
            alternationNode.left = term;
            alternationNode.right = rightTerm;
            term = alternationNode;
        }
        return term;
    }

    /**
     * 解析序列，处理连续的正则元素
     */
    private function parseSequence():ASTNode {
        var nodes:Array = [];
        while (this.index < this.length && peek() != ')' && peek() != '|') {
            var node:ASTNode = parseTerm();
            if (node != null) {
                nodes.push(node);
            }
        }
        if (nodes.length == 1) {
            return nodes[0];
        } else {
            var sequenceNode:ASTNode = new ASTNode('Sequence');
            sequenceNode.children = nodes;
            return sequenceNode;
        }
    }

    /**
     * 解析单个正则元素，如字符、字符集、量词、分组等
     */
    private function parseTerm():ASTNode {
        var node:ASTNode = null;
        var char:String = peek();

        if (char == '^') {
            consume();
            node = new ASTNode('Anchor');
            node.value = 'start';
            node = parseQuantifier(node);
        } else if (char == '$') {
            consume();
            node = new ASTNode('Anchor');
            node.value = 'end';
            node = parseQuantifier(node);
        } else if (char == '(') {
            node = parseGroup();
        } else if (char == '[') {
            node = parseCharacterClass();
            node = parseQuantifier(node);
        } else if (char == '.') {
            consume();
            node = new ASTNode('Any');
            node = parseQuantifier(node);
        } else if (char == '\\') {
            consume();
            if (this.index >= this.length) {
                throw new Error("Escape character '\\' at end of pattern");
            }
            var nextChar:String = consume();
            if (nextChar == 'd' || nextChar == 'D' || nextChar == 'w' || nextChar == 'W' || nextChar == 's' || nextChar == 'S') {
                node = new ASTNode('PredefinedCharacterClass');
                node.value = nextChar;
                node = parseQuantifier(node);
            } else if (nextChar == 'b' || nextChar == 'B') {
                // 单词边界 \b 和非单词边界 \B
                node = new ASTNode('WordBoundary');
                node.value = nextChar; // 'b' 或 'B'
                node = parseQuantifier(node);
            } else if (nextChar == 'x') {
                // \xHH: 两位十六进制表示的 ASCII 字符
                var hex2:String = "";
                if (this.index < this.length) hex2 += consume();
                if (this.index < this.length) hex2 += consume();
                if (hex2.length != 2) {
                    throw new Error("Invalid hex escape: \\x" + hex2);
                }
                var charCode2:Number = parseInt(hex2, 16);
                if (isNaN(charCode2)) {
                    throw new Error("Invalid hex escape: \\x" + hex2);
                }
                node = new ASTNode('Literal');
                node.value = String.fromCharCode(charCode2);
                node = parseQuantifier(node);
            } else if (nextChar == 'u') {
                // \uHHHH: 四位十六进制表示的 Unicode 字符
                var hex4:String = "";
                if (this.index < this.length) hex4 += consume();
                if (this.index < this.length) hex4 += consume();
                if (this.index < this.length) hex4 += consume();
                if (this.index < this.length) hex4 += consume();
                if (hex4.length != 4) {
                    throw new Error("Invalid unicode escape: \\u" + hex4);
                }
                var charCode4:Number = parseInt(hex4, 16);
                if (isNaN(charCode4)) {
                    throw new Error("Invalid unicode escape: \\u" + hex4);
                }
                node = new ASTNode('Literal');
                node.value = String.fromCharCode(charCode4);
                node = parseQuantifier(node);
            } else if (isDigit(nextChar)) {
                // 处理回溯引用，如 \1, \2
                var numberStr:String = nextChar;
                while (this.index < this.length && isDigit(peek())) {
                    numberStr += consume();
                }
                var backRefNum:Number = parseInt(numberStr);
                node = new ASTNode('BackReference');
                node.value = backRefNum;
                node = parseQuantifier(node);
            } else if (isSpecialChar(nextChar)) {
                // 处理转义的特殊字符，如 \., \*, \+, etc.
                var escapedChar:String = getEscapedChar(nextChar);
                node = new ASTNode('Literal');
                node.value = escapedChar;
                node = parseQuantifier(node);
            } else {
                // 处理转义的普通字符，如 \a, \b 等
                var literalChar:String = getEscapedChar(nextChar);
                node = new ASTNode('Literal');
                node.value = literalChar;
                node = parseQuantifier(node);
            }
        } else {
            // 处理字面量字符
            node = new ASTNode('Literal');
            node.value = consume();
            node = parseQuantifier(node);
        }
        return node;
    }

    /**
     * 判断字符是否为特殊字符，需要被转义
     */
    private function isSpecialChar(char:String):Boolean {
        return ['.', '*', '+', '?', '{', '}', '[', ']', '(', ')', '|', '\\', '^', '$', '/'].indexOf(char) >= 0;
    }

    /**
     * 解析分组，包括捕获组和非捕获组
     */
    private function parseGroup():ASTNode {
        consume(); // 跳过 '('
        var node:ASTNode = new ASTNode('Group');
        if (peek() == '?') {
            consume(); // 跳过 '?'
            if (peek() == ':') {
                consume(); // 跳过 ':'
                node.capturing = false; // 非捕获分组
            } else if (peek() == '=') {
                consume(); // 跳过 '='
                node.type = 'PositiveLookahead';
                node.capturing = false;
            } else if (peek() == '!') {
                consume(); // 跳过 '!'
                node.type = 'NegativeLookahead';
                node.capturing = false;
            } else if (peek() == '<') {
                consume(); // 跳过 '<'
                var lookbehindType:String = peek();
                if (lookbehindType == '=') {
                    consume();
                    node.type = 'PositiveLookbehind';
                } else if (lookbehindType == '!') {
                    consume();
                    node.type = 'NegativeLookbehind';
                } else {
                    var groupName:String = parseGroupName();
                    if (peek() != '>') {
                        throw new Error("Unclosed named capture group at position " + this.index);
                    }
                    consume(); // 跳过 '>'
                    node.capturing = true;
                    this.groupCount += 1;
                    node.groupNumber = this.groupCount;
                    node.groupName = groupName;
                    this.groupNames[this.groupCount] = groupName;
                }
                if (node.type == 'PositiveLookbehind' || node.type == 'NegativeLookbehind') {
                    node.capturing = false;
                }
            } else {
                throw new Error("Unsupported group syntax '(?" + peek() + "' at position " + this.index);
            }
        } else {
            node.capturing = true; // 捕获分组
            this.groupCount += 1;
            node.groupNumber = this.groupCount; // 分配组编号
        }
        node.child = parseExpression();
        if (peek() != ')') {
            throw new Error("Unclosed group '(' at position " + this.index);
        }
        consume(); // 跳过 ')'
        node = parseQuantifier(node);
        return node;
    }

    /**
     * 解析字符集，如 [a-z]
     */
    private function parseCharacterClass():ASTNode {
        var node:ASTNode = new ASTNode('CharacterClass');
        consume(); // 跳过 '['
        if (peek() == '^') {
            node.negated = true;
            consume(); // 跳过 '^'
        } else {
            node.negated = false;
        }
        var chars:Array = [];
        while (this.index < this.length && peek() != ']') {
            var startCharCode:Number = -1;
            var char:String = consume();
            
            if (char == '\\') {
                if (this.index >= this.length) {
                    throw new Error("Escape character '\\' in character class at end of pattern");
                }
                var escapedCharInClass:String = consume();
                if (escapedCharInClass == 'd') {
                    // 展开 \d 为 0-9
                    for (var digit:Number = 48; digit <= 57; digit++) {
                        chars.push(String.fromCharCode(digit));
                    }
                } else if (escapedCharInClass == 'D') {
                    // \D 在字符类中：匹配所有非数字字符
                    for (var dCode:Number = 0; dCode <= 255; dCode++) {
                        if (dCode < 48 || dCode > 57) {
                            chars.push(String.fromCharCode(dCode));
                        }
                    }
                } else if (escapedCharInClass == 'w') {
                    // 展开 \w 为 a-z, A-Z, 0-9, _
                    for (var i:Number = 97; i <= 122; i++) chars.push(String.fromCharCode(i));
                    for (var j:Number = 65; j <= 90; j++) chars.push(String.fromCharCode(j));
                    for (var k:Number = 48; k <= 57; k++) chars.push(String.fromCharCode(k));
                    chars.push('_');
                } else if (escapedCharInClass == 'W') {
                    // \W 在字符类中：匹配所有非单词字符
                    for (var wCode:Number = 0; wCode <= 255; wCode++) {
                        if (!((wCode >= 48 && wCode <= 57) ||
                              (wCode >= 65 && wCode <= 90) ||
                              (wCode >= 97 && wCode <= 122) ||
                              wCode == 95)) {
                            chars.push(String.fromCharCode(wCode));
                        }
                    }
                } else if (escapedCharInClass == 's') {
                    // 展开 \s 为空白字符
                    chars.push(' ');
                    chars.push('\t');
                    chars.push('\r');
                    chars.push('\n');
                } else if (escapedCharInClass == 'S') {
                    // \S 在字符类中：匹配所有非空白字符
                    for (var sCode:Number = 0; sCode <= 255; sCode++) {
                        if (!(sCode == 32 || sCode == 9 || sCode == 10 ||
                              sCode == 13 || sCode == 12 || sCode == 11)) {
                            chars.push(String.fromCharCode(sCode));
                        }
                    }
                } else if (escapedCharInClass == 'x') {
                    // \xHH: 两位十六进制表示的 ASCII 字符（在字符类中）
                    var hex2cls:String = "";
                    if (this.index < this.length) hex2cls += consume();
                    if (this.index < this.length) hex2cls += consume();
                    if (hex2cls.length == 2) {
                        startCharCode = parseInt(hex2cls, 16);
                        if (!isNaN(startCharCode)) {
                            chars.push(String.fromCharCode(startCharCode));
                        }
                    }
                } else if (escapedCharInClass == 'u') {
                    // \uHHHH: 四位十六进制表示的 Unicode 字符（在字符类中）
                    var hex4cls:String = "";
                    if (this.index < this.length) hex4cls += consume();
                    if (this.index < this.length) hex4cls += consume();
                    if (this.index < this.length) hex4cls += consume();
                    if (this.index < this.length) hex4cls += consume();
                    if (hex4cls.length == 4) {
                        startCharCode = parseInt(hex4cls, 16);
                        if (!isNaN(startCharCode)) {
                            chars.push(String.fromCharCode(startCharCode));
                        }
                    }
                } else {
                    // 其他转义字符
                    var escChar:String = getEscapedChar(escapedCharInClass);
                    startCharCode = escChar.charCodeAt(0);
                    chars.push(escChar);
                }
            } else {
                // 普通字符
                startCharCode = char.charCodeAt(0);
                chars.push(char);
            }
            
            // 检查是否是范围
            if (peek() == '-' && this.index + 1 < this.length && this.pattern.charAt(this.index + 1) != ']') {
                consume(); // 跳过 '-'
                var endCharRaw:String = consume();
                var endCode:Number;
                
                if (endCharRaw == '\\') {
                    if (this.index >= this.length) {
                        throw new Error("Escape character '\\' in character range at end of pattern");
                    }
                    var endEsc:String = consume();
                    if (endEsc == 'x') {
                        // \xHH 范围结束
                        var endHex2:String = "";
                        if (this.index < this.length) endHex2 += consume();
                        if (this.index < this.length) endHex2 += consume();
                        endCode = parseInt(endHex2, 16);
                    } else if (endEsc == 'u') {
                        // \uHHHH 范围结束
                        var endHex4:String = "";
                        if (this.index < this.length) endHex4 += consume();
                        if (this.index < this.length) endHex4 += consume();
                        if (this.index < this.length) endHex4 += consume();
                        if (this.index < this.length) endHex4 += consume();
                        endCode = parseInt(endHex4, 16);
                    } else {
                        endCode = getEscapedChar(endEsc).charCodeAt(0);
                    }
                } else {
                    endCode = endCharRaw.charCodeAt(0);
                }
                
                // 使用 startCharCode 作为起始点
                if (startCharCode >= 0 && !isNaN(endCode)) {
                    if (startCharCode > endCode) {
                        throw new Error("Invalid character range in character class");
                    }
                    // 移除最后添加的字符，用范围替换
                    chars.pop();
                    for (var code:Number = startCharCode; code <= endCode; code++) {
                        chars.push(String.fromCharCode(code));
                    }
                }
            }
        }
        if (peek() != ']') {
            throw new Error("Unclosed character class '[' at position " + this.index);
        }
        consume(); // 跳过 ']'
        node.value = chars;
        node.buildCharacterClassCache();
        return node;
    }

    /**
     * 解析量词，如 *, +, ?, {m,n}
     */
    private function parseQuantifier(node:ASTNode):ASTNode {
        if (this.index >= this.length) {
            return node;
        }
        var char:String = peek();
        var quantNode:ASTNode = null;
        if (char == '*' || char == '+' || char == '?' || char == '{') {
            quantNode = new ASTNode('Quantifier');
            quantNode.child = node;
            if (char == '*') {
                quantNode.min = 0;
                quantNode.max = Number.MAX_VALUE;
                consume();
            } else if (char == '+') {
                quantNode.min = 1;
                quantNode.max = Number.MAX_VALUE;
                consume();
            } else if (char == '?') {
                quantNode.min = 0;
                quantNode.max = 1;
                consume();
            } else if (char == '{') {
                consume(); // 跳过 '{'
                var quantStr:String = "";
                while (this.index < this.length && peek() != '}') {
                    quantStr += consume();
                }
                if (peek() != '}') {
                    throw new Error("Unclosed quantifier '{' at position " + this.index);
                }
                consume(); // 跳过 '}'
                var parts:Array = quantStr.split(',');
                quantNode.min = parseInt(parts[0]);
                if (parts.length == 1) {
                    quantNode.max = quantNode.min;
                } else if (parts.length == 2) {
                    if (parts[1] == "") {
                        quantNode.max = Number.MAX_VALUE;
                    } else {
                        quantNode.max = parseInt(parts[1]);
                    }
                } else {
                    throw new Error("Invalid quantifier format: {" + quantStr + "} at position " + this.index);
                }
                // 验证 min <= max
                if (quantNode.min > quantNode.max) {
                    throw new Error("Invalid quantifier: {" + quantNode.min + "," + quantNode.max + "} at position " + this.index);
                }
            }
            // 检查是否为非贪婪量词
            if (peek() == '?') {
                quantNode.greedy = false;
                consume(); // 跳过 '?'
            } else {
                quantNode.greedy = true;
            }
            return quantNode;
        } else {
            return node;
        }
    }

    /**
     * 获取下一个字符并推进索引
     */
    private function consume():String {
        return this.pattern.charAt(this.index++);
    }

    /**
     * 查看当前字符但不推进索引
     */
    private function peek():String {
        return this.pattern.charAt(this.index);
    }

    /**
     * 判断字符是否为数字
     */
    private function isDigit(char:String):Boolean {
        var code:Number = char.charCodeAt(0);
        return code >= 48 && code <= 57; // '0' to '9'
    }

    private function parseGroupName():String {
        var name:String = "";
        if (this.index >= this.length || !isGroupNameStart(peek())) {
            throw new Error("Invalid named capture group at position " + this.index);
        }
        name += consume();
        while (this.index < this.length && peek() != '>') {
            if (!isGroupNamePart(peek())) {
                throw new Error("Invalid named capture group at position " + this.index);
            }
            name += consume();
        }
        return name;
    }

    private function isGroupNameStart(char:String):Boolean {
        var code:Number = char.charCodeAt(0);
        return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95;
    }

    private function isGroupNamePart(char:String):Boolean {
        return isGroupNameStart(char) || isDigit(char);
    }

    /**
     * 获取转义字符对应的字面量
     */
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

    /**
     * 获取总捕获组数
     * @return 总捕获组数。
     */
    public function getTotalGroups():Number {
        return this.groupCount;
    }

    public function getGroupNames():Array {
        return this.groupNames;
    }
}
