/**
 * ModsBlockBuilder - 配件列表构建器
 * 
 * 职责：
 * - 构建配件列表显示
 * - 使用 EquipmentUtil.modDict 获取配件信息
 * - 处理配件 tagValue 显示
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter 统一格式化
 * - 保持与原逻辑完全一致的输出
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder;

class org.flashNight.gesh.tooltip.builder.ModsBlockBuilder {

    /**
     * 构建配件列表块
     *
     * 迁移自 TooltipTextBuilder.buildEquipmentStats Line 412-423
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param value:Object 物品数值对象（包含 mods 数组）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, value:Object):Void {
        // 检查是否有配件
        if (!value.mods || value.mods.length <= 0) {
            return;
        }

        // 标题行
        result.push("<font color='" + TooltipConstants.COL_HL + "'>已安装", value.mods.length, "个配件：</font><BR>");

        // 迭代配件列表
        for (var i:Number = 0; i < value.mods.length; i++) {
            var modName:String = value.mods[i];
            if (!modName) continue; // 跳过空配件名

            var modInfo:Object = EquipmentUtil.modDict[modName];

            // 构建配件显示文本
            result.push("  • ", modName);

            // 检查是否有 tagValue
            if (modInfo && modInfo.tagValue) {
                result.push(" <font color='" + TooltipConstants.COL_INFO + "'>[", modInfo.tagValue, "]</font>");
            }

            // 显示配件提供的百分比增幅（汇总显示）
            if (modInfo && modInfo.stats && modInfo.stats.percentage) {
                var enhancements:Array = [];
                var percentage:Object = modInfo.stats.percentage;

                // 收集所有百分比属性
                for (var prop:String in percentage) {
                    var percentValue:Number = Number(percentage[prop]);
                    if (!isNaN(percentValue) && percentValue != 0) {
                        var sign:String = percentValue > 0 ? "+" : "";
                        var percent:Number = Math.round(percentValue * 100);
                        enhancements.push(sign + percent + "%");
                    }
                }

                // 如果有增幅，显示在配件名后
                if (enhancements.length > 0) {
                    result.push(" <font color='" + TooltipConstants.COL_ENHANCE + "'>(", enhancements.join(", "), ")</font>");
                }
            }

            // 检查是否有消音属性，添加消音效果简短描述
            if (modInfo && modInfo.override && modInfo.override.silence) {
                var silenceDesc:String = SilenceEffectBuilder.getShortDescription(modInfo.override.silence);
                if (silenceDesc != "") {
                    result.push(" <font color='" + TooltipConstants.COL_SILENCE + "'>[", silenceDesc, "]</font>");
                }
            }

            result.push("<BR>");
        }
    }
}
