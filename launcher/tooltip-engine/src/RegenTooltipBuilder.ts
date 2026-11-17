// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/RegenTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace RegenTooltipBuilder {
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            var hp: any = effectData.hp;
            var mp: any = effectData.mp;
            var duration: number = as2Number(effectData.duration);
            var interval: number = as2Number(effectData.interval);
            var mode: string = effectData.mode || "perTick";
            var scaleWithAlchemy: boolean = effectData.scaleWithAlchemy !== false;
            var stack: string = effectData.stack || "refresh";
            if (as2IsNaN(interval) || as2LessEqual(interval, 0))
                interval = 30;
            if (as2IsNaN(duration) || as2LessEqual(duration, 0))
                return result;
            var durationSec: string = DrugTooltipUtil.framesToSeconds(ctx, duration);
            var intervalSec: string = DrugTooltipUtil.framesToSeconds(ctx, interval);
            var hpStr: string = DrugTooltipUtil.formatValue(ctx, hp);
            var mpStr: string = DrugTooltipUtil.formatValue(ctx, mp);
            var hpNum: number = as2Number(hp);
            var mpNum: number = as2Number(mp);
            var parts: any[] = [];
            if (!as2IsNaN(hpNum) && as2NotEqual(hpNum, 0) || as2GreaterEqual(String(hp).indexOf("%"), 0)) {
                var hpText: string;
                if (as2Equal(mode, "total")) {
                    hpText = hpStr + "hp/" + durationSec + "s";
                }
                else {
                    hpText = hpStr + "hp/" + intervalSec + "s/" + durationSec + "s";
                }
                parts.push(DrugTooltipUtil.color(ctx, hpText, TooltipConstants.COL_HP));
            }
            if (!as2IsNaN(mpNum) && as2NotEqual(mpNum, 0) || as2GreaterEqual(String(mp).indexOf("%"), 0)) {
                var mpText: string;
                if (as2Equal(mode, "total")) {
                    mpText = mpStr + "mp/" + durationSec + "s";
                }
                else {
                    mpText = mpStr + "mp/" + intervalSec + "s/" + durationSec + "s";
                }
                parts.push(DrugTooltipUtil.color(ctx, mpText, TooltipConstants.COL_MP));
            }
            if (as2Equal(parts.length, 0))
                return result;
            result.push(DrugTooltipUtil.color(ctx, TooltipConstants.LBL_DRUG_REGEN + "：", TooltipConstants.COL_HL));
            result.push(parts.join(" "));
            var alchemyStr: string = DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy);
            if (as2Greater(alchemyStr.length, 0)) {
                result.push(" ");
                result.push(alchemyStr);
            }
            result.push(DrugTooltipUtil.br(ctx));
            if (as2Equal(stack, "refresh") && !effectData.id) {
                result.push(DrugTooltipUtil.color(ctx, TooltipConstants.LBL_DRUG_REGEN_OVERRIDE, TooltipConstants.COL_INFO));
                result.push(DrugTooltipUtil.br(ctx));
            }
            return result;
        }
    }
}
