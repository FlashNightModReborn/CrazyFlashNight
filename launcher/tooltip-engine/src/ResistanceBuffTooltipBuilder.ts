// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/ResistanceBuffTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace ResistanceBuffTooltipBuilder {
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            var rawValue: number = (as2Equal(effectData.value, undefined) || as2Equal(effectData.value, ""))
                ? NaN : as2Number(effectData.value);
            var value: number = NaN;
            if (!as2IsNaN(rawValue) && as2NotEqual(rawValue, 0))
                value = rawValue;
            var rawMult: number = (as2Equal(effectData.mult_positive, undefined) || as2Equal(effectData.mult_positive, ""))
                ? NaN : as2Number(effectData.mult_positive);
            var mult: number = NaN;
            if (!as2IsNaN(rawMult) && as2NotEqual(rawMult, 1))
                mult = rawMult;
            if (as2IsNaN(value) && as2IsNaN(mult))
                return result;
            var duration: number = as2Number(effectData.duration);
            var durationSuffix: string = "";
            if (!as2IsNaN(duration) && as2Greater(duration, 0)) {
                durationSuffix = "（" + DrugTooltipUtil.framesToSeconds(ctx, duration)
                    + TooltipConstants.TIP_DRUG_SECOND + "）";
            }
            var label: string = DrugTooltipUtil.color(ctx, TooltipConstants.LBL_DRUG_BUFF + "：", TooltipConstants.COL_HL);
            var property: string = effectData.property;
            var baseName: string = "全属性抗性 ";
            if (property && as2Greater(property.length, 0)) {
                var displayName: string = (as2Equal(property, TooltipConstants.TXT_BASE))
                    ? TooltipConstants.TXT_ENERGY : property;
                baseName = displayName + TooltipConstants.SUF_RESISTANCE + " ";
            }
            if (!as2IsNaN(mult)) {
                result.push(label);
                result.push(baseName + "×" + mult);
                result.push(durationSuffix);
                result.push(DrugTooltipUtil.br(ctx));
            }
            if (!as2IsNaN(value)) {
                result.push(label);
                result.push(baseName + (as2Greater(value, 0) ? "+" : "") + value);
                result.push(durationSuffix);
                result.push(DrugTooltipUtil.br(ctx));
            }
            return result;
        }
    }
}
