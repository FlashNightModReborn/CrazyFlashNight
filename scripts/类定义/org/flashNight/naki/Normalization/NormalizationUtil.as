/**
 * NormalizationUtil
 * 提供常用的数学函数，用于归一化计算和激活函数
 */
class org.flashNight.naki.Normalization.NormalizationUtil
{
    /**
     * sigmoid函数
     * @param x 输入值
     * @return sigmoid(x)
     */
    public static function sigmoid(x:Number):Number {
        return 1 / (1 + Math.exp(-x));
    }

    /**
     * ReLU函数
     * @param x 输入值
     * @return relu(x)
     */
    public static function relu(x:Number):Number
    {
        return Math.max(0, x);
    }

    /**
     * Leaky ReLU函数
     * @param x 输入值
     * @param alpha Leaky ReLU 的斜率参数，默认为0.01
     * @return leakyRelu(x)
     */
    public static function leakyRelu(x:Number, alpha:Number):Number
    {
        return (x > 0) ? x : alpha * x;
    }

    /**
     * softplus函数
     * @param x 输入值
     * @return softplus(x)
     */
    public static function softplus(x:Number):Number
    {
        return Math.log(1 + Math.exp(x));
    }

    /**
     * 自定义sig_tyler函数
     * @param x 输入值
     * @return 计算结果
     */
    public static function sig_tyler(x:Number):Number
    {
        return 3 * x / 40 + 0.5 - (x * x * x) / 4000;
    }

    /**
     * tanh函数
     * @param x 输入值
     * @return tanh(x)
     */
    public static function tanh(x:Number):Number
    {
        var ePos:Number = Math.exp(x);
        var eNeg:Number = Math.exp(-x);
        return (ePos - eNeg) / (ePos + eNeg);
    }

    /**
     * min-max 归一化
     * 将值归一化到指定范围 [newMin, newMax]
     * @param value 需要归一化的值
     * @param originalMin 原始数据的最小值
     * @param originalMax 原始数据的最大值
     * @param newMin 归一化后的最小值
     * @param newMax 归一化后的最大值
     * @return 归一化后的值
     */
    public static function minMaxNormalize(value:Number, originalMin:Number, originalMax:Number, newMin:Number, newMax:Number):Number
    {
        if (originalMax - originalMin == 0) {
            return newMin; // 避免除以零
        }
        return ((value - originalMin) / (originalMax - originalMin)) * (newMax - newMin) + newMin;
    }

    /**
     * z-score 归一化
     * 将值转换为标准分数（z-score）
     * @param value 需要归一化的值
     * @param mean 数据的均值
     * @param stdDev 数据的标准差
     * @return 标准分数
     */
    public static function zScoreNormalize(value:Number, mean:Number, stdDev:Number):Number
    {
        if (stdDev == 0) {
            return 0; // 避免除以零
        }
        return (value - mean) / stdDev;
    }

    /**
     * clamp函数
     * 将值限制在指定的范围内
     * @param value 输入值
     * @param min 最小值
     * @param max 最大值
     * @return 限制后的值
     */
    public static function clamp(value:Number, min:Number, max:Number):Number
    {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    /**
     * softmax函数
     * 对一组值进行softmax归一化
     * @param values 输入值数组
     * @return 归一化后的数组
     */
    public static function softmax(values:Array):Array
    {
        var maxVal:Number = Math.max.apply(null, values);
        var expSum:Number = 0;
        var expValues:Array = new Array();

        // 计算每个值的指数，并累加
        for (var i:Number = 0; i < values.length; i++) {
            var expVal:Number = Math.exp(values[i] - maxVal); // 减去maxVal以提高数值稳定性
            expValues.push(expVal);
            expSum += expVal;
        }

        // 归一化
        for (i = 0; i < expValues.length; i++) {
            expValues[i] = expValues[i] / expSum;
        }

        return expValues;
    }

    /**
     * normalizeVector函数
     * 将向量归一化为单位向量
     * @param vector 输入的向量数组
     * @return 归一化后的向量数组
     */
    public static function normalizeVector(vector:Array):Array
    {
        var sumSquares:Number = 0;
        for (var i:Number = 0; i < vector.length; i++) {
            sumSquares += vector[i] * vector[i];
        }
        var magnitude:Number = Math.sqrt(sumSquares);
        if (magnitude == 0) {
            return vector; // 避免除以零
        }
        var normalizedVector:Array = new Array();
        for (i = 0; i < vector.length; i++) {
            normalizedVector.push(vector[i] / magnitude);
        }
        return normalizedVector;
    }

    /**
     * linearScale函数
     * 线性缩放值到指定范围
     * @param value 输入值
     * @param originalMin 原始最小值
     * @param originalMax 原始最大值
     * @param targetMin 目标最小值
     * @param targetMax 目标最大值
     * @return 缩放后的值
     */
    public static function linearScale(value:Number, originalMin:Number, originalMax:Number, targetMin:Number, targetMax:Number):Number
    {
        if (originalMax - originalMin == 0) {
            return targetMin; // 避免除以零
        }
        return ((value - originalMin) / (originalMax - originalMin)) * (targetMax - targetMin) + targetMin;
    }

    /**
     * exponentialScale函数
     * 指数缩放值到指定范围
     * @param value 输入值
     * @param base 缩放基数
     * @param targetMin 目标最小值
     * @param targetMax 目标最大值
     * @return 缩放后的值
     */
    public static function exponentialScale(value:Number, base:Number, targetMin:Number, targetMax:Number):Number
    {
        var scaledValue:Number = Math.pow(base, value);
        // 假设 value 在 [0, 1] 范围内
        return scaledValue * (targetMax - targetMin) + targetMin;
    }

    /**
     * Fractional Linear Transformation (FLT) 函数
     * 提供类似sigmoid的归一化效果，避免使用开销较大的exp函数
     * @param x 输入值
     * @return 归一化后的值，范围在 (-1, 1)
     */
    public static function flt(x:Number):Number
    {
        return x / (1 + ((x < 0) ? -x : x)); // 使用三元运算符替代 Math.abs
    }
}
