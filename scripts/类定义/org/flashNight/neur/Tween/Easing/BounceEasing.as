

import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * BounceEasing 弹跳效果缓动
 * 具有弹跳效果的缓动函数。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing.BounceEasing extends BaseEasing {
    /**
     * 构造函数
     * 
     * @param type 缓动类型：easeIn 或 easeOut
     */
    public function BounceEasing(type:String) {
        super(type || EASE_OUT);
    }
    
    /**
     * 弹跳效果缓动实现
     */
    public function ease(t:Number, b:Number, c:Number, d:Number):Number {
        switch(_type) {
            case EASE_IN:
                return c - easeOut(d - t, 0, c, d) + b;
            case EASE_OUT:
                return easeOut(t, b, c, d);
            case EASE_IN_OUT:
                if (t < d / 2) 
                    return (c - easeOut(d - (t * 2), 0, c, d) + b) * 0.5 + b;
                return easeOut(t * 2 - d, 0, c, d) * 0.5 + c * 0.5 + b;
            default:
                return easeOut(t, b, c, d); // 默认为easeOut
        }
    }
    
    /**
     * 弹跳效果easeOut实现（内部使用）
     */
    private function easeOut(t:Number, b:Number, c:Number, d:Number):Number {
        if ((t /= d) < (1 / 2.75)) {
            return c * (7.5625 * t * t) + b;
        } else if (t < (2 / 2.75)) {
            return c * (7.5625 * (t -= (1.5 / 2.75)) * t + .75) + b;
        } else if (t < (2.5 / 2.75)) {
            return c * (7.5625 * (t -= (2.25 / 2.75)) * t + .9375) + b;
        } else {
            return c * (7.5625 * (t -= (2.625 / 2.75)) * t + .984375) + b;
        }
    }
}