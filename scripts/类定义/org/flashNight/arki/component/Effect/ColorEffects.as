/**
 * ColorEffects.as (ActionScript 2)
 * 位于：org.flashNight.arki.component.Effect
 *
 * 本类提供一系列静态方法，用于操作 MovieClip 的色彩变换。
 * 采用中文文档注释，同时在 setColor 方法中增加了性能优化：
 * 当所有新的变换值与当前值一致时，将跳过更新操作。
 *
 * 用法示例：
 *   import org.flashNight.arki.component.Effect.ColorEffects;
 *   ColorEffects.redEffect(myClip, 50);
 */
import flash.geom.ColorTransform;

class org.flashNight.arki.component.Effect.ColorEffects {

    /**
     * 设置色彩
     * 动态调整目标 MovieClip 的各通道 multiplier 与 offset 值
     *
     * @param target     要改变色彩变换的 MovieClip 对象
     * @param rMul       红色乘数，NaN 表示保持原值
     * @param gMul       绿色乘数，NaN 表示保持原值
     * @param bMul       蓝色乘数，NaN 表示保持原值
     * @param rOff       红色偏移，NaN 表示保持原值
     * @param gOff       绿色偏移，NaN 表示保持原值
     * @param bOff       蓝色偏移，NaN 表示保持原值
     * @param alphaMul   透明度乘数，NaN 表示保持原值
     * @param alphaOff   透明度偏移，NaN 表示保持原值
     */
    public static function setColor(target:MovieClip, 
                                    rMul:Number, gMul:Number, bMul:Number, 
                                    rOff:Number, gOff:Number, bOff:Number, 
                                    alphaMul:Number, alphaOff:Number):Void {
        // 获取当前的色彩变换
        var ct:ColorTransform = target.transform.colorTransform;
        
        // 计算新的 multiplier 与 offset 值（若参数为 NaN，则保留现有值）
        var newRedMul:Number   = (isNaN(rMul)) ? ct.redMultiplier : rMul;
        var newGreenMul:Number = (isNaN(gMul)) ? ct.greenMultiplier : gMul;
        var newBlueMul:Number  = (isNaN(bMul)) ? ct.blueMultiplier : bMul;
        var newAlphaMul:Number = (isNaN(alphaMul)) ? ct.alphaMultiplier : alphaMul;
        
        var newRedOff:Number   = (isNaN(rOff)) ? ct.redOffset : rOff;
        var newGreenOff:Number = (isNaN(gOff)) ? ct.greenOffset : gOff;
        var newBlueOff:Number  = (isNaN(bOff)) ? ct.blueOffset : bOff;
        var newAlphaOff:Number = (isNaN(alphaOff)) ? ct.alphaOffset : alphaOff;
        
        // 性能优化：若所有新值与当前值一致，则直接返回，避免重复赋值
        if (ct.redMultiplier   == newRedMul &&
            ct.greenMultiplier == newGreenMul &&
            ct.blueMultiplier  == newBlueMul &&
            ct.alphaMultiplier == newAlphaMul &&
            ct.redOffset       == newRedOff &&
            ct.greenOffset     == newGreenOff &&
            ct.blueOffset      == newBlueOff &&
            ct.alphaOffset     == newAlphaOff) {
            return;
        }
        
        // 更新色彩变换对象的各属性
        ct.redMultiplier   = newRedMul;
        ct.greenMultiplier = newGreenMul;
        ct.blueMultiplier  = newBlueMul;
        ct.alphaMultiplier = newAlphaMul;
        
        ct.redOffset   = newRedOff;
        ct.greenOffset = newGreenOff;
        ct.blueOffset  = newBlueOff;
        ct.alphaOffset = newAlphaOff;
        
        // 应用更新后的色彩变换
        target.transform.colorTransform = ct;
    }
    
    /**
     * 重置色彩
     * 将 MovieClip 的颜色通道恢复为默认状态
     *
     * @param target 要重置色彩的 MovieClip 对象
     */
    public static function resetColor(target:MovieClip):Void {
        setColor(target, 1, 1, 1, 0, 0, 0, 1, 0);
    }
    
    /**
     * 重置透明度
     * 仅将透明度相关值重置为默认状态
     *
     * @param target 要重置透明度的 MovieClip 对象
     */
    public static function resetAlpha(target:MovieClip):Void {
        setColor(target, NaN, NaN, NaN, NaN, NaN, NaN, 1, 0);
    }
    
    /**
     * 红化色彩
     * 使 MovieClip 呈现红色效果，通过降低绿色和蓝色偏移实现
     *
     * @param target    要应用红化效果的 MovieClip 对象
     * @param intensity 红化强度，默认值为 75
     */
    public static function redEffect(target:MovieClip, intensity:Number):Void {
        if (isNaN(intensity)) intensity = 75;
        setColor(target, NaN, NaN, NaN, NaN, -intensity, -intensity, NaN, NaN);
    }
    
    /**
     * 受击色彩
     * 模拟受击效果，稍微降低颜色通道的偏移量
     *
     * @param target 要应用受击效果的 MovieClip 对象
     */
    public static function hitEffect(target:MovieClip):Void {
        setColor(target, NaN, NaN, NaN, -10, -40, -40, NaN, NaN);
    }
    
    /**
     * 亮化色彩
     * 提高 MovieClip 的亮度，通过增加各颜色通道的偏移量实现
     *
     * @param target 要亮化的 MovieClip 对象
     * @param amount 亮化强度，默认值为 75
     */
    public static function lightenColor(target:MovieClip, amount:Number):Void {
        if (isNaN(amount)) amount = 75;
        setColor(target, NaN, NaN, NaN, amount, amount, amount, NaN, NaN);
    }
    
    /**
     * 暗化色彩
     * 降低 MovieClip 的亮度，通过减少各颜色通道的偏移量实现
     *
     * @param target 要暗化的 MovieClip 对象
     * @param amount 暗化强度，默认值为 75
     */
    public static function darkenColor(target:MovieClip, amount:Number):Void {
        if (isNaN(amount)) amount = 75;
        setColor(target, NaN, NaN, NaN, -amount, -amount, -amount, NaN, NaN);
    }
    
    /**
     * 透明色彩
     * 调整 MovieClip 的透明度偏移
     *
     * @param target         要调整透明效果的 MovieClip 对象
     * @param alphaIntensity 透明强度，默认值为 75
     */
    public static function alphaColor(target:MovieClip, alphaIntensity:Number):Void {
        if (isNaN(alphaIntensity)) alphaIntensity = 75;
        setColor(target, NaN, NaN, NaN, NaN, NaN, NaN, NaN, -alphaIntensity);
    }
}
