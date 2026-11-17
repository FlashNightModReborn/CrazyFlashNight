namespace TooltipEngine {
    /** Closed display dispatch. No mutable registration API or per-request builder objects. */
    export namespace DrugTooltipRegistry {
        export function buildOne(ctx: Context, effect: any): any[] {
            if (!effect || effect.tooltip === false || effect.tooltip === 'false')
                return [];
            switch (effect.type) {
                case 'heal': return HealTooltipBuilder.build(ctx, effect);
                case 'regen': return RegenTooltipBuilder.build(ctx, effect);
                case 'state': return StateTooltipBuilder.build(ctx, effect);
                case 'purify': return PurifyTooltipBuilder.build(ctx, effect);
                case 'buff': return BuffTooltipBuilder.build(ctx, effect);
                case 'toughnessBuff': return ToughnessBuffTooltipBuilder.build(ctx, effect);
                case 'resistanceBuff': return ResistanceBuffTooltipBuilder.build(ctx, effect);
                case 'restoreToughness': return ToughnessRestoreTooltipBuilder.build(ctx, effect);
                case 'grantItem': return GrantItemTooltipBuilder.build(ctx, effect);
                default: return [];
            }
        }
        export function buildAll(ctx: Context, effects: any[]): any[] {
            const result: any[] = [];
            for (const effect of effects || [])
                result.push(...buildOne(ctx, effect));
            return result;
        }
    }
}
