// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/StateTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace StateTooltipBuilder {
        const _stateKeyDisplayMap: any = {
            淬毒: null
        };
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            var key: string = effectData.key;
            var value: number = as2Number(effectData.value);
            var scaleWithAlchemy: boolean = effectData.scaleWithAlchemy !== false;
            if (!key || as2IsNaN(value))
                return result;
            if (as2Equal(key, "淬毒")) {
                result.push(DrugTooltipUtil.color(ctx, TooltipConstants.LBL_POISON + "：" + value, TooltipConstants.COL_POISON));
                result.push(DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
                result.push(DrugTooltipUtil.br(ctx));
                return result;
            }
            var displayName: string = _stateKeyDisplayMap[key];
            if (as2Equal(displayName, undefined)) {
                displayName = key;
            }
            result.push(displayName + "：" + value);
            result.push(DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
            result.push(DrugTooltipUtil.br(ctx));
            return result;
        }
    }
}
