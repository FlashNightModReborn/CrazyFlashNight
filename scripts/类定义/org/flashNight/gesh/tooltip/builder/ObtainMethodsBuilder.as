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

        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (!index.isIndexBuilt()) return result;

        var records:Array = index.getObtainRecords(itemName);
        if (!records || records.length == 0) return result;

        var crafts:Array = [];
        var shops:Array = [];
        var kshops:Array = [];
        var stageDrops:Array = [];
        var enemyDrops:Array = [];
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
                    } else {
                        enemyDrops.push(rec);
                    }
                    break;
                case ItemObtainIndex.KIND_QUEST:
                    quests.push(rec);
                    break;
            }
        }

        if (crafts.length == 0 && shops.length == 0 && kshops.length == 0 &&
            stageDrops.length == 0 && enemyDrops.length == 0 && quests.length == 0) {
            return result;
        }

        result.push(TooltipFormatter.br());
        result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>");
        result.push(TooltipConstants.LBL_OBTAIN_METHODS);
        result.push("</FONT>");
        result.push(TooltipFormatter.br());

        var maxCrafts:Number = TooltipConstants.OBTAIN_MAX_CRAFTS;
        var craftCount:Number = Math.min(crafts.length, maxCrafts);
        for (var c:Number = 0; c < craftCount; c++) {
            var craft:Object = crafts[c];
            result.push("  <FONT COLOR='" + TooltipConstants.COL_CRAFT + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_CRAFT);
            result.push("</FONT>");
            result.push(craft.category);
            if (craft.price > 0 || craft.kprice > 0) {
                result.push(" (");
                if (craft.price > 0) result.push("$" + craft.price);
                if (craft.price > 0 && craft.kprice > 0) result.push(" + ");
                if (craft.kprice > 0) result.push(craft.kprice + "K");
                result.push(")");
            }
            result.push(TooltipFormatter.br());
        }
        if (crafts.length > maxCrafts) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_CRAFT + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_CRAFT);
            result.push("</FONT>");
            result.push(TooltipConstants.TIP_ETC + (crafts.length - maxCrafts) + TooltipConstants.TIP_OBTAIN_MORE);
            result.push(TooltipFormatter.br());
        }

        if (shops.length > 0) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_SHOP + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_SHOP);
            result.push("</FONT>");
            var maxShops:Number = TooltipConstants.OBTAIN_MAX_SHOPS;
            var shopNames:Array = [];
            var shopCount:Number = Math.min(shops.length, maxShops);
            for (var s:Number = 0; s < shopCount; s++) {
                shopNames.push(shops[s].npc);
            }
            result.push(shopNames.join("、"));
            if (shops.length > maxShops) {
                result.push(TooltipConstants.TIP_ETC + (shops.length - maxShops) + TooltipConstants.TIP_OBTAIN_MORE);
            }
            result.push(TooltipFormatter.br());
        }

        var maxKshops:Number = TooltipConstants.OBTAIN_MAX_KSHOPS;
        var kshopCount:Number = Math.min(kshops.length, maxKshops);
        for (var k:Number = 0; k < kshopCount; k++) {
            var kitem:Object = kshops[k];
            result.push("  <FONT COLOR='" + TooltipConstants.COL_KSHOP + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_KSHOP);
            result.push("</FONT>");
            result.push(kitem.type + " (" + kitem.priceK + "K)");
            result.push(TooltipFormatter.br());
        }
        if (kshops.length > maxKshops) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_KSHOP + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_KSHOP);
            result.push("</FONT>");
            result.push(TooltipConstants.TIP_ETC + (kshops.length - maxKshops) + TooltipConstants.TIP_OBTAIN_MORE);
            result.push(TooltipFormatter.br());
        }

        if (stageDrops.length > 0) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_STAGE + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_STAGE);
            result.push("</FONT>");
            var maxStages:Number = TooltipConstants.OBTAIN_MAX_STAGES;
            var stageNames:Array = [];
            var stageCount:Number = Math.min(stageDrops.length, maxStages);
            for (var st:Number = 0; st < stageCount; st++) {
                stageNames.push(stageDrops[st].stageName);
            }
            result.push(stageNames.join("、"));
            if (stageDrops.length > maxStages) {
                result.push(TooltipConstants.TIP_ETC + (stageDrops.length - maxStages) + TooltipConstants.TIP_OBTAIN_MORE);
            }
            result.push(TooltipFormatter.br());
        }

        if (enemyDrops.length > 0) {
            result.push("  <FONT COLOR='" + TooltipConstants.COL_DROP_ENEMY + "'>");
            result.push(TooltipConstants.TIP_OBTAIN_ENEMY);
            result.push("</FONT>");
            var maxEnemies:Number = TooltipConstants.OBTAIN_MAX_ENEMIES;
            var enemyNames:Array = [];
            var enemyCount:Number = Math.min(enemyDrops.length, maxEnemies);
            for (var e:Number = 0; e < enemyCount; e++) {
                var enemyType:String = enemyDrops[e].enemyType;
                var displayName:String = TooltipBridge.getEnemyDisplayName(enemyType);
                enemyNames.push(displayName);
            }
            result.push(enemyNames.join("、"));
            if (enemyDrops.length > maxEnemies) {
                result.push(TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies) + TooltipConstants.TIP_OBTAIN_MORE);
            }
            result.push(TooltipFormatter.br());
        }

        return result;
    }
}
