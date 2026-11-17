// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/GrenadeStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace GrenadeStatsBuilder {
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, data?: any, equipData?: any): void {
            var power: number = as2Number(data.power);
            if (as2IsNaN(power)) {
                power = 0;
            }
            if (power !== 0) {
                result.push(TooltipConstants.LBL_POWER, "：", power, "<BR>");
            }
        }
    }
}
