// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/CommonStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace CommonStatsBuilder {
        const ACTION_TYPE_USES: any = {
            刀: true,
            手部装备: true
        };
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, data?: any, equipData?: any, nativeOpt?: any): void {
            var slayTarget: any[] = result;
            if (as2NotEqual(nativeOpt, null) && nativeOpt.omitCritSlay === true && as2NotEqual(nativeOpt.critSlay, null)) {
                slayTarget = nativeOpt.critSlay;
            }
            TooltipFormatter.upgradeLine(result, data, equipData, "force", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "damage", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "punch", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "knifepower", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "gunpower", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "accuracy", null, TooltipConstants.SUF_PERCENT);
            TooltipFormatter.upgradeLine(result, data, equipData, "evasion", null, TooltipConstants.SUF_PERCENT);
            TooltipFormatter.upgradeLine(result, data, equipData, "toughness", null, TooltipConstants.SUF_PERCENT);
            TooltipFormatter.upgradeLine(result, data, equipData, "lazymiss", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "poison", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "vampirism", null, TooltipConstants.SUF_PERCENT);
            TooltipFormatter.upgradeLine(result, data, equipData, "rout", null, TooltipConstants.SUF_PERCENT);
            TooltipFormatter.upgradeLine(slayTarget, data, equipData, "slay", null, TooltipConstants.SUF_BLOOD);
            TooltipFormatter.upgradeLine(result, data, equipData, "defence", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "hp", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "mp", null, null);
            if (ACTION_TYPE_USES[item.use] === true
                && (as2Equal(nativeOpt, null) || nativeOpt.omitActionType !== true)) {
                var finalActionType: string = null;
                var originalActionType: string = item.actiontype;
                if (baseItem && as2NotEqual(baseItem.getData, undefined)) {
                    var calculatedData: any = baseItem.getData();
                    if (calculatedData && calculatedData.actiontype !== undefined) {
                        finalActionType = calculatedData.actiontype;
                    }
                }
                if (as2Equal(finalActionType, null)) {
                    finalActionType = originalActionType;
                }
                if (finalActionType === undefined) {
                    finalActionType = "默认";
                }
                var isOverridden: boolean = (originalActionType !== undefined && as2NotEqual(finalActionType, originalActionType));
                if (isOverridden) {
                    result.push(TooltipConstants.LBL_ACTION, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalActionType, "</FONT>");
                    result.push(" <FONT COLOR='", TooltipConstants.COL_INFO, "'>(←", originalActionType, ")</FONT><BR>");
                }
                else {
                    result.push(TooltipConstants.LBL_ACTION, "：", finalActionType, "<BR>");
                }
            }
        }
    }
}
