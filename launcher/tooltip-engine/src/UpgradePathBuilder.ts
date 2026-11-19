// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/UpgradePathBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace UpgradePathBuilder {
        function isRecipeUnavailableForItem(ctx: Context, item: any): boolean {
            if (!ctx.catalog.recipesUnavailable || !item)
                return false;
            var targets: any = ctx.catalog.recipeTargets;
            if (!targets)
                return true;
            return Boolean((item.name && targets[item.name]) || (item.synthesis && targets[item.synthesis]));
        }
        export function build(ctx: Context, item?: any, baseItem?: Instance): any[] {
            var result: any[] = [];
            var craftUnavailable: boolean = isRecipeUnavailableForItem(ctx, item);
            var fromRecipe: any = craftUnavailable ? null : (lookupRecipe(ctx, item.synthesis) || lookupRecipe(ctx, item.name));
            var hasFrom: boolean = (!craftUnavailable && as2NotEqual(fromRecipe, null) && as2NotEqual(fromRecipe.materials, null));
            var toProducts: any[] = craftUnavailable ? null : lookupRecipesUsing(ctx, item.name);
            var hasTo: boolean = (!craftUnavailable && toProducts && as2Greater(toProducts.length, 0));
            var supportedTiers: any[] = [];
            var rawTierOpts: any[] = ctx.projection.tierOptions;
            if (rawTierOpts) {
                for (var i: number = 0; as2Less(i, rawTierOpts.length); i++) {
                    if (rawTierOpts[i].available)
                        supportedTiers.push(rawTierOpts[i]);
                }
            }
            var hasTier: boolean = (as2Greater(supportedTiers.length, 0));
            if (!craftUnavailable && !hasFrom && !hasTo && !hasTier)
                return result;
            result.push(TooltipFormatter.br());
            result.push(TooltipFormatter.color(TooltipConstants.LBL_UPGRADE_PATH, TooltipConstants.COL_INFO));
            result.push(TooltipFormatter.br());
            var rendered: boolean = false;
            if (craftUnavailable) {
                result.push("  ", "合成材料暂不可用", TooltipFormatter.br());
                rendered = true;
            }
            if (hasFrom) {
                renderFrom(ctx, result, fromRecipe);
                rendered = true;
            }
            if (hasTo) {
                if (rendered)
                    result.push(TooltipFormatter.br());
                renderTo(ctx, result, toProducts);
                rendered = true;
            }
            if (hasTier) {
                if (rendered)
                    result.push(TooltipFormatter.br());
                renderTier(ctx, result, supportedTiers, baseItem);
            }
            return result;
        }
        export function buildWithRows(ctx: Context, item?: any, baseItem?: Instance): any {
            var html: string = build(ctx, item, baseItem).join("");
            if (as2Equal(html.length, 0))
                return null;
            var rows: any[] = [];
            var craftUnavailable: boolean = isRecipeUnavailableForItem(ctx, item);
            if (craftUnavailable) {
                rows.push({ name: "合成材料暂不可用", depth: 0 });
            }
            else {
                var fromRecipe: any = lookupRecipe(ctx, item.synthesis) || lookupRecipe(ctx, item.name);
                if (as2NotEqual(fromRecipe, null) && as2NotEqual(fromRecipe.materials, null)) {
                    pushGroup(ctx, rows, TooltipConstants.TIP_UPGRADE_FROM, TooltipConstants.COL_CRAFT);
                    var requirements: any[] = fromRecipe.materials;
                    for (var i: number = 0; as2Less(i, requirements.length); i++) {
                        var req: any = requirements[i];
                        if (!req || !req.name)
                            continue;
                        var reqData: any = lookupItem(ctx, req.name);
                        var reqName: string = (reqData && reqData.displayname) ? reqData.displayname : req.name;
                        if (req.isQuantity)
                            reqName += " x" + req.value;
                        else if (isEquipment(ctx, req.name))
                            reqName += " +" + req.value;
                        else
                            reqName += "：" + req.value;
                        rows.push({ name: reqName, icon: iconFor(ctx, req.name), depth: 1 });
                    }
                }
                var toProducts: any[] = lookupRecipesUsing(ctx, item.name);
                if (toProducts && as2Greater(toProducts.length, 0)) {
                    pushGroup(ctx, rows, TooltipConstants.TIP_UPGRADE_TO, TooltipConstants.COL_CRAFT);
                    var shown: number = Math.min(toProducts.length, TooltipConstants.UPGRADE_MAX_TO_PRODUCTS);
                    for (var p: number = 0; as2Less(p, shown); p++) {
                        var prodName: string = toProducts[p];
                        var prodData: any = lookupItem(ctx, prodName);
                        rows.push({ name: (prodData && prodData.displayname) ? prodData.displayname : prodName,
                            icon: iconFor(ctx, prodName), depth: 1 });
                    }
                    if (as2Greater(toProducts.length, shown)) {
                        rows.push({ name: "... " + TooltipConstants.TIP_ETC + "共 " + toProducts.length + " 项", depth: 1 });
                    }
                }
            }
            var supportedTiers: any[] = [];
            var rawTierOpts: any[] = ctx.projection.tierOptions;
            if (rawTierOpts) {
                for (var t: number = 0; as2Less(t, rawTierOpts.length); t++) {
                    if (rawTierOpts[t].available)
                        supportedTiers.push(rawTierOpts[t]);
                }
            }
            if (as2Greater(supportedTiers.length, 0)) {
                pushGroup(ctx, rows, TooltipConstants.TIP_TIER_OPTIONS, TooltipConstants.COL_ENHANCE);
                var currentTier: string = (baseItem && baseItem.value) ? baseItem.value.tier : null;
                for (var j: number = 0; as2Less(j, supportedTiers.length); j++) {
                    var opt: any = supportedTiers[j];
                    var row: any = { name: opt.name, depth: 1 };
                    if (currentTier && opt.name === currentTier)
                        row.name += TooltipConstants.TIP_TIER_CURRENT;
                    if (opt.material) {
                        row.icon = iconFor(ctx, opt.material);
                        row.effect = " " + TooltipFormatter.color("[" + opt.material + "]", TooltipConstants.COL_INFO);
                    }
                    rows.push(row);
                }
            }
            return { kind: "upgrades", title: TooltipConstants.LBL_UPGRADE_PATH, rows: rows, html: html };
        }
        function pushGroup(ctx: Context, rows?: any[], name?: string, color?: string): void {
            rows.push({ name: name, depth: 0, effect: TooltipFormatter.color(name, color) });
        }
        function iconFor(ctx: Context, name?: string): string {
            if (!name)
                return null;
            var data: any = lookupItem(ctx, name);
            return (data && data.icon) ? String(data.icon) : name;
        }
        function renderFrom(ctx: Context, result?: any[], fromRecipe?: any): void {
            var requirements: any[] = fromRecipe.materials;
            if (!requirements || as2Equal(requirements.length, 0))
                return;
            result.push("  ");
            result.push(TooltipFormatter.color(TooltipConstants.TIP_UPGRADE_FROM, TooltipConstants.COL_CRAFT));
            result.push(TooltipFormatter.br());
            for (var i: number = 0; as2Less(i, requirements.length); i++) {
                var req: any = requirements[i];
                if (!req || !req.name)
                    continue;
                var itemData: any = lookupItem(ctx, req.name);
                var displayName: string = (itemData && itemData.displayname) ? itemData.displayname : req.name;
                result.push("  • ", displayName);
                if (req.isQuantity) {
                    result.push(" x", req.value);
                }
                else if (isEquipment(ctx, req.name)) {
                    result.push(" +", req.value);
                }
                else {
                    result.push("：", req.value);
                }
                result.push(TooltipFormatter.br());
            }
        }
        function renderTo(ctx: Context, result?: any[], toProducts?: any[]): void {
            result.push("  ");
            result.push(TooltipFormatter.color(TooltipConstants.TIP_UPGRADE_TO, TooltipConstants.COL_CRAFT));
            result.push(TooltipFormatter.br());
            var maxN: number = TooltipConstants.UPGRADE_MAX_TO_PRODUCTS;
            var total: number = toProducts.length;
            var shown: number = Math.min(total, maxN);
            for (var i: number = 0; as2Less(i, shown); i++) {
                var prodName: string = toProducts[i];
                var itemData: any = lookupItem(ctx, prodName);
                var displayName: string = (itemData && itemData.displayname) ? itemData.displayname : prodName;
                result.push("  • ", displayName, TooltipFormatter.br());
            }
            if (as2Greater(total, maxN)) {
                result.push("  • ... ", TooltipConstants.TIP_ETC, "共 ", total, " 项", TooltipFormatter.br());
            }
        }
        function renderTier(ctx: Context, result?: any[], supportedTiers?: any[], baseItem?: Instance): void {
            result.push("  ");
            result.push(TooltipFormatter.color(TooltipConstants.TIP_TIER_OPTIONS, TooltipConstants.COL_ENHANCE));
            result.push(TooltipFormatter.br());
            var currentTier: string = (baseItem && baseItem.value) ? baseItem.value.tier : null;
            for (var i: number = 0; as2Less(i, supportedTiers.length); i++) {
                var opt: any = supportedTiers[i];
                result.push("  • ", opt.name);
                if (currentTier && opt.name === currentTier) {
                    result.push(TooltipConstants.TIP_TIER_CURRENT);
                }
                if (opt.material) {
                    result.push(" ");
                    result.push(TooltipFormatter.color("[" + opt.material + "]", TooltipConstants.COL_INFO));
                }
                result.push(TooltipFormatter.br());
            }
        }
    }
}
