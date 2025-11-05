/**
 * EquipmentStatsComposer - 装备属性编排器
 * 
 * 职责：
 * - 编排装备属性构建流程
 * - 根据装备类型（枪械/近战/护甲）分发到专门构建器
 * - 组合各类属性块（暴击/抗性/配件等）
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 零 UI 访问：不直接访问 _root 或 UI 元素
 * - 输出一致性：保持与原 buildEquipmentStats 完全相同的 HTML 输出
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.ItemUseTypes;
import org.flashNight.gesh.tooltip.builder.MeleeStatsBuilder;
import org.flashNight.gesh.tooltip.builder.GrenadeStatsBuilder;
import org.flashNight.gesh.tooltip.builder.GunStatsBuilder;
import org.flashNight.gesh.tooltip.builder.CommonStatsBuilder;
import org.flashNight.gesh.tooltip.builder.CriticalBlockBuilder;
import org.flashNight.gesh.tooltip.builder.DamageTypeBuilder;
import org.flashNight.gesh.tooltip.builder.ResistanceBlockBuilder;
import org.flashNight.gesh.tooltip.builder.ModsBlockBuilder;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.EquipmentStatsComposer {

    /**
     * 编排装备属性构建流程
     *
     * 完整重现 TooltipTextBuilder.buildEquipmentStats 的逻辑（Line 254-426）
     *
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据（来自 TooltipDataSelector）
     * @param equipData:Object 强化/配件数据（可选，upgradeLevel > 1 或有 mods 时提供）
     * @return Array<String> 装备属性 HTML 片段数组
     */
    public static function compose(baseItem:BaseItem, item:Object, data:Object, equipData:Object):Array {
        var result:Array = [];
        var value = baseItem.value ? baseItem.value : 1;

        // 1. 通用属性：level 和 weight
        TooltipFormatter.upgradeLine(result, data, equipData, "level", null, null);
        TooltipFormatter.upgradeLine(result, data, equipData, "weight", null, TooltipConstants.SUF_KG);

        // 2. 根据 item.use 分发到专门构建器
        switch (item.use) {
            case ItemUseTypes.MELEE:
                MeleeStatsBuilder.build(result, baseItem, item, data, equipData);
                break;
            case ItemUseTypes.GRENADE:
                GrenadeStatsBuilder.build(result, baseItem, item, data, equipData);
                break;
            case ItemUseTypes.RIFLE:
            case ItemUseTypes.PISTOL:
                GunStatsBuilder.build(result, baseItem, item, data, equipData);
                break;
        }

        // 3. 通用属性块（力量/伤害/精准/闪避/韧性/防御/HP/MP等）
        CommonStatsBuilder.build(result, baseItem, item, data, equipData);

        // 4. 暴击块
        CriticalBlockBuilder.build(result, baseItem, item, data, equipData);

        // 5. 伤害类型块
        DamageTypeBuilder.build(result, baseItem, item, data, equipData);

        // 6. 抗性块
        ResistanceBlockBuilder.build(result, baseItem, item, data, equipData);

        // 7. 配件列表块
        ModsBlockBuilder.build(result, baseItem, item, value);

        return result;
    }
}
