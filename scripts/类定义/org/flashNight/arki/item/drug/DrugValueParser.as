/**
 * DrugValueParser - 药剂数值解析工具类
 *
 * 提供通用的数值解析功能，支持绝对值和百分比格式。
 *
 * 使用示例:
 *   var hp:Number = DrugValueParser.parse(effectData.hp, target.hp满血值);
 *   // "150" => 150
 *   // "50%" => Math.floor(hp满血值 * 0.5)
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.DrugValueParser {

    /**
     * 解析恢复值（支持百分比）
     *
     * @param raw      原始值（可能是数字、字符串数字或百分比字符串）
     * @param maxValue 百分比计算的基准值（如hp满血值、mp满血值）
     * @return Number  解析后的数值
     *
     * 示例:
     *   parse(150, 1000)    => 150
     *   parse("150", 1000)  => 150
     *   parse("50%", 1000)  => 500  (50% of 1000)
     *   parse("0.5%", 1000) => 5    (0.5% of 1000)
     *   parse(null, 1000)   => 0
     *   parse("abc", 1000)  => 0
     */
    public static function parse(raw, maxValue:Number):Number {
        if (raw == null || raw == undefined) return 0;

        var strValue:String = String(raw);
        if (strValue.indexOf("%") >= 0) {
            // 百分比恢复
            var percent:Number = parseFloat(strValue.replace("%", ""));
            if (isNaN(percent)) return 0;
            return Math.floor(maxValue * percent / 100);
        } else {
            var num:Number = Number(raw);
            return isNaN(num) ? 0 : num;
        }
    }

    /**
     * 解析百分比值（返回0-1范围的系数）
     *
     * @param raw 原始值（可能是数字或百分比字符串）
     * @return Number 0-1范围的系数
     *
     * 示例:
     *   parsePercent("50%")  => 0.5
     *   parsePercent(0.3)    => 0.3
     *   parsePercent("0.3")  => 0.3
     *   parsePercent(null)   => 0
     */
    public static function parsePercent(raw):Number {
        if (raw == null || raw == undefined) return 0;

        var strValue:String = String(raw);
        if (strValue.indexOf("%") >= 0) {
            var percent:Number = parseFloat(strValue.replace("%", ""));
            if (isNaN(percent)) return 0;
            return percent / 100;
        } else {
            var num:Number = Number(raw);
            return isNaN(num) ? 0 : num;
        }
    }

    /**
     * 检查值是否为百分比格式
     *
     * @param raw 原始值
     * @return Boolean 是否为百分比格式
     */
    public static function isPercent(raw):Boolean {
        if (raw == null || raw == undefined) return false;
        return String(raw).indexOf("%") >= 0;
    }
}
