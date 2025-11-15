/**
 * SlayEffectBuilder - 斩杀效果构建器
 *
 * 职责：
 * - 构建斩杀线属性的显示文本
 * - 为斩杀线添加 "%血量" 后缀
 * - 处理配件和装备的斩杀线显示一致性
 *
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipConstants 统一格式化和后缀
 * - 保持与其他 builder 一致的接口风格
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.SlayEffectBuilder {

    /**
     * 构建斩杀线显示（用于配件的 flat 属性）
     *
     * 显示格式：斩杀线 + 8%血量
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param slayValue:Number 斩杀线数值
     * @return Void（直接修改 result）
     */
    public static function buildFlat(result:Array, slayValue:Number):Void {
        if (slayValue == null || slayValue == undefined) {
            return;
        }

        var n:Number = Number(slayValue);
        if (isNaN(n) || n === 0) {
            return;
        }

        var sign:String = " + ";
        if (n < 0) {
            n = -n;
            sign = " - ";
        }

        var label:String = TooltipConstants.PROPERTY_DICT["slay"];
        if (!label) label = "斩杀线";

        result.push(label, sign, n, TooltipConstants.SUF_BLOOD, "<BR>");
    }

    /**
     * 构建斩杀线显示（用于配件的 override 属性）
     *
     * 显示格式：斩杀线 -> 8%血量
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param slayValue:Number 斩杀线数值
     * @return Void（直接修改 result）
     */
    public static function buildOverride(result:Array, slayValue:Number):Void {
        if (slayValue == null || slayValue == undefined) {
            return;
        }

        var n:Number = Number(slayValue);
        if (isNaN(n)) {
            return;
        }

        var label:String = TooltipConstants.PROPERTY_DICT["slay"];
        if (!label) label = "斩杀线";

        result.push(label, " -> ", n, TooltipConstants.SUF_BLOOD, "<BR>");
    }

    /**
     * 获取斩杀效果的简短描述（用于配件列表等简略显示场景）
     *
     * @param slayValue:Number 斩杀值
     * @return String 简短描述文本（例如："8%斩杀"）
     */
    public static function getShortDescription(slayValue:Number):String {
        if (slayValue == null || slayValue == undefined) {
            return "";
        }

        var n:Number = Number(slayValue);
        if (isNaN(n) || n === 0) {
            return "";
        }

        return n + "%斩杀";
    }
}
