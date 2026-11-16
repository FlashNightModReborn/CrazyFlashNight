// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/ObtainMethodsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace ObtainMethodsBuilder {
        export function build(ctx: Context, itemName?: string): any[] {
            var result: any[] = [];
            buildWithRows(ctx, result, itemName);
            return result;
        }
        export function buildWithRows(ctx: Context, result?: any[], itemName?: string): any {
            var records: any[] = ctx.projection.obtainRecords;
            if (!records || as2Equal(records.length, 0))
                return null;
            var crafts: any[] = [];
            var shops: any[] = [];
            var kshops: any[] = [];
            var stageDrops: any[] = [];
            var enemyDrops: any[] = [];
            var arenaDrops: any[] = [];
            var quests: any[] = [];
            for (var i: number = 0; as2Less(i, records.length); i++) {
                var rec: any = records[i];
                switch (rec.kind) {
                    case "craft":
                        crafts.push(rec);
                        break;
                    case "shop":
                        shops.push(rec);
                        break;
                    case "kshop":
                        kshops.push(rec);
                        break;
                    case "drop":
                        if (rec.dropType === "stage") {
                            stageDrops.push(rec);
                        }
                        else if (rec.dropType === "enemy") {
                            enemyDrops.push(rec);
                        }
                        else if (rec.dropType === "arena") {
                            arenaDrops.push(rec);
                        }
                        break;
                    case "quest":
                        quests.push(rec);
                        break;
                }
            }
            if (as2Equal(crafts.length, 0) && as2Equal(shops.length, 0) && as2Equal(kshops.length, 0) && as2Equal(stageDrops.length, 0) && as2Equal(enemyDrops.length, 0)
                && as2Equal(arenaDrops.length, 0) && as2Equal(quests.length, 0)) {
                return null;
            }
            var rows: any[] = [];
            result.push(TooltipFormatter.br());
            result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>");
            result.push(TooltipConstants.LBL_OBTAIN_METHODS);
            result.push("</FONT>");
            result.push(TooltipFormatter.br());
            var maxCrafts: number = TooltipConstants.OBTAIN_MAX_CRAFTS;
            var craftCount: number = Math.min(crafts.length, maxCrafts);
            if (as2Greater(craftCount, 0))
                rows.push({ name: labelOf(ctx, TooltipConstants.TIP_OBTAIN_CRAFT), effect: "" });
            for (var c: number = 0; as2Less(c, craftCount); c++) {
                var craft: any = crafts[c];
                var craftLabel: string = craftLocationLabel(ctx, String(craft.category));
                result.push("  <FONT COLOR='" + TooltipConstants.COL_CRAFT + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_CRAFT);
                result.push("</FONT>");
                result.push(craftLabel);
                var craftText: string = craftLabel;
                var craftPrice: string = "";
                if (as2Greater(craft.price, 0) || as2Greater(craft.kprice, 0)) {
                    result.push(" (");
                    if (as2Greater(craft.price, 0))
                        result.push("$" + craft.price);
                    if (as2Greater(craft.price, 0) && as2Greater(craft.kprice, 0))
                        result.push(" + ");
                    if (as2Greater(craft.kprice, 0))
                        result.push(craft.kprice + "K");
                    result.push(")");
                    craftText += " (";
                    if (as2Greater(craft.price, 0))
                        craftText += "$" + craft.price;
                    if (as2Greater(craft.price, 0) && as2Greater(craft.kprice, 0))
                        craftText += " + ";
                    if (as2Greater(craft.kprice, 0))
                        craftText += craft.kprice + "K";
                    craftText += ")";
                    craftPrice = craftText.substring(craftLabel.length);
                }
                result.push(TooltipFormatter.br());
                rows.push({ name: craftLabel, effect: craftPrice, depth: 1 });
            }
            if (as2Greater(crafts.length, maxCrafts)) {
                result.push("  <FONT COLOR='" + TooltipConstants.COL_CRAFT + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_CRAFT);
                result.push("</FONT>");
                result.push(TooltipConstants.TIP_ETC + (crafts.length - maxCrafts) + TooltipConstants.TIP_OBTAIN_MORE);
                result.push(TooltipFormatter.br());
                rows.push({ name: TooltipConstants.TIP_ETC + (crafts.length - maxCrafts)
                        + TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
            }
            if (as2Greater(shops.length, 0)) {
                result.push("  <FONT COLOR='" + TooltipConstants.COL_SHOP + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_SHOP);
                result.push("</FONT>");
                rows.push({ name: "NPC商店", effect: "" });
                var maxShops: number = TooltipConstants.OBTAIN_MAX_SHOPS;
                var shopNames: any[] = [];
                var shopCount: number = Math.min(shops.length, maxShops);
                for (var s: number = 0; as2Less(s, shopCount); s++) {
                    shopNames.push(shops[s].npc);
                    rows.push({ name: String(shops[s].npc), icon: String(shops[s].npc), effect: "", depth: 1 });
                }
                result.push(shopNames.join("、"));
                if (as2Greater(shops.length, maxShops)) {
                    result.push(TooltipConstants.TIP_ETC + (shops.length - maxShops) + TooltipConstants.TIP_OBTAIN_MORE);
                    rows.push({ name: TooltipConstants.TIP_ETC + (shops.length - maxShops)
                            + TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
                }
                result.push(TooltipFormatter.br());
            }
            var maxKshops: number = TooltipConstants.OBTAIN_MAX_KSHOPS;
            var kshopCount: number = Math.min(kshops.length, maxKshops);
            if (as2Greater(kshopCount, 0))
                rows.push({ name: labelOf(ctx, TooltipConstants.TIP_OBTAIN_KSHOP), effect: "" });
            for (var k: number = 0; as2Less(k, kshopCount); k++) {
                var kitem: any = kshops[k];
                result.push("  <FONT COLOR='" + TooltipConstants.COL_KSHOP + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_KSHOP);
                result.push("</FONT>");
                result.push(kitem.type + " (" + kitem.priceK + "K)");
                result.push(TooltipFormatter.br());
                rows.push({ name: String(kitem.type), effect: "(" + kitem.priceK + "K)", depth: 1 });
            }
            if (as2Greater(kshops.length, maxKshops)) {
                result.push("  <FONT COLOR='" + TooltipConstants.COL_KSHOP + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_KSHOP);
                result.push("</FONT>");
                result.push(TooltipConstants.TIP_ETC + (kshops.length - maxKshops) + TooltipConstants.TIP_OBTAIN_MORE);
                result.push(TooltipFormatter.br());
                rows.push({ name: TooltipConstants.TIP_ETC + (kshops.length - maxKshops)
                        + TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
            }
            if (as2Greater(stageDrops.length, 0)) {
                result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_STAGE + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_STAGE);
                result.push("</FONT>");
                rows.push({ name: labelOf(ctx, TooltipConstants.TIP_OBTAIN_STAGE), effect: "" });
                var maxStages: number = TooltipConstants.OBTAIN_MAX_STAGES;
                var stageNames: any[] = [];
                var stageCount: number = Math.min(stageDrops.length, maxStages);
                for (var st: number = 0; as2Less(st, stageCount); st++) {
                    stageNames.push(stageDrops[st].stageName);
                    rows.push({ name: String(stageDrops[st].stageName), effect: "", depth: 1 });
                }
                var stageText: string = stageNames.join("、");
                result.push(stageText);
                if (as2Greater(stageDrops.length, maxStages)) {
                    result.push(TooltipConstants.TIP_ETC + (stageDrops.length - maxStages) + TooltipConstants.TIP_OBTAIN_MORE);
                    stageText += TooltipConstants.TIP_ETC + (stageDrops.length - maxStages) + TooltipConstants.TIP_OBTAIN_MORE;
                    rows.push({ name: TooltipConstants.TIP_ETC + (stageDrops.length - maxStages)
                            + TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
                }
                result.push(TooltipFormatter.br());
            }
            if (as2Greater(enemyDrops.length, 0)) {
                result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_ENEMY + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_ENEMY);
                result.push("</FONT>");
                rows.push({ name: labelOf(ctx, TooltipConstants.TIP_OBTAIN_ENEMY), effect: "" });
                var maxEnemies: number = TooltipConstants.OBTAIN_MAX_ENEMIES;
                var enemyNames: any[] = [];
                var enemyCount: number = Math.min(enemyDrops.length, maxEnemies);
                for (var e: number = 0; as2Less(e, enemyCount); e++) {
                    var enemyType: string = enemyDrops[e].enemyType;
                    var displayName: string = enemyDrops[e].enemyDisplayName || ctx.catalog.enemyNames?.[enemyType] || enemyType;
                    enemyNames.push(displayName);
                    rows.push({ name: String(displayName), effect: "", depth: 1 });
                }
                var enemyText: string = enemyNames.join("、");
                result.push(enemyText);
                if (as2Greater(enemyDrops.length, maxEnemies)) {
                    result.push(TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies) + TooltipConstants.TIP_OBTAIN_MORE);
                    enemyText += TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies) + TooltipConstants.TIP_OBTAIN_MORE;
                    rows.push({ name: TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies)
                            + TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
                }
                result.push(TooltipFormatter.br());
            }
            var maxArenas: number = TooltipConstants.OBTAIN_MAX_ARENAS;
            var arenaCount: number = Math.min(arenaDrops.length, maxArenas);
            var arenaCategoryAdded: boolean = false;
            for (var a: number = 0; as2Less(a, arenaCount); a++) {
                var arena: any = arenaDrops[a];
                var carrierLabel: string;
                if (as2Equal(arena.carrierScope, "specific_carrier")) {
                    carrierLabel = TooltipConstants.TIP_OBTAIN_ARENA_SPECIFIC_CARRIER;
                }
                else if (as2Equal(arena.carrierScope, "carrier")) {
                    carrierLabel = TooltipConstants.TIP_OBTAIN_ARENA_CARRIER;
                }
                else {
                    continue;
                }
                if (!arenaCategoryAdded) {
                    rows.push({ name: labelOf(ctx, TooltipConstants.TIP_OBTAIN_ARENA), effect: "" });
                    arenaCategoryAdded = true;
                }
                result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_ARENA + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_ARENA);
                result.push("</FONT>");
                result.push(carrierLabel);
                result.push(TooltipFormatter.br());
                rows.push({ name: String(carrierLabel), effect: "", depth: 1 });
            }
            if (as2Greater(arenaDrops.length, maxArenas)) {
                result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_ARENA + "'>");
                result.push(TooltipConstants.TIP_OBTAIN_ARENA);
                result.push("</FONT>");
                result.push(TooltipConstants.TIP_ETC
                    + (arenaDrops.length - maxArenas) + TooltipConstants.TIP_OBTAIN_MORE);
                result.push(TooltipFormatter.br());
                if (arenaCategoryAdded) {
                    rows.push({ name: TooltipConstants.TIP_ETC + (arenaDrops.length - maxArenas)
                            + TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
                }
            }
            var title: string = TooltipConstants.LBL_OBTAIN_METHODS;
            if (as2Equal(title.charAt(0), "【") && as2Equal(title.charAt(title.length - 1), "】")) {
                title = title.substring(1, title.length - 1);
            }
            return { kind: "acquisition", title: title, rows: rows };
        }
        function labelOf(ctx: Context, tip?: string): string {
            if (as2Equal(tip, null))
                return "";
            var last: string = tip.charAt(tip.length - 1);
            if (as2Equal(last, "：") || as2Equal(last, ":"))
                return tip.substring(0, tip.length - 1);
            return tip;
        }
        function craftLocationLabel(ctx: Context, category?: string): string {
            if (as2Equal(category, "属性武器"))
                return "堕落城商业区 → 升阶与涂装";
            return category;
        }
    }
}
