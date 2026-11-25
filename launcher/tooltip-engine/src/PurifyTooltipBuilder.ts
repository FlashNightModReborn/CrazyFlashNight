// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/PurifyTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace PurifyTooltipBuilder {
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            var value: number = as2Number(effectData.value);
            var target: string = effectData.target || "self";
            var scaleWithAlchemy: boolean = effectData.scaleWithAlchemy !== false;
            if (as2IsNaN(value) || as2LessEqual(value, 0))
                return result;
            var label: string = as2Equal(target, "group")
                ? (TooltipConstants.TXT_GROUP + TooltipConstants.LBL_CLEAN)
                : TooltipConstants.LBL_CLEAN;
            result.push(label + "：" + value);
            result.push(DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
            result.push(DrugTooltipUtil.br(ctx));
            return result;
        }
    }
}
