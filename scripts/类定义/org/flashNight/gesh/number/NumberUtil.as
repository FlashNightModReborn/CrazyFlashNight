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
}
