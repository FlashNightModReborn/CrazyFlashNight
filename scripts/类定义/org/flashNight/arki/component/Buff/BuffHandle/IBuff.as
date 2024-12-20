interface org.flashNight.arki.component.Buff.BuffHandle.IBuff {
    /**
     * Buff 的类型标志
     */
    function getType():String;

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

    
    /**
     * 判断 Buff 是否为 POD 类型
     * @return true
     */
    function isPOD():Boolean;
}
