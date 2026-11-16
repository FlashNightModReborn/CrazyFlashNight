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
     * @param buffBuffer Array 可选；非 null 时把 Buff 与缓释移入该缓冲区，
     *        返回值只保留其他词条，null 保持旧版完整属性区
     * @return Array HTML 文本片段数组
     */
    public static function compose(item:Object, buffBuffer:Array):Array {
        if (!item || !item.data) return [];

        // 归一化 effects（使用业务层的共享归一化器）
        var effects:Array = DrugEffectNormalizer.normalize(item.data);

        if (effects.length == 0) {
            // 无 effects，返回空（旧逻辑已废弃）
            return [];
        }

        if (buffBuffer == null) return DrugTooltipRegistry.buildAll(effects);

        var main:Array = [];
        var buff:Array = [];
        for (var i:Number = 0; i < effects.length; i++) {
            var fragments:Array = DrugTooltipRegistry.buildOne(effects[i]);
            if (fragments == null || fragments.length == 0) continue;
            if (isBuffEffect(effects[i].type)) buff = buff.concat(fragments);
            else main = main.concat(fragments);
        }
        for (var j:Number = 0; j < buff.length; j++) buffBuffer.push(buff[j]);
        return main;
    }

    private static function isBuffEffect(type:String):Boolean {
        return type == "buff" || type == "toughnessBuff"
            || type == "resistanceBuff" || type == "regen";
    }
}
