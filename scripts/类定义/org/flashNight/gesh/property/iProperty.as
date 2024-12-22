// org/flashNight/gesh/property/IProperty.as
interface org.flashNight.gesh.property.IProperty {
    /**
     * 获取属性值
     * @return 属性值
     */
    function get();
    
    /**
     * 设置属性值
     * @param newVal 新值
     */
    function set(newVal):Void;
    
    /**
     * 使缓存失效
     */
    function invalidate():Void;
}
