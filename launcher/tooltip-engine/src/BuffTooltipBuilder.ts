// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/BuffTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace BuffTooltipBuilder {
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            var property: string = effectData.property;
            var calc: string = effectData.calc;
            var value: number = as2Number(effectData.value);
            var duration: number = as2Number(effectData.duration);
            if (!property || !calc || as2IsNaN(value))
                return result;
            var valueStr: string;
            switch (calc.toLowerCase()) {
                case "add":
                    valueStr = (as2GreaterEqual(value, 0) ? "+" : "") + value;
                    break;
                case "multiply":
                    valueStr = "×" + value;
                    break;
                case "percent":
                    var percentValue: number = value * 100;
                    valueStr = (as2GreaterEqual(percentValue, 0) ? "+" : "") + percentValue + "%";
                    break;
                case "override":
                    valueStr = "=" + value;
                    break;
                case "max":
                    valueStr = "≥" + value;
                    break;
                case "min":
                    valueStr = "≤" + value;
                    break;
                default:
                    valueStr = String(value);
            }
            result.push(DrugTooltipUtil.color(ctx, TooltipConstants.LBL_DRUG_BUFF + "：", TooltipConstants.COL_HL));
            result.push(property + " " + valueStr);
            if (!as2IsNaN(duration) && as2Greater(duration, 0)) {
                var durationSec: string = DrugTooltipUtil.framesToSeconds(ctx, duration);
                result.push("（" + durationSec + TooltipConstants.TIP_DRUG_SECOND + "）");
            }
            result.push(DrugTooltipUtil.br(ctx));
            return result;
        }
    }
}
