import org.flashNight.gesh.regexp.*;

/**
 * RegExp 类实现了一个正则表达式引擎，用于在字符串中执行模式匹配、搜索和替换操作。
 */
class org.flashNight.gesh.regexp.RegExp {
    public var source:String;
    public var flags:String;

    private var ast:ASTNode;
    private var ignoreCase:Boolean;
    private var global:Boolean;
    private var multiline:Boolean;
    private var dotAll:Boolean;
    private var totalGroups:Number;
    private var groupNames:Array;

    public var lastIndex:Number = 0;

    public function RegExp(pattern:String, flags:String) {
        if (pattern == null) {
            pattern = "";
        }
        if (flags == null) {
            flags = "";
        }

        this.source = pattern;
        this.flags = flags;
        this.ignoreCase = flags.indexOf("i") >= 0;
        this.global = flags.indexOf("g") >= 0;
        this.multiline = flags.indexOf("m") >= 0;
        this.dotAll = flags.indexOf("s") >= 0;
        this.totalGroups = 0;
        this.groupNames = [];
        this.lastIndex = 0;
        this.parse();
    }

    private function parse():Void {
        var parser:Parser = new Parser(this.source, this.flags);
        this.ast = parser.parse();
        this.totalGroups = parser.getTotalGroups();
        this.groupNames = parser.getGroupNames();
    }

    public function test(input:String):Boolean {
        if (this.ast == null) {
            return false;
        }

        var inputLength:Number = length(input);
        var pos:Number;
        var result:Object;

        if (length(this.source) > 0 && this.source.charAt(0) == "^") {
            result = this.ast.match(input, 0, initializeCaptures(), this.ignoreCase, this.multiline, this.dotAll);
            if (result.matched) {
                return true;
            }

            if (this.multiline) {
                for (pos = 0; pos < inputLength; pos++) {
                    if (input.charAt(pos) == "\n") {
                        result = this.ast.match(input, pos + 1, initializeCaptures(), this.ignoreCase, this.multiline, this.dotAll);
                        if (result.matched) {
                            return true;
                        }
                    }
                }
            }
            return false;
        }

        for (pos = 0; pos <= inputLength; pos++) {
            result = this.ast.match(input, pos, initializeCaptures(), this.ignoreCase, this.multiline, this.dotAll);
            if (result.matched) {
                return true;
            }
        }
        return false;
    }

    public function exec(input:String):Array {
        if (this.ast == null) {
            return null;
        }

        var inputLength:Number = length(input);
        var startIndex:Number = this.global ? this.lastIndex : 0;
        var pos:Number;
        var captures:Array;
        var result:Object;
        var endIndex:Number;
        var nextIndex:Number;

        for (pos = startIndex; pos <= inputLength; pos++) {
            captures = initializeCaptures();
            result = this.ast.match(input, pos, captures, this.ignoreCase, this.multiline, this.dotAll);
            if (result.matched) {
                endIndex = result.position;
                captures[0] = input.substring(pos, endIndex);
                captures.index = pos;
                captures.input = input;
                captures.endIndex = endIndex;
                applyNamedGroups(captures);

                if (this.global) {
                    nextIndex = endIndex;
                    if (nextIndex == pos) {
                        nextIndex = pos + 1;
                    }
                    if (nextIndex > inputLength + 1) {
                        nextIndex = inputLength + 1;
                    }
                    this.lastIndex = nextIndex;
                }
                return captures;
            }
        }

        if (this.global) {
            this.lastIndex = 0;
        }
        return null;
    }

    private function initializeCaptures():Array {
        var captures:Array = new Array(this.totalGroups + 1);
        var i:Number;
        for (i = 0; i <= this.totalGroups; i++) {
            captures[i] = null;
        }
        return captures;
    }

    private function applyNamedGroups(captures:Array):Void {
        if (this.groupNames == null || this.groupNames.length == 0) {
            return;
        }

        var groups:Object = new Object();
        var hasNamedGroup:Boolean = false;
        var i:Number;
        var name:String;
        for (i = 1; i < this.groupNames.length; i++) {
            name = this.groupNames[i];
            if (name != undefined && name != null && name != "") {
                groups[name] = captures[i];
                hasNamedGroup = true;
            }
        }

        if (hasNamedGroup) {
            captures.groups = groups;
        }
    }

    public static function injectMethods():Void {
        String.prototype.regexp_match = function(re:RegExp):Array {
            if (!(re instanceof RegExp)) {
                return null;
            }

            var input:String = String(this);
            var matches:Array = [];
            var match:Array;
            re.lastIndex = 0;

            while ((match = re.exec(input)) != null) {
                matches.push(match[0]);
                if (!re.global) {
                    break;
                }
            }
            return matches.length > 0 ? matches : null;
        };

        String.prototype.regexp_replace = function(re:RegExp, replacement:String):String {
            if (!(re instanceof RegExp)) {
                return String(this);
            }

            var input:String = String(this);
            var result:String = "";
            var lastPos:Number = 0;
            var match:Array;
            var endIndex:Number;
            re.lastIndex = 0;

            while ((match = re.exec(input)) != null) {
                endIndex = match.endIndex != undefined ? Number(match.endIndex) : match.index + length(match[0]);
                result += input.substring(lastPos, match.index);
                result += RegExp.expandReplacement(replacement, match);
                lastPos = endIndex;

                if (!re.global) {
                    break;
                }
            }

            result += input.substring(lastPos);
            return result;
        };

        String.prototype.regexp_search = function(re:RegExp):Number {
            if (!(re instanceof RegExp)) {
                return -1;
            }

            var input:String = String(this);
            re.lastIndex = 0;
            var match:Array = re.exec(input);
            return match ? match.index : -1;
        };

        String.prototype.regexp_split = function(re:RegExp, limit:Number):Array {
            if (!(re instanceof RegExp)) {
                return String(this).split(String(re), limit);
            }
            if (limit == undefined) {
                limit = 9999;
            }

            var input:String = String(this);
            var splitRe:RegExp = RegExp.cloneWithGlobal(re);
            var result:Array = [];
            var lastPos:Number = 0;
            var match:Array;
            var endIndex:Number;
            splitRe.lastIndex = 0;

            while ((match = splitRe.exec(input)) != null && result.length < limit - 1) {
                result.push(input.substring(lastPos, match.index));
                endIndex = match.endIndex != undefined ? Number(match.endIndex) : match.index + length(match[0]);
                lastPos = endIndex;
            }

            result.push(input.substring(lastPos));
            return result;
        };
    }

    public static function removeMethods():Void {
        delete String.prototype.regexp_match;
        delete String.prototype.regexp_replace;
        delete String.prototype.regexp_search;
        delete String.prototype.regexp_split;
    }

    private static function cloneWithGlobal(re:RegExp):RegExp {
        return new RegExp(re.source, ensureFlag(re.flags, "g"));
    }

    private static function ensureFlag(flags:String, flag:String):String {
        if (flags == null) {
            flags = "";
        }
        if (flags.indexOf(flag) >= 0) {
            return flags;
        }
        return flags + flag;
    }

    private static function expandReplacement(replacement:String, match:Array):String {
        var result:String = "";
        var replacementLength:Number = length(replacement);
        var i:Number = 0;
        var nextChar:String;
        var digitToken:String;
        var name:String;
        var scanIndex:Number;
        var endIndex:Number;

        while (i < replacementLength) {
            if (replacement.charAt(i) != "$" || i + 1 >= replacementLength) {
                result += replacement.charAt(i);
                i += 1;
                continue;
            }

            nextChar = replacement.charAt(i + 1);
            if (nextChar == "$") {
                result += "$";
                i += 2;
            } else if (nextChar == "&") {
                result += match[0];
                i += 2;
            } else if (nextChar == "`") {
                result += match.input.substring(0, match.index);
                i += 2;
            } else if (nextChar == "'") {
                endIndex = match.endIndex != undefined ? Number(match.endIndex) : match.index + length(match[0]);
                result += match.input.substring(endIndex);
                i += 2;
            } else if (nextChar == "<") {
                name = "";
                scanIndex = i + 2;
                while (scanIndex < replacementLength && replacement.charAt(scanIndex) != ">") {
                    name += replacement.charAt(scanIndex);
                    scanIndex += 1;
                }
                if (scanIndex < replacementLength && match.groups != undefined && match.groups[name] != undefined) {
                    result += match.groups[name];
                    i = scanIndex + 1;
                } else {
                    result += "$<";
                    result += name;
                    if (scanIndex < replacementLength && replacement.charAt(scanIndex) == ">") {
                        result += ">";
                        i = scanIndex + 1;
                    } else {
                        i = scanIndex;
                    }
                }
            } else if (RegExp.isDigit(nextChar)) {
                digitToken = nextChar;
                i += 2;
                while (i < replacementLength && RegExp.isDigit(replacement.charAt(i))) {
                    digitToken += replacement.charAt(i);
                    i += 1;
                }
                if (match[Number(digitToken)] != undefined && match[Number(digitToken)] != null) {
                    result += match[Number(digitToken)];
                }
            } else {
                result += "$";
                i += 1;
            }
        }

        return result;
    }

    private static function isDigit(char:String):Boolean {
        var code:Number = char.charCodeAt(0);
        return code >= 48 && code <= 57;
    }
}
