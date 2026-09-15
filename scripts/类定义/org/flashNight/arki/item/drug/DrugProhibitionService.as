/**
 * DrugProhibitionService - 关卡禁药判定（唯一事实源）
 *
 * 设计契约：docs/战场即时补给品-技术调研与首批施工准备-2026-09-12.md §13 禁药段。
 * 限制系统 "DisableDrug" 条目生效中且物品属于被禁范围时，快捷用药
 * （DrugInputService.updateSlot）与背包直服（DrugInputService.consumeBackpackItem，
 * ItemUseService.executeConsume 亦委托于此）在药效/冷却/扣药任一权威写之前统一拒绝。
 *
 * 战场补给（use=战场补给）永不被禁：它走独立拾取路径，也进不了这两条用药事务（双保险）。
 */
class org.flashNight.arki.item.drug.DrugProhibitionService {

    /** 限制系统禁药词条键（关卡 XML 写法：<Limitation>DisableDrug</Limitation>） */
    public static var ENTRY_KEY:String = "DisableDrug";

    /** 禁药拦截提示文案（两个权威使用点共用） */
    public static var BLOCKED_MESSAGE:String = "本关卡禁止使用药剂！";

    /**
     * 某物品当前是否被禁药条目拦截。
     * 被禁范围：走快捷/背包两条药剂消耗路径的 use 值——全库药剂/食品/九龙物品的
     * use 均为 "药剂"，故判 "药剂" 一类；战场补给与其他用途一律不在范围内。
     */
    public static function isDrugUseBlocked(itemName:String):Boolean {
        if (_root.限制系统 == undefined) return false;
        if (_root.限制系统.entries == undefined
                || _root.限制系统.entries[ENTRY_KEY] !== true) return false;
        if (itemName == null || itemName.length == 0) return false;
        var itemData:Object = _root.getItemData(itemName);
        if (itemData == null) return false;
        return itemData.use == "药剂";
    }
}
