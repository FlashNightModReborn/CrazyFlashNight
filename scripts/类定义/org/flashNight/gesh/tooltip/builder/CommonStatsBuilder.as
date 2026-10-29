/**
 * CommonStatsBuilder - 通用属性构建器
 * 
 * 职责：
 * - 构建所有装备类型共享的通用属性
 * - 包含力量/伤害/精准/闪避/韧性/防御/HP/MP等
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
import org.flashNight.gesh.tooltip.ItemUseTypes;

class org.flashNight.gesh.tooltip.builder.CommonStatsBuilder {

    /** 需要显示动作类型的装备use类型 */
    private static var ACTION_TYPE_USES:Object = {
        刀: true,
        手部装备: true
    };

    /**
     * 构建通用属性块
     *
     * 迁移自 TooltipTextBuilder.buildEquipmentStats Line 320-408
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @param nativeOpt:Object 原生注释可选开关（nativeOpt.omitCritSlay 为 true 时
     *   斩杀行写入 nativeOpt.critSlay 缓冲区）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object, nativeOpt:Object):Void {
        // 斩杀行可与暴击行一起移入子注释框（原生路径），默认仍留在通用属性块
        var slayTarget:Array = result;
        if (nativeOpt != null && nativeOpt.omitCritSlay === true && nativeOpt.critSlay != null) {
            slayTarget = nativeOpt.critSlay;
        }

        // 力量/伤害相关
        TooltipFormatter.upgradeLine(result, data, equipData, "force", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "damage", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "punch", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "knifepower", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "gunpower", null, null);

        // 精准/闪避/韧性
        TooltipFormatter.upgradeLine(result, data, equipData, "accuracy", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "evasion", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "toughness", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "lazymiss", null, null);

        // 特殊属性
        TooltipFormatter.upgradeLine(result, data, equipData, "poison", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "vampirism", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(result, data, equipData, "rout", null, TooltipConstants.SUF_PERCENT);
        TooltipFormatter.upgradeLine(slayTarget, data, equipData, "slay", null, TooltipConstants.SUF_BLOOD);

        // 防御/HP/MP
        TooltipFormatter.upgradeLine(result, data, equipData, "defence", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "hp", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "mp", null, null);

        // 动作类型（优先显示计算后的actiontype，支持插件覆盖）
        // 仅对刀和手部装备显示动作类型
        if (ACTION_TYPE_USES[item.use] === true) {
            var finalActionType:String = null;
            var originalActionType:String = item.actiontype;

            // 从 baseItem.getData() 获取计算后的 actiontype
            if (baseItem && baseItem.getData != undefined) {
                var calculatedData:Object = baseItem.getData();
                if (calculatedData && calculatedData.actiontype !== undefined) {
                    finalActionType = calculatedData.actiontype;
                }
            }

            // 如果没有计算后的值，使用原始值
            if (finalActionType == null) {
                finalActionType = originalActionType;
            }

            // 如果仍然没有值，显示"默认"
            if (finalActionType === undefined) {
                finalActionType = "默认";
            }

            // 检查是否被插件覆盖
            var isOverridden:Boolean = (originalActionType !== undefined && finalActionType != originalActionType);

            if (isOverridden) {
                // 显示覆盖效果：新值（原值 → 新值）
                result.push(TooltipConstants.LBL_ACTION, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalActionType, "</FONT>");
                result.push(" <FONT COLOR='", TooltipConstants.COL_INFO, "'>(←", originalActionType, ")</FONT><BR>");
            } else {
                result.push(TooltipConstants.LBL_ACTION, "：", finalActionType, "<BR>");
            }
        }
    }
}
