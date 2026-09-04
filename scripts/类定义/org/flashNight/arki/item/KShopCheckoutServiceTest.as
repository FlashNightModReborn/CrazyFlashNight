import org.flashNight.aven.test.*;

import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

class org.flashNight.arki.item.KShopCheckoutServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var callSeq:Number = 0;

    public static function runAllTests():Void {
        setup();
        testCatalogProjection();
        testLegacyPurchasedNumericStringProjection();
        testLegacyPurchasedCorruptionFailsClosed();
        testLegacyPurchasedProjectionDoesNotMutateSave();
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
        testCheckoutListenerFaultRestoresExactSnapshot();
        testClaimListenerFaultRestoresExactSnapshot();
        testClaimFlushFailureRestoresAndReturnsCommitPending();
        testClaimFlushThrowRestoresAndReturnsCommitPending();
        testCheckoutFlushFailureRestoresAndReturnsCommitPending();
        testFingerprintVectorsAndSnapshotProjection();
        testSingleClaimFingerprintMismatchIsZeroWrite();
        testSingleClaimUnsupportedVersionIsZeroWrite();
        testClaimBatchSuccessK1K2K40();
        testClaimBatchInvalidEnvelopeZeroWrite();
        testClaimBatchIdentityCollisionFailsClosed();
        testClaimBatchCapacityZeroWriteNoRotation();
        testClaimBatchAcquireFalseRestoresAndReturnsAcquireFailed();
        testClaimBatchListenerFaultRestoresExactSnapshot();
        testClaimBatchReceiptCutRestoresExactSnapshot();
        testClaimBatchFlushFailureRestoresAndReturnsCommitPending();
        testClaimBatchPostFenceProjectionFaultKeepsDurableState();
        testClaimBatchReplayAndConflict();
        testClaimBatchReplayOnlyModes();
        testClaimBatchDuplicateTupleOrdinalRebase();
        testClaimBatchRestartKeepsDurableCut();
        testClaimBatchLaneQuarantineOnlyBlocksBatch();
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
        _root.强制存盘 = function():Boolean { _root.testKShopSaveCount++; return true; };
        // R1 步骤 9：A3 已迁 flushDurableNow，默认 double 镜像到新 shim 入口
        _root.存档系统.flushDurableNow = _root.强制存盘;
    }

    private static function resetState():Void {
        _root.物品栏 = {};
        _root.物品栏.背包 = new ArrayInventory(null, 50);
        _root.物品栏.药剂栏 = new ArrayInventory(null, 8);
        _root.物品栏.仓库 = new ArrayInventory(null, 10);
        _root.物品栏.战备箱 = new ArrayInventory(null, 10);
        _root.收集品栏 = {};
        _root.收集品栏.材料 = new DictCollection(null);
        _root.收集品栏.情报 = new DictCollection(null);
        _root.虚拟币 = 1000;
        _root.商城购物车 = [["legacy-cart"]];
        _root.商城已购买物品 = [["legacy", "药剂", "消耗品", 40, 1]];
        _root.testKShopSaveCount = 0;
        _root._saveExt = {};
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

    private static function testLegacyPurchasedNumericStringProjection():Void {
        resetState();
        _root.商城已购买物品 = [["legacy", "药剂", "消耗品", "200", "29"]];
        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.success && typeof(response.purchased[0][3]) == "number"
            && response.purchased[0][3] == 200
            && typeof(response.purchased[0][4]) == "number"
            && response.purchased[0][4] == 29
            && response.purchasedView[0].quantity == 29,
            "legacy purchased numeric strings are normalized at the AS2 authority boundary");
    }

    private static function testLegacyPurchasedCorruptionFailsClosed():Void {
        var invalidRows:Array = [
            ["legacy", "药剂", "消耗品", "", 1],
            ["legacy", "药剂", "消耗品", "not-a-number", 1],
            ["legacy", "药剂", "消耗品", -1, 1],
            ["legacy", "药剂", "消耗品", "Infinity", 1],
            ["legacy", "药剂", "消耗品", 40, 0],
            ["legacy", "药剂", "消耗品", 40, "1.5"]
        ];
        var allRejected:Boolean = true;
        for (var index:Number = 0; index < invalidRows.length; index++) {
            resetState();
            var row:Array = invalidRows[index];
            _root.商城已购买物品 = [row];
            var originalList:Array = _root.商城已购买物品;
            callSeq++;
            _root.gameCommands["shopBulkQuery"]({callId:callSeq});
            var response:Object = new LiteJSON().parse(String(_root.server.sent));
            allRejected = allRejected && !response.success
                && response.error == "invalid_legacy_purchased"
                && _root.商城已购买物品 === originalList
                && _root.商城已购买物品[0] === row
                && _root.testKShopSaveCount == 0;
        }
        check(allRejected,
            "corrupt legacy purchased values fail closed without save mutation");
    }

    private static function testLegacyPurchasedProjectionDoesNotMutateSave():Void {
        resetState();
        var row:Array = ["legacy", "药剂", "消耗品", "200", "29"];
        _root.商城已购买物品 = [row];
        var originalList:Array = _root.商城已购买物品;
        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.success && _root.商城已购买物品 === originalList
            && _root.商城已购买物品[0] === row
            && typeof row[3] == "string" && row[3] == "200"
            && typeof row[4] == "string" && row[4] == "29"
            && response.purchased[0] !== row && _root.testKShopSaveCount == 0,
            "legacy purchased projection returns a detached snapshot and never rewrites save state");
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
        _root.物品栏.药剂栏.add(7, BaseItem.create("药剂", 3));
        var beforePurchased:Object = _root.商城已购买物品;
        var preview:Object = requestPreview([{idx:0, qty:2}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        var item:Object = _root.物品栏.药剂栏.getItem(7);
        check(preview.success && preview.canCommit && preview.total == 80 && preview.projectedBalance == 920,
            "preview derives authoritative K-point total");
        check(commit.success && commit.newBalance == 920 && item.name == "药剂" && item.value == 5
                && _root.物品栏.背包.getIndexes().length == 0,
            "commit merges directly into the upper potion bank and deducts K points");
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
            v:1,
            purchasedIdx:0,
            expectedPurchasedToken:_root.UI系统.商城WebView.purchasedToken,
            expectedRowFingerprint:FP_INTEL
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

    private static function testCheckoutListenerFaultRestoresExactSnapshot():Void {
        resetState();
        _root.存档系统.dirtyMark = false;
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var preview:Object = requestPreview([{idx:0, qty:1}]);
        var bag:ArrayInventory = _root.物品栏.背包;
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__kshopCheckoutListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        bag.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemAdded", function():Void {
            throw "kshop_checkout_added_listener_failed";
        });

        var fault = null;
        try {
            requestCommit(preview.checkoutToken);
        } catch (error) {
            fault = error;
        }
        check(fault == "kshop_checkout_added_listener_failed"
                && bag.getItem("0") == null && _root.虚拟币 == 1000
                && _root.商城购物车.length == 1
                && _root.存档系统.dirtyMark === false
                && receipts.length == 0
                && PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "KShop checkout listener fault restores delivery/payment/cart/dirty and discards receipt");

        bag.setDispatcher(null);
        var recoveredPreview:Object = requestPreview([{idx:0, qty:1}]);
        var recovered:Object = requestCommit(recoveredPreview.checkoutToken);
        check(recovered.success === true && bag.getItem("0").value == 1
                && _root.虚拟币 == 960 && receipts.length == 1
                && PlayerAssetTransaction.current() == null,
            "KShop checkout listener fault leaves the next independent checkout healthy");
        holder.removeMovieClip();
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimListenerFaultRestoresExactSnapshot():Void {
        resetState();
        _root.存档系统.dirtyMark = false;
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var tokenBefore:String = String(_root.UI系统.商城WebView.purchasedToken);
        var bag:ArrayInventory = _root.物品栏.背包;
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__kshopClaimListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        bag.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemAdded", function():Void {
            throw "kshop_claim_added_listener_failed";
        });
        var params:Object = {
            callId:++callSeq, v:1, purchasedIdx:0, expectedPurchasedToken:tokenBefore,
            expectedRowFingerprint:FP_POTION
        };
        var fault = null;
        try {
            _root.gameCommands["shopClaim"](params);
        } catch (error) {
            fault = error;
        }
        check(fault == "kshop_claim_added_listener_failed"
                && bag.getItem("0") == null
                && _root.商城已购买物品.length == 1
                && String(_root.UI系统.商城WebView.purchasedToken) == tokenBefore
                && _root.存档系统.dirtyMark === false
                && receipts.length == 0
                && PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "KShop claim listener fault restores item/pending/token/dirty and discards receipt");

        bag.setDispatcher(null);
        params.callId = ++callSeq;
        _root.gameCommands["shopClaim"](params);
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.success === true && bag.getItem("0").value == 1
                && _root.商城已购买物品.length == 0
                && receipts.length == 1
                && PlayerAssetTransaction.current() == null,
            "KShop claim listener fault permits one exact retry without duplication");
        holder.removeMovieClip();
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimFlushFailureRestoresAndReturnsCommitPending():Void {
        resetState();
        _root.存档系统.dirtyMark = false;
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var tokenBefore:String = String(_root.UI系统.商城WebView.purchasedToken);
        var saveAttempts:Number = 0;
        var oldFlush:Function = _root.存档系统.flushDurableNow;
        _root.存档系统.flushDurableNow = function(reason):Boolean {
            saveAttempts++;
            _root.testKShopSaveCount++;
            return false;
        };
        var bag:ArrayInventory = _root.物品栏.背包;
        _root.gameCommands["shopClaim"]({
            callId:++callSeq, v:1, purchasedIdx:0, expectedPurchasedToken:tokenBefore,
            expectedRowFingerprint:FP_POTION
        });
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(!response.success && response.error == "commit_pending"
                && response.purchasedToken == tokenBefore
                && bag.getItem("0") == null
                && _root.商城已购买物品.length == 1
                && String(_root.UI系统.商城WebView.purchasedToken) == tokenBefore
                && _root.存档系统.dirtyMark === false
                && receipts.length == 0 && saveAttempts == 1
                && PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "claim flush false restores item/pending/token/dirty, withholds receipt and answers commit_pending");

        _root.存档系统.flushDurableNow = oldFlush;
        _root.gameCommands["shopClaim"]({
            callId:++callSeq, v:1, purchasedIdx:0, expectedPurchasedToken:tokenBefore,
            expectedRowFingerprint:FP_POTION
        });
        var retry:Object = new LiteJSON().parse(String(_root.server.sent));
        check(retry.success === true && bag.getItem("0").value == 1
                && _root.商城已购买物品.length == 0 && receipts.length == 1
                && PlayerAssetTransaction.current() == null,
            "claim commit_pending keeps the same token valid for one exact retry");
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimFlushThrowRestoresAndReturnsCommitPending():Void {
        resetState();
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var tokenBefore:String = String(_root.UI系统.商城WebView.purchasedToken);
        var oldFlush:Function = _root.存档系统.flushDurableNow;
        _root.存档系统.flushDurableNow = function(reason):Boolean { throw "kshop_claim_flush_failed"; return false; };
        _root.gameCommands["shopClaim"]({
            callId:++callSeq, v:1, purchasedIdx:0, expectedPurchasedToken:tokenBefore,
            expectedRowFingerprint:FP_POTION
        });
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        _root.存档系统.flushDurableNow = oldFlush;
        check(!response.success && response.error == "commit_pending"
                && _root.物品栏.背包.getItem("0") == null
                && _root.商城已购买物品.length == 1
                && String(_root.UI系统.商城WebView.purchasedToken) == tokenBefore
                && receipts.length == 0
                && PlayerAssetTransaction.current() == null,
            "claim flush throw is contained by the durable fence and answers commit_pending");
        PlayerAssetTransaction.resetForTests();
    }

    private static function testCheckoutFlushFailureRestoresAndReturnsCommitPending():Void {
        resetState();
        _root.存档系统.dirtyMark = false;
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var preview:Object = requestPreview([{idx:0, qty:2}]);
        var oldFlush:Function = _root.存档系统.flushDurableNow;
        _root.存档系统.flushDurableNow = function(reason):Boolean {
            _root.testKShopSaveCount++;
            return false;
        };
        var commit:Object = requestCommit(preview.checkoutToken);
        _root.存档系统.flushDurableNow = oldFlush;
        check(!commit.success && commit.error == "commit_pending"
                && _root.虚拟币 == 1000 && _root.商城购物车.length == 1
                && _root.物品栏.背包.getIndexes().length == 0
                && _root.存档系统.dirtyMark === false
                && receipts.length == 0 && _root.testKShopSaveCount == 1
                && PlayerAssetTransaction.current() == null,
            "checkout flush false restores delivery/payment/cart/dirty, withholds receipt and answers commit_pending");

        var retryPreview:Object = requestPreview([{idx:0, qty:2}]);
        var retry:Object = requestCommit(retryPreview.checkoutToken);
        check(retry.success === true && _root.虚拟币 == 920
                && _root.物品栏.背包.getItem(0).value == 2
                && receipts.length == 1 && _root.testKShopSaveCount == 2,
            "checkout commit_pending leaves the cart submittable for one exact retry");
        PlayerAssetTransaction.resetForTests();
    }

    // ==================== A② 行指纹 + shopClaimBatch（§7.2 矩阵） ====================
    // 已知答案向量由与 AS2 实现独立的 Node 参考实现交叉生成（双 FNV-1a lane、
    // 逐 UTF-16 code unit 喂 low/high byte）。
    private static var FP_POTION:String = "kpr1.144fe49a5fae01d1.0";
    private static var FP_INTEL:String = "kpr1.f6d429fe932c2121.0";
    private static var FP_POTION29:String = "kpr1.720e3c1c3a59c277.0";

    private static function seedTwoClaimRows():Void {
        resetState();
        _root.商城已购买物品 = [
            ["legacy", "药剂", "消耗品", 40, 1],
            ["intel", "测试情报", "研究专柜", 100, 1]
        ];
    }

    private static function lastResponse():Object {
        return new LiteJSON().parse(String(_root.server.sent));
    }

    private static function currentToken():String {
        return String(_root.UI系统.商城WebView.purchasedToken);
    }

    private static function batchParams(id:String, token:String,
            rows:Array, replayOnly:Boolean):Object {
        callSeq++;
        _root.server.sent = null;
        var params:Object = {callId:callSeq, v:1, batchOperationId:id,
            expectedPurchasedToken:token, rows:rows};
        if (replayOnly) params.replayOnly = true;
        return params;
    }

    private static function claimBatchLane():Object {
        var state:Object =
            org.flashNight.arki.item.KShopLegacyClaimSupport.ensureLane();
        return state.ok ? state.lane : null;
    }

    private static function testFingerprintVectorsAndSnapshotProjection():Void {
        resetState();
        var support = org.flashNight.arki.item.KShopLegacyClaimSupport;
        var canonical:String = support.canonicalTupleString(
            "legacy", "药剂", "消耗品", 40, 1);
        check(canonical == "S6:legacyS2:药剂S3:消耗品N2:40N1:1"
            && support.canonicalTupleDigest(canonical) == "144fe49a5fae01d1"
            && support.canonicalTupleDigest(support.canonicalTupleString(
                "intel", "测试情报", "研究专柜", 100, 1)) == "f6d429fe932c2121"
            && support.canonicalTupleString("a", "b", "", NaN, 1) == null
            && support.canonicalTupleString("a", "b", "", Infinity, 1) == null
            && support.canonicalTupleString("a", "b", "", 1, 0) == null
            && support.canonicalTupleString("a", "b", "", 1, 1.5) == null
            && support.parseRowFingerprint(FP_POTION) != null
            && support.parseRowFingerprint("kpr1.144fe49a5fae01d1.9999") != null
            && support.parseRowFingerprint("kpr1.144fe49a5fae01d1.10000") == null
            && support.parseRowFingerprint("kpr1.144fe49a5fae01d1.01") == null
            && support.parseRowFingerprint("kpr1.144FE49A5FAE01D1.0") == null
            && support.parseRowFingerprint("kpr2.144fe49a5fae01d1.0") == null,
            "row fingerprint canonical framing, dual-lane digest vectors and lexical gates hold");

        _root.商城已购买物品 = [
            ["legacy", "药剂", "消耗品", 40, 1],
            ["legacy", "药剂", "消耗品", 40, 1],
            ["legacy", "药剂", "消耗品", 40, 1]
        ];
        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var bulk:Object = lastResponse();
        check(bulk.success
            && bulk.purchasedView[0].rowFingerprint == "kpr1.144fe49a5fae01d1.0"
            && bulk.purchasedView[1].rowFingerprint == "kpr1.144fe49a5fae01d1.1"
            && bulk.purchasedView[2].rowFingerprint == "kpr1.144fe49a5fae01d1.2"
            && _root.testKShopSaveCount == 0,
            "identical five-tuples project consecutive occurrence ordinals without writes");
    }

    private static function testSingleClaimFingerprintMismatchIsZeroWrite():Void {
        seedTwoClaimRows();
        var tokenBefore:String = currentToken();
        callSeq++;
        _root.gameCommands["shopClaim"]({
            callId:callSeq, v:1, purchasedIdx:0,
            expectedPurchasedToken:tokenBefore,
            expectedRowFingerprint:FP_INTEL
        });
        var rejected:Object = lastResponse();
        check(!rejected.success && rejected.error == "stale_state"
            && _root.商城已购买物品.length == 2
            && _root.testKShopSaveCount == 0
            && currentToken() == tokenBefore,
            "single claim fingerprint mismatch is stale_state with zero write and no rotation");

        callSeq++;
        _root.gameCommands["shopClaim"]({
            callId:callSeq, v:1, purchasedIdx:0,
            expectedPurchasedToken:tokenBefore,
            expectedRowFingerprint:FP_POTION
        });
        var accepted:Object = lastResponse();
        check(accepted.success && _root.商城已购买物品.length == 1
            && accepted.purchasedView[0].rowFingerprint == FP_INTEL
            && _root.testKShopSaveCount == 1
            && accepted.purchasedToken != tokenBefore,
            "single claim v1 exact fingerprint echo claims once with one fence");
    }

    private static function testSingleClaimUnsupportedVersionIsZeroWrite():Void {
        resetState();
        var tokenBefore:String = currentToken();
        callSeq++;
        _root.gameCommands["shopClaim"]({
            callId:callSeq, purchasedIdx:0, expectedPurchasedToken:tokenBefore,
            expectedRowFingerprint:FP_POTION
        });
        var response:Object = lastResponse();
        check(!response.success && response.error == "unsupported_version"
            && _root.商城已购买物品.length == 1
            && _root.testKShopSaveCount == 0
            && currentToken() == tokenBefore,
            "single claim without v1 envelope is rejected before any write");
    }

    private static function testClaimBatchSuccessK1K2K40():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });

        seedTwoClaimRows();
        var requestToken:String = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.test.k1", requestToken, [FP_POTION], false));
        var k1:Object = lastResponse();
        check(k1.success && k1.replayed === false && k1.policy == "atomic"
            && k1.batchOperationId == "kcb.test.k1"
            && k1.committedPurchasedToken == k1.purchasedToken
            && k1.purchasedToken != requestToken
            && k1.resultRows.length == 1
            && k1.resultRows[0].rowFingerprint == FP_POTION
            && k1.resultRows[0].status == "claimed"
            && _root.商城已购买物品.length == 1
            && _root.收集品栏.情报.getValue("测试情报") == 0
            && _root.物品栏.背包.getItem(0).value == 1
            && _root.testKShopSaveCount == 1
            && claimBatchLane().receipts.length == 1
            && receipts.length == 1,
            "claimBatch K=1 fresh success: 1 fence, 1 K receipt, 1 PAT receipt, rotated token");

        seedTwoClaimRows();
        requestToken = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.test.k2", requestToken, [FP_POTION, FP_INTEL], false));
        var k2:Object = lastResponse();
        check(k2.success && k2.resultRows.length == 2
            && k2.resultRows[1].rowFingerprint == FP_INTEL
            && _root.商城已购买物品.length == 0
            && _root.物品栏.背包.getItem(0).value == 1
            && _root.收集品栏.情报.getValue("测试情报") == 1
            && _root.testKShopSaveCount == 1
            && claimBatchLane().receipts.length == 1
            && receipts.length == 2,
            "claimBatch K=2 fresh success: single fence and receipt for the whole batch");

        resetState();
        var rows:Array = [];
        var fingerprints:Array = [];
        for (var i:Number = 0; i < 40; i++) {
            rows.push(["legacy", "药剂", "消耗品", 40, 1]);
            fingerprints.push("kpr1.144fe49a5fae01d1." + i);
        }
        _root.商城已购买物品 = rows;
        requestToken = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.test.k40", requestToken, fingerprints, false));
        var k40:Object = lastResponse();
        check(k40.success && k40.resultRows.length == 40
            && k40.resultRows[39].rowFingerprint == "kpr1.144fe49a5fae01d1.39"
            && _root.商城已购买物品.length == 0
            && _root.物品栏.背包.getItem(0).value == 40
            && _root.testKShopSaveCount == 1
            && claimBatchLane().receipts.length == 1
            && receipts.length == 3,
            "claimBatch K=40 fresh success: ordinal ceiling, one fence, one receipt");
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimBatchInvalidEnvelopeZeroWrite():Void {
        var tokenBefore:String;
        var response:Object;

        seedTwoClaimRows();
        tokenBefore = currentToken();
        var badVersion:Object = batchParams("kcb.bad.v", tokenBefore, [FP_POTION], false);
        badVersion.v = 2;
        _root.gameCommands["shopClaimBatch"](badVersion);
        response = lastResponse();
        check(!response.success && response.error == "unsupported_version"
            && _root.testKShopSaveCount == 0 && currentToken() == tokenBefore
            && _root.商城已购买物品.length == 2,
            "claimBatch unsupported version: zero write, token unchanged");

        seedTwoClaimRows();
        tokenBefore = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("bad id!", tokenBefore, [FP_POTION], false));
        response = lastResponse();
        check(!response.success && response.error == "invalid_operation_id"
            && _root.testKShopSaveCount == 0 && currentToken() == tokenBefore,
            "claimBatch invalid operation id: zero write, token unchanged");

        seedTwoClaimRows();
        tokenBefore = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.bad.token", "bad token!", [FP_POTION], false));
        response = lastResponse();
        check(!response.success && response.error == "invalid_payload"
            && _root.testKShopSaveCount == 0 && currentToken() == tokenBefore,
            "claimBatch malformed token: zero write, token unchanged");

        seedTwoClaimRows();
        tokenBefore = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.bad.unknown", tokenBefore, ["kpr1.00000000000000ff.0"], false));
        response = lastResponse();
        check(!response.success && response.error == "unknown_row"
            && _root.testKShopSaveCount == 0 && currentToken() == tokenBefore
            && claimBatchLane().receipts.length == 0,
            "claimBatch unknown fingerprint: zero write, zero receipt, token unchanged");

        seedTwoClaimRows();
        tokenBefore = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.bad.dup", tokenBefore, [FP_POTION, FP_POTION], false));
        response = lastResponse();
        check(!response.success && response.error == "row_duplicate"
            && _root.testKShopSaveCount == 0 && currentToken() == tokenBefore,
            "claimBatch duplicate fingerprint: zero write, token unchanged");

        seedTwoClaimRows();
        tokenBefore = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.bad.order", tokenBefore, [FP_INTEL, FP_POTION], false));
        response = lastResponse();
        check(!response.success && response.error == "row_order_invalid"
            && _root.testKShopSaveCount == 0 && currentToken() == tokenBefore,
            "claimBatch non-increasing snapshot order: zero write, never silently sorted");

        seedTwoClaimRows();
        tokenBefore = currentToken();
        var support = org.flashNight.arki.item.KShopLegacyClaimSupport;
        var lane:Object = claimBatchLane();
        for (var fillIndex:Number = 0; fillIndex < support.MAX_RECEIPTS; fillIndex++) {
            lane.receipts.push(support.buildReceipt("kcb.fill." + fillIndex,
                "shop.fill", ["kpr1.0000000000000000.0"], "shop.fill.2"));
        }
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.bad.full", tokenBefore, [FP_POTION], false));
        response = lastResponse();
        check(!response.success && response.error == "batch_receipt_ledger_full"
            && _root.testKShopSaveCount == 0 && currentToken() == tokenBefore
            && lane.receipts.length == support.MAX_RECEIPTS
            && _root.商城已购买物品.length == 2
            && _root.物品栏.背包.getIndexes().length == 0,
            "claimBatch full receipt lane: fail-closed without FIFO eviction, single claim unaffected");
    }

    private static function testClaimBatchIdentityCollisionFailsClosed():Void {
        seedTwoClaimRows();
        var tokenBefore:String = currentToken();
        // 合成碰撞：常数 digest 让两个不同五元组共享 digest base，只能 fail-closed。
        var supportClass:Object = org.flashNight.arki.item.KShopLegacyClaimSupport;
        var oldDigest:Function = supportClass.canonicalTupleDigest;
        supportClass.canonicalTupleDigest = function(canonical:String):String {
            return "00000000000000000000000000000000";
        };
        callSeq++;
        _root.server.sent = null;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var bulk:Object = lastResponse();
        // bulkQuery 入口即铸新 token；batch 的 expected token 必须取 bulk 之后的当前值，
        // 否则撞上的是 stale_state 而非碰撞 fail-closed。
        tokenBefore = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.collision.batch", tokenBefore, [FP_POTION], false));
        var batch:Object = lastResponse();
        supportClass.canonicalTupleDigest = oldDigest;
        check(!bulk.success && bulk.error == "purchased_identity_collision"
            && !batch.success && batch.error == "purchased_identity_collision"
            && _root.testKShopSaveCount == 0
            && currentToken() == tokenBefore
            && _root.商城已购买物品.length == 2
            && claimBatchLane().receipts.length == 0,
            "digest collision across distinct tuples fails closed every projection, zero write");
    }

    private static function testClaimBatchCapacityZeroWriteNoRotation():Void {
        seedTwoClaimRows();
        _root.物品栏.背包 = new ArrayInventory(null, 1);
        _root.物品栏.背包.add(0, BaseItem.create("测试手枪", 1));
        // 药剂栏容量 0：同名药剂才有处可合并的误布景变成真实 inventory_full。
        _root.物品栏.药剂栏 = new ArrayInventory(null, 0);
        var tokenBefore:String = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.capacity.bag", tokenBefore, [FP_POTION], false));
        var bagFull:Object = lastResponse();
        check(!bagFull.success && bagFull.error == "inventory_full"
            && _root.商城已购买物品.length == 2
            && _root.testKShopSaveCount == 0
            && currentToken() == tokenBefore
            && claimBatchLane().receipts.length == 0
            && _root.物品栏.背包.getItem(0).name == "测试手枪",
            "claimBatch capacity shortfall: whole batch zero write and token NOT rotated");

        seedTwoClaimRows();
        _root.收集品栏.情报.add("测试情报", 1);
        tokenBefore = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.capacity.intel", tokenBefore, [FP_INTEL], false));
        var intelFull:Object = lastResponse();
        check(!intelFull.success && intelFull.error == "destination_full"
            && _root.商城已购买物品.length == 2
            && _root.testKShopSaveCount == 0
            && currentToken() == tokenBefore
            && claimBatchLane().receipts.length == 0,
            "claimBatch information destination full: zero write, token unchanged");
    }

    private static function testClaimBatchAcquireFalseRestoresAndReturnsAcquireFailed():Void {
        seedTwoClaimRows();
        _root.存档系统.dirtyMark = false;
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var tokenBefore:String = currentToken();
        // 经 Object 别名替换类静态方法，绕过 CS6 对方法槽赋值的严格类型检查。
        var itemUtilClass:Object = org.flashNight.arki.item.ItemUtil;
        var oldAcquire:Function = itemUtilClass.acquire;
        var acquireCalls:Number = 0;
        itemUtilClass.acquire = function(items:Array, context:Object):Boolean {
            acquireCalls++;
            return false;
        };
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.acquire.false", tokenBefore, [FP_POTION, FP_INTEL], false));
        itemUtilClass.acquire = oldAcquire;
        var response:Object = lastResponse();
        check(!response.success && response.error == "acquire_failed"
            && acquireCalls == 1
            && response.purchasedToken == tokenBefore
            && currentToken() == tokenBefore
            && _root.商城已购买物品.length == 2
            && _root.物品栏.背包.getIndexes().length == 0
            && _root.收集品栏.情报.getValue("测试情报") == 0
            && _root.存档系统.dirtyMark === false
            && claimBatchLane().receipts.length == 0
            && receipts.length == 0
            && _root.testKShopSaveCount == 0
            && PlayerAssetTransaction.current() == null,
            "claimBatch aggregate acquire false: exact restore incl. token, definitive acquire_failed");
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimBatchListenerFaultRestoresExactSnapshot():Void {
        seedTwoClaimRows();
        _root.存档系统.dirtyMark = false;
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var tokenBefore:String = currentToken();
        var bag:ArrayInventory = _root.物品栏.背包;
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__kshopBatchListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        bag.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemAdded", function():Void {
            throw "kshop_batch_added_listener_failed";
        });
        var fault = null;
        try {
            _root.gameCommands["shopClaimBatch"](
                batchParams("kcb.listener.fault", tokenBefore, [FP_POTION], false));
        } catch (error) {
            fault = error;
        }
        check(fault == "kshop_batch_added_listener_failed"
            && bag.getItem("0") == null
            && _root.商城已购买物品.length == 2
            && currentToken() == tokenBefore
            && _root.存档系统.dirtyMark === false
            && claimBatchLane().receipts.length == 0
            && receipts.length == 0
            && _root.testKShopSaveCount == 0
            && PlayerAssetTransaction.current() == null
            && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "claimBatch acquire-cut listener fault: assets/list/token/lane/dirty exact restore");

        bag.setDispatcher(null);
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.listener.retry", tokenBefore, [FP_POTION], false));
        var retry:Object = lastResponse();
        check(retry.success === true && bag.getItem("0").value == 1
            && _root.商城已购买物品.length == 1
            && receipts.length == 1
            && PlayerAssetTransaction.current() == null,
            "claimBatch listener fault leaves the next independent batch healthy");
        holder.removeMovieClip();
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimBatchReceiptCutRestoresExactSnapshot():Void {
        seedTwoClaimRows();
        _root.存档系统.dirtyMark = false;
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var tokenBefore:String = currentToken();
        var support = org.flashNight.arki.item.KShopLegacyClaimSupport;
        var supportClass:Object = support;
        var oldRecord:Function = supportClass.recordReceipt;
        supportClass.recordReceipt = function(lane:Object, receipt:Object):Boolean {
            throw "kshop_batch_receipt_cut";
            return false;
        };
        var fault = null;
        try {
            _root.gameCommands["shopClaimBatch"](
                batchParams("kcb.receipt.cut", tokenBefore, [FP_POTION], false));
        } catch (error) {
            fault = error;
        }
        supportClass.recordReceipt = oldRecord;
        check(fault == "kshop_batch_receipt_cut"
            && _root.物品栏.背包.getIndexes().length == 0
            && _root.商城已购买物品.length == 2
            && currentToken() == tokenBefore
            && _root.存档系统.dirtyMark === false
            && claimBatchLane().receipts.length == 0
            && receipts.length == 0
            && _root.testKShopSaveCount == 0
            && PlayerAssetTransaction.current() == null,
            "claimBatch receipt-append cut: assets/list/token/lane/dirty exact restore, zero fence");
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimBatchFlushFailureRestoresAndReturnsCommitPending():Void {
        seedTwoClaimRows();
        _root.存档系统.dirtyMark = false;
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var tokenBefore:String = currentToken();
        var saveAttempts:Number = 0;
        var oldFlush:Function = _root.存档系统.flushDurableNow;
        _root.存档系统.flushDurableNow = function(reason):Boolean {
            saveAttempts++;
            _root.testKShopSaveCount++;
            return false;
        };
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.flush.false", tokenBefore, [FP_POTION, FP_INTEL], false));
        var response:Object = lastResponse();
        check(!response.success && response.error == "commit_pending"
            && response.purchasedToken == tokenBefore
            && _root.物品栏.背包.getIndexes().length == 0
            && _root.收集品栏.情报.getValue("测试情报") == 0
            && _root.商城已购买物品.length == 2
            && currentToken() == tokenBefore
            && _root.存档系统.dirtyMark === false
            && claimBatchLane().receipts.length == 0
            && receipts.length == 0 && saveAttempts == 1
            && PlayerAssetTransaction.current() == null
            && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "claimBatch fence false: one attempt, zero receipts, exact restore, commit_pending");

        _root.存档系统.flushDurableNow = function(reason):Boolean {
            saveAttempts++;
            throw "kshop_batch_flush_failed";
            return false;
        };
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.flush.throw", tokenBefore, [FP_POTION], false));
        var thrown:Object = lastResponse();
        _root.存档系统.flushDurableNow = oldFlush;
        check(!thrown.success && thrown.error == "commit_pending"
            && _root.商城已购买物品.length == 2
            && currentToken() == tokenBefore
            && claimBatchLane().receipts.length == 0
            && receipts.length == 0 && saveAttempts == 2
            && PlayerAssetTransaction.current() == null,
            "claimBatch fence throw is contained by the durable fence and answers commit_pending");
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimBatchPostFenceProjectionFaultKeepsDurableState():Void {
        seedTwoClaimRows();
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var tokenBefore:String = currentToken();
        var oldCatalog:Function = _root.UI系统.商城WebView.buildCatalog;
        _root.UI系统.商城WebView.buildCatalog = function():Array {
            throw "kshop_batch_catalog_failed";
            return null;
        };
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.postfence.fault", tokenBefore, [FP_POTION], false));
        var response:Object = lastResponse();
        _root.UI系统.商城WebView.buildCatalog = oldCatalog;
        check(response.success === true && response.refreshDeferred === true
            && response.replayed === false
            && _root.商城已购买物品.length == 1
            && _root.物品栏.背包.getItem(0).value == 1
            && currentToken() != tokenBefore
            && claimBatchLane().receipts.length == 1
            && receipts.length == 1
            && _root.testKShopSaveCount == 1
            && PlayerAssetTransaction.current() == null,
            "claimBatch post-fence projection fault: durable state kept, degrades to refreshDeferred");
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimBatchReplayAndConflict():Void {
        seedTwoClaimRows();
        var requestToken:String = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.replay.base", requestToken, [FP_POTION, FP_INTEL], false));
        var first:Object = lastResponse();
        var savesAfterFirst:Number = _root.testKShopSaveCount;

        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.replay.base", requestToken, [FP_POTION, FP_INTEL], false));
        var replay:Object = lastResponse();
        check(first.success && replay.success && replay.replayed === true
            && replay.committedPurchasedToken == first.committedPurchasedToken
            && replay.purchasedToken == currentToken()
            && replay.resultRows.length == 2
            && replay.resultRows[0].rowFingerprint == FP_POTION
            && _root.商城已购买物品.length == 0
            && _root.testKShopSaveCount == savesAfterFirst
            && claimBatchLane().receipts.length == 1,
            "same id + exact request: replayed first immutable result, zero fence, zero rotation");

        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.replay.base", requestToken, [FP_POTION], false));
        var conflictRows:Object = lastResponse();
        check(!conflictRows.success && conflictRows.error == "operation_conflict"
            && _root.testKShopSaveCount == savesAfterFirst
            && _root.商城已购买物品.length == 0,
            "same id + different rows: operation_conflict, zero fence");

        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.replay.base", currentToken(), [FP_POTION, FP_INTEL], false));
        var conflictToken:Object = lastResponse();
        check(!conflictToken.success && conflictToken.error == "operation_conflict"
            && _root.testKShopSaveCount == savesAfterFirst,
            "same id + different token: operation_conflict, zero fence");
    }

    private static function testClaimBatchReplayOnlyModes():Void {
        seedTwoClaimRows();
        var requestToken:String = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.replayonly.miss", "shop.old.epoch", [FP_POTION], true));
        var miss:Object = lastResponse();
        check(!miss.success && miss.error == "stale_state"
            && _root.testKShopSaveCount == 0
            && currentToken() == requestToken
            && _root.商城已购买物品.length == 2
            && _root.物品栏.背包.getIndexes().length == 0,
            "replayOnly without prior receipt: stale_state, zero write and zero fence");

        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.replayonly.base", requestToken, [FP_POTION], false));
        var first:Object = lastResponse();
        var savesAfterFirst:Number = _root.testKShopSaveCount;
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.replayonly.base", requestToken, [FP_POTION], true));
        var replay:Object = lastResponse();
        check(first.success && replay.success && replay.replayed === true
            && replay.committedPurchasedToken == first.committedPurchasedToken
            && _root.testKShopSaveCount == savesAfterFirst
            && claimBatchLane().receipts.length == 1,
            "replayOnly with prior receipt: exact replay, zero write");

        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.replayonly.base", requestToken, [FP_INTEL], true));
        var conflict:Object = lastResponse();
        check(!conflict.success && conflict.error == "operation_conflict"
            && _root.testKShopSaveCount == savesAfterFirst,
            "replayOnly same id + different rows: operation_conflict, zero fence");
    }

    private static function testClaimBatchDuplicateTupleOrdinalRebase():Void {
        resetState();
        _root.商城已购买物品 = [
            ["legacy", "药剂", "消耗品", 40, 1],
            ["legacy", "药剂", "消耗品", 40, 1],
            ["legacy", "药剂", "消耗品", 40, 1]
        ];
        var requestToken:String = currentToken();
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.rebase.batch", requestToken,
                ["kpr1.144fe49a5fae01d1.0", "kpr1.144fe49a5fae01d1.1"], false));
        var batch:Object = lastResponse();
        check(batch.success && _root.商城已购买物品.length == 1
            && batch.purchasedView[0].rowFingerprint == "kpr1.144fe49a5fae01d1.0"
            && batch.purchased.length == 1,
            "claiming earlier duplicates rebases survivor ordinal in the new token epoch");

        callSeq++;
        _root.gameCommands["shopClaim"]({
            callId:callSeq, v:1, purchasedIdx:0,
            expectedPurchasedToken:currentToken(),
            expectedRowFingerprint:"kpr1.144fe49a5fae01d1.2"
        });
        var stale:Object = lastResponse();
        check(!stale.success && stale.error == "stale_state"
            && _root.商城已购买物品.length == 1,
            "old-epoch ordinal fingerprint cannot claim the rebased row");

        callSeq++;
        _root.gameCommands["shopClaim"]({
            callId:callSeq, v:1, purchasedIdx:0,
            expectedPurchasedToken:currentToken(),
            expectedRowFingerprint:"kpr1.144fe49a5fae01d1.0"
        });
        var claimed:Object = lastResponse();
        check(claimed.success && _root.商城已购买物品.length == 0
            && _root.物品栏.背包.getItem(0).value == 3,
            "rebased fingerprint claims the survivor exactly once");
    }

    private static function captureKshopSaveImage():Void {
        var image:Object = {
            saveExt:_root._saveExt,
            purchased:_root.商城已购买物品,
            bag:_root.物品栏.背包.toObject(),
            information:_root.收集品栏.情报.toObject()
        };
        _root.__kshopSaveWire = new LiteJSON().stringifySafe(image);
    }

    private static function restartFromKshopSaveImage():Void {
        var image:Object = new LiteJSON().parse(String(_root.__kshopSaveWire));
        _root._saveExt = image.saveExt;
        _root.商城已购买物品 = image.purchased;
        _root.物品栏.背包 = new ArrayInventory(image.bag, 50);
        _root.收集品栏.情报 = new DictCollection(image.information);
        // 进程重启后 runtime token 丢失；新 epoch 由重新铸 token 模拟。
        _root.UI系统.商城WebView.rotatePurchasedToken();
    }

    private static function testClaimBatchRestartKeepsDurableCut():Void {
        seedTwoClaimRows();
        PlayerAssetTransaction.resetForTests();
        var requestToken:String = currentToken();
        var oldFlush:Function = _root.存档系统.flushDurableNow;
        _root.存档系统.flushDurableNow = function(reason):Boolean {
            _root.testKShopSaveCount++;
            captureKshopSaveImage();
            return true;
        };
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.restart.base", requestToken, [FP_POTION, FP_INTEL], false));
        var first:Object = lastResponse();
        var savesAfterFirst:Number = _root.testKShopSaveCount;

        // 成功回包丢失 → 真实 save-image 重启（JSON wire 往返，非进程内 reset）。
        restartFromKshopSaveImage();
        var support = org.flashNight.arki.item.KShopLegacyClaimSupport;
        var laneState:Object = support.ensureLane();
        var receipt:Object = laneState.ok
            ? support.lookupReceipt(laneState.lane, "kcb.restart.base") : null;
        callSeq++;
        _root.server.sent = null;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var bulk:Object = lastResponse();
        check(first.success && receipt != null
            && receipt.committedPurchasedToken == first.committedPurchasedToken
            && _root.商城已购买物品.length == 0
            && _root.物品栏.背包.getItem(0).value == 1
            && _root.收集品栏.情报.getValue("测试情报") == 1
            && bulk.success && bulk.purchased.length == 0,
            "restart from durable save image shows only the atomic {0,K}=K cut, never a partial batch");

        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.restart.base", requestToken, [FP_POTION, FP_INTEL], false));
        var replay:Object = lastResponse();
        _root.存档系统.flushDurableNow = oldFlush;
        check(replay.success && replay.replayed === true
            && replay.committedPurchasedToken == first.committedPurchasedToken
            && _root.testKShopSaveCount == savesAfterFirst
            && _root.商城已购买物品.length == 0,
            "same-id request after restart replays the persisted receipt without another fence");
        PlayerAssetTransaction.resetForTests();
    }

    private static function testClaimBatchLaneQuarantineOnlyBlocksBatch():Void {
        seedTwoClaimRows();
        var requestToken:String = currentToken();
        _root._saveExt.kshopClaimBatch = {v:2, receipts:[]};
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.quarantine.future", requestToken, [FP_POTION], false));
        var future:Object = lastResponse();
        _root._saveExt.kshopClaimBatch = {v:1, receipts:[{broken:true}]};
        _root.gameCommands["shopClaimBatch"](
            batchParams("kcb.quarantine.malformed", requestToken, [FP_POTION], false));
        var malformed:Object = lastResponse();
        check(!future.success && future.error == "batch_lane_quarantined"
            && !malformed.success && malformed.error == "batch_lane_quarantined"
            && _root.testKShopSaveCount == 0
            && currentToken() == requestToken
            && _root.商城已购买物品.length == 2,
            "future/malformed lane quarantines only the batch capability, zero write");

        callSeq++;
        _root.gameCommands["shopBulkQuery"]({callId:callSeq});
        var bulk:Object = lastResponse();
        var preview:Object = requestPreview([{idx:0, qty:1}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        callSeq++;
        _root.gameCommands["shopClaim"]({
            callId:callSeq, v:1, purchasedIdx:0,
            expectedPurchasedToken:currentToken(),
            expectedRowFingerprint:FP_POTION
        });
        var claim:Object = lastResponse();
        check(bulk.success && commit.success && claim.success
            && _root.商城已购买物品.length == 1
            && _root.testKShopSaveCount == 2,
            "quarantined lane does not block bulkQuery, checkout or single claim");
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
