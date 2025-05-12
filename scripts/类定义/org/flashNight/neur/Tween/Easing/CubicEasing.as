

import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * CubicEasing 三次方缓动
 * 基于三次方的缓动函数。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing.CubicEasing extends BaseEasing {
    /**
     * 构造函数
     * 
     * @param type 缓动类型：easeIn, easeOut, 或 easeInOut
     */
    public function CubicEasing(type:String) {
        super(type || EASE_IN);
    }
    
    /**
     * 三次方缓动实现
     */
    public function ease(t:Number, b:Number, c:Number, d:Number):Number {
        switch(_type) {
            case EASE_IN:
                return c * (t /= d) * t * t + b;
            case EASE_OUT:
                return c * ((t = t / d - 1) * t * t + 1) + b;
            case EASE_IN_OUT:
                if ((t /= d / 2) < 1) return c / 2 * t * t * t + b;
                return c / 2 * ((t -= 2) * t * t + 2) + b;
            default:
                return c * (t /= d) * t * t + b; // 默认为easeIn
        }
    }
}