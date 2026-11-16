// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/DrugTooltipComposer.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace DrugTooltipComposer {
        export function compose(ctx: Context, item?: any, buffBuffer?: any[]): any[] {
            if (!item || !item.data)
                return [];
            var effects: any[] = ctx.projection.drugEffects;
            if (as2Equal(effects.length, 0)) {
                return [];
            }
            if (as2Equal(buffBuffer, null))
                return DrugTooltipRegistry.buildAll(ctx, effects);
            var main: any[] = [];
            var buff: any[] = [];
            for (var i: number = 0; as2Less(i, effects.length); i++) {
                var fragments: any[] = DrugTooltipRegistry.buildOne(ctx, effects[i]);
                if (as2Equal(fragments, null) || as2Equal(fragments.length, 0))
                    continue;
                if (isBuffEffect(ctx, effects[i].type))
                    buff = buff.concat(fragments);
                else
                    main = main.concat(fragments);
            }
            for (var j: number = 0; as2Less(j, buff.length); j++)
                buffBuffer.push(buff[j]);
            return main;
        }
        function isBuffEffect(ctx: Context, type?: string): boolean {
            return as2Equal(type, "buff") || as2Equal(type, "toughnessBuff")
                || as2Equal(type, "resistanceBuff") || as2Equal(type, "regen");
        }
    }
}
