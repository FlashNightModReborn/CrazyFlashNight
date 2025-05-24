
import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * BaseEasing 基类
 * 所有缓动函数实现的抽象基类。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.Easing.BaseEasing implements IEasing {
    /**
     * 缓动函数类型常量
     */
    public static var EASE_IN:String = "easeIn";
    public static var EASE_OUT:String = "easeOut";
    public static var EASE_IN_OUT:String = "easeInOut";
    public static var EASE_NONE:String = "easeNone";
    
    /**
     * 当前缓动类型
     */
    public var _type:String;
    
    /**
     * 构造函数
     * 
     * @param type 缓动类型，默认为easeOut
     */
    public function BaseEasing(type:String) {
        _type = type || EASE_OUT;
    }
    
    /**
     * 获取缓动类型
     */
    public function get type():String {
        return _type;
    }
    
    /**
     * 设置缓动类型
     */
    public function set type(value:String):Void {
        _type = value;
    }
    
    /**
     * 缓动函数实现
     * 子类必须重写此方法
     */
    public function ease(t:Number, b:Number, c:Number, d:Number):Number {
        return 0; // 基类默认实现，返回0，子类应该重写这个方法
    }
}