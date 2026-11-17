// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/CriticalBlockBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace CriticalBlockBuilder {
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, data?: any, equipData?: any): void {
            var critData: any = equipData ? equipData : data;
            if (!critData.criticalhit) {
                return;
            }
            var criticalhit: any = critData.criticalhit;
            if (!as2IsNaN(as2Number(criticalhit))) {
                result.push("<FONT COLOR='", TooltipConstants.COL_CRIT, "'>", TooltipConstants.LBL_CRIT, "：</FONT><FONT COLOR='", TooltipConstants.COL_CRIT, "'>", criticalhit, TooltipConstants.SUF_PERCENT, TooltipConstants.TIP_CRIT_CHANCE, "</FONT><BR>");
            }
            else if (criticalhit === TooltipConstants.TIP_CRIT_FULL_HP) {
                result.push("<FONT COLOR='", TooltipConstants.COL_CRIT, "'>", TooltipConstants.LBL_CRIT, "：", TooltipConstants.TIP_CRIT_FULL_HP_DESC, "</FONT><BR>");
            }
        }
    }
}
