// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/SilenceEffectBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace SilenceEffectBuilder {
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, data?: any, equipData?: any): void {
            var baseSilence: any = data ? data.silence : null;
            var finalSilence: any = equipData ? equipData.silence : null;
            var silenceValue: any = as2NotEqual(finalSilence, null) ? finalSilence : baseSilence;
            if (as2Equal(silenceValue, null) || as2Equal(silenceValue, undefined)) {
                return;
            }
            var silenceStr: string = String(silenceValue);
            if (as2Greater(silenceStr.indexOf("%"), 0)) {
                buildPercentageSilence(ctx, result, silenceStr, baseSilence, finalSilence);
            }
            else {
                buildDistanceSilence(ctx, result, silenceValue, baseSilence, finalSilence);
            }
        }
        function buildPercentageSilence(ctx: Context, result?: any[], silenceStr?: string, baseSilence?: any, finalSilence?: any): void {
            var percentIndex: number = silenceStr.indexOf("%");
            var percentValue: string = silenceStr.substring(0, percentIndex);
            var percentNum: number = as2Number(percentValue);
            if (as2IsNaN(percentNum) || as2Less(percentNum, 0) || as2Greater(percentNum, 100)) {
                return;
            }
            result.push("<FONT COLOR='" + TooltipConstants.COL_SILENCE + "'>" + TooltipConstants.LBL_SILENCE_EFFECT + "：</FONT>");
            if (as2NotEqual(finalSilence, null) && as2NotEqual(baseSilence, null) && as2NotEqual(finalSilence, baseSilence)) {
                var baseStr: string = String(baseSilence);
                var isTypeSwitched: boolean = (as2Less(baseStr.indexOf("%"), 0));
                result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>", percentValue, "%</FONT> " + TooltipConstants.TIP_SILENCE_PERCENT + " <FONT COLOR='" + TooltipConstants.COL_INFO + "'>(" + TooltipConstants.TIP_SILENCE_ORIG);
                if (isTypeSwitched) {
                    result.push(TooltipConstants.SUF_DISTANCE + " ", baseSilence);
                }
                else {
                    result.push(baseSilence);
                }
                result.push(")</FONT><BR>");
            }
            else {
                result.push(percentValue, "% " + TooltipConstants.TIP_SILENCE_PERCENT + "<BR>");
            }
            result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>  [" + TooltipConstants.TIP_SILENCE_PERCENT_DESC + " ", percentValue, "% " + TooltipConstants.TIP_SILENCE_PERCENT_DESC2 + "]</FONT><BR>");
        }
        function buildDistanceSilence(ctx: Context, result?: any[], silenceValue?: any, baseSilence?: any, finalSilence?: any): void {
            var distanceValue: number = as2Number(silenceValue);
            if (as2IsNaN(distanceValue) || as2LessEqual(distanceValue, 0)) {
                return;
            }
            result.push("<FONT COLOR='" + TooltipConstants.COL_SILENCE + "'>" + TooltipConstants.LBL_SILENCE_EFFECT + "：</FONT>");
            if (as2NotEqual(finalSilence, null) && as2NotEqual(baseSilence, null) && as2NotEqual(finalSilence, baseSilence)) {
                var baseStr: string = String(baseSilence);
                var isTypeSwitched: boolean = (as2Greater(baseStr.indexOf("%"), 0));
                result.push(TooltipConstants.LBL_SILENCE_DISTANCE + " <FONT COLOR='" + TooltipConstants.COL_HL + "'>", distanceValue, "</FONT> <FONT COLOR='" + TooltipConstants.COL_INFO + "'>(" + TooltipConstants.TIP_SILENCE_ORIG);
                if (isTypeSwitched) {
                    result.push(TooltipConstants.SUF_PERCENT + " ", baseSilence);
                }
                else {
                    result.push(baseSilence);
                }
                result.push(")</FONT><BR>");
            }
            else {
                result.push(TooltipConstants.LBL_SILENCE_DISTANCE + " <FONT COLOR='" + TooltipConstants.COL_HL + "'>", distanceValue, "</FONT><BR>");
            }
            result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>  [" + TooltipConstants.TIP_SILENCE_DIST_DESC + " ", "<FONT COLOR='" + TooltipConstants.COL_HL + "'>", distanceValue, "</FONT>", " " + TooltipConstants.TIP_SILENCE_DIST_DESC2 + "]</FONT><BR>");
        }
        export function getShortDescription(ctx: Context, silenceValue?: any): string {
            if (as2Equal(silenceValue, null) || as2Equal(silenceValue, undefined)) {
                return "";
            }
            var silenceStr: string = String(silenceValue);
            if (as2Greater(silenceStr.indexOf("%"), 0)) {
                return silenceStr + TooltipConstants.TIP_SILENCE_SHORT;
            }
            var distanceValue: number = as2Number(silenceValue);
            if (!as2IsNaN(distanceValue) && as2Greater(distanceValue, 0)) {
                return ">" + distanceValue + TooltipConstants.TIP_SILENCE_SHORT;
            }
            return "";
        }
    }
}
