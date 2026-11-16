// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/MeleeStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace MeleeStatsBuilder {
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, data?: any, equipData?: any): void {
            TooltipFormatter.upgradeLine(result, data, equipData, "power", "锋利度", null);
            var bladeCount: number = (data && as2Greater(data.bladeCount, 0)) ? as2Number(data.bladeCount) : 0;
            if (as2LessEqual(bladeCount, 0)) {
                var dressupName: string = (data && data.dressup) ? String(data.dressup) : null;
                bladeCount = as2Number(ctx.projection.bladeCount);
            }
            if (as2Greater(bladeCount, 0)) {
                result.push("判定数：", String(bladeCount), TooltipFormatter.br());
            }
        }
    }
}
