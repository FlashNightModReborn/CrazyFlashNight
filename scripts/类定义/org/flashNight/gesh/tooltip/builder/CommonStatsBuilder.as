/**
 * CommonStatsBuilder - 通用属性构建器
 * 
 * 职责：
 * - 构建所有装备类型共享的通用属性
 * - 包含力量/伤害/精准/闪避/韧性/防御/HP/MP等
 * - 应用增强值显示（强化等级 > 1 时）
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter.upgradeLine 统一格式化
 * - 复用属性后缀常量
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.CommonStatsBuilder {

    /**
     * 构建通用属性块
     *
     * 迁移自 TooltipTextBuilder.buildEquipmentStats Line 320-408
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 力量/伤害相关
        TooltipFormatter.upgradeLine(result, data, equipData, "force", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "damage", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "punch", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "knifepower", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "gunpower", null, null);

        // 精准/闪避/韧性
        TooltipFormatter.upgradeLine(result, data, equipData, "accuracy", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "evasion", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "toughness", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "lazymiss", null, null);

        // 特殊属性
        TooltipFormatter.upgradeLine(result, data, equipData, "poison", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "vampirism", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "rout", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "slay", null, TooltipConstants.SUF_BLOOD);

        // 防御/HP/MP
        TooltipFormatter.upgradeLine(result, data, equipData, "defence", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "hp", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "mp", null, null);

        // 动作类型
        if (item.actiontype !== undefined) {
            result.push("动作：", item.actiontype, "<BR>");
        }
    }
}
