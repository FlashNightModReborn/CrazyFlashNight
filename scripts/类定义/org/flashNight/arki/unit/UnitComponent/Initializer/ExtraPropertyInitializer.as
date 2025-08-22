/**
 * @class org.flashNight.arki.unit.UnitComponent.Initializer.ExtraPropertyInitializer
 * @desc
 * 属性附加初始器。读取单位的 extra 额外属性，按 set→add→muti 顺序应用：
 * - set：直接设置属性
 * - add：数值属性加减
 * - muti：数值属性乘除 
 * 应用后删除 extra 属性，避免哈希索引性能下降
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ExtraPropertyInitializer {
    
    /**
     * 初始化单位额外属性
     * @param target 目标单位 MovieClip
     */
    public static function initialize(target:MovieClip):Void {
        if (!target.extra) return;
        
        // _root.发布消息("[ExtraPropertyInitializer] 开始处理单位: " + target._name);
        
        var extra:Object = target.extra;
        
        // set: 直接设置属性
        if (extra.set) {
            // _root.发布消息("[ExtraPropertyInitializer] 处理set属性");
            for (var k:String in extra.set) {
                // _root.发布消息("[set] " + k + " = " + extra.set[k]);
                target[k] = extra.set[k];
            }
        }
        
        // add: 数值加减
        if (extra.add) {
            // _root.发布消息("[ExtraPropertyInitializer] 处理add属性");
            for (var k:String in extra.add) {
                var addVal:Number = Number(extra.add[k]);
                if (!isNaN(addVal)) {
                    var curVal:Number = Number(target[k]);
                    var newVal:Number = isNaN(curVal) ? addVal : curVal + addVal;
                    // _root.发布消息("[add] " + k + ": " + (isNaN(curVal) ? "undefined" : curVal) + " + " + addVal + " = " + newVal);
                    target[k] = newVal;
                }
            }
        }
        
        // muti: 数值乘除
        if (extra.muti) {
            // _root.发布消息("[ExtraPropertyInitializer] 处理muti属性");
            for (var k:String in extra.muti) {
                var factor:Number = Number(extra.muti[k]);
                if (!isNaN(factor)) {
                    var curVal:Number = Number(target[k]);
                    var newVal:Number = isNaN(curVal) ? factor : curVal * factor;
                    // _root.发布消息("[muti] " + k + ": " + (isNaN(curVal) ? "undefined" : curVal) + " * " + factor + " = " + newVal);
                    target[k] = newVal;
                }
            }
        }
        
        // 安全清理：删除 extra 属性，避免哈希索引性能下降
        delete target.extra;
        // _root.发布消息("[ExtraPropertyInitializer] 处理完成，已清理extra属性");
    }
}
