// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/DamageTypeBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace DamageTypeBuilder {
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, data?: any, equipData?: any): void {
            var baseDamageType: string = data ? data.damagetype : null;
            var baseMagicType: string = data ? data.magictype : null;
            var finalDamageType: string = equipData ? equipData.damagetype : baseDamageType;
            var finalMagicType: string = equipData ? equipData.magictype : baseMagicType;
            if (!finalDamageType) {
                return;
            }
            var hasOverride: boolean = as2NotEqual(equipData, null) && (as2NotEqual(finalDamageType, baseDamageType) || as2NotEqual(finalMagicType, baseMagicType));
            if (hasOverride) {
                buildWithOverride(ctx, result, baseDamageType, baseMagicType, finalDamageType, finalMagicType);
            }
            else {
                buildNormal(ctx, result, finalDamageType, finalMagicType);
            }
        }
        function buildNormal(ctx: Context, result?: any[], damageType?: string, magicType?: string): void {
            if (as2Equal(damageType, TooltipConstants.TXT_MAGIC) && magicType) {
                TooltipFormatter.colorLine(result, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_ATTR + "：" + magicType);
            }
            else if (as2Equal(damageType, TooltipConstants.TXT_BREAK) && magicType) {
                if (isMagicDamage(ctx, magicType)) {
                    TooltipFormatter.colorLine(result, TooltipConstants.COL_BREAK_LIGHT, TooltipConstants.LBL_EXTRA_DAMAGE + "：" + magicType);
                }
                else {
                    TooltipFormatter.colorLine(result, TooltipConstants.COL_BREAK_MAIN, TooltipConstants.LBL_BREAK_TYPE + "：" + magicType);
                }
            }
            else {
                TooltipFormatter.colorLine(result, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_TYPE + "：" + (as2Equal(damageType, TooltipConstants.TXT_MAGIC) ? TooltipConstants.TXT_ENERGY : damageType));
            }
        }
        function buildWithOverride(ctx: Context, result?: any[], baseDamageType?: string, baseMagicType?: string, finalDamageType?: string, finalMagicType?: string): void {
            var label: string;
            var color: string;
            var finalDisplay: string;
            if (as2Equal(finalDamageType, TooltipConstants.TXT_MAGIC) && finalMagicType) {
                label = TooltipConstants.LBL_DAMAGE_ATTR;
                color = TooltipConstants.COL_DMG;
                finalDisplay = finalMagicType;
            }
            else if (as2Equal(finalDamageType, TooltipConstants.TXT_BREAK) && finalMagicType) {
                if (isMagicDamage(ctx, finalMagicType)) {
                    label = TooltipConstants.LBL_EXTRA_DAMAGE;
                    color = TooltipConstants.COL_BREAK_LIGHT;
                }
                else {
                    label = TooltipConstants.LBL_BREAK_TYPE;
                    color = TooltipConstants.COL_BREAK_MAIN;
                }
                finalDisplay = finalMagicType;
            }
            else {
                label = TooltipConstants.LBL_DAMAGE_TYPE;
                color = TooltipConstants.COL_DMG;
                finalDisplay = (as2Equal(finalDamageType, TooltipConstants.TXT_MAGIC) ? TooltipConstants.TXT_ENERGY : finalDamageType);
            }
            var baseDisplay: string = getTypeDisplayString(ctx, baseDamageType, baseMagicType);
            result.push("<FONT COLOR='", color, "'>", label, "：</FONT>");
            result.push("<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalDisplay, "</FONT>");
            result.push(" <FONT COLOR='", TooltipConstants.COL_INFO, "'>(←", baseDisplay, ")</FONT><BR>");
        }
        function getTypeDisplayString(ctx: Context, damageType?: string, magicType?: string): string {
            if (!damageType) {
                return TooltipConstants.TXT_NONE;
            }
            if (as2Equal(damageType, TooltipConstants.TXT_MAGIC)) {
                if (magicType) {
                    return TooltipConstants.LBL_DAMAGE_ATTR + ":" + magicType;
                }
                return TooltipConstants.TXT_ENERGY;
            }
            if (as2Equal(damageType, TooltipConstants.TXT_BREAK)) {
                if (magicType) {
                    if (isMagicDamage(ctx, magicType)) {
                        return TooltipConstants.LBL_EXTRA_DAMAGE + ":" + magicType;
                    }
                    else {
                        return TooltipConstants.LBL_BREAK_TYPE + ":" + magicType;
                    }
                }
                return TooltipConstants.TXT_BREAK;
            }
            return damageType;
        }
    }
}
