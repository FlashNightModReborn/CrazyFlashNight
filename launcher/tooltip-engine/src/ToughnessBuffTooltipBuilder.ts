// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/ToughnessBuffTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace ToughnessBuffTooltipBuilder {
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            var value: number = as2Number(effectData.value);
            if (as2IsNaN(value) || as2LessEqual(value, 0))
                return result;
            result.push(DrugTooltipUtil.color(ctx, TooltipConstants.LBL_DRUG_BUFF + "：", TooltipConstants.COL_HL));
            result.push("装备韧性 +" + value);
            var duration: number = as2Number(effectData.duration);
            if (!as2IsNaN(duration) && as2Greater(duration, 0)) {
                result.push("（" + DrugTooltipUtil.framesToSeconds(ctx, duration)
                    + TooltipConstants.TIP_DRUG_SECOND + "）");
            }
            result.push(DrugTooltipUtil.br(ctx));
            return result;
        }
    }
}
