/**
 * ObtainMethodsBuilder - 物品获取方式构建器
 *
 * 从 TooltipTextBuilder.buildObtainMethods 提取。
 * 显示物品的合成来源、NPC商店、K点商店等获取渠道。
 */
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipBridge;

class org.flashNight.gesh.tooltip.builder.ObtainMethodsBuilder {

    /**
     * 构建物品获取方式文本
     * @param itemName 物品名称
     * @return Array HTML文本片段数组，若无来源返回空数组
     */
    public static function build(itemName:String):Array {
        var result:Array = [];
        buildWithRows(result, itemName);
        return result;
    }

    /**
     * 与 build 同源的一次收集：旧 HTML 写入 result（逐字节保持旧输出），同时返回
     * 结构化描述 {kind:"acquisition", title, rows:[{name, icon?, effect, depth?}]}，
     * 供原生注释框把「获取方式」渲染为独立子框。类别为父级行，具体合成/商店/掉落
     * 条目以 depth:1 作为子级；NPC 子行 icon 为头像键。rows[].effect 仍是受限 HTML
     * 片段，由 NativeTooltipDocument 在文档边界展开为 runs。
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param itemName 物品名称
     * @return Object|null 无来源时返回 null（result 不变）
     */
    public static function buildWithRows(result:Array, itemName:String):Object {
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (!index.isIndexBuilt()) return null;

        var records:Array = index.getObtainRecords(itemName);
        if (!records || records.length == 0) return null;

        var crafts:Array = [];
        var shops:Array = [];
        var kshops:Array = [];
        var stageDrops:Array = [];
        var enemyDrops:Array = [];
        var arenaDrops:Array = [];
        var quests:Array = [];

        for (var i:Number = 0; i < records.length; i++) {
            var rec:Object = records[i];
            switch (rec.kind) {
                case ItemObtainIndex.KIND_CRAFT:
                    crafts.push(rec);
                    break;
                case ItemObtainIndex.KIND_SHOP:
                    shops.push(rec);
                    break;
                case ItemObtainIndex.KIND_KSHOP:
                    kshops.push(rec);
                    break;
                case ItemObtainIndex.KIND_DROP:
                    if (rec.dropType === ItemObtainIndex.DROP_TYPE_STAGE) {
                        stageDrops.push(rec);
                    } else if (rec.dropType === ItemObtainIndex.DROP_TYPE_ENEMY) {
                        enemyDrops.push(rec);
                    } else if (rec.dropType === ItemObtainIndex.DROP_TYPE_ARENA) {
                        arenaDrops.push(rec);
                    }
                    break;
                case ItemObtainIndex.KIND_QUEST:
                    quests.push(rec);
                    break;
            }
        }

        if (crafts.length == 0 && shops.length == 0 && kshops.length == 0 &&
            stageDrops.length == 0 && enemyDrops.length == 0
            && arenaDrops.length == 0 && quests.length == 0) {
            return null;
        }

        // 结构化行与旧 HTML 同步收集；旧 HTML 逐字节保持原输出
        var rows:Array = [];

        result.push(TooltipFormatter.br());
        result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>");
        result.push(TooltipConstants.LBL_OBTAIN_METHODS);
        result.push("</FONT>");
        result.push(TooltipFormatter.br());

        var maxCrafts:Number = TooltipConstants.OBTAIN_MAX_CRAFTS;
        var craftCount:Number = Math.min(crafts.length, maxCrafts);
        if (craftCount > 0) rows.push({name:labelOf(TooltipConstants.TIP_OBTAIN_CRAFT), effect:""});
        for (var c:Number = 0; c < craftCount; c++) {
            var craft:Object = crafts[c];
            result.push("  <FONT COLOR='" + TooltipConstants.COL_CRAFT + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_CRAFT);
            result.push("</FONT>");
            result.push(craft.category);
            var craftText:String = String(craft.category);
            var craftPrice:String = "";
            if (craft.price > 0 || craft.kprice > 0) {
                result.push(" (");
                if (craft.price > 0) result.push("$" + craft.price);
                if (craft.price > 0 && craft.kprice > 0) result.push(" + ");
                if (craft.kprice > 0) result.push(craft.kprice + "K");
                result.push(")");
                craftText += " (";
                if (craft.price > 0) craftText += "$" + craft.price;
                if (craft.price > 0 && craft.kprice > 0) craftText += " + ";
                if (craft.kprice > 0) craftText += craft.kprice + "K";
                craftText += ")";
                craftPrice = craftText.substring(String(craft.category).length);
            }
            result.push(TooltipFormatter.br());
            rows.push({name:String(craft.category), effect:craftPrice, depth:1});
        }
        if (crafts.length > maxCrafts) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_CRAFT + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_CRAFT);
            result.push("</FONT>");
            result.push(TooltipConstants.TIP_ETC + (crafts.length - maxCrafts) + TooltipConstants.TIP_OBTAIN_MORE);
            result.push(TooltipFormatter.br());
            rows.push({name:TooltipConstants.TIP_ETC + (crafts.length - maxCrafts)
                + TooltipConstants.TIP_OBTAIN_MORE, effect:"", depth:1});
        }

        if (shops.length > 0) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_SHOP + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_SHOP);
            result.push("</FONT>");
            rows.push({name:"NPC商店", effect:""});
            var maxShops:Number = TooltipConstants.OBTAIN_MAX_SHOPS;
            var shopNames:Array = [];
            var shopCount:Number = Math.min(shops.length, maxShops);
            for (var s:Number = 0; s < shopCount; s++) {
                shopNames.push(shops[s].npc);
                rows.push({name:String(shops[s].npc), icon:String(shops[s].npc), effect:"", depth:1});
            }
            result.push(shopNames.join("、"));
            if (shops.length > maxShops) {
                result.push(TooltipConstants.TIP_ETC + (shops.length - maxShops) + TooltipConstants.TIP_OBTAIN_MORE);
                rows.push({name:TooltipConstants.TIP_ETC + (shops.length - maxShops)
                    + TooltipConstants.TIP_OBTAIN_MORE, effect:"", depth:1});
            }
            result.push(TooltipFormatter.br());
        }

        var maxKshops:Number = TooltipConstants.OBTAIN_MAX_KSHOPS;
        var kshopCount:Number = Math.min(kshops.length, maxKshops);
        if (kshopCount > 0) rows.push({name:labelOf(TooltipConstants.TIP_OBTAIN_KSHOP), effect:""});
        for (var k:Number = 0; k < kshopCount; k++) {
            var kitem:Object = kshops[k];
            result.push("  <FONT COLOR='" + TooltipConstants.COL_KSHOP + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_KSHOP);
            result.push("</FONT>");
            result.push(kitem.type + " (" + kitem.priceK + "K)");
            result.push(TooltipFormatter.br());
            rows.push({name:String(kitem.type), effect:"(" + kitem.priceK + "K)", depth:1});
        }
        if (kshops.length > maxKshops) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_KSHOP + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_KSHOP);
            result.push("</FONT>");
            result.push(TooltipConstants.TIP_ETC + (kshops.length - maxKshops) + TooltipConstants.TIP_OBTAIN_MORE);
            result.push(TooltipFormatter.br());
            rows.push({name:TooltipConstants.TIP_ETC + (kshops.length - maxKshops)
                + TooltipConstants.TIP_OBTAIN_MORE, effect:"", depth:1});
        }

        if (stageDrops.length > 0) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_STAGE + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_STAGE);
            result.push("</FONT>");
            rows.push({name:labelOf(TooltipConstants.TIP_OBTAIN_STAGE), effect:""});
            var maxStages:Number = TooltipConstants.OBTAIN_MAX_STAGES;
            var stageNames:Array = [];
            var stageCount:Number = Math.min(stageDrops.length, maxStages);
            for (var st:Number = 0; st < stageCount; st++) {
                stageNames.push(stageDrops[st].stageName);
                rows.push({name:String(stageDrops[st].stageName), effect:"", depth:1});
            }
            var stageText:String = stageNames.join("、");
            result.push(stageText);
            if (stageDrops.length > maxStages) {
                result.push(TooltipConstants.TIP_ETC + (stageDrops.length - maxStages) + TooltipConstants.TIP_OBTAIN_MORE);
                stageText += TooltipConstants.TIP_ETC + (stageDrops.length - maxStages) + TooltipConstants.TIP_OBTAIN_MORE;
                rows.push({name:TooltipConstants.TIP_ETC + (stageDrops.length - maxStages)
                    + TooltipConstants.TIP_OBTAIN_MORE, effect:"", depth:1});
            }
            result.push(TooltipFormatter.br());
        }

        if (enemyDrops.length > 0) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_ENEMY + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_ENEMY);
            result.push("</FONT>");
            rows.push({name:labelOf(TooltipConstants.TIP_OBTAIN_ENEMY), effect:""});
            var maxEnemies:Number = TooltipConstants.OBTAIN_MAX_ENEMIES;
            var enemyNames:Array = [];
            var enemyCount:Number = Math.min(enemyDrops.length, maxEnemies);
            for (var e:Number = 0; e < enemyCount; e++) {
                var enemyType:String = enemyDrops[e].enemyType;
                var displayName:String = TooltipBridge.getEnemyDisplayName(enemyType);
                enemyNames.push(displayName);
                rows.push({name:String(displayName), effect:"", depth:1});
            }
            var enemyText:String = enemyNames.join("、");
            result.push(enemyText);
            if (enemyDrops.length > maxEnemies) {
                result.push(TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies) + TooltipConstants.TIP_OBTAIN_MORE);
                enemyText += TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies) + TooltipConstants.TIP_OBTAIN_MORE;
                rows.push({name:TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies)
                    + TooltipConstants.TIP_OBTAIN_MORE, effect:"", depth:1});
            }
            result.push(TooltipFormatter.br());
        }

        var maxArenas:Number = TooltipConstants.OBTAIN_MAX_ARENAS;
        var arenaCount:Number = Math.min(arenaDrops.length, maxArenas);
        var arenaCategoryAdded:Boolean = false;
        for (var a:Number = 0; a < arenaCount; a++) {
            var arena:Object = arenaDrops[a];
            var carrierLabel:String;
            if (arena.carrierScope == "specific_carrier") {
                carrierLabel = TooltipConstants.TIP_OBTAIN_ARENA_SPECIFIC_CARRIER;
            } else if (arena.carrierScope == "carrier") {
                carrierLabel = TooltipConstants.TIP_OBTAIN_ARENA_CARRIER;
            } else {
                continue;
            }
            if (!arenaCategoryAdded) {
                rows.push({name:labelOf(TooltipConstants.TIP_OBTAIN_ARENA), effect:""});
                arenaCategoryAdded = true;
            }
            result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_ARENA + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_ARENA);
            result.push("</FONT>");
            result.push(carrierLabel);
            result.push(TooltipFormatter.br());
            rows.push({name:String(carrierLabel), effect:"", depth:1});
        }
        if (arenaDrops.length > maxArenas) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_ARENA + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_ARENA);
            result.push("</FONT>");
            result.push(TooltipConstants.TIP_ETC
                + (arenaDrops.length - maxArenas) + TooltipConstants.TIP_OBTAIN_MORE);
            result.push(TooltipFormatter.br());
            if (arenaCategoryAdded) {
                rows.push({name:TooltipConstants.TIP_ETC + (arenaDrops.length - maxArenas)
                    + TooltipConstants.TIP_OBTAIN_MORE, effect:"", depth:1});
            }
        }

        // 子框标题：去掉【】，与其他子框（如「已安装N个配件」）风格一致
        var title:String = TooltipConstants.LBL_OBTAIN_METHODS;
        if (title.charAt(0) == "【" && title.charAt(title.length - 1) == "】") {
            title = title.substring(1, title.length - 1);
        }
        return {kind:"acquisition", title:title, rows:rows};
    }

    /** 类别标签去尾冒号：行内 name 用 "合成"，旧 HTML 仍用原常量 "合成："。 */
    private static function labelOf(tip:String):String {
        if (tip == null) return "";
        var last:String = tip.charAt(tip.length - 1);
        if (last == "：" || last == ":") return tip.substring(0, tip.length - 1);
        return tip;
    }
}
