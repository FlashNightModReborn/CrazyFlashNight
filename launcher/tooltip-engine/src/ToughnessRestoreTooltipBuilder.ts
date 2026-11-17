// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/ToughnessRestoreTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace ToughnessRestoreTooltipBuilder {
        export function build(ctx: Context, effectData?: any): any[] {
            var result: any[] = [];
            result.push(DrugTooltipUtil.color(ctx, "韧性：", TooltipConstants.COL_HL));
            result.push("立即恢复至满");
            result.push(DrugTooltipUtil.br(ctx));
            return result;
        }
    }
}
