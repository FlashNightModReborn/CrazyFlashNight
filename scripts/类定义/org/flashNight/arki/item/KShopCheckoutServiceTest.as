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
        testDirectDelivery();
        testExactBalance();
        testMaterialRouting();
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
        itemDict["测试手枪"].weapontype = "手枪";
        ItemUtil.itemDataDict = itemDict;
        ItemUtil.equipmentDict = {};
        ItemUtil.equipmentDict["测试手枪"] = true;
        ItemUtil.materialDict = {};
        ItemUtil.materialDict["强化石"] = true;
        ItemUtil.informationMaxValueDict = {};

        _root.kshop_list = [
            {id:"potion", item:"药剂", type:"消耗品", price:40},
            {id:"material", item:"强化石", type:"收集品", price:25},
            {id:"pistol", item:"测试手枪", type:"武器", price:500}
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
        _root.kshop_list[0].price = 40;
        _root.server.sent = null;
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

    private static function testMaterialRouting():Void {
        resetState();
        var preview:Object = requestPreview([{idx:1, qty:3}]);
        var commit:Object = requestCommit(preview.checkoutToken);
        check(commit.success && _root.收集品栏.材料.getValue("强化石") == 3
            && _root.物品栏.背包.getIndexes().length == 0,
            "direct delivery routes materials to the material collection");
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
