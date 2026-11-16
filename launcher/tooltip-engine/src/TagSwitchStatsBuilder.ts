// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/TagSwitchStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace TagSwitchStatsBuilder {
        export function buildDetailed(ctx: Context, result?: any[], stats?: any): void {
            if (!stats || !stats.tagSwitch || !stats.tagSwitch.tagCases) {
                return;
            }
            var tagCases: any[] = stats.tagSwitch.tagCases;
            if (as2Equal(tagCases.length, 0)) {
                return;
            }
            result.push("<font color='" + TooltipConstants.COL_TAG_SWITCH + "'>" + TooltipConstants.LBL_TAG_SWITCH_EFFECT + "</font><BR>");
            for (var tcIdx: number = 0; as2Less(tcIdx, tagCases.length); tcIdx++) {
                var tagCase: any = tagCases[tcIdx];
                if (tagCase._isDefault || !tagCase.name) {
                    result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TIP_DEFAULT_BRANCH + "：</font><BR>");
                }
                else {
                    result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TIP_WHEN_HAS + " " + tagCase.name + " " + TooltipConstants.TIP_TAG_SUFFIX + "：</font><BR>");
                }
                UseSwitchStatsBuilder.buildStatBlock(ctx, result, tagCase, "  ");
            }
        }
    }
}
