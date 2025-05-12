/**
 * Easing 提供各种缓动函数，用于控制补间动画的速率变化。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing {
    
    /**
     * 线性缓动，没有加速或减速
     */
    public static var Linear:Object = {
        easeNone: function(t:Number, b:Number, c:Number, d:Number):Number {
            return c * t / d + b;
        },
        easeIn: function(t:Number, b:Number, c:Number, d:Number):Number {
            return c * t / d + b;
        },
        easeOut: function(t:Number, b:Number, c:Number, d:Number):Number {
            return c * t / d + b;
        },
        easeInOut: function(t:Number, b:Number, c:Number, d:Number):Number {
            return c * t / d + b;
        }
    };
    
    /**
     * 二次方缓动函数
     */
    public static var Quad:Object = {
        easeIn: function(t:Number, b:Number, c:Number, d:Number):Number {
            return c * (t /= d) * t + b;
        },
        easeOut: function(t:Number, b:Number, c:Number, d:Number):Number {
            return -c * (t /= d) * (t - 2) + b;
        },
        easeInOut: function(t:Number, b:Number, c:Number, d:Number):Number {
            if ((t /= d / 2) < 1) return c / 2 * t * t + b;
            return -c / 2 * ((--t) * (t - 2) - 1) + b;
        }
    };
    
    /**
     * 三次方缓动函数
     */
    public static var Cubic:Object = {
        easeIn: function(t:Number, b:Number, c:Number, d:Number):Number {
            return c * (t /= d) * t * t + b;
        },
        easeOut: function(t:Number, b:Number, c:Number, d:Number):Number {
            return c * ((t = t / d - 1) * t * t + 1) + b;
        },
        easeInOut: function(t:Number, b:Number, c:Number, d:Number):Number {
            if ((t /= d / 2) < 1) return c / 2 * t * t * t + b;
            return c / 2 * ((t -= 2) * t * t + 2) + b;
        }
    };
    
    /**
     * 回弹效果
     */
    public static var Back:Object = {
        easeIn: function(t:Number, b:Number, c:Number, d:Number, s:Number):Number {
            if (s == undefined) s = 1.70158;
            return c * (t /= d) * t * ((s + 1) * t - s) + b;
        },
        easeOut: function(t:Number, b:Number, c:Number, d:Number, s:Number):Number {
            if (s == undefined) s = 1.70158;
            return c * ((t = t / d - 1) * t * ((s + 1) * t + s) + 1) + b;
        },
        easeInOut: function(t:Number, b:Number, c:Number, d:Number, s:Number):Number {
            if (s == undefined) s = 1.70158;
            if ((t /= d / 2) < 1) return c / 2 * (t * t * (((s *= (1.525)) + 1) * t - s)) + b;
            return c / 2 * ((t -= 2) * t * (((s *= (1.525)) + 1) * t + s) + 2) + b;
        }
    };
    
    /**
     * 弹性效果
     */
    public static var Elastic:Object = {
        easeOut: function(t:Number, b:Number, c:Number, d:Number, a:Number, p:Number):Number {
            if (t == 0) return b;
            if ((t /= d) == 1) return b + c;
            if (!p) p = d * .3;
            var s:Number;
            if (!a || a < Math.abs(c)) {
                a = c;
                s = p / 4;
            } else {
                s = p / (2 * Math.PI) * Math.asin(c / a);
            }
            return (a * Math.pow(2, -10 * t) * Math.sin((t * d - s) * (2 * Math.PI) / p) + c + b);
        },
        easeIn: function(t:Number, b:Number, c:Number, d:Number, a:Number, p:Number):Number {
            if (t == 0) return b;
            if ((t /= d) == 1) return b + c;
            if (!p) p = d * .3;
            var s:Number;
            if (!a || a < Math.abs(c)) {
                a = c;
                s = p / 4;
            } else {
                s = p / (2 * Math.PI) * Math.asin(c / a);
            }
            return -(a * Math.pow(2, 10 * (t -= 1)) * Math.sin((t * d - s) * (2 * Math.PI) / p)) + b;
        }
    };
    
    /**
     * 弹跳效果
     */
    public static var Bounce:Object = {
        easeOut: function(t:Number, b:Number, c:Number, d:Number):Number {
            if ((t /= d) < (1 / 2.75)) {
                return c * (7.5625 * t * t) + b;
            } else if (t < (2 / 2.75)) {
                return c * (7.5625 * (t -= (1.5 / 2.75)) * t + .75) + b;
            } else if (t < (2.5 / 2.75)) {
                return c * (7.5625 * (t -= (2.25 / 2.75)) * t + .9375) + b;
            } else {
                return c * (7.5625 * (t -= (2.625 / 2.75)) * t + .984375) + b;
            }
        },
        easeIn: function(t:Number, b:Number, c:Number, d:Number):Number {
            return c - Bounce.easeOut(d - t, 0, c, d) + b;
        }
    };
}