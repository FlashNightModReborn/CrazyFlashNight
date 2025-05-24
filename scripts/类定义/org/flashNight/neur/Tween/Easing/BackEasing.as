import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * BackEasing 回弹效果缓动
 * 具有回弹效果的缓动函数。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing.BackEasing extends BaseEasing {
    /**
     * 默认回弹系数
     */
    private var _s:Number = 1.70158;
    
    /**
     * 构造函数
     * 
     * @param type 缓动类型：easeIn, easeOut, 或 easeInOut
     * @param s 回弹系数，默认为1.70158
     */
    public function BackEasing(type:String, s:Number) {
        super(type || EASE_IN);
        _s = isNaN(s) ? s : 1.70158;
    }
    
    /**
     * 设置回弹系数
     */
    public function set overshoot(value:Number):Void {
        _s = value;
    }
    
    /**
     * 获取回弹系数
     */
    public function get overshoot():Number {
        return _s;
    }
    
    /**
     * 回弹效果缓动实现
     */
    public function ease(t:Number, b:Number, c:Number, d:Number) {
        // 如果提供了参数，使用参数作为回弹系数
        var s:Number = (arguments.length > 4) ? arguments[4] : _s;
        
        switch(_type) {
            case EASE_IN:
                return c * (t /= d) * t * ((s + 1) * t - s) + b;
            case EASE_OUT:
                return c * ((t = t / d - 1) * t * ((s + 1) * t + s) + 1) + b;
            case EASE_IN_OUT:
                if ((t /= d / 2) < 1) return c / 2 * (t * t * (((s *= (1.525)) + 1) * t - s)) + b;
                return c / 2 * ((t -= 2) * t * (((s *= (1.525)) + 1) * t + s) + 2) + b;
            default:
                return c * (t /= d) * t * ((s + 1) * t - s) + b; // 默认为easeIn
        }
    }
}
