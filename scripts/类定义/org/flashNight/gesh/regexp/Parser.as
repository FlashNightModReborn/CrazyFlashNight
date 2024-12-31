import org.flashNight.gesh.regexp.ASTNode;

class org.flashNight.gesh.regexp.Parser {
    private var pattern:String;
    private var index:Number;
    private var length:Number;
    private var ignoreCase:Boolean;
    private var groupCount:Number;

    public function Parser(pattern:String, flags:String) {
        this.pattern = pattern;
        this.index = 0;
        this.length = pattern.length;
        this.ignoreCase = flags.indexOf('i') >= 0;
        this.groupCount = 0;
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
                var lookbehindType:String = consume();
                if (lookbehindType == '=') {
                    node.type = 'PositiveLookbehind';
                } else if (lookbehindType == '!') {
                    node.type = 'NegativeLookbehind';
                } else {
                    throw new Error("Invalid group syntax '(?<" + lookbehindType + "' at position " + this.index);
                }
                node.capturing = false;
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
            var char:String = consume();
            if (char == '\\') {
                if (this.index >= this.length) {
                    throw new Error("Escape character '\\' in character class at end of pattern");
                }
                var escapedCharInClass:String = consume();
                if (isSpecialChar(escapedCharInClass)) {
                    chars.push(getEscapedChar(escapedCharInClass));
                } else {
                    chars.push(getEscapedChar(escapedCharInClass));
                }
            }
            if (peek() == '-' && this.index + 1 < this.length && this.pattern.charAt(this.index + 1) != ']') {
                consume(); // 跳过 '-'
                var endChar:String = consume();
                if (endChar == '\\') {
                    if (this.index >= this.length) {
                        throw new Error("Escape character '\\' in character range at end of pattern");
                    }
                    endChar = consume();
                    endChar = getEscapedChar(endChar);
                }
                var startCode:Number = char.charCodeAt(0);
                var endCode:Number = endChar.charCodeAt(0);
                if (startCode > endCode) {
                    throw new Error("Invalid character range '" + char + "-" + endChar + "' in character class");
                }
                for (var code:Number = startCode; code <= endCode; code++) {
                    chars.push(String.fromCharCode(code));
                }
            } else {
                chars.push(char);
            }
        }
        if (peek() != ']') {
            throw new Error("Unclosed character class '[' at position " + this.index);
        }
        consume(); // 跳过 ']'
        node.value = chars;
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
}
