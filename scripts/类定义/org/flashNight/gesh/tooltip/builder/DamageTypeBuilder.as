/**
 * DamageTypeBuilder - 伤害类型构建器
 *
 * 职责：
 * - 构建伤害类型显示（物理/魔法/破击）
 * - 处理魔法伤害类型和破击类型
 * - 显示配件覆盖效果（从无到有、类型切换、内部覆盖）
 * - 应用颜色标记
 *
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter 统一格式化
 * - 支持多种覆盖场景的显示
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.component.Damage.MagicDamageTypes;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.DamageTypeBuilder {

    /**
     * 构建伤害类型块
     *
     * 迁移自 TooltipTextBuilder Line 343-345, 635-648
     * 增强：支持配件覆盖效果显示
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 基础装备数据（不含配件）
     * @param equipData:Object 强化/配件数据（可选，包含配件修改后的最终数据）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 获取基础值和最终值
        var baseDamageType:String = data ? data.damagetype : null;
        var baseMagicType:String = data ? data.magictype : null;
        var finalDamageType:String = equipData ? equipData.damagetype : baseDamageType;
        var finalMagicType:String = equipData ? equipData.magictype : baseMagicType;

        // 如果最终没有伤害类型，则不显示
        if (!finalDamageType) {
            return;
        }

        // 检查是否有覆盖
        var hasOverride:Boolean = equipData != null && (
            finalDamageType != baseDamageType ||
            finalMagicType != baseMagicType
        );

        if (hasOverride) {
            // 有配件覆盖，显示覆盖效果
            buildWithOverride(result, baseDamageType, baseMagicType, finalDamageType, finalMagicType);
        } else {
            // 无覆盖，正常显示
            buildNormal(result, finalDamageType, finalMagicType);
        }
    }

    /**
     * 正常显示伤害类型（无覆盖）
     */
    private static function buildNormal(result:Array, damageType:String, magicType:String):Void {
        if (damageType == TooltipConstants.TXT_MAGIC && magicType) {
            TooltipFormatter.colorLine(result, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_ATTR + "：" + magicType);
        } else if (damageType == TooltipConstants.TXT_BREAK && magicType) {
            if (MagicDamageTypes.isMagicDamageType(magicType)) {
                TooltipFormatter.colorLine(result, TooltipConstants.COL_BREAK_LIGHT, TooltipConstants.LBL_EXTRA_DAMAGE + "：" + magicType);
            } else {
                TooltipFormatter.colorLine(result, TooltipConstants.COL_BREAK_MAIN, TooltipConstants.LBL_BREAK_TYPE + "：" + magicType);
            }
        } else {
            TooltipFormatter.colorLine(result, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_TYPE + "：" + (damageType == TooltipConstants.TXT_MAGIC ? TooltipConstants.TXT_ENERGY : damageType));
        }
    }

    /**
     * 显示带覆盖效果的伤害类型
     *
     * 覆盖场景：
     * 1. 无 → 魔法/破击（从无到有）
     * 2. 魔法 → 破击 / 破击 → 魔法（类型切换）
     * 3. 魔法A → 魔法B / 破击A → 破击B（内部覆盖）
     */
    private static function buildWithOverride(result:Array, baseDamageType:String, baseMagicType:String,
                                               finalDamageType:String, finalMagicType:String):Void {
        // 获取最终显示的标签和颜色
        var label:String;
        var color:String;
        var finalDisplay:String;

        if (finalDamageType == TooltipConstants.TXT_MAGIC && finalMagicType) {
            label = TooltipConstants.LBL_DAMAGE_ATTR;
            color = TooltipConstants.COL_DMG;
            finalDisplay = finalMagicType;
        } else if (finalDamageType == TooltipConstants.TXT_BREAK && finalMagicType) {
            if (MagicDamageTypes.isMagicDamageType(finalMagicType)) {
                label = TooltipConstants.LBL_EXTRA_DAMAGE;
                color = TooltipConstants.COL_BREAK_LIGHT;
            } else {
                label = TooltipConstants.LBL_BREAK_TYPE;
                color = TooltipConstants.COL_BREAK_MAIN;
            }
            finalDisplay = finalMagicType;
        } else {
            label = TooltipConstants.LBL_DAMAGE_TYPE;
            color = TooltipConstants.COL_DMG;
            finalDisplay = (finalDamageType == TooltipConstants.TXT_MAGIC ? TooltipConstants.TXT_ENERGY : finalDamageType);
        }

        // 构建原始值显示
        var baseDisplay:String = getTypeDisplayString(baseDamageType, baseMagicType);

        // 输出带覆盖标记的行
        result.push("<FONT COLOR='", color, "'>", label, "：</FONT>");
        result.push("<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalDisplay, "</FONT>");
        result.push(" <FONT COLOR='", TooltipConstants.COL_INFO, "'>(", baseDisplay, " → ", finalDisplay, ")</FONT><BR>");
    }

    /**
     * 获取伤害类型的显示字符串
     *
     * 使用正确的标签：
     * - 魔法伤害 → "伤害属性：X"
     * - 破击（魔法类型） → "附加伤害：X"
     * - 破击（非魔法类型） → "破击类型：X"
     *
     * @param damageType:String 伤害类型（魔法/破击/物理等）
     * @param magicType:String 具体类型（热/冷/生化等）
     * @return String 显示字符串
     */
    private static function getTypeDisplayString(damageType:String, magicType:String):String {
        if (!damageType) {
            return TooltipConstants.TXT_NONE;
        }

        if (damageType == TooltipConstants.TXT_MAGIC) {
            if (magicType) {
                // 魔法伤害：使用 "伤害属性" 标签
                return TooltipConstants.LBL_DAMAGE_ATTR + ":" + magicType;
            }
            return TooltipConstants.TXT_ENERGY;
        }

        if (damageType == TooltipConstants.TXT_BREAK) {
            if (magicType) {
                // 破击：根据 magicType 是否为魔法伤害类型来区分标签
                if (MagicDamageTypes.isMagicDamageType(magicType)) {
                    return TooltipConstants.LBL_EXTRA_DAMAGE + ":" + magicType;
                } else {
                    return TooltipConstants.LBL_BREAK_TYPE + ":" + magicType;
                }
            }
            return TooltipConstants.TXT_BREAK;
        }

        return damageType;
    }
}
