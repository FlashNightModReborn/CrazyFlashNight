// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/HealTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace HealTooltipBuilder {
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            var hp: any = effectData.hp;
            var mp: any = effectData.mp;
            var target: string = effectData.target || "self";
            var scaleWithAlchemy: boolean = effectData.scaleWithAlchemy !== false;
            var hpStr: string = DrugTooltipUtil.formatValue(ctx, hp);
            var mpStr: string = DrugTooltipUtil.formatValue(ctx, mp);
            var hpNum: number = as2Number(hp);
            var mpNum: number = as2Number(mp);
            if (!as2IsNaN(hpNum) && as2NotEqual(hpNum, 0) || as2GreaterEqual(String(hp).indexOf("%"), 0)) {
                result.push(DrugTooltipUtil.color(ctx, "HP+" + hpStr, TooltipConstants.COL_HP));
                result.push(DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
                result.push(DrugTooltipUtil.br(ctx));
            }
            if (!as2IsNaN(mpNum) && as2NotEqual(mpNum, 0) || as2GreaterEqual(String(mp).indexOf("%"), 0)) {
                result.push(DrugTooltipUtil.color(ctx, "MP+" + mpStr, TooltipConstants.COL_MP));
                result.push(DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
                result.push(DrugTooltipUtil.br(ctx));
            }
            if (as2Equal(target, "group")) {
                result.push(DrugTooltipUtil.color(ctx, TooltipConstants.TIP_ALLY_EFFECT, TooltipConstants.COL_HL));
                result.push(DrugTooltipUtil.br(ctx));
            }
            return result;
        }
    }
}
