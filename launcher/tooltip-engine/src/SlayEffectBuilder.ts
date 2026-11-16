// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/SlayEffectBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace SlayEffectBuilder {
        export function buildFlat(ctx: Context, result?: any[], slayValue?: number): void {
            if (as2Equal(slayValue, null) || as2Equal(slayValue, undefined)) {
                return;
            }
            var n: number = as2Number(slayValue);
            if (as2IsNaN(n) || n === 0) {
                return;
            }
            var sign: string = " + ";
            if (as2Less(n, 0)) {
                n = -n;
                sign = " - ";
            }
            var label: string = TooltipConstants.PROPERTY_DICT["slay"];
            if (!label)
                label = TooltipConstants.LBL_SLAY_SHORT + "线";
            result.push(label, sign, n, TooltipConstants.SUF_BLOOD, "<BR>");
        }
        export function buildOverride(ctx: Context, result?: any[], slayValue?: number): void {
            if (as2Equal(slayValue, null) || as2Equal(slayValue, undefined)) {
                return;
            }
            var n: number = as2Number(slayValue);
            if (as2IsNaN(n)) {
                return;
            }
            var label: string = TooltipConstants.PROPERTY_DICT["slay"];
            if (!label)
                label = TooltipConstants.LBL_SLAY_SHORT + "线";
            result.push(label, " -> ", n, TooltipConstants.SUF_BLOOD, "<BR>");
        }
        export function getShortDescription(ctx: Context, slayValue?: number): string {
            if (as2Equal(slayValue, null) || as2Equal(slayValue, undefined)) {
                return "";
            }
            var n: number = as2Number(slayValue);
            if (as2IsNaN(n) || n === 0) {
                return "";
            }
            return n + TooltipConstants.SUF_PERCENT + TooltipConstants.LBL_SLAY_SHORT;
        }
    }
}
