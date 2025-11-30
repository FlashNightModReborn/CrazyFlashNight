/**
 * DamageTypeBuilder - 伤害类型构建器
 * 
 * 职责：
 * - 构建伤害类型显示（物理/魔法/破击）
 * - 处理魔法伤害类型和破击类型
 * - 应用颜色标记
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter 统一格式化
 * - 保持与原逻辑完全一致的输出
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.component.Damage.MagicDamageTypes;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.DamageTypeBuilder {

    /**
     * 构建伤害类型块
     *
     * 迁移自 TooltipTextBuilder Line 343-345, 635-648
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 使用最终计算后的数据显示伤害类型（如果有mod或强化，则使用equipData）
        var finalData:Object = equipData ? equipData : data;

        if (!finalData.damagetype) {
            return;
        }

        if (finalData.damagetype == TooltipConstants.TXT_MAGIC && finalData.magictype) {
            TooltipFormatter.colorLine(result, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_ATTR + "：" + finalData.magictype);
        } else if (finalData.damagetype == TooltipConstants.TXT_BREAK && finalData.magictype) {
            if (MagicDamageTypes.isMagicDamageType(finalData.magictype)) {
                TooltipFormatter.colorLine(result, TooltipConstants.COL_BREAK_LIGHT, TooltipConstants.LBL_EXTRA_DAMAGE + "：" + finalData.magictype);
            } else {
                TooltipFormatter.colorLine(result, TooltipConstants.COL_BREAK_MAIN, TooltipConstants.LBL_BREAK_TYPE + "：" + finalData.magictype);
            }
        } else {
            TooltipFormatter.colorLine(result, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_TYPE + "：" + (finalData.damagetype == TooltipConstants.TXT_MAGIC ? TooltipConstants.TXT_ENERGY : finalData.damagetype));
        }
    }
}
