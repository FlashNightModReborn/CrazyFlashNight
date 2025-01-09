class org.flashNight.naki.Interpolation.Interpolatior {

    /**
     * 线性插值 (Linear Interpolation, Lerp)
     * 
     * 该方法用于在源范围 (srcLow-srcHigh) 与目标范围 (dstLow-dstHigh) 之间进行线性插值。
     * 
     * @param value  当前值，插值中间点，需要位于源范围内
     * @param srcLow  源范围的最小值
     * @param srcHigh 源范围的最大值
     * @param dstLow  目标范围的最小值
     * @param dstHigh 目标范围的最大值
     * @return 返回插值结果，将 value 从源范围映射到目标范围
     */
    public static function linear(value:Number, srcLow:Number, srcHigh:Number, dstLow:Number, dstHigh:Number):Number {
        return srcLow == srcHigh ? dstLow : (value - srcLow) / (srcHigh - srcLow) * (dstHigh - dstLow) + dstLow;
    }

    /**
     * 球面线性插值 (Spherical Linear Interpolation, Slerp)
     * 
     * 该方法用于两个点之间的球面插值，通常用于处理旋转插值 (例如四元数)。
     * 
     * @param start 起始点值（例如角度或旋转）
     * @param end   终止点值
     * @param t     插值系数，范围 [0, 1]，表示插值进度
     * @return 返回在 t 时刻的插值结果
     */
    public static function slerp(start:Number, end:Number, t:Number):Number {
        // 计算两点之间的夹角 theta
        var theta:Number = Math.acos(start * end);
        // 计算 sin(theta) 避免除零错误
        var sinTheta:Number = Math.sin(theta);
        if (sinTheta == 0) return start; // 如果角度为0，返回起始值
        // 球面线性插值公式
        return (Math.sin((1 - t) * theta) / sinTheta) * start + (Math.sin(t * theta) / sinTheta) * end;
    }

    /**
     * 三次插值 (Cubic Interpolation)
     * 
     * 使用四个控制点在曲线上进行平滑的三次插值。
     * 
     * @param t   插值参数，范围 [0, 1]，表示插值进度
     * @param p0  第一个控制点（起点）
     * @param p1  第二个控制点
     * @param p2  第三个控制点
     * @param p3  第四个控制点（终点）
     * @return 返回三次插值计算结果
     */
    public static function cubic(t:Number, p0:Number, p1:Number, p2:Number, p3:Number):Number {
        // 计算三次插值的系数
        var a0:Number = p3 - p2 - p0 + p1;
        var a1:Number = p0 - p1 - a0;
        var a2:Number = p2 - p0;
        var a3:Number = p1;
        // 使用三次插值公式返回结果
        return a0 * t * t * t + a1 * t * t + a2 * t + a3;
    }

    /**
     * Hermite插值 (Hermite Interpolation)
     * 
     * 通过两个点和对应的切线斜率，计算平滑曲线上的插值。
     * 
     * @param t   插值参数，范围 [0, 1]，表示插值进度
     * @param p0  起始点值
     * @param p1  终止点值
     * @param m0  起始点的切线斜率
     * @param m1  终止点的切线斜率
     * @return 返回 Hermite 插值结果
     */
    public static function hermite(t:Number, p0:Number, p1:Number, m0:Number, m1:Number):Number {
        // 预计算 t 的平方和立方以提高性能
        var t2:Number = t * t;
        var t3:Number = t2 * t;
        // Hermite 插值公式，考虑了每个点的斜率
        return (2 * t3 - 3 * t2 + 1) * p0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * p1 + (t3 - t2) * m1;
    }

    /**
     * 贝塞尔插值 (Bezier Interpolation)
     * 
     * 通过四个控制点的贝塞尔曲线进行平滑插值。
     * 
     * @param t   插值参数，范围 [0, 1]
     * @param p0  第一个控制点
     * @param p1  第二个控制点
     * @param p2  第三个控制点
     * @param p3  第四个控制点
     * @return 返回贝塞尔曲线插值结果
     */
    public static function bezier(t:Number, p0:Number, p1:Number, p2:Number, p3:Number):Number {
        var u:Number = 1 - t;
        var tt:Number = t * t;
        var uu:Number = u * u;
        var uuu:Number = uu * u;
        var ttt:Number = tt * t;
        // 贝塞尔插值公式，将控制点组合计算插值结果
        var result:Number = uuu * p0; // 第一项
        result += 3 * uu * t * p1; // 第二项
        result += 3 * u * tt * p2; // 第三项
        result += ttt * p3; // 第四项
        return result;
    }

    /**
     * 缓动插值 (Ease-In-Out Interpolation)
     * 
     * 创建加速和减速效果的缓动插值，用于动画过渡。
     * 
     * @param t 插值参数，范围 [0, 1]
     * @return 返回缓动插值结果
     */
    public static function easeInOut(t:Number):Number {
        // 小于 0.5 加速，大于 0.5 减速
        return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
    }

    /**
     * 双线性插值 (Bilinear Interpolation)
     * 
     * 在二维平面上进行双线性插值，常用于图像缩放和纹理采样。
     * 
     * @param x    当前 x 坐标
     * @param y    当前 y 坐标
     * @param Q11  左下角的值
     * @param Q12  左上角的值
     * @param Q21  右下角的值
     * @param Q22  右上角的值
     * @param x1   x 的最小值
     * @param x2   x 的最大值
     * @param y1   y 的最小值
     * @param y2   y 的最大值
     * @return 返回插值结果
     */
    public static function bilinear(x:Number, y:Number, Q11:Number, Q12:Number, Q21:Number, Q22:Number, x1:Number, x2:Number, y1:Number, y2:Number):Number {
        // 计算 x 方向上的插值
        var R1:Number = ((x2 - x) / (x2 - x1)) * Q11 + ((x - x1) / (x2 - x1)) * Q21;
        var R2:Number = ((x2 - x) / (x2 - x1)) * Q12 + ((x - x1) / (x2 - x1)) * Q22;
        // 在 y 方向上进行插值并返回结果
        return ((y2 - y) / (y2 - y1)) * R1 + ((y - y1) / (y2 - y1)) * R2;
    }

    /**
     * 双三次插值 (Bicubic Interpolation)
     * 
     * 在二维平面上进行双三次插值，用于更加平滑的图像缩放和纹理处理。
     * 
     * @param t   插值参数，范围 [0, 1]
     * @param p0  第一个控制点
     * @param p1  第二个控制点
     * @param p2  第三个控制点
     * @param p3  第四个控制点
     * @return 返回双三次插值结果
     */
    public static function bicubic(t:Number, p0:Number, p1:Number, p2:Number, p3:Number):Number {
        // 计算双三次插值的系数
        var a0:Number = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3;
        var a1:Number = p0 - 2.5 * p1 + 2 * p2 - 0.5 * p3;
        var a2:Number = -0.5 * p0 + 0.5 * p2;
        var a3:Number = p1;
        // 使用双三次插值公式返回结果
        return a0 * t * t * t + a1 * t * t + a2 * t + a3;
    }

    /**
     * Catmull-Rom样条插值 (Catmull-Rom Spline Interpolation)
     * 
     * 使用 Catmull-Rom 样条进行平滑曲线插值，适用于路径规划。
     * 
     * @param t   插值参数，范围 [0, 1]
     * @param p0  第一个控制点
     * @param p1  第二个控制点
     * @param p2  第三个控制点
     * @param p3  第四个控制点
     * @return 返回样条插值结果
     */
    public static function catmullRom(t:Number, p0:Number, p1:Number, p2:Number, p3:Number):Number {
        // Catmull-Rom 样条插值公式
        return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t);
    }

    /**
     * 指数插值 (Exponential Interpolation)
     * 
     * 使用指数函数进行非线性插值，适用于加速或减速效果。
     * 
     * @param value 当前插值点
     * @param base  指数基数，用于控制插值的非线性程度
     * @return 返回指数插值结果
     */
    public static function exponential(value:Number, base:Number):Number {
        return Math.pow(base, value) - 1;
    }

    /**
     * 正弦插值 (Sinusoidal Interpolation)
     * 
     * 使用正弦函数进行平滑过渡，适用于周期性动画。
     * 
     * @param t 插值参数，范围 [0, 1]
     * @return 返回正弦插值结果
     */
    public static function sine(t:Number):Number {
        return Math.sin(t * (Math.PI / 2));
    }

    /**
     * 弹性插值 (Elastic Interpolation)
     * 
     * 模拟弹簧效果的弹性插值，用于创建带有弹性反弹的动画效果。
     * 
     * @param t 插值参数，范围 [0, 1]
     * @return 返回弹性插值结果
     */
    public static function elastic(t:Number):Number {
        return Math.pow(2, -10 * t) * Math.sin((t - 0.3 / 4) * (2 * Math.PI) / 0.3) + 1;
    }

    /**
     * 对数插值 (Logarithmic Interpolation)
     * 
     * 使用对数函数进行插值，常用于音量调节等渐进变化。
     * 
     * @param value 当前插值点
     * @param base  对数基数，用于控制插值的非线性程度
     * @return 返回对数插值结果
     */
    public static function logarithmic(value:Number, base:Number):Number {
        return Math.log(value + 1) / Math.log(base);
    }

    /**
     * Perlin噪声插值 (Perlin Noise Interpolation)
     * 
     * 生成平滑的噪声插值，常用于程序生成纹理或地形。
     * 
     * @param t 插值参数，范围 [0, 1]
     * @return 返回 Perlin 噪声插值结果
     */
    public static function perlin(t:Number):Number {
        // Perlin 噪声的简化实现
        return t * t * (3 - 2 * t);
    }
}
