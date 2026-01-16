import org.flashNight.arki.item.drug.DrugEffectNormalizer;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipRegistry;

/**
 * DrugTooltipComposer - 药剂 Tooltip 组合器
 *
 * 入口函数，从 item 数据生成完整的药剂属性 Tooltip。
 * 替代 TooltipTextBuilder.buildDrugStats 的旧逻辑。
 *
 * 职责边界：
 * - 本类位于 gesh/tooltip 显示层
 * - 依赖 arki/item/drug/DrugEffectNormalizer 进行数据归一化
 * - 委托 DrugTooltipRegistry 进行具体构建
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.DrugTooltipComposer {

    /**
     * 构建药剂属性 Tooltip
     *
     * @param item Object 物品数据对象
     * @return Array HTML 文本片段数组
     */
    public static function compose(item:Object):Array {
        if (!item || !item.data) return [];

        // 归一化 effects（使用业务层的共享归一化器）
        var effects:Array = DrugEffectNormalizer.normalize(item.data);

        if (effects.length == 0) {
            // 无 effects，返回空（旧逻辑已废弃）
            return [];
        }

        // 使用 Registry 构建所有词条的 Tooltip
        return DrugTooltipRegistry.buildAll(effects);
    }
}
