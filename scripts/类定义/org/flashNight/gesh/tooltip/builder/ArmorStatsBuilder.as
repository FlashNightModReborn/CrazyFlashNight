/**
 * ArmorStatsBuilder - 护甲属性构建器
 * 
 * 职责：
 * - 构建护甲/防具属性（防御/HP/MP等）
 * - 处理基础属性显示
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

class org.flashNight.gesh.tooltip.builder.ArmorStatsBuilder {

    /**
     * 构建护甲属性块
     *
     * 护甲/防具的专属属性显示被整合到 CommonStatsBuilder 中，
     * 因为防御/HP/MP 是所有装备类型的通用属性。
     *
     * 如果将来需要为防具添加专属属性（如护甲等级、防护类型等），
     * 可以在此方法中实现。
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 当前实现：防具没有独特的专属属性
        // 防御/HP/MP 等属性已在 CommonStatsBuilder 中统一处理
        // 如果未来需要添加防具特有属性，可在此实现
    }
}
