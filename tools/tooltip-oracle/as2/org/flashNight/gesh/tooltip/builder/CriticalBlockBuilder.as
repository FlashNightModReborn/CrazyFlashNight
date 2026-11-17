/**
 * CriticalBlockBuilder - 暴击块构建器
 * 
 * 职责：
 * - 构建暴击相关属性（暴击率/暴击伤害等）
 * - 迁移自原 quickBuildCriticalHit 逻辑
 * - 处理暴击增强值显示
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter 统一格式化
 * - 保持与原逻辑完全一致的输出
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.CriticalBlockBuilder {

    /**
     * 构建暴击属性块
     *
     * 迁移自 TooltipTextBuilder Line 326-330, 589-595
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 使用最终计算后的数据显示暴击（如果有mod或强化，则使用equipData）
        var critData:Object = equipData ? equipData : data;

        if (!critData.criticalhit) {
            return;
        }

        var criticalhit = critData.criticalhit;

        // 判断暴击类型并生成相应HTML
        if (!isNaN(Number(criticalhit))) {
            // 数值型暴击率
            result.push("<FONT COLOR='", TooltipConstants.COL_CRIT, "'>", TooltipConstants.LBL_CRIT, "：</FONT><FONT COLOR='", TooltipConstants.COL_CRIT, "'>", criticalhit, TooltipConstants.SUF_PERCENT, TooltipConstants.TIP_CRIT_CHANCE, "</FONT><BR>");
        } else if (criticalhit === TooltipConstants.TIP_CRIT_FULL_HP) {
            // 特殊暴击类型
            result.push("<FONT COLOR='", TooltipConstants.COL_CRIT, "'>", TooltipConstants.LBL_CRIT, "：", TooltipConstants.TIP_CRIT_FULL_HP_DESC, "</FONT><BR>");
        }
        // 其他情况不输出
    }
}
