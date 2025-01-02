// 文件: org/flashNight/gesh/number/NumberUtil.as

class org.flashNight.gesh.number.NumberUtil {
    
    // =========================================
    // 1. 静态常量 (非科学计数法, 避免精度丢失)
    // =========================================
    
    public static var EPSILON:Number = 0.0000000000000002220446049250313;
    public static var MAX_SAFE_INTEGER:Number = 9007199254740991;
    public static var MIN_SAFE_INTEGER:Number = -9007199254740991;
    
    // =========================================
    // 2. 预计算字符映射表
    // =========================================
    
    /**
     * 存储 '0'-'9', 'A'-'Z', 'a'-'z' 对应的进制数值
     * 映射关系:
     *   '0'~'9' => 0~9
     *   'A'~'Z' => 10~35
     *   'a'~'z' => 10~35
     * 其他字符 => -1 (无效)
     */
    private static var DIGIT_MAP:Array = buildDigitMap();
    
    /**
     * 生成字符映射表的静态方法:
     *  - 128 长度数组(只考虑 ASCII 范围内的字符码)
     *  - 不在范围内或无效字符 => -1
     */
    private static function buildDigitMap():Array {
        var map:Array = new Array(128);
        var i:Number;
        
        // 1) 默认全部 -1
        for (i = 0; i < 128; i++) {
            map[i] = -1;
        }
        
        // 2) '0'~'9' => 48~57
        for (i = 48; i <= 57; i++) {
            map[i] = i - 48; // '0'(48)->0, '9'(57)->9
        }
        
        // 3) 'A'~'Z' => 65~90
        for (i = 65; i <= 90; i++) {
            map[i] = i - 55; // 'A'(65)->10, 'Z'(90)->35
        }
        
        // 4) 'a'~'z' => 97~122
        for (i = 97; i <= 122; i++) {
            map[i] = i - 87; // 'a'(97)->10, 'z'(122)->35
        }
        
        return map;
    }
    
    // =========================================
    // 3. isNaN / isFinite
    // =========================================
    
    /**
     * 模拟 ES6 Number.isNaN(value)
     *  - 若不是 number 类型 => false
     *  - 若 value != value 或 value===_global.NaN => true
     */
    public static function isNaN(value:Object):Boolean {
        // 1. 检查类型是否为 number
        if (typeof value != "number") {
            return false;
        }
        // 2. 执行两种判定方式: 自身不等于自身 或 与 _global.NaN 比较
        return (value != value) || value === _global.NaN;
    }

    /**
     * 模拟 ES6 Number.isFinite(value)
     *  - 必须是 number 类型
     *  - 不得是 ±Infinity, 不得是 NaN
     */
    public static function isFinite(value:Object):Boolean {
        // 1. 必须是 number 类型
        if (typeof value != "number") {
            return false;
        }
        // 2. 检查 ±Infinity
        if (value == 1.0 / 0.0 || value == -1.0 / 0.0) {
            return false;
        }
        // 3. 检查 NaN
        return !(value != value) && value !== _global.NaN;
    }

    
    // =========================================
    // 4. isInteger / isSafeInteger
    // =========================================
    
    /**
     * 模拟 ES6 Number.isInteger(value)
     *  - 必须是 number 类型
     *  - 不得是 ±Infinity, 不得是 NaN
     *  - (value % 1 == 0) => true
     */
    public static function isInteger(value:Object):Boolean {
        if (typeof value != "number") {
            return false;
        }
        // ±Infinity
        if (value == 1.0/0.0 || value == -1.0/0.0) {
            return false;
        }
        // NaN
        if (value != value) {
            return false;
        }
        // 整数判断
        return (value % 1 == 0);
    }
    
    /**
     * 模拟 ES6 Number.isSafeInteger(value)
     *  - 必须是 number 类型
     *  - 不得是 ±Infinity, 不得是 NaN
     *  - 必须是整数 (value % 1 == 0)
     *  - 在 [MIN_SAFE_INTEGER, MAX_SAFE_INTEGER] 范围内
     */
    public static function isSafeInteger(value:Object):Boolean {
        if (typeof value != "number") {
            return false;
        }
        // ±Infinity
        if (value == 1.0/0.0 || value == -1.0/0.0) {
            return false;
        }
        // NaN
        if (value != value) {
            return false;
        }
        // 非整数
        if (value % 1 != 0) {
            return false;
        }
        // 检查范围
        var num:Number = Number(value);
        if (num < MIN_SAFE_INTEGER || num > MAX_SAFE_INTEGER) {
            return false;
        }
        return true;
    }
    
    // =========================================
    // 5. parseInt / parseFloat
    // =========================================
    
    /**
     * 模拟 ES6 Number.parseInt(str, radix)
     *  - 不使用内置 parseInt
     *  - 完全内联字符串解析 + 预计算映射表
     */
    public static function parseInt(str:String, radix:Number):Number {
        // 1) 空或 null => NaN
        if (!str) {
            return NaN;
        }
        
        // 2) 若 radix 无效 => 默认 10
        if (typeof radix != "number" || isNaN(radix) || radix < 2 || radix > 36) {
            radix = 10;
        }
        
        // 3) 去掉左侧空白
        var len:Number = str.length;
        var idx:Number = 0;
        while (idx < len) {
            var cc:String = str.charAt(idx);
            if (cc != ' ' && cc != '\t' && cc != '\r' && cc != '\n') {
                break;
            }
            idx++;
        }
        // 若全是空白 => NaN
        if (idx >= len) {
            return NaN;
        }
        
        // 4) 处理正负号
        var sign:Number = 1;
        var firstChar:String = str.charAt(idx);
        if (firstChar == '+') {
            idx++;
        } else if (firstChar == '-') {
            sign = -1;
            idx++;
        }
        
        // 5) 处理 “0x” / “0X” 前缀（仅在 radix=16 时有效）
        if (radix == 16 && (idx + 1) < len) {
            var c0:String = str.charAt(idx);
            var c1:String = str.charAt(idx + 1);
            if (c0 == '0' && (c1 == 'x' || c1 == 'X')) {
                idx += 2; // 跳过 '0x'
            }
        }
        
        // 6) 累加数字 (利用映射表)
        var result:Number = 0;
        var parsedAnyDigit:Boolean = false;
        
        while (idx < len) {
            var code:Number = str.charCodeAt(idx);
            var digit:Number = -1;
            
            // 查表(仅针对 ASCII < 128 范围内)
            if (code < 128) {
                digit = DIGIT_MAP[code];
            }
            
            // digit 超出进制或为无效 => 结束
            if (digit < 0 || digit >= radix) {
                break;
            }
            result = result * radix + digit;
            parsedAnyDigit = true;
            idx++;
        }
        
        // 若未解析到任何 digit => NaN
        if (!parsedAnyDigit) {
            return NaN;
        }
        
        return sign * result;
    }
    
    /**
     * 模拟 ES6 Number.parseFloat(str)
     *  - 不使用内置 parseFloat
     *  - 完全内联字符串解析
     *  - (AS2经测试，字符串拼接方式比数组缓冲更快)
     */
    public static function parseFloat(str:String):Number {
        // 1) 空或 null => NaN
        if (!str) {
            return NaN;
        }
        
        var len:Number = str.length;
        var idx:Number = 0;
        
        // 2) 去掉左侧空白
        while (idx < len) {
            var cc:String = str.charAt(idx);
            if (cc != ' ' && cc != '\t' && cc != '\r' && cc != '\n') {
                break;
            }
            idx++;
        }
        if (idx >= len) {
            return NaN;
        }
        
        // 3) 处理正负号
        var sign:Number = 1;
        var fc:String = str.charAt(idx);
        if (fc == '+') {
            idx++;
        } else if (fc == '-') {
            sign = -1;
            idx++;
        }
        
        // 4) 收集数字部分（含小数点）
        var numStr:String = "";
        var hasDigit:Boolean = false;
        var hasDot:Boolean = false;
        
        while (idx < len) {
            var c:String = str.charAt(idx);
            if (c >= '0' && c <= '9') {
                numStr += c;
                hasDigit = true;
                idx++;
            } else if (c == '.' && !hasDot) {
                hasDot = true;
                numStr += c;
                idx++;
            } else {
                break;
            }
        }
        
        // 如果没有任何数字 => NaN
        if (!hasDigit) {
            return NaN;
        }
        
        // 5) 解析指数 e|E
        var nextC:String = (idx < len) ? str.charAt(idx) : "";
        if ((nextC == 'e' || nextC == 'E') && numStr != "") {
            numStr += nextC;
            idx++;
            
            // 检查指数符号
            var es:String = (idx < len) ? str.charAt(idx) : "";
            if (es == '+' || es == '-') {
                numStr += es;
                idx++;
            }
            
            // 收集指数数字
            var expHasDigit:Boolean = false;
            while (idx < len) {
                var cE:String = str.charAt(idx);
                if (cE >= '0' && cE <= '9') {
                    numStr += cE;
                    expHasDigit = true;
                    idx++;
                } else {
                    break;
                }
            }
            // 无指数数字 => 去掉 e|E
            if (!expHasDigit) {
                var cutLen:Number = (es == '+' || es == '-') ? 2 : 1;
                numStr = numStr.substr(0, numStr.length - cutLen);
            }
        }
        
        // 6) 用 Number(...) 转换
        var floatVal:Number = Number(numStr);
        
        // 若转换后仍是 NaN，则返回 NaN
        if (floatVal != floatVal) {
            return NaN;
        }
        
        // 7) 应用符号
        return sign * floatVal;
    }
}
