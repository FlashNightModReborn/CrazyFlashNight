/**
 * IDrugEffect - 药剂效果词条接口
 *
 * 所有药剂效果词条必须实现此接口。
 * 每个词条负责一种特定类型的效果（如恢复、buff、净化等）。
 *
 * @author FlashNight
 * @version 1.0
 */
interface org.flashNight.arki.item.drug.IDrugEffect {

    /**
     * 执行词条效果
     *
     * @param context DrugContext 执行上下文，包含目标、炼金等级等信息
     * @param effectData Object 词条配置数据（来自XML的effect节点）
     * @return Boolean 是否执行成功
     */
    function execute(context:Object, effectData:Object):Boolean;

    /**
     * 获取词条类型标识
     * 用于注册表匹配
     *
     * @return String 类型标识（如"heal", "buff", "purify"等）
     */
    function getType():String;
}
