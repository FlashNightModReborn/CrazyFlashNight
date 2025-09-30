class org.flashNight.gesh.number.NumberUtil
{
    /**
     * 如果传入的 currentValue 是 NaN，则返回 defaultValue；否则返回 currentValue。
     * 用于处理诸如：
     *   if (isNaN(xxx)) xxx = defaultXxx;
     */
    public static function defaultIfNaN(currentValue:Number, defaultValue:Number):Number
    {
        return (isNaN(currentValue)) ? defaultValue : currentValue;
    }

    /**
     * 将字符串安全地转换为 Number，如果转换结果为 NaN，则返回 defaultValue。
     */
    public static function safeParseNumber(value:String, defaultValue:Number):Number
    {
        var parsedValue:Number = Number(value);
        return (isNaN(parsedValue)) ? defaultValue : parsedValue;
    }

    /**
     * 对两个数进行相加，如果结果为 NaN，则返回 defaultValue。
     */
    public static function safeAdd(num1:Number, num2:Number, defaultValue:Number):Number
    {
        var result:Number = num1 + num2;
        return (isNaN(result)) ? defaultValue : result;
    }

    /**
     * 对两个数进行相减，如果结果为 NaN，则返回 defaultValue。
     */
    public static function safeSubtract(num1:Number, num2:Number, defaultValue:Number):Number
    {
        var result:Number = num1 - num2;
        return (isNaN(result)) ? defaultValue : result;
    }

    /**
     * 对两个数进行相乘，如果结果为 NaN，则返回 defaultValue。
     */
    public static function safeMultiply(num1:Number, num2:Number, defaultValue:Number):Number
    {
        var result:Number = num1 * num2;
        return (isNaN(result)) ? defaultValue : result;
    }

    /**
     * 对两个数进行相除，如果除数为 0 或结果为 NaN，则返回 defaultValue。
     */
    public static function safeDivide(num1:Number, num2:Number, defaultValue:Number):Number
    {
        if (num2 == 0) {
            return defaultValue;
        }
        var result:Number = num1 / num2;
        return (isNaN(result)) ? defaultValue : result;
    }

    /**
     * 将 value 限制在 [min, max] 范围内并返回，若 value 超出范围则返回边界值。
     */
    public static function clamp(value:Number, min:Number, max:Number):Number
    {
        if (value < min) {
            return min;
        }
        if (value > max) {
            return max;
        }
        return value;
    }

    // ========== 有效性与回退 ==========
    
    /**
     * 检查一个数是否有效（非 NaN 且有限）
     */
    public static function isValidNumber(n:Number):Boolean
    {
        return !isNaN(n) && isFinite(n);
    }
    
    /**
     * 如果数值无效（NaN 或无限），返回默认值
     */
    public static function defaultIfInvalid(n:Number, defaultValue:Number):Number
    {
        return (!isNaN(n) && isFinite(n)) ? n : defaultValue;
    }
    
    /**
     * 浮点数近似相等比较
     * @param epsilon 容差值，默认 1e-6
     */
    public static function approxEqual(a:Number, b:Number, epsilon:Number):Boolean
    {
        if (epsilon == undefined) epsilon = 0.000001;
        return Math.abs(a - b) < epsilon;
    }
    
    /**
     * 检查值是否在指定区间内
     * @param inclusive 是否包含边界，默认为 true
     */
    public static function between(value:Number, min:Number, max:Number, inclusive:Boolean):Boolean
    {
        if (inclusive == undefined) inclusive = true;
        if (inclusive) {
            return value >= min && value <= max;
        } else {
            return value > min && value < max;
        }
    }

    // ========== 归一化 / 映射 / 包裹 ==========
    
    /**
     * 将值限制到 [0, 1] 区间
     */
    public static function clamp01(value:Number):Number
    {
        return clamp(value, 0, 1);
    }
    
    /**
     * 将值从 [min, max] 归一化到 [0, 1]
     * @param defaultValue 当 max == min 时返回的默认值
     */
    public static function normalize(value:Number, min:Number, max:Number, defaultValue:Number):Number
    {
        if (defaultValue == undefined) defaultValue = 0;
        if (max == min) return defaultValue;
        return (value - min) / (max - min);
    }
    
    /**
     * 将值从输入区间映射到输出区间
     * @param clampOutput 是否限制输出到目标区间内
     */
    public static function remap(value:Number, inMin:Number, inMax:Number, outMin:Number, outMax:Number, clampOutput:Boolean):Number
    {
        if (clampOutput == undefined) clampOutput = false;
        if (inMax == inMin) return outMin;
        
        var normalized:Number = (value - inMin) / (inMax - inMin);
        var result:Number = outMin + normalized * (outMax - outMin);
        
        if (clampOutput) {
            result = clamp(result, Math.min(outMin, outMax), Math.max(outMin, outMax));
        }
        return result;
    }
    
    /**
     * 将值包裹到指定区间内（循环）
     * 常用于角度、循环动画等
     */
    public static function wrap(value:Number, min:Number, max:Number):Number
    {
        var range:Number = max - min;
        if (range <= 0) return min;
        
        var result:Number = value - min;
        result = result - Math.floor(result / range) * range;
        return result + min;
    }
    
    /**
     * 将角度（度）归一化到 (-180, 180] 区间
     */
    public static function wrapAngleDeg(angle:Number):Number
    {
        angle = angle % 360;
        if (angle > 180) angle -= 360;
        else if (angle <= -180) angle += 360;
        return angle;
    }
    
    /**
     * 将角度（弧度）归一化到 (-π, π] 区间
     */
    public static function wrapAngleRad(angle:Number):Number
    {
        angle = angle % (2 * Math.PI);
        if (angle > Math.PI) angle -= 2 * Math.PI;
        else if (angle <= -Math.PI) angle += 2 * Math.PI;
        return angle;
    }
    
    /**
     * 度转弧度
     */
    public static function deg2rad(degrees:Number):Number
    {
        return degrees * Math.PI / 180;
    }
    
    /**
     * 弧度转度
     */
    public static function rad2deg(radians:Number):Number
    {
        return radians * 180 / Math.PI;
    }

    // ========== 安全算子 / 量化 ==========
    
    /**
     * 安全取模运算，n == 0 时返回默认值
     * 结果始终为正数
     */
    public static function safeMod(a:Number, n:Number, defaultValue:Number):Number
    {
        if (n == 0) return defaultValue;
        var result:Number = a % n;
        if (result < 0) result += Math.abs(n);
        return result;
    }
    
    /**
     * 将值对齐到步进网格
     * @param step 步进值
     * @param offset 偏移量，默认 0
     */
    public static function snap(value:Number, step:Number, offset:Number):Number
    {
        if (offset == undefined) offset = 0;
        if (step <= 0) return value;
        
        return Math.round((value - offset) / step) * step + offset;
    }
    
    /**
     * 限制单步变化量（常用于平滑追踪）
     * 将 current 向 target 移动，但最多移动 maxDelta
     */
    public static function constrainDelta(current:Number, target:Number, maxDelta:Number):Number
    {
        var delta:Number = target - current;
        if (Math.abs(delta) <= maxDelta) {
            return target;
        }
        return current + (delta > 0 ? maxDelta : -maxDelta);
    }
    
    /**
     * 返回数的符号：-1、0 或 1
     */
    public static function sign(n:Number):Number
    {
        if (n > 0) return 1;
        if (n < 0) return -1;
        return 0;
    }
    
    /**
     * 返回两数的绝对差值
     */
    public static function absDiff(a:Number, b:Number):Number
    {
        return Math.abs(a - b);
    }

    // ========== 聚合 ==========
    
    /**
     * 计算数组平均值，忽略 NaN 值
     * @param defaultValue 数组为空或全为 NaN 时返回的默认值
     */
    public static function average(arr:Array, defaultValue:Number):Number
    {
        if (defaultValue == undefined) defaultValue = 0;
        if (arr == null || arr.length == 0) return defaultValue;
        
        var sum:Number = 0;
        var count:Number = 0;
        
        for (var i:Number = 0; i < arr.length; i++) {
            if (!isNaN(arr[i])) {
                sum += arr[i];
                count++;
            }
        }
        
        if (count == 0) return defaultValue;
        return sum / count;
    }

    // ========== 格式化 ==========

    /**
     * 将数字格式化为固定小数位数的字符串
     * 严格按照 ECMAScript (ECMA-262) 规范实现 toFixed 方法
     * @param num 要格式化的数字
     * @param fractionDigits 小数位数（0-100），默认为 0
     * @return 格式化后的字符串
     *
     * 规范行为（现代 ES 标准）：
     * - fractionDigits 先 ToIntegerOrInfinity 转换（NaN→0, 截断小数）
     * - fractionDigits 范围必须在 0-100 之间（现代规范）
     * - NaN 返回 "NaN"
     * - Infinity 返回 "Infinity" 或 "-Infinity"
     * - 对于绝对值 >= 1e+21 的数，使用 ToString 规范转换
     * - 其他情况使用定点表示法，保留指定小数位数
     * - 采用十进制 Half-Up 舍入（五则远离零取整）
     * - 正确处理 -0 的符号
     */
    public static function toFixed(num:Number, fractionDigits:Number):String
    {
        // 1. ToIntegerOrInfinity 转换 fractionDigits
        var f:Number = toIntegerOrInfinity(fractionDigits);

        // 2. 验证范围（现代规范：0-100）
        if (f < 0 || f > 100) {
            return "RangeError: toFixed() digits argument must be between 0 and 100";
        }

        // 3. 处理特殊值
        if (isNaN(num)) {
            return "NaN";
        }

        if (!isFinite(num)) {
            return num < 0 ? "-Infinity" : "Infinity";
        }

        // 4. 处理大数值（|x| >= 1e+21 使用 ToString）
        if (Math.abs(num) >= 1e21) {
            return String(num);
        }

        // 5. 记录符号并取绝对值
        var isNegative:Boolean = num < 0;
        var x:Number = Math.abs(num);

        // 6. 十进制字符串操作实现精确 Half-Up 舍入
        var result:String = toFixedPrecise(x, f);

        // 7. 处理 -0：如果结果为纯 0，去掉负号
        if (isNegative) {
            if (!isResultZero(result)) {
                result = "-" + result;
            }
        }

        return result;
    }

    /**
     * ToIntegerOrInfinity 抽象操作（ECMA-262 规范）
     * NaN → +0
     * ±∞ → ±∞
     * 其他 → 截断小数部分（向零取整）
     */
    private static function toIntegerOrInfinity(value:Number):Number
    {
        if (value == undefined) return 0;
        if (isNaN(value)) return 0;
        if (!isFinite(value)) return value;

        // 向零截断（去掉小数部分）
        if (value >= 0) {
            return Math.floor(value);
        } else {
            return Math.ceil(value);
        }
    }

    /**
     * 精确的十进制字符串舍入（Half-Up）
     * 避免二进制浮点误差
     */
    private static function toFixedPrecise(x:Number, f:Number):String
    {
        if (f == 0) {
            // 0 位小数：直接四舍五入到整数（Half-Up）
            return String(Math.floor(x + 0.5));
        }

        // 将数字转为字符串，手动进行十进制运算
        var str:String = String(x);

        // 处理科学计数法（如 5e-7）
        if (str.indexOf("e") >= 0 || str.indexOf("E") >= 0) {
            // 扩展为完整小数表示
            str = expandScientificNotation(x);
        }

        var dotPos:Number = str.indexOf(".");

        if (dotPos < 0) {
            // 整数，直接补小数点和零
            str += ".";
            for (var i:Number = 0; i < f; i++) {
                str += "0";
            }
            return str;
        }

        var intPart:String = str.substring(0, dotPos);
        var fracPart:String = str.substring(dotPos + 1);

        // 需要舍入的位置
        if (fracPart.length <= f) {
            // 不需要舍入，补零
            while (fracPart.length < f) {
                fracPart += "0";
            }
            return intPart + "." + fracPart;
        }

        // 需要舍入：Half-Up（五则进位）
        var keepDigits:String = fracPart.substring(0, f);
        var nextDigit:Number = Number(fracPart.charAt(f));

        if (nextDigit >= 5) {
            // 进位
            var rounded:String = addOneToDecimal(intPart + keepDigits);

            // 插入小数点
            if (f == 0) {
                return rounded;
            }

            var len:Number = rounded.length;
            var insertPos:Number = len - f;
            if (insertPos <= 0) {
                // 位数不够，前面补零
                while (insertPos < 0) {
                    rounded = "0" + rounded;
                    insertPos++;
                }
                return "0." + rounded;
            }

            return rounded.substring(0, insertPos) + "." + rounded.substring(insertPos);
        } else {
            // 不进位
            return intPart + "." + keepDigits;
        }
    }

    /**
     * 将科学计数法字符串扩展为完整小数表示
     */
    private static function expandScientificNotation(x:Number):String
    {
        // 简化处理：使用足够大的精度重新格式化
        var str:String = String(x);
        var ePos:Number = str.indexOf("e");
        if (ePos < 0) ePos = str.indexOf("E");
        if (ePos < 0) return str;

        var mantissa:String = str.substring(0, ePos);
        var exponent:Number = Number(str.substring(ePos + 1));

        var dotPos:Number = mantissa.indexOf(".");
        var digits:String;

        if (dotPos >= 0) {
            digits = mantissa.substring(0, dotPos) + mantissa.substring(dotPos + 1);
            exponent -= (mantissa.length - dotPos - 1);
        } else {
            digits = mantissa;
        }

        // 移除前导零
        while (digits.length > 1 && digits.charAt(0) == "0") {
            digits = digits.substring(1);
        }

        var result:String;
        if (exponent >= 0) {
            // 正指数：整数或大数
            result = digits;
            for (var i:Number = 0; i < exponent; i++) {
                result += "0";
            }
        } else {
            // 负指数：小数
            var absExp:Number = -exponent;
            if (absExp >= digits.length) {
                // 需要前导零
                result = "0.";
                for (var j:Number = 0; j < absExp - digits.length; j++) {
                    result += "0";
                }
                result += digits;
            } else {
                // 插入小数点
                var pos:Number = digits.length - absExp;
                result = digits.substring(0, pos) + "." + digits.substring(pos);
            }
        }

        return result;
    }

    /**
     * 对十进制字符串（仅数字）加一
     */
    private static function addOneToDecimal(numStr:String):String
    {
        var carry:Number = 1;
        var result:String = "";

        for (var i:Number = numStr.length - 1; i >= 0; i--) {
            var digit:Number = Number(numStr.charAt(i)) + carry;
            if (digit >= 10) {
                result = "0" + result;
                carry = 1;
            } else {
                result = String(digit) + result;
                carry = 0;
            }
        }

        if (carry > 0) {
            result = "1" + result;
        }

        return result;
    }

    /**
     * 检查结果字符串是否表示零（含小数点的零：0, 0.0, 0.00 等）
     */
    private static function isResultZero(str:String):Boolean
    {
        for (var i:Number = 0; i < str.length; i++) {
            var c:String = str.charAt(i);
            if (c != "0" && c != ".") {
                return false;
            }
        }
        return true;
    }
}
