// org/flashNight/arki/component/Buff/IBuffCalculator.as
interface org.flashNight.arki.component.Buff.IBuffCalculator {
    /**
     * 添加数值修改
     * @param type 计算类型
     * @param value 数值
     * @param priority 优先级（影响计算顺序）
     */
    function addModification(type:String, value:Number):Void;
    
    /**
     * 计算最终结果
     * @param baseValue 基础值
     * @return 计算后的最终值
     */
    function calculate(baseValue:Number):Number;
    
    /**
     * 重置计算器
     */
    function reset():Void;
}