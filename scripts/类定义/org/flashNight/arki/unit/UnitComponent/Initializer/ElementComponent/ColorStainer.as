import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
/**
 * 染色处理组件 - 负责处理地图元件的颜色染色功能
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ColorStainer {
    
    // 默认颜色参数
    private static var DEFAULT_MULTIPLIER:Number = 1;
    private static var DEFAULT_OFFSET:Number = 0;
    
    /**
     * 为目标应用染色效果
     * @param target 要染色的目标MovieClip
     */
    public static function applyStaining(target:MovieClip):Void {
        if (!ColorStainer.hasStainTarget(target)) {
            return;
        }
        
        // 初始化色彩参数
        ColorStainer.initializeColorParameters(target);
        
        // 应用色彩设置
        ColorStainer.applyColorTransform(target);
    }
    
    /**
     * 检查目标是否有染色目标设置
     * @param target 要检查的目标MovieClip
     * @return Boolean 如果有染色目标返回true
     */
    public static function hasStainTarget(target:MovieClip):Boolean {
        return target.stainedTarget && target[target.stainedTarget];
    }
    
    /**
     * 初始化颜色参数，为未设置的参数设置默认值
     * @param target 要初始化的目标MovieClip
     */
    private static function initializeColorParameters(target:MovieClip):Void {
        // 初始化乘数参数
        target.redMultiplier = ColorStainer.validateNumber(target.redMultiplier, DEFAULT_MULTIPLIER);
        target.greenMultiplier = ColorStainer.validateNumber(target.greenMultiplier, DEFAULT_MULTIPLIER);
        target.blueMultiplier = ColorStainer.validateNumber(target.blueMultiplier, DEFAULT_MULTIPLIER);
        target.alphaMultiplier = ColorStainer.validateNumber(target.alphaMultiplier, DEFAULT_MULTIPLIER);
        
        // 初始化偏移参数
        target.redOffset = ColorStainer.validateNumber(target.redOffset, DEFAULT_OFFSET);
        target.greenOffset = ColorStainer.validateNumber(target.greenOffset, DEFAULT_OFFSET);
        target.blueOffset = ColorStainer.validateNumber(target.blueOffset, DEFAULT_OFFSET);
        target.alphaOffset = ColorStainer.validateNumber(target.alphaOffset, DEFAULT_OFFSET);
    }
    
    /**
     * 应用颜色变换
     * @param target 要应用颜色变换的目标MovieClip
     */
    private static function applyColorTransform(target:MovieClip):Void {
        var stainedObject:MovieClip = target[target.stainedTarget];
        
        if (_root.设置色彩) {
            _root.设置色彩(
                stainedObject,
                target.redMultiplier,
                target.greenMultiplier,
                target.blueMultiplier,
                target.redOffset,
                target.greenOffset,
                target.blueOffset,
                target.alphaMultiplier,
                target.alphaOffset
            );
        }
    }
    
    /**
     * 验证数字参数，如果无效则返回默认值
     * @param value 要验证的值
     * @param defaultValue 默认值
     * @return Number 有效的数字值
     */
    private static function validateNumber(value:Number, defaultValue:Number):Number {
        return isNaN(value) ? defaultValue : value;
    }
    
    /**
     * 重置目标的颜色参数为默认值
     * @param target 要重置的目标MovieClip
     */
    public static function resetColorParameters(target:MovieClip):Void {
        target.redMultiplier = DEFAULT_MULTIPLIER;
        target.greenMultiplier = DEFAULT_MULTIPLIER;
        target.blueMultiplier = DEFAULT_MULTIPLIER;
        target.alphaMultiplier = DEFAULT_MULTIPLIER;
        
        target.redOffset = DEFAULT_OFFSET;
        target.greenOffset = DEFAULT_OFFSET;
        target.blueOffset = DEFAULT_OFFSET;
        target.alphaOffset = DEFAULT_OFFSET;
    }
    
    /**
     * 获取目标的颜色参数
     * @param target 要获取参数的目标MovieClip
     * @return Object 包含所有颜色参数的对象
     */
    public static function getColorParameters(target:MovieClip):Object {
        return {
            redMultiplier: target.redMultiplier || DEFAULT_MULTIPLIER,
            greenMultiplier: target.greenMultiplier || DEFAULT_MULTIPLIER,
            blueMultiplier: target.blueMultiplier || DEFAULT_MULTIPLIER,
            alphaMultiplier: target.alphaMultiplier || DEFAULT_MULTIPLIER,
            redOffset: target.redOffset || DEFAULT_OFFSET,
            greenOffset: target.greenOffset || DEFAULT_OFFSET,
            blueOffset: target.blueOffset || DEFAULT_OFFSET,
            alphaOffset: target.alphaOffset || DEFAULT_OFFSET
        };
    }
}