
import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * ElasticEasing 弹性效果缓动
 * 具有弹性效果的缓动函数。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing.ElasticEasing extends BaseEasing {
    /**
     * 弹性振幅
     */
    private var _amplitude:Number;
    
    /**
     * 弹性周期
     */
    private var _period:Number;
    
    /**
     * 构造函数
     * 
     * @param type 缓动类型：easeIn 或 easeOut
     * @param amplitude 振幅，如果为NaN则自动计算
     * @param period 周期，如果为NaN则自动计算为持续时间的0.3倍
     */
    public function ElasticEasing(type:String, amplitude:Number, period) {
        super(type || EASE_OUT);
        _amplitude = amplitude;
        _period = period;
    }
    
    /**
     * 设置振幅
     */
    public function set amplitude(value:Number):Void {
        _amplitude = value;
    }
    
    /**
     * 获取振幅
     */
    public function get amplitude():Number {
        return _amplitude;
    }
    
    /**
     * 设置周期
     */
    public function set period(value:Number):Void {
        _period = value;
    }
    
    /**
     * 获取周期
     */
    public function get period():Number {
        return _period;
    }
    
    /**
     * 弹性效果缓动实现
     */
    public function ease(t:Number, b:Number, c:Number, d:Number):Number {
        // 从参数中获取振幅和周期，如果提供了的话
        var a:Number = (arguments.length > 4) ? arguments[4] : _amplitude;
        var p:Number = (arguments.length > 5) ? arguments[5] : _period;
        
        if (t == 0) return b;
        if ((t /= d) == 1) return b + c;
        
        if (isNaN(p)) p = d * .3;
        var s:Number;
        
        if (isNaN(a) || a < Math.abs(c)) {
            a = c;
            s = p / 4;
        } else {
            s = p / (2 * Math.PI) * Math.asin(c / a);
        }
        
        switch(_type) {
            case EASE_IN:
                return -(a * Math.pow(2, 10 * (t -= 1)) * Math.sin((t * d - s) * (2 * Math.PI) / p)) + b;
            case EASE_OUT:
                return (a * Math.pow(2, -10 * t) * Math.sin((t * d - s) * (2 * Math.PI) / p) + c + b);
            case EASE_IN_OUT:
                if ((t /= d / 2) < 1) 
                    return -0.5 * (a * Math.pow(2, 10 * (t -= 1)) * Math.sin((t * d - s) * (2 * Math.PI) / p)) + b;
                return a * Math.pow(2, -10 * (t -= 1)) * Math.sin((t * d - s) * (2 * Math.PI) / p) * 0.5 + c + b;
            default:
                return (a * Math.pow(2, -10 * t) * Math.sin((t * d - s) * (2 * Math.PI) / p) + c + b); // 默认为easeOut
        }
    }
}