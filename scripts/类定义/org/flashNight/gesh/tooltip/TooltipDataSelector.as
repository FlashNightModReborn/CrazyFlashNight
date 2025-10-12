import org.flashNight.arki.item.*;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.tooltip.TooltipDataSelector {
    public static function getEquipmentData(item:Object, tier:String):Object {
        if (tier == null) return item.data;
        var tierKey = EquipmentUtil.tierNameToKeyDict[tier];
        if (tierKey == null) return item.data;
        var tierData = item[tierKey];
        if(!tierData) tierData = EquipmentUtil.defaultTierDataDict[tier];
        if(tierData){
            for(var key in tierData){
                if (ObjectUtil.isInternalKey(key)) continue; // 跳过内部字段（如 __dictUID）
                item.data[key] = tierData[key];
            }
        }
        return item.data;
    }
}