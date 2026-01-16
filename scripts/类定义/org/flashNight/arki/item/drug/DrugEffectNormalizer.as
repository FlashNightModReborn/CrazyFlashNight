/**
 * DrugEffectNormalizer - 药剂效果归一化工具
 *
 * 将 XML 解析后的各种 effects 结构统一为 Array<Object> 格式。
 * 供"使用药剂"和"Tooltip系统"共用，确保解析逻辑一致。
 *
 * XMLParser 解析 <effects><effect>...</effect></effects> 时可能返回：
 * 1. {effect: [...]}  多个effect时
 * 2. {effect: {...}}  单个effect时
 * 3. [...]            直接数组（取决于XMLParser配置）
 * 4. {...}            单个对象
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.DrugEffectNormalizer {

    /**
     * 归一化 effects 数据
     *
     * @param drugData 药剂数据对象（item.data）
     * @return Array 归一化后的 effects 数组，无效时返回空数组
     */
    public static function normalize(drugData:Object):Array {
        if (!drugData) return [];

        var effectsNode = drugData.effects;
        if (effectsNode == null || effectsNode == undefined) {
            return [];
        }

        var effects:Array = null;

        // 检查是否是 {effect: ...} 结构
        if (effectsNode.effect != undefined) {
            effects = effectsNode.effect;
        } else if (effectsNode instanceof Array) {
            effects = effectsNode;
        } else {
            // 可能是单个effect对象
            effects = [effectsNode];
        }

        // 确保effects是数组
        if (effects != null && !(effects instanceof Array)) {
            effects = [effects];
        }

        return effects || [];
    }

    /**
     * 检查药剂数据是否有有效的 effects
     *
     * @param drugData 药剂数据对象
     * @return Boolean 是否有有效的 effects
     */
    public static function hasEffects(drugData:Object):Boolean {
        var effects:Array = normalize(drugData);
        return effects.length > 0;
    }
}
