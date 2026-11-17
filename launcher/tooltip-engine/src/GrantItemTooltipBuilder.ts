// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/GrantItemTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace GrantItemTooltipBuilder {
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            var name: string = effectData.name;
            var count: number = as2Number(effectData.count);
            var chance: number = as2Number(effectData.chance);
            var spoiler: boolean = effectData.tooltipSpoiler === true || effectData.tooltipSpoiler === "true";
            if (!name)
                return result;
            if (as2IsNaN(count) || as2LessEqual(count, 0))
                count = 1;
            if (as2IsNaN(chance) || as2LessEqual(chance, 0) || as2Greater(chance, 1))
                chance = 1;
            if (spoiler) {
                result.push(DrugTooltipUtil.color(ctx, TooltipConstants.LBL_DRUG_GRANT + "：", TooltipConstants.COL_HL));
                result.push(name);
                if (as2Greater(count, 1)) {
                    result.push(" x" + count);
                }
                if (as2Less(chance, 1)) {
                    result.push("（" + Math.round(chance * 100) + "%" + TooltipConstants.TIP_DRUG_CHANCE + "）");
                }
            }
            else {
                result.push(DrugTooltipUtil.color(ctx, TooltipConstants.LBL_DRUG_GRANT_HIDDEN, TooltipConstants.COL_INFO));
            }
            result.push(DrugTooltipUtil.br(ctx));
            return result;
        }
    }
}
