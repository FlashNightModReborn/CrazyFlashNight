import org.flashNight.arki.item.drug.DrugEffectNormalizer;
import org.flashNight.arki.item.drug.tooltip.DrugTooltipRegistry;

/**
 * DrugTooltipComposer - 药剂 Tooltip 组合器
 *
 * 入口函数，从 item 数据生成完整的药剂属性 Tooltip。
 * 替代 TooltipTextBuilder.buildDrugStats 的旧逻辑。
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.tooltip.DrugTooltipComposer {

    /**
     * 构建药剂属性 Tooltip
     *
     * @param item Object 物品数据对象
     * @return Array HTML 文本片段数组
     */
    public static function compose(item:Object):Array {
        if (!item || !item.data) return [];

        // 归一化 effects
        var effects:Array = DrugEffectNormalizer.normalize(item.data);

        if (effects.length == 0) {
            // 无 effects，返回空（旧逻辑已废弃）
            return [];
        }

        // 使用 Registry 构建所有词条的 Tooltip
        return DrugTooltipRegistry.buildAll(effects);
    }
}
