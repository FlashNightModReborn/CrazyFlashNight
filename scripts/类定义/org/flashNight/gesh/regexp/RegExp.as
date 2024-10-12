import org.flashNight.gesh.regexp.*;

class org.flashNight.gesh.regexp.RegExp {
    private var pattern:String;
    private var flags:String;
    private var ast:ASTNode;
    private var ignoreCase:Boolean;
    private var global:Boolean;
    private var multiline:Boolean;
    public var lastIndex:Number = 0; // 新增属性
    private var totalGroups:Number; // 新增属性，记录总捕获组数

    public function RegExp(pattern:String, flags:String) {
        this.pattern = pattern;
        this.flags = flags;
        this.ignoreCase = flags.indexOf('i') >= 0;
        this.global = flags.indexOf('g') >= 0;
        this.multiline = flags.indexOf('m') >= 0;
        this.lastIndex = 0;
        this.parse();
    }

    private function parse():Void {
        try {
            var parser:Parser = new Parser(this.pattern);
            this.ast = parser.parse();
            this.totalGroups = parser.getTotalGroups(); // 获取总捕获组数
        } catch (e:Error) {
            trace("正则表达式解析错误：" + e.message);
            this.ast = null;
            this.totalGroups = 0;
        }
    }

    public function test(input:String):Boolean {
        if (this.ast == null) return false;
        var inputLength:Number = input.length;
        var startPos:Number = 0;
        if (this.pattern.charAt(0) == '^') {
            var captures:Array = initializeCaptures();
            var result:Object = this.ast.match(input, 0, captures, this.ignoreCase);
            return result.matched && result.position <= inputLength;
        } else {
            for (var pos:Number = 0; pos <= inputLength; pos++) {
                var captures:Array = initializeCaptures();
                var result:Object = this.ast.match(input, pos, captures, this.ignoreCase);
                if (result.matched) {
                    return true;
                }
            }
            return false;
        }
    }

    public function exec(input:String):Array {
        if (this.ast == null) return null;
        var inputLength:Number = input.length;
        var lastIndex:Number = this.global ? this.lastIndex : 0;
        for (var pos:Number = lastIndex; pos <= inputLength; pos++) {
            // Initialize captures array with nulls
            var captures:Array = initializeCaptures();
            var result:Object = this.ast.match(input, pos, captures, this.ignoreCase);
            if (result.matched) {
                captures[0] = input.substring(pos, result.position); // Entire match
                captures.index = pos;
                captures.input = input;
                if (this.global) {
                    this.lastIndex = result.position;
                }
                return captures;
            }
        }
        if (this.global) {
            this.lastIndex = 0;
        }
        return null;
    }

    // 新增方法：初始化 captures 数组
    private function initializeCaptures():Array {
        var captures:Array = new Array(this.totalGroups + 1);
        for (var i:Number = 0; i <= this.totalGroups; i++) {
            captures[i] = null;
        }
        return captures;
    }

    // 静态方法：注入正则表达式相关方法
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
            while ((match = re.exec(this)) != null && result.length < limit) {
                result.push(this.substring(lastPos, match.index));
                lastPos = re.lastIndex;
            }
            result.push(this.substring(lastPos));
            return result;
        };
    }


    // 静态方法：移除注入的正则表达式相关方法
    public static function removeMethods():Void {
        delete String.prototype.regexp_match;
        delete String.prototype.regexp_replace;
        delete String.prototype.regexp_search;
        delete String.prototype.regexp_split;
    }
}
