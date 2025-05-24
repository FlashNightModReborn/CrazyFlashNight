import org.flashNight.arki.component.Effect.*;
// 文件路径: org/flashNight/arki/component/Effect/BulletEffectHandler.as
class org.flashNight.arki.component.Effect.BulletEffectHandler {
    
    // 使用常量直接优化访问性能
    private static var BLOOD_EFFECT_MAP:Object = {
        飙血: "子弹碎片-飞血",
        异形飙血: "子弹碎片-异形飞血"
    };

    public static function createBulletEffect(
        hitTarget:Object,
        originX:Number,
        originY:Number,
        xscale:Number
    ):Void {
        var fragment:String = BLOOD_EFFECT_MAP[hitTarget.击中效果] || ""; // 直接属性访问+短路运算
        if (fragment.length) { // 利用长度检查排除空字符串
            EffectSystem.Effect(
                fragment, 
                originX, 
                originY, 
                xscale
            ).出血来源 = hitTarget._name;
        }
    }

    // 保留维护方法，必要时可动态维护表
    public static function registerEffect(key:String, value:String):Void {
        BLOOD_EFFECT_MAP[key] = value;
    }

    public static function unregisterEffect(key:String):Void {
        delete BLOOD_EFFECT_MAP[key];
    }
}
