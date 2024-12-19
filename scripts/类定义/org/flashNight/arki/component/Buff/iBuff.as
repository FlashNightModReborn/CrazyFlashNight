// org/flashNight/gesh/property/iBuff.as
class org.flashNight.arki.component.Buff.iBuff {
    /**
     * 应用 buff 到一个值
     * @param value 原始值
     * @return 修改后的值
     */
    public function apply(value:Number):Number {
        // 子类需实现
        return value;
    }
    
    /**
     * 使 buff 的缓存失效
     */
    public function invalidate():Void {
        // 子类需实现
    }
}
