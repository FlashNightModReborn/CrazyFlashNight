// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/DrugTooltipUtil.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace DrugTooltipUtil {
        export const FPS: number = 30;
        export function framesToSeconds(ctx: Context, frames?: number): string {
            if (as2IsNaN(frames) || as2LessEqual(frames, 0))
                return "0";
            var seconds: number = frames / FPS;
            if (as2Equal(seconds, Math.floor(seconds))) {
                return String(Math.floor(seconds));
            }
            return String(Math.round(seconds * 10) / 10);
        }
        export function formatValue(ctx: Context, value?: any): string {
            if (as2Equal(value, null) || as2Equal(value, undefined))
                return "0";
            var strValue: string = String(value);
            if (as2GreaterEqual(strValue.indexOf("%"), 0)) {
                return strValue;
            }
            var num: number = as2Number(value);
            return as2IsNaN(num) ? "0" : String(num);
        }
        export function alchemyTag(ctx: Context, scaleWithAlchemy?: boolean): string {
            if (!scaleWithAlchemy) {
                return "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.LBL_DRUG_NO_ALCHEMY + "</FONT>";
            }
            return "";
        }
        export function color(ctx: Context, text?: string, col?: string): string {
            return "<FONT COLOR='" + col + "'>" + text + "</FONT>";
        }
        export function br(ctx: Context): string {
            return "<BR>";
        }
    }
}
