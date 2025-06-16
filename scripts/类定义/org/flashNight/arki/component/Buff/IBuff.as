import org.flashNight.arki.component.Buff.*;
// org/flashNight/arki/component/Buff/IBuff.as
interface org.flashNight.arki.component.Buff.IBuff {
    /**
     * 应用Buff效果 - 策略模式核心方法
     * @param calculator 计算器，负责收集和应用数值修改
     * @param context 上下文信息，包含目标对象、当前属性等
     */
    function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void;
    
    /**
     * 获取Buff唯一标识
     */
    function getId():String;
    
    /**
     * 获取Buff类型（用于调试和UI显示）
     */
    function getType():String;
    
    /**
     * 检查Buff是否仍然有效
     */
    function isActive():Boolean;
    
    /**
     * 销毁Buff，清理资源
     */
    function destroy():Void;
}
