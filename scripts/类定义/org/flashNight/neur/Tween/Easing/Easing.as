

import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * Easing 提供各种缓动函数，用于控制补间动画的速率变化。
 * 重构版：使用基于接口和类的组合方式
 * 
 * @org.flashNight.neur.Tween
 * @version 2.0
 */
class org.flashNight.neur.Tween.Easing.Easing {
    /**
     * 线性缓动，没有加速或减速
     */
    public static var Linear:Object = {
        easeNone: new LinearEasing(BaseEasing.EASE_NONE).ease,
        easeIn: new LinearEasing(BaseEasing.EASE_IN).ease,
        easeOut: new LinearEasing(BaseEasing.EASE_OUT).ease,
        easeInOut: new LinearEasing(BaseEasing.EASE_IN_OUT).ease
    };
    
    /**
     * 二次方缓动函数
     */
    public static var Quad:Object = {
        easeIn: new QuadEasing(BaseEasing.EASE_IN).ease,
        easeOut: new QuadEasing(BaseEasing.EASE_OUT).ease,
        easeInOut: new QuadEasing(BaseEasing.EASE_IN_OUT).ease
    };
    
    /**
     * 三次方缓动函数
     */
    public static var Cubic:Object = {
        easeIn: new CubicEasing(BaseEasing.EASE_IN).ease,
        easeOut: new CubicEasing(BaseEasing.EASE_OUT).ease,
        easeInOut: new CubicEasing(BaseEasing.EASE_IN_OUT).ease
    };
    
    /**
     * 回弹效果
     */
    public static var Back:Object = {
        easeIn: new BackEasing(BaseEasing.EASE_IN).ease,
        easeOut: new BackEasing(BaseEasing.EASE_OUT).ease,
        easeInOut: new BackEasing(BaseEasing.EASE_IN_OUT).ease
    };
    
    /**
     * 弹性效果
     */
    public static var Elastic:Object = {
        easeIn: new ElasticEasing(BaseEasing.EASE_IN).ease,
        easeOut: new ElasticEasing(BaseEasing.EASE_OUT).ease,
        easeInOut: new ElasticEasing(BaseEasing.EASE_IN_OUT).ease
    };
    
    /**
     * 弹跳效果
     */
    public static var Bounce:Object = {
        easeIn: new BounceEasing(BaseEasing.EASE_IN).ease,
        easeOut: new BounceEasing(BaseEasing.EASE_OUT).ease,
        easeInOut: new BounceEasing(BaseEasing.EASE_IN_OUT).ease
    };
    
    /**
     * 缓动函数类型映射
     */
    private static var _easingClassMap:Object = {
        linear: LinearEasing,
        quad: QuadEasing,
        cubic: CubicEasing,
        back: BackEasing,
        elastic: ElasticEasing,
        bounce: BounceEasing
    };
    
    /**
     * 获取指定类型的缓动函数实例
     * 
     * @param type 缓动类型（linear, quad, cubic, back, elastic, bounce）
     * @param easeType 缓动方式（easeIn, easeOut, easeInOut, easeNone）
     * @param params 额外参数，根据不同的缓动类型可能需要不同的参数
     * @return 缓动函数实例
     */
    public static function getEasing(type:String, easeType:String):IEasing {
        var easingClass:Function = _easingClassMap[type.toLowerCase()];
        if (!easingClass) {
            return new LinearEasing(); // 默认返回线性缓动
        }

        // 转换easeType字符串为BaseEasing中的常量
        var easingTypeConstant:String;
        easeType = (easeType == undefined || easeType == null) ? "easeOut" : easeType;

        switch (easeType) {
            case "easeIn":
                easingTypeConstant = BaseEasing.EASE_IN;
                break;
            case "easeOut":
                easingTypeConstant = BaseEasing.EASE_OUT;
                break;
            case "easeInOut":
                easingTypeConstant = BaseEasing.EASE_IN_OUT;
                break;
            case "easeNone":
                easingTypeConstant = BaseEasing.EASE_NONE;
                break;
            default:
                easingTypeConstant = BaseEasing.EASE_OUT;
        }

        // 提取附加参数（从第3个参数开始）
        var params:Array = [];
        for (var i:Number = 2; i < arguments.length; i++) {
            params.push(arguments[i]);
        }

        // 创建对应缓动函数实例
        switch (type.toLowerCase()) {
            case "back":
                return new BackEasing(easingTypeConstant, params.length > 0 ? params[0] : 1.70158);
            case "elastic":
                return new ElasticEasing(
                    easingTypeConstant,
                    params.length > 0 ? params[0] : NaN,
                    params.length > 1 ? params[1] : NaN
                );
            default:
                return new easingClass(easingTypeConstant);
        }
    }

    
    /**
     * 创建自定义缓动函数
     * 
     * @param easingFunction 自定义缓动函数
     * @return 包装后的缓动函数实例
     */
    public static function createCustomEasing(easingFunction:Function):IEasing {
        return new CustomEasing(easingFunction);
    }

    
    /**
     * 注册自定义缓动类型
     * 
     * @param name 自定义缓动类型名称
     * @param easingClass 缓动类的构造函数
     */
    public static function registerEasingType(name:String, easingClass:IEasing):Void {
        if (name && easingClass) {
            _easingClassMap[name.toLowerCase()] = easingClass;
        }
    }
}
