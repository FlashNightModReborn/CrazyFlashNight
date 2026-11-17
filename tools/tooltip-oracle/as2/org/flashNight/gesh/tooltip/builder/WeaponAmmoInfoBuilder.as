import org.flashNight.gesh.tooltip.TooltipConstants;

/** 最终装备数据中的条件配额；只用于弹容行，不读取或初始化玩家弹药状态。 */
class org.flashNight.gesh.tooltip.builder.WeaponAmmoInfoBuilder {
    private static function quota(value):Number {
        var n:Number = Number(value);
        return n > 0 && isFinite(n) ? Math.min(2, Math.floor(n)) : 0;
    }

    public static function capacitySuffix(data:Object):String {
        var capacity:Number = Math.floor(Number(data.capacity));
        if (!(capacity > 0) || !isFinite(capacity)) return "";
        var config:Object = data.overload;
        var chamber:Number = quota(config.chamber);
        var ghost:Number = quota(config.ghost);
        if (ghost > 0) ghost = Math.max(ghost, quota(config.ghostLimit));
        var result:String = "";
        if (chamber > 0) result += colored(chamber, TooltipConstants.COL_AMMO_CHAMBER);
        if (ghost > 0) result += colored(ghost, TooltipConstants.COL_AMMO_GHOST);
        if (config.reward) result += colored(capacity, TooltipConstants.COL_AMMO_REWARD);
        return result;
    }

    private static function colored(amount:Number, color:String):String {
        return " <FONT COLOR='" + color + "'>+" + amount + "</FONT>";
    }

    /** merge 抬高已有资格的上限，与原生值取较高值。 */
    public static function appendMerge(result:Array, config:Object, indent:String):Void {
        var limit:Number = quota(config.ghostLimit);
        if (limit == 0) return;
        result.push(indent, "<font color='", TooltipConstants.COL_HL, "'>", TooltipConstants.TAG_MERGE,
            "</font> ", TooltipConstants.LBL_GHOST_LIMIT, " → ", limit,
            "发（需原生支持及冲击连携，不累加）。<BR>");
    }
}
