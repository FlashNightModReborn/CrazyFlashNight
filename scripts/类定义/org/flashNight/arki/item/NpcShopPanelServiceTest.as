import org.flashNight.aven.test.*;

import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.ui.PanelRequestEnvelope;
import org.flashNight.gesh.number.NumberUtil;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

class org.flashNight.arki.item.NpcShopPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        setup();
        testPermillePricingContract();
        testExactEconomicNumberContract();
        testSnapshotAndGate();
        testMaterialQuantityInvariantAndQuarantine();
        testLegacyIdentityFallbackBoundary();
        testBagTooltip();
        testLegacyCatalogResolution();
        testOpenRequestWire();
        testPanelRequestEnvelopeEscaping();
        testSnapshotResponseWire();
        testTradePreviewResponseWire();
        testBuyRoutesCollections();
        testLargeStackPurchase();
        testOrdinarySellRetired();
        testBatchSell();
        testAtomicTrade();
        testTradeUsesSaleProceeds();
        testSameNamePlainEquipmentSale();
        testOverlappingBulkAndExactSaleRejected();
        testReturnedModsAreAggregated();
        testDuplicateInformationCapacityClassification();
        testMultipleEquipmentPurchaseAndBounds();
        testPurchaseBoundsAtConfiguredLimit();
        testTradeRejectsStaleAndReplay();
        testBuyListenerFaultRestoresExactSnapshot();
        testBatchSellListenerFaultRecovery();
        testRollbackTradeSalesFailureKeepsPostSaleFact();
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
        itemDict["测试手枪"].displayname = "棱镜折射阵列";
        itemDict["测试手枪"].icon = "全光谱棱镜阵列";
        itemDict["测试手枪"].weapontype = "手枪";
        itemDict["测试手枪"].setId = "test_sidearm";
        itemDict["测试手枪"].setName = "测试侧武器套装";
        itemDict["测试手枪"].data = {
            level:1, power:100, interval:400, capacity:8, weight:1, impact:2,
            bullet:"普通子弹", clipname:"手枪通用弹药", split:1, singleshoot:true
        };
        itemDict["测试手枪"].data_2 = {level:2};
        itemDict["测试插件"] = itemData("测试插件", "收集品", "材料", 50);
        ItemUtil.itemDataDict = itemDict;
        ItemUtil.balanceDataDict = {};
        ItemUtil.balanceDataDict["测试手枪"] = {
            schemaVersion:1, formulaFamily:"weapon", workbookVersion:1,
            profiles:{
                data:{
                    dualWield:2, pierce:1, damageType:1, shotgun:1, magPrice:200,
                    weightLayers:0, category:1, formula:1,
                    status:"confirmed", displayEligible:true,
                    inputDigest:"fnv1a32:96ca5e46", auditRef:"weapon:测试手枪:data"
                },
                data_2:{
                    dualWield:2, pierce:1, damageType:1, shotgun:1, magPrice:200,
                    weightLayers:1, category:1, formula:1,
                    status:"confirmed", displayEligible:true,
                    inputDigest:"fnv1a32:2f617c63", auditRef:"weapon:测试手枪:data_2"
                }
            }
        };
        ItemUtil.equipmentDict = {};
        ItemUtil.equipmentDict["测试手枪"] = true;
        ItemUtil.materialDict = {};
        ItemUtil.materialDict["强化石"] = true;
        ItemUtil.materialDict["测试插件"] = true;
        ItemUtil.informationMaxValueDict = {};
        ItemUtil.informationMaxValueDict["解锁情报"] = 1;
        _root.shops = {};
        var shop:Object = {};
        shop[0] = {name:"药剂",purchaseLimit:100};
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
        _root.testNpcShopSaveCount = 0;
        _root.强制存盘 = function():Void { _root.testNpcShopSaveCount++; };
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
        _root.testNpcShopSaveCount = 0;
    }

    private static function testPermillePricingContract():Void {
        check(NumberUtil.floorPermille(18900, 820) == 15498
                && NumberUtil.floorPermille(300, 820) == 246
                && NumberUtil.floorPermille(1001, 850) == 850
                // 有意纠正旧 AS2 二进制浮点路径的 16073 / 1889 偏差。
                && NumberUtil.floorPermille(17100, 940) == 16074
                && NumberUtil.floorPermille(2700, 700) == 1890,
            "permille helper locks exact floor vectors and intentional off-by-one corrections");

        var rejected:Boolean = true;
        var invalid:Array = [
            NumberUtil.floorPermille(NaN, 1000),
            NumberUtil.floorPermille(Infinity, 1000),
            NumberUtil.floorPermille(1.5, 1000),
            NumberUtil.floorPermille(-1, 1000),
            NumberUtil.floorPermille(1, 1.5),
            NumberUtil.floorPermille(1, -1),
            NumberUtil.floorPermille(9007199254740992, 1),
            NumberUtil.floorPermille(NumberUtil.MAX_SAFE_NON_NEGATIVE_INTEGER, 1000)
        ];
        for (var i:Number = 0; i < invalid.length; i++) {
            if (NumberUtil.isSafeNonNegativeInteger(Number(invalid[i]))) rejected = false;
        }
        check(rejected
                && NumberUtil.floorPermille(
                    NumberUtil.MAX_SAFE_NON_NEGATIVE_INTEGER, 1) == 9007199254740,
            "permille helper rejects non-finite, fractional, negative, out-of-range and unsafe products");

        resetOwned();
        ItemUtil.itemDataDict["药剂"].price = 1001;
        _root.主角被动技能.口才 = {启用:true,等级:5};
        _root.金钱 = 10000;
        var snapshot:Object = service().execute("snapshot", {shopId:"测试商店"});
        var bought:Object = service().execute("buy", {
            shopId:"测试商店", catalogIndex:0, quantity:2
        });
        check(snapshot.success && snapshot.v == 1
                && snapshot.buyRatePermille == 850
                && snapshot.buyMultiplier == undefined
                && snapshot.catalog[0].unitPrice == 850
                && bought.success && bought.total == 1701
                && Number(_root.金钱) == 8299,
            "NPC state and commit keep v1 atomic wire replacement and floor after quantity multiplication");
        ItemUtil.itemDataDict["药剂"].price = 100;
        _root.主角被动技能.口才 = {启用:false,等级:0};
    }

    private static function testExactEconomicNumberContract():Void {
        resetOwned();
        _root.金钱 = 5000.5;
        var fractionalState:Object = service().execute("snapshot", {shopId:"测试商店"});
        check(!fractionalState.success && fractionalState.error == "invalid_price",
            "NPC state rejects fractional balance instead of truncating it");

        resetOwned();
        service().execute("snapshot", {shopId:"测试商店"});
        _root.物品栏.背包.add(0, BaseItem.create("药剂", 1));
        var originalSalePrice:Function = _root.物品UI函数.计算售卖总价;
        _root.物品UI函数.计算售卖总价 = function(
                item:Object, quantity:Number):Object {
            return {总价:12.5};
        };
        var fractionalSale:Object = service().execute(
            "batchPreview", {itemNames:["药剂"]});
        _root.物品UI函数.计算售卖总价 = originalSalePrice;
        check(!fractionalSale.success && fractionalSale.error == "invalid_price"
                && _root.物品栏.背包.getItem("0") != null && _root.金钱 == 5000,
            "NPC sale preview fails closed on a fractional authoritative sale result");

        resetOwned();
        _root.金钱 = 50;
        service().execute("snapshot", {shopId:"测试商店"});
        var blocked:Object = service().execute("tradePreview", {
            shopId:"测试商店",
            purchases:[{catalogIndex:0, quantity:1}],
            sales:[]
        });
        check(blocked.success && !blocked.canCommit
                && blocked.blockingError == "insufficient_money"
                && blocked.buyTotal == 100 && blocked.sellTotal == 0
                && blocked.netDelta == -100 && blocked.projectedBalance == -50
                && _root.金钱 == 50,
            "NPC preview preserves signed exact negative balance as a non-committable success");
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
        check(snapshot.catalog[4].weaponType == "手枪" && snapshot.catalog[4].actionType == ""
            && snapshot.catalog[4].setId == "test_sidearm" && snapshot.catalog[4].setName == "测试侧武器套装",
            "existing weapon subtype and set fields projected for automatic grouping");
        check(snapshot.catalog[4].itemName == "测试手枪"
            && snapshot.catalog[4].displayName == "棱镜折射阵列"
            && snapshot.catalog[4].icon == "全光谱棱镜阵列",
            "NPC catalog preserves internal, display, and icon identity roles");
        var summary:Object = snapshot.catalog[4].balanceSummary;
        var wire:String = new LiteJSON().stringify(snapshot.catalog[4]);
        check(summary != undefined && summary.state == "confirmed"
            && summary.weightLayers == 0 && summary.formula == 1 && summary.level == 1
            && wire.indexOf("inputDigest") < 0 && wire.indexOf("rationale") < 0
            && wire.indexOf("workbookVersion") < 0 && wire.indexOf("workbookSha256") < 0
            && wire.indexOf("auditRef") < 0
            && wire.indexOf("WBR-") < 0 && wire.indexOf("SHA256") < 0,
            "NPC 目录即使存在进阶 profile 也固定投影 data 的最小 balanceSummary");
        ItemUtil.itemDataDict["测试手枪"].data.power = 101;
        var staleBalance:Object = service().execute("snapshot",{shopId:"测试商店"});
        check(staleBalance.catalog[4].balanceSummary == undefined,
            "NPC 目录在原始公式输入变化后 fail-closed 移除旧绿色摘要");
        ItemUtil.itemDataDict["测试手枪"].data.power = 100;
        check(snapshot.layout.title == "测试商人" && snapshot.layout.sections[0].entries.length == 5,"developer curated layout projected");
        var denied:Object = service().execute("buy",{shopId:"测试商店",catalogIndex:3,quantity:1});
        check(!denied.success && denied.error == "locked" && _root.金钱 == 5000,"locked buy has no write");
    }

    private static function testMaterialQuantityInvariantAndQuarantine():Void {
        resetOwned();
        var legacyItems:Object = {};
        legacyItems["强化石"] = 1.5;
        _root.收集品栏.材料 = new DictCollection(legacyItems);
        var materials:DictCollection = _root.收集品栏.材料;
        var preserved:Object = materials.toObject();
        check(materials.getValue("强化石") == 0
                && materials.getQuarantinedEntryCount() == 1
                && preserved["强化石"] == 1.5,
            "fractional legacy material is quarantined from runtime but preserved for save projection");

        var invalidAcquire:Boolean = ItemUtil.acquire([{name:"强化石",value:0.5}]);
        check(!invalidAcquire && materials.getValue("强化石") == 0
                && materials.getQuarantinedEntryCount() == 1,
            "fractional material reward fails before mutation and does not destroy quarantine");

        var repaired:Boolean = ItemUtil.acquire([
            {name:"强化石",value:2}, {name:"强化石",value:3}
        ]);
        check(repaired && materials.getValue("强化石") == 5
                && materials.getQuarantinedEntryCount() == 0
                && materials.toObject()["强化石"] == 5,
            "duplicate integer rewards aggregate and explicitly repair the quarantined key");

        var before:Number = materials.getValue("强化石");
        materials.addValue("强化石", 0.5);
        materials.addValue("强化石", 9007199254740991);
        check(materials.getValue("强化石") == before,
            "fractional and overflowing material deltas are rejected without partial mutation");

        materials.getItems()["测试插件"] = Infinity;
        var snapshot:Object = service().execute("snapshot",{shopId:"测试商店"});
        var leaked:Boolean = false;
        for (var i:Number = 0; i < snapshot.views.material.slots.length; i++) {
            if (snapshot.views.material.slots[i].collectionKey == "测试插件") leaked = true;
        }
        check(!leaked && materials.toObject()["测试插件"] == Infinity
                && service().getCollectionQuarantineCount(materials) == 1,
            "collection projection independently filters non-finite direct pollution without deleting it");
    }

    private static function testLegacyIdentityFallbackBoundary():Void {
        resetOwned();
        _root.收集品栏.材料.add("强化石", 1);
        var data:Object = ItemUtil.itemDataDict["强化石"];
        var previousDisplay:Object = data.displayname;
        var previousIcon:Object = data.icon;
        data.displayname = "   ";
        delete data.icon;
        var snapshot:Object = service().execute("snapshot", {shopId:"测试商店"});
        var material:Object = snapshot.views.material.slots[0].item;
        var snapshotWire:String = new LiteJSON().stringify({
            catalog:snapshot.catalog[1], material:material
        });
        data.displayname = 17;
        data.icon = {legacy:"bad"};
        var wrongTypeSnapshot:Object = service().execute("snapshot", {shopId:"测试商店"});
        var wrongTypeMaterial:Object = wrongTypeSnapshot.views.material.slots[0].item;
        check(snapshot.success && snapshot.catalog[1].itemName == "强化石"
            && snapshot.catalog[1].displayName == "强化石"
            && snapshot.catalog[1].icon == "强化石"
            && material.name == "强化石" && material.displayName == "强化石"
            && material.icon == "强化石" && snapshotWire.indexOf("undefined") < 0
            && wrongTypeSnapshot.catalog[1].displayName == "强化石"
            && wrongTypeSnapshot.catalog[1].icon == "强化石"
            && wrongTypeMaterial.displayName == "强化石"
            && wrongTypeMaterial.icon == "强化石",
            "NPC AS2 adapter replaces whitespace, undefined and wrong-type identities");

        var previousTooltip:Object = _root.Web物品注释HTML;
        _root.Web物品注释HTML = function(name:String):Object {
            return {displayname:" Undefined ", descHTML:"desc", introHTML:"intro"};
        };
        var tooltip:Object = service().execute("tooltip", {itemName:"强化石"});
        var tooltipWire:String = new LiteJSON().stringify(tooltip);
        _root.Web物品注释HTML = function(name:String):Object {
            return {displayname:{legacy:"bad"}, descHTML:"desc", introHTML:"intro"};
        };
        var wrongTypeTooltip:Object = service().execute("tooltip", {itemName:"强化石"});
        check(tooltip.success && tooltip.itemName == "强化石"
            && tooltip.displayname == "强化石" && tooltip.iconName == undefined
            && wrongTypeTooltip.displayname == "强化石"
            && tooltipWire.toLowerCase().indexOf("undefined") < 0,
            "NPC AS2 optional-icon tooltip replaces wrapped undefined and wrong-type display without inventing iconName");
        _root.Web物品注释HTML = previousTooltip;
        data.displayname = previousDisplay;
        data.icon = previousIcon;
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
        var balanceAfterFirst:Number = _root.金钱;
        var overflow:Object = service().execute("buy",{shopId:"测试商店",catalogIndex:2,quantity:1});
        check(!overflow.success && overflow.error == "invalid_quantity"
            && _root.金钱 == balanceAfterFirst && _root.收集品栏.情报.getValue("解锁情报") == 1,
            "full information capacity rejects without charging or truncating delivery");
        check(_root.金钱 == 4300 && _root.存档系统.dirtyMark,"buy re-derives price and marks dirty");
    }

    private static function testLargeStackPurchase():Void {
        resetOwned();
        _root.金钱 = 1000000;
        var preview:Object = service().execute("tradePreview",{
            shopId:"测试商店",purchases:[{catalogIndex:1,quantity:4549}],sales:[]
        });
        check(preview.success && preview.canCommit && preview.purchaseLines[0].purchaseLimit == 999999
            && preview.purchaseLines[0].quantity == 4549,
            "unconfigured stack purchase uses technical guard instead of arbitrary 100 quota");
        var commit:Object = service().execute("tradeCommit",{shopId:"测试商店",expectedTradeToken:preview.tradeToken});
        check(commit.success && _root.收集品栏.材料.getValue("强化石") == 4549
            && _root.金钱 == 90200,
            "large NPC purchase charges and delivers the exact same quantity atomically");
    }

    private static function testDuplicateInformationCapacityClassification():Void {
        resetOwned();
        var capacity:Object = service().analyzeTradeCapacity({
            sales:[],
            acquireItems:[{name:"解锁情报",value:1},{name:"解锁情报",value:1}]
        });
        check(!capacity.enough && capacity.error == "destination_full"
            && capacity.missingCollection == 1,
            "capacity analysis aggregates duplicate information rows before classifying the destination error");
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

    private static function testOrdinarySellRetired():Void {
        resetOwned();
        _root.物品栏.背包.add(0,BaseItem.create("药剂",4));
        var balanceBefore:Number = Number(_root.金钱);
        var retired:Object = service().execute("sell",{shopId:"测试商店",quantity:1,
            source:{containerId:"背包",slot:0,expectedLease:"retired"}});
        check(!retired.success && retired.error == "unsupported_cmd"
                && _root.物品栏.背包.getItem("0").value == 4
                && Number(_root.金钱) == balanceBefore,
            "ordinary sell is retired without mutating inventory or balance");
        check(_root.gameCommands["npcShopSell"] == undefined,
            "ordinary sell external game command is removed");
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
            && _root.物品栏.背包.getItem(0).value == 2 && _root.收集品栏.材料.getValue("强化石") == 4
            && _root.testNpcShopSaveCount == 1,
            "trade commit applies one state transition and flushes the complete save exactly once");
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
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
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
        var falsePluginGain:Boolean = false;
        for (var receiptIndex:Number = 0; receiptIndex < receipts.length; receiptIndex++) {
            var effects:Array = receipts[receiptIndex].effects;
            for (var effectIndex:Number = 0; effectIndex < effects.length; effectIndex++) {
                var effect:Object = effects[effectIndex];
                if (effect.direction == "gain" && effect.name == "测试插件") {
                    falsePluginGain = true;
                }
            }
        }
        check(commit.success && _root.收集品栏.材料.getValue("测试插件") == 2
                && !falsePluginGain,
            "trade commit aggregates returned mods without inventing an ownership gain");
        PlayerAssetTransaction.resetForTests();
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
        var wireKeys:Object = {catalogIndex:true,itemName:true,displayName:true,icon:true,
            quantity:true,unitPrice:true,total:true,maxQuantity:true,itemKind:true,
            destinationView:true,purchaseLimit:true,maxAffordable:true,maxByCapacity:true,
            maxPurchasable:true,limitingReason:true};
        var leaksInternalKeys:Boolean = false;
        for (var key:String in preview.purchaseLines[0]) {
            if (wireKeys[key] != true) leaksInternalKeys = true;
        }
        check(!leaksInternalKeys,
            "tradePreview purchase lines project only contract keys for the bridge whitelist");
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
        check(!replay.success && replay.error == "stale_state" && _root.testNpcShopSaveCount == 0,
            "stale and replayed trade tokens never flush a save");
    }

    private static function testBatchSellListenerFaultRecovery():Void {
        resetOwned();
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var bag:ArrayInventory = _root.物品栏.背包;
        bag.add(0, BaseItem.create("药剂", 2));
        var preview:Object = service().execute("batchPreview", {itemNames:["药剂"]});
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__npcShopBatchListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        bag.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemRemoved", function():Void {
            throw "npc_batch_removed_listener_failed";
        });
        var fault = null;
        try {
            service().execute("batchSell", {
                shopId:"测试商店", expectedBatchToken:preview.batchToken
            });
        } catch (error) {
            fault = error;
        }
        var indexes:Array = bag.getIndexes();
        check(fault == "npc_batch_removed_listener_failed"
                && bag.getItem("0") != null && bag.getItem("0").value == 2
                && indexes.length == 1 && indexes[0] == 0
                && _root.金钱 == 5000
                && _root.存档系统.dirtyMark === false
                && PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0
                && service().busy === false,
            "batch sell listener fault restores item/money/dirty and repairs PAT/EventBus/busy state");
        check(receipts.length == 0,
            "exactly restored batch sale discards the partial loss receipt");

        bag.setDispatcher(null);
        var recoveredPreview:Object = service().execute(
            "batchPreview", {itemNames:["药剂"]});
        var recovered:Object = service().execute("batchSell", {
            shopId:"测试商店", expectedBatchToken:recoveredPreview.batchToken
        });
        check(recovered.success === true && bag.getItem("0") == null
                && _root.金钱 == 5050
                && PlayerAssetTransaction.current() == null
                && receipts.length == 1,
            "batch sell listener fault does not contaminate the next transaction");

        bag.setDispatcher(null);
        holder.removeMovieClip();
        PlayerAssetTransaction.resetForTests();
    }

    private static function testBuyListenerFaultRestoresExactSnapshot():Void {
        resetOwned();
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        service().execute("snapshot", {shopId:"测试商店"});
        var bag:ArrayInventory = _root.物品栏.背包;
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__npcShopBuyListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        bag.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemAdded", function():Void {
            throw "npc_buy_added_listener_failed";
        });

        var fault = null;
        try {
            service().execute("buy", {
                shopId:"测试商店", catalogIndex:0, quantity:1
            });
        } catch (error) {
            fault = error;
        }
        check(fault == "npc_buy_added_listener_failed"
                && bag.getItem("0") == null && _root.金钱 == 5000
                && _root.存档系统.dirtyMark === false
                && receipts.length == 0
                && PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "NPC buy listener fault restores delivery/payment/dirty and discards receipt");

        bag.setDispatcher(null);
        var recovered:Object = service().execute("buy", {
            shopId:"测试商店", catalogIndex:0, quantity:1
        });
        check(recovered.success === true && bag.getItem("0") != null
                && bag.getItem("0").value == 1 && _root.金钱 == 4900
                && receipts.length == 1 && receipts[0].effects.length == 2
                && PlayerAssetTransaction.current() == null,
            "NPC buy listener fault leaves the next independent purchase healthy");

        bag.setDispatcher(null);
        holder.removeMovieClip();
        PlayerAssetTransaction.resetForTests();
    }

    private static function testRollbackTradeSalesFailureKeepsPostSaleFact():Void {
        resetOwned();
        var bag:ArrayInventory = _root.物品栏.背包;
        var item:Object = BaseItem.create("药剂", 2);
        bag.add(0, item);
        var revisionBefore:Number = bag.getMutationRevision();
        var plan:Object = {sales:[{
            kind:"bag", collection:bag, key:0, ref:item,
            full:false, oldCount:4
        }]};
        bag._setTransactionWriteFaultHookForTests(function(phase:String):Void {
            if (phase == "mutation") throw "rollback_write_failed";
        });
        var failed:Boolean = service().rollbackTradeSales(plan);
        bag._setTransactionWriteFaultHookForTests(null);
        check(failed === false && bag.getItem("0") === item
                && Number(item.value) == 2
                && bag.getMutationRevision() == revisionBefore,
            "failed trade compensation restores the post-sale fact instead of faking success");

        var restored:Boolean = service().rollbackTradeSales(plan);
        check(restored === true && bag.getItem("0") === item
                && Number(item.value) == 4
                && bag.getMutationRevision() > revisionBefore,
            "retrying trade compensation restores the exact object/count and advances revision");
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
