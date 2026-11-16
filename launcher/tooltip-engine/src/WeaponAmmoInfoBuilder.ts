// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/WeaponAmmoInfoBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace WeaponAmmoInfoBuilder {
        function quota(ctx: Context, value?: any): number {
            var n: number = as2Number(value);
            return as2Greater(n, 0) && as2IsFinite(n) ? Math.min(2, Math.floor(n)) : 0;
        }
        export function capacitySuffix(ctx: Context, data?: any): string {
            var capacity: number = Math.floor(as2Number(data.capacity));
            if (!(as2Greater(capacity, 0)) || !as2IsFinite(capacity))
                return "";
            var config: any = data.overload;
            var chamber: number = quota(ctx, config?.chamber);
            var ghost: number = quota(ctx, config?.ghost);
            if (as2Greater(ghost, 0))
                ghost = Math.max(ghost, quota(ctx, config?.ghostLimit));
            var result: string = "";
            if (as2Greater(chamber, 0))
                result += colored(ctx, chamber, TooltipConstants.COL_AMMO_CHAMBER);
            if (as2Greater(ghost, 0))
                result += colored(ctx, ghost, TooltipConstants.COL_AMMO_GHOST);
            if (config?.reward)
                result += colored(ctx, capacity, TooltipConstants.COL_AMMO_REWARD);
            return result;
        }
        function colored(ctx: Context, amount?: number, color?: string): string {
            return " <FONT COLOR='" + color + "'>+" + amount + "</FONT>";
        }
        export function appendMerge(ctx: Context, result?: any[], config?: any, indent?: string): void {
            var limit: number = quota(ctx, config?.ghostLimit);
            if (as2Equal(limit, 0))
                return;
            result.push(indent, "<font color='", TooltipConstants.COL_HL, "'>", TooltipConstants.TAG_MERGE, "</font> ", TooltipConstants.LBL_GHOST_LIMIT, " → ", limit, "发（需原生支持及冲击连携，不累加）。<BR>");
        }
    }
}
