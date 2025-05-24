import org.flashNight.gesh.regexp.*;

/**
 * RegExp 类实现了一个正则表达式引擎，用于在字符串中执行模式匹配、搜索和替换操作。
 */
class org.flashNight.gesh.regexp.RegExp {
    private var pattern:String;
    private var flags:String;
    private var ast:ASTNode;
    private var ignoreCase:Boolean;
    private var global:Boolean;
    private var multiline:Boolean;
    public var lastIndex:Number = 0; // 记录上一次匹配的结束位置
    private var totalGroups:Number; // 记录总捕获组数

    /**
     * 构造函数，初始化 RegExp 实例。
     * @param pattern 正则表达式模式字符串。
     * @param flags 正则表达式标志，如 'i', 'g', 'm'。
     */
    public function RegExp(pattern:String, flags:String) {
        this.pattern = pattern;
        this.flags = flags;
        this.ignoreCase = flags.indexOf('i') >= 0;
        this.global = flags.indexOf('g') >= 0;
        this.multiline = flags.indexOf('m') >= 0;
        this.lastIndex = 0;
        this.parse();
    }

    /**
     * 解析正则表达式模式，生成 AST（抽象语法树）。
     * @throws Error 如果解析失败。
     */
    private function parse():Void {
        var parser:Parser = new Parser(this.pattern, this.flags);
        this.ast = parser.parse();
        this.totalGroups = parser.getTotalGroups();
    }

    /**
     * 测试输入字符串是否匹配正则表达式模式。
     * @param input 输入字符串。
     * @return 如果匹配返回 true，否则返回 false。
     */
    public function test(input:String):Boolean {
        if (this.ast == null) return false;
        var inputLength:Number = input.length;
        var startPos:Number = 0;

        if (this.pattern.charAt(0) == '^') {
            // 模式以 ^ 开头，必须从字符串起始位置匹配
            var captures:Array = initializeCaptures();
            var result:Object = this.ast.match(input, 0, captures, this.ignoreCase);
            return result.matched && (this.multiline || result.position == inputLength);
        } else {
            // 遍历字符串中的每个位置进行匹配
            for (var pos:Number = 0; pos <= inputLength; pos++) {
                var captures:Array = initializeCaptures();
                var result:Object = this.ast.match(input, pos, captures, this.ignoreCase);
                if (result.matched) {
                    if (!this.multiline) {
                        return true;
                    } else {
                        // 在多行模式下，确保匹配符合行的边界
                        return true;
                    }
                }
            }
            return false;
        }
    }

    /**
     * 执行正则表达式匹配，并返回匹配结果数组。
     * @param input 输入字符串。
     * @return 如果匹配成功，返回包含匹配结果和捕获组的数组；否则返回 null。
     */
    public function exec(input:String):Array {
        if (this.ast == null) return null;
        var inputLength:Number = input.length;
        var lastIndex:Number = this.global ? this.lastIndex : 0;

        for (var pos:Number = lastIndex; pos <= inputLength; pos++) {
            var captures:Array = initializeCaptures();
            var result:Object = this.ast.match(input, pos, captures, this.ignoreCase);
            if (result.matched) {
                captures[0] = input.substring(pos, result.position); // 整个匹配结果
                captures.index = pos;
                captures.input = input;
                if (this.global) {
                    this.lastIndex = result.position;
                }
                return captures;
            }
        }

        if (this.global) {
            this.lastIndex = 0; // 重置 lastIndex
        }
        return null;
    }

    /**
     * 初始化捕获组数组，确保数组长度足够存储所有捕获组。
     * @return 初始化后的捕获组数组。
     */
    private function initializeCaptures():Array {
        var captures:Array = new Array(this.totalGroups + 1);
        for (var i:Number = 0; i <= this.totalGroups; i++) {
            captures[i] = null;
        }
        return captures;
    }

    /**
     * 注入正则表达式相关方法到 String.prototype。
     * 方法包括 regexp_match, regexp_replace, regexp_search, regexp_split。
     */
    public static function injectMethods():Void {
        // 注入 regexp_match 方法
        String.prototype.regexp_match = function(re:RegExp):Array {
            if (!(re instanceof RegExp)) {
                return null;
            }
            var matches:Array = [];
            re.lastIndex = 0;
            var match:Array;
            while ((match = re.exec(this)) != null) {
                matches.push(match[0]);
                if (!re.global) {
                    break;
                }
                // 防止无限循环：如果 lastIndex 没有推进，则跳出循环
                if (match.index === re.lastIndex) {
                    break;
                }
            }
            return matches.length > 0 ? matches : null;
        };

        // 注入 regexp_replace 方法
        String.prototype.regexp_replace = function(re:RegExp, replacement:String):String {
            if (!(re instanceof RegExp)) {
                return this;
            }
            var result:String = "";
            var lastPos:Number = 0;
            var match:Array;
            re.lastIndex = 0;
            while ((match = re.exec(this)) != null) {
                result += this.substring(lastPos, match.index) + replacement;
                lastPos = re.lastIndex;
                if (!re.global) {
                    break;
                }
                // 防止无限循环
                if (match.index === re.lastIndex) {
                    break;
                }
            }
            result += this.substring(lastPos);
            return result;
        };

        // 注入 regexp_search 方法
        String.prototype.regexp_search = function(re:RegExp):Number {
            if (!(re instanceof RegExp)) {
                return -1;
            }
            re.lastIndex = 0;
            var match:Array = re.exec(this);
            return match ? match.index : -1;
        };

        // 注入 regexp_split 方法
        String.prototype.regexp_split = function(re:RegExp, limit:Number):Array {
            if (!(re instanceof RegExp)) {
                return this.split(re, limit);
            }
            if (limit == undefined) {
                limit = 9999;
            }
            var result:Array = [];
            var lastPos:Number = 0;
            var match:Array;
            re.lastIndex = 0;
            while ((match = re.exec(this)) != null && result.length < limit - 1) {
                result.push(this.substring(lastPos, match.index));
                lastPos = re.lastIndex;
                // 防止无限循环
                if (match.index === re.lastIndex) {
                    break;
                }
            }
            result.push(this.substring(lastPos));
            return result;
        };
    }

    /**
     * 移除注入到 String.prototype 的正则表达式相关方法。
     */
    public static function removeMethods():Void {
        delete String.prototype.regexp_match;
        delete String.prototype.regexp_replace;
        delete String.prototype.regexp_search;
        delete String.prototype.regexp_split;
    }
}
