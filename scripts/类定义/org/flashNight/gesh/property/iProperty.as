// org/flashNight/gesh/property/iProperty.as
interface org.flashNight.gesh.property.iProperty {
    /**
     * 获取属性值
     * @return 属性值
     */
    public function get():Number
    
    /**
     * 设置属性值
     * @param newVal 新值
     */
    public function set(newVal:Number):Void
    /**
     * 使缓存失效
     */
    public function invalidate():Void
}