
import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * QuadEasing 二次方缓动
 * 基于二次方的缓动函数。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing.QuadEasing extends BaseEasing {
    /**
     * 构造函数
     * 
     * @param type 缓动类型：easeIn, easeOut, 或 easeInOut
     */
    public function QuadEasing(type:String) {
        super(type || EASE_IN);
    }
    
    /**
     * 二次方缓动实现
     */
    public function ease(t:Number, b:Number, c:Number, d:Number):Number {
        switch(_type) {
            case EASE_IN:
                return c * (t /= d) * t + b;
            case EASE_OUT:
                return -c * (t /= d) * (t - 2) + b;
            case EASE_IN_OUT:
                if ((t /= d / 2) < 1) return c / 2 * t * t + b;
                return -c / 2 * ((--t) * (t - 2) - 1) + b;
            default:
                return c * (t /= d) * t + b; // 默认为easeIn
        }
    }
}