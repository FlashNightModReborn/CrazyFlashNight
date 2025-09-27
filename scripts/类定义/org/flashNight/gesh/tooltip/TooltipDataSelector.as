import org.flashNight.arki.item.*;

class org.flashNight.gesh.tooltip.TooltipDataSelector {
    public static function getEquipmentData(item:Object, tier:String):Object {
        if (tier == null) return item.data;
        var tierKey = EquipmentUtil.tierNameToKeyDict[tier];
        if (tierKey == null) return item.data;
        var tierData = item[tierKey];
        if(!tierData) tierData = EquipmentUtil.defaultTierDataDict[tier];
        if(tierData){
            for(var key in tierData){
                item.data[key] = tierData[key];
            }
        }
        return item.data;
    }
}