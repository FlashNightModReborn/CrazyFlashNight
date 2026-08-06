import org.flashNight.aven.test.*;

import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;

class org.flashNight.arki.item.KShopCheckoutServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var callSeq:Number = 0;

    public static function runAllTests():Void {
        setup();
        testCatalogProjection();
        testIdentityTripleProjection();
        testLegacyIdentityFallbackBoundary();
        testDirectDelivery();
        testExactBalance();
        testLargeStackQuantity();
        testMaterialRouting();
        testInformationCommitRefreshesCatalog();
        testInformationCapacityIsZeroWrite();
        testLegacyCheckoutUsesAuthority();
        testLegacyCheckoutDirectDelivery();
        testLegacyInformationClaimIgnoresBagVacancy();
        testInventoryFullIsZeroWrite();
        testPriceChangeRejectsCommit();
        testTokenReplayRejected();
        testMalformedPreviewInvalidatesToken();
        trace("KShopCheckoutServiceTest Tests Passed: " + passed);
        trace("KShopCheckoutServiceTest Tests Failed: " + failed);
    }

    private static function setup():Void {
        var itemDict:Object = {};
        itemDict["药剂"] = itemData("药剂", "消耗品", "药剂", 100);
        itemDict["强化石"] = itemData("强化石", "收集品", "材料", 200);
        itemDict["测试手枪"] = itemData("测试手枪", "武器", "手枪", 1000);
        itemDict["测试情报"] = itemData("测试情报", "收集品", "情报", 100);
        itemDict["药剂"].displayname = "战地恢复剂";
        itemDict["药剂"].icon = "恢复剂专用图标";
        itemDict["测试手枪"].displayname = "训练用短铳";
        itemDict["测试手枪"].icon = "训练短铳专用图标";
        itemDict["测试手枪"].weapontype = "手枪";
        itemDict["测试手枪"].setId = "test_sidearm";
        itemDict["测试手枪"].setName = "测试侧武器套装";
        itemDict["测试手枪"].data = {
            level:1, power:100, interval:400, capacity:8, weight:1, impact:2,
            bullet:"普通子弹", clipname:"手枪通用弹药", split:1, singleshoot:true
        };
        itemDict["测试手枪"].data_2 = {level:2};
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
        ItemUtil.informationMaxValueDict = {};
        ItemUtil.informationMaxValueDict["测试情报"] = 1;

        _root.kshop_list = [
            // 生产 data/kshop 保留历史字符串 price；AS2 canonical 投影必须统一成 Number。
            {id:"potion", item:"药剂", type:"医疗专柜", price:"40"},
            {id:"material", item:"强化石", type:"研究专柜", price:25},
            {id:"pistol", item:"测试手枪", type:"训练专柜", price:500},
            {id:"intel", item:"测试情报", type:"研究专柜", price:100}
        ];
        _root.等级 = 20;
        _root.主角被动技能 = {逆向:{启用:false, 等级:0}};
        _root.根据物品名查找全部属性 = function(name:String):Object {
            var data:Object = ItemUtil.getRawItemData(name);
            if (data == undefined) return undefined;
            var attrs:Array = [];
            attrs[1] = data.icon;
            attrs[2] = data.type;
            attrs[3] = data.use;
            attrs[9] = data.data.level;
            return attrs;
        };
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            return true;
        };
        _root.server.sendServerMessage = function(message:String):Void {};
        _root.soundEffectManager = {playSound:function(name:String):Void {}};
        _root.存档系统 = {dirtyMark:false};
        _root.强制存盘 = function():Void { _root.testKShopSaveCount++; };
    }

    private static function resetState():Void {
        _root.物品栏 = {};
        _root.物品栏.背包 = new ArrayInventory(null, 50);
        _root.物品栏.药剂栏 = new ArrayInventory(null, 4);
        _root.物品栏.仓库 = new ArrayInventory(null, 10);
        _root.物品栏.战备箱 = new ArrayInventory(null, 10);
        _root.收集品栏 = {};
        _root.收集品栏.材料 = new DictCollection(null);
        _root.收集品栏.情报 = new DictCollection(null);
        _root.虚拟币 = 1000;
        _root.商城购物车 = [["legacy-cart"]];
        _root.商城已购买物品 = [["legacy", "药剂", "消耗品", 40, 1]];
        _root.testKShopSaveCount = 0;
        _root.UI系统.商城WebView.checkoutPlan = null;
        _root.kshop_list[0].price = "40";
        _root.server.sent = null;
    }

    private static function testCatalogProjection():Void {
        resetState();
        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.success && typeof(response.catalog[0].price) == "number"
            && response.catalog[0].price == 40 && response.catalog[2].type == "训练专柜"
            && response.catalog[2].majorType == "武器" && response.catalog[2].subType == "手枪"
            && response.catalog[2].weaponType == "手枪" && response.catalog[2].actionType == ""
            && response.catalog[2].setId == "test_sidearm" && response.catalog[2].setName == "测试侧武器套装",
            "catalog normalizes production string price and projects taxonomy/set metadata independently");
        var summary:Object = response.catalog[2].balanceSummary;
        var wire:String = String(_root.server.sent);
        check(summary != undefined && summary.state == "confirmed"
            && summary.weightLayers == 0 && summary.formula == 1 && summary.level == 1
            && wire.indexOf("inputDigest") < 0 && wire.indexOf("rationale") < 0
            && wire.indexOf("workbookVersion") < 0 && wire.indexOf("workbookSha256") < 0
            && wire.indexOf("auditRef") < 0
            && wire.indexOf("WBR-") < 0 && wire.indexOf("SHA256") < 0,
            "K 点目录即使存在进阶 profile 也固定投影 data 的最小 balanceSummary");

        ItemUtil.itemDataDict["测试手枪"].data.power = 101;
        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var stale:Object = new LiteJSON().parse(String(_root.server.sent));
        check(stale.catalog[2].balanceSummary == undefined,
            "K 点目录在原始公式输入变化后 fail-closed 移除旧绿色摘要");
        ItemUtil.itemDataDict["测试手枪"].data.power = 100;
    }

    private static function testIdentityTripleProjection():Void {
        resetState();
        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var bulk:Object = new LiteJSON().parse(String(_root.server.sent));
        var catalog:Object = bulk.catalog[2];
        var purchased:Object = bulk.purchasedView[0];
        check(catalog.item == "测试手枪" && catalog.displayname == "训练用短铳"
            && catalog.icon == "训练短铳专用图标"
            && catalog.item != catalog.displayname && catalog.item != catalog.icon
            && catalog.displayname != catalog.icon,
            "catalog keeps internal, display and icon identities independent");
        check(purchased.purchasedIdx == 0 && purchased.item == "药剂"
            && purchased.displayname == "战地恢复剂"
            && purchased.icon == "恢复剂专用图标" && purchased.quantity == 1
            && purchased.item != purchased.displayname && purchased.item != purchased.icon
            && purchased.displayname != purchased.icon,
            "legacy purchased storage receives an index-bound all-distinct display projection");

        var preview:Object = requestPreview([{idx:2, qty:1}]);
        var line:Object = preview.purchaseLines[0];
        check(line.catalogIndex == 2 && line.itemName == "测试手枪"
            && line.displayName == "训练用短铳" && line.icon == "训练短铳专用图标"
            && line.success == undefined,
            "checkout preview binds the request selector to the same all-distinct identity triple");
    }

    private static function testLegacyIdentityFallbackBoundary():Void {
        resetState();
        var data:Object = ItemUtil.itemDataDict["强化石"];
        var previousDisplay:Object = data.displayname;
        var previousIcon:Object = data.icon;
        data.displayname = "   ";
        data.icon = " Undefined ";

        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var bulkWire:String = String(_root.server.sent);
        var bulk:Object = new LiteJSON().parse(bulkWire);
        var catalog:Object = bulk.catalog[1];
        var preview:Object = requestPreview([{idx:1, qty:1}]);
        var line:Object = preview.purchaseLines[0];
        data.displayname = 17;
        data.icon = {legacy:"bad"};
        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var wrongTypeBulk:Object = new LiteJSON().parse(String(_root.server.sent));
        var wrongTypeCatalog:Object = wrongTypeBulk.catalog[1];
        check(catalog.item == "强化石" && catalog.displayname == "强化石"
            && catalog.icon == "强化石" && line.itemName == "强化石"
            && line.displayName == "强化石" && line.icon == "强化石"
            && wrongTypeCatalog.displayname == "强化石"
            && wrongTypeCatalog.icon == "强化石"
            && bulkWire.toLowerCase().indexOf("undefined") < 0,
            "AS2 KShop adapter replaces whitespace, wrapped-case undefined and wrong-type identities");

        var previousTooltip:Object = _root.Web物品注释HTML;
        _root.Web物品注释HTML = function(itemName:String):Object {
            return {displayname:"\t", descHTML:"desc", introHTML:"intro"};
        };
        delete data.icon;
        callSeq++;
        _root.server.sent = null;
        _root.gameCommands["shopTooltip"]({callId:callSeq, idx:1});
        var tooltipWire:String = String(_root.server.sent);
        var tooltip:Object = new LiteJSON().parse(tooltipWire);
        _root.Web物品注释HTML = function(itemName:String):Object {
            return {displayname:{legacy:"bad"}, descHTML:"desc", introHTML:"intro"};
        };
        data.icon = {legacy:"bad"};
        callSeq++;
        _root.server.sent = null;
        _root.gameCommands["shopTooltip"]({callId:callSeq, idx:1});
        var wrongTypeTooltip:Object = new LiteJSON().parse(String(_root.server.sent));
        check(tooltip.success && tooltip.itemName == "强化石"
            && tooltip.displayname == "强化石" && tooltip.iconName == "强化石"
            && wrongTypeTooltip.displayname == "强化石"
            && wrongTypeTooltip.iconName == "强化石"
            && tooltipWire.indexOf("undefined") < 0,
            "AS2 KShop tooltip adapter replaces whitespace, undefined and wrong-type identities");

        _root.Web物品注释HTML = previousTooltip;
        data.displayname = previousDisplay;
        data.icon = previousIcon;
    }

    private static function testDirectDelivery():Void {
        resetState();
        var beforePurchased:Object = _root.商城已购买物品;
        var preview:Object = requestPreview([{idx:0, qty:2}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        var item:Object = _root.物品栏.背包.getItem(0);
        check(preview.success && preview.canCommit && preview.total == 80 && preview.projectedBalance == 920,
            "preview derives authoritative K-point total");
        check(commit.success && commit.newBalance == 920 && item.name == "药剂" && item.value == 2,
            "commit delivers stack directly and deducts K points");
        check(_root.商城购物车.length == 0 && _root.商城已购买物品 === beforePurchased
            && _root.商城已购买物品.length == 1 && _root.testKShopSaveCount == 1,
            "direct checkout clears cart, saves once and does not grow legacy pending claims");
    }

    private static function testExactBalance():Void {
        resetState();
        _root.虚拟币 = 80;
        var preview:Object = requestPreview([{idx:0, qty:2}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        check(preview.canCommit && commit.success && _root.虚拟币 == 0,
            "new checkout permits an exact K-point balance");
    }

    private static function testLargeStackQuantity():Void {
        resetState();
        _root.虚拟币 = 200000;
        var preview:Object = requestPreview([{idx:0, qty:4549}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        check(preview.success && preview.purchaseLines[0].maxQuantity == 999999
            && preview.purchaseLines[0].quantity == 4549 && preview.canCommit,
            "stack purchase accepts large quantities below the technical guard");
        check(commit.success && _root.物品栏.背包.getItem(0).value == 4549
            && _root.虚拟币 == 18040,
            "large stack checkout charges and delivers the exact same quantity");
    }

    private static function testMaterialRouting():Void {
        resetState();
        var preview:Object = requestPreview([{idx:1, qty:3}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        check(commit.success && _root.收集品栏.材料.getValue("强化石") == 3
            && _root.物品栏.背包.getIndexes().length == 0,
            "direct delivery routes materials to the material collection");
    }

    private static function testInformationCommitRefreshesCatalog():Void {
        resetState();
        var preview:Object = requestPreview([{idx:3, qty:1}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        check(commit.success && _root.收集品栏.情报.getValue("测试情报") == 1
            && commit.catalog[3].maxQuantity == 0,
            "successful checkout returns catalog limits from the post-delivery state");
    }

    private static function testInformationCapacityIsZeroWrite():Void {
        resetState();
        _root.收集品栏.情报.add("测试情报", 1);
        var beforeBalance:Number = _root.虚拟币;
        var preview:Object = requestPreview([{idx:3, qty:1}]);
        check(!preview.success && preview.error == "invalid_quantity"
            && _root.虚拟币 == beforeBalance && _root.收集品栏.情报.getValue("测试情报") == 1,
            "full information capacity rejects before charging instead of relying on lossy clamp");
    }

    private static function testLegacyCheckoutUsesAuthority():Void {
        resetState();
        _root.收集品栏.情报.add("测试情报", 1);
        var beforePurchased:Number = _root.商城已购买物品.length;
        callSeq++;
        _root.gameCommands["shopCheckout"]({callId:callSeq, cart:[{idx:3, qty:1}]});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(!response.success && response.error == "invalid_quantity"
            && _root.虚拟币 == 1000 && _root.商城已购买物品.length == beforePurchased
            && _root.testKShopSaveCount == 0,
            "legacy checkout reuses authoritative quantity validation and never charges a full information destination");
    }

    private static function testLegacyCheckoutDirectDelivery():Void {
        resetState();
        _root.虚拟币 = 80;
        var beforePurchased:Number = _root.商城已购买物品.length;
        callSeq++;
        _root.gameCommands["shopCheckout"]({callId:callSeq, cart:[{idx:0, qty:2}]});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        var item:Object = _root.物品栏.背包.getItem(0);
        check(response.success && response.newBalance == 0 && item.name == "药剂" && item.value == 2
            && _root.商城已购买物品.length == beforePurchased && _root.testKShopSaveCount == 1,
            "legacy checkout shares direct delivery, exact-balance and no-new-pending-claim semantics");
    }

    private static function testLegacyInformationClaimIgnoresBagVacancy():Void {
        resetState();
        _root.物品栏.背包 = new ArrayInventory(null, 1);
        _root.物品栏.背包.add(0, BaseItem.create("药剂", 1));
        _root.商城已购买物品 = [["intel", "测试情报", "研究专柜", 100, 1]];
        callSeq++;
        _root.gameCommands["shopClaim"]({
            callId:callSeq,
            purchasedIdx:0,
            expectedPurchasedToken:_root.UI系统.商城WebView.purchasedToken
        });
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.success && _root.收集品栏.情报.getValue("测试情报") == 1
            && _root.商城已购买物品.length == 0 && response.catalog[3].maxQuantity == 0,
            "legacy information claim follows its collection destination instead of requiring an unrelated bag vacancy");
    }

    private static function testInventoryFullIsZeroWrite():Void {
        resetState();
        _root.物品栏.背包 = new ArrayInventory(null, 2);
        _root.物品栏.背包.add(0, BaseItem.create("药剂", 1));
        _root.物品栏.背包.add(1, BaseItem.create("药剂", 1));
        var preview:Object = requestPreview([{idx:2, qty:1}]);
        var token:String = preview.checkoutToken;
        var commit:Object = requestCommit(token);
        check(preview.success && !preview.canCommit && preview.blockingError == "inventory_full"
            && preview.purchaseLines[0].maxByCapacity == 0,
            "full inventory is reported during authoritative preview");
        check(!commit.success && commit.error == "inventory_full" && _root.虚拟币 == 1000
            && _root.testKShopSaveCount == 0 && _root.商城购物车.length == 1,
            "inventory-full commit is a zero-write failure");
    }

    private static function testPriceChangeRejectsCommit():Void {
        resetState();
        var preview:Object = requestPreview([{idx:0, qty:1}]);
        _root.kshop_list[0].price = 41;
        var commit:Object = requestCommit(preview.checkoutToken);
        check(!commit.success && commit.error == "stale_state" && _root.虚拟币 == 1000
            && _root.物品栏.背包.getIndexes().length == 0 && _root.testKShopSaveCount == 0,
            "catalog changes after preview reject commit without writes");
    }

    private static function testTokenReplayRejected():Void {
        resetState();
        var preview:Object = requestPreview([{idx:0, qty:1}]);
        var first:Object = requestCommit(preview.checkoutToken);
        var replay:Object = requestCommit(preview.checkoutToken);
        check(first.success && !replay.success && replay.error == "stale_state"
            && _root.虚拟币 == 960 && _root.testKShopSaveCount == 1,
            "checkout token is single-use and cannot double-charge");
    }

    private static function testMalformedPreviewInvalidatesToken():Void {
        resetState();
        var preview:Object = requestPreview([{idx:0, qty:1}]);
        var malformed:Object = requestPreview([{idx:0, qty:0}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        check(!malformed.success && malformed.error == "invalid_payload"
            && !commit.success && commit.error == "stale_state" && _root.虚拟币 == 1000,
            "a malformed new preview invalidates the previous checkout token");
    }

    private static function requestPreview(cart:Array):Object {
        callSeq++;
        _root.server.sent = null;
        _root.gameCommands["shopCheckoutPreview"]({v:1, callId:callSeq, cart:cart});
        return new LiteJSON().parse(String(_root.server.sent));
    }

    private static function requestCommit(token:String):Object {
        callSeq++;
        _root.server.sent = null;
        _root.gameCommands["shopCheckoutCommit"]({v:1, callId:callSeq, expectedCheckoutToken:token});
        return new LiteJSON().parse(String(_root.server.sent));
    }

    private static function itemData(name:String, type:String, useName:String, price:Number):Object {
        return {name:name, displayname:name, icon:name, type:type, use:useName, price:price, data:{level:1}};
    }

    private static function check(value:Boolean, label:String):Void {
        if (value) {
            passed++;
            trace("[PASS] " + label);
        } else {
            failed++;
            trace("[FAIL] " + label);
        }
    }
}
