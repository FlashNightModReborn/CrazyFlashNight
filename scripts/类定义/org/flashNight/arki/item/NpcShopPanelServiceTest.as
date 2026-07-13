import org.flashNight.aven.test.*;

import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.ui.PanelRequestEnvelope;

class org.flashNight.arki.item.NpcShopPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        setup();
        testSnapshotAndGate();
        testBagTooltip();
        testLegacyCatalogResolution();
        testOpenRequestWire();
        testPanelRequestEnvelopeEscaping();
        testSnapshotResponseWire();
        testTradePreviewResponseWire();
        testBuyRoutesCollections();
        testLeaseBoundSell();
        testBatchSell();
        testAtomicTrade();
        testTradeUsesSaleProceeds();
        testSameNamePlainEquipmentSale();
        testOverlappingBulkAndExactSaleRejected();
        testReturnedModsAreAggregated();
        testMultipleEquipmentPurchaseAndBounds();
        testPurchaseBoundsAtConfiguredLimit();
        testTradeRejectsStaleAndReplay();
        trace("NpcShopPanelServiceTest Tests Passed: " + passed);
        trace("NpcShopPanelServiceTest Tests Failed: " + failed);
    }

    private static function setup():Void {
        var itemDict:Object = {};
        itemDict["药剂"] = itemData("药剂", "消耗品", "药剂", 100);
        itemDict["强化石"] = itemData("强化石", "收集品", "材料", 200);
        itemDict["解锁情报"] = itemData("解锁情报", "收集品", "情报", 300);
        itemDict["门槛商品"] = itemData("门槛商品", "消耗品", "消耗品", 400);
        itemDict["测试手枪"] = itemData("测试手枪", "武器", "手枪", 1000);
        itemDict["测试手枪"].weapontype = "手枪";
        itemDict["测试插件"] = itemData("测试插件", "收集品", "材料", 50);
        ItemUtil.itemDataDict = itemDict;
        ItemUtil.equipmentDict = {};
        ItemUtil.equipmentDict["测试手枪"] = true;
        ItemUtil.materialDict = {};
        ItemUtil.materialDict["强化石"] = true;
        ItemUtil.materialDict["测试插件"] = true;
        ItemUtil.informationMaxValueDict = {};
        ItemUtil.informationMaxValueDict["解锁情报"] = 1;
        _root.shops = {};
        var shop:Object = {};
        shop[0] = "药剂";
        shop[1] = "强化石";
        shop[2] = "解锁情报";
        shop[3] = {name:"门槛商品",requiredInfo:"解锁情报"};
        shop[4] = "测试手枪";
        _root.shops["测试商店"] = shop;
        _root.shops["另一商店"] = shop;
        _root.shopLayouts = {};
        _root.shopLayouts["测试商店"] = {title:"测试商人",defaultSection:"supplies",sections:[{id:"supplies",label:"补给",entries:[0,1,2,3,4]}]};
        _root.物品栏 = {};
        _root.物品栏.背包 = new ArrayInventory(null,50);
        _root.物品栏.药剂栏 = new ArrayInventory(null,4);
        _root.物品栏.仓库 = new ArrayInventory(null,10);
        _root.物品栏.战备箱 = new ArrayInventory(null,10);
        _root.收集品栏 = {};
        _root.收集品栏.材料 = new DictCollection(null);
        _root.收集品栏.情报 = new DictCollection(null);
        _root.主角被动技能 = {};
        _root.主角被动技能.口才 = {启用:false,等级:0};
        _root.存档系统 = {dirtyMark:false};
        _root.soundEffectManager = {};
        _root.soundEffectManager.playSound = function():Void {};
        _root.Web物品注释HTML = function(name:String):Object { return {displayname:name,descHTML:"desc",introHTML:"intro"}; };
        _root.物品UI函数 = {};
        _root.物品UI函数.计算售卖总价 = function(item:Object,quantity:Number):Object {
            return {总价:Math.floor(Number(ItemUtil.getRawItemData(item.name).price)*quantity*0.25)};
        };
        _root.物品UI函数.是否普通物品 = function(item:Object):Boolean {
            if (item == null) return false;
            if (!ItemUtil.isEquipment(item.name)) return true;
            var value:Object = item.value;
            return value == null || ((value.level == undefined || Number(value.level) <= 1)
                && value.tier == undefined && (!(value.mods instanceof Array) || value.mods.length == 0));
        };
        InventoryPanelService.install();
    }

    private static function resetOwned():Void {
        _root.物品栏.背包.setItems({});
        _root.物品栏.药剂栏.setItems({});
        _root.收集品栏.材料.setItems({});
        _root.收集品栏.情报.setItems({});
        _root.金钱 = 5000;
        _root.存档系统.dirtyMark = false;
    }

    private static function testSnapshotAndGate():Void {
        resetOwned();
        _root.物品栏.背包.add(0,BaseItem.create("药剂",2));
        _root.收集品栏.材料.add("强化石",3);
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        check(snapshot.success && snapshot.catalog.length == 5,"projects sparse catalog");
        check(snapshot.views.bag == undefined && snapshot.views.material.containerId == "材料"
            && snapshot.views.intelligence.containerId == "情报","NPC snapshot owns collections while bag stays in inventory domain");
        var second:Object = service().execute("snapshot",{shopId:"测试商店"});
        check(snapshot.views.material.slots[0].slotLease == second.views.material.slots[0].slotLease,
            "unchanged collection resource lease survives repeated read snapshots");
        check(snapshot.catalog[3].locked == true,"required information gate projected");
        check(snapshot.catalog[4].weaponType == "手枪" && snapshot.catalog[4].actionType == "","existing weapon subtype fields projected for automatic grouping");
        check(snapshot.layout.title == "测试商人" && snapshot.layout.sections[0].entries.length == 5,"developer curated layout projected");
        var denied:Object = service().execute("buy",{shopId:"测试商店",catalogIndex:3,quantity:1});
        check(!denied.success && denied.error == "locked" && _root.金钱 == 5000,"locked buy has no write");
    }

    private static function testBagTooltip():Void {
        resetOwned();
        _root.物品栏.背包.add(0, BaseItem.create("测试手枪", 1));
        var before:Object = bagView();
        service().execute("snapshot", {shopId:"测试商店"});
        var after:Object = bagView();
        var lease:String = before.slots[0].slotLease;
        var tooltip:Object = service().execute("tooltip", {
            source:{containerId:"背包", slot:0, expectedLease:lease}
        });
        check(lease == after.slots[0].slotLease,
            "parallel inventory and NPC read snapshots preserve the same bag lease");
        check(tooltip.success && tooltip.introHTML != undefined && tooltip.descHTML != undefined,
            "bag tooltip resolves through inventory lease with v=1");
    }

    private static function testBuyRoutesCollections():Void {
        resetOwned();
        var material:Object = service().execute("buy",{shopId:"测试商店",catalogIndex:1,quantity:2});
        check(material.success && material.destinationView == "material" && _root.收集品栏.材料.getValue("强化石") == 2,"material buy routes to material view");
        var information:Object = service().execute("buy",{shopId:"测试商店",catalogIndex:2,quantity:1});
        check(information.success && information.destinationView == "intelligence" && _root.收集品栏.情报.getValue("解锁情报") == 1,"information buy routes to intelligence view");
        check(_root.金钱 == 4300 && _root.存档系统.dirtyMark,"buy re-derives price and marks dirty");
    }

    private static function testLegacyCatalogResolution():Void {
        var uniqueCatalog:Object = {};
        uniqueCatalog[0] = "药剂";
        _root.shops["旧入口商店"] = uniqueCatalog;
        check(service().resolveShopIdByCatalog(uniqueCatalog) == "旧入口商店","legacy catalog identity resolves authoritative shop id");
        delete _root.shops["旧入口商店"];
    }

    private static function testOpenRequestWire():Void {
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean { this.sent = message; return true; };
        var opened:Boolean = _root.gameCommands["openNpcShop"]({shopId:"测试商店",source:"world_npc_dialogue"});
        check(opened && String(_root.server.sent) == '{"task":"panel_request","panel":"npcshop","source":"world_npc_dialogue","initData":{"shopId":"测试商店"}}',"open entry sends concrete panel_request wire payload");
    }

    private static function testPanelRequestEnvelopeEscaping():Void {
        var source:String = "source\\line\nnext";
        var shopId:String = "带\"引号\\路径\n商店";
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "npcshop",
            source,
            [],
            [{name:"shopId", value:shopId}]
        );
        var parsed:Object = new JSON().parse(payload);
        check(parsed.panel == "npcshop" && parsed.source == source && parsed.initData.shopId == shopId,
            "panel request envelope escapes quotes, slashes and controls");
    }

    private static function testSnapshotResponseWire():Void {
        resetOwned();
        _root.server.sent = null;
        _root.UI系统.商城WebView = {json:new LiteJSON()};
        _root.gameCommands["npcShopSnapshot"]({shopId:"测试商店",callId:7});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.task == "npcshop_response" && response.callId == 7 && response.success == true
            && response.catalog.length == 5 && response.views.bag == undefined
            && response.views.material.containerId == "材料","snapshot handler sends parseable domain-scoped response wire");
    }

    private static function testTradePreviewResponseWire():Void {
        resetOwned();
        _root.物品栏.背包.add(0,BaseItem.create("药剂",2));
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var bag:Object = bagView();
        _root.server.sent = null;
        _root.gameCommands["npcShopTradePreview"]({
            shopId:"测试商店",callId:8,purchases:[],
            sales:[{quantity:1,source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}}]
        });
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.task == "npcshop_response" && response.callId == 8 && response.success
            && String(response.tradeToken).indexOf("npctrade") == 0,"trade preview handler sends parseable token wire");
        check(response.saleLines[0].sourceIdentity == "bag:0" && response.saleLines[0].ref == undefined
            && response.saleLines[0].collection == undefined,"trade response excludes internal inventory references");
    }

    private static function testLeaseBoundSell():Void {
        resetOwned();
        _root.物品栏.背包.add(0,BaseItem.create("药剂",4));
        _root.收集品栏.材料.add("强化石",5);
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var bag:Object = bagView();
        var wrongShop:Object = service().execute("sell",{shopId:"另一商店",quantity:1,source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}});
        check(!wrongShop.success && wrongShop.error == "stale_state" && _root.物品栏.背包.getItem("0").value == 4,"owned lease is bound to active shop session");
        var bagSell:Object = service().execute("sell",{shopId:"测试商店",quantity:2,source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}});
        check(bagSell.success && _root.物品栏.背包.getItem("0").value == 2 && _root.金钱 == 5050,"bag partial sell uses inventory lease");
        var materialSell:Object = service().execute("sell",{shopId:"测试商店",quantity:3,source:{viewId:"material",key:"强化石",expectedLease:bagSell.views.material.slots[0].slotLease}});
        check(materialSell.success && _root.收集品栏.材料.getValue("强化石") == 2 && _root.金钱 == 5200,"material sell uses collection lease");
        var forbidden:Object = service().execute("sell",{shopId:"测试商店",quantity:1,source:{viewId:"intelligence",key:"解锁情报",expectedLease:"fake"}});
        check(!forbidden.success && forbidden.error == "sell_forbidden","intelligence view is read only");
    }

    private static function testBatchSell():Void {
        resetOwned();
        _root.物品栏.背包.add(0,BaseItem.create("药剂",2));
        _root.物品栏.背包.add(1,BaseItem.create("药剂",3));
        var preview:Object = service().execute("batchPreview",{itemNames:["药剂"]});
        check(preview.success && preview.totalQuantity == 5 && preview.totalMoney == 125,"batch preview scans same-name stacks");
        var commit:Object = service().execute("batchSell",{shopId:"测试商店",expectedBatchToken:preview.batchToken});
        check(commit.success && _root.物品栏.背包.getItem("0") == null && _root.物品栏.背包.getItem("1") == null && _root.金钱 == 5125,"opaque batch token commits once");
        var replay:Object = service().execute("batchSell",{shopId:"测试商店",expectedBatchToken:preview.batchToken});
        check(!replay.success && replay.error == "stale_state","batch token replay rejected");
    }

    private static function testAtomicTrade():Void {
        resetOwned();
        _root.物品栏.背包.add(0,BaseItem.create("药剂",4));
        _root.收集品栏.材料.add("强化石",5);
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var bag:Object = bagView();
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",
            purchases:[{catalogIndex:1,quantity:2}],
            sales:[
                {quantity:2,source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}},
                {quantity:3,source:{viewId:"material",key:"强化石",expectedLease:snapshot.views.material.slots[0].slotLease}}
            ]
        });
        check(preview.success && preview.canCommit && preview.buyTotal == 400 && preview.sellTotal == 200
            && preview.projectedBalance == 4800,"trade preview derives both sides and projected balance");
        var commit:Object = service().execute("tradeCommit",{shopId:"测试商店",expectedTradeToken:preview.tradeToken});
        check(commit.success && commit.operation == "tradeCommit" && _root.金钱 == 4800
            && _root.物品栏.背包.getItem(0).value == 2 && _root.收集品栏.材料.getValue("强化石") == 4,
            "trade commit applies purchase and sales as one state transition");
    }

    private static function testTradeUsesSaleProceeds():Void {
        resetOwned();
        _root.金钱 = 0;
        _root.物品栏.背包.add(0,BaseItem.create("药剂",4));
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var bag:Object = bagView();
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",
            purchases:[{catalogIndex:0,quantity:1}],
            sales:[{quantity:4,source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}}]
        });
        check(preview.success && preview.canCommit && preview.buyTotal == 100 && preview.sellTotal == 100,
            "atomic preview allows selected sales to finance purchases");
        var commit:Object = service().execute("tradeCommit",{shopId:"测试商店",expectedTradeToken:preview.tradeToken});
        check(commit.success && _root.金钱 == 0 && _root.物品栏.背包.getItem(0).name == "药剂"
            && _root.物品栏.背包.getItem(0).value == 1,"sale-freed slot is reusable by same transaction");
    }

    private static function testSameNamePlainEquipmentSale():Void {
        resetOwned();
        _root.物品栏.背包.add(0,BaseItem.create("测试手枪",1));
        _root.物品栏.背包.add(1,BaseItem.create("测试手枪",1));
        var protectedItem:Object = BaseItem.create("测试手枪",3);
        _root.物品栏.背包.add(2,protectedItem);
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var bag:Object = bagView();
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",purchases:[],
            sales:[{scope:"same_name",policy:"plain_only",source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}}]
        });
        check(preview.success && preview.saleLines[0].scope == "same_name"
            && preview.saleLines[0].matchedCount == 3 && preview.saleLines[0].eligibleCount == 2
            && preview.saleLines[0].protectedCount == 1 && preview.sellTotal == 500,
            "same-name preview expands plain equipment and protects enhanced instances");
        var commit:Object = service().execute("tradeCommit",{shopId:"测试商店",expectedTradeToken:preview.tradeToken});
        check(commit.success && _root.物品栏.背包.getItem(0) == null && _root.物品栏.背包.getItem(1) == null
            && _root.物品栏.背包.getItem(2) === protectedItem && _root.金钱 == 5500,
            "same-name commit sells every eligible instance and retains protected equipment");
    }

    private static function testOverlappingBulkAndExactSaleRejected():Void {
        resetOwned();
        var first:Object = BaseItem.create("测试手枪",1);
        var second:Object = BaseItem.create("测试手枪",1);
        _root.物品栏.背包.add(0,first);
        _root.物品栏.背包.add(1,second);
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var bag:Object = bagView();
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",purchases:[],
            sales:[
                {scope:"same_name",policy:"plain_only",source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}},
                {scope:"slot",quantity:1,source:{containerId:"背包",slot:1,expectedLease:bag.slots[1].slotLease}}
            ]
        });
        check(!preview.success && preview.error == "duplicate_line","expanded bulk sale rejects an overlapping exact slot");
        check(_root.物品栏.背包.getItem(0) === first && _root.物品栏.背包.getItem(1) === second
            && _root.金钱 == 5000,"overlapping sale rejection leaves inventory and money unchanged");
    }

    private static function testReturnedModsAreAggregated():Void {
        resetOwned();
        var first:Object = BaseItem.create("测试手枪",1);
        var second:Object = BaseItem.create("测试手枪",1);
        first.value.mods = ["测试插件"];
        second.value.mods = ["测试插件"];
        _root.物品栏.背包.add(0,first);
        _root.物品栏.背包.add(1,second);
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var bag:Object = bagView();
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",purchases:[],
            sales:[
                {scope:"slot",quantity:1,source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}},
                {scope:"slot",quantity:1,source:{containerId:"背包",slot:1,expectedLease:bag.slots[1].slotLease}}
            ]
        });
        var commit:Object = service().execute("tradeCommit",{shopId:"测试商店",expectedTradeToken:preview.tradeToken});
        check(commit.success && _root.收集品栏.材料.getValue("测试插件") == 2,
            "trade commit aggregates identical returned mods without loss");
    }

    private static function testMultipleEquipmentPurchaseAndBounds():Void {
        resetOwned();
        for (var slot:Number = 0; slot < 48; slot++) {
            _root.物品栏.背包.add(slot,BaseItem.create("药剂",1));
        }
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",purchases:[{catalogIndex:4,quantity:3}],sales:[]
        });
        check(preview.success && !preview.canCommit && preview.blockingError == "inventory_full"
            && preview.requiredSlots == 3 && preview.availableSlots == 2 && preview.missingSlots == 1,
            "equipment preview returns authoritative required and missing slots");
        check(preview.purchaseLines[0].purchaseLimit == 50 && preview.purchaseLines[0].maxByCapacity == 2
            && preview.purchaseLines[0].maxAffordable == 5 && preview.purchaseLines[0].maxPurchasable == 2,
            "equipment preview returns authoritative purchase maxima");
        var feasible:Object = service().execute("tradePreview",{
            shopId:"测试商店",purchases:[{catalogIndex:4,quantity:2}],sales:[]
        });
        var commit:Object = service().execute("tradeCommit",{shopId:"测试商店",expectedTradeToken:feasible.tradeToken});
        check(commit.success && _root.物品栏.背包.getItem(48).name == "测试手枪"
            && _root.物品栏.背包.getItem(49).name == "测试手枪"
            && typeof _root.物品栏.背包.getItem(48).value == "object"
            && typeof _root.物品栏.背包.getItem(49).value == "object",
            "equipment quantity expands into independent acquired instances");
    }

    private static function testPurchaseBoundsAtConfiguredLimit():Void {
        resetOwned();
        _root.金钱 = 100000;
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",purchases:[{catalogIndex:0,quantity:1}],sales:[]
        });
        check(preview.success && preview.purchaseLines[0].purchaseLimit == 100
            && preview.purchaseLines[0].maxAffordable == 100
            && preview.purchaseLines[0].maxByCapacity == 100
            && preview.purchaseLines[0].maxPurchasable == 100,
            "purchase bound search preserves the configured upper limit");
    }

    private static function testTradeRejectsStaleAndReplay():Void {
        resetOwned();
        _root.物品栏.背包.add(0,BaseItem.create("药剂",4));
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var bag:Object = bagView();
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",purchases:[],
            sales:[{quantity:2,source:{containerId:"背包",slot:0,expectedLease:bag.slots[0].slotLease}}]
        });
        _root.物品栏.背包.addValue(0,1);
        var stale:Object = service().execute("tradeCommit",{shopId:"测试商店",expectedTradeToken:preview.tradeToken});
        check(!stale.success && stale.error == "stale_state" && _root.物品栏.背包.getItem(0).value == 5 && _root.金钱 == 5000,
            "trade commit rejects changed source without partial write");
        var replay:Object = service().execute("tradeCommit",{shopId:"测试商店",expectedTradeToken:preview.tradeToken});
        check(!replay.success && replay.error == "stale_state","trade token is consumed after one commit attempt");
    }

    private static function service():Object { return _root.UI系统.NPC商店WebView; }
    private static function bagView():Object {
        var response:Object = InventoryPanelService.execute("snapshot", {
            v:1, requests:[{containerId:"背包", offset:0, limit:50, filterKey:"all"}]
        });
        return response.snapshots[0];
    }
    private static function itemData(name:String,type:String,useName:String,price:Number):Object { return {name:name,displayname:name,icon:name,type:type,use:useName,price:price,data:{level:1}}; }
    private static function check(value:Boolean,label:String):Void { if(value){passed++;trace("[PASS] "+label);}else{failed++;trace("[FAIL] "+label);} }
}
