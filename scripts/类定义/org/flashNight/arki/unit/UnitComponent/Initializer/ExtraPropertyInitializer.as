/**
 * @class org.flashNight.arki.unit.UnitComponent.Initializer.ExtraPropertyInitializer
 * @desc
 * 属性附加初始器。读取单位的 extr 额外属性，按 set→add→muti 顺序应用：
 * - set：直接设置属性
 * - add：数值属性加减
 * - muti：数值属性乘除
 * 应用后删除 extr 属性，避免哈希索引性能下降
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ExtraPropertyInitializer {
    
    /**
     * 初始化单位额外属性
     * @param target 目标单位 MovieClip
     */
    public static function initialize(target:MovieClip):Void {
        if (!target.extr) return;
        
        var extr:Object = target.extr;
        
        // set: 直接设置属性
        if (extr.set) {
            for (var k:String in extr.set) {
                target[k] = extr.set[k];
            }
        }
        
        // add: 数值加减
        if (extr.add) {
            for (var k:String in extr.add) {
                var addVal:Number = Number(extr.add[k]);
                if (!isNaN(addVal)) {
                    var curVal:Number = Number(target[k]);
                    target[k] = isNaN(curVal) ? addVal : curVal + addVal;
                }
            }
        }
        
        // muti: 数值乘除
        if (extr.muti) {
            for (var k:String in extr.muti) {
                var factor:Number = Number(extr.muti[k]);
                if (!isNaN(factor)) {
                    var curVal:Number = Number(target[k]);
                    target[k] = isNaN(curVal) ? factor : curVal * factor;
                }
            }
        }
        
        // 安全清理：删除 extr 属性，避免哈希索引性能下降
        delete target.extr;
    }
}
