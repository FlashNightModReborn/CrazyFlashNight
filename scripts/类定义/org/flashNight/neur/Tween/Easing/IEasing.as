
import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * IEasing 接口
 * 定义所有缓动函数必须实现的方法。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
interface org.flashNight.neur.Tween.Easing.IEasing {
    /**
     * 缓动函数的核心方法
     * 
     * @param t 当前时间（当前步骤）
     * @param b 起始值
     * @param c 变化量（结束值 - 起始值）
     * @param d 持续时间（总步骤数）
     * @param args 可选参数，根据不同的缓动类型可能需要不同的参数
     * @return 当前时间下的补间值
     */
    function ease(t:Number, b:Number, c:Number, d:Number):Number;
}