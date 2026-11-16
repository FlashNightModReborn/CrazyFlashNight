import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * DrugTooltipUtil - 药剂 Tooltip 工具函数
 *
 * 提供各构建器共用的工具函数。
 * 位于 gesh/tooltip 层，统一使用 TooltipConstants 中的常量。
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil {

    /** 帧率常量 */
    public static var FPS:Number = 30;

    /**
     * 帧数转秒数（保留一位小数，整数不显示小数）
     *
     * @param frames 帧数
     * @return String 秒数字符串
     */
    public static function framesToSeconds(frames:Number):String {
        if (isNaN(frames) || frames <= 0) return "0";

        var seconds:Number = frames / FPS;

        // 整数秒直接返回整数
        if (seconds == Math.floor(seconds)) {
            return String(Math.floor(seconds));
        }

        // 非整数保留一位小数
        return String(Math.round(seconds * 10) / 10);
    }

    /**
     * 格式化恢复值显示（支持百分比原样显示）
     *
     * @param value 原始值（可能是数字或百分比字符串）
     * @return String 格式化后的字符串
     */
    public static function formatValue(value):String {
        if (value == null || value == undefined) return "0";

        var strValue:String = String(value);
        // 百分比原样显示
        if (strValue.indexOf("%") >= 0) {
            return strValue;
        }

        var num:Number = Number(value);
        return isNaN(num) ? "0" : String(num);
    }

    /**
     * 生成炼金标记（仅当无炼金加成时显示）
     *
     * 设计理由：大多数药剂默认有炼金加成，无需每个都标注。
     * 只有当 scaleWithAlchemy=false 时才显示"无炼金"提示。
     *
     * @param scaleWithAlchemy 是否应用炼金加成
     * @return String 标记文本（有炼金加成时返回空字符串）
     */
    public static function alchemyTag(scaleWithAlchemy:Boolean):String {
        if (!scaleWithAlchemy) {
            return "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.LBL_DRUG_NO_ALCHEMY + "</FONT>";
        }
        return "";
    }

    /**
     * 颜色包装
     */
    public static function color(text:String, col:String):String {
        return "<FONT COLOR='" + col + "'>" + text + "</FONT>";
    }

    /**
     * 换行
     */
    public static function br():String {
        return "<BR>";
    }
}
