
import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * 缓动函数工厂类
 * 提供便捷方法创建各种类型的缓动函数。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing.EasingFactory {
    /**
     * 创建线性缓动
     */
    public static function createLinear():IEasing {
        return new LinearEasing();
    }
    
    /**
     * 创建二次方缓动
     * 
     * @param type 缓动类型
     */
    public static function createQuad(type:String = BaseEasing.EASE_OUT):IEasing {
        return new QuadEasing(type);
    }
    
    /**
     * 创建三次方缓动
     * 
     * @param type 缓动类型
     */
    public static function createCubic(type:String = BaseEasing.EASE_OUT):IEasing {
        return new CubicEasing(type);
    }
    
    /**
     * 创建回弹效果缓动
     * 
     * @param type 缓动类型
     * @param overshoot 回弹系数
     */
    public static function createBack(type:String = BaseEasing.EASE_OUT, overshoot:Number = 1.70158):IEasing {
        return new BackEasing(type, overshoot);
    }
    
    /**
     * 创建弹性效果缓动
     * 
     * @param type 缓动类型
     * @param amplitude 振幅
     * @param period 周期
     */
    public static function createElastic(type:String = BaseEasing.EASE_OUT, amplitude:Number = NaN, period:Number = NaN):IEasing {
        return new ElasticEasing(type, amplitude, period);
    }
    
    /**
     * 创建弹跳效果缓动
     * 
     * @param type 缓动类型
     */
    public static function createBounce(type:String = BaseEasing.EASE_OUT):IEasing {
        return new BounceEasing(type);
    }
}