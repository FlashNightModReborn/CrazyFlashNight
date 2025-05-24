class org.flashNight.naki.Interpolation.Interpolatior {

    public static function linear(value:Number, srcLow:Number, srcHigh:Number, dstLow:Number, dstHigh:Number):Number {
        return srcLow == srcHigh ? dstLow : (value - srcLow) / (srcHigh - srcLow) * (dstHigh - dstLow) + dstLow;
    }

    public static function slerp(start:Number, end:Number, t:Number):Number {
        var theta:Number = Math.acos(Math.max(-1, Math.min(1, start * end))); // 确保 acos 参数在 [-1,1] 范围内
        var sinTheta:Number = Math.sin(theta);
        if (sinTheta == 0) return start;
        return (Math.sin((1 - t) * theta) / sinTheta) * start + (Math.sin(t * theta) / sinTheta) * end;
    }

    public static function cubic(t:Number, p0:Number, p1:Number, p2:Number, p3:Number):Number {
        var a0:Number = p3 - p2 - p0 + p1;
        var a1:Number = p0 - p1 - a0;
        var a2:Number = p2 - p0;
        var a3:Number = p1;
        return a0 * t * t * t + a1 * t * t + a2 * t + a3;
    }

    public static function hermite(t:Number, p0:Number, p1:Number, m0:Number, m1:Number):Number {
        var t2:Number = t * t;
        var t3:Number = t2 * t;
        return (2 * t3 - 3 * t2 + 1) * p0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * p1 + (t3 - t2) * m1;
    }

    public static function bezier(t:Number, p0:Number, p1:Number, p2:Number, p3:Number):Number {
        var u:Number = 1 - t;
        var tt:Number = t * t;
        var uu:Number = u * u;
        var uuu:Number = uu * u;
        var ttt:Number = tt * t;
        var result:Number = uuu * p0;
        result += 3 * uu * t * p1;
        result += 3 * u * tt * p2;
        result += ttt * p3;
        return result;
    }

    public static function easeInOut(t:Number):Number {
        return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
    }

    public static function bilinear(x:Number, y:Number, Q11:Number, Q12:Number, Q21:Number, Q22:Number, x1:Number, x2:Number, y1:Number, y2:Number):Number {
        var xWeight:Number = (x - x1) / (x2 - x1);
        var yWeight:Number = (y - y1) / (y2 - y1);
        var R1:Number = Q11 * (1 - xWeight) + Q21 * xWeight;
        var R2:Number = Q12 * (1 - xWeight) + Q22 * xWeight;
        return R1 * (1 - yWeight) + R2 * yWeight;
    }

    public static function bicubic(t:Number, p0:Number, p1:Number, p2:Number, p3:Number):Number {
        var a0:Number = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3;
        var a1:Number = p0 - 2.5 * p1 + 2 * p2 - 0.5 * p3;
        var a2:Number = -0.5 * p0 + 0.5 * p2;
        var a3:Number = p1;
        return a0 * t * t * t + a1 * t * t + a2 * t + a3;
    }

    public static function catmullRom(t:Number, p0:Number, p1:Number, p2:Number, p3:Number):Number {
        return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t);
    }

    public static function exponential(value:Number, base:Number):Number {
        return Math.pow(base, value) - 1;
    }

    public static function sine(t:Number):Number {
        return Math.sin(t * (Math.PI / 2));
    }

    public static function elastic(t:Number):Number {
        if (t == 0 || t == 1) return t; // 确保边界值
        var damping:Number = 0.3;
        return Math.pow(2, -10 * t) * Math.sin((t - damping / 4) * (2 * Math.PI) / damping) + 1;
    }

    public static function logarithmic(value:Number, base:Number):Number {
        return Math.log(value + 1) / Math.log(base);
    }

    public static function perlin(t:Number):Number {
        return t * t * (3 - 2 * t);
    }
}
