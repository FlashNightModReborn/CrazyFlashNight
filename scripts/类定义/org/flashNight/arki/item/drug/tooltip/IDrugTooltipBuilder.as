/**
 * IDrugTooltipBuilder - 药剂词条 Tooltip 构建器接口
 *
 * 每种词条类型实现此接口，将 effectData 转换为 Tooltip 文本片段。
 *
 * @author FlashNight
 * @version 1.0
 */
interface org.flashNight.arki.item.drug.tooltip.IDrugTooltipBuilder {

    /**
     * 获取此构建器处理的词条类型
     *
     * @return String 词条类型（如 "heal", "regen", "state"）
     */
    function getType():String;

    /**
     * 构建 Tooltip 文本
     *
     * @param effectData Object 词条配置数据（来自 XML）
     * @return Array HTML 文本片段数组（直接 concat 到结果中）
     */
    function build(effectData:Object):Array;
}
