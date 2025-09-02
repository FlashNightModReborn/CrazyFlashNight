import JSON;
import org.flashNight.gesh.object.*;
import org.flashNight.gesh.string.*;
class org.flashNight.gesh.string.StringUtils {
    
    // 私有静态实例，用于单例模式
    private static var instance:StringUtils = null;
    
    // 映射对象：HTML 实体到字符
    private var htmlEntities:Object;
    
    // 映射对象：字符到 HTML 实体
    private var htmlEntitiesReverse:Object;
    
    // 私有构造函数，防止外部实例化
    private function StringUtils() {
        // 初始化 htmlEntities 映射
        htmlEntities = new Object();
        htmlEntities["&amp;"] = "&";
        htmlEntities["&lt;"] = "<";
        htmlEntities["&gt;"] = ">";
        htmlEntities["&quot;"] = "\"";
        htmlEntities["&apos;"] = "'";
        htmlEntities["&copy;"] = "©";
        htmlEntities["&reg;"] = "®";
        htmlEntities["&trade;"] = "™";
        htmlEntities["&deg;"] = "°";
        htmlEntities["&plusmn;"] = "±";
        htmlEntities["&sup2;"] = "²";
        htmlEntities["&sup3;"] = "³";
        htmlEntities["&frac14;"] = "¼";
        htmlEntities["&frac12;"] = "½";
        htmlEntities["&frac34;"] = "¾";
        htmlEntities["&times;"] = "×";
        htmlEntities["&divide;"] = "÷";
        htmlEntities["&iexcl;"] = "¡";
        htmlEntities["&cent;"] = "¢";
        htmlEntities["&pound;"] = "£";
        htmlEntities["&curren;"] = "¤";
        htmlEntities["&yen;"] = "¥";
        htmlEntities["&brvbar;"] = "¦";
        htmlEntities["&sect;"] = "§";
        htmlEntities["&uml;"] = "¨";
        htmlEntities["&ordf;"] = "ª";
        htmlEntities["&laquo;"] = "«";
        htmlEntities["&not;"] = "¬";
        htmlEntities["&shy;"] = "­";
        htmlEntities["&macr;"] = "¯";
        
        // 初始化 htmlEntitiesReverse 映射
        htmlEntitiesReverse = new Object();
        htmlEntitiesReverse["&"] = "&amp;";
        htmlEntitiesReverse["<"] = "&lt;";
        htmlEntitiesReverse[">"] = "&gt;";
        htmlEntitiesReverse["\""] = "&quot;";
        htmlEntitiesReverse["'"] = "&apos;";
        // 移除空格和换行的转义
        // htmlEntitiesReverse[" "] = "&nbsp;";
        // htmlEntitiesReverse["\n"] = "&NewLine;";
        htmlEntitiesReverse["©"] = "&copy;";
        htmlEntitiesReverse["®"] = "&reg;";
        htmlEntitiesReverse["™"] = "&trade;";
        htmlEntitiesReverse["°"] = "&deg;";
        htmlEntitiesReverse["±"] = "&plusmn;";
        htmlEntitiesReverse["²"] = "&sup2;";
        htmlEntitiesReverse["³"] = "&sup3;";
        htmlEntitiesReverse["¼"] = "&frac14;";
        htmlEntitiesReverse["½"] = "&frac12;";
        htmlEntitiesReverse["¾"] = "&frac34;";
        htmlEntitiesReverse["×"] = "&times;";
        htmlEntitiesReverse["÷"] = "&divide;";
        htmlEntitiesReverse["¡"] = "&iexcl;";
        htmlEntitiesReverse["¢"] = "&cent;";
        htmlEntitiesReverse["£"] = "&pound;";
        htmlEntitiesReverse["¤"] = "&curren;";
        htmlEntitiesReverse["¥"] = "&yen;";
        htmlEntitiesReverse["¦"] = "&brvbar;";
        htmlEntitiesReverse["§"] = "&sect;";
        htmlEntitiesReverse["¨"] = "&uml;";
        htmlEntitiesReverse["ª"] = "&ordf;";
        htmlEntitiesReverse["«"] = "&laquo;";
        htmlEntitiesReverse["¬"] = "&not;";
        htmlEntitiesReverse["­"] = "&shy;";
        htmlEntitiesReverse["¯"] = "&macr;";
    }
    
    // 获取单例实例的方法
    private static function getInstance():StringUtils {
        if (instance == null) {
            instance = new StringUtils();
        }
        return instance;
    }
    
    // ------------------- 静态方法 -------------------

    /**
     * 使用 RLE 和 LZW 组合压缩字符串
     * 
     * @param input 要压缩的字符串
     * @return 压缩后的字符串（经过 16 进制编码）
     */
    public static function compress(input:String):String {
        if (input == null || input.length == 0) {
            return "";
        }

        // 1. 先进行 RLE 压缩
        var rleCompressed:String = RLE.compress(input);
        trace("RLE 压缩后的结果: " + rleCompressed);
        
        // 2. 再进行 LZW 压缩
        var lzwCompressed:String = LZW.compress(rleCompressed);
        trace("LZW 压缩后的结果: " + lzwCompressed);
        
        // 3. 使用 Hex16Encoder 对最终的压缩结果进行 16 进制编码以减少存储空间
        var hexEncoded:String = Hex16Encoder.encode(lzwCompressed);
        trace("LZW 压缩并编码后的结果: " + hexEncoded);
        
        // 4. 返回压缩并编码的最终结果
        return hexEncoded;
    }

    /**
     * 解压缩字符串
     * 
     * @param compressed 压缩后的字符串（经过 16 进制编码）
     * @return 解压缩后的原始字符串
     */
    public static function decompress(compressed:String):String {
        if (compressed == null || compressed.length == 0) {
            return "";
        }

        // 1. 使用 Hex16Encoder 进行 16 进制解码
        var hexDecoded:String = Hex16Encoder.decode(compressed);
        trace("编码解码后的结果: " + hexDecoded);

        // 2. 先进行 LZW 解压
        var lzwDecompressed:String = LZW.decompress(hexDecoded);
        trace("LZW 解压后的结果: " + lzwDecompressed);
        
        // 3. 再进行 RLE 解压
        var rleDecompressed:String = RLE.decompress(lzwDecompressed);
        trace("RLE 解压后的结果: " + rleDecompressed);
        
        // 4. 返回解压结果
        return rleDecompressed;
    }

    
    /**
     * 创建缩进字符串。
     * @param depth 缩进深度。
     * @return 缩进字符串。
     */
    public static function createIndent(depth:Number):String {
        var indent:String = "";
        for (var i:Number = 0; i < depth; i++) {
            indent += "    "; // 每个缩进级别使用四个空格
        }
        return indent;
    }
    
    /**
     * 转义字符串中的特殊字符。
     * @param str 要转义的字符串。
     * @return 转义后的字符串。
     */
    public static function escapeString(str:String):String {
        return StringUtils.replaceAll(
                    StringUtils.replaceAll(
                        StringUtils.replaceAll(
                            StringUtils.replaceAll(
                                StringUtils.replaceAll(str, "\\", "\\\\"),
                            "\"", "\\\""),
                        "\n", "\\n"),
                    "\r", "\\r"),
                "\t", "\\t");
    }


    /**
     * 使用正则表达式在字符串中查找匹配项。
     * 
     * @param input 要搜索的字符串。
     * @param pattern 正则表达式模式。
     * @param flags 正则表达式标志，如 "g", "i", "m"。
     * @return 一个包含所有匹配结果的数组。如果没有匹配，则返回 null。
     */
    public static function match(input:String, pattern:String, flags:String):Array {
        var regex:org.flashNight.gesh.regexp.RegExp;
        try {
            regex = new org.flashNight.gesh.regexp.RegExp(pattern, flags);
        } catch (e:Error) {
            trace("StringUtils.match: 无效的正则表达式 - " + e.message);
            return null;
        }
        
        var matches:Array = [];
        var matchResult:Array;
        
        // 如果设置了全局标志 'g'，则循环查找所有匹配
        if (flags.indexOf('g') >= 0) {
            while ((matchResult = regex.exec(input)) != null) {
                matches.push(matchResult[0]);
                // 防止零宽匹配导致无限循环
                if (matchResult[0].length == 0) {
                    regex.lastIndex++;
                }
            }
        } else {
            // 查找第一个匹配
            matchResult = regex.exec(input);
            if (matchResult != null) {
                matches.push(matchResult[0]);
            }
        }
        
        return matches.length > 0 ? matches : null;
    }
    
    /**
     * 在字符串中搜索正则表达式的第一个匹配项，并返回其索引位置。
     * 
     * @param input 要搜索的字符串。
     * @param pattern 正则表达式模式。
     * @param flags 正则表达式标志，如 "i", "m"。
     * @return 第一个匹配项的起始索引。如果没有匹配，则返回 -1。
     */
    public static function search(input:String, pattern:String, flags:String):Number {
        var regex:org.flashNight.gesh.regexp.RegExp;
        try {
            regex = new org.flashNight.gesh.regexp.RegExp(pattern, flags);
        } catch (e:Error) {
            trace("StringUtils.search: 无效的正则表达式 - " + e.message);
            return -1;
        }
        
        var matchResult:Array = regex.exec(input);
        if (matchResult != null && typeof(matchResult.index) == "number") {
            return matchResult.index;
        }
        return -1;
    }
    
    /**
     * 使用正则表达式替换字符串中的匹配部分。
     * 
     * @param input 要处理的字符串。
     * @param pattern 正则表达式模式。
     * @param flags 正则表达式标志，如 "g", "i", "m"。
     * @param replacement 替换字符串。
     * @return 替换后的新字符串。
     */
    public static function replace(input:String, pattern:String, flags:String, replacement:String):String {
        var regex:org.flashNight.gesh.regexp.RegExp;
        try {
            regex = new org.flashNight.gesh.regexp.RegExp(pattern, flags);
        } catch (e:Error) {
            trace("StringUtils.replace: 无效的正则表达式 - " + e.message);
            return input;
        }
        
        var result:String = "";
        var lastIndex:Number = 0;
        var matchResult:Array;
        
        while ((matchResult = regex.exec(input)) != null) {
            var matchIndex:Number = matchResult.index;
            var matchStr:String = matchResult[0];
            result += input.substring(lastIndex, matchIndex) + replacement;
            lastIndex = matchIndex + matchStr.length;
            
            // 如果没有设置全局标志 'g'，则只替换第一个匹配
            if (flags.indexOf('g') < 0) {
                break;
            }
            
            // 防止零宽匹配导致无限循环
            if (matchStr.length == 0) {
                lastIndex++;
            }
        }
        
        result += input.substring(lastIndex);
        return result;
    }
    
    /**
     * 使用正则表达式将字符串拆分为数组。
     * 
     * @param input 要拆分的字符串。
     * @param pattern 正则表达式模式。
     * @param flags 正则表达式标志，如 "g", "i", "m"。
     * @return 拆分后的字符串数组。
     */
    public static function split(input:String, pattern:String, flags:String):Array {
        var regex:org.flashNight.gesh.regexp.RegExp;
        try {
            regex = new org.flashNight.gesh.regexp.RegExp(pattern, flags);
        } catch (e:Error) {
            trace("StringUtils.split: 无效的正则表达式 - " + e.message);
            return [input];
        }
        
        var result:Array = [];
        var lastIndex:Number = 0;
        var matchResult:Array;
        
        while ((matchResult = regex.exec(input)) != null) {
            var matchIndex:Number = matchResult.index;
            result.push(input.substring(lastIndex, matchIndex));
            lastIndex = matchIndex + matchResult[0].length;
            
            // 防止零宽匹配导致无限循环
            if (matchResult[0].length == 0) {
                lastIndex++;
            }
        }
        
        result.push(input.substring(lastIndex));
        return result;
    }

    public static function unescape(str:String):String {
        var result:String = "";
        var i:Number = 0;

        while (i < str.length) {
            var char:String = str.charAt(i);
            if (char == "\\") {
                i++;
                if (i >= str.length) {
                    // 不完整的转义序列，保留反斜杠
                    result += "\\";
                    break;
                }
                char = str.charAt(i);
                switch (char) {
                    case "n":
                        result += "\n";
                        break;
                    case "t":
                        result += "\t";
                        break;
                    case "\\":
                        result += "\\";
                        break;
                    case "\"":
                        result += "\"";
                        break;
                    case "u":
                        // 处理 Unicode 转义序列 \uXXXX
                        if (i + 4 < str.length) {
                            var unicodeSeq:String = str.substr(i + 1, 4);
                            var isValidUnicode:Boolean = true;
                            for (var j:Number = 0; j < 4; j++) {
                                var hexChar:String = unicodeSeq.charAt(j).toUpperCase();
                                if (!((hexChar >= "0" && hexChar <= "9") || (hexChar >= "A" && hexChar <= "F"))) {
                                    isValidUnicode = false;
                                    break;
                                }
                            }
                            if (isValidUnicode) {
                                var unicodeCode:Number = parseInt(unicodeSeq, 16);
                                result += String.fromCharCode(unicodeCode);
                                i += 4; // 跳过 4 位十六进制字符
                            } else {
                                // 无效的 Unicode 序列，保留 \u
                                result += "\\u";
                            }
                        } else {
                            // 不完整的 Unicode 序列，保留 \u
                            result += "\\u";
                        }
                        break;
                    default:
                        // 保留未知的转义序列
                        result += "\\" + char;
                        break;
                }
            } else {
                result += char;
            }
            i++;
        }
        return result;
    }



    // 检查字符串是否包含子字符串
    public static function includes(str:String, substring:String):Boolean {
        return str.indexOf(substring) != -1;
    }
    
    // 检查字符串是否以指定子字符串开头
    public static function startsWith(str:String, prefix:String):Boolean {
        return str.indexOf(prefix) == 0;
    }
    
    // 检查字符串是否以指定子字符串结尾
    public static function endsWith(str:String, suffix:String):Boolean {
        var index:Number = str.lastIndexOf(suffix);
        return index != -1 && index == str.length - suffix.length;
    }
    
    // 移除字符串两端的空白字符
    public static function trim(str:String):String {
        return StringUtils.trimLeft(StringUtils.trimRight(str));
    }
    
    // 移除字符串左边的空白字符
    public static function trimLeft(str:String):String {
        while (str.length > 0 && (str.charAt(0) == " " || str.charAt(0) == "\t" || str.charAt(0) == "\n" || str.charAt(0) == "\r")) {
            str = str.substring(1);
        }
        return str;
    }
    
    // 移除字符串右边的空白字符
    public static function trimRight(str:String):String {
        while (str.length > 0 && (str.charAt(str.length - 1) == " " || str.charAt(str.length - 1) == "\t" || str.charAt(str.length - 1) == "\n" || str.charAt(str.length - 1) == "\r")) {
            str = str.substring(0, str.length - 1);
        }
        return str;
    }
    
    // 将字符串重复指定次数
    public static function repeat(str:String, count:Number):String {
        var result:String = "";
        for (var i:Number = 0; i < count; i++) {
            result += str;
        }
        return result;
    }
    
    // 在字符串开头填充字符，直到字符串达到指定长度
    public static function padStart(str:String, targetLength:Number, padString:String):String {
        if (padString.length == 0) return str; // 避免无限循环
        var padCount:Number = Math.ceil((targetLength - str.length) / padString.length);
        var padding:String = StringUtils.repeat(padString, padCount).substring(0, targetLength - str.length);
        return padding + str;
    }
    
    // 在字符串末尾填充字符，直到字符串达到指定长度
    public static function padEnd(str:String, targetLength:Number, padString:String):String {
        if (padString.length == 0) return str; // 避免无限循环
        var padCount:Number = Math.ceil((targetLength - str.length) / padString.length);
        var padding:String = StringUtils.repeat(padString, padCount).substring(0, targetLength - str.length);
        return str + padding;
    }
    
    // 替换字符串中的所有匹配项（不使用正则表达式）
    public static function replaceAll(str:String, search:String, replacement:String):String {
        var result:String = "";
        var index:Number = 0;
        var searchLength:Number = search.length;
        if (searchLength == 0) {
            // 如果 search 是空字符串，返回原字符串以避免无限循环
            return str;
        }
        while ((index = str.indexOf(search)) != -1) {
            result += str.substring(0, index) + replacement;
            str = str.substring(index + searchLength);
        }
        result += str;  // 加入剩下的部分
        return result;
    }
    
    // 反转字符串
    public static function reverse(str:String):String {
        var result:String = "";
        for (var i:Number = str.length - 1; i >= 0; i--) {
            result += str.charAt(i);
        }
        return result;
    }
    
    // 检查字符串是否为空或仅包含空白字符
    public static function isEmpty(str:String):Boolean {
        return StringUtils.trim(str).length == 0;
    }
    
    // 计算子字符串在字符串中出现的次数
    public static function countOccurrences(str:String, substring:String):Number {
        if (substring.length == 0) return 0;
        var count:Number = 0;
        var index:Number = str.indexOf(substring);
        while (index != -1) {
            count++;
            index = str.indexOf(substring, index + substring.length);
        }
        return count;
    }
    
    // 将字符串的首字母大写，并将其余部分小写
    public static function capitalize(str:String):String {
        if (str.length == 0) return str;
        return str.charAt(0).toUpperCase() + str.substring(1).toLowerCase();
    }
    
    // 将字符串转换为标题格式（每个单词首字母大写，其他字母小写）
    public static function toTitleCase(str:String):String {
        var words:Array = str.split(" ");
        for (var i:Number = 0; i < words.length; i++) {
            if (words[i].length > 0) {
                words[i] = StringUtils.capitalize(words[i]);
            }
        }
        return words.join(" ");
    }
    
    // 移除字符串中所有指定的子字符串
    public static function remove(str:String, substring:String):String {
        return StringUtils.replaceAll(str, substring, "");
    }
    
    // 获取位于两个指定子字符串之间的子字符串
    public static function substringBetween(str:String, start:String, end:String):String {
        var startIndex:Number = str.indexOf(start);
        if (startIndex == -1) return null;
        startIndex += start.length;
        var endIndex:Number = str.indexOf(end, startIndex);
        if (endIndex == -1) return null;
        return str.substring(startIndex, endIndex);
    }
    
    // 检查字符串是否包含子字符串（忽略大小写）
    public static function containsIgnoreCase(str:String, substring:String):Boolean {
        return StringUtils.includes(str.toLowerCase(), substring.toLowerCase());
    }
    
    // 检查字符串是否以指定子字符串开头（忽略大小写）
    public static function startsWithIgnoreCase(str:String, prefix:String):Boolean {
        return str.toLowerCase().indexOf(prefix.toLowerCase()) == 0;
    }
    
    // 检查字符串是否以指定子字符串结尾（忽略大小写）
    public static function endsWithIgnoreCase(str:String, suffix:String):Boolean {
        var lowerStr:String = str.toLowerCase();
        var lowerSuffix:String = suffix.toLowerCase();
        var index:Number = lowerStr.lastIndexOf(lowerSuffix);
        return index != -1 && index == str.length - suffix.length;
    }
    
    /**
     * 转义 HTML 特殊字符
     * @param str 要转义的字符串
     * @return 转义后的字符串
     */
    public static function escapeHTML(str:String):String {
        var escaped:String = str;
        
        // 按顺序替换，确保 & 首先被替换，以防止后续替换中的 &
        escaped = StringUtils.replaceAll(escaped, "&", "&amp;");
        escaped = StringUtils.replaceAll(escaped, "<", "&lt;");
        escaped = StringUtils.replaceAll(escaped, ">", "&gt;");
        escaped = StringUtils.replaceAll(escaped, "\"", "&quot;");
        escaped = StringUtils.replaceAll(escaped, "'", "&apos;");
        
        // 获取单例实例
        var singleton:StringUtils = StringUtils.getInstance();
        
        // 进一步替换其他特殊字符
        for (var char:String in singleton.htmlEntitiesReverse) {
            // 跳过已经替换的字符
            if (char == "&" || char == "<" || char == ">" || char == "\"" || char == "'") continue;
            escaped = StringUtils.replaceAll(escaped, char, singleton.htmlEntitiesReverse[char]);
        }
        
        return escaped;
    }
    
    /**
     * 反转义 HTML 特殊字符
     * @param str 要反转义的字符串
     * @return 反转义后的字符串
     */
    public static function unescapeHTML(str:String):String {
        var unescaped:String = str;
        
        // 获取单例实例
        var singleton:StringUtils = StringUtils.getInstance();
        
        for (var entity:String in singleton.htmlEntities) {
            var correspondingChar:String = singleton.htmlEntities[entity];
            unescaped = StringUtils.replaceAll(unescaped, entity, correspondingChar);
        }
        
        return unescaped;
    }
    
    /**
     * 转义 HTML 实体（别名）
     * @param str 要转义的字符串
     * @return 转义后的字符串
     */
    public static function encodeHTML(str:String):String {
        return StringUtils.escapeHTML(str);
    }
    
    /**
     * 反转义 HTML 实体（别名）
     * @param str 要反转义的字符串
     * @return 反转义后的字符串
     */
    public static function decodeHTML(str:String):String {
        return StringUtils.unescapeHTML(str);
    }

    /**
     * 将简单 HTML 文本（日志）转成纯文本（无正则，单次线性扫描）
     */
    public static function htmlToPlainTextFast(input:String):String {
        if (input == null || input == undefined) return "";

        var s:String = String(input);
        var len:Number = s.length;
        var i:Number = 0;
        var out:Array = [];              // 片段累积，减少字符串拼接
        var ch:Number;

        // 一次扫描：处理标签与实体
        while (i < len) {
            ch = s.charCodeAt(i);

            // '<' 开始：解析标签
            if (ch == 60) { // '<'
                var j:Number = i + 1;
                // 跳过空白
                while (j < len) {
                    var c:Number = s.charCodeAt(j);
                    if (c == 32 || c == 9 || c == 10 || c == 13) j++; else break;
                }
                // 可选的关闭标志 '/'
                if (j < len && s.charAt(j) == "/") j++;

                // 再次跳过空白
                while (j < len) {
                    c = s.charCodeAt(j);
                    if (c == 32 || c == 9) j++; else break;
                }

                // 提取标签名（字母数字）
                var start:Number = j;
                while (j < len) {
                    c = s.charCodeAt(j);
                    if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57)) j++;
                    else break;
                }
                var tag:String = s.substring(start, j).toLowerCase();

                // 快速跳到 '>'
                while (j < len && s.charAt(j) != ">") j++;
                if (j < len) j++; // 跳过 '>'

                // 需要换行的标签
                if (tag == "br" || tag == "p" || tag == "div" || tag == "li" || tag == "ul" || tag == "ol" ||
                    tag == "h1" || tag == "h2" || tag == "h3" || tag == "h4" || tag == "h5" || tag == "h6" ||
                    tag == "tr" || tag == "table" || tag == "thead" || tag == "tbody" || tag == "tfoot") {
                    out.push("\n");
                }

                i = j; // 继续后扫
                continue;
            }

            // '&' 开始：解析实体
            if (ch == 38) { // '&'
                var k:Number = i + 1;
                var semi:Number = k;
                while (semi < len && s.charAt(semi) != ";") semi++;

                if (semi < len) {
                    var entity:String = s.substring(k, semi);
                    var decoded:String = null;

                    if (entity.length > 0 && entity.charAt(0) == "#") {
                        // 数字实体
                        if (entity.length > 1 && (entity.charAt(1) == "x" || entity.charAt(1) == "X")) {
                            // 十六进制
                            var v:Number = 0;
                            var idx:Number = 2;
                            while (idx < entity.length) {
                                var cc:Number = entity.charCodeAt(idx);
                                if (cc >= 48 && cc <= 57) v = v * 16 + (cc - 48);
                                else if (cc >= 65 && cc <= 70) v = v * 16 + (cc - 55);
                                else if (cc >= 97 && cc <= 102) v = v * 16 + (cc - 87);
                                else break;
                                idx++;
                            }
                            decoded = String.fromCharCode(v);
                        } else {
                            // 十进制
                            var v10:Number = 0;
                            var idx2:Number = 1;
                            while (idx2 < entity.length) {
                                var c2:Number = entity.charCodeAt(idx2);
                                if (c2 >= 48 && c2 <= 57) { v10 = v10 * 10 + (c2 - 48); idx2++; }
                                else break;
                            }
                            decoded = String.fromCharCode(v10);
                        }
                    } else {
                        // 常见命名实体
                        var e:String = entity.toLowerCase();
                        if (e == "amp") decoded = "&";
                        else if (e == "lt") decoded = "<";
                        else if (e == "gt") decoded = ">";
                        else if (e == "quot") decoded = "\"";
                        else if (e == "apos") decoded = "'";
                        else if (e == "nbsp") decoded = " ";
                    }

                    if (decoded != null) {
                        out.push(decoded);
                        i = semi + 1;
                        continue;
                    }
                }

                // 兜底：不是合法实体，就原样输出 '&'
                out.push("&");
                i++;
                continue;
            }

            // 归一化 CR→LF，其它字符原样输出
            if (ch == 13) { out.push("\n"); i++; continue; } // '\r'
            out.push(s.charAt(i));
            i++;
        }

        // 二次遍历：折叠空白、限制空行数量，并整体 trim（无正则）
        var raw:String = out.join("");
        var resParts:Array = [];
        var prevSpace:Boolean = false;
        var nlCount:Number = 0;

        var L:Number = raw.length;
        for (i = 0; i < L; i++) {
            var chs:String = raw.charAt(i);
            var code:Number = raw.charCodeAt(i);

            if (chs == "\n") {
                if (nlCount < 2) resParts.push("\n"); // 至多保留两个连续空行
                nlCount++;
                prevSpace = false;
            } else if (code == 32 || code == 9 || code == 160) { // ' ' / \t / &nbsp;
                if (!prevSpace) { resParts.push(" "); prevSpace = true; }
            } else {
                resParts.push(chs);
                prevSpace = false;
                nlCount = 0;
            }
        }

        // 行内去两端空格
        var joined:String = resParts.join("");
        var lines:Array = joined.split("\n");
        for (i = 0; i < lines.length; i++) {
            lines[i] = StringUtils.trim(lines[i]);
        }
        var finalStr:String = lines.join("\n");
        return StringUtils.trim(finalStr);
    }


    /**
     * 估算一段 HTML 文本的“长度系数”（不产出纯文本，单次扫描，无正则）
     * @param input   HTML 字符串
     * @param weights (可选) 权重表：
     *   { ascii:1, latin1:1, cjkWide:2, emoji:2, whitespace:0.5, newline:0.5 }
     * @return 加权长度（Number）
     */
    public static function htmlLengthScore(input:String, weights:Object):Number {
        if (input == null || input == undefined) return 0;

        // 默认权重
        var w:Object = {
            ascii: 1,
            latin1: 1,
            cjkWide: 2,
            emoji: 2,
            whitespace: 0.5,
            newline: 0
        };
        // 覆盖默认权重
        if (weights) {
            for (var k:String in weights) w[k] = weights[k];
        }

        var s:String = String(input);
        var len:Number = s.length;
        var i:Number = 0;
        var score:Number = 0;

        // 折叠空白/换行（显示近似）
        var prevSpace:Boolean = false;
        var nlCount:Number = 0;

        // 工具：是否宽字符（粗略 CJK/全角）
        function isCJKWide(code:Number):Boolean {
            // 常见 CJK/全角/假名/兼容表意/标点等块
            if ((code >= 0x2E80 && code <= 0xA4CF)  // 部首/注音/假名等
            || (code >= 0xAC00 && code <= 0xD7A3)  // Hangul Syllables
            || (code >= 0xF900 && code <= 0xFAFF)  // 兼容表意
            || (code >= 0xFE10 && code <= 0xFE6F)  // 竖排标点/小体
            || (code >= 0xFF00 && code <= 0xFF60)  // 全角字符
            || (code >= 0xFFE0 && code <= 0xFFE6)  // 全角符号
            || (code >= 0x3400 && code <= 0x9FFF)) // 统一表意
                return true;

            // 半角片假名（FF61–FF9F）不算宽
            return false;
        }

        // 工具：累加一个“字符”的权重（含空白/换行折叠）
        function addCharWeight(code:Number, isNewline:Boolean, isSpace:Boolean):Void {
            if (isNewline) {
                if (nlCount < 2) score += w.newline;
                nlCount++;
                prevSpace = false;
                return;
            }
            if (isSpace) {
                if (!prevSpace) score += w.whitespace;
                prevSpace = true;
                nlCount = 0;
                return;
            }
            nlCount = 0;
            prevSpace = false;

            if (code < 0) { // 例如大于 0xFFFF 的实体映射为“emoji”
                score += w.emoji;
                return;
            }
            if (code <= 0x7F) { score += w.ascii; return; }
            if (code <= 0xFF) { score += w.latin1; return; }
            if (code >= 0xD800 && code <= 0xDBFF) { // 代理对上半
                score += w.emoji; // 粗略按 emoji 宽度
                return;
            }
            // 宽字符 or 普通 BMP
            score += isCJKWide(code) ? w.cjkWide : w.latin1;
        }

        // 工具：解析实体，返回(code, advance)
        // code: >=0 => BMP 码位,  -1 => emoji/非BMP,  -2 => 未识别（按 '&' 原样）
        function decodeEntity(at:Number):Object {
            var k:Number = at + 1; // 跳过 '&'
            var semi:Number = k;
            while (semi < len && s.charAt(semi) != ";") semi++;
            if (semi >= len) return {code:-2, advance:1}; // 没有 ';'，当普通字符

            var entity:String = s.substring(k, semi);
            var eLower:String = entity.toLowerCase();

            // 数字实体
            if (eLower.length > 0 && eLower.charAt(0) == "#") {
                var val:Number = 0;
                if (eLower.length > 1 && (eLower.charAt(1) == "x")) {
                    // 十六进制
                    for (var t:Number = 2; t < eLower.length; t++) {
                        var cc:Number = eLower.charCodeAt(t);
                        if      (cc >= 48 && cc <= 57)  val = val * 16 + (cc - 48);
                        else if (cc >= 97 && cc <= 102) val = val * 16 + (cc - 87);
                        else break;
                    }
                } else {
                    // 十进制
                    for (t = 1; t < eLower.length; t++) {
                        cc = eLower.charCodeAt(t);
                        if (cc >= 48 && cc <= 57) val = val * 10 + (cc - 48);
                        else break;
                    }
                }
                // 非 BMP 直接按 emoji 计分：返回 code=-1
                if (val > 0xFFFF) return {code:-1, advance:(semi - at + 1)};
                return {code:val, advance:(semi - at + 1)};
            }

            // 命名实体
            if (eLower == "amp")   return {code:38,  advance:(semi - at + 1)};   // &
            if (eLower == "lt")    return {code:60,  advance:(semi - at + 1)};   // <
            if (eLower == "gt")    return {code:62,  advance:(semi - at + 1)};   // >
            if (eLower == "quot")  return {code:34,  advance:(semi - at + 1)};   // "
            if (eLower == "apos")  return {code:39,  advance:(semi - at + 1)};   // '
            if (eLower == "nbsp")  return {code:32,  advance:(semi - at + 1)};   // space

            return {code:-2, advance:1}; // 未识别：按 '&'
        }

        // 工具：读取标签名（小写），返回 {name, jumpTo}
        function readTagName(at:Number):Object {
            var j:Number = at + 1; // 跳过 '<'
            // 跳空白
            while (j < len) {
                var c:Number = s.charCodeAt(j);
                if (c == 32 || c == 9 || c == 10 || c == 13) j++; else break;
            }
            // 可选 '/'
            if (j < len && s.charAt(j) == "/") j++;
            // 再跳空白
            while (j < len) {
                c = s.charCodeAt(j);
                if (c == 32 || c == 9) j++; else break;
            }
            // 采集[a-z0-9]
            var start:Number = j;
            while (j < len) {
                c = s.charCodeAt(j);
                if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57)) j++;
                else break;
            }
            var name:String = s.substring(start, j).toLowerCase();
            // 快速跳到 '>'
            while (j < len && s.charAt(j) != ">") j++;
            if (j < len) j++; // 跳过 '>'
            return {name:name, jumpTo:j};
        }

        // 主循环
        while (i < len) {
            var code:Number = s.charCodeAt(i);

            // 标签
            if (code == 60) { // '<'
                var tag:Object = readTagName(i);
                var tn:String = tag.name;
                if (tn == "br" || tn == "p" || tn == "div" || tn == "li" || tn == "ul" || tn == "ol" ||
                    tn == "h1" || tn == "h2" || tn == "h3" || tn == "h4" || tn == "h5" || tn == "h6" ||
                    tn == "tr" || tn == "table" || tn == "thead" || tn == "tbody" || tn == "tfoot") {
                    addCharWeight(10, true, false); // newline
                }
                i = tag.jumpTo;
                continue;
            }

            // 实体
            if (code == 38) { // '&'
                var ent:Object = decodeEntity(i);
                if (ent.code == -2) {
                    // 未识别实体，按普通 '&'
                    addCharWeight(38, false, false);
                    i++;
                } else {
                    if (ent.code == 32) addCharWeight(32, false, true); // nbsp -> space
                    else if (ent.code == 10 || ent.code == 13) addCharWeight(10, true, false);
                    else if (ent.code == -1) addCharWeight(-1, false, false); // emoji-like
                    else addCharWeight(Number(ent.code), false, false);
                    i += ent.advance;
                }
                continue;
            }

            // 换行/空白原生字符
            if (code == 10 || code == 13) { addCharWeight(10, true, false); i++; continue; } // \n/\r
            if (code == 9 || code == 32 || code == 160) { addCharWeight(32, false, true); i++; continue; } // \t/space/&nbsp;

            // 代理对（emoji等）
            if (code >= 0xD800 && code <= 0xDBFF && i + 1 < len) {
                var low:Number = s.charCodeAt(i + 1);
                if (low >= 0xDC00 && low <= 0xDFFF) {
                    addCharWeight(-1, false, false); // 视作 emoji
                    i += 2;
                    continue;
                }
            }

            // 普通字符
            addCharWeight(code, false, false);
            i++;
        }

        return score;
    }


}



/*

import org.flashNight.gesh.string.StringUtils;

// 定义一个测试函数，用于统一处理测试输出
function runTest(testName:String, expected, actual):Void {
    if (expected === actual) {
        trace(testName + ": PASS");
    } else {
        trace(testName + ": FAIL");
        trace("  Expected: " + expected);
        trace("  Actual  : " + actual);
    }
}

// 定义一个测试函数，用于处理数组结果
function runArrayTest(testName:String, expected:Array, actual:Array):Void {
    var pass:Boolean = true;
    if (expected == null && actual == null) {
        pass = true;
    } else if (expected == null || actual == null) {
        pass = false;
    } else if (expected.length != actual.length) {
        pass = false;
    } else {
        for (var i:Number = 0; i < expected.length; i++) {
            if (typeof(expected[i]) == "object" && expected[i] instanceof Array) {
                if (!arraysEqual(expected[i], actual[i])) {
                    pass = false;
                    break;
                }
            } else {
                if (expected[i] !== actual[i]) {
                    pass = false;
                    break;
                }
            }
        }
    }
    
    if (pass) {
        trace(testName + ": PASS");
    } else {
        trace(testName + ": FAIL");
        trace("  Expected: " + arrayToString(expected));
        trace("  Actual  : " + arrayToString(actual));
    }
}

// 定义一个辅助函数，将数组转换为字符串表示
function arrayToString(arr:Array):String {
    if (arr == null) return "null";
    var str:String = "[";
    for (var i:Number = 0; i < arr.length; i++) {
        if (i > 0) str += ", ";
        if (typeof(arr[i]) == "object" && arr[i] instanceof Array) {
            str += arrayToString(arr[i]);
        } else {
            str += "\"" + arr[i] + "\"";
        }
    }
    str += "]";
    return str;
}

// 定义一个辅助函数，比较两个数组是否相等
function arraysEqual(arr1:Array, arr2:Array):Boolean {
    if (arr1 == null && arr2 == null) return true;
    if (arr1 == null || arr2 == null) return false;
    if (arr1.length != arr2.length) return false;
    for (var i:Number = 0; i < arr1.length; i++) {
        if (typeof(arr1[i]) == "object" && arr1[i] instanceof Array) {
            if (!arraysEqual(arr1[i], arr2[i])) {
                return false;
            }
        } else {
            if (arr1[i] !== arr2[i]) {
                return false;
            }
        }
    }
    return true;
}

// 开始测试
trace("===== StringUtils 类单元测试 =====");

// 1. includes
trace("----- 测试 includes 方法 -----");
runTest("includes('Hello World', 'World')", true, StringUtils.includes("Hello World", "World"));
runTest("includes('Hello World', 'world')", false, StringUtils.includes("Hello World", "world"));
runTest("includes('Hello World', '')", true, StringUtils.includes("Hello World", ""));
runTest("includes('', 'a')", false, StringUtils.includes("", "a"));

// 2. startsWith
trace("----- 测试 startsWith 方法 -----");
runTest("startsWith('Hello World', 'Hello')", true, StringUtils.startsWith("Hello World", "Hello"));
runTest("startsWith('Hello World', 'World')", false, StringUtils.startsWith("Hello World", "World"));
runTest("startsWith('Hello World', '')", true, StringUtils.startsWith("Hello World", ""));
runTest("startsWith('', 'a')", false, StringUtils.startsWith("", "a"));

// 3. endsWith
trace("----- 测试 endsWith 方法 -----");
runTest("endsWith('Hello World', 'World')", true, StringUtils.endsWith("Hello World", "World"));
runTest("endsWith('Hello World', 'Hello')", false, StringUtils.endsWith("Hello World", "Hello"));
runTest("endsWith('Hello World', '')", true, StringUtils.endsWith("Hello World", ""));
runTest("endsWith('', 'a')", false, StringUtils.endsWith("", "a"));

// 4. trim
trace("----- 测试 trim 方法 -----");
runTest("trim('  Hello World  ')", "Hello World", StringUtils.trim("  Hello World  "));
runTest("trim('\\t\\nHello\\r\\n')", "Hello", StringUtils.trim("\t\nHello\r\n"));
runTest("trim('Hello')", "Hello", StringUtils.trim("Hello"));
runTest("trim('    ')", "", StringUtils.trim("    "));
runTest("trim('')", "", StringUtils.trim(""));

// 5. trimLeft
trace("----- 测试 trimLeft 方法 -----");
runTest("trimLeft('  Hello World  ')", "Hello World  ", StringUtils.trimLeft("  Hello World  "));
runTest("trimLeft('\\t\\nHello')", "Hello", StringUtils.trimLeft("\t\nHello"));
runTest("trimLeft('Hello')", "Hello", StringUtils.trimLeft("Hello"));
runTest("trimLeft('    ')", "", StringUtils.trimLeft("    "));
runTest("trimLeft('')", "", StringUtils.trimLeft(""));

// 6. trimRight
trace("----- 测试 trimRight 方法 -----");
runTest("trimRight('  Hello World  ')", "  Hello World", StringUtils.trimRight("  Hello World  "));
runTest("trimRight('Hello\\r\\n')", "Hello", StringUtils.trimRight("Hello\r\n"));
runTest("trimRight('Hello')", "Hello", StringUtils.trimRight("Hello"));
runTest("trimRight('    ')", "", StringUtils.trimRight("    "));
runTest("trimRight('')", "", StringUtils.trimRight(""));

// 7. repeat
trace("----- 测试 repeat 方法 -----");
runTest("repeat('a', 3)", "aaa", StringUtils.repeat("a", 3));
runTest("repeat('ab', 2)", "abab", StringUtils.repeat("ab", 2));
runTest("repeat('', 5)", "", StringUtils.repeat("", 5));
runTest("repeat('a', 0)", "", StringUtils.repeat("a", 0));
runTest("repeat('a', -1)", "", StringUtils.repeat("a", -1));

// 8. padStart
trace("----- 测试 padStart 方法 -----");
runTest("padStart('5', 3, '0')", "005", StringUtils.padStart("5", 3, "0"));
runTest("padStart('abc', 5, 'xy')", "xyabc", StringUtils.padStart("abc", 5, "xy"));
runTest("padStart('abc', 2, 'x')", "abc", StringUtils.padStart("abc", 2, "x")); // 不足以填充
runTest("padStart('', 3, 'a')", "aaa", StringUtils.padStart("", 3, "a"));
runTest("padStart('a', 4, 'ab')", "abaa", StringUtils.padStart("a", 4, "ab")); // 修正预期值为 "abaa"

// 9. padEnd
trace("----- 测试 padEnd 方法 -----");
runTest("padEnd('5', 3, '0')", "500", StringUtils.padEnd("5", 3, "0"));
runTest("padEnd('abc', 5, 'xy')", "abcxy", StringUtils.padEnd("abc", 5, "xy"));
runTest("padEnd('abc', 2, 'x')", "abc", StringUtils.padEnd("abc", 2, "x")); // 不足以填充
runTest("padEnd('', 3, 'a')", "aaa", StringUtils.padEnd("", 3, "a"));
runTest("padEnd('a', 4, 'ab')", "aaba", StringUtils.padEnd("a", 4, "ab")); // 拼接后截断

// 10. replaceAll
trace("----- 测试 replaceAll 方法 -----");
runTest("replaceAll('banana', 'a', 'o')", "bonono", StringUtils.replaceAll("banana", "a", "o"));
runTest("replaceAll('aaaa', 'a', 'b')", "bbbb", StringUtils.replaceAll("aaaa", "a", "b"));
runTest("replaceAll('hello', 'l', 'r')", "herro", StringUtils.replaceAll("hello", "l", "r"));
runTest("replaceAll('hello', 'x', 'y')", "hello", StringUtils.replaceAll("hello", "x", "y"));
runTest("replaceAll('', 'a', 'b')", "", StringUtils.replaceAll("", "a", "b"));

// 11. reverse
trace("----- 测试 reverse 方法 -----");
runTest("reverse('hello')", "olleh", StringUtils.reverse("hello"));
runTest("reverse('a')", "a", StringUtils.reverse("a"));
runTest("reverse('')", "", StringUtils.reverse(""));
runTest("reverse('ab')", "ba", StringUtils.reverse("ab"));
runTest("reverse('racecar')", "racecar", StringUtils.reverse("racecar"));

// 12. isEmpty
trace("----- 测试 isEmpty 方法 -----");
runTest("isEmpty('')", true, StringUtils.isEmpty(""));
runTest("isEmpty('   ')", true, StringUtils.isEmpty("   "));
runTest("isEmpty('\\t\\n')", true, StringUtils.isEmpty("\t\n"));
runTest("isEmpty('hello')", false, StringUtils.isEmpty("hello"));
runTest("isEmpty(' hello ')", false, StringUtils.isEmpty(" hello "));

// 13. countOccurrences
trace("----- 测试 countOccurrences 方法 -----");
runTest("countOccurrences('banana', 'a')", 3, StringUtils.countOccurrences("banana", "a"));
runTest("countOccurrences('aaaaa', 'aa')", 2, StringUtils.countOccurrences("aaaaa", "aa")); // overlapping not counted
runTest("countOccurrences('hello world', 'l')", 3, StringUtils.countOccurrences("hello world", "l"));
runTest("countOccurrences('hello world', 'x')", 0, StringUtils.countOccurrences("hello world", "x"));
runTest("countOccurrences('', 'a')", 0, StringUtils.countOccurrences("", "a"));
runTest("countOccurrences('abcabcabc', 'abc')", 3, StringUtils.countOccurrences("abcabcabc", "abc"));
runTest("countOccurrences('ababab', 'ab')", 3, StringUtils.countOccurrences("ababab", "ab"));

// 14. capitalize
trace("----- 测试 capitalize 方法 -----");
runTest("capitalize('hello')", "Hello", StringUtils.capitalize("hello"));
runTest("capitalize('Hello')", "Hello", StringUtils.capitalize("Hello"));
runTest("capitalize('')", "", StringUtils.capitalize(""));
runTest("capitalize('h')", "H", StringUtils.capitalize("h"));
runTest("capitalize('1abc')", "1abc", StringUtils.capitalize("1abc"));

// 15. toTitleCase
trace("----- 测试 toTitleCase 方法 -----");
runTest("toTitleCase('hello world')", "Hello World", StringUtils.toTitleCase("hello world"));
runTest("toTitleCase('javaScript is fun')", "Javascript Is Fun", StringUtils.toTitleCase("javaScript is fun")); // 'Javascript' vs 'JavaScript'
runTest("toTitleCase('')", "", StringUtils.toTitleCase(""));
runTest("toTitleCase('single')", "Single", StringUtils.toTitleCase("single"));
runTest("toTitleCase('multiple   spaces')", "Multiple   Spaces", StringUtils.toTitleCase("multiple   spaces"));

// 16. remove
trace("----- 测试 remove 方法 -----");
runTest("remove('banana', 'a')", "bnn", StringUtils.remove("banana", "a"));
runTest("remove('hello world', 'l')", "heo word", StringUtils.remove("hello world", "l"));
runTest("remove('hello world', 'x')", "hello world", StringUtils.remove("hello world", "x"));
runTest("remove('aaaaa', 'aa')", "a", StringUtils.remove("aaaaa", "aa")); // removes non-overlapping
runTest("remove('', 'a')", "", StringUtils.remove("", "a"));

// 17. substringBetween
trace("----- 测试 substringBetween 方法 -----");
runTest("substringBetween('Hello [World]!', '[', ']')", "World", StringUtils.substringBetween("Hello [World]!", "[", "]"));
runTest("substringBetween('No brackets here', '[', ']')", null, StringUtils.substringBetween("No brackets here", "[", "]"));
runTest("substringBetween('Start <middle> End', '<', '>')", "middle", StringUtils.substringBetween("Start <middle> End", "<", ">"));
runTest("substringBetween('Edge case <', '<', '>')", null, StringUtils.substringBetween("Edge case <", "<", ">"));
runTest("substringBetween('<>', '<', '>')", "", StringUtils.substringBetween("<>", "<", ">"));

// 18. containsIgnoreCase
trace("----- 测试 containsIgnoreCase 方法 -----");
runTest("containsIgnoreCase('Hello World', 'world')", true, StringUtils.containsIgnoreCase("Hello World", "world"));
runTest("containsIgnoreCase('Hello World', 'WORLD')", true, StringUtils.containsIgnoreCase("Hello World", "WORLD"));
runTest("containsIgnoreCase('Hello World', 'Earth')", false, StringUtils.containsIgnoreCase("Hello World", "Earth"));
runTest("containsIgnoreCase('Hello World', '')", true, StringUtils.containsIgnoreCase("Hello World", ""));
runTest("containsIgnoreCase('', 'a')", false, StringUtils.containsIgnoreCase("", "a"));

// 19. startsWithIgnoreCase
trace("----- 测试 startsWithIgnoreCase 方法 -----");
runTest("startsWithIgnoreCase('Hello World', 'hello')", true, StringUtils.startsWithIgnoreCase("Hello World", "hello"));
runTest("startsWithIgnoreCase('Hello World', 'HELLO')", true, StringUtils.startsWithIgnoreCase("Hello World", "HELLO"));
runTest("startsWithIgnoreCase('Hello World', 'World')", false, StringUtils.startsWithIgnoreCase("Hello World", "World"));
runTest("startsWithIgnoreCase('Hello World', '')", true, StringUtils.startsWithIgnoreCase("Hello World", ""));
runTest("startsWithIgnoreCase('', 'a')", false, StringUtils.startsWithIgnoreCase("", "a"));

// 20. endsWithIgnoreCase
trace("----- 测试 endsWithIgnoreCase 方法 -----");
runTest("endsWithIgnoreCase('Hello World', 'world')", true, StringUtils.endsWithIgnoreCase("Hello World", "world"));
runTest("endsWithIgnoreCase('Hello World', 'WORLD')", true, StringUtils.endsWithIgnoreCase("Hello World", "WORLD"));
runTest("endsWithIgnoreCase('Hello World', 'Hello')", false, StringUtils.endsWithIgnoreCase("Hello World", "Hello"));
runTest("endsWithIgnoreCase('Hello World', '')", true, StringUtils.endsWithIgnoreCase("Hello World", ""));
runTest("endsWithIgnoreCase('', 'a')", false, StringUtils.endsWithIgnoreCase("", "a"));

// 21. escapeHTML
trace("----- 测试 escapeHTML 方法 -----");
runTest("escapeHTML('<div>Tom & Jerry</div>')", "&lt;div&gt;Tom &amp; Jerry&lt;/div&gt;", StringUtils.escapeHTML("<div>Tom & Jerry</div>"));
runTest("escapeHTML('5 > 3 and 2 < 4')", "5 &gt; 3 and 2 &lt; 4", StringUtils.escapeHTML("5 > 3 and 2 < 4"));
runTest("escapeHTML('He said, \"Hello\"')", "He said, &quot;Hello&quot;", StringUtils.escapeHTML('He said, "Hello"'));
runTest("escapeHTML(\"It's a test\")", "It&apos;s a test", StringUtils.escapeHTML("It's a test"));
runTest("escapeHTML('')", "", StringUtils.escapeHTML(""));

// 22. unescapeHTML
trace("----- 测试 unescapeHTML 方法 -----");
runTest("unescapeHTML('&lt;div&gt;Tom &amp; Jerry&lt;/div&gt;')", "<div>Tom & Jerry</div>", StringUtils.unescapeHTML("&lt;div&gt;Tom &amp; Jerry&lt;/div&gt;"));
runTest("unescapeHTML('5 &gt; 3 and 2 &lt; 4')", "5 > 3 and 2 < 4", StringUtils.unescapeHTML("5 &gt; 3 and 2 &lt; 4"));
runTest("unescapeHTML('He said, &quot;Hello&quot;')", 'He said, "Hello"', StringUtils.unescapeHTML("He said, &quot;Hello&quot;"));
runTest("unescapeHTML('It&apos;s a test')", "It's a test", StringUtils.unescapeHTML("It&apos;s a test"));
runTest("unescapeHTML('')", "", StringUtils.unescapeHTML(""));

// 23. encodeHTML (别名)
trace("----- 测试 encodeHTML 方法 -----");
runTest("encodeHTML('<span>Test & Check</span>')", "&lt;span&gt;Test &amp; Check&lt;/span&gt;", StringUtils.encodeHTML("<span>Test & Check</span>"));
runTest("encodeHTML('Use \"quotes\" and \'apostrophes\'')", "Use &quot;quotes&quot; and &apos;apostrophes&apos;", StringUtils.encodeHTML('Use "quotes" and \'apostrophes\''));

// 24. decodeHTML (别名)
trace("----- 测试 decodeHTML 方法 -----");
runTest("decodeHTML('&lt;span&gt;Test &amp; Check&lt;/span&gt;')", "<span>Test & Check</span>", StringUtils.decodeHTML("&lt;span&gt;Test &amp; Check&lt;/span&gt;"));
runTest("decodeHTML('Use &quot;quotes&quot; and &apos;apostrophes&apos;')", 'Use "quotes" and \'apostrophes\'', StringUtils.decodeHTML("Use &quot;quotes&quot; and &apos;apostrophes&apos;"));

// 25. 测试单例模式
trace("----- 测试单例模式 -----");
// 由于 getInstance 方法是私有的，无法直接测试单例行为。
// 但是可以通过确保 escapeHTML 和 unescapeHTML 使用一致的映射来间接验证单例模式。

var html1:String = "<b>Bold</b>";
var escaped1:String = StringUtils.escapeHTML(html1);
var unescaped1:String = StringUtils.unescapeHTML(escaped1);
runTest("单例模式测试 1: escapeHTML & unescapeHTML", html1, unescaped1);

var html2:String = "5 > 3 & 2 < 4";
var escaped2:String = StringUtils.escapeHTML(html2);
var unescaped2:String = StringUtils.unescapeHTML(escaped2);
runTest("单例模式测试 2: escapeHTML & unescapeHTML", html2, unescaped2);

// 26. 压缩与解压缩
trace("----- 测试 compress 和 decompress 方法 -----");

var original1:String = "Hello, World!";
var compressed1:String = StringUtils.compress(original1);
var decompressed1:String = StringUtils.decompress(compressed1);
runTest("compress/decompress ('Hello, World!')", original1, decompressed1);

var original2:String = "aaaaaaaaaa";
var compressed2:String = StringUtils.compress(original2);
var decompressed2:String = StringUtils.decompress(compressed2);
runTest("compress/decompress ('aaaaaaaaaa')", original2, decompressed2);

var original3:String = "This is a longer test string that will be compressed and decompressed using LZW algorithm.";
var compressed3:String = StringUtils.compress(original3);
var decompressed3:String = StringUtils.decompress(compressed3);
runTest("compress/decompress (long string)", original3, decompressed3);

var original4:String = "你好，世界！🌍";
var compressed4:String = StringUtils.compress(original4);
var decompressed4:String = StringUtils.decompress(compressed4);
runTest("compress/decompress ('你好，世界！🌍')", original4, decompressed4);

// 结束测试
trace("===== 所有测试完成 =====");

*/



















/*

import org.flashNight.gesh.string.StringUtils;

trace("----- Test createIndent() -----");
// 测试 createIndent 方法
trace("Depth 0: [" + StringUtils.createIndent(0) + "]"); // 期望输出: []
trace("Depth 1: [" + StringUtils.createIndent(1) + "]"); // 期望输出: [    ]
trace("Depth 3: [" + StringUtils.createIndent(3) + "]"); // 期望输出: [            ]

trace("\n----- Test escapeString() -----");
// 测试 escapeString 方法
trace(StringUtils.escapeString("Hello\nWorld")); // 期望输出: Hello\nWorld
trace(StringUtils.escapeString("He said \"Hello\"")); // 期望输出: He said \"Hello\"
trace(StringUtils.escapeString("Path\\to\\file")); // 期望输出: Path\\to\\file

trace("\n----- Test toJSON() -----");
// 测试 toJSON 方法
var obj:Object = {
    name: "AS2",
    value: 100,
    nested: {key: "value"},
    list: [1, 2, 3]
};

// 测试对象的 JSON 序列化
trace("Formatted JSON output:");
trace(StringUtils.toJSON(obj, true)); // 期望输出格式化的JSON字符串

trace("Compact JSON output:");
trace(StringUtils.toJSON(obj, false)); // 期望输出紧凑的JSON字符串

trace("\n----- Test Special Cases -----");
// 测试特殊情况

// 空对象
trace("Empty object: " + StringUtils.toJSON({}, true)); // 期望输出: {}

// 空数组
trace("Empty array: " + StringUtils.toJSON([], true)); // 期望输出: []

// null 和 undefined 的处理
trace("Null value: " + StringUtils.toJSON(null, true)); // 期望输出: null
trace("Undefined value: " + StringUtils.toJSON(undefined, true)); // 期望跳过 undefined 属性

// 循环引用处理
var objWithCycle:Object = {};
objWithCycle.self = objWithCycle;
trace("Cycle object: " + StringUtils.toJSON(objWithCycle, true)); // 期望输出: null 或者处理循环引用的方式

trace("\n----- Test Combined Object -----");
// 复杂对象组合测试
var complexObj:Object = {
    name: "Test Object",
    array: [1, 2, 3, "test\nstring"],
    nested: {a: 10, b: "Hello \"World\""},
    date: new Date(),
    escapeTest: "Line1\nLine2\\Path"
};

trace("Complex Object JSON output:");
trace(StringUtils.toJSON(complexObj, true)); // 期望输出格式化的JSON字符串

trace("\n----- Test Performance with Large Object -----");
// 性能测试 - 测试大对象的 JSON 序列化
var largeObj:Object = {};
for (var i:Number = 0; i < 1000; i++) {
    largeObj["key" + i] = "value" + i;
}

trace("Large object toJSON performance:");
trace(StringUtils.toJSON(largeObj, false)); // 测试性能和输出正确性

*/


/*
import org.flashNight.gesh.string.StringUtils;

// 辅助函数，用于生成重复字符
function repeat(str:String, times:Number):String {
    var result:String = "";
    for (var i:Number = 0; i < times; i++) {
        result += str;
    }
    return result;
}

// 定义测试用例
var testCases:Array = [
    // 原有测试用例
    {input: "Mixed Escape: \\n \\t \\u0041", expected: "Mixed Escape: \n \t A", description: "Multiple Escape Characters"},
    {input: "Incomplete Unicode: \\u123", expected: "Incomplete Unicode: \\u123", description: "Incomplete Unicode Sequence"},
    {input: "Special Characters: $&\\u0041!", expected: "Special Characters: $&A!", description: "Special Characters"},
    {input: "Invalid Escape: \\q \\r", expected: "Invalid Escape: \\q \\r", description: "Invalid Escape Sequences"},
    {input: "Mixed Unicode: A\\u0042C \\u0043D", expected: "Mixed Unicode: ABC CD", description: "Mixed Unicode and Normal Characters"},
    {input: "Escape with Number: \\n123", expected: "Escape with Number: \n123", description: "Escape Characters Followed by Numbers"},
    
    // 新增边界测试用例
    {input: "\\", expected: "\\", description: "Single Backslash at End"},
    {input: "\\n", expected: "\n", description: "Simple Escape at End"},
    {input: "a\\", expected: "a\\", description: "Single Backslash at End After Character"},
    {input: "\\\\", expected: "\\", description: "Double Backslash"},
    {input: "\\u0041\\", expected: "A\\", description: "Unicode Followed by Backslash"},
    {input: "Empty Escape \\", expected: "Empty Escape \\", description: "Empty Escape Sequence"},
    {input: "Empty String", expected: "Empty String", description: "String with No Escape"},
    {input: "", expected: "", description: "Empty String (No Characters)"}
];

// 执行测试
for (var i:Number = 0; i < testCases.length; i++) {
    var testCase:Object = testCases[i];
    var result:String = StringUtils.unescape(testCase.input);
    var passed:Boolean = (result == testCase.expected);
    
    if (!passed) {
        trace("Test Case " + (i + 1) + ": " + testCase.description);
        trace("Input: " + testCase.input);
        trace("Expected: " + testCase.expected);
        trace("Result: " + result);
        trace("Passed: " + passed);
        trace("");
    } else {
        trace("Test Case " + (i + 1) + ": Passed");
    }
}
*/