/**
 * GrenadeStatsBuilder - 手雷属性构建器
 * 
 * 职责：
 * - 构建手雷专属属性（威力等）
 * - 处理投掷武器的特殊显示逻辑
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 保持与原逻辑完全一致的输出
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.GrenadeStatsBuilder {

    /**
     * 构建手雷属性块
     *
     * 迁移自 TooltipTextBuilder.buildEquipmentStats Line 270-272 (case "手雷")
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 威力数值防护（Number() + isNaN() 守卫）
        var power:Number = Number(data.power);
        if (isNaN(power)) {
            power = 0;
        }

        // 只有威力非零时才显示
        if (power !== 0) {
            result.push(TooltipConstants.LBL_POWER, "：", power, "<BR>");
        }
    }
}
