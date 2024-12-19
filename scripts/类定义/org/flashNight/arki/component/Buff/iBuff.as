// org/flashNight/arki/component/Buff/IBuff.as
interface org.flashNight.arki.component.Buff.IBuff {
    /**
     * 应用 buff 到一个值
     * @param value 原始值
     * @return 修改后的值
     */
    function apply(value:Number):Number;
    
    /**
     * 使 buff 的缓存失效
     */
    function invalidate():Void;
}
