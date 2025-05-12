
import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * LinearEasing 线性缓动
 * 无加速或减速效果的线性缓动函数。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing.LinearEasing extends BaseEasing {
    /**
     * 构造函数
     * 
     * @param type 缓动类型，对于线性缓动没有实际影响，所有类型的效果相同
     */
    public function LinearEasing(type:String) {
        super(type || EASE_NONE);
    }
    
    /**
     * 线性缓动实现
     * 所有类型（easeIn, easeOut, easeInOut, easeNone）的实现都相同
     */
    public function ease(t:Number, b:Number, c:Number, d:Number):Number {
        return c * t / d + b; // 线性缓动公式
    }
}