import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;

/**
 * 数量随机化组件 - 负责为地图元件设置随机数量
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.QuantityRandomizer {
    
    /**
     * 为目标设置随机数量
     * @param target 要设置的目标MovieClip
     */
    public static function randomizeQuantity(target:MovieClip):Void {
        // 检查是否设置了数量范围
        if (!QuantityRandomizer.hasQuantityRange(target)) {
            return;
        }
        
        // 计算随机数量
        var minQuantity:Number = target.数量_min;
        var maxQuantity:Number = target.数量_max;
        var randomRange:Number = maxQuantity - minQuantity + 1;
        
        target.数量 = minQuantity + random(randomRange);
    }
    
    /**
     * 检查目标是否设置了有效的数量范围
     * @param target 要检查的目标MovieClip
     * @return Boolean 如果有有效数量范围返回true
     */
    public static function hasQuantityRange(target:MovieClip):Boolean {
        return target.数量_min > 0 && target.数量_max > 0 && target.数量_max >= target.数量_min;
    }
    
    /**
     * 获取目标的数量范围信息
     * @param target 要检查的目标MovieClip
     * @return Object 包含min、max和range的对象，如果无效则返回null
     */
    public static function getQuantityRange(target:MovieClip):Object {
        if (!QuantityRandomizer.hasQuantityRange(target)) {
            return null;
        }
        
        return {
            min: target.数量_min,
            max: target.数量_max,
            range: target.数量_max - target.数量_min + 1
        };
    }
}