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
}
